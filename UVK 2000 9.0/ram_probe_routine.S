; ram_probe_routine.S  -  The RAM size probe
;
; Devpac source of the RAM size probe in Ultimate Virus Killer 2000 9.0 by Richard Karsmakers (C.R.I.M.E. Development,
; 2004), disassembled by Darren Birks, 30 October 2026. The memory check is by H.W.A.M. de Beer, the author of
; SysInfo.
;
; UVK.LST holds this code as the INLINE block ram_probe_routine% (592 bytes), and ram_probe_routine.bin is those
; bytes. Assembled to a plain binary, this source gives ram_probe_routine.bin byte for byte. The code is position
; independent.

;------------------------------------------------------------------------------
; Measures the RAM size for the System Status screen (memory check by H.W.A.M. de Beer, from SysInfo), called through a
; routine address from the BASIC program. Runs ram_size_probe in supervisor mode (Supexec); it tests the last word of
; 14 MB, 13 MB ... 4 MB, 3.5, 3, 2.5, 2 and 1 MB, 512, 256 and 128 KB, and the first that can be written and read
; back gives the size.
; Entry: none. Exit: d0 = RAM size in KB ($3800 for 14 MB down to $80 for 128 KB, 0 when none answers).
; Keeps d1-d7/a0-a6.
;------------------------------------------------------------------------------
measure_ram_size:
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	pea	ram_size_probe(pc)              ; routine to run
	move.w	#$26,-(sp)                      ; Supexec
	trap	#14                             ; Supexec
	addq.l	#6,sp
	movem.l	(sp)+,d1-d7/a0-a6               ; restore the registers
	rts

; Supervisor routine run by measure_ram_size. Tests the last word of each RAM size, largest first, from 14 MB down
; to 128 KB, and returns the first size whose word is RAM.
; Exit: d0 = the RAM size in KB, or 0 when none answers.
ram_size_probe:
	lea	$dffffe,a3                      ; the last word of 14 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_1                         ; no RAM there: the next size down
	move.l	#$3800,d0                       ; 14 MB
	rts
.size_1:
	lea	$cffffe,a3                      ; the last word of 13 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_2                         ; no RAM there: the next size down
	move.l	#$3400,d0                       ; 13 MB
	rts
.size_2:
	lea	$bffffe,a3                      ; the last word of 12 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_3                         ; no RAM there: the next size down
	move.l	#$3000,d0                       ; 12 MB
	rts
.size_3:
	lea	$affffe,a3                      ; the last word of 11 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_4                         ; no RAM there: the next size down
	move.l	#$2c00,d0                       ; 11 MB
	rts
.size_4:
	lea	$9ffffe,a3                      ; the last word of 10 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_5                         ; no RAM there: the next size down
	move.l	#$2800,d0                       ; 10 MB
	rts
.size_5:
	lea	$8ffffe,a3                      ; the last word of 9 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_6                         ; no RAM there: the next size down
	move.l	#$2400,d0                       ; 9 MB
	rts
.size_6:
	lea	$7ffffe,a3                      ; the last word of 8 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_7                         ; no RAM there: the next size down
	move.l	#$2000,d0                       ; 8 MB
	rts
.size_7:
	lea	$6ffffe,a3                      ; the last word of 7 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_8                         ; no RAM there: the next size down
	move.l	#$1c00,d0                       ; 7 MB
	rts
.size_8:
	lea	$5ffffe,a3                      ; the last word of 6 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_9                         ; no RAM there: the next size down
	move.l	#$1800,d0                       ; 6 MB
	rts
.size_9:
	lea	$4ffffe,a3                      ; the last word of 5 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_10                        ; no RAM there: the next size down
	move.l	#$1400,d0                       ; 5 MB
	rts
.size_10:
	lea	$3ffffe,a3                      ; the last word of 4 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_11                        ; no RAM there: the next size down
	move.l	#$1000,d0                       ; 4 MB
	rts
.size_11:
	lea	$37fffe,a3                      ; the last word of 3.5 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_12                        ; no RAM there: the next size down
	move.l	#$e00,d0                        ; 3.5 MB
	rts
.size_12:
	lea	$2ffffe,a3                      ; the last word of 3 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_13                        ; no RAM there: the next size down
	move.l	#$c00,d0                        ; 3 MB
	rts
.size_13:
	lea	$27fffe,a3                      ; the last word of 2.5 MB
	bsr.w	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_14                        ; no RAM there: the next size down
	move.l	#$a00,d0                        ; 2.5 MB
	rts
.size_14:
	lea	$1ffffe,a3                      ; the last word of 2 MB
	bsr.s	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_15                        ; no RAM there: the next size down
	move.l	#$800,d0                        ; 2 MB
	rts
.size_15:
	lea	$ffffe,a3                       ; the last word of 1 MB
	bsr.s	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_16                        ; no RAM there: the next size down
	move.l	#$400,d0                        ; 1 MB
	rts
.size_16:
	lea	$7fffe,a3                       ; the last word of 512 KB
	bsr.s	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_17                        ; no RAM there: the next size down
	move.l	#$200,d0                        ; 512 KB
	rts
.size_17:
	lea	$3fffe,a3                       ; the last word of 256 KB
	bsr.s	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_18                        ; no RAM there: the next size down
	move.l	#$100,d0                        ; 256 KB
	rts
.size_18:
	lea	$1fffe,a3                       ; the last word of 128 KB
	bsr.s	ram_test
	lea	ram_failed(pc),a6
	tst.b	(a6)
	bne.s	.size_19                        ; no RAM there: the next size down
	move.l	#$80,d0                         ; 128 KB
	rts
.size_19:
	moveq	#0,d0                           ; nothing answered
	rts

; Tests the word at a3 for RAM: with interrupts off and the bus error vector pointing at .exit, writes $631A and
; $AECE to it and reads each back. Only when both read back is the word restored and ram_failed cleared.
ram_test:
	move	sr,d1                           ; keep the status register
	lea	ram_failed(pc),a4
	move.b	#$11,(a4)                       ; failed until the word answers
	suba.l	a0,a0                           ; a0 = 0, the exception vectors
	movea.l	sp,a2                           ; keep the stack, for a bus error
	ori	#$700,sr                        ; interrupts off
	movea.l	8(a0),a1                        ; the old bus error vector
	lea	.exit(pc),a5
	move.l	a5,8(a0)                        ; a bus error comes to .exit
	lea	ram_saved_word(pc),a5
	move.w	(a3),(a5)                       ; keep the word under test
	move.w	#$631a,(a3)
	move.w	(a3),d2
	dc.w	$b47c,$631a                     ; cmp.w #$631a,d2
	bne.s	.exit                           ; not read back: no RAM
	move.w	#$aece,(a3)
	move.w	(a3),d2
	dc.w	$b47c,$aece                     ; cmp.w #$aece,d2
	bne.s	.exit                           ; not read back: no RAM
	lea	ram_saved_word(pc),a5
	move.w	(a5),(a3)                       ; put the word back
	clr.b	(a4)                            ; RAM answers
.exit:
	move.l	a1,8(a0)                        ; the old bus error vector back
	move	d1,sr
	movea.l	a2,sp
	rts

ram_failed:
	dc.b	0                               ; $11 when the last word tested is not RAM, 0 when it is
	dc.b	0
ram_saved_word:
	dc.w	0                               ; the word under test, kept while it is written
