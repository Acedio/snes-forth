all: snes-forth.smc snes-forth.mlb

snes-forth.smc snes-forth.labels snes-forth.dbg: snes-forth.o lorom128.cfg
	ld65 -C lorom128.cfg -Ln snes-forth.labels --dbgfile snes-forth.dbg -o snes-forth.smc snes-forth.o

snes-forth.o: snes-forth.s forth.s preamble.s
	ca65 $< -g -o $@

# A list of labels for use with Mesen.
snes-forth.mlb: snes-forth.labels
	< $< awk 'BEGIN {IFS=" "} {printf("SnesPrgRom:%x:%s\n", strtonum("0x" $$2) - 0x8000, substr($$3,2));}' > $@

forth.fth: std.fth main.fth 
	# Does $^ preserve order?
	cat $^ > $@

forth.s: forth.fth snes-forth.lua
	./snes-forth.lua forth.fth $@

all-tests.fth: std.fth tests/tests.fth
	cat $^ > $@

tests: all-tests.fth snes-forth.lua
	./snes-forth.lua -v all-tests.fth all-tests.s

clean:
	rm snes-forth.smc snes-forth.o forth.fth forth.s all-tests.fth all-tests.s snes-forth.mlb snes-forth.labels snes-forth.dbg
