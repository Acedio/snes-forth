#!/usr/bin/lua

local Stack = {}

function Stack:new()
  local stack = {}
  setmetatable(stack, self)
  self.__index = self
  return stack
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

function Stack:popByte()
  local byte = table.remove(self)
  assertByte(byte)
  return byte
end

function Stack:popWord()
  local lsb = table.remove(self)
  assertByte(lsb)
  local msb = table.remove(self)
  assertByte(msb)
  return (msb << 8) | lsb
end

function Stack:popAddress()
  local lsb = table.remove(self)
  assertByte(lsb)
  local kindaSignificantByte = table.remove(self)
  assertByte(kindaSignificantByte)
  local msb = table.remove(self)
  assertByte(msb)
  return (msb << 16) | (kindaSignificantByte << 8) | lsb
end

function Stack:topByte()
  local byte = self[#self]
  assertByte(byte)
  return byte
end

function Stack:topWord()
  local lsb = self[#self]
  assertByte(lsb)
  local msb = self[#self - 1]
  assertByte(msb)
  return (msb << 8) | lsb
end

function Stack:topAddress()
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
  for k,v in ipairs(self) do
    file:write(k .. ": (" .. type(v) .. ") " .. v .. "\n")
  end
end

return Stack
