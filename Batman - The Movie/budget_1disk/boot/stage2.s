; Batman The Movie (Ocean, 1989) - 1 disk budget release (The Hit Squad)
; Stage 2: track 0 sectors 2-8 as the boot sector read them to $10000 (stage2.bin).
;
; Copies the depacker part ($1001c on) to $60000 and runs it there; it copies the
; packed stage 3 (stage3.ice) back to $10000, unpacks it in place with Pack-Ice 2.31 and
; jumps to it (stage3.s).  The part copied to $60000 is PC relative and is shown where
; the disk puts it.  This source assembles to stage2.bin.

	opt	o-
	org	$10000

;----------------------------------------------------------------------
; Copy unpack_stage3 and what follows it to $60000 and run it there.
;----------------------------------------------------------------------
stage2_start:
	lea	unpack_stage3(pc),a0
	lea	$60000,a1               ; runs there
	move.l	#$d07,d7                ; $d08 bytes
copy_up_loop:
	move.b	(a0)+,(a1)+
	dbra	d7,copy_up_loop
	jmp	$60000                  ; unpack_stage3 at $60000


;----------------------------------------------------------------------
; Run at $60000: the packed stage 3 to $10000, unpack it and run it.
;----------------------------------------------------------------------
unpack_stage3:
	lea	packed_stage3(pc),a0
	lea	$10000,a1               ; over stage 2, where stage 3 runs
	move.l	#$ae7,d7                ; $ae8 bytes
copy_packed_loop:
	move.b	(a0)+,(a1)+
	dbra	d7,copy_packed_loop
	lea	$10000,a0
	bsr.s	ice_depack              ; unpack it
	jmp	$10000                  ; run stage 3


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
	lea	packed_stage3(pc),a2    ; keep the 120 bytes after the output
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
	lea	packed_stage3(pc),a2    ; put the 120 bytes back
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

; Stage 3, packed.
packed_stage3:
	incbin	"stage3.ice"            ; stage 3, Pack-Ice packed

	end
