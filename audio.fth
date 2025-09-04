CODE __AUDIO-IMPORTS
  rts
  .include "tad-audio.inc"
  .include "audio.inc"
END-CODE

CODE AUDIO-INIT
  phx
  A8
  jsl Tad_Init
  A16
  plx
  rts
END-CODE

\ Once per frame.
CODE AUDIO-UPDATE
  phx
  A8
  jsl Tad_Process
  A16
  plx
  rts
END-CODE

CODE AUDIO-PLAY-SONG
  phx
  A8
  lda #1
  jsr Tad_LoadSong
  A16
  plx
  rts
END-CODE
