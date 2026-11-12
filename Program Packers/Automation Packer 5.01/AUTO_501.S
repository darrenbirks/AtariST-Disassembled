; AUTO_501.PRG  -  Automation Packer 5.01 ("AUTOMATION COMPACTER VERSION 5.0.1"), the GEM version
; Devpac source of the program, disassembled by Darren Birks, 11 November 2026.
; Text 17482 bytes, data 0 bytes, bss 1786 bytes.
;
; AUTO_501.PRG as distributed is packed itself: an 11478 byte JAM Packer 4.0 file ("JAM Packer Decrunch
; V4.0", 'LZH!' data).  This is the source of the 18282 byte program its decruncher unpacks.
;
; This source rebuilds that unpacked program byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o AUTO_501.PRG AUTO_501.S
; It needs PACK501.RSC beside it to run.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; The main dialog credits the code to EGB (Sub Humans in Turkey) and Axe (Superior), and the GEM front end to
; SSR.  It refuses low resolution.  The main menu has PACK/DEPACK PROGRAM, PACK/DEPACK DATA, MULTI FILE
; PACKER, PACK DATA (OFFSET), PREFERENCES, CHUNK PACKER and EXIT PROGRAM.  A file that is packed already is
; depacked instead.
;
; The packing is done by Pack-Ice 2.31 by Axe of Superior (final changes 19.02.1991).  Its whole program is
; assembled in, from ice_program on, but only its packer is used: ice_pack works out three checksums of the
; source for the verify and calls ice_crunch, which calls back show_percent to draw the percentage.  The
; packed data is marked 'AU5!' where Pack-Ice wrote 'ICE!'.  The compaction rate box (1 big and fast to 10
; slow and small) sets the packer's window, $200 to $7000 bytes; BUFFER PACK marks the data 'AU5$'.
;
; After packing, the result is depacked again and its checksums compared (verify_packed), unless VERIFY is
; off in the preferences or there is not room.  A program gets program_stub in front, which depacks,
; relocates and runs it; data can get data_stub and the depacker in front, which depack it to a given
; address and jump to another (CONVERT DATA TO PROGRAM).  CHUNK PACKER packs a file in 4 K to 64 K chunks.
; The multi file packer does all the files of a folder.
;
; Left in but not called: old_pack, the packer of earlier Automation versions; Pack-Ice's own start-up,
; menus and file handling; unused_print_and_wait.
;
; The front end keeps its variables in the text section; the data section is empty.  Some of its code is
; patched while it runs: tree_index, objc_change_redraw, and in the stubs stub_clear_screen, stub_print_trap
; and data_stub_user_call (PRINT HEADER and SUPERVISOR MODE); ice_save patches the lengths into ice_stub.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$1e35  the GEM front end
;   $1e36-$2299  its texts and variables, and its stack
;   $229a-$25dd  program_stub, with au5_depack
;   $25e2-$2695  data_stub
;   $2696-$29af  the AES calls
;   $29b0-$3c59  Pack-Ice 2.31, with ice_stub (its own program stub) and ice_depack
;   $3c5a-$4449  Pack-Ice's variables and texts
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; Packed data: 'AU5!' ('AU5$' for a buffer pack), the packed length, the unpacked length, then a bit stream
; that au5_depack reads from the end down.  The packer's first bit, read last, says whether the planes of a
; picture were turned into bytes before packing.
;
; Chunked file: 'AU5C', the file length, the chunk size, the header's length less 4, then a long for each
; chunk giving where it ends, counted from the header's second long, then the chunks.  A chunk that did not
; pack under 95% of its size is stored as it is.
;
; Packed program: program_stub, $344 bytes (a PRG header with the stub as text and the packed data as data),
; then the packed data.
;
;=======================================================================
; NOTES
;=======================================================================
; - data_to_program copies the first $b0 bytes of data_stub, which end 2 bytes before stub_depacker, where the
;   stub's bsr.s goes, so the call lands 2 bytes into the copied depacker.  main_menu writes $612e to
;   data_stub_user_call, a bsr.s 2 bytes short of super_swap.  Both values fit a stub 2 bytes shorter, as in
;   Automation Packer 2.51, where they are right.
; - Pack-Ice's own verify depacks with ice_depack, which only knows 'ICE!' data.
; - ice_stub_clear_bss counts with d2, which is -1 after the copy, so it clears 8 bytes.
; - pack_chunks reads last_chunk_length, a word, as a long.
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The program starts here.  The variables below sit in the text section, in front of the code.
;------------------------------------------------------------------------------
start:
	bra.w	main                            ; jump over the variables to the start-up code
dest_buffer:	; from: main, reset_buffers
	dc.l	$00080000                       ; where packed files are built: the free memory + $1000, set at start-up
load_buffer:	; from: main, reset_buffers
	dc.l	$00088000                       ; where files are loaded: dest_buffer + $974
text_indexes:	; from: main
	dc.w	$0000,$0015,$001c,$0023,$002a,$0031,$0038,$003f ; rsrc_gaddr R_STRING indexes of the 13 texts written to
	dc.w	$0046,$004d,$005b,$0062,$0069   ; the title lines, progress and result boxes, DEPACK AT, EXECUTE AT and
                                                ;   the offset
version_text:	; from: main
	dc.b	'5.0.1',0                       ; written over the XXXXX of both title lines
no_buffer_pack:	; from: pack_loaded, pack_whole_file, multi_file_packer, choose_rate
	dc.w	$0000                           ; nonzero: BUFFER PACK and NORMAL PACK are shown disabled in the
                                                ;   compaction rate box (programs)
rsc_name:	; from: main
	dc.b	'PACK501.RSC',0
title_position:	; from: main
	dc.b	$1b                             ; VT52 cursor to row 0, column 23, for the title line printed on the
                                                ;   screen
	dc.b	'Y 7',0
	dc.b	$00                             ; pad

;------------------------------------------------------------------------------
; Start-up: shrink the memory to the program, hook the critical error handler, refuse low resolution, load
; PACK501.RSC, find its trees and texts, put the version in the title and print it at the top of the screen,
; note the free memory.
;------------------------------------------------------------------------------
main:	; from: start
	movea.l	sp,a5                           ; a5 = the stack at entry
	lea	program_stub,sp                 ; own stack: the zero bytes below the program stub
	movea.l	4(a5),a5                        ; a5 = the basepage
	move.l	$c(a5),d0                       ; text length
	add.l	$14(a5),d0                      ; + data length
	add.l	$1c(a5),d0                      ; + BSS length
	addi.l	#$100,d0                        ; + the basepage itself
	move.l	d0,d1                           ; d1 = the end of the program, made even (not used)
	add.l	a5,d1
	andi.l	#$fffffffe,d1
	move.l	d0,-(sp)                        ; Mshrink(0, basepage, length)
	move.l	a5,-(sp)
	move.l	#$4a0000,-(sp)                  ; function $4a and the 0 word
	trap	#1                              ; Mshrink
	adda.w	#$c,sp
	pea	hook_critic(pc)                 ; Supexec(hook_critic)
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.w	#6,sp
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.w	#2,sp
	cmp.b	#$0,d0                          ; low resolution?
	bne.s	load_resource                   ; no: go on
	move.w	#$1,aes_intin                   ; yes: the alert's default button 1
	move.l	#alert_low_rez_text,aes_addrin  ; "Low Rez is nice, But, I prefer Medium or High!"
	jsr	form_alert(pc)
	bra.w	quit                            ; and quit
load_resource:
	jsr	rsrc_free(pc)
	move.l	#rsc_name,aes_addrin            ; "PACK501.RSC"
	jsr	rsrc_load(pc)
	cmp.w	#$0,d0                          ; loaded?
	bne.s	find_trees                      ; yes
	move.l	#alert_rsc_text,aes_addrin      ; no: "RSC IS MISSING!!!"
	clr.w	aes_intin                       ; the alert's default button 0
	jsr	form_alert(pc)
	bra.w	quit                            ; and quit
find_trees:
	moveq	#8,d6                           ; 9 trees
	lea	tree_main(pc),a5                ; a5 = the table of tree addresses
find_tree:
	clr.w	aes_intin                       ; type R_TREE
tree_index:
	move.w	#$0,aes_intin+2                 ; tree number: the immediate is counted up below
	jsr	rsrc_gaddr(pc)
	move.l	current_tree,(a5)+              ; keep the tree's address
	addi.w	#$1,tree_index+2                ; next tree number in the instruction above
	dbra	d6,find_tree                    ; for each tree
	moveq	#12,d6                          ; 13 texts
	lea	text_title(pc),a5               ; a5 = the table of text addresses
	lea	text_indexes(pc),a6             ; a6 = their indexes
find_text:
	move.w	#$5,aes_intin                   ; type R_STRING
	move.w	(a6)+,aes_intin+2               ; the text's index
	jsr	rsrc_gaddr(pc)
	move.l	current_tree,(a5)+              ; keep the text's address
	dbra	d6,find_text                    ; for each text
	lea	version_text,a2                 ; a2 = "5.0.1"
	movea.l	text_title,a0                   ; a0 = the main box's title line
	movea.l	text_title2,a1                  ; a1 = the line under it
	adda.l	#$1d,a0                         ; the XXXXX of "AUTOMATION COMPACTER VERSION XXXXX"
	adda.l	#$1d,a1                         ; the same in the second line
	moveq	#4,d1                           ; 5 characters
copy_version:
	move.b	(a2)+,d0                        ; a character of the version
	move.b	d0,(a0)+                        ; into the first title
	move.b	d0,(a1)+                        ; and the second
	dbra	d1,copy_version                 ; for each character
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp
	movea.l	d0,a2                           ; a2 = the screen
	move.w	#$17d,d1                        ; 383 longs: the top lines of the screen
clear_top_lines:
	clr.l	(a2)+                           ; clear them
	dbra	d1,clear_top_lines
	lea	title_position,a0               ; cursor to the top line
	bsr.w	print
	movea.l	text_title,a0                   ; the title line
	bsr.w	print                           ; print it there
	move.w	#$19,-(sp)
	trap	#1                              ; Dgetdrv
	addq.w	#2,sp
	addi.w	#$41,d0                         ; drive number to letter
	move.b	d0,fsel_path                    ; into the file selector's path "A:\*.*"
	clr.l	-(sp)                           ; Malloc(0)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.w	#6,sp
	addi.l	#$1000,d0                       ; + $1000
	move.l	d0,dest_buffer                  ; = where packed files are built
	addi.l	#$974,d0                        ; + $974
	move.l	d0,load_buffer                  ; = where files are loaded
	move.l	#$ffffffff,-(sp)                ; Malloc(-1): the largest free block
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.w	#6,sp
	subi.l	#$8980,d0                       ; less $8980
	move.l	d0,free_memory                  ; = the memory the packer may use, for the verify check
	clr.w	aes_intin                       ; ARROW
	jsr	graf_mouse(pc)

;------------------------------------------------------------------------------
; The main menu.  Each pass clears the chunk, buffer and data flags, puts XXX back in "CHUNK XXX OF XXX",
; restores the stub's call that leaves supervisor mode, resets the buffers and runs the dialog.
;------------------------------------------------------------------------------
main_menu:	; from: pack_one_file, menu_chunk_packer, pack_loaded, save_file
	clr.w	chunk_mode                      ; not chunk packing
	clr.w	buffer_pack                     ; no buffer pack
	clr.w	data_mode                       ; not data packing
	movea.l	text_progress_chunk,a0          ; "CHUNK XXX OF XXX"
	adda.l	#$6,a0                          ; the first XXX
	move.b	#$58,(a0)+                      ; X
	move.b	#$58,(a0)+                      ; X
	move.b	#$58,(a0)+                      ; X
	adda.l	#$4,a0                          ; skip " OF "
	move.b	#$58,(a0)+                      ; X
	move.b	#$58,(a0)+                      ; X
	move.b	#$58,(a0)+                      ; X
	move.w	#$612e,data_stub_user_call      ; the data stub's bsr.s to super_swap again, as $612e (see the notes)
	bsr.w	reset_buffers                   ; reset the buffers and the file type
	move.l	tree_main,current_tree          ; the main box
	jsr	open_dialog(pc)                 ; centre and draw it
	jsr	form_do(pc)
	move.w	d0,d7                           ; d7 = the button chosen
	move.w	d0,aes_intin                    ; deselect it
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	move.w	d7,d0                           ; d0 = the button
	cmp.b	#$4,d0                          ; PACK/DEPACK PROGRAM?
	beq.w	menu_pack_program               ; yes
	cmp.b	#$5,d0                          ; PACK/DEPACK DATA?
	beq.w	menu_pack_data                  ; yes
	cmp.b	#$6,d0                          ; MULTI FILE PACKER?
	bne.s	menu_not_multi                  ; no
	bsr.w	multi_file_packer               ; yes: the multi file packer
	bra.w	main_menu                       ; back to the menu
menu_not_multi:
	cmp.b	#$7,d0                          ; PACK DATA (OFFSET)?
	beq.s	menu_pack_offset                ; yes
	cmp.b	#$8,d0                          ; PREFERENCES?
	bne.s	menu_not_preferences            ; no
	bsr.w	preferences                     ; yes: the preferences
	bra.w	main_menu                       ; back to the menu
menu_not_preferences:
	cmp.b	#$9,d0                          ; CHUNK PACKER?
	beq.w	menu_chunk_packer               ; yes
	cmp.b	#$a,d0                          ; EXIT PROGRAM?
	bne.w	main_menu                       ; no: the menu again

;------------------------------------------------------------------------------
; Quit: put the critical error handler back and end.
;------------------------------------------------------------------------------
quit:	; from: main
	pea	restore_critic(pc)              ; Supexec(restore_critic)
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.w	#6,sp
	clr.w	-(sp)
	trap	#1                              ; Pterm0

;------------------------------------------------------------------------------
; Supervisor routines that swap the critical error handler: while the program runs, disk errors return
; at once instead of showing TOS's alert.
;------------------------------------------------------------------------------
hook_critic:	; from: main
	move.l	$404.w,old_critic               ; etv_critic, keep TOS's handler
	move.l	#critic_handler,$404.w          ; etv_critic, and use the rts below
	rts
restore_critic:	; from: quit
	move.l	old_critic,$404.w               ; etv_critic, TOS's handler back
critic_handler:
	rts                                     ; the handler: return at once
old_critic:
	dc.l	$00000000                       ; TOS's critical error handler

;------------------------------------------------------------------------------
; Super(a0): a0 = 0 enters supervisor mode and returns the old stack; a0 = that stack leaves it again.
;------------------------------------------------------------------------------
super_toggle:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer
	move.l	a0,-(sp)                        ; the stack to use
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.w	#6,sp
	rts
old_ssp:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer
	dc.l	$00000000                       ; the stack Super returned

;------------------------------------------------------------------------------
; The four single-file menu entries.  The file type is 0 (data), 1 (program) or 2 (data packed from an
; offset); PACK/DEPACK DATA also notes data mode.
;------------------------------------------------------------------------------
menu_pack_offset:	; from: main_menu
	move.b	#$2,file_type                   ; file type 2: data from an offset
	bra.s	pack_one_file
menu_pack_program:	; from: main_menu
	move.b	#$1,file_type                   ; file type 1: a program
	bra.w	pack_one_file
menu_pack_data:	; from: main_menu
	move.w	#$1,data_mode                   ; data mode

;------------------------------------------------------------------------------
; Pack or depack one file: choose it, load it, check it, then pack it (or depack it if it is packed already).
;------------------------------------------------------------------------------
pack_one_file:	; from: menu_pack_offset
	bsr.w	file_selector                   ; fsel_input
	tst.w	fsel_ok                         ; OK clicked?
	beq.w	main_menu                       ; no: back to the menu
	bsr.w	make_file_name                  ; make the path and file name
	movea.l	source_ptr,a6                   ; a6 = where to load it
	bsr.w	load_file                       ; load it
	cmp.l	#$0,d7                          ; anything loaded?
	beq.w	main_menu                       ; no: back to the menu
	bsr.w	check_loaded_file               ; check its type and copy it if it is packed
	cmp.l	#$0,d7                          ; right type?
	beq.w	main_menu                       ; no: back to the menu
	cmpi.b	#$ff,packed_flag                ; packed already?
	bne.w	pack_loaded                     ; no: pack it
	move.l	d7,packed_length                ; yes: its length
	pea	depack_loaded(pc)               ; Supexec(depack_loaded)
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.w	#6,sp
	bsr.w	show_file_length                ; the file length into the boxes
	bsr.w	show_packed_length              ; the packed length and percentage too
	move.l	tree_result,current_tree        ; the result box
	move.w	#$7,aes_intin                   ; YES (PROGRAM FILE?)
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	move.w	#$8,aes_intin                   ; NO
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	jsr	open_dialog(pc)                 ; draw it
	jsr	form_do(pc)
	move.w	d0,aes_intin                    ; deselect the exit button
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	bra.w	save_file                       ; save the depacked file

;------------------------------------------------------------------------------
; Depack the loaded file in supervisor mode (the depacker flashes the background colour).
;------------------------------------------------------------------------------
depack_loaded:	; from: pack_one_file
	movea.l	build_ptr,a0                    ; a0 = the packed file (copied to the build buffer)
	movea.l	source_ptr,a1                   ; a1 = where it unpacks: the load buffer
	move.w	$ffff8240,-(sp)                 ; palette 0, keep the background colour
	bsr.w	au5_depack                      ; depack
	move.w	(sp)+,$ffff8240                 ; palette 0, colour back
	move.l	d0,source_length                ; the unpacked length
	rts

;------------------------------------------------------------------------------
; CHUNK PACKER: the file is packed in chunks of a chosen size, each with its own header.  A file that is packed
; already is depacked instead.
;------------------------------------------------------------------------------
menu_chunk_packer:	; from: main_menu
	move.w	#$1,chunk_mode                  ; chunk packing
	bsr.w	file_selector                   ; fsel_input
	tst.w	fsel_ok                         ; OK clicked?
	beq.w	main_menu                       ; no: back to the menu
	bsr.w	make_file_name                  ; make the path and file name
	movea.l	source_ptr,a6                   ; a6 = where to load it
	bsr.w	load_file                       ; load it
	cmp.l	#$0,d7                          ; anything loaded?
	beq.w	main_menu                       ; no: back to the menu
	bsr.w	check_loaded_file               ; check its type and copy it if it is packed
	cmp.l	#$0,d7                          ; right type?
	beq.w	main_menu                       ; no: back to the menu
	cmpi.b	#$ff,packed_flag                ; packed already?
	bne.s	chunk_pack                      ; no: pack it in chunks
	move.l	d7,packed_length                ; yes: its length
	movea.l	build_ptr,a0                    ; a0 = the packed file
	movea.l	source_ptr,a1                   ; a1 = where it unpacks
	move.w	$ffff8240,-(sp)                 ; palette 0, keep the background colour
	bsr.w	au5_depack                      ; depack
	move.w	(sp)+,$ffff8240                 ; palette 0, colour back
	move.l	d0,source_length                ; the unpacked length
	bsr.w	show_file_length                ; the file length into the boxes
	bsr.w	show_packed_length              ; the packed length and percentage
	bsr.w	wait_key                        ; wait for a key
	bra.w	save_file                       ; save the depacked file
chunk_pack:
	move.l	d7,source_length                ; the file length
	bsr.w	show_file_length                ; into the boxes
	cmpi.b	#$2,file_type                   ; data from an offset?
	bne.s	chunk_pack_file                 ; no
	bsr.w	ask_offset                      ; yes: ask for the offset and move the data
	cmp.l	#$0,d7                          ; all right?
	beq.w	main_menu                       ; no: back to the menu

;------------------------------------------------------------------------------
; Pack the loaded file.
;------------------------------------------------------------------------------
pack_loaded:	; from: pack_one_file
	move.l	d7,source_length                ; the file length
	bsr.w	show_file_length                ; into the boxes
	cmpi.b	#$2,file_type                   ; data from an offset?
	bne.w	pack_whole_file                 ; no: pack it
	bsr.w	ask_offset                      ; yes: ask for the offset and move the data
	cmp.l	#$0,d7                          ; all right?
	beq.w	main_menu                       ; no: back to the menu
	bra.w	pack_whole_file                 ; pack it
chunk_pack_file:	; from: menu_chunk_packer
	move.w	#$ffff,no_buffer_pack           ; no buffer pack
	bsr.w	choose_rate                     ; ask for the compaction rate
	bsr.w	choose_chunk_size               ; ask for the chunk size
	bsr.w	pack_in_chunks                  ; pack it in chunks
	cmpi.b	#$1,file_type                   ; a program?
	bne.w	packed_data                     ; no: show the result
	bsr.w	add_program_stub                ; yes: put the program stub in front
	bsr.w	show_packed_length              ; the packed length and percentage
	bsr.w	wait_key                        ; wait for a key
	bra.w	save_file                       ; save it

;------------------------------------------------------------------------------
; Write the number of the chunk being packed, 3 digits, into chunk_digits.
;------------------------------------------------------------------------------
chunk_number_text:	; from: pack_chunks
	clr.l	d3
	move.w	chunk_number,d3                 ; the chunk number
	divu.w	#$64,d3                         ; hundreds
	addi.w	#$30,d3                         ; to a digit
	move.b	d3,chunk_digits
	swap	d3                              ; the remainder
	ext.l	d3
	divu.w	#$a,d3                          ; tens
	addi.w	#$30,d3                         ; to a digit
	move.b	d3,chunk_digits+1
	swap	d3                              ; units
	addi.w	#$30,d3                         ; to a digit
	move.b	d3,chunk_digits+2
	rts

;------------------------------------------------------------------------------
; The chunk size box: 4 K, 8 K, 16 K or 32 K (64 K for any other button).  The limit is 95% of the size.
;------------------------------------------------------------------------------
choose_chunk_size:	; from: pack_loaded, multi_file_packer
	move.l	tree_chunk_size,current_tree    ; the chunk size box
	jsr	open_dialog(pc)                 ; centre and draw it
	jsr	form_do(pc)
	move.w	d0,d7                           ; d7 = the button
	move.w	d0,aes_intin                    ; deselect it
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	move.w	d7,d0                           ; d0 = the button
	cmp.w	#$3,d0                          ; 4 K?
	bne.w	chunk_not_4k                    ; no
	move.l	#$1000,chunk_size               ; yes: 4 K
	bra.s	chunk_size_set
chunk_not_4k:
	cmp.w	#$4,d0                          ; 8 K?
	bne.w	chunk_not_8k                    ; no
	move.l	#$2000,chunk_size               ; yes: 8 K
	bra.w	chunk_size_set
chunk_not_8k:
	cmp.w	#$5,d0                          ; 16 K?
	bne.w	chunk_not_16k                   ; no
	move.l	#$4000,chunk_size               ; yes: 16 K
	bra.w	chunk_size_set
chunk_not_16k:
	cmp.w	#$6,d0                          ; 32 K?
	bne.w	chunk_not_32k                   ; no
	move.l	#$8000,chunk_size               ; yes: 32 K
	bra.w	chunk_size_set
chunk_not_32k:
	move.l	#$10000,chunk_size              ; anything else: 64 K
chunk_size_set:
	move.l	chunk_size,d0                   ; the chunk size
	mulu.w	#$5,d0                          ; 5%
	divu.w	#$64,d0
	move.l	chunk_size,d1                   ; the size
	sub.w	d0,d1                           ; less 5%
	move.l	d1,chunk_limit                  ; = the limit a packed chunk must stay under
	rts

;------------------------------------------------------------------------------
; Pack a file in chunks; a file no longer than one chunk is packed whole, as a buffer pack.
;------------------------------------------------------------------------------
pack_in_chunks:	; from: pack_loaded
	move.l	source_length,d1                ; the file length
	cmp.l	chunk_size,d1                   ; longer than a chunk?
	bgt.w	pack_in_chunks_long             ; yes: chunks
	clr.w	chunk_mode                      ; no: not chunk packing
	move.w	#$1,buffer_pack                 ; buffer pack
	bra.w	pack_whole                      ; pack it whole
pack_in_chunks_long:
	bsr.w	pack_chunks                     ; pack it in chunks
	rts

;------------------------------------------------------------------------------
; The same for the multi file chunk packer, which packs one file at a time without the result box.
;------------------------------------------------------------------------------
pack_in_chunks_multi:	; from: multi_file_packer
	move.l	source_length,d1                ; the file length
	cmp.l	chunk_size,d1                   ; longer than a chunk?
	bgt.w	pack_in_chunks_multi_long       ; yes: chunks
	clr.w	chunk_mode                      ; no: not chunk packing
	move.w	#$1,buffer_pack                 ; buffer pack
	move.l	tree_progress,current_tree      ; the progress box
	jsr	open_dialog(pc)                 ; draw it
	lea	$0,a0                           ; supervisor mode
	bsr.w	super_toggle                    ; Super
	move.l	d0,old_ssp                      ; the old stack
	move.l	source_ptr,d0                   ; the source
	add.l	source_length,d0                ; + its length
	addi.l	#$8000,d0                       ; + 32 K
	andi.l	#$fffffffe,d0                   ; even
	move.l	d0,match_table                  ; = where the verify depacks to
	bsr.w	pack_source                     ; pack
	bsr.w	check_verify_room               ; check the verify fits
	cmpi.b	#$0,verify_off                  ; verify?
	bne.w	multi_whole_packed              ; no
	bsr.w	verify_packed                   ; yes: depack and compare
multi_whole_packed:
	movea.l	old_ssp,a0                      ; the old stack
	bsr.w	super_toggle                    ; back to user mode
	jsr	close_dialog(pc)                ; remove the progress box
	move.w	#$1,chunk_mode                  ; chunk packing again
	move.w	#$1,buffer_pack                 ; buffer pack
	rts
pack_in_chunks_multi_long:
	bsr.w	pack_chunks                     ; pack it in chunks
	rts

;------------------------------------------------------------------------------
; Pack the loaded file chunk by chunk.  The output starts with an 'AU5C' header: 'AU5C', the file length, the
; chunk size and the length of the chunk table, then a table holding the end of each packed chunk, then the
; chunks.  A chunk that does not pack below the limit is stored as it is.
;------------------------------------------------------------------------------
pack_chunks:	; from: pack_in_chunks, pack_in_chunks_multi
	move.l	chunk_size,d2                   ; the chunk size
	divu.w	d2,d1                           ; file length / chunk size
	clr.l	d3                              ; d3 = the number of whole chunks
	move.w	d1,d3
	swap	d1                              ; the remainder
	cmp.w	#$0,d1                          ; any?
	bne.w	chunk_remainder                 ; yes
	swap	d1
	bra.w	chunk_count_set
chunk_remainder:
	swap	d1
	addi.w	#$1,d3                          ; one more chunk for it
chunk_count_set:
	move.w	d3,chunk_count                  ; the number of chunks
	divu.w	#$64,d3                         ; hundreds
	addi.w	#$30,d3                         ; to a digit
	move.b	d3,chunk_count_digits           ; into chunk_count_digits
	swap	d3                              ; the remainder
	ext.l	d3
	divu.w	#$a,d3                          ; tens
	addi.w	#$30,d3                         ; to a digit
	move.b	d3,chunk_count_digits+1
	swap	d3                              ; units
	addi.w	#$30,d3                         ; to a digit
	move.b	d3,chunk_count_digits+2
	subi.w	#$1,d1                          ; the chunks still to pack after the first
	move.w	d1,chunks_left
	swap	d1                              ; the remainder
	move.w	d1,last_chunk_length            ; = the length of the last chunk
	move.w	#$1,chunk_number                ; chunk 1
	bsr.w	chunk_number_text               ; its digits
	move.l	build_ptr,d0                    ; the build buffer
	addi.w	#$4,chunk_count                 ; the chunk count + 4
	move.w	chunk_count,d1
	ext.l	d1
	lsl.l	#2,d1                           ; longs
	sub.l	d1,d0                           ; below the buffer
	movea.l	d0,a0                           ; a0 = the header
	move.l	a0,chunk_header
	move.l	#$41553543,(a0)+                ; 'AU5C'
	move.l	source_length,(a0)+             ; the file length
	move.l	source_length,chunk_file_length ; kept for the end
	move.l	chunk_size,(a0)+                ; the chunk size
	subi.l	#$4,d1                          ; the header length less 4
	move.l	d1,(a0)+
	move.l	a0,chunk_table_ptr              ; where the table starts
	subq.l	#4,build_ptr
	move.l	source_ptr,d0                   ; the source
	add.l	source_length,d0                ; + its length
	addi.l	#$8000,d0                       ; + 32 K
	andi.l	#$fffffffe,d0                   ; even
	move.l	d0,match_table                  ; = where the verify depacks to
	move.l	chunk_size,source_length        ; each chunk is a chunk long
	move.l	tree_progress,current_tree      ; the progress box
	jsr	open_dialog(pc)                 ; draw it
pack_chunk:
	movea.l	text_progress_chunk,a0          ; "CHUNK XXX OF XXX"
	adda.l	#$6,a0
	move.b	chunk_digits,(a0)+              ; the chunk number
	move.b	chunk_digits+1,(a0)+
	move.b	chunk_digits+2,(a0)+
	adda.l	#$4,a0                          ; skip " OF "
	move.b	chunk_count_digits,(a0)+        ; the chunk count
	move.b	chunk_count_digits+1,(a0)+
	move.b	chunk_count_digits+2,(a0)+
	move.w	#$5,aes_intin                   ; the CHUNK text object
	clr.w	aes_intin+2                     ; depth 0
	jsr	objc_draw(pc)
	lea	$0,a0                           ; supervisor mode
	bsr.w	super_toggle                    ; Super
	move.l	d0,old_ssp                      ; the old stack
	bsr.w	pack_source                     ; pack the chunk
	bsr.w	check_verify_room               ; check the verify fits
	cmpi.b	#$0,verify_off                  ; verify?
	bne.w	chunk_packed                    ; no
	bsr.w	verify_packed                   ; yes: depack and compare
chunk_packed:
	movea.l	old_ssp,a0                      ; the old stack
	bsr.w	super_toggle                    ; back to user mode
	addi.w	#$1,chunk_number                ; next chunk number
	bsr.w	chunk_number_text               ; its digits
	move.l	packed_length,d0                ; the packed length
	cmp.l	chunk_limit,d0                  ; below the limit?
	blt.w	chunk_kept_packed               ; yes: keep it packed
	movea.l	source_ptr,a0                   ; no: the chunk as it is
	movea.l	build_ptr,a1                    ; over the packed one
	move.l	chunk_size,d0                   ; the chunk size
	subi.l	#$1,d0
store_chunk:
	move.b	(a0)+,(a1)+                     ; copy it
	dbra	d0,store_chunk
	movea.l	chunk_table_ptr,a0              ; the table
	move.l	chunk_size,d0                   ; the chunk size
	add.l	-$4(a0),d0                      ; + where the last chunk ended
	move.l	d0,(a0)+                        ; = where this one ends
	move.l	a0,chunk_table_ptr
	move.l	build_ptr,d0                    ; the build pointer
	add.l	chunk_size,d0                   ; past the chunk
	move.l	d0,build_ptr
	bra.w	next_chunk
chunk_kept_packed:
	move.l	packed_length,d0                ; the packed length
	movea.l	chunk_table_ptr,a0              ; the table
	add.l	-$4(a0),d0                      ; + where the last chunk ended
	move.l	d0,(a0)+                        ; = where this one ends
	move.l	a0,chunk_table_ptr
	move.l	packed_length,d0                ; the build pointer
	add.l	build_ptr,d0                    ; past the packed chunk
	move.l	d0,build_ptr
next_chunk:
	move.l	source_ptr,d0                   ; the source
	add.l	chunk_size,d0                   ; on a chunk
	move.l	d0,source_ptr
	cmpi.w	#$0,chunks_left                 ; more whole chunks?
	beq.w	last_chunk                      ; no
	subi.w	#$1,chunks_left                 ; yes: one fewer
	bra.w	pack_chunk                      ; and pack it
last_chunk:
	move.w	last_chunk_length,d0            ; the last chunk's length
	ext.l	d0
	move.l	d0,source_length                ; is the length to pack
	cmp.l	#$80,d0                         ; 128 bytes or more?
	blt.w	store_last_chunk                ; no: store it as it is
	movea.l	text_progress_chunk,a0          ; "CHUNK XXX OF XXX"
	adda.l	#$6,a0
	move.b	chunk_digits,(a0)+              ; the chunk number
	move.b	chunk_digits+1,(a0)+
	move.b	chunk_digits+2,(a0)+
	move.w	#$5,aes_intin                   ; the CHUNK text object
	clr.w	aes_intin+2                     ; depth 0
	jsr	objc_draw(pc)
	lea	$0,a0                           ; supervisor mode
	bsr.w	super_toggle                    ; Super
	move.l	d0,old_ssp                      ; the old stack
	bsr.w	pack_source                     ; pack the last chunk
	bsr.w	check_verify_room               ; check the verify fits
	cmpi.b	#$0,verify_off                  ; verify?
	bne.w	last_chunk_packed               ; no
	bsr.w	verify_packed                   ; yes: depack and compare
last_chunk_packed:
	movea.l	old_ssp,a0                      ; the old stack
	bsr.w	super_toggle                    ; back to user mode
	jsr	close_dialog(pc)                ; remove the progress box
	move.l	packed_length,d0                ; the packed length
	cmp.l	last_chunk_length,d0            ; below the chunk's length?
	blt.w	last_chunk_kept_packed          ; yes: keep it packed
store_last_chunk:
	movea.l	source_ptr,a0                   ; the source
	movea.l	build_ptr,a1                    ; the build pointer
	move.l	last_chunk_length,d0            ; the chunk's length
	subi.l	#$1,d0
copy_last_chunk:
	move.b	(a0)+,(a1)+                     ; copy it
	dbra	d0,copy_last_chunk
	move.l	build_ptr,d0                    ; the build pointer
	add.l	last_chunk_length,d0            ; past it
	bra.w	chunks_done
last_chunk_kept_packed:
	move.l	build_ptr,d0                    ; the build pointer
	add.l	packed_length,d0                ; past the packed chunk
chunks_done:
	sub.l	chunk_header,d0                 ; less the start of the header
	move.l	d0,chunk_total                  ; = the length of the whole file
	move.l	chunk_header,build_ptr          ; the file starts at the header
	move.l	chunk_total,packed_length       ; and is this long
	move.l	chunk_file_length,source_length ; the original length again
	rts

;------------------------------------------------------------------------------
; Pack the loaded file in one piece: ask for the compaction rate, pack, verify, add the program stub (programs) or
; ask about the data stub (data), show the result and save.
;------------------------------------------------------------------------------
pack_whole_file:	; from: pack_loaded
	cmpi.w	#$0,data_mode                   ; data mode?
	bne.s	pack_allow_buffer               ; yes
	move.w	#$ffff,no_buffer_pack           ; no: no buffer pack
	bra.s	pack_choose_rate
pack_allow_buffer:
	clr.w	no_buffer_pack                  ; buffer pack allowed
pack_choose_rate:
	bsr.w	choose_rate                     ; ask for the compaction rate
pack_whole:	; from: pack_in_chunks
	move.l	tree_progress,current_tree      ; the progress box
	jsr	open_dialog(pc)                 ; draw it
	lea	$0,a0                           ; supervisor mode
	bsr.w	super_toggle                    ; Super
	move.l	d0,old_ssp                      ; the old stack
	move.l	source_ptr,d0                   ; the source
	add.l	source_length,d0                ; + its length
	addi.l	#$8000,d0                       ; + 32 K
	andi.l	#$fffffffe,d0                   ; even
	move.l	d0,match_table                  ; = where the verify depacks to
	bsr.w	pack_source                     ; pack
	bsr.w	check_verify_room               ; check the verify fits
	cmpi.b	#$0,verify_off                  ; verify?
	bne.w	whole_packed                    ; no
	bsr.w	verify_packed                   ; yes: depack and compare
whole_packed:
	movea.l	old_ssp,a0                      ; the old stack
	bsr.w	super_toggle                    ; back to user mode
	jsr	close_dialog(pc)                ; remove the progress box
	cmpi.b	#$1,file_type                   ; a program?
	bne.s	packed_data                     ; no
	bsr.w	add_program_stub                ; yes: put the program stub in front
	bsr.w	show_packed_length              ; the packed length and percentage
show_result:
	move.l	tree_result,current_tree        ; the result box
	move.w	#$7,aes_intin                   ; YES (PROGRAM FILE?)
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	move.w	#$8,aes_intin                   ; NO
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	jsr	open_dialog(pc)                 ; draw it
	jsr	form_do(pc)
	move.w	d0,aes_intin                    ; deselect the exit button
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	bra.s	save_file                       ; save it
packed_data:	; from: pack_loaded
	bsr.w	show_packed_length              ; the packed length and percentage
	cmpi.b	#$2,file_type                   ; data from an offset?
	bne.s	packed_plain_data               ; no
	bsr.w	add_offset_data                 ; yes: count the data before the offset in
	bra.s	save_file                       ; save it
packed_plain_data:
	cmpi.w	#$1,chunk_mode                  ; chunk packing?
	beq.w	packed_show_result              ; yes: just show the result
	cmpi.w	#$1,buffer_pack                 ; buffer pack?
	beq.w	packed_show_result              ; yes: just show the result
	bsr.w	data_to_program                 ; no: offer the data-to-program stub
	bra.w	save_file                       ; save it
packed_show_result:
	bra.w	show_result                     ; show the result

;------------------------------------------------------------------------------
; Save: choose a name and write the file.  A packed file is written from the build buffer (with an 'AU5$' magic
; for a buffer pack), a depacked one from the load buffer.  A failed write asks again.
;------------------------------------------------------------------------------
save_file:	; from: pack_one_file, menu_chunk_packer, pack_loaded, pack_whole_file
	bsr.w	file_selector                   ; fsel_input
	tst.w	fsel_ok                         ; OK clicked?
	beq.w	main_menu                       ; no: back to the menu
	bsr.w	make_file_name                  ; make the path and file name
	cmpi.b	#$ff,packed_flag                ; depacked?
	bne.s	save_packed                     ; no
	move.l	source_ptr,d7                   ; yes: write from the load buffer
	move.l	source_length,d6                ; the depacked length
	bra.s	save_write
save_packed:
	move.l	build_ptr,d7                    ; the build buffer
	cmpi.w	#$0,buffer_pack                 ; buffer pack?
	beq.w	save_packed_length              ; no
	movea.l	d7,a0                           ; yes:
	move.b	#$24,3(a0)                      ; 'AU5!' becomes 'AU5$'
save_packed_length:
	move.l	packed_length,d6                ; the packed length
save_write:
	bsr.w	write_file                      ; write the file
	cmp.l	d6,d7                           ; all written?
	beq.w	main_menu                       ; yes: back to the menu
	bsr.w	alert_write_error               ; no: "WRITE PROTECTED OR DISK IS FULL OR HAS AN ERROR"
	bra.s	save_file                       ; and choose again

;------------------------------------------------------------------------------
; MULTI FILE PACKER: pick a file in a folder, then every file matching the selector's mask is packed (or
; depacked) and saved under its own name.  MULTI PACK ALL packs programs as well; MULTI PACK (NO PRGS)
; leaves files ending .PRG or .TOS alone; MULTI CHUNK PACK packs every file in chunks.
;------------------------------------------------------------------------------
multi_file_packer:	; from: main_menu
	clr.b	pack_programs                   ; not packing programs
	clr.w	chunk_mode                      ; not chunk packing
	clr.w	buffer_pack                     ; no buffer pack
	move.l	tree_multi,current_tree         ; the multi file box
	jsr	open_dialog(pc)                 ; draw it
	jsr	form_do(pc)
	move.w	d0,d7                           ; d7 = the button
	move.w	d0,aes_intin                    ; deselect it
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	move.w	d7,d0                           ; d0 = the button
	cmp.b	#$2,d0                          ; MULTI PACK ALL?
	beq.s	multi_pack_all                  ; yes
	cmp.b	#$3,d0                          ; MULTI PACK (NO PRGS)?
	beq.s	multi_pack_files                ; yes
	cmp.w	#$4,d0                          ; MULTI CHUNK PACK?
	beq.w	multi_chunk_pack                ; yes
	rts                                     ; MAIN MENU
multi_pack_all:
	move.b	#$ff,pack_programs              ; programs too
	move.w	#$ffff,no_buffer_pack           ; no buffer pack
multi_pack_files:
	bsr.w	file_selector                   ; fsel_input
	tst.w	fsel_ok                         ; OK clicked?
	beq.s	multi_file_packer               ; no: the box again
	bsr.w	find_first_file                 ; find the first file of the folder
	cmpi.b	#$ff,pack_programs              ; packing programs?
	beq.s	multi_choose_rate               ; yes
	clr.w	no_buffer_pack                  ; no: buffer pack allowed
multi_choose_rate:
	bsr.w	choose_rate                     ; ask for the compaction rate
multi_next_file:
	bsr.w	reset_buffers                   ; reset the buffers and the file type
	bsr.w	found_name_to_boxes             ; the found name into the boxes
	bsr.w	make_file_name                  ; make the path and file name
	movea.l	source_ptr,a6                   ; a6 = where to load it
	bsr.w	load_file                       ; load it
	cmp.l	#$0,d7                          ; anything loaded?
	ble.w	multi_file_skip                 ; no: next file
	move.l	d7,source_length                ; the length
	bsr.w	find_file_type                  ; find its type
	cmp.w	#$0,d7                          ; packed already?
	beq.w	multi_file_skip                 ; yes: next file
	bsr.w	check_program_name              ; a .PRG or .TOS name?
	cmpi.b	#$ff,pack_programs              ; packing programs?
	beq.s	multi_pack_file                 ; yes
	cmpi.b	#$1,file_type                   ; a program?
	bne.s	multi_pack_file                 ; no
	bsr.w	pause                           ; yes: skip it after a pause
	bra.w	multi_file_skip                 ; next file
multi_pack_file:
	bsr.w	show_file_length                ; the file length into the boxes
	move.l	tree_progress,current_tree      ; the progress box
	jsr	open_dialog(pc)                 ; draw it
	lea	$0,a0                           ; supervisor mode
	bsr.w	super_toggle                    ; Super
	move.l	d0,old_ssp                      ; the old stack
	move.l	source_ptr,d0                   ; the source
	add.l	source_length,d0                ; + its length
	addi.l	#$8000,d0                       ; + 32 K
	andi.l	#$fffffffe,d0                   ; even
	move.l	d0,match_table                  ; = where the verify depacks to
	bsr.w	pack_source                     ; pack
	bsr.w	check_verify_room               ; check the verify fits
	cmpi.b	#$0,verify_off                  ; verify?
	bne.w	multi_file_packed               ; no
	bsr.w	verify_packed                   ; yes: depack and compare
multi_file_packed:
	movea.l	old_ssp,a0                      ; the old stack
	bsr.w	super_toggle                    ; back to user mode
	jsr	close_dialog(pc)                ; remove the progress box
	cmpi.b	#$1,file_type                   ; a program?
	bne.w	multi_file_data                 ; no
	bsr.w	add_program_stub                ; yes: put the program stub in front
	bsr.w	show_packed_length              ; the packed length and percentage
	bra.w	multi_file_check                ; check and save it
multi_chunk_pack:
	bsr.w	file_selector                   ; fsel_input
	tst.w	fsel_ok                         ; OK clicked?
	beq.w	multi_file_packer               ; no: the box again
	bsr.w	find_first_file                 ; find the first file of the folder
	move.w	#$ffff,no_buffer_pack           ; no buffer pack
	bsr.w	choose_rate                     ; ask for the compaction rate
	bsr.w	choose_chunk_size               ; ask for the chunk size
	move.l	chunk_size,multi_chunk_size     ; keep it
	move.w	#$1,chunk_mode                  ; chunk packing
multi_chunk_next_file:
	move.l	multi_chunk_size,chunk_size     ; the chunk size again (a short file changes it)
	bsr.w	reset_buffers                   ; reset the buffers and the file type
	bsr.w	found_name_to_boxes             ; the found name into the boxes
	bsr.w	make_file_name                  ; make the path and file name
	movea.l	source_ptr,a6                   ; a6 = where to load it
	bsr.w	load_file                       ; load it
	cmp.l	#$0,d7                          ; anything loaded?
	ble.w	multi_chunk_skip                ; no: next file
	move.l	d7,source_length                ; the length
	bsr.w	find_file_type                  ; find its type
	cmp.w	#$0,d7                          ; packed already?
	beq.w	multi_chunk_skip                ; yes: next file
	bsr.w	check_program_name              ; a .PRG or .TOS name?
	cmpi.b	#$ff,pack_programs              ; packing programs?
	beq.s	multi_chunk_file                ; yes
	cmpi.b	#$1,file_type                   ; a program?
	bne.s	multi_chunk_file                ; no
	bsr.w	pause                           ; yes: skip it after a pause
	bra.w	multi_chunk_skip                ; next file
multi_chunk_file:
	bsr.w	show_file_length                ; the file length into the boxes
	bsr.w	pack_in_chunks_multi            ; pack it in chunks
	cmpi.b	#$1,file_type                   ; a program?
	bne.s	multi_chunk_data                ; no
	bsr.w	add_program_stub                ; yes: put the program stub in front
	bsr.w	show_packed_length              ; the packed length and percentage
	bra.s	multi_chunk_check
multi_chunk_data:
	bsr.w	show_packed_length              ; the packed length and percentage
multi_chunk_check:
	bsr.w	found_name_to_boxes             ; the found name into the boxes
	move.l	source_length,d6                ; the length
	mulu.w	#$5,d6                          ; 5%
	divu.w	#$64,d6
	move.l	source_length,d7                ; the length
	sub.w	d6,d7                           ; less 5%
	move.l	d7,source_length                ; = what the packed file must stay under
	move.l	packed_length,d6                ; the packed length
	move.l	build_ptr,d7                    ; the packed file
	cmp.l	source_length,d6                ; under 95%?
	blt.w	multi_chunk_save                ; yes: save it
	bsr.w	pause                           ; no: skip it after a pause
	bra.s	multi_chunk_skip                ; next file
multi_chunk_save:
	cmpi.w	#$0,buffer_pack                 ; buffer pack?
	beq.w	multi_chunk_write               ; no
	movea.l	d7,a0                           ; yes:
	cmpi.l	#$41553543,(a0)                 ; chunked ('AU5C')?
	beq.w	multi_chunk_write               ; yes: leave it
	move.b	#$24,3(a0)                      ; no: 'AU5!' becomes 'AU5$'
multi_chunk_write:
	move.l	tree_result,current_tree        ; the result box
	move.w	#$9,aes_intin                   ; OK
	move.w	#$8,aes_intin+12                ; disabled while writing
	jsr	objc_change(pc)
	jsr	open_dialog(pc)                 ; draw the box
	bsr.w	write_file                      ; write the file
	jsr	close_dialog(pc)                ; remove the box
	move.w	#$9,aes_intin                   ; OK
	clr.w	aes_intin+12                    ; normal again
	jsr	objc_change(pc)
	cmp.l	packed_length,d7                ; all written?
	beq.w	multi_chunk_skip                ; yes: next file
	bsr.w	alert_write_error               ; no: "WRITE PROTECTED OR DISK IS FULL OR HAS AN ERROR"
	bra.w	multi_file_packer               ; and back to the box
multi_chunk_skip:
	bsr.w	find_next_file                  ; next matching file
	cmp.b	#$0,d0                          ; found?
	beq.w	multi_chunk_next_file           ; yes: pack it
	bra.w	multi_file_packer               ; no: back to the box
multi_file_data:
	bsr.w	show_packed_length              ; the packed length and percentage
multi_file_check:
	move.l	source_length,d6                ; the length
	mulu.w	#$5,d6                          ; 5%
	divu.w	#$64,d6
	move.l	source_length,d7                ; the length
	sub.w	d6,d7                           ; less 5%
	move.l	d7,source_length                ; = what the packed file must stay under
	bsr.w	found_name_to_boxes             ; the found name into the boxes
	move.l	build_ptr,d7                    ; the packed file
	move.l	packed_length,d6                ; the packed length
	cmp.l	source_length,d6                ; under 95%?
	blt.w	multi_file_save                 ; yes: save it
	bsr.w	pause                           ; no: skip it after a pause
	bra.s	multi_file_skip                 ; next file
multi_file_save:
	cmpi.w	#$0,buffer_pack                 ; buffer pack?
	beq.w	multi_file_write                ; no
	movea.l	d7,a0                           ; yes:
	move.b	#$24,3(a0)                      ; 'AU5!' becomes 'AU5$'
multi_file_write:
	move.l	tree_result,current_tree        ; the result box
	move.w	#$9,aes_intin                   ; OK
	move.w	#$8,aes_intin+12                ; disabled while writing
	jsr	objc_change(pc)
	jsr	open_dialog(pc)                 ; draw the box
	bsr.w	write_file                      ; write the file
	jsr	close_dialog(pc)                ; remove the box
	move.w	#$9,aes_intin                   ; OK
	clr.w	aes_intin+12                    ; normal again
	jsr	objc_change(pc)
	cmp.l	packed_length,d7                ; all written?
	beq.w	multi_file_skip                 ; yes: next file
	bsr.w	alert_write_error               ; no: "WRITE PROTECTED OR DISK IS FULL OR HAS AN ERROR"
	bra.w	multi_file_packer               ; and back to the box
multi_file_skip:
	bsr.w	find_next_file                  ; next matching file
	cmp.b	#$0,d0                          ; found?
	beq.w	multi_next_file                 ; yes: pack it
	bra.w	multi_file_packer               ; no: back to the box

;------------------------------------------------------------------------------
; PREFERENCES: three toggles, each shown as a pair of buttons with the one not chosen disabled.  PRINT HEADER
; patches the program stub so that it does not clear the screen or print its title; VERIFY sets
; verify_off; PACK STATUS chooses between a percentage and colours (only the old packer below used it).
;------------------------------------------------------------------------------
preferences:	; from: main_menu
	move.l	tree_preferences,current_tree   ; the preferences box
	jsr	open_dialog(pc)                 ; draw it
	move.w	#$1,objc_change_redraw+2        ; objc_change redraws while the box is up
preferences_loop:
	move.l	tree_preferences,current_tree   ; the preferences box
	clr.w	aes_intin                       ; FMD_START
	jsr	form_dial(pc)
	jsr	form_do(pc)
	move.w	d0,d7                           ; d7 = the button
	move.w	d0,aes_intin                    ; deselect it
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	move.w	d7,d0                           ; d0 = the button
	cmp.b	#$2,d0                          ; PRINT HEADER?
	beq.s	toggle_header                   ; yes
	cmp.b	#$3,d0                          ; VERIFY?
	beq.w	toggle_verify                   ; yes
	cmp.b	#$4,d0                          ; PACK STATUS?
	beq.w	toggle_status                   ; yes
	jsr	close_dialog(pc)                ; MAIN MENU: remove the box
	clr.w	objc_change_redraw+2            ; objc_change no longer redraws
	rts
toggle_header:
	cmpi.b	#$ff,header_off                 ; header off?
	beq.s	header_on                       ; yes: turn it on
	move.w	#$4e71,stub_clear_screen        ; no: the stub no longer clears the screen
	move.w	#$4e71,stub_print_trap          ; nor prints its title (the trap #1 of Cconws)
	move.b	#$ff,header_off                 ; header off
	move.w	#$6,aes_intin                   ; YES
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	move.w	#$7,aes_intin                   ; NO
	clr.w	aes_intin+12                    ; normal
	jsr	objc_change(pc)
	bra.s	header_toggled
header_on:
	move.w	clear_long_opcode,stub_clear_screen ; the stub clears the screen again
	move.w	#$4e41,stub_print_trap          ; and prints its title
	clr.b	header_off                      ; header on
	move.w	#$6,aes_intin                   ; YES
	clr.w	aes_intin+12                    ; normal
	jsr	objc_change(pc)
	move.w	#$7,aes_intin                   ; NO
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
header_toggled:
	bra.w	preferences_loop                ; the box again
clear_long_opcode:
	clr.l	(a2)+                           ; the stub's "clr.l (a2)+", put back when the header is turned on
header_off:
	dc.w	$0000                           ; $ff: the stub prints no header
toggle_verify:
	cmpi.b	#$ff,verify_off                 ; verify off?
	beq.s	verify_on                       ; yes: turn it on
	move.b	#$ff,verify_off                 ; verify off
	move.l	#$8,offset_gap                  ; offset_gap 8
	move.w	#$8,aes_intin                   ; YES
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	move.w	#$9,aes_intin                   ; NO
	move.w	#$0,aes_intin+12                ; normal
	jsr	objc_change(pc)
	bra.s	verify_toggled
verify_on:
	clr.b	verify_off                      ; verify on
	move.l	#$4,offset_gap                  ; offset_gap 4
	move.w	#$8,aes_intin                   ; YES
	move.w	#$0,aes_intin+12                ; normal
	jsr	objc_change(pc)
	move.w	#$9,aes_intin                   ; NO
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
verify_toggled:
	bra.w	preferences_loop                ; the box again
verify_off:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer, check_verify_room
	dc.w	$0000                           ; $ff: no verify (also set when there is no room for one)
toggle_status:
	cmpi.b	#$ff,status_colours             ; colours?
	beq.s	status_percent                  ; yes: percentage
	move.b	#$ff,status_colours             ; colours
	move.w	#$a,aes_intin                   ; PERCENT
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	move.w	#$b,aes_intin                   ; COLOURS
	clr.w	aes_intin+12                    ; normal
	jsr	objc_change(pc)
	bra.s	status_toggled
status_percent:
	clr.b	status_colours                  ; percentage
	move.w	#$a,aes_intin                   ; PERCENT
	clr.w	aes_intin+12                    ; normal
	jsr	objc_change(pc)
	move.w	#$b,aes_intin                   ; COLOURS
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
status_toggled:
	bra.w	preferences_loop                ; the box again
status_colours:	; from: old_pack
	dc.w	$0000                           ; nonzero: the old packer flashes the colours instead of showing a
                                                ;   percentage

;------------------------------------------------------------------------------
; Left-over code that nothing calls: print a string and wait for a key, and a start-up that hides the cursor
; and shrinks the memory.
;------------------------------------------------------------------------------
unused_print_and_wait:
	movea.l	a4,a0                           ; the string
	bsr.w	print                           ; print it
	bsr.w	wait_key                        ; wait for a key
	rts
unused_startup:
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
; Reset for a new file: the build pointer to dest_buffer, no packed length, the source to load_buffer, file
; type data, no offset, not packed.
;------------------------------------------------------------------------------
reset_buffers:	; from: main_menu, multi_file_packer
	move.l	dest_buffer,build_ptr           ; the build pointer
	clr.l	packed_length                   ; no packed length
	move.l	load_buffer,source_ptr          ; the source
	clr.b	file_type                       ; file type data
	clr.l	offset_length                   ; no offset
	clr.b	packed_flag                     ; not packed
	rts

;------------------------------------------------------------------------------
; fsel_input on the path in fsel_path and the name in fsel_name; fsel_ok is nonzero for OK.  The AES
; parameter block is built in front of the call.
;------------------------------------------------------------------------------
file_selector:	; from: pack_one_file, menu_chunk_packer, save_file, multi_file_packer
	move.l	#fsel_control,fsel_block        ; control
	move.l	#fsel_global,fsel_global_ptr    ; global
	move.l	#fsel_intin,fsel_intin_ptr      ; intin
	move.l	#fsel_intout,fsel_intout_ptr    ; intout
	move.l	#fsel_addrin,fsel_addrin_ptr    ; addrin: the path and the name
	move.l	#fsel_addrout,fsel_addrout_ptr  ; addrout
	move.l	#fsel_block,d1                  ; the parameter block
	move.l	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	rts

;------------------------------------------------------------------------------
; Build the full name in file_name from the selector's path (up to its last \) and name, and copy the name into
; the progress and result boxes ("CURRENT FILE IS: XXXXXXXX.XXX").
;------------------------------------------------------------------------------
make_file_name:	; from: pack_one_file, menu_chunk_packer, save_file, multi_file_packer
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
	movea.l	text_progress_file,a3           ; the progress box's file line
	movea.l	text_result_file,a2             ; the result box's file line
	adda.l	#$11,a3                         ; past "CURRENT FILE IS: "
	adda.l	#$11,a2                         ; the same
	move.w	#$b,d0                          ; 12 characters
copy_name:
	cmpi.b	#$0,(a0)                        ; end of the name?
	bne.s	copy_name_char                  ; no
	clr.b	(a1)+                           ; yes: end the full name
	lea	spaces(pc),a0                   ; and pad the boxes with spaces
copy_name_char:
	move.b	(a0),(a3)+                      ; into the progress box
	move.b	(a0),(a2)+                      ; the result box
	move.b	(a0)+,(a1)+                     ; and the full name
	dbra	d0,copy_name                    ; for each character
	rts
unused_copy_string:
	move.b	(a0)+,d0                        ; a character
	beq.s	unused_copy_string_end          ; to the end
	move.b	d0,(a1)+                        ; copy it
	bra.s	unused_copy_string
unused_copy_string_end:
	clr.b	(a1)+                           ; end it
	rts

;------------------------------------------------------------------------------
; Load file_name to a6.  d7 = the length read, 0 (after an alert) when nothing could be read.
;------------------------------------------------------------------------------
load_file:	; from: pack_one_file, menu_chunk_packer, multi_file_packer
	clr.w	-(sp)                           ; read only
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
	cmp.l	#$0,d7                          ; anything read?
	bgt.s	load_file_done                  ; yes
	bsr.w	alert_load_error                ; no: "FILE DOES NOT EXIST OR HAS AN ERROR OR IS ZERO LENGTH"
	clr.l	d7                              ; nothing
load_file_done:
	rts

;------------------------------------------------------------------------------
; Check the loaded file against the menu entry: a program must start $601a, data must not; a packed program
; has 'AU5!' after its $344 byte stub, packed data starts with it.  A packed file is copied to the build
; buffer (past the stub for a program) and packed_flag set.  d7 = 0 (after an alert) for the wrong type.
;------------------------------------------------------------------------------
check_loaded_file:	; from: pack_one_file, menu_chunk_packer
	cmpi.b	#$1,file_type                   ; a program?
	bne.s	check_data_file                 ; no
	cmpi.w	#$601a,(a6)                     ; a program file?
	bne.s	wrong_pack_type                 ; no: wrong type
	cmpi.l	#$41553521,$344(a6)             ; 'AU5!' after the stub?
	beq.s	file_is_packed                  ; yes: packed
	bra.s	check_loaded_done               ; no: pack it
check_data_file:
	cmpi.l	#$41553521,(a6)                 ; 'AU5!'?
	bne.s	check_loaded_done               ; no: pack it
file_is_packed:
	move.b	#$ff,packed_flag                ; packed
	move.l	d7,d0                           ; the length
	movea.l	source_ptr,a0                   ; the loaded file
	movea.l	build_ptr,a1                    ; the build buffer
copy_packed_file:
	move.b	(a0)+,(a1)+                     ; copy it
	dbra	d0,copy_packed_file             ; 64 K at a time
	subi.l	#$10000,d0
	bpl.s	copy_packed_file
	cmpi.b	#$1,file_type                   ; a program?
	bne.s	check_loaded_done               ; no
	addi.l	#$344,build_ptr                 ; yes: the packed data starts after the stub
	bra.s	check_loaded_done
wrong_pack_type:
	move.l	#alert_type_text,aes_addrin     ; "WRONG PACK TYPE"
	clr.w	aes_intin                       ; the alert's default button 0
	jsr	form_alert(pc)
	clr.l	d7                              ; not usable
check_loaded_done:
	rts

;------------------------------------------------------------------------------
; The multi file packer's check: the file type from the loaded file.  A packed file is skipped (d7 = 0 after
; a pause), otherwise d7 = -1.
;------------------------------------------------------------------------------
find_file_type:	; from: multi_file_packer
	movea.l	source_ptr,a0                   ; the loaded file
	cmpi.w	#$601a,(a0)                     ; a program?
	bne.s	file_type_data                  ; no
	adda.l	#$344,a0                        ; yes: past the stub
	cmpi.l	#$41553521,(a0)                 ; 'AU5!'?
	beq.s	file_type_packed                ; yes: packed
	move.b	#$1,file_type                   ; no: a program
	move.w	#$ffff,d7                       ; use it
	bra.s	find_file_type_done
file_type_data:
	cmpi.l	#$41553521,(a0)                 ; 'AU5!'?
	beq.s	file_type_packed                ; yes: packed
	clr.b	file_type                       ; no: data
	move.w	#$ffff,d7                       ; use it
	bra.s	find_file_type_done
file_type_packed:
	move.b	#$ff,packed_flag                ; packed
	bsr.w	pause
	clr.l	d7                              ; skip it
find_file_type_done:
	rts

;------------------------------------------------------------------------------
; "FILE DOES NOT EXIST OR HAS AN ERROR OR IS ZERO LENGTH"
;------------------------------------------------------------------------------
alert_load_error:	; from: load_file
	move.l	#alert_load_error_text,aes_addrin
	clr.w	aes_intin                       ; the alert's default button 0
	jsr	form_alert(pc)
	rts

;------------------------------------------------------------------------------
; PACK DATA (OFFSET): ask for the offset in hex.  The data before it is moved below the build buffer and left
; unpacked; the rest is packed.  d7 = 0 (after an alert) when the offset is not inside the file.
;------------------------------------------------------------------------------
ask_offset:	; from: menu_chunk_packer, pack_loaded
	move.l	tree_offset,current_tree        ; the offset box
	jsr	open_dialog(pc)                 ; draw it
	jsr	form_do(pc)
	move.w	d0,aes_intin                    ; deselect the exit button
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	clr.b	hex_digit_count                 ; count the digits
	movea.l	text_offset,a0                  ; the offset field
	move.w	#$4,d1                          ; up to 5
count_offset_digits:
	cmpi.b	#$0,(a0)+                       ; a digit?
	beq.s	offset_counted                  ; no: done
	addi.b	#$1,hex_digit_count             ; yes: count it
	dbra	d1,count_offset_digits
offset_counted:
	movea.l	text_offset,a0                  ; the field
	bsr.w	hex_to_number                   ; to a number in d2
	cmp.l	source_length,d2                ; inside the file?
	blt.s	offset_ok                       ; yes
	move.l	#alert_offset_text,aes_addrin   ; no: "SORRY... OFFSET TOO LARGE"
	move.w	#$1,aes_intin                   ; the alert's default button 1
	jsr	form_alert(pc)
	clr.l	d7                              ; not usable
	bra.s	ask_offset_done
offset_ok:
	move.l	d2,offset_length                ; the offset
	sub.l	d2,source_length                ; less to pack
	movea.l	build_ptr,a0                    ; the build buffer
	suba.l	d2,a0                           ; less the offset
	suba.l	offset_gap,a0                   ; less the gap
	movea.l	source_ptr,a1                   ; the loaded file
copy_offset_data:
	move.b	(a1)+,(a0)+                     ; copy the data before the offset there
	dbra	d2,copy_offset_data             ; 64 K at a time
	subi.l	#$10000,d2
	bpl.s	copy_offset_data
	move.l	a1,source_ptr                   ; the source is the rest
ask_offset_done:
	rts

;------------------------------------------------------------------------------
; After packing from an offset: the file starts with the unpacked data before the offset.
;------------------------------------------------------------------------------
add_offset_data:	; from: pack_whole_file
	move.l	offset_length,d1                ; the offset
	sub.l	d1,build_ptr                    ; the file starts that much earlier
	add.l	d1,packed_length                ; and is that much longer
	rts

;------------------------------------------------------------------------------
; Turn the verify off when twice the file length + $9000 is not below the memory noted at start-up.
;------------------------------------------------------------------------------
check_verify_room:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer
	move.l	source_length,d0                ; the length
	add.l	d0,d0                           ; twice
	addi.l	#$9000,d0                       ; + $9000
	move.l	free_memory,d1                  ; the memory there is
	cmp.l	d1,d0                           ; enough?
	blt.w	check_verify_room_done          ; yes
	move.b	#$ff,verify_off                 ; no: no verify
check_verify_room_done:
	rts

;------------------------------------------------------------------------------
; Pack source_ptr/source_length to build_ptr with Pack-Ice, mouse and keyboard mouse reports off.  The build
; buffer is first filled with $affaaffe.  packed_length = the result.
;------------------------------------------------------------------------------
pack_source:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the keyboard ACIA
	btst	#$1,d0                          ; ready to send?
	beq.s	pack_source                     ; no: wait
	move.w	#$12,$fffffc02.w                ; keyboard ACIA data, IKBD: disable mouse
	dc.w	$a00a                           ; Line-A $a, hide the mouse
	move.l	build_ptr,d0                    ; the build buffer
	movea.l	d0,a0
	move.l	source_ptr,d0                   ; the source
	sub.l	build_ptr,d0                    ; less the build buffer
	andi.l	#$fffffffe,d0                   ; even
	lsr.l	#3,d0                           ; in 8 byte steps
	subq.w	#1,d0
fill_build_buffer:
	move.b	#$af,(a0)+                      ; $af
	move.b	#$fa,(a0)+                      ; $fa
	move.b	#$af,(a0)+                      ; $af
	move.b	#$fe,(a0)+                      ; $fe
	move.b	#$af,(a0)+                      ; $af
	move.b	#$fa,(a0)+                      ; $fa
	move.b	#$af,(a0)+                      ; $af
	move.b	#$fe,(a0)+                      ; $fe
	dbra	d0,fill_build_buffer            ; up to the source
	move.l	source_ptr,ice_source           ; Pack-Ice's source
	move.l	source_length,ice_length        ; its length
	move.l	build_ptr,ice_dest              ; its destination
	move.l	window_size,ice_window          ; its window (the compaction rate)
	move.l	window_size,match_table_span
	bsr.w	ice_pack                        ; pack, with checksums
	move.l	d7,packed_length                ; the packed length
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the keyboard ACIA
	btst	#$1,d0                          ; ready to send?
	beq.w	old_pack_mouse_on               ; no: wait (in the old packer's loop)
	move.w	#$8,$fffffc02.w                 ; keyboard ACIA data, IKBD: relative mouse
	dc.w	$a009                           ; Line-A $9, show the mouse
	rts

;------------------------------------------------------------------------------
; Verify: depack the packed data to verify_buffer and work out the same three checksums Pack-Ice made of the
; source.  Any difference sets packed_length to $fffff, so that the file is not saved.
;------------------------------------------------------------------------------
verify_packed:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer
	movea.l	ice_dest,a0                     ; the packed data
	movea.l	match_table,a1                  ; where to depack it
	move.w	$ffff8240.w,-(sp)               ; palette 0, keep the background colour
	bsr.w	au5_depack                      ; depack
	move.w	(sp)+,$ffff8240.w               ; palette 0, colour back
	movea.l	match_table,a0                  ; the depacked data
	move.l	ice_length,d7                   ; its length
	moveq	#0,d0
	moveq	#0,d1                           ; sum
	moveq	#0,d2                           ; sum of the inverted bytes
	move.l	#$45474221,d3                   ; 'EGB!': the running xor
verify_sum:
	move.b	(a0)+,d0                        ; a byte
	add.l	d0,d1                           ; sum it
	not.l	d0                              ; inverted
	add.l	d0,d2                           ; sum that
	not.l	d0
	eor.l	d1,d3                           ; xor both sums in
	eor.l	d2,d3
	subq.l	#1,d7                           ; for each byte
	bne.w	verify_sum
	move.l	checksum_sum,d4                 ; the source's sum
	move.l	checksum_not_sum,d5             ; inverted sum
	move.l	checksum_xor,d6                 ; and xor
	cmp.l	d1,d4                           ; the same?
	bne.w	verify_failed                   ; no
	cmp.l	d2,d5
	bne.w	verify_failed                   ; no
	cmp.l	d3,d6
	bne.w	verify_failed                   ; no
	rts                                     ; all the same
verify_failed:
	move.l	#$fffff,packed_length           ; too long to save
	rts

;------------------------------------------------------------------------------
; The packer of earlier Automation versions, an LZ77 packer writing an 'AU5!' file.  Nothing calls it now.  It
; packs source_ptr/source_length to build_ptr+8, keeping the search window in window_size, and shows the
; percentage done (or flashes the colours).
;------------------------------------------------------------------------------
old_pack:
	move.w	$ffff8240.w,-(sp)               ; palette 0, keep the background colour
old_pack_mouse_off:
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the keyboard ACIA
	btst	#$1,d0                          ; ready to send?
	beq.s	old_pack_mouse_off              ; no: wait
	move.w	#$12,$fffffc02.w                ; keyboard ACIA data, IKBD: disable mouse
	dc.w	$a00a                           ; Line-A $a, hide the mouse
old_pack_mouse_on:	; from: pack_source
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the keyboard ACIA
	btst	#$1,d0                          ; ready to send?
	beq.s	old_pack_mouse_on               ; no: wait
	move.w	#$8,$fffffc02.w                 ; keyboard ACIA data, IKBD: relative mouse
	dc.w	$a009                           ; Line-A $9, show the mouse
	move.w	#$3030,percent_digits           ; "00" percent
	move.l	source_length,d0                ; the length
	movea.l	source_ptr,a0                   ; the source
	lea	0(a0,d0.l),a2                   ; a2 = its end
	movea.l	build_ptr,a1                    ; the build buffer
	addq.l	#8,a1                           ; past its 8 byte header
	clr.w	d5                              ; no literals yet
	moveq	#7,d6                           ; 8 bits to the byte
old_pack_loop:
	cmpi.b	#$0,status_colours              ; colours?
	beq.s	old_pack_percent                ; no
	move.b	(a0),$ffff8240.w                ; palette 0, yes: flash the background
	bra.s	old_pack_search
old_pack_percent:
	bsr.w	old_show_percent                ; show the percentage
old_pack_search:
	move.b	(a0),d0                         ; the byte to match
	move.w	#$1,old_best_length             ; best match 1
	moveq	#1,d1                           ; its offset
	move.l	old_window,d2                   ; the window
	move.l	a0,old_string_start             ; the start of this string
	lea	1(a0),a3
	addq.w	#1,a3
	adda.w	d2,a3                           ; + the window
	cmpa.l	a2,a3                           ; past the end?
	blt.s	old_search_window               ; no
	suba.w	d2,a3                           ; yes: back
	subq.w	#1,a3
	lea	old_search_near_end_next(pc),a5 ; return into the end-checking loop
old_search_near_end:
	cmp.b	(a3)+,d0                        ; the first byte?
	beq.s	old_match_found                 ; found
old_search_near_end_next:
	cmpa.l	a2,a3                           ; at the end?
	dbeq	d2,old_search_near_end          ; on through the window
	bra.s	old_match_done                  ; none
old_search_window:
	suba.w	d2,a3                           ; back
	subq.w	#1,a3
	lea	old_search_fast_next(pc),a5     ; return into the fast loop
old_search_fast:
	cmp.b	(a3)+,d0                        ; the first byte?
old_search_fast_next:
	dbeq	d2,old_search_fast              ; on through the window
	beq.s	old_match_found                 ; found
	bra.s	old_match_done                  ; none
old_string_start:
	dc.l	$00000000                       ; the start of this string
old_match_found:
	movem.l	d0/a0-a3,-(sp)
	subq.w	#1,a3                           ; the match
	movea.l	a3,a1
	move.l	a1,d1
	sub.l	old_string_start(pc),d1         ; its offset
	clr.w	d0                              ; its length
old_match_length:
	cmpm.b	(a0)+,(a1)+                     ; the same?
	bne.s	old_match_end                   ; no
	cmpa.l	a2,a1                           ; past the end?
	bhi.s	old_match_end                   ; yes
	cmpa.l	a3,a0                           ; into the string?
	bhi.s	old_match_end                   ; yes
	addq.w	#1,d0                           ; one longer
	cmp.w	#$3ff,d0                        ; at most $3ff
	bne.s	old_match_length
old_match_end:
	cmp.w	old_best_length(pc),d0          ; longer than the best?
	ble.s	old_match_next                  ; no
	move.w	d0,old_best_length              ; yes: the best
	move.w	d1,old_best_offset              ; and its offset
old_match_next:
	movem.l	(sp)+,d0/a0-a3
	tst.w	old_return_flags                ; not equal
	jmp	(a5)                            ; back into the search
old_return_flags:
	dc.w	$ffff                           ; tested for a nonzero result
old_match_done:
	move.w	old_best_offset(pc),d0          ; the best offset
	move.w	old_best_length(pc),d1          ; the best length
	sub.w	d1,d0
	cmp.w	#$1,d1                          ; 1: a literal
	beq.s	old_literal
	cmp.w	#$2,d1                          ; 2?
	beq.s	old_match_2
	bsr.w	old_put_literal_count           ; the literals before it
	bsr.w	old_put_offset                  ; the offset
	bra.s	old_match_written
old_match_2:
	cmp.w	#$23f,d0                        ; offset too large?
	bhi.s	old_literal                     ; yes: a literal
	bsr.w	old_put_literal_count           ; the literals before it
	bsr.w	old_put_short_offset            ; the short offset
old_match_written:
	bsr.w	old_put_length                  ; the length
	moveq	#0,d5                           ; no literals
	move.w	old_best_length(pc),d0          ; skip the matched bytes
	lea	0(a0,d0.w),a0
	bra.w	old_pack_next
old_literal:	; from: old_put_short_offset
	move.b	(a0)+,(a1)+                     ; copy a literal
	addq.w	#1,d5                           ; count it
old_pack_next:
	lea	-$1(a2),a3                      ; the last byte
	cmpa.l	a0,a3                           ; reached?
	bne.w	old_pack_loop                   ; no: on
	move.b	(a0)+,(a1)+                     ; the last byte as a literal
	addq.w	#1,d5
	bsr.w	old_put_literal_count           ; the literals
	bset	d6,d7                           ; end marker bit
	move.b	d7,(a1)+                        ; the last bits
	clr.w	d1
	move.l	a1,d0                           ; the build pointer
	lsr.l	#1,d0                           ; odd?
	bcc.s	old_pack_end                    ; no
	addq.w	#1,a1                           ; yes: a pad byte
	bset	#$f,d1                          ; and flag it
old_pack_end:
	move.w	d1,(a1)+
	movea.l	build_ptr,a0                    ; the header
	move.l	source_length,(a0)              ; the unpacked length
	clr.l	(a1)
	clr.l	4(a1)
	suba.l	a0,a1                           ; the packed length
	move.l	a1,4(a0)
	move.l	a1,packed_length
	move.l	offset_gap,d0                   ; the gap
	sub.l	d0,build_ptr
	move.l	#$41553521,-$4(a0)              ; 'AU5!'
	addq.l	#4,packed_length
old_pack_wait_acia:
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the keyboard ACIA
	btst	#$1,d0                          ; ready to send?
	beq.s	old_pack_wait_acia              ; no: wait
	move.w	#$8,$fffffc02.w                 ; keyboard ACIA data, IKBD: relative mouse
	dc.w	$a009                           ; Line-A $9, show the mouse
	move.w	(sp)+,$ffff8240.w               ; palette 0, the background colour back
old_put_bits_done:	; from: old_put_length
	rts

;------------------------------------------------------------------------------
; The old packer's code writers: each sets d1 = the bits and d4 = their count - 1 and goes to old_put_bits.
;------------------------------------------------------------------------------
old_put_literal_count:	; from: old_pack
	lea	old_literal_table(pc),a3        ; the literal count table
	moveq	#5,d3
old_literal_range:
	move.b	0(a3,d3.w),d4
	ext.w	d4
	cmp.w	d4,d5                           ; in this range?
	dbge	d3,old_literal_range            ; no: the one below
	sub.w	d4,d5                           ; less its start
	lsl.w	#1,d3
	move.b	6(a3,d3.w),d2                   ; the bits for it
	ext.w	d2
	moveq	#-1,d1
	lsl.l	d2,d1                           ; the prefix ones
	or.w	d5,d1                           ; the count
	clr.w	d4
	move.b	7(a3,d3.w),d4                   ; the bit count
	bra.w	old_put_bits                    ; write them
old_literal_table:
	dc.w	$0001,$0205,$080f,$0100,$0101,$0203,$0205,$0308
	dc.w	$0a12

old_put_offset:	; from: old_pack
	lea	old_offset_table(pc),a3         ; the offset table
	moveq	#2,d3
old_offset_range:
	add.w	d3,d3
	move.w	0(a3,d3.w),d4
	lsr.w	#1,d3
	cmp.w	d4,d0                           ; in this range?
	dbge	d3,old_offset_range             ; no: the one below
	sub.w	d4,d0                           ; less its start
	add.w	d3,d3
	move.w	6(a3,d3.w),d3                   ; bits and prefix
	move.w	d3,d4
	lsr.w	#8,d3                           ; the prefix length
	moveq	#-1,d1
	lsl.w	d3,d1
	or.w	d0,d1                           ; the offset
	andi.w	#$f,d4                          ; the bit count
	bra.w	old_put_bits                    ; write them
old_offset_table:
	dc.w	$0000,$0020,$0120,$0606,$0908,$0c0d

old_put_short_offset:	; from: old_pack
	cmp.w	#$23f,d0                        ; too large?
	bhi.w	old_literal                     ; yes: a literal
	move.w	d0,d1
	cmp.w	#$3f,d1                         ; 6 bits?
	ble.s	old_short_offset_6              ; yes
	subi.w	#$40,d1                         ; no: 9 bits
	moveq	#9,d4
	bset	d4,d1                           ; and a 1
	bra.w	old_put_bits                    ; write them
old_short_offset_6:
	move.w	#$6,d4                          ; 6 bits + the 0
	bra.w	old_put_bits                    ; write them
old_length_table:	; from: old_put_length
	dc.w	$0203,$0406,$0a01,$0102,$030a

old_put_length:	; from: old_pack
	lea	old_length_table(pc),a3         ; the length table
	move.w	old_best_length(pc),d0          ; the length
	moveq	#4,d5
old_length_range:
	move.b	0(a3,d5.w),d4
	ext.w	d4
	cmp.w	d4,d0                           ; in this range?
	dbge	d5,old_length_range             ; no: the one below
	sub.w	d4,d0                           ; less its start
	move.b	5(a3,d5.w),d4                   ; its bits
	ext.w	d4
	moveq	#-1,d1
	lsl.w	d4,d1                           ; the prefix
	add.w	d5,d4
	subq.w	#1,d4
	or.w	d0,d1                           ; the length
old_put_bits:	; from: old_put_literal_count, old_put_offset, old_put_short_offset
	lsr.l	#1,d1                           ; a bit
	roxr.b	#1,d7                           ; into the byte
	dbra	d6,old_put_bits_next            ; full?
	move.b	d7,(a1)+                        ; yes: write it
	clr.w	d7
	moveq	#7,d6
old_put_bits_next:
	dbra	d4,old_put_bits                 ; for each bit
	bra.w	old_put_bits_done
old_best_length:	; from: old_pack
	dc.w	$0000,$0000
old_best_offset:	; from: old_pack
	dc.w	$0000,$0000

;------------------------------------------------------------------------------
; The old packer's percentage display: work out how much is done and redraw the percentage when it changes.
;------------------------------------------------------------------------------
old_show_percent:	; from: old_pack
	movem.l	d0-d7/a0-a6,saved_registers     ; keep the registers
	move.l	source_ptr,d0                   ; the source
	suba.l	d0,a0                           ; done
	suba.l	d0,a2                           ; the end
	move.l	a0,d0
	move.l	a2,d1
	bsr.w	percent                         ; the percentage
	cmp.b	last_percent,d6                 ; changed?
	beq.w	old_show_percent_done           ; no
	move.b	d6,last_percent                 ; yes: keep it
	movea.l	text_progress_percent,a0        ; "PERCENTAGE ALREADY PACKED %XX"
	adda.l	#$1b,a0                         ; the XX
	move.b	percent_digits,(a0)+            ; tens
	move.b	percent_digits+1,(a0)+          ; units
	move.l	sp,d7                           ; keep the stack
	move.l	usp,a5                          ; and the user stack
	move.w	#$4,aes_intin                   ; the percentage line
	clr.w	aes_intin+2                     ; depth 0
	jsr	objc_draw(pc)
	lea	$0,a0
	move.l	a5,usp                          ; the stacks back
	movea.l	d7,sp
old_show_percent_done:
	movem.l	saved_registers,d0-d7/a0-a6     ; the registers back
	rts

;------------------------------------------------------------------------------
; Pack-Ice's progress call: put the percentage done (made in percent_digits) into the progress box and draw it.
; It runs in supervisor mode, so the user stack is pointed at a spare area while the AES draws.
;------------------------------------------------------------------------------
show_percent:	; from: progress
	movem.l	d0-d7/a0-a6,saved_registers     ; keep the registers
	movea.l	text_progress_percent,a0        ; "PERCENTAGE ALREADY PACKED %XX"
	adda.l	#$1b,a0                         ; the XX
	move.b	percent_digits,(a0)+            ; tens
	move.b	percent_digits+1,(a0)+          ; units
	move.l	sp,d7                           ; keep the stack
	move.l	usp,a5                          ; and the user stack
	lea	last_percent,a6                 ; the spare area below
	move.l	a6,usp                          ; as the user stack
	move.w	#$4,aes_intin                   ; the percentage line
	clr.w	aes_intin+2                     ; depth 0
	jsr	objc_draw(pc)
	lea	$0,a0
	move.l	a5,usp                          ; the stacks back
	movea.l	d7,sp
	movem.l	saved_registers,d0-d7/a0-a6     ; the registers back
	rts
user_stack_area:
	dcb.b	200,0                           ; the user stack while the AES draws the percentage
last_percent:	; from: old_show_percent
	dc.w	$0000                           ; the percentage last shown (the old packer)

;------------------------------------------------------------------------------
; Put the $344 byte program stub (program_stub, a PRG header and its depacker) in front of the packed data,
; with the packed length in the header's data length.  256 zero bytes go after the data.
;------------------------------------------------------------------------------
add_program_stub:	; from: pack_loaded, pack_whole_file, multi_file_packer
	move.l	build_ptr,d0                    ; the build buffer
	add.l	packed_length,d0                ; + the packed length
	movea.l	d0,a0                           ; = its end
	moveq	#-1,d0                          ; 256 bytes
clear_after_data:
	move.b	#$0,(a0)+                       ; cleared
	dbra	d0,clear_after_data
	move.l	#$344,d0                        ; the stub's length
	sub.l	d0,build_ptr                    ; in front of the data
	move.l	packed_length,program_stub_data_length ; the packed length is the header's data length
	add.l	d0,packed_length                ; the file is that much longer
	addq.l	#4,packed_length                ; and 4 more
	movea.l	build_ptr,a1                    ; where the stub goes
	lea	program_stub,a0                 ; the stub
	subq.l	#1,d0
copy_program_stub:
	move.b	(a0)+,(a1)+                     ; copy it
	dbra	d0,copy_program_stub
	rts

;------------------------------------------------------------------------------
; Fsfirst for the multi file packer: the folder from the selector's path, the mask too (fsel_path is used as it
; is), into file_dta.
;------------------------------------------------------------------------------
find_first_file:	; from: multi_file_packer
	lea	fsel_path,a0                    ; the selector's path
	lea	file_name,a1                    ; the full name
	moveq	#54,d7                          ; at most 55 characters back
copy_search_path:
	move.b	(a0)+,d0                        ; a character
	beq.s	find_search_backslash           ; to the end
	move.b	d0,(a1)+                        ; copy it
	bra.s	copy_search_path
find_search_backslash:
	movea.l	a1,a2                           ; the end
find_search_backslash_loop:
	move.b	-(a1),d2                        ; back a character
	cmp.b	#$5c,d2                         ; the \?
	beq.s	search_path_done                ; yes
	dbra	d7,find_search_backslash_loop   ; no: on back
	movea.l	a2,a1                           ; none: the end
search_path_done:
	clr.b	(a1)                            ; the folder in file_name
	pea	file_dta                        ; the DTA
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.l	#6,sp
	clr.w	-(sp)                           ; normal files
	pea	fsel_path(pc)                   ; the selector's path and mask
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	rts

;------------------------------------------------------------------------------
; A file found ending .PRG or .TOS is a program (file type 1).
;------------------------------------------------------------------------------
check_program_name:	; from: multi_file_packer
	lea	found_name,a0                   ; the found name
	moveq	#4,d0                           ; 5 characters
find_name_end:
	tst.b	(a0)+                           ; the end?
	beq.s	find_name_dot                   ; yes
	bra.s	find_name_end
find_name_dot:
	move.b	-(a0),d2                        ; back a character
	cmp.b	#$2e,d2                         ; the dot?
	beq.s	name_extension                  ; yes
	dbra	d0,find_name_dot                ; no: on back
	bra.s	check_program_name_done         ; no extension
name_extension:
	addq.l	#1,a0                           ; the extension
	cmpi.b	#$50,(a0)                       ; P?
	beq.s	name_extension_p                ; yes
	cmpi.b	#$54,(a0)                       ; T?
	bne.s	check_program_name_done         ; no
	cmpi.b	#$4f,1(a0)                      ; O?
	bne.s	check_program_name_done         ; no
	cmpi.b	#$53,2(a0)                      ; S?
	bne.s	check_program_name_done         ; no
name_is_program:
	move.b	#$1,file_type                   ; a program
	bra.s	check_program_name_done
name_extension_p:
	cmpi.b	#$52,1(a0)                      ; R?
	bne.s	check_program_name_done         ; no
	cmpi.b	#$47,2(a0)                      ; G?
	beq.s	name_is_program                 ; yes
check_program_name_done:
	rts

;------------------------------------------------------------------------------
; Fsnext: d0 = 0 when another file was found, $ff when not.
;------------------------------------------------------------------------------
find_next_file:	; from: multi_file_packer
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
; Copy the name Fsfirst/Fsnext found into fsel_name and the progress and result boxes.
;------------------------------------------------------------------------------
found_name_to_boxes:	; from: multi_file_packer
	lea	found_name,a0                   ; the found name
	lea	fsel_name(pc),a3                ; the selector's name
	movea.l	text_progress_file,a1           ; the progress box's file line
	movea.l	text_result_file,a2             ; the result box's file line
	adda.l	#$11,a1                         ; past "CURRENT FILE IS: "
	adda.l	#$11,a2                         ; the same
	move.w	#$b,d0                          ; 12 characters
copy_found_name:
	cmpi.b	#$0,(a0)                        ; end of the name?
	bne.s	copy_found_char                 ; no
	clr.b	(a3)+                           ; yes: end the selector's name
	lea	spaces(pc),a0                   ; and pad with spaces
copy_found_char:
	move.b	(a0),(a1)+                      ; into the progress box
	move.b	(a0),(a2)+                      ; the result box
	move.b	(a0)+,(a3)+                     ; and the selector's name
	dbra	d0,copy_found_name              ; for each character
	rts
spaces:	; from: make_file_name
	dc.b	'            '                  ; 12 spaces

;------------------------------------------------------------------------------
; Write d7 bytes from d6 to file_name.  d7 = the length written.
;------------------------------------------------------------------------------
write_file:	; from: save_file, multi_file_packer
	clr.w	-(sp)                           ; normal file
	pea	file_name                       ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	move.w	d0,d5                           ; d5 = the handle
	tst.l	d0                              ; created?
	bmi.s	write_file_done                 ; no
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
write_file_done:
	rts

;------------------------------------------------------------------------------
; "WRITE PROTECTED OR DISK IS FULL OR HAS AN ERROR"
;------------------------------------------------------------------------------
alert_write_error:	; from: save_file, multi_file_packer
	move.l	#alert_write_text,aes_addrin
	clr.w	aes_intin                       ; the alert's default button 0
	jsr	form_alert(pc)
	rts

;------------------------------------------------------------------------------
; The file length, in hex, into the progress box and the result box ("$00000").
;------------------------------------------------------------------------------
show_file_length:	; from: pack_one_file, menu_chunk_packer, pack_loaded, multi_file_packer
	move.l	source_length(pc),d0            ; the length
	movea.l	text_progress_length,a0         ; "FILE LENGTH    $00000 BYTES"
	adda.l	#$10,a0                         ; the digits
	bsr.w	hex_digits                      ; in hex
	move.l	source_length(pc),d0            ; the length
	movea.l	text_result_length,a0           ; "NORMAL LENGTH  $00000 BYTES"
	adda.l	#$10,a0                         ; the digits
	bsr.w	hex_digits                      ; in hex
	rts

;------------------------------------------------------------------------------
; The packed length and the percentage of the original into the result box.
;------------------------------------------------------------------------------
show_packed_length:	; from: pack_one_file, menu_chunk_packer, pack_loaded, pack_whole_file, multi_file_packer
	move.l	packed_length(pc),d0            ; the packed length
	move.l	source_length(pc),d1            ; the length
	bsr.w	percent                         ; the percentage
	move.l	packed_length(pc),d0            ; the packed length
	movea.l	text_result_packed,a0           ; "PACKED LENGTH  $00000 BYTES"
	adda.l	#$10,a0                         ; the digits
	bsr.w	hex_digits                      ; in hex
	movea.l	text_result_percent,a0          ; "PERCENTAGE OF ORIGINAL LENGTH %XX"
	adda.l	#$1f,a0                         ; the XX
	move.b	percent_digits,(a0)+            ; tens
	move.b	percent_digits+1,(a0)+          ; units
	rts

;------------------------------------------------------------------------------
; Cnecin: wait for a key.
;------------------------------------------------------------------------------
wait_key:	; from: menu_chunk_packer, pack_loaded, unused_print_and_wait
	move.w	#$8,-(sp)
	trap	#1                              ; Cnecin
	addq.l	#2,sp
	rts

;------------------------------------------------------------------------------
; A pause of $60000 loops, for a file that is skipped.
;------------------------------------------------------------------------------
pause:	; from: multi_file_packer, find_file_type
	move.l	#$60000,d0
pause_loop:
	subq.l	#1,d0
	cmp.l	#$0,d0
	bne.s	pause_loop
	rts

;------------------------------------------------------------------------------
; Cconws(a0).
;------------------------------------------------------------------------------
print:	; from: main, unused_print_and_wait
	move.l	a0,-(sp)                        ; the string
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; Write d0 as 5 hex digits at a0.
;------------------------------------------------------------------------------
hex_digits:	; from: show_file_length, show_packed_length
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
percent:	; from: old_show_percent, show_packed_length
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
; The compaction rate box: 1 (big and fast) to 10 (slow and small) sets the window, and BUFFER PACK or NORMAL
; PACK (shown disabled when no_buffer_pack is set).
;------------------------------------------------------------------------------
choose_rate:	; from: pack_loaded, pack_whole_file, multi_file_packer
	move.l	tree_rate,current_tree          ; the compaction rate box
	cmpi.w	#$0,no_buffer_pack              ; buffer pack allowed?
	beq.s	rate_buffer_allowed             ; yes
	move.w	#$f,aes_intin                   ; BUFFER PACK
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	move.w	#$10,aes_intin                  ; NORMAL PACK
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	bra.s	rate_dialog
rate_buffer_allowed:
	move.w	#$f,aes_intin                   ; BUFFER PACK
	clr.w	aes_intin+12                    ; normal
	jsr	objc_change(pc)
	move.w	#$10,aes_intin                  ; NORMAL PACK
	move.w	#$1,aes_intin+12                ; selected
	jsr	objc_change(pc)
rate_dialog:
	jsr	open_dialog(pc)                 ; draw it
	jsr	form_do(pc)
	move.w	d0,d7                           ; d7 = the button
	move.w	d0,aes_intin                    ; deselect it
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	move.w	#$1,aes_intin                   ; type R_OBJECT
	move.w	#$30,aes_intin+2                ; object 48: BUFFER PACK
	jsr	rsrc_gaddr(pc)
	movea.l	current_tree,a0                 ; the object
	move.w	$a(a0),d0                       ; its state
	cmp.w	#$1,d0                          ; selected?
	bne.s	rate_normal_pack                ; no
	move.w	#$1,buffer_pack                 ; yes: buffer pack
	bra.s	rate_window
rate_normal_pack:
	clr.w	buffer_pack                     ; normal pack
rate_window:
	move.w	d7,d0                           ; the button
	subi.b	#$2,d0                          ; 1-10 as 0-9
	andi.l	#$f,d0
	lsl.w	#1,d0                           ; words
	lea	window_sizes(pc),a0             ; the window sizes
	move.w	0(a0,d0.w),d0                   ; this one
	move.l	d0,window_size                  ; is Pack-Ice's window
	rts

;------------------------------------------------------------------------------
; After packing data: PROGRAM FILE?  YES asks for the depack and execute addresses and whether to stay in
; supervisor mode, then puts the data stub (data_stub, $b0 bytes) and the depacker ($15c bytes) in front of the
; packed data.  The stub's addresses are hex fields of the box.
;------------------------------------------------------------------------------
data_to_program:	; from: pack_whole_file
	move.l	tree_result,current_tree        ; the result box
	move.w	#$7,aes_intin                   ; YES
	clr.w	aes_intin+12                    ; normal
	jsr	objc_change(pc)
	move.w	#$8,aes_intin                   ; NO
	move.w	#$1,aes_intin+12                ; selected
	jsr	objc_change(pc)
	jsr	open_dialog(pc)                 ; draw it
	jsr	form_do(pc)
	move.w	d0,d7                           ; d7 = the button
	move.w	d0,aes_intin                    ; deselect it
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	move.w	#$1,aes_intin                   ; type R_OBJECT
	move.w	#$40,aes_intin+2                ; object 64: NO
	jsr	rsrc_gaddr(pc)
	movea.l	current_tree,a0                 ; the object
	move.w	$a(a0),d0                       ; its state
	cmp.w	#$1,d0                          ; NO selected?
	beq.w	data_to_program_done            ; yes: leave the data as it is
	move.l	tree_data_program,current_tree  ; the data-to-program box
	jsr	open_dialog(pc)                 ; draw it
	jsr	form_do(pc)
	move.w	d0,aes_intin                    ; deselect the exit button
	clr.w	aes_intin+12                    ; (normal state)
	jsr	objc_change(pc)
	jsr	close_dialog(pc)                ; remove the box
	clr.b	hex_digit_count                 ; count the digits
	movea.l	text_depack_at,a0               ; DEPACK AT
	move.w	#$4,d1                          ; up to 5
count_depack_digits:
	cmpi.b	#$0,(a0)+                       ; a digit?
	beq.s	depack_digits_counted           ; no: done
	addi.b	#$1,hex_digit_count             ; yes: count it
	dbra	d1,count_depack_digits
depack_digits_counted:
	movea.l	text_depack_at,a0               ; the field
	bsr.w	hex_to_number                   ; to a number
	move.l	d2,data_stub_depack_to          ; where the stub depacks to
	clr.b	hex_digit_count                 ; count the digits
	movea.l	text_execute_at,a0              ; EXECUTE AT
	move.w	#$4,d1                          ; up to 5
count_execute_digits:
	cmpi.b	#$0,(a0)+                       ; a digit?
	beq.s	execute_digits_counted          ; no: done
	addi.b	#$1,hex_digit_count             ; yes: count it
	dbra	d1,count_execute_digits
execute_digits_counted:
	movea.l	text_execute_at,a0              ; the field
	bsr.w	hex_to_number                   ; to a number
	move.l	d2,data_stub_execute            ; where the stub jumps
	move.w	#$1,aes_intin                   ; type R_OBJECT
	move.w	#$49,aes_intin+2                ; object 73: YES (SUPERVISOR MODE)
	jsr	rsrc_gaddr(pc)
	movea.l	current_tree,a0                 ; the object
	move.w	$a(a0),d0                       ; its state
	cmp.w	#$1,d0                          ; selected?
	bne.s	add_data_stub                   ; no
	move.w	#$4e71,data_stub_user_call      ; yes: the stub stays in supervisor mode
add_data_stub:
	move.l	packed_length,data_stub_data_length ; the packed length into the stub's header
	move.l	#$15c,d0                        ; the depacker's length
	sub.l	d0,build_ptr                    ; in front of the data
	add.l	d0,packed_length                ; the file is that much longer
	addq.l	#4,packed_length                ; and 4 more
	movea.l	build_ptr,a1                    ; where it goes
	lea	au5_depack,a0                   ; the depacker
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
; d2 = the hex number of hex_digit_count digits at a0; d0 = $ffff at a character that is not a hex digit.
;------------------------------------------------------------------------------
hex_to_number:	; from: ask_offset, data_to_program
	moveq	#0,d2
	moveq	#0,d7
	move.b	hex_digit_count,d7              ; the digit count
	subq.b	#1,d7
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
	bra.w	hex_number_done
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
hex_number_done:
	rts

;------------------------------------------------------------------------------
; Variables and texts of the GEM front end.
;------------------------------------------------------------------------------
place_values:	; from: hex_to_number
	dc.l	$10000000,$01000000,$00100000,$00010000 ; hex place values for hex_to_number, 8 digits down to 1
	dc.l	$00001000,$00000100,$00000010,$00000001
chunk_digits:	; from: chunk_number_text, pack_chunks
	dc.b	'000'                           ; "CHUNK XXX": the chunk being packed
chunk_count_digits:	; from: pack_chunks
	dc.b	'000'                           ; "OF XXX": the number of chunks
alert_load_error_text:	; from: alert_load_error
	dc.b	'[1][ | FILE DOES NOT EXIST | OR HAS AN ERROR | OR IS ZERO LENGTH'
	dc.b	' ][ OKAY ]',0
	dc.b	$00                             ; pad
alert_offset_text:	; from: ask_offset
	dc.b	'[1][ | SORRY... | | OFFSET TOO LARGE ][ MAIN MENU ]',0
alert_write_text:	; from: alert_write_error
	dc.b	'[1][ | WRITE PROTECTED OR | DISK IS FULL OR | HAS AN ERROR ][ SA'
	dc.b	'VE AGAIN ]',0
	dc.b	$00                             ; pad
alert_type_text:	; from: check_loaded_file
	dc.b	'[1][ | WRONG PACK TYPE ][ OKAY ]',0
	dc.b	$00                             ; pad
alert_rsc_text:	; from: main
	dc.b	'[3][ | RSC IS MISSING!!! ][ DESKTOP ]',0
alert_low_rez_text:	; from: main
	dc.b	'[3][ | Mnnn... | Low Rez is nice, But, | I prefer Medium or High'
	dc.b	'! ][ Okay ]',0
window_sizes:	; from: choose_rate
	dc.w	$0200,$0400,$0800,$1000,$2000,$3000,$4000,$5000 ; Pack-Ice's window for compaction rates 1 to 10, then a
                                                ;   0
	dc.w	$6000,$7000,$0000
	dc.b	$08                             ; not used
hex_digit_count:	; from: ask_offset, data_to_program, hex_to_number
	dc.b	$00                             ; the number of digits hex_to_number reads
	dc.w	$0000,$0000,$0000,$0000         ; not used
fsel_path:	; from: main, make_file_name, find_first_file
	dc.b	'A:\*.*',0                      ; the file selector's path, the boot drive filled in at start-up
	dcb.b	31,0
fsel_name:	; from: make_file_name, found_name_to_boxes
	dc.b	'FILENAME.EXT',0                ; the file selector's name
	dc.b	$00                             ; not used
percent_position:
	dc.w	$1b59,$2854                     ; VT52 cursor to row 8, column 52 (not used), then the percentage digits
percent_digits:	; from: old_pack, old_show_percent, show_percent, show_packed_length, percent, progress
	dc.b	$30,$30                         ; "XX" or "00".."99": the percentage made by percent and Pack-Ice's
                                                ;   progress call
	dc.w	$0000
fsel_block:	; from: file_selector
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
fsel_ok:	; from: pack_one_file, menu_chunk_packer, save_file, multi_file_packer
	dc.w	$0000                           ; intout[1]: 1 for OK, 0 for Cancel
fsel_addrin:	; from: file_selector
	dc.l	fsel_path                       ; the path and the name
	dc.l	fsel_name
fsel_addrout:	; from: file_selector
	dc.l	$00000000
file_dta:	; from: find_first_file
	dcb.b	30,0                            ; the DTA of Fsfirst/Fsnext
found_name:	; from: check_program_name, found_name_to_boxes
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; the DTA's file name
file_name:	; from: make_file_name, load_file, find_first_file, write_file
	dcb.b	54,0                            ; the full name of the file to load or save
file_type:                                      ; from: menu_pack_offset, menu_chunk_packer, pack_loaded,
                                                ;   pack_whole_file, multi_file_packer, reset_buffers, 3 more
	dc.b	$00                             ; 0 data, 1 program, 2 data from an offset
pack_programs:	; from: multi_file_packer
	dc.b	$00                             ; $ff: the multi file packer packs programs too
offset_length:	; from: reset_buffers, ask_offset, add_offset_data
	dc.l	$00000000                       ; PACK DATA (OFFSET): the length of the data left unpacked
packed_flag:	; from: pack_one_file, menu_chunk_packer, save_file, reset_buffers, check_loaded_file, find_file_type
	dc.w	$0000                           ; $ff: the loaded file is packed and is depacked instead
offset_gap:	; from: preferences, ask_offset, old_pack
	dc.l	$00000004                       ; bytes between the unpacked data and the packed data (4 or 8, set by
                                                ;   VERIFY)
source_ptr:                                     ; from: pack_one_file, depack_loaded, menu_chunk_packer,
                                                ;   pack_in_chunks_multi, pack_chunks, pack_whole_file, 9 more
	dc.l	$00028000                       ; the data to pack
source_length:                                  ; from: depack_loaded, menu_chunk_packer, pack_loaded, pack_in_chunks,
                                                ;   pack_in_chunks_multi, pack_chunks, 9 more
	dc.l	$00000000                       ; its length
build_ptr:                                      ; from: depack_loaded, menu_chunk_packer, pack_chunks, save_file,
                                                ;   multi_file_packer, reset_buffers, 7 more
	dc.l	$00020000                       ; where the packed file is built
packed_length:                                  ; from: pack_one_file, menu_chunk_packer, pack_chunks, save_file,
                                                ;   multi_file_packer, reset_buffers, 7 more
	dc.l	$00000000                       ; the packed length
old_window:	; from: old_pack
	dc.w	$0000                           ; read as a long by the old packer, whose low word is window_size's top
                                                ;   word
window_size:	; from: pack_source, choose_rate
	dc.l	$00001000                       ; Pack-Ice's window, from the compaction rate
stack_area:
	dcb.b	456,0                           ; the program's stack, up to program_stub

;------------------------------------------------------------------------------
; The program stub: a PRG header and the code that runs a packed program.  add_program_stub puts these $344
; bytes in front of the packed data; the packed data then follows at program_stub_end.  The stub depacks the
; program $400 bytes above its own text, relocates it, sets the basepage from its header, and runs a mover
; from the screen that copies it down over the stub and clears behind it.
;------------------------------------------------------------------------------
program_stub:	; from: main, add_program_stub
	bra.s	program_stub_text               ; the PRG magic $601a (bra.s past the header)
	dc.l	$00000328                       ; text length: the stub
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
stub_clear_screen:	; from: preferences
	clr.l	(a2)+                           ; clear them (a nop when PRINT HEADER is off)
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
stub_print_trap:	; from: preferences
	trap	#1                              ; Cconws, a nop when PRINT HEADER is off
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
	move.l	8(a0),(a2)                      ; its unpacked length
	lea	stub_depack_to(pc),a2
	movea.l	(a2),a1                         ; where it depacks to
	bsr.w	au5_depack                      ; depack
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
	dc.b	$1b                             ; VT52 cursor to row 0, column 5 (25 when not low resolution), then the
                                                ;   title
	dc.b	'Y %    AUTOMATION PACKER V5.0.1',0
	dc.b	$00                             ; pad

;------------------------------------------------------------------------------
; The depacker for 'AU5!' data (Pack-Ice's algorithm), part of both stubs: a0 = the packed data, a1 = where to
; depack it.  It works from the end of the packed data down, flashing the background colour as it copies
; literals.  A last bit set means the data was a picture whose planes were turned into bytes; they are put back.
;------------------------------------------------------------------------------
au5_depack:	; from: depack_loaded, menu_chunk_packer, verify_packed, data_to_program, program_stub
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	bsr.s	au5_get_long                    ; the magic
	cmpi.l	#$41553521,d0                   ; 'AU5!'?
	bne.w	au5_depack_done                 ; no: nothing to do
	bsr.s	au5_get_long                    ; the packed length
	lea	-$8(a0,d0.l),a5                 ; a5 = the end of the packed data
	bsr.s	au5_get_long                    ; the unpacked length
	move.l	d0,(sp)                         ; returned in d0
	movea.l	a1,a4                           ; a4 = the start of the output
	movea.l	a1,a6
	adda.l	d0,a6                           ; + the length
	movea.l	a6,a3                           ; a6 = its end, a3 too
	move.b	-(a5),d7                        ; the first bits
	bsr.w	au5_literals                    ; depack
	bsr.w	au5_get_bit                     ; a picture?
	bcc.s	au5_depack_done                 ; no
	move.w	#$f9f,d7                        ; 4000 groups of 16 pixels
au5_picture_group:
	moveq	#3,d6                           ; 4 words
au5_picture_word:
	move.w	-(a3),d4                        ; a word of 4 pixels
	moveq	#3,d5                           ; 4 pixels
au5_picture_pixel:
	add.w	d4,d4                           ; a bit to plane 0
	addx.w	d0,d0
	add.w	d4,d4                           ; plane 1
	addx.w	d1,d1
	add.w	d4,d4                           ; plane 2
	addx.w	d2,d2
	add.w	d4,d4                           ; plane 3
	addx.w	d3,d3
	dbra	d5,au5_picture_pixel            ; for each pixel
	dbra	d6,au5_picture_word             ; for each word
	movem.w	d0-d3,(a3)                      ; the 4 planes
	dbra	d7,au5_picture_group            ; for each group
au5_depack_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts

au5_get_long:	; from: au5_depack
	moveq	#3,d1                           ; 4 bytes
au5_get_long_loop:
	lsl.l	#8,d0
	move.b	(a0)+,d0                        ; a byte in
	dbra	d1,au5_get_long_loop
	rts

au5_literals:	; from: au5_depack, au5_get_bits
	bsr.s	au5_get_bit                     ; a literal run?
	bcc.s	au5_literals_done               ; no: a string
	moveq	#0,d1
	bsr.s	au5_get_bit                     ; one literal?
	bcc.s	au5_copy_literals               ; yes
	lea	au5_literal_bases(pc),a1        ; the run length codes
	moveq	#4,d3                           ; 5 sizes
au5_literal_size:
	move.l	-(a1),d0                        ; bits and all-ones value
	bsr.s	au5_get_bits                    ; read the bits
	swap	d0
	cmp.w	d0,d1                           ; all ones: the next size
	dbne	d3,au5_literal_size
	add.l	$14(a1),d1                      ; + the size's base
au5_copy_literals:
	move.w	d0,$ffff8240.w                  ; palette 0, flash the background
	move.b	-(a5),-(a6)                     ; copy a literal
	dbra	d1,au5_copy_literals            ; for each literal
au5_literals_done:
	cmpa.l	a4,a6                           ; all depacked?
	bgt.s	au5_string                      ; no: a string
	rts

au5_get_bit:	; from: au5_depack, au5_literals, au5_get_bits
	add.b	d7,d7                           ; the next bit
	bne.s	au5_get_bit_done                ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7
au5_get_bit_done:
	rts

au5_get_bits:	; from: au5_literals
	moveq	#0,d1                           ; d1 = d0+1 bits
au5_get_bits_loop:
	add.b	d7,d7                           ; the next bit
	bne.s	au5_get_bits_next               ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7
au5_get_bits_next:
	addx.w	d1,d1                           ; into d1
	dbra	d0,au5_get_bits_loop            ; for each bit
	rts
au5_string:	; from: au5_literals
	lea	au5_length_table(pc),a1         ; the length codes
	moveq	#3,d2                           ; up to 4 bits
au5_length_code:
	bsr.s	au5_get_bit
	dbcc	d2,au5_length_code              ; until a 0
	moveq	#0,d4
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the extra bits
	ext.w	d0
	bmi.s	au5_length_base                 ; none
	bsr.s	au5_get_bits                    ; read them
au5_length_base:
	move.b	6(a1,d2.w),d4                   ; + the base length
	add.w	d1,d4
	beq.s	au5_short_offset                ; length 2: a short offset
	lea	au5_offset_table(pc),a1         ; the offset codes
	moveq	#1,d2                           ; up to 2 bits
au5_offset_code:
	bsr.s	au5_get_bit
	dbcc	d2,au5_offset_code              ; until a 0
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the offset bits
	ext.w	d0
	bsr.s	au5_get_bits                    ; read them
	add.w	d2,d2                           ; words
	add.w	6(a1,d2.w),d1                   ; + the base offset
	bpl.s	au5_copy_string
	sub.w	d4,d1
	bra.s	au5_copy_string
au5_short_offset:
	moveq	#0,d1
	moveq	#5,d0                           ; 6 bits
	moveq	#-1,d2
	bsr.s	au5_get_bit                     ; 9 bits?
	bcc.s	au5_short_offset_bits           ; no
	moveq	#8,d0                           ; yes
	moveq	#63,d2
au5_short_offset_bits:
	bsr.s	au5_get_bits                    ; read them
	add.w	d2,d1                           ; + the base
au5_copy_string:
	lea	2(a6,d4.w),a1                   ; the string's source
	adda.w	d1,a1                           ; + the offset
	move.b	-(a1),-(a6)                     ; copy it
au5_copy_string_loop:
	move.b	-(a1),-(a6)
	dbra	d4,au5_copy_string_loop         ; for each byte
	bra.w	au5_literals                    ; and on
au5_literal_table:
	dc.l	$7fff000e,$00ff0007,$00070002,$00030001 ; bits and all-ones values of the run length codes
	dc.l	$00030001
au5_literal_bases:	; from: au5_literals
	dc.l	$0000010d,$0000000e,$00000007,$00000004 ; the run lengths they start at, less 1
	dc.l	$00000001
au5_length_table:
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; extra bits, then base lengths
au5_offset_table:
	dc.b	$0b,$04,$07,$00                 ; offset bits, then base offsets
	dc.w	$011f,$ffff,$001f
	dc.w	$0000
program_stub_end:	; from: program_stub
	dc.w	$0000,$0000                     ; the end of the program stub: the packed data follows it in a packed
                                                ;   program

;------------------------------------------------------------------------------
; The data stub: a PRG header and the code that depacks data to a fixed address and jumps to another.
; data_to_program puts its first $b0 bytes in front of the depacker and the packed data.  Note: $b0 bytes end
; 2 bytes before stub_depacker, where the stub's bsr.s goes, so the call lands 2 bytes into the copied
; depacker.
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
data_stub_user_call:	; from: main_menu, data_to_program
	bsr.s	super_swap                      ; back to user mode (a nop for SUPERVISOR MODE YES)
	movea.l	data_stub_execute(pc),a0        ; the execute address
	jmp	(a0)                            ; run it
data_stub_execute:	; from: data_to_program
	dc.l	$00000000                       ; EXECUTE AT
data_stub_depack_to:	; from: data_to_program
	dc.l	$00000000                       ; DEPACK AT
data_stub_title:
	dc.b	$1b                             ; VT52 cursor to row 0, column 5 (25 when not low resolution), then the
                                                ;   title
	dc.b	'Y %    AUTOMATION PACKER V5.0.1',0
	dc.b	$00                             ; pad

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
stub_depacker:	; from: data_stub
	dc.w	$0000                           ; the stub's call target

;------------------------------------------------------------------------------
; Centre current_tree, start the dialog with a growing box and draw it.
;------------------------------------------------------------------------------
open_dialog:                                    ; from: main_menu, pack_one_file, choose_chunk_size,
                                                ;   pack_in_chunks_multi, pack_chunks, pack_whole_file, 5 more
	jsr	form_center(pc)
	clr.w	aes_intin                       ; FMD_START
	jsr	form_dial(pc)
	move.w	#$1,aes_intin                   ; FMD_GROW
	jsr	form_dial(pc)
	jsr	draw_tree(pc)                   ; draw the tree
	rts

;------------------------------------------------------------------------------
; End the dialog: free the screen area and draw a shrinking box.
;------------------------------------------------------------------------------
close_dialog:                                   ; from: main_menu, pack_one_file, choose_chunk_size,
                                                ;   pack_in_chunks_multi, pack_chunks, pack_whole_file, 5 more
	move.w	#$3,aes_intin                   ; FMD_FINISH
	jsr	form_dial(pc)
	move.w	#$2,aes_intin                   ; FMD_SHRINK
	jsr	form_dial(pc)
	rts

;------------------------------------------------------------------------------
; Call the AES with aes_block; d0 = intout[0].
;------------------------------------------------------------------------------
aes:	; from: form_alert, form_dial, form_center, rsrc_free, rsrc_load, rsrc_gaddr, 4 more
	move.l	#aes_block,d1                   ; the parameter block
	move.w	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	move.w	aes_intout,d0                   ; intout[0]
	rts

;------------------------------------------------------------------------------
; form_alert: intin[0] = the default button, addrin[0] = the alert, both set by the caller.
;------------------------------------------------------------------------------
form_alert:	; from: main, check_loaded_file, alert_load_error, ask_offset, alert_write_error
	move.w	#$34,aes_control                ; opcode 52
	move.w	#$1,aes_control+2               ; 1 intin
	move.w	#$1,aes_control+4               ; 1 intout
	move.w	#$1,aes_control+6               ; 1 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	rts

;------------------------------------------------------------------------------
; form_dial: intin[0] = the mode (set by the caller), the small box at 0,0,0,0, the big box the dialog's.
;------------------------------------------------------------------------------
form_dial:	; from: preferences, open_dialog, close_dialog
	clr.w	aes_intin+2                     ; the small box
	clr.w	aes_intin+4
	clr.w	aes_intin+6
	clr.w	aes_intin+8
	move.w	dialog_x,aes_intin+10           ; the dialog's box
	move.w	dialog_y,aes_intin+12
	move.w	dialog_w,aes_intin+14
	move.w	dialog_h,aes_intin+16
	move.w	#$33,aes_control                ; opcode 51
	move.w	#$9,aes_control+2               ; 9 intin
	move.w	#$1,aes_control+4               ; 1 intout
	clr.w	aes_control+6                   ; 0 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	rts

;------------------------------------------------------------------------------
; form_center current_tree; the box it returns is kept in dialog_x/y/w/h.
;------------------------------------------------------------------------------
form_center:	; from: open_dialog
	move.l	current_tree,aes_addrin         ; the tree
	move.w	#$36,aes_control                ; opcode 54
	clr.w	aes_control+2                   ; 0 intin
	move.w	#$5,aes_control+4               ; 5 intout
	move.w	#$1,aes_control+6               ; 1 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	move.w	aes_intout+2,dialog_x           ; x
	move.w	aes_intout+4,dialog_y           ; y
	move.w	aes_intout+6,dialog_w           ; width
	move.w	aes_intout+8,dialog_h           ; height
	rts

;------------------------------------------------------------------------------
; rsrc_free.
;------------------------------------------------------------------------------
rsrc_free:	; from: main
	move.w	#$6f,aes_control                ; opcode 111
	clr.w	aes_control+2                   ; 0 intin
	move.w	#$1,aes_control+4               ; 1 intout
	clr.w	aes_control+6                   ; 0 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	rts

;------------------------------------------------------------------------------
; rsrc_load: addrin[0] = the file name, set by the caller.  d0 = 0 on failure.
;------------------------------------------------------------------------------
rsrc_load:	; from: main
	move.w	#$6e,aes_control                ; opcode 110
	clr.w	aes_control+2                   ; 0 intin
	move.w	#$1,aes_control+4               ; 1 intout
	move.w	#$1,aes_control+6               ; 1 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	rts

;------------------------------------------------------------------------------
; rsrc_gaddr: intin[0] = the type, intin[1] = the index, set by the caller.  current_tree = the address.
;------------------------------------------------------------------------------
rsrc_gaddr:	; from: main, choose_rate, data_to_program
	move.w	#$70,aes_control                ; opcode 112
	move.w	#$2,aes_control+2               ; 2 intin
	move.w	#$1,aes_control+4               ; 1 intout
	clr.w	aes_control+6                   ; 0 addrin
	move.w	#$1,aes_control+8               ; 1 addrout
	jsr	aes(pc)                         ; call
	move.l	aes_addrout,current_tree        ; the address
	rts

;------------------------------------------------------------------------------
; Draw the whole of current_tree inside the dialog's box.
;------------------------------------------------------------------------------
draw_tree:	; from: open_dialog
	clr.w	aes_intin                       ; from the root
	move.w	#$a,aes_intin+2                 ; 10 levels deep

;------------------------------------------------------------------------------
; objc_draw: intin[0] = the first object, intin[1] = the depth, set by the caller; clipped to the dialog's box.
;------------------------------------------------------------------------------
objc_draw:	; from: pack_chunks, old_show_percent, show_percent
	move.w	dialog_x,aes_intin+4            ; clip x
	move.w	dialog_y,aes_intin+6            ; clip y
	move.w	dialog_w,aes_intin+8            ; clip width
	move.w	dialog_h,aes_intin+10           ; clip height
	move.l	current_tree,aes_addrin         ; the tree
	move.w	#$2a,aes_control                ; opcode 42
	move.w	#$6,aes_control+2               ; 6 intin
	move.w	#$1,aes_control+4               ; 1 intout
	move.w	#$1,aes_control+6               ; 1 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	rts

;------------------------------------------------------------------------------
; graf_mouse: intin[0] = the form, set by the caller.
;------------------------------------------------------------------------------
graf_mouse:	; from: main
	move.w	#$4e,aes_control                ; opcode 78
	move.w	#$1,aes_control+2               ; 1 intin
	move.w	#$1,aes_control+4               ; 1 intout
	move.w	#$1,aes_control+6               ; 1 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	rts

;------------------------------------------------------------------------------
; form_do on current_tree; d0 = the exit object.  intin[0], the edit object, is what the last call left there.
;------------------------------------------------------------------------------
form_do:                                        ; from: main_menu, pack_one_file, choose_chunk_size, pack_whole_file,
                                                ;   multi_file_packer, preferences, 3 more
	move.l	current_tree,aes_addrin         ; the tree
	move.w	#$32,aes_control                ; opcode 50
	move.w	#$1,aes_control+2               ; 1 intin
	move.w	#$1,aes_control+4               ; 1 intout
	move.w	#$1,aes_control+6               ; 1 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	rts

;------------------------------------------------------------------------------
; objc_change: intin[0] = the object and intin[6] = the new state, set by the caller.  The redraw flag is the
; immediate at objc_change_redraw, set to 1 only while the preferences are up.
;------------------------------------------------------------------------------
objc_change:                                    ; from: main_menu, pack_one_file, choose_chunk_size, pack_whole_file,
                                                ;   multi_file_packer, preferences, 3 more
	move.l	current_tree,aes_addrin         ; the tree
	clr.w	aes_intin+2                     ; reserved
	move.w	dialog_x,aes_intin+4            ; clip x
	move.w	dialog_y,aes_intin+6            ; clip y
	move.w	dialog_w,aes_intin+8            ; clip width
	move.w	dialog_h,aes_intin+10           ; clip height
objc_change_redraw:
	move.w	#$0,aes_intin+14                ; redraw: patched by the preferences
	move.w	#$2f,aes_control                ; opcode 47
	move.w	#$8,aes_control+2               ; 8 intin
	move.w	#$1,aes_control+4               ; 1 intout
	move.w	#$1,aes_control+6               ; 1 addrin
	clr.w	aes_control+8                   ; 0 addrout
	jsr	aes(pc)                         ; call
	rts
aes_block:	; from: aes
	dc.l	aes_control                     ; the AES parameter block: control, global, intin, intout, addrin,
                                                ;   addrout
	dc.l	aes_global
	dc.l	aes_intin
	dc.l	aes_intout
	dc.l	aes_addrin
	dc.l	aes_addrout

;------------------------------------------------------------------------------
; Pack-Ice 2.31 by Axe of Superior, assembled into the program whole.  Its own start-up, menus and file handling
; below are not reached from the GEM front end, which calls only the packer (ice_pack with its checksums), and
; whose show_percent it calls back while packing.  The front end also uses ice_window, ice_length, ice_source,
; ice_dest and match_table.  ice_print is cut to an rts.  The packer writes 'AU5!' where Pack-Ice wrote 'ICE!'.
;------------------------------------------------------------------------------
ice_program:
	bra.w	ice_main                        ; Pack-Ice's start: over its notice
ice_notice:
	dc.b	'Pack-Ice: The best packer on the ST. It is Public Domain. You ma'
	dc.b	'y use it for packing anything you like. I don',$27
	dc.b	't want any donations. Greetings go to all people who use this pa'
	dc.b	'cker. ',0
	dc.b	$00                             ; pad
ice_main:
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
	move.w	ice_stub_relocate(pc),relocate_opcode ; keep the stub's relocation word
	move.w	ice_stub_clear_bss(pc),clear_bss_opcode ; and its BSS clearing word
	bsr.w	ice_appl_init                   ; appl_init
	bsr.w	ice_hide_mouse                  ; hide the mouse
	bsr.w	check_alternate                 ; Alternate held: text, not alerts
	bsr.w	ice_menu                        ; the menu
	bsr.w	ice_show_mouse                  ; show the mouse
	bsr.w	ice_appl_exit                   ; appl_exit
	bra.s	ice_quit                        ; quit

ice_appl_init:	; from: ice_program
	move.l	#$a000100,d0                    ; appl_init: opcode 10, 0 intin, 1 intout, 0 addrin
	bsr.w	ice_aes                         ; call
	move.w	d0,ice_ap_id                    ; the application id
	moveq	#-1,d7
	addq.w	#1,d0                           ; -1?
	beq.w	ice_quit                        ; yes: quit
	rts

ice_appl_exit:	; from: ice_program
	move.l	#$13000100,d0                   ; appl_exit: opcode 19, 0 intin, 1 intout, 0 addrin
	bsr.w	ice_aes                         ; call
	rts
ice_quit:	; from: ice_program, ice_appl_init
	move.w	d0,d7                           ; the exit code
	move.w	d7,-(sp)
	move.w	#$4c,-(sp)
	trap	#1                              ; Pterm

;------------------------------------------------------------------------------
; Pack-Ice's AES call: d0 holds the opcode and the intin, intout and addrin counts, a byte each, made into the
; control array (rsrc_gaddr also gets its addrout).  d0 = intout[0].
;------------------------------------------------------------------------------
ice_aes:	; from: ice_appl_init, ice_appl_exit, ice_menu, ice_alert, ice_show_mouse, ice_hide_mouse
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	lea	ice_control(pc),a0              ; clear control
	clr.l	(a0)+
	clr.l	(a0)+
	clr.w	(a0)
	movep.l	d0,-$7(a0)                      ; the four counts into the low bytes of control[0-3]
	cmpi.b	#$70,-$7(a0)                    ; rsrc_gaddr?
	bne.s	ice_aes_call                    ; no
	move.b	#$1,1(a0)                       ; yes: 1 addrout
ice_aes_call:
	lea	ice_aes_block(pc),a0            ; the parameter block
	move.l	a0,d1
	move.w	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	moveq	#0,d0
	move.w	ice_intout(pc),d0               ; intout[0]
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	rts
ice_aes_block:
	dc.l	ice_control                     ; Pack-Ice's AES parameter block: control, global, intin, intout,
                                                ;   addrin, addrout
	dc.l	ice_global
	dc.l	ice_intin
	dc.l	ice_intout
	dc.l	ice_addrin
	dc.l	ice_addrout

;------------------------------------------------------------------------------
; Pack-Ice uses alerts and the file selector unless Alternate is held when it starts.
;------------------------------------------------------------------------------
check_alternate:	; from: ice_program
	moveq	#0,d4                           ; text
	bsr.w	alternate_held                  ; Alternate held?
	bne.s	check_alternate_done            ; yes
	moveq	#1,d4                           ; no: alerts
check_alternate_done:
	move.w	d4,ice_gem
	rts

;------------------------------------------------------------------------------
; Pack-Ice's menu: data, a program or the offset (its window).  Then the picture or relocation question, the
; files to pack, and the loop over every file matching the name.
;------------------------------------------------------------------------------
ice_menu:	; from: ice_program, ice_save
	lea	ice_banner(pc),a0               ; the banner
	bsr.w	ice_print                       ; print
ice_menu_ask:
	tst.w	ice_gem                         ; alerts?
	beq.s	ice_menu_text                   ; no
	lea	alert_menu(pc),a0               ; "What do you wish to pack?"
	bsr.w	ice_alert                       ; alert
	addi.w	#$30,d0                         ; button 1-3 to '1'-'3'
	bra.s	ice_menu_button
ice_menu_text:
	lea	text_menu(pc),a0                ; "1) Crunch data file (Default) ... Please select: "
	bsr.w	ice_print                       ; print
ice_menu_key:
	bsr.w	ice_get_key                     ; a key
	cmpi.b	#$33,d0                         ; '3': parameters?
	bne.s	ice_menu_choice                 ; no
	lea	ice_newline(pc),a0              ; a new line
	bsr.w	ice_print                       ; print
	bsr.w	ice_ask_window                  ; ask for the offset
	lea	ice_newline(pc),a0              ; a new line
	bsr.w	ice_print                       ; print
	bra.s	ice_menu_ask                    ; the menu again
ice_menu_button:
	cmpi.b	#$33,d0                         ; SETUP?
	bne.s	ice_menu_choice                 ; no
	bsr.w	ice_ask_window                  ; ask for the offset
	bra.s	ice_menu_ask                    ; the menu again
ice_menu_choice:
	move.b	#$1,ice_data_mode               ; data
	cmpi.b	#$31,d0                         ; '1'?
	beq.s	ice_ask_picture                 ; yes
	cmpi.b	#$d,d0                          ; Return?
	beq.s	ice_ask_picture                 ; yes
	cmpi.b	#$32,d0                         ; '2'?
	bne.s	ice_menu_key                    ; no: another key
	clr.b	ice_data_mode                   ; a program
ice_ask_relocate:
	tst.w	ice_gem                         ; alerts?
	beq.s	ice_relocate_text               ; no
	lea	alert_relocate(pc),a0           ; "Relocate after decrunch?"
	bsr.w	ice_alert                       ; alert
	addi.w	#$6c,d0                         ; 1 to 'm', 2 to 'n'
	cmp.w	#$6e,d0                         ; NO?
	beq.s	ice_relocate_answer             ; yes
	moveq	#121,d0                         ; YES: 'y'
	bra.s	ice_relocate_answer
ice_relocate_text:
	lea	text_relocate(pc),a0            ; "Relocate program after depacking (Y/n): "
	bsr.w	ice_print                       ; print
	bsr.w	ice_get_key                     ; a key
ice_relocate_answer:
	move.w	relocate_opcode(pc),ice_stub_relocate ; the stub relocates
	move.w	clear_bss_opcode(pc),ice_stub_clear_bss ; and clears the BSS
	cmpi.b	#$d,d0                          ; Return?
	beq.s	ice_choose_files                ; yes: relocate
	ori.b	#$20,d0                         ; lower case
	cmpi.b	#$79,d0                         ; 'y'?
	beq.s	ice_choose_files                ; yes: relocate
	cmpi.b	#$6e,d0                         ; 'n'?
	bne.s	ice_ask_relocate                ; no: ask again
	move.w	#$602c,ice_stub_relocate        ; the stub skips the relocation
	move.w	#$6012,ice_stub_clear_bss       ; and the BSS clearing
	bra.s	ice_choose_files
ice_ask_picture:
	clr.w	picture_mode                    ; no picture compression
	tst.w	ice_gem                         ; alerts?
	beq.s	ice_picture_text                ; no
	lea	alert_picture(pc),a0            ; "Do you wish to use an additional algorithm for picture compression?"
	bsr.w	ice_alert                       ; alert
	cmp.w	#$1,d0                          ; NO?
	beq.s	ice_choose_files                ; yes
	bra.s	ice_picture_on                  ; YES
ice_picture_text:
	lea	text_picture(pc),a0             ; "Additional picture compression (N/y): "
	bsr.w	ice_print                       ; print
	bsr.w	ice_get_key                     ; a key
	cmp.b	#$79,d0                         ; 'y'?
	bne.s	ice_choose_files                ; no
ice_picture_on:
	move.w	#$1,picture_mode                ; picture compression
ice_choose_files:
	moveq	#-1,d3                          ; verify
	move.w	d3,verify_flag
	tst.w	ice_gem                         ; alerts?
	beq.w	ice_type_name                   ; no: type the name
	move.w	#$19,-(sp)
	trap	#1                              ; Dgetdrv
	addq.l	#2,sp
	lea	ice_fsel_path(pc),a4            ; the selector's path
	move.b	#$41,(a4)                       ; the drive letter
	add.b	d0,(a4)+
	move.b	#$3a,(a4)+                      ; :
	clr.w	-(sp)                           ; the current drive
	pea	(a4)
	move.w	#$47,-(sp)
	trap	#1                              ; Dgetpath
	addq.l	#8,sp
ice_path_end:
	tst.b	(a4)+                           ; find the end
	bne.s	ice_path_end
	move.b	#$5c,-$1(a4)                    ; \
	move.b	#$2a,(a4)+                      ; *
	move.b	#$2e,(a4)+                      ; .
	move.b	#$2a,(a4)+                      ; *
	clr.b	(a4)+
	bsr.w	ice_show_mouse                  ; show the mouse
	lea	ice_addrin(pc),a4               ; addrin
	move.l	#$5a000202,d0                   ; fsel_input: opcode 90, 0 intin, 2 intout, 2 addrin
	move.l	#ice_fsel_path,(a4)+            ; the path
	move.l	#ice_name,(a4)+                 ; the name
	bsr.w	ice_aes                         ; call
	tst.w	d0                              ; all right?
	beq.w	ice_another                     ; no: done
	move.l	ice_intout(pc),d4               ; intout[1] in the low word: the button
	bsr.w	ice_hide_mouse                  ; hide the mouse
	lea	ice_banner(pc),a0               ; the banner
	bsr.w	ice_print                       ; print
	tst.w	d4                              ; OK?
	beq.w	ice_another                     ; no: done
	lea	ice_fsel_path(pc),a2            ; the path
ice_path_scan:
	tst.b	(a2)+                           ; find its end
	bne.s	ice_path_scan
ice_path_backslash:
	cmpi.b	#$5c,-(a2)                      ; back to a \
	beq.s	ice_path_cut                    ; found
	cmpi.b	#$3a,(a2)                       ; the drive's :?
	bne.s	ice_path_backslash              ; no: on back
	addq.l	#1,a2                           ; yes:
	move.b	#$5c,(a2)                       ; a \ after it
ice_path_cut:
	clr.b	1(a2)                           ; end the path after the \
	lea	ice_fsel_path(pc),a4            ; the path
	cmpi.b	#$3a,1(a4)                      ; a drive?
	bne.s	ice_set_path                    ; no
	moveq	#14,d0                          ; Dsetdrv
	swap	d0
	move.b	(a4),d0                         ; the letter
	ori.b	#$20,d0                         ; lower case
	subi.b	#$61,d0                         ; the drive number
	move.l	d0,-(sp)
	trap	#1                              ; GEMDOS, Dsetdrv
	addq.l	#4,sp
	addq.l	#2,a4                           ; past the drive
ice_set_path:
	pea	(a4)                            ; the folder
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.l	d0                              ; all right?
	bmi.w	ice_another                     ; no: done
	lea	ice_name(pc),a2                 ; the name
	tst.b	(a2)                            ; any?
	bne.s	ice_first_file                  ; yes
	move.l	#$2a2e2a00,(a2)                 ; no: "*.*"
	bra.s	ice_first_file
ice_type_name:
	lea	text_source_prompt(pc),a0       ; "Enter name of source file: "
	bsr.w	ice_print                       ; print
	pea	ice_name_input(pc)              ; the input buffer
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	lea	ice_name(pc),a1                 ; the name
	adda.w	d0,a1                           ; + its length
	clr.b	(a1)                            ; ended
	lea	ice_newline(pc),a0              ; a new line
	bsr.w	ice_print                       ; print
ice_first_file:
	pea	ice_dta(pc)                     ; the DTA
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.l	#6,sp
	move.w	#$0,-(sp)                       ; normal files
	pea	ice_name(pc)                    ; the name
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.l	d0                              ; found?
	bmi.w	ice_another                     ; no: done
ice_pack_file:	; from: ice_save
	bsr.w	alloc_match_table               ; the string index
	bmi.s	ice_alloc_small                 ; none: without it
	move.l	ice_length(pc),d3               ; the file's length
	addi.l	#$8988,d3                       ; + $8988
	andi.w	#$fffe,d3                       ; even
	move.l	d3,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bpl.s	ice_block_ok                    ; yes
	bsr.w	free_match_table                ; no: free the index
ice_alloc_small:
	move.l	ice_length(pc),d3               ; the file's length
	addi.l	#$988,d3                        ; + $988
	andi.w	#$fffe,d3                       ; even
	move.l	d3,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bmi.w	ice_no_memory                   ; no: "Could not allocate enough memory"
ice_block_ok:
	addq.l	#1,d0                           ; even
	andi.w	#$fffe,d0
	move.l	d0,ice_dest                     ; the packed data goes at the start
	movea.l	d0,a0
	addi.l	#$974,d0                        ; the file $974 on
	move.l	d0,ice_source
	move.l	#$affeaffe,d0                   ; $affeaffe
	lsr.l	#3,d3                           ; in 8 byte steps
ice_fill_block:
	move.l	d0,(a0)+                        ; fill the block
	move.l	d0,(a0)+
	subq.l	#1,d3
	bne.s	ice_fill_block
	move.w	#$960,literal_check             ; the first output check
	bsr.w	ice_open                        ; open the file
	bmi.w	ice_menu_done                   ; failed: stop
	movea.l	ice_source(pc),a0               ; read it
	move.l	ice_length(pc),d0               ; its length
	bsr.w	ice_read
	bmi.w	ice_menu_done                   ; failed: stop
	bsr.w	ice_close                       ; close it
	move.l	ice_length(pc),d1               ; the length
	add.l	ice_source(pc),d1               ; + the source
	move.l	d1,ice_source_end               ; = its end
	lea	text_working(pc),a0             ; "Working: "
	bsr.w	ice_print                       ; print
	tst.w	match_table                     ; the index?
	bpl.s	ice_working_index               ; yes
	lea	text_no_index(pc),a0            ; no: "~"
	bsr.w	ice_print                       ; print
ice_working_index:
	tst.w	picture_mode                    ; picture compression?
	beq.s	ice_working_name                ; no
	lea	text_picture_mark(pc),a0        ; "P>"
	bsr.w	ice_print                       ; print
ice_working_name:
	lea	ice_dta_name(pc),a0             ; the file's name
	bsr.w	ice_print                       ; print
	clr.w	alt_pressed                     ; Alternate not pressed
	bsr.w	time_ticks                      ; start the clock
	bsr.w	picture_convert                 ; picture compression
	bsr.w	ice_pack                        ; pack
	movea.l	d0,a3                           ; a3 = the packed length
	tst.l	d0
	bmi.w	ice_menu_done                   ; failed: stop
	bsr.w	print_time                      ; print the time
	tst.w	alt_pressed                     ; Alternate pressed?
	bne.w	ice_skipped                     ; yes: skip the file
	tst.w	too_many_literals               ; too many literals?
	beq.s	ice_check_length                ; no
	lea	text_cannot_pack(pc),a0         ; " Data cannot be packed!  [cancelled]"
	bsr.w	ice_print                       ; print
	bra.w	ice_next_file                   ; free the block
ice_check_length:
	lea	(a3),a1                         ; the packed length
	tst.b	ice_data_mode                   ; data?
	bne.s	ice_packed_end                  ; yes
	adda.w	#$1c0,a1                        ; no: + the stub
ice_packed_end:
	move.l	a1,packed_end
	movea.l	ice_length(pc),a2               ; the file's length
	cmpa.l	a2,a1                           ; longer?
	bge.w	ice_larger                      ; yes: "Larger than original!"
	tst.w	verify_flag                     ; verify?
	beq.w	ice_save                        ; no: save
	lea	text_verify(pc),a0              ; "    Verify: "
	bsr.w	ice_print                       ; print
	move.l	ice_length(pc),d1               ; the file's length
	addi.l	#$271a,d1                       ; + $271a
	move.l	d1,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bpl.s	ice_verify                      ; yes
	lea	text_no_mem(pc),a0              ; no: "No mem!"
	bsr.w	ice_print                       ; print
	bra.w	ice_save                        ; and save without verifying
ice_verify:
	movea.l	d0,a4                           ; the block
	movea.l	d0,a2
	move.l	d0,verify_copy                  ; kept
	move.l	a3,d1                           ; the packed length
	subq.l	#1,d1
	movea.l	ice_dest(pc),a1                 ; the packed data
ice_verify_copy:
	move.b	(a1)+,(a2)+                     ; copy it to the block
	dbra	d1,ice_verify_copy              ; 64 K at a time
	subi.l	#$10000,d1
	bpl.s	ice_verify_copy
	movea.l	a4,a0                           ; the copy
	bsr.w	ice_depack                      ; depack it (only 'ICE!' data: the packer writes 'AU5!' now)
	lea	$64(a4),a2                      ; the block, $64 on
	adda.l	ice_length(pc),a2               ; + the length
	move.l	a2,d0
	andi.w	#$fffe,d0                       ; even
	move.l	d0,verify_read_buffer           ; = where the file is read back
	bsr.w	ice_open                        ; open the file again
ice_verify_read:
	movea.l	verify_read_buffer(pc),a0       ; the buffer
	move.l	#$2710,d0                       ; 10000 bytes
	bsr.w	ice_read                        ; read
	move.l	d0,d4                           ; d4 = what was read
	beq.s	ice_verify_close                ; nothing?
	cmpi.l	#$2710,d0
	bcc.s	ice_verify_compare              ; all 10000?
ice_verify_close:
	bsr.w	ice_close                       ; close it
	move.l	d4,d0
ice_verify_compare:
	movea.l	verify_read_buffer(pc),a2       ; what was read
	subq.w	#1,d0
	bmi.s	ice_verify_block_done
ice_verify_loop:
	move.b	(a2)+,d1                        ; a byte read
	move.b	(a4)+,d2                        ; and the depacked one
	cmp.b	d1,d2                           ; the same?
	bne.s	ice_verify_error                ; no: error
	dbra	d0,ice_verify_loop              ; for each byte
ice_verify_block_done:
	cmpi.l	#$2710,d4                       ; 10000 read: on
	beq.s	ice_verify_read
	lea	text_ok(pc),a0                  ; "OK! "
	bsr.w	ice_print                       ; print
	bsr.w	ice_free_verify                 ; free the copy
	bra.s	ice_save                        ; save
ice_verify_error:
	lea	text_error(pc),a0               ; "Error!        [cancelled]"
	bsr.w	ice_print                       ; print
	bsr.w	ice_free_verify                 ; free the copy
	bra.w	ice_next_file                   ; and do not save

ice_free_verify:	; from: ice_menu
	move.l	verify_copy(pc),-(sp)           ; the copy
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; Save the packed file over the original: data as it is, a program behind ice_stub (its text length set to the
; stub and the data, the packed and unpacked lengths patched in) with an empty relocation table.
;------------------------------------------------------------------------------
ice_save:	; from: ice_menu
	bsr.w	print_rate                      ; print the rate
	cmpi.b	#$1,ice_data_mode               ; data?
	beq.s	ice_save_data                   ; yes
	movea.w	#$1c0,a4                        ; the stub's length
	movea.l	a3,a5                           ; the packed length
	lea	-$1c(a5,a4.w),a5                ; + the stub less its header
	move.l	a5,d0
	addq.l	#1,d0                           ; made even
	andi.w	#$fffe,d0
	move.l	d0,ice_stub_text_length         ; is the stub's text length
	move.l	a3,d0                           ; the packed length
	moveq	#120,d1                         ; less 120
	sub.l	d1,d0
	move.l	d0,ice_stub_packed_end+2        ; into the stub
	move.l	ice_length(pc),ice_stub_unpacked_end+2 ; the unpacked length into the stub
	bsr.w	ice_create                      ; create the file
	bmi.w	ice_menu_done                   ; failed: stop
	lea	ice_stub(pc),a5                 ; the stub
	movea.w	#$1c0,a6                        ; $1c0 bytes
	bsr.w	ice_write                       ; write it
	bmi.w	ice_menu_done                   ; failed: stop
	movea.l	ice_dest(pc),a5                 ; the packed data
	move.l	a3,d0                           ; its length
	addq.l	#1,d0                           ; made even
	andi.w	#$fffe,d0
	movea.l	d0,a6
	bsr.w	ice_write                       ; write it
	bmi.w	ice_menu_done                   ; failed: stop
	lea	zero_long(pc),a5                ; a 0 long
	clr.l	(a5)
	movea.w	#$4,a6                          ; 4 bytes
	bsr.w	ice_write                       ; write it: no relocation
	bmi.w	ice_menu_done                   ; failed: stop
	bsr.w	ice_close                       ; close
	bmi.w	ice_menu_done                   ; failed: stop
	bra.s	ice_next_file
ice_save_data:
	bsr.w	ice_create                      ; create the file
	movea.l	ice_dest(pc),a5                 ; the packed data
	movea.l	a3,a6                           ; its length
	bsr.w	ice_write                       ; write it
	bmi.w	ice_menu_done                   ; failed: stop
	bsr.w	ice_close                       ; close
	bra.s	ice_next_file
ice_skipped:	; from: ice_menu
	lea	text_alt(pc),a0                 ; "   <ALT> was pressed. File is skipped."
	bsr.w	ice_print                       ; print
	bra.s	ice_next_file
ice_larger:	; from: ice_menu
	lea	text_larger(pc),a0              ; "    Larger than original!   [cancelled]"
	bsr.w	ice_print                       ; print
ice_next_file:	; from: ice_menu
	move.l	ice_dest(pc),-(sp)              ; the block
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	tst.l	d0                              ; all right?
	bne.s	ice_menu_done                   ; no: stop
	bsr.w	free_match_table                ; free the index
	move.w	#$4f,-(sp)
	trap	#1                              ; Fsnext
	addq.l	#2,sp
	tst.l	d0                              ; found?
	bpl.w	ice_pack_file                   ; yes: pack it
ice_another:	; from: ice_menu
	tst.w	ice_gem                         ; alerts?
	beq.s	ice_another_text                ; no
	lea	alert_another(pc),a0            ; "Do you wish to pack another file?"
	bsr.w	ice_alert                       ; alert
	cmp.w	#$1,d0                          ; YES?
	beq.w	ice_menu                        ; yes: the menu
	cmp.w	#$2,d0                          ; NO?
	beq.s	ice_menu_done                   ; yes: done
ice_another_text:
	lea	ice_newline(pc),a0              ; a new line
	bsr.w	ice_print                       ; print
	lea	text_another(pc),a0             ; "Crunch another file (Y/n): "
	bsr.w	ice_print                       ; print
	bsr.w	ice_get_key                     ; a key
	ori.b	#$20,d0                         ; lower case
	cmpi.b	#$6e,d0                         ; 'n'?
	beq.s	ice_menu_done                   ; yes: done
	bra.w	ice_menu                        ; no: the menu
ice_no_memory:	; from: ice_menu
	lea	text_no_memory(pc),a0           ; "Could not allocate enough memory"
	bsr.w	ice_print                       ; print
	bsr.w	ice_raw_key                     ; wait for a key
ice_menu_done:	; from: ice_menu
	rts

;------------------------------------------------------------------------------
; File calls on the found name (ice_dta_name) and ice_handle; the flags are set from d0.
;------------------------------------------------------------------------------
ice_open:	; from: ice_menu
	clr.w	-(sp)                           ; read only
	pea	ice_dta_name(pc)                ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.w	d0,ice_handle                   ; the handle
	tst.l	d0
	rts

ice_read:	; from: ice_menu
	pea	(a0)                            ; to a0
	move.l	d0,-(sp)                        ; d0 bytes
	move.w	ice_handle(pc),-(sp)            ; the handle
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	adda.w	#$c,sp
	tst.l	d0
	rts

ice_create:	; from: ice_save
	move.w	#$0,-(sp)                       ; normal file
	pea	ice_dta_name(pc)                ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	move.w	d0,ice_handle                   ; the handle
	tst.l	d0
	rts

ice_write:	; from: ice_save
	move.l	a5,-(sp)                        ; from a5
	move.l	a6,-(sp)                        ; a6 bytes
	move.w	ice_handle(pc),-(sp)            ; the handle
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	tst.l	d0
	rts

ice_close:	; from: ice_menu, ice_save
	move.w	ice_handle(pc),-(sp)            ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.l	d0
	rts

ice_get_key:	; from: ice_menu, ice_save
	move.w	#$1,-(sp)
	trap	#1                              ; Cconin
	addq.l	#2,sp
	rts

ice_raw_key:	; from: ice_save
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

;------------------------------------------------------------------------------
; Pack-Ice's text output, cut short: the rts makes it print nothing.
;------------------------------------------------------------------------------
ice_print:	; from: ice_menu, ice_save, print_time, ice_ask_window, print_rate, picture_convert
	rts
ice_print_text:
	move.l	a0,-(sp)                        ; the string
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; The 200 Hz ticks since the last call, in elapsed_ticks.
;------------------------------------------------------------------------------
time_ticks:	; from: ice_menu, print_time
	pea	read_ticks(pc)                  ; Supexec(read_ticks)
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.l	#6,sp
	rts
read_ticks:
	move.l	$4ba.w,d0                       ; _hz_200, the 200 Hz counter
	sub.l	last_ticks(pc),d0               ; less the last
	move.l	d0,elapsed_ticks
	move.l	$4ba.w,last_ticks               ; _hz_200, keep it
	rts

;------------------------------------------------------------------------------
; Print the packing time as minutes:seconds.
;------------------------------------------------------------------------------
print_time:	; from: ice_menu
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	lea	text_time(pc),a0                ; "Time:" at its place
	bsr.s	ice_print                       ; print
	bsr.s	time_ticks                      ; the ticks
	move.l	elapsed_ticks(pc),d0
	divu.w	#$c8,d0                         ; seconds
	swap	d0
	clr.w	d0
	swap	d0
	divu.w	#$3c,d0                         ; minutes and seconds
	moveq	#0,d1
	move.w	d0,d1                           ; d1 = the minutes
	swap	d0
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
	swap	d1
	tst.w	d1                              ; more?
	bne.s	time_minute_digit               ; yes
	move.l	#$200020,(a0)+                  ; two spaces after them
	lea	time_digits_end(pc),a0          ; the third word
	move.w	-(a0),d0
	bsr.w	ice_put_char                    ; printed
	move.w	-(a0),d0
	bsr.w	ice_put_char                    ; printed
	move.w	-(a0),d0
	bsr.w	ice_put_char                    ; printed
	moveq	#58,d0                          ; :
	bsr.w	ice_put_char                    ; printed
	move.l	d2,d0                           ; the seconds
	divu.w	#$a,d0                          ; tens
	addi.w	#$30,d0                         ; to a character
	bsr.w	ice_put_char                    ; printed
	swap	d0                              ; units
	addi.w	#$30,d0                         ; to a character
	bsr.w	ice_put_char                    ; printed
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts
time_digits:
	dc.w	$0000,$0000,$0000               ; the minutes' digits, a word each, units first
time_digits_end:
	dc.w	$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; "Please enter the offset": Pack-Ice's window in hex, 5 to $1528 (its current value is the default).
;------------------------------------------------------------------------------
ice_ask_window:	; from: ice_menu
	lea	text_window_prompt_end(pc),a1   ; the end of "$0000"
	move.l	ice_window(pc),d0               ; the window
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
	bsr.w	ice_print                       ; print
	lea	offset_input(pc),a3             ; the input buffer
	move.b	#$4,(a3)                        ; 4 characters
	pea	(a3)
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	moveq	#0,d2
	move.b	1(a3),d2                        ; the count
	beq.s	ice_ask_window_done             ; none: keep the window
	adda.l	d2,a3
	addq.l	#2,a3                           ; past the last character
	moveq	#0,d4                           ; the value
	moveq	#0,d3                           ; the shift
	subq.w	#1,d2
	bmi.s	ice_ask_window
window_input_digit:
	moveq	#0,d0
	move.b	-(a3),d0                        ; a character, from the last
	subi.b	#$30,d0                         ; '0'-'9'?
	bmi.s	window_bad_digit                ; below: 0
	cmpi.b	#$9,d0
	ble.s	window_add_digit                ; yes
	addi.b	#$30,d0
	ori.b	#$20,d0                         ; lower case
	subi.b	#$57,d0                         ; 'a'-'f'?
	cmpi.b	#$9,d0
	ble.s	window_bad_digit
	cmpi.b	#$f,d0
	ble.s	window_add_digit                ; yes
window_bad_digit:
	moveq	#0,d0                           ; anything else: 0
window_add_digit:
	lsl.w	d3,d0                           ; to its place
	add.l	d0,d4                           ; added
	addq.w	#4,d3                           ; the next place
	dbra	d2,window_input_digit           ; for each character
	move.l	#$1528,d0                       ; at most $1528
	cmp.l	d0,d4
	bcs.s	window_check_low
	move.l	d0,d4
window_check_low:
	cmp.w	#$5,d4                          ; at least 5
	bcc.s	window_set
	moveq	#5,d4
window_set:
	move.l	d4,ice_window                   ; the window
ice_ask_window_done:
	rts

;------------------------------------------------------------------------------
; Start the progress: a check every 128th of the length.
;------------------------------------------------------------------------------
progress_init:	; from: ice_crunch
	move.l	d0,-(sp)
	move.l	ice_length(pc),d0               ; the length
	lsr.l	#7,d0                           ; / 128
	move.l	d0,progress_step                ; the step
	move.l	ice_source(pc),progress_next    ; the first check at the start
	move.w	#$ffff,progress_last            ; no percentage shown yet
	move.l	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; Called by the packer with a0 = its position: at each step, the percentage done goes to percent_digits and
; the front end's show_percent.  Alternate stops the packing: the end is moved to the position.
;------------------------------------------------------------------------------
progress:	; from: ice_crunch
	cmpa.l	progress_next(pc),a0            ; the next check reached?
	bcs.w	progress_skip                   ; no
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	move.l	progress_step(pc),d0            ; the step
	add.l	d0,progress_next                ; the next check
	move.l	a0,d1                           ; the position
	move.l	ice_source_end(pc),d0           ; the end
	move.l	ice_source(pc),d2               ; the start
	sub.l	d2,d1                           ; done
	sub.l	d2,d0                           ; the whole
	bsr.w	scale_down                      ; both to 16 bits
	mulu.w	#$64,d1                         ; * 100
	bsr.w	scale_down                      ; to 16 bits again
	tst.w	d0
	beq.s	progress_done
	divu.w	d0,d1                           ; the percentage
	swap	d1
	clr.w	d1
	swap	d1
	cmp.w	progress_last(pc),d1            ; changed?
	beq.s	progress_done                   ; no
	move.w	d1,progress_last                ; yes: kept
	divu.w	#$a,d1                          ; tens and units
	move.l	#$300030,d0                     ; '0' '0'
	add.l	d1,d0                           ; + the digits
	lea	text_remaining_percent(pc),a0   ; Pack-Ice's own text (not used)
	move.b	d0,percent_digits               ; tens
	swap	d0
	move.b	d0,percent_digits+1             ; units
	bsr.w	show_percent                    ; show it
	bsr.w	alternate_held                  ; Alternate held?
	beq.s	progress_done                   ; no
progress_wait_alternate:
	bsr.w	alternate_held                  ; wait for it to be let go
	bne.s	progress_wait_alternate
	move.w	#$ffff,alt_pressed              ; Alternate pressed
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	move.l	a0,ice_source_end               ; the packing ends here
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
print_rate:	; from: ice_save
	lea	text_rate(pc),a0                ; " Rate: "
	bsr.w	ice_print                       ; print
	move.l	ice_length(pc),d0               ; the length
	move.l	packed_end(pc),d1               ; the packed length
	bsr.w	scale_down                      ; both to 16 bits
	mulu.w	#$64,d1                         ; * 100
	bsr.w	scale_down                      ; to 16 bits again
	divu.w	d0,d1                           ; the percentage
	move.l	d1,d0
	swap	d0
	clr.w	d0
	swap	d0
	divu.w	#$a,d0                          ; tens and units
	addi.l	#$300030,d0                     ; to characters
	bsr.w	ice_put_char                    ; print tens
	swap	d0
	bsr.w	ice_put_char                    ; print units
	lea	text_saving(pc),a0              ; "% [saving]"
	bsr.w	ice_print                       ; print
	rts

;------------------------------------------------------------------------------
; Halve d0 and d1 together until both fit 16 bits.
;------------------------------------------------------------------------------
scale_down:	; from: progress, print_rate
	swap	d0
	swap	d1
	tst.w	d0                              ; d0 over 16 bits?
	bne.s	scale_down_halve                ; yes
	tst.w	d1                              ; d1?
	bne.s	scale_down_halve                ; yes
	swap	d0
	swap	d1
	rts
scale_down_halve:
	swap	d0
	swap	d1
	lsr.l	#1,d0                           ; halve
	lsr.l	#1,d1
	bra.s	scale_down                      ; again

ice_put_char:	; from: print_time, print_rate
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
ice_alert:	; from: ice_menu, ice_save
	bsr.w	ice_show_mouse                  ; show the mouse
	move.l	#$34010101,d0                   ; form_alert: opcode 52, 1 intin, 1 intout, 1 addrin
	move.w	#$1,ice_intin                   ; default button 1
	move.l	a0,ice_addrin                   ; the alert
	bsr.w	ice_aes                         ; call
	move.w	ice_intout(pc),-(sp)            ; the button
	bsr.w	ice_hide_mouse                  ; hide the mouse
	moveq	#0,d0
	move.w	(sp)+,d0
	rts

ice_show_mouse:	; from: ice_program, ice_menu, ice_alert
	move.l	#$4e010101,d0                   ; graf_mouse: opcode 78, 1 intin, 1 intout, 1 addrin
	move.w	#$101,ice_intin                 ; M_ON
	bsr.w	ice_aes                         ; call
	move.l	#$4e010101,d0                   ; graf_mouse
	move.w	#$0,ice_intin                   ; ARROW
	bsr.w	ice_aes                         ; call
	rts

ice_hide_mouse:	; from: ice_program, ice_menu, ice_alert
	move.l	#$4e010101,d0                   ; graf_mouse: opcode 78, 1 intin, 1 intout, 1 addrin
	move.w	#$100,ice_intin                 ; M_OFF
	bsr.w	ice_aes                         ; call
	rts

;------------------------------------------------------------------------------
; Picture compression: a file of 32000 bytes plus a header under $104 bytes is taken to be a low resolution
; screen; its plane words are turned into one nibble per pixel, which packs better.  The depacker turns them
; back.  Anything else is marked with a '-'.
;------------------------------------------------------------------------------
picture_convert:	; from: ice_menu
	clr.w	picture_converted               ; not converted
	tst.w	picture_mode                    ; picture compression?
	beq.s	picture_convert_done            ; no
	movea.l	ice_source(pc),a1               ; the source
	move.l	ice_length(pc),d1               ; its length
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
	addq.w	#8,a1
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
not_a_picture:
	lea	text_not_picture(pc),a0         ; the '-' mark
	bsr.w	ice_print                       ; print
	bra.s	picture_convert_done
ice_window:	; from: pack_source, ice_ask_window, ice_crunch
	dc.l	$00001580                       ; the window: how far back strings are looked for (set by the front end
                                                ;   from the compaction rate)

;------------------------------------------------------------------------------
; Take $30010 bytes for the string index; match_table is negative when there is not enough memory.
;------------------------------------------------------------------------------
alloc_match_table:	; from: ice_menu
	pea	$30010                          ; Malloc($30010)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bgt.s	match_table_set                 ; yes
	moveq	#-1,d0                          ; no: none
match_table_set:	; from: free_match_table
	move.l	d0,match_table
	rts

free_match_table:	; from: ice_menu, ice_save
	move.l	match_table(pc),d0              ; the index
	move.w	#$ffff,match_table              ; none any more
	tst.l	d0                              ; was there one?
	bmi.s	match_table_set                 ; no
	move.l	d0,-(sp)                        ; yes: Mfree
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; The front end's pack call: three checksums of the source for its verify (two sums and a running xor from
; 'EGB!'), then the packer.
;------------------------------------------------------------------------------
ice_pack:	; from: pack_source, ice_menu
	movea.l	ice_source,a0                   ; the source
	move.l	ice_length,d7                   ; its length
	moveq	#0,d0
	moveq	#0,d1                           ; sum
	moveq	#0,d2                           ; sum of the inverted bytes
	move.l	#$45474221,d3                   ; 'EGB!': the running xor
ice_checksum:
	move.b	(a0)+,d0                        ; a byte
	add.l	d0,d1                           ; sum it
	not.l	d0                              ; inverted
	add.l	d0,d2                           ; sum that
	not.l	d0
	eor.l	d1,d3                           ; xor both sums in
	eor.l	d2,d3
	subq.l	#1,d7                           ; for each byte
	bne.w	ice_checksum
	move.l	d1,checksum_sum                 ; kept for the verify
	move.l	d2,checksum_not_sum
	move.l	d3,checksum_xor
	bsr.s	ice_crunch                      ; pack
	rts

;------------------------------------------------------------------------------
; The packer: ice_source/ice_length to ice_dest as 'AU5!', the packed length, the unpacked length, then a bit
; stream the depacker reads from the end down.  At each position it takes the longest of a run of equal bytes
; and the strings found within ice_window behind (through match_table, or by a plain search when there is
; none), and writes literal counts, offsets and lengths as variable-length codes.  d0 = the packed length.
;------------------------------------------------------------------------------
ice_crunch:	; from: ice_pack
	clr.w	too_many_literals               ; no literal overflow
	clr.l	match_table_base                ; no index yet
	move.l	#$8000,d0                       ; the index is rebuilt every $8000
	sub.l	ice_window(pc),d0               ; less the window
	move.l	d0,match_table_span             ; bytes
	bsr.w	progress_init                   ; start the progress
	movea.l	ice_source(pc),a0               ; the source
	move.l	ice_length(pc),d0               ; its length
	movea.l	ice_dest(pc),a1                 ; the output
	lea	0(a0,d0.l),a2                   ; the end of the source
	move.l	a2,ice_source_end
	move.l	#$41553521,d7                   ; 'AU5!'
	bsr.w	put_long                        ; written
	addq.l	#4,a1                           ; the packed length later
	move.l	ice_length(pc),d7               ; the unpacked length
	bsr.w	put_long                        ; written
	moveq	#0,d5                           ; no literals yet
	moveq	#7,d6                           ; 8 bits to go in the byte
	moveq	#0,d7                           ; the bit byte
	moveq	#0,d4                           ; 1 bit
	move.w	picture_converted(pc),d1        ; the picture flag
	bsr.w	put_bits                        ; written
crunch_loop:
	bsr.w	progress                        ; the progress
	lea	$409(a0),a4                     ; the longest run
	cmpa.l	ice_source_end(pc),a4           ; past the end?
	ble.s	crunch_run                      ; no
	movea.l	ice_source_end(pc),a4           ; yes: to the end
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
	move.l	d1,run_length
	cmp.l	#$409,d1                        ; the longest?
	beq.w	crunch_code_run                 ; yes: code it as a string
	movea.l	a0,a3                           ; the window's end
	adda.l	ice_window(pc),a3
	cmpa.l	ice_source_end(pc),a3           ; past the end?
	ble.s	crunch_search                   ; no
	movea.l	ice_source_end(pc),a3           ; yes: to the end
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
	move.l	a0,match_table_base
	movea.l	match_table(pc),a2              ; the index
	bsr.w	count_pairs                     ; count the pairs
	movea.l	a2,a4
	adda.l	#$20002,a4                      ; past the counts: the position lists
	lea	1(a6),a5                        ; the pairs
	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2
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
	bpl.s	index_fill                      ; 32 K of them
	bsr.w	count_pairs                     ; the counts back to list starts
crunch_index:
	move.l	a0,d0
	sub.l	a6,d0
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
	add.l	a6,d0
	cmp.l	a0,d0                           ; this one?
	bne.s	index_find_self                 ; no: on
	move.l	a2,d0
	sub.l	a4,d0
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
	moveq	#-20,d0
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
	move.w	match_length(pc),d0
	adda.w	d0,a0                           ; past the string
crunch_next:
	move.l	ice_source_end(pc),d0           ; the end
	sub.l	a0,d0
	subq.l	#3,d0                           ; 3 or more left?
	bpl.w	crunch_loop                     ; yes: on
crunch_tail:
	cmpa.l	ice_source_end(pc),a0           ; the end?
	bge.s	crunch_end                      ; yes
	move.b	(a0)+,(a1)+                     ; copy the rest
	addq.l	#1,d5                           ; as literals
	bra.s	crunch_tail
crunch_end:
	bsr.w	put_literal_count               ; the literal count
	bset	d6,d7                           ; the end marker bit
	move.b	d7,(a1)+                        ; the last bits
	suba.l	ice_dest(pc),a1                 ; the packed length
	move.l	a1,d0
	move.l	d0,d7
	movea.l	ice_dest(pc),a1                 ; the output
	addq.l	#4,a1                           ; after the magic
	bsr.w	put_long                        ; the packed length
	rts

;------------------------------------------------------------------------------
; The code writers: each sets d1 = the bits and d4 = their count - 1 and goes to put_bits.  The literal count:
; a run of up to $810d literals; longer and the packing is given up (the end moved here).
;------------------------------------------------------------------------------
put_literal_count:	; from: ice_crunch
	cmp.l	#$810d,d5                       ; too long?
	bls.s	literal_count_range             ; no
	move.w	#$ffff,too_many_literals        ; yes: give up
	move.l	a0,ice_source_end               ; here
literal_count_range:
	lea	literal_bits(pc),a3             ; the bases
	moveq	#6,d3                           ; 7 ranges
literal_count_find:
	move.w	-(a3),d4
	cmp.w	d4,d5                           ; in this range?
	dbge	d3,literal_count_find           ; no: the one below
	sub.w	d4,d5                           ; less its start
	add.w	d3,d3
	lea	literal_bits(pc),a3             ; the bits table
	adda.w	d3,a3
	move.b	(a3)+,d2                        ; the prefix
	ext.w	d2
	moveq	#-1,d1
	lsl.l	d2,d1                           ; its ones
	or.w	d5,d1                           ; the count
	moveq	#0,d5                           ; no literals
	move.b	(a3)+,d4                        ; the bit count
	ext.w	d4
	subq.w	#1,d4
	bra.w	put_bits                        ; write them
literal_bases:
	dc.w	$0000,$0001,$0002,$0005,$0008,$000f,$010e ; the literal counts the ranges start at
literal_bits:
	dc.b	$01,$01,$01,$02,$02,$04,$02,$06,$03,$09,$08,$11,$0f,$20 ; each range's prefix length and bit count

put_offset:	; from: ice_crunch
	lea	offset_table(pc),a3             ; the offset table
	moveq	#2,d3                           ; 3 ranges
offset_find:
	add.w	d3,d3
	move.w	0(a3,d3.w),d4
	lsr.w	#1,d3
	cmp.w	d4,d0                           ; in this range?
	dbge	d3,offset_find                  ; no: the one below
	sub.w	d4,d0                           ; less its start
	add.w	d3,d3
	move.w	6(a3,d3.w),d3                   ; its prefix and bits
	move.w	d3,d4
	lsr.w	#8,d3
	moveq	#-1,d1
	lsl.w	d3,d1                           ; the prefix
	or.w	d0,d1                           ; the offset
	andi.w	#$f,d4                          ; the bit count
	bra.w	put_bits                        ; write them
offset_table:
	dc.w	$0000,$0020,$0120,$0606,$0908,$0c0d ; range starts, then prefix length and bit count

put_short_offset:	; from: ice_crunch
	cmpi.w	#$23f,d0                        ; over $23f?
	bhi.w	crunch_literal                  ; yes: a literal
	move.w	d0,d1
	cmpi.w	#$3f,d1                         ; 6 bits?
	ble.s	short_offset_6                  ; yes
	subi.w	#$40,d1                         ; no: 9 bits
	moveq	#9,d4
	bset	d4,d1                           ; and a 1
	bra.w	put_bits                        ; write them
short_offset_6:
	moveq	#6,d4                           ; 6 bits + the 0
	bra.s	put_bits                        ; write them

put_length:	; from: ice_crunch
	lea	length_table(pc),a3             ; the length table
	move.w	match_length(pc),d0             ; the length
	moveq	#4,d5                           ; 5 ranges
length_find:
	move.b	0(a3,d5.w),d4
	ext.w	d4
	cmp.w	d4,d0                           ; in this range?
	dbge	d5,length_find                  ; no: the one below
	sub.w	d4,d0                           ; less its start
	move.b	5(a3,d5.w),d4                   ; its bits
	ext.w	d4
	moveq	#-1,d1
	lsl.w	d4,d1                           ; the prefix
	or.w	d0,d1                           ; the length
	add.w	d5,d4
	subq.w	#1,d4                           ; the bit count
	bra.s	put_bits                        ; write them
length_table:
	dc.b	$02,$03,$04,$06,$0a,$01,$01,$02,$03,$0a ; range starts, then bit counts

put_bits:	; from: ice_crunch, put_literal_count, put_offset, put_short_offset, put_length
	lsr.l	#1,d1                           ; a bit
	roxr.b	#1,d7                           ; into the byte
	dbra	d6,put_bits_next                ; full?
	move.b	d7,(a1)+                        ; yes: write it
	moveq	#0,d7
	moveq	#7,d6
put_bits_next:
	dbra	d4,put_bits                     ; for each bit
	rts

put_long:	; from: ice_crunch
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
; Build the index's counts: for the 32 K positions from a6, how many times each pair of bytes comes, then the
; counts summed so that each pair's slot holds where its list starts.
;------------------------------------------------------------------------------
count_pairs:	; from: ice_crunch
	lea	2(a2),a4                        ; the counts
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
	dbra	d0,clear_counts
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
	dbra	d0,count_pair
	clr.w	-(a4)                           ; the first slot starts at 0
	move.w	#$1fff,d0
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
	dbra	d0,sum_counts
	rts

;------------------------------------------------------------------------------
; Pack-Ice's program stub, written in front of a packed program by ice_save: a PRG header whose text is the stub
; and the packed data, then code that depacks the program 120 bytes past the packed data's start, relocates it
; to run at the stub's own text, sets the basepage, and runs a mover placed past the BSS that copies it down,
; clears the BSS and starts it.
;------------------------------------------------------------------------------
ice_stub:	; from: ice_save
	bra.s	ice_stub_text                   ; the PRG magic $601a (bra.s past the header)
ice_stub_text_length:	; from: ice_save
	dc.l	$000001a4                       ; text length: patched
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; data, BSS, symbols, reserved, flags, absolute flag
	dc.w	$0000,$0001,$ffff
ice_stub_text:
	bra.s	ice_stub_start                  ; over the name
	dc.b	'Pack-Ice'                      ; 'Pack-Ice'
ice_stub_start:
	lea	ice_stub_text+$21c(pc),a4       ; a4 = where the program depacks to: 120 bytes past the packed data,
                                                ;   which follows the stub's $1a4 bytes
	movea.l	a4,a5
ice_stub_packed_end:
	adda.l	#$deadface,a5                   ; a5 = the end of the packed data: the immediate is patched
	movea.l	a4,a6
ice_stub_unpacked_end:
	adda.l	#$fadedead,a6                   ; a6 = the end of the depacked program: patched
	bsr.w	ice_stub_depack                 ; depack
	movea.l	4(sp),a5                        ; a5 = the basepage
	lea	ice_stub_text(pc),a6            ; a6 = where the program will run
	lea	$1c(a4),a3                      ; a3 = its depacked text
ice_stub_relocate:	; from: ice_program, ice_menu
	movem.l	-$1a(a3),d0-d3                  ; its text, data, BSS and symbol lengths (a bra.s past the relocation
                                                ;   when it is off)
	lea	0(a3,d0.l),a0
	adda.l	d1,a0
	adda.l	d3,a0                           ; a0 = the relocation table
	move.l	a6,d0                           ; where it will run
	move.l	(a0)+,d1                        ; the first address
	beq.s	ice_stub_relocated              ; none
	adda.l	d1,a3
	moveq	#0,d1
ice_stub_relocate_long:
	add.l	d0,(a3)                         ; relocate a long
ice_stub_relocate_next:
	move.b	(a0)+,d1                        ; the next step
	beq.s	ice_stub_relocated              ; the end
	cmpi.b	#$1,d1                          ; 1: 254 on?
	bne.s	ice_stub_relocate_step          ; no
	adda.w	#$fe,a3                         ; yes
	bra.s	ice_stub_relocate_next
ice_stub_relocate_step:
	adda.l	d1,a3
	bra.s	ice_stub_relocate_long          ; relocate it
ice_stub_relocated:
	lea	2(a4),a3                        ; the lengths in the header
	addq.l	#8,a5                           ; the basepage's text address
	movea.l	(a5)+,a2
	move.l	(a3),(a5)+                      ; text length
	move.l	(a3),d2
	adda.l	(a3)+,a2
	move.l	a2,(a5)+                        ; data address
	move.l	(a3),(a5)+                      ; data length
	add.l	(a3),d2
	adda.l	(a3)+,a2
	move.l	a2,(a5)+                        ; BSS address
	move.l	(a3),(a5)+                      ; BSS length
	adda.l	(a3)+,a2
	add.l	(a3),d2
	adda.l	(a3)+,a2
	adda.w	#$2cc,a2                        ; past the BSS
	moveq	#7,d0                           ; 8 longs
	lea	(a2),a0                         ; the mover goes here
	lea	ice_stub_mover(pc),a3           ; the mover
ice_stub_copy_mover:
	move.l	(a3)+,(a2)+                     ; copied
	dbra	d0,ice_stub_copy_mover
	lea	$1c(a4),a1                      ; the depacked text
	lsr.l	#3,d2                           ; in 8 byte steps
	movea.l	a6,a3                           ; where it runs
	jmp	(a0)                            ; run the mover
ice_stub_mover:
	move.l	(a1)+,(a3)+                     ; copy 8 bytes
	move.l	(a1)+,(a3)+
	subq.l	#1,d2
	bpl.s	ice_stub_mover
ice_stub_clear_bss:	; from: ice_program, ice_menu
	movea.l	-$e8(a6),a3                     ; the BSS (a bra.s past the clearing when it is off)
	move.l	-$e4(a6),d1                     ; its length
	lsr.l	#3,d1                           ; in 8 byte steps
	suba.l	a0,a0
ice_stub_clear_loop:
	move.l	a0,(a3)+                        ; clear 8 bytes
	move.l	a0,(a3)+
	subq.l	#1,d2                           ; (counted with d2, -1 after the copy, so once)
	bpl.s	ice_stub_clear_loop
	jmp	(a6)                            ; run the program

ice_stub_depack:	; from: ice_stub
	move.b	-(a5),d7                        ; the first bits
ice_stub_literals:	; from: ice_stub_get_bits
	bsr.s	ice_stub_get_bit                ; a literal run?
	bcc.s	ice_stub_literals_done          ; no: a string
	moveq	#0,d1
	bsr.s	ice_stub_get_bit                ; one literal?
	bcc.s	ice_stub_copy_literals          ; yes
	lea	ice_stub_literal_bases(pc),a1   ; the run length codes
	moveq	#4,d3                           ; 5 sizes
ice_stub_literal_size:
	move.l	-(a1),d0                        ; bits and all-ones value
	bsr.s	ice_stub_get_bits               ; read the bits
	swap	d0
	cmp.w	d0,d1                           ; all ones: the next size
	dbne	d3,ice_stub_literal_size
	add.l	$14(a1),d1                      ; + the size's base
ice_stub_copy_literals:
	move.b	-(a5),-(a6)                     ; copy a literal
	dbra	d1,ice_stub_copy_literals       ; for each literal
ice_stub_literals_done:
	cmpa.l	a4,a6                           ; all depacked?
	bgt.s	ice_stub_string                 ; no: a string
	rts

ice_stub_get_bit:	; from: ice_stub_depack, ice_stub_get_bits
	add.b	d7,d7                           ; the next bit
	bne.s	ice_stub_get_bit_done           ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7
ice_stub_get_bit_done:
	rts

ice_stub_get_bits:	; from: ice_stub_depack
	moveq	#0,d1                           ; d1 = d0+1 bits
ice_stub_get_bits_loop:
	add.b	d7,d7                           ; the next bit
	bne.s	ice_stub_get_bits_next          ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7
ice_stub_get_bits_next:
	addx.w	d1,d1                           ; into d1
	dbra	d0,ice_stub_get_bits_loop       ; for each bit
	rts
ice_stub_string:	; from: ice_stub_depack
	lea	ice_stub_length_table(pc),a1    ; the length codes
	moveq	#3,d2                           ; up to 4 bits
ice_stub_length_code:
	bsr.s	ice_stub_get_bit
	dbcc	d2,ice_stub_length_code         ; until a 0
	moveq	#0,d4
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the extra bits
	ext.w	d0
	bmi.s	ice_stub_length_base            ; none
	bsr.s	ice_stub_get_bits               ; read them
ice_stub_length_base:
	move.b	6(a1,d2.w),d4                   ; + the base length
	add.w	d1,d4
	beq.s	ice_stub_short_offset           ; length 2: a short offset
	lea	ice_stub_offset_table(pc),a1    ; the offset codes
	moveq	#1,d2                           ; up to 2 bits
ice_stub_offset_code:
	bsr.s	ice_stub_get_bit
	dbcc	d2,ice_stub_offset_code         ; until a 0
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the offset bits
	ext.w	d0
	bsr.s	ice_stub_get_bits               ; read them
	add.w	d2,d2                           ; words
	add.w	6(a1,d2.w),d1                   ; + the base offset
	bpl.s	ice_stub_copy_string
	sub.w	d4,d1
	bra.s	ice_stub_copy_string
ice_stub_short_offset:
	moveq	#0,d1
	moveq	#5,d0                           ; 6 bits
	moveq	#-1,d2
	bsr.s	ice_stub_get_bit                ; 9 bits?
	bcc.s	ice_stub_short_offset_bits      ; no
	moveq	#8,d0                           ; yes
	moveq	#63,d2
ice_stub_short_offset_bits:
	bsr.s	ice_stub_get_bits               ; read them
	add.w	d2,d1                           ; + the base
ice_stub_copy_string:
	lea	2(a6,d4.w),a1                   ; the string's source
	adda.w	d1,a1                           ; + the offset
	move.b	-(a1),-(a6)                     ; copy it
ice_stub_copy_string_loop:
	move.b	-(a1),-(a6)
	dbra	d4,ice_stub_copy_string_loop    ; for each byte
	bra.w	ice_stub_literals               ; and on
ice_stub_literal_table:
	dc.l	$7fff000e,$00ff0007,$00070002,$00030001 ; bits and all-ones values of the run length codes
	dc.l	$00030001
ice_stub_literal_bases:	; from: ice_stub_depack
	dc.l	$0000010d,$0000000e,$00000007,$00000004 ; the run lengths they start at, less 1
	dc.l	$00000001
ice_stub_length_table:
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; extra bits, then base lengths
ice_stub_offset_table:
	dc.b	$0b,$04,$07,$00                 ; offset bits, then base offsets
	dc.w	$011f,$ffff,$001f

;------------------------------------------------------------------------------
; Pack-Ice's own depacker, for its verify: depacks 'ICE!' data at a0 in place.  It depacks 120 bytes higher,
; keeping the 120 bytes it overwrites past the end in its stack frame, then moves the data down and puts them
; back.
;------------------------------------------------------------------------------
ice_depack:	; from: ice_menu
	link	a3,#-120                        ; 120 bytes of frame
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	lea	$78(a0),a4                      ; the output, 120 bytes on
	movea.l	a4,a6
	bsr.s	ice_get_long                    ; the magic
	cmpi.l	#$49434521,d0                   ; 'ICE!'?
	bne.w	ice_depack_done                 ; no: nothing to do
	bsr.s	ice_get_long                    ; the packed length
	lea	-$8(a0,d0.l),a5                 ; a5 = the end of the packed data
	bsr.s	ice_get_long                    ; the unpacked length
	move.l	d0,(sp)                         ; returned in d0
	adda.l	d0,a6                           ; a6 = the end of the output
	movea.l	a6,a1
	moveq	#119,d0                         ; 120 bytes
ice_depack_save:
	move.b	-(a1),-(a3)                     ; kept in the frame
	dbra	d0,ice_depack_save
	movea.l	a6,a3
	move.b	-(a5),d7                        ; the first bits
	bsr.s	ice_literals                    ; depack
	movea.l	a3,a5
	bsr.s	ice_get_bit                     ; a picture?
	bcc.s	ice_depack_move                 ; no
	move.w	#$f9f,d7                        ; 4000 groups of 16 pixels
ice_picture_group:
	moveq	#3,d6                           ; 4 words
ice_picture_word:
	move.w	-(a3),d4                        ; a word of 4 pixels
	moveq	#3,d5                           ; 4 pixels
ice_picture_pixel:
	add.w	d4,d4                           ; a bit to plane 0
	addx.w	d0,d0
	add.w	d4,d4                           ; plane 1
	addx.w	d1,d1
	add.w	d4,d4                           ; plane 2
	addx.w	d2,d2
	add.w	d4,d4                           ; plane 3
	addx.w	d3,d3
	dbra	d5,ice_picture_pixel            ; for each pixel
	dbra	d6,ice_picture_word             ; for each word
	movem.w	d0-d3,(a3)                      ; the 4 planes
	dbra	d7,ice_picture_group            ; for each group
ice_depack_move:
	movem.l	(sp),d0-d7/a0-a3                ; the length, the start, a3 = the frame
ice_depack_move_loop:
	move.b	(a4)+,(a0)+                     ; move it down 120 bytes
	subq.l	#1,d0
	bne.s	ice_depack_move_loop
	moveq	#119,d0                         ; 120 bytes
ice_depack_restore:
	move.b	-(a3),-(a5)                     ; put back
	dbra	d0,ice_depack_restore
ice_depack_done:	; from: ice_stub
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	unlk	a3
	rts

ice_get_long:	; from: ice_depack
	moveq	#3,d1                           ; 4 bytes
ice_get_long_loop:
	lsl.l	#8,d0
	move.b	(a0)+,d0                        ; a byte in
	dbra	d1,ice_get_long_loop
	rts

ice_literals:	; from: ice_depack, ice_get_bits
	bsr.s	ice_get_bit                     ; a literal run?
	bcc.s	ice_literals_done               ; no: a string
	moveq	#0,d1
	bsr.s	ice_get_bit                     ; one literal?
	bcc.s	ice_copy_literals               ; yes
	lea	ice_literal_bases(pc),a1        ; the run length codes
	moveq	#4,d3                           ; 5 sizes
ice_literal_size:
	move.l	-(a1),d0                        ; bits and all-ones value
	bsr.s	ice_get_bits                    ; read the bits
	swap	d0
	cmp.w	d0,d1                           ; all ones: the next size
	dbne	d3,ice_literal_size
	add.l	$14(a1),d1                      ; + the size's base
ice_copy_literals:
	move.b	-(a5),-(a6)                     ; copy a literal
	dbra	d1,ice_copy_literals            ; for each literal
ice_literals_done:
	cmpa.l	a4,a6                           ; all depacked?
	bgt.s	ice_string                      ; no: a string
	rts

ice_get_bit:	; from: ice_depack, ice_literals, ice_get_bits
	add.b	d7,d7                           ; the next bit
	bne.s	ice_get_bit_done                ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7
ice_get_bit_done:
	rts

ice_get_bits:	; from: ice_literals
	moveq	#0,d1                           ; d1 = d0+1 bits
ice_get_bits_loop:
	add.b	d7,d7                           ; the next bit
	bne.s	ice_get_bits_next               ; any left?
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7
ice_get_bits_next:
	addx.w	d1,d1                           ; into d1
	dbra	d0,ice_get_bits_loop            ; for each bit
	rts
ice_string:	; from: ice_literals
	lea	ice_length_table(pc),a1         ; the length codes
	moveq	#3,d2                           ; up to 4 bits
ice_length_code:
	bsr.s	ice_get_bit
	dbcc	d2,ice_length_code              ; until a 0
	moveq	#0,d4
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the extra bits
	ext.w	d0
	bmi.s	ice_length_base                 ; none
	bsr.s	ice_get_bits                    ; read them
ice_length_base:
	move.b	6(a1,d2.w),d4                   ; + the base length
	add.w	d1,d4
	beq.s	ice_short_offset                ; length 2: a short offset
	lea	ice_offset_table(pc),a1         ; the offset codes
	moveq	#1,d2                           ; up to 2 bits
ice_offset_code:
	bsr.s	ice_get_bit
	dbcc	d2,ice_offset_code              ; until a 0
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the offset bits
	ext.w	d0
	bsr.s	ice_get_bits                    ; read them
	add.w	d2,d2                           ; words
	add.w	6(a1,d2.w),d1                   ; + the base offset
	bpl.s	ice_copy_string
	sub.w	d4,d1
	bra.s	ice_copy_string
ice_short_offset:
	moveq	#0,d1
	moveq	#5,d0                           ; 6 bits
	moveq	#-1,d2
	bsr.s	ice_get_bit                     ; 9 bits?
	bcc.s	ice_short_offset_bits           ; no
	moveq	#8,d0                           ; yes
	moveq	#63,d2
ice_short_offset_bits:
	bsr.s	ice_get_bits                    ; read them
	add.w	d2,d1                           ; + the base
ice_copy_string:
	lea	2(a6,d4.w),a1                   ; the string's source
	adda.w	d1,a1                           ; + the offset
	move.b	-(a1),-(a6)                     ; copy it
ice_copy_string_loop:
	move.b	-(a1),-(a6)
	dbra	d4,ice_copy_string_loop         ; for each byte
	bra.w	ice_literals                    ; and on
ice_literal_table:
	dc.l	$7fff000e,$00ff0007,$00070002,$00030001 ; bits and all-ones values of the run length codes
	dc.l	$00030001
ice_literal_bases:	; from: ice_literals
	dc.l	$0000010d,$0000000e,$00000007,$00000004 ; the run lengths they start at, less 1
	dc.l	$00000001
ice_length_table:
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; extra bits, then base lengths
ice_offset_table:
	dc.b	$0b,$04,$07,$00                 ; offset bits, then base offsets
	dc.w	$011f,$ffff,$001f
	dc.w	$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; Pack-Ice's variables and texts.
;------------------------------------------------------------------------------
ice_dta:	; from: ice_menu
	dcb.b	26,0                            ; Pack-Ice's DTA
ice_length:	; from: pack_source, verify_packed, ice_menu, ice_save, progress_init, print_rate, 3 more
	dc.l	$00000000                       ; the DTA's file length: the length to pack (the front end sets it too)
ice_dta_name:	; from: ice_menu, ice_open, ice_create
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; the DTA's file name
	dc.w	$0000,$0000                     ; not used
	move.w	d0,d0
	dcb.b	48,0
	dc.w	$0500,$0000,$0000,$0000
ice_newline:	; from: ice_menu, ice_save
	dc.b	10,13,0
text_source_prompt:	; from: ice_menu
	dc.b	13,10,10,'Enter name of source file: ',0
text_dest_prompt:
	dc.b	10,13,'Enter name of destination file: ',0 ; not used
text_no_memory:	; from: ice_save
	dc.b	'Could not allocate enough memory',10,13,0
text_working:	; from: ice_menu
	dc.b	10,13,'Working: ',0
text_picture_mark:	; from: ice_menu
	dc.b	'P>',0
text_another:	; from: ice_save
	dc.b	10,13,'Crunch another file (Y/n): ',0
text_relocate:	; from: ice_menu
	dc.b	13,10,10,'Relocate program after depacking (Y/n): ',0
text_picture:	; from: ice_menu
	dc.b	13,10,10,'Additional picture compression (N/y): ',0
text_window_prompt:	; from: ice_ask_window
	dc.b	13,10,'Please enter the offset (Default: $0000'
text_window_prompt_end:	; from: ice_ask_window
	dc.b	'): $',0
text_menu:	; from: ice_menu
	dc.b	10,13,'1) Crunch data file (Default)',10,13,'2) Crunch executable file'
	dc.b	10,13,'3) Set Parameters',10,13,'Please select: ',0
text_no_mem:	; from: ice_menu
	dc.b	'No mem!',0
text_verify:	; from: ice_menu
	dc.b	'    Verify: ',0
text_ok:	; from: ice_menu
	dc.b	'OK! ',0
text_error:	; from: ice_menu
	dc.b	'Error!        [cancelled]',0
text_cannot_pack:	; from: ice_menu
	dc.b	'    Data cannot be packed!  [cancelled]',0
text_remaining:
	dcb.w	45,$1b44                        ; not used: cursor left 45 and right 24 times, "Remaining: " and the
                                                ;   percentage
	dcb.w	24,$1b43
	dc.b	'Remaining: '
text_remaining_percent:	; from: progress
	dc.b	'99%',0
	dc.b	$00
text_not_picture:	; from: picture_convert
	dcb.w	25,$1b44                        ; cursor left 25 and right 9 times, then "-"
	dcb.w	9,$1b43
	dc.w	$2d00
text_no_index:	; from: ice_menu
	dc.b	'~',0                           ; "~": packing without the string index
text_time:	; from: print_time
	dcb.w	45,$1b44                        ; cursor left 45 and right 24 times, then "Time:" and back 10 places
	dcb.w	24,$1b43
	dc.b	'Time: ',9,'      '
	dc.b	$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$00,$00
text_rate:	; from: print_rate
	dc.b	'  Rate: ',0
text_saving:	; from: print_rate
	dc.b	'% [saving]',0
text_alt:	; from: ice_save
	dc.b	'   <ALT> was pressed. File is skipped.',0
text_larger:	; from: ice_save
	dc.b	'    Larger than original!   [cancelled]',0
ice_banner:	; from: ice_menu
	dc.w	$1b45
	dc.b	$1b
	dc.b	'f',10
	dc.b	' ~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~'
	dc.b	'-~-~-~-~-~-~-~',13,10
	dc.b	' |   Version 2.31                                               '
	dc.b	'             |',13,10
	dc.b	' {                          P A C K - I C E                     '
	dc.b	'             }',13,10
	dc.b	' |                                                              '
	dc.b	'             |',13,10
	dc.b	' {             This packer was written by Axe of Superior.      '
	dc.b	'             }',13,10
	dc.b	' |       First version: 14.02.1990    Final changes: 19.02.1991 '
	dc.b	'             |',13,10
	dc.b	' {                                                              '
	dc.b	'             }',13,10
	dc.b	' ~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~'
	dc.b	'-~-~-~-~-~-~-~',13,10,10,0
	dc.b	$00
alert_menu:	; from: ice_menu
	dc.b	'[0][| What do you wish to pack?  |  - Data files |  - Executable'
	dc.b	' files |  - Set Parameters ][ DATA | EXEC | SETUP ]',0
alert_relocate:	; from: ice_menu
	dc.b	'[0][| Relocate after decrunch?  |  ][ YES | NO ]',0
alert_another:	; from: ice_save
	dc.b	'[2][| Do you wish to pack | another file?|][ YES | NO | ??? ]',0
alert_picture:	; from: ice_menu
	dc.b	'[0][| Do you wish to use an | additional algorithm  | for pictur'
	dc.b	'e compression? |][ NO | YES ]',0
	dc.b	$00

	section	bss
ice_control:	ds.b	32                      ; Pack-Ice's AES arrays: control
ice_global:	ds.b	30
ice_addrin:	ds.b	12
ice_addrout:	ds.b	4
ice_intin:	ds.b	256
ice_intout:	ds.b	768
ice_ap_id:	ds.b	2                       ; Pack-Ice's application id
offset_input:	ds.b	6                       ; Cconrs buffer for the offset: the maximum, the count, 4 characters
ice_gem:	ds.b	2                       ; 1: Pack-Ice asks with alerts (Alternate was not held at its start), 0:
                                                ;   with text
picture_mode:	ds.b	2                       ; 1: additional picture compression
picture_converted:	ds.b	2               ; 1: the picture's planes were turned into bytes before packing
verify_copy:	ds.b	4                       ; Pack-Ice's verify: the block holding the depacked copy
match_table:	ds.b	4                       ; the packer's string index ($30010 bytes), negative for none; the front
                                                ;   end points it above the source,, where the verify depacks afterwards
match_table_base:	ds.b	4               ; the position the index was last built at
match_table_span:	ds.b	4               ; how far the packer goes before rebuilding the index: $8000 less the
                                                ;   window
relocate_opcode:	ds.b	2               ; the stub's original word at ice_stub_relocate
clear_bss_opcode:	ds.b	2               ; the stub's original word at ice_stub_clear_bss
verify_read_buffer:	ds.b	4               ; where the verify reads the written file back
verify_flag:	ds.b	2                       ; nonzero: verify the written file
elapsed_ticks:	ds.b	4                       ; 200 Hz ticks since the last time_ticks
last_ticks:	ds.b	4                       ; _hz_200 at the last time_ticks
packed_end:	ds.b	4                       ; the end of the packed data, with the stub's length for a program
ice_handle:	ds.b	2                       ; the file handle
ice_data_mode:	ds.b	2                       ; 1: packing data, 0: a program
zero_long:	ds.b	8                       ; written after a packed program as its empty relocation table
ice_source:	ds.b	4                       ; the data to pack
ice_source_end:	ds.b	4                       ; its end (moved down when the packer gives up)
ice_dest:	ds.b	4                       ; where the packed data goes
run_length:	ds.b	4                       ; the length of the run of equal bytes at the current position
match_length:	ds.b	2                       ; the best string's length
match_offset:	ds.b	2                       ; and its offset
literal_check:	ds.b	2                       ; literals before the next check that the output has not caught up with
                                                ;   the input
alt_pressed:	ds.b	2                       ; nonzero: Alternate was pressed while packing
too_many_literals:	ds.b	2               ; nonzero: a literal run too long to code
ice_fsel_path:	ds.b	80                      ; Pack-Ice's file selector path
ice_name_input:	ds.b	2                       ; Cconrs buffer: the maximum and the count
ice_name:	ds.b	20                      ; the name to pack (Pack-Ice's file selector name or the typed name)
dialog_x:	ds.b	2                       ; the dialog's box from form_center
dialog_y:	ds.b	2
dialog_w:	ds.b	2
dialog_h:	ds.b	2
current_tree:	ds.b	4                       ; the tree the AES calls work on (also rsrc_gaddr's result)
tree_main:	ds.b	4                       ; the resource's trees
tree_multi:	ds.b	4
tree_preferences:	ds.b	4
tree_rate:	ds.b	4
tree_progress:	ds.b	4
tree_result:	ds.b	4
tree_data_program:	ds.b	4
tree_chunk_size:	ds.b	4
tree_offset:	ds.b	4
text_title:	ds.b	4                       ; the texts written to: "AUTOMATION COMPACTER VERSION XXXXX"
text_title2:	ds.b	4                       ; the same, the line printed at the top of the screen
text_progress_file:	ds.b	4               ; "CURRENT FILE IS: XXXXXXXX.XXX"
text_progress_length:	ds.b	4               ; "FILE LENGTH    $00000 BYTES"
text_progress_percent:	ds.b	4               ; "PERCENTAGE ALREADY PACKED %XX"
text_progress_chunk:	ds.b	4               ; "CHUNK XXX OF XXX"
text_result_file:	ds.b	4               ; "CURRENT FILE IS: XXXXXXXX.XXX"
text_result_length:	ds.b	4               ; "NORMAL LENGTH  $00000 BYTES"
text_result_packed:	ds.b	4               ; "PACKED LENGTH  $00000 BYTES"
text_result_percent:	ds.b	4               ; "PERCENTAGE OF ORIGINAL LENGTH %XX"
text_depack_at:	ds.b	4                       ; DEPACK AT $_____
text_execute_at:	ds.b	4               ; EXECUTE AT $_____
text_offset:	ds.b	4                       ; Offset: $_____
chunk_size:	ds.b	4                       ; the chunk size
chunk_limit:	ds.b	4                       ; 95% of it: a packed chunk must be shorter
chunk_number:	ds.b	2                       ; the chunk being packed
chunk_file_length:	ds.b	4               ; the file's length, kept while packing chunks
chunk_mode:	ds.b	2                       ; 1: chunk packing
data_mode:	ds.b	2                       ; 1: PACK/DEPACK DATA
buffer_pack:	ds.b	2                       ; 1: buffer pack (magic 'AU5$')
chunk_count:	ds.b	2                       ; the number of chunks (+ 4 once the header is made)
chunks_left:	ds.b	2                       ; whole chunks still to pack
multi_chunk_size:	ds.b	4               ; the multi chunk packer's chunk size
last_chunk_length:	ds.b	2               ; the last chunk's length (a word, read as a long by pack_chunks)
chunk_header:	ds.b	4                       ; the 'AU5C' header
chunk_table_ptr:	ds.b	4               ; the next entry of its table
chunk_total:	ds.b	4                       ; the length of the chunked file
aes_control:	ds.b	24                      ; the AES arrays: control
aes_global:	ds.b	30
aes_intin:	ds.b	40
aes_intout:	ds.b	40
aes_addrin:	ds.b	40
aes_addrout:	ds.b	40
saved_registers:	ds.b	120             ; the registers while the percentage is drawn
free_memory:	ds.b	4                       ; the largest free block less $8980, at start-up
checksum_sum:	ds.b	4                       ; Pack-Ice's checksums of the source: the sum of the bytes
checksum_not_sum:	ds.b	4               ; the sum of the inverted bytes
checksum_xor:	ds.b	4                       ; both sums xored together after each byte, from 'EGB!'
bss_end:

	end
