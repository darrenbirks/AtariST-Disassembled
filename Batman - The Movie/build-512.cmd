@echo off
rem Build the 512K file version from the sources.  It builds the reissue and its game
rem files (build-files.cmd), packs each with Pack-Ice 2.40 (tools\icepack\icepack.py, so
rem Python 3 is needed) into 512-file-version\files, puts the game loader in
rem 512-file-version\loader.bin and assembles 512-file-version\batman.prg.  Packing
rem takes about half a minute.  batman.st is not rebuilt.
setlocal
set ROOT=%~dp0
call "%ROOT%build-files.cmd" || exit /b 1

set DEST=%ROOT%512-file-version
set FAILED=
for %%F in ("%ROOT%build\file-version\files\*") do (
  py -3 "%ROOT%tools\icepack\icepack.py" "%%F" "%DEST%\files\%%~nxF"
  if errorlevel 1 set FAILED=1
)
if defined FAILED (
  echo Not every file packed.
  exit /b 1
)
copy /y "%ROOT%build\file-version\loader.bin" "%DEST%\loader.bin" >nul
cd /d "%DEST%"
"%ROOT%tools\vasm\vasmm68k_mot.exe" -devpac -m68000 -Ftos -quiet -o batman.prg batman.s
if errorlevel 1 (
  echo 512-file-version\batman.s did not assemble
  exit /b 1
)
echo The 512K file version is built in 512-file-version
