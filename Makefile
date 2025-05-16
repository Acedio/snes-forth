all: snes-forth.smc

snes-forth.smc: snes-forth.o lorom128.cfg
	ld65 -C lorom128.cfg -o snes-forth.smc snes-forth.o

snes-forth.o: snes-forth.s
	ca65 $< -g -o $@

clean:
	rm snes-forth.smc snes-forth.o
