#!/usr/bin/lua

local Dataspace = {}

local SIZED_START = 0x8000
local UNSIZED_START = 0xFA00

function Dataspace:new()
  local dataspace = {
    latest = 0,
    here = SIZED_START,
    hereLabel = nil,
    unsizedHere = UNSIZED_START,
  }
  setmetatable(dataspace, self)
  self.__index = self
  return dataspace
end

function Dataspace.formatAddr(addr)
  return string.format("$%04X", addr)
end

function Dataspace:print(file)
  local i = SIZED_START
  while i < self.here do
    local v = self[i]
    file:write(string.format("%s: %s\n", Dataspace.formatAddr(i), v:toString(self, i)))
    assert(v:size())
    i = i + v:size()
  end
end

function Dataspace:assembly(file)
  -- TODO: Maybe assert that the current address is where we think we are?
  file:write([[
  .segment "CODE"
  ]])

  local i = SIZED_START
  while i < self.here do
    local v = self[i]
    if v.label then
      file:write(string.format("%s:\n", v.label))
    end
    file:write(v:asm(self, i) .. "\n")
    assert(v:size())
    i = i + v:size()
  end

  file:write(".segment \"UNSIZED\"\n\n")

  for i=UNSIZED_START,self.unsizedHere-1 do
    local v = self[i]
    if v.label then
      file:write(string.format("%s:\n", v.label))
    end
    file:write(v:asm(self, i) .. "\n")
  end
end

-- Message should include a %s where the addr should be input.
function Dataspace:assertAddr(dumpFile, cond, message, addr)
  if not cond then
    print("Dumping dataspace.")
    self:print(dumpFile)
    assert(nil, string.format(message, Dataspace.formatAddr(addr)))
  end
end

-- Set the label for HERE.
-- Because HERE doesn't yet have an entry, we store this label temporarily until
-- something is added at HERE.
-- TODO: Is there a cleaner way of doing this? Maybe keeping a list of labels ->
-- addresses somewhere?
function Dataspace:labelHere(label)
  self.hereLabel = label
end

function Dataspace:add(entry)
  assert(entry:size())
  local addr = self.here
  if self.hereLabel then
    entry.label = self.hereLabel
    self.hereLabel = nil
  end
  self[self.here] = entry
  self.here = self.here + 1
  return addr
end

function Dataspace:addUnsized(entry)
  local addr = self.unsizedHere
  self[self.unsizedHere] = entry
  self.unsizedHere = self.unsizedHere + 1
  return addr
end

function Dataspace.defaultLabel(name)
  return "_" .. string.gsub(name, "%W", "_")
end

-- Takes a (potentially partially initiated) native definition.
-- TODO: Maybe we can also support inlining by specifying an `inline` field
-- that, if specified, overrides the Forth word call and instead causes code to
-- be added directly. e.g. LIT would be
--   lda #LITERAL_NUM
--   PUSH_A
-- instead of the usual
--   JSL LIT
--   .WORD LITERNAL_NUM
-- which is a lot slower.
function Dataspace.native(entry)
  entry.type = "native"
  if not entry.asm then
    function entry:asm(dataspace)
      return string.format([[
        jsl not_implemented ; TODO: Not implemented
      ]])
    end
  end
  if not entry.size then
    function entry:size() return nil end
  end
  if not entry.toString then
    function entry:toString(dataspace, opAddr)
      return "Native: " .. self.name
    end
  end
  return entry
end

-- TODO: Should this take an address instead? And resolve at asm time?
function Dataspace.labelWord(label)
  local entry = {
    type = "label-word",
    size = function(self) return 2 end,
    label = label,
  }
  function entry:toString(dataspace, opAddr)
    local name = dataspace:addrName(self.addr)
    if not name then
      return string.format("Label: %d without name", self.addr)
    end
    return string.format("XT: %d %s", self.addr, name)
  end
  function entry:asm(dataspace)
    local label = dataspace:addrLabel(self.addr)
    if not label then
      return nil
    end
    return string.format(".WORD %s", label)
  end
  return entry
end

-- Input: lua dataspace addressing
-- Returns: SNES delta
function Dataspace:getRelativeAddr(current, to)
  if current > to then
    return -self:getRelativeAddr(to, current)
  end

  local delta = 0
  while current < to do
    local size = self[current]:size()
    assert(size, "Couldn't get size of " .. self[current]:toString(self, current))
    delta = delta + size
    current = current + 1
  end
  return delta
end

-- Input: Lua address and SNES address space delta
-- Returns: Lua address
function Dataspace:fromRelativeAddress(current, delta)
  local original = current
  if delta >= 0 then
    while delta > 0 do
      local size = self[current]:size()
      assert(size, "Couldn't get size of " .. self[current]:toString(self, current))
      delta = delta - size
      current = current + 1
    end
  else
    while delta < 0 do
      current = current - 1
      local size = self[current]:size()
      assert(size, "Couldn't get size of " .. self[current]:toString(self, current))
      delta = delta + size
    end
  end
  assert(delta == 0, "Delta was not zero from: " .. original)
  return current
end

-- Input: Two lua adddresses
-- Returns: SNES address-space delta
function Dataspace:toRelativeAddress(from, to)
  local current = from
  local delta = 0
  if current <= to then
    while current < to do
      local size = self[current]:size()
      assert(size, "Couldn't get size of " .. self[current]:toString(self, current))
      delta = delta + size
      current = current + 1
    end
  else
    while current > to do
      current = current - 1
      local size = self[current]:size()
      assert(size, "Couldn't get size of " .. self[current]:toString(self, current))
      delta = delta - size
    end
  end
  return delta
end

function Dataspace.byte(byte)
  assert(byte >= 0 and byte <= 0xFF)
  local entry = {
    type = "byte",
    size = function(self) return 1 end,
    byte = byte & 0xFF,
  }
  function entry:toString(dataspace, opAddr)
    return string.format("Byte: 0x%02X", self.byte)
  end
  function entry:asm(dataspace)
    return string.format(".byte $%02X", self.byte & 0xFF)
  end
  return entry
end

local function lowByte(value)
  return value & 0xFF
end

local function highByte(value)
  return (value >> 8) & 0xFF
end

local function bankByte(value)
  return (value >> 16) & 0xFF
end

function Dataspace:getByte(addr)
  self:assertAddr(io.stderr, addr >= 0 and addr < self.here, "Invalid addr %s", addr)
  self:assertAddr(io.stderr, self[addr].type == "byte", "Expected byte at %s", addr)
  return self[addr].byte
end

function Dataspace:setByte(addr, value)
  self:assertAddr(io.stderr, addr >= 0 and addr < self.here, "Invalid addr %s", addr)
  self:assertAddr(io.stderr, self[addr].type == "byte" and self[addr]:size() == 1, "Expected byte at %s", addr)
  self[addr] = Dataspace.byte(value)
end

function Dataspace:getWord(addr)
  return self:getByte(addr) | (self:getByte(addr + 1) << 8)
end

function Dataspace:setWord(addr, value)
  assert(value <= 0xFFFF, "Invalid word " .. value)
  self:setByte(addr, lowByte(value))
  self:setByte(addr + 1, highByte(value))
end

function Dataspace:getAddr(addr)
  return self:getByte(addr) | (self:getByte(addr + 1) << 8) | (self:getByte(addr + 2) << 16)
end

function Dataspace:addByte(byte)
  self:add(Dataspace.byte(byte))
end

function Dataspace:addWord(number)
  assert(number >= 0 and number <= 0xFFFF)
  self:addByte(lowByte(number))
  self:addByte(highByte(number))
end

-- Convenience methods.
-- TODO: Can maybe add size hints to the first byte of multi-byte data? So we
-- can pretty print it.
function Dataspace:addAddress(addr)
  assert(addr >= 0 and addr <= 0xFFFFFF)
  self:addByte(lowByte(addr))
  self:addByte(highByte(addr))
  self:addByte(bankByte(addr))
end

function Dataspace:allotBytes(bytes)
  assert(bytes > 0)
  for i=1,bytes do
    self:addByte(0)
  end
end

return Dataspace
