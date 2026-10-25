@echo off
rem Packs the reissue's files into ..\files with Pack-Ice 2.40 (icepack.py).
cd /d "%~dp0"
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\title.pic ..\files\TITLE.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\panel.gfx ..\files\PANEL.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\panel.bin ..\files\PANEL.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\sound.prg ..\files\SOUND.PRG
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\frontend.bin ..\files\FRONTEND.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\frontend.gfx ..\files\FRONTEND.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1.pic ..\files\LEVEL1.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1.bin ..\files\LEVEL1.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1a.gfx ..\files\LEVEL1A.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1b.gfx ..\files\LEVEL1B.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1.map ..\files\LEVEL1.MAP
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level2.pic ..\files\LEVEL2.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level24.bin ..\files\LEVEL24.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level24.gfx ..\files\LEVEL24.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level2.gfx ..\files\LEVEL2.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level3.pic ..\files\LEVEL3.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level3.bin ..\files\LEVEL3.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level4.pic ..\files\LEVEL4.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level4.gfx ..\files\LEVEL4.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5.pic ..\files\LEVEL5.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5.bin ..\files\LEVEL5.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5a.gfx ..\files\LEVEL5A.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5b.gfx ..\files\LEVEL5B.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5.map ..\files\LEVEL5.MAP
