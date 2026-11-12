; PACK2_51.PRG  -  Automation Packer 2.51 ("AUTOMATION COMPACTER VERSION 2.51"), the GEM version
; Devpac source of the program, disassembled by Darren Birks, 11 November 2026.
; Text 9634 bytes, data 0 bytes, bss 416 bytes.
;
; PACK2_51.PRG as distributed is packed itself: a 6582 byte Automation packed program, with the stub of
; "AUTOMATION PACKER V2.5r" and 'LSD!' data.  This is the source of the 10292 byte program that stub depacks.
;
; This source rebuilds that unpacked program byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o PACK2_51.PRG PACK2_51.S
; It needs PACK2_51.RSC beside it to run.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; The main dialog credits the program to Ozz of L.S.D. (1990) and the GEM front end to The Stainless Steel Rat.
; It refuses low resolution.  The main menu has PACK/DEPACK PROGRAM, PACK/DEPACK DATA, MULTI FILE PACKER, PACK
; DATA (OFFSET), PREFERENCES, CHUNK PACKER and EXIT PROGRAM.  A file that is packed already is depacked
; instead.
;
; It is Automation Packer 2.41's packer and stubs in the GEM front end that Automation Packer 5.01 later
; kept.  pack_source is 2.41's LZ77 packer writing 'LSD!' data (or 'AUTO-LSD' in Amiga format), and shows its
; percentage in the progress box.  The compaction rate box (1 big and fast to 10 slow and small) sets its window,
; $10 to $1120 bytes; BUFFER PACK marks the data 'LSD$'.  A program gets program_stub in front, which depacks,
; relocates and runs it; data can get data_stub and the depacker in front (CONVERT DATA TO PROGRAM).  CHUNK
; PACKER packs a file in 4 K to 64 K chunks behind an 'LSDC' header.  There is no verify.
;
; PREFERENCES has PRINT HEADER, FORMAT (AMIGA or ST) and PACK STATUS (percent or colours).  5.01 kept this
; box's code, with FORMAT relabelled VERIFY.
;
; The front end keeps its variables in the text section; the data section is empty.  Some code is patched while
; it runs: tree_index, objc_change_redraw, and in the stubs stub_clear_screen, stub_print_trap and
; data_stub_user_call.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$1b03  the GEM front end, with the packer
;   $1b04-$1e9d  its texts and variables, and its stack
;   $1e9e-$21d3  program_stub ("AUTOMATION PACKER V2.3r"), with lsd_depack
;   $21d6-$2287  data_stub ("AUTOMATION PACKER V2.2f")
;   $2288-$25a1  the AES calls
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; Packed data: 'LSD!' ('LSD$' for a buffer pack, 'AUTO-LSD' in Amiga format), the unpacked length, the packed
; length (counted from the unpacked length), then a bit stream that lsd_depack reads from the end down; the last
; word's top bit says a pad byte comes before it.
;
; Chunked file: 'LSDC', the file length, the chunk size, the header's length less 4, then a long for each chunk
; giving where it ends, then the chunks.  A chunk that did not pack under 95% of its size is stored as it is.
;
; Packed program: program_stub, $336 bytes (a PRG header with the stub as text and the packed data as data),
; then the packed data.
;
; Data program: data_stub ($b0 bytes), lsd_depack ($150 bytes), then the packed data.
;
;=======================================================================


	section	text
start:
	bra.w	main
dest_buffer:	; from: main, reset_buffers
	dc.l	$00080000                       ; where packed files are built: the free memory + $8000, set at start-up
load_buffer:	; from: main, reset_buffers
	dc.l	$00088000                       ; where files are loaded: dest_buffer + $8000
text_indexes:	; from: main
	dc.w	$0000,$0015,$001c,$0023,$002a,$0031,$0038,$003f ; rsrc_gaddr R_STRING indexes of the 13 texts written to
	dc.w	$0046,$004d,$005b,$0062,$0069
version_digits:	; from: main
	dc.b	$02,$fe,$05,$01                 ; the version, each character less '0': "2.51"
	dc.b	$23,$75,$84,$23                 ; not used
no_buffer_pack:	; from: pack_loaded, pack_whole_file, multi_file_packer, choose_rate
	dc.w	$0000                           ; nonzero: BUFFER PACK and NORMAL PACK are shown disabled in the
                                                ;   compaction rate box (programs)
rsc_name:	; from: main
	dc.b	'PACK2_51.RSC',0
	dc.b	$00
title_position:	; from: main
	dc.b	27,'Y 7',0                      ; VT52 cursor to row 0, column 23, for the title line printed on the
                                                ;   screen
	dc.b	$00

;------------------------------------------------------------------------------
; Start-up: shrink the memory to the program, hook the critical error handler, refuse low resolution, load
; PACK2_51.RSC, find its trees and texts, put the version in the title and print it at the top of the screen,
; and place the buffers in the free memory.
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
	move.l	#rsc_name,aes_addrin            ; "PACK2_51.RSC"
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
	lea	version_digits,a2               ; a2 = the version digits
	movea.l	text_title,a0                   ; a0 = the main box's title line
	movea.l	text_title2,a1                  ; a1 = the line under it
	adda.l	#$1d,a0                         ; the XXXX of "AUTOMATION COMPACTER VERSION XXXX"
	adda.l	#$1d,a1                         ; the same in the second line
	moveq	#3,d1                           ; 4 characters
copy_version:
	move.b	(a2)+,d0                        ; a digit
	addi.w	#$30,d0                         ; to a character
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
	addi.l	#$8000,d0                       ; + $8000
	move.l	d0,dest_buffer                  ; = where packed files are built
	addi.l	#$8000,d0                       ; + $8000
	move.l	d0,load_buffer                  ; = where files are loaded
	clr.w	aes_intin                       ; ARROW
	jsr	graf_mouse(pc)

;------------------------------------------------------------------------------
; The main menu.  Each pass clears the chunk, buffer and data flags, puts XXX back in "CHUNK XXX OF XXX",
; restores the data stub's call that leaves supervisor mode, resets the buffers and runs the dialog.
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
	move.w	#$612e,data_stub_user_call      ; the data stub's bsr.s super_swap again ($612e)
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
	move.l	#critic_handler,$404.w          ; etv_critic
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
super_toggle:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer, show_percent
	move.l	a0,-(sp)                        ; the stack to use
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.w	#6,sp
	rts
old_ssp:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer, show_percent
	dc.w	$0000,$0000                     ; the stack Super returned

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
	bsr.w	lsd_depack                      ; depack
	move.w	(sp)+,$ffff8240                 ; palette 0, colour back
	move.l	d5,source_length
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
	bsr.w	lsd_depack                      ; depack
	move.w	(sp)+,$ffff8240                 ; palette 0, colour back
	move.l	d5,source_length
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
	bsr.w	pack_source                     ; pack
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
; Pack the loaded file chunk by chunk.  The output starts with an 'LSDC' header: 'LSDC', the file length, the
; chunk size and the header's length less 4, then a table holding the end of each chunk, then the chunks.  The
; build pointer moves on 4 bytes past each chunk but the last.  A chunk that does not pack below the limit is
; stored as it is.
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
	move.l	#$4c534443,(a0)+                ; 'LSDC'
	move.l	source_length,(a0)+             ; the file length
	move.l	source_length,chunk_file_length ; kept for the end
	move.l	chunk_size,(a0)+                ; the chunk size
	subi.l	#$4,d1                          ; the header length less 4
	move.l	d1,(a0)+
	move.l	a0,chunk_table_ptr              ; where the table starts
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
	addi.l	#$4,d0                          ; + 4
	move.l	d0,build_ptr
	bra.w	next_chunk
chunk_kept_packed:
	move.l	packed_length,d0                ; the packed length
	movea.l	chunk_table_ptr,a0              ; the table
	add.l	-$4(a0),d0                      ; + where the last chunk ended
	move.l	d0,(a0)+                        ; = where this one ends
	move.l	a0,chunk_table_ptr
	move.l	packed_length,d0                ; the packed length
	add.l	build_ptr,d0                    ; + the build pointer
	addi.l	#$4,d0                          ; + 4
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
; Pack the loaded file in one piece: ask for the compaction rate, pack, add the program stub (programs) or ask
; about the data stub (data), show the result and save.
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
	bsr.w	pack_source                     ; pack
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
; Save: choose a name and write the file.  A packed file is written from the build buffer (with an 'LSD$' magic
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
	move.b	#$24,3(a0)                      ; 'LSD!' becomes 'LSD$'
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
	bsr.w	pack_source                     ; pack
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
	cmpi.l	#$4c534443,(a0)                 ; chunked ('LSDC')?
	beq.w	multi_chunk_write               ; yes: leave it
	move.b	#$24,3(a0)                      ; no: 'LSD!' becomes 'LSD$'
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
	move.b	#$24,3(a0)                      ; 'LSD!' becomes 'LSD$'
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
; patches the program stub so that it does not clear the screen or print its title; FORMAT chooses Amiga
; ('AUTO-LSD', an 8 byte gap) or ST ('LSD!', a 4 byte gap); PACK STATUS chooses between a percentage and
; colours while packing.
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
	cmp.b	#$3,d0                          ; FORMAT?
	beq.w	toggle_format                   ; yes
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
toggle_format:
	cmpi.b	#$ff,amiga_format               ; Amiga?
	beq.s	format_st                       ; yes: ST
	move.b	#$ff,amiga_format               ; Amiga
	move.l	#$8,offset_gap                  ; an 8 byte gap
	move.w	#$8,aes_intin                   ; AMIGA
	clr.w	aes_intin+12                    ; normal
	jsr	objc_change(pc)
	move.w	#$9,aes_intin                   ; ST
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	bra.s	format_toggled
format_st:
	clr.b	amiga_format                    ; ST
	move.l	#$4,offset_gap                  ; a 4 byte gap
	move.w	#$8,aes_intin                   ; AMIGA
	move.w	#$8,aes_intin+12                ; disabled
	jsr	objc_change(pc)
	move.w	#$9,aes_intin                   ; ST
	clr.w	aes_intin+12                    ; normal
	jsr	objc_change(pc)
format_toggled:
	bra.w	preferences_loop                ; the box again
amiga_format:	; from: pack_source
	dc.w	$0000                           ; $ff: the packed data starts 'AUTO-LSD' instead of 'LSD!'
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
status_colours:	; from: pack_source
	dc.w	$0000                           ; nonzero: pack_source flashes the colours instead of showing the
                                                ;   percentage

;------------------------------------------------------------------------------
; Left-over code that nothing calls: print a string and wait for a key.
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
	trap	#2                              ; AES
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
; has 'LSD!' after its $336 byte stub, packed data starts with it.  A packed file is copied to the build
; buffer (past the stub for a program) and packed_flag set.  d7 = 0 (after an alert) for the wrong type.
;------------------------------------------------------------------------------
check_loaded_file:	; from: pack_one_file, menu_chunk_packer
	cmpi.b	#$1,file_type                   ; a program?
	bne.s	check_data_file                 ; no
	cmpi.w	#$601a,(a6)                     ; a program file?
	bne.s	wrong_pack_type                 ; no: wrong type
	cmpi.l	#$4c534421,$336(a6)             ; 'LSD!' after the stub?
	beq.s	file_is_packed                  ; yes: packed
	bra.s	check_loaded_done               ; no: pack it
check_data_file:
	cmpi.l	#$4c534421,(a6)                 ; 'LSD!'?
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
	addi.l	#$336,build_ptr                 ; yes: the packed data starts after the stub
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
	adda.l	#$336,a0                        ; yes: past the stub
	cmpi.l	#$4c534421,(a0)                 ; 'LSD!'?
	beq.s	file_type_packed                ; yes: packed
	move.b	#$1,file_type                   ; no: a program
	move.w	#$ffff,d7                       ; use it
	bra.s	find_file_type_done
file_type_data:
	cmpi.l	#$4c534421,(a0)                 ; 'LSD!'?
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
	move.l	#alert_offset_text,aes_addrin
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
; The packer: source_ptr/source_length to build_ptr as 'LSD!' (or 'AUTO-LSD' in Amiga format), the unpacked
; length, the packed length, then a bit stream lsd_depack reads from the end down.  It looks up to
; search_window bytes ahead for the longest string equal to the one here (up to $3ff), and writes literal
; counts, offsets and lengths as variable-length codes.  The mouse is off while it runs; it shows the
; percentage done in the progress box, or flashes the background colour.
;------------------------------------------------------------------------------
pack_source:	; from: pack_in_chunks_multi, pack_chunks, pack_whole_file, multi_file_packer
	move.w	$ffff8240.w,-(sp)               ; palette 0, keep the background colour
pack_mouse_off:
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the keyboard ACIA
	btst	#$1,d0                          ; ready to send?
	beq.s	pack_mouse_off                  ; no: wait
	move.w	#$12,$fffffc02.w                ; keyboard ACIA data, IKBD: disable mouse
	dc.w	$a00a                           ; Line-A $a, hide the mouse
	move.w	#$3030,percent_digits           ; "00" percent
	move.l	source_length,d0                ; the length
	movea.l	source_ptr,a0                   ; the source
	lea	0(a0,d0.l),a2                   ; a2 = its end
	movea.l	build_ptr,a1                    ; the build buffer
	addq.l	#8,a1                           ; past its 8 byte header
	clr.w	d5                              ; no literals yet
	moveq	#7,d6                           ; 8 bits to the byte
pack_loop:
	cmpi.b	#$0,status_colours              ; colours?
	beq.s	pack_percent                    ; no
	move.b	(a0),$ffff8240.w                ; palette 0, yes: flash the background
	bra.s	pack_search
pack_percent:
	bsr.w	show_percent                    ; show the percentage
pack_search:
	move.b	(a0),d0                         ; the byte to match
	move.w	#$1,best_length                 ; best match 1
	moveq	#1,d1                           ; its offset
	move.l	search_window,d2                ; the window
	move.l	a0,string_start                 ; the start of this string
	lea	1(a0),a3
	addq.w	#1,a3
	adda.w	d2,a3                           ; + the window
	cmpa.l	a2,a3                           ; past the end?
	blt.s	search_window_loop              ; no
	suba.w	d2,a3                           ; yes: back
	subq.w	#1,a3
	lea	search_near_end_next(pc),a5     ; return into the end-checking loop
search_near_end:
	cmp.b	(a3)+,d0                        ; the first byte?
	beq.s	match_found                     ; found
search_near_end_next:
	cmpa.l	a2,a3                           ; at the end?
	dbeq	d2,search_near_end              ; on through the window
	bra.s	match_done                      ; none
search_window_loop:
	suba.w	d2,a3                           ; back
	subq.w	#1,a3
	lea	search_fast_next(pc),a5         ; return into the fast loop
search_fast:
	cmp.b	(a3)+,d0                        ; the first byte?
search_fast_next:
	dbeq	d2,search_fast                  ; on through the window
	beq.s	match_found                     ; found
	bra.s	match_done                      ; none
string_start:
	dc.l	$00000000                       ; the start of this string
match_found:
	movem.l	d0/a0-a3,-(sp)
	subq.w	#1,a3                           ; the match
	movea.l	a3,a1
	move.l	a1,d1
	sub.l	string_start(pc),d1             ; its offset
	clr.w	d0                              ; its length
match_length:
	cmpm.b	(a0)+,(a1)+                     ; the same?
	bne.s	match_end                       ; no
	cmpa.l	a2,a1                           ; past the end?
	bhi.s	match_end                       ; yes
	cmpa.l	a3,a0                           ; into the string?
	bhi.s	match_end                       ; yes
	addq.w	#1,d0                           ; one longer
	cmp.w	#$3ff,d0                        ; at most $3ff
	bne.s	match_length
match_end:
	cmp.w	best_length(pc),d0              ; longer than the best?
	ble.s	match_next                      ; no
	move.w	d0,best_length                  ; yes: the best
	move.w	d1,best_offset                  ; and its offset
match_next:
	movem.l	(sp)+,d0/a0-a3
	tst.w	return_flags                    ; not equal
	jmp	(a5)                            ; back into the search
return_flags:
	dc.w	$ffff                           ; tested for a nonzero result
match_done:
	move.w	best_offset(pc),d0              ; the best offset
	move.w	best_length(pc),d1              ; the best length
	sub.w	d1,d0
	cmp.w	#$1,d1                          ; 1: a literal
	beq.s	literal
	cmp.w	#$2,d1                          ; 2?
	beq.s	match_2
	bsr.w	put_literal_count               ; the literals before it
	bsr.w	put_offset                      ; the offset
	bra.s	match_written
match_2:
	cmp.w	#$23f,d0                        ; offset too large?
	bhi.s	literal                         ; yes: a literal
	bsr.w	put_literal_count               ; the literals before it
	bsr.w	put_short_offset                ; the short offset
match_written:
	bsr.w	put_length                      ; the length
	moveq	#0,d5                           ; no literals
	move.w	best_length(pc),d0              ; skip the matched bytes
	lea	0(a0,d0.w),a0
	bra.w	pack_next
literal:	; from: put_short_offset
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
	move.w	d1,(a1)+
	movea.l	build_ptr,a0                    ; the header
	move.l	source_length,(a0)              ; the unpacked length
	clr.l	(a1)
	clr.l	4(a1)
	suba.l	a0,a1                           ; the packed length
	move.l	a1,4(a0)
	move.l	a1,packed_length
	move.l	offset_gap,d0                   ; the gap
	sub.l	d0,build_ptr                    ; below the build buffer
	cmpi.b	#$ff,amiga_format               ; Amiga format?
	beq.s	magic_amiga                     ; yes
	move.l	#$4c534421,-$4(a0)              ; no: 'LSD!'
	addq.l	#4,packed_length
	bra.s	pack_mouse_on
magic_amiga:
	move.l	#$4155544f,-$8(a0)              ; 'AUTO'
	move.l	#$2d4c5344,-$4(a0)              ; '-LSD'
	addq.l	#8,packed_length
pack_mouse_on:
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the keyboard ACIA
	btst	#$1,d0                          ; ready to send?
	beq.s	pack_mouse_on                   ; no: wait
	move.w	#$8,$fffffc02.w                 ; keyboard ACIA data, IKBD: relative mouse
	dc.w	$a009                           ; Line-A $9, show the mouse
	move.w	(sp)+,$ffff8240.w               ; palette 0, the background colour back
put_bits_done:	; from: put_length
	rts

;------------------------------------------------------------------------------
; The code writers: each sets d1 = the bits and d4 = their count - 1 and goes to put_bits.
;------------------------------------------------------------------------------
put_literal_count:	; from: pack_source
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
	dc.w	$0001,$0205,$080f,$0100,$0101,$0203,$0205,$0308
	dc.w	$0a12

put_offset:	; from: pack_source
	lea	offset_table(pc),a3             ; the offset table
	moveq	#2,d3
offset_range:
	add.w	d3,d3
	move.w	0(a3,d3.w),d4
	lsr.w	#1,d3
	cmp.w	d4,d0                           ; in this range?
	dbge	d3,offset_range                 ; no: the one below
	sub.w	d4,d0                           ; less its start
	add.w	d3,d3
	move.w	6(a3,d3.w),d3                   ; bits and prefix
	move.w	d3,d4
	lsr.w	#8,d3                           ; the prefix length
	moveq	#-1,d1
	lsl.w	d3,d1
	or.w	d0,d1                           ; the offset
	andi.w	#$f,d4                          ; the bit count
	bra.w	put_bits                        ; write them
offset_table:
	dc.w	$0000,$0020,$0120,$0606,$0908,$0c0d

put_short_offset:	; from: pack_source
	cmp.w	#$23f,d0                        ; too large?
	bhi.w	literal                         ; yes: a literal
	move.w	d0,d1
	cmp.w	#$3f,d1                         ; 6 bits?
	ble.s	short_offset_6                  ; yes
	subi.w	#$40,d1                         ; no: 9 bits
	moveq	#9,d4
	bset	d4,d1                           ; and a 1
	bra.w	put_bits                        ; write them
short_offset_6:
	move.w	#$6,d4                          ; 6 bits + the 0
	bra.w	put_bits                        ; write them
length_table:	; from: put_length
	dc.w	$0203,$0406,$0a01,$0102,$030a

put_length:	; from: pack_source
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
	bra.w	put_bits_done
best_length:	; from: pack_source
	dc.w	$0000,$0000
best_offset:	; from: pack_source
	dc.w	$0000,$0000

;------------------------------------------------------------------------------
; The percentage display: work out how much is done and, when it changes, put it in the progress box and draw
; it.  The packer runs in supervisor mode, so this goes back to user mode for the AES and returns after.
;------------------------------------------------------------------------------
show_percent:	; from: pack_source
	movem.l	d0-d7/a0-a6,saved_registers     ; keep the registers
	move.l	source_ptr,d0                   ; the source
	suba.l	d0,a0                           ; done
	suba.l	d0,a2                           ; the end
	move.l	a0,d0
	move.l	a2,d1
	bsr.w	percent                         ; the percentage
	cmp.b	last_percent,d6                 ; changed?
	beq.w	show_percent_done               ; no
	move.b	d6,last_percent                 ; yes: keep it
	movea.l	text_progress_percent,a0        ; "PERCENTAGE ALREADY PACKED %XX"
	adda.l	#$1b,a0                         ; the XX
	move.b	percent_digits,(a0)+            ; tens
	move.b	percent_digits+1,(a0)+          ; units
	movea.l	sp,a5                           ; keep the stack
	move.l	usp,a6                          ; and the user stack
	suba.l	#$2,a6                          ; 2 bytes lower
	move.l	a6,usp
	move.l	old_ssp,-(sp)                   ; Super(the old stack): user mode
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	move.w	#$4,aes_intin                   ; the percentage line
	clr.w	aes_intin+2                     ; depth 0
	jsr	objc_draw(pc)
	lea	$0,a0                           ; supervisor mode again
	bsr.w	super_toggle                    ; Super
	adda.l	#$2,a6                          ; the user stack back
	move.l	a6,usp
	movea.l	a5,sp                           ; and the stack
show_percent_done:
	movem.l	saved_registers,d0-d7/a0-a6     ; the registers back
	rts
last_percent:
	dc.w	$0000                           ; the percentage last shown

;------------------------------------------------------------------------------
; Put the $336 byte program stub (program_stub, a PRG header and its depacker) in front of the packed data,
; with the packed length in the header's data length.
;------------------------------------------------------------------------------
add_program_stub:	; from: pack_loaded, pack_whole_file, multi_file_packer
	move.l	#$336,d0                        ; the stub's length
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
	move.l	-(a0),d0                        ; 12 spaces
	move.l	-(a0),d0
	move.l	-(a0),d0
	move.l	-(a0),d0
	move.l	-(a0),d0
	move.l	-(a0),d0

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
percent:	; from: show_percent, show_packed_length
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
	move.w	0(a0,d0.w),search_window+2
	rts

;------------------------------------------------------------------------------
; After packing data: PROGRAM FILE?  YES asks for the depack and execute addresses and whether to stay in
; supervisor mode, then puts the data stub (data_stub, $b0 bytes) and the depacker ($150 bytes) in front of the
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
	move.l	#$150,d0
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
; d2 = the hex number of hex_digit_count digits at a0; d0 = $ffff at a character that is not a hex digit.
;------------------------------------------------------------------------------
hex_to_number:	; from: ask_offset, data_to_program
	moveq	#0,d2
	moveq	#0,d7
	move.b	hex_digit_count,d7              ; the digit count
	subq.b	#1,d7
	movea.l	#place_values,a1
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
	dc.w	$0010,$0020,$0040,$0080,$0100,$0200,$0400,$0800 ; the search window for compaction rates 1 to 10, then a
                                                ;   0
	dc.w	$1000,$1120,$0000
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
percent_digits:	; from: pack_source, show_percent, show_packed_length, percent
	dc.b	$30,$30                         ; "XX" or "00".."99": the percentage made by percent
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
offset_gap:	; from: preferences, ask_offset, pack_source
	dc.l	$00000004                       ; bytes between the unpacked data and the packed data: 4 for ST, 8 for
                                                ;   Amiga
source_ptr:                                     ; from: pack_one_file, depack_loaded, menu_chunk_packer, pack_chunks,
                                                ;   save_file, multi_file_packer, 6 more
	dc.l	$00028000                       ; the data to pack
source_length:                                  ; from: depack_loaded, menu_chunk_packer, pack_loaded, pack_in_chunks,
                                                ;   pack_in_chunks_multi, pack_chunks, 6 more
	dc.l	$00000000                       ; its length
build_ptr:                                      ; from: depack_loaded, menu_chunk_packer, pack_chunks, save_file,
                                                ;   multi_file_packer, reset_buffers, 6 more
	dc.l	$00020000                       ; where the packed file is built
packed_length:                                  ; from: pack_one_file, menu_chunk_packer, pack_chunks, save_file,
                                                ;   multi_file_packer, reset_buffers, 5 more
	dc.l	$00000000                       ; the packed length
search_window:	; from: pack_source
	dc.w	$0000                           ; how far ahead pack_source looks for strings: a long whose low word
                                                ;   choose_rate sets
	dc.w	$0800
stack_area:
	dcb.b	256,0                           ; the program's stack, up to program_stub

;------------------------------------------------------------------------------
; The program stub ("AUTOMATION PACKER V2.3r"): a PRG header and the code that runs a packed program.
; add_program_stub puts these $336 bytes in front of the packed data; the packed data then follows at
; program_stub_end.  The stub depacks the program $400 bytes above its own text, relocates it, sets the
; basepage from its header, and runs a mover from the screen that copies it down over the stub and clears
; behind it.  With PRINT HEADER off it neither clears the screen nor prints its title.
; The program stub: a PRG header and the code that runs a packed program.  add_program_stub puts these $336
; bytes in front of the packed data; the packed data then follows at program_stub_end.  The stub depacks the
; program $400 bytes above its own text, relocates it, sets the basepage from its header, and runs a mover
; from the screen that copies it down over the stub and clears behind it.  The multi file packer makes it
; silent: it then neither clears the screen nor prints its title.
;------------------------------------------------------------------------------
program_stub:	; from: main, add_program_stub
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
stub_clear_screen:	; from: preferences
	clr.l	(a2)+                           ; clear them (a nop when PRINT HEADER is off), clear them (a nop for the
                                                ;   multi file packer)
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
	trap	#1                              ; Cconws, a nop when PRINT HEADER is off, a nop for the multi file
                                                ;   packer
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
	dc.b	27,'Y %    AUTOMATION PACKER V2.5r',0 ; VT52 cursor to row 0, column 5 (25 when not low resolution),
                                                ;   then the title

;------------------------------------------------------------------------------
; The depacker for 'LSD!' data, part of both stubs: a0 = the packed data, a1 = where to depack it; d5 = the
; unpacked length.  It works from the end of the packed data down, flashing the background colour as it
; copies literals.
;------------------------------------------------------------------------------
lsd_depack:	; from: depack_loaded, menu_chunk_packer, data_to_program, program_stub
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
	cmp.w	#$2,d1                          ; length 2?
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
data_stub_user_call:	; from: main_menu, data_to_program
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
stub_depacker:	; from: data_stub
	dc.w	$0000                           ; where the depacker follows the data stub when data_to_program builds a
                                                ;   file

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
objc_draw:	; from: pack_chunks, show_percent
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

	section	bss
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
buffer_pack:	ds.b	2                       ; 1: buffer pack (magic 'LSD$')
chunk_count:	ds.b	2                       ; the number of chunks (+ 4 once the header is made)
chunks_left:	ds.b	2                       ; whole chunks still to pack
multi_chunk_size:	ds.b	4               ; the multi chunk packer's chunk size
last_chunk_length:	ds.b	2               ; the last chunk's length (a word, read as a long by pack_chunks)
chunk_header:	ds.b	4                       ; the 'LSDC' header
chunk_table_ptr:	ds.b	4               ; the next entry of its table
chunk_total:	ds.b	4                       ; the length of the chunked file
aes_control:	ds.b	24                      ; the AES arrays: control
aes_global:	ds.b	30
aes_intin:	ds.b	40
aes_intout:	ds.b	40
aes_addrin:	ds.b	40
aes_addrout:	ds.b	40
saved_registers:	ds.b	60              ; the registers while the percentage is drawn
bss_end:

	end
