#!/usr/bin/lua

local stack = {
  top = 1
}

function stack:push(val)
  self[self.top] = val
  self.top = self.top + 1
end

function stack:pop()
  self.top = self.top - 1
  return self[self.top]
end

local dictionary = {
  top = 2,
  [1] = {
    name = ".",
    xt = function()
      print(stack:pop())
    end,
  },
}

function dictionary:find(name)
  local i = self.top - 1
  while i > 0 do
    if self[i].name == name then
      return self[i].xt, 1
    end
    i = i - 1
  end
  return name, 0
end

local input = {
  str = io.read("*all"),
  i = 0,
}

function input:word()
  local first, last = string.find(self.str, "%S+", self.i)
  if first == nil then
    return nil
  end
  self.i = last+1
  return string.sub(self.str, first, last)
end

while true do
  local word = input:word()
  if word == nil then
    break
  end
  local xt, immediate = dictionary:find(word)
  if immediate == 0 then
    -- not found
    -- try parse number
    local num = tonumber(word)
    if num == nil then
      -- not a number, crash
      print("Couldn't parse " .. word .. ".")
      break
    end
    stack:push(num)
  else
    -- found, execute
    xt()
  end
end

-- TODO: Need to figure out how we should actually structure the dictionary so
-- that HERE and , and friends work. Also CREATE.
