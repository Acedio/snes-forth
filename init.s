.p816
.i16
.a16

.segment "HEADERNAME"
  .byte "SNES TEST"

.segment "ROMINFO"
  .byte $30         ; Fast LoROM
  .byte 0           ; ROM-only cart
  .byte $07         ; 128K ROM
  .byte 0,0,0,0     ; No RAM, Japan, Homebrew, Version 0
  .word $FFFF,$0000 ; dummy checksums

.segment "VECTORS"
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,reset,0

.segment "UNSIZED"

.include "preamble.s"

reset:
  clc  ; native mode
  xce
  rep #$30  ; A/X/Y 16-bit
  ; Clear PPU registers
  ldx #$33
@loop:  stz $2100,x
  stz $4200,x
  dex
  bpl @loop

  ldx #RETURN_STACK_ADDR
  txs
  ldx #DATA_STACK_ADDR

.import _MAIN
  jsr _MAIN

forever:
  jmp forever

.export not_implemented
not_implemented:
  jmp not_implemented
