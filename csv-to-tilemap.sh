#!/usr/bin/bash

cat <<FORTH
CODE $1-MAP
  lda #.LOWORD($1_MAP_DATA)
  PUSH_A
  rts

.pushseg
.segment "$4"

$1_MAP_DATA:

$(< $2 awk -f csv-to-tiles.awk -v palette=$3 )

$1_MAP_DATA_END:

.popseg

END-CODE

CODE $1-MAP-BYTES
  lda #($1_MAP_DATA_END - $1_MAP_DATA)
  PUSH_A
  rts
END-CODE

CODE $1-BANK
  lda #.BANKBYTE($1_MAP_DATA)
  PUSH_A
  rts
END-CODE

FORTH
