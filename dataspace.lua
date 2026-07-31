#!/usr/bin/lua

local Dataspace = {}

-- First 0x2000 bytes of RAM, accessible from every bank from 0 to 0x3F.
Dataspace.LOWRAM_BANK = 0xFFFF
Dataspace.LOWRAM_SIZE = 0x2000

function Dataspace:new(numBanks)
  local dataspace = {
    codeBank = 0,
    dataBank = 0,
    numBanks = numBanks,
    labels = {},
    banks = {
      [Dataspace.LOWRAM_BANK] = {
        SIZED_START = 0x300,
        here = 0x300,
        UNSIZED_START = 0x1900,
        unsizedHere = 0x1900,
        segment = "BSS",
      },
    },
  }
  for bank=0,numBanks-1 do
    local bankOffset = 0x10000 * bank
    dataspace.banks[bank] = {
      SIZED_START = bankOffset + 0x8000,
      here = bankOffset + 0x8000,
      UNSIZED_START = bankOffset + 0xFA00,
      unsizedHere = bankOffset + 0xFA00,
      segment = "BANK" .. bank,
    }
  end
  setmetatable(dataspace, self)
  self.__index = self
  return dataspace
end

function Dataspace.formatAddr(addr)
  return string.format("$%04X", addr)
end

function Dataspace.bankName(bank)
  if bank == Dataspace.LOWRAM_BANK then
    return "LOWRAM Bank"
  end
  return string.format("Bank %d", bank)
end

function Dataspace:printBank(file, bank)
  file:write(string.format("== %s SIZED ==\n", Dataspace.bankName(bank)))
  local addr = self.banks[bank].SIZED_START
  while addr < self.banks[bank].here do
    local v = self[addr]
    local label = self.labels[addr]
    if label then
      file:write(string.format("%s:\n", label))
    end
    file:write(string.format("  %s: %s\n", Dataspace.formatAddr(addr), v:toString(self, addr)))
    assert(v:size())
    addr = addr + v:size()
  end
  file:write(string.format("== %s UNSIZED ==\n", Dataspace.bankName(bank)))
  addr = self.banks[bank].UNSIZED_START
  while addr < self.banks[bank].unsizedHere do
    local v = self[addr]
    local label = self.labels[addr]
    if label then
      file:write(string.format("%s:\n", label))
    end
    file:write(string.format("  %s: %s\n", Dataspace.formatAddr(addr), v:toString(self, addr)))
    addr = addr + 1
  end
end

function Dataspace:print(file)
  for index, bankInfo in pairs(self.banks) do
    self:printBank(file, index)
  end
end

-- Print assembly for the current code bank.
function Dataspace:bankAssembly(file)
  local bank = self:getCodeBank()
  local bankInfo = self.banks[bank]
  file:write(string.format([[
  .segment "%s"
  ]], bankInfo.segment))

  -- TODO: Maybe assert that the current address is where we think we are and
  -- have the assembler check it?
  local addr = bankInfo.SIZED_START
  while addr < bankInfo.here do
    local v = self[addr]
    local label = self.labels[addr]
    if label then
      file:write(string.format("%s:\n", label))
    end
    file:write(v:asm(self, addr) .. "\n")
    assert(v:size())
    addr = addr + v:size()
  end

  file:write(".segment \"" .. bankInfo.segment .. "_UNSIZED\"\n\n")

  for addr=bankInfo.UNSIZED_START,bankInfo.unsizedHere-1 do
    local v = self[addr]
    local label = self.labels[addr]
    if label then
      file:write(string.format("%s:\n", label))
    end
    file:write(v:asm(self, addr) .. "\n")
  end
end

function Dataspace:assembly(file)
  local originalBank = self:getCodeBank()
  -- Skip the LOWRAM bank since we don't initialize it anyway.
  for bank=0,self.numBanks-1 do
    self:setCodeBank(bank)
    self:bankAssembly(file, bank, bankInfo)
  end
  self:setCodeBank(originalBank)
end

-- Message should include a %s where the addr should be input.
function Dataspace:assertAddr(dumpFile, cond, message, addr)
  if not cond then
    print("Dumping dataspace.")
    self:print(dumpFile)
    assert(nil, string.format(message, Dataspace.formatAddr(addr)))
  end
end

function Dataspace:getCodeBank()
  return self.codeBank
end

function Dataspace:setCodeBank(bank)
  self.codeBank = bank
end

function Dataspace:getDataBank()
  return self.dataBank
end

function Dataspace:setDataBank(bank)
  self.dataBank = bank
end

function Dataspace:getCodeHere()
  return self.banks[self.codeBank].here
end

function Dataspace:getDataHere()
  return self.banks[self.dataBank].here
end

function Dataspace:setCodeHere(val)
  self.banks[self.codeBank].here = val
end

function Dataspace:setDataHere(val)
  self.banks[self.dataBank].here = val
end

-- Set the label for HERE.
-- Because HERE doesn't yet have an entry, we store this label temporarily until
-- something is added at HERE.
-- TODO: Is there a cleaner way of doing this? Maybe keeping a list of labels ->
-- addresses somewhere?
function Dataspace:labelCodeHere(label)
  self.labels[self:getCodeHere()] = label
end

function Dataspace:labelDataHere(label)
  self.labels[self:getDataHere()] = label
end

function Dataspace:setCodeLabel(addr, label)
  self.labels[addr] = label
end

function Dataspace:getLabelAtAddr(addr)
  return self.labels[addr]
end

-- Add at the current data space pointer (HERE).
function Dataspace:add(entry)
  assert(entry:size())
  local addr = self:getDataHere()
  self[self:getDataHere()] = entry
  self:setDataHere(self:getDataHere() + 1)
  return addr
end

-- Add at the current code space pointer.
function Dataspace:compile(entry)
  assert(entry:size())
  local addr = self:getCodeHere()
  self[self:getCodeHere()] = entry
  self:setCodeHere(self:getCodeHere() + 1)
  return addr
end

function Dataspace:compileUnsized(entry)
  local addr = self.banks[self.codeBank].unsizedHere
  self[self.banks[self.codeBank].unsizedHere] = entry
  self.banks[self.codeBank].unsizedHere = self.banks[self.codeBank].unsizedHere + 1
  return addr
end

function Dataspace.defaultLabel(name)
  return "_" .. string.gsub(name, "%W", "_")
end

-- TODO: Now that we're mimicking SNES addressing in Lua these aren't really
-- needed, but maybe handy keep around for error checking.
-- TODO: Add error checking to ensure all intervening cells have a size().
-- Input: lua dataspace addressing
-- Returns: SNES delta
function Dataspace:getRelativeAddr(from, to)
  return to - from
end

-- Input: Lua address and SNES address space delta
-- Returns: Lua address
function Dataspace:fromRelativeAddress(current, delta)
  return current + delta
end

-- Entry types, which make up Dataspace.
Dataspace.Entry = {}

function Dataspace.Entry:new(o)
  cell = o or {}
  setmetatable(cell, self)
  self.__index = self
  return cell
end

-- TODO: Should this be a function? This essentially does nothing (because all
-- undefined entries in a map are nil), but thinking it's useful for documenting
-- that subclasses should override it.
Dataspace.Entry.type = nil

-- TODO: This should be renamed. Each Entry in (sized) Dataspace must be 1 byte
-- wide to make addressing work correctly. size() is used to determine how many
-- bytes to skip after calling asm() or toString(). For example, an entry with
-- size 3 (such as a Call) is stating that it "consumes" the two following bytes
-- in addition to its own cell.
function Dataspace.Entry:size()
  return nil
end

function Dataspace.Entry:toString(dataspace, opAddr)
  return nil
end

function Dataspace.Entry:asm(dataspace)
  return nil
end

Dataspace.Native = Dataspace.Entry:new()

Dataspace.Native.type = "native"

function Dataspace.Native:size()
  return nil
end

function Dataspace.Native:toString(dataspace, opAddr)
  return "Native: " .. self.name
end

-- TODO: Maybe we can also support inlining by specifying an `inline` field
-- that, if specified, overrides the Forth word call and instead causes code to
-- be added directly. e.g. LIT would be
--   lda #LITERAL_NUM
--   PUSH_A
-- instead of the usual
--   JSL LIT
--   .WORD LITERNAL_NUM
-- which is a lot slower.
function Dataspace.Native:asm(dataspace)
  return string.format([[
    jsl not_implemented ; TODO: Not implemented
  ]])
end

Dataspace.Byte = Dataspace.Entry:new()

Dataspace.Byte.type = "byte"

function Dataspace.Byte:size()
  return 1
end

function Dataspace.Byte:toString(dataspace, opAddr)
  return string.format("Byte: 0x%02X", self.byte)
end

function Dataspace.Byte:asm(dataspace)
  return string.format(".byte $%02X", self.byte & 0xFF)
end

local function lowByte(value)
  return value & 0xFF
end

local function highByte(value)
  return (value >> 8) & 0xFF
end

local function bankByte(value)
  return (value >> 16) & 0xFF
end

function Dataspace:getByte(addr)
  self:assertAddr(io.stderr, self[addr].type == "byte", "Expected byte at %s", addr)
  return self[addr].byte
end

function Dataspace:setByte(addr, value)
  self:assertAddr(io.stderr, self[addr].type == "byte" and self[addr]:size() == 1, "Expected byte at %s", addr)
  self[addr].byte = value
end

function Dataspace:getWord(addr)
  return self:getByte(addr) | (self:getByte(addr + 1) << 8)
end

function Dataspace:setWord(addr, value)
  assert(value <= 0xFFFF, "Invalid word " .. value)
  self:setByte(addr, lowByte(value))
  self:setByte(addr + 1, highByte(value))
end

function Dataspace:getAddr(addr)
  return self:getByte(addr) | (self:getByte(addr + 1) << 8) | (self:getByte(addr + 2) << 16)
end

function Dataspace:getLocalByte(localAddr)
  assert(localAddr >= 0 and localAddr <= 0xFFFF, "Invalid local addr " .. localAddr)
  local addr
  if self:getDataBank() == Dataspace.LOWRAM_BANK or localAddr < Dataspace.LOWRAM_SIZE then
    addr = localAddr
  else
    addr = (self:getDataBank() << 16) | localAddr
  end
  self:assertAddr(io.stderr, self[addr] ~= nil and self[addr].type == "byte", "Expected byte at %s", addr)
  return self[addr].byte
end

function Dataspace:setLocalByte(localAddr, value)
  assert(localAddr >= 0 and localAddr <= 0xFFFF, "Invalid local addr " .. localAddr)
  local addr
  if self:getDataBank() == Dataspace.LOWRAM_BANK or localAddr < Dataspace.LOWRAM_SIZE then
    addr = localAddr
  else
    addr = (self:getDataBank() << 16) | localAddr
  end
  self:assertAddr(io.stderr, self[addr] ~= nil and self[addr].type == "byte" and self[addr]:size() == 1, "Expected byte at %s", addr)
  self[addr].byte = value
end

function Dataspace:getLocalWord(localAddr)
  -- TODO: Technically this could wrap to the next bank?
  return self:getLocalByte(localAddr) | (self:getLocalByte(localAddr + 1) << 8)
end

function Dataspace:setLocalWord(localAddr, value)
  assert(value <= 0xFFFF, "Invalid word " .. value)
  self:setLocalByte(localAddr, lowByte(value))
  self:setLocalByte(localAddr + 1, highByte(value))
end

function Dataspace:getLocalAddr(localAddr)
  return self:getLocalByte(localAddr) | (self:getLocalByte(localAddr + 1) << 8) | (self:getLocalByte(localAddr + 2) << 16)
end

-- Convenience methods.
-- TODO: Can maybe add size hints to the first byte of multi-byte data? So we
-- can pretty print it.
function Dataspace:addByte(byte)
  assert(byte >= 0 and byte <= 0xFF)
  self:add(Dataspace.Byte:new{byte=byte})
end

function Dataspace:addWord(number)
  assert(number >= 0 and number <= 0xFFFF)
  self:addByte(lowByte(number))
  self:addByte(highByte(number))
end

function Dataspace:addAddress(addr)
  assert(addr >= 0 and addr <= 0xFFFFFF)
  self:addByte(lowByte(addr))
  self:addByte(highByte(addr))
  self:addByte(bankByte(addr))
end

function Dataspace:allotDataBytes(bytes)
  assert(bytes > 0)
  for i=1,bytes do
    self:addByte(0)
  end
end

function Dataspace:compileByte(byte)
  assert(byte >= 0 and byte <= 0xFF)
  self:compile(Dataspace.Byte:new{byte=byte})
end

function Dataspace:compileWord(number)
  assert(number >= 0 and number <= 0xFFFF)
  self:compileByte(lowByte(number))
  self:compileByte(highByte(number))
end

function Dataspace:compileAddress(addr)
  assert(addr >= 0 and addr <= 0xFFFFFF)
  self:compileByte(lowByte(addr))
  self:compileByte(highByte(addr))
  self:compileByte(bankByte(addr))
end

function Dataspace:allotCodeBytes(bytes)
  assert(bytes > 0)
  for i=1,bytes do
    self:compileByte(0)
  end
end

return Dataspace
