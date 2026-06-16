CC := odin
CCFLAGS :=
DEBUG_CCFLAGS := -debug -o:none -sanitize:address
RELEASE_CCFLAGS := 

ifeq ($(OS),Windows_NT) 
	detected_OS := Windows
else
	detected_OS := $(shell sh -c 'uname 2>/dev/null || echo Unknown')
endif

ifeq (detected_OS,Windows)
	CCFLAGS += -out:kolori.exe
	RELEASE_CCFLAGS += -subsystem:windows
else
	CCFLAGS += -out:kolori
endif

debug:
	$(CC) build src $(CCFLAGS) $(DEBUG_CCFLAGS)

release:
	$(CC) build src $(CCFLAGS) $(RELEASE_CCFLAGS)

