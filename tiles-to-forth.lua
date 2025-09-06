#!/usr/bin/lua

local name = arg[1]
local palFile = assert(io.open(arg[2], "rb"))
local tileFile = assert(io.open(arg[3], "rb"))
local segment = arg[4] or "UNSIZED"

function toWords(str)
  local wordStrings = {}
  for i = 1, #str, 2 do
    table.insert(wordStrings, string.format("$%04X", (string.byte(str, i + 1) << 8) | string.byte(str, i)))
  end
  return wordStrings
end

function toWordRows(str)
  local wordStrings = toWords(str)
  local rowWords = {}
  local rows = {}
  for k, v in ipairs(wordStrings) do
    if #rowWords >= 8 then
      table.insert(rows, "  .WORD " .. table.concat(rowWords, ", "))
      rowWords = {}
    end
    table.insert(rowWords, v)
  end
  table.insert(rows, "  .WORD " .. table.concat(rowWords, ", "))
  return table.concat(rows, "\n")
end

function makeDataWords(name, label, data)
  return string.format([[
CODE %s
  dex
  dex
  lda #.LOWORD(%s_DATA)
  sta z:1, X
  rts

.pushseg
.segment "%s"

%s_DATA:
%s

.popseg
END-CODE

0x%04X CONSTANT %s-BYTES

CODE %s-BANK
  dex
  dex
  lda #.BANKBYTE(%s_DATA)
  sta z:1, X
  rts
END-CODE
  ]], name, label, segment, label, toWordRows(data), #data, name, name, label)
end

print(makeDataWords(name .. "-PAL", name .. "_PAL", palFile:read("*all")))
print(makeDataWords(name .. "-TILES", name .. "_TILES", tileFile:read("*all")))
