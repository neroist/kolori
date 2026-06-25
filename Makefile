FLAGS :=
VERSION := 0.3.0
OUT := kolori
DEBUG_FLAGS := -debug -o:none
RELEASE_FLAGS := 
RC :=
RC_FLAGS :=
ISCC_FLAGS := -O. -Q

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

.PHONY: clean installer
default: release

debug:
	odin build src $(FLAGS) $(DEBUG_FLAGS)

release: icon.res
	odin build src $(FLAGS) $(RELEASE_FLAGS)

icon.res:
ifeq ($(IS_WINDOWS),1)
	$(RC) $(RC_FLAGS) ./src/icon.rc
endif

installer: kolori-$(VERSION)-x86_64.exe
kolori-$(VERSION)-x86_64.exe: release icon.res
ifeq ($(IS_WINDOWS),1)
	iscc $(ISCC_FLAGS) ./src/installer/script.iss
endif

clean:
	@rm -f *.bin
	@rm -f *.exe
	@rm -f *.pdb
	@rm -f *.res
	@rm -f kolori_screenshot*.png
	@rm -f *.ini
