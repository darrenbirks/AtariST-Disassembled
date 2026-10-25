; Batman The Movie (Ocean, 1989) - file version for 2 MB
;
; Disassembled by Darren Birks in the evil month of October 2026.
;
; Not an official release: an example of a file loader, made by Darren Birks.  A TOS
; program that runs the 1 disk retail reissue from its unpacked files, on an ST with
; 2 MB or more.  The 24 files (retail_1disk_speedlock\unpacked: title.pic, panel.gfx,
; ... level5.map) lie in the folder files beside batman.prg, on any drive: a floppy
; with room for them, a hard disk or an emulator's GEMDOS drive.
;
;======================================================================
; How the original disk loads
;======================================================================
;
; The SpeedLock boot reads track 0 sectors 2-9, decrypts them to $21000 and jumps there.
; That is loader.bin: a $4c byte copy stub (loadstub.s) that copies the loader to $1000,
; puts a jump table at $200 and enters loader_start, and the loader itself (loader.s),
; which stays at $1000-$1fff for the whole game.  Each loader section loads the files of
; a scene from the load table and jumps to the game.
;
; A load table entry is 5 longs, which a section fetches with movem.l into d0-d4 and
; passes to load_file ($150e): d0 the track, d1 the offset in it, d2 the length on the
; disk, d3 the length to decrypt, d4 the destination.  load_file reads the game tracks
; with READ TRACK, undoes their escaping, decrypts the file to the destination and
; leaves the destination and length in file_vars ($16d6: +8 length, +$c destination).
; The section then calls unpack_file ($12c6), which unpacks the FORM HUFF file in place
; and clears the 31 bytes after it, and for a picture show_picture, which decodes it.
;
;======================================================================
; What this program changes
;======================================================================
;
; The game overwrites TOS's memory, so GEMDOS cannot load files while it runs.  This
; version loads them all before the game starts, into the second megabyte, which the
; game never uses (levels 2 and 4 use $80000-$e9491 when they find more than 512K):
;
;   1. batman.prg fades the screen to black with its text in white.  It takes the
;      largest free block of memory from GEMDOS and checks that it covers FILES_AT
;      ($100000): on a 2 MB ST the screen is at $1f8000, and the files end at about
;      $1be202.
;   2. It loads the 24 unpacked files one after another from FILES_AT on with GEMDOS
;      (Fopen, Fread, Fclose), a dot for each, then waits for a key and fades the text
;      out.
;   3. A copy of loader.bin (incbin'd below) gets these changes, all inside the loader:
;        - The load table: each 20 byte entry gets four new longs: 1) the file's
;          address in the second megabyte, 2) its destination (the entry's own fifth
;          long, which the loader keeps using), 3) its length and 4) a delay loop
;          count.
;        - load_file ($150e) becomes load_copy: wait out the delay, then copy the file
;          to its destination.
;        - unpack_file ($12c6) becomes unpack_clear: the files are not packed, so it only
;          clears the 31 bytes after the file, as the reissue's unpack_file does.
;   4. The loader goes to $21000 and runs as after the SpeedLock boot.
;
; The delay (DELAY, about 2.4 s at 8 MHz) is on the file loaded right after each
; picture, so the picture can be seen before the rest of the section loads, as it was
; while the original disk loaded.
;
; Assemble with Devpac, or vasmm68k_mot -devpac -m68000 -Ftos -o batman.prg batman.s.

	opt	o-

LOADER_RUN	equ	$1000			; where the game loader runs (loader.s)
STUB_AT		equ	$21000			; where loader.bin's copy stub runs (loadstub.s)
STUB_LEN	equ	$4c			; the copy stub in front of the loader code
LOADER_SIZE	equ	$1000			; loader.bin, stub and loader code
IMAGE		equ	STUB_LEN-LOADER_RUN	; loader address + IMAGE = offset in loader.bin

unpack_file	equ	$12c6			; loader.s: the FORM HUFF unpacker, replaced
find_chunk	equ	$133e			; loader.s: the routine after it
load_file	equ	$150e			; loader.s: the track loader, replaced
fdc_regs	equ	$160e			; loader.s: the first routine kept after it
file_vars	equ	$16d6			; loader.s: +8 length, +$c destination
load_table	equ	$16e8			; loader.s: 26 entries of 20 bytes
ENTRIES		equ	26
FILES		equ	24			; level24.bin and level24.gfx serve two entries

FILES_AT	equ	$100000			; the files, in the second megabyte
LAUNCH_AT	equ	$70000			; the loader image and the launcher, once
DELAY		equ	$100000			; about 2.4 s at 8 MHz (subq.l, bne: 18 cycles)
FADE_FRAMES	equ	3			; VBLs per fade step

palette		equ	$ffff8240

	section	text

;----------------------------------------------------------------------
; Start: keep only the program's own memory, go to supervisor mode (for the palette
; and later the hardware) and keep the desktop's colours.
;----------------------------------------------------------------------
start:
	movea.l	4(sp),a5			; basepage
	lea	stack_top,sp			; our own stack, in the BSS
	move.l	$c(a5),d0			; text, data and bss lengths and the basepage
	add.l	$14(a5),d0
	add.l	$1c(a5),d0
	addi.l	#$100,d0
	move.l	d0,-(sp)			; Mshrink(0, basepage, length)
	move.l	a5,-(sp)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1
	lea	12(sp),sp

	clr.l	-(sp)				; Super(0): supervisor mode, keep the old stack
	move.w	#$20,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,old_ssp

	lea	palette.w,a0			; keep the desktop's colours for an error exit
	lea	saved_palette,a1
	moveq	#7,d0				; 16 colours, 2 a long
save_palette_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,save_palette_loop

;----------------------------------------------------------------------
; The text, white on a screen that fades from white to black.  Colour 0 is the
; background, colours 1-15 the text (in any resolution).
;----------------------------------------------------------------------
	move.w	#$777,d0			; background white, as the desktop leaves it
	move.w	d0,d1				; and the text white too, so it cannot be seen
	bsr.w	set_colours
	lea	title_text(pc),a0		; clear the screen and print the text
	bsr.w	print
	move.w	#$777,d1			; the text stays white
fade_in_loop:
	subi.w	#$111,d0			; the background one step darker
	bsr.w	set_colours
	bsr.w	wait_frames
	tst.w	d0				; until it is black
	bne.s	fade_in_loop

	lea	program_end,a0			; the program must lie below the loader image
	cmpa.l	#LAUNCH_AT,a0			; that goes to LAUNCH_AT at the end
	bcc.w	no_room

;----------------------------------------------------------------------
; The memory for the files: the largest free block, which must cover FILES_AT.
;----------------------------------------------------------------------
	moveq	#-1,d0				; Malloc(-1): the largest free block's size
	bsr.w	malloc
	move.l	d0,d7
	bsr.w	malloc				; Malloc(that): the block
	tst.l	d0
	ble.w	no_memory
	cmpi.l	#FILES_AT,d0			; it must start at FILES_AT or below
	bhi.w	no_memory
	add.l	d0,d7				; and end above it
	cmpi.l	#FILES_AT,d7
	bls.w	no_memory
	move.l	d7,files_end

;----------------------------------------------------------------------
; Load the files one after another from FILES_AT on; file_list gets each one's address
; and length.
;----------------------------------------------------------------------
	lea	file_list(pc),a4		; the files
	lea	FILES_AT,a3			; where the next one goes
	moveq	#FILES-1,d6
load_loop:
	clr.w	-(sp)				; Fopen(name, read)
	move.l	(a4),-(sp)
	move.w	#$3d,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi.w	file_missing
	move.w	d0,d5				; the handle
	move.l	a3,-(sp)			; Fread(handle, room left, a3)
	move.l	files_end,d0
	sub.l	a3,d0
	move.l	d0,-(sp)
	move.w	d5,-(sp)
	move.w	#$3f,-(sp)
	trap	#1
	lea	12(sp),sp
	move.l	d0,d4				; bytes read
	move.w	d5,-(sp)			; Fclose(handle)
	move.w	#$3e,-(sp)
	trap	#1
	addq.l	#4,sp
	tst.l	d4
	bmi.w	read_error
	move.l	a3,4(a4)			; the file's address
	move.l	d4,8(a4)			; and length
	adda.l	d4,a3				; the next file, at an even address
	addq.l	#1,a3
	move.l	a3,d0
	bclr	#0,d0
	movea.l	d0,a3
	cmpa.l	files_end,a3			; it filled the block: too little memory
	bcc.w	no_memory
	lea	dot_text(pc),a0			; a dot for each file
	bsr.w	print
	lea	12(a4),a4			; the next file
	dbra	d6,load_loop

	lea	key_text(pc),a0
	bsr.w	print
	move.w	#8,-(sp)			; Cnecin: wait for a key
	trap	#1
	addq.l	#2,sp

	moveq	#0,d0				; background black
	move.w	#$777,d1			; text white ...
fade_out_loop:
	subi.w	#$111,d1			; ... one step darker
	bsr.w	set_colours
	bsr.w	wait_frames
	tst.w	d1				; until it is black as well
	bne.s	fade_out_loop

;----------------------------------------------------------------------
; The loader image at LAUNCH_AT: the load table, load_file and unpack_file; then start
; the loader from a launcher after the image (the program itself may lie where the
; loader goes).  TOS is not needed any more.
;----------------------------------------------------------------------
	lea	loader_bin(pc),a0		; loader.bin to LAUNCH_AT
	lea	LAUNCH_AT,a3
	movea.l	a3,a1
	move.w	#LOADER_SIZE/4-1,d0
copy_loader_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,copy_loader_loop

	lea	load_table+IMAGE(a3),a2		; the load table in the image
	lea	entry_list(pc),a0		; which file and delay each entry gets
	moveq	#ENTRIES-1,d1
patch_entry_loop:
	move.w	(a0)+,d0			; file number
	mulu.w	#12,d0				; its file_list entry
	lea	file_list(pc),a1
	adda.w	d0,a1
	move.l	4(a1),(a2)			; 1) the file's address
	move.l	16(a2),4(a2)			; 2) its destination: the entry's own
	move.l	8(a1),8(a2)			; 3) its length
	clr.l	12(a2)				; 4) the delay: none,
	tst.w	(a0)+
	beq.s	patch_entry_next
	move.l	#DELAY,12(a2)			; or DELAY after a picture
patch_entry_next:
	lea	20(a2),a2			; the next entry
	dbra	d1,patch_entry_loop

	lea	load_copy(pc),a0		; load_file: load_copy
	lea	load_file+IMAGE(a3),a1
	move.w	#(load_copy_end-load_copy)/2-1,d0
copy_load_loop:
	move.w	(a0)+,(a1)+
	dbra	d0,copy_load_loop

	lea	unpack_clear(pc),a0		; unpack_file: unpack_clear
	lea	unpack_file+IMAGE(a3),a1
	move.w	#(unpack_clear_end-unpack_clear)/2-1,d0
copy_unpack_loop:
	move.w	(a0)+,(a1)+
	dbra	d0,copy_unpack_loop

	lea	launch(pc),a0			; the launcher after the image
	lea	LOADER_SIZE(a3),a1
	move.w	#(launch_end-launch)/2-1,d0
copy_launch_loop:
	move.w	(a0)+,(a1)+
	dbra	d0,copy_launch_loop
	movea.l	a3,a0				; the image, for the launcher
	jmp	LOADER_SIZE(a3)			; run the launcher

;----------------------------------------------------------------------
; Run after the loader image: copy it (a0) to $21000 and start its copy stub there,
; as the SpeedLock boot does.  Interrupts off, as there.
;----------------------------------------------------------------------
launch:
	move.w	#$2700,sr
	lea	STUB_AT,a1
	move.w	#LOADER_SIZE/4-1,d0
launch_copy_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,launch_copy_loop
	jmp	STUB_AT				; loadstub: the loader to $1000, then loader_start
launch_end:

;----------------------------------------------------------------------
; Startup helpers, while TOS runs.
;----------------------------------------------------------------------

; Colour 0 = d0 (the background), colours 1-15 = d1 (the text in any resolution).
set_colours:
	movem.l	d2/a0,-(sp)
	lea	palette.w,a0
	move.w	d0,(a0)+			; colour 0
	moveq	#14,d2				; colours 1-15
set_colours_loop:
	move.w	d1,(a0)+
	dbra	d2,set_colours_loop
	movem.l	(sp)+,d2/a0
	rts

; Wait FADE_FRAMES VBLs (XBIOS Vsync), the length of one fade step.
wait_frames:
	movem.l	d0-d3/a0-a2,-(sp)		; the XBIOS may change d0-d2/a0-a2
	moveq	#FADE_FRAMES-1,d3
wait_frames_loop:
	move.w	#37,-(sp)			; Vsync
	trap	#14
	addq.l	#2,sp
	dbra	d3,wait_frames_loop
	movem.l	(sp)+,d0-d3/a0-a2
	rts

; d0 = GEMDOS Malloc(d0).
malloc:
	movem.l	d1-d2/a0-a2,-(sp)		; GEMDOS may change d1-d2/a0-a2
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1
	addq.l	#6,sp
	movem.l	(sp)+,d1-d2/a0-a2
	rts

;----------------------------------------------------------------------
; Errors: say what went wrong in white, wait for a key, back to the desktop in its
; own colours.
;----------------------------------------------------------------------
no_room:
	lea	no_room_text(pc),a0
	bra.s	quit

no_memory:
	lea	no_memory_text(pc),a0
	bra.s	quit

read_error:
	lea	read_error_text(pc),a0
	bra.s	quit

file_missing:
	bsr.s	show_error
	lea	file_missing_text(pc),a0
	bsr.s	print
	movea.l	(a4),a0				; the name
	bsr.s	print
	lea	newline_text(pc),a0
quit:
	bsr.s	show_error			; white text on black
	bsr.s	print				; the message
	move.w	#8,-(sp)			; Cnecin: wait for a key
	trap	#1
	addq.l	#2,sp
	lea	saved_palette,a0		; the desktop's colours back
	lea	palette.w,a1
	moveq	#7,d0
restore_palette_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,restore_palette_loop
	move.l	old_ssp,-(sp)			; Super: back to user mode
	move.w	#$20,-(sp)
	trap	#1
	addq.l	#6,sp
	clr.w	-(sp)				; Pterm0
	trap	#1

; White text on black for an error.
show_error:
	movem.l	d0-d1,-(sp)
	moveq	#0,d0
	move.w	#$777,d1
	bsr.w	set_colours
	movem.l	(sp)+,d0-d1
	rts

; Print the text at a0 (GEMDOS Cconws).
print:
	movem.l	d0-d2/a0-a2,-(sp)		; GEMDOS may change d0-d2/a0-a2
	move.l	a0,-(sp)
	move.w	#9,-(sp)
	trap	#1
	addq.l	#6,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts

;======================================================================
; Copied over load_file ($150e).  Position independent; it runs with the game, without
; TOS.
;======================================================================

;----------------------------------------------------------------------
; Called with a load table entry in d0-d4: d0 the file's address in the second
; megabyte, d1 its destination, d2 its length, d3 the delay (d4 is the entry's own
; destination, unused here).  Sets file_vars as load_file does for unpack_file and
; show_picture, waits, then copies the file.  Keeps all registers, as load_file did,
; and leaves interrupts off, as load_file did.
;----------------------------------------------------------------------
load_copy:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	#$2700,sr			; interrupts off, as load_file leaves them
	move.l	d1,file_vars+$c.w		; destination, for unpack_file and show_picture
	move.l	d2,file_vars+8.w		; length
	tst.l	d3				; a delay?
	beq.s	load_copy_start
load_copy_delay:
	subq.l	#1,d3
	bne.s	load_copy_delay
load_copy_start:
	movea.l	d0,a0				; from the second megabyte
	movea.l	d1,a1				; to the destination
	move.l	d2,d0				; length
	beq.s	load_copy_done
	subq.l	#1,d0
load_copy_loop:
	move.b	(a0)+,(a1)+
	dbra	d0,load_copy_loop
	subi.l	#$10000,d0			; dbra counts 64K at a time
	bpl.s	load_copy_loop
load_copy_done:
	movem.l	(sp)+,d0-d7/a0-a6
	rts
load_copy_end:

	ifgt	load_copy_end-load_copy-(fdc_regs-load_file)
	fail	load_copy does not fit over load_file
	endc

;======================================================================
; Copied over unpack_file ($12c6): the file is not packed, so only clear the 31 bytes
; after it, as the reissue's unpack_file does.  Position independent.
;======================================================================
unpack_clear:
	movem.l	d0/a0,-(sp)
	movea.l	file_vars+$c.w,a0		; the file's destination
	adda.l	file_vars+8.w,a0		; + its length
	moveq	#30,d0				; 31 bytes
unpack_clear_loop:
	clr.b	(a0)+
	dbra	d0,unpack_clear_loop
	movem.l	(sp)+,d0/a0
	rts
unpack_clear_end:

	ifgt	unpack_clear_end-unpack_clear-(find_chunk-unpack_file)
	fail	unpack_clear does not fit over unpack_file
	endc

;======================================================================
; Tables and texts.
;======================================================================

; The files, in load table order (level24.bin and level24.gfx once): name, then where
; the file was loaded and its length (filled in at startup).
file_list:
	dc.l	name_title_pic,0,0		;  0
	dc.l	name_panel_gfx,0,0		;  1
	dc.l	name_panel_bin,0,0		;  2
	dc.l	name_sound_prg,0,0		;  3
	dc.l	name_frontend_bin,0,0		;  4
	dc.l	name_frontend_gfx,0,0		;  5
	dc.l	name_level1_pic,0,0		;  6
	dc.l	name_level1_bin,0,0		;  7
	dc.l	name_level1a_gfx,0,0		;  8
	dc.l	name_level1b_gfx,0,0		;  9
	dc.l	name_level1_map,0,0		; 10
	dc.l	name_level2_pic,0,0		; 11
	dc.l	name_level24_bin,0,0		; 12
	dc.l	name_level24_gfx,0,0		; 13
	dc.l	name_level2_gfx,0,0		; 14
	dc.l	name_level3_pic,0,0		; 15
	dc.l	name_level3_bin,0,0		; 16
	dc.l	name_level4_pic,0,0		; 17
	dc.l	name_level4_gfx,0,0		; 18
	dc.l	name_level5_pic,0,0		; 19
	dc.l	name_level5_bin,0,0		; 20
	dc.l	name_level5a_gfx,0,0		; 21
	dc.l	name_level5b_gfx,0,0		; 22
	dc.l	name_level5_map,0,0		; 23

; The 26 load table entries: file number in file_list, delay (1 = after a picture).
entry_list:
	dc.w	0,0				;  0 title.pic
	dc.w	1,1				;  1 panel.gfx, after the title picture
	dc.w	2,0				;  2 panel.bin
	dc.w	3,0				;  3 sound.prg
	dc.w	4,0				;  4 frontend.bin
	dc.w	5,0				;  5 frontend.gfx
	dc.w	6,0				;  6 level1.pic
	dc.w	7,1				;  7 level1.bin, after the level 1 picture
	dc.w	8,0				;  8 level1a.gfx
	dc.w	9,0				;  9 level1b.gfx
	dc.w	10,0				; 10 level1.map
	dc.w	11,0				; 11 level2.pic
	dc.w	12,1				; 12 level24.bin, after the level 2 picture
	dc.w	13,0				; 13 level24.gfx
	dc.w	14,0				; 14 level2.gfx
	dc.w	15,0				; 15 level3.pic
	dc.w	16,1				; 16 level3.bin, after the level 3 picture
	dc.w	17,0				; 17 level4.pic
	dc.w	12,1				; 18 level24.bin, after the level 4 picture
	dc.w	13,0				; 19 level24.gfx
	dc.w	18,0				; 20 level4.gfx
	dc.w	19,0				; 21 level5.pic
	dc.w	20,1				; 22 level5.bin, after the level 5 picture
	dc.w	21,0				; 23 level5a.gfx
	dc.w	22,0				; 24 level5b.gfx
	dc.w	23,0				; 25 level5.map

; The file names: the folder files beside batman.prg.
name_title_pic:		dc.b	'FILES\TITLE.PIC',0
name_panel_gfx:		dc.b	'FILES\PANEL.GFX',0
name_panel_bin:		dc.b	'FILES\PANEL.BIN',0
name_sound_prg:		dc.b	'FILES\SOUND.PRG',0
name_frontend_bin:	dc.b	'FILES\FRONTEND.BIN',0
name_frontend_gfx:	dc.b	'FILES\FRONTEND.GFX',0
name_level1_pic:	dc.b	'FILES\LEVEL1.PIC',0
name_level1_bin:	dc.b	'FILES\LEVEL1.BIN',0
name_level1a_gfx:	dc.b	'FILES\LEVEL1A.GFX',0
name_level1b_gfx:	dc.b	'FILES\LEVEL1B.GFX',0
name_level1_map:	dc.b	'FILES\LEVEL1.MAP',0
name_level2_pic:	dc.b	'FILES\LEVEL2.PIC',0
name_level24_bin:	dc.b	'FILES\LEVEL24.BIN',0
name_level24_gfx:	dc.b	'FILES\LEVEL24.GFX',0
name_level2_gfx:	dc.b	'FILES\LEVEL2.GFX',0
name_level3_pic:	dc.b	'FILES\LEVEL3.PIC',0
name_level3_bin:	dc.b	'FILES\LEVEL3.BIN',0
name_level4_pic:	dc.b	'FILES\LEVEL4.PIC',0
name_level4_gfx:	dc.b	'FILES\LEVEL4.GFX',0
name_level5_pic:	dc.b	'FILES\LEVEL5.PIC',0
name_level5_bin:	dc.b	'FILES\LEVEL5.BIN',0
name_level5a_gfx:	dc.b	'FILES\LEVEL5A.GFX',0
name_level5b_gfx:	dc.b	'FILES\LEVEL5B.GFX',0
name_level5_map:	dc.b	'FILES\LEVEL5.MAP',0

; Lines of at most 40 characters, for the low resolution screen.
title_text:
	dc.b	27,'E',27,'f'			; clear the screen, no cursor
	dc.b	'Batman The Movie (Ocean, 1989)',13,10
	dc.b	'File version of the 1 disk reissue',13,10
	dc.b	'by Darren Birks, October 2026',13,10,13,10
	dc.b	'Loads the game files into the second',13,10
	dc.b	'megabyte (2 MB or more).',13,10,13,10
	dc.b	'Loading',0
dot_text:
	dc.b	'.',0
key_text:
	dc.b	13,10,13,10,'Press a key to start.',0
no_room_text:
	dc.b	13,10,'The program lies too high in memory.',13,10,0
no_memory_text:
	dc.b	13,10,'Not enough memory: the files go to',13,10
	dc.b	'the second megabyte, so this needs an',13,10
	dc.b	'ST with 2 MB or more.',13,10,0
read_error_text:
	dc.b	13,10,'Cannot read a game file.',13,10,0
file_missing_text:
	dc.b	13,10,'Not found:',13,10,0
newline_text:
	dc.b	13,10,0
	even

; The reissue's decrypted game loader: the copy stub for $21000, then the loader for $1000.
loader_bin:
	incbin	"loader.bin"

	section	bss

old_ssp:	ds.l	1			; TOS's supervisor stack, for the error exit
saved_palette:	ds.w	16			; the desktop's colours
files_end:	ds.l	1			; the end of the memory for the files
		ds.b	1024			; stack
stack_top:
program_end:
