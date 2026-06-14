debug:
	odin build .  -debug -sanitize:address -o:none

release:
	odin build .

run: debug
	.\kolori