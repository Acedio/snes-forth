: TEST-UNTIL 1 BEGIN DUP 1+ DUP 5 = UNTIL ;

: TEST-WHILE 1 BEGIN DUP 5 < WHILE DUP 1+ REPEAT ;

: TEST-MATH-OP
  0 1 +
  -1 -2 -
  0x00 0x01 OR
  0x05 0x03 AND
  0x03 0x02 XOR
  0xFFFE INVERT
  0xFFFF NEGATE
;

: TEST-COMPARISON
  1 2 <
  2 1 <
  2 1 >
  1 2 >
  1 1 =
  0 1 =
  0 1 <>
  1 1 <>
  0xFFFE 0xFFFF U<
  0xFFFF 0xFFFE U<
  0xFFFF 0xFFFE U>
  0xFFFE 0xFFFF U>
;

(
TODO: Implement the T{ ... -> ... }T notation.
: T{
: ->
)

: MAIN
  TEST-UNTIL
  TEST-WHILE
  TEST-MATH-OP
  TEST-COMPARISON
  ;

MAIN
