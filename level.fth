\ This file contains the gameplay and graphics routines for the puzzles. For the
\ data structures, see level-data.fth. For the levels themselves, see
\ levels.fth.

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

0x30 CONSTANT LEVEL-MAP-PALETTE-CGRAM-ADDR \ Word addr
LEVEL-MAP-PALETTE-CGRAM-ADDR SWAPBYTES LSR LSR CONSTANT LEVEL-MAP-PALETTE-OFFSET

: DRAW-TILEMAP
  LEVEL-MAP WMADDR-ADDR !
  0 WMADDR-PAGE C!

  BG1-SHADOW-TILEMAP
  DUP BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES >R

  BEGIN
    WMDATA C@ \ automatically increments
    DUP 0x20 < IF
      2* LEVEL-MAP-PALETTE-OFFSET +
    ELSE
      DROP LEVEL-MAP-PALETTE-OFFSET
    THEN
    OVER !
    1 BGTILEMAP-ENTRIES +
  DUP R@ = UNTIL
  DROP R> DROP
;

: DRAW-LEVEL
  DRAW-TILEMAP
  DRAW-BALLS
  DRAW-GOALS
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
  DUP C@ TILE-BALL-INDEX DUP BALLS BALL-ARRAY +
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
    TILE-BALL-INDEX >R
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
      TILE-BALL-INDEX BALLS BALL-ARRAY + BALL-COLOR @
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
  OAM-TILE-BASE OAM-TILE-BASE-TO-VRAM-WORD
  DMA0-VRAM-LONG-TRANSFER
;

: COPY-MAPTILES
  MAPTILES-TILES
  MAPTILES-TILES-BANK
  MAPTILES-TILES-BYTES
  LEVEL-BG-TILE-BASE TILE-BASE-TO-VRAM-WORD
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
  LEVEL-MAP-PALETTE-CGRAM-ADDR
  COPY-CGRAM-PALETTE-LONG
;

: LEVEL-COPY-BG1
  BG1-SHADOW-TILEMAP BANK@
  LEVEL-BG-MAP-BASE MAP-BASE-TO-VRAM-WORD
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

      LEVEL-BG-MAP-BASE 0x2107 C!

      LEVEL-BG-TILE-BASE BG1-TILE-BASE!

      \ Zero shift for BG1
      0x00 0x210D C!
      0x00 0x210D C!
      0x00 0x210E C!
      0x00 0x210E C!

      1 LEVEL-NMI-STATE +!
    ENDOF
    4 OF
      \ Layers 1 and OBJ
      0x11 0x11 BG-LAYER-ENABLE MASK!

      OAM-TILE-BASE 0x2101 C!

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

  LEVEL @ LOAD-LEVEL
  DRAW-LEVEL
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

      JOY1-PRESSED @ BUTTON-A AND 0<> IF
        LEVEL-TICKS @ 0x01 AND 0<> IF
          AUDIO-PLAY-MEOW1
        ELSE
          AUDIO-PLAY-MEOW2
        THEN
      THEN

      CHECK-WIN LEVEL-SKIP? OR IF
        AUDIO-PLAY-CHIME
        LEVEL-WIN LEVEL-STATE !
      ELSE
        \ Check restart after level skip because both check for a START press.
        RESTART? IF
          LEVEL @ LOAD-LEVEL
          DRAW-LEVEL
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
      DRAW-LEVEL
      LEVEL-LOAD-NMI-STATE LEVEL-NMI-STATE !
      LEVEL-PLAYING LEVEL-STATE !
    ENDOF
  ENDCASE

  LEVEL-TICKS @ DRAW-PLAYER

  FALSE \ Still running.
;

