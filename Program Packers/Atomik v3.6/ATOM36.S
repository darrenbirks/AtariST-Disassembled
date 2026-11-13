; ATOM36.PRG  -  Atomik Cruncher v3.6
; Devpac source of the program, disassembled by Darren Birks, 12 November 2026.
; Text 14050 bytes, no data, bss 65816 bytes.
;
; This source rebuilds ATOM36.PRG byte for byte, header and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o ATOM36.PRG ATOM36.S
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; "ATOMIK CRUNCHER3 BY ALTAIR", "v3.6 completed on: 23/2/93": a TOS program driven by the function keys.
;   F1/F2   crunch a program or a data file chosen with the file selector
;   F3      crunch all the programs or all the files of a folder
;   F4      parameters: the offsets of up to 50 low resolution pictures in the file
;   F5      quit
;   F6      unpack a program or a data file, one or a folder's worth
; The packed format is the one Atomik v3.5 wrote: the stubs' titles say "ATOMIK v3.5", and the unpacker takes
; only files whose stub says "3.5 ".
;
; A data file is saved as 'ATM5', the unpacked length, the packed length and the packed data.  A program is
; saved as a stub (a program of its own) with the packed data after it; the stub depacks the program behind
; itself, relocates it, sets the basepage and moves it down over itself.  With pictures set the picture stub
; is used, which also turns the pictures back.
;
; The cruncher (pack) works through the file in windows of $7fff bytes.  analyse_window lists the places of
; every byte; match finds the longest match within $3f60 bytes ahead (the depacker works backward), and
; write_block writes each window as a block.  For each block it chooses:
;   - the literals: the 16 commonest bytes as 4-bit codes ("HUFFMAN DATA PACK SYSTEM") or a delta of -8..7
;     from the byte after ("RELATIF DATA PACK SYSTEM");
;   - the length split: the lengths up to it in unary, the rest in 4, 8 or 14 bits after it;
;   - the offset nibble codes: 3 bits for the 7 commonest odd low nibbles of the offsets, when that pays.
; The least gap between input and output while crunching gives the decrunch space: how far past the packed
; data the depacker needs to start, so as not to write over what it has still to read.
; A picture is first turned from four plane words to 4-bit pixels (encode_picture), which pack better.
;
; Some things in it look unfinished:
;   - find_file leaves a word on the stack when a file is longer than the memory free: after "FREE MEMORY <
;     LENGHT FILE" its rts does not return where it should.
;   - match_report (UNDO while searching) writes $ff4 at interrupted-$2291, which is the cmp.l #$ff4 in
;     emit_block, not min_gap; it holds $ff4 already, so nothing changes.
;   - match_try's case for a 2-byte match running past the reach never runs: it needs the best length to be
;     negative.
;   - total_ticks is never cleared: the total crunching time shown after F3 counts every file crunched since
;     the start.
;   - F1 in the parameters ("EXTENDS FOR PARAMETERS") only waits for a key.
;   - The picture stub takes the pictures' offsets off a4, which it then does not use.
;   - The stub does not clear the program's bss: the relocation table's bytes are cleared as they are read,
;     and the mover clears only itself.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$066d  the start-up, the menus, unpacking, the time, printing, keys, the file selector, memory
;   $066e-$0b73  load and write, hex, the progress, UNDO, the parameters, input, crunch all, find
;   $0b74-$0ec3  crunch_file and the pictures
;   $0ec4-$1767  the cruncher: pack, match, write_block and its choices, emit_block, the bit writers,
;                encode_picture, the percentage, analyse_window
;   $1768-$1f67  the search's tables
;   $1f68-$218d  unpack
;   $218e-$247f  the picture stub (offset_steps at its end)
;   $2480-$270f  the normal stub
;   $2710-$2d91  the cruncher's counts and variables
;   $2d92-$36e1  the texts, the AES block, the names and the variables
;   bss          not used, then positions (the places listed by analyse_window)
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; start: memory shrunk and taken, mouse shown, the DTA set and the resolution kept, then the main menu.
;------------------------------------------------------------------------------
start:
	movea.l	4(sp),a5                        ; the basepage
	bsr.w	init_memory                     ; memory
	bsr.w	mouse_on                        ; mouse on
	bsr.w	set_dta                         ; the DTA
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.w	#2,sp
	move.w	d0,resolution                   ; kept

;------------------------------------------------------------------------------
; main_menu: F1 crunch a program, F2 crunch a data file, F3 crunch all, F4 parameters, F5 quit,
; F6 the unpack menu.
;------------------------------------------------------------------------------
main_menu:	; from: unpack_menu, load_chosen, parameters_menu, crunch_all_menu
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	main_menu_text(pc),a0           ; "F1: CRUNCH EXECUTABLE." ...
	bsr.w	print
	clr.w	largest_space                   ; no files counted
main_menu_key:
	bsr.w	get_key                         ; a key
	swap	d0                              ; its scan code
	cmp.w	#$3b,d0                         ; F1?
	beq.w	crunch_program                  ; crunch a program
	cmp.w	#$3c,d0                         ; F2?
	beq.w	crunch_data_file                ; crunch a data file
	cmp.w	#$3d,d0                         ; F3?
	beq.w	crunch_all_menu                 ; crunch all
	cmp.w	#$3e,d0                         ; F4?
	beq.w	parameters_menu                 ; the parameters
	cmp.w	#$3f,d0                         ; F5?
	beq.w	quit                            ; quit
	cmp.w	#$40,d0                         ; F6?
	beq.s	unpack_menu_enter               ; yes
	bra.s	main_menu_key                   ; no: another key
unpack_menu_enter:
	subi.l	#$1000,load_buffer              ; unpacking loads $1000 lower: no room for a stub needed

;------------------------------------------------------------------------------
; unpack_menu: F1 unpack a program, F2 unpack a data file, F3 unpack all, F4 back.
;------------------------------------------------------------------------------
unpack_menu:	; from: unpack_all_menu, print_unpack_counts
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	unpack_menu_text(pc),a0         ; "F1: UNPACK EXECUTABLE." ...
	bsr.w	print
unpack_menu_key:
	bsr.w	get_key                         ; a key
	swap	d0                              ; its scan code
	cmp.w	#$3b,d0                         ; F1?
	beq.w	unpack_one_program              ; unpack a program
	cmp.w	#$3c,d0                         ; F2?
	beq.w	unpack_one_data                 ; unpack a data file
	cmp.w	#$3d,d0                         ; F3?
	beq.s	unpack_all_menu                 ; unpack all
	cmp.w	#$3e,d0                         ; F4?
	bne.s	unpack_menu_key                 ; no: another key
	addi.l	#$1000,load_buffer              ; the load buffer back up $1000
	bra.w	main_menu                       ; the main menu

;------------------------------------------------------------------------------
; unpack_all_menu: F1 unpack every program of a folder, F2 every file, F3 choose the folder, F4 back.
;------------------------------------------------------------------------------
unpack_all_menu:	; from: unpack_menu
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	unpack_all_menu_text(pc),a0     ; "F1: UNPACK ALL IN EXEC MODE" ...
	bsr.w	print
unpack_all_menu_key:
	bsr.w	get_key                         ; a key
	swap	d0                              ; its scan code
	cmp.w	#$3b,d0                         ; F1?
	beq.s	unpack_all_programs             ; programs
	cmp.w	#$3c,d0                         ; F2?
	beq.s	unpack_all_data                 ; data files
	cmp.w	#$3d,d0                         ; F3?
	beq.s	unpack_all_choose_folder        ; the folder
	cmp.w	#$3e,d0                         ; F4?
	bne.s	unpack_all_menu_key             ; no: another key
	bra.s	unpack_menu                     ; back to the unpack menu
unpack_all_choose_folder:
	lea	any_mask(pc),a3                 ; "*.*"
	bsr.w	choose_file                     ; fsel_input: the folder set
	bra.s	unpack_all_menu                 ; the menu again
unpack_all_data:
	lea	any_mask(pc),a0                 ; "*.*"
	lea	any_mask(pc),a3
	sf	unpack_program_mode             ; data mode
	bra.s	unpack_all
unpack_all_programs:
	lea	program_mask(pc),a0             ; "*.PRG"
	lea	program_mask(pc),a3
	st	unpack_program_mode             ; program mode
unpack_all:
	lea	full_name(pc),a1                ; the mask into the name
unpack_all_copy_mask:
	move.b	(a0)+,(a1)+                     ; copied
	bne.s	unpack_all_copy_mask
	st	batch                           ; batch: no questions
	lea	files_done(pc),a0               ; the files counted
	clr.w	(a0)                            ; none unpacked
	clr.w	-$2(a0)                         ; none loaded
	bsr.w	find_first                      ; Fsfirst
	bpl.s	unpack_all_next                 ; found?
	lea	empty_folder_text(pc),a0        ; "HEY! EMPTY DIRECTORY!"
	bsr.w	print
	bsr.w	get_key                         ; a key
	bra.w	unpack_all_menu                 ; the menu again
unpack_all_next:
	move.b	unpack_program_mode(pc),d0      ; program mode?
	bne.s	unpack_all_program              ; yes
	bsr.w	unpack_data                     ; unpack a data file
	bra.s	unpack_all_find
unpack_all_program:
	bsr.w	unpack_program                  ; unpack a program
unpack_all_find:
	bsr.w	find_next                       ; Fsnext
	beq.s	unpack_all_next                 ; another: unpack it
	bsr.s	print_unpack_counts             ; the counts
	bsr.w	bell_flush                      ; wait for a key
	bsr.w	get_key
	bra.w	unpack_all_menu                 ; the menu again

;------------------------------------------------------------------------------
; print_unpack_counts: "OK n FILE(S) UNPACKED" and "IN n FILE(S) LOADED".
;------------------------------------------------------------------------------
print_unpack_counts:	; from: unpack_all_menu
	lea	ok_text(pc),a0                  ; "OK "
	bsr.w	print
	move.w	files_done(pc),d2               ; the files unpacked
	bsr.w	print_count                     ; printed
	lea	files_unpacked_text(pc),a0      ; " FILE(S) UNPACKED"
	bsr.w	print
	lea	in_text(pc),a0                  ; "IN "
	bsr.w	print
	move.w	files_loaded(pc),d2             ; the files loaded
	bsr.w	print_count                     ; printed
	lea	files_loaded_text(pc),a0        ; " FILE(S) LOADED"
	bsr.w	print
	rts
unpack_one_program:	; from: unpack_menu
	lea	program_mask(pc),a3             ; "*.PRG"
	sf	batch                           ; asking
	lea	files_done(pc),a0               ; the counts
	clr.w	(a0)                            ; cleared
	clr.w	-$2(a0)
	bsr.s	unpack_program                  ; unpack a program
	bra.w	unpack_menu                     ; the menu again
unpack_one_data:	; from: unpack_menu
	lea	any_mask(pc),a3                 ; "*.*"
	sf	batch                           ; asking
	lea	files_done(pc),a0               ; the counts
	clr.w	(a0)                            ; cleared
	clr.w	-$2(a0)
	bsr.s	unpack_data                     ; unpack a data file
	bra.w	unpack_menu                     ; the menu again

;------------------------------------------------------------------------------
; unpack_data: loads a file and unpacks it if it starts 'ATM5'.
;------------------------------------------------------------------------------
unpack_data:	; from: unpack_all_menu, print_unpack_counts
	bsr.w	load_counted                    ; loaded
	bmi.w	unpack_skip                     ; not
	movea.l	load_buffer(pc),a0              ; the file
	cmpi.l	#$41544d35,(a0)                 ; 'ATM5'?
	beq.s	unpack_data_go                  ; yes
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	not_atomik_text(pc),a0          ; "THIS IS NOT AN ATOMIK V3.5 PACKED FILE!"
	bsr.w	print
	move.b	batch(pc),d0                    ; batch?
	bne.w	unpack_skip                     ; yes: next
	bra.w	unpack_key                      ; no: a key
unpack_data_go:
	lea	4(a0),a1                        ; the unpacked length after 'ATM5'
	bra.w	unpack_file                     ; unpack

;------------------------------------------------------------------------------
; unpack_program: loads a program and unpacks it if its stub is Atomik's: bra.s at the start, at $ea
; "adda.l d0,a6/link a2" and "3.5 " in the stub's title (at $2cc for the picture stub, $27a for the
; normal one).  The normal stub has lea 2(a5),a5 at $f0; the picture stub has the picture count.
;------------------------------------------------------------------------------
unpack_program:	; from: unpack_all_menu, print_unpack_counts
	bsr.w	load_counted                    ; loaded
	bmi.w	unpack_skip                     ; not
	movea.l	load_buffer(pc),a0              ; the file
	cmpi.w	#$601a,(a0)                     ; a program (bra.s over the header)?
	beq.s	unpack_program_check            ; yes
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	not_program_text(pc),a0         ; "NOT AN EXECUTABLE FILE!"
	bsr.w	print
	move.b	batch(pc),d0                    ; batch?
	bne.w	unpack_skip                     ; yes: next
	bra.w	unpack_key                      ; no: a key
unpack_program_check:
	cmpi.l	#$ddc04e52,$ea(a0)              ; Atomik's depacker?
	beq.s	unpack_program_version          ; yes
unpack_program_not_atomik:
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	not_atomik_text(pc),a0          ; "THIS IS NOT AN ATOMIK V3.5 PACKED FILE!"
	bsr.w	print
	move.b	batch(pc),d0                    ; batch?
	bne.s	unpack_skip                     ; yes: next
	bra.s	unpack_key                      ; no: a key
unpack_program_version:
	cmpi.l	#$332e3520,$2cc(a0)             ; "3.5 " in the picture stub's title?
	beq.s	unpack_program_stub             ; yes
	cmpi.l	#$332e3520,$27a(a0)             ; in the normal stub's title?
	bne.s	unpack_program_not_atomik       ; no
unpack_program_stub:
	cmpi.w	#$4bed,$f0(a0)                  ; the normal stub (lea 2(a5),a5)?
	bne.s	unpack_program_length           ; no: the picture stub
	st	unpack_no_pictures              ; yes: no pictures to restore
unpack_program_length:
	movea.l	a0,a1                           ; the stub's "lea data(pc),a0" displacement
	lea	$4e(a1),a1
	adda.w	(a1),a1                         ; the packed data
	move.l	(a1),d0                         ; its unpacked length
	cmp.l	memory_free(pc),d0              ; room?
	ble.s	unpack_file                     ; yes
	lea	no_room_text(pc),a0             ; "NOT ENOUGHT MEMORY TO UNPACK THIS FILE!"
	bsr.w	print
	move.b	batch(pc),d0                    ; batch?
	bne.s	unpack_skip                     ; yes: next
	bra.s	unpack_key                      ; no: a key
unpack_file:	; from: unpack_data
	pea	(a0)                            ; the buffer kept
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	unpacking_text(pc),a0           ; "UNPACKING : "
	bsr.w	print
	lea	full_name(pc),a0                ; the name
	bsr.w	print
	movea.l	(sp)+,a0
	movea.l	4(a1),a2                        ; the packed length
	lea	8(a1,a2.l),a2                   ; the packed data's end
	bsr.w	unpack                          ; unpacked
	bsr.w	save_unpacked                   ; saved
	rts
unpack_key:	; from: unpack_data
	bsr.w	get_key                         ; a key
unpack_skip:	; from: unpack_data
	subq.w	#1,files_done                   ; not unpacked
	rts

;------------------------------------------------------------------------------
; load_counted: one more file unpacked and loaded, then loaded.
;------------------------------------------------------------------------------
load_counted:	; from: unpack_data, unpack_program
	lea	files_done(pc),a0               ; the counts
	addq.w	#1,(a0)                         ; unpacked
	addq.w	#1,-$2(a0)                      ; loaded
	bsr.s	load_chosen
	rts

;------------------------------------------------------------------------------
; load_chosen: chooses a file (not in batch) and loads it.  Returns d0 its length, or -1 (minus).
;------------------------------------------------------------------------------
load_chosen:	; from: load_counted
	move.l	a3,file_mask                    ; the mask kept
	move.b	batch(pc),d0                    ; batch?
	bne.s	load_chosen_name                ; yes: the file found
	bsr.w	choose_file                     ; fsel_input
	tst.w	d0                              ; OK?
	bne.s	load_chosen_fail                ; no
load_chosen_name:
	bsr.w	make_name                       ; the path and name
	bsr.w	load_file                       ; loaded
	move.b	io_error(pc),d0                 ; an error?
	beq.s	load_chosen_done                ; no
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	read_error_text(pc),a0          ; "READ ERROR! "
	bsr.w	print
	move.b	batch(pc),d0                    ; batch?
	bne.s	load_chosen_fail                ; yes
	bsr.w	get_key                         ; no: a key
load_chosen_fail:
	moveq	#-1,d0                          ; not loaded
	rts
load_chosen_done:
	move.l	file_length(pc),d0              ; its length
	rts
crunch_data_file:	; from: main_menu
	st	data_mode                       ; data mode
	lea	any_mask(pc),a3                 ; "*.*"
	bra.s	crunch_chosen
crunch_program:	; from: main_menu
	sf	data_mode                       ; program mode
	lea	program_mask(pc),a3             ; "*.PRG"
crunch_chosen:
	move.l	a3,file_mask                    ; the mask kept
	bsr.w	choose_file                     ; fsel_input
	tst.w	d0                              ; OK?
	bne.w	main_menu                       ; no: the menu
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	sf	batch                           ; not batch
	bsr.w	crunch_file                     ; crunch it
	bra.w	main_menu                       ; the menu

;------------------------------------------------------------------------------
; save_unpacked: "SAVE LENGTH:" and, unless batch, asks to save the unpacked file under a name chosen.
;------------------------------------------------------------------------------
save_unpacked:	; from: unpack_program
	move.l	d0,save_length                  ; the unpacked length kept
	lea	save_length_text(pc),a0         ; "SAVE LENGTH: "
	bsr.w	print
	move.l	save_length(pc),d0
	bsr.w	print_hex                       ; in hex
	move.b	batch(pc),d0                    ; batch?
	bne.s	save_unpacked_write             ; yes: saved under its own name
	lea	save_unpacked_text(pc),a0       ; "SAVE UNPACKED FILE? (Y/N)"
	bsr.w	print
save_unpacked_key:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.s	save_unpacked_choose            ; yes
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	save_unpacked_key               ; no: another key
	bra.s	save_unpacked_done              ; not saved
save_unpacked_choose:
	movea.l	file_mask(pc),a3                ; the mask
	bsr.w	choose_file                     ; fsel_input
	tst.w	d0                              ; OK?
	bne.s	save_unpacked_done              ; no
	lea	title_text(pc),a0               ; the title
	bsr.w	print
save_unpacked_write:
	bsr.w	make_name                       ; the path and name
	movea.l	load_buffer(pc),a2              ; the buffer
	move.l	save_length(pc),d2              ; the length
	bsr.w	write_file                      ; written
	tst.b	io_error                        ; an error?
	bne.s	save_unpacked_error             ; yes
	move.b	batch(pc),d0                    ; batch?
	bne.s	save_unpacked_done              ; yes: done
	lea	file_text(pc),a0                ; "FILE: "
	bsr.w	print
	lea	full_name(pc),a0                ; the name
	bsr.w	print
	lea	saved_text(pc),a0               ; " SAVED"
	bsr.w	print
	bsr.w	get_key                         ; a key
save_unpacked_done:
	rts
save_unpacked_error:
	lea	write_error_text(pc),a0         ; "WRITE ERROR! RETRY (Y/N)"
	bsr.w	print
save_unpacked_retry_key:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.w	save_unpacked                   ; yes: again
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	save_unpacked_retry_key         ; no: another key
	bra.s	save_unpacked_done              ; given up

;------------------------------------------------------------------------------
; print_total_time: "CRUNCHING TIME:" for all the files crunched.
;------------------------------------------------------------------------------
print_total_time:	; from: crunch_all_menu
	lea	crunching_time_text(pc),a4      ; "CRUNCHING TIME: "
	move.l	total_ticks(pc),d0              ; the total, in 200 Hz ticks
	bra.s	print_ticks

;------------------------------------------------------------------------------
; print_time: "CRUNCHING TIME:" for this file, added to the total.  The time is h:mm:ss.
;------------------------------------------------------------------------------
print_time:	; from: crunch_file
	lea	crunching_time_text(pc),a4      ; "CRUNCHING TIME: "
	lea	read_end_time(pc),a0            ; the time now
	bsr.w	supervisor_call                 ; from the supervisor
	move.l	end_ticks(pc),d0                ; the end
	sub.l	start_ticks(pc),d0              ; less the start
	add.l	d0,total_ticks                  ; added to the total
print_ticks:	; from: print_total_time
	moveq	#0,d2                           ; seconds = ticks/200
	lsr.l	#3,d0                           ; /8
	moveq	#25,d1                          ; /25 by subtraction
print_ticks_seconds:
	sub.l	d1,d0
	bmi.s	print_ticks_split
	addq.l	#1,d2
	bra.s	print_ticks_seconds
print_ticks_split:
	divu.w	#$3c,d2                         ; minutes, seconds
	swap	d2                              ; the seconds
	move.w	d2,-(sp)                        ; kept
	clr.w	d2                              ; the minutes
	swap	d2
	divu.w	#$3c,d2                         ; hours, minutes
	lea	time_text(pc),a0                ; the text
	bsr.s	put_bcd3                        ; the hours, in BCD
	swap	d2                              ; the minutes
	bsr.s	to_bcd                          ; in BCD
	bsr.s	put_bcd2                        ; two digits
	move.w	(sp)+,d2                        ; the seconds
	bsr.s	to_bcd                          ; in BCD
	bsr.s	put_bcd2                        ; two digits
	clr.b	-(a0)                           ; the last ':' cut
	movea.l	a4,a0                           ; "CRUNCHING TIME: "
	bsr.w	print
	lea	time_text(pc),a0                ; the time
	bsr.s	print
	rts

;------------------------------------------------------------------------------
; put_bcd3: the decimal d2 into the text at a0 as three digits (the first a space if 0), then ':'.
;------------------------------------------------------------------------------
put_bcd3:	; from: print_time
	bsr.s	to_bcd                          ; in BCD
	move.w	d3,d4                           ; the hundreds
	lsr.w	#8,d4
	bne.s	put_bcd3_digit                  ; any?
	moveq	#-16,d4                         ; no: a space ('0'-16)
put_bcd3_digit:
	addi.w	#$30,d4
	move.b	d4,(a0)+

;------------------------------------------------------------------------------
; put_bcd2: the BCD d3's two last digits into the text at a0, then ':'.
;------------------------------------------------------------------------------
put_bcd2:	; from: print_time
	move.w	d3,d4                           ; the tens
	lsr.w	#4,d4
	andi.w	#$f,d4
	addi.w	#$30,d4                         ; as a digit
	move.b	d4,(a0)+
	move.w	d3,d4                           ; the units
	andi.w	#$f,d3
	addi.w	#$30,d3                         ; as a digit
	move.b	d3,(a0)+
	move.b	#$3a,(a0)+                      ; ':'
	rts

;------------------------------------------------------------------------------
; to_bcd: the word d2 in BCD into d3.
;------------------------------------------------------------------------------
to_bcd:	; from: print_time, put_bcd3, ask_picture_offset, print_count, crunch_file, crunch_pictures, 1 more
	move.w	d1,-(sp)                        ; kept
	move.l	d2,-(sp)
	ext.l	d2                              ; as a long
	moveq	#0,d3                           ; the BCD
	clr.w	d1                              ; the shift
to_bcd_digit:
	divu.w	#$a,d2                          ; the next digit
	swap	d2                              ; it
	lsl.w	d1,d2                           ; to its place
	or.w	d2,d3                           ; in
	addq.w	#4,d1                           ; the next place
	clr.w	d2                              ; the quotient
	swap	d2
	tst.w	d2                              ; more?
	bne.s	to_bcd_digit                    ; yes
	move.l	(sp)+,d2
	move.w	(sp)+,d1
	rts

;------------------------------------------------------------------------------
; supervisor_call: runs the routine at a0 in the supervisor (Supexec).
;------------------------------------------------------------------------------
supervisor_call:	; from: print_time, crunch_file
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	pea	(a0)                            ; the routine
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.w	#6,sp
	movem.l	(sp)+,d0-d7/a0-a6
	rts
read_start_time:	; from: crunch_file
	move.l	$4ba.w,start_ticks              ; _hz_200, the clock at the start
	rts
read_end_time:	; from: print_time
	move.l	$4ba.w,end_ticks                ; _hz_200, the clock at the end
	rts

;------------------------------------------------------------------------------
; print: prints the text at a0 (Cconws), every register kept.
;------------------------------------------------------------------------------
print:	; from: main_menu, unpack_menu, unpack_all_menu, print_unpack_counts, unpack_data, unpack_program, 22 more
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	pea	(a0)                            ; the text
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.w	#6,sp
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; get_key: waits for a key (Crawcin): d0 the scan code in the high word, ASCII in the low.
;------------------------------------------------------------------------------
get_key:	; from: main_menu, unpack_menu, unpack_all_menu, unpack_program, load_chosen, save_unpacked, 9 more
	movem.l	d1-d7/a0-a6,-(sp)               ; saved
	move.w	#$7,-(sp)
	trap	#1                              ; Crawcin
	addq.w	#2,sp
	movem.l	(sp)+,d1-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; choose_file: the file selector with the path of the current folder and the mask at a3.  d0 0 for
; OK (the drive and folder chosen are set), -1 for Cancel.
;------------------------------------------------------------------------------
choose_file:	; from: unpack_all_menu, load_chosen, save_unpacked, crunch_all_menu, print_text_hex_word
	movem.l	d1-d3/a0-a2,-(sp)               ; saved
	bsr.w	mouse_off                       ; mouse off
	bsr.s	get_path                        ; the current path
	lea	path_text(pc),a2                ; the path
	tst.b	(a2)+                           ; empty?
	beq.s	choose_file_mask                ; yes
choose_file_end:
	tst.b	(a2)+                           ; to its end
	bne.s	choose_file_end
choose_file_mask:
	move.b	#$5c,-$1(a2)                    ; '\'
choose_file_copy_mask:
	move.b	(a3)+,(a2)+                     ; the mask
	bne.s	choose_file_copy_mask
	lea	aes_block(pc),a0                ; the AES block
	move.l	a0,d1
	move.w	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	bsr.w	mouse_on                        ; mouse on
	tst.w	fsel_button                     ; OK?
	beq.s	choose_file_cancel              ; no
	bsr.s	set_path                        ; the drive and folder set
	moveq	#0,d0                           ; OK
	bra.s	choose_file_done
choose_file_cancel:
	moveq	#-1,d0                          ; Cancel
choose_file_done:
	movem.l	(sp)+,d1-d3/a0-a2
	rts

;------------------------------------------------------------------------------
; set_path: the drive and folder of the path chosen made current (Dsetdrv, Dsetpath).
;------------------------------------------------------------------------------
set_path:	; from: choose_file
	lea	path_text(pc),a1                ; the path
	moveq	#0,d0
	move.b	(a1)+,d0                        ; its drive
	pea	(a1)
	subi.w	#$41,d0                         ; letter to number
	move.w	d0,-(sp)
	move.w	#$e,-(sp)
	trap	#1                              ; Dsetdrv
	addq.w	#4,sp
	movea.l	(sp)+,a1
set_path_mask:
	move.b	(a1)+,d0                        ; to the mask
	beq.s	set_path_folder
	cmp.b	#$2a,d0                         ; '*'?
	bne.s	set_path_mask                   ; no
	clr.b	-(a1)                           ; cut there
set_path_folder:
	pea	path_text(pc)                   ; the folder
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.w	#6,sp
	rts

;------------------------------------------------------------------------------
; get_path: the current drive and folder into the path ("A:\FOLDER").
;------------------------------------------------------------------------------
get_path:	; from: choose_file, make_name
	movem.l	a0-a2,-(sp)                     ; saved
	lea	path_text(pc),a1                ; the path
	movea.l	a1,a2
	moveq	#64,d0                          ; 65 bytes
get_path_clear:
	clr.b	(a1)+                           ; cleared
	dbra	d0,get_path_clear
	move.w	#$19,-(sp)
	trap	#1                              ; Dgetdrv
	addq.w	#2,sp
	addi.w	#$41,d0                         ; as a letter
	move.b	d0,(a2)+
	move.b	#$3a,(a2)+                      ; ':'
	clr.w	-(sp)                           ; the current drive
	pea	(a2)                            ; after it
	move.w	#$47,-(sp)
	trap	#1                              ; Dgetpath
	addq.w	#8,sp
	movem.l	(sp)+,a0-a2
	rts

;------------------------------------------------------------------------------
; make_name: the current drive and folder and the name chosen into the full name.
;------------------------------------------------------------------------------
make_name:	; from: load_chosen, save_unpacked, crunch_file, print_text_hex_word
	lea	full_name(pc),a0                ; the full name
	lea	path_text(pc),a1                ; the path
	bsr.s	get_path                        ; the current path
	move.b	(a1)+,(a0)+                     ; the drive
	move.b	(a1)+,(a0)+                     ; ':'
	tst.b	(a1)                            ; a folder?
	beq.s	make_name_name                  ; no
make_name_copy_path:
	move.b	(a1)+,(a0)+                     ; the folder
	bne.s	make_name_copy_path
	subq.w	#1,a0                           ; back to its 0
make_name_name:
	move.b	#$5c,(a0)+                      ; '\'
	lea	chosen_name(pc),a1              ; the name chosen
make_name_copy_name:
	move.b	(a1)+,(a0)+                     ; copied
	bne.s	make_name_copy_name
	rts

;------------------------------------------------------------------------------
; mouse_on: shows the mouse (Line-A $a).
;------------------------------------------------------------------------------
mouse_on:	; from: start, choose_file, load_file, write_file
	movem.l	d0-d2/a0-a2,-(sp)
	dc.w	$a00a                           ; Line-A $a, show mouse
	movem.l	(sp)+,d0-d2/a0-a2
	rts

;------------------------------------------------------------------------------
; mouse_off: hides the mouse (Line-A $9).
;------------------------------------------------------------------------------
mouse_off:	; from: choose_file, malloc, load_file, write_file
	movem.l	d0-d2/a0-a2,-(sp)
	dc.w	$a009                           ; Line-A $9, hide mouse
	movem.l	(sp)+,d0-d2/a0-a2
	rts

;------------------------------------------------------------------------------
; init_memory: the program shrunk to its size, then all memory left taken.
;------------------------------------------------------------------------------
init_memory:	; from: start
	bsr.s	shrink
	bsr.s	take_memory
	rts

;------------------------------------------------------------------------------
; shrink: Mshrink to the basepage, text, data and bss.
;------------------------------------------------------------------------------
shrink:	; from: init_memory
	moveq	#64,d0                          ; 64
	lsl.w	#2,d0                           ; *4: the basepage's 256
	add.l	$c(a5),d0                       ; + the text
	add.l	$14(a5),d0                      ; + the data
	add.l	$1c(a5),d0                      ; + the bss
	move.l	d0,-(sp)                        ; the size
	pea	(a5)                            ; the basepage
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
	rts

;------------------------------------------------------------------------------
; take_memory: the largest block less $2a58 taken: the load buffer starts $1000 into it (room for a stub
; in front).
;------------------------------------------------------------------------------
take_memory:	; from: init_memory
	moveq	#-1,d0                          ; -1
	bsr.s	malloc                          ; Malloc(-1): the largest block
	subi.l	#$2a58,d0                       ; less $2a58
	bmi.s	take_memory_none                ; none: "out of memory!"
	move.l	d0,d1
	subi.l	#$1000,d1                       ; less $1000
	move.l	d1,memory_free                  ; the room for a file
	bsr.s	malloc                          ; Malloc
	lea	load_buffer(pc),a0
	move.l	d0,(a0)                         ; the load buffer
	addi.l	#$1000,(a0)                     ; $1000 in
	move.l	d0,4(a0)                        ; the block
	rts
take_memory_none:
	lea	out_of_memory_text(pc),a0       ; "out of memory!"
	bsr.w	print
	bsr.w	get_key                         ; a key
	bra.s	quit                            ; quit

;------------------------------------------------------------------------------
; malloc: Malloc(d0).
;------------------------------------------------------------------------------
malloc:	; from: take_memory
	move.l	d0,-(sp)                        ; the size
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.w	#6,sp
	rts
quit:	; from: main_menu, take_memory
	bsr.w	mouse_off                       ; mouse off
	clr.w	-(sp)
	trap	#1                              ; Pterm0

;------------------------------------------------------------------------------
; load_file: loads the file named in full_name into the load buffer (the first found again in batch).
; file_length is its length; io_error is set if it fails.
;------------------------------------------------------------------------------
load_file:	; from: load_chosen, crunch_file
	bsr.w	mouse_off                       ; mouse off
	tst.b	batch                           ; batch?
	bne.s	load_file_open                  ; yes: found already
	bsr.w	find_first                      ; Fsfirst: its length
	tst.w	d0                              ; found?
	bmi.s	load_file_fail                  ; no
load_file_open:
	move.w	#$2,-(sp)                       ; read/write
	pea	full_name(pc)                   ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.w	#8,sp
	tst.w	d0                              ; opened?
	bmi.s	load_file_fail                  ; no
	move.w	d0,file_handle                  ; the handle
	move.l	load_buffer(pc),-(sp)           ; the load buffer
	move.l	dta_length(pc),-(sp)            ; its length
	move.w	d0,-(sp)                        ; the handle
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	lea	$c(sp),sp
	tst.l	d0                              ; read?
	bmi.s	load_file_read_error            ; no
	move.l	d0,file_length                  ; the length read
	bra.w	close_file                      ; closed
load_file_read_error:
	st	io_error                        ; failed
load_file_fail:
	bsr.w	mouse_on                        ; mouse on
	st	io_error                        ; failed
	rts

;------------------------------------------------------------------------------
; write_file: writes d2 bytes from a2 to the file named in full_name.  io_error is set if the write
; fails; d0 is minus if the create or the close fails.
;------------------------------------------------------------------------------
write_file:	; from: save_unpacked, print_text_hex_word
	bsr.w	mouse_off                       ; mouse off
	sf	io_error                        ; no error
	clr.w	-(sp)                           ; normal file
	pea	full_name(pc)                   ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.w	#8,sp
	tst.w	d0                              ; created?
	bpl.s	write_file_created              ; yes
	bsr.w	mouse_on                        ; mouse on
	moveq	#-1,d0                          ; failed
	bra.s	write_file_done
write_file_created:
	move.w	d0,file_handle                  ; the handle
	pea	(a2)                            ; the data
	move.l	d2,-(sp)                        ; its length
	move.w	d0,-(sp)                        ; the handle
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	tst.l	d0                              ; written?
	bpl.s	close_file                      ; yes
	st	io_error                        ; no
close_file:	; from: load_file
	bsr.w	mouse_on                        ; mouse on
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.w	#4,sp
	tst.w	d0                              ; closed?
write_file_done:
	rts

;------------------------------------------------------------------------------
; print_hex: prints the long d0 in hex, leading zeros as spaces, after a space.
;------------------------------------------------------------------------------
print_hex:	; from: save_unpacked, print_crunch_left, print_crunch_done, crunch_file
	moveq	#0,d3                           ; no digit yet
	lea	hex_text(pc),a0                 ; the text
	lea	hex_text+1(pc),a1               ; its digits
	moveq	#7,d2                           ; 8 digits
print_hex_digit:
	rol.l	#4,d0                           ; the next digit
	move.w	d0,d1
	andi.w	#$f,d1
	tst.w	d3                              ; one printed already?
	bne.s	print_hex_letter                ; yes
	tst.w	d1                              ; a 0?
	bne.s	print_hex_first                 ; no
	tst.w	d2                              ; the last?
	beq.s	print_hex_ascii                 ; yes: '0'
	move.b	#$20,(a1)+                      ; a space
	bra.s	print_hex_next
print_hex_first:
	moveq	#-1,d3                          ; digits from here
print_hex_letter:
	cmp.b	#$9,d1                          ; A-F?
	bls.s	print_hex_ascii                 ; no
	addq.w	#7,d1                           ; 'A'-'0'-10
print_hex_ascii:
	addi.w	#$30,d1
	move.b	d1,(a1)+
print_hex_next:
	dbra	d2,print_hex_digit
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; print_crunch_left: "CRUNCH LEFT:" the bytes from a4 to the end, as a length and a percentage; the next
; report when a4 passes $1fd further on.
;------------------------------------------------------------------------------
print_crunch_left:	; from: pack, match_report
	move.l	input_end(pc),d0                ; the end
	sub.l	a4,d0                           ; less where the search is
	move.l	d0,crunch_left                  ; left
	lea	$1fd(a4),a4                     ; $1fd on
	move.l	a4,next_report                  ; the next report
	lea	crunch_left_text(pc),a0         ; "CRUNCH LEFT: "
	bsr.w	print
	move.l	crunch_left(pc),d0              ; the bytes left
	move.l	d0,-(sp)
	bsr.s	print_hex                       ; in hex
	move.l	crunch_length(pc),d0            ; the file's length
	move.l	(sp)+,d1                        ; the bytes left
	sub.l	d0,d1                           ; the bytes done
	neg.l	d1
	bsr.w	print_percent                   ; as a percentage
	rts

;------------------------------------------------------------------------------
; print_crunch_done: "CRUNCH DONE:" the output so far (a5 from the work memory's start) as a length and a
; percentage of the file.
;------------------------------------------------------------------------------
print_crunch_done:	; from: check_undo, pack
	lea	crunch_done_text(pc),a0         ; "CRUNCH DONE: "
	bsr.w	print
	move.l	a5,d0                           ; the output's end
	movea.l	work_memory(pc),a0              ; the work memory
	sub.l	a0,d0                           ; its length
	move.l	d0,-(sp)
	bsr.w	print_hex                       ; in hex
	move.l	(sp)+,d1
	move.l	crunch_length(pc),d0            ; the file's length
	bsr.w	print_percent                   ; as a percentage
	rts

;------------------------------------------------------------------------------
; check_undo: the progress shown; UNDO pressed asks "INTERUPTION? (Y/N)" and Y stops the crunch.
;------------------------------------------------------------------------------
check_undo:	; from: next_word
	movem.l	d1-d3/a0-a4,-(sp)               ; saved
	bsr.s	print_crunch_done               ; "CRUNCH DONE:"
check_undo_key:
	move.w	#$ff,-(sp)                      ; $ff: a key if any
	move.w	#$6,-(sp)
	trap	#1                              ; Crawio
	addq.w	#4,sp
	swap	d0                              ; its scan code
	cmp.w	#$61,d0                         ; UNDO?
	beq.s	check_undo_ask                  ; yes
	tst.l	d0                              ; a key?
	bne.s	check_undo_key                  ; yes: the next
	bra.s	check_undo_done                 ; no
check_undo_ask:
	lea	interruption_text(pc),a0        ; "INTERUPTION? (Y/N)"
	bsr.w	print
check_undo_answer:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.s	check_undo_stop                 ; yes
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	check_undo_answer               ; no: another key
	bra.s	check_undo_done                 ; carry on
check_undo_stop:
	st	interrupted                     ; interrupted
	move.w	#$ff4,min_gap                   ; the decrunch space back to none
check_undo_done:
	movem.l	(sp)+,d1-d3/a0-a4
	rts

;------------------------------------------------------------------------------
; parameters_menu: F1 "extends" (nothing: a key back), F2 set the pictures' offsets, F3 clear them, F4 back.
;------------------------------------------------------------------------------
parameters_menu:	; from: main_menu, set_pictures
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	parameters_menu_text(pc),a0     ; "F1: EXTENDS FOR PARAMETERS" ...
	bsr.w	print
parameters_menu_key:
	bsr.w	get_key                         ; a key
	swap	d0                              ; its scan code
	cmp.w	#$3b,d0                         ; F1?
	beq.s	parameters_extends              ; yes
	cmp.w	#$3c,d0                         ; F2?
	beq.s	set_pictures                    ; the pictures
	cmp.w	#$3d,d0                         ; F3?
	beq.s	clear_parameters                ; clear
	cmp.w	#$3e,d0                         ; F4?
	bne.s	parameters_menu_key             ; no: another key
	bra.w	main_menu                       ; the main menu
clear_parameters:
	lea	clear_parameters_text(pc),a0    ; "CLEAR PARAMETERS? (Y/N)"
	bsr.w	print
clear_parameters_key:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$4e,d0                         ; 'N'?
	beq.s	parameters_menu                 ; yes: the menu
	cmp.w	#$59,d0                         ; 'Y'?
	bne.s	clear_parameters_key            ; no: another key
	lea	parameters_cleared_text(pc),a0  ; "PARAMETERS CLEARED!"
	bsr.w	print
	clr.b	picture_count                   ; no pictures
	bsr.w	get_key                         ; a key
	bra.s	parameters_menu                 ; the menu
parameters_extends:
	lea	title_text(pc),a0               ; the screen cleared
	bsr.w	print
	bsr.w	get_key                         ; a key
	bra.s	parameters_menu                 ; the menu

;------------------------------------------------------------------------------
; set_pictures: "ENTER PICTURE NUMBER:" (decimal), then the offset of each picture (6 hex digits, even).
;------------------------------------------------------------------------------
set_pictures:	; from: parameters_menu
	lea	picture_number_text(pc),a0      ; "ENTER PICTURE NUMBER: "
	bsr.w	print
	moveq	#2,d3                           ; 3 digits
	moveq	#9,d6                           ; 0-9
	bsr.w	input_number                    ; typed
	bsr.s	bcd_to_word                     ; from BCD
	move.b	d4,picture_count                ; the number of pictures
	lea	new_lines_text(pc),a0           ; two new lines
	bsr.w	print
	lea	picture_offsets(pc),a2          ; the offsets
set_pictures_next:
	tst.b	d4                              ; more?
	beq.w	parameters_menu                 ; no: the menu
	bsr.s	ask_picture_offset              ; its offset
	move.l	d2,(a2)+                        ; kept
	bra.s	set_pictures_next

;------------------------------------------------------------------------------
; ask_picture_offset: "ENTER OFFSET N.nn: " for picture d4 until an even offset is typed; d4 one less.
;------------------------------------------------------------------------------
ask_picture_offset:	; from: set_pictures
	lea	offset_number_text(pc),a0       ; "ENTER OFFSET N."
	bsr.w	print
	move.w	d4,d2                           ; the picture
	bsr.w	to_bcd                          ; in BCD
	move.w	d3,d1
	bsr.s	print_hex_byte                  ; two digits
	lea	colon_text(pc),a0               ; ": "
	bsr.w	print
	moveq	#5,d3                           ; 6 digits
	moveq	#15,d6                          ; 0-F
	bsr.s	input_number                    ; typed
	lsr.w	#1,d2                           ; odd?
	bcs.s	ask_picture_offset              ; yes: again
	add.w	d2,d2
	subq.w	#1,d4                           ; one done
	rts

;------------------------------------------------------------------------------
; bcd_to_word: the two-digit BCD d2 as a number in d4.
;------------------------------------------------------------------------------
bcd_to_word:	; from: set_pictures
	clr.w	d4
bcd_to_word_tens:
	subi.w	#$10,d2                         ; a ten?
	bmi.s	bcd_to_word_units               ; no more
	addi.w	#$a,d4                          ; 10 more
	bra.s	bcd_to_word_tens
bcd_to_word_units:
	addi.w	#$10,d2
	add.w	d2,d4                           ; + the units
	rts

;------------------------------------------------------------------------------
; print_hex_byte: prints the byte d1 as two hex digits.
;------------------------------------------------------------------------------
print_hex_byte:                                 ; from: ask_picture_offset, print_count, crunch_file,
                                                ;   print_text_hex_word, crunch_pictures, print_percent
	move.w	d1,-(sp)                        ; kept
	lsr.b	#4,d1                           ; the high digit
	bsr.s	print_hex_digit_d1              ; printed
	move.w	(sp)+,d1
	andi.w	#$f,d1                          ; the low digit
	bsr.s	print_hex_digit_d1              ; printed
	rts

;------------------------------------------------------------------------------
; print_hex_digit_d1: prints the digit d1 (0-15) in hex.
;------------------------------------------------------------------------------
print_hex_digit_d1:	; from: print_hex_byte
	cmp.w	#$9,d1                          ; A-F?
	ble.s	print_hex_digit_number          ; no
	addi.w	#$37,d1                         ; 'A'-10
	bra.s	print_char
print_hex_digit_number:
	addi.w	#$30,d1                         ; '0'

;------------------------------------------------------------------------------
; print_char: prints the character d1 (Cconout).
;------------------------------------------------------------------------------
print_char:	; from: print_hex_digit_d1, input_number
	move.w	d1,-(sp)
	move.w	#$2,-(sp)
	trap	#1                              ; Cconout
	addq.w	#4,sp
	rts

;------------------------------------------------------------------------------
; input_number: reads d3+1 digits of value 0 to d6 into d2 (4 bits each).  Return ends (once a digit is
; in), backspace takes one back; one digit too many rubs out them all and starts again.
;------------------------------------------------------------------------------
input_number:	; from: set_pictures, ask_picture_offset
	move.w	d3,d5                           ; the count kept
input_number_restart:
	moveq	#0,d2                           ; the number
input_number_key:
	bsr.w	get_key                         ; a key
	cmp.w	#$d,d0                          ; Return?
	beq.s	input_number_return             ; yes
	cmp.w	#$8,d0                          ; backspace?
	beq.s	input_number_backspace          ; yes
	move.w	d0,d1                           ; kept
	cmp.w	#$39,d0                         ; a letter?
	bgt.s	input_number_letter             ; yes
	subi.w	#$30,d0                         ; '0'-'9'
	bmi.s	input_number_key                ; not a digit
	bra.s	input_number_digit
input_number_letter:
	andi.w	#$df,d0                         ; in capitals
	subi.w	#$37,d0                         ; 'A'-'F' to 10-15
	bmi.s	input_number_key                ; not a digit
input_number_digit:
	cmp.w	d6,d0                           ; too big?
	bgt.s	input_number_key                ; yes
	lsl.l	#4,d2                           ; the digit in
	or.b	d0,d2
	bsr.s	print_char                      ; shown
	dbra	d3,input_number_key             ; all typed?
	move.w	d5,d1                           ; yes: rubbed out
	mulu.w	#$3,d1                          ; 3 bytes
	neg.w	d1                              ; back from rub_out
	lea	rub_out(pc),a0                  ; one "\b \b" for each digit
	lea	0(a0,d1.w),a0
	bsr.w	print                           ; printed
	move.w	d5,d3                           ; the count again
	bra.s	input_number_restart            ; again
input_number_return:
	cmp.w	d5,d3                           ; any digit?
	beq.s	input_number_key                ; no
	rts
input_number_backspace:
	cmp.w	d5,d3                           ; any digit?
	beq.s	input_number_key                ; no
	addq.w	#1,d3                           ; one less
	lsr.l	#4,d2                           ; the digit out
	lea	rub_out(pc),a0                  ; "\b \b"
	bsr.w	print                           ; printed
	bra.s	input_number_key

;------------------------------------------------------------------------------
; crunch_all_menu: F1 crunch every program of a folder, F2 every file, F3 choose the folder, F4 back.
;------------------------------------------------------------------------------
crunch_all_menu:	; from: main_menu
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	crunch_all_menu_text(pc),a0     ; "F1: CRUNCH ALL IN EXEC MODE" ...
	bsr.w	print
	moveq	#0,d0
	lea	files_loaded(pc),a0             ; the counts
	move.w	d0,(a0)                         ; loaded
	move.w	d0,2(a0)                        ; packed
	move.l	d0,-$10c(a0)                    ; the total length
	move.l	d0,-$108(a0)                    ; the total packed length
crunch_all_menu_key:
	bsr.w	get_key                         ; a key
	swap	d0                              ; its scan code
	cmp.w	#$3b,d0                         ; F1?
	beq.s	crunch_all_programs             ; programs
	cmp.w	#$3c,d0                         ; F2?
	beq.s	crunch_all_data                 ; data files
	cmp.w	#$3d,d0                         ; F3?
	beq.s	crunch_all_choose_folder        ; the folder
	cmp.w	#$3e,d0                         ; F4?
	bne.s	crunch_all_menu_key             ; no: another key
	bra.w	main_menu                       ; the main menu
crunch_all_choose_folder:
	lea	any_mask(pc),a3                 ; "*.*"
	bsr.w	choose_file                     ; fsel_input: the folder set
	bra.s	crunch_all_menu                 ; the menu again
crunch_all_data:
	lea	any_mask(pc),a0                 ; "*.*"
	st	data_mode                       ; data mode
	bra.s	crunch_all
crunch_all_programs:
	lea	program_mask(pc),a0             ; "*.PRG"
	sf	data_mode                       ; program mode
crunch_all:
	lea	full_name(pc),a1                ; the mask into the name
crunch_all_copy_mask:
	move.b	(a0)+,(a1)+                     ; copied
	bne.s	crunch_all_copy_mask
	bsr.w	find_first                      ; Fsfirst
	beq.s	crunch_all_batch                ; found?
	lea	empty_folder_text(pc),a0        ; "HEY! EMPTY DIRECTORY!"
	bsr.w	print
	bsr.w	get_key                         ; a key
	bra.w	crunch_all_menu                 ; the menu again
crunch_all_batch:
	st	batch                           ; batch: no questions
crunch_all_next:
	tst.b	io_error                        ; too long for memory?
	bne.s	crunch_all_find                 ; yes: skipped
	lea	files_loaded(pc),a0             ; the counts
	addq.w	#1,(a0)                         ; loaded
	addq.w	#1,2(a0)                        ; packed
	bsr.w	crunch_file                     ; crunched
	move.b	interrupted(pc),d2              ; interrupted?
	bne.s	crunch_all_not_packed           ; yes
	move.b	not_crunched(pc),d2             ; not crunched?
	beq.s	crunch_all_find                 ; no
crunch_all_not_packed:
	lea	largest_space(pc),a2            ; the decrunch space
	move.w	2(a2),(a2)                      ; back to before this file
	subq.w	#1,files_done                   ; not packed
	move.l	file_length(pc),d2              ; its length
	add.l	d2,total_packed_length          ; in the total as it is
	move.b	interrupted(pc),d2              ; interrupted?
	bne.s	crunch_all_done                 ; yes: stopped
crunch_all_find:
	bsr.w	find_next                       ; Fsnext
	beq.s	crunch_all_next                 ; another: crunch it
crunch_all_done:
	lea	clear_row_8_text(pc),a0
	bsr.w	print
	bsr.w	print_total_time                ; the total time
	lea	ok_text(pc),a0                  ; "OK "
	bsr.w	print
	move.w	files_done(pc),d2               ; the files packed
	bsr.s	print_count                     ; printed
	lea	files_packed_text(pc),a0        ; " FILE(S) PACKED"
	bsr.w	print
	lea	in_text(pc),a0                  ; "IN "
	bsr.w	print
	move.w	files_loaded(pc),d2             ; the files loaded
	bsr.s	print_count                     ; printed
	lea	files_loaded_text(pc),a0        ; " FILE(S) LOADED"
	bsr.w	print
	lea	clear_row_11_text(pc),a0
	bsr.w	print
	lea	total_space_text(pc),a0         ; "DECRUNCH SPACE = $"
	move.w	largest_space(pc),d5            ; the largest decrunch space
	addq.w	#1,d5                           ; even
	bclr	#$0,d5
	bsr.w	print_text_hex_word             ; printed
	move.l	total_length(pc),d0             ; the total length
	move.l	total_packed_length(pc),d1      ; the total packed length
	cmp.l	d0,d1                           ; the same?
	bne.s	crunch_all_total                ; no
	lea	total_unpacked_text(pc),a0      ; "TOTAL PACKED LENGTH (100%) SHEAT!"
	bsr.w	print
	bra.s	crunch_all_end
crunch_all_total:
	movem.l	d0-d1,-(sp)                     ; kept
	lea	total_packed_text(pc),a0        ; "TOTAL PACKED LENGTH "
	bsr.w	print
	movem.l	(sp)+,d0-d1
	bsr.w	print_percent                   ; as a percentage
crunch_all_end:
	bsr.s	bell_flush                      ; the bell, the keyboard emptied
	bsr.w	get_key                         ; a key
	bra.w	crunch_all_menu                 ; the menu again

;------------------------------------------------------------------------------
; print_count: prints the number d2 as four decimal digits.
;------------------------------------------------------------------------------
print_count:	; from: print_unpack_counts, crunch_all_menu
	bsr.w	to_bcd                          ; in BCD
	move.w	d3,-(sp)
	move.b	(sp)+,d1                        ; the high byte
	bsr.w	print_hex_byte                  ; two digits
	move.b	d3,d1                           ; the low byte
	bsr.w	print_hex_byte                  ; two digits
	rts

;------------------------------------------------------------------------------
; bell_flush: rings the bell and reads keys until none are left.
;------------------------------------------------------------------------------
bell_flush:	; from: unpack_all_menu, crunch_all_menu
	lea	bell_text(pc),a0                ; the bell
	bsr.w	print
	move.w	#$ff,-(sp)                      ; $ff: a key if any
	move.w	#$6,-(sp)
	trap	#1                              ; Crawio
	addq.w	#4,sp
	tst.w	d0                              ; any?
	beq.s	bell_flush                      ; yes: again
	rts

;------------------------------------------------------------------------------
; find_next: Fsnext, then as find_first.
;------------------------------------------------------------------------------
find_next:	; from: unpack_all_menu, crunch_all_menu
	moveq	#79,d5                          ; Fsnext
	bra.s	find_file

;------------------------------------------------------------------------------
; find_first: Fsfirst on full_name with the DTA set.  A file too long for memory gives "FREE MEMORY <
; LENGHT FILE" and io_error; otherwise its name is kept.  d0 is GEMDOS's answer.
;------------------------------------------------------------------------------
find_first:	; from: unpack_all_menu, load_file, crunch_all_menu
	moveq	#78,d5                          ; Fsfirst
	bsr.w	set_dta                         ; the DTA
find_file:	; from: find_next
	sf	io_error                        ; no error
	clr.w	-(sp)                           ; normal files
	pea	full_name(pc)                   ; the mask
	move.w	d5,-(sp)                        ; Fsfirst/Fsnext
	trap	#1                              ; Fsfirst
	addq.w	#8,sp
	move.w	d0,-(sp)                        ; the answer kept
	bmi.s	find_file_done                  ; none
	move.l	memory_free(pc),d0              ; the memory free
	cmp.l	dta_length(pc),d0               ; the file's length
	blt.s	find_file_too_long              ; too long
	bsr.s	copy_found_name                 ; its name kept
find_file_done:
	move.w	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; copy_found_name: the name found (DTA) as the name chosen.
;------------------------------------------------------------------------------
copy_found_name:	; from: find_first
	lea	dta_name(pc),a0                 ; the DTA's name
	lea	chosen_name(pc),a1              ; the name chosen
	moveq	#13,d1                          ; 14 bytes
copy_found_name_byte:
	move.b	(a0)+,(a1)+
	dbra	d1,copy_found_name_byte
	rts
find_file_too_long:	; from: find_first
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	too_long_text(pc),a0            ; "FREE MEMORY < LENGHT FILE"
	bsr.w	print
	tst.b	batch                           ; batch?
	bne.s	find_file_error                 ; yes
	bsr.w	get_key                         ; no: a key
find_file_error:
	st	io_error                        ; skipped
	rts

;------------------------------------------------------------------------------
; crunch_file: loads the file named, checks the pictures' offsets, crunches it, works out the decrunch
; space and the stub's lengths, and saves it (asking first, unless batch).
; A program is saved as the stub (picture stub with pictures set) and the packed data; a data file as the
; packed data with its 'ATM5' header.
;------------------------------------------------------------------------------
crunch_file:	; from: load_chosen, crunch_all_menu
	bsr.w	clear_statistics                ; the code tables cleared
	bsr.w	clear_offset_counts             ; the statistics cleared
	lea	min_gap(pc),a2                  ; the margin
	move.w	#$ff4,(a2)                      ; none yet
	move.b	data_mode(pc),d0                ; data mode?
	bne.s	crunch_file_load                ; yes
	addq.w	#4,(a2)                         ; a program: 4 more
crunch_file_load:
	move.w	2(a2),d2                        ; the largest decrunch space
	move.w	d2,4(a2)                        ; kept, to undo for this file
	bsr.w	make_name                       ; the full name
	bsr.w	load_file                       ; loaded
	move.l	file_length(pc),d0              ; its length
	add.l	d0,total_length                 ; in the total length
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	tst.b	io_error                        ; read?
	beq.s	crunch_file_check_pictures      ; yes
	lea	read_error_text(pc),a0          ; "READ ERROR! "
	bsr.w	print
	tst.b	batch                           ; batch?
	bne.s	crunch_file_read_error          ; yes
	bsr.w	get_key                         ; no: a key
crunch_file_read_error:
	bra.w	crunch_file_done
crunch_file_check_pictures:
	move.l	file_length(pc),d0              ; the length
	move.l	d0,-(sp)                        ; kept
	moveq	#0,d1
	move.b	picture_count(pc),d1            ; pictures?
	lea	picture_offsets(pc),a0          ; their offsets
	bne.s	crunch_file_pictures            ; yes
	sf	pictures_on                     ; no
	bra.s	crunch_file_offsets
crunch_file_pictures:
	st	pictures_on                     ; pictures
	subq.w	#1,d1                           ; for dblt
	subi.l	#$7d00,d0                       ; the last offset a picture can have
	bmi.s	crunch_file_bad_offset          ; the file is shorter than a picture
crunch_file_check_offset:
	cmp.l	(a0)+,d0                        ; past it?
	dblt	d1,crunch_file_check_offset     ; no: the next
	bge.s	crunch_file_offsets             ; all good
crunch_file_bad_offset:
	addq.w	#1,d1                           ; the picture
	move.w	d1,-(sp)                        ; kept
	lea	picture_parameters_text(pc),a0  ; "PICTURE PARAMETERS N."
	bsr.w	print
	move.w	(sp)+,d2
	bsr.w	to_bcd                          ; in BCD
	move.w	d3,d1
	bsr.w	print_hex_byte                  ; printed
	lea	bad_offset_text(pc),a0          ; " BAD", "OFFSET + 7D00 > FILE LENGTH"
	bsr.w	print
	bsr.w	get_key                         ; a key
	addq.w	#4,sp                           ; the length dropped
	st	interrupted                     ; stopped
	move.w	#$ff4,min_gap                   ; no decrunch space
	bra.w	crunch_file_done
crunch_file_offsets:
	move.l	(sp)+,d0                        ; the length
	moveq	#0,d7
	move.b	picture_count(pc),d7            ; pictures?
	beq.s	crunch_file_go                  ; no
	movea.l	load_buffer(pc),a0              ; the file
	movea.l	a0,a2
	addq.l	#1,d0                           ; its length
	bclr	#$0,d0                          ; even
	adda.l	d0,a0                           ; its end
	lea	picture_offsets(pc),a1          ; the offsets
crunch_file_copy_offset:
	move.l	(a1)+,(a0)+                     ; after the file, for the depacker
	subq.w	#1,d7
	bne.s	crunch_file_copy_offset
	move.l	a0,d0                           ; the end
	sub.l	a2,d0                           ; the length with the offsets
crunch_file_go:
	move.l	d0,crunch_length                ; the length crunched
	move.l	d0,crunch_left                  ; all left
	lea	crunching_text(pc),a0           ; "CRUNCHING : "
	bsr.w	print
	lea	full_name(pc),a0                ; the name
	bsr.w	print
	lea	new_lines_text(pc),a0           ; two new lines
	bsr.w	print
	sf	not_crunched                    ; crunched (so far)
	lea	read_start_time(pc),a0          ; the clock now
	bsr.w	supervisor_call
	bsr.w	crunch_pictures                 ; the pictures turned, then packed
	move.b	interrupted(pc),d2              ; interrupted?
	bne.w	crunch_file_done                ; yes
	bsr.w	print_time                      ; "CRUNCHING TIME:"
	move.l	crunch_length(pc),d0            ; the length crunched
	move.l	(a5),d1                         ; the packed length
	lsr.w	#1,d1                           ; odd?
	bcc.s	crunch_file_even                ; no
	add.w	d1,d1
	addq.l	#2,d1                           ; made even
	bra.s	crunch_file_lengths
crunch_file_even:
	add.w	d1,d1
crunch_file_lengths:
	movea.l	d1,a0
	addq.w	#8,a0                           ; + the two lengths
	moveq	#0,d3                           ; no stub
	move.b	data_mode(pc),d2                ; data mode?
	bne.s	crunch_file_data_header         ; yes
	move.l	a0,d3                           ; a program
	move.b	pictures_on(pc),d2              ; pictures?
	beq.s	crunch_file_normal_stub         ; no
	lea	$52(a0),a0                      ; + the picture stub's $52 more
crunch_file_normal_stub:
	lea	$290(a0),a0                     ; + the stub
	sub.l	a0,d3
	neg.l	d3                              ; d3 = the stub's length
	bra.s	crunch_file_gain
crunch_file_data_header:
	addq.w	#4,a0                           ; + 'ATM5'
crunch_file_gain:
	sub.l	a0,d0                           ; the bytes gained
	ble.w	crunch_file_no_gain             ; none: "SORRY CANNOT CRUNCH.."
	moveq	#0,d1
	move.w	min_gap(pc),d1                  ; the margin
	subi.w	#$ff4,d1
	move.b	data_mode(pc),d2                ; data mode?
	bne.s	crunch_file_space               ; yes
	subq.w	#4,d1
crunch_file_space:
	neg.w	d1                              ; the decrunch space
	addq.w	#1,d1
	bclr	#$0,d1                          ; even
	move.w	d1,picture_stub_space+2         ; into the picture stub
	move.w	d1,stub_space+2                 ; and the normal stub
	add.l	d1,d0                           ; the bss: the decrunch space
	add.l	d3,d0                           ; + the stub
	addq.l	#8,d0                           ; + the lengths
	move.l	d0,picture_stub_bss_length      ; + the gain: the room the stub needs past its data
	move.l	d0,stub_bss_length
	move.l	a0,save_length                  ; the length saved
	lea	save_length_text(pc),a0         ; "SAVE LENGTH: "
	bsr.w	print
	move.l	save_length(pc),d0
	move.l	d0,-(sp)
	bsr.w	print_hex                       ; in hex
	move.l	file_length(pc),d0              ; the file's length
	move.l	(sp)+,d1
	bsr.w	print_percent                   ; as a percentage
	tst.b	data_mode                       ; data mode?
	bne.s	crunch_file_data                ; yes
	movea.l	save_length(pc),a0              ; the length saved
	move.l	a0,d2
	lea	-$1c(a0),a0                     ; less the header: the stub's text length
	move.l	a0,picture_stub_text_length     ; into the picture stub
	move.l	a0,stub_text_length             ; and the normal stub
	movea.l	work_memory(pc),a1              ; the work memory
	suba.w	#$290,a1                        ; the stub before it
	lea	stub(pc),a0                     ; the normal stub
	move.w	#$147,d0                        ; $290 bytes
	tst.b	pictures_on                     ; pictures?
	beq.s	crunch_file_copy_stub           ; no
	suba.w	#$52,a1                         ; $52 more
	lea	picture_stub(pc),a0             ; the picture stub
	addi.w	#$29,d0
crunch_file_copy_stub:
	movea.l	a1,a2                           ; the file's start
crunch_file_copy_stub_word:
	move.w	(a0)+,(a1)+                     ; copied
	dbra	d0,crunch_file_copy_stub_word
	bra.s	crunch_file_save
crunch_file_data:
	movea.l	work_memory(pc),a2              ; the file's start
	move.l	save_length(pc),d2              ; its length
	bra.s	crunch_file_save

;------------------------------------------------------------------------------
; print_text_hex_word: prints the text at a0, then the word d5 as four hex digits.
;------------------------------------------------------------------------------
print_text_hex_word:	; from: crunch_all_menu
	bsr.w	print                           ; the text
	move.w	d5,-(sp)
	move.b	(sp)+,d1                        ; the high byte
	bsr.w	print_hex_byte                  ; two digits
	move.b	d5,d1                           ; the low byte
	bsr.w	print_hex_byte                  ; two digits
	rts
crunch_file_save:	; from: crunch_file
	lea	clear_row_8_text(pc),a0
	bsr.w	print
	lea	decrunch_space_text(pc),a0      ; "DECRUNCH SPACE = $"
	move.w	min_gap(pc),d5                  ; the margin
	subi.w	#$ff4,d5
	move.b	data_mode(pc),d0                ; data mode?
	bne.s	crunch_file_print_space         ; yes
	subq.w	#4,d5
crunch_file_print_space:
	neg.w	d5                              ; the decrunch space
	addq.w	#1,d5
	bclr	#$0,d5                          ; even
	bsr.s	print_text_hex_word             ; printed
	move.b	batch(pc),d0                    ; batch?
	bne.s	crunch_file_write               ; yes: saved
	lea	save_packed_text(pc),a0         ; "SAVE PACK FILE? (Y/N)"
	bsr.w	print
crunch_file_save_key:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.s	crunch_file_choose              ; yes
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	crunch_file_save_key            ; no: another key
	bra.w	crunch_file_done                ; not saved
crunch_file_choose:
	movea.l	file_mask(pc),a3                ; the mask
	bsr.w	choose_file                     ; fsel_input
	tst.w	d0                              ; OK?
	bne.s	crunch_file_done                ; no
	lea	title_text(pc),a0               ; the title
	bsr.w	print
crunch_file_write:
	bsr.w	make_name                       ; the full name
	add.l	d2,total_packed_length          ; in the total packed length
	bsr.w	write_file                      ; written
	tst.b	io_error                        ; an error?
	bne.s	crunch_file_write_error         ; yes
	move.b	batch(pc),d0                    ; batch?
	bne.s	crunch_file_done                ; yes: done
	lea	file_text(pc),a0                ; "FILE: "
	bsr.w	print
	lea	full_name(pc),a0                ; the name
	bsr.w	print
	lea	saved_text(pc),a0               ; " SAVED"
	bsr.w	print
	bsr.w	get_key                         ; a key
	bra.s	crunch_file_done
crunch_file_write_error:
	lea	write_error_text(pc),a0         ; "WRITE ERROR! RETRY (Y/N)"
	bsr.w	print
crunch_file_retry_key:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.w	crunch_file_save                ; yes: again
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	crunch_file_retry_key           ; no: another key
	bra.s	crunch_file_done                ; given up
crunch_file_no_gain:	; from: crunch_file
	st	not_crunched                    ; not crunched
	lea	cannot_crunch_text(pc),a0       ; "SORRY CANNOT CRUNCH.."
	bsr.w	print
	tst.b	batch                           ; batch?
	bne.s	crunch_file_done                ; yes
	bsr.w	get_key                         ; no: a key
crunch_file_done:	; from: crunch_file
	rts

;------------------------------------------------------------------------------
; set_dta: Fsetdta to the program's DTA.
;------------------------------------------------------------------------------
set_dta:	; from: start, find_first
	pea	dta(pc)                         ; the DTA
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.w	#6,sp
	rts

;------------------------------------------------------------------------------
; crunch_pictures: each picture turned from words of planes to bytes of pixels' bits (encode_picture),
; numbered from the last, then the file packed.
;------------------------------------------------------------------------------
crunch_pictures:	; from: crunch_file
	moveq	#0,d7
	move.b	picture_count(pc),d7            ; pictures?
	beq.s	crunch_pictures_pack            ; no
	lea	picture_offsets(pc),a2          ; their offsets
crunch_pictures_next:
	dbra	d7,crunch_pictures_one          ; one more?
	bra.s	crunch_pictures_pack            ; no
crunch_pictures_one:
	lea	encoding_picture_text(pc),a0    ; "ENCODING PICTURE N."
	bsr.w	print
	move.w	d7,d2
	addq.w	#1,d2                           ; its number
	bsr.w	to_bcd                          ; in BCD
	move.w	d3,d1
	bsr.w	print_hex_byte                  ; printed
	lea	clear_to_end_text(pc),a0
	bsr.w	print
	movea.l	load_buffer(pc),a0              ; the file
	adda.l	(a2)+,a0                        ; + its offset
	bsr.w	encode_picture                  ; turned
	bra.s	crunch_pictures_next
crunch_pictures_pack:
	bsr.s	pack                            ; packed
	rts

;------------------------------------------------------------------------------
; pack: crunches the file (with the pictures' offsets after it) from the load buffer into the work memory.
; Data mode puts 'ATM5' first.  Then the unpacked length, the packed length, and the packed data: blocks,
; each written forward and read backward by the depacker, bytes and bit bytes mixed (d7 holds the bits,
; filled from the top, with a bit 7 marker to know when it is full).  After the last block: the last bit
; byte, the number of pictures (not for a program without pictures) and 8 zero bytes.
;------------------------------------------------------------------------------
pack:	; from: crunch_pictures
	movea.l	load_buffer(pc),a0              ; the file
	move.l	a0,next_report                  ; the next report
	move.l	a0,next_undo_check              ; the next UNDO check
	movea.l	work_memory(pc),a5              ; the work memory
	tst.b	data_mode                       ; data mode?
	beq.s	pack_even                       ; no
	move.b	#$41,(a5)+                      ; 'ATM5'
	move.b	#$54,(a5)+
	move.b	#$4d,(a5)+
	move.b	#$35,(a5)+
pack_even:
	move.l	crunch_length(pc),d0            ; the length
	btst	#$0,d0                          ; odd?
	bcc.s	pack_start                      ; no
	addq.l	#1,d0                           ; made even
	move.l	d0,crunch_length
pack_start:
	lea	0(a0,d0.l),a6                   ; the file's end
	move.l	a6,input_end                    ; kept
	moveq	#0,d0
	movep.l	d0,0(a6)                        ; 8 bytes after it cleared
	movep.l	d0,1(a6)
	move.l	a6,d0
	sub.l	a0,d0                           ; the length
	move.l	d0,(a5)+                        ; the unpacked length
	addq.w	#4,a5                           ; the packed length's place
	pea	(a5)                            ; the data's start kept
	moveq	#0,d3
	moveq	#-128,d7                        ; the bit byte: empty, with its marker
	clr.b	interrupted                     ; not interrupted
	swap	d7
	move.w	#$2408,window_last              ; the window not the last
	movea.l	a0,a4                           ; where the search is
	move.l	a0,next_report                  ; the next report
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	bsr.w	print_crunch_left               ; "CRUNCH LEFT:"
	bsr.w	print_crunch_done               ; "CRUNCH DONE:"
	movem.l	(sp)+,d0-d7/a0-a6
	bsr.w	analyse_window                  ; the first window analysed
	moveq	#0,d6
	sf	output_overrun                  ; no overrun
	bsr.w	match                           ; matched and written
	tst.b	interrupted                     ; interrupted?
	beq.s	pack_end                        ; no
	addq.w	#4,sp                           ; the data's start dropped
	bra.s	pack_done
pack_end:
	swap	d7
	move.b	d7,(a5)+                        ; the last bit byte
	move.b	picture_count(pc),d7            ; the number of pictures
	move.b	data_mode(pc),d0                ; data mode?
	bne.s	pack_picture_count              ; yes: written
	tst.b	d7                              ; pictures?
	beq.s	pack_clear_end                  ; no: not written
pack_picture_count:
	move.b	d7,(a5)+
pack_clear_end:
	moveq	#0,d0
	movep.l	d0,0(a5)                        ; 8 bytes cleared after it
	movep.l	d0,1(a5)
	move.l	a5,d0                           ; the end
	movea.l	(sp)+,a5                        ; the data's start
	sub.l	a5,d0
	move.l	d0,-(a5)                        ; the packed length
pack_done:
	rts

;------------------------------------------------------------------------------
; match_report: "CRUNCH LEFT:" and UNDO checked ("INTERUPTION? (Y/N)"), then back into the search.
;------------------------------------------------------------------------------
match_report:	; from: match
	movem.l	d1-d3/a0-a4,-(sp)               ; saved
	bsr.w	print_crunch_left               ; "CRUNCH LEFT:"
match_report_key:
	move.w	#$ff,-(sp)                      ; $ff: a key if any
	move.w	#$6,-(sp)
	trap	#1                              ; Crawio
	addq.w	#4,sp
	swap	d0                              ; its scan code
	cmp.w	#$61,d0                         ; UNDO?
	beq.s	match_report_ask                ; yes
	tst.l	d0                              ; a key?
	bne.s	match_report_key                ; yes: the next
	bra.s	match_report_carry_on           ; no
match_report_ask:
	lea	interruption_text(pc),a0        ; "INTERUPTION? (Y/N)"
	bsr.w	print
match_report_answer:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.s	match_report_stop               ; yes
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	match_report_answer             ; no: another key
	bra.s	match_report_carry_on           ; carry on
match_report_stop:
	lea	interrupted(pc),a0              ; interrupted
	st	(a0)
	move.w	#$ff4,emit_block+10-interrupted(a0) ; meant for min_gap, but this is the cmp.l #$ff4 in emit_block
                                                ;   (already $ff4)
	movem.l	(sp)+,d1-d3/a0-a4
match_return:	; from: match, window_last
	rts
match_report_carry_on:
	movem.l	(sp)+,d1-d3/a0-a4
	move.b	-$1(a4),d0                      ; the byte again
	bra.s	match_next
match_overrun:	; from: match, window_last
	movea.l	work_memory(pc),a5              ; the output caught the input: the packed length is the file's (no gain)
	adda.l	crunch_length(pc),a5
	rts

;------------------------------------------------------------------------------
; match: the search, from a4 to the window's end a6.  For each byte, the later places of the same byte
; (position_lists) are tried within $3f60 bytes: the longest match wins (2 bytes only within $362).
; Each place's word in position_lists then holds what is there: -1 a literal, or a match's offset (and its
; second byte's word the length - 1).  When the window's end is in reach, the block so far is written and the
; next window analysed; at the end of the file the last block is written.
;------------------------------------------------------------------------------
match:	; from: pack, window_last
	moveq	#0,d0
	lea	match_offset(pc),a3             ; the best offset
	move.l	d0,(a3)+                        ; and length none
	move.b	d0,(a3)                         ; not found
	lea	position_lists(pc),a3           ; the lists
	lea	byte_counts(pc),a2              ; the counts
	move.b	(a4)+,d0                        ; the byte
	cmpa.l	next_report(pc),a4              ; time for a report?
	bge.s	match_report                    ; yes
match_next:	; from: match_report
	move.b	(a4),d1                         ; the next byte
match_reach:
	lea	$3f60(a4),a1                    ; the furthest a match can start
	cmpa.l	a1,a6                           ; inside the window?
	bgt.s	match_try                       ; yes
	cmpi.w	#$601e,window_last              ; the last window?
	beq.s	match_last_window               ; yes: up to its end
	move.l	a0,d2
	lea	-$1(a4),a0                      ; this block ends here
	subq.w	#1,a4
	bsr.w	write_block                     ; written
	addq.w	#1,a4
	move.b	interrupted(pc),d2              ; interrupted?
	bne.s	match_return                    ; yes
	move.b	output_overrun(pc),d2           ; overrun?
	bne.s	match_overrun                   ; yes
	bsr.w	analyse_window                  ; the next window
	bra.s	match_reach

;------------------------------------------------------------------------------
; window_last: a flag kept in the code, never run: $601e once the window is the file's last, $2408 before.
;------------------------------------------------------------------------------
window_last:	; from: pack, match, analyse_window
	dc.w	$0000
match_last_window:	; from: match
	movea.l	a6,a1                           ; the window's end
match_try:	; from: match
	move.w	d0,d2                           ; the byte
	add.w	d2,d2
	adda.w	d2,a2                           ; its count
	subq.w	#1,(a2)                         ; one less (this one): any more?
	beq.s	match_none                      ; no: a literal
	move.w	(a2),d7                         ; the places left
	subq.w	#1,d7
	lea	position_index(pc),a2
	adda.w	d2,a2                           ; its index
	addq.w	#2,(a2)                         ; past this place
	move.w	(a2),d6
	add.w	d2,d2
	movea.l	0(a3,d2.w),a2                   ; its list
	adda.l	d6,a2                           ; the next place
	pea	(a2)                            ; kept
match_try_place:
	movea.l	a0,a3                           ; the place
	adda.w	(a2)+,a3
	cmpa.l	a3,a1                           ; out of reach?
	ble.s	match_try_done                  ; yes: done
	cmp.b	(a3)+,d1                        ; the second byte the same?
	dbeq	d7,match_try_place              ; no: the next place
	bne.s	match_try_done                  ; none
	addq.w	#1,a4
	cmpa.l	a3,a1                           ; the match inside the window?
	bge.s	match_compare                   ; yes: how long
	subq.w	#1,a4
	tst.w	match_length                    ; (never: the best length is not negative)
	bge.s	match_try_done
	move.l	a3,d2
	sub.l	a4,d2                           ; the offset
	cmp.w	#$360,d2
	bgt.s	match_try_done                  ; too far
	subq.w	#1,d2
	move.w	d2,match_offset                 ; the offset
	addq.w	#2,match_length                 ; 2
	st	match_flag                      ; found
match_try_done:
	bra.s	match_tried
match_none:
	lea	position_index(pc),a2
	adda.w	d2,a2
	move.w	(a2),d6                         ; the index
	addq.w	#2,d6                           ; past this place
	add.w	d2,d2
	lea	position_lists(pc),a2           ; the lists
	movea.l	0(a2,d2.w),a2                   ; its list
	adda.l	d6,a2                           ; this place's word
	bra.s	match_decide
match_compare:
	move.l	a4,d2                           ; the start
match_compare_byte:
	cmpm.b	(a4)+,(a3)+                     ; the same?
	bne.s	match_compare_end               ; no
	cmpa.l	a3,a1                           ; out of reach?
	bge.s	match_compare_byte              ; no: the next
match_compare_end:
	sub.l	a4,d2
	neg.w	d2
	addq.w	#1,d2                           ; the length
	suba.w	d2,a4                           ; back to the start
	cmp.w	#$100,d2                        ; longer than 256?
	ble.s	match_compare_best              ; no
	cmp.w	#$1,d7                          ; more places?
	blt.s	match_compare_best              ; no
match_skip_place:
	moveq	#0,d4                           ; places inside this match skipped
	move.w	(a2)+,d4
	add.l	a0,d4
	cmpa.l	d4,a3                           ; past it?
	ble.s	match_skip_done                 ; yes
	dbra	d7,match_skip_place
	clr.w	d7                              ; none left
match_skip_done:
	subq.w	#2,a2
match_compare_best:
	cmp.w	match_length(pc),d2             ; longer than the best?
	ble.s	match_try_next                  ; no
	move.w	d2,match_length                 ; the best length
	move.l	a3,d5
	sub.l	a4,d5                           ; the distance
	cmp.w	#$2,d2                          ; 2 bytes?
	bgt.s	match_better                    ; no
	cmp.w	#$362,d5                        ; within $362?
	bgt.s	match_try_next                  ; no
match_better:
	st	match_flag                      ; found
	sub.w	d2,d5
	subq.w	#1,d5                           ; -1: the offset
	st	match_flag
	move.w	d5,match_offset                 ; the best offset
match_try_next:
	dbra	d7,match_try_place              ; the next place
match_tried:
	movea.l	(sp)+,a2                        ; this place's word
match_decide:
	move.b	match_flag(pc),d1               ; found?
	bne.s	match_found                     ; yes
	move.b	(a4),d1                         ; a literal: the next byte
	sub.b	d0,d1                           ; less this one
	cmp.b	#$7,d1                          ; -8..7?
	bgt.s	match_literal
	cmp.b	#$f8,d1
	blt.s	match_literal
	addq.w	#1,small_delta_count            ; one more small delta
match_literal:
	add.w	d0,d0
	lea	literal_counts(pc),a3           ; the literals' counts
	adda.w	d0,a3
	addq.w	#1,(a3)                         ; one more
	move.w	#$ffff,-(a2)                    ; -1: a literal
	cmpa.l	a4,a6                           ; the window done?
	bgt.w	match                           ; no: the next byte
	bra.w	match_end
match_found:
	move.w	match_offset(pc),d0             ; the offset
	move.w	d0,-(a2)                        ; into this place's word
	lea	offset_nibble_counts(pc),a2     ; the offset nibbles' counts
	andi.w	#$f,d0                          ; its low nibble
	add.w	d0,d0
	adda.w	d0,a2
	addq.w	#1,(a2)                         ; one more
	move.w	match_length(pc),d0             ; the length
	subq.w	#1,d0                           ; -1
	movea.l	a4,a2                           ; the next byte
	adda.w	d0,a4                           ; past the match
	lea	byte_counts(pc),a3
	move.b	(a2)+,d1                        ; the second byte
	moveq	#0,d2
	move.b	d1,d2
	add.w	d2,d2
	adda.w	d2,a3
	subq.w	#1,(a3)                         ; one less
	lea	position_index(pc),a3
	adda.w	d2,a3
	move.w	(a3),d6                         ; its index
	addq.w	#2,(a3)                         ; past it
	add.w	d2,d2
	lea	position_lists(pc),a3
	movea.l	0(a3,d2.w),a3                   ; its list
	adda.l	d6,a3                           ; its word
	move.w	d0,(a3)                         ; the length - 1
	subq.w	#1,d0
	move.w	d0,d1
	cmp.w	#$ff,d1                         ; longer than 257?
	bgt.s	match_long                      ; yes
	add.w	d1,d1
	lea	length_counts(pc),a3            ; the lengths' counts
	adda.w	d1,a3
	addq.w	#1,(a3)                         ; one more
	bra.s	match_skip_byte
match_long:
	addq.w	#1,long_length_count            ; one more long length
match_skip_byte:
	dbra	d0,match_skip_next              ; more bytes?
	bra.s	match_window_done               ; no
match_skip_next:
	lea	byte_counts(pc),a3              ; the counts
	move.b	(a2)+,d1                        ; the byte
	moveq	#0,d2
	move.b	d1,d2
	add.w	d2,d2
	adda.w	d2,a3
	subq.w	#1,(a3)                         ; one less
	lea	position_index(pc),a3
	adda.w	d2,a3
	addq.w	#2,(a3)                         ; its index past it
	bra.s	match_skip_byte
match_window_done:
	cmpa.l	a4,a6                           ; the window done?
	bgt.w	match                           ; no: the next byte
match_end:
	move.l	a0,d2                           ; the block's start
	bsr.s	write_block                     ; written
	move.b	interrupted(pc),d2              ; interrupted?
	bne.w	match_return                    ; yes
	move.b	output_overrun(pc),d2           ; overrun?
	bne.w	match_overrun                   ; yes
	rts

;------------------------------------------------------------------------------
; write_block: the block from d2 to a4: the literal mode chosen (16 commonest bytes "HUFFMAN", or deltas
; "RELATIF"), the length split and the offset nibble mode, then emitted with its header.  The largest
; decrunch space is updated.
;------------------------------------------------------------------------------
write_block:	; from: match, window_last
	movem.l	d0-d6/a0-a3,-(sp)               ; saved
	move.l	d2,-(sp)                        ; the block's start
	swap	d7
	bsr.w	choose_literal_mode             ; the literal mode
	tst.w	d2                              ; relative?
	bne.s	write_block_relative            ; yes
	sf	relative_mode                   ; no
	lea	huffman_text(pc),a0             ; "HUFFMAN DATA PACK SYSTEM."
	bra.s	write_block_mode
write_block_relative:
	st	relative_mode                   ; relative
	lea	relative_text(pc),a0            ; "RELATIF DATA PACK SYSTEM."
write_block_mode:
	bsr.w	print
	bsr.w	choose_length_split             ; the length split
	bsr.s	choose_offset_mode              ; the offset nibble mode
	bsr.w	clear_indexes                   ; the indexes cleared
	movea.l	(sp)+,a0                        ; the block's start
	move.l	a4,d0                           ; the end
	sub.l	a0,d0                           ; less the start
	move.w	d0,block_length                 ; the block's length
	bsr.w	emit_block                      ; emitted
	lea	clear_row_10_text(pc),a0
	bsr.w	print
	move.b	output_overrun(pc),d2           ; overrun?
	bne.s	write_block_stopped             ; yes
	tst.b	interrupted                     ; interrupted?
	bne.s	write_block_stopped             ; yes
	lea	min_gap(pc),a2                  ; the gap
	move.w	(a2),d1
	subi.w	#$ff4,d1
	move.b	data_mode(pc),d0                ; data mode?
	bne.s	write_block_space               ; yes
	subq.w	#4,d1
write_block_space:
	neg.w	d1                              ; the decrunch space
	cmp.w	largest_space(pc),d1            ; more than the largest?
	ble.s	write_block_header              ; no
	move.w	d1,2(a2)                        ; the largest
write_block_header:
	bsr.w	write_header                    ; the block header
	bsr.w	clear_statistics                ; the statistics cleared
	movem.l	(sp)+,d0-d6/a0-a3
	swap	d7
	rts
write_block_stopped:
	movem.l	(sp)+,d0-d6/a0-a3
	rts

;------------------------------------------------------------------------------
; choose_offset_mode: the offsets' low nibbles: the 7 commonest odd ones get 3-bit codes, the rarest odd
; one 4 bits, the even ones 7.  On if that saves more than 8 bits over plain offsets.
;------------------------------------------------------------------------------
choose_offset_mode:	; from: write_block
	st	offset_nibble_mode              ; on
	lea	offset_nibble_counts+2(pc),a0   ; the odd nibbles' counts
	lea	odd_nibble_counts(pc),a1
	moveq	#7,d0                           ; 8
choose_offset_mode_copy:
	move.w	(a0),(a1)+                      ; copied
	addq.w	#4,a0                           ; the next odd one
	dbra	d0,choose_offset_mode_copy
	lea	odd_nibble_counts(pc),a0
	lea	odd_nibbles_by_count(pc),a1     ; the odd nibbles by count
	moveq	#7,d2                           ; 8
	moveq	#0,d3                           ; their total
choose_offset_mode_pick:
	movea.l	a0,a2
	movea.l	a2,a3
	moveq	#7,d1
	move.w	(a2),d0                         ; the largest so far
choose_offset_mode_find:
	cmp.w	(a2)+,d0                        ; more?
	dblt	d1,choose_offset_mode_find      ; no: the next
	bge.s	choose_offset_mode_found
	lea	-$2(a2),a3                      ; yes
	move.w	(a3),d0
	dbra	d1,choose_offset_mode_find
choose_offset_mode_found:
	move.l	a3,d0
	sub.l	a0,d0
	add.w	(a3),d3                         ; in the total
	clr.w	(a3)                            ; taken
	lsr.b	#1,d0                           ; its odd nibble's number
	move.b	d0,(a1)+                        ; in order
	dbra	d2,choose_offset_mode_pick      ; the next
	lea	odd_nibble_codes(pc),a2         ; the codes
	moveq	#6,d1                           ; 7
	moveq	#0,d2
choose_offset_mode_code:
	cmp.b	d2,d0                           ; the rarest's place?
	bne.s	choose_offset_mode_set          ; no
	addq.w	#1,a2                           ; skipped
choose_offset_mode_set:
	move.b	d2,(a2)+
	addq.w	#1,d2
	dbra	d1,choose_offset_mode_code
	add.w	d0,d0
	add.w	d0,d0
	lea	offset_nibble_counts(pc),a0
	sub.w	2(a0,d0.w),d3                   ; less the rarest's count
	moveq	#7,d1                           ; 8
	clr.w	d0
choose_offset_mode_even:
	add.w	(a0),d0                         ; the even nibbles' counts
	addq.w	#4,a0
	dbra	d1,choose_offset_mode_even
	move.w	d0,d1
	add.w	d0,d0
	add.w	d1,d0                           ; *3
	sub.w	d0,d3                           ; less 3 bits each
	subq.w	#8,d3                           ; saves more than 8 bits?
	bgt.s	clear_offset_counts             ; yes
	sf	offset_nibble_mode              ; off

;------------------------------------------------------------------------------
; clear_offset_counts: the offset nibbles' counts cleared.
;------------------------------------------------------------------------------
clear_offset_counts:	; from: crunch_file, choose_offset_mode
	lea	offset_nibble_counts(pc),a0
	moveq	#7,d0                           ; 16 words
clear_offset_counts_long:
	clr.l	(a0)+
	dbra	d0,clear_offset_counts_long
	rts

;------------------------------------------------------------------------------
; choose_literal_mode: the 16 commonest literals into common_literals.  d2 kept (relative) if they
; are not more than 128 above the literals with a delta of -8..7 from the next, else 0 ("Huffman").
;------------------------------------------------------------------------------
choose_literal_mode:	; from: write_block
	pea	(a4)
	lea	literal_counts(pc),a0           ; the literals' counts
	lea	common_literals(pc),a1          ; the commonest
	moveq	#15,d2                          ; 16
	moveq	#0,d3                           ; their total
choose_literal_mode_pick:
	movea.l	a0,a2
	movea.l	a0,a3
	move.w	(a2)+,d0
	movea.l	a0,a4
	move.w	#$ff,d1                         ; 256
choose_literal_mode_find:
	cmp.w	(a4)+,d0                        ; more?
	dblt	d1,choose_literal_mode_find     ; no: the next
	bge.s	choose_literal_mode_found
	lea	-$2(a4),a3                      ; yes
	move.w	(a3),d0
	dbra	d1,choose_literal_mode_find
choose_literal_mode_found:
	move.l	a3,d0
	sub.l	a0,d0
	lsr.w	#1,d0                           ; the byte
	move.b	d0,(a1)+                        ; in order
	add.w	(a3),d3                         ; in the total
	clr.w	(a3)                            ; taken
	dbra	d2,choose_literal_mode_pick     ; the next
	movea.l	(sp)+,a4
	subi.w	#$80,d3                         ; less 128
	cmp.w	small_delta_count(pc),d3        ; more than the small deltas?
	ble.s	choose_literal_mode_done        ; no: relative
	moveq	#0,d2                           ; yes: "Huffman"
choose_literal_mode_done:
	rts

;------------------------------------------------------------------------------
; choose_length_split: the lengths' sums, then the split (the lengths coded in unary) with the fewest bits.
; d4 = split/2 - 1.
;------------------------------------------------------------------------------
choose_length_split:	; from: write_block
	move.w	long_length_count(pc),d1        ; the long lengths
	lea	length_sums(pc),a0              ; the lengths' counts' end
	lea	long_length_count(pc),a1
	lea	split_cost(pc),a2               ; the best
	move.w	#$7fff,(a2)                     ; none yet
	move.w	#$ff,d0                         ; 256
choose_length_split_sum:
	add.w	-(a0),d1                        ; the counts from this length on
	move.w	d1,-(a1)
	dbra	d0,choose_length_split_sum
	moveq	#0,d5
	move.w	#$fe,d4
choose_length_split_try:
	addq.w	#2,d5                           ; the next split
	moveq	#0,d1
	movea.l	a0,a3                           ; the counts
	move.w	d5,d0
	moveq	#1,d3
choose_length_split_unary:
	moveq	#0,d2
	move.w	(a3)+,d2
	mulu.w	d3,d2                           ; in unary
	add.l	d2,d1
	addq.w	#1,d3
	subq.w	#2,d0
	bne.s	choose_length_split_unary
	movea.l	a0,a3
	adda.w	d5,a3
	moveq	#15,d0                          ; 16
	moveq	#0,d2
choose_length_split_four:
	add.w	(a3)+,d2                        ; the next 16 lengths
	dbra	d0,choose_length_split_four
	move.l	d5,d0
	lsr.w	#1,d0
	mulu.w	d2,d0
	lsl.l	#2,d2                           ; in 4 bits
	add.l	d0,d2                           ; and the split's zeros
	add.l	d2,d1
	move.w	$20(a1,d5.w),d0                 ; the lengths past them
	ext.l	d0
	move.l	d5,d2
	lsr.w	#1,d2
	mulu.w	d0,d2
	lsl.l	#2,d0
	move.l	d0,d3
	add.l	d0,d0
	add.l	d3,d0
	add.l	d0,d1
	add.l	d2,d1
	cmp.l	(a2),d1                         ; better?
	dblt	d4,choose_length_split_try      ; no: the next
	bge.s	choose_length_split_done
	move.l	d1,(a2)                         ; the best
	move.w	d5,4(a2)                        ; its split
	dbra	d4,choose_length_split_try      ; the next
choose_length_split_done:
	move.w	4(a2),d4                        ; the best split
	lsr.w	#1,d4
	subq.w	#1,d4
	rts

;------------------------------------------------------------------------------
; clear_indexes: the lists' indexes back to their starts.
;------------------------------------------------------------------------------
clear_indexes:	; from: write_block
	lea	position_index(pc),a0
	moveq	#0,d0
	moveq	#127,d1                         ; 256 words
clear_indexes_long:
	move.l	d0,(a0)+
	dbra	d1,clear_indexes_long
	rts

;------------------------------------------------------------------------------
; clear_statistics: the literals', lengths' and sums' counts cleared.
;------------------------------------------------------------------------------
clear_statistics:	; from: crunch_file, write_block
	lea	literal_counts(pc),a0           ; from
	lea	long_length_count(pc),a1        ; to
	moveq	#0,d0
clear_statistics_long:
	move.l	d0,(a0)+
	cmpa.l	a0,a1                           ; the end?
	bgt.s	clear_statistics_long           ; no
	bne.s	clear_statistics_done
	move.w	d0,(a0)+                        ; the last word
clear_statistics_done:
	rts
emit_overrun:	; from: emit_block
	st	output_overrun                  ; the output caught the input
	move.w	#$ff4,min_gap                   ; no decrunch space
	rts

;------------------------------------------------------------------------------
; emit_block: the block from a0 to a4, from the words left in position_lists, into the work memory.
; The gap between input and output (less $1000) is the least kept in min_gap: the decrunch space.
;------------------------------------------------------------------------------
emit_block:	; from: write_block
	move.l	a0,d1                           ; the input
	sub.l	a5,d1                           ; less the output
	blt.s	emit_overrun                    ; caught up
	cmp.l	#$ff4,d1
	bge.s	emit_byte
	lea	min_gap(pc),a2                  ; the least so far
	cmp.w	(a2),d1
	bge.s	emit_byte
	move.w	d1,(a2)
emit_byte:
	moveq	#0,d5
	move.b	(a0)+,d5                        ; the byte
	bsr.w	next_word                       ; its word
	move.w	d0,d1
	bpl.s	emit_match                      ; a match
	move.b	relative_mode(pc),d1            ; relative?
	beq.s	emit_common                     ; no
	cmpa.l	input_end(pc),a0                ; the end?
	beq.s	emit_literal                    ; yes: a byte
	move.b	(a0),d0                         ; the next
	sub.b	d5,d0                           ; less this one
	cmp.b	#$7,d0                          ; -8..7?
	bgt.s	emit_literal
	cmp.b	#$f8,d0
	blt.s	emit_literal
	bra.s	emit_code                       ; yes: a delta
emit_common:
	lea	common_literals(pc),a1          ; the commonest
	move.l	a1,d0
	lea	$10(a1),a2                      ; its end
	move.b	d5,(a2)+                        ; the byte put at the end
emit_common_find:
	cmp.b	(a1)+,d5                        ; found?
	bne.s	emit_common_find                ; no: the next
	cmpa.l	a1,a2                           ; at the end?
	beq.s	emit_literal                    ; yes: a byte
	sub.l	a1,d0
	not.w	d0                              ; its number
emit_code:
	ori.w	#$30,d0                         ; '11' and 4 bits
	move.w	d0,d1
	moveq	#5,d3                           ; 6 bits
	bsr.w	put_bits
	bra.s	emit_one_bit
emit_literal:
	move.b	d5,(a5)+                        ; the byte
	lsr.b	#1,d7                           ; a 0 bit
	bcc.s	emit_literal_done               ; full?
	move.b	d7,(a5)+                        ; yes: written
	moveq	#-128,d7
emit_literal_done:
	bra.s	emit_next
emit_match:
	move.b	(a0)+,d5                        ; the second byte
	bsr.s	next_word                       ; its word: the length - 1
	lea	position_index(pc),a2
	move.w	d0,d6
	subq.w	#1,d6
	beq.s	emit_match_put
emit_match_skip:
	move.b	(a0)+,d2                        ; the match's bytes
	moveq	#0,d3
	move.b	d2,d3
	add.w	d3,d3
	addq.w	#2,0(a2,d3.w)                   ; their indexes past them
	subq.w	#1,d6
	bne.s	emit_match_skip
emit_match_put:
	bsr.s	put_length                      ; the offset and length
emit_one_bit:
	lsr.b	#1,d7
	bset	#$7,d7                          ; a 1 bit
	bcc.s	emit_next                       ; full?
	move.b	d7,(a5)+                        ; yes: written
	moveq	#-128,d7
emit_next:
	cmpa.l	next_undo_check(pc),a0          ; time for UNDO?
	bge.s	emit_check                      ; yes
emit_loop:	; from: next_word
	cmpa.l	a0,a4                           ; the end?
	bne.w	emit_block                      ; no
	rts

;------------------------------------------------------------------------------
; next_word: the byte d5's next word in position_lists, into d0.
;------------------------------------------------------------------------------
next_word:	; from: emit_block
	lea	position_lists(pc),a2
	move.w	d5,d0
	add.w	d0,d0
	lea	position_index(pc),a1
	adda.w	d0,a1
	move.w	(a1),d6                         ; its index
	addq.w	#2,(a1)                         ; past it
	add.w	d0,d0
	movea.l	0(a2,d0.w),a2                   ; its list
	adda.l	d6,a2
	move.w	(a2),d0                         ; the word
	rts
emit_check:	; from: emit_block
	lea	$13c(a0),a1
	move.l	a1,next_undo_check              ; the next check $13c on
	bsr.w	check_undo                      ; UNDO?
	tst.b	interrupted                     ; interrupted?
	beq.s	emit_loop                       ; no
	rts

;------------------------------------------------------------------------------
; put_length: the offset, then the length d0 (- 1): up to the split in unary, then 4, 8 or 14 bits after
; the split's zeros.
;------------------------------------------------------------------------------
put_length:	; from: emit_block
	bsr.s	put_offset                      ; the offset
	move.w	d0,d1
	subq.w	#1,d1
	sub.w	d4,d1                           ; past the split?
	bgt.s	put_length_four                 ; yes
	add.w	d4,d1
	move.w	d1,d3                           ; its zeros
	moveq	#1,d1                           ; and a 1
	bra.w	put_bits
put_length_four:
	subi.w	#$f,d1                          ; up to 15 more?
	bgt.s	put_length_eight                ; no
	addi.w	#$f,d1
	moveq	#4,d3                           ; 4 bits
	add.w	d4,d3                           ; and the zeros
	bra.s	put_bits
put_length_eight:
	subi.w	#$ff,d1                         ; up to 255 more?
	bgt.s	put_length_long                 ; no
	addi.w	#$ff,d1
	moveq	#12,d3                          ; 8 bits
	add.w	d4,d3                           ; and the zeros
	bra.s	put_bits
put_length_long:
	moveq	#26,d3                          ; 14 bits and the zeros
	add.w	d4,d3
	bra.s	put_bits

;------------------------------------------------------------------------------
; put_offset: the offset d1 in its class (offset_steps), with the class's prefix and bit count; with the
; offset nibble mode on, the low nibble goes first in its own code.
;------------------------------------------------------------------------------
put_offset:	; from: put_length
	lea	offset_steps(pc),a2             ; the steps
	move.l	a2,d3
put_offset_class:
	cmp.w	(a2)+,d1                        ; in this class?
	blt.s	put_offset_bits                 ; yes
	sub.w	-$2(a2),d1                      ; no: less the step
	bra.s	put_offset_class
put_offset_bits:
	sub.l	a2,d3
	neg.w	d3                              ; the class * 2 (2 up)
	or.w	offset_prefixes(pc,d3.w),d1     ; its prefix
	move.w	offset_bit_counts(pc,d3.w),d3   ; its bit count
	move.b	offset_nibble_mode(pc),d2       ; the nibble mode?
	beq.s	put_offset_rest                 ; no
	move.w	d1,d6
	andi.w	#$f,d6                          ; the low nibble
	lsr.w	#4,d1                           ; the rest
	lsr.b	#1,d6                           ; odd?
	bcs.s	put_offset_odd                  ; yes
	ori.b	#$78,d6                         ; even: '1111' and 3 bits
	move.w	d3,d2
	move.w	d1,d5
	move.w	d6,d1
	moveq	#6,d3                           ; 7 bits
	bra.s	put_offset_nibble
put_offset_odd:
	cmp.b	rarest_odd_nibble(pc),d6        ; the rarest?
	bne.s	put_offset_common               ; no
	lsl.w	#4,d1
	ori.w	#$e,d1                          ; '1110' and the rest
	bra.s	put_offset_rest
put_offset_common:
	move.b	odd_nibble_codes(pc,d6.w),d6    ; its 3-bit code
	move.w	d3,d2
	moveq	#2,d3                           ; 3 bits
	move.w	d1,d5
	move.w	d6,d1
put_offset_nibble:
	bsr.s	put_bits                        ; the code
	move.w	d5,d1                           ; the rest
	subq.w	#4,d2                           ; its bits less the nibble's
	move.w	d2,d3
put_offset_rest:
	subq.w	#1,d3                           ; for dbcs

;------------------------------------------------------------------------------
; put_bits: d3+1 bits of d1 (from bit 0) into the bit byte, written out each time it fills.
;------------------------------------------------------------------------------
put_bits:	; from: emit_block, put_length, put_offset
	lsr.w	#1,d1                           ; the next bit
	roxr.b	#1,d7                           ; in
	dbcs	d3,put_bits                     ; not full: the next
	bcc.s	put_bits_done                   ; all done
	move.b	d7,(a5)+                        ; full: written
	moveq	#-128,d7                        ; empty
	dbra	d3,put_bits                     ; the next
put_bits_done:
	rts

;------------------------------------------------------------------------------
; odd_nibble_codes: the 3-bit codes of the odd low nibbles (by nibble/2), the rarest's place skipped: the
; eighth is offset_prefixes' first byte.
;------------------------------------------------------------------------------
odd_nibble_codes:	; from: choose_offset_mode, put_offset
	dc.b	$00,$00,$00,$00,$00,$00

;------------------------------------------------------------------------------
; offset_prefixes: each class's prefix (from the second word: the class number is 1 up); the ninth is the
; first word of offset_bit_counts.
;------------------------------------------------------------------------------
offset_prefixes:	; from: put_offset
	dc.w	$0000,$0000,$0040,$0200,$0600,$1000,$2800,$6000

;------------------------------------------------------------------------------
; offset_bit_counts: each class's bit count (from the second word).
;------------------------------------------------------------------------------
offset_bit_counts:	; from: put_offset
	dc.w	$e000,$0008,$0009,$000b,$000c,$000d,$000e,$000f
	dc.w	$0010

;------------------------------------------------------------------------------
; write_header: the block's length, its split, then the literal table (16 bytes) and a 1 bit or a 0 bit,
; then the rarest odd nibble and a 1 bit or a 0 bit.
;------------------------------------------------------------------------------
write_header:	; from: write_block
	lea	block_length(pc),a2             ; the block's length
	move.b	1(a2),(a5)+                     ; low byte
	move.b	(a2),(a5)+                      ; high byte
	move.b	d4,(a5)+                        ; the split
	move.b	relative_mode(pc),d0            ; relative?
	beq.s	write_header_table              ; no
	bsr.s	put_zero_bit                    ; a 0 bit: no table
	bra.s	write_header_offsets
write_header_table:
	lea	common_literals_end(pc),a1      ; the commonest's end
	moveq	#15,d0                          ; 16
write_header_table_byte:
	move.b	-(a1),(a5)+                     ; backward
	dbra	d0,write_header_table_byte
	bsr.s	put_one_bit                     ; a 1 bit
write_header_offsets:
	move.b	offset_nibble_mode(pc),d0       ; the nibble mode?
	beq.s	put_zero_bit                    ; no: a 0 bit
	move.b	rarest_odd_nibble(pc),d0        ; the rarest
	add.b	d0,d0
	addq.b	#1,d0                           ; as its nibble
	move.b	d0,(a5)+

;------------------------------------------------------------------------------
; put_one_bit: a 1 bit.
;------------------------------------------------------------------------------
put_one_bit:	; from: write_header
	lsr.b	#1,d7
	bset	#$7,d7
	bra.s	put_bit_check

;------------------------------------------------------------------------------
; put_zero_bit: a 0 bit.
;------------------------------------------------------------------------------
put_zero_bit:	; from: write_header
	lsr.b	#1,d7
put_bit_check:	; from: put_one_bit
	bcc.s	put_bit_done                    ; full?
	move.b	d7,(a5)+                        ; yes: written
	moveq	#-128,d7                        ; empty
put_bit_done:
	rts

;------------------------------------------------------------------------------
; encode_picture: a low resolution picture (32000 bytes at a0) turned from four plane words to 4-bit pixels,
; four to a word, which pack better.  The stub turns them back.
;------------------------------------------------------------------------------
encode_picture:	; from: crunch_pictures
	lea	$7d00(a0),a1                    ; its end
encode_picture_group:
	movem.w	(a0),d0-d3                      ; 16 pixels' planes
	moveq	#3,d6                           ; 4 words
encode_picture_word:
	moveq	#3,d5                           ; 4 pixels
encode_picture_pixel:
	add.w	d0,d0                           ; plane 0
	addx.w	d4,d4
	add.w	d1,d1                           ; plane 1
	addx.w	d4,d4
	add.w	d2,d2                           ; plane 2
	addx.w	d4,d4
	add.w	d3,d3                           ; plane 3
	addx.w	d4,d4
	dbra	d5,encode_picture_pixel
	move.w	d4,(a0)+
	dbra	d6,encode_picture_word
	cmpa.l	a0,a1                           ; the end?
	bne.s	encode_picture_group            ; no
	rts

;------------------------------------------------------------------------------
; print_percent: " (nn%)" with nn = d1 * 100 / d0 (100% shows as 00%).
;------------------------------------------------------------------------------
print_percent:	; from: print_crunch_left, print_crunch_done, crunch_all_menu, crunch_file
	movem.l	d0-d1,-(sp)                     ; saved
	lea	percent_open_text(pc),a0        ; " ("
	bsr.w	print
	movem.l	(sp)+,d0-d1
	bsr.s	percent                         ; the percentage
	move.w	d1,d2
	bsr.w	to_bcd                          ; in BCD
	move.w	d3,d1
	bsr.w	print_hex_byte                  ; two digits
	lea	percent_close_text(pc),a0       ; "%)"
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; percent: d1 = d1 * 100 / d0, both scaled down to words first.
;------------------------------------------------------------------------------
percent:	; from: print_percent
	bsr.s	scale_to_words                  ; scaled
	divu.w	d0,d1
	swap	d1                              ; the remainder (d1 itself, as d1 < d0)
	mulu.w	#$64,d1                         ; * 100
	divu.w	d0,d1                           ; / d0
	ext.l	d1
	rts

;------------------------------------------------------------------------------
; scale_to_words: d0 and d1 halved together until both fit in a word.
;------------------------------------------------------------------------------
scale_to_words:	; from: percent
	moveq	#0,d2
	not.w	d2                              ; $ffff
scale_to_words_check:
	cmp.l	d2,d0                           ; d0 too big?
	bgt.s	scale_to_words_halve            ; yes
	cmp.l	d2,d1                           ; d1 too big?
	ble.s	scale_to_words_done             ; no
scale_to_words_halve:
	lsr.l	#1,d0                           ; halved
	lsr.l	#1,d1
	bra.s	scale_to_words_check
scale_to_words_done:
	rts

;------------------------------------------------------------------------------
; analyse_window: "ANALYSING DATA STRUCTURE": the window from a0 ($7fff bytes, or to the file's end, which
; makes it the last) counted by byte, and each byte's places (+1, from a0) listed in position_lists.
; a6 = the window's end.
;------------------------------------------------------------------------------
analyse_window:	; from: pack, match
	movem.l	d0-d2/a0-a5,-(sp)               ; saved
	clr.w	small_delta_count               ; no small deltas yet
	lea	analysing_text(pc),a0           ; "ANALYSING DATA STRUCTURE"
	bsr.w	print
	movea.l	$c(sp),a0                       ; the window's start (a0 as saved)
	lea	byte_counts(pc),a1              ; the counts
	moveq	#0,d0
	moveq	#127,d1                         ; and the indexes
analyse_window_clear:
	move.l	d0,(a1)+                        ; cleared
	move.l	d0,(a1)+
	dbra	d1,analyse_window_clear
	lea	$7fff(a0),a2                    ; $7fff bytes on
	cmpa.l	input_end(pc),a2                ; past the file's end?
	ble.s	analyse_window_count            ; no
	movea.l	input_end(pc),a2                ; yes: to the end
	move.w	#$601e,window_last              ; the last window
analyse_window_count:
	movea.l	a0,a1
	lea	byte_counts(pc),a3              ; the counts
analyse_window_count_byte:
	moveq	#0,d0
	move.b	(a1)+,d0                        ; the byte
	add.w	d0,d0
	addq.w	#1,0(a3,d0.w)                   ; counted
	cmpa.l	a1,a2                           ; the end?
	bgt.s	analyse_window_count_byte       ; no
	move.w	#$ff,d1                         ; 256
	moveq	#0,d0
	lea	positions(pc),a4                ; the places
	lea	position_lists(pc),a6           ; the lists' starts
	movea.l	a4,a5
	moveq	#0,d0
analyse_window_list:
	adda.l	d0,a5                           ; after the last list
	move.w	(a3)+,d0                        ; its count
	move.l	a5,(a6)+                        ; this list's start
	add.w	d0,d0                           ; its length
	dbra	d1,analyse_window_list
	lea	position_index(pc),a4           ; the indexes
	movea.l	a0,a1                           ; the window
	moveq	#0,d1
analyse_window_place:
	moveq	#0,d0
	move.b	(a1)+,d0                        ; the byte
	move.l	a1,d2                           ; its place + 1
	add.w	d0,d0
	movea.l	a4,a5
	adda.w	d0,a5                           ; its index
	move.w	(a5),d1
	addq.w	#2,(a5)                         ; past it
	add.w	d0,d0
	movea.l	position_lists(pc,d0.w),a5      ; its list
	adda.l	d1,a5
	sub.l	a0,d2                           ; from the window's start
	move.w	d2,(a5)                         ; listed
	cmpa.l	a1,a2                           ; the end?
	bgt.s	analyse_window_place            ; no
	movea.l	a2,a6                           ; the window's end
	lea	position_index(pc),a3           ; the indexes
	moveq	#127,d0                         ; 512 bytes
	moveq	#0,d1
analyse_window_clear_index:
	move.l	d1,(a3)+                        ; cleared
	dbra	d0,analyse_window_clear_index
	lea	clear_to_end_text(pc),a0        ; the line cleared
	bsr.w	print
	lea	up_two_lines_text(pc),a0        ; up two lines
	bsr.w	print
	movem.l	(sp)+,d0-d2/a0-a5
	rts

;------------------------------------------------------------------------------
; position_lists: each byte's list's start (256 longs into positions).
;------------------------------------------------------------------------------
position_lists:	; from: match, window_last, next_word, analyse_window
	dcb.b	1024,0

;------------------------------------------------------------------------------
; byte_counts: each byte's count in the window (256 words), less those passed.
;------------------------------------------------------------------------------
byte_counts:	; from: match, window_last, analyse_window
	dcb.b	512,0

;------------------------------------------------------------------------------
; position_index: each byte's index in its list (256 words, in bytes).
;------------------------------------------------------------------------------
position_index:	; from: window_last, clear_indexes, emit_block, next_word, analyse_window
	dcb.b	512,0

;------------------------------------------------------------------------------
; unpack: the packed data (a1 its lengths, to a2) moved down to a0 and depacked, from its end back,
; into the room $1000 above it; the pictures turned back, then the file moved down to a0.  d0 = its length.
; A block starts (read backward) with a bit for the offset nibble codes (then the rarest odd nibble), a bit
; for the literal table (then 16 bytes), the length split and the block's length.  Then until the block
; is done: a 0 bit and a byte, or a 1 bit and a length (up to the split in unary, then 4, 8 or 14 bits),
; with a length of 0 either a 1 bit and a 4-bit literal code, or a 0 bit and a 2-byte match with a short
; offset; any other a 3-bit class and its offset.
;------------------------------------------------------------------------------
unpack:	; from: unpack_program
	movea.l	a0,a3                           ; the destination
unpack_copy:
	move.l	(a1)+,(a3)+                     ; moved down
	move.l	(a1)+,(a3)+
	cmpa.l	a1,a2                           ; the end?
	bgt.s	unpack_copy                     ; no
	movem.l	d1-d7/a0-a6,-(sp)               ; saved
	link	a2,#-28                         ; the locals
	move.l	(a0)+,d0                        ; the unpacked length
	lea	4(a0,d0.l),a5                   ; its end
	move.l	d0,-(sp)                        ; kept
	movea.l	a5,a4
	lea	$1000(a4),a5                    ; $1000 up: the room to depack into
	subq.w	#8,a4                           ; the lengths' room
	move.l	(a0)+,d0                        ; the packed length
	movea.l	a0,a6
	adda.l	d0,a6                           ; its end
	clr.w	-$2(a2)                         ; no pictures
	move.b	unpack_no_pictures(pc),d0       ; the normal stub's?
	bne.s	unpack_start                    ; yes: no picture count
	moveq	#0,d0
	move.b	-(a6),d0                        ; the number of pictures
	move.w	d0,-$2(a2)
	lsl.w	#2,d0                           ; their offsets
	suba.w	d0,a4                           ; before the end
unpack_start:
	sf	unpack_no_pictures
	pea	(a4)                            ; the file's end, without the offsets
	pea	(a5)                            ; the output's end
	move.b	-(a6),d7                        ; the first bit byte
	bra.w	depack_block                    ; the first block
depack_code:	; from: depack_get_bits
	move.w	d3,d5                           ; the split
depack_unary:
	add.b	d7,d7                           ; the next bit
depack_unary_bit:
	dbcs	d5,depack_unary                 ; a 1 ends it
	beq.s	depack_unary_refill             ; empty: refilled
	bcc.s	depack_length_four              ; past the split?
	sub.w	d3,d5                           ; no
	neg.w	d5                              ; the length
	bra.s	depack_length
depack_length_four:
	moveq	#3,d6                           ; 4 bits
	bsr.s	depack_get_bits
	beq.s	depack_length_eight             ; 0?
	bra.s	depack_length_add               ; no
depack_length_eight:
	moveq	#7,d6                           ; 8 bits
	bsr.s	depack_get_bits
	beq.s	depack_length_long              ; 0?
	addi.w	#$f,d5                          ; no: 15 more
	bra.s	depack_length_add
depack_unary_refill:
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	depack_unary_bit
depack_length_long:
	moveq	#13,d6                          ; 14 bits
	bsr.s	depack_get_bits
	addi.w	#$10e,d5                        ; 270 more
depack_length_add:
	add.w	d3,d5                           ; + the split
depack_length:
	lea	offset_bases(pc),a4             ; the offset bases
	move.w	d5,d2                           ; the length
	bne.s	depack_offset_long              ; not 0
	add.b	d7,d7                           ; the next bit
	bne.s	depack_short
	move.b	-(a6),d7                        ; empty: refilled
	addx.b	d7,d7
depack_short:
	bcs.s	depack_literal_code             ; 1: a literal code
	moveq	#1,d6                           ; 0: a 2-byte match, 2-bit class
	bra.s	depack_offset_class
depack_literal_code:
	moveq	#3,d6                           ; 4 bits
	bsr.s	depack_get_bits
	tst.b	-$1c(a2)                        ; the literal table?
	beq.s	depack_delta                    ; no: a delta
	move.b	-$12(a2,d5.w),-(a5)             ; its byte
	bra.w	depack_block_check
depack_delta:
	move.b	(a5),d0                         ; the byte after
	btst	#$3,d5                          ; negative?
	bne.s	depack_delta_negative           ; yes
	bra.s	depack_delta_put
depack_delta_negative:
	addi.b	#$f0,d5                         ; -8..-1
depack_delta_put:
	sub.b	d5,d0                           ; less the delta
	move.b	d0,-(a5)
	bra.w	depack_block_check

;------------------------------------------------------------------------------
; depack_get_bits: d6+1 bits into d5 (Z set if 0).
;------------------------------------------------------------------------------
depack_get_bits:	; from: unpack
	clr.w	d5
depack_get_bits_loop:
	add.b	d7,d7                           ; the next bit
	beq.s	depack_get_bits_refill          ; empty: refilled
depack_get_bits_in:
	addx.w	d5,d5                           ; in
	dbra	d6,depack_get_bits_loop
	tst.w	d5
	rts
depack_get_bits_refill:
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	depack_get_bits_in
depack_offset_long:	; from: unpack
	moveq	#2,d6                           ; 3-bit class
depack_offset_class:	; from: unpack
	bsr.s	depack_get_bits                 ; the class
	move.w	d5,d4
	move.b	$e(a4,d4.w),d6                  ; its bit count
	ext.w	d6
	tst.b	-$1b(a2)                        ; the nibble codes?
	bne.s	depack_offset_nibble            ; yes
	addq.w	#4,d6                           ; no: 4 more
	bra.s	depack_offset_plain
depack_offset_nibble:
	bsr.s	depack_get_bits                 ; the high part
	move.w	d5,d1
	lsl.w	#4,d1
	moveq	#2,d6                           ; 3 bits
	bsr.s	depack_get_bits                 ; the nibble's code
	cmp.b	#$7,d5                          ; 7?
	blt.s	depack_offset_common            ; no: a common odd nibble
	moveq	#0,d6                           ; 1 bit
	bsr.s	depack_get_bits
	beq.s	depack_offset_rarest            ; 0: the rarest odd nibble
	moveq	#2,d6                           ; 1: 3 bits
	bsr.s	depack_get_bits
	add.w	d5,d5                           ; an even nibble
	or.w	d1,d5
	bra.s	depack_offset_base
depack_offset_rarest:
	or.b	-$1a(a2),d1                     ; the rarest odd nibble
	bra.s	depack_offset_odd
depack_offset_common:
	or.b	-$19(a2,d5.w),d1                ; its odd nibble
depack_offset_odd:
	move.w	d1,d5                           ; the offset
	bra.s	depack_offset_base
depack_offset_plain:
	bsr.s	depack_get_bits                 ; the offset
depack_offset_base:
	add.w	d4,d4
	beq.s	depack_copy                     ; class 0?
	add.w	-$2(a4,d4.w),d5                 ; no: + its base
depack_copy:
	lea	1(a5,d5.w),a4                   ; the source
	move.b	-(a4),-(a5)                     ; copied
depack_copy_byte:
	move.b	-(a4),-(a5)
	dbra	d2,depack_copy_byte
	bra.s	depack_block_check
depack_next:
	add.b	d7,d7                           ; the next bit
	bne.s	depack_flag
	move.b	-(a6),d7                        ; empty: refilled
	addx.b	d7,d7
depack_flag:
	bcs.s	depack_code_far                 ; 1: a code
	move.b	-(a6),-(a5)                     ; 0: a byte
depack_block_check:	; from: unpack
	cmpa.l	a5,a3                           ; the block done?
	bne.s	depack_next                     ; no
	cmpa.l	a6,a0                           ; all the data read?
	beq.s	unpack_done                     ; yes
depack_block:	; from: unpack
	moveq	#0,d6                           ; 1 bit
	bsr.w	depack_get_bits
	beq.s	depack_no_nibbles               ; 0: no nibble codes
	move.b	-(a6),d0                        ; the rarest odd nibble
	lea	-$1a(a2),a1
	move.b	d0,(a1)+
	moveq	#1,d1                           ; the odd nibbles
	moveq	#6,d2                           ; 7
depack_nibble_codes:
	cmp.b	d0,d1                           ; the rarest?
	bne.s	depack_nibble_code_set          ; no
	addq.w	#2,d1                           ; skipped
depack_nibble_code_set:
	move.b	d1,(a1)+
	addq.w	#2,d1
	dbra	d2,depack_nibble_codes
	st	-$1b(a2)                        ; on
	bra.s	depack_literal_table
depack_no_nibbles:
	sf	-$1b(a2)                        ; off
depack_literal_table:
	moveq	#0,d6                           ; 1 bit
	bsr.w	depack_get_bits
	beq.s	depack_no_literal_table         ; 0: no table
	lea	-$12(a2),a1                     ; the table
	moveq	#15,d0                          ; 16
depack_literal_table_byte:
	move.b	-(a6),(a1)+
	dbra	d0,depack_literal_table_byte
	st	-$1c(a2)                        ; on
	bra.s	depack_block_length
depack_no_literal_table:
	sf	-$1c(a2)                        ; off
depack_block_length:
	clr.w	d3
	move.b	-(a6),d3                        ; the split
	move.b	-(a6),d0                        ; the block's length
	lsl.w	#8,d0
	move.b	-(a6),d0
	movea.l	a5,a3
	suba.w	d0,a3                           ; the block's start
	bra.s	depack_next
depack_code_far:
	bra.w	depack_code
unpack_done:
	movea.l	(sp)+,a0                        ; the output's end
	pea	(a2)                            ; the frame kept
	bsr.s	unpack_pictures                 ; the pictures turned back
	movea.l	(sp)+,a2
	move.l	(sp)+,d1                        ; the file's end, without the offsets
	move.l	(sp)+,d0                        ; the unpacked length, with them
	bsr.s	unpack_move_down                ; moved down
	unlk	a2
	move.l	d1,d0                           ; its length
	movem.l	(sp)+,d1-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; offset_bases: each class's first offset (from the second word), then each class's bit count - 1 (bytes,
; at offset_bases+14).
;------------------------------------------------------------------------------
offset_bases:	; from: unpack
	dc.w	$0020,$0060,$0160,$0360,$0760,$0f60,$1f60
	dc.b	$00,$01,$03,$04,$05,$06,$07,$08

;------------------------------------------------------------------------------
; unpack_pictures: each picture turned back from 4-bit pixels to four plane words.
;------------------------------------------------------------------------------
unpack_pictures:	; from: depack_get_bits
	move.w	-$2(a2),d7
unpack_pictures_next:
	dbra	d7,unpack_picture               ; more?
	rts
unpack_picture:
	move.l	-(a0),d0                        ; its offset
	lea	0(a5,d0.l),a1                   ; the picture
	lea	$7d00(a1),a2                    ; its end
unpack_picture_group:
	moveq	#3,d6                           ; 4 words
unpack_picture_word:
	move.w	(a1)+,d0                        ; 4 pixels
	moveq	#3,d5
unpack_picture_bit:
	add.w	d0,d0                           ; plane 0
	addx.w	d1,d1
	add.w	d0,d0                           ; plane 1
	addx.w	d2,d2
	add.w	d0,d0                           ; plane 2
	addx.w	d3,d3
	add.w	d0,d0                           ; plane 3
	addx.w	d4,d4
	dbra	d5,unpack_picture_bit
	dbra	d6,unpack_picture_word
	movem.w	d1-d4,-$8(a1)                   ; the planes
	cmpa.l	a1,a2                           ; the end?
	bne.s	unpack_picture_group            ; no
	bra.s	unpack_pictures_next

;------------------------------------------------------------------------------
; unpack_move_down: the depacked file moved down to the buffer's start, 16 bytes at a time.
;------------------------------------------------------------------------------
unpack_move_down:	; from: depack_get_bits
	lsr.l	#4,d0                           ; /16
	subq.w	#8,a6                           ; the buffer's start
	sub.l	a6,d1                           ; the length
unpack_move_down_loop:
	move.l	(a5)+,(a6)+
	move.l	(a5)+,(a6)+
	move.l	(a5)+,(a6)+
	move.l	(a5)+,(a6)+
	dbra	d0,unpack_move_down_loop
	rts

;------------------------------------------------------------------------------
; picture_stub: the stub put before a packed program when pictures are set.
; The header's bra.s word is the stub's first instruction too: it jumps over the rest of the header.
; crunch_file sets the text length (the stub and the packed data) and the bss length (the room the
; depacking needs) and copies the stub before the packed data.
;------------------------------------------------------------------------------
picture_stub:	; from: crunch_file
	bra.s	picture_stub_text
picture_stub_text_length:	; from: crunch_file
	dc.l	$00000000
picture_stub_data_length:
	dc.l	$00000000
picture_stub_bss_length:	; from: crunch_file
	dc.l	$00000000
picture_stub_symbol_length:
	dc.l	$00000000
picture_stub_reserved:
	dc.l	$00000000
picture_stub_flags:
	dc.l	$00000000
picture_stub_absolute:
	dc.w	$ffff                           ; no relocation

;------------------------------------------------------------------------------
; picture_stub_text: the top of the screen cleared, the title shown, the program depacked behind the stub, relocated
; and its basepage set, then moved down over the stub by a mover copied past it, which runs the program.
;------------------------------------------------------------------------------
picture_stub_text:	; from: picture_stub
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	movea.l	d0,a0                           ; the screen
	move.w	#$17d,d0                        ; 382 longs
picture_stub_clear_screen:
	clr.l	(a0)+                           ; cleared
	dbra	d0,picture_stub_clear_screen
	move.w	#$4,(sp)                        ; Getrez
	trap	#14                             ; XBIOS
	tst.b	d0                              ; low?
	lea	picture_stub_title_text(pc),a0  ; the title
	beq.s	picture_stub_title              ; yes
	move.b	#$39,3(a0)                      ; no: column 25
picture_stub_title:
	pea	(a0)
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.w	#8,sp
	lea	picture_stub+$2e2(pc),a0        ; the packed data, after the stub
	move.l	(a0)+,d0                        ; the unpacked length
	bsr.w	picture_stub_depack             ; depacked
	movea.l	a5,a3                           ; the program's header
	lea	picture_stub_text-$100(pc),a6   ; the stub's basepage
	move.l	2(a3),d0                        ; its text length
	add.l	6(a3),d0                        ; + its data length
	add.l	$e(a3),d0                       ; + its symbol length
	lea	$1c(a3,d0.l),a0                 ; its relocation table
	move.l	8(a6),d0                        ; where its text runs
	lea	$1c(a3),a3                      ; its text
	lea	$10(a0),a4                      ; the mover's place
	tst.l	(a0)                            ; any relocation?
	beq.s	picture_stub_basepage           ; no
	adda.l	(a0)+,a3                        ; the first long
	moveq	#0,d1
picture_stub_relocate:
	add.l	d0,(a3)                         ; relocated
picture_stub_relocate_next:
	clr.b	-$1(a0)                         ; the table's bytes cleared as they are read
	move.b	(a0)+,d1                        ; the next step
	beq.s	picture_stub_basepage           ; the end?
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	picture_stub_relocate_step      ; no
	lea	$fe(a3),a3                      ; yes
	bra.s	picture_stub_relocate_next
picture_stub_relocate_step:
	adda.w	d1,a3                           ; on to the next long
	bra.s	picture_stub_relocate
picture_stub_basepage:
	lea	2(a5),a3                        ; the header's lengths
	addq.w	#8,a6                           ; p_tbase
	movea.l	(a6)+,a2
	move.l	(a3),(a6)+                      ; p_tlen
	move.l	(a3),d6                         ; the length to move
	adda.l	(a3)+,a2
	move.l	a2,(a6)+                        ; p_dbase
	move.l	(a3),(a6)+                      ; p_dlen
	add.l	(a3),d6
	adda.l	(a3)+,a2
	move.l	a2,(a6)+                        ; p_bbase
	move.l	(a3),(a6)+                      ; p_blen
	lea	picture_stub_mover(pc),a1       ; the mover
	moveq	#3,d0                           ; 16 bytes
	movea.l	a4,a2                           ; its place
picture_stub_copy_mover:
	move.l	(a1)+,(a4)+                     ; copied
	dbra	d0,picture_stub_copy_mover
	lea	picture_stub_text(pc),a3        ; the program goes here
	move.l	4(sp),d0                        ; the basepage
	lea	$1c(a5),a5                      ; the program's text
	jmp	(a2)                            ; the mover
picture_stub_mover:
	movea.l	a3,a4                           ; the start
picture_stub_mover_copy:
	move.l	(a5)+,(a3)+                     ; the text and data moved down
	subq.l	#4,d6
	bcc.s	picture_stub_mover_copy
picture_stub_mover_clear:
	clr.l	(a2)+                           ; the mover cleared, itself and this bra too (the prefetched bra still
                                                ;   runs, then 0 is ori.b, then, the clear of the last long, and the jmp
                                                ;   already fetched)
	bra.s	picture_stub_mover_clear
	clr.l	(a2)+
	jmp	(a4)                            ; run the program

;------------------------------------------------------------------------------
; picture_stub_depack: the packed data at a0 depacked backward to its end plus the decrunch space; a5 = the
; program, d6 the unpacked length.
;------------------------------------------------------------------------------
picture_stub_depack:	; from: picture_stub_text
	move.l	d0,-(sp)                        ; kept
	lea	4(a0,d0.l),a5                   ; the output's end
	move.l	(a0)+,d0                        ; the packed length
	movea.l	a0,a6
	adda.l	d0,a6                           ; its end
	link	a2,#-28                         ; the locals
	moveq	#0,d0
	move.b	-(a6),d0                        ; the number of pictures
	move.w	d0,-$2(a2)
	lsl.w	#2,d0
	suba.w	d0,a4                           ; (a4 is not used after this: left from unpack)
picture_stub_space:
	lea	2(a5),a5                        ; + the decrunch space (set by crunch_file)
	pea	(a5)                            ; the output's end kept
	move.b	-(a6),d7                        ; the first bit byte
	bra.w	picture_stub_depack_block       ; the first block
picture_stub_depack_code:	; from: picture_stub_depack_get_bits
	move.w	d3,d5                           ; the split
picture_stub_depack_unary:
	add.b	d7,d7                           ; the next bit
picture_stub_depack_unary_bit:
	dbcs	d5,picture_stub_depack_unary    ; a 1 ends it
	beq.s	picture_stub_depack_unary_refill ; empty: refilled
	bcc.s	picture_stub_depack_length_four ; past the split?
	sub.w	d3,d5                           ; no
	neg.w	d5                              ; the length
	bra.s	picture_stub_depack_length
picture_stub_depack_length_four:
	moveq	#3,d6                           ; 4 bits
	bsr.s	picture_stub_depack_get_bits
	beq.s	picture_stub_depack_length_eight ; 0?
	bra.s	picture_stub_depack_length_add  ; no
picture_stub_depack_length_eight:
	moveq	#7,d6                           ; 8 bits
	bsr.s	picture_stub_depack_get_bits
	beq.s	picture_stub_depack_length_long ; 0?
	addi.w	#$f,d5                          ; no: 15 more
	bra.s	picture_stub_depack_length_add
picture_stub_depack_unary_refill:
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	picture_stub_depack_unary_bit
picture_stub_depack_length_long:
	moveq	#13,d6                          ; 14 bits
	bsr.s	picture_stub_depack_get_bits
	addi.w	#$10e,d5                        ; 270 more
picture_stub_depack_length_add:
	add.w	d3,d5                           ; + the split
picture_stub_depack_length:
	lea	picture_stub_offset_bases(pc),a4 ; the offset bases
	move.w	d5,d2                           ; the length
	bne.s	picture_stub_depack_offset_long ; not 0
	add.b	d7,d7                           ; the next bit
	bne.s	picture_stub_depack_short
	move.b	-(a6),d7                        ; empty: refilled
	addx.b	d7,d7
picture_stub_depack_short:
	bcs.s	picture_stub_depack_literal_code ; 1: a literal code
	moveq	#1,d6                           ; 0: a 2-byte match, 2-bit class
	bra.s	picture_stub_depack_offset_class
picture_stub_depack_literal_code:
	moveq	#3,d6                           ; 4 bits
	bsr.s	picture_stub_depack_get_bits
	tst.b	-$1c(a2)                        ; the literal table?
	beq.s	picture_stub_depack_delta       ; no: a delta
	move.b	-$12(a2,d5.w),-(a5)             ; its byte
	bra.w	picture_stub_depack_block_check
picture_stub_depack_delta:
	move.b	(a5),d0                         ; the byte after
	btst	#$3,d5                          ; negative?
	bne.s	picture_stub_depack_delta_negative ; yes
	bra.s	picture_stub_depack_delta_put
picture_stub_depack_delta_negative:
	addi.b	#$f0,d5                         ; -8..-1
picture_stub_depack_delta_put:
	sub.b	d5,d0                           ; less the delta
	move.b	d0,-(a5)
	bra.w	picture_stub_depack_block_check

;------------------------------------------------------------------------------
; picture_stub_depack_get_bits: d6+1 bits into d5 (Z set if 0).
;------------------------------------------------------------------------------
picture_stub_depack_get_bits:	; from: picture_stub_depack
	clr.w	d5
picture_stub_depack_get_bits_loop:
	add.b	d7,d7                           ; the next bit
	beq.s	picture_stub_depack_get_bits_refill ; empty: refilled
picture_stub_depack_get_bits_in:
	addx.w	d5,d5                           ; in
	dbra	d6,picture_stub_depack_get_bits_loop
	tst.w	d5
	rts
picture_stub_depack_get_bits_refill:
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	picture_stub_depack_get_bits_in
picture_stub_depack_offset_long:	; from: picture_stub_depack
	moveq	#2,d6                           ; 3-bit class
picture_stub_depack_offset_class:	; from: picture_stub_depack
	bsr.s	picture_stub_depack_get_bits    ; the class
	move.w	d5,d4
	move.b	$e(a4,d4.w),d6                  ; its bit count
	ext.w	d6
	tst.b	-$1b(a2)                        ; the nibble codes?
	bne.s	picture_stub_depack_offset_nibble ; yes
	addq.w	#4,d6                           ; no: 4 more
	bra.s	picture_stub_depack_offset_plain
picture_stub_depack_offset_nibble:
	bsr.s	picture_stub_depack_get_bits    ; the high part
	move.w	d5,d1
	lsl.w	#4,d1
	moveq	#2,d6                           ; 3 bits
	bsr.s	picture_stub_depack_get_bits    ; the nibble's code
	cmp.b	#$7,d5                          ; 7?
	blt.s	picture_stub_depack_offset_common ; no: a common odd nibble
	moveq	#0,d6                           ; 1 bit
	bsr.s	picture_stub_depack_get_bits
	beq.s	picture_stub_depack_offset_rarest ; 0: the rarest odd nibble
	moveq	#2,d6                           ; 1: 3 bits
	bsr.s	picture_stub_depack_get_bits
	add.w	d5,d5                           ; an even nibble
	or.w	d1,d5
	bra.s	picture_stub_depack_offset_base
picture_stub_depack_offset_rarest:
	or.b	-$1a(a2),d1                     ; the rarest odd nibble
	bra.s	picture_stub_depack_offset_odd
picture_stub_depack_offset_common:
	or.b	-$19(a2,d5.w),d1                ; its odd nibble
picture_stub_depack_offset_odd:
	move.w	d1,d5                           ; the offset
	bra.s	picture_stub_depack_offset_base
picture_stub_depack_offset_plain:
	bsr.s	picture_stub_depack_get_bits    ; the offset
picture_stub_depack_offset_base:
	add.w	d4,d4
	beq.s	picture_stub_depack_copy        ; class 0?
	add.w	-$2(a4,d4.w),d5                 ; no: + its base
picture_stub_depack_copy:
	lea	1(a5,d5.w),a4                   ; the source
	move.b	-(a4),-(a5)                     ; copied
picture_stub_depack_copy_byte:
	move.b	-(a4),-(a5)
	dbra	d2,picture_stub_depack_copy_byte
	bra.s	picture_stub_depack_block_check
picture_stub_depack_next:
	add.b	d7,d7                           ; the next bit
	bne.s	picture_stub_depack_flag
	move.b	-(a6),d7                        ; empty: refilled
	addx.b	d7,d7
picture_stub_depack_flag:
	bcs.s	picture_stub_depack_code_far    ; 1: a code
	move.b	-(a6),-(a5)                     ; 0: a byte
picture_stub_depack_block_check:	; from: picture_stub_depack
	cmpa.l	a5,a3                           ; the block done?
	bne.s	picture_stub_depack_next        ; no
	cmpa.l	a6,a0                           ; all the data read?
	beq.s	picture_stub_depack_done        ; yes
picture_stub_depack_block:	; from: picture_stub_depack
	moveq	#0,d6                           ; 1 bit
	bsr.w	picture_stub_depack_get_bits
	beq.s	picture_stub_depack_no_nibbles  ; 0: no nibble codes
	move.b	-(a6),d0                        ; the rarest odd nibble
	lea	-$1a(a2),a1
	move.b	d0,(a1)+
	moveq	#1,d1                           ; the odd nibbles
	moveq	#6,d2                           ; 7
picture_stub_depack_nibble_codes:
	cmp.b	d0,d1                           ; the rarest?
	bne.s	picture_stub_depack_nibble_code_set ; no
	addq.w	#2,d1                           ; skipped
picture_stub_depack_nibble_code_set:
	move.b	d1,(a1)+
	addq.w	#2,d1
	dbra	d2,picture_stub_depack_nibble_codes
	st	-$1b(a2)                        ; on
	bra.s	picture_stub_depack_literal_table
picture_stub_depack_no_nibbles:
	sf	-$1b(a2)                        ; off
picture_stub_depack_literal_table:
	moveq	#0,d6                           ; 1 bit
	bsr.w	picture_stub_depack_get_bits
	beq.s	picture_stub_depack_no_literal_table ; 0: no table
	lea	-$12(a2),a1                     ; the table
	moveq	#15,d0                          ; 16
picture_stub_depack_literal_table_byte:
	move.b	-(a6),(a1)+
	dbra	d0,picture_stub_depack_literal_table_byte
	st	-$1c(a2)                        ; on
	bra.s	picture_stub_depack_block_length
picture_stub_depack_no_literal_table:
	sf	-$1c(a2)                        ; off
picture_stub_depack_block_length:
	clr.w	d3
	move.b	-(a6),d3                        ; the split
	move.b	-(a6),d0                        ; the block's length
	lsl.w	#8,d0
	move.b	-(a6),d0
	movea.l	a5,a3
	suba.w	d0,a3                           ; the block's start
	bra.s	picture_stub_depack_next
picture_stub_depack_code_far:
	bra.w	picture_stub_depack_code
picture_stub_depack_done:
	movea.l	(sp)+,a0                        ; the output's end
	bsr.s	picture_stub_pictures           ; the pictures turned back
	unlk	a2
	move.l	(sp)+,d6                        ; the unpacked length
	rts
picture_stub_offset_bases:	; from: picture_stub_depack
	dc.w	$0020,$0060,$0160,$0360,$0760,$0f60,$1f60
	dc.b	$00,$01,$03,$04,$05,$06,$07,$08

;------------------------------------------------------------------------------
; picture_stub_pictures: each picture turned back from 4-bit pixels to four plane words.
;------------------------------------------------------------------------------
picture_stub_pictures:	; from: picture_stub_depack_get_bits
	move.w	-$2(a2),d7
picture_stub_pictures_next:
	dbra	d7,picture_stub_picture         ; more?
	rts
picture_stub_picture:
	movea.l	a5,a1
	adda.l	-(a0),a1                        ; + its offset: the picture
	move.w	#$1f3f,d0                       ; (not used)
	lea	$7d00(a1),a3                    ; its end
picture_stub_picture_group:
	moveq	#3,d6                           ; 4 words
picture_stub_picture_word:
	move.w	(a1)+,d0                        ; 4 pixels
	moveq	#3,d5
picture_stub_picture_bit:
	add.w	d0,d0                           ; plane 0
	addx.w	d1,d1
	add.w	d0,d0                           ; plane 1
	addx.w	d2,d2
	add.w	d0,d0                           ; plane 2
	addx.w	d3,d3
	add.w	d0,d0                           ; plane 3
	addx.w	d4,d4
	dbra	d5,picture_stub_picture_bit
	dbra	d6,picture_stub_picture_word
	movem.w	d1-d4,-$8(a1)                   ; the planes
	cmpa.l	a1,a3                           ; the end?
	bne.s	picture_stub_picture_group      ; no
	bra.s	picture_stub_pictures_next

;------------------------------------------------------------------------------
; picture_stub_title_text: the title at row 0, column 5 (25 when not low resolution); it ends at
; offset_steps' first byte.
;------------------------------------------------------------------------------
picture_stub_title_text:	; from: picture_stub_text
	dc.b	27,'Y %ATOMIK v3.5 by ALTAIR VMAX/MCS'

;------------------------------------------------------------------------------
; offset_steps: the offsets' classes' sizes (their sum is $3f60, the search's reach).  The picture
; stub ends here: the packed data goes after it.
;------------------------------------------------------------------------------
offset_steps:	; from: put_offset, picture_stub_text
	dc.w	$0020,$0040,$0100,$0200,$0400,$0800,$1000,$2000

;------------------------------------------------------------------------------
; stub: the stub put before a packed program.
; The header's bra.s word is the stub's first instruction too: it jumps over the rest of the header.
; crunch_file sets the text length (the stub and the packed data) and the bss length (the room the
; depacking needs) and copies the stub before the packed data.
;------------------------------------------------------------------------------
stub:	; from: crunch_file
	bra.s	stub_text
stub_text_length:	; from: crunch_file
	dc.l	$00000000
stub_data_length:
	dc.l	$00000000
stub_bss_length:	; from: crunch_file
	dc.l	$00000000
stub_symbol_length:
	dc.l	$00000000
stub_reserved:
	dc.l	$00000000
stub_flags:
	dc.l	$00000000
stub_absolute:
	dc.w	$ffff                           ; no relocation

;------------------------------------------------------------------------------
; stub_text: the top of the screen cleared, the title shown, the program depacked behind the stub, relocated
; and its basepage set, then moved down over the stub by a mover copied past it, which runs the program.
;------------------------------------------------------------------------------
stub_text:	; from: stub
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	movea.l	d0,a0                           ; the screen
	move.w	#$17d,d0                        ; 382 longs
stub_clear_screen:
	clr.l	(a0)+                           ; cleared
	dbra	d0,stub_clear_screen
	move.w	#$4,(sp)                        ; Getrez
	trap	#14                             ; XBIOS
	tst.b	d0                              ; low?
	lea	stub_title_text(pc),a0          ; the title
	beq.s	stub_title                      ; yes
	move.b	#$39,3(a0)                      ; no: column 25
stub_title:
	pea	(a0)
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.w	#8,sp
	lea	stub+$290(pc),a0                ; the packed data, after the stub
	move.l	(a0)+,d0                        ; the unpacked length
	bsr.w	stub_depack                     ; depacked
	movea.l	a5,a3                           ; the program's header
	lea	stub_text-$100(pc),a6           ; the stub's basepage
	move.l	2(a3),d0                        ; its text length
	add.l	6(a3),d0                        ; + its data length
	add.l	$e(a3),d0                       ; + its symbol length
	lea	$1c(a3,d0.l),a0                 ; its relocation table
	move.l	8(a6),d0                        ; where its text runs
	lea	$1c(a3),a3                      ; its text
	lea	$10(a0),a4                      ; the mover's place
	tst.l	(a0)                            ; any relocation?
	beq.s	stub_basepage                   ; no
	adda.l	(a0)+,a3                        ; the first long
	moveq	#0,d1
stub_relocate:
	add.l	d0,(a3)                         ; relocated
stub_relocate_next:
	clr.b	-$1(a0)                         ; the table's bytes cleared as they are read
	move.b	(a0)+,d1                        ; the next step
	beq.s	stub_basepage                   ; the end?
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	stub_relocate_step              ; no
	lea	$fe(a3),a3                      ; yes
	bra.s	stub_relocate_next
stub_relocate_step:
	adda.w	d1,a3                           ; on to the next long
	bra.s	stub_relocate
stub_basepage:
	lea	2(a5),a3                        ; the header's lengths
	addq.w	#8,a6                           ; p_tbase
	movea.l	(a6)+,a2
	move.l	(a3),(a6)+                      ; p_tlen
	move.l	(a3),d6                         ; the length to move
	adda.l	(a3)+,a2
	move.l	a2,(a6)+                        ; p_dbase
	move.l	(a3),(a6)+                      ; p_dlen
	add.l	(a3),d6
	adda.l	(a3)+,a2
	move.l	a2,(a6)+                        ; p_bbase
	move.l	(a3),(a6)+                      ; p_blen
	lea	stub_mover(pc),a1               ; the mover
	moveq	#3,d0                           ; 16 bytes
	movea.l	a4,a2                           ; its place
stub_copy_mover:
	move.l	(a1)+,(a4)+                     ; copied
	dbra	d0,stub_copy_mover
	lea	stub_text(pc),a3                ; the program goes here
	move.l	4(sp),d0                        ; the basepage
	lea	$1c(a5),a5                      ; the program's text
	jmp	(a2)                            ; the mover
stub_mover:
	movea.l	a3,a4                           ; the start
stub_mover_copy:
	move.l	(a5)+,(a3)+                     ; the text and data moved down
	subq.l	#4,d6
	bcc.s	stub_mover_copy
stub_mover_clear:
	clr.l	(a2)+                           ; the mover cleared, itself and this bra too (the prefetched bra still
                                                ;   runs, then 0 is ori.b, then, the clear of the last long, and the jmp
                                                ;   already fetched)
	bra.s	stub_mover_clear
	clr.l	(a2)+
	jmp	(a4)                            ; run the program

;------------------------------------------------------------------------------
; stub_depack: the packed data at a0 depacked backward to its end plus the decrunch space; a5 = the
; program, d6 the unpacked length.
;------------------------------------------------------------------------------
stub_depack:	; from: stub_text
	move.l	d0,-(sp)                        ; kept
	lea	4(a0,d0.l),a5                   ; the output's end
	move.l	(a0)+,d0                        ; the packed length
	movea.l	a0,a6
	adda.l	d0,a6                           ; its end
	link	a2,#-26                         ; the locals
stub_space:
	lea	2(a5),a5                        ; + the decrunch space (set by crunch_file)
	move.b	-(a6),d7                        ; the first bit byte
	bra.w	stub_depack_block               ; the first block
stub_depack_code:	; from: stub_depack_get_bits
	move.w	d3,d5                           ; the split
stub_depack_unary:
	add.b	d7,d7                           ; the next bit
stub_depack_unary_bit:
	dbcs	d5,stub_depack_unary            ; a 1 ends it
	beq.s	stub_depack_unary_refill        ; empty: refilled
	bcc.s	stub_depack_length_four         ; past the split?
	sub.w	d3,d5                           ; no
	neg.w	d5                              ; the length
	bra.s	stub_depack_length
stub_depack_length_four:
	moveq	#3,d6                           ; 4 bits
	bsr.s	stub_depack_get_bits
	beq.s	stub_depack_length_eight        ; 0?
	bra.s	stub_depack_length_add          ; no
stub_depack_length_eight:
	moveq	#7,d6                           ; 8 bits
	bsr.s	stub_depack_get_bits
	beq.s	stub_depack_length_long         ; 0?
	addi.w	#$f,d5                          ; no: 15 more
	bra.s	stub_depack_length_add
stub_depack_unary_refill:
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	stub_depack_unary_bit
stub_depack_length_long:
	moveq	#13,d6                          ; 14 bits
	bsr.s	stub_depack_get_bits
	addi.w	#$10e,d5                        ; 270 more
stub_depack_length_add:
	add.w	d3,d5                           ; + the split
stub_depack_length:
	lea	stub_offset_bases(pc),a4        ; the offset bases
	move.w	d5,d2                           ; the length
	bne.s	stub_depack_offset_long         ; not 0
	add.b	d7,d7                           ; the next bit
	bne.s	stub_depack_short
	move.b	-(a6),d7                        ; empty: refilled
	addx.b	d7,d7
stub_depack_short:
	bcs.s	stub_depack_literal_code        ; 1: a literal code
	moveq	#1,d6                           ; 0: a 2-byte match, 2-bit class
	bra.s	stub_depack_offset_class
stub_depack_literal_code:
	moveq	#3,d6                           ; 4 bits
	bsr.s	stub_depack_get_bits
	tst.b	-$1a(a2)                        ; the literal table?
	beq.s	stub_depack_delta               ; no: a delta
	move.b	-$10(a2,d5.w),-(a5)             ; its byte
	bra.w	stub_depack_block_check
stub_depack_delta:
	move.b	(a5),d0                         ; the byte after
	btst	#$3,d5                          ; negative?
	bne.s	stub_depack_delta_negative      ; yes
	bra.s	stub_depack_delta_put
stub_depack_delta_negative:
	addi.b	#$f0,d5                         ; -8..-1
stub_depack_delta_put:
	sub.b	d5,d0                           ; less the delta
	move.b	d0,-(a5)
	bra.w	stub_depack_block_check

;------------------------------------------------------------------------------
; stub_depack_get_bits: d6+1 bits into d5 (Z set if 0).
;------------------------------------------------------------------------------
stub_depack_get_bits:	; from: stub_depack
	clr.w	d5
stub_depack_get_bits_loop:
	add.b	d7,d7                           ; the next bit
	beq.s	stub_depack_get_bits_refill     ; empty: refilled
stub_depack_get_bits_in:
	addx.w	d5,d5                           ; in
	dbra	d6,stub_depack_get_bits_loop
	tst.w	d5
	rts
stub_depack_get_bits_refill:
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	stub_depack_get_bits_in
stub_depack_offset_long:	; from: stub_depack
	moveq	#2,d6                           ; 3-bit class
stub_depack_offset_class:	; from: stub_depack
	bsr.s	stub_depack_get_bits            ; the class
	move.w	d5,d4
	move.b	$e(a4,d4.w),d6                  ; its bit count
	ext.w	d6
	tst.b	-$19(a2)                        ; the nibble codes?
	bne.s	stub_depack_offset_nibble       ; yes
	addq.w	#4,d6                           ; no: 4 more
	bra.s	stub_depack_offset_plain
stub_depack_offset_nibble:
	bsr.s	stub_depack_get_bits            ; the high part
	move.w	d5,d1
	lsl.w	#4,d1
	moveq	#2,d6                           ; 3 bits
	bsr.s	stub_depack_get_bits            ; the nibble's code
	cmp.b	#$7,d5                          ; 7?
	blt.s	stub_depack_offset_common       ; no: a common odd nibble
	moveq	#0,d6                           ; 1 bit
	bsr.s	stub_depack_get_bits
	beq.s	stub_depack_offset_rarest       ; 0: the rarest odd nibble
	moveq	#2,d6                           ; 1: 3 bits
	bsr.s	stub_depack_get_bits
	add.w	d5,d5                           ; an even nibble
	or.w	d1,d5
	bra.s	stub_depack_offset_base
stub_depack_offset_rarest:
	or.b	-$18(a2),d1                     ; the rarest odd nibble
	bra.s	stub_depack_offset_odd
stub_depack_offset_common:
	or.b	-$17(a2,d5.w),d1                ; its odd nibble
stub_depack_offset_odd:
	move.w	d1,d5                           ; the offset
	bra.s	stub_depack_offset_base
stub_depack_offset_plain:
	bsr.s	stub_depack_get_bits            ; the offset
stub_depack_offset_base:
	add.w	d4,d4
	beq.s	stub_depack_copy                ; class 0?
	add.w	-$2(a4,d4.w),d5                 ; no: + its base
stub_depack_copy:
	lea	1(a5,d5.w),a4                   ; the source
	move.b	-(a4),-(a5)                     ; copied
stub_depack_copy_byte:
	move.b	-(a4),-(a5)
	dbra	d2,stub_depack_copy_byte
	bra.s	stub_depack_block_check
stub_depack_next:
	add.b	d7,d7                           ; the next bit
	bne.s	stub_depack_flag
	move.b	-(a6),d7                        ; empty: refilled
	addx.b	d7,d7
stub_depack_flag:
	bcs.s	stub_depack_code_far            ; 1: a code
	move.b	-(a6),-(a5)                     ; 0: a byte
stub_depack_block_check:	; from: stub_depack
	cmpa.l	a5,a3                           ; the block done?
	bne.s	stub_depack_next                ; no
	cmpa.l	a6,a0                           ; all the data read?
	beq.s	stub_depack_done                ; yes
stub_depack_block:	; from: stub_depack
	moveq	#0,d6                           ; 1 bit
	bsr.w	stub_depack_get_bits
	beq.s	stub_depack_no_nibbles          ; 0: no nibble codes
	move.b	-(a6),d0                        ; the rarest odd nibble
	lea	-$18(a2),a1
	move.b	d0,(a1)+
	moveq	#1,d1                           ; the odd nibbles
	moveq	#6,d2                           ; 7
stub_depack_nibble_codes:
	cmp.b	d0,d1                           ; the rarest?
	bne.s	stub_depack_nibble_code_set     ; no
	addq.w	#2,d1                           ; skipped
stub_depack_nibble_code_set:
	move.b	d1,(a1)+
	addq.w	#2,d1
	dbra	d2,stub_depack_nibble_codes
	st	-$19(a2)                        ; on
	bra.s	stub_depack_literal_table
stub_depack_no_nibbles:
	sf	-$19(a2)                        ; off
stub_depack_literal_table:
	moveq	#0,d6                           ; 1 bit
	bsr.w	stub_depack_get_bits
	beq.s	stub_depack_no_literal_table    ; 0: no table
	lea	-$10(a2),a1                     ; the table
	moveq	#15,d0                          ; 16
stub_depack_literal_table_byte:
	move.b	-(a6),(a1)+
	dbra	d0,stub_depack_literal_table_byte
	st	-$1a(a2)                        ; on
	bra.s	stub_depack_block_length
stub_depack_no_literal_table:
	sf	-$1a(a2)                        ; off
stub_depack_block_length:
	clr.w	d3
	move.b	-(a6),d3                        ; the split
	move.b	-(a6),d0                        ; the block's length
	lsl.w	#8,d0
	move.b	-(a6),d0
	movea.l	a5,a3
	suba.w	d0,a3                           ; the block's start
	bra.s	stub_depack_next
stub_depack_code_far:
	bra.w	stub_depack_code
stub_depack_done:
	unlk	a2
	move.l	(sp)+,d6                        ; the unpacked length
	rts
stub_offset_bases:	; from: stub_depack
	dc.w	$0020,$0060,$0160,$0360,$0760,$0f60,$1f60
	dc.b	$00,$01,$03,$04,$05,$06,$07,$08

;------------------------------------------------------------------------------
; stub_title_text: as the picture stub's; it ends at offset_nibble_counts' first byte.
;------------------------------------------------------------------------------
stub_title_text:	; from: stub_text
	dc.b	27,'Y %ATOMIK v3.5 by ALTAIR VMAX/MCS'

;------------------------------------------------------------------------------
; offset_nibble_counts: the matches' offsets counted by low nibble (16 words).  The normal stub ends
; here: the packed data goes after it.
;------------------------------------------------------------------------------
offset_nibble_counts:	; from: window_last, choose_offset_mode, clear_offset_counts, stub_text
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; odd_nibble_counts: the odd nibbles' counts, copied to be taken in order.
;------------------------------------------------------------------------------
odd_nibble_counts:	; from: choose_offset_mode
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; odd_nibbles_by_count: the odd nibbles (as nibble/2), commonest first.
;------------------------------------------------------------------------------
odd_nibbles_by_count:	; from: choose_offset_mode
	dc.b	$00,$00,$00,$00,$00,$00,$00
rarest_odd_nibble:	; from: put_offset, write_header
	dc.b	$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; not used

;------------------------------------------------------------------------------
; literal_counts: the literals counted by byte (256 words).
;------------------------------------------------------------------------------
literal_counts:	; from: window_last, choose_literal_mode, clear_statistics
	dcb.b	512,0

;------------------------------------------------------------------------------
; common_literals: the 16 commonest literals, commonest first.
;------------------------------------------------------------------------------
common_literals:	; from: choose_literal_mode, emit_block
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
common_literals_end:	; from: write_header
	dc.w	$0000

;------------------------------------------------------------------------------
; length_counts: the matches counted by length - 2 (256 words).
;------------------------------------------------------------------------------
length_counts:	; from: window_last
	dcb.b	512,0

;------------------------------------------------------------------------------
; length_sums: the matches of each length - 2 and longer (256 words).
;------------------------------------------------------------------------------
length_sums:	; from: choose_length_split
	dcb.b	512,0

;------------------------------------------------------------------------------
; long_length_count: the matches longer than 257.
;------------------------------------------------------------------------------
long_length_count:	; from: window_last, choose_length_split, clear_statistics
	dc.w	$0000
split_cost:	; from: choose_length_split
	dc.l	$00000000
split_best:
	dc.w	$0000
block_length:	; from: write_block, write_header
	dc.w	$0000
match_offset:	; from: match, window_last
	dc.w	$0000
match_length:	; from: window_last
	dc.w	$0000
match_flag:	; from: window_last
	dc.b	$00
data_mode:	; from: load_chosen, crunch_all_menu, crunch_file, print_text_hex_word, pack, write_block
	dc.b	$00
relative_mode:	; from: write_block, emit_block, write_header
	dc.b	$00
output_overrun:	; from: pack, match, window_last, write_block, clear_statistics
	dc.b	$00
offset_nibble_mode:	; from: choose_offset_mode, put_offset, write_header
	dc.b	$00
	dc.b	$00                             ; not used

;------------------------------------------------------------------------------
; small_delta_count: the literals within -8..7 of the next byte.
;------------------------------------------------------------------------------
small_delta_count:	; from: window_last, choose_literal_mode, analyse_window
	dc.w	$0000

;------------------------------------------------------------------------------
; min_gap: the least gap between input and output ($ff4 for none); the decrunch space comes from it.
;------------------------------------------------------------------------------
min_gap:	; from: check_undo, crunch_file, print_text_hex_word, write_block, clear_statistics, emit_block
	dc.w	$0000
largest_space:	; from: main_menu, crunch_all_menu, write_block
	dc.w	$0000
largest_space_before:
	dc.w	$0000
save_length:	; from: save_unpacked, crunch_file
	dc.l	$00000000
input_end:	; from: print_crunch_left, pack, emit_block, analyse_window
	dc.l	$00000000
total_ticks:	; from: print_total_time, print_time
	dc.l	$00000000
title_text:	; from: main_menu, unpack_menu, unpack_all_menu, unpack_data, unpack_program, load_chosen, 6 more
	dc.b	27,'E****************************',13,10,'*ATOMIK CRUNCHER3 BY ALTAIR*'
	dc.b	13,10,'*v3.6 completed on: 23/2/93*',13,10
	dc.b	'****************************',13,10,0
main_menu_text:	; from: main_menu
	dc.b	'F1: CRUNCH EXECUTABLE.',13,10,'F2: CRUNCH DATA FILE.',13,10
	dc.b	'F3: CRUNCH ALL FILES.',13,10,'F4: CRUNCH PARAMETERS.',13,10
	dc.b	'F5: EXIT FROM ATOMIK.',13,10,'F6: UNPACKER PROGRAM.',13,10,10
	dc.b	'NOW WARP 9 COMPATIBLE!',13,10,0
unpack_menu_text:	; from: unpack_menu
	dc.b	'F1: UNPACK EXECUTABLE.',13,10,'F2: UNPACK DATA FILE.',13,10
	dc.b	'F3: UNPACK ALL FILES.',13,10,'F4: EXIT FROM UNPACK.',13,10,0
unpack_all_menu_text:	; from: unpack_all_menu
	dc.b	'F1: UNPACK ALL IN EXEC MODE',13,10,'F2: UNPACK ALL IN DATA MODE',13,10
	dc.b	'F3: SET DIR TO BE UNPACKED.',13,10,'F4: EXIT FROM MULTI UNPACK.',13,10
	dc.b	0
parameters_menu_text:	; from: parameters_menu
	dc.b	'F1: EXTENDS FOR PARAMETERS',13,10,'F2: SET PICTURE PARAMETERS',13,10
	dc.b	'F3: CLEAR ALL PARAMETERS',13,10,'F4: EXIT FROM PARAMETERS',13,10,0
picture_number_text:	; from: set_pictures
	dc.b	27,'Y+ ENTER PICTURE NUMBER: ',0
offset_number_text:	; from: ask_picture_offset
	dc.b	27,'Y- ENTER OFFSET N.'
clear_to_end_text:	; from: crunch_pictures, analyse_window
	dc.b	$1b,$4b,$00
picture_parameters_text:	; from: crunch_file
	dc.b	27,'Y% PICTURE PARAMETERS N.',0
bad_offset_text:	; from: crunch_file
	dc.b	' BAD',10,13,27,'Y',$27,' OFFSET + 7D00 > FILE LENGTH',0
colon_text:	; from: ask_picture_offset
	dc.w	$3a20
	dc.b	$00
encoding_picture_text:	; from: crunch_pictures
	dc.b	27,'Y* ENCODING PICTURE N.',0
clear_parameters_text:	; from: parameters_menu
	dc.b	27,'Y* CLEAR PARAMETERS? (Y/N) ',0
parameters_cleared_text:	; from: parameters_menu
	dc.b	27,'Y* PARAMETERS CLEARED!',27,'K',0
crunch_all_menu_text:	; from: crunch_all_menu
	dc.b	'F1: CRUNCH ALL IN EXEC MODE',13,10,'F2: CRUNCH ALL IN DATA MODE',13,10
	dc.b	'F3: SET DIR TO BE CRUNCHED',13,10,'F4: EXIT FROM MULTI CRUNCH',0
empty_folder_text:	; from: unpack_all_menu, crunch_all_menu
	dc.b	27,'Y+ HEY! EMPTY DIRECTORY!',27,'K',0
ok_text:	; from: print_unpack_counts, crunch_all_menu
	dc.b	27,'Y) OK ',0
files_packed_text:	; from: crunch_all_menu
	dc.b	' FILE(S) PACKED',27,'K',0
in_text:	; from: print_unpack_counts, crunch_all_menu
	dc.b	27,'Y* IN ',0
files_loaded_text:	; from: print_unpack_counts, crunch_all_menu
	dc.b	' FILE(S) LOADED',27,'K',0
total_packed_text:	; from: crunch_all_menu
	dc.b	27,'Y. TOTAL PACKED LENGTH ',0
total_unpacked_text:	; from: crunch_all_menu
	dc.b	27,'Y. TOTAL PACKED LENGTH (100%) SHEAT!',0
files_unpacked_text:	; from: print_unpack_counts
	dc.b	' FILE(S) UNPACKED',27,'K',0
out_of_memory_text:	; from: take_memory
	dc.b	27,'Eout of memory!',0
cannot_crunch_text:	; from: print_text_hex_word
	dc.b	27,'Y% SORRY CANNOT CRUNCH..',27,'K',13,10,27,'K',0
crunching_text:	; from: crunch_file
	dc.b	27,'Y% CRUNCHING  : ',0
crunch_left_text:	; from: print_crunch_left
	dc.b	27,'Y',$27,' CRUNCH LEFT: ',0
crunch_done_text:	; from: print_crunch_done
	dc.b	27,'Y( CRUNCH DONE: ',0
save_length_text:	; from: save_unpacked, crunch_file
	dc.b	27,'Y) SAVE LENGTH:  ',0
file_text:	; from: save_unpacked, print_text_hex_word
	dc.b	27,'Y- FILE: ',0
saved_text:	; from: save_unpacked, print_text_hex_word
	dc.b	' SAVED',27,'K',0
unpacking_text:	; from: unpack_program
	dc.b	27,'Y% UNPACKING  : ',0
clear_row_11_text:	; from: crunch_all_menu
	dc.b	27,'Y+ ',27,'K',0
decrunch_space_text:	; from: print_text_hex_word
	dc.b	27,'Y+ DECRUNCH SPACE = $',0
total_space_text:	; from: crunch_all_menu
	dc.b	27,'Y, DECRUNCH SPACE = $',0
too_long_text:	; from: copy_found_name
	dc.b	27,'Y% FREE MEMORY < LENGHT FILE',0
not_program_text:	; from: unpack_program
	dc.b	27,'Y% NOT AN EXECUTABLE FILE!',0
not_atomik_text:	; from: unpack_data, unpack_program
	dc.b	27,'Y% THIS IS NOT AN ATOMIK V3.5 PACKED FILE!',0
no_room_text:	; from: unpack_program
	dc.b	27,'Y% NOT ENOUGHT MEMORY TO UNPACK THIS FILE!',0
write_error_text:	; from: save_unpacked, print_text_hex_word
	dc.b	27,'Y. WRITE ERROR! RETRY (Y/N)',27,'K',0
read_error_text:	; from: load_chosen, crunch_file
	dc.b	27,'Y% READ ERROR! ',0
crunching_time_text:	; from: print_total_time, print_time
	dc.b	27,'Y',$27,' CRUNCHING TIME:    ',27,'K',0
save_packed_text:	; from: print_text_hex_word
	dc.b	27,'Y- SAVE PACK FILE? (Y/N)',27,'K',0
save_unpacked_text:	; from: save_unpacked
	dc.b	27,'Y- SAVE UNPACKED FILE? (Y/N)',27,'K',0
interruption_text:	; from: check_undo, match_report
	dc.b	27,'Y',$27,'     INTERUPTION? (Y/N)',27,'K',13,10,27,'K',27,'I',0
analysing_text:	; from: analyse_window
	dc.b	27,'Y* ANALYSING DATA STRUCTURE',27,'K',13,0
huffman_text:	; from: write_block
	dc.b	27,'Y* HUFFMAN DATA PACK SYSTEM.',27,'K',0
relative_text:	; from: write_block
	dc.b	27,'Y* RELATIF DATA PACK SYSTEM.',27,'K',0
clear_row_8_text:	; from: crunch_all_menu, print_text_hex_word
	dc.b	27,'Y( ',27,'K',0
clear_row_10_text:	; from: write_block
	dc.b	27,'Y* ',27,'K',0
new_lines_text:	; from: set_pictures, crunch_file
	dc.b	13,10,13,10,0
up_two_lines_text:	; from: analyse_window
	dc.b	27,'I',27,'I',0
percent_open_text:	; from: print_percent
	dc.w	$2028
	dc.b	$00

;------------------------------------------------------------------------------
; percent_close_text: "%)", then nine backspaces and a 0 (not used), then the rub-outs before rub_out.
;------------------------------------------------------------------------------
percent_close_text:	; from: print_percent
	dc.b	$25,$29,$00,$08,$08,$08,$08,$08,$08,$08,$08,$08,$00,$08,$20,$08
	dc.b	$08,$20,$08,$08,$20,$08,$08,$20,$08,$08,$20,$08,$08,$20,$08,$08
	dc.b	$20,$08,$08,$20,$08

;------------------------------------------------------------------------------
; rub_out: "\b \b"; input_number goes back 3 bytes for each more digit to rub out.
;------------------------------------------------------------------------------
rub_out:	; from: input_number
	dc.w	$0820,$0800
bell_text:	; from: bell_flush
	dc.w	$0700
program_mask:	; from: unpack_all_menu, print_unpack_counts, load_chosen, crunch_all_menu
	dc.b	'*.PRG',0
any_mask:	; from: unpack_all_menu, print_unpack_counts, load_chosen, crunch_all_menu
	dc.b	'*.*',0

;------------------------------------------------------------------------------
; aes_block: the AES parameter block for fsel_input (90).
;------------------------------------------------------------------------------
aes_block:	; from: choose_file
	dc.l	aes_control
	dc.l	aes_global
	dc.l	aes_int_in
	dc.l	aes_int_out
	dc.l	aes_addr_in
	dc.l	aes_addr_out
aes_control:
	dc.w	$005a,$0000,$0002,$0002
aes_global:
	dc.w	$0120,$0001
aes_int_in:
	dc.w	$0000
aes_int_out:
	dc.w	$0001
fsel_button:	; from: choose_file
	dc.w	$0000,$0000                     ; OK or Cancel
aes_addr_in:
	dc.l	path_text
	dc.l	chosen_name
aes_addr_out:
	dc.w	$0000
path_text:	; from: choose_file, set_path, get_path, make_name
	dcb.b	79,0
chosen_name:	; from: make_name, copy_found_name
	dcb.b	65,0
full_name:	; from: unpack_all_menu, unpack_program, save_unpacked, make_name, load_file, write_file, 4 more
	dcb.b	66,0
dta:	; from: set_dta
	dcb.b	26,0
dta_length:	; from: load_file, find_first
	dc.w	$0000,$0000
dta_name:	; from: copy_found_name
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000
io_error:	; from: load_chosen, save_unpacked, load_file, write_file, crunch_all_menu, find_first, 3 more
	dc.w	$0000
file_handle:	; from: load_file, write_file
	dc.w	$0000
resolution:	; from: start
	dc.w	$0000
file_length:	; from: load_chosen, load_file, crunch_all_menu, crunch_file
	dc.w	$0000,$0000
total_length:	; from: crunch_all_menu, crunch_file
	dc.w	$0000,$0000
total_packed_length:	; from: crunch_all_menu, print_text_hex_word
	dc.w	$0000,$0000
load_buffer:	; from: main_menu, unpack_menu, unpack_data, unpack_program, save_unpacked, take_memory, 4 more
	dc.w	$0000,$0000
work_memory:	; from: print_crunch_done, crunch_file, pack, match_report
	dc.w	$0000,$0000
memory_free:	; from: unpack_program, take_memory, find_first
	dc.w	$0000,$0000
start_ticks:	; from: print_time, supervisor_call
	dc.w	$0000,$0000
end_ticks:	; from: print_time, supervisor_call
	dc.w	$0000,$0000
crunch_length:	; from: print_crunch_left, print_crunch_done, crunch_file, pack, match_report
	dc.w	$0000,$0000
crunch_left:	; from: print_crunch_left, crunch_file
	dc.w	$0000,$0000
next_report:	; from: print_crunch_left, pack, match
	dc.w	$0000,$0000
next_undo_check:	; from: pack, emit_block, next_word
	dc.w	$0000,$0000
time_text:	; from: print_time
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000
file_mask:	; from: load_chosen, save_unpacked, print_text_hex_word
	dc.w	$0000,$0000

;------------------------------------------------------------------------------
; picture_offsets: up to 50 pictures' offsets.
;------------------------------------------------------------------------------
picture_offsets:	; from: set_pictures, crunch_file, crunch_pictures
	dcb.b	200,0
picture_count:	; from: parameters_menu, set_pictures, crunch_file, crunch_pictures, pack
	dc.b	$00
pictures_on:	; from: crunch_file
	dc.b	$00
batch:	; from: unpack_all_menu, print_unpack_counts, unpack_data, unpack_program, load_chosen, save_unpacked, 5 more
	dc.b	$00
interrupted:	; from: check_undo, crunch_all_menu, crunch_file, pack, match_report, match, 3 more
	dc.b	$00
unpack_no_pictures:	; from: unpack_program, unpack
	dc.b	$00
unpack_program_mode:	; from: unpack_all_menu
	dc.b	$00
not_crunched:	; from: crunch_all_menu, crunch_file, print_text_hex_word
	dc.w	$0000
files_loaded:	; from: print_unpack_counts, crunch_all_menu
	dc.w	$0000
files_done:	; from: unpack_all_menu, print_unpack_counts, unpack_program, load_counted, crunch_all_menu
	dc.w	$0000
hex_text:	; from: print_hex
	dc.w	$2000,$0000,$0000,$0000,$0000

	section	bss

;------------------------------------------------------------------------------
; spare_bss: not used.
;------------------------------------------------------------------------------
spare_bss:	ds.b	280

;------------------------------------------------------------------------------
; positions: the places of each byte in the window, by byte (32K words).
;------------------------------------------------------------------------------
positions:	ds.b	65536
bss_end:

	end
