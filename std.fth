: ' WORD FIND DROP ; LABEL _TICK
: POSTPONE ' COMPILE, ; IMMEDIATE

: IF 0x9999 COMPILE-BRANCH0 CODEHERE ; IMMEDIATE
: THEN DUP >R CODEHERE SWAP ADDRESS-OFFSET R> 2 - ! ; IMMEDIATE
: ELSE 0x9999 COMPILE-BRANCH CODEHERE SWAP POSTPONE THEN ; IMMEDIATE

: BEGIN CODEHERE ; IMMEDIATE
: UNTIL 0x9999 COMPILE-BRANCH0 CODEHERE ADDRESS-OFFSET CODEHERE 2 - ! ; IMMEDIATE

: [CHAR] KEY DROP KEY COMPILE-LIT ; IMMEDIATE

: ( BEGIN KEY [CHAR] ) = UNTIL ; IMMEDIATE LABEL _L_PAREN

( *big breath of air* Whew, can finally comment now! )

( I feel like the way I'm grabbing a CR char here probably isn't portable. )
: \ BEGIN KEY [CHAR] 
= UNTIL ; IMMEDIATE LABEL _BACKSLASH

: ['] ' COMPILE-LIT ; IMMEDIATE LABEL _BRACKET_TICK
: :NONAME CODEHERE ] ;

\ Stack manipulation stuff.
: NIP SWAP DROP ;
: TUCK SWAP OVER ;
( a b c - b c a )
: ROT >R SWAP R> SWAP ;
: -ROT ROT ROT ; LABEL _NROT

\ Random math ops.
: 0= 0 = ; LABEL _0_EQ
: 0<> 0 <> ; LABEL _0_NE
: 0< 0 < ; LABEL _0_GT
: 0> 0 > ; LABEL _0_LT

: 2/ DUP LSR SWAP 0x8000 AND OR ; LABEL _DIV2
: 1- 1 - ; LABEL _DECR

\ A couple more flow control words.
: WHILE POSTPONE IF SWAP ; IMMEDIATE
\ CODEHERE 2 - is used below (and above) to update the branch offset (0x9999).
: REPEAT 0x9999 COMPILE-BRANCH CODEHERE ADDRESS-OFFSET CODEHERE 2 - ! POSTPONE THEN ; IMMEDIATE

\ An early exit pattern (without having to use ; more than once in a word, which
\ would feel weird).
: ;THEN COMPILE-RTS POSTPONE THEN ; IMMEDIATE

( A CASE is basically just a list of IF ELSE ... ELSE ELSE THEN. The final THEN
  is shared among all the ELSEs. )
: CASE 0 ; IMMEDIATE \ Pushes the number of THENs to resolve onto the stack.
: OF ['] OVER COMPILE, ['] = COMPILE, POSTPONE IF ['] DROP COMPILE, ; IMMEDIATE
: ENDOF POSTPONE ELSE
  ( Add the unresolved ELSE to our list and increment our count )
  SWAP 1+ ; IMMEDIATE
: ENDCASE \ Fill in all of our unresolved ELSEs.
  ['] DROP COMPILE, \ First drop our CASE selector (needed for the default case)
  BEGIN
    DUP 0>
  WHILE
    SWAP POSTPONE THEN 1- \ Perform a THEN for every ELSE that we pushed.
  REPEAT DROP ; IMMEDIATE

: 2>R R> -ROT SWAP >R >R >R ;
: 2R> R> R> R> ROT >R SWAP ;
: 2R@ R> R> R@ SWAP >R R@ ROT >R ; LABEL _2R_FETCH

\ Push control vars onto the return stack.
( TO FROM -- r: TO FROM )
: DODO R> -ROT 2>R >R ;
\ TODO: This whole structure where DO has to start an IF block because ?DO needs
\       it (and they both use LOOP), is gross. Can we make it prettier?
: DO TRUE COMPILE-LIT POSTPONE IF ['] DODO COMPILE, POSTPONE BEGIN ; IMMEDIATE
: ?DO ['] 2DUP COMPILE, ['] <> COMPILE, POSTPONE IF ['] DODO COMPILE, POSTPONE BEGIN ; IMMEDIATE

: UNLOOP R> 2R> 2DROP >R ;

( According to the standard, this should actually terminate any time we cross
  the line between END-1 and END. This is probably good enough for us. )
: DO+LOOP R> R> ROT + R@ OVER >R >= SWAP >R ;
: +LOOP ['] DO+LOOP COMPILE, POSTPONE UNTIL ['] UNLOOP COMPILE, POSTPONE ELSE ['] 2DROP COMPILE, POSTPONE THEN ; IMMEDIATE
: LOOP 1 COMPILE-LIT POSTPONE +LOOP ; IMMEDIATE

: I R> R@ SWAP >R ;

: CR S" 
" TYPE ;

: ." POSTPONE S" ['] TYPE COMPILE, ; IMMEDIATE LABEL _TYPE_SLIT

: ABORT" POSTPONE IF
         POSTPONE S"
         ['] TYPE COMPILE,
         ['] CR COMPILE,
         ['] ABORT COMPILE,
         POSTPONE THEN ; IMMEDIATE LABEL _ABORT_S

: CHAR+ 1 CHARS + ;
: CELL+ 1 CELLS + ;
: ADDR+ 1 ADDRS + ;

\ Create a variable in low RAM bank (but definition in the current code bank).
: CREATELOWRAM BANK@ LOWRAM BANK! HERE SWAP BANK! CONSTANT ;

\ Masks the data and updates the value at address so that only the mask bytes
\ are modified.
: MASK! ( data mask address -- )
  >R >R
  R@ AND
  R> INVERT R@ @ AND OR
  R> !
;

( addr length -- end begin )
: EACH OVER + SWAP ;

( addend addr -- )
: +!
  TUCK @ +
  SWAP !
;

( &c1 &c2 -- )
\ Swaps the characters at the given addrs.
: CSWAP!
  OVER C@ OVER C@ SWAP
  ROT C!
  SWAP C!
;

( y1 x1 y2 x2 -- y1+y2 x1+x2 )
: 2+2
  ROT + -ROT + SWAP
;

( addr bytes -- )
: ZERO-FILL
  EACH DO
    0 I C!
  LOOP
;

