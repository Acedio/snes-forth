#!/usr/bin/lua

local Stack = require("stack")
local Input = require("input")
local Dataspace = require("dataspace")

local datastack = Stack:new()
local returnstack = Stack:new()

assert(#arg == 2, "Two arguments are required: ./snes-forth.lua [input] [output]")

local input = nil
if arg[1] == "-" then
  input = Input:stdin()
else
  input = Input:readAll(arg[1])
end

local outputs = io.stderr
local infos = io.stderr
local errors = io.stderr

local dataspace = Dataspace:new()

local ip = 0

function nextIp()
  local oldip = ip
  ip = ip + 1
  local call = dataspace[oldip]
  assert(call.type == "call", "Expected call at addr " .. oldip)

  local callee = dataspace[call.addr]
  infos:write("oldIp: " .. oldip .. " (" .. callee:toString() .. ") newIp: " .. ip .. "\n")
  assert(callee.type == "native", "Uncallable address " .. call.addr .. " at address " .. oldip)
  return callee.runtime()
end

function docol(dataaddr)
  returnstack:push(ip)
  ip = dataaddr -- TODO: Also, alignment?
  return nextIp()
end

function addColonWithLabel(name, label)
  dataspace:dictionaryAdd(name)
  local native = Dataspace.native{
    name = name,
    size = function() assert(false, "Tried to get the size of a colon def.") end,
    label = label,
    asm = function() return "; DOCOL has no codeword.\n" end,
  }
  dataspace:add(native)
  local dataaddr = dataspace.here
  native.runtime = function()
    return docol(dataaddr)
  end
end

function addColon(name)
  addColonWithLabel(name, name)
end

dataspace:addNative{name="DATASPACE", runtime=function()
  dataspace:print(io.stderr)
  return nextIp()
end}

dataspace:addNative{name=".S", label="_DOT_S", runtime=function()
  datastack:print(outputs)
  return nextIp()
end}

-- Set the XT for the latest word to start a docol at addr
-- TODO: How will this work on the SNES?
dataspace:addNative{name="XT!", label="_XT_STORE", runtime=function()
  -- TODO: datastack tags?
  local addr = datastack:pop()
  local dataaddr = Dataspace.toCodeword(dataspace.latest) + 1
  dataspace[Dataspace.toCodeword(dataspace.latest)].runtime = function()
    datastack:push(dataaddr)
    return dataspace[addr].runtime()
  end
  return nextIp()
end}

dataspace:addNative{name="COMPILE-DOCOL", label="_COMPILE_DOCOL", runtime=function()
  local entry = Dataspace.native{
    name = "docol-fn",
  }
  dataspace:add(entry)
  local addr = dataspace.here
  function entry:runtime() docol(addr) end
  return nextIp()
end}

dataspace:addNative{name=",", label="_COMMA", runtime=function()
  dataspace:addNumber(datastack:pop())
  return nextIp()
end}

dataspace:addNative{name="CREATE", runtime=function()
  local name = input:word()
  dataspace:dictionaryAdd(name)
  local entry = Dataspace.native{
    name = name,
  }
  dataspace:add(entry)  -- Use a placeholder fn initially.
  local dataaddr = dataspace.here  -- HERE has been updated by calling native()
  -- Now update the fn with the new HERE.
  entry.runtime = function()
    datastack:push(dataaddr)
    return nextIp()
  end
  return nextIp()
end}

dataspace:addNative{name="CREATEDOCOL", runtime=function()
  local name = input:word()
  addColon(name)
  return nextIp()
end}

-- TODO: Currently only for words, need another for addresses.
function makeVariable(name)
  dataspace:dictionaryAdd(name)
  local native = Dataspace.native{name=name}
  dataspace:add(native)
  local dataaddr = dataspace.here
  native.runtime = function()
    datastack:push(dataaddr)
    return nextIp()
  end
  dataspace:addNumber(0)
end

makeVariable("STATE")

dataspace:addNative{name="ALLOT", runtime=function()
  dataspace.here = dataspace.here + datastack:pop()
  return nextIp()
end}

-- TODO: For now we'll actually implement EXIT in ASM, but on the SNES it should
-- just be a `RSL` and not `JSL EXIT` like other Forth words.
dataspace:addNative{name="EXIT", runtime=function()
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

dataspace:addNative{name=".", label="_DOT", runtime=function()
  outputs:write(datastack:pop() .. "\n")
  return nextIp()
end}

dataspace:addNative{name="BYE", runtime=function()
  infos:write("WE DONE!" .. "\n")
  -- BYE ends the program by not calling nextIp
end}

dataspace:addNative{name="EMIT", runtime=function()
  outputs:write(string.char(datastack:pop()))
  return nextIp()
end}

dataspace:addNative{name="WORD", runtime=function()
  datastack:push(input:word() or "")
  return nextIp()
end}

dataspace:addNative{name="PEEK", runtime=function()
  datastack:push(input:peek())
  return nextIp()
end}

dataspace:addNative{name="KEY", runtime=function()
  datastack:push(input:key())
  return nextIp()
end}

-- Can probably be written in Forth? Though not interpreted-Forth.
dataspace:addNative{name="FIND", runtime=function()
  local word = datastack:pop()
  local dictAddr = dataspace:dictionaryFind(word)
  if not dictAddr then
    -- TODO: This should be a string pointer or something.
    datastack:push(word)
    datastack:push(0)
  elseif dataspace[dictAddr].immediate then
    datastack:push(Dataspace.toCodeword(dictAddr))
    datastack:push(1)
  else
    datastack:push(Dataspace.toCodeword(dictAddr))
    datastack:push(-1)
  end
  return nextIp()
end}

-- TODO: Non-standard.
dataspace:addNative{name=">NUMBER", label="_TO_NUMBER", runtime=function()
  datastack:push(tonumber(datastack:pop()) or 0)
  return nextIp()
end}

dataspace:addNative{name="DUP", runtime=function()
  datastack:push(datastack:top())
  return nextIp()
end,
asm=function() return [[
  lda 1,X
  PUSH_A
]] end}

dataspace:addNative{name="A.DUP", label="_A_DUP", runtime=function()
  datastack:push(datastack:top())
  return nextIp()
end}

dataspace:addNative{name="DROP", runtime=function()
  datastack:pop()
  return nextIp()
end,
asm=function() return [[
  inx
  inx
]] end}

dataspace:addNative{name="COMPILE,", label="_COMPILE_COMMA", runtime=function()
  dataspace:addCall(datastack:pop())
  return nextIp()
end}

-- TODO: Not standard.
dataspace:addNative{name="COUNT", runtime=function()
  local str = datastack:pop()
  datastack:push(string.len(str))
  return nextIp()
end}

-- Move a 2-byte word from from data stack to the R stack.
dataspace:addNative{name=">R", label="_TO_R", runtime=function()
  returnstack:push(datastack:pop())
  return nextIp()
end}

-- Move a 3-byte address from from data stack to the R stack.
dataspace:addNative{name="A.>R", label="_A_TO_R", runtime=function()
  returnstack:push(datastack:pop())
  return nextIp()
end}

dataspace:addNative{name="R>", label="_FROM_R", runtime=function()
  datastack:push(returnstack:pop())
  return nextIp()
end}

dataspace:addNative{name="A.R>", label="_A_FROM_R", runtime=function()
  datastack:push(returnstack:pop())
  return nextIp()
end}

function toSigned(unsigned)
  if unsigned > 0x7FFF then
    return unsigned - 0x10000
  end
  return unsigned
end

function toUnsigned(signed)
  if unsigned < 0 then
    return (signed + 0x10000) & 0xFFFF
  end
  return signed
end

dataspace:addNative{name="BRANCH0", runtime=function()
  if datastack:pop() == 0 then
    assert(dataspace[ip].type == "number", "Expected relative number to jump to at " .. ip)
    ip = dataspace:fromRelativeAddress(ip, toSigned(dataspace[ip].number))
  else
    -- Skip past the relative address.
    ip = ip + 1
  end
  return nextIp()
end}

-- Takes an address (3 bytes) off the stack and pushes a 2 byte word.
dataspace:addNative{name="@", label="_FETCH", runtime=function()
  local addr = datastack:pop()
  assert(dataspace[addr].type == "number", "Expected word at " .. addr)
  datastack:push(dataspace[addr].number)
  return nextIp()
end}

dataspace:addNative{name="!", label="_STORE", runtime=function()
  local addr = datastack:pop()
  local val = datastack:pop()
  dataspace[addr] = Dataspace.number(val)
  return nextIp()
end}

dataspace:addNative{name="1+", label="_INCR", runtime=function()
  datastack:push(datastack:pop() + 1)
  return nextIp()
end}

dataspace:addNative{name="A.1+", label="_A_INCR", runtime=function()
  datastack:push(datastack:pop() + 1)
  return nextIp()
end}

dataspace:addNative{name="LIT", runtime=function()
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

dataspace:addNative{name="A.LIT", label="_A_LIT", runtime=function()
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

dataspace:addNative{name="EXECUTE", runtime=function()
  local addr = datastack:pop()
  infos:write("Executing " .. dataspace[addr].name .. "\n")
  return dataspace[addr].runtime()
  -- No nextIp() is needed because the runtime() should call it.
end}

addColon("TRUE")
  dataspace:addWord("LIT")
  dataspace:addNumber(0xFFFF)
  dataspace:addWord("EXIT")

addColon("FALSE")
  dataspace:addWord("LIT")
  dataspace:addNumber(0)
  dataspace:addWord("EXIT")

addColon("CR")
  dataspace:addWord("LIT")
  dataspace:addNumber(string.byte("\n"))
  dataspace:addWords("EMIT EXIT")

addColonWithLabel("[", "_LBRACK")
  dataspace:addWords("FALSE STATE ! EXIT")

addColonWithLabel("]", "_RBRACK")
  dataspace:addWords("TRUE STATE ! EXIT")
dataspace[dataspace.latest].immediate = true

addColon("DODOES")
  dataspace:addWords("R> XT! EXIT")  -- Ends the calling word (CREATEing) early.

addColonWithLabel("DOES>", "_DOES")
  dataspace:addWords("A.LIT")
  dataspace:addAddress(dataspace:codewordOf("DODOES"))
  dataspace:addWords("COMPILE, COMPILE-DOCOL EXIT")
dataspace[dataspace.latest].immediate = true

function unaryOp(name, label, op)
  dataspace:addNative{name=name, label=label, runtime=function()
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
  dataspace:addNative{name=name, label=label, runtime=binaryOpRt(op)}
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

dataspace:addNative{name="+", label="_PLUS", runtime=binaryOpRt(function(a,b)
  return a + b
end), asm=function(self) return [[
  POP_A
  clc
  adc a:1, X ; Add stack value
  sta a:1, X
  rtl
]] end}

function binaryCmpOp(name, label, op)
  dataspace:addNative{name=name, label=label, runtime=function()
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
  addColonWithLabel(":", "_COLON")
  dataspace:addWords("CREATEDOCOL ] EXIT")
end

do
  addColonWithLabel(";", "_SEMICOLON")
  dataspace:addWords("[ A.LIT")
  dataspace:addAddress(dataspace:codewordOf("EXIT"))
  -- Also need to make the word visible now.
  dataspace:addWords("COMPILE, EXIT")
  dataspace[dataspace.latest].immediate = true
end

addColonWithLabel("DO.\"", "_DO_STRING")
do
  local loop = dataspace.here
  dataspace:addWords("A.R> A.DUP A.1+ A.>R @ DUP EMIT LIT")
  dataspace:addNumber(string.byte('"'))
  dataspace:addWords("= BRANCH0")
  dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace:addWords("EXIT")
end

addColonWithLabel(".\"", "_STRING")
do
  dataspace:addWords("A.LIT")
  dataspace:addAddress(dataspace:codewordOf("DO.\""))
  dataspace:addWords("COMPILE,")
  local loop = dataspace.here
  dataspace:addWords("KEY DUP COMPILE, LIT")
  dataspace:addNumber(string.byte('"'))
  dataspace:addWords("= BRANCH0")
  dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace:addWords("EXIT")
end
dataspace[dataspace.latest].immediate = true

do
  addColon("QUIT")
  local loop = dataspace.here
  dataspace:addWords("WORD DUP COUNT BRANCH0")
  local eofBranchAddr = dataspace.here
  dataspace:addNumber(2000)

  dataspace:addWords("FIND")

  dataspace:addWords("DUP LIT")
  dataspace:addNumber(0)
  dataspace:addWords("= BRANCH0")
  local notNumberBranchAddr = dataspace.here
  dataspace:addNumber(2000) -- will be replaced later
    -- Not found, try and parse as a number.
    -- TODO: Handle parse failure here, currently just returns zero.
    dataspace:addWords("DROP >NUMBER")
    -- If we're compiling, compile TOS as a literal.
    dataspace:addWords("STATE @ BRANCH0")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
    -- LIT the LIT so we can LIT while we LIT.
    dataspace:addWord("A.LIT")
    dataspace:addAddress(dataspace:codewordOf("LIT"))
    -- Compile LIT and then the number.
    dataspace:addWords("COMPILE, ,")
    dataspace:addWord("LIT")
    dataspace:addNumber(0)
    dataspace:addWord("BRANCH0")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace[notNumberBranchAddr].number = dataspace:getRelativeAddr(notNumberBranchAddr, dataspace.here)

  dataspace:addWords("DUP LIT")
  dataspace:addNumber(0)
  dataspace:addWords("> STATE @ INVERT OR BRANCH0")
  local branchAddrIfNotImmediate = dataspace.here
  dataspace:addNumber(2000) -- will be replaced later
    -- Interpreting, just run the word.
    dataspace:addWords("DROP EXECUTE LIT")
    dataspace:addNumber(0)
    dataspace:addWord("BRANCH0")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace[branchAddrIfNotImmediate].number = dataspace:getRelativeAddr(branchAddrIfNotImmediate, dataspace.here)

  dataspace:addWords("DROP")  -- else, compiling
  dataspace:addWords("COMPILE, LIT")
  dataspace:addNumber(0)
  dataspace:addWord("BRANCH0")
  dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))

  dataspace[eofBranchAddr].number = dataspace:getRelativeAddr(eofBranchAddr, dataspace.here)
  dataspace:addWord("EXIT")
end

ip = dataspace.here -- start on creating STATE, below
dataspace:addWord("QUIT")
dataspace:addWord("BYE")

infos:write("latest: " .. dataspace.latest .. "\n")
infos:write("here: " .. dataspace.here .. "\n")

dataspace:print(io.stderr)

nextIp()

dataspace:print(io.stderr)

datastack:print(io.stderr)

local output = assert(io.open(arg[2], "w"))
dataspace:assembly(output)
