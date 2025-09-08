#!/usr/bin/lua

local CellStack = {}

function CellStack:new()
  local stack = {}
  setmetatable(stack, self)
  self.__index = self
  return stack
end

function CellStack:entries()
  return #self
end

function CellStack:push(val)
  assert(type(val) == "number", "Value pushed was not number: " .. tostring(val))
  assert(val >= 0 and val <= 0xFFFF, "Value pushed was out of cell range: " .. val)
  table.insert(self, val)
end

function CellStack:pushDouble(val)
  assert(type(val) == "number", "Value pushed was not number: " .. tostring(val))
  assert(val >= 0 and val <= 0xFFFFFFFF, "Value pushed was out of cell range: " .. val)
  table.insert(self, val >> 16)
  table.insert(self, val & 0xFFFF)
end

function CellStack:pop()
  assert(#self > 0, "Tried to pop an empty stack.")
  local cell = table.remove(self)
  assert(cell >= 0 and cell <= 0xFFFF, "Stack value was out of cell range: " .. cell)
  return cell
end

function CellStack:popDouble()
  assert(#self > 1, "Tried to pop stack with not enough values.")
  local low = table.remove(self)
  local high = table.remove(self)
  local double = (high << 16) | low
  assert(double >= 0 and double <= 0xFFFFFFFF, "Stack value was out of double range: " .. double)
  return double
end

function CellStack:top()
  assert(#self > 0, "Tried to top an empty stack.")
  local cell = self[#self]
  assert(cell >= 0 and cell <= 0xFFFF, "Stack value was out of cell range: " .. cell)
  return cell
end

function CellStack:topDouble()
  assert(#self > 1, "Tried to top stack with not enough values.")
  local low = self[#self]
  local high = self[#self - 1]
  local double = (high << 16) | low
  assert(double >= 0 and double <= 0xFFFFFFFF, "Stack value was out of double range: " .. double)
  return double
end

function CellStack:print(file)
  -- TODO: Add pretty output for multi-byte (e.g. output multiple possible
  -- interpretations, like 0xFF (WORD: 0xFFEE ADDRESS: 0xFFEEDD)) and character
  -- values.
  file:write("#bottom#\n")
  for k,v in ipairs(self) do
    file:write(string.format("% 3d: % 5d 0x%04X\n", k, v, v))
  end
  file:write("#top#\n")
end

return CellStack
