@echo off
rem Build the 1 disk reissue (build.cmd RETAIL_1DISK) and make from it the 24 game files
rem the file versions load, unpacked, in build\file-version\files, with the game loader
rem in build\file-version\loader.bin.  build-2mb.cmd and build-512.cmd use it.
rem
rem   - The code files (PANEL.BIN, FRONTEND.BIN, LEVEL1.BIN, LEVEL24.BIN, LEVEL3.BIN,
rem     LEVEL5.BIN) are the built files with their 4 byte load address in front: the
rem     org of their source.
rem   - SOUND.PRG is sound.bin as a GEMDOS program: a 28 byte header, the code (sound.bin
rem     without the $400 byte BSS it ends with) and an empty relocation table.
rem   - The pictures, graphics and maps are copied from retail_1disk_speedlock\unpacked,
rem     which is where an edited map goes.
rem   - loader.bin is loadstub.bin followed by loader.bin, as the SpeedLock boot loads it.
setlocal enabledelayedexpansion
set ROOT=%~dp0
set VASM=%ROOT%tools\vasm\vasmm68k_mot.exe
call "%ROOT%build.cmd" RETAIL_1DISK || exit /b 1

set OUT=%ROOT%build\file-version
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%\files"
cd /d "%ROOT%build\RETAIL_1DISK"
set FAILED=

rem the code files: a source with dc.l <its org> and the built file after it (these two
rem small sources assemble in vasm's own mode, as Devpac mode has no incbin offset)
for %%S in (PANEL FRONTEND LEVEL1 LEVEL24 LEVEL3 LEVEL5) do (
  for /f "tokens=2" %%A in ('findstr /b /c:"	org	" %%S.s') do set ORG=%%A
  > header.s echo  dc.l !ORG!
  >> header.s echo  incbin "%%S.bin"
  "%VASM%" -m68000 -Fbin -quiet -o "%OUT%\files\%%S.BIN" header.s
  if errorlevel 1 set FAILED=1
)

rem the sound driver as a GEMDOS program
for %%F in (sound.bin) do set /a TEXT=%%~zF-1024
> header.s echo  dc.w $601a
>> header.s echo  dc.l %TEXT%,0,$400,0,0,0
>> header.s echo  dc.w 0
>> header.s echo  incbin "sound.bin",0,%TEXT%
>> header.s echo  dc.l 0
"%VASM%" -m68000 -Fbin -quiet -o "%OUT%\files\SOUND.PRG" header.s
if errorlevel 1 set FAILED=1
del header.s

copy /b loadstub.bin + loader.bin "%OUT%\loader.bin" >nul

rem the data files, as they are
for %%F in (TITLE.PIC PANEL.GFX FRONTEND.GFX LEVEL1.PIC LEVEL1A.GFX LEVEL1B.GFX LEVEL1.MAP LEVEL2.PIC LEVEL2.GFX LEVEL24.GFX LEVEL3.PIC LEVEL4.PIC LEVEL4.GFX LEVEL5.PIC LEVEL5A.GFX LEVEL5B.GFX LEVEL5.MAP) do (
  copy /y "%ROOT%retail_1disk_speedlock\unpacked\%%F" "%OUT%\files\%%F" >nul
  if errorlevel 1 (
    echo %%F is missing from retail_1disk_speedlock\unpacked
    set FAILED=1
  )
)
if defined FAILED exit /b 1
echo The game files are in build\file-version
