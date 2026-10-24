; Batman The Movie (Ocean, 1989) - 1 disk budget release (The Hit Squad)
; Stage 3: unpacked by stage 2 at $10000 (stage3.bin).
;
; Fades the white screen to black, then copies three parts and runs the game loader:
;   sector_load ... ($100ee-$106b9)  to $6f950: the sector loader and Pack-Ice depacker
;                                    the game loader's load_file calls (jsr $6f950)
;   game_loader_image (gameload.bin) to $21000 with 4 KB from there: the reissue's game
;                                    loader, patched (loadstub.s, loader.s, BUDGET_1DISK)
;   reset_trap                       to $300, the reset vector the boot sector set: clears
;                                    the system variables and cold boots
; The copied parts are PC relative and are shown where stage 3 holds them; add $5f862
; for the address the sector loader runs at.  This source assembles to stage3.bin.

	opt	o-
	org	$10000

;----------------------------------------------------------------------
; Stage 3: fade out, then install the parts and run the game loader.
;----------------------------------------------------------------------
stage3_start:
	lea	stage3_start,sp         ; stack
	movem.l	d0-d7/a0-a6,-(sp)
	sf	d4
	move.w	#$2300,sr               ; interrupts on
	bsr.s	fade_out
	jmp	install                 ; run the parts


;----------------------------------------------------------------------
; Fade the palette from white to black: a VBL handler sets all colours to d5 while d4 is
; set; d5 steps down by $111 every so often.
;----------------------------------------------------------------------
fade_out:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	saved_vbl(pc),a2
	move.l	$70.w,(a2)              ; save the VBL vector
	move.l	#fade_vbl,$70.w         ; VBL -> fade_vbl
	move.w	#$777,d5                ; white
	st	d4                      ; fade on
	moveq	#6,d6                   ; 7 steps
fade_step:
	subi.w	#$111,d5                ; darker
	move.l	#$ffff,d7
	dbra	d7,*                    ; wait
	dbra	d6,fade_step
	sf	d4                      ; fade off
	lea	saved_vbl(pc),a2
	move.l	(a2),$70.w              ; VBL back
	movem.l	(sp)+,d0-d7/a0-a6
	rts


;----------------------------------------------------------------------
; VBL during the fade.
;----------------------------------------------------------------------
fade_vbl:
	movem.l	d0-d7/a0-a6,-(sp)
	tst.b	d4                      ; fading?
	beq.s	fade_vbl_exit
	lea	$ffff8240.w,a0          ; palette 0
	moveq	#15,d7
fade_colour_loop:
	move.w	d5,(a0)+                ; all 16 colours
	dbra	d7,fade_colour_loop
fade_vbl_exit:
	movem.l	(sp)+,d0-d7/a0-a6
	rte

saved_vbl:
	dc.l	$00000000               ; the VBL vector while the fade runs

;----------------------------------------------------------------------
; Black palette, copy the sector loader to $6f950, the game loader to $21000 and the reset
; trap to $300, and run the game loader.
;----------------------------------------------------------------------
install:
	move.w	#$2700,sr
	lea	$ffff8240.w,a0          ; palette 0
	moveq	#7,d7
black_palette_loop:
	clr.l	(a0)+
	dbra	d7,black_palette_loop
	lea	sector_load(pc),a0
	lea	$6f950,a1               ; the sector loader
	move.l	#$5cb,d7                ; $5cc bytes
copy_sector_load_loop:
	move.b	(a0)+,(a1)+
	dbra	d7,copy_sector_load_loop
	lea	game_loader_image(pc),a0
	lea	$21000,a1               ; the game loader
	move.l	#$fff,d7                ; 4 KB
copy_game_loader_loop:
	move.b	(a0)+,(a1)+
	dbra	d7,copy_game_loader_loop
	lea	reset_trap(pc),a0
	lea	$300.w,a1               ; the reset vector
	move.l	#$1f,d7
copy_reset_trap_loop:
	move.b	(a0)+,(a1)+
	dbra	d7,copy_reset_trap_loop
	movem.l	(sp)+,d0-d7/a0-a6
	jmp	$21000                  ; run the game loader


;----------------------------------------------------------------------
; Run at $300 on a reset: clear $400-$bcf (the system variables) and cold boot.
;----------------------------------------------------------------------
reset_trap:
	move.w	#$2700,sr
	lea	$80000,sp               ; stack
	lea	$400.w,a0               ; system variables
	move.l	#$1f3,d7
clear_sysvars_loop:
	clr.l	(a0)+
	dbra	d7,clear_sysvars_loop
	movea.l	$4.w,a0                 ; reset: cold boot
	jmp	(a0)


;----------------------------------------------------------------------
; Run at $6f950, the game loader's load_file: read d2 sectors from logical sector d1 to
; d4 (side 0) and unpack them in place.
;----------------------------------------------------------------------
sector_load:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	move.w	#$2700,sr
	moveq	#0,d0                   ; drive A, side 0 only
	movea.l	d4,a0                   ; buffer = destination
	moveq	#0,d3                   ; read
	bsr.s	floppy_rw
	bsr.w	ice_depack              ; unpack the file in place
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d7/a0-a6
	rts


;----------------------------------------------------------------------
; Read or write sectors: d0 bit 0 drive, bit 3 set: the logical tracks run over both sides,
; clear: all on the side in bit 2; d1 first logical sector, d2 count, d3 mode (0 read,
; 1 write sectors, 2 write track), a0 buffer.  Returns d0 = 0 or an error code.  Locals on
; a6: -$1c drive, -$1a logical track, -$18 sector, -$16 first, -$14 count on this track,
; -$12 left, -$10 track step, -$e side, -$c buffer, -8 mode, -6 saved flock, -4 DMA address.
;----------------------------------------------------------------------
floppy_rw:
	movem.l	d1-d4/a0-a1,-(sp)
	link	a6,#$ffe4
	move.w	d0,d4
	andi.w	#$1,d4
	move.w	d4,-$1c(a6)
	move.w	d1,-$16(a6)
	move.w	d2,-$12(a6)
	move.w	d3,-$8(a6)
	move.l	a0,-$c(a6)
	ror.l	#3,d0                   ; bit 3: both sides
	andi.w	#$1,d0
	eori.b	#$1,d0
	addq.b	#1,d0
	move.w	d0,-$10(a6)             ; track step: 1 over both sides, 2 on one side
	clr.w	d0
	rol.l	#1,d0                   ; bit 2: the side
	move.w	d0,-$e(a6)
	moveq	#21,d0                  ; past the end of the disk (rw_done returns d1, not this code)
	add.w	d1,d2
	cmp.w	#$640,d2                ; 1600 sectors
	bgt.w	rw_done
	ext.l	d1
	divu.w	#$a,d1                  ; track and sector
	cmpi.w	#$1,-$10(a6)
	beq.s	rw_set_track
	add.w	d1,d1                   ; one side: logical tracks 0, 2, 4 ...
rw_set_track:
	move.w	d1,-$1a(a6)
	swap	d1
	addq.w	#1,d1                   ; sectors from 1
	move.w	d1,-$18(a6)
	bsr.w	drive_on
rw_track_loop:
	move.w	-$18(a6),d0
	moveq	#11,d1                  ; sectors to the end of this track
	sub.w	d0,d1
	cmp.w	-$12(a6),d1
	ble.s	rw_count_set
	move.w	-$12(a6),d1
rw_count_set:
	move.w	d1,-$14(a6)
	bsr.s	rw_track                ; this track
	bne.s	rw_error
	moveq	#0,d0
	cmpi.b	#$2,-$7(a6)             ; write track: one only
	beq.s	rw_error
	move.w	-$12(a6),d0
	sub.w	-$14(a6),d0
	beq.s	rw_error
	move.w	d0,-$12(a6)
	move.w	-$14(a6),d0
	lsl.l	#8,d0                   ; next buffer
	add.l	d0,d0
	add.l	d0,-$c(a6)
	move.w	#$1,-$18(a6)            ; next track from sector 1
	move.w	-$10(a6),d0             ; next track
	add.w	d0,-$1a(a6)
	bra.s	rw_track_loop


;----------------------------------------------------------------------
; Error: FDC status to an error code.
;----------------------------------------------------------------------
rw_error:
	move.l	d0,d1                   ; no error
	beq.s	rw_done
	andi.b	#$58,d0                 ; WP, RNF, CRC
	moveq	#28,d1
	cmp.b	#$50,d0
	beq.s	rw_done
	moveq	#25,d1
	cmp.b	#$8,d0
	beq.s	rw_done
	moveq	#24,d1
	cmp.b	#$18,d0
	beq.s	rw_done
	moveq	#21,d1
	cmp.b	#$10,d0
	beq.s	rw_done
	moveq	#-1,d1
rw_done:
	bsr.w	drive_off
	unlk	a6
	move.l	d1,d0
	movem.l	(sp)+,d1-d4/a0-a1
	rts


;----------------------------------------------------------------------
; One track: select the drive, seek, read or write, up to 3 tries (restore first when the
; sector is not found).
;----------------------------------------------------------------------
rw_track:
	bsr.w	select
	move.w	#$2,d3                  ; 3 tries
	bra.s	rw_seek

rw_retry:
	cmp.b	#$10,d0                 ; record not found: restore first
	bne.s	rw_transfer
	bsr.w	restore
rw_seek:
	move.w	-$1a(a6),d0
	lsr.w	#1,d0                   ; cylinder
	bsr.w	seek
rw_transfer:
	movea.l	-$c(a6),a0
	move.w	-$18(a6),d1
	move.w	-$14(a6),d2
	bsr.s	rw_sectors
	tst.w	d0
	beq.s	rw_track_exit
	cmp.w	#$40,d0                 ; write protected: no more tries
	dbeq	d3,rw_retry
rw_track_exit:
	rts

rw_sectors:
	tst.b	-$7(a6)
	beq.s	read_sectors
	bra.w	write_sectors


;----------------------------------------------------------------------
; Read d2 sectors from d1 to a0 with one multiple sector read; stop the FDC when the DMA has
; moved them all.
;----------------------------------------------------------------------
read_sectors:
	bsr.w	dma_sector              ; DMA address, sector register
	move.w	#$90,$ffff8606.w        ; clear the DMA, sector count register
	move.w	#$190,$ffff8606.w       ; DMA mode / status
	move.w	#$90,$ffff8606.w        ; DMA mode / status
	moveq	#0,d0
	move.w	d2,d0                   ; sectors
	bsr.w	fdc_write
	lsl.l	#8,d0                   ; a1 = the end of the buffer
	add.l	d0,d0
	movea.l	a0,a1
	adda.l	d0,a1
	move.w	#$80,$ffff8606.w        ; DMA mode / status
	move.w	#$90,d0                 ; READ MULTIPLE SECTORS
	bsr.w	fdc_write
	move.l	#$40000,d0
	clr.l	-$4(a6)
read_wait:
	btst	#$5,$fffffa01.w         ; FDC interrupt?
	beq.s	read_done
	subq.l	#1,d0
	beq.s	read_timeout
	move.b	$ffff8609.w,-$3(a6)     ; where the DMA is
	move.b	$ffff860b.w,-$2(a6)     ; DMA base mid
	move.b	$ffff860d.w,-$1(a6)     ; DMA base low
	cmpa.l	-$4(a6),a1              ; all moved?
	bgt.s	read_wait
	bsr.w	force_interrupt         ; stop the FDC
read_done:
	move.w	#$90,$ffff8606.w        ; DMA mode / status
	move.w	$ffff8606.w,d0          ; DMA status
	btst	#$0,d0                  ; bit 0 clear: DMA error
	beq.s	read_fail
	bsr.w	read_status
	andi.b	#$18,d0                 ; RNF, CRC
	rts

read_timeout:
	bsr.w	force_interrupt
read_fail:
	moveq	#-1,d0
	rts


;----------------------------------------------------------------------
; Write d2 sectors from d1, one at a time (mode 1), or a track (mode 2).
;----------------------------------------------------------------------
write_sectors:
	bsr.s	dma_sector
	move.w	#$190,$ffff8606.w       ; clear the DMA, write, sector count register
	move.w	#$90,$ffff8606.w        ; DMA mode / status
	move.w	#$190,$ffff8606.w       ; DMA mode / status
	moveq	#1,d0                   ; one sector
	cmpi.b	#$1,-$7(a6)
	beq.s	write_count_set
	moveq	#31,d0                  ; or 31 for a track
write_count_set:
	bsr.w	fdc_write
	move.w	#$180,$ffff8606.w       ; command register, write
	move.w	#$a0,d0                 ; WRITE SECTOR
	cmpi.b	#$1,-$7(a6)
	beq.s	write_command
	move.w	#$f0,d0                 ; WRITE TRACK
	moveq	#1,d2
write_command:
	bsr.w	fdc_write
	move.l	#$40000,d0
write_wait:
	btst	#$5,$fffffa01.w         ; FDC interrupt?
	beq.s	write_done
	subq.l	#1,d0
	bne.s	write_wait
	bsr.w	force_interrupt
	moveq	#-1,d0
	rts

write_done:
	bsr.w	read_dma_status
	andi.b	#$5c,d0                 ; WP, RNF, CRC, lost data
	bne.s	write_exit
	lea	$200(a0),a0             ; next sector
	addq.b	#1,d1
	subq.b	#1,d2
	bne.s	write_sectors
write_exit:
	rts


;----------------------------------------------------------------------
; DMA address = a0, sector register = d1.
;----------------------------------------------------------------------
dma_sector:
	move.l	a0,d0
	move.b	d0,$ffff860d.w          ; DMA base low
	lsr.l	#8,d0
	move.b	d0,$ffff860b.w          ; DMA base mid
	lsr.l	#8,d0
	move.b	d0,$ffff8609.w          ; DMA base high
	move.w	#$84,$ffff8606.w        ; sector register
	move.w	d1,d0
	bsr.w	fdc_write
	rts


;----------------------------------------------------------------------
; Seek to cylinder d0 (restore when 0).
;----------------------------------------------------------------------
seek:
	tst.w	d0
	beq.s	restore
	move.w	#$86,$ffff8606.w        ; data register: the cylinder
	bsr.w	fdc_write
	move.w	#$10,d0                 ; SEEK
	bsr.w	fdc_command
	bmi.s	seek_exit
	moveq	#0,d0
seek_exit:
	rts


;----------------------------------------------------------------------
; Restore to track 0.
;----------------------------------------------------------------------
restore:
	moveq	#0,d0                   ; RESTORE
	bsr.w	fdc_command
	bmi.s	restore_exit
	eori.b	#$4,d0                  ; track 0?
	btst	#$2,d0
	bne.s	restore_exit
	moveq	#0,d0
restore_exit:
	rts


;----------------------------------------------------------------------
; Drive on: flock set, select, track register from track_table (restore when the track is
; not known).
;----------------------------------------------------------------------
drive_on:
	move.w	$43e.w,-$6(a6)          ; flock
	st	$43e.w                  ; flock
	bsr.s	select
	move.w	-$1c(a6),d0
	add.w	d0,d0
	move.w	#$82,$ffff8606.w        ; track register
	lea	track_table(pc),a0
	move.w	$0(a0,d0.w),d0
	lsr.w	#1,d0                   ; cylinder
	bsr.w	fdc_write
	cmp.w	#$a0,d0                 ; not known ($ffff): restore
	blt.s	drive_on_exit
	bsr.s	restore
drive_on_exit:
	rts


;----------------------------------------------------------------------
; Drive off: keep the track in track_table, deselect, flock back.  The delay before the
; deselect is for a negative mode, which nothing uses.
;----------------------------------------------------------------------
drive_off:
	movem.l	d0-d1,-(sp)
	move.w	-$1c(a6),d0
	add.w	d0,d0
	lea	track_table(pc),a0
	move.w	-$1a(a6),d1
	move.w	d1,$0(a0,d0.w)
	tst.w	-$8(a6)                 ; never negative
	bpl.s	drive_off_deselect
	move.l	#$c3500,d0
	bsr.w	delay
drive_off_deselect:
	move.b	#$7,d0                  ; deselect
	bsr.s	psg_port_a
	move.w	-$6(a6),$43e.w          ; flock
	movem.l	(sp)+,d0-d1
	rts


;----------------------------------------------------------------------
; Select the drive and side through PSG port A.
;----------------------------------------------------------------------
select:
	move.w	d0,-(sp)
	move.w	-$1c(a6),d0
	andi.w	#$1,d0
	addq.b	#1,d0                   ; drive A: bit 1, drive B: bit 2
	add.b	d0,d0
	move.w	d0,-(sp)
	move.w	-$10(a6),d0
	cmp.w	#$1,d0                  ; both sides?
	beq.s	select_side
	move.w	-$e(a6),d0              ; the side from d0 bit 2
	bra.s	select_bits

select_side:
	move.w	-$1a(a6),d0             ; the side from the logical track
	andi.w	#$1,d0
select_bits:
	or.w	(sp)+,d0
	eori.b	#$7,d0                  ; active low
	andi.b	#$7,d0
	bsr.s	psg_port_a
	move.w	(sp)+,d0
	rts


;----------------------------------------------------------------------
; PSG port A bits 0-2 = d0: side, drive A, drive B, all active low.
;----------------------------------------------------------------------
psg_port_a:
	move.w	sr,-(sp)
	ori.w	#$700,sr
	move.b	#$e,$ffff8800.w         ; port A
	move.b	$ffff8800.w,d1          ; PSG register select
	andi.b	#$f8,d1
	or.b	d0,d1
	move.b	d1,$ffff8802.w          ; PSG write data
	move.w	(sp)+,sr
	rts


;----------------------------------------------------------------------
; Type I or II command d0 (step rate 3 ms for type I), wait for the FDC with a timeout.
;----------------------------------------------------------------------
fdc_command:
	cmp.b	#$80,d0                 ; type I?
	bcc.s	fdc_command_go
	ori.b	#$3,d0                  ; step rate 3 ms
fdc_command_go:
	move.w	#$80,$ffff8606.w        ; DMA mode / status
	bsr.s	fdc_write
	move.l	#$60000,d0
fdc_command_wait:
	btst	#$5,$fffffa01.w         ; FDC interrupt?
	beq.s	read_status
	subq.l	#1,d0
	bne.s	fdc_command_wait
	bsr.s	force_interrupt
	moveq	#-1,d0
	rts


;----------------------------------------------------------------------
; FORCE INTERRUPT: stop the FDC.
;----------------------------------------------------------------------
force_interrupt:
	move.w	#$80,$ffff8606.w        ; DMA mode / status
	move.w	#$d0,d0                 ; FORCE INTERRUPT
	bsr.s	fdc_write
	moveq	#15,d0
	bsr.s	delay
	bra.s	read_status


;----------------------------------------------------------------------
; FDC status in d0: with the DMA set to write, or (read_status) to read.
;----------------------------------------------------------------------
read_dma_status:
	move.w	#$180,$ffff8606.w       ; DMA mode / status
	bra.s	read_status_reg

read_status:
	move.w	#$80,$ffff8606.w        ; DMA mode / status
read_status_reg:
	bsr.s	fdc_delay
	move.w	$ffff8604.w,d0          ; DMA sector count / FDC access
	andi.l	#$ff,d0
	bra.s	fdc_delay


;----------------------------------------------------------------------
; Write d0 to the FDC register the DMA mode selects.
;----------------------------------------------------------------------
fdc_write:
	bsr.s	fdc_delay
	move.w	d0,$ffff8604.w          ; DMA sector count / FDC access
fdc_delay:
	move.w	sr,-(sp)
	move.w	d0,-(sp)
	moveq	#24,d0
	bsr.s	delay
	move.w	(sp)+,d0
	move.w	(sp)+,sr
	rts


;----------------------------------------------------------------------
; Wait d0 steps.
;----------------------------------------------------------------------
delay:
	subq.l	#1,d0
	bne.s	delay
	rts


;----------------------------------------------------------------------
; Pack-Ice 2.31: unpack the file at a0 ("Ice!", packed length, unpacked length, data)
; in place.  The bits and literal bytes are read from the end of the packed data
; backwards and the output is written from its end backwards.
;----------------------------------------------------------------------
ice_depack:
	movem.l	d0-d7/a0-a6,-(sp)
	cmpi.l	#$49636521,(a0)+        ; 'Ice!'
	bne.s	ice_exit
	move.l	(a0)+,d0                ; packed length
	lea	-$8(a0,d0.l),a5         ; a5 = end of the packed data, read backwards
	move.l	(a0)+,(sp)              ; unpacked length
	lea	$6c(a0),a4              ; output from 120 bytes on, moved down at the end
	movea.l	a4,a6
	adda.l	(sp),a6
	movea.l	a6,a3
	movea.l	a6,a1
	lea	track_table(pc),a2      ; keep the 120 bytes after the output
	moveq	#119,d0
save_end_loop:
	move.b	-(a1),-(a2)
	dbra	d0,save_end_loop
	bsr.w	get_first_long          ; first long of bits
	bsr.s	ice_next
	move.l	(sp),d0
	lea	-$78(a4),a1             ; move the output down by 120
move_down_loop:
	move.b	(a4)+,(a1)+
	dbra	d0,move_down_loop
	subi.l	#$10000,d0
	bpl.s	move_down_loop
	moveq	#119,d0
	lea	track_table(pc),a2      ; put the 120 bytes back
restore_end_loop:
	move.b	-(a2),-(a3)
	dbra	d0,restore_end_loop
ice_exit:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

ice_next:
	bsr.s	get_bit                 ; literals?
	bcc.s	ice_check_end
	moveq	#0,d1
	bsr.s	get_bit
	bcc.s	literal_copy_loop
	lea	literal_base(pc),a1     ; literal count: 2, 2, 3, 8, 15 bits
	moveq	#4,d3
literal_count_loop:
	move.l	-(a1),d0
	bsr.s	get_bits
	swap	d0
	cmp.w	d0,d1
	dbne	d3,literal_count_loop
	add.l	$14(a1),d1
literal_copy_loop:
	move.b	-(a5),-(a6)             ; literal bytes, backwards
	dbra	d1,literal_copy_loop
ice_check_end:
	cmpa.l	a4,a6                   ; all written?
	bgt.s	ice_match
	rts

get_first_long:
	moveq	#3,d0
first_long_loop:
	move.b	-(a5),d7
	ror.l	#8,d7
	dbra	d0,first_long_loop
	rts

refill_bits:
	move.w	a5,d7
	btst	#$0,d7
	bne.s	refill_bits_odd
	move.l	-(a5),d7
	addx.l	d7,d7
	bra.s	get_bits_add

refill_bits_odd:
	move.l	-$5(a5),d7
	lsl.l	#8,d7
	move.b	-(a5),d7
	subq.l	#3,a5
	add.l	d7,d7
	bset	#$0,d7
	bra.s	get_bits_add

get_bit:
	add.l	d7,d7                   ; next bit; a sentinel 1 marks the end of the long
	beq.s	refill_bit
	rts

refill_bit:
	move.w	a5,d7
	btst	#$0,d7
	bne.s	refill_bit_odd
	move.l	-(a5),d7
	addx.l	d7,d7
	rts

refill_bit_odd:
	move.l	-$5(a5),d7
	lsl.l	#8,d7
	move.b	-(a5),d7
	subq.l	#3,a5
	add.l	d7,d7
	bset	#$0,d7
	rts

get_bits:
	moveq	#0,d1                   ; d0 + 1 bits, the first highest
get_bits_loop:
	add.l	d7,d7
	beq.s	refill_bits
get_bits_add:
	addx.w	d1,d1
	dbra	d0,get_bits_loop
	rts

ice_match:
	lea	length_table(pc),a1     ; match length: up to 4 leading ones pick the table entry
	moveq	#3,d2
match_len_loop:
	bsr.s	get_bit
	dbcc	d2,match_len_loop
	moveq	#0,d4
	moveq	#0,d1
	move.b	$1(a1,d2.w),d0
	ext.w	d0
	bmi.s	match_len_base
	bsr.s	get_bits
match_len_base:
	move.b	$6(a1,d2.w),d4
	add.w	d1,d4
	beq.s	match_short
	lea	distance_table(pc),a1
	moveq	#1,d2
match_dist_loop:
	bsr.s	get_bit                 ; distance: 5, 8 or 12 bits
	dbcc	d2,match_dist_loop
	moveq	#0,d1
	move.b	$1(a1,d2.w),d0
	ext.w	d0
	bsr.s	get_bits
	add.w	d2,d2
	add.w	$6(a1,d2.w),d1
	bra.s	match_copy

match_short:
	moveq	#0,d1                   ; a 2 byte match: 6 or 9 bit distance
	moveq	#5,d0
	moveq	#0,d2
	bsr.s	get_bit
	bcc.s	match_short_bits
	moveq	#8,d0
	moveq	#64,d2
match_short_bits:
	bsr.s	get_bits
	add.w	d2,d1
match_copy:
	lea	$2(a6,d4.w),a1          ; copy from after the output written so far
	adda.w	d1,a1
	move.b	-(a1),-(a6)
match_copy_loop:
	move.b	-(a1),-(a6)
	dbra	d4,match_copy_loop
	bra.w	ice_next


; Literal count table: (largest value, bits - 1), read from the end backwards.
literal_table:
	dc.w	$7fff,$000e,$00ff,$0007,$0007,$0002,$0003,$0001
	dc.w	$0003,$0001

; What each literal count entry adds.
literal_base:
	dc.w	$0000,$010d,$0000,$000e,$0000,$0007,$0000,$0004
	dc.w	$0000,$0001

; Match length: bits - 1 and base, indexed by the leading ones (-1..3).
length_table:
	dc.w	$0901,$00ff,$ff08,$0402,$0100

; Match distance: bits - 1, then the bases as words.
distance_table:
	dc.w	$0b04,$0700,$0120,$0000,$0020

; The 120 bytes after the output are kept here while it is moved down.
end_save:
	dcb.b	120,$00

; Current track of each drive.
track_table:
	dc.w	$ffff,$ffff,$ffff,$ffff

; The game loader stage 3 copies to $21000 (4 KB from here, so it runs on past the end).
game_loader_image:
	incbin	"gameload.bin"          ; the game loader: loader.bin up to here

	end
