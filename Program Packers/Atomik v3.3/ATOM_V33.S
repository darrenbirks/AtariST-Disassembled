; ATOM_V33.PRG  -  Atomik Cruncher v3.3
; Devpac source of the program, disassembled by Darren Birks, 23 November 2026.
; Text 15070 bytes, no data, no bss.
;
; This source rebuilds the program unpacked, header and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o ATOM_V33.PRG ATOM_V33.S
;
; ATOM_V33.PRG, as it was released, is the same program packed by itself: an Atomik 3.3 stub (the same code as
; stub below, with its text length set) with the packed program after it.  This source is what that stub
; depacks.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; "ATOMIK CRUNCHER3 BY ALTAIR", "v3.3 Comleted on 15/4/1991": a TOS program driven by the keys 1 to 5 (the
; author's TOP_PROGRAM menu).  Low resolution is switched to medium, black on white; high stays as it is.
;   1   crunch a program ("*.PRG") chosen with the file selector
;   2   crunch a data file ("*.*")
;   3   crunch all: every file of a folder ("*.*" for both) in data mode or in program mode, each saved over
;       itself, then "OK nn FILE(S) PACKED IN nn FILE(S) LOADED" and the bell until a key
;   4   parameters: the offsets of up to 50 low resolution pictures in the file; its key 1 explains them
;   5   quit
; There is no unpacker, no F-key menu and no text column setting: the menus are fixed at column 26.  Esc while
; crunching asks "INTERUPTION? (Y/N)".
;
; A data file is saved as 'ATOM', the unpacked length, the packed length and the packed data.  A program is
; saved as a stub (a program of its own) with the lengths, the packed data and a zero long (no relocation)
; after it; the stub depacks the program behind itself, relocates it, sets the basepage and moves it down over
; itself.  With pictures set the picture stub is used, which also turns the pictures back.  The data packed is
; the file, then (in data mode always, in program mode with pictures) the pictures' offsets and their count
; as a word.
;
; The cruncher is simpler than 3.5's: no blocks, no statistics and no code choices; each code is written as it
; is found.  analyse_window lists the places of every byte in a window of $8000 bytes; match finds the longest
; match within $3f60 bytes ahead (the depacker works backward); a window is analysed again from the current
; byte when the reach passes its end.  The codes, read backward by the depacker:
;   - before each code, the count of the literals (bytes written as they are): 0-11 in unary, then 8 bits,
;     then 19 bits;
;   - a match: its length - 2 in unary up to 6, then 4, 8 or 14 bits; its offset in one of 8 classes (a 3-bit
;     class and 5 to 13 bits), or for a 2-byte match one of 5 classes within $3e0;
;   - a one-byte code where there is no match: the same byte among the next 8, or one of the four common bytes
;     $08, $10, $20 and $60 (the 2-byte match's classes 5-7).
; The output starts $4000 below the input; if it catches up the file is "SORRY CANNOT CRUNCH..".  The depacker
; uses a fixed margin of $7e bytes past the packed data instead of 3.5's decrunch space.
; A picture is first turned from four plane words to 4-bit pixels (encode_picture), which pack better.
;
; The author's DRI symbol table was left in the text when the program was packed: it is symbol_table at the
; end, and the notes name each label's original.  The header declares no bss, so everything the program needs
; past its end is reached at fixed places: positions (the original's bss, over the symbol table), then
; bss_end+$eec6 and bss_end+$ef0c (the two stubs' places), bss_end+$f144 (the packed data) and
; bss_end+$13144 (the load buffer).  take_memory Mallocs all but 10K for this but does not keep the address.
;
; Some things in it look unfinished or are wrong:
;   - A full window is $8000 bytes, so its last byte's place is $8000, negative to the search's adda.w: a
;     search whose next place is that one compares bytes $8000 back, outside the window, and a match found
;     there gets a wrong offset.  (3.5 makes the window $7fff bytes.)
;   - crunch_file does not check io_error: a file that cannot be opened or read is crunched as whatever the
;     load buffer holds, with the last file's length.  load_file reads up to $3f8000 bytes with no check of
;     the memory free.
;   - The crunch all counts are kept in BCD but printed through to_bcd as if binary: from 10 on they are wrong.
;     The packed count is never cleared, so it counts every run since the start.  Esc stops only the file
;     being crunched; the next one follows.
;   - The picture number is not checked against the 50 offsets there is room for.  A bad offset's message
;     counts the pictures from the first typed, while the prompts count from the last.
;   - "out of memory!" quits before the resolution and palette are saved: quit then sets low resolution and an
;     all-black palette.  In high resolution the palette is never saved but is still written back.
;   - The stack is left at the top of the TPA, in the 10K left free.
;   - match_try's case for a 2-byte match running past the reach never runs: it needs the best length to be
;     negative.
;   - The depacker skips a run of literals whose count's low word is 0 (65536 and its multiples).
;   - The stubs do not clear the program's bss: the relocation table's bytes are cleared as they are read,
;     and the mover clears only itself.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$06eb  the start-up, the main menu, the time, BCD, printing, keys, the file selector, the mouse,
;                memory, quit, load and write, hex, the progress, the parameters, input, crunch all, find
;   $06ec-$0997  crunch_file and the pictures
;   $0998-$0ec1  the cruncher: pack, match_report, match, put_match, put_offset, put_bits, put_literal_count,
;                encode_picture, analyse_window
;   $0ec2-$16c1  the search's tables
;   $16c2-$193f  the picture stub
;   $1940-$195f  the offset steps
;   $1960-$1b97  the normal stub
;   $1b98-$1bb1  the cruncher's variables, common_bytes
;   $1bb2-$2611  the texts
;   $2612-$288b  the AES block, the names, the variables, hex_text
;   $288c-$3add  the author's symbol table
;   past the end positions ($29a4), the stubs' places, the packed data and the load buffer
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; start: memory shrunk and taken, the mouse hidden and the resolution kept.  Low resolution is switched to
; medium, with the palette saved and set to black on white; then the main menu.
;------------------------------------------------------------------------------
start:	; from: symbol_table
	movea.l	4(sp),a5                        ; the basepage
	bsr.w	init_memory                     ; memory
	bsr.w	hide_mouse                      ; mouse hidden
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.w	#2,sp
	move.w	d0,resolution                   ; kept, for quit
	cmp.w	#$2,d0                          ; high?
	beq.s	main_menu                       ; yes: as it is
	move.w	#$1,-(sp)                       ; medium
	moveq	#-1,d0                          ; the screens as they are
	move.l	d0,-(sp)
	move.l	d0,-(sp)
	move.w	#$5,-(sp)
	trap	#14                             ; Setscreen
	lea	$c(sp),sp
	pea	save_palette(pc)                ; in the supervisor
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.w	#6,sp
	bra.s	main_menu                       ; the main menu

;------------------------------------------------------------------------------
; save_palette: the palette saved, colour 0 set white and colours 1-15 black (run in the supervisor).
;------------------------------------------------------------------------------
save_palette:	; from: start, symbol_table
	lea	$ffff8240.w,a0                  ; palette 0
	movem.l	(a0),d0-d7                      ; the 16 colours
	movem.l	d0-d7,saved_palette             ; saved
	move.w	#$7777,(a0)+                    ; colour 0 white
	moveq	#14,d0                          ; 15 more
save_palette_clear:
	clr.w	(a0)+                           ; black
	dbra	d0,save_palette_clear
	rts

;------------------------------------------------------------------------------
; main_menu: the author's TOP_PROGRAM.  Keys 1 crunch a program, 2 crunch a data file, 3 crunch all, 4 the
; parameters, 5 quit.
;------------------------------------------------------------------------------
main_menu:	; from: start, parameters_menu, crunch_all_menu, symbol_table
	lea	title_text(pc),a0               ; the title (the screen cleared)
	bsr.w	print
	lea	main_menu_text(pc),a0           ; "1: CRUNCH EXECUTABLE" ...
	bsr.w	print
main_menu_key:
	bsr.w	get_key                         ; a key
	cmp.w	#$31,d0                         ; '1'?
	beq.s	crunch_program                  ; crunch a program
	cmp.w	#$32,d0                         ; '2'?
	beq.s	crunch_data_file                ; crunch a data file
	cmp.w	#$33,d0                         ; '3'?
	beq.w	crunch_all_menu                 ; crunch all
	cmp.w	#$34,d0                         ; '4'?
	beq.w	parameters_menu                 ; the parameters
	cmp.w	#$35,d0                         ; '5'?
	bne.s	main_menu_key                   ; no: another key
	bra.w	quit                            ; quit
crunch_data_file:
	st	data_mode                       ; data mode
	lea	any_mask(pc),a3                 ; "*.*"
	bra.s	crunch_chosen
crunch_program:
	sf	data_mode                       ; program mode
	lea	program_mask(pc),a3             ; "*.PRG"
crunch_chosen:
	move.l	a3,file_mask                    ; the mask kept, for the save
	bsr.w	choose_file                     ; fsel_input
	tst.w	d0                              ; OK?
	bne.s	main_menu                       ; no: the menu
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	sf	batch                           ; not batch
	bsr.w	crunch_file                     ; loaded and crunched
	bra.s	main_menu                       ; the menu

;------------------------------------------------------------------------------
; print_time: "CRUNCHING TIME:" from start_ticks to end_ticks, as mmm:ss (no hours, unlike 3.5).
;------------------------------------------------------------------------------
print_time:	; from: crunch_file, symbol_table
	move.l	end_ticks(pc),d0                ; the end
	sub.l	start_ticks(pc),d0              ; less the start: 200 Hz ticks
	lsr.l	#3,d0                           ; /8
	moveq	#25,d1                          ; /25 by subtraction: seconds
	moveq	#0,d2                           ; the seconds
print_time_seconds:
	sub.l	d1,d0                           ; one more second?
	bmi.s	print_time_split                ; no
	addq.l	#1,d2                           ; yes
	bra.s	print_time_seconds
print_time_split:
	divu.w	#$3c,d2                         ; minutes, seconds
	lea	time_text(pc),a0                ; the text
	bsr.s	put_bcd3                        ; the minutes, three characters
	swap	d2                              ; the seconds
	bsr.s	to_bcd                          ; in BCD
	bsr.s	put_bcd2                        ; two digits
	clr.b	-(a0)                           ; the last ':' cut
	lea	crunching_time_text(pc),a0      ; "CRUNCHING TIME:"
	bsr.w	print                           ; printed
	lea	time_text(pc),a0                ; the time
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; put_bcd3: the number d2 into the text at a0 as three characters (the first a space if 0), then ':'.
;------------------------------------------------------------------------------
put_bcd3:	; from: print_time, symbol_table
	bsr.s	to_bcd                          ; in BCD
	move.w	d3,d4                           ; the hundreds
	lsr.w	#8,d4
	bne.s	put_bcd3_digit                  ; any?
	moveq	#-16,d4                         ; no: a space ('0'-16)
put_bcd3_digit:
	addi.w	#$30,d4                         ; as a digit
	move.b	d4,(a0)+                        ; in

;------------------------------------------------------------------------------
; put_bcd2: the BCD d3's two last digits into the text at a0, then ':'.
;------------------------------------------------------------------------------
put_bcd2:	; from: print_time, symbol_table
	move.w	d3,d4                           ; the tens
	lsr.w	#4,d4
	andi.w	#$f,d4
	addi.w	#$30,d4                         ; as a digit
	move.b	d4,(a0)+                        ; in
	move.w	d3,d4                           ; the units
	andi.w	#$f,d3
	addi.w	#$30,d3                         ; as a digit
	move.b	d3,(a0)+                        ; in
	move.b	#$3a,(a0)+                      ; ':'
	rts

;------------------------------------------------------------------------------
; to_bcd: the number d2 (0-99) in BCD into d3, by subtracting tens.  The author's HEXA_DEC.
;------------------------------------------------------------------------------
to_bcd:	; from: print_time, put_bcd3, print_decimal, symbol_table
	moveq	#0,d3                           ; the BCD
to_bcd_tens:
	subq.w	#8,d2                           ; a ten?
	subq.w	#2,d2
	bmi.s	to_bcd_units                    ; no more
	addq.w	#8,d3                           ; $10 more
	addq.w	#8,d3
	bra.s	to_bcd_tens                     ; the next
to_bcd_units:
	addq.w	#8,d2                           ; back
	addq.w	#2,d2
	add.w	d2,d3                           ; + the units
	rts

;------------------------------------------------------------------------------
; bcd_to_word: the BCD d2 (two digits) as a number in d3, by subtracting $10s.  The author's DEC_HEXA.
;------------------------------------------------------------------------------
bcd_to_word:	; from: set_pictures, symbol_table
	moveq	#0,d3                           ; the number
bcd_to_word_tens:
	subq.w	#8,d2                           ; a ten?
	subq.w	#8,d2
	bmi.s	bcd_to_word_units               ; no more
	addq.w	#8,d3                           ; 10 more
	addq.w	#2,d3
	bra.s	bcd_to_word_tens                ; the next
bcd_to_word_units:
	addq.w	#8,d2                           ; back
	addq.w	#8,d2
	add.w	d2,d3                           ; + the units
	rts

;------------------------------------------------------------------------------
; supervisor_call: runs the routine at a0 in the supervisor (Supexec).
;------------------------------------------------------------------------------
supervisor_call:	; from: crunch_file, symbol_table
	pea	(a0)                            ; the routine
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.w	#6,sp
	rts

;------------------------------------------------------------------------------
; read_start_time, read_end_time: _hz_200 into start_ticks or end_ticks (in the supervisor).
;------------------------------------------------------------------------------
read_start_time:	; from: crunch_file, symbol_table
	move.l	$4ba.w,start_ticks              ; _hz_200, the clock at the start
	rts
read_end_time:	; from: crunch_file, symbol_table
	move.l	$4ba.w,end_ticks                ; _hz_200, the clock at the end
	rts

;------------------------------------------------------------------------------
; print: prints the text at a0 (Cconws).
;------------------------------------------------------------------------------
print:	; from: main_menu, print_time, no_memory, print_hex, print_crunch_left, print_crunch_done, 12 more
	pea	(a0)                            ; the text
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.w	#6,sp
	rts

;------------------------------------------------------------------------------
; get_key: waits for a key (Crawcin): d0 the scan code in the high word, ASCII in the low.
;------------------------------------------------------------------------------
get_key:	; from: main_menu, no_memory, parameters_menu, input_number, crunch_all_menu, crunch_file, 3 more
	move.w	#$7,-(sp)
	trap	#1                              ; Crawcin
	addq.w	#2,sp
	rts

;------------------------------------------------------------------------------
; choose_file: the file selector with the path of the current folder and the mask at a3.  d0 0 for
; OK (the drive and folder chosen are set), -1 for Cancel.
;------------------------------------------------------------------------------
choose_file:	; from: main_menu, crunch_all_menu, crunch_file_save, symbol_table
	movem.l	d1-d3/a0-a2,-(sp)               ; saved
	bsr.w	show_mouse                      ; mouse shown
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
	bsr.w	hide_mouse                      ; mouse hidden
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
set_path:	; from: choose_file, symbol_table
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
get_path:	; from: choose_file, make_name, symbol_table
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
make_name:	; from: crunch_file, crunch_file_save, symbol_table
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
; hide_mouse: hides the mouse (Line-A $a).  The author's HIDE_CURSOR.
;------------------------------------------------------------------------------
hide_mouse:	; from: start, choose_file, load_file, write_file, close_file, symbol_table
	movem.l	d0-d2/a0-a2,-(sp)
	dc.w	$a00a                           ; Line-A $a, hide mouse
	movem.l	(sp)+,d0-d2/a0-a2
	rts

;------------------------------------------------------------------------------
; show_mouse: shows the mouse (Line-A $9), for the file selector and the disk alerts.  The author's
; SHOW_CURSOR.
;------------------------------------------------------------------------------
show_mouse:	; from: choose_file, quit, load_file, write_file, symbol_table
	movem.l	d0-d2/a0-a2,-(sp)
	dc.w	$a009                           ; Line-A $9, show mouse
	movem.l	(sp)+,d0-d2/a0-a2
	rts

;------------------------------------------------------------------------------
; init_memory: the program shrunk to its size, then all memory left but 10K taken.
;------------------------------------------------------------------------------
init_memory:	; from: start, symbol_table
	bsr.s	shrink                          ; shrunk
	bsr.s	take_memory                     ; taken
	rts

;------------------------------------------------------------------------------
; shrink: Mshrink to the program and $1000 bytes (the basepage and room).  The stack is not moved: it stays
; at the top of the TPA, in what take_memory leaves free.
;------------------------------------------------------------------------------
shrink:	; from: init_memory, symbol_table
	move.l	#$1000,d0                       ; $1000
	add.l	$c(a5),d0                       ; + the text
	add.l	$14(a5),d0                      ; + the data
	add.l	$1c(a5),d0                      ; + the bss (0)
	move.l	d0,-(sp)                        ; the size
	pea	(a5)                            ; the basepage
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
	rts

;------------------------------------------------------------------------------
; take_memory: the largest block less 10K taken (the author's SAVE_10K: the 10K left for the system).
; Its address is not kept: the program works at fixed places past its end (bss_end+...).
;------------------------------------------------------------------------------
take_memory:	; from: init_memory, symbol_table
	moveq	#-1,d0                          ; -1
	bsr.s	malloc                          ; Malloc(-1): the largest block
	subi.l	#$2800,d0                       ; less 10K
	bmi.s	no_memory                       ; none: "out of memory!"

;------------------------------------------------------------------------------
; malloc: Malloc(d0).
;------------------------------------------------------------------------------
malloc:	; from: take_memory
	move.l	d0,-(sp)                        ; the size
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.w	#6,sp
	rts

;------------------------------------------------------------------------------
; no_memory: "out of memory!", a key, then quit.  It runs before the resolution and palette are saved, so
; quit sets low resolution and an all-black palette.
;------------------------------------------------------------------------------
no_memory:	; from: take_memory, symbol_table
	lea	out_of_memory_text(pc),a0       ; "out of memory!"
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; a key

;------------------------------------------------------------------------------
; quit: the resolution and palette put back (the palette is written back in high resolution too, where it
; was never saved), the mouse shown and Pterm0.  The author's PTERM.
;------------------------------------------------------------------------------
quit:	; from: main_menu, symbol_table
	move.w	resolution(pc),-(sp)            ; the resolution at the start
	moveq	#-1,d0                          ; the screens as they are
	move.l	d0,-(sp)
	move.l	d0,-(sp)
	move.w	#$5,-(sp)
	trap	#14                             ; Setscreen
	lea	$c(sp),sp
	pea	restore_palette(pc)             ; in the supervisor
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.w	#6,sp
	bsr.s	show_mouse                      ; mouse shown
	clr.w	-(sp)
	trap	#1                              ; Pterm0

;------------------------------------------------------------------------------
; restore_palette: the palette saved put back (run in the supervisor).
;------------------------------------------------------------------------------
restore_palette:	; from: quit, symbol_table
	movem.l	saved_palette(pc),d0-d7         ; the colours saved
	movem.l	d0-d7,$ffff8240.w               ; palette 0
	rts

;------------------------------------------------------------------------------
; load_file: loads the file named in full_name into the load buffer (bss_end+$13144), up to $3f8000 bytes
; with no check of the memory.  file_length is its length; io_error is set if the read fails.  If the
; open fails nothing is set (file_length stays the last file's), and no caller checks io_error.
;------------------------------------------------------------------------------
load_file:	; from: crunch_file, symbol_table
	sf	io_error                        ; no error
	bsr.w	show_mouse                      ; mouse shown
	move.w	#$2,-(sp)                       ; read/write
	pea	full_name(pc)                   ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.w	#8,sp
	tst.w	d0                              ; opened?
	bmi.s	load_file_fail                  ; no
	move.w	d0,file_handle                  ; the handle
	pea	bss_end+$13144                  ; the load buffer
	move.l	#$3f8000,-(sp)                  ; at most $3f8000 bytes
	move.w	d0,-(sp)                        ; the handle
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	lea	$c(sp),sp
	tst.l	d0                              ; read?
	bmi.s	load_file_read_error            ; no
	move.l	d0,file_length                  ; the length read
	bra.s	load_file_close
load_file_read_error:
	st	io_error                        ; failed
load_file_close:
	bra.s	close_file                      ; closed
load_file_fail:
	bsr.w	hide_mouse                      ; mouse hidden
	rts

;------------------------------------------------------------------------------
; write_file: writes d2 bytes from a2 to the file named in full_name.  io_error is set if the write
; fails; d0 is minus if the create or the close fails.
;------------------------------------------------------------------------------
write_file:	; from: crunch_file_save, symbol_table
	bsr.w	show_mouse                      ; mouse shown
	sf	io_error                        ; no error
	clr.w	-(sp)                           ; normal file
	pea	full_name(pc)                   ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.w	#8,sp
	tst.w	d0                              ; created?
	bpl.s	write_file_created              ; yes
	bsr.w	hide_mouse                      ; mouse hidden
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

;------------------------------------------------------------------------------
; close_file: the mouse hidden and the file closed (Fclose); d0 minus if it fails.
;------------------------------------------------------------------------------
close_file:	; from: load_file, write_file, symbol_table
	bsr.w	hide_mouse                      ; mouse hidden
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.w	#4,sp
	tst.w	d0                              ; closed?
write_file_done:	; from: write_file, symbol_table
	rts

;------------------------------------------------------------------------------
; print_hex: prints the long d0 in hex, leading zeros as spaces, after a space.
;------------------------------------------------------------------------------
print_hex:	; from: print_crunch_left, print_crunch_done, crunch_file, symbol_table
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
	addi.w	#$30,d1                         ; as a character
	move.b	d1,(a1)+                        ; in
print_hex_next:
	dbra	d2,print_hex_digit
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; print_crunch_left: "CRUNCH LEFT:" the bytes from a4 to the end in hex, then the next report set $1fd
; further on, then as print_crunch_done.
;------------------------------------------------------------------------------
print_crunch_left:	; from: pack, match_report, symbol_table
	move.l	input_end(pc),d0                ; the end
	sub.l	a4,d0                           ; less where the search is
	move.l	d0,crunch_left                  ; left
	lea	$1fd(a4),a4                     ; $1fd on
	move.l	a4,next_report                  ; the next report
	lea	crunch_left_text(pc),a0         ; "CRUNCH LEFT: "
	bsr.w	print                           ; printed
	move.l	crunch_left(pc),d0              ; the bytes left
	bsr.s	print_hex                       ; in hex

;------------------------------------------------------------------------------
; print_crunch_done: "CRUNCH DONE:" the output so far (a5 from the packed data's start) in hex, then the
; cursor back up a line, for the next report to write over.
;------------------------------------------------------------------------------
print_crunch_done:
	lea	crunch_done_text(pc),a0         ; "CRUNCH DONE: "
	bsr.w	print                           ; printed
	move.l	a5,d0                           ; the output's end
	lea	bss_end+$f144,a0                ; less its start
	sub.l	a0,d0
	bsr.s	print_hex                       ; in hex
	lea	up_line_text(pc),a0             ; up a line
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; parameters_menu: 1 "extends" (the help page), 2 set the pictures' offsets, 3 clear them, 4 back.
;------------------------------------------------------------------------------
parameters_menu:	; from: main_menu, set_pictures, symbol_table
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	parameters_menu_text(pc),a0     ; "1: EXTENDS FOR PARAMETERS" ...
	bsr.w	print
parameters_menu_key:
	bsr.w	get_key                         ; a key
	cmp.w	#$31,d0                         ; '1'?
	beq.s	parameters_extends              ; the help page
	cmp.w	#$32,d0                         ; '2'?
	beq.s	set_pictures                    ; set the pictures
	cmp.w	#$33,d0                         ; '3'?
	beq.s	clear_parameters                ; clear them
	cmp.w	#$34,d0                         ; '4'?
	bne.s	parameters_menu_key             ; no: another key
	bra.w	main_menu                       ; the main menu
clear_parameters:
	lea	clear_parameters_text(pc),a0    ; "CLEAR PARAMETERS? (Y/N)"
	bsr.w	print                           ; printed
clear_parameters_answer:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$4e,d0                         ; 'N'?
	beq.s	parameters_menu                 ; yes: the menu
	cmp.w	#$59,d0                         ; 'Y'?
	bne.s	clear_parameters_answer         ; no: another key
	lea	parameters_cleared_text(pc),a0  ; "PARAMETERS CLEARED!"
	bsr.w	print
	clr.b	picture_count                   ; no pictures
	bsr.w	get_key                         ; a key
	bra.s	parameters_menu                 ; the menu
parameters_extends:
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	extends_text(pc),a0             ; "extends for use." ...
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; a key
	bra.s	parameters_menu                 ; the menu

;------------------------------------------------------------------------------
; set_pictures: "ENTER PICTURE NUMBER:" (two decimal digits), then the offset of each picture (five hex digits,
; even).  The number is not checked against the 50 offsets there is room for.
;------------------------------------------------------------------------------
set_pictures:	; from: parameters_menu
	lea	picture_number_text(pc),a0      ; "ENTER PICTURE NUMBER: "
	bsr.w	print
	moveq	#2,d3                           ; up to 2 digits
	moveq	#9,d6                           ; 0-9
	bsr.s	input_number                    ; typed
	bsr.w	bcd_to_word                     ; from BCD
	move.b	d3,picture_count                ; the number of pictures
	move.w	d3,d4                           ; to ask
	lea	new_lines_text(pc),a0           ; two new lines
	bsr.w	print                           ; printed
	lea	picture_offsets(pc),a2          ; the offsets
set_pictures_next:
	tst.b	d4                              ; more?
	beq.w	parameters_menu                 ; no: the menu
	bsr.s	ask_picture_offset              ; its offset
	move.l	d2,(a2)+                        ; kept
	bra.s	set_pictures_next

;------------------------------------------------------------------------------
; ask_picture_offset: "ENTER OFFSET N.nn: " for picture d4 until an even offset is typed; d4 one less.  The
; pictures are asked from the last number down.
;------------------------------------------------------------------------------
ask_picture_offset:	; from: set_pictures, symbol_table
	lea	offset_number_text(pc),a0       ; "ENTER OFFSET N."
	bsr.w	print                           ; printed
	move.w	d4,d1                           ; the picture
	bsr.s	print_decimal                   ; two digits
	lea	colon_text(pc),a0               ; ": "
	bsr.w	print                           ; printed
	moveq	#5,d3                           ; up to 5 digits
	moveq	#15,d6                          ; 0-F
	bsr.s	input_number                    ; typed
	lsr.w	#1,d2                           ; odd?
	bcs.s	ask_picture_offset              ; yes: again
	add.w	d2,d2                           ; back
	subq.w	#1,d4                           ; one done
	rts

;------------------------------------------------------------------------------
; print_decimal: prints the number d1 (0-99) as two decimal digits.  The author's PRINT2_D1.
;------------------------------------------------------------------------------
print_decimal:	; from: ask_picture_offset, crunch_all_menu, crunch_file, crunch_pictures, symbol_table
	movem.l	d2-d3,-(sp)                     ; kept
	move.w	d1,d2                           ; the number
	bsr.w	to_bcd                          ; in BCD
	move.w	d3,d1                           ; into d1
	movem.l	(sp)+,d2-d3
	move.w	d1,-(sp)                        ; kept
	lsr.w	#4,d1                           ; the tens
	addi.w	#$30,d1                         ; as a digit
	bsr.s	print_char                      ; printed
	move.w	(sp)+,d1
	andi.w	#$f,d1                          ; the units
	addi.w	#$30,d1                         ; as a digit
	bsr.s	print_char                      ; printed
	rts

;------------------------------------------------------------------------------
; print_char: prints the character d1 (Cconout).
;------------------------------------------------------------------------------
print_char:	; from: print_decimal, input_number, symbol_table
	move.w	d1,-(sp)
	move.w	#$2,-(sp)
	trap	#1                              ; Cconout
	addq.w	#4,sp
	rts

;------------------------------------------------------------------------------
; input_number: reads up to d3 digits of value 0 to d6 into d2 (4 bits each).  Return ends (once a digit is
; in), backspace takes one back; one digit more than d3 rubs out them all and starts again.
;------------------------------------------------------------------------------
input_number:	; from: set_pictures, ask_picture_offset, symbol_table
	move.w	d3,d5                           ; the count kept
input_number_restart:
	moveq	#0,d2                           ; the number
input_number_key:
	bsr.w	get_key                         ; a key
	cmp.w	#$d,d0                          ; Return?
	beq.s	input_number_return             ; yes
	cmp.w	#$8,d0                          ; backspace?
	beq.s	input_number_backspace          ; yes
	move.w	d0,d1                           ; kept, to print
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
	dbra	d3,input_number_key             ; room for more?
	move.w	d5,d1                           ; no: all rubbed out
	mulu.w	#$3,d1                          ; 3 bytes each
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
; crunch_all_menu: 1 crunch every file of the folder in data mode, 2 every file in program mode (the mask is
; "*.*" for both), 3 choose the folder, 4 back.  Each file is saved over itself.  At the end "OK nn FILE(S)
; PACKED IN nn FILE(S) LOADED" and the bell until a key.
;------------------------------------------------------------------------------
crunch_all_menu:	; from: main_menu, ring_until_key, symbol_table
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	lea	crunch_all_menu_text(pc),a0     ; "1: CRUNCH *.* IN DATA MODE" ...
	bsr.w	print
	clr.w	loaded_count                    ; none loaded (the packed count is never cleared)
crunch_all_menu_key:
	bsr.w	get_key                         ; a key
	cmp.w	#$31,d0                         ; '1'?
	beq.s	crunch_all_data                 ; data mode
	cmp.w	#$32,d0                         ; '2'?
	beq.s	crunch_all_programs             ; program mode
	cmp.w	#$33,d0                         ; '3'?
	beq.s	crunch_all_choose_folder        ; choose the folder
	cmp.w	#$34,d0                         ; '4'?
	bne.s	crunch_all_menu_key             ; no: another key
	bra.w	main_menu                       ; the main menu
crunch_all_choose_folder:
	lea	any_mask(pc),a3                 ; "*.*"
	bsr.w	choose_file                     ; fsel_input: the folder set
	bra.s	crunch_all_menu                 ; the menu again
crunch_all_data:
	st	data_mode                       ; data mode
	bra.s	crunch_all
crunch_all_programs:
	sf	data_mode                       ; program mode
crunch_all:
	bsr.w	find_first                      ; the first file
	beq.s	crunch_all_batch                ; found?
	lea	disk_empty_text(pc),a0          ; "HEY! DISK EMPTY!"
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; a key
	bra.s	crunch_all_menu                 ; the menu again
crunch_all_batch:
	st	batch                           ; batch
crunch_all_next:
	lea	loaded_count+1(pc),a0           ; one more loaded
	bsr.w	bcd_count_up
	lea	packed_count+1(pc),a0           ; one more packed
	bsr.w	bcd_count_up
	bsr.w	crunch_file                     ; loaded and crunched
	tst.b	interrupted                     ; interrupted (Esc stops this file only)?
	bne.s	crunch_all_not_packed           ; yes
	tst.b	not_crunched                    ; not crunched?
	beq.s	crunch_all_find                 ; no: packed
crunch_all_not_packed:
	lea	packed_count+1(pc),a0           ; one packed less, in BCD
	moveq	#1,d1
	move.b	(a0),d0
	sbcd	d1,d0
	move.b	d0,(a0)
	move.b	-(a0),d0                        ; the high byte
	moveq	#0,d1
	sbcd	d1,d0
	move.b	d0,(a0)
crunch_all_find:
	bsr.s	find_next                       ; the next file
	beq.s	crunch_all_next                 ; found: crunched
	lea	batch_ok_text(pc),a0            ; "OK "
	bsr.w	print
	moveq	#0,d1                           ; the packed count
	move.b	packed_count(pc),d1
	bsr.w	print_decimal                   ; its high byte, through to_bcd as if binary
	move.b	packed_count+1(pc),d1           ; its low byte
	bsr.w	print_decimal                   ; the same
	lea	files_packed_text(pc),a0        ; " FILE(S) PACKED"
	bsr.w	print
	lea	batch_in_text(pc),a0            ; "IN "
	bsr.w	print
	move.b	loaded_count(pc),d1             ; the loaded count's high byte
	bsr.w	print_decimal                   ; the same way
	move.b	loaded_count+1(pc),d1           ; its low byte
	bsr.w	print_decimal
	lea	files_loaded_text(pc),a0        ; " FILE(S) LOADED"
	bsr.w	print

;------------------------------------------------------------------------------
; ring_until_key: rings the bell again and again until a key is pressed, then the crunch all menu.
;------------------------------------------------------------------------------
ring_until_key:
	lea	bell_text(pc),a0                ; the bell
	bsr.w	print                           ; rung
	move.w	#$ff,-(sp)                      ; $ff: a key if any
	move.w	#$6,-(sp)
	trap	#1                              ; Crawio
	addq.w	#4,sp
	tst.w	d0                              ; any?
	beq.s	ring_until_key                  ; no: again
	bra.w	crunch_all_menu                 ; the menu

;------------------------------------------------------------------------------
; bcd_count_up: one more in the BCD word whose low byte is at a0.
;------------------------------------------------------------------------------
bcd_count_up:	; from: crunch_all_menu
	moveq	#1,d1                           ; 1
	move.b	(a0),d0                         ; the low byte
	abcd	d1,d0                           ; + 1
	move.b	d0,(a0)
	move.b	-(a0),d0                        ; the high byte
	moveq	#0,d1                           ; 0
	abcd	d1,d0                           ; + the carry
	move.b	d0,(a0)
	rts

;------------------------------------------------------------------------------
; find_next: Fsnext, then as find_first.
;------------------------------------------------------------------------------
find_next:	; from: crunch_all_menu, symbol_table
	moveq	#79,d0                          ; Fsnext
	bra.s	find_file

;------------------------------------------------------------------------------
; find_first: Fsfirst on "*.*" in the current folder, normal files, with the DTA set; the name found is
; copied as the name chosen.  d0 is GEMDOS's answer, with the flags set by it.
;------------------------------------------------------------------------------
find_first:	; from: crunch_all_menu, symbol_table
	moveq	#78,d0                          ; Fsfirst
find_file:	; from: find_next, symbol_table
	clr.w	-(sp)                           ; normal files
	pea	any_mask(pc)                    ; the mask
	move.w	d0,-(sp)                        ; Fsfirst/Fsnext
	bsr.w	set_dta                         ; the DTA
	trap	#1                              ; GEMDOS
	addq.w	#8,sp
	bsr.s	copy_found_name                 ; its name kept
	tst.w	d0                              ; found?
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

;------------------------------------------------------------------------------
; crunch_file: the author's LOAD_AND_PACK.  Loads the file named, checks the pictures' offsets, puts the
; offsets and their count after the file (in data mode the count always, 0 too), crunches it, works out the stub's text
;   length and saves it (asking first,
; unless batch).  A program is saved as the stub (the picture stub with pictures set), the packed data
; and a zero long (no relocation); a data file as the packed data with its 'ATOM' header.  load_file's
; io_error is not checked: a file that cannot be read is crunched as whatever the buffer holds.
;------------------------------------------------------------------------------
crunch_file:	; from: main_menu, crunch_all_menu, symbol_table
	bsr.w	make_name                       ; the full name
	bsr.w	load_file                       ; loaded
	lea	title_text(pc),a0               ; the title
	bsr.w	print
	move.l	file_length(pc),d0              ; the length
	lsr.w	#1,d0                           ; odd?
	bcc.s	crunch_file_length_even         ; no
	add.w	d0,d0                           ; back
	addq.l	#2,d0                           ; made even
	bra.s	crunch_file_check_pictures
crunch_file_length_even:
	add.w	d0,d0                           ; back
crunch_file_check_pictures:
	move.l	d0,-(sp)                        ; kept
	moveq	#0,d1
	move.b	picture_count(pc),d1            ; pictures?
	lea	picture_offsets(pc),a0          ; their offsets
	bne.s	crunch_file_pictures            ; yes
	sf	pictures_on                     ; no
	bra.s	crunch_file_offsets             ; to the offsets
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
	sub.b	picture_count(pc),d1            ; the picture, counted from the first offset typed
	neg.w	d1                              ; (the prompts count from the other end)
	ext.w	d1
	move.w	d1,-(sp)                        ; kept
	lea	picture_parameters_text(pc),a0  ; "PICTURE PARAMETERS N."
	bsr.w	print                           ; printed
	move.w	(sp)+,d1
	bsr.w	print_decimal                   ; two digits
	lea	bad_offset_text(pc),a0          ; " BAD", "OFFSET + 7D00 > FILE LENGHT"
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; a key (in batch too)
	addq.w	#4,sp                           ; the length dropped
	st	interrupted                     ; stopped
	bra.w	crunch_file_done                ; done
crunch_file_offsets:
	move.l	(sp)+,d0                        ; the length
	moveq	#0,d7                           ; no pictures
	tst.b	data_mode                       ; data mode?
	bne.s	crunch_file_put_offsets         ; yes: the count always written
	move.b	picture_count(pc),d7            ; pictures?
	beq.s	crunch_file_go                  ; no: nothing after the file
crunch_file_put_offsets:
	move.b	picture_count(pc),d7            ; the number of pictures
	lea	bss_end+$13144,a0               ; the load buffer
	movea.l	a0,a2                           ; kept
	adda.l	d0,a0                           ; the file's end
	lea	picture_offsets(pc),a1          ; the offsets
	move.w	d7,d6                           ; the count
	subq.w	#1,d6                           ; for dbra
	bmi.s	crunch_file_put_count           ; none
crunch_file_copy_offset:
	move.l	(a1)+,(a0)+                     ; after the file, for the depacker
	dbra	d6,crunch_file_copy_offset
crunch_file_put_count:
	move.w	d7,(a0)+                        ; then the number of pictures
	move.l	a0,d0                           ; the end
	sub.l	a2,d0                           ; the length with the offsets
crunch_file_go:
	move.l	d0,crunch_length                ; the length crunched
	move.l	d0,crunch_left                  ; all left
	lea	crunching_text(pc),a0           ; "CRUNCHING  : "
	bsr.w	print                           ; printed
	lea	full_name(pc),a0                ; the name
	bsr.w	print                           ; printed
	lea	new_lines_text(pc),a0           ; two new lines
	bsr.w	print                           ; printed
	sf	not_crunched                    ; crunched (so far)
	lea	read_start_time(pc),a0          ; the clock now
	bsr.w	supervisor_call
	bsr.w	crunch_pictures                 ; the pictures turned, then packed
	tst.b	interrupted                     ; interrupted?
	bne.w	crunch_file_done                ; yes
	lea	read_end_time(pc),a0            ; the clock now
	bsr.w	supervisor_call
	bsr.w	print_time                      ; "CRUNCHING TIME:"
	move.l	crunch_length(pc),d0            ; the length crunched
	move.l	(a5),d1                         ; the packed length
	lsr.w	#1,d1                           ; odd?
	bcc.s	crunch_file_even                ; no
	add.w	d1,d1                           ; back
	addq.l	#2,d1                           ; made even
	bra.s	crunch_file_lengths
crunch_file_even:
	add.w	d1,d1                           ; back
crunch_file_lengths:
	movea.l	d1,a0
	addq.w	#8,a0                           ; + the two lengths
	tst.b	data_mode                       ; data mode?
	bne.s	crunch_file_data_header         ; yes
	tst.b	pictures_on                     ; pictures?
	beq.s	crunch_file_normal_stub         ; no
	lea	$46(a0),a0                      ; + the picture stub's $46 more
crunch_file_normal_stub:
	lea	$23c(a0),a0                     ; + the stub's $238 and the zero long
	bra.s	crunch_file_gain
crunch_file_data_header:
	addq.w	#4,a0                           ; + 'ATOM'
crunch_file_gain:
	cmp.l	a0,d0                           ; any gain?
	ble.w	crunch_file_no_gain             ; no: "SORRY CANNOT CRUNCH.."
	move.l	a0,save_length                  ; the length saved
	lea	save_length_text(pc),a0         ; "SAVE LENGHT: "
	bsr.w	print                           ; printed
	move.l	save_length(pc),d0              ; the length saved
	bsr.w	print_hex                       ; in hex
	tst.b	data_mode                       ; data mode?
	bne.s	crunch_file_data                ; yes
	movea.l	save_length(pc),a0              ; the length saved
	move.l	a0,d2                           ; to write
	lea	-$20(a0),a0                     ; less the header and the zero long: the stub's text length
	move.l	a0,picture_stub_text_length     ; into the picture stub
	move.l	a0,stub_text_length             ; and the normal stub
	lea	bss_end+$ef0c,a1                ; the normal stub's place, before the packed data
	lea	stub(pc),a0                     ; the normal stub
	move.w	#$11b,d0                        ; $238 bytes
	tst.b	pictures_on                     ; pictures?
	beq.s	crunch_file_copy_stub           ; no
	lea	bss_end+$eec6,a1                ; the picture stub's place
	lea	picture_stub(pc),a0             ; the picture stub
	addi.w	#$23,d0                         ; $27e bytes
crunch_file_copy_stub:
	movea.l	a1,a2                           ; the file's start
crunch_file_copy_stub_word:
	move.w	(a0)+,(a1)+                     ; copied
	dbra	d0,crunch_file_copy_stub_word
	bra.s	crunch_file_save                ; to the save
crunch_file_data:
	lea	bss_end+$f144,a2                ; the file's start
	move.l	save_length(pc),d2              ; its length

;------------------------------------------------------------------------------
; crunch_file_save: the author's SAVE_FILE.  "SAVE PACK FILE? (Y/N)" (not in batch), the file selector, then
; written: d2 bytes from a2.
;------------------------------------------------------------------------------
crunch_file_save:	; from: crunch_file, symbol_table
	lea	new_lines_text(pc),a0           ; two new lines
	bsr.w	print                           ; printed
	tst.b	batch                           ; batch?
	bne.s	crunch_file_choose              ; yes: saved
	lea	save_packed_text(pc),a0         ; "SAVE PACK FILE? (Y/N)"
	bsr.w	print                           ; printed
crunch_file_save_answer:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.s	crunch_file_choose              ; yes
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	crunch_file_save_answer         ; no: another key
	bra.w	crunch_file_done                ; not saved
crunch_file_choose:
	tst.b	batch                           ; batch?
	bne.s	crunch_file_write               ; yes: over the file loaded
	movea.l	file_mask(pc),a3                ; the mask
	bsr.w	choose_file                     ; fsel_input
	tst.w	d0                              ; OK?
	bne.s	crunch_file_done                ; no
	lea	title_text(pc),a0               ; the title
	bsr.w	print                           ; printed
crunch_file_write:
	bsr.w	make_name                       ; the full name
	bsr.w	write_file                      ; written
	tst.b	io_error                        ; an error?
	bne.s	crunch_file_write_error         ; yes
	tst.b	batch                           ; batch?
	bne.s	crunch_file_done                ; yes: done
	lea	file_text(pc),a0                ; "FILE: "
	bsr.w	print                           ; printed
	lea	full_name(pc),a0                ; the name
	bsr.w	print                           ; printed
	lea	saved_text(pc),a0               ; " SAVED"
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; a key
	bra.s	crunch_file_done                ; done
crunch_file_write_error:	; from: symbol_table
	lea	write_error_text(pc),a0         ; "WRITE ERROR! RETRY (Y/N)"
	bsr.w	print                           ; printed
crunch_file_retry_key:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.w	crunch_file_save                ; yes: asked again
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	crunch_file_retry_key           ; no: another key
	bra.s	crunch_file_done                ; given up
crunch_file_no_gain:	; from: crunch_file, symbol_table
	st	not_crunched                    ; not crunched
	lea	cannot_crunch_text(pc),a0       ; "SORRY CANNOT CRUNCH.."
	bsr.w	print                           ; printed
	tst.b	batch                           ; batch?
	bne.s	crunch_file_done                ; yes
	bsr.w	get_key                         ; no: a key
crunch_file_done:	; from: crunch_file, symbol_table
	rts

;------------------------------------------------------------------------------
; set_dta: Fsetdta to the program's DTA.
;------------------------------------------------------------------------------
set_dta:	; from: find_first, symbol_table
	pea	dta(pc)                         ; the DTA
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.w	#6,sp
	rts

;------------------------------------------------------------------------------
; crunch_pictures: the author's ATOMIK.  Each picture turned from words of planes to 4-bit pixels
; (encode_picture), numbered from the last, then the file packed.
;------------------------------------------------------------------------------
crunch_pictures:	; from: crunch_file, symbol_table
	moveq	#0,d7
	move.b	picture_count(pc),d7            ; pictures?
	beq.s	crunch_pictures_pack            ; no
	lea	picture_offsets(pc),a2          ; their offsets
crunch_pictures_next:
	dbra	d7,crunch_pictures_one          ; one more?
	bra.s	crunch_pictures_pack            ; no
crunch_pictures_one:
	lea	encoding_picture_text(pc),a0    ; "ENCODING PICTURE N."
	bsr.w	print                           ; printed
	move.w	d7,d1                           ; its number
	addq.w	#1,d1
	bsr.w	print_decimal                   ; two digits
	lea	clear_to_end_text(pc),a0        ; the rest of the line cleared
	bsr.w	print                           ; printed
	lea	bss_end+$13144,a0               ; the load buffer
	adda.l	(a2)+,a0                        ; + its offset
	bsr.w	encode_picture                  ; turned
	bra.s	crunch_pictures_next
crunch_pictures_pack:
	bsr.s	pack                            ; packed
	rts

;------------------------------------------------------------------------------
; pack: the author's ALGORYTHM.  Crunches the file (with the pictures' offsets after it) from the load
; buffer into the packed data's place (bss_end+$f144, $4000 below the load buffer).  Data mode puts 'ATOM'
; first.  Then the unpacked length, the packed length and the codes, written forward as they are found and
; read backward by the depacker, bytes and bit bytes mixed (d7 holds the bits, filled from the top, with a
; bit 7 marker to know when it is full).  After the last literal count: the last bit byte and 8 zero bytes.
;------------------------------------------------------------------------------
pack:	; from: crunch_pictures, symbol_table
	lea	bss_end+$13144,a0               ; the load buffer
	move.l	a0,next_report                  ; the next report
	lea	bss_end+$f144,a5                ; the packed data's place
	tst.b	data_mode                       ; data mode?
	beq.s	pack_even                       ; no
	move.b	#$41,(a5)+                      ; 'ATOM'
	move.b	#$54,(a5)+
	move.b	#$4f,(a5)+
	move.b	#$4d,(a5)+
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
	move.l	a6,d0                           ; the end
	sub.l	a0,d0                           ; less the start: the length
	move.l	d0,(a5)+                        ; the unpacked length
	addq.w	#4,a5                           ; the packed length's place
	pea	(a5)                            ; the data's start kept
	moveq	#0,d3                           ; no literals yet
	moveq	#-128,d7                        ; the bit byte: empty, with its marker
	clr.b	interrupted                     ; not interrupted
	swap	d7                              ; the bit byte kept in the high word
	move.w	#$41ec,next_window              ; next_window: the window not the last
	movea.l	a0,a4                           ; where the search is
	move.l	a0,next_report                  ; a report at once
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	bsr.w	print_crunch_left               ; "CRUNCH LEFT:", "CRUNCH DONE:"
	movem.l	(sp)+,d0-d7/a0-a6
	bsr.w	analyse_window                  ; the first window analysed
	moveq	#0,d6
	bsr.w	match                           ; matched and written
	tst.b	interrupted                     ; interrupted?
	beq.s	pack_end                        ; no
	addq.w	#4,sp                           ; the data's start dropped
	bra.s	pack_done
pack_end:
	swap	d7                              ; the bit byte back
	bsr.w	put_literal_count               ; the last literals' count
	move.b	d7,(a5)+                        ; the last bit byte
	moveq	#0,d0
	movep.l	d0,0(a5)                        ; 8 bytes cleared after it
	movep.l	d0,1(a5)
	move.l	a5,d0                           ; the end
	movea.l	(sp)+,a5                        ; the data's start
	sub.l	a5,d0                           ; the length
	move.l	d0,-(a5)                        ; the packed length
pack_done:
	rts

;------------------------------------------------------------------------------
; match_report: the author's LOOK_LENGHT.  If the output has caught up with the input, the packed length is
; made the file's (no gain) and the search ends.  Otherwise "CRUNCH LEFT:", and Esc asks "INTERUPTION? (Y/N)";
; then back into the search.
;------------------------------------------------------------------------------
match_report:	; from: match, symbol_table
	movem.l	d1-d3/a0-a4,-(sp)               ; saved
	cmpa.l	a4,a5                           ; the output past the input?
	blt.s	match_report_left               ; no
	lea	bss_end+$f144,a5                ; yes: the packed length is the file's
	adda.l	crunch_length(pc),a5
	bra.s	match_report_end                ; the search ends
match_report_left:
	bsr.w	print_crunch_left               ; "CRUNCH LEFT:", "CRUNCH DONE:"
	move.w	#$ff,-(sp)                      ; $ff: a key if any
	move.w	#$6,-(sp)
	trap	#1                              ; Crawio
	addq.w	#4,sp
	cmp.w	#$1b,d0                         ; Esc?
	bne.s	match_report_carry_on           ; no
	lea	interruption_text(pc),a0        ; "INTERUPTION? (Y/N)"
	bsr.w	print                           ; printed
match_report_answer:
	bsr.w	get_key                         ; a key
	andi.w	#$df,d0                         ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.s	match_report_stop               ; yes
	cmp.w	#$4e,d0                         ; 'N'?
	bne.s	match_report_answer             ; no: another key
	bra.s	match_report_carry_on           ; carry on
match_report_stop:
	st	interrupted                     ; interrupted
match_report_end:
	movem.l	(sp)+,d1-d3/a0-a4
	rts                                     ; out of match, back to pack
match_report_carry_on:
	movem.l	(sp)+,d1-d3/a0-a4
	move.b	-$1(a4),d0                      ; the byte again
	bra.s	match_next                      ; back into the search

;------------------------------------------------------------------------------
; match: the author's PACKING.  The search, from a4 to the window's end a6.  For each byte the later places
; of the same byte (position_lists) are tried within $3f60 bytes: the longest match wins (2 bytes only within
; $3e2).  Without a match, the same byte in the next 8 or one of the four common bytes gives a one-byte code;
; otherwise the byte is a literal.  Each code is written at once by put_match.  When the reach passes the
; window's end the next window is analysed from this byte (next_window, the author's CHANGE_CODE: its first
; word is $41ec, this lea, until analyse_window reaches the file's end and makes it $6008, bra.s
; match_last_window).
;------------------------------------------------------------------------------
match:	; from: pack, symbol_table
	moveq	#0,d0                           ; none
	lea	match_offset(pc),a3             ; the best offset
	move.l	d0,(a3)+                        ; and length none
	move.w	d0,(a3)                         ; not found, no one-byte code
	lea	position_lists(pc),a3           ; the lists
	lea	byte_counts(pc),a2              ; the counts
	move.b	(a4)+,d0                        ; the byte
	cmpa.l	next_report(pc),a4              ; time for a report?
	bge.s	match_report                    ; yes
match_next:	; from: match_report, symbol_table
	move.b	(a4),d1                         ; the next byte
match_reach:	; from: symbol_table
	lea	$3f60(a4),a1                    ; the furthest a match can reach
	cmpa.l	a1,a6                           ; inside the window?
	bgt.s	match_try                       ; yes
next_window:	; from: pack, analyse_window, symbol_table
	lea	-$1(a4),a0                      ; the next window from this byte (patched to bra.s match_last_window in
                                                ;   the last)
	bsr.w	analyse_window                  ; analysed
	bra.s	match_reach                     ; the reach again
match_last_window:
	movea.l	a6,a1                           ; the reach is the window's end
match_try:	; from: symbol_table
	move.w	d0,d2                           ; the byte
	add.w	d2,d2
	adda.w	d2,a2                           ; its count
	subq.w	#1,(a2)                         ; one less (this one): any more?
	beq.s	match_try_done                  ; no
	move.w	(a2),d7                         ; the places left
	subq.w	#1,d7
	lea	position_index(pc),a2           ; the indexes
	adda.w	d2,a2                           ; its index
	addq.w	#2,(a2)                         ; past this place
	move.w	(a2),d6
	add.w	d2,d2                           ; *4
	movea.l	0(a3,d2.w),a2                   ; its list
	adda.l	d6,a2                           ; the next place
match_try_place:
	movea.l	a0,a3                           ; the place
	adda.w	(a2)+,a3
	cmpa.l	a3,a1                           ; out of reach?
	ble.s	match_try_done                  ; yes: done
	cmp.b	(a3)+,d1                        ; the second byte the same?
	dbeq	d7,match_try_place              ; no: the next place
	bne.s	match_try_done                  ; none
	addq.w	#1,a4                           ; past the second byte
	cmpa.l	a3,a1                           ; the match inside the reach?
	bge.s	match_compare                   ; yes: how long
	subq.w	#1,a4
	tst.w	match_length                    ; (never: the best length is not negative)
	bge.s	match_try_done
	move.l	a3,d2
	sub.l	a4,d2                           ; the offset
	cmp.w	#$3e0,d2                        ; too far?
	bgt.s	match_try_done
	subq.w	#1,d2                           ; -1
	move.w	d2,match_offset                 ; the offset
	addq.w	#2,match_length                 ; 2
	st	match_flag                      ; found
match_try_done:
	bra.w	match_decide
match_compare:
	move.l	a4,d2                           ; the start
match_compare_byte:
	cmpm.b	(a4)+,(a3)+                     ; the same?
	bne.s	match_compare_differ            ; no
	cmpa.l	a3,a1                           ; out of reach?
	bge.s	match_compare_byte              ; no: the next
match_compare_end:
	sub.l	a4,d2                           ; at the reach
	neg.w	d2
	addq.w	#1,d2                           ; the length, to the reach
	suba.w	d2,a4                           ; back to the start
	cmp.w	match_length(pc),d2             ; longer than the best?
	ble.w	match_decide                    ; no
	move.w	d2,match_length                 ; the best length
	move.l	a3,d5                           ; the distance
	sub.l	a4,d5
	cmp.w	#$2,d2                          ; 2 bytes?
	bne.s	match_compare_end_found         ; no
	cmp.w	#$3e2,d5                        ; within $3e2?
	bgt.s	match_decide                    ; no
match_compare_end_found:
	st	match_flag                      ; found
	sub.w	d2,d5                           ; -1: the offset
	subq.w	#1,d5
	move.w	d5,match_offset                 ; the best offset
	bra.s	match_decide                    ; no more places tried
match_compare_differ:
	sub.l	a4,d2
	neg.w	d2
	addq.w	#1,d2                           ; the length
	suba.w	d2,a4                           ; back to the start
	cmp.w	#$3f,d2                         ; longer than 63?
	ble.s	match_compare_best              ; no
match_skip_place:
	moveq	#0,d4                           ; places inside this match skipped
	move.w	(a2)+,d4
	add.l	a0,d4
	cmpa.l	d4,a3                           ; past it?
	ble.s	match_skip_done                 ; yes
	dbra	d7,match_skip_place             ; the next
	bra.s	match_decide                    ; none left
match_skip_done:
	subq.w	#2,a2                           ; back to it
match_compare_best:
	cmp.w	match_length(pc),d2             ; longer than the best?
	ble.s	match_try_next                  ; no
	move.w	d2,match_length                 ; the best length
	move.l	a3,d5
	sub.l	a4,d5                           ; the distance
	cmp.w	#$2,d2                          ; 2 bytes?
	bgt.s	match_better                    ; no
	cmp.w	#$3e2,d5                        ; within $3e2?
	bgt.s	match_try_next                  ; no
match_better:
	st	match_flag                      ; found
	sub.w	d2,d5
	subq.w	#1,d5                           ; -1: the offset
	st	match_flag                      ; (again)
	move.w	d5,match_offset                 ; the best offset
match_try_next:
	dbra	d7,match_try_place              ; the next place
match_decide:
	move.w	match_flag(pc),d2               ; found?
	bne.s	match_found                     ; yes
	movea.l	a4,a2                           ; no: the same byte in the next 8?
	lea	8(a4),a1                        ; 8 on
	cmpa.l	input_end(pc),a1                ; past the file's end?
	ble.s	match_near_find                 ; no
	movea.l	input_end(pc),a1                ; yes: to the end
match_near_find:
	cmp.b	(a2)+,d0                        ; the same?
	beq.s	match_near                      ; yes
	cmpa.l	a2,a1                           ; the end?
	bgt.s	match_near_find                 ; no
	bra.s	match_common_byte               ; none
match_near:
	move.l	a2,d1                           ; the distance, 1-8
	sub.l	a4,d1
	lea	match_length(pc),a2             ; no match
	clr.w	(a2)+
	move.w	#$2,(a2)+                       ; kind 2: a byte near
	move.w	d1,(a2)                         ; its distance
	bra.s	match_found                     ; written
match_common_byte:
	lea	common_bytes(pc),a2             ; the four common bytes
	moveq	#3,d1                           ; 4
match_common_find:
	cmp.b	(a2)+,d0                        ; this one?
	dbeq	d1,match_common_find
	bne.s	match_literal                   ; none
	lea	match_length(pc),a2             ; no match
	clr.w	(a2)+
	move.w	#$1,(a2)+                       ; kind 1: a common byte
	move.w	d1,(a2)                         ; its index, 3-0
	bra.s	match_found                     ; written
match_literal:
	move.b	d0,(a5)+                        ; a literal, written at once
	addq.l	#1,d3                           ; counted
	bra.s	match_window_done
match_found:
	swap	d7                              ; the bit byte back
	bsr.s	put_match                       ; the code written
	swap	d7                              ; the bit byte kept again
match_window_done:
	cmpa.l	a4,a6                           ; the window done?
	bgt.w	match                           ; no: the next byte
	blt.s	match_end                       ; past it
	move.b	(a4)+,(a5)+                     ; its last byte a literal
	addq.l	#1,d3                           ; counted
match_end:
	rts

;------------------------------------------------------------------------------
; offset_bit_counts: the bits of each offset class for a match of 3 or more: the offset's bits and the
; 3-bit class.
;------------------------------------------------------------------------------
offset_bit_counts:	; from: put_offset, symbol_table
	dc.w	$0008,$0009,$000b,$000c,$000d,$000e,$000f,$0010

;------------------------------------------------------------------------------
; pair_offset_bit_counts: the same for a 2-byte match (classes 0-4).
;------------------------------------------------------------------------------
pair_offset_bit_counts:	; from: put_offset, symbol_table
	dc.w	$0008,$0009,$000a,$000b,$000c

;------------------------------------------------------------------------------
; put_match: the author's CALCUL.  The count of the literals before, then the code: a one-byte code (6 bits:
; a 0, class 5 or 6 and the near byte's distance - 1, or class 7 and the common byte's index) or a match's
; offset then its length.  The bytes inside the match are taken out of the counts and lists.
;------------------------------------------------------------------------------
put_match:	; from: match, symbol_table
	bsr.w	put_literal_count               ; the literals' count
	move.w	match_length(pc),d0             ; a match?
	bne.s	put_match_offset                ; yes
	move.w	byte_value(pc),d0               ; the one-byte code's value
	cmpi.b	#$2,byte_kind                   ; a byte near?
	beq.s	put_match_near                  ; yes
	addi.w	#$1c,d0                         ; a common byte: class 7
	move.w	d0,d1
	bra.s	put_match_byte_code             ; written
put_match_near:
	subq.w	#1,d0                           ; the distance - 1, 0-7
	moveq	#1,d1                           ; 5
put_match_near_class:
	subq.w	#4,d0                           ; up to 4?
	dble	d1,put_match_near_class         ; no: 6
	neg.w	d1
	addq.w	#6,d1                           ; 5 or 6
	add.w	d1,d1                           ; *4
	add.w	d1,d1
	add.w	d0,d1                           ; + the rest
	addq.w	#4,d1                           ; 20 + the distance - 1: class 5 or 6 and the index
put_match_byte_code:
	moveq	#5,d3                           ; 6 bits
	bra.w	put_bits
put_match_offset:
	subq.w	#1,d0                           ; the length - 1
	move.w	match_offset(pc),d1             ; the offset
	bsr.s	put_offset                      ; written
	movea.l	a4,a2                           ; the second byte
	adda.w	d0,a4                           ; past the match
	move.w	d0,d3                           ; its bytes
put_match_skip:
	dbra	d3,put_match_skip_next          ; more?
	bra.s	put_match_length                ; no
put_match_skip_next:
	lea	byte_counts(pc),a3              ; the counts
	move.b	(a2)+,d1                        ; the byte
	moveq	#0,d2
	move.b	d1,d2
	add.w	d2,d2
	adda.w	d2,a3
	subq.w	#1,(a3)                         ; one less
	lea	position_index(pc),a3           ; the indexes
	adda.w	d2,a3
	addq.w	#2,(a3)                         ; its index past it
	bra.s	put_match_skip                  ; the next
put_match_length:
	subq.w	#7,d0                           ; up to 8?
	bgt.s	put_match_length_four           ; no
	addq.w	#6,d0                           ; the length - 2
	move.w	d0,d3                           ; a 0 and that many 1s
	moveq	#-2,d1
	bra.w	put_bits                        ; written
put_match_length_four:
	subi.w	#$f,d0                          ; up to 23?
	bgt.s	put_match_length_eight          ; no
	addi.w	#$7ff,d0                        ; 7 1s and the length - 8 in 4 bits
	move.w	d0,d1
	moveq	#10,d3                          ; 11 bits
	bra.s	put_bits
put_match_length_eight:
	subi.w	#$ff,d0                         ; up to 278?
	bgt.s	put_match_length_long           ; no
	addi.w	#$f0ff,d0                       ; the length - 23 in 8 bits, then 4 0s and 4 1s
	move.w	d0,d1
	moveq	#15,d3                          ; 16 bits
	bsr.s	put_bits
	moveq	#7,d1                           ; 3 more 1s
	moveq	#2,d3
	bra.s	put_bits
put_match_length_long:
	move.w	d0,d1                           ; the length - 278
	moveq	#13,d3                          ; 14 bits
	bsr.s	put_bits
	move.w	#$f000,d1                       ; then 12 0s and 4 1s
	moveq	#15,d3                          ; 16 bits
	bsr.s	put_bits
	moveq	#7,d1                           ; 3 more 1s
	moveq	#2,d3
	bra.s	put_bits

;------------------------------------------------------------------------------
; put_offset: the offset d1 in its class, with the class's prefix and bit count: offset_steps for a match of
; 3 or more (d0 the length - 1), pair_offset_steps for a 2-byte one.
;------------------------------------------------------------------------------
put_offset:	; from: put_match
	cmp.w	#$1,d0                          ; 2 bytes?
	bne.s	put_offset_steps                ; no
	lea	pair_offset_steps(pc),a2        ; the 2-byte steps
	bra.s	put_offset_find
put_offset_steps:
	lea	offset_steps(pc),a2             ; the steps
put_offset_find:
	move.l	a2,d3                           ; the table's start
	swap	d7                              ; the bit byte out of the way
put_offset_class:
	cmp.w	(a2)+,d1                        ; in this class?
	blt.s	put_offset_bits                 ; yes
	sub.w	-$2(a2),d1                      ; no: less the step
	bra.s	put_offset_class
put_offset_bits:
	sub.l	a2,d3
	neg.w	d3                              ; the class * 2 (2 up)
	cmp.w	#$1,d0                          ; 2 bytes?
	bne.s	put_offset_long                 ; no
	move.w	pair_offset_prefixes-2(pc,d3.w),d7 ; its prefix
	lea	pair_offset_bit_counts(pc),a2   ; the bit counts
	bra.s	put_offset_count
put_offset_long:
	move.w	offset_prefixes-2(pc,d3.w),d7   ; its prefix
	lea	offset_bit_counts(pc),a2        ; the bit counts
put_offset_count:
	move.w	-$2(a2,d3.w),d3                 ; its bit count
	or.w	d7,d1                           ; the prefix in
	subq.w	#1,d3                           ; for dbcs
	swap	d7                              ; the bit byte back

;------------------------------------------------------------------------------
; put_bits: d3+1 bits of d1 (from bit 0) into the bit byte, written out each time it fills; d3 is cleared
; at the end, which starts the next literal count.
;------------------------------------------------------------------------------
put_bits:	; from: put_match
	lsr.w	#1,d1                           ; the next bit
	roxr.b	#1,d7                           ; in
	dbcs	d3,put_bits                     ; not full: the next
	bcc.s	put_bits_done                   ; all done
	move.b	d7,(a5)+                        ; full: written
	moveq	#-128,d7                        ; empty
	dbra	d3,put_bits                     ; the next
put_bits_done:
	moveq	#0,d3                           ; no literals yet
	rts

;------------------------------------------------------------------------------
; offset_prefixes: each class's 3-bit prefix, above the offset's bits (the author's CODE_T).
;------------------------------------------------------------------------------
offset_prefixes:	; from: symbol_table
	dc.w	$0000,$0040,$0200,$0600,$1000,$2800,$6000,$e000

;------------------------------------------------------------------------------
; pair_offset_prefixes: the same for a 2-byte match (CODE_T2); classes 5-7 are not used here: they are the
; one-byte codes, which put_match makes itself.
;------------------------------------------------------------------------------
pair_offset_prefixes:	; from: symbol_table
	dc.w	$0000,$0040,$0100,$0300,$0800,$0a00,$0c00,$0e00

;------------------------------------------------------------------------------
; put_literal_count: the author's CALCUL_MARK.  The count d3 of the literals before the code: 0-11 as that
; many 1s and a 0; 12-266 as 12 1s and the count - 11 in 8 bits; more as 12 1s, 8 0s and the count - 11 in
; 19 bits (3 then 16).
;------------------------------------------------------------------------------
put_literal_count:	; from: pack, put_match, symbol_table
	swap	d3                              ; the high word
	tst.w	d3                              ; 65536 or more?
	bne.s	put_literal_count_high          ; yes
	swap	d3                              ; back
	cmp.w	#$b,d3                          ; up to 11?
	bgt.s	put_literal_count_eight         ; no
	move.w	d3,d2                           ; that many bits
	moveq	#-2,d3                          ; 1s and a 0
	bra.s	put_count_bits                  ; written
put_literal_count_eight:
	subi.w	#$b,d3                          ; less 11
	cmp.w	#$ff,d3                         ; up to 255?
	bgt.s	put_literal_count_long          ; no
	addi.w	#$ff00,d3                       ; 8 bits, then 8 1s
	moveq	#15,d2                          ; 16 bits
	bsr.s	put_count_bits
	moveq	#15,d3                          ; 4 more 1s
	moveq	#3,d2                           ; 4 bits
	bra.s	put_count_bits
put_literal_count_high:
	swap	d3                              ; back
	subq.l	#8,d3                           ; less 11
	subq.l	#3,d3
put_literal_count_long:
	moveq	#15,d2                          ; the low 16 bits
	bsr.s	put_count_bits
	swap	d3                              ; the high word
	moveq	#2,d2                           ; its 3 bits
	bsr.s	put_count_bits
	moveq	#-1,d3                          ; 8 0s and 8 1s
	not.b	d3
	moveq	#15,d2                          ; 16 bits
	bsr.s	put_count_bits
	swap	d3                              ; $ffff
	moveq	#3,d2                           ; 4 more 1s

;------------------------------------------------------------------------------
; put_count_bits: d2+1 bits of d3 (from bit 0) into the bit byte, as put_bits.
;------------------------------------------------------------------------------
put_count_bits:	; from: put_literal_count
	lsr.w	#1,d3                           ; the next bit
	roxr.b	#1,d7                           ; in
	dbcs	d2,put_count_bits               ; not full: the next
	bcc.s	put_count_bits_done             ; all done
	move.b	d7,(a5)+                        ; full: written
	moveq	#-128,d7                        ; empty
	dbra	d2,put_count_bits               ; the next
put_count_bits_done:
	rts

;------------------------------------------------------------------------------
; encode_picture: the author's COD_GRAPHICS.  A low resolution picture (32000 bytes at a0) turned from four
; plane words to 4-bit pixels, four to a word, which pack better.  The picture stub turns them back.
;------------------------------------------------------------------------------
encode_picture:	; from: crunch_pictures, symbol_table
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
	move.w	d4,(a0)+                        ; out
	dbra	d6,encode_picture_word
	cmpa.l	a0,a1                           ; the end?
	bne.s	encode_picture_group            ; no
	rts

;------------------------------------------------------------------------------
; analyse_window: the author's MAKE_TABLE.  "ANALYSING", then the window from a0 counted by byte and listed:
; each byte's places (offset + 1 from a0, as words) in positions, by byte.  The window is $8000 bytes (the
; end is counted in), so the place of its last byte, $8000, is negative to the search's adda.w: a search
; whose next place is that one compares bytes $8000 back, outside the window.  At the file's end
; next_window is patched to stop the windows.
;------------------------------------------------------------------------------
analyse_window:	; from: pack, match, symbol_table
	movem.l	d0-d2/a0-a5,-(sp)               ; saved
	lea	analysing_text(pc),a0           ; "ANALYSING"
	bsr.w	print                           ; printed
	movea.l	$c(sp),a0                       ; the window's start (a0 as saved)
	lea	byte_counts(pc),a1              ; the counts
	moveq	#0,d0
	moveq	#127,d1                         ; and the indexes
analyse_window_clear:
	move.l	d0,(a1)+                        ; cleared
	move.l	d0,(a1)+
	dbra	d1,analyse_window_clear
	lea	$7fff(a0),a2                    ; $7fff bytes on, counted in
	cmpa.l	input_end(pc),a2                ; past the file's end?
	blt.s	analyse_window_count            ; no
	movea.l	input_end(pc),a2                ; yes: to the end
	subq.w	#1,a2                           ; its last byte
	move.w	#$6008,next_window              ; next_window: the last window
analyse_window_count:
	movea.l	a0,a1
	lea	byte_counts(pc),a3              ; the counts
analyse_window_count_byte:
	moveq	#0,d0
	move.b	(a1)+,d0                        ; the byte
	add.w	d0,d0
	addq.w	#1,0(a3,d0.w)                   ; counted
	cmpa.l	a1,a2                           ; the end?
	bge.s	analyse_window_count_byte       ; no
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
	movea.l	a4,a5                           ; its index
	adda.w	d0,a5
	move.w	(a5),d1                         ; as it is
	addq.w	#2,(a5)                         ; past it
	add.w	d0,d0
	movea.l	position_lists(pc,d0.w),a5      ; its list
	adda.l	d1,a5                           ; its word
	sub.l	a0,d2                           ; from the window's start
	move.w	d2,(a5)                         ; listed
	cmpa.l	a1,a2                           ; the end?
	bge.s	analyse_window_place            ; no
	movea.l	a2,a6                           ; the window's end
	lea	position_index(pc),a3           ; the indexes
	moveq	#127,d0                         ; 512 bytes
	moveq	#0,d1
analyse_window_clear_index:
	move.l	d1,(a3)+                        ; cleared
	dbra	d0,analyse_window_clear_index
	lea	clear_to_end_text(pc),a0        ; the line cleared
	bsr.w	print                           ; printed
	lea	up_two_lines_text(pc),a0        ; up two lines
	bsr.w	print                           ; printed
	movem.l	(sp)+,d0-d2/a0-a5
	rts

;------------------------------------------------------------------------------
; position_lists: the author's ADRESS_TABLE.  Each byte's list's start (256 longs into positions).
;------------------------------------------------------------------------------
position_lists:	; from: match, analyse_window, symbol_table
	dcb.b	1024,0

;------------------------------------------------------------------------------
; byte_counts: the author's HOW_TABLE.  Each byte's count in the window (256 words), less those passed.
;------------------------------------------------------------------------------
byte_counts:	; from: match, put_match, analyse_window, symbol_table
	dcb.b	512,0

;------------------------------------------------------------------------------
; position_index: the author's CONTER_TABLE.  Each byte's index in its list (256 words, in bytes).
;------------------------------------------------------------------------------
position_index:	; from: match, put_match, analyse_window, symbol_table
	dcb.b	512,0

;------------------------------------------------------------------------------
; picture_stub: the author's DECRUN_CODE, the stub put before a packed program when pictures are set
; ($27e bytes, to offset_steps).  The header's bra.s word is the stub's first instruction too: it jumps
; over the rest of the header.  crunch_file sets the text length (the stub, the packed data and its
; lengths) and copies the stub before the packed data.  The bss length stays 0: the depacker writes past
; the text into the free memory.
;------------------------------------------------------------------------------
picture_stub:	; from: crunch_file, symbol_table
	bra.s	picture_stub_text
picture_stub_text_length:	; from: crunch_file, symbol_table
	dc.l	$00000000
picture_stub_data_length:
	dc.l	$00000000
picture_stub_bss_length:
	dc.l	$00000000
picture_stub_symbol_length:
	dc.l	$00000000
picture_stub_reserved:
	dc.l	$00000000
picture_stub_flags:
	dc.l	$00000000
picture_stub_absolute:
	dc.w	$0000                           ; 0: relocation follows (the zero long: none)

;------------------------------------------------------------------------------
; picture_stub_text: the author's DECRUNCHER.  The top of the screen cleared, the title shown, the program
; depacked behind the stub, its pictures turned back, relocated and its basepage set, then moved down over
; the stub by a mover copied past it, which runs the program.
;------------------------------------------------------------------------------
picture_stub_text:	; from: picture_stub, symbol_table
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
	lea	picture_stub+$27e(pc),a0        ; the packed data, after the stub
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

;------------------------------------------------------------------------------
; picture_stub_mover: the author's COPY_CODE, run past the relocation table.
;------------------------------------------------------------------------------
picture_stub_mover:	; from: picture_stub_text, symbol_table
	movea.l	a3,a4                           ; the start
picture_stub_mover_copy:
	move.l	(a5)+,(a3)+                     ; the text and data moved down
	subq.l	#4,d6
	bcc.s	picture_stub_mover_copy
picture_stub_mover_clear:
	clr.l	(a2)+                           ; the mover cleared from its start: once this clr has cleared itself and
                                                ;   the bra, the prefetched bra still runs, 0 runs as ori.b #0,d0, and
                                                ;   the last clr wipes the jmp already fetched
	bra.s	picture_stub_mover_clear
	clr.l	(a2)+
	jmp	(a4)                            ; run the program

;------------------------------------------------------------------------------
; picture_stub_depack: the author's DEPACK.  The packed data at a0 (its packed length) depacked backward,
; to $7e past a0 plus the unpacked length (a fixed margin); then the pictures turned back.  a5 = the program.
;------------------------------------------------------------------------------
picture_stub_depack:	; from: picture_stub_text, symbol_table
	lea	$7e(a0,d0.l),a5                 ; the output's end
	pea	(a5)                            ; kept, for the pictures
	move.l	(a0)+,d0                        ; the packed length
	lea	0(a0,d0.l),a6                   ; its end
	move.b	-(a6),d7                        ; the last bit byte
	bra.w	picture_stub_depack_literals    ; its literals first
picture_stub_depack_common_byte:	; from: symbol_table
	lea	picture_stub_common_bytes(pc),a4 ; class 7: one of the four common bytes
	moveq	#1,d6                           ; 2 bits
	bsr.s	picture_stub_depack_get_bits    ; its index
	bra.s	picture_stub_depack_byte_put    ; put
picture_stub_depack_match:	; from: picture_stub_depack_get_bits, symbol_table
	moveq	#6,d6                           ; a code: its length, up to 7 bits
picture_stub_depack_unary:	; from: symbol_table
	add.b	d7,d7                           ; the next bit
	beq.s	picture_stub_depack_unary_refill ; empty: refilled
picture_stub_depack_unary_bit:
	dbcc	d6,picture_stub_depack_unary    ; a 0 ends it
	bcs.s	picture_stub_depack_length_four ; 7 1s: more
	moveq	#6,d5                           ; the 1s: 0-6
	sub.w	d6,d5
	bra.s	picture_stub_depack_length      ; the length - 2
picture_stub_depack_length_four:
	moveq	#3,d6                           ; 4 bits
	bsr.s	picture_stub_depack_get_bits
	beq.s	picture_stub_depack_length_eight ; 0?
	addq.w	#6,d5                           ; no: 7-21
	bra.s	picture_stub_depack_length
picture_stub_depack_length_eight:
	moveq	#7,d6                           ; 8 bits
	bsr.s	picture_stub_depack_get_bits
	beq.s	picture_stub_depack_length_long ; 0?
	addi.w	#$15,d5                         ; no: 22-276
	bra.s	picture_stub_depack_length
picture_stub_depack_unary_refill:
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	picture_stub_depack_unary_bit
picture_stub_depack_length_long:
	moveq	#13,d6                          ; 14 bits
	bsr.s	picture_stub_depack_get_bits
	addi.w	#$114,d5                        ; + 276
picture_stub_depack_length:
	move.w	d5,-(sp)                        ; kept
	bne.s	picture_stub_depack_offset_long ; 3 or more: the long offsets
	lea	picture_stub_pair_offset_bases(pc),a4 ; 0: a 2-byte match or a one-byte code
	moveq	#2,d6                           ; 3-bit class
	bsr.s	picture_stub_depack_get_bits
	cmp.w	#$5,d5                          ; 0-4?
	blt.s	picture_stub_depack_offset_class ; yes: a 2-byte match
	addq.w	#2,sp                           ; no: a one-byte code
	subq.w	#6,d5                           ; 7?
	bgt.s	picture_stub_depack_common_byte ; yes: a common byte
	movea.l	a5,a4                           ; 5: one of the next 4 bytes
	blt.s	picture_stub_depack_near        ; yes
	addq.w	#4,a4                           ; 6: one of the 4 after them
picture_stub_depack_near:
	moveq	#1,d6                           ; 2 bits: which
	bsr.s	picture_stub_depack_get_bits
picture_stub_depack_byte_put:	; from: symbol_table
	move.b	0(a4,d5.w),-(a5)                ; the byte put
	bra.s	picture_stub_depack_literals    ; then literals

;------------------------------------------------------------------------------
; picture_stub_depack_get_bits: the author's GET_BIT2.  d6+1 bits into d5 (Z set if 0).
;------------------------------------------------------------------------------
picture_stub_depack_get_bits:	; from: picture_stub_depack, symbol_table
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
picture_stub_depack_offset_long:	; from: picture_stub_depack, symbol_table
	lea	picture_stub_offset_bases(pc),a4 ; the offsets of 3 or more
	moveq	#2,d6                           ; 3-bit class
	bsr.s	picture_stub_depack_get_bits    ; the class
picture_stub_depack_offset_class:	; from: picture_stub_depack, symbol_table
	move.w	d5,d4
	move.b	$e(a4,d4.w),d6                  ; its bit count
	ext.w	d6
	bsr.s	picture_stub_depack_get_bits    ; the offset
	add.w	d4,d4                           ; class 0?
	beq.s	picture_stub_depack_copy        ; yes
	add.w	-$2(a4,d4.w),d5                 ; no: + its base
picture_stub_depack_copy:
	lea	1(a5,d5.w),a4                   ; the source
	move.w	(sp)+,d5                        ; the length - 2
	move.b	-(a4),-(a5)                     ; copied
picture_stub_depack_copy_byte:
	move.b	-(a4),-(a5)
	dbra	d5,picture_stub_depack_copy_byte
picture_stub_depack_literals:	; from: picture_stub_depack, symbol_table
	moveq	#11,d6                          ; the literals' count: up to 12 1s
	moveq	#11,d5                          ; up to 11
picture_stub_depack_literals_unary:	; from: symbol_table
	add.b	d7,d7                           ; the next bit
	beq.s	picture_stub_depack_literals_refill ; empty: refilled
picture_stub_depack_literals_bit:	; from: symbol_table
	dbcc	d6,picture_stub_depack_literals_unary ; a 0 ends it
	bcs.s	picture_stub_depack_literals_eight ; 12 1s: more
	sub.w	d6,d5                           ; the 1s: 0-11
	bra.s	picture_stub_depack_literals_copy
picture_stub_depack_literals_eight:	; from: symbol_table
	moveq	#7,d6                           ; 8 bits
	bsr.s	picture_stub_depack_get_bits
	beq.s	picture_stub_depack_literals_long ; 0?
	addq.w	#8,d5                           ; no: + 11
	addq.w	#3,d5
	bra.s	picture_stub_depack_literals_copy
picture_stub_depack_literals_long:
	moveq	#2,d6                           ; 3 bits
	bsr.s	picture_stub_depack_get_bits    ; the high bits
	swap	d5                              ; into the high word
	moveq	#15,d6                          ; 16 bits
	bsr.s	picture_stub_depack_get_bits
	addq.l	#8,d5                           ; + 11
	addq.l	#3,d5
picture_stub_depack_literals_copy:	; from: symbol_table
	subq.w	#1,d5                           ; any?
	bmi.s	picture_stub_depack_check       ; no
	moveq	#1,d6                           ; 65536
	swap	d6
picture_stub_depack_literals_byte:
	move.b	-(a6),-(a5)                     ; copied
	dbra	d5,picture_stub_depack_literals_byte ; the low word's
	sub.l	d6,d5                           ; 65536 more?
	bpl.s	picture_stub_depack_literals_byte ; yes (a count whose low word is 0 copies nothing)
picture_stub_depack_check:
	cmpa.l	a6,a0                           ; all read?
picture_stub_depack_more:
	bne.w	picture_stub_depack_match       ; no: the next code
	cmp.b	#$80,d7                         ; only the marker left?
	bne.s	picture_stub_depack_more        ; no: on
	movea.l	(sp)+,a0                        ; the output's end
	bsr.s	picture_stub_pictures           ; the pictures turned back
	rts
picture_stub_depack_literals_refill:	; from: symbol_table
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	picture_stub_depack_literals_bit

;------------------------------------------------------------------------------
; picture_stub_offset_bases: the author's DECRUN_TABLE.  The long offsets' class bases (classes 1-7), then
; each class's bit count - 1 (5 to 13 bits).
;------------------------------------------------------------------------------
picture_stub_offset_bases:	; from: picture_stub_depack_get_bits, symbol_table
	dc.w	$0020,$0060,$0160,$0360,$0760,$0f60,$1f60
	dc.b	$04,$05,$07,$08,$09,$0a,$0b,$0c

;------------------------------------------------------------------------------
; picture_stub_pair_offset_bases: DECRUN_TABLE2, the same for a 2-byte match (classes 0-4 only).
;------------------------------------------------------------------------------
picture_stub_pair_offset_bases:	; from: picture_stub_depack, symbol_table
	dc.w	$0020,$0060,$00e0,$01e0,$03e0,$05e0,$07e0
	dc.b	$04,$05,$06,$07,$08,$08

;------------------------------------------------------------------------------
; picture_stub_common_bytes: TABLUS_TABLE, the four common bytes, by index (common_bytes backward).
;------------------------------------------------------------------------------
picture_stub_common_bytes:	; from: picture_stub_depack, symbol_table
	dc.b	$60,$20,$10,$08

;------------------------------------------------------------------------------
; picture_stub_pictures: the author's DECOD_PICTURE.  The count word and the offsets after the program (a0 =
; its end) read and cleared; each picture turned back from 4-bit pixels to four plane words.
;------------------------------------------------------------------------------
picture_stub_pictures:	; from: picture_stub_depack_get_bits, symbol_table
	move.w	-(a0),d7                        ; the number of pictures
	clr.w	(a0)                            ; cleared
picture_stub_pictures_next:
	dbra	d7,picture_stub_picture         ; more?
	rts
picture_stub_picture:
	move.l	-(a0),d0                        ; its offset
	clr.l	(a0)                            ; cleared
	lea	0(a5,d0.l),a1                   ; + the file's start: the picture
	lea	$7d00(a1),a2                    ; its end
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
	cmpa.l	a1,a2                           ; the end?
	bne.s	picture_stub_picture_group      ; no
	bra.s	picture_stub_pictures_next      ; the next picture

;------------------------------------------------------------------------------
; picture_stub_title_text: the author's HELLO_TXT.  The title at row 0, column 5 (25 when not low
; resolution), with no 0: in the file the packed data's first byte, the unpacked length's high byte, ends it.
;------------------------------------------------------------------------------
picture_stub_title_text:	; from: picture_stub_text, symbol_table
	dc.b	27,'Y %ATOMIK v3.3 by ALTAIR VMAX/MCS'

;------------------------------------------------------------------------------
; offset_steps: the author's OFFSET_TABLE (and PACKED_CODE, the end of the picture stub).  The long
; offsets' classes' sizes (their sum is $3f60, the search's reach).
;------------------------------------------------------------------------------
offset_steps:	; from: put_offset, symbol_table
	dc.w	$0020,$0040,$0100,$0200,$0400,$0800,$1000,$2000

;------------------------------------------------------------------------------
; pair_offset_steps: OFFSET_TABLE2, the same for a 2-byte match: classes 0-4 sum to $3e0.
;------------------------------------------------------------------------------
pair_offset_steps:	; from: put_offset, symbol_table
	dc.w	$0020,$0040,$0080,$0100,$0200,$0200,$0200,$0200

;------------------------------------------------------------------------------
; stub: the author's DECRUN_CODE2, the stub put before a packed program without pictures ($238 bytes, to
; match_offset).  The same as picture_stub, less the pictures.
;------------------------------------------------------------------------------
stub:	; from: crunch_file, symbol_table
	dc.w	$601a                           ; bra.s stub_text, over the header
stub_text_length:	; from: crunch_file, symbol_table
	dc.l	$00000000
stub_data_length:
	dc.l	$00000000
stub_bss_length:
	dc.l	$00000000
stub_symbol_length:
	dc.l	$00000000
stub_reserved:
	dc.l	$00000000
stub_flags:
	dc.l	$00000000
stub_absolute:
	dc.w	$0000                           ; 0: relocation follows (the zero long: none)

;------------------------------------------------------------------------------
; stub_text: the author's DECRUNCHER2.  The top of the screen cleared, the title shown, the program depacked
; behind the stub, relocated and its basepage set, then moved down over the stub by a mover copied past
; it, which runs the program.
;------------------------------------------------------------------------------
stub_text:	; from: symbol_table
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
	lea	stub+$238(pc),a0                ; the packed data, after the stub
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

;------------------------------------------------------------------------------
; stub_mover: the author's COPY_CODE2, run past the relocation table.
;------------------------------------------------------------------------------
stub_mover:	; from: stub_text, symbol_table
	movea.l	a3,a4                           ; the start
stub_mover_copy:
	move.l	(a5)+,(a3)+                     ; the text and data moved down
	subq.l	#4,d6
	bcc.s	stub_mover_copy
stub_mover_clear:
	clr.l	(a2)+                           ; the mover cleared from its start: once this clr has cleared itself and
                                                ;   the bra, the prefetched bra still runs, 0 runs as ori.b #0,d0, and
                                                ;   the last clr wipes the jmp already fetched
	bra.s	stub_mover_clear
	clr.l	(a2)+
	jmp	(a4)                            ; run the program

;------------------------------------------------------------------------------
; stub_depack: the author's DEPACK2.  The packed data at a0 (its packed length) depacked backward, to $7e
; past a0 plus the unpacked length (a fixed margin).  a5 = the program.
;------------------------------------------------------------------------------
stub_depack:	; from: stub_text, symbol_table
	lea	$7e(a0,d0.l),a5                 ; the output's end
	move.l	(a0)+,d0                        ; the packed length
	lea	0(a0,d0.l),a6                   ; its end
	move.b	-(a6),d7                        ; the last bit byte
	bra.w	stub_depack_literals            ; its literals first
stub_depack_common_byte:	; from: symbol_table
	lea	stub_common_bytes(pc),a4        ; class 7: one of the four common bytes
	moveq	#1,d6                           ; 2 bits
	bsr.s	stub_depack_get_bits            ; its index
	bra.s	stub_depack_byte_put            ; put
stub_depack_match:	; from: stub_depack_get_bits, symbol_table
	moveq	#6,d6                           ; a code: its length, up to 7 bits
stub_depack_unary:	; from: symbol_table
	add.b	d7,d7                           ; the next bit
	beq.s	stub_depack_unary_refill        ; empty: refilled
stub_depack_unary_bit:
	dbcc	d6,stub_depack_unary            ; a 0 ends it
	bcs.s	stub_depack_length_four         ; 7 1s: more
	moveq	#6,d5                           ; the 1s: 0-6
	sub.w	d6,d5
	bra.s	stub_depack_length              ; the length - 2
stub_depack_length_four:
	moveq	#3,d6                           ; 4 bits
	bsr.s	stub_depack_get_bits
	beq.s	stub_depack_length_eight        ; 0?
	addq.w	#6,d5                           ; no: 7-21
	bra.s	stub_depack_length
stub_depack_length_eight:
	moveq	#7,d6                           ; 8 bits
	bsr.s	stub_depack_get_bits
	beq.s	stub_depack_length_long         ; 0?
	addi.w	#$15,d5                         ; no: 22-276
	bra.s	stub_depack_length
stub_depack_unary_refill:
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	stub_depack_unary_bit
stub_depack_length_long:
	moveq	#13,d6                          ; 14 bits
	bsr.s	stub_depack_get_bits
	addi.w	#$114,d5                        ; + 276
stub_depack_length:
	move.w	d5,-(sp)                        ; kept
	bne.s	stub_depack_offset_long         ; 3 or more: the long offsets
	lea	stub_pair_offset_bases(pc),a4   ; 0: a 2-byte match or a one-byte code
	moveq	#2,d6                           ; 3-bit class
	bsr.s	stub_depack_get_bits
	cmp.w	#$5,d5                          ; 0-4?
	blt.s	stub_depack_offset_class        ; yes: a 2-byte match
	addq.w	#2,sp                           ; no: a one-byte code
	subq.w	#6,d5                           ; 7?
	bgt.s	stub_depack_common_byte         ; yes: a common byte
	movea.l	a5,a4                           ; 5: one of the next 4 bytes
	blt.s	stub_depack_near                ; yes
	addq.w	#4,a4                           ; 6: one of the 4 after them
stub_depack_near:
	moveq	#1,d6                           ; 2 bits: which
	bsr.s	stub_depack_get_bits
stub_depack_byte_put:	; from: symbol_table
	move.b	0(a4,d5.w),-(a5)                ; the byte put
	bra.s	stub_depack_literals            ; then literals

;------------------------------------------------------------------------------
; stub_depack_get_bits: d6+1 bits into d5 (Z set if 0).
;------------------------------------------------------------------------------
stub_depack_get_bits:	; from: stub_depack, symbol_table
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
stub_depack_offset_long:	; from: stub_depack, symbol_table
	lea	stub_offset_bases(pc),a4        ; the offsets of 3 or more
	moveq	#2,d6                           ; 3-bit class
	bsr.s	stub_depack_get_bits            ; the class
stub_depack_offset_class:	; from: stub_depack, symbol_table
	move.w	d5,d4
	move.b	$e(a4,d4.w),d6                  ; its bit count
	ext.w	d6
	bsr.s	stub_depack_get_bits            ; the offset
	add.w	d4,d4                           ; class 0?
	beq.s	stub_depack_copy                ; yes
	add.w	-$2(a4,d4.w),d5                 ; no: + its base
stub_depack_copy:
	lea	1(a5,d5.w),a4                   ; the source
	move.w	(sp)+,d5                        ; the length - 2
	move.b	-(a4),-(a5)                     ; copied
stub_depack_copy_byte:
	move.b	-(a4),-(a5)
	dbra	d5,stub_depack_copy_byte
stub_depack_literals:	; from: stub_depack, symbol_table
	moveq	#11,d6                          ; the literals' count: up to 12 1s
	moveq	#11,d5                          ; up to 11
stub_depack_literals_unary:	; from: symbol_table
	add.b	d7,d7                           ; the next bit
	beq.s	stub_depack_literals_refill     ; empty: refilled
stub_depack_literals_bit:	; from: symbol_table
	dbcc	d6,stub_depack_literals_unary   ; a 0 ends it
	bcs.s	stub_depack_literals_eight      ; 12 1s: more
	sub.w	d6,d5                           ; the 1s: 0-11
	bra.s	stub_depack_literals_copy
stub_depack_literals_eight:	; from: symbol_table
	moveq	#7,d6                           ; 8 bits
	bsr.s	stub_depack_get_bits
	beq.s	stub_depack_literals_long       ; 0?
	addq.w	#8,d5                           ; no: + 11
	addq.w	#3,d5
	bra.s	stub_depack_literals_copy
stub_depack_literals_long:
	moveq	#2,d6                           ; 3 bits
	bsr.s	stub_depack_get_bits            ; the high bits
	swap	d5                              ; into the high word
	moveq	#15,d6                          ; 16 bits
	bsr.s	stub_depack_get_bits
	addq.l	#8,d5                           ; + 11
	addq.l	#3,d5
stub_depack_literals_copy:	; from: symbol_table
	subq.w	#1,d5                           ; any?
	bmi.s	stub_depack_check               ; no
	moveq	#1,d6                           ; 65536
	swap	d6
stub_depack_literals_byte:
	move.b	-(a6),-(a5)                     ; copied
	dbra	d5,stub_depack_literals_byte    ; the low word's
	sub.l	d6,d5                           ; 65536 more?
	bpl.s	stub_depack_literals_byte       ; yes (a count whose low word is 0 copies nothing)
stub_depack_check:
	cmpa.l	a6,a0                           ; all read?
stub_depack_more:
	bne.w	stub_depack_match               ; no: the next code
	cmp.b	#$80,d7                         ; only the marker left?
	bne.s	stub_depack_more                ; no: on
	rts                                     ; done
stub_depack_literals_refill:	; from: symbol_table
	move.b	-(a6),d7                        ; the next bit byte
	addx.b	d7,d7                           ; its first bit
	bra.s	stub_depack_literals_bit

;------------------------------------------------------------------------------
; stub_offset_bases: the long offsets' class bases (classes 1-7), then each class's bit count - 1.
;------------------------------------------------------------------------------
stub_offset_bases:	; from: stub_depack_get_bits, symbol_table
	dc.w	$0020,$0060,$0160,$0360,$0760,$0f60,$1f60
	dc.b	$04,$05,$07,$08,$09,$0a,$0b,$0c

;------------------------------------------------------------------------------
; stub_pair_offset_bases: the same for a 2-byte match (classes 0-4 only).
;------------------------------------------------------------------------------
stub_pair_offset_bases:	; from: stub_depack, symbol_table
	dc.w	$0020,$0060,$00e0,$01e0,$03e0,$05e0,$07e0
	dc.b	$04,$05,$06,$07,$08,$08

;------------------------------------------------------------------------------
; stub_common_bytes: the four common bytes, by index.
;------------------------------------------------------------------------------
stub_common_bytes:	; from: stub_depack, symbol_table
	dc.b	$60,$20,$10,$08

;------------------------------------------------------------------------------
; stub_title_text: the title as in the picture stub; in the file the unpacked length's high byte ends it.
;------------------------------------------------------------------------------
stub_title_text:	; from: stub_text, symbol_table
	dc.b	27,'Y %ATOMIK v3.3 by ALTAIR VMAX/MCS'

;------------------------------------------------------------------------------
; match_offset: the author's OFFSET (and PACKED_CODE2, the end of the normal stub).  The cruncher's
; variables follow.
;------------------------------------------------------------------------------
match_offset:	; from: match, put_match, symbol_table
	dc.w	$0000                           ; the best match's offset
match_length:	; from: match, put_match, symbol_table
	dc.w	$0000                           ; its length (0: none)
match_flag:	; from: match, symbol_table
	dc.b	$00                             ; $ff: a match found (the author's SAVE_SIZE)
byte_kind:	; from: put_match
	dc.b	$00                             ; a one-byte code: 1 a common byte, 2 a byte near
byte_value:	; from: put_match
	dc.w	$0000                           ; its index (3-0) or distance (1-8)
	dc.w	$0000                           ; not used
save_length:	; from: crunch_file, symbol_table
	dc.l	$00000000                       ; the length saved
resolution:	; from: start, quit, symbol_table
	dc.w	$0000                           ; the resolution at the start
data_mode:	; from: main_menu, crunch_all_menu, crunch_file, pack, symbol_table
	dc.b	$00                             ; $ff: data mode, 0: program mode
	dc.b	$00
input_end:	; from: print_crunch_left, pack, match, analyse_window, symbol_table
	dc.l	$00000000                       ; the file's end in the load buffer

;------------------------------------------------------------------------------
; common_bytes: the author's TABLUS_TABLE3.  The four bytes with a one-byte code of their own.
;------------------------------------------------------------------------------
common_bytes:	; from: match, symbol_table
	dc.b	$08,$10,$20,$60

;------------------------------------------------------------------------------
; title_text: the author's PRESENT.  The screen cleared and the title, "v3.3 Comleted on 15/4/1991".
;------------------------------------------------------------------------------
title_text:	; from: main_menu, parameters_menu, crunch_all_menu, crunch_file, crunch_file_save, symbol_table
	dc.b	27,'E                          ****************************',10,13
	dc.b	'                          *ATOMIK CRUNCHER3 BY ALTAIR*',10,13
	dc.b	'                          *v3.3 Comleted on 15/4/1991*',10,13
	dc.b	'                          ****************************',10,10,13,0

;------------------------------------------------------------------------------
; main_menu_text: the author's ASK_MODE.  The main menu, with "173 % ERROR FREE! VMAX &MCS" down its right.
;------------------------------------------------------------------------------
main_menu_text:	; from: main_menu, symbol_table
	dcb.w	13,$2020                        ; 26 spaces
	dc.b	'1: CRUNCH EXECUTABLE |173 %',10,13
	dc.b	'                          2: CRUNCH DATA FILE. |ERROR',10,13
	dc.b	'                          3: CRUNCH ALL FILES. |FREE!',10,10,13
	dc.b	'                          4: CRUNCH PARAMETERS |VMAX',10,13
	dc.b	'                          5: EXIT FROM ATOMIK. |&MCS',10,10,13,0

;------------------------------------------------------------------------------
; parameters_menu_text: the parameters menu.
;------------------------------------------------------------------------------
parameters_menu_text:	; from: parameters_menu, symbol_table
	dcb.w	13,$2020                        ; 26 spaces
	dc.b	'1: EXTENDS FOR PARAMETERS',10,13
	dc.b	'                          2: SET PICTURE PARAMETERS',10,10,13
	dc.b	'                          3: CLEAR ALL PARAMETERS',10,13
	dc.b	'                          4: EXIT FROM PARAMETERS',10,10,13,0
picture_number_text:	; from: set_pictures, symbol_table
	dc.b	'                          ENTER PICTURE NUMBER: ',0 ; the parameters, key 2
offset_number_text:	; from: ask_picture_offset, symbol_table
	dc.b	13,'                          ENTER OFFSET N.' ; then the picture's number; no 0: it runs into
                                                ;   clear_to_end_text
clear_to_end_text:	; from: crunch_pictures, analyse_window, symbol_table
	dc.b	$1b,$4b,$00                     ; ESC K: the rest of the line cleared
picture_parameters_text:	; from: crunch_file, symbol_table
	dc.b	'                          PICTURE PARAMETERS N.',0 ; a bad offset: the picture's number, then
                                                ;   bad_offset_text
bad_offset_text:	; from: crunch_file, symbol_table
	dc.b	' BAD',10,13,'                          OFFSET + 7D00 > FILE LENGHT',0
colon_text:	; from: ask_picture_offset, symbol_table
	dc.b	$3a,$20,$00                     ; ": " after the picture's number
encoding_picture_text:	; from: crunch_pictures, symbol_table
	dc.b	13,'                          ENCODING PICTURE N.',0 ; then the picture's number
clear_parameters_text:	; from: parameters_menu, symbol_table
	dc.b	'                          CLEAR PARAMETERS? (Y/N) ',0 ; the parameters, key 3
parameters_cleared_text:	; from: parameters_menu, symbol_table
	dc.b	13,'                          PARAMETERS CLEARED!',27,'K',0

;------------------------------------------------------------------------------
; crunch_all_menu_text: the crunch all menu.
;------------------------------------------------------------------------------
crunch_all_menu_text:	; from: crunch_all_menu, symbol_table
	dc.b	'                          1: CRUNCH *.* IN DATA MODE',10,13
	dc.b	'                          2: CRUNCH *.* IN EXEC MODE',10,10,13
	dc.b	'                          3: SET DIR TO BE CRUNCHED',10,13
	dc.b	'                          4: EXIT FROM MULTI CRUNCH',10,10,13,0
disk_empty_text:	; from: crunch_all_menu, symbol_table
	dc.b	13,'                          HEY! DISK EMPTY!',27,'K',0 ; crunch all, no file found

;------------------------------------------------------------------------------
; batch_ok_text, files_packed_text, batch_in_text, files_loaded_text: the crunch all summary (the author's
; MULTI_CR_END to MULTI_CR_END3).
;------------------------------------------------------------------------------
batch_ok_text:	; from: crunch_all_menu, symbol_table
	dc.b	13,'                          OK ',0
files_packed_text:	; from: crunch_all_menu, symbol_table
	dc.b	' FILE(S) PACKED',27,'K',10,0
batch_in_text:	; from: crunch_all_menu, symbol_table
	dc.b	13,'                          IN ',0
files_loaded_text:	; from: crunch_all_menu, symbol_table
	dc.b	' FILE(S) LOADED',27,'K',0

;------------------------------------------------------------------------------
; extends_text: the author's EXTENDS_TXT, key 1 of the parameters menu: how to give the pictures' offsets.
;------------------------------------------------------------------------------
extends_text:	; from: parameters_menu, symbol_table
	dc.b	'extends for use.',10,10,13
	dc.b	'for best crunch of picture i use a special bits planes algorythm',10,13
	dc.b	'but i cannot detect picture very well without make many analyse',10,13
	dc.b	'and test and it',$27,'s better if you give me the exact offset of the'
	dc.b	10,13,'first word of the picture from the top of the file',10,10,13
	dc.b	'CAUTION !',10,10,13
	dc.b	'the offset you give me must be the offset of the first plane',10,13
	dc.b	'of the picture and not the first word of the picture file.',10,10,13
	dc.b	'exemple:',10,10,13
	dc.b	'for a degelite picture format you must give me the offset of',10,13
	dc.b	'the picture file increased of $22 (i just encode $7d00 bytes',10,13
	dc.b	'the exact lenght of a screen picture.)',10,10,13
	dc.b	'CAUTION!: offset in Hex,picture number in Dec.',0
out_of_memory_text:	; from: no_memory, symbol_table
	dc.b	27,'Eout of memory!',0          ; the screen cleared first
cannot_crunch_text:	; from: crunch_file_save, symbol_table
	dc.b	13,'                          SORRY CANNOT CRUNCH..',27,'K',10,13,27,'K' ; no gain
	dc.b	0
crunching_text:	; from: crunch_file, symbol_table
	dc.b	'                          CRUNCHING  : ',0 ; then the full name
crunch_left_text:	; from: print_crunch_left, symbol_table
	dc.b	13,'                          CRUNCH LEFT: ',0 ; then the bytes left, in hex
crunch_done_text:	; from: print_crunch_done, symbol_table
	dc.b	10,13,'                          CRUNCH DONE: ',0 ; then the output so far, in hex
save_length_text:	; from: crunch_file, symbol_table
	dc.b	10,13,27,'K',10,'                          SAVE LENGHT:  ',0 ; then the length saved, in hex
file_text:	; from: crunch_file_save, symbol_table
	dc.b	10,10,13,'                          FILE: ',0 ; then the full name and saved_text
saved_text:	; from: crunch_file_save, symbol_table
	dc.b	' SAVED',27,'K',0
write_error_text:	; from: crunch_file_save, symbol_table
	dc.b	13,'                          WRITE ERROR! RETRY (Y/N)',27,'K',0
crunching_time_text:	; from: print_time, symbol_table
	dc.b	13,'                          CRUNCHING TIME:    ',27,'K',0 ; then time_text
save_packed_text:	; from: crunch_file_save, symbol_table
	dc.b	10,10,13,'                          SAVE PACK FILE? (Y/N)',27,'K',0

;------------------------------------------------------------------------------
; interruption_text: the question, then the line below cleared and the cursor back up.
;------------------------------------------------------------------------------
interruption_text:	; from: match_report, symbol_table
	dc.b	13,'                              INTERUPTION? (Y/N)',27,'K',10,13,27
	dc.b	'K',27,'I',0
analysing_text:	; from: analyse_window, symbol_table
	dc.b	10,10,13,'                          ANALYSING',27,'K',13,0 ; the line cleared after, then up two lines

;------------------------------------------------------------------------------
; new_lines_text: two new lines; new_line_text one.
;------------------------------------------------------------------------------
new_lines_text:	; from: set_pictures, crunch_file, crunch_file_save, symbol_table
	dc.b	$0a
new_line_text:	; from: symbol_table
	dc.b	$0a,$0d,$00

;------------------------------------------------------------------------------
; up_two_lines_text: ESC I twice; up_line_text once.
;------------------------------------------------------------------------------
up_two_lines_text:	; from: analyse_window, symbol_table
	dc.b	$1b,$49
up_line_text:	; from: print_crunch_done, symbol_table
	dc.b	$1b,$49,$00

;------------------------------------------------------------------------------
; backspaces_text: nine backspaces (not used), then the rub-outs before rub_out.
;------------------------------------------------------------------------------
backspaces_text:	; from: symbol_table
	dc.b	$08,$08,$08,$08,$08,$08,$08,$08,$08,$00
	dc.b	$08,$20,$08,$08,$20,$08,$08,$20,$08,$08,$20,$08,$08,$20,$08,$08 ; eight "\b \b": with rub_out, room for
                                                ;   9 digits rubbed out
	dc.b	$20,$08,$08,$20,$08,$08,$20,$08

;------------------------------------------------------------------------------
; rub_out: "\b \b"; input_number goes back 3 bytes for each more digit to rub out.
;------------------------------------------------------------------------------
rub_out:	; from: input_number, symbol_table
	dc.b	$08,$20,$08,$00
bell_text:	; from: ring_until_key, symbol_table
	dc.b	$07,$00                         ; the bell
program_mask:	; from: main_menu, symbol_table
	dc.b	'*.PRG',0                       ; crunch a program
any_mask:	; from: main_menu, crunch_all_menu, find_first, symbol_table
	dc.b	'*.*',0                         ; crunch a data file, crunch all

;------------------------------------------------------------------------------
; aes_block: the AES parameter block for fsel_input (90).
;------------------------------------------------------------------------------
aes_block:	; from: choose_file, symbol_table
	dc.l	aes_control
	dc.l	aes_global
	dc.l	aes_int_in
	dc.l	aes_int_out
	dc.l	aes_addr_in
	dc.l	aes_addr_out
aes_control:	; from: symbol_table
	dc.w	$005a,$0000,$0002,$0002         ; fsel_input, 0 int_in, 2 int_out, 2 addr_in
aes_global:	; from: symbol_table
	dc.w	$0120,$0001                     ; also read as control's fifth word
aes_int_in:	; from: symbol_table
	dc.w	$0000                           ; not used by fsel_input
aes_int_out:	; from: symbol_table
	dc.w	$0001                           ; 0 for an error
fsel_button:	; from: choose_file
	dc.w	$0000,$0000                     ; OK or Cancel
aes_addr_in:	; from: symbol_table
	dc.l	path_text                       ; the path and the name
	dc.l	chosen_name
aes_addr_out:	; from: symbol_table
	dc.w	$0000

;------------------------------------------------------------------------------
; path_text: the author's ADR0.  The path for the file selector, then cut to the folder.
;------------------------------------------------------------------------------
path_text:	; from: choose_file, set_path, get_path, make_name, aes_block, symbol_table
	dcb.b	79,0

;------------------------------------------------------------------------------
; chosen_name: the author's ADR1.  The name chosen or found.
;------------------------------------------------------------------------------
chosen_name:	; from: make_name, copy_found_name, aes_block, symbol_table
	dcb.b	65,0

;------------------------------------------------------------------------------
; full_name: the author's FILENAME.  The drive, folder and name.
;------------------------------------------------------------------------------
full_name:	; from: make_name, load_file, write_file, crunch_file, crunch_file_save, symbol_table
	dcb.b	66,0

;------------------------------------------------------------------------------
; dta: the author's DTA_BUFFER.
;------------------------------------------------------------------------------
dta:	; from: set_dta, symbol_table
	dcb.b	30,0
dta_name:	; from: copy_found_name, symbol_table
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; the name found
io_error:	; from: load_file, write_file, crunch_file_save, symbol_table
	dc.b	$00,$00                         ; $ff: a read or write failed
file_handle:	; from: load_file, write_file, close_file, symbol_table
	dc.w	$0000                           ; the file open
file_length:	; from: load_file, crunch_file, symbol_table
	dc.l	$00000000                       ; the length read
start_ticks:	; from: print_time, read_start_time, symbol_table
	dc.l	$00000000                       ; _hz_200 at the start
end_ticks:	; from: print_time, read_start_time, symbol_table
	dc.l	$00000000                       ; _hz_200 at the end
crunch_length:	; from: crunch_file, pack, match_report, symbol_table
	dc.l	$00000000                       ; the length crunched (with the offsets)
crunch_left:	; from: print_crunch_left, crunch_file, symbol_table
	dc.l	$00000000                       ; the bytes left to crunch
next_report:	; from: print_crunch_left, pack, match, symbol_table
	dc.l	$00000000                       ; where the next "CRUNCH LEFT:" is due
time_text:	; from: print_time, symbol_table
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00 ; mmm:ss
file_mask:	; from: main_menu, crunch_file_save, symbol_table
	dc.l	$00000000                       ; the mask for the save

;------------------------------------------------------------------------------
; picture_offsets: the author's OFFSET_SAVER.  Up to 50 pictures' offsets.
;------------------------------------------------------------------------------
picture_offsets:	; from: set_pictures, crunch_file, crunch_pictures, symbol_table
	dcb.b	200,0
picture_count:	; from: parameters_menu, set_pictures, crunch_file, crunch_pictures, symbol_table
	dc.b	$00                             ; the number of pictures
pictures_on:	; from: crunch_file, symbol_table
	dc.b	$00                             ; $ff: pictures in this file
batch:	; from: main_menu, crunch_all_menu, crunch_file_save, symbol_table
	dc.b	$00                             ; $ff: crunch all
interrupted:	; from: crunch_all_menu, crunch_file, pack, match_report, symbol_table
	dc.b	$00                             ; $ff: stopped
not_crunched:	; from: crunch_all_menu, crunch_file, crunch_file_save, symbol_table
	dc.b	$00,$00                         ; $ff: no gain
loaded_count:	; from: crunch_all_menu, symbol_table
	dc.b	$00                             ; the files loaded by crunch all, in BCD (the author's FILE_NUMBER)
	dc.b	$00
packed_count:	; from: crunch_all_menu, symbol_table
	dc.b	$00                             ; the files packed, in BCD (CRUNCH_NUMBER), never cleared
	dc.b	$00

;------------------------------------------------------------------------------
; saved_palette: the author's SAVE_COLORS: 64 bytes, of which the palette uses 32.
;------------------------------------------------------------------------------
saved_palette:	; from: save_palette, restore_palette, symbol_table
	dcb.b	64,0                            ; the 16 colours at the start

;------------------------------------------------------------------------------
; hex_text: the author's STRING_BUFFER.  A space, the 8 hex digits (VALUE_BUFFER), then ESC q.
;------------------------------------------------------------------------------
hex_text:	; from: print_hex, symbol_table
	dc.b	$20,$00,$00,$00,$00,$00,$00,$00,$00,$1b,$71,$00

;------------------------------------------------------------------------------
; symbol_table: the author's DRI symbol table, left in the text when the program was packed: 14-byte records,
; an 8-byte name, the type and the value.  $a200 is a text symbol, $a100 a bss one; $0048 set means the next
; record holds the rest of the name.  Bss values count from the bss start, which was $288c: PACK_ADR $10396 is
; bss_end+$f144, LOAD_ADRESS $14396 bss_end+$13144, DECRUN_SPACE(2) the stubs' places before it, and
; MARK_TABLE $118 is positions ($29a4).  The bss values are written as numbers.
;------------------------------------------------------------------------------
symbol_table:
	dc.b	'ADR0',0,0,0,0
	dc.w	$a200
	dc.l	path_text-start
	dc.b	'ADR1',0,0,0,0
	dc.w	$a200
	dc.l	chosen_name-start
	dc.b	'MODE',0,0,0,0
	dc.w	$a200
	dc.l	data_mode-start
	dc.b	'CLOSE',0,0,0
	dc.w	$a200
	dc.l	close_file-start
	dc.b	'CTRL0',0,0,0
	dc.w	$a200
	dc.l	aes_control-start
	dc.b	'CTRL1',0,0,0
	dc.w	$a200
	dc.l	aes_global-start
	dc.b	'CTRL2',0,0,0
	dc.w	$a200
	dc.l	aes_int_in-start
	dc.b	'CTRL3',0,0,0
	dc.w	$a200
	dc.l	aes_int_out-start
	dc.b	'CTRL4',0,0,0
	dc.w	$a200
	dc.l	aes_addr_in-start
	dc.b	'CTRL5',0,0,0
	dc.w	$a200
	dc.l	aes_addr_out-start
	dc.b	'EMPTY',0,0,0
	dc.w	$a200
	dc.l	picture_stub_depack_literals_refill-start
	dc.b	'PTERM',0,0,0
	dc.w	$a200
	dc.l	quit-start
	dc.b	'START',0,0,0
	dc.w	$a200
	dc.l	start-start
	dc.b	'ATOMIK',0,0
	dc.w	$a200
	dc.l	crunch_pictures-start
	dc.b	'BIGGER',0,0
	dc.w	$a200
	dc.l	picture_stub_depack_offset_long-start
	dc.b	'CALCUL',0,0
	dc.w	$a200
	dc.l	put_match-start
	dc.b	'CODE_T',0,0
	dc.w	$a200
	dc.l	offset_prefixes-start
	dc.b	'CONTUS',0,0
	dc.w	$a200
	dc.l	picture_stub_depack_offset_class-start
	dc.b	'DEPACK',0,0
	dc.w	$a200
	dc.l	picture_stub_depack-start
	dc.b	'EMPTY2',0,0
	dc.w	$a200
	dc.l	stub_depack_literals_refill-start
positions:	; from: analyse_window
	dc.b	'FSNEXT',0,0                    ; positions: the author's MARK_TABLE, the places of each byte in the
                                                ;   window, by byte ($8000 words, to the picture stub's place); it
                                                ;   writes over this table at run time
	dc.w	$a200
	dc.l	find_next-start
	dc.b	'HANDLE',0,0
	dc.w	$a200
	dc.l	file_handle-start
	dc.b	'LARGER',0,0
	dc.w	$a200
	dc.l	crunch_file_no_gain-start
	dc.b	'LENGHT',0,0
	dc.w	$a200
	dc.l	match_length-start
	dc.b	'OFFSET',0,0
	dc.w	$a200
	dc.l	match_offset-start
	dc.b	'PARAMS',0,0
	dc.w	$a200
	dc.l	aes_block-start
	dc.b	'TABLUS',0,0
	dc.w	$a200
	dc.l	picture_stub_depack_common_byte-start
	dc.b	'BIGGER2',0
	dc.w	$a200
	dc.l	stub_depack_offset_long-start
	dc.b	'CODE_T2',0
	dc.w	$a200
	dc.l	pair_offset_prefixes-start
	dc.b	'CONTUS2',0
	dc.w	$a200
	dc.l	stub_depack_offset_class-start
	dc.b	'DEPACK2',0
	dc.w	$a200
	dc.l	stub_depack-start
	dc.b	'FSETDTA',0
	dc.w	$a200
	dc.l	set_dta-start
	dc.b	'FSFIRST',0
	dc.w	$a200
	dc.l	find_first-start
	dc.b	'GET_DIR',0
	dc.w	$a200
	dc.l	get_path-start
	dc.b	'MSHRINK',0
	dc.w	$a200
	dc.l	shrink-start
	dc.b	'PACKING',0
	dc.w	$a200
	dc.l	match-start
	dc.b	'PRESENT',0
	dc.w	$a200
	dc.l	title_text-start
	dc.b	'SET_DIR',0
	dc.w	$a200
	dc.l	set_path-start
	dc.b	'SUPEXEC',0
	dc.w	$a200
	dc.l	supervisor_call-start
	dc.b	'TABLUS2',0
	dc.w	$a200
	dc.l	picture_stub_depack_byte_put-start
	dc.b	'UP_LINE',0
	dc.w	$a200
	dc.l	up_line_text-start
	dc.b	'ASK_MODE'
	dc.w	$a200
	dc.l	main_menu_text-start
	dc.b	'ASK_SAVE'
	dc.w	$a200
	dc.l	save_packed_text-start
	dc.b	'BIP_CODE'
	dc.w	$a200
	dc.l	bell_text-start
	dc.b	'CONT_JNK'
	dc.w	$a200
	dc.l	picture_stub_depack_literals_bit-start
	dc.b	'DECRUNCH'
	dc.w	$a200
	dc.l	picture_stub_depack_match-start
	dc.b	'DEC_HEXA'
	dc.w	$a200
	dc.l	bcd_to_word-start
	dc.b	'END_FILE'
	dc.w	$a200
	dc.l	input_end-start
	dc.b	'FILENAME'
	dc.w	$a200
	dc.l	full_name-start
	dc.b	'GET_BIT2'
	dc.w	$a200
	dc.l	picture_stub_depack_get_bits-start
	dc.b	'HEXA_DEC'
	dc.w	$a200
	dc.l	to_bcd-start
	dc.b	'INTERUPT'
	dc.w	$a200
	dc.l	interruption_text-start
	dc.b	'MAKE_JNK'
	dc.w	$a200
	dc.l	picture_stub_depack_literals-start
	dc.b	'NEXT_COD'
	dc.w	$a200
	dc.l	picture_stub_depack_literals_eight-start
	dc.b	'PACK_ADR'
	dc.w	$a100
	dc.l	$10396
	dc.b	'PIC_FLAG'
	dc.w	$a200
	dc.l	pictures_on-start
	dc.b	'PRINT_A0'
	dc.w	$a200
	dc.l	print-start
	dc.b	'PRINT_D0'
	dc.w	$a200
	dc.l	print_hex-start
	dc.b	'PRINT_D1'
	dc.w	$a200
	dc.l	print_char-start
	dc.b	'READ_KEY'
	dc.w	$a200
	dc.l	get_key-start
	dc.b	'RW_ERROR'
	dc.w	$a200
	dc.l	io_error-start
	dc.b	'SAVE_10K'
	dc.w	$a200
	dc.l	take_memory-start
	dc.b	'SAVE_4BA'
	dc.w	$a200
	dc.l	start_ticks-start
	dc.b	'SAVE_REZ'
	dc.w	$a200
	dc.l	resolution-start
	dc.b	'SET_TIME'
	dc.w	$a200
	dc.l	put_bcd3-start
	dc.b	'TABLUS_2'
	dc.w	$a200
	dc.l	stub_depack_common_byte-start
	dc.b	'TAKE_JNK'
	dc.w	$a200
	dc.l	picture_stub_depack_literals_unary-start
	dc.b	'ALGORYTH'
	dc.w	$a248
	dc.l	pack-start
	dc.b	'M',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'CONT_JNK'
	dc.w	$a248
	dc.l	stub_depack_literals_bit-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'CONT_PAC'
	dc.w	$a248
	dc.l	match_next-start
	dc.b	'K',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'COPY_COD'
	dc.w	$a248
	dc.l	picture_stub_mover-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'COPY_JNK'
	dc.w	$a248
	dc.l	picture_stub_depack_literals_copy-start
	dc.b	'1',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'CRUNCHIN'
	dc.w	$a248
	dc.l	crunching_text-start
	dc.b	'G',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'DECRUNCH'
	dc.w	$a248
	dc.l	stub_depack_match-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'EVER_PAC'
	dc.w	$a248
	dc.l	crunch_done_text-start
	dc.b	'K',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'EXEC_TIM'
	dc.w	$a248
	dc.l	crunching_time_text-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'FILENAME'
	dc.w	$a248
	dc.l	dta_name-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'GET_HZ20'
	dc.w	$a248
	dc.l	read_end_time-start
	dc.b	'0',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'HELLO_TX'
	dc.w	$a248
	dc.l	picture_stub_title_text-start
	dc.b	'T',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'HOW_TABL'
	dc.w	$a248
	dc.l	byte_counts-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'MAKE_JNK'
	dc.w	$a248
	dc.l	stub_depack_literals-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'MULTI_TX'
	dc.w	$a248
	dc.l	crunch_all_menu_text-start
	dc.b	'T',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'NEXT_COD'
	dc.w	$a248
	dc.l	stub_depack_literals_eight-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'NEXT_FIL'
	dc.w	$a248
	dc.l	find_file-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'OK_OFFSE'
	dc.w	$a248
	dc.l	match_try-start
	dc.b	'T',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'OK_SAVED'
	dc.w	$a248
	dc.l	saved_text-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'PRINT2_D'
	dc.w	$a248
	dc.l	print_decimal-start
	dc.b	'1',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'QUIT_COD'
	dc.w	$a248
	dc.l	crunch_file_done-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'QUIT_FLA'
	dc.w	$a248
	dc.l	interrupted-start
	dc.b	'G',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'READ_FIL'
	dc.w	$a248
	dc.l	load_file-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'SAVE2_4B'
	dc.w	$a248
	dc.l	end_ticks-start
	dc.b	'A',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'SAVE_FIL'
	dc.w	$a248
	dc.l	crunch_file_save-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'SAVE_SIZ'
	dc.w	$a248
	dc.l	match_flag-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'SET_COLO'
	dc.w	$a248
	dc.l	save_palette-start
	dc.b	'R',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'SET_TIME'
	dc.w	$a248
	dc.l	put_bcd2-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'SKIP_LIN'
	dc.w	$a248
	dc.l	new_line_text-start
	dc.b	'E',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'TABLUS2_'
	dc.w	$a248
	dc.l	stub_depack_byte_put-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'TAKE_JNK'
	dc.w	$a248
	dc.l	stub_depack_literals_unary-start
	dc.b	'2',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'TO_CRUNC'
	dc.w	$a248
	dc.l	crunch_left_text-start
	dc.b	'H',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'UP_2LINE'
	dc.w	$a248
	dc.l	up_two_lines_text-start
	dc.b	'S',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'WRITE_ER'
	dc.w	$a248
	dc.l	crunch_file_write_error-start
	dc.b	'R',0,0,0,0,0,0,0,0,0,0,0,0,0   ; the rest of the name
	dc.b	'ANALYS_T'
	dc.w	$a248
	dc.l	analysing_text-start
	dc.b	'XT',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'ASK_OFFS'
	dc.w	$a248
	dc.l	offset_number_text-start
	dc.b	'ET',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'BACK_SPA'
	dc.w	$a248
	dc.l	rub_out-start
	dc.b	'CE',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'CODING_T'
	dc.w	$a248
	dc.l	encoding_picture_text-start
	dc.b	'XT',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'COPY_COD'
	dc.w	$a248
	dc.l	stub_mover-start
	dc.b	'E2',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'CRH_LENG'
	dc.w	$a248
	dc.l	crunch_left-start
	dc.b	'HT',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'DECRUNCH'
	dc.w	$a248
	dc.l	picture_stub_text-start
	dc.b	'ER',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'DISK_EMP'
	dc.w	$a248
	dc.l	disk_empty_text-start
	dc.b	'TY',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'DTA_BUFF'
	dc.w	$a248
	dc.l	dta-start
	dc.b	'ER',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'GET_BIT2'
	dc.w	$a248
	dc.l	stub_depack_get_bits-start
	dc.b	'_2',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'GET_PICO'
	dc.w	$a248
	dc.l	ask_picture_offset-start
	dc.b	'FF',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'HELLO_TX'
	dc.w	$a248
	dc.l	stub_title_text-start
	dc.b	'T2',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'LARGER_T'
	dc.w	$a248
	dc.l	cannot_crunch_text-start
	dc.b	'XT',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'MAKE_TAB'
	dc.w	$a248
	dc.l	analyse_window-start
	dc.b	'LE',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'MARK_TAB'
	dc.w	$a148
	dc.l	$118
	dc.b	'LE',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'MULTI_FL'
	dc.w	$a248
	dc.l	batch-start
	dc.b	'AG',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'MULTI_PA'
	dc.w	$a248
	dc.l	crunch_all_menu-start
	dc.b	'CK',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'ORG_LENG'
	dc.w	$a248
	dc.l	crunch_length-start
	dc.b	'HT',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'OUT_MEMO'
	dc.w	$a248
	dc.l	out_of_memory_text-start
	dc.b	'RY',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'OUT_OF_M'
	dc.w	$a248
	dc.l	no_memory-start
	dc.b	'EM',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'PARAMS_E'
	dc.w	$a248
	dc.l	picture_parameters_text-start
	dc.b	'RR',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'PARAMS_T'
	dc.w	$a248
	dc.l	parameters_menu_text-start
	dc.b	'XT',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'PIC_NUMB'
	dc.w	$a248
	dc.l	picture_count-start
	dc.b	'ER',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'PRG_EXTE'
	dc.w	$a248
	dc.l	program_mask-start
	dc.b	'ND',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'PRINT_TI'
	dc.w	$a248
	dc.l	print_time-start
	dc.b	'ME',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'SAVE_HZ2'
	dc.w	$a248
	dc.l	read_start_time-start
	dc.b	'00',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'SET_PARA'
	dc.w	$a248
	dc.l	parameters_menu-start
	dc.b	'MS',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'TIME_SAV'
	dc.w	$a248
	dc.l	time_text-start
	dc.b	'ER',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'TXT_LENG'
	dc.w	$a248
	dc.l	picture_stub_text_length-start
	dc.b	'HT',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'WRITE_FI'
	dc.w	$a248
	dc.l	write_file-start
	dc.b	'LE',0,0,0,0,0,0,0,0,0,0,0,0    ; the rest of the name
	dc.b	'ASK_CLR_'
	dc.w	$a248
	dc.l	clear_parameters_text-start
	dc.b	'TXT',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'ASK_OFFS'
	dc.w	$a248
	dc.l	colon_text-start
	dc.b	'ET2',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'ASK_PIC_'
	dc.w	$a248
	dc.l	picture_number_text-start
	dc.b	'NUM',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'BACK_SPA'
	dc.w	$a248
	dc.l	backspaces_text-start
	dc.b	'CES',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'CALCUL_M'
	dc.w	$a248
	dc.l	put_literal_count-start
	dc.b	'ARK',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'CHANGE_C'
	dc.w	$a248
	dc.l	next_window-start
	dc.b	'ODE',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'CLEARED_'
	dc.w	$a248
	dc.l	parameters_cleared_text-start
	dc.b	'TXT',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'CLEAR_RI'
	dc.w	$a248
	dc.l	clear_to_end_text-start
	dc.b	'GHT',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'COPY_JNK'
	dc.w	$a248
	dc.l	stub_depack_literals_copy-start
	dc.b	'1_2',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'CRUNCH_L'
	dc.w	$a248
	dc.l	save_length_text-start
	dc.b	'ENG',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'DECRUNCH'
	dc.w	$a248
	dc.l	stub_text-start
	dc.b	'ER2',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'DECRUN_C'
	dc.w	$a248
	dc.l	picture_stub-start
	dc.b	'ODE',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'EXTENDS_'
	dc.w	$a248
	dc.l	extends_text-start
	dc.b	'TXT',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'FILE_NUM'
	dc.w	$a248
	dc.l	loaded_count-start
	dc.b	'BER',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'FILE_SEL'
	dc.w	$a248
	dc.l	choose_file-start
	dc.b	'ECT',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'HIDE_CUR'
	dc.w	$a248
	dc.l	hide_mouse-start
	dc.b	'SOR',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'LARGER_F'
	dc.w	$a248
	dc.l	not_crunched-start
	dc.b	'LAG',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'LENGHT_R'
	dc.w	$a248
	dc.l	file_length-start
	dc.b	'EAD',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'LENGHT_T'
	dc.w	$a248
	dc.l	offset_bit_counts-start
	dc.b	'ABL',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'LOAD_ADR'
	dc.w	$a148
	dc.l	$14396
	dc.b	'ESS',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'LOOK_LEN'
	dc.w	$a248
	dc.l	match_report-start
	dc.b	'GHT',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'NEXT_ADR'
	dc.w	$a248
	dc.l	next_report-start
	dc.b	'ESS',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'PACKED_C'
	dc.w	$a248
	dc.l	offset_steps-start
	dc.b	'ODE',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'PARAMS_E'
	dc.w	$a248
	dc.l	bad_offset_text-start
	dc.b	'RR2',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'SAVE_COL'
	dc.w	$a248
	dc.l	saved_palette-start
	dc.b	'ORS',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'SAVE_EXT'
	dc.w	$a248
	dc.l	file_mask-start
	dc.b	'END',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'SAVE_LEN'
	dc.w	$a248
	dc.l	save_length-start
	dc.b	'GHT',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'SHOW_CUR'
	dc.w	$a248
	dc.l	show_mouse-start
	dc.b	'SOR',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'SKIP_2LI'
	dc.w	$a248
	dc.l	new_lines_text-start
	dc.b	'NES',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'STRUCT_F'
	dc.w	$a248
	dc.l	make_name-start
	dc.b	'ILE',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'TAKE_LEN'
	dc.w	$a248
	dc.l	picture_stub_depack_unary-start
	dc.b	'GHT',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'TAKE_NUM'
	dc.w	$a248
	dc.l	input_number-start
	dc.b	'BER',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'TOP_PROG'
	dc.w	$a248
	dc.l	main_menu-start
	dc.b	'RAM',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'TXT_LENG'
	dc.w	$a248
	dc.l	stub_text_length-start
	dc.b	'HT2',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'WRITE_ER'
	dc.w	$a248
	dc.l	write_error_text-start
	dc.b	'ROR',0,0,0,0,0,0,0,0,0,0,0     ; the rest of the name
	dc.b	'ADRESS_T'
	dc.w	$a248
	dc.l	position_lists-start
	dc.b	'ABLE',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'COD_GRAP'
	dc.w	$a248
	dc.l	encode_picture-start
	dc.b	'HICS',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'CONTER_T'
	dc.w	$a248
	dc.l	position_index-start
	dc.b	'ABLE',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'CONT_PAK'
	dc.w	$a248
	dc.l	match_reach-start
	dc.b	'ITOS',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'CREATE_E'
	dc.w	$a248
	dc.l	write_file_done-start
	dc.b	'RROR',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'DECRUN_C'
	dc.w	$a248
	dc.l	stub-start
	dc.b	'ODE2',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'DECRUN_S'
	dc.w	$a148
	dc.l	$10118
	dc.b	'PACE',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'DECRUN_T'
	dc.w	$a248
	dc.l	picture_stub_offset_bases-start
	dc.b	'ABLE',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'LENGHT_T'
	dc.w	$a248
	dc.l	pair_offset_bit_counts-start
	dc.b	'ABL2',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'MEMORY_A'
	dc.w	$a248
	dc.l	init_memory-start
	dc.b	'LLOC',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'MULTI_CR'
	dc.w	$a248
	dc.l	batch_ok_text-start
	dc.b	'_END',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'OFFSET_S'
	dc.w	$a248
	dc.l	picture_offsets-start
	dc.b	'AVER',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'OFFSET_T'
	dc.w	$a248
	dc.l	offset_steps-start
	dc.b	'ABLE',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'OK_SAVED'
	dc.w	$a248
	dc.l	file_text-start
	dc.b	'_TXT',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'PACKED_C'
	dc.w	$a248
	dc.l	match_offset-start
	dc.b	'ODE2',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'PRINT_LE'
	dc.w	$a248
	dc.l	print_crunch_left-start
	dc.b	'NGHT',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'STARS_EX'
	dc.w	$a248
	dc.l	any_mask-start
	dc.b	'TEND',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'TABLUS_T'
	dc.w	$a248
	dc.l	picture_stub_common_bytes-start
	dc.b	'ABLE',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'TAKE_LEN'
	dc.w	$a248
	dc.l	stub_depack_unary-start
	dc.b	'GHT2',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'VALUE_BU'
	dc.w	$a248
	dc.l	hex_text+1-start
	dc.b	'FFER',0,0,0,0,0,0,0,0,0,0      ; the rest of the name
	dc.b	'CRUNCH_N'
	dc.w	$a248
	dc.l	packed_count-start
	dc.b	'UMBER',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'DECOD_PI'
	dc.w	$a248
	dc.l	picture_stub_pictures-start
	dc.b	'CTURE',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'DECRUN_S'
	dc.w	$a148
	dc.l	$1015e
	dc.b	'PACE2',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'DECRUN_T'
	dc.w	$a248
	dc.l	picture_stub_pair_offset_bases-start
	dc.b	'ABLE2',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'LOAD_AND'
	dc.w	$a248
	dc.l	crunch_file-start
	dc.b	'_PACK',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'MULTI_CR'
	dc.w	$a248
	dc.l	files_packed_text-start
	dc.b	'_END1',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'MULTI_CR'
	dc.w	$a248
	dc.l	batch_in_text-start
	dc.b	'_END2',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'MULTI_CR'
	dc.w	$a248
	dc.l	files_loaded_text-start
	dc.b	'_END3',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'OFFSET_T'
	dc.w	$a248
	dc.l	pair_offset_steps-start
	dc.b	'ABLE2',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'STRING_B'
	dc.w	$a248
	dc.l	hex_text-start
	dc.b	'UFFER',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'TABLUS_T'
	dc.w	$a248
	dc.l	stub_common_bytes-start
	dc.b	'ABLE2',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'TABLUS_T'
	dc.w	$a248
	dc.l	common_bytes-start
	dc.b	'ABLE3',0,0,0,0,0,0,0,0,0       ; the rest of the name
	dc.b	'DECRUN_T'
	dc.w	$a248
	dc.l	stub_offset_bases-start
	dc.b	'ABLE_2',0,0,0,0,0,0,0,0        ; the rest of the name
	dc.b	'RESTORE_'
	dc.w	$a248
	dc.l	restore_palette-start
	dc.b	'COLORS',0,0,0,0,0,0,0,0        ; the rest of the name
	dc.b	'DECRUN_T'
	dc.w	$a248
	dc.l	stub_pair_offset_bases-start
	dc.b	'ABLE2_2',0,0,0,0,0,0,0         ; the rest of the name

	section	bss
bss_end:

	end
