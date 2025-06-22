#!/usr/bin/lua

local Stack = {}

function Stack:new()
  local stack = {}
  setmetatable(stack, self)
  self.__index = self
  return stack
end

function Stack:push(val)
  table.insert(self, val)
end

function Stack:pop()
  return table.remove(self)
end

function Stack:top()
  return self[#self]
end

function Stack:print()
  for k,v in ipairs(self) do
    print(k .. ": " .. v)
  end
end

return Stack
