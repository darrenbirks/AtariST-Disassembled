; PACK2_31.PRG  -  Automation Packer 2.31 ("VERSION 2.31 ... AUTOMATION USE ONLY.  (P) 1989")
; Devpac source of the program, disassembled by Darren Birks, 11 November 2026.
; Text 5666 bytes, data 2 bytes, bss 0 bytes.
;
; PACK2_31.PRG as distributed is packed itself: a 4562 byte Automation packed program, with the stub of
; "AUTOMATION PACKER V2.3r" and 'LSD!' data.  This is the source of the 5847 byte program that stub depacks.
;
; This source rebuilds that unpacked program byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o PACK2_31.PRG PACK2_31.S
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; A text screen program: its menus are printed with VT52 codes and answered with keys, and the only AES call
; is the file selector.  It runs in supervisor mode from start to end.  The main menu has 1 PACK/DEPACK
; PROGRAM, 2 PACK/DEPACK DATA FILE, 3 MULTI-PACKER MENU, 4 PACK DATA FILE (OFFSET) and 5 EXIT PROGRAM.  A file
; that is packed already is depacked instead.  F1 (fast, big) to F10 (slow, small) sets how far the packer
; looks for strings, $10 to $1120 bytes.
;
; The packer, pack_file, is an LZ77 packer writing 'LSD!' data; Automation Packer 5.01 still carries it,
; unused.  A program gets program_stub in front, which depacks, relocates and runs it; data can get data_stub
; and the depacker in front, which depack it to a given address and jump to another ("PROGRAM FILE (y/n)").
; The multi file packer packs every file of the current folder, with or without programs.
;
; Some code is patched while it runs: the multi file packer makes program_stub silent (stub_clear_screen and
; stub_print_trap become nops), and SUPERVISOR MODE y makes data_stub_user_call a nop.  find_first_file puts
; the DTA at the fixed address $1000.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$0bb7  the program
;   $0bb8-$1239  its texts and variables
;   $123a-$156f  program_stub ("AUTOMATION PACKER V2.3r"), with lsd_depack
;   $1572-$1621  data_stub ("AUTOMATION PACKER V2.2f")
;   $1622        the data section: the word data_stub calls, where the depacker follows it in a file
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; Packed data: 'LSD!', the unpacked length, the packed length (counted from the unpacked length), then a bit
; stream that lsd_depack reads from the end down; the last word's top bit says a pad byte comes before it.
;
; Packed program: program_stub, $336 bytes (a PRG header with the stub as text and the packed data as data),
; then the packed data.
;
; Data program: data_stub ($b0 bytes), lsd_depack ($150 bytes), then the packed data.
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The program starts here, over its variables and notice.
;------------------------------------------------------------------------------
start:
	bra.s	main                            ; over the variables
dest_buffer:	; from: reset_buffers
	dc.l	$00020000                       ; where packed files are built
load_buffer:	; from: reset_buffers
	dc.l	$00028000                       ; where files are loaded
notice:
	dc.b	'CODED COPY. AUTOMATION (DON',$27,'T JEST WITH THE BEST!)    '

;------------------------------------------------------------------------------
; Start-up: hide the mouse and the cursor, shrink the memory, enter supervisor mode.
;------------------------------------------------------------------------------
main:	; from: start
	bsr.w	init                            ; the mouse, the cursor, the memory
	bsr.w	super_toggle                    ; supervisor mode

;------------------------------------------------------------------------------
; The main menu: 1 a program, 2 data, 3 the multi file packer, 4 data from an offset, 5 quit.
;------------------------------------------------------------------------------
main_menu:	; from: pack_one_file, save_file, multi_menu
	bsr.w	reset_buffers                   ; reset the buffers and the file type
	clr.b	packed_flag                     ; not packed
	lea	text_main_menu(pc),a4           ; the main menu
	bsr.w	show_menu                       ; show it and wait for a key
	cmp.b	#$31,d0                         ; '1'?
	beq.s	menu_program                    ; yes: a program
	cmp.b	#$32,d0                         ; '2'?
	beq.w	pack_one_file                   ; yes: data
	cmp.b	#$33,d0                         ; '3'?
	beq.w	multi_menu                      ; yes: the multi file packer
	cmp.b	#$34,d0                         ; '4'?
	beq.s	menu_offset                     ; yes: data from an offset
	cmp.b	#$35,d0                         ; '5'?
	bne.s	main_menu                       ; no: the menu again
	bsr.w	super_toggle                    ; back to user mode
	move.w	#$0,-(sp)
	trap	#1                              ; Pterm0
menu_offset:
	move.b	#$ff,offset_flag                ; from an offset
	bra.s	pack_one_file
menu_program:
	move.b	#$ff,program_flag               ; a program

;------------------------------------------------------------------------------
; Pack or depack one file: choose it, load it, then pack it, or depack it if it is packed already.
;------------------------------------------------------------------------------
pack_one_file:	; from: main_menu
	bsr.w	set_extension                   ; .PRG or .DAT on the selector's name
	bsr.w	file_selector                   ; fsel_input
	tst.w	fsel_ok                         ; OK clicked?
	beq.s	main_menu                       ; no: back to the menu
	bsr.w	show_title                      ; the title screen
	bsr.w	make_file_name                  ; make the path and file name
	movea.l	source_ptr,a6                   ; where to load it
	bsr.w	load_file                       ; load it
	cmp.l	#$0,d7                          ; anything loaded?
	bgt.s	file_loaded                     ; yes
	bsr.w	alert_load_error                ; no: "FILE DOES NOT EXIST OR HAS AN ERROR"
	bra.s	main_menu                       ; back to the menu
file_loaded:
	cmpi.b	#$ff,packed_flag                ; packed already?
	bne.s	pack_loaded                     ; no: pack it
	move.l	d7,packed_length                ; yes: its length
	cmpi.b	#$ff,program_flag               ; a program?
	bne.s	depack_loaded                   ; no
	addi.l	#$336,build_ptr                 ; yes: the packed data starts after the stub
depack_loaded:
	movea.l	build_ptr,a0                    ; the packed data
	movea.l	source_ptr,a1                   ; where it depacks to
	move.w	$ffff8240,saved_colour          ; palette 0, keep the background colour
	bsr.w	lsd_depack                      ; depack
	move.w	saved_colour,$ffff8240          ; palette 0, colour back
	move.l	d5,source_length                ; the depacked length
	bsr.w	show_original_size              ; "ORIGINAL SIZE"
	bsr.w	show_packed_size                ; "PACKED SIZE" and the percentage
	bsr.w	wait_key                        ; wait for a key
	bra.s	save_file                       ; save it
pack_loaded:
	move.l	d7,source_length                ; the length to pack
	bsr.w	show_original_size              ; "ORIGINAL SIZE"
	cmpi.b	#$ff,offset_flag                ; from an offset?
	bne.s	pack_choose_rate                ; no
	bsr.w	ask_offset                      ; yes: ask for it
pack_choose_rate:
	bsr.w	choose_rate                     ; F1-F10: the window
	bsr.w	pack_file                       ; pack
	cmpi.b	#$ff,program_flag               ; a program?
	bne.s	packed_data                     ; no
	bsr.w	add_program_stub                ; yes: the program stub in front
	bsr.w	show_packed_size                ; "PACKED SIZE" and the percentage
	bsr.w	wait_key                        ; wait for a key
	bra.s	save_file                       ; save it
packed_data:
	bsr.w	show_packed_size                ; "PACKED SIZE" and the percentage
	cmpi.b	#$ff,offset_flag                ; from an offset?
	bne.s	ask_data_to_program             ; no
	bsr.w	add_offset_data                 ; yes: the data before it in front
	bra.s	save_file                       ; save it
ask_data_to_program:
	bsr.w	data_to_program                 ; offer the data-to-program stub

;------------------------------------------------------------------------------
; Save: choose a name and write the file, the depacked one from the load buffer, a packed one from the build
; buffer.  A failed write asks again.
;------------------------------------------------------------------------------
save_file:	; from: pack_one_file
	bsr.w	file_selector                   ; fsel_input
	tst.w	fsel_ok                         ; OK clicked?
	beq.w	main_menu                       ; no: back to the menu
	bsr.w	show_title                      ; the title screen
	bsr.w	make_file_name                  ; make the path and file name
	cmpi.b	#$ff,packed_flag                ; depacked?
	bne.s	save_packed                     ; no
	move.l	source_ptr,d7                   ; yes: from the load buffer
	move.l	source_length,d6                ; its length
	bra.s	save_write
save_packed:
	move.l	build_ptr,d7                    ; the build buffer
	move.l	packed_length,d6                ; the packed length
save_write:
	bsr.w	write_file                      ; write it
	cmp.l	d6,d7                           ; all written?
	beq.w	main_menu                       ; yes: back to the menu
	bsr.w	alert_write_error               ; no: "WE APPEAR TO HAVE A SAVE FAILURE!"
	bra.s	save_file                       ; and choose again

;------------------------------------------------------------------------------
; The multi file packer: every file of the current folder is packed and saved under its own name.  1 packs
; programs too, 2 leaves files ending .PRG or .TOS alone.  The program stub is made silent first: it no
; longer clears the screen or prints its title (this stays for the rest of the run).
;------------------------------------------------------------------------------
multi_menu:	; from: main_menu
	move.w	#$4e71,stub_clear_screen        ; the stub does not clear the screen
	move.w	#$4e71,stub_print_trap          ; nor print its title
	move.b	#$0,multi_programs              ; not packing programs
	lea	text_multi_menu(pc),a4          ; the multi file menu
	bsr.w	show_menu                       ; show it and wait for a key
	cmp.b	#$31,d0                         ; '1'?
	beq.s	multi_all                       ; yes: programs too
	cmp.b	#$32,d0                         ; '2'?
	beq.s	multi_start                     ; yes: data only
	cmp.b	#$33,d0                         ; '3'?
	beq.w	main_menu                       ; yes: the main menu
	bra.s	multi_menu                      ; no: the menu again
multi_all:
	move.b	#$ff,multi_programs             ; programs too
multi_start:
	bsr.w	multi_title                     ; its title
	bsr.w	find_first_file                 ; the first file
	bsr.w	choose_rate                     ; F1-F10: the window
multi_next_file:
	bsr.w	reset_buffers                   ; reset the buffers and the file type
	bsr.w	found_name                      ; the found name to the selector's
	bsr.w	make_file_name                  ; make the path and file name
	movea.l	source_ptr,a6                   ; where to load it
	bsr.w	load_file                       ; load it
	move.l	d7,source_length                ; the length to pack
	cmpi.b	#$ff,packed_flag                ; packed already?
	bne.s	multi_check_loaded              ; no
	lea	text_already_packed(pc),a0      ; yes: "FILE IS ALREADY PACKED!!"
	bsr.w	print
	bsr.w	pause
	bra.w	multi_skip                      ; next file
multi_check_loaded:
	cmp.l	#$0,d7                          ; anything loaded?
	bgt.s	multi_check_program             ; yes
	bsr.w	alert_load_error                ; no: "FILE DOES NOT EXIST OR HAS AN ERROR"
	bra.w	multi_skip                      ; next file
multi_check_program:
	bsr.w	check_program_name              ; a .PRG or .TOS name?
	cmpi.b	#$ff,multi_programs             ; packing programs?
	beq.s	multi_pack_file                 ; yes
	cmpi.b	#$ff,program_flag               ; a program?
	bne.s	multi_pack_file                 ; no
	lea	text_not_compacted(pc),a0       ; yes: "PROGRAM FILE - NOT COMPACTED"
	bsr.w	print
	bsr.w	pause
	bra.s	multi_skip                      ; next file
multi_pack_file:
	bsr.w	show_original_size              ; "ORIGINAL SIZE"
	bsr.w	pack_file                       ; pack
	cmpi.b	#$ff,program_flag               ; a program?
	bne.s	multi_packed_data               ; no
	bsr.w	add_program_stub                ; yes: the program stub in front
	bsr.w	show_packed_size                ; "PACKED SIZE" and the percentage
	bra.s	multi_save
multi_packed_data:
	bsr.w	show_packed_size                ; "PACKED SIZE" and the percentage
multi_save:
	bsr.w	found_name                      ; the found name to the selector's again
	move.l	build_ptr,d7                    ; the build buffer
	move.l	packed_length,d6                ; the packed length
	cmp.l	source_length,d6                ; shorter than the file?
	blt.w	multi_write                     ; yes: save it
	lea	text_got_larger(pc),a0          ; no: "FILE HAS GOT LARGER!!"
	bsr.w	print
	bsr.w	pause
	bra.s	multi_skip                      ; next file
multi_write:
	bsr.w	write_file                      ; write it
	cmp.l	packed_length,d7                ; all written?
	beq.w	multi_skip                      ; yes: next file
	bsr.w	alert_write_error               ; no: "WE APPEAR TO HAVE A SAVE FAILURE!"
	bra.w	multi_menu                      ; and back to the multi file menu
multi_skip:
	bsr.s	show_title                      ; the title screen
	bsr.w	find_next_file                  ; the next file
	cmp.b	#$0,d0                          ; found?
	beq.w	multi_next_file                 ; yes: pack it
	lea	text_multi_done(pc),a0          ; no: "MULTI-FILE PACKER COMPLETE!!"
	bsr.w	print
	bsr.w	wait_key                        ; wait for a key
	bra.w	multi_menu                      ; the multi file menu again

;------------------------------------------------------------------------------
; The title screen and the menu at a4, then wait for a key.
;------------------------------------------------------------------------------
show_menu:	; from: main_menu, multi_menu
	bsr.s	show_title                      ; the title screen
	movea.l	a4,a0                           ; the menu
	bsr.w	print
	bsr.w	wait_key                        ; wait for a key
	rts

;------------------------------------------------------------------------------
; Clear the screen and print the title.
;------------------------------------------------------------------------------
show_title:	; from: pack_one_file, save_file, multi_menu, show_menu, multi_title
	lea	text_title(pc),a0               ; "VERSION 2.31 ... AUTOMATION USE ONLY."
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; Hide the mouse and the cursor, shrink the memory to the program.
;------------------------------------------------------------------------------
init:	; from: main
	dc.w	$a00a                           ; Line-A $a, hide the mouse
	move.l	#$2,-(sp)                       ; Cursconf(0, 2): hide the cursor
	move.w	#$15,-(sp)
	trap	#14                             ; Cursconf
	addq.l	#6,sp
	movea.l	sp,a5                           ; the stack
	movea.l	8(a5),a5                        ; a5 = the basepage, one level up
	move.l	$c(a5),d0                       ; the text length
	addi.l	#$100,d0                        ; + the basepage
	move.l	d0,-(sp)                        ; Mshrink(0, basepage, length)
	move.l	a5,-(sp)
	move.l	#$4a0000,-(sp)                  ; function $4a and the 0 word
	trap	#1                              ; Mshrink
	adda.l	#$c,sp
	rts

;------------------------------------------------------------------------------
; Super(0): into supervisor mode at the start, back to user mode at the end.
;------------------------------------------------------------------------------
super_toggle:	; from: main, main_menu
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; Reset for a new file: the build pointer to dest_buffer, nothing packed, the source to load_buffer, data, no
; offset, not packed.
;------------------------------------------------------------------------------
reset_buffers:	; from: main_menu, multi_menu
	move.l	dest_buffer,build_ptr           ; the build pointer
	move.l	#$0,packed_length               ; no packed length
	move.l	load_buffer,source_ptr          ; the source
	move.b	#$0,program_flag                ; data
	clr.b	offset_flag                     ; no offset
	clr.l	offset_length                   ; no offset length
	move.b	#$0,packed_flag                 ; not packed
	rts

;------------------------------------------------------------------------------
; The multi file packer's title line for the chosen mode.
;------------------------------------------------------------------------------
multi_title:	; from: multi_menu
	bsr.w	show_title                      ; the title screen
	cmpi.b	#$ff,multi_programs             ; programs too?
	bne.s	multi_title_data                ; no
	lea	text_multi_all(pc),a0           ; "* MULTI-FILE PACKER (DATA + PRG) *"
	bra.s	multi_title_print
multi_title_data:
	lea	text_multi_data(pc),a0          ; "* MULTI-FILE PACKER  (DATA ONLY) *"
multi_title_print:
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; fsel_input on fsel_path and fsel_name, with the mouse shown; fsel_ok is nonzero for OK.
;------------------------------------------------------------------------------
file_selector:	; from: pack_one_file, save_file
	move.l	#fsel_control,fsel_control_ptr  ; control
	move.l	#fsel_global,fsel_global_ptr    ; global
	move.l	#fsel_intin,fsel_intin_ptr      ; intin
	move.l	#fsel_intout,fsel_intout_ptr    ; intout
	move.l	#fsel_addrin,fsel_addrin_ptr    ; addrin: the path and the name
	move.l	#fsel_addrout,fsel_addrout_ptr  ; addrout
	dc.w	$a009                           ; Line-A $9, show the mouse
	move.l	#fsel_control_ptr,d1            ; the parameter block
	move.l	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	dc.w	$a00a                           ; Line-A $a, hide the mouse
	rts

;------------------------------------------------------------------------------
; file_name = the selector's path up to its last \, then its name.
;------------------------------------------------------------------------------
make_file_name:	; from: pack_one_file, save_file, multi_menu
	lea	fsel_path,a0                    ; the selector's path
	lea	file_name,a1                    ; the full name
	moveq	#54,d7                          ; at most 55 characters back
copy_path:
	move.b	(a0)+,d0                        ; a character
	beq.s	find_backslash                  ; to the end of the path
	move.b	d0,(a1)+                        ; copy it
	bra.s	copy_path
find_backslash:
	movea.l	a1,a2                           ; the end
find_backslash_loop:
	move.b	-(a1),d2                        ; back a character
	cmp.b	#$5c,d2                         ; the \?
	beq.s	path_done                       ; yes
	dbra	d7,find_backslash_loop          ; no: on back
	movea.l	a2,a1                           ; none: the end
path_done:
	move.b	#$5c,(a1)+                      ; the \
	lea	fsel_name,a0                    ; the selector's name
copy_name:
	move.b	(a0)+,d0                        ; a character
	beq.s	copy_name_done                  ; to the end
	move.b	d0,(a1)+                        ; copy it
	bra.s	copy_name
copy_name_done:
	clr.b	(a1)+                           ; end it
	rts

;------------------------------------------------------------------------------
; Show the file's name and "LOADING", load file_name to a6.  d7 = the length read.  A packed file ('LSD!' at the
; start, or after the $336 byte stub for a program) is copied to the build buffer and packed_flag set.  d7 = 0
; for a program that is not a program file.
;------------------------------------------------------------------------------
load_file:	; from: pack_one_file, multi_menu
	lea	text_file_line(pc),a0           ; "CURRENT FILE IS ..."
	bsr.w	print
	lea	text_loading(pc),a0             ; "LOADING......."
	bsr.w	print
	move.w	#$0,-(sp)                       ; read only
	pea	file_name                       ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.w	d0,d6                           ; d6 = the handle
	move.l	a6,-(sp)                        ; to a6
	move.l	#$fffff,-(sp)                   ; up to 1 MB
	move.w	d6,-(sp)
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	adda.l	#$c,sp
	move.l	d0,d7                           ; d7 = the length
	move.w	d6,-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	cmpi.b	#$ff,program_flag               ; a program?
	bne.s	load_check_data                 ; no
	cmpi.w	#$601a,(a6)                     ; a program file?
	bne.s	load_not_program                ; no: not usable
	cmpi.l	#$4c534421,$336(a6)             ; 'LSD!' after the stub?
	beq.s	load_packed                     ; yes: packed
	bra.s	load_file_done                  ; no: pack it
load_check_data:
	cmpi.l	#$4c534421,(a6)                 ; 'LSD!'?
	bne.s	load_file_done                  ; no: pack it
load_packed:
	move.b	#$ff,packed_flag                ; packed
	move.l	d7,d0                           ; the length
	movea.l	source_ptr,a0                   ; the loaded file
	movea.l	build_ptr,a1                    ; the build buffer
copy_packed_file:
	move.b	(a0)+,(a1)+                     ; copy it
	dbra	d0,copy_packed_file             ; 64 K at a time
	subi.l	#$10000,d0
	bpl.s	copy_packed_file
	bra.s	load_file_done
load_not_program:
	clr.l	d7                              ; not usable
load_file_done:
	rts

;------------------------------------------------------------------------------
; "FILE DOES NOT EXIST OR HAS AN ERROR", then wait for a key.
;------------------------------------------------------------------------------
alert_load_error:	; from: pack_one_file, multi_menu
	lea	text_load_error(pc),a0
	bsr.w	print
	bsr.w	wait_key                        ; wait for a key
	rts

;------------------------------------------------------------------------------
; Data from an offset: the data before the offset (read in hex) is left unpacked and the rest packed.  An
; offset past the end is ignored.
;------------------------------------------------------------------------------
ask_offset:	; from: pack_one_file
	lea	text_enter_offset(pc),a0        ; "ENTER OFFSET $"
	bsr.w	print
	bsr.w	read_hex                        ; read it to d2
	cmp.l	source_length,d2                ; past the end?
	bgt.s	ask_offset_done                 ; yes: ignore it
	move.l	d2,offset_length                ; the offset
	add.l	d2,source_ptr                   ; the source starts there
	sub.l	d2,source_length                ; and is that much shorter
ask_offset_done:
	rts

;------------------------------------------------------------------------------
; After packing from an offset: the packed data goes behind the unpacked data in the load buffer, and the file
; starts at the unpacked data.
;------------------------------------------------------------------------------
add_offset_data:	; from: pack_one_file
	move.l	offset_length,d1                ; the offset
	movea.l	build_ptr,a0                    ; the packed data
	movea.l	source_ptr,a1                   ; behind the unpacked data
	move.l	packed_length,d0                ; its length
copy_behind_offset:
	move.b	(a0)+,(a1)+                     ; copied
	dbra	d0,copy_behind_offset           ; 64 K at a time
	subi.l	#$10000,d0
	bpl.s	copy_behind_offset
	move.l	source_ptr,build_ptr            ; the file
	sub.l	d1,build_ptr                    ; starts at the unpacked data
	add.l	d1,packed_length                ; and is that much longer
	rts

;------------------------------------------------------------------------------
; The packer: source_ptr/source_length to build_ptr as 'LSD!', the unpacked length, the packed length, then a
; bit stream lsd_depack reads from the end down.  At each position it looks up to search_window bytes ahead for
; the longest string equal to the one here (up to $3ff), and writes literal counts, offsets and lengths as
; variable-length codes.  The percentage done is shown as it goes.
;------------------------------------------------------------------------------
pack_file:	; from: pack_one_file, multi_menu
	move.w	$ffff8240,saved_colour          ; palette 0, keep the background colour
	move.w	#$3030,percent_digits           ; "00" percent
	lea	text_amount_packed(pc),a0       ; "AMOUNT ALREADY PACKED = %"
	bsr.w	print
	move.l	source_length,d0                ; the length
	movea.l	source_ptr,a0                   ; the source
	lea	0(a0,d0.l),a2                   ; a2 = its end
	movea.l	build_ptr,a1                    ; the build buffer
	addq.l	#8,a1                           ; past its 8 byte header
	clr.w	d5                              ; no literals yet
	moveq	#7,d6                           ; 8 bits to the byte
pack_loop:
	bsr.w	show_percent                    ; show the percentage
	move.b	(a0),d0                         ; the byte to match
	move.w	#$1,best_length                 ; best match 1
	moveq	#1,d1                           ; offset 1
	move.l	search_window,d2                ; the window
pack_search:
	cmp.b	0(a0,d1.w),d0                   ; the same first byte?
	bne.s	pack_search_next                ; no: on
	movem.l	d0/a0-a3,-(sp)
	clr.w	d0                              ; the match's length
	lea	0(a0,d1.w),a1                   ; the other string
	movea.l	a1,a3                           ; where it starts
pack_compare:
	cmpm.b	(a0)+,(a1)+                     ; the same?
	bne.s	pack_compare_done               ; no
	cmpa.l	a2,a1                           ; past the end?
	bhi.s	pack_compare_done               ; yes
	cmpa.l	a3,a0                           ; into the other string?
	bhi.s	pack_compare_done               ; yes
	addq.w	#1,d0                           ; one longer
	cmpi.w	#$3ff,d0                        ; at most $3ff
	bne.s	pack_compare
pack_compare_done:
	cmp.w	best_length(pc),d0              ; longer than the best?
	ble.s	pack_match_restore              ; no
	move.w	d0,best_length                  ; yes: the best
	move.w	d1,best_offset                  ; and its offset
pack_match_restore:
	movem.l	(sp)+,d0/a0-a3
pack_search_next:
	addq.w	#1,d1                           ; the next offset
	lea	0(a0,d1.w),a3
	cmpa.l	a2,a3                           ; past the end?
	dbeq	d2,pack_search                  ; on through the window
	move.w	best_offset(pc),d0              ; the best offset
	move.w	best_length(pc),d1              ; the best length
	sub.w	d1,d0                           ; the code's offset
	cmpi.w	#$1,d1                          ; 1: a literal
	beq.s	pack_literal
	cmpi.w	#$2,d1                          ; 2?
	beq.s	pack_short
	bsr.w	put_literal_count               ; the literals before it
	bsr.w	put_offset                      ; the offset
	bra.s	pack_length
pack_short:
	cmpi.w	#$23f,d0                        ; offset too large?
	bhi.s	pack_literal                    ; yes: a literal
	bsr.w	put_literal_count               ; the literals before it
	bsr.w	put_short_offset                ; the short offset
pack_length:
	bsr.w	put_length                      ; the length
	moveq	#0,d5                           ; no literals
	move.w	best_length(pc),d0              ; skip the matched bytes
	lea	0(a0,d0.w),a0
	bra.w	pack_next
pack_literal:	; from: put_short_offset
	move.b	(a0)+,(a1)+                     ; copy a literal
	addq.w	#1,d5                           ; count it
pack_next:
	lea	-$1(a2),a3                      ; the last byte
	cmpa.l	a0,a3                           ; reached?
	bne.w	pack_loop                       ; no: on
	move.b	(a0)+,(a1)+                     ; the last byte as a literal
	addq.w	#1,d5
	bsr.w	put_literal_count               ; the literals
	bset	d6,d7                           ; end marker bit
	move.b	d7,(a1)+                        ; the last bits
	clr.w	d1
	move.l	a1,d0                           ; the build pointer
	lsr.l	#1,d0                           ; odd?
	bcc.s	pack_end                        ; no
	addq.w	#1,a1                           ; yes: a pad byte
	bset	#$f,d1                          ; and flag it
pack_end:
	move.w	d1,(a1)+                        ; the pad flag word
	movea.l	build_ptr,a0                    ; the header
	move.l	source_length,(a0)              ; the unpacked length
	clr.l	(a1)
	clr.l	4(a1)
	suba.l	a0,a1
	move.l	a1,4(a0)                        ; the packed length
	move.l	a1,packed_length
	subq.l	#4,build_ptr                    ; 4 bytes earlier
	move.l	#$4c534421,-$4(a0)              ; 'LSD!'
	addq.l	#4,packed_length
pack_done:	; from: put_length
	move.w	saved_colour,$ffff8240          ; palette 0, the background colour back
	rts

;------------------------------------------------------------------------------
; The code writers: each sets d1 = the bits and d4 = their count - 1 and goes to put_bits.
;------------------------------------------------------------------------------
put_literal_count:	; from: pack_file
	lea	literal_table(pc),a3            ; the literal count table
	moveq	#5,d3
literal_range:
	move.b	0(a3,d3.w),d4
	ext.w	d4
	cmp.w	d4,d5                           ; in this range?
	dbge	d3,literal_range                ; no: the one below
	sub.w	d4,d5                           ; less its start
	lsl.w	#1,d3
	move.b	6(a3,d3.w),d2                   ; the bits for it
	ext.w	d2
	moveq	#-1,d1
	lsl.l	d2,d1                           ; the prefix ones
	or.w	d5,d1                           ; the count
	clr.w	d4
	move.b	7(a3,d3.w),d4                   ; the bit count
	bra.w	put_bits                        ; write them
literal_table:
	dc.w	$0001,$0205,$080f,$0100,$0101,$0203,$0205,$0308 ; range starts, then prefix length and bit count
	dc.w	$0a12

put_offset:	; from: pack_file
	lea	offset_table(pc),a3             ; the offset table
	moveq	#2,d3
offset_range:
	lsl.w	#1,d3
	move.w	0(a3,d3.w),d4
	lsr.w	#1,d3
	cmp.w	d4,d0                           ; in this range?
	dbge	d3,offset_range                 ; no: the one below
	sub.w	d4,d0                           ; less its start
	lsl.w	#1,d3
	move.w	6(a3,d3.w),d3                   ; bits and prefix
	move.w	d3,d4
	lsr.w	#8,d3                           ; the prefix length
	moveq	#-1,d1
	lsl.w	d3,d1
	or.w	d0,d1                           ; the offset
	andi.w	#$f,d4                          ; the bit count
	bra.w	put_bits                        ; write them
offset_table:
	dc.w	$0000,$0020,$0120,$0606,$0908,$0c0d ; range starts, then prefix length and bit count

put_short_offset:	; from: pack_file
	cmpi.w	#$23f,d0                        ; too large?
	bhi.w	pack_literal                    ; yes: a literal
	move.w	d0,d1
	cmpi.w	#$3f,d1                         ; 6 bits?
	ble.s	short_offset_6                  ; yes
	subi.w	#$40,d1                         ; no: 9 bits
	moveq	#9,d4
	bset	d4,d1                           ; and a 1
	bra.w	put_bits                        ; write them
short_offset_6:
	move.w	#$6,d4                          ; 6 bits + the 0
	bra.w	put_bits                        ; write them
length_table:	; from: put_length
	dc.b	$02,$03,$04,$06,$0a,$01,$01,$02,$03,$0a ; range starts, then bit counts

put_length:	; from: pack_file
	lea	length_table(pc),a3             ; the length table
	move.w	best_length(pc),d0              ; the length
	moveq	#4,d5
length_range:
	move.b	0(a3,d5.w),d4
	ext.w	d4
	cmp.w	d4,d0                           ; in this range?
	dbge	d5,length_range                 ; no: the one below
	sub.w	d4,d0                           ; less its start
	move.b	5(a3,d5.w),d4                   ; its bits
	ext.w	d4
	moveq	#-1,d1
	lsl.w	d4,d1                           ; the prefix
	add.w	d5,d4
	subq.w	#1,d4
	or.w	d0,d1                           ; the length
put_bits:	; from: put_literal_count, put_offset, put_short_offset
	lsr.l	#1,d1                           ; a bit
	roxr.b	#1,d7                           ; into the byte
	dbra	d6,put_bits_next                ; full?
	move.b	d7,(a1)+                        ; yes: write it
	clr.w	d7
	moveq	#7,d6
put_bits_next:
	dbra	d4,put_bits                     ; for each bit
	bra.w	pack_done
best_length:	; from: pack_file
	dc.w	$0000,$0000
best_offset:	; from: pack_file
	dc.w	$0000,$0000

;------------------------------------------------------------------------------
; Print the percentage done when it changes.
;------------------------------------------------------------------------------
show_percent:	; from: pack_file
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	move.l	source_ptr,d0                   ; the source
	suba.l	d0,a0                           ; done
	suba.l	d0,a2                           ; the end
	move.l	a0,d0
	move.l	a2,d1
	bsr.w	percent                         ; the percentage
	cmp.b	last_percent,d6                 ; changed?
	beq.s	show_percent_done               ; no
	move.b	d6,last_percent                 ; yes: keep it
	lea	percent_position(pc),a0         ; the percentage at its place
	bsr.w	print
show_percent_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts
last_percent:
	dc.w	$0000                           ; the percentage last shown

;------------------------------------------------------------------------------
; Put .PRG (a program) or .DAT on the selector's name, after its last dot or at its end.
;------------------------------------------------------------------------------
set_extension:	; from: pack_one_file
	lea	fsel_name,a0                    ; the selector's name
	moveq	#3,d0                           ; up to 4 back
find_name_end:
	tst.b	(a0)                            ; the end?
	beq.s	find_extension                  ; yes
	adda.l	#$1,a0
	bra.s	find_name_end
find_extension:
	movea.l	a0,a2                           ; the end
find_dot:
	move.b	-(a0),d2                        ; back a character
	cmp.b	#$2e,d2                         ; the dot?
	beq.s	write_extension                 ; yes
	dbra	d0,find_dot                     ; no: on back
	movea.l	a2,a0                           ; none: at the end
write_extension:
	move.b	#$2e,(a0)+                      ; .
	cmpi.b	#$ff,program_flag               ; a program?
	bne.s	extension_dat                   ; no
	move.b	#$50,(a0)+                      ; P
	move.b	#$52,(a0)+                      ; R
	move.b	#$47,(a0)+                      ; G
	bra.s	extension_done
extension_dat:
	move.b	#$44,(a0)+                      ; D
	move.b	#$41,(a0)+                      ; A
	move.b	#$54,(a0)+                      ; T
extension_done:
	clr.b	(a0)+                           ; end it
	rts

;------------------------------------------------------------------------------
; Put the $336 byte program stub (program_stub, a PRG header and its depacker) in front of the packed data,
; with the packed length as the header's data length.
;------------------------------------------------------------------------------
add_program_stub:	; from: pack_one_file, multi_menu
	move.l	#$336,d0                        ; the stub's length
	sub.l	d0,build_ptr                    ; in front of the data
	move.l	packed_length,program_stub_data_length ; the packed length is the header's data length
	add.l	d0,packed_length                ; the file is that much longer
	addq.l	#4,packed_length                ; and 4 more
	movea.l	build_ptr,a1                    ; where it goes
	lea	program_stub,a0                 ; the stub
	subq.l	#1,d0
copy_program_stub:
	move.b	(a0)+,(a1)+                     ; copy it
	dbra	d0,copy_program_stub
	rts

;------------------------------------------------------------------------------
; Fsfirst "*.*" with the DTA at $1000.
;------------------------------------------------------------------------------
find_first_file:	; from: multi_menu
	pea	$1000                           ; the DTA
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.l	#6,sp
	move.w	#$0,-(sp)                       ; normal files
	move.l	#search_mask,-(sp)              ; "*.*"
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	rts

;------------------------------------------------------------------------------
; A file found ending .PRG or .TOS is a program.
;------------------------------------------------------------------------------
check_program_name:	; from: multi_menu
	lea	$101e,a0                        ; the DTA's name
	moveq	#4,d0                           ; 5 characters
find_found_end:
	tst.b	(a0)+                           ; the end?
	beq.s	find_found_dot                  ; yes
	bra.s	find_found_end
find_found_dot:
	move.b	-(a0),d2                        ; back a character
	cmp.b	#$2e,d2                         ; the dot?
	beq.s	found_extension                 ; yes
	dbra	d0,find_found_dot               ; no: on back
	bra.s	check_program_name_done         ; no extension
found_extension:
	addq.l	#1,a0                           ; the extension
	cmpi.b	#$50,(a0)                       ; P?
	beq.s	found_extension_p               ; yes
	cmpi.b	#$54,(a0)                       ; T?
	bne.s	check_program_name_done         ; no
	cmpi.b	#$4f,1(a0)                      ; O?
	bne.s	check_program_name_done         ; no
	cmpi.b	#$53,2(a0)                      ; S?
	bne.s	check_program_name_done         ; no
found_is_program:
	move.b	#$ff,program_flag               ; a program
	bra.s	check_program_name_done
found_extension_p:
	cmpi.b	#$52,1(a0)                      ; R?
	bne.s	check_program_name_done         ; no
	cmpi.b	#$47,2(a0)                      ; G?
	beq.s	found_is_program                ; yes
check_program_name_done:
	rts

;------------------------------------------------------------------------------
; Fsnext: d0 = 0 when another file was found, $ff when not.
;------------------------------------------------------------------------------
find_next_file:	; from: multi_menu
	move.w	#$4f,-(sp)
	trap	#1                              ; Fsnext
	addq.l	#2,sp
	tst.l	d0                              ; found?
	bmi.s	no_next_file                    ; no
	moveq	#0,d0                           ; yes
	bra.s	find_next_file_done
no_next_file:
	move.b	#$ff,d0                         ; none
find_next_file_done:
	rts

;------------------------------------------------------------------------------
; Copy the name Fsfirst/Fsnext found into fsel_name.
;------------------------------------------------------------------------------
found_name:	; from: multi_menu
	lea	$101e,a0                        ; the DTA's name
	lea	fsel_name(pc),a1                ; the selector's name
	move.w	#$d,d0                          ; 14 bytes
copy_found_name:
	move.b	(a0)+,(a1)+                     ; copied
	dbra	d0,copy_found_name
	rts

;------------------------------------------------------------------------------
; Print "SAVING" and write d7 bytes from d6 to file_name.  d7 = the length written.
;------------------------------------------------------------------------------
write_file:	; from: save_file, multi_menu
	lea	text_saving(pc),a0              ; "SAVING....."
	bsr.w	print
	move.w	#$0,-(sp)                       ; normal file
	pea	file_name                       ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	move.w	d0,d5                           ; d5 = the handle
	move.l	d7,-(sp)                        ; the data
	move.l	d6,-(sp)                        ; the length
	move.w	d5,-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	adda.l	#$c,sp
	move.l	d0,d7                           ; d7 = what was written
	move.w	d5,-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	rts

;------------------------------------------------------------------------------
; "WE APPEAR TO HAVE A SAVE FAILURE!", then wait for a key.
;------------------------------------------------------------------------------
alert_write_error:	; from: save_file, multi_menu
	lea	text_write_error(pc),a0
	bsr.w	print
	bsr.w	wait_key                        ; wait for a key
	rts

;------------------------------------------------------------------------------
; "FILE IS INCORRECT PACK TYPE!", then wait for a key.  Nothing calls it.
;------------------------------------------------------------------------------
unused_alert_type:
	lea	text_wrong_type(pc),a0
	bsr.w	print
	bsr.w	wait_key                        ; wait for a key
	rts

;------------------------------------------------------------------------------
; "ORIGINAL SIZE: $xxxxx BYTES LONG".
;------------------------------------------------------------------------------
show_original_size:	; from: pack_one_file, multi_menu
	move.l	source_length(pc),d0            ; the length
	lea	original_size_digits(pc),a0     ; the digits
	bsr.w	hex_digits                      ; in hex
	lea	text_original_size(pc),a0       ; the line
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; "PACKED SIZE: $xxxxx BYTES LONG", "HIT A KEY!" and the percentage of the original size.
;------------------------------------------------------------------------------
show_packed_size:	; from: pack_one_file, multi_menu
	move.l	packed_length(pc),d0            ; the packed length
	move.l	source_length(pc),d1            ; the length
	bsr.w	percent                         ; the percentage
	move.l	packed_length(pc),d0            ; the packed length
	lea	packed_size_digits(pc),a0       ; the digits
	bsr.w	hex_digits                      ; in hex
	lea	text_packed_size(pc),a0         ; the lines
	bsr.w	print
	lea	percent_digits(pc),a0           ; the percentage
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; Cnecin: wait for a key.
;------------------------------------------------------------------------------
wait_key:                                       ; from: pack_one_file, multi_menu, show_menu, alert_load_error,
                                                ;   alert_write_error, unused_alert_type, 2 more
	move.w	#$8,-(sp)
	trap	#1                              ; Cnecin
	addq.l	#2,sp
	rts

;------------------------------------------------------------------------------
; A pause of $60000 loops, after a message about a skipped file.
;------------------------------------------------------------------------------
pause:	; from: multi_menu
	move.l	#$60000,d0
pause_loop:
	subq.l	#1,d0
	cmp.l	#$0,d0
	bne.s	pause_loop
	rts

;------------------------------------------------------------------------------
; Cconws(a0).
;------------------------------------------------------------------------------
print:	; from: multi_menu, show_menu, show_title, multi_title, load_file, alert_load_error, 10 more
	move.l	a0,-(sp)                        ; the string
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; Write d0 as 5 hex digits at a0.
;------------------------------------------------------------------------------
hex_digits:	; from: show_original_size, show_packed_size
	move.l	#$10000,d1                      ; the top digit's value
hex_digit:
	clr.b	(a0)                            ; the digit starts at 0
hex_count:
	cmp.l	d1,d0                           ; below the value?
	bmi.s	hex_digit_done                  ; yes: done
	addq.b	#1,(a0)                         ; count it
	sub.l	d1,d0
	bra.s	hex_count
hex_digit_done:
	move.b	(a0),d2                         ; the digit
	cmp.b	#$a,d2                          ; 0-9?
	bmi.s	hex_to_char                     ; yes
	addi.b	#$7,d2                          ; no: A-F
hex_to_char:
	addi.b	#$30,d2                         ; to a character
	move.b	d2,(a0)+
	lsr.l	#4,d1                           ; the next digit
	tst.l	d1                              ; any?
	bne.s	hex_digit                       ; yes
	rts

;------------------------------------------------------------------------------
; percent_digits = d0 * 100 / d1 as two digits ("XX" when over 99 or d0 > d1); d6 = the percentage.
;------------------------------------------------------------------------------
percent:	; from: show_percent, show_packed_size
	cmp.l	d0,d1                           ; over 100%?
	blt.w	percent_too_large               ; yes: XX
	move.l	d0,d2
	lsl.l	#2,d0                           ; * 4
	lsl.l	#5,d2                           ; * 32
	add.l	d2,d0                           ; * 36
	lsl.l	#1,d2                           ; * 64
	add.l	d2,d0                           ; * 100
percent_scale:
	btst	#$0,d1                          ; d1 odd?
	bne.s	percent_fit                     ; yes
	tst.l	d0                              ; nothing left?
	beq.s	percent_done                    ; yes: done
	lsr.l	#1,d0                           ; halve both
	lsr.l	#1,d1
	bra.s	percent_scale
percent_fit:
	cmp.l	#$ffff,d1                       ; d1 fits a word?
	bmi.s	percent_divide                  ; yes
	lsr.l	#1,d0                           ; no: halve both
	lsr.l	#1,d1
	tst.l	d0                              ; nothing left?
	beq.s	percent_done                    ; yes: done
	bra.s	percent_fit
percent_divide:
	divu.w	d1,d0                           ; the percentage
	ext.l	d0
	move.b	d0,d6                           ; d6 = it
	move.w	#$3030,percent_digits           ; "00"
percent_count:
	cmp.b	#$0,d0                          ; counted?
	beq.s	percent_done                    ; yes
	subq.b	#1,d0
	addq.b	#1,percent_digits+1             ; units + 1
	cmpi.b	#$3a,percent_digits+1           ; past 9?
	bne.s	percent_count                   ; no
	cmpi.b	#$39,percent_digits             ; tens 9 already?
	beq.s	percent_too_large               ; yes: XX
	move.b	#$30,percent_digits+1           ; units 0
	addq.b	#1,percent_digits               ; tens + 1
	bra.s	percent_count
percent_too_large:
	move.w	#$5858,percent_digits           ; "XX"
percent_done:
	rts

;------------------------------------------------------------------------------
; "SELECT: F1=FAST/BIG to F10=SLOW/SMALL": the function key sets the search window.
;------------------------------------------------------------------------------
choose_rate:	; from: pack_one_file, multi_menu
	lea	text_choose_rate,a0             ; the prompt
	bsr.w	print
choose_rate_key:
	bsr.w	wait_key                        ; a key
	swap	d0                              ; the scan code
	subi.b	#$3b,d0                         ; F1-F10 to 0-9
	bmi.s	choose_rate_key                 ; below F1: again
	cmp.b	#$a,d0
	bpl.s	choose_rate_key                 ; above F10: again
	andi.l	#$f,d0
	lsl.w	#1,d0                           ; words
	lea	window_sizes(pc),a0             ; the window sizes
	move.w	0(a0,d0.w),search_window+2      ; this one
	rts

;------------------------------------------------------------------------------
; After packing data: PROGRAM FILE (y/n)?  y asks for the decompact and execute addresses and whether to stay
; in supervisor mode, then puts the data stub ($b0 bytes) and the depacker ($150 bytes) in front of the data.
;------------------------------------------------------------------------------
data_to_program:	; from: pack_one_file
	lea	text_program_file(pc),a0        ; "PROGRAM FILE (y/n) ? "
	bsr.w	print
	bsr.w	wait_key                        ; a key
	cmp.b	#$6e,d0                         ; n?
	beq.w	data_to_program_done            ; yes: leave it
	cmp.b	#$4e,d0                         ; N?
	beq.w	data_to_program_done            ; yes: leave it
	cmp.b	#$79,d0                         ; y?
	beq.w	ask_addresses                   ; yes
	cmp.b	#$59,d0                         ; Y?
	bne.s	data_to_program                 ; no: ask again
ask_addresses:
	lea	text_decompact_at(pc),a0        ; "DECOMPACT CODE AT LOCATION: $"
	bsr.w	print
	bsr.w	read_hex                        ; read it
	move.l	d2,data_stub_depack_to          ; where the stub depacks to
	lea	text_execute_at(pc),a0          ; "EXECUTE CODE FROM LOCATION: $"
	bsr.w	print
	bsr.w	read_hex                        ; read it
	move.l	d2,data_stub_execute            ; where the stub jumps
ask_supervisor:
	lea	text_supervisor(pc),a0          ; "SUPERVISOR MODE (y/n) ? "
	bsr.w	print
	bsr.w	wait_key                        ; a key
	cmp.b	#$79,d0                         ; y?
	beq.s	stay_supervisor                 ; yes
	cmp.b	#$59,d0                         ; Y?
	beq.s	stay_supervisor                 ; yes
	cmp.b	#$6e,d0                         ; n?
	beq.s	add_data_stub                   ; yes
	cmp.b	#$4e,d0                         ; N?
	beq.s	add_data_stub                   ; yes
	bra.s	ask_supervisor                  ; ask again
stay_supervisor:
	move.w	#$4e71,data_stub_user_call      ; the stub stays in supervisor mode
add_data_stub:
	move.l	packed_length,data_stub_data_length ; the packed length into the stub's header
	move.l	#$150,d0                        ; the depacker's length
	sub.l	d0,build_ptr                    ; in front of the data
	add.l	d0,packed_length                ; the file is that much longer
	addq.l	#4,packed_length                ; and 4 more
	movea.l	build_ptr,a1                    ; where it goes
	lea	lsd_depack,a0                   ; the depacker
	subq.l	#1,d0
copy_depacker:
	move.b	(a0)+,(a1)+                     ; copy it
	dbra	d0,copy_depacker
	move.l	#$b0,d0                         ; the stub's length
	sub.l	d0,build_ptr                    ; in front of the depacker
	add.l	d0,packed_length                ; the file is that much longer
	movea.l	build_ptr,a1                    ; where it goes
	lea	data_stub,a0                    ; the stub
	subq.l	#1,d0
copy_data_stub:
	move.b	(a0)+,(a1)+                     ; copy it
	dbra	d0,copy_data_stub
data_to_program_done:
	rts

;------------------------------------------------------------------------------
; Read up to 8 hex digits with Cconrs; d2 = the number, d0 = $ffff at a character that is not a hex digit.
;------------------------------------------------------------------------------
read_hex:	; from: ask_offset, data_to_program
	move.l	#hex_input_buffer,-(sp)         ; the input buffer
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	moveq	#0,d2
	moveq	#0,d7
	move.b	hex_input_buffer+1,d7           ; the count
	subq.b	#1,d7
	movea.l	#hex_input_buffer+2,a0          ; the digits
	movea.l	#place_values,a1                ; the place values
	adda.l	#$20,a1                         ; past the end
	move.w	d7,d0
find_place_value:
	subq.l	#4,a1                           ; back one place for each digit
	dbra	d0,find_place_value
hex_number_digit:
	moveq	#0,d0
	move.l	(a1)+,d1                        ; the digit's place value
	move.b	(a0)+,d0                        ; the digit
	cmp.b	#$41,d0                         ; A or above?
	bge.s	hex_number_letter               ; yes
	cmp.b	#$30,d0                         ; below 0?
	blt.s	hex_number_bad                  ; yes: not a digit
	beq.s	hex_number_next                 ; 0: nothing to add
	subi.b	#$31,d0                         ; 1-9 to 0-8
add_place_value:
	add.l	d1,d2                           ; add the place value
	dbra	d0,add_place_value              ; digit times
hex_number_next:
	dbra	d7,hex_number_digit             ; for each digit
	bra.w	read_hex_done
hex_number_letter:
	cmp.b	#$46,d0                         ; above F?
	bgt.s	hex_number_lower                ; yes: a-f?
	cmp.b	#$41,d0
	blt.s	hex_number_bad
	subi.b	#$38,d0                         ; A-F to 9-14
	bra.s	add_place_value
hex_number_lower:
	cmp.b	#$66,d0                         ; above f?
	bgt.s	hex_number_bad                  ; yes: not a digit
	cmp.b	#$61,d0                         ; below a?
	blt.s	hex_number_bad                  ; yes: not a digit
	subi.b	#$58,d0                         ; a-f to 9-14
	bra.s	add_place_value
hex_number_bad:
	move.w	#$ffff,d0                       ; not a digit
read_hex_done:
	rts

;------------------------------------------------------------------------------
; Texts and variables.  The texts place themselves with VT52 cursor codes.
;------------------------------------------------------------------------------
place_values:	; from: read_hex
	dc.l	$10000000,$01000000,$00100000,$00010000 ; hex place values for read_hex, 8 digits down to 1
	dc.l	$00001000,$00000100,$00000010,$00000001
text_title:	; from: show_title
	dc.b	27,'E',27,'Y 7          VERSION 2.31           ',27 ; clear the screen, "VERSION 2.31", a line,
                                                ;   "AUTOMATION USE ONLY. (P) 1989"
	dc.b	'Y!7---------------------------------',27
	dc.b	'Y87AUTOMATION USE ONLY.     (P) 1989',0
text_main_menu:	; from: main_menu
	dc.b	27,'Y&=1. PACK/DEPACK PROGRAM',27,'Y(=2. PACK/DEPACK DATA FILE',27
	dc.b	'Y*=3. MULTI-PACKER MENU',27,'Y,=4. PACK DATA FILE(OFFSET)',27
	dc.b	'Y.=5. EXIT PROGRAM',0
text_multi_menu:	; from: multi_menu
	dc.b	27,'Y&=1. MULTI-PACK ALL',27,'Y(=2. MULTI-PACK (NO PRGS)',27
	dc.b	'Y*=3. MAIN MENU',0
text_enter_offset:	; from: ask_offset
	dc.b	27,'Y(7ENTER OFFSET $',0
text_loading:	; from: load_file
	dc.b	27,'Y&7  LOADING.......                     ',0
text_original_size:	; from: show_original_size
	dc.b	27,'Y&8ORIGINAL SIZE: $'
original_size_digits:	; from: show_original_size
	dc.b	'00000 BYTES LONG  ',0
text_choose_rate:	; from: choose_rate
	dc.b	27,'Y(6SELECT: F1=FAST/BIG to F10=SLOW/SMALL',0
text_amount_packed:	; from: pack_file
	dc.b	27,'Y(5     AMOUNT ALREADY PACKED = %        ',0
text_packed_size:	; from: show_packed_size
	dc.b	27,'Y',$27,'8PACKED SIZE:   $'
packed_size_digits:	; from: show_packed_size
	dc.b	'00000 BYTES LONG  ',27,'Y(:                             ',27 ; then a blank line, "HIT A KEY!" and
                                                ;   "PERCENTAGE OF ORIGINAL SIZE = %"
	dc.b	'Y+BHIT A KEY!',27,'Y)6 PERCENTAGE OF ORIGINAL SIZE = % ',0
text_decompact_at:	; from: data_to_program
	dc.b	27,'Y-7DECOMPACT CODE AT LOCATION: $',0
text_execute_at:	; from: data_to_program
	dc.b	27,'Y.7EXECUTE CODE FROM LOCATION: $',0
text_program_file:	; from: data_to_program
	dc.b	27,'Y+>PROGRAM FILE (y/n) ? ',0
text_supervisor:	; from: data_to_program
	dc.b	27,'Y0=SUPERVISOR MODE (y/n) ? ',0
text_saving:	; from: write_file
	dc.b	27,'Y+7  SAVING.....                        ',0
text_multi_all:	; from: multi_title
	dc.b	27,'Y"7* MULTI-FILE PACKER (DATA + PRG) *',0
text_multi_data:	; from: multi_title
	dc.b	27,'Y"7* MULTI-FILE PACKER  (DATA ONLY) *',0
text_multi_done:	; from: multi_menu
	dc.b	27,'E',27,'Y"7*  MULTI-FILE PACKER COMPLETE!!  *',27
	dc.b	'Y%7- HIT ANY KEY TO RETURN TO MENU! -',0
text_not_compacted:	; from: multi_menu
	dc.b	27,'Y+7*  PROGRAM FILE - NOT COMPACTED  *',0
text_load_error:	; from: alert_load_error
	dc.b	27,'E',27,'Y#7FILE DOES NOT EXIST OR HAS AN ERROR',27
	dc.b	'Y%7     -- ANY KEY TO TRY AGAIN --',0
text_write_error:	; from: alert_write_error
	dc.b	27,'E',27,'Y#7WE APPEAR TO HAVE A SAVE FAILURE!',27
	dc.b	'Y$7PLEASE CHECK DISK IS NOT FULL OR',27,'Y%7        WRITE PROTECTED',27
	dc.b	'Y',$27,'7  -- ANY KEY TO SAVE AGAIN --',0
text_wrong_type:	; from: unused_alert_type
	dc.b	27,'E',27,'Y#7    FILE IS INCORRECT PACK TYPE!',27
	dc.b	'Y%7     -- ANY KEY TO TRY AGAIN --',0
text_already_packed:	; from: multi_menu
	dc.b	27,'Y+7    FILE IS ALREADY PACKED!!   ',0
text_got_larger:	; from: multi_menu
	dc.b	27,'Y+7      FILE HAS GOT LARGER!!     ',0
	dc.b	$00
window_sizes:	; from: choose_rate
	dc.w	$0010,$0020,$0040,$0080,$0100,$0200,$0400,$0800 ; the search window for F1 to F10
	dc.w	$1000,$1120
	dc.w	$0000,$0000                     ; not used
hex_input_buffer:	; from: read_hex
	dc.w	$0800,$0000,$0000,$0000,$0000   ; Cconrs buffer: the maximum, the count, 8 characters
fsel_path:	; from: make_file_name
	dc.b	'A:\*.*',0                      ; the file selector's path
	dcb.b	31,0
text_file_line:	; from: load_file
	dc.b	27,'Y"7                                  ',27,'Y"9 CURRENT FILE IS ' ; a blank line, then "CURRENT FILE
                                                ;   IS " and the selector's name
fsel_name:	; from: make_file_name, set_extension, found_name
	dc.b	'PROG.DAT',0                    ; the file selector's name, printed as part of text_file_line
	dc.b	$00,$00,$00,$00,$00,$00
search_mask:	; from: find_first_file
	dc.b	'*.*',0                         ; the multi file packer's Fsfirst mask
percent_position:	; from: show_percent
	dc.b	27,'Y(T'                        ; VT52 cursor to row 8, column 52, then the percentage
percent_digits:	; from: pack_file, show_packed_size, percent
	dc.b	$30,$30                         ; "XX" or "00".."99"
	dc.b	$00,$00
fsel_control_ptr:	; from: file_selector
	dc.l	$00000000                       ; the AES parameter block for fsel_input: control
fsel_global_ptr:	; from: file_selector
	dc.l	$00000000                       ; global
fsel_intin_ptr:	; from: file_selector
	dc.l	$00000000                       ; intin
fsel_intout_ptr:	; from: file_selector
	dc.l	$00000000                       ; intout
fsel_addrin_ptr:	; from: file_selector
	dc.l	$00000000                       ; addrin
fsel_addrout_ptr:	; from: file_selector
	dc.l	$00000000                       ; addrout
fsel_control:	; from: file_selector
	dc.w	$005a,$0000,$0002,$0002,$0000   ; fsel_input: opcode 90, 0 intin, 2 intout, 2 addrin, 0 addrout
fsel_global:	; from: file_selector
	dc.w	$0000
fsel_intin:	; from: file_selector
	dc.w	$0000
fsel_intout:	; from: file_selector
	dc.w	$0000
fsel_ok:	; from: pack_one_file, save_file
	dc.w	$0000                           ; intout[1]: 1 for OK, 0 for Cancel
fsel_addrin:	; from: file_selector
	dc.l	fsel_path                       ; the path and the name
	dc.l	fsel_name
fsel_addrout:	; from: file_selector
	dc.l	$00000000
file_name:	; from: make_file_name, load_file, write_file
	dcb.b	54,0                            ; the full name of the file to load or save
program_flag:	; from: main_menu, pack_one_file, multi_menu, reset_buffers, load_file, set_extension, 1 more
	dc.b	$00                             ; $ff: the file is a program
multi_programs:	; from: multi_menu, multi_title
	dc.b	$00                             ; $ff: the multi file packer packs programs too
offset_flag:	; from: main_menu, pack_one_file, reset_buffers
	dc.b	$00,$00                         ; $ff: data from an offset
offset_length:	; from: reset_buffers, ask_offset, add_offset_data
	dc.l	$00000000                       ; the length of the data left unpacked
packed_flag:	; from: main_menu, pack_one_file, save_file, multi_menu, reset_buffers, load_file
	dc.b	$00,$00                         ; $ff: the loaded file is packed and is depacked instead
saved_colour:	; from: pack_one_file, pack_file
	dc.w	$0000                           ; the background colour while packing or depacking
source_ptr:	; from: pack_one_file, save_file, multi_menu, reset_buffers, load_file, ask_offset, 3 more
	dc.l	$00028000                       ; the data to pack
source_length:	; from: pack_one_file, save_file, multi_menu, ask_offset, pack_file, show_original_size, 1 more
	dc.l	$00000000                       ; its length
build_ptr:	; from: pack_one_file, save_file, multi_menu, reset_buffers, load_file, add_offset_data, 3 more
	dc.l	$00020000                       ; where the packed file is built
packed_length:	; from: pack_one_file, save_file, multi_menu, reset_buffers, add_offset_data, pack_file, 3 more
	dc.l	$00000000                       ; the packed length
search_window:	; from: pack_file
	dc.w	$0000                           ; how far ahead pack_file looks for strings: a long whose low word
                                                ;   choose_rate sets
	dc.w	$0800

;------------------------------------------------------------------------------
; The program stub: a PRG header and the code that runs a packed program.  add_program_stub puts these $336
; bytes in front of the packed data; the packed data then follows at program_stub_end.  The stub depacks the
; program $400 bytes above its own text, relocates it, sets the basepage from its header, and runs a mover
; from the screen that copies it down over the stub and clears behind it.  The multi file packer makes it
; silent: it then neither clears the screen nor prints its title.
;------------------------------------------------------------------------------
program_stub:	; from: add_program_stub
	bra.s	program_stub_text               ; the PRG magic $601a (bra.s past the header)
	dc.l	$0000031a                       ; text length: the stub
program_stub_data_length:	; from: add_program_stub
	dc.l	$00000000                       ; data length: the packed data
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; BSS, symbols, reserved, flags, absolute flag
	dc.w	$0000
program_stub_text:
	movea.l	4(sp),a5                        ; a5 = the basepage
	movea.l	$10(a5),a1                      ; the data segment: the packed data
	lea	stub_data(pc),a2
	move.l	a1,(a2)                         ; kept
	movea.l	8(a5),a1                        ; the text segment
	lea	stub_text(pc),a2
	move.l	a1,(a2)                         ; kept: the program will run here
	adda.l	#$400,a1                        ; $400 higher
	lea	stub_depack_to(pc),a2
	move.l	a1,(a2)                         ; is where it depacks to
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp
	lea	stub_screen(pc),a1
	move.l	d0,(a1)                         ; keep the screen
	movea.l	d0,a2                           ; a2 = the screen
	move.w	#$17d,d1                        ; 383 longs: the top lines
stub_clear_screen:	; from: multi_menu
	clr.l	(a2)+                           ; clear them (a nop for the multi file packer)
	dbra	d1,stub_clear_screen
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp
	cmp.b	#$0,d0                          ; low resolution?
	beq.s	stub_print_title                ; yes
	lea	stub_title+3(pc),a1             ; no: the title's column
	move.b	#$39,(a1)                       ; is 25, not 5
stub_print_title:
	lea	stub_title(pc),a1               ; the title
	move.l	a1,-(sp)
	move.w	#$9,-(sp)
stub_print_trap:	; from: multi_menu
	trap	#1                              ; Cconws, a nop for the multi file packer
	addq.l	#6,sp
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	lea	stub_old_ssp(pc),a6
	move.l	d0,(a6)                         ; the old stack
	move.w	$ff8240,d7                      ; palette 0, keep the background colour
	lea	program_stub_end(pc),a0         ; the packed data
	lea	stub_unpacked_length(pc),a2
	move.l	4(a0),(a2)                      ; its unpacked length
	lea	stub_depack_to(pc),a2
	movea.l	(a2),a1                         ; where it depacks to
	bsr.w	lsd_depack                      ; depack
	move.w	d7,$ff8240                      ; palette 0, colour back
	move.l	stub_old_ssp(pc),-(sp)          ; Super(old stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	movea.l	stub_text(pc),a5                ; the text segment
	suba.l	#$100,a5                        ; less $100
	movea.l	stub_depack_to(pc),a3           ; a5 = the basepage
	movea.l	2(a3),a0                        ; a3 = the depacked program's header
	adda.l	6(a3),a0                        ; + text length
	adda.l	$e(a3),a0                       ; + data length
	adda.l	#$1c,a0                         ; + symbol length
	adda.l	a3,a0                           ; + the header: a0 = its relocation table
	move.l	8(a5),d0                        ; d0 = where it will run
	movea.l	stub_depack_to(pc),a1           ; the depacked text
	adda.l	#$1c,a1
	tst.l	(a0)                            ; any relocation?
	beq.w	stub_relocated                  ; no
	adda.l	(a0),a1                         ; the first address
	clr.l	(a0)+                           ; the table's first long cleared
stub_relocate:
	add.l	d0,(a1)                         ; relocate a long
stub_relocate_next:
	clr.l	d1
	move.b	(a0),d1                         ; the next step
	clr.b	(a0)+                           ; cleared
	tst.w	d1                              ; the end?
	beq.s	stub_relocated                  ; yes
	cmp.b	#$1,d1                          ; 1: 254 on, nothing to relocate?
	bne.s	stub_relocate_step              ; no
	adda.l	#$fe,a1                         ; yes
	bra.s	stub_relocate_next
stub_relocate_step:
	adda.l	d1,a1                           ; on to the next long
	bra.s	stub_relocate                   ; relocate it
stub_relocated:
	movea.l	stub_depack_to(pc),a3           ; the depacked program's header
	move.l	2(a3),$c(a5)                    ; text length into the basepage
	move.l	6(a3),$14(a5)                   ; data length
	move.l	$a(a3),$1c(a5)                  ; BSS length
	move.l	8(a5),d0                        ; the text segment
	move.l	$c(a5),d1                       ; its length
	add.l	d0,d1
	move.l	d1,$10(a5)                      ; = the data segment
	move.l	$14(a5),d0
	add.l	d0,d1
	move.l	d1,$18(a5)                      ; = the BSS
	move.l	$1c(a5),d0
	add.l	d0,d1
	move.l	d1,$20(a5)                      ; the BSS's end
	addi.l	#$400,d1                        ; + $400
	movea.l	d1,a1
	move.l	stub_screen(pc),d0              ; the screen
	addi.l	#$7f00,d0                       ; + $7f00: below its last lines
	movea.l	d0,a2                           ; a2 = where the mover goes
	movea.l	d0,a5                           ; and runs
	move.l	#$26,d2                         ; 39 bytes
	lea	stub_mover(pc),a1               ; the mover
stub_copy_mover:
	move.b	(a1)+,(a2)+                     ; copy it
	dbra	d2,stub_copy_mover
	movea.l	stub_depack_to(pc),a1           ; the depacked header
	adda.l	#$1c,a1                         ; a1 = its text
	move.l	stub_unpacked_length(pc),d2     ; its length
	movea.l	stub_text(pc),a4                ; where it will run
	movea.l	a4,a3
	jmp	(a5)                            ; run the mover
stub_mover:
	addi.l	#$1c,d1                         ; the end of the depacked program
stub_mover_loop:
	move.b	(a1)+,(a3)+                     ; copy it down
	cmpa.l	d1,a1                           ; all copied?
	bne.s	stub_mover_loop                 ; no
	move.w	#$41c,d0                        ; $41d bytes
stub_mover_clear:
	clr.b	(a3)+                           ; cleared behind it
	dbra	d0,stub_mover_clear
	movea.l	a4,a1                           ; where it runs
	suba.l	#$100,a1                        ; less $100
	move.l	a1,d0                           ; d0 = the basepage
	move.l	a1,4(sp)                        ; on the stack, as at the start
	jmp	(a4)                            ; run the program
stub_text:
	dc.l	$00000000                       ; the text segment
stub_depack_to:
	dc.l	$00000000                       ; where the program depacks to
stub_unpacked_length:
	dc.l	$00000000                       ; its unpacked length
stub_screen:
	dc.l	$00000000                       ; the screen
stub_data:
	dc.l	$00000000                       ; the data segment
stub_old_ssp:
	dc.l	$00000000                       ; the stack Super returned
stub_title:
	dc.b	27,'Y %    AUTOMATION PACKER V2.3r',0 ; VT52 cursor to row 0, column 5 (25 when not low resolution),
                                                ;   then the title

;------------------------------------------------------------------------------
; The depacker for 'LSD!' data, part of both stubs: a0 = the packed data, a1 = where to depack it; d5 = the
; unpacked length.  It works from the end of the packed data down, flashing the background colour as it
; copies literals.
;------------------------------------------------------------------------------
lsd_depack:	; from: pack_one_file, data_to_program, program_stub
	adda.l	#$4,a0                          ; past 'LSD!'
	movea.l	a0,a4                           ; a4 = the header
	move.l	(a0)+,d5                        ; d5 = the unpacked length
	adda.l	d5,a1                           ; a1 = the end of the output
	adda.l	(a0),a0                         ; + the packed length
	suba.l	#$4,a0                          ; a0 = the end of the packed data
	tst.w	-(a0)                           ; the pad flag word
	bpl.s	lsd_first_bits                  ; no pad byte
	subq.l	#1,a0                           ; a pad byte: skip it
lsd_first_bits:
	move.b	-(a0),d0                        ; the first bits
lsd_next:
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_literal_bit                 ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_literal_bit:
	bcc.s	lsd_string                      ; 0: no literals
	clr.w	d1                              ; one literal
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_literal_count_bit           ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_literal_count_bit:
	bcc.s	lsd_copy_literals               ; 0: one literal
	lea	lsd_literal_table(pc),a3        ; the literal count codes
	moveq	#3,d3                           ; 4 sizes
lsd_literal_size:
	clr.w	d1
	move.b	0(a3,d3.w),d2                   ; its bits
	ext.w	d2
	moveq	#-1,d4
	lsl.w	d2,d4
	not.w	d4                              ; the all-ones value
	subq.w	#1,d2
lsd_literal_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_literal_bits_next           ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_literal_bits_next:
	roxl.w	#1,d1                           ; into d1
	dbra	d2,lsd_literal_bits             ; for each bit
	tst.w	d3                              ; the last size?
	beq.s	lsd_literal_base                ; yes
	cmp.w	d1,d4                           ; all ones: the next size
	dbne	d3,lsd_literal_size
lsd_literal_base:
	move.b	4(a3,d3.w),d2                   ; + the size's base
	ext.w	d2
	add.w	d2,d1
	bra.w	lsd_copy_literals
lsd_literal_table:
	dc.b	$0a,$03,$02,$02,$0e,$07,$04,$01 ; bits, then base counts less 1
lsd_copy_literals:
	move.b	-(a0),-(a1)                     ; copy a literal
	move.w	d0,$ffff8240                    ; palette 0, flash the background
	dbra	d1,lsd_copy_literals            ; for each literal
lsd_string:
	movea.l	a4,a3                           ; the header
	addq.l	#8,a3                           ; + 8: the start of the bit stream
	cmpa.l	a3,a0                           ; reached?
	ble.w	lsd_depack_done                 ; yes: done
	lea	lsd_length_table(pc),a3         ; the length codes
	moveq	#3,d2                           ; up to 4 bits
lsd_length_code:
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_length_code_bit             ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_length_code_bit:
	bcc.s	lsd_length_found                ; 0: this code
	dbra	d2,lsd_length_code
lsd_length_found:
	clr.w	d1
	addq.w	#1,d2
	move.b	0(a3,d2.w),d3                   ; its extra bits
	beq.s	lsd_length_base                 ; none
	ext.w	d3
	subq.w	#1,d3
lsd_length_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_length_bits_next            ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_length_bits_next:
	roxl.w	#1,d1                           ; into d1
	dbra	d3,lsd_length_bits              ; for each bit
lsd_length_base:
	move.b	5(a3,d2.w),d3                   ; + the base length
	ext.w	d3
	add.w	d3,d1
	bra.w	lsd_offset
lsd_length_table:
	dc.b	$0a,$02,$01,$00,$00,$0a,$06,$04,$03,$02 ; extra bits, then base lengths
lsd_offset:
	cmpi.w	#$2,d1                          ; length 2?
	beq.s	lsd_short_offset                ; yes: a short offset
	lea	lsd_offset_table(pc),a3         ; the offset codes
	moveq	#1,d3                           ; up to 2 bits
lsd_offset_code:
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_offset_code_bit             ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_offset_code_bit:
	bcc.s	lsd_offset_found                ; 0: this code
	dbra	d3,lsd_offset_code
lsd_offset_found:
	addq.w	#1,d3
	clr.w	d2
	move.b	0(a3,d3.w),d4                   ; its bits
	ext.w	d4
lsd_offset_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_offset_bits_next            ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_offset_bits_next:
	roxl.w	#1,d2                           ; into d2
	dbra	d4,lsd_offset_bits              ; for each bit
	lsl.w	#1,d3                           ; words
	add.w	4(a3,d3.w),d2                   ; + the base offset
	bra.s	lsd_copy_string
lsd_offset_table:
	dc.b	$0b,$04,$07,$00                 ; bits, then base offsets
	dc.w	$0120,$0000,$0020,$0000
lsd_short_offset:
	clr.w	d2
	moveq	#5,d3                           ; 6 bits
	clr.w	d4                              ; base 0
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_short_offset_bit            ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_short_offset_bit:
	bcc.s	lsd_short_offset_bits           ; 0: 6 bits
	moveq	#8,d3                           ; 1: 9 bits
	moveq	#64,d4                          ; base 64
lsd_short_offset_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	lsd_short_offset_next           ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
lsd_short_offset_next:
	roxl.w	#1,d2                           ; into d2
	dbra	d3,lsd_short_offset_bits        ; for each bit
	add.w	d4,d2                           ; + the base
lsd_copy_string:
	lea	0(a1,d2.w),a2                   ; the string's source
	ext.l	d1
	adda.l	d1,a2                           ; + the length
	subq.w	#1,d1
lsd_copy_string_loop:
	move.b	-(a2),-(a1)                     ; copy it
	dbra	d1,lsd_copy_string_loop         ; for each byte
	bra.w	lsd_next                        ; and on
lsd_depack_done:
	rts
program_stub_end:	; from: program_stub
	dc.w	$0000                           ; the end of the program stub: the packed data follows it in a packed
                                                ;   program

;------------------------------------------------------------------------------
; The data stub: a PRG header and the code that depacks data to a fixed address and jumps to another.
; data_to_program puts these $b0 bytes in front of the depacker and the packed data.
;------------------------------------------------------------------------------
data_stub:	; from: data_to_program
	bra.s	data_stub_text                  ; the PRG magic $601a (bra.s past the header)
	dc.l	$000001e4                       ; text length
data_stub_data_length:	; from: data_to_program
	dc.l	$00000000                       ; data length: the packed data
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; BSS, symbols, reserved, flags, absolute flag
	dc.w	$0000
data_stub_text:
	move.w	#$2,-(sp)                       ; cursor
	move.w	#$0,-(sp)                       ; hidden
	move.w	#$15,-(sp)
	trap	#14                             ; Cursconf
	addq.l	#6,sp
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp
	cmp.b	#$0,d0                          ; low resolution?
	beq.s	data_stub_print_title           ; yes
	lea	data_stub_title+3(pc),a1        ; no: the title's column
	move.b	#$39,(a1)                       ; is 25, not 5
data_stub_print_title:
	lea	data_stub_title(pc),a1          ; the title
	move.l	a1,-(sp)
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	bsr.s	super_swap                      ; supervisor mode
	lea	stub_depacker(pc),a0            ; the depacker
	move.l	#$150,d0                        ; the packed data, $150 on
	adda.l	d0,a0
	lea	data_stub_depack_to(pc),a1
	movea.l	(a1),a1                         ; a1 = where to depack it
	bsr.s	stub_depacker                   ; depack
data_stub_user_call:	; from: data_to_program
	bsr.s	super_swap                      ; back to user mode (a nop for SUPERVISOR MODE y)
	movea.l	data_stub_execute(pc),a0        ; the execute address
	jmp	(a0)                            ; run it
data_stub_execute:	; from: data_to_program
	dc.l	$00000000                       ; EXECUTE CODE FROM LOCATION
data_stub_depack_to:	; from: data_to_program
	dc.l	$00000000                       ; DECOMPACT CODE AT LOCATION
data_stub_title:
	dc.b	27,'Y %    AUTOMATION PACKER V2.2f',0 ; VT52 cursor to row 0, column 5 (25 when not low resolution),
                                                ;   then the title

super_swap:	; from: data_stub
	movea.l	(sp)+,a6                        ; the return address
	move.l	super_swap_stack(pc),-(sp)      ; Super with the kept stack: 0 the first time
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	lea	super_swap_stack(pc),a0
	move.l	d0,(a0)                         ; keep what it returned
	jmp	(a6)                            ; return
super_swap_stack:
	dc.l	$00000000                       ; the stack Super returned

	section	data

;------------------------------------------------------------------------------
; The data section: one word.  The depacker follows the data stub here when data_to_program builds a file.
;------------------------------------------------------------------------------
stub_depacker:	; from: data_stub
	dc.w	$0000                           ; the stub's call target

	section	bss
bss_end:

	end
