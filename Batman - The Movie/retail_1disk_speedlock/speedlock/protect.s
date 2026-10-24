; Batman The Movie (Ocean, 1989) - 1 disk retail reissue, SpeedLock protection
; Track 1 sectors 5-7, read to $1fd66 by the boot sector ($600 bytes, protect.bin as
; on the disk).
;
; $1fd66-$1ff67 is plain code: three decryption stages over the $300 bytes from
; $1ff68 (stage 2 needs a bus error for each word read at $ffff00-$fffffe), ended
; by an address error.  $1ff68-$20267 is encrypted on the disk and is shown
; decrypted, so this source assembles to protect.dec: the protection check times
; each 16 byte DMA burst of track 1 sector 1 with MFP timer A (the sector is
; mastered with a slow and a fast part), checks the sector 1 ID field with Read
; Track, then patches the boot sector code to read sectors 8-10 to $1ff68 and runs
; it.  Those sectors go through the same three stages again (layer3.s).
;
; The loader code is also the key: stage 2 uses $1fd68-$1ff67 as key words and
; mix_key reads its longs from the code at $1fe08 on.

; addresses outside this source
dma_buffer	equ	$20382          ; sector and track buffer, after the sectors
other_entry	equ	$20686          ; taken when check_long is not 0, never on this disk
saved_registers	equ	$5ff80          ; d0-a7 of TOS while the loader runs
saved_vectors	equ	$60000          ; copy of $8-$7ff while the vectors are cleared

; addresses inside instructions
mix_table	equ	$1fe08          ; mix_key+20
encrypted_end	equ	$20268          ; check_long+$300

	opt	o-
	org	$1fd66
loader_entry:
	bra.w	loader_start            ; over the data


; Loaded into d0-d7 by stages 1 and 3.
stage_regs:
	dc.l	$00000000               ; d0
	dc.l	$00000000               ; d1
	dc.l	$00000003               ; d2: rotate count of the key
	dc.l	$00000000               ; d3
	dc.l	$00000000               ; d4
	dc.l	$00000000               ; d5
	dc.l	$00000000               ; d6
	dc.l	$00000000               ; d7

; Loaded into d0-a6 to clear them.
zero_regs:
	dcb.b	64,$00                  ; d0-a6 (15 longs) and one spare long

; Bus error return PC: stage 2 uses its high word ($0001) as part of the key.
bus_return_pc:
	dc.l	bus_error_return        ; return PC stored by bus_error (already on the disk)

;----------------------------------------------------------------------
; Bus error handler: continue after the faulting instruction and keep the return PC.
; The fault is on the source read of the 6 byte move at bus_error_read; the 68000 stacks
; its address + 2, so + 4 is bus_error_return.
;----------------------------------------------------------------------
bus_error:
	lea	$a(sp),sp               ; drop the status word, access address, IR and SR
	addq.l	#4,(sp)                 ; stacked PC + 4: the instruction after the faulting one
	move.l	(sp)+,bus_return_pc     ; keep the return PC
	move.l	bus_return_pc,-(sp)
	rts                             ; continue there


;----------------------------------------------------------------------
; Address error handler: the end of the decryption.
;----------------------------------------------------------------------
address_error:
	lea	$10(sp),sp              ; drop the address error frame
	move.l	check_long,d0           ; first long of the decrypted area
	bne.w	other_entry
	bra.w	protection_check        ; 0 on both passes


;----------------------------------------------------------------------
; Mix a long of the loader code into the key d4.  mix_table is this code and what
; follows it, so a changed loader decrypts wrongly.
;----------------------------------------------------------------------
mix_key:
	add.l	d0,d6
	add.l	d1,d6
	add.l	d2,d6
	add.l	d3,d6
	add.l	d7,d6
	eor.l	d5,d6                   ; d6 = (d0+d1+d2+d3+d6+d7) eor d5
	andi.l	#$fe,d6                 ; even offset 0..$fe
	move.l	mix_table(pc,d6.w),d6   ; a long of the code from $1fe08
	eor.l	d6,d4                   ; into the key
	rts


;----------------------------------------------------------------------
; Start: save the TOS registers and vectors, take over bus error and address error.
;----------------------------------------------------------------------
loader_start:
	movem.l	d0-d7/a0-a7,saved_registers ; save the registers of TOS
	movem.l	zero_regs,d0-d7/a0-a6   ; clear d0-a6
	move.w	#$2700,sr               ; interrupts off
	suba.l	a4,a4                   ; a4 = 0
	lea	$8(a4),a0
	lea	saved_vectors,a1
save_vectors_loop:
	move.l	(a0),(a1)+              ; save $8-$7ff at $60000 and clear it
	clr.l	(a0)+
	cmpa.l	#$800,a0
	bne.s	save_vectors_loop
	move.l	#bus_error,$8(a4)       ; bus error -> bus_error
	move.l	#address_error,$c(a4)   ; address error -> address_error

;----------------------------------------------------------------------
; Stage 1: each long of a $f0 byte block is eored with a key made from all the other longs
; of the block, the low vectors and the system variables (all 0 now but two vectors).
;----------------------------------------------------------------------
stage1:
	lea	check_long,a0           ; $300 bytes from $1ff68 in blocks of $f0
	lea	stage_regs(pc),a1
	movem.l	(a1),d0-d7              ; d0-d7 = stage_regs (once)
stage1_block:
	moveq	#0,d0                   ; d0 = offset of the long to decrypt
stage1_long:
	move.w	d0,d1
	addq.b	#4,d1                   ; d1 = the long after it, wrapping in the block
	moveq	#0,d4
stage1_sum:
	move.l	$0(a0,d1.l),d5          ; each of the other longs of the block
	movea.l	d1,a2
	move.l	$8(a2),d6               ; low vectors $8-$107
	move.l	$108(a2),d7             ; system variables $108-$207
	eor.l	d5,d4
	eor.l	d6,d4
	add.l	d5,d4
	add.l	d7,d4
	ror.l	d2,d4                   ; ror by d2 = 3
	eor.l	d5,d4
	add.l	d6,d4
	addq.b	#4,d1
	cmp.b	d1,d0
	bne.s	stage1_sum
	bsr.w	mix_key                 ; mix a long of the code into d4
	eor.l	d4,$0(a0,d0.l)          ; decrypt the long
	addq.b	#4,d0
	cmpi.b	#$fc,d0
	bne.s	stage1_long
	lea	$f0(a0),a0
	cmpa.l	#encrypted_end,a0
	bcs.s	stage1_block
	lea	-$f0(a0),a0             ; a0 = the last block

;----------------------------------------------------------------------
; Stage 2: two passes over the $300 bytes in words, keyed by the loader code and by the
; return PC of a bus error.  Without the bus errors the key is wrong.
;----------------------------------------------------------------------
stage2:
	moveq	#1,d5                   ; two passes
stage2_pass:
	lea	check_long,a1           ; data words from $1ff68
	lea	-$200(a1),a2            ; key words from $1fd68 (the loader, $200 bytes)
	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d4
stage2_word:
	move.w	$0(a1,d0.l),d2
	move.w	$0(a2,d1.l),d3
	add.w	d3,d4                   ; sum of the key words
	eor.w	d3,d2
	move.w	d2,$0(a1,d0.l)
	andi.l	#$fe,d2                 ; d2 = 2..256 from the data word
	addq.l	#2,d2
	suba.l	d2,a4                   ; a4 = $ffff00..$fffffe
bus_error_read:
	move.w	(a4),bus_return_pc      ; no hardware there: BUS ERROR, bus_return_pc = bus_error_return
bus_error_return:
	adda.l	d2,a4                   ; a4 = 0
	move.w	bus_return_pc,d2        ; d2 = $0001, the high word of the return PC
	add.w	d0,d2                   ; + offset
	eor.w	d2,$0(a1,d0.l)          ; decrypt the word
	addq.w	#2,d0
	addq.w	#2,d1
	andi.w	#$1ff,d1                ; key wraps after $200 bytes
	cmpi.w	#$300,d0
	bne.s	stage2_word
	moveq	#0,d0
stage2_swap:
	move.w	$0(a1,d0.l),d2
	eor.w	d4,d2                   ; eor the sum, swap the bytes, eor again
	rol.w	#8,d2
	eor.w	d4,d2
	move.w	d2,$0(a1,d0.l)
	addq.w	#2,d0
	cmpi.w	#$300,d0
	bne.s	stage2_swap
	dbra	d5,stage2_pass          ; next pass

;----------------------------------------------------------------------
; Stage 3: stage 1 again, from the last block back to the first.
;----------------------------------------------------------------------
stage3:
	lea	stage_regs(pc),a1
	movem.l	(a1),d0-d7              ; d0-d7 = stage_regs
stage3_block:
	move.l	#$f8,d0                 ; last long of the block first
stage3_long:
	move.w	d0,d1
	addq.b	#4,d1
	moveq	#0,d4
stage3_sum:
	move.l	$0(a0,d1.l),d5
	movea.l	d1,a2
	move.l	$8(a2),d6
	move.l	$108(a2),d7
	eor.l	d5,d4
	eor.l	d6,d4
	add.l	d7,d4                   ; d7 before d5 (stage 1 adds d5 first)
	add.l	d5,d4
	ror.l	d2,d4
	eor.l	d5,d4
	add.l	d6,d4
	addq.b	#4,d1
	cmp.b	d1,d0
	bne.s	stage3_sum
	bsr.w	mix_key
	eor.l	d4,$0(a0,d0.l)
	subq.b	#4,d0                   ; backwards
	cmpi.b	#$fc,d0
	bne.s	stage3_long
	lea	-$f0(a0),a0             ; block before
	cmpa.l	#check_long,a0
	bcc.s	stage3_block

;----------------------------------------------------------------------
; End: an address error takes address_error, which goes on to protection_check.
;----------------------------------------------------------------------
odd_access:
	move.l	$1.l,$1.l               ; long access at an odd address: ADDRESS ERROR

; Encrypted on the disk up to $20267 and shown decrypted.
check_long:
	dc.l	$00000000               ; decrypts to 0: address_error goes on to protection_check
	dc.l	$00000000               ; spare

;----------------------------------------------------------------------
; Protection check: TOS vectors, registers and stack back, timer A taken over, then time
; track 1 sector 1.
;----------------------------------------------------------------------
protection_check:
	move.w	#$2700,sr               ; interrupts off
	lea	$8.l,a0                 ; a0 = $8
	lea	saved_vectors,a1
restore_vectors_loop:
	move.w	(a1),(a0)+              ; put $8-$7ff back from saved_vectors
	clr.w	(a1)+
	cmpa.l	#$800,a0
	bne.s	restore_vectors_loop
	movem.l	saved_registers,d0-d7/a0-a7 ; TOS registers back, sp too
	move.w	#$2500,sr               ; MFP interrupts (level 6) allowed
	move.l	#check_passed,$18.w     ; CHK vector -> check_passed
	lea	$ffff8600.w,a3          ; a3 = $ffff8600 DMA
	lea	$ffff8800.w,a4          ; a4 = $ffff8800 PSG
	lea	$fffffa01.w,a6          ; a6 = $fffffa01 MFP, registers at odd offsets
	lea	measurements(pc),a0
	lea	measure_ptr(pc),a1
	move.l	a0,(a1)                 ; measure_ptr = measurements
	lea	timer_a_irq(pc),a0
	lea	saved_timer_a(pc),a1
	lea	$134.w,a2               ; MFP timer A vector
	move.l	(a2),(a1)               ; save the TOS timer A vector
	move.l	a0,(a2)                 ; timer A -> timer_a_irq
	ori.b	#$20,$6(a6)             ; IERA: timer A enabled
	ori.b	#$20,$12(a6)            ; IMRA: timer A unmasked
	lea	saved_timer_ctrl(pc),a0
	move.b	$18(a6),(a0)+           ; save TACR
	sf	$18(a6)                 ; timer A stopped
	st	$1e(a6)                 ; TADR = 255
	move.b	$1a(a6),(a0)+           ; save TBCR
	sf	$1a(a6)                 ; timer B stopped
	move.b	$1c(a6),(a0)            ; save TCDCR
	sf	$1c(a6)                 ; timers C and D stopped
	lea	measurements(pc),a0
	lea	measure_ptr(pc),a1
	move.l	a0,(a1)                 ; measure_ptr = measurements
	bsr.w	measure_sector          ; time the 16 byte bursts of track 1 sector 1

;----------------------------------------------------------------------
; Average the measurements of blocks 0-30 in four groups.
;----------------------------------------------------------------------
average_blocks:
	lea	measurements(pc),a0
	lea	$e.w,a3                 ; a3 = $e, used by check_failed
	lea	block_averages(pc),a2
	moveq	#30,d2                  ; 31 measurements
	moveq	#6,d3                   ; first group: 7 (the first counted twice)
	move.w	(a0),d4                 ; d4 = the first measurement
	moveq	#3,d5                   ; / 8
	moveq	#0,d0
average_loop:
	move.w	(a0)+,d0
	add.w	d0,d4
	dbra	d3,average_next         ; group not done
	lsr.w	d5,d4                   ; group average
	move.w	d4,(a2)+
	moveq	#7,d3                   ; next groups: 8
	moveq	#0,d4
average_next:
	dbra	d2,average_loop

;----------------------------------------------------------------------
; A sector read at an even rate gives d0 = $60, inside the CHK bounds 0..$80.  The disk has a
; slow quarter and a fast quarter, which take d0 out of the bounds: CHK goes to check_passed.
;----------------------------------------------------------------------
check_timing:
	lea	block_averages(pc),a2
	moveq	#96,d0                  ; d0 = $60 + 2*w1 + w3 - w0 - 2*w2
	add.w	$2(a2),d0
	add.w	$2(a2),d0
	add.w	$6(a2),d0
	sub.w	(a2),d0
	sub.w	$4(a2),d0
	sub.w	$4(a2),d0
	move.w	a4,d1                   ; d1 = $8800
	lsr.w	#4,d1
	andi.w	#$ff,d1                 ; d1 = $80
	chk.w	d1,d0                   ; d0 < 0 or > $80: CHK exception -> check_passed

;----------------------------------------------------------------------
; Failed: endless ILLEGAL at $e.
;----------------------------------------------------------------------
check_failed:
	lea	$42e.w,a0               ; phystop
	movea.l	(a0),a0
	lea	-$4(a0),sp              ; stack under the top of RAM
	move.l	a3,$2(a3)               ; illegal instruction vector ($10) = $e
	move.w	illegal_word(pc),(a3)   ; ILLEGAL at $e
	illegal                         ; ILLEGAL -> $e -> ILLEGAL ... for ever


; Never run (the ILLEGAL above comes first); its immediate word is copied to $e.
	dc.w	$303c
illegal_word:
	dc.w	$4afc                   ; ILLEGAL, copied to $e by check_failed

;----------------------------------------------------------------------
; Passed: timer A back to TOS, then Read Track on track 1: the ID field of sector 1 must be
; within the first bytes of the track.
;----------------------------------------------------------------------
check_passed:
	move.w	(sp)+,d0                ; drop the CHK frame: SR
	move.l	(sp)+,d1                ; and PC
	lea	check_failed(pc),a1     ; a1 = check_failed
	eori.b	#$20,$6(a6)             ; IERA: timer A off
	eori.b	#$20,$12(a6)            ; IMRA: timer A masked
	lea	saved_timer_ctrl(pc),a0 ; restore TACR, TBCR, TCDCR
	move.b	(a0)+,$18(a6)
	move.b	(a0)+,$1a(a6)
	move.b	(a0),$1c(a6)
	lea	$fffffa01.w,a6          ; MFP GPIP
	lea	$ffff8600.w,a3
	lea	dma_buffer(pc),a0       ; DMA address = dma_buffer
	move.l	a0,d7
	move.b	d7,$d(a3)
	lsr.w	#8,d7
	move.b	d7,$b(a3)
	swap	d7
	move.b	d7,$9(a3)
	move.w	#$190,$6(a3)            ; DMA mode $190 then $90: clear the DMA, sector count register
	move.w	#$90,$6(a3)
	bsr.w	fdc_delay
	move.w	#$e,$4(a3)              ; sector count 14
	bsr.w	fdc_delay
	move.w	#$80,$6(a3)             ; DMA mode: FDC command register
	bsr.w	fdc_delay
	move.w	#$e0,$4(a3)             ; READ TRACK (track 1)
	bsr.w	wait_fdc                ; wait for the FDC
	lea	$7a0e(a3),a3            ; a3 = $e
	moveq	#0,d0
	lea	$18(a0),a0              ; from byte $18 of the track
	moveq	#127,d1                 ; 128 bytes
find_id_loop:
	move.b	(a0)+,d0
	addq.b	#2,d0                   ; $fe: ID address mark
	beq.s	id_mark_found
	dbra	d1,find_id_loop
	jmp	(a1)                    ; not found: check_failed

id_mark_found:
	cmpi.b	#$1,$2(a0)              ; sector 1?
	bne.s	find_id_loop            ; no: search on

;----------------------------------------------------------------------
; Patch the boot sector code to read sectors 8-10 to $1ff68 and jump to $1fd66, and run it
; from read_loader (bootsect.s).
;----------------------------------------------------------------------
patch_boot:
	movea.l	$20.w,a0                ; a0 = read_loader in the boot sector (privilege violation vector)
	move.w	#$3,$a4(a0)             ; boot+$124: sector count 3
	move.w	#$8,$84(a0)             ; boot+$104: first sector 8
	move.b	#$5c,$a6(a0)            ; boot+$126: addq.b #6,d6 (unchanged)
	move.b	#$6,$ec(a0)             ; boot+$16c: lea $600(a6),a0 (unchanged)
	move.l	#$ff68,$46(a0)          ; boot+$c6: DMA address $1ff68
	move.l	#$4ef90001,$102(a0)     ; boot+$182: jmp $1fd66.l in place of jmp (a6)
	move.l	#$fd669544,$106(a0)     ; (continued)
	jmp	(a0)                    ; read sectors 8-10 to $1ff68 and run loader_entry again


;----------------------------------------------------------------------
; Read sector 1 and time each 16 byte DMA burst with timer A: 32 words at measurements,
; timer A ticks x2 for each burst after the first.
;----------------------------------------------------------------------
measure_sector:
	moveq	#14,d2                  ; d2 = 14 (not used)
	moveq	#1,d3                   ; d3 = 1: sector, count and timer A mode
	move.w	#$80,d4                 ; d4 = $80: FDC command register, READ SECTOR
	move.w	#$84,$6(a3)             ; DMA mode: FDC sector register
	bsr.w	fdc_delay
	move.w	d3,$4(a3)               ; sector 1
	bsr.w	fdc_delay
	move.w	#$190,$6(a3)            ; DMA mode $190 then $90: clear the DMA, sector count register
	move.w	#$90,$6(a3)
	bsr.w	fdc_delay
	move.w	d3,$4(a3)               ; sector count 1
	bsr.w	fdc_delay
	lea	dma_buffer(pc),a5       ; DMA address = dma_buffer
	move.l	a5,d0
	move.b	d0,$d(a3)
	lsr.w	#8,d0
	move.b	d0,$b(a3)
	swap	d0
	move.b	d0,$9(a3)
	move.w	d4,$6(a3)               ; DMA mode: FDC command register
	bsr.w	fdc_delay
	move.w	d4,$4(a3)               ; READ SECTOR
	bsr.w	fdc_delay
	move.b	$d(a3),d1               ; d1 = DMA address low byte
	moveq	#31,d7                  ; 32 bursts
	sf	$18(a6)                 ; timer A stopped
	st	$1e(a6)                 ; TADR = 255
	bsr.s	wait_dma                ; the first 16 bytes
	move.b	d3,$18(a6)              ; timer A on: delay mode, /4 (614.4 kHz)
measure_loop:
	movea.l	measure_ptr(pc),a0      ; a0 = measure_ptr
	move.w	#$ffff,(a0)             ; the high byte counts the timer A interrupts
	bsr.s	wait_dma                ; the next 16 bytes
	sf	$18(a6)                 ; timer A stopped
	move.b	$1e(a6),d0              ; the count where it stopped
	st	$1e(a6)                 ; reload 255
	move.b	d3,$18(a6)              ; timer A on
	move.b	d0,$1(a0)               ; low byte = the count
	move.w	(a0),d0
	neg.w	d0                      ; ticks used
	lsl.w	d3,d0                   ; x2
	move.w	d0,(a0)
	addq.l	#2,measure_ptr          ; next measurement
	dbra	d7,measure_loop
measure_exit:
	rts


;----------------------------------------------------------------------
; Wait for the DMA address low byte to change (the next 16 byte burst), with a timeout.
;----------------------------------------------------------------------
wait_dma:
	moveq	#2,d0                   ; timeout $20000
	swap	d0
wait_dma_loop:
	sub.l	d3,d0
	beq.s	measure_exit            ; timeout: return through the rts of measure_sector
	cmp.b	$d(a3),d1               ; DMA address low byte changed?
	beq.s	wait_dma_loop
	move.b	$d(a3),d1               ; remember it
	rts


;----------------------------------------------------------------------
; Delay between FDC register accesses.
;----------------------------------------------------------------------
fdc_delay:
	moveq	#40,d0
	dbra	d0,*
	rts


;----------------------------------------------------------------------
; Wait for the FDC interrupt (GPIP bit 5 low).
;----------------------------------------------------------------------
wait_fdc:
	nop
	nop
	btst	#$5,(a6)                ; GPIP bit 5: FDC interrupt
	bne.s	wait_fdc
	rts


;----------------------------------------------------------------------
; Timer A interrupt every 255 ticks: count down the high byte of the current measurement.
;----------------------------------------------------------------------
timer_a_irq:
	move.l	a0,-(sp)
	lea	$fffffa0f.w,a0          ; ISRA
	bclr	#$5,(a0)                ; end of interrupt
	lea	measure_ptr(pc),a0
	movea.l	(a0),a0
	subq.b	#1,(a0)                 ; high byte of the current measurement - 1
	movea.l	(sp)+,a0
	rte


; Variables.
saved_timer_ctrl:
	dc.b	$00                     ; TOS timer A control
	dc.b	$00                     ; TOS timer B control
	dc.b	$00                     ; TOS timer C/D control
	dc.b	$00                     ; spare
measure_ptr:
	dc.l	$00000000               ; the measurement being made
saved_timer_a:
	dc.l	$00000000               ; TOS timer A vector
spare_long:
	dcb.b	4,$00
block_averages:
	dc.w	$0000                   ; blocks 0-6 (block 0 counted twice) / 8
	dc.w	$0000                   ; blocks 7-14 / 8
	dc.w	$0000                   ; blocks 15-22 / 8
	dc.w	$0000                   ; blocks 23-30 / 8
spare_words:
	dcb.b	32,$00
measurements:
	dcb.b	64,$00                  ; 32 words: timer A ticks x2 per 16 byte burst
sector_rest:
	dcb.b	228,$00                 ; not encrypted

	end
