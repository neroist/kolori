@echo off

if "%1" == "1" (
	set release_mode=1
) else if "%1" == "release" (
	set release_mode=1
) else (
	set release_mode=0
)

if %release_mode% equ 0 (
	REM allow for extra building flags
	odin build src -out:kolori.exe -show-timings -debug -o:none %*
) else (
	REM compile icon resource
	where rc >nul 2>nul
	IF %ERRORLEVEL% NEQ 0 (
		rc /fo icon.res ./src/icon.rc
	) else (
		windres -O coff -o icon.res .\src\icon.rc
	)

	REM link compiled resource file into executable
	odin build src -out:kolori.exe -show-timings -subsystem:windows -extra-linker-flags:icon.res
)
