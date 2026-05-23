BUILD=build

all: tests

build:
	mkdir -p build

$(BUILD)/%.smc $(BUILD)/%.labels $(BUILD)/%.dbg: $(BUILD)/%.o $(BUILD)/init.o lorom128.cfg | build
	ld65 -C lorom128.cfg -Ln $(BUILD)/$*.labels --dbgfile $(BUILD)/$*.dbg -o $(BUILD)/$*.smc $(BUILD)/$*.o $(BUILD)/init.o

$(BUILD)/%.o: $(BUILD)/%.out.s $(BUILD)/preamble.inc | build
	ca65 $< -g -o $@

$(BUILD)/init.o: init.s $(BUILD)/preamble.inc | build
	ca65 $< -g -o $@

# A list of labels for use with Mesen.
$(BUILD)/%.mlb: $(BUILD)/%.labels | build
	< $< awk 'BEGIN {IFS=" "} {printf("SnesPrgRom:%x:%s\n", strtonum("0x" $$2) - 0x8000, substr($$3,2));}' > $@

.PRECIOUS: $(BUILD)/%.out.s
$(BUILD)/%.out.s: %.fth snes-forth.lua | build
	./snes-forth.lua $< $@

$(BUILD)/%.out.s: tests/%.fth snes-forth.lua tests/test-util.fth tests/snes-test-util.fth | build 
	./snes-forth.lua $< $@

snes-forth.lua: bytestack.lua  cellstack.lua  dataspace.lua  dictionary.lua  input.lua

tests: $(BUILD)/tests.smc $(BUILD)/tests.mlb

JUSTCOPY=preamble.inc
$(foreach file,$(JUSTCOPY),$(BUILD)/$(file)): $(JUSTCOPY)
	cp $(JUSTCOPY) $(BUILD)

clean:
	$(RM) *.smc *.labels *.dbg *.o *.mlb *.out.s *.out.fth dataspace.dump
	$(RM) -r $(BUILD)
