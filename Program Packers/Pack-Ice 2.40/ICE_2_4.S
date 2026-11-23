; ICE_2_4.PRG  -  Pack-Ice 2.40 ("This packer was written by Axe of Superior for ST-NEWS")
; Devpac source of the program, disassembled by Darren Birks, 23 November 2026.
; Text 6836 bytes, data 0 bytes, bss 1350 bytes.
;
; This source rebuilds ICE_2_4.PRG byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o ICE_2_4.PRG ICE_2_4.S
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; Pack-Ice 2.40 by Axe of Superior, "First version: 14.02.1990    Final changes: 14.08.1991", public domain.
; A TOS program that asks its questions with GEM alerts and picks files with the file selector, or in text
; when Alternate is held at its start.  The menu has 1) Crunch data file, 2) Crunch executable file and 3) Set
; Parameters, which sets the window (how far back strings are looked for) in hex, 5 to $1528; it starts at
; $1580.  Data can have the additional picture compression; a program can be relocated after depacking or
; not.  Every file matching the name or the selector's mask is packed in turn and saved over itself.
;
; While packing it shows "Remaining: xx%", then the time and the rate.  Alternate held while packing skips the
; file.  Before saving, the packed data is depacked again with ice_depack and compared with the file on disk.
;
; A command line makes it run without questions (read_command_line): a name packs the matching files as
; relocated programs and quits; a line that starts with $ is the answers to its questions, key by key.
;
; Some code is patched while it runs: relocate NO turns stub_relocate and stub_clear_bss into branches over
; their work, and save_packed writes the lengths into the stub.
;
; Some things in it look unfinished:
;   - read_line does not set the Cconrs buffer's count byte when it takes a line from the command line, and
;     ask_window reads only that byte, so an offset given in a $ line is ignored.
;   - The window starts at $1580, more than Set Parameters allows.  alloc_small leaves the string index out for
;     a window over $7000, which never happens.
;   - text_dest_prompt and the bytes after the DTA are not used.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$00b9  the notice
;   $00ba-$0b59  start-up, the menu and the file loop, file calls, input, time, window and progress
;   $0b5a-$0bf5  the picture conversion and the window
;   $0bf6-$1057  the packer, crunch
;   $1058-$1211  the program stub
;   $1212-$139b  ice_depack
;   $139c-$1ab3  the variables and texts
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; Packed data: 'ICE!', the packed length (with these 12 bytes), the unpacked length, then a bit stream that the
; depacker reads from the end down.  The first bits written, read last, are the picture flag: 0 for none, 1 0
; for a converted screen (4000 groups of 4 plane words), 1 1 and 16 bits for that many groups less 1.
;
; Packed program: the stub's $1ba bytes (a PRG header whose text is the stub's $19e bytes and the packed data,
; whose BSS is the room the program needs, with no relocation), then the packed data and a 0 long.
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The program starts here: over the notice to main.
;------------------------------------------------------------------------------
start:
	bra.w	main                            ; over the notice
notice:
	dc.b	'Pack-Ice: The best packer on the ST. It is Public Domain. You ma'
	dc.b	'y use it for packing anything you like. I don',$27
	dc.b	't want any donations. Greetings go to all people who use this pa'
	dc.b	'cker. ',0
	dc.b	$00                             ; pad
main:
	movea.l	sp,a5                           ; a5 = the stack at entry
	movea.l	4(a5),a5                        ; a5 = the basepage
	move.l	$c(a5),d0                       ; text length
	add.l	$14(a5),d0                      ; + data length
	add.l	$1c(a5),d0                      ; + BSS length
	addi.l	#$200,d0                        ; + $200
	move.l	d0,-(sp)                        ; Mshrink(0, basepage, length)
	move.l	a5,-(sp)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	adda.w	#$c,sp
	move.w	stub_relocate(pc),relocate_opcode ; keep the stub's relocation word
	move.w	stub_clear_bss(pc),clear_bss_opcode ; and its BSS clearing word
	bsr.w	check_alternate                 ; Alternate held: text, not alerts
	bsr.w	read_command_line               ; a command line: the answers taken from it
	bsr.w	appl_init
	bsr.w	hide_mouse                      ; hide the mouse
	bsr.w	menu                            ; the menu
	bsr.w	show_mouse                      ; show the mouse
	bsr.w	appl_exit
	bra.s	quit                            ; quit

appl_init:	; from: start
	move.l	#$a000100,d0                    ; appl_init: opcode 10, 0 intin, 1 intout, 0 addrin
	bsr.w	aes                             ; call
	move.w	d0,ap_id                        ; the application id
	moveq	#-1,d7                          ; exit code -1 if it failed
	addq.w	#1,d0                           ; -1?
	beq.w	quit                            ; yes: quit
	rts

appl_exit:	; from: start
	move.l	#$13000100,d0                   ; appl_exit: opcode 19, 0 intin, 1 intout, 0 addrin
	bsr.w	aes                             ; call
	rts
quit:	; from: start, appl_init
	move.w	d0,d7                           ; the exit code
	move.w	d7,-(sp)
	move.w	#$4c,-(sp)
	trap	#1                              ; Pterm

;------------------------------------------------------------------------------
; Pack-Ice's AES call: d0 holds the opcode and the intin, intout and addrin counts, a byte each, made into the
; control array (rsrc_gaddr also gets its addrout).  d0 = intout[0].
;------------------------------------------------------------------------------
aes:	; from: appl_init, appl_exit, menu, alert, show_mouse, hide_mouse
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	lea	aes_control(pc),a0              ; clear control
	clr.l	(a0)+
	clr.l	(a0)+
	clr.w	(a0)
	movep.l	d0,-$7(a0)                      ; the four counts into the low bytes of control[0-3]
	cmpi.b	#$70,-$7(a0)                    ; rsrc_gaddr?
	bne.s	aes_call                        ; no
	move.b	#$1,1(a0)                       ; yes: 1 addrout
aes_call:
	lea	aes_block(pc),a0                ; the parameter block
	move.l	a0,d1                           ; d1 = the block
	move.w	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	moveq	#0,d0
	move.w	aes_intout(pc),d0               ; intout[0]
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	rts
aes_block:
	dc.l	aes_control                     ; Pack-Ice's AES parameter block: control, global, intin, intout,
                                                ;   addrin, addrout
	dc.l	aes_global
	dc.l	aes_intin
	dc.l	aes_intout
	dc.l	aes_addrin
	dc.l	aes_addrout

;------------------------------------------------------------------------------
; Pack-Ice uses alerts and the file selector unless Alternate is held when it starts.
;------------------------------------------------------------------------------
check_alternate:	; from: start
	moveq	#0,d4                           ; text
	bsr.w	alternate_held                  ; Alternate held?
	bne.s	check_alternate_done            ; yes
	moveq	#1,d4                           ; no: alerts
check_alternate_done:
	move.w	d4,gem_mode                     ; kept
	rts

;------------------------------------------------------------------------------
; A command line makes Pack-Ice answer its own questions from it, in text, not alerts: keys_pending points at
; the answers, which get_answer and read_line take before the keyboard.  A plain name gives "2y", the name,
; Return and "n": the files matching it packed as programs, relocated, then quit.  A line that starts with $ is
; the answers themselves.
;------------------------------------------------------------------------------
read_command_line:	; from: start
	lea	zero_long(pc),a1                ; no answers
	lea	$80(a5),a0                      ; the command line
	moveq	#0,d1
	move.b	(a0)+,d1                        ; its length
	beq.s	command_line_set                ; none
	clr.w	gem_mode                        ; text, not alerts
	cmpi.b	#$24,(a0)+                      ; '$': the answers as they are?
	beq.s	command_line_dollar             ; yes
	lea	-$2(a0),a1                      ; from the length byte
command_line_end:
	tst.b	(a0)+                           ; find the end
	bne.s	command_line_end                ; up to the 0
	subq.w	#1,a0                           ; back to the 0
	cmpi.b	#$d,-$1(a0)                     ; a Return at the end?
	beq.s	command_line_add_n              ; yes
	move.b	#$d,(a0)+                       ; no: add one
command_line_add_n:
	move.b	#$6e,(a0)+                      ; then 'n': no other file
	clr.b	(a0)+                           ; ended
	lea	1(a0),a2                        ; one byte up
command_line_shift:
	move.b	-(a0),-(a2)                     ; move the line up a byte
	cmpa.l	a1,a0                           ; at the start?
	bne.s	command_line_shift              ; no: on
	move.w	#$3279,(a0)                     ; "2y" in front: a program, relocated
command_line_dollar:
	lea	(a0),a1                         ; the answers
command_line_set:
	move.l	a1,keys_pending                 ; kept
	rts

;------------------------------------------------------------------------------
; Pack-Ice's menu: data, a program or the parameters (its window).  Then the picture or relocation question,
; the files to pack, and the loop over every file matching the name.
;------------------------------------------------------------------------------
menu:	; from: start, save_packed
	lea	banner(pc),a0                   ; the banner
	bsr.w	print_text                      ; print
menu_ask:
	tst.w	gem_mode                        ; alerts?
	beq.s	menu_text                       ; no
	lea	alert_menu(pc),a0               ; "What do you wish to pack?"
	bsr.w	alert
	addi.w	#$30,d0                         ; button 1-3 to '1'-'3'
	bra.s	menu_button                     ; to the choice
menu_text:
	lea	text_menu(pc),a0                ; "1) Crunch data file (Default) ... Please select: "
	bsr.w	print_text                      ; print
menu_key:
	bsr.w	get_answer                      ; a key or an answer
	cmpi.b	#$33,d0                         ; '3': parameters?
	bne.s	menu_choice                     ; no
	lea	newline(pc),a0                  ; a new line
	bsr.w	print_text                      ; print
	bsr.w	ask_window                      ; ask for the offset
	lea	newline(pc),a0                  ; a new line
	bsr.w	print_text                      ; print
	bra.s	menu_ask                        ; the menu again
menu_button:
	cmpi.b	#$33,d0                         ; SETUP?
	bne.s	menu_choice                     ; no
	bsr.w	ask_window                      ; ask for the offset
	bra.s	menu_ask                        ; the menu again
menu_choice:
	move.b	#$1,data_mode                   ; data
	cmpi.b	#$31,d0                         ; '1'?
	beq.s	ask_picture                     ; yes
	cmpi.b	#$d,d0                          ; Return?
	beq.s	ask_picture                     ; yes
	cmpi.b	#$32,d0                         ; '2'?
	bne.s	menu_key                        ; no: another key
	clr.b	data_mode                       ; a program
ask_relocate:
	tst.w	gem_mode                        ; alerts?
	beq.s	relocate_text                   ; no
	lea	alert_relocate(pc),a0           ; "Relocate after decrunch?"
	bsr.w	alert
	addi.w	#$6c,d0                         ; 1 to 'm', 2 to 'n'
	cmp.w	#$6e,d0                         ; NO?
	beq.s	relocate_answer                 ; yes
	moveq	#121,d0                         ; YES: 'y'
	bra.s	relocate_answer                 ; to the answer
relocate_text:
	lea	text_relocate(pc),a0            ; "Relocate program after depacking (Y/n): "
	bsr.w	print_text                      ; print
	bsr.w	get_answer                      ; a key or an answer
relocate_answer:
	move.w	relocate_opcode(pc),stub_relocate ; the stub relocates
	move.w	clear_bss_opcode(pc),stub_clear_bss ; and clears the BSS
	cmpi.b	#$d,d0                          ; Return?
	beq.s	choose_files                    ; yes: relocate
	ori.b	#$20,d0                         ; lower case
	cmpi.b	#$79,d0                         ; 'y'?
	beq.s	choose_files                    ; yes: relocate
	cmpi.b	#$6e,d0                         ; 'n'?
	bne.s	ask_relocate                    ; no: ask again
	move.w	#$602c,stub_relocate            ; the stub skips the relocation
	move.w	#$6012,stub_clear_bss           ; and the BSS clearing
	bra.s	choose_files                    ; choose the files
ask_picture:
	clr.w	picture_mode                    ; no picture compression
	tst.w	gem_mode                        ; alerts?
	beq.s	picture_text                    ; no
	lea	alert_picture(pc),a0            ; "Do you wish to use an additional algorithm for picture compression?"
	bsr.w	alert
	cmp.w	#$1,d0                          ; NO?
	beq.s	choose_files                    ; yes
	bra.s	picture_on                      ; YES
picture_text:
	lea	text_picture(pc),a0             ; "Additional picture compression (N/y): "
	bsr.w	print_text                      ; print
	bsr.w	get_answer                      ; a key or an answer
	cmp.b	#$79,d0                         ; 'y'?
	bne.s	choose_files                    ; no
picture_on:
	move.w	#$1,picture_mode                ; picture compression
choose_files:
	moveq	#-1,d3                          ; verify
	move.w	d3,verify_flag                  ; on
	tst.w	gem_mode                        ; alerts?
	beq.w	type_name                       ; no: type the name
	move.w	#$19,-(sp)
	trap	#1                              ; Dgetdrv
	addq.l	#2,sp
	lea	fsel_path(pc),a4                ; the selector's path
	move.b	#$41,(a4)                       ; the drive letter
	add.b	d0,(a4)+                        ; + the drive
	move.b	#$3a,(a4)+                      ; :
	clr.w	-(sp)                           ; the current drive
	pea	(a4)                            ; into the path
	move.w	#$47,-(sp)
	trap	#1                              ; Dgetpath
	addq.l	#8,sp
path_end:
	tst.b	(a4)+                           ; find the end
	bne.s	path_end
	move.b	#$5c,-$1(a4)                    ; \
	move.b	#$2a,(a4)+                      ; *
	move.b	#$2e,(a4)+                      ; .
	move.b	#$2a,(a4)+                      ; *
	clr.b	(a4)+                           ; ended
	bsr.w	show_mouse                      ; show the mouse
	lea	aes_addrin(pc),a4               ; addrin
	move.l	#$5a000202,d0                   ; fsel_input: opcode 90, 0 intin, 2 intout, 2 addrin
	move.l	#fsel_path,(a4)+                ; the path
	move.l	#file_name,(a4)+                ; and the name
	bsr.w	aes                             ; call
	tst.w	d0                              ; all right?
	beq.w	another                         ; no: done
	move.l	aes_intout(pc),d4               ; intout[1] in the low word: the button
	bsr.w	hide_mouse                      ; hide the mouse
	lea	banner(pc),a0                   ; the banner
	bsr.w	print_text                      ; print
	tst.w	d4                              ; OK?
	beq.w	another                         ; no: done
	bsr.w	set_folder                      ; the selector's folder made current
	bmi.w	another                         ; failed: done
	lea	file_name(pc),a2                ; the name
	tst.b	(a2)                            ; any?
	bne.s	first_file                      ; yes
	move.l	#$2a2e2a00,(a2)                 ; no: "*.*"
	bra.s	first_file                      ; find it
type_name:
	lea	text_source_prompt(pc),a0       ; "Enter name of source file: "
	bsr.w	print_text                      ; print
	lea	path_input(pc),a0               ; the line buffer, its text in fsel_path
	moveq	#90,d0                          ; up to 90 characters
	bsr.w	read_line                       ; read a line
	lea	fsel_path(pc),a1                ; the typed name
	adda.w	d0,a1                           ; + its length
	clr.b	(a1)                            ; ended
find_name_start:
	cmpi.b	#$5c,-(a1)                      ; back to a \
	beq.s	name_found                      ; found
	cmpi.b	#$3a,(a1)                       ; or a :
	beq.s	name_found                      ; found
	subq.w	#1,d0                           ; one character less
	bpl.s	find_name_start                 ; on back
name_found:
	lea	file_name(pc),a0                ; the name part
	addq.w	#1,a1                           ; after the \ or :
copy_name:
	tst.b	(a1)                            ; the end?
	move.b	(a1)+,(a0)+                     ; to file_name
	bne.s	copy_name                       ; up to its 0
	tst.w	d0                              ; a folder in front?
	ble.s	typed_name_done                 ; no
	bsr.w	set_folder                      ; yes: make it current
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
	bmi.w	another                         ; no: done
alloc_small:	; from: save_packed
	move.l	file_length(pc),d3              ; the file's length
	addi.l	#$988,d3                        ; + $988
	andi.w	#$fffe,d3                       ; even
	move.l	d3,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	ble.w	no_memory                       ; no: "Could not allocate enough memory"
block_ok:
	addq.l	#1,d0                           ; even
	andi.w	#$fffe,d0
	move.l	d0,dest                         ; the packed data goes at the start
	addi.l	#$974,d0                        ; $974 on: the source
	move.l	d0,source                       ; where the file is read to
	move.w	#$942,literal_check             ; check the output after $942 literals
	cmpi.l	#$7000,window                   ; a window over $7000?
	bgt.s	read_source                     ; yes: no index
	bsr.w	alloc_match_table               ; no: take the index
read_source:
	bsr.w	open_file                       ; open the file
	bmi.w	menu_done                       ; failed: stop
	movea.l	source(pc),a0                   ; read it
	move.l	file_length(pc),d0              ; its length
	bsr.w	read_file                       ; read
	bmi.w	menu_done                       ; failed: stop
	bsr.w	close_file                      ; close it
	move.l	file_length(pc),d1              ; the length
	add.l	source(pc),d1                   ; + the source
	move.l	d1,source_end                   ; = its end
	lea	text_working(pc),a0             ; "Working: "
	bsr.w	print_text                      ; print
	tst.w	match_table                     ; the index?
	bpl.s	working_index                   ; yes
	lea	text_no_index(pc),a0            ; no: "~"
	bsr.w	print_text                      ; print
working_index:
	tst.w	picture_mode                    ; picture compression?
	beq.s	working_name                    ; no
	lea	text_picture_mark(pc),a0        ; "P>"
	bsr.w	print_text                      ; print
working_name:
	lea	dta_name(pc),a0                 ; the file's name
	bsr.w	print_text                      ; print
	movea.l	source(pc),a0                   ; keep the source's first 28 bytes (a program's header) for the stub
	lea	source_header(pc),a1            ; to source_header
	moveq	#6,d0                           ; 7 longs
keep_header:
	move.l	(a0)+,(a1)+                     ; a long
	dbra	d0,keep_header                  ; for each
	clr.w	alt_pressed                     ; Alternate not pressed
	bsr.w	time_ticks                      ; start the clock
	bsr.w	picture_convert                 ; picture compression
	bsr.w	crunch                          ; pack
	movea.l	d0,a3                           ; a3 = the packed length
	bsr.w	free_match_table                ; free the index
	move.l	a3,d0                           ; the packed length
	bmi.w	menu_done                       ; failed: stop
	bsr.w	print_time                      ; print the time
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
	adda.w	#$1ba,a1                        ; + the stub's $1ba bytes
set_packed_end:
	move.l	a1,packed_end                   ; kept
	movea.l	file_length(pc),a2              ; the file's length
	cmpa.l	a2,a1                           ; longer?
	bge.w	larger                          ; yes: "Larger than original!"
	tst.w	verify_flag                     ; verify?
	beq.w	save_packed                     ; no: save
	lea	text_verify(pc),a0              ; "    Verify: "
	bsr.w	print_text                      ; print
	move.l	a3,d1                           ; the packed length
	addi.l	#$2724,d1                       ; + $2724
	move.l	d1,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bgt.s	verify_depack                   ; yes
	lea	text_no_mem(pc),a0              ; no: "No mem!"
	bsr.w	print_text                      ; print
	bra.w	save_packed                     ; and save without verifying
verify_depack:
	movea.l	d0,a2                           ; a2 = the block
	move.l	d0,packed_copy                  ; kept
	move.l	a3,d1                           ; the packed length
	subq.l	#1,d1
	movea.l	dest(pc),a1                     ; the packed data
	movea.l	a1,a0                           ; a0 = it, for the depacker
	movea.l	a1,a4                           ; a4 = it, the depacked data afterwards
verify_keep_packed:
	move.b	(a1)+,(a2)+                     ; copied to the block
	subq.l	#1,d1
	bpl.s	verify_keep_packed              ; for each byte
	bsr.w	ice_depack                      ; depack it where it is
	cmp.l	file_length(pc),d0              ; the right length?
	bne.s	verify_error                    ; no: error
	move.l	a2,d0                           ; past the copy
	addq.l	#8,d0                           ; 8 on
	andi.w	#$fffe,d0                       ; even
	movea.l	d0,a2
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
	bmi.s	verify_block_done               ; none
verify_loop:
	move.b	(a2)+,d1                        ; a byte read
	move.b	(a4)+,d2                        ; and the depacked one
	cmp.b	d1,d2                           ; the same?
	bne.s	verify_error                    ; no: error
	dbra	d0,verify_loop                  ; for each byte
verify_block_done:
	cmpi.l	#$2710,d4                       ; 10000 read: on
	beq.s	verify_read                     ; yes: the next block
	movea.l	packed_copy(pc),a1              ; the copy
	movea.l	dest(pc),a2                     ; back to dest: the depacking wrote over it
	move.l	a3,d1                           ; the packed length
	subq.l	#1,d1
verify_restore:
	move.b	(a1)+,(a2)+                     ; copied back
	subq.l	#1,d1
	bpl.s	verify_restore                  ; for each byte
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
; Save the packed file over the original: data as it is; a program behind the stub, with the stub's text
; length, its BSS (room for the program) and the two lengths patched in, and an empty relocation table.
;------------------------------------------------------------------------------
save_packed:	; from: menu
	bsr.w	print_rate                      ; print the rate
	cmpi.b	#$1,data_mode                   ; data?
	beq.w	save_data                       ; yes
	lea	source_header(pc),a0            ; the program's header
	lea	$19e(a3),a5                     ; the stub's text: its $19e bytes and the packed data
	move.l	a5,d0
	addq.l	#1,d0                           ; made even
	andi.w	#$fffe,d0
	move.l	d0,stub_text_length             ; is the stub's text length
	cmpi.w	#$601a,(a0)+                    ; a program header?
	bne.s	stub_lengths                    ; no
	move.l	(a0)+,d2                        ; its text
	add.l	(a0)+,d2                        ; + data
	add.l	(a0)+,d2                        ; + BSS
	sub.l	d0,d2                           ; less the stub's text
	move.l	d2,stub_bss_length              ; = the stub's BSS: room to depack in
stub_lengths:
	move.l	a3,d0                           ; the packed length
	moveq	#120,d1                         ; less 120
	sub.l	d1,d0
	move.l	d0,stub_packed_end+2            ; into the stub
	move.l	file_length(pc),stub_unpacked_end+2 ; the unpacked length into the stub
	bsr.w	create_file                     ; create the file
	bmi.w	menu_done                       ; failed: stop
	lea	stub(pc),a5                     ; the stub
	movea.w	#$1ba,a6                        ; $1ba bytes
	bsr.w	write_file                      ; write it
	bmi.w	menu_done                       ; failed: stop
	movea.l	dest(pc),a5                     ; the packed data
	move.l	a3,d0                           ; its length
	addq.l	#1,d0                           ; made even
	andi.w	#$fffe,d0
	movea.l	d0,a6
	bsr.w	write_file                      ; write it
	bmi.w	menu_done                       ; failed: stop
	lea	zero_long(pc),a5                ; a 0 long
	clr.l	(a5)
	movea.w	#$4,a6                          ; 4 bytes
	bsr.w	write_file                      ; write it: no relocation
	bmi.w	menu_done                       ; failed: stop
	bsr.w	close_file                      ; close
	bmi.w	menu_done                       ; failed: stop
	bra.s	next_file                       ; the next file
save_data:
	bsr.w	create_file                     ; create the file
	movea.l	dest(pc),a5                     ; the packed data
	movea.l	a3,a6                           ; its length
	bsr.w	write_file                      ; write it
	bmi.w	menu_done                       ; failed: stop
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
	bpl.w	alloc_small                     ; yes: pack it
another:	; from: menu
	tst.w	gem_mode                        ; alerts?
	beq.s	another_text                    ; no
	lea	alert_another(pc),a0            ; "Do you wish to pack another file?"
	bsr.w	alert
	cmp.w	#$1,d0                          ; YES?
	beq.w	menu                            ; yes: the menu
	cmp.w	#$2,d0                          ; NO?
	beq.s	menu_done                       ; yes: done
another_text:
	lea	newline(pc),a0                  ; a new line
	bsr.w	print_text                      ; print
	lea	text_another(pc),a0             ; "Crunch another file (Y/n): "
	bsr.w	print_text                      ; print
	bsr.w	get_answer                      ; a key
	ori.b	#$20,d0                         ; lower case
	cmpi.b	#$6e,d0                         ; 'n'?
	beq.s	menu_done                       ; yes: done
	bra.w	menu                            ; no: the menu
no_memory:	; from: menu
	lea	text_no_memory(pc),a0           ; "Could not allocate enough memory"
	bsr.w	print_text                      ; print
	bsr.w	raw_key                         ; wait for a key
menu_done:	; from: menu
	rts

;------------------------------------------------------------------------------
; File calls on the found name (dta_name) and file_handle; the flags are set from d0.
;------------------------------------------------------------------------------
open_file:	; from: menu
	clr.w	-(sp)                           ; read only
	pea	dta_name(pc)                    ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.w	d0,file_handle                  ; the handle
	tst.l	d0                              ; the flags
	rts

read_file:	; from: menu
	pea	(a0)                            ; to a0
	move.l	d0,-(sp)                        ; d0 bytes
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	adda.w	#$c,sp
	tst.l	d0                              ; the flags
	rts

create_file:	; from: save_packed
	move.w	#$0,-(sp)                       ; normal file
	pea	dta_name(pc)                    ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	move.w	d0,file_handle                  ; the handle
	tst.l	d0                              ; the flags
	rts

write_file:	; from: save_packed
	move.l	a5,-(sp)                        ; from a5
	move.l	a6,-(sp)                        ; a6 bytes
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	tst.l	d0                              ; the flags
	rts

close_file:	; from: menu, save_packed
	move.w	file_handle(pc),-(sp)           ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.l	d0                              ; the flags
	rts

;------------------------------------------------------------------------------
; Cut fsel_path after its last \ (adding one after a drive's :) and make it the current drive and folder; the
; flags from Dsetpath.
;------------------------------------------------------------------------------
set_folder:	; from: menu
	lea	fsel_path(pc),a2                ; the path
set_folder_end:
	tst.b	(a2)+                           ; find its end
	bne.s	set_folder_end
set_folder_back:
	cmpi.b	#$5c,-(a2)                      ; back to a \
	beq.s	set_folder_cut                  ; found
	cmpi.b	#$3a,(a2)                       ; a :?
	bne.s	set_folder_back                 ; no: on back
	addq.l	#1,a2                           ; yes: a \ after it
	move.b	#$5c,(a2)
set_folder_cut:
	clr.b	1(a2)                           ; end the path after the \
	lea	fsel_path(pc),a4                ; the path
	cmpi.b	#$3a,1(a4)                      ; a drive?
	bne.s	set_folder_path                 ; no
	moveq	#14,d0                          ; Dsetdrv
	swap	d0                              ; the function in the high word
	move.b	(a4),d0                         ; the letter
	ori.b	#$20,d0                         ; lower case
	subi.b	#$61,d0                         ; the drive number
	move.l	d0,-(sp)
	trap	#1                              ; GEMDOS, Dsetdrv
	addq.l	#4,sp
	addq.l	#2,a4                           ; past the drive
set_folder_path:
	pea	(a4)                            ; the folder
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.l	d0                              ; all right?
	rts

;------------------------------------------------------------------------------
; A key: the next answer from the command line if one is left (echoed), else Cconin.
;------------------------------------------------------------------------------
get_answer:	; from: menu, save_packed
	movea.l	keys_pending(pc),a0             ; the answers
	move.b	(a0)+,d0                        ; the next
	beq.s	get_key                         ; none: the keyboard
	move.l	a0,keys_pending                 ; used
	move.l	d0,-(sp)
	bsr.w	put_char                        ; echo it
	move.l	(sp)+,d0
	rts
get_key:
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
; Read a line into the Cconrs buffer at a0, at most d0 characters: from the command line's answers up to a
; Return if any are left (printed), else with Cconrs.  d0 = the count.  The answers do not set the buffer's count
; byte, which ask_window reads.
;------------------------------------------------------------------------------
read_line:	; from: menu, ask_window
	move.b	d0,(a0)                         ; the maximum
	movea.l	keys_pending(pc),a1             ; the answers
	tst.b	(a1)                            ; any?
	beq.s	read_line_keyboard              ; no: Cconrs
	addq.w	#2,a0                           ; the text
	move.l	a0,d2                           ; its start
read_line_copy:
	move.b	(a1)+,(a0)                      ; a character
	beq.s	read_line_end                   ; the end?
	cmpi.b	#$d,(a0)                        ; Return?
	beq.s	read_line_end                   ; yes: the line ends
	addq.w	#1,a0
	subq.b	#1,d0                           ; one less to go
	bpl.s	read_line_copy                  ; up to the maximum
read_line_end:
	clr.b	(a0)                            ; ended
	suba.l	d2,a0                           ; the count
	movem.l	a0-a1,-(sp)
	movea.l	d2,a0                           ; the line
	bsr.w	print_text                      ; printed
	move.l	(sp)+,d0                        ; d0 = the count
	move.l	(sp)+,keys_pending              ; the answers left
	rts
read_line_keyboard:
	pea	(a0)                            ; the buffer
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; Z clear when Alternate is held.
;------------------------------------------------------------------------------
alternate_held:	; from: check_alternate, progress
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	trap	#13                             ; Kbshift
	addq.l	#4,sp
	btst	#$3,d0                          ; Alternate?
	rts

print_text:	; from: menu, save_packed, read_line, print_time, ask_window, progress, 2 more
	move.l	a0,-(sp)                        ; the string
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; The 200 Hz ticks since the last call, in elapsed_ticks.
;------------------------------------------------------------------------------
time_ticks:	; from: menu, print_time
	pea	read_ticks(pc)                  ; Supexec(read_ticks)
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.l	#6,sp
	rts
read_ticks:
	move.l	$4ba.w,d0                       ; _hz_200, the 200 Hz counter
	sub.l	last_ticks(pc),d0               ; less the last
	move.l	d0,elapsed_ticks                ; the ticks since
	move.l	$4ba.w,last_ticks               ; _hz_200, keep it
	rts

;------------------------------------------------------------------------------
; Print the packing time as minutes:seconds.
;------------------------------------------------------------------------------
print_time:	; from: menu
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	lea	text_time(pc),a0                ; "Time:" at its place
	bsr.s	print_text                      ; print
	bsr.s	time_ticks                      ; the ticks
	move.l	elapsed_ticks(pc),d0            ; the ticks
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
	moveq	#58,d0                          ; :
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
; "Please enter the offset": Pack-Ice's window in hex, 5 to $1528 (its current value is the default).
;------------------------------------------------------------------------------
ask_window:	; from: menu
	lea	text_window_prompt_end(pc),a1   ; the end of "$0000"
	move.l	window(pc),d0                   ; the window
	moveq	#3,d2                           ; 4 digits
window_digit:
	moveq	#15,d1
	and.l	d0,d1                           ; the low digit
	cmp.w	#$9,d1                          ; 0-9?
	ble.s	window_digit_char               ; yes
	addi.w	#$27,d1                         ; no: a-f
window_digit_char:
	addi.w	#$30,d1                         ; to a character
	move.b	d1,-(a1)                        ; into the prompt
	lsr.l	#4,d0                           ; the next digit
	dbra	d2,window_digit                 ; for each
	lea	text_window_prompt(pc),a0       ; "Please enter the offset (Default: $xxxx): $"
	bsr.w	print_text                      ; print
	lea	offset_input(pc),a3             ; the input buffer
	moveq	#4,d0                           ; 4 characters
	lea	(a3),a0                         ; the buffer
	bsr.w	read_line                       ; read a line
	moveq	#0,d2
	move.b	1(a3),d2                        ; the count
	beq.s	ask_window_done                 ; none: keep the window
	adda.l	d2,a3                           ; + the count
	addq.l	#2,a3                           ; past the last character
	moveq	#0,d4                           ; the value
	moveq	#0,d3                           ; the shift
	subq.w	#1,d2
	bmi.s	ask_window                      ; none: ask again
window_input_digit:
	moveq	#0,d0
	move.b	-(a3),d0                        ; a character, from the last
	subi.b	#$30,d0                         ; '0'-'9'?
	bmi.s	window_bad_digit                ; below: 0
	cmpi.b	#$9,d0                          ; 0-9?
	ble.s	window_add_digit                ; yes
	addi.b	#$30,d0                         ; back to the character
	ori.b	#$20,d0                         ; lower case
	subi.b	#$57,d0                         ; 'a'-'f'?
	cmpi.b	#$9,d0                          ; below 'a'?
	ble.s	window_bad_digit                ; yes: 0
	cmpi.b	#$f,d0                          ; over 'f'?
	ble.s	window_add_digit                ; yes
window_bad_digit:
	moveq	#0,d0                           ; anything else: 0
window_add_digit:
	lsl.w	d3,d0                           ; to its place
	add.l	d0,d4                           ; added
	addq.w	#4,d3                           ; the next place
	dbra	d2,window_input_digit           ; for each character
	move.l	#$1528,d0                       ; at most $1528
	cmp.l	d0,d4                           ; over it?
	bcs.s	window_check_low                ; no
	move.l	d0,d4                           ; yes: $1528
window_check_low:
	cmp.w	#$5,d4                          ; at least 5
	bcc.s	window_set                      ; yes
	moveq	#5,d4                           ; no: 5
window_set:
	move.l	d4,window                       ; the window
ask_window_done:
	rts

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
	bcs.w	progress_skip                   ; no
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
	move.l	a0,source_end                   ; the packing ends here
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

put_char:	; from: get_answer, print_time, print_rate
	movem.l	d0-d3/a0-a3,-(sp)               ; keep the registers
	move.w	d0,-(sp)                        ; the character
	move.w	#$2,-(sp)
	trap	#1                              ; Cconout
	addq.l	#4,sp
	movem.l	(sp)+,d0-d3/a0-a3               ; the registers back
	rts

;------------------------------------------------------------------------------
; form_alert(1, a0) with the mouse shown; d0 = the button.
;------------------------------------------------------------------------------
alert:	; from: menu, save_packed
	bsr.w	show_mouse                      ; show the mouse
	move.l	#$34010101,d0                   ; form_alert: opcode 52, 1 intin, 1 intout, 1 addrin
	move.w	#$1,aes_intin                   ; default button 1
	move.l	a0,aes_addrin                   ; the alert
	bsr.w	aes                             ; call
	move.w	aes_intout(pc),-(sp)            ; the button
	bsr.w	hide_mouse                      ; hide the mouse
	moveq	#0,d0
	move.w	(sp)+,d0
	rts

show_mouse:	; from: start, menu, alert
	move.l	#$4e010101,d0                   ; graf_mouse: opcode 78, 1 intin, 1 intout, 1 addrin
	move.w	#$101,aes_intin                 ; M_ON
	bsr.w	aes                             ; call
	move.l	#$4e010101,d0                   ; graf_mouse
	move.w	#$0,aes_intin                   ; ARROW
	bsr.w	aes                             ; call
	rts

hide_mouse:	; from: start, menu, alert
	move.l	#$4e010101,d0                   ; graf_mouse: opcode 78, 1 intin, 1 intout, 1 addrin
	move.w	#$100,aes_intin                 ; M_OFF
	bsr.w	aes                             ; call
	rts

;------------------------------------------------------------------------------
; Picture compression: the file's plane words are turned into one nibble per pixel, 4 pixels a word, which
; packs better; the depacker turns them back.  A file of 32000 bytes and less than $104 bytes in front is taken
; as a screen, its 4000 groups of 4 words after the header.  Any other even length is done too: its groups after
; a header of the length's last 3 bits, or the last $80000 bytes of a longer file.  The group count less 1 goes
; to picture_groups for the packer.  An odd length is marked with a '-'.
;------------------------------------------------------------------------------
picture_convert:	; from: menu
	clr.w	picture_converted               ; not converted
	tst.w	picture_mode                    ; picture compression?
	beq.s	picture_convert_done            ; no
	movea.l	source(pc),a1                   ; the source
	move.l	file_length(pc),d1              ; its length
	move.l	#$7d00,d0                       ; less 32000
	sub.l	d0,d1
	bmi.s	picture_any_length              ; shorter: any length
	cmp.l	#$104,d1                        ; a header under $104?
	bcc.s	picture_any_length              ; no: any length
	move.w	#$f9f,d7                        ; 4000 groups
picture_set_groups:
	move.w	d7,picture_groups               ; the group count less 1, for the packer
	adda.l	d1,a1                           ; past the header
picture_group:
	movem.w	(a1),d0-d3                      ; the 4 plane words
	moveq	#3,d6                           ; 4 words out
	addq.w	#8,a1                           ; past them
picture_word:
	moveq	#3,d5                           ; 4 pixels
picture_pixel:
	add.w	d0,d0                           ; plane 0's bit
	addx.w	d4,d4
	add.w	d1,d1                           ; plane 1's
	addx.w	d4,d4
	add.w	d2,d2                           ; plane 2's
	addx.w	d4,d4
	add.w	d3,d3                           ; plane 3's
	addx.w	d4,d4
	dbra	d5,picture_pixel                ; for each pixel
	move.w	d4,-(a1)                        ; the 4 pixels' word, from the end
	dbra	d6,picture_word                 ; for each word
	addq.w	#8,a1                           ; the next group
	dbra	d7,picture_group                ; for each group
	move.w	#$1,picture_converted           ; converted
picture_convert_done:
	rts
picture_any_length:
	add.l	d0,d1                           ; the length
	moveq	#1,d7
	and.l	d1,d7                           ; odd?
	bne.s	not_a_picture                   ; yes: not a picture
	moveq	#7,d7                           ; the header: what is over whole groups
	and.l	d1,d7
	move.l	#$80000,d0                      ; over $80000 bytes?
	cmp.l	d0,d1
	ble.s	picture_header_done             ; no
	move.l	d1,d7                           ; yes: the header is all but the last $80000
	sub.l	d0,d7
picture_header_done:
	sub.l	d7,d1                           ; less the header
	lsr.l	#3,d1                           ; the groups
	subq.l	#1,d1                           ; less 1
	bmi.s	not_a_picture                   ; none: not a picture
	exg	d7,d1                           ; d7 = the count, d1 = the header
	bra.s	picture_set_groups              ; convert
not_a_picture:
	lea	text_not_picture(pc),a0         ; the '-' mark
	bsr.w	print_text                      ; print
	bra.s	picture_convert_done
window:	; from: menu, ask_window, crunch
	dc.l	$00001580                       ; the window: how far back strings are looked for, $1580 at the start;
                                                ;   Set Parameters sets 5 to $1528

;------------------------------------------------------------------------------
; Take $30010 bytes for the string index; match_table is negative when there is not enough memory.
;------------------------------------------------------------------------------
alloc_match_table:	; from: menu
	pea	$30010                          ; Malloc($30010)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bgt.s	match_table_set                 ; yes
	moveq	#-1,d0                          ; no: none
match_table_set:	; from: free_match_table
	move.l	d0,match_table                  ; kept
	rts

free_match_table:	; from: menu
	move.l	match_table(pc),d0              ; the index
	move.w	#$ffff,match_table              ; none any more
	tst.l	d0                              ; was there one?
	bmi.s	match_table_set                 ; no
	beq.s	match_table_set                 ; 0: none
	move.l	d0,-(sp)                        ; yes: Mfree
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	tst.l	d0                              ; the flags
	rts

;------------------------------------------------------------------------------
; The packer: source/file_length to dest as 'ICE!', the packed length, the unpacked length, then a bit stream
; that the depacker reads from the end down.  At each position it takes the longest of a run of equal bytes and
; the strings found within window behind (through match_table, or by a plain search when there is none), and
; writes literal counts, offsets and lengths as variable-length codes.  The first bits, read last, say whether the
; data is a converted picture and its group count.  d0 = the packed length.
;------------------------------------------------------------------------------
crunch:	; from: menu
	clr.w	too_many_literals               ; no literal overflow
	clr.l	match_table_base                ; no index yet
	move.l	#$8000,d0                       ; the index is rebuilt every $8000
	sub.l	window(pc),d0                   ; less the window
	move.l	d0,match_table_span             ; bytes
	bsr.w	progress_init                   ; start the progress
	movea.l	source(pc),a0                   ; the source
	move.l	file_length(pc),d0              ; its length
	movea.l	dest(pc),a1                     ; the output
	lea	0(a0,d0.l),a2                   ; the end of the source
	move.l	a2,source_end
	move.l	#$49434521,d7                   ; 'ICE!'
	bsr.w	put_long                        ; written
	addq.l	#4,a1                           ; the packed length later
	move.l	file_length(pc),d7              ; the unpacked length
	bsr.w	put_long                        ; written
	moveq	#0,d5                           ; no literals yet
	moveq	#7,d6                           ; 8 bits to go in the byte
	moveq	#0,d7                           ; the bit byte
	move.w	picture_converted(pc),d1        ; a converted picture?
	beq.s	crunch_picture_flag             ; no: a 0 bit
	moveq	#0,d1
	move.w	picture_groups(pc),d0           ; the group count
	cmp.w	#$f9f,d0                        ; a screen's?
	beq.s	crunch_count_flag               ; yes: a 0 bit
	move.w	d0,d1                           ; no: the count in 16 bits
	moveq	#15,d4                          ; 16 bits
	bsr.w	put_bits                        ; written
	moveq	#1,d1                           ; then a 1 bit
crunch_count_flag:
	moveq	#0,d4                           ; 1 bit
	bsr.w	put_bits                        ; written
	moveq	#1,d1                           ; then the picture bit, 1
crunch_picture_flag:
	moveq	#0,d4                           ; 1 bit
	bsr.w	put_bits                        ; written
crunch_loop:
	bsr.w	progress                        ; the progress
	lea	$409(a0),a4                     ; the longest run
	cmpa.l	source_end(pc),a4               ; past the end?
	ble.s	crunch_run                      ; no
	movea.l	source_end(pc),a4               ; yes: to the end
crunch_run:
	movea.l	a0,a3
	move.b	(a3)+,d0                        ; the byte
crunch_run_loop:
	cmp.b	(a3)+,d0                        ; the same?
	bne.s	crunch_run_end                  ; no
	cmpa.l	a4,a3                           ; at the limit?
	blt.s	crunch_run_loop                 ; no: on
crunch_run_end:
	move.l	a3,d1
	sub.l	a0,d1
	subq.l	#2,d1                           ; the run's length
	move.l	d1,run_length                   ; kept
	cmp.l	#$409,d1                        ; the longest?
	beq.w	crunch_code_run                 ; yes: code it as a string
	movea.l	a0,a3                           ; the window's end
	adda.l	window(pc),a3
	cmpa.l	source_end(pc),a3               ; past the end?
	ble.s	crunch_search                   ; no
	movea.l	source_end(pc),a3               ; yes: to the end
crunch_search:
	moveq	#1,d4                           ; the best length so far
	lea	2(a0),a4                        ; where the search starts
	tst.w	match_table                     ; an index?
	bmi.w	plain_search                    ; no: plain search
	move.l	a3,-(sp)
	movea.l	match_table_base(pc),a6         ; where it was built
	move.l	a0,d0
	sub.l	a6,d0                           ; how far since
	cmp.l	match_table_span(pc),d0         ; far enough to rebuild?
	blt.w	crunch_index                    ; no
	movea.l	a0,a6                           ; yes: from here
	move.l	a0,match_table_base             ; kept
	movea.l	match_table(pc),a2              ; the index
	bsr.w	index_counts                    ; the counts and the list starts
	movea.l	a2,a4
	adda.l	#$20002,a4                      ; past the counts: the position lists
	lea	1(a6),a5                        ; the pairs
	moveq	#0,d0                           ; the position
	moveq	#0,d1
	moveq	#0,d2
	move.l	source_end(pc),d3               ; the positions to index
	sub.l	a0,d3                           ; left
	cmp.l	#$8000,d3                       ; up to $8000
	ble.s	index_fill                      ; no more
	move.w	#$8000,d3                       ; else $8000
index_fill:
	movep.w	-$1(a5),d1                      ; a pair of bytes
	move.b	(a5)+,d1
	movea.l	d1,a3
	adda.l	a3,a3                           ; words
	adda.l	a2,a3                           ; its slot
	move.w	(a3),d2                         ; where its list fills
	addq.w	#2,(a3)                         ; on
	move.w	d0,0(a4,d2.l)                   ; its position
	addq.w	#1,d0                           ; the next
	cmp.w	d3,d0                           ; all?
	bne.s	index_fill                      ; no: on
	bsr.w	index_counts                    ; the list starts again
crunch_index:
	move.l	a0,d0                           ; this position
	sub.l	a6,d0                           ; from the base
	movea.l	match_table(pc),a3              ; the index
	moveq	#0,d3
	movep.w	0(a0),d3                        ; the pair here
	move.b	1(a0),d3
	add.l	d3,d3                           ; words
	movea.l	a3,a2
	adda.l	#$20002,a2                      ; the lists
	movea.l	a2,a4
	moveq	#0,d1
	move.w	0(a3,d3.l),d1                   ; this pair's list
	adda.l	d1,a2
index_find_self:
	moveq	#0,d0
	move.w	(a2)+,d0                        ; a position
	add.l	a6,d0                           ; + the base
	cmp.l	a0,d0                           ; this one?
	bne.s	index_find_self                 ; no: on
	move.l	a2,d0
	sub.l	a4,d0                           ; the list offset
	move.w	d0,0(a3,d3.l)                   ; the list starts after it next time
	movea.l	(sp)+,a3
index_next:
	tst.w	match_table                     ; the index?
	bmi.s	plain_search                    ; gone: plain search
	movea.l	match_table_base(pc),a4         ; the base
	adda.w	(a2)+,a4                        ; + the next position in the list
	cmpa.l	a4,a3                           ; inside the window?
	ble.w	crunch_choose                   ; no: done
	move.b	(a4)+,d0
	cmp.b	(a0),d0                         ; the first byte
	bne.w	crunch_choose                   ; no: done
	move.b	(a4),d1
	cmp.b	1(a0),d1                        ; the second
	bne.w	crunch_choose                   ; no: done
	bra.s	compare_string                  ; a match
plain_search:
	move.b	(a0),d0                         ; the first two bytes
	move.b	1(a0),d1
plain_search_loop:
	cmp.b	(a4)+,d0                        ; the first?
	beq.s	plain_search_second             ; yes
plain_search_next:
	cmpa.l	a4,a3                           ; inside the window?
	bgt.s	plain_search_loop               ; yes: on
	bra.s	crunch_choose                   ; no: done
plain_search_second:
	cmp.b	(a4),d1                         ; the second?
	bne.s	plain_search_next               ; no: on
compare_string:
	movea.l	a4,a6
	subq.w	#1,a6                           ; the match
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
	addq.l	#1,d2                           ; the offset
	move.l	#$409,d0                        ; the longest length
	cmp.l	d0,d4                           ; have it already?
	beq.s	crunch_choose                   ; yes: done
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
	bgt.w	index_next                      ; yes: the next
crunch_choose:
	move.l	run_length(pc),d0               ; the run
	cmp.w	#$1,d0                          ; 1 or less?
	ble.s	crunch_code                     ; no run
	cmp.l	d4,d0                           ; longer than the string?
	bge.s	crunch_code_run                 ; yes: code the run
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
	subq.w	#1,literal_check                ; time to check?
	bpl.s	crunch_next                     ; no
	moveq	#-50,d0                         ; 50 bytes in hand
	add.l	a0,d0                           ; the input
	sub.l	a1,d0                           ; less the output
	bmi.s	crunch_tail                     ; the output caught up: stop
	move.w	d0,literal_check                ; the next check
	bra.s	crunch_next
crunch_code_run:
	move.l	run_length(pc),d1               ; the run
	move.w	d1,match_length                 ; its length
	moveq	#0,d0                           ; offset 0
	subq.l	#2,d1
	bne.s	crunch_string                   ; more than 2: a string
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
	adda.w	d0,a0                           ; past the string
crunch_next:
	move.l	source_end(pc),d0               ; the end
	sub.l	a0,d0
	subq.l	#3,d0                           ; 3 or more left?
	bpl.w	crunch_loop                     ; yes: on
crunch_tail:
	cmpa.l	source_end(pc),a0               ; the end?
	bge.s	crunch_end                      ; yes
	move.b	(a0)+,(a1)+                     ; copy the rest
	addq.l	#1,d5                           ; as literals
	bra.s	crunch_tail
crunch_end:
	bsr.w	put_literal_count               ; the literal count
	bset	d6,d7                           ; the end marker bit
	move.b	d7,(a1)+                        ; the last bits
	suba.l	dest(pc),a1                     ; the packed length
	move.l	a1,d0
	move.l	d0,d7
	movea.l	dest(pc),a1                     ; the output
	addq.l	#4,a1                           ; after the magic
	bsr.w	put_long                        ; the packed length
	rts

;------------------------------------------------------------------------------
; The code writers: each sets d1 = the bits and d4 = their count - 1 and goes to put_bits.  The literal count:
; a run of up to $810d literals; longer and the packing is given up (the end moved here).
;------------------------------------------------------------------------------
put_literal_count:	; from: crunch
	cmp.l	#$810d,d5                       ; too long?
	bls.s	literal_count_range             ; no
	move.w	#$ffff,too_many_literals        ; yes: give up
	move.l	a0,source_end                   ; here
literal_count_range:
	lea	literal_bits(pc),a3             ; the bases
	moveq	#6,d3                           ; 7 ranges
literal_count_find:
	move.w	-(a3),d4                        ; the range's start
	cmp.w	d4,d5                           ; in this range?
	dbge	d3,literal_count_find           ; no: the one below
	sub.w	d4,d5                           ; less its start
	add.w	d3,d3                           ; bytes
	lea	literal_bits(pc),a3             ; the bits table
	adda.w	d3,a3                           ; the range's entry
	move.b	(a3)+,d2                        ; the prefix
	ext.w	d2
	moveq	#-1,d1
	lsl.l	d2,d1                           ; its ones
	or.w	d5,d1                           ; the count
	moveq	#0,d5                           ; no literals
	move.b	(a3)+,d4                        ; the bit count
	ext.w	d4
	subq.w	#1,d4                           ; less 1
	bra.w	put_bits                        ; write them
literal_bases:
	dc.w	$0000,$0001,$0002,$0005,$0008,$000f,$010e ; the literal counts the ranges start at
literal_bits:
	dc.b	$01,$01,$01,$02,$02,$04,$02,$06,$03,$09,$08,$11,$0f,$20 ; each range's prefix length and bit count

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
	bra.s	put_bits                        ; write them
length_table:
	dc.b	$02,$03,$04,$06,$0a,$01,$01,$02,$03,$0a ; range starts, then bit counts

put_bits:	; from: crunch, put_literal_count, put_offset, put_short_offset, put_length
	lsr.l	#1,d1                           ; a bit
	roxr.b	#1,d7                           ; into the byte
	dbra	d6,put_bits_next                ; full?
	move.b	d7,(a1)+                        ; yes: write it
	moveq	#0,d7                           ; a new byte
	moveq	#7,d6                           ; 8 bits
put_bits_next:
	dbra	d4,put_bits                     ; for each bit
	rts

put_long:	; from: crunch
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
; Clear the index's pair counts, count the pairs of the $8000 bytes from a6, and turn the counts into the start
; of each pair's list (2 bytes a position).
;------------------------------------------------------------------------------
index_counts:	; from: crunch
	lea	(a2),a4                         ; the index
	clr.w	(a4)+                           ; the first slot
	move.w	#$fff,d0                        ; 64 K of them
	moveq	#0,d1
clear_counts:
	move.l	d1,(a4)+                        ; cleared
	move.l	d1,(a4)+
	move.l	d1,(a4)+
	move.l	d1,(a4)+
	move.l	d1,(a4)+
	move.l	d1,(a4)+
	move.l	d1,(a4)+
	move.l	d1,(a4)+
	dbra	d0,clear_counts                 ; for each 32 bytes
	lea	2(a2),a4                        ; the counts
	lea	1(a6),a5                        ; the pairs
	move.w	#$7fff,d0                       ; 32 K
	moveq	#0,d1
count_pair:
	movep.w	-$1(a5),d1                      ; a pair
	move.b	(a5)+,d1
	movea.l	d1,a3
	adda.l	a3,a3                           ; words
	addq.w	#2,0(a4,a3.l)                   ; counted (2 bytes a position)
	dbra	d0,count_pair                   ; for each position
	clr.w	-(a4)                           ; the first slot starts at 0
	move.w	#$1fff,d0                       ; $10000 slots, 8 at a time
sum_counts:
	move.w	(a4)+,d1                        ; each slot + all before it
	add.w	d1,(a4)
	move.w	(a4)+,d1
	add.w	d1,(a4)
	move.w	(a4)+,d1
	add.w	d1,(a4)
	move.w	(a4)+,d1
	add.w	d1,(a4)
	move.w	(a4)+,d1
	add.w	d1,(a4)
	move.w	(a4)+,d1
	add.w	d1,(a4)
	move.w	(a4)+,d1
	add.w	d1,(a4)
	move.w	(a4)+,d1
	add.w	d1,(a4)
	dbra	d0,sum_counts                   ; for each 8
	rts

;------------------------------------------------------------------------------
; Pack-Ice's program stub, written in front of a packed program by save_packed: a PRG header whose text is the
; stub and the packed data and whose BSS leaves room for the program, then code that depacks the program 120
; bytes past the packed data's start, relocates it to run at the stub's own text, sets the basepage's lengths,
; and runs a mover placed past the BSS that copies it down, clears its BSS and starts it.
;------------------------------------------------------------------------------
stub:	; from: save_packed
	bra.s	stub_text                       ; the PRG magic $601a (bra.s past the header)
stub_text_length:	; from: save_packed
	dc.l	$0000019e                       ; text length: patched
	dc.l	$00000000                       ; data length
stub_bss_length:	; from: save_packed
	dc.l	$00000000                       ; BSS length: patched
	dc.l	$00000000                       ; symbols
	dc.l	$00000000                       ; reserved
	dc.l	$00000001                       ; flags: fast load
	dc.w	$ffff                           ; no relocation
stub_text:
	bra.s	stub_start                      ; over the name
	dc.b	'Pack-Ice'
stub_start:
	lea	stub_text+$216(pc),a4           ; a4 = where the program depacks to: 120 bytes past the packed data,
                                                ;   which follows the stub's $19e bytes of text
	movea.l	a4,a5
stub_packed_end:
	adda.l	#$deadface,a5                   ; a5 = the end of the packed data: the immediate is patched
	movea.l	a4,a6
stub_unpacked_end:
	adda.l	#$fadedead,a6                   ; a6 = the end of the depacked program: patched
	bsr.w	stub_depack                     ; depack
	movea.l	4(sp),a5                        ; a5 = the basepage
	lea	stub_text(pc),a6                ; a6 = where the program will run
	lea	$1c(a4),a3                      ; a3 = its depacked text
stub_relocate:	; from: start, menu
	movem.l	-$1a(a3),d0-d3                  ; its text, data, BSS and symbol lengths (a bra.s past the relocation
                                                ;   when it is off)
	lea	0(a3,d0.l),a0                   ; past the text
	adda.l	d1,a0                           ; and the data
	adda.l	d3,a0                           ; a0 = the relocation table
	move.l	a6,d0                           ; where it will run
	move.l	(a0)+,d1                        ; the first address
	beq.s	stub_relocated                  ; none
	adda.l	d1,a3                           ; the first long
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
	lea	2(a4),a3                        ; the depacked header's lengths
	addq.l	#8,a5                           ; the basepage's text address
	movea.l	(a5)+,a2                        ; a2 = it
	moveq	#0,d2
	sub.l	a2,d2                           ; d2 = less it
	move.l	(a3),(a5)+                      ; the text length
	adda.l	(a3)+,a2
	move.l	a2,(a5)+                        ; the data address
	move.l	(a3),(a5)+                      ; the data length
	adda.l	(a3)+,a2
	add.l	a2,d2                           ; d2 = the text and data length
	move.l	a2,(a5)+                        ; the BSS address
	move.l	(a3),(a5)+                      ; the BSS length
	adda.l	(a3)+,a2                        ; past the BSS
	lea	$2c6(a2),a2                     ; + $2c6
	movem.l	stub_mover(pc),d0-d1/d3-d5/a0-a1/a3 ; the mover
	movem.l	d0-d1/d3-d5/a0-a1/a3,(a2)       ; put there
	lea	$1c(a4),a1                      ; the depacked text
	lsr.l	#3,d2                           ; in 8 byte steps
	movea.l	a6,a3                           ; where it runs
	jmp	(a2)                            ; run the mover
stub_mover:
	move.l	(a1)+,(a3)+                     ; copy 8 bytes
	move.l	(a1)+,(a3)+
	subq.l	#1,d2
	bpl.s	stub_mover                      ; for each 8 bytes
stub_clear_bss:	; from: start, menu
	movea.l	-$e8(a6),a3                     ; the BSS (a bra.s past the clearing when it is off)
	move.l	-$e4(a6),d1                     ; its length
	lsr.l	#3,d1                           ; in 8 byte steps
	suba.l	a0,a0                           ; a 0
stub_clear_loop:
	move.l	a0,(a3)+                        ; clear 8 bytes
	move.l	a0,(a3)+
	subq.l	#1,d1
	bpl.s	stub_clear_loop                 ; for each 8 bytes
	jmp	(a6)                            ; run the program

stub_depack:	; from: stub
	move.b	-(a5),d7                        ; the first bits
stub_literals:	; from: stub_get_bits
	bsr.s	stub_get_bit                    ; a literal run?
	bcc.s	stub_literals_done              ; no: a string
	moveq	#0,d1
	bsr.s	stub_get_bit                    ; one literal?
	bcc.s	stub_copy_literals              ; yes
	lea	stub_literal_bases(pc),a1       ; the run length codes
	moveq	#4,d3                           ; 5 sizes
stub_literal_size:
	move.l	-(a1),d0                        ; bits and all-ones value
	bsr.s	stub_get_bits                   ; read the bits
	swap	d0                              ; the all-ones value
	cmp.w	d0,d1                           ; all ones: the next size
	dbne	d3,stub_literal_size
	add.l	$14(a1),d1                      ; + the size's base
stub_copy_literals:
	move.b	-(a5),-(a6)                     ; copy a literal
	dbra	d1,stub_copy_literals           ; for each literal
stub_literals_done:
	cmpa.l	a4,a6                           ; all depacked?
	bgt.s	stub_string                     ; no: a string
	rts

stub_get_bit:	; from: stub_depack, stub_get_bits
	add.b	d7,d7                           ; the next bit
	bne.s	stub_get_bit_done               ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7                           ; the marker bit in
stub_get_bit_done:
	rts

stub_get_bits:	; from: stub_depack
	moveq	#0,d1                           ; d1 = d0+1 bits
stub_get_bits_loop:
	add.b	d7,d7                           ; the next bit
	bne.s	stub_get_bits_next              ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7                           ; the marker bit in
stub_get_bits_next:
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
	bpl.s	stub_copy_string
	sub.w	d4,d1
	bra.s	stub_copy_string
stub_short_offset:
	moveq	#0,d1
	moveq	#5,d0                           ; 6 bits
	moveq	#-1,d2                          ; base -1
	bsr.s	stub_get_bit                    ; 9 bits?
	bcc.s	stub_short_offset_bits          ; no
	moveq	#8,d0                           ; yes
	moveq	#63,d2                          ; base 63
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
	dc.l	$7fff000e,$00ff0007,$00070002,$00030001 ; bits and all-ones values of the run length codes
	dc.l	$00030001
stub_literal_bases:	; from: stub_depack
	dc.l	$0000010d,$0000000e,$00000007,$00000004 ; the run lengths they start at, less 1
	dc.l	$00000001
stub_length_table:
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; extra bits, then base lengths
stub_offset_table:
	dc.b	$0b,$04,$07,$00                 ; offset bits, then base offsets
	dc.w	$011f,$ffff,$001f

;------------------------------------------------------------------------------
; Pack-Ice's depacker, for the verify: depacks 'ICE!' data at a0 where it is, and turns a converted picture's
; nibbles back into planes.  It depacks 120 bytes higher, keeping the 120 bytes it overwrites past the end in its
; stack frame, then moves the data down and puts them back.  d0 = the unpacked length.
;------------------------------------------------------------------------------
ice_depack:	; from: menu
	link	a3,#-120                        ; 120 bytes of frame
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	lea	$78(a0),a4                      ; the output, 120 bytes on
	movea.l	a4,a6                           ; a6 = the output
	bsr.w	depack_get_long                 ; the magic
	cmpi.l	#$49434521,d0                   ; 'ICE!'?
	bne.w	depack_done                     ; no: nothing to do
	bsr.s	depack_get_long                 ; the packed length
	lea	-$8(a0,d0.l),a5                 ; a5 = the end of the packed data
	bsr.s	depack_get_long                 ; the unpacked length
	move.l	d0,(sp)                         ; returned in d0
	adda.l	d0,a6                           ; a6 = the end of the output
	movea.l	a6,a1                           ; the end
	moveq	#119,d0                         ; 120 bytes
depack_save:
	move.b	-(a1),-(a3)                     ; kept in the frame
	dbra	d0,depack_save
	movea.l	a6,a3                           ; a3 = the end
	move.b	-(a5),d7                        ; the first bits
	bsr.s	depack_literals                 ; depack
	movea.l	a3,a5                           ; the end of the depacked data
	bsr.w	depack_get_bit                  ; a converted picture?
	bcc.s	depack_move                     ; no
	move.w	#$f9f,d7                        ; a screen: 4000 groups
	bsr.w	depack_get_bit                  ; another count?
	bcc.s	depack_picture_group            ; no
	moveq	#15,d0                          ; yes: 16 bits
	bsr.w	depack_get_bits                 ; read
	move.w	d1,d7                           ; the count
depack_picture_group:
	moveq	#3,d6                           ; 4 words
depack_picture_word:
	move.w	-(a3),d4                        ; a word of 4 pixels
	moveq	#3,d5                           ; 4 pixels
depack_picture_pixel:
	add.w	d4,d4                           ; a bit to plane 0
	addx.w	d0,d0
	add.w	d4,d4                           ; plane 1
	addx.w	d1,d1
	add.w	d4,d4                           ; plane 2
	addx.w	d2,d2
	add.w	d4,d4                           ; plane 3
	addx.w	d3,d3
	dbra	d5,depack_picture_pixel         ; for each pixel
	dbra	d6,depack_picture_word          ; for each word
	movem.w	d0-d3,(a3)                      ; the 4 planes
	dbra	d7,depack_picture_group         ; for each group
depack_move:
	movem.l	(sp),d0-d7/a0-a3                ; the length, the start, a3 = the frame
depack_move_loop:
	move.b	(a4)+,(a0)+                     ; move it down 120 bytes
	subq.l	#1,d0
	bne.s	depack_move_loop                ; for each byte
	moveq	#119,d0                         ; 120 bytes
depack_restore:
	move.b	-(a3),-(a5)                     ; put back
	dbra	d0,depack_restore
depack_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	unlk	a3
	rts

depack_get_long:	; from: ice_depack
	moveq	#3,d1                           ; 4 bytes
depack_get_long_loop:
	lsl.l	#8,d0
	move.b	(a0)+,d0                        ; a byte in
	dbra	d1,depack_get_long_loop         ; for each byte
	rts

depack_literals:	; from: ice_depack, depack_get_bits
	bsr.s	depack_get_bit                  ; a literal run?
	bcc.s	depack_literals_done            ; no: a string
	moveq	#0,d1
	bsr.s	depack_get_bit                  ; one literal?
	bcc.s	depack_copy_literals            ; yes
	lea	depack_literal_bases(pc),a1     ; the run length codes
	moveq	#4,d3                           ; 5 sizes
depack_literal_size:
	move.l	-(a1),d0                        ; bits and all-ones value
	bsr.s	depack_get_bits                 ; read the bits
	swap	d0                              ; the all-ones value
	cmp.w	d0,d1                           ; all ones: the next size
	dbne	d3,depack_literal_size
	add.l	$14(a1),d1                      ; + the size's base
depack_copy_literals:
	move.b	-(a5),-(a6)                     ; copy a literal
	dbra	d1,depack_copy_literals         ; for each literal
depack_literals_done:
	cmpa.l	a4,a6                           ; all depacked?
	bgt.s	depack_string                   ; no: a string
	rts

depack_get_bit:	; from: ice_depack, depack_literals, depack_get_bits
	add.b	d7,d7                           ; the next bit
	bne.s	depack_get_bit_done             ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7                           ; the marker bit in
depack_get_bit_done:
	rts

depack_get_bits:	; from: ice_depack, depack_literals
	moveq	#0,d1                           ; d1 = d0+1 bits
depack_get_bits_loop:
	add.b	d7,d7                           ; the next bit
	bne.s	depack_get_bits_next            ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7                           ; the marker bit in
depack_get_bits_next:
	addx.w	d1,d1                           ; into d1
	dbra	d0,depack_get_bits_loop         ; for each bit
	rts
depack_string:	; from: depack_literals
	lea	depack_length_table(pc),a1      ; the length codes
	moveq	#3,d2                           ; up to 4 bits
depack_length_code:
	bsr.s	depack_get_bit                  ; a bit
	dbcc	d2,depack_length_code           ; until a 0
	moveq	#0,d4
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the extra bits
	ext.w	d0
	bmi.s	depack_length_base              ; none
	bsr.s	depack_get_bits                 ; read them
depack_length_base:
	move.b	6(a1,d2.w),d4                   ; + the base length
	add.w	d1,d4
	beq.s	depack_short_offset             ; length 2: a short offset
	lea	depack_offset_table(pc),a1      ; the offset codes
	moveq	#1,d2                           ; up to 2 bits
depack_offset_code:
	bsr.s	depack_get_bit                  ; a bit
	dbcc	d2,depack_offset_code           ; until a 0
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the offset bits
	ext.w	d0
	bsr.s	depack_get_bits                 ; read them
	add.w	d2,d2                           ; words
	add.w	6(a1,d2.w),d1                   ; + the base offset
	bpl.s	depack_copy_string
	sub.w	d4,d1
	bra.s	depack_copy_string
depack_short_offset:
	moveq	#0,d1
	moveq	#5,d0                           ; 6 bits
	moveq	#-1,d2                          ; base -1
	bsr.s	depack_get_bit                  ; 9 bits?
	bcc.s	depack_short_offset_bits        ; no
	moveq	#8,d0                           ; yes
	moveq	#63,d2                          ; base 63
depack_short_offset_bits:
	bsr.s	depack_get_bits                 ; read them
	add.w	d2,d1                           ; + the base
depack_copy_string:
	lea	2(a6,d4.w),a1                   ; the string's source
	adda.w	d1,a1                           ; + the offset
	move.b	-(a1),-(a6)                     ; copy it
depack_copy_string_loop:
	move.b	-(a1),-(a6)
	dbra	d4,depack_copy_string_loop      ; for each byte
	bra.w	depack_literals                 ; and on
depack_literal_table:
	dc.l	$7fff000e,$00ff0007,$00070002,$00030001 ; bits and all-ones values of the run length codes
	dc.l	$00030001
depack_literal_bases:	; from: depack_literals
	dc.l	$0000010d,$0000000e,$00000007,$00000004 ; the run lengths they start at, less 1
	dc.l	$00000001
depack_length_table:
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; extra bits, then base lengths
depack_offset_table:
	dc.b	$0b,$04,$07,$00                 ; offset bits, then base offsets
	dc.w	$011f,$ffff,$001f
	dc.w	$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; Pack-Ice's variables and texts.
;------------------------------------------------------------------------------
dta:	; from: menu
	dcb.b	26,0                            ; Pack-Ice's DTA
file_length:	; from: menu, save_packed, progress_init, print_rate, picture_convert, crunch
	dc.w	$0000,$0000                     ; the DTA's file length: the length to pack
dta_name:	; from: menu, open_file, create_file
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; the DTA's file name
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
text_picture_mark:	; from: menu
	dc.b	'P>',0
text_another:	; from: save_packed
	dc.b	10,13,'Crunch another file (Y/n): ',0
text_relocate:	; from: menu
	dc.b	13,10,10,'Relocate program after depacking (Y/n): ',0
text_picture:	; from: menu
	dc.b	13,10,10,'Additional picture compression (N/y): ',0
text_window_prompt:	; from: ask_window
	dc.b	13,10,'Please enter the offset (Default: $0000'
text_window_prompt_end:	; from: ask_window
	dc.b	'): $',0
text_menu:	; from: menu
	dc.b	10,13,'1) Crunch data file (Default)',10,13,'2) Crunch executable file'
	dc.b	10,13,'3) Set Parameters',10,13,'Please select: ',0
text_no_mem:	; from: menu
	dc.b	'No mem!',0
text_verify:	; from: menu
	dc.b	'    Verify: ',0
text_ok:	; from: menu
	dc.b	'OK! ',0
text_error:	; from: menu
	dc.b	'Error!        [cancelled]',0
text_cannot_pack:	; from: menu
	dc.b	'    Data cannot be packed!  [cancelled]',0
text_remaining:	; from: progress
	dc.b	13,27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C' ; back to the line's start, 24
                                                ;   places right, then "Remaining: xx%"
	dc.b	27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27
	dc.b	'C',27,'C',27,'C',27,'CRemaining: '
remaining_digits:	; from: progress
	dc.b	'99%',0                         ; the percentage left
	dc.b	$00
text_not_picture:	; from: picture_convert
	dc.b	13,27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C-',0 ; back to the line's start, 9
                                                ;   places right, then "-"
text_no_index:	; from: menu
	dc.b	'~',0                           ; "~": packing without the string index
text_time:	; from: print_time
	dc.b	13,27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C' ; back to the line's start, 24
                                                ;   places right, then "Time:" and 10 places back
	dc.b	27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27,'C',27
	dc.b	'C',27,'C',27,'C',27,'CTime:           '
	dc.b	$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$00,$00
text_rate:	; from: print_rate
	dc.b	'  Rate: ',0
text_saving:	; from: print_rate
	dc.b	'% [saving]',0
text_alt:	; from: save_packed
	dc.b	'   <ALT> was pressed. File is skipped.',0
text_larger:	; from: save_packed
	dc.b	'    Larger than original!   [cancelled]',0
banner:	; from: menu
	dc.b	27,'E',27,'f',10
	dc.b	' ~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~'
	dc.b	'-~-~-~-~-~-~-~',13,10
	dc.b	' |   Version 2.40                                               '
	dc.b	'             |',13,10
	dc.b	' {                          P A C K - I C E                     '
	dc.b	'             }',13,10
	dc.b	' |                                                              '
	dc.b	'             |',13,10
	dc.b	' {          This packer was written by Axe of Superior for ST-NE'
	dc.b	'WS           }',13,10
	dc.b	' |          First version: 14.02.1990    Final changes: 14.08.19'
	dc.b	'91           |',13,10
	dc.b	' {                                                              '
	dc.b	'             }',13,10
	dc.b	' ~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~'
	dc.b	'-~-~-~-~-~-~-~',13,10,10,0
	dc.b	$00
alert_menu:	; from: menu
	dc.b	'[0][| What do you wish to pack?  |  - Data files |  - Executable'
	dc.b	' files |  - Set Parameters ][ DATA | EXEC | SETUP ]',0
alert_relocate:	; from: menu
	dc.b	'[0][| Relocate after decrunch?  |  ][ YES | NO ]',0
alert_another:	; from: save_packed
	dc.b	'[2][| Do you wish to pack | another file?|][ YES | NO | ??? ]',0
alert_picture:	; from: menu
	dc.b	'[0][| Do you wish to use an | additional algorithm  | for pictur'
	dc.b	'e compression? |][ NO | YES ]',0
	dc.b	$00

	section	bss
aes_control:	ds.b	32                      ; Pack-Ice's AES arrays: control
aes_global:	ds.b	30
aes_addrin:	ds.b	12
aes_addrout:	ds.b	4
aes_intin:	ds.b	256
aes_intout:	ds.b	768
ap_id:	ds.b	2                               ; Pack-Ice's application id
offset_input:	ds.b	6                       ; Cconrs buffer for the offset: the maximum, the count, 4 characters
gem_mode:	ds.b	2                       ; 1: alerts and the file selector, 0: text (Alternate held at the start,
                                                ;   or a command line)
picture_mode:	ds.b	2                       ; 1: additional picture compression
picture_converted:	ds.b	2               ; 1: the picture's planes were turned into bytes before packing
picture_groups:	ds.b	2                       ; the picture's group count less 1 ($f9f for a screen)
packed_copy:	ds.b	4                       ; the verify's block: a copy of the packed data while it is depacked
                                                ;   where it is, then the file read back
match_table:	ds.b	4                       ; the packer's string index ($30010 bytes), negative for none
match_table_base:	ds.b	4               ; the position the index was last built at
match_table_span:	ds.b	4               ; how far the packer goes before rebuilding the index: $8000 less the
                                                ;   window
relocate_opcode:	ds.b	2               ; the stub's original word at stub_relocate
clear_bss_opcode:	ds.b	2               ; the stub's original word at stub_clear_bss
verify_read_buffer:	ds.b	4               ; where the verify reads the original file back
verify_flag:	ds.b	2                       ; nonzero: verify the written file
elapsed_ticks:	ds.b	4                       ; 200 Hz ticks since the last time_ticks
last_ticks:	ds.b	4                       ; _hz_200 at the last time_ticks
packed_end:	ds.b	4                       ; the end of the packed data, with the stub's length for a program
file_handle:	ds.b	2                       ; the file handle
data_mode:	ds.b	2                       ; 1: packing data, 0: a program
zero_long:	ds.b	8                       ; written after a packed program as its empty relocation table
source:	ds.b	4                               ; the data to pack
source_end:	ds.b	4                       ; its end (moved down when the packer gives up)
dest:	ds.b	4                               ; where the packed data goes
run_length:	ds.b	4                       ; the length of the run of equal bytes at the current position
match_length:	ds.b	2                       ; the best string's length
match_offset:	ds.b	2                       ; and its offset
literal_check:	ds.b	2                       ; literals before the next check that the output has not caught up with
                                                ;   the input
alt_pressed:	ds.b	2                       ; nonzero: Alternate was pressed while packing
too_many_literals:	ds.b	2               ; nonzero: a literal run too long to code
keys_pending:	ds.b	4                       ; the command line's answers still to give (a 0 byte: none)
source_header:	ds.b	28                      ; the source's first 28 bytes: a program's header, for the stub's BSS
path_input:	ds.b	2                       ; Cconrs buffer for the typed name: the maximum and the count, its text
                                                ;   in fsel_path
fsel_path:	ds.b	102                     ; the file selector's path, or the typed name
file_name:	ds.b	20                      ; the name to pack: the file selector's, or the typed one without its
                                                ;   folder
bss_end:

	end
