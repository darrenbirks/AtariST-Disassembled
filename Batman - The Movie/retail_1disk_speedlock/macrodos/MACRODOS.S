;======================================================================
; MACRODOS.S - Batman The Movie (Ocean, 1989), 1 disk retail reissue:
; write the MacroDOS game tracks 2-79 with the WD1772's Write Track.
;
; Copyright (c) Darren Birks, November 2026
;
; Assembles with Devpac or vasm (vasmm68k_mot -devpac -Ftos).  Runs on a
; 512 KB ST.  Run it from the root of a disk that has the packed game files
; (retail_1disk_speedlock\packed) in \FILES.  It loads them, then asks for
; the destination disk and writes tracks 2-79 of drive A, side 0, one track
; at a time: build, Write Track, Read Track, compare.  A track that does
; not read back the same is written again, up to 3 times, then the program
; goes on to the next one.  Tracks 0 and 1 (the SpeedLock boot) are never
; touched; they must already be on the destination disk.  When it is done
; a key reboots the ST, which boots the game from the new disk.
;
; The files take about 452 KB, more than a 512 KB ST has free, so they
; are always loaded in two parts, into FILES_MEMORY bytes, whatever the
; RAM: as many as fit, then the tracks they fill are written, then it asks
; for the disk with \FILES again, loads the rest and asks for the
; destination disk again.  The file that runs on into the next track is
; loaded again with the rest; the stream carries on from where it was.
; Run from a hard drive (\FILES on drive C or later), there are no swaps:
; the destination disk is asked for once and stays in drive A.
;
; What it proves: the game's MacroDOS tracks can be made with the WD1772's
; own Write Track ($f0), byte for byte as on the original disk.
;
; The game tracks (see loader.s): no sectors, one block of data a track.
; Write Track is given, as the mastering tool in loader.s built it
; (tool_write_next_track):
;
;   40 x $4e  12 x $00  $f5 $f5 $f5  $0f <track> $0f  <$1800 data bytes>
;   $00 <checksum word> $00  257 x $4e
;
; The FDC writes each $f5 as an $a1 sync with a missing clock, so Read
; Track gives back  ... $00 $c2 $a1 $a1 $0f <track> $0f <data> ...  (the
; first sync usually reads as $c2).  The write stops at the next index
; pulse, cutting the last gap short; the data and checksum are well inside
; one turn of the disk (about 6250 bytes).
;
; The data of tracks 2-79 is one stream of $1800 bytes a track: the game's
; files one after the other, at the track and offset the 1 disk reissue's
; load table (loader.s, RETAIL_1DISK load_table) gives each, with $07 in
; the bytes between them and after the last one.  The packed files are as
; the loader leaves them before unpacking, so this program does what the
; loader undoes, in the other order:
;
; 1. Encrypt.  The loader decrypts each file with DECRYPT_KEY0/1, two
;    passes over its first "length to decrypt" bytes, a long at a time:
;    long ^ k0, swap, ^ k1, then k0 += k1.  encrypt_file does each pass
;    backwards (long ^ k1, swap, ^ k0), over one long more than the loader
;    when the length is not a multiple of 4, as the packed files were made
;    that way (the loader never looks at those 4 bytes).
;
; 2. Escape.  Two kinds of byte cannot go on the track as they are:
;    - $f5, $f6 and $f7, which Write Track turns into syncs and CRCs, and
;      $0f, the escape byte itself;
;    - a byte that would put the data bits %000101001 on the disk ending in
;      it.  In MFM those bits hold the pattern of a $c2 sync one cell out of
;      step, and the FDC would lock onto it while reading the track: the
;      bytes after it would come back shifted.  The bits looked at are those
;      of the byte written before, this byte, and the next byte of the file.
;    Such a byte x is written as $0f, ~x; the loader turns $0f, y back into
;    ~y.  The escaped file is the "length on disc" of the load table.
;
; The only bytes of tracks 2-79 not made from the packed files are 8 bytes
; the mastering tool left after frontend.bin (frontend_tail): they are on
; the original disk, outside the length the load table gives the file.
;
; Every step is logged on the screen, 40 columns, for low resolution.
;======================================================================

;----------------------------------------------------------------------
; Constants
;----------------------------------------------------------------------

FIRST_TRACK	equ	2		; the first game track
LAST_TRACK	equ	79		; and the last
TRACK_BYTES	equ	$1800		; data bytes on a game track (6144)
FILE_COUNT	equ	26		; entries in the load table
ENTRY_BYTES	equ	20		; bytes of a load table entry
TRIES		equ	3		; writes of a track before going on
FILES_MEMORY	equ	$50000		; memory for the files: fits in 512 KB

FILL_BYTE	equ	$07		; the bytes between the files
ESCAPE_BYTE	equ	$0f		; escape: $0f, ~x stands for x
TRACK_SYNC	equ	$a1		; the sync bytes, as Read Track gives them
SYNC_WRITE	equ	$f5		; and as Write Track is given them
GAP_BYTE	equ	$4e		; the gaps
SYNC_BITS	equ	%000101001	; data bits a $c2 sync out of step needs
SYNC_BITS_MASK	equ	%111111111	; 9 bits

CHECKSUM_SET	equ	$4992		; a track checksum is (sum | CHECKSUM_SET)
CHECKSUM_MASK	equ	$7fbf		; & CHECKSUM_MASK (never $f5-$f7)
DECRYPT_KEY0	equ	$f4bd128c	; the loader's decryption keys
DECRYPT_KEY1	equ	$5716923a

IMAGE_DATA	equ	40+12+3+3	; where the data starts in the track image
IMAGE_BYTES	equ	IMAGE_DATA+TRACK_BYTES+4+257 ; the whole track image
WRITE_SECTORS	equ	14		; DMA count for Write Track (14 x 512 bytes)
READ_SECTORS	equ	22		; and for Read Track, as the loader uses
READ_BYTES	equ	READ_SECTORS*512
SYNC_SEARCH	equ	600		; the sync is looked for in this many bytes

; FDC commands (WD1772)
CMD_RESTORE	equ	$01		; Restore, 12 ms steps
CMD_SEEK	equ	$11		; Seek, 12 ms steps, no verify
CMD_READ_TRACK	equ	$e0		; Read Track
CMD_WRITE_TRACK	equ	$f0		; Write Track
CMD_FORCE_INT	equ	$d0		; Force Interrupt (stop)

; FDC status bits after a type III command
FDC_WRITE_PROTECT equ	6
FDC_LOST_DATA	equ	2
FDC_MOTOR_ON	equ	7

; system variables and hardware
PHYSTOP		equ	$42e		; the top of the RAM TOS found at power on
FLOCK		equ	$43e		; floppy lock: the VBL leaves the FDC alone
HZ200		equ	$4ba		; 200 Hz timer
MFP_GPIP	equ	$fffffa01	; MFP GPIP, bit 5 low = FDC interrupt
FDC_TIMEOUT	equ	3*200		; 3 seconds for an FDC command

; Line-A
LINEA_INIT	equ	$a000		; a0 = the Line-A variables
LINEA_SHOW_MOUSE equ	$a009		; show the mouse pointer
LINEA_HIDE_MOUSE equ	$a00a		; hide it
LINEA_INTIN	equ	8		; the variables' pointer to INTIN

;----------------------------------------------------------------------
; Start: own stack, give back the memory not needed, supervisor mode,
; low resolution, title.
;----------------------------------------------------------------------

	section	text

start:
	move.l	4(sp),a5			; the basepage
	move.l	$c(a5),d0			; text +
	add.l	$14(a5),d0			; data +
	add.l	$1c(a5),d0			; bss +
	add.l	#$100,d0			; the basepage itself
	lea	stack_top,sp			; our own stack, in the BSS
	move.l	d0,-(sp)
	move.l	a5,-(sp)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1				; Mshrink: keep just the program
	lea	12(sp),sp

	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1				; Super
	addq.l	#6,sp
	move.l	d0,old_ssp

	move.w	#4,-(sp)
	trap	#14				; Getrez
	addq.l	#2,sp
	move.w	d0,old_rez
	cmpi.w	#1,d0				; medium resolution: go to low
	bne.s	start_colours
	moveq	#0,d0
	bsr.w	set_rez

start_colours:
	; white paper, black text: colours 0 and 15 of the palette, and the
	; console's own colours (after Setscreen it still draws in colour 3,
	; medium resolution's black, which is yellow in low resolution)
	moveq	#0,d0
	move.w	#$777,d1
	bsr.w	set_colour
	move.w	d0,old_colour0
	moveq	#15,d0
	moveq	#0,d1
	bsr.w	set_colour
	move.w	d0,old_colour15

	; hide GEM's mouse pointer: drawn over the console's scrolling text,
	; it would put back stale screen where it was each time it moves
	dc.w	LINEA_INIT			; a0 = the Line-A variables
	move.l	a0,line_a
	dc.w	LINEA_HIDE_MOUSE

start_title:
	lea	title_text,a0
	bsr.w	print
	bsr.w	wait_key			; "Press a key to start."

	move.w	#$19,-(sp)
	trap	#1				; Dgetdrv: the drive we run from
	addq.l	#2,sp
	cmpi.w	#2,d0				; A or B: \FILES is on a floppy, to
	scs	files_on_floppy			; swap with the destination disk

	bsr.w	measure_files			; d0 = 0 when all are there
	tst.w	d0
	bne.w	quit_after_key

	clr.l	stream_pos			; the stream starts with file 0
	clr.w	cur_file
	sf	file_active
	clr.w	failed_count
	clr.w	written_count
	move.w	#FIRST_TRACK,pass_first_track
	bra.s	start_load

start_next_load:
	tst.b	files_on_floppy			; from a hard drive: no swaps, the
	beq.s	start_load			; destination disk stays in drive A
	lea	source_text,a0			; the disk with \FILES back in
	bsr.w	print
	bsr.w	wait_key

start_load:
	bsr.w	load_pass			; d0 = 0 when loaded
	tst.w	d0
	bne.w	quit_after_key
	tst.b	files_on_floppy			; from a hard drive, the destination
	bne.s	start_ask			; disk is asked for once only
	cmpi.w	#FIRST_TRACK,pass_first_track
	bne.s	start_write

start_ask:
	lea	insert_text,a0			; ask for the destination disk
	bsr.w	print
	lea	tracks_text,a0			; "Tracks 02-79 will be OVERWRITTEN."
	bsr.w	print
	move.w	pass_first_track,d0
	bsr.w	print_dec2
	moveq	#'-',d0
	bsr.w	print_char
	move.w	pass_last_track,d0		; the tracks of these files, or
	tst.b	files_on_floppy			; from a hard drive, all of them
	bne.s	start_ask_last
	moveq	#LAST_TRACK,d0
start_ask_last:
	bsr.w	print_dec2
	lea	overwrite_text,a0
	bsr.w	print
	bsr.w	wait_key
	cmpi.b	#'y',d0
	beq.s	start_write
	cmpi.b	#'Y',d0
	bne.w	quit

start_write:
	bsr.w	write_tracks
	tst.b	write_protected			; stopped
	bne.s	start_summary
	move.w	pass_last_track,d0		; more files to load?
	cmpi.w	#LAST_TRACK,d0
	bcc.s	start_summary
	addq.w	#1,d0
	move.w	d0,pass_first_track
	bra.w	start_next_load

start_summary:
	bsr.w	print_summary
	tst.b	write_protected			; nothing written: just quit
	bne.s	quit_after_key

	lea	reboot_text,a0			; "Press a key to reboot ..."
	bsr.w	print
	bsr.w	wait_key
	; Reboot through the reset vector: the long at address 4 is the ROM's
	; start address, as the 68000 reads it at power on.  The disk in drive
	; A is the one just written, so TOS boots Batman from it.
	movea.l	4.w,a0
	jmp	(a0)

quit_after_key:
	lea	key_text,a0
	bsr.w	print
	bsr.w	wait_key

quit:
	moveq	#0,d0				; the palette as it was
	move.w	old_colour0,d1
	bsr.w	set_colour
	moveq	#15,d0
	move.w	old_colour15,d1
	bsr.w	set_colour
	move.w	old_rez,d0			; back to the resolution we came in
	cmpi.w	#1,d0
	bne.s	quit_user
	bsr.w	set_rez
	lea	medium_colours_text,a0		; and the console's medium colours
	bsr.w	print
quit_user:
	movea.l	line_a,a0			; the mouse pointer back: INTIN[0]
	movea.l	LINEA_INTIN(a0),a1		; = 1 undoes just the one hide, as
	move.w	#1,(a1)				; GEM counts them
	dc.w	LINEA_SHOW_MOUSE
	move.l	old_ssp,-(sp)
	move.w	#$20,-(sp)
	trap	#1				; Super: back to user mode
	addq.l	#6,sp
	clr.w	-(sp)
	trap	#1				; Pterm0


;----------------------------------------------------------------------
; Setcolor(d0, d1): set palette colour d0 to d1; d0 = what it was.
;----------------------------------------------------------------------
set_colour:
	movem.l	d1-d2/a0-a2,-(sp)
	move.w	d1,-(sp)
	move.w	d0,-(sp)
	move.w	#7,-(sp)
	trap	#14				; Setcolor
	addq.l	#6,sp
	movem.l	(sp)+,d1-d2/a0-a2
	rts


;----------------------------------------------------------------------
; Setscreen(-1, -1, d0): change the resolution.
;----------------------------------------------------------------------
set_rez:
	move.w	d0,-(sp)
	move.l	#-1,-(sp)
	move.l	#-1,-(sp)
	move.w	#5,-(sp)
	trap	#14				; Setscreen
	lea	12(sp),sp
	rts


;======================================================================
; Loading the files
;======================================================================

;----------------------------------------------------------------------
; Find every file of the load table in \FILES, note its length, and take
; FILES_MEMORY bytes for them.  An entry at the same track and offset as
; an earlier one (the level 2/4 code and graphics, which the table lists
; twice) is the earlier one's file, and is not looked at.  d0 = 0 when all
; went well.
;----------------------------------------------------------------------
measure_files:
	movem.l	d1-d7/a0-a6,-(sp)
	lea	checking_text,a0
	bsr.w	print

	moveq	#0,d7				; d7 = file number
mf_file:
	move.w	d7,d0
	bsr.w	same_entry
	bpl.s	mf_step				; listed before
	bsr.w	open_file			; d0 = handle
	bmi.w	load_missing
	move.w	d0,d5
	bsr.w	file_length			; d4 = the length
	bsr.w	close_file
	lea	file_sizes,a1
	move.w	d7,d1
	lsl.w	#2,d1
	move.l	d4,0(a1,d1.w)
mf_step:
	addq.w	#1,d7
	cmpi.w	#FILE_COUNT,d7
	bcs.s	mf_file

	; "RAM $080000, free $05xxxx"
	move.l	#-1,-(sp)
	move.w	#$48,-(sp)
	trap	#1				; Malloc(-1): the largest free block
	addq.l	#6,sp
	move.l	d0,d5
	lea	memory_text,a0
	bsr.w	print
	move.l	PHYSTOP.w,d0			; the RAM TOS sees
	moveq	#6,d1
	bsr.w	print_dollar_hex
	lea	free_text,a0
	bsr.w	print
	move.l	d5,d0
	moveq	#6,d1
	bsr.w	print_dollar_hex
	bsr.w	print_crlf

	move.l	#FILES_MEMORY,-(sp)
	move.w	#$48,-(sp)
	trap	#1				; Malloc: the block for the files
	addq.l	#6,sp
	tst.l	d0
	beq.s	mf_no_memory
	move.l	d0,files_block
	lea	parts_text,a0			; "The files load in two parts."
	bsr.w	print
	moveq	#0,d0
	bra.w	load_exit

mf_no_memory:
	lea	no_memory_text,a0
	bra.w	load_fail


;----------------------------------------------------------------------
; Load and encrypt as many files as fit in the block, from the one under
; way in the stream (cur_file) on, and set pass_last_track to the last
; track they fill: the track before the first file left out starts, or
; LAST_TRACK when none is.  The file under way, if one is, is in the
; middle of being written out: its stream pointers are moved to its new
; copy.  d0 = 0 when all went well.
;----------------------------------------------------------------------
load_pass:
	movem.l	d1-d7/a0-a6,-(sp)
	lea	loading_text,a0
	bsr.w	print

	tst.b	file_active			; how far the file under way got
	beq.s	lp_start
	lea	file_buffers,a1
	move.w	cur_file,d1
	lsl.w	#2,d1
	move.l	src_ptr,d0
	sub.l	0(a1,d1.w),d0
	move.l	d0,src_offset

lp_start:
	movea.l	files_block,a5			; a5 = where the next file goes
	move.l	a5,d6				; d6 = the end of the block
	add.l	#FILES_MEMORY,d6
	move.w	cur_file,d7			; d7 = file number
lp_next:
	cmpi.w	#FILE_COUNT,d7
	bcc.w	lp_all
	move.w	d7,d0
	bsr.w	same_entry			; listed before: the stream
	bpl.w	lp_step				; skips it
	lea	file_sizes,a1			; d4 = its length, measured
	move.w	d7,d1
	lsl.w	#2,d1
	move.l	0(a1,d1.w),d4
	lea	8+1(a5,d4.l),a0			; room for it and 8 bytes?
	move.l	a0,d0
	andi.b	#$fe,d0
	cmp.l	d6,d0
	bhi.w	lp_full

	bsr.w	print_file_number		; "00 TITLE.PIC    "
	bsr.w	open_file
	bmi.w	load_missing
	move.w	d0,d5				; d5 = handle
	pea	(a5)
	move.l	d4,-(sp)
	move.w	d5,-(sp)
	move.w	#$3f,-(sp)
	trap	#1				; Fread
	lea	12(sp),sp
	move.l	d0,d3				; bytes read
	bsr.w	close_file
	cmp.l	d4,d3
	bne.w	load_missing

	; the file must reach past the bytes the encryption covers
	bsr.w	table_entry			; a1 = the load table entry
	move.l	12(a1),d0			; length to decrypt
	addq.l	#4,d0
	cmp.l	d4,d0
	bhi.w	load_too_short

	lea	file_buffers,a1
	move.w	d7,d1
	lsl.w	#2,d1
	move.l	a5,0(a1,d1.w)

	lea	0(a5,d4.l),a0			; 8 zero bytes after it (a byte at
	moveq	#8-1,d0				; a time: the length may be odd)
lp_zero:
	clr.b	(a0)+
	dbra	d0,lp_zero

	move.l	d4,d0				; "$04839 enc $04826"
	moveq	#5,d1
	bsr.w	print_dollar_hex
	lea	encrypt_text,a0
	bsr.w	print
	bsr.w	table_entry
	move.l	12(a1),d0
	moveq	#5,d1
	bsr.w	print_dollar_hex
	bsr.w	print_crlf

	movea.l	a5,a0				; encrypt it where it is
	move.l	12(a1),d0
	bsr.w	encrypt_file

	tst.b	file_active			; the file under way: its place
	beq.s	lp_placed			; in the new copy
	cmp.w	cur_file,d7
	bne.s	lp_placed
	move.l	a5,d0
	add.l	src_offset,d0
	move.l	d0,src_ptr
	lea	0(a5,d4.l),a0
	move.l	a0,src_end
lp_placed:
	adda.l	d4,a5				; the next file's place
	lea	8+1(a5),a5
	move.l	a5,d0
	andi.b	#$fe,d0
	movea.l	d0,a5

lp_step:
	addq.w	#1,d7
	bra.w	lp_next

lp_all:
	move.w	#LAST_TRACK,pass_last_track
	lea	loaded_text,a0			; "All files loaded."
	cmpi.w	#FIRST_TRACK,pass_first_track
	beq.s	lp_said
	lea	rest_loaded_text,a0
	bra.s	lp_said

lp_full:
	; file d7 does not fit: the tracks before the one it starts in
	bsr.w	table_entry
	move.l	(a1),d0
	subq.w	#1,d0
	cmp.w	pass_first_track,d0
	blt.w	mf_no_memory			; not even one track
	move.w	d0,pass_last_track
	lea	full_text,a0			; "Memory full: the rest loads later."
lp_said:
	bsr.w	print
	bsr.w	print_crlf
	moveq	#0,d0
load_exit:
	movem.l	(sp)+,d1-d7/a0-a6
	rts

load_missing:
	bsr.w	print_file_number		; "07 LEVEL1.BIN NOT FOUND"
	lea	missing_text,a0
	bra.s	load_fail
load_too_short:
	lea	short_text,a0
load_fail:
	bsr.w	print
	moveq	#1,d0
	bra.s	load_exit


;----------------------------------------------------------------------
; Open file d7 from \FILES (Fopen, read only): d0 = the handle, negative
; (flags set) when it is not there.
;----------------------------------------------------------------------
open_file:
	movem.l	d1-d2/a0-a2,-(sp)
	lea	path_buffer,a0			; \FILES\ and the name
	lea	files_dir,a1
of_copy_dir:
	move.b	(a1)+,(a0)+
	bne.s	of_copy_dir
	subq.l	#1,a0
	bsr.w	file_name			; a1 = the name
of_copy_name:
	move.b	(a1)+,(a0)+
	bne.s	of_copy_name
	clr.w	-(sp)
	pea	path_buffer
	move.w	#$3d,-(sp)
	trap	#1				; Fopen
	addq.l	#8,sp
	movem.l	(sp)+,d1-d2/a0-a2
	tst.l	d0
	rts


;----------------------------------------------------------------------
; d4 = the length of the file open as handle d5 (Fseek to its end and
; back).
;----------------------------------------------------------------------
file_length:
	movem.l	d0-d2/a0-a2,-(sp)
	move.w	#2,-(sp)			; from the end
	move.w	d5,-(sp)
	clr.l	-(sp)
	move.w	#$42,-(sp)
	trap	#1				; Fseek
	lea	10(sp),sp
	move.l	d0,d4
	clr.w	-(sp)				; and back to the start
	move.w	d5,-(sp)
	clr.l	-(sp)
	move.w	#$42,-(sp)
	trap	#1				; Fseek
	lea	10(sp),sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts


;----------------------------------------------------------------------
; Close handle d5 (Fclose).
;----------------------------------------------------------------------
close_file:
	movem.l	d0-d2/a0-a2,-(sp)
	move.w	d5,-(sp)
	move.w	#$3e,-(sp)
	trap	#1				; Fclose
	addq.l	#4,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts


;----------------------------------------------------------------------
; d0 = the earlier entry with the same start track and offset as entry
; d0, or -1 (flags set on d0).
;----------------------------------------------------------------------
same_entry:
	movem.l	d1-d3/a0-a1,-(sp)
	lea	load_table,a0
	move.w	d0,d1
	mulu.w	#ENTRY_BYTES,d1
	lea	0(a0,d1.l),a1			; a1 = entry d0
	moveq	#0,d2				; d2 = earlier entry
same_loop:
	cmp.w	d0,d2
	bcc.s	same_none
	move.l	(a0),d3
	cmp.l	(a1),d3				; start track
	bne.s	same_step
	move.l	4(a0),d3
	cmp.l	4(a1),d3			; offset into the track
	bne.s	same_step
	move.w	d2,d0
	bra.s	same_exit
same_step:
	lea	ENTRY_BYTES(a0),a0
	addq.w	#1,d2
	bra.s	same_loop
same_none:
	moveq	#-1,d0
same_exit:
	movem.l	(sp)+,d1-d3/a0-a1
	tst.w	d0
	rts


;----------------------------------------------------------------------
; a1 = the load table entry of file d7.
;----------------------------------------------------------------------
table_entry:
	move.l	d0,-(sp)
	lea	load_table,a1
	move.w	d7,d0
	mulu.w	#ENTRY_BYTES,d0
	adda.l	d0,a1
	move.l	(sp)+,d0
	rts


;----------------------------------------------------------------------
; a1 = the name of file d7.
;----------------------------------------------------------------------
file_name:
	move.w	d7,-(sp)
	lsl.w	#2,d7
	lea	file_names,a1
	movea.l	0(a1,d7.w),a1
	move.w	(sp)+,d7
	rts


;----------------------------------------------------------------------
; Print "nn NAME" for file d7, the name padded to 12 characters.
;----------------------------------------------------------------------
print_file_number:
	movem.l	d0-d1/a0-a1,-(sp)
	move.w	d7,d0
	bsr.w	print_dec2
	moveq	#' ',d0
	bsr.w	print_char
	bsr.s	file_name
	movea.l	a1,a0
	bsr.w	print
	moveq	#13,d1				; pad to 13 (name and a space)
pfn_length:
	tst.b	(a1)+
	beq.s	pfn_pad
	subq.w	#1,d1
	bra.s	pfn_length
pfn_pad:
	moveq	#' ',d0
	bsr.w	print_char
	subq.w	#1,d1
	bgt.s	pfn_pad
	movem.l	(sp)+,d0-d1/a0-a1
	rts


;----------------------------------------------------------------------
; Encrypt d0 + 4 bytes (rounded down to longs) at a0, a long at a time:
; the loader's decrypt (loader.s, decrypt_pass) done backwards.  The loader
; does per long  x ^ k0, swap, ^ k1  and k0 += k1, twice over the file;
; this does  x ^ k1, swap, ^ k0  with the same keys, twice.  It stops at
; a0 + d0 + 4; the loader at a0 + d0 + 1 (bcc), which is one long less when
; d0 is not a multiple of 4.
;----------------------------------------------------------------------
encrypt_file:
	movem.l	d0-d4/a0-a2,-(sp)
	lea	4(a0,d0.l),a1			; a1 = the end
	movea.l	a0,a2
	moveq	#1,d4				; two passes
encrypt_pass:
	movea.l	a2,a0
	move.l	#DECRYPT_KEY0,d0
	move.l	#DECRYPT_KEY1,d1
encrypt_loop:
	move.l	(a0),d2
	eor.l	d1,d2
	swap	d2
	eor.l	d0,d2
	move.l	d2,(a0)+
	add.l	d1,d0
	cmpa.l	a1,a0
	bcs.s	encrypt_loop
	dbra	d4,encrypt_pass
	movem.l	(sp)+,d0-d4/a0-a2
	rts


;======================================================================
; Writing the tracks
;======================================================================

;----------------------------------------------------------------------
; Write tracks pass_first_track to pass_last_track: for each, build its
; data, its track image, then write, read back and compare, up to TRIES
; times.  The FDC's track register says where TOS left the head; it goes
; back there at the end, so that TOS, which keeps its own note of the
; track, finds the tracks of the disk with \FILES when it is put back.
;----------------------------------------------------------------------
write_tracks:
	movem.l	d0-d7/a0-a6,-(sp)
	st	FLOCK.w				; keep the TOS floppy VBL away
	bsr.w	fdc_select
	bsr.w	fdc_track			; where TOS left the head
	move.w	d0,tos_track
	moveq	#CMD_RESTORE,d0			; head to track 0 (the tool's start)
	bsr.w	fdc_command

	move.w	pass_first_track,d7		; d7 = track
wt_track:
	lea	track_text,a0			; "Track 02"
	bsr.w	print
	move.w	d7,d0
	bsr.w	print_dec2
	bsr.w	print_crlf

	bsr.w	build_track_data		; the $1800 data bytes
	bsr.w	make_track_image		; and what Write Track is given
	lea	built_text,a0			; "  built, checksum $4F96"
	bsr.w	print
	move.w	track_checksum,d0
	moveq	#4,d1
	bsr.w	print_dollar_hex
	bsr.w	print_crlf

	moveq	#1,d6				; d6 = try
wt_try:
	move.w	d7,d5
	bsr.w	seek_track
	bsr.w	write_track			; d0 = FDC status, d1 = DMA status
	lea	write_text,a0			; "  write 1: fdc $00 dma $01"
	bsr.w	print_try
	bsr.w	print_status
	cmpi.w	#$ff,d0				; timed out: not a status
	beq.s	wt_read
	btst	#FDC_WRITE_PROTECT,d0
	bne.w	wt_protected
wt_read:

	bsr.w	read_track
	lea	verify_text,a0			; "  verify 1: ..."
	bsr.w	print_try
	bsr.w	verify_track
	tst.w	d0
	beq.s	wt_ok
	addq.w	#1,d6
	cmpi.w	#TRIES,d6
	bls.s	wt_try
	lea	give_up_text,a0			; three times bad: go on
	bsr.w	print
	lea	failed_tracks,a0
	move.w	failed_count,d0
	move.b	d7,0(a0,d0.w)
	addq.w	#1,failed_count
	bra.s	wt_next
wt_ok:
	addq.w	#1,written_count
wt_next:
	addq.w	#1,d7
	cmp.w	pass_last_track,d7
	bls.w	wt_track
	bra.s	wt_done

wt_protected:
	lea	protect_text,a0
	bsr.w	print
	st	write_protected
wt_done:
	move.w	tos_track,d5			; the head back for TOS
	bsr.w	seek_track
	bsr.w	drive_deselect
	sf	FLOCK.w
	movem.l	(sp)+,d0-d7/a0-a6
	rts


;----------------------------------------------------------------------
; Print the text at a0, the try number d6 and ": ".
;----------------------------------------------------------------------
print_try:
	move.l	d0,-(sp)
	bsr.w	print
	move.w	d6,d0
	addi.w	#'0',d0
	bsr.w	print_char
	lea	colon_text,a0
	bsr.w	print
	move.l	(sp)+,d0
	rts


;----------------------------------------------------------------------
; Print "fdc $xx dma $xx" for FDC status d0 and DMA status d1, and what
; the FDC status bits mean.
;----------------------------------------------------------------------
print_status:
	movem.l	d0-d2/a0,-(sp)
	move.w	d1,d2
	lea	fdc_text,a0
	bsr.w	print
	moveq	#2,d1
	bsr.w	print_dollar_hex
	lea	dma_text,a0
	bsr.w	print
	exg	d0,d2
	moveq	#2,d1
	bsr.w	print_dollar_hex
	exg	d0,d2
	cmpi.w	#$ff,d0
	bne.s	ps_bits
	lea	timeout_text,a0
	bsr.w	print
	bra.s	ps_exit
ps_bits:
	btst	#FDC_WRITE_PROTECT,d0
	beq.s	ps_lost
	lea	wp_text,a0
	bsr.w	print
ps_lost:
	btst	#FDC_LOST_DATA,d0
	beq.s	ps_exit
	lea	lost_text,a0
	bsr.w	print
ps_exit:
	bsr.w	print_crlf
	movem.l	(sp)+,d0-d2/a0
	rts


;----------------------------------------------------------------------
; Print what was written.
;----------------------------------------------------------------------
print_summary:
	movem.l	d0-d2/a0-a1,-(sp)
	lea	done_text,a0			; "Done. Tracks good: 78 failed: 0"
	bsr.w	print
	move.w	written_count,d0
	bsr.w	print_dec2
	lea	failed_text,a0
	bsr.w	print
	move.w	failed_count,d0
	bsr.w	print_dec2
	bsr.w	print_crlf
	tst.b	write_protected
	beq.s	sum_list
	lea	stopped_text,a0
	bsr.w	print
sum_list:
	move.w	failed_count,d2
	beq.s	sum_exit
	lea	failed_list_text,a0		; "Failed tracks: 12 34"
	bsr.w	print
	lea	failed_tracks,a1
	subq.w	#1,d2
sum_loop:
	moveq	#' ',d0
	bsr.w	print_char
	moveq	#0,d0
	move.b	(a1)+,d0
	bsr.w	print_dec2
	dbra	d2,sum_loop
	bsr.w	print_crlf
sum_exit:
	movem.l	(sp)+,d0-d2/a0-a1
	rts


;======================================================================
; Building a track
;======================================================================

;----------------------------------------------------------------------
; The $1800 data bytes of track d7 in track_data: $07, and the bytes of
; the stream of escaped files that fall in this track.  The stream runs on
; from the track before (cur_file, file_active and the escape state), so
; the tracks must be built in order.  A file's start is checked against
; the load table, and when it ends its escaped length is checked against
; the table's length on disc.  Once d4 and d5 hold the track's place in
; the stream, d7 holds the number of the file under way.
;----------------------------------------------------------------------
build_track_data:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	track_data,a0			; all $07 to start with
	move.w	#TRACK_BYTES-1,d0
btd_fill:
	move.b	#FILL_BYTE,(a0)+
	dbra	d0,btd_fill

	move.w	d7,d0				; d4 = the stream position where
	subq.w	#FIRST_TRACK,d0			;      this track starts
	mulu.w	#TRACK_BYTES,d0
	move.l	d0,d4
	move.l	d0,d5				; d5 = where it ends
	add.l	#TRACK_BYTES,d5
	lea	track_data,a4			; a4 = the data
	move.l	stream_pos,d6			; d6 = stream position

btd_loop:
	tst.b	file_active
	bne.w	btd_byte
	; no file under way: the next one, if it starts in this track
	move.w	cur_file,d0
	cmpi.w	#FILE_COUNT,d0
	bcc.w	btd_done			; all written
	bsr.w	same_entry			; listed twice: done already
	bmi.s	btd_new
	addq.w	#1,cur_file
	bra.s	btd_loop
btd_new:
	move.w	cur_file,d7
	bsr.w	table_entry
	move.l	(a1),d0				; its start in the stream
	subq.l	#FIRST_TRACK,d0
	mulu.w	#TRACK_BYTES,d0
	add.l	4(a1),d0
	cmp.l	d5,d0
	bcc.w	btd_done			; starts in a later track
	move.l	d0,d6
	move.l	d0,file_start
	lea	file_buffers,a2			; its packed, encrypted copy
	move.w	d7,d1
	lsl.w	#2,d1
	move.l	0(a2,d1.w),src_ptr
	movea.l	src_ptr,a3
	lea	file_sizes,a2
	adda.l	0(a2,d1.w),a3
	move.l	a3,src_end
	lea	file_tails,a2			; bytes after it, if any
	move.l	0(a2,d1.w),tail_ptr
	lea	file_tail_sizes,a2
	lsr.w	#1,d1
	move.w	0(a2,d1.w),tail_left
	clr.b	prev_byte
	sf	pending
	st	file_active
	lea	starts_text,a0			; "  TITLE.PIC starts at $0000"
	bsr.w	print_event
	move.l	d6,d0
	sub.l	d4,d0
	moveq	#4,d1
	bsr.w	print_dollar_hex
	bsr.w	print_crlf

btd_byte:
	cmp.l	d5,d6
	bcc.w	btd_done			; the track is full
	bsr.w	next_disk_byte			; d0 = byte, or -1 at the file's end
	tst.w	d0
	bmi.s	btd_file_end
	move.l	d6,d1
	sub.l	d4,d1
	move.b	d0,0(a4,d1.l)
	addq.l	#1,d6
	bra.s	btd_byte

btd_file_end:
	; the file is done: its length against the load table
	sf	file_active
	move.w	cur_file,d7
	bsr.w	table_entry
	lea	ends_text,a0			; "  TITLE.PIC ends $0283, $04A83 ok"
	bsr.w	print_event
	move.l	d6,d0
	sub.l	d4,d0
	moveq	#4,d1
	bsr.w	print_dollar_hex
	lea	comma_text,a0
	bsr.w	print
	move.l	d6,d0
	sub.l	file_start,d0
	lea	file_tail_sizes,a2		; less the tail bytes after it
	move.w	d7,d1
	add.w	d1,d1
	moveq	#0,d2
	move.w	0(a2,d1.w),d2
	sub.l	d2,d0
	moveq	#5,d1
	bsr.w	print_dollar_hex
	cmp.l	8(a1),d0			; the length on disc
	bne.s	btd_bad_length
	lea	ok_text,a0
	bra.s	btd_length_said
btd_bad_length:
	lea	bad_length_text,a0
btd_length_said:
	bsr.w	print
	bsr.w	print_crlf
	addq.w	#1,cur_file
	move.l	d6,stream_pos
	bra.w	btd_loop

btd_done:
	move.l	d6,stream_pos
	movem.l	(sp)+,d0-d7/a0-a6
	rts


;----------------------------------------------------------------------
; Print the text at a0 with the name of file cur_file in it: two spaces,
; the name, then the text.
;----------------------------------------------------------------------
print_event:
	movem.l	d0/d7/a0-a1,-(sp)
	move.l	a0,-(sp)
	moveq	#' ',d0
	bsr.w	print_char
	bsr.w	print_char
	move.w	cur_file,d7
	bsr.w	file_name
	movea.l	a1,a0
	bsr.w	print
	movea.l	(sp)+,a0
	bsr.w	print
	movem.l	(sp)+,d0/d7/a0-a1
	rts


;----------------------------------------------------------------------
; The next byte of the file under way as it goes on the disk, in d0.w, or
; -1 at its end.  A byte to escape gives $0f now and ~x next time
; (pending).  After the file's own bytes come its tail bytes, if any.
;
; The test for a byte x: the 24 data bits  prev x next  (prev = the byte
; written before it, next = the file's next byte, 0 after the last) must
; not hold SYNC_BITS ending in x: the 9 bits at shifts 7 to 14 from the
; bottom.  $0f and $f5-$f7 are always escaped.
;----------------------------------------------------------------------
next_disk_byte:
	movem.l	d1-d3/a0-a1,-(sp)
	tst.b	pending				; the second byte of an escape
	beq.s	ndb_next
	sf	pending
	moveq	#0,d0
	move.b	pending_byte,d0
	bra.w	ndb_exit

ndb_next:
	movea.l	src_ptr,a0
	movea.l	src_end,a1
	cmpa.l	a1,a0
	bcc.s	ndb_tail
	moveq	#0,d0
	move.b	(a0)+,d0			; d0 = x
	move.l	a0,src_ptr
	moveq	#0,d1				; d1 = the next byte, 0 at the end
	cmpa.l	a1,a0
	bcc.s	ndb_have_next
	move.b	(a0),d1
ndb_have_next:
	cmpi.b	#ESCAPE_BYTE,d0
	beq.s	ndb_escape
	cmpi.b	#$f5,d0
	bcs.s	ndb_bits
	cmpi.b	#$f7,d0
	bls.s	ndb_escape
ndb_bits:
	moveq	#0,d2				; d2 = prev x next
	move.b	prev_byte,d2
	lsl.l	#8,d2
	move.b	d0,d2
	lsl.l	#8,d2
	move.b	d1,d2
	lsr.l	#7,d2				; the 9 bits ending at bit 7 of x
	moveq	#7,d3				; 8 places
ndb_bits_loop:
	move.w	d2,d1
	andi.w	#SYNC_BITS_MASK,d1
	cmpi.w	#SYNC_BITS,d1
	beq.s	ndb_escape
	lsr.l	#1,d2
	dbra	d3,ndb_bits_loop
	move.b	d0,prev_byte			; as it is
	bra.s	ndb_exit

ndb_escape:
	not.b	d0				; $0f now, ~x next
	move.b	d0,pending_byte
	move.b	d0,prev_byte
	st	pending
	moveq	#ESCAPE_BYTE,d0
	bra.s	ndb_exit

ndb_tail:
	tst.w	tail_left
	beq.s	ndb_end
	subq.w	#1,tail_left
	movea.l	tail_ptr,a0
	moveq	#0,d0
	move.b	(a0)+,d0
	move.l	a0,tail_ptr
	bra.s	ndb_exit
ndb_end:
	moveq	#-1,d0
ndb_exit:
	movem.l	(sp)+,d1-d3/a0-a1
	rts


;----------------------------------------------------------------------
; The track image of track d7 in track_image, from track_data, with its
; checksum in track_checksum: the mastering tool's track (loader.s,
; tool_write_next_track), its code as it is apart from where it reads
; and writes.
;----------------------------------------------------------------------
make_track_image:
	movem.l	d0-d2/a0/a6,-(sp)
	lea	track_image,a6
	move.l	#$4e4e4e4e,d0			; gap
	moveq	#9,d1
mti_gap_loop:
	move.l	d0,(a6)+
	dbra	d1,mti_gap_loop
	moveq	#0,d0
	moveq	#2,d1
mti_zero_loop:
	move.l	d0,(a6)+
	dbra	d1,mti_zero_loop
	move.b	#SYNC_WRITE,d0			; three syncs
	moveq	#2,d1
mti_sync_loop:
	move.b	d0,(a6)+
	dbra	d1,mti_sync_loop
	move.b	#$f,(a6)+			; $0f track $0f
	move.b	d7,(a6)+
	move.b	#$f,(a6)+
	lea	track_data,a0
	moveq	#0,d2
	moveq	#0,d0
	move.w	#TRACK_BYTES-1,d1		; 6144 data bytes
mti_data_loop:
	move.b	(a0)+,d0
	add.w	d0,d2
	rol.w	#1,d2
	move.b	d0,(a6)+
	dbra	d1,mti_data_loop
	ori.w	#CHECKSUM_SET,d2		; the checksum load_file reads
	andi.w	#CHECKSUM_MASK,d2
	move.w	d2,track_checksum
	clr.b	(a6)+
	ror.l	#8,d2
	move.b	d2,(a6)+
	rol.l	#8,d2
	move.b	d2,(a6)+
	clr.b	(a6)+
	move.w	#$100,d1			; gap to the end of the track
mti_gap_end_loop:
	move.b	#GAP_BYTE,(a6)+
	dbra	d1,mti_gap_end_loop
	movem.l	(sp)+,d0-d2/a0/a6
	rts


;----------------------------------------------------------------------
; Compare what Read Track gave (read_buffer) with track d7's image, as the
; loader reads a track (loader.s, load_file): find the first $a1, skip the
; $a1s, the byte after them must be $0f, then the track number and $0f,
; then the data, $00 and the checksum.  Prints the result; d0 = 0 when
; it is the same.
;----------------------------------------------------------------------
verify_track:
	movem.l	d1-d4/a0-a2,-(sp)
	lea	read_buffer,a0
	lea	SYNC_SEARCH(a0),a1
vt_find_sync:
	cmpa.l	a1,a0
	bcc.w	vt_no_sync
	cmpi.b	#TRACK_SYNC,(a0)+
	bne.s	vt_find_sync
vt_skip_sync:
	cmpa.l	a1,a0
	bcc.w	vt_no_sync
	cmpi.b	#TRACK_SYNC,(a0)+
	beq.s	vt_skip_sync
	cmpi.b	#$0f,-1(a0)			; $0f <track> $0f
	bne.w	vt_bad_header
	cmp.b	(a0)+,d7
	bne.s	vt_bad_header
	cmpi.b	#$0f,(a0)+
	bne.s	vt_bad_header

	lea	track_image+IMAGE_DATA,a2	; data, $00, checksum, $00
	move.w	#TRACK_BYTES+4-1,d1
	moveq	#0,d4				; d4 = offset
vt_compare:
	cmpm.b	(a0)+,(a2)+
	bne.s	vt_differs
	addq.w	#1,d4
	dbra	d1,vt_compare
	lea	same_ok_text,a0			; "same, $1804 bytes"
	bsr.w	print
	moveq	#0,d0
	bra.s	vt_exit

vt_differs:
	moveq	#0,d2
	move.b	-1(a0),d2			; d2 = the byte read
	moveq	#0,d3
	move.b	-1(a2),d3			; d3 = the byte written
	lea	differs_text,a0			; "differs $0123: $12 not $34"
	bsr.w	print
	move.w	d4,d0
	moveq	#4,d1
	bsr.w	print_dollar_hex
	lea	got_text,a0
	bsr.w	print
	move.l	d2,d0
	moveq	#2,d1
	bsr.w	print_dollar_hex
	lea	not_text,a0
	bsr.w	print
	move.l	d3,d0
	moveq	#2,d1
	bsr.w	print_dollar_hex
	bsr.w	print_crlf
	moveq	#1,d0
	bra.s	vt_exit

vt_no_sync:
	lea	no_sync_text,a0
	bra.s	vt_fail
vt_bad_header:
	lea	bad_header_text,a0
vt_fail:
	bsr.w	print
	moveq	#1,d0
vt_exit:
	movem.l	(sp)+,d1-d4/a0-a2
	rts


;======================================================================
; The FDC, as the loader and its mastering tool drive it (loader.s)
;======================================================================

;----------------------------------------------------------------------
; a4 = $ffff8800 PSG, a2 = $ffff8604 FDC access, a3 = $ffff8606 DMA mode;
; d3 PSG port A, d4 delay, d1 drive A side 0 (loader.s, fdc_regs).
;----------------------------------------------------------------------
fdc_regs:
	suba.l	a4,a4
	lea	-$7800(a4),a4
	lea	-$1fc(a4),a2
	lea	2(a2),a3
	moveq	#14,d3
	moveq	#40,d4
	moveq	#5,d1
	rts


;----------------------------------------------------------------------
; Select drive A side 0 through PSG port A (loader.s, fdc_select).
;----------------------------------------------------------------------
fdc_select:
	movem.l	d0-d4/a2-a4,-(sp)
	bsr.s	fdc_regs
	move.b	d3,(a4)
	move.b	(a4),d0
	andi.b	#$f8,d0
	or.b	d1,d0
	move.b	d0,2(a4)
	movem.l	(sp)+,d0-d4/a2-a4
	rts


;----------------------------------------------------------------------
; d0 = the FDC's track register.
;----------------------------------------------------------------------
fdc_track:
	movem.l	d1-d4/a2-a4,-(sp)
	bsr.s	fdc_regs
	move.w	#$82,(a3)			; the track register
	move.w	d4,d2
ft_delay:
	dbra	d2,ft_delay
	move.w	(a2),d0
	andi.w	#$ff,d0
	movem.l	(sp)+,d1-d4/a2-a4
	rts


;----------------------------------------------------------------------
; Wait for the motor to stop and deselect the drive (loader.s,
; drive_deselect).
;----------------------------------------------------------------------
drive_deselect:
	movem.l	d0-d4/a2-a4,-(sp)
	bsr.s	fdc_regs
	move.w	#$80,(a3)
dd_wait_motor:
	move.w	d4,d2
dd_delay:
	dbra	d2,dd_delay
	move.w	(a2),d0
	btst	#FDC_MOTOR_ON,d0
	bne.s	dd_wait_motor
	moveq	#7,d1
	move.b	d3,(a4)
	move.b	(a4),d0
	andi.b	#$f8,d0
	or.b	d1,d0
	move.b	d0,2(a4)
	movem.l	(sp)+,d0-d4/a2-a4
	rts


;----------------------------------------------------------------------
; Seek to track d5 (loader.s, tool_write_track's start: track to the data
; register, then Seek).
;----------------------------------------------------------------------
seek_track:
	movem.l	d0-d4/a2-a4,-(sp)
	bsr.s	fdc_regs
	move.w	#$86,(a3)			; the data register
	move.l	d4,d0
st_mode_delay:
	dbra	d0,st_mode_delay
	move.w	d5,(a2)
	move.l	d4,d0
st_track_delay:
	dbra	d0,st_track_delay
	moveq	#CMD_SEEK,d0			; Seek, no verify
	bsr.w	fdc_command
	movem.l	(sp)+,d0-d4/a2-a4
	rts


;----------------------------------------------------------------------
; Write Track from track_image (loader.s, tool_write_track after the
; seek).  d0 = FDC status ($ff after a time-out), d1 = DMA status.
;----------------------------------------------------------------------
write_track:
	movem.l	d2-d4/a2-a4,-(sp)
	bsr.w	fdc_regs
	move.w	#$90,(a3)			; reset the DMA, write direction
	move.w	#$190,(a3)
	moveq	#WRITE_SECTORS,d0		; sector count
	bsr.w	fdc_write_reg
	move.l	#track_image,d0			; DMA address
	move.b	d0,9(a2)
	lsr.w	#8,d0
	move.b	d0,7(a2)
	swap	d0
	move.b	d0,5(a2)
	move.w	#CMD_WRITE_TRACK,d0		; WRITE TRACK
	move.w	#$180,(a3)
	bsr.w	fdc_write_wait
	bra.s	fdc_status


;----------------------------------------------------------------------
; Read Track into read_buffer (loader.s, read_track, without its seek:
; the head is on the track just written).  d0 = FDC status, d1 = DMA
; status.  The buffer is cleared first, so nothing old can pass.
;----------------------------------------------------------------------
read_track:
	movem.l	d2-d4/a2-a4,-(sp)
	lea	read_buffer,a2
	move.w	#READ_BYTES/4-1,d0
rt_clear:
	clr.l	(a2)+
	dbra	d0,rt_clear
	bsr.w	fdc_regs
	move.w	#$190,(a3)			; reset the DMA, read direction
	move.w	#$90,(a3)
	moveq	#READ_SECTORS,d0
	bsr.w	fdc_write_reg
	move.l	#read_buffer,d0
	move.b	d0,9(a2)
	lsr.w	#8,d0
	move.b	d0,7(a2)
	swap	d0
	move.b	d0,5(a2)
	move.w	#CMD_READ_TRACK,d0		; READ TRACK
	move.w	#$80,(a3)
	bsr.w	fdc_write_wait
	; fall into fdc_status

;----------------------------------------------------------------------
; d0 = FDC status (or $ff after a time-out), d1 = DMA status, after a
; command; restores what write_track or read_track saved.
;----------------------------------------------------------------------
fdc_status:
	tst.w	d2				; timed out?
	bmi.s	fs_timeout
	move.w	(a3),d1				; DMA status
	andi.w	#$ff,d1
	move.w	#$80,(a3)			; FDC status
	move.w	d4,d2
fs_delay:
	dbra	d2,fs_delay
	move.w	(a2),d0
	andi.w	#$ff,d0
	bra.s	fs_exit
fs_timeout:
	move.w	(a3),d1
	andi.w	#$ff,d1
	move.w	#$ff,d0
fs_exit:
	movem.l	(sp)+,d2-d4/a2-a4
	rts


;----------------------------------------------------------------------
; Give the FDC command d0 and wait for it (loader.s, fdc_command and
; fdc_write_reg).  fdc_write_reg writes d0 to the register the DMA mode
; selects; fdc_write_wait also waits for the FDC to finish.  The loader's
; fdc_write_reg always waits for GPIP bit 5, even after the DMA sector
; count (which only returns because the FDC interrupt is still on from the
; command before), and with no limit; here only commands wait, and the
; wait gives up after FDC_TIMEOUT, stops the FDC and sets d2 = -1 (else
; d2 = 0).
;----------------------------------------------------------------------
fdc_command:
	movem.l	d0-d4/a2-a4,-(sp)
	bsr.w	fdc_regs
	move.w	#$80,(a3)
	bsr.s	fdc_write_wait
	movem.l	(sp)+,d0-d4/a2-a4
	rts

fdc_write_reg:
	move.w	d4,d2
fwr_delay:
	dbra	d2,fwr_delay
	move.w	d0,(a2)
	rts

fdc_write_wait:
	bsr.s	fdc_write_reg
	move.l	HZ200.w,d2
	addi.l	#FDC_TIMEOUT,d2
fwr_wait:
	btst	#5,MFP_GPIP.w			; FDC interrupt (low) = done
	beq.s	fwr_done
	cmp.l	HZ200.w,d2
	bcc.s	fwr_wait
	move.w	#$80,(a3)			; too long: stop the FDC
	move.w	#CMD_FORCE_INT,(a2)
	moveq	#-1,d2
	rts
fwr_done:
	moveq	#0,d2
	rts


;======================================================================
; The screen and the keyboard
;======================================================================

;----------------------------------------------------------------------
; Print the text at a0 (Cconws).  Keeps every register.
;----------------------------------------------------------------------
print:
	movem.l	d0-d2/a0-a2,-(sp)
	pea	(a0)
	move.w	#9,-(sp)
	trap	#1				; Cconws
	addq.l	#6,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts


;----------------------------------------------------------------------
; Print the character d0 (Cconout).
;----------------------------------------------------------------------
print_char:
	movem.l	d0-d2/a0-a2,-(sp)
	andi.w	#$ff,d0
	move.w	d0,-(sp)
	move.w	#2,-(sp)
	trap	#1				; Cconout
	addq.l	#4,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts


print_crlf:
	move.l	a0,-(sp)
	lea	crlf_text,a0
	bsr.s	print
	move.l	(sp)+,a0
	rts


;----------------------------------------------------------------------
; Print d0 in hex, d1 digits (1-8), after a "$" (print_dollar_hex) or not.
;----------------------------------------------------------------------
print_dollar_hex:
	move.l	d0,-(sp)
	moveq	#'$',d0
	bsr.s	print_char
	move.l	(sp)+,d0

print_hex:
	movem.l	d0-d3/a0,-(sp)
	move.l	d0,d2
	moveq	#8,d0				; the first digit to the top
	sub.w	d1,d0
	lsl.w	#2,d0
	lsl.l	d0,d2
	move.w	d1,d3
	subq.w	#1,d3
	lea	hex_digits,a0
ph_digit:
	rol.l	#4,d2
	move.w	d2,d0
	andi.w	#$f,d0
	move.b	0(a0,d0.w),d0
	bsr.s	print_char
	dbra	d3,ph_digit
	movem.l	(sp)+,d0-d3/a0
	rts


;----------------------------------------------------------------------
; Print d0 (0-99) as two decimal digits.
;----------------------------------------------------------------------
print_dec2:
	movem.l	d0-d1,-(sp)
	andi.l	#$ffff,d0
	divu.w	#10,d0
	move.l	d0,d1
	addi.w	#'0',d0
	bsr.s	print_char
	swap	d1
	move.w	d1,d0
	addi.w	#'0',d0
	bsr.s	print_char
	movem.l	(sp)+,d0-d1
	rts


;----------------------------------------------------------------------
; Wait for a key, with the keys pressed before thrown away; d0 = its
; character (Crawcin).
;----------------------------------------------------------------------
wait_key:
	movem.l	d1-d2/a0-a2,-(sp)
wk_flush:
	move.w	#$b,-(sp)
	trap	#1				; Cconis
	addq.l	#2,sp
	tst.w	d0
	beq.s	wk_wait
	move.w	#7,-(sp)
	trap	#1				; Crawcin
	addq.l	#2,sp
	bra.s	wk_flush
wk_wait:
	move.w	#7,-(sp)
	trap	#1				; Crawcin
	addq.l	#2,sp
	movem.l	(sp)+,d1-d2/a0-a2
	rts


;======================================================================
; Data
;======================================================================

	section	data

;----------------------------------------------------------------------
; The 1 disk reissue's load table, as in loader.s (RETAIL_1DISK
; load_table): 20 bytes a file: start track, offset into the track, length
; on disc, length to decrypt, destination (where the loader puts the
; packed file; not used here).
;----------------------------------------------------------------------
load_table:
	dc.l	2,$0,$4a83,$4826,$3f23a		;  0 title.pic
	dc.l	5,$284,$17cc,$16fa,$75efc	;  1 panel.gfx
	dc.l	6,$252,$1634,$156c,$6b7fc	;  2 panel.bin
	dc.l	7,$88,$2299,$2160,$6d3e4	;  3 sound.prg
	dc.l	8,$b22,$1cb6,$1bc6,$1fffc	;  4 frontend.bin
	dc.l	9,$fe2,$8262,$7e34,$3f236	;  5 frontend.gfx
	dc.l	15,$246,$1868,$1788,$78000	;  6 level1.pic
	dc.l	16,$2b0,$4671,$4400,$21fc	;  7 level1.bin
	dc.l	19,$122,$74a1,$70de,$4fffc	;  8 level1a.gfx
	dc.l	23,$15c4,$1d7a,$1c70,$5fffc	;  9 level1b.gfx
	dc.l	25,$340,$4128,$3f0c,$73fc	; 10 level1.map
	dc.l	27,$146a,$22df,$21a4,$78000	; 11 level2.pic
	dc.l	29,$74a,$633a,$6006,$21fc	; 12 level24.bin
	dc.l	33,$a86,$2ab0,$2926,$bbfc	; 13 level24.gfx
	dc.l	35,$538,$103ad,$fb74,$10434	; 14 level2.gfx
	dc.l	46,$e6,$299b,$2848,$78000	; 15 level3.pic
	dc.l	47,$1282,$613d,$5e4c,$1fffc	; 16 level3.bin
	dc.l	51,$13c0,$25a7,$245c,$78000	; 17 level4.pic
	dc.l	29,$74a,$633a,$6006,$21fc	; 18 level24.bin (as 12)
	dc.l	33,$a86,$2ab0,$2926,$bbfc	; 19 level24.gfx (as 13)
	dc.l	53,$968,$122b7,$119a6,$10434	; 20 level4.gfx
	dc.l	65,$c20,$281c,$26b4,$78000	; 21 level5.pic
	dc.l	67,$43e,$4a36,$47c4,$21fc	; 22 level5.bin
	dc.l	70,$676,$690b,$6568,$4fffc	; 23 level5a.gfx
	dc.l	74,$f82,$1d29,$1c38,$5fffc	; 24 level5b.gfx
	dc.l	75,$14ac,$5e7e,$5b86,$73fc	; 25 level5.map

; Each file's name in \FILES, and the bytes that follow it on the disk.
file_names:
	dc.l	name_title_pic,name_panel_gfx,name_panel_bin,name_sound_prg
	dc.l	name_frontend_bin,name_frontend_gfx,name_level1_pic,name_level1_bin
	dc.l	name_level1a_gfx,name_level1b_gfx,name_level1_map,name_level2_pic
	dc.l	name_level24_bin,name_level24_gfx,name_level2_gfx,name_level3_pic
	dc.l	name_level3_bin,name_level4_pic,name_level24_bin,name_level24_gfx
	dc.l	name_level4_gfx,name_level5_pic,name_level5_bin,name_level5a_gfx
	dc.l	name_level5b_gfx,name_level5_map

file_tails:
	dc.l	0,0,0,0,frontend_tail,0,0,0,0,0,0,0,0
	dc.l	0,0,0,0,0,0,0,0,0,0,0,0,0
file_tail_sizes:
	dc.w	0,0,0,0,8,0,0,0,0,0,0,0,0
	dc.w	0,0,0,0,0,0,0,0,0,0,0,0,0
; The 8 bytes after frontend.bin on the original disk, before the $07
; filler: left there by the mastering tool, outside the file's length in
; the load table, and in no packed file.
frontend_tail:
	dc.b	$e9,$83,$d0,$ea,$cd,$d5,$d0,$2f

name_title_pic:		dc.b	'TITLE.PIC',0
name_panel_gfx:		dc.b	'PANEL.GFX',0
name_panel_bin:		dc.b	'PANEL.BIN',0
name_sound_prg:		dc.b	'SOUND.PRG',0
name_frontend_bin:	dc.b	'FRONTEND.BIN',0
name_frontend_gfx:	dc.b	'FRONTEND.GFX',0
name_level1_pic:	dc.b	'LEVEL1.PIC',0
name_level1_bin:	dc.b	'LEVEL1.BIN',0
name_level1a_gfx:	dc.b	'LEVEL1A.GFX',0
name_level1b_gfx:	dc.b	'LEVEL1B.GFX',0
name_level1_map:	dc.b	'LEVEL1.MAP',0
name_level2_pic:	dc.b	'LEVEL2.PIC',0
name_level24_bin:	dc.b	'LEVEL24.BIN',0
name_level24_gfx:	dc.b	'LEVEL24.GFX',0
name_level2_gfx:	dc.b	'LEVEL2.GFX',0
name_level3_pic:	dc.b	'LEVEL3.PIC',0
name_level3_bin:	dc.b	'LEVEL3.BIN',0
name_level4_pic:	dc.b	'LEVEL4.PIC',0
name_level4_gfx:	dc.b	'LEVEL4.GFX',0
name_level5_pic:	dc.b	'LEVEL5.PIC',0
name_level5_bin:	dc.b	'LEVEL5.BIN',0
name_level5a_gfx:	dc.b	'LEVEL5A.GFX',0
name_level5b_gfx:	dc.b	'LEVEL5B.GFX',0
name_level5_map:	dc.b	'LEVEL5.MAP',0

files_dir:	dc.b	'\FILES\',0
hex_digits:	dc.b	'0123456789ABCDEF'

; The texts: 39 characters a line at most, for 40 columns.
title_text:
; text colour 15 on colour 0: the VT52 colour is the low 4 bits of the
; character after ESC b / ESC c, so '?' is 15 and '0' is 0 (a 0 byte
; would end the text)
	dc.b	27,'b','?',27,'c','0'
	dc.b	27,'E'
	dc.b	'MACRODOS  Batman The Movie track writer',13,10
	dc.b	'Copyright (c) Darren Birks,',13,10
	dc.b	'November 2026',13,10
	dc.b	13,10
	dc.b	'Writes the 1 disk reissue game tracks',13,10
	dc.b	'2-79 with WD1772 Write Track ($F0),',13,10
	dc.b	'built from the packed files in \FILES.',13,10
	dc.b	13,10
	dc.b	'Press a key to start.',13,10
	dc.b	13,10,0
checking_text:
	dc.b	'Looking for the files in \FILES.',13,10,0
memory_text:	dc.b	'RAM ',0
free_text:	dc.b	', free ',0
no_memory_text:
	dc.b	'Not enough free memory.',13,10,0
parts_text:
	dc.b	'The files load in two parts.',13,10,0
loading_text:
	dc.b	'Loading and encrypting the files:',13,10,0
same_text:	dc.b	'same as ',0
encrypt_text:	dc.b	' enc ',0
missing_text:	dc.b	'NOT FOUND',13,10,0
short_text:	dc.b	'too short',13,10,0
loaded_text:	dc.b	'All files loaded.',13,10,0
rest_loaded_text: dc.b	'The rest of the files loaded.',13,10,0
full_text:	dc.b	'Memory full: the rest loads later.',13,10,0
insert_text:
	dc.b	'Insert the DESTINATION disk in drive A',13,10
	dc.b	'(tracks 0-1 already written).',13,10,0
tracks_text:	dc.b	'Tracks ',0
overwrite_text:	dc.b	' will be OVERWRITTEN.',13,10
	dc.b	'Press Y to write, any other key quits.',13,10,13,10,0
source_text:
	dc.b	13,10,'Insert the disk with \FILES in drive A',13,10
	dc.b	'and press a key.',13,10,13,10,0
track_text:	dc.b	'Track ',0
built_text:	dc.b	'  built, checksum ',0
starts_text:	dc.b	' starts at ',0
ends_text:	dc.b	' ends ',0
comma_text:	dc.b	', ',0
ok_text:	dc.b	' ok',0
bad_length_text: dc.b	' BAD LENGTH',0
write_text:	dc.b	'  write ',0
verify_text:	dc.b	'  verify ',0
colon_text:	dc.b	': ',0
fdc_text:	dc.b	'fdc ',0
dma_text:	dc.b	' dma ',0
timeout_text:	dc.b	' TIME-OUT',0
wp_text:	dc.b	' PROTECTED',0
lost_text:	dc.b	' LOST DATA',0
same_ok_text:	dc.b	'same, $1804 bytes',13,10,0
differs_text:	dc.b	'differs ',0
got_text:	dc.b	': ',0
not_text:	dc.b	' not ',0
no_sync_text:	dc.b	'no sync found',13,10,0
bad_header_text: dc.b	'bad header',13,10,0
give_up_text:	dc.b	'  3 tries failed, going on',13,10,0
protect_text:	dc.b	'The disk is write protected: stopped.',13,10,0
done_text:	dc.b	13,10,'Done. Tracks good: ',0
failed_text:	dc.b	', failed: ',0
stopped_text:	dc.b	'(stopped: write protected)',13,10,0
failed_list_text: dc.b	'Failed tracks:',0
key_text:	dc.b	13,10,'Press a key to quit.',13,10,0
reboot_text:	dc.b	13,10,'Press a key to reboot into Batman.',13,10,0
crlf_text:	dc.b	13,10,0
medium_colours_text: dc.b	27,'b','3',27,'c','0',0
	even


;======================================================================
; Variables and buffers
;======================================================================

	section	bss

old_ssp:	ds.l	1		; the stack Super gave back
old_rez:	ds.w	1		; the resolution at the start
old_colour0:	ds.w	1		; and palette colours 0 and 15
old_colour15:	ds.w	1
line_a:		ds.l	1		; the Line-A variables
path_buffer:	ds.b	32		; \FILES\NAME
	even
file_buffers:	ds.l	FILE_COUNT	; each file's encrypted copy
file_sizes:	ds.l	FILE_COUNT	; and its length
files_block:	ds.l	1		; the memory for the files
src_offset:	ds.l	1		; how far the file under way got
pass_first_track: ds.w	1		; the tracks the files loaded fill
pass_last_track: ds.w	1
tos_track:	ds.w	1		; where TOS left the head

; the stream of escaped files (build_track_data, next_disk_byte)
stream_pos:	ds.l	1		; where the next byte goes, from track 2
file_start:	ds.l	1		; where the file under way started
src_ptr:	ds.l	1		; its next byte
src_end:	ds.l	1		; and its end
tail_ptr:	ds.l	1		; its tail bytes still to come
tail_left:	ds.w	1
cur_file:	ds.w	1		; the file under way, or the next one
file_active:	ds.b	1		; a file is under way
pending:	ds.b	1		; the second byte of an escape is due
pending_byte:	ds.b	1		; and is this
prev_byte:	ds.b	1		; the byte written before
write_protected: ds.b	1
files_on_floppy: ds.b	1		; \FILES is on drive A or B
	even
track_checksum:	ds.w	1
written_count:	ds.w	1		; tracks that read back the same
failed_count:	ds.w	1		; and tracks that did not
failed_tracks:	ds.b	80

track_data:	ds.b	TRACK_BYTES	; a track's data bytes
	even
track_image:	ds.b	IMAGE_BYTES+512	; what Write Track is given (DMA)
	even
read_buffer:	ds.b	READ_BYTES+512	; what Read Track gives (DMA)
	even
		ds.b	4096		; the stack
stack_top:

	end
