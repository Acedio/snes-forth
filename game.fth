0 BANK!

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

: TEXT-PALETTE
  0 0x2121 C!
  0 SET-PALETTE-ENTRY
  0x7FFF SET-PALETTE-ENTRY
;

BANK@
LOWRAM BANK!
CREATE BG-COLOR 1 CELLS ALLOT
BANK!

: 2BIT-TILES
  2* 2* 2* 2*
;

32 2* 2* 2* 2* 2* CONSTANT TILEMAP-TILE-COUNT

: TILEMAP-ENTRIES
  CELLS
;

( tilemap-addr -- )
: ZERO-TILEMAP
  DUP TILEMAP-TILE-COUNT TILEMAP-ENTRIES + SWAP DO
    0 I !
  1 CELLS +LOOP
;

128 CONSTANT OAM-OBJECT-COUNT

\ 4 bytes per object
: OAM-OBJECT-LOWER-BYTES
  2* 2*
;

\ 2 bits per object
: OAM-OBJECT-UPPER-BYTES
  LSR LSR
;

BANK@
LOWRAM BANK!
CREATE VRAM-COPIED 1 CELLS ALLOT
CREATE SHADOW-TILEMAP TILEMAP-TILE-COUNT TILEMAP-ENTRIES ALLOT
CREATE SHADOW-OAM-LOWER OAM-OBJECT-COUNT OAM-OBJECT-LOWER-BYTES ALLOT
CREATE SHADOW-OAM-UPPER OAM-OBJECT-COUNT OAM-OBJECT-UPPER-BYTES ALLOT
BANK!

: ZERO-OAM
  SHADOW-OAM-LOWER OAM-OBJECT-COUNT OAM-OBJECT-LOWER-BYTES +
  SHADOW-OAM-LOWER DO
    -32 I     C! \ X (lower 8 bits)
    -32 I 1 + C! \ Y
      0 I 2 + C! \ Tile no (lower 8 bits)
      0 I 3 + C! \ Attributes
  1 OAM-OBJECT-LOWER-BYTES +LOOP

  SHADOW-OAM-UPPER OAM-OBJECT-COUNT OAM-OBJECT-UPPER-BYTES +
  SHADOW-OAM-UPPER DO
    0x55 I C!
  LOOP
;

( from bytes to -- )
: DMA0-VRAM-TRANSFER
  \ Set up VRAM reg.
  \ Increment after writing high byte
  0x80 0x2115 C!
  \ Which word-indexed entry to transfer to.
  0x2116 !

  \ Number of copies (bytes)
  0x4305 !
  \ Transfer from
  0x4302 !
  \ Page (TODO: This shouldn't always be 0)
  0 0x4304 C!
  \ Copy to addr (2118), then addr+1 (2119).
  0x1 0x4300 C!
  \ Copy to VRAM reg
  0x18 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

: COPY-FONT
  FONT
  FONT-CHARS 2BIT-TILES
  \ Start at the character data area (4Kth word).
  0x1000
  DMA0-VRAM-TRANSFER
;

: COPY-CAT
  \ The bottom two tiles are 16 tiles ahead (1 row below) the first tile.
  CAT-TILES
  CAT-TILES-BYTES
  0x2000
  DMA0-VRAM-TRANSFER
;

( from bytes to-word-index -- )
: COPY-CGRAM-PALETTE
  \ Which word-indexed entry to transfer to.
  0x2121 C!
  \ Number of copies (bytes)
  0x4305 !
  \ Transfer from
  0x4302 !
  \ Page (TODO: This shouldn't always be 0)
  0 0x4304 C!
  \ Always copy byte-by-byte to the same address.
  0x0 0x4300 C!
  \ Copy to CGRAM reg
  0x22 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

: COPY-CAT-PALETTE
  CAT-PAL
  CAT-PAL-BYTES
  0x80
  COPY-CGRAM-PALETTE
;

: COPY-TILEMAP
  SHADOW-TILEMAP
  TILEMAP-TILE-COUNT TILEMAP-ENTRIES
  \ Start at the tilemap data area (0th word).
  0x0000
  DMA0-VRAM-TRANSFER
;

: COPY-OAM
  \ Set OAM address to 0.
  0 0x2102 C!
  0 0x2103 C!

  \ Number of copies (bytes)
  [ OAM-OBJECT-COUNT OAM-OBJECT-LOWER-BYTES
    OAM-OBJECT-COUNT OAM-OBJECT-UPPER-BYTES +
    COMPILE-LIT ] 0x4305 !
  \ Transfer from shadow OAM
  SHADOW-OAM-LOWER 0x4302 !
  \ Page (TODO: This shouldn't always be 0)
  0 0x4304 C!
  \ Always copy byte-by-byte to the same address.
  0x0 0x4300 C!
  \ Copy to OAM write reg
  0x04 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

: PULSE-BG
  BG-COLOR @
  0x0421 +
  DUP 0x1F AND 0= IF
    DROP 0x0044
  THEN
  DUP BG-COLOR !
  SET-BACKDROP-COLOR
  ;

: SNES-NMI
  \ layer 3 and sprites
  0x14 0x212C C!
  \ Set Mode 1
  1 0x2105 C!
  \ Set BG base (0)
  0 0x2109 C!
  \ Character data area (BG3 1*4K words = 4K words start)
  0x0100 0x210B !

  \ Small sprites, tile base at VRAM 0x2000 (8Kth word)
  1 0x2101 C!

  VRAM-COPIED @ 0= IF
    COPY-FONT

    COPY-CAT
    COPY-CAT-PALETTE

    TEXT-PALETTE

    TRUE VRAM-COPIED !
  THEN

  COPY-TILEMAP
  COPY-OAM

  \ PULSE-BG

  \ Maximum screen brightness
  0x0F 0x2100 C!
;

\ Converts ASCII string (bytes) to tile references (words where 0 = space, 1 =
\ !, etc)
( addr u tilemap-addr -- )
: COPY-STRING-TO-TILES
  SWAP CELLS OVER + SWAP DO
    DUP C@ 0x20 - I !
    1+
  1 CELLS +LOOP DROP ;
;

: TILEMAP-XY
  32 PPU-MULT DROP + ;

: SNES-MAIN
  FALSE VRAM-COPIED !
  0x0044 BG-COLOR !

  SHADOW-TILEMAP ZERO-TILEMAP

  ZERO-OAM

  S"   Testing out this fanciness!  
                               
We're not interpreting Forth   
here, but we are indeed running
compiled Forth code! Pretty    
cool, if a bit slow...         
                               
        :D :D :D :D            "
  SHADOW-TILEMAP 0 10 TILEMAP-XY CELLS + COPY-STRING-TO-TILES

  0x7000 SHADOW-OAM-LOWER 2 + !
  0x56   SHADOW-OAM-UPPER     C!

  0
  BEGIN
    1+ DUP LSR LSR LSR LSR LSR LSR LSR LSR 0x2000 OR SHADOW-OAM-LOWER !
  FALSE UNTIL
;
