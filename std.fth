: ' WORD FIND DROP ; LABEL _TICK
: POSTPONE ' COMPILE, ; IMMEDIATE

: ['] ' COMPILE-LIT ; IMMEDIATE LABEL _BRACKET_TICK

: IF ['] BRANCH0 COMPILE, HERE 0 , ; IMMEDIATE
: THEN DUP >R HERE SWAP ADDRESS-OFFSET R> ! ; IMMEDIATE
: ELSE ['] BRANCH COMPILE, HERE 0 , SWAP POSTPONE THEN ; IMMEDIATE

: BEGIN HERE ; IMMEDIATE
: UNTIL ['] BRANCH0 COMPILE, HERE ADDRESS-OFFSET , ; IMMEDIATE

: [CHAR] KEY DROP KEY COMPILE-LIT ; IMMEDIATE

: ( BEGIN KEY [CHAR] ) = UNTIL ; IMMEDIATE LABEL _L_PAREN

( *big breath of air* Whew, can finally comment now! )

( I feel like the way I'm grabbing a CR char here probably isn't portable. )
: \ BEGIN KEY [CHAR] 
= UNTIL ; IMMEDIATE LABEL _BACKSLASH

\ Stack manipulation stuff.
: NIP SWAP DROP ;
: OVER >R DUP R> SWAP ;
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
: REPEAT ['] BRANCH COMPILE, HERE ADDRESS-OFFSET , POSTPONE THEN ; IMMEDIATE

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

\ Push control vars onto the return stack.
( TO FROM -- r: TO FROM )
: DODO R> -ROT 2>R >R ;
: DO ['] DODO COMPILE, POSTPONE BEGIN ; IMMEDIATE

: UNLOOP R> 2R> 2DROP >R ;

( According to the standard, this should actually terminate any time we cross
  the line between END-1 and END. This is probably good enough for us. )
: DO+LOOP R> R> ROT + R@ OVER >R >= SWAP >R ;
: +LOOP ['] DO+LOOP COMPILE, POSTPONE UNTIL ['] UNLOOP COMPILE, ; IMMEDIATE
: LOOP 1 COMPILE-LIT POSTPONE +LOOP ; IMMEDIATE

: I R> R@ SWAP >R ;

: CR S" 
" TYPE ;

: ." POSTPONE S" ['] TYPE COMPILE, ; IMMEDIATE LABEL _TYPE_SLIT

: ABORT" POSTPONE IF
         POSTPONE S"
         ['] TYPE COMPILE,
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
