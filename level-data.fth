\ This file describes the data structures used to store and manipulate level
\ data. It's separated from the level gameplay/drawing code itself because I
\ want to store the data for levels in a separate file and that file must come
\ _after_ the data descriptions but _before_ the level gameplay code.

\ == Enums and data structures ==

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

: GOAL-ENABLED ; \ First cell.
: GOAL-Y 1 CELLS + ;
: GOAL-X 2 CELLS + ;
: GOAL-COLOR 3 CELLS + ;
: GOALS 2* 2* CELLS ;

8 CONSTANT MAX-GOALS

: MAP-TILES
  \ 1 byte per entry
;

\ For now we're limited to one BGTILEMAP's-worth of tiles in a map.
BGTILEMAP-TILE-COUNT CONSTANT MAP-TILES-COUNT

BANK@
LOWRAM BANK!
CREATE LEVEL 1 CELLS ALLOT
CREATE LEVEL-STATE 1 CELLS ALLOT
CREATE LEVEL-NMI-STATE 1 CELLS ALLOT
CREATE LEVEL-TICKS 1 CELLS ALLOT
\ Level data is contiguous so we can initialize it in a single DMA call.
HERE
DUP CONSTANT LEVEL-DATA-START
CREATE PLAYER-X 1 CELLS ALLOT
CREATE PLAYER-Y 1 CELLS ALLOT
CREATE BALL-ARRAY MAX-BALLS BALLS ALLOT
CREATE GOAL-ARRAY MAX-GOALS GOALS ALLOT
CREATE LEVEL-MAP MAP-TILES-COUNT MAP-TILES ALLOT
HERE
SWAP - CONSTANT LEVEL-DATA-SIZE-BYTES
BANK!

\ == Ball words ==

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

\ == Goal words ==

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

\ == Player words ==

( y x -- )
: SET-PLAYER-COORDS
  PLAYER-X !
  PLAYER-Y !
;

\ == Tilemap words ==

\ These are word constants, but will be stored as bytes in the level map.
0x0000 CONSTANT EMPTY-TILE
0x0001 CONSTANT WALL-TILE
0x0010 CONSTANT TUTORIAL-TILES
0x0020 CONSTANT BALL-0-TILE \ Ball 1 is BALL-0-TILE 1+, etc

( y x -- &tile )
: TILE-ADDR
  SWAP 32 PPU-MULT DROP + MAP-TILES
  LEVEL-MAP +
;

( y x -- tile )
: TILE-AT
  TILE-ADDR C@
;

( tile-id -- is-ball )
: IS-BALL-TILE?
  DUP BALL-0-TILE >=
  SWAP BALL-0-TILE MAX-BALLS + < AND
;

( ball-tile-id -- ball-id )
: TILE-BALL-INDEX
  BALL-0-TILE -
;

\ == Loading and compiling levels ==

\ Skips linefeeds.
( -- next-char )
: GET-NEXT-CHAR
  BEGIN
    KEY
    DUP
    0x0A =
  WHILE
    DROP
  REPEAT
;

\ Loads a level from a description in the input stream.
: LOAD-LEVEL"
  CLEAR-BALLS
  CLEAR-GOALS

  \ Keep track of Y and X
  0 0
  LEVEL-MAP MAP-TILES-COUNT MAP-TILES EACH DO
    GET-NEXT-CHAR
    ( y x char -- )
    CASE
      [CHAR]   OF                        EMPTY-TILE    ENDOF
      [CHAR] # OF                        WALL-TILE     ENDOF
      [CHAR] r OF 2DUP RED      ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] y OF 2DUP YELLOW   ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] g OF 2DUP GREEN    ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] c OF 2DUP CYAN     ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] b OF 2DUP BLUE     ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] m OF 2DUP MAGENTA  ADD-GOAL EMPTY-TILE    ENDOF
      [CHAR] w OF 2DUP WHITE    ADD-GOAL EMPTY-TILE    ENDOF
      \ Set the ball tile based on the index returned by ADD-BALL.
      [CHAR] R OF 2DUP RED      ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] Y OF 2DUP YELLOW   ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] G OF 2DUP GREEN    ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] C OF 2DUP CYAN     ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] B OF 2DUP BLUE     ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] M OF 2DUP MAGENTA  ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] W OF 2DUP WHITE    ADD-BALL BALL-0-TILE + ENDOF
      [CHAR] @ OF 2DUP SET-PLAYER-COORDS EMPTY-TILE    ENDOF
      [CHAR] 0 OF                        TUTORIAL-TILES 0 + ENDOF
      [CHAR] 1 OF                        TUTORIAL-TILES 1 + ENDOF
      [CHAR] 2 OF                        TUTORIAL-TILES 2 + ENDOF
      [CHAR] 3 OF                        TUTORIAL-TILES 3 + ENDOF
      [CHAR] 4 OF                        TUTORIAL-TILES 4 + ENDOF
      [CHAR] 5 OF                        TUTORIAL-TILES 5 + ENDOF
      [CHAR] 6 OF                        TUTORIAL-TILES 6 + ENDOF
      [CHAR] 7 OF                        TUTORIAL-TILES 7 + ENDOF
      >R EMPTY-TILE R>
    ENDCASE
    \ Store the tile.
    I C!
    \ Increment X, then overflow to Y and reset if necessary.
    1+ DUP 32 >= IF
      DROP 1+ 0
    THEN
  1 MAP-TILES +LOOP
  KEY [CHAR] " <> ABORT" Level included an incorrect number of characters."
  \ Drop the X and Y
  DROP DROP
;

\ Compiles the level.
: LEVEL-DATA,
  LEVEL-DATA-START LEVEL-DATA-SIZE-BYTES EACH DO
    I C@ C,
  LOOP
;

( addr page -- )
: LEVEL-DATA@
  LEVEL-DATA-SIZE-BYTES LEVEL-DATA-START 0
  DMA0-WRAM-LONG-TRANSFER
; LABEL _LEVEL_DATA_FETCH
 
