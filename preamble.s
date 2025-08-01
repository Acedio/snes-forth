.macro POP_A
  lda z:1, X  ; X is the datastack reg
  inx
  inx
.endmacro

.macro POP_Y
  ldy z:1, X
  inx
  inx
.endmacro

.macro PUSH_A
  dex
  dex
  sta z:1, X
.endmacro

.macro PUSH_Y
  dex
  dex
  sty z:1, X
.endmacro

.macro A8
  sep #$20
  .a8
.endmacro

.macro A16
  rep #$20
  .a16
.endmacro

RETURN_STACK_ADDR := $01FF
DATA_STACK_ADDR := $02FF
