\ These are in order such that 3 bits indicate color combinations, e.g. a color
\ with bit 1 set always has red in it, bit 2 for green, and bit 3 for blue.
1 CONSTANT RED
2 CONSTANT GREEN
3 CONSTANT YELLOW
4 CONSTANT BLUE
5 CONSTANT MAGENTA
6 CONSTANT CYAN
7 CONSTANT WHITE

: BALL-ENABLED ; \ First cell.
: BALL-Y 1 CELLS + ;
: BALL-X 2 CELLS + ;
: BALL-COLOR 3 CELLS + ;
: BALLS 2* 2* CELLS ;

8 CONSTANT MAX-BALLS

BANK@
LOWRAM BANK!
CREATE LEVEL 1 CELLS ALLOT
CREATE LEVEL-STATE 1 CELLS ALLOT
CREATE LEVEL-NMI-STATE 1 CELLS ALLOT
CREATE LEVEL-TICKS 1 CELLS ALLOT
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
  \ Red is color 1 and red ball at 0x02, in color order to the right.
  2*
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
    0x30 SWAP OAM-ATTRIBUTES C!
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
  \ Red is color 1 and red goal at 0x22, in color order to the right.
  2* 0x20 +
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
    0x30 OVER OAM-ATTRIBUTES C!
  THEN
  DROP
  PLAYER-Y @ 16* PLAYER-X @ 16* PLAYER-OAM-OBJECT OAM-OBJECT-COORDS!
  TRUE PLAYER-OAM-OBJECT OAM-OBJECT-LARGE!
;

\ These are word constants, but will be stored as bytes in the level map.
0x0000 CONSTANT EMPTY-TILE
0x0001 CONSTANT WALL-TILE
0x0010 CONSTANT TUTORIAL-TILES
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
    I C@ DUP 0x20 < IF
      2* 0x0400 +
    ELSE
      DROP 0x0400
    THEN
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
      [CHAR] 0 OF                                  TUTORIAL-TILES 0 + ENDOF
      [CHAR] 1 OF                                  TUTORIAL-TILES 1 + ENDOF
      [CHAR] 2 OF                                  TUTORIAL-TILES 2 + ENDOF
      [CHAR] 3 OF                                  TUTORIAL-TILES 3 + ENDOF
      [CHAR] 4 OF                                  TUTORIAL-TILES 4 + ENDOF
      [CHAR] 5 OF                                  TUTORIAL-TILES 5 + ENDOF
      [CHAR] 6 OF                                  TUTORIAL-TILES 6 + ENDOF
      [CHAR] 7 OF                                  TUTORIAL-TILES 7 + ENDOF
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

( tile-id -- is-ball )
: IS-BALL-TILE?
  DUP BALL-0-TILE >=
  SWAP BALL-0-TILE MAX-BALLS + < AND
;

( ball-tile-id -- ball-id )
: BALL-FOR-TILE
  BALL-0-TILE -
;

( dy dx &ball -- can-move )
: BALL-CAN-MOVE?
  >R
  R@ BALL-X @ + SWAP
  R> BALL-Y @ + SWAP
  TILE-AT EMPTY-TILE =
;

( dy dx &ball -- merged )
: TRY-MERGE
  \ TODO: Refactor this, this is long and gross.
  >R
  R@ BALL-X @ + SWAP
  R@ BALL-Y @ + SWAP
  TILE-ADDR
  ( &target-tile R: &merging-ball )
  DUP C@ IS-BALL-TILE? 0= IF
    DROP R> DROP FALSE EXIT
  THEN
  ( &target-tile R: &merging-ball )
  \ Use ball tile as index into ball array
  DUP C@ BALL-FOR-TILE DUP BALLS BALL-ARRAY +
  ( &target-tile target-ball-id &target-ball R: &merging-ball )
  DUP BALL-COLOR @ DUP
  ( &target-tile target-ball-id &target-ball target-color target-color )
  R@ BALL-COLOR @ AND 0<> IF
    \ If the colors overlap in one or more bits, they are not mergeable.
    DROP DROP DROP DROP R> DROP FALSE EXIT
  THEN
  ( &target-tile target-ball-id &target-ball target-color R: &merging-ball )
  \ Update current ball color.
  R@ BALL-COLOR TUCK @ OR SWAP !

  ( &target-tile target-ball-id &target-ball R: &merging-ball )
  \ Disable target ball and draw it to hide it.
  FALSE OVER BALL-ENABLED !
  SWAP DRAW-BALL

  ( &target-tile &target-ball R: &merging-ball )
  \ Save the tile address of the merging ball.
  R@ BALL-Y @ R@ BALL-X @ TILE-ADDR SWAP
  ( &target-tile &merging-tile &target-ball R: &merging-ball )
  \ Take the target balls position.
  DUP BALL-Y @ R@ BALL-Y !
  BALL-X @ R@ BALL-X !

  ( &target-tile &merging-tile R: &merging-ball )
  DUP C@ SWAP \ Save the merging ball tile ID
  EMPTY-TILE SWAP C! \ Erase the merging position.
  SWAP C! \ Overwrite the target ball position.

  R> DROP

  TRUE
;

( dy dx y x -- )
: MOVE-TILEMAP-BALL
  2>R 2R@ 2+2 TILE-ADDR
  2R> TILE-ADDR
  ( &tile1 &tile2 )
  \ TODO: This is silly, should just set EMPTY-TILE behind us.
  CSWAP!
;

( dy dx ball-id -- moved )
: MOVE-BALL
  DUP >R
  BALLS BALL-ARRAY + >R
  ( dy dx )
  2DUP R@ BALL-CAN-MOVE? IF
    \ Update tilemap and array.
    2DUP
    R@ BALL-Y @ R@ BALL-X @ MOVE-TILEMAP-BALL
    R@ BALL-X +!
    R> BALL-Y +!
    R> DRAW-BALL
    TRUE EXIT
  THEN
  ( dy dx )
  R@ TRY-MERGE IF
    R> DROP
    R> DRAW-BALL
    TRUE EXIT
  THEN
  R> R> DROP DROP
  FALSE
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
      -1 0 MOVE-PLAYER
    ENDOF
    JOY1-PRESSED @ BUTTON-DOWN AND 0<> OF
      1 0 MOVE-PLAYER
    ENDOF
    JOY1-PRESSED @ BUTTON-LEFT AND 0<> OF
      0 -1 MOVE-PLAYER
    ENDOF
    JOY1-PRESSED @ BUTTON-RIGHT AND 0<> OF
      0 1 MOVE-PLAYER
    ENDOF
    \ Player didn't move.
    >R FALSE R>
  ENDCASE
  IF INCR-STEPS THEN
;

: CHECK-WIN
  GOAL-ARRAY MAX-GOALS GOALS EACH DO
    I GOAL-ENABLED @ IF
      I GOAL-Y @ I GOAL-X @ TILE-AT
      DUP IS-BALL-TILE? 0= IF
        DROP FALSE UNLOOP EXIT
      THEN
      \ Check for color match.
      BALL-FOR-TILE BALLS BALL-ARRAY + BALL-COLOR @
      I GOAL-COLOR @ <> IF
        FALSE UNLOOP EXIT
      THEN
    THEN
  1 GOALS +LOOP
  TRUE
;

: COPY-SPRITES
  \ The bottom two 8x8 tiles of a 16x16 tile are 16 8x8 tiles ahead (1 row
  \ below) the first 8x8 tile.
  SPRITES-TILES
  SPRITES-TILES-BANK
  SPRITES-TILES-BYTES
  0x2000
  DMA0-VRAM-LONG-TRANSFER
;

\ TODO: VRAM organization
\ TODO: Store details about VRAM locations all in the same place.

: COPY-MAPTILES
  MAPTILES-TILES
  MAPTILES-TILES-BANK
  MAPTILES-TILES-BYTES
  0x4000
  DMA0-VRAM-LONG-TRANSFER
;

: COPY-SPRITES-PALETTE
  SPRITES-PAL
  SPRITES-PAL-BANK
  SPRITES-PAL-BYTES
  0x80
  COPY-CGRAM-PALETTE-LONG
;

: COPY-MAPTILES-PALETTE
  MAPTILES-PAL
  MAPTILES-PAL-BANK
  MAPTILES-PAL-BYTES
  0x10
  COPY-CGRAM-PALETTE-LONG
;

: LEVEL-COPY-BG1
  BG1-SHADOW-TILEMAP
  \ Start at the tilemap data area (1kth word).
  0x0400 \ word-indexed
  COPY-BG-TO-VRAM
;

3 CONSTANT LEVEL-LOAD-NMI-STATE

: LEVEL-NMI
  \ TODO: Text is at 1*4K words = starts at 4K.w
  \ Character data areas 
  \ - BG1 4*4K words = 16K.w start
  LEVEL-NMI-STATE @ CASE
    0 OF
      COPY-SPRITES
      COPY-SPRITES-PALETTE

      1 LEVEL-NMI-STATE +!
    ENDOF
    1 OF
      COPY-MAPTILES
      COPY-MAPTILES-PALETTE

      1 LEVEL-NMI-STATE +!
    ENDOF
    2 OF
      STARS-NMI IF
        1 LEVEL-NMI-STATE +!
      THEN
    ENDOF
    LEVEL-LOAD-NMI-STATE OF
      LEVEL-COPY-BG1

      \ Set Mode 1 BG3 high priority (0x.9), BG1 BG2 BG3 tile size 16x16 (0x7.)
      0x11 0x11 BG-MODE MASK!

      \ Set BG1 base (VRAM @ 0x800 (0x400.w))
      4 0x2107 C!

      \ Zero shift for BG1
      0x00 0x210D C!
      0x00 0x210D C!

      1 LEVEL-NMI-STATE +!
    ENDOF
    4 OF
      \ Layers 1 and OBJ
      0x11 0x11 BG-LAYER-ENABLE MASK!

      \ Small sprites, OBJ tile base at VRAM 0x2000 (8Kth word)
      1 0x2101 C!

      \ TODO: Copying this below STARS-NMI causes issues.
      COPY-OAM

      STARS-NMI DROP
    ENDOF
  ENDCASE

  \ Maximum screen brightness
  0x0F 0x2100 C!
;

0 CONSTANT LEVEL-PLAYING
1 CONSTANT LEVEL-WIN

: LEVEL-INIT
  INIT-STEPS
  0 LEVEL-NMI-STATE !
  LEVEL-PLAYING LEVEL-STATE !

  0 LEVEL-TICKS !

  INITIAL-LEVEL LEVEL !

  0 PLAYER-X !
  0 PLAYER-Y !

  STARS-INIT

  0x0004 0x000F BG-BASE-ADDRESSES MASK!
  0x11   0x11   BG-MODE           MASK!

  LEVEL @ LOAD-LEVEL
;

: LEVEL-SKIP?
  \ Skip the level if the player presses START while holding SELECT.
  JOY1-HELD @ BUTTON-SELECT AND 0<>
  JOY1-PRESSED @ BUTTON-START AND 0<>
  AND
;

: RESTART?
  JOY1-PRESSED @ BUTTON-START AND 0<>
;

: LEVEL-MAIN
  1 LEVEL-TICKS +!

  STARS-MAIN

  LEVEL-STATE @ CASE
    LEVEL-PLAYING OF
      PLAYER-MOVEMENT

      CHECK-WIN LEVEL-SKIP? OR IF
        AUDIO-PLAY-SFX
        LEVEL-WIN LEVEL-STATE !
      ELSE
        \ Check restart after level skip because both check for a START press.
        RESTART? IF
          LEVEL @ LOAD-LEVEL
        THEN
      THEN
    ENDOF
    LEVEL-WIN OF
      \ Separate win state so we get a frame to update the player and ball
      \ positions, as well as let the SFX play.
      LEVEL @ 1+ DUP NUM-LEVELS >= IF
        DROP TRUE EXIT
      THEN LEVEL !
      LEVEL @ LOAD-LEVEL
      LEVEL-LOAD-NMI-STATE LEVEL-NMI-STATE !
      LEVEL-PLAYING LEVEL-STATE !
    ENDOF
  ENDCASE

  LEVEL-TICKS @ DRAW-PLAYER

  FALSE \ Still running.
;
