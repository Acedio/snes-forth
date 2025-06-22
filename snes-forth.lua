#!/usr/bin/lua

local Stack = require("stack")
local Input = require("input")

local datastack = Stack:new()
local returnstack = Stack:new()

local latest = 0
local ip = 0

local input = Input:stdin()

local dataspace = {}

-- HERE is the DATASPACE pointer
local here = #dataspace + 1

-- Print dataspace.
function printDataspace()
  for k,v in ipairs(dataspace) do
    cellString(v)
    print(k .. ": " .. cellString(v))
  end
end

function snesAssembly()
  for k,v in ipairs(dataspace) do
    if type(v) == "table" then
      if v.label then
        print(string.format("%s:", v.label))
      end
      print(v.asm())
    elseif type(v) == "number" then
      if v >= 0 and v < here and type(dataspace[v]) == "table" and dataspace[v].name ~= nil then
        assert(dataspace[v].label, "label was nil for " .. dataspace[v].name)
        print(string.format("JML %s", dataspace[v].label))
      else
        print(string.format(".B %d", v & 0xFFFF))
      end
    end
  end
end

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
  print("oldIp: " .. oldip .. " (" .. cellString(dataspace[dataspace[oldip]]) .. ") newIp: " .. ip)
  return dataspace[dataspace[oldip]].runtime()
end

function snes_not_implemented(name)
  return function()
    return [[
  ; Not Implemented Yet
  ; TODO: abort?
]]
  end
end

function Dictionary.nativeWithLabel(name, label, fn)
  dataspace[here] = {
    name = name,
    label = label,
    runtime = fn,
    asm = snes_not_implemented(label),
    prev = latest,
  }
  latest = here
  here = here + DICTIONARY_HEADER_SIZE
end

function Dictionary.native(name, fn)
  Dictionary.nativeWithLabel(name, name, fn)
end

function docol(dataaddr)
  returnstack:push(ip)
  ip = dataaddr -- TODO: Also, alignment?
  return nextIp()
end

-- TODO: Can we express this neatly in terms of Dictionary.native()?
function Dictionary.colonWithLabel(name, label)
  local dataaddr = here + DICTIONARY_HEADER_SIZE
  dataspace[here] = {
    name = name,
    label = label,
    runtime = function()
      return docol(dataaddr)
    end,
    asm = snes_not_implemented(label),
    prev = latest,
  }
  latest = here
  here = here + DICTIONARY_HEADER_SIZE
end

function Dictionary.colon(name)
  Dictionary.colonWithLabel(name, name)
end

Dictionary.native("DATASPACE", function()
  printDataspace()
  return nextIp()
end)

Dictionary.nativeWithLabel(".S", "_DOT_S", function()
  datastack:print()
  return nextIp()
end)

-- Set the XT for the latest word to start a docol at addr
-- TODO: How will this work on the SNES?
Dictionary.nativeWithLabel("XT!", "_XT_STORE", function()
  local addr = datastack:pop()
  local dataaddr = latest + 1
  dataspace[latest].runtime = function()
    datastack:push(dataaddr)
    return dataspace[addr].runtime()
  end
  return nextIp()
end)

Dictionary.nativeWithLabel("COMPILE-DOCOL", "_COMPILE_DOCOL", function()
  local addr = here + DICTIONARY_HEADER_SIZE
  dataspace[here] = {
    name = "docol-fn",
    label = nil,
    runtime = function()
      docol(addr)
    end,
    -- No prev because this isn't a dictionary entry.
  }
  here = here + DICTIONARY_HEADER_SIZE
  return nextIp()
end)

Dictionary.nativeWithLabel(",", "_COMMA", function()
  dataspace[here] = datastack:pop()
  here = here + 1
  return nextIp()
end)

Dictionary.native("CREATE", function()
  local addr = here
  local name = input:word()
  Dictionary.native(name, nil)  -- Use a placeholder fn initially.
  local dataaddr = here  -- HERE has been updated by calling native()
  -- Now update the fn with the new HERE.
  dataspace[addr].runtime = function()
    datastack:push(dataaddr)
    return nextIp()
  end
  return nextIp()
end)

Dictionary.native("CREATEDOCOL", function()
  local name = input:word()
  Dictionary.colon(name)
  return nextIp()
end)

function Dictionary.makeVariable(name)
  local addr = here
  Dictionary.native(name, nil)
  local dataaddr = here
  dataspace[addr].runtime = function()
    datastack:push(dataaddr)
    return nextIp()
  end
  -- initialize the var
  dataspace[here] = 0
  -- space for the var
  here = here + 1
end

Dictionary.makeVariable("STATE")

Dictionary.native("EXIT", function()
  ip = returnstack:pop()
  return nextIp()
end)

Dictionary.nativeWithLabel(".", "_DOT", function()
  print(datastack:pop())
  return nextIp()
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

Dictionary.native("EMIT", function()
  io.write(string.char(datastack:pop()))
  return nextIp()
end)

Dictionary.native("WORD", function()
  datastack:push(input:word() or "")
  return nextIp()
end)

Dictionary.native("PEEK", function()
  datastack:push(input:peek())
  return nextIp()
end)

Dictionary.native("KEY", function()
  datastack:push(input:key())
  return nextIp()
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
  return nextIp()
end)

-- TODO: Non-standard.
Dictionary.nativeWithLabel(">NUMBER", "_TO_NUMBER", function()
  datastack:push(tonumber(datastack:pop()) or 0)
  return nextIp()
end)

Dictionary.native("DUP", function()
  datastack:push(datastack:top())
  return nextIp()
end)

Dictionary.native("DROP", function()
  datastack:pop()
  return nextIp()
end)

Dictionary.nativeWithLabel("COMPILE,", "_COMPILE_COMMA", function()
  dataspace[here] = datastack:pop()
  here = here + 1
  return nextIp()
end)

-- TODO: Not standard.
Dictionary.native("COUNT", function()
  local str = datastack:pop()
  datastack:push(string.len(str))
  return nextIp()
end)

Dictionary.nativeWithLabel(">R", "_TO_R", function()
  returnstack:push(datastack:pop())
  return nextIp()
end)

Dictionary.nativeWithLabel("R>", "_FROM_R", function()
  datastack:push(returnstack:pop())
  return nextIp()
end)

Dictionary.native("BRANCH0", function()
  if datastack:pop() == 0 then
    ip = dataspace[ip]
  else
    ip = ip + 1
  end
  return nextIp()
end)

Dictionary.nativeWithLabel("@", "_FETCH", function()
  datastack:push(dataspace[datastack:pop()])
  return nextIp()
end)

Dictionary.nativeWithLabel("!", "_STORE", function()
  local addr = datastack:pop()
  local val = datastack:pop()
  dataspace[addr] = val
  return nextIp()
end)

Dictionary.nativeWithLabel("1+", "_INCR", function()
  datastack:push(datastack:pop() + 1)
  return nextIp()
end)

Dictionary.colon("LIT")
  addWord("R>")
  addWord("DUP")
  addWord("1+")
  addWord(">R")
  addWord("@")
  addWord("EXIT")

Dictionary.native("EXECUTE", function()
  return dataspace[datastack:pop()].runtime()
  -- No nextIp() is needed because the runtime() should call it.
end)

Dictionary.colon("TRUE")
  addWord("LIT")
  addNumber(0xFFFF)
  addWord("EXIT")

Dictionary.colon("FALSE")
  addWord("LIT")
  addNumber(0)
  addWord("EXIT")

Dictionary.colon("CR")
  addWord("LIT")
  addNumber(string.byte("\n"))
  addWords("EMIT EXIT")

Dictionary.colonWithLabel("[", "_LBRACK")
  addWords("FALSE STATE ! EXIT")

Dictionary.colonWithLabel("]", "_RBRACK")
  addWords("TRUE STATE ! EXIT")
dataspace[latest].immediate = true

Dictionary.colon("DODOES")
  addWords("R> XT! EXIT")  -- Ends the calling word (CREATEing) early.

Dictionary.colonWithLabel("DOES>", "_DOES")
  addWords("LIT")
  addNumber(Dictionary.find("DODOES"))
  addWords("COMPILE, COMPILE-DOCOL EXIT")
dataspace[latest].immediate = true

function unaryOp(name, label, op)
  Dictionary.nativeWithLabel(name, label, function()
    local a = datastack:pop()
    datastack:push(op(a) & 0xFFFF)
    return nextIp()
  end)
end

-- TODO: Maybe pull these out into a mathops.lua file?
unaryOp("NEGATE", "NEGATE", function(a)
  return -a
end)

unaryOp("INVERT", "INVERT", function(a)
  return ~a
end)

function binaryOpWithLabel(name, label, op)
  Dictionary.nativeWithLabel(name, label, function()
    local b = datastack:pop()
    local a = datastack:pop()
    datastack:push(op(a,b) & 0xFFFF)
    return nextIp()
  end)
end

function binaryOp(name, op)
  binaryOpWithLabel(name, name, op)
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

binaryOpWithLabel("-", "_MINUS", function(a,b)
  return a - b
end)

binaryOpWithLabel("+", "_PLUS", function(a,b)
  return a + b
end)

function binaryCmpOp(name, label, op)
  Dictionary.nativeWithLabel(name, label, function()
    local b = datastack:pop()
    local a = datastack:pop()
    datastack:push(op(a,b) and 0xFFFF or 0)
    return nextIp()
  end)
end

binaryCmpOp("=", "_EQ", function(a, b)
  return a == b
end)

binaryCmpOp("<", "_LT", function(a, b)
  return a < b
end)

binaryCmpOp(">", "_GT", function(a, b)
  return a > b
end)

binaryCmpOp("<=", "_LTE", function(a, b)
  return a <= b
end)

binaryCmpOp(">=", "_GTE", function(a, b)
  return a >= b
end)

binaryCmpOp("<>", "_NE", function(a, b)
  return a ~= b
end)

do
  Dictionary.colonWithLabel(":", "_COLON")
  addWords("CREATEDOCOL ] EXIT")
end

do
  Dictionary.colonWithLabel(";", "_SEMICOLON")
  addWords("[ LIT")
  addNumber(Dictionary.find("EXIT"))
  -- Also need to make the word visible now.
  addWords("COMPILE, EXIT")
  dataspace[latest].immediate = true
end

Dictionary.colonWithLabel("DO.\"", "_DO_STRING")
do
  local loop = here
  addWords("R> DUP 1+ >R @ DUP EMIT LIT")
  addNumber(string.byte('"'))
  addWords("= BRANCH0")
  addNumber(loop)
  addWords("EXIT")
end

Dictionary.colonWithLabel(".\"", "_STRING")
do
  addWords("LIT")
  addNumber(Dictionary.find("DO.\""))
  addWords("COMPILE,")
  local loop = here
  addWords("KEY DUP COMPILE, LIT")
  addNumber(string.byte('"'))
  addWords("= BRANCH0")
  addNumber(loop)
  addWords("EXIT")
end
dataspace[latest].immediate = true

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
  addWords("COMPILE, LIT")
  addNumber(0)
  addWord("BRANCH0")
  addNumber(loop)

  dataspace[eofBranchAddr] = here
  addWord("EXIT")
end

ip = here -- start on TEST, below
addWord("QUIT")
addWord("BYE")

print("latest: "..latest)
print("here: "..here)

-- TODO: Should probably be a Dataspace method.
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

printDataspace()

nextIp()

printDataspace()

datastack:print()

snesAssembly()
