all: nes-forth.nes nes-forth.fdb

nes-forth.nes: ines_header.bin nes-forth.bin smb.chr
	cat $^ > $@

nes-forth.bin nes-forth.labels: nes-forth.o link.cfg
	ld65 -C link.cfg -Ln nes-forth.labels -o nes-forth.bin nes-forth.o

nes-forth.o: nes-forth.s
	ca65 $< -g -o $@

# A list of labels for use with FCEUX's Bookmark feature.
nes-forth.fdb: nes-forth.labels
	< $< awk 'BEGIN {IFS=" "} {printf("Bookmark: addr=%s  desc=\"%s\"\n", substr($$2,3,6), $$3);}' > $@

ines_header.bin: ines_header.hex
	xxd -r -p $< > $@

clean:
	rm nes-forth.nes nes-forth.bin nes-forth.labels nes-forth.o nes-forth.fdb ines_header.bin
