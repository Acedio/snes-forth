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

function Stack:print(file)
  for k,v in ipairs(self) do
    file:write(k .. ": " .. v .. "\n")
  end
end

return Stack
