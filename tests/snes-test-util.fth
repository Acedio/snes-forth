REQUIRE std.fth
REQUIRE snes-std.fth

BANK@
LOWRAM BANK!
CREATE TESTS-PASSED 1 CELLS ALLOT
BANK!

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

\ Needed to run on the SNES.
: SNES-NMI
  TESTS-PASSED @ IF
    \ Green! :D
    0x02E0 SET-BACKDROP-COLOR
  ELSE
    \ Red! :(
    0x001F SET-BACKDROP-COLOR
  THEN

  \ Set base addresses.
  0x0000 0x210B !
  \ Set Mode 1 BG3 high priority (0x.9), BG1 BG2 BG3 tile size 16x16 (0x7.)
  0x79 0x2105 C!
  \ Disable all layers (including sprites).
  0x00 0x212C C!
  \ Screen brightness.
  0x000F 0x2100 C!
;

: SNES-TEST-INIT
  FALSE TESTS-PASSED !

  NMI-ENABLE
;

: SNES-TESTS-PASSED-YAY!
  TRUE TESTS-PASSED !
;

