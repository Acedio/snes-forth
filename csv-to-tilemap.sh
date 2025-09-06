#!/usr/bin/bash

cat <<FORTH
CODE $1-MAP
  dex
  dex
  lda #.LOWORD($1_MAP_DATA)
  sta z:1, X
  rts

$1_MAP_DATA:
$(< $2 awk 'BEGIN { FS="," ; OFS=","} {for (i = 1; i <= NF; i++) { $i = or(and($i * 2, 0xF), and($i, 0xF8) * 4) } printf(".WORD "); print ; }')

$1_MAP_DATA_END:
END-CODE

CODE $1-MAP-BYTES
  dex
  dex
  lda #($1_MAP_DATA_END - $1_MAP_DATA)
  sta z:1, X
  rts
END-CODE

FORTH
