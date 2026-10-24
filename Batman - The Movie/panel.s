; Batman The Movie (Ocean, 1989) - panel / score routines (resident), all versions
; Module panel: panel.bin, loaded at $6b800, in scenes front, level1, level2, level3, level4, level5.
; Size: RETAIL_2DISK 6268 bytes, RETAIL_1DISK 6145 bytes, BUDGET_1DISK 6176 bytes.
;
; Resident panel module.  Entry points $6b800-$6b870 are a jump table the
; level engines call; the panel bitmap lives in panel_gfx ($75f00) and is copied to
; the visible panel at $7df00 by panel_copy.  Status flags:
;   panel_flags  bit0 time up / paused, bit1 game over, bit2 life lost
;   game_flags   bit0 music on, bit5 abort level, bit6 level complete, bit7 cheat
;
; Labels are named for what they do or hold; unused_ marks code that nothing
; calls.  A label still ending in its address (tab_ table, dat_ data) is one
; whose use is not known yet.  "; from:" lists the routines or modules that
; refer to a label (documentation only).

	include	"config.s"			; CONFIG: which version to assemble

	opt	o-
	org	$6b800


;----------------------------------------------------------------------
; Panel tick, called every frame by the level VBL/timer handlers:
; counts down the timer and depletes energy.
;----------------------------------------------------------------------
panel_tick:	; from: level1, level2_gfx
	movem.l	d0-d7/a0-a2,-(sp)
	bsr.w	tick_body
	movem.l	(sp)+,d0-d7/a0-a2
	rts


;----------------------------------------------------------------------
; Set the level timer, d0 = BCD seconds.
;----------------------------------------------------------------------
panel_set_time:	; from: level1, level2_gfx
	movem.l	d0-d7/a0-a2,-(sp)
	bsr.w	set_time_body
	movem.l	(sp)+,d0-d7/a0-a2
	rts


panel_reset_score:	; from: frontend
	movem.l	d0-d7/a0-a2,-(sp)
	bsr.w	reset_score_body
	movem.l	(sp)+,d0-d7/a0-a2
	rts


;----------------------------------------------------------------------
; Add d0 (BCD) to the score; an extra life every 10000 points.
;----------------------------------------------------------------------
panel_add_score:	; from: level1, level2_gfx
	movem.l	d0-d7/a0-a2,-(sp)
	bsr.w	add_score_body
	movem.l	(sp)+,d0-d7/a0-a2
	rts


;----------------------------------------------------------------------
; Reset to 3 lives and redraw the life icons.
;----------------------------------------------------------------------
panel_reset_lives:	; from: level1, frontend
	movem.l	d0-d7/a0-a2,-(sp)
	bsr.w	reset_lives_body
	movem.l	(sp)+,d0-d7/a0-a2
	rts


panel_add_life:	; from: level1
	movem.l	d0-d7/a0-a2,-(sp)
	bsr.w	panel_extra_life
	movem.l	(sp)+,d0-d7/a0-a2
	rts


;----------------------------------------------------------------------
; Initialise the energy bar.
;----------------------------------------------------------------------
panel_init_energy:	; from: level1, level2_gfx
	movem.l	d0-d7/a0-a2,-(sp)
	bsr.w	init_energy_body
	movem.l	(sp)+,d0-d7/a0-a2
	rts


;----------------------------------------------------------------------
; Lose a life (sets panel_flags bit1 when none are left).
;----------------------------------------------------------------------
panel_lose_life:	; from: level1
	movem.l	d0-d7/a0-a2,-(sp)
	bsr.w	panel_remove_life
	movem.l	(sp)+,d0-d7/a0-a2
	rts


;----------------------------------------------------------------------
; Lose d0 units of energy; a life is lost when the bar is empty.
;----------------------------------------------------------------------
panel_lose_energy:	; from: level1, level2_gfx
	bra.w	lose_energy_body

panel_flags:	; from: level1, frontend, level2_gfx, reset_lives_body, panel_deplete_energy, panel_remove_life, ...
	dc.b	$00
game_flags:	; from: level1, frontend, level2_gfx, panel_remove_life
	dc.b	$00
panel_lives:	; from: panel_extra_life, reset_lives_body, panel_remove_life
	dc.w	$0000
panel_next_life_score:	; from: frontend, add_score_body
	dc.w	$0000,$0000
panel_score:	; from: level1, frontend, reset_score_body, add_score_body
	dc.w	$0000,$0000
panel_tick_count:	; from: add_score_body, set_time_body, tick_body
	dc.w	$0000
panel_time:	; from: level2_gfx, set_time_body, tick_body
	dc.w	$0000
panel_time_bcd:	; from: level2_gfx, set_time_body, tick_body, draw_time
	dc.w	$0300
score_add_value:	; from: add_score_body, tick_body
	dc.w	$0000,$0000
score_drawn:	; from: reset_score_body, add_score_body
	dc.w	$ffff,$ffff
energy_steps_left:	; from: level1, init_energy_body, panel_deplete_energy
	dc.w	$0000
energy_pending:	; from: init_energy_body, panel_deplete_energy, panel_remove_life
	dc.w	$0000
energy_screen_ptr:	; from: init_energy_body, panel_deplete_energy
	dc.w	$0000,$0000
energy_step_ptr:	; from: init_energy_body, panel_deplete_energy
	dc.w	$0000,$0000

; Energy bar bitmap: 41 rows of 32 bytes, copied to the panel at $761c0 (and $7e1c0) by panel_init_energy.
energy_bar_gfx:	; from: init_energy_body
	incbin	"data/pn_ebar.bin"		; $520 bytes of data

; Energy bar depletion: one 32 byte row per step, written over the bar from the top by panel_deplete_energy.
energy_bar_steps:
	incbin	"data/pn_estep.bin"		; $504 bytes of data

; Small digit font for the score: 10 digits of 7 rows x 4 bytes (one plane each).
small_digits:
	incbin	"data/pn_sdig.bin"		; $118 bytes of data

; Blank small digit (leading zeros).
small_digit_blank:
	incbin	"data/pn_sdigb.bin"		; $1c bytes of data

; Time digits: 11 rows x 4 bytes each, offsets in time_digit_offsets (10 digits, colon, blank).
time_digits:
	incbin	"data/pn_tdig.bin"		; $270 bytes of data

; Life icon bitmap drawn on the panel by panel_draw_life_icon.
life_icon_gfx:	; from: panel_extra_life, reset_lives_body
	incbin	"data/pn_life.bin"		; $104 bytes of data

; Blank life icon, drawn over a lost life.
life_icon_blank:	; from: reset_lives_body, panel_remove_life
	incbin	"data/pn_lifeb.bin"		; $10e bytes of data

;----------------------------------------------------------------------
; Copy the panel bitmap from panel_gfx ($75f00) to the screen panel at $7df00.
;----------------------------------------------------------------------
panel_copy:	; from: level1, level2_gfx
	movem.l	d0/a0-a1,-(sp)
	move.l	#$780,d0
	lea	$75f00,a0                       ; panel_gfx +$0
	lea	$7df00,a1
panel_copy_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,panel_copy_loop
	movem.l	(sp)+,d0/a0-a1
	rts


panel_extra_life:	; from: panel_add_life, add_score_body
	lea	life_icon_gfx,a0
	move.w	panel_lives,d0
	addi.w	#$1,panel_lives
	cmpi.w	#$3,d0
	blt.w	panel_draw_life_icon
	rts


reset_lives_body:	; from: panel_reset_lives
	move.w	#$2,panel_lives
	clr.b	panel_flags
	moveq	#0,d0
	lea	life_icon_gfx,a0
	bsr.w	panel_draw_life_icon
	moveq	#1,d0
	lea	life_icon_gfx,a0
	bsr.w	panel_draw_life_icon
	moveq	#2,d0
	lea	life_icon_blank,a0
	bsr.w	panel_draw_life_icon
	rts


panel_draw_life_icon:	; from: panel_extra_life, reset_lives_body, panel_remove_life
	asl.w	#4,d0
	movea.l	a0,a2
	suba.l	#$34,a2
	lea	$765a8,a1                       ; panel_gfx +$6a8
	adda.w	d0,a1
	movea.l	a1,a3
	adda.l	#$8000,a3                       ; level1_map +$c00
	move.w	#$c,d0
life_icon_row_loop:
	move.b	(a2),d7
	not.b	d7
	and.b	d7,(a1)
	and.b	d7,$2(a1)
	and.b	d7,$4(a1)
	and.b	d7,$6(a1)
	move.b	(a0),d7
	or.b	d7,(a1)
	move.b	(a1),(a3)
	move.b	$34(a0),d7
	or.b	d7,$2(a1)
	move.b	$2(a1),$2(a3)
	move.b	$68(a0),d7
	or.b	d7,$4(a1)
	move.b	$4(a1),$4(a3)
	move.b	$9c(a0),d7
	or.b	d7,$6(a1)
	move.b	$6(a1),$6(a3)
	move.b	$1(a2),d7
	not.b	d7
	and.b	d7,$1(a1)
	and.b	d7,$3(a1)
	and.b	d7,$5(a1)
	and.b	d7,$7(a1)
	move.b	$1(a0),d7
	or.b	d7,$1(a1)
	move.b	$1(a1),$1(a3)
	move.b	$35(a0),d7
	or.b	d7,$3(a1)
	move.b	$3(a1),$3(a3)
	move.b	$69(a0),d7
	or.b	d7,$5(a1)
	move.b	$5(a1),$5(a3)
	move.b	$9d(a0),d7
	or.b	d7,$7(a1)
	move.b	$7(a1),$7(a3)
	move.b	$2(a2),d7
	not.b	d7
	and.b	d7,$8(a1)
	and.b	d7,$a(a1)
	and.b	d7,$c(a1)
	and.b	d7,$e(a1)
	move.b	$2(a0),d7
	or.b	d7,$8(a1)
	move.b	$8(a1),$8(a3)
	move.b	$36(a0),d7
	or.b	d7,$a(a1)
	move.b	$a(a1),$a(a3)
	move.b	$6a(a0),d7
	or.b	d7,$c(a1)
	move.b	$c(a1),$c(a3)
	move.b	$9e(a0),d7
	or.b	d7,$e(a1)
	move.b	$e(a1),$e(a3)
	move.b	$3(a2),d7
	not.b	d7
	and.b	d7,$9(a1)
	and.b	d7,$b(a1)
	and.b	d7,$d(a1)
	and.b	d7,$f(a1)
	move.b	$3(a0),d7
	or.b	d7,$9(a1)
	move.b	$9(a1),$9(a3)
	move.b	$37(a0),d7
	or.b	d7,$b(a1)
	move.b	$b(a1),$b(a3)
	move.b	$6b(a0),d7
	or.b	d7,$d(a1)
	move.b	$d(a1),$d(a3)
	move.b	$9f(a0),d7
	or.b	d7,$f(a1)
	move.b	$f(a1),$f(a3)
	lea	$4(a0),a0
	lea	$4(a2),a2
	lea	$a0(a1),a1
	lea	$a0(a3),a3
	dbra	d0,life_icon_row_loop
	rts


init_energy_body:	; from: panel_init_energy
	move.w	#$28,d0
	move.w	d0,energy_steps_left
	clr.w	energy_pending
	lea	energy_bar_gfx,a0
	lea	$761c0,a1                       ; panel_gfx +$2c0
	lea	$7e1c0,a2
	move.l	a1,energy_screen_ptr
energy_bar_copy_loop:
	move.l	(a0),(a1)
	move.l	(a0)+,(a2)
	move.l	(a0),$4(a1)
	move.l	(a0)+,$4(a2)
	move.l	(a0),$8(a1)
	move.l	(a0)+,$8(a2)
	move.l	(a0),$c(a1)
	move.l	(a0)+,$c(a2)
	move.l	(a0),$10(a1)
	move.l	(a0)+,$10(a2)
	move.l	(a0),$14(a1)
	move.l	(a0)+,$14(a2)
	move.l	(a0),$18(a1)
	move.l	(a0)+,$18(a2)
	move.l	(a0),$1c(a1)
	move.l	(a0)+,$1c(a2)
	lea	$a0(a1),a1
	lea	$a0(a2),a2
	dbra	d0,energy_bar_copy_loop
	move.l	#energy_bar_steps,energy_step_ptr
energy_exit:	; from: panel_deplete_energy
	rts

lose_energy_body:	; from: panel_lose_energy
	tst.w	energy_steps_left
	bne.s	energy_add_pending
	clr.w	energy_pending
	rts

energy_add_pending:
	add.w	d0,energy_pending
	rts


panel_deplete_energy:	; from: tick_body
	move.w	energy_pending,d0
	bpl.w	energy_step
	clr.w	energy_pending
	moveq	#0,d0
energy_step:
	beq.s	energy_exit
	subi.w	#$1,energy_pending
	movea.l	energy_step_ptr,a0
	movea.l	energy_screen_ptr,a1
	movea.l	a1,a2
	adda.l	#$8000,a2                       ; level1_map +$c00
	move.l	(a0),(a1)
	move.l	(a0)+,(a2)
	move.l	(a0),$4(a1)
	move.l	(a0)+,$4(a2)
	move.l	(a0),$8(a1)
	move.l	(a0)+,$8(a2)
	move.l	(a0),$c(a1)
	move.l	(a0)+,$c(a2)
	move.l	(a0),$10(a1)
	move.l	(a0)+,$10(a2)
	move.l	(a0),$14(a1)
	move.l	(a0)+,$14(a2)
	move.l	(a0),$18(a1)
	move.l	(a0)+,$18(a2)
	move.l	(a0),$1c(a1)
	move.l	(a0)+,$1c(a2)
	lea	$a0(a1),a1
	move.l	a0,energy_step_ptr
	move.l	a1,energy_screen_ptr
	subi.w	#$1,energy_steps_left
	bne.w	energy_exit
	bra.w	panel_remove_life

no_lives_left:	; from: panel_remove_life
	bset	#$1,panel_flags
	rts


panel_remove_life:	; from: panel_lose_life, panel_deplete_energy
	clr.w	energy_pending
	tst.w	panel_lives
	beq.s	no_lives_left
	bset	#$2,panel_flags
	btst	#$7,game_flags
	bne.s	remove_life_exit
	subq.w	#1,panel_lives
	move.w	panel_lives,d0
	cmpi.w	#$2,d0
	bgt.w	remove_life_exit
	lea	life_icon_blank,a0
	bra.w	panel_draw_life_icon

remove_life_exit:
	rts


reset_score_body:	; from: panel_reset_score
	clr.l	panel_score
	move.l	#$ffffffff,score_drawn
	moveq	#0,d0
	move.b	panel_next_life_score+1,d0
	move.w	#$80e,d1
	bsr.w	panel_draw_digits
	move.b	panel_next_life_score+2,d0
	move.w	#$a0e,d1
	bsr.w	panel_draw_digits
	move.b	panel_next_life_score+3,d0
	move.w	#$c0e,d1
	bsr.w	panel_draw_digits
	moveq	#0,d0

;----------------------------------------------------------------------
; Add score_add_value (BCD) to panel_score, redraw the digits that changed, extra life
; and new threshold when panel_next_life_score is passed.
;----------------------------------------------------------------------
add_score_body:	; from: panel_add_score
	move.l	d0,score_add_value
	lea	score_drawn,a0
	lea	panel_tick_count,a1
	andi.l	#$ff,d0
	movem.l	d0-d1,-(sp)
	move.b	panel_score+1,d0
	andi.b	#$f0,d0
	move.w	#$0,ccr
	abcd	-(a0),-(a1)
	abcd	-(a0),-(a1)
	abcd	-(a0),-(a1)
	move.b	panel_score+1,d1
	andi.b	#$f0,d1
	cmp.b	d0,d1
	beq.s	score_digit_low
	bsr.w	panel_extra_life
score_digit_low:
	movem.l	(sp)+,d0-d1
	move.b	panel_score+3,d0
	cmp.b	score_drawn+3,d0
	beq.s	score_digit_mid
	move.b	d0,score_drawn+3
	move.w	#$c1e,d1
	bsr.w	panel_draw_digits
score_digit_mid:
	move.b	panel_score+2,d0
	cmp.b	score_drawn+2,d0
	beq.s	score_digit_high
	move.b	d0,score_drawn+2
	move.w	#$a1e,d1
	bsr.w	panel_draw_digits
score_digit_high:
	move.b	panel_score+1,d0
	cmp.b	score_drawn+1,d0
	beq.s	score_check_life
	move.b	d0,score_drawn+1
	move.w	#$81e,d1
	bsr.w	panel_draw_digits
score_check_life:
	move.l	panel_next_life_score,d0
	cmp.l	panel_score,d0
	bgt.w	add_score_exit
	moveq	#0,d0
	move.b	panel_score+3,d0
	cmp.b	panel_next_life_score+3,d0
	beq.s	life_digit_mid
	move.w	#$c0e,d1
	bsr.w	panel_draw_digits
life_digit_mid:
	move.b	panel_score+2,d0
	cmp.b	panel_next_life_score+2,d0
	beq.s	life_digit_high
	move.w	#$a0e,d1
	bsr.w	panel_draw_digits
life_digit_high:
	move.b	panel_score+1,d0
	cmp.b	panel_next_life_score+1,d0
	beq.s	life_score_store
	move.w	#$80e,d1
	bsr.w	panel_draw_digits
life_score_store:
	move.l	panel_score,panel_next_life_score
add_score_exit:
	rts


set_time_body:	; from: panel_set_time
	move.w	d0,panel_time_bcd
	move.w	#$32,panel_tick_count
	bsr.w	draw_time
	clr.w	panel_time
	clr.b	panel_flags
	rts


;----------------------------------------------------------------------
; Panel tick: energy depletion, then every 50 ticks one second off panel_time_bcd (MM:SS),
; colon blink, panel_flags bit0 when the time is up; panel_time $9999 stops the clock.
;----------------------------------------------------------------------
tick_body:	; from: panel_tick
	bsr.w	panel_deplete_energy
	cmpi.w	#$9999,panel_time
	beq.w	tick_exit
	subi.w	#$1,panel_tick_count
	bpl.w	time_colon
	move.w	#$32,panel_tick_count
	tst.w	panel_time_bcd
	beq.w	time_up
	lea	panel_time_bcd,a0
	lea	score_add_value,a1
	move.w	#$10,ccr
	sbcd	-(a0),-(a1)
	sbcd	-(a0),-(a1)
	move.b	panel_time_bcd+1,d0
	andi.b	#$f0,d0
	cmpi.b	#$90,d0
	bne.s	time_redraw
	move.b	#$59,panel_time_bcd+1
time_redraw:
	bsr.w	draw_time
time_colon:
	move.w	#$a,d0
	cmpi.w	#$19,panel_tick_count
	beq.s	time_colon_draw
	cmpi.w	#$32,panel_tick_count
	bne.s	tick_exit
	move.w	#$b,d0
time_colon_draw:
	move.w	#$1d19,d1
	bsr.w	panel_draw_digit
tick_exit:
	rts

time_up:
	bset	#$0,panel_flags
	bra.w	time_colon


draw_time:	; from: set_time_body, tick_body
	moveq	#0,d0
	move.b	panel_time_bcd+1,d0
	move.w	#$1f19,d1
	bsr.w	panel_draw_digit
	move.b	panel_time_bcd+1,d0
	lsr.b	#4,d0
	move.w	#$1e19,d1
	bsr.w	panel_draw_digit
	move.b	panel_time_bcd,d0
	move.w	#$1c19,d1
	bsr.w	panel_draw_digit
	move.b	panel_time_bcd,d0
	lsr.b	#4,d0
	move.w	#$1b19,d1
	bra.w	panel_draw_digit


panel_draw_digits:	; from: reset_score_body, add_score_body
	bsr.w	draw_small_digit
	lsr.b	#4,d0
	subi.w	#$100,d1

;----------------------------------------------------------------------
; Draw one small digit d0 (low nibble) at panel column/row d1 (high byte column, low byte row).
;----------------------------------------------------------------------
draw_small_digit:	; from: panel_draw_digits
	movem.l	d0-d2/d7,-(sp)
	moveq	#0,d2
	move.b	d1,d2
	andi.w	#$ff,d2
	mulu.w	#$a0,d2
	lsr.w	#8,d1
	move.w	d1,d7
	andi.w	#$1,d7
	andi.w	#$fffe,d1
	asl.w	#2,d1
	add.w	d7,d1
	add.w	d1,d2
	addi.l	#$75f00,d2                      ; panel_gfx +$0
	movea.l	d2,a0
	andi.b	#$f,d0
	bne.s	small_digit_gfx
	movea.l	#small_digit_blank,a1
	bra.w	small_digit_rows

small_digit_gfx:
	mulu.w	#$1c,d0
	addi.l	#small_digits,d0
	movea.l	d0,a1
small_digit_rows:
	movea.l	a0,a2
	adda.l	#$8000,a2                       ; level1_map +$c00
	moveq	#6,d2
small_digit_loop:
	move.b	(a1),(a0)
	move.b	(a1)+,(a2)
	move.b	(a1),$2(a0)
	move.b	(a1)+,$2(a2)
	move.b	(a1),$4(a0)
	move.b	(a1)+,$4(a2)
	move.b	(a1),$6(a0)
	move.b	(a1)+,$6(a2)
	lea	$a0(a2),a2
	lea	$a0(a0),a0
	dbra	d2,small_digit_loop
	movem.l	(sp)+,d0-d2/d7
	rts


;----------------------------------------------------------------------
; Draw one time digit d0 at panel column/row d1 (to both panel copies).
;----------------------------------------------------------------------
panel_draw_digit:	; from: tick_body, draw_time
	andi.l	#$ffff,d0
	movem.l	d0-d2,-(sp)
	moveq	#0,d2
	move.b	d1,d2
	andi.w	#$ff,d2
	mulu.w	#$a0,d2
	lsr.w	#8,d1
	move.w	d1,d7
	andi.w	#$1,d7
	andi.w	#$fffe,d1
	asl.w	#2,d1
	add.w	d7,d1
	add.w	d1,d2
	addi.l	#$75f00,d2                      ; panel_gfx +$0
	movea.l	d2,a0
	andi.w	#$f,d0
	add.w	d0,d0
	lea	time_digit_offsets,a2
	move.w	$0(a2,d0.w),d0
	addi.l	#time_digits,d0
	movea.l	d0,a1
	movea.l	a0,a2
	adda.l	#$8000,a2                       ; level1_map +$c00
	moveq	#10,d2
time_digit_loop:
	move.b	(a1),(a0)
	move.b	(a1)+,(a2)
	move.b	(a1),$2(a0)
	move.b	(a1)+,$2(a2)
	move.b	(a1),$4(a0)
	move.b	(a1)+,$4(a2)
	move.b	(a1),$6(a0)
	move.b	(a1)+,$6(a2)
	lea	$a0(a2),a2
	lea	$a0(a0),a0
	dbra	d2,time_digit_loop
	movem.l	(sp)+,d0-d2
	rts

time_digit_offsets:	; from: panel_draw_digit
	dc.w	$01b8,$002c,$0058,$0084,$00b0,$00dc,$0108,$0134
	ifeq	CONFIG-RETAIL_2DISK
	dc.w	$0160,$018c,$0000,$01e4,$2079,$0006,$bc96,$2279
	endc
	ifne	CONFIG-RETAIL_2DISK
	dc.w	$0160,$018c,$0000,$01e4,$0000,$01e4,$0000,$0000
	endc

; High score table as a credits script for the front end (command 3 of run_credits).
hiscore_text:
	dc.b	'         HI SCORES'
	dc.w	$0d0d
	dc.b	$0d
	dc.b	'     1ST  AJS  125000'
	dc.w	$0d0d
	dc.b	'     2ND  MIK  100000'
	dc.b	$0d,$0d
	dc.b	'     3RD  JOB  075000'
	dc.w	$0d0d
	dc.b	'     4TH  BIL  050000'
	dc.b	$0d,$0d
hiscore_last_name:	; from: frontend
	dc.b	'     5TH  JON  025000'
	dc.w	$0d0d

; Blank line the front end writes a new name into, then command 4 (return).
hiscore_entry_line:	; from: frontend
	dcb.b	21,$20
	dc.b	$0d,$0d,$04,$00,$00,$00,$00

; The five high score values, highest first (hiscore_entry scans them from the last).
hiscore_values:	; from: frontend
	dc.w	$0012,$5000,$0010,$0000,$0007,$5000,$0005,$0000
hiscore_last_value:	; from: frontend
	ifeq	CONFIG-RETAIL_2DISK
	dc.w	$0002,$5000,$0002,$5000,$0000,$0000,$bc8a,$7000
	dc.w	$1039,$0006,$bc79,$323c,$080e,$6100,$0208,$1039
	dc.w	$0006,$bc7a,$323c,$0a0e,$6100,$01fa,$1039,$0006
	dc.w	$bc7b,$323c,$0c0e,$6100,$01ec,$7000,$23c0,$0006
	dc.w	$bc86,$41f9,$0006,$bc8a,$43f9,$0006
	dc.b	$bc
	dcb.b	123,$00
	endc
	ifeq	CONFIG-RETAIL_1DISK
	dc.w	$0002,$5000,$0002
	dc.b	$50
	dcb.b	70,$00
	endc
	ifeq	CONFIG-BUDGET_1DISK
	dc.w	$0002,$5000,$0002
	dc.b	$50
	dcb.b	70,$00
file_padding:
	dcb.b	31,$00
	endc

	end
