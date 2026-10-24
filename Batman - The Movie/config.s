; Batman The Movie (Ocean, 1989) - which version the sources assemble.
;
; Every source includes this file.  Set CONFIG to one of the versions below.
; The parts of a source that not every version has are in blocks:
;   "ifeq CONFIG-<version>" ... "endc"   only that version
;   "ifne CONFIG-<version>" ... "endc"   every version but that one
;
;   RETAIL_2DISK   the 2 disk retail release, the original
;   RETAIL_1DISK   the 1 disk retail reissue
;   BUDGET_1DISK   the 1 disk budget release (The Hit Squad)

RETAIL_2DISK	equ	1
RETAIL_1DISK	equ	2
BUDGET_1DISK	equ	3

CONFIG	equ	RETAIL_1DISK

