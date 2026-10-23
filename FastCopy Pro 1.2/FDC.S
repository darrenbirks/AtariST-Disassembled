; FDC.S  -  the floppy driver of FCOPYPRO.PRG, included by FCOPYPRO.S
;
; Programs the DMA chip and the WD1772 directly (a5 = $ffff8600, a6 = fdc_state):
; building and writing track images, seeking, reading and writing sectors with retries,
; drive select through the PSG.  The variables (fdc_state, src_*/dst_*, fmt_*) are in
; BSS.S, the field offsets in EQUATES.S.


;----------------------------------------------------------------------
; Floppy driver.  The driver programs the DMA chip and the WD1772 directly with
; a5 = $ffff8600 and a6 = fdc_state, holding flock while it works.  Drive 0 is the
; source and drive 1 the destination of a copy; select_drive_params loads their
; unit, step rate, sides and sectors per track from src_*/dst_*.
;----------------------------------------------------------------------
lock_floppy:
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	bsr.w	set_flock
	move.l	d0,-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	rts


unlock_floppy:
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	clr.w	$43e.w                          ; flock
	move.l	d0,-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	rts


;----------------------------------------------------------------------
; Builds the image of one track for Write Track in track_buffer: gap 4e, sync,
; ID fields, 512 data bytes of 0 and the CRC marks for fs_sectors sectors.  The
; gap sizes depend on the sector count (9 to 22 sectors, DD or HD), with the
; "fast format" layouts of FastCopy and an extra ID field before the index on 11
; sector tracks.  build_sector_order then sets the interleave.
;----------------------------------------------------------------------
build_track_image:
	movem.l	d0-d7/a0-a6,-(sp)               ; all registers kept
	moveq	#1,d0                           ; destination parameters
	bsr.w	select_drive_params
	move.w	fs_sectors(a6),d0               ; sectors per track
	move.w	d0,fs_count(a6)
	clr.b	fs_split_sector(a6)             ; no split sector, no extra ID fields, no DMA stop yet
	move.w	#$21,fs_split_offset(a6)
	clr.b	fs_extra_ids(a6)
	clr.b	fs_long_track(a6)
	clr.l	fs_dma_stop(a6)
	move.b	fmt_fast,d3                     ; d3 = Fast Format flag
	move.w	#$0,fs_density(a6)              ; density DD
	tst.b	dst_hd                          ; HD destination:
	beq.w	.dd
	move.w	#$3,fs_density(a6)              ; HD density bits for $ff860e
	cmpi.b	#$1,drive_density               ; drive_density 1: HD 5.25" table
	beq.w	.hd_drive_mode_1
	cmp.b	#$16,d0                         ; HD 3.5" with 22 sectors: interleave 11, skew 18
	bne.s	.hd_not_22
	move.w	#$b,fs_interleave(a6)
	move.w	#$12,fs_skew(a6)
	bra.w	.gaps_22_or_11

.hd_not_22
	cmp.b	#$15,d0                         ; 21 sectors
	bne.s	.hd_not_21
	move.w	#$b,fs_interleave(a6)
	move.w	#$12,fs_skew(a6)
	moveq	#9,d3
	moveq	#7,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#23,d7
	bra.w	.build

.hd_not_21
	cmp.b	#$14,d0                         ; 20 sectors
	bne.s	.hd_not_20
	move.w	#$1,fs_interleave(a6)
	move.w	#$11,fs_skew(a6)
	move.w	#$c7,d3
	moveq	#11,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#39,d7
	bra.w	.build

.hd_not_20
	cmp.b	#$13,d0                         ; 19 sectors: longer than one revolution unless fast format
	bne.s	.hd_18_or_less
	move.w	#$1,fs_interleave(a6)
	move.w	#$10,fs_skew(a6)
	tst.b	d3
	beq.s	.hd_19_normal
	move.l	#$2ea0,fs_dma_stop(a6)          ; stop by DMA address at $2ea0
	addq.b	#1,fs_long_track(a6)
	move.w	#$12c,d3
	bra.s	.hd_19_gaps

.hd_19_normal
	move.w	#$2ed,d3
.hd_19_gaps
	moveq	#11,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#36,d7
	bra.w	.build

.hd_18_or_less
	move.l	#$2ea0,d7                       ; 18 sectors and less
	cmp.b	#$12,d0
	bne.w	.hd_other
	move.w	#$f,fs_skew(a6)
	move.w	#$1,fs_interleave(a6)
	tst.b	d3
	beq.s	.hd_18_gaps
	move.l	d7,fs_dma_stop(a6)
.hd_18_gaps
	bsr.w	default_gaps
	bra.w	.build

.hd_drive_mode_1
	cmp.b	#$12,d0                         ; HD 5.25": 18, 17, 16 sectors
	bne.s	.hd1_not_18
	move.w	#$9,fs_interleave(a6)
	move.w	#$f,fs_skew(a6)
	bra.w	.gaps_22_or_11

.hd1_not_18
	cmp.b	#$11,d0
	bne.s	.hd1_not_17
	move.w	#$9,fs_interleave(a6)
	move.w	#$f,fs_skew(a6)
	moveq	#9,d3
	moveq	#7,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#23,d7
	bra.w	.build

.hd1_not_17
	cmp.b	#$10,d0
	bne.s	.hd1_15_or_less
	move.w	#$1,fs_interleave(a6)
	move.w	#$d,fs_skew(a6)
	tst.b	d3
	beq.s	.hd1_16_normal
	move.l	#$2630,fs_dma_stop(a6)
	addq.b	#1,fs_long_track(a6)
	moveq	#9,d3
	moveq	#15,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#32,d7
	bra.w	.build

.hd1_16_normal
	move.w	#$18f,d3
	moveq	#11,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#39,d7
	bra.w	.build

.hd1_15_or_less
	move.l	#$2580,d7
	cmp.b	#$f,d0
	bne.s	.hd_other
	move.w	#$c,fs_skew(a6)
	move.w	#$1,fs_interleave(a6)
	tst.b	d3
	beq.s	.hd1_15_gaps
	move.l	d7,fs_dma_stop(a6)
.hd1_15_gaps
	bsr.w	default_gaps
	bra.w	.build

.hd_other
	move.w	d0,d4                           ; other HD counts: skew = sectors - 3
	subq.w	#3,d4
	bsr.w	clamp_skew
	move.w	d4,fs_skew(a6)
	move.w	#$1,fs_interleave(a6)
	tst.b	d3
	beq.s	.hd_other_gaps
	move.l	d7,fs_dma_stop(a6)
.hd_other_gaps
	bsr.w	default_gaps
	cmp.b	#$d,d0
	bne.w	.build
	moveq	#37,d7
	bra.w	.build

.dd
	cmp.b	#$b,d0                          ; DD destination: 11 sectors: interleave 6, skew 9
	bne.s	.dd_not_11
	move.w	#$6,fs_interleave(a6)
	move.w	#$9,fs_skew(a6)
.gaps_22_or_11
	moveq	#2,d3                           ; gaps: d3 after index, d4 before ID, d5 before data, d6 sync, d7 after data
	moveq	#1,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#1,d7
	bra.w	.build

.dd_not_11
	cmp.b	#$a,d0                          ; 10 sectors
	bne.s	.dd_other
	move.w	#$1,fs_interleave(a6)
	move.w	#$8,fs_skew(a6)
	tst.b	d3
	beq.s	.dd_10_normal
	move.l	#$1780,fs_dma_stop(a6)
	addq.b	#1,fs_long_track(a6)
	moveq	#6,d3
	moveq	#4,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#35,d7
	bra.s	.build

.dd_10_normal
	tst.b	fmt_fast_access                 ; fast access headers: sector 10 written split over the index
	beq.s	.dd_10_gaps
	move.w	#$9,fs_skew(a6)
	addq.b	#1,fs_split_sector(a6)
.dd_10_gaps
	bsr.w	default_gaps
	bra.s	.build

.dd_other
	moveq	#0,d4                           ; other DD counts
	tst.b	fmt_fast_access
	bne.s	.dd_other_set
	move.w	d0,d4
	subq.w	#2,d4
	bsr.w	clamp_skew
.dd_other_set
	move.w	#$1,fs_interleave(a6)           ; extra ID fields before and after the data (Fast Access headers)
	move.w	d4,fs_skew(a6)
	addq.b	#1,fs_extra_ids(a6)
	tst.b	d3                              ; fast format: shorter gaps, track stops by DMA address at $1700
	beq.s	.dd_other_normal
	move.l	#$1700,fs_dma_stop(a6)
	move.w	#$ef,d3
	moveq	#11,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#39,d7
	bra.s	.build

.dd_other_normal
	move.w	#$1f4,d3
	moveq	#11,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#39,d7
.build
	movea.l	track_buffer,a0                 ; gap after the index ($4e)
	lea	fs_id_offsets(a6),a1
	move.w	d3,d0
	moveq	#78,d1
	bsr.w	fill_bytes
	tst.b	fmt_fast_access                 ; extra ID fields only with Fast Access headers
	bne.s	.first_extra_id
	clr.b	fs_extra_ids(a6)
.first_extra_id
	tst.b	fs_extra_ids(a6)                ; extra ID field with sector number $42 before the first sector
	beq.s	.next_sector
	moveq	#66,d2
	bsr.s	put_id_field
.next_sector
	moveq	#0,d2                           ; each sector: ID field,
	bsr.s	put_id_field
	move.w	d6,d0                           ; gap before the data,
	moveq	#0,d1
	bsr.w	fill_bytes
	moveq	#2,d0                           ; three sync bytes ($f5 = $a1),
	move.b	#$f5,d1
	bsr.s	fill_bytes
	move.b	#$fb,(a0)+                      ; data mark,
	move.w	#$1ff,d0                        ; 512 bytes of 0,
.clear_data
	clr.b	(a0)+
	dbra	d0,.clear_data
	move.b	#$f7,(a0)+                      ; CRC ($f7)
	move.w	d7,d0                           ; and the gap after the data
	moveq	#78,d1
	bsr.s	fill_bytes
	subq.w	#1,fs_count(a6)                 ; next sector
	bne.s	.next_sector
	tst.b	fs_extra_ids(a6)
	beq.s	.last_extra_id
	moveq	#66,d2
	bsr.s	put_id_field
.last_extra_id
	move.l	track_buffer,d1                 ; fill the rest of the buffer with $4e
	add.l	track_image_size,d1
	subq.l	#1,d1
	sub.l	a0,d1
	bmi.s	.end_of_ids
	moveq	#78,d0
.fill_end
	move.b	d0,(a0)+
	dbra	d1,.fill_end
.end_of_ids
	clr.w	(a1)                            ; end of the ID offset table
	bsr.w	build_sector_order              ; sector order with the interleave
	movem.l	(sp)+,d0-d7/a0-a6
	rts


put_id_field:
	move.w	d4,d0                           ; gap before the ID
	moveq	#0,d1
	bsr.s	fill_bytes
	moveq	#2,d0                           ; three sync bytes ($f5 = $a1)
	move.b	#$f5,d1
	bsr.s	fill_bytes
	move.b	#$fe,(a0)+                      ; ID mark
	move.l	a0,d0                           ; remember the offset of the ID field
	sub.l	track_buffer,d0
	move.w	d0,(a1)+
	clr.b	(a0)+                           ; track and side filled in later, sector number d2, size 2 (512)
	clr.b	(a0)+
	move.b	d2,(a0)+
	move.b	#$2,(a0)+
	move.b	#$f7,(a0)+                      ; CRC
	move.w	d5,d0                           ; gap before the data
	moveq	#78,d1

fill_bytes:
	move.b	d1,(a0)+
	dbra	d0,fill_bytes
	rts


;----------------------------------------------------------------------
; Formats track d0, side d1 of drive fs_drive from the image in track_buffer.
;----------------------------------------------------------------------
format_track:
	movem.l	d1-d7/a0-a6,-(sp)
	bsr.w	super_on
	bsr.w	set_flock
	bsr.s	format_track_command
	tst.b	fs_split_sector(a6)             ; split sector: put the bytes it overwrote back
	beq.s	.done
	lea	fs_saved_bytes(a6),a0
	movea.l	(a0)+,a1
	moveq	#8,d1
.restore_split
	move.b	(a0)+,(a1)+
	dbra	d1,.restore_split
.done
	bsr.w	super_off
	movem.l	(sp)+,d1-d7/a0-a6
	rts


;----------------------------------------------------------------------
; Puts track, side and sector numbers into the ID fields of the image and issues
; Write Track ($f0, $f4 for an HD long track) through fdc_command.
;----------------------------------------------------------------------
format_track_command:
	move.w	d0,fdc_state+fs_side            ; side
	move.w	d1,fdc_state+fs_track           ; track
	moveq	#1,d0
	bsr.w	select_drive_params
	bsr.w	sector_order_for_track          ; sector order of this track
	move.l	a0,fs_order_ptr(a6)
	lea	fs_id_offsets(a6),a1
	movea.l	track_buffer,a2
	move.w	fs_track(a6),d0
	move.w	fs_side(a6),d1
	moveq	#0,d2
.next_id
	movea.l	a2,a3                           ; each ID field: track, side
	move.w	(a1)+,d2
	beq.s	.ids_done
	adda.l	d2,a3
	move.b	d0,(a3)+
	move.b	d1,(a3)+
	cmpi.b	#$42,(a3)                       ; extra ID field ($42) keeps its sector number
	beq.s	.next_id
	move.b	(a0)+,d2                        ; sector number from the order table
	move.b	d2,(a3)+
	cmp.b	#$1,d2                          ; sector 1 with a split sector:
	bne.s	.next_id
	tst.b	fs_split_sector(a6)
	beq.s	.next_id
	suba.w	fs_split_offset(a6),a3          ; save the bytes the split copy overwrites,
	lea	fs_saved_bytes(a6),a4
	move.l	a3,(a4)+
	pea	(a3)
	moveq	#8,d3
.save_split
	move.b	(a3)+,(a4)+
	dbra	d3,.save_split
	movea.l	(sp)+,a3
	moveq	#-11,d3                         ; and write a second ID field of sector 1 in front of it
	move.b	d3,(a3)+
	move.b	d3,(a3)+
	move.b	d3,(a3)+
	move.b	#$fe,(a3)+
	move.b	d0,(a3)+
	move.b	d1,(a3)+
	move.b	#$42,(a3)+                      ; 'B'
	move.b	#$2,(a3)+
	move.b	#$f7,(a3)
	bra.s	.next_id

.ids_done
	bsr.w	select_drive_side               ; select drive and side
	tst.b	is_ste                          ; Mega STE / TT: floppy density
	beq.s	.no_density
	move.w	fs_density(a6),fdc_density(a5)
.no_density
	bsr.w	dma_reset_write                 ; DMA for writing, address of the track image
	move.l	track_buffer,d0
	bsr.w	set_dma_address
	moveq	#31,d0                          ; sector count register: 31
	bsr.w	write_fdc
	move.l	fs_dma_stop(a6),d7              ; stop the Write Track at this DMA offset
	beq.s	.stop_at_index
	add.l	track_buffer,d7
	bra.s	.write_track

.stop_at_index
	moveq	#0,d7
.write_track
	moveq	#68,d6                          ; status bits to check: write protect, lost data
	move.w	#$180,dma_mode(a5)              ; DMA write, FDC command register
	move.w	#$f0,d0                         ; Write Track
	tst.w	fs_side(a6)
	bne.w	fdc_command
	tst.b	fs_long_track(a6)               ; side 0 of a long track: Write Track with the 15 ms settle bit
	beq.w	fdc_command
	addq.w	#4,d0
	bra.w	fdc_command


;----------------------------------------------------------------------
; a6 = fdc_state, a5 = $ffff8600; loads the parameters of drive d0 (0 source,
; 1 destination) and the track its head is on.
;----------------------------------------------------------------------
select_drive_params:
	lea	fdc_state,a6
	lea	$ffff8600.w,a5
	move.w	d0,fs_drive(a6)
	tst.w	d0                              ; source drive
	bne.s	.destination
	move.w	src_unit,fs_unit(a6)
	move.w	src_step_rate,fs_step_rate(a6)
	move.w	src_sides,fs_sides(a6)
	move.w	src_sectors,fs_sectors(a6)
	bra.s	.head_track

.destination
	move.w	dst_unit,fs_unit(a6)            ; destination drive
	move.w	dst_step_rate,fs_step_rate(a6)
	move.w	dst_sides,fs_sides(a6)
	move.w	dst_sectors,fs_sectors(a6)
.head_track
	tst.w	fs_unit(a6)                     ; track of the head of that unit
	bne.s	.head_track_b
	move.w	fs_track_a(a6),fs_head_track(a6)
	rts

.head_track_b
	move.w	fs_track_b(a6),fs_head_track(a6)
	rts

store_head_track:
	move.w	fs_track(a6),d1                 ; store fs_track as the head track of the unit
	tst.w	fs_drive(a6)
	bne.s	.destination
	move.w	src_unit,d2
.store
	tst.w	d2
	bne.s	.store_b
	move.w	d1,fs_track_a(a6)
	rts

.store_b
	move.w	d1,fs_track_b(a6)
	rts

.destination
	move.w	dst_unit,d2
	bra.s	.store


;----------------------------------------------------------------------
; Builds two sector order tables with the interleave fs_interleave.
;----------------------------------------------------------------------
build_sector_order:
	moveq	#1,d4                           ; two tables: d4 = 1, 0
	lea	fs_sector_order(a6),a0
.next_table
	moveq	#1,d0
	move.w	fs_interleave(a6),d1            ; step = interleave, wrap at the sector count
	move.w	fs_sectors(a6),d2
	move.w	d2,d7
	cmpi.b	#$1,drive_density               ; HD 5.25" with 18 or 22 sectors: wrap to one less
	bne.s	.not_hd_18
	cmp.b	#$12,d2
	beq.s	.wrap_one_less
.not_hd_18
	cmp.b	#$16,d2
	bne.s	.fill
.wrap_one_less
	subq.w	#1,d7
.fill
	move.w	d2,d3
	subq.w	#1,d3
.next_sector
	move.b	d0,(a0)+                        ; store sector number, add the step, wrap
	add.w	d1,d0
	cmp.w	d2,d0
	ble.s	.count
	sub.w	d7,d0
.count
	dbra	d3,.next_sector
	dbra	d4,.next_table
	rts


;----------------------------------------------------------------------
; Returns in a0 the sector order of the current track, skewed by fs_skew per track.
;----------------------------------------------------------------------
sector_order_for_track:
	move.w	fs_track(a6),d1                 ; index = track (times two plus side when double sided)
	tst.w	fs_sides(a6)
	beq.s	.skew
	add.w	d1,d1
	add.w	fs_side(a6),d1
.skew
	move.w	fs_skew(a6),d3
	move.w	fs_sectors(a6),d4
	moveq	#0,d0
	bra.s	.count

.add_skew
	add.w	d3,d0                           ; offset += skew per track, modulo sectors
	cmp.w	d4,d0
	bmi.s	.count
	sub.w	d4,d0
.count
	dbra	d1,.add_skew
	lea	fs_sector_order(a6),a0
	adda.l	d0,a0
	rts


;----------------------------------------------------------------------
; Waits until the motor is off, then deselects both drives.
;----------------------------------------------------------------------
deselect_after_motor_off:
	move.w	#$80,dma_mode(a5)               ; FDC status register
.wait_motor_off
	move.w	fdc_access(a5),d0               ; wait until the motor-on bit clears
	btst	#$7,d0
	bne.s	.wait_motor_off
	moveq	#0,d0                           ; no drive, side 0

;----------------------------------------------------------------------
; Writes the drive and side select bits d0 (bit 0 side, 1 drive A, 2 drive B) to
; PSG port A, inverted.
;----------------------------------------------------------------------
psg_select_drive:
	move.w	d0,d7                           ; bits are active low in port A
	eori.b	#$7,d7
	dc.w	$ce3c,$0007                     ; and.b #$7,d7
	move.w	sr,-(sp)                        ; no interrupts while port A is changed
	ori.w	#$700,sr
	move.b	#$e,$ffff8800.w                 ; PSG register 14: port A
	move.b	$ffff8800.w,d0                  ; PSG register select
	dc.w	$c03c,$00f8                     ; and.b #$f8,d0, keep the other port A bits
	or.b	d0,d7
	move.b	d7,$ffff8802.w                  ; PSG write data
	move.w	(sp)+,sr
	rts


select_drive_side:
	move.w	fs_unit(a6),d0                  ; drive bit (unit + 1) * 2 plus the side
	addq.w	#1,d0
	add.w	d0,d0
	add.w	fdc_state+fs_side,d0
	bra.s	psg_select_drive


set_dma_address:
	move.b	d0,dma_low(a5)                  ; low, mid, high byte
	lsr.l	#8,d0
	move.b	d0,dma_mid(a5)
	lsr.w	#8,d0
	move.b	d0,dma_high(a5)
	rts


write_fdc:
	nop                                     ; the DMA chip needs time between accesses
	nop
	move.w	d0,fdc_access(a5)
	nop
	nop
	rts


read_fdc:
	nop
	nop
	move.w	fdc_access(a5),d0
	nop
	nop
	rts


;----------------------------------------------------------------------
; Issues FDC command d0 and waits for the interrupt (MFP GPIP bit 5), at most
; 2.2 seconds.  With d7 set, the command is stopped by Force Interrupt as soon as the
; DMA address reaches d7 (track images longer than one revolution).  The status is
; masked with d6 and returned as 0 OK, 1 DMA error, 2 timeout, 3 write protected,
; 4 lost data, 5 record not found, 6 CRC error.
;----------------------------------------------------------------------
fdc_command:
	bsr.s	write_fdc                       ; issue the command
	move.l	$4ba.w,d1                       ; timeout 2.2 seconds
	dc.w	$d2bc                           ; add.l #$1b8,d1
	dc.l	$1b8
.wait_interrupt
	btst	#$5,$fffffa01.w                 ; INTRQ: GPIP bit 5 low
	beq.s	.check_status
	cmp.l	$4ba.w,d1                       ; timed out
	beq.s	.timeout
	tst.l	d7                              ; no DMA stop address
	beq.s	.wait_interrupt
	moveq	#0,d2                           ; current DMA address
	move.b	dma_high(a5),d2
	lsl.w	#8,d2
	move.b	dma_mid(a5),d2
	lsl.l	#8,d2
	move.b	dma_low(a5),d2
	cmp.l	d2,d7                           ; not yet at the stop address
	bgt.s	.wait_interrupt
	bsr.s	fdc_force_interrupt             ; stop the command
.check_status
	tst.w	d6                              ; no status check wanted
	beq.s	.return
	move.w	#$80,dma_mode(a5)               ; read the FDC status
	bsr.s	read_fdc
	and.w	d6,d0                           ; status bits asked for
	tst.w	d0
	bne.s	.not_ok
	move.w	#$90,dma_mode(a5)               ; no FDC error: DMA status bit 0 low = DMA error
	move.w	dma_mode(a5),d0
	dc.w	$c07c,$1                        ; and.w #$1,d0
	eori.b	#$1,d0                          ; 1 = DMA error, 0 = OK
	rts

.not_ok
	move.b	d0,d1                           ; $40 write protect: 3
	dc.w	$c23c,$0040                     ; and.b #$40,d1
	beq.s	.not_write_protect
	moveq	#3,d0
	rts

.not_write_protect
	move.b	d0,d1                           ; $04 lost data: 4
	dc.w	$c23c,$0004                     ; and.b #$4,d1
	beq.s	.not_lost_data
	moveq	#4,d0
	rts

.not_lost_data
	move.b	d0,d1                           ; $10 record not found: 5
	dc.w	$c23c,$0010                     ; and.b #$10,d1
	beq.s	.not_rnf
	moveq	#5,d0
	rts

.not_rnf
	move.b	d0,d1                           ; $08 CRC error: 6
	dc.w	$c23c,$0008                     ; and.b #$8,d1
	beq.s	.return
	moveq	#6,d0
.return
	rts

.timeout
	bsr.s	fdc_force_interrupt             ; timeout: Force Interrupt, 2
	moveq	#2,d0
	rts


fdc_force_interrupt:
	move.w	#$d0,d0                         ; Force Interrupt immediately
	bsr.w	write_fdc
	moveq	#20,d0                          ; short delay
.delay
	dbra	d0,.delay
	rts


super_on:
	movem.l	d0-d2/a0-a2,-(sp)               ; supervisor mode, old stack in saved_ssp
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	move.l	d0,fdc_state+fs_saved_ssp
	movem.l	(sp)+,d0-d2/a0-a2
	rts


super_off:
	movem.l	d0-d2/a0-a2,-(sp)               ; back to user mode
	move.l	fdc_state+fs_saved_ssp,-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts


;----------------------------------------------------------------------
; Seeks drive d0 to track d1 (Restore for track 0).
;----------------------------------------------------------------------
seek_track:
	movem.l	d1-d7/a0-a6,-(sp)               ; d0 drive, d1 track
	bsr.s	super_on
	bsr.w	set_flock
	bsr.s	seek_track_super
	bsr.s	super_off
	movem.l	(sp)+,d1-d7/a0-a6
	rts


seek_track_super:
	tst.w	d1                              ; track 0: Restore
	beq.s	restore_and_seek
	move.w	d1,fdc_state+fs_track
	bsr.w	select_drive_params
	clr.w	fs_side(a6)                     ; side 0
	bsr.w	select_drive_side
	bsr.s	seek_command
	rts


restore_drive:
	movem.l	d1-d7/a0-a6,-(sp)
	bsr.s	super_on
	bsr.w	set_flock
	bsr.s	restore_and_seek
	bsr.s	super_off
	movem.l	(sp)+,d1-d7/a0-a6
	rts


restore_and_seek:
	move.w	d1,fdc_state+fs_track           ; target track
	bsr.w	select_drive_params
	clr.w	fs_head_track(a6)               ; head on track 0 after the Restore
	clr.w	fs_side(a6)
	bsr.w	select_drive_side
	move.w	#$80,dma_mode(a5)               ; FDC command register
	moveq	#0,d0                           ; Restore with the step rate
	add.w	fs_step_rate(a6),d0
	moveq	#0,d7
	moveq	#0,d6
	bsr.w	fdc_command
	tst.w	fs_track(a6)                    ; target not track 0: Seek
	beq.w	store_head_track

seek_command:
	move.w	#$82,dma_mode(a5)               ; track register = head track
	move.w	fdc_state+fs_head_track,d0
	bsr.w	write_fdc
	move.w	#$86,dma_mode(a5)               ; data register = target track
	move.w	fs_track(a6),d0
	bsr.w	write_fdc
	move.w	#$80,dma_mode(a5)
	moveq	#16,d0                          ; Seek with the step rate
	add.w	fs_step_rate(a6),d0
	moveq	#0,d7
	moveq	#0,d6
	bsr.w	fdc_command
	bra.w	store_head_track                ; the head is now on the target track


read_fdc_status:
	bsr.w	super_on
	move.l	a5,-(sp)
	lea	$ffff8600.w,a5
	move.w	#$80,dma_mode(a5)               ; FDC status (track 0, write protect, motor on)
	bsr.w	read_fdc
	movea.l	(sp)+,a5
	bsr.w	super_off
	rts


step_out:
	movem.l	d1-d7/a0-a6,-(sp)
	bsr.w	super_on
	bsr.w	set_flock
	bsr.s	step_out_super
	bsr.w	super_off
	movem.l	(sp)+,d1-d7/a0-a6
	rts


step_out_super:
	moveq	#1,d0
	bsr.w	select_drive_params
	clr.w	fs_side(a6)
	bsr.w	select_drive_side
	move.w	#$80,dma_mode(a5)
	moveq	#112,d0                         ; Step Out with track update
	add.w	fs_step_rate(a6),d0
	moveq	#0,d7
	moveq	#0,d6
	bsr.w	fdc_command
	move.w	fs_head_track(a6),d1            ; head one track lower
	subq.w	#1,d1
	move.w	d1,fs_track(a6)
	bra.w	store_head_track


;----------------------------------------------------------------------
; Calls the FDC routine in a1 with retries: retries_left tries, a recalibrate
; before every second one; write protect errors are not retried.
;----------------------------------------------------------------------
fdc_with_retries:
	move.b	fmt_retries,retries_left        ; retries_left = fmt_retries; with the flag on the stack clear only one more try
	beq.s	.start
	tst.b	$4(sp)
	bne.s	.start
	move.b	#$1,retries_left
.start
	bsr.w	super_on                        ; supervisor mode, flock
	bsr.w	set_flock
.try
	movem.l	d0-d7/a0-a6,-(sp)               ; call the routine in a1
	jsr	(a1)
	move.w	d0,fdc_result
	movem.l	(sp)+,d0-d7/a0-a6
	beq.s	.done                           ; OK or write protected: done
	cmpi.w	#$3,fdc_result
	beq.s	.done
	bsr.s	retry_recalibrate               ; retry?
	bne.s	.try
.done
	bsr.w	super_off                       ; result in d0
	move.w	fdc_result,d0
	rts


retry_recalibrate:
	movem.l	d0-d7/a0-a6,-(sp)
	subq.b	#1,retries_left                 ; retries left?
	bmi.s	.give_up
	btst	#$0,retries_left                ; every second retry: Restore and Seek back
	beq.s	.retry
	bsr.w	select_drive_params
	move.w	fs_head_track(a6),d1
	bsr.w	restore_and_seek
.retry
	moveq	#1,d0
	bra.s	.return

.give_up
	moveq	#0,d0
.return
	movem.l	(sp)+,d0-d7/a0-a6
	rts


;----------------------------------------------------------------------
; Reads sector d2 of side d1 on the current track of drive d0 into a0.
;----------------------------------------------------------------------
read_sectors:
	lea	read_sectors_command,a1
	bra.w	fdc_with_retries

read_sectors_command:
	move.w	d1,fdc_state+fs_side            ; side
	move.w	d2,-(sp)
	pea	(a0)
	bsr.w	select_drive_params             ; select drive and side, DMA address
	bsr.w	select_drive_side
	move.l	(sp)+,d0
	bsr.w	set_dma_address
	bsr.w	dma_reset_read                  ; DMA for reading
	moveq	#1,d0                           ; one sector
	bsr.w	write_fdc
	move.w	#$84,dma_mode(a5)               ; FDC sector register
	move.w	(sp)+,d0
	bsr.w	write_fdc
	moveq	#0,d7                           ; check record not found and CRC
	moveq	#28,d6
	move.w	#$80,dma_mode(a5)               ; FDC command register
	move.w	#$80,d0                         ; Read Sector
	bra.w	fdc_command


;----------------------------------------------------------------------
; XBIOS Floprate (41) for drive d0, rate d1; TOS 1.00 and 1.02 have no
; Floprate, so their seek rate variables are patched directly.
;----------------------------------------------------------------------
floprate:
	bsr.w	super_on                        ; TOS version
	movea.l	$4f2.w,a0                       ; _sysbase
	move.w	$2(a0),d2
	bsr.w	super_off
	cmp.w	#$100,d2                        ; TOS 1.00 and 1.02 have no Floprate
	beq.s	.tos_100
	cmp.w	#$102,d2
	beq.s	.tos_102
	move.w	d1,-(sp)                        ; XBIOS Floprate
	move.w	d0,-(sp)
	move.w	#$29,-(sp)
	trap	#14                             ; fn 41
	addq.l	#6,sp
	bra.s	.check_rate

.tos_100
	lea	$a06.w,a0                       ; TOS 1.00: seek rate variables of drive A and B
	bra.s	.patch_seekrate

.tos_102
	lea	$a4c.w,a0                       ; TOS 1.02
.patch_seekrate
	tst.w	d0
	bne.s	.drive_b
	lea	$2(a0),a0
	bra.s	.patch

.drive_b
	lea	$6(a0),a0
.patch
	move.w	(a0),d0                         ; old rate, set the new one unless -1
	tst.w	d1
	bmi.s	.check_rate
	move.w	d1,(a0)
.check_rate
	tst.b	d0                              ; returned rate limited to 0..3
	bmi.s	.clamp_rate
	cmp.b	#$3,d0
	ble.s	.return
.clamp_rate
	moveq	#3,d0
.return
	rts


;----------------------------------------------------------------------
; Writes sector d2 of side d1 on the current track of drive d0 from a0.
;----------------------------------------------------------------------
write_sectors:
	lea	write_sectors_command(pc),a1
	bra.w	fdc_with_retries

write_sectors_command:
	move.w	d1,fdc_state+fs_side            ; side
	move.w	d2,-(sp)
	pea	(a0)
	bsr.w	select_drive_params             ; select drive and side, DMA address
	bsr.w	select_drive_side
	move.l	(sp)+,d0
	bsr.w	set_dma_address
	bsr.s	dma_reset_write                 ; DMA for writing
	moveq	#1,d0
	bsr.w	write_fdc                       ; one sector
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	move.w	#$184,dma_mode(a5)              ; DMA write, FDC sector register
	move.w	(sp)+,d0
	bsr.w	write_fdc
	moveq	#0,d7                           ; check write protect and lost data
	moveq	#92,d6
	move.w	#$180,dma_mode(a5)              ; DMA write, FDC command register
	move.w	#$a0,d0                         ; Write Sector
	bra.w	fdc_command


set_flock:
	move.w	#$1,$43e.w                      ; stop the VBL floppy routine of TOS
	rts


clamp_skew:
	tst.w	d4
	bpl.s	.return
	moveq	#0,d4
.return
	rts


default_gaps:
	moveq	#59,d3                          ; gap sizes of the normal format
	moveq	#11,d4
	moveq	#21,d5
	moveq	#11,d6
	moveq	#39,d7
	rts


wait_ticks:
	bsr.w	super_on                        ; wait d0 + 1 200 Hz ticks
	dc.w	$c0bc                           ; and.l #$ffff,d0
	dc.l	$ffff
	addq.l	#1,d0
	add.l	$4ba.w,d0                       ; _hz_200
.wait
	cmp.l	$4ba.w,d0                       ; _hz_200
	bne.s	.wait
	bsr.w	super_off
	rts


dma_reset_write:
	move.w	#$190,dma_mode(a5)              ; toggle the DMA direction to clear the FIFO, ending in write mode
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	move.w	#$90,dma_mode(a5)
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	move.w	#$190,dma_mode(a5)
	rts


dma_reset_read:
	move.w	#$90,dma_mode(a5)               ; toggle the DMA direction to clear the FIFO, ending in read mode
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	move.w	#$190,dma_mode(a5)
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	tst.b	$fffffa01.w                     ; MFP GPIP
	move.w	#$90,dma_mode(a5)
	rts

