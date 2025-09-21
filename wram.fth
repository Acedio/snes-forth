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
  \ Copy to addr (2180) repeatedly.
  0x0 0x4300 C!
  \ Copy to WRAM reg
  0x80 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

