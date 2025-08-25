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

: TILEMAP-TILE-COUNT
  32 2* 2* 2* 2* 2*
;

: TILEMAP-ENTRIES
  \ 1 word each
;

( tilemap-addr -- )
: ZERO-TILEMAP
  DUP TILEMAP-TILE-COUNT TILEMAP-ENTRIES CELLS + >R
  BEGIN
    0 OVER !
    CELL+ DUP R@ =
  UNTIL
  R> DROP
;

BANK@
LOWRAM BANK!
CREATE TILEMAP TILEMAP-TILE-COUNT TILEMAP-ENTRIES ALLOT
BANK!

( from bytes to -- )
: DMA1-VRAM-TRANSFER
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
  \ Copy low byte, then high byte.
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
  DMA1-VRAM-TRANSFER
;

: COPY-TILEMAP
  TILEMAP
  TILEMAP-TILE-COUNT TILEMAP-ENTRIES CELLS
  \ Start at the tilemap data area (0th word).
  0x0000
  DMA1-VRAM-TRANSFER
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
  \ Only layer 3
  0x04 0x212C C!
  \ Set Mode 1
  1 0x2105 C!
  \ Set BG base (0)
  0 0x2109 C!
  \ Character data area (BG3 1*4K words = 4K words start)
  0x0100 0x210B !

  COPY-TILEMAP

  COPY-FONT

  TEXT-PALETTE

  PULSE-BG

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
  0x0044 BG-COLOR !

  TILEMAP ZERO-TILEMAP

  S"   Testing out this fanciness!  
                               
We're not interpreting Forth   
here, but we are indeed running
compiled Forth code! Pretty    
cool, if a bit slow...         
                               
        :D :D :D :D            "
  TILEMAP 0 10 TILEMAP-XY CELLS + COPY-STRING-TO-TILES

  BEGIN FALSE UNTIL
;
