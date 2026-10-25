@echo off
rem Packs the reissue's files into 512-file-version\files with Pack-Ice 2.40 (icepack.go).
cd /d "%~dp0"
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\title.pic ..\..\512-file-version\files\TITLE.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\panel.gfx ..\..\512-file-version\files\PANEL.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\panel.bin ..\..\512-file-version\files\PANEL.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\sound.prg ..\..\512-file-version\files\SOUND.PRG
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\frontend.bin ..\..\512-file-version\files\FRONTEND.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\frontend.gfx ..\..\512-file-version\files\FRONTEND.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1.pic ..\..\512-file-version\files\LEVEL1.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1.bin ..\..\512-file-version\files\LEVEL1.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1a.gfx ..\..\512-file-version\files\LEVEL1A.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1b.gfx ..\..\512-file-version\files\LEVEL1B.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1.map ..\..\512-file-version\files\LEVEL1.MAP
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level2.pic ..\..\512-file-version\files\LEVEL2.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level24.bin ..\..\512-file-version\files\LEVEL24.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level24.gfx ..\..\512-file-version\files\LEVEL24.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level2.gfx ..\..\512-file-version\files\LEVEL2.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level3.pic ..\..\512-file-version\files\LEVEL3.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level3.bin ..\..\512-file-version\files\LEVEL3.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level4.pic ..\..\512-file-version\files\LEVEL4.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level4.gfx ..\..\512-file-version\files\LEVEL4.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5.pic ..\..\512-file-version\files\LEVEL5.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5.bin ..\..\512-file-version\files\LEVEL5.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5a.gfx ..\..\512-file-version\files\LEVEL5A.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5b.gfx ..\..\512-file-version\files\LEVEL5B.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5.map ..\..\512-file-version\files\LEVEL5.MAP
