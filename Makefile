# please don't read. my god this is a mess.

# for making linux distributables:
#         `make dist LINUXDEPLOY=... APPIMAGETOOL=..."
# make sure to use relative (or absolute) paths!
# (e.g. NO: "linuxdeploy.AppImage" YES: "./linuxdeploy.AppImage")

DEBUG_FLAGS := -debug -o:none
RELEASE_FLAGS := 
RC :=
RC_FLAGS :=
ISCC_FLAGS := -O. -Q
ICON_SIZES := 16x16 24x24 32x32 48x48 64x64 128x128 180x180 192x192 256x256 512x512
SOURCES := $(wildcard ./src/*) $(wildcard ./src/math-parser/*) $(wildcard ./src/shaders/*) $(wildcard ./odin-imgui/*) $(wildcard ./fonts/*) ./favicon/favicon-64x64.png
LINUXDEPLOY := linuxdeploy
APPIMAGETOOL := appimagetool

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
	SOURCES += SDL3.dll
	DEBUG_FLAGS += -out:kolori_debug.exe
	RELEASE_FLAGS += -out:kolori.exe
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
	DEBUG_FLAGS += -out:kolori_debug
	RELEASE_FLAGS += -out:kolori
endif

.PHONY: clean installer
.SILENT:

default: release
release: kolori
debug: kolori_debug
dist: clean kolori-x86_64.exe kolori-x86_64.AppImage

kolori_debug: $(SOURCES)
	odin build src $(DEBUG_FLAGS)

kolori: $(SOURCES) icon.res
	odin build src $(RELEASE_FLAGS)

icon.res: ./src/icon.rc
ifeq ($(IS_WINDOWS),1)
	$(RC) $(RC_FLAGS) ./src/icon.rc
endif

./src/icon.rc: ./favicon/favicon.ico

kolori-x86_64.exe: release icon.res $(wildcard ./src/installer/*) LICENSE
ifeq ($(IS_WINDOWS),1)
	iscc $(ISCC_FLAGS) ./src/installer/script.iss
	rm kolori.exe
endif

kolori-x86_64.AppImage: release $(wildcard ./src/AppImage/*) $(wildcard ./favicon/*)
ifneq ($(IS_WINDOWS),1)
	for i in $(ICON_SIZES); do \
		mkdir -p ./AppDir/usr/share/icons/hicolor/$$i/apps/; \
		cp ./favicon/favicon-$$i.png ./AppDir/usr/share/icons/hicolor/$$i/apps/io.github.neroist.kolori.png; \
	done

	mkdir -p ./AppDir/usr/share/metainfo/
	cp ./src/AppImage/io.github.neroist.kolori.appdata.xml ./AppDir/usr/share/metainfo/

	# see: https://github.com/linuxdeploy/linuxdeploy/issues/272
	# was running into this issue on Arch, but not on WSL Ubuntu
	export NO_STRIP=true; \
	$(LINUXDEPLOY) -e ./kolori -d ./src/AppImage/io.github.neroist.kolori.desktop --appdir ./AppDir/
	$(APPIMAGETOOL) AppDir

	# AppImage created, begin cleaning up artifacts
	rm kolori

	# we want to make lowercase the "K" in the resulting AppImage
	# this roundabout way is used as a workaround for this error:
	# 	"mv: 'Kolori-x86_64.AppImage' and 'kolori-x86_64.AppImage' are the same file"
	# which i got on WSL
	mkdir tmp
	mv Kolori-x86_64.AppImage tmp/kolori-x86_64.AppImage
	mv tmp/kolori-x86_64.AppImage .
	rmdir tmp
endif

clean:
	rm -f kolori_debug
	rm -f kolori
	rm -f *.tar.gz
	rm -f *.bin
	rm -f *.exe
	rm -f *.pdb
	rm -f *.res
	rm -f *.ini
	rm -f *.zip
	rm -f *.AppImage
	rm -f kolori_screenshot*.png
	rm -rf AppDir
