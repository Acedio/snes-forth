.byt "NES",$1A
.byt $01, $01, $00, $00
.byt $00, $10, $00, $00
.byt $00, $00, $00, $00

PPUCTRL = $2000
PPUMASK = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR = $2006
PPUDATA = $2007

* = $C000
reset:
nmi:
irq:
  sei            ; Ignore IRQs.
  cld            ; Disable decimal mode.
  ldx #$ff
  txs            ; Set up the stack.

  bit PPUSTATUS  ; clear the VBL flag if it was set at reset time
vwait1:
  bit PPUSTATUS
  bpl vwait1     ; at this point, about 27384 cycles have passed
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

  lda #$00
  sta PPUCTRL
  lda #$0A
  sta PPUMASK

  ; Set up the nametable at $2000
  lda #$20
  sta PPUADDR
  lda #$00
  sta PPUADDR

  ; Loop 4 times
  IDX = $00
  lda #$04
  sta IDX
  ldx #$00
write_nametable:
  stx PPUDATA
  inx
  bne write_nametable
  dec IDX
  bne write_nametable

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
  lda #$01
  sta PPUDATA
  lda #$03
  sta PPUDATA
  lda #$06
  sta PPUDATA
  lda #$09
  sta PPUDATA

  ; Reset the scrolling.
  lda #$00
  sta PPUSCROLL
  sta PPUSCROLL

loop:
  jmp loop
  rti
end:
* = $fffa
.dsb * - end, $55
.word nmi, reset, irq
