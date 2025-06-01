PPUCTRL = $2000
PPUMASK = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR = $2006
PPUDATA = $2007

; The bottom of the paramter and return stacks.
PSLOC = $0100
RSLOC = $0200

.ZEROPAGE
TIL = $00
TIH = $01
; Stores the address of the next word to execute.
IPL = $02
IPH = $03
; Return stack pointer (occupies the $0200 block and grows down)
RSP = $04
; Stores the instruction for an indirect JMP ($6C)
WJMP:
  jmp $beef  ; Garbage at first.
; Stores the address of the codeword of the next word to execute.
WL = $06
WH = $07
TMPL = $08
TMPH = $09

.CODE
NEXT:
  ; Pulled from FIG-FORTH :) Self-modifying code!
  ; IP is already pointing to the _next_ instruction to be executed
  ; W = *IP and then increment IP
  ldy #01
  lda (IPL),Y
  sta WH
  dey ; Can we just remove this and then lda (IPH),Y above instead?
  lda (IPL),Y
  sta WL
  clc
  lda IPL
  adc #02
  sta IPL
  bcc @nocarry
  inc IPH
@nocarry:
  ; W contains the address of the codeword of the next word, so doing an
  ; indirect jump here will start executing the codeword (e.g. DOCOL or
  ; whatever).
  jmp WJMP

DOCOL:
  ; Push IP onto the return stack
  lda IPH
  ldy RSP ; index with Y because NEXT will clobber it anyway
  sta RSLOC,Y
  dey
  lda IPL
  sta RSLOC,Y
  dey
  sty RSP

  ; set IP = W + 2, then NEXT.
  clc
  lda WL
  adc #02
  sta IPL
  lda WH
  adc #00
  sta IPH

  jmp NEXT

.macro defcode name
.ident(name):
  .addr .ident(.concat(name, "_ASM"))
.ident(.concat(name, "_ASM")):
.endmacro

.macro defword name
.ident(name):
  .addr DOCOL
.endmacro

defcode "EXIT"
  ; Pop the return stack into IP, then NEXT.
  ldy RSP
  iny
  lda RSLOC,Y
  sta IPL
  iny
  lda RSLOC,Y
  sta IPH
  sty RSP

  jmp NEXT

defcode "LIT"
  ldy #01
  lda (IPL),Y
  pha
  dey
  lda (IPL),Y
  pha
  lda IPL
  adc #02
  sta IPL
  bcc @nocarry
  inc IPH
@nocarry:
  jmp NEXT

defcode "DROP"
  pla ; 4
  pla ; 4
  jmp NEXT

defcode "SWAP"
  ; 46 Cycles, slightly faster than pop * 4 push * 4
  tsx ; 2
  lda PSLOC+2,X ; 4
  tay           ; 2
  lda PSLOC+4,X ; 4
  sta PSLOC+2,X ; 5
  tya           ; 2
  sta PSLOC+4,X ; 5

  lda PSLOC+1,X ; 4
  tay           ; 2
  lda PSLOC+3,X ; 4
  sta PSLOC+1,X ; 5
  tya           ; 2
  sta PSLOC+3,X ; 5
  jmp NEXT

defcode "DUP"
  tsx
  ; Can grab certain elements of the stack by adding to the stack base.
  lda PSLOC+2,X
  pha
  lda PSLOC+1,X
  pha
  jmp NEXT

defcode "OVER"
  tsx
  lda PSLOC+4,X
  pha
  lda PSLOC+3,X
  pha
  jmp NEXT

defcode "ROT"
  tsx
  lda PSLOC+6,X
  sta TMPH
  lda PSLOC+4,X
  sta PSLOC+6,X
  lda PSLOC+2,X
  sta PSLOC+4,X
  lda TMPH
  sta PSLOC+2,X
  ; Could shrink code size here by decreasing X and looping once.
  lda PSLOC+5,X
  sta TMPL
  lda PSLOC+3,X
  sta PSLOC+5,X
  lda PSLOC+1,X
  sta PSLOC+3,X
  lda TMPL
  sta PSLOC+1,X
  jmp NEXT

defword "NROT"  ; -ROT
  .addr ROT
  .addr ROT
  .addr EXIT

defword "TWODROP" ; 2DROP
  .addr DROP
  .addr DROP
  .addr EXIT

defcode "ADD"
  clc
  pla
  sta TMPL
  pla
  sta TMPH
  pla
  adc TMPL
  sta TMPL
  pla
  adc TMPH
  pha
  lda TMPL
  pha
  jmp NEXT

defcode "END"
  jmp END  ; Loop forever.

defword "FORTHWORD"
  .addr LIT
  .word 1
  .addr LIT
  .word 2
  .addr LIT
  .word 3
  .addr NROT
  .addr EXIT

FORTH_MAIN:
  .addr FORTHWORD
  .addr END

reset:
  sei            ; Ignore IRQs.
  cld            ; Disable decimal mode.
  ldx #$ff
  txs            ; Set up the stack.
  stx RSP        ; Set up return stack.

  lda #.lobyte(FORTH_MAIN)
  sta IPL
  lda #.hibyte(FORTH_MAIN)
  sta IPH
  jmp NEXT

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
  lda #$2F
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
  adc #$1E
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
