: <STATES 0 ;
: STATE: DUP CONSTANT 1+ ;
: STATES>COUNT: CONSTANT ;

( #states -- &state-list )
: <STATE-MACHINE CREATE HERE SWAP CELLS ALLOT DOES> OVER @ CELLS + @ EXECUTE ;

\ When the state behavior is called, will push the state address so it can be
\ modified.
( &state-list state -- &state-list )
: STATE-BEHAVIOR: CELLS OVER + :NONAME SWAP ! ;

( &state-list -- )
: STATE-MACHINE> DROP ;

: STATE! SWAP ! ;

