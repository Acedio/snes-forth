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
CREATE MISSED-FRAMES 1 CELLS ALLOT
BANK!

( tiles -- bytes )
: 2BIT-8X8-TILES
  16*
;

( tiles -- bytes )
: 4BIT-16X16-TILES
  [ 16 16 * 2/ COMPILE-LIT ] PPU-MULT DROP
;

32 2* 2* 2* 2* 2* CONSTANT BGTILEMAP-TILE-COUNT

: BGTILEMAP-ENTRIES
  CELLS
;

( addr bytes -- )
: ZERO-FILL
  EACH DO
    0 I C!
  LOOP
;

( tilemap-addr -- )
: ZERO-BGTILEMAP
  BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES ZERO-FILL
;

BANK@
LOWRAM BANK!
CREATE NMI-READY 1 CELLS ALLOT
CREATE NMI-STATE 1 CELLS ALLOT
CREATE BG1-SHADOW-TILEMAP BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES ALLOT
CREATE BG3-SHADOW-TILEMAP BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES ALLOT
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
  FONT-CHARS 2BIT-8X8-TILES
  \ Start at the character data area (4Kth word).
  0x1000
  DMA0-VRAM-TRANSFER
;

: COPY-SPRITES
  \ The bottom two 8x8 tiles of a 16x16 tile are 16 8x8 tiles ahead (1 row
  \ below) the first 8x8 tile.
  SPRITES-TILES
  SPRITES-TILES-BYTES
  0x2000
  DMA0-VRAM-TRANSFER
;

\ TODO: VRAM organization
\ TODO: Store details about VRAM locations all in the same place.

: COPY-MAPTILES
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
  BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES
  \ Start at the tilemap data area (1kth word).
  0x0400 \ word-indexed
  DMA0-VRAM-TRANSFER
;

: COPY-BG3
  BG3-SHADOW-TILEMAP
  BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES
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
    \ We missed a frame.
    1 MISSED-FRAMES +!
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
      TEXT-PALETTE

      1 NMI-STATE +!
    ENDOF
    1 OF
      COPY-SPRITES
      COPY-SPRITES-PALETTE

      1 NMI-STATE +!
    ENDOF
    2 OF
      COPY-MAPTILES
      COPY-MAPTILES-PALETTE

      1 NMI-STATE +!
    ENDOF
    3 OF
      \ Zero shift for BG1
      0x00 0x210D C!
      0x00 0x210D C!
      \ Shift BG3 right by 4 pixels to center text.
      0xFC 0x2111 C!
      0xFF 0x2111 C!

      COPY-BG3

      1 NMI-STATE +!
    ENDOF
    4 OF
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

0 CONSTANT RED
1 CONSTANT YELLOW
2 CONSTANT GREEN
3 CONSTANT CYAN
4 CONSTANT BLUE
5 CONSTANT MAGENTA
6 CONSTANT WHITE

: BALL-ENABLED ; \ First cell.
: BALL-Y 1 CELLS + ;
: BALL-X 2 CELLS + ;
: BALL-COLOR 3 CELLS + ;
: BALLS 2* 2* CELLS ;

8 CONSTANT MAX-BALLS

BANK@
LOWRAM BANK!
CREATE LEVEL 1 CELLS ALLOT
CREATE PLAYER-X 1 CELLS ALLOT
CREATE PLAYER-Y 1 CELLS ALLOT
CREATE BALL-ARRAY MAX-BALLS BALLS ALLOT
BANK!

: CLEAR-BALLS
  BALL-ARRAY MAX-BALLS BALLS EACH DO
    FALSE I BALL-ENABLED !
  1 BALLS +LOOP
;

: NEXT-FREE-BALL-ID
  MAX-BALLS 0 DO
    BALL-ARRAY I BALLS +
    ( &ball )
    BALL-ENABLED @ 0= IF
      I UNLOOP EXIT
    THEN
  LOOP
  \ TODO: ABORT?
  BREAKPOINT
;

( y x color -- ball-index )
: ADD-BALL
  NEXT-FREE-BALL-ID
  >R R@ BALLS BALL-ARRAY +
  TRUE OVER BALL-ENABLED !
  TUCK BALL-COLOR !
  TUCK BALL-X !
  BALL-Y !
  R>
;

4 CONSTANT FIRST-BALL-OAM-OBJECT

: BALL-COLOR-TILE
  \ Red ball at 0x02, in color order to the right.
  2* 0x02 +
;

( ball-id -- )
: DRAW-BALL
  BALL-ARRAY OVER BALLS + SWAP
  FIRST-BALL-OAM-OBJECT + >R
  ( ball-addr R: oam-id )
  DUP BALL-ENABLED @ IF
    DUP BALL-Y @ 16*
    SWAP DUP BALL-X @ 16*
    SWAP BALL-COLOR @ BALL-COLOR-TILE

    \ Tile and attributes only need to be set for enabled balls.
    SHADOW-OAM-LOWER R@ OAM-LOWER-OBJECTS +
    TUCK OAM-TILE-NUMBER C!
    \ TODO: Priority
    0x00 SWAP OAM-ATTRIBUTES C!
  ELSE
    DROP
    \ Hide the ball
    -32 -32
  THEN

  R@ OAM-OBJECT-COORDS!
  TRUE R> OAM-OBJECT-LARGE!
;

: DRAW-BALLS
  MAX-BALLS 0 DO
    I DRAW-BALL
  LOOP
;

: GOAL-ENABLED ; \ First cell.
: GOAL-Y 1 CELLS + ;
: GOAL-X 2 CELLS + ;
: GOAL-COLOR 3 CELLS + ;
: GOALS 2* 2* CELLS ;

8 CONSTANT MAX-GOALS

BANK@
LOWRAM BANK!
CREATE GOAL-ARRAY MAX-GOALS GOALS ALLOT
BANK!

: CLEAR-GOALS
  GOAL-ARRAY MAX-GOALS GOALS EACH DO
    FALSE I GOAL-ENABLED !
  1 GOALS +LOOP
;

( -- &goal )
: NEXT-FREE-GOAL
  MAX-GOALS 0 DO
    GOAL-ARRAY I GOALS +
    ( &goal )
    DUP GOAL-ENABLED @ 0= IF
      UNLOOP EXIT
    THEN
    DROP
  LOOP
  \ TODO: ABORT?
  BREAKPOINT
;

( y x color -- )
: ADD-GOAL
  NEXT-FREE-GOAL
  ( y x color &goal )
  TRUE OVER GOAL-ENABLED !
  TUCK GOAL-COLOR !
  TUCK GOAL-X !
  GOAL-Y !
;

0x14 CONSTANT FIRST-GOAL-OAM-OBJECT

: GOAL-COLOR-TILE
  \ Red goal at 0x02, in color order to the right.
  2* 0x22 +
;

( goal-id )
: DRAW-GOAL
  GOAL-ARRAY OVER GOALS + SWAP
  FIRST-GOAL-OAM-OBJECT + >R
  ( goal-addr R: oam-id )
  DUP GOAL-ENABLED @ IF
    DUP GOAL-Y @ 16*
    SWAP DUP GOAL-X @ 16*
    SWAP GOAL-COLOR @ GOAL-COLOR-TILE

    \ Tile and attributes only need to be set for enabled balls.
    SHADOW-OAM-LOWER R@ OAM-LOWER-OBJECTS +
    TUCK OAM-TILE-NUMBER C!
    \ TODO: Priority
    0x00 SWAP OAM-ATTRIBUTES C!
  ELSE
    DROP
    \ Hide the goal
    -32 -32
  THEN

  R@ OAM-OBJECT-COORDS!
  TRUE R> OAM-OBJECT-LARGE!
;

: DRAW-GOALS
  MAX-GOALS 0 DO
    I DRAW-GOAL
  LOOP
;

( y x -- )
: SET-PLAYER-COORDS
  PLAYER-X !
  PLAYER-Y !
;

3 CONSTANT PLAYER-OAM-OBJECT

( ticks -- )
: DRAW-PLAYER
  SHADOW-OAM-LOWER PLAYER-OAM-OBJECT OAM-LOWER-OBJECTS +
  SWAP
  0xF AND 0= IF
    DUP OAM-TILE-NUMBER DUP @ 0x20 XOR SWAP C!
  THEN
  JOY1-PRESSED @ BUTTON-RIGHT AND 0<> IF
    0x40 OVER OAM-ATTRIBUTES C!
  THEN
  JOY1-PRESSED @ BUTTON-LEFT AND 0<> IF
    0x00 OVER OAM-ATTRIBUTES C!
  THEN
  DROP
  PLAYER-Y @ 16* PLAYER-X @ 16* PLAYER-OAM-OBJECT OAM-OBJECT-COORDS!
  TRUE PLAYER-OAM-OBJECT OAM-OBJECT-LARGE!
;

\ These are word constants, but will be stored as bytes in the level map.
0x0000 CONSTANT EMPTY-TILE
0x0001 CONSTANT WALL-TILE
\ TODO: Other goal tiles.
0x0020 CONSTANT BALL-0-TILE \ Ball 1 is BALL-0-TILE 1+, etc

: MAP-TILES
  \ 1 byte per entry
;

\ For now we're limited to one BGTILEMAP's-worth of tiles in a map.
BGTILEMAP-TILE-COUNT CONSTANT MAP-TILES-COUNT

BANK@
LOWRAM BANK!
CREATE LEVEL-MAP MAP-TILES-COUNT MAP-TILES ALLOT
BANK!

( y x -- &tile )
: TILE-ADDR
  SWAP 32 PPU-MULT DROP + MAP-TILES
  LEVEL-MAP +
;

( y x -- tile )
: TILE-AT
  TILE-ADDR C@
;

: DRAW-LEVEL
  BG1-SHADOW-TILEMAP
  LEVEL-MAP MAP-TILES-COUNT MAP-TILES EACH DO
    I C@ CASE
      EMPTY-TILE OF 0x0400 ENDOF
      WALL-TILE OF 0x0420 ENDOF
      >R 0x0400 R>
    ENDCASE
    OVER !
    1 BGTILEMAP-ENTRIES +
  1 MAP-TILES +LOOP
  DROP \ Drop the BGTILEMAP pointer
;

( addr -- non-lf-addr )
: SKIP-LINEFEEDS
  BEGIN
    DUP 1+ SWAP
    C@
    DUP 0x0A =
  WHILE
    DROP
  REPEAT
;

( addr -- )
: LOAD-LEVEL-FROM-STRING
  CLEAR-BALLS
  CLEAR-GOALS

  \ Keep track of Y and X
  0 0 ROT
  LEVEL-MAP MAP-TILES-COUNT MAP-TILES EACH DO
    SKIP-LINEFEEDS
    ( y x &str char -- )
    CASE
      [CHAR]   OF                                  EMPTY-TILE    ENDOF
      [CHAR] # OF                                  WALL-TILE     ENDOF
      [CHAR] r OF >R 2DUP R> -ROT RED     ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] y OF >R 2DUP R> -ROT YELLOW  ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] g OF >R 2DUP R> -ROT GREEN   ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] c OF >R 2DUP R> -ROT CYAN    ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] b OF >R 2DUP R> -ROT BLUE    ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] m OF >R 2DUP R> -ROT MAGENTA ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] w OF >R 2DUP R> -ROT WHITE   ADD-GOAL EMPTY-TILE    ENDOF
      \ Set the ball tile based on the index returned by ADD-BALL.
      [CHAR] R OF >R 2DUP R> -ROT RED     ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] Y OF >R 2DUP R> -ROT YELLOW  ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] G OF >R 2DUP R> -ROT GREEN   ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] C OF >R 2DUP R> -ROT CYAN    ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] B OF >R 2DUP R> -ROT BLUE    ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] M OF >R 2DUP R> -ROT MAGENTA ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] W OF >R 2DUP R> -ROT WHITE   ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] @ OF -ROT 2DUP SET-PLAYER-COORDS ROT  EMPTY-TILE    ENDOF
      >R EMPTY-TILE R>
    ENDCASE
    \ Store the tile.
    I C!
    \ Increment X, then overflow to Y and reset if necessary.
    >R 1+ DUP 32 >= IF
      DROP 1+ 0
    THEN R>
  1 MAP-TILES +LOOP
  \ Drop the string indexing address, X, and Y
  DROP DROP DROP
;

( level-id -- )
: LOAD-LEVEL
  LEVEL-STRING LOAD-LEVEL-FROM-STRING
  DRAW-LEVEL
  DRAW-BALLS
  DRAW-GOALS
;

: TILEMAP-XY
  32 PPU-MULT DROP + ;

( tile-id -- is-ball )
: IS-BALL-TILE?
  DUP BALL-0-TILE >=
  SWAP BALL-0-TILE MAX-BALLS + < AND
;

( dy dx &ball -- can-move )
: BALL-CAN-MOVE?
  >R
  R@ BALL-X @ + SWAP
  R> BALL-Y @ + SWAP
  TILE-AT EMPTY-TILE =
;

( dy dx y x -- )
: MOVE-TILEMAP-BALL
  2>R 2R@ 2+2 TILE-ADDR
  2R> TILE-ADDR
  ( &tile1 &tile2 )
  CSWAP!
;

( dy dx ball-id -- moved )
: MOVE-BALL
  DUP >R
  BALLS BALL-ARRAY + >R
  ( dy dx )
  2DUP R@ BALL-CAN-MOVE? 0= IF
    2DROP R> R> DROP DROP
    FALSE EXIT
  THEN
  \ Update tilemap and array.
  2DUP
  R@ BALL-Y @ R@ BALL-X @ MOVE-TILEMAP-BALL
  R@ BALL-X +!
  R> BALL-Y +!
  R> DRAW-BALL
  TRUE
;

( tile-id -- ball-id )
: BALL-INDEX
  BALL-0-TILE -
;

( dy dx -- moved )
: MOVE-PLAYER
  OVER PLAYER-Y @ +
  OVER PLAYER-X @ +
  ( dy dx ny nx )
  2DUP TILE-AT
  ( dy dx ny nx tile-id )
  DUP EMPTY-TILE = IF
    DROP PLAYER-X ! PLAYER-Y !
    2DROP
    TRUE EXIT
  THEN

  ( dy dx ny nx tile-id )
  DUP IS-BALL-TILE? IF
    BALL-INDEX >R
    2SWAP R>
    ( ny nx dy dx ball-id )
    MOVE-BALL IF 
      PLAYER-X ! PLAYER-Y !
      TRUE EXIT
    THEN
    2DROP FALSE EXIT
  THEN
  \ Wasn't empty or a ball, so no bueno.
  DROP 2DROP 2DROP FALSE
;

: PLAYER-MOVEMENT
  TRUE CASE
    JOY1-PRESSED @ BUTTON-UP AND 0<> OF
      -1 0 MOVE-PLAYER DROP
    ENDOF
    JOY1-PRESSED @ BUTTON-DOWN AND 0<> OF
      1 0 MOVE-PLAYER DROP
    ENDOF
    JOY1-PRESSED @ BUTTON-LEFT AND 0<> OF
      0 -1 MOVE-PLAYER DROP
    ENDOF
    JOY1-PRESSED @ BUTTON-RIGHT AND 0<> OF
      0 1 MOVE-PLAYER DROP
    ENDOF
  ENDCASE
  \ TODO: Can make a sound here?
;

: CHECK-WIN
  GOAL-ARRAY MAX-GOALS GOALS EACH DO
    I GOAL-ENABLED @ IF
      \ TODO: Care about colors.
      I GOAL-Y @ I GOAL-X @ TILE-AT IS-BALL-TILE? 0= IF
        FALSE UNLOOP EXIT
      THEN
    THEN
  1 GOALS +LOOP
  TRUE
;

: SNES-MAIN
  FALSE NMI-READY !
  0 NMI-STATE !
  0 BG-TICKS !
  0 MISSED-FRAMES !

  0 JOY1-HELD !
  0 JOY1-PRESSED !

  0 LEVEL !

  0 PLAYER-X !
  0 PLAYER-Y !

  BG1-SHADOW-TILEMAP ZERO-BGTILEMAP
  BG3-SHADOW-TILEMAP ZERO-BGTILEMAP

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

    DUP DRAW-PLAYER
  FALSE UNTIL
;
