: ' WORD FIND DROP ; LABEL _TICK
: POSTPONE ' COMPILE, ; IMMEDIATE

: NIP SWAP DROP ;
: OVER >R DUP R> SWAP ;
: TUCK SWAP OVER ;
: ROT >R SWAP R> SWAP ;
: -ROT ROT ROT ; LABEL _NROT

: 2/ DUP LSR SWAP 0x8000 AND OR ; LABEL _DIV2

: ['] LIT [ ' LIT XT, ] COMPILE, ' XT, ; IMMEDIATE LABEL _BRACKET_TICK

: 0= 0 = ; LABEL _0_EQ
: 0<> 0 <> ; LABEL _0_NE
: 0< 0 < ; LABEL _0_GT
: 0> 0 > ; LABEL _0_LT

: 1- 1 - ; LABEL _DECR

: IF ['] BRANCH0 COMPILE, HERE 0 , ; IMMEDIATE
: THEN DUP >R HERE SWAP ADDRESS-OFFSET R> ! ; IMMEDIATE
: ELSE ['] BRANCH COMPILE, HERE 0 , SWAP POSTPONE THEN ; IMMEDIATE

: BEGIN HERE ; IMMEDIATE
: UNTIL ['] BRANCH0 COMPILE, HERE ADDRESS-OFFSET , ; IMMEDIATE

: WHILE POSTPONE IF SWAP ; IMMEDIATE
: REPEAT ['] BRANCH COMPILE, HERE ADDRESS-OFFSET , POSTPONE THEN ; IMMEDIATE

: CR S" 
" TYPE ;

: ." POSTPONE S" ['] TYPE COMPILE, ; IMMEDIATE LABEL _TYPE_SLIT

: [CHAR] KEY DROP KEY ['] LIT COMPILE, , ; IMMEDIATE

: ( BEGIN KEY [CHAR] ) = UNTIL ; IMMEDIATE LABEL _L_PAREN

( Do comments work now? )

( Seems like it!
  Woohoo! We can finally comment our Forth code! )

( I feel like the way I'm grabbing a CR char here probably isn't portable. )
: \ BEGIN KEY [CHAR] 
= UNTIL ; IMMEDIATE LABEL _BACKSLASH

: ABORT" POSTPONE IF
         POSTPONE S"
         ['] TYPE COMPILE,
         ['] ABORT COMPILE,
         POSTPONE THEN ; IMMEDIATE LABEL _ABORT_S

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

: CHAR+ 1 CHARS + ;
: CELL+ 1 CELLS + ;
: ADDR+ 1 ADDRS + ;

\ Create a variable in low RAM bank (but definition in the current bank).
: CREATELOWRAM BANK@ LOWRAM BANK! HERE SWAP BANK! CONSTANT ;

