all: game.smc game.mlb

%.smc %.labels %.dbg: %.o init.o lorom128.cfg tad-audio.o audio.o
	ld65 -C lorom128.cfg -Ln $*.labels --dbgfile $*.dbg -o $*.smc $*.o init.o tad-audio.o audio.o

tad-audio.o: tad-audio.s
	ca65 $< -g -o $@ -DLOROM

audio.o: audio.s
	ca65 $< -g -o $@ -DLOROM

%.o: %.out.s preamble.s
	ca65 $< -g -o $@

init.o: init.s preamble.s
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

game.out.fth: std.fth snes-std.fth joypad.fth sin-lut.fth oam.fth vram.fth cgram.fth maptiles.tiles.fth sprites.tiles.fth stars.tiles.fth farstars.tiles2b.fth starfield.map.fth farstars.map.fth font.fth audio.fth levels.fth level.fth game.fth 
	cat $^ > $@

tests: tests.smc tests.mlb
	echo tests

farstars.png: stars.png
	cp $< $@

audio.terrificaudio: song.mml FM_Harp.brr sound_effects.txt

audio.s audio.bin: audio.terrificaudio
	tad-compiler ca65-export audio.terrificaudio --output-asm audio.s --output-bin audio.bin --segment BANK1 --lorom

audio.inc: audio.terrificaudio
	tad-compiler ca65-enums audio.terrificaudio --output audio.inc

audio.fth: tad-audio.inc audio.inc

%.tiles.pal.out %.tiles.tiles.out: %.png
	superfamiconv -i $^ -p $*.tiles.pal.out -t $*.tiles.tiles.out -m $*.tiles.map.out -S

%.tiles.fth: %.tiles.pal.out %.tiles.tiles.out
	./tiles-to-forth.lua $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $^ > $@

%.tiles2b.pal.out %.tiles2b.tiles.out: %.png
	superfamiconv -i $^ -p $*.tiles2b.pal.out -t $*.tiles2b.tiles.out -m $*.tiles2b.map.out -S -B 2

%.tiles2b.fth: %.tiles2b.pal.out %.tiles2b.tiles.out
	./tiles-to-forth.lua $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $^ > $@

%.map.csv: %.tmx
	tiled --export-map csv $< $@

%.map.fth: %.map.csv
	./csv-to-tilemap.sh $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $< > $@

clean:
	rm *.smc *.labels *.dbg *.o *.mlb *.out.s *.out.fth dataspace.dump *.pal.out *.tiles.out *.tiles.fth *.tiles2b.fth *.sprites.fth audio.inc audio.bin audio.s *.map.csv *.map.fth
