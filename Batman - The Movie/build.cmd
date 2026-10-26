@echo off
rem Assemble every source for one release with vasm (tools\vasm), in Devpac mode.
rem
rem usage: build.cmd [RETAIL_2DISK | RETAIL_1DISK | BUDGET_1DISK]
rem
rem With no release it builds the 2 MB file version (build-2mb.cmd), the quickest way
rem to try an edited source or map.
rem
rem The release is built in build\<release>\: a copy of the sources and data\, a
rem config.s that selects the release, and <source>.bin for each source, the file as
rem the game loads it after its 4 byte load address (sound.bin is the text and data
rem of sound.prg).
setlocal
if not "%~1"=="" goto release
call "%~dp0build-2mb.cmd"
exit /b %errorlevel%

:release
set CFG=
if /i "%~1"=="RETAIL_2DISK" set CFG=RETAIL_2DISK
if /i "%~1"=="RETAIL_1DISK" set CFG=RETAIL_1DISK
if /i "%~1"=="BUDGET_1DISK" set CFG=BUDGET_1DISK
if not defined CFG (
  echo usage: build.cmd [RETAIL_2DISK ^| RETAIL_1DISK ^| BUDGET_1DISK]
  exit /b 1
)

cd /d "%~dp0"
set VASM=%~dp0tools\vasm\vasmm68k_mot.exe
set OUT=build\%CFG%
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
copy /y *.s "%OUT%" >nul
copy /y *.inc "%OUT%" >nul
xcopy /e /i /q data "%OUT%\data" >nul

rem config.s with CONFIG set to this release
findstr /v /b /c:"CONFIG" config.s > "%OUT%\config.s"
>>"%OUT%\config.s" echo CONFIG	equ	%CFG%

cd /d "%OUT%"
set FAILED=
for %%S in (loadstub loader panel sound frontend level1 level24 level3 level5) do (
  "%VASM%" -devpac -m68000 -Fbin -quiet -o %%S.bin %%S.s
  if errorlevel 1 (
    echo %CFG%: %%S.s did not assemble
    set FAILED=1
  )
)
if defined FAILED exit /b 1
echo %CFG%: built in %OUT%
