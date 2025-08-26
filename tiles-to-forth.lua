#!/usr/bin/lua

local name = arg[1]
local palFile = assert(io.open(arg[2], "rb"))
local tileFile = assert(io.open(arg[3], "rb"))
local mapFile = assert(io.open(arg[4], "rb"))

function toWords(str)
  wordStrings = {}
  for i = 1, #str, 2 do
    table.insert(wordStrings, string.format("$%04X", (string.byte(str, i + 1) << 8) | string.byte(str, i)))
  end
  return ".WORD " .. table.concat(wordStrings, ", ")
end

function makeDataWords(name, data)
  return string.format([[
CODE %s
  dex
  dex
  lda #%s_DATA
  sta z:1, X
  rts

%s_DATA:
  %s
END-CODE

: %s_BYTES 0x%04X ;
  ]], name, name, name, toWords(data), name, #data)
end

print(makeDataWords(name .. "_PAL", palFile:read("*all")))
print(makeDataWords(name .. "_TILES", tileFile:read("*all")))
print(makeDataWords(name .. "_MAP", mapFile:read("*all")))
