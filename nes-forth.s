.byt "NES",$1A
.byt $1, $0, $0, $0
.byt $0, $10, $0, $0
.byt $0, $0, $0, $0

* = $C000
reset:
nmi:
irq:
  lda #$01
  sta $4015
  lda #$1F
  sta $4000
  lda #253
  sta $4002
  lda #$08
  sta $4003
loop:
  jmp loop
  rti
end:
* = $fffa
.dsb * - end, $55
.word nmi, reset, irq
