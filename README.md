# snes-forth

A Forth written for the Super Nintendo's 65C816! Created as a part of [SNESDEV
2025](https://itch.io/jam/snesdev-2025).

For an example game created with snes-forth, check out [Super
Sokonyan](https://github.com/Acedio/super-sokonyan).

## Implementation

snes-forth is a subroutine-threaded Forth written in Lua. The host system
executes Forth and compiles to 65C816 assembly for the target. `ca65` can then
be used to assemble binaries for the SNES.

More details later! 🚧
