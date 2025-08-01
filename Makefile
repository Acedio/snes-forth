all: snes-forth.smc snes-forth.mlb

%.smc %.labels %.dbg: %.o init.o lorom128.cfg
	ld65 -C lorom128.cfg -Ln $*.labels --dbgfile $*.dbg -o $*.smc $*.o init.o

%.o: %.s preamble.s
	ca65 $< -g -o $@

# A list of labels for use with Mesen.
%.mlb: %.labels
	< $< awk 'BEGIN {IFS=" "} {printf("SnesPrgRom:%x:%s\n", strtonum("0x" $$2) - 0x8000, substr($$3,2));}' > $@

%.s: %.fth snes-forth.lua
	./snes-forth.lua $*.fth $@

snes-forth.fth: std.fth main.fth 
	# Does $^ preserve order?
	cat $^ > $@

all-tests.fth: std.fth tests/tests.fth
	cat $^ > $@

tests: all-tests.smc all-tests.mlb
	./snes-forth.lua -v all-tests.fth all-tests.s

clean:
	rm snes-forth.smc snes-forth.o forth.fth forth.s all-tests.fth all-tests.s snes-forth.mlb snes-forth.labels snes-forth.dbg
