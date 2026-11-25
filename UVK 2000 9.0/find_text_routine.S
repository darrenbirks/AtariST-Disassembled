; find_text_routine.S  -  The lookup of a numbered text
;
; Devpac source of the lookup of a numbered text in Ultimate Virus Killer 2000 9.0 by Richard Karsmakers (C.R.I.M.E.
; Development, 2004), disassembled by Darren Birks, 30 October 2026.
;
; UVK.LST holds this code as the INLINE block find_text_routine% (144 bytes), and find_text_routine.bin is those
; bytes. Assembled to a plain binary, this source gives find_text_routine.bin byte for byte. The code is position
; independent.

;------------------------------------------------------------------------------
; Finds a text by number in one of UVK's numbered text tables, called with RCALL from the BASIC program.
; A table holds records of a word number followed by a zero-terminated string padded to an even length; $ffff ends it.
; Up to six tables are remembered in text_table_cache together with the record last found in each, and the search starts
; there, wrapping round at the end of the table, so texts read in order are found at once.
; Entry: a0 (RCALL array element 8) = table address, d0 (RCALL array element 0) = text number.
; Exit: a0 = address of the string, or of "ERROR!" when the number is not in the table.
;------------------------------------------------------------------------------
find_numbered_text:
	movea.l	a0,a1                           ; a1 = table start
	lea	text_table_cache(pc),a2         ; a2 = cache, first slot at +4
.next_slot:
	addq.l	#4,a2                           ; next slot
	tst.l	(a2)                            ; free slot?
	bne.s	.check_slot
	move.l	a0,(a2)                         ; yes: remember this table there
	bra.s	.start_search                   ; and search from its start
.check_slot:
	cmpa.l	(a2),a0                         ; slot for this table?
	bne.s	.next_slot                      ; no: next slot
	movea.l	$18(a2),a0                      ; yes: search from the record last found
.start_search:
	lea	$18(a2),a3                      ; a3 = the slot's last-found position
	movea.l	a0,a4                           ; a4 = where the search started
	moveq	#-1,d1                          ; d1 = end marker $ffff
	bra.s	.next_record
.check_wrapped:
	cmpa.l	a0,a4                           ; back where it started?
	beq.s	.not_found                      ; yes: not in the table
.next_record:
	move.w	(a0)+,d2                        ; d2 = record number
	cmp.w	d2,d0                           ; the one wanted?
	bne.s	.check_table_end
	move.l	a0,(a3)                         ; remember the record for next time
	subq.l	#2,(a3)                         ; (its number word)
	rts                                     ; a0 = the string
.check_table_end:
	cmp.w	d2,d1                           ; end of the table?
	bne.s	.skip_string
	movea.l	a1,a0                           ; yes: wrap round to the start
	bra.s	.check_wrapped
.skip_string:
	tst.b	d2                              ; low byte 0: string and padding ended
	beq.s	.check_wrapped
	move.w	(a0)+,d2                        ; skip the string a word at a time
	tst.b	d2
	beq.s	.check_wrapped
	move.w	(a0)+,d2
	tst.b	d2
	beq.s	.check_wrapped
	move.w	(a0)+,d2
	bra.s	.skip_string
.not_found:
	lea	text_not_found(pc),a0           ; a0 = "ERROR!"
	rts

; Text returned by find_numbered_text when a number is not in the table: "ERROR!" (it runs on into the first word of
; text_table_cache, which holds "R!" and the terminator).
text_not_found:
	dc.w	$4552,$524f                     ; "ERRO"

; Cache of find_numbered_text. The first word ends the "ERROR!" text. Then six longs ($1b6c2): addresses of the tables
; searched so far (0 = free slot), and six longs $18 bytes further ($1b6da): for each, the address of the record last
; found.
text_table_cache:
	dc.w	$5221,$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; "R!",0 ends "ERROR!"; then the table slots
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; last-found positions
	dc.w	$0000,$0000,$0000,$0000
