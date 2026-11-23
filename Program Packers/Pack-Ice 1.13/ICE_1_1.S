; ICE_1_1.PRG  -  Pack-Ice 1.13 ("This packer was written by Axe of Delight.")
; Devpac source of the program, disassembled by Darren Birks, 23 November 2026.
; Text 4446 bytes, data 0 bytes, bss 68 bytes.
;
; ICE_1_1.PRG as released is this program packed with its own program stub ("Pack-Ice by Axe/Delight"),
; 3352 bytes.  This is the source of the 4518 byte program that the stub unpacks; it rebuilds ICE_1_1.PRG
; unpacked, byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o ICE_1_1.PRG ICE_1_1.S
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; Pack-Ice 1.13 by Axe of Delight, "First version finished on: 14.02.1990", "Final changes on: 20.05.1990".
; A text program: it asks 1) Crunch data file or 2) Crunch executable file, whether a program is to be
; relocated after depacking, and the name to pack; every file matching the name is packed in turn and saved
; over itself.  The window is always $1528 bytes; there is no picture compression and no GEM.
;
; While packing it shows "Remaining: xx%", then the time and the rate; the mouse is turned off at the IKBD
; meanwhile, and the time is read from _hz_200 in supervisor mode.  Alternate held while packing skips the
; file.  Before saving, the packed data is depacked in a block of its own and compared with the file on disk.
;
; Its packed data has no header: the bit stream, written a long at a time, ends with the unpacked length and
; 'Ice!'.  The only depacker is the program stub's; ice_depack sets up and jumps into its loop.
;
; Some code is patched while it runs: relocate NO turns stub_relocate and stub_clear_bss into branches over
; their work, and save_packed writes the packed length into the stub.
;
; Some things in it look unfinished:
;   - text_dest_prompt and text_verify_question are not used: the verify is always on.
;   - stub_clear_bss counts its high word in d2, left negative by the copy, so a BSS of 512 K or more is
;     cleared only in part.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$0043  start-up
;   $0044-$0645  the menu and the file loop, file calls, input, time and progress
;   $0646-$0869  the packer, crunch
;   $086a-$0a85  the program stub, with stub_depack
;   $0a86-$0ab9  ice_depack
;   $0aba-$115d  the variables and texts
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; Packed data: a bit stream of longs that the depacker reads from the end down, then the unpacked length and
; 'Ice!'.
;
; Packed program: the stub's $21c bytes (a PRG header whose text is the stub's $200 bytes and the packed data,
; with no relocation), then the packed data without 'Ice!', and a 0 long.
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The program starts here.
;------------------------------------------------------------------------------
start:
	dc.w	$a00a                           ; Line-A $a, Line-A: hide the mouse
main:
	movea.l	sp,a5                           ; a5 = the stack at entry
	movea.l	4(a5),a5                        ; a5 = the basepage
	move.l	$c(a5),d0                       ; text length
	add.l	$14(a5),d0                      ; + data length
	add.l	$1c(a5),d0                      ; + BSS length
	addi.l	#$200,d0                        ; + $200
	move.l	d0,-(sp)                        ; Mshrink(0, basepage, length)
	move.l	a5,-(sp)
	move.w	#$0,-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	adda.w	#$c,sp
	move.w	stub_relocate(pc),relocate_opcode ; keep the stub's relocation word
	move.w	stub_clear_bss(pc),clear_bss_opcode ; and its BSS clearing word
	bsr.w	menu                            ; the menu
	clr.w	-(sp)
	trap	#1                              ; Pterm0

;------------------------------------------------------------------------------
; The menu: data or a program, the relocation question for a program, then the name to pack and the loop over
; every file matching it.  The verify is always on.
;------------------------------------------------------------------------------
menu:	; from: start, save_packed
	lea	banner(pc),a0                   ; the banner
	bsr.w	print_text                      ; print
menu_text:
	lea	text_menu(pc),a0                ; "1) Crunch data file (Default) ... Please select: "
	bsr.w	print_text                      ; print
menu_key:
	bsr.w	get_key                         ; a key
menu_choice:
	move.b	#$1,data_mode                   ; data
	cmpi.b	#$31,d0                         ; '1'?
	beq.s	verify_on                       ; yes
	cmpi.b	#$d,d0                          ; Return?
	beq.s	verify_on                       ; yes
	cmpi.b	#$32,d0                         ; '2'?
	bne.s	menu_key                        ; no: another key
	move.b	#$0,data_mode                   ; a program
relocate_text:
	lea	text_relocate(pc),a0            ; "Relocate program after depacking (Y/n): "
	bsr.w	print_text                      ; print
	bsr.w	get_key                         ; a key
relocate_answer:
	move.w	relocate_opcode(pc),stub_relocate ; the stub relocates
	move.w	clear_bss_opcode(pc),stub_clear_bss ; and clears the BSS
	cmpi.b	#$d,d0                          ; Return?
	beq.s	verify_on                       ; yes: relocate
	ori.b	#$20,d0                         ; lower case
	cmpi.b	#$79,d0                         ; 'y'?
	beq.s	verify_on                       ; yes: relocate
	cmpi.b	#$6e,d0                         ; 'n'?
	bne.s	relocate_text                   ; no: ask again
	move.w	#$6034,stub_relocate            ; the stub skips the relocation
	move.w	#$6016,stub_clear_bss           ; and the BSS clearing
verify_on:
	moveq	#-1,d3                          ; verify
	move.w	d3,verify_flag                  ; on
type_name:
	lea	text_source_prompt(pc),a0       ; "Enter name of source file: "
	bsr.w	print_text                      ; print
	pea	name_input(pc)                  ; the input buffer
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	lea	file_name(pc),a1                ; the typed name
	adda.w	d0,a1                           ; + its length
	clr.b	(a1)                            ; ended
typed_name_done:
	lea	newline(pc),a0                  ; a new line
	bsr.w	print_text                      ; print
first_file:
	pea	dta(pc)                         ; the DTA
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.l	#6,sp
	move.w	#$0,-(sp)                       ; normal files
	pea	file_name(pc)                   ; the name
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.l	d0                              ; found?
	bne.s	type_name                       ; not found: ask again
pack_file:	; from: save_packed
	move.l	file_length(pc),d0              ; the file's length
	addi.l	#$4b1,d0                        ; + $4b1
	bclr	#$0,d0                          ; even
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bmi.w	no_memory                       ; no: "Could not allocate enough memory"
	move.l	d0,dest                         ; the packed data goes at the start
	addi.l	#$4b0,d0                        ; the file $4b0 on
	move.l	d0,source                       ; where it is read to
	move.w	#$2,-(sp)                       ; read and write
	pea	dta_name(pc)                    ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.w	d0,file_handle                  ; the handle
	tst.l	d0
	bmi.w	menu_done                       ; failed: stop
	move.l	source(pc),-(sp)                ; to the source
	move.l	file_length(pc),-(sp)           ; its length
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	lea	$c(sp),sp
	tst.l	d0
	bmi.w	menu_done                       ; failed: stop
	bsr.w	close_file                      ; close it
	move.l	file_length(pc),d1              ; the length
	add.l	source(pc),d1                   ; + the source
	move.l	d1,source_end                   ; = its end
	lea	text_working(pc),a0             ; "Working: "
	bsr.w	print_text                      ; print
working_name:
	lea	dta_name(pc),a0                 ; the file's name
	bsr.w	print_text                      ; print
	clr.w	alt_pressed                     ; Alternate not pressed
	pea	mouse_off(pc)                   ; IKBD: mouse off
	clr.w	-(sp)                           ; 1 byte
	move.w	#$19,-(sp)
	trap	#14                             ; Ikbdws
	addq.l	#8,sp
	clr.l	-(sp)                           ; supervisor mode
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	move.l	d0,old_ssp                      ; the old stack kept
	move.l	$4ba.w,start_ticks              ; _hz_200, the start time
	bsr.w	crunch                          ; pack
	movea.l	d0,a3                           ; a3 = the packed length
	bsr.w	print_time                      ; print the time
	move.l	old_ssp(pc),-(sp)               ; back to user mode
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	pea	mouse_on(pc)                    ; IKBD: the mouse back on
	clr.w	-(sp)
	move.w	#$19,-(sp)
	trap	#14                             ; Ikbdws
	addq.l	#8,sp
	tst.w	alt_pressed                     ; Alternate pressed?
	bne.w	skipped                         ; yes: skip the file
	tst.w	too_many_literals               ; too many literals?
	beq.s	check_length                    ; no
	lea	text_cannot_pack(pc),a0         ; " Data cannot be packed!  [cancelled]"
	bsr.w	print_text                      ; print
	bra.w	next_file                       ; free the block
check_length:
	lea	(a3),a1                         ; the packed length
	tst.b	data_mode                       ; data?
	bne.s	set_packed_end                  ; yes
	adda.w	#$21c,a1                        ; no: + the stub's $21c bytes
set_packed_end:
	move.l	a1,packed_end                   ; kept
	movea.l	file_length(pc),a2              ; the file's length
	cmpa.l	a2,a1                           ; longer?
	bge.w	larger                          ; yes: "Larger than original!"
	tst.w	verify_flag                     ; verify?
	beq.w	save_packed                     ; no: save
	lea	text_verify(pc),a0              ; "    Verify: "
	bsr.w	print_text                      ; print
	move.l	file_length(pc),d1              ; the file's length
	addi.l	#$2af8,d1                       ; + $2af8
	move.l	d1,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bpl.s	verify                          ; yes
	lea	text_no_mem(pc),a0              ; no: "No mem!"
	bsr.w	print_text                      ; print
	bra.w	save_packed                     ; and save without verifying
verify:
	movea.l	d0,a4                           ; a4 = the block
verify_depack:
	movea.l	d0,a2                           ; a2 = it too
	move.l	d0,packed_copy                  ; kept
	move.l	a3,d1                           ; the packed length
	subq.l	#1,d1
	movea.l	dest(pc),a1                     ; the packed data
verify_keep_packed:
	move.b	(a1)+,(a2)+                     ; copy it to the block
	dbra	d1,verify_keep_packed           ; 64 K at a time
	subi.l	#$10000,d1
	bpl.s	verify_keep_packed
	movea.l	a4,a0                           ; a0 = the packed copy
	move.l	a3,d0                           ; the packed length
	bsr.w	ice_depack
	adda.w	#$78,a4                         ; the depacked data, $78 bytes on
	lea	$64(a4),a2                      ; past the depacked data and $64 bytes
	adda.l	file_length(pc),a2              ; + the length
	move.l	a2,d0
	bclr	#$0,d0                          ; even
	move.l	d0,verify_read_buffer           ; = where the file is read back
	bsr.w	open_file                       ; open the original again
verify_read:
	movea.l	verify_read_buffer(pc),a0       ; the buffer
	move.l	#$2710,d0                       ; 10000 bytes
	bsr.w	read_file                       ; read
	move.l	d0,d4                           ; d4 = what was read
	beq.s	verify_close                    ; nothing?
	cmpi.l	#$2710,d0                       ; a whole 10000?
	bcc.s	verify_compare                  ; all 10000?
verify_close:
	bsr.w	close_file                      ; close it
	move.l	d4,d0                           ; the count
verify_compare:
	movea.l	verify_read_buffer(pc),a2       ; what was read
	subq.w	#1,d0
	bmi.s	verify_block_done
verify_loop:
	move.b	(a2)+,d1                        ; a byte read
	move.b	(a4)+,d2                        ; and the depacked one
	cmp.b	d1,d2                           ; the same?
	bne.s	verify_error                    ; no: error
	dbra	d0,verify_loop                  ; for each byte
verify_block_done:
	cmpi.l	#$2710,d4                       ; 10000 read: on
	beq.s	verify_read                     ; yes: the next block
	lea	text_ok(pc),a0                  ; "OK! "
	bsr.w	print_text                      ; print
	bsr.w	free_verify                     ; free the copy
	bra.s	save_packed                     ; save
verify_error:
	lea	text_error(pc),a0               ; "Error!        [cancelled]"
	bsr.w	print_text                      ; print
	bsr.w	free_verify                     ; free the copy
	bra.w	next_file                       ; and do not save

free_verify:	; from: menu
	move.l	packed_copy(pc),-(sp)           ; the copy
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; Save the packed file over the original: data as it is; a program as the stub (its text length and packed end
; patched in), the bit stream with its unpacked length but without 'Ice!', and an empty relocation table.
;------------------------------------------------------------------------------
save_packed:	; from: menu
	bsr.w	print_rate                      ; print the rate
	cmpi.b	#$1,data_mode                   ; data?
	beq.s	save_data                       ; yes
	subq.l	#4,a3                           ; less 'Ice!' at the end
	movea.w	#$21c,a4                        ; the stub's length
	movea.l	a3,a5                           ; the packed length
	lea	-$1c(a5,a4.w),a5                ; + the stub less its header
	move.l	a5,d0
	addq.l	#1,d0                           ; made even
	bclr	#$0,d0                          ; even
	move.l	d0,stub_text_length             ; the stub's text length
	bsr.w	create_file                     ; create the file
	lea	stub(pc),a5                     ; the stub
	movea.w	#$21c,a6                        ; $21c bytes
	lea	stub_packed_end+2,a4
	move.l	(a4),d0
	add.l	a3,d0                           ; + the packed length
	move.l	d0,(a4)                         ; patched
	bsr.w	write_file                      ; write it
	move.l	(a4),d0                         ; the immediate
	sub.l	a3,d0                           ; back
	move.l	d0,(a4)
	movea.l	dest(pc),a5                     ; the packed data
	move.l	a3,d0                           ; its length
	addq.l	#1,d0                           ; made even
	bclr	#$0,d0
	movea.l	d0,a6
	bsr.w	write_file                      ; write it
	lea	zero_long(pc),a5                ; a 0 long
	movea.w	#$4,a6                          ; 4 bytes
	bsr.w	write_file                      ; write it: no relocation
	bsr.w	close_file                      ; close
	bra.s	next_file                       ; the next file
save_data:
	bsr.w	create_file                     ; create the file
	movea.l	dest(pc),a5                     ; the packed data
	movea.l	a3,a6                           ; its length
	bsr.w	write_file                      ; write it
	bsr.w	close_file                      ; close
	bra.s	next_file                       ; the next file
skipped:	; from: menu
	lea	text_alt(pc),a0                 ; "   <ALT> was pressed. File is skipped."
	bsr.w	print_text                      ; print
	bra.s	next_file                       ; the next file
larger:	; from: menu
	lea	text_larger(pc),a0              ; "    Larger than original!   [cancelled]"
	bsr.w	print_text                      ; print
next_file:	; from: menu
	move.l	dest(pc),-(sp)                  ; the block
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	tst.l	d0                              ; all right?
	bne.s	menu_done                       ; no: stop
	move.w	#$4f,-(sp)
	trap	#1                              ; Fsnext
	addq.l	#2,sp
	tst.l	d0                              ; found?
	bpl.w	pack_file                       ; yes: pack it
another_text:
	lea	newline(pc),a0                  ; a new line
	bsr.w	print_text                      ; print
	lea	text_another(pc),a0             ; "Crunch another file (Y/n): "
	bsr.w	print_text                      ; print
	bsr.w	get_key                         ; a key
	ori.b	#$20,d0                         ; lower case
	cmpi.b	#$79,d0                         ; 'y'?
	bne.s	menu_done                       ; no: done
	bra.w	menu                            ; yes: the menu
no_memory:	; from: menu
	lea	text_no_memory(pc),a0           ; "Could not allocate enough memory"
	bsr.w	print_text                      ; print
	bsr.w	raw_key                         ; wait for a key
menu_done:	; from: menu, open_file, create_file, write_file, close_file
	rts

;------------------------------------------------------------------------------
; Fopen the found name (dta_name) to read into file_handle; a failure returns at once through menu_done.
;------------------------------------------------------------------------------
open_file:	; from: menu
	move.w	#$0,-(sp)                       ; read only
	pea	dta_name(pc)                    ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	tst.l	d0                              ; failed?
	bmi.s	menu_done                       ; yes
	move.w	d0,file_handle                  ; the handle
	rts

read_file:	; from: menu
	pea	(a0)                            ; to a0
	move.l	d0,-(sp)                        ; d0 bytes
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	adda.w	#$c,sp
	rts

create_file:	; from: save_packed
	move.w	#$0,-(sp)                       ; normal file
	pea	dta_name(pc)                    ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	tst.l	d0                              ; the flags
	bmi.s	menu_done                       ; failed
	move.w	d0,file_handle                  ; the handle
	rts

write_file:	; from: save_packed
	move.l	a5,-(sp)                        ; from a5
	move.l	a6,-(sp)                        ; a6 bytes
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	tst.l	d0                              ; the flags
	bmi.s	menu_done                       ; failed
	rts

close_file:	; from: menu, save_packed
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	bmi.s	menu_done                       ; failed
	rts

get_key:	; from: menu, save_packed
	move.w	#$1,-(sp)
	trap	#1                              ; Cconin
	addq.l	#2,sp
	rts

raw_key:	; from: save_packed
	move.w	#$7,-(sp)
	trap	#1                              ; Crawcin
	addq.l	#2,sp
	rts

;------------------------------------------------------------------------------
; Z clear when Alternate is held.
;------------------------------------------------------------------------------
alternate_held:	; from: progress
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	trap	#13                             ; Kbshift
	addq.l	#4,sp
	btst	#$3,d0                          ; Alternate?
	rts

print_text:	; from: menu, save_packed, print_time, progress, print_rate
	move.l	a0,-(sp)                        ; the string
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; Print the packing time as minutes:seconds.
;------------------------------------------------------------------------------
print_time:	; from: menu
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	lea	text_time(pc),a0                ; "Time:" at its place
	bsr.s	print_text                      ; print
	move.l	$4ba.w,d0                       ; _hz_200
	sub.l	start_ticks(pc),d0
	divu.w	#$c8,d0                         ; seconds
	swap	d0
	clr.w	d0                              ; the remainder dropped
	swap	d0
	divu.w	#$3c,d0                         ; minutes and seconds
	moveq	#0,d1
	move.w	d0,d1                           ; d1 = the minutes
	swap	d0                              ; the remainder
	moveq	#0,d2
	move.w	d0,d2                           ; d2 = the seconds
	lea	time_digits(pc),a0              ; the minute digits
	clr.l	(a0)                            ; cleared
	clr.l	2(a0)
time_minute_digit:
	divu.w	#$a,d1                          ; a digit
	swap	d1                              ; the remainder
	addi.w	#$30,d1                         ; to a character
	move.w	d1,(a0)+                        ; stored
	clr.w	d1
	swap	d1                              ; the quotient
	tst.w	d1                              ; more?
	bne.s	time_minute_digit               ; yes
	move.l	#$200020,(a0)+                  ; two spaces after them
	lea	time_digits_end(pc),a0          ; the third word
	move.w	-(a0),d0                        ; the hundreds
	bsr.w	put_char                        ; printed
	move.w	-(a0),d0                        ; the tens
	bsr.w	put_char                        ; printed
	move.w	-(a0),d0                        ; the units
	bsr.w	put_char                        ; printed
	move.b	#$3a,d0                         ; :
	bsr.w	put_char                        ; printed
	move.l	d2,d0                           ; the seconds
	divu.w	#$a,d0                          ; tens
	addi.w	#$30,d0                         ; to a character
	bsr.w	put_char                        ; printed
	swap	d0                              ; units
	addi.w	#$30,d0                         ; to a character
	bsr.w	put_char                        ; printed
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts
time_digits:
	dc.w	$0000,$0000,$0000               ; the minutes' digits, a word each, units first
time_digits_end:
	dc.w	$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; Start the progress: a check every 128th of the length.
;------------------------------------------------------------------------------
progress_init:	; from: crunch
	move.l	d0,-(sp)
	move.l	file_length(pc),d0              ; the length
	lsr.l	#7,d0                           ; / 128
	move.l	d0,progress_step                ; the step
	move.l	source(pc),progress_next        ; the first check at the start
	move.w	#$ffff,progress_last            ; no percentage shown yet
	move.l	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; Called by the packer with a0 = its position: at each step the percentage still to do is printed after
; "Remaining:".  Alternate stops the packing: the end is moved to the position.
;------------------------------------------------------------------------------
progress:	; from: crunch
	cmpa.l	progress_next(pc),a0            ; the next check reached?
	bcs.s	progress_skip                   ; no
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	move.l	progress_step(pc),d0            ; the step
	add.l	d0,progress_next                ; the next check
	move.l	a0,d1                           ; the position
	move.l	source_end(pc),d0               ; the end
	move.l	source(pc),d2                   ; the start
	sub.l	d2,d1                           ; done
	sub.l	d2,d0                           ; the whole
	bsr.w	scale_down                      ; both to 16 bits
	mulu.w	#$64,d1                         ; * 100
	bsr.w	scale_down                      ; to 16 bits again
	tst.w	d0                              ; the whole 0?
	beq.s	progress_done                   ; yes: nothing to show
	divu.w	d0,d1                           ; the percentage
	swap	d1
	clr.w	d1                              ; the remainder dropped
	swap	d1
	cmp.w	progress_last(pc),d1            ; changed?
	beq.s	progress_done                   ; no
	move.w	d1,progress_last                ; yes: kept
	divu.w	#$a,d1                          ; tens and units
	move.l	#$390039,d0                     ; '9' '9'
	sub.l	d1,d0                           ; less: the percentage left
	lea	remaining_digits(pc),a0         ; into "99%"
	move.b	d0,(a0)+                        ; tens
	swap	d0
	move.b	d0,(a0)+                        ; units
	lea	text_remaining(pc),a0           ; "Remaining: xx%" at its place
	bsr.w	print_text                      ; print
	bsr.w	alternate_held                  ; Alternate held?
	beq.s	progress_done                   ; no
progress_wait_alternate:
	bsr.w	alternate_held                  ; wait for it to be let go
	bne.s	progress_wait_alternate
	move.w	#$ffff,alt_pressed              ; Alternate pressed
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	movea.l	a0,a2                           ; the packing ends here
	bra.s	progress_skip
progress_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
progress_skip:
	rts
progress_next:	; from: progress_init
	dc.l	$00000000                       ; the position of the next check
progress_step:	; from: progress_init
	dc.l	$00000000                       ; the step
progress_last:	; from: progress_init
	dc.w	$0000                           ; the percentage shown last

;------------------------------------------------------------------------------
; Print " Rate: xx% [saving]", the packed length as a percentage.
;------------------------------------------------------------------------------
print_rate:	; from: save_packed
	lea	text_rate(pc),a0                ; " Rate: "
	bsr.w	print_text                      ; print
	move.l	file_length(pc),d0              ; the length
	move.l	packed_end(pc),d1               ; the packed length
	bsr.w	scale_down                      ; both to 16 bits
	mulu.w	#$64,d1                         ; * 100
	bsr.w	scale_down                      ; to 16 bits again
	divu.w	d0,d1                           ; the percentage
	move.l	d1,d0
	swap	d0
	clr.w	d0                              ; the remainder dropped
	swap	d0
	divu.w	#$a,d0                          ; tens and units
	addi.l	#$300030,d0                     ; to characters
	bsr.w	put_char                        ; print tens
	swap	d0
	bsr.w	put_char                        ; print units
	lea	text_saving(pc),a0              ; "% [saving]"
	bsr.w	print_text                      ; print
	rts

;------------------------------------------------------------------------------
; Halve d0 and d1 together until both fit 16 bits.
;------------------------------------------------------------------------------
scale_down:	; from: progress, print_rate
	swap	d0                              ; the high words
	swap	d1
	tst.w	d0                              ; d0 over 16 bits?
	bne.s	scale_down_halve                ; yes
	tst.w	d1                              ; d1?
	bne.s	scale_down_halve                ; yes
	swap	d0                              ; back
	swap	d1
	rts
scale_down_halve:
	swap	d0                              ; back
	swap	d1
	lsr.l	#1,d0                           ; halve
	lsr.l	#1,d1
	bra.s	scale_down                      ; again

put_char:	; from: print_time, print_rate
	movem.l	d0-d3/a0-a3,-(sp)               ; keep the registers
	move.w	d0,-(sp)                        ; the character
	move.w	#$2,-(sp)
	trap	#1                              ; Cconout
	addq.l	#4,sp
	movem.l	(sp)+,d0-d3/a0-a3               ; the registers back
	rts

;------------------------------------------------------------------------------
; The packer: source/file_length to dest as a bit stream, written a long at a time, then the unpacked length and
; 'Ice!'; the depacker reads it from the end down.  At each position it takes the longest string found by a plain
; search within window behind, and writes literal counts, offsets and lengths as variable-length codes.  a2 holds
; the end of the source.  d0 = the packed length.
;------------------------------------------------------------------------------
crunch:	; from: menu
	clr.w	too_many_literals               ; no literal overflow
	bsr.w	progress_init                   ; start the progress
	move.l	#$1528,window                   ; the window: always $1528
	movea.l	source(pc),a0                   ; the source
	move.l	file_length(pc),d0              ; its length
	movea.l	dest(pc),a1                     ; the output
	lea	0(a0,d0.l),a2                   ; a2 = the end of the source
	moveq	#0,d5                           ; no literals yet
	moveq	#31,d6                          ; 32 bits to go in the long
	moveq	#0,d7                           ; the bit long
crunch_loop:
	movea.l	a0,a3                           ; the window's end
	adda.l	window(pc),a3
	cmpa.l	a2,a3                           ; past the end?
	ble.s	crunch_search                   ; no
	movea.l	a2,a3                           ; yes: to the end
crunch_search:
	moveq	#1,d4                           ; the best length so far
	lea	1(a0),a4                        ; where the search starts
plain_search:
	move.b	(a0),d0                         ; the first two bytes
	move.b	1(a0),d1
plain_search_loop:
	cmp.b	(a4)+,d0                        ; the first?
	beq.s	plain_search_second             ; yes
plain_search_next:
	cmpa.l	a4,a3                           ; inside the window?
	bgt.s	plain_search_loop               ; yes: on
	bra.s	crunch_code                     ; no: done
plain_search_second:
	cmp.b	(a4),d1                         ; the second?
	bne.s	plain_search_next               ; no: on
compare_string:
	movea.l	a4,a6
	subq.l	#1,a6                           ; the match
	move.l	a6,d0
	movea.l	a0,a5                           ; the current position
compare_loop:
	cmpm.b	(a5)+,(a6)+                     ; the same?
	bne.s	compare_done                    ; no
	cmpa.l	d0,a5                           ; into the current position?
	bhi.s	compare_done                    ; yes: stop
	cmpa.l	a6,a3                           ; inside the window?
	bgt.s	compare_loop                    ; yes: on
compare_done:
	move.l	a5,d1
	sub.l	a0,d1
	subq.l	#1,d1                           ; the length
	move.l	a6,d2
	sub.l	a5,d2
	sub.l	d1,d2
	move.l	#$409,d0                        ; the longest length
	cmp.l	d0,d1                           ; longer?
	bls.s	compare_best                    ; no
	sub.l	d0,d1                           ; yes: cut to the longest
	add.l	d1,d2                           ; the offset grows with it
	move.l	d0,d1
compare_best:
	cmp.l	d1,d4                           ; longer than the best?
	bge.s	compare_next                    ; no
	cmp.w	#$2,d1                          ; 2 bytes?
	bls.s	take_string                     ; yes: take it
	cmp.w	#$111f,d2                       ; offset within $111f?
	bhi.s	compare_next                    ; no
take_string:
	move.l	d1,d4                           ; the best
	move.w	d1,match_length                 ; its length
	move.w	d2,match_offset                 ; its offset
compare_next:
	cmpa.l	a4,a3                           ; inside the window?
	bgt.s	plain_search                    ; yes: the next
crunch_code:
	move.w	match_offset(pc),d0             ; the offset
	move.w	d4,d1                           ; the length
	cmpi.w	#$1,d1                          ; 1: a literal
	beq.s	crunch_literal
	cmpi.w	#$2,d1                          ; 2: a short string
	beq.s	crunch_short
	bra.s	crunch_string                   ; longer: a string
crunch_literal:	; from: put_short_offset
	move.b	(a0)+,(a1)+                     ; copy the byte
	addq.l	#1,d5                           ; count it
	bra.s	crunch_next                     ; the next position
crunch_short:
	cmpi.w	#$23f,d0                        ; offset over $23f?
	bhi.s	crunch_literal                  ; yes: a literal
	bsr.w	put_literal_count               ; the literal count
	bsr.w	put_short_offset                ; the short offset
	bra.s	crunch_length
crunch_string:
	bsr.w	put_literal_count               ; the literal count
	bsr.w	put_offset                      ; the offset
crunch_length:
	bsr.w	put_length                      ; the length
	moveq	#0,d5                           ; no literals
	move.w	match_length(pc),d0             ; the length
	lea	0(a0,d0.w),a0                   ; past the string
crunch_next:
	bsr.w	progress                        ; the progress
	lea	-$3(a2),a3                      ; 3 before the end
	cmpa.l	a3,a0                           ; reached?
	bcs.w	crunch_loop                     ; no: on
crunch_tail:
	cmpa.l	a2,a0                           ; the end?
	beq.s	crunch_end                      ; yes
	move.b	(a0)+,(a1)+                     ; copy the rest
	addq.l	#1,d5                           ; as literals
	bra.s	crunch_tail
crunch_end:
	bsr.w	put_literal_count               ; the literal count
	bset	d6,d7                           ; the end marker bit
	bsr.w	put_long                        ; the last bits
	move.l	file_length(pc),d7              ; the unpacked length
	bsr.w	put_long                        ; after them
	move.l	#$49636521,d7                   ; 'Ice!'
	bsr.w	put_long                        ; last
	suba.l	dest(pc),a1                     ; the packed length
	move.l	a1,d0                           ; in d0
	rts

;------------------------------------------------------------------------------
; The literal count: a run of up to $40e literals in 6 ranges; longer and the packing is given up (the end moved
; here).
;------------------------------------------------------------------------------
put_literal_count:	; from: crunch
	cmp.l	#$40e,d5                        ; too long?
	bls.s	literal_count_range             ; no
	move.w	#$ffff,too_many_literals        ; yes: give up
	movea.l	a0,a2                           ; here: the end
literal_count_range:
	lea	literal_bits(pc),a3             ; the bases
	moveq	#5,d3                           ; 6 ranges
literal_count_find:
	move.b	0(a3,d3.w),d4                   ; the range's start
	ext.w	d4
	cmp.w	d4,d5                           ; in this range?
	dbge	d3,literal_count_find           ; no: the one below
	sub.w	d4,d5                           ; less its start
	lsl.w	#1,d3                           ; words
	move.b	6(a3,d3.w),d2                   ; the prefix length
	ext.w	d2
	moveq	#-1,d1
	lsl.l	d2,d1                           ; its ones
	or.w	d5,d1                           ; the count
	moveq	#0,d5                           ; no literals
	move.b	7(a3,d3.w),d4                   ; the bit count
	ext.w	d4
	bra.w	put_bits                        ; write them
literal_bits:
	dc.b	$00,$01,$02,$05,$08,$0f,$01,$00,$01,$01,$02,$03,$02,$05,$03,$08 ; the literal counts the ranges start
                                                ;   at, then each range's prefix length and bit count
	dc.b	$0a,$12

put_offset:	; from: crunch
	lea	offset_table(pc),a3             ; the offset table
	moveq	#2,d3                           ; 3 ranges
offset_find:
	add.w	d3,d3                           ; words
	move.w	0(a3,d3.w),d4                   ; the range's start
	lsr.w	#1,d3
	cmp.w	d4,d0                           ; in this range?
	dbge	d3,offset_find                  ; no: the one below
	sub.w	d4,d0                           ; less its start
	add.w	d3,d3                           ; words
	move.w	6(a3,d3.w),d3                   ; its prefix and bits
	move.w	d3,d4
	lsr.w	#8,d3                           ; the prefix length
	moveq	#-1,d1
	lsl.w	d3,d1                           ; the prefix
	or.w	d0,d1                           ; the offset
	andi.w	#$f,d4                          ; the bit count
	bra.w	put_bits                        ; write them
offset_table:
	dc.w	$0000,$0020,$0120,$0606,$0908,$0c0d ; range starts, then prefix length and bit count

put_short_offset:	; from: crunch
	cmpi.w	#$23f,d0                        ; over $23f?
	bhi.w	crunch_literal                  ; yes: a literal
	move.w	d0,d1
	cmpi.w	#$3f,d1                         ; 6 bits?
	ble.s	short_offset_6                  ; yes
	subi.w	#$40,d1                         ; no: 9 bits
	moveq	#9,d4                           ; 10 bits
	bset	d4,d1                           ; and a 1
	bra.w	put_bits                        ; write them
short_offset_6:
	moveq	#6,d4                           ; 6 bits + the 0
	bra.s	put_bits                        ; write them

put_length:	; from: crunch
	lea	length_table(pc),a3             ; the length table
	move.w	match_length(pc),d0             ; the length
	moveq	#4,d5                           ; 5 ranges
length_find:
	move.b	0(a3,d5.w),d4                   ; the range's start
	ext.w	d4
	cmp.w	d4,d0                           ; in this range?
	dbge	d5,length_find                  ; no: the one below
	sub.w	d4,d0                           ; less its start
	move.b	5(a3,d5.w),d4                   ; its bits
	ext.w	d4
	moveq	#-1,d1
	lsl.w	d4,d1                           ; the prefix
	or.w	d0,d1                           ; the length
	add.w	d5,d4                           ; + the prefix length
	subq.w	#1,d4                           ; the bit count
	bra.s	put_bits
length_table:
	dc.b	$02,$03,$04,$06,$0a,$01,$01,$02,$03,$0a ; range starts, then bit counts

;------------------------------------------------------------------------------
; Write the low d4+1 bits of d1 into the bit long d7, the long to the output each time it fills.
;------------------------------------------------------------------------------
put_bits:	; from: put_literal_count, put_offset, put_short_offset, put_length
	lsr.l	#1,d1                           ; a bit
	roxr.l	#1,d7                           ; into the long
	dbra	d6,put_bits_next                ; full?
	bsr.s	put_long                        ; yes: write it
	moveq	#0,d7
	moveq	#31,d6                          ; 32 bits
put_bits_next:
	dbra	d4,put_bits                     ; for each bit
	rts

put_long:	; from: crunch, put_bits
	rol.l	#8,d7                           ; the top byte
	move.b	d7,(a1)+                        ; written
	rol.l	#8,d7
	move.b	d7,(a1)+
	rol.l	#8,d7
	move.b	d7,(a1)+
	rol.l	#8,d7
	move.b	d7,(a1)+
	rts

;------------------------------------------------------------------------------
; Pack-Ice's program stub, written in front of a packed program by save_packed: a PRG header whose text is the
; stub's $200 bytes and the packed data, then code that depacks the program $2e4 bytes past the stub's text,
; relocates it to run there, sets the basepage's lengths, and runs a mover placed past the BSS that copies it
; down, clears the BSS and starts it.
;------------------------------------------------------------------------------
stub:	; from: save_packed
	bra.s	stub_text                       ; the PRG magic $601a (bra.s past the header)
stub_text_length:	; from: save_packed
	dc.l	$00000200                       ; text length: patched
	dc.w	$0000,$0000
stub_bss_length:
	dc.l	$00000000                       ; BSS length
	dc.w	$0000,$0000,$0000,$0000,$0000,$0001,$ffff
stub_text:
	bra.s	stub_start                      ; over the name
	dc.b	'Pack-Ice by Axe/Delight',0
stub_start:
	lea	stub_text(pc),a4                ; a4 = the stub's text: where the program will run
	lea	(a4),a5                         ; a5 = it
stub_packed_end:
	adda.l	#$200,a5                        ; + $200 and the packed length: the end of the packed data (patched)
	lea	$2e4(a4),a6                     ; a6 = where the program depacks to
	bsr.w	stub_depack                     ; depack
	movea.l	a6,a3                           ; a3 = the depacked program
	lea	-$100(a4),a5                    ; a5 = the basepage, $100 below the text
stub_relocate:	; from: start, menu
	movea.l	2(a3),a0                        ; its text length (a bra.s past the relocation when it is off)
	adda.l	6(a3),a0                        ; + data
	adda.l	$e(a3),a0                       ; + symbols
	lea	$1c(a0,a3.l),a0                 ; a0 = the relocation table
	move.l	8(a5),d0                        ; d0 = where it will run
	adda.w	#$1c,a3                         ; a3 = its text
	tst.l	(a0)                            ; any?
	beq.s	stub_relocated                  ; no
	adda.l	(a0)+,a3                        ; the first long
	moveq	#0,d1
stub_relocate_long:
	add.l	d0,(a3)                         ; relocate a long
stub_relocate_next:
	move.b	(a0)+,d1                        ; the next step
	beq.s	stub_relocated                  ; the end
	cmpi.b	#$1,d1                          ; 1: 254 on?
	bne.s	stub_relocate_step              ; no
	adda.w	#$fe,a3                         ; yes
	bra.s	stub_relocate_next
stub_relocate_step:
	adda.l	d1,a3                           ; on
	bra.s	stub_relocate_long              ; relocate it
stub_relocated:
	lea	2(a6),a3                        ; the depacked header's lengths
	addq.l	#8,a5                           ; the basepage's text address
	movea.l	(a5)+,a2                        ; a2 = it
	move.l	(a3),(a5)+                      ; text length
	move.l	(a3),d2                         ; d2 = the text length
	adda.l	(a3)+,a2
	move.l	a2,(a5)+                        ; data address
	move.l	(a3),(a5)+                      ; data length
	add.l	(a3),d2                         ; + the data: d2 = what the mover copies
	adda.l	(a3)+,a2
	move.l	a2,(a5)+                        ; the BSS address
	move.l	(a3),(a5)+                      ; the BSS length
	adda.l	(a3)+,a2                        ; past the BSS
	adda.w	#$328,a2                        ; + $328
	moveq	#10,d0                          ; 11 longs: the mover and the clearing
	lea	(a2),a0                         ; the mover goes here
	lea	stub_mover(pc),a1               ; the mover
stub_copy_mover:
	move.l	(a1)+,(a2)+                     ; copied
	dbra	d0,stub_copy_mover
	lea	$1c(a6),a1                      ; the depacked text
	lsr.l	#3,d2                           ; in 8 byte steps
	movea.l	a4,a3                           ; where it runs
	jmp	(a0)                            ; run the mover
stub_mover:
	move.l	(a1)+,(a3)+                     ; copy 8 bytes
	move.l	(a1)+,(a3)+
	dbra	d2,stub_mover                   ; for each 8 bytes
	moveq	#1,d3                           ; $10000
	swap	d3
	sub.l	d3,d2                           ; the high count
	bpl.s	stub_mover                      ; more
stub_clear_bss:	; from: start, menu
	movea.l	-$e8(a4),a3                     ; the BSS (a bra.s past the clearing when it is off)
	move.l	-$e4(a4),d1                     ; its length
	lsr.l	#3,d1                           ; in 8 byte steps
	moveq	#0,d0                           ; a 0
stub_clear_loop:
	move.l	d0,(a3)+                        ; clear 8 bytes
	move.l	d0,(a3)+
	dbra	d1,stub_clear_loop              ; for each 8 bytes
	sub.l	d3,d2                           ; the high count, from d2, which is negative after the copy
	bpl.s	stub_clear_loop
	jmp	(a4)                            ; run the program

;------------------------------------------------------------------------------
; Depack the bit stream that ends at a5 to a6; its last long is the unpacked length.  The verify's ice_depack
; jumps into it.  The stream is read a long at a time from the end down, a long at an odd address in two parts.
;------------------------------------------------------------------------------
stub_depack:	; from: stub
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	movea.l	a6,a0                           ; a0 = the output's start
	bsr.s	stub_first_long                 ; the unpacked length
	adda.l	d7,a6                           ; a6 = the output's end
	bsr.s	stub_first_long                 ; the first long
stub_literals:	; from: stub_get_bits, ice_depack
	bsr.s	stub_get_bit                    ; a literal run?
	bcc.s	stub_literals_done              ; no: a string
	moveq	#0,d1
	bsr.s	stub_get_bit                    ; one literal?
	bcc.s	stub_copy_literals              ; yes
	lea	stub_literal_bases(pc),a1       ; the run length codes
	moveq	#3,d3                           ; 4 sizes
stub_literal_size:
	move.l	-(a1),d0                        ; bits and all-ones value
	bsr.s	stub_get_bits                   ; read the bits
	swap	d0                              ; the all-ones value
	cmp.w	d0,d1                           ; all ones: the next size
	dbne	d3,stub_literal_size
	add.l	$10(a1),d1                      ; + the size's base
stub_copy_literals:
	move.b	-(a5),-(a6)                     ; copy a literal
	dbra	d1,stub_copy_literals           ; for each literal
stub_literals_done:
	cmpa.l	a0,a6                           ; all depacked?
	bgt.s	stub_string                     ; no: a string
stub_depack_done:	; from: ice_depack
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts

;------------------------------------------------------------------------------
; The stream's last long, 4 bytes from a5 down, into d7.
;------------------------------------------------------------------------------
stub_first_long:	; from: stub_depack, ice_depack
	moveq	#3,d0                           ; 4 bytes
stub_first_long_loop:
	move.b	-(a5),d7                        ; a byte
	ror.l	#8,d7                           ; into the long
	dbra	d0,stub_first_long_loop         ; for each
	rts
stub_get_bits_refill:	; from: stub_get_bits
	move.w	a5,d7                           ; a5 odd?
	btst	#$0,d7
	bne.s	stub_get_bits_odd               ; yes
	move.l	-(a5),d7                        ; no: the next long
	addx.l	d7,d7                           ; the marker bit in
	bra.s	stub_get_bits_next
stub_get_bits_odd:
	move.l	-$5(a5),d7                      ; from an odd address: 3 bytes
	lsl.l	#8,d7
	move.b	-(a5),d7                        ; and 1
	subq.l	#3,a5
	add.l	d7,d7                           ; the first bit out
	bset	#$0,d7                          ; the marker bit in
	bra.s	stub_get_bits_next

;------------------------------------------------------------------------------
; The next bit into the X and C flags.
;------------------------------------------------------------------------------
stub_get_bit:	; from: stub_depack, stub_get_bits
	add.l	d7,d7                           ; the next bit
	beq.s	stub_get_bit_refill             ; none left?
	rts
stub_get_bit_refill:
	move.w	a5,d7                           ; a5 odd?
	btst	#$0,d7
	bne.s	stub_get_bit_odd                ; yes
	move.l	-(a5),d7                        ; no: the next long
	addx.l	d7,d7                           ; the marker bit in
	rts
stub_get_bit_odd:
	move.l	-$5(a5),d7                      ; from an odd address: 3 bytes
	lsl.l	#8,d7
	move.b	-(a5),d7                        ; and 1
	subq.l	#3,a5
	add.l	d7,d7                           ; the first bit out
	bset	#$0,d7                          ; the marker bit in
	rts

;------------------------------------------------------------------------------
; d0+1 bits into d1.
;------------------------------------------------------------------------------
stub_get_bits:	; from: stub_depack
	moveq	#0,d1                           ; d1 = d0+1 bits
stub_get_bits_loop:
	add.l	d7,d7                           ; the next bit
	beq.s	stub_get_bits_refill            ; none left: refill
stub_get_bits_next:	; from: stub_first_long
	addx.w	d1,d1                           ; into d1
	dbra	d0,stub_get_bits_loop           ; for each bit
	rts
stub_string:	; from: stub_depack
	lea	stub_length_table(pc),a1        ; the length codes
	moveq	#3,d2                           ; up to 4 bits
stub_length_code:
	bsr.s	stub_get_bit                    ; a bit
	dbcc	d2,stub_length_code             ; until a 0
	moveq	#0,d4
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the extra bits
	ext.w	d0
	bmi.s	stub_length_base                ; none
	bsr.s	stub_get_bits                   ; read them
stub_length_base:
	move.b	6(a1,d2.w),d4                   ; + the base length
	add.w	d1,d4
	beq.s	stub_short_offset               ; length 2: a short offset
	lea	stub_offset_table(pc),a1        ; the offset codes
	moveq	#1,d2                           ; up to 2 bits
stub_offset_code:
	bsr.s	stub_get_bit                    ; a bit
	dbcc	d2,stub_offset_code             ; until a 0
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the offset bits
	ext.w	d0
	bsr.s	stub_get_bits                   ; read them
	add.w	d2,d2                           ; words
	add.w	6(a1,d2.w),d1                   ; + the base offset
	bra.s	stub_copy_string
stub_short_offset:
	moveq	#0,d1
	moveq	#5,d0                           ; 6 bits
	moveq	#0,d2
	bsr.s	stub_get_bit                    ; 9 bits?
	bcc.s	stub_short_offset_bits          ; no
	moveq	#8,d0                           ; yes
	moveq	#64,d2
stub_short_offset_bits:
	bsr.s	stub_get_bits                   ; read them
	add.w	d2,d1                           ; + the base
stub_copy_string:
	lea	2(a6,d4.w),a1                   ; the string's source
	adda.w	d1,a1                           ; + the offset
	move.b	-(a1),-(a6)                     ; copy it
stub_copy_string_loop:
	move.b	-(a1),-(a6)
	dbra	d4,stub_copy_string_loop        ; for each byte
	bra.w	stub_literals                   ; and on
stub_literal_table:
	dc.l	$03ff0009,$00070002,$00030001,$00030001 ; bits and all-ones values of the run length codes
stub_literal_bases:	; from: stub_depack
	dc.l	$0000000e,$00000007,$00000004,$00000001 ; the run lengths they start at, less 1
stub_length_table:
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; extra bits, then base lengths
stub_offset_table:
	dc.b	$0b,$04,$07,$00                 ; offset bits, then base offsets
	dc.w	$0120,$0000,$0020

;------------------------------------------------------------------------------
; Pack-Ice's depacker, for the verify: depacks the 'Ice!' data of d0 bytes at a0 to $78 bytes past it.  It keeps
; the registers as stub_depack does and jumps into its loop, whose register restore and rts end it.  d0 = the
; unpacked length.
;------------------------------------------------------------------------------
ice_depack:	; from: menu
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers, as stub_depack does
	lea	0(a0,d0.l),a5                   ; a5 = the end of the packed data
	bsr.w	stub_first_long                 ; its last long
	cmp.l	#$49636521,d7                   ; 'Ice!'?
	bne.w	stub_depack_done                ; no: done
	adda.w	#$78,a0                         ; the output, $78 bytes on
	bsr.w	stub_first_long                 ; the unpacked length
	move.l	d7,(sp)                         ; returned in d0
	lea	0(a0,d7.l),a6                   ; a6 = the output's end
	bsr.w	stub_first_long                 ; the first long
	bra.w	stub_literals                   ; into the depacker's loop
	dc.w	$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; Pack-Ice's variables and texts.
;------------------------------------------------------------------------------
dta:	; from: menu
	dcb.b	26,0                            ; Pack-Ice's DTA
file_length:	; from: menu, progress_init, print_rate, crunch
	dc.l	$00000000                       ; the DTA's file length: the length to pack
dta_name:	; from: menu, open_file, create_file
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; the DTA's file name
	dc.w	$0000,$0000
name_input:	; from: menu
	dc.w	$3000                           ; Cconrs buffer: the maximum and the count
file_name:	; from: menu
	dcb.b	44,0                            ; the name to pack: the file selector's or the typed one
	dc.w	$0000,$0000,$3000,$0000,$0000,$0000,$0000,$0000 ; not used
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	22,0
	dc.w	$0500,$0000,$0000,$0000
newline:	; from: menu, save_packed
	dc.b	10,13,0
text_source_prompt:	; from: menu
	dc.b	13,10,10,'Enter name of source file: ',0
text_dest_prompt:
	dc.b	10,13,'Enter name of destination file: ',0 ; not used
text_no_memory:	; from: save_packed
	dc.b	'Could not allocate enough memory',10,13,0
text_working:	; from: menu
	dc.b	10,13,'Working: ',0
text_another:	; from: save_packed
	dc.b	10,13,'Crunch another file (y/N): ',0
text_relocate:	; from: menu
	dc.b	13,10,10,'Relocate program after depacking (Y/n):',0
text_menu:	; from: menu
	dc.b	10,13,'1) Crunch data file (Default)',10,13,'2) Crunch executable file'
	dc.b	10,13,'Choose:',0
text_verify_question:
	dc.b	13,10,10,'Pack files with verify (Y/n)? ',0 ; not used
text_no_mem:	; from: menu
	dc.b	'No mem!',0
text_verify:	; from: menu
	dc.b	'      Verify: ',0
text_ok:	; from: menu
	dc.b	'OK! ',0
text_error:	; from: menu
	dc.b	'Error!          [cancelled]',0
text_cannot_pack:	; from: menu
	dc.b	'      Data cannot be packed!  [cancelled]',0
	dc.b	$00
text_remaining:	; from: progress
	dcb.w	45,$1b44                        ; 45 places left, 24 right, then "Remaining: xx%"
	dcb.w	24,$1b43
	dc.b	'Remaining: '
remaining_digits:	; from: progress
	dc.b	'99%',0                         ; the percentage left
	dc.b	$00
text_time:	; from: print_time
	dcb.w	45,$1b44                        ; 45 places left, 24 right, then "Time:" and 10 places back
	dcb.w	24,$1b43
	dc.b	'Time:           '
	dc.w	$0808,$0808,$0808,$0808,$0808,$0000
text_rate:	; from: print_rate
	dc.b	'  Rate: ',0
text_saving:	; from: print_rate
	dc.b	'% [saving]',0
text_alt:	; from: save_packed
	dc.b	'      <ALT> was pressed. File is skipped.',0
text_larger:	; from: save_packed
	dc.b	'      Larger than original!   [cancelled]',0
banner:	; from: menu
	dc.b	27,'E',10
	dc.b	' ~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~'
	dc.b	'-~-~-~-~-~-~-~',13,10
	dc.b	' |   Version 1.13                                               '
	dc.b	'             |',13,10
	dc.b	' {                              P A C K - I C E                 '
	dc.b	'             }',13,10
	dc.b	' |                                                              '
	dc.b	'             |',13,10
	dc.b	' {                 This packer was written by Axe of Delight.   '
	dc.b	'             }',13,10
	dc.b	' |                   First version finished on: 14.02.1990      '
	dc.b	'             |',13,10
	dc.b	' {                   Final changes on:          20.05.1990      '
	dc.b	'             }',13,10
	dc.b	' |                                                              '
	dc.b	'             |',13,10
	dc.b	' ~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~'
	dc.b	'-~-~-~-~-~-~-~',13,10,10,0
	dc.b	$00
mouse_off:	; from: menu
	dc.w	$1200                           ; IKBD $12: mouse off
mouse_on:	; from: menu
	dc.w	$0800                           ; IKBD $08: relative mouse

	section	bss
packed_copy:	ds.b	4                       ; the verify's block: the packed data copied in and depacked there, then
                                                ;   the file read back
relocate_opcode:	ds.b	2               ; the stub's original word at stub_relocate
clear_bss_opcode:	ds.b	2               ; the stub's original word at stub_clear_bss
verify_read_buffer:	ds.b	4               ; where the verify reads the original file back
verify_flag:	ds.b	2                       ; nonzero: verify the written file
start_ticks:	ds.b	4                       ; _hz_200 when the packing started
packed_end:	ds.b	4                       ; the end of the packed data, with the stub's length for a program
file_handle:	ds.b	2                       ; the file handle
data_mode:	ds.b	2                       ; 1: packing data, 0: a program
old_ssp:	ds.b	4                       ; the supervisor stack from Super
zero_long:	ds.b	8                       ; written after a packed program as its empty relocation table
source:	ds.b	4                               ; the data to pack
dest:	ds.b	4                               ; where the packed data goes
source_end:	ds.b	10                      ; the end of the data to pack, for the progress
match_length:	ds.b	2                       ; the best string's length
match_offset:	ds.b	2                       ; and its offset
window:	ds.b	4                               ; the window: how far back strings are looked for, set to $1528 by
                                                ;   crunch
alt_pressed:	ds.b	2                       ; nonzero: Alternate was pressed while packing
too_many_literals:	ds.b	2               ; nonzero: a literal run too long to code
bss_end:

	end
