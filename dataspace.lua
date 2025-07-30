#!/usr/bin/lua

local Dataspace = {}

function Dataspace:new()
  local dataspace = {
    latest = 0,
    here = 1,
  }
  setmetatable(dataspace, self)
  self.__index = self
  return dataspace
end

function Dataspace:print(file)
  for k,v in ipairs(self) do
    file:write(k .. ": " .. v:toString(self) .. "\n")
  end
end

function Dataspace:assembly(file)
  for k,v in ipairs(self) do
    if v.label then
      file:write(v.label .. ":\n")
    end
    file:write(v:asm(self) .. "\n")
  end
end

function Dataspace:add(entry)
  self[self.here] = entry
  self.here = self.here + 1
end

function Dataspace.dictionaryEntry(name, prev)
  local entry = {
    type = "dictionary-entry",
    name = name,
    size = function() assert(false, "Tried to get size of dictionary entry.") end,
    prev = prev,
  }
  function entry:toString(dataspace)
    return "Dictionary entry: " .. name
  end
  function entry:asm(dataspace)
    -- TODO: Implement.
    return "; Dictionary entry for " .. name
  end
  return entry
end

function Dataspace:dictionaryAdd(name)
  local entry = Dataspace.dictionaryEntry(name, self.latest)
  self.latest = self.here
  self:add(entry)
end

-- Returns address or nil if missing
function Dataspace:dictionaryFind(name)
  local i = self.latest
  while i > 0 do
    assert(self[i].type == "dictionary-entry", "Expected dictionary entry at addr = " .. i)
    if self[i].name == name then
      -- Return the address of the dictionary entry.
      return i
    end
    i = self[i].prev
  end
  return nil
end

function Dataspace.toCodeword(dictAddr)
  return dictAddr + 1
end

function Dataspace:codewordOf(name)
  local dictAddr = self:dictionaryFind(name)
  if dictAddr then
    return Dataspace.toCodeword(dictAddr)
  else
    return dictAddr
  end
end

function Dataspace.defaultLabel(name)
  return "_" .. string.gsub(name, "%W", "_")
end

function Dataspace.native(entry)
  entry.type = "native"
  if not entry.size then
    entry.size = function() assert(false, "Tried to get size of native entry.") end
  end
  if not entry.label then
    -- TODO: Add default logic here to convert name to label by replacing
    -- non-alphas with underscores.
    entry.label = Dataspace.defaultLabel(entry.name)
  end
  if not entry.asm then
    function entry:asm(dataspace)
      return string.format("jsl not_implemented ; TODO: Not implemented")
    end
  end
  function entry:toString(dataspace)
    return "Native: " .. self.name
  end
  return entry
end

function Dataspace.call(addr)
  local entry = {
    type = "call",
    size = function() return 3 end,
    addr = addr,
  }
  function entry:toString(dataspace)
    assert(self.addr > 0 and self.addr < dataspace.here, "Invalid address " .. self.addr )
    assert(dataspace[self.addr].type == "native", "Expected fn at " .. self.addr)
    if dataspace[self.addr].name ~= nil then
      return "Call " .. dataspace[self.addr].name .. " (" .. self.addr .. ")"
    else
      return "Unnamed fn at: " .. tostring(self.addr)
    end
  end
  function entry:asm(dataspace)
    assert(self.addr > 0 and self.addr < dataspace.here, "Invalid address " .. self.addr)
    assert(dataspace[self.addr].type == "native", "Expected fn at " .. self.addr)
    return string.format("JSR %s", dataspace[self.addr].label)
  end
  return entry
end

function Dataspace.address(addr)
  local entry = {
    type = "address",
    size = function() return 3 end,
    addr = addr,
  }
  function entry:toString(dataspace)
    assert(self.addr >= -0x800000 and self.addr <= 0x7FFFFF, "Invalid address " .. self.addr )
    return "Address: " .. tostring(self.addr)
  end
  function entry:asm(dataspace)
    assert(self.addr >= -0x800000 and self.addr <= 0x7FFFFF, "Invalid address " .. self.addr )
    return string.format(".FARADDR %d", self.addr)
  end
  return entry
end

function Dataspace.xt(addr)
  local entry = {
    type = "xt",
    size = function() return 3 end,
    addr = addr,
  }
  function entry:toString(dataspace)
    assert(self.addr < dataspace.here and dataspace[self.addr].label, "Invalid xt " .. self.addr )
    return string.format("XT: %d %s", self.addr, dataspace[self.addr].label)
  end
  function entry:asm(dataspace)
    assert(self.addr < dataspace.here and dataspace[self.addr].label, "Invalid xt " .. self.addr )
    return string.format(".WORD %s", dataspace[self.addr].label)
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
    delta = delta + self[current]:size()
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
      delta = delta - self[current]:size()
      current = current + 1
    end
  else
    while delta < 0 do
      current = current - 1
      delta = delta + self[current]:size()
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
      delta = delta + self[current]:size()
      current = current + 1
    end
  else
    while current > to do
      current = current - 1
      delta = delta - self[current]:size()
    end
  end
  return delta
end

function Dataspace.number(number)
  local entry = {
    type = "number",
    size = function() return 2 end,
    -- TODO: Signed vs Unsigned? Or maybe always store unsigned but rely on
    -- caller?
    number = number & 0xFFFF,
  }
  function entry:toString(dataspace)
    return "Number: " .. tostring(self.number)
  end
  function entry:asm(dataspace)
    return string.format(".WORD %d", self.number & 0xFFFF)
  end
  return entry
end

function Dataspace.byte(byte)
  local entry = {
    type = "byte",
    size = function() return 1 end,
    byte = byte & 0xFF,
  }
  function entry:toString(dataspace)
    return "Byte: " .. tostring(self.byte)
  end
  function entry:asm(dataspace)
    return string.format(".BYTE %d", self.byte & 0xFF)
  end
  return entry
end

-- Convenience methods.
function Dataspace:addCall(addr)
  self:add(Dataspace.call(addr))
end

function Dataspace:addAddress(addr)
  self:add(Dataspace.address(addr))
end

function Dataspace:addXt(name)
  self:add(Dataspace.xt(self:codewordOf(name)))
end

function Dataspace:addNumber(number)
  self:add(Dataspace.number(number))
end

function Dataspace:addByte(byte)
  self:add(Dataspace.byte(byte))
end

-- Table should have at least name and runtime specified.
-- TODO: Maybe we can also support inlining by specifying an `inline` field
-- that, if specified, overrides the Forth word call and instead causes code to
-- be added directly. e.g. LIT would be
--   lda #LITERAL_NUM
--   PUSH_A
-- instead of the usual
--   JSL LIT
--   .WORD LITERNAL_NUM
-- which is a lot slower.
function Dataspace:addNative(entry)
  self:dictionaryAdd(entry.name)
  self:add(Dataspace.native(entry))
end

-- Add word to the current colon defintion
function Dataspace:addWord(name)
  index = self:codewordOf(name)
  assert(index, "Couldn't find " .. name)
  self:addCall(index)
end

function Dataspace:addWords(names)
  local first = 0
  local last = 0
  while true do
    first, last = string.find(names, "%S+", last)
    if first == nil then
      break
    end
    self:addWord(string.sub(names, first, last))
    last = last + 1
  end
end

return Dataspace
