; FCOPYPRO.PRG  -  FastCopy PRO 1.2 (Ver. 17.2.94)  (c) 1986-94 Martin Backschat / ICP / ACN
;
; A Turbo C 2.0 program that runs as a program (FCOPYPRO.PRG) or a desk accessory
; (FCOPYPRO.ACC, the same file renamed; start tells them apart by a0 at entry).
;
; Functions of the main dialog (main_tree, object numbers in main_dialog):
;   Copy Disk, New Conf     copy_disk / copy_engine (New Conf rewrites with a new configuration)
;   Scan Disk               scan_disk: bad sector scan, FAT marking, damaged file report
;   Format Disk, Soft Fmt   format_disk: own track layouts, MS-DOS / TOS / optimized, Guardian
;   Streamer                streamer: hard disk partition backup to floppies and restore
;   Directory               show_directory
;   Inspect Disk            inspect_disk: sector editor
;   Image Copy              image_copy: disk to .DIM file and back
;   >> More Options         options_dialog: drives A/B, HD detection, extended memory, retries
;   Save Config.            save_config: writes the config block into the program file
;
; The floppy work is done by an own driver (lock_floppy .. dma_reset_read) that programs
; the WD1772 and the DMA chip directly: track images for Write Track with 9 to 22 sectors
; per track, interleave and skew, Mega STE / TT HD density, retries with recalibration.
; GEMDOS/BIOS are used for hard disk partitions (Rwabs) and files.
;
; The resource is compiled in (RSH): TEDINFOs, the logo BITBLK and 14 object trees in the
; data section, fixed with rsrc_obfix on the first start.  The configuration block
; (config, 112 bytes with the $2442 mark) sits in the data section and is saved back
; into the program file.  Strings are named after their text (alert_* for form_alert).
;
; Turbo C passes the first arguments in d0-d2/a0-a1 and keeps a global's address in a
; register to reach its neighbours as d(An); such operands carry a "-> label" comment.
; Disassembly in Devpac syntax.  Text 50504 bytes, data 23260 bytes, bss 6982 bytes.
;
; The program this source must assemble to (FCOPYPRO.PRG):
;   file size     75979 bytes ($128cb)
;   text          50504 bytes ($c548)
;   data          23260 bytes ($5adc)
;   bss           6982 bytes ($1b46)
;   symbols       0 bytes
;   relocations   2157, table 2187 bytes
;   header flags  $00000001 (fast load)
;   CRC32         $7268805a
;   MD5           0cc3c869a4b9a2317fcb42cd8a435b77
;
; Devpac cannot set the header flags: it always writes the long at file offset 22
; as $00000000, so its output differs from the original in that long only.  The
; program Devpac writes from this source is:
;   header flags  $00000000
;   CRC32         $962a64d4
;   MD5           4742d4fdccb13a7af91e91d876003874
; Change byte 25 of that file from $00 to $01 (fast load) to get the original
; program with the CRC32 and MD5 above.
;
; Add/sub/and/or with an immediate and a data register are dc.w with the instruction
; in the comment: Devpac would assemble them as addi/subi/andi/ori.


	include	EQUATES.S

	section	text


	include	TCSTART.S

;----------------------------------------------------------------------
; Boot sector Guardian.  put_guardian copies guardian_show..read_directory_tree to
; offset $1e of a boot sector and puts "bra.s guardian_entry" at offset 0.  At boot it
; prints guardian_text, or only the bell when Control is held with a Shift key.
;----------------------------------------------------------------------
guardian_show:
	pea	$bffff                          ; Kbshift(-1)
	trap	#13                             ; BIOS
	pea	guardian_bell(pc)
	dc.w	$c03c,$0007                     ; and.b #$7,d0, Control with a Shift key: bell only
	cmp.b	#$4,d0
	bhi.s	guardian_print
	pea	guardian_text(pc)
	bra.s	guardian_print

guardian_entry:
	movea.l	sp,a3
	bra.s	guardian_show

guardian_print:
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	movea.l	a3,sp
	rts

guardian_text:
	dc.b	$07
	dc.b	13,10,'(Ver. 17.2.94)',13,10
	dc.b	$1b
	dc.b	'p                Hello !!               ',13,10
	dc.b	'     I am your personal boot sector    ',13,10
	dc.b	'              GUARDIAN                 ',13,10
	dc.b	'   As long as I display this message   ',13,10
	dc.b	'          the Boot sector is           ',13,10
	dc.b	'       NOT infected by any virus       ',13,10
	dc.b	'---------------------------------------',13,10
	dc.b	'     This guardian was placed on       ',13,10
	dc.b	'    your diskette by FASTCOPY PRO      ',13,10
	dc.b	'   (c) 1986-94 by Martin Backschat     ',13,10
	dc.b	$1b,$71,$0d,$0a,$00
guardian_bell:
	dc.w	$0700

;----------------------------------------------------------------------
; Reads the directory tree of the source disk into the record list at
; $1202e: 26 bytes per entry (parent, name, start cluster, flags and damaged count,
; size).  Used by Scan Disk for the damaged file report.
;----------------------------------------------------------------------
read_directory_tree:
	move.w	d3,-(sp)
	move.l	a2,-(sp)
	movea.l	dir_list_end,a2
	clr.w	d3
	bra.s	.check_bpb_rdlen

.loop_use_bpb_datrec
	suba.l	a0,a0
	move.w	d3,d0
	add.w	bpb+bpb_datrec,d0
	sub.w	bpb+bpb_rdlen,d0
	jsr	read_directory_sector
	tst.b	d0
	beq.s	.finish
	addq.w	#1,d3
.check_bpb_rdlen
	cmp.w	bpb+bpb_rdlen,d3
	bcs.s	.loop_use_bpb_datrec
	movea.l	dir_list_end,a1
	movea.l	a2,a0
	jsr	read_subdirectories
.finish
	movea.l	(sp)+,a2
	move.w	(sp)+,d3
	rts


read_subdirectories:
	movem.l	d3-d5/a2-a4,-(sp)
	movea.l	a0,a2
	movea.l	a1,a4
	bra.w	.loop_test

.loop_read_directory_sector
	move.w	$14(a2),d0
	moveq	#15,d1
	lsr.w	d1,d0
	dc.w	$c07c,$1                        ; and.w #$1,d0
	beq.s	.next
	move.w	$12(a2),d3
	movea.l	dir_list_end,a3
.loop_use_bpb_clsiz
	moveq	#-2,d4
	add.w	d3,d4
	mulu.w	bpb+bpb_clsiz,d4
	add.w	bpb+bpb_datrec,d4
	clr.w	d5
	bra.s	.check_bpb_clsiz

.loop_read_directory_sector2
	movea.l	a2,a0
	move.w	d4,d0
	jsr	read_directory_sector
	tst.b	d0
	beq.s	.result_0
	addq.w	#1,d5
	addq.w	#1,d4
.check_bpb_clsiz
	cmp.w	bpb+bpb_clsiz,d5
	bcs.s	.loop_read_directory_sector2
	moveq	#1,d1
	move.w	d3,d0
	movea.l	fat_buffer,a0
	jsr	get_fat_entry
	move.w	d0,d3
	bne.s	.loop_use_bpb_clsiz
	movea.l	dir_list_end,a1
	movea.l	a3,a0
	jsr	read_subdirectories(pc)
	tst.b	d0
	bne.s	.next
.result_0
	clr.b	d0
	bra.s	.return

.next
	lea	$1a(a2),a2
.loop_test
	cmpa.l	a2,a4
	bne.w	.loop_read_directory_sector
	moveq	#1,d0
.return
	movem.l	(sp)+,d3-d5/a2-a4
	rts


;----------------------------------------------------------------------
; Reads one directory sector d0 and adds its entries, parent a0, to the list.
;----------------------------------------------------------------------
read_directory_sector:
	movem.l	d4/a2-a5,-(sp)                  ; a0 = parent entry, d0 = sector
	movea.l	a0,a4
	lea	dir_list_end,a3
	clr.w	d1                              ; read the sector from the source drive
	move.b	cfg_source_drive,d1
	move.w	d1,-(sp)
	move.w	d0,d2
	clr.w	d0
	movea.l	buffer_start,a0
	moveq	#1,d1
	jsr	Rwabs
	addq.w	#2,sp
	tst.l	d0
	bge.s	.scan
	suba.l	a0,a0                           ; "Read Error on directory entry! [CONT|ABORT]"
	clr.w	d0
	jsr	graf_mouse
	lea	alert_read_error_on_directory_entry,a0
	moveq	#1,d0
	jsr	alert
	move.w	d0,d4
	suba.l	a0,a0
	moveq	#2,d0
	jsr	graf_mouse
	cmp.w	#$1,d4
	bne.s	.failed
	bra.w	.ok

.scan
	movea.l	buffer_start,a2                 ; 16 directory entries per sector
	clr.w	d4
	bra.w	.slot_test

.next_slot
	move.b	(a2),d0                         ; end of the directory
	beq.w	.ok
	cmp.b	#$e5,d0                         ; deleted entries and . / .. are skipped
	beq.w	.next
	cmp.b	#$2e,d0                         ; '.'
	beq.w	.next
	movea.l	(a3),a0                         ; room for a new record?
	lea	$1a(a0),a0
	cmpa.l	buffer_end,a0
	bcs.s	.add_entry
.failed
	clr.b	d0
	bra.w	.return

.add_entry
	clr.w	d0                              ; start cluster (Intel word); empty files are skipped
	move.b	$1a(a2),d0
	clr.w	d1
	move.b	$1b(a2),d1
	lsl.w	#8,d1
	add.w	d1,d0
	movea.l	(a3),a0
	move.w	d0,$12(a0)
	beq.w	.next
	movea.l	(a3),a0                         ; parent
	move.l	a4,(a0)
	moveq	#16,d0                          ; directory flag in bit 15 of the flags word, damaged count 0
	and.b	$b(a2),d0
	beq.s	.file
	moveq	#1,d1
	bra.s	.set_flags

.file
	clr.w	d1
.set_flags
	movea.l	(a3),a0
	andi.w	#$7fff,$14(a0)
	dc.w	$c27c,$1                        ; and.w #$1,d1
	lsl.w	#8,d1
	lsl.w	#7,d1
	or.w	d1,$14(a0)
	movea.l	(a3),a0
	andi.w	#$8000,$14(a0)
	clr.w	d0                              ; size (three bytes are enough)
	move.b	$1c(a2),d0
	ext.l	d0
	clr.w	d1
	move.b	$1d(a2),d1
	ext.l	d1
	lsl.l	#8,d1
	add.l	d1,d0
	clr.w	d2
	move.b	$1e(a2),d2
	ext.l	d2
	moveq	#16,d1
	lsl.l	d1,d2
	add.l	d2,d0
	movea.l	(a3),a0
	move.l	d0,$16(a0)
	movea.l	a2,a1                           ; name: 8 characters, trailing spaces cut
	movea.l	(a3),a0
	addq.w	#4,a0
	moveq	#8,d0
	jsr	memcpy
	movea.l	(a3),a0
	clr.b	$c(a0)
	moveq	#32,d0
	movea.l	(a3),a0
	addq.w	#4,a0
	jsr	strchr
	movea.l	a0,a5
	move.l	a5,d0
	beq.s	.extension
	clr.b	(a0)
.extension
	cmpi.b	#$20,$8(a2)                     ; extension: ".EXT" without spaces
	beq.s	.added
	clr.b	$b(a2)
	move.b	#$2e,$7(a2)                     ; '.'
	moveq	#32,d0
	lea	$8(a2),a0
	jsr	strchr
	movea.l	a0,a5
	move.l	a5,d0
	beq.s	.append_extension
	clr.b	(a0)
.append_extension
	lea	$7(a2),a1
	movea.l	(a3),a0
	addq.w	#4,a0
	jsr	strcat
.added
	addi.l	#$1a,(a3)                       ; next record
.next
	addq.w	#1,d4
	lea	$20(a2),a2
.slot_test
	cmp.w	#$10,d4
	blt.w	.next_slot
.ok
	moveq	#1,d0
.return
	movem.l	(sp)+,d4/a2-a5
	rts


;----------------------------------------------------------------------
; Reads FAT entry d0 from the FAT in a0 (12 or 16 bit after bpb_bflags).  With d1
; set, free (0, 1) and reserved/bad/last entries (>= $fff0) return 0.
;----------------------------------------------------------------------
get_fat_entry:
	movem.l	d3-d5,-(sp)
	moveq	#1,d3
	and.w	bpb+bpb_bflags,d3               ; bpb_bflags bit 0: 16-bit FAT
	tst.w	d3
	beq.s	.fat12
	add.w	d0,d0                           ; FAT16: Intel word at 2 * cluster
	moveq	#0,d2
	move.w	d0,d2
	clr.w	d3
	move.b	$0(a0,d2.l),d3
	move.w	d3,d2
	moveq	#1,d3
	add.w	d0,d3
	moveq	#0,d4
	move.w	d3,d4
	clr.w	d3
	move.b	$0(a0,d4.l),d3
	lsl.w	#8,d3
	add.w	d3,d2
	bra.s	.check_free

.fat12
	move.w	d0,d3                           ; FAT12: 12 bits at 1.5 * cluster
	lsr.w	#1,d3
	add.w	d0,d3
	moveq	#0,d2
	move.w	d3,d2
	clr.w	d4
	move.b	$0(a0,d2.l),d4
	move.w	d4,d2
	moveq	#1,d4
	add.w	d3,d4
	moveq	#0,d5
	move.w	d4,d5
	clr.w	d4
	move.b	$0(a0,d5.l),d4
	lsl.w	#8,d4
	add.w	d4,d2
	moveq	#1,d3                           ; odd cluster: upper 12 bits, even: lower 12 bits
	and.w	d0,d3
	beq.s	.even
	lsr.w	#4,d2
	bra.s	.sign_extend

.even
	dc.w	$c47c,$fff                      ; and.w #$fff,d2
.sign_extend
	cmp.w	#$ff0,d2                        ; $ff0 and higher become $fff0 and higher
	bcs.s	.check_free
	dc.w	$847c,$f000                     ; or.w #$f000,d2
.check_free
	tst.b	d1
	beq.s	.used
	cmp.w	#$2,d2
	bcs.s	.free
	cmp.w	#$fff0,d2
	bcs.s	.used
.free
	clr.w	d0
	bra.s	.return

.used
	move.w	d2,d0
.return
	movem.l	(sp)+,d3-d5
	rts


;----------------------------------------------------------------------
; Writes d1 into FAT entry d0 of the FAT in a0.
;----------------------------------------------------------------------
set_fat_entry:
	movem.l	d3-d5,-(sp)
	moveq	#1,d2                           ; FAT16: Intel word
	and.w	bpb+bpb_bflags,d2
	beq.s	.fat12
	move.w	d0,d2
	add.w	d2,d2
	moveq	#0,d3
	move.w	d2,d3
	move.b	d1,$0(a0,d3.l)
	move.w	d1,d2
	lsr.w	#8,d2
	move.w	d0,d3
	add.w	d3,d3
	addq.w	#1,d3
	moveq	#0,d4
	move.w	d3,d4
	move.b	d2,$0(a0,d4.l)
	bra.s	.return

.fat12
	move.w	d0,d2                           ; FAT12: 12 bits, keeping the nibble of the neighbour
	lsr.w	#1,d2
	add.w	d0,d2
	moveq	#0,d3
	move.w	d2,d3
	clr.w	d4
	move.b	$0(a0,d3.l),d4
	move.w	d4,d3
	moveq	#1,d4
	add.w	d2,d4
	moveq	#0,d5
	move.w	d4,d5
	clr.w	d4
	move.b	$0(a0,d5.l),d4
	lsl.w	#8,d4
	add.w	d4,d3
	moveq	#1,d5
	and.w	d0,d5
	beq.s	.even
	moveq	#15,d0
	and.w	d3,d0
	move.w	d1,d4
	lsl.w	#4,d4
	or.w	d4,d0
	move.w	d0,d3
	bra.s	.store

.even
	move.w	d3,d0
	dc.w	$c07c,$f000                     ; and.w #$f000,d0
	move.w	d1,d4
	dc.w	$c87c,$fff                      ; and.w #$fff,d4
	or.w	d4,d0
	move.w	d0,d3
.store
	moveq	#0,d0
	move.w	d2,d0
	move.b	d3,$0(a0,d0.l)
	move.w	d3,d1
	lsr.w	#8,d1
	moveq	#1,d4
	add.w	d2,d4
	moveq	#0,d5
	move.w	d4,d5
	move.b	d1,$0(a0,d5.l)
.return
	movem.l	(sp)+,d3-d5
	rts


count_damaged_cluster:
	movem.l	d3-d4/a2,-(sp)
	move.w	d0,d4
	movea.l	dir_list,a2
	bra.s	.loop_test

.loop_get_fat_entry
	move.w	$12(a2),d3
.loop_get_fat_entry2
	cmp.w	d3,d4
	bne.s	.get_fat_entry
	move.w	$14(a2),d0
	addq.w	#1,d0
	dc.w	$c07c,$7fff                     ; and.w #$7fff,d0
	andi.w	#$8000,$14(a2)
	or.w	d0,$14(a2)
	bra.s	.return

.get_fat_entry
	moveq	#1,d1
	move.w	d3,d0
	movea.l	fat_buffer,a0
	jsr	get_fat_entry(pc)
	move.w	d0,d3
	bne.s	.loop_get_fat_entry2
	lea	$1a(a2),a2
.loop_test
	cmpa.l	dir_list_end,a2
	bcs.s	.loop_get_fat_entry
.return
	movem.l	(sp)+,d3-d4/a2
	rts


build_report_path:
	movem.l	d3/a2-a3,-(sp)
	lea	-$40(sp),sp
	movea.l	a0,a2                           ; a0 = line buffer, a1 = entry
	movea.l	a1,a3
	moveq	#80,d1                          ; line of 80 dots
	moveq	#46,d0
	jsr	memset
	clr.w	d3                              ; collect the parent chain
	movea.l	a3,a0
	bra.s	.parent_test

.next_parent
	lea	$4(a0),a1
	move.w	d3,d0
	lsl.w	#2,d0
	move.l	a1,$0(sp,d0.w)
	addq.w	#1,d3
.parent_test
	movea.l	(a0),a0
	move.l	a0,d0
	bne.s	.next_parent
	lea	str_backslash,a1                ; path from the root: \dir\dir\name
	movea.l	a2,a0
	jsr	strcpy
	bra.s	.element_test

.next_element
	move.w	d3,d0
	lsl.w	#2,d0
	movea.l	$0(sp,d0.w),a1
	movea.l	a2,a0
	jsr	strcat
	lea	str_backslash,a1
	movea.l	a2,a0
	jsr	strcat
.element_test
	move.w	d3,d0
	subq.w	#1,d3
	tst.w	d0
	bne.s	.next_element
	lea	$4(a3),a1
	movea.l	a2,a0
	jsr	strcat
	movea.l	a2,a0
	jsr	strlen
	move.b	#$20,$0(a2,d0.l)                ; damaged count at column 62, size at column 69
	moveq	#10,d1
	lea	$3e(a2),a0
	move.w	$14(a3),d0
	dc.w	$c07c,$7fff                     ; and.w #$7fff,d0
	jsr	itoa
	movea.l	a2,a0
	jsr	strlen
	move.b	#$2e,$0(a2,d0.l)                ; '.'
	moveq	#10,d1
	lea	$45(a2),a0
	move.l	$16(a3),d0
	jsr	ltoa
	lea	str_newline,a1                  ; line end
	movea.l	a2,a0
	jsr	strcat
	lea	$40(sp),sp
	movem.l	(sp)+,d3/a2-a3
	rts


;----------------------------------------------------------------------
; Streamer, optimized writing: moves the FAT to the start of the free buffer and
; rebuilds the cluster chains so that the used clusters are contiguous.
;----------------------------------------------------------------------
compact_fat:
	movem.l	d3-d5/a2-a4,-(sp)
	lea	bpb,a2
	move.w	(a2),d1
	move.w	$8(a2),d0                       ; -> bpb+bpb_fsiz
	jsr	mul_words
	move.l	d0,d3
	lea	new_fat,a3
	movea.l	buffer_free,a0
	adda.l	d3,a0
	move.l	a0,(a3)
	adda.l	d3,a0
	move.l	a0,-$4(a3)                      ; -> dir_buffer
	moveq	#0,d0
	move.w	$4(a2),d0                       ; -> bpb+bpb_clsizb
	adda.l	d0,a0
	cmpa.l	buffer_end,a0
	bcs.s	.copy_fat
	lea	alert_not_enough_memory_free_for,a0
	moveq	#1,d0
	jsr	alert
	clr.b	d0
	bra.w	.return

.copy_fat
	lea	fat_buffer,a4                   ; old FAT to the free buffer; new_fat holds the old to new cluster mapping
	move.l	d3,d0
	movea.l	(a4),a1
	movea.l	buffer_free,a0
	jsr	memcpy
	move.l	buffer_free,(a4)
	moveq	#2,d3
	move.w	d3,d4
	bra.s	.cluster_test

.next_cluster
	clr.b	d1                              ; each cluster: used clusters get the next new number, bad ones are freed
	move.w	d3,d0
	movea.l	(a4),a0
	jsr	get_fat_entry(pc)
	move.w	d0,d5
	beq.s	.advance
	cmp.w	#$fff0,d0
	bcs.s	.used_cluster
	cmp.w	#$fff8,d0
	bcc.s	.used_cluster
	clr.w	d1
	movea.l	(a4),a0
	move.w	d3,d0
	jsr	set_fat_entry(pc)
	bra.s	.advance

.used_cluster
	cmp.w	d3,d4
	beq.s	.map
	clr.w	d1
	move.w	d3,d0
	movea.l	(a4),a0
	jsr	set_fat_entry(pc)
.map
	move.w	d4,d1
	move.w	d3,d0
	movea.l	(a3),a0
	jsr	set_fat_entry(pc)
	move.w	d5,d1
	move.w	d4,d0
	movea.l	(a4),a0
	jsr	set_fat_entry(pc)
	addq.w	#1,d4
.advance
	addq.w	#1,d3
.cluster_test
	cmp.w	$e(a2),d3                       ; -> bpb+bpb_numcl
	bcs.s	.next_cluster
	moveq	#2,d3                           ; second pass: chains point to the new numbers
	bra.s	.relink_test

.relink
	moveq	#1,d1
	move.w	d3,d0
	movea.l	(a4),a0
	jsr	get_fat_entry(pc)
	move.w	d0,d5
	beq.s	.relink_advance
	clr.b	d1
	movea.l	(a3),a0
	jsr	get_fat_entry(pc)
	move.w	d0,d1
	move.w	d3,d0
	movea.l	(a4),a0
	jsr	set_fat_entry(pc)
.relink_advance
	addq.w	#1,d3
.relink_test
	cmp.w	$e(a2),d3                       ; -> bpb+bpb_numcl
	bcs.s	.relink
	moveq	#1,d0
.return
	movem.l	(sp)+,d3-d5/a2-a4
	rts


;----------------------------------------------------------------------
; Streamer, optimized writing: rewrites the directories after the clusters moved.
;----------------------------------------------------------------------
relocate_root_directory:
	move.w	d3,-(sp)
	clr.w	d3
	bra.s	.check_bpb_rdlen2

.loop_use_bpb_datrec
	move.w	d3,d1
	add.w	bpb+bpb_datrec,d1
	sub.w	bpb+bpb_rdlen,d1
	moveq	#1,d0
	jsr	relocate_directory_sectors
	tst.b	d0
	bne.s	.check_bpb_rdlen
	clr.b	d0
	bra.s	.finish

.check_bpb_rdlen
	addq.w	#1,d3
.check_bpb_rdlen2
	cmp.w	bpb+bpb_rdlen,d3
	bcs.s	.loop_use_bpb_datrec
	moveq	#1,d0
.finish
	move.w	(sp)+,d3
	rts


relocate_directory_chain:
	move.w	d3,-(sp)
	move.w	d0,d3
.loop_use_bpb_clsiz
	moveq	#-2,d1
	add.w	d3,d1
	mulu.w	bpb+bpb_clsiz,d1
	add.w	bpb+bpb_datrec,d1
	move.w	bpb+bpb_clsiz,d0
	jsr	relocate_directory_sectors
	tst.b	d0
	bne.s	.get_fat_entry
	clr.b	d0
	bra.s	.finish

.get_fat_entry
	moveq	#1,d1
	move.w	d3,d0
	movea.l	fat_buffer,a0
	jsr	get_fat_entry(pc)
	move.w	d0,d3
	bne.s	.loop_use_bpb_clsiz
	moveq	#1,d0
.finish
	move.w	(sp)+,d3
	rts


relocate_directory_sectors:
	movem.l	d3-d7/a2-a3,-(sp)               ; d0 sector, d1 count: renumber the start clusters of the entries after compact_fat
	subq.w	#2,sp
	move.w	d0,d3
	move.w	d1,(sp)
	move.w	bpb,d1
	jsr	mul_words
	move.l	d0,d4
	lea	dir_buffer,a2
	movea.l	(a2),a0
	adda.l	d4,a0
	cmpa.l	buffer_end,a0
	bcs.s	.read
	lea	alert_not_enough_memory_free_for,a0
	moveq	#1,d0
	jsr	alert
	bra.w	.failed

.read
	move.w	partition_drive,-(sp)
	move.w	$2(sp),d2
	move.w	d3,d1
	movea.l	(a2),a0
	clr.w	d0
	jsr	Rwabs
	addq.w	#2,sp
	tst.l	d0
	bge.s	.scan
	lea	alert_cannot_read_directory_stop,a0
	moveq	#1,d0
	jsr	alert
	bra.w	.failed

.scan
	movea.l	(a2),a3
	move.l	d4,d7
	lsr.l	#5,d7
	clr.w	d6
	bra.s	.entry_test

.next_entry
	move.b	(a3),d0
	beq.s	.write
	cmp.b	#$e5,d0
	beq.s	.next
	cmp.b	#$2e,d0                         ; '.'
	beq.s	.next
	clr.w	d5
	move.b	$1a(a3),d5
	clr.w	d0
	move.b	$1b(a3),d0
	lsl.w	#8,d0
	add.w	d0,d5
	tst.w	d5
	beq.s	.next
	moveq	#1,d1                           ; new cluster number from the mapping
	movea.l	$4(a2),a0                       ; -> new_fat
	move.w	d5,d0
	jsr	get_fat_entry(pc)
	move.w	d0,d5
	move.b	d5,$1a(a3)
	lsr.w	#8,d0
	move.b	d0,$1b(a3)
	moveq	#16,d1                          ; subdirectories recursively
	and.b	$b(a3),d1
	beq.s	.next
	cmp.w	#$2,d5
	bcs.s	.next
	add.l	d4,(a2)
	move.w	d5,d0
	jsr	relocate_directory_chain(pc)
	tst.b	d0
	beq.s	.failed
	sub.l	d4,(a2)
.next
	addq.w	#1,d6
	lea	$20(a3),a3
.entry_test
	cmp.w	d6,d7
	bgt.s	.next_entry
.write
	move.w	partition_drive,-(sp)
	move.w	$2(sp),d2
	move.w	d3,d1
	movea.l	(a2),a0
	moveq	#1,d0
	jsr	Rwabs
	addq.w	#2,sp
	tst.l	d0
	bge.s	.ok
	lea	alert_cannot_write_directory_stop,a0
	moveq	#1,d0
	jsr	alert
.failed
	clr.b	d0
	bra.s	.return

.ok
	moveq	#1,d0
.return
	addq.w	#2,sp
	movem.l	(sp)+,d3-d7/a2-a3
	rts


	include	FDC.S

;----------------------------------------------------------------------
; Inspect Disk: a sector editor in a window on inspect_tree.  Shows a sector
; of a drive as hex and ASCII, moves through the disk (boot sector, FATs, root
; directory, data, by cluster or logical sector), changes bytes, searches patterns,
; loads and saves sector ranges to files and checks or protects boot sectors.
;----------------------------------------------------------------------
inspect_disk:
	movem.l	d3-d7/a2-a6,-(sp)
	lea	-$164(sp),sp
	move.l	buffer_free,$16(sp)             ; buffers in the free memory: object strings for the 16 hex lines,
	lea	inspect_tree_ptr,a5
	movea.l	$16(sp),a0                      ; the sector buffer at +$480,
	lea	$480(a0),a0
	move.l	a0,-$4(a5)                      ; -> sector_buffer
	movea.l	a0,a4                           ; a search buffer of two sectors after it, and a second one
	lea	$2080(a4),a4
	lea	$2080(a4),a1
	move.l	a1,$20(sp)
	clr.b	(sp)                            ; nothing shown yet, sector not modified
	clr.b	d0
	move.b	d0,$1f(sp)
	move.b	d0,-$a(a5)                      ; -> sector_modified
	moveq	#61,d4                          ; no object to deselect
	move.l	#inspect_tree,(a5)              ; tree pointers of the editor and its boxes
	move.l	#values_tree,$160(sp)
	lea	search_tree,a6
	move.l	#save_tree,$15c(sp)
	move.l	#load_tree,$158(sp)
	move.l	#goto_tree,$154(sp)
	pea	$144(sp)                        ; center the editor; the boxes go in its middle, below the hex area
	pea	$14a(sp)
	pea	$150(sp)
	lea	$156(sp),a1
	movea.l	(a5),a0
	jsr	form_center
	lea	$c(sp),sp
	movea.l	(a5),a0
	move.w	$14(a0),d0
	movea.l	$160(sp),a1
	sub.w	$14(a1),d0
	ext.l	d0
	divs.w	#$2,d0
	add.w	$10(a0),d0
	move.w	d0,$10(a1)
	movea.l	(a5),a0
	move.w	$12(a0),d1
	add.w	$252(a0),d1
	move.w	d1,$12(a1)
	movea.l	$15c(sp),a0
	move.w	d1,$12(a0)
	movea.l	$158(sp),a1
	move.w	d1,$12(a1)
	movea.l	$154(sp),a0
	move.w	d1,$12(a0)
	movea.l	(a5),a1
	move.w	$14(a1),d0
	movea.l	$15c(sp),a0
	sub.w	$14(a0),d0
	ext.l	d0
	divs.w	#$2,d0
	add.w	$10(a1),d0
	move.w	d0,$10(a0)
	movea.l	(a5),a1
	move.w	$14(a1),d1
	movea.l	$158(sp),a0
	sub.w	$14(a0),d1
	ext.l	d1
	divs.w	#$2,d1
	add.w	$10(a1),d1
	move.w	d1,$10(a0)
	movea.l	(a5),a1
	move.w	$14(a1),d0
	movea.l	$154(sp),a0
	sub.w	$14(a0),d0
	ext.l	d0
	divs.w	#$2,d0
	add.w	$10(a1),d0
	move.w	d0,$10(a0)
	movea.l	$160(sp),a1                     ; the search box shows the editor's value line in object 7
	move.l	$24(a1),$b4(a6)                 ; -> search_tree+7*OBJECT_SIZE+ob_spec
	move.w	$14(a6),$13c(sp)                ; -> search_tree+ob_width
	move.w	$16(a6),$13a(sp)                ; -> search_tree+ob_height
	movea.l	(a5),a0
	move.w	$14(a0),d0
	sub.w	$13c(sp),d0
	ext.l	d0
	divs.w	#$2,d0
	add.w	$10(a0),d0
	move.w	d0,$10(a6)                      ; -> search_tree+ob_x
	move.w	d0,$140(sp)
	movea.l	(a5),a0
	move.w	$12(a0),d1
	add.w	$16(a0),d1
	sub.w	$13a(sp),d1
	subq.w	#8,d1
	move.w	d1,$12(a6)                      ; -> search_tree+ob_y
	move.w	d1,$13e(sp)
	movea.l	(a5),a0                         ; text of the sector number field
	movea.l	$27c(a0),a1
	move.l	(a1),$24(sp)
.choose_drive
	lea	bpb,a2                          ; choose a drive
	lea	inspect_drive,a3
	move.b	has_drive_b,d0                  ; single floppy and no hard disk: drive B is the only choice
	bne.s	.drive_box_over_editor
	move.b	no_hard_disk,d1
	beq.s	.drive_box_over_editor
	moveq	#1,d7
	bra.s	.set_drive

.drive_box_over_editor
	move.b	$1f(sp),d0                      ; editor shown: drive box over it, else over the main dialog
	beq.s	.drive_box_over_main
	movea.l	(a5),a1
	moveq	#8,d2
	lea	$1b(a3),a0                      ; -> str_select_drive_to_inspect
	move.w	(a3),d1
	clr.b	d0
	jsr	select_drive
	move.w	d0,d7
	beq.w	.command
	bra.s	.set_drive

.drive_box_over_main
	movea.l	main_tree_ptr,a1
	clr.w	d2
	lea	$1b(a3),a0                      ; -> str_select_drive_to_inspect
	move.w	(a3),d1
	clr.b	d0
	jsr	select_drive
	move.w	d0,d7
	beq.w	.leave
.set_drive
	moveq	#-1,d0                          ; inspect_drive = drive
	add.w	d7,d0
	move.w	d0,(a3)
.restart
	clr.w	d0                              ; start at sector 0
	move.w	d0,-$c(a5)                      ; -> inspect_sector
	move.w	d0,$152(sp)
.read_drive
	move.w	(a3),d0                         ; media change; floppies: read the configuration from the boot sector
	jsr	select_partition
	cmpi.w	#$2,(a3)
	bge.s	.get_bpb
	clr.w	d1
	move.w	(a3),d0
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	jsr	read_disk_config
	tst.w	d0
	bne.w	.leave
.get_bpb
	move.w	(a3),d0                         ; BPB of the drive
	jsr	Getbpb
	movea.l	a0,a1
	movea.l	a2,a0
	moveq	#18,d0
	jsr	memcpy
	move.w	$e(a2),d0                       ; inspect_sectors = data clusters * cluster size + system sectors, -> bpb+bpb_numcl
	mulu.w	$2(a2),d0                       ; -> bpb+bpb_clsiz
	add.w	$6(a2),d0                       ; -> bpb+bpb_rdlen
	move.w	$8(a2),d1                       ; -> bpb+bpb_fsiz
	add.w	d1,d1
	add.w	d1,d0
	addq.w	#1,d0
	move.w	d0,$8(a5)                       ; -> inspect_sectors
	lea	str_drive_x,a1                  ; title line "Drive X, nnn BpS, nnnnn Sectors"
	lea	$10e(sp),a0
	jsr	strcpy
	moveq	#65,d0                          ; drive letter into the title and the messages
	add.b	$1(a3),d0                       ; -> inspect_drive+1
	move.b	d0,$114(sp)
	move.b	d0,-$3d8(a3)                    ; -> alert_drive_x+11
	move.b	d0,-$531(a3)                    ; -> alert_put_boot_sector_guardian_on+47
	move.b	d0,-$572(a3)                    ; -> alert_please_remove_write+52
	lea	$10e(sp),a0
	jsr	strlen
	lea	$10e(sp),a0
	adda.w	d0,a0
	move.w	(a2),d0
	moveq	#10,d1
	jsr	itoa
	lea	str_bps,a1
	lea	$10e(sp),a0
	jsr	strcat
	lea	$10e(sp),a0
	jsr	strlen
	lea	$10e(sp),a0
	adda.w	d0,a0
	moveq	#0,d0
	move.w	$8(a5),d0                       ; -> inspect_sectors
	moveq	#10,d1
	jsr	ltoa
	lea	str_sectors,a1
	lea	$10e(sp),a0
	jsr	strcat
.new_page
	clr.w	d0                              ; cursor and display start to offset 0
	move.w	d0,-$6(a5)                      ; -> display_offset
	move.w	d0,-$8(a5)                      ; -> cursor_offset
.read_sector
	movea.l	-$4(a5),a0                      ; read the sector (with the RETRY/QUIT box), -> sector_buffer
	move.w	-$c(a5),d0                      ; -> inspect_sector
	jsr	read_inspect_sector
	move.w	d0,d5
	beq.s	.sector_read
	subq.w	#1,d0                           ; QUIT
	beq.w	.leave
	move.w	$152(sp),-$c(a5)                ; error: back to the previous sector, -> inspect_sector
	bra.w	.read_drive

.sector_read
	clr.b	-$a(a5)                         ; sector unchanged, -> sector_modified
.set_texts
	lea	$10e(sp),a0                     ; title, offset and position lines into their objects
	movea.l	(a5),a1
	move.l	a0,$2dc(a1)
	lea	$e6(sp),a1
	movea.l	(a5),a0
	move.l	a1,$30c(a0)
	lea	$c8(sp),a0
	movea.l	(a5),a1
	move.l	a0,$33c(a1)
	moveq	#10,d1                          ; sector number into the sector field
	moveq	#0,d0
	move.w	-$c(a5),d0                      ; -> inspect_sector
	movea.l	$24(sp),a0
	jsr	ltoa
	movea.l	(a5),a0                         ; slider position = sector * slider range / sectors
	move.w	$26c(a0),d1
	sub.w	$284(a0),d1
	move.w	-$c(a5),d0                      ; -> inspect_sector
	jsr	mul_words
	moveq	#0,d1
	move.w	$8(a5),d1                       ; -> inspect_sectors
	jsr	ldiv
	movea.l	(a5),a0
	move.w	d0,$280(a0)
.offset_line
	lea	$12(a3),a1                      ; offset line "Offset $xx", -> str_offset
	lea	$e6(sp),a0
	jsr	strcpy
	lea	$e6(sp),a0
	jsr	strlen
	lea	$e6(sp),a0
	adda.w	d0,a0
	move.w	-$8(a5),d0                      ; -> cursor_offset
	moveq	#16,d1
	jsr	itoa
	cmpi.w	#$2,(a3)                        ; floppy: position line " S n Tr nn Sec nn"
	bge.w	.hard_disk_position
	lea	str_s,a1
	lea	$c8(sp),a0
	jsr	strcpy
	lea	$c8(sp),a0
	jsr	strlen
	lea	$c8(sp),a0
	adda.w	d0,a0
	moveq	#0,d0
	move.w	-$c(a5),d0                      ; -> inspect_sector
	divu.w	cfg_sectors,d0
	moveq	#0,d1
	move.w	d0,d1
	move.l	d1,d0
	moveq	#1,d1
	add.w	cfg_sides,d1
	divu.w	d1,d0
	swap	d0
	addq.w	#1,d0
	moveq	#10,d1
	jsr	itoa
	lea	str_tr,a1
	lea	$c8(sp),a0
	jsr	strcat
	lea	$c8(sp),a0
	jsr	strlen
	lea	$c8(sp),a0
	adda.w	d0,a0
	moveq	#0,d0
	move.w	-$c(a5),d0                      ; -> inspect_sector
	moveq	#1,d1
	add.w	cfg_sides,d1
	muls.w	cfg_sectors,d1
	divu.w	d1,d0
	moveq	#10,d1
	jsr	itoa
	lea	str_sec,a1
	lea	$c8(sp),a0
	jsr	strcat
	moveq	#0,d6
	move.w	-$c(a5),d6                      ; -> inspect_sector
	divu.w	cfg_sectors,d6
	swap	d6
	addq.w	#1,d6
	bra.s	.number

.hard_disk_position
	move.w	-$c(a5),d0                      ; hard disk: "System Area" or "Cluster nnnn", -> inspect_sector
	cmp.w	$c(a2),d0                       ; -> bpb+bpb_datrec
	bcc.s	.cluster_position
	lea	str_system_area,a1
	lea	$c8(sp),a0
	jsr	strcpy
	bra.s	.hex_lines

.cluster_position
	lea	str_cluster,a1
	lea	$c8(sp),a0
	jsr	strcpy
	move.w	-$c(a5),d0                      ; -> inspect_sector
	sub.w	$c(a2),d0                       ; -> bpb+bpb_datrec
	moveq	#0,d6
	move.w	d0,d6
	divu.w	$2(a2),d6                       ; -> bpb+bpb_clsiz
	addq.w	#2,d6
.number
	lea	$c8(sp),a0
	jsr	strlen
	lea	$c8(sp),a0
	adda.w	d0,a0
	moveq	#0,d0
	move.w	d6,d0
	moveq	#10,d1
	jsr	ltoa
.hex_lines
	clr.w	d5                              ; build the 16 hex lines of the displayed 256 bytes:
	bra.w	.line_test

.next_line
	move.w	d5,d1
	ext.l	d1
	move.l	d1,d0
	lsl.l	#3,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	$16(sp),a0
	adda.l	d0,a0
	move.l	a0,$1a(sp)
	moveq	#2,d0
	add.w	d5,d0
	ext.l	d0
	move.l	d0,d2
	add.l	d2,d2
	add.l	d0,d2
	lsl.l	#3,d2
	movea.l	(a5),a1
	move.l	a0,$c(a1,d2.l)
	move.w	d5,d7                           ; offset "xxx: ",
	lsl.w	#4,d7
	add.w	-$6(a5),d7                      ; -> display_offset
	move.w	d7,d1
	asr.w	#8,d1
	dc.w	$c27c,$f                        ; and.w #$f,d1
	move.b	$2(a3,d1.w),(a0)                ; -> hex_digits indexed
	move.w	d7,d2
	asr.w	#4,d2
	dc.w	$c47c,$f                        ; and.w #$f,d2
	move.b	$2(a3,d2.w),$1(a0)              ; -> hex_digits indexed
	moveq	#15,d0
	and.w	d7,d0
	move.b	$2(a3,d0.w),$2(a0)              ; -> hex_digits indexed
	move.b	#$3a,$3(a0)                     ; ':'
	moveq	#32,d1
	move.b	d1,$4(a0)
	move.b	d1,$35(a0)
	clr.w	d3
	bra.s	.byte_test

.next_byte
	move.w	d7,d0                           ; 16 bytes as hex, "-" after the 8th,
	add.w	d3,d0
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	move.b	$0(a0,d0.w),d0
	clr.w	d1
	move.b	d0,d1
	asr.w	#4,d1
	dc.w	$c27c,$f                        ; and.w #$f,d1
	moveq	#3,d2
	muls.w	d3,d2
	movea.l	$1a(sp),a1
	move.b	$2(a3,d1.w),$5(a1,d2.w)         ; -> hex_digits indexed
	clr.w	d1
	move.b	d0,d1
	dc.w	$c27c,$f                        ; and.w #$f,d1
	move.b	$2(a3,d1.w),$6(a1,d2.w)         ; -> hex_digits indexed
	cmp.w	#$7,d3
	bne.s	.space_separator
	moveq	#45,d1
	bra.s	.store_separator

.space_separator
	moveq	#32,d1
.store_separator
	moveq	#3,d2
	muls.w	d3,d2
	movea.l	$1a(sp),a0
	move.b	d1,$7(a0,d2.w)
	tst.b	d0
	bne.s	.ascii_char
	moveq	#32,d0
.ascii_char
	movea.l	$1a(sp),a0                      ; and as characters (0 shown as space)
	move.b	d0,$36(a0,d3.w)
	addq.w	#1,d3
.byte_test
	cmp.w	#$10,d3
	blt.s	.next_byte
	movea.l	$1a(sp),a0
	move.b	#$20,$34(a0)
	clr.b	$46(a0)
	addq.w	#1,d5
.line_test
	cmp.w	#$10,d5
	blt.w	.next_line
	move.w	-$6(a5),d0                      ; disable the arrows at the start and end of the disk, -> display_offset
	bne.s	.up_enabled
	move.w	-$c(a5),d1                      ; -> inspect_sector
	beq.s	.up_disabled
.up_enabled
	clr.w	d0
	bra.s	.set_up_state

.up_disabled
	moveq	#8,d0
.set_up_state
	movea.l	(a5),a0
	move.w	d0,$1ea(a0)
	move.w	-$6(a5),d1                      ; -> display_offset
	dc.w	$d27c,$100                      ; add.w #$100,d1
	cmp.w	(a2),d1
	bcs.s	.down_enabled
	moveq	#-1,d2
	add.w	$8(a5),d2                       ; -> inspect_sectors
	movea.w	-$c(a5),a0                      ; -> inspect_sector
	cmpa.w	d2,a0
	bcc.s	.down_disabled
.down_enabled
	clr.w	d0
	bra.s	.set_down_state

.down_disabled
	moveq	#8,d0
.set_down_state
	movea.l	(a5),a0
	move.w	d0,$232(a0)
	move.w	-$c(a5),d1                      ; -> inspect_sector
	beq.s	.left_disabled
	clr.w	d2
	bra.s	.set_left_state

.left_disabled
	moveq	#8,d2
.set_left_state
	movea.l	(a5),a0
	move.w	d2,$24a(a0)
	moveq	#-1,d0
	add.w	$8(a5),d0                       ; -> inspect_sectors
	move.w	-$c(a5),d1                      ; -> inspect_sector
	cmp.w	d0,d1
	bcc.s	.right_disabled
	clr.w	d2
	bra.s	.set_right_state

.right_disabled
	moveq	#8,d2
.set_right_state
	movea.l	(a5),a0
	move.w	d2,$292(a0)
	movea.l	(a5),a0                         ; size and position of the slider of the 512 byte sector
	moveq	#0,d0
	move.w	$20e(a0),d0
	move.w	(a2),d1
	lsr.w	#8,d1
	divu.w	d1,d0
	move.w	d0,$226(a0)
	movea.l	(a5),a0
	move.w	$20e(a0),d1
	sub.w	d0,d1
	move.w	-$6(a5),d0                      ; -> display_offset
	jsr	mul_words
	move.w	(a2),d1
	dc.w	$d27c,$ff00                     ; add.w #$ff00,d1
	moveq	#0,d2
	move.w	d1,d2
	move.l	d2,d1
	jsr	ldiv
	movea.l	(a5),a0
	move.w	d0,$222(a0)
	move.b	$1f(sp),d1                      ; editor already drawn: redraw only the changed objects
	beq.s	.draw_all
	movea.l	(a5),a0
	moveq	#20,d0
	jsr	draw_object
	moveq	#21,d0
	movea.l	(a5),a0
	jsr	draw_object
	moveq	#23,d0
	movea.l	(a5),a0
	jsr	draw_object
	moveq	#1,d0
	movea.l	(a5),a0
	jsr	draw_object
	moveq	#29,d0
	movea.l	(a5),a0
	jsr	draw_object
	moveq	#31,d0
	movea.l	(a5),a0
	jsr	draw_object
	moveq	#33,d0
	movea.l	(a5),a0
	jsr	draw_object
	moveq	#25,d0
	movea.l	(a5),a0
	jsr	draw_object
	moveq	#24,d0
	movea.l	(a5),a0
	jsr	draw_object
	moveq	#27,d0
	movea.l	(a5),a0
	jsr	draw_object
	bra.s	.draw_cursor

.draw_all
	move.b	#$1,$1f(sp)                     ; first time: draw the whole editor
	clr.w	d0
	movea.l	(a5),a0
	jsr	draw_object
.draw_cursor
	jsr	inspect_draw_cursor             ; cursor
.command
	cmp.w	#$3d,d4                         ; command loop
	bge.s	.form_do
	move.w	d4,d0
	movea.l	(a5),a0
	jsr	deselect_object
.form_do
	pea	-$280(a3)                       ; help text and keyboard shortcuts, -> str_undo_return_to_main_menu_jump
	lea	-$2cc(a3),a1                    ; -> keys_inspect
	moveq	#26,d0
	movea.l	(a5),a0
	jsr	form_do                         ; d4 = object clicked or key code
	addq.w	#4,sp
	move.w	d0,d4
	move.w	-$c(a5),$152(sp)                ; remember the sector, -> inspect_sector
	dc.w	$907c,$12                       ; sub.w #$12,d0
	cmp.w	#$62,d0
	bhi.w	.hex_click
	add.w	d0,d0
	move.w	.table(pc,d0.w),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	.other_drive-.table,.sector_0-.table,.page_up-.table,.offset_bar-.table
	dc.w	.offset_slider-.table,.page_down-.table,.previous_sector-.table,.slider_bar-.table
	dc.w	.sector_field-.table,.next_sector-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.boot-.table,.fat_1-.table,.fat_2-.table
	dc.w	.root-.table,.data-.table,.end-.table,.show_word-.table
	dc.w	.show_word-.table,.change-.table,.search-.table,.search_next-.table
	dc.w	.write_button-.table,.main_menu-.table,.save-.table,.load-.table
	dc.w	.hex_click-.table,.analyse-.table,.protect-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.jump_to_entry-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.clr_home-.table,.cursor_up-.table,.hex_click-.table
	dc.w	.hex_click-.table,.cursor_left-.table,.hex_click-.table,.cursor_right-.table
	dc.w	.hex_click-.table,.hex_click-.table,.cursor_down-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.hex_click-.table,.hex_click-.table,.hex_click-.table
	dc.w	.hex_click-.table,.track_back-.table,.track_on-.table
.jump_to_entry
	move.w	-$8(a5),d5                      ; key $3d (F3): jump to the start cluster of the directory entry under the cursor, -> cursor_offset
	move.w	-$8(a5),d0                      ; -> cursor_offset
	ext.l	d0
	divs.w	#$10,d0
	swap	d0
	sub.w	d0,d5
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	move.b	$0(a0,d5.w),d1
	bne.s	.entry_cluster
	cmp.w	#$10,d5
	blt.s	.not_on_entry
	move.b	-$10(a0,d5.w),d2
	bne.s	.previous_line
.not_on_entry
	lea	alert_in_order_to_jump_to_a,a0  ; "In order to jump to a directory entry put the cursor onto the filename!"
	moveq	#1,d0
	jsr	alert
	bra.w	.command

.previous_line
	dc.w	$9a7c,$10                       ; sub.w #$10,d5
.entry_cluster
	movea.l	-$4(a5),a0                      ; start cluster (Intel word at +$1a) to logical sector, -> sector_buffer
	clr.w	d6
	move.b	$1a(a0,d5.w),d6
	clr.w	d0
	move.b	$1b(a0,d5.w),d0
	lsl.w	#8,d0
	add.w	d0,d6
	moveq	#-2,d1
	add.w	d6,d1
	mulu.w	$2(a2),d1                       ; -> bpb+bpb_clsiz
	add.w	$c(a2),d1                       ; -> bpb+bpb_datrec
	move.w	d1,d6
	bra.w	.go_sector

.show_word
	move.w	-$8(a5),d0                      ; C->S and I->M: show the word under the cursor, -> cursor_offset
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	clr.w	d6
	move.b	$0(a0,d0.w),d6
	clr.w	d1
	move.b	$1(a0,d0.w),d1
	lsl.w	#8,d1
	add.w	d1,d6
	cmp.w	#$2a,d4
	bne.s	.as_cluster
	lea	str_motorola_word,a1            ; I->M: as Motorola word
	lea	$28(sp),a0
	jsr	strcpy
	movea.l	$154(sp),a0
	ori.w	#$8,$52(a0)
	bra.s	.show_value

.as_cluster
	lea	str_logical_sector,a1           ; C->S: as cluster, converted to its logical sector
	lea	$28(sp),a0
	jsr	strcpy
	moveq	#-2,d0
	add.w	d6,d0
	mulu.w	$2(a2),d0                       ; -> bpb+bpb_clsiz
	add.w	$c(a2),d0                       ; -> bpb+bpb_datrec
	move.w	d0,d6
	movea.l	$154(sp),a0
	andi.w	#$fff7,$52(a0)
.show_value
	lea	$28(sp),a0
	jsr	strlen
	lea	$28(sp,d0.w),a0
	moveq	#0,d0
	move.w	d6,d0
	moveq	#10,d1
	jsr	ltoa
	lea	str_hex_open,a1                 ; " ($hex)" after the decimal value
	lea	$28(sp),a0
	jsr	strcat
	lea	$28(sp),a0
	jsr	strlen
	lea	$28(sp,d0.w),a0
	moveq	#0,d0
	move.w	d6,d0
	moveq	#16,d1
	jsr	ltoa
	lea	str_hex_close,a1
	lea	$28(sp),a0
	jsr	strcat
	lea	$28(sp),a0
	movea.l	$154(sp),a1
	move.l	a0,$3c(a1)
	moveq	#7,d0                           ; message box with OK and GOTO
	jsr	Cconout
	clr.w	d0
	movea.l	$154(sp),a0
	jsr	draw_object
	pea	-$20(a3)                        ; -> str_return_ok_g_goto
	lea	-$5(a3),a1                      ; -> keys_goto
	clr.w	d0
	movea.l	$158(sp),a0
	jsr	form_do
	addq.w	#4,sp
	move.w	d0,d5
	movea.l	$154(sp),a0
	jsr	deselect_object
	movea.l	$154(sp),a0
	move.w	$16(a0),-(sp)
	move.w	$14(a0),-(sp)
	move.w	$12(a0),-(sp)
	move.w	$10(a0),d2
	moveq	#8,d1
	clr.w	d0
	movea.l	(a5),a0
	jsr	objc_draw
	addq.w	#6,sp
	cmp.w	#$3,d5                          ; GOTO: go to that sector
	beq.w	.go_sector
	bra.w	.command

.write_button
	move.b	#$1,-$a(a5)                     ; Write: write the sector back (asks first), -> sector_modified
	moveq	#1,d0
	jsr	write_inspect_sector
	bra.w	.command

.main_menu
	clr.b	d0                              ; Main Menu: offer to write a modified sector, then leave
	jsr	write_inspect_sector
.leave
	move.b	$1f(sp),d0
	beq.w	.return
	movea.l	(a5),a0
	move.w	d4,d0
	jsr	deselect_object
	clr.w	d0
	movea.l	main_tree_ptr,a0
	jsr	draw_object
	bra.w	.return

.sector_0
	clr.b	d0                              ; button 19: back to sector 0 of the drive
	jsr	write_inspect_sector
	bra.w	.restart

.other_drive
	clr.b	d0                              ; button D: another drive
	jsr	write_inspect_sector
	bra.w	.choose_drive

.page_down
	clr.w	$142(sp)                        ; down arrow: next 256 bytes, or the next sector
.page_down_keep
	move.w	-$6(a5),d0                      ; -> display_offset
	dc.w	$d07c,$100                      ; add.w #$100,d0
	cmp.w	(a2),d0
	bcc.s	.next_sector_page
	addi.w	#$100,-$6(a5)                   ; -> display_offset
	bra.s	.set_cursor

.next_sector_page
	moveq	#-1,d0
	add.w	$8(a5),d0                       ; -> inspect_sectors
	move.w	-$c(a5),d1                      ; -> inspect_sector
	cmp.w	d0,d1
	bne.s	.next_sector_top
.at_limit
	moveq	#7,d0
	jsr	Cconout
	bra.w	.command

.next_sector_top
	clr.w	-$6(a5)                         ; -> display_offset
	move.w	$142(sp),-$8(a5)                ; -> cursor_offset
	bra.s	.go_next

.page_up
	clr.w	$142(sp)                        ; up arrow: previous 256 bytes, or the previous sector
.page_up_keep
	move.w	-$6(a5),d0                      ; -> display_offset
	beq.s	.previous_sector_end
	subi.w	#$100,-$6(a5)                   ; -> display_offset
.set_cursor
	move.w	-$6(a5),d0                      ; -> display_offset
	add.w	$142(sp),d0
	move.w	d0,-$8(a5)                      ; -> cursor_offset
	bra.w	.offset_line

.previous_sector_end
	move.w	-$c(a5),d0                      ; -> inspect_sector
	beq.s	.at_limit
	move.w	(a2),d1
	add.w	$142(sp),d1
	dc.w	$d27c,$ff00                     ; add.w #$ff00,d1
	move.w	d1,-$8(a5)                      ; -> cursor_offset
	dc.w	$c27c,$ff00                     ; and.w #$ff00,d1
	move.w	d1,-$6(a5)                      ; -> display_offset
	bra.s	.go_previous

.previous_sector
	move.w	-$c(a5),d0                      ; left arrow: previous sector, -> inspect_sector
	beq.s	.at_limit
	clr.w	d1
	move.w	d1,-$6(a5)                      ; -> display_offset
	move.w	d1,-$8(a5)                      ; -> cursor_offset
.go_previous
	clr.b	d0
	jsr	write_inspect_sector
	subq.w	#1,-$c(a5)                      ; -> inspect_sector
	bra.w	.read_sector

.next_sector
	moveq	#-1,d0                          ; right arrow: next sector
	add.w	$8(a5),d0                       ; -> inspect_sectors
	move.w	-$c(a5),d1                      ; -> inspect_sector
	cmp.w	d0,d1
	beq.w	.at_limit
	clr.w	d2
	move.w	d2,-$6(a5)                      ; -> display_offset
	move.w	d2,-$8(a5)                      ; -> cursor_offset
.go_next
	clr.b	d0
	jsr	write_inspect_sector
	addq.w	#1,-$c(a5)                      ; -> inspect_sector
	bra.w	.read_sector

.boot
	clr.w	d6                              ; B: boot sector
	bra.s	.go_sector

.fat_1
	moveq	#1,d6                           ; F1: first FAT
	bra.s	.go_sector

.fat_2
	moveq	#1,d6                           ; F2: second FAT
	add.w	$8(a2),d6                       ; -> bpb+bpb_fsiz
	bra.s	.go_sector

.root
	move.w	$8(a2),d6                       ; R: root directory, -> bpb+bpb_fsiz
	add.w	d6,d6
	addq.w	#1,d6
	bra.s	.go_sector

.data
	move.w	$c(a2),d6                       ; D: first data sector, -> bpb+bpb_datrec
	bra.s	.go_sector

.end
	moveq	#-1,d6                          ; E: last sector
	add.w	$8(a5),d6                       ; -> inspect_sectors
.go_sector
	clr.b	d0                              ; go to sector d6
	jsr	write_inspect_sector
	moveq	#1,d0
	add.w	d6,d0
	move.w	d0,-$c(a5)                      ; -> inspect_sector
	bra.s	.check_sector

.sector_field
	movea.l	$24(sp),a0                      ; sector number field edited
	jsr	atol
	move.l	d0,d6
.check_sector
	clr.b	d0
	jsr	write_inspect_sector
	cmp.w	-$c(a5),d6                      ; unchanged: the field was dragged as slider; position in 1/1000, -> inspect_sector
	bne.s	.check_range
	clr.w	d2
	moveq	#26,d1
	moveq	#25,d0
	movea.l	(a5),a0
	jsr	graf_slidebox
	move.w	$8(a5),d1                       ; -> inspect_sectors
	jsr	mul_words
	move.l	#$3e8,d1
	jsr	ldiv
	move.w	d0,-$c(a5)                      ; -> inspect_sector
	cmp.w	$8(a5),d0                       ; -> inspect_sectors
	bcs.w	.new_page
	bra.s	.clamp_last

.check_range
	cmp.w	$8(a5),d6                       ; -> inspect_sectors
	bcs.w	.show_loaded
.clamp_last
	moveq	#-1,d0                          ; clamp to the last sector
	add.w	$8(a5),d0                       ; -> inspect_sectors
	move.w	d0,-$c(a5)                      ; -> inspect_sector
	bra.w	.new_page

.slider_bar
	pea	mouse_state                     ; click into the sector slider bar: a track (10 sectors on a hard disk) back or on
	pea	mouse_state
	lea	mouse_state,a1
	lea	$140(sp),a0
	jsr	graf_mkstate
	addq.w	#8,sp
	pea	mouse_state
	lea	$13a(sp),a1
	moveq	#26,d0
	movea.l	(a5),a0
	jsr	objc_offset
	addq.w	#4,sp
.track_step
	clr.b	d0
	jsr	write_inspect_sector
	cmpi.w	#$2,(a3)
	bge.s	.hard_disk_step
	move.w	cfg_sectors,d5
	bra.s	.slider_step

.hard_disk_step
	moveq	#10,d5
.slider_step
	move.w	$138(sp),d0
	cmp.w	$136(sp),d0
	bge.s	.step_on
	cmp.w	-$c(a5),d5                      ; -> inspect_sector
	bhi.s	.to_first
	sub.w	d5,-$c(a5)                      ; -> inspect_sector
	bra.w	.new_page

.to_first
	clr.w	-$c(a5)                         ; -> inspect_sector
	bra.w	.new_page

.step_on
	move.w	$8(a5),d0                       ; -> inspect_sectors
	sub.w	d5,d0
	move.w	-$c(a5),d1                      ; -> inspect_sector
	cmp.w	d0,d1
	bcc.w	.clamp_last
	add.w	d5,-$c(a5)                      ; -> inspect_sector
	bra.w	.new_page

.offset_bar
	pea	mouse_state                     ; click into the offset slider bar: page up or down
	pea	mouse_state
	lea	$13e(sp),a1
	lea	mouse_state,a0
	jsr	graf_mkstate
	addq.w	#8,sp
	pea	$138(sp)
	lea	mouse_state,a1
	moveq	#22,d0
	movea.l	(a5),a0
	jsr	objc_offset
	addq.w	#4,sp
	clr.w	$142(sp)
	move.w	$136(sp),d0
	cmp.w	$138(sp),d0
	blt.w	.page_up_keep
	bra.w	.page_down_keep

.offset_slider
	move.w	(a2),d1                         ; offset slider dragged
	lsr.w	#8,d1
	subq.w	#1,d1
	move.w	d1,-(sp)
	moveq	#1,d2
	moveq	#21,d0
	movea.l	(a5),a0
	moveq	#22,d1
	jsr	graf_slidebox
	move.w	(sp)+,d1
	jsr	mul_words
	move.l	#$3e8,d1
	jsr	ldiv
	lsl.w	#8,d0
	move.w	d0,-$8(a5)                      ; -> cursor_offset
	move.w	d0,-$6(a5)                      ; -> display_offset
	bra.w	.offset_line

.track_on
	move.w	#$1,$138(sp)                    ; Control right: a track on
	clr.w	$136(sp)
	bra.w	.track_step

.track_back
	clr.w	$138(sp)                        ; Control left: a track back
	move.w	#$1,$136(sp)
	bra.w	.track_step

.cursor_right
	move.w	-$6(a5),d0                      ; cursor right, -> display_offset
	dc.w	$d07c,$ff                       ; add.w #$ff,d0
	move.w	-$8(a5),d1                      ; -> cursor_offset
	cmp.w	d0,d1
	bge.w	.page_down
	jsr	inspect_draw_cursor
	addq.w	#1,-$8(a5)                      ; -> cursor_offset
.show_cursor
	jsr	inspect_draw_cursor             ; redraw the cursor and the offset line
	lea	$12(a3),a1                      ; -> str_offset
	lea	$e6(sp),a0
	jsr	strcpy
	lea	$e6(sp),a0
	jsr	strlen
	lea	$e6(sp),a0
	adda.w	d0,a0
	move.w	-$8(a5),d0                      ; -> cursor_offset
	moveq	#16,d1
	jsr	itoa
	moveq	#31,d0
	movea.l	(a5),a0
	jsr	draw_object
	bra.w	.command

.cursor_left
	move.w	-$8(a5),d0                      ; cursor left, -> cursor_offset
	cmp.w	-$6(a5),d0                      ; -> display_offset
	ble.s	.left_previous_page
	jsr	inspect_draw_cursor
	subq.w	#1,-$8(a5)                      ; -> cursor_offset
	bra.s	.show_cursor

.left_previous_page
	move.w	#$ff,$142(sp)
	bra.w	.page_up_keep

.cursor_down
	moveq	#16,d0                          ; cursor down
	add.w	-$8(a5),d0                      ; -> cursor_offset
	move.w	-$6(a5),d1                      ; -> display_offset
	dc.w	$d27c,$100                      ; add.w #$100,d1
	cmp.w	d1,d0
	bge.s	.down_to_next
	jsr	inspect_draw_cursor
	addi.w	#$10,-$8(a5)                    ; -> cursor_offset
	bra.w	.show_cursor

.down_to_next
	move.w	-$8(a5),d0                      ; -> cursor_offset
	ext.l	d0
	divs.w	#$10,d0
	swap	d0
	move.w	d0,$142(sp)
	bra.w	.page_down_keep

.cursor_up
	moveq	#-16,d0                         ; cursor up
	add.w	-$8(a5),d0                      ; -> cursor_offset
	cmp.w	-$6(a5),d0                      ; -> display_offset
	blt.s	.up_to_previous
	jsr	inspect_draw_cursor
	subi.w	#$10,-$8(a5)                    ; -> cursor_offset
	bra.w	.show_cursor

.up_to_previous
	move.w	-$8(a5),d0                      ; -> cursor_offset
	ext.l	d0
	divs.w	#$10,d0
	swap	d0
	dc.w	$d07c,$f0                       ; add.w #$f0,d0
	move.w	d0,$142(sp)
	bra.w	.page_up_keep

.load
	clr.b	d0                              ; Load: load a file to a sector (load_tree)
	jsr	write_inspect_sector
	moveq	#10,d1
	movea.l	$158(sp),a0
	movea.l	$24(a0),a1
	movea.l	(a1),a0
	moveq	#0,d0
	move.w	-$c(a5),d0                      ; -> inspect_sector
	jsr	ltoa
	clr.w	d0
	movea.l	$158(sp),a0
	jsr	draw_object
.load_dialog
	moveq	#7,d0
	jsr	Cconout
	pea	-$304(a3)                       ; -> str_undo_cancel_predefined_sector
	lea	-$308(a3),a1                    ; -> keys_load
	moveq	#1,d0
	movea.l	$15c(sp),a0
	jsr	form_do
	addq.w	#4,sp
	move.w	d0,d5
	movea.l	$158(sp),a0
	jsr	deselect_object
	movea.l	$158(sp),a0
	move.w	$16(a0),-(sp)
	move.w	$14(a0),-(sp)
	move.w	$12(a0),-(sp)
	move.w	$10(a0),d2
	moveq	#8,d1
	clr.w	d0
	movea.l	(a5),a0
	jsr	objc_draw
	addq.w	#6,sp
	cmp.w	#$3,d5
	beq.w	.command
	moveq	#1,d0                           ; start sector, with the sector macros
	movea.l	$158(sp),a0
	jsr	parse_sector_number
	move.w	d0,d6
	cmp.w	$8(a5),d6                       ; -> inspect_sectors
	bcc.s	.load_dialog
	jsr	inspect_draw_cursor
	move.l	(a5),-(sp)                      ; file selector
	pea	str_all_names
	lea	$8(sp),a1
	lea	str_select_file_to_load_from,a0
	jsr	file_selector
	addq.w	#8,sp
	clr.w	d5
	move.b	d0,d5
	jsr	inspect_draw_cursor
	tst.w	d5
	beq.w	.command
	clr.w	d0
	lea	(sp),a0
	jsr	Fopen
	move.w	d0,$e(sp)
	bge.s	.load_file
	lea	-$51c(a3),a0                    ; -> alert_cannot_open_file_abort
	moveq	#1,d0
	jsr	alert
	bra.w	.command

.load_file
	suba.l	a0,a0                           ; read the file sector by sector and write it to the disk
	moveq	#2,d0
	jsr	graf_mouse
	move.w	d6,-$c(a5)                      ; -> inspect_sector
	bra.s	.load_test

.load_next
	moveq	#0,d0
	move.w	(a2),d0
	move.l	d0,-(sp)
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	move.l	d0,d1
	move.w	$12(sp),d0
	jsr	Fread
	cmp.l	(sp)+,d0
	beq.s	.load_write
	move.w	$e(sp),d0
	jsr	Fclose
	bra.s	.load_done

.load_write
	moveq	#2,d0
	jsr	write_inspect_sector
	addq.w	#1,-$c(a5)                      ; -> inspect_sector
.load_test
	move.w	-$c(a5),d0                      ; -> inspect_sector
	cmp.w	$8(a5),d0                       ; -> inspect_sectors
	bcs.s	.load_next
.load_done
	move.w	$e(sp),d0
	jsr	Fclose
	suba.l	a0,a0
	clr.w	d0
	jsr	graf_mouse
.show_loaded
	move.w	d6,-$c(a5)                      ; -> inspect_sector
	bra.w	.new_page

.save
	clr.b	d0                              ; Save: save a sector range to a file (save_tree)
	jsr	write_inspect_sector
	moveq	#10,d1
	movea.l	$15c(sp),a0
	movea.l	$24(a0),a1
	movea.l	(a1),a0
	moveq	#0,d0
	move.w	-$c(a5),d0                      ; -> inspect_sector
	jsr	ltoa
.save_dialog
	moveq	#7,d0
	jsr	Cconout
	clr.w	d0
	movea.l	$15c(sp),a0
	jsr	draw_object
.save_form
	pea	-$304(a3)                       ; -> str_undo_cancel_predefined_sector
	lea	-$30c(a3),a1                    ; -> keys_save
	moveq	#1,d0
	movea.l	$160(sp),a0
	jsr	form_do
	addq.w	#4,sp
	move.w	d0,d5
	movea.l	$15c(sp),a0
	jsr	deselect_object
	movea.l	$15c(sp),a0
	move.w	$16(a0),-(sp)
	move.w	$14(a0),-(sp)
	move.w	$12(a0),-(sp)
	move.w	$10(a0),d2
	moveq	#8,d1
	clr.w	d0
	movea.l	(a5),a0
	jsr	objc_draw
	addq.w	#6,sp
	cmp.w	#$4,d5
	beq.w	.command
	moveq	#1,d0                           ; first sector
	movea.l	$15c(sp),a0
	jsr	parse_sector_number
	move.w	d0,$150(sp)
	cmp.w	$8(a5),d0                       ; -> inspect_sectors
	bcs.s	.save_last
	moveq	#7,d0
	jsr	Cconout
	bra.s	.save_form

.save_last
	moveq	#2,d0                           ; last sector; out of range: set it to the last sector of the disk
	movea.l	$15c(sp),a0
	jsr	parse_sector_number
	move.w	d0,d6
	cmp.w	$150(sp),d6
	bcs.s	.save_clamp
	cmp.w	$8(a5),d0                       ; -> inspect_sectors
	bcs.s	.save_file
.save_clamp
	moveq	#10,d1
	movea.l	$15c(sp),a0
	movea.l	$3c(a0),a1
	movea.l	(a1),a0
	moveq	#-1,d0
	add.w	$8(a5),d0                       ; -> inspect_sectors
	moveq	#0,d2
	move.w	d0,d2
	move.l	d2,d0
	jsr	ltoa
	bra.w	.save_dialog

.save_file
	jsr	inspect_draw_cursor             ; file selector, Fcreate
	move.l	(a5),-(sp)
	pea	str_all_names
	lea	$8(sp),a1
	lea	str_select_file_to_save_to,a0
	jsr	file_selector
	addq.w	#8,sp
	clr.w	d5
	move.b	d0,d5
	suba.l	a0,a0
	moveq	#2,d0
	jsr	graf_mouse
	jsr	inspect_draw_cursor
	tst.w	d5
	beq.s	.save_done
	clr.w	d0
	lea	(sp),a0
	jsr	Fcreate
	move.w	d0,$e(sp)
	bge.s	.save_test
	lea	-$51c(a3),a0                    ; -> alert_cannot_open_file_abort
	moveq	#1,d0
	jsr	alert
	bra.s	.save_done

.save_next
	movea.l	a4,a0                           ; read each sector and write it to the file
	move.w	$150(sp),d0
	jsr	read_inspect_sector
	move.w	d0,d5
	beq.s	.save_write
	subq.w	#1,d0
	beq.s	.save_close
.save_write
	moveq	#0,d0
	move.w	(a2),d0
	move.l	d0,-(sp)
	movea.l	a4,a0
	move.l	d0,d1
	move.w	$12(sp),d0
	jsr	Fwrite
	cmp.l	(sp)+,d0
	beq.s	.save_advance
	lea	-$4fa(a3),a0                    ; -> alert_cannot_write_file_abort
	moveq	#1,d0
	jsr	alert
	bra.s	.save_close

.save_advance
	addq.w	#1,$150(sp)
.save_test
	cmp.w	$150(sp),d6
	bcc.s	.save_next
.save_close
	move.w	$e(sp),d0
	jsr	Fclose
.save_done
	suba.l	a0,a0
	clr.w	d0
	jsr	graf_mouse
	bra.w	.command

.search_next
	moveq	#1,d0                           ; Next: search on from the byte after the cursor
	add.w	-$8(a5),d0                      ; -> cursor_offset
	move.w	d0,$14(sp)
	moveq	#10,d1
	movea.l	$3c(a6),a0                      ; -> search_tree+2*OBJECT_SIZE+ob_spec
	movea.l	(a0),a0
	moveq	#0,d0
	move.w	$8(a5),d0                       ; -> inspect_sectors
	subq.l	#1,d0
	jsr	ltoa
	bra.s	.search_start

.search
	clr.w	$14(sp)                         ; Search: search from the start of the range
.search_start
	clr.b	$10(sp)
	clr.b	d0
	jsr	write_inspect_sector
	jsr	inspect_draw_cursor
.search_box
	ori.w	#$80,$e0(a6)                    ; search box (search_tree); the progress line is hidden while it is edited, -> search_tree+9*OBJECT_SIZE+ob_flags
	moveq	#10,d1
	movea.l	$24(a6),a0                      ; -> search_tree+1*OBJECT_SIZE+ob_spec
	movea.l	(a0),a0
	moveq	#0,d0
	move.w	-$c(a5),d0                      ; -> inspect_sector
	jsr	ltoa
	move.w	$14(sp),d0
	bne.s	.search_show
	move.b	#$1,$10(sp)
	moveq	#7,d0
	jsr	Cconout
	clr.w	d0
	movea.l	a6,a0
	jsr	draw_object
.search_show
	andi.w	#$ff7f,$e0(a6)                  ; -> search_tree+9*OBJECT_SIZE+ob_flags
.search_ask
	move.w	$14(sp),d0                      ; F1 toggles Ignore Case
	bne.s	.search_range
.search_form
	pea	-$372(a3)                       ; -> str_f1_toggle_ignore_case_undo
	lea	-$379(a3),a1                    ; -> keys_search
	moveq	#1,d0
	movea.l	a6,a0
	jsr	form_do
	addq.w	#4,sp
	move.w	d0,d5
	subq.w	#4,d0
	beq.s	.search_form
	moveq	#1,d1                           ; Ignore Case check box
	and.b	$6b(a6),d1                      ; -> search_tree+4*OBJECT_SIZE+11
	move.b	d1,$11(sp)
	movea.l	a6,a0
	move.w	d5,d0
	jsr	deselect_object
	cmp.w	#$6,d5
	bne.s	.search_range
.search_close
	move.b	$10(sp),d0
	beq.w	.draw_cursor
	move.w	$13a(sp),-(sp)
	move.w	$13e(sp),-(sp)
	move.w	$142(sp),-(sp)
	move.w	$146(sp),d2
	moveq	#8,d1
	movea.l	(a5),a0
	clr.w	d0
	jsr	objc_draw
	addq.w	#6,sp
	bra.w	.draw_cursor

.search_range
	moveq	#1,d0                           ; sector range
	movea.l	a6,a0
	jsr	parse_sector_number
	move.w	d0,$150(sp)
	cmp.w	$8(a5),d0                       ; -> inspect_sectors
	bcs.s	.search_last
	moveq	#7,d0
	jsr	Cconout
	bra.w	.search_ask

.search_last
	moveq	#2,d0
	movea.l	a6,a0
	jsr	parse_sector_number
	move.w	d0,d6
	cmp.w	$150(sp),d6
	bcs.s	.search_clamp
	cmp.w	$8(a5),d0                       ; -> inspect_sectors
	bcs.s	.search_pattern
.search_clamp
	moveq	#10,d1
	movea.l	$3c(a6),a0                      ; -> search_tree+2*OBJECT_SIZE+ob_spec
	movea.l	(a0),a0
	moveq	#-1,d0
	add.w	$8(a5),d0                       ; -> inspect_sectors
	moveq	#0,d2
	move.w	d0,d2
	move.l	d2,d0
	jsr	ltoa
	bra.w	.search_box

.search_pattern
	movea.l	$cc(a6),a0                      ; pattern from the value line, -> search_tree+8*OBJECT_SIZE+ob_spec
	movea.l	(a0),a1
	lea	$78(sp),a0
	jsr	parse_values
	move.w	d0,$12(sp)
	beq.w	.search_close
	move.b	$11(sp),d1                      ; Ignore Case: lower case pattern
	beq.s	.search_clear
	lea	$78(sp),a0
	jsr	to_lower
.search_clear
	move.w	$12(sp),d1                      ; empty overlap area in front of the search buffer
	ext.l	d1
	clr.w	d0
	movea.l	a4,a0
	jsr	memset
	clr.b	$1e(sp)
	bra.w	.search_test

.search_sector
	clr.w	d0                              ; search loop over the sectors: Esc or Space stops it
	jsr	check_keyboard
	subq.w	#1,d0
	beq.w	.search_close
	move.w	$14(sp),d0
	beq.s	.search_read
	moveq	#0,d0                           ; Next on the current sector: search the sector in memory
	move.w	(a2),d0
	movea.l	-$4(a5),a1                      ; -> sector_buffer
	move.w	$12(sp),d1
	lea	$0(a4,d1.w),a0
	jsr	memcpy
	bra.s	.search_progress

.search_read
	move.w	$12(sp),d0                      ; else read the sector behind the overlap
	lea	$0(a4,d0.w),a0
	move.w	$150(sp),d0
	jsr	read_inspect_sector
	move.w	d0,d5
	beq.s	.search_progress
	subq.w	#1,d0
	bne.w	.search_advance
	bra.w	.search_close

.search_progress
	moveq	#10,d1                          ; "Searching in Sector nnnnn"
	movea.l	$12c(a6),a0                     ; -> search_tree+12*OBJECT_SIZE+ob_spec
	moveq	#0,d0
	move.w	$150(sp),d0
	jsr	ltoa
	move.b	$10(sp),d0
	beq.s	.search_case
	move.b	$1e(sp),d1
	addq.b	#1,$1e(sp)
	tst.b	d1
	beq.s	.progress_object
	moveq	#11,d0
	bra.s	.draw_progress

.progress_object
	moveq	#9,d0
.draw_progress
	movea.l	a6,a0
	jsr	draw_object
.search_case
	move.b	$11(sp),d0                      ; Ignore Case: lower case copy of the sector
	beq.s	.search_from_cursor
	moveq	#0,d0
	move.w	(a2),d0
	move.w	$12(sp),d1
	lea	$0(a4,d1.w),a1
	movea.l	$20(sp),a0
	jsr	memcpy
	move.w	(a2),d0
	move.w	$12(sp),d1
	lea	$0(a4,d1.w),a0
	jsr	to_lower
.search_from_cursor
	move.w	$14(sp),d0                      ; search from the cursor
	beq.s	.search_whole
	pea	$78(sp)
	move.w	$16(sp),d1
	moveq	#0,d2
	move.w	(a2),d2
	lea	$0(a4,d2.l),a1
	adda.w	d1,a1
	lea	$0(a4,d0.w),a0
	adda.w	d1,a0
	move.w	d1,d0
	jsr	search_buffer
	addq.w	#4,sp
	move.w	d0,d5
	blt.s	.not_found_here
	move.w	$14(sp),d1
	add.w	$12(sp),d1
	add.w	d1,d5
	bra.s	.found

.not_found_here
	clr.w	$14(sp)
	move.b	#$1,$10(sp)
	clr.w	d0
	movea.l	a6,a0
	jsr	draw_object
	bra.w	.keep_tail

.search_whole
	pea	$78(sp)                         ; search the sector (with the end of the previous one)
	move.w	$16(sp),d0
	move.w	$16(sp),d1
	moveq	#0,d2
	move.w	(a2),d2
	lea	$0(a4,d2.l),a1
	adda.w	d1,a1
	movea.l	a4,a0
	jsr	search_buffer
	addq.w	#4,sp
	move.w	d0,d5
	blt.w	.keep_tail
	lea	alert_pattern_found_ok_cont,a0  ; "Pattern found! [OK|CONT]"
	moveq	#1,d0
	jsr	request_alert
	subq.w	#1,d0
	bne.w	.keep_tail
.found
	move.w	$150(sp),-$c(a5)                ; show the sector with the cursor on the pattern, -> inspect_sector
	clr.b	$1e(sp)
	sub.w	$12(sp),d5
	tst.w	d5
	blt.s	.found_previous
	moveq	#0,d0
	move.w	(a2),d0
	move.l	d0,-(sp)
	move.b	$15(sp),d1
	beq.s	.copy_search_buffer
	movea.l	$24(sp),a1
	bra.s	.copy_found_sector

.copy_search_buffer
	move.w	$16(sp),d0
	lea	$0(a4,d0.w),a1
.copy_found_sector
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	move.l	(sp)+,d0
	jsr	memcpy
	bra.s	.show_found

.found_previous
	move.b	#$1,$1e(sp)                     ; pattern starts in the previous sector
	subq.w	#1,-$c(a5)                      ; -> inspect_sector
	add.w	(a2),d5
.show_found
	move.w	d5,d0
	dc.w	$c07c,$ff00                     ; and.w #$ff00,d0
	move.w	d0,-$6(a5)                      ; -> display_offset
	move.w	d5,-$8(a5)                      ; -> cursor_offset
	move.b	$10(sp),d1
	beq.s	.found_new_sector
	move.w	$13a(sp),-(sp)
	move.w	$13e(sp),-(sp)
	move.w	$142(sp),-(sp)
	move.w	$146(sp),d2
	movea.l	(a5),a0
	clr.w	d0
	moveq	#8,d1
	jsr	objc_draw
	addq.w	#6,sp
.found_new_sector
	move.b	$1e(sp),d0
	bne.w	.read_sector
	bra.w	.set_texts

.keep_tail
	move.w	$12(sp),d0                      ; not here: keep the end of the sector for patterns across sectors
	ext.l	d0
	moveq	#0,d1
	move.w	(a2),d1
	lea	$0(a4,d1.l),a1
	movea.l	a4,a0
	jsr	memcpy
.search_advance
	addq.w	#1,$150(sp)
.search_test
	cmp.w	$150(sp),d6
	bcc.w	.search_sector
	lea	alert_pattern_not_found_ok,a0   ; "Pattern not found!"
	moveq	#1,d0
	jsr	alert
	bra.w	.search_close

.clr_home
	jsr	inspect_draw_cursor             ; Clr Home: start of the sector, or its end when already at the start
	move.w	-$6(a5),d5                      ; -> display_offset
	move.w	-$8(a5),d0                      ; -> cursor_offset
	beq.s	.to_end
	clr.w	d1
	move.w	d1,-$8(a5)                      ; -> cursor_offset
	move.w	d1,-$6(a5)                      ; -> display_offset
	bra.s	.home_redraw

.to_end
	moveq	#-1,d0
	add.w	(a2),d0
	move.w	d0,-$8(a5)                      ; -> cursor_offset
	dc.w	$c07c,$ff00                     ; and.w #$ff00,d0
	move.w	d0,-$6(a5)                      ; -> display_offset
.home_redraw
	cmp.w	-$6(a5),d5                      ; -> display_offset
	bne.w	.offset_line
	bra.w	.show_cursor

.change
	moveq	#7,d0                           ; Change: enter values at the cursor (values_tree)
	jsr	Cconout
	clr.w	d0
	movea.l	$160(sp),a0
	jsr	draw_object
	pea	-$31b(a3)                       ; -> str_undo_cancel
	lea	-$31f(a3),a1                    ; -> keys_values
	moveq	#4,d0
	movea.l	$164(sp),a0
	jsr	form_do
	addq.w	#4,sp
	move.w	d0,d5
	movea.l	$160(sp),a0
	jsr	deselect_object
	movea.l	$160(sp),a0
	move.w	$16(a0),-(sp)
	move.w	$14(a0),-(sp)
	move.w	$12(a0),-(sp)
	move.w	$10(a0),d2
	moveq	#8,d1
	clr.w	d0
	movea.l	(a5),a0
	jsr	objc_draw
	addq.w	#6,sp
	cmp.w	#$2,d5
	bne.w	.command
	movea.l	$160(sp),a0                     ; OK: parse them into the sector
	movea.l	$6c(a0),a1
	movea.l	(a1),a1
	move.w	-$8(a5),d0                      ; -> cursor_offset
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	adda.w	d0,a0
	jsr	parse_values
	move.b	#$1,-$a(a5)                     ; sector modified, -> sector_modified
	bra.w	.offset_line

.protect
	cmpi.w	#$2,(a3)                        ; Protect: floppies only
	blt.s	.protect_floppy
.floppies_only
	lea	alert_analyse_protect_work_only,a0 ; "Analyse/Protect work only with boot-sectors of diskettes."
	moveq	#1,d0
	jsr	alert
	bra.w	.command

.protect_floppy
	clr.b	d0
	jsr	write_inspect_sector
	move.w	(a3),d0
	jsr	force_media_change
	lea	-$560(a3),a0                    ; "Put Boot-Sector Guardian on selected Drive X: ?", -> alert_put_boot_sector_guardian_on
	moveq	#1,d0
	jsr	request_alert
	subq.w	#1,d0
	bne.w	.command
	movea.l	-$4(a5),a0                      ; read the boot sector, put the Guardian in and write it, -> sector_buffer
	clr.w	d0
	move.w	d0,-$c(a5)                      ; -> inspect_sector
	jsr	read_inspect_sector
	move.w	d0,d5
	beq.s	.put_guardian
.read_failed
	cmp.w	#$1,d5
	bne.w	.read_drive
	bra.w	.leave

.put_guardian
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	jsr	put_guardian
.write_back
	moveq	#2,d0
	jsr	write_inspect_sector
	bra.w	.restart

.analyse
	cmpi.w	#$2,(a3)                        ; Analyse: floppies only; read the boot sector
	bge.s	.floppies_only
	clr.b	d0
	jsr	write_inspect_sector
	move.w	(a3),d0
	jsr	force_media_change
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	clr.w	d0
	move.w	d0,-$c(a5)                      ; -> inspect_sector
	jsr	read_inspect_sector
	move.w	d0,d5
	bne.s	.read_failed
	lea	-$3e3(a3),a1                    ; "[1][ Drive X:| The Boot-Sector| ...", -> alert_drive_x
	lea	$28(sp),a0
	jsr	strcpy
	lea	-$4d7(a3),a1                    ; -> str_the_boot_sector
	lea	$28(sp),a0
	jsr	strcat
	jsr	analyse_boot_sector             ; analyse it: 0 no virus, 1 not executable but maybe a sleeping virus,
	tst.w	d0                              ; 2 executable without virus (Guardian), 3 executable and maybe a virus
	beq.s	.no_virus
	subq.w	#1,d0
	beq.s	.sleeping_virus
	subq.w	#1,d0
	beq.s	.executable_clean
	subq.w	#1,d0
	beq.w	.maybe_virus
	bra.w	.command

.no_virus
	lea	-$4c4(a3),a1                    ; "contains NO VIRUS! [GREAT]", -> str_contains_no_virus_great
	lea	$28(sp),a0
	jsr	strcat
.show_result
	lea	$28(sp),a0
	moveq	#1,d0
	jsr	alert
.redisplay
	move.w	$152(sp),d0
	beq.w	.set_texts
	clr.w	d1
	move.w	d1,-$6(a5)                      ; -> display_offset
	move.w	d1,-$8(a5)                      ; -> cursor_offset
	bra.w	.set_texts

.executable_clean
	lea	-$455(a3),a1                    ; "is executable but contains NO VIRUS! [GREAT]", -> str_is_executable_but_contains_no
	lea	$28(sp),a0
	jsr	strcat
	bra.s	.show_result

.sleeping_virus
	lea	-$4a7(a3),a1                    ; "is NOT executable but maybe contains a sleeping VIRUS! [OK|CLEAR|PROTECT]", -> str_is_not_executable_but_maybe
	lea	$28(sp),a0
	jsr	strcat
.ask_clear
	lea	$28(sp),a0
	moveq	#1,d0
	jsr	alert
	move.w	d0,d5
	subq.w	#1,d0
	beq.s	.redisplay
	cmp.w	#$3,d5                          ; PROTECT: put the Guardian on
	beq.w	.put_guardian
	moveq	#0,d1                           ; CLEAR: clear the boot code and make the sector not executable
	move.w	(a2),d1
	clr.w	d0
	movea.l	-$4(a5),a0                      ; -> sector_buffer
	lea	$1e(a0),a0
	jsr	memset
	move.l	-$4(a5),$14c(sp)                ; -> sector_buffer
	move.w	(a2),d3
	lsr.w	#1,d3
	subq.w	#1,d3
	clr.w	d5
	move.w	d5,$150(sp)
	bra.s	.sum_test

.sum_next
	movea.l	$14c(sp),a0
	addq.l	#2,$14c(sp)
	add.w	(a0),d5
	addq.w	#1,$150(sp)
.sum_test
	cmp.w	$150(sp),d3
	bhi.s	.sum_next
	movea.l	$14c(sp),a0
	move.w	d5,(a0)
	bra.w	.write_back

.maybe_virus
	lea	-$426(a3),a1                    ; "is executable and MAYBE contains a VIRUS! [OK|CLEAR|PROTECT]", -> str_is_executable_and_maybe
	lea	$28(sp),a0
	jsr	strcat
	bra.s	.ask_clear

.hex_click
	cmp.w	#$2,d4                          ; click into a hex line: cursor to the clicked byte
	blt.w	.command
	cmp.w	#$11,d4
	bgt.w	.command
	jsr	inspect_click_offset
	moveq	#61,d4
	bra.w	.show_cursor

.return
	lea	$164(sp),sp
	movem.l	(sp)+,d3-d7/a2-a6
	rts


to_lower:
	bra.s	.count                          ; d0 bytes at a0 to lower case

.next_char
	move.b	(a0)+,d1
	cmp.b	#$41,d1                         ; 'A'
	bcs.s	.count
	cmp.b	#$5a,d1                         ; 'Z'
	bhi.s	.count
	moveq	#32,d2
	add.b	d1,d2
	move.b	d2,-$1(a0)
.count
	subq.w	#1,d0
	bge.s	.next_char
	rts


parse_sector_number:
	move.l	a2,-(sp)                        ; number of an edit field, or a sector macro: c current, b boot, f1 / f2 FATs, r root, d data, e end
	movea.l	a0,a2
	ext.l	d0
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	lsl.l	#3,d1
	movea.l	$c(a2,d1.l),a1
	movea.l	(a1),a2
	lea	bpb,a0
	clr.w	d2
	move.b	(a2),d2
	moveq	#11,d1
	lea	.table(pc),a1
.find_macro
	cmp.w	(a1)+,d2
	dbeq	d1,.find_macro
	bne.w	.number
	move.w	$16(a1),d2
	jmp	.table(pc,d2.w)

.table
	dc.w	$42,$43,$44,$45,$46,$52,$62,$63
	dc.w	$64,$65,$66,$72
	dc.w	.boot-.table,.current-.table,.data-.table,.end-.table
	dc.w	.fat-.table,.root-.table,.boot-.table,.current-.table
	dc.w	.data-.table,.end-.table,.fat-.table,.root-.table
.current
	move.w	inspect_sector,d0
	bra.s	.return

.boot
	clr.w	d0
	bra.s	.return

.fat
	cmpi.b	#$31,$1(a2)                     ; '1'
	bne.s	.fat_2
	moveq	#1,d0
	bra.s	.return

.fat_2
	moveq	#1,d0
	add.w	$8(a0),d0                       ; -> bpb+bpb_fsiz
	bra.s	.return

.root
	move.w	$8(a0),d0                       ; -> bpb+bpb_fsiz
	add.w	d0,d0
	addq.w	#1,d0
	bra.s	.return

.data
	move.w	$c(a0),d0                       ; -> bpb+bpb_datrec
	bra.s	.return

.end
	moveq	#-1,d0
	add.w	inspect_sectors,d0
	bra.s	.return

.number
	movea.l	a2,a0
	jsr	atol
.return
	movea.l	(sp)+,a2
	rts


analyse_boot_sector:
	movem.l	d3-d4/a2-a3,-(sp)
	movea.l	sector_buffer,a2
	movea.l	a2,a0
	jsr	is_boot_executable
	move.b	d0,d3
	lea	guardian_show,a3
	lea	read_directory_tree,a0
	move.l	a0,d0
	sub.l	a3,d0
	movea.l	a3,a1
	lea	$1e(a2),a0
	jsr	memcmp
	tst.w	d0
	beq.s	.guardian
	clr.b	d4
	bra.s	.search_marker

.guardian
	moveq	#1,d4
.search_marker
	pea	virus_marker
	moveq	#4,d0
	moveq	#0,d1
	move.w	bpb,d1
	lea	$0(a2,d1.l),a1
	lea	$1e(a2),a0
	jsr	search_buffer
	addq.w	#4,sp
	dc.w	$c07c,$1                        ; and.w #$1,d0
	beq.s	.no_marker
	clr.b	d0
	bra.s	.decide

.no_marker
	moveq	#1,d0
.decide
	tst.b	d3
	bne.s	.executable
	tst.b	d0
	beq.s	.no_virus
	tst.b	d4
	beq.s	.sleeping_virus
.no_virus
	clr.w	d0
	bra.s	.return

.sleeping_virus
	moveq	#1,d0
	bra.s	.return

.executable
	tst.b	d4
	beq.s	.maybe_virus
	moveq	#2,d0
	bra.s	.return

.maybe_virus
	moveq	#3,d0
.return
	movem.l	(sp)+,d3-d4/a2-a3
	rts


search_buffer:
	movem.l	d3/a2-a4,-(sp)                  ; searches d0 bytes (pattern on the stack) from a0 to a1; returns the offset or -1
	movea.l	a0,a2
	movea.l	a1,a4
	move.w	d0,d3
	movea.l	a0,a3
	bra.s	.position_test

.compare
	move.w	d3,d0
	ext.l	d0
	movea.l	$14(sp),a1
	movea.l	a3,a0
	jsr	memcmp
	tst.w	d0
	bne.s	.next
	move.l	a3,d0
	sub.l	a2,d0
	bra.s	.return

.next
	addq.w	#1,a3
.position_test
	movea.l	a4,a0
	suba.w	d3,a0
	cmpa.l	a0,a3
	bcs.s	.compare
	moveq	#-1,d0
.return
	movem.l	(sp)+,d3/a2-a4
	rts


read_inspect_sector:
	movem.l	d3-d4/a2-a3,-(sp)
	lea	-$50(sp),sp
	move.w	d0,d3
	movea.l	a0,a2
.loop_use_inspect_drive
	lea	alert_drive_x,a3
	move.w	$3e3(a3),-(sp)                  ; -> inspect_drive
	move.w	d3,d2
	moveq	#1,d1
	movea.l	a2,a0
	clr.w	d0
	jsr	Rwabs
	addq.w	#2,sp
	tst.l	d0
	beq.s	.finish
	movea.l	a3,a1
	lea	(sp),a0
	jsr	strcpy
	lea	$f(a3),a1                       ; -> str_read_error_on_sector
	lea	(sp),a0
	jsr	strcat
	lea	(sp),a0
	jsr	strlen
	lea	$0(sp,d0.w),a0
	moveq	#0,d0
	move.w	d3,d0
	moveq	#10,d1
	jsr	ltoa
	lea	$3e(a3),a1                      ; -> str_ok_retry_quit
	lea	(sp),a0
	jsr	strcat
	lea	(sp),a0
	moveq	#1,d0
	jsr	alert
	move.w	d0,d4
	subq.w	#2,d0
	beq.s	.loop_use_inspect_drive
	cmp.w	#$3,d4
	bne.s	.result_2
	moveq	#1,d0
	bra.s	.return

.result_2
	moveq	#2,d0
	bra.s	.return

.finish
	clr.w	d0
.return
	lea	$50(sp),sp
	movem.l	(sp)+,d3-d4/a2-a3
	rts


write_inspect_sector:
	move.l	d3,-(sp)                        ; d0: 0 ask if modified, 1 ask "Write Sector?", 2 write without asking
	move.l	a2,-(sp)
	lea	-$50(sp),sp
	move.b	d0,d3
	clr.w	d0
	move.b	sector_modified,d0
	clr.b	sector_modified
	cmp.b	#$2,d3
	beq.s	.write
	tst.w	d0
	beq.w	.done
	tst.b	d3
	beq.s	.ask_modified
	lea	alert_write_sector_ok_cancel,a0
	moveq	#1,d0
	jsr	request_alert
	bra.s	.answer

.ask_modified
	lea	alert_sector_has_been_modified,a0
	moveq	#1,d0
	jsr	alert
.answer
	subq.w	#2,d0
	beq.w	.done
.write
	lea	alert_please_remove_write,a2    ; write it
	move.w	$5a6(a2),-(sp)                  ; -> inspect_drive
	move.w	inspect_sector,d2
	moveq	#1,d1
	movea.l	sector_buffer,a0
	moveq	#1,d0
	jsr	rwabs_checked
	addq.w	#2,sp
	move.l	d0,d3
	tst.w	d3
	bge.s	.done
	cmp.w	#$fff3,d3                       ; write protected: "Please remove WRITE-PROTECTION"
	bne.s	.write_error
	movea.l	a2,a0
	moveq	#1,d0
	jsr	alert
	subq.w	#1,d0
	bne.s	.done
	bra.s	.write

.write_error
	lea	$1c3(a2),a1                     ; "[1][ Drive X:| Write Error on Sector nnn ][ ABORT | RETRY ]", -> alert_drive_x
	lea	(sp),a0
	jsr	strcpy
	lea	$1e9(a2),a1                     ; -> str_write_error_on_sector
	lea	(sp),a0
	jsr	strcat
	lea	(sp),a0
	jsr	strlen
	lea	$0(sp,d0.w),a0
	moveq	#0,d0
	move.w	inspect_sector,d0
	moveq	#10,d1
	jsr	ltoa
	lea	$219(a2),a1                     ; -> str_abort_retry
	lea	(sp),a0
	jsr	strcat
	lea	(sp),a0
	moveq	#1,d0
	jsr	alert
	subq.w	#2,d0
	beq.w	.write
.done
	lea	$50(sp),sp
	movea.l	(sp)+,a2
	move.l	(sp)+,d3
	rts


;----------------------------------------------------------------------
; Parses a list of values for a sector change (values_tree): decimal, $hex,
; "text" and empty fields, written to a0.
;----------------------------------------------------------------------
parse_values:
	movem.l	d3-d4/a2-a4,-(sp)               ; a0 = destination, a1 = text; returns the number of bytes
	movea.l	a0,a2
	movea.l	a1,a4
	movea.l	a0,a3
.next_value
	move.b	(a4),d3                         ; per value: "text", $hex, number, or an empty field (0)
	clr.w	d0
	move.b	d3,d0
	dc.w	$907c,$22                       ; sub.w #$22,d0
	beq.s	.text
	subq.w	#2,d0
	beq.s	.hex
	subq.w	#8,d0
	beq.s	.empty
	bra.w	.decimal

.text
	addq.w	#1,a4                           ; "text": its characters
	bra.s	.text_next

.text_char
	move.b	d3,(a2)+
.text_next
	move.b	(a4)+,d3
	cmp.b	#$22,d3                         ; '"'
	beq.s	.text_end
	tst.b	d3
	bne.s	.text_char
.text_end
	tst.b	d3
	bne.w	.to_comma
	subq.w	#1,a4
	bra.w	.to_comma

.empty
	clr.b	(a2)+                           ; empty field: one 0 byte
	bra.w	.to_comma

.hex
	clr.b	d4                              ; $hex: digits and letters A..F
.hex_digit
	addq.w	#1,a4
	move.b	(a4),d3
	cmp.b	#$30,d3                         ; '0'
	bcs.s	.hex_letter
	cmp.b	#$39,d3                         ; '9'
	bhi.s	.hex_letter
	move.b	d4,d0
	lsl.b	#4,d0
	move.b	d3,d1
	dc.w	$d23c,$00d0                     ; add.b #$d0,d1
	or.b	d1,d0
	move.b	d0,d4
	bra.s	.hex_digit

.hex_letter
	cmp.b	#$5a,d3                         ; 'Z'
	bls.s	.hex_upper
	dc.w	$963c,$0020                     ; sub.b #$20,d3
.hex_upper
	cmp.b	#$41,d3                         ; 'A'
	bcs.s	.store
	cmp.b	#$46,d3                         ; 'F'
	bhi.s	.store
	move.b	d4,d0
	lsl.b	#4,d0
	move.b	d3,d1
	dc.w	$d23c,$00c9                     ; add.b #$c9,d1
	or.b	d1,d0
	move.b	d0,d4
	bra.s	.hex_digit

.decimal
	cmp.b	#$30,d3                         ; decimal (also negative) with atoi
	bcs.s	.not_digit
	cmp.b	#$39,d3                         ; '9'
	bls.s	.number
.not_digit
	cmp.b	#$2d,d3                         ; '-'
	beq.s	.number
	moveq	#7,d0                           ; anything else: bell, stop
	jsr	Cconout
	bra.s	.done

.number
	movea.l	a4,a0
	jsr	atoi
	move.w	d0,d4
.store
	move.b	d4,(a2)+
.to_comma
	move.b	(a4)+,d3                        ; on to the next comma
	cmp.b	#$2c,d3                         ; ','
	beq.s	.value_test
	tst.b	d3
	bne.s	.to_comma
.value_test
	tst.b	d3
	bne.w	.next_value
.done
	move.l	a2,d0
	sub.l	a3,d0
	movem.l	(sp)+,d3-d4/a2-a4
	rts


inspect_click_offset:
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	subq.w	#4,sp
	movea.l	inspect_tree_ptr,a2             ; line from the mouse y over the hex lines
	lea	$30(a2),a2
	lea	$2(sp),a3
	pea	(sp)
	movea.l	a3,a1
	moveq	#2,d0
	movea.l	inspect_tree_ptr,a0
	jsr	objc_offset
	addq.w	#4,sp
	move.w	mouse_y,d0
	sub.w	(sp),d0
	ext.l	d0
	divs.w	$16(a2),d0
	move.w	d0,(sp)
	move.w	mouse_x,d1                      ; column from the mouse x
	sub.w	(a3),d1
	ext.l	d1
	divs.w	char_width,d1
	move.w	d1,(a3)
	subq.w	#5,d1                           ; left of the hex: byte 0
	bge.s	.hex_area
	clr.w	(a3)
	bra.s	.clamp

.hex_area
	cmpi.w	#$35,(a3)                       ; hex area: three columns per byte
	bge.s	.between
	moveq	#-5,d0
	add.w	(a3),d0
	ext.l	d0
	divs.w	#$3,d0
	move.w	d0,(a3)
	bra.s	.clamp

.between
	cmpi.w	#$36,(a3)                       ; between hex and characters: byte 15
	bge.s	.ascii_area
	move.w	#$f,(a3)
	bra.s	.clamp

.ascii_area
	addi.w	#$ffca,(a3)                     ; character area: one column per byte
.clamp
	cmpi.w	#$f,(a3)
	ble.s	.set_cursor
	move.w	#$f,(a3)
.set_cursor
	jsr	inspect_draw_cursor             ; move the cursor there
	move.w	(sp),d0
	lsl.w	#4,d0
	add.w	(a3),d0
	add.w	display_offset,d0
	move.w	d0,cursor_offset
	addq.w	#4,sp
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


inspect_draw_cursor:
	movem.l	d3-d4/a2-a4,-(sp)
	subq.w	#4,sp
	lea	$2(sp),a2
	pea	(a2)
	lea	$4(sp),a1
	moveq	#2,d0
	movea.l	inspect_tree_ptr,a0
	jsr	objc_offset
	addq.w	#4,sp
	jsr	linea_defaults
	moveq	#2,d0
	jsr	set_write_mode
	clr.w	d1
	clr.w	d0
	lea	fill_solid,a0
	jsr	set_fill_pattern
	move.w	cursor_offset,d3
	sub.w	display_offset,d3
	movea.l	inspect_tree_ptr,a3
	lea	$30(a3),a3
	move.w	d3,d0
	ext.l	d0
	divs.w	#$10,d0
	muls.w	$16(a3),d0
	add.w	d0,(a2)
	lea	char_width,a4
	moveq	#5,d4
	muls.w	(a4),d4
	add.w	(sp),d4
	move.w	d3,d1
	ext.l	d1
	divs.w	#$10,d1
	swap	d1
	muls.w	(a4),d1
	muls.w	#$3,d1
	add.w	d1,d4
	move.w	(a2),d2
	add.w	$16(a3),d2
	move.w	d2,-(sp)
	move.w	(a4),d2
	add.w	d2,d2
	add.w	d4,d2
	move.w	d4,d0
	move.w	(a2),d1
	jsr	filled_rect
	addq.w	#2,sp
	moveq	#54,d4
	muls.w	(a4),d4
	add.w	(sp),d4
	move.w	d3,d0
	ext.l	d0
	divs.w	#$10,d0
	swap	d0
	muls.w	(a4),d0
	add.w	d0,d4
	move.w	(a2),d1
	add.w	$16(a3),d1
	move.w	d1,-(sp)
	move.w	d4,d2
	add.w	(a4),d2
	move.w	d4,d0
	move.w	(a2),d1
	jsr	filled_rect
	addq.w	#2,sp
	clr.w	d0
	jsr	show_mouse
	addq.w	#4,sp
	movem.l	(sp)+,d3-d4/a2-a4
	rts


;----------------------------------------------------------------------
; Shows the about box.
;----------------------------------------------------------------------
about_box:
	move.l	a2,-(sp)
	subq.w	#8,sp
	lea	about_tree,a2
	pea	(sp)
	pea	$6(sp)
	pea	$c(sp)
	lea	$12(sp),a1
	movea.l	a2,a0
	jsr	form_center
	lea	$c(sp),sp
	moveq	#7,d0
	jsr	Cconout
	clr.w	d0
	movea.l	a2,a0
	jsr	draw_object
	move.l	d0,-(sp)
	clr.l	-(sp)
	lea	keys_none,a1
	clr.w	d0
	movea.l	a2,a0
	jsr	form_do
	addq.w	#4,sp
	ext.l	d0
	move.l	(sp)+,d1
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	lsl.l	#3,d1
	andi.w	#$fffe,$a(a2,d1.l)              ; -> list_tree+1*OBJECT_SIZE+ob_state+3336 indexed
	moveq	#8,d0
	add.w	(sp),d0
	move.w	d0,-(sp)
	moveq	#8,d1
	add.w	$4(sp),d1
	move.w	d1,-(sp)
	move.w	$8(sp),-(sp)
	move.w	$c(sp),d2
	movea.l	main_tree_ptr,a0
	clr.w	d0
	moveq	#8,d1
	jsr	objc_draw
	addq.w	#6,sp
	addq.w	#8,sp
	movea.l	(sp)+,a2
	rts


;----------------------------------------------------------------------
; Drive selection box: d1 is the current drive, a0 the title.  Lists the drives
; in Drvmap and returns the chosen drive + 1 or 0 for abort.
;----------------------------------------------------------------------
select_drive:
	movem.l	d3-d7/a2-a4,-(sp)
	subq.w	#8,sp
	move.b	d0,d6
	move.w	d1,d4
	movea.l	a0,a3
	move.w	d2,d5
	movea.l	a1,a4
	jsr	Drvmap                          ; Drvmap, with drive B only when it exists
	move.l	d0,d3
	dc.w	$c6bc                           ; and.l #$fffffffd,d3
	dc.l	$fffffffd
	clr.w	d0
	move.b	has_drive_b,d0
	add.w	d0,d0
	ext.l	d0
	or.l	d0,d3
	tst.b	d6                              ; d0 set: no floppies
	beq.s	.drives_known
	dc.w	$c6bc                           ; and.l #$fffffffc,d3
	dc.l	$fffffffc
.drives_known
	tst.l	d3                              ; no drives: "No Drives found!"
	bne.s	.have_drives
	lea	alert_no_drives_found_abort,a0
	moveq	#1,d0
	jsr	alert
	clr.w	d0
	bra.w	.done

.have_drives
	moveq	#1,d0                           ; current drive not present: start at C
	lsl.w	d4,d0
	ext.l	d0
	and.l	d3,d0
	bne.s	.show_box
	moveq	#2,d4
.show_box
	lea	drive_tree_ptr,a2               ; title and drive letter into drive_tree
	move.l	#drive_tree,(a2)
	movea.l	(a2),a0
	movea.l	$24(a0),a1
	move.l	a3,(a1)
	movea.l	(a2),a0
	movea.l	$54(a0),a1
	movea.l	(a1),a3
	moveq	#65,d0
	add.b	d4,d0
	move.b	d0,(a3)
	movea.l	(a2),a0
	move.w	d5,$9a(a0)
	pea	(sp)
	pea	$6(sp)
	pea	$c(sp)
	lea	$12(sp),a1
	movea.l	(a2),a0
	jsr	form_center
	lea	$c(sp),sp
	moveq	#7,d0                           ; bell
	jsr	Cconout
.draw_box
	clr.w	d0
	movea.l	(a2),a0
	jsr	draw_object
.ask
	pea	str_a_p_select_drive_a_p_select ; form_do; keys a..p come back as object $80 + drive
	lea	keys_drive,a1
	clr.w	d0
	movea.l	(a2),a0
	jsr	form_do                         ; a drive key: take it if the drive exists
	addq.w	#4,sp
	move.w	d0,d5
	cmp.w	#$80,d0
	blt.s	.clicked
	move.l	d3,d1
	moveq	#-128,d2
	add.b	d5,d2
	lsr.l	d2,d1
	dc.w	$c2bc                           ; and.l #$1,d1
	dc.l	$1
	beq.w	.no_drive
	moveq	#-128,d4
	add.w	d0,d4
	bra.w	.show_drive

.clicked
	move.w	d5,d0                           ; object: 2 left arrow, 4 right arrow, 5 OK, 6 DIRECTORY, 7 ABORT
	movea.l	(a2),a0
	jsr	deselect_object
	move.w	d5,d0
	subq.w	#2,d0
	cmp.w	#$5,d0
	bhi.s	.ask
	add.w	d0,d0
	move.w	.table(pc,d0.w),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	.previous_drive-.table,.ask-.table,.next_drive-.table,.close-.table
	dc.w	.directory-.table,.close-.table
.directory
	clr.w	d6                              ; DIRECTORY: show the directory of the drive without request boxes
	move.b	cfg_request_boxes,d6
	clr.b	cfg_request_boxes
	moveq	#8,d0
	add.w	(sp),d0
	move.w	d0,-(sp)
	moveq	#8,d1
	add.w	$4(sp),d1
	move.w	d1,-(sp)
	move.w	$8(sp),-(sp)
	move.w	$c(sp),d2
	movea.l	main_tree_ptr,a0
	clr.w	d0
	moveq	#8,d1
	jsr	objc_draw
	addq.w	#6,sp
	move.w	d4,d0
	jsr	show_directory
	move.b	d6,cfg_request_boxes
	moveq	#3,d0
	movea.l	main_tree_ptr,a0
	jsr	draw_object
	jsr	redraw_status
	bra.w	.draw_box

.previous_drive
	moveq	#-1,d7                          ; left arrow: previous existing drive
	add.w	d4,d7
	bra.s	.prev_test

.prev_scan
	subq.w	#1,d7
.prev_test
	tst.w	d7
	blt.s	.prev_found
	moveq	#1,d0
	lsl.w	d7,d0
	ext.l	d0
	and.l	d3,d0
	beq.s	.prev_scan
.prev_found
	cmp.w	#$ffff,d7
	beq.s	.no_drive
.take_drive
	move.w	d7,d4
.show_drive
	moveq	#65,d0                          ; show the letter; repeat while the arrow is held
	add.b	d4,d0
	move.b	d0,(a3)
	movea.l	(a2),a0
	moveq	#3,d0
	jsr	draw_object
	move.b	key_event,d0
	bne.w	.ask
	clr.w	d1
	moveq	#125,d0
	jsr	evnt_timer
	bra.w	.ask

.next_drive
	moveq	#1,d7                           ; right arrow: next existing drive
	add.w	d4,d7
	bra.s	.next_test

.next_scan
	addq.w	#1,d7
.next_test
	cmp.w	#$10,d7
	bge.s	.next_found
	moveq	#1,d0
	lsl.w	d7,d0
	ext.l	d0
	and.l	d3,d0
	beq.s	.next_scan
.next_found
	cmp.w	#$10,d7
	bne.s	.take_drive
.no_drive
	moveq	#7,d0                           ; none: bell
	jsr	Cconout
	bra.w	.ask

.close
	moveq	#8,d0                           ; close the box: redraw what was under it
	add.w	(sp),d0
	move.w	d0,-(sp)
	moveq	#8,d1
	add.w	$4(sp),d1
	move.w	d1,-(sp)
	move.w	$8(sp),-(sp)                    ; partition letter for the messages
	move.w	$c(sp),d2
	movea.l	a4,a0
	clr.w	d0
	moveq	#8,d1
	jsr	objc_draw
	addq.w	#6,sp
	moveq	#65,d0
	add.b	d4,d0
	move.b	d0,-$12(a2)                     ; -> partition_letter
	cmp.w	#$7,d5
	bne.s	.ok
	clr.w	d0
	bra.s	.done

.ok
	moveq	#1,d0                           ; OK: drive + 1, ABORT: 0
	add.w	d4,d0
.done
	addq.w	#8,sp
	movem.l	(sp)+,d3-d7/a2-a4
	rts


;----------------------------------------------------------------------
; Returns 1 if the boot sector in a0 has the executable checksum $1234.
;----------------------------------------------------------------------
is_boot_executable:
	clr.w	d0                              ; word sum of the sector
	move.w	d0,d1
	bra.s	.word_test

.add_word
	move.w	d0,d2
	ext.l	d2
	add.l	d2,d2
	add.w	$0(a0,d2.l),d1
	addq.w	#1,d0
.word_test
	move.w	bpb,d2
	lsr.w	#1,d2
	cmp.w	d2,d0
	bcs.s	.add_word
	cmp.w	#$1234,d1
	bne.s	.not_executable
	moveq	#1,d0
	rts

.not_executable
	clr.b	d0
	rts


;----------------------------------------------------------------------
; Format Disk (d0 = 0) and Soft Format (d0 = 1).  format_tree asks for the disk
; name, directory entries, sectors per cluster, MS-DOS / TOS / optimized layout and the
; Guardian.  The tracks are formatted (or, for Soft Format, only the system sectors
; written), verified if wanted, bad sectors marked in the FAT and the free space shown.
;----------------------------------------------------------------------
format_disk:
	movem.l	d3-d7/a2-a6,-(sp)
	lea	-$a4(sp),sp
	move.w	d0,d3                           ; d3 = 1 for Soft Format
	move.l	buffer_free,$6(sp)              ; free buffer, restored at the end
.start
	lea	$2a(sp),a3
	lea	format_tree_ptr,a2              ; format_tree_ptr, bpb and the disk values follow it
	lea	$48(sp),a6
	lea	alert_x_destination_disk_format,a5
	lea	config,a4
	move.w	$6a(a4),d0                      ; formatting from track 0: BEST MATCH allowed in the error box, -> cfg_start_track
	bne.s	.no_best_match
	jsr	enable_status_box
	bra.s	.drive_letter

.no_best_match
	jsr	disable_status_box
.drive_letter
	jsr	enable_status_button            ; NEW DISK allowed
	moveq	#65,d0                          ; destination drive letter into the messages
	add.b	$5e(a4),d0                      ; -> cfg_dest_drive
	move.b	d0,$4(a5)                       ; -> alert_x_destination_disk_format+4
	move.b	d0,$245(a5)                     ; -> str_sector_s_marked_as_bad_on+42
	move.b	d0,alert_please_remove_write+52
	moveq	#1,d1                           ; formatting implies Format Destination, Read Disk Config. and used sectors only
	move.b	d1,$5f(a4)                      ; -> cfg_format_dest
	move.b	d1,$63(a4)                      ; -> cfg_read_config
	move.b	d1,$64(a4)                      ; -> cfg_used_only
	tst.w	d3
	beq.s	.text_format
	lea	str_soft_formatting,a0
	bra.s	.status

.text_format
	lea	$465(a5),a0                     ; -> str_formatting_2
.status
	jsr	show_status_line
	tst.w	d3                              ; Soft Format: KEEP the old configuration (and its bad sectors) or TAKE the new one
	beq.s	.format_disk
	lea	$199(a5),a0                     ; -> alert_keep_old_disk_configuration
	moveq	#1,d0
	jsr	alert
	move.w	d0,$98(sp)                      ; choice: 0 Format Disk, 1 KEEP, 2 TAKE, 3 CANCEL
	subq.w	#3,d0
	beq.w	.return
	bra.s	.by_choice

.format_disk
	clr.w	$98(sp)
.by_choice
	move.w	$98(sp),d0
	tst.w	d0
	beq.s	.new_bpb
	subq.w	#2,d0
	beq.s	.take
	bra.s	.keep

.take
	clr.w	$6a(a4)                         ; TAKE: rewrite the whole disk from track 0, -> cfg_start_track
.new_bpb
	moveq	#1,d0                           ; Format Disk or TAKE: BPB from the disk configuration of the main dialog
	jsr	check_drive_support
	tst.b	d0
	beq.w	.return
	clr.w	-(sp)
	move.w	$68(a4),d2                      ; -> cfg_sectors
	move.w	$6c(a4),d1                      ; -> cfg_end_track
	move.w	$66(a4),d0                      ; -> cfg_sides
	jsr	bpb_from_config
	addq.w	#2,sp
	bra.w	.dialog

.keep
	movea.l	a5,a0                           ; KEEP: "X: Destination Disk  [FORMAT|ABORT]"
	moveq	#1,d0
	jsr	request_alert
	subq.w	#2,d0
	beq.w	.return
	moveq	#1,d1
	clr.w	d0
	move.b	$5e(a4),d0                      ; -> cfg_dest_drive
	movea.l	buffer_free,a0                  ; read the boot sector of the destination
	jsr	read_disk_config
	tst.w	d0
	bne.w	.return
	moveq	#1,d0
	jsr	check_drive_support
	tst.b	d0
	beq.w	.return
	move.b	#$3,$58(a4)                     ; format type 3: keep the BPB that was read, -> cfg_format_type
	movea.l	buffer_free,a0                  ; Guardian already on the disk?
	jsr	is_boot_executable
	tst.b	d0
	beq.s	.no_guardian
	lea	read_directory_tree,a0
	move.l	a0,d0
	dc.w	$90bc                           ; sub.l #guardian_show,d0
	dc.l	guardian_show
	lea	guardian_show,a1
	movea.l	buffer_free,a0
	lea	$1e(a0),a0
	jsr	memcmp
	tst.w	d0
	bne.s	.no_guardian
	moveq	#1,d0
	bra.s	.guardian_flag

.no_guardian
	clr.w	d0
.guardian_flag
	move.b	d0,$59(a4)                      ; -> cfg_format_guardian
	lea	$4(a2),a0                       ; keep a copy of the old BPB for the bad cluster scan, -> bpb
	lea	$a(sp),a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.w	(a0)+,(a1)+
	movea.l	buffer_free,a0                  ; and the old FATs in the free buffer
	move.l	a0,$2(sp)
	move.l	a0,fat_buffer
	clr.w	d0
	move.b	$5e(a4),d0                      ; -> cfg_dest_drive
	jsr	read_system_sectors
	tst.w	d0
	bne.w	.return
	move.w	$4(a2),d1                       ; -> bpb
	move.w	$c(a2),d0                       ; -> bpb+bpb_fsiz
	jsr	mul_words                       ; free buffer after the FAT
	add.l	d0,buffer_free
.dialog
	tst.w	d3                              ; Format Disk from track 0, or Soft Format: show the format dialog
	bne.s	.bytes_available
	move.w	$6a(a4),d0                      ; -> cfg_start_track
	bne.w	.confirm
.bytes_available
	moveq	#10,d1
	movea.l	a6,a0
	move.w	d1,-(sp)
	move.l	a0,-(sp)
	move.w	#$200,d0                        ; disk sectors * 512
	move.w	$3e(a2),d1                      ; -> disk_sectors
	jsr	mul_words
	movea.l	(sp)+,a0
	move.w	(sp)+,d1
	jsr	ltoa
	lea	str_bytes_available,a1          ; "nnnnn Bytes available"
	movea.l	a6,a0
	jsr	strcat
	move.l	#format_tree,(a2)               ; show the format dialog
	pea	$9c(sp)
	pea	$a2(sp)
	pea	$a8(sp)
	lea	$ae(sp),a1
	movea.l	(a2),a0
	jsr	form_center
	lea	$c(sp),sp
	tst.w	d3
	beq.s	.data_disk_enabled
	moveq	#8,d0
	bra.s	.data_disk_state

.data_disk_enabled
	clr.w	d0
.data_disk_state
	movea.l	(a2),a0                         ; DATA DISK button disabled for Soft Format
	move.w	d0,$202(a0)
	move.b	$59(a4),d1                      ; Guardian check box, -> cfg_format_guardian
	beq.s	.guardian_off
	moveq	#1,d2
	bra.s	.guardian_state

.guardian_off
	clr.w	d2
.guardian_state
	movea.l	(a2),a0
	move.w	d2,$1ba(a0)
	jsr	format_dialog_values
	moveq	#8,d0                           ; select the button of the format type (MS DOS, TOS, Optimized) unless disabled
	clr.w	d2
	move.b	$58(a4),d2                      ; -> cfg_format_type
	dc.w	$d47c,$f                        ; add.w #$f,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a2),a0
	and.w	$a(a0,d1.l),d0
	bne.s	.show_entries
	cmpi.b	#$3,$58(a4)                     ; -> cfg_format_type
	beq.s	.show_entries
	lea	$9a(sp),a1
	clr.w	d0
	move.b	$58(a4),d0                      ; -> cfg_format_type
	dc.w	$d07c,$f                        ; add.w #$f,d0
	moveq	#1,d1
	jsr	form_button
	clr.w	d0
	move.b	$58(a4),d0                      ; -> cfg_format_type
	jsr	format_preset_bpb
.show_entries
	clr.b	$29(sp)                         ; directory entries = root sectors * 16
	moveq	#10,d1
	lea	$26(sp),a0
	move.w	$a(a2),d0                       ; -> bpb+bpb_rdlen
	lsl.w	#4,d0
	jsr	itoa
	move.b	$28(sp),d0
	bne.s	.show_clusters
	move.b	#$20,$28(sp)
.show_clusters
	moveq	#10,d1                          ; sectors per cluster
	lea	$24(sp),a0
	move.w	$6(a2),d0                       ; -> bpb+bpb_clsiz
	jsr	itoa
	jsr	bpb_count_clusters
	movea.l	a3,a0
	jsr	show_bytes_free
	moveq	#65,d0                          ; drive letter in the title
	add.b	$5e(a4),d0                      ; -> cfg_dest_drive
	movea.l	(a2),a0
	movea.l	$24(a0),a1
	move.b	d0,(a1)
	movea.l	(a2),a0
	move.l	a6,$54(a0)
	movea.l	(a2),a0
	move.l	a3,$84(a0)
	lea	$26(sp),a0
	movea.l	(a2),a1
	movea.l	$e4(a1),a1
	move.l	a0,(a1)
	lea	$24(sp),a1
	movea.l	(a2),a0
	movea.l	$114(a0),a0
	move.l	a1,(a0)
	movea.l	(a2),a0
	movea.l	$3c(a0),a1
	move.l	(a1),$20(sp)
	cmpi.w	#$1,$98(sp)                     ; KEEP: the old volume name becomes the disk name
	bne.s	.draw_dialog
	clr.w	d0
	move.b	$5e(a4),d0                      ; -> cfg_dest_drive
	jsr	select_partition
	moveq	#8,d0
	lea	str_star_dot_star,a0            ; volume label: Fsfirst("*.*", attribute 8)
	jsr	Fsfirst
	tst.w	d0
	bne.s	.draw_dialog
	moveq	#46,d0                          ; drop the dot of the 8.3 name
	lea	dta+d_fname,a0
	jsr	strchr
	move.l	a0,$1c(sp)
	beq.s	.volume_name
	movea.l	a0,a1
	addq.w	#1,a1
	jsr	strcpy
.volume_name
	lea	dta+d_fname,a1
	movea.l	$20(sp),a0
	jsr	strcpy
.draw_dialog
	clr.w	d0
	movea.l	(a2),a0
	jsr	draw_object
	lea	$400(a5),a1                     ; underline the shortcut letters of the dialog, -> underlines_format
	movea.l	(a2),a0
	move.w	$12(a0),d1
	move.w	$10(a0),d0
	jsr	underline_shortcuts
	moveq	#7,d0
	jsr	Cconout
	clr.w	d5
	move.w	d5,d7
	move.b	d7,(sp)
	bra.w	.dialog_test

.ask
	pea	$329(a5)                        ; help text for the Help key, -> str_d_data_disk_undo_cancel_p_put
	lea	$30a(a5),a1                     ; keyboard shortcuts of the format dialog, -> keys_format
	moveq	#2,d0
	movea.l	(a2),a0
	jsr	form_do
	addq.w	#4,sp
	move.w	d0,d5
	subq.w	#8,d0                           ; clicked object
	cmp.w	#$e,d0
	bhi.w	.show_values
	add.w	d0,d0
	move.w	.table(pc,d0.w),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	.entries_down-.table,.show_values-.table,.entries_up-.table,.show_values-.table
	dc.w	.clusters_down-.table,.clusters_up-.table,.show_values-.table,.ms_dos-.table
	dc.w	.format_type-.table,.format_type-.table,.guardian_box-.table,.show_values-.table
	dc.w	.leave_dialog-.table,.data_disk-.table,.leave_dialog-.table
.data_disk
	move.b	#$1,(sp)                        ; DATA DISK: only format the tracks, no boot sector, FATs or directory
.leave_dialog
	moveq	#1,d7                           ; OK, DATA DISK, CANCEL: leave the dialog
	bra.w	.show_values

.guardian_box
	moveq	#1,d0                           ; Guardian check box: the Guardian needs a TOS boot sector, so MS DOS is deselected
	movea.l	(a2),a0
	and.b	$1bb(a0),d0
	move.b	d0,$59(a4)                      ; -> cfg_format_guardian
	beq.w	.show_values
	move.b	$58(a4),d1                      ; -> cfg_format_type
	bne.w	.show_values
	moveq	#1,d2
	move.w	d2,-(sp)
	clr.w	-(sp)
	move.w	$a0(sp),-(sp)
	move.w	$a4(sp),-(sp)
	move.w	$a8(sp),-(sp)
	moveq	#15,d0
	clr.w	d1
	move.w	$ac(sp),d2
	jsr	objc_change
	lea	$a(sp),sp
	move.b	#$3,$58(a4)                     ; -> cfg_format_type
	bra.w	.show_values

.ms_dos
	move.b	$59(a4),d0                      ; MS DOS: no Guardian, -> cfg_format_guardian
	beq.s	.format_type
	clr.b	$59(a4)                         ; -> cfg_format_guardian
	moveq	#1,d0
	move.w	d0,-(sp)
	clr.w	-(sp)
	move.w	$a0(sp),-(sp)
	move.w	$a4(sp),-(sp)
	move.w	$a8(sp),-(sp)
	move.w	$ac(sp),d2
	clr.w	d1
	movea.l	(a2),a0
	moveq	#18,d0
	jsr	objc_change
	lea	$a(sp),sp
.format_type
	move.b	d5,d0                           ; MS DOS, TOS, Optimized: format type 0, 1, 2
	dc.w	$d03c,$00f1                     ; add.b #$f1,d0
	move.b	d0,$58(a4)                      ; -> cfg_format_type
	clr.w	d1
	move.b	d0,d1
	move.w	d1,d0
	jsr	format_preset_bpb
	bra.w	.show_values

.entries_down
	cmpi.w	#$1,$a(a2)                      ; directory entries down (16 per root sector), -> bpb+bpb_rdlen
	bls.s	.limit
	subq.w	#1,$a(a2)                       ; -> bpb+bpb_rdlen
	bra.s	.optimized

.limit
	moveq	#7,d0                           ; limit: bell
	jsr	Cconout
.optimized
	move.b	#$2,$58(a4)                     ; a changed value makes the type Optimized, -> cfg_format_type
	lea	$9a(sp),a1
	moveq	#1,d1
	moveq	#17,d0
	movea.l	(a2),a0
	jsr	form_button
	move.w	d5,d0
	movea.l	(a2),a0
	jsr	deselect_object
	bra.s	.show_values

.entries_up
	move.w	$6(a2),d0                       ; directory entries up, while it fits and the root stays below 15 sectors, -> bpb+bpb_clsiz
	add.w	d0,d0
	addq.w	#1,d0
	move.w	$18(a2),d1                      ; -> data_sectors
	cmp.w	d0,d1
	bcs.s	.limit
	cmpi.w	#$f,$a(a2)                      ; -> bpb+bpb_rdlen
	bcc.s	.limit
	addq.w	#1,$a(a2)                       ; -> bpb+bpb_rdlen
	bra.s	.optimized

.clusters_down
	cmpi.w	#$1,$6(a2)                      ; sectors per cluster down; undone if the clusters no longer fit, -> bpb+bpb_clsiz
	bls.s	.limit
	lsr.w	$6(a2)                          ; -> bpb+bpb_clsiz
	jsr	bpb_fat_size
	jsr	bpb_count_clusters
	move.w	$6(a2),d0                       ; -> bpb+bpb_clsiz
	add.w	d0,d0
	addq.w	#1,d0
	move.w	$18(a2),d1                      ; -> data_sectors
	cmp.w	d0,d1
	bcc.s	.optimized
	lsl.w	$6(a2)                          ; -> bpb+bpb_clsiz
	bra.s	.limit

.clusters_up
	cmpi.w	#$8,$6(a2)                      ; sectors per cluster up, at most 8, -> bpb+bpb_clsiz
	bcc.w	.limit
	lsl.w	$6(a2)                          ; -> bpb+bpb_clsiz
	bra.s	.optimized

.show_values
	jsr	bpb_data_start                  ; show the new values
	moveq	#10,d1
	lea	$26(sp),a0
	move.w	$a(a2),d0                       ; -> bpb+bpb_rdlen
	lsl.w	#4,d0
	jsr	itoa
	move.b	$28(sp),d0
	bne.s	.draw_entries
	move.b	#$20,$28(sp)
.draw_entries
	moveq	#9,d0
	movea.l	(a2),a0
	jsr	draw_object
	moveq	#10,d1
	lea	$24(sp),a0
	move.w	$6(a2),d0                       ; -> bpb+bpb_clsiz
	jsr	itoa
	moveq	#11,d0
	movea.l	(a2),a0
	jsr	draw_object
	cmpi.b	#$2,$58(a4)                     ; -> cfg_format_type
	bne.s	.free_space
	jsr	bpb_fat_size                    ; Optimized: smallest FAT
.free_space
	jsr	bpb_count_clusters
	movea.l	a3,a0
	jsr	show_bytes_free
	moveq	#4,d0
	movea.l	(a2),a0
	jsr	draw_object
.dialog_test
	tst.b	d7                              ; until OK, DATA DISK or CANCEL
	beq.w	.ask
	cmpi.b	#$2,$58(a4)                     ; Optimized: root directory to a cluster boundary, -> cfg_format_type
	bne.s	.close_dialog
	jsr	bpb_align_root
.close_dialog
	tst.w	d3                              ; Format Disk: remove the dialog by redrawing the main dialog under it
	bne.s	.check_cancel
	move.w	d5,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	andi.w	#$fffe,$a(a0,d0.l)
	move.w	$9c(sp),-(sp)
	moveq	#4,d2
	add.w	$a0(sp),d2
	move.w	d2,-(sp)
	move.w	$a4(sp),-(sp)
	moveq	#-4,d2
	add.w	$a8(sp),d2
	movea.l	main_tree_ptr,a0
	clr.w	d0
	moveq	#8,d1
	jsr	objc_draw
	addq.w	#6,sp
.check_cancel
	cmp.w	#$16,d5                         ; CANCEL
	beq.w	.redraw
	tst.w	d3
	bne.s	.start_format
	jsr	draw_progress_frame
.start_format
	cmpi.b	#$3,$58(a4)                     ; type 3 (read BPB) is written as Optimized, -> cfg_format_type
	bne.s	.prepare
	move.b	#$2,$58(a4)                     ; -> cfg_format_type
	bra.s	.prepare

.confirm
	movea.l	a5,a0                           ; not from track 0: only "X: Destination Disk [FORMAT|ABORT]"
	moveq	#1,d0
	jsr	request_alert
	subq.w	#2,d0
	beq.w	.redraw
.prepare
	jsr	alloc_track_buffers             ; track buffers and drive parameters
	jsr	set_drive_params
	tst.w	d3                              ; Soft Format writes no tracks
	bne.w	.tracks_done
	jsr	draw_status_labels
	jsr	build_track_image               ; track image for Write Track
	move.w	$6c(a4),d7                      ; format from the end track down to the start track, -> cfg_end_track
	move.w	d7,d1
	moveq	#1,d0
	jsr	restore_drive                   ; move the destination head to the end track
	clr.w	d6                              ; sector list 1, 2, .. dst_sectors, 0 terminated
	bra.s	.list_test

.next_list_sector
	moveq	#1,d0
	add.b	d6,d0
	lea	sector_list,a0
	move.b	d0,$0(a0,d6.w)                  ; -> sector_list indexed
	addq.w	#1,d6
.list_test
	cmp.w	$28(a2),d6                      ; -> dst_sectors
	blt.s	.next_list_sector
	lea	sector_list,a0
	clr.b	$0(a0,d6.w)                     ; -> sector_list indexed
.next_track
	clr.w	d4                              ; all sides of the track
	bra.s	.side_test

.format_track
	move.w	d7,d1
	move.w	d4,d0
	jsr	format_track                    ; format the track
	move.w	d0,d6
	move.b	$60(a4),d1                      ; Verify Destination: sector list in the order the track was formatted, -> cfg_verify_dest
	beq.s	.verify
	jsr	order_sector_list
.verify
	move.w	d6,-(sp)
	move.w	d7,-(sp)
	move.w	d4,d2
	moveq	#1,d1
	moveq	#5,d0
	jsr	show_track_result               ; show the track (5 = Formatting), verify it; 0 CONTINUE, 1 ABORT, 2 RETRY, 3 BEST MATCH, 4 OK, 5 NEW DISK
	addq.w	#4,sp
	cmp.w	#$5,d0
	bhi.s	.next_side
	add.w	d0,d0
	move.w	.table2(pc,d0.w),d0
	jmp	.table2(pc,d0.w)

.table2
	dc.w	.continue-.table2,.abort-.table2,.format_track-.table2,.best_match-.table2
	dc.w	.next_side-.table2,.start-.table2
.continue
	move.w	$6a(a4),d0                      ; CONTINUE: the failing sectors go into the bad sector list (from track 0 only), -> cfg_start_track
	bne.s	.next_side
	clr.w	-(sp)
	suba.l	a0,a0
	move.w	d7,d2
	move.w	d4,d1
	moveq	#1,d0
	jsr	mark_bad_sectors
	addq.w	#2,sp
	bra.s	.next_side

.best_match
	moveq	#1,d0                           ; BEST MATCH: mark them too
	move.w	d0,-(sp)
	suba.l	a0,a0
	move.w	d7,d2
	move.w	d4,d1
	moveq	#1,d0
	jsr	mark_bad_sectors
	addq.w	#2,sp
.next_side
	addq.w	#1,d4
.side_test
	cmp.w	$2c(a2),d4                      ; -> dst_sides
	ble.w	.format_track
	subq.w	#1,d7                           ; next track down
	cmp.w	$6a(a4),d7                      ; -> cfg_start_track
	blt.s	.from_track_0
	jsr	step_out                        ; step out one track
	jsr	read_fdc_status
	jsr	read_fdc_status
	jsr	read_fdc_status
	dc.w	$c07c,$4                        ; and.w #$4,d0, FDC status bit 2: track 0
	beq.s	.last_track
	tst.w	d7                              ; track 0 signalled before the last track: head misaligned
	beq.w	.next_track
	lea	alert_the_floppy_head_has_reached,a0
	moveq	#1,d0
	jsr	alert
	bra.w	.abort

.last_track
	tst.w	d7                              ; last track done: the head must now be on track 0
	bne.w	.next_track
	moveq	#2,d0
	jsr	wait_ticks
	jsr	read_fdc_status
	dc.w	$c07c,$4                        ; and.w #$4,d0
	bne.w	.next_track
	lea	alert_the_floppy_head_has_not,a0
	moveq	#1,d0
	jsr	alert
	bra.w	.abort

.from_track_0
	move.w	$6a(a4),d0                      ; -> cfg_start_track
	bne.w	.abort
.tracks_done
	jsr	unlock_floppy                   ; tracks done
	move.b	(sp),d0                         ; DATA DISK: finished
	bne.w	.redraw
	move.w	$28(a2),d2                      ; boot sector for the new format, -> dst_sectors
	move.w	$6c(a4),d1                      ; -> cfg_end_track
	movea.l	track_buffer,a0
	move.w	$2c(a2),d0                      ; -> dst_sides
	jsr	build_boot_sector
	cmpi.b	#$1,$58(a4)                     ; TOS type with 18 or more sectors: media byte $f9 (TOS 2.05) or $f6, -> cfg_format_type
	bne.s	.guardian
	cmpi.w	#$12,$28(a2)                    ; -> dst_sectors
	blt.s	.guardian
	move.b	tos_205,d0
	beq.s	.media_f6
	move.b	#$f9,d1
	bra.s	.set_media

.media_f6
	move.b	#$f6,d1
.set_media
	movea.l	track_buffer,a0
	move.b	d1,$15(a0)
.guardian
	move.b	$59(a4),d0                      ; Guardian into the boot sector, -> cfg_format_guardian
	beq.s	.write_boot
	movea.l	track_buffer,a0
	jsr	put_guardian
.write_boot
	moveq	#1,d0                           ; Flopwr the boot sector: sector 1, track 0, side 0
	move.w	d0,-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	move.w	d0,d2
	move.w	$24(a2),d1                      ; -> dst_unit
	movea.l	track_buffer,a0
	moveq	#0,d0
	jsr	Flopwr
	addq.w	#6,sp
	move.w	d0,d6
	beq.s	.new_fat
	cmp.w	#$fff3,d0                       ; write protected (-13)
	bne.s	.boot_failed
	lea	alert_please_remove_write,a0
	moveq	#1,d0
	jsr	alert
	subq.w	#1,d0
	bne.w	.redraw
	bra.s	.write_boot

.boot_failed
	move.b	$5a(a4),d0                      ; TAKE with Smart Formatting: a boot sector that cannot be written means the disk, -> cfg_smart_format
	beq.s	.no_system
	cmpi.w	#$2,$98(sp)
	bne.s	.no_system
.format_completely
	clr.w	d3                              ; is formatted completely instead
	move.w	d3,$98(sp)
	lea	$465(a5),a0                     ; -> str_formatting_2
	jsr	draw_progress_text
	bra.w	.close_dialog

.no_system
	lea	$d6(a5),a0                      ; "Cannot access System sectors!", -> alert_cannot_access_system_sectors
	moveq	#1,d0
	jsr	alert
	bra.w	.redraw

.new_fat
	movea.l	track_buffer,a0                 ; new FAT: media byte, $ff, $ff
	movea.l	fat_buffer,a1
	move.b	$15(a0),(a1)
	move.b	#$ff,d0
	movea.l	fat_buffer,a0
	move.b	d0,$2(a0)
	movea.l	fat_buffer,a0
	move.b	d0,$1(a0)
	cmpi.w	#$1,$98(sp)                     ; KEEP: carry the bad clusters of the old FAT over
	bne.s	.take_fats
	clr.w	d4
	bra.s	.bad_test

.next_bad
	move.w	d4,d0
	lea	$a(sp),a1
	movea.l	$2(sp),a0
	jsr	sector_is_bad
	tst.b	d0
	beq.s	.bad_advance
	addq.w	#1,$16(a2)                      ; -> bad_sectors
	move.w	d4,d0
	jsr	mark_bad_cluster
.bad_advance
	addq.w	#1,d4
.bad_test
	cmp.w	$3e(a2),d4                      ; -> disk_sectors
	bcs.s	.next_bad
.take_fats
	move.b	$5a(a4),d0                      ; TAKE with Smart Formatting: write both FATs directly with Rwabs, -> cfg_smart_format
	beq.s	.write_fats
	cmpi.w	#$2,$98(sp)
	bne.s	.write_fats
	move.w	$24(a2),d0                      ; -> dst_unit
	jsr	Getbpb
	move.w	$24(a2),-(sp)                   ; -> dst_unit
	moveq	#1,d2
	move.w	$c(a2),d1                       ; -> bpb+bpb_fsiz
	movea.l	fat_buffer,a0
	moveq	#1,d0
	jsr	Rwabs
	addq.w	#2,sp
	tst.l	d0
	bne.w	.format_completely
	move.w	$24(a2),-(sp)                   ; -> dst_unit
	moveq	#1,d2
	add.w	$c(a2),d2                       ; -> bpb+bpb_fsiz
	move.w	$c(a2),d1                       ; -> bpb+bpb_fsiz
	movea.l	fat_buffer,a0
	moveq	#1,d0
	jsr	Rwabs
	addq.w	#2,sp
	tst.l	d0
	beq.s	.root
	bra.w	.format_completely

.write_fats
	move.w	$24(a2),d0                      ; else write_fats (asks to remove write protection), -> dst_unit
	jsr	write_fats
	tst.w	d0
	bne.w	.redraw
.root
	tst.w	d3                              ; Soft Format: clear the root directory
	beq.s	.label
	move.w	#$200,d1
	move.w	$a(a2),d0                       ; -> bpb+bpb_rdlen
	jsr	mul_words
	move.l	d0,d1
	clr.w	d0
	movea.l	track_buffer,a0
	jsr	memset
	move.w	$24(a2),-(sp)                   ; -> dst_unit
	move.w	$c(a2),d2                       ; -> bpb+bpb_fsiz
	add.w	d2,d2
	addq.w	#1,d2
	move.w	$a(a2),d1                       ; -> bpb+bpb_rdlen
	movea.l	track_buffer,a0
	moveq	#1,d0
	jsr	Rwabs
	addq.w	#2,sp
	tst.l	d0
	bne.w	.boot_failed
.label
	move.w	$24(a2),d0                      ; media change, then the disk name as volume label, -> dst_unit
	jsr	select_partition
	clr.w	d0
	lea	dfree_info,a0
	jsr	Dfree
	movea.l	$20(sp),a0
	move.b	(a0),d0
	beq.s	.report_bad
	movea.l	a0,a1
	movea.l	a3,a0
	jsr	strcpy
	movea.l	a3,a0                           ; name longer than 8: insert the dot
	jsr	strlen
	moveq	#8,d1
	cmp.l	d0,d1
	bcc.s	.create_label
	moveq	#4,d0
	lea	$8(a3),a1
	lea	$9(a3),a0
	jsr	memcpy
	move.b	#$2e,$8(a3)                     ; '.'
.create_label
	moveq	#8,d0                           ; Fcreate with attribute 8 (volume label)
	movea.l	a3,a0
	jsr	Fcreate
	move.w	d0,d6
	tst.w	d0
	blt.s	.label_error
	jsr	Fclose
	bra.s	.report_bad

.label_error
	lea	$102(a5),a0                     ; -> alert_cannot_write_diskname_ok
	moveq	#1,d0
	jsr	alert
.report_bad
	move.w	$16(a2),d0                      ; bad sectors marked: "[1][nn Sector(s) marked as BAD on Disk in Drive X:]", -> bad_sectors
	beq.s	.redraw
	lea	$216(a5),a1                     ; -> str_alert_1
	movea.l	a6,a0
	jsr	strcpy
	movea.l	a6,a0
	jsr	strlen
	lea	$0(a6,d0.w),a0
	move.w	$16(a2),d0                      ; -> bad_sectors
	moveq	#10,d1
	jsr	itoa
	lea	$21b(a5),a1                     ; -> str_sector_s_marked_as_bad_on
	movea.l	a6,a0
	jsr	strcat
	movea.l	a6,a0
	moveq	#1,d0
	jsr	alert
	bra.s	.redraw

.abort
	clr.w	d1                              ; ABORT: head back to track 0
	moveq	#1,d0
	jsr	restore_drive
	jsr	unlock_floppy
.redraw
	tst.w	d3                              ; Soft Format: redraw the main dialog under the format dialog
	beq.s	.free_buffer
	move.w	d5,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	andi.w	#$fffe,$a(a0,d0.l)
	move.w	$9c(sp),-(sp)
	moveq	#4,d2
	add.w	$a0(sp),d2
	move.w	d2,-(sp)
	move.w	$a4(sp),-(sp)
	moveq	#-4,d2
	add.w	$a8(sp),d2
	movea.l	main_tree_ptr,a0
	clr.w	d0
	moveq	#8,d1
	jsr	objc_draw
	addq.w	#6,sp
.free_buffer
	move.l	$6(sp),buffer_free
.return
	lea	$a4(sp),sp
	movem.l	(sp)+,d3-d7/a2-a6
	rts


sector_is_bad:
	move.l	d3,-(sp)
	move.l	d4,-(sp)
	cmp.w	$c(a1),d0
	bcs.w	.not_bad
	move.w	d0,d1
	sub.w	$c(a1),d1
	moveq	#0,d2
	move.w	d1,d2
	divu.w	$2(a1),d2
	addq.w	#2,d2
	move.w	d2,d0
	moveq	#1,d2
	and.w	$10(a1),d2
	beq.s	.fat12
	add.w	d0,d0
	moveq	#0,d1
	move.w	d0,d1
	clr.w	d2
	move.b	$0(a0,d1.l),d2
	move.w	d2,d1
	moveq	#1,d2
	add.w	d0,d2
	moveq	#0,d3
	move.w	d2,d3
	clr.w	d2
	move.b	$0(a0,d3.l),d2
	lsl.w	#8,d2
	add.w	d2,d1
	bra.s	.check_bad

.fat12
	move.w	d0,d2
	lsr.w	#1,d2
	add.w	d0,d2
	moveq	#0,d1
	move.w	d2,d1
	clr.w	d3
	move.b	$0(a0,d1.l),d3
	move.w	d3,d1
	moveq	#1,d3
	add.w	d2,d3
	moveq	#0,d4
	move.w	d3,d4
	clr.w	d3
	move.b	$0(a0,d4.l),d3
	lsl.w	#8,d3
	add.w	d3,d1
	moveq	#1,d2
	and.w	d0,d2
	beq.s	.even
	lsr.w	#4,d1
	bra.s	.sign_extend

.even
	dc.w	$c27c,$fff                      ; and.w #$fff,d1
.sign_extend
	dc.w	$827c,$f000                     ; or.w #$f000,d1
.check_bad
	cmp.w	#$fff0,d1
	bcs.s	.not_bad
	cmp.w	#$fff8,d1
	bcc.s	.not_bad
	moveq	#1,d0
	bra.s	.return

.not_bad
	clr.b	d0
.return
	move.l	(sp)+,d4
	move.l	(sp)+,d3
	rts


format_dialog_values:
	move.l	a2,-(sp)                        ; enables the directory entry and cluster buttons of format_tree for the formats
	lea	config,a0
	move.w	$6c(a0),d0                      ; -> cfg_end_track
	move.w	$68(a0),d1                      ; -> cfg_sectors
	lea	dir_entry_step,a1               ; standard 80 track formats with a known directory size
	move.w	#$ffff,$2(a1)                   ; -> dir_entry_dir
	cmp.w	#$4f,d0
	bne.s	.dir_buttons
	cmp.w	#$9,d1
	bne.s	.check_18
	clr.w	$2(a1)                          ; -> dir_entry_dir
.check_18
	cmp.w	#$12,d1
	bne.s	.dir_buttons
	move.b	tos_205,d2
	beq.s	.tos_205
	move.w	#$1,$2(a1)                      ; -> dir_entry_dir
	bra.s	.dir_buttons

.tos_205
	move.w	#$2,$2(a1)                      ; -> dir_entry_dir
.dir_buttons
	cmpi.w	#$ffff,$2(a1)                   ; -> dir_entry_dir
	beq.s	.dir_disabled
	clr.w	d2
	bra.s	.set_dir_state

.dir_disabled
	moveq	#8,d2
.set_dir_state
	movea.l	-$34(a1),a2                     ; directory entry buttons enabled only for those, -> format_tree_ptr
	move.w	d2,$18a(a2)
	move.w	#$ffff,(a1)                     ; cluster size buttons by format
	cmpi.w	#$1,$66(a0)                     ; -> cfg_sides
	bne.s	.cluster_buttons
	cmp.w	#$27,d0
	bne.s	.check_80
	cmp.w	#$9,d1
	bne.s	.check_80
	clr.w	(a1)
	bra.s	.cluster_buttons

.check_80
	cmp.w	#$4f,d0
	bne.s	.cluster_buttons
	move.w	d1,d0
	dc.w	$907c,$9                        ; sub.w #$9,d0
	beq.s	.dd_9
	subq.w	#6,d0
	beq.s	.hd_15
	subq.w	#3,d0
	beq.s	.hd_18
	bra.s	.cluster_buttons

.dd_9
	move.w	#$1,(a1)
	bra.s	.cluster_buttons

.hd_15
	move.w	#$2,(a1)
	bra.s	.cluster_buttons

.hd_18
	move.b	$5e(a0),d0                      ; -> cfg_dest_drive
	beq.s	.drive_a
	move.b	$4b(a0),d1                      ; -> cfg_b_density
	bra.s	.check_hd3

.drive_a
	move.b	$49(a0),d1                      ; -> cfg_a_density
.check_hd3
	subq.b	#2,d1
	bne.s	.cluster_buttons
	move.w	#$3,(a1)
.cluster_buttons
	cmpi.w	#$ffff,(a1)                     ; cluster buttons enabled only for known formats
	bne.s	.cluster_enabled
	moveq	#8,d0
	bra.s	.set_cluster_state

.cluster_enabled
	clr.w	d0
.set_cluster_state
	movea.l	-$34(a1),a0                     ; -> format_tree_ptr
	move.w	d0,$172(a0)
	movea.l	-$34(a1),a0                     ; -> format_tree_ptr
	clr.w	$1a2(a0)
	movea.l	(sp)+,a2
	rts


format_preset_bpb:
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	lea	bpb,a3
	move.w	d0,d1
	tst.w	d1
	beq.s	.use_dir_entry_step
	subq.w	#1,d1
	beq.s	.use_dir_entry_dir
	subq.w	#1,d1
	beq.s	.use_sectors
	bra.s	.finish

.use_dir_entry_dir
	move.w	$32(a3),d0                      ; -> dir_entry_dir
	lsl.w	#2,d0
	lea	format_layouts_hd,a2
	adda.w	d0,a2
	bra.s	.set_bpb_rdlen

.use_sectors
	clr.w	-(sp)
	move.w	cfg_sectors,d2
	move.w	cfg_end_track,d1
	move.w	cfg_sides,d0
	jsr	bpb_from_config
	addq.w	#2,sp
	bra.s	.finish

.use_dir_entry_step
	move.w	$30(a3),d0                      ; -> dir_entry_step
	lsl.w	#2,d0
	lea	format_layouts,a2
	adda.w	d0,a2
.set_bpb_rdlen
	clr.w	d0
	move.b	$2(a2),d0
	move.w	d0,$6(a3)                       ; -> bpb+bpb_rdlen
	clr.w	d1
	move.b	(a2),d1
	move.w	d1,$2(a3)                       ; -> bpb+bpb_clsiz
	clr.w	d2
	move.b	$1(a2),d2
	move.w	d2,$8(a3)                       ; -> bpb+bpb_fsiz
.finish
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


show_bytes_free:
	move.l	a2,-(sp)
	movea.l	a0,a2
	moveq	#10,d1
	move.w	d1,-(sp)
	move.w	#$200,d0
	move.w	data_sectors,d1
	jsr	mul_words
	movea.l	a2,a0
	move.w	(sp)+,d1
	jsr	ltoa
	lea	str_bytes,a1
	movea.l	a2,a0
	jsr	strcat
	moveq	#10,d1
	move.w	d1,-(sp)
	movea.l	a2,a0
	jsr	strlen
	lea	$0(a2,d0.l),a0
	move.l	a0,-(sp)
	moveq	#100,d1
	move.w	data_sectors,d0
	jsr	mul_words
	moveq	#0,d1
	move.w	disk_sectors,d1
	jsr	ldiv
	movea.l	(sp)+,a0
	move.w	(sp)+,d1
	jsr	ltoa
	lea	str_free,a1
	movea.l	a2,a0
	jsr	strcat
	movea.l	(sp)+,a2
	rts


bpb_count_clusters:
	lea	bpb,a0
	move.w	$3a(a0),d0                      ; -> disk_sectors
	move.w	$8(a0),d1                       ; -> bpb+bpb_fsiz
	add.w	d1,d1
	add.w	$6(a0),d1                       ; -> bpb+bpb_rdlen
	addq.w	#1,d1
	sub.w	d1,d0
	move.w	d0,$14(a0)                      ; -> data_sectors
	rts


set_drive_params:
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	jsr	lock_floppy                     ; flock for the whole function
	lea	config,a2
	move.b	$50(a2),d0                      ; HD mode of the drives, -> cfg_hd_detect
	beq.s	.step_rates
	clr.w	d0
	move.b	$6e(a2),d0                      ; -> cfg_hd
	jsr	set_hd_mode
.step_rates
	lea	hd_step_rates,a0                ; step rates of source and destination drive from the DD or HD table
	move.b	$6e(a2),d0                      ; -> cfg_hd
	beq.s	.dd_rates
	movea.l	a0,a1
	bra.s	.source_rate

.dd_rates
	lea	-$8(a0),a1                      ; -> dd_step_rates
.source_rate
	lea	src_step_rate,a3
	move.b	$5d(a2),d0                      ; -> cfg_source_drive
	beq.s	.source_a
	move.b	$4d(a2),d1                      ; -> cfg_b_step_rate
	bra.s	.set_source_rate

.source_a
	move.b	$4c(a2),d1                      ; -> cfg_a_step_rate
.set_source_rate
	moveq	#0,d0
	move.b	d1,d0
	add.l	d0,d0
	move.w	$0(a1,d0.l),(a3)                ; -> dd_step_rates indexed
	move.b	$5e(a2),d0                      ; -> cfg_dest_drive
	beq.s	.dest_a
	move.b	$4d(a2),d1                      ; -> cfg_b_step_rate
	bra.s	.set_dest_rate

.dest_a
	move.b	$4c(a2),d1                      ; -> cfg_a_step_rate
.set_dest_rate
	moveq	#0,d0
	move.b	d1,d0
	add.l	d0,d0
	move.w	$0(a1,d0.l),$2(a3)              ; -> dd_step_rates indexed, -> dst_step_rate
	clr.w	d0                              ; units
	move.b	$5d(a2),d0                      ; -> cfg_source_drive
	move.w	d0,$4(a3)                       ; -> src_unit
	clr.w	d0
	move.b	$5e(a2),d0                      ; -> cfg_dest_drive
	move.w	d0,$6(a3)                       ; -> dst_unit
	jsr	drive_hd_mode                   ; drive limits
	move.w	$66(a2),d0                      ; source and destination get the disk configuration of the main dialog, -> cfg_sides
	move.w	d0,$e(a3)                       ; -> dst_sides
	move.w	d0,$c(a3)                       ; -> src_sides
	move.w	$68(a2),d1                      ; -> cfg_sectors
	move.w	d1,$a(a3)                       ; -> dst_sectors
	move.w	d1,$8(a3)                       ; -> src_sectors
	move.b	$6e(a2),d0                      ; -> cfg_hd
	move.b	d0,$11(a3)                      ; -> dst_hd
	move.b	d0,$10(a3)                      ; -> src_hd
	move.b	$62(a2),$12(a3)                 ; Fast Format, Fast Access headers, retries, -> cfg_fast_format, -> fmt_fast
	move.b	$51(a2),$13(a3)                 ; -> cfg_fast_access, -> fmt_fast_access
	move.b	$57(a2),$14(a3)                 ; -> cfg_retries, -> fmt_retries
	move.w	#$ffff,d0                       ; track map empty, no bad sectors, no first pass, no sector order
	move.w	d0,$1c(a3)                      ; -> shown_track
	move.w	d0,$1e(a3)                      ; -> shown_side
	move.w	d0,$1a(a3)                      ; -> shown_result
	clr.w	-$8(a3)                         ; -> bad_sectors
	clr.b	first_pass
	moveq	#0,d0
	move.l	d0,fdc_state+fs_order_ptr
	move.l	d0,copy_buffer_end
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


;----------------------------------------------------------------------
; Shows the result of track d5 (stack), side d2 of drive d1 (0 source, 1 destination)
; in the track map and handles errors.  d0 is the operation: 0 and 5 formatting,
; 1 verifying, 2 scanning, 3 writing, 4 reading; the error code d4 (stack) comes from
; fdc_command.  Without an error, Verify Destination reads the track back (for writing
; also comparing three longs of each sector with the copy buffer).  With an error the
; error box "Error while ... Track of Drive X:" is shown; Smart Formatting formats a
; track that failed to write.  Returns 0 CONTINUE, 1 ABORT, 2 RETRY, 3 BEST MATCH,
; 4 OK, 5 NEW DISK.  Esc/Space and the toggle keys are read by check_keyboard.
;----------------------------------------------------------------------
show_track_result:
	movem.l	d3-d7/a2-a5,-(sp)
	lea	-$3a(sp),sp
	move.w	d0,$38(sp)                      ; operation, drive, side, track, error code
	move.w	d1,$36(sp)
	move.w	d2,d6
	move.w	$62(sp),d5
	move.w	$64(sp),d4
	jsr	linea_defaults                  ; cell of the track map: colour or pattern by result and drive
	lea	fill_solid,a2
	move.b	medium_res,d0                   ; medium resolution: colours
	beq.s	.monochrome
	clr.w	d1
	movea.l	a2,a0
	clr.w	d0
	jsr	set_fill_pattern
	tst.w	d4                              ; error: colour 1
	beq.s	.colour_by_drive
	moveq	#1,d0
	bra.s	.set_colour

.colour_by_drive
	move.w	$36(sp),d0                      ; source green (2), destination 15
	bne.s	.dest_colour
	moveq	#2,d0
	bra.s	.set_colour

.dest_colour
	moveq	#15,d0
.set_colour
	jsr	set_colour
	bra.s	.cell

.monochrome
	clr.w	d1                              ; monochrome: fill patterns
	moveq	#1,d0
	move.w	d1,-(sp)
	move.w	d0,-(sp)
	tst.w	d4
	beq.s	.pattern_by_drive
	lea	-$8(a2),a0                      ; error: dotted, -> fill_dotted
	bra.s	.set_pattern

.pattern_by_drive
	move.w	$3a(sp),d0
	bne.s	.dest_pattern
	lea	-$4(a2),a0                      ; source grey, destination solid, -> fill_grey
	bra.s	.set_pattern

.dest_pattern
	movea.l	a2,a0
.set_pattern
	move.w	(sp)+,d0
	move.w	(sp)+,d1
	jsr	set_fill_pattern
.cell
	move.w	d5,d7                           ; cell position from track and side
	mulu.w	map_cell_w,d7
	add.w	map_x,d7
	addq.w	#2,d7
	move.w	d6,d0
	mulu.w	map_cell_h,d0
	add.w	map_y,d0
	addq.w	#2,d0
	move.w	d0,$30(sp)
	add.w	map_cell_h,d0
	subq.w	#4,d0
	move.w	d0,-(sp)
	move.w	d7,d2
	add.w	map_cell_w,d2
	subq.w	#4,d2
	move.w	$32(sp),d1
	move.w	d7,d0
	jsr	filled_rect                     ; fill the cell
	addq.w	#2,sp
	lea	$2(sp),a3
	lea	dst_sectors,a5                  ; status line: side, track and result only when changed
	cmp.w	$14(a5),d6                      ; -> shown_side
	beq.s	.check_track
	moveq	#49,d0                          ; side "1" / "2"
	add.b	d6,d0
	move.b	d0,(a3)
	clr.b	$1(a3)
	moveq	#1,d1
	movea.l	a3,a0
	moveq	#38,d0
	jsr	draw_text_line
.check_track
	cmp.w	$12(a5),d5                      ; -> shown_track
	beq.s	.check_result
	moveq	#0,d0                           ; track as two digits
	move.w	d5,d0
	divu.w	#$a,d0
	dc.w	$d03c,$0030                     ; add.b #$30,d0
	move.b	d0,(a3)
	moveq	#0,d1
	move.w	d5,d1
	divu.w	#$a,d1
	swap	d1
	dc.w	$d23c,$0030                     ; add.b #$30,d1
	move.b	d1,$1(a3)
	clr.b	$2(a3)
	movea.l	a3,a0
	moveq	#28,d0
	moveq	#1,d1
	jsr	draw_text_line
.check_result
	cmp.w	$10(a5),d4                      ; -> shown_result
	beq.s	.remember
	moveq	#1,d1                           ; result text ("OK", "DMA Error", ... 16 characters each)
	moveq	#50,d0
	move.w	d4,d2
	lsl.w	#4,d2
	lea	-$a7(a2),a0                     ; -> str_ok_2
	adda.w	d2,a0
	jsr	draw_text_line
.remember
	move.w	d4,$10(a5)                      ; remember what is shown, -> shown_result
	move.w	d6,$14(a5)                      ; -> shown_side
	move.w	d5,$12(a5)                      ; -> shown_track
	cmpi.w	#$3,$38(sp)                     ; keys: Esc/Space always, F and T while formatting/writing, M and V otherwise
	beq.s	.keys_write
	move.w	$38(sp),d0
	bne.s	.keys_other
.keys_write
	moveq	#10,d0
	bra.s	.keyboard

.keys_other
	moveq	#20,d0
.keyboard
	dc.w	$807c,$21                       ; or.w #$21,d0
	jsr	check_keyboard
	subq.w	#1,d0                           ; interrupted: ABORT
	beq.w	.abort
	tst.w	d4                              ; no error:
	bne.w	.error
	move.b	cfg_verify_dest,d0              ; Verify Destination of a destination track, not already a verify call
	beq.w	.ok
	cmpi.w	#$1,$36(sp)
	bne.w	.ok
	cmpi.w	#$1,$38(sp)
	beq.w	.ok
	cmpi.w	#$b,(a5)                        ; tracks the FDC wrote in its own order need the order table; else sector 1..n
	beq.s	.numbered
	cmpi.w	#$15,(a5)
	bge.s	.numbered
	cmpi.b	#$1,-$d(a5)                     ; -> drive_density
	bne.s	.not_hd5
	cmpi.w	#$12,(a5)
	beq.s	.numbered
.not_hd5
	cmpi.w	#$11,(a5)
	beq.s	.numbered
	move.l	fdc_state+fs_order_ptr,d0
	bne.s	.ordered
.numbered
	moveq	#1,d0
	bra.s	.order_flag

.ordered
	clr.w	d0
.order_flag
	move.b	d0,(sp)
	clr.w	d7                              ; each sector of the track:
	bra.w	.verify_test

.next_sector
	move.b	(sp),d0                         ; sector number in order or from the order table
	beq.s	.from_order
	moveq	#1,d3
	add.w	d7,d3
	bra.s	.check_writing

.from_order
	moveq	#0,d0
	move.w	d7,d0
	movea.l	fdc_state+fs_order_ptr,a0
	clr.w	d3
	move.b	$0(a0,d0.l),d3
.check_writing
	cmpi.w	#$3,$38(sp)                     ; writing: only sectors that were written (written_sectors list)
	bne.s	.read_back
	lea	$20(a5),a4                      ; -> written_sectors
.find_written
	move.w	(a4),$2e(sp)
	beq.s	.written_found
	cmp.w	$2e(sp),d3
	beq.s	.written_found
	addq.w	#6,a4
	bra.s	.find_written

.written_found
	move.w	$2e(sp),d0
	beq.s	.next_verify
.read_back
	moveq	#1,d0                           ; read the sector back
	move.b	d0,-(sp)
	movea.l	buffer_start,a0
	move.w	d3,d2
	move.w	d6,d1
	moveq	#1,d0
	jsr	read_sectors
	addq.w	#2,sp
	move.w	d0,d4
	tst.w	d4                              ; read error: show it as Verifying (1)
	beq.s	.verify_read_ok
.verify_error
	move.w	d4,-(sp)
	move.w	d5,-(sp)
	move.w	d6,d2
	moveq	#1,d1
	moveq	#1,d0
	jsr	show_track_result(pc)
	addq.w	#4,sp
	bra.w	.return

.verify_read_ok
	cmpi.w	#$3,$38(sp)                     ; writing: compare three longs (start, middle, end) with the copy buffer
	bne.s	.next_verify
	movea.l	buffer_start,a0
	move.l	$2(a4),$32(sp)
	move.l	(a0),d0
	movea.l	$32(sp),a1
	cmp.l	(a1),d0
	bne.s	.compare_error
	move.l	$fc(a0),d1
	cmp.l	$fc(a1),d1
	bne.s	.compare_error
	move.l	$1fc(a0),d2
	cmp.l	$1fc(a1),d2
	beq.s	.next_verify
.compare_error
	moveq	#6,d4                           ; difference: error 6 (bad checksum)
	bra.s	.verify_error

.next_verify
	addq.w	#1,d7
.verify_test
	cmp.w	(a5),d7
	bcs.w	.next_sector
	bra.w	.ok

.error
	move.w	$36(sp),d0                      ; error: drive letter of source or destination
	bne.s	.dest_letter
	move.b	-$5(a5),d3                      ; -> src_unit+1
	bra.s	.drive_letter

.dest_letter
	move.b	-$3(a5),d3                      ; -> dst_unit+1
.drive_letter
	dc.w	$d63c,$0041                     ; add.b #$41,d3
	cmp.w	#$3,d4                          ; write protected: "Please remove WRITE-PROTECTION"
	bne.s	.error_box
	move.b	d3,alert_please_remove_write+52
	lea	alert_please_remove_write,a0
	moveq	#1,d0
	jsr	alert
	subq.w	#2,d0
	bne.w	.retry_result
	bra.w	.abort

.error_box
	lea	error_tree_ptr,a4               ; error box: "Error while <operation> Track of Drive X:"
	movea.l	(a4),a0                         ; BEST MATCH state saved
	move.w	$6a(a0),d7
	lea	-$1ab(a2),a1                    ; -> str_error_while
	movea.l	a3,a0
	jsr	strcpy
	move.w	$38(sp),d0                      ; operation text
	cmp.w	#$5,d0
	bhi.w	.drive_text
	add.w	d0,d0
	move.w	.table(pc,d0.w),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	.formatting_0-.table,.verifying-.table,.scanning-.table,.writing-.table
	dc.w	.reading-.table,.formatting-.table
.writing
	move.b	cfg_smart_format,d0             ; writing with Smart Formatting: format the track and write again
	beq.s	.offer_format
	move.b	cfg_format_dest,d1
	bne.s	.offer_format
	move.b	#$1,cfg_format_dest
	lea	str_format_writing,a0           ; "Format. & Writing"
	jsr	draw_progress_text
	move.l	copy_buffer_end,track_buffer
	bra.s	.format_retry

.offer_format
	move.b	cfg_format_dest,d0              ; writing without formatting: offer to format
	bne.s	.text_writing
	movea.l	copy_buffer_end,a0
	suba.l	copy_read_ptr,a0
	cmpa.l	$18(a5),a0                      ; -> track_image_size
	bcs.s	.text_writing
	lea	alert_write_error_on_track_format,a0 ; "Write Error on Track! Format it and try again? [YES|NO]"
	moveq	#1,d0
	jsr	alert
	subq.w	#1,d0
	bne.s	.text_writing
	movea.l	copy_buffer_end,a0
	suba.l	$18(a5),a0                      ; -> track_image_size
	move.l	a0,track_buffer
.format_retry
	move.w	d5,d1                           ; format the track, then RETRY
	move.w	$36(sp),d0
	jsr	seek_track
	jsr	build_track_image
	move.w	d5,d1
	move.w	d6,d0
	jsr	format_track
	move.b	cfg_format_dest,d0
	bne.w	.retry_result
	clr.l	fdc_state+fs_order_ptr          ; the next write uses the normal sector order again
	bra.w	.retry_result

.text_writing
	lea	-$165(a2),a1                    ; -> str_writing
	movea.l	a3,a0
	jsr	strcat
	bra.s	.drive_text

.reading
	lea	-$16d(a2),a1                    ; -> str_reading
	movea.l	a3,a0
	jsr	strcat
	bra.s	.drive_text

.scanning
	lea	-$176(a2),a1                    ; -> str_scanning
	movea.l	a3,a0
	jsr	strcat
	bra.s	.drive_text

.formatting_0
	jsr	disable_status_box              ; Formatting (0) also disables BEST MATCH
.formatting
	lea	-$18b(a2),a1                    ; -> str_formatting
	movea.l	a3,a0
	jsr	strcat
	bra.s	.drive_text

.verifying
	lea	-$180(a2),a1                    ; -> str_verifying
	movea.l	a3,a0
	jsr	strcat
.drive_text
	move.b	d3,-$18e(a2)                    ; drive letter into "Track of Drive X:", -> str_track_of_drive_x+16
	lea	-$19e(a2),a1                    ; -> str_track_of_drive_x
	movea.l	a3,a0
	jsr	strcat
	movea.l	(a4),a0                         ; the text goes into the error box
	movea.l	$24(a0),a1
	move.l	a3,(a1)
	movea.l	(a4),a0                         ; center the box over the track map
	move.w	$14(a0),d3
	move.w	$16(a0),$2a(sp)
	move.w	work_w,d0
	sub.w	d3,d0
	ext.l	d0
	divs.w	#$2,d0
	add.w	work_x,d0
	move.w	d0,$10(a0)
	move.w	d0,$2c(sp)
	movea.l	main_tree_ptr,a0
	move.w	$d2(a0),d6
	add.w	window_y,d6
	movea.l	(a4),a1
	move.w	d6,$12(a1)
	movea.l	(a4),a0
	clr.w	d0
	jsr	draw_object                     ; draw it, bell
	moveq	#7,d0
	jsr	Cconout
	pea	$11e(a2)                        ; help text and shortcuts, -> str_c_continue_b_best_match_n
	lea	$10e(a2),a1                     ; -> keys_error
	clr.w	d0
	movea.l	(a4),a0
	jsr	form_do                         ; RETRY, CONTINUE, BEST MATCH, NEW DISK or ABORT
	addq.w	#4,sp
	move.w	d0,$2e(sp)
	ext.l	d0
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	lsl.l	#3,d1
	movea.l	(a4),a0
	andi.w	#$fffe,$a(a0,d1.l)
	tst.w	d7
	bne.s	.remove_box
	jsr	enable_status_box
.remove_box
	moveq	#8,d0                           ; remove the box by redrawing the main dialog under it
	add.w	$2a(sp),d0
	move.w	d0,-(sp)
	moveq	#8,d1
	add.w	d3,d1
	move.w	d1,-(sp)
	move.w	d6,-(sp)
	move.w	$32(sp),d2
	movea.l	main_tree_ptr,a0
	clr.w	d0
	moveq	#8,d1
	jsr	objc_draw
	addq.w	#6,sp
	move.w	$2e(sp),d0                      ; clicked button to the result
	subq.w	#2,d0
	cmp.w	#$4,d0
	bhi.s	.ok
	add.w	d0,d0
	move.w	.table2(pc,d0.w),d0
	jmp	.table2(pc,d0.w)

.table2
	dc.w	.retry-.table2,.continue-.table2,.best_match-.table2,.new_disk-.table2
	dc.w	.abort-.table2
.abort
	moveq	#1,d0                           ; ABORT: 1
	bra.s	.return

.retry
	cmpi.b	#$1,cfg_retries                 ; RETRY: 2; with fewer than two retries recalibrate first
	bhi.s	.retry_result
	move.w	d5,d1
	move.w	$36(sp),d0
	jsr	restore_drive
.retry_result
	moveq	#2,d0
	bra.s	.return

.continue
	clr.w	d0                              ; CONTINUE: 0
	bra.s	.return

.best_match
	moveq	#3,d0                           ; BEST MATCH: 3
	bra.s	.return

.new_disk
	jsr	draw_progress_frame             ; NEW DISK: 5
	moveq	#5,d0
	bra.s	.return

.ok
	moveq	#4,d0                           ; OK: 4
.return
	lea	$3a(sp),sp
	movem.l	(sp)+,d3-d7/a2-a5
	rts


enable_status_box:
	movea.l	error_tree_ptr,a0
	clr.w	$6a(a0)
	rts


disable_status_box:
	movea.l	error_tree_ptr,a0
	move.w	#$8,$6a(a0)
	rts


enable_status_button:
	movea.l	error_tree_ptr,a0
	clr.w	$82(a0)
	rts


disable_status_button:
	movea.l	error_tree_ptr,a0
	move.w	#$8,$82(a0)
	rts


show_status_line:
	move.l	a2,-(sp)
	movea.l	a0,a2
	jsr	linea_defaults
	lea	str_status_empty,a0
	jsr	draw_status_text
	movea.l	a2,a0
	jsr	draw_progress_text
	movea.l	(sp)+,a2
	rts


alloc_track_buffers:
	move.l	d3,-(sp)                        ; buffers from the free memory: track image, FAT, then the copy buffer
	move.l	a2,-(sp)
	clr.l	verify_buffer
	lea	config,a0                       ; track image: 13000 bytes HD, 7000 DD
	move.b	$6e(a0),d0                      ; -> cfg_hd
	beq.s	.dd_image
	move.w	#$32c8,d1
	bra.s	.set_image_size

.dd_image
	move.w	#$1b58,d1
.set_image_size
	ext.l	d1
	move.l	d1,track_image_size
	lea	copy_buffer,a2
	move.l	buffer_free,(a2)
	move.b	$5f(a0),d0                      ; only when formatting, -> cfg_format_dest
	beq.s	.fat_room
	move.l	(a2),track_buffer
	add.l	d1,(a2)
.fat_room
	move.b	$64(a0),d0                      ; FAT of the disk when only used sectors are copied, -> cfg_used_only
	beq.s	.show_memory
	move.b	$63(a0),d1                      ; -> cfg_read_config
	beq.s	.show_memory
	move.l	(a2),fat_buffer
	move.w	bpb+bpb_fsiz,d0
	move.w	bpb,d1
	jsr	mul_words
	move.l	d0,d3
	add.l	d3,(a2)
	movea.l	(a2),a0
	cmpa.l	buffer_end,a0
	bcs.s	.clear_fat
	move.l	buffer_end,d3
	sub.l	fat_buffer,d3
.clear_fat
	move.l	d3,d1                           ; cleared
	clr.w	d0
	movea.l	fat_buffer,a0
	jsr	memset
.show_memory
	clr.b	d0                              ; memory bar
	movea.l	(a2),a0
	jsr	draw_memory_bar
	movea.l	(sp)+,a2
	move.l	(sp)+,d3
	rts


draw_status_labels:
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	d2
	clr.w	d1
	clr.w	d0
	jsr	set_clip
	addq.w	#4,sp
	moveq	#15,d1
	moveq	#33,d0
	lea	str_side,a0
	jsr	draw_text_line
	moveq	#15,d1
	moveq	#22,d0
	lea	str_track,a0
	jsr	draw_text_line
	moveq	#15,d1
	moveq	#42,d0
	lea	str_status,a0
	jsr	draw_text_line
	rts


mark_bad_sectors:
	movem.l	d3-d5/a2-a6,-(sp)               ; d0 drive, d1 side, d2 track; a0 bad cluster list or 0; stack: ask flag
	subq.w	#4,sp
	move.w	d0,d3
	move.w	d1,$2(sp)
	movea.l	a0,a5
	lea	bpb,a6
	tst.w	d0
	bne.s	.dest_sectors
	move.w	$22(a6),d0                      ; -> src_sectors
	bra.s	.sides

.dest_sectors
	move.w	$24(a6),d0                      ; -> dst_sectors
.sides
	tst.w	d3
	bne.s	.dest_sides
	move.w	$26(a6),d1                      ; -> src_sides
	bra.s	.first_sector

.dest_sides
	move.w	$28(a6),d1                      ; -> dst_sides
.first_sector
	addq.w	#1,d1                           ; first sector number of the track
	move.w	d2,d4
	mulu.w	d1,d4
	add.w	$2(sp),d4
	mulu.w	d0,d4
	move.w	d4,(sp)
	lea	sector_list,a2
	lea	buffer_start,a3
	lea	alert_sector,a4
	bra.w	.sector_test

.next_sector
	clr.w	d5                              ; each listed sector:
	move.b	(a2)+,d5
	move.w	(sp),d4
	add.w	d5,d4
	subq.w	#1,d4
	move.w	$28(sp),d0
	beq.w	.mark
	clr.b	-(sp)                           ; read it again
	movea.l	(a3),a0
	move.w	d5,d2
	move.w	$4(sp),d1
	move.w	d3,d0
	jsr	read_sectors
	addq.w	#2,sp
	move.w	d0,d2
	tst.w	d0
	beq.w	.sector_test
	movea.l	a4,a1                           ; "[1][Sector nn is damaged|" and "free! [MARK BAD]" or "but used! [NOTICED]"
	movea.l	(a3),a0
	jsr	strcpy
	movea.l	(a3),a0
	jsr	strlen
	movea.l	(a3),a0
	adda.l	d0,a0
	move.w	d5,d0
	moveq	#10,d1
	jsr	itoa
	lea	$c(a4),a1                       ; -> str_is_damaged
	movea.l	(a3),a0
	jsr	strcat
	move.w	d4,d0
	jsr	sector_is_used
	move.w	d0,d5
	tst.w	d0
	beq.s	.free
	lea	$30(a4),a1                      ; -> str_but_used_noticed
	bra.s	.ask

.free
	lea	$19(a4),a1                      ; -> str_and_free_mark_bad
.ask
	movea.l	(a3),a0
	jsr	strcat
	movea.l	(a3),a0
	moveq	#1,d0
	jsr	request_alert
	tst.w	d5                              ; used: into the bad cluster list for the report
	beq.s	.mark
	move.l	a5,d0
	beq.s	.sector_test
	cmp.w	$c(a6),d4                       ; -> bpb+bpb_datrec
	bcs.s	.count
	cmp.l	buffer_end,d0
	bcc.s	.count
	move.w	d4,d1
	sub.w	$c(a6),d1                       ; -> bpb+bpb_datrec
	moveq	#0,d2
	move.w	d1,d2
	divu.w	$2(a6),d2                       ; -> bpb+bpb_clsiz
	addq.w	#2,d2
	movea.l	(a5),a0
	addq.l	#2,(a5)
	move.w	d2,(a0)
	bra.s	.count

.mark
	move.w	d4,d0                           ; free: mark its cluster bad in the FAT
	jsr	mark_bad_cluster
.count
	addq.w	#1,$12(a6)                      ; count it, -> bad_sectors
.sector_test
	move.b	(a2),d0
	bne.w	.next_sector
	addq.w	#4,sp
	movem.l	(sp)+,d3-d5/a2-a6
	rts


mark_bad_cluster:
	cmp.w	bpb+bpb_datrec,d0
	bcs.s	.return
	move.w	#$fff7,d1
	sub.w	bpb+bpb_datrec,d0
	moveq	#0,d2
	move.w	d0,d2
	move.l	d2,d0
	divu.w	bpb+bpb_clsiz,d0
	addq.w	#2,d0
	movea.l	fat_buffer,a0
	jsr	set_fat_entry
.return
	rts


write_fats:
	move.w	d3,-(sp)                        ; writes both FATs of drive d0 from fat_buffer; returns 1 when given up
	move.l	d4,-(sp)
	move.w	d0,d3
.fat_1
	move.w	d3,d0
	jsr	Getbpb
	move.w	d3,-(sp)
	moveq	#1,d2
	move.w	bpb+bpb_fsiz,d1
	movea.l	fat_buffer,a0
	moveq	#1,d0
	jsr	rwabs_checked
	addq.w	#2,sp
	move.l	d0,d4
	tst.w	d4
	bge.s	.fat_2
.write_error
	cmp.w	#$fff3,d4                       ; write protected: "Please remove WRITE-PROTECTION"
	bne.s	.other_error
	moveq	#65,d0
	add.b	d3,d0
	move.b	d0,alert_please_remove_write+52
	lea	alert_please_remove_write,a0
	moveq	#1,d0
	jsr	alert
	subq.w	#1,d0
	beq.s	.fat_1
	bra.s	.failed

.other_error
	lea	alert_cannot_write_the_fats_retry,a0 ; "Cannot write the FATs! [RETRY|ABORT]"
	moveq	#1,d0
	jsr	alert
	subq.w	#1,d0
	beq.s	.fat_1
.failed
	moveq	#1,d0
	bra.s	.return

.fat_2
	move.w	d3,-(sp)
	moveq	#1,d2
	add.w	bpb+bpb_fsiz,d2
	move.w	bpb+bpb_fsiz,d1
	movea.l	fat_buffer,a0
	moveq	#1,d0
	jsr	rwabs_checked
	addq.w	#2,sp
	move.l	d0,d4
	tst.w	d4
	blt.s	.write_error
	clr.w	d0
.return
	move.l	(sp)+,d4
	move.w	(sp)+,d3
	rts


;----------------------------------------------------------------------
; Reads the boot sector of drive d0 and sets the disk configuration (sides,
; sectors, tracks, density) of the main dialog from it.
;----------------------------------------------------------------------
read_disk_config:
	movem.l	d3-d6/a2-a4,-(sp)               ; a0 buffer, d0 drive, d1 show it in the dialog; returns 0 when read
	movea.l	a0,a3
	move.w	d0,d4
	move.w	d1,d6
	moveq	#-1,d3
	moveq	#2,d0
	suba.l	a0,a0
	jsr	graf_mouse
	move.w	d4,d0
	jsr	drive_hd_mode                   ; drive density settings
.read_boot
	lea	config,a4                       ; media change, Getbpb, read the boot sector
	move.w	d4,-(sp)
	clr.w	d2
	moveq	#2,d1
	suba.l	a0,a0
	clr.w	d0
	jsr	Rwabs
	addq.w	#2,sp
	move.w	d4,d0
	jsr	Getbpb
	movea.l	a0,a2
	move.l	a2,d0
	beq.s	.failed
	movea.l	a2,a1
	lea	bpb,a0
	moveq	#18,d0
	jsr	memcpy
	move.w	d4,-(sp)
	clr.w	d2
	moveq	#1,d1
	movea.l	a3,a0
	clr.w	d0
	jsr	Rwabs
	addq.w	#2,sp
	tst.l	d0
	beq.s	.check_sides
.failed
	addq.w	#1,d3                           ; failed once on an HD drive with detection: try the other density
	tst.w	d3
	bne.s	.cannot_read
	move.b	drive_density,d0
	beq.s	.cannot_read
	move.b	$50(a4),d1                      ; -> cfg_hd_detect
	beq.s	.cannot_read
	jsr	detect_hd_disk
	tst.w	d0
	bne.s	.try_dd
	moveq	#1,d0
	bra.s	.switch_density

.try_dd
	clr.w	d0
.switch_density
	jsr	set_hd_mode
	bra.w	.read_boot

.cannot_read
	lea	alert_cannot_read_disk,a0       ; "Cannot read Disk-Configuration!"
	moveq	#1,d0
	jsr	alert
	suba.l	a0,a0
	clr.w	d0
	jsr	graf_mouse
	moveq	#1,d0
	bra.w	.return

.check_sides
	clr.w	d0                              ; sides from the boot sector (1 or 2)
	move.b	$1a(a3),d0
	subq.w	#1,d0
	move.w	d0,$66(a4)                      ; -> cfg_sides
	cmp.w	#$1,d0
	beq.s	.check_sectors
	tst.w	d0
	bne.s	.failed
.check_sectors
	clr.w	d5                              ; sectors per track 1..23
	move.b	$18(a3),d5
	move.w	d5,$68(a4)                      ; -> cfg_sectors
	cmp.w	#$1,d5
	blt.s	.failed
	cmp.w	#$17,d5
	bgt.w	.failed
	clr.w	d1                              ; sector count, at most $102c
	move.b	$13(a3),d1
	clr.w	d2
	move.b	$14(a3),d2
	lsl.w	#8,d2
	add.w	d2,d1
	move.w	d1,disk_sectors
	tst.w	d1
	blt.w	.failed
	cmp.w	#$102c,d1
	bgt.w	.failed
	clr.w	$6a(a4)                         ; tracks = sectors / (sides * sectors per track), -> cfg_start_track
	move.w	d1,d3
	ext.l	d3
	moveq	#1,d4
	add.w	d0,d4
	muls.w	d5,d4
	divs.w	d4,d3
	subq.w	#1,d3
	move.w	d3,$6c(a4)                      ; -> cfg_end_track
	move.b	drive_density,d0                ; density: from the HD detection or from more than 11 sectors
	beq.s	.dd_drive
	move.b	$50(a4),d1                      ; -> cfg_hd_detect
	beq.s	.by_sectors
	jsr	detect_hd_disk
	move.b	d0,$6e(a4)                      ; -> cfg_hd
	bra.s	.show

.by_sectors
	cmp.w	#$b,d5
	ble.s	.dd
	moveq	#1,d0
	bra.s	.store_hd

.dd
	clr.b	d0
.store_hd
	move.b	d0,$6e(a4)                      ; -> cfg_hd
	bra.s	.show

.dd_drive
	clr.b	$6e(a4)                         ; -> cfg_hd
.show
	tst.w	d6
	beq.s	.done
	jsr	show_disk_config
	jsr	set_sides_density
.done
	suba.l	a0,a0
	clr.w	d0
	jsr	graf_mouse
	clr.w	d0
.return
	movem.l	(sp)+,d3-d6/a2-a4
	rts


;----------------------------------------------------------------------
; Sets the HD mode of drive d0 through the PSG port A bit chosen in the options
; (cfg_hd_detect).
;----------------------------------------------------------------------
set_hd_mode:
	move.w	d3,-(sp)                        ; cfg_hd_detect: 1 bit 6 inverted, 2 bit 6, 3 bit 7 inverted, 4 bit 7; 0 automatic
	move.w	d0,d3
	clr.w	d1
	move.b	cfg_hd_detect,d1
	subq.w	#1,d1
	beq.s	.bit6_inverted
	subq.w	#1,d1
	beq.s	.bit6_direct
	subq.w	#1,d1
	beq.s	.bit7_inverted
	subq.w	#1,d1
	beq.s	.bit7_direct
	bra.s	.return

.bit6_inverted
	tst.w	d3
	bne.s	.bit6_hd
	moveq	#1,d1
	bra.s	.write_bit6

.bit6_hd
	clr.w	d1
.write_bit6
	moveq	#6,d0
	jsr	write_psg_port_bit
	bra.s	.return

.bit6_direct
	move.w	d3,d1
	moveq	#6,d0
	jsr	write_psg_port_bit
	bra.s	.return

.bit7_inverted
	tst.w	d3
	bne.s	.bit7_hd
	moveq	#1,d1
	bra.s	.write_bit7

.bit7_hd
	clr.w	d1
.write_bit7
	moveq	#7,d0
	jsr	write_psg_port_bit
	bra.s	.return

.bit7_direct
	move.w	d3,d1
	moveq	#7,d0
	jsr	write_psg_port_bit
.return
	move.w	(sp)+,d3
	rts


;----------------------------------------------------------------------
; Reads the HD detect bit of the PSG port A (cfg_hd_detect).
;----------------------------------------------------------------------
detect_hd_disk:
	clr.w	d0                              ; HD disk in the drive? From the PSG port A bit chosen by cfg_hd_detect
	move.b	cfg_hd_detect,d0
	subq.w	#1,d0
	beq.s	.bit6_inverted
	subq.w	#1,d0
	beq.s	.bit6_direct
	subq.w	#1,d0
	beq.s	.bit7_inverted
	subq.w	#1,d0
	beq.s	.bit7_direct
	bra.s	.automatic

.bit6_inverted
	moveq	#6,d0
	jsr	read_psg_port_bit
	tst.w	d0
	bne.s	.dd
	moveq	#1,d0
	bra.s	.return

.dd
	clr.w	d0
.return
	rts

.bit6_direct
	moveq	#6,d0
	jsr	read_psg_port_bit
	rts

.bit7_inverted
	moveq	#7,d0
	jsr	read_psg_port_bit
	tst.w	d0
	bne.s	.dd_7
	moveq	#1,d0
	bra.s	.return_7

.dd_7
	clr.w	d0
.return_7
	rts

.bit7_direct
	moveq	#7,d0
	jsr	read_psg_port_bit
	rts

.automatic
	clr.w	d0
	rts


bpb_from_config:
	movem.l	d3-d4/a2,-(sp)                  ; BPB for d0 = sides - 1, d1 = end track, d2 = sectors; stack flag keeps the cluster size
	lea	bpb,a2
	moveq	#1,d3                           ; disk_sectors
	add.w	d1,d3
	mulu.w	d2,d3
	moveq	#1,d4
	add.w	d0,d4
	mulu.w	d4,d3
	move.w	d3,$3a(a2)                      ; -> disk_sectors
	move.w	$10(sp),d0
	bne.s	.fat_size
	cmp.w	#$168,d3                        ; clusters of 2 sectors above 360 sectors, else 1
	bls.s	.one_sector_clusters
	moveq	#2,d1
	bra.s	.set_cluster_size

.one_sector_clusters
	moveq	#1,d1
.set_cluster_size
	move.w	d1,$2(a2)                       ; -> bpb+bpb_clsiz
.fat_size
	jsr	bpb_fat_size                    ; FAT size
	moveq	#0,d0                           ; root directory: one sector per 240 disk sectors, at most 15
	move.w	$3a(a2),d0                      ; -> disk_sectors
	divu.w	#$f0,d0
	addq.w	#1,d0
	move.w	d0,$6(a2)                       ; -> bpb+bpb_rdlen
	cmp.w	#$10,d0
	bcs.s	.data_start
	move.w	#$f,$6(a2)                      ; -> bpb+bpb_rdlen
.data_start
	jsr	bpb_data_start                  ; data start, 512 byte sectors, FAT12
	move.w	#$200,(a2)
	clr.w	$10(a2)                         ; -> bpb+bpb_bflags
	movem.l	(sp)+,d3-d4/a2
	rts


bpb_fat_size:
	moveq	#0,d0
	move.w	disk_sectors,d0
	move.w	bpb+bpb_clsiz,d1
	mulu.w	#$154,d1
	divu.w	d1,d0
	addq.w	#1,d0
	move.w	d0,bpb+bpb_fsiz
	rts


bpb_data_start:
	lea	bpb,a0
	move.w	$8(a0),d0                       ; -> bpb+bpb_fsiz
	add.w	d0,d0
	add.w	$6(a0),d0                       ; -> bpb+bpb_rdlen
	addq.w	#1,d0
	move.w	d0,$c(a0)                       ; -> bpb+bpb_datrec
	rts


media_byte:
	move.l	d3,-(sp)                        ; d0 = sides - 1, d1 = tracks, d2 = sectors
	cmp.w	#$f,d2                          ; 15 sectors: $f9
	bne.s	.not_15
	move.b	#$f9,d0
	bra.s	.return

.not_15
	cmp.w	#$12,d2                         ; 18 and more: $f0
	bcs.s	.dd
	move.b	#$f0,d0
	bra.s	.return

.dd
	cmp.w	#$2d,d1                         ; DD: $f8 + 4 for 40 tracks + 2 for 8 sectors + 1 for double sided
	bls.s	.single_sided
	clr.b	d3
	bra.s	.eight_sectors

.single_sided
	moveq	#4,d3
.eight_sectors
	move.b	d3,-(sp)
	cmp.w	#$8,d2
	bne.s	.nine_sectors
	moveq	#2,d3
	bra.s	.combine

.nine_sectors
	clr.b	d3
.combine
	add.b	(sp)+,d3
	add.b	d0,d3
	dc.w	$d63c,$00f8                     ; add.b #$f8,d3
	move.b	d3,d0
.return
	move.l	(sp)+,d3
	rts


;----------------------------------------------------------------------
; Puts the Guardian into the boot sector in a0 and makes it executable.
;----------------------------------------------------------------------
put_guardian:
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	movea.l	a0,a2
	move.w	#$6038,(a0)
	lea	guardian_show,a3
	lea	read_directory_tree,a1
	move.l	a1,d0
	sub.l	a3,d0
	movea.l	a3,a1
	lea	$1e(a2),a0
	jsr	memcpy
	movea.l	a2,a0
	jsr	make_boot_executable
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


;----------------------------------------------------------------------
; Builds a boot sector in a0 with Protobt and FastCopy's BPB values.
;----------------------------------------------------------------------
build_boot_sector:
	movem.l	d3-d5/a2-a3,-(sp)               ; a0 buffer, d0 sides - 1, d1 end track, d2 sectors
	movea.l	a0,a2
	move.w	d0,d5
	move.w	d1,d4
	move.w	d2,d3
	clr.w	d0
	move.l	#$200,d1
	jsr	memset
	moveq	#-1,d2                          ; Protobt: random serial, type 3 (2 sides 80 tracks), not executable
	moveq	#3,d1
	move.l	#$1111111,d0
	movea.l	a2,a0
	jsr	Protobt
	moveq	#8,d0                           ; branch and OEM name "IBM  "
	lea	boot_sector_start,a1
	movea.l	a2,a0
	jsr	memcpy
	lea	bpb,a3                          ; BPB values: cluster size, directory entries, sector count,
	move.b	$3(a3),$d(a2)                   ; -> bpb+3
	move.b	$7(a3),d0                       ; -> bpb+7
	lsl.b	#4,d0
	move.b	d0,$11(a2)
	move.b	$3b(a3),d1                      ; -> disk_sectors+1
	dc.w	$c23c,$00ff                     ; and.b #$ff,d1
	move.b	d1,$13(a2)
	move.w	$3a(a3),d0                      ; -> disk_sectors
	lsr.w	#8,d0
	move.b	d0,$14(a2)
	move.w	d3,d2                           ; media byte, FAT size, sectors per track, sides
	move.w	d4,d1
	move.w	d5,d0
	jsr	media_byte(pc)
	move.b	d0,$15(a2)
	move.b	$9(a3),$16(a2)                  ; -> bpb+9
	move.b	d3,$18(a2)
	moveq	#1,d0
	add.b	d5,d0
	move.b	d0,$1a(a2)
	lea	str_fastcopy_pro_1_2_by_martin,a1 ; FastCopy's name in the boot code area
	lea	$20(a2),a0
	jsr	strcpy
	movem.l	(sp)+,d3-d5/a2-a3
	rts


;----------------------------------------------------------------------
; Keys while copying (from the keyboard buffer): Esc or Space interrupts, F
; toggles Format Destination, M Multiple Copy, T Smart Formatting, V Verify.
;----------------------------------------------------------------------
check_keyboard:
	movem.l	d3/a2-a6,-(sp)                  ; d3: which keys are allowed (bits 0 V, 1/2 F, 3/4 T, 5 M)
	move.w	d0,d3
	jsr	Cconis                          ; nothing typed: not interrupted
	tst.w	d0
	beq.w	.not_interrupted
	lea	config,a2
	lea	copy_buffer_end,a3
	lea	track_image_size,a4
	lea	str_writing_2,a5
	lea	str_format_writing,a6
	jsr	Crawcin                         ; read the key
	moveq	#9,d1
	lea	.table(pc),a0
.find_key
	cmp.w	(a0)+,d0
	dbeq	d1,.find_key
	bne.w	.flush_keys
	move.w	$12(a0),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	$1b,$20,$46,$4d,$54,$56,$66,$6d
	dc.w	$74,$76
	dc.w	.key_esc-.table,.key_esc-.table,.key_f-.table,.key_m-.table
	dc.w	.key_t-.table,.key_v-.table,.key_f-.table,.key_m-.table
	dc.w	.key_t-.table,.key_v-.table
.key_esc
	lea	alert_interruption_abort_cont,a0 ; Esc or Space: "Interruption! [ABORT|CONT]"
	moveq	#1,d0
	jsr	alert
	subq.w	#1,d0
	bne.w	.flush_keys
	moveq	#1,d0
	bra.w	.return

.key_m
	moveq	#32,d0                          ; M: Multiple Copy on (9999 copies) or off
	and.w	d3,d0
	beq.w	.flush_keys
	move.b	first_pass,d1
	beq.w	.flush_keys
	move.b	$61(a2),d2                      ; -> cfg_multiple_copy
	beq.s	.multiple_on
	clr.b	$61(a2)                         ; -> cfg_multiple_copy
	move.w	#$1,copies
	bra.s	.multiple_done

.multiple_on
	move.b	#$1,$61(a2)                     ; -> cfg_multiple_copy
	move.w	#$270f,copies
.multiple_done
	clr.w	copy_count
	moveq	#7,d0
	jsr	Cconout
	move.b	$61(a2),d0                      ; -> cfg_multiple_copy
	beq.s	.multiple_box_off
	moveq	#1,d1
	bra.s	.multiple_box

.multiple_box_off
	clr.w	d1
.multiple_box
	moveq	#40,d0
	jsr	set_state_draw
	bra.w	.flush_keys

.key_v
	moveq	#1,d0                           ; V: Verify Destination on or off
	and.w	d3,d0
	beq.w	.flush_keys
	move.b	$60(a2),d1                      ; -> cfg_verify_dest
	beq.s	.verify_on
	clr.b	$60(a2)                         ; -> cfg_verify_dest
	bra.s	.verify_done

.verify_on
	move.b	#$1,$60(a2)                     ; -> cfg_verify_dest
.verify_done
	moveq	#7,d0
	jsr	Cconout
	move.b	$60(a2),d0                      ; -> cfg_verify_dest
	beq.s	.verify_box_off
	moveq	#1,d1
	bra.s	.verify_box

.verify_box_off
	clr.w	d1
.verify_box
	moveq	#33,d0
	jsr	set_state_draw
	bra.w	.flush_keys

.key_t
	moveq	#8,d0                           ; T: Smart Formatting on or off
	and.w	d3,d0
	bne.s	.smart_toggle
	moveq	#16,d1
	and.w	d3,d1
	beq.w	.flush_keys
.smart_toggle
	move.l	(a3),d0
	beq.w	.flush_keys
	move.b	$5a(a2),d1                      ; -> cfg_smart_format
	bne.s	.smart_off
	sub.l	copy_read_ptr,d0                ; needs room for a track image
	cmp.l	(a4),d0
	bcs.w	.no_memory
	move.b	#$1,$5a(a2)                     ; -> cfg_smart_format
	move.l	(a4),d1
	sub.l	d1,(a3)
	clr.b	$5f(a2)                         ; -> cfg_format_dest
	moveq	#8,d0
	and.w	d3,d0
	beq.s	.smart_box_on
	movea.l	a5,a0
	jsr	draw_progress_text
.smart_box_on
	moveq	#7,d0
	jsr	Cconout
	moveq	#1,d1
	moveq	#35,d0
	jsr	set_state_draw
	jsr	update_smart_format
	bra.w	.flush_keys

.smart_off
	clr.b	$5a(a2)                         ; off: the track image space goes back to the buffer, -> cfg_smart_format
	move.b	$5f(a2),d0                      ; -> cfg_format_dest
	bne.s	.smart_off_text
	move.l	(a4),d1
	add.l	d1,(a3)
.smart_off_text
	moveq	#8,d0
	and.w	d3,d0
	beq.s	.smart_box_off
	move.b	$5f(a2),d1                      ; -> cfg_format_dest
	beq.s	.text_writing
	movea.l	a6,a0
	bra.s	.show_text

.text_writing
	movea.l	a5,a0
.show_text
	jsr	draw_progress_text
.smart_box_off
	moveq	#7,d0
	jsr	Cconout
	clr.w	d1
	moveq	#35,d0
	jsr	set_state_draw
	jsr	update_smart_format
	move.b	$5f(a2),d0                      ; -> cfg_format_dest
	beq.s	.format_box_off
	moveq	#1,d1
	bra.s	.format_box

.format_box_off
	clr.w	d1
.format_box
	moveq	#37,d0
	jsr	set_state_draw
	bra.w	.flush_keys

.key_f
	moveq	#2,d0                           ; F: Format Destination on or off
	and.w	d3,d0
	bne.s	.format_toggle
	moveq	#4,d1
	and.w	d3,d1
	beq.w	.flush_keys
.format_toggle
	move.l	(a3),d0
	beq.w	.flush_keys
	move.b	$5f(a2),d1                      ; -> cfg_format_dest
	bne.w	.format_off
	move.b	$5a(a2),d2                      ; with Smart Formatting: "Formatting is now ON.", -> cfg_smart_format
	beq.s	.format_on
	moveq	#7,d0
	jsr	Cconout
	lea	alert_formatting_is_now_on_ok,a0
	moveq	#1,d0
	jsr	request_alert
	bra.s	.build_image

.format_on
	move.l	$4(a4),d0                       ; a track image buffer is still there, -> verify_buffer
	beq.s	.take_track_buffer
	moveq	#7,d0
	jsr	Cconout
	moveq	#1,d1
	moveq	#37,d0
	jsr	set_state_draw
	bra.s	.format_set

.take_track_buffer
	movea.l	(a3),a0                         ; take a track image from the buffer
	suba.l	copy_read_ptr,a0
	cmpa.l	(a4),a0
	bcs.s	.no_memory
	move.l	(a4),d0
	sub.l	d0,(a3)
	moveq	#7,d0
	jsr	Cconout
	moveq	#1,d1
	moveq	#37,d0
	jsr	set_state_draw
.build_image
	move.l	(a3),track_buffer               ; build the track image
	jsr	build_track_image
.format_set
	move.b	#$1,$5f(a2)                     ; -> cfg_format_dest
	moveq	#2,d0
	and.w	d3,d0
	beq.w	.flush_keys
	movea.l	a6,a0
	jsr	draw_progress_text
	bra.s	.flush_keys

.no_memory
	lea	alert_not_enough_memory_free_ok,a0 ; "Not enough memory free!"
	moveq	#1,d0
	jsr	alert
	bra.s	.flush_keys

.format_off
	clr.b	$5f(a2)                         ; off, -> cfg_format_dest
	moveq	#2,d0
	and.w	d3,d0
	beq.s	.format_off_order
	movea.l	a5,a0
	jsr	draw_progress_text
.format_off_order
	clr.l	fdc_state+fs_order_ptr
	moveq	#7,d0
	jsr	Cconout
	move.b	$5a(a2),d0                      ; -> cfg_smart_format
	bne.s	.smart_still_formats            ; with Smart Formatting: "Formatting is now OFF."
	movea.l	track_buffer,a0                 ; image at the buffer end: give it back, else keep it for a verify
	cmpa.l	(a3),a0
	bne.s	.keep_buffer
	move.l	(a4),d1
	add.l	d1,(a3)
	bra.s	.format_box_clear

.keep_buffer
	move.l	track_buffer,$4(a4)             ; -> verify_buffer
.format_box_clear
	clr.w	d1
	moveq	#37,d0
	jsr	set_state_draw
	bra.s	.flush_keys

.smart_still_formats
	lea	alert_formatting_is_now_off_ok,a0
	moveq	#1,d0
	jsr	request_alert
	bra.s	.flush_keys

.discard_key
	jsr	Crawcin                         ; empty the keyboard buffer
.flush_keys
	jsr	Cconis
	tst.w	d0
	bne.s	.discard_key
.not_interrupted
	clr.w	d0
.return
	movem.l	(sp)+,d3/a2-a6
	rts


drive_hd_mode:
	lea	config,a0
	lea	drive_density,a1
	tst.w	d0
	bne.s	.drive_b
	move.b	$48(a0),-$1(a1)                 ; -> cfg_a_double_sided, -> drive_double_sided
	move.b	$49(a0),(a1)                    ; -> cfg_a_density
	bra.s	.max_sectors

.drive_b
	move.b	$4a(a0),-$1(a1)                 ; -> cfg_b_double_sided, -> drive_double_sided
	move.b	$4b(a0),(a1)                    ; -> cfg_b_density
.max_sectors
	move.b	(a1),d0
	bne.s	.not_dd
	move.b	#$b,$1(a1)                      ; -> drive_max_sectors
	rts

.not_dd
	cmpi.b	#$1,(a1)
	bne.s	.hd_3
	move.b	#$12,$1(a1)                     ; -> drive_max_sectors
	rts

.hd_3
	move.b	#$16,$1(a1)                     ; -> drive_max_sectors
	rts


;----------------------------------------------------------------------
; Checks that the drives support the chosen sides, density and sectors.
;----------------------------------------------------------------------
check_drive_support:
	movem.l	d3/a2-a4,-(sp)                  ; d0: 0 source, 1 destination; drive limits against the disk configuration
	lea	config,a2
	tst.w	d0
	beq.s	.source
	move.b	$5e(a2),d1                      ; -> cfg_dest_drive
	bra.s	.drive_values

.source
	move.b	$5d(a2),d1                      ; -> cfg_source_drive
.drive_values
	clr.w	d3
	move.b	d1,d3
	move.w	d3,d0
	jsr	drive_hd_mode(pc)
	lea	drive_max_sectors,a3
	lea	alert_drive_x_does_only_support_xx,a4
	move.b	$6e(a2),d0                      ; density: "Drive X: doesn't support this High Density mode!", -> cfg_hd
	cmp.b	-$1(a3),d0                      ; -> drive_density
	bls.s	.check_sides
	moveq	#65,d1
	add.b	d3,d1
	move.b	d1,-$35(a4)                     ; -> alert_drive_x_doesnt_support_this+10
	lea	-$3f(a4),a0                     ; -> alert_drive_x_doesnt_support_this
	moveq	#1,d0
	jsr	alert
	bra.s	.not_supported

.check_sides
	clr.w	d0                              ; sides: "Drive X: is one-sided!"
	move.b	-$2(a3),d0                      ; -> drive_double_sided
	move.w	$66(a2),d1                      ; -> cfg_sides
	cmp.w	d0,d1
	ble.s	.check_sectors
	moveq	#65,d2
	add.b	d3,d2
	move.b	d2,-$5e(a4)                     ; -> alert_drive_x_is_one_sided_abort+10
	lea	-$68(a4),a0                     ; -> alert_drive_x_is_one_sided_abort
	moveq	#1,d0
	jsr	alert
	bra.s	.not_supported

.check_sectors
	clr.w	d0                              ; sectors: "Drive X: does only support XX Sectors per Track!"
	move.b	(a3),d0
	move.w	$68(a2),d1                      ; -> cfg_sectors
	cmp.w	d0,d1
	ble.s	.supported
	moveq	#65,d2
	add.b	d3,d2
	move.b	d2,$a(a4)                       ; -> alert_drive_x_does_only_support_xx+10
	ext.l	d0
	divs.w	#$a,d0
	dc.w	$d03c,$0030                     ; add.b #$30,d0
	move.b	d0,$1f(a4)                      ; -> alert_drive_x_does_only_support_xx+31
	clr.w	d3
	move.b	(a3),d3
	ext.l	d3
	divs.w	#$a,d3
	swap	d3
	dc.w	$d63c,$0030                     ; add.b #$30,d3
	move.b	d3,$20(a4)                      ; -> alert_drive_x_does_only_support_xx+32
	movea.l	a4,a0
	moveq	#1,d0
	jsr	alert
.not_supported
	jsr	check_config_fields             ; fields corrected, not supported
	clr.b	d0
	bra.s	.return

.supported
	moveq	#1,d0
.return
	movem.l	(sp)+,d3/a2-a4
	rts


rwabs_checked:
	movem.l	d3-d7/a2,-(sp)                  ; Rwabs with write protect detection and media change handling
	move.w	d0,d6
	movea.l	a0,a2
	move.w	d1,d5
	move.w	d2,d4
	move.w	$1c(sp),d3
.try
	move.w	d3,-(sp)
	move.w	d4,d2
	move.w	d5,d1
	movea.l	a2,a0
	move.w	d6,d0
	jsr	Rwabs
	addq.w	#2,sp
	move.l	d0,d7
	bge.s	.check_media
	cmp.w	#$2,d3                          ; floppy error: write protect bit of the FDC gives -13
	bge.s	.check_media
	jsr	read_fdc_status
	dc.w	$c07c,$40                       ; and.w #$40,d0
	beq.s	.check_media
	moveq	#-13,d0
	bra.s	.return

.check_media
	tst.w	d4
	bne.s	.done
	tst.l	d7
	beq.s	.media_changed
	moveq	#-14,d0
	cmp.l	d7,d0
	bne.s	.done
.media_changed
	move.w	d3,d0                           ; media changed on sector 0: force the change and continue with the next sectors
	jsr	force_media_change
	moveq	#0,d7
	cmp.w	#$1,d5
	ble.s	.done
	moveq	#0,d0
	move.w	bpb,d0
	adda.l	d0,a2
	subq.w	#1,d5
	addq.w	#1,d4
	bra.s	.try

.done
	move.l	d7,d0
.return
	movem.l	(sp)+,d3-d7/a2
	rts


make_boot_executable:
	clr.w	d1                              ; last word makes the word sum $1234
	move.w	d1,d2
	move.w	bpb,d0
	lsr.w	#1,d0
	subq.w	#1,d0
	bra.s	.word_test

.add_word
	add.w	(a0)+,d2
	addq.w	#1,d1
.word_test
	cmp.w	d1,d0
	bgt.s	.add_word
	move.w	#$1234,d0
	sub.w	d2,d0
	move.w	d0,(a0)
	rts


bpb_align_root:
	jsr	bpb_count_clusters(pc)
	lea	bpb,a0
	moveq	#0,d0
	move.w	$14(a0),d0                      ; -> data_sectors
	divu.w	$2(a0),d0                       ; -> bpb+bpb_clsiz
	swap	d0
	tst.w	d0
	beq.s	.return
	move.w	$6(a0),d1                       ; -> bpb+bpb_rdlen
	add.w	d0,d1
	cmp.w	#$10,d1
	bcc.s	.return
	add.w	d0,$6(a0)                       ; -> bpb+bpb_rdlen
.return
	rts


;----------------------------------------------------------------------
; Streamer: backs a hard disk partition up to floppies (READ) or restores it
; (WRITE).
;----------------------------------------------------------------------
streamer:
	movem.l	d3-d4/a2,-(sp)
	lea	str_select_destination_partition,a2
	lea	alert_read_from_partition_or_write,a0 ; "Read from Partition or write to Partition? [READ|WRITE|CANCEL]"
	moveq	#1,d0
	jsr	alert(pc)
	move.w	d0,d3
	subq.w	#1,d3
	bne.s	.write_or_cancel
	lea	str_select_source_partition,a2  ; READ: backup, choose the source partition
	bra.s	.choose_partition

.write_or_cancel
	cmp.w	#$2,d3
	beq.s	.return
.choose_partition
	movea.l	main_tree_ptr,a1                ; choose the partition
	clr.w	d2
	movea.l	a2,a0
	move.w	partition_drive,d1
	moveq	#1,d0
	jsr	select_drive(pc)
	move.w	d0,d4
	beq.s	.return
	jsr	draw_progress_frame(pc)
	moveq	#-1,d0
	add.w	d4,d0
	move.w	d0,partition_drive              ; partition drive, first disk is number 1
	move.w	#$1,disk_number
	tst.w	d3
	beq.s	.streamer_backup
	clr.w	d3                              ; restore; Optimize Partition is put back afterwards
	move.b	cfg_optimize_partition,d3
	jsr	streamer_restore(pc)
	move.b	d3,cfg_optimize_partition
	bra.s	.return

.streamer_backup
	jsr	streamer_backup(pc)
.return
	movem.l	(sp)+,d3-d4/a2
	rts


;----------------------------------------------------------------------
; Streamer restore: reads the backup floppies in order and writes the sectors
; back to the destination partition; with optimized writing only the used clusters,
; then the FAT and directories are updated.
;----------------------------------------------------------------------
streamer_restore:
	movem.l	d3-d7/a2-a6,-(sp)
	lea	-$46(sp),sp
	lea	config,a2
	lea	alert_write_error_on_partition_x,a3
	moveq	#65,d0                          ; drive letters into the messages
	add.b	$5d(a2),d0                      ; -> cfg_source_drive
	move.b	d0,$6d(a3)                      ; -> alert_x_source_disk+6
	move.b	partition_letter,d1
	move.b	d1,$58(a3)                      ; -> str_writing_drive_x+14
	move.b	d1,$1d(a3)                      ; -> alert_write_error_on_partition_x+29
	lea	str_reading_2,a0
	jsr	show_status_line(pc)
	clr.b	d0                              ; restoring neither reads the configuration nor formats
	move.b	d0,$63(a2)                      ; -> cfg_read_config
	move.b	d0,$5f(a2)                      ; -> cfg_format_dest
.ask_first_disk
	lea	floppy_sector,a4                ; ask for backup disk #1 until it is inserted
	lea	str_copy_abort,a1
	lea	$67(a3),a0                      ; -> alert_x_source_disk
	jsr	alert_disk_number(pc)
	subq.w	#2,d0
	beq.w	.return
	moveq	#1,d1                           ; read its boot sector
	clr.w	d0
	move.b	$5d(a2),d0                      ; -> cfg_source_drive
	movea.l	buffer_start,a0
	jsr	read_disk_config(pc)
	tst.w	d0
	bne.w	.return
	movea.l	buffer_start,a0                 ; $c0: disk number of this backup floppy
	clr.w	d0
	move.b	$c0(a0),d0
	cmp.w	-$6(a4),d0                      ; -> disk_number
	bne.s	.ask_first_disk
	move.b	$d4(a0),$44(sp)                 ; $d4 Compack: room for one packed block ($d6) and its header
	beq.s	.used_only
	move.l	$d6(a0),d1
	dc.w	$d2bc                           ; add.l #$400,d1
	dc.l	$400
	move.l	d1,$16(sp)
.used_only
	movea.l	buffer_start,a0                 ; $c1: the backup holds used clusters only
	move.b	$c1(a0),$64(a2)                 ; -> cfg_used_only
	lea	bpb,a5                          ; the backup data starts after the system sectors of the floppy:
	moveq	#0,d0
	move.w	$c(a5),d0                       ; -> bpb+bpb_datrec
	moveq	#1,d1
	add.w	$66(a2),d1                      ; -> cfg_sides
	muls.w	$68(a2),d1                      ; -> cfg_sectors
	divu.w	d1,d0
	move.w	d0,$28(sp)                      ; start track,
	move.w	d0,-$2(a4)                      ; -> floppy_track
	moveq	#0,d2
	move.w	$c(a5),d2                       ; -> bpb+bpb_datrec
	divu.w	$68(a2),d2                      ; -> cfg_sectors
	moveq	#0,d0
	move.w	d2,d0
	moveq	#1,d1
	add.w	$66(a2),d1                      ; -> cfg_sides
	divu.w	d1,d0
	swap	d0
	move.w	d0,$26(sp)
	move.w	d0,-$4(a4)                      ; side, -> floppy_side
	moveq	#0,d2
	move.w	$c(a5),d2                       ; -> bpb+bpb_datrec
	divu.w	$68(a2),d2                      ; -> cfg_sectors
	swap	d2
	move.w	d2,$24(sp)                      ; and sector
	move.w	d2,$32(sp)
	move.w	-$8(a4),d0                      ; BPB of the destination partition, -> partition_drive
	jsr	Getbpb(pc)
	movea.l	a0,a1
	movea.l	a5,a0
	moveq	#18,d0
	jsr	memcpy(pc)
	move.w	$e(a5),d0                       ; sectors of the destination partition, -> bpb+bpb_numcl
	mulu.w	$2(a5),d0                       ; -> bpb+bpb_clsiz
	add.w	$c(a5),d0                       ; -> bpb+bpb_datrec
	move.w	d0,$38(sp)
	movea.l	buffer_start,a0                 ; sector size must match the partition of the backup
	move.w	(a5),d1
	cmp.w	$c2(a0),d1
	beq.s	.backup_bpb
	lea	alert_source_and_destination,a0
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.backup_bpb
	moveq	#18,d0                          ; from now on the BPB of the backed up partition
	movea.l	buffer_start,a1
	lea	$c2(a1),a1
	movea.l	a5,a0
	jsr	memcpy(pc)
.needed
	movea.l	buffer_start,a0                 ; $da used clusters, $dc last used cluster + 1
	move.w	$da(a0),d0
	move.w	d0,$6(sp)
	move.w	d0,$34(sp)
	move.w	$dc(a0),$4(sp)
	move.w	$e(a5),d5                       ; sectors needed: all, up to the last used cluster, or (optimized) the used ones, -> bpb+bpb_numcl
	mulu.w	$2(a5),d5                       ; -> bpb+bpb_clsiz
	add.w	$c(a5),d5                       ; -> bpb+bpb_datrec
	move.w	$6(sp),d1
	beq.s	.not_packed
	move.b	$53(a2),d2                      ; -> cfg_optimize_partition
	bne.s	.check_size
.not_packed
	move.w	$4(sp),d0
	beq.s	.all_sectors
	move.b	$64(a2),d1                      ; -> cfg_used_only
	bne.s	.store_needed
.all_sectors
	move.w	d5,d0
	bra.s	.set_needed

.store_needed
	move.w	$4(sp),d0
.set_needed
	move.w	d0,$34(sp)
.check_size
	clr.w	d4                              ; d4: extra FAT sectors when the destination is larger
	move.w	$38(sp),d0                      ; destination too small for the needed sectors:
	cmp.w	$34(sp),d0
	bcc.s	.larger
	move.w	$6(sp),d1
	beq.w	.too_small
	cmp.w	d1,d0
	bcs.w	.too_small
	lea	$182(a3),a0                     ; offer optimized writing if that fits, -> alert_without_optimized_writing_the
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0
	beq.s	.optimize
	bra.s	.too_small

.larger
	move.w	$38(sp),d0                      ; destination larger: the FAT must grow
	cmp.w	$34(sp),d0
	bls.s	.mode
	moveq	#0,d4
	move.w	d0,d4
	move.w	(a5),d1
	lsr.w	#1,d1
	mulu.w	$2(a5),d1                       ; -> bpb+bpb_clsiz
	divu.w	d1,d4
	addq.w	#1,d4
	cmp.w	$8(a5),d4                       ; -> bpb+bpb_fsiz
	bhi.s	.fat_growth
	clr.w	d4
	bra.s	.mode

.fat_growth
	move.w	d4,d0                           ; each extra FAT sector moves the data by two sectors (two FATs)
	sub.w	$8(a5),d0                       ; -> bpb+bpb_fsiz
	add.w	d0,d0
	move.w	d0,$1e(sp)
	move.w	$34(sp),d1
	add.w	d0,d1
	move.w	$38(sp),d2
	cmp.w	d1,d2
	bcc.s	.mode
	move.w	$6(sp),d1
	beq.s	.too_small
	add.w	d0,d1
	cmp.w	d1,d2
	bcs.s	.too_small
	lea	$182(a3),a0                     ; -> alert_without_optimized_writing_the
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0
	bne.s	.too_small
.optimize
	move.b	#$1,$53(a2)                     ; switch to optimized writing and check again, -> cfg_optimize_partition
	bra.w	.needed

.too_small
	lea	$203(a3),a0                     ; "Destination Partition is too small! Write back as much as possible?", -> alert_destination_partition_is_too
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#2,d0
	beq.w	.return
	move.w	$38(sp),d5
.mode
	move.b	$53(a2),d0                      ; used-cluster mode when optimizing or when the backup holds used clusters only, -> cfg_optimize_partition
	or.b	$64(a2),d0                      ; -> cfg_used_only
	move.b	d0,$8(sp)
	move.b	$53(a2),d1                      ; -> cfg_optimize_partition
	beq.s	.buffers
	move.b	$64(a2),d2                      ; -> cfg_used_only
	bne.s	.buffers
	lea	alert_with_optimized_writing_fcopy,a0 ; "With Optimized Writing FCopy will only write back the used Sectors"
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#2,d0
	beq.w	.return
.buffers
	jsr	alloc_track_buffers(pc)
	tst.w	d4
	beq.s	.compack_buffer
	moveq	#0,d1                           ; one empty sector in front of the buffer for the larger FAT
	move.w	(a5),d1
	clr.w	d0
	movea.l	copy_buffer,a0
	move.l	a0,$40(sp)
	jsr	memset(pc)
	moveq	#0,d0
	move.w	(a5),d0
	add.l	d0,copy_buffer
.compack_buffer
	move.b	$44(sp),d0                      ; Compack: buffer for the packed blocks
	beq.s	.system_bounds
	movea.l	buffer_end,a0
	suba.l	copy_buffer,a0
	move.l	$16(sp),d1
	add.l	d1,d1
	dc.w	$d2bc                           ; add.l #$4000,d1
	dc.l	$4000
	cmpa.l	d1,a0
	bcs.s	.no_memory
	movea.l	copy_buffer,a6
	move.l	$16(sp),d2
	add.l	d2,copy_buffer
	clr.b	$3f(sp)
	clr.l	$a(sp)
.system_bounds
	move.w	$c(a5),d0                       ; first data sector of the root directory and of the second FAT, -> bpb+bpb_datrec
	sub.w	$6(a5),d0                       ; -> bpb+bpb_rdlen
	move.w	d0,$22(sp)
	moveq	#1,d1
	add.w	$8(a5),d1                       ; -> bpb+bpb_fsiz
	move.w	d1,$20(sp)
	move.b	$8(sp),d2                       ; used-cluster mode needs room for the FAT
	beq.s	.start
	move.w	(a5),d1
	jsr	mul_words(pc)
	movea.l	copy_buffer,a0
	adda.l	d0,a0
	movea.l	buffer_end,a1
	suba.l	a0,a1
	cmpa.l	#$4000,a1
	bge.s	.start
.no_memory
	lea	$134(a3),a0                     ; -> alert_not_enough_memory_free_for_2
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.start
	jsr	draw_status_labels(pc)          ; track map, drive parameters, head to the start track
	jsr	set_drive_params(pc)
	move.w	-$2(a4),d1                      ; -> floppy_track
	clr.w	d0
	jsr	restore_drive(pc)
	clr.w	d7                              ; nothing read or written yet
	move.w	d7,(sp)
	move.w	d7,(a4)
	move.w	d7,$36(sp)
	move.l	copy_buffer,copy_read_ptr
	clr.l	fat_buffer
	move.w	(a5),d0                         ; sectors per Rwabs sector unit (bpb_recsiz / 512)
	moveq	#9,d1
	lsr.w	d1,d0
	move.w	d0,$2e(sp)
	clr.w	d2
	move.w	d2,$1a(sp)
	move.b	d2,$3e(sp)
	jsr	disable_status_box(pc)
	jsr	disable_status_button(pc)
	bra.w	.loop_test

.read_or_write
	movea.l	buffer_end,a0                   ; main loop: read the floppies while the buffer has room
	suba.l	copy_read_ptr,a0
	moveq	#0,d0
	move.w	(a5),d0
	cmpa.l	d0,a0
	bge.w	.read_phase
.write_phase
	lea	$4a(a3),a0                      ; write phase: the buffer goes to the partition, -> str_writing_drive_x
	jsr	show_status_line(pc)
	move.l	copy_buffer,copy_write_ptr
	bra.w	.write_test

.write_next
	move.l	fat_buffer,d0                   ; used-cluster mode: keep the FAT once the system sectors are in the buffer
	bne.s	.count
	move.b	$8(sp),d1
	beq.s	.count
	move.w	(a4),d2
	cmp.w	$22(sp),d2
	bcs.s	.count
	move.w	$8(a5),d0                       ; -> bpb+bpb_fsiz
	move.w	(a5),d1
	jsr	mul_words(pc)
	move.l	d0,-(sp)
	move.w	(a5),d1
	moveq	#1,d0
	add.w	$8(a5),d0                       ; -> bpb+bpb_fsiz
	jsr	mul_words(pc)
	movea.l	copy_buffer,a1
	adda.l	d0,a1
	movea.l	copy_buffer,a0
	move.l	(sp)+,d0
	jsr	memcpy(pc)
	move.l	copy_buffer,fat_buffer
	move.w	(a5),d1
	move.w	$8(a5),d0                       ; -> bpb+bpb_fsiz
	jsr	mul_words(pc)
	add.l	d0,copy_buffer
.count
	move.b	$8(sp),d0                       ; d3 = sectors to write in one go:
	beq.w	.everything
	move.l	fat_buffer,d1                   ; system sectors still: all of them
	bne.s	.used_run
	move.w	$22(sp),d3
	sub.w	(a4),d3
	add.w	d3,$36(sp)
	bra.s	.check_count

.used_run
	move.b	$53(a2),d0                      ; not optimized: the run of used clusters, -> cfg_optimize_partition
	bne.s	.packed
	clr.w	d3
	bra.s	.used_test

.used_scan
	move.w	(a4),d0
	add.w	d3,d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.check_count
	addq.w	#1,d3
	addq.w	#1,$36(sp)
.used_test
	cmp.w	$36(sp),d7
	bhi.s	.used_scan
	bra.s	.check_count

.packed
	move.b	$64(a2),d0                      ; optimized from a full backup: used clusters are written packed, -> cfg_used_only
	bne.s	.everything
	move.w	(sp),d1
	bne.s	.packed_start
	move.w	(a4),(sp)
.packed_start
	clr.w	d3
	bra.s	.packed_test

.packed_scan
	move.w	(sp),d0
	add.w	d3,d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.run_end
	addq.w	#1,d3
.packed_test
	move.w	(sp),d0
	add.w	d3,d0
	cmp.w	d0,d7
	bhi.s	.packed_scan
.run_end
	tst.w	d3
	beq.s	.one_cluster
	move.w	d3,d0
	bra.s	.skip_run

.one_cluster
	moveq	#1,d0
.skip_run
	add.w	d0,(sp)
	bra.s	.check_count

.everything
	move.w	d7,d3                           ; all sectors mode: everything in the buffer
	sub.w	(a4),d3
.check_count
	tst.w	d3
	beq.w	.not_written
.write
	move.w	d3,$2c(sp)                      ; write loop
	move.w	(a4),d0                         ; boot sector: the sector count and FAT size of the destination partition
	bne.s	.fat_extension
	movea.l	copy_write_ptr,a0
	jsr	is_boot_executable(pc)
	movea.l	copy_write_ptr,a0
	move.b	$39(sp),$13(a0)
	move.w	$38(sp),d1
	lsr.w	#8,d1
	movea.l	copy_write_ptr,a0
	move.b	d1,$14(a0)
	tst.w	d4
	beq.s	.boot_done
	movea.l	copy_write_ptr,a0
	move.b	d4,$16(a0)
	move.w	d4,d2
	lsr.w	#8,d2
	movea.l	copy_write_ptr,a0
	move.b	d2,$17(a0)
.boot_done
	tst.b	d0                              ; keep it executable
	beq.s	.boot_sector_only
	movea.l	copy_write_ptr,a0
	jsr	make_boot_executable(pc)
.boot_sector_only
	move.w	#$1,$2c(sp)
	clr.w	$2a(sp)
	bra.w	.rwabs

.fat_extension
	tst.w	d4                              ; larger FAT: write the first FAT, then empty sectors for its extension
	beq.w	.no_shift
	cmpi.w	#$1,(a4)
	bcs.s	.second_fat
	move.w	(a4),d0
	cmp.w	$20(sp),d0
	bcc.s	.second_fat
	add.w	d3,d0
	cmp.w	$20(sp),d0
	bcs.w	.no_shift
	move.w	$20(sp),d1
	sub.w	(a4),d1
	move.w	d1,$2c(sp)
	move.w	$20(sp),d6
	bra.s	.extension_test

.write_extension
	move.w	-$8(a4),-(sp)                   ; -> partition_drive
	move.w	d6,d2
	moveq	#1,d1
	movea.l	$42(sp),a0
	moveq	#1,d0
	jsr	Rwabs(pc)
	addq.w	#2,sp
	tst.l	d0
	bge.s	.next_extension
	movea.l	a3,a0
	moveq	#1,d0
	jsr	alert(pc)
	move.w	d0,$2(sp)
	subq.w	#1,d0
	beq.s	.write_extension
	cmpi.w	#$3,$2(sp)
	beq.w	.done
.next_extension
	addq.w	#1,d6
.extension_test
	moveq	#1,d0
	add.w	d4,d0
	cmp.w	d0,d6
	bcs.s	.write_extension
	bra.w	.no_shift

.second_fat
	move.w	(a4),d0                         ; second FAT and its extension
	cmp.w	$20(sp),d0
	bcs.s	.data_shifted
	cmp.w	$22(sp),d0
	bcc.s	.data_shifted
	add.w	d3,d0
	cmp.w	$22(sp),d0
	bcs.s	.shift_data
	move.w	$22(sp),d1
	sub.w	(a4),d1
	move.w	d1,$2c(sp)
	move.w	d4,d6
	add.w	$8(a5),d6                       ; -> bpb+bpb_fsiz
	addq.w	#1,d6
	bra.s	.fat2_test

.write_extension2
	move.w	-$8(a4),-(sp)                   ; -> partition_drive
	move.w	d6,d2
	moveq	#1,d1
	movea.l	$42(sp),a0
	moveq	#1,d0
	jsr	Rwabs(pc)
	addq.w	#2,sp
	tst.l	d0
	bge.s	.next_fat2_sector
	movea.l	a3,a0
	moveq	#1,d0
	jsr	alert(pc)
	move.w	d0,$2(sp)
	subq.w	#1,d0
	beq.s	.write_extension2
	cmpi.w	#$3,$2(sp)
	beq.w	.done
.next_fat2_sector
	addq.w	#1,d6
.fat2_test
	move.w	d4,d0
	add.w	d0,d0
	addq.w	#1,d0
	cmp.w	d0,d6
	bcs.s	.write_extension2
.shift_data
	move.w	$1e(sp),d0                      ; data sectors move by the FAT growth
	lsr.w	#1,d0
	add.w	(a4),d0
	move.w	d0,$2a(sp)
	bra.s	.rwabs

.data_shifted
	move.w	(a4),d0
	add.w	$1e(sp),d0
	move.w	d0,$2a(sp)
	bra.s	.rwabs

.no_shift
	move.w	(a4),$2a(sp)
.rwabs
	move.w	-$8(a4),-(sp)                   ; write the sectors to the partition, -> partition_drive
	move.w	$2c(sp),d2
	move.w	$2e(sp),d1
	movea.l	copy_write_ptr,a0
	moveq	#1,d0
	jsr	rwabs_checked(pc)
	addq.w	#2,sp
	move.w	d0,$1c(sp)
	bge.s	.written
	cmp.w	#$fff3,d0                       ; write protected partition
	bne.s	.write_error
	lea	alert_destination_partition_is,a0
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.done

.write_error
	movea.l	a3,a0                           ; "Write Error on Partition X: [RETRY|CONT|ABORT]"
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0
	beq.w	.write
	subq.w	#1,d0
	beq.s	.continue
	subq.w	#1,d0
	beq.w	.done
	bra.s	.written

.continue
	move.w	#$1,$2c(sp)
.written
	move.w	$2c(sp),d1                      ; advance
	move.w	(a5),d0
	jsr	mul_words(pc)
	add.l	d0,copy_write_ptr
	move.w	$2c(sp),d0
	add.w	d0,(a4)
	sub.w	d0,d3
	beq.s	.keyboard
	bra.w	.write

.not_written
	move.b	$53(a2),d0                      ; optimized: skip an unused cluster in the buffer, -> cfg_optimize_partition
	beq.s	.next_sector
	move.b	$64(a2),d1                      ; -> cfg_used_only
	bne.s	.next_sector
	moveq	#0,d2
	move.w	(a5),d2
	add.l	d2,copy_write_ptr
	bra.s	.keyboard

.next_sector
	addq.w	#1,(a4)
.keyboard
	clr.w	d0                              ; Esc or Space?
	jsr	check_keyboard(pc)
	subq.w	#1,d0
	beq.w	.done
.write_test
	movea.l	copy_write_ptr,a0               ; until the buffer is written
	cmpa.l	copy_read_ptr,a0
	bcs.w	.write_next
	move.w	$1a(sp),d0                      ; everything read: finish
	bne.w	.finish
	move.w	#$ffff,d1                       ; read phase: reset the track map, buffer empty
	move.w	d1,shown_track
	move.w	d1,shown_side
	move.w	d1,shown_result
	lea	str_reading_2,a0
	jsr	draw_progress_text(pc)
	jsr	draw_status_labels(pc)
	clr.b	d0
	movea.l	copy_buffer,a0
	move.l	a0,copy_read_ptr
	jsr	draw_memory_bar(pc)
	jsr	lock_floppy(pc)
.read_phase
	move.b	$44(sp),d0                      ; Compack: read one packed block at a time
	beq.w	.read_sectors
	movea.l	buffer_end,a0
	suba.l	copy_read_ptr,a0
	cmpa.l	$16(sp),a0
	bcs.w	.write_phase
	move.b	$3f(sp),d1                      ; first the block header sector
	bne.s	.block_body
	move.w	#$1,$2e(sp)
	bra.s	.read_block

.block_body
	cmpi.b	#$1,$3f(sp)                     ; then the rest of the block: header words are unpacked and packed size / 2
	bne.s	.check_block_complete
	moveq	#0,d0
	move.w	(a6),d0
	add.l	d0,d0
	move.l	d0,$12(sp)
	bne.s	.unpacked_max
	move.l	#$20000,$12(sp)
.unpacked_max
	moveq	#0,d0
	move.w	$2(a6),d0
	add.l	d0,d0
	move.l	d0,$e(sp)
	bne.s	.rest_of_block
	move.l	#$20000,$e(sp)
.rest_of_block
	move.l	$e(sp),d0
	moveq	#-4,d1
	add.l	$a(sp),d1
	sub.l	d1,d0
	move.l	d0,d2
	moveq	#9,d1
	lsr.l	d1,d2
	move.w	d2,$2e(sp)
	move.l	d0,d2
	dc.w	$c4bc                           ; and.l #$fffffe00,d2
	dc.l	$fffffe00
	cmp.l	d2,d0
	beq.s	.read_block
	addq.w	#1,$2e(sp)
.read_block
	move.l	$a(sp),d0
	lea	$0(a6,d0.l),a0
	move.l	a0,$3a(sp)
	move.w	#$200,d1
	move.w	$2e(sp),d0
	jsr	mul_words(pc)
	add.l	d0,$a(sp)
	addq.b	#1,$3f(sp)
	move.w	$2e(sp),d0
	bne.w	.read_sectors
.check_block_complete
	cmpi.b	#$2,$3f(sp)
	bne.w	.read_sectors
	move.l	$12(sp),d1                      ; block complete: unpack it into the buffer
	move.l	$e(sp),d0
	movea.l	copy_read_ptr,a1
	lea	$4(a6),a0
	jsr	decompress(pc)
	moveq	#4,d0                           ; keep the bytes after the block for the next one
	add.l	$e(sp),d0
	sub.l	d0,$a(sp)
	move.l	$e(sp),d1
	lea	$4(a6,d1.l),a1
	movea.l	a6,a0
	move.l	$a(sp),d0
	jsr	memcpy(pc)
	moveq	#1,d0
	move.l	$12(sp),d1
	add.l	d1,copy_read_ptr
	movea.l	copy_read_ptr,a0
	jsr	draw_memory_bar(pc)
	move.l	$12(sp),d0
	moveq	#0,d1
	move.w	(a5),d1
	jsr	uldiv(pc)
	add.w	d0,d7                           ; partition sectors now in the buffer, at most the needed ones
	cmp.w	d7,d5
	bcc.s	.more_data
	move.w	(a5),d1
	move.w	d7,d0
	sub.w	d5,d0
	jsr	mul_words(pc)
	sub.l	d0,copy_read_ptr
	move.w	d5,d7
.more_data
	moveq	#4,d0
	cmp.l	$a(sp),d0
	bhi.s	.no_more
	moveq	#1,d1
	bra.s	.block_state

.no_more
	clr.b	d1
.block_state
	move.b	d1,$3f(sp)
	bra.w	.check_needed

.read_sectors
	clr.w	d6                              ; read d6 sectors from the floppy
	bra.w	.read_test

.read_next
	moveq	#1,d0
	move.b	d0,-(sp)
	move.b	$46(sp),d1
	beq.s	.to_read_ptr
	movea.l	$3c(sp),a0
	bra.s	.read

.to_read_ptr
	movea.l	copy_read_ptr,a0
.read
	moveq	#1,d2
	add.w	$34(sp),d2
	move.w	-$4(a4),d1                      ; -> floppy_side
	clr.w	d0
	jsr	read_sectors(pc)                ; read one sector
	addq.w	#2,sp
	move.w	d0,$1c(sp)
	tst.w	d0
	beq.s	.sector_read
	move.w	d0,-(sp)
	move.w	-$2(a4),-(sp)                   ; -> floppy_track
	move.w	-$4(a4),d2                      ; -> floppy_side
	clr.w	d1
	moveq	#4,d0
	jsr	show_track_result(pc)           ; error: show it (4 = reading); ABORT or RETRY
	addq.w	#4,sp
	subq.w	#1,d0
	beq.w	.done
	subq.w	#1,d0
	beq.s	.read_next
.sector_read
	move.b	$44(sp),d0
	beq.s	.unpacked_advance
	addi.l	#$200,$3a(sp)
	bra.s	.advance

.unpacked_advance
	addi.l	#$200,copy_read_ptr
.advance
	addq.w	#1,$32(sp)                      ; next sector; at the end of the track show it as done
	move.w	$32(sp),d0
	cmp.w	src_sectors,d0
	bcs.w	.read_advance
	move.b	$44(sp),d0
	bne.s	.track_done
	movea.l	copy_read_ptr,a0
	moveq	#1,d0
	jsr	draw_memory_bar(pc)
.track_done
	clr.w	-(sp)
	move.w	-$2(a4),-(sp)                   ; -> floppy_track
	move.w	-$4(a4),d2                      ; -> floppy_side
	clr.w	d1
	moveq	#4,d0
	jsr	show_track_result(pc)
	addq.w	#4,sp
	subq.w	#1,d0
	beq.w	.done
	clr.w	$32(sp)
	addq.w	#1,-$4(a4)                      ; next side, next track, -> floppy_side
	move.w	-$4(a4),d0                      ; -> floppy_side
	cmp.w	src_sides,d0
	bls.s	.read_advance
	clr.w	-$4(a4)                         ; -> floppy_side
	addq.w	#1,-$2(a4)                      ; -> floppy_track
	move.w	-$2(a4),d0                      ; -> floppy_track
	cmp.w	$6c(a2),d0                      ; -> cfg_end_track
	bls.s	.seek
	addq.w	#1,-$6(a4)                      ; end of the floppy: ask for the next backup disk, -> disk_number
.ask_next_disk
	clr.w	d1
	clr.w	d0
	jsr	restore_drive(pc)
	lea	str_copy_abort,a1
	lea	$67(a3),a0                      ; -> alert_x_source_disk
	jsr	alert_disk_number(pc)
	subq.w	#2,d0
	beq.w	.done
	moveq	#1,d0
	move.b	d0,-(sp)
	movea.l	buffer_start,a0
	moveq	#1,d2
	clr.w	d1
	clr.w	d0
	jsr	read_sectors(pc)                ; until its disk number is the expected one
	addq.w	#2,sp
	movea.l	buffer_start,a0
	clr.w	d0
	move.b	$c0(a0),d0
	cmp.w	-$6(a4),d0                      ; -> disk_number
	bne.s	.ask_next_disk
	jsr	draw_progress_frame(pc)
	move.w	$28(sp),-$2(a4)                 ; the data continues at the first data sector of the new floppy, -> floppy_track
	move.w	$26(sp),-$4(a4)                 ; -> floppy_side
	move.w	$24(sp),$32(sp)
.seek
	move.w	-$2(a4),d1                      ; -> floppy_track
	clr.w	d0
	jsr	seek_track(pc)
.read_advance
	addq.w	#1,d6
.read_test
	cmp.w	$2e(sp),d6
	bcs.w	.read_next
	move.b	$44(sp),d0
	bne.w	.loop_test
	addq.w	#1,d7
.check_needed
	move.b	$8(sp),d0                       ; all system sectors read in used-cluster mode: find the last needed sector
	beq.w	.loop_test
	cmp.w	$22(sp),d7
	bcs.w	.loop_test
	move.b	$3e(sp),d1
	bne.w	.loop_test
	move.b	#$1,$3e(sp)
	lea	$5b(a3),a0                      ; -> str_calculating
	jsr	draw_progress_text(pc)
	move.w	(a5),d1                         ; from the FAT now in the buffer
	moveq	#1,d0
	add.w	$8(a5),d0                       ; -> bpb+bpb_fsiz
	jsr	mul_words(pc)
	movea.l	copy_buffer,a0
	adda.l	d0,a0
	move.l	a0,fat_buffer
	move.b	$53(a2),d0                      ; -> cfg_optimize_partition
	beq.s	.count_used
	move.b	$64(a2),d1                      ; -> cfg_used_only
	bne.s	.count_used
	move.w	$4(sp),d2
	beq.s	.find_last
	move.w	d2,$30(sp)
	bra.s	.limit_needed

.find_last
	clr.w	d6
	move.w	d6,$30(sp)
	bra.s	.last_test

.last_scan
	move.w	d6,d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.last_advance
	move.w	d6,$30(sp)
.last_advance
	addq.w	#1,d6
.last_test
	cmp.w	d6,d5
	bhi.s	.last_scan
	addq.w	#1,$30(sp)
	bra.s	.limit_needed

.count_used
	move.w	$6(sp),d0
	bne.s	.used_from_header
	clr.w	d6
	move.w	d6,$30(sp)
	bra.s	.count_test

.count_scan
	move.w	d6,d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.count_advance
	addq.w	#1,$30(sp)
.count_advance
	addq.w	#1,d6
.count_test
	cmp.w	d6,d5
	bhi.s	.count_scan
	bra.s	.limit_needed

.used_from_header
	move.w	$6(sp),$30(sp)
.limit_needed
	cmp.w	$30(sp),d5
	bls.s	.fat_found
	move.w	$30(sp),d5
.fat_found
	clr.l	fat_buffer
	lea	str_reading_2,a0
	jsr	draw_progress_text(pc)
.loop_test
	cmp.w	d7,d5                           ; until all needed sectors are read
	bhi.w	.read_or_write
	move.w	#$1,$1a(sp)                     ; last write phase
	bra.w	.write_phase

.finish
	move.b	$53(a2),d0                      ; optimized writing: rebuild the FAT for the packed clusters, -> cfg_optimize_partition
	beq.w	.done
	lea	str_updating_fat,a0
	jsr	draw_progress_text(pc)
	jsr	compact_fat(pc)
	tst.b	d0
	beq.w	.done
	tst.w	d4                              ; larger FAT: the data starts later
	beq.s	.same_fat
	move.w	$1e(sp),d0
	add.w	d0,$c(a5)                       ; -> bpb+bpb_datrec
	bra.s	.write_fats

.same_fat
	move.w	$8(a5),d4                       ; -> bpb+bpb_fsiz
.write_fats
	move.w	-$8(a4),d0                      ; write both FATs, -> partition_drive
	jsr	Getbpb(pc)
	move.w	-$8(a4),-(sp)                   ; -> partition_drive
	moveq	#1,d2
	move.w	$8(a5),d1                       ; -> bpb+bpb_fsiz
	movea.l	fat_buffer,a0
	moveq	#1,d0
	jsr	rwabs_checked(pc)
	addq.w	#2,sp
	move.w	d0,$1c(sp)
	bge.s	.fat_2
.fat_error
	lea	alert_cannot_write_the_fats_retry,a0
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0
	beq.s	.write_fats
	bra.s	.done

.fat_2
	move.w	-$8(a4),-(sp)                   ; -> partition_drive
	moveq	#1,d2
	add.w	d4,d2
	move.w	$8(a5),d1                       ; -> bpb+bpb_fsiz
	movea.l	fat_buffer,a0
	moveq	#1,d0
	jsr	rwabs_checked(pc)
	addq.w	#2,sp
	move.w	d0,$1c(sp)
	blt.s	.fat_error
	lea	str_updating_dirs,a0            ; and fix the directories
	jsr	draw_progress_text(pc)
	jsr	relocate_root_directory(pc)
.done
	move.w	-$8(a4),d0                      ; media change on the partition, head to track 0, -> partition_drive
	jsr	select_partition(pc)
	clr.w	d1
	clr.w	d0
	jsr	restore_drive(pc)
	jsr	unlock_floppy(pc)
.return
	lea	$46(sp),sp
	movem.l	(sp)+,d3-d7/a2-a6
	rts


;----------------------------------------------------------------------
; Streamer backup: reads the used sectors of the source partition, compresses
; them (compress) if Compack Streamer Data is on and writes them to as many floppies
; as needed, formatting each one with a backup header (disk number, random id).
;----------------------------------------------------------------------
streamer_backup:
	movem.l	d3-d7/a2-a6,-(sp)
	lea	-$3c(sp),sp
	moveq	#1,d0                           ; the destination drive must support the configuration
	jsr	check_drive_support(pc)
	tst.b	d0
	beq.w	.return
	jsr	enable_status_box(pc)
	move.b	partition_letter,str_reading_drive_x+14 ; "Reading Drive X:"
	lea	str_reading_drive_x,a0
	jsr	show_status_line(pc)
	lea	copy_data_end,a4
	move.w	-$a(a4),d0                      ; BPB of the source partition, -> partition_drive
	jsr	Getbpb(pc)
	movea.l	a0,a1
	lea	bpb,a0
	moveq	#18,d0
	jsr	memcpy(pc)
	lea	config,a5
	move.b	#$1,$63(a5)                     ; backups read the configuration and copy used clusters only (option restored later), -> cfg_read_config
	move.b	$64(a5),(sp)                    ; -> cfg_used_only
	move.b	#$1,$64(a5)                     ; -> cfg_used_only
	jsr	set_drive_params(pc)
	jsr	alloc_track_buffers(pc)
	move.l	buffer_end,copy_buffer_end      ; buffer end, less one track image when formatting
	move.b	$5a(a5),d0                      ; -> cfg_smart_format
	bne.s	.less_track
	move.b	$5f(a5),d1                      ; -> cfg_format_dest
	bne.s	.check_memory
.less_track
	move.l	track_image_size,d0
	sub.l	d0,copy_buffer_end
.check_memory
	movea.l	copy_buffer_end,a0              ; at least 16KB of buffer
	suba.l	copy_buffer,a0
	cmpa.l	#$4000,a0
	bge.s	.build
.no_memory
	jsr	unlock_floppy(pc)
	lea	alert_not_enough_memory_free_for_2,a0
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.build
	lea	bpb,a0                          ; keep the partition BPB
	lea	$2a(sp),a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.w	(a0)+,(a1)+
	movea.l	copy_buffer,a6                  ; build the system sectors of a backup floppy at copy_buffer:
	clr.w	-(sp)                           ; BPB of the floppy format from the disk configuration,
	move.w	$68(a5),d2                      ; -> cfg_sectors
	move.w	$6c(a5),d1                      ; -> cfg_end_track
	move.w	$66(a5),d0                      ; -> cfg_sides
	jsr	bpb_from_config(pc)
	addq.w	#2,sp
	move.w	#$1,bpb+bpb_rdlen               ; one root sector and 8 sectors per cluster
	move.w	#$8,bpb+bpb_clsiz
	jsr	bpb_fat_size(pc)
	jsr	bpb_data_start(pc)
	move.w	$68(a5),d2                      ; -> cfg_sectors
	move.w	$6c(a5),d1                      ; -> cfg_end_track
	move.w	$66(a5),d0                      ; -> cfg_sides
	movea.l	a6,a0
	jsr	build_boot_sector(pc)           ; boot sector
	lea	$200(a6),a6                     ; FAT: all clusters $42, so the backup data looks allocated
	move.w	#$200,d1
	move.w	bpb+bpb_fsiz,d0
	jsr	mul_words(pc)
	move.l	d0,d4
	move.l	d4,d1
	movea.l	a6,a0
	moveq	#66,d0
	jsr	memset(pc)
	movea.l	copy_buffer,a0
	move.b	$15(a0),(a6)                    ; media byte, $ff, $ff
	move.b	#$ff,d0
	move.b	d0,$2(a6)
	move.b	d0,$1(a6)
	movea.l	a6,a1                           ; second FAT copy
	lea	$0(a6,d4.l),a0
	move.l	d4,d0
	jsr	memcpy(pc)
	move.l	d4,d0
	add.l	d4,d0
	adda.l	d0,a6
	move.l	#$200,d1                        ; root directory: volume label "PART_X  #nn"
	movea.l	a6,a0
	clr.w	d0
	jsr	memset(pc)
	move.b	partition_letter,str_part_x_12+5
	lea	str_part_x_12,a1
	movea.l	a6,a0
	jsr	strcpy(pc)
	lea	$16(a6),a2
	jsr	Gettime(pc)                     ; with the time as label date
	move.b	d0,(a2)+
	move.l	d0,d1
	lsr.l	#8,d1
	move.b	d1,(a2)+
	move.l	d0,d2
	moveq	#16,d4
	lsr.l	d4,d2
	move.b	d2,(a2)+
	move.l	d0,d1
	moveq	#24,d2
	lsr.l	d2,d1
	move.b	d1,(a2)
	lea	$2a(sp),a0                      ; partition BPB back
	lea	bpb,a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.w	(a0)+,(a1)+
	moveq	#18,d0                          ; backup header in the boot sector: $c2 partition BPB
	lea	bpb,a1
	movea.l	copy_buffer,a0
	lea	$c2(a0),a0
	jsr	memcpy(pc)
	movea.l	copy_buffer,a0                  ; $d4 Compack flag
	move.b	$52(a5),$d4(a0)                 ; -> cfg_compack
	lea	$200(a6),a2                     ; a2: start of the backup data in the buffer (after boot, FATs, root)
	move.b	$52(a5),d0                      ; -> cfg_compack
	beq.s	.no_compack
	move.l	copy_buffer_end,d0              ; Compack: compress blocks of an eighth of the buffer, 10 sectors to 128KB
	sub.l	a2,d0
	moveq	#8,d1
	jsr	ldiv(pc)
	move.l	d0,d3
	dc.w	$c6bc                           ; and.l #$fffffffe,d3
	dc.l	$fffffffe
	cmp.l	#$20000,d3
	bls.s	.minimum_block
	move.l	#$20000,d3
.minimum_block
	moveq	#10,d1
	move.w	bpb,d0
	jsr	mul_words(pc)
	cmp.l	d0,d3
	bcs.w	.no_memory
	movea.l	copy_buffer,a0                  ; $d6 block size
	move.l	d3,$d6(a0)
	movea.l	copy_buffer_end,a0              ; partition sectors are read into the top block, packed below
	suba.l	d3,a0
	move.l	a0,$26(sp)
	move.l	a0,copy_read_ptr
	movea.l	a2,a3
	bra.s	.read_system

.no_compack
	move.l	a2,copy_read_ptr                ; no Compack: read straight into the backup data
.read_system
	move.w	-$a(a4),d0                      ; read the boot sector and FAT of the partition, -> partition_drive
	jsr	read_system_sectors(pc)
	tst.w	d0
	bne.w	.return
	move.b	$5f(a5),d0                      ; track image when formatting the floppies, -> cfg_format_dest
	beq.s	.letters
	jsr	build_track_image(pc)
.letters
	moveq	#65,d0                          ; destination letter into "X: Destination Disk"
	add.b	dst_unit+1,d0
	move.b	d0,alert_x_destination_disk+6
	move.w	bpb+bpb_numcl,d4                ; d4 = sectors of the partition
	mulu.w	bpb+bpb_clsiz,d4
	add.w	bpb+bpb_datrec,d4
	move.w	#$200,d1                        ; d0 = backup data bytes per floppy
	move.w	disk_sectors,d0
	jsr	mul_words(pc)
	movea.l	a2,a0
	suba.l	copy_buffer,a0
	sub.l	a0,d0
	move.l	d0,$2(sp)
	lea	str_calculating,a0              ; count the used clusters and find the last one
	jsr	draw_progress_text(pc)
	clr.w	d5
	move.w	d5,$1c(sp)
	move.w	d5,d7
	bra.s	.count_test

.count_used
	move.w	$1c(sp),d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.count_advance
	addq.w	#1,d7
	move.w	$1c(sp),d5
.count_advance
	addq.w	#1,$1c(sp)
.count_test
	cmp.w	$1c(sp),d4
	bhi.s	.count_used
	lea	str_reading_drive_x,a0
	jsr	draw_progress_text(pc)
	move.b	(sp),$64(a5)                    ; Get Sectors setting back, -> cfg_used_only
	movea.l	copy_buffer,a0                  ; $da used clusters
	move.w	d7,$da(a0)
	addq.w	#1,d5
	movea.l	copy_buffer,a0                  ; $dc last used cluster + 1
	move.w	d5,$dc(a0)
	move.b	$64(a5),d0                      ; all sectors: read up to the end of the partition, -> cfg_used_only
	bne.s	.used_only
	move.w	d4,d7
	bra.s	.floppies_needed

.used_only
	move.w	d5,d4
.floppies_needed
	move.w	bpb,d1                          ; number of floppies needed into "of max. XX Disks"
	move.w	d7,d0
	jsr	mul_words(pc)
	move.l	$2(sp),d1
	jsr	uldiv(pc)
	move.l	d0,d5
	addq.w	#1,d5
	moveq	#0,d0
	move.w	d5,d0
	divu.w	#$a,d0
	dc.w	$d03c,$0030                     ; add.b #$30,d0
	move.b	d0,str_of_max_xx_disks_copy_abort+16
	moveq	#0,d1
	move.w	d5,d1
	divu.w	#$a,d1
	swap	d1
	dc.w	$d23c,$0030                     ; add.b #$30,d1
	move.b	d1,str_of_max_xx_disks_copy_abort+17
	jsr	Random(pc)                      ; $e0 random backup id: the same disk cannot be reused within one backup
	movea.l	copy_buffer,a0
	move.l	d0,$e0(a0)
	clr.w	d5
	moveq	#0,d1
	move.l	d1,$a(sp)
	move.l	d1,$e(sp)
	move.w	#$ffff,$1a(sp)                  ; no floppy inserted yet
	clr.w	$16(sp)
	bra.w	.read_test

.read_more
	movea.l	copy_buffer_end,a0              ; loop: read until the buffer is full
	suba.l	copy_read_ptr,a0
	moveq	#0,d0
	move.w	bpb,d0
	cmpa.l	d0,a0
	bge.w	.read_count
.pack
	move.b	$52(a5),d0                      ; Compack: pack the block just read, -> cfg_compack
	beq.w	.unpacked
	move.l	copy_read_ptr,d1
	sub.l	$26(sp),d1
	move.l	d1,$6(sp)                       ; unpacked and packed totals for the ratio
	add.l	d1,$a(sp)
	lea	$4(a3),a1
	movea.l	$26(sp),a0
	move.l	$6(sp),d0
	jsr	compress(pc)
	move.l	d0,$12(sp)
	add.l	d0,$e(sp)
	move.l	$6(sp),d0
	lsr.l	#1,d0                           ; block header: unpacked words, packed words
	move.w	d0,(a3)+
	move.l	$12(sp),d1
	lsr.l	#1,d1
	move.w	d1,(a3)+
	adda.l	$12(sp),a3
	movea.l	a3,a0
	adda.l	d3,a0
	clr.b	d0
	jsr	draw_memory_bar(pc)             ; memory bar
	move.w	$16(sp),d0                      ; more to read and the next block fits: read on
	bne.s	.whole_sectors
	movea.l	$26(sp),a0
	lea	$4(a3),a1
	suba.l	a1,a0
	cmp.l	a0,d3
	bhi.s	.whole_sectors
	move.l	$26(sp),copy_read_ptr
	bra.w	.read_count

.whole_sectors
	move.l	a3,d0                           ; write whole sectors only; the rest stays for the next round
	sub.l	a2,d0
	dc.w	$c0bc                           ; and.l #$fffffe00,d0
	dc.l	$fffffe00
	lea	$0(a2,d0.l),a0
	move.l	a0,(a4)
	move.l	a0,$22(sp)
	move.w	$16(sp),d1
	beq.s	.write_start
	addi.l	#$200,(a4)
	bra.s	.write_start

.unpacked
	move.l	copy_read_ptr,(a4)              ; no Compack: write everything read
.write_start
	move.w	#$ffff,d0                       ; reset the track map
	move.w	d0,shown_track
	move.w	d0,shown_side
	move.w	d0,shown_result
	move.b	$5f(a5),d1                      ; -> cfg_format_dest
	beq.s	.text_writing
	lea	str_format_writing,a0
	bra.s	.show_text

.text_writing
	lea	str_writing_2,a0
.show_text
	jsr	draw_progress_text(pc)
	jsr	draw_status_labels(pc)
	move.b	#$1,$1(sp)
.write_round
	move.w	$1a(sp),d0                      ; write loop
	cmp.w	-$8(a4),d0                      ; right floppy already in the drive: continue on it, -> disk_number
	bne.s	.check_read_more
	move.l	a2,copy_write_ptr
	jsr	disable_status_button(pc)
	bra.w	.round_test

.check_read_more
	move.w	$16(sp),d0                      ; not at the end of the floppy and more to read: go back to reading
	bne.s	.next_floppy
	movea.l	(a4),a0
	suba.l	a2,a0
	cmpa.l	$2(sp),a0
	bcc.s	.next_floppy
	move.b	$1(sp),d1
	bne.s	.next_floppy
	move.b	$52(a5),d2                      ; -> cfg_compack
	beq.s	.plain_room
	movea.l	$26(sp),a1
	movea.l	(a4),a0
	lea	$204(a0),a0
	suba.l	a0,a1
	cmp.l	a1,d3
	bhi.s	.no_room
	moveq	#1,d0
	bra.s	.decide

.no_room
	clr.w	d0
.decide
	bra.s	.check_fits

.plain_room
	movea.l	copy_buffer_end,a0
	suba.l	(a4),a0
	moveq	#0,d0
	move.w	bpb,d0
	cmpa.l	d0,a0
	blt.s	.full
	moveq	#1,d0
	bra.s	.check_fits

.full
	clr.w	d0
.check_fits
	tst.w	d0
	beq.s	.next_floppy
	move.w	#$ffff,$1a(sp)
	move.l	(a4),$1e(sp)
	bra.w	.keep_rest

.next_floppy
	jsr	enable_status_button(pc)        ; next floppy
	move.b	$5a(a5),d0                      ; Smart Formatting: try writing without formatting first, -> cfg_smart_format
	beq.s	.floppy_start
	clr.b	$5f(a5)                         ; -> cfg_format_dest
	clr.l	fdc_state+fs_order_ptr
	lea	str_writing_2,a0
	jsr	draw_progress_text(pc)
.floppy_start
	move.l	copy_buffer,copy_write_ptr      ; write from the start of the buffer, track 0, side 0, sector 0
	clr.w	d0
	move.w	d0,-$6(a4)                      ; -> floppy_side
	move.w	d0,-$4(a4)                      ; -> floppy_track
	move.w	d0,-$2(a4)                      ; -> floppy_sector
	clr.w	d1
	moveq	#1,d0
	jsr	restore_drive(pc)
	lea	str_of_max_xx_disks_copy_abort,a1 ; "X: Destination Disk #nn of max. XX Disks [COPY|ABORT]"
	lea	alert_x_destination_disk,a0
	jsr	alert_disk_number(pc)
	subq.w	#2,d0
	beq.w	.done
	cmpi.w	#$1,-$8(a4)                     ; from the second floppy on: refuse a floppy of this backup, -> disk_number
	beq.s	.mark_disk
	jsr	draw_progress_frame(pc)
	jsr	check_backup_disk(pc)
	tst.b	d0
	beq.w	.done
.mark_disk
	movea.l	copy_buffer,a0                  ; mark the boot sector as a backup disk (OEM byte + $42)
	addi.b	#$42,$9(a0)
	movea.l	copy_buffer,a0                  ; $c0 disk number, $c1 used clusters only
	move.b	-$7(a4),$c0(a0)                 ; -> disk_number+1
	movea.l	copy_buffer,a0
	move.b	$64(a5),$c1(a0)                 ; -> cfg_used_only
	move.w	-$8(a4),d0                      ; disk number into the volume label, -> disk_number
	ext.l	d0
	divs.w	#$a,d0
	dc.w	$d03c,$0030                     ; add.b #$30,d0
	move.b	d0,$9(a6)
	move.w	-$8(a4),d1                      ; -> disk_number
	ext.l	d1
	divs.w	#$a,d1
	swap	d1
	dc.w	$d23c,$0030                     ; add.b #$30,d1
	move.b	d1,$a(a6)
	move.w	-$8(a4),$1a(sp)                 ; -> disk_number
	bra.w	.round_test

.track_list
	clr.w	d7                              ; sector list of a track
	bra.s	.list_test

.next_list_sector
	moveq	#1,d0
	add.b	d7,d0
	lea	sector_list,a0
	move.b	d0,$0(a0,d7.w)                  ; -> sector_list indexed
	addq.w	#1,d7
.list_test
	cmp.w	dst_sectors,d7
	bcs.s	.next_list_sector
	lea	sector_list,a0
	clr.b	$0(a0,d7.w)                     ; -> sector_list indexed
.write_track
	move.w	-$2(a4),d0                      ; Format Destination at the start of a track: format it, -> floppy_sector
	bne.s	.write_sectors
	move.b	$5f(a5),d1                      ; -> cfg_format_dest
	beq.s	.write_sectors
	moveq	#1,d0
	move.w	-$4(a4),d1                      ; -> floppy_track
	jsr	seek_track(pc)
	move.w	-$4(a4),d1                      ; -> floppy_track
	move.w	-$6(a4),d0                      ; -> floppy_side
	jsr	format_track(pc)
	move.w	d0,$18(sp)
	jsr	order_sector_list(pc)
	move.w	$18(sp),d0
	beq.s	.write_sectors
	move.w	d0,-(sp)
	move.w	-$4(a4),-(sp)                   ; -> floppy_track
	move.w	-$6(a4),d2                      ; -> floppy_side
	moveq	#1,d1
	clr.w	d0
	jsr	show_track_result(pc)           ; show the result (0 = formatting): ABORT, RETRY or NEW DISK
	addq.w	#4,sp
	move.w	d0,d1
	subq.w	#1,d1
	beq.w	.done
	subq.w	#1,d1
	beq.s	.write_track
	subq.w	#3,d1
	beq.s	.new_disk
	bra.s	.write_sectors

.new_disk
	move.w	#$ffff,$1a(sp)
	bra.w	.write_round

.write_sectors
	move.w	-$4(a4),d1                      ; write the sectors of the track, -> floppy_track
	moveq	#1,d0
	jsr	seek_track(pc)
	moveq	#1,d0
	jsr	build_backup_sector_list(pc)
	move.w	d0,$18(sp)
	move.w	d0,-(sp)
	move.w	-$4(a4),-(sp)                   ; -> floppy_track
	move.w	-$6(a4),d2                      ; -> floppy_side
	moveq	#1,d1
	moveq	#3,d0
	jsr	show_track_result(pc)           ; show the result (3 = writing)
	addq.w	#4,sp
	subq.w	#1,d0
	beq.w	.done
	subq.w	#1,d0
	beq.s	.retry
	subq.w	#1,d0
	beq.s	.best_match
	subq.w	#2,d0
	beq.s	.new_disk
	bra.s	.advance

.retry
	move.w	-$2(a4),d0                      ; -> floppy_sector
	bne.s	.write_sectors
	bra.w	.write_track

.best_match
	clr.w	d0                              ; BEST MATCH: write again, ignoring errors
	jsr	build_backup_sector_list(pc)
.advance
	move.l	copy_write_ptr,$1e(sp)          ; advance the write pointer by the sectors left on the track
	move.w	#$200,d1
	move.w	dst_sectors,d0
	sub.w	-$2(a4),d0                      ; -> floppy_sector
	jsr	mul_words(pc)
	add.l	d0,copy_write_ptr
	movea.l	copy_write_ptr,a0
	cmpa.l	(a4),a0                         ; data ends inside this track: remember the sector
	bls.s	.track_done
	move.l	(a4),d0
	sub.l	$1e(sp),d0
	move.l	#$200,d1
	jsr	ldiv(pc)
	add.w	d0,-$2(a4)                      ; -> floppy_sector
	bra.s	.buffer_written

.track_done
	clr.w	-$2(a4)                         ; next side, track; past the end track the floppy is full, -> floppy_sector
	addq.w	#1,-$6(a4)                      ; -> floppy_side
	move.w	-$6(a4),d0                      ; -> floppy_side
	cmp.w	dst_sides,d0
	bls.s	.round_test
	clr.w	-$6(a4)                         ; -> floppy_side
	addq.w	#1,-$4(a4)                      ; -> floppy_track
	move.w	-$4(a4),d0                      ; -> floppy_track
	cmp.w	$6c(a5),d0                      ; -> cfg_end_track
	bls.s	.round_test
	addq.w	#1,-$8(a4)                      ; floppy full: next disk number, move the unwritten data down, -> disk_number
	move.l	(a4),d0
	sub.l	copy_write_ptr,d0
	movea.l	copy_write_ptr,a1
	movea.l	a2,a0
	jsr	memcpy(pc)
	move.l	copy_write_ptr,d0
	sub.l	a2,d0
	sub.l	d0,(a4)
	clr.b	$1(sp)
	bra.w	.write_round

.round_test
	movea.l	copy_write_ptr,a0               ; until all data in the buffer is written
	cmpa.l	(a4),a0
	bne.w	.track_list
.buffer_written
	move.w	$16(sp),d0                      ; everything read and written: done
	bne.w	.ratio
	move.l	a2,$1e(sp)
.keep_rest
	move.b	$52(a5),d0                      ; Compack: move the unwritten packed data to the start of the backup data, -> cfg_compack
	beq.s	.unpacked_rest
	move.l	a3,d1
	sub.l	$22(sp),d1
	move.l	d1,$12(sp)
	movea.l	$22(sp),a1
	movea.l	$1e(sp),a0
	move.l	d1,d0
	jsr	memcpy(pc)
	move.l	$12(sp),d0
	movea.l	$1e(sp),a3
	adda.l	d0,a3
	move.l	$26(sp),copy_read_ptr
	bra.s	.bar

.unpacked_rest
	move.l	$1e(sp),copy_read_ptr
.bar
	clr.b	d0                              ; memory bar
	move.b	d0,-(sp)
	move.b	$52(a5),d1                      ; -> cfg_compack
	beq.s	.bar_unpacked
	lea	$0(a3,d3.l),a0
	bra.s	.show_bar

.bar_unpacked
	movea.l	copy_read_ptr,a0
.show_bar
	move.b	(sp)+,d0
	jsr	draw_memory_bar(pc)
	lea	str_reading_drive_x,a0
	jsr	show_status_line(pc)
.read_count
	move.b	$64(a5),d0                      ; all sectors: as many as fit, -> cfg_used_only
	bne.s	.used_run
	move.l	copy_buffer_end,d0
	sub.l	copy_read_ptr,d0
	moveq	#0,d1
	move.w	bpb,d1
	jsr	ldiv(pc)
	move.l	d0,d6
	move.w	d5,d0
	add.w	d6,d0
	cmp.w	d0,d4
	bcc.s	.read_run
	move.w	d4,d6
	sub.w	d5,d6
	bra.s	.read_run

.used_run
	clr.w	d6                              ; used clusters only: a run of used clusters that fits
	bra.s	.used_test

.used_scan
	move.w	d5,d0
	add.w	d6,d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.read_run
	addq.w	#1,d6
.used_test
	moveq	#0,d0
	move.w	bpb,d0
	move.l	d0,-(sp)
	move.w	bpb,d1
	move.w	d6,d0
	jsr	mul_words(pc)
	movea.l	copy_read_ptr,a0
	adda.l	d0,a0
	movea.l	copy_buffer_end,a1
	suba.l	a0,a1
	cmpa.l	(sp)+,a1
	blt.s	.read_run
	move.w	d5,d0
	add.w	d6,d0
	cmp.w	d0,d4
	bhi.s	.used_scan
.read_run
	tst.w	d6
	beq.s	.skip_unused
.rwabs
	move.w	-$a(a4),-(sp)                   ; read the sectors from the partition, -> partition_drive
	move.w	d5,d2
	move.w	d6,d1
	movea.l	copy_read_ptr,a0
	clr.w	d0
	jsr	Rwabs(pc)
	addq.w	#2,sp
	tst.l	d0
	beq.s	.read_advance
	move.b	partition_letter,alert_read_error_on_partition_x+28 ; "Read Error on Partition X: [RETRY|CONT|ABORT]"
	lea	alert_read_error_on_partition_x,a0
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0
	beq.s	.rwabs
	subq.w	#2,d0
	beq.w	.done
.read_advance
	move.w	d6,d1                           ; advance
	move.w	bpb,d0
	jsr	mul_words(pc)
	add.l	d0,copy_read_ptr
	add.w	d6,d5
	move.b	$52(a5),d0                      ; -> cfg_compack
	bne.s	.keyboard
	movea.l	copy_read_ptr,a0
	clr.b	d0
	jsr	draw_memory_bar(pc)
	bra.s	.keyboard

.skip_unused
	addq.w	#1,d5                           ; unused cluster: skip it
.keyboard
	moveq	#21,d0                          ; Esc or Space?
	jsr	check_keyboard(pc)
	subq.w	#1,d0
	beq.s	.done
.read_test
	cmp.w	d5,d4                           ; until the end of the partition
	bhi.w	.read_more
	move.w	#$1,$16(sp)                     ; all read: write the rest
	bra.w	.pack

.ratio
	move.b	$52(a5),d0                      ; Compack: "compacked into XX% of its original size", -> cfg_compack
	beq.s	.done
	move.b	partition_letter,alert_the_data_of_partition_x_has+28
	move.l	$e(sp),d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	add.l	d1,d0
	lsl.l	#2,d0
	move.l	$a(sp),d1
	jsr	uldiv(pc)
	move.w	d0,$1c(sp)
	moveq	#0,d1
	move.w	d0,d1
	divu.w	#$a,d1
	dc.w	$d23c,$0030                     ; add.b #$30,d1
	move.b	d1,alert_the_data_of_partition_x_has+61
	moveq	#0,d2
	move.w	d0,d2
	divu.w	#$a,d2
	swap	d2
	dc.w	$d43c,$0030                     ; add.b #$30,d2
	move.b	d2,alert_the_data_of_partition_x_has+62
	lea	alert_the_data_of_partition_x_has,a0
	moveq	#1,d0
	jsr	alert(pc)
.done
	clr.w	d1                              ; head to track 0
	moveq	#1,d0
	jsr	restore_drive(pc)
	jsr	unlock_floppy(pc)
.return
	lea	$3c(sp),sp
	movem.l	(sp)+,d3-d7/a2-a6
	rts


alert_disk_number:
	move.l	a2,-(sp)
	move.l	a4,-(sp)
	lea	-$64(sp),sp
	movea.l	a0,a2
	movea.l	a1,a4
	lea	(sp),a0
	movea.l	a2,a1
	jsr	strcpy(pc)
	lea	(sp),a0
	jsr	strlen(pc)
	lea	$0(sp,d0.w),a0
	move.w	disk_number,d0
	moveq	#10,d1
	jsr	itoa(pc)
	movea.l	a4,a1
	lea	(sp),a0
	jsr	strcat(pc)
	lea	(sp),a0
	moveq	#1,d0
	jsr	alert(pc)
	lea	$64(sp),sp
	movea.l	(sp)+,a4
	movea.l	(sp)+,a2
	rts


build_backup_sector_list:
	movem.l	d3-d7/a2-a3,-(sp)
	move.w	d0,d7
	clr.w	d3
	move.w	d3,d4
	lea	written_sectors,a3
	bra.s	.use_sector_list

.loop_check_floppy_sector
	clr.w	d5
	cmp.w	floppy_sector,d6
	bls.s	.use_sector_list
	move.w	#$200,d1
	moveq	#-1,d0
	add.w	d6,d0
	sub.w	floppy_sector,d0
	jsr	mul_words(pc)
	movea.l	copy_write_ptr,a2
	adda.l	d0,a2
	cmpa.l	copy_data_end,a2
	bcc.s	.use_sector_list
	moveq	#6,d0
	muls.w	d4,d0
	move.w	d6,$0(a3,d0.w)                  ; -> written_sectors indexed
	move.l	a2,$2(a3,d0.w)                  ; -> written_sectors+2 indexed
	addq.w	#1,d4
	move.b	d7,-(sp)
	movea.l	a2,a0
	move.w	d6,d2
	move.w	floppy_side,d1
	moveq	#1,d0
	jsr	write_sectors(pc)
	addq.w	#2,sp
	move.w	d0,d5
	tst.w	d0
	beq.s	.use_sector_list
	tst.w	d7
	bne.s	.set_written_sectors
.use_sector_list
	move.w	d3,d0
	addq.w	#1,d3
	lea	sector_list,a0
	clr.w	d6
	move.b	$0(a0,d0.w),d6                  ; -> sector_list indexed
	bne.s	.loop_check_floppy_sector
.set_written_sectors
	moveq	#6,d0
	muls.w	d4,d0
	clr.w	$0(a3,d0.w)                     ; -> written_sectors indexed
	tst.w	d7
	beq.s	.result_0
	move.w	d5,d0
	bra.s	.return

.result_0
	clr.w	d0
.return
	movem.l	(sp)+,d3-d7/a2-a3
	rts


check_backup_disk:
	move.w	d3,-(sp)
.loop_read_sectors
	clr.b	-(sp)
	movea.l	buffer_start,a0
	moveq	#1,d2
	clr.w	d1
	moveq	#1,d0
	jsr	read_sectors(pc)
	addq.w	#2,sp
	tst.w	d0
	bne.s	.finish
	movea.l	copy_buffer,a0
	move.l	$e0(a0),d0
	movea.l	buffer_start,a1
	cmp.l	$e0(a1),d0
	bne.s	.finish
	lea	alert_the_disk_you_have_inserted,a0
	moveq	#1,d0
	jsr	alert(pc)
	move.w	d0,d3
	subq.w	#1,d0
	beq.s	.loop_read_sectors
	cmp.w	#$3,d3
	bne.s	.finish
	clr.b	d0
	bra.s	.finish2

.finish
	moveq	#1,d0
.finish2
	move.w	(sp)+,d3
	rts


;----------------------------------------------------------------------
; Scan Disk: reads every sector of the source disk, collects the damaged ones,
; offers to mark them bad in the FATs (or unmark sectors that are good again) and
; writes a damaged file report to the printer or a file.
;----------------------------------------------------------------------
scan_disk:
	movem.l	d3-d7/a2-a5,-(sp)
	lea	-$a4(sp),sp
.start
	lea	bpb,a3                          ; restart point after NEW DISK
	lea	buffer_start,a5
	lea	alert_x_source_disk_scan_abort,a4
	lea	config,a2
	clr.w	convert                         ; no conversion
	clr.w	d3                              ; keep Get Sectors; the configuration is read with used sectors only
	move.b	$64(a2),d3                      ; -> cfg_used_only
	move.b	#$1,$64(a2)                     ; -> cfg_used_only
	lea	str_scanning_2,a0               ; "Scanning"
	jsr	show_status_line(pc)
	moveq	#65,d0                          ; source letter into "X: Source Disk [SCAN|ABORT]"
	add.b	$5d(a2),d0                      ; -> cfg_source_drive
	move.b	d0,$5(a4)                       ; -> alert_x_source_disk_scan_abort+5
	clr.b	$5f(a2)                         ; nothing is formatted, -> cfg_format_dest
	clr.b	-(sp)                           ; ask for the source disk and read its configuration and FAT
	clr.w	d2
	clr.b	d1
	movea.l	(a5),a1
	movea.l	a4,a0
	moveq	#1,d0
	jsr	prepare_source(pc)
	addq.w	#2,sp
	tst.w	d0
	beq.w	.return
	move.b	d3,$64(a2)                      ; Get Sectors back, -> cfg_used_only
	jsr	enable_status_button(pc)        ; NEW DISK allowed
	move.l	copy_buffer,(sp)                ; the bad cluster list grows from the start of the copy buffer
	move.w	$6a(a2),d3                      ; from the start track, head there, -> cfg_start_track
	move.w	d3,d1
	clr.w	d0
	jsr	restore_drive(pc)
	clr.w	d4                              ; d4 = clusters marked bad before that are now read again
	bra.w	.track_test

.next_track
	clr.w	d5                              ; each track
	bra.w	.side_test

.next_side
	move.b	$63(a2),d0                      ; each side, -> cfg_read_config
	beq.s	.read_track                     ; all sectors (not Get Sectors used): bad marks of this track are cleared, they get rescanned
	move.b	$64(a2),d1                      ; -> cfg_used_only
	bne.s	.read_track
	moveq	#1,d7
	add.w	src_sides,d7
	muls.w	d3,d7
	add.w	d5,d7
	muls.w	src_sectors,d7
	move.w	d7,d6
	add.w	src_sectors,d6
	bra.s	.sector_test

.free_bad_cluster
	move.w	d7,d0                           ; cluster marked bad: free it and count it
	movea.l	a3,a1
	movea.l	fat_buffer,a0
	jsr	sector_is_bad(pc)
	tst.b	d0
	beq.s	.next_sector
	move.w	d7,d0
	movea.l	a3,a0
	jsr	free_sector_cluster(pc)
	addq.w	#1,d4
.next_sector
	addq.w	#1,d7
.sector_test
	cmp.w	d7,d6
	bhi.s	.free_bad_cluster
.read_track
	move.w	d3,d2                           ; sector list of the track
	move.w	d5,d1
	clr.w	d0
	jsr	build_track_sector_list(pc)
.retry_track
	moveq	#1,d2                           ; read the track
	move.w	d3,d1
	move.w	d5,d0
	suba.l	a0,a0
	jsr	read_track_sectors(pc)
	move.w	d0,d7
	tst.w	d0
	blt.s	.side_done
	move.w	d0,-(sp)                        ; show it (2 = scanning): ABORT, RETRY, BEST MATCH, NEW DISK
	move.w	d3,-(sp)
	move.w	d5,d2
	clr.w	d1
	moveq	#2,d0
	jsr	show_track_result(pc)
	addq.w	#4,sp
	subq.w	#1,d0
	beq.s	.scan_done
	subq.w	#1,d0
	beq.s	.retry_track
	subq.w	#1,d0
	beq.s	.best_match
	subq.w	#2,d0
	beq.s	.new_disk
	bra.s	.side_done

.best_match
	moveq	#1,d0                           ; BEST MATCH: put the failing sectors into the bad cluster list
	move.w	d0,-(sp)
	lea	$2(sp),a0
	move.w	d3,d2
	move.w	d5,d1
	clr.w	d0
	jsr	mark_bad_sectors(pc)
	addq.w	#2,sp
	bra.s	.side_done

.new_disk
	clr.w	d1                              ; NEW DISK: start again
	clr.w	d0
	jsr	restore_drive(pc)
	bra.w	.start

.side_done
	addq.w	#1,d5
.side_test
	cmp.w	src_sides,d5
	ble.w	.next_side
	addq.w	#1,d3                           ; next track
.track_test
	cmp.w	$6c(a2),d3                      ; -> cfg_end_track
	ble.w	.next_track
.scan_done
	clr.w	d1                              ; head to track 0
	clr.w	d0
	jsr	restore_drive(pc)
	jsr	unlock_floppy(pc)
	move.w	bad_sectors,d0                  ; new bad sectors or previously bad ones now good?
	bne.s	.offer_marking
	tst.w	d4
	beq.w	.return
.offer_marking
	cmpi.b	#$1,$64(a2)                     ; only when all sectors were scanned, -> cfg_used_only
	beq.s	.offer_report
	lea	$e(sp),a3                       ; "[2][nn Sectors are bad. Mark them in the FATs or leave them untouched? ][ MARK | LEAVE ]"
	lea	$27(a4),a1                      ; -> str_alert_2
	movea.l	a3,a0
	jsr	strcpy(pc)
	move.w	bad_sectors,d0
	beq.s	.only_unmarked
	moveq	#10,d1
	lea	$4(sp),a0
	jsr	itoa(pc)
	lea	$4(sp),a1
	movea.l	a3,a0
	jsr	strcat(pc)
	lea	$2c(a4),a1                      ; -> str_sectors_are_bad_mark_them_in
	movea.l	a3,a0
	jsr	strcat(pc)
	bra.s	.ask_mark

.only_unmarked
	lea	$7f(a4),a1                      ; "Previously bad-marked sectors are now OK. Update the FATs ...? [UPDATE|LEAVE]", -> str_previously_bad_marked_sectors
	movea.l	a3,a0
	jsr	strcat(pc)
.ask_mark
	movea.l	a3,a0
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0                           ; MARK / UPDATE: write the FATs of the source disk
	bne.s	.offer_report
	jsr	Dgetdrv(pc)
	move.w	d0,d6
	move.w	src_unit,d0
	jsr	write_fats(pc)
	move.w	src_unit,d0                     ; and make TOS read the disk again
	jsr	force_media_change(pc)
	move.w	d6,d0
	jsr	Dsetdrv(pc)
.offer_report
	movea.l	(sp),a0                         ; damaged sectors found?
	cmpa.l	copy_buffer,a0
	beq.w	.return
	lea	$1c4(a4),a0                     ; "Output a report of the damaged files to the printer or to a file?", -> alert_output_a_report_of_the
	moveq	#1,d0
	jsr	alert(pc)
	move.w	d0,d6                           ; 1 CANCEL, 2 PRINTER, 3 FILE
	subq.w	#1,d0
	beq.w	.return
	clr.w	d0
	jsr	show_mouse(pc)
	suba.l	a0,a0
	moveq	#2,d0
	jsr	graf_mouse(pc)
	movea.l	(sp),a0                         ; directory tree of the disk after the bad cluster list
	move.l	a0,dir_list_end
	move.l	a0,dir_list
	jsr	read_directory_tree(pc)
	move.l	copy_buffer,(sp)                ; count the damaged clusters of each file
	bra.s	.bad_cluster_test

.next_bad_cluster
	movea.l	(sp),a0
	addq.l	#2,(sp)
	move.w	(a0),d0
	jsr	count_damaged_cluster(pc)
.bad_cluster_test
	movea.l	(sp),a0
	cmpa.l	dir_list,a0
	bcs.s	.next_bad_cluster
	clr.w	d0
	suba.l	a0,a0
	jsr	graf_mouse(pc)
	cmp.w	#$2,d6                          ; printer: GEMDOS handle 3 (PRN:)
	bne.s	.report_to_file
	moveq	#3,d7
	bra.s	.write_report

.report_to_file
	movea.l	(a5),a0                         ; file: file selector and Fcreate
	clr.b	(a0)
	move.l	main_tree_ptr,-(sp)
	pea	str_report_names
	movea.l	(a5),a1
	lea	str_output_scan_report_to,a0
	jsr	file_selector(pc)
	addq.w	#8,sp
	tst.b	d0
	beq.w	.return
	jsr	draw_progress_frame(pc)
	clr.w	d0
	movea.l	(a5),a0
	jsr	Fcreate(pc)
	move.w	d0,d7
	bge.s	.write_report
	lea	alert_cannot_open_file_abort,a0
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.write_report
	suba.l	a0,a0
	moveq	#2,d0
	jsr	graf_mouse(pc)
	lea	str_damaged_file_report_path,a1 ; header "Damaged File Report / Path & Filename ... Damaged Sectors File Size"
	movea.l	(a5),a0
	jsr	strcpy(pc)
	movea.l	(a5),a0
	jsr	strlen(pc)
	move.l	d0,d1
	move.w	d7,d0
	movea.l	(a5),a0
	jsr	Fwrite(pc)
	move.l	copy_buffer,(sp)
	movea.l	dir_list,a3                     ; each directory entry with damaged clusters:
	clr.w	d6
	bra.s	.entry_test

.next_entry
	move.w	$14(a3),d0
	dc.w	$c07c,$7fff                     ; and.w #$7fff,d0
	beq.s	.entry_done
	addq.w	#1,d6
	movea.l	a3,a1                           ; one report line with path, damaged count and size
	movea.l	(a5),a0
	jsr	build_report_path(pc)
	movea.l	(a5),a0
	jsr	strlen(pc)
	move.l	d0,-(sp)
	movea.l	(a5),a0
	jsr	strlen(pc)
	move.l	d0,d1
	move.w	d7,d0
	movea.l	(a5),a0
	jsr	Fwrite(pc)
	cmp.l	(sp)+,d0
	beq.s	.entry_done
	lea	alert_cannot_write_file_abort,a0
	moveq	#1,d0
	jsr	alert(pc)
	bra.s	.close_report

.entry_done
	lea	$1a(a3),a3
.entry_test
	cmpa.l	dir_list_end,a3
	bcs.s	.next_entry
	moveq	#10,d1                          ; footer "nn Files damaged."
	movea.l	(a5),a0
	move.w	d6,d0
	jsr	itoa(pc)
	lea	str_files_damaged,a1
	movea.l	(a5),a0
	jsr	strcat(pc)
	movea.l	(a5),a0
	jsr	strlen(pc)
	move.l	d0,d1
	move.w	d7,d0
	movea.l	(a5),a0
	jsr	Fwrite(pc)
.close_report
	cmp.w	#$5,d7                          ; close a file (handles 0..4 are devices)
	blt.s	.done
	move.w	d7,d0
	jsr	Fclose(pc)
.done
	suba.l	a0,a0
	clr.w	d0
	jsr	graf_mouse(pc)
.return
	lea	$a4(sp),sp
	movem.l	(sp)+,d3-d7/a2-a5
	rts


read_system_sectors:
	move.w	d0,-(sp)                        ; reads the second FAT of drive d0 into fat_buffer
	moveq	#1,d2
	add.w	bpb+bpb_fsiz,d2
	move.w	bpb+bpb_fsiz,d1
	movea.l	fat_buffer,a0
	clr.w	d0
	jsr	Rwabs(pc)
	addq.w	#2,sp
	tst.l	d0
	beq.s	.ok
	lea	alert_cannot_access_system_sectors,a0
	moveq	#1,d0
	jsr	alert(pc)
	moveq	#1,d0
	rts

.ok
	clr.w	d0
	rts


build_track_sector_list:
	movem.l	d3-d5/a2,-(sp)
	subq.w	#4,sp
	tst.w	d0
	bne.s	.use_dst_sectors
	move.w	src_sectors,d3
	move.w	src_sides,(sp)
	bra.s	.use_read_config

.use_dst_sectors
	move.w	dst_sectors,d3
	move.w	dst_sides,(sp)
.use_read_config
	lea	sector_list,a2
	move.b	cfg_read_config,d0
	beq.s	.set_list_sectors
	move.b	cfg_used_only,d0
	beq.s	.set_list_sectors
	moveq	#1,d0
	add.w	(sp),d0
	mulu.w	d2,d0
	add.w	d1,d0
	mulu.w	d3,d0
	move.w	d0,$2(sp)
	clr.w	d5
	move.w	d5,$20(a2)                      ; -> list_sectors
	moveq	#1,d4
	bra.s	.loop_test

.loop_sector_is_used
	move.w	$2(sp),d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.next
	move.b	d4,$0(a2,d5.w)                  ; -> sector_list indexed
	addq.w	#1,d5
	addq.w	#1,$20(a2)                      ; -> list_sectors
.next
	addq.w	#1,$2(sp)
	addq.w	#1,d4
.loop_test
	cmp.w	d4,d3
	bcc.s	.loop_sector_is_used
	bra.s	.set_sector_list

.set_list_sectors
	move.w	d3,$20(a2)                      ; -> list_sectors
	clr.w	d5
	bra.s	.loop_test2

.loop_set_sector_list
	moveq	#1,d0
	add.b	d5,d0
	move.b	d0,$0(a2,d5.w)                  ; -> sector_list indexed
	addq.w	#1,d5
.loop_test2
	cmp.w	d5,d3
	bhi.s	.loop_set_sector_list
.set_sector_list
	clr.b	$0(a2,d5.w)                     ; -> sector_list indexed
	addq.w	#4,sp
	movem.l	(sp)+,d3-d5/a2
	rts


free_sector_cluster:
	cmp.w	$c(a0),d0
	bcs.s	.return
	move.w	d0,d1
	sub.w	$c(a0),d1
	moveq	#0,d2
	move.w	d1,d2
	divu.w	$2(a0),d2
	addq.w	#2,d2
	move.w	d2,d0
	move.w	d0,d1
	lsr.w	#1,d1
	add.w	d2,d1
	lea	fat_buffer,a0
	moveq	#1,d2
	and.w	d0,d2
	beq.s	.false
	moveq	#0,d0
	move.w	d1,d0
	movea.l	(a0),a1
	andi.b	#$f,$0(a1,d0.l)
	moveq	#1,d2
	add.w	d1,d2
	moveq	#0,d0
	move.w	d2,d0
	movea.l	(a0),a1
	clr.b	$0(a1,d0.l)
	rts

.false
	moveq	#0,d0
	move.w	d1,d0
	movea.l	(a0),a1
	clr.b	$0(a1,d0.l)
	moveq	#1,d2
	add.w	d1,d2
	moveq	#0,d0
	move.w	d2,d0
	movea.l	(a0),a1
	andi.b	#$f0,$0(a1,d0.l)
.return
	rts


sector_is_used:
	move.l	d3,-(sp)
	move.l	d4,-(sp)
	lea	bpb,a0
	cmp.w	$c(a0),d0                       ; -> bpb+bpb_datrec
	bcs.w	.used
	move.w	d0,d1
	sub.w	$c(a0),d1                       ; -> bpb+bpb_datrec
	moveq	#0,d2
	move.w	d1,d2
	divu.w	$2(a0),d2                       ; -> bpb+bpb_clsiz
	addq.w	#2,d2
	move.w	d2,d0
	lea	fat_buffer,a1
	moveq	#1,d2
	and.w	$10(a0),d2                      ; -> bpb+bpb_bflags
	beq.s	.fat12
	add.w	d0,d0
	moveq	#0,d1
	move.w	d0,d1
	movea.l	(a1),a0
	clr.w	d2
	move.b	$0(a0,d1.l),d2
	move.w	d2,d1
	moveq	#1,d2
	add.w	d0,d2
	moveq	#0,d3
	move.w	d2,d3
	clr.w	d2
	move.b	$0(a0,d3.l),d2
	lsl.w	#8,d2
	add.w	d2,d1
	bra.s	.check_used

.fat12
	move.w	d0,d2
	lsr.w	#1,d2
	add.w	d0,d2
	moveq	#0,d1
	move.w	d2,d1
	movea.l	(a1),a0
	clr.w	d3
	move.b	$0(a0,d1.l),d3
	move.w	d3,d1
	moveq	#1,d3
	add.w	d2,d3
	moveq	#0,d4
	move.w	d3,d4
	clr.w	d3
	move.b	$0(a0,d4.l),d3
	lsl.w	#8,d3
	add.w	d3,d1
	moveq	#1,d2
	and.w	d0,d2
	beq.s	.even
	lsr.w	#4,d1
	bra.s	.sign_extend

.even
	dc.w	$c27c,$fff                      ; and.w #$fff,d1
.sign_extend
	cmp.w	#$ff0,d1
	bcs.s	.check_used
	dc.w	$827c,$f000                     ; or.w #$f000,d1
.check_used
	cmp.w	#$2,d1
	bcs.s	.free
	cmp.w	#$fff0,d1
	bcs.s	.used
	cmp.w	#$fff8,d1
	bcc.s	.used
.free
	clr.w	d0
	bra.s	.return

.used
	moveq	#1,d0
.return
	move.l	(sp)+,d4
	move.l	(sp)+,d3
	rts


prepare_source:
	movem.l	d3-d6/a3-a4,-(sp)               ; a0 message, a1 buffer, d0 show the configuration, d1/d2 use density d2, stack: drives to check
	movea.l	a1,a4
	move.b	d0,d3
	move.b	d1,d5
	move.w	d2,d6
	move.b	$1c(sp),d4
	lea	config,a3
	moveq	#1,d0                           ; ask for the disk (request boxes)
	jsr	request_alert(pc)
	subq.w	#2,d0
	beq.s	.failed
	move.b	$63(a3),d0                      ; read its configuration, -> cfg_read_config
	beq.s	.no_read
	jsr	enable_status_box(pc)
	clr.w	d1
	move.b	d3,d1
	clr.w	d0
	move.b	$5d(a3),d0                      ; -> cfg_source_drive
	movea.l	a4,a0
	jsr	read_disk_config(pc)
	tst.w	d0
	beq.s	.check_drives
	bra.s	.failed

.no_read
	jsr	disable_status_box(pc)
.check_drives
	cmp.b	#$3,d4                          ; check the drives
	beq.s	.buffers
	cmp.b	#$2,d4
	bne.s	.check_one
	clr.w	d0
	jsr	check_drive_support(pc)
	tst.b	d0
	beq.s	.failed
	moveq	#1,d0
	jsr	check_drive_support(pc)
	tst.b	d0
	bne.s	.buffers
	bra.s	.failed

.check_one
	clr.w	d0
	move.b	d4,d0
	jsr	check_drive_support(pc)
	tst.b	d0
	bne.s	.buffers
.failed
	clr.w	d0
	bra.s	.return

.buffers
	tst.b	d5                              ; track buffers (with a given density) and the system sectors
	beq.s	.own_density
	clr.w	d5
	move.b	$6e(a3),d5                      ; -> cfg_hd
	move.b	d6,$6e(a3)                      ; -> cfg_hd
	jsr	alloc_track_buffers(pc)
	move.b	d5,$6e(a3)                      ; -> cfg_hd
	bra.s	.read_config

.own_density
	jsr	alloc_track_buffers(pc)
.read_config
	jsr	read_source_config(pc)
	clr.w	d1
	move.b	d0,d1
	move.w	d1,d0
.return
	movem.l	(sp)+,d3-d6/a3-a4
	rts


read_source_config:
	move.b	cfg_read_config,d0
	beq.s	.set_drive_params
	move.b	cfg_used_only,d1
	beq.s	.set_drive_params
	clr.w	d0
	move.b	cfg_source_drive,d0
	jsr	read_system_sectors(pc)
	tst.w	d0
	beq.s	.set_drive_params
	clr.b	d0
	rts

.set_drive_params
	jsr	set_drive_params(pc)
	jsr	draw_status_labels(pc)
	moveq	#1,d0
	rts


;----------------------------------------------------------------------
; Image Copy: reads a disk into a .DIM image file or restores one to a disk.
;----------------------------------------------------------------------
image_copy:
	move.w	d3,-(sp)
	move.l	a2,-(sp)
	lea	-$70(sp),sp
	lea	alert_read_disk_image_and_write_it,a0 ; "Read Disk Image and write it to a file or restore Disk Image ..."
	moveq	#2,d0
	jsr	alert(pc)
	move.w	d0,d3                           ; 1 READ (disk to file), 2 RESTORE (file to disk), 3 CANCEL
	subq.w	#3,d0
	beq.w	.done
	lea	config,a2
	movea.l	a2,a0                           ; save the configuration, it is changed for the copy
	lea	(sp),a1
	moveq	#27,d0
.save_config
	move.l	(a0)+,(a1)+
	dbra	d0,.save_config
	clr.b	$5b(a2)                         ; no extended memory, -> cfg_ext_memory
	cmp.w	#$1,d3
	bne.s	.restore_other_drive_source
	clr.b	d0                              ; READ: nothing is formatted; the other drive is the "destination"
	move.b	d0,$5f(a2)                      ; -> cfg_format_dest
	move.b	d0,$5a(a2)                      ; -> cfg_smart_format
	move.b	$5d(a2),d1                      ; -> cfg_source_drive
	bne.s	.set_dest_drive
	moveq	#1,d2
	bra.s	.set_dest_drive2

.set_dest_drive
	clr.w	d2
.set_dest_drive2
	move.b	d2,$5e(a2)                      ; -> cfg_dest_drive
	bra.s	.status

.restore_other_drive_source
	move.b	$5e(a2),d0                      ; RESTORE: the other drive is the "source", -> cfg_dest_drive
	bne.s	.set_source_drive
	moveq	#1,d1
	bra.s	.set_source_drive2

.set_source_drive
	clr.w	d1
.set_source_drive2
	move.b	d1,$5d(a2)                      ; -> cfg_source_drive
.status
	cmp.w	#$1,d3
	bne.s	.show_status_line
	lea	str_read_image,a0
	bra.s	.show_status_line2

.show_status_line
	lea	str_restore_image,a0
.show_status_line2
	jsr	show_status_line(pc)
	move.b	d3,d1                           ; d1 = image mode
	clr.w	d0
	jsr	copy_engine(pc)
	lea	(sp),a0                         ; configuration back
	movea.l	a2,a1
	moveq	#27,d0
.restore_config
	move.l	(a0)+,(a1)+
	dbra	d0,.restore_config
.done
	lea	$70(sp),sp
	movea.l	(sp)+,a2
	move.w	(sp)+,d3
	rts


;----------------------------------------------------------------------
; Copy Disk (d0 = 0) and New Conf (d0 = 1, Converting: write with the
; configuration of the main dialog instead of the source's).
;----------------------------------------------------------------------
copy_disk:
	move.w	d3,-(sp)
	move.w	d0,d3
	tst.w	d0
	beq.s	.show_status_line
	lea	str_converting,a0
	bra.s	.show_status_line2

.show_status_line
	lea	str_copying,a0
.show_status_line2
	jsr	show_status_line(pc)
	clr.b	d1                              ; no image file
	move.w	d3,d0
	jsr	copy_engine(pc)
	move.w	(sp)+,d3
	rts


;----------------------------------------------------------------------
; Copy engine of Copy Disk, New Conf and Image Copy: reads as many tracks as fit in
; memory (or extended memory on a hard disk partition), then writes them to one or
; more destination disks or the image file.
;----------------------------------------------------------------------
copy_engine:
	movem.l	d3-d7/a2-a6,-(sp)
	lea	-$aa(sp),sp
	move.w	d0,$a8(sp)                      ; convert flag (New Conf)
	move.b	d1,d4                           ; d4 = image mode: 0 disk to disk, 1 disk to file, 2 file to disk
	lea	copy_read_ptr,a4
	clr.b	$36(a4)                         ; no extended memory file open, -> temp_file_open
.restart
	lea	copy_buffer,a3                  ; restart point after NEW DISK
	lea	config,a2
	jsr	close_image_file(pc)
	move.w	$a8(sp),$2c(a4)                 ; -> convert
	move.w	$a8(sp),d0
	beq.s	.units                          ; New Conf: the destination format is the disk configuration of the main dialog
	moveq	#1,d0
	jsr	check_drive_support(pc)
	tst.b	d0
	beq.w	.return
	clr.w	d0
	move.b	$6e(a2),d0                      ; step rate table for DD or HD, -> cfg_hd
	move.w	d0,$4c(sp)
	beq.s	.dd_rates
	move.l	#hd_step_rates,$46(sp)
	bra.s	.rate_by_drive

.dd_rates
	move.l	#dd_step_rates,$46(sp)
.rate_by_drive
	move.b	$5e(a2),d0                      ; step rate of the destination drive, -> cfg_dest_drive
	beq.s	.rate_a
	move.b	$4d(a2),d1                      ; -> cfg_b_step_rate
	bra.s	.rate

.rate_a
	move.b	$4c(a2),d1                      ; -> cfg_a_step_rate
.rate
	moveq	#0,d0
	move.b	d1,d0
	add.l	d0,d0
	movea.l	$46(sp),a0
	move.w	$0(a0,d0.l),$4a(sp)
	move.w	$68(a2),$38(sp)                 ; keep the destination format, -> cfg_sectors
	move.w	$66(a2),$3c(sp)                 ; -> cfg_sides
	move.w	$6c(a2),$3a(sp)                 ; -> cfg_end_track
	move.b	#$1,$63(a2)                     ; the source is read with its own configuration, used sectors only, -> cfg_read_config
	clr.w	d0
	move.b	$64(a2),d0                      ; -> cfg_used_only
	move.w	d0,$26(sp)
	move.b	#$1,$64(a2)                     ; -> cfg_used_only
.units
	clr.w	d0                              ; source and destination units
	move.b	$5d(a2),d0                      ; -> cfg_source_drive
	move.w	d0,src_unit
	clr.w	d1
	move.b	$5e(a2),d1                      ; -> cfg_dest_drive
	move.w	d1,dst_unit
	lea	image_handle,a6                 ; drive letters into the messages
	moveq	#65,d2
	add.b	dst_unit+1,d2
	move.b	d2,-$204(a6)                    ; -> alert_x_destination_disk_2+6
	moveq	#65,d0
	add.b	src_unit+1,d0
	move.b	d0,-$295(a6)                    ; -> alert_x_source_disk_copy_abort+5
	move.b	d2,-$26f(a6)                    ; -> alert_x_destination_disk_copy_abort+4
	move.b	d0,-$242(a6)                    ; -> alert_x_source_disk_x_destination+4
	move.b	d2,-$233(a6)                    ; -> alert_x_source_disk_x_destination+19
	movea.w	src_unit,a0                     ; one drive or Multiple Copy: "X: Source Disk" alone
	cmpa.w	d1,a0
	beq.s	.source_message
	move.b	$61(a2),d0                      ; -> cfg_multiple_copy
	beq.s	.both_message
.source_message
	lea	-$29a(a6),a5                    ; -> alert_x_source_disk_copy_abort
	bra.s	.by_mode

.both_message
	lea	-$246(a6),a5                    ; else "X: Source Disk / X: Destination Disk", -> alert_x_source_disk_x_destination
.by_mode
	tst.b	d4                              ; image modes ask for a file first
	bne.s	.choose_file
	move.w	$a8(sp),d0
	beq.s	.copy_source
	moveq	#3,d1                           ; New Conf: read the source configuration (keeps the boot sector)
	move.b	d1,-(sp)
	move.w	$4e(sp),d2
	movea.l	buffer_start,a1
	movea.l	a5,a0
	clr.b	d0
	moveq	#1,d1
	jsr	prepare_source(pc)
	addq.w	#2,sp
	tst.w	d0
	beq.w	.return
	bra.w	.buffer

.copy_source
	moveq	#2,d0                           ; Copy: read the source configuration
	move.b	d0,-(sp)
	clr.w	d2
	clr.b	d1
	movea.l	buffer_start,a1
	movea.l	a5,a0
	moveq	#1,d0
	jsr	prepare_source(pc)
	addq.w	#2,sp
	tst.w	d0
	beq.w	.return
	bra.w	.buffer

.choose_file
	move.w	$2e(a4),d0                      ; file selector on the image drive, -> image_drive
	jsr	Dsetdrv(pc)
	clr.b	$58(sp)
	move.l	main_tree_ptr,-(sp)
	pea	str_dim
	lea	$60(sp),a1
	move.l	a1,-(sp)
	cmp.b	#$2,d4
	bne.s	.write_title
	lea	str_restore_image_from_file,a0
	bra.s	.file_selector

.write_title
	lea	str_write_image_to_file,a0
.file_selector
	movea.l	(sp)+,a1
	jsr	file_selector(pc)
	addq.w	#8,sp
	clr.w	d6
	move.b	d0,d6
	tst.w	d6
	beq.w	.return
	jsr	draw_progress_frame(pc)
	jsr	Dgetdrv(pc)                     ; the image may not be on a floppy that takes part in the copy
	move.w	d0,$2e(a4)                      ; -> image_drive
	cmp.b	#$1,d4
	bne.s	.image_dest
	move.w	src_unit,d1
	bra.s	.check_drive

.image_dest
	move.w	dst_unit,d1
.check_drive
	move.w	$2e(a4),d0                      ; -> image_drive
	cmp.w	d1,d0
	bne.s	.extension
	lea	alert_please_select_a_partition_ok,a0
	moveq	#1,d0
	jsr	alert(pc)
	move.w	#$2,$2e(a4)                     ; -> image_drive
	bra.w	.choose_file

.extension
	moveq	#46,d0                          ; default extension .DIM
	lea	$58(sp),a0
	jsr	strchr(pc)
	move.l	a0,d0
	bne.s	.open_image
	lea	str_dim_2,a1
	lea	$58(sp),a0
	jsr	strcat(pc)
.open_image
	cmp.b	#$2,d4                          ; RESTORE: open the image and read its header
	bne.w	.create_image
	clr.w	d0
	lea	$58(sp),a0
	jsr	Fopen(pc)
	move.w	d0,(a6)
	subq.w	#4,d0
	bge.s	.read_header
.bad_file
	jsr	close_image_file(pc)
	lea	alert_cannot_access_the_selected,a0
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0
	bne.w	.return
	bra.w	.choose_file

.read_header
	clr.w	d0                              ; the image is written with the disk configuration of the main dialog
	move.b	$6e(a2),d0                      ; -> cfg_hd
	move.w	d0,$4c(sp)
	move.w	$68(a2),$38(sp)                 ; -> cfg_sectors
	move.w	$66(a2),$3c(sp)                 ; -> cfg_sides
	move.w	$6c(a2),$3a(sp)                 ; -> cfg_end_track
	lea	$6f(a2),a0                      ; header offset of the track data, -> cfg_disk_name
	move.l	a0,d1
	dc.w	$92bc                           ; sub.l #cfg_read_config,d1
	dc.l	cfg_read_config
	dc.w	$d2bc                           ; add.l #$14,d1
	dc.l	$14
	move.l	d1,(sp)
	lea	$6(sp),a0                       ; header: $4242,
	move.w	(a6),d0
	moveq	#2,d1
	jsr	Fread(pc)
	moveq	#2,d1
	cmp.l	d0,d1
	bne.s	.bad_file
	lea	$6f(a2),a0                      ; the configuration bytes cfg_read_config .. cfg_hd (Read Disk Config., Get Sectors,, -> cfg_disk_name
	suba.l	#cfg_read_config,a0
	move.l	a0,-(sp)
	lea	$63(a2),a0                      ; -> cfg_read_config
	lea	$6f(a2),a1                      ; sides, sectors, start and end track, density),, -> cfg_disk_name
	move.l	a1,d1
	dc.w	$92bc                           ; sub.l #cfg_read_config,d1
	dc.l	cfg_read_config
	move.w	(a6),d0
	jsr	Fread(pc)
	cmp.l	(sp)+,d0
	bne.w	.bad_file
	lea	bpb,a0                          ; and the BPB
	moveq	#18,d1
	move.w	(a6),d0
	jsr	Fread(pc)
	moveq	#18,d1
	cmp.l	d0,d1
	bne.w	.bad_file
	cmpi.w	#$4242,$6(sp)                   ; not $4242: "The selected file does not contain a Disk Image"
	beq.s	.read_boot
	jsr	close_image_file(pc)
	lea	alert_the_selected_file_does_not,a0
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0
	bne.w	.return
	bra.w	.choose_file

.read_boot
	move.b	$63(a2),d0                      ; then the boot sector if the configuration was read from the disk, -> cfg_read_config
	beq.s	.ask_convert
	movea.l	buffer_start,a0
	move.l	#$200,d1
	move.w	(a6),d0
	jsr	Fread(pc)
	cmp.l	#$200,d0
	bne.w	.file_error
.ask_convert
	move.b	$63(a2),d0                      ; -> cfg_read_config
	beq.w	.image_config
	lea	alert_do_you_want_to_use_the,a0 ; "Do you want to use the settings of the Disk-Configuration-Box?"
	moveq	#2,d0
	jsr	alert(pc)
	subq.w	#1,d0
	bne.s	.image_config
	moveq	#1,d0                           ; YES: convert to the dialog's configuration while restoring
	move.w	d0,$a8(sp)
	move.w	d0,$2c(a4)                      ; -> convert
	move.w	$4c(sp),d1
	beq.s	.hd_rates
	move.l	#hd_step_rates,$46(sp)
	bra.s	.rate_by_drive2

.hd_rates
	move.l	#dd_step_rates,$46(sp)
.rate_by_drive2
	move.b	$5e(a2),d0                      ; -> cfg_dest_drive
	beq.s	.rate_a2
	move.b	$4d(a2),d1                      ; -> cfg_b_step_rate
	bra.s	.rate2

.rate_a2
	move.b	$4c(a2),d1                      ; -> cfg_a_step_rate
.rate2
	moveq	#0,d0
	move.b	d1,d0
	add.l	d0,d0
	movea.l	$46(sp),a0
	move.w	$0(a0,d0.l),$4a(sp)
	clr.w	d0
	move.b	$64(a2),d0                      ; -> cfg_used_only
	move.w	d0,$26(sp)
	move.b	#$1,$64(a2)                     ; -> cfg_used_only
	clr.w	d6
	move.b	$6e(a2),d6                      ; -> cfg_hd
	move.b	$4d(sp),$6e(a2)                 ; -> cfg_hd
	jsr	alloc_track_buffers(pc)
	move.b	d6,$6e(a2)                      ; -> cfg_hd
	bra.s	.check_support

.image_config
	jsr	show_disk_config(pc)            ; NO: the image's own configuration
	jsr	set_sides_density(pc)
	jsr	alloc_track_buffers(pc)
.check_support
	moveq	#1,d0
	jsr	check_drive_support(pc)
	tst.b	d0
	beq.w	.return
	move.b	$63(a2),d0                      ; used sectors only: read the FAT from the image, -> cfg_read_config
	beq.s	.drive_params
	move.b	$64(a2),d1                      ; -> cfg_used_only
	beq.s	.drive_params
	moveq	#1,d2
	move.w	d2,-(sp)
	move.w	bpb+bpb_fsiz,d0
	move.w	#$200,d1
	jsr	mul_words(pc)
	move.l	d0,d7
	move.w	(a6),d1
	move.w	(sp)+,d2
	jsr	Fseek(pc)
	movea.l	fat_buffer,a0
	move.l	d7,d1
	move.w	(a6),d0
	jsr	Fread(pc)
	cmp.l	d0,d7
	bne.w	.file_error
.drive_params
	jsr	set_drive_params(pc)
	jsr	draw_status_labels(pc)
	bra.w	.buffer

.create_image
	clr.w	d0                              ; READ: create the image file
	lea	$58(sp),a0
	jsr	Fopen(pc)
	move.w	d0,(a6)
	subq.w	#4,d0
	ble.s	.ask_source
	move.w	(a6),d0
	jsr	Fclose(pc)
	lea	alert_file_already_exists_overwrite,a0 ; "File already exists. Overwrite it?"
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#2,d0
	beq.w	.choose_file
	lea	$58(sp),a0
	jsr	Fdelete(pc)
.ask_source
	move.w	#$ffff,(a6)
	lea	-$29a(a6),a0                    ; "X: Source Disk [COPY|ABORT]", -> alert_x_source_disk_copy_abort
	moveq	#1,d0
	jsr	request_alert(pc)
	subq.w	#2,d0
	beq.w	.return
	move.b	$63(a2),d0                      ; read the configuration of the source disk, -> cfg_read_config
	beq.s	.dialog_config
	moveq	#1,d1
	clr.w	d0
	move.b	$5d(a2),d0                      ; -> cfg_source_drive
	movea.l	buffer_start,a0
	jsr	read_disk_config(pc)
	tst.w	d0
	bne.w	.return
	bra.s	.buffers

.dialog_config
	clr.w	d0
	jsr	check_drive_support(pc)
	tst.b	d0
	beq.w	.return
.buffers
	jsr	alloc_track_buffers(pc)
	jsr	read_source_config(pc)
	tst.b	d0
	beq.w	.return
	jsr	image_size(pc)                  ; enough space on the partition for the image?
	move.l	d0,d7
	clr.w	d0
	lea	dfree_info,a0
	jsr	Dfree(pc)
	tst.w	d0
	bne.s	.file_error
	move.l	d7,d0
	jsr	image_fits_partition(pc)
	tst.b	d0
	bne.s	.write_header
	lea	alert_partition_has_not_enough,a0
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.write_header
	clr.w	d0                              ; create it and write the header: $4242, configuration bytes, BPB
	lea	$58(sp),a0
	jsr	Fcreate(pc)
	move.w	d0,(a6)
	bge.s	.header
.file_error
	lea	-$b3(a6),a0                     ; -> alert_read_write_error_on_the_disk
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.header
	move.w	#$4242,$6(sp)
	lea	$6(sp),a0
	moveq	#2,d1
	move.w	(a6),d0
	jsr	Fwrite(pc)
	moveq	#2,d1
	cmp.l	d0,d1
	bne.s	.file_error
	lea	$6f(a2),a0                      ; -> cfg_disk_name
	suba.l	#cfg_read_config,a0
	move.l	a0,-(sp)
	lea	$63(a2),a0                      ; -> cfg_read_config
	lea	$6f(a2),a1                      ; -> cfg_disk_name
	move.l	a1,d1
	dc.w	$92bc                           ; sub.l #cfg_read_config,d1
	dc.l	cfg_read_config
	move.w	(a6),d0
	jsr	Fwrite(pc)
	cmp.l	(sp)+,d0
	bne.s	.file_error
	lea	bpb,a0
	moveq	#18,d1
	move.w	(a6),d0
	jsr	Fwrite(pc)
	moveq	#18,d1
	cmp.l	d0,d1
	bne.s	.file_error
.buffer
	move.l	buffer_end,-$4(a4)              ; buffer end, less one track image for Smart Formatting, -> copy_buffer_end
	move.b	$5a(a2),d0                      ; -> cfg_smart_format
	beq.s	.flags
	move.l	track_image_size,d1
	sub.l	d1,-$4(a4)                      ; -> copy_buffer_end
.flags
	moveq	#1,d0                           ; first pass, first serial number
	move.b	d0,$34(a4)                      ; -> first_pass
	move.b	d0,$35(a4)                      ; -> first_serial
	move.w	src_unit,d1                     ; one drive with extended memory: the image goes to a file on a hard disk
	cmp.w	dst_unit,d1
	bne.s	.no_ext_memory
	move.b	$5b(a2),d2                      ; -> cfg_ext_memory
	bra.s	.set_ext_memory

.no_ext_memory
	clr.b	d2
.set_ext_memory
	move.b	d2,$8(sp)
	tst.b	d2
	beq.w	.start_copy
	moveq	#65,d0                          ; its letter into the messages and into "A:\FCOPYPRO.TMP"
	add.b	$5c(a2),d0                      ; -> cfg_ext_memory_drive
	move.b	d0,-$106(a6)                    ; -> str_a_fcopypro_tmp
	move.b	d0,-$c3(a6)                     ; -> alert_read_write_error_on_the+51
	move.b	d0,-$53(a6)                     ; -> alert_the_disk_image_is_too_big_for+40
	clr.b	$9(sp)
	jsr	image_size(pc)                  ; fits into memory: no extended memory needed
	move.l	d0,d7
	movea.l	-$4(a4),a0                      ; -> copy_buffer_end
	suba.l	(a3),a0
	cmp.l	a0,d7
	ble.s	.in_memory
	clr.w	d0
	move.b	$5c(a2),d0                      ; -> cfg_ext_memory_drive
	addq.w	#1,d0                           ; Dfree of the extended memory partition
	lea	dfree_info,a0
	jsr	Dfree(pc)
	tst.w	d0
	bne.s	.temp_error
	move.l	d7,d0
	jsr	image_fits_partition(pc)
	tst.b	d0
	bne.s	.create_temp
	lea	-$7b(a6),a0                     ; "The Disk Image is too big for Drive X!", -> alert_the_disk_image_is_too_big_for
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#1,d0
	bne.w	.return
.in_memory
	clr.b	$8(sp)
	bra.s	.start_copy

.create_temp
	clr.w	d0                              ; create A:\FCOPYPRO.TMP
	lea	-$106(a6),a0                    ; -> str_a_fcopypro_tmp
	jsr	Fcreate(pc)
	move.w	d0,(a6)
	bge.s	.temp_open
.temp_error
	lea	-$f6(a6),a0                     ; -> alert_read_write_error_on_the
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.temp_open
	move.b	#$1,$36(a4)                     ; -> temp_file_open
.start_copy
	jsr	enable_status_box(pc)           ; NEW DISK and BEST MATCH allowed
	jsr	enable_status_button(pc)
	move.l	(a3),(a4)                       ; buffer empty
	move.w	$a8(sp),d0
	beq.w	.not_converting                 ; New Conf: destination parameters from the dialog
	move.w	$4a(sp),dst_step_rate
	move.b	$4d(sp),dst_hd
	move.b	$27(sp),$64(a2)                 ; -> cfg_used_only
	move.w	$38(sp),dst_sectors
	move.w	$3c(sp),dst_sides
	move.w	$3a(sp),$26(a4)                 ; -> dest_end_track
	lea	bpb,a0                          ; keep the source BPB
	lea	$a(sp),a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.w	(a0)+,(a1)+
	move.w	$16(sp),d1                      ; size of the source system area
	sub.w	$10(sp),d1
	move.w	d1,$44(sp)
	move.w	disk_sectors,$30(a4)            ; -> copies
	moveq	#1,d2                           ; BPB for the new format,
	move.w	d2,-(sp)
	move.w	$3e(sp),d0
	move.w	$26(a4),d1                      ; -> dest_end_track
	move.w	$3a(sp),d2
	jsr	bpb_from_config(pc)
	addq.w	#2,sp
	move.w	$16(sp),bpb+bpb_datrec          ; with at least the source's root directory and FAT sizes
	move.w	bpb+bpb_rdlen,d0
	cmp.w	$10(sp),d0
	bcc.s	.root_size
	move.w	$10(sp),bpb+bpb_rdlen
.root_size
	move.w	bpb+bpb_fsiz,d0
	cmp.w	$12(sp),d0
	bcc.s	.fat_size
	move.w	$12(sp),bpb+bpb_fsiz
.fat_size
	jsr	bpb_align_root(pc)
	move.l	#$200,d0                        ; new boot sector from the source's, with the new values:
	movea.l	buffer_start,a1
	movea.l	(a3),a0
	jsr	memcpy(pc)
	movea.l	(a3),a0
	jsr	is_boot_executable(pc)
	move.b	d0,d3
	move.w	$38(sp),d2
	move.w	$26(a4),d1                      ; -> dest_end_track
	move.w	$3c(sp),d0                      ; media byte (also in the FAT),
	jsr	media_byte(pc)
	movea.l	(a3),a0
	move.b	d0,$15(a0)
	movea.l	fat_buffer,a0
	move.b	d0,(a0)
	move.b	bpb+7,d1                        ; directory entries,
	lsl.b	#4,d1
	movea.l	(a3),a0
	move.b	d1,$11(a0)
	move.w	bpb+bpb_rdlen,d0
	lsl.w	#4,d0
	lsr.w	#8,d0
	movea.l	(a3),a0
	move.b	d0,$12(a0)
	movea.l	(a3),a0                         ; sector count,
	move.b	disk_sectors+1,$13(a0)
	move.w	disk_sectors,d0
	lsr.w	#8,d0
	movea.l	(a3),a0
	move.b	d0,$14(a0)
	movea.l	(a3),a0                         ; FAT size, sectors per track, sides
	move.b	bpb+9,$16(a0)
	movea.l	(a3),a0
	move.b	$39(sp),$18(a0)
	moveq	#1,d0
	add.b	$3d(sp),d0
	movea.l	(a3),a0
	move.b	d0,$1a(a0)
	tst.b	d3                              ; stays executable if it was
	beq.s	.clear_clusters
	movea.l	(a3),a0
	jsr	make_boot_executable(pc)
.clear_clusters
	clr.w	d6                              ; clusters past the new disk size are cleared in the FAT
	bra.s	.cluster_test

.next_cluster
	move.w	d6,d0
	lea	$a(sp),a1
	movea.l	fat_buffer,a0
	jsr	sector_is_bad(pc)
	tst.b	d0
	beq.s	.cluster_advance
	move.w	d6,d0
	lea	$a(sp),a0
	jsr	free_sector_cluster(pc)
.cluster_advance
	addq.w	#1,d6
.cluster_test
	cmp.w	$30(a4),d6                      ; -> copies
	bcs.s	.next_cluster
	clr.b	$35(a4)                         ; -> first_serial
	movea.l	(a3),a5                         ; system sectors of the new format into the buffer:
	lea	$200(a5),a5
	move.w	#$200,d1                        ; FAT 1 (from the source FAT),
	move.w	bpb+bpb_fsiz,d0
	jsr	mul_words(pc)
	move.l	d0,d7
	move.l	d7,d1
	movea.l	a5,a0
	clr.w	d0
	jsr	memset(pc)
	move.l	(a3),d0
	sub.l	fat_buffer,d0
	movea.l	fat_buffer,a1
	movea.l	a5,a0
	jsr	memcpy(pc)
	adda.l	d7,a5
	move.l	d7,d0                           ; FAT 2,
	movea.l	a5,a1
	suba.l	d7,a1
	movea.l	a5,a0
	jsr	memcpy(pc)
	adda.l	d7,a5
	move.w	#$200,d1                        ; root directory
	move.w	bpb+bpb_rdlen,d0
	jsr	mul_words(pc)
	move.l	d0,d1
	clr.w	d0
	movea.l	a5,a0
	jsr	memset(pc)
	cmp.b	#$2,d4                          ; RESTORE: root directory from the image
	bne.s	.root_from_disk
	moveq	#0,d0
	move.w	$10(sp),d0
	moveq	#9,d1
	lsl.l	d1,d0
	move.l	d0,-(sp)
	movea.l	a5,a0
	move.l	d0,d1
	move.w	(a6),d0
	jsr	Fread(pc)
	cmp.l	(sp)+,d0
	bne.w	.file_error
	bra.s	.system_area

.root_from_disk
	move.w	src_unit,-(sp)                  ; else from the source disk
	move.w	$46(sp),d2
	move.w	$12(sp),d1
	movea.l	a5,a0
	clr.w	d0
	jsr	Rwabs(pc)
	addq.w	#2,sp
	tst.l	d0
	beq.s	.system_area
	lea	alert_cannot_access_system_sectors,a0
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.not_converting
	cmp.b	#$2,d4                          ; Copy: RESTORE continues after the header
	bne.s	.end_track
	clr.w	d2
	move.w	(a6),d1
	move.l	(sp),d0
	jsr	Fseek(pc)
.end_track
	move.w	$6c(a2),$26(a4)                 ; -> cfg_end_track, -> dest_end_track
.system_area
	move.w	$a8(sp),d0                      ; New Conf or used sectors only: the new system area replaces the source's
	bne.s	.new_system_area
	move.b	$64(a2),d1                      ; -> cfg_used_only
	beq.s	.no_system_area
	move.b	$63(a2),d2                      ; -> cfg_read_config
	beq.s	.no_system_area
.new_system_area
	move.w	bpb+bpb_fsiz,d0
	add.w	bpb+bpb_fsiz,d0
	add.w	bpb+bpb_rdlen,d0
	addq.w	#1,d0
	move.w	d0,$34(sp)
	sub.w	bpb+bpb_datrec,d0
	move.w	d0,$2a(sp)
	move.w	#$200,d1
	jsr	mul_words(pc)
	add.l	d0,(a4)
	bra.s	.last_sector

.no_system_area
	clr.w	$2a(sp)
.last_sector
	moveq	#1,d3                           ; d3 = last source sector to copy
	add.w	$6c(a2),d3                      ; -> cfg_end_track
	moveq	#1,d0
	add.w	src_sides,d0
	muls.w	d0,d3
	muls.w	src_sectors,d3
	move.b	$63(a2),d1                      ; used sectors only: up to the last used cluster, -> cfg_read_config
	beq.s	.check_size
	move.b	$64(a2),d2                      ; -> cfg_used_only
	beq.s	.check_size
	clr.w	d6
	move.w	d6,d5
	bra.s	.last_test

.find_last_used
	move.w	d6,d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.last_advance
	move.w	d6,d5
.last_advance
	addq.w	#1,d6
.last_test
	cmp.w	d6,d3
	bhi.s	.find_last_used
	moveq	#1,d3
	add.w	d5,d3
.check_size
	move.w	$a8(sp),d0                      ; New Conf: "Destination Disk is too small! Copy as much as possible?"
	beq.s	.copies
	move.w	d3,d1
	add.w	$2a(sp),d1
	cmp.w	disk_sectors,d1
	bls.s	.copies
	lea	alert_destination_disk_is_too_small,a0
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#2,d0
	beq.w	.return
.copies
	move.b	$61(a2),d0                      ; number of copies: 9999 for Multiple Copy, -> cfg_multiple_copy
	beq.s	.one
	move.w	#$270f,d1
	bra.s	.set_copies

.one
	moveq	#1,d1
.set_copies
	move.w	d1,$30(a4)                      ; -> copies
	clr.w	$24(sp)
	move.w	src_sectors,d0                  ; bytes per source track
	move.w	#$200,d1
	jsr	mul_words(pc)
	move.l	d0,$20(sp)
	move.b	$5f(a2),d1                      ; track image when formatting, -> cfg_format_dest
	beq.s	.start_track
	jsr	build_track_image(pc)
.start_track
	move.w	$6a(a2),d0                      ; start at the start track, -> cfg_start_track
	move.w	d0,$32(sp)
	move.w	d0,$42(sp)
	clr.w	$40(sp)
	moveq	#1,d5                           ; first sector in the buffer
	add.w	src_sides,d5
	muls.w	$6a(a2),d5                      ; -> cfg_start_track
	muls.w	src_sectors,d5
	move.w	d5,$24(a4)                      ; -> buffer_first_sector
	cmp.b	#$2,d4                          ; heads to the start track, HD mode
	beq.s	.reading
	move.w	$32(sp),d1
	clr.w	d0
	jsr	restore_drive(pc)
	cmp.b	#$1,d4
	beq.s	.hd_mode
	move.w	$32(sp),d1
	moveq	#1,d0
	jsr	restore_drive(pc)
.hd_mode
	move.b	$50(a2),d0                      ; -> cfg_hd_detect
	beq.s	.reading
	clr.w	d0
	move.b	$6e(a2),d0                      ; -> cfg_hd
	jsr	set_hd_mode(pc)
.reading
	lea	-$128(a6),a0                    ; -> str_reading_2
	jsr	draw_progress_text(pc)
	bra.w	.track_test

.next_track
	clr.w	$30(sp)                         ; read loop over the sides of a track
	bra.w	.side_test

.next_side
	cmp.w	$24(a4),d3                      ; all sectors read: write the rest, -> buffer_first_sector
	bls.w	.all_read
	movea.l	-$4(a4),a0                      ; no room for another track: write phase, -> copy_buffer_end
	suba.l	(a4),a0
	cmpa.l	$20(sp),a0
	bcc.w	.read_part
.write_phase
	cmp.b	#$1,d4                          ; READ: the buffer goes to the image file
	bne.s	.to_temp_file
	lea	str_saving,a0
	jsr	draw_progress_text(pc)
	jsr	unlock_and_vsync(pc)
	movea.l	(a4),a0
	suba.l	(a3),a0
	move.l	a0,-(sp)
	move.l	a0,d1
	move.w	(a6),d0
	movea.l	(a3),a0
	jsr	Fwrite(pc)
	cmp.l	(sp)+,d0
	bne.s	.temp_write_error
	move.w	$24(sp),d0
	bne.w	.finish
	move.l	(a3),(a4)
	lea	-$128(a6),a0                    ; -> str_reading_2
	jsr	draw_progress_text(pc)
	bra.w	.read_part

.to_temp_file
	move.b	$8(sp),d0                       ; extended memory: the buffer goes to the temporary file
	beq.s	.write_disks
	move.b	$9(sp),d1
	bne.s	.save_temp
	move.w	$24(sp),d2
	bne.s	.write_disks
.save_temp
	jsr	unlock_and_vsync(pc)
	movea.l	(a4),a0
	suba.l	(a3),a0
	move.l	a0,-(sp)
	move.l	a0,d1
	move.w	(a6),d0
	movea.l	(a3),a0
	jsr	Fwrite(pc)
	cmp.l	(sp)+,d0                        ; "READ/WRITE ERROR on the Extended Memory"
	beq.s	.temp_written
.temp_write_error
	lea	-$b3(a6),a0                     ; -> alert_read_write_error_on_the_disk
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.finish

.temp_written
	move.w	$24(sp),d0
	bne.s	.temp_full
	move.l	(a3),(a4)
	move.b	#$1,$9(sp)
	bra.w	.read_part

.temp_full
	move.l	#$ffffff00,(a4)
.write_disks
	move.b	$34(a4),d0                      ; write phase: NEW DISK only on the first pass, -> first_pass
	beq.s	.no_new_disk
	jsr	enable_status_button(pc)
	bra.s	.system_start

.no_new_disk
	jsr	disable_status_button(pc)
.system_start
	move.w	bpb+bpb_datrec,$16(sp)          ; the destination system area starts at the new data start
	move.w	$34(sp),bpb+bpb_datrec
	move.b	$50(a2),d0                      ; -> cfg_hd_detect
	beq.s	.first_copy
	clr.w	d0
	move.b	dst_hd,d0
	jsr	set_hd_mode(pc)
.first_copy
	clr.w	$32(a4)                         ; copy number 0, -> copy_count
	bra.w	.copy_test

.next_copy
	move.b	$61(a2),d0                      ; one copy, -> cfg_multiple_copy
	bne.s	.smart_format
	move.b	$34(a4),d1                      ; -> first_pass
	beq.s	.text
.smart_format
	move.b	$5a(a2),d0                      ; Smart Formatting: write without formatting first, -> cfg_smart_format
	beq.s	.text
	clr.b	$5f(a2)                         ; -> cfg_format_dest
	clr.l	fdc_state+fs_order_ptr
.text
	move.b	$5f(a2),d0                      ; -> cfg_format_dest
	beq.s	.text_writing
	lea	-$118(a6),a0                    ; -> str_format_writing
	bra.s	.show_text

.text_writing
	lea	-$120(a6),a0                    ; -> str_writing_2
.show_text
	jsr	draw_progress_text(pc)
	move.b	$8(sp),d0                       ; extended memory: the first part of the image from the temporary file
	beq.s	.serial
	move.b	$9(sp),d1
	beq.s	.serial
	jsr	unlock_and_vsync(pc)
	clr.w	d2
	move.w	(a6),d1
	moveq	#0,d0
	jsr	Fseek(pc)
	tst.l	d0
	bne.w	.temp_read_error
	movea.l	(a3),a0
	move.l	-$4(a4),d1                      ; -> copy_buffer_end
	sub.l	(a3),d1
	move.w	(a6),d0
	jsr	Fread(pc)
	tst.l	d0
	blt.w	.temp_read_error
.serial
	jsr	randomize_serial(pc)            ; new serial number in the boot sector of each copy
	move.w	src_unit,d0
	cmp.w	dst_unit,d0
	bne.s	.ask_dest
	move.w	$42(sp),d1                      ; destination head to the first track of this part
	moveq	#1,d0
	jsr	seek_track(pc)
.ask_dest
	cmpi.w	#$1,$30(a4)                     ; one copy: ask for the destination disk, -> copies
	bne.s	.ask_numbered
	move.w	src_unit,d0                     ; one drive: "X: Destination Disk [COPY|ABORT]"
	cmp.w	dst_unit,d0
	bne.s	.restore_first
	lea	-$273(a6),a0                    ; -> alert_x_destination_disk_copy_abort
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#2,d0
	beq.w	.finish
	bra.w	.new_map

.restore_first
	move.b	$34(a4),d0                      ; first pass of RESTORE: ask (request boxes), -> first_pass
	beq.w	.new_map
	cmp.b	#$2,d4
	bne.w	.new_map
	lea	-$273(a6),a0                    ; -> alert_x_destination_disk_copy_abort
	moveq	#1,d0
	jsr	request_alert(pc)
	subq.w	#2,d0
	beq.w	.finish
	bra.w	.new_map

.ask_numbered
	lea	-$20a(a6),a1                    ; more copies: "X: Destination Disk #n [COPY|ABORT|LAST]", -> alert_x_destination_disk_2
	lea	$58(sp),a0
	jsr	strcpy(pc)
	moveq	#10,d1
	lea	$4e(sp),a0
	moveq	#1,d0
	add.w	$32(a4),d0                      ; -> copy_count
	jsr	itoa(pc)
	lea	$4e(sp),a1
	lea	$58(sp),a0
	jsr	strcat(pc)
	cmpi.w	#$270f,$30(a4)                  ; -> copies
	bne.s	.ask_single
	move.w	$32(a4),d0                      ; -> copy_count
	beq.s	.first_numbered
	lea	-$1d7(a6),a1                    ; -> str_copy_abort_last
	bra.s	.ask_copy

.first_numbered
	lea	-$1ee(a6),a1                    ; -> str_copy_abort
.ask_copy
	lea	$58(sp),a0
	jsr	strcat(pc)
	lea	$58(sp),a0
	moveq	#1,d0
	jsr	alert(pc)
	move.w	d0,$26(sp)
	subq.w	#3,d0
	bne.s	.not_last
	move.w	$32(a4),$30(a4)                 ; LAST: this is the last copy, -> copy_count, -> copies
	bra.w	.part_done

.not_last
	cmpi.w	#$2,$26(sp)
	beq.w	.finish
	bra.s	.new_map

.ask_single
	lea	-$1ee(a6),a1                    ; -> str_copy_abort
	lea	$58(sp),a0
	jsr	strcat(pc)
	lea	$58(sp),a0
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#2,d0
	beq.w	.finish
.new_map
	move.w	$32(a4),d0                      ; from the second copy on: new track map, -> copy_count
	beq.s	.write_part
	jsr	draw_progress_frame(pc)
.write_part
	move.w	$42(sp),$2e(sp)                 ; write from the first track and side of this part
	move.w	$40(sp),$2c(sp)
	moveq	#0,d0                           ; part of a track already written in the last round
	move.w	d5,d0
	divu.w	dst_sectors,d0
	swap	d0
	move.w	d0,$36(sp)
	move.w	d5,d1
	sub.w	d0,d1
	move.w	d1,$3e(sp)
	move.l	(a3),$4(a4)                     ; write pointer to the start of the buffer, -> copy_write_ptr
	tst.w	d0
	beq.s	.track_list
	move.w	$2e(sp),d2                      ; sector list of the rest of that track
	moveq	#1,d0
	move.w	$2c(sp),d1
	jsr	build_track_sector_list(pc)
	bra.w	.write_track

.next_write_track
	clr.w	$36(sp)                         ; write loop: next track
	move.w	dst_sectors,d0
	add.w	d0,$3e(sp)
	move.w	$24(a4),d1                      ; all sectors of this part written, -> buffer_first_sector
	add.w	$2a(sp),d1
	move.w	$3e(sp),d2
	cmp.w	d1,d2
	bhi.w	.format_rest
	addq.w	#1,$2c(sp)
	movea.w	$2c(sp),a0
	cmpa.w	dst_sides,a0
	ble.s	.track_list
	clr.w	$2c(sp)
	addq.w	#1,$2e(sp)
.track_list
	move.w	$24(a4),d0                      ; sector list of the track (used sectors only), -> buffer_first_sector
	add.w	$2a(sp),d0
	move.w	$3e(sp),d1
	cmp.w	d0,d1
	beq.w	.format_rest
	move.w	$2e(sp),d2
	cmp.w	$26(a4),d2                      ; -> dest_end_track
	bhi.w	.format_rest
	moveq	#1,d0
	move.w	$2c(sp),d1
	jsr	build_track_sector_list(pc)
.format_track
	move.b	$5f(a2),d0                      ; Format Destination: format the track first, -> cfg_format_dest
	beq.s	.write_track
	move.w	$2e(sp),d1
	moveq	#1,d0
	jsr	seek_track(pc)
	move.w	$2e(sp),d1
	move.w	$2c(sp),d0
	jsr	format_track(pc)
	move.w	d0,$28(sp)
	jsr	order_sector_list(pc)
	move.w	$28(sp),d0
	bne.s	.format_error
	move.w	$28(a4),d1                      ; -> list_sectors
	bne.s	.write_track
.format_error
	move.w	$28(sp),-(sp)                   ; format errors: ABORT, RETRY, NEW DISK
	move.w	$30(sp),-(sp)
	move.w	$30(sp),d2
	moveq	#1,d1
	clr.w	d0
	jsr	show_track_result(pc)
	addq.w	#4,sp
	move.w	d0,$26(sp)
	subq.w	#1,d0
	beq.w	.finish
	subq.w	#1,d0
	beq.s	.format_track
	subq.w	#3,d0
	beq.w	.next_copy
.write_track
	move.w	$36(sp),-(sp)                   ; write the sectors of the track
	moveq	#1,d2
	move.w	$30(sp),d1
	move.w	$2e(sp),d0
	jsr	write_track_sectors(pc)
	addq.w	#2,sp
	move.w	d0,$28(sp)
	tst.w	d0
	blt.w	.next_write_track
	move.w	d0,-(sp)                        ; show the result (3 = writing)
	move.w	$30(sp),-(sp)
	move.w	$30(sp),d2
	moveq	#1,d1
	moveq	#3,d0
	jsr	show_track_result(pc)
	addq.w	#4,sp
	subq.w	#1,d0
	beq.w	.finish
	subq.w	#1,d0
	beq.s	.retry
	subq.w	#1,d0
	beq.s	.best_match
	subq.w	#2,d0
	beq.w	.next_copy
	bra.s	.advance

.retry
	move.w	$36(sp),d0                      ; RETRY: format again unless only part of the track was written
	beq.w	.format_track
	bra.s	.write_track

.best_match
	move.w	$36(sp),-(sp)                   ; BEST MATCH: write again ignoring errors
	clr.w	d2
	move.w	$30(sp),d1
	move.w	$2e(sp),d0
	jsr	write_track_sectors(pc)
	addq.w	#2,sp
.advance
	move.w	#$200,d1                        ; advance the write pointer by the sectors written
	move.w	$2a(a4),d0                      ; -> sectors_written
	jsr	mul_words(pc)
	add.l	d0,$4(a4)                       ; -> copy_write_ptr
	move.b	$8(sp),d0                       ; extended memory: reload the buffer from the temporary file when it runs out
	beq.w	.next_write_track
	move.b	$9(sp),d1
	beq.w	.next_write_track
	move.w	dst_sectors,d0
	move.w	#$200,d1
	jsr	mul_words(pc)
	movea.l	$4(a4),a0                       ; -> copy_write_ptr
	adda.l	d0,a0
	cmpa.l	-$4(a4),a0                      ; -> copy_buffer_end
	bcs.w	.next_write_track
	move.l	-$4(a4),d7                      ; -> copy_buffer_end
	sub.l	$4(a4),d7                       ; -> copy_write_ptr
	move.l	d7,d0
	movea.l	$4(a4),a1                       ; -> copy_write_ptr
	movea.l	(a3),a0
	jsr	memcpy(pc)
	jsr	unlock_and_vsync(pc)
	movea.l	(a3),a0
	adda.l	d7,a0
	move.l	$4(a4),d1                       ; -> copy_write_ptr
	sub.l	(a3),d1
	move.w	(a6),d0
	jsr	Fread(pc)
	tst.l	d0
	bge.s	.reloaded
.temp_read_error
	lea	-$f6(a6),a0                     ; -> alert_read_write_error_on_the
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.finish

.reloaded
	move.l	(a3),$4(a4)                     ; -> copy_write_ptr
	bra.w	.next_write_track

.format_rest
	move.w	$24(sp),d0                      ; last part, formatting: format the remaining tracks of the destination
	beq.w	.copy_done
	move.b	$5f(a2),d1                      ; -> cfg_format_dest
	beq.w	.copy_done
	jsr	disable_status_box(pc)
	jsr	disable_status_button(pc)
	move.w	$24(a4),d0                      ; -> buffer_first_sector
	add.w	$2a(sp),d0
	moveq	#0,d1
	move.w	d0,d1
	divu.w	dst_sectors,d1
	swap	d1
	tst.w	d1
	beq.s	.rest_track
	bra.s	.rest_test

.rest_next_side
	addq.w	#1,$2c(sp)
	move.w	$2c(sp),d0
	cmp.w	dst_sides,d0
	ble.s	.rest_track
	clr.w	$2c(sp)
	addq.w	#1,$2e(sp)
.rest_track
	move.w	$2e(sp),d0
	cmp.w	$26(a4),d0                      ; -> dest_end_track
	bhi.s	.copy_done
	move.w	d0,d1
	moveq	#1,d0
	jsr	seek_track(pc)
	move.w	$2e(sp),d1
	move.w	$2c(sp),d0
	jsr	format_track(pc)
	move.w	d0,$28(sp)
	move.w	d0,-(sp)
	move.w	$30(sp),-(sp)
	move.w	$30(sp),d2
	moveq	#1,d1
	clr.w	d0
	jsr	show_track_result(pc)
	addq.w	#4,sp
	subq.w	#1,d0
	beq.w	.finish
	subq.w	#1,d0
	beq.s	.rest_track
.rest_test
	move.b	$5f(a2),d0                      ; -> cfg_format_dest
	bne.s	.rest_next_side
.copy_done
	addq.w	#1,$32(a4)                      ; next copy, -> copy_count
.copy_test
	move.w	$32(a4),d0                      ; -> copy_count
	cmp.w	$30(a4),d0                      ; -> copies
	bcs.w	.next_copy
.part_done
	clr.b	$34(a4)                         ; all copies of this part done, -> first_pass
	move.w	$24(sp),d0                      ; everything copied: finished
	bne.w	.finish
	move.w	$2e(sp),d1
	cmp.w	$26(a4),d1                      ; -> dest_end_track
	bhi.w	.finish
	move.w	d1,$42(sp)                      ; the next part starts here
	move.w	$2c(sp),$40(sp)
	move.w	$24(a4),d5                      ; -> buffer_first_sector
	add.w	$2a(sp),d5
	lea	-$128(a6),a0                    ; -> str_reading_2
	jsr	draw_progress_text(pc)
	cmp.b	#$2,d4                          ; one drive: "X: Source Disk [COPY|ABORT]" again
	beq.s	.read_on
	move.w	src_unit,d0
	cmp.w	dst_unit,d0
	bne.s	.read_on
	move.w	$32(sp),d1
	clr.w	d0
	jsr	seek_track(pc)
	lea	-$29a(a6),a0                    ; -> alert_x_source_disk_copy_abort
	moveq	#1,d0
	jsr	alert(pc)
	subq.w	#2,d0
	beq.w	.finish
.read_on
	move.w	$16(sp),bpb+bpb_datrec          ; buffer empty, source HD mode
	move.l	(a3),(a4)
	jsr	enable_status_button(pc)
	cmp.b	#$2,d4
	beq.s	.read_part
	move.b	$50(a2),d0                      ; -> cfg_hd_detect
	beq.s	.read_part
	clr.w	d0
	move.b	$6e(a2),d0                      ; -> cfg_hd
	jsr	set_hd_mode(pc)
.read_part
	cmp.b	#$2,d4                          ; RESTORE: read the next part of the image file
	bne.w	.read_disk
	move.w	$2c(a4),d0                      ; New Conf: skip the source system area in the image, -> convert
	beq.s	.fit
	move.w	$24(a4),d1                      ; -> buffer_first_sector
	cmp.w	bpb+bpb_datrec,d1
	bcc.s	.fit
	move.w	bpb+bpb_datrec,d0
	sub.w	d1,d0
	move.w	#$200,d1
	jsr	mul_words(pc)
	add.l	d0,(a4)
	move.w	bpb+bpb_datrec,$24(a4)          ; -> buffer_first_sector
.fit
	move.l	-$4(a4),d0                      ; as many sectors as fit, -> copy_buffer_end
	sub.l	(a4),d0
	move.l	#$200,d1
	jsr	ldiv(pc)
	move.l	d0,$1c(sp)
	move.b	$63(a2),d1                      ; used sectors only: as many used clusters, -> cfg_read_config
	beq.s	.all_sectors
	move.b	$64(a2),d2                      ; -> cfg_used_only
	beq.s	.all_sectors
	clr.w	$4(sp)
	move.w	$24(a4),d6                      ; -> buffer_first_sector
	bra.s	.count_test

.count_used
	move.w	d6,d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.next_cluster2
	addq.w	#1,$4(sp)
.next_cluster2
	addq.w	#1,d6
.count_test
	move.w	$4(sp),d0
	cmp.w	$1e(sp),d0
	bcc.s	.used_done
	cmp.w	d6,d3
	bhi.s	.count_used
.used_done
	move.w	d6,$24(a4)                      ; -> buffer_first_sector
	moveq	#0,d0
	move.w	$4(sp),d0
	move.l	d0,$1c(sp)
	bra.s	.read_file

.all_sectors
	moveq	#0,d0
	move.w	$24(a4),d0                      ; -> buffer_first_sector
	add.l	$1c(sp),d0
	moveq	#0,d1
	move.w	d3,d1
	cmp.l	d1,d0
	bcs.s	.advance_first
	move.w	d3,d2
	sub.w	$24(a4),d2                      ; -> buffer_first_sector
	moveq	#0,d0
	move.w	d2,d0
	move.l	d0,$1c(sp)
.advance_first
	move.w	$1e(sp),d0
	add.w	d0,$24(a4)                      ; -> buffer_first_sector
.read_file
	move.l	$1c(sp),d0
	moveq	#9,d1
	lsl.l	d1,d0
	move.l	d0,$1c(sp)
	jsr	unlock_and_vsync(pc)            ; read them
	movea.l	(a4),a0
	move.l	$1c(sp),d1
	move.w	(a6),d0
	jsr	Fread(pc)
	tst.l	d0
	blt.w	.temp_write_error
	move.l	$1c(sp),d0
	add.l	d0,(a4)
	movea.l	(a4),a0
	clr.b	d0
	jsr	draw_memory_bar(pc)
	bra.w	.next_side

.read_disk
	move.w	$32(sp),d2                      ; disk source: sector list of the track
	move.w	$30(sp),d1
	clr.w	d0
	jsr	build_track_sector_list(pc)
.read_track
	moveq	#1,d2                           ; read the track
	move.w	$32(sp),d1
	move.w	$30(sp),d0
	movea.l	(a4),a0
	jsr	read_track_sectors(pc)
	move.w	d0,$28(sp)
	tst.w	d0
	blt.w	.track_done
	move.w	#$200,d1
	move.w	$28(a4),d0                      ; -> list_sectors
	jsr	mul_words(pc)
	move.l	d0,$1c(sp)
	add.l	d0,(a4)
	move.w	$28(sp),-(sp)                   ; show the result (4 = reading)
	move.w	$34(sp),-(sp)
	move.w	$34(sp),d2
	clr.w	d1
	moveq	#4,d0
	jsr	show_track_result(pc)
	addq.w	#4,sp
	move.w	d0,$28(sp)
	move.l	$1c(sp),d1
	sub.l	d1,(a4)
	subq.w	#1,d0
	beq.w	.finish
	subq.w	#1,d0
	beq.s	.read_track
	subq.w	#1,d0
	beq.s	.best_match_read
	subq.w	#2,d0
	beq.s	.new_disk
	bra.s	.keep_track

.best_match_read
	clr.w	d2                              ; BEST MATCH: read again ignoring errors
	move.w	$32(sp),d1
	move.w	$30(sp),d0
	movea.l	(a4),a0
	jsr	read_track_sectors(pc)
	bra.s	.keep_track

.new_disk
	clr.w	d1                              ; NEW DISK: start again
	clr.w	d0
	jsr	restore_drive(pc)
	cmp.b	#$1,d4
	beq.s	.restart_copy
	clr.w	d1
	moveq	#1,d0
	jsr	restore_drive(pc)
.restart_copy
	jsr	unlock_floppy(pc)
	bra.w	.restart

.keep_track
	move.l	$1c(sp),d0                      ; keep the track in the buffer
	add.l	d0,(a4)
	movea.l	(a4),a0
	moveq	#1,d0
	jsr	draw_memory_bar(pc)
.track_done
	addq.w	#1,$30(sp)                      ; next side, next track
	move.w	src_sectors,d0
	add.w	d0,$24(a4)                      ; -> buffer_first_sector
.side_test
	move.w	$30(sp),d0
	cmp.w	src_sides,d0
	ble.w	.next_side
	addq.w	#1,$32(sp)
.track_test
	move.w	$32(sp),d0
	cmp.w	$6c(a2),d0                      ; -> cfg_end_track
	ble.w	.next_track
.all_read
	move.w	#$1,$24(sp)                     ; all read: last write phase
	move.w	d3,$24(a4)                      ; -> buffer_first_sector
	bra.w	.write_phase

.finish
	cmp.b	#$2,d4                          ; heads to track 0
	beq.s	.restore_destination
	clr.w	d1
	clr.w	d0
	jsr	restore_drive(pc)
.restore_destination
	cmp.b	#$1,d4
	beq.s	.unlock
	clr.w	d1
	moveq	#1,d0
	jsr	restore_drive(pc)
.unlock
	jsr	unlock_floppy(pc)
.return
	lea	$aa(sp),sp
	movem.l	(sp)+,d3-d7/a2-a6
	rts


read_track_sectors:
	movem.l	d3-d6/a2-a3,-(sp)               ; d0 side, d1 track, d2 stop at errors, a0 buffer (0: buffer_start)
	move.w	d0,d6
	move.w	d1,d3
	move.w	d2,d5
	move.w	list_sectors,d2                 ; no sectors listed: nothing to read
	bne.s	.seek
	moveq	#-1,d0
	bra.s	.return

.seek
	lea	sector_list,a2
	movea.l	a0,a3
	move.w	d3,d1
	clr.w	d0
	jsr	seek_track(pc)
	bra.s	.sector_test

.next_sector
	clr.w	d3                              ; each listed sector
	move.b	(a2)+,d3
	move.w	convert,d0                      ; New Conf: sectors of the source system area are not read
	beq.s	.read
	move.w	buffer_first_sector,d1
	add.w	d3,d1
	subq.w	#1,d1
	cmp.w	bpb+bpb_datrec,d1
	bcc.s	.read
	clr.w	d4
	bra.s	.advance

.read
	move.b	d5,-(sp)
	move.l	a3,d0
	beq.s	.to_buffer_start
	movea.l	a3,a0
	bra.s	.read_sector

.to_buffer_start
	movea.l	buffer_start,a0
.read_sector
	move.w	d3,d2
	move.w	d6,d1
	clr.w	d0
	jsr	read_sectors(pc)                ; one sector
	addq.w	#2,sp
	move.w	d0,d4
	tst.w	d0
	beq.s	.advance
	tst.w	d5                              ; with d5 set an error stops the track
	bne.s	.done
.advance
	move.l	a3,d0
	beq.s	.sector_test
	lea	$200(a3),a3
.sector_test
	move.b	(a2),d0
	bne.s	.next_sector
.done
	move.w	d4,d0
.return
	movem.l	(sp)+,d3-d6/a2-a3
	rts


write_track_sectors:
	movem.l	d3-d7/a2-a6,-(sp)               ; d0 track, d1 side, d2 stop at errors; first sector to write on the stack
	lea	-$1a(sp),sp
	move.w	d0,$18(sp)
	move.w	d1,d5
	move.w	d2,d7
	lea	sector_list,a2
	clr.w	$22(a2)                         ; sectors written, -> sectors_written
	move.w	$20(a2),d0                      ; -> list_sectors
	bne.s	.order_list
	moveq	#-1,d0
	bra.w	.return

.order_list
	moveq	#22,d1                          ; order the listed sectors by sector number
	clr.w	d0
	lea	(sp),a0
	jsr	memset(pc)
	moveq	#1,d3
	add.w	$46(sp),d3
	bra.s	.number_test

.next_number
	movea.l	a2,a3
	lea	(sp),a4
	bra.s	.scan_list

.find_number
	cmp.w	d4,d3
	bne.s	.not_listed
	addq.w	#1,$22(a2)                      ; -> sectors_written
	move.w	$22(a2),d0                      ; -> sectors_written
	move.b	d0,(a4)
	bra.s	.number_done

.not_listed
	addq.w	#1,a4
.scan_list
	clr.w	d4
	move.b	(a3)+,d4
	bne.s	.find_number
.number_done
	addq.w	#1,d3
.number_test
	cmp.w	dst_sectors,d3
	bls.s	.next_number
	movea.l	a2,a3
	lea	(sp),a4
	clr.w	d4
	move.w	d5,d1                           ; destination head to the track
	moveq	#1,d0
	jsr	seek_track(pc)
	lea	written_sectors,a6
	bra.s	.sector_test

.next_sector
	clr.w	d5                              ; write each sector that is in the buffer
	move.b	(a4)+,d5
	beq.s	.not_in_buffer
	move.w	#$200,d1
	moveq	#-1,d0
	add.w	d5,d0
	jsr	mul_words(pc)
	movea.l	-$4(a2),a5                      ; -> copy_write_ptr
	adda.l	d0,a5
	cmpa.l	copy_buffer,a5
	bcs.s	.not_in_buffer
	cmpa.l	-$8(a2),a5                      ; -> copy_read_ptr
	bcs.s	.write
.not_in_buffer
	clr.w	d6
	bra.s	.sector_test

.write
	moveq	#6,d0                           ; and record sector and address for the verify
	muls.w	d4,d0
	move.w	d3,$0(a6,d0.w)                  ; -> written_sectors indexed
	move.w	d4,d1
	muls.w	#$6,d1
	move.l	a5,$2(a6,d1.w)                  ; -> written_sectors+2 indexed
	addq.w	#1,d4
	move.b	d7,-(sp)
	movea.l	a5,a0
	move.w	d3,d2
	move.w	$1a(sp),d1
	moveq	#1,d0
	jsr	write_sectors(pc)
	addq.w	#2,sp
	move.w	d0,d6
	tst.w	d0
	beq.s	.sector_test
	tst.w	d7                              ; with d7 set an error stops the track
	bne.s	.end_list
.sector_test
	clr.w	d3
	move.b	(a3)+,d3
	bne.s	.next_sector
.end_list
	moveq	#6,d0
	muls.w	d4,d0
	clr.w	$0(a6,d0.w)                     ; -> written_sectors indexed
	move.w	d6,d0
.return
	lea	$1a(sp),sp
	movem.l	(sp)+,d3-d7/a2-a6
	rts


order_sector_list:
	move.l	a2,-(sp)                        ; sector_list into the order the sectors were formatted (fs_order_ptr)
	move.l	a3,-(sp)
	lea	-$1c(sp),sp
	move.l	fdc_state+fs_order_ptr,d0
	beq.w	.return
	move.w	dst_sectors,d1                  ; only for the track layouts with their own order
	dc.w	$927c,$a                        ; sub.w #$a,d1
	cmp.w	#$a,d1
	bhi.w	.return
	add.w	d1,d1
	move.w	.table(pc,d1.w),d1
	jmp	.table(pc,d1.w)

.table
	dc.w	.reorder-.table,.return-.table,.return-.table,.return-.table
	dc.w	.return-.table,.reorder-.table,.reorder-.table,.return-.table
	dc.w	.hd_18-.table,.reorder-.table,.reorder-.table
.hd_18
	cmpi.b	#$1,drive_density
	beq.s	.return
.reorder
	move.w	dst_sectors,d1                  ; position of each listed sector in the order table
	ext.l	d1
	addq.l	#1,d1
	clr.w	d0
	lea	(sp),a0
	jsr	memset(pc)
	lea	sector_list,a0
	movea.l	a0,a1
	lea	(sp),a2
	bra.s	.listed_test

.next_listed
	clr.b	d0
	bra.s	.find_position

.next_position
	addq.b	#1,d0
.find_position
	clr.w	d2
	move.b	d0,d2
	movea.l	fdc_state+fs_order_ptr,a3
	cmp.b	$0(a3,d2.w),d1
	bne.s	.next_position
	move.b	d1,$0(a2,d2.w)
.listed_test
	move.b	(a1)+,d1
	bne.s	.next_listed
	movea.l	a0,a1                           ; listed sectors in that order back into sector_list
	clr.b	d1
	bra.s	.slot_test

.copy_back
	move.b	(a2),d0
	beq.s	.next_slot
	move.b	d0,(a1)+
.next_slot
	addq.w	#1,a2
	addq.b	#1,d1
.slot_test
	clr.w	d0
	move.b	d1,d0
	cmp.w	dst_sectors,d0
	blt.s	.copy_back
.return
	lea	$1c(sp),sp
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


close_image_file:
	move.l	a2,-(sp)
	lea	image_handle,a2
	move.w	(a2),d0
	ble.s	.finish
	jsr	unlock_and_vsync(pc)
	move.w	(a2),d0
	jsr	Fclose(pc)
	move.b	temp_file_open,d0
	beq.s	.set_temp_file_open
	lea	-$106(a2),a0                    ; -> str_a_fcopypro_tmp
	jsr	Fdelete(pc)
.set_temp_file_open
	clr.b	temp_file_open
	move.w	#$ffff,(a2)
.finish
	movea.l	(sp)+,a2
	rts


image_size:
	move.l	d3,-(sp)                        ; bytes of the copied sectors plus 8KB
	move.w	d4,-(sp)
	lea	config,a0
	move.b	$63(a0),d0                      ; configuration not read: tracks of the dialog, -> cfg_read_config
	bne.s	.configuration_read
	moveq	#1,d3
	add.w	src_sides,d3
	muls.w	src_sectors,d3
	move.w	$6c(a0),d1                      ; -> cfg_end_track
	sub.w	$6a(a0),d1                      ; -> cfg_start_track
	addq.w	#1,d1
	muls.w	d1,d3
	ext.l	d3
	bra.s	.bytes

.configuration_read
	move.b	$64(a0),d0                      ; all sectors of the disk, -> cfg_used_only
	bne.s	.count_used
	moveq	#0,d3
	move.w	disk_sectors,d3
	bra.s	.bytes

.count_used
	clr.w	d4                              ; or the used ones
	moveq	#0,d3
	move.w	d4,d3
	bra.s	.sector_test

.next_sector
	move.w	d4,d0
	jsr	sector_is_used(pc)
	tst.w	d0
	beq.s	.advance
	addq.l	#1,d3
.advance
	addq.w	#1,d4
.sector_test
	cmp.w	disk_sectors,d4
	bcs.s	.next_sector
.bytes
	move.w	#$200,d1
	move.w	d3,d0
	jsr	mul_words(pc)
	move.l	d0,d3
	dc.w	$d0bc                           ; add.l #$2000,d0
	dc.l	$2000
	move.w	(sp)+,d4
	move.l	(sp)+,d3
	rts


image_fits_partition:
	move.l	d3,-(sp)                        ; d0 bytes plus two clusters fit into the free space of dfree_info?
	move.l	a2,-(sp)
	move.l	d0,d3
	lea	dfree_info,a2
	move.l	$c(a2),d0                       ; -> dfree_info+b_clsiz
	add.l	d0,d0
	move.l	$8(a2),d1                       ; -> dfree_info+b_secsiz
	jsr	lmul(pc)
	add.l	d0,d3
	move.l	(a2),d0
	move.l	$8(a2),d1                       ; -> dfree_info+b_secsiz
	jsr	lmul(pc)
	move.l	$c(a2),d1                       ; -> dfree_info+b_clsiz
	jsr	lmul(pc)
	cmp.l	d0,d3
	bhi.s	.too_big
	moveq	#1,d0
	bra.s	.return

.too_big
	clr.w	d0
.return
	movea.l	(sp)+,a2
	move.l	(sp)+,d3
	rts


randomize_serial:
	movem.l	d3-d4/a2-a5,-(sp)               ; each copy: new serial number in the boot sector, checksum kept
	move.b	cfg_read_config,d0
	beq.w	.return
	move.b	first_pass,d1
	beq.w	.return
	lea	copy_buffer,a2                  ; sum of the serial words before
	movea.l	(a2),a0
	move.w	$8(a0),d3
	add.w	$a(a0),d3
	move.b	$b(a0),d4
	jsr	Random(pc)                      ; Random, high 24 bits as serial
	lsl.l	#8,d0
	movea.l	(a2),a0
	move.l	d0,$8(a0)
	movea.l	(a2),a0
	move.b	d4,$b(a0)
	movea.l	(a2),a0                         ; the last word keeps the boot sector sum
	move.w	$8(a0),d0
	add.w	$a(a0),d0
	sub.w	d3,d0
	sub.w	d0,$1fe(a0)
	move.b	first_serial,d0                 ; first copy: the bad clusters of the source are freed in both FATs of the copy
	beq.s	.done
	lea	bpb,a3
	move.w	#$200,d1
	move.w	$8(a3),d0                       ; -> bpb+bpb_fsiz
	add.w	d0,d0
	addq.w	#1,d0
	jsr	mul_words(pc)
	movea.l	(a2),a0
	adda.l	d0,a0
	cmpa.l	copy_read_ptr,a0
	bcc.s	.done
	lea	fat_buffer,a4
	movea.l	(a4),a5
	clr.w	d4
	bra.s	.sector_test

.next_sector
	move.w	d4,d0
	movea.l	a3,a1
	movea.l	a5,a0
	jsr	sector_is_bad(pc)
	tst.b	d0
	beq.s	.advance
	movea.l	(a2),a0
	lea	$200(a0),a0
	move.l	a0,(a4)
	move.w	d4,d0
	movea.l	a3,a0
	jsr	free_sector_cluster(pc)
	move.w	#$200,d1
	moveq	#1,d0
	add.w	$8(a3),d0                       ; -> bpb+bpb_fsiz
	jsr	mul_words(pc)
	movea.l	(a2),a0
	adda.l	d0,a0
	move.l	a0,(a4)
	move.w	d4,d0
	movea.l	a3,a0
	jsr	free_sector_cluster(pc)
.advance
	addq.w	#1,d4
.sector_test
	cmp.w	disk_sectors,d4
	bcs.s	.next_sector
	move.l	a5,(a4)
.done
	clr.b	first_serial
.return
	movem.l	(sp)+,d3-d4/a2-a5
	rts


unlock_and_vsync:
	jsr	unlock_floppy(pc)
	jsr	Vsync(pc)
	rts


;----------------------------------------------------------------------
; main: Line-A, screen check, mouse accelerator, then as a program run FastCopy
; once and quit, as an accessory register "  FastCopy PRO" and wait for AC_OPEN.
;----------------------------------------------------------------------
main:
	movem.l	d3-d4/a2-a4,-(sp)
	lea	-$10(sp),sp
	jsr	check_machine(pc)               ; TOS version and cookies
	jsr	appl_init(pc)
	move.w	d0,d3
	jsr	linea_init(pc)                  ; Line-A
	lea	unsupported_res,a2              ; screen check: at least 640 pixels wide
	movea.l	linea_vars,a0
	move.w	(a0),$6(a2)                     ; -> screen_planes
	move.w	#$1,(a2)
	lea	linea_base,a0
	movea.l	(a0),a1
	cmpi.w	#$280,$382(a1)                  ; 400 lines: high resolution
	blt.s	.check_resolution
	cmpi.w	#$190,$38a(a1)
	blt.s	.medium_res
	clr.w	d0
	move.w	d0,(a2)
	move.b	d0,$8(a2)                       ; -> medium_res
	bra.s	.check_resolution

.medium_res
	movea.l	(a0),a1                         ; 200 lines: medium resolution
	cmpi.w	#$c8,$38a(a1)
	blt.s	.check_resolution
	move.b	#$1,$8(a2)                      ; -> medium_res
	clr.w	(a2)
.check_resolution
	lea	alert_fastcopy_pro_does_not_support,a3 ; unsupported resolution: only an error when run as a program
	move.w	(a2),d0
	beq.s	.small_font
	move.w	is_program,d1
	beq.s	.small_font
	movea.l	a3,a0
	moveq	#1,d0
	jsr	form_alert(pc)
	jsr	quit(pc)
.small_font
	move.b	$8(a2),d0                       ; system font of the resolution, -> medium_res
	beq.s	.large_font
	moveq	#1,d1
	bra.s	.set_font

.large_font
	moveq	#2,d1
.set_font
	ext.l	d1
	lsl.l	#2,d1
	movea.l	linea_fonts,a0
	move.l	$0(a0,d1.l),$50(a2)             ; -> small_font
	jsr	set_keyclick(pc)                ; keyclick and bell
	jsr	low_memory_free(pc)             ; mouse accelerator only if $600 is free
	tst.b	d0
	bne.s	.mouse_accel
	move.b	$312(a3),d0                     ; -> cfg_mouse_accel
	beq.s	.no_mouse_accel
	lea	alert_cannot_install_the_mouse,a0 ; "Cannot install the Mouse Accelerator!"
	moveq	#1,d0
	jsr	alert(pc)
.no_mouse_accel
	clr.b	d0                              ; option off and disabled in the options dialog
	move.b	d0,$312(a3)                     ; -> cfg_mouse_accel
	move.b	d0,$2ae(a3)                     ; -> mouse_accel_ok
	moveq	#8,d1
	move.w	d1,options_tree+21*OBJECT_SIZE+ob_state
	move.w	d1,options_tree+22*OBJECT_SIZE+ob_state
	bra.s	.step_rates

.mouse_accel
	jsr	set_mouse_accel(pc)
.step_rates
	jsr	set_step_rates(pc)              ; step rates of drive A and B
	jsr	Dgetdrv(pc)                     ; partition for images and the streamer: the current drive, at least C
	move.w	d0,image_drive
	move.w	d0,partition_drive
	subq.w	#2,d0
	bge.s	.accessory_or_program
	moveq	#2,d0
	move.w	d0,image_drive
	move.w	d0,partition_drive
.accessory_or_program
	move.w	is_program,d0                   ; accessory: register in the Desk menu
	bne.w	.program
	lea	-$cf(a2),a0                     ; -> start_path
	clr.w	d0
	jsr	Dgetpath(pc)
	jsr	Dgetdrv(pc)
	move.w	d0,-$2c(a2)                     ; -> start_drive
	lea	-$19f(a3),a0                    ; -> str_fastcopy_pro
	move.w	d3,d0
	jsr	menu_register(pc)
	move.w	d0,d3
.accessory_loop
	suba.l	a4,a4                           ; accessory loop:
	move.w	(a2),d0                         ; reserve memory (More Options, KByte) while waiting so programs cannot take it
	bne.s	.wait_ac_open
	move.w	#$400,d1
	move.w	$30b(a3),d0                     ; -> cfg_reserve_kb
	jsr	mul_words(pc)
	move.l	d0,d4
	beq.s	.wait_ac_open
	moveq	#-1,d0
	jsr	malloc_st_ram(pc)
	move.l	a0,d0
	cmp.l	d0,d4
	ble.s	.check_reserve
	move.l	d0,d4
.check_reserve
	tst.l	d4
	ble.s	.wait_ac_open
	move.l	d4,d0
	jsr	malloc_st_ram(pc)
	movea.l	a0,a4
.wait_ac_open
	lea	(sp),a0                         ; wait for AC_OPEN (40) of our menu entry
	jsr	evnt_mesag(pc)
	cmpi.w	#$28,(sp)
	bne.s	.wait_ac_open
	cmp.w	$8(sp),d3
	bne.s	.wait_ac_open
	move.w	(a2),d0                         ; unsupported resolution: only the alert
	beq.s	.open
	movea.l	a3,a0
	moveq	#1,d0
	jsr	alert(pc)
	bra.s	.wait_ac_open

.open
	move.l	a4,d0                           ; release the reserved memory and run
	beq.s	.run
	movea.l	a4,a0
	jsr	Mfree(pc)
.run
	jsr	run_fastcopy(pc)
	bra.s	.accessory_loop

.program
	jsr	run_fastcopy(pc)                ; program: run once and quit
	jsr	quit(pc)
	lea	$10(sp),sp
	movem.l	(sp)+,d3-d4/a2-a4
	rts


;----------------------------------------------------------------------
; Fixes the resource once, checks the messages, allocates the buffer and runs the
; main dialog with the critical error handler installed.
;----------------------------------------------------------------------
run_fastcopy:
	movem.l	d3-d4/a2-a6,-(sp)
	lea	resource_fixed,a2
	lea	saved_path,a6
	move.w	(a2),d0                         ; first start: fix the resource
	bne.w	.save_dta
	move.w	#$1,(a2)
	lea	main_tree,a4                    ; every object of every tree
	movea.l	a4,a5
	lea	high_res_coords,a3
	clr.w	d3
	bra.s	.object_test

.next_object
	move.b	$b7(a6),d0                      ; high resolution: coordinates from high_res_coords, -> medium_res
	bne.s	.fix_object
	move.w	(a3)+,$10(a5)
	move.w	(a3)+,$12(a5)
	move.w	(a3)+,$14(a5)
	move.w	(a3)+,$16(a5)
.fix_object
	move.w	d3,d0                           ; characters to pixels
	movea.l	a4,a0
	jsr	rsrc_obfix(pc)
	addq.w	#1,d3
	lea	$18(a5),a5
.object_test
	cmp.w	#$139,d3
	blt.s	.next_object
	move.l	a4,-$41(a6)                     ; tree pointers, -> main_tree_ptr
	move.l	#error_tree,-$3d(a6)            ; -> error_tree_ptr
	move.b	$b7(a6),d0                      ; medium resolution: outlined main dialog and error box, smaller text, -> medium_res
	bne.s	.check
	movea.l	-$41(a6),a0                     ; -> main_tree_ptr
	ori.w	#$10,$22(a0)
	lea	$720(a4),a5                     ; -> list_tree
	ori.w	#$10,$22(a5)                    ; -> list_tree+1*OBJECT_SIZE+ob_state
	movea.l	-$3d(a6),a0                     ; -> error_tree_ptr
	movea.l	$24(a0),a1
	move.w	#$1100,$12(a1)
	movea.l	-$3d(a6),a0                     ; -> error_tree_ptr
	andi.w	#$ff8f,$e(a0)
	clr.w	d3                              ; box characters as arrows
	bra.s	.box_char_test

.next_box_char
	move.w	d4,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	andi.w	#$ff00,$c(a4,d0.l)              ; -> main_tree+12 indexed
	ori.w	#$3,$c(a4,d0.l)                 ; -> main_tree+12 indexed
.box_char_test
	move.w	d3,d0
	addq.w	#1,d3
	add.w	d0,d0
	move.w	$2(a2,d0.w),d4                  ; -> resource_fixed+2 indexed
	cmp.w	#$ffff,d4
	bne.s	.next_box_char
.check
	jsr	check_messages(pc)              ; tamper check
.save_dta
	jsr	Fgetdta(pc)                     ; keep DTA, path and drive of the caller
	movea.l	a0,a5
	clr.w	d0
	movea.l	a6,a0
	jsr	Dgetpath(pc)
	jsr	Dgetdrv(pc)
	move.w	d0,$81(a6)                      ; -> saved_drive
	move.w	$b1(a6),d1                      ; messages modified: "Somebody overwrote important messages in FastCopy PRO!", -> messages_modified
	beq.s	.run
	lea	-$4bd(a2),a0                    ; -> alert_somebody_overwrote_important
	moveq	#1,d0
	jsr	alert(pc)
	bra.s	.restore_dta

.run
	jsr	alloc_buffer(pc)                ; allocate the buffer
	tst.w	d0
	beq.s	.restore_dta
	suba.l	a0,a0                           ; arrow mouse
	clr.w	d0
	jsr	graf_mouse(pc)
	movea.l	linea_base,a0
	move.w	$138(a0),d4
	clr.w	d0
	jsr	show_mouse(pc)
	lea	$d3(a6),a0                      ; own DTA, critical error handler, -> dta
	jsr	Fsetdta(pc)
	jsr	install_critic(pc)
	jsr	main_dialog(pc)                 ; run
	jsr	remove_critic(pc)
	jsr	free_buffer(pc)
	clr.w	-(sp)                           ; make GEMDOS see a media change on A and B (Rwabs mode 2)
	clr.w	d2
	moveq	#2,d1
	suba.l	a0,a0
	clr.w	d0
	jsr	Rwabs(pc)
	addq.w	#2,sp
	moveq	#1,d0
	move.w	d0,-(sp)
	clr.w	d2
	moveq	#2,d1
	suba.l	a0,a0
	clr.w	d0
	jsr	Rwabs(pc)
	addq.w	#2,sp
	tst.w	d4
	bne.s	.hide
	clr.w	d0
	jsr	show_mouse(pc)
	bra.s	.restore_dta

.hide
	jsr	hide_mouse(pc)
.restore_dta
	movea.l	a5,a0                           ; DTA, drive and path back
	jsr	Fsetdta(pc)
	move.w	$81(a6),d0                      ; -> saved_drive
	jsr	Dsetdrv(pc)
	movea.l	a6,a0
	jsr	Dsetpath(pc)
	movem.l	(sp)+,d3-d4/a2-a6
	rts


;----------------------------------------------------------------------
; The main dialog in a window: form_do and the dispatch of the clicked object.
;----------------------------------------------------------------------
main_dialog:
	movem.l	d3-d5/a2-a6,-(sp)
	lea	dialog_w,a3                     ; dialog_x/y/w/h for the window
	lea	dialog_y,a4
	lea	dialog_x,a5
	lea	main_tree_ptr,a6
	pea	$d8(a6)                         ; -> dialog_h
	pea	(a3)
	pea	(a4)
	movea.l	a5,a1
	movea.l	(a6),a0
	jsr	form_center(pc)                 ; center the main dialog
	lea	$c(sp),sp
	move.w	$d8(a6),-(sp)                   ; -> dialog_h
	move.w	(a3),-(sp)
	move.w	(a4),d2
	move.w	(a5),d1
	clr.w	d0
	jsr	wind_create(pc)                 ; a window without elements, as large as the dialog
	addq.w	#4,sp
	move.w	d0,$c6(a6)                      ; -> window_handle
	tst.w	d0
	bge.s	.window_open
	lea	alert_unable_to_open_window_please,a0 ; "Unable to open Window! Please remove one and try again."
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.return

.window_open
	move.b	$f8(a6),d0                      ; medium resolution: no frame correction, -> medium_res
	beq.s	.with_frame
	clr.w	d1
	bra.s	.open_height

.with_frame
	moveq	#2,d1
.open_height
	move.w	$d8(a6),d0                      ; -> dialog_h
	sub.w	d1,d0
	move.w	d0,-(sp)
	move.b	$f8(a6),d0                      ; -> medium_res
	beq.s	.with_frame2
	clr.w	d1
	bra.s	.open_width

.with_frame2
	moveq	#2,d1
.open_width
	move.w	(a3),d0
	sub.w	d1,d0
	move.w	d0,-(sp)
	move.w	(a4),d2
	move.w	(a5),d1
	move.w	$c6(a6),d0                      ; -> window_handle
	jsr	wind_open(pc)
	addq.w	#4,sp
	move.w	$d8(a6),-(sp)                   ; -> dialog_h
	move.w	(a3),-(sp)
	move.w	(a4),-(sp)
	move.w	(a5),-(sp)
	move.w	$d8(a6),-(sp)                   ; -> dialog_h
	move.w	(a3),-(sp)
	move.w	(a4),d2
	move.w	(a5),d1
	clr.w	d0
	jsr	form_dial(pc)                   ; reserve the screen area
	lea	$c(sp),sp
	jsr	init_main_dialog(pc)            ; object states from the configuration
	lea	config,a2
	move.b	#$1,-$12(a2)                    ; window open: draw_object draws, -> window_open
	clr.w	d0
	movea.l	(a6),a0
	jsr	draw_object(pc)
	movea.l	(a6),a0                         ; origin of the dialog and of the track map
	move.w	$10(a0),$c8(a6)                 ; -> window_x
	movea.l	(a6),a0
	move.w	$12(a0),$ca(a6)                 ; -> window_y
	movea.l	(a6),a0
	move.w	$58(a0),d0
	add.w	$c8(a6),d0                      ; -> window_x
	move.w	d0,$cc(a6)                      ; -> work_x
	movea.l	(a6),a0
	move.w	$5a(a0),d1
	add.w	$ca(a6),d1                      ; -> window_y
	move.w	d1,$ce(a6)                      ; -> work_y
	movea.l	(a6),a0
	move.w	$5c(a0),$d0(a6)                 ; -> work_w
	movea.l	(a6),a0
	move.w	$5e(a0),$d2(a6)                 ; -> work_h
	pea	-$2(a6)                         ; character size, -> mouse_state
	pea	-$2(a6)                         ; -> mouse_state
	lea	$dc(a6),a1                      ; -> char_baseline
	lea	$de(a6),a0                      ; -> char_width
	jsr	graf_handle(pc)
	addq.w	#8,sp
	move.w	d0,-$2(a6)                      ; -> mouse_state
	movea.l	(a6),a0                         ; track map geometry
	move.w	$40(a0),d1
	add.w	$c8(a6),d1                      ; -> window_x
	move.w	d1,$e0(a6)                      ; -> text_x
	movea.l	(a6),a0
	move.w	$42(a0),d0
	add.w	$ca(a6),d0                      ; -> window_y
	move.w	d0,$e2(a6)                      ; -> text_y
	move.b	$f8(a6),d1                      ; -> medium_res
	beq.s	.map_cell_low
	moveq	#22,d2
	bra.s	.map_cell

.map_cell_low
	moveq	#46,d2
.map_cell
	move.w	d2,$ee(a6)                      ; -> map_cell_h
	move.w	#$6,$ec(a6)                     ; -> map_cell_w
	movea.l	(a6),a0
	move.w	$70(a0),d0
	add.w	$cc(a6),d0                      ; -> work_x
	subq.w	#1,d0
	move.w	d0,$e8(a6)                      ; -> map_x
	move.b	$f8(a6),d1                      ; -> medium_res
	beq.s	.map_bottom_low
	moveq	#-1,d2
	bra.s	.map_bottom

.map_bottom_low
	moveq	#2,d2
.map_bottom
	movea.l	(a6),a0
	move.w	$72(a0),d0
	add.w	$ce(a6),d0                      ; -> work_y
	sub.w	$ee(a6),d0                      ; -> map_cell_h
	sub.w	$ee(a6),d0                      ; -> map_cell_h
	add.w	d0,d2
	move.w	d2,$ea(a6)                      ; -> map_y
	jsr	redraw_status(pc)               ; underline the shortcuts, status line, progress frame
	moveq	#1,d0                           ; wind_update: BEG_UPDATE, BEG_MCTRL
	jsr	wind_update(pc)
	moveq	#3,d0
	jsr	wind_update(pc)
.next_click
	pea	-$1b0(a2)                       ; main loop: form_do with the shortcut table, help text and object 60 for edits, -> str_f1_copy_f6_new_conf_f2_scan
	lea	-$220(a2),a1                    ; -> keys_main
	moveq	#60,d0
	movea.l	(a6),a0
	jsr	form_do(pc)
	addq.w	#4,sp
	move.w	d0,d3
	jsr	read_config_fields(pc)          ; values of the dialog into the configuration
	move.w	d3,d0
	cmp.w	#$4b,d0                         ; dispatch on the clicked object
	bhi.s	.next_click
	add.w	d0,d0
	move.w	.table(pc,d0.w),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	.next_click-.table,.about-.table,.next_click-.table,.next_click-.table
	dc.w	.next_click-.table,.next_click-.table,.next_click-.table,.next_click-.table
	dc.w	.next_click-.table,.copy_disk-.table,.scan_disk-.table,.format_disk-.table
	dc.w	.streamer-.table,.directory-.table,.new_conf-.table,.inspect_disk-.table
	dc.w	.soft_format-.table,.image_copy-.table,.quit-.table,.next_click-.table
	dc.w	.next_click-.table,.preset_name-.table,.preset_load-.table,.preset_name-.table
	dc.w	.preset_load-.table,.preset_name-.table,.preset_load-.table,.preset_name-.table
	dc.w	.preset_load-.table,.preset_name-.table,.preset_load-.table,.next_click-.table
	dc.w	.next_click-.table,.next_click-.table,.next_click-.table,.smart_format_box-.table
	dc.w	.next_click-.table,.next_click-.table,.read_config_box-.table,.read_disk_config-.table
	dc.w	.next_click-.table,.next_click-.table,.next_click-.table,.next_click-.table
	dc.w	.next_click-.table,.next_click-.table,.directory_source-.table,.next_click-.table
	dc.w	.next_click-.table,.next_click-.table,.directory_dest-.table,.next_click-.table
	dc.w	.next_click-.table,.next_click-.table,.next_click-.table,.next_click-.table
	dc.w	.next_click-.table,.next_click-.table,.next_click-.table,.sectors_down-.table
	dc.w	.next_click-.table,.sectors_up-.table,.next_click-.table,.start_down-.table
	dc.w	.next_click-.table,.start_up-.table,.end_down-.table,.next_click-.table
	dc.w	.end_up-.table,.next_click-.table,.next_click-.table,.next_click-.table
	dc.w	.next_click-.table,.next_click-.table,.more_options-.table,.save_config-.table
.save_config
	jsr	save_config(pc)                 ; Save Config.
	bra.w	.deselect

.copy_disk
	move.w	$f2(a6),d0                      ; Copy Disk; not as accessory while the messages are modified, -> messages_modified
	beq.s	.copy
.messages_changed
	lea	-$44d(a2),a0                    ; -> alert_somebody_overwrote_important
	moveq	#1,d0
	jsr	alert(pc)
	bra.w	.deselect

.copy
	clr.w	d0
	jsr	copy_disk(pc)
	bra.w	.function_done

.image_copy
	move.w	$f2(a6),d0                      ; Image Copy, -> messages_modified
	bne.s	.messages_changed
	jsr	image_copy(pc)
	bra.w	.function_done

.scan_disk
	jsr	scan_disk(pc)                   ; Scan Disk
	bra.w	.function_done

.format_disk
	move.w	$f2(a6),d0                      ; Format Disk, -> messages_modified
	bne.s	.messages_changed
	clr.w	d0
	jsr	format_disk(pc)
	bra.w	.function_done

.directory_source
	clr.w	d0                              ; "Source": directory of the source drive
	move.b	$5d(a2),d0                      ; -> cfg_source_drive
	jsr	show_directory(pc)
	bra.s	.directory_done

.directory_dest
	clr.w	d0                              ; "Dest.": directory of the destination drive
	move.b	$5e(a2),d0                      ; -> cfg_dest_drive
	jsr	show_directory(pc)
.directory_done
	moveq	#3,d0
	movea.l	(a6),a0
	jsr	draw_object(pc)
	jsr	redraw_status(pc)
	bra.w	.select_button

.directory
	move.b	-$11(a2),d0                     ; Directory: of the current partition, -> no_hard_disk
	beq.s	.directory_choose
	move.b	$f9(a6),d1                      ; -> has_drive_b
	bne.s	.directory_choose
	clr.w	d0
	jsr	show_directory(pc)
	bra.s	.directory_redraw

.directory_choose
	movea.l	(a6),a1                         ; or choose a drive
	moveq	#8,d2
	lea	str_display_directory,a0
	clr.w	d1
	move.b	$ff(a6),d1                      ; -> directory_drive
	clr.b	d0
	jsr	select_drive(pc)
	move.w	d0,d4
	tst.w	d0
	beq.s	.function_done
	move.b	$54(a2),d5                      ; -> cfg_request_boxes
	clr.b	$54(a2)                         ; -> cfg_request_boxes
	move.b	d4,d1
	dc.w	$d23c,$00ff                     ; add.b #$ff,d1
	move.b	d1,$ff(a6)                      ; -> directory_drive
	clr.w	d0
	move.b	d1,d0
	jsr	show_directory(pc)
	move.b	d5,$54(a2)                      ; -> cfg_request_boxes
.directory_redraw
	moveq	#3,d0
	movea.l	(a6),a0
	jsr	draw_object(pc)
	bra.s	.function_done

.inspect_disk
	move.w	$f2(a6),d0                      ; Inspect Disk, -> messages_modified
	bne.w	.messages_changed
	jsr	inspect_disk(pc)
	bra.s	.function_done

.new_conf
	move.w	$f2(a6),d0                      ; New Conf, -> messages_modified
	bne.w	.messages_changed
	moveq	#1,d0
	jsr	copy_disk(pc)
	bra.s	.function_done

.about
	jsr	check_messages(pc)              ; title: about box
	jsr	about_box(pc)
	jsr	redraw_status(pc)
	bra.w	.next_click

.soft_format
	moveq	#1,d0                           ; Soft Format
	jsr	format_disk(pc)
	bra.s	.function_done

.streamer
	jsr	streamer(pc)                    ; Streamer
.function_done
	jsr	unlock_floppy(pc)               ; after a function: floppy unlocked, mouse shown, status redrawn, image closed
	clr.w	d0
	jsr	show_mouse(pc)
	jsr	redraw_status(pc)
	jsr	close_image_file(pc)
.deselect
	move.w	d3,d0                           ; deselect the button
	movea.l	(a6),a0
	jsr	deselect_object(pc)
	bra.w	.next_click

.quit
	moveq	#2,d0                           ; Quit: close the window
	jsr	wind_update(pc)
	clr.w	d0
	jsr	wind_update(pc)
	movea.l	(a6),a0
	andi.w	#$fffe,$1ba(a0)
	move.w	$d8(a6),-(sp)                   ; -> dialog_h
	move.w	(a3),-(sp)
	move.w	(a4),-(sp)
	move.w	(a5),-(sp)
	move.w	$d8(a6),-(sp)                   ; -> dialog_h
	move.w	(a3),-(sp)
	move.w	(a4),d2
	move.w	(a5),d1
	moveq	#3,d0
	jsr	form_dial(pc)
	lea	$c(sp),sp
	move.w	$c6(a6),d0                      ; -> window_handle
	jsr	wind_close(pc)
	move.w	$c6(a6),d0                      ; -> window_handle
	jsr	wind_delete(pc)
	clr.b	-$12(a2)                        ; -> window_open
	bra.w	.return

.read_disk_config
	moveq	#65,d0                          ; Read Disk Config.: "Read Disk Configuration from Drive X: [READ|ABORT]"
	add.b	$5d(a2),d0                      ; -> cfg_source_drive
	move.b	d0,-$2d(a2)                     ; -> alert_read_disk_configuration_from+41
	lea	-$56(a2),a0                     ; -> alert_read_disk_configuration_from
	moveq	#1,d0
	jsr	request_alert(pc)
	subq.w	#1,d0
	bne.s	.select_button
	moveq	#1,d1
	clr.w	d0
	move.b	$5d(a2),d0                      ; -> cfg_source_drive
	movea.l	$c(a6),a0                       ; -> buffer_free
	jsr	read_disk_config(pc)
.select_button
	lea	-$2(a6),a1                      ; -> mouse_state
	moveq	#1,d1
	move.w	d3,d0
	movea.l	(a6),a0
	jsr	form_button(pc)
	bra.w	.next_click

.more_options
	jsr	options_dialog(pc)              ; >> More Options
	bra.w	.function_done

.sectors_down
	moveq	#-1,d0                          ; Sectors -
	jsr	change_sectors(pc)
	bra.w	.deselect

.sectors_up
	moveq	#1,d0                           ; Sectors +
	jsr	change_sectors(pc)
	bra.w	.deselect

.start_down
	moveq	#-1,d0                          ; Start at -
	jsr	change_start_track(pc)
	bra.w	.deselect

.start_up
	moveq	#1,d0                           ; Start at +
	jsr	change_start_track(pc)
	bra.w	.deselect

.end_down
	moveq	#-1,d0                          ; End at -
	jsr	change_end_track(pc)
	bra.w	.deselect

.end_up
	moveq	#1,d0                           ; End at +
	jsr	change_end_track(pc)
	bra.w	.deselect

.read_config_box
	jsr	update_read_config(pc)          ; Read Disk Config. box
	bra.w	.next_click

.smart_format_box
	jsr	update_smart_format(pc)         ; Smart Formatting box
	bra.w	.next_click

.preset_name
	moveq	#-21,d0                         ; preset ">" button: save the configuration under a name
	add.w	d3,d0
	ext.l	d0
	divs.w	#$2,d0
	muls.w	#$e,d0
	lea	$2(a2,d0.w),a0                  ; -> presets indexed
	jsr	name_preset(pc)
	moveq	#1,d0
	add.w	d3,d0
	movea.l	(a6),a0
	jsr	draw_object(pc)
	bra.w	.deselect

.preset_load
	moveq	#-22,d0                         ; preset name button: load it
	add.w	d3,d0
	ext.l	d0
	divs.w	#$2,d0
	muls.w	#$e,d0
	lea	$2(a2,d0.w),a0                  ; -> presets indexed
	jsr	load_preset(pc)
	bra.w	.deselect

.return
	movem.l	(sp)+,d3-d5/a2-a6
	rts


quit:
	jsr	appl_exit(pc)
	jsr	Pterm0(pc)
	rts


;----------------------------------------------------------------------
; form_do with keyboard shortcuts (evnt_multi on keys and button), help key and
; editable fields.
;----------------------------------------------------------------------
form_do:
	movem.l	d3-d7/a2-a6,-(sp)
	lea	-$20(sp),sp
	movea.l	a0,a4                           ; tree, edit object, shortcut table, help text on the stack
	move.w	d0,$1e(sp)
	movea.l	a1,a3
	lea	$1e(sp),a2
	movea.l	linea_base,a1                   ; mouse shown during the dialog
	move.w	$138(a1),d3
	beq.s	.start
	clr.w	d0
	jsr	show_mouse(pc)
.start
	clr.w	d4
	moveq	#1,d5
	lea	$14(sp),a5
	lea	$16(sp),a6
	bra.w	.loop_test

.next_event
	move.w	(a2),d0                         ; start editing a new edit object
	beq.s	.wait_event
	cmp.w	d0,d4
	beq.s	.wait_event
	move.w	d0,d4
	clr.w	(a2)
	moveq	#1,d2
	lea	$1c(sp),a1
	clr.w	d1
	move.w	d4,d0
	movea.l	a4,a0
	jsr	objc_edit(pc)
.wait_event
	clr.b	key_event                       ; evnt_multi: keyboard and left button
	pea	(a5)
	pea	(a6)
	pea	$20(sp)
	pea	$26(sp)
	pea	mouse_y
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	-(sp)
	moveq	#1,d0
	move.w	d0,-(sp)
	lea	mouse_x,a1
	lea	$2e(sp),a0
	move.w	d0,d2
	moveq	#2,d1
	moveq	#19,d0
	jsr	evnt_multi(pc)
	lea	$2e(sp),sp
	move.w	d0,d6
	moveq	#16,d1
	and.w	d0,d1                           ; ignore mouse rectangle events
	bne.s	.wait_event
	moveq	#1,d2
	and.w	d0,d2
	beq.w	.check_button
	move.b	#$1,key_event                   ; keyboard:
	move.w	(a6),d1                         ; Help key: the help pages
	asr.w	#8,d1
	cmp.w	#$62,d1
	bne.s	.not_inspect
	movea.l	$4c(sp),a0
	jsr	show_help(pc)
	bra.w	.loop_test

.not_inspect
	cmpa.l	inspect_tree_ptr,a4             ; disk editor: cursor and function keys go to the editor
	bne.s	.drive_letter
	move.w	$18(sp),d0
	beq.s	.inspect_keys
	subq.w	#4,d0
	bne.s	.drive_letter
.inspect_keys
	move.w	(a6),d0
	asr.w	#8,d0
	moveq	#7,d1
	lea	.table(pc),a0
.inspect_key_test
	cmp.w	(a0)+,d0
	dbeq	d1,.inspect_key_test
	bne.s	.drive_letter
	move.w	$e(a0),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	$3d,$47,$48,$4b,$4d,$50,$73,$74
	dc.w	.inspect_key-.table,.inspect_key-.table,.inspect_key-.table,.inspect_key-.table
	dc.w	.inspect_key-.table,.inspect_key-.table,.inspect_key-.table,.inspect_key-.table
.inspect_key
	move.w	(a6),d0
	asr.w	#8,d0
	move.w	d0,(a2)
	bra.s	.key_exit

.drive_letter
	cmpa.l	drive_tree_ptr,a4               ; drive box: keys a..p choose the drive (object $80 + n)
	bne.s	.shortcuts
	move.w	$18(sp),d0
	bne.s	.shortcuts
	cmpi.b	#$61,$1(a6)                     ; 'a'
	bcs.s	.shortcuts
	cmpi.b	#$70,$1(a6)                     ; 'p'
	bhi.s	.shortcuts
	clr.w	d1
	move.b	$1(a6),d1
	dc.w	$d27c,$1f                       ; add.w #$1f,d1
	move.w	d1,(a2)
.key_exit
	clr.w	d5
	bra.w	.check_exit

.shortcuts
	clr.w	$12(sp)                         ; shortcut table entries: shift flag, scancode, object; ended by 2
	move.l	a3,d0
	beq.w	.form_keybd
	bra.w	.shortcut_test

.next_shortcut
	move.w	$12(sp),d0                      ; shift state must match the entry
	clr.w	d1
	move.b	$0(a3,d0.w),d1
	move.w	d1,-(sp)
	move.w	$1a(sp),d2
	beq.s	.unshifted
	moveq	#1,d0
	bra.s	.check_shift

.unshifted
	clr.w	d0
.check_shift
	move.w	(sp)+,d1
	cmp.w	d0,d1
	bne.w	.skip_entry
	move.w	$12(sp),d0
	clr.w	d1
	move.b	$1(a3,d0.w),d1                  ; scancode must match
	move.w	(a6),d2
	asr.w	#8,d2
	cmp.w	d2,d1
	bne.w	.skip_entry
	clr.w	d1                              ; object of the entry
	move.b	$2(a3,d0.w),d1
	move.w	d1,(a5)
	cmpa.l	#keys_main,a3                   ; main dialog: Sides, Sectors and Density keys cycle through their radio buttons
	bne.s	.not_main
	cmp.w	#$2b,d1
	beq.s	.radio_1
	cmp.w	#$38,d1
	beq.s	.radio_1
	cmp.w	#$47,d1
	bne.w	.press
	bra.s	.radio_1

.not_main
	cmpa.l	#keys_options,a3                ; options dialog: cycle radio groups too
	bne.s	.press
	move.w	(a5),d0
	moveq	#6,d1
	lea	.table2(pc),a0
.radio_test
	cmp.w	(a0)+,d0
	dbeq	d1,.radio_test
	bne.s	.press
	move.w	$c(a0),d0
	jmp	.table2(pc,d0.w)

.table2
	dc.w	$28,$2c,$30,$38,$3c,$40,$49
	dc.w	.radio_1-.table2,.radio_2-.table2,.radio_3-.table2,.radio_1-.table2
	dc.w	.radio_2-.table2,.radio_3-.table2,.radio_4-.table2
.radio_1
	moveq	#1,d7                           ; next selectable object of the group, wrapping to its first
.radio_next
	move.w	(a5),$10(sp)
	bra.s	.radio_count

.radio_scan
	moveq	#1,d0
	move.w	(a5),d2
	addq.w	#1,(a5)
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	and.w	$a(a4,d1.l),d0
	bne.s	.radio_found
.radio_count
	subq.w	#1,d7
	bge.s	.radio_scan
.radio_found
	tst.w	d7
	bge.s	.press
	move.w	$10(sp),(a5)
	bra.s	.press

.radio_3
	moveq	#3,d7
	bra.s	.radio_next

.radio_2
	moveq	#2,d7
	bra.s	.radio_next

.radio_4
	moveq	#4,d7
	bra.s	.radio_next

.press
	moveq	#8,d0                           ; disabled objects are not pressed
	move.w	(a5),d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	and.w	$a(a4,d1.l),d0
	bne.w	.check_exit
	move.w	(a5),(a2)                       ; press the object
	lea	$12(sp),a1
	movea.l	a4,a0
	move.w	(a2),d0
	moveq	#1,d1
	jsr	form_button(pc)
	clr.w	d5
	bra.s	.form_keybd

.skip_entry
	addq.w	#3,$12(sp)
.shortcut_test
	move.w	$12(sp),d0
	cmpi.b	#$2,$0(a3,d0.w)
	bne.w	.next_shortcut
.form_keybd
	tst.w	d5                              ; other keys go to the edit field
	beq.s	.check_button
	pea	(a6)
	movea.l	a2,a1
	move.w	(a6),d2
	move.w	(a2),d1
	move.w	d4,d0
	movea.l	a4,a0
	jsr	form_keybd(pc)
	addq.w	#4,sp
	move.w	d0,d5
	move.w	(a6),d1
	beq.s	.check_button
	moveq	#2,d2
	lea	$1c(sp),a1
	movea.l	a4,a0
	move.w	d4,d0
	jsr	objc_edit(pc)
.check_button
	moveq	#2,d0                           ; mouse button:
	and.w	d6,d0
	beq.s	.check_exit
	move.w	mouse_y,-(sp)                   ; object under the mouse
	move.w	mouse_x,d2
	moveq	#8,d1
	movea.l	a4,a0
	clr.w	d0
	jsr	objc_find(pc)
	addq.w	#2,sp
	move.w	d0,d6
	move.w	d6,(a2)
	cmpi.w	#$ffff,(a2)                     ; outside the dialog: bell
	bne.s	.click
	moveq	#7,d0
	jsr	Cconout(pc)
	clr.w	(a2)
	bra.s	.click_exits_main

.click
	movea.l	a2,a1                           ; click the object
	moveq	#1,d1
	move.w	(a2),d0
	movea.l	a4,a0
	jsr	form_button(pc)
	move.w	d0,d5
.click_exits_main
	cmpa.l	#keys_main,a3                   ; main dialog: Sides 1/2 and Density buttons exit too
	bne.s	.click_exits_options
	cmp.w	#$26,d6
	beq.s	.exit
	cmp.w	#$23,d6
	beq.s	.exit
.click_exits_options
	cmpa.l	#keys_options,a3                ; options dialog: drive buttons exit too
	bne.s	.check_exit
	cmp.w	#$15,d6
	beq.s	.exit
	cmp.w	#$13,d6
	beq.s	.exit
	cmp.w	#$6,d6
	bne.s	.check_exit
.exit
	clr.w	d5
	move.w	d6,(a2)
.check_exit
	tst.w	d5                              ; exit object: end the edit and return it
	beq.s	.end_edit
	move.w	(a2),d0
	beq.s	.loop_test
	cmp.w	d0,d4
	beq.s	.loop_test
.end_edit
	moveq	#3,d2
	lea	$1c(sp),a1
	clr.w	d1
	move.w	d4,d0
	movea.l	a4,a0
	jsr	objc_edit(pc)
.loop_test
	tst.w	d5
	bne.w	.next_event
	tst.w	d3                              ; mouse back, no clipping
	beq.s	.done
	jsr	hide_mouse(pc)
.done
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	d2
	clr.w	d1
	clr.w	d0
	jsr	set_clip(pc)
	addq.w	#4,sp
	move.w	(a2),d0
	lea	$20(sp),sp
	movem.l	(sp)+,d3-d7/a2-a6
	rts


read_config_fields:
	move.l	a2,-(sp)
	lea	main_tree_ptr,a0
	lea	config,a1
	moveq	#1,d0
	movea.l	(a0),a2
	and.b	$48b(a2),d0
	move.b	d0,$5d(a1)                      ; -> cfg_source_drive
	moveq	#1,d1
	and.b	$4eb(a2),d1
	move.b	d1,$5e(a1)                      ; -> cfg_dest_drive
	moveq	#1,d2
	and.b	$353(a2),d2
	move.b	d2,$5a(a1)                      ; -> cfg_smart_format
	tst.b	d2
	beq.s	.set_format_dest
	clr.b	d0
	bra.s	.set_format_dest2

.set_format_dest
	moveq	#1,d0
	movea.l	(a0),a2
	and.b	$383(a2),d0
.set_format_dest2
	move.b	d0,$5f(a1)                      ; -> cfg_format_dest
	moveq	#1,d1
	movea.l	(a0),a2
	and.b	$323(a2),d1
	move.b	d1,$60(a1)                      ; -> cfg_verify_dest
	moveq	#1,d0
	and.b	$3cb(a2),d0
	move.b	d0,$61(a1)                      ; -> cfg_multiple_copy
	moveq	#1,d2
	and.b	$39b(a2),d2
	move.b	d2,$63(a1)                      ; -> cfg_read_config
	moveq	#1,d1
	and.b	$42b(a2),d1
	move.b	d1,$64(a1)                      ; -> cfg_used_only
	moveq	#1,d0
	and.b	$6cb(a2),d0
	move.b	d0,$6e(a1)                      ; -> cfg_hd
	jsr	check_config_fields(pc)
	movea.l	(sp)+,a2
	rts


name_preset:
	movem.l	a2-a5,-(sp)
	subq.w	#8,sp
	movea.l	a0,a4
	lea	preset_tree,a2
	pea	(sp)
	pea	$6(sp)
	pea	$c(sp)
	lea	$12(sp),a1
	movea.l	a2,a0
	jsr	form_center(pc)
	lea	$c(sp),sp
	movea.l	$24(a2),a0                      ; -> preset_tree+1*OBJECT_SIZE+ob_spec
	movea.l	(a0),a3
	movea.l	a4,a1
	movea.l	a3,a0
	jsr	strcpy(pc)
	moveq	#7,d0
	jsr	Cconout(pc)
	clr.w	d0
	movea.l	a2,a0
	jsr	draw_object(pc)
	lea	config,a5
	lea	mouse_state,a1
	move.l	a1,-(sp)
	pea	$88(a5)                         ; -> str_ret_ok_undo_cancel
	lea	$84(a5),a1                      ; -> keys_preset
	moveq	#1,d0
	movea.l	a2,a0
	jsr	form_do(pc)
	addq.w	#4,sp
	move.w	d0,$a(sp)
	movea.l	a2,a0
	moveq	#1,d1
	movea.l	(sp)+,a1
	jsr	form_button(pc)
	move.w	$16(a2),-(sp)                   ; -> preset_tree+ob_height
	move.w	$14(a2),-(sp)                   ; -> preset_tree+ob_width
	move.w	$12(a2),-(sp)                   ; -> preset_tree+ob_y
	move.w	$10(a2),d2                      ; -> preset_tree+ob_x
	moveq	#8,d1
	clr.w	d0
	movea.l	main_tree_ptr,a0
	jsr	objc_draw(pc)
	addq.w	#6,sp
	cmpi.w	#$2,$6(sp)
	bne.s	.finish
	movea.l	a3,a1
	movea.l	a4,a0
	jsr	strcpy(pc)
	move.b	$67(a5),$8(a4)                  ; -> cfg_sides+1
	move.b	$69(a5),$9(a4)                  ; -> cfg_sectors+1
	move.b	$6b(a5),$a(a4)                  ; -> cfg_start_track+1
	move.b	$6d(a5),$b(a4)                  ; -> cfg_end_track+1
	move.b	$6e(a5),$c(a4)                  ; -> cfg_hd
.finish
	addq.w	#8,sp
	movem.l	(sp)+,a2-a5
	rts


load_preset:
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	movea.l	a0,a2
	lea	config,a3
	clr.w	d0
	move.b	$8(a2),d0
	move.w	d0,$66(a3)                      ; -> cfg_sides
	moveq	#60,d1
	clr.w	d0
	move.b	$9(a2),d0
	move.w	d0,$68(a3)                      ; -> cfg_sectors
	movea.l	main_tree_ptr,a0
	jsr	set_two_digits(pc)
	moveq	#64,d1
	movea.l	main_tree_ptr,a0
	clr.w	d0
	move.b	$a(a2),d0
	move.w	d0,$6a(a3)                      ; -> cfg_start_track
	jsr	set_two_digits(pc)
	moveq	#67,d1
	movea.l	main_tree_ptr,a0
	clr.w	d0
	move.b	$b(a2),d0
	move.w	d0,$6c(a3)                      ; -> cfg_end_track
	jsr	set_two_digits(pc)
	clr.w	d0
	move.b	$49(a3),d0                      ; -> cfg_a_density
	clr.w	d1
	move.b	$4b(a3),d1                      ; -> cfg_b_density
	add.w	d1,d0
	beq.s	.set_sides_density
	move.b	$c(a2),$6e(a3)                  ; -> cfg_hd
.set_sides_density
	jsr	set_sides_density(pc)
	jsr	check_config_fields(pc)
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


set_step_rates:
	move.l	a2,-(sp)
	lea	dd_step_rates,a2
	clr.w	d0
	move.b	cfg_a_step_rate,d0
	add.w	d0,d0
	move.w	$0(a2,d0.w),d1                  ; -> dd_step_rates indexed
	clr.w	d0
	jsr	floprate(pc)
	clr.w	d0
	move.b	cfg_b_step_rate,d0
	add.w	d0,d0
	move.w	$0(a2,d0.w),d1                  ; -> dd_step_rates indexed
	moveq	#1,d0
	jsr	floprate(pc)
	movea.l	(sp)+,a2
	rts


init_main_dialog:
	movem.l	d3/a2-a3,-(sp)
	clr.w	d3
	lea	config,a2                       ; preset names into the main dialog
	lea	main_tree_ptr,a3
	bra.s	.preset_test

.next_preset
	moveq	#14,d0
	muls.w	d3,d0
	lea	$2(a2,d0.w),a0                  ; -> presets indexed
	move.w	d3,d2
	add.w	d2,d2
	dc.w	$d47c,$16                       ; add.w #$16,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a3),a1
	movea.l	$c(a1,d1.l),a1
	move.l	a0,(a1)
	addq.w	#1,d3
.preset_test
	cmp.w	#$5,d3
	blt.s	.next_preset
	suba.l	a0,a0
	jsr	Super(pc)
	move.l	d0,$100(a3)                     ; -> saved_ssp_gem
	move.b	#$1,$f9(a3)                     ; -> has_drive_b
	cmpi.b	#$1,$4a7.w
	bne.s	.drives
	moveq	#8,d0
	movea.l	(a3),a0
	move.w	d0,$4ea(a0)
	movea.l	(a3),a0
	move.w	d0,$48a(a0)
	clr.b	d1
	move.b	d1,$5e(a2)                      ; -> cfg_dest_drive
	move.b	d1,$5d(a2)                      ; -> cfg_source_drive
	move.b	d1,$f9(a3)                      ; -> has_drive_b
.drives
	movea.l	$100(a3),a0                     ; drives: Drvmap, -> saved_ssp_gem
	jsr	Super(pc)
	move.b	$5d(a2),$ff(a3)                 ; -> cfg_source_drive, -> directory_drive
	jsr	Drvmap(pc)
	move.l	d0,d3
	dc.w	$c0bc                           ; and.l #$fffffffc,d0, no hard disk: extended memory and Fast Format off
	dc.l	$fffffffc
	bne.s	.check_ext_memory
	clr.b	$5b(a2)                         ; -> cfg_ext_memory
	moveq	#8,d0
	movea.l	(a3),a0
	move.w	d0,$12a(a0)
	movea.l	(a3),a0
	move.w	d0,$1a2(a0)
	move.b	#$1,-$11(a2)                    ; -> no_hard_disk
	bra.s	.drive_buttons

.check_ext_memory
	move.b	$5b(a2),d0                      ; extended memory partition missing: "Drive X: is not active! No Extended Memory is used!", -> cfg_ext_memory
	beq.s	.drive_buttons
	moveq	#1,d1
	move.b	$5c(a2),d2                      ; -> cfg_ext_memory_drive
	lsl.w	d2,d1
	ext.l	d1
	and.l	d3,d1
	bne.s	.drive_buttons
	moveq	#65,d3
	add.b	d2,d3
	move.b	d3,$af(a2)                      ; -> alert_drive_x_is_not_active_no+10
	lea	$a5(a2),a0                      ; -> alert_drive_x_is_not_active_no
	moveq	#1,d0
	jsr	alert(pc)
	clr.b	$5b(a2)                         ; -> cfg_ext_memory
.drive_buttons
	moveq	#1,d0                           ; source and destination drive buttons
	move.w	d0,-(sp)
	move.l	d1,-(sp)
	move.b	$5e(a2),d1                      ; -> cfg_dest_drive
	beq.s	.dest_a
	moveq	#52,d2
	bra.s	.set_dest

.dest_a
	moveq	#51,d2
.set_dest
	ext.l	d2
	move.l	(sp)+,d0
	move.l	d2,d0
	add.l	d0,d0
	add.l	d2,d0
	lsl.l	#3,d0
	movea.l	(a3),a0
	move.w	(sp)+,d1
	move.w	d1,$a(a0,d0.l)
	move.w	d1,-(sp)
	move.l	d0,-(sp)
	move.b	$5d(a2),d0                      ; -> cfg_source_drive
	beq.s	.source_a
	moveq	#48,d1
	bra.s	.set_source

.source_a
	moveq	#47,d1
.set_source
	ext.l	d1
	move.l	(sp)+,d0
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a3),a0
	move.w	(sp)+,$a(a0,d0.l)
	jsr	set_step_rates(pc)
	move.b	$5f(a2),d0                      ; check boxes from the configuration, -> cfg_format_dest
	beq.s	.no_format_dest
	movea.l	(a3),a0
	move.w	#$1,$382(a0)
.no_format_dest
	move.b	$60(a2),d0                      ; -> cfg_verify_dest
	beq.s	.no_verify
	movea.l	(a3),a0
	move.w	#$1,$322(a0)
.no_verify
	move.b	$61(a2),d0                      ; -> cfg_multiple_copy
	beq.s	.no_multiple
	movea.l	(a3),a0
	move.w	#$1,$3ca(a0)
.no_multiple
	move.b	$63(a2),d0                      ; -> cfg_read_config
	beq.s	.no_read_config
	movea.l	(a3),a0
	move.w	#$1,$39a(a0)
.no_read_config
	move.b	$5a(a2),d0                      ; -> cfg_smart_format
	beq.s	.no_smart_format
	movea.l	(a3),a0
	move.w	#$1,$352(a0)
.no_smart_format
	move.b	$64(a2),$20(a3)                 ; Get Sectors all / used, -> cfg_used_only, -> used_only_shown
	move.l	d0,-(sp)
	move.b	$64(a2),d0                      ; -> cfg_used_only
	beq.s	.all_sectors
	moveq	#44,d1
	bra.s	.get_sectors

.all_sectors
	moveq	#43,d1
.get_sectors
	ext.l	d1
	move.l	(sp)+,d0
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a3),a0
	move.w	#$1,$a(a0,d0.l)
	jsr	update_read_config(pc)          ; dependent objects, sides, density, disk configuration values, options
	jsr	update_smart_format(pc)
	moveq	#1,d0
	clr.w	d2
	move.b	$6e(a2),d2                      ; -> cfg_hd
	dc.w	$d47c,$47                       ; add.w #$47,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a3),a0
	move.w	d0,$a(a0,d1.l)
	moveq	#56,d2
	add.w	$66(a2),d2                      ; -> cfg_sides
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a3),a0
	move.w	d0,$a(a0,d1.l)
	jsr	show_disk_config(pc)
	jsr	show_options(pc)
	movem.l	(sp)+,d3/a2-a3
	rts


show_disk_config:
	moveq	#60,d1
	movea.l	main_tree_ptr,a0
	move.w	cfg_sectors,d0
	jsr	set_two_digits(pc)
	moveq	#64,d1
	movea.l	main_tree_ptr,a0
	move.w	cfg_start_track,d0
	jsr	set_two_digits(pc)
	moveq	#67,d1
	movea.l	main_tree_ptr,a0
	move.w	cfg_end_track,d0
	jsr	set_two_digits(pc)
	rts


check_config_fields:
	movem.l	d3-d5/a2-a3,-(sp)               ; checks the sides, sectors and track fields against the drives
	lea	config,a2
	lea	main_tree_ptr,a3
	move.b	$6e(a2),d0                      ; most sectors: 11 DD, 18 HD 5.25", 22 HD 3.5", -> cfg_hd
	beq.s	.dd
	cmpi.b	#$2,$49(a2)                     ; -> cfg_a_density
	beq.s	.hd_3
	cmpi.b	#$2,$4b(a2)                     ; -> cfg_b_density
	bne.s	.hd_5
.hd_3
	moveq	#22,d0
	bra.s	.set_max

.hd_5
	moveq	#18,d0
.set_max
	bra.s	.store_max

.dd
	moveq	#11,d0
.store_max
	move.w	d0,$f4(a3)                      ; -> shown_sectors
	clr.w	d3
	moveq	#1,d1
	movea.l	(a3),a0
	and.w	$562(a0),d1
	move.w	d1,$66(a2)                      ; -> cfg_sides
	movea.l	$5ac(a0),a1
	movea.l	(a1),a0
	jsr	atoi(pc)
	move.w	d0,d4
	move.w	d4,$68(a2)                      ; -> cfg_sectors
	cmp.w	#$1,d4
	blt.s	.clamp_sectors
	cmp.w	$f4(a3),d4                      ; -> shown_sectors
	ble.s	.tracks
.clamp_sectors
	move.w	$f4(a3),$68(a2)                 ; -> shown_sectors, -> cfg_sectors
	moveq	#60,d1
	movea.l	(a3),a0
	move.w	$f4(a3),d0                      ; -> shown_sectors
	jsr	set_two_digits(pc)
	moveq	#1,d3
.tracks
	movea.l	(a3),a0                         ; start and end track, at most 86, start not past end
	movea.l	$60c(a0),a1
	movea.l	(a1),a0
	jsr	atoi(pc)
	move.w	d0,d4
	movea.l	(a3),a0
	movea.l	$654(a0),a1
	movea.l	(a1),a0
	jsr	atoi(pc)
	move.w	d0,d5
	cmp.w	#$56,d0
	ble.s	.start_test
	moveq	#86,d5
	moveq	#67,d1
	movea.l	(a3),a0
	move.w	d5,d0
	jsr	set_two_digits(pc)
	moveq	#1,d3
.start_test
	cmp.w	d4,d5
	bge.s	.store_tracks
	move.w	d5,d4
	moveq	#64,d1
	movea.l	(a3),a0
	move.w	d4,d0
	jsr	set_two_digits(pc)
	moveq	#1,d3
.store_tracks
	move.w	d4,$6a(a2)                      ; -> cfg_start_track
	move.w	d5,$6c(a2)                      ; -> cfg_end_track
	tst.w	d3
	beq.s	.return
	jsr	set_sides_density(pc)
.return
	movem.l	(sp)+,d3-d5/a2-a3
	rts


set_sides_density:
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	lea	main_tree_ptr,a2
	lea	config,a3
	moveq	#1,d0
	movea.l	(a2),a0
	and.w	$562(a0),d0
	move.w	$66(a3),d1                      ; -> cfg_sides
	cmp.w	d0,d1
	beq.s	.use_hd
	lea	-$2(a2),a1                      ; -> mouse_state
	moveq	#56,d0
	add.w	d1,d0
	moveq	#1,d1
	jsr	form_button(pc)
.use_hd
	clr.w	d0
	move.b	$6e(a3),d0                      ; -> cfg_hd
	moveq	#1,d1
	movea.l	(a2),a0
	and.w	$6ca(a0),d1
	cmp.w	d1,d0
	beq.s	.draw_object
	lea	-$2(a2),a1                      ; -> mouse_state
	dc.w	$d07c,$47                       ; add.w #$47,d0
	moveq	#1,d1
	jsr	form_button(pc)
.draw_object
	moveq	#60,d0
	movea.l	(a2),a0
	jsr	draw_object(pc)
	moveq	#64,d0
	movea.l	(a2),a0
	jsr	draw_object(pc)
	moveq	#67,d0
	movea.l	(a2),a0
	jsr	draw_object(pc)
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


change_sectors:
	move.l	d3,-(sp)
	move.w	d0,d3
	add.w	cfg_sectors,d3
	cmp.w	#$1,d3
	bge.s	.check_shown_sectors
	moveq	#1,d3
	moveq	#7,d0
	jsr	Cconout(pc)
.check_shown_sectors
	cmp.w	shown_sectors,d3
	ble.s	.set_sectors
	move.w	shown_sectors,d3
	moveq	#7,d0
	jsr	Cconout(pc)
.set_sectors
	move.w	d3,cfg_sectors
	moveq	#60,d1
	movea.l	main_tree_ptr,a0
	move.w	d3,d0
	jsr	set_two_digits(pc)
	moveq	#60,d0
	movea.l	main_tree_ptr,a0
	jsr	draw_object(pc)
	move.l	(sp)+,d3
	rts


change_start_track:
	move.l	d3,-(sp)                        ; start track + d0, limited to 0..end track, at most 86
	move.l	a2,-(sp)
	move.w	d0,d3
	lea	config,a2
	add.w	$6a(a2),d3                      ; -> cfg_start_track
	tst.w	d3
	bge.s	.check_end
	clr.w	d3
	moveq	#7,d0
	jsr	Cconout(pc)
.check_end
	cmp.w	$6c(a2),d3                      ; -> cfg_end_track
	ble.s	.check_86
	move.w	$6c(a2),d3                      ; -> cfg_end_track
	moveq	#7,d0
	jsr	Cconout(pc)
.check_86
	cmp.w	#$56,d3
	ble.s	.store
	moveq	#86,d3
	moveq	#7,d0
	jsr	Cconout(pc)
.store
	move.w	d3,$6a(a2)                      ; -> cfg_start_track
	moveq	#64,d1
	movea.l	main_tree_ptr,a0
	move.w	d3,d0
	jsr	set_two_digits(pc)
	moveq	#64,d0
	movea.l	main_tree_ptr,a0
	jsr	draw_object(pc)
	movea.l	(sp)+,a2
	move.l	(sp)+,d3
	rts


change_end_track:
	move.l	d3,-(sp)                        ; end track + d0, limited to start track..86
	move.l	a2,-(sp)
	move.w	d0,d3
	lea	config,a2
	add.w	$6c(a2),d3                      ; -> cfg_end_track
	tst.w	d3
	bge.s	.check_start
	clr.w	d3
	moveq	#7,d0
	jsr	Cconout(pc)
.check_start
	cmp.w	$6a(a2),d3                      ; -> cfg_start_track
	bge.s	.check_86
	move.w	$6a(a2),d3                      ; -> cfg_start_track
	moveq	#7,d0
	jsr	Cconout(pc)
.check_86
	cmp.w	#$56,d3
	ble.s	.store
	moveq	#86,d3
	moveq	#7,d0
	jsr	Cconout(pc)
.store
	move.w	d3,$6c(a2)                      ; -> cfg_end_track
	moveq	#67,d1
	movea.l	main_tree_ptr,a0
	move.w	d3,d0
	jsr	set_two_digits(pc)
	moveq	#67,d0
	movea.l	main_tree_ptr,a0
	jsr	draw_object(pc)
	movea.l	(sp)+,a2
	move.l	(sp)+,d3
	rts


first_selected:
	movem.l	d3-d4/a2,-(sp)                  ; first selected object from d0 to d1, or 0
	movea.l	a0,a2
	move.w	d0,d3
	move.w	d1,d4
	bra.s	.object_test

.next_object
	moveq	#1,d0
	move.w	d3,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	and.w	$a(a2,d1.l),d0
	beq.s	.advance
	move.w	d3,d0
	bra.s	.return

.advance
	addq.w	#1,d3
.object_test
	cmp.w	d3,d4
	bge.s	.next_object
	clr.w	d0
.return
	movem.l	(sp)+,d3-d4/a2
	rts


set_two_digits:
	move.w	d4,-(sp)
	move.l	a2,-(sp)
	move.w	d0,d4
	movea.l	a0,a2
	ext.l	d1
	move.l	d1,d2
	add.l	d2,d2
	add.l	d1,d2
	lsl.l	#3,d2
	movea.l	$c(a2,d2.l),a1
	movea.l	(a1),a0
	ext.l	d0
	divs.w	#$a,d0
	dc.w	$d03c,$0030                     ; add.b #$30,d0
	move.b	d0,(a0)+
	move.w	d4,d2
	ext.l	d2
	divs.w	#$a,d2
	swap	d2
	dc.w	$d43c,$0030                     ; add.b #$30,d2
	move.b	d2,(a0)
	movea.l	(sp)+,a2
	move.w	(sp)+,d4
	rts


draw_object:
	move.w	d3,-(sp)
	move.l	a2,-(sp)
	movea.l	a0,a2
	move.w	d0,d3
	cmpa.l	main_tree_ptr,a0
	bne.s	.use_dialog_h
	move.b	window_open,d1
	beq.s	.finish
.use_dialog_h
	move.w	dialog_h,-(sp)
	move.w	dialog_w,-(sp)
	move.w	dialog_y,-(sp)
	move.w	dialog_x,d2
	moveq	#8,d1
	move.w	d3,d0
	movea.l	a2,a0
	jsr	objc_draw(pc)
	addq.w	#6,sp
.finish
	movea.l	(sp)+,a2
	move.w	(sp)+,d3
	rts


set_state_draw:
	move.w	d4,-(sp)
	move.w	d0,d4
	ext.l	d0
	move.l	d0,d2
	add.l	d2,d2
	add.l	d0,d2
	lsl.l	#3,d2
	movea.l	main_tree_ptr,a0
	move.w	d1,$a(a0,d2.l)
	movea.l	main_tree_ptr,a0
	move.w	d4,d0
	jsr	draw_object(pc)
	move.w	(sp)+,d4
	rts


enable_object:
	move.w	d3,-(sp)
	move.w	d0,d3
	ext.l	d0
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	lsl.l	#3,d1
	movea.l	main_tree_ptr,a0
	andi.w	#$fff7,$a(a0,d1.l)
	movea.l	main_tree_ptr,a0
	move.w	d3,d0
	jsr	draw_object(pc)
	move.w	(sp)+,d3
	rts


update_read_config:
	move.b	cfg_read_config,d0
	beq.s	.set_used_only_shown
	moveq	#8,d1
	moveq	#54,d0
	jsr	set_state_draw(pc)
	moveq	#42,d0
	jsr	enable_object(pc)
	clr.w	d1
	move.b	used_only_shown,d1
	dc.w	$d27c,$2b                       ; add.w #$2b,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	main_tree_ptr,a0
	move.w	#$1,$a(a0,d0.l)
	moveq	#43,d0
	jsr	enable_object(pc)
	moveq	#44,d0
	jsr	enable_object(pc)
	rts

.set_used_only_shown
	move.b	cfg_used_only,used_only_shown
	moveq	#54,d0
	jsr	enable_object(pc)
	moveq	#8,d1
	moveq	#42,d0
	jsr	set_state_draw(pc)
	moveq	#8,d1
	moveq	#43,d0
	jsr	set_state_draw(pc)
	moveq	#8,d1
	moveq	#44,d0
	jsr	set_state_draw(pc)
	rts


update_smart_format:
	move.b	cfg_smart_format,d0
	beq.s	.enable_object
	moveq	#8,d1
	moveq	#36,d0
	jsr	set_state_draw(pc)
	movea.l	main_tree_ptr,a0
	ori.w	#$8,$382(a0)
	moveq	#37,d0
	movea.l	main_tree_ptr,a0
	jsr	draw_object(pc)
	rts

.enable_object
	moveq	#36,d0
	jsr	enable_object(pc)
	moveq	#37,d0
	jsr	enable_object(pc)
	rts


draw_status_text:
	move.l	a2,-(sp)
	lea	main_tree_ptr,a2
	movea.l	(a2),a1
	move.l	a0,$3c(a1)
	move.w	$d8(a2),-(sp)                   ; -> dialog_h
	move.w	$da(a2),-(sp)                   ; -> dialog_w
	move.w	$d6(a2),-(sp)                   ; -> dialog_y
	move.w	$d4(a2),d2                      ; -> dialog_x
	clr.w	d1
	moveq	#2,d0
	movea.l	(a2),a0
	jsr	objc_draw(pc)
	addq.w	#6,sp
	movea.l	(sp)+,a2
	rts


alloc_buffer:
	move.l	d3,-(sp)
	move.l	a2,-(sp)
	moveq	#-1,d0
	jsr	malloc_st_ram(pc)
	move.l	a0,d3
.loop_alert
	lea	buffer_start,a2
	cmp.l	#$8000,d3
	bge.s	.malloc_st_ram
	lea	alert_fastcopy_pro_needs_at_least,a0
	moveq	#1,d0
	jsr	alert(pc)
	clr.w	d0
	bra.s	.finish

.malloc_st_ram
	move.l	d3,d0
	jsr	malloc_st_ram(pc)
	move.l	a0,(a2)
	moveq	#-1,d0
	jsr	Malloc(pc)
	cmpa.l	#$1000,a0
	bge.s	.set_buffer_free
	jsr	free_buffer(pc)
	dc.w	$96bc                           ; sub.l #$1100,d3
	dc.l	$1100
	bra.s	.loop_alert

.set_buffer_free
	movea.l	(a2),a0
	lea	$204(a0),a0
	move.l	a0,$4(a2)                       ; -> buffer_free
	move.l	a0,$14(a2)                      ; -> copy_buffer
	movea.l	(a2),a1
	adda.l	d3,a1
	move.l	a1,$8(a2)                       ; -> buffer_end
	moveq	#1,d0
.finish
	movea.l	(sp)+,a2
	move.l	(sp)+,d3
	rts


free_buffer:
	movea.l	buffer_start,a0
	jsr	Mfree(pc)
	rts


;----------------------------------------------------------------------
; alert only when Show Request Boxes is on; otherwise returns d0.
;----------------------------------------------------------------------
request_alert:
	move.w	d3,-(sp)
	move.w	d0,d3
	move.b	cfg_request_boxes,d1
	beq.s	.finish
	jsr	alert(pc)
	bra.s	.finish2

.finish
	move.w	d3,d0
.finish2
	move.w	(sp)+,d3
	rts


;----------------------------------------------------------------------
; form_alert with the bell (cfg_sound) and the mouse shown.
;----------------------------------------------------------------------
alert:
	movem.l	d3-d4/a2,-(sp)
	move.w	d0,d4
	movea.l	a0,a2
	movea.l	linea_base,a1
	move.w	$138(a1),d3
	beq.s	.bell
	clr.w	d0
	jsr	show_mouse(pc)
.bell
	move.b	alert_bell,d0                   ; bell when Use Sound is on
	beq.s	.show
	moveq	#7,d0
	jsr	Cconout(pc)
.show
	movea.l	a2,a0
	move.w	d4,d0
	jsr	form_alert(pc)
	move.w	d0,d4
	tst.w	d3
	beq.s	.done
	jsr	hide_mouse(pc)
.done
	move.w	d4,d0
	movem.l	(sp)+,d3-d4/a2
	rts


linea_defaults:
	clr.w	d0
	jsr	set_write_mode(pc)
	moveq	#15,d0
	jsr	set_colour(pc)
	clr.w	-(sp)
	clr.w	-(sp)
	clr.w	d2
	clr.w	d1
	clr.w	d0
	jsr	set_clip(pc)
	addq.w	#4,sp
	jsr	hide_mouse(pc)
	rts


draw_text_line:
	movem.l	d3-d5/a2,-(sp)
	movea.l	a0,a2
	move.w	d0,d5
	move.w	d1,d4
	movea.l	linea_base,a1
	move.w	$138(a1),d3
	bne.s	.set_write_mode
	jsr	hide_mouse(pc)
.set_write_mode
	clr.w	d0
	jsr	set_write_mode(pc)
	clr.w	-(sp)
	move.w	d4,-(sp)
	clr.w	d2
	clr.w	d1
	clr.w	d0
	movea.l	small_font,a0
	jsr	set_text_font(pc)
	addq.w	#4,sp
	movea.l	a2,a0
	clr.w	d2
	move.w	text_y,d1
	move.w	d5,d0
	muls.w	char_width,d0
	add.w	text_x,d0
	jsr	text_string(pc)
	tst.w	d3
	bne.s	.return
	clr.w	d0
	jsr	show_mouse(pc)
.return
	movem.l	(sp)+,d3-d5/a2
	rts


draw_progress_text:
	move.l	d3,-(sp)
	move.l	a2,-(sp)
	lea	-$14(sp),sp
	movea.l	a0,a2
	jsr	strlen(pc)
	move.l	d0,d3
	movea.l	a2,a1
	lea	(sp),a0
	jsr	strcpy(pc)
	lea	$0(sp,d3.w),a0
	move.w	d3,d0
	bra.s	.loop_test2

.loop_test
	move.b	#$20,(a0)+
	addq.w	#1,d0
.loop_test2
	cmp.w	#$12,d0
	blt.s	.loop_test
	clr.b	(a0)
	moveq	#1,d1
	moveq	#1,d0
	lea	(sp),a0
	jsr	draw_text_line(pc)
	lea	$14(sp),sp
	movea.l	(sp)+,a2
	move.l	(sp)+,d3
	rts


draw_memory_bar:
	movem.l	d3/a2-a4,-(sp)                  ; free buffer in KB at the end of the status line; d0 set: only changed digits
	subq.w	#8,sp
	movea.l	a0,a3
	move.b	d0,d3
	tst.b	d0
	bne.s	.value
	moveq	#15,d1
	lea	str_kb,a0
	moveq	#74,d0
	jsr	draw_text_line(pc)
.value
	lea	(sp),a2
	moveq	#32,d0
	move.b	d0,(a2)+
	move.b	d0,(a2)+
	move.b	d0,(a2)+
	lea	memory_bar,a4
	moveq	#10,d1
	movea.l	a2,a0
	move.w	d1,-(sp)
	move.l	a0,-(sp)
	move.l	copy_buffer_end,d0
	beq.s	.whole_buffer
	movea.l	d0,a1
	bra.s	.kbytes

.whole_buffer
	movea.l	-$134(a4),a1                    ; -> buffer_end
.kbytes
	move.l	a1,d0
	sub.l	a3,d0
	moveq	#10,d1
	asr.l	d1,d0
	movea.l	(sp)+,a0
	move.w	(sp)+,d1
	jsr	ltoa(pc)
	movea.l	a2,a0
	jsr	strlen(pc)
	moveq	#4,d1
	sub.l	d0,d1
	suba.l	d1,a2
	tst.b	d3
	beq.s	.draw_all
	clr.w	d0
	jsr	set_write_mode(pc)
	clr.w	-(sp)
	moveq	#1,d0
	move.w	d0,-(sp)
	clr.w	d2
	clr.w	d1
	movea.l	-$4(a4),a0                      ; -> small_font
	clr.w	d0
	jsr	set_text_font(pc)
	addq.w	#4,sp
	clr.w	d3
	bra.s	.digit_test

.next_digit
	move.b	$0(a2,d3.w),d0
	cmp.b	$0(a4,d3.w),d0                  ; -> memory_bar indexed
	beq.s	.advance
	move.b	d0,d2
	move.w	-$62(a4),d1                     ; -> text_y
	moveq	#69,d0
	add.w	d3,d0
	muls.w	-$66(a4),d0                     ; -> char_width
	add.w	-$64(a4),d0                     ; -> text_x
	jsr	text_char_at(pc)
.advance
	addq.w	#1,d3
.digit_test
	cmp.w	#$4,d3
	blt.s	.next_digit
	bra.s	.remember

.draw_all
	moveq	#1,d1
	move.w	d1,-(sp)
	movea.l	a2,a0
	jsr	strlen(pc)
	moveq	#4,d1
	sub.l	d0,d1
	movea.l	a2,a0
	suba.l	d1,a0
	moveq	#69,d0
	move.w	(sp)+,d1
	jsr	draw_text_line(pc)
.remember
	moveq	#4,d0
	movea.l	a2,a1
	movea.l	a4,a0
	jsr	memcpy(pc)
	addq.w	#8,sp
	movem.l	(sp)+,d3/a2-a4
	rts


redraw_status:
	lea	underlines_main,a1
	move.w	window_y,d1
	move.w	window_x,d0
	movea.l	main_tree_ptr,a0
	jsr	underline_shortcuts(pc)
	jsr	draw_select_option(pc)
	jsr	draw_progress_frame(pc)
	rts


draw_select_option:
	lea	str_select_option,a0
	jsr	draw_status_text(pc)
	clr.l	copy_buffer_end
	clr.b	d0
	movea.l	buffer_free,a0
	jsr	draw_memory_bar(pc)
	rts


draw_progress_frame:
	movem.l	d3-d6/a2,-(sp)
	lea	map_y,a2
	move.w	$4(a2),d0                       ; -> map_cell_h
	add.w	d0,d0
	move.w	d0,-(sp)
	moveq	#87,d1
	mulu.w	$2(a2),d1                       ; -> map_cell_w
	move.w	d1,-(sp)
	move.w	(a2),-(sp)
	move.w	-$2(a2),d2                      ; -> map_x
	movea.l	-$ea(a2),a0                     ; -> main_tree_ptr
	moveq	#3,d0
	moveq	#8,d1
	jsr	objc_draw(pc)
	addq.w	#6,sp
	movea.l	linea_base,a0
	move.w	$138(a0),d3
	jsr	linea_defaults(pc)
	moveq	#-1,d0
	jsr	set_line_mask(pc)
	move.w	-$2(a2),d5                      ; -> map_x
	moveq	#-1,d4
	bra.s	.loop_test

.loop_use_map_cell_h
	move.w	$4(a2),d0                       ; -> map_cell_h
	add.w	d0,d0
	add.w	(a2),d0
	move.w	d0,-(sp)
	move.w	d5,d2
	move.w	(a2),d1
	move.w	d5,d0
	jsr	draw_line(pc)
	addq.w	#2,sp
	addq.w	#1,d4
	add.w	$2(a2),d5                       ; -> map_cell_w
.loop_test
	cmp.w	#$56,d4
	ble.s	.loop_use_map_cell_h
	sub.w	$2(a2),d5                       ; -> map_cell_w
	move.w	(a2),d6
	clr.w	d4
	bra.s	.loop_test2

.loop_draw_line
	move.w	d6,-(sp)
	move.w	d5,d2
	move.w	d6,d1
	move.w	-$2(a2),d0                      ; -> map_x
	jsr	draw_line(pc)
	addq.w	#2,sp
	addq.w	#1,d4
	add.w	$4(a2),d6                       ; -> map_cell_h
.loop_test2
	cmp.w	#$3,d4
	blt.s	.loop_draw_line
	tst.w	d3
	bne.s	.return
	clr.w	d0
	jsr	show_mouse(pc)
.return
	movem.l	(sp)+,d3-d6/a2
	rts


install_critic:
	suba.l	a0,a0
	jsr	Super(pc)
	move.l	d0,saved_ssp_gem
	lea	critic_xbra,a0
	move.l	$404.w,$8(a0)                   ; etv_critic, -> critic_old
	move.l	#critic_handler,$404.w          ; etv_critic
	movea.l	saved_ssp_gem,a0
	jsr	Super(pc)
	rts


remove_critic:
	suba.l	a0,a0
	jsr	Super(pc)
	move.l	d0,saved_ssp_gem
	move.l	critic_old,$404.w               ; etv_critic
	movea.l	saved_ssp_gem,a0
	jsr	Super(pc)
	rts


;----------------------------------------------------------------------
; Tamper check: sums the characters of ten messages and compares them with the
; sums stored after str_fastcopy_pro; messages_modified is set on a mismatch.
;----------------------------------------------------------------------
check_messages:
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	lea	-$a(sp),sp
	lea	str_fastcopy_pro,a3
	lea	$540(a3),a0                     ; -> message_sums
	lea	(sp),a1
	moveq	#9,d0
.copy_sums
	move.b	(a0)+,(a1)+
	dbra	d0,.copy_sums
	lea	(sp),a2
	clr.w	messages_modified
	move.b	(a2)+,d0
	movea.l	a3,a0
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	$f(a3),a0                       ; -> alert_somebody_overwrote_important
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	$88(a3),a0                      ; -> str_fastcopy_pro_1_2_by_martin
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	$f3(a3),a0                      ; -> ted_00_text
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	$13b(a3),a0                     ; -> about_03_text
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	$147(a3),a0                     ; -> about_04_text
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	$165(a3),a0                     ; -> about_05_text
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	$176(a3),a0                     ; -> about_06_text
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	$18a(a3),a0                     ; -> about_07_text
	jsr	check_message_sum(pc)
	move.b	(a2)+,d0
	lea	guardian_text,a0
	jsr	check_message_sum(pc)
	lea	$a(sp),sp
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


check_message_sum:
	clr.w	d1                              ; byte sum of the string at a0 must be d0
	move.w	d1,d2
	bra.s	.char_test

.add_char
	add.b	$0(a0,d1.w),d2
	addq.w	#1,d1
.char_test
	tst.b	$0(a0,d1.w)
	bne.s	.add_char
	cmp.b	d2,d0
	beq.s	.return
	move.w	#$1,messages_modified
.return
	rts


underline_shortcuts:
	movem.l	d3-d7/a2-a3,-(sp)               ; table: object, letter, parent object; 0 ends it
	subq.w	#6,sp
	movea.l	a0,a3
	move.w	d0,$4(sp)
	move.w	d1,$2(sp)
	movea.l	a1,a2
	movea.l	linea_base,a1
	move.w	$138(a1),d3
	jsr	linea_defaults(pc)
	clr.w	d1
	clr.w	d0
	lea	fill_black,a0
	jsr	set_fill_pattern(pc)
	bra.w	.mark_test

.next_mark
	move.b	(a2)+,d4                        ; position of the object (relative to its parent)
	move.w	d6,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	move.w	$10(a3,d0.l),d7
	add.w	$4(sp),d7
	move.w	$12(a3,d0.l),d5
	add.w	char_baseline,d5
	add.w	$2(sp),d5
	clr.w	d2
	move.b	(a2)+,d2
	move.w	d2,(sp)
	beq.s	.object_text
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	lea	$0(a3,d1.l),a0
	add.w	$10(a0),d7
	add.w	$12(a0),d5
.object_text
	move.w	d6,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	$c(a3,d0.l),a0                  ; find the letter in the object text, any case
	clr.w	d6
.find_letter
	cmp.b	$0(a0,d6.w),d4
	beq.s	.found
	clr.w	d0
	move.b	$0(a0,d6.w),d0
	clr.w	d1
	move.b	d4,d1
	dc.w	$d27c,$ffe0                     ; add.w #$ffe0,d1
	cmp.w	d1,d0
	beq.s	.found
	addq.w	#1,d6
	bra.s	.find_letter

.found
	move.w	d6,d0                           ; underline it
	muls.w	char_width,d0
	add.w	d0,d7
	move.w	d7,d2
	add.w	char_width,d2
	move.w	d5,d1
	move.w	d7,d0
	jsr	horizontal_line(pc)
.mark_test
	clr.w	d6
	move.b	(a2)+,d6
	bne.w	.next_mark
	tst.w	d3
	bne.s	.done
	clr.w	d0
	jsr	show_mouse(pc)
.done
	addq.w	#6,sp
	movem.l	(sp)+,d3-d7/a2-a3
	rts


;----------------------------------------------------------------------
; Save Configuration: writes the 112 bytes from config into FCOPYPRO.PRG or
; FCOPYPRO.ACC, after checking the $2442 mark at the same place in the file.
;----------------------------------------------------------------------
save_config:
	movem.l	d3/a2-a5,-(sp)
	lea	-$e(sp),sp
	lea	alert_cannot_install_the_mouse,a2
	lea	$8a(a2),a0                      ; -> alert_save_configuration_yes_no
	moveq	#1,d0
	jsr	request_alert(pc)
	subq.w	#2,d0
	beq.w	.return                         ; CANCEL
	lea	start_path,a3
	lea	str_fcopypro_xxx,a4
	move.b	-$dd(a4),d0                     ; Get Sectors only means something with Read Disk Config., -> cfg_read_config
	bne.s	.program_path
	move.b	-$1(a3),-$dc(a4)                ; -> used_only_shown, -> cfg_used_only
.program_path
	move.w	is_program,d0                   ; program: start drive and path; accessory: the boot drive and path
	beq.s	.accessory_drive
	move.w	$a1(a3),d0                      ; -> saved_drive
	bra.s	.set_drive

.accessory_drive
	move.w	$a3(a3),d0                      ; -> start_drive
.set_drive
	jsr	Dsetdrv(pc)
	move.w	is_program,d0
	beq.s	.accessory_path
	lea	$20(a3),a0                      ; -> saved_path
	bra.s	.set_path

.accessory_path
	movea.l	a3,a0
.set_path
	jsr	Dsetpath(pc)
	moveq	#3,d0                           ; file name FCOPYPRO.PRG or FCOPYPRO.ACC
	move.l	d0,-(sp)
	move.w	is_program,d1
	beq.s	.acc
	lea	$b1(a2),a1                      ; -> str_prg
	bra.s	.set_extension

.acc
	lea	$b5(a2),a1                      ; -> str_acc
.set_extension
	lea	$9(a4),a0                       ; -> str_fcopypro_xxx+9
	move.l	(sp)+,d0
	jsr	memcpy(pc)
	movea.l	a4,a0                           ; also into the "Cannot access" message
	jsr	strlen(pc)
	movea.l	a4,a1
	lea	-$40(a4),a0                     ; -> alert_cannot_access_xxxxxxxxxxxx+18
	jsr	memcpy(pc)
	lea	$2(sp),a5
	movea.l	a4,a1
	movea.l	a5,a0
	jsr	strcpy(pc)
.open
	moveq	#2,d0                           ; open it
	movea.l	a5,a0
	jsr	Fopen(pc)
	move.w	d0,d3
	bge.s	.check_mark
.not_found
	lea	-$52(a4),a0                     ; "Cannot access FCOPYPRO.XXX! Select the proper path and program file.", -> alert_cannot_access_xxxxxxxxxxxx
	moveq	#1,d0
	jsr	alert(pc)
	move.l	-$21(a3),-(sp)                  ; file selector for the program file, -> main_tree_ptr
	pea	$9(a4)                          ; -> str_fcopypro_xxx+9
	movea.l	a5,a1
	lea	$b9(a2),a0                      ; -> str_save_configuration_into
	jsr	file_selector(pc)
	addq.w	#8,sp
	clr.w	d3
	move.b	d0,d3
	jsr	redraw_status(pc)
	tst.w	d3
	bne.s	.open
	bra.s	.return

.check_mark
	clr.w	d2                              ; seek to the config block in the file (header $1c + offset in the program)
	move.w	d3,d1
	lea	-$140(a4),a0                    ; -> config
	move.l	a0,d0
	dc.w	$90bc                           ; sub.l #start,d0
	dc.l	start
	dc.w	$d0bc                           ; add.l #$1c,d0
	dc.l	$1c
	jsr	Fseek(pc)
	clr.w	(sp)
	lea	(sp),a0
	moveq	#2,d1
	move.w	d3,d0
	jsr	Fread(pc)
	cmpi.w	#$2442,(sp)                     ; must hold the $2442 mark
	beq.s	.write
	move.w	d3,d0
	jsr	Fclose(pc)
	bra.s	.not_found

.write
	moveq	#1,d2                           ; back over the mark and write the 112 bytes
	move.w	d3,d1
	moveq	#-2,d0
	jsr	Fseek(pc)
	lea	-$140(a4),a0                    ; -> config
	moveq	#112,d1
	move.w	d3,d0
	jsr	Fwrite(pc)
	move.w	d3,d0
	jsr	Fclose(pc)
.return
	lea	$e(sp),sp
	movem.l	(sp)+,d3/a2-a5
	rts


file_selector:
	movem.l	d3-d4/a2-a6,-(sp)
	lea	-$92(sp),sp
	movea.l	a0,a6                           ; a0 title, a1 file name, path from the stack
	movea.l	a1,a4
	movea.l	$b6(sp),a5
	movea.l	linea_base,a1
	move.w	$138(a1),d3
	beq.s	.path
	clr.w	d0
	jsr	show_mouse(pc)
.path
	lea	$12(sp),a2                      ; current drive and path plus "\*.*" or the given mask
	jsr	Dgetdrv(pc)
	dc.w	$d03c,$0041                     ; add.b #$41,d0
	move.b	d0,(a2)
	move.b	#$3a,$1(a2)                     ; ':'
	clr.w	d0
	lea	$2(a2),a0
	jsr	Dgetpath(pc)
	lea	str_all_files,a1
	movea.l	a2,a0
	jsr	strcat(pc)
	movea.l	$b2(sp),a1
	movea.l	a2,a0
	jsr	strcat(pc)
	jsr	Fgetdta(pc)
	movea.l	a0,a3
	move.b	tos_104,d0                      ; TOS 1.04 and later: fsel_exinput with title
	beq.s	.old_selector
	move.l	a6,-(sp)
	pea	$4(sp)
	movea.l	a4,a1
	movea.l	a2,a0
	jsr	fsel_exinput(pc)
	addq.w	#8,sp
	move.w	d0,d4
	bra.s	.restore_dta

.old_selector
	pea	(sp)
	movea.l	a4,a1
	movea.l	a2,a0
	jsr	fsel_input(pc)
	addq.w	#4,sp
	move.w	d0,d4
.restore_dta
	movea.l	a3,a0
	jsr	Fsetdta(pc)
	tst.w	d4                              ; cancelled: redraw
	bne.s	.wait_redraw
	clr.w	d0
	movea.l	a5,a0
	jsr	draw_object(pc)
	jsr	linea_defaults(pc)
	bra.w	.mouse

.wait_redraw
	lea	$2(sp),a6                       ; wait for the redraw message of our window and redraw
	movea.l	a6,a0
	jsr	evnt_mesag(pc)
	cmpi.w	#$14,(a6)
	bne.s	.wait_redraw
	move.w	$6(a6),d0
	cmp.w	window_handle,d0
	bne.s	.wait_redraw
	move.w	$e(a6),-(sp)
	move.w	$c(a6),-(sp)
	move.w	$a(a6),-(sp)
	move.w	$8(a6),d2
	moveq	#8,d1
	movea.l	a5,a0
	clr.w	d0
	jsr	objc_draw(pc)
	addq.w	#6,sp
	jsr	linea_defaults(pc)
	move.w	(sp),d0                         ; OK with a name?
	beq.s	.cancelled
	move.b	(a4),d1
	bne.s	.strip_mask
.cancelled
	clr.w	d4
	bra.s	.mouse

.strip_mask
	moveq	#42,d0                          ; cut the mask off the path
	movea.l	a2,a0
	jsr	strchr(pc)
	movea.l	a0,a6
	move.l	a6,d0
	beq.s	.set_path
	cmpi.b	#$3a,-$2(a6)                    ; ':'
	bne.s	.strip_backslash
	clr.b	(a0)
	bra.s	.set_path

.strip_backslash
	clr.b	-$1(a6)
.set_path
	cmpi.b	#$3a,$1(a2)                     ; set drive and path for the file
	bne.s	.path_only
	clr.w	d0
	move.b	(a2),d0
	dc.w	$c07c,$f                        ; and.w #$f,d0
	subq.w	#1,d0
	jsr	Dsetdrv(pc)
	lea	$2(a2),a0
	jsr	Dsetpath(pc)
	bra.s	.selected

.path_only
	movea.l	a2,a0
	jsr	Dsetpath(pc)
.selected
	moveq	#1,d4
.mouse
	tst.w	d3
	beq.s	.done
	jsr	hide_mouse(pc)
.done
	move.b	d4,d0
	lea	$92(sp),sp
	movem.l	(sp)+,d3-d4/a2-a6
	rts


;----------------------------------------------------------------------
; Machine check: TOS version and the _MCH and _FRB cookies.
;----------------------------------------------------------------------
check_machine:
	movem.l	a2-a4,-(sp)
	suba.l	a0,a0
	jsr	Super(pc)
	movea.l	d0,a2
	lea	has_alt_ram,a4
	clr.b	d0
	move.b	d0,$2(a4)                       ; -> tos_104
	move.b	d0,$3(a4)                       ; -> tos_205
	movea.l	$4f2.w,a0                       ; TOS version: 1.04 and later, 2.05 / 3.05
	move.w	$2(a0),d0
	cmp.w	#$104,d0
	bcs.s	.check_205
	move.b	#$1,$2(a4)                      ; -> tos_104
.check_205
	cmp.w	#$205,d0
	beq.s	.tos_205
	cmp.w	#$305,d0
	bne.s	.cookies
.tos_205
	move.b	#$1,$3(a4)                      ; -> tos_205
.cookies
	movea.l	$5a0.w,a3                       ; cookie jar: _MCH (STE and later, TT) and _FRB (alternative RAM)
	clr.b	d0
	move.b	d0,(a4)
	move.b	d0,$1(a4)                       ; -> is_ste
	move.l	a3,d1
	beq.s	.done
	bra.s	.cookie_test

.next_cookie
	lea	str_mch,a1
	movea.l	a3,a0
	jsr	strcmp(pc)
	tst.w	d0
	bne.s	.check_frb
	move.l	$4(a3),d0
	moveq	#16,d1
	asr.l	d1,d0
	cmp.w	#$2,d0
	bne.s	.mch_ste
	move.b	#$1,(a4)
	bra.s	.done

.mch_ste
	cmp.w	#$1,d0
	blt.s	.check_frb
	move.b	#$1,$1(a4)                      ; -> is_ste
.check_frb
	lea	str_frb,a1
	movea.l	a3,a0
	jsr	strcmp(pc)
	tst.w	d0
	bne.s	.next
	move.l	$4(a3),d0
	beq.s	.next
	move.b	#$1,(a4)
.next
	addq.w	#8,a3
.cookie_test
	move.l	(a3),d0
	bne.s	.next_cookie
.done
	movea.l	a2,a0
	jsr	Super(pc)
	movem.l	(sp)+,a2-a4
	rts


deselect_object:
	move.w	d3,-(sp)
	move.l	a2,-(sp)
	movea.l	a0,a2
	move.w	d0,d3
	ext.l	d0
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	lsl.l	#3,d1
	andi.w	#$fffe,$a(a2,d1.l)
	move.w	d3,d0
	jsr	draw_object(pc)
	movea.l	(sp)+,a2
	move.w	(sp)+,d3
	rts


show_help:
	movem.l	d3-d5/a2-a4,-(sp)               ; help text pages are separated by @
	movea.l	a0,a2
	move.l	a2,d0
	beq.w	.return
	movea.l	a2,a3
	clr.b	d3
	bra.s	.page_test

.next_page
	moveq	#64,d0                          ; cut the text at the next @
	movea.l	a3,a0
	jsr	strchr(pc)
	movea.l	a0,a4
	move.l	a4,d0
	beq.s	.last_page
	clr.b	(a0)
	moveq	#1,d4
	bra.s	.has_prev

.last_page
	clr.b	d4
.has_prev
	cmpa.l	a3,a2
	bne.s	.not_first
	clr.b	d5
	bra.s	.show_page

.not_first
	moveq	#1,d5
.show_page
	move.b	d4,d1
	move.b	d5,d0
	movea.l	a3,a0
	jsr	help_alert(pc)                  ; show the page with NEXT, OK, PREV as needed
	move.l	a4,d1
	beq.s	.restore_mark
	move.b	#$40,(a4)                       ; '@'
.restore_mark
	move.w	d0,d1                           ; 1 NEXT, 2 OK, 3 PREV
	subq.w	#1,d1
	beq.s	.forward
	subq.w	#1,d1
	beq.s	.ok
	subq.w	#1,d1
	beq.s	.back_scan
	bra.s	.page_test

.ok
	moveq	#1,d3
	bra.s	.page_test

.forward
	lea	$1(a4),a3
	bra.s	.page_test

.back_scan
	subq.w	#1,a3                           ; PREV: back to the start of the previous page
	cmpi.b	#$40,-$1(a3)                    ; '@'
	beq.s	.page_test
	cmpa.l	a3,a2
	bne.s	.back_scan
.page_test
	tst.b	d3
	beq.s	.next_page
.return
	movem.l	(sp)+,d3-d5/a2-a4
	rts


help_alert:
	movem.l	d3-d6/a2/a4,-(sp)
	lea	-$12c(sp),sp
	movea.l	a0,a4
	move.b	d0,d4
	move.b	d1,d3
	lea	alert_cannot_install_the_mouse,a2 ; "[0][" page "]["
	lea	$e2(a2),a1                      ; -> str_alert_0
	lea	(sp),a0
	jsr	strcpy(pc)
	movea.l	a4,a1
	lea	(sp),a0
	jsr	strcat(pc)
	lea	$e4(a2),a1                      ; -> str_alert_sep
	lea	(sp),a0
	jsr	strcat(pc)
	lea	alert_bell,a4
	tst.b	d3                              ; " NEXT |"
	beq.s	.ok_button
	lea	$15d(a4),a1                     ; -> str_next
	lea	(sp),a0
	jsr	strcat(pc)
	lea	$e7(a2),a1                      ; -> str_bar
	lea	(sp),a0
	jsr	strcat(pc)
.ok_button
	lea	$164(a4),a1                     ; " OK |", -> str_ok_3
	lea	(sp),a0
	jsr	strcat(pc)
	lea	$e7(a2),a1                      ; -> str_bar
	lea	(sp),a0
	jsr	strcat(pc)
	tst.b	d4                              ; " PREV |"
	beq.s	.close_buttons
	lea	$169(a4),a1                     ; -> str_prev
	lea	(sp),a0
	jsr	strcat(pc)
	lea	$e7(a2),a1                      ; -> str_bar
	lea	(sp),a0
	jsr	strcat(pc)
.close_buttons
	lea	(sp),a0                         ; last "|" becomes "]"
	jsr	strlen(pc)
	move.b	#$5d,-$1(sp,d0.w)               ; ']'
	moveq	#-1,d5                          ; ( ) * / in the text become the arrow characters 4 3 2 1
	bra.s	.next_char

.convert
	clr.w	d0
	move.b	d6,d0
	dc.w	$907c,$28                       ; sub.w #$28,d0
	beq.s	.left_arrow
	subq.w	#1,d0
	beq.s	.right_arrow
	subq.w	#1,d0
	beq.s	.down_arrow
	subq.w	#5,d0
	beq.s	.up_arrow
	bra.s	.next_char

.left_arrow
	move.b	#$4,$0(sp,d5.w)
	bra.s	.next_char

.right_arrow
	move.b	#$3,$0(sp,d5.w)
	bra.s	.next_char

.up_arrow
	move.b	#$1,$0(sp,d5.w)
	bra.s	.next_char

.down_arrow
	move.b	#$2,$0(sp,d5.w)
.next_char
	addq.w	#1,d5
	move.b	$0(sp,d5.w),d6
	bne.s	.convert
	move.b	(a4),d6                         ; no PREV on the first page
	tst.b	d4
	beq.s	.show
	clr.b	(a4)
.show
	lea	(sp),a0                         ; show it; the button number is mapped to 1 NEXT, 2 OK, 3 PREV
	moveq	#1,d0
	jsr	alert(pc)
	move.w	d0,d5
	move.b	d6,(a4)
	tst.b	d3
	beq.s	.no_next
	bra.s	.return

.no_next
	tst.b	d4
	beq.s	.only_ok
	moveq	#1,d0
	add.w	d5,d0
	bra.s	.return

.only_ok
	moveq	#2,d0
.return
	lea	$12c(sp),sp
	movem.l	(sp)+,d3-d6/a2/a4
	rts


;----------------------------------------------------------------------
; Forces a media change on drive d0: hooks hdv_bpb, hdv_mediach and hdv_rw,
; opens a file on the drive and restores the vectors.
;----------------------------------------------------------------------
force_media_change:
	move.w	d0,media_drive
	dc.w	$d03c,$0041                     ; add.b #$41,d0
	move.b	d0,str_x_x
	jsr	super_on
	move.l	$472.w,old_hdv_bpb              ; hdv_bpb
	move.l	$47e.w,old_hdv_mediach          ; hdv_mediach
	move.l	$476.w,old_hdv_rw               ; hdv_rw
	move.l	#media_change_bpb,$472.w        ; hdv_bpb
	move.l	#media_change_mediach,$47e.w    ; hdv_mediach
	move.l	#media_change_rw,$476.w         ; hdv_rw
	clr.w	-(sp)
	pea	str_x_x
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	tst.l	d0
	bmi.s	.true
	move.w	d0,-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
.true
	moveq	#1,d7
	cmpi.l	#media_change_bpb,$472.w        ; hdv_bpb
	bne.s	.finish
	moveq	#0,d7
	bsr.s	restore_disk_vectors
.finish
	jsr	super_off
	move.l	d7,d0
	rts

media_change_bpb:
	move.w	media_drive,d0                  ; Getbpb of the drive: vectors back, then on to the old one
	cmp.w	$4(sp),d0
	bne.s	.old_bpb
	bsr.s	restore_disk_vectors
.old_bpb
	movea.l	old_hdv_bpb,a0
	jmp	(a0)


restore_disk_vectors:
	move.l	old_hdv_bpb,$472.w              ; hdv_bpb
	move.l	old_hdv_mediach,$47e.w          ; hdv_mediach
	move.l	old_hdv_rw,$476.w               ; hdv_rw
	rts

media_change_mediach:
	move.w	media_drive,d0                  ; Mediach of the drive: changed (2)
	cmp.w	$4(sp),d0
	bne.s	.old_mediach
	moveq	#2,d0
	rts

.old_mediach
	movea.l	old_hdv_mediach,a0
	jmp	(a0)

media_change_rw:
	move.w	media_drive,d0                  ; Rwabs of the drive: E_CHNG (-14)
	cmp.w	$e(sp),d0
	bne.s	.old_rw
	moveq	#-14,d0
	rts

.old_rw
	movea.l	old_hdv_mediach,a0              ; other drives: on to the old hdv_mediach, not hdv_rw
	jmp	(a0)


mul_words:
	mulu.w	d1,d0
	rts


read_psg_port_bit:
	jsr	super_on                        ; bit d0 of PSG port A
	move.w	sr,d1
	ori.w	#$700,sr
	lea	$ff8800,a0                      ; PSG register select
	move.b	#$e,(a0)
	move.b	(a0),d2
	move.w	d1,sr
	jsr	super_off
	btst	d0,d2
	beq.s	.result_0
	moveq	#1,d0
	rts

.result_0
	moveq	#0,d0
	rts


write_psg_port_bit:
	jsr	super_on                        ; set or clear bit d0 of PSG port A
	move.w	d3,-(sp)
	lea	$ff8800,a0                      ; PSG register select
	move.w	sr,d2
	ori.w	#$700,sr
	move.b	#$e,(a0)
	move.b	(a0),d3
	tst.b	d1
	beq.s	.clear_bit
	bset	d0,d3
	bra.s	.write_port

.clear_bit
	bclr	d0,d3
.write_port
	move.b	d3,$2(a0)
	move.w	d2,sr
	move.w	(sp)+,d3
	jsr	super_off
	rts


;----------------------------------------------------------------------
; Malloc, or Mxalloc(ST RAM) when alternative RAM is present.
;----------------------------------------------------------------------
malloc_st_ram:
	tst.b	has_alt_ram
	bne.s	.has_alt_ram
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	movea.l	d0,a0
	rts

.has_alt_ram
	clr.w	-(sp)
	move.l	d0,-(sp)
	move.w	#$44,-(sp)
	trap	#1                              ; fn 68
	addq.l	#8,sp
	movea.l	d0,a0
	rts


;----------------------------------------------------------------------
; Word run length compression: three or more equal words become $9b8b, word,
; count; the marker word itself is escaped.  Returns the packed size in d0, or copies
; the data unpacked when it does not get smaller.
;----------------------------------------------------------------------
compress:
	movem.l	d4-d7/a2-a5,-(sp)               ; a0 source, a1 destination, d0 bytes; destination ends 6 bytes early for the last code
	lea	$0(a0,d0.l),a2
	lea	$0(a1,d0.l),a3
	lea	-$6(a1,d0.l),a4
	movea.l	a1,a5
	move.w	#$9b8b,d2                       ; marker word
.next_word
	move.w	(a0)+,d6
.check_word
	cmp.w	d2,d6                           ; the marker word itself is written as marker, marker, count 0
	beq.s	.marker
	cmpa.l	a0,a2
	beq.s	.last_word
.literal
	move.w	d6,d7                           ; copy words until two equal ones follow
	move.w	(a0)+,d6
	cmp.w	d2,d6
	beq.s	.marker_after
	cmp.w	d7,d6
	beq.s	.repeat
	cmpa.l	a1,a3
	beq.s	.size
	move.w	d7,(a1)+
	cmpa.l	a0,a2
	bne.s	.literal
.last_word
	move.w	d6,(a1)+
.size
	suba.l	a5,a1                           ; packed size; no gain: copy unpacked
	cmp.l	a1,d0
	bmi.s	.no_gain
	beq.s	.no_gain
	move.l	a1,d0
	movem.l	(sp)+,d4-d7/a2-a5
	rts

.marker_after
	move.w	d7,(a1)+
.marker
	cmpa.l	a1,a4
	bmi.s	.no_gain
	move.w	d2,(a1)+
	move.w	d2,(a1)+
	move.w	d2,d7
	moveq	#0,d5
	bra.s	.count_run

.repeat
	cmpa.l	a1,a4                           ; two equal words: a third makes a run
	bmi.s	.no_gain
	cmpa.l	a0,a2
	beq.s	.pair_at_end
	cmp.w	(a0),d6
	bne.s	.pair
	move.w	d2,(a1)+                        ; run: marker, word, count
	move.w	d6,(a1)+
	moveq	#1,d5
.count_run
	cmpa.l	a0,a2
	beq.s	.run_at_end
	move.w	(a0)+,d6
	cmp.w	d6,d7
	bne.s	.run_end
	addq.w	#1,d5
	bra.s	.count_run

.run_at_end
	move.w	d5,(a1)+
	bra.s	.size

.run_end
	move.w	d5,(a1)+
	bra.s	.check_word

.pair_at_end
	move.w	d6,(a1)+
	move.w	d6,(a1)+
	bra.s	.size

.pair
	move.w	d6,(a1)+                        ; only two: copied as they are
	move.w	d6,(a1)+
	bra.s	.next_word

.no_gain
	suba.l	d0,a2                           ; no gain: copy the data unpacked and return its size
	movea.l	a2,a0
	movea.l	a5,a1
	movem.l	(sp)+,d4-d7/a2-a5
	bra.s	copy_block


;----------------------------------------------------------------------
; Unpacks data packed by compress.
;----------------------------------------------------------------------
decompress:
	cmp.l	d1,d0                           ; same size: the block was stored unpacked
	beq.s	copy_block
	move.w	d2,-(sp)
	move.l	d3,-(sp)
	lsr.l	#1,d0
	subq.l	#1,d0
	bmi.s	.done
	move.w	#$9b8b,d2
.next_word
	move.w	(a0)+,(a1)                      ; copy words until the marker
	cmp.w	(a1)+,d2
	dbeq	d0,.next_word
	bne.s	.done
	subq.l	#2,a1
	move.w	(a0)+,d1                        ; marker: word, count; repeat the word count + 1 times
	move.w	(a0)+,d3
	subq.w	#2,d0
.repeat
	move.w	d1,(a1)+
	dbra	d3,.repeat
	dbra	d0,.next_word
.done
	move.l	(sp)+,d3
	move.w	(sp)+,d2
	rts

copy_block:
	movem.l	d0/d2-d7/a2-a6,-(sp)            ; copies d0 bytes, a multiple of 512, from a0 to a1
.copy_512
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$30(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$60(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$90(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$c0(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$f0(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$120(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$150(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$180(a1)
	movem.l	(a0)+,d1-d7/a2-a6
	movem.l	d1-d7/a2-a6,$1b0(a1)
	movem.l	(a0)+,d1-d7/a2
	movem.l	d1-d7/a2,$1e0(a1)
	lea	$200(a1),a1
	dc.w	$90bc                           ; sub.l #$200,d0
	dc.l	$200
	bne.s	.copy_512
	movem.l	(sp)+,d0/d2-d7/a2-a6
	rts


low_memory_free:
	jsr	super_on
	move.w	$60c.w,d0
	jsr	super_off
	tst.w	d0
	beq.s	.result_1
	cmp.w	#$4242,d0
	beq.s	.result_1
	moveq	#0,d0
	rts

.result_1
	moveq	#1,d0
	rts


;----------------------------------------------------------------------
; Mouse accelerator: mouse_handler is copied to $600 and hooked into the IKBD
; mouse vector (Kbdvbase) with the XBRA id FCMS.
;----------------------------------------------------------------------
remove_mouse_accel:
	movem.l	d1-d7/a0-a6,-(sp)
	lea	unhook_mousevec,a4
	bra.s	mouse_accel_super


install_mouse_accel:
	bsr.s	remove_mouse_accel
	movem.l	d1-d7/a0-a6,-(sp)
	lea	hook_mousevec,a4
mouse_accel_super:
	move.w	#$22,-(sp)
	trap	#14                             ; Kbdvbase
	movea.l	d0,a3
	move.l	a4,-(sp)
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.l	#8,sp
	movem.l	(sp)+,d1-d7/a0-a6
	rts

unhook_mousevec:
	cmpi.l	#$46434d53,$604.w
	bne.s	.finish
	move.l	$608.w,d0
	beq.s	.finish
	move.l	d0,$10(a3)
.finish
	clr.l	$604.w
	rts

hook_mousevec:
	lea	mouse_xbra(pc),a0
	lea	options_dialog(pc),a1
	lea	$600.w,a2
.loop_test
	move.w	(a0)+,(a2)+
	cmpa.l	a0,a1
	bne.s	.loop_test
	movea.l	$10(a3),a1
	move.l	a1,$608.w
	move.l	#$60e,$10(a3)
	rts

mouse_xbra:
	dc.b	'XBRAFCMS'
mouse_old:
	dc.w	$0000,$0000

;----------------------------------------------------------------------
; Mouse accelerator, runs at $600: relative mouse packets moving more than 2
; pixels are multiplied by their size (up to 7).
;----------------------------------------------------------------------
mouse_handler:
	clr.w	d2
	movem.l	d0-d2/a0,-(sp)
	cmpi.b	#$f8,(a0)                       ; relative mouse packet ($f8..$fb)?
	bcs.s	.old_handler
	cmpi.b	#$fc,(a0)+
	bcc.s	.old_handler
	move.b	(a0)+,d0
	move.b	(a0)+,d1
	cmpi.b	#$2,d0                          ; x: more than 2 pixels: times its size (up to 7)
	bls.s	.check_y
	move.b	d0,d2
	bpl.s	.scale_x
	neg.b	d2
.scale_x
	dc.w	$c47c,$7                        ; and.w #$7,d2
	mulu.w	d2,d0
.check_y
	cmpi.b	#$2,d1                          ; y the same
	bls.s	.store
	move.b	d1,d2
	bpl.s	.scale_y
	neg.b	d2
.scale_y
	dc.w	$c47c,$7                        ; and.w #$7,d2
	mulu.w	d2,d1
.store
	move.b	d1,-(a0)
	move.b	d0,-(a0)
.old_handler
	movem.l	(sp)+,d0-d2/a0
	move.l	mouse_old(pc),-(sp)             ; on to the old mouse vector
	rts


;----------------------------------------------------------------------
; More Options dialog (options_tree).
;----------------------------------------------------------------------
options_dialog:
	movem.l	d3/a2-a5,-(sp)
	lea	-$7a(sp),sp
	lea	options_tree_ptr,a2
	move.l	#options_tree,(a2)              ; all buttons from the configuration:
	moveq	#73,d3                          ; HD detection radio buttons 73..77
	bra.s	.detect_test

.clear_detect
	move.w	d3,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	clr.w	$a(a0,d0.l)
	addq.w	#1,d3
.detect_test
	cmp.w	#$4d,d3
	ble.s	.clear_detect
	lea	config,a3
	clr.w	d1
	move.b	$50(a3),d1                      ; -> cfg_hd_detect
	dc.w	$d27c,$49                       ; add.w #$49,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	move.w	#$1,$a(a0,d0.l)
	move.b	$62(a3),d0                      ; Fast Format, Fast Access headers, -> cfg_fast_format
	beq.s	.no_fast_format
	moveq	#1,d1
	bra.s	.fast_format

.no_fast_format
	clr.w	d1
.fast_format
	movea.l	(a2),a0
	move.w	d1,$12a(a0)
	move.b	$51(a3),d0                      ; -> cfg_fast_access
	beq.s	.no_fast_access
	moveq	#1,d2
	bra.s	.fast_access

.no_fast_access
	clr.w	d2
.fast_access
	movea.l	(a2),a0
	move.w	d2,$15a(a0)
	moveq	#44,d3                          ; drive A: density 44..46, step rate 48..51, sides 40/41
	bra.s	.a_density_test

.clear_a_density
	move.w	d3,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	clr.w	$a(a0,d0.l)
	addq.w	#1,d3
.a_density_test
	cmp.w	#$2e,d3
	ble.s	.clear_a_density
	moveq	#48,d3
	bra.s	.a_rate_test

.clear_a_rate
	move.w	d3,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	clr.w	$a(a0,d0.l)
	addq.w	#1,d3
.a_rate_test
	cmp.w	#$33,d3
	ble.s	.clear_a_rate
	move.l	d0,-(sp)
	move.b	$48(a3),d0                      ; -> cfg_a_double_sided
	bne.s	.a_single
	moveq	#1,d1
	bra.s	.a_sides

.a_single
	clr.w	d1
.a_sides
	dc.w	$d27c,$28                       ; add.w #$28,d1
	ext.l	d1
	move.l	(sp)+,d0
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	clr.w	$a(a0,d0.l)
	moveq	#1,d0
	clr.w	d2
	move.b	$49(a3),d2                      ; -> cfg_a_density
	dc.w	$d47c,$2c                       ; add.w #$2c,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a2),a0
	move.w	d0,$a(a0,d1.l)
	clr.w	d2
	move.b	$48(a3),d2                      ; -> cfg_a_double_sided
	dc.w	$d47c,$28                       ; add.w #$28,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a2),a0
	move.w	d0,$a(a0,d1.l)
	clr.w	d2
	move.b	$4c(a3),d2                      ; -> cfg_a_step_rate
	dc.w	$d47c,$30                       ; add.w #$30,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a2),a0
	move.w	d0,$a(a0,d1.l)
	move.b	has_drive_b,d1                  ; no drive B: its buttons disabled
	bne.s	.drive_b
	moveq	#8,d2
	movea.l	(a2),a0
	move.w	d2,$5da(a0)
	movea.l	(a2),a0
	move.w	d2,$5c2(a0)
	movea.l	(a2),a0
	move.w	d2,$5aa(a0)
	movea.l	(a2),a0
	move.w	d2,$562(a0)
	movea.l	(a2),a0
	move.w	d2,$54a(a0)
	movea.l	(a2),a0
	move.w	d2,$652(a0)
	movea.l	(a2),a0
	move.w	d2,$63a(a0)
	movea.l	(a2),a0
	move.w	d2,$622(a0)
	movea.l	(a2),a0
	move.w	d2,$60a(a0)
	bra.w	.checkboxes

.drive_b
	moveq	#64,d3                          ; drive B: step rate 64..67, density 60..62, sides 56/57
	bra.s	.b_rate_test

.clear_b_rate
	move.w	d3,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	clr.w	$a(a0,d0.l)
	addq.w	#1,d3
.b_rate_test
	cmp.w	#$43,d3
	ble.s	.clear_b_rate
	moveq	#60,d3
	bra.s	.b_density_test

.clear_b_density
	move.w	d3,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	clr.w	$a(a0,d0.l)
	addq.w	#1,d3
.b_density_test
	cmp.w	#$3e,d3
	ble.s	.clear_b_density
	move.l	d0,-(sp)
	move.b	$4a(a3),d0                      ; -> cfg_b_double_sided
	bne.s	.b_single
	moveq	#1,d1
	bra.s	.b_sides

.b_single
	clr.w	d1
.b_sides
	dc.w	$d27c,$38                       ; add.w #$38,d1
	ext.l	d1
	move.l	(sp)+,d0
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	clr.w	$a(a0,d0.l)
	moveq	#1,d0
	clr.w	d2
	move.b	$4b(a3),d2                      ; -> cfg_b_density
	dc.w	$d47c,$3c                       ; add.w #$3c,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a2),a0
	move.w	d0,$a(a0,d1.l)
	clr.w	d2
	move.b	$4a(a3),d2                      ; -> cfg_b_double_sided
	dc.w	$d47c,$38                       ; add.w #$38,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a2),a0
	move.w	d0,$a(a0,d1.l)
	clr.w	d2
	move.b	$4d(a3),d2                      ; -> cfg_b_step_rate
	dc.w	$d47c,$40                       ; add.w #$40,d2
	ext.l	d2
	move.l	d2,d1
	add.l	d1,d1
	add.l	d2,d1
	lsl.l	#3,d1
	movea.l	(a2),a0
	move.w	d0,$a(a0,d1.l)
.checkboxes
	movea.l	(a2),a0                         ; Mouse Accelerator, Show Request Boxes, Use Sound, Optimize Partition, Compack
	andi.w	#$fffe,$202(a0)
	move.b	$55(a3),d0                      ; -> cfg_mouse_accel
	beq.s	.no_request_boxes
	moveq	#1,d1
	bra.s	.request_boxes

.no_request_boxes
	clr.w	d1
.request_boxes
	movea.l	(a2),a0
	or.w	d1,$202(a0)
	move.b	$54(a3),d0                      ; -> cfg_request_boxes
	beq.s	.no_sound
	moveq	#1,d1
	bra.s	.sound

.no_sound
	clr.w	d1
.sound
	movea.l	(a2),a0
	move.w	d1,$1a2(a0)
	move.b	$56(a3),d0                      ; -> cfg_sound
	beq.s	.no_optimize
	moveq	#1,d2
	bra.s	.optimize

.no_optimize
	clr.w	d2
.optimize
	movea.l	(a2),a0
	move.w	d2,$1d2(a0)
	move.b	$53(a3),d0                      ; -> cfg_optimize_partition
	beq.s	.no_compack
	moveq	#1,d1
	bra.s	.compack

.no_compack
	clr.w	d1
.compack
	movea.l	(a2),a0
	move.w	d1,$6a(a0)
	move.b	$52(a3),d0                      ; -> cfg_compack
	beq.s	.ext_memory_state
	moveq	#1,d2
	bra.s	.ext_memory_disabled

.ext_memory_state
	clr.w	d2
.ext_memory_disabled
	movea.l	(a2),a0
	move.w	d2,$3a(a0)
	move.b	no_hard_disk,d0                 ; Use Harddisk as Extended Memory, disabled without hard disk
	beq.s	.ext_memory_check
	moveq	#8,d1
	bra.s	.set_ext_memory

.ext_memory_check
	move.b	$5b(a3),d0                      ; -> cfg_ext_memory
	beq.s	.ext_memory_off
	moveq	#1,d1
	bra.s	.set_ext_memory

.ext_memory_off
	clr.w	d1
.set_ext_memory
	movea.l	(a2),a0
	move.w	d1,$9a(a0)
	move.b	no_hard_disk,d0
	beq.s	.ext_memory_letter
	movea.l	(a2),a0
	move.w	#$8,$b2(a0)
.ext_memory_letter
	moveq	#65,d0                          ; partition letter in "Current Partition is A:"
	add.b	$5c(a3),d0                      ; -> cfg_ext_memory_drive
	movea.l	(a2),a0
	movea.l	$e4(a0),a1
	move.b	d0,$15(a1)
	jsr	update_ext_memory
	moveq	#31,d1                          ; retries and reserve
	movea.l	(a2),a0
	clr.w	d0
	move.b	$57(a3),d0                      ; -> cfg_retries
	jsr	set_two_digits
	moveq	#10,d1
	movea.l	(a2),a0
	movea.l	$294(a0),a1
	movea.l	(a1),a0
	move.w	$4e(a3),d0                      ; -> cfg_reserve_kb
	jsr	itoa
	movea.l	a3,a0                           ; keep the configuration for CANCEL
	lea	$a(sp),a1
	moveq	#27,d0
.save_config
	move.l	(a0)+,(a1)+
	dbra	d0,.save_config
	pea	(sp)                            ; show the dialog
	pea	$6(sp)
	pea	$c(sp)
	lea	$12(sp),a1
	movea.l	(a2),a0
	jsr	form_center
	lea	$c(sp),sp
	clr.w	d0
	movea.l	(a2),a0
	jsr	draw_object
	lea	str_select_drive_for_ext_memory,a5 ; underline the shortcuts
	lea	-$14e(a5),a1                    ; -> underlines_options
	movea.l	(a2),a0
	move.w	$12(a0),d1
	move.w	$10(a0),d0
	jsr	underline_shortcuts
.ask
	lea	$8(sp),a4                       ; form_do
	pea	-$e6(a5)                        ; -> str_configure_drive_a_b_s_sides_d
	lea	-$123(a5),a1                    ; -> keys_options
	moveq	#27,d0
	movea.l	(a2),a0
	jsr	form_do
	addq.w	#4,sp
	move.w	d0,d3
	moveq	#7,d1                           ; objects: 6 extended memory, 10 Select, 19 sound, 21 mouse, 30 retries -, 32 +, 34 OK, 37 CANCEL
	lea	.table(pc),a0
.clicked_test
	cmp.w	(a0)+,d0
	dbeq	d1,.clicked_test
	bne.s	.ask
	move.w	$e(a0),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	$6,$a,$13,$15,$1e,$20,$22,$25
	dc.w	.ext_memory-.table,.select_partition-.table,.sound2-.table,.mouse_accel-.table
	dc.w	.retries_down-.table,.retries_up-.table,.ok-.table,.cancel-.table
.retries_up
	movea.l	(a2),a0                         ; retries +, at most 99
	movea.l	$2f4(a0),a1
	movea.l	(a1),a0
	jsr	atoi
	move.w	d0,(a4)
	cmp.w	#$63,d0
	blt.s	.retries_add
	move.w	#$63,(a4)
.retries_limit
	moveq	#7,d0
	jsr	Cconout
	bra.s	.show_retries

.retries_add
	addq.w	#1,(a4)
.show_retries
	moveq	#31,d1
	movea.l	(a2),a0
	move.w	(a4),d0
	jsr	set_two_digits
	move.w	d3,d0
	movea.l	(a2),a0
	jsr	deselect_object
	moveq	#31,d0
	movea.l	(a2),a0
	jsr	draw_object
	bra.w	.ask

.retries_down
	movea.l	(a2),a0                         ; retries -, at least 0
	movea.l	$2f4(a0),a1
	movea.l	(a1),a0
	jsr	atoi
	move.w	d0,(a4)
	beq.s	.retries_limit
	subq.w	#1,(a4)
	bra.s	.show_retries

.ext_memory
	moveq	#1,d0                           ; Use Harddisk as Extended Memory: choose the partition
	movea.l	(a2),a0
	and.b	$9b(a0),d0
	move.b	d0,$5b(a3)                      ; -> cfg_ext_memory
	beq.s	.show_ext_memory
	movea.l	a0,a1
	moveq	#8,d2
	movea.l	a5,a0
	clr.w	d1
	move.b	$5c(a3),d1                      ; -> cfg_ext_memory_drive
	moveq	#1,d0
	jsr	select_drive
	move.w	d0,(a4)
	bne.s	.set_ext_drive
	movea.l	a4,a1
	moveq	#1,d1
	movea.l	(a2),a0
	moveq	#6,d0
	jsr	form_button
	bra.s	.ext_memory

.set_ext_drive
	move.b	$1(a4),d0
	dc.w	$d03c,$00ff                     ; add.b #$ff,d0
	move.b	d0,$5c(a3)                      ; -> cfg_ext_memory_drive
	moveq	#65,d1
	add.b	d0,d1
	movea.l	(a2),a0
	movea.l	$e4(a0),a1
	move.b	d1,$15(a1)
.show_ext_memory
	jsr	update_ext_memory
	moveq	#8,d0
	movea.l	(a2),a0
	jsr	draw_object
	bra.w	.ask

.select_partition
	movea.l	(a2),a1                         ; Select: choose the partition
	moveq	#8,d2
	movea.l	a5,a0
	clr.w	d1
	move.b	$5c(a3),d1                      ; -> cfg_ext_memory_drive
	moveq	#1,d0
	jsr	select_drive
	move.w	d0,(a4)
	bne.s	.set_ext_drive
	movea.l	(a2),a0
	moveq	#10,d0
	jsr	deselect_object
	bra.w	.ask

.sound2
	moveq	#1,d0                           ; Use Sound: keyclick and bell now
	movea.l	(a2),a0
	and.b	$1d3(a0),d0
	move.b	d0,$56(a3)                      ; -> cfg_sound
	jsr	set_keyclick
	bra.w	.ask

.mouse_accel
	moveq	#1,d0                           ; Mouse Accelerator: install or remove now
	movea.l	(a2),a0
	and.b	$203(a0),d0
	move.b	d0,$55(a3)                      ; -> cfg_mouse_accel
	jsr	set_mouse_accel
	bra.w	.ask

.cancel
	lea	$a(sp),a0                       ; CANCEL: configuration back
	movea.l	a3,a1
	moveq	#27,d0
.restore_config
	move.l	(a0)+,(a1)+
	dbra	d0,.restore_config
	jsr	set_mouse_accel
	jsr	set_keyclick
	bra.s	.close

.ok
	moveq	#77,d1                          ; OK: buttons into the configuration
	moveq	#73,d0
	movea.l	(a2),a0
	jsr	first_selected
	dc.w	$d03c,$00b7                     ; add.b #$b7,d0
	move.b	d0,$50(a3)                      ; -> cfg_hd_detect
	movea.l	(a2),a0
	movea.l	$2f4(a0),a1
	movea.l	(a1),a0
	jsr	atoi
	move.b	d0,$57(a3)                      ; -> cfg_retries
	moveq	#1,d1
	movea.l	(a2),a0
	and.b	$3b(a0),d1
	move.b	d1,$52(a3)                      ; -> cfg_compack
	moveq	#1,d0
	and.b	$6b(a0),d0
	move.b	d0,$53(a3)                      ; -> cfg_optimize_partition
	moveq	#1,d2
	and.b	$1a3(a0),d2
	move.b	d2,$54(a3)                      ; -> cfg_request_boxes
	moveq	#1,d1
	and.b	$12b(a0),d1
	move.b	d1,$62(a3)                      ; -> cfg_fast_format
	moveq	#1,d0
	and.b	$15b(a0),d0
	move.b	d0,$51(a3)                      ; -> cfg_fast_access
	jsr	read_options
	movea.l	(a2),a0
	movea.l	$294(a0),a1
	movea.l	(a1),a0
	jsr	atoi
	move.w	d0,$4e(a3)                      ; -> cfg_reserve_kb
	jsr	show_options
.close
	move.w	d3,d1                           ; close: redraw the main dialog
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	(a2),a0
	andi.w	#$fffe,$a(a0,d0.l)
	clr.b	window_open
	jsr	update_smart_format
	move.b	#$1,window_open
	clr.w	d0
	movea.l	main_tree_ptr,a0
	jsr	draw_object
	lea	$7a(sp),sp
	movem.l	(sp)+,d3/a2-a5
	rts


read_options:
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	lea	options_tree_ptr,a2
	lea	config,a3
	moveq	#1,d0
	movea.l	(a2),a0
	and.b	$3e3(a0),d0
	move.b	d0,$48(a3)                      ; -> cfg_a_double_sided
	moveq	#46,d1
	moveq	#44,d0
	jsr	first_selected
	dc.w	$d03c,$00d4                     ; add.b #$d4,d0
	move.b	d0,$49(a3)                      ; -> cfg_a_density
	moveq	#51,d1
	movea.l	(a2),a0
	moveq	#48,d0
	jsr	first_selected
	dc.w	$d03c,$00d0                     ; add.b #$d0,d0
	move.b	d0,$4c(a3)                      ; -> cfg_a_step_rate
	move.b	has_drive_b,d1
	beq.s	.set_step_rates
	moveq	#1,d2
	movea.l	(a2),a0
	and.b	$563(a0),d2
	move.b	d2,$4a(a3)                      ; -> cfg_b_double_sided
	moveq	#60,d0
	moveq	#62,d1
	jsr	first_selected
	dc.w	$d03c,$00c4                     ; add.b #$c4,d0
	move.b	d0,$4b(a3)                      ; -> cfg_b_density
	moveq	#67,d1
	movea.l	(a2),a0
	moveq	#64,d0
	jsr	first_selected
	dc.w	$d03c,$00c0                     ; add.b #$c0,d0
	move.b	d0,$4d(a3)                      ; -> cfg_b_step_rate
.set_step_rates
	jsr	set_step_rates
	movea.l	(sp)+,a3
	movea.l	(sp)+,a2
	rts


show_options:
	movem.l	a2-a4,-(sp)
	movea.l	main_tree_ptr,a2
	lea	config,a3
	move.b	has_drive_b,d0
	bne.s	.use_a_double_sided
	clr.b	d1
	move.b	d1,$4b(a3)                      ; -> cfg_b_density
	move.b	d1,$4a(a3)                      ; -> cfg_b_double_sided
.use_a_double_sided
	lea	mouse_state,a4
	clr.w	d0
	move.b	$48(a3),d0                      ; -> cfg_a_double_sided
	clr.w	d1
	move.b	$4a(a3),d1                      ; -> cfg_b_double_sided
	add.w	d1,d0
	bne.s	.use_a_density
	movea.l	a4,a1
	movea.l	main_tree_ptr,a0
	moveq	#56,d0
	moveq	#1,d1
	jsr	form_button
	move.w	#$8,$562(a2)
	bra.s	.use_a_density2

.use_a_density
	andi.w	#$fff7,$562(a2)
.use_a_density2
	clr.w	d0
	move.b	$49(a3),d0                      ; -> cfg_a_density
	clr.w	d1
	move.b	$4b(a3),d1                      ; -> cfg_b_density
	add.w	d1,d0
	bne.s	.read_config_fields
	movea.l	a4,a1
	movea.l	main_tree_ptr,a0
	moveq	#71,d0
	moveq	#1,d1
	jsr	form_button
	move.w	#$8,$6ca(a2)
	bra.s	.read_config_fields2

.read_config_fields
	andi.w	#$fff7,$6ca(a2)
.read_config_fields2
	jsr	read_config_fields
	movem.l	(sp)+,a2-a4
	rts


update_ext_memory:
	lea	options_tree_ptr,a0
	move.b	cfg_ext_memory,d0
	beq.s	.no_ext_memory
	movea.l	(a0),a1
	clr.w	$fa(a1)
	movea.l	(a0),a1
	clr.w	$e2(a1)
	rts

.no_ext_memory
	movea.l	(a0),a1
	move.w	#$8,$fa(a1)
	movea.l	(a0),a1
	move.w	#$8,$e2(a1)
	rts


set_mouse_accel:
	move.b	mouse_accel_ok,d0
	beq.s	.return
	move.b	cfg_mouse_accel,d1
	beq.s	.remove_mouse_accel
	jsr	install_mouse_accel
	rts

.remove_mouse_accel
	jsr	remove_mouse_accel
.return
	rts


set_keyclick:
	move.l	d3,-(sp)
	suba.l	a0,a0
	jsr	Super
	move.l	d0,d3
	move.b	$484.w,d0                       ; conterm
	move.b	cfg_sound,d1
	beq.s	.super
	dc.w	$803c,$0005                     ; or.b #$5,d0
	bra.s	.super2

.super
	dc.w	$c03c,$00fa                     ; and.b #$fa,d0
.super2
	move.b	d0,$484.w                       ; conterm
	movea.l	d3,a0
	jsr	Super
	move.l	(sp)+,d3
	rts


;----------------------------------------------------------------------
; Directory display of drive d0 in list_tree, with the slider and the parent
; entry.
;----------------------------------------------------------------------
show_directory:
	movem.l	d3/a2-a3,-(sp)
	lea	list_tree_ptr,a3
	move.w	d0,$26(a3)                      ; drive, -> dir_drive
	lea	alert_x_source_disk_dir_abort,a2
	cmp.w	#$2,d0                          ; floppy: "X: Source Disk [DIR|ABORT]" (request boxes)
	bge.s	.place_box
	moveq	#65,d1
	add.b	d0,d1
	move.b	d1,$5(a2)                       ; -> alert_x_source_disk_dir_abort+5
	movea.l	a2,a0
	moveq	#1,d0
	jsr	request_alert
	subq.w	#2,d0
	beq.w	.quit
.place_box
	move.l	#list_tree,(a3)                 ; center list_tree in the work area and take its geometry
	movea.l	(a3),a0
	move.w	$14(a0),$10(a3)                 ; -> list_tree_w
	movea.l	(a3),a0
	move.w	$16(a0),$12(a3)                 ; -> list_tree_h
	move.w	work_w,d0
	sub.w	$10(a3),d0                      ; -> list_tree_w
	ext.l	d0
	divs.w	#$2,d0
	add.w	work_x,d0
	movea.l	(a3),a0
	move.w	d0,$10(a0)
	move.w	d0,$c(a3)                       ; -> list_tree_x
	move.w	work_h,d1
	sub.w	$12(a3),d1                      ; -> list_tree_h
	ext.l	d1
	divs.w	#$2,d1
	add.w	work_y,d1
	movea.l	(a3),a0
	move.w	d1,$12(a0)
	move.w	d1,$e(a3)                       ; -> list_tree_y
	movea.l	(a3),a0
	move.w	$88(a0),$14(a3)                 ; -> list_left
	movea.l	(a3),a0
	move.w	$8c(a0),$1e(a3)                 ; -> list_margin
	movea.l	(a3),a0
	move.w	$a0(a0),d0
	add.w	$1e(a3),d0                      ; -> list_margin
	sub.w	$14(a3),d0                      ; -> list_left
	move.w	d0,$1a(a3)                      ; -> list_width
	movea.l	(a3),a0
	move.w	$8e(a0),$1c(a3)                 ; -> list_line_h
	movea.l	(a3),a0
	move.w	$70(a0),d0
	add.w	$c(a3),d0                       ; -> list_tree_x
	add.w	d0,$14(a3)                      ; -> list_left
	move.w	$14(a3),d0                      ; -> list_left
	add.w	$1a(a3),d0                      ; -> list_width
	sub.w	$1e(a3),d0                      ; -> list_margin
	move.w	d0,$16(a3)                      ; -> list_right
	movea.l	(a3),a0
	move.w	$8a(a0),d1
	add.w	$72(a0),d1
	add.w	$e(a3),d1                       ; -> list_tree_y
	move.w	d1,$18(a3)                      ; -> list_x
	jsr	read_directory                  ; read the directory
	tst.w	d0
	beq.w	.quit
.draw_box
	clr.w	d0                              ; draw the box and the frames of the 12 lines
	movea.l	(a3),a0
	jsr	draw_object
	clr.w	d3
	bra.s	.frame_test

.next_frame
	move.w	d3,d0
	addq.w	#1,d3
	jsr	draw_list_frame
.frame_test
	cmp.w	#$c,d3
	blt.s	.next_frame
.ask
	pea	$33(a2)                         ; form_do with the shortcuts and help text, -> str_scroll_up_scroll_down_esc_re
	lea	$26(a2),a1                      ; -> keys_directory
	clr.w	d0
	movea.l	(a3),a0
	jsr	form_do
	addq.w	#4,sp
	move.w	d0,d3
	lea	mouse_state,a1
	moveq	#1,d1
	movea.l	(a3),a0
	jsr	form_button
	move.w	d3,d0                           ; objects: 2 re-read (Esc), 3 quit, 17 up, 18 slider bar, 19 slider, 20 down, 5..16 lines
	subq.w	#2,d0
	cmp.w	#$12,d0
	bhi.s	.entry_clicked
	add.w	d0,d0
	move.w	.table(pc,d0.w),d0
	jmp	.table(pc,d0.w)

.table
	dc.w	.reread-.table,.quit-.table,.entry_clicked-.table,.entry_clicked-.table
	dc.w	.entry_clicked-.table,.entry_clicked-.table,.entry_clicked-.table,.entry_clicked-.table
	dc.w	.entry_clicked-.table,.entry_clicked-.table,.entry_clicked-.table,.entry_clicked-.table
	dc.w	.entry_clicked-.table,.entry_clicked-.table,.entry_clicked-.table,.line_up-.table
	dc.w	.page-.table,.drag-.table,.line_down-.table
.page
	jsr	page_directory                  ; click into the slider bar: a page up or down
	bra.s	.ask

.drag
	jsr	drag_slider                     ; drag the slider
	bra.s	.ask

.line_up
	moveq	#-2,d0                          ; up arrow: two entries up
	add.w	$22(a3),d0                      ; -> dir_top
	jsr	scroll_directory
	bra.s	.ask

.line_down
	moveq	#2,d0                           ; down arrow: two entries down
	add.w	$22(a3),d0                      ; -> dir_top
	jsr	scroll_directory
	bra.w	.ask

.reread
	jsr	read_directory                  ; Esc: read the directory again
	tst.w	d0
	bne.w	.draw_box
	bra.s	.quit

.entry_clicked
	move.w	$22(a3),d0                      ; a line: enter the directory (or the parent), -> dir_top
	add.w	d3,d0
	subq.w	#5,d0
	jsr	enter_directory
	bra.w	.ask

.quit
	movem.l	(sp)+,d3/a2-a3
	rts


select_partition:
	move.w	d3,-(sp)
	move.w	d0,d3
	subq.w	#2,d0                           ; floppy: Rwabs mode 2 marks it as changed
	bge.s	.hard_disk
	move.w	d3,-(sp)
	clr.w	d2
	moveq	#2,d1
	suba.l	a0,a0
	clr.w	d0
	jsr	Rwabs
	addq.w	#2,sp
	bra.s	.set_path

.hard_disk
	move.w	d3,d0                           ; hard disk: force a media change
	jsr	force_media_change
.set_path
	moveq	#65,d0                          ; drive and root path "X:\"
	add.b	d3,d0
	move.b	d0,str_a
	move.w	d3,d0
	jsr	Dsetdrv
	lea	str_a+2,a0
	jsr	Dsetpath
	move.w	(sp)+,d3
	rts


read_directory:
	movem.l	d3-d4/a2-a6,-(sp)
	lea	-$a(sp),sp
	lea	dfree_info,a5
	lea	dir_path_ptr,a2
	lea	str_bytes,a6
	cmpi.w	#$2,$22(a2)                     ; floppy: read its configuration first, -> dir_drive
	bge.s	.free_space
	moveq	#1,d1
	move.w	$22(a2),d0                      ; -> dir_drive
	movea.l	buffer_free,a0
	jsr	read_disk_config
	tst.w	d0
	bne.s	.failed
.free_space
	move.w	$22(a2),d0                      ; Dfree, -> dir_drive
	jsr	select_partition(pc)
	clr.w	d0
	movea.l	a5,a0
	jsr	Dfree
	tst.w	d0
	bge.s	.build_title
	lea	-$b5(a6),a0                     ; "Can't read directory! Please check your disk!", -> alert_cant_read_directory_please
	moveq	#1,d0
	jsr	alert
.failed
	clr.w	d0
	bra.w	.return

.build_title
	move.l	buffer_free,(a2)                ; path buffer, title line and the entry list in the free memory
	movea.l	(a2),a3
	lea	$100(a3),a3
	lea	$50(a3),a0
	move.l	a0,$4(a2)                       ; -> dir_list_ptr
	lea	str_name,a4
	movea.l	a4,a1                           ; title "Name: <volume label>    nnn Bytes (nn%) used    nnn Bytes (nn%) free"
	movea.l	a3,a0
	jsr	strcpy
	lea	-$7(a6),a1                      ; -> str_a
	movea.l	(a2),a0
	jsr	strcpy
	moveq	#8,d0                           ; volume label: Fsfirst with attribute 8
	movea.l	(a2),a0
	jsr	Fsfirst
	tst.w	d0
	bne.s	.no_label
	lea	dta+d_fname,a1
	movea.l	a3,a0
	jsr	strcat
	bra.s	.sizes

.no_label
	lea	$7(a4),a1                       ; -> str_dash
	movea.l	a3,a0
	jsr	strcat
.sizes
	lea	$9(a4),a1                       ; -> str_spaces
	movea.l	a3,a0
	jsr	strcat
	move.l	$8(a5),d0                       ; total and free bytes from the Dfree values, -> dfree_info+b_secsiz
	move.l	$c(a5),d1                       ; -> dfree_info+b_clsiz
	jsr	lmul
	move.l	$4(a5),d1                       ; -> dfree_info+b_total
	jsr	lmul
	move.l	d0,d3
	move.l	$8(a5),d0                       ; -> dfree_info+b_secsiz
	move.l	$c(a5),d1                       ; -> dfree_info+b_clsiz
	jsr	lmul
	move.l	(a5),d1
	jsr	lmul
	move.l	d0,d4
	moveq	#10,d1
	lea	(sp),a0
	move.l	d3,d0
	sub.l	d4,d0
	jsr	ltoa
	lea	(sp),a1
	movea.l	a3,a0
	jsr	strcat
	movea.l	a6,a1
	movea.l	a3,a0
	jsr	strcat
	moveq	#10,d1
	lea	(sp),a0
	move.w	d1,-(sp)
	move.l	a0,-(sp)
	move.l	d3,d2
	sub.l	d4,d2
	move.l	d2,d0
	add.l	d0,d0
	add.l	d2,d0
	lsl.l	#3,d0
	add.l	d2,d0
	lsl.l	#2,d0
	move.l	d3,d1
	jsr	uldiv
	movea.l	(sp)+,a0
	move.w	(sp)+,d1
	jsr	ltoa
	lea	(sp),a1
	movea.l	a3,a0
	jsr	strcat
	lea	$e(a4),a1                       ; -> str_used
	movea.l	a3,a0
	jsr	strcat
	moveq	#10,d1
	lea	(sp),a0
	move.l	d4,d0
	jsr	ltoa
	lea	(sp),a1
	movea.l	a3,a0
	jsr	strcat
	movea.l	a6,a1
	movea.l	a3,a0
	jsr	strcat
	moveq	#10,d1
	lea	(sp),a0
	move.w	d1,-(sp)
	move.l	a0,-(sp)
	move.l	d4,d0
	add.l	d0,d0
	add.l	d4,d0
	lsl.l	#3,d0
	add.l	d4,d0
	lsl.l	#2,d0
	move.l	d3,d1
	jsr	uldiv
	movea.l	(sp)+,a0
	move.w	(sp)+,d1
	jsr	ltoa
	lea	(sp),a1
	movea.l	a3,a0
	jsr	strcat
	lea	$9(a6),a1                       ; -> str_free
	movea.l	a3,a0
	jsr	strcat
	movea.l	a3,a0                           ; title into the status line
	jsr	draw_status_text
	clr.w	$20(a2)                         ; root directory: depth 0, -> dir_depth
	movea.l	-$4(a2),a0                      ; -> list_tree_ptr
	move.l	(a2),$24(a0)
	jsr	list_directory                  ; list it
	moveq	#1,d0
.return
	lea	$a(sp),sp
	movem.l	(sp)+,d3-d4/a2-a6
	rts


list_directory:
	movem.l	d3-d5/a2-a5,-(sp)
	lea	-$a(sp),sp
	lea	dir_count,a2                    ; no entries, top line 0
	clr.w	(a2)
	clr.w	$2(a2)                          ; -> dir_top
	moveq	#55,d0                          ; Fsfirst with all attributes ($37)
	movea.l	-$1c(a2),a0                     ; -> dir_path_ptr
	jsr	Fsfirst
	move.w	d0,d3
	lea	dta,a3
	move.w	$4(a2),d1                       ; in a subdirectory the first entry is ">>Parent<<", -> dir_depth
	bne.w	.fsnext
	bra.w	.entry_test

.next_entry
	move.w	$4(a2),d0                       ; -> dir_depth
	beq.s	.file_entry
	move.w	(a2),d1
	bne.s	.file_entry
	lea	str_parent,a1                   ; entries are 54 bytes: text line, file name at +$28 ($ff for the parent entry)
	ext.l	d1
	move.l	d1,d2
	add.l	d2,d2
	add.l	d1,d2
	lsl.l	#2,d2
	add.l	d1,d2
	add.l	d2,d2
	add.l	d1,d2
	add.l	d2,d2
	movea.l	-$18(a2),a0                     ; -> dir_list_ptr
	adda.l	d2,a0
	jsr	strcpy
	move.w	(a2),d1
	addq.w	#1,(a2)
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#2,d0
	add.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	add.l	d0,d0
	movea.l	-$18(a2),a0                     ; -> dir_list_ptr
	move.b	#$ff,$28(a0,d0.l)
	bra.w	.fsnext

.file_entry
	move.b	$15(a3),d4                      ; a file or directory:, -> dta+d_attrib
	lea	$1e(a3),a1                      ; its name at +$28 for entering it, -> dta+d_fname
	move.w	(a2),d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#2,d0
	add.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	add.l	d0,d0
	movea.l	-$18(a2),a0                     ; -> dir_list_ptr
	lea	$28(a0,d0.l),a0
	jsr	strcpy
	move.w	(a2),d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#2,d0
	add.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	add.l	d0,d0
	movea.l	-$18(a2),a4                     ; -> dir_list_ptr
	adda.l	d0,a4
	addq.w	#1,(a2)
	moveq	#16,d0                          ; type character: ">" directory, " " file
	and.b	d4,d0
	beq.s	.not_directory
	moveq	#62,d1
	bra.s	.type_char

.not_directory
	moveq	#32,d1
.type_char
	move.b	d1,(a4)+
	clr.w	d5                              ; name padded to 12 columns, extension at column 9
	lea	$1e(a3),a5                      ; -> dta+d_fname
.name_char
	move.b	(a5),d0
	bne.s	.not_end
	bra.s	.pad_test

.pad_name
	move.b	#$20,(a4)+
	addq.w	#1,d5
.pad_test
	cmp.w	#$c,d5
	blt.s	.pad_name
	move.b	#$20,(a4)+
	move.b	#$20,(a4)+
	moveq	#10,d1                          ; size right aligned
	lea	(sp),a0
	move.l	$1a(a3),d0                      ; -> dta+d_length
	jsr	ltoa
	lea	(sp),a0
	jsr	strlen
	move.l	d0,d3
	move.w	d3,d5
	bra.s	.pad_size_test

.not_end
	cmpi.b	#$2e,(a5)                       ; '.'
	bne.s	.name_letter
	bra.s	.pad_base_test

.pad_base
	move.b	#$20,(a4)+
	addq.w	#1,d5
.pad_base_test
	cmp.w	#$8,d5
	blt.s	.pad_base
	bra.s	.extension_test

.copy_extension
	move.b	(a5)+,(a4)+
	addq.w	#1,d5
.extension_test
	move.b	(a5),d0
	bne.s	.copy_extension
	bra.s	.pad_test

.name_letter
	move.b	(a5)+,(a4)+
	addq.w	#1,d5
	bra.s	.name_char

.pad_size
	move.b	#$20,(a4)+
.pad_size_test
	move.w	d3,d0
	addq.w	#1,d3
	subq.w	#6,d0
	blt.s	.pad_size
	lea	(sp),a1
	movea.l	a4,a0
	jsr	strcpy
	adda.w	d5,a4
	move.b	#$20,(a4)+
	move.b	#$20,(a4)+
	moveq	#1,d0                           ; attribute flags: p read only, h hidden, s system, d directory, a archive; "-" when clear
	and.b	d4,d0
	beq.s	.not_read_only
	moveq	#112,d1
	bra.s	.flag_p

.not_read_only
	moveq	#45,d1
.flag_p
	move.b	d1,(a4)+
	moveq	#2,d0
	and.b	d4,d0
	beq.s	.not_hidden
	moveq	#104,d1
	bra.s	.flag_h

.not_hidden
	moveq	#45,d1
.flag_h
	move.b	d1,(a4)+
	moveq	#4,d0
	and.b	d4,d0
	beq.s	.not_system
	moveq	#115,d1
	bra.s	.flag_s

.not_system
	moveq	#45,d1
.flag_s
	move.b	d1,(a4)+
	moveq	#16,d0
	and.b	d4,d0
	beq.s	.not_dir
	moveq	#100,d1
	bra.s	.flag_d

.not_dir
	moveq	#45,d1
.flag_d
	move.b	d1,(a4)+
	moveq	#32,d0
	and.b	d4,d0
	beq.s	.not_archive
	moveq	#97,d1
	bra.s	.flag_a

.not_archive
	moveq	#45,d1
.flag_a
	move.b	d1,(a4)+
	clr.b	(a4)
.fsnext
	jsr	Fsnext                          ; next entry
	move.w	d0,d3
.entry_test
	tst.w	d3
	beq.w	.next_entry
	lea	compare_entries,a1              ; sort them (compare_entries) and draw
	moveq	#54,d1
	move.w	(a2),d0
	ext.l	d0
	movea.l	-$18(a2),a0                     ; -> dir_list_ptr
	jsr	qsort
	clr.w	d0
	jsr	draw_directory
	lea	$a(sp),sp
	movem.l	(sp)+,d3-d5/a2-a5
	rts


draw_directory:
	movem.l	d3-d4/a2,-(sp)                  ; d0: 0 only set the objects, 1 redraw all, 2 scroll up, 3 scroll down
	move.w	d0,d4
	lea	dir_top,a2
	move.w	(a2),d3
	bra.s	.line_test

.next_line
	move.w	d3,d1                           ; each of the 12 visible lines: text pointer, directories in bold
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#2,d0
	add.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	add.l	d0,d0
	movea.l	-$1a(a2),a0                     ; -> dir_list_ptr
	cmpi.b	#$3e,$0(a0,d0.l)                ; '>'
	bne.s	.file_line
	moveq	#5,d2
	bra.s	.set_flags

.file_line
	clr.w	d2
.set_flags
	moveq	#5,d1
	add.w	d3,d1
	sub.w	(a2),d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	-$22(a2),a0                     ; -> list_tree_ptr
	move.w	d2,$8(a0,d0.l)
	move.w	d3,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#2,d0
	add.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	add.l	d0,d0
	movea.l	-$1a(a2),a0                     ; -> dir_list_ptr
	adda.l	d0,a0
	moveq	#5,d0
	add.w	d3,d0
	sub.w	(a2),d0
	ext.l	d0
	move.l	d0,d2
	add.l	d2,d2
	add.l	d0,d2
	lsl.l	#3,d2
	movea.l	-$22(a2),a1                     ; -> list_tree_ptr
	move.l	a0,$c(a1,d2.l)
	addq.w	#1,d3
.line_test
	cmp.w	-$2(a2),d3                      ; -> dir_count
	bge.s	.hide_test
	moveq	#12,d0
	add.w	(a2),d0
	cmp.w	d0,d3
	blt.w	.next_line
	bra.s	.hide_test

.hide_line
	moveq	#5,d1                           ; lines past the end are hidden
	add.w	d3,d1
	sub.w	(a2),d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	movea.l	-$22(a2),a0                     ; -> list_tree_ptr
	move.w	#$80,$8(a0,d0.l)
	addq.w	#1,d3
.hide_test
	moveq	#12,d0
	add.w	(a2),d0
	cmp.w	d0,d3
	blt.s	.hide_line
	jsr	directory_slider                ; slider
	tst.w	d4
	beq.s	.return
	moveq	#18,d0                          ; redraw the slider bar, then the lines or scroll
	movea.l	-$22(a2),a0                     ; -> list_tree_ptr
	jsr	draw_object
	cmp.w	#$1,d4
	bne.s	.scroll
	moveq	#4,d0
	movea.l	-$22(a2),a0                     ; -> list_tree_ptr
	jsr	draw_object
	clr.w	d3
	bra.s	.redraw_test

.redraw_line
	moveq	#5,d0
	add.w	d3,d0
	movea.l	-$22(a2),a0                     ; -> list_tree_ptr
	jsr	draw_object
	move.w	d3,d0
	jsr	draw_list_frame
	addq.w	#1,d3
.redraw_test
	cmp.w	#$c,d3
	blt.s	.redraw_line
	bra.s	.return

.scroll
	move.w	d4,d0                           ; scroll the window contents by two lines
	jsr	scroll_window
.return
	movem.l	(sp)+,d3-d4/a2
	rts


scroll_directory:
	movem.l	d3-d4/a2,-(sp)
	move.w	d0,d3
	lea	dir_top,a2                      ; highest top line: entries - 12, even
	cmpi.w	#$c,-$2(a2)                     ; -> dir_count
	ble.s	.no_scroll
	moveq	#-12,d4
	add.w	-$2(a2),d4                      ; -> dir_count
	bra.s	.even_top

.no_scroll
	clr.w	d4
.even_top
	moveq	#1,d0
	and.w	d4,d0
	beq.s	.check_low
	addq.w	#1,d4
.check_low
	tst.w	d3                              ; limits: bell
	bge.s	.check_high
	moveq	#7,d0
	jsr	Cconout
	clr.w	d3
.check_high
	cmp.w	d3,d4
	bge.s	.move
	moveq	#7,d0
	jsr	Cconout
	move.w	d4,d3
.move
	cmp.w	(a2),d3                         ; moved by two: scroll, else redraw
	beq.s	.return
	move.w	(a2),d4
	move.w	d3,(a2)
	moveq	#2,d0
	add.w	d4,d0
	cmp.w	d0,d3
	bne.s	.not_down_one
	moveq	#2,d0
	jsr	draw_directory(pc)
	bra.s	.return

.not_down_one
	moveq	#-2,d0
	add.w	d4,d0
	cmp.w	d0,d3
	bne.s	.redraw_all
	moveq	#3,d0
	jsr	draw_directory(pc)
	bra.s	.return

.redraw_all
	moveq	#1,d0
	jsr	draw_directory(pc)
.return
	movem.l	(sp)+,d3-d4/a2
	rts


directory_slider:
	move.l	d3,-(sp)                        ; slider position and size in 1/1000 of the bar
	lea	list_tree_ptr,a0
	movea.l	(a0),a1
	move.w	$1c6(a1),d0
	move.w	$20(a0),d1                      ; -> dir_count
	move.w	d1,d2
	dc.w	$c47c,$1                        ; and.w #$1,d2
	beq.s	.position
	addq.w	#1,d1
.position
	tst.w	d1
	beq.s	.top
	move.w	$22(a0),d2                      ; -> dir_top
	mulu.w	d0,d2
	moveq	#0,d3
	move.w	d2,d3
	divu.w	d1,d3
	bra.s	.size

.top
	clr.w	d3
.size
	movea.l	(a0),a1
	move.w	d3,$1da(a1)
	cmp.w	#$c,d1
	bhi.s	.partial
	move.w	d0,d2
	bra.s	.set_size

.partial
	moveq	#12,d2
	mulu.w	d0,d2
	moveq	#0,d3
	move.w	d2,d3
	move.l	d3,d2
	divu.w	d1,d2
.set_size
	movea.l	(a0),a1
	move.w	d2,$1de(a1)
	move.l	(sp)+,d3
	rts


drag_slider:
	move.l	d3,-(sp)
	cmpi.w	#$c,dir_count                   ; more than 12 entries: drag and scroll to the position
	ble.s	.done
	moveq	#1,d2
	moveq	#19,d1
	moveq	#18,d0
	movea.l	list_tree_ptr,a0
	jsr	graf_slidebox
	move.w	d0,d3
	ext.l	d3
	move.l	d3,d0
	moveq	#-12,d1
	add.w	dir_count,d1
	ext.l	d1
	jsr	lmul
	move.l	d0,d3
	move.l	#$3e8,d1
	jsr	uldiv
	move.l	d0,d3
	moveq	#1,d1
	and.l	d0,d1
	beq.s	.even
	moveq	#1,d0
	add.w	d3,d0
	bra.s	.scroll

.even
	move.w	d3,d0
.scroll
	jsr	scroll_directory(pc)
.done
	move.l	(sp)+,d3
	rts


page_directory:
	move.l	a2,-(sp)
	subq.w	#4,sp
	lea	mouse_state,a2                  ; mouse above the slider: page up, below: page down
	pea	(a2)
	pea	(a2)
	lea	$a(sp),a1
	movea.l	a2,a0
	jsr	graf_mkstate
	addq.w	#8,sp
	pea	(sp)
	movea.l	a2,a1
	moveq	#19,d0
	movea.l	list_tree_ptr,a0
	jsr	objc_offset
	addq.w	#4,sp
	move.w	(sp),d0
	cmp.w	$2(sp),d0
	ble.s	.page_down
	moveq	#-12,d0
	bra.s	.scroll

.page_down
	moveq	#12,d0
.scroll
	add.w	dir_top,d0
	jsr	scroll_directory(pc)
	addq.w	#4,sp
	movea.l	(sp)+,a2
	rts


enter_directory:
	movem.l	d3/a2-a3,-(sp)
	move.w	d0,d3
	lea	dir_path_ptr,a2
	lea	str_a,a3
	move.w	$20(a2),d1                      ; parent entry: cut the last path element, -> dir_depth
	beq.s	.subdirectory
	tst.w	d0
	bne.s	.subdirectory
	movea.l	(a2),a0
	moveq	#92,d0
	jsr	strrchr
	clr.b	(a0)
	lea	$2(a3),a1                       ; -> str_a+2
	move.l	a1,-(sp)
	moveq	#92,d0
	movea.l	(a2),a0
	jsr	strrchr
	movea.l	(sp)+,a1
	jsr	strcpy
	subq.w	#1,$20(a2)                      ; -> dir_depth
	bra.s	.list

.subdirectory
	addq.w	#1,$20(a2)                      ; directory: append its name to the path, -> dir_depth
	move.w	d3,d1
	ext.l	d1
	move.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#2,d0
	add.l	d1,d0
	add.l	d0,d0
	add.l	d1,d0
	add.l	d0,d0
	movea.l	$4(a2),a1                       ; -> dir_list_ptr
	lea	$28(a1,d0.l),a1
	move.l	a1,-(sp)
	movea.l	(a2),a0
	moveq	#42,d0
	jsr	strchr
	movea.l	(sp)+,a1
	jsr	strcpy
	lea	$2(a3),a1                       ; -> str_a+2
	movea.l	(a2),a0
	jsr	strcat
.list
	jsr	list_directory(pc)              ; list and draw the new directory
	moveq	#1,d0
	jsr	draw_directory(pc)
	moveq	#1,d0
	movea.l	-$4(a2),a0                      ; -> list_tree_ptr
	jsr	draw_object
	movem.l	(sp)+,d3/a2-a3
	rts

compare_entries:
	movem.l	d3/a2-a3,-(sp)
	movea.l	a0,a2
	movea.l	a1,a3
	move.w	dir_depth,d0                    ; qsort compare: the parent entry first,
	beq.s	.by_type
	cmpi.b	#$ff,$28(a2)
	bne.s	.second_parent
	moveq	#-1,d0
	bra.s	.return

.second_parent
	cmpi.b	#$ff,$28(a3)
	bne.s	.by_type
	moveq	#1,d0
	bra.s	.return

.by_type
	clr.w	d3                              ; directories before files,
	move.b	(a2),d3
	clr.w	d0
	move.b	(a3),d0
	cmp.w	d3,d0
	beq.s	.by_extension
	sub.w	d3,d0
	bra.s	.return

.by_extension
	moveq	#3,d0                           ; then by extension, then by name
	lea	$a(a3),a1
	lea	$a(a2),a0
	jsr	strncmp
	move.w	d0,d3
	bne.s	.extension_differs
	lea	$28(a3),a1
	lea	$28(a2),a0
	jsr	strcmp
	bra.s	.return

.extension_differs
	move.w	d3,d0
.return
	movem.l	(sp)+,d3/a2-a3
	rts


scroll_window:
	movem.l	d3-d5/a3,-(sp)
	lea	-$4c(sp),sp
	move.w	d0,d3
	lea	list_x,a3
	move.w	$2(a3),(sp)                     ; -> list_width
	moveq	#5,d1
	muls.w	$4(a3),d1                       ; -> list_line_h
	move.w	d1,$2(sp)
	move.w	screen_planes,$4(sp)
	clr.w	d2
	move.w	d2,$8(sp)
	move.w	d2,$6(sp)
	lea	$a(sp),a0
	move.l	#$3030303,(a0)
	move.w	-$4(a3),d1                      ; -> list_left
	move.w	d1,$1c(sp)
	move.w	d1,$e(sp)
	subq.w	#2,d0
	bne.s	.logbase
	move.w	(a3),d2
	add.w	$4(a3),d2                       ; -> list_line_h
	bra.s	.logbase2

.logbase
	move.w	(a3),d2
.logbase2
	move.w	d2,$10(sp)
	jsr	Logbase
	move.l	a0,$20(sp)
	move.l	a0,$12(sp)
	move.w	screen_planes,d0
	add.w	d0,d0
	move.w	d0,$24(sp)
	move.w	d0,$16(sp)
	movea.l	linea_vars,a0
	move.w	$2(a0),d1
	move.w	d1,$26(sp)
	move.w	d1,$18(sp)
	moveq	#2,d0
	move.w	d0,$28(sp)
	move.w	d0,$1a(sp)
	cmp.w	#$2,d3
	bne.s	.use_list_line_h
	move.w	(a3),d1
	bra.s	.linea_defaults

.use_list_line_h
	move.w	(a3),d1
	add.w	$4(a3),d1                       ; -> list_line_h
.linea_defaults
	move.w	d1,$1e(sp)
	clr.l	$2a(sp)
	jsr	linea_defaults
	lea	(sp),a0
	jsr	bitblt
	clr.w	d1
	clr.w	d0
	lea	fill_lines,a0
	jsr	set_fill_pattern
	cmp.w	#$2,d3
	bne.s	.use_list_line_h2
	moveq	#6,d0
	muls.w	$4(a3),d0                       ; -> list_line_h
	add.w	(a3),d0
	move.w	d0,-(sp)
	move.w	-$4(a3),d2                      ; -> list_left
	add.w	$2(a3),d2                       ; -> list_width
	moveq	#5,d1
	muls.w	$4(a3),d1                       ; -> list_line_h
	add.w	(a3),d1
	move.w	-$4(a3),d0                      ; -> list_left
	jsr	filled_rect
	addq.w	#2,sp
	moveq	#10,d4
	moveq	#15,d5
	bra.s	.show_mouse

.use_list_line_h2
	move.w	(a3),d0
	add.w	$4(a3),d0                       ; -> list_line_h
	subq.w	#1,d0
	move.w	d0,-(sp)
	move.w	-$4(a3),d2                      ; -> list_left
	add.w	$2(a3),d2                       ; -> list_width
	move.w	(a3),d1
	move.w	-$4(a3),d0                      ; -> list_left
	jsr	filled_rect
	addq.w	#2,sp
	clr.w	d4
	moveq	#5,d5
.show_mouse
	clr.w	d0
	jsr	show_mouse
	move.w	d5,d0
	movea.l	-$18(a3),a0                     ; -> list_tree_ptr
	jsr	draw_object
	moveq	#1,d0
	add.w	d5,d0
	movea.l	-$18(a3),a0                     ; -> list_tree_ptr
	jsr	draw_object
	move.w	d4,d0
	jsr	draw_list_frame
	moveq	#1,d0
	add.w	d4,d0
	jsr	draw_list_frame
	lea	$4c(sp),sp
	movem.l	(sp)+,d3-d5/a3
	rts


draw_list_frame:
	movem.l	d3-d4/a2,-(sp)
	move.w	d0,d3
	move.b	medium_res,d1
	bne.s	.return
	lea	list_line_h,a2
	move.w	#$80,d2
	moveq	#5,d1
	add.w	d3,d1
	moveq	#0,d4
	move.w	d1,d4
	move.l	d4,d0
	add.l	d0,d0
	add.l	d4,d0
	lsl.l	#3,d0
	movea.l	-$1c(a2),a0                     ; -> list_tree_ptr
	and.w	$8(a0,d0.l),d2
	bne.s	.return
	jsr	linea_defaults
	clr.w	d1
	clr.w	d0
	lea	fill_black,a0
	jsr	set_fill_pattern
	moveq	#15,d0
	jsr	set_colour
	moveq	#1,d0
	and.w	d3,d0
	beq.s	.use_list_left
	move.w	-$6(a2),d4                      ; -> list_right
	bra.s	.use_list_margin

.use_list_left
	move.w	-$8(a2),d4                      ; -> list_left
.use_list_margin
	move.w	d4,d2
	add.w	$2(a2),d2                       ; -> list_margin
	subq.w	#1,d2
	move.w	d3,d1
	lsr.w	#1,d1
	mulu.w	(a2),d1
	add.w	-$4(a2),d1                      ; -> list_x
	add.w	(a2),d1
	subq.w	#1,d1
	move.w	d4,d0
	jsr	horizontal_line
	clr.w	d0
	jsr	show_mouse
.return
	movem.l	(sp)+,d3-d4/a2
	rts


	include	TCLIB.S

	section	data

errno:
	dc.w	$0000

	include	RSC.S

	include	STRINGS.S

	include	CONFIG.S

	include	VARS.S

	section	bss


	include	BSS.S

	end
