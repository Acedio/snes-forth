0 BANK!

CODE SET-BG
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

  rts
END-CODE

: SET-BG-FORTH
  0x1F 0x2122 C!
  0x3C 0x2122 C!
  0x0F 0x2100 C!
  ;

: MAIN SET-BG ;
