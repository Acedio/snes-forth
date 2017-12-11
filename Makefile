nes-forth.nes: nes-forth.no_chr smb.chr
	cat $^ > $@

nes-forth.no_chr: nes-forth.s
	xa $< -o $@
