#!/usr/bin/lua

local Stack = {}

function Stack:new()
  local stack = {}
  setmetatable(stack, self)
  self.__index = self
  return stack
end

function Stack:entries()
  return #self
end

local function assertByte(byte)
  assert(type(byte) == "number", "Stack value wasn't number: " .. tostring(byte))
  assert(byte >= 0 and byte <= 0xFF, "Stack value was out of byte range: " .. byte)
end

function Stack:pushByte(val)
  assert(type(val) == "number", "Value pushed was not number: " .. tostring(val))
  assert(val >= 0 and val <= 0xFF, "Value pushed was out of byte range: " .. val)
  table.insert(self, val & 0xFF)
end

function Stack:pushWord(val)
  assert(type(val) == "number", "Value pushed was not number: " .. tostring(val))
  assert(val >= 0 and val <= 0xFFFF, "Value pushed was out of word range: " .. val)
  table.insert(self, (val >> 8) & 0xFF)
  table.insert(self, val & 0xFF)
end

function Stack:pushAddress(val)
  assert(type(val) == "number", "Value pushed was not number: " .. tostring(val))
  assert(val >= 0 and val <= 0xFFFFFF, "Value pushed was out of address range: " .. val)
  table.insert(self, (val >> 16) & 0xFF)
  table.insert(self, (val >> 8) & 0xFF)
  table.insert(self, val & 0xFF)
end

function Stack:pushQuaddress(val)
  self:pushByte(val >> 24)
  self:pushAddress(val & 0xFFFFFF)
end

function Stack:popByte()
  assert(#self > 0, "Tried to pop an empty stack.")
  local byte = table.remove(self)
  assertByte(byte)
  return byte
end

function Stack:popWord()
  assert(#self > 0, "Tried to pop an empty stack.")
  local lsb = table.remove(self)
  assertByte(lsb)
  local msb = table.remove(self)
  assertByte(msb)
  return (msb << 8) | lsb
end

function Stack:popAddress()
  assert(#self > 0, "Tried to pop an empty stack.")
  local lsb = table.remove(self)
  assertByte(lsb)
  local kindaSignificantByte = table.remove(self)
  assertByte(kindaSignificantByte)
  local msb = table.remove(self)
  assertByte(msb)
  return (msb << 16) | (kindaSignificantByte << 8) | lsb
end

function Stack:popQuaddress()
  return self:popAddress() & self:popByte() << 24
end

function Stack:topByte()
  assert(#self > 0, "Tried to top an empty stack.")
  local byte = self[#self]
  assertByte(byte)
  return byte
end

function Stack:topWord()
  assert(#self > 0, "Tried to top an empty stack.")
  local lsb = self[#self]
  assertByte(lsb)
  local msb = self[#self - 1]
  assertByte(msb)
  return (msb << 8) | lsb
end

function Stack:topAddress()
  assert(#self > 0, "Tried to top an empty stack.")
  local lsb = self[#self]
  assertByte(lsb)
  local kindaSignificantByte = self[#self - 1]
  assertByte(kindaSignificantByte)
  local msb = self[#self - 2]
  assertByte(msb)
  return (msb << 16) | (kindaSignificantByte << 8) | lsb
end

function Stack:print(file)
  -- TODO: Add pretty output for multi-byte (e.g. output multiple possible
  -- interpretations, like 0xFF (WORD: 0xFFEE ADDRESS: 0xFFEEDD)) and character
  -- values.
  file:write("#bottom#\n")
  for k,v in ipairs(self) do
    file:write(k .. ": (" .. type(v) .. ") " .. v .. "\n")
  end
  file:write("#top#\n")
end

return Stack
