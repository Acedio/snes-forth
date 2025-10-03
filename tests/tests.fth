\ TODO: Tests defined at the root level here don't actually get run on the SNES.

\ Stack ops
T{ 1 2 NIP -> 2 }T
T{ 1 2 OVER -> 1 2 1 }T
T{ 1 2 TUCK -> 2 1 2 }T
T{ 1 2 3 ROT -> 2 3 1 }T
T{ 1 2 3 -ROT -> 3 1 2 }T
T{ 1 >R 2 R@ R> -> 2 1 1 }T
T{ 1 2 2>R 2R@ 2R> -> 1 2 1 2 }T
T{ $123456 A.>R A.R> -> $123456 }T

\ Control flow ops
T{ : TEST-UNTIL 1 BEGIN DUP 1+ DUP 3 = UNTIL ; -> }T
T{ TEST-UNTIL -> 1 2 3 }T

T{ : TEST-WHILE 1 BEGIN DUP 3 < WHILE DUP 1+ REPEAT ; -> }T
T{ TEST-WHILE -> 1 2 3 }T

T{ : TEST-DO 0 4 1 DO I + LOOP ; -> }T
T{ TEST-DO -> 6 }T
T{ : TEST-?DO 4 4 ?DO 1 LOOP ; -> }T
T{ TEST-?DO -> }T

T{ : TEST-IF IF 2 + THEN ; -> }T
T{ 1 TRUE TEST-IF 2 FALSE TEST-IF -> 3 2 }T
T{ : TEST-ELSE IF 1 ELSE 2 THEN ; -> }T
T{ TRUE TEST-ELSE FALSE TEST-ELSE -> 1 2 }T

T{ : TEST-CASE CASE 1 OF 111 ENDOF 2 OF 222 ENDOF >R 333 R> ENDCASE ; -> }T
T{ 1 TEST-CASE 2 TEST-CASE 4 TEST-CASE -> 111 222 333 }T
T{ : TEST-OVERLAPPING-CASE TRUE CASE TRUE OF 111 ENDOF TRUE OF 222 ENDOF ENDCASE ; -> }T
T{ TEST-OVERLAPPING-CASE -> 111 }T

\ Math ops
T{ 0 1 + -> 1 }T
T{ -1 -2 - -> 1 }T
T{ 0x00 0x01 OR -> 1 }T
T{ 0x05 0x03 AND -> 1 }T
T{ 0x03 0x02 XOR -> 1 }T
T{ 0xFFFE INVERT -> 1 }T
T{ 0xFFFF NEGATE -> 1 }T
T{ 0xFF00 LSR -> 0x7F80 }T
T{ 0xFF00 2/ -> 0xFF80 }T
T{ 0x7F80 2* -> 0xFF00 }T
T{ 0x1234 HIBYTE -> 0x0012 }T
T{ 0x1234 SWAPBYTES -> 0x3412 }T

\ Comparison ops
T{ 1 2 < -> TRUE }T
T{ 2 1 < -> FALSE }T
T{ -1 1 < -> TRUE }T
T{ 1 -1 < -> FALSE }T
T{ 2 1 > -> TRUE }T
T{ 1 2 > -> FALSE }T
T{ 1 -1 > -> TRUE }T
T{ -1 1 > -> FALSE }T
T{ 1 1 = -> TRUE }T
T{ 0 1 = -> FALSE }T
T{ 0 1 <> -> TRUE }T
T{ 1 1 <> -> FALSE }T
T{ 0x0001 0xFFFF U< -> TRUE }T
T{ 0xFFFF 0x0001 U< -> FALSE }T
T{ 0xFFFF 0x0001 U> -> TRUE }T
T{ 0x0001 0xFFFF U> -> FALSE }T

\ Literals
T{ $123456 -> 0x0012 0x3456 }T

\ Fetching and storing
T{ CREATELOWRAM TEST-LOWRAM-VAR -> }T
T{ BANK@ LOWRAM BANK! 1 CELLS ALLOT BANK! -> }T
T{ CREATE TEST-VAR 1 CELLS ALLOT -> }T
T{ 21 TEST-LOWRAM-VAR ! TEST-LOWRAM-VAR @ -> 21 }T
T{ 42 TEST-LOWRAM-VAR ! TEST-LOWRAM-VAR @ -> 42 }T

\ Lowram should still be accessible in different banks.
: TEST-BANKS
  T{ BANK@ >R -> }T
  T{ 0 BANK! 33 TEST-LOWRAM-VAR ! 55 TEST-VAR ! -> }T 
  T{ LOWRAM BANK! TEST-LOWRAM-VAR @ TEST-VAR @ -> 33 55 }T
  T{ R> BANK! -> }T
;

T{ : TEST-DOES CREATE , DOES> @ ; -> }T
T{ 21 TEST-DOES TEST-MY-CONSTANT -> }T
\ TODO: Seems like this broke, but why?
\ T{ TEST-MY-CONSTANT TEST-MY-CONSTANT -> 21 21 }T

T{ 0x1234 TEST-LOWRAM-VAR ! -> }T
T{ TEST-LOWRAM-VAR TEST-LOWRAM-VAR 1+ CSWAP! TEST-LOWRAM-VAR @ -> 0x3412 }T

: LUA-ONLY-TESTS
  TEST-BANKS \ Not implemented on the SNES yet.
;

: SNES-ONLY-TESTS
  T{ 0x4000 0x40 PPU-MULT -> $100000 }T
;

: SNES-MAIN
  SNES-ONLY-TESTS
;

\ Needed to run on the SNES.
: SNES-NMI ;

LUA-ONLY-TESTS

: HURRAY! ." All tests passed!" CR ;
HURRAY!
