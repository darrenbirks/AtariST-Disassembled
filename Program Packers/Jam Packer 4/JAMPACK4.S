; JAMPACK4.PRG  -  The JAM Packer V4.0
; Devpac source of the program, disassembled by Darren Birks, 11 November 2026.
; Text 41064 bytes, data 11488 bytes, bss 49786 bytes.
;
; JAMPACK4.PRG as distributed is packed itself: a 28214 byte program with the JAM Packer's own LZW stub
; ("JAM Packer Decrunch V4.0") and 'LZW!' data.  This is the source of the 54743 byte program that stub
; depacks.
;
; This source rebuilds that unpacked program byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o JAMPACK4.PRG JAMPACK4.S
; It needs no resource file: both its resources are built into the data section.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; The JAM Packer V4.0, shareware, (c) 1990, 1991 by Andrew and Tim Knipe.  It is JAM Packer 3.0 grown: the
; same C program (with its Megamax/Laser style library), two new methods, a new disk packer, and no Jammer.
; It refuses low resolution; medium and high resolution each have their own resource.
;
; The desktop dialog has:
;   Pack Method   LZH, V2, ICE or LZW.  V2 and ICE open the PackPower box, which sets how far the packer
;                 looks for strings: 4384 (5504 for ICE), 2048, 1024, 256, 64, or 8 more or less.
;   Multi Packer  pack every file a path matches into another folder, programs only when Programs is on, with
;                 a report of the files left alone and why.
;   File Packer   UNPACK a file packed with any of the methods ('LSD!', 'AUTM', 'LZH!', 'Ice!' or 'LZW!' in
;                 its first 2 K), or PACK one, as a program (Program) or as data; a file without a program
;                 header can be packed as data instead.  Flash and Heading set what a packed program's stub
;                 does while it depacks.
;   Disk Packer   PACK a disk in drive A or B into a .JPK file on drive A, B or C, or UnPACK one back to a disk
;                 (formatting it first with Format).  Use Boot takes the format from the boot sector, else it
;                 is found by reading the disk; with No Pack the sectors are stored as they are.  The sectors
;                 are read and written straight through the FDC and the DMA.
;
; The methods, each with the packometer bar drawn while it packs; holding Alternate aborts any of them:
;   LZH  LHarc 1.13's lzhuf (LZSS over a 4 K window and an adaptive Huffman code), compiled from C (pack_lzh),
;        reading the source from its end so that the data can be depacked in place from the end down.
;   V2   the Automation packers' 'LSD!' algorithm (pack_v2, in assembly).
;   ICE  a packer in assembly for the 'Ice!' format of Pack-Ice (pack_ice), with its depacker (ice_depack).
;   LZW  as the program calls it, but LZSS: a 4 K window and a flag byte before every 8 codes, as in Haruhiko
;        Okumura's lzss.c, in assembly (pack_lzw), the source read from its end down.
;
; A packed program is a PRG whose text is the method's stub, whose data is the packed data and whose BSS leaves
; room to depack it.  Each of the four stubs keeps the registers, clears the top of the screen and prints its
; title (Heading), depacks the program $100 bytes past its own end flashing the background (Flash), relocates
; it to run where the stub starts, and starts it from a mover on the screen.  set_stub_options patches the
; stubs for Flash and Heading before they are written.
;
; Some things in it look unfinished:
;   - disk_pack reads the FAT and unpacks it into a map when Use FAT is on, but nothing then uses the map.
;   - disk_unpack's read errors after the first chunk call close_gem rather than disk_error.
;   - fdc_sectors leaves flock set when the FDC times out.
;   - The PackPower box's OK is deselected with the state of the desktop's object 16.
;   - The multi packer's report gives a write error as both "Error writing destination file" and "Not enough
;     memory to pack file".
;   - Whether a program got smaller is judged with the LZH stub's length, whichever the method.
;   - check_object and uncheck_object are never called.
;   - The disk unpacker's file name defaults to DRIVEA.JPK whichever drive is written.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$0aaf  the C start-up, main and the PackPower box
;   $0ab0-$17a9  pack_one_file, the GEM helpers, ltoa/itoa and the about box
;   $17aa-$1ccd  depack_v2, lsd_depack and pack_v2
;   $1cce-$1fa7  v2_stub, the V2 program stub, with its depacker
;   $1fa8-$3c4f  the multi packer, unpack_file, set_stub_options, write_program, pack_file, the pack info and
;                multi_pack_file
;   $3c50-$41db  depack_ice, ice_depack and pack_ice
;   $41dc-$4487  ice_stub, the ICE program stub, with its depacker
;   $4488-$46b3  fdc_sectors, sectors read and written through the FDC
;   $46b4-$648d  the disk unpacker and packer and their helpers
;   $648e-$7641  pack_lzh, the LZH packer
;   $7642-$79cf  depack_lzh and the program's LZH decoder
;   $79d0-$7e5d  lzh_stub, the LZH program stub, with its decoder
;   $7e5e-$84ff  pack_lzw, depack_lzw and the program's LZW decoder
;   $8500-$8703  lzw_stub, the LZW program stub, with its decoder
;   $8704-$a067  the C library: AES, VDI, BIOS, XBIOS and GEMDOS bindings, stdio, malloc, strings
;   $a068-$cd47  the data: settings, texts and alerts, the two resources, the LZH tables and the library's
;                variables
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; LZH data: 'LZH!', the unpacked length, the packed length, then the code, read from the end down.
;
; V2 data: 'LSD!' ('AUTM' is also recognised), the unpacked length, the packed length, then a bit stream read
; from the end down, as the Automation packers write it.
;
; ICE data: 'Ice!', the packed length (with the header), the unpacked length, then a bit stream read from the
; end down: literal runs and strings, each coded as a run of 1 bits and a value.
;
; LZW data: 'LZW!', the unpacked length, the packed length, then the codes, read from the end down: a flag
; byte, lowest bit first (1 a literal, 0 a string), before each 8 codes; a string is 2 bytes, the low 8 bits
; of its window position, then its upper 4 bits and its length less 3.
;
; Packed program: a PRG header whose text is the stub ($2da bytes for V2, $48e for LZH, $2ac for ICE, $204 for
; LZW) and whose data is the packed data, then a 0 long for the relocation table.
;
; JPK file: 'JPK!', the sectors a track, the tracks and the sides (a word each), then chunks, each after its
; length (a long), and a -1 length at the end.  The first chunk is the system sectors (boot sector, FATs and
; root directory; none when the format was found by reading), the rest are 500 sectors each.  A chunk with
; none of the magics is stored as it is.
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The C start-up.  As a desk accessory (no parent basepage) it takes a stack from Malloc; as a program it
; shrinks its memory to the program plus the stack.  Then main(argc, argv, envp) and exit.
;------------------------------------------------------------------------------
start:	; from: v2_stub, ice_stub, lzh_stub, lzw_stub
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
; boxes are read after every form_do: the disk packer's four into locals, Programs, Flash and Heading into
; their flags.  The button is then dispatched through main_cases.
;------------------------------------------------------------------------------
main:	; from: start
	link	a6,#-8                          ; 8 bytes of locals
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	#$1,-$2(a6)                     ; Format
	move.w	#$1,-$4(a6)                     ; Use FAT
	clr.w	-$6(a6)                         ; Use Boot
	move.w	#$1,-$8(a6)                     ; No Pack
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
	move.w	$24a(a0),d0                     ; Use FAT (object 24)
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_use_fat                 ; no
	move.w	#$1,-$4(a6)                     ; yes
	bra.s	main_read_format
main_no_use_fat:
	clr.w	-$4(a6)
main_read_format:
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$262(a0),d0                     ; Format (object 25)
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_format                  ; no
	move.w	#$1,-$2(a6)                     ; yes
	bra.s	main_read_use_boot
main_no_format:
	clr.w	-$2(a6)
main_read_use_boot:
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$292(a0),d0                     ; Use Boot (object 27)
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_use_boot                ; no
	move.w	#$1,-$6(a6)                     ; yes
	bra.s	main_read_no_pack
main_no_use_boot:
	clr.w	-$6(a6)
main_read_no_pack:
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$2aa(a0),d0                     ; No Pack (object 28)
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_no_pack                 ; no
	move.w	#$1,-$8(a6)                     ; yes
	bra.s	main_read_programs
main_no_no_pack:
	clr.w	-$8(a6)
main_read_programs:
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$b2(a0),d0                      ; Programs (object 7)
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_programs                ; no
	move.w	#$1,multi_programs              ; yes
	bra.s	main_read_flash
main_no_programs:
	clr.w	multi_programs
main_read_flash:
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$1d2(a0),d0                     ; Flash (object 19)
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_flash                   ; no
	move.w	#$1,flash_flag                  ; yes
	bra.s	main_read_heading
main_no_flash:
	clr.w	flash_flag
main_read_heading:
	movea.l	tree_desktop,a0                 ; the desktop
	move.w	$1ea(a0),d0                     ; Heading (object 20)
	and.w	#$1,d0                          ; selected?
	beq.s	main_no_heading                 ; no
	move.w	#$1,heading_flag                ; yes
	bra.s	main_dispatch
main_no_heading:
	clr.w	heading_flag
main_dispatch:
	move.w	d7,d0                           ; the button
	bra.w	main_switch                     ; through main_cases
menu_lzh:	; from: app_flag
	move.w	#$9,algorithm                   ; LZH: the algorithm is its button
	bra.w	main_next
menu_lzw:	; from: app_flag
	move.w	#$d,algorithm                   ; LZW
	bra.w	main_next
menu_v2:	; from: app_flag
	move.w	#$a,algorithm                   ; V2
	move.l	#$1120,v2_window                ; its PackPower at most 4384
	pea	text_largest_v2                 ; "4384"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$6c(a0),-(sp)                   ; object 4's text: the largest
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.l	#$1120,-(sp)                    ; at most 4384
	jsr	pack_power                      ; the PackPower box
	addq.l	#4,sp                           ; drop the arguments
	bra.w	main_next
menu_ice:	; from: app_flag
	move.w	#$c,algorithm                   ; ICE
	move.l	#$1580,v2_window                ; its PackPower at most 5504
	pea	text_largest_ice                ; "5504"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$6c(a0),-(sp)                   ; object 4's text: the largest
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.l	#$1580,-(sp)                    ; at most 5504
	jsr	pack_power                      ; the PackPower box
	addq.l	#4,sp                           ; drop the arguments
	bra.w	main_next
menu_disk_pack:	; from: app_flag
	move.w	#$17,-(sp)                      ; deselect the disk PACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	move.w	-$8(a6),-(sp)                   ; No Pack
	move.w	-$6(a6),-(sp)                   ; Use Boot
	move.w	-$4(a6),-(sp)                   ; Use FAT
	jsr	disk_pack                       ; pack a disk
	addq.l	#6,sp                           ; drop the arguments
	bra.w	main_next
menu_disk_unpack:	; from: app_flag
	move.w	#$16,-(sp)                      ; deselect the disk UnPACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	move.w	-$2(a6),-(sp)                   ; Format
	jsr	disk_unpack                     ; unpack a disk
	addq.l	#2,sp                           ; drop the arguments
	bra.w	main_next
menu_toggle_program:	; from: app_flag
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
	move.l	$1bc(a0),-(sp)                  ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	clr.w	program_flag                    ; now data
	bra.s	menu_draw_program
menu_now_program:
	pea	text_program                    ; "Program"
	movea.l	tree_desktop,a0                 ; the button's text
	move.l	$1bc(a0),-(sp)                  ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$1,program_flag                ; now a program
menu_draw_program:
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$1,-(sp)                       ; depth 1
	move.w	#$12,-(sp)                      ; the button
	move.l	tree_desktop,-(sp)              ; the desktop
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	bra.w	main_next
menu_pack_file:	; from: app_flag
	move.w	program_flag,-(sp)              ; a program?
	jsr	pack_one_file                   ; pack or unpack a file
	addq.l	#2,sp                           ; drop the arguments
	jsr	clear_title                     ; the background
	bra.w	main_next
menu_unpack_file:	; from: app_flag
	pea	text_choose_unpack_file         ; "Choose a file to UNPACK"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	file_name                       ; the path chosen
	pea	pack_file_name                  ; the name
	pea	source_path                     ; the source path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.w	menu_unpack_done                ; no
	pea	file_name                       ; the file
	jsr	unpack_file                     ; unpack it
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,d7                           ; the result
	move.w	d7,d0
	bra.w	menu_unpack_result              ; -1 or 1?
menu_not_packed:
	pea	alert_not_packed                ; -1: "File not packed with LZH, V2 or ICE"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	bra.w	menu_unpack_done
menu_unpack_no_memory:
	pea	alert_no_memory_to_unpack       ; 1: "Insufficient Memory To Unpack File"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	bra.s	menu_unpack_done
menu_unpack_result:
	cmp.w	#$1,d0
	beq.s	menu_unpack_no_memory
	cmp.w	#$ffff,d0
	beq.s	menu_not_packed
menu_unpack_done:
	jsr	clear_title                     ; the background
	move.w	#$f,-(sp)                       ; deselect the UNPACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	bra.w	main_next
menu_multi_pack:	; from: app_flag
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
	pea	file_name                       ; the file chosen
	jsr	multi_pack
	lea	$e(sp),sp                       ; drop the arguments
	bra.s	menu_multi_paths
menu_multi_data:
	clr.w	-(sp)                           ; data only
	pea	destination_path                ; the destination
	pea	source_path                     ; the source
	pea	file_name                       ; the file chosen
	jsr	multi_pack
	lea	$e(sp),sp                       ; drop the arguments
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
	move.w	#$5,-(sp)                       ; deselect the PACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	jsr	clear_title                     ; the background
	bra.w	main_next
menu_about:	; from: app_flag
	jsr	about_box                       ; the about box
	bra.w	main_next
menu_about2:	; from: app_flag
	jsr	about_box                       ; the about box
	bra.w	main_next
menu_none:	; from: app_flag
	bra.s	main_next                       ; anything else
main_switch:
	subq.w	#1,d0                           ; buttons 1 to 23
	cmp.w	#$16,d0
	bls.s	main_switch_case
	move.w	#$17,d0                         ; others: the last case
main_switch_case:
	add.w	d0,d0                           ; words
	movea.l	#main_cases,a0                  ; the offsets
	movea.l	#main,a1                        ; from main
	adda.w	0(a0,d0.w),a1                   ; the case
	jmp	(a1)
main_next:
	movea.l	tree_desktop,a0                 ; EXIT selected?
	move.w	$52(a0),d0                      ; object 3's state
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
; pack_power(largest): the PackPower dialog for V2 and ICE, which sets v2_window, the window the packer looks
; back over: the largest button (4384, or 5504 for ICE), 2048, 1024, 256 and 64, or the arrows for 8 more or
; less, from 8 up to the largest.  Its OK is deselected with the state of the desktop's object 16 rather
; than its own.
;------------------------------------------------------------------------------
pack_power:	; from: main
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	cmpi.w	#$a,algorithm                   ; V2?
	bne.s	pack_power_ice                  ; no
	pea	text_pack_power_v2              ; "4384"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$15c(a0),-(sp)                  ; object 14's text: the window shown
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	bra.s	pack_power_open
pack_power_ice:
	pea	text_pack_power_ice             ; "5504"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$15c(a0),-(sp)                  ; object 14's text
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
pack_power_open:
	move.l	screen_buffer,-(sp)             ; the screen
	move.l	screen,-(sp)                    ; saved
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	pea	packpower_rect                  ; its box
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	open_box                        ; drawn
	addq.l	#8,sp                           ; drop the arguments
pack_power_loop:
	clr.w	-(sp)                           ; no edit object
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	form_do
	addq.l	#6,sp                           ; drop the arguments
	move.w	d0,d7
	move.w	d7,d0                           ; the button
	bra.w	pack_power_button
pack_power_less:
	move.l	8(a6),-(sp)                     ; the largest
	move.l	#$fffffff8,-(sp)                ; 8 less
	jsr	pack_power_step
	addq.l	#8,sp                           ; drop the arguments
	bra.w	pack_power_next
pack_power_more:
	move.l	8(a6),-(sp)                     ; the largest
	move.l	#$8,-(sp)                       ; 8 more
	jsr	pack_power_step
	addq.l	#8,sp                           ; drop the arguments
	bra.w	pack_power_next
pack_power_largest:
	pea	dummy                           ; wait for the mouse button to be let go
	pea	dummy                           ; argument 6
	pea	dummy                           ; argument 5
	pea	dummy                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	#$1,-(sp)                       ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	evnt_button
	lea	$16(sp),sp                      ; drop the arguments
	move.l	8(a6),v2_window                 ; window = the largest
	cmpi.w	#$a,algorithm                   ; V2?
	bne.s	pack_power_largest_ice          ; no
	pea	text_largest_v2_again           ; "4384"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$15c(a0),-(sp)                  ; object 14's text
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	bra.s	pack_power_draw
pack_power_largest_ice:
	pea	text_largest_ice_again          ; "5504"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$15c(a0),-(sp)                  ; object 14's text
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
pack_power_draw:
	move.w	#$25,-(sp)                      ; Vsync
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$c,-(sp)                       ; the slider (object 12)
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	bra.w	pack_power_next
pack_power_2048:
	pea	dummy                           ; wait for the mouse button to be let go
	pea	dummy                           ; argument 6
	pea	dummy                           ; argument 5
	pea	dummy                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	#$1,-(sp)                       ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	evnt_button
	lea	$16(sp),sp                      ; drop the arguments
	move.l	#$800,v2_window                 ; window = 2048
	pea	text_2048                       ; "2048"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$15c(a0),-(sp)                  ; object 14's text
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$25,-(sp)                      ; Vsync
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$c,-(sp)                       ; the slider
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	bra.w	pack_power_next
pack_power_1024:
	pea	dummy                           ; wait for the mouse button to be let go
	pea	dummy                           ; argument 6
	pea	dummy                           ; argument 5
	pea	dummy                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	#$1,-(sp)                       ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	evnt_button
	lea	$16(sp),sp                      ; drop the arguments
	move.l	#$400,v2_window                 ; window = 1024
	pea	text_1024                       ; "1024"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$15c(a0),-(sp)                  ; object 14's text
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$25,-(sp)                      ; Vsync
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$c,-(sp)                       ; the slider
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	bra.w	pack_power_next
pack_power_256:
	pea	dummy                           ; wait for the mouse button to be let go
	pea	dummy                           ; argument 6
	pea	dummy                           ; argument 5
	pea	dummy                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	#$1,-(sp)                       ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	evnt_button
	lea	$16(sp),sp                      ; drop the arguments
	move.l	#$100,v2_window                 ; window = 256
	pea	text_256                        ; " 256"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$15c(a0),-(sp)                  ; object 14's text
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$25,-(sp)                      ; Vsync
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$c,-(sp)                       ; the slider
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	bra.w	pack_power_next
pack_power_64:
	pea	dummy                           ; wait for the mouse button to be let go
	pea	dummy                           ; argument 6
	pea	dummy                           ; argument 5
	pea	dummy                           ; argument 4
	clr.w	-(sp)                           ; argument 3
	move.w	#$1,-(sp)                       ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	evnt_button
	lea	$16(sp),sp                      ; drop the arguments
	move.l	#$40,v2_window                  ; window = 64
	pea	text_64                         ; "  64"
	movea.l	tree_packpower,a0               ; the PackPower box
	move.l	$15c(a0),-(sp)                  ; object 14's text
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$25,-(sp)                      ; Vsync
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	move.w	#$2,-(sp)                       ; depth 2
	move.w	#$c,-(sp)                       ; the slider
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	bra.s	pack_power_next
	bra.s	pack_power_next
pack_power_button:
	cmp.w	#$4,d0                          ; the largest?
	beq.w	pack_power_largest
	cmp.w	#$5,d0                          ; 2048?
	beq.w	pack_power_2048
	cmp.w	#$6,d0                          ; 1024?
	beq.w	pack_power_1024
	cmp.w	#$7,d0                          ; 256?
	beq.w	pack_power_256
	cmp.w	#$8,d0                          ; 64?
	beq.w	pack_power_64
	cmp.w	#$b,d0                          ; the arrow for more?
	beq.w	pack_power_more
	cmp.w	#$f,d0                          ; the arrow for less?
	beq.w	pack_power_less
pack_power_next:
	movea.l	tree_packpower,a0               ; the PackPower box
	move.w	$18a(a0),d0                     ; OK (object 16) selected?
	and.w	#$1,d0
	beq.w	pack_power_loop                 ; no: on
	movea.l	tree_desktop,a0                 ; yes: the desktop
	move.w	$18a(a0),d6                     ; its object 16's state
	and.w	#$fffe,d6                       ; not selected
	move.w	#$1,-(sp)                       ; redraw
	move.w	d6,-(sp)                        ; the new state
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	clr.w	-(sp)                           ; 0
	move.w	#$10,-(sp)                      ; OK
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	objc_change
	lea	$14(sp),sp                      ; drop the arguments
	pea	packpower_rect                  ; its box
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	close_box                       ; removed
	addq.l	#8,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the screen
	move.l	screen_buffer,-(sp)             ; back from the buffer
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; pack_power_step(step, largest): window + step, kept from 8 to the largest, written into object 14 four
; characters wide, and the slider and the text redrawn.
;------------------------------------------------------------------------------
pack_power_step:	; from: pack_power
	link	a6,#0                           ; the frame
	movem.l	a5,-(sp)                        ; keep the registers
	movea.l	tree_packpower,a0               ; the PackPower box
	movea.l	$15c(a0),a5                     ; object 14's text
	move.l	8(a6),d0
	add.l	d0,v2_window
	cmpi.l	#$8,v2_window                   ; less than 8?
	bge.s	pack_power_step_largest         ; no
	move.l	#$8,v2_window                   ; yes: 8
	bra.s	pack_power_step_show
pack_power_step_largest:
	move.l	v2_window,d0                    ; more than the largest?
	cmp.l	$c(a6),d0
	ble.s	pack_power_step_show            ; no
	move.l	$c(a6),v2_window                ; yes: the largest
pack_power_step_show:
	cmpi.l	#$3e8,v2_window                 ; 1000 or more?
	blt.s	pack_power_step_3               ; no
	move.l	a5,-(sp)                        ; the text
	move.l	v2_window,d0                    ; the window
	move.w	d0,-(sp)                        ; in decimal
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	bra.s	pack_power_step_draw
pack_power_step_3:
	cmpi.l	#$64,v2_window                  ; 100 or more?
	blt.s	pack_power_step_2               ; no
	move.b	#$20,(a5)                       ; a space
	move.l	a5,d0                           ; then the digits
	addq.l	#1,d0
	move.l	d0,-(sp)
	move.l	v2_window,d0
	move.w	d0,-(sp)                        ; the window
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
	bra.s	pack_power_step_draw
pack_power_step_2:
	move.b	#$20,(a5)                       ; two spaces
	move.b	#$20,1(a5)
	move.l	a5,d0                           ; then the digits
	addq.l	#2,d0
	move.l	d0,-(sp)
	move.l	v2_window,d0
	move.w	d0,-(sp)                        ; the window
	jsr	itoa
	addq.l	#6,sp                           ; drop the arguments
pack_power_step_draw:
	move.w	#$25,-(sp)                      ; Vsync
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	clr.w	-(sp)                           ; depth 0
	move.w	#$d,-(sp)                       ; the slider's box (object 13)
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	move.w	#$25,-(sp)                      ; Vsync
	jsr	xbios
	addq.l	#2,sp                           ; drop the arguments
	move.w	screen_height,-(sp)             ; the clip box: the screen
	move.w	screen_width,-(sp)              ; argument 6
	clr.w	-(sp)                           ; argument 5
	clr.w	-(sp)                           ; argument 4
	clr.w	-(sp)                           ; depth 0
	move.w	#$e,-(sp)                       ; the text (object 14)
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	objc_draw
	lea	$10(sp),sp                      ; drop the arguments
	movem.l	(sp)+,a5                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; pack_one_file(program): choose a file and pack it.  A program that does not start with $601a is offered as
; data instead (Yes: as data, No: as a program, Cancel).  The mouse is hidden while it packs; each failure
; has its alert.
;------------------------------------------------------------------------------
pack_one_file:	; from: main
	link	a6,#-54                         ; 54 bytes of locals
	movem.l	d7,-(sp)                        ; keep the registers
	pea	text_choose_pack_file           ; "Choose a file to PACK"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$10,-(sp)                      ; deselect the file PACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	pea	file_name                       ; the path chosen
	pea	pack_file_name                  ; the name
	pea	source_path                     ; the source path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	bne.w	pack_one_file_done              ; no
	jsr	clear_title                     ; the background
	move.w	#$2f,-(sp)                      ; Fgetdta
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	move.l	d0,-$4(a6)                      ; kept
	pea	-$36(a6)                        ; a DTA of our own
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
	cmpi.l	#$a,-$1c(a6)                    ; more than 10 bytes?
	bgt.s	pack_file_size_ok               ; yes
	pea	alert_file_too_small            ; no: "File Too Small"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$10,-(sp)                      ; deselect the file PACK button
	jsr	deselect
	addq.l	#2,sp                           ; drop the arguments
	move.w	#$ffff,d0
	bra.w	pack_one_file_done
pack_file_size_ok:
	move.l	-$4(a6),-(sp)                   ; the old DTA
	move.w	#$1a,-(sp)                      ; Fsetdta
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	cmpi.w	#$1,8(a6)                       ; a program?
	bne.w	pack_one_file_pack              ; no
	move.l	#$2,-(sp)                       ; 2 bytes
	pea	-$a(a6)                         ; into a local
	pea	file_name                       ; of the file
	jsr	load_file
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$ffffffff,d0                   ; could not be opened?
	beq.w	pack_one_file_pack              ; yes: pack it anyway
	cmpi.w	#$601a,-$a(a6)                  ; a program's header?
	beq.w	pack_one_file_pack              ; yes
	pea	alert_not_executable            ; no: "Not an executable file. Pack as DATA only?"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.w	d0,d7                           ; the button
	move.w	d7,d0
	bra.w	pack_one_file_answer
pack_one_file_as_data:
	clr.w	8(a6)                           ; Yes: as data
	bra.w	pack_one_file_pack
pack_one_file_cancel:
	move.w	#$ffff,d0                       ; Cancel: -1
	bra.w	pack_one_file_done
	bra.s	pack_one_file_pack
pack_one_file_answer:
	cmp.w	#$1,d0                          ; Yes?
	beq.s	pack_one_file_as_data
	cmp.w	#$3,d0                          ; Cancel? (No: as a program)
	beq.s	pack_one_file_cancel
pack_one_file_pack:
	clr.l	-(sp)                           ; M_OFF: the mouse hidden
	move.w	#$100,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	pea	-$18(a6)                        ; the DTA's name, shown
	move.w	8(a6),-(sp)                     ; a program?
	move.l	-$1c(a6),-(sp)                  ; its length
	pea	file_name                       ; the file
	jsr	pack_file                       ; pack it
	lea	$e(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; the result
	clr.l	-(sp)                           ; M_ON: the mouse back
	move.w	#$101,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
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
	bra.w	pack_one_file_done
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
	bne.s	pack_file_not_larger            ; no
	pea	alert_packed_size_larger        ; "Packed Size > Original Size"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$ffff,d0
	bra.s	pack_one_file_done
pack_file_not_larger:
	cmpi.l	#$6,-$8(a6)                     ; 6: aborted?
	bne.s	pack_one_file_done              ; no
	pea	alert_pack_aborted              ; "Pack Aborted!"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	nop
pack_one_file_done:
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; choose_file(path, name, full): the file selector over the saved screen; full = the path up to its last \
; and the name.  d0 = 0 for OK, -1 for Cancel.
;------------------------------------------------------------------------------
choose_file:	; from: main, pack_one_file, unpack_file, pack_file, disk_unpack, disk_pack
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
; it is relocated and its six trees found.  The defaults are set (Flash, Heading, Program, Programs,
; Format, Use FAT and LZH), and the desktop is placed at the bottom of the screen, the others where they
; fit.
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
	pea	alert_low_rez                   ; "The JAM Packer V4.0 will not work in low res."
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
	pea	tree_desktop                    ; tree 0: the desktop
	clr.w	-(sp)                           ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	rsrc_gaddr
	addq.l	#8,sp                           ; drop the arguments
	pea	tree_packometer                 ; tree 2: the packometer
	move.w	#$2,-(sp)                       ; argument 2
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
	pea	tree_disk                       ; tree 3: the disk progress
	move.w	#$3,-(sp)                       ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	rsrc_gaddr
	addq.l	#8,sp                           ; drop the arguments
	pea	tree_packpower                  ; tree 5: PackPower
	move.w	#$5,-(sp)                       ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	rsrc_gaddr
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$1,heading_flag                ; Heading on
	move.w	#$1,flash_flag                  ; Flash on
	move.w	#$1,program_flag                ; Program on
	move.w	#$1,multi_programs              ; Programs on
	movea.l	tree_desktop,a0                 ; the desktop
	ori.w	#$1,$1d2(a0)                    ; Flash (object 19) selected
	movea.l	tree_desktop,a0                 ; the desktop
	ori.w	#$1,$1ea(a0)                    ; Heading (object 20)
	movea.l	tree_desktop,a0                 ; the desktop
	ori.w	#$1,$262(a0)                    ; Format (object 25)
	movea.l	tree_desktop,a0                 ; the desktop
	ori.w	#$1,$b2(a0)                     ; Programs (object 7)
	movea.l	tree_desktop,a0                 ; the desktop
	ori.w	#$1,$24a(a0)                    ; Use FAT (object 24)
	movea.l	tree_desktop,a0                 ; the desktop
	ori.w	#$1,$e2(a0)                     ; LZH (object 9)
	pea	packometer_rect+6               ; its box
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
	pea	packpower_rect+6                ; the PackPower box's place
	pea	packpower_rect+4                ; argument 4
	pea	packpower_rect+2                ; argument 3
	pea	packpower_rect                  ; argument 2
	move.l	tree_packpower,-(sp)            ; the PackPower box
	jsr	form_center                     ; centred
	lea	$14(sp),sp                      ; drop the arguments
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
fatal_alert:	; from: init_gem, unpack_file
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
copy_screen:	; from: main, pack_power, pack_one_file, choose_file, about_box, multi_pack, 5 more
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
open_box:	; from: main, pack_power, disk_unpack, disk_pack
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
close_box:	; from: main, pack_power, disk_unpack, disk_pack, disk_error
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
clear_title:	; from: main, pack_one_file, show_title, disk_unpack, disk_pack, analyse_disk, 1 more
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
show_title:	; from: main, pack_one_file, unpack_file, write_program, pack_file, save_file, 3 more
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
ltoa:	; from: show_pack_sizes, show_crunching, disk_unpack
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
itoa:	; from: pack_power_step, disk_unpack, disk_pack, show_disk_info
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; the value
	clr.w	d5                              ; the digit count
	move.w	#$1,d4                          ; leading zeros
	tst.w	d7
	bne.s	itoa_places
	move.w	d5,d0
	addq.w	#1,d5
	movea.l	$a(a6),a0
	move.b	#$30,0(a0,d0.w)
	bra.s	itoa_end
itoa_places:
	move.w	#$2710,d6                       ; from the ten thousands
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
itoa_end:
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
depack_v2:	; from: unpack_file, depack_chunk
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the packed data
	move.l	$c(a6),d6                       ; the destination
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	depack_v2_colour(pc),a0         ; the background colour
	move.w	$ffff8240.w,(a0)                ; palette 0, palette 0, kept
	movea.l	d7,a0                           ; a0 = the packed data
	movea.l	d6,a1                           ; a1 = the destination
	lea	depack_v2_ssp(pc),a2
	move.l	d0,(a2)                         ; keep the old stack
	move.l	4(a0),-(sp)                     ; the unpacked length, kept
	move.l	$bc.w,-(sp)                     ; keep the trap #15 vector: lsd_depack uses it
	bsr.s	lsd_depack                      ; depack
	move.l	(sp)+,$bc.w                     ; the vector back
	move.l	(sp)+,d7                        ; d7 = the unpacked length
	move.w	depack_v2_colour(pc),$ffff8240.w ; palette 0, palette 0, the colour back
	move.l	depack_v2_ssp(pc),-(sp)         ; Super(old stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d7,d0                           ; returned
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
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
; pack_v2(source, length, destination, window): pack with the V2 algorithm in supervisor mode, drawing the
; packometer's bar on the screen as it goes; holding Alternate aborts it.  The packer's variables are kept in
; the trap vectors $80-$b0, which are saved and put back.  d0 = the packed length, or -1 when aborted.
;------------------------------------------------------------------------------
pack_v2:	; from: pack_file, multi_pack_file, pack_chunk
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
	lea	pack_v2_ssp(pc),a0              ; the old stack
	move.l	d0,(a0)                         ; kept
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
	bsr.w	pack_v2_crunch
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	lea	pack_v2_result(pc),a0           ; the result
	move.l	d0,(a0)                         ; kept
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
	move.l	pack_v2_result(pc),d0           ; the packed length
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; Draw the packometer's bar up to the position reached: one line of it for each $a4 bytes.  With Alternate
; held it returns -1 from pack_v2_crunch instead.
;------------------------------------------------------------------------------
pack_v2_bar:	; from: pack_v2_crunch
	movem.l	d0-d2/a0-a2,-(sp)               ; keep the registers
	move.l	a0,d0                           ; the position
	sub.l	a5,d0                           ; less the start
	divu.w	$a4.w,d0                        ; in bar lines
pack_v2_bar_loop:
	cmpa.w	bar_height,a4                   ; the bar full?
	bge.s	pack_v2_bar_done                ; yes
	cmp.w	a4,d0                           ; drawn so far?
	bgt.s	pack_v2_bar_check               ; no: another line
pack_v2_bar_done:
	movem.l	(sp)+,d0-d2/a0-a2               ; the registers back
	rts
pack_v2_bar_check:
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	trap	#13                             ; Kbshift
	addq.l	#4,sp                           ; drop the arguments
	btst	#$3,d0                          ; Alternate?
	bne.s	pack_v2_bar_abort               ; yes: abort
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
pack_v2_bar_abort:
	movem.l	(sp)+,d0-d2/a0-a2               ; the registers back
	addq.l	#4,sp                           ; not back to pack_v2_crunch
	moveq	#-1,d0                          ; -1
	rts
pack_v2_ssp:	; from: pack_v2
	dc.l	$00000000                       ; the stack Super returned
pack_v2_result:	; from: pack_v2
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
	move.w	#$1,$80.w                       ; trap #0, best match 1
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
	cmp.w	$80.w,d0                        ; trap #0, longer than the best?
	ble.s	pack_v2_match_restore           ; no
	move.w	d0,$80.w                        ; trap #0, yes: the best
	move.w	d1,$8c.w                        ; and its offset
pack_v2_match_restore:
	movem.l	(sp)+,d0/a0-a3                  ; the registers back
pack_v2_search_next:
	addq.w	#1,d1                           ; the next offset
	lea	0(a0,d1.w),a3
	cmpa.l	a2,a3                           ; past the end?
	dbeq	d2,pack_v2_search               ; on through the window
	move.w	$8c.w,d0                        ; the best offset
	move.w	$80.w,d1                        ; trap #0, the best length
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
	move.w	$80.w,d0                        ; trap #0, the length
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
	move.l	$9c.w,d0
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
	move.w	$80.w,d0                        ; trap #0, the length
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
	dc.w	$4cdf,$00f0,$4e5e,$4e75         ; not reached: pack_v2's end as compiled

;------------------------------------------------------------------------------
; The V2 program stub ("JAM Packer Decrunch V4.0"), put in front of a program packed with V2.
; Each stub keeps the registers, clears the top of the screen and prints its title (unless Heading is off),
; depacks the program $100 bytes past its own end flashing the background (unless Flash is off), relocates
; it to run where the stub starts, sets the basepage and runs a mover from the screen that copies it down,
; clears its BSS (at least $400 bytes, $1a00 for LZH), puts the registers back and jumps to it.  The packed
; data follows the stub.
;------------------------------------------------------------------------------
v2_stub:	; from: write_program, pack_file, multi_pack_file
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
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
	beq.s	v2_stub_clear                   ; yes
	move.w	#$167,d1                        ; 360 longs otherwise
v2_stub_clear:	; from: set_stub_options
	clr.l	(a2)+                           ; clear the top of the screen (a nop without Heading)
	dbra	d1,v2_stub_clear
	lea	v2_stub_text(pc),a1             ; the title
	move.b	#$3c,5(a1)                      ; column 28
	cmp.b	#$0,d0                          ; low resolution?
	bne.s	v2_stub_title                   ; no
	move.b	#$28,5(a1)                      ; yes: column 8
v2_stub_title:
	pea	v2_stub_text(pc)                ; the title
	move.w	#$9,-(sp)
v2_stub_print:	; from: set_stub_options
	trap	#1                              ; Cconws, Cconws (a nop without Heading)
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; kept
	move.w	$ffff8240.w,-(sp)               ; palette 0
	lea	v2_stub+$2da(pc),a0             ; the packed data after the stub
	movea.l	a0,a1
	adda.l	#$100,a1                        ; a1 = $400 above it
	move.l	4(a0),-(sp)                     ; argument 1
	bsr.w	v2_stub_depack
	movea.l	(sp)+,a6
	move.w	(sp)+,$ffff8240.w               ; palette 0
	move.w	#$20,-(sp)                      ; Super(old stack)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	v2_stub+$2da(pc),a3             ; the depacked program: $100 bytes on
	adda.l	#$100,a3
	movea.l	a3,a1
	movea.l	2(a3),a0                        ; its header's text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	adda.l	#$1c,a0                         ; + the header
	adda.l	a3,a0                           ; a0 = its relocation table
	lea	v2_stub(pc),a5                  ; where it will run: the stub's text
	move.l	a5,d0
	adda.l	#$1c,a1                         ; its text
	tst.l	(a0)                            ; any relocation?
	beq.s	v2_stub_relocated               ; no
	adda.l	(a0)+,a1                        ; the first address
v2_stub_relocate:
	add.l	d0,(a1)                         ; relocate a long
v2_stub_relocate_next:
	clr.l	d1
	move.b	(a0)+,d1                        ; the next step
	tst.w	d1                              ; the end?
	beq.s	v2_stub_relocated               ; yes
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	v2_stub_relocate_step           ; no
	adda.l	#$fe,a1                         ; yes
	bra.s	v2_stub_relocate_next
v2_stub_relocate_step:
	adda.l	d1,a1                           ; on to the next long
	bra.s	v2_stub_relocate                ; relocate it
v2_stub_relocated:
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
	moveq	#95,d2
	lea	v2_stub_mover(pc),a1            ; the mover
v2_stub_copy_mover:
	move.b	(a1)+,(a2)+                     ; copied
	dbra	d2,v2_stub_copy_mover
	movea.l	a3,a1                           ; the depacked text
	adda.l	#$1c,a1
	lea	v2_stub(pc),a0                  ; where it runs
	movea.l	a0,a2
	jmp	(a5)                            ; run the mover
v2_stub_mover:
	lea	v2_stub_start+2(pc),a6          ; where the last jump goes
	move.l	a0,(a6)                         ; the start of the program, put in it
v2_stub_mover_copy:
	move.l	(a1)+,(a2)+                     ; copy the program down, 16 bytes at a time
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	cmpa.l	d1,a2                           ; to the BSS?
	ble.s	v2_stub_mover_copy
	lea	-$100(a0),a1                    ; the basepage
	movea.l	$18(a1),a3                      ; its BSS
	move.l	$1c(a1),d1                      ; its length
	cmp.l	#$400,d1                        ; at least $400 bytes
	bgt.s	v2_stub_clear_size              ; yes
	move.l	#$400,d1                        ; no: $400
v2_stub_clear_size:
	lsr.l	#4,d1                           ; in 16 bytes
v2_stub_clear_bss:
	clr.l	(a3)+                           ; cleared
	clr.l	(a3)+
	clr.l	(a3)+
	clr.l	(a3)+
	subq.l	#1,d1                           ; less one
	bge.s	v2_stub_clear_bss
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	clr.l	d0                              ; d0 = 0
v2_stub_start:
	jmp	$0                              ; start the program (the mover puts its address in)

;------------------------------------------------------------------------------
; The stub's depacker: lsd_depack with the background colour rotating as it goes.
;------------------------------------------------------------------------------
v2_stub_depack:	; from: v2_stub
	move.w	#$fe,d7                         ; the colour
	adda.l	#$4,a0                          ; past 'LSD!'
	movea.l	a0,a6                           ; a6 = the header
	move.l	(a0)+,d5                        ; d5 = the unpacked length
	adda.l	d5,a1                           ; a1 = the end of the output
	adda.l	(a0),a0                         ; + the packed length
	suba.l	#$4,a0
	tst.w	-(a0)                           ; the pad flag word
	bpl.s	v2_stub_first_bits              ; no pad byte
	subq.l	#1,a0                           ; a pad byte: skip it
v2_stub_first_bits:
	move.b	-(a0),d0                        ; the first bits
v2_stub_next:
	ror.w	#1,d7                           ; the next colour
v2_stub_flash:	; from: set_stub_options
	move.w	d7,$ffff8240.w                  ; palette 0, flash the background (a nop without Flash)
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_literal_bit             ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_literal_bit:
	bcc.s	v2_stub_string                  ; 0: no literals
	clr.w	d1                              ; one literal
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_literal_count_bit       ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_literal_count_bit:
	bcc.s	v2_stub_copy_literals           ; 0: one literal
	lea	v2_stub_literal_table(pc),a3    ; the literal count codes
	moveq	#3,d3                           ; 4 sizes
v2_stub_literal_size:
	clr.w	d1
	move.b	0(a3,d3.w),d2                   ; its bits
	ext.w	d2                              ; to a word
	moveq	#-1,d4
	lsl.w	d2,d4
	not.w	d4                              ; the all-ones value
	subq.w	#1,d2
v2_stub_literal_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_literal_bits_next       ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_literal_bits_next:
	roxl.w	#1,d1                           ; into d1
	dbra	d2,v2_stub_literal_bits         ; for each bit
	tst.w	d3                              ; the last size?
	beq.s	v2_stub_literal_base            ; yes
	cmp.w	d1,d4                           ; all ones: the next size
	dbne	d3,v2_stub_literal_size
v2_stub_literal_base:
	move.b	4(a3,d3.w),d2                   ; + the size's base
	ext.w	d2                              ; to a word
	add.w	d2,d1
v2_stub_copy_literals:
	move.b	-(a0),-(a1)                     ; copy a literal
	dbra	d1,v2_stub_copy_literals        ; for each literal
v2_stub_string:
	movea.l	a6,a3                           ; the header
	addq.l	#8,a3                           ; + 8: the start of the bit stream
	cmpa.l	a3,a0                           ; reached?
	ble.w	v2_stub_depack_done             ; yes: done
	lea	v2_stub_length_table(pc),a3     ; the length codes
	moveq	#3,d2                           ; up to 4 bits
v2_stub_length_code:
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_length_code_bit         ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_length_code_bit:
	bcc.s	v2_stub_length_found            ; 0: this code
	dbra	d2,v2_stub_length_code
v2_stub_length_found:
	clr.w	d1
	addq.w	#1,d2
	move.b	0(a3,d2.w),d3                   ; its extra bits
	beq.s	v2_stub_length_base             ; none
	ext.w	d3                              ; to a word
	subq.w	#1,d3
v2_stub_length_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_length_bits_next        ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_length_bits_next:
	roxl.w	#1,d1                           ; into d1
	dbra	d3,v2_stub_length_bits          ; for each bit
v2_stub_length_base:
	move.b	5(a3,d2.w),d3                   ; + the base length
	ext.w	d3                              ; to a word
	add.w	d3,d1
	cmpi.w	#$2,d1                          ; length 2?
	beq.s	v2_stub_short_offset            ; yes: a short offset
	lea	v2_stub_offset_table(pc),a3     ; the offset codes
	moveq	#1,d3                           ; up to 2 bits
v2_stub_offset_code:
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_offset_code_bit         ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_offset_code_bit:
	bcc.s	v2_stub_offset_found            ; 0: this code
	dbra	d3,v2_stub_offset_code
v2_stub_offset_found:
	addq.w	#1,d3
	clr.w	d2
	move.b	0(a3,d3.w),d4                   ; its bits
	ext.w	d4                              ; to a word
v2_stub_offset_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_offset_bits_next        ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_offset_bits_next:
	roxl.w	#1,d2                           ; into d2
	dbra	d4,v2_stub_offset_bits          ; for each bit
	lsl.w	#1,d3                           ; words
	add.w	4(a3,d3.w),d2                   ; + the base offset
	bra.s	v2_stub_copy_string
v2_stub_short_offset:
	clr.w	d2
	moveq	#5,d3                           ; 6 bits
	clr.w	d4                              ; base 0
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_short_offset_bit        ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_short_offset_bit:
	bcc.s	v2_stub_short_offset_bits       ; 0: 6 bits
	moveq	#8,d3                           ; 1: 9 bits
	moveq	#64,d4                          ; base 64
v2_stub_short_offset_bits:
	lsl.b	#1,d0                           ; a bit
	bne.s	v2_stub_short_offset_next       ; any left?
	move.b	-(a0),d0                        ; no: the next byte
	roxl.b	#1,d0
v2_stub_short_offset_next:
	roxl.w	#1,d2                           ; into d2
	dbra	d3,v2_stub_short_offset_bits    ; for each bit
	add.w	d4,d2                           ; + the base
v2_stub_copy_string:
	lea	0(a1,d2.w),a2                   ; the string's source
	ext.l	d1                              ; to a long
	adda.l	d1,a2                           ; + the length
	subq.w	#1,d1
v2_stub_copy_string_loop:
	move.b	-(a2),-(a1)                     ; copy it
	dbra	d1,v2_stub_copy_string_loop     ; for each byte
	bra.w	v2_stub_next                    ; and on
v2_stub_depack_done:
	rts
v2_stub_literal_table:
	dc.b	$0a,$03,$02,$02,$0e,$07,$04,$01 ; bits, then base counts less 1
v2_stub_length_table:
	dc.b	$0a,$02,$01,$00,$00,$0a,$06,$04,$03,$02 ; extra bits, then base lengths
v2_stub_offset_table:
	dc.b	$0b,$04,$07,$00                 ; bits, then base offsets
	dc.w	$0120,$0000,$0020,$0000
v2_stub_text:	; from: v2_stub
	dc.b	27,'j',27,'Y  JAM Packer Decrunch V4.0',27,'k',0 ; save the cursor, cursor to row 0 and the column, the
                                                ;   title, restore the cursor
	dc.b	$00

;------------------------------------------------------------------------------
; multi_pack(file, source, destination, programs): pack every file the file selector's path matches into
; the destination folder under the same name, with the mouse hidden.  Files left alone are noted with the
; reason, and when there are any a text report is shown at the end, 16 lines a page.  d0 = 1 when no file
; matches.  A write error is reported as "Error writing destination file" and "Not enough memory" both.
;------------------------------------------------------------------------------
multi_pack:	; from: main, v2_stub, write_program, pack_file, multi_pack_file
	link	a6,#-316                        ; 316 bytes of locals
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
	pea	-$13c(a6)                       ; a DTA of our own
	move.w	#$1a,-(sp)                      ; Fsetdta
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	clr.w	-(sp)                           ; argument 2
	move.l	8(a6),-(sp)                     ; the files the path chosen matches
	move.w	#$4e,-(sp)                      ; Fsfirst
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,-$a(a6)                      ; the result
	tst.w	-$a(a6)                         ; any?
	beq.s	multi_pack_found                ; yes
	clr.l	-(sp)                           ; no: M_ON
	move.w	#$101,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_no_files                  ; "No files found to pack!"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	move.w	#$1,d0                          ; 1
	bra.w	multi_pack_return
multi_pack_found:
	move.l	$10(a6),-(sp)                   ; the destination
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,-$c(a6)                      ; its length
	move.w	-$c(a6),d0
	subq.w	#3,d0                           ; less 3
	movea.l	$10(a6),a0
	clr.b	0(a0,d0.w)                      ; "*.*" cut off
	move.l	$c(a6),-(sp)                    ; the source
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,-$c(a6)
	move.w	-$c(a6),d0
	subq.w	#3,d0                           ; less 3
	movea.l	$c(a6),a0
	clr.b	0(a0,d0.w)                      ; "*.*" cut off
	move.l	$10(a6),-(sp)                   ; the destination
	pea	-$90(a6)                        ; kept
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	move.l	$c(a6),-(sp)                    ; the source
	pea	-$110(a6)                       ; kept
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$11e(a6)                       ; the name found
	move.l	$10(a6),-(sp)                   ; after the destination folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	-$11e(a6)                       ; the name found
	move.l	$c(a6),-(sp)                    ; after the source folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.w	$14(a6),-(sp)                   ; programs?
	move.l	-$122(a6),-(sp)                 ; its length
	pea	-$11e(a6)                       ; the name
	move.l	$10(a6),-(sp)                   ; the destination file
	move.l	$c(a6),-(sp)                    ; the source file
	jsr	multi_pack_one                  ; pack it
	lea	$12(sp),sp                      ; drop the arguments
	bra.s	multi_pack_fsnext
multi_pack_next:
	pea	-$90(a6)                        ; the destination folder
	move.l	$10(a6),-(sp)                   ; back
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$110(a6)                       ; the source folder
	move.l	$c(a6),-(sp)                    ; back
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	-$11e(a6)                       ; the name found
	move.l	$10(a6),-(sp)                   ; after the destination folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	-$11e(a6)                       ; the name found
	move.l	$c(a6),-(sp)                    ; after the source folder
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	move.w	$14(a6),-(sp)                   ; programs?
	move.l	-$122(a6),-(sp)                 ; its length
	pea	-$11e(a6)                       ; the name
	move.l	$10(a6),-(sp)                   ; the destination file
	move.l	$c(a6),-(sp)                    ; the source file
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
report_page_title:
	pea	text_report_title               ; the title
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_page:
	pea	text_report_heading             ; "****** MULTI PACKER REPORT ******"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	text_report_underline           ; the underlining
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
	move.w	0(a0,d0.w),d0
	bra.w	report_reason_switch            ; which reason
report_too_small:
	pea	text_reason_too_small           ; "Too small - not worth compacting"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.w	report_next_line
report_larger:
	pea	text_reason_larger              ; "Packed file larger than original"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.w	report_next_line
report_read_error:
	pea	text_reason_read_error          ; "Error reading source file"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.w	report_next_line
report_write_error:
	pea	text_reason_write_error         ; "Error writing destination file"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
report_no_memory:
	pea	text_reason_no_memory           ; (and after a write error)
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.w	report_next_line
report_program:
	pea	text_reason_program             ; "Program file"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.w	report_next_line
report_aborted:
	pea	text_reason_aborted             ; "Pack aborted"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.w	report_next_line
report_unknown:
	pea	text_reason_unknown             ; "Unknown error"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.s	report_next_line
report_reason_switch:
	cmp.w	#$0,d0                          ; 0: a program
	beq.s	report_program
	cmp.w	#$1,d0                          ; 1: no memory
	beq.s	report_no_memory
	cmp.w	#$2,d0                          ; 2: read error
	beq.w	report_read_error
	cmp.w	#$3,d0                          ; 3: write error
	beq.w	report_write_error
	cmp.w	#$4,d0                          ; 4: larger
	beq.w	report_larger
	cmp.w	#$5,d0                          ; 5: too small
	beq.w	report_too_small
	cmp.w	#$6,d0                          ; 6: aborted
	beq.s	report_aborted
	jmp	report_unknown                  ; anything else
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
	pea	text_press_return               ; "Press any key to continue"
	move.w	#$9,-(sp)                       ; Cconws
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$1,-(sp)                       ; Cconin
	jsr	gemdos
	addq.l	#2,sp                           ; drop the arguments
	move.w	d0,-$a(a6)                      ; the key
report_next_page:
	addi.w	#$10,-$e(a6)                    ; 16 on
	clr.w	-$10(a6)                        ; line 0
report_pages_loop:
	move.w	-$e(a6),d0
	cmp.w	report_count,d0                 ; all shown?
	ble.w	report_page_title               ; no
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
multi_pack_return:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; multi_pack_one(source, destination, name, length, programs): files over 20 bytes are packed, programs only
; when programs is set; the rest are noted (0 a program left alone, 5 too small).
;------------------------------------------------------------------------------
multi_pack_one:	; from: multi_pack
	link	a6,#-8                          ; 8 bytes of locals
	move.l	$10(a6),-(sp)                   ; the name
	jsr	is_program_name                 ; a program name?
	addq.l	#4,sp                           ; drop the arguments
	move.l	d0,-$4(a6)
	cmpi.l	#$14,$14(a6)                    ; over 20 bytes?
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
; note_file(name, result): results 0-5 are noted for the report, 6 (aborted) only for the first 101.  Other
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
	beq.s	note_file_store                 ; yes
	cmpi.l	#$6,$c(a6)                      ; 6?
	bne.s	note_file_done                  ; no: packed
	cmpi.w	#$64,report_count               ; more than 100 noted?
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
; unpack_file(name): look in the first 2 K for 'LSD!', 'AUTM', 'LZH!', 'Ice!' or 'LZW!'.  When there is one
; the file is read from it, depacked with V2, LZH (with a 5000 byte work area of its own), ICE or LZW, and saved
; under a name chosen, with the mouse hidden meanwhile.  d0 = -1 when the file is not packed or cannot be read,
; 1 when there is not the memory, else 0.
;------------------------------------------------------------------------------
unpack_file:	; from: main
	link	a6,#-30                         ; 30 bytes of locals
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
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
	beq.s	unpack_file_unreadable          ; yes
	move.l	-$4(a6),-(sp)                   ; the buffer
	jsr	find_packed                     ; find the packed data
	addq.l	#4,sp                           ; drop the arguments
	move.l	d0,-$8(a6)
	cmpi.l	#$ffffffff,-$8(a6)              ; found?
	bne.s	unpack_file_found               ; yes
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1: not packed
	ext.l	d0                              ; to a long
	bra.w	unpack_file_done
unpack_file_found:
	bra.s	unpack_file_packed
unpack_file_unreadable:
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
unpack_file_failed:
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.w	unpack_file_done
unpack_file_packed:
	move.l	-$8(a6),-(sp)                   ; the packed data
	jsr	packed_algorithm                ; which algorithm
	addq.l	#4,sp                           ; drop the arguments
	move.w	d0,-$1e(a6)                     ; kept
	move.l	-$8(a6),d0
	sub.l	-$4(a6),d0                      ; less the buffer: its offset in the file
	move.l	d0,-$c(a6)                      ; kept
	move.l	-$8(a6),-(sp)                   ; the packed data
	jsr	unpacked_length                 ; its unpacked length
	addq.l	#4,sp                           ; drop the arguments
	move.l	d0,-$10(a6)                     ; kept
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
	cmpi.l	#$ffffffff,-$4(a6)              ; got it?
	bgt.s	unpack_file_read                ; yes
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; no: M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$1,d0                          ; 1: no memory
	ext.l	d0                              ; to a long
	bra.w	unpack_file_done
unpack_file_read:
	clr.w	-(sp)                           ; read only
	move.l	8(a6),-(sp)                     ; the file
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,-$1a(a6)                     ; the handle
	clr.w	-(sp)                           ; from the start
	move.w	-$1a(a6),-(sp)                  ; the handle
	move.l	-$c(a6),-(sp)                   ; to the packed data
	move.w	#$42,-(sp)                      ; Fseek
	jsr	gemdos
	lea	$a(sp),sp                       ; drop the arguments
	move.l	d0,-$14(a6)
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.l	#$f4240,-(sp)                   ; up to a million bytes
	move.w	-$1a(a6),-(sp)                  ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$14(a6)
	move.w	-$1a(a6),-(sp)                  ; the handle
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	pea	text_unpacking                  ; "Unpacking File...."
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	move.w	-$1e(a6),d0                     ; the algorithm
	bra.w	unpack_file_switch              ; which?
unpack_file_v2:
	move.l	-$4(a6),d0                      ; the packed data
	add.l	#$100,d0                        ; + 256: where it depacks to
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$4(a6),-(sp)                   ; argument 1
	jsr	depack_v2                       ; depack it
	addq.l	#8,sp                           ; drop the arguments
	bra.w	unpack_file_save
unpack_file_lzh:
	move.l	#$1388,-(sp)                    ; 5000 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$18(a6)                     ; LZH's work area
	tst.l	-$18(a6)                        ; got it?
	ble.s	unpack_file_no_work             ; no
	move.l	-$18(a6),-(sp)                  ; the work area
	move.l	-$4(a6),d0                      ; the packed data
	add.l	#$100,d0                        ; + 256: where it depacks to
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$4(a6),-(sp)                   ; the packed data
	jsr	depack_lzh                      ; depack it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	-$18(a6),-(sp)                  ; the work area
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.s	unpack_file_lzh_done
unpack_file_no_work:
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$1,d0                          ; 1: no memory
	ext.l	d0                              ; to a long
	bra.w	unpack_file_done
unpack_file_lzh_done:
	bra.w	unpack_file_save
unpack_file_ice:
	move.l	-$4(a6),d0                      ; the packed data
	add.l	#$100,d0                        ; + 256
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$4(a6),-(sp)                   ; argument 1
	jsr	depack_ice                      ; depack it
	addq.l	#8,sp                           ; drop the arguments
	bra.w	unpack_file_save
unpack_file_lzw:
	move.l	-$4(a6),d0                      ; the packed data
	add.l	#$100,d0                        ; + 256
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$4(a6),-(sp)                   ; the packed data
	jsr	depack_lzw                      ; depack it
	addq.l	#8,sp                           ; drop the arguments
	bra.w	unpack_file_save
unpack_file_unknown:
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_depack_error              ; "Fatal Error in Depack"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	fatal_alert                     ; and quit
	addq.l	#6,sp                           ; drop the arguments
	bra.s	unpack_file_save
unpack_file_switch:
	cmp.w	#$1,d0                          ; 1: V2
	beq.w	unpack_file_v2
	cmp.w	#$2,d0                          ; 2: LZH
	beq.w	unpack_file_lzh
	cmp.w	#$3,d0                          ; 3: ICE
	beq.s	unpack_file_ice
	cmp.w	#$4,d0                          ; 4: LZW
	beq.s	unpack_file_lzw
	jmp	unpack_file_unknown             ; anything else
unpack_file_save:
	pea	text_supply_save_path           ; "Supply the SAVE path and file name"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	pea	save_name                       ; the path chosen
	pea	pack_file_name                  ; the name
	pea	destination_path                ; the destination path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	move.w	d0,-$1c(a6)                     ; the button
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	cmpi.w	#$ffff,-$1c(a6)                 ; cancelled?
	beq.s	unpack_file_free                ; yes
	move.l	-$4(a6),d0                      ; the depacked data
	add.l	#$100,d0
	move.l	d0,-(sp)                        ; the depacked data
	move.l	-$10(a6),-(sp)                  ; its length
	pea	save_name                       ; the file
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
unpack_file_free:
	move.l	-$4(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$0,d0                          ; 0
	ext.l	d0                              ; to a long
unpack_file_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; packed_algorithm(data): 1 for 'LSD!' or 'AUTM' (V2), 2 for 'LZH!', 3 for 'Ice!', 4 for 'LZW!', else 0.
;------------------------------------------------------------------------------
packed_algorithm:	; from: unpack_file, depack_chunk
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.l	8(a6),d7                        ; the data
	movea.l	d7,a1
	move.l	(a1),d1                         ; the magic
	cmp.l	#$4c534421,d1                   ; 'LSD!'?
	beq.s	packed_algorithm_v2             ; yes
	cmp.l	#$4155544d,d1                   ; 'AUTM'?
	beq.s	packed_algorithm_v2             ; yes
	cmp.l	#$4c5a4821,d1                   ; 'LZH!'?
	beq.s	packed_algorithm_lzh            ; yes
	cmp.l	#$49636521,d1                   ; 'Ice!'?
	beq.s	packed_algorithm_ice            ; yes
	cmp.l	#$4c5a5721,d1                   ; 'LZW!'?
	beq.s	packed_algorithm_lzw            ; yes
	moveq	#0,d0                           ; 0: none
	bra.s	packed_algorithm_done
packed_algorithm_v2:
	moveq	#1,d0                           ; 1: V2
	bra.s	packed_algorithm_done
packed_algorithm_lzh:
	moveq	#2,d0                           ; 2: LZH
	bra.s	packed_algorithm_done
packed_algorithm_ice:
	moveq	#3,d0                           ; 3: ICE
	bra.s	packed_algorithm_done
packed_algorithm_lzw:
	moveq	#4,d0                           ; 4: LZW
packed_algorithm_done:
	unlk	a6                              ; the frame back
	rts
	movem.l	(sp)+,d7                        ; not reached
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; unpacked_length(data): the long after the magic, or after the packed length for 'Ice!'.
;------------------------------------------------------------------------------
unpacked_length:	; from: unpack_file
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.l	8(a6),d7                        ; the data
	movea.l	d7,a1
	move.l	(a1),d1                         ; the magic
	cmp.l	#$49636521,d1                   ; 'Ice!'?
	bne.s	unpacked_length_second          ; no
	move.l	8(a1),d0                        ; yes: the third long
	bra.s	unpacked_length_done
unpacked_length_second:
	move.l	4(a1),d0                        ; the second
unpacked_length_done:
	unlk	a6                              ; the frame back
	rts
	movem.l	(sp)+,d7                        ; not reached
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; find_packed(buffer): the address of the first 'LSD!', 'AUTM', 'LZH!', 'Ice!' or 'LZW!' among the first $401
; words, or -1.
;------------------------------------------------------------------------------
find_packed:	; from: unpack_file
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.l	8(a6),d7                        ; the buffer
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
	cmp.l	#$49636521,d1                   ; 'Ice!'?
	beq.s	find_packed_done                ; yes
	cmp.l	#$4c5a5721,d1                   ; 'LZW!'?
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
; Patch the four program stubs for the Flash and Heading check boxes: without Flash their colour writes
; become nops, without Heading their screen clearing and title printing do.  The original instructions are
; kept below as patterns (each stub writes a different register to the colour).
;------------------------------------------------------------------------------
set_stub_options:	; from: write_program
	link	a6,#-64                         ; 64 bytes of locals
	tst.w	flash_flag                      ; Flash?
	bne.s	set_stub_flash                  ; yes
	lea	v2_stub_flash,a0                ; the V2 stub's colour write
	move.l	a0,-$4(a6)
	lea	lzh_stub_flash,a0               ; the LZH stub's
	move.l	a0,-$8(a6)
	lea	lzw_stub_flash,a0               ; the LZW stub's
	move.l	a0,-$c(a6)
	lea	ice_stub_flash,a0               ; the ICE stub's
	move.l	a0,-$10(a6)
	movea.l	-$4(a6),a0                      ; nop nop
	move.l	#$4e714e71,(a0)
	movea.l	-$8(a6),a0                      ; nop nop
	move.l	#$4e714e71,(a0)
	movea.l	-$c(a6),a0                      ; nop nop
	move.l	#$4e714e71,(a0)
	movea.l	-$10(a6),a0                     ; nop nop
	move.l	#$4e714e71,(a0)
	bra.s	set_stub_heading
set_stub_flash:
	lea	v2_stub_flash,a0                ; the V2 stub's colour write
	move.l	a0,-$14(a6)
	lea	lzh_stub_flash,a0               ; the LZH stub's
	move.l	a0,-$18(a6)
	lea	lzw_stub_flash,a0               ; the LZW stub's
	move.l	a0,-$1c(a6)
	lea	ice_stub_flash,a0               ; the ICE stub's
	move.l	a0,-$20(a6)
	movea.l	-$14(a6),a0                     ; V2's
	lea	stub_flash_d7(pc),a1            ; its pattern
	move.l	(a1)+,(a0)+                     ; put back
	movea.l	-$18(a6),a0                     ; LZH's
	lea	stub_flash_d3(pc),a1            ; its pattern
	move.l	(a1)+,(a0)+                     ; put back
	movea.l	-$1c(a6),a0                     ; LZW's
	lea	stub_flash_d0(pc),a1            ; its pattern
	move.l	(a1)+,(a0)+                     ; put back
	movea.l	-$20(a6),a0                     ; ICE's
	lea	stub_flash_d7(pc),a1            ; the same as V2's
	move.l	(a1)+,(a0)+                     ; put back
	bra.s	set_stub_heading
stub_flash_d7:
	move.w	d7,$ffff8240.w                  ; palette 0, V2's and ICE's colour write
stub_flash_d3:
	move.w	d3,$ffff8240.w                  ; palette 0, LZH's
stub_flash_d0:
	move.w	d0,$ffff8240.w                  ; palette 0, LZW's
set_stub_heading:
	tst.w	heading_flag                    ; Heading?
	bne.w	set_stub_heading_on             ; yes
	lea	v2_stub_clear,a0                ; no: the screen clearing
	move.l	a0,-$24(a6)
	lea	lzh_stub_clear,a0
	move.l	a0,-$28(a6)
	lea	lzw_stub_clear,a0
	move.l	a0,-$2c(a6)
	lea	ice_stub_clear,a0
	move.l	a0,-$30(a6)
	movea.l	-$24(a6),a0                     ; a nop
	move.w	#$4e71,(a0)
	movea.l	-$28(a6),a0
	move.w	#$4e71,(a0)
	movea.l	-$2c(a6),a0
	move.w	#$4e71,(a0)
	movea.l	-$30(a6),a0
	move.w	#$4e71,(a0)
	lea	v2_stub_print,a0                ; and the title printing
	move.l	a0,-$24(a6)
	lea	lzh_stub_print,a0
	move.l	a0,-$28(a6)
	lea	lzw_stub_print,a0
	move.l	a0,-$2c(a6)
	lea	ice_stub_print,a0
	move.l	a0,-$30(a6)
	movea.l	-$24(a6),a0                     ; a nop
	move.w	#$4e71,(a0)
	movea.l	-$28(a6),a0
	move.w	#$4e71,(a0)
	movea.l	-$2c(a6),a0
	move.w	#$4e71,(a0)
	movea.l	-$30(a6),a0
	move.w	#$4e71,(a0)
	bra.w	set_stub_done
set_stub_heading_on:
	lea	v2_stub_clear,a0                ; the screen clearing
	move.l	a0,-$34(a6)
	lea	lzh_stub_clear,a0
	move.l	a0,-$38(a6)
	lea	lzw_stub_clear,a0
	move.l	a0,-$3c(a6)
	lea	ice_stub_clear,a0
	move.l	a0,-$40(a6)
	lea	stub_clear_pattern(pc),a1       ; its pattern
	movea.l	-$34(a6),a0                     ; put back
	move.w	(a1),(a0)
	movea.l	-$38(a6),a0
	move.w	(a1),(a0)
	movea.l	-$3c(a6),a0
	move.w	(a1),(a0)
	movea.l	-$40(a6),a0
	move.w	(a1),(a0)
	bra.s	set_stub_print
stub_clear_pattern:
	clr.l	(a2)+                           ; the stubs' screen clearing
set_stub_print:
	lea	v2_stub_print,a0                ; the title printing
	move.l	a0,-$34(a6)
	lea	lzh_stub_print,a0
	move.l	a0,-$38(a6)
	lea	lzw_stub_print,a0
	move.l	a0,-$3c(a6)
	lea	ice_stub_print,a0
	move.l	a0,-$40(a6)
	movea.l	-$34(a6),a0                     ; trap #1 put back
	move.w	#$4e41,(a0)
	movea.l	-$38(a6),a0
	move.w	#$4e41,(a0)
	movea.l	-$3c(a6),a0
	move.w	#$4e41,(a0)
	movea.l	-$40(a6),a0
	move.w	#$4e41,(a0)
set_stub_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; write_program(name, packed length, unpacked length, data): write a packed program: a PRG header whose text
; is the stub (V2, LZH, LZW or ICE, with the options patched in), whose data is the packed data (made even)
; and whose BSS leaves room to depack (the unpacked length less the packed length, + $180, + $13c4 more for
; LZH's tables), then a 0 long for the relocation table.  d0 = 0, or -1 on error.
;------------------------------------------------------------------------------
write_program:	; from: pack_file, multi_pack_file
	link	a6,#-44                         ; 44 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.l	$c(a6),d7                       ; the packed length
	move.l	$10(a6),d6                      ; the unpacked length
	move.l	$14(a6),d5                      ; the data
	clr.l	-$20(a6)                        ; the relocation long: 0
	pea	text_saving_executable          ; "Saving Executable File"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	jsr	set_stub_options                ; patch the stubs
	move.w	#$601a,-$2(a6)                  ; the header: $601a
	clr.w	d4                              ; the rest of it: 11 words of 0
	bra.s	write_program_clear_loop
write_program_clear:
	move.w	d4,d0
	asl.w	#1,d0                           ; words
	lea	-$18(a6),a0                     ; the header's last 22 bytes
	clr.w	0(a0,d0.w)                      ; cleared
	addq.w	#1,d4
write_program_clear_loop:
	cmpi.w	#$b,d4                          ; 11?
	blt.s	write_program_clear
	move.l	d6,d0                           ; the unpacked length
	sub.l	d7,d0                           ; less the packed length
	add.l	#$100,d0                        ; + 256
	add.l	#$80,d0                         ; + 128
	move.l	d0,-$2c(a6)                     ; is the BSS length
	move.w	algorithm,d0                    ; the algorithm
	bra.w	write_program_stub_switch       ; which stub?
write_program_v2:
	lea	v2_stub+$2da,a0                 ; the end of the V2 stub
	move.l	a0,d0
	lea	v2_stub,a0                      ; less its start
	sub.l	a0,d0
	move.l	d0,-$1c(a6)                     ; the stub's length
	bra.w	write_program_header
write_program_lzh:
	addi.l	#$13c4,-$2c(a6)                 ; more BSS for the depacker's tables
	lea	lzh_stub+$48e,a0
	move.l	a0,d0
	lea	lzh_stub,a0                     ; less its start
	sub.l	a0,d0
	move.l	d0,-$1c(a6)                     ; the stub's length
	bra.w	write_program_header
write_program_lzw:
	lea	lzw_stub+$204,a0                ; the end of the LZW stub
	move.l	a0,d0
	lea	lzw_stub,a0                     ; less its start
	sub.l	a0,d0
	move.l	d0,-$1c(a6)                     ; the stub's length
	bra.w	write_program_header
write_program_ice:
	lea	ice_stub+$2ac,a0                ; the end of the ICE stub
	move.l	a0,d0
	lea	ice_stub,a0                     ; less its start
	sub.l	a0,d0
	move.l	d0,-$1c(a6)                     ; the stub's length
	bra.s	write_program_header
write_program_stub_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.s	write_program_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.s	write_program_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.s	write_program_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	write_program_lzw
write_program_header:
	move.l	-$1c(a6),-$24(a6)               ; the text length: the stub's
	move.l	d7,d0                           ; the packed length
	btst	#$0,d0                          ; odd?
	beq.s	write_program_create            ; no
	addq.l	#1,d7                           ; yes: one more
write_program_create:
	move.l	d7,-$28(a6)                     ; the data length
	clr.w	-(sp)                           ; normal
	move.l	8(a6),-(sp)                     ; the name
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,d4                           ; the handle
	tst.w	d4                              ; created?
	bge.s	write_program_magic             ; yes
	move.w	#$ffff,d0                       ; no: -1
	ext.l	d0                              ; to a long
	bra.w	write_program_done
write_program_magic:
	pea	-$2(a6)                         ; the magic
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	pea	-$24(a6)                        ; the text length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	pea	-$28(a6)                        ; the data length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	pea	-$2c(a6)                        ; the BSS length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	pea	-$18(a6)                        ; the rest of the header
	move.l	#$e,-(sp)                       ; 14 bytes
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	move.w	algorithm,d0                    ; the algorithm
	bra.w	write_program_write_switch      ; which stub?
write_program_write_v2:
	pea	v2_stub                         ; the V2 stub
	move.l	-$1c(a6),-(sp)                  ; its length
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	bra.w	write_program_data
write_program_write_lzh:
	pea	lzh_stub                        ; the LZH stub
	move.l	-$1c(a6),-(sp)                  ; its length
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	bra.w	write_program_data
write_program_write_lzw:
	pea	lzw_stub                        ; the LZW stub
	move.l	-$1c(a6),-(sp)                  ; its length
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	bra.w	write_program_data
write_program_write_ice:
	pea	ice_stub                        ; the ICE stub
	move.l	-$1c(a6),-(sp)                  ; its length
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	bra.s	write_program_data
write_program_write_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.s	write_program_write_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	write_program_write_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.s	write_program_write_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	write_program_write_lzw
write_program_data:
	move.l	d5,-(sp)                        ; the packed data
	move.l	d7,-(sp)                        ; its length
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	d7,d0                           ; all written?
	beq.s	write_program_relocation        ; yes
	move.w	d4,-(sp)                        ; no: the handle
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.s	write_program_done
write_program_relocation:
	pea	-$20(a6)                        ; the 0 long
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d4,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	write_program_close             ; yes
	move.w	d4,-(sp)                        ; no: the handle
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$ffff,d0                       ; -1
	ext.l	d0                              ; to a long
	bra.s	write_program_done
write_program_close:
	move.w	d4,-(sp)                        ; the handle
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
; pack_file(name, length, program, shown name): load the file 2 K into a buffer and pack it with V2, LZH, ICE
; or LZW (LZW with a work area of its own), drawing the packometer and the pack info.  When it got smaller
; (the LZH stub and the header counted for a program, whichever the method) the sizes are shown and it is
; saved under a name chosen.  d0 = 1 no memory, 2 read error, 3 save given up, 4 not smaller, 6 aborted,
; 0 cancelled, otherwise the packed length.
;------------------------------------------------------------------------------
pack_file:	; from: pack_one_file
	link	a6,#-24                         ; 24 bytes of locals
	move.l	$c(a6),d0                       ; the length
	add.l	#$2000,d0                       ; + 8 K
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$48,-(sp)                      ; the function
	jsr	gemdos                          ; Malloc
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$c(a6)                      ; the buffer
	cmpi.l	#$ffffffff,-$c(a6)              ; got it?
	bgt.s	pack_file_buffer                ; yes
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
	move.w	algorithm,d0                    ; the algorithm
	bra.w	pack_file_switch                ; which?
pack_file_v2:
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
	bra.w	pack_file_packed
pack_file_lzh:
	pea	-$14(a6)                        ; where the address goes
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzh                        ; pack it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	bra.w	pack_file_packed
pack_file_ice:
	move.l	v2_window,-(sp)                 ; the window
	move.l	-$c(a6),-(sp)                   ; the buffer: where it packs to
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_ice                        ; pack it
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	bra.w	pack_file_packed
pack_file_lzw:
	move.l	#$8534,-(sp)                    ; $8534 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$10(a6)                     ; LZW's work area
	tst.l	-$10(a6)                        ; got it?
	ble.s	pack_file_no_work               ; no
	pea	-$14(a6)                        ; where the address goes
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$10(a6),-(sp)                  ; the work area
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzw                        ; pack it
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	move.l	-$10(a6),-(sp)                  ; the work area
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.s	pack_file_lzw_done
pack_file_no_work:
	move.w	#$1,d0                          ; 1: no memory
	ext.l	d0                              ; to a long
	bra.w	pack_file_done
pack_file_lzw_done:
	bra.s	pack_file_packed
pack_file_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.w	pack_file_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	pack_file_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.w	pack_file_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	pack_file_lzw
pack_file_packed:
	tst.l	-$8(a6)                         ; packed?
	ble.s	pack_file_aborted               ; no: aborted
	pea	text_pack_complete              ; "Pack Complete!"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	bra.s	pack_file_check_program
pack_file_aborted:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$6,d0                          ; 6: aborted
	ext.l	d0                              ; to a long
	bra.w	pack_file_done
pack_file_check_program:
	cmpi.w	#$1,$10(a6)                     ; a program?
	bne.s	pack_file_check_data            ; no
	lea	lzh_stub+$48e,a0                ; the end of the LZH stub
	move.l	a0,d1
	lea	lzh_stub,a0                     ; less its start
	sub.l	a0,d1                           ; = its length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	add.l	d1,d0                           ; + the stub
	cmp.l	$c(a6),d0                       ; smaller?
	blt.s	pack_file_smaller               ; yes
pack_file_check_data:
	tst.w	$10(a6)                         ; data?
	bne.w	pack_file_not_smaller
	move.l	-$8(a6),d0                      ; the packed length
	cmp.l	$c(a6),d0                       ; smaller?
	bge.w	pack_file_not_smaller
pack_file_smaller:
	cmpi.w	#$1,$10(a6)                     ; a program?
	bne.w	pack_file_info_data
	move.w	algorithm,d0                    ; the algorithm
	bra.w	pack_file_size_switch           ; which stub?
pack_file_size_v2:
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	v2_stub+$2da,a0                 ; the end of the V2 stub
	add.l	a0,d0                           ; + the end of the stub
	lea	v2_stub,a0
	sub.l	a0,d0                           ; less its start
	move.l	d0,-(sp)                        ; = the file's length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.w	pack_file_info_shown
pack_file_size_lzh:
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	lzh_stub+$48e,a0                ; the end of the LZH stub
	add.l	a0,d0                           ; + the end of the stub
	lea	lzh_stub,a0
	sub.l	a0,d0                           ; less its start
	move.l	d0,-(sp)                        ; = the file's length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.w	pack_file_info_shown
pack_file_size_lzw:
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	lzw_stub+$204,a0                ; the end of the LZW stub
	add.l	a0,d0                           ; + the end of the stub
	lea	lzw_stub,a0
	sub.l	a0,d0                           ; less its start
	move.l	d0,-(sp)                        ; = the file's length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.w	pack_file_info_shown
pack_file_size_ice:
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	ice_stub+$2ac,a0                ; the end of the ICE stub
	add.l	a0,d0                           ; + the end of the stub
	lea	ice_stub,a0                     ; less its start
	sub.l	a0,d0                           ; = the file's length
	move.l	d0,-(sp)                        ; show the sizes
	jsr	show_pack_sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.s	pack_file_info_shown
	bra.s	pack_file_info_shown
pack_file_size_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.w	pack_file_size_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	pack_file_size_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.s	pack_file_size_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	pack_file_size_lzw
pack_file_info_shown:
	bra.s	pack_file_info_ok
pack_file_info_data:
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
pack_file_info_ok:
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	clr.w	-(sp)                           ; no edit object
	move.l	tree_info,-(sp)                 ; the pack info: wait for OK
	jsr	form_do
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	movea.l	tree_info,a0                    ; OK's state
	move.w	$b2(a0),d0
	and.w	#$fffe,d0                       ; deselected
	move.w	d0,-$18(a6)
	move.w	#$1,-(sp)                       ; redraw
	move.w	-$18(a6),-(sp)                  ; the new state
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
pack_file_choose:
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
pack_file_save:
	pea	save_name                       ; the path chosen
	pea	pack_file_name                  ; the name
	pea	destination_path                ; the destination path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	ext.l	d0                              ; the button
	move.l	d0,-$4(a6)
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	cmpi.l	#$ffffffff,-$4(a6)              ; cancelled?
	beq.w	pack_file_cancelled             ; yes
	clr.w	-$16(a6)                        ; no alert answer yet
	tst.w	$10(a6)                         ; a program?
	bne.w	pack_file_write_program         ; yes
	move.w	algorithm,d0                    ; the algorithm
	bra.w	pack_file_save_switch           ; which?
pack_file_save_v2:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	pack_file_saved
pack_file_save_ice:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	pack_file_saved
pack_file_save_lzh:
	move.l	-$14(a6),-(sp)                  ; the packed data
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	pack_file_saved
pack_file_save_lzw:
	move.l	-$14(a6),-(sp)                  ; the packed data
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
pack_file_saved_data:
	bra.s	pack_file_saved
pack_file_save_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.s	pack_file_save_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	pack_file_save_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.s	pack_file_save_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	pack_file_save_lzw
pack_file_saved:
	bra.w	pack_file_written
pack_file_write_program:
	move.w	algorithm,d0                    ; the algorithm
	bra.w	pack_file_program_switch        ; which?
pack_file_program_v2:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	write_program                   ; as a program
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	pack_file_written
pack_file_program_ice:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	write_program                   ; as a program
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	pack_file_written
pack_file_program_lzh:
	move.l	-$14(a6),-(sp)                  ; the packed data
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	write_program                   ; as a program
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	pack_file_written
pack_file_program_lzw:
	move.l	-$14(a6),-(sp)                  ; the packed data
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	pea	save_name                       ; the file
	jsr	write_program                   ; as a program
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$4(a6)
	bra.s	pack_file_written
pack_file_program_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.s	pack_file_program_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	pack_file_program_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.s	pack_file_program_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	pack_file_program_lzw
pack_file_written:
	bra.s	pack_file_check_save
pack_file_cancelled:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$0,d0                          ; 0: cancelled
	ext.l	d0                              ; to a long
	bra.w	pack_file_done
pack_file_check_save:
	cmpi.l	#$ffffffff,-$4(a6)              ; failed?
	bne.s	pack_file_answer                ; no
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_save_failure              ; "Save Failure!"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert                      ; Retry or Abort
	addq.l	#6,sp                           ; drop the arguments
	move.w	d0,-$16(a6)                     ; the answer
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; M_OFF
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
pack_file_answer:
	cmpi.w	#$2,-$16(a6)                    ; Abort?
	bne.s	pack_file_retry                 ; no
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$3,d0                          ; 3
	ext.l	d0                              ; to a long
	bra.s	pack_file_done
pack_file_retry:
	cmpi.w	#$1,-$16(a6)                    ; Retry?
	bne.s	pack_file_end                   ; no
	cmpi.l	#$ffffffff,-$4(a6)              ; and it failed?
	beq.w	pack_file_choose                ; yes: again
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
load_file:	; from: pack_one_file, unpack_file, pack_file, multi_pack_file
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
	link	a6,#-24                         ; 24 bytes of locals
	move.l	$10(a6),d0                      ; the length
	add.l	#$2000,d0                       ; + 8 K
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$48,-(sp)                      ; the function
	jsr	gemdos                          ; Malloc
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$c(a6)                      ; the buffer
	cmpi.l	#$ffffffff,-$c(a6)              ; got it?
	bgt.s	multi_pack_file_buffer          ; yes
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
	move.w	algorithm,d0                    ; the algorithm
	bra.w	multi_pack_file_switch          ; which?
multi_pack_file_v2:
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
	bra.w	multi_pack_file_packed
multi_pack_file_lzh:
	pea	-$10(a6)                        ; where the address goes
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzh                        ; pack it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	bra.w	multi_pack_file_packed
multi_pack_file_ice:
	move.l	v2_window,-(sp)                 ; the window
	move.l	-$c(a6),-(sp)                   ; the buffer: where it packs to
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_ice                        ; pack it
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	bra.w	multi_pack_file_packed
multi_pack_file_lzw:
	move.l	#$8534,-(sp)                    ; $8534 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$14(a6)                     ; LZW's work area
	tst.l	-$14(a6)                        ; got it?
	ble.s	multi_pack_file_no_work         ; no
	pea	-$10(a6)                        ; where the address goes
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$14(a6),-(sp)                  ; the work area
	move.l	-$c(a6),d0                      ; the loaded file
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzw                        ; pack it
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	move.l	-$14(a6),-(sp)                  ; the work area
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	bra.s	multi_pack_file_lzw_done
multi_pack_file_no_work:
	move.l	-$c(a6),-(sp)                   ; argument 1
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$1,d0                          ; 1: no memory
	ext.l	d0                              ; to a long
	bra.w	multi_pack_file_done
multi_pack_file_lzw_done:
	bra.s	multi_pack_file_packed
multi_pack_file_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.w	multi_pack_file_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	multi_pack_file_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.w	multi_pack_file_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.w	multi_pack_file_lzw
multi_pack_file_packed:
	tst.l	-$8(a6)                         ; packed?
	bge.s	multi_pack_file_check_program
multi_pack_file_aborted:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$6,d0                          ; 6: aborted
	ext.l	d0                              ; to a long
	bra.w	multi_pack_file_done
multi_pack_file_check_program:
	cmpi.w	#$1,$14(a6)                     ; a program?
	bne.s	multi_pack_file_check_data      ; no
	lea	lzh_stub+$48e,a0                ; the end of the LZH stub
	move.l	a0,d1
	lea	lzh_stub,a0                     ; less its start
	sub.l	a0,d1                           ; = its length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	add.l	d1,d0                           ; + the stub
	cmp.l	$10(a6),d0                      ; smaller?
	blt.s	multi_pack_file_smaller         ; yes
multi_pack_file_check_data:
	tst.w	$14(a6)                         ; data?
	bne.w	multi_pack_file_not_smaller
	move.l	-$8(a6),d0                      ; the packed length
	cmp.l	$10(a6),d0                      ; smaller?
	bge.w	multi_pack_file_not_smaller
multi_pack_file_smaller:
	cmpi.w	#$1,$14(a6)                     ; a program?
	bne.w	multi_pack_file_info_data
	move.w	algorithm,d0                    ; the algorithm
	bra.w	multi_pack_file_size_switch     ; which stub?
multi_pack_file_size_v2:
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	v2_stub+$2da,a0                 ; the end of the V2 stub
	add.l	a0,d0                           ; + the end of the stub
	lea	v2_stub,a0
	sub.l	a0,d0                           ; less its start
	move.l	d0,-(sp)                        ; = the file's length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.w	multi_pack_file_info_shown
multi_pack_file_size_lzh:
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	lzh_stub+$48e,a0                ; the end of the LZH stub
	add.l	a0,d0                           ; + the end of the stub
	lea	lzh_stub,a0
	sub.l	a0,d0                           ; less its start
	move.l	d0,-(sp)                        ; = the file's length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.w	multi_pack_file_info_shown
multi_pack_file_size_lzw:
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	lzw_stub+$204,a0                ; the end of the LZW stub
	add.l	a0,d0                           ; + the end of the stub
	lea	lzw_stub,a0
	sub.l	a0,d0                           ; less its start
	move.l	d0,-(sp)                        ; = the file's length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.w	multi_pack_file_info_shown
multi_pack_file_size_ice:
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),d0                      ; the packed length
	add.l	#$20,d0                         ; + the header
	lea	ice_stub+$2ac,a0                ; the end of the ICE stub
	add.l	a0,d0                           ; + the end of the stub
	lea	ice_stub,a0                     ; less its start
	sub.l	a0,d0                           ; = the file's length
	move.l	d0,-(sp)                        ; argument 1
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
	bra.s	multi_pack_file_info_shown
	bra.s	multi_pack_file_info_shown
multi_pack_file_size_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.w	multi_pack_file_size_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	multi_pack_file_size_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.s	multi_pack_file_size_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	multi_pack_file_size_lzw
multi_pack_file_info_shown:
	bra.s	multi_pack_file_save
multi_pack_file_info_data:
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	jsr	show_pack_sizes                 ; show the sizes
	addq.l	#8,sp                           ; drop the arguments
multi_pack_file_save:
	tst.w	$14(a6)                         ; a program?
	bne.w	multi_pack_file_write_program   ; yes
	move.w	algorithm,d0                    ; the algorithm
	bra.w	multi_pack_file_save_switch     ; which?
multi_pack_file_save_v2:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; the destination
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	multi_pack_file_written
multi_pack_file_save_ice:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; argument 1
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	multi_pack_file_written
multi_pack_file_save_lzh:
	move.l	-$10(a6),-(sp)                  ; the packed data
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; argument 1
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	multi_pack_file_written
multi_pack_file_save_lzw:
	move.l	-$10(a6),-(sp)                  ; the packed data
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; the destination
	jsr	save_file                       ; save it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$4(a6)
multi_pack_file_saved_data:
	bra.s	multi_pack_file_written
multi_pack_file_save_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.s	multi_pack_file_save_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	multi_pack_file_save_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.s	multi_pack_file_save_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	multi_pack_file_save_lzw
multi_pack_file_written:
	bra.w	multi_pack_file_check_save
multi_pack_file_write_program:
	move.w	algorithm,d0                    ; the algorithm
	bra.w	multi_pack_file_program_switch  ; which?
multi_pack_file_program_v2:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; argument 1
	jsr	write_program                   ; as a program
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	multi_pack_file_check_save
multi_pack_file_program_ice:
	move.l	-$c(a6),-(sp)                   ; the buffer
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; argument 1
	jsr	write_program                   ; as a program
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	multi_pack_file_check_save
multi_pack_file_program_lzh:
	move.l	-$10(a6),-(sp)                  ; the packed data
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; argument 1
	jsr	write_program                   ; as a program
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$4(a6)
	bra.w	multi_pack_file_check_save
multi_pack_file_program_lzw:
	move.l	-$10(a6),-(sp)                  ; the packed data
	move.l	$10(a6),-(sp)                   ; the length
	move.l	-$8(a6),-(sp)                   ; the packed length
	move.l	$c(a6),-(sp)                    ; argument 1
	jsr	write_program                   ; as a program
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$4(a6)
	bra.s	multi_pack_file_check_save
multi_pack_file_program_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.s	multi_pack_file_program_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	multi_pack_file_program_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.s	multi_pack_file_program_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	multi_pack_file_program_lzw
multi_pack_file_check_save:
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
; depack_ice(packed, destination): depack 'Ice!' data in supervisor mode, keeping the background colour.
; d0 = the unpacked length.
;------------------------------------------------------------------------------
depack_ice:	; from: unpack_file, depack_chunk
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the packed data
	move.l	$c(a6),d6                       ; the destination
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	depack_ice_colour(pc),a0        ; the background colour
	move.w	$ffff8240.w,(a0)                ; palette 0, palette 0, kept
	movea.l	d7,a0                           ; a0 = the packed data
	movea.l	d6,a1                           ; a1 = the destination
	lea	depack_ice_ssp(pc),a2           ; the old stack
	move.l	d0,(a2)                         ; kept
	move.l	8(a0),-(sp)                     ; the unpacked length, kept
	move.l	$bc.w,-(sp)                     ; the trap #15 vector, kept
	bsr.s	ice_depack                      ; depack
	move.l	(sp)+,$bc.w                     ; the vector back
	move.l	(sp)+,d7                        ; d7 = the unpacked length
	move.w	depack_ice_colour(pc),$ffff8240.w ; palette 0, palette 0, the colour back
	move.l	depack_ice_ssp(pc),-(sp)        ; Super(old stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d7,d0                           ; returned
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	unlk	a6                              ; the frame back
	rts
depack_ice_ssp:
	dc.l	$00000000                       ; the stack Super returned
depack_ice_colour:
	dc.w	$0000                           ; the background colour

;------------------------------------------------------------------------------
; ice_depack: depack 'Ice!' data (a0 = it) to a1: the magic, the packed length and the unpacked
; length, then a bit stream read from the end down, the output written from its end down.  The
; background colour follows the bits as it goes.
;------------------------------------------------------------------------------
ice_depack:	; from: depack_ice
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	bsr.s	ice_read_long                   ; the magic
	cmpi.l	#$49636521,d0                   ; 'Ice!'?
	bne.s	ice_depack_done                 ; no: done
	bsr.s	ice_read_long                   ; the packed length
	lea	-$8(a0,d0.l),a5                 ; a5 = the packed data's end
	bsr.s	ice_read_long                   ; the unpacked length
	move.l	d0,(sp)                         ; returned in d0
	movea.l	a1,a4                           ; a4 = the destination
	movea.l	a1,a6                           ; a6 = it
	adda.l	d0,a6                           ; + the length: its end
	movea.l	a6,a3
	move.b	-(a5),d7                        ; the last byte: the first bits
	bsr.s	ice_literals                    ; depack
ice_depack_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts

;------------------------------------------------------------------------------
; ice_read_long: d0 = the next 4 bytes at a0, high byte first.
;------------------------------------------------------------------------------
ice_read_long:	; from: ice_depack
	moveq	#3,d1                           ; d0 = the next 4 bytes
ice_read_long_loop:
	lsl.l	#8,d0
	move.b	(a0)+,d0
	dbra	d1,ice_read_long_loop
	rts

;------------------------------------------------------------------------------
; ice_literals: a 1 bit means literals, their count coded; then, until the output's start is reached, a
; string (ice_string).
;------------------------------------------------------------------------------
ice_literals:	; from: ice_depack, ice_bits
	bsr.s	ice_bit                         ; a 1 bit: literals first?
	bcc.s	ice_next                        ; no
ice_flash:
	move.w	d7,$ffff8240.w                  ; palette 0, the background
	moveq	#0,d1                           ; one literal
	bsr.s	ice_bit                         ; a 1 bit: more?
	bcc.s	ice_copy_literals               ; no
	lea	ice_literal_bases(pc),a1        ; the literal count codes
	moveq	#4,d3                           ; 5 of them
ice_literal_code:
	move.l	-(a1),d0                        ; the next: its bit count and its all-ones value
	bsr.s	ice_bits                        ; read
	swap	d0                              ; the value
	cmp.w	d0,d1                           ; all ones: the next code
	dbne	d3,ice_literal_code
	add.l	$14(a1),d1                      ; + its base
ice_copy_literals:
	move.b	-(a5),-(a6)                     ; a literal
	dbra	d1,ice_copy_literals            ; for the count
ice_next:
	cmpa.l	a4,a6                           ; all done?
	bgt.s	ice_string                      ; no: a string
	rts                                     ; yes

;------------------------------------------------------------------------------
; ice_bit: the next bit of the stream (d7) into x and c, a new byte from the end down when needed.
;------------------------------------------------------------------------------
ice_bit:	; from: ice_literals, ice_bits
	add.b	d7,d7                           ; the next bit into x and c
	bne.s	ice_bit_got                     ; the byte still has bits
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7                           ; with a 1 bit to mark its end
ice_bit_got:
	rts

;------------------------------------------------------------------------------
; ice_bits: d1 = the next d0 + 1 bits of the stream.
;------------------------------------------------------------------------------
ice_bits:	; from: ice_literals
	moveq	#0,d1                           ; d1 = the next d0 + 1 bits
ice_bits_loop:
	add.b	d7,d7                           ; the next bit
	bne.s	ice_bits_got                    ; the byte still has bits
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7
ice_bits_got:
	addx.w	d1,d1                           ; into d1
	dbra	d0,ice_bits_loop
	rts
ice_string:	; from: ice_literals
	lea	ice_length_table(pc),a1         ; the length codes
	moveq	#3,d2                           ; up to 4 bits
ice_length_code:
	bsr.s	ice_bit                         ; a 1 bit: a longer code
	dbcc	d2,ice_length_code
	moveq	#0,d4                           ; d4 = the length
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the extra bits
	ext.w	d0                              ; to a word
	bmi.s	ice_length                      ; none
	bsr.s	ice_bits                        ; read
ice_length:
	move.b	6(a1,d2.w),d4                   ; + the base
	add.w	d1,d4
	beq.s	ice_short_offset                ; 0: a 2 byte string
	lea	ice_offset_table(pc),a1         ; the offset codes
	moveq	#1,d2                           ; up to 2 bits
ice_offset_code:
	bsr.s	ice_bit                         ; a 1 bit: a longer code
	dbcc	d2,ice_offset_code
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the offset's bit count
	ext.w	d0                              ; to a word
	bsr.s	ice_bits                        ; read
	add.w	d2,d2                           ; words
	add.w	6(a1,d2.w),d1                   ; + the base
	bpl.s	ice_copy_string                 ; positive: done
	sub.w	d4,d1                           ; negative: less the length
	bra.s	ice_copy_string
ice_short_offset:
	moveq	#0,d1                           ; a 2 byte string
	moveq	#5,d0                           ; 6 bits
	moveq	#-1,d2                          ; less one
	bsr.s	ice_bit                         ; a 1 bit: more?
	bcc.s	ice_short_offset_bits           ; no
	moveq	#8,d0                           ; yes: 9 bits
	moveq	#63,d2                          ; plus 63
ice_short_offset_bits:
	bsr.s	ice_bits                        ; read
	add.w	d2,d1                           ; + the base
ice_copy_string:
	lea	2(a6,d4.w),a1                   ; from where it was
	adda.w	d1,a1
	move.b	-(a1),-(a6)                     ; the first byte
ice_copy_string_loop:
	move.b	-(a1),-(a6)                     ; the rest
	dbra	d4,ice_copy_string_loop
	bra.w	ice_literals                    ; then literals again

;------------------------------------------------------------------------------
; The literal count, length and offset codes: a code is a run of 1 bits ended by a 0 (or the
; longest run), then a value of a set number of bits, added to its base.
;------------------------------------------------------------------------------
ice_literal_codes:
	dc.l	$7fff000e,$00ff0007,$00070002,$00030001 ; the literal count codes: bit count less one and all-ones value
	dc.l	$00030001
ice_literal_bases:	; from: ice_literals
	dc.l	$0000010d,$0000000e,$00000007,$00000004 ; their bases, less one
	dc.l	$00000001
ice_length_table:	; from: ice_bits
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; the length codes: extra bits less one, then bases less one
ice_offset_table:	; from: ice_bits
	dc.b	$0b,$04,$07,$00                 ; the offset codes: bit counts less one, then bases
	dc.w	$011f,$ffff,$001f
	dc.w	$4cdf,$00c0,$4e5e,$4e75         ; not used: left-over code (movem.l (sp)+,d6-d7, unlk a6, rts)

;------------------------------------------------------------------------------
; pack_ice(source, length, destination, window): pack with the ICE algorithm, a packer in assembly for
; 'Ice!' data, drawing the packometer's bar on the screen as it goes.  Holding Alternate aborts it.
; d0 = the packed length, or -1 when aborted.
;------------------------------------------------------------------------------
pack_ice:	; from: pack_file, multi_pack_file, pack_chunk
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the source
	move.l	$c(a6),d6                       ; its length
	move.l	$10(a6),d5                      ; the destination
	move.l	$14(a6),d4                      ; the window
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	lea	ice_window(pc),a0               ; the packer's variables
	move.l	d4,(a0)                         ; window
	move.l	d5,4(a0)                        ; destination
	move.l	d7,8(a0)                        ; source
	move.l	d6,$c(a0)                       ; length
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp                           ; drop the arguments
	movea.l	d0,a6                           ; the screen
	adda.l	#$7d00,a6                       ; + 32000: its end
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp                           ; drop the arguments
	lea	ice_rez(pc),a0                  ; the resolution
	move.w	d0,(a0)                         ; kept
	cmp.w	#$2,d0                          ; high?
	beq.s	pack_ice_high                   ; yes
	move.l	#$a0,d0                         ; 160 bytes a line
	lea	ice_bar_line_bytes(pc),a0       ; bytes a line
	move.l	d0,(a0)                         ; kept
	mulu.w	bar_offset,d0                   ; * the bar's distance from the bottom
	move.w	bar_column,d1                   ; + its column
	mulu.w	#$4,d1                          ; * 4 bytes
	move.l	#$a0,d2                         ; from the line's end
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a6                           ; where the bar starts
	lea	ice_bar_next(pc),a0             ; the next line to draw
	move.l	a6,(a0)                         ; kept
	lea	ice_bar_height(pc),a0           ; the bar's height in lines
	move.w	bar_height,(a0)                 ; kept
	bra.s	pack_ice_step
pack_ice_high:
	move.l	#$50,d0                         ; 80 bytes a line
	lea	ice_bar_line_bytes(pc),a0       ; bytes a line
	move.l	d0,(a0)                         ; kept
	mulu.w	bar_offset,d0                   ; * the bar's distance from the bottom
	move.w	bar_column,d1                   ; + its column
	mulu.w	#$2,d1                          ; * 2 bytes
	move.l	#$50,d2                         ; from the line's end
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a6                           ; where the bar starts
	lea	ice_bar_next(pc),a0             ; the next line to draw
	move.l	a6,(a0)                         ; kept
	lea	ice_bar_height(pc),a0           ; the bar's height in lines
	move.w	bar_height,(a0)                 ; kept
pack_ice_step:
	lea	ice_bar_lines(pc),a0            ; no lines drawn
	clr.w	(a0)
	move.l	ice_source_length(pc),d0        ; the length
	divu.w	ice_bar_height(pc),d0           ; / the height
	lea	ice_bar_step(pc),a0             ; bytes for each line
	move.w	d0,(a0)                         ; kept
	bsr.w	ice_crunch                      ; pack
	lea	ice_packed_length(pc),a0        ; the packed length
	move.l	d0,(a0)                         ; kept
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	move.l	ice_packed_length(pc),d0        ; returned
	unlk	a6                              ; the frame back
	rts
ice_bar_lines:	; from: ice_bar
	dc.w	$0000                           ; the lines of the bar drawn
ice_bar_step:	; from: ice_bar
	dc.w	$0000                           ; bytes packed for each line
ice_bar_line_bytes:	; from: ice_bar
	dc.l	$00000000                       ; bytes a screen line: 160 or 80
ice_bar_height:
	dc.w	$0000                           ; the bar's height
ice_bar_next:	; from: ice_bar
	dc.l	$00000000                       ; where the next line is drawn
ice_rez:	; from: ice_bar
	dc.w	$0000                           ; the resolution
ice_packed_length:
	dc.l	$00000000                       ; the packed length
	dc.w	$0000                           ; not used
ice_window:	; from: ice_crunch
	dc.l	$00000000                       ; how far ahead to look for strings
ice_destination:	; from: ice_crunch
	dc.l	$00000000
ice_source:	; from: ice_bar, ice_crunch
	dc.l	$00000000
ice_source_length:	; from: ice_crunch
	dc.l	$00000000                       ; the source's length
ice_run:	; from: ice_crunch
	dc.l	$00000000                       ; how many bytes after this one are the same
ice_match_length:	; from: ice_crunch, ice_put_length
	dc.w	$0000                           ; the best string's length
ice_match_offset:	; from: ice_crunch
	dc.w	$0000                           ; and its offset

;------------------------------------------------------------------------------
; ice_bar: draw the packometer's bar down to the source position (a0) reached, a line for each
; ice_bar_step bytes.  With Alternate held it returns -1 from ice_crunch instead.
;------------------------------------------------------------------------------
ice_bar:	; from: ice_crunch
	movem.l	d0-d2/a0-a2,-(sp)               ; keep the registers
	move.l	a0,d0                           ; the position
	sub.l	ice_source(pc),d0               ; - the source
	divu.w	ice_bar_step(pc),d0             ; / bytes a line: the lines due
ice_bar_loop:
	movea.w	ice_bar_lines(pc),a0            ; the lines drawn
	cmpa.w	bar_height,a0                   ; all of the bar?
	bge.s	ice_bar_done                    ; yes: done
	cmp.w	a0,d0                           ; all due drawn?
	bgt.s	ice_bar_line                    ; no: another
ice_bar_done:
	movem.l	(sp)+,d0-d2/a0-a2               ; the registers back
	rts
ice_bar_line:
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	trap	#13                             ; Kbshift
	addq.l	#4,sp                           ; drop the arguments
	btst	#$3,d0                          ; Alternate?
	bne.s	ice_bar_abort                   ; yes: abort
	lea	ice_bar_lines(pc),a0            ; one more line
	addq.w	#1,(a0)
	movea.l	ice_bar_next(pc),a1             ; where it goes
	move.w	#$ffff,(a1)                     ; a line of the bar
	move.w	#$ffff,2(a1)
	move.w	ice_rez(pc),d0                  ; the resolution
	cmpi.w	#$2,d0                          ; high?
	beq.s	ice_bar_up                      ; yes: 2 words are 32 pixels
	move.w	#$ffff,4(a1)                    ; 4 words in the colour resolutions
	move.w	#$ffff,6(a1)
ice_bar_up:
	suba.l	ice_bar_line_bytes(pc),a1       ; one line up
	lea	ice_bar_next(pc),a0
	move.l	a1,(a0)                         ; kept
	bra.s	ice_bar_loop
ice_bar_abort:
	movem.l	(sp)+,d0-d2/a0-a2               ; the registers back
	addq.l	#4,sp                           ; not back to ice_crunch
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; The ICE packer: the source (a0) to the destination (a1) as 'Ice!', the packed length, the unpacked length,
; then the codes.  It goes from the start of the source up and looks ahead for strings, so that
; ice_depack, reading the codes from the end down, writes the output from its end down.  At each byte it
; takes the longer of a run of the same byte and the longest string found within the window ahead (up to
; $409 bytes, an offset up to $111f, a 2 byte string up to $23f away), else a literal.
;------------------------------------------------------------------------------
ice_crunch:	; from: pack_ice
	movea.l	ice_source(pc),a0               ; the source
	movea.l	ice_destination(pc),a1          ; the destination
	movea.l	a0,a2
	adda.l	ice_source_length(pc),a2        ; a2 = the source's end
	move.l	#$49636521,d7                   ; 'Ice!'
	bsr.w	ice_put_long                    ; written
	addq.l	#4,a1                           ; room for the packed length
	move.l	ice_source_length(pc),d7        ; the unpacked length
	bsr.w	ice_put_long                    ; written
	moveq	#0,d5                           ; no literals yet
	moveq	#7,d6                           ; 8 bits to go
	moveq	#0,d7                           ; none yet
	moveq	#0,d4                           ; one bit
	clr.l	d1                              ; 0
	bsr.w	ice_put_bits                    ; the first bit
ice_crunch_loop:
	lea	$409(a0),a4                     ; how far a run can go: $409 bytes
	cmpa.l	a2,a4                           ; past the end?
	ble.s	ice_crunch_run                  ; no
	movea.l	a2,a4                           ; yes: the end
ice_crunch_run:
	movea.l	a0,a3                           ; from here
	move.b	(a3)+,d0                        ; this byte
ice_crunch_run_loop:
	cmp.b	(a3)+,d0                        ; the same?
	bne.s	ice_crunch_run_end              ; no
	cmpa.l	a4,a3                           ; up to the limit
	blt.s	ice_crunch_run_loop
ice_crunch_run_end:
	move.l	a3,d1                           ; how many after this one are the same
	sub.l	a0,d1
	subq.l	#2,d1
	lea	ice_run(pc),a3                  ; kept
	move.l	d1,(a3)
	cmp.l	#$409,d1                        ; the longest run?
	beq.w	ice_crunch_take_run             ; yes: take it
	movea.l	a0,a3                           ; how far a string can be: the window
	adda.l	ice_window(pc),a3
	cmpa.l	a2,a3                           ; past the end?
	ble.s	ice_crunch_search               ; no
	movea.l	a2,a3                           ; yes: the end
ice_crunch_search:
	moveq	#1,d4                           ; the best so far: 1
	lea	2(a0),a4                        ; from 2 bytes on
ice_crunch_search_next:
	move.b	(a0),d0                         ; this byte
	move.b	1(a0),d1                        ; and the next
ice_crunch_find:
	cmp.b	(a4)+,d0                        ; the first byte?
	beq.s	ice_crunch_found                ; yes
ice_crunch_find_next:
	cmpa.l	a4,a3                           ; up to the window
	bgt.s	ice_crunch_find
	bra.s	ice_crunch_choose               ; not found
ice_crunch_found:
	cmp.b	(a4),d1                         ; the second too?
	bne.s	ice_crunch_find_next            ; no
	movea.l	a4,a6                           ; the string found
	subq.l	#1,a6
	move.l	a6,d0                           ; d0: not into this one
	movea.l	a0,a5                           ; this one
ice_crunch_compare:
	cmpm.b	(a5)+,(a6)+                     ; the same?
	bne.s	ice_crunch_compared             ; no
	cmpa.l	d0,a5                           ; up to the string found?
	bhi.s	ice_crunch_compared             ; yes: stop
	cmpa.l	a6,a3                           ; up to the window?
	bgt.s	ice_crunch_compare              ; yes
ice_crunch_compared:
	move.l	a5,d1                           ; the length
	sub.l	a0,d1
	subq.l	#1,d1
	move.l	a6,d2                           ; the offset: the distance less the length
	sub.l	a5,d2
	sub.l	d1,d2
	addq.l	#1,d2
	move.l	#$409,d0                        ; $409: the longest
	cmp.l	d0,d4                           ; had already?
	beq.s	ice_crunch_choose               ; yes
	cmp.l	d0,d1                           ; longer than that?
	bls.s	ice_crunch_best                 ; no
	sub.l	d0,d1                           ; yes: the rest
	add.l	d1,d2                           ; goes into the offset
	move.l	d0,d1                           ; $409
ice_crunch_best:
	cmp.l	d1,d4                           ; longer than the best?
	bge.s	ice_crunch_more                 ; no
	cmp.w	#$2,d1                          ; 2 bytes or less?
	bls.s	ice_crunch_take                 ; yes: it will do
	cmp.w	#$111f,d2                       ; offset beyond $111f?
	bhi.s	ice_crunch_more                 ; yes: no good
ice_crunch_take:
	move.l	d1,d4                           ; the best
	lea	ice_match_length(pc),a6
	move.w	d1,(a6)                         ; its length
	move.w	d2,2(a6)                        ; and offset
ice_crunch_more:
	cmpa.l	a4,a3                           ; up to the window
	bgt.s	ice_crunch_search_next
ice_crunch_choose:
	move.l	ice_run(pc),d0                  ; the run
	cmp.w	#$1,d0                          ; more than one?
	ble.s	ice_crunch_string               ; no
	cmp.l	d4,d0                           ; as long as the string?
	bge.s	ice_crunch_take_run             ; yes: the run
ice_crunch_string:
	move.w	ice_match_offset(pc),d0         ; the offset
	move.w	d4,d1                           ; the length
	cmpi.w	#$1,d1                          ; 1: a literal
	beq.s	ice_crunch_literal
	cmpi.w	#$2,d1                          ; 2: a short string
	beq.s	ice_crunch_short
	bra.s	ice_crunch_long                 ; longer
ice_crunch_literal:	; from: ice_put_short_offset
	move.b	(a0)+,(a1)+                     ; a literal
	addq.l	#1,d5                           ; counted
	bra.s	ice_crunch_next
ice_crunch_take_run:
	move.l	ice_run(pc),d1                  ; the run
	lea	ice_match_length(pc),a6
	move.w	d1,(a6)                         ; is the length
	moveq	#0,d0                           ; offset 0: the byte before
	subq.l	#2,d1                           ; 2 bytes?
	bne.s	ice_crunch_long                 ; no
ice_crunch_short:
	cmpi.w	#$23f,d0                        ; more than $23f away?
	bhi.s	ice_crunch_literal              ; yes: a literal instead
	bsr.s	ice_put_literals                ; the literals first
	bsr.w	ice_put_short_offset            ; the short offset
	bra.s	ice_crunch_length
ice_crunch_long:
	bsr.s	ice_put_literals                ; the literals first
	bsr.w	ice_put_offset                  ; the offset
ice_crunch_length:
	bsr.w	ice_put_length                  ; the length
	moveq	#0,d5                           ; no literals now
	move.w	ice_match_length(pc),d0         ; the length
	adda.w	d0,a0                           ; past the string
ice_crunch_next:
	bsr.w	ice_bar                         ; the bar
	lea	-$3(a2),a3                      ; 3 bytes before the end
	cmpa.l	a3,a0                           ; reached?
	bcs.w	ice_crunch_loop                 ; no: on
ice_crunch_tail:
	cmpa.l	a2,a0                           ; the rest
	bge.s	ice_crunch_end
	move.b	(a0)+,(a1)+                     ; as literals
	addq.l	#1,d5                           ; counted
	bra.s	ice_crunch_tail
ice_crunch_end:
	bsr.s	ice_put_literals                ; the literals
	bset	d6,d7                           ; a 1 bit to mark the end of the bits
	move.b	d7,(a1)+                        ; the last byte
	suba.l	ice_destination(pc),a1          ; the packed length
	move.l	a1,d0
	move.l	d0,d7
	movea.l	ice_destination(pc),a1          ; after the magic
	addq.l	#4,a1
	bsr.w	ice_put_long                    ; written
	rts

;------------------------------------------------------------------------------
; ice_put_literals: the literal count (d5) and the flag bit; the literals have been copied already.
;------------------------------------------------------------------------------
ice_put_literals:	; from: ice_crunch
	cmp.l	#$810d,d5                       ; more than $810d?
	bls.s	ice_put_literals_code           ; no
	movea.l	a0,a2                           ; yes: the end of the source here
ice_put_literals_code:
	lea	ice_literal_bits(pc),a3         ; the counts' ranges
	moveq	#6,d3                           ; 7 of them
ice_put_literals_find:
	move.w	-(a3),d4                        ; the next lower
	cmp.w	d4,d5                           ; in it?
	dbge	d3,ice_put_literals_find        ; no: the next
	sub.w	d4,d5                           ; the count within it
	add.w	d3,d3                           ; words
	lea	ice_literal_bits(pc),a3         ; its code
	adda.w	d3,a3
	move.b	(a3)+,d2                        ; the value's bits
	ext.w	d2                              ; to a word
	moveq	#-1,d1                          ; ones above it
	lsl.l	d2,d1
	or.w	d5,d1                           ; then the value
	moveq	#0,d5                           ; the literals counted from 0
	move.b	(a3)+,d4                        ; the code's length
	ext.w	d4                              ; to a word
	subq.w	#1,d4                           ; less one
	bra.w	ice_put_bits                    ; written
ice_literal_ranges:
	dc.w	$0000,$0001,$0002,$0005,$0008,$000f,$010e ; the literal counts' range starts
ice_literal_bits:
	dc.w	$0101,$0102,$0204,$0206,$0309,$0811,$0f20 ; for each: the value's bits, then the code's length

;------------------------------------------------------------------------------
; ice_put_offset: the offset (d0) of a string of 3 or more.
;------------------------------------------------------------------------------
ice_put_offset:	; from: ice_crunch
	lea	ice_offset_ranges(pc),a3        ; the offsets' ranges
	moveq	#2,d3                           ; 3 of them
ice_put_offset_find:
	add.w	d3,d3
	move.w	0(a3,d3.w),d4                   ; the next lower
	lsr.w	#1,d3
	cmp.w	d4,d0                           ; in it?
	dbge	d3,ice_put_offset_find          ; no: the next
	sub.w	d4,d0                           ; the offset within it
	add.w	d3,d3
	move.w	6(a3,d3.w),d3                   ; its bits and its code's length
	move.w	d3,d4
	lsr.w	#8,d3                           ; the value's bits
	moveq	#-1,d1                          ; ones above it
	lsl.w	d3,d1
	or.w	d0,d1                           ; then the value
	andi.w	#$f,d4                          ; the code's length less one
	bra.s	ice_put_bits                    ; written
ice_offset_ranges:
	dc.w	$0000,$0020,$0120,$0606,$0908,$0c0d ; the offsets' range starts, then the value's bits and the code's
                                                ;   length

;------------------------------------------------------------------------------
; ice_put_short_offset: the offset (d0) of a 2 byte string, 6 or 9 bits.
;------------------------------------------------------------------------------
ice_put_short_offset:	; from: ice_crunch
	cmpi.w	#$23f,d0                        ; too far?
	bhi.w	ice_crunch_literal              ; yes: never, the caller has looked
	move.w	d0,d1                           ; the offset
	cmpi.w	#$3f,d1                         ; more than 63?
	ble.s	ice_put_short_offset_6          ; no
	subi.w	#$40,d1                         ; yes: from 64
	moveq	#9,d4                           ; 10 bits
	bset	d4,d1                           ; a 1 bit above 9
	bra.s	ice_put_bits                    ; written
ice_put_short_offset_6:
	moveq	#6,d4                           ; 7 bits: a 0 and 6
	bra.s	ice_put_bits                    ; written

;------------------------------------------------------------------------------
; ice_put_length: the string's length.
;------------------------------------------------------------------------------
ice_put_length:	; from: ice_crunch
	lea	ice_length_ranges(pc),a3        ; the lengths' ranges
	move.w	ice_match_length(pc),d0         ; the length
	moveq	#4,d5                           ; 5 of them
ice_put_length_find:
	move.b	0(a3,d5.w),d4                   ; the next lower
	ext.w	d4                              ; to a word
	cmp.w	d4,d0                           ; in it?
	dbge	d5,ice_put_length_find          ; no: the next
	sub.w	d4,d0                           ; the length within it
	move.b	5(a3,d5.w),d4                   ; the value's bits
	ext.w	d4                              ; to a word
	moveq	#-1,d1                          ; ones above it
	lsl.w	d4,d1
	or.w	d0,d1                           ; then the value
	add.w	d5,d4                           ; + the code's ones
	subq.w	#1,d4                           ; less one

;------------------------------------------------------------------------------
; ice_put_bits: the low d4 + 1 bits of d1, lowest first, into the code bytes.
;------------------------------------------------------------------------------
ice_put_bits:	; from: ice_crunch, ice_put_literals, ice_put_offset, ice_put_short_offset
	lsr.l	#1,d1                           ; the next bit
	roxr.b	#1,d7                           ; into the byte
	dbra	d6,ice_put_bits_next            ; full?
	move.b	d7,(a1)+                        ; yes: written
	moveq	#0,d7
	moveq	#7,d6                           ; 8 bits
ice_put_bits_next:
	dbra	d4,ice_put_bits                 ; for each bit
	rts
ice_length_ranges:	; from: ice_put_length
	dc.b	$02,$03,$04,$06,$0a,$01,$01,$02,$03,$0a ; the lengths' range starts, then the value's bits

;------------------------------------------------------------------------------
; ice_put_long: d7, high byte first.
;------------------------------------------------------------------------------
ice_put_long:	; from: ice_crunch
	rol.l	#8,d7
	move.b	d7,(a1)+
	rol.l	#8,d7
	move.b	d7,(a1)+
	rol.l	#8,d7
	move.b	d7,(a1)+
	rol.l	#8,d7
	move.b	d7,(a1)+
	rts
	movem.l	(sp)+,d4-d7                     ; not reached: pack_ice's end as compiled
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The ICE program stub ("JAM Packer Decrunch V4.0"), put in front of a program packed with ICE.
; Each stub keeps the registers, clears the top of the screen and prints its title (unless Heading is off),
; depacks the program $100 bytes past its own end flashing the background (unless Flash is off), relocates
; it to run where the stub starts, sets the basepage and runs a mover from the screen that copies it down,
; clears its BSS (at least $400 bytes, $1a00 for LZH), puts the registers back and jumps to it.  The packed
; data follows the stub.
;------------------------------------------------------------------------------
ice_stub:	; from: write_program, pack_file, multi_pack_file
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
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
	beq.s	ice_stub_clear                  ; yes
	move.w	#$167,d1                        ; 360 longs otherwise
ice_stub_clear:	; from: set_stub_options
	clr.l	(a2)+                           ; clear the top of the screen (a nop without Heading)
	dbra	d1,ice_stub_clear
	lea	ice_stub_text(pc),a1            ; the title
	move.b	#$3c,5(a1)                      ; column 28
	cmp.b	#$0,d0                          ; low resolution?
	bne.s	ice_stub_title                  ; no
	move.b	#$28,5(a1)                      ; yes: column 8
ice_stub_title:
	pea	ice_stub_text(pc)               ; the title
	move.w	#$9,-(sp)
ice_stub_print:	; from: set_stub_options
	trap	#1                              ; Cconws, Cconws (a nop without Heading)
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; kept
	move.w	$ffff8240.w,-(sp)               ; palette 0
	lea	ice_stub+$2ac(pc),a0            ; the packed data after the stub
	movea.l	a0,a1
	adda.l	#$100,a1
	move.l	4(a0),-(sp)                     ; argument 1
	bsr.w	ice_stub_depack
	movea.l	(sp)+,a6
	move.w	(sp)+,$ffff8240.w               ; palette 0
	move.w	#$20,-(sp)                      ; Super(old stack)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	ice_stub+$2ac(pc),a3            ; the depacked program: $100 bytes on
	adda.l	#$100,a3
	movea.l	a3,a1
	movea.l	2(a3),a0                        ; its header's text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	adda.l	#$1c,a0                         ; + the header
	adda.l	a3,a0                           ; a0 = its relocation table
	lea	ice_stub(pc),a5                 ; where it will run: the stub's text
	move.l	a5,d0
	adda.l	#$1c,a1                         ; its text
	tst.l	(a0)                            ; any relocation?
	beq.s	ice_stub_relocated              ; no
	adda.l	(a0)+,a1                        ; the first address
ice_stub_relocate:
	add.l	d0,(a1)                         ; relocate a long
ice_stub_relocate_next:
	clr.l	d1
	move.b	(a0)+,d1                        ; the next step
	tst.w	d1                              ; the end?
	beq.s	ice_stub_relocated              ; yes
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	ice_stub_relocate_step          ; no
	adda.l	#$fe,a1                         ; yes
	bra.s	ice_stub_relocate_next
ice_stub_relocate_step:
	adda.l	d1,a1                           ; on to the next long
	bra.s	ice_stub_relocate               ; relocate it
ice_stub_relocated:
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
	moveq	#95,d2
	lea	ice_stub_mover(pc),a1           ; the mover
ice_stub_copy_mover:
	move.b	(a1)+,(a2)+                     ; copied
	dbra	d2,ice_stub_copy_mover
	movea.l	a3,a1                           ; the depacked text
	adda.l	#$1c,a1
	lea	ice_stub(pc),a0                 ; where it runs
	movea.l	a0,a2
	jmp	(a5)                            ; run the mover
ice_stub_mover:
	lea	ice_stub_start+2(pc),a6         ; where the last jump goes
	move.l	a0,(a6)                         ; the start of the program, put in it
ice_stub_mover_copy:
	move.l	(a1)+,(a2)+                     ; copy the program down, 16 bytes at a time
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	cmpa.l	d1,a2                           ; to the BSS?
	ble.s	ice_stub_mover_copy
	lea	-$100(a0),a1                    ; the basepage
	movea.l	$18(a1),a3                      ; its BSS
	move.l	$1c(a1),d1                      ; its length
	cmp.l	#$400,d1                        ; at least $400 bytes
	bgt.s	ice_stub_clear_size             ; yes
	move.l	#$400,d1                        ; no: $400
ice_stub_clear_size:
	lsr.l	#4,d1                           ; in 16 bytes
ice_stub_clear_bss:
	clr.l	(a3)+                           ; cleared
	clr.l	(a3)+
	clr.l	(a3)+
	clr.l	(a3)+
	subq.l	#1,d1                           ; less one
	bge.s	ice_stub_clear_bss
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	clr.l	d0                              ; d0 = 0
ice_stub_start:
	jmp	$0                              ; start the program (the mover puts its address in)

;------------------------------------------------------------------------------
; The stub's copy of ice_depack, which does not check the magic.
;------------------------------------------------------------------------------
ice_stub_depack:	; from: ice_stub
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	bsr.s	ice_stub_read_long              ; the magic, not checked
	bsr.s	ice_stub_read_long              ; the packed length
	lea	-$8(a0,d0.l),a5                 ; a5 = the packed data's end
	bsr.s	ice_stub_read_long              ; the unpacked length
	move.l	d0,(sp)                         ; returned in d0
	movea.l	a1,a4                           ; a4 = the destination
	movea.l	a1,a6                           ; a6 = it
	adda.l	d0,a6                           ; + the length: its end
	movea.l	a6,a3
	move.b	-(a5),d7                        ; the last byte: the first bits
	bsr.s	ice_stub_literals               ; depack
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts

;------------------------------------------------------------------------------
; The stub's copies of ice_read_long, ice_literals, ice_bit and ice_bits follow.
;------------------------------------------------------------------------------
ice_stub_read_long:	; from: ice_stub_depack
	moveq	#3,d1                           ; d0 = the next 4 bytes
ice_stub_read_long_loop:
	lsl.l	#8,d0
	move.b	(a0)+,d0
	dbra	d1,ice_stub_read_long_loop
	rts

ice_stub_literals:	; from: ice_stub_depack, ice_stub_bits
	bsr.s	ice_stub_bit                    ; a 1 bit: literals first?
	bcc.s	ice_stub_next                   ; no
ice_stub_flash:	; from: set_stub_options
	move.w	d7,$ffff8240.w                  ; palette 0, the background (a nop without Flash)
	moveq	#0,d1                           ; one literal
	bsr.s	ice_stub_bit                    ; a 1 bit: more?
	bcc.s	ice_stub_copy_literals          ; no
	lea	ice_stub_literal_bases(pc),a1   ; the literal count codes
	moveq	#4,d3                           ; 5 of them
ice_stub_literal_code:
	move.l	-(a1),d0                        ; the next: its bit count and its all-ones value
	bsr.s	ice_stub_bits                   ; read
	swap	d0                              ; the value
	cmp.w	d0,d1                           ; all ones: the next code
	dbne	d3,ice_stub_literal_code
	add.l	$14(a1),d1                      ; + its base
ice_stub_copy_literals:
	move.b	-(a5),-(a6)                     ; a literal
	dbra	d1,ice_stub_copy_literals       ; for the count
ice_stub_next:
	cmpa.l	a4,a6                           ; all done?
	bgt.s	ice_stub_string                 ; no: a string
	rts                                     ; yes

ice_stub_bit:	; from: ice_stub_literals, ice_stub_bits
	add.b	d7,d7                           ; the next bit into x and c
	bne.s	ice_stub_bit_got                ; the byte still has bits
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7                           ; with a 1 bit to mark its end
ice_stub_bit_got:
	rts

ice_stub_bits:	; from: ice_stub_literals
	moveq	#0,d1                           ; d1 = the next d0 + 1 bits
ice_stub_bits_loop:
	add.b	d7,d7                           ; the next bit
	bne.s	ice_stub_bits_got               ; the byte still has bits
	move.b	-(a5),d7                        ; no: the next byte
	addx.b	d7,d7
ice_stub_bits_got:
	addx.w	d1,d1                           ; into d1
	dbra	d0,ice_stub_bits_loop
	rts
ice_stub_string:	; from: ice_stub_literals
	lea	ice_stub_length_table(pc),a1    ; the length codes
	moveq	#3,d2                           ; up to 4 bits
ice_stub_length_code:
	bsr.s	ice_stub_bit                    ; a 1 bit: a longer code
	dbcc	d2,ice_stub_length_code
	moveq	#0,d4                           ; d4 = the length
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the extra bits
	ext.w	d0                              ; to a word
	bmi.s	ice_stub_length                 ; none
	bsr.s	ice_stub_bits                   ; read
ice_stub_length:
	move.b	6(a1,d2.w),d4                   ; + the base
	add.w	d1,d4
	beq.s	ice_stub_short_offset           ; 0: a 2 byte string
	lea	ice_stub_offset_table(pc),a1    ; the offset codes
	moveq	#1,d2                           ; up to 2 bits
ice_stub_offset_code:
	bsr.s	ice_stub_bit                    ; a 1 bit: a longer code
	dbcc	d2,ice_stub_offset_code
	moveq	#0,d1
	move.b	1(a1,d2.w),d0                   ; the offset's bit count
	ext.w	d0                              ; to a word
	bsr.s	ice_stub_bits                   ; read
	add.w	d2,d2                           ; words
	add.w	6(a1,d2.w),d1                   ; + the base
	bpl.s	ice_stub_copy_string            ; positive: done
	sub.w	d4,d1                           ; negative: less the length
	bra.s	ice_stub_copy_string
ice_stub_short_offset:
	moveq	#0,d1                           ; a 2 byte string
	moveq	#5,d0                           ; 6 bits
	moveq	#-1,d2                          ; less one
	bsr.s	ice_stub_bit                    ; a 1 bit: more?
	bcc.s	ice_stub_short_offset_bits      ; no
	moveq	#8,d0                           ; yes: 9 bits
	moveq	#63,d2                          ; plus 63
ice_stub_short_offset_bits:
	bsr.s	ice_stub_bits                   ; read
	add.w	d2,d1                           ; + the base
ice_stub_copy_string:
	lea	2(a6,d4.w),a1                   ; from where it was
	adda.w	d1,a1
	move.b	-(a1),-(a6)                     ; the first byte
ice_stub_copy_string_loop:
	move.b	-(a1),-(a6)                     ; the rest
	dbra	d4,ice_stub_copy_string_loop
	bra.w	ice_stub_literals               ; then literals again

;------------------------------------------------------------------------------
; The literal count, length and offset codes: a code is a run of 1 bits ended by a 0 (or the
; longest run), then a value of a set number of bits, added to its base.
;------------------------------------------------------------------------------
ice_stub_literal_codes:
	dc.l	$7fff000e,$00ff0007,$00070002,$00030001 ; the literal count codes: bit count less one and all-ones value
	dc.l	$00030001
ice_stub_literal_bases:	; from: ice_stub_literals
	dc.l	$0000010d,$0000000e,$00000007,$00000004 ; their bases, less one
	dc.l	$00000001
ice_stub_length_table:	; from: ice_stub_bits
	dc.b	$09,$01,$00,$ff,$ff,$08,$04,$02,$01,$00 ; the length codes: extra bits less one, then bases less one
ice_stub_offset_table:	; from: ice_stub_bits
	dc.b	$0b,$04,$07,$00                 ; the offset codes: bit counts less one, then bases
	dc.w	$011f,$ffff,$001f
ice_stub_text:	; from: ice_stub
	dc.b	27,'j',27,'Y  JAM Packer Decrunch V4.0',27,'k',0 ; the title, its column put in
	dc.b	$00

;------------------------------------------------------------------------------
; fdc_sectors(write, buffer, count, first, drive): read (write = 0) or write sectors straight through the FDC
; and the DMA, counting from the first sector of track 0, side 0, through the sides of each track.  A
; Floprd of the boot sector into a buffer of its own comes first.  d0 = 0, or -1 when the FDC times out
; (leaving flock set).
;------------------------------------------------------------------------------
fdc_sectors:	; from: write_program, pack_file, multi_pack_file, ice_stub, disk_unpack, disk_pack
	link	a6,#-512                        ; 512 bytes of locals
	move.w	#$1,-(sp)                       ; 1 sector
	clr.w	-(sp)                           ; side 0
	clr.w	-(sp)                           ; track 0
	move.w	#$1,-(sp)                       ; sector 1
	move.w	$12(a6),-(sp)                   ; the drive
	clr.l	-(sp)                           ; argument 2
	pea	-$200(a6)                       ; the buffer
	move.w	#$8,-(sp)                       ; Floprd
	jsr	xbios
	lea	$14(sp),sp                      ; drop the arguments
	move.l	a6,-(sp)                        ; keep a6
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; the old stack, kept
	lea	fdc_write(pc),a0                ; write
	move.w	8(a6),(a0)
	lea	fdc_select(pc),a0               ; the drive's select bit
	tst.w	$12(a6)                         ; drive B?
	beq.s	fdc_sectors_drive_a             ; no
	move.w	#$4,(a0)                        ; yes: 4
	bra.s	fdc_sectors_go
fdc_sectors_drive_a:
	move.w	#$2,(a0)                        ; A: 2
fdc_sectors_go:
	lea	fdc_spt(pc),a0                  ; sectors a track
	move.w	disk_spt,(a0)
	lea	fdc_sides(pc),a0                ; sides
	move.w	disk_sides,(a0)
	move.w	$10(a6),d6                      ; d6 = the first sector
	move.w	$e(a6),d2                       ; d2 = the count
	movea.l	$a(a6),a0                       ; a0 = the buffer
	bsr.s	fdc_transfer                    ; read or write
	move.l	d0,d7                           ; the result
	move.w	#$20,-(sp)                      ; Super(old stack)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d7,d0                           ; returned
	movea.l	(sp)+,a6                        ; a6 back
	unlk	a6                              ; the frame back
	rts
fdc_select:	; from: fdc_transfer
	dc.w	$0000                           ; the drive and side bits
fdc_spt:	; from: fdc_transfer
	dc.w	$0000                           ; sectors a track
fdc_sides:	; from: fdc_transfer
	dc.w	$0000                           ; sides
fdc_sector_size:	; from: fdc_transfer
	dc.w	$0200                           ; 512 bytes a sector
	dc.w	$0000,$0000,$0000,$0000         ; not used
fdc_write:	; from: fdc_transfer
	dc.w	$0000                           ; nonzero to write
	nop

;------------------------------------------------------------------------------
; fdc_transfer: d6 = the first sector, d2 the count, a0 the buffer, a1 nonzero to write, d3 the drive's select
; bit: each sector is read or written by the FDC with the DMA, seeking as the tracks change.
;------------------------------------------------------------------------------
fdc_transfer:	; from: fdc_sectors
	clr.l	d0
	movea.w	fdc_write(pc),a1                ; a1 = write?
	move.w	fdc_select(pc),d3               ; d3 = the select bits
	addq.w	#1,d6                           ; the first, from 1
	move.w	d6,d0
	move.w	fdc_spt(pc),d4                  ; sectors a track
	muls.w	fdc_sides(pc),d4                ; * sides: a cylinder
	divs.w	d4,d0                           ; d0 = the track
	move.l	d0,d1
	swap	d1                              ; d1 = the sector within it
	tst.w	d1                              ; 0?
	bne.s	fdc_transfer_side               ; no
	sub.w	#$1,d0                          ; yes: the last of the track before
	move.w	fdc_spt(pc),d1                  ; a cylinder's
	mulu.w	fdc_sides(pc),d1
fdc_transfer_side:
	cmp.w	fdc_spt(pc),d1                  ; past side 0?
	bgt.s	fdc_transfer_side_1             ; yes
	bclr	#$0,d3                          ; no: side 0
	bra.s	fdc_transfer_select
fdc_transfer_side_1:
	bset	#$0,d3                          ; side 1
	sub.w	fdc_spt(pc),d1                  ; the sector on it
fdc_transfer_select:
	st	$43e.w                          ; flock, flock
	bsr.w	fdc_select_drive                ; the drive and side
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the command register
	move.w	#$f,d7                          ; $0f: Restore
	bsr.w	fdc_command
	bsr.w	fdc_wait                        ; wait
fdc_transfer_seek:
	move.w	#$86,$ffff8606.w                ; DMA mode / status, the data register
	move.w	d0,d7                           ; the track
	bsr.w	fdc_command
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the command register
	move.w	#$17,d7                         ; $17: Seek
	bsr.w	fdc_command
	bsr.w	fdc_wait                        ; wait
fdc_transfer_sector:
	move.w	#$84,$ffff8606.w                ; DMA mode / status, the sector register
	move.w	d1,d7                           ; the sector
	bsr.w	fdc_command
	move.l	a0,d7                           ; the buffer
	move.b	d7,$ffff860d.w                  ; DMA base low, into the DMA
	lsr.l	#8,d7
	move.b	d7,$ffff860b.w                  ; DMA base mid
	lsr.w	#8,d7
	move.b	d7,$ffff8609.w                  ; DMA base high
	cmpa.w	#$0,a1                          ; write?
	bne.s	fdc_transfer_write              ; yes
	move.w	#$90,$ffff8606.w                ; DMA mode / status, read: the DMA's direction toggled to clear it
	move.w	#$190,$ffff8606.w               ; DMA mode / status
	move.w	#$90,$ffff8606.w                ; DMA mode / status
	bra.s	fdc_transfer_count
fdc_transfer_write:
	move.w	#$190,$ffff8606.w               ; DMA mode / status, write: the same the other way
	move.w	#$90,$ffff8606.w                ; DMA mode / status
	move.w	#$190,$ffff8606.w               ; DMA mode / status
fdc_transfer_count:
	move.w	#$1,d7                          ; 1 sector
	bsr.s	fdc_command                     ; to the sector count
	cmpa.w	#$0,a1                          ; write?
	bne.s	fdc_transfer_write_command      ; yes
	move.w	#$80,$ffff8606.w                ; DMA mode / status, read: the command register
	move.w	#$80,d7                         ; $80: Read Sector
	bra.s	fdc_transfer_command
fdc_transfer_write_command:
	move.w	#$180,$ffff8606.w               ; DMA mode / status, the command register, write
	move.w	#$a0,d7                         ; $a0: Write Sector
fdc_transfer_command:
	bsr.s	fdc_command                     ; given
	bsr.s	fdc_wait                        ; wait
	subq.w	#1,d2                           ; one less
	beq.w	fdc_transfer_done               ; all done
	adda.w	fdc_sector_size(pc),a0          ; the next 512 bytes
	cmp.w	fdc_spt(pc),d1                  ; the track's last sector?
	beq.s	fdc_transfer_next_side          ; yes
	addq.w	#1,d1                           ; no: the next
	bra.w	fdc_transfer_sector
fdc_transfer_next_side:
	move.w	fdc_sides(pc),d6                ; sides
	cmpi.w	#$2,d6                          ; two?
	blt.s	fdc_transfer_next_track         ; no: the next track
	bchg	#$0,d3                          ; the other side
	bsr.s	fdc_select_drive                ; selected
	bne.s	fdc_transfer_next_track         ; from side 1 back to 0: the next track
	move.w	#$1,d1                          ; sector 1 of side 1
	bra.w	fdc_transfer_sector
fdc_transfer_next_track:
	addq.w	#1,d0                           ; the next track
	move.w	#$1,d1                          ; sector 1
	bra.w	fdc_transfer_seek               ; seek it
	bsr.s	fdc_pause                       ; not used: read the FDC register
	move.w	$ffff8604.w,d7                  ; DMA sector count / FDC access
	bra.s	fdc_pause

;------------------------------------------------------------------------------
; fdc_command: d7 to the FDC register selected, with a pause before and after.
;------------------------------------------------------------------------------
fdc_command:	; from: fdc_transfer
	bsr.s	fdc_pause                       ; pause
	move.w	d7,$ffff8604.w                  ; DMA sector count / FDC access, d7 to it

;------------------------------------------------------------------------------
; fdc_pause: a short pause; the rte takes the status register back.
;------------------------------------------------------------------------------
fdc_pause:	; from: fdc_transfer, fdc_command
	move.w	sr,-(sp)
	move.w	#$20,d5                         ; 32 times
fdc_pause_loop:
	dbra	d5,fdc_pause_loop
	rte                                     ; the status register back

;------------------------------------------------------------------------------
; fdc_wait: wait for the FDC's interrupt (GPIP bit 5); after too long, d0 = -1 from fdc_transfer.
;------------------------------------------------------------------------------
fdc_wait:	; from: fdc_transfer
	move.w	#$180,d5                        ; a pause
fdc_wait_pause:
	dbra	d5,fdc_wait_pause
	move.l	#$40000,d5                      ; then the time out
fdc_wait_loop:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt?
	beq.s	fdc_wait_done                   ; yes
	subq.l	#1,d5                           ; no: again
	bne.s	fdc_wait_loop
	addq.l	#4,sp                           ; timed out: not back to fdc_transfer
	moveq	#-1,d0                          ; -1
	rts
fdc_wait_done:
	rts

;------------------------------------------------------------------------------
; fdc_select_drive: the drive and side select bits of d3 to PSG port A (active low), interrupts off.
;------------------------------------------------------------------------------
fdc_select_drive:	; from: fdc_transfer
	move.w	sr,-(sp)
	move.b	d3,-(sp)                        ; keep d3
	eori.b	#$7,d3                          ; active low
	andi.b	#$7,d3
	ori.w	#$700,sr                        ; interrupts off
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	$ffff8800.w,d6                  ; PSG register select, its bits
	andi.b	#$f8,d6                         ; all but the drive and side
	or.b	d6,d3                           ; + ours
	move.b	d3,$ffff8802.w                  ; PSG write data, written
	move.b	(sp)+,d3                        ; d3 back
	rte                                     ; the status register back
fdc_transfer_done:	; from: fdc_transfer
	clr.l	d0                              ; 0
	sf	$43e.w                          ; flock, flock off
	rts
	unlk	a6                              ; not reached: fdc_sectors' end as compiled
	rts

;------------------------------------------------------------------------------
; disk_unpack(format): write a .JPK file back to a disk in drive A or B, formatting it first when Format is
; on.  The JPK file can be read from drive A, B or C.  It holds 'JPK!', the sectors a track, the tracks and
; the sides (a word each), then chunks, each after its length, and a -1 length at the end.  Each chunk is
; depacked with depack_chunk and its sectors written straight through the FDC (fdc_sectors), from sector 0
; on.  Its read errors after the first chunk call close_gem, not disk_error.
;------------------------------------------------------------------------------
disk_unpack:	; from: main
	link	a6,#-62                         ; 62 bytes of locals
	clr.w	-$3c(a6)                        ; no sectors written yet
	move.l	screen_buffer,-(sp)             ; the screen
	move.l	screen,-(sp)                    ; to the buffer
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	pea	alert_unpack_to_which_drive     ; "Unpack file to which drive?"
	move.w	#$1,-(sp)                       ; A or B
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	subq.w	#1,d0                           ; 0 or 1
	move.w	d0,-$c(a6)                      ; the drive to write
	pea	text_root_unpack                ; "\"
	pea	dpk_path                        ; the path
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_dpk_mask_unpack            ; "*.JPK"
	pea	dpk_path                        ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	pea	text_drivea_unpack              ; "DRIVEA.JPK"
	pea	dpk_name                        ; the name
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	alert_get_from_which_drive      ; "Get file from which drive?"
	move.w	#$1,-(sp)                       ; A, B or C
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	subq.w	#1,d0                           ; 0, 1 or 2
	move.w	d0,-$3e(a6)                     ; the drive to read it from
	move.w	-$3e(a6),-(sp)                  ; argument 1
	move.w	#$e,-(sp)                       ; Dsetdrv
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	pea	text_choose_input               ; "Choose the input pathname"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	pea	dpk_path                        ; the path chosen
	pea	dpk_name                        ; the name
	pea	dpk_path                        ; the path
	jsr	choose_file                     ; the file selector
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; OK?
	beq.s	disk_unpack_go                  ; yes
	clr.l	-(sp)                           ; no
	move.w	#$100,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; no alert
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_go:
	jsr	clear_title                     ; the title line cleared
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	clr.w	-(sp)                           ; read only
	pea	dpk_path                        ; the JPK file
	move.w	#$3d,-(sp)                      ; Fopen
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,-$a(a6)                      ; the handle
	tst.w	d0                              ; opened?
	bge.s	disk_unpack_magic               ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_magic:
	pea	jpk_magic                       ; the magic
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	-$a(a6),-(sp)                   ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; read?
	beq.s	disk_unpack_check_magic         ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	-$a(a6),-(sp)                   ; the handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_check_magic:
	cmpi.l	#$4a504b21,jpk_magic            ; 'JPK!'?
	beq.s	disk_unpack_spt                 ; yes
	pea	alert_not_jpk                   ; no: "Not a diskpack file"
	move.w	-$a(a6),-(sp)                   ; the handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_spt:
	pea	disk_spt                        ; the sectors a track
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	-$a(a6),-(sp)                   ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; read?
	beq.s	disk_unpack_tracks              ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	-$a(a6),-(sp)                   ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_tracks:
	pea	disk_tracks                     ; the tracks
	move.l	#$2,-(sp)                       ; argument 2
	move.w	-$a(a6),-(sp)                   ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; read?
	beq.s	disk_unpack_sides               ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	-$a(a6),-(sp)                   ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_sides:
	pea	disk_sides                      ; the sides
	move.l	#$2,-(sp)                       ; argument 2
	move.w	-$a(a6),-(sp)                   ; argument 1
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; read?
	beq.s	disk_unpack_header_read         ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	-$a(a6),-(sp)                   ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_header_read:
	move.w	disk_tracks,d0                  ; tracks
	muls.w	disk_spt,d0                     ; * sectors a track
	muls.w	disk_sides,d0                   ; * sides
	move.w	d0,disk_sectors                 ; = the total
	pea	text_disk_unpack_progress       ; "Disk Unpack Progress"
	pea	-$3a(a6)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	lea	-$3a(a6),a0
	move.l	a0,d0
	movea.l	tree_disk,a0
	movea.l	$24(a0),a0
	move.l	d0,(a0)
	pea	-$3a(a6)                        ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	movea.l	$24(a0),a0
	move.w	d0,$18(a0)
	move.w	-$c(a6),-(sp)                   ; argument 1
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
	move.w	-$c(a6),-(sp)                   ; argument 4
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
	move.l	#$3f000,-(sp)                   ; 258048 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$8(a6)                      ; the chunk buffer
	tst.l	-$8(a6)                         ; got it?
	bgt.s	disk_unpack_first_length        ; yes
	pea	alert_insufficient_memory       ; no: "Insufficient Memory."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_first_length:
	pea	chunk_length                    ; the first chunk's length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	-$a(a6),-(sp)                   ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; read?
	beq.s	disk_unpack_first_read          ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	-$a(a6),-(sp)                   ; the handle
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
	move.l	-$8(a6),-(sp)                   ; the buffer
	move.l	chunk_length,-(sp)              ; the chunk's length
	move.w	-$a(a6),-(sp)                   ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	chunk_length,d0                 ; all read?
	beq.s	disk_unpack_first_depack        ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	move.w	-$a(a6),-(sp)                   ; the handle
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
	move.l	chunk_length,-(sp)              ; its length
	move.l	-$8(a6),d0                      ; the buffer
	add.l	#$100,d0                        ; + 256: where it depacks to
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$8(a6),-(sp)                   ; the chunk
	jsr	depack_chunk                    ; depack it
	lea	$c(sp),sp                       ; drop the arguments
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
	pea	work_text                       ; the last sector
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	subq.l	#1,d0                           ; less 1: the last sector
	move.l	d0,-(sp)                        ; argument 1
	jsr	ltoa                            ; in decimal
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
	move.w	-$c(a6),-(sp)                   ; the drive
	clr.w	-(sp)                           ; from sector 0
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.w	d0,-(sp)                        ; = the sectors
	move.l	-$8(a6),d0                      ; the depacked data
	add.l	#$100,d0
	move.l	d0,-(sp)                        ; argument 2
	move.w	#$1,-(sp)                       ; write
	jsr	fdc_sectors                     ; the sectors
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; written?
	bge.s	disk_unpack_first_written       ; yes
	move.l	-$8(a6),-(sp)                   ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	-$a(a6),-(sp)                   ; the handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_unpack_done
disk_unpack_first_written:
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.w	d0,-$3c(a6)                     ; = the next sector
	movea.l	tree_disk,a0                    ; the disk info
	move.l	$54(a0),-(sp)                   ; the sectors remaining' text
	move.w	disk_sectors,d0                 ; the sectors
	sub.w	-$3c(a6),d0                     ; less those written
	move.w	d0,-(sp)                        ; argument 1
	jsr	itoa                            ; in decimal
	addq.l	#6,sp                           ; drop the arguments
	pea	chunk_length                    ; the next chunk's length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	-$a(a6),-(sp)                   ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	tst.l	d0                              ; read?
	bge.s	disk_unpack_first_ok            ; yes
	move.l	-$8(a6),-(sp)                   ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	-$a(a6),-(sp)                   ; the handle
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
	move.l	-$8(a6),-(sp)                   ; the buffer
	move.l	chunk_length,-(sp)              ; the chunk's length
	move.w	-$a(a6),-(sp)                   ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	tst.l	d0                              ; read?
	bge.s	disk_unpack_chunk_depack        ; yes
	move.l	-$8(a6),-(sp)                   ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	-$a(a6),-(sp)                   ; the handle
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
	move.l	chunk_length,-(sp)              ; its length
	move.l	-$8(a6),d0                      ; the buffer
	add.l	#$100,d0                        ; + 256: where it depacks to
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$8(a6),-(sp)                   ; the chunk
	jsr	depack_chunk                    ; depack it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,chunk_length                 ; its length
	pea	text_writing_chunk              ; "Writing Sectors"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	move.l	$9c(a0),-(sp)                   ; the sectors line
	move.w	-$3c(a6),-(sp)                  ; the first sector
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
	move.w	-$3c(a6),d3                     ; + the first sector
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
	move.w	-$c(a6),-(sp)                   ; the drive
	move.w	-$3c(a6),-(sp)                  ; from the next sector
	move.l	chunk_length,d0                 ; the length
	move.l	d0,-(sp)                        ; the dividend
	move.l	#$200,d0                        ; 512
	move.l	d0,-(sp)                        ; the divisor
	jsr	ldiv                            ; /
	move.l	(sp)+,d0                        ; the quotient
	addq.l	#4,sp                           ; the remainder dropped
	move.w	d0,-(sp)                        ; = the sectors
	move.l	-$8(a6),d0                      ; the depacked data
	add.l	#$100,d0
	move.l	d0,-(sp)                        ; argument 2
	move.w	#$1,-(sp)                       ; write
	jsr	fdc_sectors                     ; the sectors
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0                              ; written?
	bge.s	disk_unpack_chunk_done          ; yes
	move.l	-$8(a6),-(sp)                   ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	-$a(a6),-(sp)                   ; the handle
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
	add.w	d0,-$3c(a6)                     ; the next sector
	movea.l	tree_disk,a0                    ; the disk info
	move.l	$54(a0),-(sp)                   ; the sectors remaining' text
	move.w	disk_sectors,d0                 ; the sectors
	sub.w	-$3c(a6),d0                     ; less those written
	move.w	d0,-(sp)                        ; argument 1
	jsr	itoa                            ; in decimal
	addq.l	#6,sp                           ; drop the arguments
	pea	chunk_length                    ; the next chunk's length
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	-$a(a6),-(sp)                   ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	tst.l	d0                              ; read?
	bge.s	disk_unpack_loop                ; yes
	move.l	-$8(a6),-(sp)                   ; no: the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	-$a(a6),-(sp)                   ; the handle
	jsr	close_gem                       ; close_gem, as written
	addq.l	#6,sp                           ; drop the arguments
	bra.s	disk_unpack_done
disk_unpack_loop:
	cmpi.l	#$ffffffff,chunk_length         ; the end (-1)?
	bne.w	disk_unpack_chunk
	move.l	-$8(a6),-(sp)                   ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	-$a(a6),-(sp)                   ; the handle
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	pea	disk_rect                       ; its box
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	close_box                       ; closed
	addq.l	#8,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	jsr	clear_title                     ; the background
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; M_ON
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
disk_unpack_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; disk_pack(use_fat, use_boot, no_pack): pack the disk in drive A or B into a .JPK file on drive A, B or C:
; the header, the system sectors (boot, FATs, root directory) as one chunk, then the rest in chunks of 500
; sectors, and a -1 length.  The format comes from the boot sector with Use Boot, else analyse_disk finds it
; (and Use FAT and the system chunk are then dropped).  The sectors are read straight through the FDC and
; each chunk packed with pack_chunk, by the method chosen; with No Pack they are stored as they are and the
; packometer is not shown.  With Use FAT the FAT is read and unpacked into a map, which nothing then uses.
;------------------------------------------------------------------------------
disk_pack:	; from: main
	link	a6,#-78                         ; 78 bytes of locals
	move.l	screen_buffer,-(sp)             ; argument 2
	move.l	screen,-(sp)                    ; argument 1
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	pea	alert_pack_which_drive          ; "Pack disk in which drive?"
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	subq.w	#1,d0                           ; 0 or 1
	move.w	d0,-$10(a6)                     ; the drive to read
	pea	text_root_pack                  ; "\"
	pea	dpk_path                        ; the path
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_dpk_mask_pack              ; "*.JPK"
	pea	dpk_path                        ; argument 1
	jsr	strcat
	addq.l	#8,sp                           ; drop the arguments
	cmpi.w	#$1,-$10(a6)                    ; drive B?
	bne.s	disk_pack_name_a                ; no
	pea	text_driveb_pack                ; yes: "DRIVEB.JPK"
	pea	dpk_name                        ; the name
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	bra.s	disk_pack_save_drive
disk_pack_name_a:
	pea	text_drivea_pack                ; no: "DRIVEA.JPK"
	pea	dpk_name                        ; the name
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
disk_pack_save_drive:
	pea	alert_save_to_which_drive       ; "Save to which drive?"
	move.w	#$1,-(sp)                       ; A, B or C
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	subq.w	#1,d0                           ; 0, 1 or 2
	move.w	d0,-$4a(a6)                     ; the drive to save to
	move.w	-$4a(a6),-(sp)                  ; argument 1
	move.w	#$e,-(sp)                       ; Dsetdrv
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
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
	pea	text_dpk_pack                   ; "JPK"
	pea	dpk_path                        ; as its extension
	jsr	set_extension
	addq.l	#8,sp                           ; drop the arguments
	bra.s	disk_pack_go
disk_pack_cancelled:
	clr.l	-(sp)                           ; the title line cleared
	move.w	#$100,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; no alert
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_go:
	jsr	clear_title                     ; the title line cleared
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	clr.w	-(sp)                           ; normal file
	pea	dpk_path                        ; the JPK file
	move.w	#$3c,-(sp)                      ; Fcreate
	jsr	gemdos
	addq.l	#8,sp                           ; drop the arguments
	move.w	d0,-$12(a6)
	tst.w	d0                              ; created?
	bge.s	disk_pack_format                ; yes
	pea	alert_cannot_create_file        ; no: "Can't create file."
	move.w	#$ffff,-(sp)                    ; no handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_format:
	move.w	$a(a6),d0                       ; Use Boot?
	beq.s	disk_pack_analyse               ; no
	move.w	-$10(a6),-(sp)                  ; yes: the drive
	jsr	read_boot_sector                ; the format from its boot sector
	addq.l	#2,sp                           ; drop the arguments
	bra.s	disk_pack_header
disk_pack_analyse:
	move.w	-$10(a6),-(sp)                  ; the drive
	jsr	analyse_disk                    ; the format found by reading it
	addq.l	#2,sp                           ; drop the arguments
	cmpi.w	#$ffff,d0                       ; failed?
	bne.s	disk_pack_no_fat                ; no
	pea	alert_disk_read_error           ; yes: "Disk read error."
	move.w	-$12(a6),-(sp)                  ; the handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_no_fat:
	clr.w	8(a6)                           ; no Use FAT
	clr.w	system_sectors                  ; and no system sectors
disk_pack_header:
	move.w	disk_sectors,-$6(a6)            ; the sectors left
	move.w	disk_sides,-(sp)                ; sides
	move.w	disk_tracks,-(sp)               ; tracks
	move.w	disk_spt,-(sp)                  ; sectors a track
	move.w	-$12(a6),-(sp)                  ; the handle
	jsr	write_jpk_header                ; the header
	addq.l	#8,sp                           ; drop the arguments
	tst.w	d0                              ; all right?
	bge.s	disk_pack_info                  ; yes
	move.w	#$ffff,d0                       ; no: -1
	bra.w	disk_pack_done
disk_pack_info:
	move.w	-$10(a6),-(sp)                  ; the drive
	jsr	show_disk_info
	addq.l	#2,sp                           ; drop the arguments
	move.w	$a(a6),d0                       ; Use Boot?
	beq.s	disk_pack_no_system             ; no
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
	bra.s	disk_pack_open
disk_pack_no_system:
	pea	text_spaces                     ; spaces
	movea.l	tree_disk,a0                    ; the progress box
	move.l	$9c(a0),-(sp)                   ; the sectors line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
disk_pack_open:
	pea	text_reading_system             ; "Reading Sectors"
	movea.l	tree_disk,a0
	move.l	$84(a0),-(sp)                   ; the action line
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	pea	text_disk_pack_progress         ; "Disk Pack Progress"
	pea	-$44(a6)                        ; argument 1
	jsr	strcpy
	addq.l	#8,sp                           ; drop the arguments
	lea	-$44(a6),a0
	move.l	a0,d0
	movea.l	tree_disk,a0                    ; the progress box
	movea.l	$24(a0),a0                      ; its title's TEDINFO
	move.l	d0,(a0)                         ; its text
	pea	-$44(a6)                        ; argument 1
	jsr	strlen
	addq.l	#4,sp                           ; drop the arguments
	movea.l	tree_disk,a0
	movea.l	$24(a0),a0
	move.w	d0,$18(a0)                      ; its length
	pea	disk_rect                       ; its box
	move.l	tree_disk,-(sp)                 ; the progress box
	jsr	open_box                        ; opened
	addq.l	#8,sp                           ; drop the arguments
	move.w	$c(a6),d0                       ; No Pack?
	bne.s	disk_pack_check_fat             ; yes
	pea	packometer_rect                 ; its box
	move.l	tree_packometer,-(sp)           ; the packometer
	jsr	open_box                        ; opened
	addq.l	#8,sp                           ; drop the arguments
disk_pack_check_fat:
	move.w	8(a6),d0                        ; Use FAT?
	beq.w	disk_pack_buffer                ; no
	move.w	cluster_count,d0                ; the clusters
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2
	move.l	d0,-(sp)                        ; argument 1
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$48(a6)                     ; the map
	tst.l	-$48(a6)
	bne.s	disk_pack_fat
	pea	alert_insufficient_memory       ; argument 2
	move.w	-$12(a6),-(sp)                  ; argument 1
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
	move.l	d0,-$16(a6)                     ; the FAT buffer
	tst.l	-$16(a6)
	bne.s	disk_pack_read_fat
	move.l	-$48(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_insufficient_memory       ; "Insufficient Memory."
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_read_fat:
	move.w	-$10(a6),-(sp)                  ; the drive
	move.w	#$1,-(sp)                       ; from sector 1
	move.w	fat_sectors,-(sp)               ; the FAT's sectors
	move.l	-$16(a6),-(sp)                  ; the FAT buffer
	clr.w	-(sp)                           ; read
	jsr	fdc_sectors                     ; the FAT
	lea	$c(sp),sp                       ; drop the arguments
	ext.l	d0                              ; to a long
	cmp.l	#$0,d0
	bge.s	disk_pack_unpack_fat
	move.l	-$16(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	-$48(a6),-(sp)                  ; the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_cannot_read_fat           ; "Can't read FAT"
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_unpack_fat:
	move.l	-$48(a6),-(sp)
	move.l	-$16(a6),d0
	addq.l	#3,d0                           ; past the media byte entries
	move.l	d0,-(sp)                        ; argument 1
	jsr	unpack_fat                      ; unpacked into the map
	addq.l	#8,sp                           ; drop the arguments
	move.l	-$16(a6),-(sp)                  ; the FAT buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_buffer:
	move.l	#$40800,-(sp)                   ; $4b800 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$4e(a6)                     ; the buffer
	tst.l	-$4e(a6)
	bgt.s	disk_pack_read_system
	move.w	8(a6),d0
	beq.s	disk_pack_no_memory
	move.l	-$48(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_no_memory:
	pea	alert_insufficient_memory       ; "Insufficient Memory."
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_read_system:
	move.w	$a(a6),d0
	beq.w	disk_pack_chunks
	move.w	-$10(a6),-(sp)
	clr.w	-(sp)
	move.w	system_sectors,-(sp)
	move.l	-$4e(a6),d0
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	fdc_sectors                     ; the system sectors
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0
	bge.s	disk_pack_system                ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_system_failed         ; no
	move.l	-$48(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_system_failed:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	-$12(a6),-(sp)                  ; argument 1
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
	move.w	$c(a6),d0                       ; No Pack?
	beq.s	disk_pack_pack_system
	move.w	system_sectors,d0               ; yes: the system sectors as they are
	ext.l	d0                              ; to a long
	asl.l	#1,d0
	asl.l	#8,d0
	move.l	d0,chunk_length
	move.l	-$4e(a6),d0                     ; the sectors read
	add.l	#$800,d0                        ; 2 K into the buffer
	move.l	d0,-$a(a6)
	bra.s	disk_pack_check_system
disk_pack_pack_system:
	pea	-$a(a6)                         ; the packed data's address comes back here
	move.w	system_sectors,d0               ; the system sectors
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2
	asl.l	#8,d0                           ; * 256: bytes
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$4e(a6),-(sp)                  ; argument 1
	jsr	pack_chunk                      ; pack them
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,chunk_length                 ; the packed length
disk_pack_check_system:
	tst.l	chunk_length                    ; aborted?
	bge.s	disk_pack_write_system
	move.w	8(a6),d0
	beq.s	disk_pack_aborted
	move.l	-$48(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; the function
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_aborted:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_pack_aborted         ; "Disk Pack Aborted"
	move.w	-$12(a6),-(sp)                  ; the handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_write_system:
	pea	chunk_length                    ; argument 3
	move.l	#$4,-(sp)                       ; argument 2
	move.w	-$12(a6),-(sp)                  ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	disk_pack_system_write          ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_length_failed         ; no
	move.l	-$48(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_length_failed:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_system_write:
	move.l	-$a(a6),-(sp)                   ; the packed data
	move.l	chunk_length,-(sp)              ; its length
	move.w	-$12(a6),-(sp)                  ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	chunk_length,d0                 ; all written?
	beq.s	disk_pack_system_done           ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_data_failed           ; no
	move.l	-$48(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_data_failed:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_system_done:
	move.w	system_sectors,d0               ; the system sectors
	sub.w	d0,-$6(a6)                      ; less: the sectors left
disk_pack_chunks:
	move.w	$c(a6),d0
	bne.s	disk_pack_chunk_reading
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
disk_pack_chunk_reading:
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
	cmpi.w	#$1f4,-$6(a6)                   ; 500 or more left?
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
	move.w	#$1f4,d0
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
	cmpi.w	#$1f4,-$6(a6)                   ; 500 or more left?
	bge.s	disk_pack_chunk_write_sectors
	move.w	-$10(a6),-(sp)
	move.w	disk_sectors,d0                 ; the total
	sub.w	-$6(a6),d0                      ; less the sectors left: the first
	move.w	d0,-(sp)
	move.w	-$6(a6),-(sp)                   ; the sectors left
	move.l	-$4e(a6),d0                     ; the buffer
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 2
	clr.w	-(sp)                           ; read
	jsr	fdc_sectors
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0
	bge.s	disk_pack_chunk_read            ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_read_failed           ; no
	move.l	-$48(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_read_failed:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_chunk_read:
	bra.s	disk_pack_chunk_pack
disk_pack_chunk_write_sectors:
	move.w	-$10(a6),-(sp)
	move.w	disk_sectors,d0                 ; the total
	sub.w	-$6(a6),d0                      ; less the sectors left: the first
	move.w	d0,-(sp)
	move.w	#$1f4,-(sp)                     ; 500 sectors
	move.l	-$4e(a6),d0
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,-(sp)                        ; argument 2
	clr.w	-(sp)                           ; read
	jsr	fdc_sectors
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0
	bge.s	disk_pack_chunk_pack            ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_read_600_failed       ; no
	move.l	-$48(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_read_600_failed:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; "Disk read error."
	move.w	-$12(a6),-(sp)                  ; argument 1
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
	move.w	$c(a6),d0
	beq.s	disk_pack_chunk_aborted
	cmpi.w	#$1f4,-$6(a6)
	bge.s	disk_pack_chunk_packing
	move.w	-$6(a6),d0
	ext.l	d0                              ; to a long
	asl.l	#1,d0
	asl.l	#8,d0
	move.l	d0,chunk_length
	bra.s	disk_pack_chunk_check
disk_pack_chunk_packing:
	move.l	#$3e800,chunk_length
disk_pack_chunk_check:
	move.l	-$4e(a6),d0
	add.l	#$800,d0
	move.l	d0,-$a(a6)
	bra.w	disk_pack_end
disk_pack_chunk_aborted:
	cmpi.w	#$1f4,-$6(a6)
	bge.w	disk_pack_chunk_write_error
	pea	-$a(a6)                         ; the packed data's address comes back here
	move.w	-$6(a6),d0                      ; the sectors left
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2
	asl.l	#8,d0                           ; * 256: bytes
	move.l	d0,-(sp)                        ; argument 2
	move.l	-$4e(a6),-(sp)                  ; argument 1
	jsr	pack_chunk                      ; pack them
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,chunk_length                 ; the packed length
	move.l	chunk_length,d0
	move.w	-$6(a6),d1
	ext.l	d1                              ; to a long
	asl.l	#1,d1
	asl.l	#8,d1
	cmp.l	d1,d0
	ble.w	disk_pack_chunk_length_written
	move.w	-$10(a6),-(sp)
	move.w	disk_sectors,d0
	sub.w	-$6(a6),d0
	move.w	d0,-(sp)
	move.w	-$6(a6),-(sp)
	move.l	-$4e(a6),d0
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	fdc_sectors
	lea	$c(sp),sp                       ; drop the arguments
	tst.w	d0
	bge.s	disk_pack_chunk_write_failed
	move.w	8(a6),d0
	beq.s	disk_pack_chunk_write
	move.l	-$48(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; the function
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_chunk_write:
	move.l	-$4e(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; the function
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; argument 2
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_chunk_write_failed:
	move.l	-$4e(a6),d0
	add.l	#$800,d0
	move.l	d0,-$a(a6)
	move.w	-$6(a6),d0
	ext.l	d0                              ; to a long
	asl.l	#1,d0
	asl.l	#8,d0
	move.l	d0,chunk_length
disk_pack_chunk_length_written:
	bra.w	disk_pack_end
disk_pack_chunk_write_error:
	pea	-$a(a6)                         ; argument 3
	move.l	#$3e800,-(sp)                   ; argument 2
	move.l	-$4e(a6),-(sp)                  ; argument 1
	jsr	pack_chunk                      ; pack them
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,chunk_length                 ; the packed length
	cmpi.l	#$3e800,chunk_length
	ble.w	disk_pack_end
	move.w	-$10(a6),-(sp)
	move.w	disk_sectors,d0
	sub.w	-$6(a6),d0
	move.w	d0,-(sp)
	move.l	#$3e800,-(sp)
	move.l	-$4e(a6),d0
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 2
	clr.w	-(sp)                           ; argument 1
	jsr	fdc_sectors
	lea	$e(sp),sp                       ; drop the arguments
	tst.w	d0
	bge.s	disk_pack_loop
	move.w	8(a6),d0
	beq.s	disk_pack_chunk_written
	move.l	-$48(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; the function
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_chunk_written:
	move.l	-$4e(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; the function
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_read_error           ; argument 2
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_loop:
	move.l	-$4e(a6),d0
	add.l	#$800,d0
	move.l	d0,-$a(a6)
	move.l	#$3e800,chunk_length
disk_pack_end:
	tst.l	chunk_length
	bge.s	disk_pack_closed
	move.l	-$4e(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; the function
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.w	8(a6),d0
	beq.s	disk_pack_end_write_failed
	move.l	-$48(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; the function
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_end_write_failed:
	pea	alert_disk_pack_aborted         ; argument 2
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_closed:
	pea	chunk_length                    ; argument 3
	move.l	#$4,-(sp)                       ; argument 2
	move.w	-$12(a6),-(sp)                  ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	disk_pack_chunk_data            ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_chunk_length_failed   ; no
	move.l	-$48(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_chunk_length_failed:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_chunk_data:
	move.l	-$a(a6),-(sp)                   ; the packed data
	move.l	chunk_length,-(sp)              ; its length
	move.w	-$12(a6),-(sp)                  ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmp.l	chunk_length,d0                 ; all written?
	beq.s	disk_pack_chunk_done            ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_chunk_data_failed     ; no
	move.l	-$48(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_chunk_data_failed:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_chunk_done:
	subi.w	#$1f4,-$6(a6)                   ; 500 fewer left
	tst.w	-$6(a6)                         ; any left?
	bgt.w	disk_pack_chunks                ; yes: the next chunk
	move.l	#$ffffffff,chunk_length         ; the end: -1
	pea	chunk_length                    ; argument 3
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	-$12(a6),-(sp)                  ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	disk_pack_close                 ; yes
	move.w	8(a6),d0                        ; no: Use FAT?
	beq.s	disk_pack_end_failed            ; no
	move.l	-$48(a6),-(sp)                  ; yes: the map
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_end_failed:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	pea	alert_disk_write_error          ; "Disk write error."
	move.w	-$12(a6),-(sp)                  ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	disk_pack_done
disk_pack_close:
	move.w	-$12(a6),-(sp)                  ; the JPK file
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
	pea	disk_rect                       ; argument 2
	move.l	tree_disk,-(sp)                 ; argument 1
	jsr	close_box
	addq.l	#8,sp                           ; drop the arguments
	move.w	$c(a6),d0
	bne.s	disk_pack_return
	pea	packometer_rect                 ; argument 2
	move.l	tree_packometer,-(sp)           ; argument 1
	jsr	close_box
	addq.l	#8,sp                           ; drop the arguments
disk_pack_return:
	move.w	8(a6),d0
	beq.s	disk_pack_free
	move.l	-$48(a6),-(sp)                  ; argument 1
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
disk_pack_free:
	move.l	-$4e(a6),-(sp)                  ; the buffer
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; the saved screen
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen                     ; back
	addq.l	#8,sp                           ; drop the arguments
	jsr	clear_title
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
disk_pack_done:
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; pack_chunk(buffer, length, &packed): pack the sectors 2 K into the buffer by the method chosen (LZW with a
; work area of its own); *packed = the packed data.  d0 = the packed length, -1 when aborted.
;------------------------------------------------------------------------------
pack_chunk:	; from: disk_pack
	link	a6,#-12                         ; 12 bytes of locals
	move.w	algorithm,d0                    ; the algorithm
	bra.w	pack_chunk_switch               ; which?
pack_chunk_v2:
	move.l	v2_window,-(sp)                 ; the window
	move.l	8(a6),d0                        ; the buffer
	addq.l	#4,d0                           ; + 4: where it packs to
	move.l	d0,-(sp)
	move.l	$c(a6),-(sp)                    ; the length
	move.l	8(a6),d0                        ; the sectors
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_v2                         ; pack them
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	movea.l	$10(a6),a0                      ; where the address goes
	move.l	8(a6),(a0)                      ; the buffer
	bra.w	pack_chunk_done
pack_chunk_lzh:
	pea	-$c(a6)                         ; where the address goes
	move.l	$c(a6),-(sp)                    ; the length
	move.l	8(a6),d0                        ; the sectors
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzh                        ; pack them
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	movea.l	$10(a6),a0                      ; where the address goes
	move.l	-$c(a6),(a0)                    ; the packed data
	bra.w	pack_chunk_done
pack_chunk_ice:
	move.l	v2_window,-(sp)                 ; the window
	move.l	8(a6),-(sp)                     ; the buffer: where it packs to
	move.l	$c(a6),-(sp)                    ; the length
	move.l	8(a6),d0                        ; the sectors
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_ice                        ; pack them
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	movea.l	$10(a6),a0                      ; where the address goes
	move.l	8(a6),(a0)                      ; the buffer
	bra.w	pack_chunk_done
pack_chunk_lzw:
	move.l	#$8534,-(sp)                    ; $8534 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$4(a6)                      ; LZW's work area
	tst.l	-$4(a6)                         ; got it?
	ble.s	pack_chunk_lzw_done             ; no
	pea	-$c(a6)                         ; where the address goes
	move.l	$c(a6),-(sp)                    ; the length
	move.l	-$4(a6),-(sp)                   ; the work area
	move.l	8(a6),d0                        ; the sectors
	add.l	#$800,d0
	move.l	d0,-(sp)                        ; argument 1
	jsr	pack_lzw                        ; pack them
	lea	$10(sp),sp                      ; drop the arguments
	move.l	d0,-$8(a6)                      ; the packed length
	move.l	-$4(a6),-(sp)                   ; the work area
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
pack_chunk_lzw_done:
	movea.l	$10(a6),a0                      ; where the address goes
	move.l	-$c(a6),(a0)                    ; the packed data
	bra.s	pack_chunk_done
pack_chunk_switch:
	cmp.w	#$9,d0                          ; LZH?
	beq.w	pack_chunk_lzh
	cmp.w	#$a,d0                          ; V2?
	beq.w	pack_chunk_v2
	cmp.w	#$c,d0                          ; ICE?
	beq.w	pack_chunk_ice
	cmp.w	#$d,d0                          ; LZW?
	beq.s	pack_chunk_lzw
pack_chunk_done:
	move.l	-$8(a6),d0                      ; returned
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
; write_jpk_header(handle, sectors a track, tracks, sides): 'JPK!' and the three words.  On an error
; disk_error is given the handle and the alert.
;------------------------------------------------------------------------------
write_jpk_header:	; from: disk_pack
	link	a6,#0                           ; the frame
	movem.l	d7,-(sp)                        ; keep the registers
	move.w	8(a6),d7                        ; the handle
	pea	text_jpk_magic                  ; "JPK!"
	move.l	#$4,-(sp)                       ; 4 bytes
	move.w	d7,-(sp)                        ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$4,d0                          ; written?
	beq.s	write_jpk_spt                   ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d7,-(sp)                        ; the handle
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.w	write_jpk_header_done
write_jpk_spt:
	pea	$a(a6)                          ; the sectors a track
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; written?
	beq.s	write_jpk_tracks                ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.s	write_jpk_header_done
write_jpk_tracks:
	pea	$c(a6)                          ; the tracks
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; written?
	beq.s	write_jpk_sides                 ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	bra.s	write_jpk_header_done
write_jpk_sides:
	pea	$e(a6)                          ; the sides
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$40,-(sp)                      ; Fwrite
	jsr	gemdos
	lea	$c(sp),sp                       ; drop the arguments
	cmpi.l	#$2,d0                          ; written?
	beq.s	write_jpk_header_done           ; yes
	pea	alert_disk_write_error          ; no: "Disk write error."
	move.w	d7,-(sp)                        ; argument 1
	jsr	disk_error
	addq.l	#6,sp                           ; drop the arguments
	nop
write_jpk_header_done:
	movem.l	(sp)+,d7                        ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; depack_chunk(packed, destination, length): depack a chunk by its magic (LZH with a 5000 byte work area of
; its own); a chunk with no magic is copied as it is.  d0 = the length depacked (chunk_length).
;------------------------------------------------------------------------------
depack_chunk:	; from: disk_unpack
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the chunk
	move.l	$c(a6),d6                       ; the destination
	move.l	$10(a6),d5                      ; its length
	move.l	d7,-(sp)                        ; the chunk
	jsr	packed_algorithm                ; its algorithm
	addq.l	#4,sp                           ; drop the arguments
	bra.w	depack_chunk_switch             ; which?
depack_chunk_v2:
	move.l	d6,-(sp)                        ; the destination
	move.l	d7,-(sp)                        ; the chunk
	jsr	depack_v2                       ; depack it
	addq.l	#8,sp                           ; drop the arguments
	move.l	d0,chunk_length                 ; the length
	bra.w	depack_chunk_done
depack_chunk_lzh:
	move.l	#$1388,-(sp)                    ; 5000 bytes
	move.w	#$48,-(sp)                      ; Malloc
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,d4                           ; LZH's work area
	tst.l	d4                              ; got it?
	ble.s	depack_chunk_lzh_done           ; no
	move.l	d4,-(sp)                        ; the work area
	move.l	d6,-(sp)                        ; the destination
	move.l	d7,-(sp)                        ; the chunk
	jsr	depack_lzh                      ; depack it
	lea	$c(sp),sp                       ; drop the arguments
	move.l	d0,chunk_length                 ; the length
	move.l	d4,-(sp)                        ; the work area
	move.w	#$49,-(sp)                      ; Mfree
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
depack_chunk_lzh_done:
	bra.w	depack_chunk_done
depack_chunk_ice:
	move.l	d6,-(sp)                        ; the destination
	move.l	d7,-(sp)                        ; the chunk
	jsr	depack_ice                      ; depack it
	addq.l	#8,sp                           ; drop the arguments
	move.l	d0,chunk_length                 ; the length
	bra.w	depack_chunk_done
depack_chunk_lzw:
	move.l	d6,-(sp)                        ; the destination
	move.l	d7,-(sp)                        ; the chunk
	jsr	depack_lzw                      ; depack it
	addq.l	#8,sp                           ; drop the arguments
	move.l	d0,chunk_length                 ; the length
	bra.w	depack_chunk_done
depack_chunk_copy:
	movea.l	d7,a0                           ; the chunk
	movea.l	d6,a1                           ; the destination
	adda.l	d5,a0                           ; its end
	adda.l	d5,a1
	move.l	d5,d0                           ; the length
depack_chunk_copy_loop:
	move.b	-(a0),-(a1)                     ; copied from the end down
	subq.l	#1,d0
	bne.s	depack_chunk_copy_loop
	move.l	d5,d0                           ; returned
	bra.s	depack_chunk_return
	bra.s	depack_chunk_done
	bra.s	depack_chunk_done
depack_chunk_switch:
	cmp.w	#$1,d0                          ; V2?
	beq.w	depack_chunk_v2
	cmp.w	#$2,d0                          ; LZH?
	beq.w	depack_chunk_lzh
	cmp.w	#$3,d0                          ; ICE?
	beq.s	depack_chunk_ice
	cmp.w	#$4,d0                          ; LZW?
	beq.s	depack_chunk_lzw
	jmp	depack_chunk_copy               ; none: copied
depack_chunk_done:
	move.l	chunk_length,d0                 ; the length
depack_chunk_return:
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; format_disk(sides, sectors a track, tracks, drive): Flopfmt every track (side 1 too for 2 sides).
; d0 = 1, or 0 on an error.
;------------------------------------------------------------------------------
format_disk:	; from: disk_unpack
	link	a6,#-6                          ; 6 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7
	move.w	$a(a6),d6
	move.w	$c(a6),d5
	move.w	$e(a6),d4
	move.l	#$5000,-(sp)                    ; argument 1
	move.w	#$48,-(sp)                      ; the function
	jsr	gemdos
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-$4(a6)
	clr.w	-$6(a6)
	bra.w	format_disk_next
format_track:
	move.w	#$e5e5,-(sp)                    ; the virgin word
	move.l	#$87654321,-(sp)                ; the magic
	move.w	#$1,-(sp)                       ; interleave 1
	clr.w	-(sp)                           ; side 0
	move.w	-$6(a6),-(sp)                   ; argument 5
	move.w	d6,-(sp)                        ; argument 4
	move.w	d4,-(sp)                        ; argument 3
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
	move.w	-$6(a6),-(sp)                   ; argument 5
	move.w	d6,-(sp)                        ; argument 4
	move.w	d4,-(sp)                        ; argument 3
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
	addq.w	#1,-$6(a6)                      ; next
format_disk_next:
	move.w	-$6(a6),d0
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
	bge.s	read_boot_sector_ok             ; yes
	pea	alert_disk_read_error           ; no: "Disk read error."
	jsr	disk_error
	addq.l	#4,sp                           ; drop the arguments
	bra.w	read_boot_sector_done
read_boot_sector_ok:
	clr.l	d0
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
; analyse_disk(drive): find a disk's format by reading it with Floprd: the tracks (from 81 down to 70), the
; sectors a track (from 11 down to 1) and the sides.  d0 = -1 when no track or sector can be read.
;------------------------------------------------------------------------------
analyse_disk:	; from: disk_pack
	link	a6,#-512                        ; 512 bytes of locals
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7
	pea	text_analysing                  ; "Analysing disk format"
	jsr	show_title                      ; on the title line
	addq.l	#4,sp                           ; drop the arguments
	move.w	#$52,disk_tracks                ; from 82 tracks
	move.w	#$ffff,d6                       ; none read yet
	bra.s	analyse_disk_tracks_test
analyse_disk_tracks:
	subq.w	#1,disk_tracks                  ; one track less
	move.w	#$1,-(sp)                       ; argument 7
	clr.w	-(sp)                           ; argument 6
	move.w	disk_tracks,-(sp)               ; argument 5
	move.w	#$1,-(sp)                       ; argument 4
	move.w	d7,-(sp)                        ; argument 3
	clr.l	-(sp)                           ; argument 2
	pea	-$200(a6)                       ; argument 1
	move.w	#$8,-(sp)                       ; the function
	jsr	xbios
	lea	$14(sp),sp                      ; drop the arguments
	move.w	d0,d6                           ; the result
analyse_disk_tracks_test:
	tst.w	d6                              ; read?
	bge.s	analyse_disk_tracks_end
	cmpi.w	#$46,disk_tracks                ; down to 70 tracks?
	bgt.s	analyse_disk_tracks
analyse_disk_tracks_end:
	cmpi.w	#$46,disk_tracks                ; none from 81 to 70?
	bne.s	analyse_disk_spt_start
	move.w	#$ffff,d0                       ; -1
	bra.w	analyse_disk_done
analyse_disk_spt_start:
	addq.w	#1,disk_tracks                  ; the last that was read is the last track
	move.w	#$c,disk_spt                    ; from 12 sectors
	move.w	#$ffff,d6                       ; none read yet
	bra.s	analyse_disk_spt_test
analyse_disk_spt:
	subq.w	#1,disk_spt                     ; one sector less
	move.w	#$1,-(sp)
	clr.w	-(sp)
	move.w	disk_tracks,d0
	subq.w	#1,d0
	move.w	d0,-(sp)                        ; argument 5
	move.w	disk_spt,-(sp)                  ; argument 4
	move.w	d7,-(sp)                        ; argument 3
	clr.l	-(sp)                           ; argument 2
	pea	-$200(a6)                       ; argument 1
	move.w	#$8,-(sp)                       ; the function
	jsr	xbios
	lea	$14(sp),sp                      ; drop the arguments
	move.w	d0,d6                           ; the result
analyse_disk_spt_test:
	tst.w	d6                              ; read?
	bge.s	analyse_disk_spt_end
	cmpi.w	#$1,disk_spt                    ; down to 1?
	bgt.s	analyse_disk_spt
analyse_disk_spt_end:
	cmpi.w	#$1,disk_spt                    ; none?
	bne.s	analyse_disk_sides
	move.w	#$ffff,d0                       ; -1
	bra.s	analyse_disk_done
analyse_disk_sides:
	move.w	#$1,-(sp)                       ; 1 sector
	move.w	#$1,-(sp)                       ; side 1
	move.w	disk_tracks,d0
	subq.w	#1,d0
	move.w	d0,-(sp)                        ; argument 5
	move.w	disk_spt,-(sp)                  ; argument 4
	move.w	d7,-(sp)                        ; argument 3
	clr.l	-(sp)                           ; argument 2
	pea	-$200(a6)                       ; argument 1
	move.w	#$8,-(sp)                       ; the function
	jsr	xbios                           ; Floprd
	lea	$14(sp),sp                      ; drop the arguments
	move.w	d0,d6                           ; the result
	tst.w	d6                              ; read?
	bge.s	analyse_disk_two_sides
	move.w	#$1,disk_sides                  ; no: 1 side
	bra.s	analyse_disk_sectors
analyse_disk_two_sides:
	move.w	#$2,disk_sides                  ; 2 sides
analyse_disk_sectors:
	move.w	disk_spt,d0
	muls.w	disk_tracks,d0
	muls.w	disk_sides,d0
	move.w	d0,disk_sectors                 ; the disk's sectors
	jsr	clear_title
	move.w	#$0,d0
analyse_disk_done:
	movem.l	(sp)+,d6-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; disk_error(handle, alert): show the alert (if any), close the handle (if any), put the screen back; d0 = -1.
;------------------------------------------------------------------------------
disk_error:	; from: disk_unpack, disk_pack, write_jpk_header, read_boot_sector
	link	a6,#0                           ; the frame
	movem.l	d7/a5,-(sp)                     ; keep the registers
	move.w	8(a6),d7                        ; the handle
	movea.l	$a(a6),a5                       ; the alert
	move.l	a5,d3
	beq.s	disk_error_close                ; none
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.l	a5,-(sp)                        ; argument 2
	move.w	#$1,-(sp)                       ; argument 1
	jsr	form_alert
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; argument 2
	move.w	#$100,-(sp)                     ; argument 1
	jsr	graf_mouse                      ; form_alert
	addq.l	#6,sp                           ; drop the arguments
disk_error_close:
	tst.w	d7                              ; a handle?
	blt.s	disk_error_screen               ; no
	move.w	d7,-(sp)                        ; argument 1
	move.w	#$3e,-(sp)                      ; Fclose
	jsr	gemdos
	addq.l	#4,sp                           ; drop the arguments
disk_error_screen:
	pea	disk_rect                       ; the saved screen
	move.l	tree_disk,-(sp)                 ; argument 1
	jsr	close_box
	addq.l	#8,sp                           ; drop the arguments
	move.l	screen,-(sp)                    ; argument 2
	move.l	screen_buffer,-(sp)             ; argument 1
	jsr	copy_screen
	addq.l	#8,sp                           ; drop the arguments
	jsr	clear_title
	clr.l	-(sp)                           ; argument 2
	move.w	#$101,-(sp)                     ; argument 1
	jsr	graf_mouse
	addq.l	#6,sp                           ; drop the arguments
	move.w	#$ffff,d0
	movem.l	(sp)+,d7/a5                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; set_extension(name, extension): put the extension after the name's dot, adding one when there is none.
;------------------------------------------------------------------------------
set_extension:	; from: disk_pack
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
; pack_lzh(source, length, &packed): the LZH packer, LHarc 1.13's lzhuf (LZSS over a 4 K window with an
; adaptive Huffman code) compiled from C.  It reads the source from its end and writes the code downwards from
; source + length + $800, so that it can be depacked in place.  The header in front is 'LZH!', the unpacked
; length and the packed length.  *packed = the header; d0 = the packed length + 12.
;------------------------------------------------------------------------------
pack_lzh:	; from: pack_file, multi_pack_file, pack_chunk
	link	a6,#-2                          ; 2 bytes of locals
	movem.l	d7/a4-a5,-(sp)                  ; keep the registers
	movea.l	8(a6),a5                        ; the source
	move.l	$c(a6),d7                       ; its length
	movea.l	$10(a6),a4                      ; where the address goes
	clr.l	codesize                        ; no code yet
	clr.l	textsize                        ; nothing read yet
	clr.w	bar_lines
	move.l	a5,lzh_source                   ; the source
	move.l	d7,d0
	subq.l	#1,d0                           ; read from the last byte
	move.l	d0,lzh_source_index
	move.l	a5,d0
	add.l	d7,d0                           ; the source's end
	add.l	#$800,d0                        ; + 2 K
	move.l	d0,lzh_output                   ; is where the code ends
	jsr	encode
	beq.s	pack_lzh_finish_bar             ; not aborted?
	move.l	#$ffffffff,d0                   ; aborted: -1
	bra.w	pack_lzh_done
pack_lzh_finish_bar:
	movem.l	d0-d2/a0-a2/a5,-(sp)            ; keep the registers
pack_lzh_bar_loop:
	move.w	bar_lines,d1                    ; the bar's lines drawn
	cmp.w	bar_height,d1                   ; all of it?
	bge.s	pack_lzh_header                 ; yes
	addq.w	#1,d1                           ; no: one more
	move.w	d1,bar_lines
	movea.l	bar_address,a5                  ; where it goes
	move.w	#$ffff,(a5)                     ; a line of the bar
	move.w	#$ffff,2(a5)
	cmpi.w	#$2,resolution                  ; high resolution?
	beq.s	pack_lzh_bar_up                 ; yes: 2 words
	move.w	#$ffff,4(a5)                    ; no: 4 words
	move.w	#$ffff,6(a5)
pack_lzh_bar_up:
	suba.l	bar_line_bytes,a5               ; a line up
	move.l	a5,bar_address
	bra.s	pack_lzh_bar_loop
pack_lzh_header:
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
	movem.l	(sp)+,d0-d2/a0-a2/a5            ; the registers back
	move.l	lzh_output,(a4)                 ; returned
	move.l	codesize,d0                     ; the length
pack_lzh_done:
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
	move.w	#$1,d5
	move.w	d7,d0
	lea	text_buf,a0
	ext.l	d0                              ; to a long
	add.l	a0,d0
	movea.l	d0,a5
	move.b	1(a5),d0
	and.w	#$ff,d0
	move.b	2(a5),d3
	and.w	#$ff,d3
	eor.w	d3,d0
	move.w	d0,-$2(a6)
	move.w	-$2(a6),d0
	lsr.w	#4,d0
	eor.w	d0,-$2(a6)
	move.w	#$1001,d6
	move.b	(a5),d3
	and.w	#$ff,d3
	add.w	d3,d6
	move.w	-$2(a6),d1
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
	move.w	#$1,d0
	move.w	d0,-$4(a6)
	move.w	d0,-$2(a6)
insert_node_loop:
	tst.w	d5                              ; cmp >= 0?
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
	move.w	-$2(a6),d0
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
	move.w	-$2(a6),d0
	lea	same,a0
	move.b	d0,0(a0,d7.w)
	bra.w	insert_node_done
insert_node_compare:
	move.w	-$2(a6),d0                      ; i > same[p]?
	cmp.w	-$4(a6),d0
	bls.s	insert_node_equal
	move.w	-$4(a6),-$2(a6)
	move.w	d6,d1
	add.w	-$2(a6),d1
	lea	text_buf,a0
	move.b	0(a0,d1.w),d1
	move.w	-$2(a6),d5
	move.b	0(a5,d5.w),d5
	and.w	#$ff,d5
	and.w	#$ff,d1
	sub.w	d1,d5
	bra.s	insert_node_found
insert_node_equal:
	move.w	-$2(a6),d0
	cmp.w	-$4(a6),d0
	bne.s	insert_node_found
	bra.s	insert_node_scan_loop
insert_node_scan:
	move.w	d6,d1
	add.w	-$2(a6),d1
	lea	text_buf,a0
	move.b	0(a0,d1.w),d1
	move.w	-$2(a6),d0
	move.b	0(a5,d0.w),d0
	and.w	#$ff,d0
	and.w	#$ff,d1
	sub.w	d1,d0
	move.w	d0,d5
	tst.w	d0
	beq.s	insert_node_scan_next
	bra.s	insert_node_found
insert_node_scan_next:
	addq.w	#1,-$2(a6)
insert_node_scan_loop:
	cmpi.w	#$3c,-$2(a6)
	bcs.s	insert_node_scan
insert_node_found:
	cmpi.w	#$2,-$2(a6)
	bls.s	insert_node_next
	move.w	-$2(a6),d0
	cmp.w	match_length,d0                 ; longer than match_length?
	bls.s	insert_node_same_length         ; no
	move.w	d7,d0                           ; yes: match_position = (r - p) & (N-1) - 1
	sub.w	d6,d0
	and.w	#$fff,d0
	subq.w	#1,d0
	move.w	d0,match_position
	move.w	-$2(a6),d0
	move.w	d0,match_length
	cmpi.w	#$3c,d0
	bcs.s	insert_node_longer
	bra.s	insert_node_replace
insert_node_longer:
	bra.s	insert_node_next
insert_node_same_length:
	move.w	-$2(a6),d0                      ; the same length?
	cmp.w	match_length,d0
	bne.s	insert_node_next                ; no
	move.w	d7,d0                           ; yes: a nearer one?
	sub.w	d6,d0
	and.w	#$fff,d0
	subq.w	#1,d0
	move.w	d0,d4
	cmp.w	match_position,d0
	bcc.s	insert_node_next
	move.w	d4,match_position
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
	movem.l	d5-d7/a3-a5,-(sp)               ; keep the registers
	move.w	8(a6),d7
	move.w	$a(a6),d6
	move.w	$c(a6),d5
	cmpi.w	#$1000,d6
	blt.s	lzh_link_compare
	lea	same,a0
	move.b	#$1,0(a0,d5.w)
	bra.s	lzh_link_done
lzh_link_compare:
	lea	text_buf,a0
	move.l	a0,d0
	ext.l	d6                              ; to a long
	add.l	d6,d0
	ext.l	d7                              ; to a long
	add.l	d7,d0
	movea.l	d0,a5                           ; s1
	lea	text_buf,a0
	move.l	a0,d0
	ext.l	d5                              ; to a long
	add.l	d5,d0
	ext.l	d7                              ; to a long
	add.l	d7,d0
	movea.l	d0,a4                           ; s2 = text_buf + q + n
	lea	text_buf,a0
	move.l	a0,d0
	ext.l	d6                              ; to a long
	add.l	d6,d0
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
	sub.w	d6,d0
	lea	same,a0
	move.b	d0,0(a0,d5.w)
	bra.s	lzh_link_done
lzh_link_next:
	move.l	a5,d0
	cmp.l	a3,d0                           ; to F?
	blt.s	lzh_link_loop                   ; no: on
	lea	same,a0
	move.b	#$3c,0(a0,d5.w)
lzh_link_done:
	movem.l	(sp)+,d5-d7/a3-a5               ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; linknode(p, q, r): after a node moves, keep same[r] right: equal same values need a new comparison.
;------------------------------------------------------------------------------
lzh_linknode:	; from: delete_node
	link	a6,#0                           ; the frame
	movem.l	d4-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7
	move.w	$a(a6),d6
	move.w	$c(a6),d5
	lea	same,a0
	move.b	0(a0,d6.w),d0
	lea	same,a0
	and.w	#$ff,d0
	move.b	0(a0,d5.w),d3
	and.w	#$ff,d3
	sub.w	d3,d0
	move.w	d0,d4
	tst.w	d0
	bne.s	lzh_linknode_same
	move.w	d5,-(sp)
	move.w	d7,-(sp)
	lea	same,a0
	move.b	0(a0,d6.w),d0
	and.w	#$ff,d0
	move.w	d0,-(sp)                        ; n = same[q]
	jsr	lzh_link                        ; link(n, p, r)
	addq.l	#6,sp                           ; drop the arguments
	bra.s	lzh_linknode_done
lzh_linknode_same:
	tst.w	d4
	bge.s	lzh_linknode_done
	lea	same,a0
	move.b	0(a0,d6.w),d0
	lea	same,a0
	and.w	#$ff,d0
	move.b	d0,0(a0,d5.w)
lzh_linknode_done:
	movem.l	(sp)+,d4-d7                     ; the registers back
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
	link	a6,#-2                          ; 2 bytes of locals
	movem.l	d4-d7/a5,-(sp)                  ; keep the registers
	move.w	8(a6),d7
	cmpi.w	#$8000,freq+$4e4                ; the root's frequency $8000?
	bne.s	update_start                    ; no
	jsr	reconst                         ; yes: rebuild
update_start:
	move.w	d7,d0                           ; c = prnt[c + T]
	asl.w	#1,d0                           ; * 2: words
	lea	prnt+$4e6,a0
	move.w	0(a0,d0.w),d7
update_loop:
	move.w	d7,d4                           ; freq[c]++
	asl.w	#1,d4                           ; * 2: words
	lea	freq,a0
	addq.w	#1,0(a0,d4.w)
	move.w	0(a0,d4.w),d4
	move.w	d7,d1
	addq.w	#1,d1
	move.w	d1,-$2(a6)
	asl.w	#1,d1                           ; * 2: words
	lea	freq,a0
	move.w	0(a0,d1.w),d1
	move.w	d4,d0
	cmp.w	d1,d0
	bls.w	update_next                     ; more than freq[c + 1]?
	lea	freq,a0                         ; from &freq[l + 1]
	move.l	a0,d0
	move.w	-$2(a6),d1
	asl.w	#1,d1
	ext.l	d1                              ; to a long
	add.l	d1,d0
	addq.l	#2,d0
	movea.l	d0,a5
	nop
update_find:
	move.w	d4,d0
	cmp.w	(a5)+,d0
	bhi.s	update_find
	move.l	a5,d0
	lea	freq,a0
	sub.l	a0,d0
	asr.l	#1,d0
	subq.w	#2,d0
	move.w	d0,-$2(a6)
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	freq,a0
	move.w	-$4(a5),0(a0,d0.w)
	move.w	d4,-$4(a5)
	move.w	d7,d6
	asl.w	#1,d6                           ; * 2: words
	lea	son,a0
	move.w	0(a0,d6.w),d6
	move.w	d6,d0                           ; prnt[j] = c
	asl.w	#1,d0                           ; * 2: words
	lea	prnt,a0
	move.w	-$2(a6),0(a0,d0.w)
	cmpi.w	#$273,d6                        ; j < T?
	bge.s	update_swap_done                ; no
	move.w	d6,d0                           ; prnt[j + 1] = c
	asl.w	#1,d0                           ; * 2: words
	lea	prnt+2,a0
	move.w	-$2(a6),0(a0,d0.w)
update_swap_done:
	move.w	-$2(a6),d5                      ; son[c] = j
	asl.w	#1,d5                           ; * 2: words
	lea	son,a0
	move.w	0(a0,d5.w),d5
	move.w	-$2(a6),d0
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0
	move.w	d6,0(a0,d0.w)
	move.w	d5,d0
	asl.w	#1,d0                           ; * 2: words
	lea	prnt,a0
	move.w	d7,0(a0,d0.w)
	cmpi.w	#$273,d5
	bge.s	update_swap_son
	move.w	d5,d0
	asl.w	#1,d0                           ; * 2: words
	lea	prnt+2,a0
	move.w	d7,0(a0,d0.w)
update_swap_son:
	move.w	d7,d0
	asl.w	#1,d0                           ; * 2: words
	lea	son,a0
	move.w	d5,0(a0,d0.w)
	move.w	-$2(a6),d7
update_next:
	move.w	d7,d0                           ; c = prnt[c]
	asl.w	#1,d0                           ; * 2: words
	lea	prnt,a0
	move.w	0(a0,d0.w),d0
	move.w	d0,d7
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
	movem.l	d4-d7/a5,-(sp)                  ; keep the registers
	move.w	8(a6),d7
	clr.l	d6
	clr.w	d5
	lea	prnt,a0
	movea.l	a0,a5
	move.w	d7,d4
	and.l	#$ffff,d4
	asl.l	#1,d4
	add.l	a5,d4
	movea.l	d4,a0
	move.w	$4e6(a0),d4
encode_char_loop:
	move.l	d6,d0
	lsr.l	#1,d0
	move.l	d0,d6
	move.w	d4,d0
	and.w	#$1,d0
	beq.s	encode_char_next                ; no
	move.l	#$80000000,d0                   ; yes: the bit set
	add.l	d0,d6
encode_char_next:
	addq.w	#1,d5                           ; one more bit
	move.w	d4,d0
	ext.l	d0                              ; to a long
	asl.l	#1,d0                           ; * 2: words
	move.w	0(a5,d0.l),d0                   ; k = prnt[k]
	move.w	d0,d4
	cmpi.w	#$272,d0
	bne.s	encode_char_loop
	cmpi.w	#$10,d5
	ble.s	encode_char_short
	move.l	d6,d0
	lsr.l	#8,d0
	lsr.l	#8,d0
	move.w	d0,-(sp)                        ; argument 2
	move.w	#$10,-(sp)                      ; argument 1
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
	move.l	d6,d0
	move.w	d0,-(sp)
	move.w	d5,d0
	sub.w	#$10,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
	bra.s	encode_char_update
encode_char_short:
	move.l	d6,d0
	lsr.l	#8,d0
	lsr.l	#8,d0
	move.w	d0,-(sp)                        ; argument 2
	move.w	d5,-(sp)                        ; argument 1
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
encode_char_update:
	move.w	d7,-(sp)                        ; c
	jsr	update
	addq.l	#2,sp                           ; drop the arguments
	movem.l	(sp)+,d4-d7/a5                  ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; EncodePosition(c): the upper 6 bits of the position through p_code/p_len, the lower 6 bits plain.
;------------------------------------------------------------------------------
encode_position:	; from: encode
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.w	8(a6),d7
	move.w	d7,d6
	lsr.w	#6,d6
	lea	p_code,a0
	move.b	0(a0,d6.w),d0
	and.w	#$ff,d0
	asl.w	#8,d0                           ; at the top of the word
	move.w	d0,-(sp)
	lea	p_len,a0
	move.b	0(a0,d6.w),d0
	and.w	#$ff,d0
	move.w	d0,-(sp)                        ; argument 1
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
	move.w	d7,d0
	and.w	#$3f,d0                         ; the lower 6 bits
	asl.w	#2,d0                           ; at the top of the word
	asl.w	#8,d0
	move.w	d0,-(sp)                        ; argument 2
	move.w	#$6,-(sp)                       ; 6 bits
	jsr	putcode
	addq.l	#4,sp                           ; drop the arguments
	movem.l	(sp)+,d6-d7                     ; the registers back
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
	link	a6,#-6                          ; 6 bytes of locals
	movem.l	d4-d7,-(sp)                     ; keep the registers
	clr.w	-$6(a6)                         ; the aborted flag (-6(a6)) clear
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
	move.l	d0,bar_line_bytes
	mulu.w	bar_offset,d0                   ; times the bar's distance from the bottom
	move.w	bar_column,d1                   ; the bar's column
	mulu.w	#$4,d1                          ; * 4 bytes
	move.l	#$a0,d2
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a5
	move.l	a5,bar_address
	bra.s	encode_start
encode_high:
	move.l	#$50,d0                         ; 80 bytes a line
	move.l	d0,bar_line_bytes
	mulu.w	bar_offset,d0                   ; times the bar's distance from the bottom
	move.w	bar_column,d1                   ; the bar's column
	mulu.w	#$2,d1                          ; * 2 bytes
	move.l	#$50,d2
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a5
	move.l	a5,bar_address
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
	ble.s	encode_check_abort              ; no
	move.l	bar_step,d0                     ; yes: the next one
	add.l	d0,bar_next
	movem.l	d0-d2/a0-a2/a5,-(sp)            ; keep the registers
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	trap	#13                             ; Kbshift
	addq.l	#4,sp                           ; drop the arguments
	btst	#$3,d0                          ; Alternate?
	beq.s	encode_bar_line                 ; no
	move.w	#$1,-$6(a6)                     ; yes: aborted
	bra.s	encode_bar_done
encode_bar_line:
	move.w	bar_lines,d1                    ; the bar's lines drawn
	cmp.w	bar_height,d1                   ; all of it?
	bge.s	encode_bar_done                 ; yes
	addq.w	#1,d1                           ; no: one more
	move.w	d1,bar_lines
	movea.l	bar_address,a5                  ; where it goes
	move.w	#$ffff,(a5)                     ; a line of the bar
	move.w	#$ffff,2(a5)
	cmpi.w	#$2,resolution                  ; high resolution?
	beq.s	encode_bar_up                   ; yes: 2 words
	move.w	#$ffff,4(a5)                    ; no: 4 words
	move.w	#$ffff,6(a5)
encode_bar_up:
	suba.l	bar_line_bytes,a5               ; a line up
	move.l	a5,bar_address
encode_bar_done:
	movem.l	(sp)+,d0-d2/a0-a2/a5            ; the registers back
encode_check_abort:
	move.w	-$6(a6),d0                      ; aborted?
	beq.s	encode_flush                    ; no
	move.w	#$1,d0                          ; yes: d0 = 1
	bra.s	encode_return
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
	move.w	#$0,d0
encode_return:
	movem.l	(sp)+,d4-d7                     ; the registers back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; depack_lzh(packed, destination): depack 'LZH!' data with the program's own decoder, in supervisor mode.
; d0 = the unpacked length.
;------------------------------------------------------------------------------
depack_lzh:	; from: unpack_file, depack_chunk
	link	a6,#0                           ; the frame
	movem.l	d5-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the packed data
	move.l	$c(a6),d6                       ; the destination
	move.l	$10(a6),d5
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
	move.l	d0,-(sp)
	movea.l	d7,a5                           ; a5 = the packed data
	move.l	4(a5),-(sp)                     ; its unpacked length
	movea.l	d6,a6                           ; a6 = the destination
	lea	depack_lzh_ssp(pc),a0
	move.l	d5,(a0)
	move.w	$ffff8240.w,-(sp)               ; palette 0
	bsr.w	lzh_decode
	move.w	(sp)+,$ffff8240.w               ; palette 0
	move.l	(sp)+,d7
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d7,d0                           ; returned
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	unlk	a6                              ; the frame back
	rts
depack_lzh_ssp:	; from: lzh_decode
	dc.l	$00000000                       ; the stack Super returned

;------------------------------------------------------------------------------
; As lzh_stub_reconst, in the copy the program uses itself.
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
; As lzh_stub_make_tables, in the copy the program uses itself.
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
; As lzh_stub_start_huff, in the copy the program uses itself.
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
; As lzh_stub_depack, in the copy the program uses itself.
;------------------------------------------------------------------------------
lzh_decode:	; from: depack_lzh
	lea	lzh_freq(pc),a0                 ; the table pointers
	move.l	depack_lzh_ssp(pc),d1
	move.w	#$7,d0                          ; 8 pointers
lzh_tables_relocate:
	add.l	d1,(a0)+                        ; made absolute
	dbra	d0,lzh_tables_relocate
	movea.l	d1,a0                           ; the work area
	move.w	#$4e0,d0                        ; $1500 bytes
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
	dc.l	$0000122a
	dc.w	$4cdf,$00e0,$4e5e               ; not used: left-over code (movem.l (sp)+,d5-d7, unlk a6, rts)
	dc.w	$4e75

;------------------------------------------------------------------------------
; The LZH program stub ("JAM Packer Decrunch V4.0"), put in front of a program packed with LZH.
; Each stub keeps the registers, clears the top of the screen and prints its title (unless Heading is off),
; depacks the program $100 bytes past its own end flashing the background (unless Flash is off), relocates
; it to run where the stub starts, sets the basepage and runs a mover from the screen that copies it down,
; clears its BSS (at least $400 bytes, $1a00 for LZH), puts the registers back and jumps to it.  The packed
; data follows the stub.
;------------------------------------------------------------------------------
lzh_stub:	; from: write_program, pack_file, multi_pack_file
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
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
	beq.s	lzh_stub_clear                  ; yes
	move.w	#$167,d1                        ; 360 longs otherwise
lzh_stub_clear:	; from: set_stub_options
	clr.l	(a2)+                           ; clear the top of the screen (a nop without Heading)
	dbra	d1,lzh_stub_clear
	lea	lzh_stub_text(pc),a1            ; the title
	move.b	#$3c,5(a1)                      ; column 28
	cmp.b	#$0,d0                          ; low resolution?
	bne.s	lzh_stub_title                  ; no
	move.b	#$28,5(a1)                      ; yes: column 8
lzh_stub_title:
	pea	lzh_stub_text(pc)               ; the title
	move.w	#$9,-(sp)
lzh_stub_print:	; from: set_stub_options
	trap	#1                              ; Cconws, Cconws (a nop without Heading)
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; kept
	move.w	$ffff8240.w,-(sp)               ; palette 0
	lea	lzh_stub+$48e(pc),a5            ; the packed data after the stub
	movea.l	a5,a6
	adda.l	#$100,a6                        ; a6 = $400 above it
	move.l	4(a5),-(sp)                     ; the unpacked length
	bsr.w	lzh_stub_depack                 ; depack
	movea.l	(sp)+,a6
	move.w	(sp)+,$ffff8240.w               ; palette 0
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	lzh_stub+$48e(pc),a3            ; the depacked program: $100 bytes on
	adda.l	#$100,a3
	movea.l	a3,a1
	movea.l	2(a3),a0                        ; text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	adda.l	#$1c,a0                         ; + the header
	adda.l	a3,a0                           ; a0 = its relocation table
	lea	lzh_stub(pc),a5                 ; where it will run: the stub's text
	move.l	a5,d0
	adda.l	#$1c,a1                         ; its text
	tst.l	(a0)                            ; any relocation?
	beq.s	lzh_stub_relocated              ; no
	adda.l	(a0)+,a1                        ; the first address
lzh_stub_relocate:
	add.l	d0,(a1)                         ; relocate a long
lzh_stub_relocate_next:
	clr.l	d1
	move.b	(a0)+,d1                        ; the next step
	tst.w	d1
	beq.s	lzh_stub_relocated              ; the end?
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	lzh_stub_relocate_step          ; no
	adda.l	#$fe,a1                         ; yes
	bra.s	lzh_stub_relocate_next
lzh_stub_relocate_step:
	adda.l	d1,a1                           ; on to the next long
	bra.s	lzh_stub_relocate               ; relocate it
lzh_stub_relocated:
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
	moveq	#95,d2
	lea	lzh_stub_mover(pc),a1           ; the mover
lzh_stub_copy_mover:
	move.b	(a1)+,(a2)+                     ; copied
	dbra	d2,lzh_stub_copy_mover
	movea.l	a3,a1                           ; the depacked text
	adda.l	#$1c,a1
	lea	lzh_stub(pc),a0                 ; where it runs
	movea.l	a0,a2
	jmp	(a5)                            ; run the mover
lzh_stub_mover:
	lea	lzh_stub_start+2(pc),a6         ; where the last jump goes
	move.l	a0,(a6)                         ; the start of the program, put in it
lzh_stub_mover_copy:
	move.l	(a1)+,(a2)+                     ; copy the program down, 16 bytes at a time
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	cmpa.l	d1,a2                           ; to the BSS?
	ble.s	lzh_stub_mover_copy
	lea	-$100(a0),a1                    ; the basepage
	movea.l	$18(a1),a3                      ; its BSS
	move.l	$1c(a1),d1                      ; its length
	cmp.l	#$1a00,d1                       ; at least $400 bytes
	bgt.s	lzh_stub_clear_size             ; yes
	move.l	#$1a00,d1                       ; no: $400
lzh_stub_clear_size:
	lsr.l	#4,d1                           ; in 16 bytes
lzh_stub_clear_bss:
	clr.l	(a3)+                           ; cleared
	clr.l	(a3)+
	clr.l	(a3)+
	clr.l	(a3)+
	subq.l	#1,d1                           ; less one
	bge.s	lzh_stub_clear_bss
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	clr.l	d0                              ; d0 = 0
lzh_stub_start:
	jmp	$0                              ; start the program (the mover puts its address in)

;------------------------------------------------------------------------------
; The stub's LZH decoder: LHarc's Huffman decoding in assembly.  reconst rebuilds the tree when the
; root's frequency reaches $8000.
;------------------------------------------------------------------------------
lzh_stub_reconst:	; from: lzh_stub_start_huff
	movem.w	d0-d1/d3/d5,-(sp)               ; a0 = prnt, a1 = son, a3 = freq, d7 = T * 2
	movea.l	a1,a2                           ; a2 walks son
	moveq	#0,d2                           ; d2 = the next node to fill
	moveq	#-2,d4                          ; d4 = the leaf being looked at
	moveq	#0,d1                           ; d1 = the next pair of nodes to join
	move.w	#$139,d5                        ; 314 leaves
lzh_stub_reconst_leaves:
	addq.w	#2,d4                           ; the next entry
	cmp.w	(a2)+,d7                        ; a leaf (son >= T)?
	bhi.s	lzh_stub_reconst_leaves         ; no: on
	move.w	0(a3,d4.w),d3                   ; its frequency
	addq.w	#1,d3                           ; halved, rounding up
	lsr.w	#1,d3
	cmp.w	-$2(a3,d2.w),d3                 ; no more than the last node's?
	bls.s	lzh_stub_reconst_leaf           ; yes: the leaf next
	move.w	0(a3,d1.w),d0                   ; the next pair's sum
	add.w	2(a3,d1.w),d0
	cmp.w	d0,d3                           ; the leaf no more?
	bls.s	lzh_stub_reconst_leaf           ; yes: the leaf next
lzh_stub_reconst_node:
	move.w	d0,0(a3,d2.w)                   ; a node: freq = the sum
	move.w	d1,0(a1,d2.w)                   ; son = the pair
	move.w	d2,0(a0,d1.w)                   ; prnt of both = it
	move.w	d2,2(a0,d1.w)
	addq.w	#2,d2                           ; the next node
	addq.l	#4,d1                           ; the next pair
	move.w	0(a3,d1.w),d0                   ; its sum
	add.w	2(a3,d1.w),d0
	cmp.w	d0,d3                           ; the leaf still bigger?
	bhi.s	lzh_stub_reconst_node           ; yes: another node
lzh_stub_reconst_leaf:
	move.w	d3,0(a3,d2.w)                   ; the leaf: its frequency
	move.w	0(a1,d4.w),d0                   ; son = the leaf's own
	move.w	d0,0(a1,d2.w)
	move.w	d2,0(a0,d0.w)                   ; prnt of the leaf = it
	addq.w	#2,d2                           ; the next node
	dbra	d5,lzh_stub_reconst_leaves      ; the next leaf
lzh_stub_reconst_rest:
	move.w	0(a3,d1.w),d0                   ; the rest are nodes: the pair's sum
	add.w	2(a3,d1.w),d0
	move.w	d0,0(a3,d2.w)                   ; freq
	move.w	d1,0(a1,d2.w)                   ; son = the pair
	move.w	d2,0(a0,d1.w)                   ; prnt of both = it
	move.w	d2,2(a0,d1.w)
	addq.w	#2,d2                           ; the next node
	addq.l	#4,d1                           ; the next pair
	cmp.w	d7,d2                           ; up to T?
	bne.s	lzh_stub_reconst_rest           ; no
	movem.w	(sp)+,d0-d1/d3/d5               ; the registers back
	rts

;------------------------------------------------------------------------------
; Make the d_code and d_len tables for the upper 6 bits of a position.
;------------------------------------------------------------------------------
lzh_stub_make_tables:	; from: lzh_stub_depack
	movea.l	lzh_stub_d_code(pc),a0          ; d_code
	lea	lzh_stub_d_code_counts(pc),a1   ; its counts
	moveq	#0,d0                           ; d0 = the code, 4 times
	moveq	#31,d1                          ; the first 32 bytes
	moveq	#0,d2                           ; 3 nibbles before the next word
lzh_stub_make_code:
	move.b	d0,(a0)+                        ; the code
	dbra	d1,lzh_stub_make_code           ; as many times as the count
	dbra	d2,lzh_stub_make_code_next      ; a nibble left?
	move.w	(a1)+,d3                        ; no: the next 4 nibbles
	moveq	#3,d2
lzh_stub_make_code_next:
	rol.w	#4,d3                           ; the next nibble
	move.w	d3,d1                           ; the count less one
	andi.w	#$f,d1
	addq.b	#4,d0                           ; the next code
	bcc.s	lzh_stub_make_code              ; all 64 done?
	movea.l	lzh_stub_d_len(pc),a0           ; d_len
	lea	lzh_stub_d_len_counts(pc),a1    ; its counts
	moveq	#5,d0                           ; 6 counts, read from the last
	moveq	#3,d1                           ; from 3 bits
lzh_stub_make_len:
	move.b	0(a1,d0.w),d2                   ; the count less one
	ext.w	d2                              ; to a word
lzh_stub_make_len_loop:
	move.b	d1,(a0)+                        ; the length
	dbra	d2,lzh_stub_make_len_loop       ; as many times
	addq.w	#1,d1                           ; one bit more
	dbra	d0,lzh_stub_make_len            ; the next count
	rts

;------------------------------------------------------------------------------
; Set up the Huffman tree with every character seen once.
;------------------------------------------------------------------------------
lzh_stub_start_huff:	; from: lzh_stub_depack
	movea.l	lzh_stub_freq(pc),a0            ; freq
	movea.l	lzh_stub_son(pc),a1             ; son
	movea.l	lzh_stub_prnt_leaves(pc),a2     ; prnt + T
	moveq	#1,d1                           ; every leaf seen once
	move.w	#$4e6,d2                        ; son = (i + T) * 2
	moveq	#0,d4                           ; prnt[i + T] = i * 2
	move.w	#$139,d0                        ; 314 leaves
lzh_stub_start_leaves:
	move.w	d1,(a0)+                        ; freq
	move.w	d2,(a1)+                        ; son
	move.w	d4,(a2)+                        ; prnt
	addq.w	#2,d2                           ; the next leaf
	addq.w	#2,d4
	dbra	d0,lzh_stub_start_leaves
	movea.l	lzh_stub_freq(pc),a0            ; the leaves
	movea.l	lzh_stub_freq_nodes(pc),a3      ; the nodes
	movea.l	lzh_stub_son_nodes(pc),a1       ; their sons
	movea.l	lzh_stub_prnt(pc),a2            ; the prnt of the leaves and nodes
	move.w	#$274,d2                        ; the first node (N_CHAR * 2)
	moveq	#0,d4                           ; the first pair
	move.w	#$138,d0                        ; 313 nodes
lzh_stub_start_nodes:
	move.w	(a0)+,d1                        ; the pair's frequencies
	add.w	(a0)+,d1                        ; added
	move.w	d1,(a3)+                        ; freq
	move.w	d4,(a1)+                        ; son = the pair
	move.w	d2,(a2)+                        ; prnt of both = the node
	move.w	d2,(a2)+
	addq.w	#4,d4                           ; the next pair
	addq.w	#2,d2                           ; the next node
	dbra	d0,lzh_stub_start_nodes
	move.w	#$ffff,(a3)                     ; freq[T] = $ffff, a guard
	clr.w	(a2)                            ; prnt[R] = 0, the root
	rts
lzh_stub_reconst_and_update:	; from: lzh_stub_depack
	bsr.w	lzh_stub_reconst                ; the tree rebuilt
	bra.w	lzh_stub_update                 ; then updated
lzh_stub_depack_done:	; from: lzh_stub_depack
	addq.l	#4,sp                           ; the output's start
	rts

;------------------------------------------------------------------------------
; Depack 'LZH!' data (a5 = it) to a6, from the end of the packed data down; the tables live in a work area
; $1500 bytes below the stack.
;------------------------------------------------------------------------------
lzh_stub_depack:	; from: lzh_stub
	lea	lzh_stub_freq(pc),a0            ; the table pointers
	move.l	a6,d1
	add.l	4(a5),d1
	btst	#$0,d1
	beq.s	lzh_stub_fill_even
	addq.l	#1,d1
lzh_stub_fill_even:
	add.l	#$3e,d1
	move.w	#$7,d0                          ; 8 pointers
lzh_stub_tables_relocate:
	add.l	d1,(a0)+                        ; made absolute
	dbra	d0,lzh_stub_tables_relocate
	movea.l	d1,a0                           ; the work area
	move.w	#$4e0,d0                        ; $1500 bytes
lzh_stub_clear_work:
	clr.l	(a0)+                           ; cleared
	dbra	d0,lzh_stub_clear_work
	bsr.w	lzh_stub_make_tables            ; d_code and d_len
	bsr.w	lzh_stub_start_huff             ; the tree
	movea.l	lzh_stub_prnt(pc),a0
	movea.l	lzh_stub_son(pc),a1
	movea.l	lzh_stub_freq(pc),a3
	move.l	a6,-(sp)                        ; the output's start, kept
	adda.l	4(a5),a6                        ; + the unpacked length: its end
	adda.l	8(a5),a5                        ; + the packed length
	adda.l	#$c,a5                          ; + 12: the packed data's end
	movea.l	a6,a4
	move.w	#$3c,d0                         ; 60 spaces past the end
lzh_stub_fill_spaces:
	move.b	#$20,(a4)+
	dbra	d0,lzh_stub_fill_spaces
	moveq	#8,d6                           ; 8 bits to go
	move.b	-(a5),d5                        ; the first byte
	move.w	#$4e6,d7                        ; T, as a word index
	movea.l	lzh_stub_d_len(pc),a4           ; d_len
	move.w	#$ff,d3                         ; the colour
lzh_stub_next:
	ror.w	#1,d3                           ; the next colour
lzh_stub_flash:	; from: set_stub_options
	move.w	d3,$ffff8240                    ; palette 0, flash the background (a nop without Flash)
	cmpa.l	(sp),a6                         ; all depacked?
	ble.w	lzh_stub_depack_done
	move.w	$4e4(a1),d0                     ; from the root (R * 2)
lzh_stub_decode_bit:
	dbra	d6,lzh_stub_decode_bit_got      ; a bit left?
	moveq	#7,d6                           ; no: 8 more
	move.b	-(a5),d5                        ; the next byte, from the end down
lzh_stub_decode_bit_got:
	add.b	d5,d5                           ; the top bit out
	bcc.s	lzh_stub_decode_walk            ; 0: the left son
	addq.w	#2,d0                           ; 1: the right son
lzh_stub_decode_walk:
	move.w	0(a1,d0.w),d0                   ; down the tree
	cmp.w	d7,d0                           ; still a node (< T)?
	blt.s	lzh_stub_decode_bit             ; yes: another bit
	move.w	d0,d1                           ; d1 = the leaf
	sub.w	d7,d0                           ; d0 = the character * 2
	move.w	$4e4(a3),d4                     ; the root's frequency $8000?
	bmi.w	lzh_stub_reconst_and_update     ; yes: rebuild the tree first
lzh_stub_update:	; from: lzh_stub_start_huff
	move.w	0(a0,d1.w),d1                   ; from the leaf's parent up
lzh_stub_update_loop:
	lea	0(a3,d1.w),a2                   ; freq[c]
	addq.w	#1,(a2)                         ; one more
	cmpm.w	(a2)+,(a2)+                     ; more than freq[c + 1]?
	bcs.s	lzh_stub_update_swap            ; yes: move it up
	move.w	0(a0,d1.w),d1                   ; its parent
	bne.s	lzh_stub_update_loop            ; up to the root
	lsr.w	#1,d0                           ; the character
	cmp.w	#$100,d0                        ; a length (256 or more)?
	bge.s	lzh_stub_position               ; yes: a position follows
lzh_stub_literal:
	move.b	d0,-(a6)                        ; no: a byte, stored downwards
	bra.s	lzh_stub_next                   ; the next code
lzh_stub_update_swap:
	subq.w	#1,-$4(a2)                      ; freq[c] back
	move.w	-$4(a2),d4                      ; k = it
lzh_stub_update_find:
	cmp.w	(a2)+,d4                        ; l: the last node with the same frequency
	beq.s	lzh_stub_update_find
	subq.l	#4,a2
	addq.w	#1,(a2)                         ; that one is increased instead
	suba.l	a3,a2                           ; l as an offset
	move.w	0(a1,d1.w),d4                   ; i = son[c]
	move.w	a2,0(a0,d4.w)                   ; prnt[i] = l
	cmp.w	d7,d4                           ; a leaf?
	bcc.s	lzh_stub_update_link            ; yes
	move.w	a2,2(a0,d4.w)                   ; no: prnt[i + 1] = l too
lzh_stub_update_link:
	move.w	0(a1,a2.w),d2                   ; j = son[l]
	move.w	d4,0(a1,a2.w)                   ; son[l] = i
	move.w	d1,0(a0,d2.w)                   ; prnt[j] = c
	cmp.w	d7,d2                           ; a leaf?
	bcc.s	lzh_stub_update_next            ; yes
	move.w	d1,2(a0,d2.w)                   ; no: prnt[j + 1] = c too
lzh_stub_update_next:
	move.w	d2,0(a1,d1.w)                   ; son[c] = j
	move.w	0(a0,a2.w),d1                   ; c = prnt[l]
	bne.s	lzh_stub_update_loop            ; up to the root
	lsr.w	#1,d0                           ; the character
	cmp.w	#$100,d0                        ; a byte?
	blt.s	lzh_stub_literal                ; yes
lzh_stub_position:
	move.b	-$1(a5),d1                      ; the position: the next byte's bits
	moveq	#0,d2
	lsr.b	d6,d1                           ; below the bits left in d5
	or.b	d5,d1                           ; d1 = the next 8 bits
	move.b	0(a4,d1.w),d2                   ; d2 = their upper code's length
	sub.w	d2,d6                           ; used
	bpl.s	lzh_stub_position_more          ; all in d5?
	move.b	-(a5),d5                        ; no: the next byte
	move.b	d5,d4
	addq.w	#2,d6                           ; its bits left, less 6
	bmi.s	lzh_stub_position_bits          ; fewer than 6: a third byte
	beq.s	lzh_stub_position_low           ; exactly 6: the low 6 bits
	lsr.b	#1,d4                           ; 7: the low 6 bits are its top bits
	lsl.b	#7,d5                           ; one bit left
	bra.s	lzh_stub_position_low
lzh_stub_position_6:
	move.b	-(a5),d5                        ; the low 6 bits are all in the next byte
	move.b	d5,d4
	lsl.b	#6,d5                           ; two bits left
	moveq	#2,d6
	lsr.b	d6,d4                           ; its top 6 bits
	bra.s	lzh_stub_copy
lzh_stub_position_more:
	beq.s	lzh_stub_position_6             ; d5 used up?
	move.b	(a5),d5                         ; no: the byte d5 came from
	subq.w	#6,d6                           ; the bits needed from the next
lzh_stub_position_bits:
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
lzh_stub_position_low:
	andi.w	#$3f,d4                         ; the low 6 bits
lzh_stub_copy:
	movea.l	lzh_stub_d_code(pc),a0          ; d_code
	move.b	0(a0,d1.w),d2                   ; the upper bits, * 4
	lsl.w	#4,d2                           ; * 64
	or.b	d4,d2                           ; + the low 6 bits
	lea	1(a6,d2.w),a0                   ; from where the text was the position earlier
	subi.w	#$fe,d0                         ; the length: the character - 253, less one
	move.w	d0,d1
lzh_stub_copy_loop:
	move.b	-(a0),d0                        ; a byte from the text
	move.b	d0,-(a6)                        ; copied, downwards
	dbra	d1,lzh_stub_copy_loop
	movea.l	lzh_stub_prnt(pc),a0            ; prnt back
	bra.w	lzh_stub_next                   ; the next code
lzh_stub_d_len_counts:	; from: lzh_stub_make_tables
	dc.w	$0f2f,$2f3f,$2f1f               ; how many upper position values have 3, 4, 5, 6, 7 and 8 bit codes,
                                                ;   less one, from the last
lzh_stub_d_code_counts:	; from: lzh_stub_make_tables
	dc.w	$fff7                           ; the counts behind d_code, a nibble each, less one
	dc.b	'wwws333331'
	dc.w	$1111,$1111,$1111,$1111,$1111,$1110,$0000,$0000
	dc.w	$0000,$0000
lzh_stub_freq:	; from: lzh_stub_start_huff
	dc.w	$0000,$0000                     ; the work area's tables, as offsets until depacking adds the work area:
                                                ;   freq
lzh_stub_freq_nodes:	; from: lzh_stub_start_huff
	dc.w	$0000,$0274                     ; freq + N_CHAR
lzh_stub_prnt:	; from: lzh_stub_start_huff
	dc.w	$0000,$04e8                     ; prnt
lzh_stub_prnt_leaves:	; from: lzh_stub_start_huff
	dc.w	$0000,$09ce                     ; prnt + T
lzh_stub_son:	; from: lzh_stub_start_huff
	dc.w	$0000,$0c42                     ; son
lzh_stub_son_nodes:	; from: lzh_stub_start_huff
	dc.w	$0000,$0eb6                     ; son + N_CHAR
lzh_stub_d_code:	; from: lzh_stub_make_tables
	dc.w	$0000,$112a                     ; d_code: 256 bytes
lzh_stub_d_len:	; from: lzh_stub_make_tables
	dc.w	$0000,$122a                     ; d_len: 256 bytes
lzh_stub_text:	; from: lzh_stub
	dc.b	27,'j',27,'Y  JAM Packer Decrunch V4.0',27,'k',0 ; the title, its column put in
	dc.b	$00

;------------------------------------------------------------------------------
; pack_lzw(source, work, length, &packed): pack with the method the program calls LZW, which is LZSS: a 4 K
; window of the bytes before (at first all spaces), strings of 3 to 18 bytes found with a binary tree, and a
; flag byte (lowest bit first: 1 a literal, 0 a string) before each 8 codes.  A string is 2 bytes: the low 8
; bits of its window position, then its upper 4 bits and the length less 3.  It reads the source from its
; end down and writes the codes downwards from source + length + $800, so that the data can be depacked in
; place.  The header in front is 'LZW!', the unpacked length and the packed length.  The work area ($8504
; bytes) holds the window and the tree.  The packometer's bar is drawn as it goes; holding Alternate aborts.
; *packed = the header; d0 = the packed length + 12, or -1 when aborted.
;------------------------------------------------------------------------------
pack_lzw:	; from: write_program, pack_file, multi_pack_file, pack_chunk, lzh_stub
	link	a6,#0                           ; the frame
	movem.l	d7/a3-a5,-(sp)                  ; keep the registers
	movea.l	8(a6),a5                        ; the source
	movea.l	$c(a6),a4                       ; the work area
	move.l	$10(a6),d7                      ; the length
	movea.l	$14(a6),a3                      ; where the address goes
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	lea	lzw_length(pc),a0               ; the packer's variables
	move.l	d7,(a0)                         ; the length
	move.l	d7,4(a0)                        ; the bytes left to read
	move.l	a5,8(a0)                        ; the source
	clr.l	$c(a0)                          ; no code yet
	move.l	a5,$10(a0)                      ; the output, from the source
	move.l	a4,$14(a0)                      ; the work area
	move.l	a5,$18(a0)                      ; the source again, for the bar
	movea.l	a4,a0                           ; the work area
	move.w	#$2140,d0                       ; $8504 bytes
pack_lzw_clear:
	clr.l	(a0)+                           ; cleared
	dbra	d0,pack_lzw_clear
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp                           ; drop the arguments
	movea.l	d0,a6                           ; the screen
	adda.l	#$7d00,a6                       ; + 32000: its end
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp                           ; drop the arguments
	lea	lzw_rez(pc),a0                  ; the resolution
	move.w	d0,(a0)                         ; kept
	cmp.w	#$2,d0                          ; high?
	beq.s	pack_lzw_high                   ; yes
	move.l	#$a0,d0                         ; 160 bytes a line
	lea	lzw_bar_line_bytes(pc),a0       ; bytes a line
	move.l	d0,(a0)                         ; kept
	mulu.w	bar_offset,d0                   ; * the bar's distance from the bottom
	move.w	bar_column,d1                   ; + its column
	mulu.w	#$4,d1                          ; * 4 bytes
	move.l	#$a0,d2                         ; from the line's end
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a6                           ; where the bar starts
	lea	lzw_bar_next(pc),a0             ; the next line to draw
	move.l	a6,(a0)                         ; kept
	lea	lzw_bar_height(pc),a0           ; the bar's height in lines
	move.w	bar_height,(a0)                 ; kept
	bra.s	pack_lzw_step
pack_lzw_high:
	move.l	#$50,d0                         ; 80 bytes a line
	lea	lzw_bar_line_bytes(pc),a0       ; bytes a line
	move.l	d0,(a0)                         ; kept
	mulu.w	bar_offset,d0                   ; * the bar's distance from the bottom
	move.w	bar_column,d1                   ; + its column
	mulu.w	#$2,d1                          ; * 2 bytes
	move.l	#$50,d2                         ; from the line's end
	sub.l	d1,d2
	add.l	d2,d0
	suba.l	d0,a6                           ; where the bar starts
	lea	lzw_bar_next(pc),a0             ; the next line to draw
	move.l	a6,(a0)                         ; kept
	lea	lzw_bar_height(pc),a0           ; the bar's height in lines
	move.w	bar_height,(a0)                 ; kept
pack_lzw_step:
	lea	lzw_bar_lines(pc),a0            ; no lines drawn
	clr.w	(a0)
	move.l	lzw_left(pc),d0                 ; the length
	divu.w	lzw_bar_height(pc),d0           ; / the height
	lea	lzw_bar_step(pc),a0             ; bytes for each line
	move.w	d0,(a0)                         ; kept
	bsr.w	lzw_encode                      ; pack
	move.l	lzw_packed_length(pc),d0        ; the packed length
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	movea.l	a3,a0                           ; where the address goes
	move.l	lzw_output(pc),(a0)             ; the header
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; lzw_bar: draw the packometer's bar down to the source position (a1) reached, a line for each lzw_bar_step
; bytes read.  With Alternate held the packed length is -1 and it returns from lzw_encode instead.
;------------------------------------------------------------------------------
lzw_bar:	; from: lzw_getc
	movem.l	d0-d2/a0-a2,-(sp)               ; keep the registers
	move.l	a1,d0                           ; the position
	move.l	lzw_source_end(pc),d1           ; from the source's end
	sub.l	d0,d1                           ; the bytes read
	divu.w	lzw_bar_step(pc),d1             ; / bytes a line: the lines due
lzw_bar_loop:
	movea.w	lzw_bar_lines(pc),a0            ; the lines drawn
	cmpa.w	bar_height,a0                   ; all of the bar?
	bge.s	lzw_bar_done                    ; yes: done
	cmp.w	a0,d1                           ; all due drawn?
	bgt.s	lzw_bar_line                    ; no: another
lzw_bar_done:
	movem.l	(sp)+,d0-d2/a0-a2               ; the registers back
	rts
lzw_bar_line:
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	trap	#13                             ; Kbshift
	addq.l	#4,sp                           ; drop the arguments
	btst	#$3,d0                          ; Alternate?
	bne.s	lzw_bar_abort                   ; yes: abort
	lea	lzw_bar_lines(pc),a0            ; one more line
	addq.w	#1,(a0)
	movea.l	lzw_bar_next(pc),a1             ; where it goes
	move.w	#$ffff,(a1)                     ; a line of the bar
	move.w	#$ffff,2(a1)
	move.w	lzw_rez(pc),d0                  ; the resolution
	cmpi.w	#$2,d0                          ; high?
	beq.s	lzw_bar_up                      ; yes: 2 words are 32 pixels
	move.w	#$ffff,4(a1)                    ; 4 words in the colour resolutions
	move.w	#$ffff,6(a1)
lzw_bar_up:
	suba.l	lzw_bar_line_bytes(pc),a1       ; one line up
	lea	lzw_bar_next(pc),a0
	move.l	a1,(a0)                         ; kept
	bra.s	lzw_bar_loop
lzw_bar_abort:
	moveq	#-1,d0                          ; -1
	lea	lzw_packed_length(pc),a0        ; as the packed length
	move.l	d0,(a0)
	movem.l	(sp)+,d0-d2/a0-a2               ; the registers back
	adda.l	#$50,sp                         ; and lzw_getc's and lzw_encode's: back to pack_lzw
	rts
lzw_bar_lines:	; from: pack_lzw
	dc.w	$0000                           ; the lines of the bar drawn
lzw_bar_step:	; from: pack_lzw
	dc.w	$0000                           ; bytes read for each line
lzw_bar_line_bytes:	; from: pack_lzw
	dc.l	$00000000                       ; bytes a screen line: 160 or 80
lzw_bar_height:	; from: pack_lzw
	dc.w	$0000                           ; the bar's height
lzw_bar_next:	; from: pack_lzw
	dc.l	$00000000                       ; where the next line is drawn
lzw_rez:	; from: pack_lzw
	dc.w	$0000                           ; the resolution

;------------------------------------------------------------------------------
; lzw_header: put the header in front of the codes, at an even address.
;------------------------------------------------------------------------------
lzw_header:	; from: lzw_encode
	move.l	lzw_output(pc),d0               ; the codes' start
	btst	#$0,d0                          ; odd?
	beq.s	lzw_header_even                 ; no
	subq.l	#1,d0                           ; yes: a byte more
	lea	lzw_packed_length(pc),a0        ; counted
	addq.l	#1,(a0)
lzw_header_even:
	lea	lzw_packed_length(pc),a0        ; + the header
	addi.l	#$c,(a0)
	movea.l	d0,a0
	move.l	lzw_packed_length(pc),-$4(a0)   ; the packed length
	move.l	lzw_length(pc),-$8(a0)          ; the unpacked length
	move.l	#$4c5a5721,-$c(a0)              ; 'LZW!'
	sub.l	#$c,d0                          ; the header's start
	lea	lzw_output(pc),a0               ; as the output
	move.l	d0,(a0)
lzw_encode_done:	; from: lzw_encode
	movem.l	(sp)+,d0-d7/a0-a6               ; the registers back
	rts

;------------------------------------------------------------------------------
; lzw_encode: LZSS as in Haruhiko Okumura's lzss.c (N = 4096, F = 18, THRESHOLD = 2), in assembly.  The work
; area holds match_position, match_length and last_match_length (+$306), lson (+$30c), rson (+$230e), dad
; (+$4510), text_buf (+$6512) and code_buf (+$7523).  d5 = s, d6 = r, d4 = len, d2 = code_buf_ptr, d7 = mask.
;------------------------------------------------------------------------------
lzw_encode:	; from: pack_lzw
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	move.l	lzw_source(pc),d0               ; the source
	add.l	lzw_left(pc),d0                 ; + the length
	lea	lzw_source_end(pc),a0           ; its end
	move.l	d0,(a0)
	lea	lzw_source(pc),a0               ; read from there down
	move.l	d0,(a0)
	move.l	lzw_output(pc),d0               ; the output
	add.l	lzw_left(pc),d0                 ; + the length
	add.l	#$800,d0                        ; + 2 K
	lea	lzw_output(pc),a0               ; is where the codes end
	move.l	d0,(a0)
	bsr.w	lzw_init_tree                   ; InitTree
	movea.l	lzw_work(pc),a6                 ; the work area
	movea.l	a6,a2
	movea.l	a6,a3
	movea.l	a6,a4
	movea.l	a6,a5
	adda.l	#$30c,a2                        ; a2 = lson
	adda.l	#$230e,a3                       ; a3 = rson
	adda.l	#$6512,a5                       ; a5 = text_buf
	adda.l	#$7523,a4                       ; a4 = code_buf
	adda.l	#$6512,a6                       ; a6 = text_buf
	move.l	lzw_left(pc),d4
	clr.b	(a4)                            ; code_buf[0] = 0
	moveq	#1,d2                           ; code_buf_ptr = 1
	moveq	#1,d7                           ; mask = 1
	moveq	#0,d5                           ; s = 0
	move.w	#$fee,d6                        ; r = N - F
	movea.l	a6,a0                           ; text_buf
	move.w	#$fed,d7                        ; $fee
lzw_encode_spaces:
	move.b	#$20,(a0)+                      ; spaces
	dbra	d7,lzw_encode_spaces
	moveq	#0,d4                           ; len = 0
	lea	$fee(a6),a0                     ; text_buf[r]
lzw_encode_first:
	bsr.w	lzw_getc                        ; getc
	beq.s	lzw_encode_got                  ; none left?
	move.b	d0,(a0)+                        ; text_buf[r + len] = c
	addq.w	#1,d4                           ; len++
	cmp.w	#$12,d4                         ; up to F
	blt.s	lzw_encode_first
lzw_encode_got:
	tst.w	d4                              ; nothing?
	beq.w	lzw_encode_done                 ; yes: done
	move.w	#$fed,d6                        ; r - 1
	move.w	#$11,d7                         ; to r - F
lzw_encode_insert:
	bsr.w	lzw_insert_node                 ; InsertNode
	subq.w	#1,d6
	dbra	d7,lzw_encode_insert
	move.w	#$fee,d6                        ; r
	bsr.w	lzw_insert_node                 ; InsertNode(r)
	moveq	#1,d7
lzw_encode_loop:
	movea.l	lzw_work(pc),a0                 ; the work area
	adda.l	#$308,a0                        ; match_length
	cmp.w	(a0),d4                         ; more than len?
	bgt.s	lzw_encode_code                 ; no
	move.w	d4,(a0)                         ; yes: len
lzw_encode_code:
	cmpi.w	#$2,(a0)                        ; more than THRESHOLD?
	bgt.s	lzw_encode_string               ; yes: a string
	move.w	#$1,(a0)                        ; no: match_length = 1
	or.b	d7,(a4)                         ; the flag: a literal
	move.b	0(a6,d6.w),0(a4,d2.w)           ; code_buf[code_buf_ptr++] = text_buf[r]
	addq.w	#1,d2
	bra.s	lzw_encode_mask
lzw_encode_string:
	movea.l	lzw_work(pc),a0                 ; the work area
	adda.l	#$306,a0                        ; match_position
	move.w	(a0),d0
	move.b	d0,0(a4,d2.w)                   ; its low 8 bits
	lsr.w	#4,d0                           ; its upper 4
	and.w	#$f0,d0
	move.w	2(a0),d1                        ; match_length
	sub.w	#$3,d1                          ; - 3
	or.w	d1,d0
	move.b	d0,1(a4,d2.w)                   ; the second byte
	addq.w	#2,d2                           ; code_buf_ptr += 2
lzw_encode_mask:
	lsl.b	#1,d7                           ; mask <<= 1
	bne.s	lzw_encode_last                 ; 8 codes yet?
	moveq	#0,d1                           ; yes: code_buf written
	move.w	d2,d0
	movea.l	a4,a0
	subq.w	#1,d0                           ; the count less one
	bsr.w	lzw_put_block                   ; written
	clr.b	(a4)                            ; code_buf[0] = 0
	moveq	#1,d2                           ; code_buf_ptr = 1
	moveq	#1,d7                           ; mask = 1
lzw_encode_last:
	movea.l	lzw_work(pc),a0                 ; the work area
	adda.l	#$30a,a0                        ; last_match_length
	movea.l	lzw_work(pc),a1
	adda.l	#$308,a1
	move.w	(a1),(a0)                       ; = match_length
	moveq	#1,d1                           ; i = 1
lzw_encode_read:
	cmp.w	(a0),d1                         ; i <= last_match_length?
	bgt.s	lzw_encode_rest                 ; no
	bsr.w	lzw_getc                        ; getc
	beq.s	lzw_encode_eof                  ; none left
	addq.w	#1,d1                           ; i++
	bsr.w	lzw_delete_node                 ; DeleteNode(s)
	cmp.w	#$11,d5                         ; s < F - 1?
	bge.s	lzw_encode_store                ; no
	lea	$1000(a6),a1                    ; yes: text_buf[s + N] = c too
	move.b	d0,0(a1,d5.w)
lzw_encode_store:
	move.b	d0,0(a6,d5.w)                   ; text_buf[s] = c
	addq.w	#1,d5                           ; s = (s + 1) & (N - 1)
	and.w	#$fff,d5
	addq.w	#1,d6                           ; r = (r + 1) & (N - 1)
	and.w	#$fff,d6
	bsr.w	lzw_insert_node                 ; InsertNode(r)
	bra.s	lzw_encode_read
lzw_encode_rest:
	addq.w	#1,d1                           ; i++
	movea.l	lzw_work(pc),a0                 ; the work area
	adda.l	#$30a,a0                        ; last_match_length
	cmp.w	(a0),d1                         ; i <= it?
	bgt.s	lzw_encode_next                 ; no
	bsr.w	lzw_delete_node                 ; DeleteNode(s)
	addq.w	#1,d5                           ; s = (s + 1) & (N - 1)
	and.w	#$fff,d5
	addq.w	#1,d6                           ; r = (r + 1) & (N - 1)
	and.w	#$fff,d6
	move.w	d4,d0                           ; len--
	subq.w	#1,d4
	tst.w	d0                              ; it was 0?
	beq.s	lzw_encode_rest                 ; yes
	bsr.w	lzw_insert_node                 ; no: InsertNode(r)
	bra.s	lzw_encode_rest
lzw_encode_next:
	cmpi.w	#$1,d4                          ; len > 0?
	bge.w	lzw_encode_loop                 ; yes: on
	moveq	#0,d1                           ; the last codes
lzw_encode_tail:
	move.b	0(a4,d1.w),d0                   ; code_buf[i]
	bsr.w	lzw_putc                        ; putc
	addq.w	#1,d1
	cmp.w	d2,d1                           ; up to code_buf_ptr
	blt.s	lzw_encode_tail
	bra.w	lzw_header                      ; then the header
lzw_encode_eof:
	subq.w	#1,d1                           ; i back
	bra.s	lzw_encode_rest

;------------------------------------------------------------------------------
; lzw_init_tree: InitTree: rson[N + 1..N + 256] and dad[0..N - 1] = NIL ($2000, as offsets).
;------------------------------------------------------------------------------
lzw_init_tree:	; from: lzw_encode
	move.w	#$1001,d0                       ; N + 1
	movea.l	lzw_work(pc),a0                 ; the work area
	adda.l	#$230e,a0                       ; rson
	bra.s	lzw_init_roots_loop
lzw_init_roots:
	move.w	d0,d1
	add.w	d1,d1                           ; as an offset
	move.w	#$2000,0(a0,d1.w)               ; NIL
	addq.w	#1,d0
lzw_init_roots_loop:
	cmp.w	#$1100,d0                       ; up to N + 256
	ble.s	lzw_init_roots
	clr.w	d0                              ; 0
	bra.s	lzw_init_dad_loop
lzw_init_dad:
	move.w	d0,d1
	add.w	d1,d1                           ; as an offset
	lea	$2202(a0),a1                    ; dad
	move.w	#$2000,0(a1,d1.w)               ; NIL
	addq.w	#1,d0
lzw_init_dad_loop:
	cmp.w	#$1000,d0                       ; up to N
	blt.s	lzw_init_dad
	rts

;------------------------------------------------------------------------------
; lzw_delete_node: DeleteNode(p = d5): take p out of the tree.
;------------------------------------------------------------------------------
lzw_delete_node:	; from: lzw_encode
	movem.l	d0-d7/a0-a1/a4-a6,-(sp)         ; keep the registers
	move.w	#$2000,d7                       ; NIL
	movea.l	lzw_work(pc),a0                 ; the work area
	adda.l	#$4510,a0                       ; dad
	add.w	d5,d5                           ; p, as an offset
	cmp.w	0(a0,d5.w),d7                   ; dad[p] = NIL?
	beq.s	lzw_delete_done                 ; yes: not in the tree
	cmp.w	0(a3,d5.w),d7                   ; rson[p] = NIL?
	beq.w	lzw_delete_no_right             ; yes: q = lson[p]
	cmp.w	0(a2,d5.w),d7                   ; lson[p] = NIL?
	beq.s	lzw_delete_no_left              ; yes: q = rson[p]
lzw_delete_both:
	lea	0(a2,d5.w),a4                   ; &lson[p]
	lea	0(a3,d5.w),a5                   ; &rson[p]
	move.w	(a4),d1                         ; q = lson[p]
	move.w	d1,d2
	cmp.w	0(a3,d2.w),d7                   ; rson[q] = NIL?
	beq.s	lzw_delete_right                ; yes
lzw_delete_rightmost:
	move.w	0(a3,d2.w),d2                   ; q = rson[q]
	cmp.w	d7,d2                           ; until rson[q] = NIL
	beq.s	lzw_delete_found
	move.w	d2,d1
	bra.s	lzw_delete_rightmost
lzw_delete_found:
	move.w	d1,d2
	move.w	0(a0,d2.w),d3                   ; dad[q]
	lea	0(a2,d2.w),a1
	move.w	(a1),0(a3,d3.w)                 ; rson[dad[q]] = lson[q]
	move.w	(a1),d3
	move.w	0(a0,d2.w),0(a0,d3.w)           ; dad[lson[q]] = dad[q]
	move.w	(a4),d3                         ; lson[p]
	move.w	d3,(a1)                         ; lson[q] = lson[p]
	move.w	d1,0(a0,d3.w)                   ; dad[lson[p]] = q
lzw_delete_right:
	move.w	(a5),d3                         ; rson[p]
	move.w	d3,0(a3,d2.w)                   ; rson[q] = rson[p]
	move.w	d1,0(a0,d3.w)                   ; dad[rson[p]] = q
lzw_delete_link:
	move.w	0(a0,d5.w),0(a0,d1.w)           ; dad[q] = dad[p]
	lea	0(a0,d5.w),a5                   ; &dad[p]
	move.w	(a5),d3
	cmp.w	0(a3,d3.w),d5                   ; rson[dad[p]] = p?
	bne.s	lzw_delete_left                 ; no
	move.w	d1,0(a3,d3.w)                   ; yes: rson[dad[p]] = q
	move.w	d7,(a5)                         ; dad[p] = NIL
	movem.l	(sp)+,d0-d7/a0-a1/a4-a6         ; the registers back
	rts
lzw_delete_left:
	move.w	d1,0(a2,d3.w)                   ; lson[dad[p]] = q
	move.w	d7,(a5)                         ; dad[p] = NIL
lzw_delete_done:
	movem.l	(sp)+,d0-d7/a0-a1/a4-a6         ; the registers back
	rts
lzw_delete_no_left:
	move.w	0(a3,d5.w),d1                   ; q = rson[p]
	bra.s	lzw_delete_link
lzw_delete_no_right:
	move.w	0(a2,d5.w),d1                   ; q = lson[p]
	bra.s	lzw_delete_link

;------------------------------------------------------------------------------
; lzw_insert_node: InsertNode(r = d6): put the string at r into the tree; match_position and match_length =
; the longest match.
;------------------------------------------------------------------------------
lzw_insert_node:	; from: lzw_encode
	movem.l	d0-d7/a0-a1/a4/a6,-(sp)         ; keep the registers
	moveq	#1,d1                           ; cmp = 1
	lea	0(a5,d6.w),a1                   ; key = &text_buf[r]
	add.w	d6,d6                           ; r, as an offset
	moveq	#0,d2                           ; p = N + 1 + key[0]
	move.b	(a1),d2
	add.w	#$1001,d2
	add.w	d2,d2                           ; as an offset
	move.w	#$2000,d7                       ; NIL
	move.w	d7,0(a2,d6.w)                   ; lson[r] = NIL
	move.w	d7,0(a3,d6.w)                   ; rson[r] = NIL
	movea.l	lzw_work(pc),a0                 ; the work area
	adda.l	#$308,a0                        ; match_length
	clr.w	(a0)                            ; = 0
	movea.l	lzw_work(pc),a4                 ; the work area
	adda.l	#$4510,a4                       ; dad
lzw_insert_loop:
	tst.w	d1                              ; cmp >= 0?
	blt.s	lzw_insert_left                 ; no: left
	lea	0(a3,d2.w),a6                   ; &rson[p]
	cmp.w	(a6),d7                         ; NIL?
	bne.s	lzw_insert_compare              ; no: on
	move.w	d6,(a6)                         ; yes: rson[p] = r
	move.w	d2,0(a4,d6.w)                   ; dad[r] = p
	bra.w	lzw_insert_done                 ; done
lzw_insert_left_new:
	move.w	d6,(a6)                         ; lson[p] = r
	move.w	d2,0(a4,d6.w)                   ; dad[r] = p
	bra.w	lzw_insert_done                 ; done
lzw_insert_left:
	lea	0(a2,d2.w),a6                   ; &lson[p]
	cmp.w	(a6),d7                         ; NIL?
	beq.s	lzw_insert_left_new             ; yes: insert here
lzw_insert_compare:
	move.w	(a6),d2                         ; p = the son
	moveq	#0,d1
	moveq	#16,d5                          ; 17 bytes
	lea	1(a1),a0                        ; key + 1
	lsr.w	#1,d2
	lea	1(a5,d2.w),a6                   ; text_buf + p + 1
	add.w	d2,d2
lzw_insert_compare_loop:
	cmpm.b	(a0)+,(a6)+                     ; the same?
	dbne	d5,lzw_insert_compare_loop      ; up to F - 1
	moveq	#17,d3                          ; i = the bytes the same
	sub.w	d5,d3
	moveq	#0,d5
	move.b	-$1(a0),d1                      ; key[i]
	move.b	-$1(a6),d5                      ; text_buf[p + i]
	sub.w	d5,d1                           ; cmp
	movea.l	lzw_work(pc),a6                 ; the work area
	adda.l	#$308,a6                        ; match_length
	cmp.w	(a6),d3                         ; i > it?
	ble.s	lzw_insert_loop                 ; no: on
	move.w	d2,d4                           ; yes: match_position = p
	lsr.w	#1,d4
	movea.l	lzw_work(pc),a0
	adda.l	#$306,a0
	move.w	d4,(a0)
	move.w	d3,(a6)                         ; match_length = i
	cmp.w	#$12,d3                         ; F?
	blt.s	lzw_insert_loop                 ; no: on
	move.w	0(a4,d2.w),0(a4,d6.w)           ; yes: replace p by r: dad[r] = dad[p]
	move.w	0(a2,d2.w),0(a2,d6.w)           ; lson[r] = lson[p]
	move.w	0(a3,d2.w),0(a3,d6.w)           ; rson[r] = rson[p]
	move.w	0(a2,d2.w),d4                   ; dad[lson[p]] = r
	move.w	d6,0(a4,d4.w)
	move.w	0(a3,d2.w),d4                   ; dad[rson[p]] = r
	move.w	d6,0(a4,d4.w)
	lea	0(a4,d2.w),a6                   ; &dad[p]
	move.w	(a6),d4
	cmp.w	0(a3,d4.w),d2                   ; rson[dad[p]] = p?
	beq.s	lzw_insert_replace_right        ; yes
	move.w	(a6),d3                         ; no: lson[dad[p]] = r
	move.w	d6,0(a2,d3.w)
	move.w	d7,(a6)                         ; dad[p] = NIL
lzw_insert_done:
	movem.l	(sp)+,d0-d7/a0-a1/a4/a6         ; the registers back
	rts
lzw_insert_replace_right:
	move.w	d6,0(a3,d4.w)                   ; rson[dad[p]] = r
	move.w	d7,(a6)                         ; dad[p] = NIL
	movem.l	(sp)+,d0-d7/a0-a1/a4/a6         ; the registers back
	rts

;------------------------------------------------------------------------------
; lzw_putc: put a code byte (d0), downwards.
;------------------------------------------------------------------------------
lzw_putc:	; from: lzw_encode
	movem.l	a0-a1,-(sp)                     ; keep the registers
	lea	lzw_packed_length(pc),a0        ; the packed length
	addq.l	#1,(a0)                         ; one more
	movea.l	lzw_output(pc),a1               ; the output
	move.b	d0,-(a1)                        ; the byte
	move.l	a1,4(a0)                        ; moved down
	movem.l	(sp)+,a0-a1                     ; the registers back
	rts

;------------------------------------------------------------------------------
; lzw_put_block: put the d0 + 1 bytes at a0, downwards (the first ends up highest).
;------------------------------------------------------------------------------
lzw_put_block:	; from: lzw_encode
	movem.l	d0/d2/a0-a2,-(sp)               ; keep the registers
	move.w	d0,d2                           ; the count less one
	lea	lzw_packed_length(pc),a2        ; the packed length
	add.l	d0,(a2)                         ; + the count
	addq.l	#1,(a2)
	movea.l	lzw_output(pc),a1               ; the output
lzw_put_block_loop:
	move.b	(a0)+,-(a1)                     ; each byte
	dbra	d2,lzw_put_block_loop
	move.l	a1,4(a2)                        ; moved down
	movem.l	(sp)+,d0/d2/a0-a2               ; the registers back
	rts

;------------------------------------------------------------------------------
; lzw_getc: d0 = the next source byte, from the end down, with the bar drawn; Z set when there are none.
;------------------------------------------------------------------------------
lzw_getc:	; from: lzw_encode
	movem.l	d1/a0-a1,-(sp)                  ; keep the registers
	lea	lzw_left(pc),a0                 ; the bytes left
	tst.l	(a0)                            ; none?
	beq.s	lzw_getc_done                   ; yes
	subq.l	#1,(a0)                         ; one fewer
	movea.l	4(a0),a1                        ; where they are
	bsr.w	lzw_bar                         ; the bar
	moveq	#0,d0
	move.b	-(a1),d0                        ; the byte
	move.l	a1,4(a0)                        ; moved down
lzw_getc_done:
	movem.l	(sp)+,d1/a0-a1                  ; the registers back
	rts
lzw_length:	; from: pack_lzw, lzw_header
	dc.l	$00000000                       ; the unpacked length
lzw_left:	; from: pack_lzw, lzw_encode
	dc.l	$00000000                       ; the bytes left to read
lzw_source:	; from: lzw_encode
	dc.l	$00000000                       ; the source, then where it is read from
lzw_packed_length:	; from: pack_lzw, lzw_bar, lzw_header, lzw_putc, lzw_put_block
	dc.l	$00000000                       ; the packed length
lzw_output:	; from: pack_lzw, lzw_header, lzw_encode, lzw_putc, lzw_put_block
	dc.l	$00000000                       ; where the next code byte goes, then the header
lzw_work:	; from: lzw_encode, lzw_init_tree, lzw_delete_node, lzw_insert_node
	dc.l	$00000000                       ; the work area
lzw_source_end:	; from: lzw_bar, lzw_encode
	dc.l	$00000000                       ; the source's end, for the bar
	movem.l	(sp)+,d7/a3-a5                  ; not reached: pack_lzw's end as compiled
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; depack_lzw(packed, destination): depack 'LZW!' data in supervisor mode, keeping the background colour.
; d0 = the unpacked length.
;------------------------------------------------------------------------------
depack_lzw:	; from: unpack_file, depack_chunk
	link	a6,#0                           ; the frame
	movem.l	d6-d7,-(sp)                     ; keep the registers
	move.l	8(a6),d7                        ; the packed data
	move.l	$c(a6),d6                       ; the destination
	move.l	a6,-(sp)                        ; keep a6
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; the old stack, kept
	move.w	$ffff8240.w,-(sp)               ; palette 0, palette 0, kept
	movea.l	d7,a0                           ; a0 = the packed data
	movea.l	d6,a1                           ; a1 = the destination
	move.l	4(a0),-(sp)                     ; its unpacked length, kept
	bsr.s	lzw_depack                      ; depack
	move.l	(sp)+,d7                        ; d7 = the unpacked length
	move.w	(sp)+,$ffff8240.w               ; palette 0, palette 0, the colour back
	move.w	#$20,-(sp)                      ; Super(old stack)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d7,d0                           ; returned
	movea.l	(sp)+,a6                        ; a6 back
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; lzw_depack: depack 'LZW!' data (a0 = it) to a1, from the end of the packed data down, the
; output written from its end down; positions before the start are spaces.  The background
; colour follows the positions as it goes.
;------------------------------------------------------------------------------
lzw_depack:	; from: depack_lzw
	movea.l	a0,a4                           ; a4 = the packed data
	movea.l	a1,a6                           ; a6 = the destination
	adda.l	8(a0),a4                        ; + the packed length: its end
	adda.l	4(a0),a6                        ; + the unpacked length: its end
	movea.l	a6,a5                           ; a5 = the output's end
	move.l	4(a0),d4                        ; d4 = the bytes to go
	move.b	#$20,d3                         ; a space, for what is past the end
	move.w	#$fed,d5                        ; r, less one
	movea.l	a6,a3
	moveq	#0,d7                           ; no flag bits yet
lzw_depack_loop:
	dbra	d7,lzw_depack_flag              ; a flag bit left?
	move.b	-(a4),d6                        ; no: the next flag byte
	moveq	#7,d7                           ; 8 bits
lzw_depack_flag:
	lsr.b	#1,d6                           ; the next flag
	bcc.s	lzw_depack_string               ; 0: a string
	move.b	-(a4),-(a6)                     ; 1: a literal
	addq.w	#1,d5                           ; r++
	subq.l	#1,d4                           ; one fewer to go
	bgt.s	lzw_depack_loop                 ; more?
	bra.s	lzw_depack_done                 ; no: done
lzw_depack_string:
	move.b	-$2(a4),d0                      ; the second byte
	lsl.w	#4,d0                           ; its upper 4 bits as bits 8-11
	move.b	-(a4),d0                        ; the low 8 bits: the window position
lzw_depack_flash:
	move.w	d0,$ffff8240.w                  ; palette 0, the background
	sub.w	d5,d0                           ; - r
	neg.w	d0
	and.w	#$fff,d0                        ; how far back it is
	lea	1(a6,d0.w),a0                   ; where it is in the output
	moveq	#15,d1
	and.b	-(a4),d1                        ; the length less 3
	addq.w	#2,d1                           ; less one more, for dbra
	moveq	#1,d0
	add.w	d1,d0                           ; d0 = the length
	cmpa.l	a5,a0                           ; past the output's end?
	bgt.s	lzw_depack_spaces               ; yes: spaces first
lzw_depack_copy:
	move.b	-(a0),-(a6)                     ; copied
	dbra	d1,lzw_depack_copy
lzw_depack_next:
	add.l	d0,d5                           ; r += the length
	sub.l	d0,d4                           ; fewer to go
	bgt.s	lzw_depack_loop                 ; more?
lzw_depack_done:
	rts
lzw_depack_spaces:
	cmpa.l	a5,a0                           ; still past the end?
	ble.s	lzw_depack_copy                 ; no: copy the rest
	move.b	d3,-(a6)                        ; a space
	subq.l	#1,a0
	dbra	d1,lzw_depack_spaces
	bra.s	lzw_depack_next
	movem.l	(sp)+,d6-d7                     ; not reached: depack_lzw's end as compiled
	unlk	a6                              ; the frame back
	rts

;------------------------------------------------------------------------------
; The LZW program stub ("JAM Packer Decrunch V4.0"), put in front of a program packed with LZW.
; Each stub keeps the registers, clears the top of the screen and prints its title (unless Heading is off),
; depacks the program $100 bytes past its own end flashing the background (unless Flash is off), relocates
; it to run where the stub starts, sets the basepage and runs a mover from the screen that copies it down,
; clears its BSS (at least $400 bytes, $1a00 for LZH), puts the registers back and jumps to it.  The packed
; data follows the stub.
;------------------------------------------------------------------------------
lzw_stub:	; from: write_program, pack_file, multi_pack_file
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
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
	beq.s	lzw_stub_clear                  ; yes
	move.w	#$167,d1                        ; 360 longs otherwise
lzw_stub_clear:	; from: set_stub_options
	clr.l	(a2)+                           ; clear the top of the screen (a nop without Heading)
	dbra	d1,lzw_stub_clear
	lea	lzw_stub_text(pc),a1            ; the title
	move.b	#$3c,5(a1)                      ; column 28
	cmp.b	#$0,d0                          ; low resolution?
	bne.s	lzw_stub_title                  ; no
	move.b	#$28,5(a1)                      ; yes: column 8
lzw_stub_title:
	pea	lzw_stub_text(pc)               ; the title
	move.w	#$9,-(sp)
lzw_stub_print:	; from: set_stub_options
	trap	#1                              ; Cconws, Cconws (a nop without Heading)
	addq.l	#6,sp                           ; drop the arguments
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	move.l	d0,-(sp)                        ; kept
	move.w	$ffff8240.w,-(sp)               ; palette 0
	lea	lzw_stub+$204(pc),a0            ; the packed data after the stub
	movea.l	a0,a1
	adda.l	#$100,a1
	move.l	4(a0),-(sp)                     ; argument 1
	bsr.w	lzw_stub_depack
	movea.l	(sp)+,a6
	move.w	(sp)+,$ffff8240.w               ; palette 0
	move.w	#$20,-(sp)                      ; Super(old stack)
	trap	#1                              ; Super
	addq.l	#6,sp                           ; drop the arguments
	lea	lzw_stub+$204(pc),a3            ; the depacked program: $100 bytes on
	adda.l	#$100,a3
	movea.l	a3,a1
	movea.l	2(a3),a0                        ; its header's text length
	adda.l	6(a3),a0                        ; + data length
	adda.l	$e(a3),a0                       ; + symbol length
	adda.l	#$1c,a0                         ; + the header
	adda.l	a3,a0                           ; a0 = its relocation table
	lea	lzw_stub(pc),a5                 ; where it will run: the stub's text
	move.l	a5,d0
	adda.l	#$1c,a1                         ; its text
	tst.l	(a0)                            ; any relocation?
	beq.s	lzw_stub_relocated              ; no
	adda.l	(a0)+,a1                        ; the first address
lzw_stub_relocate:
	add.l	d0,(a1)                         ; relocate a long
lzw_stub_relocate_next:
	clr.l	d1
	move.b	(a0)+,d1                        ; the next step
	tst.w	d1                              ; the end?
	beq.s	lzw_stub_relocated              ; yes
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	lzw_stub_relocate_step          ; no
	adda.l	#$fe,a1                         ; yes
	bra.s	lzw_stub_relocate_next
lzw_stub_relocate_step:
	adda.l	d1,a1                           ; on to the next long
	bra.s	lzw_stub_relocate               ; relocate it
lzw_stub_relocated:
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
	moveq	#95,d2
	lea	lzw_stub_mover(pc),a1           ; the mover
lzw_stub_copy_mover:
	move.b	(a1)+,(a2)+                     ; copied
	dbra	d2,lzw_stub_copy_mover
	movea.l	a3,a1                           ; the depacked text
	adda.l	#$1c,a1
	lea	lzw_stub(pc),a0                 ; where it runs
	movea.l	a0,a2
	jmp	(a5)                            ; run the mover
lzw_stub_mover:
	lea	lzw_stub_start+2(pc),a6         ; where the last jump goes
	move.l	a0,(a6)                         ; the start of the program, put in it
lzw_stub_mover_copy:
	move.l	(a1)+,(a2)+                     ; copy the program down, 16 bytes at a time
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	cmpa.l	d1,a2                           ; to the BSS?
	ble.s	lzw_stub_mover_copy
	lea	-$100(a0),a1                    ; the basepage
	movea.l	$18(a1),a3                      ; its BSS
	move.l	$1c(a1),d1                      ; its length
	cmp.l	#$400,d1                        ; at least $400 bytes
	bgt.s	lzw_stub_clear_size             ; yes
	move.l	#$400,d1                        ; no: $400
lzw_stub_clear_size:
	lsr.l	#4,d1                           ; in 16 bytes
lzw_stub_clear_bss:
	clr.l	(a3)+                           ; cleared
	clr.l	(a3)+
	clr.l	(a3)+
	clr.l	(a3)+
	subq.l	#1,d1                           ; less one
	bge.s	lzw_stub_clear_bss
	movem.l	(sp)+,d1-d7/a0-a6               ; the registers back
	clr.l	d0                              ; d0 = 0
lzw_stub_start:
	jmp	$0                              ; start the program (the mover puts its address in)

;------------------------------------------------------------------------------
; The stub's copy of lzw_depack.
;------------------------------------------------------------------------------
lzw_stub_depack:	; from: lzw_stub
	movea.l	a0,a4                           ; a4 = the packed data
	movea.l	a1,a6                           ; a6 = the destination
	adda.l	8(a0),a4                        ; + the packed length: its end
	adda.l	4(a0),a6                        ; + the unpacked length: its end
	movea.l	a6,a5                           ; a5 = the output's end
	move.l	4(a0),d4                        ; d4 = the bytes to go
	move.b	#$20,d3                         ; a space, for what is past the end
	move.w	#$fed,d5                        ; r, less one
	movea.l	a6,a3
	moveq	#0,d7                           ; no flag bits yet
lzw_stub_depack_loop:
	dbra	d7,lzw_stub_depack_flag         ; a flag bit left?
	move.b	-(a4),d6                        ; no: the next flag byte
	moveq	#7,d7                           ; 8 bits
lzw_stub_depack_flag:
	lsr.b	#1,d6                           ; the next flag
	bcc.s	lzw_stub_depack_string          ; 0: a string
	move.b	-(a4),-(a6)                     ; 1: a literal
	addq.w	#1,d5                           ; r++
	subq.l	#1,d4                           ; one fewer to go
	bgt.s	lzw_stub_depack_loop            ; more?
	bra.s	lzw_stub_depack_done            ; no: done
lzw_stub_depack_string:
	move.b	-$2(a4),d0                      ; the second byte
	lsl.w	#4,d0                           ; its upper 4 bits as bits 8-11
	move.b	-(a4),d0                        ; the low 8 bits: the window position
lzw_stub_flash:	; from: set_stub_options
	move.w	d0,$ffff8240.w                  ; palette 0, the background (a nop without Flash)
	sub.w	d5,d0                           ; - r
	neg.w	d0
	and.w	#$fff,d0                        ; how far back it is
	lea	1(a6,d0.w),a0                   ; where it is in the output
	moveq	#15,d1
	and.b	-(a4),d1                        ; the length less 3
	addq.w	#2,d1                           ; less one more, for dbra
	moveq	#1,d0
	add.w	d1,d0                           ; d0 = the length
	cmpa.l	a5,a0                           ; past the output's end?
	bgt.s	lzw_stub_depack_spaces          ; yes: spaces first
lzw_stub_depack_copy:
	move.b	-(a0),-(a6)                     ; copied
	dbra	d1,lzw_stub_depack_copy
lzw_stub_depack_next:
	add.l	d0,d5                           ; r += the length
	sub.l	d0,d4                           ; fewer to go
	bgt.s	lzw_stub_depack_loop            ; more?
lzw_stub_depack_done:
	rts
lzw_stub_depack_spaces:
	cmpa.l	a5,a0                           ; still past the end?
	ble.s	lzw_stub_depack_copy            ; no: copy the rest
	move.b	d3,-(a6)                        ; a space
	subq.l	#1,a0
	dbra	d1,lzw_stub_depack_spaces
	bra.s	lzw_stub_depack_next
lzw_stub_text:	; from: lzw_stub
	dc.b	27,'j',27,'Y  JAM Packer Decrunch V4.0',27,'k',0 ; the title, its column put in
	dc.b	$00

;------------------------------------------------------------------------------
; The C library.  The AES bindings put their arguments in the AES arrays and call aes with the opcode;
; the trap bindings keep a1/a2 and the return address on a small stack of their own.
;
; appl_exit().
;------------------------------------------------------------------------------
appl_exit:	; from: close_gem, write_program, pack_file, multi_pack_file, lzw_stub
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
evnt_button:	; from: main, pack_power
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
form_alert:	; from: main, pack_one_file, fatal_alert, open_workstation, multi_pack, pack_file, 3 more
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
form_do:	; from: main, pack_power, about_box, pack_file
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
graf_mouse:	; from: pack_one_file, init_gem, copy_screen, clear_title, show_title, multi_pack, 5 more
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
objc_change:	; from: pack_power, deselect, check_object, pack_file
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
objc_draw:	; from: main, pack_power, pack_power_step, open_box, about_box, pack_file, 5 more
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
bios:	; from: read_boot_sector
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

xbios:	; from: pack_power, pack_power_step, init_gem, open_workstation, fdc_sectors, format_disk, 1 more
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

gemdos:	; from: pack_one_file, init_gem, multi_pack, unpack_file, write_program, pack_file, 16 more
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
exit:	; from: start, main, fatal_alert, open_workstation
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
fflush:	; from: fclose
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
malloc_word:
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
fd_mode:	; from: lseek, write
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
	unlk	a6                              ; , 
	rts                                     ; , 

;------------------------------------------------------------------------------
; strrchr(string, c): the last c in the string, or its end for c = 0; 0 when not found.
;------------------------------------------------------------------------------
strrchr:	; from: choose_file, set_extension
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
strcat:	; from: choose_file, multi_pack, show_pack_sizes, show_crunching, disk_unpack, disk_pack, 1 more
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
strcmp:	; from: open
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
strcpy:	; from: main, pack_power, choose_file, multi_pack, note_file, show_crunching, 2 more
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
strlen:	; from: multi_pack, is_program_name, disk_unpack, disk_pack
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
	dc.w	$0000

	section	data

;------------------------------------------------------------------------------
; The data section: settings, texts and alerts, the two built-in resources, the packer's tables and the C
; library's variables.
;------------------------------------------------------------------------------
app_flag:	; from: start
	dc.w	$0001                           ; 1 for a program, 0 for a desk accessory
v2_window:	; from: main, pack_power, pack_power_step, pack_file, multi_pack_file, pack_chunk
	dc.l	$00001120                       ; how far ahead the V2 packer looks for strings
algorithm:	; from: main, pack_power, write_program, pack_file, multi_pack_file, pack_chunk
	dc.w	$0009                           ; the method: the object number of its button (9 LZH, 10 V2, 12 ICE, 13
                                                ;   LZW)
pack_file_name:	; from: main, pack_one_file, unpack_file, pack_file
	dc.b	'*.*',0                         ; the name in the file selector when packing one file
	dcb.b	16,0
text_supply_save_path:	; from: unpack_file, pack_file
	dc.b	'Supply the SAVE path and file name',0
	dc.b	$00
text_choose_pack_file:	; from: pack_one_file
	dc.b	'Choose a file to PACK',0
text_supply_source_path:	; from: main
	dc.b	'Supply the SOURCE path and file template',0
	dc.b	$00
text_choose_unpack_file:	; from: main
	dc.b	'Choose a file to UNPACK',0
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
	dc.b	'*.*',0                         ; the name in the file selector for the multi packer
	dcb.b	16,0
source_path:	; from: main, pack_one_file
	dc.b	'\*.*',0                        ; the source path
	dcb.b	123,0
text_largest_v2:	; from: main
	dc.b	'4384',0
	dc.b	$00
text_largest_ice:	; from: main
	dc.b	'5504',0
	dc.b	$00
text_data:	; from: main
	dc.b	'Data',0
	dc.b	$00
text_program:	; from: main
	dc.b	'Program',0
alert_not_packed:	; from: main
	dc.b	'[0][|File not packed with  |   LZH, V2 or ICE | ][Really?]',0
	dc.b	$00
alert_no_memory_to_unpack:	; from: main
	dc.b	'[0][ |  Insufficient Memory To   |      Unpack File | ][Upgrade '
	dc.b	'now!]',0
text_performing_multi_pack:	; from: main
	dc.b	'Performing Multi Pack...',0
	dc.b	$00
text_all_files_source:	; from: main
	dc.b	'\*.*',0                        ; "\*.*" for the source path again
	dc.b	$00
text_all_files_destination:	; from: main
	dc.b	'\*.*',0                        ; "\*.*" for the destination path again
	dc.b	$00
main_cases:	; from: main
	dc.w	menu_about-main
	dc.w	menu_about2-main
	dc.w	menu_none-main
	dc.w	menu_none-main
	dc.w	menu_multi_pack-main
	dc.w	menu_none-main
	dc.w	menu_none-main
	dc.w	menu_none-main
	dc.w	menu_lzh-main
	dc.w	menu_v2-main
	dc.w	menu_none-main
	dc.w	menu_ice-main
	dc.w	menu_lzw-main
	dc.w	menu_none-main
	dc.w	menu_unpack_file-main
	dc.w	menu_pack_file-main
	dc.w	menu_none-main
	dc.w	menu_toggle_program-main
	dc.w	menu_none-main
	dc.w	menu_none-main
	dc.w	menu_none-main
	dc.w	menu_disk_unpack-main
	dc.w	menu_disk_pack-main
	dc.w	menu_none-main
text_pack_power_v2:	; from: pack_power
	dc.b	'4384',0
	dc.b	$00
text_pack_power_ice:	; from: pack_power
	dc.b	'5504',0
	dc.b	$00
text_largest_v2_again:	; from: pack_power
	dc.b	'4384',0
	dc.b	$00
text_largest_ice_again:	; from: pack_power
	dc.b	'5504',0
	dc.b	$00
text_2048:	; from: pack_power
	dc.b	'2048',0
	dc.b	$00
text_1024:	; from: pack_power
	dc.b	'1024',0
	dc.b	$00
text_256:	; from: pack_power
	dc.b	' 256',0
	dc.b	$00
text_64:	; from: pack_power
	dc.b	'  64',0
	dc.b	$00
alert_file_not_found:	; from: pack_one_file
	dc.b	'[0][ |    File Not Found!   | ][Grrr!]',0
	dc.b	$00
alert_file_too_small:	; from: pack_one_file
	dc.b	'[0][ |   File Too Small | Not worth crunching! | ][Yes!]',0
	dc.b	$00
alert_not_executable:	; from: pack_one_file
	dc.b	'[2][ | Not an executable file | Pack as DATA only? |][ Yes | No '
	dc.b	'| Cancel ]',0
	dc.b	$00
alert_no_memory_to_compact:	; from: pack_one_file
	dc.b	'[0][ |  Insufficient Memory To   |       Compact File | ][Upgrad'
	dc.b	'e now!]',0
alert_error_reading_source:	; from: pack_one_file
	dc.b	'[0][|Error Reading Source File | ][Oh Shit!!]',0
alert_packed_size_larger:	; from: pack_one_file
	dc.b	'[0][| Packed Size > Original Size  |      File Not saved | ][Oh '
	dc.b	'well..]',0
alert_pack_aborted:	; from: pack_one_file
	dc.b	'[0][ |  Pack Aborted!   | ][Fine.]',0
	dc.b	$00
alert_low_rez:	; from: init_gem
	dc.b	'[1][ The JAM Packer V4.0 will| not work in low res. ][ Ok ]',0
alert_other_rez:	; from: init_gem
	dc.b	'[1][ Wow!  You',$27
	dc.b	've got a trendy|resolution on your system!|Unfortunately this pr'
	dc.b	'ogram|doesn',$27,'t support it.][ Oh... ]',0
	dc.b	$00
alert_no_workstation:	; from: open_workstation
	dc.b	'[1][ Couldn',$27,'t open workstation ][Exit]',0
	dc.b	$00
alert_no_files:	; from: multi_pack
	dc.b	'[1][ | |No files found to pack!| ][ Why',$27,'s that then?? ]',0
text_report_title:	; from: multi_pack
	dcb.w	11,$2020
	dc.b	' ****** MULTI PACKER REPORT ******',10,10,13,0
text_report_heading:	; from: multi_pack
	dc.b	9,'   FILE NOT COMPACTED',9,9,9,'REASON',10,13,0
text_report_underline:	; from: multi_pack
	dc.b	9,'   ------------------                   ------',10,13,0
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
text_reason_aborted:	; from: multi_pack
	dc.b	'Pack aborted',10,13,0
	dc.b	$00
text_reason_unknown:	; from: multi_pack
	dc.b	'Unknown error',10,13,0
text_press_return:	; from: multi_pack
	dc.b	10,'                           Press any key to continue',0
text_unpacking:	; from: unpack_file
	dc.b	'Unpacking File....',0
	dc.b	$00
alert_depack_error:	; from: unpack_file
	dc.b	'[1][ Fatal Error in Depack][ Shit! ]',0
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
alert_unpack_to_which_drive:	; from: disk_unpack
	dc.b	'[2][|Unpack file to which drive? ][  A:  |  B:  ]',0
alert_pack_which_drive:	; from: disk_pack
	dc.b	'[2][|Pack disk in which drive? ][  A:  |  B:  ]',0
alert_disk_read_error:	; from: disk_unpack, disk_pack, read_boot_sector
	dc.b	'[3][ Disk read error. ][Abort]',0
	dc.b	$00
	dc.b	'[3][ Disk Error. ][Abort]',0
	dc.b	'[0][Press RETURN  ][Ok]',0
alert_disk_write_error:	; from: disk_unpack, disk_pack, write_jpk_header
	dc.b	'[3][ Disk write error. ][Abort]',0
alert_format_error:	; from: disk_unpack
	dc.b	'[3][ Disk error while formatting.][Abort]',0
alert_cannot_read_fat:	; from: disk_pack
	dc.b	'[3][ Can',$27,'t read FAT ][Abort]',0
	dc.b	$00
alert_disk_pack_aborted:	; from: disk_pack
	dc.b	'[0][ |Disk Pack Aborted ][Ok]',0
alert_not_jpk:	; from: disk_unpack
	dc.b	'[1][ |Not a diskpack file ][Ok]',0
alert_cannot_create_file:	; from: disk_pack
	dc.b	'[3][ Can',$27,'t create file. ][Abort]',0
	dc.b	$00
alert_insufficient_memory:	; from: disk_unpack, disk_pack
	dc.b	'[3][ Insufficient Memory. ][Abort]',0
	dc.b	$00
dpk_path:	; from: disk_unpack, disk_pack
	dc.b	'\',0                           ; the JPK file's path
	dcb.b	126,0
text_root_unpack:	; from: disk_unpack
	dc.b	'\',0
text_dpk_mask_unpack:	; from: disk_unpack
	dc.b	'*.JPK',0
text_drivea_unpack:	; from: disk_unpack
	dc.b	'DRIVEA.JPK',0
	dc.b	$00
alert_get_from_which_drive:	; from: disk_unpack
	dc.b	'[2][|Get file from which drive? ][  A:  |  B:  |  C:  ]',0
text_choose_input:	; from: disk_unpack
	dc.b	'Choose the input pathname',0
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
	dc.b	'*.JPK',0
text_driveb_pack:	; from: disk_pack
	dc.b	'DRIVEB.JPK',0
	dc.b	$00
text_drivea_pack:	; from: disk_pack
	dc.b	'DRIVEA.JPK',0
	dc.b	$00
alert_save_to_which_drive:	; from: disk_pack
	dc.b	'[2][|Save to which drive? ][  A:  |  B:  |  C:  ]',0
text_choose_destination:	; from: disk_pack
	dc.b	'Choose the destination pathname',0
text_dpk_pack:	; from: disk_pack
	dc.b	'JPK',0
text_zero_to_pack:	; from: disk_pack
	dc.b	'0 to ',0
text_spaces:	; from: disk_pack
	dc.b	'            ',0
	dc.b	$00
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
text_jpk_magic:	; from: write_jpk_header
	dc.b	'JPK!',0
	dc.b	$00
text_analysing:	; from: analyse_disk
	dc.b	'Analysing disk format',0
text_dot:	; from: set_extension
	dc.b	'.',0
resource_high:	; from: init_gem
	dc.w	$0000,$05bc,$0370,$0370,$0370,$0370,$0024,$0370 ; the resource for high resolution, as in a .RSC file
	dc.w	$0370,$0f64,$0067,$0006,$0015,$0000,$0000,$0000
	dc.w	$0000
	dc.b	$0f
	dc.b	'|The JAM Packer V4.0',0
	dc.b	$00
	dc.b	'EXIT',0
	dc.b	$00
	dc.b	'LZH',0
	dc.b	$56,$32,$00
	dc.b	'Pack Method',0
	dc.b	$00
	dc.b	'ICE',0
	dc.b	'LZW',0
	dc.b	'PACK',0
	dc.b	'Multi Packer',0
	dc.b	$00
	dc.b	'Programs',0
	dc.b	'Program',0
	dc.b	'Flash',0
	dc.b	'UNPACK',0
	dc.b	'PACK',0
	dc.b	'Heading',0
	dc.b	'File Packer',0
	dc.b	$00
	dc.b	'Disk Packer',0
	dc.b	$00
	dc.b	'UnPACK',0
	dc.b	'PACK',0
	dc.b	'No Pack',0
	dc.b	'Use Boot',0
	dc.b	'Use FAT',0
	dc.b	'Format',0
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
	dc.w	$004f,$4b00
	dc.b	'FILENAME.DAT',0
	dc.b	'9999999 Bytes    ',0
	dc.b	'9999999 Bytes    ',0
	dc.b	'1234567 Bytes',0
	dc.b	'99%',0
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
	dc.b	'256',0
	dc.w	$3634
	dc.b	$00
	dc.b	'Larger',0
	dc.b	$00
	dc.b	'Set PackPower',0
	dc.b	$00,$4f,$6b,$00
	dc.b	'4380',0
	dc.b	'Slow',0
	dc.b	$00
	dc.b	'4384',0
	dc.b	'2048',0
	dc.b	'Fast',0
	dc.b	$00
	dc.b	'Smaller',0
	dc.b	$00
	dc.b	'1024',0
	dc.b	'(c) 1990,1991 by Andrew and Tim Knipe',0
	dc.b	$00
	dc.b	'AUSTRALIA',0
	dc.b	'Melbourne, 3000',0
	dc.b	'367 Collins Street',0
	dc.b	'P.O. Box 369',0
	dc.b	'Andrew Knipe',0
	dc.b	'AUSTRALIA',0
	dc.b	'Victoria',0
	dc.b	'Bendigo, 3551',0
	dc.b	'Maiden Gully RSD',0
	dc.b	'Tim Knipe',0
	dc.w	$4f52
	dc.b	$00
	dc.b	'This program is SHAREWARE',0
	dc.b	$00
	dc.b	'To contact us write to:',0
	dc.w	$4f6b
	dc.b	$00
	dc.b	'The JAM Packer V4.0',0
	dc.b	$00,$00,$00,$00,$24,$00,$00,$00,$00,$00,$00,$00,$38,$00,$03,$00
	dc.b	$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00,$14,$00,$01,$00,$00,$00
	dc.b	$39,$00,$00,$00,$00,$00,$00,$00,$3e,$00,$03,$00,$06,$00,$02,$11
	dc.b	$70,$00,$00,$00,$ff,$00,$05,$00,$01,$00,$00,$00,$46,$00,$00,$00
	dc.b	$00,$00,$00,$00,$52,$00,$03,$00,$06,$00,$02,$10,$71,$00,$00,$00
	dc.b	$ff,$00,$0c,$00,$01,$00,$00,$00,$60,$00,$00,$00,$00,$00,$00,$00
	dc.b	$6d,$00,$03,$00,$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00,$0d,$00
	dc.b	$01,$00,$00,$00,$99,$00,$00,$00,$00,$00,$00,$00,$a5,$00,$03,$00
	dc.b	$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00,$0c,$00,$01,$00,$00,$00
	dc.b	$a6,$00,$00,$00,$00,$00,$00,$00,$b2,$00,$03,$00,$06,$00,$02,$10
	dc.b	$71,$00,$00,$00,$ff,$00,$0c,$00,$01,$00,$00,$00,$df,$00,$00,$00
	dc.b	$00,$00,$00,$00,$ea,$00,$03,$00,$06,$00,$02,$10,$71,$00,$00,$00
	dc.b	$ff,$00,$0b,$00,$01,$00,$00,$00,$eb,$00,$00,$00,$00,$00,$00,$00
	dc.b	$ef,$00,$03,$00,$06,$00,$00,$11,$00,$00,$00,$00,$ff,$00,$04,$00
	dc.b	$01,$00,$00,$00,$f0,$00,$00,$00,$00,$00,$00,$00,$f4,$00,$03,$00
	dc.b	$06,$00,$00,$11,$00,$00,$00,$00,$ff,$00,$04,$00,$01,$00,$00,$00
	dc.b	$f5,$00,$00,$00,$00,$00,$00,$00,$f9,$00,$03,$00,$06,$00,$00,$11
	dc.b	$00,$00,$00,$00,$ff,$00,$04,$00,$01,$00,$00,$01,$42,$00,$00,$00
	dc.b	$00,$00,$00,$01,$4c,$00,$03,$00,$06,$00,$02,$10,$71,$00,$00,$00
	dc.b	$ff,$00,$0a,$00,$01,$00,$00,$01,$93,$00,$00,$00,$00,$00,$00,$01
	dc.b	$a6,$00,$03,$00,$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00,$13,$00
	dc.b	$01,$00,$00,$01,$e9,$00,$00,$00,$00,$00,$00,$01,$f3,$00,$03,$00
	dc.b	$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00,$0a,$00,$01,$00,$00,$02
	dc.b	$35,$00,$00,$00,$00,$00,$00,$02,$3c,$00,$05,$00,$06,$00,$02,$11
	dc.b	$80,$00,$00,$00,$ff,$00,$07,$00,$01,$00,$00,$02,$3d,$00,$00,$00
	dc.b	$00,$00,$00,$02,$4b,$00,$03,$00,$06,$00,$02,$10,$71,$00,$00,$00
	dc.b	$ff,$00,$0e,$00,$01,$00,$00,$02,$54,$00,$00,$00,$00,$00,$00,$02
	dc.b	$59,$00,$05,$00,$06,$00,$02,$11,$80,$00,$00,$00,$ff,$00,$05,$00
	dc.b	$01,$00,$00,$02,$64,$00,$00,$00,$00,$00,$00,$02,$69,$00,$05,$00
	dc.b	$06,$00,$02,$11,$80,$00,$00,$00,$ff,$00,$05,$00,$01,$00,$00,$02
	dc.b	$6a,$00,$00,$00,$00,$00,$00,$02,$72,$00,$05,$00,$06,$00,$02,$11
	dc.b	$80,$00,$00,$00,$ff,$00,$08,$00,$01,$00,$00,$02,$78,$00,$00,$00
	dc.b	$00,$00,$00,$02,$9e,$00,$03,$00,$06,$00,$00,$11,$80,$00,$00,$00
	dc.b	$ff,$00,$26,$00,$01,$00,$00,$03,$25,$00,$00,$00,$00,$00,$00,$03
	dc.b	$3f,$00,$03,$00,$06,$00,$00,$11,$80,$00,$00,$00,$ff,$00,$1a,$00
	dc.b	$01,$00,$00,$03,$5b,$00,$00,$00,$00,$00,$00,$03,$6f,$00,$03,$00
	dc.b	$06,$00,$02,$10,$71,$00,$00,$00,$00,$00,$14,$00,$01,$ff,$ff,$00
	dc.b	$01,$00,$15,$00,$14,$00,$00,$00,$00,$00,$02,$11,$31,$00,$00,$00
	dc.b	$00,$00,$2d,$00,$14,$00,$03,$00,$02,$00,$02,$00,$14,$00,$40,$00
	dc.b	$30,$00,$ff,$11,$71,$00,$02,$00,$01,$00,$18,$00,$02,$00,$01,$ff
	dc.b	$ff,$ff,$ff,$00,$15,$00,$40,$00,$00,$00,$00,$03,$70,$05,$02,$07
	dc.b	$00,$00,$13,$00,$01,$00,$04,$ff,$ff,$ff,$ff,$00,$16,$00,$05,$00
	dc.b	$00,$00,$00,$03,$8c,$00,$1d,$00,$01,$00,$0e,$00,$02,$00,$08,$00
	dc.b	$09,$00,$0d,$00,$14,$00,$00,$00,$20,$00,$ff,$11,$43,$00,$02,$00
	dc.b	$04,$00,$14,$02,$05,$00,$0b,$ff,$ff,$ff,$ff,$00,$1a,$00,$05,$00
	dc.b	$00,$00,$00,$00,$5b,$00,$02,$00,$05,$00,$0f,$00,$01,$00,$0c,$ff
	dc.b	$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$03,$a8,$00,$02,$07
	dc.b	$00,$00,$10,$00,$01,$00,$08,$ff,$ff,$ff,$ff,$00,$1a,$00,$01,$00
	dc.b	$00,$00,$00,$00,$6e,$00,$02,$00,$03,$00,$0f,$00,$01,$00,$0e,$00
	dc.b	$05,$00,$07,$00,$14,$00,$00,$00,$20,$00,$01,$11,$42,$00,$18,$00
	dc.b	$04,$00,$13,$00,$07,$00,$0a,$ff,$ff,$ff,$ff,$00,$1a,$00,$51,$00
	dc.b	$00,$00,$00,$00,$3f,$00,$02,$03,$02,$00,$07,$00,$01,$00,$06,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$51,$00,$00,$00,$00,$00,$43,$00,$0b,$03
	dc.b	$02,$00,$07,$00,$01,$00,$07,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00
	dc.b	$30,$00,$00,$03,$c4,$00,$02,$0a,$00,$00,$0f,$00,$01,$00,$0d,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$51,$00,$00,$00,$00,$00,$53,$00,$02,$08
	dc.b	$03,$00,$07,$00,$01,$00,$04,$ff,$ff,$ff,$ff,$00,$1a,$00,$51,$00
	dc.b	$00,$00,$00,$00,$57,$00,$0b,$08,$03,$00,$07,$00,$01,$00,$15,$00
	dc.b	$12,$00,$11,$00,$14,$00,$00,$00,$20,$00,$ff,$11,$42,$00,$02,$00
	dc.b	$0a,$00,$14,$00,$09,$00,$10,$ff,$ff,$ff,$ff,$00,$1a,$00,$05,$00
	dc.b	$00,$00,$00,$00,$85,$00,$0b,$07,$07,$00,$08,$00,$01,$00,$14,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$05,$00,$00,$00,$00,$00,$8c,$02,$01,$07
	dc.b	$07,$00,$08,$00,$01,$00,$0e,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00
	dc.b	$30,$00,$00,$03,$e0,$00,$02,$0b,$00,$00,$10,$00,$01,$00,$13,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$40,$00,$00,$00,$00,$00,$77,$00,$02,$03
	dc.b	$03,$00,$08,$00,$01,$00,$0f,$ff,$ff,$ff,$ff,$00,$1a,$00,$01,$00
	dc.b	$00,$00,$00,$00,$7f,$00,$0b,$03,$03,$00,$07,$00,$01,$00,$11,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$01,$00,$00,$00,$00,$00,$91,$00,$02,$01
	dc.b	$05,$00,$10,$00,$01,$00,$00,$00,$1a,$00,$19,$00,$14,$00,$00,$00
	dc.b	$20,$00,$ff,$11,$41,$00,$18,$0d,$0b,$00,$13,$03,$07,$00,$17,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$05,$00,$00,$00,$00,$00,$b3,$00,$0a,$0b
	dc.b	$05,$00,$07,$00,$01,$00,$1c,$ff,$ff,$ff,$ff,$00,$1a,$00,$05,$00
	dc.b	$00,$00,$00,$00,$ba,$00,$02,$0b,$05,$00,$07,$00,$01,$00,$19,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$01,$00,$00,$00,$00,$00,$d0,$00,$01,$03
	dc.b	$02,$00,$08,$00,$01,$00,$15,$ff,$ff,$ff,$ff,$00,$1a,$00,$21,$00
	dc.b	$00,$00,$00,$00,$d8,$00,$0a,$03,$02,$00,$08,$00,$01,$00,$16,$ff
	dc.b	$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$03,$fc,$00,$02,$06
	dc.b	$00,$00,$0f,$00,$01,$00,$18,$ff,$ff,$ff,$ff,$00,$1a,$00,$01,$00
	dc.b	$00,$00,$00,$00,$c7,$00,$01,$0d,$03,$00,$08,$00,$01,$00,$1b,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$01,$00,$00,$00,$00,$00,$bf,$00,$0a,$0d
	dc.b	$03,$00,$08,$00,$01,$ff,$ff,$00,$01,$00,$02,$00,$14,$00,$00,$00
	dc.b	$10,$00,$02,$11,$22,$00,$00,$00,$00,$00,$12,$00,$16,$00,$02,$ff
	dc.b	$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$04,$18,$00,$02,$00
	dc.b	$01,$00,$0e,$00,$01,$00,$00,$00,$03,$00,$05,$00,$14,$00,$00,$00
	dc.b	$00,$00,$01,$11,$43,$07,$06,$00,$03,$01,$04,$00,$12,$00,$04,$ff
	dc.b	$ff,$ff,$ff,$00,$15,$00,$00,$00,$00,$00,$00,$04,$34,$05,$00,$06
	dc.b	$08,$00,$03,$00,$01,$00,$05,$ff,$ff,$ff,$ff,$00,$15,$00,$00,$00
	dc.b	$00,$00,$00,$04,$50,$05,$00,$05,$04,$00,$03,$00,$01,$00,$02,$ff
	dc.b	$ff,$ff,$ff,$00,$15,$00,$20,$00,$00,$00,$00,$04,$6c,$05,$00,$00
	dc.b	$0d,$00,$03,$00,$01,$ff,$ff,$00,$01,$00,$0c,$00,$14,$00,$00,$00
	dc.b	$10,$00,$02,$11,$03,$00,$00,$00,$00,$00,$24,$00,$10,$00,$02,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$00,$fa,$00,$03,$00
	dc.b	$05,$00,$0f,$00,$01,$00,$03,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$01,$0a,$00,$04,$00,$07,$00,$0e,$00,$01,$00,$04,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$19,$00,$04,$00
	dc.b	$0b,$00,$0e,$00,$01,$00,$05,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$01,$28,$00,$06,$00,$08,$00,$0c,$00,$01,$00,$06,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$35,$00,$06,$00
	dc.b	$0a,$00,$0c,$00,$01,$00,$07,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00
	dc.b	$30,$00,$00,$04,$88,$00,$07,$00,$01,$00,$15,$00,$02,$00,$08,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$07,$00,$00,$00,$00,$01,$4d,$00,$0a,$05
	dc.b	$0d,$00,$10,$00,$01,$00,$09,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$01,$50,$00,$13,$00,$05,$00,$0d,$00,$01,$00,$0a,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$5d,$00,$13,$00
	dc.b	$07,$00,$11,$00,$01,$00,$0b,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$01,$6f,$00,$13,$00,$08,$00,$11,$00,$01,$00,$0c,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$81,$00,$13,$00
	dc.b	$0a,$00,$11,$00,$01,$00,$00,$ff,$ff,$ff,$ff,$00,$1c,$00,$20,$00
	dc.b	$00,$00,$00,$01,$8f,$00,$13,$00,$0b,$00,$06,$00,$01,$ff,$ff,$00
	dc.b	$01,$00,$11,$00,$14,$00,$00,$00,$10,$00,$02,$11,$33,$00,$00,$00
	dc.b	$00,$00,$21,$00,$0e,$00,$02,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00
	dc.b	$30,$00,$00,$04,$a4,$00,$02,$00,$01,$00,$1d,$00,$02,$00,$07,$00
	dc.b	$03,$00,$06,$00,$14,$00,$00,$00,$20,$00,$ff,$11,$00,$00,$02,$00
	dc.b	$04,$00,$1d,$01,$02,$00,$04,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$01,$a7,$00,$16,$00,$00,$00,$04,$00,$01,$00,$05,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$ac,$00,$03,$00
	dc.b	$00,$00,$12,$00,$01,$00,$06,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$01,$bf,$00,$01,$00,$01,$00,$1c,$00,$01,$00,$02,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$dc,$00,$11,$00
	dc.b	$01,$00,$0c,$00,$01,$00,$08,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00
	dc.b	$30,$00,$00,$04,$c0,$00,$02,$00,$07,$00,$1d,$00,$01,$00,$11,$00
	dc.b	$09,$00,$10,$00,$14,$00,$00,$00,$20,$00,$ff,$11,$01,$00,$02,$00
	dc.b	$09,$00,$1d,$00,$02,$00,$0a,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$01,$f4,$00,$17,$00,$00,$00,$02,$00,$01,$00,$0b,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$f7,$00,$17,$00
	dc.b	$01,$00,$02,$00,$01,$00,$0c,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$01,$fa,$00,$10,$00,$00,$00,$06,$00,$01,$00,$0d,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$01,$00,$12,$00
	dc.b	$01,$00,$04,$00,$01,$00,$0e,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$02,$06,$00,$0c,$00,$01,$00,$02,$00,$01,$00,$0f,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$09,$00,$0c,$00
	dc.b	$00,$00,$01,$00,$01,$00,$10,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$02,$0b,$00,$05,$00,$00,$00,$06,$00,$01,$00,$08,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$12,$00,$04,$00
	dc.b	$01,$00,$07,$00,$01,$00,$00,$00,$12,$00,$13,$00,$14,$00,$00,$00
	dc.b	$20,$00,$ff,$11,$01,$00,$02,$00,$0c,$00,$1d,$00,$01,$00,$13,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$1a,$00,$14,$00
	dc.b	$00,$00,$04,$00,$01,$00,$11,$ff,$ff,$ff,$ff,$00,$1c,$00,$20,$00
	dc.b	$00,$00,$00,$02,$1f,$00,$05,$00,$00,$00,$0e,$00,$01,$ff,$ff,$00
	dc.b	$07,$00,$0b,$00,$14,$00,$00,$00,$10,$00,$02,$11,$41,$00,$00,$00
	dc.b	$00,$00,$1b,$00,$0a,$00,$02,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00
	dc.b	$00,$00,$00,$04,$dc,$04,$14,$07,$04,$07,$04,$07,$00,$00,$10,$ff
	dc.b	$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$04,$f8,$06,$02,$09
	dc.b	$00,$05,$15,$03,$01,$00,$04,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00
	dc.b	$00,$00,$00,$05,$14,$00,$02,$08,$02,$03,$04,$07,$00,$00,$05,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$40,$00,$00,$00,$00,$02,$5a,$00,$02,$03
	dc.b	$03,$04,$04,$00,$01,$00,$09,$ff,$ff,$ff,$ff,$00,$1a,$00,$40,$00
	dc.b	$00,$00,$00,$02,$5f,$01,$07,$03,$03,$04,$04,$00,$01,$00,$0f,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$40,$00,$00,$00,$00,$02,$73,$04,$0c,$03
	dc.b	$03,$04,$04,$00,$01,$00,$08,$ff,$ff,$ff,$ff,$00,$1a,$00,$40,$00
	dc.b	$00,$00,$00,$02,$2e,$07,$11,$03,$03,$04,$03,$00,$01,$00,$01,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$40,$00,$00,$00,$00,$02,$32,$03,$16,$03
	dc.b	$03,$00,$03,$00,$01,$00,$0a,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00
	dc.b	$00,$00,$00,$05,$30,$03,$16,$08,$02,$00,$03,$07,$00,$00,$06,$ff
	dc.b	$ff,$ff,$ff,$00,$16,$00,$00,$00,$00,$00,$00,$05,$4c,$00,$02,$07
	dc.b	$04,$05,$05,$07,$00,$00,$00,$ff,$ff,$ff,$ff,$00,$1b,$00,$60,$00
	dc.b	$00,$04,$ff,$11,$00,$02,$05,$0b,$05,$00,$05,$00,$02,$00,$03,$00
	dc.b	$0d,$00,$0e,$00,$14,$00,$00,$00,$00,$00,$ff,$11,$00,$03,$0a,$0b
	dc.b	$05,$00,$06,$00,$02,$00,$0e,$ff,$ff,$ff,$ff,$00,$14,$00,$00,$00
	dc.b	$00,$00,$ff,$01,$00,$00,$01,$06,$00,$07,$03,$04,$01,$00,$0c,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$4f,$07,$00,$07
	dc.b	$00,$00,$04,$00,$01,$00,$0b,$ff,$ff,$ff,$ff,$00,$1b,$00,$40,$00
	dc.b	$00,$03,$ff,$11,$00,$04,$10,$0b,$05,$00,$05,$00,$02,$00,$0c,$ff
	dc.b	$ff,$ff,$ff,$00,$1a,$00,$07,$00,$00,$00,$00,$02,$4c,$05,$09,$06
	dc.b	$08,$00,$08,$00,$01,$ff,$ff,$00,$01,$00,$11,$00,$14,$00,$00,$00
	dc.b	$10,$00,$02,$11,$52,$00,$00,$00,$00,$00,$3d,$00,$14,$00,$02,$00
	dc.b	$03,$00,$10,$00,$14,$00,$00,$00,$20,$00,$02,$11,$00,$00,$06,$03
	dc.b	$05,$00,$31,$00,$0b,$00,$11,$ff,$ff,$ff,$ff,$00,$1a,$00,$07,$00
	dc.b	$00,$00,$00,$03,$58,$01,$11,$06,$11,$00,$1c,$00,$01,$00,$04,$ff
	dc.b	$ff,$ff,$ff,$00,$15,$00,$00,$00,$00,$00,$00,$05,$68,$00,$06,$07
	dc.b	$00,$00,$25,$00,$01,$00,$05,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$02,$9f,$00,$05,$01,$09,$00,$09,$00,$01,$00,$06,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$a9,$00,$05,$01
	dc.b	$08,$00,$0f,$00,$01,$00,$07,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$02,$b9,$00,$05,$01,$07,$00,$12,$00,$01,$00,$08,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$cc,$00,$05,$01
	dc.b	$06,$00,$0c,$00,$01,$00,$09,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$02,$d9,$00,$05,$01,$05,$00,$0c,$00,$01,$00,$0a,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$e6,$05,$1d,$01
	dc.b	$09,$00,$09,$00,$01,$00,$0b,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$02,$f0,$05,$1d,$01,$08,$00,$08,$00,$01,$00,$0c,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$f9,$05,$1d,$01
	dc.b	$07,$00,$0d,$00,$01,$00,$0d,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$03,$07,$05,$1d,$01,$06,$00,$10,$00,$01,$00,$0e,$ff
	dc.b	$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$03,$18,$05,$1d,$01
	dc.b	$05,$00,$09,$00,$01,$00,$0f,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$03,$22,$00,$19,$02,$05,$01,$02,$00,$01,$00,$10,$ff
	dc.b	$ff,$ff,$ff,$00,$15,$00,$00,$00,$00,$00,$00,$05,$84,$04,$0c,$09
	dc.b	$01,$00,$19,$00,$01,$00,$01,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00
	dc.b	$00,$00,$00,$03,$40,$00,$05,$05,$03,$00,$17,$00,$01,$00,$00,$ff
	dc.b	$ff,$ff,$ff,$00,$16,$00,$20,$00,$30,$00,$00,$05,$a0,$00,$08,$00
	dc.b	$01,$00,$2d,$00,$03,$00,$00,$05,$bc,$00,$00,$09,$04,$00,$00,$08
	dc.b	$74,$00,$00,$0a,$3c,$00,$00,$0d,$b4,$00,$00,$0c,$1c
resource_medium:	; from: init_gem
	dc.w	$0000,$05bc,$0370,$0370,$0370,$0370,$0024,$0370 ; the resource for medium resolution
	dc.w	$0370,$0f64,$0067,$0006,$0015,$0000,$0000,$0000
	dc.w	$0000
	dc.b	$0f
	dc.b	'|Set PackPower',0
	dc.b	$00
	dc.b	'4384',0
	dc.b	'Slow',0
	dc.b	$00
	dc.b	'Smaller',0
	dc.b	$00
	dc.b	'2048',0
	dc.b	'1024',0
	dc.b	'256',0
	dc.b	$36,$34,$00
	dc.b	'Fast',0
	dc.b	$00
	dc.b	'Larger',0
	dc.b	$00
	dc.b	'4380',0
	dc.b	$4f,$6b,$00
	dc.b	'PACKOMETER',0
	dc.b	$00
	dc.b	'50%',0
	dc.b	$00
	dc.b	'75%',0
	dc.b	$00
	dc.b	'25%',0
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
	dc.b	'Crunching File:',0
	dc.b	'Original Size:',0
	dc.b	'% of Original:',0
	dc.b	'Packed Size:',0
	dc.b	'Space Saved:',0
	dc.w	$4f4b
	dc.b	$00
	dc.b	'FILENAME.DAT',0
	dc.b	'9999999 Bytes    ',0
	dc.b	'9999999 Bytes    ',0
	dc.b	'1234567 Bytes',0
	dc.b	'99%',0
	dc.b	'Pack Info',0
	dc.b	$00
	dc.b	'EXIT',0
	dc.b	$00
	dc.b	'The JAM Packer V4.0',0
	dc.b	$00
	dc.b	'LZH',0
	dc.w	$5632
	dc.b	$00
	dc.b	'Pack Method',0
	dc.b	$00
	dc.b	'ICE',0
	dc.b	'LZW',0
	dc.b	'PACK',0
	dc.b	'Multi Packer',0
	dc.b	$00
	dc.b	'Programs',0
	dc.b	'File Packer',0
	dc.b	$00
	dc.b	'Program',0
	dc.b	'Flash',0
	dc.b	'Heading',0
	dc.b	'UNPACK',0
	dc.b	'PACK',0
	dc.b	'Use FAT',0
	dc.b	'Format',0
	dc.b	'Disk Packer',0
	dc.b	$00
	dc.b	'Use Boot',0
	dc.b	'No Pack',0
	dc.b	'PACK',0
	dc.b	'UnPACK',0
	dc.b	'The JAM Packer V4.0',0
	dc.b	$00
	dc.b	'This program is SHAREWARE',0
	dc.b	$00
	dc.b	'(c) 1990,1991 by Andrew and Tim Knipe',0
	dc.b	$00
	dc.b	'To contact us write to:',0
	dc.b	'Andrew Knipe',0
	dc.b	'P.O. Box 369',0
	dc.b	'367 Collins Street',0
	dc.b	'Melbourne, 3000',0
	dc.b	'AUSTRALIA',0
	dc.w	$4f52
	dc.b	$00
	dc.b	'Maiden Gully RSD',0
	dc.b	'Bendigo, 3551',0
	dc.b	'Victoria',0
	dc.b	'AUSTRALIA',0
	dc.b	'Tim Knipe',0
	dc.b	$4f,$6b,$00,$00,$00,$00,$24,$00,$00,$00,$00,$00,$00,$00,$32,$00
	dc.b	$03,$00,$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00,$0e,$00,$01,$00
	dc.b	$00,$00,$38,$00,$00,$00,$00,$00,$00,$00,$3d,$00,$05,$00,$06,$00
	dc.b	$02,$11,$80,$00,$00,$00,$ff,$00,$05,$00,$01,$00,$00,$00,$3e,$00
	dc.b	$00,$00,$00,$00,$00,$00,$46,$00,$05,$00,$06,$00,$02,$11,$80,$00
	dc.b	$00,$00,$ff,$00,$08,$00,$01,$00,$00,$00,$58,$00,$00,$00,$00,$00
	dc.b	$00,$00,$5d,$00,$05,$00,$06,$00,$02,$11,$80,$00,$00,$00,$ff,$00
	dc.b	$05,$00,$01,$00,$00,$00,$5e,$00,$00,$00,$00,$00,$00,$00,$65,$00
	dc.b	$05,$00,$06,$00,$02,$11,$80,$00,$00,$00,$ff,$00,$07,$00,$01,$00
	dc.b	$00,$00,$6e,$00,$00,$00,$00,$00,$00,$00,$79,$00,$03,$00,$06,$00
	dc.b	$02,$10,$71,$00,$00,$00,$ff,$00,$0b,$00,$01,$00,$00,$00,$7a,$00
	dc.b	$00,$00,$00,$00,$00,$00,$7e,$00,$03,$00,$06,$00,$00,$11,$00,$00
	dc.b	$00,$00,$ff,$00,$04,$00,$01,$00,$00,$00,$7f,$00,$00,$00,$00,$00
	dc.b	$00,$00,$83,$00,$03,$00,$06,$00,$00,$11,$00,$00,$00,$00,$ff,$00
	dc.b	$04,$00,$01,$00,$00,$00,$84,$00,$00,$00,$00,$00,$00,$00,$88,$00
	dc.b	$03,$00,$06,$00,$00,$11,$00,$00,$00,$00,$ff,$00,$04,$00,$01,$00
	dc.b	$00,$00,$89,$00,$00,$00,$00,$00,$00,$00,$9c,$00,$03,$00,$06,$00
	dc.b	$02,$10,$71,$00,$00,$00,$ff,$00,$13,$00,$01,$00,$00,$00,$df,$00
	dc.b	$00,$00,$00,$00,$00,$00,$e9,$00,$03,$00,$06,$00,$02,$10,$71,$00
	dc.b	$00,$00,$ff,$00,$0a,$00,$01,$00,$00,$01,$b2,$00,$00,$00,$00,$00
	dc.b	$00,$01,$bc,$00,$03,$00,$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00
	dc.b	$0a,$00,$01,$00,$00,$01,$bd,$00,$00,$00,$00,$00,$00,$01,$c2,$00
	dc.b	$03,$00,$06,$00,$02,$11,$70,$00,$00,$00,$ff,$00,$05,$00,$01,$00
	dc.b	$00,$01,$c3,$00,$00,$00,$00,$00,$00,$01,$d7,$00,$03,$00,$06,$00
	dc.b	$02,$10,$71,$00,$00,$00,$ff,$00,$14,$00,$01,$00,$00,$01,$df,$00
	dc.b	$00,$00,$00,$00,$00,$01,$eb,$00,$03,$00,$06,$00,$02,$10,$71,$00
	dc.b	$00,$00,$ff,$00,$0c,$00,$01,$00,$00,$01,$f9,$00,$00,$00,$00,$00
	dc.b	$00,$02,$06,$00,$03,$00,$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00
	dc.b	$0d,$00,$01,$00,$00,$02,$10,$00,$00,$00,$00,$00,$00,$02,$1c,$00
	dc.b	$03,$00,$06,$00,$02,$10,$71,$00,$00,$00,$ff,$00,$0c,$00,$01,$00
	dc.b	$00,$02,$4e,$00,$00,$00,$00,$00,$00,$02,$5a,$00,$03,$00,$06,$00
	dc.b	$02,$10,$71,$00,$00,$00,$ff,$00,$0c,$00,$01,$00,$00,$02,$78,$00
	dc.b	$00,$00,$00,$00,$00,$02,$8c,$00,$03,$00,$06,$00,$02,$10,$71,$00
	dc.b	$00,$00,$00,$00,$14,$00,$01,$00,$00,$02,$8d,$00,$00,$00,$00,$00
	dc.b	$00,$02,$a7,$00,$03,$00,$06,$00,$00,$11,$80,$00,$00,$00,$ff,$00
	dc.b	$1a,$00,$01,$00,$00,$02,$a8,$00,$00,$00,$00,$00,$00,$02,$ce,$00
	dc.b	$03,$00,$06,$00,$00,$11,$80,$00,$00,$00,$ff,$00,$26,$00,$01,$ff
	dc.b	$ff,$00,$01,$00,$10,$00,$14,$00,$00,$00,$10,$00,$02,$11,$63,$00
	dc.b	$00,$00,$00,$00,$1b,$00,$0c,$00,$04,$ff,$ff,$ff,$ff,$00,$16,$00
	dc.b	$00,$00,$30,$00,$00,$03,$70,$06,$02,$06,$00,$05,$15,$03,$01,$00
	dc.b	$03,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00,$00,$00,$00,$03,$8c,$04
	dc.b	$01,$07,$02,$03,$04,$07,$00,$00,$05,$ff,$ff,$ff,$ff,$00,$16,$00
	dc.b	$00,$00,$00,$00,$00,$03,$a8,$04,$01,$04,$05,$05,$05,$07,$00,$00
	dc.b	$02,$ff,$ff,$ff,$ff,$00,$1a,$00,$40,$00,$00,$00,$00,$00,$33,$03
	dc.b	$01,$01,$04,$04,$04,$00,$01,$00,$06,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$40,$00,$00,$00,$00,$00,$47,$07,$06,$01,$04,$04,$04,$00,$01,$00
	dc.b	$07,$ff,$ff,$ff,$ff,$00,$1a,$00,$40,$00,$00,$00,$00,$00,$4c,$03
	dc.b	$0c,$01,$04,$04,$04,$00,$01,$00,$08,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$40,$00,$00,$00,$00,$00,$51,$07,$11,$01,$04,$04,$03,$00,$01,$00
	dc.b	$09,$ff,$ff,$ff,$ff,$00,$1a,$00,$40,$00,$00,$00,$00,$00,$55,$03
	dc.b	$16,$01,$04,$00,$03,$00,$01,$00,$0a,$ff,$ff,$ff,$ff,$00,$16,$00
	dc.b	$00,$00,$00,$00,$00,$03,$c4,$03,$16,$07,$02,$00,$03,$07,$00,$00
	dc.b	$0b,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00,$00,$00,$00,$03,$e0,$05
	dc.b	$14,$04,$05,$07,$04,$07,$00,$00,$0f,$ff,$ff,$ff,$ff,$00,$1b,$00
	dc.b	$40,$00,$00,$04,$ff,$11,$00,$01,$05,$00,$07,$00,$05,$00,$02,$00
	dc.b	$10,$00,$0d,$00,$0e,$00,$14,$00,$00,$00,$00,$00,$ff,$11,$00,$03
	dc.b	$0a,$00,$07,$00,$06,$00,$02,$00,$0e,$ff,$ff,$ff,$ff,$00,$14,$00
	dc.b	$00,$00,$00,$00,$ff,$01,$00,$01,$01,$05,$00,$07,$03,$07,$00,$00
	dc.b	$0c,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$00,$66,$00
	dc.b	$01,$05,$00,$00,$04,$00,$01,$00,$0c,$ff,$ff,$ff,$ff,$00,$1b,$00
	dc.b	$40,$00,$00,$03,$ff,$11,$00,$05,$10,$00,$07,$00,$05,$00,$02,$00
	dc.b	$00,$ff,$ff,$ff,$ff,$00,$1a,$00,$27,$00,$00,$00,$00,$00,$6b,$06
	dc.b	$09,$01,$0a,$00,$08,$00,$01,$ff,$ff,$00,$01,$00,$02,$00,$14,$00
	dc.b	$00,$00,$10,$00,$02,$11,$22,$00,$00,$00,$00,$00,$12,$00,$16,$00
	dc.b	$02,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$03,$fc,$00
	dc.b	$02,$00,$01,$00,$0e,$00,$01,$00,$00,$00,$03,$00,$05,$00,$14,$00
	dc.b	$00,$00,$00,$00,$01,$11,$43,$07,$06,$00,$03,$01,$04,$00,$12,$00
	dc.b	$04,$ff,$ff,$ff,$ff,$00,$15,$00,$00,$00,$00,$00,$00,$04,$18,$05
	dc.b	$00,$06,$08,$00,$03,$00,$01,$00,$05,$ff,$ff,$ff,$ff,$00,$15,$00
	dc.b	$00,$00,$00,$00,$00,$04,$34,$05,$00,$05,$04,$00,$03,$00,$01,$00
	dc.b	$02,$ff,$ff,$ff,$ff,$00,$15,$00,$20,$00,$00,$00,$00,$04,$50,$05
	dc.b	$00,$00,$0d,$00,$03,$00,$01,$ff,$ff,$00,$01,$00,$11,$00,$14,$00
	dc.b	$00,$00,$10,$00,$02,$11,$33,$00,$00,$00,$00,$00,$21,$00,$0e,$00
	dc.b	$02,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$04,$6c,$00
	dc.b	$02,$00,$01,$00,$1d,$00,$02,$00,$07,$00,$03,$00,$06,$00,$14,$00
	dc.b	$00,$00,$20,$00,$ff,$11,$00,$00,$02,$00,$04,$00,$1d,$01,$02,$00
	dc.b	$04,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$00,$9d,$00
	dc.b	$16,$00,$00,$00,$04,$00,$01,$00,$05,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$00,$a2,$00,$03,$00,$00,$00,$12,$00,$01,$00
	dc.b	$06,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$00,$b5,$00
	dc.b	$01,$00,$01,$00,$1c,$00,$01,$00,$02,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$00,$d2,$00,$11,$00,$01,$00,$0c,$00,$01,$00
	dc.b	$08,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$04,$88,$00
	dc.b	$02,$00,$07,$00,$1d,$00,$01,$00,$11,$00,$09,$00,$10,$00,$14,$00
	dc.b	$00,$00,$20,$00,$ff,$11,$01,$00,$02,$00,$09,$00,$1d,$00,$02,$00
	dc.b	$0a,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$00,$ea,$00
	dc.b	$17,$00,$00,$00,$02,$00,$01,$00,$0b,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$00,$ed,$00,$17,$00,$01,$00,$02,$00,$01,$00
	dc.b	$0c,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$00,$f0,$00
	dc.b	$10,$00,$00,$00,$06,$00,$01,$00,$0d,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$00,$f7,$00,$12,$00,$01,$00,$04,$00,$01,$00
	dc.b	$0e,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$00,$fc,$00
	dc.b	$0c,$00,$01,$00,$02,$00,$01,$00,$0f,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$00,$ff,$00,$0c,$00,$00,$00,$01,$00,$01,$00
	dc.b	$10,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$01,$00
	dc.b	$05,$00,$00,$00,$06,$00,$01,$00,$08,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$01,$08,$00,$04,$00,$01,$00,$07,$00,$01,$00
	dc.b	$00,$00,$12,$00,$13,$00,$14,$00,$00,$00,$20,$00,$ff,$11,$01,$00
	dc.b	$02,$00,$0c,$00,$1d,$00,$01,$00,$13,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$01,$10,$00,$14,$00,$00,$00,$04,$00,$01,$00
	dc.b	$11,$ff,$ff,$ff,$ff,$00,$1c,$00,$20,$00,$00,$00,$00,$01,$15,$00
	dc.b	$05,$00,$00,$00,$0e,$00,$01,$ff,$ff,$00,$01,$00,$06,$00,$14,$00
	dc.b	$00,$00,$10,$00,$02,$11,$03,$00,$00,$00,$00,$00,$24,$00,$10,$00
	dc.b	$02,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$24,$00
	dc.b	$03,$00,$05,$00,$0f,$00,$01,$00,$03,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$01,$34,$00,$04,$00,$07,$00,$0e,$00,$01,$00
	dc.b	$04,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$43,$00
	dc.b	$04,$00,$0b,$00,$0e,$00,$01,$00,$05,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$01,$52,$00,$06,$00,$08,$00,$0c,$00,$01,$00
	dc.b	$07,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$5f,$00
	dc.b	$06,$00,$0a,$00,$0c,$00,$01,$00,$00,$ff,$ff,$ff,$ff,$00,$16,$00
	dc.b	$20,$00,$30,$00,$00,$04,$a4,$02,$07,$00,$01,$00,$15,$00,$02,$00
	dc.b	$08,$ff,$ff,$ff,$ff,$00,$1a,$00,$07,$00,$00,$00,$00,$01,$6c,$00
	dc.b	$0a,$05,$0d,$00,$10,$00,$01,$00,$09,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$01,$6f,$00,$13,$00,$05,$00,$0d,$00,$01,$00
	dc.b	$0a,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$7c,$00
	dc.b	$13,$00,$07,$00,$11,$00,$01,$00,$0b,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$01,$8e,$00,$13,$00,$08,$00,$11,$00,$01,$00
	dc.b	$0c,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$01,$a0,$00
	dc.b	$13,$00,$0a,$00,$11,$00,$01,$00,$06,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$01,$ae,$00,$13,$00,$0b,$00,$06,$00,$01,$ff
	dc.b	$ff,$00,$03,$00,$15,$00,$14,$00,$00,$00,$00,$00,$02,$11,$41,$00
	dc.b	$00,$00,$00,$00,$2d,$00,$14,$00,$04,$00,$02,$00,$02,$00,$14,$00
	dc.b	$40,$00,$30,$00,$ff,$11,$71,$02,$02,$07,$00,$00,$18,$00,$02,$00
	dc.b	$01,$ff,$ff,$ff,$ff,$00,$15,$00,$40,$00,$00,$00,$00,$04,$dc,$06
	dc.b	$02,$04,$00,$00,$13,$00,$01,$00,$01,$ff,$ff,$ff,$ff,$00,$16,$00
	dc.b	$05,$00,$00,$00,$00,$04,$c0,$04,$1c,$00,$01,$00,$0e,$00,$02,$00
	dc.b	$08,$00,$09,$00,$0d,$00,$14,$00,$00,$00,$20,$00,$ff,$11,$73,$00
	dc.b	$02,$06,$03,$00,$14,$02,$05,$00,$0b,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$05,$00,$00,$00,$00,$01,$f4,$00,$02,$00,$05,$00,$0f,$00,$01,$00
	dc.b	$0c,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$04,$f8,$00
	dc.b	$02,$05,$00,$00,$10,$00,$01,$00,$08,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$01,$00,$00,$00,$00,$02,$07,$00,$02,$03,$03,$00,$0f,$00,$01,$00
	dc.b	$0e,$00,$05,$00,$07,$00,$14,$00,$00,$00,$20,$00,$01,$11,$42,$00
	dc.b	$18,$05,$03,$00,$13,$00,$07,$00,$0a,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$51,$00,$00,$00,$00,$01,$d8,$00,$02,$03,$02,$00,$07,$00,$01,$00
	dc.b	$06,$ff,$ff,$ff,$ff,$00,$1a,$00,$51,$00,$00,$00,$00,$01,$dc,$00
	dc.b	$0b,$03,$02,$00,$07,$00,$01,$00,$07,$ff,$ff,$ff,$ff,$00,$16,$00
	dc.b	$00,$00,$30,$00,$00,$05,$14,$00,$02,$00,$01,$00,$0f,$00,$01,$00
	dc.b	$0d,$ff,$ff,$ff,$ff,$00,$1a,$00,$51,$00,$00,$00,$00,$01,$ec,$00
	dc.b	$02,$07,$03,$00,$07,$00,$01,$00,$04,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$51,$00,$00,$00,$00,$01,$f0,$00,$0b,$07,$03,$00,$07,$00,$01,$00
	dc.b	$15,$00,$11,$00,$10,$00,$14,$00,$00,$00,$20,$00,$ff,$11,$72,$00
	dc.b	$02,$07,$09,$00,$14,$00,$09,$00,$10,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$05,$00,$00,$00,$00,$02,$33,$00,$0b,$01,$07,$00,$08,$00,$01,$00
	dc.b	$0e,$ff,$ff,$ff,$ff,$00,$1a,$00,$05,$00,$00,$00,$00,$02,$3a,$02
	dc.b	$01,$01,$07,$00,$08,$00,$01,$00,$12,$ff,$ff,$ff,$ff,$00,$16,$00
	dc.b	$00,$00,$30,$00,$00,$05,$30,$00,$02,$07,$00,$00,$10,$00,$01,$00
	dc.b	$13,$ff,$ff,$ff,$ff,$00,$1a,$00,$40,$00,$00,$00,$00,$02,$1d,$00
	dc.b	$02,$02,$03,$00,$08,$00,$01,$00,$14,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$01,$00,$00,$00,$00,$02,$25,$00,$0b,$02,$03,$00,$07,$00,$01,$00
	dc.b	$0f,$ff,$ff,$ff,$ff,$00,$1a,$00,$01,$00,$00,$00,$00,$02,$2b,$00
	dc.b	$02,$07,$04,$00,$10,$00,$01,$00,$00,$00,$18,$00,$16,$00,$14,$00
	dc.b	$00,$00,$20,$00,$ff,$11,$43,$00,$18,$03,$0b,$00,$13,$04,$07,$00
	dc.b	$15,$ff,$ff,$ff,$ff,$00,$1a,$00,$25,$00,$00,$00,$00,$02,$71,$01
	dc.b	$0a,$00,$06,$00,$07,$00,$01,$00,$16,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$05,$00,$00,$00,$00,$02,$6c,$07,$01,$00,$06,$00,$07,$00,$01,$00
	dc.b	$19,$ff,$ff,$ff,$ff,$00,$1a,$00,$01,$00,$00,$00,$00,$02,$3f,$00
	dc.b	$01,$04,$02,$00,$08,$00,$01,$00,$1a,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$01,$00,$00,$00,$00,$02,$47,$00,$0a,$04,$02,$00,$08,$00,$01,$00
	dc.b	$1b,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$05,$4c,$00
	dc.b	$02,$05,$00,$00,$0f,$00,$01,$00,$1c,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$01,$00,$00,$00,$00,$02,$5b,$00,$01,$01,$04,$00,$08,$00,$01,$00
	dc.b	$17,$ff,$ff,$ff,$ff,$00,$1a,$00,$01,$00,$00,$00,$00,$02,$64,$00
	dc.b	$0a,$01,$04,$00,$08,$00,$01,$ff,$ff,$00,$01,$00,$02,$00,$14,$00
	dc.b	$00,$00,$10,$00,$02,$11,$52,$00,$00,$00,$00,$00,$3d,$00,$14,$00
	dc.b	$03,$ff,$ff,$ff,$ff,$00,$16,$00,$00,$00,$30,$00,$00,$05,$68,$00
	dc.b	$0b,$04,$01,$00,$27,$07,$02,$00,$00,$ff,$ff,$ff,$ff,$00,$1a,$00
	dc.b	$27,$00,$00,$00,$00,$03,$6d,$07,$10,$06,$11,$00,$1c,$00,$01,$00
	dc.b	$02,$00,$04,$00,$11,$00,$14,$00,$00,$00,$20,$00,$02,$11,$00,$00
	dc.b	$06,$03,$05,$00,$31,$00,$0b,$00,$05,$ff,$ff,$ff,$ff,$00,$15,$00
	dc.b	$00,$00,$00,$00,$00,$05,$84,$04,$0c,$01,$02,$00,$19,$00,$01,$00
	dc.b	$06,$ff,$ff,$ff,$ff,$00,$15,$00,$00,$00,$00,$00,$00,$05,$a0,$00
	dc.b	$06,$07,$00,$00,$25,$00,$01,$00,$07,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$02,$cf,$01,$05,$06,$03,$00,$17,$00,$01,$00
	dc.b	$08,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$02,$e7,$00
	dc.b	$05,$03,$05,$00,$0c,$00,$01,$00,$09,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$02,$f4,$00,$05,$03,$06,$00,$10,$00,$01,$00
	dc.b	$0a,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$03,$01,$00
	dc.b	$05,$03,$07,$00,$12,$00,$01,$00,$0b,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$03,$14,$00,$05,$03,$08,$00,$0f,$00,$01,$00
	dc.b	$0c,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$03,$24,$00
	dc.b	$05,$03,$09,$00,$09,$00,$01,$00,$0d,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$03,$2e,$00,$18,$05,$05,$00,$06,$00,$01,$00
	dc.b	$0e,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$03,$31,$00
	dc.b	$1f,$03,$06,$00,$10,$00,$01,$00,$0f,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$03,$42,$00,$1f,$03,$07,$00,$0d,$00,$01,$00
	dc.b	$10,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$03,$50,$00
	dc.b	$1f,$03,$08,$00,$08,$00,$01,$00,$11,$ff,$ff,$ff,$ff,$00,$1c,$00
	dc.b	$00,$00,$00,$00,$00,$03,$59,$00,$1f,$03,$09,$00,$09,$00,$01,$00
	dc.b	$03,$ff,$ff,$ff,$ff,$00,$1c,$00,$00,$00,$00,$00,$00,$03,$63,$00
	dc.b	$1f,$03,$05,$00,$09,$00,$01,$00,$00,$0a,$fc,$00,$00,$09,$c4,$00
	dc.b	$00,$07,$54,$00,$00,$07,$e4,$00,$00,$0d,$b4,$00,$00,$05,$bc
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
iob:	; from: exit
	dc.w	$0000,$0000,$0000,$0000,$0000,$0209,$0000,$0000 ; the 20 streams, 16 bytes each: stdin, stdout,
                                                ;   stderr...
	dc.w	$0000,$0000,$0000,$0000,$0000,$0102,$0001,$0200
	dc.w	$0000,$0000,$0000,$0000,$0000,$0102,$0001,$0200
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	256,0
bufsiz:
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
last_vdi_handle:	; from: v_opnvwk
	dc.w	$ffff                           ; the workstation v_opnvwk opened last

	section	bss
startup_stack:	ds.b	100                     ; a desk accessory's stack at the start
dial_box_h:	ds.b	2                       ; the box form_dial(FMD_GROW) kept
dial_box_w:	ds.b	2
dial_box_x:	ds.b	2
dial_box_y:	ds.b	2
atexit_table:	ds.b	32                      ; up to 8 functions
malloc_base:	ds.b	8                       ; malloc's empty list head: pointer and size
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
bar_address:	ds.b	4                       ; LZH: where the next line of the bar is drawn
tree_disk:	ds.b	4                       ; the disk progress box
disk_rect:	ds.b	8
bar_lines:	ds.b	2                       ; LZH: the lines of the bar drawn
rson:	ds.b	16386                           ; LZH: right children, and the 256 tree roots past N
dpk_name:	ds.b	16                      ; the name in the file selector for the disk packer
bar_offset:	ds.b	2                       ; the packometer bar's distance from the bottom of the screen
codesize:	ds.b	4                       ; LZH: the code written so far
text_buf:	ds.b	4156                    ; LZH: the 4 K window and 59 bytes more
multi_programs:	ds.b	2                       ; Programs (the multi packer packs programs)
envp:	ds.b	4
match_position:	ds.b	2
freq:	ds.b	1256                            ; LZH: each node's frequency
dir_entries:	ds.b	2                       ; the disk's root directory entries
dad:	ds.b	8194                            ; LZH: each node's parent in the string tree
jpk_magic:	ds.b	4                       ; the JPK file's magic, read
ap_id:	ds.b	2
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
bar_line_bytes:	ds.b	4                       ; LZH: bytes a screen line
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
chunk_length:	ds.b	4                       ; a JPK chunk's length
disk_spt:	ds.b	2                       ; sectors a track
resolution:	ds.b	2
basepage:	ds.b	4
lson:	ds.b	8194                            ; LZH: left children
screen_width:	ds.b	2
fat_count:	ds.b	2
screen:	ds.b	4
packpower_rect:	ds.b	8
tree_packpower:	ds.b	4                       ; the PackPower box
textsize:	ds.b	4                       ; LZH: the bytes read
vdi_intout:	ds.b	256
aes_global:	ds.b	32
aes_control:	ds.b	10
tree_about:	ds.b	4
cluster_count:	ds.b	2
program_flag:	ds.b	2                       ; the Program button: 1 for a program
desktop_rect:	ds.b	8
heading_flag:	ds.b	2                       ; Heading
tree_desktop:	ds.b	4
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
