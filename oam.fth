REQUIRE std.fth

128 CONSTANT OAM-OBJECT-COUNT

\ 4 bytes per object
: OAM-LOWER-OBJECTS
  2* 2*
;

: OAM-COORDINATES
  \ Coordinates are the first CELL
;

: OAM-TILE-NUMBER
  2 +
;

: OAM-ATTRIBUTES
  3 +
;

( palette-id -- oam-attributes )
: OAM-PALETTE
  2* 0x0E AND
;

\ 2 bits per object
: OAM-UPPER-OBJECTS
  LSR LSR
;

BANK@
LOWRAM BANK!
CREATE SHADOW-OAM-LOWER OAM-OBJECT-COUNT OAM-LOWER-OBJECTS ALLOT
CREATE SHADOW-OAM-UPPER OAM-OBJECT-COUNT OAM-UPPER-OBJECTS ALLOT
BANK!

: ZERO-OAM
  SHADOW-OAM-LOWER OAM-OBJECT-COUNT OAM-LOWER-OBJECTS +
  SHADOW-OAM-LOWER DO
    -32 I     C! \ X (lower 8 bits)
    -32 I 1 + C! \ Y
      0 I 2 + C! \ Tile no (lower 8 bits)
      0 I 3 + C! \ Attributes
  1 OAM-LOWER-OBJECTS +LOOP

  SHADOW-OAM-UPPER OAM-OBJECT-COUNT OAM-UPPER-OBJECTS +
  SHADOW-OAM-UPPER DO
    0x55 I C!
  LOOP
;

: COPY-OAM
  \ Set OAM address to 0.
  0 0x2102 C!
  0 0x2103 C!

  \ Number of copies (bytes)
  [ OAM-OBJECT-COUNT OAM-LOWER-OBJECTS
    OAM-OBJECT-COUNT OAM-UPPER-OBJECTS +
    COMPILE-LIT ] 0x4305 !
  \ Transfer from shadow OAM
  SHADOW-OAM-LOWER 0x4302 !
  \ Page (TODO: This shouldn't always be 0)
  0 0x4304 C!
  \ Always copy byte-by-byte to the same address.
  0x0 0x4300 C!
  \ Copy to OAM write reg
  0x04 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

( is-set oam-index -- )
: OAM-OBJECT-LARGE!
  >R
  0x02 AND \ Value to set
  0x02     \ Mask
  R@ 0x03 AND \ Find the number of shifts needed
  BEGIN
    DUP 0 <>
  WHILE
    >R
      2* 2* SWAP 2* 2* SWAP
    R> 1-
  REPEAT
  DROP
  \ ( value mask -- )
  SHADOW-OAM-UPPER R> OAM-UPPER-OBJECTS + MASK!
;

( is-set oam-index -- )
: OAM-OBJECT-NEGATIVE-X!
  >R
  0x01 AND \ Value to set
  0x01     \ Mask
  R@ 0x03 AND \ Find the number of shifts needed
  BEGIN
    DUP 0 <>
  WHILE
    >R
      2* 2* SWAP 2* 2* SWAP
    R> 1-
  REPEAT
  DROP
  \ ( value mask -- )
  SHADOW-OAM-UPPER R> OAM-UPPER-OBJECTS + MASK!
;

( y x oam-index -- )
: OAM-OBJECT-COORDS!
  >R
  DUP 0x0100 AND 0<> R@ OAM-OBJECT-NEGATIVE-X!
  0xFF AND SWAP
  SWAPBYTES 0xFF00 AND OR
  SHADOW-OAM-LOWER R> OAM-LOWER-OBJECTS + OAM-COORDINATES !
;
