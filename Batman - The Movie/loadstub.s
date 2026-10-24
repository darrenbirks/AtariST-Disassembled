; Batman The Movie (Ocean, 1989) - game loader: copy stub (decrypted image), all versions
; Module loadstub: loader.bin, loaded at $21000, in scenes loader.
; Size: RETAIL_2DISK 70 bytes, RETAIL_1DISK 76 bytes, BUDGET_1DISK 76 bytes.
;
; The copy stub at the start of each version's decrypted game loader image
; (loader.bin):
;
; RETAIL_2DISK, the 2 disk retail release (the original): the first $46 bytes of
; track 0 sectors 2-9 of disk 1 after the SpeedLock decryption.  Copies the jump
; table to $200 and $400 longs from $21046 to $1000 (the loader, loader.s, and $46
; bytes from beyond the 4 KB read), then enters loader_start.
;
; RETAIL_1DISK and BUDGET_1DISK: the first $4c bytes.  Copies the loader that follows
; to $1000, puts the jump table at $200 and enters loader_start.
;
; Labels are named for what they do or hold; unused_ marks code that nothing
; calls.  A label still ending in its address (tab_ table, dat_ data) is one
; whose use is not known yet.  "; from:" lists the routines or modules that
; refer to a label (documentation only).

	include	"config.s"			; CONFIG: which version to assemble

; symbols in other modules
loader_vectors	equ	$1000		; loader.s
loader_start	equ	$1018		; loader.s

	opt	o-
	org	$21000

copy_stub:
	ifne	CONFIG-RETAIL_2DISK
	move.b	#$2e,$2e.w
	endc
	lea	jump_table(pc),a0
	lea	$200.w,a1                       ; loader section 0 (jmp $1000)
	move.w	#$7,d0
copy_jumps_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,copy_jumps_loop
	ifne	CONFIG-BUDGET_1DISK
	lea	loader_code(pc),a0
	endc
	ifeq	CONFIG-BUDGET_1DISK
	lea	$2104c(pc),a0
	endc
	lea	loader_vectors.w,a1
	ifeq	CONFIG-RETAIL_2DISK
	move.w	#$3ff,d0                        ; $400 longs: 4 KB from $21046, $46 bytes past the sectors read
	endc
	ifne	CONFIG-RETAIL_2DISK
	move.w	#$4ff,d0
	endc
copy_loader_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,copy_loader_loop
	jmp	loader_start


; Copied to $200: jmp $1000.w, jmp $1004.w ... jmp $1014.w, jmp $1000.w (one per loader vector).
jump_table:	; from: copy_stub
	dc.w	$4ef8,$1000,$4ef8,$1004,$4ef8,$1008,$4ef8,$100c
	dc.w	$4ef8,$1010,$4ef8,$1014,$4ef8,$1000
	ifne	CONFIG-BUDGET_1DISK
loader_code:
	endc

	end
