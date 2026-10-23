; TCLIB.S  -  Turbo C 2.0 library code of FCOPYPRO.PRG, included by FCOPYPRO.S
;
; qsort, atoi/atol, itoa/ltoa, string and memory functions, long multiply and divide,
; the GEMDOS/BIOS/XBIOS and AES bindings and the Line-A bindings.  It sits at the end of
; the text section.  Its variables are errno (FCOPYPRO.S) and the AES arrays and Line-A
; pointers (BSS.S).


;----------------------------------------------------------------------
; qsort: qsort_swap exchanges d0 bytes at a0 and a1, qsort_sort sorts d0 elements of
; d1 bytes at a0 with the compare function in a1.
;----------------------------------------------------------------------
qsort_swap:
	move.b	(a1),d1
	move.b	(a0),(a1)+
	move.b	d1,(a0)+
	subq.l	#1,d0
	bne.s	qsort_swap
	rts


qsort_sort:
	movem.l	d3-d5/a2-a5,-(sp)
	movea.l	a0,a3
	move.l	d0,d3
	movea.l	a1,a2
	move.l	d1,d4
.next_partition
	moveq	#2,d0
	cmp.l	d3,d0
	bcs.s	.median_of_three
	cmp.l	d3,d0
	bne.w	.return
	lea	$0(a3,d4.l),a4
	movea.l	a4,a1
	movea.l	a3,a0
	jsr	(a2)
	tst.w	d0
	ble.w	.return
	move.l	d4,d0
	movea.l	a4,a1
	movea.l	a3,a0
	jsr	qsort_swap(pc)
	bra.w	.return

.median_of_three
	moveq	#-1,d0
	add.l	d3,d0
	move.l	d4,d1
	jsr	lmul(pc)
	lea	$0(a3,d0.l),a4
	move.l	d3,d0
	lsr.l	#1,d0
	move.l	d4,d1
	jsr	lmul(pc)
	lea	$0(a3,d0.l),a5
	movea.l	a4,a1
	movea.l	a5,a0
	jsr	(a2)
	tst.w	d0
	ble.s	.compare_first
	move.l	d4,d0
	movea.l	a4,a1
	movea.l	a5,a0
	jsr	qsort_swap(pc)
.compare_first
	movea.l	a3,a1
	movea.l	a5,a0
	jsr	(a2)
	tst.w	d0
	ble.s	.compare_last
	move.l	d4,d0
	movea.l	a3,a1
	movea.l	a5,a0
	jsr	qsort_swap(pc)
	bra.s	.three_left

.compare_last
	movea.l	a4,a1
	movea.l	a3,a0
	jsr	(a2)
	tst.w	d0
	ble.s	.three_left
	move.l	d4,d0
	movea.l	a4,a1
	movea.l	a3,a0
	jsr	qsort_swap(pc)
.three_left
	moveq	#3,d0
	cmp.l	d3,d0
	bne.s	.scan_init
	movea.l	a5,a1
	movea.l	a3,a0
	move.l	d4,d0
	jsr	qsort_swap(pc)
	bra.w	.return

.scan_init
	lea	$0(a3,d4.l),a5
	bra.s	.compare_left

.scan_up
	cmpa.l	a5,a4
	bls.s	.place_pivot
	adda.l	d4,a5
.compare_left
	movea.l	a3,a1
	movea.l	a5,a0
	jsr	(a2)
	tst.w	d0
	blt.s	.scan_up
	bra.s	.check_crossed

.scan_down
	movea.l	a4,a1
	movea.l	a3,a0
	jsr	(a2)
	tst.w	d0
	bgt.s	.qsort_swap
	suba.l	d4,a4
	bra.s	.check_crossed

.qsort_swap
	move.l	d4,d0
	movea.l	a4,a1
	movea.l	a5,a0
	jsr	qsort_swap(pc)
	adda.l	d4,a5
	suba.l	d4,a4
	bra.s	.check_done

.check_crossed
	cmpa.l	a5,a4
	bhi.s	.scan_down
.check_done
	cmpa.l	a5,a4
	bhi.s	.compare_left
.place_pivot
	movea.l	a3,a1
	movea.l	a5,a0
	jsr	(a2)
	tst.w	d0
	bge.s	.recurse_smaller
	move.l	d4,d0
	movea.l	a3,a1
	movea.l	a5,a0
	jsr	qsort_swap(pc)
.recurse_smaller
	move.l	a5,d0
	sub.l	a3,d0
	move.l	d4,d1
	jsr	uldiv(pc)
	move.l	d0,d5
	sub.l	d5,d3
	cmp.l	d3,d5
	bls.s	.sort_right
	moveq	#1,d1
	cmp.l	d3,d1
	bcc.s	.continue_left
	movea.l	a2,a1
	movea.l	a5,a0
	move.l	d3,d0
	move.l	d4,d1
	jsr	qsort_sort(pc)
.continue_left
	move.l	d5,d3
	bra.w	.next_partition

.sort_right
	moveq	#1,d0
	cmp.l	d5,d0
	bcc.s	.continue_right
	move.l	d4,d1
	movea.l	a2,a1
	movea.l	a3,a0
	move.l	d5,d0
	jsr	qsort_sort(pc)
.continue_right
	movea.l	a5,a3
	bra.w	.next_partition

.return
	movem.l	(sp)+,d3-d5/a2-a5
	rts


qsort:
	tst.l	d1
	beq.s	.return
	jsr	qsort_sort(pc)
.return
	rts


atoi:
	move.w	d3,-(sp)
	move.w	d4,-(sp)
	clr.w	d0
	lea	ctype_table(pc),a1
.skip_space
	move.b	(a0)+,d0
	beq.s	.negate
	move.b	$0(a1,d0.w),d0
	bmi.s	.skip_space
	clr.w	d0
	clr.w	d1
	move.b	#$9,d3
	lea	digit_table(pc),a1
	move.b	-$1(a0),d1
	cmp.b	#$2d,d1                         ; '-'
	seq	d2
	beq.s	.sign
	cmp.b	#$2b,d1                         ; '+'
	bne.s	.first_digit
.sign
	move.b	(a0)+,d1
	beq.s	.negate
.first_digit
	move.b	$0(a1,d1.w),d1
	cmp.b	d3,d1
	bhi.s	.negate
.digits
	add.w	d1,d0
	move.b	(a0)+,d1
	beq.s	.negate
	move.b	$0(a1,d1.w),d1
	cmp.b	d3,d1
	bhi.s	.negate
	add.w	d0,d0
	move.w	d0,d4
	add.w	d0,d0
	add.w	d0,d0
	add.w	d4,d0
	bra.s	.digits

.negate
	tst.b	d2
	beq.s	.finish
	neg.w	d0
.finish
	move.w	(sp)+,d4
	move.w	(sp)+,d3
	rts


atol:
	move.w	d3,-(sp)
	move.l	d4,-(sp)
	clr.l	d0
	lea	ctype_table(pc),a1
.skip_space
	move.b	(a0)+,d0
	beq.s	.finish
	move.b	$0(a1,d0.w),d0
	bmi.s	.skip_space
	moveq	#0,d0
	moveq	#0,d1
	move.w	#$9,d3
	move.b	-$1(a0),d1
	cmp.b	#$2d,d1                         ; '-'
	seq	d2
	beq.s	.sign
	cmp.b	#$2b,d1                         ; '+'
	bne.s	.first_digit
.sign
	move.b	(a0)+,d1
	beq.s	.negate
.first_digit
	lea	digit_table(pc),a1
	move.b	$0(a1,d1.w),d1
	cmp.b	d3,d1
	bhi.s	.negate
.digits
	add.l	d1,d0
	move.b	(a0)+,d1
	beq.s	.negate
	move.b	$0(a1,d1.w),d1
	cmp.b	d3,d1
	bhi.s	.negate
	add.l	d0,d0
	move.l	d0,d4
	add.l	d0,d0
	add.l	d0,d0
	add.l	d4,d0
	bra.s	.digits

.negate
	tst.b	d2
	beq.s	.finish
	neg.l	d0
.finish
	move.l	(sp)+,d4
	move.w	(sp)+,d3
	rts


itoa:
	move.l	d3,-(sp)
	move.l	a0,-(sp)
	lea	-$12(sp),sp
	move.w	d1,d2
	subq.w	#2,d2
	cmp.w	#$22,d2
	bhi.s	.bad_radix
	tst.w	d0
	bpl.s	.convert
	cmp.b	#$a,d1
	bne.s	.convert
	neg.w	d0
	move.b	#$2d,(a0)+                      ; '-'
.convert
	lea	$12(sp),a1
	moveq	#-1,d2
	swap	d0
	clr.w	d0
	swap	d0
.divide
	divu.w	d1,d0
	move.l	d0,d3
	swap	d3
	move.b	itoa_digits(pc,d3.w),-(a1)
	addq.w	#1,d2
	swap	d0
	clr.w	d0
	swap	d0
	bne.s	.divide
.copy_digits
	move.b	(a1)+,(a0)+
	dbra	d2,.copy_digits
.terminate
	clr.b	(a0)+
	lea	$12(sp),sp
	movea.l	(sp)+,a0
	move.l	(sp)+,d3
	rts

.bad_radix
	move.w	#$21,errno
	bra.s	.terminate

itoa_digits:
	dc.b	'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'

ltoa:
	move.l	d3,-(sp)
	move.l	a0,-(sp)
	suba.w	#$22,sp
	move.w	d1,d2
	subq.w	#2,d2
	cmp.w	#$22,d2
	bhi.s	.bad_radix
	tst.l	d0
	bpl.s	.convert
	cmp.b	#$a,d1
	bne.s	.convert
	move.b	#$2d,(a0)+                      ; '-'
	neg.l	d0
.convert
	lea	$22(sp),a1
	moveq	#-1,d2
	move.l	d0,d3
	swap	d3
	tst.w	d3
	bne.s	.long_value
.divide_word
	divu.w	d1,d0
	move.l	d0,d3
	swap	d3
	move.b	ltoa_digits(pc,d3.w),-(a1)
	addq.w	#1,d2
	swap	d0
	clr.w	d0
	swap	d0
	bne.s	.divide_word
	bra.s	.copy_digits

.long_value
	move.w	d4,-(sp)
.divide_long
	move.l	d0,d3
	move.w	d0,d4
	clr.w	d3
	swap	d3
	divu.w	d1,d3
	move.w	d3,d0
	move.w	d4,d3
	divu.w	d1,d3
	swap	d0
	move.w	d3,d0
	swap	d3
	move.b	ltoa_digits(pc,d3.w),-(a1)
	addq.w	#1,d2
	tst.l	d0
	bne.s	.divide_long
	move.w	(sp)+,d4
.copy_digits
	move.b	(a1)+,(a0)+
	dbra	d2,.copy_digits
.terminate
	clr.b	(a0)+
	adda.w	#$22,sp
	movea.l	(sp)+,a0
	move.l	(sp)+,d3
	rts

.bad_radix
	move.w	#$21,errno
	bra.s	.terminate

ltoa_digits:
	dc.b	'0123456789abcdefghijklmnopqrstuvwxyz'

strcat:
	move.l	a0,d0
.find_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	bne.s	.find_end
.at_end
	subq.w	#1,a0
.copy
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	bne.s	.copy
.finish
	movea.l	d0,a0
	rts


strchr:
	move.b	(a0)+,d1
	beq.s	.end_of_string
	cmp.b	d1,d0
	bne.s	strchr
.found
	subq.w	#1,a0
	rts

.end_of_string
	tst.b	d0
	beq.s	.found
	suba.l	a0,a0
	rts


strrchr:
	suba.l	a1,a1
.scan
	move.b	(a0)+,d1
	beq.s	.at_end
	cmp.b	d0,d1
	bne.s	.scan
	lea	-$1(a0),a1
	bra.s	.scan

.at_end
	tst.b	d0
	beq.s	.finish
	movea.l	a1,a0
	rts

.finish
	subq.w	#1,a0
	rts


strcmp:
	move.b	(a0)+,d0
	beq.s	.end_of_first
	cmp.b	(a1)+,d0
	bne.s	.differ
	move.b	(a0)+,d0
	beq.s	.end_of_first
	cmp.b	(a1)+,d0
	bne.s	.differ
	move.b	(a0)+,d0
	beq.s	.end_of_first
	cmp.b	(a1)+,d0
	bne.s	.differ
	move.b	(a0)+,d0
	beq.s	.end_of_first
	cmp.b	(a1)+,d0
	bne.s	.differ
	move.b	(a0)+,d0
	beq.s	.end_of_first
	cmp.b	(a1)+,d0
	bne.s	.differ
	move.b	(a0)+,d0
	beq.s	.end_of_first
	cmp.b	(a1)+,d0
	bne.s	.differ
	move.b	(a0)+,d0
	beq.s	.end_of_first
	cmp.b	(a1)+,d0
	bne.s	.differ
	move.b	(a0)+,d0
	beq.s	.end_of_first
	cmp.b	(a1)+,d0
	beq.s	strcmp
.differ
	cmp.b	-(a1),d0
	bcs.s	.less
	moveq	#1,d0
	rts

.less
	moveq	#-1,d0
	rts

.end_of_first
	tst.b	(a1)
	bne.s	.less
	moveq	#0,d0
	rts


strcpy:
	move.l	a0,d0
.copy
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	beq.s	.finish
	move.b	(a1)+,(a0)+
	bne.s	.copy
.finish
	movea.l	d0,a0
	rts


strlen:
	movea.l	a0,a1
.scan
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	beq.s	.at_end
	tst.b	(a0)+
	bne.s	.scan
.at_end
	move.l	a0,d0
	sub.l	a1,d0
	subq.l	#1,d0
	rts


strncmp:
	subq.l	#1,d0
	bcs.s	.result_0
	move.b	(a0)+,d1
	beq.s	.end_of_first
	cmp.b	(a1)+,d1
	beq.s	strncmp
	bhi.s	.result_1
.less
	moveq	#-1,d0
	rts

.end_of_first
	tst.b	(a1)+
	bne.s	.less
.result_0
	moveq	#0,d0
	rts

.result_1
	moveq	#1,d0
	rts


memcmp:
	subq.l	#1,d0
	bcs.s	.result_0
	cmpm.b	(a1)+,(a0)+
	beq.s	memcmp
	bcs.s	.result_minus_1
	moveq	#1,d0
	rts

.result_minus_1
	moveq	#-1,d0
	rts

.result_0
	moveq	#0,d0
	rts


memcpy:
	tst.l	d0
	beq.w	.return
	move.l	a0,-(sp)
	cmpa.l	a0,a1
	bhi.w	.forward
	beq.w	.finish
	adda.l	d0,a1
	adda.l	d0,a0
	move.w	a1,d1
	move.w	a0,d2
	btst	#$0,d1
	beq.s	.backward_dest_check
	btst	#$0,d2
	bne.s	.backward_align
.backward_bytes
	move.b	-(a1),-(a0)
	subq.l	#1,d0
	bne.s	.backward_bytes
	bra.w	.finish

.backward_dest_check
	btst	#$0,d2
	bne.s	.backward_bytes
	bra.s	.backward_blocks

.backward_align
	move.b	-(a1),-(a0)
	subq.l	#1,d0
	beq.w	.finish
.backward_blocks
	move.l	d0,d1
	lsr.l	#5,d1
	lsr.l	#4,d1
	beq.w	.backward_longs
	movem.l	d2-d7/a3-a6,-(sp)
.backward_512
	movem.l	-$28(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$50(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$78(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$a0(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$c8(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$f0(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$118(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$140(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$168(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$190(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$1b8(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$1e0(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$200(a1),d2-d7/a3-a4
	movem.l	d2-d7/a3-a4,-(a0)
	suba.w	#$200,a1
	subq.l	#1,d1
	bne.w	.backward_512
	movem.l	(sp)+,d2-d7/a3-a6
.backward_longs
	move.w	d0,d1
	dc.w	$c07c,$1ff                      ; and.w #$1ff,d0
	lsr.w	#2,d0
	beq.s	.backward_tail
	subq.w	#1,d0
.backward_long
	move.l	-(a1),-(a0)
	dbra	d0,.backward_long
.backward_tail
	dc.w	$c27c,$3                        ; and.w #$3,d1
	beq.w	.finish
	subq.w	#1,d1
.backward_byte
	move.b	-(a1),-(a0)
	dbra	d1,.backward_byte
	bra.w	.finish

.forward
	move.w	a1,d1
	move.w	a0,d2
	btst	#$0,d1
	beq.s	.forward_dest_check
	btst	#$0,d2
	bne.s	.forward_align
.forward_bytes
	move.b	(a1)+,(a0)+
	subq.l	#1,d0
	bne.s	.forward_bytes
	bra.w	.finish

.forward_dest_check
	btst	#$0,d2
	bne.s	.forward_bytes
	bra.s	.forward_blocks

.forward_align
	move.b	(a1)+,(a0)+
	subq.l	#1,d0
.forward_blocks
	move.l	d0,d1
	lsr.l	#5,d1
	lsr.l	#4,d1
	beq.w	.forward_longs
	movem.l	d2-d7/a3-a6,-(sp)
.forward_512
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$28(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$50(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$78(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$a0(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$c8(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$f0(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$118(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$140(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$168(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$190(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$1b8(a0)
	movem.l	(a1)+,d2-d7/a3-a4
	movem.l	d2-d7/a3-a4,$1e0(a0)
	adda.w	#$200,a0
	subq.l	#1,d1
	bne.w	.forward_512
	movem.l	(sp)+,d2-d7/a3-a6
.forward_longs
	move.w	d0,d1
	dc.w	$c07c,$1ff                      ; and.w #$1ff,d0
	lsr.w	#2,d0
	beq.s	.forward_tail
	subq.w	#1,d0
.forward_long
	move.l	(a1)+,(a0)+
	dbra	d0,.forward_long
.forward_tail
	dc.w	$c27c,$3                        ; and.w #$3,d1
	beq.s	.finish
	subq.w	#1,d1
.forward_byte
	move.b	(a1)+,(a0)+
	dbra	d1,.forward_byte
.finish
	movea.l	(sp)+,a0
.return
	rts


memset:
	move.l	a0,-(sp)
	adda.l	d1,a0
	move.l	a0,d2
	btst	#$0,d2
	beq.s	.even
	subq.l	#1,d1
	bcs.w	.finish
	move.b	d0,-(a0)
.even
	move.b	d0,-(sp)
	move.w	(sp)+,d2
	move.b	d0,d2
	move.w	d2,d0
	swap	d2
	move.w	d0,d2
	move.l	d1,d0
	lsr.l	#8,d0
	lsr.l	#2,d0
	beq.s	.longs
	movem.l	d1/d3-d7/a2-a6,-(sp)
	move.l	d2,d1
	move.l	d2,d3
	move.l	d2,d4
	move.l	d2,d5
	move.l	d2,d6
	move.l	d2,d7
	movea.l	d2,a1
	movea.l	d2,a2
	movea.l	d2,a3
	movea.l	d2,a4
	movea.l	d2,a5
	movea.l	d2,a6
.fill_block
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a6,-(a0)
	movem.l	d1-d7/a1-a2,-(a0)
	subq.l	#1,d0
	bne.s	.fill_block
	movem.l	(sp)+,d1/d3-d7/a2-a6
	dc.w	$c27c,$3ff                      ; and.w #$3ff,d1
.longs
	move.w	d1,d0
	lsr.w	#2,d0
	beq.s	.tail
	subq.w	#1,d0
.fill_long
	move.l	d2,-(a0)
	dbra	d0,.fill_long
.tail
	dc.w	$c27c,$3                        ; and.w #$3,d1
	beq.s	.finish
	subq.w	#1,d1
.fill_byte
	move.b	d2,-(a0)
	dbra	d1,.fill_byte
.finish
	movea.l	(sp)+,a0
	rts

ctype_table:
	dc.b	'@@@@@@@@@'
	dc.b	$c0,$c0,$c0,$c0,$c0
	dc.b	'@@@@@@@@@@@@@@@@@@'
	dc.w	$8001,$0101,$0101,$0101,$0101,$0101,$0101,$0101
	dc.w	$1212,$1212,$1212,$1212,$1212,$0101,$0101,$0101
	dc.b	$00
	dc.b	'::::::88888888888888888888'
	dc.b	$01,$01,$01,$01,$01,$01
	dc.b	'66666644444444444444444444'
	dc.b	$01,$01,$01,$01,$40,$08,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
	dc.b	$04,$04,$04,$08,$08,$08,$04,$08,$04,$04,$04,$04,$04,$04,$04,$04
	dc.b	$04,$08,$04,$04,$04,$04,$04,$04,$04,$04,$08,$04,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$04,$04,$08,$04,$04,$08,$08,$08,$08,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00
digit_table:
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$0001,$0203,$0405,$0607,$0809,$ffff,$ffff,$ffff
	dc.w	$ff0a,$0b0c,$0d0e,$0f10,$1112,$1314,$1516,$1718
	dc.w	$191a,$1b1c,$1d1e,$1f20,$2122,$23ff,$ffff,$ffff
	dc.w	$ff0a,$0b0c,$0d0e,$0f10,$1112,$1314,$1516,$1718
	dc.w	$191a,$1b1c,$1d1e,$1f20,$2122,$23ff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff

lmul:
	move.l	d0,d2                           ; d0 * d1 (32 bit result)
	swap	d2
	tst.w	d2
	bne.s	.long_first
	move.l	d1,d2
	swap	d2
	tst.w	d2
	bne.s	.long_second
	mulu.w	d1,d0
	rts

.long_second
	mulu.w	d0,d2
	swap	d2
	mulu.w	d1,d0
	add.l	d2,d0
	rts

.long_first
	mulu.w	d1,d2
	swap	d2
	mulu.w	d1,d0
	add.l	d2,d0
	rts


uldiv:
	move.l	d1,d2
	swap	d2
	tst.w	d2
	bne.s	.long_divisor
	move.l	d0,d2
	swap	d2
	tst.w	d2
	bne.s	.long_dividend
	divu.w	d1,d0
	swap	d0
	clr.w	d0
	swap	d0
	rts

.long_dividend
	clr.w	d0
	swap	d0
	swap	d2
	divu.w	d1,d0
	movea.w	d0,a0
	move.w	d2,d0
	divu.w	d1,d0
	swap	d0
	move.w	a0,d0
	swap	d0
	rts

.long_divisor
	movea.l	d1,a0
	swap	d0
	moveq	#0,d1
	move.w	d0,d1
	clr.w	d0
	moveq	#15,d2
	add.l	d0,d0
	addx.l	d1,d1
.shift_subtract
	sub.l	a0,d1
	bcc.s	.next_bit
	add.l	a0,d1
.next_bit
	addx.l	d0,d0
	addx.l	d1,d1
	dbra	d2,.shift_subtract
	not.w	d0
	rts


ldiv:
	move.l	d0,d2
	bpl.s	.positive_dividend
	neg.l	d0
.positive_dividend
	eor.l	d1,d2
	movea.l	d2,a1
	tst.l	d1
	bpl.s	.positive_divisor
	neg.l	d1
.positive_divisor
	move.l	d1,d2
	swap	d2
	tst.w	d2
	bne.s	.long_divisor
	move.l	d0,d2
	swap	d2
	tst.w	d2
	bne.s	.long_dividend
	divu.w	d1,d0
	swap	d0
	clr.w	d0
	swap	d0
	move.l	a1,d2
	bpl.s	.return
	neg.l	d0
.return
	rts

.long_dividend
	clr.w	d0
	swap	d0
	swap	d2
	divu.w	d1,d0
	movea.w	d0,a0
	move.w	d2,d0
	divu.w	d1,d0
	swap	d0
	move.w	a0,d0
	swap	d0
	move.l	a1,d2
	bpl.s	.return2
	neg.l	d0
.return2
	rts

.long_divisor
	movea.l	d1,a0
	swap	d0
	moveq	#0,d1
	move.w	d0,d1
	clr.w	d0
	moveq	#15,d2
	add.l	d0,d0
	addx.l	d1,d1
.shift_subtract
	sub.l	a0,d1
	bcc.s	.next_bit
	add.l	a0,d1
.next_bit
	addx.l	d0,d0
	addx.l	d1,d1
	dbra	d2,.shift_subtract
	not.w	d0
	move.l	a1,d2
	bpl.s	.return3
	neg.l	d0
.return3
	rts


;----------------------------------------------------------------------
; GEMDOS, BIOS and XBIOS bindings.
;----------------------------------------------------------------------
Fread:
	move.l	a0,-(sp)
	move.l	d1,-(sp)
	move.w	d0,-(sp)
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	lea	$c(sp),sp
	rts


Pterm0:
	move.w	#$0,-(sp)
	trap	#1                              ; Pterm0

Fsetdta:
	move.l	a0,-(sp)
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.w	#6,sp
	rts


Fsfirst:
	move.w	d0,-(sp)
	move.l	a0,-(sp)
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.w	#8,sp
	rts


Crawcin:
	move.w	#$7,-(sp)
	trap	#1                              ; Crawcin
	addq.w	#2,sp
	rts


Dgetdrv:
	move.w	#$19,-(sp)
	trap	#1                              ; Dgetdrv
	addq.w	#2,sp
	rts


Fgetdta:
	move.w	#$2f,-(sp)
	trap	#1                              ; Fgetdta
	addq.w	#2,sp
	movea.l	d0,a0
	rts


Fsnext:
	move.w	#$4f,-(sp)
	trap	#1                              ; Fsnext
	addq.w	#2,sp
	rts


Cconout:
	move.w	d0,-(sp)
	move.w	#$2,-(sp)
	trap	#1                              ; Cconout
	addq.w	#4,sp
	rts


Dsetdrv:
	move.w	d0,-(sp)
	move.w	#$e,-(sp)
	trap	#1                              ; Dsetdrv
	addq.w	#4,sp
	rts


Fclose:
	move.w	d0,-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.w	#4,sp
	rts


Malloc:
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.w	#6,sp
	movea.l	d0,a0
	rts


Dsetpath:
	move.l	a0,-(sp)
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.w	#6,sp
	rts


Fdelete:
	move.l	a0,-(sp)
	move.w	#$41,-(sp)
	trap	#1                              ; Fdelete
	addq.w	#6,sp
	rts


Fwrite:
	move.l	a0,-(sp)
	move.l	d1,-(sp)
	move.w	d0,-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	rts


Super:
	move.l	a0,-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.w	#6,sp
	rts


Cconis:
	move.w	#$b,-(sp)
	trap	#1                              ; Cconis
	addq.w	#2,sp
	rts


Dfree:
	move.w	d0,-(sp)
	move.l	a0,-(sp)
	move.w	#$36,-(sp)
	trap	#1                              ; Dfree
	addq.w	#8,sp
	rts


Dgetpath:
	move.w	d0,-(sp)
	move.l	a0,-(sp)
	move.w	#$47,-(sp)
	trap	#1                              ; Dgetpath
	addq.w	#8,sp
	rts


Fcreate:
	move.w	d0,-(sp)
	move.l	a0,-(sp)
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.w	#8,sp
	rts


Fopen:
	move.w	d0,-(sp)
	move.l	a0,-(sp)
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.w	#8,sp
	rts


Fseek:
	move.w	d2,-(sp)
	move.w	d1,-(sp)
	move.l	d0,-(sp)
	move.w	#$42,-(sp)
	trap	#1                              ; Fseek
	lea	$a(sp),sp
	rts


Mfree:
	move.l	a0,-(sp)
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.w	#6,sp
	rts


Drvmap:
	move.l	a2,-(sp)
	move.w	#$a,-(sp)
	trap	#13                             ; Drvmap
	addq.w	#2,sp
	movea.l	(sp)+,a2
	rts


Getbpb:
	move.l	a2,-(sp)
	move.w	d0,-(sp)
	move.w	#$7,-(sp)
	trap	#13                             ; Getbpb
	addq.w	#4,sp
	movea.l	d0,a0
	movea.l	(sp)+,a2
	rts


Rwabs:
	move.l	a2,-(sp)
	move.w	$8(sp),-(sp)
	move.w	d2,-(sp)
	move.w	d1,-(sp)
	move.l	a0,-(sp)
	move.w	d0,-(sp)
	move.w	#$4,-(sp)
	trap	#13                             ; Rwabs
	lea	$e(sp),sp
	movea.l	(sp)+,a2
	rts


Flopwr:
	move.l	a2,-(sp)
	move.w	$c(sp),-(sp)
	move.w	$c(sp),-(sp)
	move.w	$c(sp),-(sp)
	move.w	d2,-(sp)
	move.w	d1,-(sp)
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	move.w	#$9,-(sp)
	trap	#14                             ; Flopwr
	lea	$14(sp),sp
	movea.l	(sp)+,a2
	rts


Logbase:
	move.l	a2,-(sp)
	move.w	#$3,-(sp)
	trap	#14                             ; Logbase
	addq.w	#2,sp
	movea.l	d0,a0
	movea.l	(sp)+,a2
	rts


Gettime:
	move.l	a2,-(sp)
	move.w	#$17,-(sp)
	trap	#14                             ; Gettime
	addq.w	#2,sp
	movea.l	(sp)+,a2
	rts


Protobt:
	move.l	a2,-(sp)
	move.w	d2,-(sp)
	move.w	d1,-(sp)
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	move.w	#$12,-(sp)
	trap	#14                             ; Protobt
	lea	$e(sp),sp
	movea.l	(sp)+,a2
	rts


Random:
	move.l	a2,-(sp)
	move.w	#$11,-(sp)
	trap	#14                             ; Random
	addq.w	#2,sp
	movea.l	(sp)+,a2
	rts


Vsync:
	move.l	a2,-(sp)
	move.w	#$25,-(sp)
	trap	#14                             ; Vsync
	addq.w	#2,sp
	movea.l	(sp)+,a2
	rts


;----------------------------------------------------------------------
; AES bindings: the parameters go into aes_intin / aes_addrin, d0 is the
; function number for aes.
;----------------------------------------------------------------------
appl_init:
	moveq	#10,d0
	bra.w	aes


appl_exit:
	moveq	#19,d0
	bra.w	aes


evnt_timer:
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)
	moveq	#24,d0
	bra.w	aes


evnt_mesag:
	move.l	a0,aes_addrin
	moveq	#23,d0
	bra.w	aes


evnt_multi:
	move.l	a0,aes_addrin
	move.l	a1,-(sp)
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)+
	move.w	$8(sp),(a0)+
	move.w	$a(sp),(a0)+
	move.w	$c(sp),(a0)+
	move.w	$e(sp),(a0)+
	move.w	$10(sp),(a0)+
	move.w	$12(sp),(a0)+
	move.w	$14(sp),(a0)+
	move.w	$16(sp),(a0)+
	move.w	$18(sp),(a0)+
	move.w	$1a(sp),(a0)+
	move.w	$1c(sp),(a0)+
	move.w	$1e(sp),(a0)+
	move.w	$20(sp),(a0)
	moveq	#25,d0
	bsr.w	aes
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	movea.l	$1e(sp),a1
	move.w	(a0)+,(a1)
	movea.l	$22(sp),a1
	move.w	(a0)+,(a1)
	movea.l	$26(sp),a1
	move.w	(a0)+,(a1)
	movea.l	$2a(sp),a1
	move.w	(a0)+,(a1)
	movea.l	$2e(sp),a1
	move.w	(a0)+,(a1)
	rts


objc_draw:
	move.l	a0,aes_addrin
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)+
	move.w	$4(sp),(a0)+
	move.w	$6(sp),(a0)+
	move.w	$8(sp),(a0)+
	moveq	#42,d0
	bra.w	aes


objc_find:
	move.l	a0,aes_addrin
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)+
	move.w	$4(sp),(a0)
	moveq	#43,d0
	bra.w	aes


objc_offset:
	move.l	a1,-(sp)
	move.l	a0,aes_addrin
	move.w	d0,aes_intin
	moveq	#44,d0
	bsr.w	aes
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	movea.l	$4(sp),a1
	move.w	(a0)+,(a1)
	rts


objc_edit:
	move.l	a1,-(sp)
	move.l	a0,aes_addrin
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	(a1),(a0)+
	move.w	d2,(a0)+
	moveq	#46,d0
	bsr.w	aes
	movea.l	(sp)+,a1
	move.w	(a0),(a1)
	rts


objc_change:
	move.l	a0,aes_addrin
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)+
	move.w	$4(sp),(a0)+
	move.w	$6(sp),(a0)+
	move.w	$8(sp),(a0)+
	move.w	$a(sp),(a0)+
	move.w	$c(sp),(a0)
	moveq	#47,d0
	bra.w	aes


form_dial:
	move.l	a0,aes_addrin
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)+
	move.w	$4(sp),(a0)+
	move.w	$6(sp),(a0)+
	move.w	$8(sp),(a0)+
	move.w	$a(sp),(a0)+
	move.w	$c(sp),(a0)+
	move.w	$e(sp),(a0)
	moveq	#51,d0
	bra.w	aes


form_center:
	move.l	a1,-(sp)
	move.l	a0,aes_addrin
	moveq	#54,d0
	bsr.w	aes
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	movea.l	$4(sp),a1
	move.w	(a0)+,(a1)
	movea.l	$8(sp),a1
	move.w	(a0)+,(a1)
	movea.l	$c(sp),a1
	move.w	(a0)+,(a1)
	rts


form_alert:
	move.l	a0,aes_addrin
	move.w	d0,aes_intin
	moveq	#52,d0
	bra.w	aes


form_keybd:
	move.l	a1,-(sp)
	lea	aes_intin,a1
	move.w	d0,(a1)+
	move.w	d2,(a1)+
	move.w	d1,(a1)
	move.l	a0,aes_addrin
	moveq	#55,d0
	bsr.w	aes
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	movea.l	$4(sp),a1
	move.w	(a0)+,(a1)
	rts


form_button:
	move.l	a1,-(sp)
	lea	aes_intin,a1
	move.w	d0,(a1)+
	move.w	d1,(a1)
	move.l	a0,aes_addrin
	moveq	#56,d0
	bsr.w	aes
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	rts


rsrc_obfix:
	move.l	a0,aes_addrin
	move.w	d0,aes_intin
	moveq	#114,d0
	bra.w	aes


menu_register:
	move.w	d0,aes_intin
	move.l	a0,aes_addrin
	moveq	#35,d0
	bra.w	aes


graf_handle:
	move.l	a1,-(sp)
	move.l	a0,-(sp)
	moveq	#77,d0
	bsr.w	aes
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	movea.l	$4(sp),a1
	move.w	(a0)+,(a1)
	movea.l	$8(sp),a1
	move.w	(a0)+,(a1)
	rts


graf_slidebox:
	move.l	a0,aes_addrin
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)
	moveq	#76,d0
	bra.w	aes


graf_mouse:
	move.l	a0,aes_addrin
	move.w	d0,aes_intin
	moveq	#78,d0
	bra.w	aes


graf_mkstate:
	move.l	a1,-(sp)
	move.l	a0,-(sp)
	moveq	#79,d0
	bsr.w	aes
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	movea.l	(sp)+,a1
	move.w	(a0)+,(a1)
	movea.l	$4(sp),a1
	move.w	(a0)+,(a1)
	movea.l	$8(sp),a1
	move.w	(a0)+,(a1)
	rts


wind_create:
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)+
	move.w	$4(sp),(a0)+
	move.w	$6(sp),(a0)
	moveq	#100,d0
	bra.w	aes


wind_open:
	lea	aes_intin,a0
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)+
	move.w	$4(sp),(a0)+
	move.w	$6(sp),(a0)
	moveq	#101,d0
	bra.w	aes


wind_delete:
	move.w	d0,aes_intin
	moveq	#103,d0
	bra.w	aes


wind_close:
	move.w	d0,aes_intin
	moveq	#102,d0
	bra.w	aes


wind_update:
	move.w	d0,aes_intin
	moveq	#107,d0
	bra.w	aes


fsel_input:
	move.l	a0,aes_addrin
	move.l	a1,aes_addrin+4
	moveq	#90,d0
	bsr.w	aes
	movea.l	$4(sp),a1
	move.w	(a0),(a1)
	rts


fsel_exinput:
	move.l	a0,aes_addrin
	move.l	a1,aes_addrin+4
	move.l	$8(sp),aes_addrin+8
	moveq	#91,d0
	bsr.w	aes
	movea.l	$4(sp),a1
	move.w	(a0),(a1)
	rts


;----------------------------------------------------------------------
; AES call: d0 is the function; its contrl counts come from aes_ctrl_table.
;----------------------------------------------------------------------
aes:
	move.l	a2,-(sp)
	move.w	d0,aes_contrl
	add.w	d0,d0
	add.w	d0,d0
	lea	aes_ctrl_table-40(pc,d0.w),a0
	lea	aes_contrl+2,a1
	clr.w	d0
	move.b	(a0)+,d0
	move.w	d0,(a1)+
	move.b	(a0)+,d0
	move.w	d0,(a1)+
	move.b	(a0)+,d0
	move.w	d0,(a1)+
	move.b	(a0)+,d0
	move.w	d0,(a1)+
	move.w	#$c8,d0
	move.l	#aes_pb,d1
	trap	#2                              ; AES
	lea	aes_intout,a0
	move.w	(a0)+,d0
	movea.l	(sp)+,a2
	rts

aes_pb:
	dc.l	aes_contrl
	dc.l	aes_global
	dc.l	aes_intin
	dc.l	aes_intout
	dc.l	aes_addrin
	dc.l	aes_addrout

aes_ctrl_table:
; contrl[1..4] of each AES function from 10: int_in, int_out, addr_in, addr_out
	dc.b	0,1,0,0				; 10 appl_init
	dc.b	2,1,1,0				; 11 appl_read
	dc.b	2,1,1,0				; 12 appl_write
	dc.b	0,1,1,0				; 13 appl_find
	dc.b	2,1,1,0				; 14 appl_tplay
	dc.b	1,1,1,0				; 15 appl_trec
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,1,0,0				; 19 appl_exit
	dc.b	0,1,0,0				; 20 evnt_keybd
	dc.b	3,5,0,0				; 21 evnt_button
	dc.b	5,5,0,0				; 22 evnt_mouse
	dc.b	0,1,1,0				; 23 evnt_mesag
	dc.b	2,1,0,0				; 24 evnt_timer
	dc.b	16,7,1,0				; 25 evnt_multi
	dc.b	2,1,0,0				; 26 evnt_dclick
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	1,1,1,0				; 30 menu_bar
	dc.b	2,1,1,0				; 31 menu_icheck
	dc.b	2,1,1,0				; 32 menu_ienable
	dc.b	2,1,1,0				; 33 menu_tnormal
	dc.b	1,1,2,0				; 34 menu_text
	dc.b	1,1,1,0				; 35 menu_register
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	2,1,1,0				; 40 objc_add
	dc.b	1,1,1,0				; 41 objc_delete
	dc.b	6,1,1,0				; 42 objc_draw
	dc.b	4,1,1,0				; 43 objc_find
	dc.b	1,3,1,0				; 44 objc_offset
	dc.b	2,1,1,0				; 45 objc_order
	dc.b	4,2,1,0				; 46 objc_edit
	dc.b	8,1,1,0				; 47 objc_change
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	1,1,1,0				; 50 form_do
	dc.b	9,1,1,0				; 51 form_dial
	dc.b	1,1,1,0				; 52 form_alert
	dc.b	1,1,0,0				; 53 form_error
	dc.b	0,5,1,0				; 54 form_center
	dc.b	3,3,1,0				; 55 form_keybd
	dc.b	2,2,1,0				; 56 form_button
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	4,3,0,0				; 70 graf_rubberbox
	dc.b	8,3,0,0				; 71 graf_dragbox
	dc.b	6,1,0,0				; 72 graf_movebox
	dc.b	8,1,0,0				; 73 graf_growbox
	dc.b	8,1,0,0				; 74 graf_shrinkbox
	dc.b	4,1,1,0				; 75 graf_watchbox
	dc.b	3,1,1,0				; 76 graf_slidebox
	dc.b	0,5,0,0				; 77 graf_handle
	dc.b	1,1,1,0				; 78 graf_mouse
	dc.b	0,5,0,0				; 79 graf_mkstate
	dc.b	0,1,1,0				; 80 scrp_read
	dc.b	0,1,1,0				; 81 scrp_write
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,2,2,0				; 90 fsel_input
	dc.b	0,2,3,0				; 91 fsel_exinput
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	5,1,0,0				; 100 wind_create
	dc.b	5,1,0,0				; 101 wind_open
	dc.b	1,1,0,0				; 102 wind_close
	dc.b	1,1,0,0				; 103 wind_delete
	dc.b	2,5,0,0				; 104 wind_get
	dc.b	6,1,0,0				; 105 wind_set
	dc.b	2,1,0,0				; 106 wind_find
	dc.b	1,1,0,0				; 107 wind_update
	dc.b	6,5,0,0				; 108 wind_calc
	dc.b	0,0,0,0				; 109 wind_new
	dc.b	0,1,1,0				; 110 rsrc_load
	dc.b	0,1,0,0				; 111 rsrc_free
	dc.b	2,1,0,1				; 112 rsrc_gaddr
	dc.b	2,1,1,0				; 113 rsrc_saddr
	dc.b	1,1,1,0				; 114 rsrc_obfix
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,0,0,0
	dc.b	0,1,2,0				; 120 shel_read
	dc.b	3,1,2,0				; 121 shel_write
	dc.b	1,1,1,0				; 122 shel_get
	dc.b	1,1,1,0				; 123 shel_put
	dc.b	0,1,1,0				; 124 shel_find
	dc.b	0,1,3,0				; 125 shel_envrn

;----------------------------------------------------------------------
; Line-A bindings.
;----------------------------------------------------------------------
linea_init:
	move.l	a2,-(sp)
	dc.w	$a000                           ; Line-A Init
	move.l	a0,linea_vars
	suba.w	#$38e,a0
	move.l	a0,linea_base
	move.l	a1,linea_fonts
	move.l	a2,linea_routines
	movea.l	(sp)+,a2
	rts


bitblt:
	move.l	$4(a0),-(sp)
	move.w	$8(a0),-(sp)
	movem.l	a0/a2/a6,-(sp)
	movea.l	a0,a6
	dc.w	$a007                           ; Line-A BitBlt
	movem.l	(sp)+,a0/a2/a6
	move.w	(sp)+,$8(a0)
	move.l	(sp)+,$4(a0)
	rts


draw_line:
	movea.l	linea_vars,a0
	move.w	d0,$26(a0)
	move.w	d1,$28(a0)
	move.w	d2,$2a(a0)
	move.w	$4(sp),$2c(a0)
	move.w	#$ffff,$20(a0)
	move.l	a2,-(sp)
	dc.w	$a003                           ; Line-A Arbitrary line
	movea.l	(sp)+,a2
	rts


filled_rect:
	movea.l	linea_vars,a0
	move.w	d0,$26(a0)
	move.w	d1,$28(a0)
	move.w	d2,$2a(a0)
	move.w	$4(sp),$2c(a0)
	move.l	a2,-(sp)
	dc.w	$a005                           ; Line-A Filled rectangle
	movea.l	(sp)+,a2
	rts


hide_mouse:
	move.l	a2,-(sp)
	dc.w	$a00a                           ; Line-A Hide mouse
	movea.l	(sp)+,a2
	rts


horizontal_line:
	movea.l	linea_vars,a0
	move.w	d0,$26(a0)
	move.w	d1,$28(a0)
	move.w	d2,$2a(a0)
	move.l	a2,-(sp)
	dc.w	$a004                           ; Line-A Horizontal line
	movea.l	(sp)+,a2
	rts


show_mouse:
	movea.l	linea_vars,a0
	movea.l	$8(a0),a1
	move.w	d0,(a1)
	move.l	a2,-(sp)
	dc.w	$a009                           ; Line-A Show mouse
	movea.l	(sp)+,a2
	rts


text_string:
	move.w	d3,-(sp)
	move.l	a2,-(sp)
	move.w	d2,d3
	movea.l	a0,a2
	movea.l	linea_vars,a1
	move.w	d0,$4c(a1)
	move.w	d1,$4e(a1)
	bra.s	.loop_test

.loop_text_char
	move.w	d3,d1
	jsr	text_char(pc)
.loop_test
	move.b	(a2)+,d0
	bne.s	.loop_text_char
	movea.l	(sp)+,a2
	move.w	(sp)+,d3
	rts


text_char_at:
	movea.l	linea_vars,a0
	move.w	d0,d0
	bmi.s	.store_d2
	move.w	d0,$4c(a0)
	move.w	d1,$4e(a0)
.store_d2
	move.b	d2,d0
	clr.w	d1

text_char:
	movea.l	linea_vars,a0
	movea.l	text_font,a1
	sub.b	$25(a1),d0
	andi.w	#$ff,d0
	move.w	$42(a1),d2
	andi.w	#$8,d2
	beq.s	.proportional
	move.w	$34(a1),d2
	mulu.w	d2,d0
	move.w	d0,$48(a0)
	bra.s	.blit

.proportional
	movea.l	$48(a1),a1
	add.w	d0,d0
	move.w	$0(a1,d0.w),d2
	move.w	d2,$48(a0)
	neg.w	d2
	add.w	$2(a1,d0.w),d2
	move.w	d2,$50(a0)
.blit
	movem.l	d1/a0/a2,-(sp)
	dc.w	$a008                           ; Line-A TextBlt
	movem.l	(sp)+,d1/a0/a2
	add.w	d1,$4c(a0)
	rts


set_fill_pattern:
	movea.l	linea_vars,a1
	move.l	a0,$2e(a1)
	move.w	d0,$32(a1)
	move.w	d1,$34(a1)
	rts


set_clip:
	movea.l	linea_vars,a0
	move.w	d0,$38(a0)
	move.w	d1,$3a(a0)
	move.w	d2,$3c(a0)
	move.w	$4(sp),$3e(a0)
	move.w	$6(sp),$36(a0)
	rts


set_write_mode:
	movea.l	linea_vars,a0
	move.w	d0,$24(a0)
	rts


set_colour:
	movea.l	linea_vars,a0
	adda.w	#$18,a0
	move.w	#$3,d1
.next_plane
	clr.w	d2
	lsr.w	#1,d0
	roxl.w	#1,d2
	move.w	d2,(a0)+
	dbra	d1,.next_plane
	rts


set_line_mask:
	movea.l	linea_vars,a0
	move.w	d0,$22(a0)
	rts


set_text_font:
	lea	text_font,a1
	cmpa.w	#$0,a0
	beq.s	.font_set
	move.l	a0,(a1)
.font_set
	movea.l	(a1),a1
	movea.l	linea_vars,a0
	move.w	d0,$66(a0)
	move.w	d1,$5a(a0)
	move.w	d2,$68(a0)
	move.w	$42(a1),d2
	lsr.w	#3,d2
	dc.w	$c47c,$1                        ; and.w #$1,d2
	move.w	d2,$46(a0)
	beq.s	.proportional
	move.w	$34(a1),$50(a0)
.proportional
	move.w	$36(a1),$64(a0)
	move.w	$38(a1),$62(a0)
	move.w	$3a(a1),$60(a0)
	move.w	$3e(a1),$5c(a0)
	move.w	$40(a1),$5e(a0)
	move.l	$4c(a1),$54(a0)
	move.w	$50(a1),$58(a0)
	move.w	$52(a1),$52(a0)
	clr.w	$42(a0)
	clr.w	$44(a0)
	clr.w	$4a(a0)
	move.w	$4(sp),$6a(a0)
	move.w	$6(sp),$72(a0)
	move.l	#text_scratch,$6c(a0)
	move.w	#$8000,$40(a0)
	move.w	#$40,$70(a0)
	rts

