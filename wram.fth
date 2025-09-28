\ Byte access to WMDATA
0x2180 CONSTANT WMDATA
0x2181 CONSTANT WMADDR-ADDR
\ Page is either 0 (for the first 64k, page 7E) or 1 (page 7F)
0x2183 CONSTANT WMADDR-PAGE

\ to-page is either 0 (for the first 64k, page 7E) or 1 (page 7F)
( from from-page bytes to to-page -- )
: DMA0-WRAM-LONG-TRANSFER
  \ Set up WRAM reg.
  0x2183 C! \ "page", though it's actually just 1 bit for either 7E or 7F.
  0x2181 !  \ Lower word of addr.

  \ Number of copies (bytes)
  0x4305 !
  \ Page
  0x4304 C!
  \ Transfer from
  0x4302 !
  \ Copy to same addr repeatedly.
  0x0 0x4300 C!
  \ Copy to WRAM reg
  WMDATA 0xFF AND 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

