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

.segment "CODE"

RETURN_STACK_ADDR := $01FF
DATA_STACK_ADDR := $02FF

.include "preamble.s"
.include "forth.s"

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

  sep #$20
  .a8
  ; Set background color to $03E0
  lda #$1F
  sta $2122
  lda #$3C
  sta $2122
  ; sta z:$12

  ; Maximum screen brightness
  lda #$0F
  sta $2100
  rep #$20
  .a16

  ldx #RETURN_STACK_ADDR
  txs
  ldx #DATA_STACK_ADDR

  jsl _MAIN

forever:
  jmp forever

not_implemented:
  jmp not_implemented
