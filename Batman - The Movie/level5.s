; Batman The Movie (Ocean, 1989) - level 5 code, all versions
; Module level5: level5.bin, loaded at $2200, in scenes level5.
; Size: RETAIL_2DISK 21500 bytes, RETAIL_1DISK 21500 bytes, BUDGET_1DISK 21531 bytes.
;
; Level 5, Cathedral.  The code and data are in level15.inc, which both levels
; assemble; BUILD_LEVEL picks level 5.
;
; The map is map_tiles at $7406: 204 rows of $5c tiles, after the tile count, the row
; length and the rows at $7400.  Tiles below $18 are walls, $18-$c9 open space,
; $ca-$cc deadly floor (landing on one counts as a fall of $70, which costs a life),
; $cd-$fa floor to stand on, and $f8 and up ladders (the floor counts them up to $fa).
; The tile cache has 72 slots, and the time limit is 12:00.  The map file loads over
; the tail of the code at $7400, so everything from $7400 on is overwritten before the
; level runs.

BUILD_LEVEL	equ	5
	include	"level15.inc"

	end
