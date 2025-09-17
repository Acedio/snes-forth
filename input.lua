#!/usr/bin/lua

local Input = {}

function Input:fromString(str)
  local input = {
    str = str,
    line = "",
    lineStart = 1,
    lineNo = 1,
    i = 1,
  }
  setmetatable(input, self)
  self.__index = self
  input:nextLine()
  return input
end

function Input:stdin()
  return self:fromString(io.read("*all"))
end

function Input:readAll(filename)
  local f = assert(io.open(filename, "r"))
  local str = f:read("*all")
  f:close()
  return self:fromString(str)
end

-- Returns false if EOF
function Input:nextLine()
  if self.lineStart > string.len(self.str) then
    return false
  end
  local first = self.lineStart
  local last = string.find(self.str, "\n", first)
  if last == nil then
    last = string.len(self.str)
  end
  self.line = string.sub(self.str, first, last)
  self.lineStart = last + 1
  self.lineNo = self.lineNo + 1
  self.i = 1
  return true
end

function Input:word()
  local first, last = string.find(self.line, "%S+", self.i)
  while first == nil do
    if not self:nextLine() then
      return ""
    end
    first, last = string.find(self.line, "%S+", self.i)
  end
  self.i = last+1
  return string.sub(self.line, first, last)
end

-- Returns all text until `token`, then discards `token`.
function Input:untilToken(token)
  local str = ""
  local first = self.i
  local tokenFirst, tokenLast = string.find(self.line, token, first)
  while tokenFirst == nil do
    str = str .. string.sub(self.line, first, string.len(self.line))
    if not self:nextLine() then
      return str
    end
    first = self.i
    tokenFirst, tokenLast = string.find(self.line, token, first)
  end
  self.i = tokenLast+1
  return str .. string.sub(self.line, first, tokenFirst-1)
end

-- TODO: EOF handling.
function Input:peek()
  return string.byte(string.sub(self.line, self.i, self.i))
end

function Input:key()
  local c = self:peek()
  self.i = self.i + 1
  if self.i > string.len(self.line) then
    self:nextLine()
  end
  return c
end

return Input
