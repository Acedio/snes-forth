REQUIRE std.fth

: SET-PALETTE-ENTRY
  \ 0b0BBBBBGGGGGRRRRR
  \ Set background, low byte first
  DUP 0x2122 C!
  HIBYTE 0x2122 C!
;

: SET-BACKDROP-COLOR
  0 0x2121 C!
  SET-PALETTE-ENTRY
;

( from from-page bytes to-word-index -- )
: COPY-CGRAM-PALETTE-LONG
  \ Which word-indexed entry to transfer to.
  0x2121 C!
  \ Number of copies (bytes)
  0x4305 !
  \ Page
  0x4304 C!
  \ Transfer from
  0x4302 !
  \ Always copy byte-by-byte to the same address.
  0x0 0x4300 C!
  \ Copy to CGRAM reg
  0x22 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

\ Assumes page 0.
( from bytes to-word-index -- )
: COPY-CGRAM-PALETTE
  0 -ROT COPY-CGRAM-PALETTE-LONG
;

( CGRAM organization
  0x0 - 0x0F = 4 4 color palettes for BG3
  0x10 - 0x7F = 7 4 color palettes for BG1 and BG2
  0x80 - 0xFF = 8 16 color palettes for OBJ

  Text is currently using 4 color palette 0 = CGRAM @ 0x0
  Tiles are using 16 color palette 1 = CGRAM @ 0x10
  Cat is using 16 color obj palette 0 = CGRAM @ 0x80
)
