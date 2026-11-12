; JAMPACK.PRG  -  The JAM Packer V3.0 Pre-Release 1.1
; Devpac source of the program, disassembled by Darren Birks, 11 November 2026.
; Text 35052 bytes, data 10372 bytes, bss 49894 bytes.
;
; JAMPACK.PRG as distributed is packed itself: a 21170 byte program with the JAM Packer's own V3.0 stub
; ("JAM Packer Decrunch V3.0") and 'LZH!' data.  This is the source of the 47539 byte program that stub
; depacks.
;
; This source rebuilds that unpacked program byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o JAMPACK.PRG JAMPACK.S
; It needs no resource file: both its resources are built into the data section.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; The JAM Packer V3.0, Pre-Release 1.1, shareware, (c) 1990, 1991 by Andrew and Tim Knipe.  It is written in C
; (with a Megamax/Laser style library: the C start-up, stdio, malloc, the AES and VDI bindings) and runs as a
; program or as a desk accessory.  It refuses low resolution; medium and high resolution each have their own
; resource, relocated in place at start-up.
;
; The desktop dialog has:
;   File Packer   PACK or UnPACK one file.  A file that is packed already ('LSD!', 'AUTM' or 'LZH!' in its
;                 first 2 K) is depacked and saved; any other is packed, as a program (Program) or as data,
;                 and saved if it got smaller.
;   Multi Packer  pack every file of a folder into another, programs only when Programs is on, with a report of
;                 the files left alone and why.
;   Jammer        JAM puts every file of a folder into one .JAM file; UnJAM makes the folder again.
;   Disk Packer   pack a disk in drive A or B into a .DPK file, or write one back to a disk (formatting it
;                 first when Format is on).
;   Algorithm     LZH or V2.  Flash and Heading set what a packed program's stub does while it depacks.
;
; There are two algorithms:
;   LZH  LHarc 1.13's lzhuf (LZSS over a 4 K window and an adaptive Huffman code), compiled from C (pack_lzh),
;        reading the source from its end so that the data can be depacked in place from the end down.  The
;        depackers (the V3.0 stub's and the program's own copy, depack_lzh) are in assembly.
;   V2   the Automation packers' 'LSD!' algorithm (pack_v2, in assembly), with the packometer bar drawn while
;        it packs.  Its depacker is lsd_depack.
;
; A packed program gets the V2.4 stub (V2) or the V3.0 stub (LZH) in front.  Each clears the top of the screen
; and prints its title (Heading), depacks the program flashing the background (Flash), relocates it to run
; where the stub was, and starts it from a mover on the screen.  set_stub_options patches the stubs for Flash
; and Heading before they are written.
;
; Some things in it look unfinished:
;   - disk_pack reads the FAT and unpacks it into a map when Use FAT is on, but nothing then uses the map.
;   - disk_unpack's read errors after the first chunk call close_gem rather than disk_error.
;   - write_dpk_header gives disk_error only the alert, not the handle.
;   - check_object and uncheck_object are never called.
;   - The UnJAM file selector's mask comes out as "*.*JAM" rather than "*.JAM".
;   - The disk unpacker's file name defaults to DRIVEA.DPK whichever drive is written.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$10a1  the C start-up, main, the desktop, the GEM helpers, ltoa/itoa and the about box
;   $10a2-$1253  depack_v2 and lsd_depack
;   $1254-$15b7  pack_v2, the V2 packer
;   $15b8-$1887  v24_stub, the V2.4 program stub, with its depacker
;   $1888-$2e3b  the file and multi packers, unpack_file, set_stub_options, write_program, pack_file and the
;                pack info
;   $2e3c-$3b47  JAM and UnJAM
;   $3b48-$50ff  the disk packer and unpacker
;   $5100-$621f  pack_lzh, the LZH packer
;   $6220-$6695  v30_stub, the V3.0 program stub, with its LZH depacker
;   $6696-$6a31  depack_lzh, the program's own copy of that depacker
;   $6a32-$88eb  the C library: AES, VDI, BIOS, XBIOS and GEMDOS bindings, stdio, malloc, strings
;   $88ec-$af7f  the data: settings, texts and alerts, and the two resources
;   $af80-$b16f  the LZH tables and the library's variables
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; LZH data: 'LZH!', the unpacked length, the packed length, then the code, which the depacker reads from the
; end down.  A position is coded as in lzhuf: a variable length code for its upper 6 bits (d_code, d_len),
; then its low 6 bits.
;
; V2 data: 'LSD!' ('AUTM' is also recognised), the unpacked length, the packed length, then a bit stream read
; from the end down, as the Automation packers write it.
;
; Packed program: a PRG header whose text is the stub ($2d0 bytes for V2.4, $476 for V3.0) followed by the
; packed data, then a 0 long for its relocation table.
;
; JAM file: the file count (a word), the largest file's length (a long), the folder's name (12 bytes), then for
; each file its name (12 bytes), its length (a long) and its data.
;
; DPK file: the sectors a track, the tracks and the sides (a word each), then LZH chunks, each after its length
; (a long), and a -1 length at the end.  The first chunk is the system sectors (boot sector, FATs and root
; directory), the rest are 600 sectors each.
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The C start-up.  As a desk accessory (no parent basepage) it takes a stack from Malloc; as a program it
; shrinks its memory to the program plus the stack.  Then main(argc, argv, envp) and exit.
;------------------------------------------------------------------------------
start:
	lea	start,a5                        ; a5 = the text
	suba.l	#$100,a5                        ; less $100: the basepage
	tst.l	$24(a5)                         ; a parent?
	bne.s	start_program                   ; yes: a program
	clr.w	app_flag                        ; an accessory
	lea	dial_box_h,sp                   ; a stack of its own for now
	move.l	stack_size,-(sp)                ; the stack size
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.w	#6,sp                           ; drop the arguments
	tst.l	d0                              ; got it?
start_no_memory:
	beq.s	start_no_memory                 ; no: hang
	movea.l	d0,sp                           ; yes: the stack
	adda.l	stack_size,sp                   ; at its top
	bra.s	start_main
start_program:
	move.l	$c(a5),d0                       ; text length
	add.l	$14(a5),d0                      ; + data
	add.l	$1c(a5),d0                      ; + BSS
	add.l	stack_size,d0                   ; + the stack
	addi.l	#$100,d0                        ; + the basepage
	move.l	d0,d1
	add.l	a5,d1                           ; the end
	and.l	#$fffffffe,d1                   ; even
	movea.l	d1,sp                           ; is the stack
	move.l	d0,-(sp)                        ; Mshrink(0, basepage, length)
	move.l	a5,-(sp)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	adda.l	#$c,sp                          ; drop the arguments
start_main:
	move.l	a5,basepage                     ; the basepage
	movea.l	basepage,a0
	move.l	$2c(a0),-(sp)                   ; the environment
	pea	$80(a0)                         ; the command line
	jsr	command_line_args               ; not used
	addq.l	#8,sp                           ; drop the arguments
	move.l	envp,-(sp)                      ; envp
	move.l	argv,-(sp)                      ; argv
	move.w	argc,-(sp)                      ; argc
	jsr	main
	addq.l	#2,sp                           ; drop the arguments
	move.w	#$0,-(sp)                       ; exit(0)
	jsr	exit

;------------------------------------------------------------------------------
; main: open the AES and the VDI, load the resource, then run the desktop dialog until EXIT.  The check
; boxes and radio buttons are read after every form_do.
;------------------------------------------------------------------------------
main:	; from: start
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	jsr	init_gem                        ; the AES, the VDI, the resource
	jsr	clear_title                     ; the background
	pea	desktop_rect                    ; the desktop's box
	move.l	tree_desktop,-(sp)              ; the desktop
	jsr	open_box                        ; draw it
	addq.l	#8,sp                           ; drop the arguments
main_loop:
	clr.w	-(sp)                           ; no edit object
	move.l	tree_desktop,-(sp)              ; the desktop
	jsr	form_do
	addq.l	#6,sp                           ; drop the arguments
	move.w	d0,d7                           ; d7 = the button
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$1ba(a0),d0                     ; Use FAT
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_fat                     ; no
	move.w	#$1,use_fat_flag                ; yes
	bra.s	main_read_format
main_no_fat:
	clr.w	use_fat_flag
main_read_format:
	movea.l	tree_desktop,a0
	move.w	$1a2(a0),d0                     ; Format
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_format                  ; no
	move.w	#$1,format_flag                 ; yes
	bra.s	main_read_programs
main_no_format:
	clr.w	format_flag
main_read_programs:
	movea.l	tree_desktop,a0
	move.w	$15a(a0),d0                     ; Programs (multi packer)
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_programs                ; no
	move.w	#$1,multi_programs              ; yes
	bra.s	main_read_flash
main_no_programs:
	clr.w	multi_programs
main_read_flash:
	movea.l	tree_desktop,a0
	move.w	$ca(a0),d0                      ; Flash
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_flash                   ; no
	move.w	#$1,flash_flag                  ; yes
	bra.s	main_read_heading
main_no_flash:
	clr.w	flash_flag
main_read_heading:
	movea.l	tree_desktop,a0
	move.w	$e2(a0),d0                      ; Heading
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_heading                 ; no
	move.w	#$1,heading_flag                ; yes
	bra.s	main_read_algorithm
main_no_heading:
	clr.w	heading_flag
main_read_algorithm:
	movea.l	tree_desktop,a0
	move.w	$3a(a0),d0                      ; LZH
	and.w	#$1,d0                          ; selected?
	beq.s	main_v2                         ; no
	move.w	#$2,algorithm                   ; yes: algorithm 2, LZH
	bra.s	main_dispatch
main_v2:
	move.w	#$3,algorithm                   ; no: algorithm 3, V2
main_dispatch:
	move.w	d7,d0                           ; the button
	bra.w	main_switch
menu_disk_pack:
	move.w	#$14,-(sp)                      ; deselect the disk PACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	move.w	use_fat_flag,-(sp)              ; Use FAT
	jsr	disk_pack                       ; pack a disk
	addq.l	#2,sp                           ; drop the arguments
	bra.w	main_next
menu_disk_unpack:
	move.w	#$13,-(sp)                      ; deselect the disk UnPACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	move.w	format_flag,-(sp)               ; Format
	jsr	disk_unpack                     ; unpack a disk
	addq.l	#2,sp                           ; drop the arguments
	bra.w	main_next
menu_toggle_program:
	pea	dummy                           ; wait for the mouse button to be let go
	pea	dummy                           ; argument 6
	pea	dummy                           ; argument 5
	pea	dummy                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	#$1,-(sp)                       ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	evnt_button
	lea	$16(sp),sp                      ; drop the arguments
	cmpi.w	#$1,program_flag                ; a program?
	bne.s	menu_now_program                ; no
	pea	text_data                       ; "Data"
	movea.l	tree_desktop,a0                 ; the button's text
	move.l	$b4(a0),-(sp)                   ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	clr.w	program_flag                    ; now data
	bra.s	menu_draw_program
menu_now_program:
	pea	text_program                    ; "Program"
	movea.l	tree_desktop,a0                 ; the button's text
	move.l	$b4(a0),-(sp)                   ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$1,program_flag                ; now a program
menu_draw_program:
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$1,-(sp)                       ; depth 1
	move.w	#$7,-(sp)                       ; the button
	move.l	tree_desktop,-(sp)              ; the desktop
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	bra.w	main_next
menu_pack_file:
	move.w	program_flag,-(sp)              ; a program?
	jsr	pack_one_file                   ; pack or unpack a file
	addq.l	#2,sp                           ; drop the arguments
	jsr	clear_title                     ; the background
	bra.w	main_next
menu_multi_pack:
	pea	text_supply_source_path         ; "Supply the SOURCE path"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	file_name                       ; the path chosen
	pea	multi_name                      ; the name
	pea	source_path                     ; the source path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.w	menu_multi_done                 ; no
	pea	text_supply_destination_path    ; "Supply the DESTINATION path"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	save_name                       ; the path chosen
	pea	multi_name                      ; the name
	pea	destination_path                ; the destination path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.s	menu_multi_paths                ; no
	pea	text_performing_multi_pack      ; "Performing Multi Pack..."
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	move.l	screen_buffer,-(sp)             ; the screen
	move.l	screen,-(sp)                    ; saved
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	move.w	multi_programs,d0               ; packing programs?
	beq.s	menu_multi_data                 ; no
	move.w	#$1,-(sp)                       ; yes
	pea	destination_path                ; the destination
	pea	source_path                     ; the source
	jsr	multi_pack                      ; multi pack
	lea	$a(sp),sp                       ; drop the arguments
	bra.s	menu_multi_paths
menu_multi_data:
	clr.w	-(sp)                           ; data only
	pea	destination_path                ; the destination
	pea	source_path                     ; the source
	jsr	multi_pack                      ; multi pack
	lea	$a(sp),sp                       ; drop the arguments
menu_multi_paths:
	pea	text_all_files_source           ; "\*.*" back on the source path
	pea	source_path                     ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_all_files_destination      ; and the destination path
	pea	destination_path                ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
menu_multi_done:
	move.w	#$d,-(sp)                       ; deselect the PACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	jsr	clear_title                     ; the background
	bra.w	main_next
menu_about:
	jsr	about_box                       ; the about box
	bra.w	main_next
menu_about2:
	jsr	about_box                       ; the about box
	bra.w	main_next
menu_about3:
	jsr	about_box                       ; the about box
	bra.w	main_next
menu_jam:
	move.w	#$19,-(sp)                      ; jam a folder (the routine is given the button)
	jsr	jam_unjam
	addq.l	#2,sp                           ; drop the arguments
	move.w	#$19,-(sp)                      ; deselect the JAM button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	jsr	clear_title                     ; the background
	bra.w	main_next
menu_unjam:
	move.w	#$1b,-(sp)                      ; unjam a file (the same routine, given UnJAM)
	jsr	jam_unjam
	addq.l	#2,sp                           ; drop the arguments
	move.w	#$1b,-(sp)                      ; deselect the UnJAM button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	jsr	clear_title                     ; the background
	bra.s	main_next
	bra.s	main_next
main_switch:
	cmp.w	#$7,d0                          ; Program/Data?
	beq.w	menu_toggle_program
	cmp.w	#$a,d0                          ; PACK or UnPACK?
	beq.w	menu_pack_file
	cmp.w	#$d,d0                          ; Multi PACK?
	beq.w	menu_multi_pack
	cmp.w	#$13,d0                         ; Disk UnPACK?
	beq.w	menu_disk_unpack
	cmp.w	#$14,d0                         ; Disk PACK?
	beq.w	menu_disk_pack
	cmp.w	#$15,d0                         ; the title box?
	beq.w	menu_about
	cmp.w	#$16,d0                         ; the title box
	beq.w	menu_about3
	cmp.w	#$17,d0                         ; the title box
	beq.w	menu_about2
	cmp.w	#$19,d0                         ; JAM?
	beq.w	menu_jam
	cmp.w	#$1b,d0                         ; UnJAM?
	beq.s	menu_unjam
main_next:
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$2aa(a0),d0                     ; EXIT selected?
	and.w	#$1,d0
	beq.w	main_loop                       ; no: on
	pea	desktop_rect                    ; the desktop's box
	move.l	tree_desktop,-(sp)              ; the desktop
	jsr	close_box                       ; remove it
	addq.l	#8,sp                           ; drop the arguments
	jsr	close_gem                       ; close the VDI and the AES
	move.w	#$1,-(sp)                       ; exit(1)
	jsr	exit
	addq.l	#2,sp                           ; drop the arguments
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The command line, unused.
;------------------------------------------------------------------------------
command_line_args:	; from: start
	rts

;------------------------------------------------------------------------------
; PACK or UnPACK: choose a file; a packed one is unpacked, otherwise it is loaded (more than 10 bytes) and
; packed, with an alert for each failure.
;------------------------------------------------------------------------------
pack_one_file:	; from: main
	link	a6,#-52                         ; 52 bytes of locals
	movem.l	d7,-(sp)                        ; keep the registers
	pea	text_choose_file                ; "Choose a file to pack/unpack"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$a,-(sp)                       ; deselect the PACK or UnPACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	pea	file_name                       ; the path chosen
	pea	pack_file_name                  ; the name
	pea	source_path                     ; the source path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.w	pack_one_file_done              ; no
	pea	file_name                       ; the file
	jsr	unpack_file                     ; unpack it if it is packed
	addq.l	#4,sp                           ; drop the arguments
	cmpi.l	#$ffffffff,d0                   ; not packed?
	bne.w	pack_one_file_done              ; it was: done
	jsr	clear_title                     ; the background
	move.w	#$2f,-(sp)                      ; Fgetdta
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,-$4(a6)                      ; kept
	pea	-$34(a6)                        ; a DTA of our own
	move.w	#$1a,-(sp)                      ; Fsetdta
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	clr.w	-(sp)                           ; normal files
	pea	file_name                       ; the file
	move.w	#$4e,-(sp)                      ; Fsfirst
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	tst.w	d0                              ; found?
	beq.s	pack_file_found                 ; yes
	pea	alert_file_not_found            ; no: "File Not Found!"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$ffff,d0
	bra.w	pack_one_file_done
pack_file_found:
	cmpi.l	#$a,-$1a(a6)                    ; more than 10 bytes?
	bgt.s	pack_file_size_ok               ; yes
	pea	alert_file_too_small            ; no: "File Too Small Not worth crunching!"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$a,-(sp)                       ; deselect the button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	move.w	#$ffff,d0
	bra.w	pack_one_file_done
pack_file_size_ok:
	move.l	-$4(a6),-(sp)                   ; the old DTA
	move.w	#$1a,-(sp)                      ; Fsetdta
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	-$16(a6)                        ; the name found
	move.w	8(a6),-(sp)                     ; a program?
	move.l	-$1a(a6),-(sp)                  ; the length
	pea	file_name                       ; the file
	jsr	pack_file                       ; pack it
	lea	$e(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; the result
	cmpi.l	#$1,-$8(a6)                     ; 1: no memory?
	bne.s	pack_file_not_memory            ; no
	pea	alert_no_memory_to_compact      ; "Insufficient Memory To Compact File"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$ffff,d0
	bra.w	pack_one_file_done
pack_file_not_memory:
	cmpi.l	#$2,-$8(a6)                     ; 2: read error?
	bne.s	pack_file_not_read              ; no
	pea	alert_error_reading_source      ; "Error Reading Source File"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$ffff,d0
	bra.s	pack_one_file_done
pack_file_not_read:
	cmpi.l	#$3,-$8(a6)                     ; 3: cancelled?
	bne.s	pack_file_not_cancelled         ; no
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$ffff,d0
	bra.s	pack_one_file_done
pack_file_not_cancelled:
	cmpi.l	#$4,-$8(a6)                     ; 4: larger?
	bne.s	pack_one_file_done              ; no
	pea	alert_packed_size_larger        ; "Packed Size > Original Size File Not saved"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$ffff,d0
	nop
pack_one_file_done:
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; choose_file(path, name, full): the file selector over the saved screen; full = the path up to its last \
; and the name.  d0 = 0 for OK, -1 for Cancel.
;------------------------------------------------------------------------------
choose_file:	; from: main, pack_one_file, unpack_file, pack_file, jam_unjam, disk_unpack, 1 more
	link	a6,#-2                          ; 2 bytes of locals
	move.l	screen_buffer,-(sp)             ; the screen
	move.l	screen,-(sp)                    ; saved
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	pea	-$2(a6)                         ; the button
	move.l	$c(a6),-(sp)                    ; the name
	move.l	8(a6),-(sp)                     ; the path
	jsr	fsel_input
	lea	$c(sp),sp                       ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	tst.w	-$2(a6)                         ; OK?
	bne.s	choose_file_ok                  ; yes
	move.w	#$ffff,d0                       ; no: -1
	bra.s	choose_file_done
choose_file_ok:
	move.l	8(a6),-(sp)                     ; the path
	move.l	$10(a6),-(sp)                   ; into full
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$5c,-(sp)                      ; its last \
	move.l	$10(a6),-(sp)                   ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)                           ; cut after it
	move.l	$c(a6),-(sp)                    ; the name
	move.l	$10(a6),-(sp)                   ; after it
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$0,d0                          ; 0
choose_file_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; deselect(object): clear the object's SELECTED state in the desktop and redraw it.
;------------------------------------------------------------------------------
deselect:	; from: main, pack_one_file
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; the object
	move.w	d7,d6
	ext.l	d6                              ; to a long
	move.l	d6,-(sp)                        ; the number
	move.l	#$18,d6                         ; 24 bytes an object
	move.l	d6,-(sp)                        ; the multiplier
	jsr	lmul                            ; times
	move.l	(sp)+,d6                        ; the product
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$a(a0,d6.l),d6                  ; its state
	and.w	#$fffe,d6                       ; not selected
	move.w	#$1,-(sp)                       ; redraw
	move.w	d6,-(sp)                        ; the state
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	d7,-(sp)                        ; the object
	move.l	tree_desktop,-(sp)              ; the desktop
	jsr	objc_change
	lea	$14(sp),sp                      ; drop the arguments
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; check_object(object), uncheck_object(object): set or clear CHECKED in the desktop.  Nothing calls them.
;------------------------------------------------------------------------------
check_object:
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7
	move.w	d7,d6
	ext.l	d6                              ; to a long
	move.l	d6,-(sp)                        ; the number
	move.l	#$18,d6
	move.l	d6,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d6                        ; the product
	movea.l	tree_desktop,a0
	move.w	$a(a0,d6.l),d6                  ; its state
	or.w	#$4,d6                          ; checked
	move.w	#$1,-(sp)                       ; redraw
	move.w	d6,-(sp)                        ; argument 8
	move.w	screen_height,-(sp)             ; argument 7
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	d7,-(sp)                        ; argument 2
	move.l	tree_desktop,-(sp)              ; argument 1
	jsr	objc_change
	lea	$14(sp),sp                      ; drop the arguments
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts
uncheck_object:
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7
	move.w	d7,d6
	ext.l	d6                              ; to a long
	move.l	d6,-(sp)                        ; the number
	move.l	#$18,d6
	move.l	d6,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d6                        ; the product
	movea.l	tree_desktop,a0
	move.w	$a(a0,d6.l),d6                  ; its state
	and.w	#$fffb,d6                       ; not checked
	move.w	#$1,-(sp)                       ; argument 9
	move.w	d6,-(sp)                        ; argument 8
	move.w	screen_height,-(sp)             ; argument 7
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	d7,-(sp)                        ; argument 2
	move.l	tree_desktop,-(sp)              ; argument 1
	jsr	objc_change
	lea	$14(sp),sp                      ; drop the arguments
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Open the AES (appl_init) and a VDI workstation, set the arrow, find the screen and a buffer for it, and
; refuse low resolution.  Medium and high resolution each have their own resource, built into the data;
; it is relocated and its five trees found.  The defaults are set (LZH, Flash, Heading, Format, Use FAT,
; Programs), and the desktop is placed at the bottom of the screen, the others where they fit.
;------------------------------------------------------------------------------
init_gem:	; from: main
	link	a6,#0                           ; the frame
	jsr	appl_init
	jsr	open_workstation                ; the VDI workstation
	move.w	d0,vdi_handle                   ; its handle
	clr.l	-(sp)                           ; argument 2
	clr.w	-(sp)                           ; ARROW
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$2,-(sp)                       ; Physbase
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,screen                       ; the screen
	move.l	#$7d00,-(sp)                    ; 32000 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,screen_buffer                ; the screen buffer
	move.w	#$4,-(sp)                       ; Getrez
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.w	d0,resolution                   ; the resolution
	move.w	resolution,d0
	bra.w	init_rez_switch
init_low_rez:
	pea	alert_low_rez                   ; "The JAM Packer V3.0 will not work in low res."
	move.w	#$1,-(sp)                       ; argument 1
	jsr	fatal_alert                     ; and quit
	addq.l	#6,sp                           ; drop the arguments
	bra.w	init_trees
init_medium:
	pea	resource_medium                 ; the medium resolution resource
	jsr	rsrc_relocate                   ; relocated
	addq.l	#4,sp                           ; drop the arguments
	bra.w	init_trees
init_high:
	pea	resource_high                   ; the high resolution resource
	jsr	rsrc_relocate                   ; relocated
	addq.l	#4,sp                           ; drop the arguments
	bra.w	init_trees
init_other_rez:
	pea	alert_other_rez                 ; "Wow! You've got a trendy resolution..."
	move.w	#$1,-(sp)                       ; argument 1
	jsr	fatal_alert                     ; and quit
	addq.l	#6,sp                           ; drop the arguments
	bra.s	init_trees
init_rez_switch:
	cmp.w	#$0,d0                          ; low?
	beq.s	init_low_rez
	cmp.w	#$1,d0                          ; medium?
	beq.s	init_medium
	cmp.w	#$2,d0                          ; high?
	beq.s	init_high
	jmp	init_other_rez                  ; anything else
init_trees:
	pea	tree_desktop                    ; tree 2: the desktop
	move.w	#$2,-(sp)                       ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	rsrc_gaddr
	addq.l	#8,sp                           ; drop the arguments
	pea	tree_packometer                 ; tree 3: the packometer
	move.w	#$3,-(sp)                       ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	rsrc_gaddr
	addq.l	#8,sp                           ; drop the arguments
	pea	tree_info                       ; tree 1: the pack info
	move.w	#$1,-(sp)                       ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	rsrc_gaddr
	addq.l	#8,sp                           ; drop the arguments
	pea	tree_about                      ; tree 4: about
	move.w	#$4,-(sp)                       ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	rsrc_gaddr
	addq.l	#8,sp                           ; drop the arguments
	pea	tree_disk                       ; tree 0: the disk progress
	clr.w	-(sp)                           ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	rsrc_gaddr
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$1,use_fat_flag                ; Use FAT on
	move.w	#$1,format_flag                 ; Format on
	move.w	#$1,heading_flag                ; Heading on
	move.w	#$1,flash_flag                  ; Flash on
	move.w	#$1,program_flag                ; a program
	move.w	#$1,multi_programs              ; Programs on
	movea.l	tree_desktop,a0                 ; the desktop
	ori.w	#$1,$ca(a0)                     ; Flash selected
	movea.l	tree_desktop,a0
	ori.w	#$1,$e2(a0)                     ; Heading
	movea.l	tree_desktop,a0
	ori.w	#$1,$1a2(a0)                    ; Format
	movea.l	tree_desktop,a0
	ori.w	#$1,$15a(a0)                    ; Programs
	movea.l	tree_desktop,a0
	ori.w	#$1,$1ba(a0)                    ; Use FAT
	movea.l	tree_desktop,a0
	ori.w	#$1,$3a(a0)                     ; LZH
	pea	packometer_rect+6               ; argument 5
	pea	packometer_rect+4               ; argument 4
	pea	packometer_rect+2               ; argument 3
	pea	dummy                           ; argument 2
	move.l	tree_packometer,-(sp)           ; the packometer
	jsr	form_center
	lea	$14(sp),sp                      ; drop the arguments
	move.w	#$5,bar_column                  ; column 5
	move.w	bar_column,d0
	asl.w	#4,d0                           ; * 16
	subq.w	#1,d0
	movea.l	tree_packometer,a0              ; the packometer
	sub.w	$40(a0),d0                      ; less its bar's x
	move.w	d0,packometer_rect
	movea.l	tree_packometer,a0
	move.w	packometer_rect,$10(a0)         ; is its x
	movea.l	tree_packometer,a0
	move.w	$12(a0),d1                      ; its y
	movea.l	tree_packometer,a0
	add.w	$42(a0),d1                      ; + the bar's y
	movea.l	tree_packometer,a0
	add.w	$46(a0),d1                      ; + the bar's height
	move.w	#$1,d0
	add.w	screen_height,d0                ; + the screen height
	sub.w	d1,d0
	move.w	d0,bar_offset
	movea.l	tree_packometer,a0
	move.w	$46(a0),bar_height              ; the bar's height
	pea	desktop_rect+6                  ; the desktop's box
	pea	desktop_rect+4                  ; argument 4
	pea	desktop_rect+2                  ; argument 3
	pea	desktop_rect                    ; argument 2
	move.l	tree_desktop,-(sp)              ; the desktop
	jsr	form_center
	lea	$14(sp),sp                      ; drop the arguments
	pea	info_rect+6                     ; the pack info's box
	pea	info_rect+4                     ; argument 4
	pea	info_rect+2                     ; argument 3
	pea	info_rect                       ; argument 2
	move.l	tree_info,-(sp)                 ; the pack info
	jsr	form_center
	lea	$14(sp),sp                      ; drop the arguments
	addi.w	#$a,info_rect                   ; 10 to the right
	movea.l	tree_info,a0
	move.w	info_rect,$10(a0)
	pea	disk_rect+6                     ; the disk progress's box
	pea	disk_rect+4                     ; argument 4
	pea	disk_rect+2                     ; argument 3
	pea	disk_rect                       ; argument 2
	move.l	tree_disk,-(sp)                 ; the disk progress
	jsr	form_center
	lea	$14(sp),sp                      ; drop the arguments
	addi.w	#$0,disk_rect
	movea.l	tree_disk,a0
	move.w	disk_rect,$10(a0)
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Close the VDI workstation and the AES.
;------------------------------------------------------------------------------
close_gem:	; from: main, fatal_alert, disk_unpack
	link	a6,#0                           ; the frame
	move.w	vdi_handle,-(sp)                ; the handle
	jsr	v_clsvwk
	addq.l	#2,sp                           ; drop the arguments
	jsr	appl_exit
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; fatal_alert(button, alert): show it, close GEM and exit(1).
;------------------------------------------------------------------------------
fatal_alert:	; from: init_gem
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.w	8(a6),d7
	move.l	$a(a6),-(sp)                    ; the alert
	move.w	d7,-(sp)                        ; the button
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	jsr	close_gem                       ; close GEM
	move.w	#$1,-(sp)                       ; exit(1)
	jsr	exit
	addq.l	#2,sp                           ; drop the arguments
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; copy_screen(from, to): 32000 bytes, with the mouse hidden.
;------------------------------------------------------------------------------
copy_screen:	; from: main, pack_one_file, choose_file, about_box, multi_pack, multi_pack_one, 4 more
	link	a6,#0                           ; the frame
	movem.l	a4-a5,-(sp)                     ; keep the registers
	movea.l	8(a6),a5                        ; from
	movea.l	$c(a6),a4                       ; to
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$7cf,d0                        ; 2000 times 16 bytes
copy_screen_loop:
	move.l	(a5)+,(a4)+
	move.l	(a5)+,(a4)+
	move.l	(a5)+,(a4)+
	move.l	(a5)+,(a4)+
	dbra	d0,copy_screen_loop
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	movem.l	(sp)+,a4-a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; open_box(tree, box): FMD_START, a shrinking box (as the program does it) and the tree drawn.
;------------------------------------------------------------------------------
open_box:	; from: main, disk_unpack, disk_pack
	link	a6,#0                           ; the frame
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	movea.l	$c(a6),a0                       ; the box
	move.w	6(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	4(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	2(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	(a0),-(sp)                      ; argument 2
	clr.w	-(sp)                           ; FMD_START
	jsr	form_dial
	lea	$12(sp),sp                      ; drop the arguments
	move.w	screen_height,-(sp)             ; the screen as the big box
	move.w	screen_width,-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	movea.l	$c(a6),a0                       ; the box
	move.w	6(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	4(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	2(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	(a0),-(sp)                      ; argument 1
	jsr	graf_shrinkbox
	lea	$10(sp),sp                      ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$a,-(sp)                       ; depth 10
	clr.w	-(sp)                           ; from the root
	move.l	8(a6),-(sp)                     ; the tree
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; close_box(tree, box): FMD_FINISH and a growing box.
;------------------------------------------------------------------------------
close_box:	; from: main, disk_unpack
	link	a6,#0                           ; the frame
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	movea.l	$c(a6),a0                       ; the box
	move.w	6(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	4(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	2(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	(a0),-(sp)                      ; argument 2
	move.w	#$3,-(sp)                       ; FMD_FINISH
	jsr	form_dial
	lea	$12(sp),sp                      ; drop the arguments
	move.w	screen_height,-(sp)             ; the screen as the big box
	move.w	screen_width,-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	movea.l	$c(a6),a0                       ; the box
	move.w	6(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	4(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	2(a0),-(sp)
	movea.l	$c(a6),a0
	move.w	(a0),-(sp)                      ; argument 1
	jsr	graf_growbox
	lea	$10(sp),sp                      ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Open a VDI virtual workstation on the AES's handle (GDOS present or not); d0 = its handle.  The screen's
; width and height are kept.
;------------------------------------------------------------------------------
open_workstation:	; from: init_gem
	link	a6,#-142                        ; 142 bytes of locals
	movem.l	d7,-(sp)                        ; keep the registers
	clr.w	-$8e(a6)                        ; no GDOS
	move.w	#$fffe,d0                       ; vq_gdos
	trap	#2                              ; AES/VDI
	cmp.w	#$fffe,d0
	beq.s	open_workstation_device         ; no
	move.w	#$1,-$8e(a6)                    ; yes
open_workstation_device:
	move.w	-$8e(a6),d0                     ; GDOS?
	beq.s	open_workstation_screen         ; no
	move.w	#$4,-(sp)                       ; yes: Getrez
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	addq.w	#2,d0                           ; + 2: the screen device
	move.w	d0,-$16(a6)                     ; work_in[0]
	bra.s	open_workstation_defaults
open_workstation_screen:
	move.w	#$1,-$16(a6)                    ; device 1
open_workstation_defaults:
	move.w	#$1,d7                          ; work_in[1-9] = 1
	bra.s	open_workstation_next
open_workstation_loop:
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	-$16(a6),a0
	move.w	#$1,0(a0,d0.w)
	addq.w	#1,d7
open_workstation_next:
	cmpi.w	#$a,d7
	blt.s	open_workstation_loop
	move.w	#$2,-$2(a6)                     ; raster coordinates
	pea	-$8c(a6)                        ; argument 4
	pea	-$8c(a6)                        ; argument 3
	pea	-$8c(a6)                        ; argument 2
	pea	-$8c(a6)                        ; argument 1
	jsr	graf_handle
	lea	$10(sp),sp                      ; drop the arguments
	move.w	d0,-$8a(a6)                     ; the handle
	pea	-$88(a6)                        ; work_out
	pea	-$8a(a6)                        ; the handle
	pea	-$16(a6)                        ; work_in
	jsr	v_opnvwk
	lea	$c(sp),sp                       ; drop the arguments
	move.w	-$88(a6),screen_width           ; the width - 1
	move.w	-$86(a6),screen_height          ; the height - 1
	move.w	-$8a(a6),d0                     ; opened?
	bne.s	open_workstation_done           ; yes
	pea	alert_no_workstation            ; no: "Couldn't open workstation"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$1,-(sp)                       ; exit(1)
	jsr	exit
	addq.l	#2,sp                           ; drop the arguments
open_workstation_done:
	move.w	-$8a(a6),d0                     ; the handle
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Clear the title line at the top of the screen with a pattern bar.
;------------------------------------------------------------------------------
clear_title:	; from: main, pack_one_file, show_title, disk_unpack, disk_pack
	link	a6,#-16                         ; 16 bytes of locals
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$2,-(sp)                       ; pattern
	move.w	vdi_handle,-(sp)                ; the handle
	jsr	vsf_interior
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$3,-(sp)                       ; style 3
	move.w	vdi_handle,-(sp)                ; the handle
	jsr	vsf_style
	addq.l	#4,sp                           ; drop the arguments
	clr.w	-$10(a6)                        ; x1 = 0
	clr.w	-$e(a6)                         ; y1 = 0
	move.w	#$27f,-$c(a6)                   ; x2 = 639
	cmpi.w	#$2,resolution                  ; high resolution?
	bne.s	clear_title_medium              ; no
	move.w	#$13,d0                         ; yes: y2 = 19
	bra.s	clear_title_bar
clear_title_medium:
	move.w	#$a,d0                          ; no: y2 = 10
clear_title_bar:
	move.w	d0,-$a(a6)
	pea	-$10(a6)                        ; the box
	move.w	vdi_handle,-(sp)                ; the handle
	jsr	v_bar
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; show_title(text): clear the title line and print the text centred on it.
;------------------------------------------------------------------------------
show_title:	; from: main, pack_one_file, unpack_file, write_program, pack_file, save_file, 5 more
	link	a6,#-16                         ; 16 bytes of locals
	jsr	clear_title                     ; clear it
	pea	-$10(a6)                        ; the extent
	move.l	8(a6),-(sp)                     ; the text
	move.w	vdi_handle,-(sp)                ; the handle
	jsr	vqt_extent
	lea	$a(sp),sp                       ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.l	8(a6),-(sp)                     ; the text
	cmpi.w	#$2,resolution                  ; high resolution?
	bne.s	show_title_medium               ; no
	move.w	#$f,d0                          ; yes: y = 15
	bra.s	show_title_y
show_title_medium:
	move.w	#$8,d0                          ; no: y = 8
show_title_y:
	move.w	d0,-(sp)
	move.w	#$140,d0                        ; 320
	move.w	-$c(a6),d1                      ; the width
	sub.w	-$10(a6),d1
	ext.l	d1                              ; to a long
	divs.w	#$2,d1                          ; halved
	sub.w	d1,d0                           ; less: x
	move.w	d0,-(sp)                        ; argument 2
	move.w	vdi_handle,-(sp)                ; the handle
	jsr	v_gtext
	lea	$a(sp),sp                       ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; ltoa(value, buffer): the decimal digits of a long, without leading zeros.
;------------------------------------------------------------------------------
ltoa:	; from: show_pack_sizes, show_crunching, jam_unjam, disk_unpack
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the value
	clr.w	d5                              ; the digit count
	move.w	#$1,d4                          ; leading zeros
	move.l	#$3b9aca00,d6                   ; 1000000000
	bra.s	ltoa_loop
ltoa_digit:
	move.l	d7,d0
	cmp.l	d6,d0                           ; the value at least the place?
	blt.s	ltoa_zero                       ; no
	move.l	#$30,d0                         ; '0'
	move.l	d7,d1
	move.l	d1,-(sp)                        ; the dividend
	move.l	d6,d1
	move.l	d1,-(sp)                        ; the divisor
	jsr	ldiv                            ; value / place
	move.l	(sp)+,d1                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	add.l	d1,d0                           ; + the digit
	move.w	d5,d1
	addq.w	#1,d5
	movea.l	$c(a6),a0                       ; the buffer
	move.b	d0,0(a0,d1.w)                   ; stored
	move.l	d7,d0
	move.l	d0,-(sp)                        ; the dividend
	move.l	d6,d0
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; value / place
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.l	d0,-(sp)                        ; the number
	move.l	d6,d0
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul                            ; * place
	move.l	(sp)+,d0                        ; the product
	sub.l	d0,d7                           ; taken off
	clr.w	d4                              ; no more leading zeros
	bra.s	ltoa_next
ltoa_zero:
	move.w	d4,d0                           ; still leading?
	bne.s	ltoa_next                       ; yes: nothing
	move.w	d5,d0                           ; no: a 0
	addq.w	#1,d5
	movea.l	$c(a6),a0
	move.b	#$30,0(a0,d0.w)
ltoa_next:
	move.l	d6,d0                           ; the place
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$a,d0
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; / 10
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.l	d0,d6
ltoa_loop:
	tst.l	d6                              ; any places left?
	bgt.w	ltoa_digit                      ; yes
	movea.l	$c(a6),a0
	clr.b	0(a0,d5.w)                      ; ended
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; itoa(value, buffer): the same for a word, from 10000.
;------------------------------------------------------------------------------
itoa:	; from: jam_unjam, disk_unpack, disk_pack, show_disk_info
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; the value
	clr.w	d5                              ; the digit count
	move.w	#$1,d4                          ; leading zeros
	move.w	#$2710,d6                       ; 10000
	bra.s	itoa_loop
itoa_digit:
	move.w	d7,d0
	cmp.w	d6,d0                           ; at least the place?
	blt.s	itoa_zero                       ; no
	move.w	#$30,d0                         ; '0'
	move.w	d7,d1
	ext.l	d1                              ; to a long
	divs.w	d6,d1                           ; value / place
	add.w	d1,d0                           ; + the digit
	move.w	d5,d1
	addq.w	#1,d5
	movea.l	$a(a6),a0                       ; the buffer
	move.b	d0,0(a0,d1.w)                   ; stored
	move.w	d7,d0
	ext.l	d0                              ; to a long
	divs.w	d6,d0
	muls.w	d6,d0                           ; * place
	sub.w	d0,d7                           ; taken off
	clr.w	d4                              ; no more leading zeros
	bra.s	itoa_next
itoa_zero:
	move.w	d4,d0                           ; still leading?
	bne.s	itoa_next                       ; yes: nothing
	move.w	d5,d0                           ; no: a 0
	addq.w	#1,d5
	movea.l	$a(a6),a0
	move.b	#$30,0(a0,d0.w)
itoa_next:
	move.w	d6,d0                           ; the place
	ext.l	d0                              ; to a long
	divs.w	#$a,d0                          ; / 10
	move.w	d0,d6
itoa_loop:
	tst.w	d6                              ; any places left?
	bgt.s	itoa_digit                      ; yes
	movea.l	$a(a6),a0
	clr.b	0(a0,d5.w)                      ; ended
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The about box, over the saved screen.
;------------------------------------------------------------------------------
about_box:	; from: main
	link	a6,#0                           ; the frame
	move.l	screen_buffer,-(sp)             ; the screen
	move.l	screen,-(sp)                    ; saved
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	pea	about_rect+6                    ; its box
	pea	about_rect+4                    ; argument 4
	pea	about_rect+2                    ; argument 3
	pea	about_rect                      ; argument 2
	move.l	tree_about,-(sp)                ; the about box
	jsr	form_center
	lea	$14(sp),sp                      ; drop the arguments
	move.w	screen_height,-(sp)             ; the screen as the big box
	move.w	screen_width,-(sp)              ; argument 7
	clr.w	-(sp)                           ; argument 6
	clr.w	-(sp)                           ; argument 5
	move.w	about_rect+6,-(sp)              ; its box
	move.w	about_rect+4,-(sp)              ; argument 3
	move.w	about_rect+2,-(sp)              ; argument 2
	move.w	about_rect,-(sp)                ; argument 1
	jsr	graf_shrinkbox
	lea	$10(sp),sp                      ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	clr.w	-(sp)                           ; from the root
	move.l	tree_about,-(sp)                ; the about box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	clr.w	-(sp)                           ; no edit object
	move.l	tree_about,-(sp)                ; the about box
	jsr	form_do
	addq.l	#6,sp                           ; drop the arguments
	movea.l	tree_about,a0                   ; the about box
	andi.w	#$fffe,$3a(a0)                  ; Ok not selected
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the screen as the big box
	move.w	screen_width,-(sp)              ; argument 7
	clr.w	-(sp)                           ; argument 6
	clr.w	-(sp)                           ; argument 5
	move.w	about_rect+6,-(sp)              ; its box
	move.w	about_rect+4,-(sp)              ; argument 3
	move.w	about_rect+2,-(sp)              ; argument 2
	move.w	about_rect,-(sp)                ; argument 1
	jsr	graf_growbox
	lea	$10(sp),sp                      ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; depack_v2(packed, destination): depack 'LSD!' data in supervisor mode.  d0 = 0.
;------------------------------------------------------------------------------
depack_v2:	; from: unpack_file
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the packed data
	move.l	$c(a6),d6                       ; the destination
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	depack_v2_colour(pc),a0
	move.w	$ffff8240,(a0)                  ; palette 0, keep the background colour
	movea.l	d7,a0                           ; a0 = the packed data
	movea.l	d6,a1                           ; a1 = the destination
	lea	depack_v2_ssp(pc),a2
	move.l	d0,(a2)                         ; keep the old stack
	move.l	$bc.w,-(sp)                     ; keep the trap #15 vector: lsd_depack uses it
	bsr.s	lsd_depack                      ; depack
	move.l	(sp)+,$bc.w                     ; the vector back
	move.w	depack_v2_colour(pc),$ffff8240  ; palette 0, the colour back
	move.l	depack_v2_ssp(pc),-(sp)         ; Super(old stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	move.l	#$0,d0                          ; 0
	unlk	a6                              ; the frame back
	rts
depack_v2_ssp:
	dc.l	$00000000                       ; the stack Super returned
depack_v2_colour:
	dc.w	$0000                           ; the background colour

;------------------------------------------------------------------------------
; Depack 'LSD!' data at a0 to a1 (the V2 format of the Automation packers), from the end of the packed data
; down.  The header's address is kept in the trap #15 vector at $bc.
;------------------------------------------------------------------------------
lsd_depack:	; from: depack_v2
	adda.l	#$4,a0                          ; past 'LSD!'
	move.l	a0,$bc.w                        ; the header, kept at $bc
	move.l	(a0)+,d5                        ; d5 = the unpacked length
	adda.l	d5,a1                           ; a1 = the end of the output
	adda.l	(a0),a0                         ; + the packed length
	suba.l	#$4,a0
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
	ext.w	d2                              ; to a word
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
	ext.w	d2                              ; to a word
	add.w	d2,d1
lsd_copy_literals:
	move.b	-(a0),-(a1)                     ; copy a literal
	dbra	d1,lsd_copy_literals            ; for each literal
lsd_string:
	movea.l	$bc.w,a3                        ; the header
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
	ext.w	d3                              ; to a word
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
	ext.w	d3                              ; to a word
	add.w	d3,d1
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
	ext.w	d4                              ; to a word
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
	ext.l	d1                              ; to a long
	adda.l	d1,a2                           ; + the length
	subq.w	#1,d1
lsd_copy_string_loop:
	move.b	-(a2),-(a1)                     ; copy it
	dbra	d1,lsd_copy_string_loop         ; for each byte
	bra.w	lsd_next                        ; and on
lsd_depack_done:
	rts
lsd_literal_table:
	dc.b	$0a,$03,$02,$02,$0e,$07,$04,$01 ; bits, then base counts less 1
lsd_length_table:
	dc.b	$0a,$02,$01,$00,$00,$0a,$06,$04,$03,$02 ; extra bits, then base lengths
lsd_offset_table:
	dc.b	$0b,$04,$07,$00                 ; bits, then base offsets
	dc.w	$0120,$0000,$0020,$0000
	dc.w	$4cdf,$00c0,$4e5e,$4e75         ; not used: left-over code bytes

;------------------------------------------------------------------------------
; pack_v2(source, length, destination, window): pack with the V2 algorithm in supervisor mode with the
; interrupts off, drawing the packometer's bar on the screen as it goes.  The packer's variables are kept in the
; trap vectors $80-$b0, which are saved and put back.  d0 = the packed length.
;------------------------------------------------------------------------------
pack_v2:	; from: pack_file, multi_pack_file
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the source
	move.l	$c(a6),d6                       ; its length
	move.l	$10(a6),d5                      ; the destination
	move.l	$14(a6),d4                      ; the window
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	pack_v2_ssp(pc),a0
	move.l	d0,(a0)                         ; keep the old stack
	move.l	$90.w,-(sp)                     ; keep the trap vectors $90-$b0
	move.l	$94.w,-(sp)
	move.l	$98.w,-(sp)
	move.l	$9c.w,-(sp)
	move.l	$a0.w,-(sp)
	move.l	$a4.w,-(sp)
	move.l	$a8.w,-(sp)
	move.l	$ac.w,-(sp)
	move.l	$b0.w,-(sp)
	move.l	d7,$90.w                        ; $90: the source
	move.l	d6,$94.w                        ; $94: its length
	move.l	d5,$98.w                        ; $98: the destination
	move.l	d4,$a0.w                        ; $a0: the window
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp                           ; drop the arguments
	movea.l	d0,a6
	adda.l	#$7d00,a6                       ; + 32000: the screen's end
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp                           ; drop the arguments
	move.w	d0,$b0.w                        ; $b0: the resolution
	cmp.w	#$2,d0                          ; high?
	beq.s	pack_v2_high                    ; yes
	move.l	#$a0,d0                         ; medium: 160 bytes a line
	move.l	d0,$a8.w                        ; $a8: the line length
	mulu.w	bar_offset,d0                   ; times the bar's distance from the bottom
	move.w	bar_column,d1                   ; the bar's column
	mulu.w	#$4,d1                          ; * 4 bytes
	move.l	#$a0,d2
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a6                           ; a6 = the bar's bottom on the screen
	move.w	bar_height,$ac.w                ; $ac: the bar's height
	bra.s	pack_v2_run
pack_v2_high:
	move.l	#$50,d0                         ; high: 80 bytes a line
	move.l	d0,$a8.w                        ; $a8: the line length
	mulu.w	bar_offset,d0                   ; times the bar's distance from the bottom
	move.w	bar_column,d1                   ; the bar's column
	mulu.w	#$2,d1                          ; * 2 bytes
	move.l	#$50,d2
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a6                           ; a6 = the bar's bottom on the screen
	move.w	bar_height,$ac.w                ; $ac: the bar's height
pack_v2_run:
	movea.l	#$0,a4                          ; no bar lines drawn
	movea.l	$90.w,a5                        ; a5 = the source
	move.l	$94.w,d0                        ; its length
	divu.w	$ac.w,d0                        ; / the bar's height
	move.w	d0,$a4.w                        ; $a4: the bytes a bar line stands for
	lea	pack_v2_sr(pc),a0
	move.w	sr,(a0)                         ; keep the status register
	move.w	#$2700,sr                       ; interrupts off
	bsr.w	pack_v2_crunch                  ; pack
	move.w	pack_v2_sr(pc),sr               ; the status register back
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	lea	pack_v2_length(pc),a0
	move.l	$9c.w,(a0)                      ; the packed length
	move.l	(sp)+,$b0.w                     ; the trap vectors back
	move.l	(sp)+,$ac.w
	move.l	(sp)+,$a8.w
	move.l	(sp)+,$a4.w
	move.l	(sp)+,$a0.w
	move.l	(sp)+,$9c.w
	move.l	(sp)+,$98.w
	move.l	(sp)+,$94.w
	move.l	(sp)+,$90.w
	move.l	pack_v2_ssp(pc),-(sp)           ; Super(old stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	pack_v2_length(pc),d0           ; the packed length
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Draw the packometer's bar up to the position reached: one line of it for each $a4 bytes.
;------------------------------------------------------------------------------
pack_v2_bar:	; from: pack_v2_crunch
	move.l	d0,-(sp)
	move.l	a0,d0                           ; the position
	sub.l	a5,d0                           ; less the start
	divu.w	$a4.w,d0                        ; in bar lines
pack_v2_bar_loop:
	cmpa.w	bar_height,a4                   ; the bar full?
	bge.s	pack_v2_bar_done                ; yes
	cmp.w	a4,d0                           ; drawn so far?
	bgt.s	pack_v2_bar_line                ; no: draw a line
pack_v2_bar_done:
	move.l	(sp)+,d0
	rts
pack_v2_bar_line:
	addq.w	#1,a4                           ; one more line
	move.w	#$ffff,(a6)                     ; a line of the bar
	move.w	#$ffff,2(a6)
	cmpi.w	#$2,$b0.w                       ; high resolution?
	beq.s	pack_v2_bar_up                  ; yes: 2 words
	move.w	#$ffff,4(a6)                    ; no: 4 words, all planes
	move.w	#$ffff,6(a6)
pack_v2_bar_up:
	suba.l	$a8.w,a6                        ; a line up
	bra.s	pack_v2_bar_loop
pack_v2_ssp:	; from: pack_v2
	dc.l	$00000000                       ; the stack Super returned
pack_v2_length:	; from: pack_v2
	dc.l	$00000000                       ; the packed length

;------------------------------------------------------------------------------
; The V2 packer, as Automation's: the source at $90, length at $94, to the destination at $98 as 'LSD!', the
; unpacked length, the packed length, then a bit stream read from the end down.  It looks up to the window
; ($a0) bytes ahead for the longest string equal to the one here (up to $3ff).  $80 holds the best length, $8c
; its offset, $9c the packed length at the end.
;------------------------------------------------------------------------------
pack_v2_crunch:	; from: pack_v2
	move.l	$94.w,d0                        ; the length
	movea.l	$90.w,a0                        ; the source
	lea	0(a0,d0.l),a2                   ; a2 = its end
	movea.l	$98.w,a1                        ; the destination
	addq.l	#8,a1                           ; past its 8 byte header
	clr.w	d5                              ; no literals yet
	moveq	#7,d6                           ; 8 bits to the byte
pack_v2_loop:
	bsr.s	pack_v2_bar                     ; the bar
	move.b	(a0),d0                         ; the byte to match
	move.w	#$1,$80.w                       ; best match 1
	moveq	#1,d1                           ; offset 1
	move.l	$a0.w,d2                        ; the window
pack_v2_search:
	cmp.b	0(a0,d1.w),d0                   ; the same first byte?
	bne.s	pack_v2_search_next             ; no: on
	movem.l	d0/a0-a3,-(sp)                  ; keep the registers
	clr.w	d0                              ; the match's length
	lea	0(a0,d1.w),a1                   ; the other string
	movea.l	a1,a3                           ; where it starts
pack_v2_compare:
	cmpm.b	(a0)+,(a1)+                     ; the same?
	bne.s	pack_v2_compare_done            ; no
	cmpa.l	a2,a1                           ; past the end?
	bhi.s	pack_v2_compare_done            ; yes
	cmpa.l	a3,a0                           ; into the other string?
	bhi.s	pack_v2_compare_done            ; yes
	addq.w	#1,d0                           ; one longer
	cmpi.w	#$3ff,d0                        ; at most $3ff
	bne.s	pack_v2_compare
pack_v2_compare_done:
	cmp.w	$80.w,d0                        ; longer than the best?
	ble.s	pack_v2_match_restore           ; no
	move.w	d0,$80.w                        ; yes: the best
	move.w	d1,$8c.w                        ; and its offset
pack_v2_match_restore:
	movem.l	(sp)+,d0/a0-a3                  ; the registers back
pack_v2_search_next:
	addq.w	#1,d1                           ; the next offset
	lea	0(a0,d1.w),a3
	cmpa.l	a2,a3                           ; past the end?
	dbeq	d2,pack_v2_search               ; on through the window
	move.w	$8c.w,d0                        ; the best offset
	move.w	$80.w,d1                        ; the best length
	sub.w	d1,d0                           ; the code's offset
	cmpi.w	#$1,d1                          ; 1: a literal
	beq.s	pack_v2_literal
	cmpi.w	#$2,d1                          ; 2?
	beq.s	pack_v2_short
	bsr.s	put_literal_count               ; the literals before it
	bsr.w	put_offset                      ; the offset
	bsr.w	put_length                      ; the length
	bra.s	pack_v2_coded
pack_v2_short:
	cmpi.w	#$23f,d0                        ; offset too large?
	bhi.s	pack_v2_literal                 ; yes: a literal
	bsr.s	put_literal_count               ; the literals before it
	bsr.w	put_short_offset                ; the short offset
	bsr.w	put_length                      ; the length
pack_v2_coded:
	moveq	#0,d5                           ; no literals
	move.w	$80.w,d0                        ; the length
	lea	0(a0,d0.w),a0                   ; skip the matched bytes
	bra.s	pack_v2_next
pack_v2_literal:
	move.b	(a0)+,(a1)+                     ; copy a literal
	addq.w	#1,d5                           ; count it
pack_v2_next:
	lea	-$1(a2),a3                      ; the last byte
	cmpa.l	a0,a3                           ; reached?
	bne.w	pack_v2_loop                    ; no: on
	move.b	(a0)+,(a1)+                     ; the last byte as a literal
	addq.w	#1,d5
	bsr.s	put_literal_count               ; the literals
	bset	d6,d7                           ; end marker bit
	move.b	d7,(a1)+                        ; the last bits
	clr.w	d1
	move.l	a1,d0                           ; the destination
	lsr.l	#1,d0                           ; odd?
	bcc.s	pack_v2_end                     ; no
	addq.w	#1,a1                           ; yes: a pad byte
	bset	#$f,d1                          ; and flag it
pack_v2_end:
	move.w	d1,(a1)+                        ; the pad flag word
	movea.l	$98.w,a0                        ; the header
	move.l	$94.w,(a0)                      ; the unpacked length
	suba.l	a0,a1
	move.l	a1,4(a0)                        ; the packed length
	move.l	a1,$9c.w                        ; is the result
	subq.l	#4,$98.w                        ; 4 bytes earlier
	move.l	#$4c534421,-$4(a0)              ; 'LSD!'
	addq.l	#4,$9c.w
	rts

;------------------------------------------------------------------------------
; The code writers: each sets d1 = the bits and d4 = their count - 1 and goes to put_bits.
;------------------------------------------------------------------------------
put_literal_count:	; from: pack_v2_crunch
	lea	pack_literal_table(pc),a3       ; the literal count table
	moveq	#5,d3
literal_range:
	move.b	0(a3,d3.w),d4
	ext.w	d4                              ; to a word
	cmp.w	d4,d5                           ; in this range?
	dbge	d3,literal_range                ; no: the one below
	sub.w	d4,d5                           ; less its start
	lsl.w	#1,d3                           ; * 2: words
	move.b	6(a3,d3.w),d2                   ; the bits for it
	ext.w	d2                              ; to a word
	moveq	#-1,d1
	lsl.l	d2,d1                           ; the prefix ones
	or.w	d5,d1                           ; the count
	clr.w	d4
	move.b	7(a3,d3.w),d4                   ; the bit count
	bra.s	put_bits                        ; write them

put_offset:	; from: pack_v2_crunch
	lea	pack_offset_table(pc),a3        ; the offset table
	moveq	#2,d3                           ; 3 ranges
offset_range:
	lsl.w	#1,d3                           ; * 2: words
	move.w	0(a3,d3.w),d4                   ; its start
	lsr.w	#1,d3
	cmp.w	d4,d0                           ; in this range?
	dbge	d3,offset_range                 ; no: the one below
	sub.w	d4,d0                           ; less its start
	lsl.w	#1,d3                           ; * 2: words
	move.w	6(a3,d3.w),d3                   ; bits and prefix
	move.w	d3,d4
	lsr.w	#8,d3                           ; the prefix length
	moveq	#-1,d1
	lsl.w	d3,d1
	or.w	d0,d1                           ; the offset
	andi.w	#$f,d4                          ; the bit count
	bra.s	put_bits                        ; write them

put_short_offset:	; from: pack_v2_crunch
	move.w	d0,d1
	cmpi.w	#$3f,d1                         ; 6 bits?
	ble.s	short_offset_6                  ; yes
	subi.w	#$40,d1                         ; no: 9 bits
	moveq	#9,d4
	bset	d4,d1                           ; and a 1
	bra.s	put_bits                        ; write them
short_offset_6:
	move.w	#$6,d4                          ; 6 bits + the 0
	bra.s	put_bits                        ; write them

put_length:	; from: pack_v2_crunch
	lea	pack_length_table(pc),a3        ; the length table
	move.w	$80.w,d0                        ; the length
	moveq	#4,d5
length_range:
	move.b	0(a3,d5.w),d4
	ext.w	d4                              ; to a word
	cmp.w	d4,d0                           ; in this range?
	dbge	d5,length_range                 ; no: the one below
	sub.w	d4,d0                           ; less its start
	move.b	5(a3,d5.w),d4                   ; its bits
	ext.w	d4                              ; to a word
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
	rts
pack_literal_table:	; from: put_literal_count
	dc.w	$0001,$0205,$080f,$0100,$0101,$0203,$0205,$0308 ; range starts, then prefix length and bit count
	dc.w	$0a12
pack_offset_table:	; from: put_offset
	dc.w	$0000,$0020,$0120,$0606,$0908,$0c0d ; range starts, then prefix length and bit count
pack_length_table:
	dc.b	$02,$03,$04,$06,$0a,$01,$01,$02,$03,$0a ; range starts, then bit counts
pack_v2_sr:	; from: pack_v2
	dc.w	$0000                           ; the status register while packing
	dc.w	$4cdf,$00f0,$4e5e,$4e75         ; not used: left-over code bytes

;------------------------------------------------------------------------------
; The V2.4 program stub ("JAM Packer Decrunch V2.4"), put in front of a program packed with V2: it clears the
; top of the screen and prints its title (unless Heading is off), depacks the program $400 bytes above its
; end flashing the background (unless Flash is off), relocates it to run where the stub's text is, sets the
; basepage, and runs a mover from the screen that copies it down, clears its BSS and $600 bytes more, clears
; the registers and starts it.  The packed data follows the stub at v24_stub+$2d0.
;------------------------------------------------------------------------------
v24_stub:	; from: write_program, pack_file, multi_pack_file
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; kept
	movea.l	d0,a2                           ; a2 = the screen
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp                           ; drop the arguments
	move.w	#$9f,d1                         ; 160 longs in high resolution
	cmp.b	#$2,d0                          ; high?
	beq.s	v24_stub_clear                  ; yes
	move.w	#$167,d1                        ; 360 longs otherwise
v24_stub_clear:	; from: set_stub_options
	clr.l	(a2)+                           ; clear the top of the screen (a nop without Heading)
	dbra	d1,v24_stub_clear
	lea	v24_title(pc),a1                ; the title
	move.b	#$3c,5(a1)                      ; column 28
	cmp.b	#$0,d0                          ; low resolution?
	bne.s	v24_stub_title                  ; no
	move.b	#$28,5(a1)                      ; yes: column 8
v24_stub_title:
	pea	v24_title(pc)                   ; the title
	move.w	#$9,-(sp)
v24_stub_print:	; from: set_stub_options
	trap	#1                              ; Cconws, Cconws (a nop without Heading)
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; kept
	move.w	$fff8240,-(sp)                  ; palette 0, keep the background colour
	lea	v24_stub+$2d0(pc),a0            ; a0 = the packed data
	movea.l	a0,a1
	adda.l	#$400,a1                        ; a1 = $400 above it
	movea.l	4(a0),a6
	bsr.w	v24_depack                      ; depack
	move.w	(sp)+,$fff8240                  ; palette 0, the colour back
	move.w	#$20,-(sp)                      ; Super(old stack)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	v24_stub+$2d0(pc),a3            ; the depacked program
	adda.l	#$400,a3                        ; $400 above the packed data
	movea.l	a3,a1
	movea.l	2(a3),a0                        ; its header's text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	adda.l	#$1c,a0                         ; + the header
	adda.l	a3,a0                           ; a0 = its relocation table
	lea	v24_stub(pc),a5                 ; where it will run: the stub's text
	move.l	a5,d0
	adda.l	#$1c,a1                         ; its text
	tst.l	(a0)                            ; any relocation?
	beq.s	v24_stub_relocated              ; no
	adda.l	(a0)+,a1                        ; the first address
v24_stub_relocate:
	add.l	d0,(a1)                         ; relocate a long
v24_stub_relocate_next:
	clr.l	d1
	move.b	(a0)+,d1                        ; the next step
	tst.w	d1                              ; the end?
	beq.s	v24_stub_relocated              ; yes
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	v24_stub_relocate_step          ; no
	adda.l	#$fe,a1                         ; yes
	bra.s	v24_stub_relocate_next
v24_stub_relocate_step:
	adda.l	d1,a1                           ; on to the next long
	bra.s	v24_stub_relocate               ; relocate it
v24_stub_relocated:
	suba.l	#$100,a5                        ; a5 = the basepage
	move.l	2(a3),$c(a5)                    ; text length
	move.l	6(a3),$14(a5)                   ; data length
	move.l	$a(a3),$1c(a5)                  ; BSS length
	move.l	8(a5),d0                        ; the text segment
	move.l	$c(a5),d1
	add.l	d0,d1
	move.l	d1,$10(a5)                      ; = the data segment
	move.l	$14(a5),d0
	add.l	d0,d1
	move.l	d1,$18(a5)                      ; = the BSS
	move.l	(sp)+,d0                        ; the screen
	add.l	#$7f00,d0                       ; + $7f00
	movea.l	d0,a2                           ; where the mover goes
	movea.l	d0,a5                           ; and runs
	move.w	#$40,d2                         ; 65 bytes
	lea	v24_stub_mover(pc),a1           ; the mover
v24_stub_copy_mover:
	move.b	(a1)+,(a2)+                     ; copied
	dbra	d2,v24_stub_copy_mover
	movea.l	a3,a1                           ; the depacked text
	adda.l	#$1c,a1
	lea	v24_stub(pc),a0                 ; where it runs
	movea.l	a0,a2
	jmp	(a5)                            ; run the mover
v24_stub_mover:
	move.l	(a1)+,(a2)+                     ; copy the program down
	cmpa.l	d1,a2                           ; to the BSS?
	ble.s	v24_stub_mover
	movea.l	4(sp),a1                        ; the basepage
	movea.l	$18(a1),a3                      ; its BSS
	move.l	$1c(a1),d1                      ; its length
	add.l	#$600,d1                        ; + $600
v24_stub_clear_bss:
	clr.b	(a3)+                           ; cleared
	subq.l	#1,d1
	bne.s	v24_stub_clear_bss
	clr.l	d1                              ; the registers cleared
	clr.l	d2
	clr.l	d3
	clr.l	d4
	clr.l	d5
	clr.l	d6
	clr.l	d7
	movea.l	d1,a1
	movea.l	d2,a2
	movea.l	d3,a3
	movea.l	d4,a4
	movea.l	d5,a5
	movea.l	d6,a6
	jmp	(a0)                            ; start the program

;------------------------------------------------------------------------------
; The stub's depacker: lsd_depack with the background colour rotating as it goes.
;------------------------------------------------------------------------------
v24_depack:	; from: v24_stub
	move.w	#$fe,d7                         ; the colour
	adda.l	#$4,a0                          ; past 'LSD!'
	movea.l	a0,a6                           ; a6 = the header
	move.l	(a0)+,d5                        ; d5 = the unpacked length
	adda.l	d5,a1                           ; a1 = the end of the output
	adda.l	(a0),a0                         ; + the packed length
	suba.l	#$4,a0
	tst.w	-(a0)                           ; the pad flag word
	bpl.s	v24_first_bits                  ; no pad byte
	subq.l	#1,a0                           ; a pad byte: skip it
v24_first_bits:
	move.b	-(a0),d0                        ; the first bits
v24_next:
	ror.w	#1,d7                           ; the next colour
v24_stub_flash:	; from: set_stub_options
	move.w	d7,$ffff8240                    ; palette 0, flash the background (a nop without Flash)
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_literal_bit                 ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_literal_bit:
	bcc.s	v24_string                      ; 0: no literals
	clr.w	d1                              ; one literal
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_literal_count_bit           ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_literal_count_bit:
	bcc.s	v24_copy_literals               ; 0: one literal
	lea	v24_literal_table(pc),a3        ; the literal count codes
	moveq	#3,d3                           ; 4 sizes
v24_literal_size:
	clr.w	d1
	move.b	0(a3,d3.w),d2                   ; its bits
	ext.w	d2                              ; to a word
	moveq	#-1,d4
	lsl.w	d2,d4
	not.w	d4                              ; the all-ones value
	subq.w	#1,d2
v24_literal_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_literal_bits_next           ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_literal_bits_next:
	roxl.w	#1,d1                           ; into d1
	dbra	d2,v24_literal_bits             ; for each bit
	tst.w	d3                              ; the last size?
	beq.s	v24_literal_base                ; yes
	cmp.w	d1,d4                           ; all ones: the next size
	dbne	d3,v24_literal_size
v24_literal_base:
	move.b	4(a3,d3.w),d2                   ; + the size's base
	ext.w	d2                              ; to a word
	add.w	d2,d1
v24_copy_literals:
	move.b	-(a0),-(a1)                     ; copy a literal
	dbra	d1,v24_copy_literals            ; for each literal
v24_string:
	movea.l	a6,a3                           ; the header
	addq.l	#8,a3                           ; + 8: the start of the bit stream
	cmpa.l	a3,a0                           ; reached?
	ble.w	v24_depack_done                 ; yes: done
	lea	v24_length_table(pc),a3         ; the length codes
	moveq	#3,d2                           ; up to 4 bits
v24_length_code:
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_length_code_bit             ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_length_code_bit:
	bcc.s	v24_length_found                ; 0: this code
	dbra	d2,v24_length_code
v24_length_found:
	clr.w	d1
	addq.w	#1,d2
	move.b	0(a3,d2.w),d3                   ; its extra bits
	beq.s	v24_length_base                 ; none
	ext.w	d3                              ; to a word
	subq.w	#1,d3
v24_length_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_length_bits_next            ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_length_bits_next:
	roxl.w	#1,d1                           ; into d1
	dbra	d3,v24_length_bits              ; for each bit
v24_length_base:
	move.b	5(a3,d2.w),d3                   ; + the base length
	ext.w	d3                              ; to a word
	add.w	d3,d1
	cmpi.w	#$2,d1                          ; length 2?
	beq.s	v24_short_offset                ; yes: a short offset
	lea	v24_offset_table(pc),a3         ; the offset codes
	moveq	#1,d3                           ; up to 2 bits
v24_offset_code:
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_offset_code_bit             ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_offset_code_bit:
	bcc.s	v24_offset_found                ; 0: this code
	dbra	d3,v24_offset_code
v24_offset_found:
	addq.w	#1,d3
	clr.w	d2
	move.b	0(a3,d3.w),d4                   ; its bits
	ext.w	d4                              ; to a word
v24_offset_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_offset_bits_next            ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_offset_bits_next:
	roxl.w	#1,d2                           ; into d2
	dbra	d4,v24_offset_bits              ; for each bit
	lsl.w	#1,d3                           ; words
	add.w	4(a3,d3.w),d2                   ; + the base offset
	bra.s	v24_copy_string
v24_short_offset:
	clr.w	d2
	moveq	#5,d3                           ; 6 bits
	clr.w	d4                              ; base 0
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_short_offset_bit            ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_short_offset_bit:
	bcc.s	v24_short_offset_bits           ; 0: 6 bits
	moveq	#8,d3                           ; 1: 9 bits
	moveq	#64,d4                          ; base 64
v24_short_offset_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	v24_short_offset_next           ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v24_short_offset_next:
	roxl.w	#1,d2                           ; into d2
	dbra	d3,v24_short_offset_bits        ; for each bit
	add.w	d4,d2                           ; + the base
v24_copy_string:
	lea	0(a1,d2.w),a2                   ; the string's source
	ext.l	d1                              ; to a long
	adda.l	d1,a2                           ; + the length
	subq.w	#1,d1
v24_copy_string_loop:
	move.b	-(a2),-(a1)                     ; copy it
	dbra	d1,v24_copy_string_loop         ; for each byte
	bra.w	v24_next                        ; and on
v24_depack_done:
	rts
v24_literal_table:
	dc.b	$0a,$03,$02,$02,$0e,$07,$04,$01 ; bits, then base counts less 1
v24_length_table:
	dc.b	$0a,$02,$01,$00,$00,$0a,$06,$04,$03,$02 ; extra bits, then base lengths
v24_offset_table:
	dc.b	$0b,$04,$07,$00                 ; bits, then base offsets
	dc.w	$0120,$0000,$0020,$0000
v24_title:	; from: v24_stub
	dc.b	27,'j',27,'Y  JAM Packer Decrunch V2.4',27,'k',0 ; save the cursor, cursor to row 0 and the column, the
                                                ;   title, restore the cursor
	dc.b	$00

;------------------------------------------------------------------------------
; multi_pack(source, destination, programs): pack every file of the source path (it ends "*.*") into the
; destination folder under the same name.  Files left alone are noted with the reason, and when there are
; any a text report is shown at the end, 16 lines a page.
;------------------------------------------------------------------------------
multi_pack:	; from: main, v24_stub, write_program, pack_file, multi_pack_file
	link	a6,#-444                        ; 444 bytes of locals
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	clr.w	report_count                    ; no files noted
	move.w	#$1,multi_active                ; multi packing
	move.w	#$2f,-(sp)                      ; Fgetdta
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,-$4(a6)                      ; kept
	pea	-$1bc(a6)                       ; a DTA of our own
	move.w	#$1a,-(sp)                      ; Fsetdta
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	8(a6),-(sp)                     ; the source path
	pea	-$190(a6)                       ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	clr.w	-(sp)                           ; normal files
	pea	-$190(a6)                       ; the path
	move.w	#$4e,-(sp)                      ; Fsfirst
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.l	$c(a6),-(sp)                    ; the destination
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,-$c(a6)
	move.w	-$c(a6),d0
	subq.w	#3,d0                           ; less 3
	movea.l	$c(a6),a0
	clr.b	0(a0,d0.w)                      ; "*.*" cut off
	move.l	8(a6),-(sp)                     ; the source
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,-$c(a6)
	move.w	-$c(a6),d0
	subq.w	#3,d0                           ; less 3
	movea.l	8(a6),a0
	clr.b	0(a0,d0.w)                      ; "*.*" cut off
	move.l	$c(a6),-(sp)                    ; the destination folder
	pea	-$90(a6)                        ; kept
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.l	8(a6),-(sp)                     ; the source folder
	pea	-$110(a6)                       ; kept
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$19e(a6)                       ; the name found
	move.l	$c(a6),-(sp)                    ; after the destination folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	-$19e(a6)                       ; the name found
	move.l	8(a6),-(sp)                     ; after the source folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.w	$10(a6),-(sp)                   ; programs?
	move.l	-$1a2(a6),-(sp)                 ; the length found
	pea	-$19e(a6)                       ; the name
	move.l	$c(a6),-(sp)                    ; the destination
	move.l	8(a6),-(sp)                     ; the source
	jsr	multi_pack_one                  ; pack it
	lea	$12(sp),sp                      ; drop the arguments
	bra.s	multi_pack_fsnext
multi_pack_next:
	pea	-$90(a6)                        ; the destination folder
	move.l	$c(a6),-(sp)                    ; back
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$110(a6)                       ; the source folder
	move.l	8(a6),-(sp)                     ; back
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$19e(a6)                       ; the name found
	move.l	$c(a6),-(sp)                    ; after the destination folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	-$19e(a6)                       ; the name found
	move.l	8(a6),-(sp)                     ; after the source folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.w	$10(a6),-(sp)                   ; programs?
	move.l	-$1a2(a6),-(sp)                 ; the length found
	pea	-$19e(a6)                       ; the name
	move.l	$c(a6),-(sp)                    ; the destination
	move.l	8(a6),-(sp)                     ; the source
	jsr	multi_pack_one                  ; pack it
	lea	$12(sp),sp                      ; drop the arguments
multi_pack_fsnext:
	move.w	#$4f,-(sp)                      ; Fsnext
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	move.w	d0,-$a(a6)
	tst.w	d0                              ; another?
	beq.s	multi_pack_next                 ; yes
	move.l	-$4(a6),-(sp)                   ; the old DTA
	move.w	#$1a,-(sp)                      ; Fsetdta
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	clr.w	multi_active                    ; no longer multi packing
	tst.w	report_count                    ; any noted?
	beq.w	multi_pack_done                 ; no
	move.w	vdi_handle,-(sp)                ; the text screen
	jsr	v_exit_cur
	addq.l	#2,sp                           ; drop the arguments
	clr.w	-$e(a6)                         ; the page's first
	clr.w	-$10(a6)                        ; the line
	bra.w	report_pages_loop
report_page:
	pea	text_report_title               ; "****** MULTI PACKER REPORT ******"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	text_report_heading             ; the column headings
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.w	report_lines_loop
report_line:
	pea	text_report_indent              ; the indent
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	-$e(a6),d0                      ; the entry
	add.w	-$10(a6),d0
	muls.w	#$14,d0                         ; 20 bytes a name
	lea	report_names,a0                 ; the names
	ext.l	d0                              ; to a long
	add.l	a0,d0
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	-$e(a6),d0                      ; the entry
	add.w	-$10(a6),d0
	muls.w	#$14,d0
	lea	report_names,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	cmpi.w	#$8,d0                          ; 8 or less?
	bgt.s	report_long_name                ; no
	pea	text_report_tabs_short_name     ; two tabs
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.s	report_reason
report_long_name:
	pea	text_report_tabs_long_name      ; one tab
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_reason:
	move.w	-$e(a6),d0                      ; the entry
	add.w	-$10(a6),d0
	asl.w	#1,d0                           ; words
	lea	report_reasons,a0               ; the reasons
	cmpi.w	#$5,0(a0,d0.w)                  ; 5?
	bne.s	report_reason_4                 ; no
	pea	text_reason_too_small           ; "Too small - not worth compacting"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_reason_4:
	move.w	-$e(a6),d0
	add.w	-$10(a6),d0
	asl.w	#1,d0                           ; * 2: words
	lea	report_reasons,a0
	cmpi.w	#$4,0(a0,d0.w)                  ; 4?
	bne.s	report_reason_2                 ; no
	pea	text_reason_larger              ; "Packed file larger than original"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_reason_2:
	move.w	-$e(a6),d0
	add.w	-$10(a6),d0
	asl.w	#1,d0                           ; * 2: words
	lea	report_reasons,a0
	cmpi.w	#$2,0(a0,d0.w)                  ; 2?
	bne.s	report_reason_3                 ; no
	pea	text_reason_read_error          ; "Error reading source file"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_reason_3:
	move.w	-$e(a6),d0
	add.w	-$10(a6),d0
	asl.w	#1,d0                           ; * 2: words
	lea	report_reasons,a0
	cmpi.w	#$3,0(a0,d0.w)                  ; 3?
	bne.s	report_reason_1                 ; no
	pea	text_reason_write_error         ; "Error writing destination file"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_reason_1:
	move.w	-$e(a6),d0
	add.w	-$10(a6),d0
	asl.w	#1,d0                           ; * 2: words
	lea	report_reasons,a0
	cmpi.w	#$1,0(a0,d0.w)                  ; 1?
	bne.s	report_reason_0                 ; no
	pea	text_reason_no_memory           ; "Not enough memory to pack file"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_reason_0:
	move.w	-$e(a6),d0
	add.w	-$10(a6),d0
	asl.w	#1,d0                           ; * 2: words
	lea	report_reasons,a0
	tst.w	0(a0,d0.w)                      ; 0?
	bne.s	report_next_line                ; no
	pea	text_reason_program             ; "Program file"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_next_line:
	addq.w	#1,-$10(a6)                     ; the next line
report_lines_loop:
	cmpi.w	#$10,-$10(a6)                   ; 16 lines?
	bge.s	report_page_end                 ; yes
	move.w	-$e(a6),d0
	add.w	-$10(a6),d0
	cmp.w	report_count,d0                 ; all shown?
	blt.w	report_line                     ; no: on
report_page_end:
	pea	text_press_return               ; "Press RETURN to continue"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	lea	iob,a0                          ; stdin
	subq.w	#1,4(a0)                        ; getc
	move.w	4(a0),d0
	tst.w	d0
	blt.s	report_getc
	movea.l	iob,a0
	addq.l	#1,iob
	move.b	(a0),d0
	ext.w	d0                              ; to a word
	and.w	#$ff,d0
	bra.s	report_next_page
report_getc:
	pea	iob                             ; argument 1
	jsr	getc
	addq.l	#4,sp                           ; drop the arguments
report_next_page:
	addi.w	#$10,-$e(a6)                    ; 16 on
	clr.w	-$10(a6)                        ; line 0
report_pages_loop:
	move.w	-$e(a6),d0
	cmp.w	report_count,d0                 ; all shown?
	ble.w	report_page                     ; no
	move.w	vdi_handle,-(sp)                ; back to GEM
	jsr	v_enter_cur
	addq.l	#2,sp                           ; drop the arguments
multi_pack_done:
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; multi_pack_one(source, destination, name, length, programs): files over 512 bytes are packed, programs only
; when programs is set; the rest are noted (0 a program left alone, 5 too small).
;------------------------------------------------------------------------------
multi_pack_one:	; from: multi_pack
	link	a6,#-8                          ; 8 bytes of locals
	move.l	$10(a6),-(sp)                   ; the name
	jsr	is_program_name                 ; a program name?
	addq.l	#4,sp                           ; drop the arguments
	move.l	d0,-$4(a6)
	cmpi.l	#$200,$14(a6)                   ; over 512 bytes?
	ble.w	multi_pack_one_small            ; no
	cmpi.l	#$ffffffff,-$4(a6)              ; a program?
	bne.s	multi_pack_one_data             ; no
	tst.w	$18(a6)                         ; packing programs?
	beq.s	multi_pack_one_data             ; no
	move.l	$10(a6),-(sp)                   ; the name
	move.w	#$1,-(sp)                       ; a program
	move.l	$14(a6),-(sp)                   ; the length
	move.l	$c(a6),-(sp)                    ; the destination
	move.l	8(a6),-(sp)                     ; the source
	jsr	multi_pack_file                 ; pack it
	lea	$12(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the result
	move.l	-$8(a6),-(sp)                   ; argument 2
	move.l	$10(a6),-(sp)                   ; the name
	jsr	note_file                       ; noted when it failed
	addq.l	#8,sp                           ; drop the arguments
	bra.s	multi_pack_one_done
multi_pack_one_data:
	cmpi.l	#$ffffffff,-$4(a6)              ; a program?
	beq.s	multi_pack_one_program          ; yes: left alone
	move.l	$10(a6),-(sp)                   ; the name
	clr.w	-(sp)                           ; data
	move.l	$14(a6),-(sp)                   ; the length
	move.l	$c(a6),-(sp)                    ; the destination
	move.l	8(a6),-(sp)                     ; the source
	jsr	multi_pack_file                 ; pack it
	lea	$12(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the result
	move.l	-$8(a6),-(sp)                   ; argument 2
	move.l	$10(a6),-(sp)                   ; the name
	jsr	note_file                       ; noted when it failed
	addq.l	#8,sp                           ; drop the arguments
	bra.s	multi_pack_one_done
multi_pack_one_program:
	clr.l	-(sp)                           ; 0: a program
	move.l	$10(a6),-(sp)                   ; the name
	jsr	note_file                       ; noted
	addq.l	#8,sp                           ; drop the arguments
multi_pack_one_done:
	bra.s	multi_pack_one_end
multi_pack_one_small:
	cmpi.l	#$ffffffff,-$4(a6)              ; a program?
	bne.s	multi_pack_one_too_small        ; no
	tst.w	$18(a6)                         ; packing programs?
	bne.s	multi_pack_one_too_small        ; yes
	clr.l	-(sp)                           ; no: 0, a program
	move.l	$10(a6),-(sp)                   ; the name
	jsr	note_file                       ; noted
	addq.l	#8,sp                           ; drop the arguments
	bra.s	multi_pack_one_end
multi_pack_one_too_small:
	move.l	#$5,-(sp)                       ; 5: too small
	move.l	$10(a6),-(sp)                   ; the name
	jsr	note_file                       ; noted
	addq.l	#8,sp                           ; drop the arguments
multi_pack_one_end:
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; note_file(name, result): results 0-4 are noted for the report, 5 (too small) only for the first 101.  Other
; results are packed lengths: nothing to note.
;------------------------------------------------------------------------------
note_file:	; from: multi_pack_one
	link	a6,#-2                          ; 2 bytes of locals
	tst.l	$c(a6)                          ; 0?
	beq.s	note_file_store                 ; yes
	cmpi.l	#$4,$c(a6)                      ; 4?
	beq.s	note_file_store                 ; yes
	cmpi.l	#$3,$c(a6)                      ; 3?
	beq.s	note_file_store                 ; yes
	cmpi.l	#$2,$c(a6)                      ; 2?
	beq.s	note_file_store                 ; yes
	cmpi.l	#$1,$c(a6)                      ; 1?
	beq.s	note_file_store                 ; yes
	cmpi.l	#$5,$c(a6)                      ; 5?
	bne.s	note_file_done                  ; no: packed
	cmpi.w	#$64,report_count               ; 100 noted already?
	bgt.s	note_file_done                  ; yes: not noted
note_file_store:
	move.l	$c(a6),d0                       ; the reason
	move.w	d0,-$2(a6)
	move.l	8(a6),-(sp)                     ; the name
	move.w	report_count,d1                 ; the next entry
	muls.w	#$14,d1                         ; 20 bytes a name
	lea	report_names,a0                 ; the names
	ext.l	d1                              ; to a long
	add.l	a0,d1
	move.l	#$0,d0
	add.l	d1,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	report_count,d0                 ; the entry
	asl.w	#1,d0                           ; words
	lea	report_reasons,a0               ; the reasons
	move.w	-$2(a6),0(a0,d0.w)              ; its reason
	addq.w	#1,report_count                 ; one more
note_file_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; is_program_name(name): -1 when it ends PRG, TOS or TTP, else 0.
;------------------------------------------------------------------------------
is_program_name:	; from: multi_pack_one
	link	a6,#-2                          ; 2 bytes of locals
	move.l	8(a6),-(sp)                     ; the name
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,-$2(a6)
	move.w	-$2(a6),d0
	subq.w	#3,d0                           ; less 3: the extension
	move.w	d0,-$2(a6)
	move.w	#$3,-(sp)                       ; 3 characters
	pea	text_prg                        ; "PRG"
	move.w	-$2(a6),d0
	ext.l	d0                              ; to a long
	add.l	8(a6),d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	strncmp
	lea	$a(sp),sp                       ; drop the arguments
	tst.w	d0                              ; the same?
	beq.s	is_program_name_yes             ; yes
	move.w	#$3,-(sp)                       ; 3 characters
	pea	text_tos                        ; "TOS"
	move.w	-$2(a6),d0
	ext.l	d0                              ; to a long
	add.l	8(a6),d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	strncmp
	lea	$a(sp),sp                       ; drop the arguments
	tst.w	d0                              ; the same?
	beq.s	is_program_name_yes             ; yes
	move.w	#$3,-(sp)                       ; 3 characters
	pea	text_ttp                        ; "TTP"
	move.w	-$2(a6),d0
	ext.l	d0                              ; to a long
	add.l	8(a6),d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	strncmp
	lea	$a(sp),sp                       ; drop the arguments
	tst.w	d0                              ; the same?
	bne.s	is_program_name_no              ; no
is_program_name_yes:
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.s	is_program_name_done
is_program_name_no:
	move.w	#$0,d0                          ; 0
	ext.l	d0                              ; to a long
is_program_name_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; unpack_file(name): look in the first 2 K for 'LSD!', 'AUTM' or 'LZH!'.  When there is one the file is
; loaded from it, depacked with V2 or LZH, and saved under a name chosen.  d0 = -1 when the file is not packed.
;------------------------------------------------------------------------------
unpack_file:	; from: pack_one_file
	link	a6,#-26                         ; 26 bytes of locals
	move.l	#$800,-(sp)                     ; 2 K
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$4(a6)                      ; the buffer
	move.l	#$800,-(sp)                     ; 2 K
	move.l	-$4(a6),-(sp)                   ; into the buffer
	move.l	8(a6),-(sp)                     ; the file
	jsr	load_file                       ; load it
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$ffffffff,d0                   ; failed?
	beq.s	unpack_file_failed              ; yes
	move.l	-$4(a6),-(sp)                   ; the buffer
	jsr	find_packed                     ; find the packed data
	addq.l	#4,sp                           ; drop the arguments
	move.l	d0,-$8(a6)
	cmpi.l	#$ffffffff,-$8(a6)              ; found?
	bne.s	unpack_file_found               ; yes
	move.w	#$ffff,d0                       ; no: -1
	ext.l	d0                              ; to a long
	bra.w	unpack_file_done
unpack_file_found:
	bra.s	unpack_file_packed
unpack_file_failed:
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.w	unpack_file_done
unpack_file_packed:
	move.l	-$8(a6),-(sp)                   ; the packed data
	jsr	packed_algorithm                ; which algorithm
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,-$1a(a6)
	move.l	-$8(a6),d0
	sub.l	-$4(a6),d0                      ; less the buffer: its offset in the file
	move.l	d0,-$c(a6)
	move.l	-$8(a6),-(sp)                   ; argument 1
	jsr	unpacked_length                 ; its unpacked length
	addq.l	#4,sp                           ; drop the arguments
	move.l	d0,-$10(a6)
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	-$10(a6),d0                     ; the unpacked length
	add.l	#$200,d0                        ; + 512
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$4(a6)                      ; the buffer
	clr.w	-(sp)                           ; read only
	move.l	8(a6),-(sp)                     ; the file
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,-$16(a6)                     ; the handle
	clr.w	-(sp)                           ; from the start
	move.w	-$16(a6),-(sp)                  ; argument 2
	move.l	-$c(a6),-(sp)                   ; to the packed data
	move.w	#$42,-(sp)                      ; Fseek
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	move.l	d0,-$14(a6)
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.l	#$f4240,-(sp)                   ; up to a million bytes
	move.w	-$16(a6),-(sp)                  ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$14(a6)
	move.w	-$16(a6),-(sp)                  ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	pea	text_decrunching                ; "Decrunching File...."
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	cmpi.w	#$1,-$1a(a6)                    ; V2?
	bne.s	unpack_file_lzh                 ; no
	move.l	-$4(a6),d0                      ; the packed data
	add.l	#$100,d0                        ; + 256: where it depacks to
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$4(a6),-(sp)                   ; argument 1
	jsr	depack_v2                       ; depack it
	addq.l	#8,sp                           ; drop the arguments
	bra.s	unpack_file_save
unpack_file_lzh:
	move.l	-$4(a6),d0                      ; the packed data
	add.l	#$100,d0                        ; + 256
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$4(a6),-(sp)                   ; argument 1
	jsr	depack_lzh                      ; depack it
	addq.l	#8,sp                           ; drop the arguments
unpack_file_save:
	pea	text_supply_save_path           ; "Supply the SAVE path and file name"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	save_name                       ; the path chosen
	pea	pack_file_name                  ; the name
	pea	destination_path                ; the destination path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	move.w	d0,-$18(a6)
	cmpi.w	#$ffff,-$18(a6)                 ; OK?
	beq.s	unpack_file_free                ; no
	move.l	-$4(a6),d0                      ; the depacked data
	add.l	#$100,d0
	move.l	d0,-(sp)                        ; argument 3
	move.l	-$10(a6),-(sp)                  ; its length
	pea	save_name                       ; the file
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
unpack_file_free:
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
unpack_file_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; packed_algorithm(data): 1 for 'LSD!' or 'AUTM' (V2), 2 otherwise (LZH).
;------------------------------------------------------------------------------
packed_algorithm:	; from: unpack_file
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.l	8(a6),d7
	movea.l	d7,a1
	move.l	(a1),d1                         ; the magic
	cmp.l	#$4c534421,d1                   ; 'LSD!'?
	beq.s	packed_algorithm_v2             ; yes
	cmp.l	#$4155544d,d1                   ; 'AUTM'?
	beq.s	packed_algorithm_v2             ; yes
	move.l	#$2,d0                          ; 2: LZH
	bra.s	packed_algorithm_done
packed_algorithm_v2:
	move.l	#$1,d0                          ; 1: V2
packed_algorithm_done:
	unlk	a6                              ; the frame back
	rts
	movem.l	(sp)+,d7                        ; not reached
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; unpacked_length(data): the long after the magic.
;------------------------------------------------------------------------------
unpacked_length:	; from: unpack_file
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.l	8(a6),d7
	movea.l	d7,a1
	move.l	4(a1),d0
	unlk	a6                              ; the frame back
	rts
	movem.l	(sp)+,d7                        ; not reached
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; find_packed(buffer): the address of the first 'LSD!', 'AUTM' or 'LZH!' among the first $401 words, or -1.
;------------------------------------------------------------------------------
find_packed:	; from: unpack_file
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.l	8(a6),d7
	movea.l	d7,a1
	move.l	#$400,d2                        ; $401 words
find_packed_loop:
	move.l	(a1),d1
	cmp.l	#$4c534421,d1                   ; 'LSD!'?
	beq.s	find_packed_done                ; yes
	cmp.l	#$4155544d,d1                   ; 'AUTM'?
	beq.s	find_packed_done                ; yes
	cmp.l	#$4c5a4821,d1                   ; 'LZH!'?
	beq.s	find_packed_done                ; yes
	adda.l	#$2,a1                          ; the next word
	dbra	d2,find_packed_loop
	movea.l	#$ffffffff,a1                   ; not found: -1
find_packed_done:
	move.l	a1,d0
	unlk	a6                              ; the frame back
	rts
	movem.l	(sp)+,d7                        ; not reached
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Patch both program stubs for the Flash and Heading check boxes: without Flash their colour writes become
; nops, without Heading their screen clearing and title printing do.  The original instructions are kept
; below as patterns.
;------------------------------------------------------------------------------
set_stub_options:	; from: write_program
	link	a6,#-32                         ; 32 bytes of locals
	tst.w	flash_flag                      ; Flash?
	bne.s	set_stub_flash                  ; yes
	lea	v24_stub_flash,a0               ; the V2.4 stub's colour write
	move.l	a0,-$4(a6)
	lea	v30_stub_flash,a0               ; the V3.0 stub's
	move.l	a0,-$8(a6)
	movea.l	-$4(a6),a0
	move.w	#$4e71,(a0)+                    ; nops
	move.w	#$4e71,(a0)+
	move.w	#$4e71,(a0)+
	movea.l	-$8(a6),a0
	move.w	#$4e71,(a0)+                    ; nops
	move.w	#$4e71,(a0)+
	move.w	#$4e71,(a0)+
	bra.s	set_stub_heading
set_stub_flash:
	lea	v24_stub_flash,a0               ; the V2.4 stub's colour write
	move.l	a0,-$c(a6)
	lea	v30_stub_flash,a0               ; the V3.0 stub's
	move.l	a0,-$10(a6)
	movea.l	-$c(a6),a0
	lea	flash_pattern_v24(pc),a1        ; its pattern
	move.w	(a1)+,(a0)+                     ; put back
	move.w	(a1)+,(a0)+
	move.w	(a1)+,(a0)+
	movea.l	-$10(a6),a0
	lea	flash_pattern_v30(pc),a1        ; its pattern
	move.w	(a1)+,(a0)+                     ; put back
	move.w	(a1)+,(a0)+
	move.w	(a1)+,(a0)+
	bra.s	set_stub_heading
flash_pattern_v24:
	move.w	d7,$ffff8240                    ; palette 0, the V2.4 stub's colour write
flash_pattern_v30:
	move.w	d3,$ffff8240                    ; palette 0, the V3.0 stub's
set_stub_heading:
	tst.w	heading_flag                    ; Heading?
	bne.s	set_stub_heading_on             ; yes
	lea	v24_stub_clear,a0               ; the V2.4 stub's screen clear
	move.l	a0,-$14(a6)
	lea	v30_stub_clear,a0               ; the V3.0 stub's
	move.l	a0,-$18(a6)
	movea.l	-$14(a6),a0
	move.w	#$4e71,(a0)                     ; a nop
	movea.l	-$18(a6),a0
	move.w	#$4e71,(a0)                     ; a nop
	lea	v24_stub_print,a0               ; the V2.4 stub's title trap
	move.l	a0,-$14(a6)
	lea	v30_stub_print,a0               ; the V3.0 stub's
	move.l	a0,-$18(a6)
	movea.l	-$14(a6),a0
	move.w	#$4e71,(a0)                     ; a nop
	movea.l	-$18(a6),a0
	move.w	#$4e71,(a0)                     ; a nop
	bra.s	set_stub_options_done
set_stub_heading_on:
	lea	v24_stub_clear,a0               ; the V2.4 stub's screen clear
	move.l	a0,-$1c(a6)
	lea	v30_stub_clear,a0               ; the V3.0 stub's
	move.l	a0,-$20(a6)
	movea.l	-$1c(a6),a0
	lea	clear_pattern(pc),a1            ; the pattern
	move.w	(a1),(a0)                       ; put back
	movea.l	-$20(a6),a0
	move.w	(a1),(a0)                       ; put back
	bra.s	set_stub_heading_trap
clear_pattern:
	clr.l	(a2)+                           ; the stubs' screen clear
set_stub_heading_trap:
	lea	v24_stub_print,a0               ; the V2.4 stub's title trap
	move.l	a0,-$1c(a6)
	lea	v30_stub_print,a0               ; the V3.0 stub's
	move.l	a0,-$20(a6)
	movea.l	-$1c(a6),a0
	move.w	#$4e41,(a0)                     ; trap #1 again
	movea.l	-$20(a6),a0
	move.w	#$4e41,(a0)                     ; trap #1 again
set_stub_options_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; write_program(name, length, data): write a packed program: a PRG header whose text is the stub and the
; packed data, the stub (V2.4 for V2, V3.0 for LZH, with the options patched in), the data and a 0 long for the
; relocation table.  d0 = 0, or -1 on error.
;------------------------------------------------------------------------------
write_program:	; from: pack_file, multi_pack_file
	link	a6,#-36                         ; 36 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.l	$c(a6),d7                       ; the length
	move.l	$10(a6),d6                      ; the data
	clr.l	-$20(a6)                        ; the relocation long: 0
	pea	text_saving_executable          ; "Saving Executable File"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	jsr	set_stub_options                ; patch the stubs
	move.w	#$601a,-$2(a6)                  ; the magic $601a
	clr.w	d5                              ; the rest of the header cleared
	bra.s	write_program_clear_loop
write_program_clear:
	move.w	d5,d0
	asl.w	#1,d0                           ; * 2: words
	lea	-$18(a6),a0
	clr.w	0(a0,d0.w)
	addq.w	#1,d5
write_program_clear_loop:
	cmpi.w	#$b,d5
	blt.s	write_program_clear
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	write_program_v30               ; no
	lea	v24_stub+$2d0,a0                ; the V2.4 stub's end
	move.l	a0,d4
	lea	v24_stub,a0                     ; less its start
	sub.l	a0,d4                           ; = its length
	bra.s	write_program_length
write_program_v30:
	lea	v30_stub+$476,a0                ; the V3.0 stub's end
	move.l	a0,d4
	lea	v30_stub,a0                     ; less its start
	sub.l	a0,d4                           ; = its length
write_program_length:
	move.l	d4,d0                           ; the stub's length
	add.l	d7,d0                           ; + the data's
	move.l	d0,-$1c(a6)                     ; is the text length
	move.l	-$1c(a6),-$24(a6)
	clr.w	-(sp)                           ; normal file
	move.l	8(a6),-(sp)                     ; the name
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d5                           ; the handle
	tst.w	d5                              ; created?
	bge.s	write_program_magic             ; yes
	move.w	#$ffff,d0                       ; no: -1
	ext.l	d0                              ; to a long
	bra.w	write_program_done
write_program_magic:
	pea	-$2(a6)                         ; the magic
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; written?
	beq.s	write_program_text_length       ; yes
	move.w	d5,-(sp)                        ; no: closed
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.w	write_program_done
write_program_text_length:
	pea	-$24(a6)                        ; the text length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	write_program_header_rest       ; yes
	move.w	d5,-(sp)                        ; no: closed
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.w	write_program_done
write_program_header_rest:
	pea	-$18(a6)                        ; the rest of the header
	move.l	#$16,-(sp)                      ; 22 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$16,d0                         ; written?
	beq.s	write_program_stub              ; yes
	move.w	d5,-(sp)                        ; no: closed
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.w	write_program_done
write_program_stub:
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	write_program_v30_stub          ; no
	pea	v24_stub                        ; the V2.4 stub
	move.l	d4,-(sp)                        ; its length
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	d4,d0                           ; written?
	beq.s	write_program_v24_written       ; yes
	move.w	d5,-(sp)                        ; no: closed
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.w	write_program_done
write_program_v24_written:
	bra.s	write_program_data
write_program_v30_stub:
	pea	v30_stub                        ; the V3.0 stub
	move.l	d4,-(sp)                        ; its length
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	d4,d0                           ; written?
	beq.s	write_program_data              ; yes
	move.w	d5,-(sp)                        ; no: closed
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.s	write_program_done
write_program_data:
	move.l	d6,-(sp)                        ; the data
	move.l	d7,-(sp)                        ; its length
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	d7,d0                           ; written?
	beq.s	write_program_relocation        ; yes
	move.w	d5,-(sp)                        ; no: closed
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.s	write_program_done
write_program_relocation:
	pea	-$20(a6)                        ; the 0 long
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	write_program_close             ; yes
	move.w	d5,-(sp)                        ; no: closed
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.s	write_program_done
write_program_close:
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$0,d0                          ; 0
	ext.l	d0                              ; to a long
write_program_done:
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; pack_file(name, length, program, shown name): load the file and pack it with V2 or LZH, drawing the
; packometer and the pack info.  When it got smaller (the stub and header counted for a program) the sizes are
; shown and it is saved under a name chosen.  d0 = 1 no memory, 2 read error, 3 save given up, 4 not smaller,
; 0 cancelled, otherwise the packed length.
;------------------------------------------------------------------------------
pack_file:	; from: pack_one_file
	link	a6,#-20                         ; 20 bytes of locals
	move.l	$c(a6),d0                       ; the length
	add.l	#$1388,d0                       ; + 5000
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$c(a6)                      ; the buffer
	tst.l	-$c(a6)                         ; got it?
	bne.s	pack_file_buffer                ; yes
	move.w	#$1,d0                          ; no: 1
	ext.l	d0                              ; to a long
	bra.w	pack_file_done
	bra.w	pack_file_free
pack_file_buffer:
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	clr.w	-(sp)                           ; from the root
	move.l	tree_packometer,-(sp)           ; the packometer
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.l	$c(a6),-(sp)                    ; the length
	move.l	$12(a6),-(sp)                   ; the shown name
	jsr	show_crunching                  ; into the pack info
	addq.l	#8,sp                           ; drop the arguments
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$c(a6),d0                      ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 2
	move.l	8(a6),-(sp)                     ; the file
	jsr	load_file                       ; load it
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$ffffffff,d0                   ; failed?
	beq.w	pack_file_read_error            ; yes: 2
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	pack_file_lzh                   ; no
	move.l	v2_window,-(sp)                 ; the window
	move.l	-$c(a6),d0                      ; the buffer + 4: where it packs to
	addq.l	#4,d0
	move.l	d0,-(sp)
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_v2                         ; pack it
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	bra.s	pack_file_packed
pack_file_lzh:
	pea	-$10(a6)                        ; the packed data's address comes back here
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzh                        ; pack it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
pack_file_packed:
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	pea	text_pack_complete              ; "Pack Complete!"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	cmpi.w	#$1,$10(a6)                     ; a program?
	bne.s	pack_file_check_data            ; no
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	pack_file_check_data            ; no
	lea	v24_stub+$2d0,a0                ; the V2.4 stub's end
	move.l	a0,d1
	lea	v24_stub,a0                     ; less its start
	sub.l	a0,d1                           ; = its length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	add.l	d1,d0                           ; + the stub
	cmp.l	$c(a6),d0                       ; smaller?
	blt.s	pack_file_smaller               ; yes
pack_file_check_data:
	tst.w	$10(a6)                         ; data?
	bne.s	pack_file_check_lzh             ; no
	cmpi.w	#$3,algorithm                   ; V2?
	beq.s	pack_file_data_size             ; yes
	cmpi.w	#$2,algorithm                   ; LZH?
	bne.s	pack_file_check_lzh             ; no
pack_file_data_size:
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + 32
	cmp.l	$c(a6),d0                       ; smaller?
	blt.s	pack_file_smaller               ; yes
pack_file_check_lzh:
	cmpi.w	#$1,$10(a6)                     ; a program?
	bne.w	pack_file_not_smaller           ; no: not smaller
	cmpi.w	#$2,algorithm                   ; LZH?
	bne.w	pack_file_not_smaller           ; no: not smaller
	lea	v30_stub+$476,a0                ; the V3.0 stub's end
	move.l	a0,d1
	lea	v30_stub,a0                     ; less its start
	sub.l	a0,d1                           ; = its length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	d1,d0                           ; + the stub
	cmp.l	$c(a6),d0                       ; smaller?
	bge.w	pack_file_not_smaller           ; no
pack_file_smaller:
	cmpi.w	#$1,$10(a6)                     ; a program?
	bne.s	pack_file_info_data             ; no
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	pack_file_info_v30              ; no
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	v24_stub+$2d0,a0                ; the V2.4 stub's end
	add.l	a0,d0                           ; +
	lea	v24_stub,a0                     ; less its start
	sub.l	a0,d0                           ; = the file's length
	move.l	d0,-(sp)                        ; show the sizes
	jsr	show_pack_sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.s	pack_file_info_shown
pack_file_info_v30:
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	v30_stub+$476,a0                ; the V3.0 stub's end
	add.l	a0,d0                           ; +
	lea	v30_stub,a0                     ; less its start
	sub.l	a0,d0                           ; = the file's length
	move.l	d0,-(sp)                        ; argument 1
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
pack_file_info_shown:
	bra.s	pack_file_ok
pack_file_info_data:
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
pack_file_ok:
	clr.w	-(sp)                           ; no edit object
	move.l	tree_info,-(sp)                 ; the pack info
	jsr	form_do
	addq.l	#6,sp                           ; drop the arguments
	movea.l	tree_info,a0                    ; the pack info
	move.w	$b2(a0),d0                      ; OK's state
	and.w	#$fffe,d0                       ; not selected
	move.w	d0,-$14(a6)
	move.w	#$1,-(sp)                       ; redraw
	move.w	-$14(a6),-(sp)                  ; the state
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	#$7,-(sp)                       ; OK
	move.l	tree_info,-(sp)                 ; the pack info
	jsr	objc_change
	lea	$14(sp),sp                      ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	pea	text_supply_save_path           ; "Supply the SAVE path and file name"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
pack_file_save:
	pea	save_name                       ; the path chosen
	pea	pack_file_name                  ; the name
	pea	destination_path                ; the destination path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	ext.l	d0                              ; to a long
	move.l	d0,-$4(a6)
	cmpi.l	#$ffffffff,-$4(a6)              ; OK?
	beq.w	pack_file_cancelled             ; no
	clr.w	-$12(a6)                        ; no alert answer yet
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	tst.w	$10(a6)                         ; a program?
	bne.s	pack_file_save_program          ; yes
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	pack_file_save_lzh              ; no
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.s	pack_file_saved_data
pack_file_save_lzh:
	move.l	-$10(a6),-(sp)                  ; the packed data
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
pack_file_saved_data:
	bra.s	pack_file_saved
pack_file_save_program:
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	pack_file_save_program_lzh      ; no
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	write_program                   ; write the program
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.s	pack_file_saved
pack_file_save_program_lzh:
	move.l	-$10(a6),-(sp)                  ; the packed data
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	write_program                   ; write the program
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
pack_file_saved:
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	bra.s	pack_file_check_save
pack_file_cancelled:
	move.w	#$0,d0                          ; 0
	ext.l	d0                              ; to a long
	bra.w	pack_file_done
pack_file_check_save:
	cmpi.l	#$ffffffff,-$4(a6)              ; failed?
	bne.s	pack_file_answer                ; no
	pea	alert_save_failure              ; "Save Failure!" Retry or Abort
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.w	d0,-$12(a6)                     ; the answer
pack_file_answer:
	cmpi.w	#$2,-$12(a6)                    ; Abort?
	bne.s	pack_file_retry                 ; no
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$3,d0                          ; 3
	ext.l	d0                              ; to a long
	bra.s	pack_file_done
pack_file_retry:
	cmpi.w	#$1,-$12(a6)                    ; Retry?
	bne.s	pack_file_end                   ; no
	cmpi.l	#$ffffffff,-$4(a6)              ; and it failed?
	beq.w	pack_file_save                  ; yes: again
pack_file_end:
	bra.s	pack_file_end2
pack_file_not_smaller:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$4,d0                          ; 4
	ext.l	d0                              ; to a long
	bra.s	pack_file_done
pack_file_end2:
	bra.s	pack_file_free
pack_file_read_error:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$2,d0                          ; 2
	ext.l	d0                              ; to a long
	bra.s	pack_file_done
pack_file_free:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	-$8(a6),d0                      ; the packed length
pack_file_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; save_file(name, length, data): "Saving File", Fcreate, Fwrite, Fclose.  d0 = -1 on error.
;------------------------------------------------------------------------------
save_file:	; from: unpack_file, pack_file, multi_pack_file
	link	a6,#0                           ; the frame
	movem.l	d5-d7,-(sp)                     ; keep the registers
	move.l	$c(a6),d7                       ; the length
	move.l	$10(a6),d6                      ; the data
	pea	text_saving_file                ; "Saving File"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	clr.w	-(sp)                           ; normal file
	move.l	8(a6),-(sp)                     ; the name
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d5                           ; the handle
	tst.w	d5                              ; created?
	bge.s	save_file_write                 ; yes
	move.w	#$ffff,d0                       ; no: -1
	ext.l	d0                              ; to a long
	bra.s	save_file_done
save_file_write:
	move.l	d6,-(sp)                        ; the data
	move.l	d7,-(sp)                        ; the length
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	d7,d0                           ; written?
	beq.s	save_file_close                 ; yes
	move.w	#$ffff,d0                       ; no: -1
	ext.l	d0                              ; to a long
	bra.s	save_file_done
save_file_close:
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
save_file_done:
	movem.l	(sp)+,d5-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; load_file(name, buffer, length): Fopen, Fread, Fclose.  d0 = 0, or -1 when it cannot be opened.
;------------------------------------------------------------------------------
load_file:	; from: unpack_file, pack_file, multi_pack_file
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.l	$c(a6),d7                       ; the buffer
	move.l	$10(a6),d6                      ; the length
	clr.w	-(sp)                           ; read only
	move.l	8(a6),-(sp)                     ; the name
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d5                           ; the handle
	tst.w	d5                              ; opened?
	bge.s	load_file_read                  ; yes
	move.w	#$ffff,d0                       ; no: -1
	ext.l	d0                              ; to a long
	bra.s	load_file_done
load_file_read:
	move.l	d7,-(sp)                        ; the length
	move.l	d6,-(sp)                        ; the buffer
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,d4
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$0,d0                          ; 0
	ext.l	d0                              ; to a long
load_file_done:
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; show_pack_sizes(packed, original): the packed size, the space saved and the percentage into the pack info,
; shown, with its OK button unless multi packing.
;------------------------------------------------------------------------------
show_pack_sizes:	; from: pack_file, multi_pack_file
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the packed size
	move.l	$c(a6),d6                       ; the original
	movea.l	tree_info,a0                    ; the pack info
	move.l	$fc(a0),-(sp)                   ; the packed size's text
	move.l	d7,-(sp)                        ; argument 1
	jsr	ltoa
	addq.l	#8,sp                           ; drop the arguments
	pea	text_bytes_packed               ; " Bytes"
	movea.l	tree_info,a0
	move.l	$fc(a0),-(sp)                   ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_info,a0
	move.l	$114(a0),-(sp)                  ; the space saved's text
	move.l	d6,d0                           ; the original
	sub.l	d7,d0                           ; less the packed size
	move.l	d0,-(sp)                        ; argument 1
	jsr	ltoa
	addq.l	#8,sp                           ; drop the arguments
	pea	text_bytes_saved                ; " Bytes"
	movea.l	tree_info,a0
	move.l	$114(a0),-(sp)                  ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_info,a0
	move.l	$12c(a0),-(sp)                  ; the percentage's text
	move.l	#$64,d0                         ; 100
	move.l	d0,-(sp)                        ; the number
	move.l	d7,d0                           ; the packed size
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul                            ; * 100
	move.l	(sp)+,d0                        ; the product
	move.l	d0,-(sp)                        ; the dividend
	move.l	d6,d0                           ; the original
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.l	d0,-(sp)                        ; argument 1
	jsr	ltoa
	addq.l	#8,sp                           ; drop the arguments
	pea	text_percent                    ; "%"
	movea.l	tree_info,a0
	move.l	$12c(a0),-(sp)                  ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_info,a0
	andi.w	#$ff7f,$f8(a0)                  ; the packed size shown
	movea.l	tree_info,a0
	andi.w	#$ff7f,$128(a0)                 ; the percentage shown
	movea.l	tree_info,a0
	andi.w	#$ff7f,$110(a0)                 ; the space saved shown
	tst.w	multi_active                    ; multi packing?
	bne.s	show_pack_sizes_draw            ; yes
	movea.l	tree_info,a0                    ; no: OK shown
	andi.w	#$ff7f,$b0(a0)
show_pack_sizes_draw:
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	clr.w	-(sp)                           ; from the root
	move.l	tree_info,-(sp)                 ; the pack info
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; show_crunching(name, length): the file's name and length in the pack info, the results and OK hidden.
;------------------------------------------------------------------------------
show_crunching:	; from: pack_file, multi_pack_file
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.l	$c(a6),d7                       ; the length
	move.l	8(a6),-(sp)                     ; the name
	movea.l	tree_info,a0                    ; the pack info
	move.l	$cc(a0),-(sp)                   ; "FILENAME.DAT"
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_info,a0
	move.l	$e4(a0),-(sp)                   ; the original size's text
	move.l	d7,-(sp)                        ; the length
	jsr	ltoa
	addq.l	#8,sp                           ; drop the arguments
	pea	text_bytes_original             ; " Bytes"
	movea.l	tree_info,a0
	move.l	$e4(a0),-(sp)                   ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_info,a0
	ori.w	#$80,$f8(a0)                    ; the packed size hidden
	movea.l	tree_info,a0
	ori.w	#$80,$128(a0)                   ; the percentage hidden
	movea.l	tree_info,a0
	ori.w	#$80,$110(a0)                   ; the space saved hidden
	movea.l	tree_info,a0
	ori.w	#$80,$b0(a0)                    ; OK hidden
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$1,-(sp)                       ; depth 1
	clr.w	-(sp)                           ; from the root
	move.l	tree_info,-(sp)                 ; the pack info
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; multi_pack_file(source, destination, length, program, name): pack_file without the dialogs: the result is
; written to the destination when it got smaller.  The same results as pack_file.
;------------------------------------------------------------------------------
multi_pack_file:	; from: multi_pack_one
	link	a6,#-20                         ; 20 bytes of locals
	move.l	$10(a6),d0                      ; the length
	add.l	#$1000,d0                       ; + 4 K
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$c(a6)                      ; the buffer
	tst.l	-$c(a6)                         ; got it?
	bne.s	multi_pack_file_buffer          ; yes
	move.w	#$1,d0                          ; no: 1
	ext.l	d0                              ; to a long
	bra.w	multi_pack_file_done
	bra.w	multi_pack_file_free
multi_pack_file_buffer:
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	clr.w	-(sp)                           ; from the root
	move.l	tree_packometer,-(sp)           ; the packometer
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.l	$10(a6),-(sp)                   ; the length
	move.l	$16(a6),-(sp)                   ; the name
	jsr	show_crunching                  ; into the pack info
	addq.l	#8,sp                           ; drop the arguments
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$c(a6),d0                      ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 2
	move.l	8(a6),-(sp)                     ; the source
	jsr	load_file                       ; load it
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$ffffffff,d0                   ; failed?
	beq.w	multi_pack_file_read_error      ; yes: 2
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	multi_pack_file_lzh             ; no
	move.l	v2_window,-(sp)                 ; the window
	move.l	-$c(a6),d0                      ; the buffer + 4
	addq.l	#4,d0
	move.l	d0,-(sp)
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_v2                         ; pack it
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	bra.s	multi_pack_file_packed
multi_pack_file_lzh:
	pea	-$10(a6)                        ; the packed data's address comes back here
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzh                        ; pack it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
multi_pack_file_packed:
	cmpi.w	#$1,$14(a6)                     ; a program?
	bne.s	multi_pack_file_check_data      ; no
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	multi_pack_file_check_data      ; no
	lea	v24_stub+$2d0,a0                ; the V2.4 stub's end
	move.l	a0,d1
	lea	v24_stub,a0                     ; less its start
	sub.l	a0,d1                           ; = its length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	add.l	d1,d0                           ; + the stub
	cmp.l	$10(a6),d0                      ; smaller?
	blt.s	multi_pack_file_smaller         ; yes
multi_pack_file_check_data:
	tst.w	$14(a6)                         ; data?
	bne.s	multi_pack_file_check_lzh       ; no
	cmpi.w	#$3,algorithm                   ; V2?
	beq.s	multi_pack_file_data_size       ; yes
	cmpi.w	#$2,algorithm                   ; LZH?
	bne.s	multi_pack_file_check_lzh       ; no
multi_pack_file_data_size:
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + 32
	cmp.l	$10(a6),d0                      ; smaller?
	blt.s	multi_pack_file_smaller         ; yes
multi_pack_file_check_lzh:
	cmpi.w	#$1,$14(a6)                     ; a program?
	bne.w	multi_pack_file_not_smaller     ; no: not smaller
	cmpi.w	#$2,algorithm                   ; LZH?
	bne.w	multi_pack_file_not_smaller     ; no: not smaller
	lea	v30_stub+$476,a0                ; the V3.0 stub's end
	move.l	a0,d1
	lea	v30_stub,a0                     ; less its start
	sub.l	a0,d1                           ; = its length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	d1,d0                           ; + the stub
	cmp.l	$10(a6),d0                      ; smaller?
	bge.w	multi_pack_file_not_smaller     ; no
multi_pack_file_smaller:
	cmpi.w	#$1,$14(a6)                     ; a program?
	bne.s	multi_pack_file_info_data       ; no
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	multi_pack_file_info_v30        ; no
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	v24_stub+$2d0,a0                ; the V2.4 stub's end
	add.l	a0,d0                           ; +
	lea	v24_stub,a0                     ; less its start
	sub.l	a0,d0                           ; = the file's length
	move.l	d0,-(sp)                        ; argument 1
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.s	multi_pack_file_info_shown
multi_pack_file_info_v30:
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	v30_stub+$476,a0                ; the V3.0 stub's end
	add.l	a0,d0                           ; +
	lea	v30_stub,a0                     ; less its start
	sub.l	a0,d0                           ; = the file's length
	move.l	d0,-(sp)                        ; argument 1
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
multi_pack_file_info_shown:
	bra.s	multi_pack_file_save
multi_pack_file_info_data:
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
multi_pack_file_save:
	tst.w	$14(a6)                         ; a program?
	bne.s	multi_pack_file_save_program    ; yes
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	multi_pack_file_save_lzh        ; no
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; the destination
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.s	multi_pack_file_saved_data
multi_pack_file_save_lzh:
	move.l	-$10(a6),-(sp)                  ; the packed data
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; the destination
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
multi_pack_file_saved_data:
	bra.s	multi_pack_file_saved
multi_pack_file_save_program:
	cmpi.w	#$3,algorithm                   ; V2?
	bne.s	multi_pack_file_program_lzh     ; no
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; the destination
	jsr	write_program                   ; write the program
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.s	multi_pack_file_saved
multi_pack_file_program_lzh:
	move.l	-$10(a6),-(sp)                  ; the packed data
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; the destination
	jsr	write_program                   ; write the program
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
multi_pack_file_saved:
	cmpi.l	#$ffffffff,-$4(a6)              ; failed?
	bne.s	multi_pack_file_ok              ; no
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$3,d0                          ; 3
	ext.l	d0                              ; to a long
	bra.s	multi_pack_file_done
multi_pack_file_ok:
	bra.s	multi_pack_file_end
multi_pack_file_not_smaller:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$4,d0                          ; 4
	ext.l	d0                              ; to a long
	bra.s	multi_pack_file_done
multi_pack_file_end:
	bra.s	multi_pack_file_free
multi_pack_file_read_error:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$2,d0                          ; 2
	ext.l	d0                              ; to a long
	bra.s	multi_pack_file_done
multi_pack_file_free:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	-$8(a6),d0                      ; the packed length
multi_pack_file_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; jam_unjam(button): JAM puts every file of a folder into one .JAM file; UnJAM recreates the folder from one.
; A JAM file holds the file count (a word), the largest file's length (a long), the folder's name (12 bytes),
; then for each file its name (12 bytes), its length (a long) and its data.
;------------------------------------------------------------------------------
jam_unjam:	; from: main
	link	a6,#-16                         ; 16 bytes of locals
	movem.l	d7,-(sp)                        ; keep the registers
	move.w	8(a6),d7                        ; the button
	cmpi.w	#$19,d7                         ; JAM?
	bne.w	unjam                           ; no: UnJAM
	pea	text_supply_jam_folder          ; "Supply the PATH of the folder to jam"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	text_all_files_jam_folder       ; "*.*"
	pea	jam_folder_path                 ; on the folder path
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	jam_folder_path                 ; the path chosen
	pea	jam_name                        ; the name
	pea	jam_folder_path                 ; the folder path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.w	jam_folder_cancelled            ; no
	move.w	#$5c,-(sp)                      ; cut after the last \
	pea	jam_folder_path                 ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	pea	jam_folder_path                 ; the path
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	cmpi.w	#$3,d0                          ; the root (3 characters or less)?
	bgt.s	jam_count                       ; no
	pea	alert_cannot_jam_root           ; "Cannot jam from ROOT directory."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	jam_unjam_done
jam_count:
	jsr	count_folder                    ; count the folder's files
	move.l	d0,jam_total                    ; the total length
	pea	text_supply_jam_file            ; "Supply the PATH of the jam file ("
	pea	work_text                       ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text                       ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	lea	work_text,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0                           ; its end
	move.l	d0,-(sp)                        ; argument 2
	move.w	jam_file_count,-(sp)            ; the file count
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	pea	text_files                      ; " files, "
	pea	work_text                       ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text                       ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	lea	work_text,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0                           ; its end
	move.l	d0,-(sp)                        ; argument 2
	move.l	jam_total,-(sp)                 ; the total length
	jsr	ltoa
	addq.l	#8,sp                           ; drop the arguments
	pea	text_bytes_total                ; " bytes)"
	pea	work_text                       ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text                       ; argument 1
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	text_all_files_jam_file         ; "*.*"
	pea	jam_destination_path            ; on the destination path
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	jam_destination_path            ; the path chosen
	pea	jam_name                        ; the name
	pea	jam_destination_path            ; the destination path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.w	jam_cancelled                   ; no
	move.w	#$5c,-(sp)                      ; cut after the last \
	pea	jam_destination_path            ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	pea	jam_folder_path                 ; the folder path
	pea	work_text                       ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text                       ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	subq.w	#1,d0                           ; its last character (the \)
	lea	work_text,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	clr.b	(a0)                            ; cut
	move.w	#$5c,-(sp)                      ; the folder's own name
	pea	work_text                       ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	addq.l	#1,d0                           ; after it
	move.l	d0,-(sp)                        ; argument 2
	pea	-$10(a6)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_jam_extension              ; "JAM"
	pea	-$10(a6)                        ; as its extension
	jsr	set_extension
	addq.l	#8,sp                           ; drop the arguments
	pea	-$10(a6)                        ; the jam file's name
	pea	jam_destination_path            ; on the destination path
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	jsr	write_jam                       ; write the jam file
	bra.w	jam_unjam_done
	bra.s	jam_unjam_end
jam_cancelled:
	move.w	#$ffff,d0                       ; -1
	bra.w	jam_unjam_done
jam_unjam_end:
	bra.s	jam_unjam_end2
jam_folder_cancelled:
	move.w	#$ffff,d0                       ; -1
	bra.w	jam_unjam_done
jam_unjam_end2:
	bra.w	jam_unjam_done
unjam:
	pea	text_supply_jam_source          ; "Supply the PATHNAME of the source file"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	text_all_files_unjam            ; "*.*"
	pea	jam_folder_path                 ; on the folder path
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	text_jam_extension_unjam        ; "JAM" after it
	pea	jam_folder_path                 ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	clr.b	jam_name                        ; no name
	pea	jam_folder_path                 ; the path chosen
	pea	jam_name                        ; the name
	pea	jam_folder_path                 ; the jam file
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.s	unjam_cancelled                 ; no
	pea	text_supply_unjam_folder        ; "Supply the PATH of the destination folder"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	clr.b	jam_name                        ; no name
	pea	jam_destination_path            ; the path chosen
	pea	jam_name                        ; the name
	pea	jam_destination_path            ; the destination path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.s	unjam_folder_cancelled          ; no
	move.w	#$5c,-(sp)                      ; cut after the last \
	pea	jam_destination_path            ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	jsr	unjam_file                      ; unjam it
	bra.s	jam_unjam_done
	bra.s	unjam_end
unjam_folder_cancelled:
	move.w	#$ffff,d0                       ; -1
	bra.s	jam_unjam_done
unjam_end:
	bra.s	jam_unjam_done
unjam_cancelled:
	move.w	#$ffff,d0                       ; -1
	nop
jam_unjam_done:
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; unjam_file: read the jam file's header, make the folder in the destination (asking when it is there
; already), extract every file, then cut the paths back.
;------------------------------------------------------------------------------
unjam_file:	; from: jam_unjam
	link	a6,#-174                        ; 174 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.w	#$2f,-(sp)                      ; Fgetdta
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,-$ae(a6)                     ; not used
	clr.w	-(sp)                           ; read only
	pea	jam_folder_path                 ; the jam file
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d6                           ; the handle
	tst.w	d0                              ; opened?
	bge.s	unjam_count                     ; yes
	pea	alert_cannot_find_file          ; no: "Can't find file."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	unjam_file_done
unjam_count:
	pea	jam_file_count                  ; the file count
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; read?
	bge.s	unjam_largest                   ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	unjam_file_done
unjam_largest:
	pea	-$aa(a6)                        ; the largest length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; read?
	bge.s	unjam_buffer                    ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	unjam_file_done
unjam_buffer:
	move.l	-$aa(a6),-(sp)                  ; the largest length
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,jam_buffer                   ; the buffer
	tst.l	d0                              ; got it?
	bne.s	unjam_folder_name               ; yes
	pea	alert_insufficient_memory       ; no: "Insufficient Memory."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	unjam_file_done
unjam_folder_name:
	pea	-$a6(a6)                        ; the folder's name
	move.l	#$c,-(sp)                       ; 12 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$c,d0                          ; read?
	bge.s	unjam_make_folder               ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	unjam_file_done
unjam_make_folder:
	pea	-$a6(a6)                        ; the folder's name
	pea	jam_destination_path            ; on the destination path
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	jam_destination_path            ; the folder
	move.w	#$39,-(sp)                      ; Dcreate
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	d0,d4
	tst.w	d0                              ; made?
	beq.s	unjam_extract                   ; yes
	cmpi.w	#$ffdc,d4                       ; there already (access denied)?
	bne.s	unjam_folder_error              ; no
	pea	alert_folder_exists             ; "Destination folder already exists." Continue or Abort
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	cmpi.w	#$2,d0                          ; Abort?
	bne.s	unjam_continue                  ; no
	clr.l	-(sp)                           ; yes: no alert
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$0,d0                          ; 0
	bra.w	unjam_file_done
unjam_continue:
	bra.s	unjam_extract
unjam_folder_error:
	pea	alert_cannot_make_folder        ; "Can't make destination folder."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	unjam_file_done
unjam_extract:
	pea	text_backslash                  ; "\"
	pea	jam_destination_path            ; after the folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	clr.w	d5                              ; the file number
	bra.s	unjam_extract_next
unjam_extract_loop:
	move.w	d6,-(sp)                        ; the jam file
	jsr	extract_file                    ; extract a file
	addq.l	#2,sp                           ; drop the arguments
	addq.w	#1,d5                           ; next
unjam_extract_next:
	move.w	d5,d0
	cmp.w	jam_file_count,d0               ; all done?
	blt.s	unjam_extract_loop              ; no
	pea	alert_folder_recreated          ; "Folder succesfully recreated."
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$5c,-(sp)                      ; cut the destination path's \
	pea	jam_destination_path            ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	(a0)
	move.w	#$5c,-(sp)                      ; and back to its parent
	pea	jam_destination_path            ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	move.w	#$5c,-(sp)                      ; the folder path too
	pea	jam_folder_path                 ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	move.w	#$0,d0                          ; 0
unjam_file_done:
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; extract_file(handle): read a file's name, length and data from the jam file and write it to the folder.
;------------------------------------------------------------------------------
extract_file:	; from: unjam_file
	link	a6,#-170                        ; 170 bytes of locals
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; the jam file
	pea	-$a6(a6)                        ; the name
	move.l	#$c,-(sp)                       ; 12 bytes
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$c,d0                          ; read?
	bge.s	extract_length                  ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	extract_file_done
extract_length:
	clr.b	-$9a(a6)                        ; the name ended
	pea	-$aa(a6)                        ; the length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; read?
	bge.s	extract_data                    ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	extract_file_done
extract_data:
	move.l	jam_buffer,-(sp)                ; the buffer
	move.l	-$aa(a6),-(sp)                  ; the length
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	-$aa(a6),d0                     ; all read?
	bge.s	extract_name                    ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	extract_file_done
extract_name:
	pea	jam_destination_path            ; the destination folder
	pea	-$96(a6)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$a6(a6)                        ; the name
	pea	-$96(a6)                        ; after it
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	text_extracting                 ; "Extracting "
	pea	work_text                       ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$96(a6)                        ; the name
	pea	work_text                       ; after it
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text                       ; argument 1
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	clr.w	-(sp)                           ; normal file
	pea	-$96(a6)                        ; the file
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d6                           ; the handle
	tst.w	d0                              ; created?
	bge.s	extract_write                   ; yes
	pea	alert_cannot_create_file        ; no: "Can't create file."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.s	extract_file_done
extract_write:
	move.l	jam_buffer,-(sp)                ; the buffer
	move.l	-$aa(a6),-(sp)                  ; the length
	move.w	d6,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	-$aa(a6),d0                     ; all written?
	bge.s	extract_close                   ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.s	extract_file_done
extract_close:
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
extract_file_done:
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; count_folder: the files of the folder path: the count in jam_file_count, the largest length in
; jam_largest, and d0 = the jam file's length (-1 for no files).  The search stops if the first name comes
; round again.
;------------------------------------------------------------------------------
count_folder:	; from: jam_unjam
	link	a6,#-20                         ; 20 bytes of locals
	movem.l	d6-d7,-(sp)                     ; keep the registers
	clr.l	d6                              ; the length
	clr.w	jam_file_count                  ; no files
	clr.l	jam_largest                     ; no largest
	move.w	#$2f,-(sp)                      ; Fgetdta
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,-$14(a6)                     ; the DTA
	pea	jam_folder_path                 ; the folder path
	pea	work_text                       ; kept
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_all_files_count            ; "*.*"
	pea	jam_folder_path                 ; on the folder path
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	clr.w	-(sp)                           ; normal files
	pea	jam_folder_path                 ; the path
	move.w	#$4e,-(sp)                      ; Fsfirst
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	tst.w	d0                              ; found?
	bne.w	count_folder_none               ; no: -1
	movea.l	-$14(a6),a0                     ; the DTA
	move.l	$1a(a0),d0                      ; its length
	addq.l	#2,d0                           ; + 2: the count
	add.l	#$c,d0                          ; + 12: the folder's name
	addq.l	#4,d0                           ; + 4: the largest
	add.l	#$c,d0                          ; + 12: the file's name
	addq.l	#4,d0                           ; + 4: its length
	add.l	d0,d6                           ; counted
	movea.l	-$14(a6),a0
	move.l	$1a(a0),jam_largest             ; the largest so far
	addq.w	#1,jam_file_count               ; one file
	movea.l	-$14(a6),a0                     ; the first name
	pea	$1e(a0)                         ; argument 2
	pea	-$10(a6)                        ; kept
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	bra.s	count_folder_fsnext
count_folder_next:
	move.w	#$5c,-(sp)                      ; the path back
	pea	work_text                       ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	movea.l	-$14(a6),a0                     ; the DTA
	move.l	$1a(a0),d0                      ; its length
	add.l	#$c,d0                          ; + 12: its name
	addq.l	#4,d0                           ; + 4: its length
	add.l	d0,d6                           ; counted
	movea.l	-$14(a6),a0
	move.l	$1a(a0),d0
	cmp.l	jam_largest,d0                  ; larger?
	ble.s	count_folder_one                ; no
	movea.l	-$14(a6),a0                     ; yes: the largest
	move.l	$1a(a0),jam_largest
count_folder_one:
	addq.w	#1,jam_file_count               ; one more file
count_folder_fsnext:
	move.w	#$4f,-(sp)                      ; Fsnext
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	tst.w	d0                              ; found?
	bne.s	count_folder_end                ; no
	pea	-$10(a6)                        ; the first name
	movea.l	-$14(a6),a0                     ; the DTA
	pea	$1e(a0)                         ; its name
	jsr	strcmp
	addq.l	#8,sp                           ; drop the arguments
	tst.w	d0                              ; the first again?
	bne.s	count_folder_next               ; no: count it
count_folder_end:
	bra.s	count_folder_done
count_folder_none:
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.s	count_folder_return
count_folder_done:
	move.w	#$5c,-(sp)                      ; cut the mask off
	pea	jam_folder_path                 ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	move.l	d6,d0                           ; the length
count_folder_return:
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; write_jam: create the jam file (asking before writing over one), write its header and every file of the
; folder.  The paths are cut back afterwards.
;------------------------------------------------------------------------------
write_jam:	; from: jam_unjam
	link	a6,#-186                        ; 186 bytes of locals
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	#$2f,-(sp)                      ; Fgetdta
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,-$ba(a6)                     ; the DTA
	clr.w	-(sp)                           ; read only
	pea	jam_destination_path            ; the jam file
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	cmpi.w	#$ffdf,d0                       ; not found?
	beq.s	write_jam_create                ; yes: make it
	pea	alert_jam_file_exists           ; "Destination file already exits." Write Over or Abort
	move.w	#$2,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	cmpi.w	#$2,d0                          ; Abort?
	bne.s	write_jam_create                ; no
	move.w	#$0,d0                          ; 0
	bra.w	write_jam_return
write_jam_create:
	clr.w	-(sp)                           ; normal file
	pea	jam_destination_path            ; the jam file
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d6                           ; the handle
	tst.w	d0                              ; created?
	bge.s	write_jam_buffer                ; yes
	pea	alert_cannot_create_file        ; no: "Can't create file."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	write_jam_return
write_jam_buffer:
	move.l	jam_largest,-(sp)               ; the largest length
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,jam_buffer                   ; the buffer
	tst.l	jam_buffer                      ; got it?
	bne.s	write_jam_count                 ; yes
	pea	alert_insufficient_memory       ; no: "Insufficient Memory."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	write_jam_return
write_jam_count:
	pea	jam_file_count                  ; the file count
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	write_jam_largest               ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	write_jam_return
write_jam_largest:
	pea	jam_largest                     ; the largest length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	write_jam_folder_name           ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	write_jam_return
write_jam_folder_name:
	pea	jam_folder_path                 ; the folder path
	pea	work_text                       ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text                       ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	subq.w	#1,d0                           ; its last character (the \)
	lea	work_text,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	clr.b	(a0)                            ; cut
	move.w	#$5c,-(sp)                      ; the folder's own name
	pea	work_text                       ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	addq.l	#1,d0                           ; after it
	move.l	d0,-(sp)                        ; argument 2
	pea	-$a6(a6)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$a6(a6)                        ; the name
	move.l	#$c,-(sp)                       ; 12 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$c,d0                          ; all right?
	bge.s	write_jam_files                 ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	write_jam_return
write_jam_files:
	pea	jam_folder_path                 ; the folder path
	pea	-$96(a6)                        ; kept
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_all_files_write            ; "*.*"
	pea	jam_folder_path                 ; on the folder path
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	clr.w	-(sp)                           ; normal files
	pea	jam_folder_path                 ; the path
	move.w	#$4e,-(sp)                      ; Fsfirst
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	tst.w	d0                              ; found?
	bne.w	write_jam_none                  ; no
	movea.l	-$ba(a6),a0                     ; the DTA
	pea	$1e(a0)                         ; the first name
	pea	-$b6(a6)                        ; kept
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	movea.l	-$ba(a6),a0
	pea	$1e(a0)                         ; the name
	pea	-$96(a6)                        ; after the folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	movea.l	-$ba(a6),a0
	move.l	$1a(a0),-(sp)                   ; its length
	move.w	d6,-(sp)                        ; the jam file
	pea	-$96(a6)                        ; the file
	jsr	add_to_jam                      ; add it
	lea	$a(sp),sp                       ; drop the arguments
	tst.w	d0                              ; all right?
	bge.s	write_jam_next                  ; yes
	move.w	#$ffff,d0                       ; no: -1
	bra.w	write_jam_return
write_jam_next:
	bra.s	write_jam_fsnext
write_jam_add:
	movea.l	-$ba(a6),a0                     ; the DTA
	pea	$1e(a0)                         ; its name
	move.w	#$5c,-(sp)                      ; argument 2
	pea	-$96(a6)                        ; the file's path
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	addq.l	#1,d0                           ; after the \
	move.l	d0,-(sp)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	movea.l	-$ba(a6),a0
	move.l	$1a(a0),-(sp)                   ; its length
	move.w	d6,-(sp)                        ; the jam file
	pea	-$96(a6)                        ; the file
	jsr	add_to_jam                      ; add it
	lea	$a(sp),sp                       ; drop the arguments
	tst.w	d0                              ; all right?
	bge.s	write_jam_fsnext                ; yes
	move.w	#$ffff,d0                       ; no: -1
	bra.w	write_jam_return
write_jam_fsnext:
	move.w	#$4f,-(sp)                      ; Fsnext
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	tst.w	d0                              ; found?
	bne.s	write_jam_end                   ; no
	pea	-$b6(a6)                        ; the first name
	movea.l	-$ba(a6),a0                     ; the DTA
	pea	$1e(a0)                         ; its name
	jsr	strcmp
	addq.l	#8,sp                           ; drop the arguments
	tst.w	d0                              ; the first again?
	bne.s	write_jam_add                   ; no: add it
write_jam_end:
	bra.s	write_jam_done
write_jam_none:
	move.w	#$ffff,d0                       ; -1
	bra.s	write_jam_return
write_jam_done:
	pea	alert_folder_jammed             ; "Folder successfully jammed."
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$5c,-(sp)                      ; cut the jam file's path back
	pea	jam_destination_path            ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	move.w	#$5c,-(sp)                      ; and the folder path
	pea	jam_folder_path                 ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)
	move.w	d6,-(sp)                        ; the jam file
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
write_jam_return:
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; add_to_jam(file, handle, length): write the file's name, length and data to the jam file.
;------------------------------------------------------------------------------
add_to_jam:	; from: write_jam
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	$c(a6),d7                       ; the jam file
	pea	text_jamming                    ; "Jamming "
	pea	work_text                       ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$5c,-(sp)                      ; the name after the last \
	move.l	8(a6),-(sp)                     ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	addq.l	#1,d0
	move.l	d0,-(sp)                        ; argument 2
	pea	work_text                       ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text                       ; argument 1
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$5c,-(sp)                      ; the name
	move.l	8(a6),-(sp)                     ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	addq.l	#1,d0
	move.l	d0,-(sp)                        ; argument 3
	move.l	#$c,-(sp)                       ; 12 bytes
	move.w	d7,-(sp)                        ; the jam file
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$c,d0                          ; all right?
	bge.s	add_to_jam_length               ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	add_to_jam_done
add_to_jam_length:
	pea	$e(a6)                          ; the length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d7,-(sp)                        ; the jam file
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; all right?
	bge.s	add_to_jam_open                 ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	add_to_jam_done
add_to_jam_open:
	clr.w	-(sp)                           ; read only
	move.l	8(a6),-(sp)                     ; the file
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d6                           ; the handle
	tst.w	d0                              ; opened?
	bge.s	add_to_jam_read                 ; yes
	pea	alert_cannot_find_file          ; no: "Can't find file."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.s	add_to_jam_done
add_to_jam_read:
	move.l	jam_buffer,-(sp)                ; the buffer
	move.l	$e(a6),-(sp)                    ; the length
	move.w	d6,-(sp)                        ; the file
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	$e(a6),d0                       ; all read?
	beq.s	add_to_jam_write                ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.s	add_to_jam_done
add_to_jam_write:
	move.w	d6,-(sp)                        ; the file
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.l	jam_buffer,-(sp)                ; the buffer
	move.l	$e(a6),-(sp)                    ; the length
	move.w	d7,-(sp)                        ; the jam file
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	$e(a6),d0                       ; all written?
	beq.s	add_to_jam_ok                   ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	jam_error                       ; the error
	addq.l	#6,sp                           ; drop the arguments
	bra.s	add_to_jam_done
add_to_jam_ok:
	move.w	#$0,d0                          ; 0
add_to_jam_done:
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; jam_error(handle, alert): show the alert (if any), close the handle (if any), free the buffer; d0 = -1.
;------------------------------------------------------------------------------
jam_error:	; from: jam_unjam, unjam_file, extract_file, write_jam, add_to_jam
	link	a6,#0                           ; the frame
	movem.l	d7/a5,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; the handle
	movea.l	$a(a6),a5                       ; the alert
	move.l	a5,d3
	beq.s	jam_error_close                 ; none
	move.l	a5,-(sp)                        ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
jam_error_close:
	tst.w	d7                              ; a handle?
	blt.s	jam_error_free                  ; no
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
jam_error_free:
	tst.l	jam_buffer                      ; a buffer?
	beq.s	jam_error_done                  ; no
	move.l	jam_buffer,-(sp)                ; argument 1
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
jam_error_done:
	move.w	#$ffff,d0                       ; -1
	movem.l	(sp)+,d7/a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; set_extension(name, extension): put the extension after the name's dot, adding one when there is none.
;------------------------------------------------------------------------------
set_extension:	; from: jam_unjam, disk_unpack, disk_pack
	link	a6,#0                           ; the frame
	move.w	#$2e,-(sp)                      ; '.'
	move.l	8(a6),-(sp)                     ; the name
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	tst.l	d0                              ; a dot?
	bne.s	set_extension_dot               ; yes
	pea	text_dot                        ; no: "."
	move.l	8(a6),-(sp)                     ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.l	$c(a6),-(sp)                    ; the extension
	move.l	8(a6),-(sp)                     ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	bra.s	set_extension_done
set_extension_dot:
	move.w	#$2e,-(sp)                      ; '.'
	move.l	8(a6),-(sp)                     ; argument 1
	jsr	strrchr
	addq.l	#6,sp                           ; drop the arguments
	movea.l	d0,a0
	clr.b	1(a0)                           ; cut after it
	move.l	$c(a6),-(sp)                    ; the extension
	move.l	8(a6),-(sp)                     ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
set_extension_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; disk_unpack(format): write a .DPK file back to a disk in drive A or B, formatting it first when Format is
; on.  A DPK file holds the sectors a track, the tracks and the sides (a word each), then LZH chunks, each
; after its length, and a -1 length at the end.  The first chunk is written from sector 0 (its first sector
; with Flopwr too), the rest follow on.  Its read errors after the first chunk call close_gem, not disk_error.
;------------------------------------------------------------------------------
disk_unpack:	; from: main
	link	a6,#-48                         ; 48 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	clr.w	-$30(a6)                        ; no sectors yet
	pea	alert_unpack_which_drive        ; "Unpack file to which drive?" A or B
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	subq.w	#1,d0                           ; 0 or 1
	move.w	d0,d4                           ; d4 = the drive
	pea	text_root_unpack                ; "\"
	pea	dpk_path                        ; the path
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_dpk_mask_unpack            ; "*.DPK"
	pea	dpk_path                        ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	text_drivea_unpack              ; "DRIVEA.DPK"
	pea	dpk_name                        ; the name
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_choose_input               ; "Choose the input pathname"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	dpk_path                        ; the path chosen
	pea	dpk_name                        ; the name
	pea	dpk_path                        ; the path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.s	disk_unpack_cancelled           ; no
	pea	text_dpk_unpack                 ; "DPK"
	pea	dpk_path                        ; as its extension
	jsr	set_extension
	addq.l	#8,sp                           ; drop the arguments
	bra.s	disk_unpack_go
disk_unpack_cancelled:
	jsr	clear_title                     ; the title line cleared
	move.l	screen_buffer,-(sp)             ; the screen
	move.l	screen,-(sp)                    ; saved
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	clr.l	-(sp)                           ; no alert
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_go:
	jsr	clear_title                     ; the title line cleared
	move.l	screen_buffer,-(sp)             ; the screen
	move.l	screen,-(sp)                    ; saved
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	move.l	#$4b800,-(sp)                   ; $4b800 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,d6                           ; d6 = the buffer
	tst.l	d6                              ; got it?
	bne.s	disk_unpack_open                ; yes
	pea	alert_insufficient_memory       ; no: "Insufficient Memory."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_open:
	clr.w	-(sp)                           ; read only
	pea	dpk_path                        ; the DPK file
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d5                           ; d5 = the handle
	ext.l	d0                              ; to a long
	cmp.l	#$0,d0                          ; 0?
	bne.s	disk_unpack_spt                 ; no
	pea	alert_disk_read_error           ; yes: "Disk read error."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_spt:
	pea	disk_spt                        ; the sectors a track
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; read?
	beq.s	disk_unpack_tracks              ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_tracks:
	pea	disk_tracks                     ; the tracks
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; read?
	beq.s	disk_unpack_sides               ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_sides:
	pea	disk_sides                      ; the sides
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; read?
	beq.s	disk_unpack_header_read         ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_header_read:
	move.w	disk_tracks,d0                  ; tracks
	muls.w	disk_spt,d0                     ; * sectors a track
	muls.w	disk_sides,d0                   ; * sides
	move.w	d0,disk_sectors                 ; = the total
	pea	text_disk_unpack_progress       ; "Disk Unpack Progress"
	pea	-$2e(a6)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	lea	-$2e(a6),a0
	move.l	a0,d0
	movea.l	tree_disk,a0                    ; the progress box
	movea.l	$24(a0),a0                      ; its title's TEDINFO
	move.l	d0,(a0)                         ; its text
	pea	-$2e(a6)                        ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	movea.l	$24(a0),a0
	move.w	d0,$18(a0)                      ; its length
	move.w	d4,-(sp)                        ; the drive
	jsr	show_disk_info                  ; the disk info
	addq.l	#2,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	movea.l	$84(a0),a0                      ; the action line
	clr.b	(a0)                            ; cleared
	movea.l	tree_disk,a0
	movea.l	$9c(a0),a0                      ; the sectors line
	clr.b	(a0)                            ; cleared
	pea	disk_rect                       ; its box
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	open_box                        ; opened
	addq.l	#8,sp                           ; drop the arguments
	move.w	8(a6),d0                        ; Format?
	beq.s	disk_unpack_first               ; no
	pea	text_formatting                 ; "     -- Formatting --"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$1,-(sp)                       ; depth 1
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.w	d4,-(sp)                        ; the drive
	move.w	disk_tracks,-(sp)               ; tracks
	move.w	disk_spt,-(sp)                  ; sectors a track
	move.w	disk_sides,-(sp)                ; sides
	jsr	format_disk                     ; format the disk
	addq.l	#8,sp                           ; drop the arguments
	bne.s	disk_unpack_first               ; all right?
	pea	alert_format_error              ; no: "Disk error while formatting."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_first:
	pea	chunk_length                    ; the chunk's length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; read?
	beq.s	disk_unpack_first_read          ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_first_read:
	pea	text_reading_first              ; "Reading"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d6,-(sp)                        ; the buffer
	move.l	chunk_length,-(sp)              ; the length
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	chunk_length,d0                 ; all read?
	beq.s	disk_unpack_first_depack        ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_first_depack:
	pea	text_unpacking_first            ; "Unpacking"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d6,d0                           ; the buffer
	add.l	#$100,d0                        ; + 256: where it depacks to
	move.l	d0,-(sp)                        ; argument 2
	move.l	d6,-(sp)                        ; the packed chunk
	jsr	depack_lzh                      ; depack it
	addq.l	#8,sp                           ; drop the arguments
	move.l	d0,chunk_length                 ; its length
	pea	text_writing_first              ; "Writing Sectors"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_zero_to_unpack             ; "0 to "
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; the sectors line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	subq.l	#1,d0                           ; less 1: the last sector
	move.l	d0,-(sp)                        ; argument 1
	jsr	ltoa
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; after it
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.w	#$1,-(sp)                       ; Flopwr: 1 sector
	clr.w	-(sp)                           ; side 0
	clr.w	-(sp)                           ; track 0
	move.w	#$1,-(sp)                       ; sector 1
	move.w	d4,-(sp)                        ; the drive
	clr.l	-(sp)                           ; argument 2
	move.l	d6,-(sp)                        ; the boot sector
	move.w	#$9,-(sp)                       ; Flopwr
	jsr	xbios
	lea	$14(sp),sp                      ; drop the arguments
	tst.w	d0                              ; all right?
	beq.s	disk_unpack_first_write         ; yes
	move.l	d6,-(sp)                        ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_first_write:
	move.w	d4,-(sp)                        ; the drive
	move.w	#$7,-(sp)                       ; Mediach
	jsr	bios
	addq.l	#4,sp                           ; drop the arguments
	move.w	d4,-(sp)                        ; the drive
	clr.w	-(sp)                           ; from sector 0
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.w	d0,-(sp)                        ; = the sectors
	move.l	d6,-(sp)                        ; the buffer
	move.w	#$1,-(sp)                       ; write
	move.w	#$4,-(sp)                       ; Rwabs
	jsr	bios
	lea	$e(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	disk_unpack_first_done          ; yes
	move.l	d6,-(sp)                        ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_first_done:
	move.w	d4,-(sp)                        ; the drive
	move.w	#$7,-(sp)                       ; Mediach
	jsr	bios
	addq.l	#4,sp                           ; drop the arguments
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.w	d0,-$30(a6)                     ; = the next sector
	pea	chunk_length                    ; the next chunk's length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	tst.l	d0                              ; read?
	bge.s	disk_unpack_first_ok            ; yes
	move.l	d6,-(sp)                        ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	close_gem                       ; close_gem, as written
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_first_ok:
	bra.w	disk_unpack_loop
disk_unpack_chunk:
	pea	text_reading_chunk              ; "Reading"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	movea.l	$9c(a0),a0                      ; the sectors line
	clr.b	(a0)                            ; cleared
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d6,-(sp)                        ; the buffer
	move.l	chunk_length,-(sp)              ; the length
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	disk_unpack_chunk_depack        ; yes
	move.l	d6,-(sp)                        ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	close_gem                       ; close_gem, as written
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_chunk_depack:
	pea	text_unpacking_chunk            ; "Unpacking"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d6,d0                           ; the buffer
	add.l	#$100,d0                        ; + 256
	move.l	d0,-(sp)                        ; argument 2
	move.l	d6,-(sp)                        ; the packed chunk
	jsr	depack_lzh                      ; depack it
	addq.l	#8,sp                           ; drop the arguments
	move.l	d0,chunk_length                 ; its length
	pea	text_writing_chunk              ; "Writing Sectors"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; the sectors line
	move.w	-$30(a6),-(sp)                  ; the first sector
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	pea	text_to_unpack                  ; " to "
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	subq.l	#1,d0                           ; less 1
	move.w	-$30(a6),d3                     ; + the first sector
	ext.l	d3                              ; to a long
	add.l	d3,d0                           ; = the last
	move.l	d0,-(sp)                        ; argument 1
	jsr	ltoa
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; after it
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.w	d4,-(sp)                        ; the drive
	move.w	-$30(a6),-(sp)                  ; the first sector
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.w	d0,-(sp)                        ; = the sectors
	move.l	d6,-(sp)                        ; the buffer
	move.w	#$1,-(sp)                       ; write
	move.w	#$4,-(sp)                       ; Rwabs
	jsr	bios
	lea	$e(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	disk_unpack_chunk_done          ; yes
	move.l	d6,-(sp)                        ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_chunk_done:
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	add.w	d0,-$30(a6)                     ; the next sector
	pea	chunk_length                    ; the next chunk's length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d5,-(sp)                        ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	tst.l	d0                              ; read?
	bge.s	disk_unpack_loop                ; yes
	move.l	d6,-(sp)                        ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	d5,-(sp)                        ; argument 1
	jsr	close_gem                       ; close_gem, as written
	addq.l	#6,sp                           ; drop the arguments
	bra.s	disk_unpack_done
disk_unpack_loop:
	cmpi.l	#$ffffffff,chunk_length         ; the end (-1)?
	bne.w	disk_unpack_chunk               ; no: the chunk
	move.l	d6,-(sp)                        ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	d5,-(sp)                        ; the DPK file
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	pea	disk_rect                       ; its box
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	close_box                       ; closed
	addq.l	#8,sp                           ; drop the arguments
disk_unpack_done:
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; disk_pack(use_fat): pack the disk in drive A or B into a .DPK file: the header, the system sectors (boot,
; FATs, root directory) as one LZH chunk, then the rest in chunks of 600 sectors, and a -1 length.  With Use
; FAT on, the FAT is read and unpacked into a map, which nothing then uses.
;------------------------------------------------------------------------------
disk_pack:	; from: main
	link	a6,#-68                         ; 68 bytes of locals
	movem.l	d6-d7,-(sp)                     ; keep the registers
	pea	alert_pack_which_drive          ; "Pack disk in which drive?" A or B
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	subq.w	#1,d0                           ; 0 or 1
	move.w	d0,d7                           ; d7 = the drive
	pea	text_root_pack                  ; "\"
	pea	dpk_path                        ; the path
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_dpk_mask_pack              ; "*.DPK"
	pea	dpk_path                        ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	cmpi.w	#$1,d7                          ; drive B?
	bne.s	disk_pack_name_b                ; no
	pea	text_drivea_pack                ; "DRIVEA.DPK"
	pea	dpk_name                        ; the name
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	bra.s	disk_pack_choose
disk_pack_name_b:
	pea	text_driveb_pack                ; "DRIVEB.DPK"
	pea	dpk_name                        ; the name
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
disk_pack_choose:
	pea	text_choose_destination         ; "Choose the destination pathname"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	dpk_path                        ; the path chosen
	pea	dpk_name                        ; the name
	pea	dpk_path                        ; the path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.s	disk_pack_cancelled             ; no
	pea	text_dpk_pack                   ; "DPK"
	pea	dpk_path                        ; as its extension
	jsr	set_extension
	addq.l	#8,sp                           ; drop the arguments
	bra.s	disk_pack_go
disk_pack_cancelled:
	jsr	clear_title                     ; the title line cleared
	clr.l	-(sp)                           ; no alert
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_go:
	jsr	clear_title                     ; the title line cleared
	clr.w	-(sp)                           ; normal file
	pea	dpk_path                        ; the DPK file
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d6                           ; d6 = the handle
	tst.w	d0                              ; created?
	bge.s	disk_pack_bpb                   ; yes
	pea	alert_cannot_create_file        ; no: "Can't create file."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_bpb:
	move.w	d7,-(sp)                        ; the drive
	jsr	read_boot_sector                ; read its boot sector
	addq.l	#2,sp                           ; drop the arguments
	move.w	disk_sectors,-$6(a6)            ; the sectors to pack
	move.w	d7,-(sp)                        ; the drive
	move.w	#$7,-(sp)                       ; Mediach
	jsr	bios
	addq.l	#4,sp                           ; drop the arguments
	move.w	disk_sides,-(sp)                ; sides
	move.w	disk_tracks,-(sp)               ; tracks
	move.w	disk_spt,-(sp)                  ; sectors a track
	move.w	d6,-(sp)                        ; the DPK file
	jsr	write_dpk_header                ; the header
	addq.l	#8,sp                           ; drop the arguments
	tst.w	d0                              ; all right?
	bge.s	disk_pack_info                  ; yes
	move.w	#$ffff,d0                       ; no: -1
	bra.w	disk_pack_done
disk_pack_info:
	move.w	d7,-(sp)                        ; the drive
	jsr	show_disk_info                  ; the disk info
	addq.l	#2,sp                           ; drop the arguments
	pea	text_zero_to_pack               ; "0 to "
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; the sectors line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	work_text
	move.w	system_sectors,d0               ; the system sectors
	subq.w	#1,d0                           ; less 1
	move.w	d0,-(sp)                        ; argument 1
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	pea	work_text
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; after it
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	text_reading_system             ; "Reading Sectors"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_disk_pack_progress         ; "Disk Pack Progress"
	pea	-$40(a6)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	lea	-$40(a6),a0
	move.l	a0,d0
	movea.l	tree_disk,a0                    ; the progress box
	movea.l	$24(a0),a0                      ; its title's TEDINFO
	move.l	d0,(a0)                         ; its text
	pea	-$40(a6)                        ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	movea.l	$24(a0),a0
	move.w	d0,$18(a0)                      ; its length
	move.l	screen_buffer,-(sp)             ; the screen
	move.l	screen,-(sp)                    ; saved
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	pea	disk_rect                       ; its box
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	open_box                        ; opened
	addq.l	#8,sp                           ; drop the arguments
	pea	packometer_rect                 ; its box
	move.l	tree_packometer,-(sp)           ; the packometer
	jsr	open_box                        ; opened
	addq.l	#8,sp                           ; drop the arguments
	move.w	8(a6),d0                        ; Use FAT?
	beq.w	disk_pack_buffer                ; no
	move.w	cluster_count,d0                ; the clusters
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$44(a6)                     ; the map
	tst.l	-$44(a6)                        ; got it?
	bne.s	disk_pack_fat                   ; yes
	pea	alert_insufficient_memory       ; no: "Insufficient Memory."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_fat:
	move.w	fat_sectors,d0                  ; the sectors a FAT
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2
	asl.l	#8,d0                           ; * 256: * 512 bytes
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$12(a6)                     ; the FAT buffer
	tst.l	-$12(a6)                        ; got it?
	bne.s	disk_pack_read_fat              ; yes
	move.l	-$44(a6),-(sp)                  ; no: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_insufficient_memory       ; "Insufficient Memory."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_read_fat:
	move.w	d7,-(sp)                        ; the drive
	move.w	#$1,-(sp)                       ; from sector 1
	move.w	fat_sectors,-(sp)               ; the FAT's sectors
	move.l	-$12(a6),-(sp)                  ; the FAT buffer
	move.w	#$2,-(sp)                       ; read, no media change
	move.w	#$4,-(sp)                       ; Rwabs
	jsr	bios
	lea	$e(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	disk_pack_map_fat               ; yes
	move.l	-$12(a6),-(sp)                  ; no: the FAT buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	-$44(a6),-(sp)                  ; the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_cannot_read_fat           ; "Can't read FAT"
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_map_fat:
	move.l	-$44(a6),-(sp)                  ; the map
	move.l	-$12(a6),d0                     ; the FAT
	addq.l	#3,d0                           ; past the media byte entries
	move.l	d0,-(sp)                        ; argument 1
	jsr	unpack_fat                      ; unpacked into the map
	addq.l	#8,sp                           ; drop the arguments
	move.l	-$12(a6),-(sp)                  ; the FAT buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_buffer:
	move.l	#$4b800,-(sp)                   ; $4b800 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$e(a6)                      ; the buffer
	tst.l	-$e(a6)                         ; got it?
	bne.s	disk_pack_read_system           ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_no_memory             ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_no_memory:
	pea	alert_insufficient_memory       ; "Insufficient Memory."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_read_system:
	move.w	d7,-(sp)                        ; the drive
	clr.w	-(sp)                           ; from sector 0
	move.w	system_sectors,-(sp)            ; the system sectors
	move.l	-$e(a6),d0                      ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 2
	move.w	#$2,-(sp)                       ; read, no media change
	move.w	#$4,-(sp)                       ; Rwabs
	jsr	bios
	lea	$e(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	disk_pack_system                ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_system_failed         ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_system_failed:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_system:
	pea	text_packing_system             ; "Packing Sectors"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$1,-(sp)                       ; depth 1
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	pea	-$a(a6)                         ; the packed data's address comes back here
	move.w	system_sectors,d0               ; the system sectors
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2
	asl.l	#8,d0                           ; * 256: bytes
	move.l	d0,-(sp)
	move.l	-$e(a6),d0                      ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzh                        ; pack them
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,chunk_length                 ; the packed length
	pea	chunk_length                    ; the length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	disk_pack_system_write          ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_length_failed         ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_length_failed:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_system_write:
	move.l	-$a(a6),-(sp)                   ; the packed data
	move.l	chunk_length,-(sp)              ; its length
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	chunk_length,d0                 ; all written?
	beq.s	disk_pack_system_done           ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_data_failed           ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_data_failed:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_system_done:
	move.w	system_sectors,d0               ; the system sectors
	sub.w	d0,-$6(a6)                      ; less: the sectors left
disk_pack_chunk:
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_packometer,-(sp)           ; the packometer
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	pea	text_reading_chunk_pack         ; "Reading Sectors"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	move.l	$54(a0),-(sp)                   ; "Sectors Remaining:"
	move.w	-$6(a6),-(sp)                   ; the sectors left
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; the sectors line
	move.w	disk_sectors,d0                 ; the total
	sub.w	-$6(a6),d0                      ; less the sectors left: the first
	move.w	d0,-(sp)                        ; argument 1
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	pea	text_to_pack                    ; " to "
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	cmpi.w	#$258,-$6(a6)                   ; 600 or more left?
	bge.s	disk_pack_chunk_last            ; yes
	pea	work_text
	move.w	disk_sectors,d0                 ; the last: the total
	subq.w	#1,d0                           ; less 1
	move.w	d0,-(sp)                        ; argument 1
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	bra.s	disk_pack_chunk_shown
disk_pack_chunk_last:
	pea	work_text
	move.w	#$258,d0                        ; 600
	add.w	disk_sectors,d0                 ; + the total
	sub.w	-$6(a6),d0                      ; less the sectors left
	subq.w	#1,d0                           ; less 1
	move.w	d0,-(sp)                        ; argument 1
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
disk_pack_chunk_shown:
	pea	work_text
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; after it
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$1,-(sp)                       ; depth 1
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	cmpi.w	#$258,-$6(a6)                   ; 600 or more left?
	bge.s	disk_pack_read_600              ; yes
	move.w	d7,-(sp)                        ; the drive
	move.w	disk_sectors,d0                 ; the total
	sub.w	-$6(a6),d0                      ; less the sectors left: the first
	move.w	d0,-(sp)
	move.w	-$6(a6),-(sp)                   ; the sectors left
	move.l	-$e(a6),d0                      ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 2
	clr.w	-(sp)                           ; read
	move.w	#$4,-(sp)                       ; Rwabs
	jsr	bios
	lea	$e(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	disk_pack_chunk_read            ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_read_failed           ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_read_failed:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_chunk_read:
	bra.s	disk_pack_chunk_pack
disk_pack_read_600:
	move.w	d7,-(sp)                        ; the drive
	move.w	disk_sectors,d0                 ; the total
	sub.w	-$6(a6),d0                      ; less the sectors left: the first
	move.w	d0,-(sp)
	move.w	#$258,-(sp)                     ; 600 sectors
	move.l	-$e(a6),d0                      ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 2
	clr.w	-(sp)                           ; read
	move.w	#$4,-(sp)                       ; Rwabs
	jsr	bios
	lea	$e(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	disk_pack_chunk_pack            ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_read_600_failed       ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_read_600_failed:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_chunk_pack:
	pea	text_packing_chunk              ; "Packing Sectors"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$1,-(sp)                       ; depth 1
	move.w	#$2,-(sp)                       ; from object 2
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	cmpi.w	#$258,-$6(a6)                   ; 600 or more left?
	bge.s	disk_pack_chunk_pack_600        ; yes
	pea	-$a(a6)                         ; the packed data's address comes back here
	move.w	-$6(a6),d0                      ; the sectors left
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2
	asl.l	#8,d0                           ; * 256: bytes
	move.l	d0,-(sp)
	move.l	-$e(a6),d0                      ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzh                        ; pack them
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,chunk_length                 ; the packed length
	bra.s	disk_pack_chunk_write
disk_pack_chunk_pack_600:
	pea	-$a(a6)                         ; the packed data's address comes back here
	move.l	#$4b000,-(sp)                   ; 600 sectors
	move.l	-$e(a6),d0                      ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzh                        ; pack them
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,chunk_length                 ; the packed length
disk_pack_chunk_write:
	pea	chunk_length                    ; the length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	disk_pack_chunk_data            ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_chunk_length_failed   ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_chunk_length_failed:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_chunk_data:
	move.l	-$a(a6),-(sp)                   ; the packed data
	move.l	chunk_length,-(sp)              ; its length
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	chunk_length,d0                 ; all written?
	beq.s	disk_pack_chunk_done            ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_chunk_data_failed     ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_chunk_data_failed:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_chunk_done:
	subi.w	#$258,-$6(a6)                   ; 600 fewer left
	tst.w	-$6(a6)                         ; any left?
	bgt.w	disk_pack_chunk                 ; yes: the next chunk
	move.l	#$ffffffff,chunk_length         ; the end: -1
	pea	chunk_length                    ; argument 3
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d6,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	disk_pack_close                 ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_end_failed            ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_end_failed:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	d6,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.s	disk_pack_done
disk_pack_close:
	move.w	d6,-(sp)                        ; the DPK file
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	8(a6),d0                        ; Use FAT?
	beq.s	disk_pack_free                  ; no
	move.l	-$44(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_free:
	move.l	-$e(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
disk_pack_done:
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; show_disk_info(drive): the drive letter, sides, sectors a track, tracks and total sectors into the progress
; box, and the total as the sectors remaining.
;------------------------------------------------------------------------------
show_disk_info:	; from: disk_unpack, disk_pack
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.w	8(a6),d7                        ; the drive
	tst.w	d7                              ; A?
	bne.s	show_disk_info_b                ; no
	movea.l	tree_disk,a0
	movea.l	$15c(a0),a0                     ; the drive's text
	move.b	#$41,(a0)                       ; 'A'
	bra.s	show_disk_info_sides
show_disk_info_b:
	movea.l	tree_disk,a0
	movea.l	$15c(a0),a0                     ; the drive's text
	move.b	#$42,(a0)                       ; 'B'
show_disk_info_sides:
	movea.l	tree_disk,a0
	movea.l	$e4(a0),a0                      ; the sides' text
	move.b	#$20,(a0)                       ; a space first
	movea.l	tree_disk,a0
	move.l	$e4(a0),d0
	addq.l	#1,d0                           ; after it
	move.l	d0,-(sp)                        ; argument 2
	move.w	disk_sides,-(sp)                ; the sides
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	move.l	$144(a0),-(sp)                  ; the tracks' text
	move.w	disk_tracks,-(sp)               ; the tracks
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	cmpi.w	#$a,disk_spt                    ; sectors a track under 10?
	bge.s	show_disk_info_spt              ; no
	movea.l	tree_disk,a0
	movea.l	$fc(a0),a0                      ; the sectors a track's text
	move.b	#$20,(a0)                       ; a space first
	movea.l	tree_disk,a0
	move.l	$fc(a0),d0
	addq.l	#1,d0                           ; after it
	move.l	d0,-(sp)                        ; argument 2
	move.w	disk_spt,-(sp)                  ; the sectors a track
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	bra.s	show_disk_info_total
show_disk_info_spt:
	movea.l	tree_disk,a0
	move.l	$fc(a0),-(sp)                   ; the sectors a track's text
	move.w	disk_spt,-(sp)                  ; the sectors a track
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
show_disk_info_total:
	movea.l	tree_disk,a0
	move.l	$1bc(a0),-(sp)                  ; the total's text
	move.w	disk_sectors,-(sp)              ; the total
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	move.l	$54(a0),-(sp)                   ; "Sectors Remaining:"
	move.w	disk_sectors,-(sp)              ; the total
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; unpack_fat(fat, map): the 12 bit FAT entries as words, two from each 3 bytes, for each cluster.
;------------------------------------------------------------------------------
unpack_fat:	; from: disk_pack
	link	a6,#0                           ; the frame
	movea.l	8(a6),a0                        ; the FAT
	movea.l	$c(a6),a1                       ; the map
	move.w	cluster_count,d4                ; the clusters
	subq.w	#1,d4
unpack_fat_loop:
	clr.w	d0
	clr.w	d1
	clr.w	d2
	clr.w	d3
	move.b	(a0)+,d0                        ; 3 bytes
	move.b	(a0)+,d1
	move.b	(a0)+,d2
	move.b	d1,d3
	andi.w	#$f,d1                          ; the first entry's high nibble
	lsl.w	#8,d1
	or.w	d1,d0
	lsr.b	#4,d3                           ; the second's low nibble
	lsl.w	#4,d2
	or.w	d2,d3
	move.w	d0,(a1)+                        ; the first entry
	move.w	d3,(a1)+                        ; the second
	dbra	d4,unpack_fat_loop              ; for each cluster
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; write_dpk_header(handle, sectors a track, tracks, sides): the three words.  On an error disk_error is given
; only the alert.
;------------------------------------------------------------------------------
write_dpk_header:	; from: disk_pack
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.w	8(a6),d7                        ; the handle
	pea	$a(a6)                          ; the sectors a track
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; written?
	beq.s	write_dpk_tracks                ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	jsr	disk_error
	addq.l	#4,sp                           ; drop the arguments
	bra.s	write_dpk_header_done
write_dpk_tracks:
	pea	$c(a6)                          ; the tracks
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; written?
	beq.s	write_dpk_sides                 ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	jsr	disk_error
	addq.l	#4,sp                           ; drop the arguments
	bra.s	write_dpk_header_done
write_dpk_sides:
	pea	$e(a6)                          ; the sides
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; written?
	beq.s	write_dpk_header_done           ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	jsr	disk_error
	addq.l	#4,sp                           ; drop the arguments
	nop
write_dpk_header_done:
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; format_disk(sides, sectors a track, tracks, drive): Flopfmt every track (side 1 too for 2 sides).
; d0 = 1, or 0 on an error.
;------------------------------------------------------------------------------
format_disk:	; from: disk_unpack
	link	a6,#-4                          ; 4 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; sides
	move.w	$a(a6),d6                       ; sectors a track
	move.w	$c(a6),d5                       ; tracks
	move.l	#$2800,-(sp)                    ; $2800 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$4(a6)                      ; the buffer
	clr.w	d4                              ; track 0
	bra.w	format_loop
format_track:
	move.w	#$e5e5,-(sp)                    ; the virgin word
	move.l	#$87654321,-(sp)                ; the magic
	move.w	#$1,-(sp)                       ; interleave 1
	clr.w	-(sp)                           ; side 0
	move.w	d4,-(sp)                        ; the track
	move.w	d6,-(sp)                        ; sectors a track
	move.w	$e(a6),-(sp)                    ; the drive
	clr.l	-(sp)                           ; argument 2
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$a,-(sp)                       ; Flopfmt
	jsr	xbios
	lea	$1a(sp),sp                      ; drop the arguments
	tst.w	d0                              ; all right?
	beq.s	format_side_1                   ; yes
	move.l	-$4(a6),-(sp)                   ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$0,d0                          ; 0
	bra.s	format_disk_done
format_side_1:
	cmpi.w	#$2,d7                          ; 2 sides?
	bne.s	format_next_track               ; no
	move.w	#$e5e5,-(sp)                    ; the virgin word
	move.l	#$87654321,-(sp)                ; the magic
	move.w	#$1,-(sp)                       ; interleave 1
	move.w	#$1,-(sp)                       ; side 1
	move.w	d4,-(sp)                        ; the track
	move.w	d6,-(sp)                        ; sectors a track
	move.w	$e(a6),-(sp)                    ; the drive
	clr.l	-(sp)                           ; argument 2
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$a,-(sp)                       ; Flopfmt
	jsr	xbios
	lea	$1a(sp),sp                      ; drop the arguments
	tst.w	d0                              ; all right?
	beq.s	format_next_track               ; yes
	move.l	-$4(a6),-(sp)                   ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$0,d0                          ; 0
	bra.s	format_disk_done
format_next_track:
	addq.w	#1,d4                           ; next
format_loop:
	move.w	d4,d0
	cmp.w	d5,d0                           ; all done?
	blt.w	format_track                    ; no
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$1,d0                          ; 1
format_disk_done:
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; read_boot_sector(drive): read sector 0 and take the disk's shape from its BPB: sides, sectors a track,
; total sectors and tracks, FAT count and size, reserved and directory sectors, sectors a cluster; the system
; sectors before the data and the cluster count follow.
;------------------------------------------------------------------------------
read_boot_sector:	; from: disk_pack
	link	a6,#-512                        ; 512 bytes of locals
	movem.l	d7,-(sp)                        ; keep the registers
	move.w	8(a6),d7                        ; the drive
	move.w	d7,-(sp)                        ; argument 5
	clr.w	-(sp)                           ; sector 0
	move.w	#$1,-(sp)                       ; 1 sector
	pea	-$200(a6)                       ; into the frame
	move.w	#$2,-(sp)                       ; read, no media change
	move.w	#$4,-(sp)                       ; Rwabs
	jsr	bios
	lea	$e(sp),sp                       ; drop the arguments
	tst.l	d0                              ; all right?
	bge.s	read_boot_sector_bpb            ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	jsr	disk_error
	addq.l	#4,sp                           ; drop the arguments
	bra.w	read_boot_sector_done
read_boot_sector_bpb:
	lea	-$200(a6),a0                    ; the boot sector
	move.w	$1a(a0),d0                      ; sides (Intel order)
	ror.w	#8,d0
	move.w	d0,disk_sides
	move.w	$18(a0),d0                      ; sectors a track
	ror.w	#8,d0
	move.w	d0,disk_spt
	clr.w	d1
	move.b	$14(a0),d1                      ; the total sectors' high byte
	lsl.w	#8,d1
	move.b	$13(a0),d1                      ; and low byte
	move.w	d1,disk_sectors                 ; the total
	divu.w	d0,d1                           ; / sectors a track
	and.l	#$ffff,d1
	divu.w	disk_sides,d1                   ; / sides
	move.w	d1,disk_tracks                  ; = the tracks
	move.b	$10(a0),d0                      ; the FATs
	ext.w	d0                              ; to a word
	move.w	d0,fat_count
	move.w	$16(a0),d0                      ; sectors a FAT
	ror.w	#8,d0
	move.w	d0,fat_sectors
	move.w	$e(a0),d0                       ; reserved sectors
	ror.w	#8,d0
	move.w	d0,reserved_sectors
	move.b	$12(a0),d0                      ; root directory entries' high byte
	lsl.w	#8,d0
	add.b	$11(a0),d0                      ; and low byte
	move.w	d0,dir_entries
	move.b	$d(a0),d0                       ; sectors a cluster
	ext.w	d0                              ; to a word
	move.w	d0,cluster_sectors
	move.w	reserved_sectors,d0             ; the reserved sectors
	move.w	fat_count,d1                    ; + FATs
	muls.w	fat_sectors,d1                  ; * sectors a FAT
	add.w	d1,d0
	move.w	dir_entries,d1                  ; + the directory entries
	asl.w	#5,d1                           ; * 32
	ext.l	d1                              ; to a long
	divs.w	#$200,d1                        ; / 512
	add.w	d1,d0
	move.w	d0,system_sectors               ; = the system sectors
	move.w	disk_sectors,d0                 ; the total
	sub.w	system_sectors,d0               ; less the system sectors
	ext.l	d0                              ; to a long
	divs.w	cluster_sectors,d0              ; / sectors a cluster
	move.w	d0,cluster_count                ; = the clusters
read_boot_sector_done:
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; disk_error(handle, alert): show the alert (if any), close the handle (if any), put the screen back; d0 = -1.
;------------------------------------------------------------------------------
disk_error:	; from: disk_unpack, disk_pack, write_dpk_header, read_boot_sector
	link	a6,#0                           ; the frame
	movem.l	d7/a5,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; the handle
	movea.l	$a(a6),a5                       ; the alert
	move.l	a5,d3
	beq.s	disk_error_close                ; none
	move.l	a5,-(sp)                        ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
disk_error_close:
	tst.w	d7                              ; a handle?
	blt.s	disk_error_screen               ; no
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
disk_error_screen:
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	movem.l	(sp)+,d7/a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; pack_lzh(source, length, &packed): the LZH packer, LHarc 1.13's lzhuf (LZSS over a 4 K window with an
; adaptive Huffman code) compiled from C.  It reads the source from its end and writes the code downwards from
; source + length + $800, so that it can be depacked in place.  The header in front is 'LZH!', the unpacked
; length and the packed length.  *packed = the header; d0 = the packed length + 12.
;------------------------------------------------------------------------------
pack_lzh:	; from: pack_file, multi_pack_file, disk_pack
	link	a6,#-2                          ; 2 bytes of locals
	movem.l	d7/a4-a5,-(sp)                  ; keep the registers
	movea.l	8(a6),a5                        ; the source
	move.l	$c(a6),d7                       ; its length
	movea.l	$10(a6),a4                      ; where the address goes
	clr.l	codesize                        ; no code yet
	clr.l	textsize                        ; nothing read yet
	move.l	a5,lzh_source                   ; the source
	move.l	d7,d0
	subq.l	#1,d0                           ; read from the last byte
	move.l	d0,lzh_source_index
	move.l	a5,d0
	add.l	d7,d0                           ; the source's end
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,lzh_output                   ; is where the code ends
	jsr	encode
	movem.l	d0/a0,-(sp)                     ; keep the registers
	movea.l	lzh_output,a0                   ; the code's start
	move.l	codesize,d0                     ; the packed length
	move.b	d0,(a0)                         ; its bytes, in front
	lsr.l	#8,d0
	move.b	d0,-(a0)
	lsr.l	#8,d0
	move.b	d0,-(a0)
	lsr.l	#8,d0
	move.b	d0,-(a0)
	move.l	d7,d0                           ; the unpacked length
	move.b	d0,-(a0)                        ; its bytes
	lsr.l	#8,d0
	move.b	d0,-(a0)
	lsr.l	#8,d0
	move.b	d0,-(a0)
	lsr.l	#8,d0
	move.b	d0,-(a0)
	move.b	#$21,-(a0)                      ; '!'
	move.b	#$48,-(a0)                      ; 'H'
	move.b	#$5a,-(a0)                      ; 'Z'
	move.b	#$4c,-(a0)                      ; 'L'
	move.l	a0,lzh_output                   ; the header's start
	move.l	codesize,d0                     ; the packed length
	add.l	#$c,d0                          ; + the header
	lea	codesize,a0
	move.l	d0,(a0)
	movem.l	(sp)+,d0/a0                     ; the registers back
	move.l	lzh_output,(a4)                 ; returned
	move.l	codesize,d0                     ; the length
	movem.l	(sp)+,d7/a4-a5                  ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Put a byte of code, downwards.
;------------------------------------------------------------------------------
lzh_putc:	; from: putcode, encode_end
	link	a6,#0                           ; the frame
	movea.l	lzh_output,a0                   ; the output
	move.b	9(a6),(a0)                      ; the byte
	subq.l	#1,lzh_output                   ; down one
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The next source byte, from the end down; -1 when all are read.
;------------------------------------------------------------------------------
lzh_getc:	; from: encode
	link	a6,#0                           ; the frame
	cmpi.l	#$ffffffff,lzh_source_index     ; all read?
	bne.s	lzh_getc_byte                   ; no
	move.w	#$ffff,d0                       ; yes: -1
	bra.s	lzh_getc_done
	bra.s	lzh_getc_done
lzh_getc_byte:
	move.l	lzh_source_index,d0             ; the index
	subq.l	#1,lzh_source_index             ; down one
	movea.l	lzh_source,a0                   ; the source
	move.b	0(a0,d0.l),d0                   ; the byte
	and.w	#$ff,d0                         ; unsigned
	nop
lzh_getc_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; InitTree: the 256 tree roots (rson[N+1] on) and every dad[] set to NIL ($1000).
;------------------------------------------------------------------------------
init_tree:	; from: encode
	link	a6,#0                           ; the frame
	movem.l	a4-a5,-(sp)                     ; keep the registers
	lea	rson,a0                         ; rson
	move.l	a0,d0
	add.l	#$2000,d0                       ; + N
	addq.l	#2,d0                           ; + 2: rson[N+1]
	movea.l	d0,a5
	lea	rson,a0
	move.l	a0,d0
	add.l	#$2000,d0                       ; + N
	add.l	#$2000,d0                       ; + N: the end
	movea.l	d0,a4
	bra.s	init_tree_roots_loop
init_tree_roots:
	move.w	#$1000,(a5)+                    ; NIL
init_tree_roots_loop:
	move.l	a5,d0
	cmp.l	a4,d0
	ble.s	init_tree_roots
	lea	dad,a0                          ; dad
	movea.l	a0,a5
	lea	dad,a0
	move.l	a0,d0
	add.l	#$2000,d0                       ; + N
	movea.l	d0,a4
	bra.s	init_tree_dad_loop
init_tree_dad:
	move.w	#$1000,(a5)+                    ; NIL
init_tree_dad_loop:
	move.l	a5,d0
	cmp.l	a4,d0
	blt.s	init_tree_dad
	movem.l	(sp)+,a4-a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; InsertNode(r): put the string at r into the tree; match_position and match_length = the longest match.
; The same[] lengths kept with each node save comparing what is known to match (LHarc's version).
;------------------------------------------------------------------------------
insert_node:	; from: encode
	link	a6,#-4                          ; 4 bytes of locals
	movem.l	d4-d7/a5,-(sp)                  ; keep the registers
	move.w	8(a6),d7                        ; r
	move.w	#$1,-$2(a6)                     ; cmp = 1
	move.w	d7,d0
	lea	text_buf,a0                     ; text_buf
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a5                           ; key = &text_buf[r]
	move.b	1(a5),d4                        ; the hash from key[1], key[2]
	and.w	#$ff,d4
	move.b	2(a5),d3
	and.w	#$ff,d3
	eor.w	d3,d4
	move.w	d4,d0
	lsr.w	#4,d0
	eor.w	d0,d4
	move.w	#$1001,d6                       ; p = N + 1
	move.b	(a5),d3                         ; + key[0]
	and.w	#$ff,d3
	add.w	d3,d6
	move.w	d4,d1                           ; + the hash's low nibble * 256
	and.w	#$f,d1
	asl.w	#8,d1
	add.w	d1,d6
	move.w	#$1000,d0                       ; NIL
	move.w	d7,d1
	asl.w	#1,d1                           ; * 2: words
	lea	lson,a0                         ; lson[r]
	move.w	d0,0(a0,d1.w)
	move.w	d7,d1
	asl.w	#1,d1                           ; * 2: words
	lea	rson,a0                         ; rson[r]
	move.w	d0,0(a0,d1.w)
	clr.w	match_length                    ; match_length = 0
	move.w	#$1,d4                          ; i = 1
	move.w	d4,-$4(a6)
insert_node_loop:
	tst.w	-$2(a6)                         ; cmp >= 0?
	blt.s	insert_node_left                ; no: left
	move.w	d6,d0
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0                         ; rson[p]
	cmpi.w	#$1000,0(a0,d0.w)               ; NIL?
	beq.s	insert_node_right               ; yes: insert here
	move.w	d6,d0
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	move.w	0(a0,d0.w),d6                   ; p = rson[p]
	lea	same,a0                         ; same[p]
	move.b	0(a0,d6.w),d0
	and.w	#$ff,d0
	move.w	d0,-$4(a6)
	bra.s	insert_node_compare_right
insert_node_right:
	move.w	d6,d0                           ; rson[p] = r
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	move.w	d7,0(a0,d0.w)
	move.w	d7,d0                           ; dad[r] = p
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	d6,0(a0,d0.w)
	move.w	d4,d0                           ; same[r] = i
	lea	same,a0
	move.b	d0,0(a0,d7.w)
	bra.w	insert_node_done
insert_node_compare_right:
	bra.s	insert_node_compare
insert_node_left:
	move.w	d6,d0
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0                         ; lson[p]
	cmpi.w	#$1000,0(a0,d0.w)               ; NIL?
	beq.s	insert_node_left_new            ; yes: insert here
	move.w	d6,d0
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),d6                   ; p = lson[p]
	lea	same,a0                         ; same[p]
	move.b	0(a0,d6.w),d0
	and.w	#$ff,d0
	move.w	d0,-$4(a6)
	bra.s	insert_node_compare
insert_node_left_new:
	move.w	d6,d0                           ; lson[p] = r
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	d7,0(a0,d0.w)
	move.w	d7,d0                           ; dad[r] = p
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	d6,0(a0,d0.w)
	move.w	d4,d0                           ; same[r] = i
	lea	same,a0
	move.b	d0,0(a0,d7.w)
	bra.w	insert_node_done
insert_node_compare:
	move.w	d4,d0                           ; i > same[p]?
	cmp.w	-$4(a6),d0
	bls.s	insert_node_equal               ; no
	move.w	-$4(a6),d4                      ; yes: i = same[p]
	move.w	d6,d1
	add.w	d4,d1
	lea	text_buf,a0
	move.b	0(a0,d1.w),d1                   ; text_buf[p + i]
	move.b	0(a5,d4.w),d0                   ; key[i]
	and.w	#$ff,d0
	and.w	#$ff,d1
	sub.w	d1,d0                           ; cmp = the difference
	move.w	d0,-$2(a6)
	bra.s	insert_node_found
insert_node_equal:
	move.w	d4,d0                           ; i = same[p]?
	cmp.w	-$4(a6),d0
	bne.s	insert_node_found               ; no
	bra.s	insert_node_scan_loop
insert_node_scan:
	move.w	d6,d1
	add.w	d4,d1
	lea	text_buf,a0
	move.b	0(a0,d1.w),d1                   ; text_buf[p + i]
	move.b	0(a5,d4.w),d0                   ; key[i]
	and.w	#$ff,d0
	and.w	#$ff,d1
	sub.w	d1,d0
	move.w	d0,-$2(a6)                      ; cmp
	tst.w	d0                              ; different?
	beq.s	insert_node_scan_next           ; no
	bra.s	insert_node_found               ; yes
insert_node_scan_next:
	addq.w	#1,d4                           ; i++
insert_node_scan_loop:
	cmpi.w	#$3c,d4                         ; up to F (60)
	bcs.s	insert_node_scan
insert_node_found:
	cmpi.w	#$2,d4                          ; longer than 2?
	bls.s	insert_node_next                ; no
	move.w	d4,d0
	cmp.w	match_length,d0                 ; longer than match_length?
	bls.s	insert_node_same_length         ; no
	move.w	d7,d0                           ; yes: match_position = (r - p) & (N-1) - 1
	sub.w	d6,d0
	and.w	#$fff,d0
	subq.w	#1,d0
	move.w	d0,match_position
	move.w	d4,d0
	move.w	d0,match_length                 ; match_length = i
	cmpi.w	#$3c,d0                         ; F?
	bcs.s	insert_node_longer              ; no
	bra.s	insert_node_replace             ; yes: the whole string: replace p by r
insert_node_longer:
	bra.s	insert_node_next
insert_node_same_length:
	move.w	d4,d0                           ; the same length?
	cmp.w	match_length,d0
	bne.s	insert_node_next                ; no
	move.w	d7,d0                           ; yes: a nearer one?
	sub.w	d6,d0
	and.w	#$fff,d0
	subq.w	#1,d0
	move.w	d0,d5
	cmp.w	match_position,d0
	bcc.s	insert_node_next                ; no
	move.w	d5,match_position               ; yes
insert_node_next:
	bra.w	insert_node_loop                ; on
insert_node_replace:
	lea	same,a0                         ; r takes p's place: same[r] = same[p]
	move.b	0(a0,d6.w),d0
	lea	same,a0
	and.w	#$ff,d0
	move.b	d0,0(a0,d7.w)
	move.w	d6,d0                           ; dad[r] = dad[p]
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	move.w	d7,d1
	asl.w	#1,d1                           ; * 2: words
	lea	dad,a0
	move.w	d0,0(a0,d1.w)
	move.w	d6,d0                           ; lson[r] = lson[p]
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),d0
	move.w	d7,d1
	asl.w	#1,d1                           ; * 2: words
	lea	lson,a0
	move.w	d0,0(a0,d1.w)
	move.w	d6,d0                           ; rson[r] = rson[p]
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	move.w	0(a0,d0.w),d0
	move.w	d7,d1
	asl.w	#1,d1                           ; * 2: words
	lea	rson,a0
	move.w	d0,0(a0,d1.w)
	move.w	d6,d0                           ; dad[lson[p]] = r
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	dad,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	d7,(a0)
	move.w	d6,d0                           ; dad[rson[p]] = r
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	dad,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	d7,(a0)
	move.w	d6,d0                           ; p its parent's right child?
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	rson,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	(a0),d0
	cmp.w	d6,d0
	bne.s	insert_node_replace_left        ; no
	move.w	d6,d0                           ; yes: rson[dad[p]] = r
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	rson,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	d7,(a0)
	bra.s	insert_node_remove
insert_node_replace_left:
	move.w	d6,d0                           ; lson[dad[p]] = r
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	lson,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	d7,(a0)
insert_node_remove:
	move.w	d6,d0                           ; dad[p] = NIL
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	#$1000,0(a0,d0.w)
insert_node_done:
	movem.l	(sp)+,d4-d7/a5                  ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; link(n, p, q): same[q] = how far the strings at p and q match from n on (all of F when q is NIL).
;------------------------------------------------------------------------------
lzh_link:	; from: lzh_linknode, delete_node
	link	a6,#0                           ; the frame
	movem.l	a3-a5,-(sp)                     ; keep the registers
	cmpi.w	#$1000,$a(a6)                   ; p at NIL?
	blt.s	lzh_link_compare                ; no
	move.w	$c(a6),d0
	lea	same,a0
	move.b	#$1,0(a0,d0.w)                  ; same[q] = 1
	bra.w	lzh_link_done
lzh_link_compare:
	lea	text_buf,a0
	move.l	a0,d0
	move.w	$a(a6),d3
	ext.l	d3                              ; to a long
	add.l	d3,d0                           ; + p + n
	move.w	8(a6),d3
	ext.l	d3                              ; to a long
	add.l	d3,d0
	movea.l	d0,a5                           ; s1
	lea	text_buf,a0
	move.l	a0,d0
	move.w	$c(a6),d3
	ext.l	d3                              ; to a long
	add.l	d3,d0
	move.w	8(a6),d3
	ext.l	d3                              ; to a long
	add.l	d3,d0
	movea.l	d0,a4                           ; s2 = text_buf + q + n
	lea	text_buf,a0
	move.l	a0,d0
	move.w	$a(a6),d3
	ext.l	d3                              ; to a long
	add.l	d3,d0
	add.l	#$3c,d0                         ; + F
	movea.l	d0,a3                           ; s3 = text_buf + p + F
	bra.s	lzh_link_next
lzh_link_loop:
	move.b	(a5)+,d0
	and.w	#$ff,d0
	cmp.b	(a4)+,d0                        ; the same?
	beq.s	lzh_link_next                   ; yes: on
	move.l	a5,d0                           ; no: same[q] = the length matched
	subq.l	#1,d0
	lea	text_buf,a0
	sub.l	a0,d0
	sub.w	$a(a6),d0
	move.w	$c(a6),d1
	lea	same,a0
	move.b	d0,0(a0,d1.w)
	bra.s	lzh_link_done
lzh_link_next:
	move.l	a5,d0
	cmp.l	a3,d0                           ; to F?
	blt.s	lzh_link_loop                   ; no: on
	move.w	$c(a6),d0
	lea	same,a0
	move.b	#$3c,0(a0,d0.w)                 ; same[q] = F
lzh_link_done:
	movem.l	(sp)+,a3-a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; linknode(p, q, r): after a node moves, keep same[r] right: equal same values need a new comparison.
;------------------------------------------------------------------------------
lzh_linknode:	; from: delete_node
	link	a6,#-2                          ; 2 bytes of locals
	move.w	$a(a6),d0
	lea	same,a0
	move.b	0(a0,d0.w),d0                   ; same[q]
	move.w	$c(a6),d1
	lea	same,a0
	and.w	#$ff,d0
	move.b	0(a0,d1.w),d3                   ; same[r]
	and.w	#$ff,d3
	sub.w	d3,d0                           ; the difference
	move.w	d0,-$2(a6)
	tst.w	d0                              ; equal?
	bne.s	lzh_linknode_less               ; no
	move.w	$c(a6),-(sp)                    ; r
	move.w	8(a6),-(sp)                     ; p
	move.w	$a(a6),d0
	lea	same,a0
	move.b	0(a0,d0.w),d0
	and.w	#$ff,d0
	move.w	d0,-(sp)                        ; n = same[q]
	jsr	lzh_link                        ; link(n, p, r)
	addq.l	#6,sp                           ; drop the arguments
	bra.s	lzh_linknode_done
lzh_linknode_less:
	tst.w	-$2(a6)                         ; same[q] smaller?
	bge.s	lzh_linknode_done               ; no
	move.w	$a(a6),d0                       ; yes: same[r] = same[q]
	lea	same,a0
	move.b	0(a0,d0.w),d0
	move.w	$c(a6),d1
	lea	same,a0
	and.w	#$ff,d0
	move.b	d0,0(a0,d1.w)
lzh_linknode_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; DeleteNode(p): take the string at p out of the tree, fixing the same[] lengths around it.
;------------------------------------------------------------------------------
delete_node:	; from: encode
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; p
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0                          ; dad[p] NIL?
	cmpi.w	#$1000,0(a0,d0.w)
	bne.s	delete_node_in                  ; no
	bra.w	delete_node_done                ; yes: not in the tree
delete_node_in:
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0                         ; rson[p] NIL?
	cmpi.w	#$1000,0(a0,d0.w)
	bne.s	delete_node_check_left          ; no
	move.w	d7,d0                           ; yes: q = lson[p]
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),d0
	move.w	d0,d6
	cmpi.w	#$1000,d0                       ; NIL?
	beq.s	delete_node_right_nil           ; yes
	move.w	d6,-(sp)                        ; q
	move.w	d7,-(sp)                        ; p
	move.w	d7,d0                           ; dad[p]
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),-(sp)                ; argument 1
	jsr	lzh_linknode                    ; linknode
	addq.l	#6,sp                           ; drop the arguments
delete_node_right_nil:
	bra.w	delete_node_replace
delete_node_check_left:
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0                         ; lson[p] NIL?
	cmpi.w	#$1000,0(a0,d0.w)
	bne.s	delete_node_both                ; no
	move.w	d7,d6                           ; yes: q = rson[p]
	asl.w	#1,d6                           ; * 2: words
	lea	rson,a0
	move.w	0(a0,d6.w),d6
	move.w	d6,-(sp)                        ; q
	move.w	d7,-(sp)                        ; p
	move.w	d7,d0                           ; dad[p]
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),-(sp)                ; argument 1
	jsr	lzh_linknode                    ; linknode
	addq.l	#6,sp                           ; drop the arguments
	bra.w	delete_node_replace
delete_node_both:
	move.w	d7,d6                           ; q = lson[p]
	asl.w	#1,d6                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d6.w),d6
	move.w	d6,d0                           ; rson[q] NIL?
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	cmpi.w	#$1000,0(a0,d0.w)
	beq.w	delete_node_relink              ; yes
delete_node_rightmost:
	move.w	d6,d0                           ; q = rson[q]
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	move.w	0(a0,d0.w),d6
	move.w	d6,d0                           ; to the rightmost
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	cmpi.w	#$1000,0(a0,d0.w)
	bne.s	delete_node_rightmost
	move.w	d6,d0                           ; lson[q] NIL?
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	cmpi.w	#$1000,0(a0,d0.w)
	beq.s	delete_node_unlink              ; yes
	move.w	d6,d0                           ; lson[q]
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),-(sp)
	move.w	d6,-(sp)                        ; q
	move.w	d6,d0                           ; dad[q]
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),-(sp)                ; argument 1
	jsr	lzh_linknode                    ; linknode
	addq.l	#6,sp                           ; drop the arguments
delete_node_unlink:
	move.w	d7,d0                           ; lson[p]
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),-(sp)                ; argument 3
	move.w	d6,-(sp)                        ; q
	move.w	#$1,-(sp)                       ; n = 1
	jsr	lzh_link                        ; link
	addq.l	#6,sp                           ; drop the arguments
	move.w	d6,d0                           ; rson[dad[q]] = lson[q]
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),d0
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d1.w),d1
	asl.w	#1,d1
	lea	rson,a0
	ext.l	d1                              ; to a long
	add.l	a0,d1
	movea.l	d1,a0
	move.w	d0,(a0)
	move.w	d6,d0                           ; dad[lson[q]] = dad[q]
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d1.w),d1
	asl.w	#1,d1
	lea	dad,a0
	ext.l	d1                              ; to a long
	add.l	a0,d1
	movea.l	d1,a0
	move.w	d0,(a0)
	move.w	d7,d0                           ; lson[q] = lson[p]
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),d0
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	lson,a0
	move.w	d0,0(a0,d1.w)
	move.w	d7,d0                           ; dad[lson[p]] = q
	asl.w	#1,d0                           ; * 2: words
	lea	lson,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	dad,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	d6,(a0)
delete_node_relink:
	move.w	d6,-(sp)                        ; q
	move.w	d7,d0                           ; dad[p]
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),-(sp)                ; argument 2
	move.w	#$1,-(sp)                       ; n = 1
	jsr	lzh_link                        ; link
	addq.l	#6,sp                           ; drop the arguments
	move.w	d7,d0                           ; rson[p]
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	move.w	0(a0,d0.w),-(sp)                ; argument 3
	move.w	d6,-(sp)                        ; q
	move.w	#$1,-(sp)                       ; n = 1
	jsr	lzh_link                        ; link
	addq.l	#6,sp                           ; drop the arguments
	move.w	d7,d0                           ; rson[q] = rson[p]
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	move.w	0(a0,d0.w),d0
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	rson,a0
	move.w	d0,0(a0,d1.w)
	move.w	d7,d0                           ; dad[rson[p]] = q
	asl.w	#1,d0                           ; * 2: words
	lea	rson,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	dad,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	d6,(a0)
delete_node_replace:
	move.w	d7,d0                           ; dad[q] = dad[p]
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	dad,a0
	move.w	d0,0(a0,d1.w)
	move.w	d7,d0                           ; p its parent's right child?
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	rson,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	(a0),d0
	cmp.w	d7,d0
	bne.s	delete_node_left_child          ; no
	move.w	d7,d0                           ; yes: rson[dad[p]] = q
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	rson,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	d6,(a0)
	bra.s	delete_node_remove
delete_node_left_child:
	move.w	d7,d0                           ; lson[dad[p]] = q
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	0(a0,d0.w),d0
	asl.w	#1,d0
	lea	lson,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a0
	move.w	d6,(a0)
delete_node_remove:
	move.w	d7,d0                           ; dad[p] = NIL
	asl.w	#1,d0                           ; * 2: words
	lea	dad,a0
	move.w	#$1000,0(a0,d0.w)
delete_node_done:
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Putcode(l, c): the top l bits of c into the code, through putbuf and putlen.
;------------------------------------------------------------------------------
putcode:	; from: encode_char, encode_position
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; l
	move.w	$a(a6),d6                       ; c
	move.b	lzh_putlen,d5                   ; putlen
	and.w	#$ff,d5
	move.w	lzh_putbuf,d4                   ; putbuf
	move.w	d6,d0
	lsr.w	d5,d0                           ; c >> putlen
	or.w	d0,d4                           ; into putbuf
	move.w	d5,d0
	add.w	d7,d0                           ; + l
	move.w	d0,d5
	cmpi.w	#$8,d0                          ; 8 or more?
	blt.s	putcode_done                    ; no
	move.w	d4,d0                           ; yes: the high byte out
	lsr.w	#8,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	lzh_putc
	addq.l	#2,sp                           ; drop the arguments
	move.w	d5,d0
	subq.w	#8,d0
	move.w	d0,d5                           ; less 8
	cmpi.w	#$8,d0                          ; 8 or more still?
	blt.s	putcode_shift                   ; no
	move.w	d4,-(sp)                        ; yes: the low byte out
	jsr	lzh_putc
	addq.l	#2,sp                           ; drop the arguments
	addq.l	#2,codesize                     ; codesize + 2
	subq.w	#8,d5
	move.w	d6,d4                           ; putbuf = c << (l - putlen)
	move.w	d7,d1
	sub.w	d5,d1
	asl.w	d1,d4
	bra.s	putcode_done
putcode_shift:
	move.w	d4,d0                           ; putbuf << 8
	asl.w	#8,d0
	move.w	d0,d4
	addq.l	#1,codesize                     ; codesize + 1
putcode_done:
	move.w	d4,lzh_putbuf                   ; putbuf
	move.w	d5,d0
	move.b	d0,lzh_putlen                   ; putlen
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; StartHuff: every character's frequency 1, the tree built up from them, the code buffers empty.
;------------------------------------------------------------------------------
start_huff:	; from: encode
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	clr.w	d7                              ; i = 0
	bra.s	start_huff_leaves_loop
start_huff_leaves:
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	freq,a0                         ; freq[i] = 1
	move.w	#$1,0(a0,d0.w)
	move.w	d7,d0
	add.w	#$273,d0                        ; + T
	move.w	d7,d1
	asl.w	#1,d1                           ; son[i] = i + T
	lea	son,a0
	move.w	d0,0(a0,d1.w)
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	prnt+$4e6,a0                    ; prnt[i + T] = i
	move.w	d7,0(a0,d0.w)
	addq.w	#1,d7
start_huff_leaves_loop:
	cmpi.w	#$13a,d7                        ; N_CHAR (314)
	blt.s	start_huff_leaves
	clr.w	d7                              ; i = 0
	move.w	#$13a,d6                        ; j = N_CHAR
	bra.s	start_huff_nodes_loop
start_huff_nodes:
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	freq,a0                         ; freq[i]
	move.w	0(a0,d0.w),d0
	move.w	d7,d1
	asl.w	#1,d1                           ; * 2: words
	lea	freq+2,a0                       ; + freq[i + 1]
	add.w	0(a0,d1.w),d0
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	freq,a0                         ; freq[j]
	move.w	d0,0(a0,d1.w)
	move.w	d6,d0
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0                          ; son[j] = i
	move.w	d7,0(a0,d0.w)
	move.w	d6,d0
	move.w	d7,d1
	asl.w	#1,d1                           ; * 2: words
	lea	prnt+2,a0
	move.w	d0,0(a0,d1.w)                   ; prnt[i + 1] = j
	move.w	d7,d1
	asl.w	#1,d1                           ; * 2: words
	lea	prnt,a0
	move.w	d0,0(a0,d1.w)                   ; prnt[i] = j
	addq.w	#2,d7                           ; i += 2
	addq.w	#1,d6                           ; j++
start_huff_nodes_loop:
	cmpi.w	#$272,d6                        ; to R (T - 1)
	ble.s	start_huff_nodes
	move.w	#$ffff,freq+$4e6                ; freq[T] = $ffff
	clr.w	prnt+$4e4                       ; prnt[R] = 0
	move.b	#$0,d0
	and.w	#$ff,d0
	move.b	d0,lzh_getlen                   ; getlen = 0
	move.b	d0,lzh_putlen                   ; putlen = 0
	move.w	#$0,d0
	move.w	d0,lzh_getbuf                   ; getbuf = 0
	move.w	d0,lzh_putbuf                   ; putbuf = 0
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; reconst: the frequencies halved and the tree rebuilt, when the root's frequency reaches $8000.
;------------------------------------------------------------------------------
reconst:	; from: update
	link	a6,#-16                         ; 16 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	clr.w	d6                              ; j = 0
	clr.w	d7                              ; i = 0: the leaves first, freq halved
	bra.s	reconst_leaves_loop
reconst_leaves:
	move.w	d7,d0                           ; a leaf?
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0
	cmpi.w	#$273,0(a0,d0.w)                ; son[i] >= T?
	blt.s	reconst_leaf_next               ; no
	move.w	d7,d0                           ; freq[j] = (freq[i] + 1) / 2
	asl.w	#1,d0                           ; * 2: words
	lea	freq,a0
	move.w	0(a0,d0.w),d0
	addq.w	#1,d0
	and.l	#$ffff,d0
	divu.w	#$2,d0
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	freq,a0
	move.w	d0,0(a0,d1.w)
	move.w	d7,d0                           ; son[j] = son[i]
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0
	move.w	0(a0,d0.w),d0
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	son,a0
	move.w	d0,0(a0,d1.w)
	addq.w	#1,d6                           ; j++
reconst_leaf_next:
	addq.w	#1,d7                           ; i++
reconst_leaves_loop:
	cmpi.w	#$273,d7                        ; up to T
	blt.s	reconst_leaves
	clr.w	d7                              ; i = 0: then the nodes joined again
	move.w	#$13a,d6                        ; j = N_CHAR
	bra.w	reconst_nodes_loop
reconst_nodes:
	move.w	d7,d5                           ; k = i + 1
	addq.w	#1,d5
	move.w	d7,d4                           ; f = freq[j] = freq[i] + freq[k]
	asl.w	#1,d4                           ; * 2: words
	lea	freq,a0
	move.w	0(a0,d4.w),d4
	move.w	d5,d1
	asl.w	#1,d1                           ; * 2: words
	lea	freq,a0
	add.w	0(a0,d1.w),d4
	move.w	d6,d1
	asl.w	#1,d1                           ; * 2: words
	lea	freq,a0
	move.w	d4,0(a0,d1.w)
	move.w	d6,d5                           ; k = j - 1
	subq.w	#1,d5
	bra.s	reconst_find_loop
reconst_find:
	subq.w	#1,d5                           ; k--
reconst_find_loop:
	move.w	d5,d1                           ; f < freq[k]?
	asl.w	#1,d1                           ; * 2: words
	lea	freq,a0
	move.w	0(a0,d1.w),d1
	move.w	d4,d0
	cmp.w	d1,d0
	bcs.s	reconst_find                    ; yes: down
	addq.w	#1,d5                           ; k++: where the node goes
	move.w	d6,d0                           ; freq[k..j-1] up one, from &freq[j]
	asl.w	#1,d0
	lea	freq,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	move.l	d0,-$4(a6)
	move.w	d5,d0                           ; down to &freq[k]
	asl.w	#1,d0
	lea	freq,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	move.l	d0,-$8(a6)
	bra.s	reconst_shift_freq_loop
reconst_shift_freq:
	movea.l	-$4(a6),a0                      ; freq[n] = freq[n - 1]
	move.w	-$2(a0),d0
	movea.l	-$4(a6),a0
	move.w	d0,(a0)
	subq.l	#2,-$4(a6)                      ; down
reconst_shift_freq_loop:
	move.l	-$4(a6),d0                      ; past &freq[k]?
	cmp.l	-$8(a6),d0
	bgt.s	reconst_shift_freq
	move.w	d5,d0                           ; freq[k] = f
	asl.w	#1,d0                           ; * 2: words
	lea	freq,a0
	move.w	d4,0(a0,d0.w)
	move.w	d6,d0                           ; son[k..j-1] up one, from &son[j]
	asl.w	#1,d0
	lea	son,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	move.l	d0,-$c(a6)
	move.w	d5,d0                           ; down to &son[k]
	asl.w	#1,d0
	lea	son,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	move.l	d0,-$10(a6)
	bra.s	reconst_shift_son_loop
reconst_shift_son:
	movea.l	-$c(a6),a0                      ; son[n] = son[n - 1]
	move.w	-$2(a0),d0
	movea.l	-$c(a6),a0
	move.w	d0,(a0)
	subq.l	#2,-$c(a6)                      ; down
reconst_shift_son_loop:
	move.l	-$c(a6),d0                      ; past &son[k]?
	cmp.l	-$10(a6),d0
	bgt.s	reconst_shift_son
	move.w	d5,d0                           ; son[k] = i
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0
	move.w	d7,0(a0,d0.w)
	addq.w	#2,d7                           ; i += 2
	addq.w	#1,d6                           ; j++
reconst_nodes_loop:
	cmpi.w	#$273,d6                        ; up to T
	blt.w	reconst_nodes
	clr.w	d7                              ; i = 0: then the parents
	bra.s	reconst_parents_loop
reconst_parents:
	move.w	d7,d0                           ; k = son[i]
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0
	move.w	0(a0,d0.w),d0
	move.w	d0,d5
	cmpi.w	#$273,d0                        ; a leaf (>= T)?
	blt.s	reconst_parent_node             ; no
	move.w	d5,d0                           ; prnt[k] = i
	asl.w	#1,d0                           ; * 2: words
	lea	prnt,a0
	move.w	d7,0(a0,d0.w)
	bra.s	reconst_parent_next
reconst_parent_node:
	move.w	d7,d0                           ; prnt[k] = prnt[k + 1] = i
	move.w	d5,d1
	asl.w	#1,d1                           ; * 2: words
	lea	prnt+2,a0
	move.w	d0,0(a0,d1.w)
	move.w	d5,d1
	asl.w	#1,d1                           ; * 2: words
	lea	prnt,a0
	move.w	d0,0(a0,d1.w)
reconst_parent_next:
	addq.w	#1,d7                           ; i++
reconst_parents_loop:
	cmpi.w	#$273,d7                        ; up to T
	blt.s	reconst_parents
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; update(c): count character c once more and move it up the tree while it is more frequent than the next.
;------------------------------------------------------------------------------
update:	; from: encode_char
	link	a6,#0                           ; the frame
	movem.l	d4-d7/a5,-(sp)                  ; keep the registers
	cmpi.w	#$8000,freq+$4e4                ; the root's frequency $8000?
	bne.s	update_start                    ; no
	jsr	reconst                         ; yes: rebuild
update_start:
	move.w	8(a6),d0                        ; c = prnt[c + T]
	asl.w	#1,d0                           ; * 2: words
	lea	prnt+$4e6,a0
	move.w	0(a0,d0.w),8(a6)
update_loop:
	move.w	8(a6),d5                        ; freq[c]++
	asl.w	#1,d5                           ; * 2: words
	lea	freq,a0
	addq.w	#1,0(a0,d5.w)
	move.w	0(a0,d5.w),d5                   ; k = it
	move.w	8(a6),d1                        ; l = c + 1
	addq.w	#1,d1
	move.w	d1,d4
	asl.w	#1,d1                           ; * 2: words
	lea	freq,a0
	move.w	0(a0,d1.w),d1
	move.w	d5,d0
	cmp.w	d1,d0
	bls.w	update_next                     ; more than freq[c + 1]?
	lea	freq,a0                         ; from &freq[l + 1]
	move.l	a0,d0
	move.w	d4,d1
	asl.w	#1,d1
	ext.l	d1                              ; to a long
	add.l	d1,d0
	addq.l	#2,d0
	movea.l	d0,a5
	nop
update_find:
	move.w	d5,d0                           ; the last with a smaller frequency
	cmp.w	(a5)+,d0
	bhi.s	update_find
	move.l	a5,d4                           ; l = the one before it
	lea	freq,a0
	sub.l	a0,d4
	asr.l	#1,d4
	subq.w	#2,d4
	move.w	8(a6),d0                        ; freq[c] = freq[l]
	asl.w	#1,d0                           ; * 2: words
	lea	freq,a0
	move.w	-$4(a5),0(a0,d0.w)
	move.w	d5,-$4(a5)                      ; freq[l] = k
	move.w	8(a6),d7                        ; i = son[c]
	asl.w	#1,d7                           ; * 2: words
	lea	son,a0
	move.w	0(a0,d7.w),d7
	move.w	d7,d0                           ; prnt[i] = l
	asl.w	#1,d0                           ; * 2: words
	lea	prnt,a0
	move.w	d4,0(a0,d0.w)
	cmpi.w	#$273,d7                        ; i < T?
	bge.s	update_swap_son                 ; no
	move.w	d7,d0                           ; prnt[i + 1] = l
	asl.w	#1,d0                           ; * 2: words
	lea	prnt+2,a0
	move.w	d4,0(a0,d0.w)
update_swap_son:
	move.w	d4,d6                           ; j = son[l]
	asl.w	#1,d6                           ; * 2: words
	lea	son,a0
	move.w	0(a0,d6.w),d6
	move.w	d4,d0                           ; son[l] = i
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0
	move.w	d7,0(a0,d0.w)
	move.w	d6,d0                           ; prnt[j] = c
	asl.w	#1,d0                           ; * 2: words
	lea	prnt,a0
	move.w	8(a6),0(a0,d0.w)
	cmpi.w	#$273,d6                        ; j < T?
	bge.s	update_swap_done                ; no
	move.w	d6,d0                           ; prnt[j + 1] = c
	asl.w	#1,d0                           ; * 2: words
	lea	prnt+2,a0
	move.w	8(a6),0(a0,d0.w)
update_swap_done:
	move.w	8(a6),d0                        ; son[c] = j
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0
	move.w	d6,0(a0,d0.w)
	move.w	d4,8(a6)                        ; c = l
update_next:
	move.w	8(a6),d0                        ; c = prnt[c]
	asl.w	#1,d0                           ; * 2: words
	lea	prnt,a0
	move.w	0(a0,d0.w),d0
	move.w	d0,8(a6)
	tst.w	d0                              ; the root?
	bne.w	update_loop                     ; no: on
	movem.l	(sp)+,d4-d7/a5                  ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; EncodeChar(c): the Huffman code of c, from its leaf to the root, written with putcode, then update.
;------------------------------------------------------------------------------
encode_char:	; from: encode
	link	a6,#0                           ; the frame
	movem.l	d5-d7/a5,-(sp)                  ; keep the registers
	clr.l	d7                              ; the code
	clr.w	d6                              ; its length
	lea	prnt,a0                         ; prnt
	movea.l	a0,a5
	move.w	8(a6),d5                        ; c
	and.l	#$ffff,d5
	asl.l	#1,d5
	add.l	a5,d5
	movea.l	d5,a0
	move.w	$4e6(a0),d5                     ; k = prnt[c + T]
encode_char_loop:
	move.l	d7,d0                           ; code >>= 1
	lsr.l	#1,d0
	move.l	d0,d7
	move.w	d5,d0                           ; k odd?
	and.w	#$1,d0
	beq.s	encode_char_next                ; no
	move.l	#$80000000,d0                   ; yes: the bit set
	add.l	d0,d7
encode_char_next:
	addq.w	#1,d6                           ; one more bit
	move.w	d5,d0
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2: words
	move.w	0(a5,d0.l),d0                   ; k = prnt[k]
	move.w	d0,d5
	cmpi.w	#$272,d0                        ; the root?
	bne.s	encode_char_loop                ; no: on
	cmpi.w	#$10,d6                         ; more than 16 bits?
	ble.s	encode_char_short               ; no
	move.l	d7,d0                           ; yes: the top 16
	lsr.l	#8,d0
	lsr.l	#8,d0
	move.w	d0,-(sp)                        ; argument 2
	move.w	#$10,-(sp)                      ; argument 1
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
	move.l	d7,d0                           ; and the rest
	move.w	d0,-(sp)
	move.w	d6,d0
	sub.w	#$10,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
	bra.s	encode_char_update
encode_char_short:
	move.l	d7,d0                           ; the code
	lsr.l	#8,d0
	lsr.l	#8,d0
	move.w	d0,-(sp)                        ; argument 2
	move.w	d6,-(sp)                        ; its length
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
encode_char_update:
	move.w	8(a6),-(sp)                     ; c
	jsr	update
	addq.l	#2,sp                           ; drop the arguments
	movem.l	(sp)+,d5-d7/a5                  ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; EncodePosition(c): the upper 6 bits of the position through p_code/p_len, the lower 6 bits plain.
;------------------------------------------------------------------------------
encode_position:	; from: encode
	link	a6,#-2                          ; 2 bytes of locals
	move.w	8(a6),d0                        ; c >> 6
	lsr.w	#6,d0
	move.w	d0,-$2(a6)
	move.w	-$2(a6),d0
	lea	p_code,a0                       ; p_code
	move.b	0(a0,d0.w),d0                   ; its code
	and.w	#$ff,d0
	asl.w	#8,d0                           ; at the top of the word
	move.w	d0,-(sp)
	move.w	-$2(a6),d0
	lea	p_len,a0                        ; p_len
	move.b	0(a0,d0.w),d0                   ; its length
	and.w	#$ff,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
	move.w	8(a6),d0                        ; c
	and.w	#$3f,d0                         ; the lower 6 bits
	asl.w	#2,d0                           ; at the top of the word
	asl.w	#8,d0
	move.w	d0,-(sp)                        ; argument 2
	move.w	#$6,-(sp)                       ; 6 bits
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; EncodeEnd: the last bits in putbuf out.
;------------------------------------------------------------------------------
encode_end:	; from: encode
	link	a6,#0                           ; the frame
	move.b	lzh_putlen,d0                   ; any left?
	beq.s	encode_end_done                 ; no
	move.w	lzh_putbuf,d0                   ; yes: the high byte
	lsr.w	#8,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	lzh_putc
	addq.l	#2,sp                           ; drop the arguments
	addq.l	#1,codesize                     ; codesize + 1
encode_end_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Encode: LHarc's main loop, with the packometer's bar drawn as the source is read.
;------------------------------------------------------------------------------
encode:	; from: pack_lzh
	link	a6,#-14                         ; 14 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	clr.w	-$e(a6)                         ; no bar lines yet
	move.l	lzh_source_index,d0             ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.w	bar_height,d0                   ; the bar's height
	ext.l	d0                              ; to a long
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.l	d0,bar_step                     ; bytes a bar line
	clr.l	bar_next                        ; the next bar line at 0
	movem.l	d1-d7/a0-a5,-(sp)               ; keep the registers
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp                           ; drop the arguments
	movea.l	d0,a5
	adda.l	#$7d00,a5                       ; + 32000: the screen's end
	move.w	resolution,d0                   ; high resolution?
	cmp.w	#$2,d0
	beq.s	encode_high                     ; yes
	move.l	#$a0,d0                         ; 160 bytes a line
	move.l	d0,-$c(a6)
	mulu.w	bar_offset,d0                   ; times the bar's distance from the bottom
	move.w	bar_column,d1                   ; the bar's column
	mulu.w	#$4,d1                          ; * 4 bytes
	move.l	#$a0,d2
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a5
	move.l	a5,-$8(a6)                      ; the bar's bottom on the screen
	bra.s	encode_start
encode_high:
	move.l	#$50,d0                         ; 80 bytes a line
	move.l	d0,-$c(a6)
	mulu.w	bar_offset,d0                   ; times the bar's distance from the bottom
	move.w	bar_column,d1                   ; the bar's column
	mulu.w	#$2,d1                          ; * 2 bytes
	move.l	#$50,d2
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a5
	move.l	a5,-$8(a6)                      ; the bar's bottom on the screen
encode_start:
	movem.l	(sp)+,d1-d7/a0-a5               ; the registers back
	clr.l	textsize                        ; textsize = 0
	jsr	start_huff                      ; StartHuff
	jsr	init_tree                       ; InitTree
	clr.w	-$2(a6)                         ; s = 0
	move.w	#$fc4,d4                        ; r = N - F
	move.w	-$2(a6),d7
	bra.s	encode_fill_loop
encode_fill:
	lea	text_buf,a0                     ; text_buf[i] = ' '
	move.b	#$20,0(a0,d7.w)
	addq.w	#1,d7
encode_fill_loop:
	move.w	d7,d0                           ; up to r
	cmp.w	d4,d0
	blt.s	encode_fill
	clr.w	d5                              ; len = 0
	bra.s	encode_read_loop
encode_read:
	move.w	d6,d0
	move.w	d4,d1
	add.w	d5,d1
	lea	text_buf,a0
	move.b	d0,0(a0,d1.w)                   ; text_buf[r + len] = c
	addq.w	#1,d5                           ; len++
encode_read_loop:
	cmpi.w	#$3c,d5                         ; up to F
	bge.s	encode_read_done
	jsr	lzh_getc                        ; getc
	move.w	d0,d6
	cmpi.w	#$ffff,d0                       ; the end?
	bne.s	encode_read                     ; no
encode_read_done:
	move.w	d5,d0                           ; textsize = len
	ext.l	d0                              ; to a long
	move.l	d0,textsize
	move.w	#$1,d7                          ; i = 1
	bra.s	encode_insert_loop
encode_insert:
	move.w	d4,d0                           ; r - i
	sub.w	d7,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	insert_node                     ; InsertNode
	addq.l	#2,sp                           ; drop the arguments
	addq.w	#1,d7
encode_insert_loop:
	cmpi.w	#$3c,d7                         ; up to F
	ble.s	encode_insert
	move.w	d4,-(sp)                        ; r
	jsr	insert_node                     ; InsertNode
	addq.l	#2,sp                           ; drop the arguments
encode_loop:
	move.w	match_length,d0                 ; match_length > len?
	move.w	d5,d1
	cmp.w	d1,d0
	bls.s	encode_match                    ; no
	move.w	d5,match_length                 ; yes: match_length = len
encode_match:
	cmpi.w	#$2,match_length                ; more than 2?
	bhi.s	encode_string                   ; yes
	move.w	#$1,match_length                ; no: match_length = 1
	lea	text_buf,a0                     ; text_buf[r]
	move.b	0(a0,d4.w),d0
	and.w	#$ff,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	encode_char                     ; EncodeChar
	addq.l	#2,sp                           ; drop the arguments
	bra.s	encode_advance
encode_string:
	move.w	#$fd,d0                         ; 255 - THRESHOLD + match_length
	add.w	match_length,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	encode_char                     ; EncodeChar
	addq.l	#2,sp                           ; drop the arguments
	move.w	match_position,-(sp)            ; match_position
	jsr	encode_position                 ; EncodePosition
	addq.l	#2,sp                           ; drop the arguments
encode_advance:
	move.w	match_length,-$4(a6)            ; last_match_length
	clr.w	d7                              ; i = 0
	bra.s	encode_advance_loop
encode_advance_read:
	move.w	-$2(a6),-(sp)                   ; s
	jsr	delete_node                     ; DeleteNode
	addq.l	#2,sp                           ; drop the arguments
	move.w	d6,d0
	move.w	-$2(a6),d1
	lea	text_buf,a0
	move.b	d0,0(a0,d1.w)                   ; text_buf[s] = c
	cmpi.w	#$3b,-$2(a6)                    ; s < F - 1?
	bge.s	encode_advance_next             ; no
	move.w	d6,d0                           ; yes: text_buf[s + N] = c too
	move.w	-$2(a6),d1
	lea	text_buf+$1000,a0
	move.b	d0,0(a0,d1.w)
encode_advance_next:
	move.w	-$2(a6),d0                      ; s = (s + 1) & (N - 1)
	addq.w	#1,d0
	and.w	#$fff,d0
	move.w	d0,-$2(a6)
	move.w	d4,d0                           ; r = (r + 1) & (N - 1)
	addq.w	#1,d0
	and.w	#$fff,d0
	move.w	d0,d4
	move.w	d4,-(sp)                        ; argument 1
	jsr	insert_node                     ; InsertNode
	addq.l	#2,sp                           ; drop the arguments
	addq.w	#1,d7                           ; i++
encode_advance_loop:
	move.w	d7,d0                           ; i < last_match_length?
	cmp.w	-$4(a6),d0
	bge.s	encode_bar                      ; no
	jsr	lzh_getc                        ; getc
	move.w	d0,d6
	cmpi.w	#$ffff,d0                       ; the end?
	bne.s	encode_advance_read             ; no
encode_bar:
	move.w	d7,d0
	ext.l	d0                              ; to a long
	add.l	d0,textsize                     ; textsize += i
	move.l	textsize,d0
	cmp.l	bar_next,d0                     ; past the next bar line?
	ble.s	encode_flush                    ; no
	move.l	bar_step,d0                     ; yes: the next one
	add.l	d0,bar_next
	movem.l	d1/a5,-(sp)                     ; keep the registers
	move.w	-$e(a6),d1                      ; the lines drawn
	cmp.w	bar_height,d1                   ; all of the bar?
	bge.s	encode_bar_done                 ; yes
	addq.w	#1,d1                           ; one more
	move.w	d1,-$e(a6)
	movea.l	-$8(a6),a5
	move.w	#$ffff,(a5)                     ; a line of the bar
	move.w	#$ffff,2(a5)
	cmpi.w	#$2,resolution                  ; high resolution?
	beq.s	encode_bar_up                   ; yes: 2 words
	move.w	#$ffff,4(a5)                    ; no: 4 words
	move.w	#$ffff,6(a5)
encode_bar_up:
	suba.l	-$c(a6),a5                      ; a line up
	move.l	a5,-$8(a6)
encode_bar_done:
	movem.l	(sp)+,d1/a5                     ; the registers back
encode_flush:
	bra.s	encode_flush_next
encode_flush_loop:
	move.w	-$2(a6),-(sp)                   ; s
	jsr	delete_node                     ; DeleteNode
	addq.l	#2,sp                           ; drop the arguments
	move.w	-$2(a6),d0                      ; s = (s + 1) & (N - 1)
	addq.w	#1,d0
	and.w	#$fff,d0
	move.w	d0,-$2(a6)
	move.w	d4,d0                           ; r = (r + 1) & (N - 1)
	addq.w	#1,d0
	and.w	#$fff,d0
	move.w	d0,d4
	subq.w	#1,d5                           ; len--
	beq.s	encode_flush_next               ; none left
	move.w	d4,-(sp)                        ; r
	jsr	insert_node                     ; InsertNode
	addq.l	#2,sp                           ; drop the arguments
encode_flush_next:
	move.w	d7,d0                           ; i++ < last_match_length?
	addq.w	#1,d7
	cmp.w	-$4(a6),d0
	blt.s	encode_flush_loop               ; yes
	tst.w	d5                              ; more?
	bgt.w	encode_loop                     ; yes
	jsr	encode_end                      ; EncodeEnd
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The V3.0 program stub ("JAM Packer Decrunch V3.0"), put in front of a program packed with LZH: it clears
; the top of the screen and prints its title (unless Heading is off), depacks the program $400 bytes above
; its end flashing the background (unless Flash is off), relocates it to run where the stub's text is, sets
; the basepage, and runs a mover from the screen that copies it down, clears its BSS and $600 bytes more,
; clears the registers and starts it.  The packed data follows the stub at v30_stub+$476.  JAMPACK.PRG
; itself was packed with this stub.
;------------------------------------------------------------------------------
v30_stub:	; from: write_program, pack_file, multi_pack_file
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; kept
	movea.l	d0,a2                           ; a2 = the screen
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp                           ; drop the arguments
	move.w	#$9f,d1                         ; 160 longs in high resolution
	cmp.b	#$2,d0                          ; high?
	beq.s	v30_stub_clear                  ; yes
	move.w	#$167,d1                        ; 360 longs otherwise
v30_stub_clear:	; from: set_stub_options
	clr.l	(a2)+                           ; clear the top of the screen (a nop without Heading)
	dbra	d1,v30_stub_clear
	lea	v30_title(pc),a1                ; the title
	move.b	#$3c,5(a1)                      ; column 28
	cmp.b	#$0,d0                          ; low resolution?
	bne.s	v30_stub_title                  ; no
	move.b	#$28,5(a1)                      ; yes: column 8
v30_stub_title:
	pea	v30_title(pc)                   ; the title
	move.w	#$9,-(sp)
v30_stub_print:	; from: set_stub_options
	trap	#1                              ; Cconws, Cconws (a nop without Heading)
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; kept
	move.w	$fff8240,-(sp)                  ; palette 0, keep the background colour
	lea	v30_stub+$476(pc),a5            ; the packed data
	movea.l	a5,a6
	adda.l	#$400,a6                        ; a6 = $400 above it
	move.l	4(a5),-(sp)                     ; the unpacked length
	bsr.w	v30_depack                      ; depack
	movea.l	(sp)+,a6
	move.w	(sp)+,$fff8240                  ; palette 0, the colour back
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	v30_stub+$476(pc),a3            ; the depacked program
	adda.l	#$400,a3                        ; $400 above the packed data
	movea.l	a3,a1
	movea.l	2(a3),a0                        ; text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	adda.l	#$1c,a0                         ; + the header
	adda.l	a3,a0                           ; a0 = its relocation table
	lea	v30_stub(pc),a5                 ; where it will run: the stub's text
	move.l	a5,d0
	adda.l	#$1c,a1                         ; its text
	tst.l	(a0)                            ; any relocation?
	beq.s	v30_stub_relocated              ; no
	adda.l	(a0)+,a1                        ; the first address
v30_stub_relocate:
	add.l	d0,(a1)                         ; relocate a long
v30_stub_relocate_next:
	clr.l	d1
	move.b	(a0)+,d1                        ; the next step
	tst.w	d1
	beq.s	v30_stub_relocated              ; the end?
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	v30_stub_relocate_step          ; no
	adda.l	#$fe,a1                         ; yes
	bra.s	v30_stub_relocate_next
v30_stub_relocate_step:
	adda.l	d1,a1                           ; on to the next long
	bra.s	v30_stub_relocate               ; relocate it
v30_stub_relocated:
	suba.l	#$100,a5                        ; a5 = the basepage
	move.l	2(a3),$c(a5)                    ; text length
	move.l	6(a3),$14(a5)                   ; data length
	move.l	$a(a3),$1c(a5)                  ; BSS length
	move.l	8(a5),d0                        ; the text segment
	move.l	$c(a5),d1
	add.l	d0,d1
	move.l	d1,$10(a5)                      ; = the data segment
	move.l	$14(a5),d0
	add.l	d0,d1
	move.l	d1,$18(a5)                      ; = the BSS
	move.l	(sp)+,d0                        ; the screen
	add.l	#$7f00,d0                       ; + $7f00
	movea.l	d0,a2                           ; where the mover goes
	movea.l	d0,a5                           ; and runs
	move.w	#$40,d2                         ; 65 bytes
	lea	v30_stub_mover(pc),a1           ; the mover
v30_stub_copy_mover:
	move.b	(a1)+,(a2)+                     ; copied
	dbra	d2,v30_stub_copy_mover
	movea.l	a3,a1                           ; the depacked text
	adda.l	#$1c,a1
	lea	v30_stub(pc),a0                 ; where it runs
	movea.l	a0,a2
	jmp	(a5)                            ; run the mover
v30_stub_mover:
	move.l	(a1)+,(a2)+                     ; copy the program down
	cmpa.l	d1,a2                           ; to the BSS?
	ble.s	v30_stub_mover
	movea.l	4(sp),a1                        ; the basepage
	movea.l	$18(a1),a3                      ; its BSS
	move.l	$1c(a1),d1                      ; its length
	add.l	#$600,d1                        ; + $600
v30_stub_clear_bss:
	clr.b	(a3)+                           ; cleared
	subq.l	#1,d1
	bne.s	v30_stub_clear_bss
	clr.l	d1                              ; the registers cleared
	clr.l	d2
	clr.l	d3
	clr.l	d4
	clr.l	d5
	clr.l	d6
	clr.l	d7
	movea.l	d1,a1
	movea.l	d2,a2
	movea.l	d3,a3
	movea.l	d4,a4
	movea.l	d5,a5
	movea.l	d6,a6
	jmp	(a0)                            ; start the program

;------------------------------------------------------------------------------
; The stub's LZH decoder: LHarc's Huffman decoding in assembly.  reconst rebuilds the tree when the
; root's frequency reaches $8000.
;------------------------------------------------------------------------------
v30_reconst:	; from: v30_start_huff
	movem.w	d0-d1/d3/d5,-(sp)               ; a0 = prnt, a1 = son, a3 = freq, d7 = T * 2
	movea.l	a1,a2                           ; a2 walks son
	moveq	#0,d2                           ; d2 = the next node to fill
	moveq	#-2,d4                          ; d4 = the leaf being looked at
	moveq	#0,d1                           ; d1 = the next pair of nodes to join
	move.w	#$139,d5                        ; 314 leaves
v30_reconst_leaves:
	addq.w	#2,d4                           ; the next entry
	cmp.w	(a2)+,d7                        ; a leaf (son >= T)?
	bhi.s	v30_reconst_leaves              ; no: on
	move.w	0(a3,d4.w),d3                   ; its frequency
	addq.w	#1,d3                           ; halved, rounding up
	lsr.w	#1,d3
	cmp.w	-$2(a3,d2.w),d3                 ; no more than the last node's?
	bls.s	v30_reconst_leaf                ; yes: the leaf next
	move.w	0(a3,d1.w),d0                   ; the next pair's sum
	add.w	2(a3,d1.w),d0
	cmp.w	d0,d3                           ; the leaf no more?
	bls.s	v30_reconst_leaf                ; yes: the leaf next
v30_reconst_node:
	move.w	d0,0(a3,d2.w)                   ; a node: freq = the sum
	move.w	d1,0(a1,d2.w)                   ; son = the pair
	move.w	d2,0(a0,d1.w)                   ; prnt of both = it
	move.w	d2,2(a0,d1.w)
	addq.w	#2,d2                           ; the next node
	addq.l	#4,d1                           ; the next pair
	move.w	0(a3,d1.w),d0                   ; its sum
	add.w	2(a3,d1.w),d0
	cmp.w	d0,d3                           ; the leaf still bigger?
	bhi.s	v30_reconst_node                ; yes: another node
v30_reconst_leaf:
	move.w	d3,0(a3,d2.w)                   ; the leaf: its frequency
	move.w	0(a1,d4.w),d0                   ; son = the leaf's own
	move.w	d0,0(a1,d2.w)
	move.w	d2,0(a0,d0.w)                   ; prnt of the leaf = it
	addq.w	#2,d2                           ; the next node
	dbra	d5,v30_reconst_leaves           ; the next leaf
v30_reconst_rest:
	move.w	0(a3,d1.w),d0                   ; the rest are nodes: the pair's sum
	add.w	2(a3,d1.w),d0
	move.w	d0,0(a3,d2.w)                   ; freq
	move.w	d1,0(a1,d2.w)                   ; son = the pair
	move.w	d2,0(a0,d1.w)                   ; prnt of both = it
	move.w	d2,2(a0,d1.w)
	addq.w	#2,d2                           ; the next node
	addq.l	#4,d1                           ; the next pair
	cmp.w	d7,d2                           ; up to T?
	bne.s	v30_reconst_rest                ; no
	movem.w	(sp)+,d0-d1/d3/d5               ; the registers back
	rts

;------------------------------------------------------------------------------
; Make the d_code and d_len tables for the upper 6 bits of a position.
;------------------------------------------------------------------------------
v30_make_tables:	; from: v30_depack
	movea.l	v30_d_code(pc),a0               ; d_code
	lea	v30_d_code_counts(pc),a1        ; its counts
	moveq	#0,d0                           ; d0 = the code, 4 times
	moveq	#31,d1                          ; the first 32 bytes
	moveq	#0,d2                           ; 3 nibbles before the next word
v30_make_code:
	move.b	d0,(a0)+                        ; the code
	dbra	d1,v30_make_code                ; as many times as the count
	dbra	d2,v30_make_code_next           ; a nibble left?
	move.w	(a1)+,d3                        ; no: the next 4 nibbles
	moveq	#3,d2
v30_make_code_next:
	rol.w	#4,d3                           ; the next nibble
	move.w	d3,d1                           ; the count less one
	andi.w	#$f,d1
	addq.b	#4,d0                           ; the next code
	bcc.s	v30_make_code                   ; all 64 done?
	movea.l	v30_d_len(pc),a0                ; d_len
	lea	v30_d_len_counts(pc),a1         ; its counts
	moveq	#5,d0                           ; 6 counts, read from the last
	moveq	#3,d1                           ; from 3 bits
v30_make_len:
	move.b	0(a1,d0.w),d2                   ; the count less one
	ext.w	d2                              ; to a word
v30_make_len_loop:
	move.b	d1,(a0)+                        ; the length
	dbra	d2,v30_make_len_loop            ; as many times
	addq.w	#1,d1                           ; one bit more
	dbra	d0,v30_make_len                 ; the next count
	rts

;------------------------------------------------------------------------------
; Set up the Huffman tree with every character seen once.
;------------------------------------------------------------------------------
v30_start_huff:	; from: v30_depack
	movea.l	v30_freq(pc),a0                 ; freq
	movea.l	v30_son(pc),a1                  ; son
	movea.l	v30_prnt_leaves(pc),a2          ; prnt + T
	moveq	#1,d1                           ; every leaf seen once
	move.w	#$4e6,d2                        ; son = (i + T) * 2
	moveq	#0,d4                           ; prnt[i + T] = i * 2
	move.w	#$139,d0                        ; 314 leaves
v30_start_leaves:
	move.w	d1,(a0)+                        ; freq
	move.w	d2,(a1)+                        ; son
	move.w	d4,(a2)+                        ; prnt
	addq.w	#2,d2                           ; the next leaf
	addq.w	#2,d4
	dbra	d0,v30_start_leaves
	movea.l	v30_freq(pc),a0                 ; the leaves
	movea.l	v30_freq_nodes(pc),a3           ; the nodes
	movea.l	v30_son_nodes(pc),a1            ; their sons
	movea.l	v30_prnt(pc),a2                 ; the prnt of the leaves and nodes
	move.w	#$274,d2                        ; the first node (N_CHAR * 2)
	moveq	#0,d4                           ; the first pair
	move.w	#$138,d0                        ; 313 nodes
v30_start_nodes:
	move.w	(a0)+,d1                        ; the pair's frequencies
	add.w	(a0)+,d1                        ; added
	move.w	d1,(a3)+                        ; freq
	move.w	d4,(a1)+                        ; son = the pair
	move.w	d2,(a2)+                        ; prnt of both = the node
	move.w	d2,(a2)+
	addq.w	#4,d4                           ; the next pair
	addq.w	#2,d2                           ; the next node
	dbra	d0,v30_start_nodes
	move.w	#$ffff,(a3)                     ; freq[T] = $ffff, a guard
	clr.w	(a2)                            ; prnt[R] = 0, the root
	rts
v30_reconst_and_update:	; from: v30_depack
	bsr.w	v30_reconst                     ; the tree rebuilt
	bra.w	v30_update                      ; then updated
v30_depack_done:	; from: v30_depack
	addq.l	#4,sp                           ; the output's start
	rts

;------------------------------------------------------------------------------
; Depack 'LZH!' data (a5 = it) to a6, from the end of the packed data down; the tables live in a work area
; $1500 bytes below the stack.
;------------------------------------------------------------------------------
v30_depack:	; from: v30_stub
	lea	v30_freq(pc),a0                 ; the table pointers
	move.l	sp,d1                           ; the work area: $1500 below the stack
	sub.l	#$1500,d1
	move.w	#$7,d0                          ; 8 pointers
v30_tables_relocate:
	add.l	d1,(a0)+                        ; made absolute
	dbra	d0,v30_tables_relocate
	movea.l	d1,a0                           ; the work area
	move.w	#$53f,d0                        ; $1500 bytes
v30_clear_work:
	clr.l	(a0)+                           ; cleared
	dbra	d0,v30_clear_work
	bsr.w	v30_make_tables                 ; d_code and d_len
	bsr.w	v30_start_huff                  ; the tree
	movea.l	v30_prnt(pc),a0
	movea.l	v30_son(pc),a1
	movea.l	v30_freq(pc),a3
	move.l	a6,-(sp)                        ; the output's start, kept
	adda.l	4(a5),a6                        ; + the unpacked length: its end
	adda.l	8(a5),a5                        ; + the packed length
	adda.l	#$c,a5                          ; + 12: the packed data's end
	movea.l	a6,a4
	move.w	#$3c,d0                         ; 60 spaces past the end
v30_fill_spaces:
	move.b	#$20,(a4)+
	dbra	d0,v30_fill_spaces
	moveq	#8,d6                           ; 8 bits to go
	move.b	-(a5),d5                        ; the first byte
	move.w	#$4e6,d7                        ; T, as a word index
	movea.l	v30_d_len(pc),a4                ; d_len
	move.w	#$ff,d3                         ; the colour
v30_next:
	ror.w	#1,d3                           ; the next colour
v30_stub_flash:	; from: set_stub_options
	move.w	d3,$ffff8240                    ; palette 0, flash the background (a nop without Flash)
	cmpa.l	(sp),a6                         ; all depacked?
	ble.s	v30_depack_done                 ; yes: done
	move.w	$4e4(a1),d0                     ; from the root (R * 2)
v30_decode_bit:
	dbra	d6,v30_decode_bit_got           ; a bit left?
	moveq	#7,d6                           ; no: 8 more
	move.b	-(a5),d5                        ; the next byte, from the end down
v30_decode_bit_got:
	add.b	d5,d5                           ; the top bit out
	bcc.s	v30_decode_walk                 ; 0: the left son
	addq.w	#2,d0                           ; 1: the right son
v30_decode_walk:
	move.w	0(a1,d0.w),d0                   ; down the tree
	cmp.w	d7,d0                           ; still a node (< T)?
	blt.s	v30_decode_bit                  ; yes: another bit
	move.w	d0,d1                           ; d1 = the leaf
	sub.w	d7,d0                           ; d0 = the character * 2
	move.w	$4e4(a3),d4                     ; the root's frequency $8000?
	bmi.w	v30_reconst_and_update          ; yes: rebuild the tree first
v30_update:	; from: v30_start_huff
	move.w	0(a0,d1.w),d1                   ; from the leaf's parent up
v30_update_loop:
	lea	0(a3,d1.w),a2                   ; freq[c]
	addq.w	#1,(a2)                         ; one more
	cmpm.w	(a2)+,(a2)+                     ; more than freq[c + 1]?
	bcs.s	v30_update_swap                 ; yes: move it up
	move.w	0(a0,d1.w),d1                   ; its parent
	bne.s	v30_update_loop                 ; up to the root
	lsr.w	#1,d0                           ; the character
	cmp.w	#$100,d0                        ; a length (256 or more)?
	bge.s	v30_position                    ; yes: a position follows
v30_literal:
	move.b	d0,-(a6)                        ; no: a byte, stored downwards
	bra.s	v30_next                        ; the next code
v30_update_swap:
	subq.w	#1,-$4(a2)                      ; freq[c] back
	move.w	-$4(a2),d4                      ; k = it
v30_update_find:
	cmp.w	(a2)+,d4                        ; l: the last node with the same frequency
	beq.s	v30_update_find
	subq.l	#4,a2
	addq.w	#1,(a2)                         ; that one is increased instead
	suba.l	a3,a2                           ; l as an offset
	move.w	0(a1,d1.w),d4                   ; i = son[c]
	move.w	a2,0(a0,d4.w)                   ; prnt[i] = l
	cmp.w	d7,d4                           ; a leaf?
	bcc.s	v30_update_link                 ; yes
	move.w	a2,2(a0,d4.w)                   ; no: prnt[i + 1] = l too
v30_update_link:
	move.w	0(a1,a2.w),d2                   ; j = son[l]
	move.w	d4,0(a1,a2.w)                   ; son[l] = i
	move.w	d1,0(a0,d2.w)                   ; prnt[j] = c
	cmp.w	d7,d2                           ; a leaf?
	bcc.s	v30_update_next                 ; yes
	move.w	d1,2(a0,d2.w)                   ; no: prnt[j + 1] = c too
v30_update_next:
	move.w	d2,0(a1,d1.w)                   ; son[c] = j
	move.w	0(a0,a2.w),d1                   ; c = prnt[l]
	bne.s	v30_update_loop                 ; up to the root
	lsr.w	#1,d0                           ; the character
	cmp.w	#$100,d0                        ; a byte?
	blt.s	v30_literal                     ; yes
v30_position:
	move.b	-$1(a5),d1                      ; the position: the next byte's bits
	moveq	#0,d2
	lsr.b	d6,d1                           ; below the bits left in d5
	or.b	d5,d1                           ; d1 = the next 8 bits
	move.b	0(a4,d1.w),d2                   ; d2 = their upper code's length
	sub.w	d2,d6                           ; used
	bpl.s	v30_position_more               ; all in d5?
	move.b	-(a5),d5                        ; no: the next byte
	move.b	d5,d4
	addq.w	#2,d6                           ; its bits left, less 6
	bmi.s	v30_position_bits               ; fewer than 6: a third byte
	beq.s	v30_position_low                ; exactly 6: the low 6 bits
	lsr.b	#1,d4                           ; 7: the low 6 bits are its top bits
	lsl.b	#7,d5                           ; one bit left
	bra.s	v30_position_low
v30_position_6:
	move.b	-(a5),d5                        ; the low 6 bits are all in the next byte
	move.b	d5,d4
	lsl.b	#6,d5                           ; two bits left
	moveq	#2,d6
	lsr.b	d6,d4                           ; its top 6 bits
	bra.s	v30_copy
v30_position_more:
	beq.s	v30_position_6                  ; d5 used up?
	move.b	(a5),d5                         ; no: the byte d5 came from
	subq.w	#6,d6                           ; the bits needed from the next
v30_position_bits:
	neg.w	d6
	lsl.b	d6,d5                           ; its bits left, moved up
	move.b	d5,d4
	move.b	-(a5),d5                        ; the next byte
	move.b	d5,d2
	lsl.b	d6,d5                           ; its bits left
	subq.w	#8,d6
	neg.w	d6
	lsr.b	d6,d2                           ; the bits needed
	or.b	d2,d4                           ; added
v30_position_low:
	andi.w	#$3f,d4                         ; the low 6 bits
v30_copy:
	movea.l	v30_d_code(pc),a0               ; d_code
	move.b	0(a0,d1.w),d2                   ; the upper bits, * 4
	lsl.w	#4,d2                           ; * 64
	or.b	d4,d2                           ; + the low 6 bits
	lea	1(a6,d2.w),a0                   ; from where the text was the position earlier
	subi.w	#$fe,d0                         ; the length: the character - 253, less one
	move.w	d0,d1
v30_copy_loop:
	move.b	-(a0),d0                        ; a byte from the text
	move.b	d0,-(a6)                        ; copied, downwards
	dbra	d1,v30_copy_loop
	movea.l	v30_prnt(pc),a0                 ; prnt back
	bra.w	v30_next                        ; the next code
v30_d_len_counts:	; from: v30_make_tables
	dc.w	$0f2f,$2f3f,$2f1f               ; how many upper position values have 3, 4, 5, 6, 7 and 8 bit codes
v30_d_code_counts:	; from: v30_make_tables
	dc.w	$fff7                           ; the counts behind d_code, a nibble each
	dc.b	'wwws333331'
	dc.w	$1111,$1111,$1111,$1111,$1111,$1110,$0000,$0000
	dc.w	$0000,$0000
v30_freq:	; from: v30_start_huff
	dc.w	$0000,$0000                     ; the work area's tables, as offsets until v30_depack adds the work
                                                ;   area: freq
v30_freq_nodes:	; from: v30_start_huff
	dc.w	$0000,$0274                     ; freq + N_CHAR
v30_prnt:	; from: v30_start_huff
	dc.w	$0000,$04e8                     ; prnt
v30_prnt_leaves:	; from: v30_start_huff
	dc.w	$0000,$09ce                     ; prnt + T
v30_son:	; from: v30_start_huff
	dc.w	$0000,$0c42                     ; son
v30_son_nodes:	; from: v30_start_huff
	dc.w	$0000,$0eb6                     ; son + N_CHAR
v30_d_code:	; from: v30_make_tables
	dc.w	$0000,$112a                     ; d_code: 256 bytes
v30_d_len:	; from: v30_make_tables
	dc.w	$0000,$122a                     ; d_len: 256 bytes
v30_title:	; from: v30_stub
	dc.b	27,'j',27,'Y  JAM Packer Decrunch V3.0',27,'k',0 ; save the cursor, cursor to row 0 and the column, the
                                                ;   title, restore the cursor
	dc.b	$00

;------------------------------------------------------------------------------
; depack_lzh(packed, destination): depack 'LZH!' data with the program's own decoder, in supervisor mode.
; d0 = the unpacked length.
;------------------------------------------------------------------------------
depack_lzh:	; from: unpack_file, write_program, pack_file, multi_pack_file, disk_unpack, v30_stub
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the packed data
	move.l	$c(a6),d6                       ; the destination
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	lea	lzh_freq(pc),a0                 ; the table offsets, as the stub has them
	move.l	#$0,(a0)                        ; freq
	move.l	#$274,4(a0)                     ; freq + N_CHAR
	move.l	#$4e8,8(a0)                     ; prnt
	move.l	#$9ce,$c(a0)                    ; prnt + T
	move.l	#$c42,$10(a0)                   ; son
	move.l	#$eb6,$14(a0)                   ; son + N_CHAR
	move.l	#$112a,$18(a0)                  ; d_code
	move.l	#$122a,$1c(a0)                  ; d_len
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	depack_lzh_colour(pc),a0
	move.w	$ffff8240,(a0)                  ; palette 0, keep the background colour
	movea.l	d7,a5                           ; a5 = the packed data
	move.l	4(a5),-(sp)                     ; its unpacked length
	movea.l	d6,a6                           ; a6 = the destination
	lea	depack_lzh_ssp(pc),a2
	move.l	d0,(a2)                         ; keep the old stack
	bsr.w	lzh_decode                      ; decode
	move.l	(sp)+,d7                        ; the unpacked length
	move.w	depack_lzh_colour(pc),$ffff8240 ; palette 0, the colour back
	move.l	depack_lzh_ssp(pc),-(sp)        ; Super(old stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d7,d0                           ; returned
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	unlk	a6                              ; the frame back
	rts
depack_lzh_ssp:
	dc.l	$00000000                       ; the stack Super returned
depack_lzh_colour:
	dc.w	$0000                           ; the background colour

;------------------------------------------------------------------------------
; As v30_reconst, in the copy the program uses itself.
;------------------------------------------------------------------------------
lzh_reconst:	; from: lzh_start_huff
	movem.w	d0-d1/d3/d5,-(sp)               ; a0 = prnt, a1 = son, a3 = freq, d7 = T * 2
	movea.l	a1,a2                           ; a2 walks son
	moveq	#0,d2                           ; d2 = the next node to fill
	moveq	#-2,d4                          ; d4 = the leaf being looked at
	moveq	#0,d1                           ; d1 = the next pair of nodes to join
	move.w	#$139,d5                        ; 314 leaves
lzh_reconst_leaves:
	addq.w	#2,d4                           ; the next entry
	cmp.w	(a2)+,d7                        ; a leaf (son >= T)?
	bhi.s	lzh_reconst_leaves              ; no: on
	move.w	0(a3,d4.w),d3                   ; its frequency
	addq.w	#1,d3                           ; halved, rounding up
	lsr.w	#1,d3
	cmp.w	-$2(a3,d2.w),d3                 ; no more than the last node's?
	bls.s	lzh_reconst_leaf                ; yes: the leaf next
	move.w	0(a3,d1.w),d0                   ; the next pair's sum
	add.w	2(a3,d1.w),d0
	cmp.w	d0,d3                           ; the leaf no more?
	bls.s	lzh_reconst_leaf                ; yes: the leaf next
lzh_reconst_node:
	move.w	d0,0(a3,d2.w)                   ; a node: freq = the sum
	move.w	d1,0(a1,d2.w)                   ; son = the pair
	move.w	d2,0(a0,d1.w)                   ; prnt of both = it
	move.w	d2,2(a0,d1.w)
	addq.w	#2,d2                           ; the next node
	addq.l	#4,d1                           ; the next pair
	move.w	0(a3,d1.w),d0                   ; its sum
	add.w	2(a3,d1.w),d0
	cmp.w	d0,d3                           ; the leaf still bigger?
	bhi.s	lzh_reconst_node                ; yes: another node
lzh_reconst_leaf:
	move.w	d3,0(a3,d2.w)                   ; the leaf: its frequency
	move.w	0(a1,d4.w),d0                   ; son = the leaf's own
	move.w	d0,0(a1,d2.w)
	move.w	d2,0(a0,d0.w)                   ; prnt of the leaf = it
	addq.w	#2,d2                           ; the next node
	dbra	d5,lzh_reconst_leaves           ; the next leaf
lzh_reconst_rest:
	move.w	0(a3,d1.w),d0                   ; the rest are nodes: the pair's sum
	add.w	2(a3,d1.w),d0
	move.w	d0,0(a3,d2.w)                   ; freq
	move.w	d1,0(a1,d2.w)                   ; son = the pair
	move.w	d2,0(a0,d1.w)                   ; prnt of both = it
	move.w	d2,2(a0,d1.w)
	addq.w	#2,d2                           ; the next node
	addq.l	#4,d1                           ; the next pair
	cmp.w	d7,d2                           ; up to T?
	bne.s	lzh_reconst_rest                ; no
	movem.w	(sp)+,d0-d1/d3/d5               ; the registers back
	rts

;------------------------------------------------------------------------------
; As v30_make_tables, in the copy the program uses itself.
;------------------------------------------------------------------------------
lzh_make_tables:	; from: lzh_decode
	movea.l	lzh_d_code(pc),a0               ; d_code
	lea	lzh_d_code_counts(pc),a1        ; its counts
	moveq	#0,d0                           ; d0 = the code, 4 times
	moveq	#31,d1                          ; the first 32 bytes
	moveq	#0,d2                           ; 3 nibbles before the next word
lzh_make_code:
	move.b	d0,(a0)+                        ; the code
	dbra	d1,lzh_make_code                ; as many times as the count
	dbra	d2,lzh_make_code_next           ; a nibble left?
	move.w	(a1)+,d3                        ; no: the next 4 nibbles
	moveq	#3,d2
lzh_make_code_next:
	rol.w	#4,d3                           ; the next nibble
	move.w	d3,d1                           ; the count less one
	andi.w	#$f,d1
	addq.b	#4,d0                           ; the next code
	bcc.s	lzh_make_code                   ; all 64 done?
	movea.l	lzh_d_len(pc),a0                ; d_len
	lea	lzh_d_len_counts(pc),a1         ; its counts
	moveq	#5,d0                           ; 6 counts, read from the last
	moveq	#3,d1                           ; from 3 bits
lzh_make_len:
	move.b	0(a1,d0.w),d2                   ; the count less one
	ext.w	d2                              ; to a word
lzh_make_len_loop:
	move.b	d1,(a0)+                        ; the length
	dbra	d2,lzh_make_len_loop            ; as many times
	addq.w	#1,d1                           ; one bit more
	dbra	d0,lzh_make_len                 ; the next count
	rts

;------------------------------------------------------------------------------
; As v30_start_huff, in the copy the program uses itself.
;------------------------------------------------------------------------------
lzh_start_huff:	; from: lzh_decode
	movea.l	lzh_freq(pc),a0                 ; freq
	movea.l	lzh_son(pc),a1                  ; son
	movea.l	lzh_prnt_leaves(pc),a2          ; prnt + T
	moveq	#1,d1                           ; every leaf seen once
	move.w	#$4e6,d2                        ; son = (i + T) * 2
	moveq	#0,d4                           ; prnt[i + T] = i * 2
	move.w	#$139,d0                        ; 314 leaves
lzh_start_leaves:
	move.w	d1,(a0)+                        ; freq
	move.w	d2,(a1)+                        ; son
	move.w	d4,(a2)+                        ; prnt
	addq.w	#2,d2                           ; the next leaf
	addq.w	#2,d4
	dbra	d0,lzh_start_leaves
	movea.l	lzh_freq(pc),a0                 ; the leaves
	movea.l	lzh_freq_nodes(pc),a3           ; the nodes
	movea.l	lzh_son_nodes(pc),a1            ; their sons
	movea.l	lzh_prnt(pc),a2                 ; the prnt of the leaves and nodes
	move.w	#$274,d2                        ; the first node (N_CHAR * 2)
	moveq	#0,d4                           ; the first pair
	move.w	#$138,d0                        ; 313 nodes
lzh_start_nodes:
	move.w	(a0)+,d1                        ; the pair's frequencies
	add.w	(a0)+,d1                        ; added
	move.w	d1,(a3)+                        ; freq
	move.w	d4,(a1)+                        ; son = the pair
	move.w	d2,(a2)+                        ; prnt of both = the node
	move.w	d2,(a2)+
	addq.w	#4,d4                           ; the next pair
	addq.w	#2,d2                           ; the next node
	dbra	d0,lzh_start_nodes
	move.w	#$ffff,(a3)                     ; freq[T] = $ffff, a guard
	clr.w	(a2)                            ; prnt[R] = 0, the root
	rts
lzh_reconst_and_update:	; from: lzh_decode
	bsr.w	lzh_reconst                     ; the tree rebuilt
	bra.w	lzh_update                      ; then updated
lzh_decode_done:	; from: lzh_decode
	addq.l	#4,sp                           ; the output's start
	rts

;------------------------------------------------------------------------------
; As v30_depack, in the copy the program uses itself.
;------------------------------------------------------------------------------
lzh_decode:	; from: depack_lzh
	lea	lzh_freq(pc),a0                 ; the table pointers
	move.l	sp,d1                           ; the work area: $1500 below the stack
	sub.l	#$1500,d1
	move.w	#$7,d0                          ; 8 pointers
lzh_tables_relocate:
	add.l	d1,(a0)+                        ; made absolute
	dbra	d0,lzh_tables_relocate
	movea.l	d1,a0                           ; the work area
	move.w	#$53f,d0                        ; $1500 bytes
lzh_clear_work:
	clr.l	(a0)+                           ; cleared
	dbra	d0,lzh_clear_work
	bsr.w	lzh_make_tables                 ; d_code and d_len
	bsr.w	lzh_start_huff                  ; the tree
	movea.l	lzh_prnt(pc),a0
	movea.l	lzh_son(pc),a1
	movea.l	lzh_freq(pc),a3
	move.l	a6,-(sp)                        ; the output's start, kept
	adda.l	4(a5),a6                        ; + the unpacked length: its end
	adda.l	8(a5),a5                        ; + the packed length
	adda.l	#$c,a5                          ; + 12: the packed data's end
	movea.l	a6,a4
	move.w	#$3c,d0                         ; 60 spaces past the end
lzh_fill_spaces:
	move.b	#$20,(a4)+
	dbra	d0,lzh_fill_spaces
	moveq	#8,d6                           ; 8 bits to go
	move.b	-(a5),d5                        ; the first byte
	move.w	#$4e6,d7                        ; T, as a word index
	movea.l	lzh_d_len(pc),a4                ; d_len
	move.w	#$ff,d3                         ; the colour
lzh_next:
	ror.w	#1,d3                           ; the next colour
	move.w	d3,$ffff8240                    ; palette 0, flash the background
	cmpa.l	(sp),a6                         ; all depacked?
	ble.s	lzh_decode_done                 ; yes: done
	move.w	$4e4(a1),d0                     ; from the root (R * 2)
lzh_decode_bit:
	dbra	d6,lzh_decode_bit_got           ; a bit left?
	moveq	#7,d6                           ; no: 8 more
	move.b	-(a5),d5                        ; the next byte, from the end down
lzh_decode_bit_got:
	add.b	d5,d5                           ; the top bit out
	bcc.s	lzh_decode_walk                 ; 0: the left son
	addq.w	#2,d0                           ; 1: the right son
lzh_decode_walk:
	move.w	0(a1,d0.w),d0                   ; down the tree
	cmp.w	d7,d0                           ; still a node (< T)?
	blt.s	lzh_decode_bit                  ; yes: another bit
	move.w	d0,d1                           ; d1 = the leaf
	sub.w	d7,d0                           ; d0 = the character * 2
	move.w	$4e4(a3),d4                     ; the root's frequency $8000?
	bmi.w	lzh_reconst_and_update          ; yes: rebuild the tree first
lzh_update:	; from: lzh_start_huff
	move.w	0(a0,d1.w),d1                   ; from the leaf's parent up
lzh_update_loop:
	lea	0(a3,d1.w),a2                   ; freq[c]
	addq.w	#1,(a2)                         ; one more
	cmpm.w	(a2)+,(a2)+                     ; more than freq[c + 1]?
	bcs.s	lzh_update_swap                 ; yes: move it up
	move.w	0(a0,d1.w),d1                   ; its parent
	bne.s	lzh_update_loop                 ; up to the root
	lsr.w	#1,d0                           ; the character
	cmp.w	#$100,d0                        ; a length (256 or more)?
	bge.s	lzh_position                    ; yes: a position follows
lzh_literal:
	move.b	d0,-(a6)                        ; no: a byte, stored downwards
	bra.s	lzh_next                        ; the next code
lzh_update_swap:
	subq.w	#1,-$4(a2)                      ; freq[c] back
	move.w	-$4(a2),d4                      ; k = it
lzh_update_find:
	cmp.w	(a2)+,d4                        ; l: the last node with the same frequency
	beq.s	lzh_update_find
	subq.l	#4,a2
	addq.w	#1,(a2)                         ; that one is increased instead
	suba.l	a3,a2                           ; l as an offset
	move.w	0(a1,d1.w),d4                   ; i = son[c]
	move.w	a2,0(a0,d4.w)                   ; prnt[i] = l
	cmp.w	d7,d4                           ; a leaf?
	bcc.s	lzh_update_link                 ; yes
	move.w	a2,2(a0,d4.w)                   ; no: prnt[i + 1] = l too
lzh_update_link:
	move.w	0(a1,a2.w),d2                   ; j = son[l]
	move.w	d4,0(a1,a2.w)                   ; son[l] = i
	move.w	d1,0(a0,d2.w)                   ; prnt[j] = c
	cmp.w	d7,d2                           ; a leaf?
	bcc.s	lzh_update_next                 ; yes
	move.w	d1,2(a0,d2.w)                   ; no: prnt[j + 1] = c too
lzh_update_next:
	move.w	d2,0(a1,d1.w)                   ; son[c] = j
	move.w	0(a0,a2.w),d1                   ; c = prnt[l]
	bne.s	lzh_update_loop                 ; up to the root
	lsr.w	#1,d0                           ; the character
	cmp.w	#$100,d0                        ; a byte?
	blt.s	lzh_literal                     ; yes
lzh_position:
	move.b	-$1(a5),d1                      ; the position: the next byte's bits
	moveq	#0,d2
	lsr.b	d6,d1                           ; below the bits left in d5
	or.b	d5,d1                           ; d1 = the next 8 bits
	move.b	0(a4,d1.w),d2                   ; d2 = their upper code's length
	sub.w	d2,d6                           ; used
	bpl.s	lzh_position_more               ; all in d5?
	move.b	-(a5),d5                        ; no: the next byte
	move.b	d5,d4
	addq.w	#2,d6                           ; its bits left, less 6
	bmi.s	lzh_position_bits               ; fewer than 6: a third byte
	beq.s	lzh_position_low                ; exactly 6: the low 6 bits
	lsr.b	#1,d4                           ; 7: the low 6 bits are its top bits
	lsl.b	#7,d5                           ; one bit left
	bra.s	lzh_position_low
lzh_position_6:
	move.b	-(a5),d5                        ; the low 6 bits are all in the next byte
	move.b	d5,d4
	lsl.b	#6,d5                           ; two bits left
	moveq	#2,d6
	lsr.b	d6,d4                           ; its top 6 bits
	bra.s	lzh_copy
lzh_position_more:
	beq.s	lzh_position_6                  ; d5 used up?
	move.b	(a5),d5                         ; no: the byte d5 came from
	subq.w	#6,d6                           ; the bits needed from the next
lzh_position_bits:
	neg.w	d6
	lsl.b	d6,d5                           ; its bits left, moved up
	move.b	d5,d4
	move.b	-(a5),d5                        ; the next byte
	move.b	d5,d2
	lsl.b	d6,d5                           ; its bits left
	subq.w	#8,d6
	neg.w	d6
	lsr.b	d6,d2                           ; the bits needed
	or.b	d2,d4                           ; added
lzh_position_low:
	andi.w	#$3f,d4                         ; the low 6 bits
lzh_copy:
	movea.l	lzh_d_code(pc),a0               ; d_code
	move.b	0(a0,d1.w),d2                   ; the upper bits, * 4
	lsl.w	#4,d2                           ; * 64
	or.b	d4,d2                           ; + the low 6 bits
	lea	1(a6,d2.w),a0                   ; from where the text was the position earlier
	subi.w	#$fe,d0                         ; the length: the character - 253, less one
	move.w	d0,d1
lzh_copy_loop:
	move.b	-(a0),d0                        ; a byte from the text
	move.b	d0,-(a6)                        ; copied, downwards
	dbra	d1,lzh_copy_loop
	movea.l	lzh_prnt(pc),a0                 ; prnt back
	bra.w	lzh_next                        ; the next code
lzh_d_len_counts:	; from: lzh_make_tables
	dc.w	$0f2f,$2f3f,$2f1f
lzh_d_code_counts:	; from: lzh_make_tables
	dc.w	$fff7
	dc.b	'wwws333331'
	dc.w	$1111,$1111,$1111,$1111,$1111,$1110,$0000,$0000
	dc.w	$0000,$0000
lzh_freq:	; from: depack_lzh, lzh_start_huff
	dc.w	$0000,$0000                     ; the work area's tables: freq
lzh_freq_nodes:	; from: lzh_start_huff
	dc.w	$0000,$0274
lzh_prnt:	; from: lzh_start_huff
	dc.w	$0000,$04e8
lzh_prnt_leaves:	; from: lzh_start_huff
	dc.w	$0000,$09ce
lzh_son:	; from: lzh_start_huff
	dc.w	$0000,$0c42
lzh_son_nodes:	; from: lzh_start_huff
	dc.w	$0000,$0eb6
lzh_d_code:	; from: lzh_make_tables
	dc.w	$0000,$112a
lzh_d_len:	; from: lzh_make_tables
	dc.w	$0000,$122a,$4cdf,$00c0,$4e5e,$4e75

;------------------------------------------------------------------------------
; The C library.  The AES bindings put their arguments in the AES arrays and call aes with the opcode;
; the trap bindings keep a1/a2 and the return address on a small stack of their own.
;
; appl_exit().
;------------------------------------------------------------------------------
appl_exit:	; from: close_gem
	link	a6,#0                           ; the frame
	move.w	#$13,-(sp)                      ; opcode 19
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	move.w	#$1,d0                          ; returns 1
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; appl_init(): sets up the AES parameter block and returns the application id.
;------------------------------------------------------------------------------
appl_init:	; from: init_gem
	link	a6,#-2                          ; 2 bytes of locals
	lea	aes_control,a0                  ; control
	move.l	a0,aes_block
	lea	aes_global,a0                   ; global
	move.l	a0,aes_block+4
	lea	aes_intin,a0                    ; intin
	move.l	a0,aes_block+8
	lea	aes_intout,a0                   ; intout
	move.l	a0,aes_block+12
	lea	aes_addrin,a0                   ; addrin
	move.l	a0,aes_block+16
	lea	aes_addrout,a0                  ; addrout
	move.l	a0,aes_block+20
	lea	aes_block,a0                    ; the block
	move.l	a0,aes_pb_ptr                   ; is the one aes uses
	move.w	#$a,-(sp)                       ; opcode 10
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	move.w	aes_intout,ap_id                ; the application id
	move.w	ap_id,d0                        ; returned
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; evnt_button(clicks, mask, state, &x, &y, &button, &kstate).
;------------------------------------------------------------------------------
evnt_button:	; from: main
	link	a6,#0                           ; the frame
	move.w	8(a6),aes_intin                 ; clicks
	move.w	$a(a6),aes_intin+2              ; mask
	move.w	$c(a6),aes_intin+4              ; state
	move.w	#$15,-(sp)                      ; opcode 21
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	movea.l	$e(a6),a0                       ; x
	move.w	aes_intout+2,(a0)
	movea.l	$12(a6),a0                      ; y
	move.w	aes_intout+4,(a0)
	movea.l	$16(a6),a0                      ; button
	move.w	aes_intout+6,(a0)
	movea.l	$1a(a6),a0                      ; keyboard state
	move.w	aes_intout+8,(a0)
	move.w	aes_intout,d0                   ; the click count
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; form_alert(default button, string); d0 = the button.
;------------------------------------------------------------------------------
form_alert:	; from: pack_one_file, fatal_alert, open_workstation, pack_file, unjam_file, write_jam, 4 more
	link	a6,#0                           ; the frame
	move.w	8(a6),aes_intin                 ; default button
	move.l	$a(a6),aes_addrin               ; the alert
	move.w	#$34,-(sp)                      ; opcode 52
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; form_center(tree, &x, &y, &w, &h).
;------------------------------------------------------------------------------
form_center:	; from: init_gem, about_box
	link	a6,#0                           ; the frame
	move.l	8(a6),aes_addrin                ; the tree
	move.w	#$36,-(sp)                      ; opcode 54
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	movea.l	$c(a6),a0                       ; x
	move.w	aes_intout+2,(a0)
	movea.l	$10(a6),a0                      ; y
	move.w	aes_intout+4,(a0)
	movea.l	$14(a6),a0                      ; width
	move.w	aes_intout+6,(a0)
	movea.l	$18(a6),a0                      ; height
	move.w	aes_intout+8,(a0)
	move.w	aes_intout,d0                   ; returned
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; form_dial(mode, small box, big box); FMD_GROW also keeps the big box for dial_box.
;------------------------------------------------------------------------------
form_dial:	; from: open_box, close_box
	link	a6,#0                           ; the frame
	move.w	8(a6),aes_intin                 ; mode
	move.w	$a(a6),aes_intin+2              ; the small box
	move.w	$c(a6),aes_intin+4
	move.w	$e(a6),aes_intin+6
	move.w	$10(a6),aes_intin+8
	move.w	$12(a6),aes_intin+10            ; the big box
	move.w	$14(a6),aes_intin+12
	move.w	$16(a6),aes_intin+14
	move.w	$18(a6),aes_intin+16
	cmpi.w	#$3,8(a6)                       ; FMD_GROW?
	bne.s	form_dial_call                  ; no
	move.w	$12(a6),dial_box_x              ; yes: keep the big box
	move.w	$14(a6),dial_box_y
	move.w	$16(a6),dial_box_w
	move.w	$18(a6),dial_box_h
form_dial_call:
	move.w	#$33,-(sp)                      ; opcode 51
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Return the box kept by form_dial.  Nothing calls it.
;------------------------------------------------------------------------------
dial_box:
	link	a6,#0                           ; the frame
	movea.l	8(a6),a0
	move.w	dial_box_x,(a0)
	movea.l	$c(a6),a0
	move.w	dial_box_y,(a0)
	movea.l	$10(a6),a0
	move.w	dial_box_w,(a0)
	movea.l	$14(a6),a0
	move.w	dial_box_h,(a0)
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; form_do(tree, edit object); d0 = the exit object.
;------------------------------------------------------------------------------
form_do:	; from: main, about_box, pack_file
	link	a6,#0                           ; the frame
	move.l	8(a6),aes_addrin                ; the tree
	move.w	$c(a6),aes_intin                ; edit object
	move.w	#$32,-(sp)                      ; opcode 50
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; fsel_input(path, name, &button).
;------------------------------------------------------------------------------
fsel_input:	; from: choose_file
	link	a6,#0                           ; the frame
	move.l	8(a6),aes_addrin                ; the path
	move.l	$c(a6),aes_addrin+4             ; the name
	move.w	#$5a,-(sp)                      ; opcode 90
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	movea.l	$10(a6),a0                      ; OK or Cancel
	move.w	aes_intout+2,(a0)
	move.w	aes_intout,d0                   ; returned
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; graf_growbox(small box, big box).
;------------------------------------------------------------------------------
graf_growbox:	; from: close_box, about_box
	link	a6,#0                           ; the frame
	move.w	8(a6),aes_intin
	move.w	$a(a6),aes_intin+2
	move.w	$c(a6),aes_intin+4
	move.w	$e(a6),aes_intin+6
	move.w	$10(a6),aes_intin+8
	move.w	$12(a6),aes_intin+10
	move.w	$14(a6),aes_intin+12
	move.w	$16(a6),aes_intin+14
	move.w	#$49,-(sp)                      ; opcode 73
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; graf_handle(&wchar, &hchar, &wbox, &hbox); d0 = the AES's VDI handle.
;------------------------------------------------------------------------------
graf_handle:	; from: open_workstation
	link	a6,#0                           ; the frame
	move.w	#$4d,-(sp)                      ; opcode 77
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	movea.l	8(a6),a0                        ; character width
	move.w	aes_intout+2,(a0)
	movea.l	$c(a6),a0                       ; character height
	move.w	aes_intout+4,(a0)
	movea.l	$10(a6),a0                      ; box width
	move.w	aes_intout+6,(a0)
	movea.l	$14(a6),a0                      ; box height
	move.w	aes_intout+8,(a0)
	move.w	aes_intout,d0                   ; the handle
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; graf_mouse(form, address).
;------------------------------------------------------------------------------
graf_mouse:	; from: init_gem, copy_screen, clear_title, show_title, multi_pack, pack_file
	link	a6,#0                           ; the frame
	move.w	8(a6),aes_intin                 ; the form
	move.l	$a(a6),aes_addrin               ; a user form
	move.w	#$4e,-(sp)                      ; opcode 78
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; graf_shrinkbox(small box, big box).
;------------------------------------------------------------------------------
graf_shrinkbox:	; from: open_box, about_box
	link	a6,#0                           ; the frame
	move.w	8(a6),aes_intin
	move.w	$a(a6),aes_intin+2
	move.w	$c(a6),aes_intin+4
	move.w	$e(a6),aes_intin+6
	move.w	$10(a6),aes_intin+8
	move.w	$12(a6),aes_intin+10
	move.w	$14(a6),aes_intin+12
	move.w	$16(a6),aes_intin+14
	move.w	#$4a,-(sp)                      ; opcode 74
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; objc_change(tree, object, reserved, clip box, new state, redraw).
;------------------------------------------------------------------------------
objc_change:	; from: deselect, check_object, pack_file
	link	a6,#0                           ; the frame
	move.l	8(a6),aes_addrin                ; the tree
	move.w	$c(a6),aes_intin                ; the object
	move.w	$e(a6),aes_intin+2
	move.w	$10(a6),aes_intin+4             ; the clip box
	move.w	$12(a6),aes_intin+6
	move.w	$14(a6),aes_intin+8
	move.w	$16(a6),aes_intin+10
	move.w	$18(a6),aes_intin+12            ; the new state
	move.w	$1a(a6),aes_intin+14            ; redraw
	move.w	#$2f,-(sp)                      ; opcode 47
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; objc_draw(tree, start object, depth, clip box).
;------------------------------------------------------------------------------
objc_draw:	; from: main, open_box, about_box, pack_file, show_pack_sizes, show_crunching, 3 more
	link	a6,#0                           ; the frame
	move.l	8(a6),aes_addrin                ; the tree
	move.w	$c(a6),aes_intin                ; the first object
	move.w	$e(a6),aes_intin+2              ; depth
	move.w	$10(a6),aes_intin+4             ; the clip box
	move.w	$12(a6),aes_intin+6
	move.w	$14(a6),aes_intin+8
	move.w	$16(a6),aes_intin+10
	move.w	#$2a,-(sp)                      ; opcode 42
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; rsrc_gaddr(type, index, &address).
;------------------------------------------------------------------------------
rsrc_gaddr:	; from: init_gem
	link	a6,#0                           ; the frame
	move.w	8(a6),aes_intin                 ; the type
	move.w	$a(a6),aes_intin+2              ; the index
	move.w	#$1,aes_control+8               ; one addrout
	move.w	#$70,-(sp)                      ; opcode 112
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	clr.w	aes_control+8                   ; back to none
	movea.l	$c(a6),a0                       ; the address
	move.l	aes_addrout,(a0)
	move.w	aes_intout,d0                   ; returned
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; bios(function, ...), xbios(...), gemdos(...): the arguments are on the stack already.  a1, a2 and the
; return address are kept on trap_save_stack while the trap runs.
;------------------------------------------------------------------------------
bios:	; from: disk_unpack, disk_pack, read_boot_sector, console_getc
	lea	trap_save_stack,a0              ; the next save slot
	adda.w	trap_save_index,a0
	addq.w	#4,trap_save_index
	move.l	a1,(a0)                         ; keep a1
	move.l	a2,$10(a0)                      ; a2
	move.l	(sp)+,$20(a0)                   ; and the return address
	trap	#13                             ; BIOS, the trap
	subq.w	#4,trap_save_index              ; back a slot
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	movea.l	(a0),a1                         ; a1 back
	movea.l	$10(a0),a2                      ; a2
	move.l	$20(a0),-(sp)                   ; the return address
	tst.w	d0
	rts

xbios:	; from: init_gem, open_workstation, disk_unpack, format_disk
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	addq.w	#4,trap_save_index
	move.l	a1,(a0)
	move.l	a2,$10(a0)
	move.l	(sp)+,$20(a0)
	trap	#14                             ; XBIOS
	subq.w	#4,trap_save_index
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	movea.l	(a0),a1
	movea.l	$10(a0),a2
	move.l	$20(a0),-(sp)
	tst.w	d0
	rts

gemdos:	; from: pack_one_file, init_gem, multi_pack, unpack_file, write_program, pack_file, 23 more
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	addq.w	#4,trap_save_index
	move.l	a1,(a0)
	move.l	a2,$10(a0)
	move.l	(sp)+,$20(a0)
	trap	#1                              ; GEMDOS
	subq.w	#4,trap_save_index
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	movea.l	(a0),a1
	movea.l	$10(a0),a2
	move.l	$20(a0),-(sp)
	tst.w	d0
	rts

;------------------------------------------------------------------------------
; Make a resource held in memory usable, as rsrc_load would: the tree, object, TEDINFO, ICONBLK and BITBLK
; addresses are made absolute, the objects' coordinates converted with rsrc_obfix, and the AES given the
; tree table.  The argument is the resource's header.
;------------------------------------------------------------------------------
rsrc_relocate:	; from: init_gem
	link	a6,#-58                         ; 58 bytes of locals
	movem.l	d7,-(sp)                        ; keep the registers
	move.w	#$24,-(sp)                      ; 36 bytes
	pea	-$24(a6)                        ; of the header
	move.l	8(a6),-(sp)                     ; from the resource
	jsr	bcopy                           ; copied to the frame
	lea	$a(sp),sp                       ; drop the arguments
	move.l	8(a6),d0                        ; the resource
	move.w	-$12(a6),d3                     ; + the tree table's offset
	ext.l	d3                              ; to a long
	add.l	d3,d0
	move.l	d0,-$2a(a6)                     ; = the tree table
	move.l	-$2a(a6),d0
	asr.l	#8,d0
	asr.l	#8,d0                           ; high word
	and.l	#$ffff,d0
	move.w	d0,aes_global+10                ; into the AES global array
	move.l	-$2a(a6),d0
	and.l	#$ffff,d0                       ; low word
	move.w	d0,aes_global+12
	clr.l	d7                              ; each tree
	bra.s	relocate_trees_loop
relocate_tree:
	move.l	d7,d0
	asl.l	#2,d0                           ; longs
	add.l	-$2a(a6),d0                     ; its entry
	movea.l	d0,a0
	move.l	(a0),d0
	add.l	8(a6),d0                        ; + the resource
	move.l	d0,(a0)                         ; absolute
	addq.l	#1,d7                           ; next
relocate_trees_loop:
	move.l	d7,d0
	move.w	-$e(a6),d1                      ; the tree count
	ext.l	d1                              ; to a long
	cmp.l	d1,d0
	blt.s	relocate_tree
	move.l	8(a6),d0                        ; the resource
	move.w	-$22(a6),d3                     ; + the object table's offset
	ext.l	d3                              ; to a long
	add.l	d3,d0
	move.l	d0,-$2e(a6)                     ; = the objects
	clr.l	d7                              ; each object
	bra.w	relocate_objects_loop
relocate_object:
	move.l	d7,d0
	move.l	d0,-(sp)                        ; the number
	move.l	#$18,d0                         ; 24 bytes an object
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul                            ; times
	move.l	(sp)+,d0                        ; the product
	movea.l	-$2e(a6),a0
	move.w	6(a0,d0.l),d0                   ; its type
	bra.w	object_type_check
relocate_ob_spec:
	move.l	d7,d0
	move.l	d0,-(sp)                        ; the number
	move.l	#$18,d0                         ; 24 bytes an object
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul                            ; times
	move.l	(sp)+,d0                        ; the product
	add.l	-$2e(a6),d0                     ; + the objects
	movea.l	d0,a0
	move.l	$c(a0),d0                       ; its ob_spec
	add.l	8(a6),d0                        ; + the resource
	move.l	d0,$c(a0)                       ; absolute
	bra.s	object_obfix
	bra.s	object_obfix
object_type_check:
	cmp.w	#$15,d0                         ; TEXT
	beq.s	relocate_ob_spec
	cmp.w	#$16,d0                         ; BOXTEXT
	beq.s	relocate_ob_spec
	cmp.w	#$17,d0                         ; IMAGE
	beq.s	relocate_ob_spec
	cmp.w	#$1a,d0                         ; BUTTON
	beq.s	relocate_ob_spec
	cmp.w	#$1c,d0                         ; STRING
	beq.s	relocate_ob_spec
	cmp.w	#$1d,d0                         ; FTEXT
	beq.s	relocate_ob_spec
	cmp.w	#$1e,d0                         ; FBOXTEXT
	beq.s	relocate_ob_spec
	cmp.w	#$1f,d0                         ; ICON
	beq.s	relocate_ob_spec
	cmp.w	#$20,d0                         ; TITLE: these point somewhere
	beq.s	relocate_ob_spec
object_obfix:
	move.l	d7,d0
	move.w	d0,-(sp)                        ; the object
	move.l	-$2e(a6),-(sp)                  ; the objects
	jsr	rsrc_obfix
	addq.l	#6,sp                           ; drop the arguments
	addq.l	#1,d7                           ; next
relocate_objects_loop:
	move.l	d7,d0
	move.w	-$10(a6),d1                     ; the object count
	ext.l	d1                              ; to a long
	cmp.l	d1,d0
	blt.w	relocate_object
	move.l	8(a6),d0                        ; the resource
	move.w	-$20(a6),d3                     ; + the TEDINFO table's offset
	ext.l	d3                              ; to a long
	add.l	d3,d0
	move.l	d0,-$32(a6)                     ; = the TEDINFOs
	clr.l	d7                              ; each
	bra.s	relocate_tedinfos_loop
relocate_tedinfo:
	move.l	d7,d0
	move.l	d0,-(sp)                        ; the number
	move.l	#$1c,d0                         ; 28 bytes a TEDINFO
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul                            ; times
	move.l	(sp)+,d0                        ; the product
	add.l	-$32(a6),d0
	movea.l	d0,a0
	move.l	(a0),d0                         ; te_ptext
	add.l	8(a6),d0                        ; + the resource
	move.l	d0,(a0)
	move.l	d7,d0
	move.l	d0,-(sp)                        ; the number
	move.l	#$1c,d0
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d0                        ; the product
	add.l	-$32(a6),d0
	movea.l	d0,a0
	move.l	4(a0),d0                        ; te_ptmplt
	add.l	8(a6),d0                        ; + the resource
	move.l	d0,4(a0)
	move.l	d7,d0
	move.l	d0,-(sp)                        ; the number
	move.l	#$1c,d0
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d0                        ; the product
	add.l	-$32(a6),d0
	movea.l	d0,a0
	move.l	8(a0),d0                        ; te_pvalid
	add.l	8(a6),d0                        ; + the resource
	move.l	d0,8(a0)
	addq.l	#1,d7                           ; next
relocate_tedinfos_loop:
	move.l	d7,d0
	move.w	-$c(a6),d1                      ; the TEDINFO count
	ext.l	d1                              ; to a long
	cmp.l	d1,d0
	blt.s	relocate_tedinfo
	move.l	8(a6),d0                        ; the resource
	move.w	-$1e(a6),d3                     ; + the ICONBLK table's offset
	ext.l	d3                              ; to a long
	add.l	d3,d0
	move.l	d0,-$36(a6)                     ; = the ICONBLKs
	clr.l	d7                              ; each
	bra.w	relocate_iconblks_loop
relocate_iconblk:
	move.l	d7,d0                           ; 34 bytes an ICONBLK: the mask, data and text pointers
	move.l	d0,-(sp)                        ; the number
	move.l	#$22,d0
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d0                        ; the product
	movea.l	-$36(a6),a0
	move.l	0(a0,d0.l),d0
	add.l	8(a6),d0
	move.l	d7,d1
	move.l	d1,-(sp)                        ; the number
	move.l	#$22,d1
	move.l	d1,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d1                        ; the product
	movea.l	-$36(a6),a0
	move.l	d0,0(a0,d1.l)
	move.l	d7,d0
	move.l	d0,-(sp)                        ; the number
	move.l	#$22,d0
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d0                        ; the product
	movea.l	-$36(a6),a0
	move.l	4(a0,d0.l),d0
	add.l	8(a6),d0
	move.l	d7,d1
	move.l	d1,-(sp)                        ; the number
	move.l	#$22,d1
	move.l	d1,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d1                        ; the product
	movea.l	-$36(a6),a0
	move.l	d0,4(a0,d1.l)
	move.l	d7,d0
	move.l	d0,-(sp)                        ; the number
	move.l	#$22,d0
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d0                        ; the product
	add.l	-$36(a6),d0
	movea.l	d0,a0
	move.l	8(a0),d0
	add.l	8(a6),d0
	move.l	d0,8(a0)
	addq.l	#1,d7                           ; next
relocate_iconblks_loop:
	move.l	d7,d0
	move.w	-$a(a6),d1                      ; the ICONBLK count
	ext.l	d1                              ; to a long
	cmp.l	d1,d0
	blt.w	relocate_iconblk
	move.l	8(a6),d0                        ; the resource
	move.w	-$1c(a6),d3                     ; + the BITBLK table's offset
	ext.l	d3                              ; to a long
	add.l	d3,d0
	move.l	d0,-$3a(a6)                     ; = the BITBLKs
	clr.l	d7                              ; each
	bra.s	relocate_bitblks_loop
relocate_bitblk:
	move.l	d7,d0                           ; 14 bytes a BITBLK: its data pointer
	move.l	d0,-(sp)                        ; the number
	move.l	#$e,d0
	move.l	d0,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d0                        ; the product
	movea.l	-$3a(a6),a0
	move.l	0(a0,d0.l),d0
	add.l	8(a6),d0
	move.l	d7,d1
	move.l	d1,-(sp)                        ; the number
	move.l	#$e,d1
	move.l	d1,-(sp)                        ; the multiplier
	jsr	lmul
	move.l	(sp)+,d1                        ; the product
	movea.l	-$3a(a6),a0
	move.l	d0,0(a0,d1.l)
	addq.l	#1,d7                           ; next
relocate_bitblks_loop:
	move.l	d7,d0
	move.w	-$8(a6),d1                      ; the BITBLK count
	ext.l	d1                              ; to a long
	cmp.l	d1,d0
	blt.s	relocate_bitblk
	move.w	#$1,d0                          ; returns 1
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Signed long division: the two longs on the stack, divisor first, are replaced by the quotient and the
; remainder.
;------------------------------------------------------------------------------
ldiv:	; from: ltoa, show_pack_sizes, disk_unpack, encode
	link	a6,#-2                          ; 2 bytes of locals
	movem.l	d0-d3,-(sp)                     ; keep the registers
	move.l	8(a6),d2                        ; the divisor
	bne.s	ldiv_signs                      ; not 0
	divu.w	#$0,d0                          ; by 0: a divide-by-zero exception
	clr.l	d0
	clr.l	d1
	bra.s	ldiv_done
ldiv_signs:
	move.l	$c(a6),d1                       ; the dividend
	clr.w	-$2(a6)                         ; the signs
	tst.l	d1                              ; negative?
	bge.s	ldiv_divisor_sign               ; no
	addq.w	#3,-$2(a6)                      ; yes: remainder and quotient negative
	neg.l	d1
ldiv_divisor_sign:
	tst.l	d2                              ; divisor negative?
	bge.s	ldiv_shift                      ; no
	addq.w	#1,-$2(a6)                      ; yes: the quotient's sign flips
	neg.l	d2
ldiv_shift:
	moveq	#1,d3                           ; the quotient bit
ldiv_shift_loop:
	cmp.l	d1,d2                           ; line the divisor up
	bcc.s	ldiv_divide
	asl.l	#1,d2
	asl.l	#1,d3
	bra.s	ldiv_shift_loop
ldiv_divide:
	clr.l	d0                              ; the quotient
ldiv_divide_loop:
	cmp.l	d1,d2                           ; fits?
	bhi.s	ldiv_next_bit                   ; no
	or.l	d3,d0                           ; yes: the bit
	sub.l	d2,d1                           ; subtracted
ldiv_next_bit:
	lsr.l	#1,d2
	lsr.l	#1,d3
	bcc.s	ldiv_divide_loop                ; for each bit
	cmpi.w	#$3,-$2(a6)                     ; remainder negative?
	blt.s	ldiv_quotient_sign              ; no
	neg.l	d1
ldiv_quotient_sign:
	lsr.w	-$2(a6)                         ; quotient negative?
	bcc.s	ldiv_done                       ; no
	neg.l	d0
ldiv_done:
	move.l	d0,8(a6)                        ; the quotient
	move.l	d1,$c(a6)                       ; the remainder
	movem.l	(sp)+,d0-d3                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Signed long multiply: the product of the two longs on the stack replaces them, popped to one long.
;------------------------------------------------------------------------------
lmul:	; from: deselect, check_object, ltoa, show_pack_sizes, rsrc_relocate
	link	a6,#0                           ; the frame
	movem.l	d0-d3/d7,-(sp)                  ; keep the registers
	clr.w	d7                              ; the sign
	move.l	8(a6),d1                        ; the first: positive?
	bge.s	lmul_second
	moveq	#1,d7
	neg.l	d1
lmul_second:
	move.l	$c(a6),d2                       ; the second
	bge.s	lmul_multiply                   ; positive?
	eori.w	#$1,d7
	neg.l	d2
lmul_multiply:
	move.l	d1,d3                           ; high word of the first
	andi.l	#$ffff0000,d3
	beq.s	lmul_cross                      ; times the low of the second
	swap	d3
	mulu.w	d2,d3
lmul_cross:
	move.l	d2,d0                           ; high word of the second
	swap	d0
	tst.w	d0
	beq.s	lmul_low
	mulu.w	d1,d0                           ; times the low of the first
	add.w	d0,d3
lmul_low:
	swap	d3                              ; the cross products are the high word
	clr.w	d3
	mulu.w	d1,d2                           ; low times low
	add.l	d2,d3
	tst.w	d7                              ; negative?
	beq.s	lmul_done
	neg.l	d3
lmul_done:
	move.l	d3,$c(a6)                       ; the product
	movem.l	(sp)+,d0-d3/d7                  ; the registers back
	unlk	a6                              ; the frame back
	move.l	(sp)+,(sp)                      ; one long off the stack
	tst.l	4(sp)                           ; flags from the product
	rts

;------------------------------------------------------------------------------
; bcopy(source, destination, count): copies by longs, words or bytes, backwards when they overlap upwards.
;------------------------------------------------------------------------------
bcopy:	; from: rsrc_relocate
	link	a6,#0                           ; the frame
	movea.l	8(a6),a0                        ; the source
	movea.l	$c(a6),a1                       ; the destination
	move.w	$10(a6),d1                      ; the count
	ext.l	d1                              ; to a long
	cmpa.l	a0,a1                           ; destination above?
	bhi.s	bcopy_backwards                 ; yes: backwards
	move.w	d1,d0
	and.w	#$3,d0                          ; a multiple of 4?
	bne.s	bcopy_not_long                  ; no
	or.l	8(a6),d0
	or.l	$c(a6),d0
	and.w	#$1,d0                          ; both even?
	bne.s	bcopy_bytes                     ; no: bytes
	bra.s	bcopy_longs                     ; yes: longs
bcopy_not_long:
	or.l	8(a6),d0
	or.l	$c(a6),d0
	and.w	#$1,d0                          ; both even?
	beq.s	bcopy_words                     ; yes: words
bcopy_bytes:
	bra.s	bcopy_bytes_next
bcopy_bytes_loop:
	move.b	(a0)+,(a1)+                     ; a byte
bcopy_bytes_next:
	dbra	d1,bcopy_bytes_loop
	bra.s	bcopy_done
bcopy_words:
	asr.w	#1,d1                           ; words
	bra.s	bcopy_words_next
bcopy_words_loop:
	move.w	(a0)+,(a1)+                     ; a word
bcopy_words_next:
	dbra	d1,bcopy_words_loop
	bra.s	bcopy_done
bcopy_longs:
	asr.w	#2,d1                           ; longs
	bra.s	bcopy_longs_next
bcopy_longs_loop:
	move.l	(a0)+,(a1)+                     ; a long
bcopy_longs_next:
	dbra	d1,bcopy_longs_loop
	bra.s	bcopy_done
bcopy_backwards:
	adda.l	d1,a0                           ; from the ends
	adda.l	d1,a1
	move.w	d1,d0                           ; the same, backwards
	and.w	#$3,d0
	bne.s	bcopy_back_not_long
	or.l	8(a6),d0
	or.l	$c(a6),d0
	and.w	#$1,d0
	bne.s	bcopy_back_bytes
	bra.s	bcopy_back_longs
bcopy_back_not_long:
	or.l	8(a6),d0
	or.l	$c(a6),d0
	and.w	#$1,d0
	beq.s	bcopy_back_words
bcopy_back_bytes:
	bra.s	bcopy_back_bytes_next
bcopy_back_bytes_loop:
	move.b	-(a0),-(a1)
bcopy_back_bytes_next:
	dbra	d1,bcopy_back_bytes_loop
	bra.s	bcopy_done
bcopy_back_words:
	asr.w	#1,d1
	bra.s	bcopy_back_words_next
bcopy_back_words_loop:
	move.w	-(a0),-(a1)
bcopy_back_words_next:
	dbra	d1,bcopy_back_words_loop
	bra.s	bcopy_done
bcopy_back_longs:
	asr.w	#2,d1
	bra.s	bcopy_back_longs_next
bcopy_back_longs_loop:
	move.l	-(a0),-(a1)
bcopy_back_longs_next:
	dbra	d1,bcopy_back_longs_loop
bcopy_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; atexit(function): up to 8.  Nothing calls it.
;------------------------------------------------------------------------------
atexit:
	link	a6,#0                           ; the frame
	move.l	atexit_next,d0                  ; the next free entry
	lea	atexit_table,a0                 ; the table
	sub.l	a0,d0
	asr.l	#2,d0                           ; entries used
	cmp.w	#$8,d0                          ; full?
	bge.s	atexit_full                     ; yes
	movea.l	atexit_next,a0
	addq.l	#4,atexit_next
	move.l	8(a6),(a0)                      ; the function
	move.w	#$1,d0
	bra.s	atexit_done
atexit_full:
	move.w	#$0,d0
atexit_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; exit(code): call the atexit functions, close the open streams, Pterm.
;------------------------------------------------------------------------------
exit:	; from: start, main, fatal_alert, open_workstation, console_getc
	link	a6,#-2                          ; 2 bytes of locals
	movem.l	a5,-(sp)                        ; keep the registers
	bra.s	exit_atexit_loop
exit_call:
	subq.l	#4,atexit_next                  ; back an entry
	movea.l	atexit_next,a0
	movea.l	(a0),a0                         ; the function
	jsr	(a0)                            ; call it
exit_atexit_loop:
	move.l	atexit_next,d0
	lea	atexit_table,a0
	sub.l	a0,d0
	asr.l	#2,d0                           ; entries left
	bne.s	exit_call                       ; any: call it
	lea	iob,a0                          ; the streams
	movea.l	a0,a5
	bra.s	exit_close_loop
exit_close:
	move.w	$a(a5),d0                       ; in use?
	and.w	#$403,d0
	beq.s	exit_close_next                 ; no
	move.l	a5,-(sp)                        ; argument 1
	jsr	fclose                          ; close it
	addq.l	#4,sp                           ; drop the arguments
exit_close_next:
	adda.w	#$10,a5                         ; the next stream
exit_close_loop:
	move.l	a5,d0
	lea	iob,a0
	move.l	a0,d1
	add.l	#$140,d1                        ; 20 streams of 16 bytes
	cmp.l	d1,d0
	blt.s	exit_close
	move.w	8(a6),-(sp)                     ; the code
	jsr	pterm                           ; Pterm
	addq.l	#2,sp                           ; drop the arguments
	movem.l	(sp)+,a5                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; fclose(stream): flush it, free its buffer, close its file.  d0 = -1 on error.
;------------------------------------------------------------------------------
fclose:	; from: exit
	link	a6,#0                           ; the frame
	movem.l	a5,-(sp)                        ; keep the registers
	movea.l	8(a6),a5                        ; the stream
	move.w	$a(a5),d0                       ; writing?
	and.w	#$2,d0
	beq.s	fclose_buffer                   ; no
	move.l	a5,-(sp)                        ; argument 1
	jsr	fflush                          ; flush it
	addq.l	#4,sp                           ; drop the arguments
	beq.s	fclose_buffer                   ; all right
	move.w	#$ffff,d0
	bra.s	fclose_done
fclose_buffer:
	move.w	$a(a5),d0                       ; its own buffer?
	and.w	#$10,d0
	beq.s	fclose_file                     ; no
	move.l	6(a5),-(sp)                     ; argument 1
	jsr	free                            ; free it
	addq.l	#4,sp                           ; drop the arguments
fclose_file:
	clr.w	$a(a5)                          ; not in use
	move.w	$c(a5),-(sp)                    ; the handle
	jsr	close                           ; close it
	addq.l	#2,sp                           ; drop the arguments
	beq.s	fclose_ok                       ; all right
	move.w	#$ffff,d0
	bra.s	fclose_done
fclose_ok:
	move.w	#$0,d0
fclose_done:
	movem.l	(sp)+,a5                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; fflush(stream): write out what is buffered.  d0 = -1 on error.
;------------------------------------------------------------------------------
fflush:	; from: fclose, filbuf
	link	a6,#0                           ; the frame
	movem.l	d7/a5,-(sp)                     ; keep the registers
	movea.l	8(a6),a5                        ; the stream
	move.w	$a(a5),d0                       ; open?
	and.w	#$403,d0
	bne.s	fflush_open                     ; yes
	move.w	#$ffff,d0
	bra.s	fflush_done
fflush_open:
	move.l	(a5),d7                         ; the bytes in the buffer
	sub.l	6(a5),d7
	move.w	$a(a5),d0                       ; written to?
	and.w	#$80,d0
	beq.s	fflush_reset                    ; no
	move.w	$a(a5),d0                       ; writing?
	and.w	#$2,d0
	bne.s	fflush_write                    ; yes
	move.w	#$ffff,d0
	bra.s	fflush_done
fflush_write:
	move.w	$a(a5),d0                       ; appending?
	and.w	#$4,d0
	beq.s	fflush_write_buffer             ; no
	move.w	#$2,-(sp)                       ; yes: to the end first
	clr.l	-(sp)                           ; argument 2
	move.w	$c(a5),-(sp)                    ; argument 1
	jsr	lseek
	addq.l	#8,sp                           ; drop the arguments
fflush_write_buffer:
	move.w	d7,-(sp)                        ; the length
	move.l	6(a5),-(sp)                     ; the buffer
	move.w	$c(a5),-(sp)                    ; the handle
	jsr	write
	addq.l	#8,sp                           ; drop the arguments
	cmpi.w	#$ffff,d0                       ; failed?
	bne.s	fflush_written                  ; no
	ori.w	#$40,$a(a5)                     ; yes: the error flag
	move.w	#$ffff,d0
	bra.s	fflush_done
fflush_written:
	andi.w	#$ff7f,$a(a5)                   ; no longer written to
fflush_reset:
	move.l	6(a5),(a5)                      ; the buffer is empty
	clr.w	4(a5)
	move.w	#$0,d0
fflush_done:
	movem.l	(sp)+,d7/a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Refill the stream's buffer: d0 = -1 at the end or on error.
;------------------------------------------------------------------------------
filbuf:	; from: getc
	link	a6,#0                           ; the frame
	movem.l	a5,-(sp)                        ; keep the registers
	movea.l	8(a6),a5                        ; the stream
	move.w	$a(a5),d0                       ; read/write?
	and.w	#$400,d0
	beq.s	filbuf_mode                     ; no
	move.w	$a(a5),d0                       ; writing?
	and.w	#$2,d0
	bne.s	filbuf_mode                     ; yes
	ori.w	#$1,$a(a5)                      ; no: reading
filbuf_mode:
	move.w	$a(a5),d0                       ; reading?
	and.w	#$1,d0
	bne.s	filbuf_errors                   ; yes
	ori.w	#$40,$a(a5)                     ; no: an error
filbuf_errors:
	move.w	$a(a5),d0                       ; end or error?
	and.w	#$60,d0
	beq.s	filbuf_buffer                   ; no
	move.l	6(a5),(a5)
	clr.w	4(a5)                           ; empty
	move.w	#$ffff,d0
	bra.s	filbuf_done
filbuf_buffer:
	move.l	6(a5),d0                        ; a buffer?
	bne.s	filbuf_read                     ; yes
	move.l	a5,-(sp)                        ; argument 1
	jsr	getbuf                          ; get one
	addq.l	#4,sp                           ; drop the arguments
filbuf_read:
	move.l	6(a5),(a5)
	move.w	$a(a5),d0                       ; linked to stdout?
	and.w	#$200,d0
	beq.s	filbuf_size                     ; no
	pea	iob+16                          ; yes: flush it first
	jsr	fflush
	addq.l	#4,sp                           ; drop the arguments
filbuf_size:
	move.w	$a(a5),d0                       ; unbuffered?
	and.w	#$108,d0
	beq.s	filbuf_full_size                ; no
	move.w	#$1,d0                          ; yes: 1 byte
	bra.s	filbuf_do_read
filbuf_full_size:
	move.w	$e(a5),d0                       ; the buffer's size
filbuf_do_read:
	move.w	d0,-(sp)                        ; argument 3
	move.l	(a5),-(sp)                      ; the buffer
	move.w	$c(a5),-(sp)                    ; the handle
	jsr	read
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,4(a5)                        ; the bytes in it
	move.w	#$0,d0
filbuf_done:
	movem.l	(sp)+,a5                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; getc(stream): the next byte, or -1 at the end.
;------------------------------------------------------------------------------
getc:	; from: multi_pack
	link	a6,#0                           ; the frame
	movem.l	a5,-(sp)                        ; keep the registers
	movea.l	8(a6),a5                        ; the stream
	move.l	a5,-(sp)                        ; argument 1
	jsr	filbuf                          ; refill if needed
	addq.l	#4,sp                           ; drop the arguments
	beq.s	getc_take                       ; all right
	move.w	#$ffff,d0
	bra.s	getc_done
getc_take:
	subq.w	#1,4(a5)                        ; one fewer
	move.w	4(a5),d0
	tst.w	d0                              ; any left?
	bge.s	getc_byte                       ; yes
	cmpi.w	#$ffff,4(a5)                    ; the end?
	bne.s	getc_error                      ; no
	ori.w	#$20,$a(a5)                     ; yes: the end flag
	bra.s	getc_empty
getc_error:
	ori.w	#$40,$a(a5)                     ; the error flag
getc_empty:
	clr.w	4(a5)
	move.w	#$ffff,d0
	bra.s	getc_done
getc_byte:
	movea.l	(a5),a0
	addq.l	#1,(a5)                         ; on
	move.b	(a0),d0                         ; the byte
	ext.w	d0                              ; to a word
	and.w	#$ff,d0                         ; unsigned
getc_done:
	movem.l	(sp)+,a5                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; lseek(handle, offset, mode): Fseek, extending the file with zeros when seeking past its end.
;------------------------------------------------------------------------------
lseek:	; from: fflush
	link	a6,#-14                         ; 14 bytes of locals
	tst.w	8(a6)                           ; a handle?
	bge.s	lseek_try                       ; yes
	move.w	#$ffdb,errno                    ; no: an error
	move.l	#$ffffffff,d0
	bra.w	lseek_return
lseek_try:
	move.w	$e(a6),-(sp)                    ; mode
	move.w	8(a6),-(sp)                     ; handle
	move.l	$a(a6),-(sp)                    ; offset
	move.w	#$42,-(sp)                      ; Fseek
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	tst.l	d0                              ; all right?
	blt.s	lseek_extend                    ; no
	move.l	-$4(a6),d0                      ; yes
	bra.w	lseek_return
lseek_extend:
	move.w	#$1,-(sp)                       ; the current position
	move.w	8(a6),-(sp)                     ; argument 2
	clr.l	-(sp)                           ; argument 1
	move.w	#$42,-(sp)                      ; Fseek(0, handle, 1)
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)
	tst.l	d0
	bge.s	lseek_end
	move.l	-$8(a6),d0
	move.w	d0,errno
	move.l	#$ffffffff,d0
	bra.w	lseek_return
lseek_end:
	move.w	#$2,-(sp)                       ; the end
	move.w	8(a6),-(sp)                     ; argument 2
	clr.l	-(sp)                           ; argument 1
	move.w	#$42,-(sp)                      ; Fseek(0, handle, 2)
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	move.l	d0,-$c(a6)
	cmpi.w	#$1,$e(a6)                      ; from the current position?
	bne.s	lseek_mode_end                  ; no
	move.l	-$8(a6),d0                      ; yes: + the position
	add.l	$a(a6),d0
	move.l	d0,$a(a6)
	bra.s	lseek_check_end
lseek_mode_end:
	cmpi.w	#$2,$e(a6)                      ; from the end?
	bne.s	lseek_mode_bad                  ; no
	move.l	-$c(a6),d0                      ; yes: + the end
	add.l	$a(a6),d0
	move.l	d0,$a(a6)
	bra.s	lseek_check_end
lseek_mode_bad:
	move.w	$e(a6),d0                       ; from the start?
	beq.s	lseek_check_end                 ; yes
	move.l	#$ffffffff,d0                   ; no: an error
	bra.w	lseek_return
lseek_check_end:
	move.l	$a(a6),d0                       ; past the end?
	cmp.l	-$c(a6),d0
	ble.s	lseek_seek                      ; no
	move.w	8(a6),-(sp)                     ; argument 1
	jsr	fd_mode                         ; the handle's mode
	addq.l	#2,sp                           ; drop the arguments
	and.w	#$dfff,d0
	tst.w	d0                              ; writable?
	bne.s	lseek_fill                      ; yes
	move.l	-$4(a6),d0                      ; no: an error
	move.w	d0,errno
	move.l	#$ffffffff,d0
	bra.s	lseek_return
	bra.s	lseek_seek
lseek_fill:
	pea	-$e(a6)
	move.l	$a(a6),d0                       ; the gap
	sub.l	-$c(a6),d0
	move.l	d0,-(sp)                        ; argument 2
	move.w	8(a6),-(sp)                     ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
lseek_seek:
	clr.w	-(sp)                           ; from the start
	move.w	8(a6),-(sp)                     ; the handle
	move.l	$a(a6),-(sp)                    ; the offset
	move.w	#$42,-(sp)                      ; Fseek
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	tst.l	d0                              ; failed?
	slt	d0
	and.w	#$1,d0
	move.w	d0,-$e(a6)
	beq.s	lseek_done                      ; no
	move.w	-$e(a6),errno                   ; yes: the error
	move.l	#$ffffffff,d0
	bra.s	lseek_return
	bra.s	lseek_return
lseek_done:
	move.l	$a(a6),d0                       ; the position
	nop
lseek_return:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; morecore(units): take memory from GEMDOS for malloc, at least $418 8 byte units, and free it into the
; free list.  d0 = the free list, or 0.
;------------------------------------------------------------------------------
morecore:	; from: malloc
	link	a6,#0                           ; the frame
	movem.l	d7/a4-a5,-(sp)                  ; keep the registers
	move.l	#$418,d7                        ; at least $418 units
	move.l	8(a6),d1
	add.l	#$418,d1
	subq.l	#1,d1
	move.l	d1,-(sp)                        ; rounded up
	move.l	#$418,d1
	move.l	d1,-(sp)                        ; argument 1
	jsr	uldiv                           ; to a multiple of $418
	move.l	(sp)+,d1
	addq.l	#4,sp
	move.l	d7,-(sp)
	move.l	d1,d7
	move.l	d7,-(sp)                        ; argument 1
	jsr	ulmul                           ; times $418
	move.l	(sp)+,d7
	move.l	d7,d0
	asl.l	#3,d0                           ; bytes
	move.l	d0,-(sp)                        ; argument 1
	jsr	sbrk                            ; Malloc
	addq.l	#4,sp                           ; drop the arguments
	movea.l	d0,a5
	cmpa.l	#$ffffffff,a5                   ; got it?
	bne.s	morecore_got                    ; yes
	move.l	#$0,d0                          ; no: 0
	bra.s	morecore_done
morecore_got:
	movea.l	a5,a4                           ; the block
	move.l	d7,4(a4)                        ; its size
	move.l	a4,d0
	addq.l	#8,d0                           ; past its header
	move.l	d0,-(sp)                        ; argument 1
	jsr	free                            ; free it into the list
	addq.l	#4,sp                           ; drop the arguments
	move.l	malloc_free_list,d0             ; the free list
morecore_done:
	movem.l	(sp)+,d7/a4-a5                  ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; malloc(size): K&R malloc over 8 byte units, first fit from the last place, taking more memory when the free
; list has nothing big enough.  d0 = the block, or 0.
;------------------------------------------------------------------------------
malloc:	; from: malloc_word
	link	a6,#0                           ; the frame
	movem.l	d7/a4-a5,-(sp)                  ; keep the registers
	move.l	#$1,d7
	move.l	8(a6),d1
	addq.l	#8,d1                           ; + 7
	subq.l	#1,d1
	move.l	d1,-(sp)
	move.l	#$8,d1
	move.l	d1,-(sp)                        ; argument 1
	jsr	uldiv                           ; in 8 byte units
	move.l	(sp)+,d1
	addq.l	#4,sp
	add.l	d1,d7                           ; + the header
	move.l	malloc_free_list,d0             ; the free list
	movea.l	d0,a4
	tst.l	d0                              ; started?
	bne.s	malloc_search                   ; yes
	lea	malloc_base,a0                  ; no: the empty base
	move.l	a0,d0
	movea.l	d0,a4
	move.l	d0,malloc_free_list
	move.l	d0,malloc_base                  ; points to itself
	clr.l	malloc_base+4                   ; with size 0
malloc_search:
	movea.l	(a4),a5
malloc_loop:
	move.l	4(a5),d0                        ; big enough?
	cmp.l	d7,d0
	bcs.s	malloc_next                     ; no
	move.l	4(a5),d0
	cmp.l	d7,d0                           ; exactly?
	bne.s	malloc_split                    ; no
	move.l	(a5),(a4)                       ; yes: out of the list
	bra.s	malloc_found
malloc_split:
	move.l	d7,d0
	sub.l	d0,4(a5)                        ; the tail is taken
	move.l	4(a5),d0
	asl.l	#3,d0
	adda.l	d0,a5
	move.l	d7,4(a5)                        ; its size
malloc_found:
	move.l	a4,malloc_free_list             ; the search goes on from here
	move.l	a5,d0
	addq.l	#8,d0                           ; past the header
	bra.s	malloc_done
malloc_next:
	move.l	a5,d0                           ; back to the start?
	cmp.l	malloc_free_list,d0
	bne.s	malloc_step                     ; no
	move.l	d7,-(sp)                        ; yes: more memory
	jsr	morecore
	addq.l	#4,sp                           ; drop the arguments
	movea.l	d0,a5
	tst.l	d0                              ; got it?
	bne.s	malloc_step                     ; yes
	move.l	#$0,d0                          ; no: 0
	bra.s	malloc_done
malloc_step:
	movea.l	a5,a4
	movea.l	(a5),a5                         ; the next free block
	bra.s	malloc_loop
malloc_done:
	movem.l	(sp)+,d7/a4-a5                  ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; malloc(unsigned short size).
;------------------------------------------------------------------------------
malloc_word:	; from: getbuf
	link	a6,#0                           ; the frame
	move.w	8(a6),d0                        ; the size
	and.l	#$ffff,d0                       ; unsigned
	move.l	d0,-(sp)                        ; argument 1
	jsr	malloc
	addq.l	#4,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; free(block): back into the free list in address order, joined with its neighbours.
;------------------------------------------------------------------------------
free:	; from: fclose, morecore
	link	a6,#0                           ; the frame
	movem.l	a4-a5,-(sp)                     ; keep the registers
	move.l	8(a6),d0                        ; a block?
	bne.s	free_block                      ; yes
	bra.s	free_return                     ; no: nothing
free_block:
	move.l	8(a6),d0
	subq.l	#8,d0                           ; its header
	movea.l	d0,a5
	movea.l	malloc_free_list,a4             ; the list
	bra.s	free_where
free_find:
	move.l	a4,d0                           ; the list wraps here?
	cmp.l	(a4),d0
	blt.s	free_next                       ; no
	move.l	a5,d0
	cmp.l	a4,d0
	bgt.s	free_found
	move.l	a5,d0
	cmp.l	(a4),d0
	bge.s	free_next
free_found:
	bra.s	free_join_next
free_next:
	movea.l	(a4),a4
free_where:
	move.l	a5,d0                           ; between this and the next?
	cmp.l	a4,d0
	ble.s	free_find
	move.l	a5,d0
	cmp.l	(a4),d0
	bge.s	free_find
free_join_next:
	move.l	a5,d0                           ; its end
	move.l	4(a5),d1
	asl.l	#3,d1
	add.l	d1,d0
	cmp.l	(a4),d0                         ; touches the next?
	bne.s	free_link_next                  ; no
	movea.l	(a4),a0                         ; yes: joined
	move.l	4(a0),d0
	add.l	d0,4(a5)
	movea.l	(a4),a0
	move.l	(a0),(a5)
	bra.s	free_join_previous
free_link_next:
	move.l	(a4),(a5)
free_join_previous:
	move.l	a4,d0                           ; the previous one's end
	move.l	4(a4),d1
	asl.l	#3,d1
	add.l	d1,d0
	cmp.l	a5,d0                           ; touches this?
	bne.s	free_link_previous              ; no
	move.l	4(a5),d0                        ; yes: joined
	add.l	d0,4(a4)
	move.l	(a5),(a4)
	bra.s	free_done
free_link_previous:
	move.l	a5,(a4)
free_done:
	move.l	a4,malloc_free_list
free_return:
	movem.l	(sp)+,a4-a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Remember the open mode of a handle in fd_modes (23 entries of handle and mode).
;------------------------------------------------------------------------------
fd_set_mode:	; from: open
	link	a6,#-2                          ; 2 bytes of locals
	clr.w	-$2(a6)                         ; the first entry
	bra.s	fd_set_loop
fd_set_find:
	move.w	-$2(a6),d0
	asl.w	#2,d0                           ; * 4: longs
	lea	fd_modes,a0
	move.w	0(a0,d0.w),d0                   ; free?
	bne.s	fd_set_next                     ; no
	move.w	-$2(a6),d0                      ; yes:
	asl.w	#2,d0                           ; * 4: longs
	lea	fd_modes,a0
	move.w	8(a6),0(a0,d0.w)                ; the handle
	move.w	-$2(a6),d0
	asl.w	#2,d0                           ; * 4: longs
	lea	fd_modes,a0
	move.w	$a(a6),2(a0,d0.w)               ; the mode
	bra.s	fd_set_done
fd_set_next:
	addq.w	#1,-$2(a6)
fd_set_loop:
	cmpi.w	#$17,-$2(a6)
	blt.s	fd_set_find
fd_set_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Forget a handle in fd_modes.
;------------------------------------------------------------------------------
fd_clear:	; from: close
	link	a6,#-2                          ; 2 bytes of locals
	clr.w	-$2(a6)
	bra.s	fd_clear_loop
fd_clear_find:
	move.w	-$2(a6),d0
	asl.w	#2,d0                           ; * 4: longs
	lea	fd_modes,a0
	move.w	0(a0,d0.w),d0
	cmp.w	8(a6),d0                        ; this handle?
	bne.s	fd_clear_next                   ; no
	move.w	-$2(a6),d0                      ; yes: cleared
	asl.w	#2,d0                           ; * 4: longs
	lea	fd_modes,a0
	clr.w	0(a0,d0.w)
fd_clear_next:
	addq.w	#1,-$2(a6)
fd_clear_loop:
	cmpi.w	#$17,-$2(a6)
	blt.s	fd_clear_find
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The open mode remembered for a handle (the last entry's when it is not there).
;------------------------------------------------------------------------------
fd_mode:	; from: lseek, read, write
	link	a6,#-2                          ; 2 bytes of locals
	movem.l	d7,-(sp)                        ; keep the registers
	move.w	8(a6),d7                        ; the handle
	move.w	#$5c,-$2(a6)                    ; the table's length
	lea	fd_modes,a0
	movea.l	a0,a1
	adda.w	-$2(a6),a1                      ; its end
fd_mode_find:
	cmp.w	(a0),d7                         ; this one?
	beq.s	fd_mode_found                   ; yes
	addq.w	#4,a0
	cmpa.l	a0,a1
	bne.s	fd_mode_find
fd_mode_found:
	move.w	2(a0),d0                        ; its mode
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; open(name, mode): CON:, AUX: and PRT: are handles 0, 2 and 3; otherwise Fopen, or Fcreate when creating or
; truncating.  The mode is remembered.  Nothing calls it.
;------------------------------------------------------------------------------
open:
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	pea	text_con                        ; "CON:"
	move.l	8(a6),-(sp)                     ; the name
	jsr	strcmp
	addq.l	#8,sp                           ; drop the arguments
	bne.s	open_not_con                    ; not it
	clr.w	d7                              ; handle 0
	bra.w	open_done
open_not_con:
	pea	text_aux                        ; "AUX:"
	move.l	8(a6),-(sp)                     ; argument 1
	jsr	strcmp
	addq.l	#8,sp                           ; drop the arguments
	bne.s	open_not_aux                    ; not it
	move.w	#$2,d7                          ; handle 2
	bra.w	open_done
open_not_aux:
	pea	text_prt                        ; "PRT:"
	move.l	8(a6),-(sp)                     ; argument 1
	jsr	strcmp
	addq.l	#8,sp                           ; drop the arguments
	bne.s	open_file                       ; not it
	move.w	#$3,d7                          ; handle 3
	bra.w	open_done
open_file:
	move.w	$c(a6),d0                       ; create?
	and.w	#$4,d0
	beq.s	open_not_create                 ; no
	move.w	$c(a6),d0                       ; yes: try to open it first
	and.w	#$3,d0
	move.w	d0,-(sp)                        ; argument 2
	move.l	8(a6),-(sp)                     ; argument 1
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d7                           ; the handle
	tst.w	d0                              ; opened?
	blt.s	open_create                     ; no
	move.w	$c(a6),d0                       ; yes: truncate?
	and.w	#$10,d0
	beq.s	open_created                    ; no
open_create:
	tst.w	d7                              ; open?
	blt.s	open_fcreate                    ; no
	move.w	d7,-(sp)                        ; yes: closed
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
open_fcreate:
	clr.w	-(sp)                           ; argument 2
	move.l	8(a6),-(sp)                     ; the name
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d7                           ; the handle
open_created:
	bra.s	open_done
open_not_create:
	move.w	$c(a6),d0                       ; truncate?
	and.w	#$10,d0
	beq.s	open_plain                      ; no
	move.w	$c(a6),d0                       ; yes: open it
	and.w	#$3,d0
	move.w	d0,-(sp)                        ; argument 2
	move.l	8(a6),-(sp)                     ; argument 1
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d7
	tst.w	d0                              ; opened?
	blt.s	open_truncated                  ; no
	move.w	d7,-(sp)                        ; yes: close it
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	clr.w	-(sp)                           ; and create it again
	move.l	8(a6),-(sp)                     ; argument 1
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d7                           ; the handle
open_truncated:
	bra.s	open_done
open_plain:
	move.w	$c(a6),d0                       ; the mode
	and.w	#$3,d0
	move.w	d0,-(sp)                        ; argument 2
	move.l	8(a6),-(sp)                     ; the name
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d7                           ; the handle
open_done:
	tst.w	d7                              ; a handle?
	bge.s	open_remember                   ; yes
	move.w	d7,errno                        ; no: the error
	move.w	#$ffff,d0
	bra.s	open_return
open_remember:
	move.w	$c(a6),-(sp)                    ; the mode
	move.w	d7,-(sp)                        ; the handle
	jsr	fd_set_mode                     ; remembered
	addq.l	#4,sp                           ; drop the arguments
	move.w	d7,d0                           ; the handle
open_return:
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Read one byte from a handle; ^Z at the end.
;------------------------------------------------------------------------------
read_byte:	; from: console_getc
	link	a6,#-2                          ; 2 bytes of locals
	pea	-$1(a6)                         ; into the frame
	move.l	#$1,-(sp)                       ; 1 byte
	move.w	8(a6),-(sp)                     ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	bne.s	read_byte_done                  ; read?
	move.b	#$1a,-$1(a6)                    ; no: ^Z
read_byte_done:
	move.b	-$1(a6),d0
	ext.w	d0                              ; to a word
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The next character typed: a line is read into console_line with backspace and echo, ^C ends the program,
; ^Z ends the input.
;------------------------------------------------------------------------------
console_getc:	; from: read
	link	a6,#-4                          ; 4 bytes of locals
	move.w	console_line_len,d0             ; anything left in the line?
	cmp.w	console_line_pos,d0
	bne.w	console_take                    ; yes
	move.w	#$0,d0                          ; no: a new line
	move.w	d0,console_line_pos
	move.w	d0,console_line_len
	bra.w	console_more
console_read:
	clr.w	-(sp)                           ; handle 0
	jsr	read_byte                       ; a character
	addq.l	#2,sp                           ; drop the arguments
	move.w	d0,-$4(a6)
	cmpi.w	#$8,-$4(a6)                     ; backspace?
	bne.s	console_not_backspace           ; no
	move.w	#$1,-(sp)                       ; the screen?
	jsr	isatty
	addq.l	#2,sp                           ; drop the arguments
	beq.s	console_backspace               ; no
	move.w	#$20,-(sp)                      ; yes: rub it out with a space
	move.w	#$2,-(sp)                       ; argument 1
	move.w	#$3,-(sp)                       ; Bconout(2, ...)
	jsr	bios                            ; BIOS
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$8,-(sp)                       ; and back
	move.w	#$2,-(sp)                       ; argument 1
	move.w	#$3,-(sp)                       ; the function
	jsr	bios                            ; BIOS
	addq.l	#6,sp                           ; drop the arguments
console_backspace:
	move.w	console_line_len,d0             ; anything to remove?
	beq.s	console_next                    ; no
	subq.w	#1,console_line_len             ; one fewer
console_next:
	bra.w	console_more
console_not_backspace:
	cmpi.w	#$d,-$4(a6)                     ; Return?
	bne.s	console_not_return              ; no
	move.w	console_line_len,d0
	addq.w	#1,console_line_len
	lea	console_line,a0
	move.b	#$a,0(a0,d0.w)                  ; the line ends with a linefeed
	move.w	#$a,-(sp)                       ; echoed
	move.w	#$2,-(sp)                       ; argument 1
	move.w	#$3,-(sp)                       ; the function
	jsr	bios                            ; BIOS
	addq.l	#6,sp                           ; drop the arguments
	bra.w	console_take
console_not_return:
	cmpi.w	#$3,-$4(a6)                     ; ^C?
	bne.s	console_not_break               ; no
	move.w	#$2,-(sp)                       ; yes: exit(2)
	jsr	exit
	addq.l	#2,sp                           ; drop the arguments
console_not_break:
	cmpi.w	#$1a,-$4(a6)                    ; ^Z?
	bne.s	console_store                   ; no
	move.w	-$4(a6),d0                      ; yes: stored
	move.w	console_line_len,d1
	addq.w	#1,console_line_len
	lea	console_line,a0
	move.b	d0,0(a0,d1.w)
	move.w	#$d,-(sp)                       ; a new line echoed
	move.w	#$2,-(sp)                       ; argument 1
	move.w	#$3,-(sp)                       ; the function
	jsr	bios                            ; BIOS
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$a,-(sp)                       ; argument 2
	move.w	#$2,-(sp)                       ; argument 1
	move.w	#$3,-(sp)                       ; the function
	jsr	bios                            ; BIOS
	addq.l	#6,sp                           ; drop the arguments
	bra.s	console_take
console_store:
	move.w	-$4(a6),d0                      ; stored
	move.w	console_line_len,d1
	addq.w	#1,console_line_len
	lea	console_line,a0
	move.b	d0,0(a0,d1.w)
console_more:
	move.w	#$1,d0
	bne.w	console_read                    ; on
console_take:
	move.w	console_line_pos,d0             ; the next character
	lea	console_line,a0
	move.b	0(a0,d0.w),d0
	ext.w	d0                              ; to a word
	cmp.w	#$1a,d0                         ; ^Z?
	bne.s	console_char                    ; no
	addq.w	#1,console_line_pos             ; yes: the end
	move.w	#$ffff,d0
	bra.s	console_done
	bra.s	console_done
console_char:
	move.w	console_line_pos,d0
	addq.w	#1,console_line_pos
	lea	console_line,a0
	move.b	0(a0,d0.w),d0                   ; the character
	ext.w	d0                              ; to a word
	nop
console_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; read(handle, buffer, count): the console through console_getc; a text mode file has its carriage returns
; taken out.  d0 = the count read, -1 on error.
;------------------------------------------------------------------------------
read:	; from: filbuf
	link	a6,#-8                          ; 8 bytes of locals
	movem.l	a4-a5,-(sp)                     ; keep the registers
	movea.l	$a(a6),a5                       ; the buffer
	move.w	$e(a6),d0                       ; the count
	and.l	#$ffff,d0
	move.l	d0,-$4(a6)
	clr.w	errno                           ; no error
	move.w	8(a6),-(sp)                     ; the handle
	jsr	isatty                          ; a terminal?
	addq.l	#2,sp                           ; drop the arguments
	beq.s	read_file                       ; no
	clr.l	-$4(a6)
	bra.s	read_console_loop
read_console:
	jsr	console_getc                    ; a character
	move.b	d0,(a5)                         ; stored
	cmp.w	#$ffff,d0                       ; the end?
	bne.s	read_console_next               ; no
	bra.s	read_console_done
	bra.s	read_console_loop
read_console_next:
	addq.l	#1,a5
	addq.l	#1,-$4(a6)                      ; counted
read_console_loop:
	move.w	$e(a6),d0
	subq.w	#1,$e(a6)
	tst.w	d0
	bne.s	read_console
read_console_done:
	move.l	-$4(a6),d0                      ; the count
	bra.w	read_exit
	bra.s	read_text
read_file:
	move.l	$a(a6),-(sp)                    ; the buffer
	move.l	-$4(a6),-(sp)                   ; the count
	move.w	8(a6),-(sp)                     ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	tst.l	d0                              ; all right?
	bge.s	read_text                       ; yes
	move.l	-$4(a6),d0                      ; no: the error
	move.w	d0,errno
	move.w	#$ffff,d0
	bra.w	read_exit
read_text:
	move.w	8(a6),-(sp)                     ; the handle's mode
	jsr	fd_mode
	addq.l	#2,sp                           ; drop the arguments
	and.w	#$2000,d0                       ; binary?
	bne.w	read_return                     ; yes: done
	move.l	-$4(a6),d0                      ; the bytes still wanted
	move.w	d0,$e(a6)
	move.l	$a(a6),d0                       ; the buffer
	movea.l	d0,a5                           ; a5 reads
	movea.l	d0,a4                           ; a4 writes
	bra.s	read_text_next
read_text_loop:
	move.l	a5,d0                           ; how far a5 is in
	sub.l	$a(a6),d0
	ext.l	d0                              ; to a long
	cmp.l	-$4(a6),d0                      ; all looked at?
	blt.s	read_text_char                  ; no
	move.l	a4,-(sp)                        ; yes: read more for the removed CRs
	move.w	$e(a6),d0
	and.l	#$ffff,d0
	move.l	d0,-(sp)                        ; argument 2
	move.w	8(a6),-(sp)                     ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; read
	tst.l	d0                              ; an error?
	bge.s	read_text_more
	move.l	-$8(a6),d0                      ; yes: errno
	move.w	d0,errno
	move.w	#$ffff,d0                       ; -1
	bra.s	read_exit
read_text_more:
	move.l	-$8(a6),d0                      ; nothing more?
	bne.s	read_text_got                   ; some
	bra.s	read_text_done                  ; no: done
read_text_got:
	move.w	$e(a6),d0                       ; the bytes still wanted, less those read
	and.l	#$ffff,d0
	sub.l	-$8(a6),d0
	sub.l	d0,-$4(a6)                      ; off the count
	movea.l	a4,a5                           ; from where the text has got to
read_text_char:
	move.b	(a5),d0
	ext.w	d0                              ; to a word
	cmp.w	#$d,d0                          ; carriage return?
	bne.s	read_text_keep                  ; no
	addq.l	#1,a5                           ; yes: skipped
	bra.s	read_text_next
read_text_keep:
	move.b	(a5)+,(a4)+                     ; kept
	subq.w	#1,$e(a6)                       ; one fewer wanted
read_text_next:
	move.w	$e(a6),d0                       ; more wanted?
	bne.s	read_text_loop
read_text_done:
	move.l	a4,d0                           ; the bytes kept
	sub.l	$a(a6),d0
	ext.l	d0                              ; to a long
	move.l	d0,-$4(a6)
read_return:
	move.l	-$4(a6),d0                      ; returned
read_exit:
	movem.l	(sp)+,a4-a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; strrchr(string, c): the last c in the string, or its end for c = 0; 0 when not found.
;------------------------------------------------------------------------------
strrchr:	; from: choose_file, jam_unjam, unjam_file, count_folder, write_jam, add_to_jam, 1 more
	movea.l	4(sp),a0                        ; the string
	move.b	9(sp),d2                        ; the character
	bne.s	strrchr_search                  ; not 0
	moveq	#-1,d0                          ; 0: the end of the string
strrchr_end:
	tst.b	(a0)+
	dbeq	d0,strrchr_end
	bne.s	strrchr_end
	move.l	a0,d0
	bra.s	strrchr_done
strrchr_search:
	move.l	#$1,d0                          ; 0 + 1 when not found
strrchr_loop:
	move.b	(a0)+,d1
	beq.s	strrchr_done                    ; the end?
	cmp.b	d1,d2
	bne.s	strrchr_loop                    ; c?
	move.l	a0,d0                           ; yes: noted
	bra.s	strrchr_loop
strrchr_done:
	subq.l	#1,d0                           ; one back
	rts

;------------------------------------------------------------------------------
; Malloc(size); -1 when there is no memory.
;------------------------------------------------------------------------------
sbrk:	; from: morecore, sbrk_word
	link	a6,#-4                          ; 4 bytes of locals
	move.l	8(a6),-(sp)                     ; the size
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$4(a6)                      ; the block
	move.l	-$4(a6),d0
	bne.s	sbrk_done                       ; got it?
	move.l	#$ffffffff,-$4(a6)              ; no: -1
	move.w	#$ffd9,errno                    ; and the error
sbrk_done:
	move.l	-$4(a6),d0                      ; returned
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; sbrk_word(n): sbrk with a word.
;------------------------------------------------------------------------------
sbrk_word:
	link	a6,#0                           ; the frame
	move.w	8(a6),d0
	and.l	#$ffff,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	sbrk
	addq.l	#4,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; strcat(destination, source).
;------------------------------------------------------------------------------
strcat:	; from: choose_file, multi_pack, show_pack_sizes, show_crunching, jam_unjam, unjam_file, 7 more
	link	a6,#0                           ; the frame
	move.l	8(a6),d0                        ; the destination
	movea.l	d0,a0
	movea.l	$c(a6),a1                       ; the source
	moveq	#-1,d1
strcat_end:
	tst.b	(a0)+                           ; find the end
	dbeq	d1,strcat_end
	bne.s	strcat_end
	subq.l	#1,a0
strcat_copy:
	move.b	(a1)+,(a0)+                     ; copy
	dbeq	d1,strcat_copy
	bne.s	strcat_copy
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; strcmp(a, b).
;------------------------------------------------------------------------------
strcmp:	; from: count_folder, write_jam, open
	movem.l	4(sp),a0-a1                     ; both strings
	clr.w	d0
strcmp_loop:
	move.b	(a0)+,d0
	beq.s	strcmp_end                      ; the end?
	cmp.b	(a1)+,d0                        ; the same?
	beq.s	strcmp_loop                     ; yes: on
	subq.l	#1,a1
strcmp_end:
	clr.w	d1
	move.b	(a1),d1
	beq.s	strcmp_sign
	ext.w	d0                              ; to a word
strcmp_sign:
	tst.w	d0
	beq.s	strcmp_done
	ext.w	d1                              ; to a word
strcmp_done:
	sub.w	d1,d0                           ; the difference
	rts

;------------------------------------------------------------------------------
; strcpy(destination, source); d0 = the destination.
;------------------------------------------------------------------------------
strcpy:	; from: main, choose_file, multi_pack, note_file, show_crunching, jam_unjam, 6 more
	movem.l	4(sp),a0-a1                     ; both strings
	move.l	a0,d0                           ; returned
	moveq	#-1,d1
strcpy_loop:
	move.b	(a1)+,(a0)+                     ; copy
	dbeq	d1,strcpy_loop
	bne.s	strcpy_loop
	rts

;------------------------------------------------------------------------------
; strlen(string).
;------------------------------------------------------------------------------
strlen:	; from: multi_pack, is_program_name, jam_unjam, write_jam, disk_unpack, disk_pack
	movea.l	4(sp),a0                        ; the string
	moveq	#-1,d0
	bra.s	strlen_loop
strlen_more:
	addq.w	#1,d0                           ; more than 64 K
	subq.l	#1,d0
strlen_loop:
	tst.b	(a0)+
	dbeq	d0,strlen_loop
	bne.s	strlen_more
	not.l	d0                              ; the length
	rts

;------------------------------------------------------------------------------
; strncmp(a, b, n).
;------------------------------------------------------------------------------
strncmp:	; from: is_program_name
	movem.l	4(sp),a0-a1                     ; both strings
	move.w	$c(sp),d1                       ; n
	bne.s	strncmp_compare                 ; not 0
	move.w	d1,d0                           ; 0: equal
	rts
strncmp_compare:
	subq.w	#1,d1
	clr.w	d0
strncmp_loop:
	move.b	(a0)+,d0
	beq.s	strncmp_end                     ; the end?
	cmp.b	(a1)+,d0                        ; the same?
	dbne	d1,strncmp_loop
	subq.l	#1,a1
strncmp_end:
	clr.w	d1
	move.b	(a1),d1
	beq.s	strncmp_sign
	ext.w	d0                              ; to a word
strncmp_sign:
	tst.w	d0
	beq.s	strncmp_done
	ext.w	d1                              ; to a word
strncmp_done:
	sub.w	d1,d0                           ; the difference
	rts

;------------------------------------------------------------------------------
; write(handle, buffer, count): a text mode file (or the console) has a carriage return put before each
; linefeed, written through a 512 byte buffer in the frame.  d0 = the count, -1 on error.
;------------------------------------------------------------------------------
write:	; from: fflush
	link	a6,#-518                        ; 518 bytes of locals
	movem.l	d6-d7/a3-a5,-(sp)               ; keep the registers
	movea.l	$a(a6),a5                       ; the buffer
	movea.l	a5,a4
	clr.w	-$2(a6)
	cmpi.w	#$1,8(a6)                       ; the console?
	beq.s	write_text                      ; yes: text
	move.w	8(a6),-(sp)                     ; argument 1
	jsr	fd_mode                         ; the handle's mode
	addq.l	#2,sp                           ; drop the arguments
	and.w	#$2000,d0                       ; binary?
	bne.w	write_binary                    ; yes
write_text:
	lea	-$206(a6),a0                    ; the frame's buffer
	movea.l	a0,a3
	move.l	a4,d7
	sub.l	a5,d7
	cmp.w	$e(a6),d7                       ; more?
	scs	d7
	and.w	#$1,d7
	bra.s	write_text_more
write_text_loop:
	move.b	(a4)+,d0                        ; a character
	move.b	d0,(a3)+
	ext.w	d0                              ; to a word
	cmp.w	#$a,d0                          ; linefeed?
	bne.s	write_text_next                 ; no
	move.l	a3,d0                           ; yes: a carriage return first
	subq.l	#1,d0
	movea.l	d0,a0
	move.b	#$d,(a0)
	move.b	#$a,(a3)+
write_text_next:
	move.l	a4,d7
	sub.l	a5,d7
	cmp.w	$e(a6),d7                       ; more?
	scs	d7
	and.w	#$1,d7
	move.l	a3,d0
	lea	-$206(a6),a0
	sub.l	a0,d0
	cmp.w	#$1fe,d0                        ; buffer full?
	bge.s	write_text_flush                ; yes
	move.w	d7,d0
	bne.s	write_text_more                 ; more: on
write_text_flush:
	move.l	a3,d0
	lea	-$206(a6),a0
	sub.l	a0,d0
	ext.l	d0                              ; to a long
	move.l	d0,-$6(a6)
	pea	-$206(a6)                       ; the buffer
	move.l	-$6(a6),-(sp)                   ; its length
	move.w	8(a6),-(sp)                     ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	move.w	d0,d6
	cmp.l	-$6(a6),d0                      ; all written?
	beq.s	write_text_empty                ; yes
	move.w	d6,errno                        ; no: the error
	move.w	#$ffff,d0
	bra.s	write_done
write_text_empty:
	lea	-$206(a6),a0
	movea.l	a0,a3
write_text_more:
	move.w	d7,d0
	bne.w	write_text_loop
	move.l	a4,d0
	sub.l	a5,d0
	move.w	d0,-$2(a6)
	bra.s	write_count
write_binary:
	move.l	a5,-(sp)                        ; the buffer
	move.w	$e(a6),d0                       ; the count
	and.l	#$ffff,d0
	move.l	d0,-(sp)                        ; argument 2
	move.w	8(a6),-(sp)                     ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$6(a6)
	move.w	$e(a6),d1
	and.l	#$ffff,d1
	cmp.l	d1,d0                           ; all written?
	beq.s	write_binary_done               ; yes
	move.l	-$6(a6),d0                      ; no: the error
	move.w	d0,errno
	move.w	#$ffff,d0
	bra.s	write_done
write_binary_done:
	move.l	-$6(a6),d0
	add.w	d0,-$2(a6)
write_count:
	move.w	-$2(a6),d0                      ; the count
write_done:
	movem.l	(sp)+,d6-d7/a3-a5               ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; aes(opcode): control[0] = the opcode, control[1-3] from aes_counts; d0 = intout[0].
;------------------------------------------------------------------------------
aes:	; from: appl_exit, appl_init, evnt_button, form_alert, form_center, form_dial, 10 more
	link	a6,#-6                          ; 6 bytes of locals
	move.w	8(a6),aes_control               ; control[0]
	move.w	8(a6),d0
	sub.w	#$a,d0                          ; less 10
	muls.w	#$3,d0                          ; 3 bytes an opcode
	lea	aes_counts,a0                   ; the counts
	ext.l	d0                              ; to a long
	add.l	a0,d0
	move.l	d0,-$6(a6)
	move.w	#$1,-$2(a6)                     ; control[1-3]
	bra.s	aes_counts_next
aes_counts_loop:
	movea.l	-$6(a6),a0
	addq.l	#1,-$6(a6)
	move.b	(a0),d0                         ; a count
	move.w	-$2(a6),d1
	asl.w	#1,d1                           ; * 2: words
	lea	aes_control,a0
	ext.w	d0                              ; to a word
	move.w	d0,0(a0,d1.w)                   ; into control
	addq.w	#1,-$2(a6)
aes_counts_next:
	cmpi.w	#$4,-$2(a6)
	blt.s	aes_counts_loop
	move.l	aes_pb_ptr,-(sp)                ; the parameter block
	jsr	aes_trap                        ; the trap
	addq.l	#4,sp                           ; drop the arguments
	move.w	aes_intout,d0                   ; intout[0]
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; v_bar(handle, pxy).
;------------------------------------------------------------------------------
v_bar:	; from: clear_title
	link	a6,#0                           ; the frame
	move.l	$a(a6),vdi_pb+8                 ; ptsin = pxy
	move.w	#$b,vdi_contrl                  ; opcode 11
	move.w	#$2,vdi_contrl+2                ; 2 points
	clr.w	vdi_contrl+6                    ; no intin
	move.w	#$1,vdi_contrl+10               ; sub-opcode 1
	move.w	8(a6),vdi_contrl+12             ; the handle
	jsr	vdi                             ; call
	lea	vdi_ptsin,a0                    ; ptsin back
	move.l	a0,vdi_pb+8
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; v_clsvwk(handle).
;------------------------------------------------------------------------------
v_clsvwk:	; from: close_gem
	link	a6,#0                           ; the frame
	move.w	#$65,vdi_contrl                 ; opcode 101
	clr.w	vdi_contrl+2                    ; no points
	clr.w	vdi_contrl+6                    ; no intin
	move.w	8(a6),vdi_contrl+12             ; the handle
	jsr	vdi                             ; call
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; v_exit_cur(handle): leave the text cursor mode.
;------------------------------------------------------------------------------
v_exit_cur:	; from: multi_pack
	link	a6,#0                           ; the frame
	move.w	#$5,vdi_contrl                  ; opcode 5
	clr.w	vdi_contrl+2
	clr.w	vdi_contrl+6
	move.w	#$3,vdi_contrl+10               ; sub-opcode 3
	move.w	8(a6),vdi_contrl+12             ; the handle
	jsr	vdi                             ; call
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; v_enter_cur(handle): enter the text cursor mode.
;------------------------------------------------------------------------------
v_enter_cur:	; from: multi_pack
	link	a6,#0                           ; the frame
	move.w	#$5,vdi_contrl                  ; opcode 5
	clr.w	vdi_contrl+2
	clr.w	vdi_contrl+6
	move.w	#$2,vdi_contrl+10               ; sub-opcode 2
	move.w	8(a6),vdi_contrl+12             ; the handle
	jsr	vdi                             ; call
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; v_gtext(handle, x, y, string).
;------------------------------------------------------------------------------
v_gtext:	; from: show_title
	link	a6,#-2                          ; 2 bytes of locals
	move.w	$a(a6),vdi_ptsin                ; x
	move.w	$c(a6),vdi_ptsin+2              ; y
	clr.w	-$2(a6)                         ; count the characters
	nop
v_gtext_loop:
	movea.l	$e(a6),a0
	addq.l	#1,$e(a6)
	move.b	(a0),d0                         ; a character
	move.w	-$2(a6),d1
	addq.w	#1,-$2(a6)
	ext.l	d1                              ; to a long
	asl.l	#1,d1                           ; words
	lea	vdi_intin,a0
	and.w	#$ff,d0
	move.w	d0,0(a0,d1.l)                   ; into intin
	bne.s	v_gtext_loop                    ; to the end
	move.w	#$8,vdi_contrl                  ; opcode 8
	move.w	#$1,vdi_contrl+2                ; 1 point
	subq.w	#1,-$2(a6)
	move.w	-$2(a6),d0
	move.w	d0,vdi_contrl+6                 ; the characters
	move.w	8(a6),vdi_contrl+12             ; the handle
	jsr	vdi                             ; call
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; v_opnvwk(work_in, &handle, work_out).
;------------------------------------------------------------------------------
v_opnvwk:	; from: open_workstation
	link	a6,#0                           ; the frame
	move.l	8(a6),vdi_pb+4                  ; intin = work_in
	move.l	$10(a6),vdi_pb+12               ; intout = work_out
	move.l	$10(a6),d0
	add.l	#$5a,d0
	move.l	d0,vdi_pb+16                    ; ptsout = work_out + 45 words
	move.w	#$64,vdi_contrl                 ; opcode 100
	clr.w	vdi_contrl+2
	move.w	#$b,vdi_contrl+6                ; 11 intin
	movea.l	$c(a6),a0
	move.w	(a0),vdi_contrl+12              ; the AES's handle
	jsr	vdi                             ; call
	move.w	vdi_contrl+12,d0                ; the new handle
	movea.l	$c(a6),a0
	move.w	d0,(a0)                         ; returned
	move.w	d0,last_vdi_handle              ; kept
	lea	vdi_intin,a0                    ; the arrays back
	move.l	a0,vdi_pb+4
	lea	vdi_intout,a0
	move.l	a0,vdi_pb+12
	lea	vdi_ptsout,a0
	move.l	a0,vdi_pb+16
	lea	vdi_ptsin,a0
	move.l	a0,vdi_pb+8
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Set the long in control[7-8], or control[9-10], or read the latter back.  Nothing calls them.
;------------------------------------------------------------------------------
vdi_set_ptr1:
	link	a6,#0                           ; the frame
	move.l	8(a6),d0
	asr.l	#8,d0
	asr.l	#8,d0                           ; high word
	move.w	d0,vdi_contrl+14
	move.l	8(a6),d0
	and.l	#$ffff,d0                       ; low word
	move.w	d0,vdi_contrl+16
	unlk	a6                              ; the frame back
	rts
vdi_set_ptr2:
	link	a6,#0                           ; the frame
	move.l	8(a6),d0
	asr.l	#8,d0
	asr.l	#8,d0
	move.w	d0,vdi_contrl+18
	move.l	8(a6),d0
	and.l	#$ffff,d0
	move.w	d0,vdi_contrl+20
	unlk	a6                              ; the frame back
	rts
vdi_get_ptr2:
	link	a6,#0                           ; the frame
	move.w	vdi_contrl+18,d0
	and.l	#$ffff,d0
	asl.l	#8,d0
	asl.l	#8,d0
	move.w	vdi_contrl+20,d3
	and.l	#$ffff,d3
	or.l	d3,d0
	movea.l	8(a6),a0
	move.l	d0,(a0)
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; vdi(): the trap with vdi_block; a1, a2 kept on trap_save_stack.
;------------------------------------------------------------------------------
vdi:	; from: v_bar, v_clsvwk, v_exit_cur, v_enter_cur, v_gtext, v_opnvwk, 3 more
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	addq.w	#4,trap_save_index
	move.l	a1,(a0)                         ; keep a1
	move.l	a2,$10(a0)                      ; and a2
	pea	vdi_contrl                      ; control
	move.l	(sp),$20(a0)
	move.l	(sp)+,vdi_pb                    ; is the block's first entry
	pea	vdi_pb                          ; the block
	move.l	(sp)+,d1
	move.l	#$73,d0                         ; VDI
	trap	#2                              ; AES/VDI
	subq.w	#4,trap_save_index              ; back a slot
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	movea.l	(a0),a1                         ; a1 back
	movea.l	$10(a0),a2                      ; a2
	rts

;------------------------------------------------------------------------------
; vqt_extent(handle, string, extent).
;------------------------------------------------------------------------------
vqt_extent:	; from: show_title
	link	a6,#-4                          ; 4 bytes of locals
	lea	vdi_intin,a0                    ; intin
	move.l	a0,-$4(a6)
	nop
vqt_extent_loop:
	movea.l	$a(a6),a0
	addq.l	#1,$a(a6)
	move.b	(a0),d0                         ; a character
	movea.l	-$4(a6),a0
	addq.l	#2,-$4(a6)
	ext.w	d0                              ; to a word
	move.w	d0,(a0)                         ; into intin
	bne.s	vqt_extent_loop                 ; to the end
	move.l	$e(a6),vdi_pb+16                ; ptsout = extent
	move.w	#$74,vdi_contrl                 ; opcode 116
	clr.w	vdi_contrl+2                    ; no points
	move.l	-$4(a6),d0
	lea	vdi_intin,a0
	sub.l	a0,d0
	asr.l	#1,d0                           ; words
	subq.w	#1,d0                           ; the count
	move.w	d0,vdi_contrl+6
	move.w	8(a6),vdi_contrl+12             ; the handle
	jsr	vdi                             ; call
	lea	vdi_ptsout,a0                   ; ptsout back
	move.l	a0,vdi_pb+16
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; vsf_interior(handle, style).
;------------------------------------------------------------------------------
vsf_interior:	; from: clear_title
	link	a6,#0                           ; the frame
	move.w	$a(a6),vdi_intin                ; the style
	move.w	#$17,vdi_contrl                 ; opcode 23
	clr.w	vdi_contrl+2
	move.w	#$1,vdi_contrl+6                ; 1 intin
	move.w	8(a6),vdi_contrl+12             ; the handle
	jsr	vdi                             ; call
	move.w	vdi_intout,d0                   ; the style set
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; vsf_style(handle, index).
;------------------------------------------------------------------------------
vsf_style:	; from: clear_title
	link	a6,#0                           ; the frame
	move.w	$a(a6),vdi_intin                ; the index
	move.w	#$18,vdi_contrl                 ; opcode 24
	clr.w	vdi_contrl+2
	move.w	#$1,vdi_contrl+6                ; 1 intin
	move.w	8(a6),vdi_contrl+12             ; the handle
	jsr	vdi                             ; call
	move.w	vdi_intout,d0                   ; the index set
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The AES trap with the parameter block at 4(sp); a1, a2 kept on trap_save_stack.
;------------------------------------------------------------------------------
aes_trap:	; from: aes
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	addq.w	#4,trap_save_index
	move.l	a1,(a0)                         ; keep a1
	move.l	a2,$10(a0)                      ; and a2
	move.l	4(sp),d1                        ; the block
	move.w	#$c8,d0                         ; AES
	trap	#2                              ; AES/VDI
	subq.w	#4,trap_save_index              ; back a slot
	lea	trap_save_stack,a0
	adda.w	trap_save_index,a0
	movea.l	(a0),a1                         ; a1 back
	movea.l	$10(a0),a2                      ; a2
	rts
aes_counts:	; from: aes
	dc.w	$0001,$0002,$0101,$0201,$0100,$0101,$0201,$0101 ; intin, intout and addrin counts of the AES calls from
                                                ;   opcode 10 on, 3 bytes each
	dc.w	$0101,$0000,$0000,$0000,$0000,$0000,$0100,$0001
	dc.w	$0003,$0500,$0505,$0000,$0101,$0201,$0010,$0701
	dc.w	$0201,$0000,$0000,$0000,$0000,$0000,$0101,$0102
	dc.w	$0101,$0201,$0102,$0101,$0101,$0201,$0101,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0201,$0101,$0101
	dc.w	$0601,$0104,$0101,$0103,$0102,$0101,$0402,$0108
	dc.w	$0101,$0000,$0000,$0000,$0101,$0109,$0101,$0101
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
	dc.w	$0101,$0001,$0100,$0102

;------------------------------------------------------------------------------
; rsrc_obfix(tree, object).
;------------------------------------------------------------------------------
rsrc_obfix:	; from: rsrc_relocate
	link	a6,#0                           ; the frame
	move.l	8(a6),aes_addrin                ; the tree
	move.w	$c(a6),aes_intin                ; the object
	move.w	#$72,-(sp)                      ; opcode 114
	jsr	aes                             ; call
	addq.l	#2,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Unsigned long division, as ldiv.
;------------------------------------------------------------------------------
uldiv:	; from: morecore, malloc
	link	a6,#0                           ; the frame
	movem.l	d0-d3,-(sp)                     ; keep the registers
	move.l	8(a6),d2                        ; the divisor
	bne.s	uldiv_start                     ; not 0
	divu.w	#$0,d0                          ; by 0: a divide-by-zero exception
	clr.l	d0
	clr.l	d1
	bra.s	uldiv_done
uldiv_start:
	move.l	$c(a6),d1                       ; the dividend
	clr.l	d0                              ; the quotient
	moveq	#1,d3                           ; the quotient bit
uldiv_shift:
	cmp.l	d1,d2                           ; line the divisor up
	bcc.s	uldiv_divide
	asl.l	#1,d2
	bcc.s	uldiv_shift_bit
	roxr.l	#1,d2
	bra.s	uldiv_divide
uldiv_shift_bit:
	asl.l	#1,d3
	bra.s	uldiv_shift
uldiv_divide:
	cmp.l	d1,d2                           ; fits?
	bhi.s	uldiv_next                      ; no
	or.l	d3,d0                           ; yes: the bit
	sub.l	d2,d1                           ; subtracted
uldiv_next:
	lsr.l	#1,d2
	lsr.l	#1,d3
	bcc.s	uldiv_divide                    ; for each bit
uldiv_done:
	move.l	d0,8(a6)                        ; the quotient
	move.l	d1,$c(a6)                       ; the remainder
	movem.l	(sp)+,d0-d3                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Unsigned long multiply, as lmul.
;------------------------------------------------------------------------------
ulmul:	; from: morecore
	link	a6,#0                           ; the frame
	movem.l	d0-d3,-(sp)                     ; keep the registers
	movem.l	8(a6),d1-d2                     ; both
	move.l	d1,d3
	andi.l	#$ffff0000,d3
	beq.s	ulmul_cross
	swap	d3
	mulu.w	d2,d3
ulmul_cross:
	move.l	d2,d0
	swap	d0
	tst.w	d0
	beq.s	ulmul_low
	mulu.w	d1,d0
	add.w	d0,d3
ulmul_low:
	swap	d3
	clr.w	d3
	mulu.w	d1,d2
	add.l	d2,d3
	move.l	d3,$c(a6)                       ; the product
	movem.l	(sp)+,d0-d3                     ; the registers back
	unlk	a6                              ; the frame back
	move.l	(sp)+,(sp)                      ; one long off the stack
	tst.l	4(sp)                           ; flags from the product
	rts

;------------------------------------------------------------------------------
; Pterm(code).
;------------------------------------------------------------------------------
pterm:	; from: exit
	link	a6,#0                           ; the frame
	move.w	8(a6),-(sp)                     ; the code
	move.w	#$4c,-(sp)                      ; Pterm
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Give a stream a buffer: stdin and stdout on the console are left unbuffered (a 1 byte buffer of their own),
; others get malloc'ed ones, or a 1 byte one when there is no memory.
;------------------------------------------------------------------------------
getbuf:	; from: filbuf
	link	a6,#0                           ; the frame
	movem.l	a5,-(sp)                        ; keep the registers
	movea.l	8(a6),a5                        ; the stream
	move.l	a5,d0
	lea	iob+16,a0                       ; stdout?
	cmp.l	a0,d0                           ; no
	bne.s	getbuf_stdin
	move.w	#$1,-(sp)                       ; a terminal?
	jsr	isatty
	addq.l	#2,sp                           ; drop the arguments
	bne.s	getbuf_stdin                    ; no
	andi.w	#$fef7,$a(a5)                   ; yes: unbuffered
	ori.w	#$10,$a(a5)
	move.w	bufsiz,$e(a5)
	lea	iob,a0
	andi.w	#$fdff,$a(a0)
	bra.s	getbuf_check
getbuf_stdin:
	move.l	a5,d0
	lea	iob,a0                          ; stdin?
	cmp.l	a0,d0
	bne.s	getbuf_check                    ; no
	clr.w	-(sp)                           ; argument 1
	jsr	isatty                          ; a terminal?
	addq.l	#2,sp                           ; drop the arguments
	bne.s	getbuf_check                    ; no
	andi.w	#$fcf7,$a(a5)                   ; yes: unbuffered
	ori.w	#$10,$a(a5)
	move.w	bufsiz,$e(a5)
getbuf_check:
	bra.s	getbuf_done
getbuf_one_byte:
	move.w	$a(a5),d0                       ; unbuffered?
	and.w	#$8,d0
	beq.s	getbuf_malloc                   ; no
	move.l	a5,d0                           ; yes: its own byte
	lea	iob,a0
	sub.l	a0,d0
	divs.w	#$10,d0
	lea	stream_bytes,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	move.l	d0,(a5)
	move.l	d0,6(a5)
	bra.s	getbuf_done
getbuf_malloc:
	move.w	$e(a5),d0                       ; the size
	move.w	d0,-(sp)                        ; argument 1
	jsr	malloc_word                     ; malloc
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,(a5)
	move.l	d0,6(a5)
	bne.s	getbuf_own                      ; got it?
	ori.w	#$8,$a(a5)                      ; no: unbuffered
	bra.s	getbuf_done
getbuf_own:
	move.w	$a(a5),d0
	and.w	#$100,d0
	bne.s	getbuf_done
	ori.w	#$10,$a(a5)                     ; its own buffer
getbuf_done:
	move.l	6(a5),d0                        ; a buffer?
	beq.s	getbuf_one_byte                 ; no: on
	movem.l	(sp)+,a5                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; close(handle): Fclose, after forgetting its mode.  The standard handles are not closed.
;------------------------------------------------------------------------------
close:	; from: fclose
	link	a6,#-2                          ; 2 bytes of locals
	move.w	8(a6),-(sp)                     ; argument 1
	jsr	fd_clear                        ; forget it
	addq.l	#2,sp                           ; drop the arguments
	tst.w	8(a6)                           ; a file handle?
	bgt.s	close_file                      ; yes
	move.w	#$0,d0                          ; no: nothing
	bra.s	close_done
close_file:
	move.w	8(a6),-(sp)                     ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,-$2(a6)
	beq.s	close_ok                        ; all right?
	move.w	-$2(a6),errno                   ; no: the error
	move.w	#$ffff,d0
	bra.s	close_done
	bra.s	close_done
close_ok:
	move.w	#$0,d0
	nop
close_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; isatty(handle): a device when seeking 1 byte on does not move the position to 1.
;------------------------------------------------------------------------------
isatty:	; from: console_getc, read, getbuf
	link	a6,#-8                          ; 8 bytes of locals
	move.w	#$1,-(sp)                       ; from the current position
	move.w	8(a6),-(sp)                     ; the handle
	clr.l	-(sp)                           ; 0
	move.w	#$42,-(sp)                      ; Fseek: the position
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)                      ; kept
	clr.w	-(sp)                           ; from the start
	move.w	8(a6),-(sp)                     ; argument 2
	move.l	#$1,-(sp)                       ; 1
	move.w	#$42,-(sp)                      ; Fseek
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; where it went
	clr.w	-(sp)                           ; back
	move.w	8(a6),-(sp)                     ; argument 2
	move.l	-$4(a6),-(sp)                   ; argument 1
	move.w	#$42,-(sp)                      ; Fseek
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	cmpi.l	#$1,-$8(a6)                     ; not 1: a device
	sne	d0
	and.w	#$1,d0
	unlk	a6                              ; the frame back
	rts
	dc.w	$0000

	section	data

;------------------------------------------------------------------------------
; The data section: settings, texts and alerts, the two built-in resources, the packer's tables and the C
; library's variables.
;------------------------------------------------------------------------------
app_flag:	; from: start
	dc.w	$0001                           ; 1 for a program, 0 for a desk accessory
	dc.b	'AUTM',0
	dc.b	$00
v2_window:	; from: pack_file, multi_pack_file
	dc.l	$00001120                       ; how far ahead the V2 packer looks for strings
text_choose_file:	; from: pack_one_file
	dc.b	'Choose a file to pack/unpack',0
	dc.b	$00
algorithm:	; from: main, write_program, pack_file, multi_pack_file
	dc.w	$0002                           ; 2 LZH, 3 V2
pack_file_name:	; from: pack_one_file, unpack_file, pack_file
	dcb.b	20,0                            ; the name in the file selector when packing one file
text_supply_save_path:	; from: unpack_file, pack_file
	dc.b	'Supply the SAVE path and file name',0
	dc.b	$00
	dc.b	'[2][ Can',$27
	dc.b	't find the resource|file.  Must be in the same|directory as the '
	dc.b	'Shell.][  Ok  ]',0
	dc.b	$00
	dc.b	'LSD!',0
	dc.b	$00
text_supply_source_path:	; from: main
	dc.b	'Supply the SOURCE path',0
	dc.b	$00
text_prg:	; from: is_program_name
	dc.b	'PRG',0
multi_active:	; from: multi_pack, show_pack_sizes
	dc.w	$0000                           ; nonzero while multi packing
text_tos:	; from: is_program_name
	dc.b	'TOS',0
text_supply_destination_path:	; from: main
	dc.b	'Supply the DESTINATION path',0
text_ttp:	; from: is_program_name
	dc.b	'TTP',0
	dc.b	'APP',0
destination_path:	; from: main, unpack_file, pack_file
	dc.b	'\*.*',0                        ; the destination path for saving and multi packing
	dcb.b	123,0
multi_name:	; from: main
	dcb.b	20,0                            ; the name in the file selector for the multi packer
source_path:	; from: main, pack_one_file
	dc.b	'\*.*',0                        ; the source path
	dcb.b	123,0
text_data:	; from: main
	dc.b	'Data',0
	dc.b	$00
text_program:	; from: main
	dc.b	'Program',0
text_performing_multi_pack:	; from: main
	dc.b	'Performing Multi Pack...',0
	dc.b	$00
text_all_files_source:	; from: main
	dc.b	'\*.*',0                        ; "\*.*" for the source path again
	dc.b	$00
text_all_files_destination:	; from: main
	dc.b	'\*.*',0                        ; "\*.*" for the destination path again
	dc.b	$00
alert_file_not_found:	; from: pack_one_file
	dc.b	'[0][ |    File Not Found!   | ][Grrr!]',0
	dc.b	$00
alert_file_too_small:	; from: pack_one_file
	dc.b	'[0][ |   File Too Small | Not worth crunching! | ][Yes!]',0
	dc.b	$00
alert_no_memory_to_compact:	; from: pack_one_file
	dc.b	'[0][ |  Insufficient Memory To   |       Compact File | ][Utter '
	dc.b	'Bastard!]',0
alert_error_reading_source:	; from: pack_one_file
	dc.b	'[0][|Error Reading Source File | ][Oh Shit!!]',0
alert_packed_size_larger:	; from: pack_one_file
	dc.b	'[0][| Packed Size > Original Size  |      File Not saved | ][Oh '
	dc.b	'well..]',0
alert_low_rez:	; from: init_gem
	dc.b	'[1][ The JAM Packer V3.0 will| not work in low res. ][ Ok ]',0
alert_other_rez:	; from: init_gem
	dc.b	'[1][ Wow!  You',$27
	dc.b	've got a trendy|resolution on your system!|Unfortunately this pr'
	dc.b	'ogram|doesn',$27,'t support it.][ Oh... ]',0
	dc.b	$00
alert_no_workstation:	; from: open_workstation
	dc.b	'[1][ Couldn',$27,'t open workstation ][Exit]',0
	dc.b	$00
text_report_title:	; from: multi_pack
	dcb.w	11,$2020
	dc.b	' ****** MULTI PACKER REPORT ******',10,10,13,0
text_report_heading:	; from: multi_pack
	dc.b	9,'   FILE NOT COMPACTED',9,9,9,'REASON',10,13,0
text_report_indent:	; from: multi_pack
	dc.b	9,'       ',0
	dc.b	$00
text_report_tabs_short_name:	; from: multi_pack
	dc.b	9,9,9,0
text_report_tabs_long_name:	; from: multi_pack
	dc.b	9,9,0
	dc.b	$00
text_reason_too_small:	; from: multi_pack
	dc.b	'Too small - not worth compacting',10,13,0
	dc.b	$00
text_reason_larger:	; from: multi_pack
	dc.b	'Packed file larger than original',10,13,0
	dc.b	$00
text_reason_read_error:	; from: multi_pack
	dc.b	'Error reading source file',10,13,0
text_reason_write_error:	; from: multi_pack
	dc.b	'Error writing destination file',10,13,0
	dc.b	$00
text_reason_no_memory:	; from: multi_pack
	dc.b	'Not enough memory to pack file',10,13,0
	dc.b	$00
text_reason_program:	; from: multi_pack
	dc.b	'Program file',10,13,0
	dc.b	$00
text_press_return:	; from: multi_pack
	dc.b	10,10,'                            Press RETURN to continue',0
	dc.b	$00
text_decrunching:	; from: unpack_file
	dc.b	'Decrunching File....',0
	dc.b	$00
text_saving_executable:	; from: write_program
	dc.b	'Saving Executable File',0
	dc.b	$00
text_pack_complete:	; from: pack_file
	dc.b	'Pack Complete!',0
	dc.b	$00
alert_save_failure:	; from: pack_file
	dc.b	'[1][ | Save Failure!| ][Retry|Abort]',0
	dc.b	$00
text_saving_file:	; from: save_file
	dc.b	'Saving File',0
text_bytes_packed:	; from: show_pack_sizes
	dc.b	' Bytes',0
	dc.b	$00
text_bytes_saved:	; from: show_pack_sizes
	dc.b	' Bytes',0
	dc.b	$00
text_percent:	; from: show_pack_sizes
	dc.b	'%',0
text_bytes_original:	; from: show_crunching
	dc.b	' Bytes',0
	dc.b	$00
alert_cannot_make_folder:	; from: unjam_file
	dc.b	'[3][ Can',$27,'t make destination folder. ][Abort]',0
	dc.b	$00
alert_cannot_find_file:	; from: unjam_file, add_to_jam
	dc.b	'[3][ Can',$27,'t find file. ][Abort]',0
	dc.b	$00
alert_jam_file_exists:	; from: write_jam
	dc.b	'[2][ Destination file already|exits.][Write Over|Abort]',0
alert_disk_read_error:	; from: unjam_file, extract_file, add_to_jam, disk_unpack, disk_pack, read_boot_sector
	dc.b	'[3][ Disk read error. ][Abort]',0
	dc.b	$00
	dc.b	'[3][ Disk Error. ][Abort]',0
alert_disk_write_error:	; from: extract_file, write_jam, add_to_jam, disk_unpack, disk_pack, write_dpk_header
	dc.b	'[3][ Disk write error. ][Abort]',0
jam_folder_path:	; from: jam_unjam, unjam_file, count_folder, write_jam
	dc.b	'\',0                           ; the folder to jam, or the jam file to unjam
	dcb.b	126,0
alert_folder_recreated:	; from: unjam_file
	dc.b	'[1][ Folder succesfully recreated. ][Ok]',0
	dc.b	$00
alert_folder_jammed:	; from: write_jam
	dc.b	'[1][ Folder successfully jammed. ][Ok]',0
	dc.b	$00
alert_cannot_jam_root:	; from: jam_unjam
	dc.b	'[3][ Cannot jam from ROOT directory. ][Abort]',0
jam_destination_path:	; from: jam_unjam, unjam_file, extract_file, write_jam
	dc.b	'\',0                           ; the jam file to write, or the folder to unjam into
	dcb.b	126,0
alert_cannot_create_file:	; from: extract_file, write_jam, disk_pack
	dc.b	'[3][ Can',$27,'t create file. ][Abort]',0
	dc.b	$00
jam_buffer:	; from: unjam_file, extract_file, write_jam, add_to_jam, jam_error
	dc.l	$00000000                       ; the buffer for the jam's files
alert_folder_exists:	; from: unjam_file
	dc.b	'[2][ Destination folder already|exists.][Continue|Abort]',0
	dc.b	$00
alert_insufficient_memory:	; from: unjam_file, write_jam, disk_unpack, disk_pack
	dc.b	'[3][ Insufficient Memory. ][Abort]',0
	dc.b	$00
text_supply_jam_folder:	; from: jam_unjam
	dc.b	'Supply the PATH of the folder to jam',0
	dc.b	$00
text_all_files_jam_folder:	; from: jam_unjam
	dc.b	'*.*',0
text_supply_jam_file:	; from: jam_unjam
	dc.b	'Supply the PATH of the jam file (',0
text_files:	; from: jam_unjam
	dc.b	' files, ',0
	dc.b	$00
text_bytes_total:	; from: jam_unjam
	dc.b	' bytes)',0
text_all_files_jam_file:	; from: jam_unjam
	dc.b	'*.*',0
text_jam_extension:	; from: jam_unjam
	dc.b	'JAM',0
text_supply_jam_source:	; from: jam_unjam
	dc.b	'Supply the PATHNAME of the source file',0
	dc.b	$00
text_all_files_unjam:	; from: jam_unjam
	dc.b	'*.*',0
text_jam_extension_unjam:	; from: jam_unjam
	dc.b	'JAM',0
text_supply_unjam_folder:	; from: jam_unjam
	dc.b	'Supply the PATH of the destination folder',0
text_backslash:	; from: unjam_file
	dc.b	'\',0
text_extracting:	; from: extract_file
	dc.b	'Extracting ',0
text_all_files_count:	; from: count_folder
	dc.b	'*.*',0
text_all_files_write:	; from: write_jam
	dc.b	'*.*',0
text_jamming:	; from: add_to_jam
	dc.b	'Jamming ',0
	dc.b	$00
text_dot:	; from: set_extension
	dc.b	'.',0
alert_unpack_which_drive:	; from: disk_unpack
	dc.b	'[2][ Unpack file to which drive? ][  A:  |  B:  ]',0
alert_pack_which_drive:	; from: disk_pack
	dc.b	'[2][ Pack disk in which drive? ][  A:  |  B:  ]',0
	dc.b	'[0][Press RETURN  ][Ok]',0
alert_format_error:	; from: disk_unpack
	dc.b	'[3][ Disk error while formatting.][Abort]',0
alert_cannot_read_fat:	; from: disk_pack
	dc.b	'[3][ Can',$27,'t read FAT ][Abort]',0
	dc.b	$00
dpk_path:	; from: disk_unpack, disk_pack
	dc.b	'\',0                           ; the DPK file's path
	dcb.b	126,0
text_root_unpack:	; from: disk_unpack
	dc.b	'\',0
text_dpk_mask_unpack:	; from: disk_unpack
	dc.b	'*.DPK',0
text_drivea_unpack:	; from: disk_unpack
	dc.b	'DRIVEA.DPK',0
	dc.b	$00
text_choose_input:	; from: disk_unpack
	dc.b	'Choose the input pathname',0
text_dpk_unpack:	; from: disk_unpack
	dc.b	'DPK',0
text_disk_unpack_progress:	; from: disk_unpack
	dc.b	'Disk Unpack Progress',0
	dc.b	$00
text_formatting:	; from: disk_unpack
	dc.b	'     -- Formatting --',0
text_reading_first:	; from: disk_unpack
	dc.b	'Reading',0
text_unpacking_first:	; from: disk_unpack
	dc.b	'Unpacking',0
text_writing_first:	; from: disk_unpack
	dc.b	'Writing Sectors',0
text_zero_to_unpack:	; from: disk_unpack
	dc.b	'0 to ',0
text_reading_chunk:	; from: disk_unpack
	dc.b	'Reading',0
text_unpacking_chunk:	; from: disk_unpack
	dc.b	'Unpacking',0
text_writing_chunk:	; from: disk_unpack
	dc.b	'Writing Sectors',0
text_to_unpack:	; from: disk_unpack
	dc.b	' to ',0
	dc.b	$00
text_root_pack:	; from: disk_pack
	dc.b	'\',0
text_dpk_mask_pack:	; from: disk_pack
	dc.b	'*.DPK',0
text_drivea_pack:	; from: disk_pack
	dc.b	'DRIVEA.DPK',0
	dc.b	$00
text_driveb_pack:	; from: disk_pack
	dc.b	'DRIVEB.DPK',0
	dc.b	$00
text_choose_destination:	; from: disk_pack
	dc.b	'Choose the destination pathname',0
text_dpk_pack:	; from: disk_pack
	dc.b	'DPK',0
text_zero_to_pack:	; from: disk_pack
	dc.b	'0 to ',0
text_reading_system:	; from: disk_pack
	dc.b	'Reading Sectors',0
text_disk_pack_progress:	; from: disk_pack
	dc.b	'Disk Pack Progress',0
	dc.b	$00
text_packing_system:	; from: disk_pack
	dc.b	'Packing Sectors',0
text_reading_chunk_pack:	; from: disk_pack
	dc.b	'Reading Sectors',0
text_to_pack:	; from: disk_pack
	dc.b	' to ',0
	dc.b	$00
text_packing_chunk:	; from: disk_pack
	dc.b	'Packing Sectors',0
resource_high:	; from: init_gem
	dc.w	$0000,$053e,$030e,$030e,$030e,$030e,$0024,$030e ; the resource for high resolution, as in a .RSC file
	dc.w	$030e,$0cee,$0052,$0005,$0014,$0000,$0000,$0000
	dc.w	$0000,$0d02
	dc.b	'PACKOMETER',0
	dc.b	$00
	dc.b	'50%',0
	dc.b	$00
	dc.b	'75%',0
	dc.b	$00
	dc.b	'25%',0
	dc.b	$00
	dc.b	'LZH',0
	dc.b	$56,$32,$00
	dc.b	'Algorithm',0
	dc.b	$00
	dc.b	'File Packer',0
	dc.b	$00
	dc.b	'Program',0
	dc.b	'Flash',0
	dc.b	'Heading',0
	dc.b	'PACK or UnPACK',0
	dc.b	'Multi Packer',0
	dc.b	$00
	dc.b	'PACK',0
	dc.b	'Programs',0
	dc.b	'Disk Packer',0
	dc.b	$00
	dc.b	'Format',0
	dc.b	'Use FAT',0
	dc.b	'UnPACK',0
	dc.b	'PACK',0
	dc.b	'The JAM Packer',0
	dc.b	$00
	dc.b	'Version 3.0',0
	dc.b	$00
	dc.b	'Pre-Release 1.1',0
	dc.b	$00
	dc.b	'JAM',0
	dc.b	'Jammer',0
	dc.b	$00
	dc.b	'UnJAM',0
	dc.b	'EXIT',0
	dc.b	$00
	dc.b	'Crunching File:',0
	dc.b	'Original Size:',0
	dc.b	'% of Original:',0
	dc.b	'Packed Size:',0
	dc.b	'Space Saved:',0
	dc.b	'Pack Info',0
	dc.b	$00,$4f,$4b,$00
	dc.b	'FILENAME.DAT',0
	dc.b	'9999999 Bytes    ',0
	dc.b	'9999999 Bytes    ',0
	dc.b	'1234567 Bytes',0
	dc.b	'99%',0
	dc.b	'The JAM Packer V3.0',0
	dc.b	$00
	dc.b	'Pre-Release 1.1',0
	dc.b	$00,$4f,$6b,$00
	dc.b	'Victoria, 3551',0
	dc.b	'AUSTRALIA',0
	dc.b	'Maiden Gully RSD',0
	dc.b	'A & T Knipe',0
	dc.b	'This program is SHAREWARE',0
	dc.b	$00
	dc.b	' cash to:',0
	dc.b	'Send bug reports, suggestions and',0
	dc.b	'(c) 1990,1991 by Andrew and Tim Knipe',0
	dc.b	$00
	dc.b	'Disk Pack Progress',0
	dc.b	$00
	dc.b	'9999',0
	dc.b	'Sectors Remaining:',0
	dc.b	'Packing Sectors.............',0
	dc.b	'XXXXXXXXXXXX',0
	dc.b	'Disk Info',0
	dc.b	$00,$39,$39,$00,$39,$39,$00
	dc.b	'Sides:',0
	dc.b	'SPT:',0
	dc.w	$3939,$0058
	dc.b	$00
	dc.b	'Drive:',0
	dc.b	'Tracks:',0
	dc.b	'9999',0
	dc.b	'Total Sectors:',0
	dc.w	$0000,$0024,$0000,$0000,$0000,$002f,$0003,$0006
	dc.w	$0002,$1071,$0000,$00ff,$000b,$0001,$0000,$0030
	dc.w	$0000,$0000,$0000,$0034,$0003,$0006,$0000,$1100
	dc.w	$0000,$00ff,$0004,$0001,$0000,$0035,$0000,$0000
	dc.w	$0000,$0039,$0003,$0006,$0000,$1100,$0000,$00ff
	dc.w	$0004,$0001,$0000,$003a,$0000,$0000,$0000,$003e
	dc.w	$0003,$0006,$0000,$1100,$0000,$00ff,$0004,$0001
	dc.w	$0000,$0046,$0000,$0000,$0000,$0050,$0003,$0006
	dc.w	$0002,$1071,$0000,$00ff,$000a,$0001,$0000,$0051
	dc.w	$0000,$0000,$0000,$005d,$0003,$0006,$0002,$1071
	dc.w	$0000,$00ff,$000c,$0001,$0000,$0083,$0000,$0000
	dc.w	$0000,$0090,$0003,$0006,$0002,$1071,$0000,$00ff
	dc.w	$000d,$0001,$0000,$009f,$0000,$0000,$0000,$00ab
	dc.w	$0003,$0006,$0002,$1071,$0000,$00ff,$000c,$0001
	dc.w	$0000,$00c7,$0000,$0000,$0000,$00d6,$0003,$0006
	dc.w	$0002,$1071,$0000,$00ff,$000f,$0001,$0000,$00d7
	dc.w	$0000,$0000,$0000,$00e3,$0003,$0006,$0002,$1071
	dc.w	$0000,$00ff,$000c,$0001,$0000,$00e4,$0000,$0000
	dc.w	$0000,$00f4,$0005,$0006,$0002,$1000,$0000,$00ff
	dc.w	$0010,$0001,$0000,$00f9,$0000,$0000,$0000,$0100
	dc.w	$0003,$0006,$0002,$1071,$0000,$00ff,$0007,$0001
	dc.w	$0000,$0107,$0000,$0000,$0000,$010c,$0003,$0006
	dc.w	$0002,$1170,$0000,$00ff,$0005,$0001,$0000,$0155
	dc.w	$0000,$0000,$0000,$015f,$0003,$0006,$0002,$1073
	dc.w	$0000,$00ff,$000a,$0001,$0000,$01a6,$0000,$0000
	dc.w	$0000,$01ba,$0003,$0006,$0002,$1073,$0000,$0000
	dc.w	$0014,$0001,$0000,$01bb,$0000,$0000,$0000,$01cb
	dc.w	$0005,$0006,$0002,$1000,$0000,$00ff,$0010,$0001
	dc.w	$0000,$0205,$0000,$0000,$0000,$021f,$0003,$0006
	dc.w	$0000,$1180,$0000,$00ff,$001a,$0001,$0000,$024c
	dc.w	$0000,$0000,$0000,$0272,$0003,$0006,$0000,$1180
	dc.w	$0000,$00ff,$0026,$0001,$0000,$0273,$0000,$0000
	dc.w	$0000,$0286,$0003,$0006,$0002,$1071,$0000,$00ff
	dc.w	$0013,$0001,$0000,$02c9,$0000,$0000,$0000,$02d3
	dc.w	$0003,$0006,$0002,$1071,$0000,$00ff,$000a,$0001
	dc.w	$ffff,$0001,$0002,$0014,$0000,$0010,$0002,$1122
	dc.w	$0000,$0000,$0012,$0016,$0002,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$030e,$0002,$0001,$000e,$0001
	dc.w	$0000,$0003,$0005,$0014,$0000,$0000,$0001,$1143
	dc.w	$0706,$0003,$0104,$0012,$0004,$ffff,$ffff,$0015
	dc.w	$0000,$0000,$0000,$032a,$0500,$0608,$0003,$0001
	dc.w	$0005,$ffff,$ffff,$0015,$0000,$0000,$0000,$0346
	dc.w	$0500,$0d03,$0003,$0001,$0002,$ffff,$ffff,$0015
	dc.w	$0020,$0000,$0000,$0362,$0500,$000d,$0003,$0001
	dc.w	$ffff,$0001,$001c,$0014,$0000,$0000,$0002,$1111
	dc.w	$0000,$0000,$0042,$0011,$0005,$0002,$0004,$0014
	dc.w	$0000,$0020,$00ff,$1151,$0002,$0001,$0014,$0005
	dc.w	$0003,$ffff,$ffff,$001a,$0011,$0000,$0000,$003f
	dc.w	$0002,$0003,$0007,$0001,$0004,$ffff,$ffff,$001a
	dc.w	$0011,$0000,$0000,$0043,$000b,$0003,$0007,$0001
	dc.w	$0001,$ffff,$ffff,$0016,$0000,$0030,$0000,$037e
	dc.w	$0002,$0001,$0010,$0001,$000b,$0006,$000a,$0014
	dc.w	$0000,$0020,$00ff,$1141,$0002,$0007,$0014,$0009
	dc.w	$0007,$ffff,$ffff,$0016,$0000,$0030,$0000,$039a
	dc.w	$0002,$0001,$0010,$0001,$0008,$ffff,$ffff,$001a
	dc.w	$0040,$0000,$0000,$005e,$0002,$0003,$0008,$0001
	dc.w	$0009,$ffff,$ffff,$001a,$0001,$0000,$0000,$0066
	dc.w	$000b,$0003,$0007,$0001,$000a,$ffff,$ffff,$001a
	dc.w	$0001,$0000,$0000,$006c,$0002,$0005,$0010,$0001
	dc.w	$0005,$ffff,$ffff,$001a,$0005,$0000,$0000,$0074
	dc.w	$0002,$0007,$0010,$0001,$000f,$000c,$000e,$0014
	dc.w	$0000,$0020,$0001,$1132,$0018,$0001,$0013,$0007
	dc.w	$000d,$ffff,$ffff,$0016,$0000,$0030,$0000,$03b6
	dc.w	$0002,$0001,$000f,$0001,$000e,$ffff,$ffff,$001a
	dc.w	$0005,$0000,$0000,$0091,$0002,$0005,$000f,$0001
	dc.w	$000b,$ffff,$ffff,$001a,$0001,$0000,$0000,$0096
	dc.w	$0002,$0003,$000f,$0001,$0015,$0010,$0014,$0014
	dc.w	$0000,$0020,$00ff,$1121,$0018,$0009,$0013,$0007
	dc.w	$0011,$ffff,$ffff,$0016,$0000,$0030,$0000,$03d2
	dc.w	$0002,$0001,$000f,$0001,$0012,$ffff,$ffff,$001a
	dc.w	$0001,$0000,$0000,$00ac,$000a,$0003,$0007,$0001
	dc.w	$0013,$ffff,$ffff,$001a,$0001,$0000,$0000,$00b3
	dc.w	$0002,$0003,$0007,$0001,$0014,$ffff,$ffff,$001a
	dc.w	$0005,$0000,$0000,$00bb,$000a,$0005,$0007,$0001
	dc.w	$000f,$ffff,$ffff,$001a,$0005,$0000,$0000,$00c2
	dc.w	$0002,$0005,$0007,$0001,$001a,$0017,$0018,$0014
	dc.w	$0040,$0030,$00ff,$1171,$002d,$0001,$0013,$0c04
	dc.w	$0018,$ffff,$ffff,$0015,$0040,$0000,$0000,$040a
	dc.w	$0001,$0702,$0011,$0001,$0016,$ffff,$ffff,$0015
	dc.w	$0040,$0000,$0000,$03ee,$0001,$0301,$0011,$0001
	dc.w	$0015,$ffff,$ffff,$0015,$0000,$0000,$0000,$0426
	dc.w	$0000,$0503,$0013,$0001,$001d,$ffff,$ffff,$001a
	dc.w	$0005,$0000,$0000,$00f5,$0002,$0003,$0007,$0001
	dc.w	$001c,$0019,$001b,$0014,$0000,$0020,$00ff,$1161
	dc.w	$002d,$0007,$0013,$0005,$001a,$ffff,$ffff,$001a
	dc.w	$0005,$0000,$0000,$0101,$000a,$0003,$0007,$0001
	dc.w	$0000,$ffff,$ffff,$0016,$0025,$0000,$0000,$045e
	dc.w	$002e,$000d,$0011,$0003,$001b,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$0442,$0002,$0001,$000f,$0001
	dc.w	$ffff,$0001,$000c,$0014,$0000,$0010,$0002,$1170
	dc.w	$0000,$0000,$0024,$0010,$0002,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$010d,$0003,$0005,$000f,$0001
	dc.w	$0003,$ffff,$ffff,$001c,$0000,$0000,$0000,$011d
	dc.w	$0004,$0007,$000e,$0001,$0004,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$012c,$0004,$000b,$000e,$0001
	dc.w	$0005,$ffff,$ffff,$001c,$0000,$0000,$0000,$013b
	dc.w	$0006,$0008,$000c,$0001,$0006,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0148,$0006,$000a,$000c,$0001
	dc.w	$0007,$ffff,$ffff,$0016,$0000,$0030,$0000,$047a
	dc.w	$0007,$0001,$0016,$0002,$0008,$ffff,$ffff,$001a
	dc.w	$0007,$0000,$0000,$0160,$000a,$050d,$0010,$0001
	dc.w	$0009,$ffff,$ffff,$001c,$0000,$0000,$0000,$0163
	dc.w	$0013,$0005,$000d,$0001,$000a,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0170,$0013,$0007,$0011,$0001
	dc.w	$000b,$ffff,$ffff,$001c,$0000,$0000,$0000,$0182
	dc.w	$0013,$0008,$0011,$0001,$000c,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0194,$0013,$000a,$0011,$0001
	dc.w	$0000,$ffff,$ffff,$001c,$0020,$0000,$0000,$01a2
	dc.w	$0013,$000b,$0006,$0001,$ffff,$0001,$0004,$0014
	dc.w	$0000,$0010,$0002,$1121,$0000,$0000,$003d,$0013
	dc.w	$0002,$0003,$0003,$0016,$0000,$0030,$0000,$0496
	dc.w	$000b,$0c00,$0027,$0403,$0004,$ffff,$ffff,$001a
	dc.w	$0007,$0000,$0000,$01cc,$0012,$0311,$001c,$0001
	dc.w	$0001,$ffff,$ffff,$0015,$0000,$0000,$0000,$04b2
	dc.w	$000a,$0402,$0013,$0001,$0000,$0005,$000c,$0014
	dc.w	$0000,$0020,$0003,$1100,$0006,$0005,$0031,$000b
	dc.w	$0006,$ffff,$ffff,$001c,$0000,$0000,$0000,$01cf
	dc.w	$0010,$0d07,$0012,$0001,$0007,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$01de,$0010,$0d08,$0009,$0001
	dc.w	$0008,$ffff,$ffff,$001c,$0000,$0000,$0000,$01e8
	dc.w	$0010,$0e06,$0010,$0001,$0009,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$01f9,$0010,$0e05,$000b,$0001
	dc.w	$000a,$ffff,$ffff,$0015,$0000,$0000,$0000,$04ce
	dc.w	$040c,$0102,$0019,$0001,$000b,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0220,$0025,$0004,$0009,$0001
	dc.w	$000c,$ffff,$ffff,$001c,$0000,$0000,$0000,$022a
	dc.w	$0004,$0004,$0023,$0001,$0004,$ffff,$ffff,$0015
	dc.w	$0020,$0000,$0000,$04ea,$0006,$0c00,$0025,$0001
	dc.w	$ffff,$0001,$0011,$0014,$0000,$0010,$0002,$1121
	dc.w	$0000,$0000,$0021,$000e,$0002,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$0506,$0002,$0001,$001d,$0002
	dc.w	$0007,$0003,$0006,$0014,$0000,$0020,$00ff,$1100
	dc.w	$0002,$0004,$001d,$0102,$0004,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0287,$0016,$0000,$0004,$0001
	dc.w	$0005,$ffff,$ffff,$001c,$0000,$0000,$0000,$028c
	dc.w	$0003,$0000,$0012,$0001,$0006,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$029f,$0001,$0001,$001c,$0001
	dc.w	$0002,$ffff,$ffff,$001c,$0000,$0000,$0000,$02bc
	dc.w	$0011,$0001,$000c,$0001,$0008,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$0522,$0002,$0007,$001d,$0001
	dc.w	$0011,$0009,$0010,$0014,$0000,$0020,$00ff,$1101
	dc.w	$0002,$0009,$001d,$0002,$000a,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$02d4,$0017,$0000,$0002,$0001
	dc.w	$000b,$ffff,$ffff,$001c,$0000,$0000,$0000,$02d7
	dc.w	$0017,$0001,$0002,$0001,$000c,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$02da,$0010,$0000,$0006,$0001
	dc.w	$000d,$ffff,$ffff,$001c,$0000,$0000,$0000,$02e1
	dc.w	$0012,$0001,$0004,$0001,$000e,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$02e6,$000c,$0001,$0002,$0001
	dc.w	$000f,$ffff,$ffff,$001c,$0000,$0000,$0000,$02e9
	dc.w	$000c,$0000,$0001,$0001,$0010,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$02eb,$0005,$0000,$0006,$0001
	dc.w	$0008,$ffff,$ffff,$001c,$0000,$0000,$0000,$02f2
	dc.w	$0004,$0001,$0007,$0001,$0000,$0012,$0013,$0014
	dc.w	$0000,$0020,$00ff,$1101,$0002,$000c,$001d,$0001
	dc.w	$0013,$ffff,$ffff,$001c,$0000,$0000,$0000,$02fa
	dc.w	$0014,$0000,$0004,$0001,$0011,$ffff,$ffff,$001c
	dc.w	$0020,$0000,$0000,$02ff,$0005,$0000,$000e,$0001
	dc.w	$0000,$0b0e,$0000,$089e,$0000,$05ce,$0000,$053e
	dc.w	$0000,$09d6
resource_medium:	; from: init_gem
	dc.w	$0000,$053e,$030e,$030e,$030e,$030e,$0024,$030e ; the resource for medium resolution
	dc.w	$030e,$0cee,$0052,$0005,$0014,$0000,$0000,$0000
	dc.w	$0000,$0d02
	dc.b	'LZH',0
	dc.w	$5632
	dc.b	$00
	dc.b	'Algorithm',0
	dc.b	$00
	dc.b	'File Packer',0
	dc.b	$00
	dc.b	'Program',0
	dc.b	'Flash',0
	dc.b	'Heading',0
	dc.b	'PACK or UnPACK',0
	dc.b	'Multi Packer',0
	dc.b	$00
	dc.b	'PACK',0
	dc.b	'Programs',0
	dc.b	'Disk Packer',0
	dc.b	$00
	dc.b	'Format',0
	dc.b	'Use FAT',0
	dc.b	'UnPACK',0
	dc.b	'PACK',0
	dc.b	'The JAM Packer',0
	dc.b	$00
	dc.b	'Version 3.0',0
	dc.b	$00
	dc.b	'Pre-Release 1.1',0
	dc.b	$00
	dc.b	'EXIT',0
	dc.b	$00
	dc.b	'JAM',0
	dc.b	'Jammer',0
	dc.b	$00
	dc.b	'UnJAM',0
	dc.b	'Disk Pack Progress',0
	dc.b	$00
	dc.b	'9999',0
	dc.b	'Sectors Remaining:',0
	dc.b	'Packing Sectors.............',0
	dc.b	'XXXXXXXXXXXX',0
	dc.b	'Disk Info',0
	dc.w	$0039,$3900,$3939
	dc.b	$00
	dc.b	'Sides:',0
	dc.b	'SPT:',0
	dc.b	$39,$39,$00,$58,$00
	dc.b	'Drive:',0
	dc.b	'Tracks:',0
	dc.b	'9999',0
	dc.b	'Total Sectors:',0
	dc.b	'The JAM Packer V3.0',0
	dc.b	$00,$4f,$6b,$00
	dc.b	'This program is SHAREWARE',0
	dc.b	$00
	dc.b	' cash to:',0
	dc.b	'Send bug reports, suggestions and',0
	dc.b	'(c) 1990,1991 by Andrew and Tim Knipe',0
	dc.b	$00
	dc.b	'A & T Knipe',0
	dc.b	'Maiden Gully RSD',0
	dc.b	'Victoria, 3551',0
	dc.b	'AUSTRALIA',0
	dc.b	'Pre-Release 1.1',0
	dc.b	$00
	dc.b	'PACKOMETER',0
	dc.b	$00
	dc.b	'50%',0
	dc.b	$00
	dc.b	'75%',0
	dc.b	$00
	dc.b	'25%',0
	dc.b	$00
	dc.b	'Crunching File:',0
	dc.b	'Original Size:',0
	dc.b	'% of Original:',0
	dc.b	'Packed Size:',0
	dc.b	'Space Saved:',0
	dc.b	'Pack Info',0
	dc.b	$00,$4f,$4b,$00
	dc.b	'FILENAME.DAT',0
	dc.b	'9999999 Bytes    ',0
	dc.b	'9999999 Bytes    ',0
	dc.b	'1234567 Bytes',0
	dc.b	'99%',0
	dc.w	$0000,$002b,$0000,$0000,$0000,$0035,$0003,$0006
	dc.w	$0002,$1071,$0000,$00ff,$000a,$0001,$0000,$0036
	dc.w	$0000,$0000,$0000,$0042,$0003,$0006,$0002,$1071
	dc.w	$0000,$00ff,$000c,$0001,$0000,$0068,$0000,$0000
	dc.w	$0000,$0075,$0003,$0006,$0002,$1071,$0000,$00ff
	dc.w	$000d,$0001,$0000,$0084,$0000,$0000,$0000,$0090
	dc.w	$0003,$0006,$0002,$1071,$0000,$00ff,$000c,$0001
	dc.w	$0000,$00ac,$0000,$0000,$0000,$00bb,$0003,$0006
	dc.w	$0002,$1071,$0000,$00ff,$000f,$0001,$0000,$00bc
	dc.w	$0000,$0000,$0000,$00c8,$0003,$0006,$0002,$1071
	dc.w	$0000,$00ff,$000c,$0001,$0000,$00c9,$0000,$0000
	dc.w	$0000,$00d9,$0005,$0006,$0002,$1000,$0000,$00ff
	dc.w	$0010,$0001,$0000,$00da,$0000,$0000,$0000,$00df
	dc.w	$0003,$0006,$0002,$1170,$0000,$00ff,$0005,$0001
	dc.w	$0000,$00e4,$0000,$0000,$0000,$00eb,$0003,$0006
	dc.w	$0002,$1071,$0000,$00ff,$0007,$0001,$0000,$00f2
	dc.w	$0000,$0000,$0000,$0105,$0003,$0006,$0002,$1071
	dc.w	$0000,$00ff,$0013,$0001,$0000,$0148,$0000,$0000
	dc.w	$0000,$0152,$0003,$0006,$0002,$1071,$0000,$00ff
	dc.w	$000a,$0001,$0000,$018d,$0000,$0000,$0000,$01a1
	dc.w	$0003,$0006,$0002,$1071,$0000,$0000,$0014,$0001
	dc.w	$0000,$01a5,$0000,$0000,$0000,$01bf,$0003,$0006
	dc.w	$0000,$1180,$0000,$00ff,$001a,$0001,$0000,$01ec
	dc.w	$0000,$0000,$0000,$0212,$0003,$0006,$0000,$1180
	dc.w	$0000,$00ff,$0026,$0001,$0000,$0249,$0000,$0000
	dc.w	$0000,$0259,$0005,$0006,$0002,$1000,$0000,$00ff
	dc.w	$0010,$0001,$0000,$025a,$0000,$0000,$0000,$0265
	dc.w	$0003,$0006,$0002,$1071,$0000,$00ff,$000b,$0001
	dc.w	$0000,$0266,$0000,$0000,$0000,$026a,$0003,$0006
	dc.w	$0000,$1100,$0000,$00ff,$0004,$0001,$0000,$026b
	dc.w	$0000,$0000,$0000,$026f,$0003,$0006,$0000,$1100
	dc.w	$0000,$00ff,$0004,$0001,$0000,$0270,$0000,$0000
	dc.w	$0000,$0274,$0003,$0006,$0000,$1100,$0000,$00ff
	dc.w	$0004,$0001,$0000,$02bd,$0000,$0000,$0000,$02c7
	dc.w	$0003,$0006,$0002,$1071,$0000,$00ff,$000a,$0001
	dc.w	$ffff,$0001,$001a,$0014,$0000,$0000,$0002,$1131
	dc.w	$0000,$0000,$0042,$0011,$0005,$0002,$0004,$0014
	dc.w	$0000,$0020,$00ff,$1173,$0002,$0001,$0014,$0005
	dc.w	$0003,$ffff,$ffff,$001a,$0011,$0000,$0000,$0024
	dc.w	$0002,$0003,$0007,$0001,$0004,$ffff,$ffff,$001a
	dc.w	$0011,$0000,$0000,$0028,$000b,$0003,$0007,$0001
	dc.w	$0001,$ffff,$ffff,$0016,$0000,$0030,$0000,$030e
	dc.w	$0002,$0001,$0010,$0001,$000b,$0006,$000a,$0014
	dc.w	$0000,$0020,$00ff,$1172,$0002,$0007,$0014,$0009
	dc.w	$0007,$ffff,$ffff,$0016,$0000,$0030,$0000,$032a
	dc.w	$0002,$0001,$0010,$0001,$0008,$ffff,$ffff,$001a
	dc.w	$0040,$0000,$0000,$0043,$0002,$0003,$0008,$0001
	dc.w	$0009,$ffff,$ffff,$001a,$0001,$0000,$0000,$004b
	dc.w	$000b,$0003,$0007,$0001,$000a,$ffff,$ffff,$001a
	dc.w	$0001,$0000,$0000,$0051,$0002,$0005,$0010,$0001
	dc.w	$0005,$ffff,$ffff,$001a,$0005,$0000,$0000,$0059
	dc.w	$0002,$0007,$0010,$0001,$000f,$000c,$000e,$0014
	dc.w	$0000,$0020,$0001,$1142,$0018,$0001,$0013,$0007
	dc.w	$000d,$ffff,$ffff,$0016,$0000,$0030,$0000,$0346
	dc.w	$0002,$0001,$000f,$0001,$000e,$ffff,$ffff,$001a
	dc.w	$0005,$0000,$0000,$0076,$0002,$0005,$000f,$0001
	dc.w	$000b,$ffff,$ffff,$001a,$0001,$0000,$0000,$007b
	dc.w	$0002,$0003,$000f,$0001,$0015,$0010,$0014,$0014
	dc.w	$0000,$0020,$00ff,$1141,$0018,$0009,$0013,$0007
	dc.w	$0011,$ffff,$ffff,$0016,$0000,$0030,$0000,$0362
	dc.w	$0002,$0001,$000f,$0001,$0012,$ffff,$ffff,$001a
	dc.w	$0001,$0000,$0000,$0091,$000a,$0003,$0007,$0001
	dc.w	$0013,$ffff,$ffff,$001a,$0001,$0000,$0000,$0098
	dc.w	$0002,$0003,$0007,$0001,$0014,$ffff,$ffff,$001a
	dc.w	$0005,$0000,$0000,$00a0,$000a,$0005,$0007,$0001
	dc.w	$000f,$ffff,$ffff,$001a,$0005,$0000,$0000,$00a7
	dc.w	$0002,$0005,$0007,$0001,$001c,$0017,$0018,$0014
	dc.w	$0040,$0030,$00ff,$1171,$002d,$0001,$0013,$0704
	dc.w	$0018,$ffff,$ffff,$0015,$0040,$0000,$0000,$039a
	dc.w	$0001,$0202,$0011,$0001,$0016,$ffff,$ffff,$0015
	dc.w	$0040,$0000,$0000,$037e,$0001,$0600,$0011,$0001
	dc.w	$0015,$ffff,$ffff,$0015,$0000,$0000,$0000,$03b6
	dc.w	$0000,$0303,$0013,$0001,$001d,$ffff,$ffff,$001a
	dc.w	$0005,$0000,$0000,$00e0,$0002,$0003,$0007,$0001
	dc.w	$0000,$0019,$001b,$0014,$0000,$0020,$00ff,$1143
	dc.w	$002d,$0706,$0013,$0005,$001a,$ffff,$ffff,$001a
	dc.w	$0025,$0000,$0000,$00ec,$000a,$0003,$0007,$0001
	dc.w	$001a,$ffff,$ffff,$0016,$0005,$0000,$0000,$03d2
	dc.w	$002e,$000d,$0011,$0003,$001b,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$03ee,$0002,$0001,$000f,$0001
	dc.w	$ffff,$0001,$0011,$0014,$0000,$0010,$0002,$1133
	dc.w	$0000,$0000,$0021,$000e,$0002,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$040a,$0002,$0001,$001d,$0002
	dc.w	$0007,$0003,$0006,$0014,$0000,$0020,$00ff,$1100
	dc.w	$0002,$0004,$001d,$0102,$0004,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0106,$0016,$0000,$0004,$0001
	dc.w	$0005,$ffff,$ffff,$001c,$0000,$0000,$0000,$010b
	dc.w	$0003,$0000,$0012,$0001,$0006,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$011e,$0001,$0001,$001c,$0001
	dc.w	$0002,$ffff,$ffff,$001c,$0000,$0000,$0000,$013b
	dc.w	$0011,$0001,$000c,$0001,$0008,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$0426,$0002,$0007,$001d,$0001
	dc.w	$0011,$0009,$0010,$0014,$0000,$0020,$00ff,$1101
	dc.w	$0002,$0009,$001d,$0002,$000a,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0153,$0017,$0000,$0002,$0001
	dc.w	$000b,$ffff,$ffff,$001c,$0000,$0000,$0000,$0156
	dc.w	$0017,$0001,$0002,$0001,$000c,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0159,$0010,$0000,$0006,$0001
	dc.w	$000d,$ffff,$ffff,$001c,$0000,$0000,$0000,$0160
	dc.w	$0012,$0001,$0004,$0001,$000e,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0165,$000c,$0001,$0002,$0001
	dc.w	$000f,$ffff,$ffff,$001c,$0000,$0000,$0000,$0168
	dc.w	$000c,$0000,$0001,$0001,$0010,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$016a,$0005,$0000,$0006,$0001
	dc.w	$0008,$ffff,$ffff,$001c,$0000,$0000,$0000,$0171
	dc.w	$0004,$0001,$0007,$0001,$0000,$0012,$0013,$0014
	dc.w	$0000,$0020,$00ff,$1101,$0002,$000c,$001d,$0001
	dc.w	$0013,$ffff,$ffff,$001c,$0000,$0000,$0000,$0179
	dc.w	$0014,$0000,$0004,$0001,$0011,$ffff,$ffff,$001c
	dc.w	$0020,$0000,$0000,$017e,$0005,$0000,$000e,$0001
	dc.w	$ffff,$0001,$000c,$0014,$0000,$0010,$0002,$1152
	dc.w	$0000,$0000,$003d,$0014,$0002,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$0442,$000b,$0401,$0027,$0702
	dc.w	$0003,$ffff,$ffff,$001a,$0007,$0000,$0000,$01a2
	dc.w	$0012,$0611,$001c,$0001,$000c,$0004,$000b,$0014
	dc.w	$0000,$0020,$0002,$1100,$0006,$0305,$0031,$000b
	dc.w	$0005,$ffff,$ffff,$0015,$0000,$0000,$0000,$045e
	dc.w	$040c,$0102,$0019,$0001,$0006,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$01c0,$0025,$0004,$0009,$0001
	dc.w	$0007,$ffff,$ffff,$001c,$0000,$0000,$0000,$01ca
	dc.w	$0004,$0004,$0023,$0001,$0008,$ffff,$ffff,$0015
	dc.w	$0000,$0000,$0000,$047a,$0006,$0700,$0025,$0001
	dc.w	$0009,$ffff,$ffff,$001c,$0000,$0000,$0000,$0213
	dc.w	$0010,$0705,$000b,$0001,$000a,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$021f,$0010,$0706,$0010,$0001
	dc.w	$000b,$ffff,$ffff,$001c,$0000,$0000,$0000,$0230
	dc.w	$0010,$0707,$0012,$0001,$0003,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$023f,$0010,$0708,$0009,$0001
	dc.w	$0000,$ffff,$ffff,$0015,$0020,$0000,$0000,$0496
	dc.w	$0315,$0303,$0512,$0001,$ffff,$0001,$0002,$0014
	dc.w	$0000,$0010,$0002,$1122,$0000,$0000,$0012,$0016
	dc.w	$0002,$ffff,$ffff,$0016,$0000,$0030,$0000,$04b2
	dc.w	$0002,$0001,$000e,$0001,$0000,$0003,$0005,$0014
	dc.w	$0000,$0000,$0001,$1143,$0706,$0003,$0104,$0012
	dc.w	$0004,$ffff,$ffff,$0015,$0000,$0000,$0000,$04ce
	dc.w	$0500,$0608,$0003,$0001,$0005,$ffff,$ffff,$0015
	dc.w	$0000,$0000,$0000,$04ea,$0500,$0504,$0003,$0001
	dc.w	$0002,$ffff,$ffff,$0015,$0020,$0000,$0000,$0506
	dc.w	$0500,$000d,$0003,$0001,$ffff,$0001,$000c,$0014
	dc.w	$0000,$0010,$0002,$1103,$0000,$0000,$0024,$0010
	dc.w	$0002,$ffff,$ffff,$001c,$0000,$0000,$0000,$0275
	dc.w	$0003,$0005,$000f,$0001,$0003,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$0285,$0004,$0007,$000e,$0001
	dc.w	$0004,$ffff,$ffff,$001c,$0000,$0000,$0000,$0294
	dc.w	$0004,$000b,$000e,$0001,$0005,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$02a3,$0006,$0008,$000c,$0001
	dc.w	$0006,$ffff,$ffff,$001c,$0000,$0000,$0000,$02b0
	dc.w	$0006,$000a,$000c,$0001,$0007,$ffff,$ffff,$0016
	dc.w	$0000,$0030,$0000,$0522,$0007,$0001,$0015,$0002
	dc.w	$0008,$ffff,$ffff,$001a,$0007,$0000,$0000,$02c8
	dc.w	$000a,$050d,$0010,$0001,$0009,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$02cb,$0013,$0005,$000d,$0001
	dc.w	$000a,$ffff,$ffff,$001c,$0000,$0000,$0000,$02d8
	dc.w	$0013,$0007,$0011,$0001,$000b,$ffff,$ffff,$001c
	dc.w	$0000,$0000,$0000,$02ea,$0013,$0008,$0011,$0001
	dc.w	$000c,$ffff,$ffff,$001c,$0000,$0000,$0000,$02fc
	dc.w	$0013,$000a,$0011,$0001,$0000,$ffff,$ffff,$001c
	dc.w	$0020,$0000,$0000,$030a,$0013,$000b,$0006,$0001
	dc.w	$0000,$080e,$0000,$0bb6,$0000,$053e,$0000,$0b26
	dc.w	$0000,$09ee
p_len:	; from: encode_position
	dc.w	$0304,$0404,$0505,$0505,$0505,$0505,$0606,$0606 ; LZH: the code lengths for the upper 6 bits of a
                                                ;   position
	dc.w	$0606,$0606,$0606,$0606,$0707,$0707,$0707,$0707
	dcb.w	8,$0707
	dcb.w	8,$0808
lzh_putbuf:	; from: putcode, start_huff, encode_end
	dc.w	$0000                           ; LZH: the bits waiting to be written
lzh_putlen:	; from: putcode, start_huff, encode_end
	dc.w	$0000                           ; and how many
p_code:	; from: encode_position
	dc.b	$00                             ; LZH: the codes for the upper 6 bits of a position
	dc.b	' 0@PX`hpx'
	dc.w	$8088,$9094,$989c,$a0a4,$a8ac,$b0b4,$b8bc,$c0c2
	dc.w	$c4c6,$c8ca,$ccce,$d0d2,$d4d6,$d8da,$dcde,$e0e2
	dc.w	$e4e6,$e8ea,$ecee,$f0f1,$f2f3,$f4f5,$f6f7,$f8f9
	dc.w	$fafb,$fcfd,$feff
lzh_getbuf:	; from: start_huff
	dc.w	$0000
lzh_getlen:	; from: start_huff
	dc.w	$0000
stack_size:	; from: start
	dc.l	$00002000                       ; the stack size (for a desk accessory)
atexit_next:	; from: atexit, exit
	dc.l	atexit_table                    ; the next free entry of atexit_table
iob:	; from: multi_pack, exit, getbuf
	dc.w	$0000,$0000,$0000,$0000,$0000,$0209,$0000,$0000 ; the 20 streams, 16 bytes each: stdin, stdout,
                                                ;   stderr...
	dc.w	$0000,$0000,$0000,$0000,$0000,$0102,$0001,$0200
	dc.w	$0000,$0000,$0000,$0000,$0000,$0102,$0001,$0200
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	256,0
bufsiz:	; from: getbuf
	dc.w	$0200                           ; the size of a stream's buffer
malloc_free_list:	; from: morecore, malloc, free
	dc.l	$00000000                       ; malloc's free list
text_con:	; from: open
	dc.b	'CON:',0
	dc.b	$00
text_aux:	; from: open
	dc.b	'AUX:',0
	dc.b	$00
text_prt:	; from: open
	dc.b	'PRT:',0
	dc.b	$00
console_line_pos:	; from: console_getc
	dc.w	$0000
console_line_len:	; from: console_getc
	dc.w	$0000
last_vdi_handle:	; from: v_opnvwk
	dc.w	$ffff,$0000                     ; the workstation v_opnvwk opened last

	section	bss
startup_stack:	ds.b	100                     ; a desk accessory's stack at the start
dial_box_h:	ds.b	2                       ; the box form_dial(FMD_GROW) kept
dial_box_w:	ds.b	2
dial_box_x:	ds.b	2
dial_box_y:	ds.b	2
atexit_table:	ds.b	32                      ; up to 8 functions
malloc_base:	ds.b	8                       ; malloc's empty list head: pointer and size
console_line:	ds.b	80                      ; the line console_getc reads
stream_bytes:	ds.b	20                      ; one byte buffers for the unbuffered streams
disk_tracks:	ds.b	2                       ; the tracks of the disk
vdi_contrl:	ds.b	24                      ; the VDI arrays: contrl
lzh_source_index:	ds.b	4               ; the next source byte to read, from the end down
flash_flag:	ds.b	2                       ; Flash
argv:	ds.b	4
prnt:	ds.b	1882                            ; LZH: each node's parent
tree_info:	ds.b	4                       ; the pack info box
info_rect:	ds.b	8
screen_height:	ds.b	2
aes_intin:	ds.b	34
report_count:	ds.b	10                      ; the files noted for the multi packer's report
errno:	ds.b	2
tree_disk:	ds.b	4                       ; the disk progress box
disk_rect:	ds.b	8
rson:	ds.b	16386                           ; LZH: right children, and the 256 tree roots past N
jam_name:	ds.b	16                      ; the name in the file selector for JAM
dpk_name:	ds.b	16                      ; the name in the file selector for the disk packer
use_fat_flag:	ds.b	2                       ; Use FAT
bar_offset:	ds.b	2                       ; the packometer bar's distance from the bottom of the screen
codesize:	ds.b	4                       ; LZH: the code written so far
text_buf:	ds.b	4156                    ; LZH: the 4 K window and 59 bytes more
multi_programs:	ds.b	2                       ; Programs (the multi packer packs programs)
envp:	ds.b	4
match_position:	ds.b	2
freq:	ds.b	1256                            ; LZH: each node's frequency
jam_file_count:	ds.b	2
dir_entries:	ds.b	2                       ; the disk's root directory entries
dad:	ds.b	8194                            ; LZH: each node's parent in the string tree
ap_id:	ds.b	2
jam_largest:	ds.b	4                       ; the largest file of the jam
report_names:	ds.b	2000                    ; the files noted, 20 bytes each
vdi_ptsin:	ds.b	256
aes_pb_ptr:	ds.b	4                       ; the AES parameter block aes uses
vdi_pb:	ds.b	20                              ; the VDI parameter block: contrl, intin, ptsin, intout, ptsout
screen_buffer:	ds.b	4                       ; 32000 bytes for the saved screen
reserved_sectors:	ds.b	2
lzh_source:	ds.b	4
file_name:	ds.b	128                     ; the file chosen
bar_column:	ds.b	2                       ; the packometer bar's column
report_reasons:	ds.b	200                     ; the reason for each file noted
trap_save_index:	ds.b	6               ; the next slot of trap_save_stack, in bytes
lzh_output:	ds.b	4                       ; where the next code byte goes, downwards
packometer_rect:	ds.b	8
system_sectors:	ds.b	2                       ; the sectors before the disk's data
fat_sectors:	ds.b	2
match_length:	ds.b	2
same:	ds.b	4106                            ; LZH: how far each node matches its parent
cluster_sectors:	ds.b	2
aes_addrout:	ds.b	8
vdi_handle:	ds.b	2
son:	ds.b	1254                            ; LZH: each node's children
dummy:	ds.b	2                               ; the results nobody looks at
bar_step:	ds.b	4                       ; bytes for each line of the packometer bar
bar_next:	ds.b	4                       ; where the next line is drawn
chunk_length:	ds.b	4                       ; a DPK chunk's length
disk_spt:	ds.b	2                       ; sectors a track
resolution:	ds.b	2
basepage:	ds.b	4
lson:	ds.b	8194                            ; LZH: left children
screen_width:	ds.b	2
fat_count:	ds.b	6
screen:	ds.b	4
textsize:	ds.b	4                       ; LZH: the bytes read
vdi_intout:	ds.b	256
aes_global:	ds.b	32
format_flag:	ds.b	2                       ; Format
aes_control:	ds.b	10
tree_about:	ds.b	4
cluster_count:	ds.b	2
program_flag:	ds.b	2                       ; the Data/Program button: 1 for a program
desktop_rect:	ds.b	8
heading_flag:	ds.b	2                       ; Heading
tree_desktop:	ds.b	4
jam_total:	ds.b	4                       ; the jam file's length
vdi_ptsout:	ds.b	256
work_text:	ds.b	180                     ; titles put together here
save_name:	ds.b	128                     ; the file chosen to save to
disk_sectors:	ds.b	2                       ; the disk's sectors
bar_height:	ds.b	2                       ; the packometer bar's height in lines
about_rect:	ds.b	8
tree_packometer:	ds.b	4
aes_block:	ds.b	24                      ; the AES parameter block: control, global, intin, intout, addrin,
                                                ;   addrout
fd_modes:	ds.b	92                      ; the open handles and their modes
trap_save_stack:	ds.b	48              ; a1, a2 and the return address of the trap calls under way
vdi_intin:	ds.b	256
disk_sides:	ds.b	2
aes_addrin:	ds.b	12
aes_intout:	ds.b	16
argc:	ds.b	2
bss_end:

	end
