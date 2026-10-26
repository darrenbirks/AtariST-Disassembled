; Batman The Movie (Ocean, 1989) - level 1 code, all versions
; Module level1: level1.bin, loaded at $2200, in scenes level1.
; Size: RETAIL_2DISK 21116 bytes, RETAIL_1DISK 20085 bytes, BUDGET_1DISK 20116 bytes.
;
; Level 1, Axis Chemical Factory.  The code and data are in level15.inc, which both
; levels assemble; BUILD_LEVEL picks level 1.
;
; The map is map_tiles at $7406: 42 rows of $cc tiles, after the tile count, the row
; length and the rows at $7400.  Tiles below $28 are walls, $28-$e1 open space,
; $e2-$fb floor to stand on, and $fa and up ladders (the floor counts them up to $fb).
; The tile cache has 96 slots, and the time limit is 9:00.  The code ends before
; $7400, where the map file loads.

BUILD_LEVEL	equ	1
	include	"level15.inc"

	end
