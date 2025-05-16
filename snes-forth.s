.p816
.i16
.a8

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

reset:
  clc  ; native mode
  xce
  rep #$10  ; X/Y 16-bit
  sep #$20  ; A 8-bit
  ; Clear PPU registers
  ldx #$33
@loop:  stz $2100,x
  stz $4200,x
  dex
  bpl @loop

  ; Set background color to $03E0
  lda #$1F
  sta $2122
  lda #$3C
  sta $2122

  ; Maximum screen brightness
  lda #$0F
  sta $2100

forever:
  jmp forever
