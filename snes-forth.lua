#!/usr/bin/lua

local Stack = require("stack")
local Input = require("input")
local Dataspace = require("dataspace")

local datastack = Stack:new()
local returnstack = Stack:new()

toRemove = {}
flags = {}
for i=1,#arg do
  if arg[i] == "-v" then
    flags[arg[i]] = true
    table.insert(toRemove, i)
  elseif arg[i] == "-" then
    -- "-" is parsed as reading from stdin
  else
    assert(string.sub(arg[i],1,1) ~= "-", "Unrecognized flag: " .. arg[i])
  end
end
for _, i in ipairs(toRemove) do
  table.remove(arg, i)
end

assert(#arg == 2, "Two arguments are required: ./snes-forth.lua [input] [output]")

local input = nil
if arg[1] == "-" then
  input = Input:stdin()
else
  input = Input:readAll(arg[1])
end

local outputs = io.stderr
local infos = io.stdout
local errors = io.stderr

local dataspace = Dataspace:new()

local ip = 0

local debugEntry = Dataspace.number(0)
if flags["-v"] then
  debugEntry = Dataspace.number(0xFFFF)
end

function debugging()
  return debugEntry.number ~= 0
end

function nextIp()
  local oldip = ip
  ip = ip + 1
  local call = dataspace[oldip]
  assert(call.type == "call", "Expected call at addr " .. oldip)

  local callee = dataspace[call.addr]
  if debugging() then
    infos:write("oldIp: " .. oldip .. " (" .. callee:toString() .. ") newIp: " .. ip .. "\n")
    datastack:print(infos)
  end
  assert(callee.type == "native", "Uncallable address " .. call.addr .. " at address " .. oldip)
  return callee.runtime()
end

function docol(dataaddr)
  returnstack:pushAddress(ip)
  ip = dataaddr -- TODO: Also, alignment?
  return nextIp()
end

function addColonWithLabel(name, label)
  dataspace:dictionaryAdd(name)
  local native = Dataspace.native{
    name = name,
    size = function() assert(false, "Tried to get the size of a colon def.") end,
    label = label,
    asm = function() return "; Colon definition." end,
  }
  dataspace:add(native)
  local dataaddr = dataspace.here
  native.runtime = function()
    return docol(dataaddr)
  end
end

function addColon(name)
  addColonWithLabel(name, Dataspace.defaultLabel(name))
end

-- TODO: Should this be a 2 byte or 4 byte address if we switch to 1-word
-- addressing?
dataspace:addNative{name="HERE", runtime=function()
  datastack:pushAddress(dataspace.here)
  return nextIp()
end}

dataspace:addNative{name="DATASPACE", runtime=function()
  dataspace:print(outputs)
  return nextIp()
end}

dataspace:addNative{name="DEPTH", runtime=function()
  datastack:pushWord(datastack:entries())
  return nextIp()
end,
asm=function() return [[
  txa
  eor #$FFFF
  inc A
  clc
  adc #DATA_STACK_ADDR
  PUSH_A
  rtl
]] end}

dataspace:addNative{name=".S", label="_DOT_S", runtime=function()
  datastack:print(outputs)
  return nextIp()
end}

-- Set the XT for the latest word to start a docol at addr
-- TODO: How will this work on the SNES?
dataspace:addNative{name="XT!", label="_XT_STORE", runtime=function()
  local addr = datastack:popAddress()
  local dataaddr = Dataspace.toCodeword(dataspace.latest) + 1
  dataspace[Dataspace.toCodeword(dataspace.latest)].runtime = function()
    datastack:pushAddress(dataaddr)
    return dataspace[addr].runtime()
  end
  return nextIp()
end}

dataspace:addNative{name="COMPILE-DOCOL", runtime=function()
  local entry = Dataspace.native{
    name = "docol-fn",
  }
  dataspace:add(entry)
  local addr = dataspace.here
  function entry:runtime() docol(addr) end
  return nextIp()
end}

dataspace:addNative{name=",", label="_COMMA", runtime=function()
  dataspace:addNumber(datastack:popWord())
  return nextIp()
end}

dataspace:addNative{name="A.,", label="_A_COMMA", runtime=function()
  dataspace:addAddress(datastack:popAddress())
  return nextIp()
end}

dataspace:addNative{name="XT,", label="_XT_COMMA", runtime=function()
  local xt = datastack:popAddress()
  dataspace:add(Dataspace.xt(xt))
  if debugging() then
    infos:write("Compiling XT " .. dataspace[xt].name .. "\n")
  end
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
    datastack:pushAddress(dataaddr)
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
function makeLowRamVariable(name, entry)
  dataspace:dictionaryAdd(name)
  local native = Dataspace.native{name=name}
  dataspace:add(native)
  local dataaddr = dataspace.here
  native.runtime = function()
    datastack:pushAddress(dataaddr)
    return nextIp()
  end
  native.asm = function() return string.format([[
    dex
    dex
    dex
    lda #.HIWORD(_%s_DATA)
    sta z:2, X
    lda #.LOWORD(_%s_DATA)
    sta z:1, X
    rtl
  .BSS
  _%s_DATA:
    .WORD $0000
  .CODE
  ]], name, name, name) end
  if not entry then
    entry = Dataspace.number(0)
  end
  dataspace:add(entry)
end

makeLowRamVariable("STATE")
makeLowRamVariable("DEBUG", debugEntry)

dataspace:addNative{name="ALLOT", runtime=function()
  dataspace.here = dataspace.here + datastack:popWord()
  return nextIp()
end}

-- TODO: For now we'll actually implement EXIT in ASM, but on the SNES it should
-- just be a `RTL` and not `JSL EXIT` like other Forth words.
dataspace:addNative{name="EXIT", runtime=function()
  ip = returnstack:popAddress()
  return nextIp()
end,
asm=function() return [[
  ; Remove the caller's return address (3 bytes) and return.
  tsa
  clc
  adc #3
  tas
  rtl
]] end}

dataspace:addNative{name=".", label="_DOT", runtime=function()
  outputs:write(datastack:popWord() .. "\n")
  return nextIp()
end}

dataspace:addNative{name="BYE", runtime=function()
  infos:write("WE DONE!" .. "\n")
  -- BYE ends the program by not calling nextIp
end}

dataspace:addNative{name="EMIT", runtime=function()
  outputs:write(string.char(datastack:popWord()))
  return nextIp()
end}

local wordBufferAddr = dataspace.here
local wordBufferSize = 32
dataspace:addNumber(0)
for i=1,wordBufferSize do
  -- TODO: Bytes?
  dataspace:addNumber(0)
end

function setWordBuffer(str)
  local length = string.len(str)
  assert(length < wordBufferSize, "Strings length too large: " .. str)
  dataspace[wordBufferAddr] = Dataspace.number(length)
  for i=1,length do
    dataspace[wordBufferAddr + i] = Dataspace.number(string.byte(string.sub(str, i, i)))
  end
end

function getCountedWord(addr)
  assert(dataspace[addr].type == "number")
  local length = dataspace[addr].number
  local str = ""
  for i=1,length do
    assert(dataspace[wordBufferAddr + i].type == "number")
    str = str .. string.char(dataspace[wordBufferAddr + i].number)
  end
  return str
end

dataspace:addNative{name="WORD", runtime=function()
  setWordBuffer(input:word() or "")
  datastack:pushAddress(wordBufferAddr)
  return nextIp()
end}

dataspace:addNative{name="PEEK", runtime=function()
  datastack:pushWord(input:peek())
  return nextIp()
end}

dataspace:addNative{name="KEY", runtime=function()
  datastack:pushWord(input:key())
  return nextIp()
end}

dataspace:addNative{name="TYPE", runtime=function()
  local str = getCountedWord(datastack:popAddress())
  outputs:write(str)
  return nextIp()
end}

-- Can probably be written in Forth? Though not interpreted-Forth.
dataspace:addNative{name="FIND", runtime=function()
  local wordAddress = datastack:popAddress()
  local word = getCountedWord(wordAddress)
  local dictAddr = dataspace:dictionaryFind(word)
  if not dictAddr then
    datastack:pushAddress(wordAddress)
    datastack:pushWord(0)
  elseif dataspace[dictAddr].immediate then
    datastack:pushAddress(Dataspace.toCodeword(dictAddr))
    datastack:pushWord(1)
  else
    datastack:pushAddress(Dataspace.toCodeword(dictAddr))
    datastack:pushWord(0xFFFF)
  end
  return nextIp()
end}

-- Non-standard. Returns TRUE or FALSE at the top of the stack.
dataspace:addNative{name=">NUMBER", label="_TO_NUMBER", runtime=function()
  local strAddress = datastack:popAddress()
  local str = getCountedWord(strAddress)
  local number = tonumber(str)
  if number == nil then
    datastack:pushWord(0)
    -- Failed.
    datastack:pushWord(0)
    return nextIp()
  end

  if number > 0xFFFF or number < -0x8000 then
    datastack:pushWord(0)
    -- Failed.
    datastack:pushWord(0)
    return nextIp()
  end

  datastack:pushWord(toUnsigned(number))
  datastack:pushWord(0xFFFF)
  return nextIp()
end}

-- Returns TRUE or FALSE at the top of the stack, and the parsed address below
-- that.
dataspace:addNative{name=">ADDRESS", label="_TO_ADDRESS", runtime=function()
  local strAddress = datastack:popAddress()
  local maybeAddress = getCountedWord(strAddress)
  if string.sub(maybeAddress, 1, 1) ~= "$" then
    datastack:pushAddress(0)
    -- Failed.
    datastack:pushWord(0)
    return nextIp()
  end

  local address = tonumber(string.sub(maybeAddress, 2), 16)
  if address == nil then
    datastack:pushAddress(0)
    -- Failed.
    datastack:pushWord(0)
    return nextIp()
  end

  if address > 0xFFFFFF or address < -0x800000 then
    datastack:pushAddress(0)
    -- Failed.
    datastack:pushWord(0)
    return nextIp()
  end

  datastack:pushAddress(address & 0xFFFFFF)
  datastack:pushWord(0xFFFF)
  return nextIp()
end}

dataspace:addNative{name="DUP", runtime=function()
  datastack:pushWord(datastack:topWord())
  return nextIp()
end,
asm=function() return [[
  lda z:1,X
  PUSH_A
  rtl
]] end}

dataspace:addNative{name="A.DUP", runtime=function()
  datastack:pushAddress(datastack:topAddress())
  return nextIp()
end,
asm=function() return [[
  dex
  dex
  dex
  lda z:4, X
  sta z:1, X
  lda z:5, X
  sta z:2, X
  rtl
]] end}

dataspace:addNative{name="DROP", runtime=function()
  datastack:popWord()
  return nextIp()
end,
asm=function() return [[
  inx
  inx
  rtl
]] end}

dataspace:addNative{name="A.DROP", runtime=function()
  datastack:popAddress()
  return nextIp()
end,
asm=function() return [[
  inx
  inx
  inx
  rtl
]] end}

dataspace:addNative{name="SWAP", runtime=function()
  local first = datastack:popWord()
  local second = datastack:popWord()
  datastack:pushWord(first)
  datastack:pushWord(second)
  return nextIp()
end,
asm=function() return [[
  ldy z:1, X
  lda z:3, X
  sta z:1, X
  sty z:3, X
  rtl
]] end}

dataspace:addNative{name="A.SWAP", runtime=function()
  local first = datastack:popAddress()
  local second = datastack:popAddress()
  datastack:pushAddress(first)
  datastack:pushAddress(second)
  return nextIp()
end,
asm=function() return [[
  ; G = garbage
  ; G 1 2 3 4 5 6
  ldy z:2, X
  lda z:5, X
  sta z:2, X
  sty z:5, X
  ; G 1 5 6 4 2 3
  lda z:0, X
  ldy z:3, X
  sty z:0, X
  ; 6 4 5 6 4 2 3
  ldy z:2, X
  sta z:3, X
  ; 6 4 5 G 1 2 3
  sty z:2, X
  ; 6 4 5 6 1 2 3
  
  rtl
]] end}

dataspace:addNative{name="COMPILE,", label="_COMPILE_COMMA", runtime=function()
  local xt = datastack:popAddress()
  dataspace:addCall(xt)
  if debugging() then
    infos:write("Compiling " .. dataspace[xt].name .. "\n")
  end
  return nextIp()
end}

-- Pushes the address of the first character of the string, then the size of the
-- string in bytes.
dataspace:addNative{name="COUNT", runtime=function()
  local addr = datastack:popAddress()
  assert(dataspace[addr].type == "number")
  local length = dataspace[addr].number
  datastack:pushAddress(addr + 1)
  datastack:pushWord(length)
  return nextIp()
end}

-- Move a 2-byte word from from data stack to the R stack.
dataspace:addNative{name=">R", label="_TO_R", runtime=function()
  returnstack:pushWord(datastack:popWord())
  return nextIp()
end,
asm=function() return [[
  ; First, move the return address two bytes back.
  lda 1, S
  pha
  lda 4, S ; Recopying the second byte again.
  sta 2, S

  POP_A
  sta 4, S
  rtl
]] end}

-- Move a 3-byte address from from data stack to the R stack.
dataspace:addNative{name="A.>R", label="_A_TO_R", runtime=function()
  returnstack:pushAddress(datastack:popAddress())
  return nextIp()
end,
asm=function() return [[
  ; First move the return address three bytes back, two MSBs first.
  lda 2, S
  pha
  sep #$20
  .a8
  ; Move the LSB.
  lda 3, S
  pha

  ; Now move the address off the data stack, LSB first.
  lda z:1, X
  sta 4, S
  rep #$20
  .a16

  lda z:2, X
  sta 5, S
  inx
  inx
  inx

  rtl
]] end}

dataspace:addNative{name="R>", label="_FROM_R", runtime=function()
  datastack:pushWord(returnstack:popWord())
  return nextIp()
end,
asm=function() return [[
  lda 4, S
  PUSH_A

  ; Shift the return address
  lda 2, S
  sta 4, S
  pla
  sta 1, S
  rtl
]] end}

dataspace:addNative{name="A.R>", label="_A_FROM_R", runtime=function()
  datastack:pushAddress(returnstack:popAddress())
  return nextIp()
end,
asm=function() return [[
  dex
  dex
  dex
  lda 4, S
  sta z:1, X

  sep #$20
  .a8
  lda 6, S
  sta z:3, X

  ; Now shift the return address, first moving the LSB.
  pla
  sta 3, S
  rep #$20
  .a16

  ; Now the two MSBs
  pla
  sta 2, S
  rtl
]] end}

function toSigned(unsigned)
  if unsigned > 0x7FFF then
    return unsigned - 0x10000
  end
  return unsigned
end

function toUnsigned(signed)
  return signed & 0xFFFF
end

-- Branch based on the relative offset stored at `ip`.
function branch()
  assert(dataspace[ip].type == "number", "Expected relative number to jump to at " .. ip)
  ip = dataspace:fromRelativeAddress(ip, toSigned(dataspace[ip].number))
end

dataspace:addNative{name="BRANCH0", runtime=function()
  if datastack:popWord() == 0 then
    branch()
  else
    -- Skip past the relative address.
    ip = ip + 1
  end
  return nextIp()
end,
asm=function() return [[
  lda z:1, X
  bne @notzero
  ; Equals zero, we branch!
  inx
  inx

  jml _BRANCH

@notzero:
  inx
  inx
  lda #2
  clc
  adc 1, S
  sta 1, S
  bcc @nocarry
  lda #0
  adc 3, S
  sta 3, S
@nocarry:
  rtl
]] end}

dataspace:addNative{name="ADDRESS-OFFSET", runtime=function()
  local from = datastack:popAddress()
  local to = datastack:popAddress()
  local delta = dataspace:toRelativeAddress(from, to)
  assert(delta >= -0x8000 and delta <= 0x7FFF, "Delta out of range: " .. delta)
  datastack:pushWord(toUnsigned(delta))
  return nextIp()
end}

-- Can we do this in Forth based on BRANCH0?
dataspace:addNative{name="BRANCH", runtime=function()
  branch()
  return nextIp()
end,
asm=function() return [[
  tsc
  tcd ; set the DP to the return stack
  ldy #1
  lda [1],Y ; Grab the relative branch pointer
  bmi @negative

  clc
  adc z:1
  sta z:1
  bcc @nocarry
  inc z:3
@nocarry:
  lda #0 ; reset the data stack
  tcd
  rtl ; "return" to the branch point

  ; Negative branch case needs different handling for carry logic, because we
  ; expect the carry flag to be set when we stay on the same page.
  ; e.g. if we're at $010001 and we branch by -1 (0xFFFF) then carry will be
  ; set and no decrement should occur ($010000). If we branch by -2 (0xFFFE),
  ; carry won't be set and so we should decrement to $00FFFF.
@negative:
  clc
  adc z:1
  sta z:1
  bcs @carry
  dec z:3
@carry:
  lda #0 ; reset the data stack
  tcd
  rtl ; "return" to the branch point
]] end}

-- Takes an address (3 bytes) off the stack and pushes a 2 byte word.
dataspace:addNative{name="@", label="_FETCH", runtime=function()
  local addr = datastack:popAddress()
  assert(dataspace[addr].type == "number", "Expected word at " .. addr)
  datastack:pushWord(dataspace[addr].number)
  return nextIp()
end,
asm=function() return [[
  inx ; Reduce stack size by one byte.
  txa
  tcd
  lda [0]
  sta z:1
  lda #0
  tcd
  rtl
]] end}

dataspace:addNative{name="!", label="_STORE", runtime=function()
  local addr = datastack:popAddress()
  local val = datastack:popWord()
  assert(dataspace[addr].type == "number", "Address value must be word-sized: " .. addr)
  dataspace[addr] = Dataspace.number(val)
  return nextIp()
end,
asm=function() return [[
  txa
  tcd
  adc #5
  tax
  lda z:4 ; Grab the argument.
  sta [1]
  lda #0
  tcd
  rtl
]] end}

dataspace:addNative{name="1+", label="_INCR", runtime=function()
  datastack:pushWord(datastack:popWord() + 1)
  return nextIp()
end,
asm=function() return [[
  inc z:1, X
  rtl
]] end}

dataspace:addNative{name="A.1+", label="_A_INCR", runtime=function()
  datastack:pushAddress(datastack:popAddress() + 1)
  return nextIp()
end,
asm=function() return [[
  inc z:1, X
  beq @carry
  rtl
@carry:
  sep #$20
  .a8
  inc z:3, X
  rep #$20
  .a16
  rtl
]] end}

dataspace:addNative{name="LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litaddr = ip
  -- increment the return address to skip the literal
  ip = ip + 1
  assert(dataspace[litaddr].type == "number", "Expected number for LIT at addr = " .. litaddr)
  datastack:pushWord(dataspace[litaddr].number)
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

dataspace:addNative{name="A.LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litaddr = ip
  -- increment the return address to skip the literal
  ip = ip + 1
  assert(dataspace[litaddr].type == "address" or dataspace[litaddr].type == "xt", "Expected address or xt for A.LIT at addr = " .. litaddr)
  datastack:pushAddress(dataspace[litaddr].addr)
  return nextIp()
end,
-- TODO: calls to A.LIT should probably just be inlined :P
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
  sta f:1, X
  iny
  lda [1], Y
  sta f:2, X

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
  local addr = datastack:popAddress()
  if debugging() then
    infos:write("Executing " .. dataspace[addr].name .. "\n")
  end
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

addColonWithLabel("[", "_LBRACK")
  dataspace:addWords("FALSE STATE ! EXIT")
dataspace[dataspace.latest].immediate = true

addColonWithLabel("]", "_RBRACK")
  dataspace:addWords("TRUE STATE ! EXIT")

dataspace:addNative{name="IMMEDIATE", runtime=function()
  dataspace[dataspace.latest].immediate = true
  return nextIp()
end}

dataspace:addNative{name="LABEL", runtime=function()
  local label = input:word()
  dataspace[Dataspace.toCodeword(dataspace.latest)].label = label
  return nextIp()
end}

addColon("DODOES")
  dataspace:addWords("A.R> XT! EXIT")  -- Ends the calling word (CREATEing) early.

addColonWithLabel("DOES>", "_DOES")
  dataspace:addWords("A.LIT")
  dataspace:addXt("DODOES")
  dataspace:addWords("COMPILE, COMPILE-DOCOL EXIT")
dataspace[dataspace.latest].immediate = true

-- TODO: Maybe pull these out into a mathops.lua file?
function unaryOp(name, label, op, asm)
  dataspace:addNative{name=name, label=label, runtime=function()
    local a = datastack:popWord()
    datastack:pushWord(op(a) & 0xFFFF)
    return nextIp()
  end, asm=function() return asm end}
end

unaryOp("NEGATE", "NEGATE", function(a)
  return -a
end, [[
  lda #0
  sec
  sbc z:1, X
  sta z:1, X
  rtl
]])

unaryOp("INVERT", "INVERT", function(a)
  return ~a
end, [[
  lda #$FFFF
  eor z:1, X
  sta z:1, X
  rtl
]])

function binaryOpRt(op)
  return function()
    local b = datastack:popWord()
    local a = datastack:popWord()
    datastack:pushWord(op(a,b) & 0xFFFF)
    return nextIp()
  end
end

function binaryOpWithLabel(name, label, op, asmOp)
  dataspace:addNative{name=name, label=label, runtime=binaryOpRt(op), asm=function() return string.format([[
    lda z:3, X
    %s z:1, X ; Perform computation
    sta z:3, X
    inx
    inx
    rtl
  ]], asmOp) end}
end

binaryOpWithLabel("AND", "_AND", function(a,b)
  return a & b
end, "and")

binaryOpWithLabel("OR", "_OR", function(a,b)
  return a | b
end, "ora")

binaryOpWithLabel("XOR", "_XOR", function(a,b)
  return a ~ b
end, "eor")

binaryOpWithLabel("-", "_MINUS", function(a,b)
  return a - b
end, "sec\n  sbc")

binaryOpWithLabel("+", "_PLUS", function(a,b)
  return a + b
end, "clc\n  adc")

function binaryCmpOp(name, label, op, asmOp)
  dataspace:addNative{name=name, label=label, runtime=function()
    local b = datastack:popWord()
    local a = datastack:popWord()
    datastack:pushWord(op(a,b) and 0xFFFF or 0)
    return nextIp()
  end,
  asm=function() return string.format([[
    ldy #$FFFF
    lda z:3, X
    sec
    sbc z:1, X
    %s @true
    ldy #$0000
  @true:
    sty z:3, X
    inx
    inx
    rtl
  ]], asmOp) end}
end

binaryCmpOp("=", "_EQ", function(a, b)
  return a == b
end, "beq")

binaryCmpOp("<>", "_NE", function(a, b)
  return a ~= b
end, "bne")

binaryCmpOp("<", "_LT", function(a, b)
  return toSigned(a) < toSigned(b)
end, "bmi")

binaryCmpOp(">", "_GT", function(a, b)
  return toSigned(a) > toSigned(b)
end, "bpl")

binaryCmpOp("U<", "_UNSIGNED_LT", function(a, b)
  return toUnsigned(a) < toUnsigned(b)
end, "bcs")

binaryCmpOp("U>", "_UNSIGNED_GT", function(a, b)
  return toUnsigned(a) > toUnsigned(b)
end, "bcc")

do
  addColonWithLabel(":", "_COLON")
  dataspace:addWords("CREATEDOCOL ] EXIT")
end

do
  addColonWithLabel(";", "_SEMICOLON")
  dataspace:addWords("[ A.LIT")
  dataspace:addXt("EXIT")
  -- Also need to make the word visible now.
  dataspace:addWords("COMPILE, EXIT")
  dataspace[dataspace.latest].immediate = true
end

addColonWithLabel("DO.\"", "_DO_STRING")
do
  local loop = dataspace.here
  dataspace:addWords("A.R> A.DUP A.1+ A.>R @ DUP EMIT LIT")
  dataspace:addNumber(0)
  dataspace:addWords("= BRANCH0")
  dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace:addWords("EXIT")
end

addColonWithLabel(".\"", "_STRING")
do
  dataspace:addWords("A.LIT")
  dataspace:addXt("DO.\"")
  dataspace:addWords("COMPILE,")
  dataspace:addWords("KEY DROP") -- Discard the first whitespace.
  local loop = dataspace.here
  dataspace:addWords("KEY DUP LIT")
  dataspace:addNumber(string.byte('"'))
  dataspace:addWords("<> BRANCH0")
  local exitBranchAddr = dataspace.here
  dataspace:addNumber(2000)
  dataspace:addWords(", BRANCH")
  dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace[exitBranchAddr].number = toUnsigned(dataspace:getRelativeAddr(exitBranchAddr, dataspace.here))
  dataspace:addWords("DROP LIT") -- Drop the " and null terminate.
  dataspace:addNumber(0)
  dataspace:addWords(", EXIT")
end
dataspace[dataspace.latest].immediate = true

do
  -- TODO: Can we define a simpler QUIT here and then define the real QUIT in
  -- Forth?
  addColon("QUIT")
  local loop = dataspace.here
  -- TODO: Rather than COUNT we can use C@ to get the length of a counted string
  -- (if we decide to use byte-addressing instead of cell-addressing for
  -- characters).
  dataspace:addWords("WORD A.DUP COUNT >R A.DROP R> BRANCH0")
  local eofBranchAddr = dataspace.here
  dataspace:addNumber(2000)

  dataspace:addWords("FIND")

  dataspace:addWords("DUP LIT")
  dataspace:addNumber(0)
  dataspace:addWords("= BRANCH0")
  local wordFoundBranchAddr = dataspace.here
  dataspace:addNumber(2000) -- will be replaced later
    -- Not found, try and parse as a number.
    dataspace:addWords("DROP A.DUP >NUMBER BRANCH0")
    local numberParseErrorAddr = dataspace.here
    dataspace:addNumber(2000)
    -- String is no longer needed, drop it.
    dataspace:addWords(">R A.DROP R>")
    -- If we're compiling, compile TOS as a literal.
    dataspace:addWords("STATE @ BRANCH0")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
    -- A.LIT the LIT so we can LIT while we A.LIT.
    dataspace:addWord("A.LIT")
    dataspace:addXt("LIT")
    -- Compile LIT and then the number.
    dataspace:addWords("COMPILE, , BRANCH")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))

    dataspace[numberParseErrorAddr].number = toUnsigned(dataspace:getRelativeAddr(numberParseErrorAddr, dataspace.here))
    dataspace:addWords("DROP A.DUP >ADDRESS BRANCH0")
    local addressParseErrorAddr = dataspace.here
    dataspace:addNumber(2000)
    -- String is no longer needed, drop it.
    dataspace:addWords("A.>R A.DROP A.R>")
    -- If we're compiling, compile TOS as a literal.
    dataspace:addWords("STATE @ BRANCH0")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
    -- A.LIT the A.LIT so we can A.LIT while we A.LIT.
    dataspace:addWord("A.LIT")
    dataspace:addXt("A.LIT")
    -- Compile A.LIT and then the number.
    dataspace:addWords("COMPILE, A., BRANCH")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace[wordFoundBranchAddr].number = toUnsigned(dataspace:getRelativeAddr(wordFoundBranchAddr, dataspace.here))

  -- Word found, see if we're compiling or interpreting.
  dataspace:addWords("LIT")
  dataspace:addNumber(0)
  dataspace:addWords("> STATE @ INVERT OR BRANCH0")
  local branchAddrIfNotImmediate = dataspace.here
  dataspace:addNumber(2000) -- will be replaced later
    -- Interpreting, just run the word.
    dataspace:addWords("EXECUTE BRANCH")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace[branchAddrIfNotImmediate].number = toUnsigned(dataspace:getRelativeAddr(branchAddrIfNotImmediate, dataspace.here))

  -- else, compiling
  dataspace:addWords("COMPILE, BRANCH")
  dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))

  dataspace[addressParseErrorAddr].number = toUnsigned(dataspace:getRelativeAddr(addressParseErrorAddr, dataspace.here))
  dataspace:addWords("A.DROP A.DUP TYPE")
  dataspace:addWords("DO.\"")
  dataspace:addNumber(string.byte("?"))
  dataspace:addNumber(string.byte("\n"))
  dataspace:addNumber(0)
  dataspace[eofBranchAddr].number = toUnsigned(dataspace:getRelativeAddr(eofBranchAddr, dataspace.here))
  dataspace:addWords("A.DROP EXIT")
end

ip = dataspace.here -- start on creating STATE, below
dataspace:addWord("QUIT")
dataspace:addWord("BYE")

if debugging() then
  infos:write("latest: " .. dataspace.latest .. "\n")
  infos:write("here: " .. dataspace.here .. "\n")

  dataspace:print(io.stderr)
end

nextIp()

if debugging() then
  dataspace:print(io.stderr)

  datastack:print(io.stderr)
end

local output = assert(io.open(arg[2], "w"))
dataspace:assembly(output)

