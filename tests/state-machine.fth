NUM-LEVEL-STATES
<STATE-MACHINE LEVEL-STATE
  LEVEL-INIT STATE-BEHAVIOR:
    \ Level init behavior.
    ." Level init!"
    LEVEL-DONE LEVEL-STATE !
  ;
  LEVEL-DONE STATE-BEHAVIOR:
    ." Level done!"
    \ Other behavior.
    \ Final state so never changes.
  ;
STATE-MACHINE>

\ Init state machine.
LEVEL-INIT LEVEL-STATE !
\ ... later, in the loop
LEVEL-STATE RUN-STATE
LEVEL-STATE RUN-STATE
LEVEL-STATE RUN-STATE
