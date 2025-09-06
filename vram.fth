( from from-page bytes to -- )
: DMA-VRAM-LONG-TRANSFER
  \ Set up VRAM reg.
  \ Increment after writing high byte
  0x80 0x2115 C!
  \ Which word-indexed entry to transfer to.
  0x2116 !

  \ Number of copies (bytes)
  0x4305 !
  \ Page
  0x4304 C!
  \ Transfer from
  0x4302 !
  \ Copy to addr (2118), then addr+1 (2119).
  0x1 0x4300 C!
  \ Copy to VRAM reg
  0x18 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

\ Assumes page 0.
( from bytes to -- )
: DMA0-VRAM-TRANSFER
  0 -ROT DMA-VRAM-LONG-TRANSFER
;

32 2* 2* 2* 2* 2* CONSTANT BGTILEMAP-TILE-COUNT

: BGTILEMAP-ENTRIES
  CELLS
;

( tilemap-addr -- )
: ZERO-BGTILEMAP
  BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES ZERO-FILL
;

\ Set up shadow registers.
BANK@
LOWRAM BANK!
\ BG12NBA/BG34NBA 0x210B
CREATE BG-BASE-ADDRESSES 1 CELLS ALLOT
\ BGMODE 0x2105 
CREATE BG-MODE 1 CHARS ALLOT
CREATE BG-LAYER-ENABLE 1 CHARS ALLOT
BANK!

: COPY-BASE-REGISTERS
  BG-BASE-ADDRESSES @ 0x210B !
  BG-MODE @ 0x2105 C!
  BG-LAYER-ENABLE @ 0x212C C!
;

BANK@
LOWRAM BANK!
CREATE BG1-SHADOW-TILEMAP BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES ALLOT
CREATE BG3-SHADOW-TILEMAP BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES ALLOT
BANK!

: TILEMAP-XY
  32 PPU-MULT DROP + ;

( tiles -- bytes )
: 2BIT-8X8-TILES
  16*
;

( tiles -- bytes )
: 4BIT-16X16-TILES
  [ 16 16 * 2/ COMPILE-LIT ] PPU-MULT DROP
;

( shadow-tilemap &vram -- )
\ vram address is word-indexed.
: COPY-BG-TO-VRAM
  BGTILEMAP-TILE-COUNT BGTILEMAP-ENTRIES SWAP
  DMA0-VRAM-TRANSFER
;
