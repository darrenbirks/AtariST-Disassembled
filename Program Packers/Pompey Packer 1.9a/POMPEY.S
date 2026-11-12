; POMPEY.PRG  -  The Pompey Pirates Packer v1.9a
; Devpac source of the program, disassembled by Darren Birks, 11 November 2026.
; Text 14400 bytes, data 372 bytes, bss 100 bytes.
;
; This source rebuilds POMPEY.PRG byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o POMPEY.PRG POMPEY.S
; It needs POMPEY.RSC beside it to run.  PACKER19.DOC in the POMPEY_1.9 folder is the author's manual.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; "The Pompey Pirates Packer (c) v1.9a", "V1.9a created 17/10/90", by J.P.M.  A GEM program in assembly that
; calls the AES itself (aes, with its own table of control counts), grown from v1.5 (whose source is in the
; Pompey Packer 1.5 folder).  What is new:
;   - Two batch modes: B1 packs files chosen one after another; B2 packs the files of a folder with the
;     extension of one file chosen.
;   - Compression from 4k to 32k (the 24k button gives a 20 K window).
;   - Def chooses the stub put in front of a packed program: Normal, Printed ("POMPEY PACKER V1.9" shown
;     first) or Utility (to offer saving the program unpacked).
;   - Each packed file is verified (verify runs the depacker without writing, looking for a collision of the
;     output with the packed data); bad files are counted and listed, and saved or not as the status box
;     says.  STATS shows the counts and the names, nine to a page.
;   - When packing is done the drive lights flash (a VBL routine) until the status box is closed.
; The 'POPI' format and the codes are those of v1.5.
;
; Some things in it look unfinished:
;   - process_batch's branch for DISC goes to disc_flag, a variable, not to process_disc: with DISC chosen
;     the program runs into its data.
;   - The utility stub turns the key to a capital and then compares it with 'y', so it never offers to save
;     (the manual has Utility as "NOT INSTALLED").
;   - The relocation table written after a packed program is the first long only; the 0 byte that should
;     end it is not written.
;   - process_mode is set for every process but only read for B2.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$0745  the start-up, the main dialog, the processes, STATS and Def
;   $0746-$0cf9  the object helpers, the about and status boxes, FILES and SAVE
;   $0cfa-$0e01  depack
;   $0e02-$1407  the screen, the alerts, numbers, and the program's stack
;   $1408-$2189  PACK: one file, B1, B2 and DISC, load, write, the alerts, numbers and the time
;   $218a-$2449  the clock's VBL routine, the variables and the alerts
;   $244a-$26fb  the packer and its bit writers
;   $26fc-$2805  verify
;   $2806-$290f  the VBL helpers, the abort and drive lights routines
;   $2910-$2ad3  the normal stub
;   $2ad4-$2ccf  the printed stub
;   $2cd0-$30d7  the utility stub, its texts and name buffer
;   $30d8-$3359  FORMAT, and the variables
;   $335a-$3809  the bad files' names
;   $380a-$383f  aes
;   $3840-$39b3  the AES parameter block and the control counts (the data)
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The start-up: the program's own stack, Mshrink, the screen (Logbase), the AES, the resource and its three
; trees, the work memory (all that is free), the drive, the dialogs' text fields, and two VBL routines (the
; Alt-Help abort and the clock).  Then the main dialog until EXIT.
;------------------------------------------------------------------------------
start:
	movea.l	4(sp),a3                        ; the basepage
	lea	stack_top(pc),sp                ; a stack of our own
	move.l	$c(a3),d0                       ; text length
	add.l	$14(a3),d0                      ; + data length
	add.l	$1c(a3),d0                      ; + BSS length
	addi.l	#$100,d0                        ; + the basepage
	move.l	d0,-(sp)                        ; to keep
	move.l	a3,-(sp)                        ; from the basepage
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
	move.w	#$3,-(sp)
	trap	#14                             ; Logbase
	addq.l	#2,sp
	move.l	d0,clear_screen_address+2       ; the screen, for clear_screen
	bsr.w	hide_mouse                      ; the mouse hidden
	move.w	#$2,process_mode
	moveq	#10,d0                          ; appl_init
	bsr.w	aes
	move.w	d0,app_id                       ; the application id
	moveq	#77,d0                          ; graf_handle
	bsr.w	aes
	move.w	d0,vdi_handle                   ; the VDI handle
	bsr.w	clear_screen                    ; the screen cleared
	move.w	#$0,aes_int_in                  ; ARROW
	moveq	#78,d0                          ; graf_mouse
	bsr.w	aes
	bsr.w	show_mouse                      ; the mouse shown
	move.l	#text_rsc,aes_addr_in           ; "pompey.rsc"
	moveq	#110,d0                         ; rsrc_load
	bsr.w	aes
	tst.w	d0                              ; loaded?
	beq.w	no_resource                     ; no: "Resource file missing!" and quit
	moveq	#0,d0                           ; tree 0
	bsr.w	tree_address                    ; rsrc_gaddr
	move.l	a0,tree_main                    ; the main dialog
	moveq	#1,d0                           ; tree 1
	bsr.w	tree_address
	move.l	a0,tree_about                   ; the about box
	moveq	#2,d0                           ; tree 2
	bsr.w	tree_address                    ; rsrc_gaddr
	move.l	a0,tree_status                  ; the status box
	move.l	tree_main,aes_addr_in           ; the main dialog
	moveq	#54,d0                          ; form_center
	bsr.w	aes
	moveq	#0,d0                           ; FMD_START
	bsr.w	form_dial
	move.l	#$1000,-(sp)                    ; 4 K
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	bmi.w	no_memory                       ; none: "Not enough memory"
	move.l	d0,d4
	addi.l	#$c8,d0                         ; + 200
	move.l	d0,work_start                   ; is where the work memory starts
	move.l	#$ffffffff,-(sp)                ; all that is left
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	bmi.w	no_memory
	add.l	d0,d4                           ; + its start
	move.l	d4,work_end                     ; the work memory's end
	bsr.w	get_dta                         ; the DTA
	move.w	#$19,-(sp)
	trap	#1                              ; Dgetdrv
	addq.l	#2,sp
	move.w	d0,d7                           ; the drive
	moveq	#21,d0                          ; its button: A (21), B, F or D
	add.w	d7,d0
	bsr.w	select
	bsr.w	select_drive_path
	moveq	#37,d0                          ; the source position field (37)
	bsr.w	object_text
	move.l	a0,field_output_position
	moveq	#38,d0                          ; the output position field
	bsr.w	object_text
	move.l	a0,field_source_position
	moveq	#39,d0                          ; the packed length
	bsr.w	object_text
	addq.l	#1,a0
	move.l	a0,field_name                   ; the name field, past its first character
	moveq	#40,d0
	bsr.w	object_text
	addq.l	#1,a0
	move.l	a0,field_output_name            ; the output name field, past its first character
	moveq	#41,d0
	bsr.w	object_text
	move.l	a0,field_length                 ; the length field
	moveq	#42,d0
	bsr.w	object_text
	move.l	a0,field_packed                 ; the packed length field
	moveq	#43,d0
	bsr.w	object_text
	move.l	a0,field_percent                ; the percentage field
	moveq	#44,d0
	bsr.w	object_text
	move.l	a0,field_time                   ; the time field
	moveq	#25,d0                          ; the free bytes field (25)
	bsr.w	object_text
	move.l	a0,field_free
	moveq	#8,d0                           ; the offset field (8)
	bsr.w	object_text
	move.l	a0,field_offset
	movea.l	tree_status(pc),a0              ; the status box
	moveq	#19,d0                          ; its "Packed:" string
	bsr.w	object_spec
	addq.l	#4,a0                           ; past "Packed:"
	move.l	a0,stats_packed_field           ; kept
	movea.l	tree_status(pc),a0              ; the status box
	moveq	#18,d0                          ; its "Bad:" string
	bsr.w	object_spec
	addq.l	#7,a0                           ; past "Bad:"
	move.l	a0,stats_bad_field              ; kept
	lea	stats_names(pc),a3              ; the status box's nine name strings
	movea.l	tree_status(pc),a0
	moveq	#9,d0                           ; object 9
	bsr.w	object_spec
	move.l	a0,(a3)+                        ; kept
	movea.l	tree_status(pc),a0
	moveq	#10,d0
	bsr.w	object_spec
	move.l	a0,(a3)+
	movea.l	tree_status(pc),a0
	moveq	#11,d0
	bsr.w	object_spec
	move.l	a0,(a3)+
	movea.l	tree_status(pc),a0
	moveq	#12,d0
	bsr.w	object_spec
	move.l	a0,(a3)+
	movea.l	tree_status(pc),a0
	moveq	#13,d0
	bsr.w	object_spec
	move.l	a0,(a3)+
	movea.l	tree_status(pc),a0
	moveq	#14,d0
	bsr.w	object_spec
	move.l	a0,(a3)+
	movea.l	tree_status(pc),a0
	moveq	#15,d0
	bsr.w	object_spec
	move.l	a0,(a3)+
	movea.l	tree_status(pc),a0
	moveq	#7,d0
	bsr.w	object_spec
	move.l	a0,(a3)+
	movea.l	tree_status(pc),a0
	moveq	#8,d0
	bsr.w	object_spec
	move.l	a0,(a3)+
	move.b	#$ff,save_bad                   ; No Save
	move.l	#$4ee,dumpflg_address           ; _dumpflg: Alt-Help
	lea	vbl_abort(pc),a3                ; the abort routine
	bsr.w	install_vbl                     ; into the VBL queue
	move.l	a3,vbl_slot_abort               ; its slot
	lea	vbl_clock(pc),a3                ; the clock
	bsr.w	install_vbl                     ; into the VBL queue
	move.l	a3,vbl_slot_clock               ; its slot
	bsr.w	get_dta                         ; the DTA
	movea.l	tree_about(pc),a0               ; the about box
	moveq	#6,d0                           ; object 6, its icon
	bsr.w	object_text_in
	move.l	a0,about_icon                   ; kept (not used)
	bsr.w	grow                            ; a growing box
main_redraw:	; from: menu_stats, object_state, load_file
	move.l	tree_main,aes_addr_in           ; the main dialog
	move.w	#$0,aes_int_in                  ; from the root
	move.w	#$29,aes_int_in+2               ; depth 41
	move.w	main_x,aes_int_in+4             ; its box
	move.w	main_y,aes_int_in+6
	move.w	main_w,aes_int_in+8
	move.w	main_h,aes_int_in+10
	moveq	#42,d0                          ; objc_draw
	bsr.w	aes
main_loop:	; from: clear_stats_names, object_state, form_dial, grow, pack_b2, utility_stub_bits
	move.l	tree_main,aes_addr_in           ; the main dialog
	move.w	#$0,aes_int_in                  ; no edit field
	moveq	#50,d0                          ; form_do
	bsr.w	aes
	move.w	d0,button                       ; the button
	bsr.w	select_drive_path               ; the path for the drive chosen
	move.w	button(pc),d0
	bsr.w	deselect
	move.w	button(pc),d0
	bsr.w	draw_object
	move.w	button(pc),d0
	cmpi.w	#$1,d0                          ; EXIT?
	beq.w	quit
	cmpi.w	#$a,d0                          ; the title: about?
	beq.w	menu_about_cls
	cmpi.w	#$2,d0                          ; PACK?
	beq.s	menu_pack
	cmpi.w	#$b,d0                          ; DEPACK?
	beq.w	menu_depack
	cmpi.w	#$1a,d0                         ; '?': the free space?
	beq.w	menu_free
	cmpi.w	#$2d,d0                         ; SAVE?
	beq.w	menu_save
	cmpi.w	#$30,d0                         ; FILES?
	beq.w	menu_files
	cmpi.w	#$31,d0                         ; FORMAT?
	beq.w	menu_format
	cmpi.w	#$32,d0                         ; STATS?
	beq.w	menu_stats
	cmpi.w	#$33,d0                         ; Def: the depack header?
	beq.w	menu_header
	bra.w	main_loop                       ; anything else
menu_pack:
	moveq	#18,d0                          ; 4k (object 18)?
	bsr.w	is_selected
	beq.s	pack_8k                         ; no
	move.l	#$fff,pack_window+2             ; a 4 K window
	bra.s	pack_output
pack_8k:
	moveq	#13,d0                          ; 8k?
	bsr.w	is_selected
	beq.s	pack_12k                        ; no
	move.l	#$1fff,pack_window+2            ; an 8 K window
	bra.s	pack_output
pack_12k:
	moveq	#16,d0                          ; 12k?
	bsr.w	is_selected
	beq.s	pack_16k                        ; no
	move.l	#$2fff,pack_window+2            ; a 12 K window
	bra.s	pack_output
pack_16k:
	moveq	#14,d0                          ; 16k?
	bsr.w	is_selected
	beq.s	pack_24k                        ; no
	move.l	#$3fff,pack_window+2            ; a 16 K window
	bra.s	pack_output
pack_24k:
	moveq	#17,d0                          ; 24k?
	bsr.w	is_selected
	beq.s	pack_32k                        ; no
	move.l	#$4fff,pack_window+2            ; a 20 K window, for 24k
	bra.s	pack_output
pack_32k:
	move.l	#$7fff,pack_window+2            ; 32k: a 32 K window
pack_output:
	moveq	#29,d0                          ; KILL (object 29)?
	bsr.w	is_selected
	beq.s	pack_keep                       ; no
	move.w	#$ffff,kill_flag                ; yes: over the original
	bra.s	pack_type
pack_keep:
	clr.w	kill_flag                       ; KEEP: as name.POP
pack_type:
	moveq	#33,d0                          ; EXEC (object 33)?
	bsr.w	is_selected
	beq.s	pack_data                       ; no
	clr.w	data_flag                       ; a program
	bra.w	pack_process
pack_data:
	move.w	#$ffff,data_flag                ; DATA
	bra.w	pack_process

;------------------------------------------------------------------------------
; select_drive_path: the path for the drive button selected (A, B, F or D): "X:\*.*", unless it is on that
; drive already.
;------------------------------------------------------------------------------
select_drive_path:	; from: start, form_dial
	move.b	path(pc),d2                     ; the path's drive
	moveq	#21,d0
	bsr.w	is_selected
	beq.s	check_drive_b                   ; no
	cmpi.b	#$41,d2                         ; already?
	bne.s	path_a                          ; no
	rts
path_a:
	move.l	#$413a5c2a,path                 ; "A:\*"
	move.w	#$2e2a,path+4
	clr.w	path+6
	rts
check_drive_b:
	move.w	#$16,d0                         ; B?
	bsr.w	is_selected
	beq.s	check_drive_f
	cmpi.b	#$42,d2
	bne.s	path_b
	rts
path_b:
	move.l	#$423a5c2a,path                 ; "B:\*"
	move.w	#$2e2a,path+4
	clr.w	path+6
	rts
check_drive_f:
	move.w	#$17,d0                         ; F?
	bsr.w	is_selected
	beq.s	check_drive_d
	cmpi.b	#$46,d2
	bne.s	path_f
	rts
path_f:
	move.l	#$463a5c2a,path                 ; "F:\*"
	move.w	#$2e2a,path+4
	clr.w	path+6
	rts
check_drive_d:
	move.w	#$18,d0                         ; D (not checked: the last)
	bsr.w	is_selected
	cmpi.b	#$44,d2
	bne.s	path_d
	rts
path_d:
	move.l	#$443a5c2a,path
	move.w	#$2e2a,path+4
	clr.w	path+6
	rts
pack_process:	; from: start
	moveq	#4,d0                           ; FILE?
	bsr.w	is_selected
	beq.s	process_batch                   ; no
	clr.w	process_mode                    ; one file
	clr.w	disc_flag
	move.w	#$ffff,file_flag
	bra.s	pack_show_source
process_batch:
	moveq	#5,d0                           ; B1?
	bsr.w	is_selected
	bne.s	process_b1                      ; yes
	moveq	#9,d0                           ; B2?
	bsr.w	is_selected
	beq.w	disc_flag                       ; no: DISC, but the branch goes to disc_flag, not process_disc
	move.w	#$fffe,process_mode             ; B2: the files with the extension of one chosen
	bra.s	process_batch_go
process_b1:
	move.w	#$ffff,process_mode             ; B1: the files chosen one after another
process_batch_go:
	clr.w	stop_flag
	clr.w	disc_flag
	clr.w	file_flag
	move.w	#$ffff,kill_flag
	bra.s	pack_show_source
process_disc:
	moveq	#6,d0                           ; DISC?
	bsr.w	is_selected
	beq.s	pack_show_source                ; no
	move.w	#$ffff,disc_flag                ; every folder of the disk
	clr.w	process_mode
	clr.w	file_flag
	move.w	#$ffff,kill_flag
	clr.b	path                            ; the path from the root
	bsr.w	select_drive_path
	clr.b	path_mask
	clr.w	stop_flag
pack_show_source:
	move.w	#$25,d0                         ; the source position field (37) selected?
	bsr.w	is_selected
	beq.s	source_shown
	move.w	#$25,d0
	bsr.w	deselect
	move.w	#$ffff,hide_source
	move.w	#$25,d0
	bsr.w	disable
	bra.s	pack_show_output
source_shown:
	clr.w	hide_source
	move.w	#$25,d0
	bsr.w	enable
pack_show_output:
	move.w	#$26,d0                         ; the output position field (38) selected?
	bsr.w	is_selected
	beq.s	output_shown
	move.w	#$26,d0
	bsr.w	deselect
	move.w	#$ffff,hide_output
	move.w	#$26,d0
	bsr.w	disable
	bra.w	pack_go
output_shown:
	clr.w	hide_output
	move.w	#$26,d0
	bsr.w	enable
	bra.w	pack_go

;------------------------------------------------------------------------------
; menu_stats: the status box: how many files were packed and how many were bad (collided), and the bad
; files' names, nine to a page (EXIT shows the next).  Its Save / No Save sets save_bad, and closing it
; stops the drive lights flashing.
;------------------------------------------------------------------------------
menu_stats:	; from: start, pack_file
	clr.w	stats_pages                     ; no pages yet
	bsr.w	clear_screen                    ; the screen cleared
	moveq	#0,d0
	move.w	bad_count(pc),d0                ; the files packed
	movea.l	d0,a0
	moveq	#3,d7                           ; 3 digits
	lea	stats_packed_text(pc),a2        ; into a buffer
	bsr.w	number_text_width               ; as text
	lea	stats_packed_text(pc),a0
	movea.l	stats_packed_field(pc),a1       ; the "Packed:" field
	moveq	#2,d1                           ; 3 characters
stats_packed_digit:
	move.b	(a0)+,d0
	bne.s	stats_packed_store              ; a digit?
	addi.b	#$30,d0                         ; 0: '0'
stats_packed_store:
	move.b	d0,(a1)+
	dbra	d1,stats_packed_digit
	move.w	files_packed(pc),d0             ; the bad files
	movea.l	d0,a0
	moveq	#3,d7                           ; 3 digits
	lea	stats_bad_text(pc),a2           ; into a buffer
	bsr.w	number_text_width               ; as text
	lea	stats_bad_text(pc),a0
	movea.l	stats_bad_field(pc),a1          ; the "Bad:" field
	moveq	#2,d1
stats_bad_digit:
	move.b	(a0)+,d0
	bne.s	stats_bad_store
	addi.b	#$30,d0
stats_bad_store:
	move.b	d0,(a1)+
	dbra	d1,stats_bad_digit
	tst.w	bad_count                       ; any packed?
	beq.s	stats_empty                     ; no
	move.w	bad_count(pc),d0
	divu.w	#$9,d0                          ; in nines: the pages
	move.w	d0,stats_pages
	lea	bad_names(pc),a0                ; the bad files' names
stats_page:
	lea	stats_names(pc),a2              ; the nine name strings
	moveq	#8,d0                           ; 9 of them
stats_name:
	movea.l	(a2)+,a1
stats_name_copy:
	move.b	(a0)+,(a1)+                     ; copied
	bne.s	stats_name_copy
	dbra	d0,stats_name
	bsr.w	show_status_box                 ; the box shown
	subq.w	#1,stats_pages                  ; one page fewer
	bpl.s	stats_page                      ; more?
	bra.s	stats_done
stats_empty:
	bsr.w	show_status_box                 ; the box shown
	move.w	d0,button
stats_done:
	moveq	#4,d0                           ; Save (object 4) selected?
	movea.l	tree_status(pc),a0
	mulu.w	#$18,d0
	adda.l	d0,a0
	lea	$a(a0),a0
	btst	#$0,1(a0)
	seq	save_bad                        ; save_bad: nonzero for No Save
	movea.l	vbl_slot_lights(pc),a3          ; the drive lights' VBL slot
	tst.l	vbl_slot_lights                 ; flashing?
	beq.s	stats_return                    ; no
	bsr.w	stop_drive_lights               ; stopped
stats_return:
	bra.w	main_redraw
stats_packed_text:
	dc.w	$0000,$0000,$0000
stats_bad_text:
	dc.w	$0000,$0000,$0000
stats_pages:
	dc.w	$0000

;------------------------------------------------------------------------------
; clear_stats_names: the status box's nine name strings back to dashes.
;------------------------------------------------------------------------------
clear_stats_names:	; from: pack_go
	lea	stats_names(pc),a2              ; the nine strings
	moveq	#8,d2                           ; 9 of them
	moveq	#45,d0                          ; '-'
clear_stats_name:
	moveq	#14,d1                          ; 15 characters
	movea.l	(a2)+,a0
clear_stats_char:
	move.b	d0,(a0)+
	dbra	d1,clear_stats_char
	dbra	d2,clear_stats_name
	rts
alert_header:
	dc.b	'[2][Please select a depack header|for programs. Choose either | ' ; "Please select a depack header for
                                                ;   programs: Normal / Printed / Utility"
	dc.b	'PRINTED / NORMAL / UTILITY|as a depack header.][ Normal|Printed|'
	dc.b	'Utility ]',0
menu_header:	; from: start
	move.w	#$1,aes_int_in
	move.l	#alert_header,aes_addr_in       ; "Please select a depack header..."
	moveq	#52,d0                          ; form_alert
	bsr.w	aes
	move.w	d0,header_type                  ; the header chosen
	bra.w	main_loop
header_type:	; from: pack_file
	dc.w	$0000,$3f3c,$00ff,$3f3c,$0006,$4e41,$588f,$4a00 ; 1 Normal, 2 Printed, 3 Utility
	dc.w	$67f0,$4e75

;------------------------------------------------------------------------------
; deselect(d0): clear an object's SELECTED in the main dialog; deselect_object does it in the tree at a0.
;------------------------------------------------------------------------------
deselect:	; from: start, select_drive_path, form_dial
	move.w	d0,button                       ; kept
	movea.l	tree_main(pc),a0

deselect_object:	; from: object_state, show_status_box
	mulu.w	#$18,d0                         ; 24 bytes an object
	adda.l	d0,a0
	lea	$a(a0),a0                       ; its state
	bclr	#$0,1(a0)                       ; SELECTED off
	rts

;------------------------------------------------------------------------------
; select(d0): set an object's SELECTED.
;------------------------------------------------------------------------------
select:	; from: start
	bsr.s	object_state
	bset	#$0,1(a0)                       ; SELECTED on
	rts

;------------------------------------------------------------------------------
; is_selected(d0): Z clear when the object is selected.
;------------------------------------------------------------------------------
is_selected:	; from: start, select_drive_path
	bsr.s	object_state
	btst	#$0,1(a0)                       ; SELECTED?
	rts

;------------------------------------------------------------------------------
; enable(d0): clear an object's DISABLED.
;------------------------------------------------------------------------------
enable:	; from: select_drive_path, form_dial, pack_file
	move.w	d0,button
	bsr.s	object_state
	bclr	#$3,1(a0)                       ; DISABLED off
	rts

;------------------------------------------------------------------------------
; disable(d0): set an object's DISABLED.
;------------------------------------------------------------------------------
disable:	; from: select_drive_path, form_dial, pack_go
	move.w	d0,button
	bsr.s	object_state
	bset	#$3,1(a0)                       ; DISABLED on
	rts

;------------------------------------------------------------------------------
; object_state(d0): a0 = the address of an object's state in the main dialog.
;------------------------------------------------------------------------------
object_state:	; from: select, is_selected, enable, disable
	movea.l	tree_main(pc),a0                ; the main dialog
	mulu.w	#$18,d0                         ; 24 bytes an object
	adda.l	d0,a0
	lea	$a(a0),a0                       ; its state
	rts
menu_free:	; from: start
	bsr.w	show_free                       ; the free space shown
	bra.w	main_loop
menu_about_cls:	; from: start
	bsr.w	clear_screen                    ; the screen cleared first
menu_about:
	bsr.w	shrink                          ; a shrinking box
	move.l	tree_about,aes_addr_in          ; the about box
	moveq	#54,d0                          ; form_center
	bsr.w	aes
	move.l	tree_about,aes_addr_in          ; the about box
	move.w	#$0,aes_int_in                  ; from the root
	move.w	#$6,aes_int_in+2                ; depth 6
	move.w	about_x,aes_int_in+4            ; its box
	move.w	about_y,aes_int_in+6
	move.w	about_w,aes_int_in+8
	move.w	about_h,aes_int_in+10
	moveq	#42,d0                          ; objc_draw
	bsr.w	aes
	move.l	tree_about,aes_addr_in          ; the about box
	move.w	#$0,aes_int_in                  ; no edit field
	moveq	#50,d0                          ; form_do
	bsr.w	aes
	move.w	d0,button                       ; the button
	movea.l	tree_about(pc),a0
	bsr.w	deselect_object
	bsr.w	clear_screen
	bsr.w	shrink
	bra.w	main_redraw
menu_files:	; from: start
	move.l	work_start(pc),work_saved
	bsr.w	set_drive                       ; the drive
	bsr.w	set_dta                         ; the DTA
	move.w	#$3,aes_int_in                  ; the default button: Oops
	move.l	#alert_files,aes_addr_in        ; "Choose wether you want to REName or DELete a file"
	moveq	#52,d0                          ; form_alert
	bsr.w	aes
	cmpi.w	#$1,d0                          ; DEL?
	beq.s	files_delete
	cmpi.w	#$2,d0
	beq.s	files_rename
	bra.w	main_loop                       ; Oops
files_delete:
	lea	file_name(pc),a0                ; the name
	bsr.w	choose_file                     ; chosen
	tst.w	d0                              ; cancelled?
	beq.w	main_loop                       ; yes
	bsr.w	set_drive                       ; the drive
	bsr.w	set_folder                      ; the path
	bsr.w	set_dta                         ; the DTA
	pea	file_name(pc)
	move.w	#$41,-(sp)
	trap	#1                              ; Fdelete
	addq.l	#6,sp
files_done:
	bsr.w	clear_names                     ; the names cleared
	bra.w	main_loop
files_rename:
	lea	file_name(pc),a0                ; the name
	bsr.w	choose_file                     ; chosen
	tst.w	d0                              ; cancelled?
	beq.w	main_loop                       ; yes
	bsr.w	set_drive                       ; the drive
	bsr.w	set_folder                      ; the path
	bsr.w	set_dta                         ; the DTA
	lea	file_name(pc),a0                ; the old name
	lea	saved_name(pc),a1               ; copied
	movem.l	a1,-(sp)
files_copy_name:
	move.b	(a0)+,(a1)+
	bne.s	files_copy_name
	movem.l	(sp)+,a0                        ; the new name
	bsr.w	choose_file                     ; chosen
	tst.w	d0                              ; cancelled?
	beq.w	main_loop                       ; yes
	pea	saved_name(pc)
	pea	file_name(pc)
	clr.w	-(sp)
	move.w	#$56,-(sp)
	trap	#1                              ; Frename
	lea	$c(sp),sp
	bra.s	files_done

;------------------------------------------------------------------------------
; tree_address(d0): a0 = the address of tree d0 (rsrc_gaddr R_TREE).
;------------------------------------------------------------------------------
tree_address:	; from: start
	move.w	#$0,aes_int_in                  ; R_TREE
	move.w	d0,aes_int_in+2                 ; the tree
	move.l	#$700002,aes_control            ; control: rsrc_gaddr, 2 ints in, 1 out
	move.l	#$10000,aes_control+4           ; 0 addresses in, 1 out
	move.w	#$1,aes_control+8
	move.l	#aes_block,d1                   ; the AES parameter block
	move.w	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	move.w	aes_int_out,d0                  ; the result
	movea.l	aes_addr_out(pc),a0
	rts

;------------------------------------------------------------------------------
; show_status_box: the status box, until a button.
;------------------------------------------------------------------------------
show_status_box:	; from: menu_stats
	movem.l	d0-d7/a0-a6,-(sp)
	bsr.w	clear_screen                    ; the screen cleared
	bsr.w	shrink                          ; a shrinking box
	move.l	tree_status,aes_addr_in         ; the status box
	moveq	#54,d0                          ; form_center
	bsr.w	aes
	move.l	tree_status,aes_addr_in         ; the status box
	move.w	#$0,aes_int_in                  ; from the root
	move.w	#$6,aes_int_in+2                ; depth 6
	move.w	about_x,aes_int_in+4
	move.w	about_y,aes_int_in+6
	move.w	about_w,aes_int_in+8
	move.w	about_h,aes_int_in+10
	moveq	#42,d0                          ; objc_draw
	bsr.w	aes
	move.l	tree_status,aes_addr_in         ; the status box
	move.w	#$0,aes_int_in                  ; no edit field
	moveq	#50,d0                          ; form_do
	bsr.w	aes
	move.w	d0,button                       ; the button
	movea.l	tree_status(pc),a0              ; the status box
	bsr.w	deselect_object                 ; the button deselected
	bsr.w	clear_screen                    ; the screen cleared
	bsr.w	shrink                          ; a shrinking box
	movem.l	(sp)+,d0-d7/a0-a6
	rts
tree_status:	; from: start, menu_stats
	dc.l	$00000000                       ; the status box's tree
tree_about:	; from: start, object_state
	dc.l	$00000000                       ; the about box's tree
about_icon:	; from: start
	dc.l	$00000000                       ; its icon (not used)
about_x:	; from: object_state
	dc.w	$0000
about_y:	; from: object_state
	dc.w	$0000
about_h:	; from: object_state
	dc.w	$0000
about_w:	; from: object_state
	dc.w	$0000
grow_box:	; from: grow
	dc.w	$00d2,$0032,$0000,$0000,$00d2,$0032,$0118,$006e ; graf_growbox's boxes
shrink_box:	; from: shrink
	dc.w	$00d2,$0000,$0000,$0000,$00d2,$0032,$0118,$006e ; graf_shrinkbox's boxes

;------------------------------------------------------------------------------
; draw_object(d0): objc_draw object d0 of the main dialog, as deep as its number.
;------------------------------------------------------------------------------
draw_object:	; from: start, clear_status, clear_time, form_dial, show_free_dfree, pack_file, 4 more
	move.l	tree_main,aes_addr_in           ; the main dialog
	move.w	d0,aes_int_in                   ; the object
	move.w	d0,aes_int_in+2                 ; depth
	move.w	main_x,aes_int_in+4             ; the dialog's box
	move.w	main_y,aes_int_in+6
	move.w	main_w,aes_int_in+8
	move.w	main_h,aes_int_in+10
	moveq	#42,d0                          ; objc_draw
	bsr.w	aes
	rts

;------------------------------------------------------------------------------
; draw_main: the screen cleared and the main dialog drawn again.
;------------------------------------------------------------------------------
draw_main:	; from: choose_file, pack_go, pack_b2
	movem.l	d0-d7/a0-a6,-(sp)
	bsr.w	clear_screen                    ; the screen cleared
	move.l	tree_main,aes_addr_in           ; the main dialog
	move.w	#$0,aes_int_in                  ; from the root
	move.w	#$29,aes_int_in+2               ; depth 41
	move.w	main_x,aes_int_in+4             ; its box
	move.w	main_y,aes_int_in+6
	move.w	main_w,aes_int_in+8
	move.w	main_h,aes_int_in+10
	moveq	#42,d0                          ; objc_draw
	bsr.w	aes
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; clear_status: the status fields back to 0s and spaces, and drawn.
;------------------------------------------------------------------------------
clear_status:	; from: form_dial, pack_file, clear_names
	lea	number_fields(pc),a1            ; the four number fields
	moveq	#48,d1                          ; '0'
	moveq	#3,d2
clear_number:
	movea.l	(a1)+,a0                        ; 6 characters
	moveq	#6,d0
	bsr.s	fill                            ; filled
	dbra	d2,clear_number
	lea	field_percent(pc),a0            ; the percentage
	moveq	#2,d0                           ; 2 characters
	bsr.s	fill
	lea	field_name(pc),a1               ; the two name fields
	moveq	#95,d1                          ; spaces
	moveq	#1,d2
clear_name:
	movea.l	a1,a0
	moveq	#12,d0                          ; 12 characters
	bsr.s	fill                            ; filled
	addq.l	#4,a1
	dbra	d2,clear_name
	moveq	#36,d0
	bsr.w	draw_object                     ; drawn
	rts

;------------------------------------------------------------------------------
; fill: d0 bytes of d1 into the text whose address is at a0.
;------------------------------------------------------------------------------
fill:	; from: clear_status, clear_time, pack_file
	movea.l	(a0),a0                         ; the text
fill_loop:
	move.b	d1,(a0)+
	subq.w	#1,d0
	bne.s	fill_loop
	rts

;------------------------------------------------------------------------------
; clear_time: the time field back to 0s, and drawn.
;------------------------------------------------------------------------------
clear_time:	; from: pack_file
	lea	field_time(pc),a0               ; the time field
	moveq	#6,d0                           ; 6 characters
	moveq	#48,d1                          ; '0'
	bsr.s	fill
	moveq	#44,d0
	bsr.w	draw_object                     ; drawn
	rts

;------------------------------------------------------------------------------
; form_dial(d0): form_dial with the main dialog's box, from a 0 by 9 box.
;------------------------------------------------------------------------------
form_dial:	; from: start
	move.w	d0,aes_int_in                   ; the call
	move.w	#$0,aes_int_in+2                ; the small box: 0, 0
	move.w	#$0,aes_int_in+4
	move.w	#$9,aes_int_in+6                ; 9 by 0
	move.w	#$0,aes_int_in+8
	move.w	main_x,aes_int_in+10            ; the dialog's box
	move.w	main_y,aes_int_in+12
	move.w	main_h,aes_int_in+14
	move.w	main_w,aes_int_in+16
	moveq	#51,d0                          ; form_dial
	bsr.w	aes
	rts
quit:	; from: start, grow
	moveq	#3,d0                           ; FMD_FINISH
	bsr.s	form_dial
	bsr.w	clear_screen
	bsr.w	shrink
	moveq	#19,d0
	bsr.w	aes
	movea.l	vbl_slot_abort(pc),a3
	bsr.w	remove_vbl
	movea.l	vbl_slot_clock(pc),a3
	bsr.w	remove_vbl
	movea.l	vbl_slot_lights(pc),a3
	tst.l	vbl_slot_lights
	beq.s	depack_name_set
	bsr.w	remove_vbl                      ; cleared
depack_name_set:
	clr.w	-(sp)                           ; Pterm(0)
	move.w	#$4c,-(sp)
	trap	#1                              ; Pterm
menu_depack:	; from: start, grow
	tst.l	vbl_slot_lights                 ; depacking
	beq.s	depack_check
	movea.l	vbl_slot_lights(pc),a3
	bsr.w	stop_drive_lights
depack_check:
	move.w	#$ffff,depacking
	moveq	#37,d0
	bsr.w	deselect
	moveq	#38,d0
	bsr.w	deselect                        ; deselected
	bsr.w	set_drive                       ; the drive
	move.l	#$2a2e2a00,d0                   ; "*.*"
	move.l	d0,file_name                    ; as the name
	move.l	d0,saved_name                   ; and the saved name
	tst.w	path_set                        ; the path set already?
	bne.s	depack_choose                   ; yes
	clr.w	path                            ; no: from the drive's root
	bsr.w	select_drive_path
	move.w	#$ffff,path_set                 ; now set
depack_choose:
	moveq	#0,d0
	lea	file_name(pc),a0
	bsr.w	choose_file                     ; chosen
	tst.w	d0                              ; cancelled?
	beq.w	main_loop                       ; yes: the main dialog
	move.l	work_start(pc),load_address
	bsr.w	set_drive                       ; the drive
	bsr.w	set_folder                      ; the path
	bsr.w	load_file                       ; loaded
	tst.l	d0                              ; an error?
	bmi.w	file_error                      ; yes
	movea.l	load_address(pc),a0
	moveq	#0,d0
	moveq	#0,d1
	adda.l	d6,a0                           ; its end
	subq.l	#4,a0                           ; the last long
	movea.l	a0,a4
	movep.w	0(a0),d0                        ; 'P' and 'P'
	movep.w	1(a0),d1                        ; + 'O' and 'I'
	add.l	d0,d1
	cmpi.w	#$9f99,d1                       ; 'POPI'?
	beq.s	depack_check_previous
	subq.l	#4,a0                           ; the long before
	movea.l	a0,a4
	movep.w	0(a0),d0
	movep.w	1(a0),d1
	add.l	d0,d1
	cmpi.w	#$9f99,d1                       ; 'POPI'?
	beq.s	depack_check_previous
	bra.w	not_packed
depack_check_previous:
	bsr.w	depack
	move.l	d6,d5
	subq.l	#1,d5
	adda.l	d6,a4
	movea.l	work_end(pc),a0
depack_found_popi:
	move.b	-(a4),-(a0)
	dbra	d5,depack_found_popi
	move.l	a0,load_address
	bsr.w	clear_status
	movea.l	d6,a0
	movea.l	field_packed(pc),a2
	bsr.w	number_text
	move.w	#$2d,d0
	bsr.w	enable
	movea.l	field_name(pc),a0
	lea	file_name(pc),a1                ; the name
depack_copy_name:
	move.b	(a1)+,(a0)+                     ; copied
	bne.s	depack_copy_name
	move.w	#$24,d0                         ; the status box
	bsr.w	draw_object                     ; drawn
	bsr.w	show_free                       ; the free space
	bra.w	main_loop                       ; the main dialog
menu_save:	; from: start
	lea	file_name(pc),a0
	bsr.w	choose_file                     ; chosen
	tst.w	d0                              ; cancelled?
	beq.w	main_loop                       ; yes
	bsr.w	set_drive
	bsr.w	set_folder
save_create:
	clr.w	-(sp)                           ; normal file
	pea	file_name(pc)                   ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	tst.l	d0                              ; created?
	bpl.s	save_write                      ; yes
	cmpi.w	#$fff3,d0                       ; write protected?
	bne.w	create_error                    ; no: "Open out error."
	bsr.w	write_protected                 ; "Disc is WRITE protected!"
	cmpi.w	#$1,d0                          ; Retry?
	beq.s	save_create                     ; yes
	bra.s	save_done                       ; no
save_write:
	move.w	d0,handle                       ; the handle
	move.l	load_address(pc),-(sp)          ; the depacked file
	move.l	d6,-(sp)                        ; its length
	move.w	handle(pc),-(sp)                ; the handle
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	move.w	handle(pc),-(sp)                ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
save_done:
	move.w	#$2d,d0                         ; SAVE (object 45)
	bsr.w	disable
	bsr.w	clear_status
	move.w	#$24,d0                         ; the status
	bsr.w	draw_object                     ; drawn
	bra.w	main_loop

;------------------------------------------------------------------------------
; depack: depack the 'POPI' file at a4 (its last long, or the one before) in supervisor mode, flashing
; the background.  The last longs are the unpacked length, then the packed length; the codes are bits
; read from the end down, a byte at a time, the output written from its end down over the packed data.
; a4 = the depacked file, d6 = its length; "That file is bad" when the output would pass the input.
;------------------------------------------------------------------------------
depack:	; from: form_dial
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	move.l	d0,2(sp)                        ; the old stack, as the argument
	movea.l	a4,a0                           ; the end
	movea.l	a4,a2
	addq.l	#4,a2                           ; past 'POPI'
	move.l	-(a0),d6                        ; the unpacked length
	move.l	-(a0),d2                        ; the packed length
	suba.l	d2,a2                           ; back to its start
	movea.l	a2,a4                           ; a4 = where it depacks to
	adda.l	d6,a2                           ; + the length: a2 = its end
	moveq	#0,d0
	moveq	#0,d5
	lea	$ff8240,a6                      ; palette 0
	move.w	(a6),d7                         ; the background colour
depack_skip_zeros:
	move.b	-(a0),d0                        ; the first byte of bits
	beq.s	depack_skip_zeros               ; 0: padding
depack_loop:
	moveq	#0,d2
	cmpa.l	a2,a0                           ; the output past the input?
	bgt.w	depack_bad                      ; yes: bad
	bsr.w	depack_bit                      ; a bit
	bcs.s	depack_code                     ; 1: a code
	move.b	-(a0),d2                        ; 0: a literal
depack_store:
	move.b	d2,-(a2)                        ; stored, downwards
	bra.s	depack_next
depack_short:
	moveq	#15,d4                          ; 110: a 0 byte, or a 3 byte string
	moveq	#2,d3                           ; 3 bytes
	bsr.w	depack_offset_d4                ; the offset, or all ones
	bne.s	depack_copy                     ; an offset: the string
	move.w	d4,d2                           ; all ones: a 0
	bra.s	depack_store
depack_code:
	bsr.s	depack_bit
	bcc.s	depack_string                   ; 10: a string
	bsr.s	depack_bit                      ; a bit
	bcc.s	depack_short                    ; 110
	bsr.s	depack_bit                      ; a bit
	bcs.s	depack_code_2                   ; 1111
	moveq	#2,d1                           ; 3 bits
	bsr.w	depack_bits                     ; 1110: a byte with one bit set
	exg	d1,d2                           ; the bit number
	addq.w	#1,d2
	bset	d1,d2                           ; that bit alone
	bra.s	depack_store                    ; stored
depack_code_2:
	bsr.s	depack_bit                      ; the next bit
	bcc.s	depack_string_5
	moveq	#15,d4                          ; 11110: a 4 byte string, or a pair
	move.w	#$3,d3                          ; 4 bytes
	bsr.s	depack_offset_d4                ; the offset, or all ones
	bne.s	depack_copy                     ; an offset: the string
	move.b	(a2),-(a2)                      ; all ones: the byte before again
depack_next:
	neg.w	(a6)                            ; the background flashed
	move.w	d7,(a6)                         ; and back
	cmpa.l	a2,a4                           ; all done?
	blt.s	depack_loop                     ; no
	trap	#1                              ; GEMDOS, Super(old stack)
	addq.l	#6,sp
	rts
depack_string_5:
	moveq	#4,d3                           ; 5 bytes
	bra.s	depack_string_offset            ; the offset
depack_string:
	bsr.s	depack_bit                      ; a bit
	bcs.s	depack_byte_run                 ; 101: a 2 byte string, 8 bit offset
	moveq	#1,d1                           ; 100: the length's size, 2 bits
depack_length_bits:
	lsr.b	#1,d0
	bne.s	depack_length_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
depack_length_bit_got:
	addx.w	d2,d2
	dbra	d1,depack_length_bits
	move.w	d2,d1                           ; the length
	beq.s	depack_string_2                 ; 0?
	addq.w	#1,d1                           ; + 1
	add.w	d1,d1                           ; * 2
	subq.w	#1,d1                           ; less one
	bsr.s	depack_bits                     ; 2, 4, 6 or 8 bits of length
	move.w	d2,d3                           ; the length less one
depack_string_offset:
	bsr.s	depack_offset                   ; then the offset
depack_copy:	; from: depack_bits
	movea.l	a2,a1                           ; from the offset
	adda.l	d2,a1                           ; back
depack_copy_loop:
	move.b	-(a1),-(a2)
	dbra	d3,depack_copy_loop             ; for each byte
	bra.s	depack_next                     ; the next

;------------------------------------------------------------------------------
; depack_bit: the next bit into x and c, a new byte (with its marker) when needed.
;------------------------------------------------------------------------------
depack_bit:	; from: depack
	lsr.b	#1,d0                           ; the next bit
	bne.s	depack_bit_got                  ; the byte still has bits
	move.b	-(a0),d0                        ; no: the next byte down
	roxr.b	#1,d0                           ; its marker in, the first bit out
depack_bit_got:
	rts

;------------------------------------------------------------------------------
; depack_offset: a 2 bit size code and then that many bits of offset (4, 8, 12 or 16); with d4 set, all
; ones in the code means d4 instead.
;------------------------------------------------------------------------------
depack_offset:	; from: depack, depack_bits
	moveq	#0,d4                           ; no all ones code

depack_offset_d4:	; from: depack
	moveq	#1,d1                           ; 2 bits: the size
	moveq	#0,d2
depack_offset_loop:
	lsr.b	#1,d0
	bne.s	depack_offset_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
depack_offset_bit_got:
	addx.w	d2,d2
	dbra	d1,depack_offset_loop
	move.w	d2,d1                           ; (code + 1) * 4 - 1: 3, 7, 11 or 15
	addq.w	#1,d1
	lsl.w	#2,d1
	subq.w	#1,d1                           ; bits less one
	eor.b	d1,d4                           ; all ones with d4 = 15?
	bne.s	depack_bits                     ; no: the offset
	rts
	moveq	#7,d1                           ; (not reached: 8 bits)

;------------------------------------------------------------------------------
; depack_bits: d2 = the next d1 + 1 bits.
;------------------------------------------------------------------------------
depack_bits:	; from: depack, depack_offset_d4
	moveq	#0,d2
depack_bits_loop:
	lsr.b	#1,d0
	bne.s	depack_bits_got
	move.b	-(a0),d0
	roxr.b	#1,d0
depack_bits_got:
	addx.w	d2,d2                           ; into d2
	dbra	d1,depack_bits_loop             ; for each bit
	rts
depack_string_2:	; from: depack
	bsr.s	depack_offset                   ; 1000: a run of the byte before, its length as an offset is
	move.w	d2,d3                           ; the length less one
	moveq	#1,d2                           ; offset 1: the byte before
	bra.s	depack_copy                     ; copied
depack_byte_run:	; from: depack
	moveq	#1,d3                           ; 101: 2 bytes
	move.b	-(a0),d2                        ; the 8 bit offset
	bra.s	depack_copy                     ; copied

;------------------------------------------------------------------------------
; clear_screen: hide the mouse, clear the 32000 bytes at the top of the TPA, show the mouse again.
;------------------------------------------------------------------------------
clear_screen:	; from: start, menu_stats, object_state, show_status_box, draw_main, form_dial, 2 more
	bsr.s	hide_mouse                      ; the mouse hidden
	movem.l	d0-d1/a0,-(sp)
clear_screen_address:
	movea.l	#$0,a0                          ; the screen (put in at the start)
	move.l	#$7d0,d1                        ; 2001 times 16 bytes
	moveq	#0,d0
clear_screen_loop:
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	dbra	d1,clear_screen_loop
	bsr.s	show_mouse
	movem.l	(sp)+,d0-d1/a0
	rts

;------------------------------------------------------------------------------
; show_mouse: Line-A show mouse, after any number of hides.
;------------------------------------------------------------------------------
show_mouse:	; from: start, clear_screen, pack_file
	movem.l	d0-d2/a0-a3,-(sp)
	dc.w	$a000                           ; Line-A $0, Line-A init
	movea.l	8(a0),a0                        ; intin
	clr.w	(a0)                            ; 0: show however often hidden
	dc.w	$a009                           ; Line-A $9, show mouse
	movem.l	(sp)+,d0-d2/a0-a3
	rts

;------------------------------------------------------------------------------
; hide_mouse: Line-A hide mouse.
;------------------------------------------------------------------------------
hide_mouse:	; from: start, clear_screen, pack_file
	movem.l	d0-d2/a0-a3,-(sp)
	dc.w	$a00a                           ; Line-A $a, hide mouse
	movem.l	(sp)+,d0-d2/a0-a3
	rts

;------------------------------------------------------------------------------
; shrink: graf_shrinkbox with shrink_box.
;------------------------------------------------------------------------------
shrink:	; from: object_state, show_status_box, form_dial
	lea	shrink_box(pc),a0
	move.w	(a0),aes_int_in
	move.w	2(a0),aes_int_in+2
	move.w	4(a0),aes_int_in+4
	move.w	6(a0),aes_int_in+6
	move.w	8(a0),aes_int_in+8
	move.w	$a(a0),aes_int_in+10
	move.w	$c(a0),aes_int_in+12
	move.w	$e(a0),aes_int_in+14
	moveq	#74,d0                          ; graf_shrinkbox
	bsr.w	aes
	rts

;------------------------------------------------------------------------------
; grow: graf_growbox with grow_box.
;------------------------------------------------------------------------------
grow:	; from: start
	lea	grow_box(pc),a0
	move.w	(a0),aes_int_in
	move.w	2(a0),aes_int_in+2
	move.w	4(a0),aes_int_in+4
	move.w	6(a0),aes_int_in+6
	move.w	8(a0),aes_int_in+8
	move.w	$a(a0),aes_int_in+10
	move.w	$c(a0),aes_int_in+12
	move.w	$e(a0),aes_int_in+14
	moveq	#73,d0                          ; graf_growbox
	bsr.w	aes
	rts
not_packed:	; from: form_dial
	move.w	#$1,aes_int_in                  ; the button
	move.l	#alert_not_packed,aes_addr_in   ; "This file is not packed with the POMPEY PACKER"
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	bra.w	main_loop
no_resource:	; from: start
	move.w	#$1,aes_int_in                  ; the button
	move.l	#alert_no_resource,aes_addr_in  ; "Resource file missing!"
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	bra.w	quit                            ; quit
file_error:	; from: form_dial
	move.w	handle(pc),-(sp)                ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	move.w	#$1,aes_int_in                  ; the button
	move.l	#alert_file_error,aes_addr_in   ; "FILE error, you just blew it! Wanna try again"
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	cmpi.b	#$1,d0                          ; Yes?
	beq.w	menu_depack                     ; yes: again
	bra.w	main_loop
depack_bad:	; from: depack
	move.w	d7,(a6)                         ; the colour back
	trap	#1                              ; GEMDOS, Super(old stack)
	addq.l	#6,sp
	move.w	#$1,aes_int_in                  ; the button
	move.l	#alert_bad_file,aes_addr_in     ; "Whoops. That file is bad. It collided with depack data."
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	bra.w	main_loop

;------------------------------------------------------------------------------
; parse_decimal(a0 = the text, d0 = its digits): its value into parsed_value, then the offset field set
; back to 0s.
;------------------------------------------------------------------------------
parse_decimal:	; from: pack_go
	movem.l	d0-d4/a0-a2,-(sp)
	moveq	#0,d3
	moveq	#0,d1                           ; the value
	moveq	#48,d2                          ; '0'
	lea	powers_of_ten(pc),a1            ; the powers of ten
	move.w	d0,d1                           ; for d0 digits
	lsl.w	#2,d1
	adda.l	d1,a1                           ; past the highest
	moveq	#0,d1
parse_decimal_loop:
	moveq	#0,d4
	subq.l	#4,a1                           ; the next lower
	move.l	(a1),d3
	move.b	(a0),d4                         ; the digit
	beq.s	parse_decimal_done              ; none: done
	sub.w	d2,d4                           ; its value
	mulu.w	d3,d4                           ; * its power
	add.l	d4,d1                           ; added
	addq.w	#1,a0
	subq.w	#1,d0                           ; one digit fewer
	bne.s	parse_decimal_loop
parse_decimal_done:
	move.l	d1,parsed_value                 ; the value
	movem.l	(sp)+,d0-d4/a0-a2
	rts

;------------------------------------------------------------------------------
; object_text(d0): a0 = the text of a text object of the main dialog; object_text_in does it in the tree
; at a0 (for an image, its data).
;------------------------------------------------------------------------------
object_text:	; from: start
	movea.l	tree_main(pc),a0                ; the main dialog

object_text_in:	; from: start
	mulu.w	#$18,d0                         ; 24 bytes an object
	adda.l	d0,a0
	lea	$c(a0),a0                       ; its spec
	movea.l	(a0),a1                         ; the TEDINFO
	movea.l	(a1),a0                         ; its text
	rts

;------------------------------------------------------------------------------
; object_spec(a0 = a tree, d0): a0 = an object's spec (a string's text).
;------------------------------------------------------------------------------
object_spec:	; from: start
	mulu.w	#$18,d0                         ; 24 bytes an object
	adda.l	d0,a0
	lea	$c(a0),a0
	movea.l	(a0),a0                         ; its spec
	rts

;------------------------------------------------------------------------------
; choose_file(a0 = the name): fsel_input on the path; d0 = 0 when cancelled.  The dialog is drawn again.
;------------------------------------------------------------------------------
choose_file:	; from: object_state, form_dial, pack_b2
	bsr.w	set_dta                         ; the DTA
	move.l	#path,aes_addr_in               ; the path
	move.l	a0,aes_addr_in+4                ; the name
	moveq	#90,d0                          ; fsel_input
	bsr.w	aes
	bsr.w	draw_main                       ; the main dialog again
	move.w	aes_int_out+2,d0                ; OK?
	rts

;------------------------------------------------------------------------------
; show_free: Dfree of the path's drive, the free bytes shown in object 22.
;------------------------------------------------------------------------------
show_free:	; from: object_state, form_dial, pack_file
	move.b	path(pc),d0                     ; the drive
	subi.b	#$40,d0                         ; 1 for A
	ext.w	d0
	move.w	d0,-(sp)
	bsr.s	show_free_dfree
dfree_buffer:	; from: show_free_dfree
	dc.w	$0000,$0000,$0000,$0000         ; free clusters, total clusters
dfree_sector_size:	; from: show_free_dfree
	dc.l	$00000000                       ; bytes a sector
dfree_cluster_size:	; from: show_free_dfree
	dc.l	$00000000                       ; sectors a cluster

show_free_dfree:	; from: show_free
	move.w	#$36,-(sp)                      ; Dfree (the buffer is the return address pushed)
	trap	#1                              ; Dfree
	addq.l	#8,sp
	move.l	dfree_cluster_size,d0           ; sectors a cluster
	move.l	dfree_sector_size,d1            ; * bytes a sector
	mulu.w	d1,d0
	move.l	dfree_buffer(pc),d1
	mulu.w	d1,d0
	movea.l	d0,a0                           ; the free bytes
	movem.l	d0,-(sp)
	movea.l	field_free(pc),a2
	moveq	#8,d7
	bsr.w	number_text_width
	moveq	#25,d0
	bsr.w	draw_object                     ; drawn
	movem.l	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; clear_work: clear the work memory, from work_start to the end.
;------------------------------------------------------------------------------
clear_work:	; from: pack_go, pack_b2, utility_stub_bits
	movem.l	d0-d7/a0-a6,-(sp)
	movea.l	work_start(pc),a0
	move.l	work_end(pc),d0
	sub.l	a0,d0
	lsr.l	#3,d0                           ; in 8 bytes
	subq.l	#4,d0                           ; less a little
	moveq	#0,d1
clear_work_loop:
	move.l	d1,(a0)+
	move.l	d1,(a0)+
	subq.l	#1,d0
	bne.s	clear_work_loop
	movem.l	(sp)+,d0-d7/a0-a6
	rts
path_set:	; from: form_dial, pack_go
	dc.w	$0000                           ; the depack path has been set
parsed_value:	; from: parse_decimal, pack_go
	dc.l	$00000000                       ; parse_decimal's result
powers_of_ten:	; from: parse_decimal
	dc.l	$00000001,$0000000a,$00000064,$000003e8 ; 1, 10, 100, 1000, 10000, 100000
	dc.l	$00002710,$000186a0
vdi_handle:	; from: start
	dc.w	$0000                           ; graf_handle's
button:	; from: start, menu_stats, deselect, enable, disable, object_state, 1 more
	dc.w	$0000                           ; the last button
alert_not_packed:	; from: grow
	dc.b	'[1][This file is not packed | with the POMPEY PACKER][ Ughh ]',0
	dc.b	'[2] Do you wish to save | the unpacked file.][ YES | NO ]',0
	dc.b	'[2] Use the old | filename.][ YES | NO ]',0
alert_no_resource:	; from: grow
	dc.b	'[2] Resource file missing! | Please rectify this. ][ OKAY ]',0
alert_bad_file:	; from: grow
	dc.b	'[3] Whoops.  That file is bad news. |It collided with depack dat'
	dc.b	'a.|Repack with a different |COMPRESSION factor or leave it|unpac'
	dc.b	'ked.][ Damn ]',0
	dc.b	$00
tree_main:	; from: start, deselect, object_state, draw_object, draw_main, object_text
	dc.l	$00000000                       ; the main dialog's tree
main_x:	; from: start, draw_object, draw_main, form_dial
	dc.w	$0078                           ; its box, from form_center
main_y:	; from: start, draw_object, draw_main, form_dial
	dc.w	$0028
main_h:	; from: start, draw_object, draw_main, form_dial
	dc.w	$000a
main_w:	; from: start, draw_object, draw_main, form_dial
	dc.w	$0000
app_id:	; from: start
	dc.w	$0000
text_rsc:	; from: start
	dc.b	'pompey.rsc',0
	dcb.b	511,0
stack_top:	; from: start
	dc.w	$0000

;------------------------------------------------------------------------------
; pack_go: the bad names list and the counts cleared, the drive lights stopped, SAVE disabled, the clock
; and the offset set, the work memory cleared, then one file, B1, B2 or DISC.
;------------------------------------------------------------------------------
pack_go:	; from: select_drive_path
	move.l	#bad_names,bad_list_end         ; the bad names list empty
	movea.l	vbl_slot_lights(pc),a3          ; the drive lights' slot
	tst.l	vbl_slot_lights                 ; flashing?
	beq.s	pack_go_reset                   ; no
	bsr.w	stop_drive_lights               ; yes: stopped
pack_go_reset:
	moveq	#45,d0                          ; SAVE
	bsr.w	disable                         ; disabled
	moveq	#0,d0
	move.w	d0,depacking                    ; not depacking
	move.w	d0,path_set                     ; the depack path to be set again
	move.w	d0,files_packed                 ; no files packed
	move.w	d0,bad_count                    ; no bad files
	move.l	d0,clock_ticks                  ; the clock to 0
	move.l	d0,clock_minutes
	move.l	#$4af,d1                        ; 1200 bytes
	lea	bad_names(pc),a0                ; the bad names
pack_go_clear_names:
	move.b	d0,(a0)+                        ; cleared
	dbra	d1,pack_go_clear_names
	bsr.w	clear_stats_names               ; the status box's names too
	move.l	work_start(pc),work_saved       ; the work memory's start, kept
	movea.l	field_offset(pc),a0             ; the offset field
	moveq	#4,d0                           ; 4 digits
	bsr.w	parse_decimal                   ; its value
	bsr.w	clear_names                     ; the names cleared
	move.l	parsed_value(pc),offset         ; the offset
	bsr.w	clear_work                      ; the work memory cleared
	move.w	#$ffff,file_found               ; the first file
pack_again:	; from: write_block
	bsr.w	set_drive                       ; the drive
	bsr.w	set_dta                         ; the DTA
	tst.w	file_flag                       ; one file?
	bne.w	pack_one_file                   ; yes
	tst.w	disc_flag                       ; a disk?
	bne.w	pack_disc                       ; yes
	cmpi.w	#$fffe,process_mode             ; B2?
	beq.w	pack_b2                         ; yes
	move.w	#$ffff,kill_flag
	clr.w	stop_flag
	move.l	work_start(pc),work_saved
	move.l	work_start(pc),mask_list
	bsr.w	clear_screen                    ; the screen cleared
batch_choose:
	bsr.w	set_dta                         ; the DTA
	movea.l	#file_name,a0                   ; the name
	move.l	#path,aes_addr_in               ; the path
	move.l	a0,aes_addr_in+4
	moveq	#90,d0                          ; fsel_input
	bsr.w	aes
	move.w	aes_int_out+2,d0                ; OK?
	bsr.w	clear_screen                    ; the screen cleared
	tst.w	d0
	beq.s	batch_go                        ; no: the list is done
	movea.l	mask_list(pc),a0
	lea	path(pc),a1                     ; the path
batch_copy_path:
	move.b	(a1)+,d0                        ; copied up to the '*'
	move.b	d0,(a0)+
	cmpi.b	#$2a,d0
	bne.s	batch_copy_path
	lea	file_name(pc),a1                ; then the name
batch_copy_name:
	move.b	(a1)+,(a0)+
	bne.s	batch_copy_name
	move.l	a0,mask_list                    ; the list's new end
	addq.w	#1,mask_count                   ; one more
	bra.s	batch_choose                    ; another
batch_go:
	clr.l	clock_ticks                     ; the clock to 0
	clr.l	clock_minutes
	bsr.w	draw_main                       ; the main dialog
	addq.w	#1,mask_count
	move.l	mask_list(pc),d0
	btst	#$0,d0
	beq.s	batch_even
	addq.l	#1,d0
batch_even:
	move.l	d0,work_start
	move.l	work_saved(pc),mask_list
batch_next_mask:
	subq.w	#1,mask_count
	tst.w	mask_count
	beq.w	pack_finished
	movea.l	mask_list(pc),a1
	lea	path(pc),a0                     ; the path
batch_get_path:
	move.b	(a1)+,d0                        ; up to the '*'
	move.b	d0,(a0)+
	cmpi.b	#$2a,d0
	bne.s	batch_get_path
	move.b	#$2e,(a0)                       ; "*.*" after it
	move.b	#$2a,1(a0)
	clr.b	2(a0)
	lea	file_name(pc),a0                ; the name
batch_get_name:
	move.b	(a1)+,(a0)+
	bne.s	batch_get_name
	move.l	a1,mask_list                    ; the next entry
	bsr.w	set_drive                       ; the drive
	bsr.w	set_folder                      ; the path
	clr.w	-(sp)                           ; normal files
	pea	file_name(pc)
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.w	d0
	bmi.w	pack_finished
	bsr.w	get_dta
	bsr.w	check_type
	bsr.w	pack_file
	bsr.w	clear_names
	bsr.w	clear_work
	bra.s	batch_next_mask

;------------------------------------------------------------------------------
; pack_b2: B2: the files of the folder with the extension of one file chosen ("*.ext").
;------------------------------------------------------------------------------
pack_b2:	; from: pack_go
	move.w	#$ffff,kill_flag                ; over the originals
	clr.w	stop_flag
	move.l	work_start(pc),work_saved       ; the work memory's start, kept
	move.l	work_start(pc),mask_list
	bsr.w	clear_screen                    ; the screen cleared
	bsr.w	set_dta                         ; the DTA
	movea.l	#file_name,a0                   ; the name
	move.l	#path,aes_addr_in               ; the path
	move.l	a0,aes_addr_in+4
	moveq	#90,d0                          ; fsel_input
	bsr.w	aes
	move.w	aes_int_out+2,d0                ; OK?
	bsr.w	clear_screen                    ; the screen cleared
	tst.w	d0
	beq.w	pack_finished                   ; no: done
	lea	file_name(pc),a0                ; the name chosen
	lea	b2_mask(pc),a1                  ; the mask
	move.b	#$2a,(a1)+                      ; '*'
b2_find_dot:
	cmpi.b	#$2e,(a0)+                      ; to its extension
	bne.s	b2_find_dot
	subq.l	#1,a0                           ; back to the '.'
	cmpi.b	#$2a,1(a0)                      ; "*" as the extension?
	beq.w	pack_finished                   ; yes: refused
b2_copy_extension:
	move.b	(a0)+,(a1)+                     ; ".ext"
	bne.s	b2_copy_extension
	clr.b	(a1)+
	bsr.w	set_drive                       ; the drive
	bsr.w	set_folder                      ; the path
	clr.l	clock_ticks                     ; the clock to 0
	clr.l	clock_minutes
	bsr.w	draw_main                       ; the main dialog
	clr.w	-(sp)                           ; normal files
	pea	b2_mask(pc)                     ; the mask
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.w	d0                              ; any?
	bmi.w	pack_finished                   ; no: done
	bra.s	b2_pack                         ; pack it
b2_next:
	clr.w	-(sp)
	pea	b2_mask(pc)                     ; the mask
	move.w	#$4f,-(sp)
	trap	#1                              ; Fsnext
	addq.l	#8,sp
	tst.w	d0                              ; another?
	bmi.w	pack_finished                   ; no: done
	lea	file_name(pc),a1                ; its name
	movea.l	dta(pc),a0                      ; the DTA
	lea	$1e(a0),a0                      ; the name found
b2_copy_name:
	move.b	(a0)+,(a1)+                     ; copied
	bne.s	b2_copy_name
	clr.b	(a1)+
b2_pack:
	bsr.w	get_dta                         ; the DTA
	bsr.w	check_type                      ; program or data, by the extension
	bsr.w	pack_file                       ; pack it
	bsr.w	clear_work                      ; the work memory cleared
	bsr.w	clear_names                     ; the names cleared
	bra.s	b2_next                         ; the next file
b2_mask:
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000 ; B2's mask: "*." and the extension chosen
pack_one_file:	; from: pack_go
	movea.l	#file_name,a0                   ; the name
	bsr.w	choose_file                     ; chosen
	tst.w	d0                              ; cancelled?
	beq.w	main_loop                       ; yes
	bsr.w	set_drive                       ; the drive
	bsr.w	set_folder                      ; the path
	clr.w	-(sp)                           ; normal files
	pea	file_name(pc)
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.w	d0                              ; found?
	bmi.w	pack_finished                   ; no: done
	bsr.w	get_dta                         ; the DTA
	lea	saved_name(pc),a0
	lea	file_name(pc),a1
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	bsr.w	set_drive
	bsr.w	set_folder
pack_one_go:
	clr.l	clock_ticks                     ; the clock to 0
	clr.l	clock_minutes
	bsr.w	pack_file                       ; pack it
	bra.w	pack_finished                   ; done
path:	; from: select_drive_path, form_dial, choose_file, show_free, pack_go, set_path, 3 more
	dc.w	$413a                           ; the path: "A:\*.*" and room for more
	dc.b	$5c
path_mask:	; from: select_drive_path, enter_folder
	dc.b	'*.*',0
	dcb.b	61,0
pack_disc:	; from: pack_go
	clr.l	clock_ticks                     ; the clock to 0
	clr.l	clock_minutes
	moveq	#0,d0                           ; no offset
	move.l	d0,offset
	bsr.w	set_path                        ; the path set
	bsr.w	clear_names                     ; the names cleared
	movea.l	work_start(pc),a0
	move.l	a0,folder_pointer
	bsr.w	first_folder
	bmi.w	disc_done
	movea.l	dta(pc),a4
	lea	$1e(a4),a4
	movea.l	folder_pointer(pc),a0
	movea.l	a0,a2
	bra.s	disc_check
disc_folder:
	movea.l	a4,a3                           ; the name
	move.l	path(pc),d0
	rol.l	#8,d0
	move.b	d0,(a0)+
	rol.l	#8,d0
	move.b	d0,(a0)+
	rol.l	#8,d0
	move.b	d0,(a0)+
disc_folder_name:
	move.b	(a3)+,(a0)+                     ; then the folder's name
	bne.s	disc_folder_name
	move.b	#$5c,-$1(a0)                    ; a '\' after it
	clr.b	(a0)+                           ; ended
	movea.l	a0,a2                           ; the list's end
disc_next_folder:
	move.w	#$4f,-(sp)
	trap	#1                              ; Fsnext
	addq.l	#2,sp
disc_check:
	tst.w	d0                              ; another?
	bne.s	disc_list_done                  ; no
	btst	#$4,-$9(a4)                     ; a folder?
	beq.s	disc_next_folder                ; no: the next
	movea.l	a2,a0                           ; yes: noted
	bra.s	disc_folder
disc_list_done:
	lea	path(pc),a1                     ; the root itself last: "X:\*"
	move.b	(a1)+,(a2)+
	move.b	(a1)+,(a2)+
	move.b	(a1)+,(a2)+
	move.b	(a1)+,(a2)+
	move.b	#$2a,(a2)
	movea.l	work_saved(pc),a0
	move.l	a0,folder_pointer               ; as the current entry
	move.l	a2,d0                           ; the list's end
	addq.l	#6,d0                           ; + 6
	btst	#$0,d0                          ; odd?
	beq.s	disc_list_even                  ; no
	addq.l	#1,d0                           ; yes: even
disc_list_even:
	move.l	d0,work_start                   ; the work memory from there
	bsr.s	enter_folder
	tst.w	d7
	beq.s	disc_file
	bsr.s	next_folder
disc_file:
	bsr.w	clear_names                     ; the names cleared
	bsr.w	next_file                       ; the next file
	tst.w	no_more_files                   ; no more in this folder?
	beq.s	disc_pack                       ; no
disc_skip:
	bsr.s	next_folder                     ; the next folder
	tst.w	d7                              ; none with files?
	bne.s	disc_skip
	bra.s	disc_file
disc_pack:
	bsr.w	pack_file                       ; pack it
	bsr.w	clear_work                      ; the work memory cleared
	bra.s	disc_file                       ; the next

;------------------------------------------------------------------------------
; next_folder: on to the next folder in the list and into it (enter_folder); at the list's end, done.
;------------------------------------------------------------------------------
next_folder:	; from: pack_b2
	clr.w	no_more_files                   ; more files
	movea.l	folder_pointer(pc),a0
next_folder_skip:
	move.b	(a0)+,d0                        ; past its name
	bne.s	next_folder_skip
	cmpi.b	#$2a,(a0)                       ; the root's "*": the end?
	beq.s	disc_done
	move.l	a0,folder_pointer

;------------------------------------------------------------------------------
; enter_folder(a0): Dsetpath to the folder and Fsfirst "*.*": d7 = 0 when it has files.
;------------------------------------------------------------------------------
enter_folder:	; from: pack_b2
	move.l	a0,-(sp)                        ; the folder
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.w	d0
	bmi.s	enter_folder_none               ; failed
	bsr.w	set_dta                         ; the DTA
	clr.w	-(sp)                           ; normal files
	pea	text_all_files(pc)
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.w	d0                              ; any?
	bne.s	enter_folder_none               ; no
	moveq	#0,d7                           ; yes: 0
	move.w	#$ffff,file_found               ; the first file found
	rts
enter_folder_none:
	move.w	#$ffff,d7                       ; -1
	rts
disc_done:	; from: pack_b2, next_folder
	clr.b	path_mask                       ; the mask cut
	bsr.w	clear_names                     ; the names cleared
	bra.w	pack_finished                   ; done

;------------------------------------------------------------------------------
; first_folder: Fsfirst "*.*" for folders.
;------------------------------------------------------------------------------
first_folder:	; from: pack_b2
	bsr.w	set_dta                         ; the DTA
	move.w	#$10,-(sp)                      ; folders
	pea	text_all_files(pc)
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.w	d0                              ; found?
	rts
folder_pointer:	; from: pack_b2, next_folder
	dc.l	$00000000                       ; the folder list's current entry

;------------------------------------------------------------------------------
; pack_file: load the file in the DTA high in the work memory, pack it (packed data from the work memory's start)
; with the clock running, and write it: data as the packed data and its header, a program behind the stub
; with a one entry relocation table.  It is saved only when it got smaller and the disk has the room: over
; the original (KILL), or as name.POP (KEEP).  A 'POPI' file is left as it is.
;------------------------------------------------------------------------------
pack_file:	; from: pack_go, pack_b2
	bsr.w	find_load_address               ; where to load it
	bsr.w	load_file                       ; loaded
	cmpi.w	#$3,d0                          ; packed already?
	bne.s	pack_file_loaded                ; no
	rts                                     ; yes: left alone
pack_file_loaded:
	tst.l	d0                              ; an error?
	bmi.w	write_error                     ; yes
	bsr.w	hide_mouse                      ; the mouse hidden
	bsr.w	pack                            ; packed
	bsr.w	show_mouse                      ; the mouse shown
	tst.w	abort_flag                      ; Alt-Help?
	bne.w	pack_finished                   ; yes: stopped
	tst.w	bad_flag
	beq.s	pack_file_save
	movea.l	bad_list_end(pc),a0
	lea	file_name(pc),a1
pack_file_note_bad:
	move.b	(a1)+,(a0)+
	bne.s	pack_file_note_bad
	move.l	a0,bad_list_end
	tst.w	save_bad
	beq.s	pack_file_save
	rts
pack_file_save:
	bsr.w	show_time
	lea	$c(a2),a2
	move.l	a2,d0
	movea.l	packed_end(pc),a0
	move.l	d0,whole_length                 ; the whole length
	sub.l	offset,d0                       ; less the offset
	move.l	d0,(a0)+                        ; the packed length
	move.l	file_length(pc),d0
	sub.l	offset,d0                       ; less the offset
	move.l	d0,(a0)+                        ; the unpacked length
	move.l	#$504f5049,(a0)+                ; 'POPI'
	move.l	whole_length(pc),d6
	cmpi.w	#$0,kill_flag                   ; KILL?
	bne.s	pack_file_show                  ; yes
	lea	output_name(pc),a1              ; no: the new name
	movea.l	field_output_name(pc),a2
pack_file_copy_output:
	move.b	(a1)+,(a2)+
	bne.s	pack_file_copy_output
	moveq	#40,d0
	bsr.w	draw_object
pack_file_show:
	movea.l	whole_length(pc),a0             ; the whole length
	movea.l	field_packed(pc),a2
	bsr.w	number_text
	moveq	#42,d0
	bsr.w	draw_object
	move.l	whole_length(pc),d0
	move.l	file_length(pc),d2
	bsr.w	percent_saved                   ; the percentage saved
	bpl.s	pack_file_percent
	moveq	#0,d1                           ; negative: 0
pack_file_percent:
	movea.l	d1,a0
	movea.l	field_percent(pc),a2
	moveq	#2,d7
	bsr.w	number_text_width
	moveq	#43,d0
	bsr.w	draw_object
	move.l	whole_length(pc),d0
	move.l	file_length(pc),d1
	cmp.l	d0,d1
	bgt.s	pack_file_room
	addq.w	#1,files_packed_all
	rts                                     ; no: left alone
pack_file_room:
	bsr.w	show_free                       ; the free space
	tst.w	kill_flag                       ; KILL?
	bne.s	pack_file_kill                  ; yes
	move.l	whole_length(pc),d1
	cmp.l	d0,d1                           ; room?
	blt.s	pack_file_keep                  ; yes
	move.w	#$1,aes_int_in
	move.l	#alert_no_room,aes_addr_in      ; "Not enough room on the disc."
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	cmpi.b	#$2,d0                          ; RETRY?
	beq.s	pack_file_room                  ; yes: again
	rts
pack_file_kill:
	clr.w	-(sp)                           ; normal file
	pea	file_name(pc)
	bra.s	pack_file_create
pack_file_keep:
	clr.w	-(sp)                           ; normal file
	pea	output_name(pc)
pack_file_create:
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	tst.l	d0                              ; created?
	bpl.s	pack_file_write
	cmpi.w	#$fff3,d0
	bne.w	create_error
	bsr.w	write_protected
	cmpi.w	#$1,d0
	beq.s	pack_file_keep
	rts
pack_file_write:
	move.w	d0,handle                       ; the handle
	move.w	d0,d6
	move.l	whole_length(pc),d1             ; the packed length
	tst.w	data_flag                       ; data?
	bne.w	pack_file_data                  ; yes
	cmpi.w	#$2,header_type                 ; Printed?
	beq.s	pack_file_printed               ; yes
	cmpi.w	#$3,header_type                 ; Utility?
	beq.s	pack_file_utility               ; yes
	lea	stub(pc),a0                     ; Normal: the stub
	move.l	#$1c4,d0                        ; its length with its header
	move.l	file_length(pc),d2
	sub.l	d1,d2                           ; less the packed: its BSS
	move.l	d0,stub_text_length             ; the stub's header: text
	move.l	d1,stub_data_length             ; data: the packed data
	move.l	d2,stub_bss_length              ; BSS
	subi.l	#$1c,2(a0)                      ; the text without the header
	bsr.w	write_block                     ; written
	tst.l	d0                              ; an error?
	bmi.w	write_error                     ; yes
	bra.s	pack_file_data_after_stub
pack_file_printed:
	lea	printed_stub(pc),a0             ; the printed stub
	move.l	#$1fc,d0                        ; its length with its header
	move.l	file_length(pc),d2
	sub.l	d1,d2
	move.l	d0,printed_stub_text_length
	move.l	d1,printed_stub_data_length
	move.l	d2,printed_stub_bss_length
	subi.l	#$1c,2(a0)
	bsr.w	write_block
	tst.l	d0
	bmi.w	write_error
	bra.s	pack_file_data_after_stub
pack_file_utility:
	lea	utility_stub(pc),a0             ; the utility stub
	move.l	#$408,d0                        ; its length with its header
	move.l	file_length(pc),d2
	sub.l	d1,d2
	move.l	d0,utility_stub_text_length
	move.l	d1,utility_stub_data_length
	move.l	d2,utility_stub_bss_length
	subi.l	#$1c,2(a0)
	bsr.w	write_block
	tst.l	d0
	bmi.w	write_error
pack_file_data_after_stub:
	movea.l	work_start(pc),a0               ; the packed data
	move.l	d1,d0                           ; its length
	bsr.w	write_block                     ; written
	tst.l	d0                              ; an error?
	bmi.w	write_error                     ; yes
	lea	stub_relocation(pc),a0          ; the relocation table
	moveq	#4,d0
	bsr.w	write_block                     ; written
	tst.l	d0                              ; an error?
	bmi.w	write_error                     ; yes
	bra.s	pack_file_close
pack_file_data:
	movea.l	work_start(pc),a0
	move.l	d1,d0                           ; its length
	movea.l	a0,a1
	bsr.w	write_block                     ; written
	tst.l	d0                              ; an error?
	bmi.w	write_error                     ; yes
pack_file_close:
	move.w	handle(pc),-(sp)                ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	bmi.w	write_error
	rts
pack_finished:	; from: pack_go, pack_b2, enter_folder, write_block
	lea	vbl_drive_lights(pc),a3         ; the drive lights' routine
	bsr.w	install_vbl                     ; into the VBL queue: they flash
	move.l	a3,vbl_slot_lights              ; its slot
pack_done:
	clr.l	offset                          ; all back to the start
	clr.w	mask_count
	clr.w	file_found
	clr.w	kill_flag
	clr.w	no_more_files
	clr.w	file_flag
	clr.w	abort_flag
	clr.w	stop_flag
	move.l	work_saved,work_start           ; the work memory's start back
	bsr.w	clear_status                    ; the status cleared
	move.w	#$25,d0
	bsr.w	enable
	move.w	#$26,d0
	bsr.w	enable
	bsr.w	clear_time
	lea	field_offset(pc),a0
	moveq	#4,d0
	moveq	#48,d1
	bsr.w	fill
	bra.w	menu_stats

;------------------------------------------------------------------------------
; clear_names: the file names cleared ("*.*" as the name), and the status.
;------------------------------------------------------------------------------
clear_names:	; from: object_state, pack_go, pack_b2, enter_folder
	moveq	#0,d0
	lea	file_name(pc),a0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	lea	output_name(pc),a0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	#$2a2e2a00,d0
	move.l	d0,file_name
	move.l	d0,saved_name
	bsr.w	clear_status
	rts

;------------------------------------------------------------------------------
; write_block(a0, d0): Fwrite d0 bytes (made even) from a0 to the handle in d6.
;------------------------------------------------------------------------------
write_block:	; from: pack_file
	move.l	a0,-(sp)
	btst	#$0,d0
	beq.s	write_block_even
	addq.l	#1,d0
write_block_even:
	move.l	d0,-(sp)
	move.w	d6,-(sp)                        ; the handle
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	rts
no_memory:	; from: start
	move.w	#$1,aes_int_in                  ; "Not enough memory for file selector."
	move.l	#alert_no_memory,aes_addr_in
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	bra.s	write_error
	move.w	#$1,aes_int_in                  ; "Disk error. That was clumsy of you." (not reached)
	move.l	#alert_disk_error,aes_addr_in
	moveq	#52,d0
	bsr.w	aes
	bra.s	write_error
	bra.s	write_error
create_error:	; from: form_dial, pack_file
	move.w	#$1,aes_int_in                  ; "Open out error."
	move.l	#alert_create_error,aes_addr_in
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
write_error:	; from: pack_file
	move.w	handle(pc),-(sp)                ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	move.w	#$1,aes_int_in
	move.l	#alert_file_error,aes_addr_in   ; "FILE error, you just blew it! Wanna try again"
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	cmpi.b	#$1,d0                          ; Yes?
	beq.w	pack_again                      ; yes: again
	bra.w	pack_finished                   ; no: done

;------------------------------------------------------------------------------
; write_protected: "Disc is WRITE protected! Please RECTIFY this."; d0 = the button (1 Retry).
;------------------------------------------------------------------------------
write_protected:	; from: form_dial, pack_file
	move.w	#$1,aes_int_in
	move.l	#alert_write_protected,aes_addr_in ; "Disc is WRITE protected!"
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	rts

;------------------------------------------------------------------------------
; check_type: data_flag by the name's extension: 0 for PRG, TOS or TTP.
;------------------------------------------------------------------------------
check_type:	; from: pack_go, pack_b2
	lea	file_name(pc),a2                ; the name
	lea	extension_codes(pc),a0
	movea.l	a0,a1
check_type_dot:
	cmpi.b	#$2e,(a2)+                      ; to the extension
	bne.s	check_type_dot
	moveq	#0,d1
	moveq	#0,d1
	movep.w	0(a2),d1                        ; its 1st and 3rd characters
	movep.w	1(a2),d0                        ; + its 2nd and a 0
	add.l	d0,d1
	moveq	#2,d0                           ; 3 of them
check_type_loop:
	cmp.w	(a0)+,d1                        ; this one?
	beq.s	check_type_program
	dbra	d0,check_type_loop
	bra.s	check_type_data
check_type_program:
	clr.w	data_flag                       ; a program
	bra.s	check_type_done
check_type_data:
	move.w	#$ffff,data_flag                ; data
check_type_done:
	rts

;------------------------------------------------------------------------------
; next_file: the next file of the folder (Fsnext, unless one was just found) into the names, skipping
; .POP files; no_more_files when there are none, and data_flag by its extension.
;------------------------------------------------------------------------------
next_file:	; from: pack_b2
	movem.l	d0-d7/a0-a6,-(sp)
next_file_loop:
	tst.w	file_found                      ; one found already?
	bne.s	next_file_name                  ; yes
	bsr.w	set_dta                         ; the DTA
	move.w	#$4f,-(sp)
	trap	#1                              ; Fsnext
	addq.l	#2,sp
	tst.w	d0                              ; another?
	bpl.s	next_file_name                  ; yes
	move.w	#$ffff,no_more_files            ; no more
	bra.s	next_file_done
next_file_name:
	lea	file_name(pc),a1                ; the name
	lea	saved_name(pc),a3
	movea.l	a1,a2
	movea.l	dta(pc),a0
	lea	$1e(a0),a0
next_file_copy:
	move.b	(a0),(a1)+
	move.b	(a0)+,(a3)+
	bne.s	next_file_copy
	lea	extension_codes(pc),a0
	movea.l	a0,a1
next_file_dot:
	cmpi.b	#$2e,(a2)+                      ; to the extension
	bne.s	next_file_dot
	moveq	#0,d0
	moveq	#0,d1
	movep.w	0(a2),d1
	movep.w	1(a2),d0
	add.w	d0,d1
	cmpi.l	#$9f50,d1                       ; POP?
	bne.s	next_file_type                  ; no
	clr.w	file_found                      ; yes: skipped
	bra.s	next_file_loop
next_file_type:
	moveq	#2,d0
next_file_type_loop:
	cmp.w	(a0)+,d1
	beq.s	next_file_program
	dbra	d0,next_file_type_loop
	bra.s	next_file_data
next_file_program:
	clr.w	data_flag                       ; a program
	bra.s	next_file_done
next_file_data:
	move.w	#$ffff,data_flag                ; data
next_file_done:
	clr.w	file_found                      ; not just found
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; set_path: Dsetpath to the path; d0 = 3 with an alert when it is not there.
;------------------------------------------------------------------------------
set_path:	; from: pack_b2
	pea	path(pc)                        ; the path
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.w	d0                              ; there?
	beq.s	set_path_done                   ; yes
	move.w	#$1,aes_int_in
	move.l	#alert_no_path,aes_addr_in      ; "Cannot find the correct PATH"
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	moveq	#3,d0                           ; 3
set_path_done:
	rts

;------------------------------------------------------------------------------
; percent_saved(d0 = packed, d2 = length): d0 = 100 less the packed length's percentage of the length.
;------------------------------------------------------------------------------
percent_saved:	; from: pack_file
	move.l	d2,-(sp)                        ; the length
	moveq	#100,d1                         ; * 100
	move.w	d0,d2                           ; the length * 100, in two halves
	move.w	d1,d3
	swap	d0
	swap	d1
	mulu.w	d2,d1
	mulu.w	d3,d0
	mulu.w	d3,d2
	add.w	d1,d0
	swap	d0
	clr.w	d0
	add.l	d2,d0
	move.l	(sp)+,d1                        ; the length
	bsr.s	divide                          ; divided
	moveq	#100,d1                         ; 100
	sub.l	d0,d1                           ; less it
	rts

;------------------------------------------------------------------------------
; divide: d0 = d0 / d1, longs.
;------------------------------------------------------------------------------
divide:	; from: percent_saved
	cmp.l	#$ffff,d1                       ; a word divisor?
	bls.s	divide_word                     ; yes
	cmp.l	d0,d1                           ; equal?
	beq.s	divide_equal                    ; yes: 1
	bls.s	divide_long                     ; smaller: worked out
	move.l	d0,d1                           ; larger: 0, the dividend the remainder
	moveq	#0,d0
	rts
divide_equal:
	moveq	#0,d1                           ; 1, no remainder
	moveq	#1,d0
	rts
divide_long:
	move.l	d1,d2                           ; an estimate from the divisor's upper word + 1
	clr.w	d2
	swap	d2
	addq.l	#1,d2
	move.l	d0,d3
	move.l	d1,d4
	move.l	d2,d1
	bsr.s	divide_word
	move.l	d4,d1
	divu.w	d2,d1
	divu.w	d1,d0
	andi.l	#$ffff,d0
divide_check:
	move.l	d4,d1                           ; then corrected by one each way
	move.l	d4,d2
	swap	d2
	mulu.w	d0,d1
	mulu.w	d0,d2
	swap	d2
	add.l	d2,d1
	sub.l	d3,d1                           ; the remainder
	bhi.s	divide_lower                    ; too large: one less
	neg.l	d1
	cmp.l	d1,d4                           ; within the divisor?
	bhi.s	divide_done                     ; yes: done
	addq.l	#1,d1                           ; no: one more
	bra.s	divide_check
divide_lower:
	subq.l	#1,d1
	bra.s	divide_check

;------------------------------------------------------------------------------
; divide_word: d0 = d0 / d1.w, a long quotient.
;------------------------------------------------------------------------------
divide_word:	; from: divide
	movem.w	d0/d2,-(sp)                     ; the upper word
	clr.w	d0
	swap	d0
	divu.w	d1,d0                           ; divided
	move.w	d0,d2
	move.w	(sp)+,d0                        ; then the lower with its remainder
	divu.w	d1,d0
	swap	d0
	moveq	#0,d1                           ; d1 = the remainder
	move.w	d0,d1
	move.w	d2,d0
	swap	d0                              ; d0 = the quotient
	move.w	(sp)+,d2
divide_done:	; from: divide
	rts

;------------------------------------------------------------------------------
; number_text(a0, a2): the value a0 as 6 decimal digits ending before a2 + 6, with leading 0s;
; number_text_width does it d7 digits wide.
;------------------------------------------------------------------------------
number_text:	; from: form_dial, pack_file, show_source, show_output, load_file
	moveq	#6,d7                           ; 6 digits

number_text_width:	; from: menu_stats, show_free_dfree, pack_file
	movem.l	d0-d7/a0-a3,-(sp)
	bsr.s	to_digits                       ; its digits
	lea	digits(pc),a0                   ; the digits
	move.w	digit_count(pc),d0
	beq.s	number_text_done                ; none
	adda.l	d7,a2                           ; past the end
	sub.w	d0,d7                           ; the 0s to put first
	subq.w	#1,d0
	moveq	#0,d1
number_text_loop:
	move.b	0(a0,d0.w),d1                   ; a digit
	addi.b	#$30,d1                         ; as a character
	move.b	d1,-(a2)                        ; stored, downwards
	dbra	d0,number_text_loop
	moveq	#48,d1                          ; '0'
	subq.w	#1,d7                           ; any to fill?
	ble.s	number_text_done
number_text_fill:
	move.b	d1,-(a2)
	dbra	d7,number_text_fill
number_text_done:
	movem.l	(sp)+,d0-d7/a0-a3
	rts
digit_count:	; from: to_digits, put_digit
	dc.w	$0000                           ; the digits found
digits:	; from: to_digits
	dc.w	$0000,$0000,$0000,$0000,$0000   ; to_digits's digits

;------------------------------------------------------------------------------
; to_digits(a0): the decimal digits of a0 into digits, without leading 0s.
;------------------------------------------------------------------------------
to_digits:	; from: number_text_width
	moveq	#0,d2                           ; no digits yet, leading 0s off
	move.l	d2,d3
	move.w	d2,digit_count
	move.l	d2,d1
	lea	digits(pc),a1
	move.l	d2,(a1)
	move.l	d2,4(a1)
	move.l	a0,d0
	cmpi.l	#$f4240,d0                      ; a million or more?
	blt.s	to_digits_low
to_digits_millions:
	subi.l	#$f4240,d0                      ; counted
	bmi.s	to_digits_high
	addq.w	#1,d1
	movea.l	d0,a0
	bra.s	to_digits_millions
to_digits_high:
	moveq	#0,d0                           ; the millions: 2 digits
	move.w	d1,d0
	divu.w	#$a,d0
	bsr.s	put_digit
	swap	d0
	bsr.s	put_digit
	move.l	a0,d0
to_digits_low:
	divu.w	#$2710,d0                       ; the rest below 10000 ...
	andi.l	#$ffff,d0
	divu.w	#$a,d0
	bsr.s	put_digit
	swap	d0
	andi.l	#$ffff,d0
	bsr.s	put_digit
	move.l	a0,d0                           ; the rest
	divu.w	#$2710,d0
	swap	d0
	andi.l	#$ffff,d0
	divu.w	#$3e8,d0
	bsr.s	put_digit
	swap	d0
	andi.l	#$ffff,d0
	divu.w	#$64,d0
	bsr.s	put_digit
	swap	d0
	andi.l	#$ffff,d0
	divu.w	#$a,d0
	bsr.s	put_digit
	swap	d0
	bsr.s	put_digit
	rts

;------------------------------------------------------------------------------
; put_digit(d0.b): a digit into digits, unless it is a leading 0.
;------------------------------------------------------------------------------
put_digit:	; from: to_digits
	move.b	d0,d0                           ; 0?
	beq.s	put_digit_zero
	moveq	#1,d2                           ; no: leading 0s over
	bra.s	put_digit_store
put_digit_zero:
	move.b	d2,d2                           ; a leading 0?
	beq.s	put_digit_done                  ; yes: not stored
put_digit_store:
	move.b	d0,(a1)+                        ; stored
	addq.w	#1,digit_count                  ; counted
put_digit_done:
	rts

;------------------------------------------------------------------------------
; show_source: the source position (a0 less the file's start) in its field.
;------------------------------------------------------------------------------
show_source:	; from: pack
	movem.l	a0-a6,-(sp)
	suba.l	load_address,a0
	movea.l	field_output_position(pc),a2
	bsr.w	number_text
	moveq	#37,d0
	bsr.w	draw_object
	movem.l	(sp)+,a0-a6
	rts

;------------------------------------------------------------------------------
; show_output: the output position (a2 less the work memory's start) in its field.
;------------------------------------------------------------------------------
show_output:	; from: pack
	movem.l	a0-a6,-(sp)
	movea.l	a2,a0
	suba.l	work_start,a0
	movea.l	field_source_position(pc),a2
	bsr.w	number_text
	moveq	#38,d0
	bsr.w	draw_object
	movem.l	(sp)+,a0-a6
	rts

;------------------------------------------------------------------------------
; load_file: load the file named into load_address; d6 = its length.  d0 = 3 when it ends 'POPI' already
; (not when depacking), -1 on an error; otherwise its names are shown and the output name is name.POP.
;------------------------------------------------------------------------------
load_file:	; from: form_dial, pack_file
	clr.w	-(sp)                           ; read only
	pea	file_name(pc)
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	tst.l	d0                              ; opened?
	bmi.w	load_file_done                  ; no
	move.w	d0,handle                       ; the handle
	move.l	load_address(pc),-(sp)
	move.l	#$ffffff,-(sp)
	move.w	handle(pc),-(sp)
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	lea	$c(sp),sp
	tst.l	d0                              ; read?
	bmi.w	load_file_done                  ; no
	move.l	d0,d6                           ; its length
	movea.l	load_address(pc),a0
	adda.l	d0,a0
	move.l	a0,pack_source
	move.w	handle(pc),-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	bmi.w	load_file_done
	cmp.l	offset,d6                       ; longer than the offset?
	ble.w	too_small                       ; no
	move.l	d6,file_length                  ; the length
	tst.w	depacking                       ; depacking?
	bne.s	load_file_names                 ; yes
	movea.l	load_address(pc),a0
	moveq	#0,d0
	moveq	#0,d1
	adda.l	d6,a0                           ; its end
	subq.l	#4,a0                           ; the last long
	movep.w	0(a0),d0
	movep.w	1(a0),d1
	add.l	d0,d1
	cmpi.w	#$9f99,d1                       ; 'POPI'?
	beq.s	load_file_packed
	subq.l	#4,a0
	movep.w	0(a0),d0
	movep.w	1(a0),d1
	add.l	d0,d1
	cmpi.w	#$9f99,d1
	beq.s	load_file_packed
load_file_names:
	lea	file_name(pc),a0                ; the name
	movea.l	field_name(pc),a1
load_file_copy:
	move.b	(a0)+,(a1)+
	bne.s	load_file_copy
	movea.l	field_length(pc),a2
	movea.l	file_length(pc),a0
	bsr.w	number_text
	moveq	#41,d0
	bsr.w	draw_object
	moveq	#39,d0
	bsr.w	draw_object                     ; drawn
	lea	file_name(pc),a0                ; the name
	lea	output_name(pc),a1              ; the output name
load_file_out:
	move.b	(a0)+,(a1)+                     ; up to the extension
	cmpi.b	#$2e,(a0)
	beq.s	load_file_ext
	cmpi.b	#$0,(a0)
	bne.s	load_file_out
load_file_ext:
	move.l	#$70702e6f,d0                   ; ".POP"
	movep.w	d0,0(a1)
	swap	d0
	movep.w	d0,1(a1)
	moveq	#0,d0                           ; 0
load_file_done:
	rts
load_file_packed:
	moveq	#3,d0                           ; 3: packed already
	rts
too_small:
	move.w	#$1,aes_int_in
	move.l	#alert_too_small,aes_addr_in    ; "The file is smaller than the offset!!"
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	bra.w	main_redraw
alert_too_small:
	dc.b	'[1][The file is smaller |than  the offset!!][ OKAY ]',0
	dc.b	$00

;------------------------------------------------------------------------------
; set_folder: Dsetpath to the path up to its '*'; d0 = 3 with an alert when it is not there.
;------------------------------------------------------------------------------
set_folder:	; from: object_state, form_dial, pack_go, pack_b2
	lea	path(pc),a0
set_folder_find:
	cmpi.b	#$2a,(a0)+
	bne.s	set_folder_find
	clr.b	-$1(a0)
	movea.l	a0,a4
	pea	path(pc)
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.w	d0
	beq.s	set_folder_done
	move.w	#$1,aes_int_in
	move.l	#alert_no_path,aes_addr_in      ; "Cannot find the correct PATH"
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	moveq	#3,d0                           ; 3
set_folder_done:
	move.b	#$2a,-$1(a4)                    ; the '*' back
	rts
alert_no_path:	; from: set_path
	dc.b	'[1][ Cannot find the correct PATH | Check the disc...][ HAR HAR ',']',0

;------------------------------------------------------------------------------
; set_drive: Dsetdrv to the path's drive.
;------------------------------------------------------------------------------
set_drive:	; from: object_state, form_dial, pack_go, pack_b2
	movem.l	d0-d7/a0-a6,-(sp)
	move.b	path(pc),d0
	subi.b	#$41,d0                         ; 0 for A
	ext.w	d0
	move.w	d0,-(sp)
	move.w	#$e,-(sp)
	trap	#1                              ; Dsetdrv
	addq.l	#4,sp
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; get_dta: Fgetdta into dta.
;------------------------------------------------------------------------------
get_dta:	; from: start, pack_go, pack_b2
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	#$2f,-(sp)
	trap	#1                              ; Fgetdta
	addq.l	#2,sp
	move.l	d0,dta                          ; kept
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; set_dta: Fsetdta(dta).
;------------------------------------------------------------------------------
set_dta:	; from: object_state, choose_file, pack_go, pack_b2, enter_folder, first_folder, 1 more
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	dta(pc),-(sp)
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.l	#6,sp
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; find_load_address: where to load a file: the work memory's end less its length (from the DTA) and $150, even.
;------------------------------------------------------------------------------
find_load_address:	; from: pack_file
	movea.l	work_end(pc),a1                 ; the work memory's end
	movea.l	dta(pc),a0
	suba.l	$1a(a0),a1                      ; less the file's length
	suba.l	#$150,a1                        ; less $150
	move.l	a1,d0
	andi.w	#$fffe,d0                       ; even
	movea.l	d0,a1
	move.l	d0,load_address                 ; where to load it
	rts
work_end:	; from: start, form_dial, clear_work
	dc.l	$00000000                       ; the work memory's end

;------------------------------------------------------------------------------
; show_time: the clock in the time field, hh mm ss.
;------------------------------------------------------------------------------
show_time:	; from: pack_file
	movem.l	d0-d6/a0-a6,-(sp)
	bsr.s	time_text
	moveq	#2,d0
	movea.l	field_time(pc),a0
	lea	time_buffer(pc),a1              ; "hh:mm:ss:"
show_time_loop:
	move.b	(a1)+,(a0)+                     ; two digits
	move.b	(a1)+,(a0)+                     ; 2 digits
	addq.l	#1,a1                           ; past the ':'
	dbra	d0,show_time_loop               ; for each pair
	moveq	#44,d0
	bsr.w	draw_object                     ; drawn
	movem.l	(sp)+,d0-d6/a0-a6               ; the registers back
	rts

;------------------------------------------------------------------------------
; time_text: "hh:mm:ss:" into time_buffer.
;------------------------------------------------------------------------------
time_text:	; from: show_time
	lea	time_buffer(pc),a3              ; the buffer
	moveq	#0,d1
	move.w	clock_hours(pc),d1
	bsr.s	two_digits
	moveq	#0,d1
	move.w	clock_minutes(pc),d1
	bsr.s	two_digits
	moveq	#0,d1
	move.w	clock_seconds(pc),d1

;------------------------------------------------------------------------------
; two_digits(d1): d1 as two digits and a ':'.
;------------------------------------------------------------------------------
two_digits:	; from: time_text
	divu.w	#$a,d1                          ; tens and units
	addi.b	#$30,d1                         ; the tens
	move.b	d1,(a3)+                        ; stored
	swap	d1                              ; the units
	addi.b	#$30,d1
	move.b	d1,(a3)+                        ; stored
	move.b	#$3a,(a3)+                      ; ':'
	rts

;------------------------------------------------------------------------------
; vbl_clock: the VBL routine that runs the clock: 50ths, seconds, minutes, hours.
;------------------------------------------------------------------------------
vbl_clock:	; from: start
	addq.w	#1,clock_ticks                  ; a 50th more
	cmpi.w	#$32,clock_ticks                ; a second?
	blt.s	vbl_clock_done
	clr.w	clock_ticks
	addq.w	#1,clock_seconds
	cmpi.w	#$3c,clock_seconds
	blt.s	vbl_clock_done
	clr.w	clock_seconds
	addq.w	#1,clock_minutes
	cmpi.w	#$3c,clock_minutes
	blt.s	vbl_clock_done
	clr.w	clock_minutes
	addq.w	#1,clock_hours
	cmpi.w	#$c,clock_hours
	blt.s	vbl_clock_done
	clr.w	clock_hours
vbl_clock_done:
	rts
clock_ticks:	; from: pack_go, pack_b2
	dc.w	$0000                           ; the clock: 50ths
clock_seconds:	; from: time_text
	dc.w	$0000
clock_minutes:	; from: pack_go, pack_b2, time_text
	dc.w	$0000
clock_hours:	; from: time_text
	dc.w	$0000
file_name:	; from: object_state, form_dial, pack_go, pack_b2, pack_file, clear_names, 3 more
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; the file's name
output_name:	; from: pack_file, clear_names, load_file
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; the name it is saved under (KEEP)
saved_name:	; from: object_state, form_dial, pack_b2, clear_names, next_file
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000
offset:	; from: pack_go, pack_b2, pack_file, load_file, pack, verify
	dc.l	$00000000                       ; bytes left unpacked at the start
no_more_files:	; from: pack_b2, next_folder, pack_file, next_file
	dc.w	$0000
file_found:	; from: pack_go, enter_folder, pack_file, next_file
	dc.w	$0000                           ; a file was just found (Fsfirst)
data_flag:	; from: start, pack_file, check_type, next_file
	dc.w	$0000                           ; 0 for a program
kill_flag:	; from: start, select_drive_path, pack_go, pack_b2, pack_file
	dc.w	$0000                           ; nonzero: over the original
disc_flag:	; from: select_drive_path, pack_go
	dc.w	$0000
file_flag:	; from: select_drive_path, pack_go, pack_file
	dc.w	$0000
time_buffer:	; from: show_time, time_text
	dc.w	$0000,$0000,$0000,$0000
handle:	; from: form_dial, grow, pack_file, write_block, load_file
	dc.w	$0000
alert_files:	; from: object_state
	dc.b	'[1][Choose wether you want to| REName or DELete a file.  |Or lea'
	dc.b	've.][ DEL | REN | Oops ]',0
alert_write_protected:	; from: write_protected
	dc.b	'[2][J.P.M 1990|Disc is WRITE protected!|  Please RECTIFY this.]['
	dc.b	' Retry | Cancel ]',0
alert_file_error:	; from: grow, write_block
	dc.b	'[2][FILE error,you just blew it!|   Wanna try again][ Yes | No ]',0
alert_create_error:	; from: write_block
	dc.b	'[1][ Open out error.|How did you manage that!][Dunno]',0
alert_disk_error:	; from: write_block
	dc.b	'[1][Disk error. That was| clumsy of you.][Aaargh]',0
alert_no_memory:	; from: write_block
	dc.b	'[1][Not enough memory for|file selector.][Drat]',0
alert_no_room:	; from: pack_file
	dc.b	'[1][Not enough room on the disc.|Gimme a blank or quit.][ JESUS '
	dc.b	'| RETRY ]',0
alert_insert_disc:	; from: utility_stub_bits
	dc.b	'[2][ Please insert a disc into| drive '
format_drive_letter:	; from: utility_stub_bits
	dc.b	'A.][ FORMAT | CANCEL ]',0
	dc.b	$00
extension_codes:	; from: check_type, next_file
	dc.w	$a247,$a353,$a850               ; PRG, TOS and TTP: 1st and 3rd characters + 2nd
text_all_files:	; from: enter_folder, first_folder
	dc.w	$2a2e
	dc.b	$2a
stub_relocation:	; from: pack_file
	dc.b	$00,$00,$00,$06                 ; written after a packed program: the first relocation, text+6 (the
                                                ;   stub's movea.l #0,a2)
	dc.b	$00

;------------------------------------------------------------------------------
; pack: the file at load_address to the work memory: first offset bytes as they are, then the codes, with
; the positions shown (unless their fields are selected) until done or Alt-Help.
;------------------------------------------------------------------------------
pack:	; from: pack_file
	movea.l	load_address(pc),a0             ; the source
	movea.l	pack_source(pc),a1
	movea.l	work_start(pc),a2
	move.l	offset(pc),d0
	beq.s	pack_start                      ; no
	subq.l	#1,d0
pack_copy:
	move.b	(a0)+,(a2)+                     ; copied as it is
	dbra	d0,pack_copy
pack_start:
	moveq	#1,d2                           ; the bit byte's marker
	moveq	#0,d1
pack_loop:
	tst.w	abort_flag                      ; Alt-Help?
	bne.s	pack_end                        ; yes
	subq.w	#1,d5
	beq.s	pack_step                       ; yes: not shown
	tst.w	hide_source                     ; the source position hidden?
	bne.s	pack_step                       ; yes
	bsr.w	show_source                     ; shown
pack_step:
	bsr.s	pack_code                       ; the next code
	tst.w	hide_output                     ; the output position hidden?
	bne.s	pack_check                      ; yes
	bsr.w	show_output                     ; shown
pack_check:
	cmpa.l	a0,a1                           ; all done?
	bgt.s	pack_loop                       ; no
	addq.w	#1,files_packed
pack_end:
	bsr.w	put_last                        ; the last bits
	move.l	a2,d0                           ; the output's end
	move.l	a2,packed_end                   ; kept
	sub.l	work_start,d0                   ; less the start
	move.l	d0,packed_length                ; the packed length
	movea.l	d0,a2
	bsr.w	verify
	rts

;------------------------------------------------------------------------------
; pack_code: the longest string ahead within the window (4 to 16 K) from a0, or a literal, as codes.
;------------------------------------------------------------------------------
pack_code:	; from: pack
	movea.l	a0,a3                           ; how far to look
pack_window:
	adda.l	#$7fff,a3                       ; the window, put in by the Compression button
	cmpa.l	a1,a3
	ble.s	pack_find
	movea.l	a1,a3
pack_find:
	move.l	pack_source(pc),d7
	sub.l	a0,d7
	moveq	#1,d5                           ; the best so far: 1
	movea.l	a0,a5                           ; from the next byte
	addq.w	#1,a5
pack_find_next:
	move.b	(a0),d3                         ; this byte
	move.b	1(a0),d4                        ; and the next
pack_find_first:
	cmp.b	(a5)+,d3                        ; the first byte?
	bne.s	pack_find_on                    ; no
	cmp.b	(a5),d4                         ; the second too?
	beq.s	pack_compare_start              ; yes
pack_find_on:
	cmpa.l	a5,a3                           ; up to the window
	bgt.s	pack_find_first
	bra.s	pack_choose                     ; none
pack_compare_start:
	subq.w	#1,a5                           ; back to the first byte
	movea.l	a0,a4                           ; from here
pack_compare:
	move.b	(a4)+,d3
	cmp.b	(a5)+,d3                        ; the same?
	bne.s	pack_compared                   ; no
	cmpa.l	a5,a3                           ; up to the window
	bgt.s	pack_compare
pack_compared:
	move.l	a4,d3                           ; the length
	sub.l	a0,d3
	subq.l	#1,d3
	cmp.l	d3,d5                           ; longer than the best?
	bge.s	pack_find_more                  ; no
	move.l	a5,d4                           ; yes: the offset
	sub.l	a0,d4                           ; the distance
	sub.l	d3,d4                           ; less the length
	subq.l	#1,d4                           ; less one
	move.l	d3,d5                           ; the best
	move.l	d4,match_offset                 ; its offset
pack_find_more:
	cmpa.l	a5,a3                           ; up to the window
	bgt.s	pack_find_next
pack_choose:
	cmpi.l	#$1,d5                          ; a literal?
	beq.s	pack_literal                    ; yes
	move.l	match_offset(pc),d3
	cmpi.w	#$1,d3                          ; 1?
	beq.w	pack_run                        ; offset 1: a run of the byte before
	cmp.l	d7,d5                           ; not past the end
	ble.s	pack_length                     ; yes
	move.l	d7,d5                           ; no: what is left
pack_length:
	cmpi.w	#$2,d5                          ; 2 bytes?
	beq.w	pack_two
	cmpi.w	#$3,d5                          ; 3?
	beq.w	pack_three
	cmpi.w	#$4,d5                          ; 4?
	beq.w	pack_four
	cmpi.w	#$5,d5                          ; 5?
	beq.w	pack_five
	move.l	match_offset(pc),d3
	bsr.w	put_offset                      ; put
	cmpi.w	#$100,d5                        ; 256 or more?
	blt.s	pack_long                       ; no
	move.w	#$ff,d5                         ; 255
pack_long:
	move.l	d5,d3                           ; the length
	subq.w	#1,d3                           ; less one
	bsr.w	put_length                      ; put
	adda.l	d5,a0                           ; past it
	bsr.w	put_zero                        ; a 0 bit
	bsr.w	put_zero                        ; a 0 bit
	bsr.w	put_one                         ; a 1 bit
	rts
pack_literal:	; from: put_zero
	moveq	#0,d3                           ; the byte
	move.b	(a0)+,d3                        ; the byte
	beq.s	pack_zero                       ; 0?
	cmp.b	(a0),d3                         ; the same as the next?
	beq.s	pack_pair                       ; the same again: a pair
	lea	single_bit_bytes(pc),a6         ; the single bit bytes
	moveq	#0,d0
pack_literal_bit:
	cmp.b	(a6)+,d3
	beq.s	pack_bit_byte                   ; yes
	addq.w	#1,d0
	cmpi.w	#$8,d0                          ; all 8?
	blt.s	pack_literal_bit                ; no
	move.b	d3,(a2)+                        ; no: stored as it is
	add.b	d2,d2                           ; a 0 bit: a literal
	bcc.s	pack_literal_done               ; not full yet
	move.b	d2,(a2)+                        ; the bit byte full: stored
	moveq	#1,d2                           ; a new one: the marker
pack_literal_done:
	rts
pack_bit_byte:
	move.w	d0,d3                           ; its number, 3 bits
	moveq	#2,d0                           ; 3 bits
	bsr.w	put_bits                        ; put
	move.b	#$e,d3                          ; the code
	moveq	#3,d0                           ; then the code 1110 (4 bits from the lowest)
	bsr.w	put_bits                        ; put
	rts
single_bit_bytes:
	dc.w	$0102,$0408,$1020,$4080         ; $01, $02, $04 ... $80
pack_zero:
	move.b	#$1b,d3                         ; the code 01100 for a 0 byte
	moveq	#4,d0                           ; 5 bits
	bsr.w	put_bits                        ; put
	rts
pack_pair:
	move.b	#$7f,d3                         ; the code 1111011 for a pair
	moveq	#6,d0
	bsr.w	put_bits
	rts
pack_two:
	move.l	match_offset(pc),d3             ; the offset
	cmpi.l	#$ff,d3                         ; up to 255?
	bgt.s	pack_literal                    ; no: a literal
	move.b	d3,(a2)+                        ; stored as it is
	bsr.s	put_one                         ; a 1 bit
	bsr.s	put_zero                        ; a 0 bit
	bsr.s	put_one                         ; a 1 bit
	addq.l	#2,a0                           ; past them
	rts
pack_three:
	move.l	match_offset(pc),d3             ; the offset
	cmpi.l	#$fff,d3
	bgt.s	pack_literal
	bsr.s	put_offset                      ; the offset
	bsr.s	put_zero
	bsr.s	put_one
	bsr.s	put_one                         ; the code 110 (with the bits put above)
	addq.l	#3,a0                           ; past them
	rts

;------------------------------------------------------------------------------
; put_one: a 1 bit.
;------------------------------------------------------------------------------
put_one:	; from: pack_code
	add.b	d2,d2                           ; the bit byte shifted
	bcc.s	put_one_kept                    ; not full
	bset	#$0,d2                          ; a 1 bit
	move.b	d2,(a2)+                        ; stored
	moveq	#1,d2                           ; a new one: the marker
	rts
put_one_kept:
	bset	#$0,d2                          ; a 1 bit
	rts

;------------------------------------------------------------------------------
; put_zero: a 0 bit.
;------------------------------------------------------------------------------
put_zero:	; from: pack_code
	add.b	d2,d2                           ; the bit byte shifted: a 0 bit
	bcc.s	put_zero_done                   ; not full
	move.b	d2,(a2)+                        ; stored
	moveq	#1,d2                           ; a new one: the marker
put_zero_done:
	rts
pack_four:	; from: pack_code
	move.l	match_offset(pc),d3             ; the offset
	cmpi.l	#$fff,d3
	bgt.w	pack_literal
	bsr.s	put_offset
	move.b	#$1f,d3
	moveq	#4,d0
	bsr.s	put_bits
	addq.l	#4,a0
	rts
pack_five:	; from: pack_code
	bsr.s	put_offset                      ; the offset
	move.b	#$1e,d3                         ; the code for 5 bytes
	moveq	#4,d0                           ; 5 bits
	bsr.s	put_bits                        ; put
	addq.l	#5,a0                           ; past them
	rts
pack_run:	; from: pack_code
	move.w	d5,d3                           ; the length
	subq.w	#1,d3                           ; less one, as the offset is put
	bsr.s	put_offset
	adda.l	d5,a0                           ; past them
	move.b	#$10,d3                         ; the code for a run of the byte before
	moveq	#4,d0                           ; 5 bits
	bsr.s	put_bits                        ; put
	rts
match_offset:	; from: pack_code
	dc.l	$00000000                       ; the best string's offset

;------------------------------------------------------------------------------
; put_bits(d3, d0): the low d0 + 1 bits of d3, lowest first; each full byte is stored.
;------------------------------------------------------------------------------
put_bits:	; from: pack_code, put_zero, put_offset, put_length
	lsr.w	#1,d3                           ; the lowest bit
	addx.b	d2,d2                           ; into the bit byte
	bcc.s	put_bits_next                   ; not full
	move.b	d2,(a2)+                        ; stored
	moveq	#1,d2                           ; a new one: the marker
put_bits_next:
	dbra	d0,put_bits
	rts

;------------------------------------------------------------------------------
; put_offset(d3): the offset in 4, 8, 12 or 16 bits, then its size in 2.
;------------------------------------------------------------------------------
put_offset:	; from: pack_code, put_zero
	movem.l	d3-d6,-(sp)
	cmpi.w	#$f,d3                          ; up to 15?
	bgt.s	put_offset_8                    ; no
	moveq	#3,d0                           ; 4 bits
	bsr.s	put_bits                        ; put
	moveq	#0,d3                           ; size 0
	bra.s	put_offset_size
put_offset_8:
	cmpi.w	#$ff,d3                         ; up to 255?
	bgt.s	put_offset_12                   ; no
	moveq	#7,d0                           ; 8 bits
	bsr.s	put_bits                        ; put
	moveq	#1,d3                           ; size 1
	bra.s	put_offset_size
put_offset_12:
	cmpi.w	#$fff,d3                        ; up to 4095?
	bgt.s	put_offset_16                   ; no
	moveq	#11,d0                          ; 12 bits
	bsr.s	put_bits                        ; put
	moveq	#2,d3                           ; size 2
	bra.s	put_offset_size
put_offset_16:
	moveq	#15,d0                          ; 16 bits
	bsr.s	put_bits                        ; put
	moveq	#3,d3                           ; size 3
put_offset_size:
	moveq	#1,d0                           ; the size: 2 bits
	bsr.s	put_bits                        ; put
	movem.l	(sp)+,d3-d6
	rts

;------------------------------------------------------------------------------
; put_length(d3): the length less one in 2, 4, 6 or 8 bits, then its size in 2.
;------------------------------------------------------------------------------
put_length:	; from: pack_code
	movem.l	d3-d6,-(sp)
	cmpi.w	#$3,d3                          ; up to 3?
	bgt.s	put_length_4                    ; no
	moveq	#1,d0                           ; 2 bits
	bsr.s	put_bits                        ; put
	moveq	#0,d3                           ; size 0
	bra.s	put_length_size
put_length_4:
	cmpi.w	#$f,d3                          ; up to 15?
	bgt.s	put_length_6                    ; no
	moveq	#3,d0                           ; 4 bits
	bsr.s	put_bits                        ; put
	moveq	#1,d3                           ; size 1
	bra.s	put_length_size
put_length_6:
	cmpi.w	#$3f,d3                         ; up to 63?
	bgt.s	put_length_8                    ; no
	moveq	#5,d0                           ; 6 bits
	bsr.s	put_bits                        ; put
	moveq	#2,d3                           ; size 2
	bra.s	put_length_size
put_length_8:
	moveq	#7,d0                           ; 8 bits
	bsr.s	put_bits                        ; put
	moveq	#3,d3                           ; size 3
put_length_size:
	moveq	#1,d0                           ; the size: 2 bits
	bsr.w	put_bits                        ; put
	movem.l	(sp)+,d3-d6
	rts

;------------------------------------------------------------------------------
; put_last: the last bit byte, and the output made even.
;------------------------------------------------------------------------------
put_last:	; from: pack
	move.b	d2,(a2)+                        ; the last bit byte
	move.l	a2,d0
	btst	#$0,d0                          ; odd?
	beq.s	put_last_done                   ; no
	clr.b	(a2)+                           ; yes: a 0 byte
put_last_done:
	rts

;------------------------------------------------------------------------------
; verify: run the depacker over the packed data without writing anything, to see whether the output would
; overrun the packed data (a collision); a bad file is counted in bad_count and flagged in bad_flag.
;------------------------------------------------------------------------------
verify:	; from: pack
	movem.l	d0-d7/a0-a6,-(sp)
	clr.w	bad_flag                        ; not bad yet
	movea.l	packed_end(pc),a0               ; the packed data's end
	movea.l	work_start(pc),a2               ; the work memory: where it would depack
	movea.l	a2,a4
	adda.l	offset(pc),a4                   ; + the offset
	adda.l	file_length,a2                  ; + the length: the output's end
	moveq	#0,d0
verify_skip_zeros:
	move.b	-(a0),d0                        ; the first byte of bits
	beq.s	verify_skip_zeros               ; 0: padding
verify_loop:
	moveq	#0,d2
	cmpa.l	a2,a0                           ; the output past the input?
	bgt.w	verify_bad                      ; yes: bad
	bsr.s	verify_bit                      ; a bit
	bcs.s	verify_code                     ; 1: a code
	move.b	-(a0),d2                        ; 0: a literal
verify_store:
	subq.l	#1,a2                           ; one byte down
	bra.s	verify_next
verify_short:
	moveq	#15,d4                          ; 110: a 0 byte, or a 3 byte string
	moveq	#2,d3                           ; 3 bytes
	bsr.s	verify_offset_d4                ; the offset, or all ones
	bne.s	verify_copy                     ; an offset: the string
	move.w	d4,d2                           ; all ones: a 0
	bra.s	verify_store
verify_code:
	bsr.s	verify_bit
	bcc.s	verify_string                   ; 10: a string
	bsr.s	verify_bit                      ; a bit
	bcc.s	verify_short                    ; 110
	bsr.s	verify_bit                      ; a bit
	bcs.s	verify_code_2                   ; 1111
	moveq	#2,d1                           ; 3 bits
	bsr.w	verify_bits                     ; 1110: a byte with one bit set
	exg	d1,d2                           ; the bit number
	addq.w	#1,d2
	bset	d1,d2                           ; that bit alone
	bra.s	verify_store
verify_code_2:
	bsr.s	verify_bit                      ; the next bit
	bcc.s	verify_string_5
	moveq	#15,d4                          ; 11110: a 4 byte string, or a pair
	move.w	#$3,d3                          ; 4 bytes
	bsr.s	verify_offset_d4                ; the offset, or all ones
	bne.s	verify_copy                     ; an offset: the string
	subq.l	#1,a2                           ; the byte before again
verify_next:
	cmpa.l	a2,a4                           ; all done?
	blt.s	verify_loop                     ; no
verify_done:	; from: verify_bits
	movem.l	(sp)+,d0-d7/a0-a6
	rts
verify_string_5:
	moveq	#4,d3                           ; 5 bytes
	bra.s	verify_string_offset            ; the offset
verify_string:
	bsr.s	verify_bit                      ; a bit
	bcs.s	verify_byte_run                 ; 101: a 2 byte string, 8 bit offset
	moveq	#1,d1                           ; 100: the length's size, 2 bits
verify_length_bits:
	lsr.b	#1,d0
	bne.s	verify_length_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
verify_length_bit_got:
	addx.w	d2,d2
	dbra	d1,verify_length_bits
	move.w	d2,d1                           ; the length
	beq.s	verify_string_2                 ; 0?
	addq.w	#1,d1                           ; + 1
	add.w	d1,d1                           ; * 2
	subq.w	#1,d1                           ; less one
	bsr.s	verify_bits                     ; 2, 4, 6 or 8 bits of length
	move.w	d2,d3                           ; the length less one
verify_string_offset:
	bsr.s	verify_offset                   ; then the offset
verify_copy:	; from: verify_bits
	movea.l	a2,a1                           ; from the offset
	adda.l	d2,a1                           ; back
verify_copy_loop:
	subq.l	#1,a2                           ; a byte down
	dbra	d3,verify_copy_loop             ; for each byte
	bra.s	verify_next                     ; the next

verify_bit:	; from: verify
	lsr.b	#1,d0                           ; the next bit
	bne.s	verify_bit_got                  ; the byte still has bits
	move.b	-(a0),d0                        ; no: the next byte down
	roxr.b	#1,d0                           ; its marker in, the first bit out
verify_bit_got:
	rts

verify_offset:	; from: verify, verify_bits
	moveq	#0,d4                           ; no all ones code

verify_offset_d4:	; from: verify
	moveq	#1,d1                           ; 2 bits: the size
	moveq	#0,d2
verify_offset_loop:
	lsr.b	#1,d0
	bne.s	verify_offset_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
verify_offset_bit_got:
	addx.w	d2,d2
	dbra	d1,verify_offset_loop
	move.w	d2,d1                           ; (code + 1) * 4 - 1: 3, 7, 11 or 15
	addq.w	#1,d1
	lsl.w	#2,d1
	subq.w	#1,d1                           ; bits less one
	eor.b	d1,d4                           ; all ones with d4 = 15?
	bne.s	verify_bits                     ; no: the offset
	rts
	moveq	#7,d1                           ; (not reached: 8 bits)

verify_bits:	; from: verify, verify_offset_d4
	moveq	#0,d2
verify_bits_loop:
	lsr.b	#1,d0
	bne.s	verify_bits_got
	move.b	-(a0),d0
	roxr.b	#1,d0
verify_bits_got:
	addx.w	d2,d2                           ; into d2
	dbra	d1,verify_bits_loop             ; for each bit
	rts
verify_string_2:	; from: verify
	bsr.s	verify_offset                   ; 1000: a run of the byte before, its length as an offset is
	move.w	d2,d3                           ; the length less one
	moveq	#1,d2                           ; offset 1: the byte before
	bra.s	verify_copy                     ; copied
verify_byte_run:	; from: verify
	moveq	#1,d3                           ; 101: 2 bytes
	move.b	-(a0),d2                        ; the 8 bit offset
	bra.s	verify_copy                     ; copied
verify_bad:	; from: verify
	move.w	#$ffff,bad_flag                 ; bad
	addq.w	#1,bad_count                    ; counted
	bra.w	verify_done

;------------------------------------------------------------------------------
; install_vbl(a3): put a3 in the first free VBL slot; a3 = the slot.
;------------------------------------------------------------------------------
install_vbl:	; from: start, pack_file
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	move.l	d0,-(sp)
	movea.l	$456.w,a0                       ; _vblqueue
	moveq	#7,d0                           ; 8 slots
install_vbl_find:
	tst.l	(a0)+
	beq.s	install_vbl_found
	dbra	d0,install_vbl_find
install_vbl_found:
	move.l	a3,-(a0)                        ; put in
	movea.l	a0,a3
	move.w	#$20,-(sp)                      ; Super(old stack)
	trap	#1                              ; Super
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; vbl_abort: the VBL routine that turns Alt-Help (_dumpflg) into abort_flag.
;------------------------------------------------------------------------------
vbl_abort:	; from: start
	movem.l	d0/a1,-(sp)
	movea.l	dumpflg_address(pc),a1
	tst.w	(a1)                            ; Alt-Help pressed?
	bne.s	vbl_abort_done                  ; no
	move.w	#$ffff,abort_flag               ; yes: abort
	move.w	#$ffff,(a1)                     ; and the screen dump off again
vbl_abort_done:
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, in service A cleared
	movem.l	(sp)+,d0/a1
	rts

;------------------------------------------------------------------------------
; vbl_drive_lights: the VBL routine that flashes the drive lights when packing is done: every 20 VBLs the
; PSG's port A is written one way or the other (the register selected last), unless a floppy is busy.
;------------------------------------------------------------------------------
vbl_drive_lights:	; from: pack_file
	tst.w	$43e.w                          ; flock, flock?
	beq.s	drive_lights_check              ; no
	rts                                     ; yes: left alone
drive_lights_check:
	tst.w	drive_lights_state              ; on?
	beq.s	drive_lights_off
	subq.w	#1,drive_lights_count           ; 20 VBLs gone?
	beq.s	drive_lights_turn_off
	rts
drive_lights_off:
	subq.w	#1,drive_lights_count
	beq.s	drive_lights_on
	rts
drive_lights_on:
	move.b	#$5,$ff8802                     ; PSG write data, lights on
	move.w	#$14,drive_lights_count         ; 20 VBLs
	move.w	#$1,drive_lights_state          ; now on
	rts
drive_lights_turn_off:
	move.b	#$2,$ff8802                     ; PSG write data, lights off
	move.w	#$14,drive_lights_count         ; 20 VBLs
	move.w	#$0,drive_lights_state          ; now off
	rts
drive_lights_count:
	dc.w	$0014                           ; VBLs left
drive_lights_state:
	dc.w	$0001
dumpflg_address:	; from: start, vbl_abort
	dc.l	$00000000
abort_flag:	; from: pack_file, pack, vbl_abort
	dc.w	$0000
vbl_slot_abort:	; from: start, form_dial
	dc.l	$00000000
vbl_slot_clock:	; from: start, form_dial
	dc.l	$00000000
vbl_slot_lights:	; from: menu_stats, form_dial, pack_go, pack_file, stop_drive_lights
	dc.l	$00000000                       ; the drive lights' VBL slot
packed_length:	; from: pack
	dc.l	$00000000

;------------------------------------------------------------------------------
; remove_vbl(a3): clear a VBL slot.
;------------------------------------------------------------------------------
remove_vbl:	; from: form_dial
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	move.l	d0,2(sp)                        ; the old stack, as the argument
	clr.l	(a3)                            ; cleared
	trap	#1                              ; GEMDOS, Super(old stack)
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; stop_drive_lights: the drive lights' VBL routine removed and the lights off.
;------------------------------------------------------------------------------
stop_drive_lights:	; from: menu_stats, form_dial, pack_go
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	move.l	d0,2(sp)                        ; the old stack, as the argument
	movea.l	vbl_slot_lights,a3              ; its slot
	clr.l	(a3)                            ; cleared
	move.b	#$2,$ff8802                     ; PSG write data, the PSG written: lights off
	move.b	#$6,$ff8802                     ; PSG write data
	trap	#1                              ; GEMDOS, Super(old stack)
	addq.l	#6,sp
	rts
	movea.l	work_start(pc),a2               ; not used: the stub's depacker run in the program
	movea.l	packed_end(pc),a4
	lea	$c(a4),a4
	bra.s	stub_depack

;------------------------------------------------------------------------------
; The normal stub put in front of a packed program, $1c4 bytes: its first word, bra.s over the stub's header,
; is also the PRG magic $601a.  It depacks the program over its packed data (a4 is taken as the end of the
; data), flashing the background, relocates it, sets the basepage, and runs a mover from below the stack
; that copies it down, clears from its BSS to the end and starts it.
;------------------------------------------------------------------------------
stub:	; from: pack_file
	bra.s	stub_start
stub_text_length:	; from: pack_file
	dc.l	$00000000                       ; the stub's code
stub_data_length:	; from: pack_file
	dc.l	$00000000                       ; the packed data
stub_bss_length:	; from: pack_file
	dc.l	$00000000                       ; room to depack
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000
stub_start:
	movea.l	4(sp),a5                        ; the basepage
	movea.l	#$0,a2                          ; the packed data: text + $1a8 once relocated (the one relocation)
	adda.l	#$1a8,a2
stub_depack:	; from: stop_drive_lights
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	move.l	d0,2(sp)                        ; the old stack, as the argument
	movea.l	a4,a0                           ; the packed data's end
	movea.l	a2,a3                           ; a3 = its start: where it depacks to
	subq.l	#4,a0
	adda.l	-(a0),a2                        ; + the unpacked length: a2 = the output's end
	movea.l	a2,a4                           ; a4 = it, for the BSS clearing
	subq.l	#4,a0                           ; past the packed length
	movea.l	#$ff8240,a6                     ; palette 0
	move.w	(a6),d5                         ; the background colour
stub_skip_zeros:
	move.b	-(a0),d0                        ; the first byte of bits
	beq.s	stub_skip_zeros                 ; 0: padding
stub_loop:
	moveq	#0,d2
	bsr.w	stub_bit                        ; a bit
	bcs.s	stub_code                       ; 1: a code
	move.b	-(a0),d2                        ; 0: a literal
stub_store:
	move.b	d2,-(a2)                        ; stored, downwards
	bra.s	stub_next
stub_short:
	moveq	#15,d4
	moveq	#2,d3
	bsr.s	stub_offset_d4
	bne.s	stub_copy
	move.w	d4,d2
	bra.s	stub_store
stub_code:
	bsr.s	stub_bit                        ; a bit
	bcc.s	stub_string
	bsr.s	stub_bit                        ; a bit
	bcc.s	stub_short
	bsr.s	stub_bit                        ; a bit
	bcs.s	stub_code_2
	moveq	#2,d1                           ; 3 bits
	bsr.w	stub_bits
	exg	d1,d2
	addq.w	#1,d2
	bset	d1,d2
	bra.s	stub_store
stub_code_2:
	bsr.s	stub_bit                        ; a bit
	bcc.s	stub_string_5
	moveq	#15,d4
	move.w	#$3,d3
	bsr.s	stub_offset_d4
	bne.s	stub_copy
	move.b	(a2),-(a2)                      ; the byte before again
stub_next:
	neg.w	(a6)                            ; the background flashed
	move.w	d5,(a6)                         ; and back
	cmpa.l	a2,a3                           ; all done?
	blt.s	stub_loop                       ; no
	jmp	stub_relocate(pc)
stub_string_5:
	moveq	#4,d3                           ; 5 bytes
	bra.s	stub_string_offset
stub_string:
	bsr.s	stub_bit                        ; a bit
	bcs.s	stub_byte_run
	moveq	#1,d1
stub_length_bits:
	lsr.b	#1,d0
	bne.s	stub_length_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
stub_length_bit_got:
	addx.w	d2,d2
	dbra	d1,stub_length_bits
	move.w	d2,d1                           ; the length
	beq.s	stub_string_2                   ; 0?
	addq.w	#1,d1
	add.w	d1,d1                           ; * 2
	subq.w	#1,d1                           ; less one
	bsr.s	stub_bits                       ; bits
	move.w	d2,d3                           ; the count
stub_string_offset:
	bsr.s	stub_offset                     ; the offset
stub_copy:	; from: stub_bits
	movea.l	a2,a1                           ; from the offset
	adda.l	d2,a1                           ; back
stub_copy_loop:
	move.b	-(a1),-(a2)                     ; copied, downwards
	dbra	d3,stub_copy_loop
	bra.s	stub_next

;------------------------------------------------------------------------------
; The stub's copies of depack_bit, depack_offset and depack_bits.
;------------------------------------------------------------------------------
stub_bit:	; from: stub
	lsr.b	#1,d0
	bne.s	stub_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
stub_bit_got:
	rts

stub_offset:	; from: stub, stub_bits
	moveq	#0,d4

stub_offset_d4:	; from: stub
	moveq	#1,d1
	moveq	#0,d2
stub_offset_loop:
	lsr.b	#1,d0
	bne.s	stub_offset_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
stub_offset_bit_got:
	addx.w	d2,d2
	dbra	d1,stub_offset_loop
	move.w	d2,d1
	addq.w	#1,d1
	lsl.w	#2,d1
	subq.w	#1,d1
	eor.b	d1,d4
	bne.s	stub_bits
	rts
	moveq	#7,d1

stub_bits:	; from: stub, stub_offset_d4
	moveq	#0,d2
stub_bits_loop:
	lsr.b	#1,d0
	bne.s	stub_bits_got
	move.b	-(a0),d0
	roxr.b	#1,d0
stub_bits_got:
	addx.w	d2,d2
	dbra	d1,stub_bits_loop
	rts
stub_string_2:	; from: stub
	bsr.s	stub_offset
	move.w	d2,d3
	moveq	#1,d2
	bra.s	stub_copy
stub_byte_run:	; from: stub
	moveq	#1,d3
	move.b	-(a0),d2
	bra.s	stub_copy
stub_relocate:	; from: stub
	move.w	d5,(a6)                         ; the colour back
	trap	#1                              ; GEMDOS, Super(old stack)
	addq.l	#6,sp
	movea.l	2(a3),a0                        ; the depacked program's header: text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	lea	$1c(a0),a0
	adda.l	a3,a0
	move.l	8(a5),d0
	lea	$1c(a3),a3
	movea.l	a3,a6
	tst.l	(a0)
	beq.s	stub_basepage
	adda.l	(a0)+,a3
	moveq	#0,d1
stub_relocate_long:
	add.l	d0,(a3)
stub_relocate_next:
	move.b	(a0)+,d1
	beq.s	stub_basepage
	cmp.b	#$1,d1
	bne.s	stub_relocate_step
	lea	$fe(a3),a3
	bra.s	stub_relocate_next
stub_relocate_step:
	adda.l	d1,a3
	bra.s	stub_relocate_long
stub_basepage:
	addq.l	#2,a2
	move.l	(a2),$c(a5)
	add.l	(a2),d0
	move.l	d0,$10(a5)
	move.l	4(a2),$14(a5)
	add.l	4(a2),d0
	move.l	d0,$18(a5)
	move.l	8(a2),$1c(a5)
	movea.l	sp,a0
	lea	-$100(a0),a0
	move.l	a0,-(sp)
	lea	stub_mover(pc),a1
	move.l	#$29,d0
stub_copy_mover:
	move.b	(a1)+,(a0)+
	dbra	d0,stub_copy_mover
	rts
stub_mover:
	move.l	$c(a5),d0
	add.l	$14(a5),d0
	lsr.l	#2,d0
	addq.l	#2,d0
	lea	$100(a5),a5
	movea.l	a5,a3
stub_mover_copy:
	move.l	(a6)+,(a5)+
	subq.l	#1,d0
	bne.s	stub_mover_copy
	movea.l	4(sp),a5
	movea.l	$18(a5),a0
stub_mover_clear:
	move.l	d0,(a0)+
	cmpa.l	a4,a0
	blt.s	stub_mover_clear
	jmp	(a3)

;------------------------------------------------------------------------------
; The printed stub: the normal stub with "POMPEY PACKER V1.9" printed first, its column moved out of low
; resolution.
;------------------------------------------------------------------------------
printed_stub:	; from: pack_file
	bra.s	printed_stub_start
printed_stub_text_length:	; from: pack_file
	dc.l	$00000000                       ; its code
printed_stub_data_length:	; from: pack_file
	dc.l	$00000000                       ; the packed data
printed_stub_bss_length:	; from: pack_file
	dc.l	$00000000                       ; room to depack
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000
printed_stub_start:
	movea.l	4(sp),a5                        ; the basepage
	movea.l	#$0,a2                          ; the stub's text, once relocated (the one relocation)
	adda.l	#$1e0,a2                        ; + $1e0: the packed data
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	tst.w	d0
	beq.s	printed_stub_print
	lea	printed_stub_column(pc),a0      ; the column
	addi.b	#$14,(a0)                       ; + 20
printed_stub_print:
	bsr.s	printed_stub_print_it           ; the text's address as the return address
printed_stub_text:
	dc.w	$1b45,$1b66,$1b59               ; ESC f, ESC Y and the place, then the title
	dc.b	$20
printed_stub_column:
	dc.b	'*POMPEY PACKER V1.9',0
	dc.b	$00

printed_stub_print_it:	; from: printed_stub
	move.w	#$9,-(sp)                       ; Cconws the text
	trap	#1                              ; Cconws
	addq.l	#8,sp                           ; its address and the function dropped
printed_stub_depack:
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	move.l	d0,2(sp)                        ; the old stack, as the argument
	movea.l	a4,a0                           ; the packed data's end
	movea.l	a2,a3                           ; a3 = its start: where it depacks to
	subq.l	#4,a0
	adda.l	-(a0),a2                        ; + the unpacked length: a2 = the output's end
	movea.l	a2,a4                           ; a4 = it, for the BSS clearing
	subq.l	#4,a0                           ; past the packed length
	movea.l	#$ff8240,a6                     ; palette 0
	move.w	(a6),d5                         ; the background colour
printed_stub_skip_zeros:
	move.b	-(a0),d0                        ; the first byte of bits
	beq.s	printed_stub_skip_zeros         ; 0: padding
printed_stub_loop:
	moveq	#0,d2
	bsr.w	printed_stub_bit                ; a bit
	bcs.s	printed_stub_code               ; 1: a code
	move.b	-(a0),d2                        ; 0: a literal
printed_stub_store:
	move.b	d2,-(a2)                        ; stored, downwards
	bra.s	printed_stub_next
printed_stub_short:
	moveq	#15,d4
	moveq	#2,d3
	bsr.s	printed_stub_offset_d4
	bne.s	printed_stub_copy
	move.w	d4,d2
	bra.s	printed_stub_store
printed_stub_code:
	bsr.s	printed_stub_bit                ; a bit
	bcc.s	printed_stub_string
	bsr.s	printed_stub_bit                ; a bit
	bcc.s	printed_stub_short
	bsr.s	printed_stub_bit                ; a bit
	bcs.s	printed_stub_code_2
	moveq	#2,d1                           ; 3 bits
	bsr.w	printed_stub_bits
	exg	d1,d2
	addq.w	#1,d2
	bset	d1,d2
	bra.s	printed_stub_store
printed_stub_code_2:
	bsr.s	printed_stub_bit                ; a bit
	bcc.s	printed_stub_string_5
	moveq	#15,d4
	move.w	#$3,d3
	bsr.s	printed_stub_offset_d4
	bne.s	printed_stub_copy
	move.b	(a2),-(a2)                      ; the byte before again
printed_stub_next:
	neg.w	(a6)                            ; the background flashed
	move.w	d5,(a6)                         ; and back
	cmpa.l	a2,a3                           ; all done?
	blt.s	printed_stub_loop               ; no
	jmp	printed_stub_relocate(pc)
printed_stub_string_5:
	moveq	#4,d3                           ; 5 bytes
	bra.s	printed_stub_string_offset
printed_stub_string:
	bsr.s	printed_stub_bit                ; a bit
	bcs.s	printed_stub_byte_run
	moveq	#1,d1
printed_stub_length_bits:
	lsr.b	#1,d0
	bne.s	printed_stub_length_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
printed_stub_length_bit_got:
	addx.w	d2,d2
	dbra	d1,printed_stub_length_bits
	move.w	d2,d1                           ; the length
	beq.s	printed_stub_string_2           ; 0?
	addq.w	#1,d1
	add.w	d1,d1                           ; * 2
	subq.w	#1,d1                           ; less one
	bsr.s	printed_stub_bits               ; bits
	move.w	d2,d3                           ; the count
printed_stub_string_offset:
	bsr.s	printed_stub_offset             ; the offset
printed_stub_copy:	; from: printed_stub_bits
	movea.l	a2,a1                           ; from the offset
	adda.l	d2,a1                           ; back
printed_stub_copy_loop:
	move.b	-(a1),-(a2)                     ; copied, downwards
	dbra	d3,printed_stub_copy_loop
	bra.s	printed_stub_next

printed_stub_bit:	; from: printed_stub_print_it
	lsr.b	#1,d0
	bne.s	printed_stub_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
printed_stub_bit_got:
	rts

printed_stub_offset:	; from: printed_stub_print_it, printed_stub_bits
	moveq	#0,d4

printed_stub_offset_d4:	; from: printed_stub_print_it
	moveq	#1,d1
	moveq	#0,d2
printed_stub_offset_loop:
	lsr.b	#1,d0
	bne.s	printed_stub_offset_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
printed_stub_offset_bit_got:
	addx.w	d2,d2
	dbra	d1,printed_stub_offset_loop
	move.w	d2,d1
	addq.w	#1,d1
	lsl.w	#2,d1
	subq.w	#1,d1
	eor.b	d1,d4
	bne.s	printed_stub_bits
	rts
	moveq	#7,d1

printed_stub_bits:	; from: printed_stub_print_it, printed_stub_offset_d4
	moveq	#0,d2
printed_stub_bits_loop:
	lsr.b	#1,d0
	bne.s	printed_stub_bits_got
	move.b	-(a0),d0
	roxr.b	#1,d0
printed_stub_bits_got:
	addx.w	d2,d2
	dbra	d1,printed_stub_bits_loop
	rts
printed_stub_string_2:	; from: printed_stub_print_it
	bsr.s	printed_stub_offset
	move.w	d2,d3
	moveq	#1,d2
	bra.s	printed_stub_copy
printed_stub_byte_run:	; from: printed_stub_print_it
	moveq	#1,d3
	move.b	-(a0),d2
	bra.s	printed_stub_copy
printed_stub_relocate:	; from: printed_stub_print_it
	move.w	d5,(a6)                         ; the colour back
	trap	#1                              ; GEMDOS, GEMDOS, Super(old stack)
	addq.l	#6,sp
	movea.l	2(a3),a0                        ; the depacked program's header: text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	lea	$1c(a0),a0
	adda.l	a3,a0
	move.l	8(a5),d0
	lea	$1c(a3),a3
	movea.l	a3,a6
	tst.l	(a0)
	beq.s	printed_stub_basepage
	adda.l	(a0)+,a3
	moveq	#0,d1
printed_stub_relocate_long:
	add.l	d0,(a3)
printed_stub_relocate_next:
	move.b	(a0)+,d1
	beq.s	printed_stub_basepage
	cmp.b	#$1,d1
	bne.s	printed_stub_relocate_step
	lea	$fe(a3),a3
	bra.s	printed_stub_relocate_next
printed_stub_relocate_step:
	adda.l	d1,a3
	bra.s	printed_stub_relocate_long
printed_stub_basepage:
	addq.l	#2,a2
	move.l	(a2),$c(a5)
	add.l	(a2),d0
	move.l	d0,$10(a5)
	move.l	4(a2),$14(a5)
	add.l	4(a2),d0
	move.l	d0,$18(a5)
	move.l	8(a2),$1c(a5)
	movea.l	sp,a0
	lea	-$100(a0),a0
	move.l	a0,-(sp)
	lea	printed_stub_mover(pc),a1
	move.l	#$29,d0
printed_stub_copy_mover:
	move.b	(a1)+,(a0)+
	dbra	d0,printed_stub_copy_mover
	rts
printed_stub_mover:
	move.l	$c(a5),d0
	add.l	$14(a5),d0
	lsr.l	#2,d0
	addq.l	#2,d0
	lea	$100(a5),a5
	movea.l	a5,a3
printed_stub_mover_copy:
	move.l	(a6)+,(a5)+
	subq.l	#1,d0
	bne.s	printed_stub_mover_copy
	movea.l	4(sp),a5
	movea.l	$18(a5),a0
printed_stub_mover_clear:
	move.l	d0,(a0)+
	cmpa.l	a4,a0
	blt.s	printed_stub_mover_clear
	jmp	(a3)

;------------------------------------------------------------------------------
; The utility stub: the normal stub that, after depacking, offers to save the program unpacked instead of
; running it.
;------------------------------------------------------------------------------
utility_stub:	; from: pack_file
	bra.s	utility_stub_start
utility_stub_text_length:	; from: pack_file
	dc.l	$00000000                       ; its code
utility_stub_data_length:	; from: pack_file
	dc.l	$00000000                       ; the packed data
utility_stub_bss_length:	; from: pack_file
	dc.l	$00000000                       ; room to depack
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000
utility_stub_start:
	movea.l	4(sp),a5                        ; the basepage
	movea.l	#$0,a2                          ; the stub's text, once relocated (not used: the data is found
                                                ;   pc-relative below)
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp
	tst.w	d0                              ; low?
	beq.s	utility_stub_hide_mouse         ; yes
	moveq	#20,d0                          ; no: every text's column 20 further
	add.b	d0,utility_stub_title
	add.b	d0,utility_stub_ask
	add.b	d0,utility_stub_ask_2
	add.b	d0,utility_stub_enter_text
	add.b	d0,utility_stub_name_line
	add.b	d0,utility_stub_bell
	add.b	d0,utility_stub_saving_text
utility_stub_hide_mouse:
	dc.w	$a00a                           ; Line-A $a, hide mouse
utility_stub_depack:
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	move.l	d0,2(sp)                        ; the old stack, as the argument
	btst	#$3,$4c4.w                      ; bit 3 of $4c4 (in _drvbits) set?
	bne.s	utility_stub_go                 ; yes: no question
	pea	utility_stub_clear(pc)          ; "Do you wish to save program in unpacked format?"
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	move.w	#$8,-(sp)
	trap	#1                              ; Cnecin
	addq.l	#8,sp
	andi.b	#$df,d0                         ; in capitals
	cmp.b	#$79,d0                         ; 'Y'? (as 'y' less $20 this never matches)
	bne.s	utility_stub_go                 ; no
	pea	utility_stub_enter(pc)          ; "Enter filename to save as:"
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	pea	utility_stub_name_end(pc)       ; the line buffer
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	lea	$c(sp),sp
utility_stub_go:
	pea	utility_stub_text(pc)           ; the title
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	lea	utility_stub+$408(pc),a2        ; the packed data, after the stub
	bsr.w	utility_stub_depack_data        ; depack
	trap	#1                              ; GEMDOS, Super(old stack)
	addq.l	#6,sp
	lea	utility_stub_name_end(pc),a0    ; the name typed
	tst.b	2(a0)                           ; any?
	beq.s	utility_stub_relocate           ; no: run it
	pea	utility_stub_saving(pc)         ; "Saving unpacked program..."
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	clr.w	-(sp)                           ; normal file
	pea	utility_stub_name(pc)           ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	lea	$e(sp),sp
	tst.l	d0                              ; created?
	bmi.w	utility_stub_error              ; no
	pea	utility_stub+$408(pc)           ; the depacked file
	move.l	a4,d5                           ; its end
	sub.l	a3,d5                           ; less its start: its length
	move.l	d5,-(sp)
	move.w	d0,-(sp)                        ; the handle
	move.w	d0,d7                           ; kept
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	tst.l	d0                              ; written?
	bmi.w	utility_stub_error              ; no
	move.w	d7,-(sp)                        ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.l	d0                              ; closed?
	bmi.w	utility_stub_error              ; no
	lea	utility_stub+$408(pc),a2        ; the depacked file again
utility_stub_relocate:
	movea.l	2(a3),a0                        ; the header: text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	lea	$1c(a0),a0                      ; + the header
	adda.l	a3,a0                           ; a0 = its relocation table
	move.l	8(a5),d0                        ; the text segment: where it runs
	lea	$1c(a3),a3                      ; its text
	movea.l	a3,a6
	tst.l	(a0)                            ; any relocation?
	beq.s	utility_stub_basepage           ; no
	adda.l	(a0)+,a3                        ; the first address
utility_stub_relocate_long:
	add.l	d0,(a3)                         ; relocated
	moveq	#0,d1
utility_stub_relocate_next:
	move.b	(a0)+,d1                        ; the next step
	beq.s	utility_stub_basepage           ; the end?
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	utility_stub_relocate_step      ; no
	lea	$fe(a3),a3                      ; yes
	bra.s	utility_stub_relocate_next
utility_stub_relocate_step:
	adda.l	d1,a3                           ; on to the next long
	bra.s	utility_stub_relocate_long
utility_stub_basepage:
	addq.l	#2,a2                           ; the header's lengths
	move.l	(a2),$c(a5)
	add.l	(a2),d0
	move.l	d0,$10(a5)
	move.l	4(a2),$14(a5)
	add.l	4(a2),d0
	move.l	d0,$18(a5)
	move.l	8(a2),$1c(a5)
	movea.l	sp,a0                           ; the stack
	lea	-$100(a0),a0                    ; less $100: where the mover goes
	move.l	a0,-(sp)                        ; its address, for the rts
	lea	utility_stub_mover(pc),a1       ; the mover
	move.l	#$2a,d0                         ; 44 bytes
	lsr.l	#1,d0                           ; in words
utility_stub_copy_mover:
	move.w	(a1)+,(a0)+                     ; copied
	dbra	d0,utility_stub_copy_mover
	rts                                     ; run it
utility_stub_mover:
	move.l	$c(a5),d0
	add.l	$14(a5),d0
	lsr.l	#2,d0
	addq.l	#2,d0
	lea	$100(a5),a5
	movea.l	a5,a3
utility_stub_mover_copy:
	move.l	(a6)+,(a5)+                     ; copied down
	subq.l	#1,d0
	bne.s	utility_stub_mover_copy
	movea.l	4(sp),a5
	movea.l	$18(a5),a0
utility_stub_mover_clear:
	move.l	d0,(a0)+                        ; cleared
	cmpa.l	a4,a0                           ; up to the depacked data's end
	blt.s	utility_stub_mover_clear
	dc.w	$a009                           ; Line-A $9
	jmp	(a3)                            ; start the program

;------------------------------------------------------------------------------
; The utility stub's depacker: the normal stub's, as a subroutine.
;------------------------------------------------------------------------------
utility_stub_depack_data:	; from: utility_stub
	movea.l	a4,a0                           ; the packed data's end
	movea.l	a2,a3                           ; a3 = its start: where it depacks to
	subq.l	#4,a0
	adda.l	-(a0),a2                        ; + the unpacked length: a2 = the output's end
	movea.l	a2,a4                           ; a4 = it, for the BSS clearing
	subq.l	#4,a0                           ; past the packed length
	movea.l	#$ff8240,a6                     ; palette 0
	move.w	(a6),d5                         ; the background colour
utility_stub_skip_zeros:
	move.b	-(a0),d0                        ; the first byte of bits
	beq.s	utility_stub_skip_zeros         ; 0: padding
utility_stub_loop:
	moveq	#0,d2
	bsr.s	utility_stub_bit
	bcs.s	utility_stub_code               ; 1: a code
	move.b	-(a0),d2                        ; 0: a literal
utility_stub_store:
	move.b	d2,-(a2)                        ; stored, downwards
	bra.s	utility_stub_next
utility_stub_short:
	moveq	#15,d4
	moveq	#2,d3
	bsr.s	utility_stub_offset_d4
	bne.s	utility_stub_copy
	move.w	d4,d2
	bra.s	utility_stub_store
utility_stub_code:
	bsr.s	utility_stub_bit                ; a bit
	bcc.s	utility_stub_string
	bsr.s	utility_stub_bit                ; a bit
	bcc.s	utility_stub_short
	bsr.s	utility_stub_bit                ; a bit
	bcs.s	utility_stub_code_2
	moveq	#2,d1                           ; 3 bits
	bsr.w	utility_stub_bits
	exg	d1,d2
	addq.w	#1,d2
	bset	d1,d2
	bra.s	utility_stub_store
utility_stub_code_2:
	bsr.s	utility_stub_bit                ; a bit
	bcc.s	utility_stub_string_5
	moveq	#15,d4
	move.w	#$3,d3
	bsr.s	utility_stub_offset_d4
	bne.s	utility_stub_copy
	move.b	(a2),-(a2)                      ; the byte before again
utility_stub_next:
	neg.w	(a6)                            ; the background flashed
	move.w	d5,(a6)                         ; and back
	cmpa.l	a2,a3                           ; all done?
	blt.s	utility_stub_loop               ; no
	rts
utility_stub_string_5:
	moveq	#4,d3                           ; 5 bytes
	bra.s	utility_stub_string_offset
utility_stub_string:
	bsr.s	utility_stub_bit                ; a bit
	bcs.s	utility_stub_byte_run
	moveq	#1,d1
utility_stub_length_bits:
	lsr.b	#1,d0
	bne.s	utility_stub_length_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
utility_stub_length_bit_got:
	addx.w	d2,d2
	dbra	d1,utility_stub_length_bits
	move.w	d2,d1                           ; the length
	beq.s	utility_stub_string_2           ; 0?
	addq.w	#1,d1
	add.w	d1,d1                           ; * 2
	subq.w	#1,d1                           ; less one
	bsr.s	utility_stub_bits               ; bits
	move.w	d2,d3                           ; the count
utility_stub_string_offset:
	bsr.s	utility_stub_offset             ; the offset
utility_stub_copy:	; from: utility_stub_bits
	movea.l	a2,a1                           ; from the offset
	adda.l	d2,a1                           ; back
utility_stub_copy_loop:
	move.b	-(a1),-(a2)                     ; copied, downwards
	dbra	d3,utility_stub_copy_loop
	bra.s	utility_stub_next

utility_stub_bit:	; from: utility_stub_depack_data
	lsr.b	#1,d0
	bne.s	utility_stub_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
utility_stub_bit_got:
	rts

utility_stub_offset:	; from: utility_stub_depack_data, utility_stub_bits
	moveq	#0,d4

utility_stub_offset_d4:	; from: utility_stub_depack_data
	moveq	#1,d1
	moveq	#0,d2
utility_stub_offset_loop:
	lsr.b	#1,d0
	bne.s	utility_stub_offset_bit_got
	move.b	-(a0),d0
	roxr.b	#1,d0
utility_stub_offset_bit_got:
	addx.w	d2,d2
	dbra	d1,utility_stub_offset_loop
	move.w	d2,d1
	addq.w	#1,d1
	lsl.w	#2,d1
	subq.w	#1,d1
	eor.b	d1,d4
	bne.s	utility_stub_bits
	rts
	moveq	#7,d1

utility_stub_bits:	; from: utility_stub_depack_data, utility_stub_offset_d4
	moveq	#0,d2
utility_stub_bits_loop:
	lsr.b	#1,d0
	bne.s	utility_stub_bits_got
	move.b	-(a0),d0
	roxr.b	#1,d0
utility_stub_bits_got:
	addx.w	d2,d2
	dbra	d1,utility_stub_bits_loop
	rts
utility_stub_string_2:	; from: utility_stub_depack_data
	bsr.s	utility_stub_offset
	move.w	d2,d3
	moveq	#1,d2
	bra.s	utility_stub_copy
utility_stub_byte_run:	; from: utility_stub_depack_data
	moveq	#1,d3
	move.b	-(a0),d2
	bra.s	utility_stub_copy
utility_stub_error:	; from: utility_stub
	move.w	#$2020,utility_stub_name_end    ; the name buffer's length cleared
	pea	utility_stub_error_text(pc)     ; "... a bell"
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	move.w	#$8,-(sp)
	trap	#1                              ; Cnecin
	addq.l	#8,sp
	clr.w	-(sp)
	trap	#1                              ; Pterm0
utility_stub_text:	; from: utility_stub
	dc.w	$1b45,$1b66,$1b59
	dc.b	$20
utility_stub_title:	; from: utility_stub
	dc.b	'+POMPEY PACKER V1.9',0
utility_stub_clear:	; from: utility_stub
	dc.b	$1b,$45,$1b,$59,$2c
utility_stub_ask:	; from: utility_stub
	dc.b	'$Do you wish to save program in',27,'Y-'
utility_stub_ask_2:	; from: utility_stub
	dc.b	'+unpacked format?'
	dc.b	$07,$00
utility_stub_enter:	; from: utility_stub
	dc.b	$1b,$59,$2c
utility_stub_enter_text:	; from: utility_stub
	dc.b	'$  Enter filename to save as:  ',27,'Y-'
utility_stub_name_line:	; from: utility_stub
	dc.b	'+>               ',27,'Y-'
utility_stub_bell:	; from: utility_stub
	dc.w	$2c07,$1b65
	dc.b	$00
utility_stub_saving:	; from: utility_stub
	dc.b	$1b,$59,$2f
utility_stub_saving_text:	; from: utility_stub
	dc.b	$27,'Saving unpacked program...'
	dc.b	$07,$00
utility_stub_error_text:
	dc.b	$07
	dc.b	27,'E',27,'fERROR WRITING',0
utility_stub_name_end:	; from: utility_stub
	dc.w	$8000
utility_stub_name:	; from: utility_stub
	dcb.b	128,0                           ; the name to save under
menu_format:	; from: start, utility_stub
	bsr.w	clear_work                      ; the work memory cleared
	move.b	path,d0                         ; the drive
	cmpi.b	#$46,d0                         ; F?
	bne.s	format_check_d                  ; no
	bra.w	main_loop                       ; yes: not formatted
format_check_d:
	cmpi.b	#$44,d0                         ; D?
	bne.s	format_ask
	bra.w	main_loop                       ; yes: not formatted
format_ask:
	move.b	path,d0                         ; the drive letter
	move.b	d0,format_drive_letter          ; into the alert
	subi.b	#$41,d0                         ; 0 or 1
	ext.w	d0
	move.w	d0,format_drive_number          ; the drive
	move.w	#$2,aes_int_in                  ; the default button: CANCEL
	move.l	#alert_insert_disc,aes_addr_in  ; "Please insert a disc into drive A."
	moveq	#52,d0
	bsr.w	aes                             ; form_alert
	cmpi.w	#$1,d0                          ; FORMAT?
	beq.s	format_go                       ; yes
	bra.w	main_loop
format_go:
	clr.w	format_track_number             ; from track 0
	move.w	format_virgin,-(sp)             ; virgin
	move.l	format_magic,-(sp)              ; magic
	move.w	format_interleave,-(sp)         ; interleave
	clr.w	-(sp)                           ; side 0
	move.w	format_track_number,-(sp)       ; track
	move.w	format_spt,-(sp)                ; sectors a track
	move.w	format_drive_number,-(sp)       ; the drive
	clr.l	-(sp)
	move.l	work_start,-(sp)                ; the buffer
format_track:
	move.w	#$a,-(sp)
	trap	#14                             ; Flopfmt
	addq.l	#2,sp
	tst.w	d0                              ; an error?
	bmi.w	format_error_track
	tst.w	$e(sp)                          ; side 1 done?
	bne.s	format_next_track               ; yes
	move.w	#$1,$e(sp)                      ; no: side 1
	bra.s	format_track
format_next_track:
	clr.w	$e(sp)                          ; side 0
	addq.w	#1,$c(sp)                       ; the next track
	cmpi.w	#$50,$c(sp)                     ; 80 tracks
	blt.s	format_track
	lea	$18(sp),sp
	movea.l	work_start,a0                   ; the buffer
	moveq	#0,d0
	move.l	d0,d1
	move.w	#$2710,d1                       ; 40004 bytes
format_clear:
	move.l	d0,(a0)+
	dbra	d1,format_clear
	moveq	#1,d0                           ; tracks 1 and 0
	moveq	#0,d1                           ; filled with 0
format_track_0:
	moveq	#0,d2                           ; side 0
	bsr.w	format_again
	moveq	#1,d2                           ; side 1
	bsr.w	format_again
	dbra	d0,format_track_0
	move.w	#$11,-(sp)
	trap	#14                             ; Random
	addq.l	#2,sp
	move.l	d0,format_serial                ; the serial number
	move.w	format_exec,-(sp)               ; executable
	move.w	format_type,-(sp)               ; the disk type
	move.l	format_serial,-(sp)             ; the serial number
	move.l	work_start,-(sp)                ; the buffer
	move.w	#$12,-(sp)
	trap	#14                             ; Protobt
	lea	$e(sp),sp
	movea.l	work_start,a0                   ; the boot sector
	move.l	#$504f4d50,2(a0)                ; "POMP"
	move.w	#$4559,6(a0)                    ; "EY"
	move.w	#$a00,$18(a0)                   ; 10 sectors a track
	move.b	#$40,$13(a0)                    ; 1600 sectors
	move.b	#$6,$14(a0)
	move.w	#$1,-(sp)                       ; 1 sector
	clr.w	-(sp)                           ; side 0
	move.w	#$0,-(sp)                       ; track 0
	move.w	#$1,-(sp)                       ; sector 1
	move.w	format_drive_number,-(sp)       ; the drive
	clr.l	-(sp)
	move.l	work_start,-(sp)                ; the buffer
	move.w	#$9,-(sp)
	trap	#14                             ; Flopwr
	lea	$14(sp),sp
	tst.l	d0                              ; an error?
	bmi.s	format_error
	bra.w	main_loop
format_error_track:
	lea	$18(sp),sp
format_error:
	eori.l	#$ffffffff,d0                   ; the error, made positive
	move.w	d0,aes_int_in
	moveq	#53,d0                          ; form_error
	bsr.w	aes
	bra.w	main_loop

;------------------------------------------------------------------------------
; format_again(d0 = the track, d1 = the filler, d2 = the side): Flopfmt one track again.
;------------------------------------------------------------------------------
format_again:	; from: utility_stub_bits
	movem.l	d0-d7/a0-a2,-(sp)
	move.w	d1,-(sp)
	move.l	format_magic,-(sp)
	move.w	format_interleave,-(sp)
	move.w	d2,-(sp)
	move.w	d0,-(sp)
	move.w	format_spt,-(sp)
	move.w	format_drive_number,-(sp)
	clr.l	-(sp)
	move.l	work_start,-(sp)
	move.w	#$a,-(sp)
	trap	#14                             ; Flopfmt
	lea	$1a(sp),sp
	movem.l	(sp)+,d0-d7/a0-a2
	rts
format_track_number:	; from: utility_stub_bits
	dc.w	$0000
format_virgin:	; from: utility_stub_bits
	dc.w	$e5e5
format_magic:	; from: utility_stub_bits
	dc.l	$87654321
format_interleave:	; from: utility_stub_bits
	dc.w	$0001,$0000,$004f
format_spt:	; from: utility_stub_bits
	dc.w	$000a
format_drive_number:	; from: utility_stub_bits
	dc.w	$0000
format_serial:	; from: utility_stub_bits
	dc.l	$00000000
format_exec:	; from: utility_stub_bits
	dc.w	$0000
format_type:	; from: utility_stub_bits
	dc.w	$0003
number_fields:	; from: clear_status
	dc.l	field_source_position           ; the four number fields cleared by clear_status
	dc.l	field_output_position
	dc.l	field_length
	dc.l	field_packed
field_source_position:	; from: start, show_output
	dc.w	$0000,$0000
field_output_position:	; from: start, show_source
	dc.w	$0000,$0000
field_name:	; from: start, clear_status, form_dial, load_file
	dc.w	$0000,$0000
field_output_name:	; from: start, pack_file
	dc.w	$0000,$0000
field_length:	; from: start, load_file
	dc.w	$0000,$0000
field_packed:	; from: start, form_dial, pack_file
	dc.w	$0000,$0000
field_percent:	; from: start, clear_status, pack_file
	dc.w	$0000,$0000
field_time:	; from: start, clear_time, show_time
	dc.w	$0000,$0000
field_free:	; from: start, show_free_dfree
	dc.w	$0000,$0000
field_offset:	; from: start, pack_go, pack_file
	dc.w	$0000,$0000
stats_packed_field:	; from: start, menu_stats
	dc.w	$0000,$0000
stats_bad_field:	; from: start, menu_stats
	dc.w	$0000,$0000
save_bad:	; from: start, menu_stats, pack_file
	dc.w	$0000                           ; nonzero: bad files are not saved (No Save)
stats_names:	; from: start, menu_stats, clear_stats_names
	dcb.b	36,0                            ; the status box's nine name strings
files_packed_all:	; from: pack_file
	dc.w	$0000
bad_count:	; from: menu_stats, pack_go, verify_bits
	dc.w	$0000                           ; the bad files
bad_flag:	; from: pack_file, verify, verify_bits
	dc.w	$0000                           ; the file just verified was bad
files_packed:	; from: menu_stats, pack_go, pack
	dc.w	$0000                           ; the files packed
work_saved:	; from: object_state, pack_go, pack_b2, pack_file
	dc.l	$00000000                       ; the work memory's start, kept
hide_source:	; from: select_drive_path, pack
	dc.w	$0000
hide_output:	; from: select_drive_path, pack
	dc.w	$0000
depacking:	; from: form_dial, pack_go, load_file
	dc.w	$0000
stop_flag:	; from: select_drive_path, pack_go, pack_b2, pack_file
	dc.w	$0000
process_mode:	; from: start, select_drive_path, pack_go
	dc.w	$0000                           ; set, never read
mask_count:	; from: pack_go, pack_file
	dc.w	$0000
mask_list:	; from: pack_go, pack_b2
	dc.l	$00000000
	dc.w	$0000,$0000,$0000
dta:	; from: pack_b2, next_file, get_dta, set_dta, find_load_address
	dc.l	$00000000
pack_source:	; from: load_file, pack, pack_code
	dc.l	$00000000
work_start:	; from: start, object_state, form_dial, clear_work, pack_go, pack_b2, 6 more
	dc.l	$00000000                       ; the work memory's start
	dc.w	$0000,$0000
file_length:	; from: pack_file, load_file, verify
	dc.l	$00000000
whole_length:	; from: pack_file
	dc.l	$00000000                       ; the packed length with its header
load_address:	; from: form_dial, show_source, load_file, find_load_address, pack
	dc.l	$00000000
packed_end:	; from: pack_file, pack, verify, stop_drive_lights
	dc.l	$00000000
bad_list_end:	; from: pack_go, pack_file
	dc.l	$00000000                       ; the next free place in bad_names
bad_names:	; from: menu_stats, pack_go
	dcb.b	1200,0                          ; the bad files' names, 12 bytes and a 0 each

;------------------------------------------------------------------------------
; aes(d0): call the AES function d0, its control counts from aes_counts; d0 = int_out[0].
;------------------------------------------------------------------------------
aes:	; from: start, clear_stats_names, object_state, show_status_box, draw_object, draw_main, 13 more
	lea	aes_control(pc),a1              ; control
	move.w	d0,(a1)+
	subi.w	#$a,d0
	mulu.w	#$3,d0
	lea	aes_counts(pc),a0
	adda.w	d0,a0
	moveq	#0,d0
	move.b	(a0)+,d0                        ; int_in
	move.w	d0,(a1)+
	move.b	(a0)+,d0                        ; int_out
	move.w	d0,(a1)+
	move.b	(a0)+,d0                        ; addr_in
	move.w	d0,(a1)+
	clr.w	(a1)                            ; addr_out: 0
	move.l	#aes_block,d1                   ; the parameter block
	move.w	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	move.w	aes_int_out(pc),d0
	rts

	section	data
aes_block:	; from: tree_address
	dc.l	aes_control                     ; the AES parameter block: control, global, int_in, int_out, addr_in,
                                                ;   addr_out
	dc.l	aes_global
	dc.l	aes_int_in
	dc.l	aes_int_out
	dc.l	aes_addr_in
	dc.l	aes_addr_out
aes_counts:
	dc.w	$0001,$0002,$0101,$0201,$0100,$0101,$0201,$0101 ; for functions 10 on: int_in, int_out and addr_in
                                                ;   counts
	dc.w	$0101,$0000,$0000,$0000,$0000,$0000,$0100,$0001
	dc.w	$0003,$0500,$0505,$0000,$0101,$0201,$0010,$0701
	dc.w	$0201,$0000,$0000,$0000,$0000,$0000,$0101,$0102
	dc.w	$0101,$0201,$0102,$0101,$0101,$0201,$0101,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0201,$0101,$0101
	dc.w	$0601,$0104,$0101,$0103,$0102,$0101,$0402,$0108
	dc.w	$0101,$0000,$0000,$0000,$0101,$0109,$0100,$0101
	dc.w	$0101,$0100,$0005,$0103,$0301,$0202,$0100,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	20,0
	dc.w	$0403,$0008,$0300,$0601,$0008,$0100,$0801,$0004
	dc.w	$0101,$0301,$0100,$0500,$0101,$0100,$0500,$0001
	dc.w	$0100,$0101,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0002,$0200
	dc.w	$0203,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0501,$0005,$0100
	dc.w	$0101,$0001,$0100,$0205,$0006,$0100,$0201,$0001
	dc.w	$0100,$0605,$0000,$0000,$0001,$0100,$0100,$0201
	dc.w	$0002,$0101,$0101,$0100,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0001,$0203,$0102,$0101,$0101
	dc.w	$0101,$0001,$0100,$0103

	section	bss
aes_control:	ds.b	10
aes_global:	ds.b	28
aes_int_in:	ds.b	32
aes_int_out:	ds.b	14
aes_addr_in:	ds.b	12
aes_addr_out:	ds.b	4
bss_end:

	end
