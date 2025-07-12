#!/usr/bin/lua

local Input = {}

function Input:stdin()
  local input = {
    str = io.read("*all"),
    i = 0,
  }
  setmetatable(input, self)
  self.__index = self
  return input
end

function Input:readAll(filename)
  local f = assert(io.open(filename, "r"))
  local input = {
    str = f:read("*all"),
    i = 0,
  }
  f:close()
  setmetatable(input, self)
  self.__index = self
  return input
end

function Input:word()
  local first, last = string.find(self.str, "%S+", self.i)
  if first == nil then
    return ""
  end
  self.i = last+1
  return string.sub(self.str, first, last)
end

function Input:peek()
  return string.byte(string.sub(self.str, self.i, self.i))
end

function Input:key()
  local c = self:peek()
  self.i = self.i + 1
  return c
end

return Input
