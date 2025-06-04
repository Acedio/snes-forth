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

local datastack = Stack:new()
local returnstack = Stack:new()

local latest = 0
local ip = 0
local input = {
  str = io.read("*all"),
  i = 0,
}

local dataspace = {}

local here = #dataspace + 1

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

function addNext(fn)
  return function()
    fn()
    nextIp()
  end
end

function Dictionary.native(name, fn)
  dataspace[here] = {
    name = name,
    xt = fn,
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
    nextIp()
  end
end)

function Dictionary.makeVariable(name)
  local addr = here
  Dictionary.native(name, nil)
  local dataaddr = here
  dataspace[addr].xt = function()
    datastack:push(dataaddr)
    nextIp()
  end
  -- initialize the var
  dataspace[here] = 0
  -- space for the var
  here = here + 1
end

Dictionary.makeVariable("STATE")

Dictionary.native("EXIT", function()
  ip = returnstack:pop()
  nextIp()
end)

Dictionary.native(".", function()
  print(datastack:pop())
  nextIp()
end)

Dictionary.native("BYE", function()
  print("WE DONE!")
  -- BYE ends the program by not calling nextIp
end)

-- Add word to the current colon defintion
function addWord(name)
  index = Dictionary.find(name)
  assert(index, "Couldn't find " .. name)
  dataspace[here] = index
  here = here + 1
end

function addWords(names)
  local first = 0
  local last = 0
  while true do
    first, last = string.find(names, "%S+", last)
    if first == nil then
      break
    end
    addWord(string.sub(names, first, last))
    last = last + 1
  end
end

function addNumber(number)
  dataspace[here] = number
  here = here + 1
end

function input:word()
  local first, last = string.find(self.str, "%S+", self.i)
  if first == nil then
    return ""
  end
  self.i = last+1
  return string.sub(self.str, first, last)
end

Dictionary.native("WORD", function()
  datastack:push(input:word() or "")
  nextIp()
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
  nextIp()
end)

-- TODO: Non-standard.
Dictionary.native(">NUMBER", function()
  datastack:push(tonumber(datastack:pop()) or 0)
  nextIp()
end)

Dictionary.native("DUP", function()
  datastack:push(datastack:top())
  nextIp()
end)

Dictionary.native("DROP", function()
  datastack:pop()
  nextIp()
end)

Dictionary.native("COMPILE,", function()
  dataspace[here] = datastack:pop()
  here = here + 1
  nextIp()
end)

-- TODO: Not standard.
Dictionary.native("COUNT", function()
  local str = datastack:pop()
  datastack:push(string.len(str))
  nextIp()
end)

Dictionary.native(">R", function()
  returnstack:push(datastack:pop())
  nextIp()
end)

Dictionary.native("R>", function()
  datastack:push(returnstack:pop())
  nextIp()
end)

Dictionary.native("BRANCH0", function()
  if datastack:pop() == 0 then
    ip = dataspace[ip]
  else
    ip = ip + 1
  end
  nextIp()
end)

Dictionary.native("@", function()
  datastack:push(dataspace[datastack:pop()])
  nextIp()
end)

Dictionary.native("!", function()
  local addr = datastack:pop()
  local val = datastack:pop()
  dataspace[addr] = val
  nextIp()
end)

Dictionary.native("1+", function()
  datastack:push(datastack:pop() + 1)
  nextIp()
end)

Dictionary.native("EXECUTE", function()
  dataspace[datastack:pop()].xt()
  -- No nextIp() is needed because the xt() should call it.
end)

function unaryOp(name, op)
  Dictionary.native(name, function()
    local a = datastack:pop()
    datastack:push(op(a) & 0xFFFF)
    nextIp()
  end)
end

unaryOp("NEGATE", function(a)
  return -a
end)

unaryOp("INVERT", function(a)
  return ~a
end)

function binaryOp(name, op)
  Dictionary.native(name, function()
    local b = datastack:pop()
    local a = datastack:pop()
    datastack:push(op(a,b) & 0xFFFF)
    nextIp()
  end)
end

binaryOp("AND", function(a,b)
  return a & b
end)

binaryOp("OR", function(a,b)
  return a | b
end)

binaryOp("XOR", function(a,b)
  return a ~ b
end)

binaryOp("-", function(a,b)
  return a - b
end)

binaryOp("+", function(a,b)
  return a + b
end)

function binaryCmpOp(name, op)
  Dictionary.native(name, function()
    local b = datastack:pop()
    local a = datastack:pop()
    datastack:push(op(a,b) and 0xFFFF or 0)
    nextIp()
  end)
end

binaryCmpOp("=", function(a, b)
  return a == b
end)

binaryCmpOp("<", function(a, b)
  return a < b
end)

binaryCmpOp(">", function(a, b)
  return a > b
end)

binaryCmpOp("<=", function(a, b)
  return a <= b
end)

binaryCmpOp(">=", function(a, b)
  return a >= b
end)

binaryCmpOp("<>", function(a, b)
  return a ~= b
end)

Dictionary.colon("LIT")
  addWord("R>")
  addWord("DUP")
  addWord("1+")
  addWord(">R")
  addWord("@")
  addWord("EXIT")

do
  Dictionary.colon("QUIT")
  local loop = here
  addWords("WORD DUP COUNT BRANCH0")
  local eofBranchAddr = here
  addNumber(2000)

  addWords("FIND")

  addWords("DUP LIT")
  addNumber(0)
  addWords("= BRANCH0")
    local notNumberBranchAddr = here
    addNumber("2000") -- will be replaced later
    addWords("DROP >NUMBER LIT")
    addNumber(0)
    addWord("BRANCH0")
    addNumber(loop)
  dataspace[notNumberBranchAddr] = here

  addWords("DUP LIT")
  addNumber(0)
  addWords("> STATE @ INVERT OR BRANCH0")
    local branchAddrIfNotImmediate = here
    addNumber("2000") -- will be replaced later
    addWords("DROP EXECUTE LIT")
    addNumber(0)
    addWord("BRANCH0")
    addNumber(loop)
  dataspace[branchAddrIfNotImmediate] = here

  addWords("DROP")  -- else, compiling
  addWords("COMPILE,")
  addNumber(loop)

  dataspace[eofBranchAddr] = here
  addWord("EXIT")
end

ip = here -- start on TEST, below
addWord("QUIT")
addWord("BYE")

print("latest: "..latest)
print("here: "..here)

function cellString(contents)
  if type(contents) == "number" then
    if contents >= 0 and contents < here and type(dataspace[contents]) == "table" and dataspace[contents].name ~= nil then
      return contents .. " (? " .. dataspace[contents].name .. ")"
    else
      return tostring(contents)
    end
  elseif type(contents) == "table" and contents.name ~= nil then
    return contents.name
  else
    return "???"
  end
end

-- Print dataspace.
for k,v in ipairs(dataspace) do
  cellString(v)
  print(k .. ": " .. cellString(v))
end

nextIp()

for k,v in ipairs(datastack) do
  print(k .. ": " .. v)
end

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
