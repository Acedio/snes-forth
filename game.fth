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

: FONT-COPY-BG3
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
      \ Set Mode 1 BG3 high priority (0x.9), BG1 and BG2 tile size 16x16 (0x3.), other BGs 8x8
      0x39 0x2105 C!

      COPY-FONT
      TEXT-PALETTE

      \ Maximum screen brightness
      0x0F 0x2100 C!

      1 NMI-STATE +!
    ENDOF
    1 OF
      \ Set BG3 base (VRAM @ 0)
      0 0x2109 C!

      \ Shift BG3 right by 4 pixels to center text.
      0xFC 0x2111 C!
      0xFF 0x2111 C!

      FONT-COPY-BG3

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

  0
  BEGIN
    1+

    READ-JOY1

    LEVEL-MAIN

    AUDIO-UPDATE

    TRUE NMI-READY !
    BEGIN
      NMI-WAIT
    NMI-READY @ 0= UNTIL
  FALSE UNTIL
;
