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

%.out.s: %.out.fth snes-forth.lua
	./snes-forth.lua $< $@

snes-forth.lua: bytestack.lua  cellstack.lua  dataspace.lua  dictionary.lua  input.lua

tests.out.fth: std.fth snes-std.fth tests/tests.fth
	cat $^ > $@

game.out.fth: std.fth snes-std.fth cat.sprite.fth font.fth game.fth 
	cat $^ > $@

tests: tests.smc tests.mlb
	echo tests

%.pal.out %.tiles.out %.map.out: %.png
	superfamiconv -i $^ -p $*.pal.out -t $*.tiles.out -m $*.map.out -S

%.sprite.fth: %.pal.out %.tiles.out %.map.out
	./tiles-to-forth.lua $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $^ > $@

clean:
	rm *.smc *.labels *.dbg *.o *.mlb *.out.s *.out.fth dataspace.dump *.pal.out *.tiles.out *.map.out *.sprite.fth
