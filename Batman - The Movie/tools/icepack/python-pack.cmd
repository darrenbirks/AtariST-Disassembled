@echo off
rem Packs the reissue's files into 512-file-version\files with Pack-Ice 2.40 (icepack.py).
cd /d "%~dp0"
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\title.pic ..\..\512-file-version\files\TITLE.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\panel.gfx ..\..\512-file-version\files\PANEL.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\panel.bin ..\..\512-file-version\files\PANEL.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\sound.prg ..\..\512-file-version\files\SOUND.PRG
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\frontend.bin ..\..\512-file-version\files\FRONTEND.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\frontend.gfx ..\..\512-file-version\files\FRONTEND.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1.pic ..\..\512-file-version\files\LEVEL1.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1.bin ..\..\512-file-version\files\LEVEL1.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1a.gfx ..\..\512-file-version\files\LEVEL1A.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1b.gfx ..\..\512-file-version\files\LEVEL1B.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level1.map ..\..\512-file-version\files\LEVEL1.MAP
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level2.pic ..\..\512-file-version\files\LEVEL2.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level24.bin ..\..\512-file-version\files\LEVEL24.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level24.gfx ..\..\512-file-version\files\LEVEL24.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level2.gfx ..\..\512-file-version\files\LEVEL2.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level3.pic ..\..\512-file-version\files\LEVEL3.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level3.bin ..\..\512-file-version\files\LEVEL3.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level4.pic ..\..\512-file-version\files\LEVEL4.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level4.gfx ..\..\512-file-version\files\LEVEL4.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5.pic ..\..\512-file-version\files\LEVEL5.PIC
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5.bin ..\..\512-file-version\files\LEVEL5.BIN
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5a.gfx ..\..\512-file-version\files\LEVEL5A.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5b.gfx ..\..\512-file-version\files\LEVEL5B.GFX
py -3 icepack.py ..\..\retail_1disk_speedlock\unpacked\level5.map ..\..\512-file-version\files\LEVEL5.MAP
