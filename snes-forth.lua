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

function Stack:top()
  return self[#self]
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

Dictionary.native("BYE", nil)
dataspace[Dictionary.find("BYE")].xt = function()
  print("WE DONE!")
  -- BYE ends the program by not calling nextIp
end

-- Add word to the current colon defintion
function addWord(name)
  index = Dictionary.find(name)
  assert(index, "Couldn't find " .. name)
  dataspace[here] = index
  here = here + 1
end

function addNumber(number)
  dataspace[here] = number
  here = here + 1
end

function input:word()
  local first, last = string.find(self.str, "%S+", self.i)
  if first == nil then
    return nil
  end
  self.i = last+1
  return string.sub(self.str, first, last)
end

Dictionary.native("WORD", function()
  datastack:push(input:word() or "")
end)

-- Can probably be written in Forth? Though not interpreted-Forth.
Dictionary.native("FIND", function()
  local word = datastack:pop()
  local index = Dictionary.find(word)
  if not index then
    datastack:push(word)
    datastack:push(0)
  elseif dataspace[index].immediate then
    datastack:push(index)
    datastack:push(1)
  else
    datastack:push(index)
    datastack:push(-1)
  end
end)

Dictionary.native("DUP", function()
  datastack:push(datastack:top())
end)

Dictionary.native(">R", function()
  returnstack:push(datastack:pop())
end)

Dictionary.native("R>", function()
  datastack:push(returnstack:pop())
end)

Dictionary.native("BRANCH0", function()
  if datastack:pop() == 0 then
    ip = dataspace[ip]
  else
    ip = ip + 1
  end
end)

Dictionary.native("@", function()
  datastack:push(dataspace[datastack:pop()])
end)

Dictionary.native("!", function()
  local addr = datastack:pop()
  local val = datastack:pop()
  dataspace[addr] = val
end)

Dictionary.native("1+", function()
  datastack:push(datastack:pop() + 1)
end)

Dictionary.colon("LIT")
addWord("R>")
addWord("DUP")
addWord("1+")
addWord(">R")
addWord("@")
addWord("EXIT")

Dictionary.colon("TEST")
addWord("LIT")
addNumber(21)
addWord(".")
addWord("EXIT")
ip = here -- start on TEST, below
addWord("TEST")
addWord("BYE")

print("latest: "..latest)
print("here: "..here)

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
