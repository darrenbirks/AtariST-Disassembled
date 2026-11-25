; pattern_match_routine.S  -  The 8-byte pattern compare
;
; Devpac source of the 8-byte pattern compare in Ultimate Virus Killer 2000 9.0 by Richard Karsmakers (C.R.I.M.E.
; Development, 2004), disassembled by Darren Birks, 30 October 2026.
;
; UVK.LST holds this code as the INLINE block pattern_match_routine% (152 bytes), and pattern_match_routine.bin is
; those bytes. Assembled to a plain binary, this source gives pattern_match_routine.bin byte for byte. The code is
; position independent.

;------------------------------------------------------------------------------
; Compares 8 bytes against a pattern, called with RCALL from the BASIC program; "?" in the pattern matches any byte.
; Entry: a0 (RCALL array element 8) = pattern (padded with "?"), a1 (RCALL array element 9) = bytes to test.
; Exit: d0 (RCALL array element 0) = 1 when all 8 bytes match, 0 otherwise.
;------------------------------------------------------------------------------
match_name_pattern:
	moveq	#0,d0                           ; result: no match
	moveq	#0,d1
	cmpi.b	#$3f,(a0)                       ; byte 0 of the pattern "?"?
	beq.s	.check_byte_one                 ; yes: matches anything
	move.b	(a1),d1                         ; compare byte 0
	cmp.b	(a0),d1
	bne.w	.done                           ; differs: no match
.check_byte_one:
	cmpi.b	#$3f,1(a0)                      ; byte 1
	beq.s	.check_byte_two
	move.b	1(a1),d1
	cmp.b	1(a0),d1
	bne.s	.done
.check_byte_two:
	cmpi.b	#$3f,2(a0)                      ; byte 2
	beq.s	.check_byte_three
	move.b	2(a1),d1
	cmp.b	2(a0),d1
	bne.s	.done
.check_byte_three:
	cmpi.b	#$3f,3(a0)                      ; byte 3
	beq.s	.check_byte_four
	move.b	3(a1),d1
	cmp.b	3(a0),d1
	bne.s	.done
.check_byte_four:
	cmpi.b	#$3f,4(a0)                      ; byte 4
	beq.s	.check_byte_five
	move.b	4(a1),d1
	cmp.b	4(a0),d1
	bne.s	.done
.check_byte_five:
	cmpi.b	#$3f,5(a0)                      ; byte 5
	beq.s	.check_byte_six
	move.b	5(a1),d1
	cmp.b	5(a0),d1
	bne.s	.done
.check_byte_six:
	cmpi.b	#$3f,6(a0)                      ; byte 6
	beq.s	.check_byte_seven
	move.b	6(a1),d1
	cmp.b	6(a0),d1
	bne.s	.done
.check_byte_seven:
	cmpi.b	#$3f,7(a0)                      ; byte 7
	beq.s	.matched
	move.b	7(a1),d1
	cmp.b	7(a0),d1
	bne.s	.done
.matched:
	moveq	#1,d0                           ; all 8 match
.done:
	rts
	dc.w	$0000,$0000                     ; unused
