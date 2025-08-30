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
CREATE NMI-READY 1 CELLS ALLOT
CREATE NMI-STATE 1 CELLS ALLOT
CREATE BG1-SHADOW-TILEMAP TILEMAP-TILE-COUNT TILEMAP-ENTRIES ALLOT
CREATE BG3-SHADOW-TILEMAP TILEMAP-TILE-COUNT TILEMAP-ENTRIES ALLOT
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

\ TODO: VRAM organization
\ TODO: Store details about VRAM locations all in the same place.

: COPY-MAPTILES
  \ TODO: What does maptile data look like?
  MAPTILES-TILES
  MAPTILES-TILES-BYTES
  0x4000
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

( CGRAM organization
  0x0 - 0x0F = 4 4 color palettes for BG3
  0x10 - 0x7F = 7 4 color palettes for BG1 and BG2
  0x80 - 0xFF = 8 16 color palettes for OBJ

  Text is currently using 4 color palette 0 = CGRAM @ 0x0
  Tiles are using 16 color palette 1 = CGRAM @ 0x10
  Cat is using 16 color obj palette 0 = CGRAM @ 0x80
)

: COPY-CAT-PALETTE
  CAT-PAL
  CAT-PAL-BYTES
  0x80
  COPY-CGRAM-PALETTE
;

: COPY-MAPTILES-PALETTE
  MAPTILES-PAL
  MAPTILES-PAL-BYTES
  0x10
  COPY-CGRAM-PALETTE
;

: COPY-BG1
  BG1-SHADOW-TILEMAP
  TILEMAP-TILE-COUNT TILEMAP-ENTRIES
  \ Start at the tilemap data area (1kth word).
  0x0400 \ word-indexed
  DMA0-VRAM-TRANSFER
;

: COPY-BG3
  BG3-SHADOW-TILEMAP
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

BANK@
LOWRAM BANK!
CREATE PLAYER-X 1 CELLS ALLOT
CREATE PLAYER-Y 1 CELLS ALLOT
BANK!

: SNES-NMI
  NMI-READY @ 0= IF
    \ TODO: We missed a frame. Find a way to track/signal this.
    EXIT
  THEN

  FALSE NMI-READY !

  \ layer 3 and sprites
  0x15 0x212C C!
  \ Set Mode 1 BG3 high priority (0x.9), BG1 tile size 16x16 (0x1.), other BGs 8x8
  0x19 0x2105 C!
  \ Set BG1 base (VRAM @ 0x800)
  4 0x2107 C!
  \ Set BG3 base (VRAM @ 0)
  0 0x2109 C!
  \ Character data area (BG1 4*4K words = 16K words start, BG3 1*4K words = 4K words start)
  0x0104 0x210B !

  \ Small sprites, tile base at VRAM 0x2000 (8Kth word)
  1 0x2101 C!

  NMI-STATE @ CASE
    0 OF
      COPY-FONT

      COPY-CAT
      COPY-CAT-PALETTE

      TEXT-PALETTE

      1 NMI-STATE !
    ENDOF
    1 OF
      COPY-MAPTILES
      COPY-MAPTILES-PALETTE

      2 NMI-STATE !
    ENDOF
    2 OF
      \ Zero shift for BG1
      0x00 0x210D C!
      0x00 0x210D C!
      \ Shift BG3 right by 4 pixels to center text.
      0xFC 0x2111 C!
      0xFF 0x2111 C!

      COPY-BG3

      3 NMI-STATE !
    ENDOF
    3 OF
      COPY-BG1

      4 NMI-STATE !
    ENDOF
    4 OF
      COPY-OAM

      \ PULSE-BG
    ENDOF
  ENDCASE

  \ Maximum screen brightness
  0x0F 0x2100 C!
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
  1 CELLS +LOOP DROP ;
;

: INIT-LEVEL-TILEMAP
  S"                                 
      #####                     
      #Rr #                     
      ## @#                     
       ####                     
       R                        
       R                        
       R                        
       R                        
 # # ### # #                    
 # #  #  # #                    
 ###  #  # #                    
 # #  #                         
 # # ### # #                    
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                "
  ( addr u )
  DROP BG1-SHADOW-TILEMAP TILEMAP-TILE-COUNT CELLS EACH DO
    BEGIN
      DUP 1+ SWAP
      C@
      DUP 0x0A =
    WHILE
      DROP
    REPEAT
    \ Convert to text tile offset (missing the first 0x20 control characters).
    CASE
      [CHAR] # OF 0x0400 ENDOF
      [CHAR] R OF 0x0402 ENDOF
      [CHAR] r OF 0x0402 ENDOF
      [CHAR] @ OF 0x0402 ENDOF
      [CHAR]   OF 0x0404 ENDOF
      >R 0x0404 R>
    ENDCASE
    I !
  1 CELLS +LOOP
  \ Drop the string indexing address.
  DROP ;

: TILEMAP-XY
  32 PPU-MULT DROP + ;

: SNES-MAIN
  FALSE NMI-READY !
  0 NMI-STATE !
  0x0044 BG-COLOR !

  0 JOY1-HELD !
  0 JOY1-PRESSED !

  0 PLAYER-X !
  0 PLAYER-Y !

  BG1-SHADOW-TILEMAP ZERO-TILEMAP
  BG3-SHADOW-TILEMAP ZERO-TILEMAP

  ZERO-OAM

  S"   Testing out this fanciness!   
                                
We're not interpreting Forth    
here, but we are indeed running 
compiled Forth code! Pretty     
cool, if a bit slow...          
                                
        :D :D :D :D             "
  DROP [ 32 2* 2* 2* COMPILE-LIT ] BG3-SHADOW-TILEMAP 0 10 TILEMAP-XY CELLS + COPY-STRING-TO-TILES

  INIT-LEVEL-TILEMAP

  0x7000 SHADOW-OAM-LOWER 2 + !
  0x56   SHADOW-OAM-UPPER     C!

  0
  BEGIN
    1+

    DUP 0xFF AND 0x2000 OR SHADOW-OAM-LOWER !
    DUP HIBYTE 0x02 OR 0x03 SHADOW-OAM-UPPER MASK!

    DUP 2*
    DUP 0xFF AND 0x3000 OR SHADOW-OAM-LOWER 4 + !
    HIBYTE 0x02 OR 2* 2* 0x0C SHADOW-OAM-UPPER MASK!

    DUP LSR
    DUP 0xFF AND 0x4000 OR SHADOW-OAM-LOWER 8 + !
    HIBYTE 0x02 OR 2* 2* 2* 2* 0x30 SHADOW-OAM-UPPER MASK!

    TRUE NMI-READY !
    BEGIN
      NMI-WAIT
    NMI-READY @ 0= UNTIL

    READ-JOY1

    JOY1-HELD @ BUTTON-UP AND 0<> IF
      PLAYER-Y @ 1 - PLAYER-Y !
    THEN
    JOY1-HELD @ BUTTON-DOWN AND 0<> IF
      PLAYER-Y @ 1 + PLAYER-Y !
    THEN
    JOY1-HELD @ BUTTON-LEFT AND 0<> IF
      PLAYER-X @ 1 - PLAYER-X !
    THEN
    JOY1-HELD @ BUTTON-RIGHT AND 0<> IF
      PLAYER-X @ 1 + PLAYER-X !
    THEN

    PLAYER-X @ 0xFF AND
    PLAYER-Y @ 0xFF AND SWAPBYTES OR
    SHADOW-OAM-LOWER 12 + !

    PLAYER-X @ 0x100 AND LSR LSR 0x80 OR 0xC0 SHADOW-OAM-UPPER MASK!
  FALSE UNTIL
;
