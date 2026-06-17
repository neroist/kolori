@echo off

if "%1" == "1" (
	set release_mode=1
) else if "%1" == "release" (
	set release_mode=1
) else (
	set release_mode=0
)

if %release_mode% equ 0 (
	odin build src -out:kolori.exe -debug -o:none -sanitize:address
) else (
	windres .\src\icon.rc -O coff icon.res
	odin build src -out:kolori.exe -subsystem:windows -extra-linker-flags:icon.res
)