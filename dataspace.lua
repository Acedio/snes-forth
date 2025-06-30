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

function Dataspace.native(entry)
  entry.type = "native"
  if not entry.size then
    entry.size = function() assert(false, "Tried to get size of native entry.") end
  end
  if not entry.label then
    entry.label = entry.name
  end
  if not entry.asm then
    function entry:asm(dataspace)
      return string.format("; TODO: Not implemented\n; TODO: abort?\n")
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
    size = function() return 4 end,
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
    return string.format("JSL %s\n", dataspace[self.addr].label)
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
    assert(self.addr > 0, "Invalid address " .. self.addr )
    return "Address: " .. tostring(self.addr)
  end
  function entry:asm(dataspace)
    assert(self.addr > 0, "Invalid address " .. self.addr)
    if dataspace[self.addr].label then
      return string.format(".FARADDR %s\n", dataspace[self.addr].label)
    else
      -- TODO: This doesn't work, we need to calculate the address.
      return string.format(".FARADDR %d\n", self.addr)
    end
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

-- Input: Lua address and SNES delta
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

function Dataspace.number(number)
  local entry = {
    type = "number",
    size = function() return 2 end,
    number = number,
  }
  function entry:toString(dataspace)
    return "Number: " .. tostring(self.number)
  end
  function entry:asm(dataspace)
    return string.format(".WORD %d\n", self.number & 0xFFFF)
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

function Dataspace:addNumber(number)
  self:add(Dataspace.number(number))
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
