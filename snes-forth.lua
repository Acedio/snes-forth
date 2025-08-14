#!/usr/bin/lua

local ByteStack = require("bytestack")
local CellStack = require("cellstack")
local Input = require("input")
local Dataspace = require("dataspace")
local Dictionary = require("dictionary")

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
local dumpFile = assert(io.open("dataspace.dump", "w"))

local dictionary = Dictionary:new()
local dataspace = Dataspace:new()

local function assertAddr(cond, message, addr)
  dataspace:assertAddr(dumpFile, cond, message, addr)
end
  
local running = true
local ip = 0

function addCall(addr)
  local entry = Dataspace.native{
    size = function(self) return 3 end,
    runtime = function(self, dataspace, opAddr)
      ip = ip + 3
      local callAddr = self:addr(dataspace, opAddr)
      -- TODO: Can probably just remove this check as the interpreter will do it
      assert(dataspace[callAddr].type == "native", string.format("Expected native at %s", Dataspace.formatAddr(callAddr)))
      -- TODO: To match the 65816 this should be ip - 1
      returnStack:pushWord(ip)
      ip = callAddr
    end,
    addr = function(self, dataspace, opAddr)
      return dataspace:getWord(opAddr + 1)
    end,
    toString = function(self, dataspace, opAddr)
      local callAddr = self:addr(dataspace, opAddr)
      local name = dictionary:addrName(callAddr)
      if not name then
        return string.format("Call to $%04X (missing name)", callAddr)
      end
      return string.format("Call $%04X (to %s)", callAddr, name)
    end,
    asm = function(self, dataspace, opAddr)
      local callAddr = self:addr(dataspace, opAddr)
      assert(dataspace[callAddr].type == "native", string.format("Expected native at %s", Dataspace.formatAddr(callAddr)))
      if dataspace[callAddr]:size() then
        return string.format([[
          jsr $%04X ; Cross our fingers!
        ]], callAddr)
      else
        local label = dictionary:addrLabel(callAddr)
        if not label then
          return string.format([[
            jsr $%04X ; Cross our fingers!
          ]], callAddr)
        end
        return string.format([[
          jsr %s
        ]], label)
      end
    end,
  }
  dataspace:add(entry)
  dataspace:addWord(addr)
end

function rts()
  ip = returnStack:popWord()
end

function addXt(name)
  return dataspace:addWord(dictionary:findAddr(name))
end

-- Add words to the current colon defintion
function addWords(names)
  local first = 0
  local last = 0
  while true do
    first, last = string.find(names, "%S+", last)
    if first == nil then
      break
    end
    local name = string.sub(names, first, last)
    local callAddr = dictionary:findAddr(name)
    assert(callAddr, "Couldn't find " .. name)
    print(string.format("Found %s at %04X", name, callAddr))
    addCall(callAddr)
    last = last + 1
  end
end

-- Table should have at least name and runtime specified.
function addNative(entry)
  entry.label = entry.label or Dataspace.defaultLabel(entry.name)
  -- Native fns are unsized, so they don't affect/use HERE.
  local addr = dataspace:addUnsized(Dataspace.native(entry))
  print(string.format("Adding unsized %s at %04X", entry.name, addr))
  dictionary:add(entry.name, entry.label, addr)
end

-- Make a variable that is easily accessible to Lua and the SNES.
-- Returns the dataspace address of the variable contents.
function makeSystemVariable(name)
  local native = Dataspace.native{name=name, label=Dataspace.defaultLabel(name)}
  addNative(native)
  local dataaddr = dataspace.here
  native.runtime = function()
    dataStack:push(dataaddr)
    rts()
  end
  native.asm = function() return string.format([[
    dex
    dex
    ; Load address.
    lda #_%s_DATA
    sta z:1, X
    rts
  .PUSHSEG
  .ZEROPAGE
  _%s_DATA:
    .WORD $0000
  .POPSEG
  ]], name, name, name) end
  dataspace:addWord(0)
  return dataaddr
end

makeSystemVariable("STATE")
local debugAddr = makeSystemVariable("DEBUG")

if flags["-v"] then
  dataspace:setWord(debugAddr, 0xFFFF)
else
  dataspace:setWord(debugAddr, 0x0)
end

function debugging()
  return true --dataspace:getWord(debugAddr) ~= 0
end

function addColonWithLabel(name, label)
  print(string.format("Adding colon %s at %04X", name, dataspace.here))
  dictionary:add(name, label, dataspace.here)
end

function addColon(name)
  addColonWithLabel(name, Dataspace.defaultLabel(name))
end

-- TODO: Should this be a 2 byte or 4 byte address if we switch to 1-word
-- addressing? Probably keep it as a two byte and have it update depending on
-- our bank.
addNative{name="HERE", runtime=function()
  dataStack:push(dataspace.here)
  rts()
end}

-- All datatypes are one cell in Lua, but varying sizes on the SNES.
addNative{name="CHARS", runtime=function()
  -- Noop.
  rts()
end,
asm=function() return [[
  rts
]] end}

addNative{name="CELLS", runtime=function()
  dataStack:push(dataStack:pop() * 2)
  rts()
end,
asm=function() return [[
  asl z:1, X
  rts
]] end}

addNative{name="ADDRS", runtime=function()
  dataStack:push(dataStack:pop() * 2)
  rts()
end,
asm=function() return [[
  clc
  lda z:1, X
  asl A
  adc z:1, X
  sta z:1, X
  rts
]] end}

addNative{name="DATASPACE", runtime=function()
  dataspace:print(outputs)
  rts()
end}

addNative{name="DEPTH", runtime=function()
  dataStack:push(dataStack:entries())
  rts()
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

addNative{name=".S", label="_DOT_S", runtime=function()
  dataStack:print(outputs)
  rts()
end}

addNative{name="C,", label="_C_COMMA", runtime=function()
  dataspace:addByte(dataStack:pop() & 0xFF)
  rts()
end}

addNative{name=",", label="_COMMA", runtime=function()
  dataspace:addWord(dataStack:pop())
  rts()
end}

addNative{name="A.,", label="_A_COMMA", runtime=function()
  -- TODO: Zero top byte? Or error?
  dataspace:addAddress(dataStack:popDouble())
  rts()
end}

addNative{name="XT,", label="_XT_COMMA", runtime=function()
  -- TODO: How do we deal with this when we quantize dataspace?
  local xt = dataStack:pop()
  dataspace:addWord(xt)
  if debugging() then
    local name = dictionary:addrName(xt) or "missing name"
    infos:write("Compiling XT " .. name .. "\n")
  end
  rts()
end}

-- Set the XT for the latest word to start a docol at addr
-- TODO: How will this work on the SNES?
addNative{name="XT!", label="_XT_STORE", runtime=function()
  local addr = dataStack:pop()
  -- Update the EXIT to instead jump to the code after DODOES.
  local exitAddress = dictionary:latest().addr + 3 + 2 + 1
  dataspace:setWord(exitAddress, addr)
  rts()
end}

addNative{name="CREATE", runtime=function()
  local name = input:word()
  dictionary:add(name, name, dataspace.here)
  addWords("LIT")
  local dataAddrAddr = dataspace.here
  dataspace:addWord(0)
  addWords("EXIT")
  dataspace:setWord(dataAddrAddr, dataspace.here)
  rts()
end}

addNative{name="CREATEDOCOL", runtime=function()
  local name = input:word()
  addColon(name)
  rts()
end}

addNative{name="ALLOT", runtime=function()
  dataspace.here = dataspace.here + dataStack:pop()
  rts()
end}

-- TODO: For now we'll actually implement EXIT in ASM, but on the SNES it should
-- just be a `RTS` and not `JSR EXIT` like other Forth words.
addNative{name="EXIT", runtime=function()
  returnStack:popWord()
  rts()
end,
asm=function() return [[
  ; Remove the caller's return address (2 bytes) and return.
  tsa
  inc A
  inc A
  tas
  rts
]] end}

addNative{name=".", label="_DOT", runtime=function()
  outputs:write(dataStack:pop() .. "\n")
  rts()
end}

addNative{name="BYE", runtime=function()
  infos:write("WE DONE!" .. "\n")
  running = false
  rts()
end}

addNative{name="ABORT", runtime=function()
  infos:write("ABORTED!" .. "\n")
  assert(nil)
  rts()
end}

addNative{name="EMIT", runtime=function()
  outputs:write(string.char(dataStack:pop()))
  rts()
end}

local wordBufferAddr = dataspace.here
local wordBufferSize = 32
dataspace:addWord(0)
for i=1,wordBufferSize do
  dataspace:addByte(0)
end

function setWordBuffer(str)
  local length = string.len(str)
  assert(length < wordBufferSize, "Strings length too large: " .. str)
  dataspace:setWord(wordBufferAddr, length)
  for i=1,length do
    dataspace:setByte(wordBufferAddr + 1 + i, string.byte(string.sub(str, i, i)))
  end
end

function getWordWithCount(addr, count)
  local str = ""
  for i=0,count-1 do
    str = str .. string.char(dataspace:getByte(addr + i))
  end
  return str
end

function getCountedWord(addr)
  local count = dataspace:getWord(addr)
  return getWordWithCount(addr + 2, count)
end

addNative{name="WORD", runtime=function()
  setWordBuffer(input:word() or "")
  dataStack:push(wordBufferAddr)
  rts()
end}

addNative{name="PEEK", runtime=function()
  dataStack:push(input:peek())
  rts()
end}

addNative{name="KEY", runtime=function()
  dataStack:push(input:key())
  rts()
end}

addNative{name="TYPE", runtime=function()
  local count = dataStack:pop()
  local addr = dataStack:pop()
  outputs:write(getWordWithCount(addr, count))
  rts()
end}

-- Can probably be written in Forth? Though not interpreted-Forth.
addNative{name="FIND", runtime=function()
  local wordAddress = dataStack:pop()
  local word = getCountedWord(wordAddress)
  local dictEntry = dictionary:find(word)
  if not dictEntry then
    dataStack:push(wordAddress)
    dataStack:push(0)
  elseif dictEntry.immediate then
    dataStack:push(dictEntry.addr)
    dataStack:push(1)
  else
    dataStack:push(dictEntry.addr)
    dataStack:push(0xFFFF)
  end
  rts()
end}

-- Non-standard. Returns TRUE or FALSE at the top of the stack.
addNative{name=">NUMBER", label="_TO_NUMBER", runtime=function()
  local strAddress = dataStack:pop()
  local str = getCountedWord(strAddress)
  local number = tonumber(str)
  if number == nil then
    dataStack:push(0)
    -- Failed.
    dataStack:push(0)
    rts()
    return
  end

  if number > 0xFFFF or number < -0x8000 then
    dataStack:push(0)
    -- Failed.
    dataStack:push(0)
    rts()
    return
  end

  dataStack:push(toUnsigned(number))
  dataStack:push(0xFFFF)
  rts()
end}

-- Returns TRUE or FALSE at the top of the stack, and the parsed address below
-- that.
addNative{name=">ADDRESS", label="_TO_ADDRESS", runtime=function()
  local strAddress = dataStack:pop()
  local maybeAddress = getCountedWord(strAddress)
  if string.sub(maybeAddress, 1, 1) ~= "$" then
    dataStack:pushDouble(0)
    -- Failed.
    dataStack:push(0)
    rts()
    return
  end

  local address = tonumber(string.sub(maybeAddress, 2), 16)
  if address == nil then
    dataStack:pushDouble(0)
    -- Failed.
    dataStack:push(0)
    rts()
    return
  end

  if address > 0xFFFFFF or address < 0 then
    dataStack:pushDouble(0)
    -- Failed.
    dataStack:push(0)
    rts()
    return
  end

  dataStack:pushDouble(address)
  dataStack:push(0xFFFF)
  rts()
end}

addNative{name="DUP", runtime=function()
  dataStack:push(dataStack:top())
  rts()
end,
asm=function() return [[
  lda z:1,X
  PUSH_A
  rts
]] end}

addNative{name="2DUP", runtime=function()
  local double = dataStack:topDouble()
  dataStack:pushDouble(double)
  rts()
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

addNative{name="DROP", runtime=function()
  dataStack:pop()
  rts()
end,
asm=function() return [[
  inx
  inx
  rts
]] end}

addNative{name="2DROP", runtime=function()
  dataStack:popDouble()
  rts()
end,
asm=function() return [[
  inx
  inx
  inx
  inx
  rts
]] end}

addNative{name="SWAP", runtime=function()
  local first = dataStack:pop()
  local second = dataStack:pop()
  dataStack:push(first)
  dataStack:push(second)
  rts()
end,
asm=function() return [[
  ldy z:1, X
  lda z:3, X
  sta z:1, X
  sty z:3, X
  rts
]] end}

addNative{name="2SWAP", runtime=function()
  local first = dataStack:popDouble()
  local second = dataStack:popDouble()
  dataStack:pushDouble(first)
  dataStack:pushDouble(second)
  rts()
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

addNative{name="COMPILE,", label="_COMPILE_COMMA", runtime=function()
  local xt = dataStack:pop()
  addCall(xt)
  if debugging() then
    local name = dictionary:addrName(xt) or "missing name"
    infos:write("Compiling " .. name .. "\n")
  end
  rts()
end}

-- Pushes the address of the first character of the string, then the size of the
-- string in bytes.
addNative{name="COUNT", runtime=function()
  local addr = dataStack:pop()
  local length = dataspace:getWord(addr)
  dataStack:push(addr + 1)
  dataStack:push(length)
  rts()
end}

-- Move a 2-byte word from from data stack to the R stack.
addNative{name=">R", label="_TO_R", runtime=function()
  local holdReturn = returnStack:popWord()
  returnStack:pushWord(dataStack:pop())
  returnStack:pushWord(holdReturn)
  rts()
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
addNative{name="A.>R", label="_A_TO_R", runtime=function()
  local holdReturn = returnStack:popWord()
  returnStack:pushAddress(dataStack:popDouble())
  returnStack:pushWord(holdReturn)
  rts()
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

addNative{name="R>", label="_FROM_R", runtime=function()
  local holdReturn = returnStack:popWord()
  dataStack:push(returnStack:popWord())
  returnStack:pushWord(holdReturn)
  rts()
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

addNative{name="A.R>", label="_A_FROM_R", runtime=function()
  local holdReturn = returnStack:popWord()
  dataStack:pushDouble(returnStack:popAddress())
  returnStack:pushWord(holdReturn)
  rts()
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

addNative{name="R@", label="_FETCH_R", runtime=function()
  local holdReturn = returnStack:popWord()
  dataStack:push(returnStack:topWord())
  returnStack:pushWord(holdReturn)
  rts()
end,
asm=function() return [[
  lda 3, S
  PUSH_A
  rts
]] end}

addNative{name="A.R@", label="_A_FETCH_R", runtime=function()
  local holdReturn = returnStack:popWord()
  dataStack:pushDouble(returnStack:topAddress())
  returnStack:pushWord(holdReturn)
  rts()
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
  ip = dataspace:fromRelativeAddress(retAddr, toSigned(dataspace:getWord(retAddr)))
end

addNative{name="BRANCH0", runtime=function()
  if dataStack:pop() == 0 then
    branch()
  else
    -- Skip past the relative address.
    ip = returnStack:popWord() + 2
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

addNative{name="ADDRESS-OFFSET", runtime=function()
  local from = dataStack:pop()
  local to = dataStack:pop()
  local delta = dataspace:toRelativeAddress(from, to)
  assert(delta >= -0x8000 and delta <= 0x7FFF, "Delta out of range: " .. delta)
  dataStack:push(toUnsigned(delta))
  rts()
end}

-- Can we do this in Forth based on BRANCH0?
addNative{name="BRANCH", runtime=function()
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
addNative{name="@", label="_FETCH", runtime=function()
  local addr = dataStack:pop()
  dataStack:push(dataspace:getWord(addr))
  rts()
end,
asm=function() return [[
  lda (1, X)
  sta 1, X
  rts
]] end}

addNative{name="!", label="_STORE", runtime=function()
  local addr = dataStack:pop()
  local val = dataStack:pop()
  dataspace:setWord(addr, val)
  rts()
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

-- Takes a local address (2 bytes) off the stack and pushes 1 byte plus a zeroed
-- high byte.
addNative{name="C@", label="_C_FETCH", runtime=function()
  local addr = dataStack:pop()
  dataStack:push(dataspace:getByte(addr))
  rts()
end,
asm=function() return [[
  A8
  lda (1, X)
  A16
  and #$FF
  sta 1, X
  rts
]] end}

addNative{name="C!", label="_C_STORE", runtime=function()
  local addr = dataStack:pop()
  local val = dataStack:pop()
  dataspace:setByte(addr, val & 0xFF)
  rts()
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

-- Takes a far address (2 cells) off the stack and pushes a 1 cell word.
addNative{name="F@", label="_FAR_FETCH", runtime=function()
  local addr = dataStack:popDouble()
  --TODO: Should be getFarWord
  dataStack:push(dataspace:getWord(addr))
  rts()
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

addNative{name="F!", label="_FAR_STORE", runtime=function()
  local addr = dataStack:popDouble()
  local val = dataStack:pop()
  --TODO: Should be setFarWord
  dataspace:setWord(addr, val)
  rts()
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

addNative{name="1+", label="_INCR", runtime=function()
  dataStack:push(dataStack:pop() + 1)
  rts()
end,
asm=function() return [[
  inc z:1, X
  rts
]] end}

addNative{name="DOUBLE+", label="_DOUBLE_INCR", runtime=function()
  dataStack:pushDouble(dataStack:popDouble() + 1)
  rts()
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

addNative{name="LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litAddr = returnStack:popWord()
  -- increment the return address to skip the literal
  returnStack:pushWord(litAddr + 2)
  dataStack:push(dataspace:getWord(litAddr))
  rts()
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

addNative{name="A.LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litAddr = returnStack:popWord()
  -- increment the return address to skip the literal
  returnStack:pushWord(litAddr + 3)
  dataStack:pushDouble(dataspace:getAddr(litAddr))
  rts()
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

addNative{name="EXECUTE", runtime=function()
  local addr = dataStack:pop()
  if debugging() then
    local name = dictionary:addrName(addr) or "missing name"
    infos:write("Executing " .. name .. "\n")
  end
  ip = addr
  -- No rts since we're branching.
end}

addColon("TRUE")
  addWords("LIT")
  dataspace:addWord(0xFFFF)
  addWords("EXIT")

addColon("FALSE")
  addWords("LIT")
  dataspace:addWord(0)
  addWords("EXIT")

addColonWithLabel("[", "_LBRACK")
  addWords("FALSE STATE ! EXIT")
dictionary:latest().immediate = true

addColonWithLabel("]", "_RBRACK")
  addWords("TRUE STATE ! EXIT")

addNative{name="IMMEDIATE", runtime=function()
  dictionary:latest().immediate = true
  rts()
end}

addNative{name="LABEL", runtime=function()
  local label = input:word()
  dictionary:latest().label = label
  rts()
end}

addColon("DODOES")
  -- TODO: More to consider here, probably need to change XT!
  -- TODO: Should probably use INLINE-DATA instead of R>
  addWords("R> XT! EXIT")  -- Ends the calling word (CREATEing) early.

addColonWithLabel("DOES>", "_DOES")
  addWords("LIT")
  addXt("DODOES")
  addWords("COMPILE,")

  -- Need to drop the return address so we skip returning to the codeword of the
  -- DOES body.
  -- TODO: It should just be a jmp instead instead of a jsr.
  addWords("LIT")
  addXt("R>")
  addWords("COMPILE,")

  addWords("LIT")
  addXt("DROP")
  addWords("COMPILE,")

  addWords("EXIT")
dictionary:latest().immediate = true

-- TODO: Maybe pull these out into a mathops.lua file?
function unaryOp(name, label, op, asm)
  addNative{name=name, label=label, runtime=function()
    local a = dataStack:pop()
    dataStack:push(op(a) & 0xFFFF)
    rts()
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
    rts()
  end
end

function binaryOpWithLabel(name, label, op, asmOp)
  addNative{name=name, label=label, runtime=binaryOpRt(op), asm=function() return string.format([[
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
  addNative{name=name, label=label, runtime=function()
    local b = dataStack:pop()
    local a = dataStack:pop()
    dataStack:push(op(a,b) and 0xFFFF or 0)
    rts()
  end,
  asm=function() return string.format([[
    ldy #$FFFF
    lda z:3, X
    sec
    sbc z:1, X
    %s :+
    ldy #$0000
  :
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
  addWords("CREATEDOCOL ] EXIT")
end

do
  addColonWithLabel(";", "_SEMICOLON")
  addWords("[ LIT")
  addXt("EXIT")
  -- Also need to make the word visible now.
  addWords("COMPILE, EXIT")
  dictionary:latest().immediate = true
end

-- Given a return stack entry, push where the inline data for this word is.
addNative{name="INLINE-DATA", runtime=function()
  -- The return stack in Lua already points at the inline data.
  rts()
end,
asm=function() return [[
  ; We're one byte behind the inline data.
  inc 1, X
  rts
]] end}

-- Push the inline string address and the length.
addColonWithLabel("DOS\"", "_DO_SLIT")
do
  addWords("R@ INLINE-DATA DUP LIT")
  dataspace:addWord(1)
  addWords("CELLS + SWAP @ DUP CHARS LIT")
  dataspace:addWord(1)
  addWords("CELLS + R> + >R EXIT")
end

addColonWithLabel("S\"", "_SLIT")
do
  addWords("LIT")
  addXt("DOS\"")
  addWords("COMPILE,")
  -- Make space for the length and save its addr.
  addWords("HERE LIT")
  dataspace:addWord(0)
  addWords("DUP ,") -- Also grab a zero to track the length.
  addWords("KEY DROP") -- Discard the first whitespace.
  local loop = dataspace.here
  addWords("KEY DUP LIT")
  dataspace:addWord(string.byte('"'))
  addWords("<> BRANCH0")
  local exitBranchAddr = dataspace.here
  dataspace:addWord(2000)
  addWords("C, 1+ BRANCH")
  dataspace:addWord(toUnsigned(dataspace:getRelativeAddr(dataspace.here, loop)))
  dataspace:setWord(exitBranchAddr, toUnsigned(dataspace:getRelativeAddr(exitBranchAddr, dataspace.here)))
  addWords("DROP SWAP !") -- Drop the " and fill in the length
  addWords("EXIT")
end
dictionary:latest().immediate = true

do
  -- TODO: Can we define a simpler QUIT here and then define the real QUIT in
  -- Forth?
  addColon("QUIT")
  local loop = dataspace.here
  -- Grab the length of the counted string with @.
  addWords("WORD DUP @ BRANCH0")
  local eofBranchAddr = dataspace.here
  dataspace:addWord(2000)

  addWords("FIND")

  addWords("DUP LIT")
  dataspace:addWord(0)
  addWords("= BRANCH0")
  local wordFoundBranchAddr = dataspace.here
  dataspace:addWord(2000) -- will be replaced later
    -- Not found, try and parse as a number.
    addWords("DROP DUP >NUMBER BRANCH0")
    local numberParseErrorAddr = dataspace.here
    dataspace:addWord(2000)
    -- String is no longer needed, drop it.
    addWords(">R DROP R>")
    -- If we're compiling, compile TOS as a literal.
    addWords("STATE @ BRANCH0")
    dataspace:addWord(toUnsigned(dataspace:getRelativeAddr(dataspace.here, loop)))
    -- LIT the LIT so we can LIT while we LIT.
    addWords("LIT")
    addXt("LIT")
    -- Compile LIT and then the number.
    addWords("COMPILE, , BRANCH")
    dataspace:addWord(toUnsigned(dataspace:getRelativeAddr(dataspace.here, loop)))

    dataspace:setWord(numberParseErrorAddr, toUnsigned(dataspace:getRelativeAddr(numberParseErrorAddr, dataspace.here)))
    addWords("DROP DUP >ADDRESS BRANCH0")
    local addressParseErrorAddr = dataspace.here
    dataspace:addWord(2000)
    -- String is no longer needed, drop it.
    addWords(">R >R DROP R> R>")
    -- If we're compiling, compile TOS as a literal.
    addWords("STATE @ BRANCH0")
    dataspace:addWord(toUnsigned(dataspace:getRelativeAddr(dataspace.here, loop)))
    -- LIT the A.LIT so we can A.LIT while we LIT.
    addWords("LIT")
    addXt("A.LIT")
    -- Compile A.LIT and then the number.
    addWords("COMPILE, A., BRANCH")
    dataspace:addWord(toUnsigned(dataspace:getRelativeAddr(dataspace.here, loop)))
  dataspace:setWord(wordFoundBranchAddr, toUnsigned(dataspace:getRelativeAddr(wordFoundBranchAddr, dataspace.here)))

  -- Word found, see if we're compiling or interpreting.
  addWords("LIT")
  dataspace:addWord(0)
  addWords("> STATE @ INVERT OR BRANCH0")
  local branchAddrIfNotImmediate = dataspace.here
  dataspace:addWord(2000) -- will be replaced later
    -- Interpreting, just run the word.
    addWords("EXECUTE BRANCH")
    dataspace:addWord(toUnsigned(dataspace:getRelativeAddr(dataspace.here, loop)))
  dataspace:setWord(branchAddrIfNotImmediate, toUnsigned(dataspace:getRelativeAddr(branchAddrIfNotImmediate, dataspace.here)))

  -- else, compiling
  addWords("COMPILE, BRANCH")
  dataspace:addWord(toUnsigned(dataspace:getRelativeAddr(dataspace.here, loop)))

  dataspace:setWord(addressParseErrorAddr, toUnsigned(dataspace:getRelativeAddr(addressParseErrorAddr, dataspace.here)))
  addWords("2DROP DUP COUNT TYPE")
  addWords("DOS\"")
  dataspace:addWord(2)
  dataspace:addByte(string.byte("?"))
  dataspace:addByte(string.byte("\n"))
  addWords("TYPE ABORT")
  dataspace:setWord(eofBranchAddr, toUnsigned(dataspace:getRelativeAddr(eofBranchAddr, dataspace.here)))
  addWords("DROP EXIT")
end

ip = dataspace.here -- start on creating QUIT, below
print(string.format("Starting IP at %04X", ip))
addWords("QUIT")
addWords("BYE")

if debugging() then
  infos:write(string.format("here: %s\n", Dataspace.formatAddr(dataspace.here)))

  dataspace:print(infos)
end

-- The processing loop.
while running do
  -- Capture ip value so instruction can modify the next ip.
  local oldip = ip
  local instruction = dataspace[oldip]
  if instruction.type ~= "native" then
    assertAddr(nil, "Attempted to execute a non-call, non-native cell: %s\n", oldip)
  end

  if debugging() then
    local name = dictionary:addrName(oldip) or dataspace[oldip]:toString(dataspace, oldip)
    infos:write(string.format("Executing IP = %s (native %s)\n", Dataspace.formatAddr(oldip), name))
    infos:write(" == data ==\n")
    dataStack:print(infos)
    infos:write(" == return ==\n")
    returnStack:print(infos)
  end

  instruction:runtime(dataspace, oldip)
end


if debugging() then
  dataspace:print(infos)

  dataStack:print(infos)
end

local output = assert(io.open(arg[2], "w"))
output:write([[
.p816
.i16
.a16
.import not_implemented

.segment "UNSIZED"

.include "preamble.s"

.export _MAIN

]])

dataspace:assembly(output)

