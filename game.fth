0 BANK!

: SET-PALETTE-ENTRY
  \ 0b0BBBBBGGGGGRRRRR
  \ Set background, low byte first
  DUP 0x2122 C!
  HIBYTE 0x2122 C!
  \ Maximum screen brightness
  0x0F 0x2100 C!
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
CREATE BG-COLOR 1 ALLOT
BANK!

: SNES-MAIN
  0x0044 BG-COLOR !

  BEGIN FALSE UNTIL
;

: SNES-NMI
  \ Only layer 3
  0x04 0x212C C!
  \ Set Mode 1
  1 0x2105 C!
  \ Set BG base
  0 0x2109 C!
  \ Character data area (BG3 1*4K words = 4K words start)
  0x0100 0x210B !
  \ Increment after writing high byte
  0x80 0x2115 C!

  \ Start at the character data area (4Kth word).
  0x1000 0x2116 !

  \ Transfer FONT from page 0
  FONT 0x4302 !
  0 0x4304 C!
  96 2* 2* 2* 2* 0x4305 !
  \ Copy same byte twice (?)
  0x1 0x4300 C!
  \ Copy to VRAM reg
  0x18 0x4301 C!
  \ Start transfer.
  0x01 0x420B C!

  BG-COLOR @
  0x0421 +
  DUP 0x1F AND 0= IF
    DROP 0x0044
  THEN
  DUP BG-COLOR !
  SET-BACKDROP-COLOR
;
