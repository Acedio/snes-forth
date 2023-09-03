PPUCTRL = $2000
PPUMASK = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR = $2006
PPUDATA = $2007

TIH = $00
TIL = $01

; * = $C000
.CODE
reset:
  sei            ; Ignore IRQs.
  cld            ; Disable decimal mode.
  ldx #$ff
  txs            ; Set up the stack.

  bit PPUSTATUS  ; clear the VBL flag if it was set at reset time
vwait1:
  bit PPUSTATUS
  bpl vwait1     ; at this point, about 27384 cycles have passed

  ; Clear RAM.
  lda #$00
  ldx #$00
  clear_ram_loop:
    sta $0000,X
    sta $0100,X
    sta $0200,X
    sta $0300,X
    sta $0400,X
    sta $0500,X
    sta $0600,X
    sta $0700,X
    inx
    bne clear_ram_loop

vwait2:
  bit PPUSTATUS
  bpl vwait2     ; at this point, about 57165 cycles have passed

  lda #$01       ; Play a sound
  sta $4015
  lda #$1F
  sta $4000
  lda #253
  sta $4002
  lda #$08
  sta $4003

  ; Set initial tile index to $2000
  lda #$20
  sta TIH
  lda #$00
  sta TIL

  ; enable NMI for PPU VBlank
  lda #$80
  sta PPUCTRL

loop:
  jmp loop

nmi:
  pha
  txa
  pha
  tya
  pha

  lda #$0A
  sta PPUMASK

  ; Start modifying the nametable at the current table index
  lda PPUSTATUS  ; First reset the latch on PPUADDR
  lda TIH
  sta PPUADDR
  lda TIL
  sta PPUADDR

  ; Populate a few rows of the nametable
  ldx #$00
write_nametable_loop:
  stx PPUDATA
  inx
  cpx #$20
  bne write_nametable_loop
  ; Increment the tile index by #$40
  clc
  lda TIL
  adc #$20
  sta TIL
  lda TIH
  adc #$00
  ; Reset the high byte if we've overflowed
  cmp #$24
  bne skip_reset
  lda #$20
skip_reset:
  sta TIH

  ; Write attribute table.
  ldx #$23
  stx PPUADDR
  ldx #$C0
  stx PPUADDR
  lda #$00
write_attribute:
  sta PPUDATA
  inx
  bne write_attribute

  ; Write BG color
  lda #$3F
  sta PPUADDR
  lda #$00
  sta PPUADDR
  lda #$0f
  sta PPUDATA
  lda #$05
  sta PPUDATA
  lda #$28
  sta PPUDATA
  lda #$08
  sta PPUDATA

  ; Reset the scrolling.
  lda PPUSTATUS
  lda #$00
  sta PPUSCROLL
  sta PPUSCROLL
  lda #$88
  sta PPUCTRL

  ; Return registers to their stored version.
  pla
  tay
  pla
  tax
  pla
  rti

irq:
  rti

.SEGMENT "INTERRUPTS"
.word nmi, reset, irq
