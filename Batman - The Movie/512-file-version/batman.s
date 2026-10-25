; Batman The Movie (Ocean, 1989) - file version on a floppy
;
; Disassembled by Darren Birks in the evil month of October 2026.
;
; A TOS program that runs the 1 disk retail reissue from the files on a normal TOS
; floppy instead of its SpeedLock disk, on any ST with 512K or more.  The disk in drive
; A holds batman.prg and the game files in its root directory: the reissue's 24 files
; (retail_1disk_speedlock\unpacked: title.pic, panel.gfx, ... level5.map) packed with
; Pack-Ice 2.40 by icepack (icepack\python-pack.cmd or go-pack.cmd, into files\).
;
;======================================================================
; How the original disk loads
;======================================================================
;
; The SpeedLock boot (retail_1disk_speedlock\speedlock) reads track 0 sectors 2-9,
; decrypts them to $21000 and jumps there.  That is loader.bin: a $4c byte copy stub
; (loadstub.s) that copies the loader to $1000, puts a jump table at $200 and enters
; loader_start, and the loader itself (loader.s), which stays at $1000-$1fff for the
; whole game.  Each loader section (start, after a level, levels 1-5) loads the files
; of a scene from the load table and jumps to the game; a level leaves through the
; table at $200 back into the loader.
;
; A load table entry is 5 longs, which a section fetches with movem.l into d0-d4 and
; passes to load_file: d0 the track, d1 the offset in it, d2 the length on the disk,
; d3 the length to decrypt, d4 the destination.  load_file ($150e) is the track loader:
;
;   - The game tracks (2-81) have no sectors.  Each was written with Write Track as
;       gap, $f5 $f5 $f5 (read back as $c2 $a1 $a1), $0f, track number, $0f,
;       $1800 data bytes, a checksum word, gap
;     and files run on from the end of one track into the next.
;   - load_file selects drive A side 0, seeks to the track and reads the whole track
;     into $70000 with READ TRACK.  It looks for the $a1 sync bytes, checks the track
;     number after them (and starts again if it is wrong), skips the offset into the
;     track and copies the data bytes to the destination until the length is reached,
;     reading the next track whenever one runs out.  The checksum is read but not
;     checked.
;   - The data is escaped, as Write Track cannot write $f5-$f7: $0f, x stands for ~x.
;     load_file undoes that in place, then decrypts the first d3 bytes in two passes
;     (each long: swap(long ^ k0) ^ k1, then k0 += k1, k0 = $f4bd128c, k1 = $5716923a).
;   - It leaves the destination and length in file_vars ($16d6: +8 length, +$c
;     destination).
;
; After load_file the section calls unpack_file ($12c6), which unpacks the FORM HUFF
; file at the destination in place (the SIZE, CODE and TREE chunks; see loader.s), and
; for a picture show_picture, which decodes it to the screen.  Both take the file from
; file_vars+$c.
;
;======================================================================
; What this program changes
;======================================================================
;
; The game overwrites TOS's memory, so GEMDOS cannot load files while it runs, and the
; files on a TOS disk lie in sectors, not on game tracks.  So the files are read with
; the FDC, sector by sector, with a reader that replaces load_file:
;
;   1. While TOS still runs, batman.prg fades the screen to black with its text in
;      white, waits for a key and fades the text out.  It reads the boot sector, FAT
;      and root directory of drive A with BIOS Rwabs and works out where each file is:
;      its clusters, followed through the FAT, become runs of logical sectors (first
;      sector, count).  A file written to a fresh disk is one run.
;   2. A copy of loader.bin (incbin'd below) gets these changes, all inside the loader,
;      which is in memory for the whole game (nothing goes outside $1000-$1fff):
;        - The load table: each 20 byte entry gets four new longs: 1) the address of
;          the file's runs, 2) its destination (the entry's own fifth long, which the
;          loader keeps using), 3) its length and 4) a delay loop count.
;        - load_file starts with jmp resident_load, and the runs go over the rest of
;          the old track loader ($1514-$160d).  fdc_regs and drive_deselect after it
;          are kept: the sections still call drive_deselect.
;        - The resident reader (resident_start .. resident_end) goes in the zero
;          padding after the Huffman tree work area ($1d14-$1fb3).
;        - The files are Pack-Ice packed, not FORM HUFF, so the FORM HUFF unpacker is
;          not needed: the Pack-Ice 2.40 depacker (ice_start .. ice_end, as it comes
;          with Pack-Ice) goes over the Huffman tree work area ($1914-$1d13), and
;          unpack_file ($12c6) becomes unpack_stub: Pack-Ice unpacks the file at
;          file_vars+$c in place, from the same address, as FORM HUFF did, and the 31
;          bytes after it are cleared, as the reissue's unpack_file clears them.  The
;          sections and show_picture call unpack_file after each load as before.
;   3. The loader goes to $21000 and runs as after the SpeedLock boot.
;
; The sector reader (resident_load), each time a section loads a file:
;
;   - It waits out the delay: the file loaded right after each picture has one (DELAY,
;     about 2.4 s at 8 MHz), so the picture can be seen before the rest of the section
;     loads, as it was while the original disk loaded.
;   - It sets file_vars as load_file did, for unpack_file and show_picture.
;   - For each run it reads as many sectors as lie on one track side at a time with a
;     single READ MULTIPLE SECTORS command: logical sector n is on cylinder
;     n / (sectors per track x sides), side (n / sectors per track) mod sides, sector
;     n mod sectors per track + 1, as TOS numbers them.  The DMA moves the sectors
;     straight to the destination; when the DMA address reaches the end of them, the
;     FDC is stopped with FORCE INTERRUPT (it would read on to the next sector).
;   - The last sector of a file goes to TEMP ($70000, where the old loader kept its
;     track), and only the bytes left of the file are copied from there, so nothing
;     past the file is written.
;   - A read that fails (the FDC stops early, a timeout, a DMA error) is tried again
;     after a RESTORE to track 0, for ever, as the old loader also did.
;
; Pack-Ice 2.40 (ice_depack), after the reader, through unpack_file:
;
;   - A packed file is 'ICE!', the packed length, the unpacked length and the packed
;     data.  The bits and literal bytes are read from the end of the data backwards
;     and the output is written from its end backwards: literal runs, and matches that
;     copy bytes from further up the output (an LZ77 scheme), or repeat the byte after
;     them.
;   - Unpacking in place: the output is first written 120 bytes higher than the file's
;     destination, so that it never overtakes the packed data still to be read, and is
;     then moved down by 120.  The 120 bytes after the output are kept on the stack
;     meanwhile and put back, so the depacker takes 196 bytes of stack; every scene's
;     stack has room for that below it.
;
; Assemble with Devpac, or vasmm68k_mot -devpac -m68000 -Ftos -o batman.prg batman.s.

	opt	o-

LOADER_RUN	equ	$1000			; where the game loader runs (loader.s)
STUB_AT		equ	$21000			; where loader.bin's copy stub runs (loadstub.s)
STUB_LEN	equ	$4c			; the copy stub in front of the loader code
LOADER_SIZE	equ	$1000			; loader.bin, stub and loader code
IMAGE		equ	STUB_LEN-LOADER_RUN	; loader address + IMAGE = offset in loader.bin

unpack_file	equ	$12c6			; loader.s: the FORM HUFF unpacker, replaced
load_file	equ	$150e			; loader.s: the track loader, replaced
fdc_regs	equ	$160e			; loader.s: the first routine kept after it
file_vars	equ	$16d6			; loader.s: +8 length, +$c destination
load_table	equ	$16e8			; loader.s: 26 entries of 20 bytes
huff_tree	equ	$1914			; loader.s: the Huffman tree work area (1024 bytes)
sector_padding	equ	$1d14			; loader.s: zero padding up to the end of loader.bin
ENTRIES		equ	26
FILES		equ	24			; level24.bin and level24.gfx serve two entries

RESIDENT	equ	sector_padding		; the resident reader
RESIDENT_END	equ	LOADER_RUN+LOADER_SIZE-STUB_LEN
ICE		equ	huff_tree		; the Pack-Ice depacker
ICE_END		equ	sector_padding
RUNS		equ	load_file+6		; the runs, after jmp resident_load
RUNS_END	equ	fdc_regs
TEMP		equ	$70000			; the last sector of a file (the old track buffer)
LAUNCH_AT	equ	$70000			; the loader image and the launcher, once
DELAY		equ	$100000			; about 2.4 s at 8 MHz (subq.l, bne: 18 cycles)
FADE_FRAMES	equ	3			; VBLs per fade step
FAT_SECTORS	equ	9			; largest FAT read at startup
ROOT_SECTORS	equ	16			; largest root directory read at startup

palette		equ	$ffff8240
dma_data	equ	$ffff8604		; FDC registers / DMA sector count
dma_mode	equ	$ffff8606		; DMA mode (write), DMA status (read)
dma_high	equ	$ffff8609
dma_mid		equ	$ffff860b
dma_low		equ	$ffff860d
gpip		equ	$fffffa01		; MFP GPIP: bit 5 low = FDC interrupt
psg_select	equ	$ffff8800
psg_write	equ	$ffff8802

	section	text

;----------------------------------------------------------------------
; Start: keep only the program's own memory, go to supervisor mode (for the palette,
; the system variables and later the hardware) and keep the desktop's colours.
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
; The text, white on a screen that fades from white to black; a key; the text fades out.
; Colour 0 is the background, colours 1-15 the text (in any resolution).
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
; The disk layout from the boot sector of drive A (its BIOS parameter block, little
; endian words): bytes per sector, sectors per cluster, reserved sectors, FATs, root
; directory entries, sectors per FAT, sectors per track, sides.  Logical sectors then
; run: the reserved sectors (the boot sector), the FATs, the root directory, the data
; area where cluster 2 is the first.
;----------------------------------------------------------------------
	moveq	#0,d0				; logical sector 0: the boot sector
	moveq	#1,d1
	lea	sector_buffer,a0
	bsr.w	read_logical
	lea	sector_buffer,a0
	lea	$b(a0),a1			; bytes per sector
	bsr.w	get_le16
	cmpi.w	#512,d0				; the reader moves 512 byte sectors only
	bne.w	bad_disk
	moveq	#0,d0
	move.b	$d(a0),d0			; sectors per cluster
	move.w	d0,cluster_size
	lea	$e(a0),a1			; reserved sectors: where the first FAT starts
	bsr.w	get_le16
	move.w	d0,fat_start
	lea	$16(a0),a1			; sectors per FAT
	bsr.w	get_le16
	move.w	d0,fat_size
	cmpi.w	#FAT_SECTORS,d0			; must fit fat_buffer
	bhi.w	bad_disk
	lea	$18(a0),a1			; sectors per track, for the reader
	bsr.w	get_le16
	lea	sectors_per_track(pc),a2
	move.w	d0,(a2)
	lea	$1a(a0),a1			; sides, for the reader
	bsr.w	get_le16
	lea	sides(pc),a2
	move.w	d0,(a2)
	moveq	#0,d1
	move.b	$10(a0),d1			; FATs
	mulu.w	fat_size,d1			; x sectors per FAT
	add.w	fat_start,d1			; + reserved sectors
	move.w	d1,root_start			; = the root directory's first sector
	lea	$11(a0),a1			; root directory entries
	bsr.w	get_le16
	move.w	d0,root_entries
	lsr.w	#4,d0				; 16 entries (32 bytes each) a sector
	cmpi.w	#ROOT_SECTORS,d0		; must fit root_buffer
	bhi.w	bad_disk
	move.w	d0,root_size
	add.w	root_start,d0			; after the root directory: the data area,
	move.w	d0,data_start			; cluster 2

	move.w	fat_start,d0			; the (first) FAT
	move.w	fat_size,d1
	lea	fat_buffer,a0
	bsr.w	read_logical
	move.w	root_start,d0			; the root directory
	move.w	root_size,d1
	lea	root_buffer,a0
	bsr.w	read_logical

;----------------------------------------------------------------------
; Each file's sectors as runs: first logical sector and count, words, ended by a count
; of 0.  They are built in run_buffer and go to RUNS in the loader; file_list gets the
; address each file's runs will have there and the file's length.
;----------------------------------------------------------------------
	lea	file_list(pc),a4		; the files
	lea	run_buffer,a3			; where the next run goes
	moveq	#FILES-1,d7
file_loop:
	movea.l	(a4),a0				; the name, 11 characters as in the directory
	bsr.w	find_entry
	tst.l	d0
	beq.w	file_missing
	movea.l	d0,a0				; the directory entry
	lea	$1c(a0),a1			; +$1c: the file's length
	bsr.w	get_le32
	move.l	d0,8(a4)
	move.l	a3,d1				; its runs, at their address in the loader
	sub.l	#run_buffer,d1
	add.l	#RUNS,d1
	move.l	d1,4(a4)
	addi.l	#511,d0				; whole sectors
	moveq	#9,d1
	lsr.l	d1,d0
	move.w	d0,d5				; sectors still to note
	lea	$1a(a0),a1			; +$1a: the first cluster
	bsr.w	get_le16
	move.w	d0,d6
	moveq	#-1,d4				; no run yet for this file
cluster_loop:
	tst.w	d5				; all sectors noted?
	beq.s	file_done
	cmpi.w	#2,d6				; a cluster number must be a data cluster,
	bcs.w	bad_disk
	cmpi.w	#$ff8,d6			; not the end of the chain while sectors are left
	bcc.w	bad_disk
	move.w	d6,d0				; its first logical sector:
	subq.w	#2,d0				; data_start + (cluster - 2) x cluster size
	mulu.w	cluster_size,d0
	add.w	data_start,d0
	move.w	cluster_size,d2			; sectors in the cluster
cluster_sector_loop:
	tst.w	d5
	beq.s	cluster_next
	tst.w	d4				; the first sector of the file: a new run
	bmi.s	new_run
	move.w	-4(a3),d1			; does it follow on from the last run?
	add.w	-2(a3),d1			; (its first sector + its count)
	cmp.w	d0,d1
	bne.s	new_run
	addq.w	#1,-2(a3)			; yes: one more sector in it
	bra.s	sector_noted
new_run:
	lea	run_buffer_end-8,a1		; room for this run and the end marker?
	cmpa.l	a1,a3
	bhi.w	no_room
	move.w	d0,(a3)+			; first sector
	move.w	#1,(a3)+			; count
	moveq	#0,d4
sector_noted:
	addq.w	#1,d0				; the cluster's next sector
	subq.w	#1,d5
	subq.w	#1,d2
	bne.s	cluster_sector_loop
cluster_next:
	move.w	d6,d0				; the next cluster from the FAT
	bsr.w	next_cluster
	move.w	d0,d6
	bra.s	cluster_loop
file_done:
	lea	run_buffer_end-4,a1		; room for the end marker?
	cmpa.l	a1,a3
	bhi.w	no_room
	clr.l	(a3)+				; end of the runs (first sector and count 0)
	lea	12(a4),a4			; the next file
	dbra	d7,file_loop

;----------------------------------------------------------------------
; The loader image at LAUNCH_AT: the load table, load_file, the runs and the resident
; reader; then start the loader from a launcher after the image (the program itself
; may lie where the loader goes).  TOS is not needed any more.
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
	move.l	4(a1),(a2)			; 1) the file's runs
	move.l	16(a2),4(a2)			; 2) its destination: the entry's own
	move.l	8(a1),8(a2)			; 3) its length
	clr.l	12(a2)				; 4) the delay: none,
	tst.w	(a0)+
	beq.s	patch_entry_next
	move.l	#DELAY,12(a2)			; or DELAY after a picture
patch_entry_next:
	lea	20(a2),a2			; the next entry
	dbra	d1,patch_entry_loop

	lea	load_file+IMAGE(a3),a1		; load_file: jmp resident_load
	move.w	#$4ef9,(a1)+			; (jmp abs.l)
	move.l	#RESIDENT+resident_load-resident_start,(a1)+
	lea	run_buffer,a0			; the runs over the rest of the track loader
	move.w	#(RUNS_END-RUNS)/2-1,d0
copy_runs_loop:
	move.w	(a0)+,(a1)+
	dbra	d0,copy_runs_loop

	lea	unpack_stub(pc),a0		; unpack_file: movea.l file_vars+$c,a0 / jmp ice_depack
	lea	unpack_file+IMAGE(a3),a1
	move.w	#(unpack_stub_end-unpack_stub)/2-1,d0
copy_unpack_loop:
	move.w	(a0)+,(a1)+
	dbra	d0,copy_unpack_loop

	lea	ice_start(pc),a0		; the depacker over the Huffman tree work area
	lea	ICE+IMAGE(a3),a1
	move.w	#(ice_end-ice_start)/2-1,d0
copy_ice_loop:
	move.w	(a0)+,(a1)+
	dbra	d0,copy_ice_loop

	lea	resident_start(pc),a0		; the resident reader in the padding
	lea	RESIDENT+IMAGE(a3),a1
	move.w	#(resident_end-resident_start)/2-1,d0
copy_resident_loop:
	move.w	(a0)+,(a1)+
	dbra	d0,copy_resident_loop

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

; Read d1 sectors from logical sector d0 of drive A to a0 (BIOS Rwabs).
read_logical:
	movem.l	d0-d2/a0-a2,-(sp)
	clr.w	-(sp)				; drive A
	move.w	d0,-(sp)			; first logical sector
	move.w	d1,-(sp)			; count
	move.l	a0,-(sp)			; buffer
	clr.w	-(sp)				; read
	move.w	#4,-(sp)			; Rwabs
	trap	#13
	lea	14(sp),sp
	tst.l	d0				; negative: a disk error
	bmi.w	read_error
	movem.l	(sp)+,d0-d2/a0-a2
	rts

; d0 = the little endian word at a1 (the DOS layout of the boot sector and directory).
get_le16:
	moveq	#0,d0
	move.b	1(a1),d0			; high byte
	lsl.w	#8,d0
	move.b	(a1),d0				; low byte
	rts

; d0 = the little endian long at a1.
get_le32:
	move.l	d1,-(sp)
	addq.w	#2,a1				; the high word
	bsr.s	get_le16
	move.w	d0,d1
	swap	d1
	subq.w	#2,a1				; the low word
	bsr.s	get_le16
	move.w	d0,d1
	move.l	d1,d0
	move.l	(sp)+,d1
	rts

; d0 = the root directory entry of the file named at a0 (11 characters, as in a
; directory entry: 8 for the name, 3 for the extension, padded with spaces), or 0.
find_entry:
	movem.l	d1-d2/a1-a2,-(sp)
	lea	root_buffer,a1
	move.w	root_entries,d1
	subq.w	#1,d1
find_entry_loop:
	tst.b	(a1)				; a first byte of 0: the end of the directory
	beq.s	find_entry_none
	btst	#3,11(a1)			; attributes: not a volume label
	bne.s	find_entry_next
	btst	#4,11(a1)			; nor a folder
	bne.s	find_entry_next
	moveq	#10,d2				; the 11 name characters
find_entry_compare:
	move.b	0(a0,d2.w),d0
	cmp.b	0(a1,d2.w),d0
	bne.s	find_entry_next
	dbra	d2,find_entry_compare
	move.l	a1,d0				; found
	bra.s	find_entry_exit
find_entry_next:
	lea	32(a1),a1			; the next entry
	dbra	d1,find_entry_loop
find_entry_none:
	moveq	#0,d0
find_entry_exit:
	movem.l	(sp)+,d1-d2/a1-a2
	rts

; d0 = the FAT12 entry of cluster d0: the next cluster of the file ($ff8+ = the end).
; Two entries share 3 bytes: an even cluster has the low 12 bits of the word at
; cluster x 3 / 2, an odd one the high 12 bits.
next_cluster:
	movem.l	d1-d2/a0,-(sp)
	move.w	d0,d1
	lsr.w	#1,d1
	add.w	d0,d1				; cluster x 3 / 2
	lea	fat_buffer,a0
	moveq	#0,d2				; the little endian word there
	move.b	1(a0,d1.w),d2
	lsl.w	#8,d2
	move.b	0(a0,d1.w),d2
	btst	#0,d0
	beq.s	next_cluster_even
	lsr.w	#4,d2				; odd: the high 12 bits
	bra.s	next_cluster_exit
next_cluster_even:
	andi.w	#$fff,d2			; even: the low 12 bits
next_cluster_exit:
	move.w	d2,d0
	movem.l	(sp)+,d1-d2/a0
	rts

;----------------------------------------------------------------------
; Errors: say what went wrong in white, wait for a key, back to the desktop in its
; own colours.
;----------------------------------------------------------------------
no_room:
	lea	no_room_text(pc),a0
	bra.s	quit

bad_disk:
	lea	bad_disk_text(pc),a0
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
; The resident reader, copied into the loader's zero padding at RESIDENT ($1d14).
; Position independent; it runs with the game, without TOS.
;======================================================================
resident_start:

;----------------------------------------------------------------------
; Replaces load_file (jmp from $150e).  Called with a load table entry in d0-d4: d0
; the file's runs, d1 its destination, d2 its length, d3 the delay (d4 is the entry's
; own destination, unused here).  Sets file_vars as load_file does for unpack_file and
; show_picture, waits, then reads the file: whole sectors straight to the destination,
; the last one to TEMP and only the file's bytes from there.  Keeps all registers, as
; load_file did, and leaves interrupts off, as load_file did.
;----------------------------------------------------------------------
resident_load:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	#$2700,sr			; interrupts off: the reader polls the FDC
	move.l	d1,file_vars+$c.w		; destination, for unpack_file and show_picture
	move.l	d2,file_vars+8.w		; length
	tst.l	d3				; a delay?
	beq.s	resident_read
resident_delay_loop:
	subq.l	#1,d3
	bne.s	resident_delay_loop
resident_read:
	movea.l	d0,a5				; runs
	movea.l	d1,a4				; where the next sectors go
	move.l	d2,d7				; bytes of the file left
run_loop:
	move.w	(a5)+,d6			; first logical sector of the run
	move.w	(a5)+,d5			; sectors in it
	beq.s	resident_done			; a count of 0: the end (not reached normally)
chunk_loop:
	moveq	#0,d0				; logical sector to cylinder, side and sector:
	move.w	d6,d0				; d0 = sector / sectors per track (the track,
	divu.w	sectors_per_track(pc),d0	; counting both sides), remainder the sector - 1
	move.l	d0,d1
	swap	d1				; d1 = sector - 1
	moveq	#0,d2				; side 0
	move.w	sides(pc),d3
	cmpi.w	#2,d3
	bne.s	chunk_track
	moveq	#1,d2				; two sides: the tracks alternate sides,
	and.w	d0,d2				; side = track & 1,
	lsr.w	#1,d0				; cylinder = track / 2
chunk_track:
	move.w	sectors_per_track(pc),d3	; the sectors from here to the end of the
	sub.w	d1,d3				; track side, or the rest of the run if fewer
	cmp.w	d5,d3
	bls.s	chunk_count
	move.w	d5,d3
chunk_count:
	addq.w	#1,d1				; the FDC numbers sectors from 1
	moveq	#0,d4				; bytes in these sectors: count x 512
	move.w	d3,d4
	lsl.l	#8,d4
	add.l	d4,d4
	cmp.l	d7,d4				; does the file end in them?
	bcc.s	chunk_last
	movea.l	a4,a0				; no: all of them straight to the destination
	bsr.s	read_sectors
	adda.l	d4,a4
	sub.l	d4,d7
	add.w	d3,d6				; on in the run
	sub.w	d3,d5
	bne.s	chunk_loop
	bra.s	run_loop			; the run is done: the next one

chunk_last:
	subq.w	#1,d3				; yes: the sectors before the last one
	beq.s	chunk_last_sector		; (if any) straight to the destination
	movea.l	a4,a0
	bsr.s	read_sectors
	moveq	#0,d4
	move.w	d3,d4
	lsl.l	#8,d4
	add.l	d4,d4
	adda.l	d4,a4
	sub.l	d4,d7
	add.w	d3,d1				; the last sector's number
chunk_last_sector:
	moveq	#1,d3				; the last one to TEMP,
	lea	TEMP,a0
	bsr.s	read_sectors
	subq.w	#1,d7				; then only the file's bytes from there
copy_last_loop:
	move.b	(a0)+,(a4)+
	dbra	d7,copy_last_loop
resident_done:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;----------------------------------------------------------------------
; Read d3 sectors from sector d1 of cylinder d0, side d2, to a0, with one READ MULTIPLE
; SECTORS.  The DMA counts the bytes it has moved in its address register; when it has
; moved them all, FORCE INTERRUPT stops the FDC, which would go on to the next sector.
; Retries for ever, restoring to track 0 before each new try.
;----------------------------------------------------------------------
read_sectors:
	movem.l	d4-d7/a1,-(sp)
read_retry:
	bsr.w	select_side			; drive A on, the side
	bsr.w	seek				; the head to the cylinder
	move.l	a0,d4				; DMA address = a0, low byte first
	move.b	d4,dma_low.w
	lsr.l	#8,d4
	move.b	d4,dma_mid.w
	lsr.l	#8,d4
	move.b	d4,dma_high.w
	move.w	#$90,dma_mode.w			; toggling the write bit clears the DMA;
	move.w	#$190,dma_mode.w		; $90 then selects the sector count register
	move.w	#$90,dma_mode.w			; for reading
	move.w	d3,d4				; sectors the DMA may move
	bsr.w	fdc_write
	move.w	#$84,dma_mode.w			; FDC sector register: the first sector
	move.w	d1,d4
	bsr.w	fdc_write
	move.w	#$80,dma_mode.w			; FDC command register:
	move.w	#$94,d4				; READ MULTIPLE SECTORS, 15 ms head settle
	bsr.w	fdc_write
	move.l	a0,d5				; the end the DMA must reach
	moveq	#0,d4
	move.w	d3,d4
	lsl.l	#8,d4
	add.l	d4,d4
	add.l	d4,d5
	move.l	#$200000,d7			; timeout, several seconds
read_wait:
	btst	#5,gpip.w			; the FDC stopped before the end: error
	beq.s	read_failed			; (CRC error, sector not found, ...)
	moveq	#0,d4				; where the DMA is
	move.b	dma_high.w,d4
	lsl.l	#8,d4
	move.b	dma_mid.w,d4
	lsl.l	#8,d4
	move.b	dma_low.w,d4
	cmp.l	d5,d4				; all moved?
	bcc.s	read_done
	subq.l	#1,d7
	bne.s	read_wait
read_failed:
	bsr.s	force_interrupt			; stop the FDC
	lea	cylinder(pc),a1			; and restore before the next try
	move.w	#-1,(a1)
	bra.w	read_retry
read_done:
	bsr.s	force_interrupt			; stop it reading on
	move.w	#$90,dma_mode.w			; DMA status: bit 0 clear = DMA error
	move.w	dma_mode.w,d4
	btst	#0,d4
	beq.s	read_failed
	movem.l	(sp)+,d4-d7/a1
	rts

; FORCE INTERRUPT: stop the FDC, wait a little, read its status (clears the interrupt).
force_interrupt:
	move.w	#$80,dma_mode.w
	move.w	#$d0,d4
	bsr.w	fdc_write
	move.w	#$100,d4
force_interrupt_delay:
	dbra	d4,force_interrupt_delay
	move.w	dma_data.w,d4			; status
	rts

; Drive A, side d2, through PSG port A (register 14), active low: bit 0 clear = side 1,
; bit 1 clear = drive A, bit 2 clear = drive B.  The other bits stay.
select_side:
	move.w	d4,-(sp)
	move.b	#14,psg_select.w
	move.b	psg_select.w,d4			; port A as it is
	andi.b	#$f8,d4
	ori.b	#5,d4				; side 0, drive A on, drive B off
	sub.b	d2,d4				; side 1: bit 0 clear
	move.b	d4,psg_write.w
	move.w	(sp)+,d4
	rts

; Seek to cylinder d0.  The first time, and after an error, RESTORE to track 0 first, so
; that the FDC's track register is right; then SEEK (no verify) when the head is not
; already there.  3 ms steps, as TOS.
seek:
	movem.l	d4/a1,-(sp)
	lea	cylinder(pc),a1			; where the head is, -1 = not known
	tst.w	(a1)
	bpl.s	seek_known
	move.w	#$80,dma_mode.w			; RESTORE
	moveq	#$03,d4
	bsr.s	fdc_write
	bsr.s	wait_fdc
	clr.w	(a1)				; now on track 0
seek_known:
	cmp.w	(a1),d0				; already there?
	beq.s	seek_exit
	move.w	#$86,dma_mode.w			; FDC data register: the cylinder
	move.w	d0,d4
	bsr.s	fdc_write
	move.w	#$80,dma_mode.w			; SEEK
	moveq	#$13,d4
	bsr.s	fdc_write
	bsr.s	wait_fdc
	move.w	d0,(a1)
seek_exit:
	movem.l	(sp)+,d4/a1
	rts

; Wait for the FDC interrupt (with a timeout), then read the status to clear it.
wait_fdc:
	move.l	d7,-(sp)
	move.l	#$200000,d7
wait_fdc_loop:
	btst	#5,gpip.w			; low = the FDC is done
	beq.s	wait_fdc_done
	subq.l	#1,d7
	bne.s	wait_fdc_loop
	bsr.w	force_interrupt			; timed out: stop it
wait_fdc_done:
	move.w	#$80,dma_mode.w			; status register
	move.w	dma_data.w,d4
	move.l	(sp)+,d7
	rts

; Write d4 to the FDC register the DMA mode selects, with a short wait either side (the
; FDC needs time between register accesses).
fdc_write:
	move.w	d7,-(sp)
	moveq	#$20,d7
fdc_write_delay1:
	dbra	d7,fdc_write_delay1
	move.w	d4,dma_data.w
	moveq	#$20,d7
fdc_write_delay2:
	dbra	d7,fdc_write_delay2
	move.w	(sp)+,d7
	rts

; Variables, set at startup in this copy before it goes into the loader.
sectors_per_track:	dc.w	0		; from the boot sector
sides:			dc.w	0
cylinder:		dc.w	-1		; where the head is, -1 = not known
resident_end:

	ifgt	resident_end-resident_start-(RESIDENT_END-RESIDENT)
	fail	the resident reader does not fit in the loader's padding
	endc

;======================================================================
; Copied over unpack_file ($12c6): unpack the file just loaded, at file_vars+$c, and
; clear the 31 bytes after it, as the reissue's unpack_file does.
;======================================================================
unpack_stub:
	movea.l	file_vars+$c.w,a0		; the file's destination
	move.l	8(a0),-(sp)			; its unpacked length, from the Ice header
	jsr	ICE+ice_depack-ice_start	; Pack-Ice unpacks it there
	movea.l	file_vars+$c.w,a0		; the end of the unpacked file
	adda.l	(sp)+,a0
	moveq	#30,d0				; 31 bytes
unpack_clear_loop:
	clr.b	(a0)+
	dbra	d0,unpack_clear_loop
	rts
unpack_stub_end:

;======================================================================
; Pack-Ice 2.40, copied over the Huffman tree work area at ICE ($1914): the in-place
; depacker that comes with Pack-Ice 2.40 (ICE_UNP2.S, by Axe of Superior), position
; independent; icepack packs the files for it.
;======================================================================
ice_start:

;----------------------------------------------------------------------
; Unpack the file at a0 ('ICE!', packed length, unpacked length, data) in place.  The
; bits and literal bytes are read from the end of the packed data backwards and the
; output is written from its end backwards, 120 bytes higher than a0, then moved down.
; The 120 bytes after the output are kept on the stack meanwhile.  Returns the unpacked
; length in d0 and keeps the other registers.
;----------------------------------------------------------------------
ice_depack:
	link	a3,#-120			; room for the 120 bytes after the output
	movem.l	d0-a6,-(sp)
	lea	120(a0),a4			; the output starts 120 bytes above the file
	movea.l	a4,a6
	bsr	ice_get_long
	cmpi.l	#'ICE!',d0			; not packed: leave it
	bne	ice_not_packed
	bsr.s	ice_get_long			; packed length
	lea	-8(a0,d0.l),a5			; a5 = end of the packed data, read backwards
	bsr.s	ice_get_long			; unpacked length
	move.l	d0,(sp)				; (in the saved d0)
	adda.l	d0,a6				; a6 = end of the output, written backwards
	movea.l	a6,a1
	moveq	#119,d0				; keep the 120 bytes after the output
ice_save_loop:
	move.b	-(a1),-(a3)
	dbra	d0,ice_save_loop
	movea.l	a6,a3
	move.b	-(a5),d7			; the first byte of bits, with its end marker
	bsr.s	ice_literals			; unpack
	movea.l	a3,a5

	bsr	ice_get_bit			; a picture (never, for these files)?
	bcc.s	ice_no_picture
	move.w	#$0f9f,d7			; 4000 groups of 4 words, or
	bsr	ice_get_bit
	bcc.s	ice_picture_loop
	moveq	#15,d0				; a count of 16 bits
	bsr	ice_get_bits
	move.w	d1,d7
ice_picture_loop:
	moveq	#3,d6				; 4 words packed bit by bit, back into planes
ice_picture_word_loop:
	move.w	-(a3),d4
	moveq	#3,d5
ice_picture_bit_loop:
	add.w	d4,d4
	addx.w	d0,d0
	add.w	d4,d4
	addx.w	d1,d1
	add.w	d4,d4
	addx.w	d2,d2
	add.w	d4,d4
	addx.w	d3,d3
	dbra	d5,ice_picture_bit_loop
	dbra	d6,ice_picture_word_loop
	movem.w	d0-d3,(a3)
	dbra	d7,ice_picture_loop
ice_no_picture:
	movem.l	(sp),d0-a3			; d0 = unpacked length, a0 = the file, a3 = frame

ice_move_loop:
	move.b	(a4)+,(a0)+			; move the output down by 120
	subq.l	#1,d0
	bne.s	ice_move_loop
	moveq	#119,d0				; put the 120 bytes back
ice_restore_loop:
	move.b	-(a3),-(a5)
	dbra	d0,ice_restore_loop
ice_not_packed:
	movem.l	(sp)+,d0-a6
	unlk	a3
	rts

; d0 = the long at a0, a0 moves past it.
ice_get_long:
	moveq	#3,d1
ice_get_long_loop:
	lsl.l	#8,d0
	move.b	(a0)+,d0
	dbra	d1,ice_get_long_loop
	rts

; One step: a literal run (bit 1), then a match unless the output is complete.
ice_literals:
	bsr.s	ice_get_bit			; literals?
	bcc.s	ice_check_end
	moveq	#0,d1				; one literal,
	bsr.s	ice_get_bit
	bcc.s	ice_literal_loop
	lea	ice_literal_base(pc),a1		; or a count of 2, 2, 3, 8 or 15 bits,
	moveq	#4,d3				; the next size when all its bits are 1
ice_literal_count_loop:
	move.l	-(a1),d0
	bsr.s	ice_get_bits
	swap	d0
	cmp.w	d0,d1
	dbne	d3,ice_literal_count_loop
	add.l	20(a1),d1			; plus the base of that size
ice_literal_loop:
	move.b	-(a5),-(a6)			; the literal bytes, backwards
	dbra	d1,ice_literal_loop
ice_check_end:
	cmpa.l	a4,a6				; all written?
	bgt.s	ice_match
	rts

; The next bit in X (and C): d7 shifts left, a 1 bit left alone marks its end.
ice_get_bit:
	add.b	d7,d7
	bne.s	ice_get_bit_done
	move.b	-(a5),d7			; the next byte, with a new end marker
	addx.b	d7,d7
ice_get_bit_done:
	rts

; d1 = the next d0 + 1 bits, the first highest.
ice_get_bits:
	moveq	#0,d1
ice_get_bits_loop:
	add.b	d7,d7
	bne.s	ice_get_bits_add
	move.b	-(a5),d7
	addx.b	d7,d7
ice_get_bits_add:
	addx.w	d1,d1
	dbra	d0,ice_get_bits_loop
	rts

; A match: its length (up to 4 leading 1 bits pick the entry of ice_length_table), its
; offset (5, 8 or 12 bits, or 6 or 9 for a 2 byte match), then the copy.  An offset of
; -1 repeats the byte after the match.
ice_match:
	lea	ice_length_table(pc),a1
	moveq	#3,d2
ice_match_len_loop:
	bsr.s	ice_get_bit
	dbcc	d2,ice_match_len_loop
	moveq	#0,d4
	moveq	#0,d1
	move.b	1(a1,d2.w),d0			; bits - 1 for the length
	ext.w	d0
	bmi.s	ice_match_len_base
	bsr.s	ice_get_bits
ice_match_len_base:
	move.b	6(a1,d2.w),d4			; plus the base
	add.w	d1,d4
	beq.s	ice_match_short
	lea	ice_offset_table(pc),a1
	moveq	#1,d2
ice_match_offset_loop:
	bsr.s	ice_get_bit
	dbcc	d2,ice_match_offset_loop
	moveq	#0,d1
	move.b	1(a1,d2.w),d0			; bits - 1 for the offset
	ext.w	d0
	bsr.s	ice_get_bits
	add.w	d2,d2
	add.w	6(a1,d2.w),d1			; plus the base
	bpl.s	ice_match_copy
	sub.w	d4,d1				; -1: the byte after the match, repeated
	bra.s	ice_match_copy
ice_match_short:
	moveq	#0,d1				; a 2 byte match: 6 or 9 bit offset
	moveq	#5,d0
	moveq	#-1,d2
	bsr.s	ice_get_bit
	bcc.s	ice_match_short_bits
	moveq	#8,d0
	moveq	#$3f,d2
ice_match_short_bits:
	bsr.s	ice_get_bits
	add.w	d2,d1
ice_match_copy:
	lea	2(a6,d4.w),a1			; copy from further up the output
	adda.w	d1,a1
	move.b	-(a1),-(a6)
ice_match_copy_loop:
	move.b	-(a1),-(a6)
	dbra	d4,ice_match_copy_loop
	bra	ice_literals

; Literal count sizes: (largest value, bits - 1), read from the end backwards.
ice_literal_table:
	dc.l	$7fff000e,$00ff0007,$00070002,$00030001,$00030001
; What each literal count size adds.
ice_literal_base:
	dc.l	270-1,15-1,8-1,5-1,2-1
; Match length: bits - 1, then the base, indexed by the leading 1 bits (-1..3).
ice_length_table:
	dc.b	9,1,0,-1,-1
	dc.b	8,4,2,1,0
; Match offset: bits - 1, then the bases as words.
ice_offset_table:
	dc.b	11,4,7,0
	dc.w	$11f,-1,$1f
	even
ice_end:

	ifgt	ice_end-ice_start-(ICE_END-ICE)
	fail	the depacker does not fit in the Huffman tree work area
	endc

;======================================================================
; Tables and texts.
;======================================================================

; The files, in load table order (level24.bin and level24.gfx once): name as in the
; directory, then where their runs are and their length (filled in at startup).
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

; Names as in a directory entry: 8 characters, 3 for the extension, padded with spaces.
name_title_pic:		dc.b	'TITLE   PIC',0
name_panel_gfx:		dc.b	'PANEL   GFX',0
name_panel_bin:		dc.b	'PANEL   BIN',0
name_sound_prg:		dc.b	'SOUND   PRG',0
name_frontend_bin:	dc.b	'FRONTENDBIN',0
name_frontend_gfx:	dc.b	'FRONTENDGFX',0
name_level1_pic:	dc.b	'LEVEL1  PIC',0
name_level1_bin:	dc.b	'LEVEL1  BIN',0
name_level1a_gfx:	dc.b	'LEVEL1A GFX',0
name_level1b_gfx:	dc.b	'LEVEL1B GFX',0
name_level1_map:	dc.b	'LEVEL1  MAP',0
name_level2_pic:	dc.b	'LEVEL2  PIC',0
name_level24_bin:	dc.b	'LEVEL24 BIN',0
name_level24_gfx:	dc.b	'LEVEL24 GFX',0
name_level2_gfx:	dc.b	'LEVEL2  GFX',0
name_level3_pic:	dc.b	'LEVEL3  PIC',0
name_level3_bin:	dc.b	'LEVEL3  BIN',0
name_level4_pic:	dc.b	'LEVEL4  PIC',0
name_level4_gfx:	dc.b	'LEVEL4  GFX',0
name_level5_pic:	dc.b	'LEVEL5  PIC',0
name_level5_bin:	dc.b	'LEVEL5  BIN',0
name_level5a_gfx:	dc.b	'LEVEL5A GFX',0
name_level5b_gfx:	dc.b	'LEVEL5B GFX',0
name_level5_map:	dc.b	'LEVEL5  MAP',0

; Lines of at most 40 characters, for the low resolution screen.
title_text:
	dc.b	27,'E',27,'f'			; clear the screen, no cursor
	dc.b	'Batman The Movie (Ocean, 1989)',13,10
	dc.b	'File version of the 1 disk reissue',13,10
	dc.b	'by Darren Birks, October 2026',13,10,13,10
	dc.b	'Reads the game files from drive A.',13,10,13,10
	dc.b	'Press a key to start.',0
no_room_text:
	dc.b	13,10,'Not enough room: the files are in too',13,10
	dc.b	'many pieces, or the program lies too',13,10
	dc.b	'high in memory.',13,10,0
bad_disk_text:
	dc.b	13,10,'Drive A has no normal TOS disk.',13,10,0
read_error_text:
	dc.b	13,10,'Cannot read the disk in drive A.',13,10,0
file_missing_text:
	dc.b	13,10,'Not on the disk in drive A:',13,10,0
newline_text:
	dc.b	13,10,0
	even

; The reissue's decrypted game loader: the copy stub for $21000, then the loader for $1000.
loader_bin:
	incbin	"loader.bin"

	section	bss

old_ssp:	ds.l	1			; TOS's supervisor stack, for the error exit
saved_palette:	ds.w	16			; the desktop's colours
cluster_size:	ds.w	1			; from the boot sector
fat_start:	ds.w	1
fat_size:	ds.w	1
root_start:	ds.w	1
root_entries:	ds.w	1
root_size:	ds.w	1
data_start:	ds.w	1			; logical sector of cluster 2
run_buffer:	ds.b	RUNS_END-RUNS		; the runs, as they go into the loader
run_buffer_end:
sector_buffer:	ds.b	512			; the boot sector
fat_buffer:	ds.b	FAT_SECTORS*512		; the FAT
root_buffer:	ds.b	ROOT_SECTORS*512	; the root directory
		ds.b	1024			; stack
stack_top:
program_end:
