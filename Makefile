all: snes-forth.smc

snes-forth.smc: snes-forth.o lorom128.cfg
	ld65 -C lorom128.cfg -o snes-forth.smc snes-forth.o

snes-forth.o: snes-forth.s forth.s preamble.s
	ca65 $< -g -o $@

forth.s: forth.fth snes-forth.lua
	./snes-forth.lua $< $@

clean:
	rm snes-forth.smc snes-forth.o forth.s
