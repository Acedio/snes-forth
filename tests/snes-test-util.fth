REQUIRE std.fth

REQUIRE cgram.fth
REQUIRE oam.fth
REQUIRE snes-std.fth
REQUIRE vram.fth

BANK@
LOWRAM BANK!
CREATE TESTS-PASSED 1 CELLS ALLOT
BANK!

\ Needed to run on the SNES.
: SNES-NMI
  \ Disable all layers initially.
  0x00 BG-LAYER-ENABLE C!
  \ Set Mode 1 BG3 high priority (0x.9), BG1 BG2 BG3 tile size 16x16 (0x7.)
  0x79 BG-MODE C!

  \ Maximum screen brightness
  0x000F SET-SCREEN-BRIGHTNESS

  TESTS-PASSED @ IF
    \ Green! :D
    0x02E0 SET-BACKDROP-COLOR
  ELSE
    \ Red! :(
    0x001F SET-BACKDROP-COLOR
  THEN

  \ Wait for copying until the subcomponents had a chance to modify.
  COPY-BASE-REGISTERS
;

: SNES-TEST-INIT
  FALSE TESTS-PASSED !

  INIT-BASE-REGISTERS
  ZERO-SHADOW-TILEMAPS
  ZERO-OAM

  NMI-ENABLE
;

: SNES-TESTS-PASSED-YAY!
  TRUE TESTS-PASSED !
;

