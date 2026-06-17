EXECUTABLE := kolori
DEBUG_FLAGS := -debug -o:none -sanitize:address
RELEASE_FLAGS := 

# Check for Windows_NT environment variable (cmd.exe/PowerShell)
OS ?= $(shell echo %OS% 2>/dev/null)  # Fetch %OS% from Windows shell
ifeq ($(OS),Windows_NT)
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
	EXECUTABLE := kolori.exe
	RELEASE_CCFLAGS += -subsystem:windows
endif

debug:
	odin build src -out:$(EXECUTABLE) $(DEBUG_FLAGS)

release:
	odin build src -out:$(EXECUTABLE) $(RELEASE_FLAGS)
