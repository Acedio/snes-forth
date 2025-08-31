all: game.smc game.mlb

%.smc %.labels %.dbg: %.o init.o lorom128.cfg
	ld65 -C lorom128.cfg -Ln $*.labels --dbgfile $*.dbg -o $*.smc $*.o init.o

%.o: %.out.s preamble.s
	ca65 $< -g -o $@

%.o: %.s preamble.s
	ca65 $< -g -o $@

# A list of labels for use with Mesen.
%.mlb: %.labels
	< $< awk 'BEGIN {IFS=" "} {printf("SnesPrgRom:%x:%s\n", strtonum("0x" $$2) - 0x8000, substr($$3,2));}' > $@

.PRECIOUS: %.out.s
%.out.s: %.out.fth snes-forth.lua
	./snes-forth.lua $< $@

snes-forth.lua: bytestack.lua  cellstack.lua  dataspace.lua  dictionary.lua  input.lua

tests.out.fth: std.fth snes-std.fth tests/tests.fth
	cat $^ > $@

game.out.fth: std.fth snes-std.fth joypad.fth sin-lut.fth oam.fth maptiles.tiles.fth sprites.sprites.fth font.fth game.fth 
	cat $^ > $@

tests: tests.smc tests.mlb
	echo tests

%.sprites.pal.out %.sprites.tiles.out %.sprites.map.out: %.png
	superfamiconv -i $^ -p $*.sprites.pal.out -t $*.sprites.tiles.out -m $*.sprites.map.out -S -W 8 -H 8 -B 4 --no-discard --no-flip --color-zero FF00FF

# TODO: Do sprites and tiles actually need to be separated?
%.tiles.pal.out %.tiles.tiles.out %.tiles.map.out: %.png
	superfamiconv -i $^ -p $*.tiles.pal.out -t $*.tiles.tiles.out -m $*.tiles.map.out -S -W 8 -H 8 -B 4 --no-discard --no-flip --color-zero FF00FF

%.tiles.fth: %.tiles.pal.out %.tiles.tiles.out %.tiles.map.out
	./tiles-to-forth.lua $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $^ > $@

%.sprites.fth: %.sprites.pal.out %.sprites.tiles.out %.sprites.map.out
	./tiles-to-forth.lua $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $^ > $@

clean:
	rm *.smc *.labels *.dbg *.o *.mlb *.out.s *.out.fth dataspace.dump *.pal.out *.tiles.out *.map.out *.tiles.fth *.sprites.fth
