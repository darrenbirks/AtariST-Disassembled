; find_disk_driver_routine.S  -  The search for a reset-resident program in memory
;
; Devpac source of the search for a reset-resident program in memory in Ultimate Virus Killer 2000 9.0 by Richard
; Karsmakers (C.R.I.M.E. Development, 2004), disassembled by Darren Birks, 30 October 2026.
;
; UVK.LST holds this code as the INLINE block find_disk_driver_routine% (56 bytes), and find_disk_driver_routine.bin
; is those bytes. Assembled to a plain binary, this source gives find_disk_driver_routine.bin byte for byte. The code
; is position independent.

;------------------------------------------------------------------------------
; Looks for a reset-resident program in memory, called with RCALL from the BASIC program (the check for a virus in
; memory).
; Runs the code at reset_resident_scan in supervisor mode (Supexec). That code walks down from phystop in 512-byte steps
; looking for the reset-resident mark: the long $12123456 followed by a long pointing at itself.
; Entry: none. Exit: d0 (RCALL array element 0) = address of the block found, or $200 when there is none.
;------------------------------------------------------------------------------
find_reset_resident:
	pea	reset_resident_scan(pc)         ; routine to run
	move.w	#$26,-(sp)                      ; Supexec
	trap	#14                             ; Supexec
	addq.l	#6,sp
	move.l	a0,d0                           ; d0 = address the scan stopped at
	rts

; Supervisor routine run by find_reset_resident.
; Walks down from phystop a page (512 bytes) at a time, down to $200, looking for a page that starts with the
; reset-resident magic $12123456 followed by a long pointing at the page itself.
; Exit: a0 = the page found, or $200 when there is none.
reset_resident_scan:
	movea.l	$42e.w,a0                       ; phystop
	suba.w	#$200,a0                        ; the first page below it
	move.l	#$12123456,d0                   ; reset-resident magic
	move.l	#$200,d1                        ; the lowest page to check
.check_page:
	cmp.l	(a0),d0                         ; magic at the start of the page?
	bne.s	.next_page
	cmpa.l	4(a0),a0                        ; followed by a pointer to the page itself?
	beq.s	.done                           ; yes: found
.next_page:
	lea	-$200(a0),a0                    ; the page below
	cmpa.l	d1,a0
	bgt.s	.check_page                     ; until $200
.done:
	rts
