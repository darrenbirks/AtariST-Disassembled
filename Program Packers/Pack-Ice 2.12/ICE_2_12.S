; ICE_2_12.PRG  -  Pack-Ice 2.12 ("This packer was written by Axe of Superior for ST-NEWS")
; Devpac source of the program, disassembled by Darren Birks, 23 November 2026.
; Text 6022 bytes, data 0 bytes, bss 1296 bytes.
;
; ICE_2_12.PRG as released is this program packed: a $1b2 byte depacker stub with the packed program as its
; data, which ends with the packed and unpacked lengths and 'PUFF'; 4426 bytes.  This is the source of the
; 6131 byte program the stub unpacks;
;   vasmm68k_mot -devpac -m68000 -Ftos -o ICE_2_12.PRG ICE_2_12.S
; rebuilds ICE_2_12.PRG unpacked, byte for byte, header, relocation table and all.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; Pack-Ice 2.12 by Axe of Superior, "First version: 14.02.1990      Final changes: 22.06.1990".  It starts
; with "A special hello goes to those guys who like using this packer."
;
; It is 2.11 with two changes: in text the '3' key now asks for the window (2.11 offered Set Parameters only
; in the alert), and check_alternate returns to start, which calls the menu, instead of running into it.  The
; bit stream, the program stub, the depacker and the file format are 2.11's.
;
; A TOS program that asks its questions with GEM alerts and picks files with the file selector, or in text
; when Alternate is held at its start.  The menu has 1) Crunch data file, 2) Crunch executable file and 3) Set
; Parameters, which sets the window (how far back strings are looked for) in hex, 5 to $1528, the value it
; starts with.  Data can have the additional picture compression; a program can be relocated after depacking
; or not.  Every file matching the name or the selector's mask is packed in turn and saved over itself.
;
; While packing it shows "Remaining: xx%", then the time and the rate.  Alternate held while packing skips the
; file.  Before saving, the packed data is depacked in a block of its own and compared with the file on disk.
;
; Some code is patched while it runs: relocate NO turns stub_relocate and stub_clear_bss into branches over
; their work; save_packed writes the lengths into the stub, and ice_depack patches stub_depack_done.
;
; Some things in it look unfinished:
;   - vdi, a VDI call with its own parameter block, is never called, and vdi_handle is never set.
;   - stub_clear_bss counts its high word in d2, left negative by the copy, so a BSS of 512 K or more is
;     cleared only in part.
;   - text_dest_prompt and the bytes after the DTA are not used.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$0057  the greeting
;   $0058-$0189  start-up, the AES call and the unused VDI call
;   $018a-$0a3f  the menu and the file loop, file calls, input, time, window and progress
;   $0a40-$0aaf  the picture conversion and the window
;   $0ab0-$0cef  the packer, crunch
;   $0cf0-$0f0b  the program stub, with stub_depack
;   $0f0c-$0f89  ice_depack
;   $0f8a-$1785  the variables and texts
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; Packed data: 'Ice!', the packed length (with these 12 bytes), the unpacked length, then a bit stream of longs
; that the depacker reads from the end down.  The first bit written, read last, is 1 for a converted picture.
;
; Packed program: the stub's $21c bytes (a PRG header whose text is the stub's $200 bytes and the bit stream,
; with no relocation), then the bit stream without the 12 byte header, and a 0 long.
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The program starts here: over the greeting to main.
;------------------------------------------------------------------------------
start:
	bra.s	main                            ; over the greeting
greeting:
	dc.b	'A special hello goes to those guys who like using this packer. ('
	dc.b	'You know who you are).'
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
	bsr.w	appl_init
	bsr.w	hide_mouse                      ; hide the mouse
	bsr.w	check_alternate                 ; Alternate held: text, not alerts
	bsr.w	menu                            ; the menu
	bsr.w	show_mouse                      ; show the mouse
	bra.w	appl_exit                       ; appl_exit and quit

appl_init:	; from: start
	move.l	#$a000100,d0                    ; appl_init: opcode 10, 0 intin, 1 intout, 0 addrin
	bsr.w	aes                             ; call
	move.w	d0,ap_id                        ; the application id
	moveq	#-1,d7                          ; exit code -1 if it failed
	addq.w	#1,d0                           ; -1?
	beq.w	quit                            ; yes: quit
	rts
appl_exit:	; from: start
	move.w	d0,d7                           ; the exit code
	move.l	#$13000100,d0                   ; appl_exit: opcode 19, 0 intin, 1 intout, 0 addrin
	bsr.w	aes                             ; call
quit:
	move.w	d7,-(sp)                        ; Pterm with it
	move.w	#$4c,-(sp)
	trap	#1                              ; Pterm

;------------------------------------------------------------------------------
; Pack-Ice's AES call: d0 holds the opcode and the intin, intout and addrin counts, a byte each, made into the
; control array (rsrc_gaddr also gets its addrout).  d0 = intout[0].
;------------------------------------------------------------------------------
aes:	; from: appl_init, menu, alert, show_mouse, hide_mouse
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	lea	control(pc),a0                  ; clear control
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
	dc.l	control                         ; Pack-Ice's AES parameter block: control, global, intin, intout,
                                                ;   addrin, addrout
	dc.l	aes_global
	dc.l	aes_intin
	dc.l	aes_intout
	dc.l	aes_addrin
	dc.l	aes_addrout

;------------------------------------------------------------------------------
; Pack-Ice's VDI call, never called: d0 holds the opcode in its top byte and the ptsin, sub-opcode and intin
; counts in the others (or only the opcode, in the low byte, when the top byte is 0), made into the control
; array with vdi_handle.  d0 = intout[0].
;------------------------------------------------------------------------------
vdi:
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	lea	vdi_ptsin_count(pc),a0          ; the control array from [1]
	clr.w	(a0)+                           ; cleared
	clr.l	(a0)+
	clr.w	(a0)
	move.l	d0,-(sp)                        ; the top byte
	tst.b	(sp)                            ; 0?
	addq.l	#4,sp
	bne.s	vdi_counts                      ; no: all the counts
	move.b	d0,-$7(a0)                      ; yes: only the opcode
	bra.s	vdi_set_handle
vdi_counts:
	move.b	d0,-$5(a0)                      ; ptsin count
	lsr.w	#8,d0
	move.w	d0,2(a0)                        ; sub-opcode
	swap	d0
	move.b	d0,-$1(a0)                      ; intin count
	lsr.w	#8,d0
	move.w	d0,-$8(a0)                      ; the opcode
vdi_set_handle:
	move.w	vdi_handle(pc),4(a0)            ; the handle
	lea	vdi_block(pc),a0                ; the parameter block
	move.l	a0,d1                           ; d1 = it
	moveq	#115,d0                         ; VDI
	trap	#2                              ; AES/VDI
	moveq	#0,d0
	move.w	aes_intout(pc),d0               ; intout[0]
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	rts
vdi_block:
	dc.l	control                         ; Pack-Ice's VDI parameter block: control, intin, ptsin, intout, ptsout
	dc.l	aes_intin
	dc.l	vdi_ptsin
	dc.l	aes_intout
	dc.l	vdi_ptsout

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
	bsr.w	get_key                         ; a key
	cmpi.b	#$33,d0                         ; '3': parameters?
	bne.s	menu_choice                     ; no
	lea	newline(pc),a0                  ; a new line
	bsr.w	print_text                      ; print
	bsr.w	ask_window                      ; ask for the offset
	lea	newline(pc),a0                  ; a new line
	bsr.w	print_text                      ; print
	bra.s	menu_ask                        ; the menu again
menu_button:
	cmpi.b	#$33,d0                         ; '3': SETUP?
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
	move.b	#$0,data_mode                   ; a program
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
	bsr.w	get_key                         ; a key
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
	move.w	#$6034,stub_relocate            ; the stub skips the relocation
	move.w	#$6016,stub_clear_bss           ; and the BSS clearing
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
	bsr.w	get_key                         ; a key
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
	move.b	#$61,(a4)                       ; the drive letter, lower case
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
	move.l	#fsel_path,(a4)+
	move.l	#file_name,(a4)+
	bsr.w	aes                             ; call
	tst.w	d0                              ; all right?
	beq.w	another                         ; no: done
	move.l	aes_intout(pc),d4               ; intout[1] in the low word: the button
	bsr.w	hide_mouse                      ; hide the mouse
	lea	banner(pc),a0                   ; the banner
	bsr.w	print_text                      ; print
	tst.w	d4                              ; OK?
	beq.w	another                         ; no: done
	lea	fsel_path(pc),a2                ; the path
path_scan:
	tst.b	(a2)+                           ; find its end
	bne.s	path_scan
path_backslash:
	cmpi.b	#$5c,-(a2)                      ; back to a \
	beq.s	path_cut                        ; found
	cmpi.b	#$3a,(a2)                       ; the drive's :?
	bne.s	path_backslash                  ; no: on back
	addq.l	#1,a2                           ; yes:
	move.b	#$5c,(a2)                       ; a \ after it
path_cut:
	clr.b	1(a2)                           ; end the path after the \
	lea	fsel_path(pc),a4                ; the path
	cmpi.b	#$3a,1(a4)                      ; a drive?
	bne.s	set_path                        ; no
	moveq	#14,d0                          ; Dsetdrv
	swap	d0
	move.b	(a4),d0                         ; the letter
	ori.b	#$20,d0                         ; lower case
	subi.b	#$61,d0                         ; the drive number
	move.l	d0,-(sp)
	trap	#1                              ; GEMDOS, Dsetdrv
	addq.l	#4,sp
	addq.l	#2,a4                           ; past the drive
set_path:
	pea	(a4)                            ; the folder
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.l	d0                              ; all right?
	bmi.w	another                         ; failed: done
	lea	file_name(pc),a2                ; the name
	tst.b	(a2)                            ; any?
	bne.s	first_file                      ; yes
	move.l	#$2a2e2a00,(a2)                 ; no: "*.*"
	bra.s	first_file                      ; find it
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
	bmi.w	another                         ; no: done
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
working_index:
	tst.w	picture_mode                    ; picture compression?
	beq.s	working_name                    ; no
	lea	text_picture_mark(pc),a0        ; "P>"
	bsr.w	print_text                      ; print
working_name:
	lea	dta_name(pc),a0                 ; the file's name
	bsr.w	print_text                      ; print
	clr.w	alt_pressed                     ; Alternate not pressed
	bsr.w	time_ticks                      ; start the clock
	bsr.w	picture_convert                 ; picture compression
	bsr.w	crunch                          ; pack
	movea.l	d0,a3                           ; a3 = the packed length
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
	bsr.w	ice_depack                      ; depack it
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
; Save the packed file over the original: data as it is; a program as the stub (its text length and the two
; lengths patched in), the packed data without its 12 byte header, and an empty relocation table.
;------------------------------------------------------------------------------
save_packed:	; from: menu
	bsr.w	print_rate                      ; print the rate
	cmpi.b	#$1,data_mode                   ; data?
	beq.s	save_data                       ; yes
	moveq	#12,d0                          ; the 12 byte header
	add.l	d0,dest                         ; left out
	suba.l	d0,a3
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
	lea	stub_packed_end+2(pc),a4        ; the stub's packed end immediate
	move.l	(a4),d0
	add.l	a3,d0                           ; + the packed length
	move.l	d0,(a4)                         ; patched
	move.l	file_length(pc),$a(a4)          ; and the unpacked length
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
	bsr.w	get_key                         ; a key
	ori.b	#$20,d0                         ; lower case
	cmpi.b	#$6e,d0                         ; 'n'?
	beq.s	menu_done                       ; yes: done
	bra.w	menu                            ; no: the menu
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
alternate_held:	; from: check_alternate, progress
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	trap	#13                             ; Kbshift
	addq.l	#4,sp
	btst	#$3,d0                          ; Alternate?
	rts

print_text:	; from: menu, save_packed, print_time, ask_window, progress, print_rate, 1 more
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
	move.b	#$4,(a3)                        ; 4 characters
	pea	(a3)
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
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
; Picture compression: a file of 32000 bytes and a header under $104 bytes is taken to be a low resolution
; screen; its plane words are turned into one nibble per pixel, which packs better.  The depacker turns them
; back.  Anything else is marked with a '-'.
;------------------------------------------------------------------------------
picture_convert:	; from: menu
	clr.w	picture_converted               ; not converted
	tst.w	picture_mode                    ; picture compression?
	beq.s	picture_convert_done            ; no
	movea.l	source(pc),a1                   ; the source
	move.l	file_length(pc),d1              ; its length
	move.l	#$7d00,d0                       ; less 32000
	sub.l	d0,d1
	bmi.s	not_a_picture                   ; shorter: not a picture
	cmp.l	#$104,d1                        ; a header under $104?
	bcc.s	not_a_picture                   ; no: not a picture
	adda.l	d1,a1                           ; past the header
	move.w	#$f9f,d7                        ; 4000 groups of 16 pixels
picture_group:
	movem.w	(a1),d0-d3                      ; the 4 plane words
	moveq	#3,d6                           ; 4 words out
	addq.l	#8,a1                           ; past them
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
	addq.l	#8,a1                           ; the next group
	dbra	d7,picture_group                ; for each group
	move.w	#$1,picture_converted           ; converted
picture_convert_done:
	rts
not_a_picture:
	lea	text_not_picture(pc),a0         ; the '-' mark
	bsr.w	print_text                      ; print
	bra.s	picture_convert_done
window:	; from: ask_window, crunch
	dc.l	$00001528                       ; the window: how far back strings are looked for, $1528 at the start;
                                                ;   Set Parameters sets 5 to $1528

;------------------------------------------------------------------------------
; The packer: source/file_length to dest as 'Ice!', the packed length, the unpacked length, then a bit stream,
; written a long at a time, that the depacker reads from the end down.  At each position it takes the longest
; string found by a plain search within window behind, and writes literal counts, offsets and lengths as
; variable-length codes.  The first bit, read last, says whether the data is a converted picture.  a2 holds the
; end of the source.  d0 = the packed length.
;------------------------------------------------------------------------------
crunch:	; from: menu
	clr.w	too_many_literals               ; no literal overflow
	bsr.w	progress_init                   ; start the progress
	movea.l	source(pc),a0                   ; the source
	move.l	file_length(pc),d0              ; its length
	movea.l	dest(pc),a1                     ; the output
	lea	0(a0,d0.l),a2                   ; a2 = the end of the source
	move.l	#$49636521,d7                   ; 'Ice!'
	bsr.w	put_long                        ; written
	addq.l	#4,a1                           ; the packed length later
	move.l	file_length(pc),d7              ; the unpacked length
	bsr.w	put_long                        ; written
	moveq	#0,d5                           ; no literals yet
	moveq	#31,d6                          ; 32 bits to go in the long
	moveq	#0,d7                           ; the bit long
	moveq	#0,d4                           ; 1 bit
	move.w	picture_converted(pc),d1        ; the picture flag
	bsr.w	put_bits                        ; written
crunch_loop:
	movea.l	a0,a3                           ; the window's end
	adda.l	window(pc),a3
	cmpa.l	a2,a3                           ; past the end?
	ble.s	crunch_search                   ; no
	movea.l	a2,a3                           ; yes: to the end
crunch_search:
	moveq	#1,d4                           ; the best length so far
	lea	2(a0),a4                        ; where the search starts
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
	cmp.l	d0,d4                           ; have it already?
	beq.s	crunch_code                     ; yes: done
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
	bge.s	crunch_end                      ; yes
	move.b	(a0)+,(a1)+                     ; copy the rest
	addq.l	#1,d5                           ; as literals
	bra.s	crunch_tail
crunch_end:
	bsr.w	put_literal_count               ; the literal count
	bset	d6,d7                           ; the end marker bit
	bsr.w	put_long                        ; the last bits
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
	movea.l	a0,a2                           ; here: the end
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
	bra.w	put_bits
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
	bra.s	put_bits
length_table:
	dc.b	$02,$03,$04,$06,$0a,$01,$01,$02,$03,$0a ; range starts, then bit counts

;------------------------------------------------------------------------------
; Write the low d4+1 bits of d1 into the bit long d7, the long to the output each time it fills.
;------------------------------------------------------------------------------
put_bits:	; from: crunch, put_literal_count, put_offset, put_short_offset, put_length
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
	dc.l	$00000000                       ; symbols
	dc.l	$00000000                       ; reserved
	dc.l	$00000001                       ; flags: fast load
	dc.w	$ffff                           ; no relocation
stub_text:
	bra.s	stub_start                      ; over the name
	dc.b	'Pack-Ice'
stub_start:
	lea	stub_text(pc),a4                ; a4 = the stub's text: where the program will run
	lea	(a4),a5                         ; a5 = it
stub_packed_end:
	adda.l	#$200,a5                        ; + $200 and the packed length: the end of the packed data (patched)
	lea	$2e4(a4),a6                     ; a6 = where the program depacks to
stub_unpacked_length:
	move.l	#$0,d7                          ; d7 = the unpacked length: patched
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
	add.l	(a3),d2                         ; + the data
	adda.l	(a3)+,a2
	move.l	a2,(a5)+                        ; the BSS address
	move.l	(a3),(a5)+                      ; the BSS length
	adda.l	(a3)+,a2                        ; past the BSS
	add.l	(a3),d2                         ; + the symbols: d2 = what the mover copies
	adda.l	(a3)+,a2                        ; past the symbols
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
; Depack the bit stream that ends at a5 to a6, d7 bytes; the verify's ice_depack uses it too.  The stream is
; read a long at a time from the end down, a long at an odd address in two parts.
;------------------------------------------------------------------------------
stub_depack:	; from: stub
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	movea.l	a6,a0                           ; a0 = the output's start
	adda.l	d7,a6                           ; a6 = its end
	bsr.s	stub_first_long                 ; the first long

stub_literals:	; from: stub_get_bits, ice_depack
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
	cmpa.l	a0,a6                           ; all depacked?
	bgt.s	stub_string                     ; no: a string
stub_depack_done:	; from: ice_depack
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back (nops while ice_depack uses it)
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
stub_get_bit:	; from: stub_literals, stub_get_bits, ice_depack
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
stub_get_bits:	; from: stub_literals
	moveq	#0,d1                           ; d1 = d0+1 bits
stub_get_bits_loop:
	add.l	d7,d7                           ; the next bit
	beq.s	stub_get_bits_refill            ; none left: refill
stub_get_bits_next:	; from: stub_first_long
	addx.w	d1,d1                           ; into d1
	dbra	d0,stub_get_bits_loop           ; for each bit
	rts
stub_string:	; from: stub_literals
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
	dc.w	$7fff,$000e,$00ff,$0007,$0007,$0002,$0003,$0001 ; bits and all-ones values of the run length codes
	dc.w	$0003,$0001
stub_literal_bases:	; from: stub_literals
	dc.l	$0000010d,$0000000e,$00000007,$00000004 ; the run lengths they start at, less 1
	dc.l	$00000001
stub_length_table:
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; extra bits, then base lengths
stub_offset_table:
	dc.b	$0b,$04,$07,$00                 ; offset bits, then base offsets
	dc.w	$0120,$0000,$0020

;------------------------------------------------------------------------------
; Pack-Ice's depacker, for the verify: depacks 'Ice!' data at a0 to $78 bytes past it with the stub's depacker,
; whose register restore is turned into nops while it runs, and turns a converted screen's nibbles back into
; planes.  d0 = the unpacked length.
;------------------------------------------------------------------------------
ice_depack:	; from: menu
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	cmpi.l	#$49636521,(a0)+                ; 'Ice!'?
	bne.s	depack_done                     ; no: nothing to do
	move.l	(a0)+,d0                        ; the packed length
	lea	-$8(a0,d0.l),a5                 ; a5 = the end of the packed data
	move.l	(a0)+,(sp)                      ; the unpacked length, returned in d0
	adda.w	#$6c,a0                         ; $78 bytes on
	movea.l	a0,a6                           ; a6 = the output
	adda.l	(sp),a6                         ; + the length: its end
	movea.l	a6,a4                           ; a4 = it
	bsr.w	stub_first_long                 ; the first long
	move.l	stub_depack_done(pc),depack_restore_opcode ; keep the depacker's register restore
	move.l	#$4e714e71,stub_depack_done     ; nops in its place
	bsr.w	stub_literals                   ; depack
	move.l	depack_restore_opcode(pc),stub_depack_done ; the restore back
	bsr.w	stub_get_bit                    ; a converted picture?
	bcc.s	depack_done                     ; no
	move.w	#$f9f,d7                        ; 4000 groups of 16 pixels
depack_picture_group:
	moveq	#3,d6                           ; 4 words
depack_picture_word:
	move.w	-(a4),d4                        ; a word of 4 pixels
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
	movem.w	d0-d3,(a4)                      ; the 4 planes
	dbra	d7,depack_picture_group         ; for each group
depack_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts
	dc.w	$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; Pack-Ice's variables and texts.
;------------------------------------------------------------------------------
dta:	; from: menu
	dcb.b	26,0                            ; Pack-Ice's DTA
file_length:	; from: menu, save_packed, progress_init, print_rate, picture_convert, crunch
	dc.l	$00000000                       ; the DTA's file length: the length to pack
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
	dc.b	'      Verify: ',0
text_ok:	; from: menu
	dc.b	'OK! ',0
text_error:	; from: menu
	dc.b	'Error!          [cancelled]',0
text_cannot_pack:	; from: menu
	dc.b	'      Data cannot be packed!  [cancelled]',0
text_remaining:	; from: progress
	dcb.w	45,$1b44                        ; back to the line's start, 24 places right, then "Remaining: xx%"
	dcb.w	24,$1b43
	dc.b	'Remaining: '
remaining_digits:	; from: progress
	dc.b	'99%',0                         ; the percentage left
	dc.b	$00
text_not_picture:	; from: picture_convert
	dcb.w	25,$1b44                        ; back to the line's start, 9 places right, then "-"
	dcb.w	9,$1b43
	dc.w	$2d00
text_time:	; from: print_time
	dcb.w	45,$1b44                        ; back to the line's start, 24 places right, then "Time:" and 10 places
                                                ;   back
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
	dc.b	27,'E',27,'f',10
	dc.b	' ~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~'
	dc.b	'-~-~-~-~-~-~-~',13,10
	dc.b	' |   Version 2.12                                               '
	dc.b	'             |',13,10
	dc.b	' {                              P A C K - I C E                 '
	dc.b	'             }',13,10
	dc.b	' |                                                              '
	dc.b	'             |',13,10
	dc.b	' {                 This packer was written by Axe of Delight.   '
	dc.b	'             }',13,10
	dc.b	' |         First version: 14.02.1990      Final changes: 22.06.1'
	dc.b	'990          |',13,10
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
offset_input:	ds.b	6                       ; Cconrs buffer for the offset: the maximum, the count, 4 characters
gem_mode:	ds.b	2                       ; 1: alerts and the file selector, 0: text (Alternate held at the start)
picture_mode:	ds.b	2                       ; 1: additional picture compression
picture_converted:	ds.b	2               ; 1: the picture's planes were turned into bytes before packing
packed_copy:	ds.b	4                       ; the verify's block: the packed data copied in and depacked there, then
                                                ;   the file read back
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
dest:	ds.b	4                               ; where the packed data goes
source_end:	ds.b	10                      ; the end of the data to pack, for the progress
match_length:	ds.b	2                       ; the best string's length
match_offset:	ds.b	2                       ; and its offset
alt_pressed:	ds.b	2                       ; nonzero: Alternate was pressed while packing
too_many_literals:	ds.b	2               ; nonzero: a literal run too long to code
depack_restore_opcode:	ds.b	4               ; the stub depacker's register restore while ice_depack uses it
fsel_path:	ds.b	80                      ; the file selector's path
name_input:	ds.b	2                       ; Cconrs buffer: the maximum and the count
file_name:	ds.b	20                      ; the name to pack: the file selector's or the typed one
control:	ds.b	2                       ; the AES and VDI control array
vdi_ptsin_count:	ds.b	30              ; control[1] on
aes_global:	ds.b	30
aes_addrin:	ds.b	12
aes_addrout:	ds.b	4
aes_intin:	ds.b	256
aes_intout:	ds.b	256
vdi_ptsin:	ds.b	256
vdi_ptsout:	ds.b	256
ap_id:	ds.b	2                               ; Pack-Ice's application id
vdi_handle:	ds.b	10                      ; the VDI handle (never set)
bss_end:

	end
