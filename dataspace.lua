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

function Dataspace.formatAddr(addr)
  return string.format("$%04X", addr)
end

function Dataspace:print(file)
  for k,v in ipairs(self) do
    file:write(string.format("%s: %s\n", Dataspace.formatAddr(k), v:toString(self)))
  end
end

function Dataspace:assembly(file)
  for k,v in ipairs(self) do
    file:write(v:asm(self) .. "\n")
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

-- TODO: Maybe addSized and addUnsized
function Dataspace:add(entry)
  self[self.here] = entry
  self.here = self.here + 1
  return entry
end

function Dataspace.dictionaryEntry(name, label, prev)
  local entry = {
    type = "dictionary-entry",
    name = name,
    label = label,
    -- TODO: These should be sizable.
    size = function() return nil end,
    prev = prev,
  }
  function entry:toString(dataspace)
    return "Dictionary entry: " .. name
  end
  function entry:asm(dataspace)
    -- TODO: Implement.
    return string.format([[
    ; Dictionary entry for %s
    %s:
    ]], self.name, self.label)
  end
  return entry
end

function Dataspace:dictionaryAdd(name, label)
  local entry = Dataspace.dictionaryEntry(name, label, self.latest)
  self.latest = self.here
  return self:add(entry)
end

-- Returns address or nil if missing
function Dataspace:dictionaryFind(name)
  local addr = self.latest
  while addr > 0 do
    assert(self[addr].type == "dictionary-entry", string.format("Expected dictionary entry at addr = %s", Dataspace.formatAddr(addr)))
    if self[addr].name == name then
      -- Return the address of the dictionary entry.
      return addr
    end
    addr = self[addr].prev
  end
  return nil
end

function Dataspace.toCodeword(dictAddr)
  return dictAddr + 1
end

-- Returns the dictionary-entry for the given XT.
function Dataspace:addrDict(xt)
  local maybeDict = self[xt - 1]
  if maybeDict.type ~= "dictionary-entry" then
    return nil
  end
  return self[xt - 1]
end

function Dataspace:addrName(addr)
  local maybeDict = self:addrDict(addr)
  if not maybeDict then
    return nil
  end
  return maybeDict.name
end

function Dataspace:addrLabel(addr)
  local maybeDict = self:addrDict(addr)
  if not maybeDict then
    return nil
  end
  return maybeDict.label
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

-- Takes a (potentially partially initiated) native definition.
function Dataspace.native(entry)
  entry.type = "native"
  if not entry.size then
    entry.size = function() return nil end
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

-- TODO: I think maybe `call` is just `native` but has a defined size? This
-- should/could also probably have runtime().
function Dataspace.call(addr)
  local entry = {
    type = "call",
    size = function() return 3 end,
    addr = addr,
  }
  function entry:toString(dataspace)
    assert(self.addr > 0 and self.addr < dataspace.here, "Invalid address " .. self.addr )
    -- TODO: This check should happen at runtime()
    assert(dataspace[self.addr].type == "native" or dataspace[self.addr].type == "call", string.format("Expected fn or call at %s", Dataspace.formatAddr(self.addr)))
    local name = dataspace:addrName(self.addr)
    if not name then
      return string.format("Call to $%04X (missing name)", self.addr)
    end
    return "Call " .. name
  end
  function entry:asm(dataspace)
    assert(self.addr > 0 and self.addr < dataspace.here, "Invalid address " .. self.addr)
    assert(dataspace[self.addr].type == "native" or dataspace[self.addr].type == "call", string.format("Expected fn or call at %s", Dataspace.formatAddr(self.addr)))
    -- TODO: I think this might be broken for code after DODOES.
    local label = dataspace:addrLabel(self.addr)
    if not label then
      return nil
    end
    return string.format("JSR %s", label)
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
    size = function() return 2 end,
    addr = addr,
  }
  function entry:toString(dataspace)
    local name = dataspace:addrName(self.addr)
    if not name then
      return string.format("XT: %d without name", self.addr)
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
    assert(size, "Couldn't get size of " .. self[current]:toString(self))
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
      assert(size, "Couldn't get size of " .. self[current]:toString(self))
      delta = delta - size
      current = current + 1
    end
  else
    while delta < 0 do
      current = current - 1
      local size = self[current]:size()
      assert(size, "Couldn't get size of " .. self[current]:toString(self))
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
      assert(size, "Couldn't get size of " .. self[current]:toString(self))
      delta = delta + size
      current = current + 1
    end
  else
    while current > to do
      current = current - 1
      local size = self[current]:size()
      assert(size, "Couldn't get size of " .. self[current]:toString(self))
      delta = delta - size
    end
  end
  return delta
end

-- Always unsigned.
function Dataspace.number(number)
  local entry = {
    type = "number",
    size = function() return 2 end,
    number = number & 0xFFFF,
  }
  function entry:toString(dataspace)
    return "Number: " .. string.format("$%04X", self.number)
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
  return self:add(Dataspace.call(addr))
end

function Dataspace:addAddress(addr)
  return self:add(Dataspace.address(addr))
end

function Dataspace:addXt(name)
  return self:add(Dataspace.xt(self:codewordOf(name)))
end

function Dataspace:addNumber(number)
  return self:add(Dataspace.number(number))
end

function Dataspace:addByte(byte)
  return self:add(Dataspace.byte(byte))
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
  self:dictionaryAdd(entry.name, entry.label or Dataspace.defaultLabel(entry.name))
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
