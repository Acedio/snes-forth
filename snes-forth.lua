#!/usr/bin/lua

local Stack = {}

function Stack:new()
  local stack = {}
  setmetatable(stack, self)
  self.__index = self
  return stack
end

function Stack:push(val)
  self[#self+1] = val
end

function Stack:pop()
  local val = self[#self]
  self[#self] = nil
  return val
end

local datastack = Stack:new()
local returnstack = Stack:new()

local latest = 0
local here = 1
local ip = 0
-- non-zero (true) if compiling
local state = 0
local input = {
  str = io.read("*all"),
  i = 0,
}

local dataspace = {}

local Dictionary = {}
local DICTIONARY_HEADER_SIZE = 1

-- Returns address or nil if missing
function Dictionary.find(name)
  local i = latest
  while i > 0 do
    if dataspace[i].name == name then
      return i
    end
    i = dataspace[i].prev
  end
  return nil
end

function nextIp()
  local oldip = ip
  ip = ip + 1
  print("oldIp: " .. oldip .. " newIp: " .. ip)
  dataspace[dataspace[oldip]].xt()
end

function addnext(fn)
  return function()
    fn()
    nextIp()
  end
end

function Dictionary.native(name, fn)
  dataspace[here] = {
    name = name,
    xt = addnext(fn),
    prev = latest,
  }
  latest = here
  here = here + DICTIONARY_HEADER_SIZE
end

function docol(there)
  returnstack:push(ip)
  ip = there -- TODO: Also, alignment?
  nextIp()
end

function Dictionary.colon(name)
  local there = here + DICTIONARY_HEADER_SIZE
  dataspace[here] = {
    name = name,
    xt = function()
      docol(there)
    end,
    prev = latest,
  }
  latest = here
  here = here + DICTIONARY_HEADER_SIZE
  -- TODO: How do we want to handle colon definitions? Do we have DOCOL
  -- somewhere? How does that translate to subroutine-threaded code?
end

Dictionary.native("CREATE", function()
  local addr = here
  local name = input:word()
  Dictionary.native(name, nil)  -- Use a placeholder fn initially.
  local dataaddr = here  -- HERE has been updated by calling native()
  -- Now update the fn with the new HERE.
  dataspace[addr].xt = function()
    datastack:push(dataaddr)
  end
end)

Dictionary.native("EXIT", function()
  ip = returnstack:pop()
end)

Dictionary.native(".", function()
  print(datastack:pop())
end)

-- TODO: QUIT currently just ends the program (by not calling nextIp), but
-- should actually be the eval loop.
Dictionary.native("QUIT", nil)
dataspace[Dictionary.find("QUIT")].xt = function()
  print("WE DONE!")
end

Dictionary.colon("TEST")
-- Add word to the current colon defintion
function addWord(name)
  index = Dictionary.find(name)
  assert(index ~= 0)
  dataspace[here] = index
  here = here + 1
end

datastack:push(1)
addWord(".")
addWord("EXIT")
addWord("TEST")
ip = here - 1  -- start on TEST, above
addWord("QUIT")

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

-- Print dataspace.
for k,v in ipairs(dataspace) do
  print(k .. ": " .. (type(v) == "number" and v or v.name))
end

nextIp()

--[[
while true do
  local word = input:word()
  if word == nil then
    break
  end
  local addr = Dictionary.find(word)
  if addr == nil then
    -- not found
    -- try parse number
    local num = tonumber(word)
    if num == nil then
      -- not a number, crash
      print("Couldn't parse " .. word .. ".")
      break
    end
    datastack:push(num)
  elseif dataspace[addr].immediate or state == 0 then
    -- found and immediate or we're not compiling, execute
    dataspace[addr].xt()
  else
    -- compiling
  end
end
]]

-- TODO: ALLOT, ",", stack manipulation, compiling vs interpreting, actual colon
