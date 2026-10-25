@echo off
rem Packs the reissue's files into ..\files with Pack-Ice 2.40 (icepack.go).
cd /d "%~dp0"
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\title.pic ..\files\TITLE.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\panel.gfx ..\files\PANEL.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\panel.bin ..\files\PANEL.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\sound.prg ..\files\SOUND.PRG
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\frontend.bin ..\files\FRONTEND.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\frontend.gfx ..\files\FRONTEND.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1.pic ..\files\LEVEL1.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1.bin ..\files\LEVEL1.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1a.gfx ..\files\LEVEL1A.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1b.gfx ..\files\LEVEL1B.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level1.map ..\files\LEVEL1.MAP
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level2.pic ..\files\LEVEL2.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level24.bin ..\files\LEVEL24.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level24.gfx ..\files\LEVEL24.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level2.gfx ..\files\LEVEL2.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level3.pic ..\files\LEVEL3.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level3.bin ..\files\LEVEL3.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level4.pic ..\files\LEVEL4.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level4.gfx ..\files\LEVEL4.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5.pic ..\files\LEVEL5.PIC
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5.bin ..\files\LEVEL5.BIN
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5a.gfx ..\files\LEVEL5A.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5b.gfx ..\files\LEVEL5B.GFX
go run icepack.go ..\..\retail_1disk_speedlock\unpacked\level5.map ..\files\LEVEL5.MAP
