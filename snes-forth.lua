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

local latest = 0
local here = 1
local input = {
  str = io.read("*all"),
  i = 0,
}

local dataspace = {}

local dictionary = {}

function dictionary:find(name)
  local i = latest
  while i > 0 do
    if dataspace[i].name == name then
      return dataspace[i].xt, 1
    end
    i = dataspace[i].prev
  end
  return nil, 0
end

function dictionary:colon(name, fn)
  dataspace[here] = {
    name = name,
    xt = fn,
    prev = latest,
  }
  latest = here
  here = here + 1
end

dictionary:colon("CREATE", function()
  local addr = here
  local name = input:word()
  dictionary:colon(name, function()
    stack:push(addr)
  end)
end)

dictionary:colon(".", function()
  print(stack:pop())
end)

print("latest: "..latest)
print("here: "..here)

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

-- TODO: ALLOT, ",", stack manipulation, compiling vs interpreting, actual colon
