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

local outputs = io.stdout
local infos = io.stdout
local errors = io.stderr
local dumpFile = assert(io.open("dataspace.dump", "w"))

local dictionary = Dictionary:new()
local dataspace = Dataspace:new()
  
local running = true
local ip = 0

local function assertAddr(cond, message, addr)
  dataspace:assertAddr(dumpFile, cond, message, addr)
end

local function toSigned(unsignedWord)
  if unsignedWord > 0x7FFF then
    return unsignedWord - 0x10000
  end
  return unsignedWord
end

local function toUnsigned(signedWord)
  return signedWord & 0xFFFF
end

local Call = Dataspace.Native:new()

function Call:size()
  return 3
end

-- Closes over returnStack and ip
function Call:runtime(dataspace, opAddr)
  ip = ip + self:size()
  local callAddr = self:addr(dataspace, opAddr)
  -- TODO: Can probably just remove this check as the interpreter will do it
  assert(dataspace[callAddr].type == "native", string.format("Expected native at %s", Dataspace.formatAddr(callAddr)))
  -- TODO: To match the 65816 this should be ip - 1
  returnStack:pushWord(ip)
  ip = callAddr
end

function Call:addr(dataspace, opAddr)
  return dataspace:getWord(opAddr + 1)
end

-- Closes over dictionary
function Call:toString(dataspace, opAddr)
  local callAddr = self:addr(dataspace, opAddr)
  local name = dictionary:addrName(callAddr)
  if not name then
    return string.format("Call to $%04X (missing name)", callAddr)
  end
  return string.format("Call $%04X (to %s)", callAddr, name)
end

-- Closes over dictionary
function Call:asm(dataspace, opAddr)
  local callAddr = self:addr(dataspace, opAddr)
  assert(dataspace[callAddr].type == "native", string.format("Expected native at %s", Dataspace.formatAddr(callAddr)))

  local label = dictionary:addrLabel(callAddr)
  if label then
    return string.format([[
      jsr %s
    ]], label)
  else
    -- TODO: Assert that we're in sized space. Or maybe just assert that we
    -- can get an address/label for the given (Lua) address?
    return string.format([[
      jsr $%04X ; Cross our fingers!
    ]], callAddr)
  end
end

local function compileCall(addr)
  dataspace:compile(Call:new())
  dataspace:compileWord(addr)
end

local Branch0 = Dataspace.Native:new()

function Branch0:size()
  return 10
end

-- Closes over ip
function Branch0:runtime(dataspace, opAddr)
  ip = ip + self:size()
  local offset = self:offset(dataspace, opAddr)
  if dataStack:pop() == 0 then
    ip = dataspace:fromRelativeAddress(ip, offset)
  end
end

function Branch0:offset(dataspace, opAddr)
  return toSigned(dataspace:getWord(opAddr + 8))
end

-- Closes over dictionary
function Branch0:toString(dataspace, opAddr)
  local offset = self:offset(dataspace, opAddr)
  return string.format("Branch0 $%04X", offset)
end

-- Closes over dictionary
function Branch0:asm(dataspace, opAddr)
  local branchOffset = self:offset(dataspace, opAddr)
  return string.format([[
    lda z:1, X     ; 2 bytes
    inx            ; 1 byte
    inx            ; 1 byte
    tay            ; 1 byte
    bne :+         ; 2 bytes
    brl (:+)+%d    ; 1 byte prior to branch offset ($%04X)
  :
  ]], branchOffset, toUnsigned(branchOffset))
end

local function compileBranch0(offset)
  local branchEntry = Branch0:new()
  dataspace:compile(branchEntry)
  -- A couple of filler words so addresses stay correct. Other than this space
  -- we compile 3 bytes of code (the op above and the offset below).
  dataspace:allotCodeBytes(branchEntry:size() - 2 - 1)
  local offsetAddr = dataspace:getCodeHere()
  dataspace:compileWord(offset)
  return offsetAddr
end

local function compileBranch0To(addr)
  local offsetAddr = compileBranch0(0x9999)
  dataspace:setWord(
    offsetAddr,
    toUnsigned(dataspace:getRelativeAddr(dataspace:getCodeHere(), addr)))
end

local function compileForwardBranch0()
  local branchOffsetAddr = compileBranch0(0x9999)
  return {
    toHere = function()
      local branchOffset = toUnsigned(
        dataspace:getRelativeAddr(branchOffsetAddr + 2, dataspace:getCodeHere()))
      dataspace:setWord(branchOffsetAddr, branchOffset)
    end
  }
end

local Branch = Dataspace.Native:new()

function Branch:size()
  return 3
end

-- Closes over ip
function Branch:runtime(dataspace, opAddr)
  -- Branch location is an offset from the beginning of the next instruction.
  ip = ip + self:size()
  local offset = self:offset(dataspace, opAddr)
  ip = dataspace:fromRelativeAddress(ip, offset)
end

function Branch:offset(dataspace, opAddr)
  return toSigned(dataspace:getWord(opAddr + 1))
end

-- Closes over dictionary
function Branch:toString(dataspace, opAddr)
  local offset = self:offset(dataspace, opAddr)
  return string.format("Branch $%04X", offset)
end

-- Closes over dictionary
function Branch:asm(dataspace, opAddr)
  local branchOffset = self:offset(dataspace, opAddr)
  return string.format([[
    brl (:+)+%d    ; branch offset = $%04X
  :
  ]], branchOffset, toUnsigned(branchOffset))
end

local function compileBranch(offset)
  dataspace:compile(Branch:new())
  local offsetAddr = dataspace:getCodeHere()
  dataspace:compileWord(offset)
  return offsetAddr
end

local function compileBranchTo(addr)
  local offsetAddr = compileBranch(0x9999)
  dataspace:setWord(
    offsetAddr,
    toUnsigned(dataspace:getRelativeAddr(dataspace:getCodeHere(), addr)))
end

local function compileForwardBranch()
  local branchOffsetAddr = compileBranch(0x9999)
  return {
    toHere = function()
      local branchOffset = toUnsigned(
        dataspace:getRelativeAddr(branchOffsetAddr + 2, dataspace:getCodeHere()))
      dataspace:setWord(branchOffsetAddr, branchOffset)
    end
  }
end

local Lit = Dataspace.Native:new()

function Lit:size()
  -- See :asm(), below.
  return 3 + 1 + 1 + 2
end

-- Closes over dataStack and ip
function Lit:runtime(dataspace, opAddr)
  ip = ip + self:size()
  local value = self:value(dataspace, opAddr)
  dataStack:push(value)
end

function Lit:value(dataspace, opAddr)
  return dataspace:getWord(opAddr + 1)
end

function Lit:toString(dataspace, opAddr)
  local value = self:value(dataspace, opAddr)
  return string.format("Lit $%04X", value)
end

function Lit:asm(dataspace, opAddr)
  local value = self:value(dataspace, opAddr)
  return string.format([[
    lda #$%04X ; dataspace address, 3 bytes
    dex        ; 1 byte
    dex        ; 1 byte
    sta z:1, X ; 2 bytes
  ]], value)
end

local function compileLit(value)
  dataspace:compile(Lit:new())
  dataspace:compileWord(value)
  -- Garbage bytes to fill for assembly.
  dataspace:allotCodeBytes(1 + 1 + 2)
  -- TODO: assert that we've added bytes equal to Lit:size()
end

-- Right now this is the same as `['] name ,`.
local function compileXtLit(name)
  return compileLit(dictionary:findAddr(name))
end

local Rts = Dataspace.Native:new()

function Rts:size()
  return 1
end

-- Should be called at the end of every (normal) native words runtime() to
-- return control to the caller.
local function rts()
  ip = returnStack:popWord()
end

-- Closes over dataStack and ip
function Rts:runtime(dataspace, opAddr)
  rts()
end

function Rts:toString(dataspace, opAddr)
  return "Rts"
end

function Rts:asm(dataspace, opAddr)
  return [[
    rts
  ]]
end

local function compileRts()
  dataspace:compile(Rts:new())
end

-- Add words to the current colon defintion
local function compile(names)
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
    compileCall(callAddr)
    last = last + 1
  end
end

-- Table should have at least name and runtime specified.
local function addNative(entry)
  entry.label = entry.label or Dataspace.defaultLabel(entry.name)
  -- Native fns are unsized, so they don't affect/use HERE.
  local addr = dataspace:compileUnsized(Dataspace.Native:new(entry))
  dictionary:add(entry.name, entry.label, addr)
end

-- Make a variable that is easily accessible to Lua and the SNES.
-- Returns the dataspace address of the variable contents.
local function makeSystemVariable(name)
  local native = Dataspace.Native:new{
    name=name,
    label=Dataspace.defaultLabel(name),
  }
  addNative(native)

  local originalBank = dataspace:getDataBank()
  dataspace:setDataBank(Dataspace.LOWRAM_BANK)
  local dataaddr = dataspace:getDataHere()
  dataspace:addWord(0)
  dataspace:setDataBank(originalBank)

  native.runtime = function()
    dataStack:push(dataaddr)
    rts()
  end
  native.asm = function() return string.format([[
    dex
    dex
    ; Load address.
    lda #$%04X
    sta z:1, X
    rts
  ]], dataaddr) end
  return dataaddr
end

makeSystemVariable("STATE")
local debugAddr = makeSystemVariable("DEBUG")

if flags["-v"] then
  dataspace:setWord(debugAddr, 0xFFFF)
else
  dataspace:setWord(debugAddr, 0x0)
end

local function debugging()
  return dataspace:getWord(debugAddr) ~= 0
end

addNative{name="CODE", label="_CODE", runtime=function()
  local name = input:word()
  local asm = input:untilToken("END%-CODE")
  assert(asm)
  local native = Dataspace.Native:new{
    name = name,
    asm = function(dataspace) return asm end,
  }
  addNative(native)
  rts()
end}

local function addColonWithLabel(name, label)
  dataspace:labelCodeHere(label)
  dictionary:add(name, label, dataspace:getCodeHere())
end

local function addColon(name)
  addColonWithLabel(name, Dataspace.defaultLabel(name))
end

addNative{name="BANK@", label="_BANK_FETCH", runtime=function()
  dataStack:push(dataspace:getDataBank())
  rts()
end}

addNative{name="BANK!", label="_BANK_STORE", runtime=function()
  dataspace:setDataBank(dataStack:pop())
  rts()
end}

addNative{name="LOWRAM", runtime=function()
  dataStack:push(dataspace.LOWRAM_BANK)
  rts()
end}

addNative{name="HERE", runtime=function()
  dataStack:push(dataspace:getDataHere())
  rts()
end}

addNative{name="CODEHERE", runtime=function()
  dataStack:push(dataspace:getCodeHere())
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

local function stacktrace()
  local calls = {}
  local i = #returnStack - 1
  while i > 0 do
    local address = ((returnStack[i] << 8) | returnStack[i+1]) - 3
    local callString = dataspace[address]:toString(dataspace, address) or "{no name}"
    table.insert(calls, string.format("$%04X: %s\n", address, callString))
    i = i - 2
  end
  return table.concat(calls)
end

addNative{name="STACKTRACE", runtime=function()
  infos:write(stacktrace())
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

-- TODO: This is now basically the same as "," now . Should that be the case?
-- e.g. should we be able to store a label in Dataspace and have it resolved by
-- the assembler? I think this is only necessary for calls to unsized words.
addNative{name="XT,", label="_XT_COMMA", runtime=function()
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
  -- CREATEd word looks like:
  --   lda $1234 ; dataspace address, 3 byte instruction
  --   dex ; 1 byte
  --   dex ; 1 byte
  --   sta z:1, x ; 2 bytes
  --   jsr EXIT ; 1 byte opcode + 2 byte addr, we want the addr
  local exitAddress = dictionary:latest().addr + 3 + 1 + 1 + 2 + 1
  dataspace:setWord(exitAddress, addr)
  rts()
end}

addNative{name="CREATE", runtime=function()
  local name = input:word()
  local label = Dataspace.defaultLabel(name)
  dictionary:add(name, label, dataspace:getCodeHere())
  dataspace:labelCodeHere(label)
  dataspace:labelDataHere(label .. "_data")
  -- The value of the Lit is 1 byte into the assembly.
  -- Need to wait to set this until after we're done compiling the execution
  -- behavior because data ptr and code ptr might be using the same bank.
  local dataAddrAddr = dataspace:getCodeHere() + 1
  compileLit(0)
  -- TODO: We should use compileRts() here instead, but once we do that we'll
  -- also need to add a Jmp instruction to replace it with when we call DOES>.
  compile("EXIT")
  dataspace:setWord(dataAddrAddr, dataspace:getDataHere())
  rts()
end}

addNative{name="CONSTANT", runtime=function()
  local name = input:word()
  local value = dataStack:pop()
  local label = Dataspace.defaultLabel(name)
  dictionary:add(name, label, dataspace:getCodeHere())
  dataspace:labelCodeHere(label)
  compileLit(value)
  compileRts()
  rts()
end}

addNative{name="CREATEDOCOL", runtime=function()
  local name = input:word()
  addColon(name)
  rts()
end}

addNative{name="ALLOT", runtime=function()
  dataspace:allotDataBytes(dataStack:pop())
  rts()
end}

-- TODO: Maybe this should compile an RTS instead?
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
  dataspace:print(dumpFile)
  dumpFile:write(" == data ==\n")
  dataStack:print(dumpFile)
  dumpFile:write(" == return ==\n")
  returnStack:print(dumpFile)
  infos:write("Stacktrace:\n")
  infos:write(stacktrace())
  assert(nil)
  rts()
end}

addNative{name="EMIT", runtime=function()
  outputs:write(string.char(dataStack:pop()))
  rts()
end}

local wordBufferAddr = dataspace:getDataHere()
local wordBufferSize = 32
-- Currently allocating this in ROM, but if we move the interpreter to the SNES
-- then it should be in RAM (probably high-ram).
dataspace:addWord(0)
dataspace:allotDataBytes(wordBufferSize)

local function setWordBuffer(str)
  local length = string.len(str)
  assert(length < wordBufferSize, "Strings length too large: " .. str)
  dataspace:setWord(wordBufferAddr, length)
  for i=1,length do
    dataspace:setByte(wordBufferAddr + 1 + i, string.byte(string.sub(str, i, i)))
  end
end

local function getWordWithCount(addr, count)
  local str = ""
  for i=0,count-1 do
    str = str .. string.char(dataspace:getByte(addr + i))
  end
  return str
end

local function getCountedWord(addr)
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

addNative{name="PRINT-LINE", runtime=function()
  outputs:write(input.line)
  rts()
end}

addNative{name="LINE#", runtime=function()
  dataStack:push(input.lineNo)
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
  compileCall(xt)
  if debugging() then
    local name = dictionary:addrName(xt) or "missing name"
    infos:write("Compiling " .. name .. "\n")
  end
  rts()
end}

addNative{name="COMPILE-WORD", label="_COMPILE_WORD", runtime=function()
  dataspace:compileWord(dataStack:pop())
  rts()
end}

addNative{name="COMPILE-CHAR", label="_COMPILE_CHAR", runtime=function()
  dataspace:compileByte(dataStack:pop() & 0xFF)
  rts()
end}

-- Pushes the address of the first character of the string, then the size of the
-- string in bytes.
addNative{name="COUNT", runtime=function()
  local addr = dataStack:pop()
  local length = dataspace:getWord(addr)
  dataStack:push(addr + 2)
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

addNative{name="ADDRESS-OFFSET", runtime=function()
  local from = dataStack:pop()
  local to = dataStack:pop()
  local delta = dataspace:getRelativeAddr(from, to)
  assert(delta >= -0x8000 and delta <= 0x7FFF, "Delta out of range: " .. delta)
  dataStack:push(toUnsigned(delta))
  rts()
end}

addNative{name="COMPILE-BRANCH", runtime=function()
  compileBranch(dataStack:pop())
  rts()
end}

addNative{name="COMPILE-BRANCH0", runtime=function()
  compileBranch0(dataStack:pop())
  rts()
end}

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

-- Inlines a literal into dataspace (e.g. calls LDA #x instead of a word).
-- TODO: LITERAL is the immediate version of this.
addNative{name="COMPILE-LIT", runtime=function()
  compileLit(dataStack:pop())
  rts()
end}

addNative{name="A.LIT", runtime=function()
  -- return stack should be the next IP, where the literal is located
  local litAddr = returnStack:popWord()
  -- increment the return address to skip the literal
  returnStack:pushWord(litAddr + 3)
  dataStack:pushDouble(dataspace:getAddr(litAddr))
  rts()
end,
-- TODO: calls to A.LIT should be inlined if we use this more often.
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
    infos:write("EXECUTEing " .. name .. "\n")
  end
  ip = addr
  -- No rts since we're branching.
end,
asm=function() return [[
  lda 1, X
  inx
  inx
  pha
  ; "return" to the new address
  rts
]] end}

addColon("TRUE")
  compileLit(0xFFFF)
  compileRts()

addColon("FALSE")
  compileLit(0)
  compileRts()

addColonWithLabel("[", "_LBRACK")
  compile("FALSE STATE !")
  compileRts()
dictionary:latest().immediate = true

addColonWithLabel("]", "_RBRACK")
  compile("TRUE STATE !")
  compileRts()

addNative{name="IMMEDIATE", runtime=function()
  dictionary:latest().immediate = true
  rts()
end}

addNative{name="LABEL", runtime=function()
  local label = input:word()
  dictionary:latest().label = label
  dataspace[dictionary:latest().addr].label = label
  rts()
end}

addColon("DODOES")
  -- TODO: More to consider here, probably need to change XT!
  -- TODO: Should probably use INLINE-DATA instead of R>
  compile("R> XT!")  -- Ends the calling word (CREATEing) early.
  compileRts()

addColonWithLabel("DOES>", "_DOES")
  compileXtLit("DODOES")
  compile("COMPILE,")

  -- Need to drop the return address so we skip returning to the codeword of the
  -- DOES body.
  -- TODO: It should just be a jmp instead instead of a jsr.
  compileXtLit("R>")
  compile("COMPILE,")

  compileXtLit("DROP")
  compile("COMPILE,")

  compileRts()
dictionary:latest().immediate = true

-- TODO: Maybe pull these out into a mathops.lua file?
local function unaryOp(name, label, op, asm)
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

unaryOp("HIBYTE", "_HIBYTE", function(a)
  return (0xFF00 & a) >> 8
end, [[
  lda z:1, X
  xba
  and #$FF
  sta z:1, X
  rts
]])

unaryOp("SWAPBYTES", "_SWAPBYTES", function(a)
  return ((0xFF00 & a) >> 8) | ((0xFF & a) << 8)
end, [[
  lda z:1, X
  xba
  sta z:1, X
  rts
]])

local function binaryOpRt(op)
  return function()
    local b = dataStack:pop()
    local a = dataStack:pop()
    dataStack:push(op(a,b) & 0xFFFF)
    rts()
  end
end

local function binaryOpWithLabel(name, label, op, asmOp)
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

addNative{name="SIN", label="_SIN", runtime=function()
  dataStack:push(math.floor(0x7FFF * math.sin(dataStack:pop() * 2 * math.pi / 0x10000)) & 0xFFFF)
  rts()
end}

addNative{name="*", label="_MULTIPLY", runtime=function()
  dataStack:push((dataStack:pop() * dataStack:pop()) & 0xFFFF)
  rts()
end}

local function binaryCmpOp(name, label, op, asmOp)
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

binaryCmpOp("<=", "_LTE", function(a, b)
  return toSigned(a) <= toSigned(b)
end, "bmi")

binaryCmpOp(">", "_GT", function(a, b)
  return toSigned(a) > toSigned(b)
end, "bpl")

binaryCmpOp(">=", "_GTE", function(a, b)
  return toSigned(a) >= toSigned(b)
end, "bpl")

binaryCmpOp("U<", "_UNSIGNED_LT", function(a, b)
  return toUnsigned(a) < toUnsigned(b)
end, "bcc")

binaryCmpOp("U<=", "_UNSIGNED_LTE", function(a, b)
  return toUnsigned(a) <= toUnsigned(b)
end, "bcc")

binaryCmpOp("U>", "_UNSIGNED_GT", function(a, b)
  return toUnsigned(a) > toUnsigned(b)
end, "bcs")

binaryCmpOp("U>=", "_UNSIGNED_GTE", function(a, b)
  return toUnsigned(a) >= toUnsigned(b)
end, "bcs")

do
  addColonWithLabel(":", "_COLON")
  compile("CREATEDOCOL ]")
  compileRts()
end

addNative{name="COMPILE-RTS", runtime=function()
  compileRts()
  rts()
end}

do
  addColonWithLabel(";", "_SEMICOLON")
  compile("[ COMPILE-RTS")
  compileRts()
  -- TODO: The word should have been non-visible up to this point.
  dictionary:latest().immediate = true
end

-- Given a return stack entry, push where the inline data for this word is.
--
-- The SNES and Lua diverge a bit on how the inline data is addressed, so this
-- word allows for normalized access.
-- On the 6502, JSR pushes an address that doesn't quite jump past the JSR
-- instruction itself
-- [link](https://retrocomputing.stackexchange.com/questions/19543/why-does-the-6502-jsr-instruction-only-increment-the-return-address-by-2-bytes)
-- Also true for 816's
-- [JSL](https://web.archive.org/web/20250114225959/http://www.6502.org/tutorials/65c816opcodes.html#6.2.2.1),
-- which increments IP by 3 and not the full 4.
-- TODO: Probably should make the return stack behave the same as the SNES
-- (point at one byte behind the return address) 
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
  compile("R@ INLINE-DATA DUP")
  compileLit(1)
  compile("CELLS + SWAP @ DUP CHARS")
  compileLit(1)
  compile("CELLS + R> + >R")
  compileRts()
end

addColonWithLabel("S\"", "_SLIT")
do
  compileXtLit("DOS\"")
  compile("COMPILE,")
  -- Make space for the length and save its addr.
  compile("CODEHERE")
  compileLit(0)
  compile("DUP COMPILE-WORD") -- Also grab a zero to track the length.
  compile("KEY DROP") -- Discard the first whitespace.
  local loop = dataspace:getCodeHere()
    compile("KEY DUP")
    compileLit(string.byte('"'))
    compile("<>")
    local exitBranch = compileForwardBranch0()
    compile("COMPILE-CHAR 1+")
    compileBranchTo(loop)
  exitBranch.toHere()
  compile("DROP SWAP !") -- Drop the " and fill in the length
  compileRts()
end
dictionary:latest().immediate = true

local function branchToHereFrom(addr)
  dataspace:setWord(addr, toUnsigned(dataspace:getRelativeAddr(addr + 2, dataspace:getCodeHere())))
end

do
  -- TODO: Can we define a simpler QUIT here and then define the real QUIT in
  -- Forth?
  addColon("QUIT")
  local loop = dataspace:getCodeHere()
  -- Grab the length of the counted string with @.
  compile("WORD DUP @")
  local eofBranch = compileForwardBranch0()

  compile("FIND")

  compile("DUP")
  compileLit(0)
  compile("=")
  local wordFoundBranch = compileForwardBranch0()
    -- Not found, try and parse as a number.
    compile("DROP DUP >NUMBER")
    local numberParseErrorBranch = compileForwardBranch0()
    -- String is no longer needed, drop it.
    compile(">R DROP R>")
    -- If we're compiling, compile TOS as a literal.
    compile("STATE @")
    compileBranch0To(loop)
    -- We're compiling, so compile the LITERAL.
    compile("COMPILE-LIT")
    compileBranchTo(loop)

    numberParseErrorBranch.toHere()
    compile("DROP DUP >ADDRESS")
    local addressParseErrorBranch = compileForwardBranch0()
    -- String is no longer needed, drop it.
    compile(">R >R DROP R> R>")
    -- If we're compiling, compile TOS as a literal.
    compile("STATE @")
    compileBranch0To(loop)
    -- LIT the A.LIT so we can A.LIT while we LIT.
    compileXtLit("A.LIT")
    -- Compile A.LIT and then the number.
    compile("COMPILE, A.,")
    compileBranchTo(loop)
  wordFoundBranch.toHere()

  -- Word found, see if we're compiling or interpreting.
  compileLit(0)
  compile("> STATE @ INVERT OR")
  local notImmediateBranch = compileForwardBranch0()
    -- Interpreting, just run the word.
    compile("EXECUTE")
    compileBranchTo(loop)
  notImmediateBranch.toHere()

  -- else, compiling
  compile("COMPILE,")
  compileBranchTo(loop)

  addressParseErrorBranch.toHere()
  compile("2DROP DUP COUNT TYPE")
  compile("DOS\"")
  dataspace:compileWord(7)
  dataspace:compileByte(string.byte("?"))
  dataspace:compileByte(string.byte("\n"))
  dataspace:compileByte(string.byte("L"))
  dataspace:compileByte(string.byte("I"))
  dataspace:compileByte(string.byte("N"))
  dataspace:compileByte(string.byte("E"))
  dataspace:compileByte(string.byte(" "))
  compile("TYPE LINE# . PRINT-LINE ABORT")
  eofBranch.toHere()
  compile("DROP")
  compileRts()
end

ip = dataspace:getCodeHere() -- start on creating QUIT, below
compile("QUIT")
compile("BYE")

if debugging() then
  dataspace:print(infos)
  infos:write(string.format("CODEHERE = %s\n", Dataspace.formatAddr(dataspace:getCodeHere())))
  infos:write(string.format("Starting IP at %04X\n", ip))
end

-- The processing loop.
while running do
  -- Capture ip value so instruction can modify the next ip.
  local oldip = ip
  local instruction = dataspace[oldip]
  if instruction.type ~= "native" then
    assertAddr(nil, "Attempted to execute a non-native cell: %s\n", oldip)
  end

  if debugging() then
    local name = dictionary:addrName(oldip) or dataspace[oldip]:toString(dataspace, oldip)
    infos:write(string.format("Executing IP = %s (native %s)\n", Dataspace.formatAddr(oldip), name))
    infos:write(" == data ==\n")
    dataStack:print(infos)
    infos:write(" == return ==\n")
    returnStack:print(infos)
  end

  -- Using xpcall allows us to catch asserts and additionally print out a Forth
  -- stack trace.
  assert(xpcall(instruction.runtime, function(msg)
    errors:write("\nForth stacktrace:\n")
    errors:write(stacktrace())
    errors:write("\nLua stacktrace:\n")
    errors:write(debug.traceback(msg) .. "\n")
    return msg
  end, instruction, dataspace, oldip))
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

.include "preamble.inc"

.export _SNES_MAIN
.export _SNES_NMI

]])

dataspace:assembly(output)

dumpFile:close()
