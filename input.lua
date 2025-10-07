#!/usr/bin/lua

local Source = {}

function Source:fromString(name, str)
  local input = {
    name = name,
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

-- Returns false if EOF
function Source:nextLine()
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

function Source:word()
  local first, last = string.find(self.line, "%S+", self.i)
  while first == nil do
    if not self:nextLine() then
      return nil
    end
    first, last = string.find(self.line, "%S+", self.i)
  end
  self.i = last+1
  return string.sub(self.line, first, last)
end

-- Returns all text until `token`, then discards `token`.
function Source:untilToken(token)
  local str = ""
  local first = self.i
  local tokenFirst, tokenLast = string.find(self.line, token, first)
  while tokenFirst == nil do
    str = str .. string.sub(self.line, first, string.len(self.line))
    assert(self:nextLine(), string.format("Expect token '%s' but hit EOF.", token))
    first = self.i
    tokenFirst, tokenLast = string.find(self.line, token, first)
  end
  self.i = tokenLast+1
  return str .. string.sub(self.line, first, tokenFirst-1)
end

function Source:peek()
  while self.i > string.len(self.line) do
    if not self:nextLine() then
      return nil
    end
  end
  return string.byte(string.sub(self.line, self.i, self.i))
end

function Source:key()
  local c = self:peek()
  self.i = self.i + 1
  while self.i > string.len(self.line) and self:nextLine() do
    -- Keep moving on to the next line until we hit a character or EOF.
  end
  return c
end

local Input = {}

function Input:new()
  local input = {
    sourceStack = {},
    sources = {},
  }
  setmetatable(input, self)
  self.__index = self
  return input
end

function Input:pushSource(source)
  table.insert(self.sourceStack, source)
end

function Input:popSource(source)
  table.remove(self.sourceStack)
end

function Input:fromStdin()
  self:pushSource(Source:fromString("stdin", io.read("*all")))
end

function Input:include(filename)
  self.sources[filename] = true
  local f = assert(io.open(filename, "r"))
  local str = f:read("*all")
  f:close()
  self:pushSource(Source:fromString(filename, str))
end

function Input:require(filename)
  if not self.sources[filename] then
    self:include(filename)
  end
end

function Input:topSource()
  return self.sourceStack[#self.sourceStack]
end

function Input:word()
  local word = self:topSource():word()
  while word == nil do
    self:popSource()
    if #self.sourceStack == 0 then
      -- EOF and no more files to read.
      return nil
    end
    word = self:topSource():word()
  end
  return word
end

-- Returns all text until `token`, then discards `token`.
function Input:untilToken(token)
  -- Expects to find the token in the same file, so never moves to next file.
  return self:topSource():untilToken(token)
end

function Input:key()
  local c = self:topSource():key()
  while c == nil do
    self:popSource()
    if #self.sourceStack == 0 then
      -- EOF and no more files to read.
      return nil
    end
    c = self:topSource():key()
  end
  return c
end

return Input
