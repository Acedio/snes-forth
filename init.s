.p816
.i16
.a16

.segment "HEADERNAME"
  .byte "SUPER SOKONYAN"

.segment "ROMINFO"
  .byte $30         ; Fast LoROM
  .byte 0           ; ROM-only cart
  .byte $07         ; 128K ROM
  .byte 0,0,0,0     ; No RAM, Japan, Homebrew, Version 0
  .word $FFFF,$0000 ; dummy checksums

.segment "VECTORS"
  .addr 0,0,0,0,0,nmi,0,0
  .addr 0,0,0,0,0,0,reset,0

.segment "UNSIZED"

.include "preamble.inc"

reset:
  clc  ; native mode
  xce
  rep #$30  ; A/X/Y 16-bit
  ; We'll start in the 0th bank, but doing a long jump to `fastrom` (which ld65
  ; will put into the $80th bank, fast rom) will switch us.
  jml fastrom
fastrom:
  ; Clear PPU registers
  ldx #$33
@loop:  stz $2100,x
  stz $4200,x
  dex
  bpl @loop
  lda #$8F
  sta $4100

  ldx #RETURN_STACK_ADDR
  txs
  ldx #DATA_STACK_ADDR

  ; Set Data Bank to the current (fast) Program Bank.
  phk
  plb

.import _SNES_MAIN
  jsr _SNES_MAIN

forever:
  jmp forever

.export not_implemented
not_implemented:
  jmp not_implemented

nmi:
  jml nmiFast
nmiFast:
; Thanks to Oziphantom (https://www.youtube.com/watch?v=rPcwGeX_hLs) for the NMI overview :)

; = Save registers =
; First save the data page and set it to the current code page (so we know that
; $4210 is indeed the ACK register).
  phb
  phk
  plb
; ACK NMI
  A8
  bit $4210

; Make sure we save all 16 bits of each register.
  A16
  pha
  phx
  phy
  phd

; Set direct page to 0 (Forth expects no offset).
  lda #0000
  tcd

; Call Forth NMI handler.
.import _SNES_NMI
  jsr _SNES_NMI

; Restore registers.
  A16
  pld
  ply
  plx
  pla
  plb
  rti
