BUILD=build
ASSETS=assets

all: $(BUILD)/game.smc $(BUILD)/game.mlb

build:
	mkdir -p build

$(BUILD)/%.smc $(BUILD)/%.labels $(BUILD)/%.dbg: $(BUILD)/%.o $(BUILD)/init.o lorom128.cfg $(BUILD)/tad-audio.o $(BUILD)/audio.o | build
# audio.o should come first to ensure that it gets precedence in its bank.
	ld65 -C lorom128.cfg -Ln $(BUILD)/$*.labels --dbgfile $(BUILD)/$*.dbg -o $(BUILD)/$*.smc $(BUILD)/audio.o $(BUILD)/$*.o $(BUILD)/init.o $(BUILD)/tad-audio.o

$(BUILD)/tad-audio.o: tad-audio.s | build
	ca65 $< -g -o $@ -DLOROM

$(BUILD)/audio.o: $(BUILD)/audio.s | build
	ca65 $< -g -o $@ -DLOROM

$(BUILD)/%.o: $(BUILD)/%.out.s $(BUILD)/preamble.inc | build
	ca65 $< -g -o $@

$(BUILD)/init.o: init.s $(BUILD)/preamble.inc | build
	ca65 $< -g -o $@

# A list of labels for use with Mesen.
$(BUILD)/%.mlb: $(BUILD)/%.labels | build
	< $< awk 'BEGIN {IFS=" "} {printf("SnesPrgRom:%x:%s\n", strtonum("0x" $$2) - 0x8000, substr($$3,2));}' > $@

.PRECIOUS: $(BUILD)/%.out.s
$(BUILD)/%.out.s: %.fth forth/snes-forth.lua | build
	LUA_PATH=forth/?.lua forth/snes-forth.lua $< $@

forth/snes-forth.lua: forth/bytestack.lua  forth/cellstack.lua  forth/dataspace.lua  forth/dictionary.lua  forth/input.lua

tests.fth: std.fth snes-std.fth tests/test-util.fth tests/tests.fth

4BTILES=maptiles sprites stars title
4BTILES_FTH=$(foreach name,$(4BTILES),$(BUILD)/$(name).tiles.fth)
2BTILES=farstars
2BTILES_FTH=$(foreach name,$(2BTILES),$(BUILD)/$(name).tiles2b.fth)
MAPS=starfield.p2 farstars.p1 title.p1
MAPS_FTH=$(foreach name,$(MAPS),$(BUILD)/$(name).map.fth)

game.fth: std.fth snes-std.fth joypad.fth sin-lut.fth oam.fth vram.fth cgram.fth wram.fth $(4BTILES_FTH) $(2BTILES_FTH) $(MAPS_FTH) font.fth audio.fth stars.fth steps.fth level-data.fth levels.fth level.fth title.fth end.fth

tests: $(BUILD)/tests.smc $(BUILD)/tests.mlb
	echo tests

$(ASSETS)/farstars.png: $(ASSETS)/stars.png
	cp $< $@

$(ASSETS)/audio.terrificaudio: $(ASSETS)/song.mml $(ASSETS)/FM_Harp.brr $(ASSETS)/sound_effects.txt

$(BUILD)/audio.s $(BUILD)/audio.bin: $(ASSETS)/audio.terrificaudio | build
	tad-compiler ca65-export $< --output-asm $(BUILD)/audio.s --output-bin $(BUILD)/audio.bin --segment BANK1 --lorom

$(BUILD)/audio.inc: $(ASSETS)/audio.terrificaudio | build
	tad-compiler ca65-enums $< --output $@

audio.fth: $(BUILD)/tad-audio.inc $(BUILD)/audio.inc

JUSTCOPY=tad-audio.inc preamble.inc
$(foreach file,$(JUSTCOPY),$(BUILD)/$(file)): $(JUSTCOPY)
	cp $(JUSTCOPY) $(BUILD)

$(BUILD)/%.tiles.pal.out $(BUILD)/%.tiles.tiles.out: $(ASSETS)/%.png | build
	superfamiconv -i $^ -p $(BUILD)/$*.tiles.pal.out -t $(BUILD)/$*.tiles.tiles.out -S

$(BUILD)/%.tiles.fth: $(BUILD)/%.tiles.pal.out $(BUILD)/%.tiles.tiles.out | build
	./tiles-to-forth.lua $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $^ BANK2 > $@

$(BUILD)/%.tiles2b.pal.out $(BUILD)/%.tiles2b.tiles.out: $(ASSETS)/%.png | build
	superfamiconv -i $^ -p $(BUILD)/$*.tiles2b.pal.out -t $(BUILD)/$*.tiles2b.tiles.out -S -B 2

$(BUILD)/%.tiles2b.fth: $(BUILD)/%.tiles2b.pal.out $(BUILD)/%.tiles2b.tiles.out | build
	./tiles-to-forth.lua $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $^ BANK1 > $@

$(BUILD)/%.map.csv: $(ASSETS)/%.tmx | build
	xvfb-run -a tiled --export-map csv $< $@

# These have .pX in their filename to indicate which palette they use.
# TODO: This kind of configuration shouldn't be in the makefile :P
$(BUILD)/%.p0.map.fth: $(BUILD)/%.map.csv | build
	./csv-to-tilemap.sh $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $< 0 BANK1 > $@

$(BUILD)/%.p1.map.fth: $(BUILD)/%.map.csv | build
	./csv-to-tilemap.sh $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $< 1024 BANK1 > $@

$(BUILD)/%.p2.map.fth: $(BUILD)/%.map.csv | build
	./csv-to-tilemap.sh $(shell echo '$*' | tr '[:lower:]' '[:upper:]') $< 2048 BANK1 > $@

clean:
	$(RM) *.smc *.labels *.dbg *.o *.mlb *.out.s *.out.fth dataspace.dump *.pal.out *.tiles.out *.tiles.fth *.tiles2b.fth *.sprites.fth audio.inc audio.bin audio.s *.map.csv *.map.fth
	$(RM) -r $(BUILD)
