0 BANK!

BANK@
LOWRAM BANK!
CREATE MISSED-FRAMES 1 CELLS ALLOT
BANK!

BANK@
LOWRAM BANK!
CREATE NMI-READY 1 CELLS ALLOT
CREATE NMI-STATE 1 CELLS ALLOT
BANK!

: COPY-FONT
  FONT
  FONT-CHARS 2BIT-8X8-TILES
  \ Start at the character data area (4Kth word).
  0x1000
  DMA0-VRAM-TRANSFER
;

: TEXT-PALETTE
  0 0x2121 C!
  0 SET-PALETTE-ENTRY
  0x7FFF SET-PALETTE-ENTRY
;

: COPY-BG3
  BG3-SHADOW-TILEMAP
  \ Start at the tilemap data area (0th word).
  0x0000
  COPY-BG-TO-VRAM
;

: SNES-NMI
  NMI-READY @ 0= IF
    \ We missed a frame.
    1 MISSED-FRAMES +!
    EXIT
  THEN

  FALSE NMI-READY !

  \ TODO: Shadow this so we can modify it per BG easily.
  \ Character data area (BG1 4*4K words = 16K words start, BG3 1*4K words = 4K words start)
  0x0104 0x210B !

  NMI-STATE @ CASE
    0 OF
      \ Disable all layers initially.
      0x00 0x212C C!
      \ Set Mode 1 BG3 high priority (0x.9), BG1 tile size 16x16 (0x1.), other BGs 8x8
      0x19 0x2105 C!

      COPY-FONT
      TEXT-PALETTE

      \ Maximum screen brightness
      0x0F 0x2100 C!

      1 NMI-STATE +!
    ENDOF
    1 OF
      \ Set BG3 base (VRAM @ 0)
      0 0x2109 C!

      \ Zero shift for BG1
      0x00 0x210D C!
      0x00 0x210D C!
      \ Shift BG3 right by 4 pixels to center text.
      0xFC 0x2111 C!
      0xFF 0x2111 C!

      COPY-BG3

      1 NMI-STATE +!
    ENDOF
    2 OF
      LEVEL-NMI
    ENDOF
  ENDCASE
;

\ Converts ASCII string (bytes) to tile references (words where 0 = space, 1 =
\ !, etc). Ignores 0x0A (line feed?) characters.
( addr u tilemap-addr -- )
: COPY-STRING-TO-TILES
  SWAP CELLS OVER + SWAP DO
    BEGIN
      DUP 1+ SWAP
      C@
      DUP 0x0A =
    WHILE
      DROP
    REPEAT
    \ Convert to text tile offset (missing the first 0x20 control characters).
    0x20 -
    \ Give text tiles priority over others. (bit 5 of $2105 ensures they show
    \ over other backgrounds).
    0x2000 OR I !
  1 CELLS +LOOP DROP
;

: SNES-MAIN
  FALSE NMI-READY !
  0 NMI-STATE !
  0 MISSED-FRAMES !

  0 JOY1-HELD !
  0 JOY1-PRESSED !

  BG1-SHADOW-TILEMAP ZERO-BGTILEMAP
  BG3-SHADOW-TILEMAP ZERO-BGTILEMAP

  AUDIO-INIT
  NMI-ENABLE

  ZERO-OAM

(
  S"   Testing out this fanciness!   
                                
We're not interpreting Forth    
here, but we are indeed running 
compiled Forth code! Pretty     
cool, if a bit slow...          
                                
        :D :D :D :D             "
  DROP [ 32 2* 2* 2* COMPILE-LIT ] BG3-SHADOW-TILEMAP 0 10 TILEMAP-XY CELLS + COPY-STRING-TO-TILES
  )

  LEVEL-INIT

  AUDIO-PLAY-SONG

  0x7000 SHADOW-OAM-LOWER 0 OAM-LOWER-OBJECTS OAM-COORDINATES + !
  0x02   SHADOW-OAM-UPPER 0 OAM-UPPER-OBJECTS MASK!

  0x02   SHADOW-OAM-LOWER 2 OAM-LOWER-OBJECTS OAM-TILE-NUMBER + C!
  0x30   SHADOW-OAM-LOWER 2 OAM-LOWER-OBJECTS OAM-ATTRIBUTES + C!

  0
  BEGIN
    1+

    READ-JOY1

    DUP 0xFF AND 0x2000 OR SHADOW-OAM-LOWER !
    DUP HIBYTE 0x02 OR 0x03 SHADOW-OAM-UPPER MASK!

    DUP 2*
    DUP 0xFF AND 0x3000 OR
      SHADOW-OAM-LOWER 1 OAM-LOWER-OBJECTS + !
    HIBYTE 0x02 OR 2* 2*
      0x0C SHADOW-OAM-UPPER MASK!

    \ Ticks
    DUP LSR
    \ X
    DUP 0xFF AND
    \ Y
    DUP 2* 2* 2* 0xFF AND SIN-LUT
      0x7FFF + LSR LSR LSR 0xFF00 AND 0x4000 +
    \ Combine
    OR SHADOW-OAM-LOWER 2 OAM-LOWER-OBJECTS OAM-COORDINATES + !
    HIBYTE 0x02 OR 2* 2* 2* 2* 0x30 SHADOW-OAM-UPPER MASK!

    LEVEL-MAIN

    AUDIO-UPDATE

    TRUE NMI-READY !
    BEGIN
      NMI-WAIT
    NMI-READY @ 0= UNTIL
  FALSE UNTIL
;
