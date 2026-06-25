# please don't read. my god this is a mess.

DEBUG_FLAGS := -debug -o:none
RELEASE_FLAGS := 
RC :=
RC_FLAGS :=
ISCC_FLAGS := -O. -Q
ICON_SIZES := 16x16,24x24,32x32,48x48,64x64,128x128,180x180,192x192,256x256,512x512

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
default: release
release: kolori
debug: kolori_debug

kolori_debug: $(wildcard src/*) $(wildcard odin-imgui/*)
	odin build src $(DEBUG_FLAGS)

kolori: $(wildcard src/*) $(wildcard odin-imgui/*) icon.res
	odin build src $(RELEASE_FLAGS)

icon.res:
ifeq ($(IS_WINDOWS),1)
	$(RC) $(RC_FLAGS) ./src/icon.rc
endif

kolori-x86_64.exe: release icon.res
ifeq ($(IS_WINDOWS),1)
	iscc $(ISCC_FLAGS) ./src/installer/script.iss
endif

kolori-x86_64.AppImage: release
ifneq ($(IS_WINDOWS),1)
	@mkdir -p AppDir/usr/share/icons/hicolor/{$(ICON_SIZES)}/apps/
	@mkdir -p AppDir/usr/share/metainfo/

	@for i in $$(echo $(ICON_SIZES) | tr ',' '\n'); do \
		cp ./favicon/favicon-$$i.png AppDir/usr/share/icons/hicolor/$$i/apps/io.github.neroist.kolori.png; \
	done

	cp ./src/AppImage/io.github.neroist.kolori.appdata.xml ./AppDir/usr/share/metainfo/

	# https://github.com/linuxdeploy/linuxdeploy/issues/272
	@export NO_STRIP=true; \
	linuxdeploy -e ./kolori -d ./src/AppImage/io.github.neroist.kolori.desktop -l /usr/lib/libm.so.6 -l /usr/lib/libc.so.6 -l /usr/lib/libgcc_s.so.1 --appdir ./AppDir/
	appimagetool AppDir

	mv Kolori-x86_64.AppImage kolori-x86_64.AppImage
endif

installer: clean kolori-x86_64.exe kolori-x86_64.AppImage

clean:
	@rm -rf kolori_debug
	@rm -rf kolori
	@rm -f *.bin
	@rm -f *.exe
	@rm -f *.pdb
	@rm -f *.res
	@rm -f *.ini
	@rm -f kolori_screenshot*.png
<<<<<<< HEAD
	@rm -f *.ini
=======
	@rm -rf AppDir
	@rm -rf AppImage
>>>>>>> 3f92b15 (feat: support creation of AppImages for distribution on Linux)
