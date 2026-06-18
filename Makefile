FLAGS := -show-timings
DEBUG_FLAGS := -debug -o:none
RELEASE_FLAGS := 
RC :=
RC_FLAGS :=

# Check for Windows_NT environment variable (cmd.exe/PowerShell)
ifeq ($(shell echo %OS% 2>/dev/null),Windows_NT)
    IS_WINDOWS := 1  # Confirmed Windows (cmd.exe/PowerShell)
endif

# Not Windows cmd.exe; check via `uname -s` (Unix-like shells)
UNAME_S := $(shell uname -s 2>/dev/null)  # Get OS name (e.g., Linux, Darwin)

# Detect Windows subsystems (MINGW64, CYGWIN, etc.)
ifneq ($(filter MINGW%,$(UNAME_S)),)  # Git Bash/MinGW
	IS_WINDOWS := 1
else ifneq ($(filter MSYS%,$(UNAME_S)),)  # MSYS
	IS_WINDOWS := 1
else ifneq ($(filter CYGWIN%,$(UNAME_S)),)  # Cygwin
	IS_WINDOWS := 1
endif
# Fallback: Assume Unix-like if unrecognized

ifeq ($(IS_WINDOWS),1)
	FLAGS += -out:kolori.exe
	RELEASE_FLAGS += -subsystem:windows
	RELEASE_FLAGS += -extra-linker-flags:icon.res

	ifneq ($(shell rc --version 2>/dev/null),)
		RC := rc
		RC_FLAGS += /fo icon.res
	else
		RC := windres
		RC_FLAGS += -O coff -o icon.res
	endif
else
	FLAGS += -out:kolori
endif

debug:
	odin build src $(FLAGS) $(DEBUG_FLAGS)

release: icon.res
	odin build src $(FLAGS) $(RELEASE_FLAGS)

icon.res:
ifeq ($(IS_WINDOWS),1)
	$(RC) $(RC_FLAGS) ./src/icon.rc
endif

.PHONY clean:
	rm -f *.bin
	rm -f *.exe
	rm -f *.pdb
	rm -f *.res
	rm -f kolori_screenshot*.png
