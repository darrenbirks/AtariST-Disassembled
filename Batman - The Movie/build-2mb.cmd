@echo off
rem Build the 2 MB file version from the sources, the quickest way to try an edited
rem source or map: no packing.  It builds the reissue and its game files
rem (build-files.cmd), puts them in 2mb-file-version\files with the game loader in
rem 2mb-file-version\loader.bin, and assembles 2mb-file-version\batman.prg.  Run
rem batman.prg from a hard disk or an emulator's GEMDOS drive, with files\ beside it.
rem batman.st is not rebuilt.
setlocal
set ROOT=%~dp0
call "%ROOT%build-files.cmd" || exit /b 1

set DEST=%ROOT%2mb-file-version
xcopy /y /q "%ROOT%build\file-version\files\*" "%DEST%\files\" >nul
copy /y "%ROOT%build\file-version\loader.bin" "%DEST%\loader.bin" >nul
cd /d "%DEST%"
"%ROOT%tools\vasm\vasmm68k_mot.exe" -devpac -m68000 -Ftos -quiet -o batman.prg batman.s
if errorlevel 1 (
  echo 2mb-file-version\batman.s did not assemble
  exit /b 1
)
echo The 2 MB file version is built in 2mb-file-version
