#!/usr/bin/lua

local Stack = require("stack")
local Input = require("input")

local datastack = Stack:new()
local returnstack = Stack:new()

local latest = 0
local ip = 0

local input = Input:stdin()

local outputs = io.stderr
local infos = io.stderr
local errors = io.stderr

local function Address(addr)
  return {type = "address", addr = addr}
end

local dataspace = {}

-- HERE is the DATASPACE pointer
local here = #dataspace + 1

-- Print dataspace.
function printDataspace(file)
  for k,v in ipairs(dataspace) do
    file:write(k .. ": " .. cellString(v) .. "\n")
  end
end

function snesAssembly(file)
  for k,v in ipairs(dataspace) do
    assert(type(v) == "table" or v.type == nil, "Invalid entry at addr = " .. k)
    if v.type == "native" or v.type == "colon" then
      if v.label then
        file:write(string.format("%s:\n", v.label))
      end
      if v.asm then
        file:write(v.asm())
      else
        file:write("; TODO: Not implemented\n; TODO: abort?\n")
      end
    elseif v.type == "call" then
      assert(v.addr > 0 and v.addr < here, "Invalid address " .. v.addr .. " at addr " .. k)
      assert(dataspace[v.addr].type == "native" or dataspace[v.addr].type == "colon", "Expected fn at " .. v.addr .. ", referenced from addr " .. k)
      file:write(string.format("JSL %s\n", dataspace[v.addr].label))
    elseif v.type == "address" then
      assert(v.addr > 0, "Invalid address " .. v.addr .. " at addr " .. k)
      if dataspace[v.addr].label then
        file:write(string.format(".FARADDR %s\n", dataspace[v.addr].label))
      else
        -- TODO: This doesn't work, we need to calculate the address.
        file:write(string.format(".FARADDR %d\n", v.addr))
      end
    elseif v.type == "number" then
      file:write(string.format(".WORD %d\n", v.number & 0xFFFF))
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
  local ref = dataspace[oldip]
  assert(ref.type == "call", "Expected call at addr " .. oldip)

  local callee = dataspace[ref.addr]
  infos:write("oldIp: " .. oldip .. " (" .. cellString(callee) .. ") newIp: " .. ip .. "\n")
  assert(callee.type == "native" or callee.type == "colon", "Uncallable address " .. ref.addr .. " at address " .. oldip)
  return callee.runtime()
end

-- Table should have at least name and runtime specified.
-- TODO: Maybe we can also support inlining by specifying an `inline` field
-- that, if specified, overrides the Forth word call and instead causes code to
-- be added directly. e.g. LIT would be
--   lda #LITERAL_NUM
--   PUSH_A
-- instead of the usual
--   JSL LIT
--   .WORD LITERNAL_NUM
-- which is a lot slower.
function Dictionary.native(entry)
  entry.type = "native"
  entry.prev = latest
  if not entry.label then
    entry.label = entry.name
  end
  dataspace[here] = entry
  latest = here
  here = here + DICTIONARY_HEADER_SIZE
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
    type = "colon",
    label = label,
    runtime = function()
      return docol(dataaddr)
    end,
    asm = function() return "; DOCOL has no codeword.\n" end,
    prev = latest,
  }
  latest = here
  here = here + DICTIONARY_HEADER_SIZE
end

function Dictionary.colon(name)
  Dictionary.colonWithLabel(name, name)
end

Dictionary.native{name="DATASPACE", runtime=function()
  printDataspace(io.stderr)
  return nextIp()
end}

Dictionary.native{name=".S", label="_DOT_S", runtime=function()
  datastack:print(errors)
  return nextIp()
end}

-- Set the XT for the latest word to start a docol at addr
-- TODO: How will this work on the SNES?
Dictionary.native{name="XT!", label="_XT_STORE", runtime=function()
  -- TODO: datastack tags?
  local addr = datastack:pop()
  local dataaddr = latest + 1
  dataspace[latest].runtime = function()
    datastack:push(dataaddr)
    return dataspace[addr].runtime()
  end
  return nextIp()
end}

Dictionary.native{name="COMPILE-DOCOL", label="_COMPILE_DOCOL", runtime=function()
  local addr = here + DICTIONARY_HEADER_SIZE
  dataspace[here] = {
    name = "docol-fn",
    type = "docol",
    label = nil,
    runtime = function()
      docol(addr)
    end,
    -- No prev because this isn't a dictionary entry.
  }
  here = here + DICTIONARY_HEADER_SIZE
  return nextIp()
end}

Dictionary.native{name=",", label="_COMMA", runtime=function()
  dataspace[here] = {
    type = "number",
    number = datastack:pop(),
  }
  here = here + 1
  return nextIp()
end}

Dictionary.native{name="CREATE", runtime=function()
  local addr = here
  local name = input:word()
  Dictionary.native{name=name}  -- Use a placeholder fn initially.
  local dataaddr = here  -- HERE has been updated by calling native()
  -- Now update the fn with the new HERE.
  dataspace[addr].runtime = function()
    datastack:push(dataaddr)
    return nextIp()
  end
  return nextIp()
end}

Dictionary.native{name="CREATEDOCOL", runtime=function()
  local name = input:word()
  Dictionary.colon(name)
  return nextIp()
end}

-- TODO: Currently only for words, need another for addresses.
function Dictionary.makeVariable(name)
  local addr = here
  Dictionary.native{name=name}
  local dataaddr = here
  dataspace[addr].runtime = function()
    datastack:push(dataaddr)
    return nextIp()
  end
  -- initialize the var
  dataspace[here] = {
    type = "number",
    number = 0,
  }
  -- space for the var
  here = here + 1
end

Dictionary.makeVariable("STATE")

-- TODO: For now we'll actually implement EXIT in ASM, but on the SNES it should
-- just be a `RSL` and not `JSL EXIT` like other Forth words.
Dictionary.native{name="EXIT", runtime=function()
  ip = returnstack:pop()
  return nextIp()
end,
asm=function() return [[
  ; Remove the caller's return address (3 bytes, hence the sep) and return.
  tsa
  clc
  adc #3
  tas
  rts
]] end}

Dictionary.native{name=".", label="_DOT", runtime=function()
  outputs:write(datastack:pop() .. "\n")
  return nextIp()
end}

Dictionary.native{name="BYE", runtime=function()
  infos:write("WE DONE!" .. "\n")
  -- BYE ends the program by not calling nextIp
end}

-- Add word to the current colon defintion
function addWord(name)
  index = Dictionary.find(name)
  assert(index, "Couldn't find " .. name)
  addCall(index)
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

function addCall(addr)
  dataspace[here] = {
    type = "call",
    addr = addr,
  }
  here = here + 1
end

function addAddress(addr)
  dataspace[here] = {
    type = "address",
    addr = addr,
  }
  here = here + 1
end

function addNumber(number)
  dataspace[here] = {
    type = "number",
    number = number,
  }
  here = here + 1
end

Dictionary.native{name="EMIT", runtime=function()
  outputs:write(string.char(datastack:pop()))
  return nextIp()
end}

Dictionary.native{name="WORD", runtime=function()
  datastack:push(input:word() or "")
  return nextIp()
end}

Dictionary.native{name="PEEK", runtime=function()
  datastack:push(input:peek())
  return nextIp()
end}

Dictionary.native{name="KEY", runtime=function()
  datastack:push(input:key())
  return nextIp()
end}

-- Can probably be written in Forth? Though not interpreted-Forth.
Dictionary.native{name="FIND", runtime=function()
  local word = datastack:pop()
  local index = Dictionary.find(word)
  if not index then
    -- TODO: This should be a string pointer or something.
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
end}

-- TODO: Non-standard.
Dictionary.native{name=">NUMBER", label="_TO_NUMBER", runtime=function()
  datastack:push(tonumber(datastack:pop()) or 0)
  return nextIp()
end}

Dictionary.native{name="DUP", runtime=function()
  datastack:push(datastack:top())
  return nextIp()
end,
asm=function() return [[
  lda 1,X
  PUSH_A
]] end}

Dictionary.native{name="DROP", runtime=function()
  datastack:pop()
  return nextIp()
end,
asm=function() return [[
  inx
  inx
]] end}

Dictionary.native{name="COMPILE,", label="_COMPILE_COMMA", runtime=function()
  addCall(datastack:pop())
  return nextIp()
end}

-- TODO: Not standard.
Dictionary.native{name="COUNT", runtime=function()
  local str = datastack:pop()
  datastack:push(string.len(str))
  return nextIp()
end}

-- TODO: How should this behave given the different bit width's of the stacks?
-- Probably just have >R deal with words and A.>R deal with addresses.
Dictionary.native{name=">R", label="_TO_R", runtime=function()
  returnstack:push(datastack:pop())
  return nextIp()
end}

Dictionary.native{name="R>", label="_FROM_R", runtime=function()
  datastack:push(returnstack:pop())
  return nextIp()
end}

Dictionary.native{name="BRANCH0", runtime=function()
  if datastack:pop() == 0 then
    assert(dataspace[ip].type == "address", "Expected address to jump to at " .. ip)
    ip = dataspace[ip].addr
  else
    ip = ip + 1
  end
  return nextIp()
end}

-- Takes an address (3 bytes) off the stack and pushes a 2 byte word.
Dictionary.native{name="@", label="_FETCH", runtime=function()
  local addr = datastack:pop()
  assert(dataspace[addr].type == "number", "Expected word at " .. addr)
  datastack:push(dataspace[addr].number)
  return nextIp()
end}

Dictionary.native{name="!", label="_STORE", runtime=function()
  local addr = datastack:pop()
  local val = datastack:pop()
  dataspace[addr] = {
    type = "number",
    number = val,
  }
  return nextIp()
end}

Dictionary.native{name="1+", label="_INCR", runtime=function()
  datastack:push(datastack:pop() + 1)
  return nextIp()
end}

Dictionary.native{name="LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litaddr = ip
  -- increment the return address to skip the literal
  ip = ip + 1
  assert(dataspace[litaddr].type == "number", "Expected number for LIT at addr = " .. litaddr)
  datastack:push(dataspace[litaddr].number)
  return nextIp()
end,
-- TODO: calls to LIT should probably just be inlined :P
asm=function() return [[
  ; We have the 24 bit return address on the stack, need to grab that value to a
  ; DP location (it's already in the DP because it's on the stack, but we need
  ; to pull it to a static location because that's the only indirect long
  ; addressing that exists) and increment it, then do a LDA indirect long
  ; addressing to grab the actual literal value.
  ;
  ; Can we do something silly like treating the return stack like the DP?
  dex ; make room for the literal word
  dex
  tsc
  tcd ; set the DP to the return stack

  ldy #1
  lda [1],Y ; indirect long read the address on the top of the stack + 1
  sta f:1,X ; TODO: Could save a byte here if we can use data page addressing.

  lda #0
  tcd ; reset DP before we PUSH

  ; Increment return address past the literal word
  lda #2
  clc
  adc 1, S
  sta 1, S
  ; TODO: handle the carry here

  rtl
]] end}

Dictionary.native{name="A.LIT", label="A_LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litaddr = ip
  -- increment the return address to skip the literal
  ip = ip + 1
  assert(dataspace[litaddr].type == "address", "Expected address for LIT at addr = " .. litaddr)
  datastack:push(dataspace[litaddr].addr)
  return nextIp()
end,
-- TODO: calls to A.LIT should probably just be inlined :P
-- TODO: Test this.
asm=function() return [[
  ; We have the 24 bit return address on the stack, need to grab that value to a
  ; DP location (it's already in the DP because it's on the stack, but we need
  ; to pull it to a static location because that's the only indirect long
  ; addressing that exists) and increment it, then do a LDA indirect long
  ; addressing to grab the actual literal value.
  ;
  ; Can we do something silly like treating the return stack like the DP?
  dex ; make room for the literal address
  dex
  dex
  tsc
  tcd
  ldy #1
  lda [1], Y
  sta z:1, X
  iny
  lda [1], Y
  sta z:2, X

  lda z:1
  clc
  adc #3
  ; TODO: Need to check for carry
  sta z:1

  lda #0
  tcd
  rtl
]] end}

Dictionary.native{name="EXECUTE", runtime=function()
  return dataspace[datastack:pop()].runtime()
  -- No nextIp() is needed because the runtime() should call it.
end}

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
  addWords("A.LIT")
  addAddress(Dictionary.find("DODOES"))
  addWords("COMPILE, COMPILE-DOCOL EXIT")
dataspace[latest].immediate = true

function unaryOp(name, label, op)
  Dictionary.native{name=name, label=label, runtime=function()
    local a = datastack:pop()
    datastack:push(op(a) & 0xFFFF)
    return nextIp()
  end}
end

-- TODO: Maybe pull these out into a mathops.lua file?
unaryOp("NEGATE", "NEGATE", function(a)
  return -a
end)

unaryOp("INVERT", "INVERT", function(a)
  return ~a
end)

function binaryOpRt(op)
  return function()
    local b = datastack:pop()
    local a = datastack:pop()
    datastack:push(op(a,b) & 0xFFFF)
    return nextIp()
  end
end

function binaryOpWithLabel(name, label, op)
  Dictionary.native{name=name, label=label, runtime=binaryOpRt(op)}
end

function binaryOp(name, op)
  binaryOpWithLabel(name, name, op)
end

binaryOpWithLabel("AND", "_AND", function(a,b)
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

Dictionary.native{name="+", label="_PLUS", runtime=binaryOpRt(function(a,b)
  return a + b
end), asm=function() return [[
  POP_A
  clc
  adc a:1, X ; Add stack value
  sta a:1, X
  rtl
]] end}

function binaryCmpOp(name, label, op)
  Dictionary.native{name=name, label=label, runtime=function()
    local b = datastack:pop()
    local a = datastack:pop()
    datastack:push(op(a,b) and 0xFFFF or 0)
    return nextIp()
  end}
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
  addWords("[ A.LIT")
  addAddress(Dictionary.find("EXIT"))
  -- Also need to make the word visible now.
  addWords("COMPILE, EXIT")
  dataspace[latest].immediate = true
end

Dictionary.colonWithLabel("DO.\"", "_DO_STRING")
do
  local loop = here
  addWords("A.R> A.DUP A.1+ A.>R @ DUP EMIT LIT")
  addNumber(string.byte('"'))
  addWords("= BRANCH0")
  addAddress(loop)
  addWords("EXIT")
end

Dictionary.colonWithLabel(".\"", "_STRING")
do
  addWords("A.LIT")
  addAddress(Dictionary.find("DO.\""))
  addWords("COMPILE,")
  local loop = here
  addWords("KEY DUP COMPILE, LIT")
  addNumber(string.byte('"'))
  addWords("= BRANCH0")
  addAddress(loop)
  addWords("EXIT")
end
dataspace[latest].immediate = true

do
  Dictionary.colon("QUIT")
  local loop = here
  addWords("WORD DUP COUNT BRANCH0")
  local eofBranchAddr = here
  addAddress(2000)

  addWords("FIND")

  addWords("DUP LIT")
  addNumber(0)
  addWords("= BRANCH0")
  local notNumberBranchAddr = here
  addAddress(2000) -- will be replaced later
    -- Not found, try and parse as a number.
    -- TODO: Handle parse failure here, currently just returns zero.
    addWords("DROP >NUMBER")
    -- If we're compiling, compile TOS as a literal.
    addWords("STATE @ BRANCH0")
    addAddress(loop)
    -- LIT the LIT so we can LIT while we LIT.
    addWord("A.LIT")
    addAddress(Dictionary.find("LIT"))
    -- Compile LIT and then the number.
    addWords("COMPILE, ,")
    addWord("LIT")
    addNumber(0)
    addWord("BRANCH0")
    addAddress(loop)
  dataspace[notNumberBranchAddr].addr = here

  addWords("DUP LIT")
  addNumber(0)
  addWords("> STATE @ INVERT OR BRANCH0")
  local branchAddrIfNotImmediate = here
  addAddress(2000) -- will be replaced later
    -- Interpreting, just run the word.
    addWords("DROP EXECUTE LIT")
    addNumber(0)
    addWord("BRANCH0")
    addAddress(loop)
  dataspace[branchAddrIfNotImmediate].addr = here

  addWords("DROP")  -- else, compiling
  addWords("COMPILE, LIT")
  addNumber(0)
  addWord("BRANCH0")
  addAddress(loop)

  dataspace[eofBranchAddr].addr = here
  addWord("EXIT")
end

ip = here -- start on QUIT, below
addWord("QUIT")
addWord("BYE")

infos:write("latest: "..latest .. "\n")
infos:write("here: "..here .. "\n")

-- TODO: Should probably be a Dataspace method.
function cellString(contents)
  assert(type(contents) == "table" and contents.type ~= nil)
  if contents.type == "call" then
    assert(contents.addr > 0 and contents.addr < here, "Invalid address " .. contents.addr )
    assert(dataspace[contents.addr].type == "native" or dataspace[contents.addr].type == "colon", "Expected fn at " .. contents.addr)
    if dataspace[contents.addr].name ~= nil then
      return "Call " .. dataspace[contents.addr].name .. " (" .. contents.addr .. ")"
    else
      return "Unnamed fn at: " .. tostring(contents.addr)
    end
  elseif contents.type == "address" then
    assert(contents.addr > 0, "Invalid address " .. contents.addr )
    return "Address: " .. tostring(contents.addr)
  elseif contents.type == "number" then
    return "Number: " .. tostring(contents.number)
  elseif type(contents) == "table" and contents.name ~= nil then
    return contents.name
  else
    return "???"
  end
end

printDataspace(io.stderr)

nextIp()

printDataspace(io.stderr)

datastack:print(io.stderr)

snesAssembly(io.stdout)
