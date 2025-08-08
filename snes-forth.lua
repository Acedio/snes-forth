#!/usr/bin/lua

local ByteStack = require("bytestack")
local CellStack = require("cellstack")
local Input = require("input")
local Dataspace = require("dataspace")

local dataStack = CellStack:new()
local returnStack = ByteStack:new()

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

-- Make a variable that is easily accessible to Lua and the SNES.
function makeSystemVariable(name)
  local native = Dataspace.native{name=name}
  dataspace:addNative(native)
  local dataaddr = dataspace.here
  native.runtime = function()
    dataStack:push(dataaddr)
  end
  native.asm = function() return string.format([[
    dex
    dex
    ; Load address.
    lda #_%s_DATA
    sta z:1, X
    rts
  .ZEROPAGE
  _%s_DATA:
    .WORD $0000
  .CODE
  ]], name, name, name) end
  return dataspace:addNumber(0)
end

local stateEntry = makeSystemVariable("STATE")
local debugEntry = makeSystemVariable("DEBUG")

if flags["-v"] then
  debugEntry.number = 0xFFFF
else
  debugEntry.number = 0x0
end

function debugging()
  return debugEntry.number ~= 0
end

-- TODO: This should probably just be a while loop rather than this recursive
-- deal :P
function nextIp()
  local oldip = ip
  ip = ip + 1
  if debugging() then
    if dataspace[oldip].type == "call" then
      local name = dataspace:addrName(dataspace[oldip].addr) or "missing name"
      infos:write(string.format("IP = $%04x (call %s)\n", oldip, name))
    elseif dataspace[oldip].type == "native" then
      local name = dataspace:addrName(oldip) or "missing name"
      infos:write(string.format("IP = $%04x (native %s)\n", oldip, name))
    end
    infos:write("== data ==\n")
    dataStack:print(infos)
    infos:write("== return ==\n")
    returnStack:print(infos)
  end

  return execute(oldip)
end

function execute(xt)
  local instruction = dataspace[xt]
  if instruction.type == "call" then
    returnStack:pushWord(ip)
    ip = instruction.addr
    return nextIp()
  elseif instruction.type == "native" then
    instruction.runtime()
    ip = returnStack:popWord()
    return nextIp()
  else
    dataspace:print(infos)
    assert(nil, string.format("Attempted to execute a non-call, non-native cell: $%04x\n", xt))
  end
end

function addColonWithLabel(name, label)
  local entry = dataspace:dictionaryAdd(name, label)
  -- TODO: It's kind of weird to have a zero-sized entry because it shares its
  -- (Lua dataspace) address with whatever else comes next. I think I split
  -- off the dictionary entry so that I could put a label at the beginning of
  -- each word (native or DOCOL), but maybe we should instead put the label at
  -- the end of each dict entry? Maybe docol isn't really needed? Does that
  -- fix our problem?
end

function addColon(name)
  addColonWithLabel(name, Dataspace.defaultLabel(name))
end

-- TODO: Should this be a 2 byte or 4 byte address if we switch to 1-word
-- addressing?
dataspace:addNative{name="HERE", runtime=function()
  dataStack:push(dataspace.here)
end}

-- All datatypes are one cell in Lua, but varying sizes on the SNES.
dataspace:addNative{name="CHARS", runtime=function()
  -- Noop.
end,
asm=function() return [[
  rts
]] end}

dataspace:addNative{name="CELLS", runtime=function()
  -- TODO: This should be two.
end,
asm=function() return [[
  asl z:1, X
  rts
]] end}

dataspace:addNative{name="ADDRS", runtime=function()
  -- TODO: This should be three.
end,
asm=function() return [[
  clc
  lda z:1, X
  asl A
  adc z:1, X
  sta z:1, X
  rts
]] end}

dataspace:addNative{name="DATASPACE", runtime=function()
  dataspace:print(outputs)
end}

dataspace:addNative{name="DEPTH", runtime=function()
  dataStack:push(dataStack:entries())
end,
asm=function() return [[
  txa
  eor #$FFFF
  inc A
  clc
  adc #DATA_STACK_ADDR
  lsr ; 2 bytes per cell
  PUSH_A
  rts
]] end}

dataspace:addNative{name=".s", LABEL="_dot_S", runtime=function()
  dataStack:print(outputs)
end}

dataspace:addNative{name="C,", label="_C_COMMA", runtime=function()
  dataspace:addByte(dataStack:pop() & 0xFF)
end}

dataspace:addNative{name=",", label="_COMMA", runtime=function()
  dataspace:addNumber(dataStack:pop())
end}

dataspace:addNative{name="A.,", label="_A_COMMA", runtime=function()
  -- TODO: Zero top byte? Or error?
  dataspace:addAddress(dataStack:popDouble())
end}

dataspace:addNative{name="XT,", label="_XT_COMMA", runtime=function()
  local xt = dataStack:pop()
  dataspace:add(Dataspace.xt(xt))
  if debugging() then
    infos:write("Compiling XT " .. dataspace:addrName(xt) .. "\n")
  end
end}

-- Set the XT for the latest word to start a docol at addr
-- TODO: How will this work on the SNES?
dataspace:addNative{name="XT!", label="_XT_STORE", runtime=function()
  local addr = dataStack:pop()
  local dataaddr = Dataspace.toCodeword(dataspace.latest) + 1
  dataspace[Dataspace.toCodeword(dataspace.latest)].runtime = function()
    dataStack:push(dataaddr)
    return dataspace[addr].runtime()
  end
end}

dataspace:addNative{name="CREATE", runtime=function()
  local name = input:word()
  local native = Dataspace.native{
    name = name,
  }
  dataspace:addNative(native)  -- Use a placeholder fn initially.
  local dataaddr = dataspace.here  -- HERE has been updated by calling native()
  -- Now update the fn with the new HERE.
  native.runtime = function()
    dataStack:push(dataaddr)
  end
end}

dataspace:addNative{name="CREATEDOCOL", runtime=function()
  local name = input:word()
  addColon(name)
end}

dataspace:addNative{name="ALLOT", runtime=function()
  dataspace.here = dataspace.here + dataStack:pop()
end}

-- TODO: For now we'll actually implement EXIT in ASM, but on the SNES it should
-- just be a `RTS` and not `JSR EXIT` like other Forth words.
dataspace:addNative{name="EXIT", runtime=function()
  returnStack:popWord()
end,
asm=function() return [[
  ; Remove the caller's return address (2 bytes) and return.
  tsa
  inc A
  inc A
  tas
  rts
]] end}

dataspace:addNative{name=".", label="_DOT", runtime=function()
  outputs:write(dataStack:pop() .. "\n")
end}

dataspace:addNative{name="BYE", runtime=function()
  infos:write("WE DONE!" .. "\n")
  -- TODO: WHY DOES THIS WORK? It's still quitting!
  -- TODO: BYE ends the program by not calling nextIp
end}

dataspace:addNative{name="ABORT", runtime=function()
  infos:write("ABORTED!" .. "\n")
  assert(nil)
end}

dataspace:addNative{name="EMIT", runtime=function()
  outputs:write(string.char(dataStack:pop()))
end}

local wordBufferAddr = dataspace.here
local wordBufferSize = 32
dataspace:addNumber(0)
for i=1,wordBufferSize do
  dataspace:addByte(0)
end

function setWordBuffer(str)
  local length = string.len(str)
  assert(length < wordBufferSize, "Strings length too large: " .. str)
  dataspace[wordBufferAddr] = Dataspace.number(length)
  for i=1,length do
    dataspace[wordBufferAddr + i] = Dataspace.byte(string.byte(string.sub(str, i, i)))
  end
end

function getWordWithCount(addr, count)
  local str = ""
  for i=0,count-1 do
    assert(dataspace[addr + i].type == "byte", string.format("Expected byte at addr = $%04x", addr + i))
    str = str .. string.char(dataspace[addr + i].byte)
  end
  return str
end

function getCountedWord(addr)
  assert(dataspace[addr].type == "number")
  local count = dataspace[addr].number
  return getWordWithCount(addr + 1, count)
end

dataspace:addNative{name="WORD", runtime=function()
  setWordBuffer(input:word() or "")
  dataStack:push(wordBufferAddr)
end}

dataspace:addNative{name="PEEK", runtime=function()
  dataStack:push(input:peek())
end}

dataspace:addNative{name="KEY", runtime=function()
  dataStack:push(input:key())
end}

dataspace:addNative{name="TYPE", runtime=function()
  local count = dataStack:pop()
  local addr = dataStack:pop()
  outputs:write(getWordWithCount(addr, count))
end}

-- Can probably be written in Forth? Though not interpreted-Forth.
dataspace:addNative{name="FIND", runtime=function()
  local wordAddress = dataStack:pop()
  local word = getCountedWord(wordAddress)
  -- TODO: Dictionary should probably not be stored in dataspace for now.
  local dictAddr = dataspace:dictionaryFind(word)
  if not dictAddr then
    dataStack:push(wordAddress)
    dataStack:push(0)
  elseif dataspace[dictAddr].immediate then
    dataStack:push(Dataspace.toCodeword(dictAddr))
    dataStack:push(1)
  else
    dataStack:push(Dataspace.toCodeword(dictAddr))
    dataStack:push(0xFFFF)
  end
end}

-- Non-standard. Returns TRUE or FALSE at the top of the stack.
dataspace:addNative{name=">NUMBER", label="_TO_NUMBER", runtime=function()
  local strAddress = dataStack:pop()
  local str = getCountedWord(strAddress)
  local number = tonumber(str)
  if number == nil then
    dataStack:push(0)
    -- Failed.
    dataStack:push(0)
    return
  end

  if number > 0xFFFF or number < -0x8000 then
    dataStack:push(0)
    -- Failed.
    dataStack:push(0)
    return
  end

  dataStack:push(toUnsigned(number))
  dataStack:push(0xFFFF)
end}

-- Returns TRUE or FALSE at the top of the stack, and the parsed address below
-- that.
dataspace:addNative{name=">ADDRESS", label="_TO_ADDRESS", runtime=function()
  local strAddress = dataStack:pop()
  local maybeAddress = getCountedWord(strAddress)
  if string.sub(maybeAddress, 1, 1) ~= "$" then
    dataStack:pushDouble(0)
    -- Failed.
    dataStack:push(0)
    return
  end

  local address = tonumber(string.sub(maybeAddress, 2), 16)
  if address == nil then
    dataStack:pushDouble(0)
    -- Failed.
    dataStack:push(0)
    return
  end

  if address > 0xFFFFFF or address < 0 then
    dataStack:pushDouble(0)
    -- Failed.
    dataStack:push(0)
    return
  end

  dataStack:pushDouble(address)
  dataStack:push(0xFFFF)
end}

dataspace:addNative{name="DUP", runtime=function()
  dataStack:push(dataStack:top())
end,
asm=function() return [[
  lda z:1,X
  PUSH_A
  rts
]] end}

dataspace:addNative{name="2DUP", runtime=function()
  local double = dataStack:topDouble()
  dataStack:pushDouble(double)
end,
asm=function() return [[
  dex
  dex
  dex
  dex
  lda z:5, X
  sta z:1, X
  lda z:7, X
  sta z:3, X
  rts
]] end}

dataspace:addNative{name="DROP", runtime=function()
  dataStack:pop()
end,
asm=function() return [[
  inx
  inx
  rts
]] end}

dataspace:addNative{name="2DROP", runtime=function()
  dataStack:popDouble()
end,
asm=function() return [[
  inx
  inx
  inx
  inx
  rts
]] end}

dataspace:addNative{name="SWAP", runtime=function()
  local first = dataStack:pop()
  local second = dataStack:pop()
  dataStack:push(first)
  dataStack:push(second)
end,
asm=function() return [[
  ldy z:1, X
  lda z:3, X
  sta z:1, X
  sty z:3, X
  rts
]] end}

dataspace:addNative{name="2SWAP", runtime=function()
  local first = dataStack:popDouble()
  local second = dataStack:popDouble()
  dataStack:pushDouble(first)
  dataStack:pushDouble(second)
end,
asm=function() return [[
  ldy z:1, X
  lda z:5, X
  sta z:1, X
  sty z:5, X
  ldy z:3, X
  lda z:7, X
  sta z:3, X
  sty z:7, X
  
  rts
]] end}

dataspace:addNative{name="COMPILE,", label="_COMPILE_COMMA", runtime=function()
  local xt = dataStack:pop()
  dataspace:addCall(xt)
  if debugging() then
    infos:write("Compiling " .. dataspace:addrName(xt) .. "\n")
  end
end}

-- Pushes the address of the first character of the string, then the size of the
-- string in bytes.
dataspace:addNative{name="COUNT", runtime=function()
  local addr = dataStack:pop()
  assert(dataspace[addr].type == "number")
  local length = dataspace[addr].number
  dataStack:push(addr + 1)
  dataStack:push(length)
end}

-- Move a 2-byte word from from data stack to the R stack.
dataspace:addNative{name=">R", label="_TO_R", runtime=function()
  local holdReturn = returnStack:popWord()
  returnStack:pushWord(dataStack:pop())
  returnStack:pushWord(holdReturn)
end,
asm=function() return [[
  ; First, move the return address two bytes back.
  lda 1, S
  pha

  POP_A
  sta 3, S
  rts
]] end}

-- Move a 2-cell address from from data stack to 3-bytes on the R stack.
-- 2 cell addresses store the LSB in the lowest position (so it's pushed onto
-- the stack MSB first)
dataspace:addNative{name="A.>R", label="_A_TO_R", runtime=function()
  local holdReturn = returnStack:popWord()
  returnStack:pushAddress(dataStack:popDouble())
  returnStack:pushWord(holdReturn)
end,
asm=function() return [[
  ; First transfer the LSB of the address
  A8
  lda 1, X
  pha
  A16
  ; Shift the return address three bytes back.
  lda 2, S
  pha
  ; Now fill in the two MSBs of the address
  lda 2, X
  sta 4, S
  inx
  inx
  inx
  inx

  rts
]] end}

dataspace:addNative{name="R>", label="_FROM_R", runtime=function()
  local holdReturn = returnStack:popWord()
  dataStack:push(returnStack:popWord())
  returnStack:pushWord(holdReturn)
end,
asm=function() return [[
  ; Move the cell from the return stack
  lda 3, S
  PUSH_A

  ; Now shift the return address
  pla
  sta 1, S

  rts
]] end}

dataspace:addNative{name="A.R>", label="_A_FROM_R", runtime=function()
  local holdReturn = returnStack:popWord()
  dataStack:pushDouble(returnStack:popAddress())
  returnStack:pushWord(holdReturn)
end,
asm=function() return [[
  dex
  dex
  dex
  dex

  ; Copy the 2 MSBs
  lda 4, S
  sta 2, X
  ; Move the return word
  pla
  sta 2, S
  ; Copy the LSB
  A8
  pla
  sta 1, X
  ; Zero the garbage byte at the end
  stz 4, X
  A16

  rts
]] end}

dataspace:addNative{name="R@", label="_FETCH_R", runtime=function()
  local holdReturn = returnStack:popWord()
  dataStack:push(returnStack:topWord())
  returnStack:pushWord(holdReturn)
end,
asm=function() return [[
  lda 3, S
  PUSH_A
  rts
]] end}

dataspace:addNative{name="A.R@", label="_A_FETCH_R", runtime=function()
  local holdReturn = returnStack:popWord()
  dataStack:pushDouble(returnStack:topAddress())
  returnStack:pushWord(holdReturn)
end,
asm=function() return [[
  dex
  dex
  dex
  dex
  ; LSBs
  lda 3, S
  sta z:1, X
  ; MSB
  lda 6, S
  and #$FF
  sta z:3, X

  rts
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

-- Branch based on the relative offset stored in front of the called branch fn.
function branch()
  local retAddr = returnStack:popWord()
  assert(dataspace[retAddr].type == "number", string.format("Expected relative number to jump to at $%04x", retAddr))
  local newRet = dataspace:fromRelativeAddress(retAddr, toSigned(dataspace[retAddr].number))
  returnStack:pushWord(newRet)
end

dataspace:addNative{name="BRANCH0", runtime=function()
  if dataStack:pop() == 0 then
    branch()
  else
    -- Skip past the relative address.
    returnStack:pushWord(returnStack:popWord() + 1)
  end
end,
asm=function() return [[
  lda z:1, X
  bne @notzero
  ; Equals zero, we branch!
  inx
  inx

  jmp _BRANCH

@notzero:
  inx
  inx
  lda #2
  clc
  adc 1, S
  sta 1, S
  rts
]] end}

dataspace:addNative{name="ADDRESS-OFFSET", runtime=function()
  local from = dataStack:pop()
  local to = dataStack:pop()
  local delta = dataspace:toRelativeAddress(from, to)
  assert(delta >= -0x8000 and delta <= 0x7FFF, "Delta out of range: " .. delta)
  dataStack:push(toUnsigned(delta))
end}

-- Can we do this in Forth based on BRANCH0?
dataspace:addNative{name="BRANCH", runtime=function()
  branch()
end,
asm=function() return [[
  ldy #1
  lda (1,S),Y ; Grab the relative branch pointer

  clc
  adc 1, S
  sta 1, S

  rts ; "return" to the branch point
]] end}

-- Takes a local address (2 bytes) off the stack and pushes a 2 byte word.
dataspace:addNative{name="@", label="_FETCH", runtime=function()
  local addr = dataStack:pop()
  assert(dataspace[addr].type == "number", string.format("Expected word at $%04x", addr))
  dataStack:push(dataspace[addr].number)
end,
asm=function() return [[
  lda (1, X)
  sta 1, X
  rts
]] end}

dataspace:addNative{name="!", label="_STORE", runtime=function()
  local addr = dataStack:pop()
  local val = dataStack:pop()
  assert(dataspace[addr].type == "number", string.format("Address value must be word-sized: $%04x", addr))
  dataspace[addr].number = val
end,
asm=function() return [[
  lda 3, X
  sta (1, X)
  inx
  inx
  inx
  inx
  rts
]] end}

-- Takes a local address (2 bytes) off the stack and pushes 1 byte extended into
-- a word.
dataspace:addNative{name="C@", label="_C_FETCH", runtime=function()
  local addr = dataStack:pop()
  assert(dataspace[addr].type == "number", string.format("Expected word at $%04x", addr))
  dataStack:push(dataspace[addr].number)
end,
asm=function() return [[
  A8
  lda (1, X)
  A16
  and #$FF
  sta 1, X
  rts
]] end}

dataspace:addNative{name="C!", label="_C_STORE", runtime=function()
  local addr = dataStack:pop()
  local val = dataStack:pop()
  assert(dataspace[addr].type == "byte", string.format("Address value must be word-sized: $%04x", addr))
  dataspace[addr] = Dataspace.byte(val & 0xFF)
end,
asm=function() return [[
  lda 3, X
  A8
  sta (1, X)
  A16
  inx
  inx
  inx
  inx
  rts
]] end}

-- TODO: Takes a far address (2 cells) off the stack and pushes a 1 cell word.
dataspace:addNative{name="F@", label="_FAR_FETCH", runtime=function()
  local addr = dataStack:pop()
  assert(dataspace[addr].type == "number", string.format("Expected word at $%04x", addr))
  dataStack:push(dataspace[addr].number)
end,
asm=function() return [[
  inx ; Reduce stack size by one byte.
  txa
  tcd
  lda [0]
  sta z:1
  lda #0
  tcd
  rts
]] end}

-- TODO
dataspace:addNative{name="F!", label="_FAR_STORE", runtime=function()
  local addr = dataStack:pop()
  local val = dataStack:pop()
  assert(dataspace[addr].type == "number", string.format("Address value must be word-sized: $%04x", addr))
  dataspace[addr] = Dataspace.number(val)
end,
-- TODO: This expects three bytes from the data stack
asm=function() return [[
  txa
  tcd
  adc #5
  tax
  lda z:4 ; Grab the argument.
  sta [1]
  lda #0
  tcd
  rts
]] end}

dataspace:addNative{name="1+", label="_INCR", runtime=function()
  dataStack:push(dataStack:pop() + 1)
end,
asm=function() return [[
  inc z:1, X
  rts
]] end}

dataspace:addNative{name="DOUBLE+", label="_DOUBLE_INCR", runtime=function()
  dataStack:pushDouble(dataStack:popDouble() + 1)
end,
asm=function() return [[
  inc z:1, X
  beq @carry
  rts
@carry:
  A8
  inc z:3, X
  A16
  rts
]] end}

dataspace:addNative{name="LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litAddr = returnStack:popWord()
  -- increment the return address to skip the literal
  returnStack:pushWord(litAddr + 1)
  if dataspace[litAddr].type == "number" then
    dataStack:push(dataspace[litAddr].number)
  elseif dataspace[litAddr].type == "xt" then
    dataStack:push(dataspace[litAddr].addr)
  else
    assert(false, string.format("Expected number or xt for LIT at addr = $%04x", litAddr))
  end
end,
-- TODO: calls to LIT should probably just be inlined :P
asm=function() return [[
  ldy #1
  lda (1, S), Y
  PUSH_A
  lda 1, S
  inc A
  inc A
  sta 1, S

  rts
]] end}

dataspace:addNative{name="A.LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litAddr = returnStack:popWord()
  -- increment the return address to skip the literal
  returnStack:pushWord(litAddr + 1)
  assert(dataspace[litAddr].type == "address", string.format("Expected address for A.LIT at addr = $%04x", litAddr))
  dataStack:pushDouble(dataspace[litAddr].addr)
end,
-- TODO: calls to A.LIT should probably just be inlined :P
asm=function() return [[
  ; Copy the MSB and garbage
  ldy #3
  lda (1, S), Y
  and #$FF
  PUSH_A
  ; Copy the LSBs
  ldy #1
  lda (1, S), Y
  PUSH_A
  lda 1, S
  inc A
  inc A
  inc A
  sta 1, S

  rts
]] end}

dataspace:addNative{name="EXECUTE", runtime=function()
  local addr = dataStack:pop()
  if debugging() then
    infos:write("Executing " .. dataspace:addrName(addr) .. "\n")
  end
  ip = addr
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
end}

dataspace:addNative{name="LABEL", runtime=function()
  local label = input:word()
  dataspace[dataspace.latest].label = label
end}

addColon("DODOES")
  -- TODO: More to consider here, probably need to change XT!
  dataspace:addWords("R> XT! EXIT")  -- Ends the calling word (CREATEing) early.

addColonWithLabel("DOES>", "_DOES")
  dataspace:addWords("LIT")
  dataspace:addXt("DODOES")
  dataspace:addWords("COMPILE, EXIT")
dataspace[dataspace.latest].immediate = true

-- TODO: Maybe pull these out into a mathops.lua file?
function unaryOp(name, label, op, asm)
  dataspace:addNative{name=name, label=label, runtime=function()
    local a = dataStack:pop()
    dataStack:push(op(a) & 0xFFFF)
  end, asm=function() return asm end}
end

unaryOp("NEGATE", "_NEGATE", function(a)
  return -a
end, [[
  lda #0
  sec
  sbc z:1, X
  sta z:1, X
  rts
]])

unaryOp("INVERT", "_INVERT", function(a)
  return ~a
end, [[
  lda #$FFFF
  eor z:1, X
  sta z:1, X
  rts
]])

unaryOp("2*", "_MUL2", function(a)
  return a << 1
end, [[
  asl z:1, X
  rts
]])

unaryOp("LSR", "_LSR", function(a)
  return a >> 1
end, [[
  lsr z:1, X
  rts
]])

function binaryOpRt(op)
  return function()
    local b = dataStack:pop()
    local a = dataStack:pop()
    dataStack:push(op(a,b) & 0xFFFF)
  end
end

function binaryOpWithLabel(name, label, op, asmOp)
  dataspace:addNative{name=name, label=label, runtime=binaryOpRt(op), asm=function() return string.format([[
    lda z:3, X
    %s z:1, X ; Perform computation
    sta z:3, X
    inx
    inx
    rts
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
    local b = dataStack:pop()
    local a = dataStack:pop()
    dataStack:push(op(a,b) and 0xFFFF or 0)
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
    rts
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
end, "bcc")

binaryCmpOp("U>", "_UNSIGNED_GT", function(a, b)
  return toUnsigned(a) > toUnsigned(b)
end, "bcs")

do
  addColonWithLabel(":", "_COLON")
  dataspace:addWords("CREATEDOCOL ] EXIT")
end

do
  addColonWithLabel(";", "_SEMICOLON")
  dataspace:addWords("[ LIT")
  dataspace:addXt("EXIT")
  -- Also need to make the word visible now.
  dataspace:addWords("COMPILE, EXIT")
  dataspace[dataspace.latest].immediate = true
end

-- Given a return stack entry, push where the inline data for this word is.
dataspace:addNative{name="INLINE-DATA", runtime=function()
  -- The return stack in Lua already points at the inline data.
end,
asm=function() return [[
  ; We're one byte behind the inline data.
  inc 1, X
  rts
]] end}

-- Push the inline string address and the length.
addColonWithLabel("DOS\"", "_DO_SLIT")
do
  dataspace:addWords("R@ INLINE-DATA DUP LIT")
  dataspace:addNumber(1)
  dataspace:addWords("CELLS + SWAP @ DUP CHARS LIT")
  dataspace:addNumber(1)
  dataspace:addWords("CELLS + R> + >R EXIT")
end

addColonWithLabel("S\"", "_SLIT")
do
  dataspace:addWords("LIT")
  dataspace:addXt("DOS\"")
  dataspace:addWords("COMPILE,")
  -- Make space for the length and save its addr.
  dataspace:addWords("HERE LIT")
  dataspace:addNumber(0)
  dataspace:addWords("DUP ,") -- Also grab a zero to track the length.
  dataspace:addWords("KEY DROP") -- Discard the first whitespace.
  local loop = dataspace.here
  dataspace:addWords("KEY DUP LIT")
  dataspace:addNumber(string.byte('"'))
  dataspace:addWords("<> BRANCH0")
  local exitBranchAddr = dataspace.here
  dataspace:addNumber(2000)
  dataspace:addWords("C, 1+ BRANCH")
  dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
  dataspace[exitBranchAddr].number = toUnsigned(dataspace:getRelativeAddr(exitBranchAddr, dataspace.here))
  dataspace:addWords("DROP SWAP !") -- Drop the " and fill in the length
  dataspace:addWords("EXIT")
end
dataspace[dataspace.latest].immediate = true

do
  -- TODO: Can we define a simpler QUIT here and then define the real QUIT in
  -- Forth?
  addColon("QUIT")
  local loop = dataspace.here
  -- Grab the length of the counted string with @.
  dataspace:addWords("WORD DUP @ BRANCH0")
  local eofBranchAddr = dataspace.here
  dataspace:addNumber(2000)

  dataspace:addWords("FIND")

  dataspace:addWords("DUP LIT")
  dataspace:addNumber(0)
  dataspace:addWords("= BRANCH0")
  local wordFoundBranchAddr = dataspace.here
  dataspace:addNumber(2000) -- will be replaced later
    -- Not found, try and parse as a number.
    dataspace:addWords("DROP DUP >NUMBER BRANCH0")
    local numberParseErrorAddr = dataspace.here
    dataspace:addNumber(2000)
    -- String is no longer needed, drop it.
    dataspace:addWords(">R DROP R>")
    -- If we're compiling, compile TOS as a literal.
    dataspace:addWords("STATE @ BRANCH0")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
    -- LIT the LIT so we can LIT while we LIT.
    dataspace:addWord("LIT")
    dataspace:addXt("LIT")
    -- Compile LIT and then the number.
    dataspace:addWords("COMPILE, , BRANCH")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))

    dataspace[numberParseErrorAddr].number = toUnsigned(dataspace:getRelativeAddr(numberParseErrorAddr, dataspace.here))
    dataspace:addWords("DROP DUP >ADDRESS BRANCH0")
    local addressParseErrorAddr = dataspace.here
    dataspace:addNumber(2000)
    -- String is no longer needed, drop it.
    dataspace:addWords(">R >R DROP R> R>")
    -- If we're compiling, compile TOS as a literal.
    dataspace:addWords("STATE @ BRANCH0")
    dataspace:addNumber(dataspace:getRelativeAddr(dataspace.here, loop))
    -- LIT the A.LIT so we can A.LIT while we LIT.
    dataspace:addWord("LIT")
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
  dataspace:addWords("2DROP DUP COUNT TYPE")
  dataspace:addWords("DOS\"")
  dataspace:addNumber(2)
  dataspace:addNumber(string.byte("?"))
  dataspace:addNumber(string.byte("\n"))
  dataspace:addWords("TYPE ABORT")
  dataspace[eofBranchAddr].number = toUnsigned(dataspace:getRelativeAddr(eofBranchAddr, dataspace.here))
  dataspace:addWords("DROP EXIT")
end

ip = dataspace.here -- start on creating STATE, below
dataspace:addWord("QUIT")
dataspace:addWord("BYE")

if debugging() then
  infos:write(string.format("latest: $%04x\n", dataspace.latest))
  infos:write(string.format("here: $%04x\n", dataspace.here))

  dataspace:print(io.stderr)
end

nextIp()

if debugging() then
  dataspace:print(io.stderr)

  dataStack:print(io.stderr)
end

local output = assert(io.open(arg[2], "w"))
output:write([[
.p816
.i16
.a16
.import not_implemented

.segment "CODE"

.include "preamble.s"

.export _MAIN

]])

dataspace:assembly(output)

