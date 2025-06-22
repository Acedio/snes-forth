.macro POP_A
  dex
  dex
  lda z:0, X
.endmacro

.macro POP_A
  dex
  dex
  ldy z:0, X
.endmacro

.macro PUSH_A
  sta z:0, X  ; X is the datastack reg
  inx
  inx
.endmacro

.macro PUSH_Y
  sty z:0, X  ; X is the datastack reg
  inx
  inx
.endmacro
