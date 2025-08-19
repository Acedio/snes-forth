#!/usr/bin/lua

local Dataspace = {}

-- First 0x2000 bytes of RAM, accessible from every bank from 0 to 0x3F.
Dataspace.LOWRAM_BANK = 0xFFFF

function Dataspace:new()
  local dataspace = {
    codeBank = 0,
    dataBank = 0,
    banks = {
      [0] = {
        SIZED_START = 0x8000,
        here = 0x8000,
        UNSIZED_START = 0xFA00,
        unsizedHere = 0xFA00,
        hereLabel = nil,
        segment = "CODE",
      },
      [Dataspace.LOWRAM_BANK] = {
        SIZED_START = 0x300,
        here = 0x300,
        UNSIZED_START = 0x1900,
        unsizedHere = 0x1900,
        hereLabel = nil,
        segment = "BSS",
      },
    },
  }
  setmetatable(dataspace, self)
  self.__index = self
  return dataspace
end

function Dataspace.formatAddr(addr)
  return string.format("$%04X", addr)
end

-- TODO: Print all banks?
function Dataspace:print(file)
  local i = self.banks[self.codeBank].SIZED_START
  while i < self:getCodeHere() do
    local v = self[i]
    file:write(string.format("%s: %s\n", Dataspace.formatAddr(i), v:toString(self, i)))
    assert(v:size())
    i = i + v:size()
  end
end

function Dataspace:assembly(file)
  for index,bankInfo in pairs(self.banks) do
    file:write(string.format([[
    .segment "%s"
    ]], bankInfo.segment))

    -- TODO: Maybe assert that the current address is where we think we are?
    local i = bankInfo.SIZED_START
    while i < bankInfo.here do
      local v = self[i]
      if v.label then
        file:write(string.format("%s:\n", v.label))
      end
      file:write(v:asm(self, i) .. "\n")
      assert(v:size())
      i = i + v:size()
    end

    -- TODO: There should be one UNSIZED segment per bank.
    file:write(".segment \"UNSIZED\"\n\n")

    for i=bankInfo.UNSIZED_START,bankInfo.unsizedHere-1 do
      local v = self[i]
      if v.label then
        file:write(string.format("%s:\n", v.label))
      end
      file:write(v:asm(self, i) .. "\n")
    end
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

function Dataspace:getCodeBank()
  return self.codeBank
end

function Dataspace:setCodeBank(bank)
  self.codeBank = bank
end

function Dataspace:getDataBank()
  return self.dataBank
end

function Dataspace:setDataBank(bank)
  self.dataBank = bank
end

function Dataspace:getCodeHere()
  return self.banks[self.codeBank].here
end

function Dataspace:getDataHere()
  return self.banks[self.dataBank].here
end

function Dataspace:setCodeHere(val)
  self.banks[self.codeBank].here = val
end

function Dataspace:setDataHere(val)
  self.banks[self.dataBank].here = val
end

-- Set the label for HERE.
-- Because HERE doesn't yet have an entry, we store this label temporarily until
-- something is added at HERE.
-- TODO: Is there a cleaner way of doing this? Maybe keeping a list of labels ->
-- addresses somewhere?
function Dataspace:labelCodeHere(label)
  self.hereLabel = label
end

function Dataspace:add(entry)
  assert(entry:size())
  local addr = self:getDataHere()
  -- TODO: Do we need a dataspace hereLabel?
  self[self:getDataHere()] = entry
  self:setDataHere(self:getDataHere() + 1)
  return addr
end

function Dataspace:compile(entry)
  assert(entry:size())
  local addr = self:getCodeHere()
  if self.hereLabel then
    entry.label = self.hereLabel
    self.hereLabel = nil
  end
  self[self:getCodeHere()] = entry
  self:setCodeHere(self:getCodeHere() + 1)
  return addr
end

function Dataspace:compileUnsized(entry)
  local addr = self.banks[self.codeBank].unsizedHere
  self[self.banks[self.codeBank].unsizedHere] = entry
  self.banks[self.codeBank].unsizedHere = self.banks[self.codeBank].unsizedHere + 1
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

-- TODO: Now that we're mimicking SNES addressing in Lua these aren't really
-- needed, but maybe handy keep around for error checking.
-- TODO: Add error checking to ensure all intervening cells have a size.
-- Input: lua dataspace addressing
-- Returns: SNES delta
function Dataspace:getRelativeAddr(from, to)
  return to - from
end

-- Input: Lua address and SNES address space delta
-- Returns: Lua address
function Dataspace:fromRelativeAddress(current, delta)
  return current + delta
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
  -- TODO: Implement banking for this and setByte.
  self:assertAddr(io.stderr, self[addr].type == "byte", "Expected byte at %s", addr)
  return self[addr].byte
end

function Dataspace:setByte(addr, value)
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

-- Convenience methods.
-- TODO: Can maybe add size hints to the first byte of multi-byte data? So we
-- can pretty print it.
function Dataspace:addByte(byte)
  self:add(Dataspace.byte(byte))
end

function Dataspace:addWord(number)
  assert(number >= 0 and number <= 0xFFFF)
  self:addByte(lowByte(number))
  self:addByte(highByte(number))
end

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

function Dataspace:compileByte(byte)
  self:compile(Dataspace.byte(byte))
end

function Dataspace:compileWord(number)
  assert(number >= 0 and number <= 0xFFFF)
  self:compileByte(lowByte(number))
  self:compileByte(highByte(number))
end

return Dataspace
