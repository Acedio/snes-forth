#!/usr/bin/lua

local name = arg[1]
local palFile = assert(io.open(arg[2], "rb"))
local tileFile = assert(io.open(arg[3], "rb"))
local mapFile = assert(io.open(arg[4], "rb"))

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

%s_DATA:
%s
END-CODE

: %s-BYTES 0x%04X ;
  ]], name, label, label, toWordRows(data), name, #data)
end

print(makeDataWords(name .. "-PAL", name .. "_PAL", palFile:read("*all")))
print(makeDataWords(name .. "-TILES", name .. "_TILES", tileFile:read("*all")))
print(makeDataWords(name .. "-MAP", name .. "_MAP", mapFile:read("*all")))
