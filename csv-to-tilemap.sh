#!/usr/bin/bash

cat <<FORTH
CODE $1-MAP
  dex
  dex
  lda #.LOWORD($1_MAP_DATA)
  sta z:1, X
  rts

.pushseg
.segment "$4"

$1_MAP_DATA:

$(< $2 awk -f csv-to-tiles.awk -v palette=$3 )

$1_MAP_DATA_END:

.popseg

END-CODE

CODE $1-MAP-BYTES
  dex
  dex
  lda #($1_MAP_DATA_END - $1_MAP_DATA)
  sta z:1, X
  rts
END-CODE

CODE $1-BANK
  dex
  dex
  lda #.BANKBYTE($1_MAP_DATA)
  sta z:1, X
  rts
END-CODE

FORTH
