REQUIRE std.fth

( 16b-op 8b-op -- 16b-lsb 8b-msb )
: PPU-MULT
  0x211C C!
  DUP 0x211B C!
  HIBYTE 0x211B C!
  0x2134 @
  0x2136 C@
;

CODE BREAKPOINT
  ; Mesen will break on this failed assert.
  ; assert(0)
  rts
END-CODE

CODE NMI-ENABLE
  ; Enable NMI and automatic controller reading.
  A8
  lda #$81
  sta $4200
  A16
  rts
END-CODE

CODE NMI-WAIT
  wai
  rts
END-CODE

: 16* 2* 2* 2* 2* ;
