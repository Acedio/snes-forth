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
CREATE BG-TICKS 1 CELLS ALLOT
BANK!

: 2BIT-TILES
  16*
;

32 2* 2* 2* 2* 2* CONSTANT TILEMAP-TILE-COUNT

: TILEMAP-ENTRIES
  CELLS
;

( tilemap-addr -- )
: ZERO-TILEMAP
  \ TODO: Use DMA for this.
  TILEMAP-TILE-COUNT TILEMAP-ENTRIES EACH DO
    0 I !
  1 CELLS +LOOP
;

BANK@
LOWRAM BANK!
CREATE NMI-READY 1 CELLS ALLOT
CREATE NMI-STATE 1 CELLS ALLOT
CREATE BG1-SHADOW-TILEMAP TILEMAP-TILE-COUNT TILEMAP-ENTRIES ALLOT
CREATE BG3-SHADOW-TILEMAP TILEMAP-TILE-COUNT TILEMAP-ENTRIES ALLOT
BANK!

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

: COPY-SPRITES
  \ The bottom two tiles are 16 tiles ahead (1 row below) the first tile.
  SPRITES-TILES
  SPRITES-TILES-BYTES
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

: COPY-SPRITES-PALETTE
  SPRITES-PAL
  SPRITES-PAL-BYTES
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

: PULSE-BG
  BG-TICKS @
  DUP 1+ BG-TICKS !
  0xFF AND SIN-LUT 0x7FFF + \ Sine between 0x0000 and 0xFFFF
  \ Blue component
  DUP LSR LSR LSR 0x7C00 AND SWAP
  \ Green component
  HIBYTE 2* 0x03E0 AND
  \ Combine
  OR
  SET-BACKDROP-COLOR
  ;

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

      COPY-SPRITES
      COPY-SPRITES-PALETTE

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
      COPY-OAM

      PULSE-BG
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
  1 CELLS +LOOP DROP
;

: GOAL-ENABLED ; \ First cell.
: GOAL-Y 1 CELLS + ;
: GOAL-X 2 CELLS + ;
: GOALS DUP 2* + CELLS ;

8 CONSTANT MAX-GOALS

BANK@
LOWRAM BANK!
CREATE LEVEL 1 CELLS ALLOT
CREATE PLAYER-X 1 CELLS ALLOT
CREATE PLAYER-Y 1 CELLS ALLOT
CREATE GOAL-ARRAY MAX-GOALS GOALS ALLOT
BANK!

: CLEAR-GOALS
  GOAL-ARRAY MAX-GOALS GOALS EACH DO
    FALSE I GOAL-ENABLED !
  1 GOALS +LOOP
;

( y x -- )
: ADD-GOAL
  GOAL-ARRAY MAX-GOALS GOALS EACH DO
    I GOAL-ENABLED @ 0= IF
      TRUE I GOAL-ENABLED !
      I GOAL-X !
      I GOAL-Y !
      UNLOOP EXIT
    THEN
  1 GOALS +LOOP
  BREAKPOINT
;

4 CONSTANT FIRST-GOAL-OAM-OBJECT

: DRAW-GOAL
  >R
  SHADOW-OAM-LOWER FIRST-GOAL-OAM-OBJECT R@ + OAM-LOWER-OBJECTS +
  \ 0x04 = goal sprite
  0x04 OVER OAM-TILE-NUMBER C!
  0x00 SWAP OAM-ATTRIBUTES C!

  GOAL-ARRAY R@ GOALS +

  DUP GOAL-ENABLED @ IF
    DUP GOAL-Y @ 16*
    SWAP GOAL-X @ 16*
  ELSE
    DROP
    \ Hide the ball.
    -32 -32
  THEN
  FIRST-GOAL-OAM-OBJECT R@ + OAM-OBJECT-COORDS!
  TRUE FIRST-GOAL-OAM-OBJECT R> + OAM-OBJECT-LARGE!
;

: DRAW-GOALS
  MAX-GOALS 0 DO
    I DRAW-GOAL
  LOOP
;

0x0400 CONSTANT WALL-TILE
0x0402 CONSTANT BALL-TILE
0x0404 CONSTANT EMPTY-TILE

( y x -- )
: SET-PLAYER-COORDS
  PLAYER-X !
  PLAYER-Y !
;

( y x -- &tile )
: TILE-ADDR
  SWAP 32 PPU-MULT DROP + CELLS
  BG1-SHADOW-TILEMAP +
;

( y x -- tile )
: TILE-AT
  TILE-ADDR @
;

( addr -- )
: LOAD-LEVEL-FROM-STRING
  CLEAR-GOALS

  0 0 ROT BG1-SHADOW-TILEMAP TILEMAP-TILE-COUNT CELLS EACH DO
    BEGIN
      DUP 1+ SWAP
      C@
      DUP 0x0A =
    WHILE
      DROP
    REPEAT
    \ Convert to text tile offset (missing the first 0x20 control characters).
    CASE
      [CHAR]   OF                              EMPTY-TILE I ! ENDOF
      [CHAR] # OF                              WALL-TILE  I ! ENDOF
      [CHAR] R OF                              BALL-TILE  I ! ENDOF
      [CHAR] r OF >R 2DUP ADD-GOAL          R> EMPTY-TILE I ! ENDOF
      [CHAR] @ OF >R 2DUP SET-PLAYER-COORDS R> EMPTY-TILE I ! ENDOF
      \ Don't need to use >R for the default case here because we don't care
      \ about what is on the stack (and we need to access I).
      EMPTY-TILE I !
    ENDCASE
    \ Increment X, then overflow to Y and reset if necessary.
    >R 1+ DUP 32 >= IF
      DROP 1+ 0
    THEN R>
  1 CELLS +LOOP
  \ Drop the string indexing address, X, and Y
  DROP DROP DROP
;

( level-id -- )
: LOAD-LEVEL
  LEVEL-STRING LOAD-LEVEL-FROM-STRING
  DRAW-GOALS
;

: CHECK-WIN
  GOAL-ARRAY MAX-GOALS GOALS EACH DO
    I GOAL-ENABLED @ IF
      I GOAL-Y @ I GOAL-X @ TILE-AT BALL-TILE <> IF
        FALSE UNLOOP EXIT
      THEN
    THEN
  1 GOALS +LOOP
  TRUE
;

: TILEMAP-XY
  32 PPU-MULT DROP + ;

3 CONSTANT PLAYER-OAM-OBJECT

: DRAW-PLAYER
  PLAYER-Y @ 16* PLAYER-X @ 16* PLAYER-OAM-OBJECT OAM-OBJECT-COORDS!
  TRUE PLAYER-OAM-OBJECT OAM-OBJECT-LARGE!
;

\ Move ball at (x, y) to (nx, ny)
( y x ny nx -- moved )
: MOVE-BALL
  2DUP TILE-AT EMPTY-TILE = IF
    TILE-ADDR BALL-TILE SWAP !
    TILE-ADDR EMPTY-TILE SWAP !
    TRUE EXIT
  THEN
  2DROP 2DROP
  FALSE
;

: PLAYER-MOVEMENT
  TRUE CASE
    JOY1-PRESSED @ BUTTON-UP AND 0<> OF
      \ TODO: Pull out all this common logic.
      PLAYER-Y @ 1- PLAYER-X @
      2DUP TILE-AT CASE
        EMPTY-TILE OF PLAYER-X ! PLAYER-Y ! ENDOF
        BALL-TILE OF
          2DUP OVER 1- OVER MOVE-BALL IF
            PLAYER-X ! PLAYER-Y !
          ELSE
            2DROP
          THEN
        ENDOF
        >R 2DROP R>
      ENDCASE
    ENDOF
    JOY1-PRESSED @ BUTTON-DOWN AND 0<> OF
      PLAYER-Y @ 1+ PLAYER-X @
      2DUP TILE-AT CASE
        EMPTY-TILE OF PLAYER-X ! PLAYER-Y ! ENDOF
        BALL-TILE OF
          2DUP OVER 1+ OVER MOVE-BALL IF
            PLAYER-X ! PLAYER-Y !
          ELSE
            2DROP
          THEN
        ENDOF
        >R 2DROP R>
      ENDCASE
    ENDOF
    JOY1-PRESSED @ BUTTON-LEFT AND 0<> OF
      PLAYER-Y @ PLAYER-X @ 1-
      2DUP TILE-AT CASE
        EMPTY-TILE OF PLAYER-X ! PLAYER-Y ! ENDOF
        BALL-TILE OF
          2DUP 2DUP 1- MOVE-BALL IF
            PLAYER-X ! PLAYER-Y !
          ELSE
            2DROP
          THEN
        ENDOF
        >R 2DROP R>
      ENDCASE
    ENDOF
    JOY1-PRESSED @ BUTTON-RIGHT AND 0<> OF
      PLAYER-Y @ PLAYER-X @ 1+
      2DUP TILE-AT CASE
        EMPTY-TILE OF PLAYER-X ! PLAYER-Y ! ENDOF
        BALL-TILE OF
          2DUP 2DUP 1+ MOVE-BALL IF
            PLAYER-X ! PLAYER-Y !
          ELSE
            2DROP
          THEN
        ENDOF
        >R 2DROP R>
      ENDCASE
    ENDOF
  ENDCASE
;

: SNES-MAIN
  FALSE NMI-READY !
  0 NMI-STATE !
  0 BG-TICKS !

  0 JOY1-HELD !
  0 JOY1-PRESSED !

  0 LEVEL !

  0 PLAYER-X !
  0 PLAYER-Y !

  CLEAR-GOALS

  BG1-SHADOW-TILEMAP ZERO-TILEMAP
  BG3-SHADOW-TILEMAP ZERO-TILEMAP

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

  LEVEL @ LOAD-LEVEL

  0x7000 SHADOW-OAM-LOWER 0 OAM-LOWER-OBJECTS OAM-COORDINATES + !
  0x02   SHADOW-OAM-UPPER 0 OAM-UPPER-OBJECTS MASK!

  0x02   SHADOW-OAM-LOWER 2 OAM-LOWER-OBJECTS OAM-TILE-NUMBER + C!
  0x30   SHADOW-OAM-LOWER 2 OAM-LOWER-OBJECTS OAM-ATTRIBUTES + C!

  0
  BEGIN
    1+

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

    TRUE NMI-READY !
    BEGIN
      NMI-WAIT
    NMI-READY @ 0= UNTIL

    READ-JOY1

    PLAYER-MOVEMENT

    JOY1-PRESSED @ BUTTON-SELECT AND 0<> IF
      LEVEL @ LOAD-LEVEL
    THEN

    CHECK-WIN IF
      LEVEL @ 1+ DUP NUM-LEVELS >= IF
        DROP 0
      THEN LEVEL !
      LEVEL @ LOAD-LEVEL
    THEN

    DRAW-PLAYER
  FALSE UNTIL
;
