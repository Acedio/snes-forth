0 BANK!

: SET-PALETTE-ENTRY
  \ 0b0BBBBBGGGGGRRRRR
  \ Set background, low byte first
  DUP 0x2122 C!
  HIBYTE 0x2122 C!
  \ Maximum screen brightness
  0x0F 0x2100 C!
  ;

: SNES-MAIN 0x0008 BEGIN
  0x0421 +
  DUP 0x1F AND 0= IF
    DROP 0x0044
  THEN
  DUP SET-PALETTE-ENTRY FALSE UNTIL ;

: SNES-NMI
  21 21 C!
;
