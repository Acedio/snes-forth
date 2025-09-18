BANK@
LOWRAM BANK!
CREATE END-TICKS 1 CELLS ALLOT
CREATE END-NMI-STATE 1 CELLS ALLOT
BANK!
 
: COPY-FONT
  FONT
  FONT-BANK
  FONT-CHARS 16* 2*
  END-BG-TILE-BASE TILE-BASE-TO-VRAM-WORD
  DMA0-VRAM-LONG-TRANSFER
;

: TEXT-PALETTE
  0 0x2121 C!
  0 SET-PALETTE-ENTRY
  0x7FFF SET-PALETTE-ENTRY
;

: END-COPY-BG1
  BG1-SHADOW-TILEMAP
  END-BG-MAP-BASE MAP-BASE-TO-VRAM-WORD
  COPY-BG-TO-VRAM
;

\ Converts ASCII string (bytes) to tile references (words where 0 = space, 1 =
\ !, etc). Ignores 0x0A (line feed) characters.
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

: END-NMI
  END-NMI-STATE @ CASE
    0 OF
      COPY-FONT
      TEXT-PALETTE

      1 END-NMI-STATE +!
    ENDOF
    1 OF
      END-COPY-BG1

      1 END-NMI-STATE +!
    ENDOF
    2 OF
      END-BG-TILE-BASE BG1-TILE-BASE!
      0x08   0x18   BG-MODE           MASK!
      \ Leave on our cat hero.
      0x11   0x11   BG-LAYER-ENABLE   MASK!

      END-BG-MAP-BASE 0x2107 C!

      \ Shift BG1 right by 4 pixels to center text.
      0xFC 0x210D C!
      0xFF 0x210D C!
      \ But no Y shift.
      0x00 0x210E C!
      0x00 0x210E C!

      1 END-NMI-STATE +!
    ENDOF
    3 OF
      STARS-NMI DROP
    ENDOF
  ENDCASE

  \ Maximum screen brightness
  0x0F 0x2100 C!
;

: END-INIT
  0 END-NMI-STATE !
  0 END-TICKS !

  BG1-SHADOW-TILEMAP ZERO-BGTILEMAP

  S" : THE-END .(                   
                                
 You did it! It looks like you  
 arrived here after taking 0    
 steps. Nice! I hope the puzzles
 were interesting and not too   
 difficult. Either way...       
                                
     Thank you for playing!     
                                
 This was largely a yak-shaving 
 project to create a Forth      
 compiler for the SNES! Check   
 out the code at:               
  github.com/acedio/snes-forth  
                                
 ) ; \ See you next time! :D    "
  DROP [ 32 17 * COMPILE-LIT ] BG1-SHADOW-TILEMAP 0 8 TILEMAP-XY CELLS + COPY-STRING-TO-TILES

  STEPS-STRING BG1-SHADOW-TILEMAP 26 11 TILEMAP-XY CELLS + COPY-STRING-TO-TILES

  STARS-INIT
;

\ Returns TRUE when done with title.
: END-MAIN
  1 END-TICKS +!

  STARS-MAIN

  JOY1-PRESSED @ BUTTON-START AND 0<> IF
    AUDIO-PLAY-CHIME
    TRUE
    EXIT
  THEN

  FALSE
;
