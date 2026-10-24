; Batman The Movie (Ocean, 1989) - level 3, all versions
; Module level3: level3.bin, loaded at $20000, in scenes level3.
; Size: RETAIL_2DISK 54652 bytes, RETAIL_1DISK 54635 bytes, BUDGET_1DISK 54666 bytes.
;
; Batcave puzzle.  The module starts with the packed Batcave picture
; ($20000) and the cursor graphics; the code is entered at $28000.  Three of the
; eight cosmetic items are the answer (pick_answer); the player moves a cursor
; over the items and selects three.  show_matches prints how many were right;
; after the tries are used up a life is lost, a full match completes the level
; (level_complete -> loader vector 4).
;
; Labels are named for what they do or hold; unused_ marks code that nothing
; calls.  A label still ending in its address (tab_ table, dat_ data) is one
; whose use is not known yet.  "; from:" lists the routines or modules that
; refer to a label (documentation only).

	include	"config.s"			; CONFIG: which version to assemble

; symbols in other modules
panel_tick	equ	$6b800		; panel.s
panel_set_time	equ	$6b80e		; panel.s
panel_add_score	equ	$6b82a		; panel.s
panel_init_energy	equ	$6b854		; panel.s
panel_lose_energy	equ	$6b870		; panel.s
panel_flags	equ	$6b874		; panel.s
game_flags	equ	$6b875		; panel.s
panel_time	equ	$6b882		; panel.s
panel_time_bcd	equ	$6b884		; panel.s
panel_copy	equ	$6c874		; panel.s
snd_reset	equ	$6d400		; sound.s
snd_stop	equ	$6d404		; sound.s
snd_stop_music	equ	$6d408		; sound.s
snd_play_tune	equ	$6d410		; sound.s
snd_play_sfx	equ	$6d414		; sound.s
snd_tick	equ	$6d418		; sound.s

	opt	o-
	org	$20000


; Packed Batcave picture (unpack_picture -> $63800), followed by the sprites below.
batcave_picture:	; from: level_start
	incbin	"data/l3_pic.bin"		; $36b0 bytes of data

; Sprites 1-8 of sprite_table: the eight cosmetic items, 6 words x 30 lines, $2d0 bytes each.
item_sprites:
	incbin	"data/l3_items.bin"		; $1680 bytes of data

; Sprite 0: the highlight frame drawn round the item under the cursor, 6 words x 90 lines;
; draw_cursor_masked uses it from 6 bytes in.
frame_gfx:
	incbin	"data/l3_frame.bin"		; $870 bytes of data
frame_mask:
	incbin	"data/l3_framem.bin"		; $21c bytes of data

; Sprite 11: swept over the items by reveal_answer after a wrong analysis.
fail_sprite:
	incbin	"data/l3_fails.bin"		; $2d0 bytes of data

; Sprite 13: swept over the items by reveal_answer after the right analysis.
success_sprite:
	incbin	"data/l3_wins.bin"		; $2d0 bytes of data

; Sprite 12: 192 x 104 picture shown after a wrong analysis.
fail_picture:
	incbin	"data/l3_fail.bin"		; $1380 bytes of data

; Sprite 14: 192 x 42 picture shown after the right analysis.
success_picture:
	incbin	"data/l3_win.bin"		; $f24 bytes of data

;----------------------------------------------------------------------
; Level entry: stack at $63800, unscramble the font, hardware init,
; unpack the Batcave picture to $63800.
;----------------------------------------------------------------------
level_start:
	lea	$63800,sp
	jsr	snd_reset
	move.w	#$13f,d7
	lea	font,a0
unscramble_font:
	move.b	$4(a0),d0
	and.b	$1(a0),d0
	not.b	d0
	and.b	$2(a0),d0
	and.b	$3(a0),d0
	eor.b	d0,$4(a0)
	move.b	$4(a0),d0
	and.b	$3(a0),d0
	not.b	d0
	and.b	$1(a0),d0
	and.b	$2(a0),d0
	eor.b	d0,$1(a0)
	eor.b	d0,$3(a0)
	adda.l	#$5,a0
	dbra	d7,unscramble_font
	bsr.w	hw_init
	lea	batcave_picture,a0
	lea	$63800,a1
	lea	palette,a2
	bsr.w	unpack_picture
	bra.w	level_loop

	dc.w	$303c,$02cc,$1e10,$e30f,$10c7,$51c8,$fff8,$6000
	dc.w	$21b0
cheat_skip:	; from: level_restart, play_sound, is_selected
	dc.w	$0000
game_over_exit:	; from: level_restart
	move.w	#$64,d0
	bsr.w	wait_frames
	bsr.w	fade_out
	jmp	$200                            ; loader section 0 (jmp $1000)

level_complete_exit:	; from: level_restart
	move.w	#$9999,panel_time
	move.l	#$70000,screen_front
	move.l	#$78000,screen_back
	bsr.w	clear_back_dissolve
	bsr.w	fade_out
	jsr	snd_stop_music
	jmp	$210                            ; loader section 4 (jmp $1010)

level_loop:
	jsr	snd_stop_music

;----------------------------------------------------------------------
; Start (or restart after a wrong answer) the puzzle.
;----------------------------------------------------------------------
level_restart:	; from: is_selected
	btst	#$1,panel_flags
	bne.w	game_over_exit
	tst.w	cheat_skip
	bne.w	level_complete_exit
	jsr	snd_stop_music
	bsr.w	init_puzzle
	bsr.w	fade_in
	bsr.w	draw_batcave
	clr.w	panel_time
	moveq	#0,d0
	bsr.w	play_sound
	clr.w	spare_counter
	jsr	panel_copy

;----------------------------------------------------------------------
; Main loop: frame_update (cursor, input, selection) and key handling until time is up.
;----------------------------------------------------------------------
main_loop:
	moveq	#0,d0
	bsr.w	wait_frames
	bsr.w	frame_update
	bsr.w	cursor_update
	jsr	handle_keys
	btst	#$0,panel_flags
	beq.s	main_loop
	bra.w	lose_game


;----------------------------------------------------------------------
; Hardware init: black palette, screen $70000, VBL and MFP vectors, IKBD, timer C at 200 Hz.
;----------------------------------------------------------------------
hw_init:	; from: level_start
	moveq	#0,d0
	move.w	#$2700,sr
	move.b	d0,$fffa07                      ; MFP IERA
	move.b	d0,$fffa09                      ; MFP IERB
	lea	$ff8240,a0                      ; palette 0
	lea	current_palette,a1
	moveq	#15,d1
clear_palette_loop:
	move.w	d0,(a0)+
	clr.w	(a1)+
	dbra	d1,clear_palette_loop
	move.l	#$70000,d0
	move.l	d0,screen_front
	ror.l	#8,d0
	move.b	d0,$ff8203                      ; video base mid
	ror.l	#8,d0
	move.b	d0,$ff8201                      ; video base high
	lea	vbl_handler,a0
	move.l	a0,$70                          ; VBL vector
	lea	mfp_vectors,a0
	lea	$100.w,a1                       ; MFP vector 0 (Centronics busy)
	moveq	#15,d1
copy_vectors_loop:
	move.l	(a0)+,(a1)+
	dbra	d1,copy_vectors_loop
	move.b	#$e,$ff8800                     ; PSG register select
	moveq	#7,d1
	or.b	$ff8800,d1                      ; PSG register select
	move.b	d1,$ff8802                      ; PSG write data
	lea	$fffa01,a0                      ; MFP GPIP
	movep.l	d0,$0(a0)
	movep.l	d0,$8(a0)
	movep.l	d0,$10(a0)
	move.b	#$48,$fffa17                    ; MFP VR
	move.b	#$3,$fffc04                     ; MIDI ACIA control
	move.b	#$9c,$fffc04                    ; MIDI ACIA control
	move.b	#$3,$fffc00                     ; keyboard ACIA control
	move.b	#$96,$fffc00                    ; keyboard ACIA control
	lea	ikbd_init_cmds(pc),a0
	moveq	#3,d0
	bsr.w	ikbd_send
	move.b	#$1,$fffa13                     ; MFP IMRA
	move.b	#$1,$fffa07                     ; MFP IERA
	move.b	#$40,$fffa09                    ; MFP IERB
	move.b	#$60,$fffa15                    ; MFP IMRB
	move.b	#$60,$fffa09                    ; MFP IERB
	move.b	#$f6,$fffa23                    ; MFP TCDR
	move.b	#$70,$fffa1d                    ; MFP TCDCR
	move.w	#$2300,sr
	move.b	#$0,$fffa1b                     ; MFP TBCR
	bclr	#$0,$fffa0b                     ; MFP IPRA
	bclr	#$0,$fffa0f                     ; MFP ISRA
	bset	#$0,$fffa13                     ; MFP IMRA
	bset	#$0,$fffa07                     ; MFP IERA
	bsr.w	ikbd_joystick_mode
	bra.w	clear_screens

mfp_vectors:	; from: hw_init
	dc.l	mfp_busy
	dc.l	mfp_dcd
	dc.l	mfp_cts
	dc.l	mfp_blitter
	dc.l	mfp_timer_d
	dc.l	timerc_handler
	dc.l	acia_handler
	dc.l	mfp_fdc
	dc.l	timerb_handler
	dc.l	mfp_tx_error
	dc.l	mfp_tx_empty
	dc.l	mfp_rx_error
	dc.l	mfp_rx_full
	dc.l	mfp_timer_a
	dc.l	mfp_ring
	dc.l	mfp_mono
ikbd_init_cmds:	; from: hw_init
	dc.w	$8010,$121a
palette:	; from: level_start, vbl_handler
	dc.w	$0000,$0001,$0444,$0777,$0030,$0400,$0600,$0666
	dc.w	$0555,$0333,$0000,$0630,$0751,$0770,$0774,$0222
	dc.w	$0098
current_palette:	; from: hw_init, fade_in, fade_out
	dcb.b	34,$00
target_palette:	; from: fade_in
	dc.w	$0000,$0030,$0777,$0004,$0511,$0222,$0431,$0333
	dc.w	$0444,$0555,$0520,$0630,$0740,$0750,$0760
debug_printed:	; from: unused_print_text
	dc.w	$0777

mfp_busy:	; from: mfp_vectors
	bclr	#$0,$fffa11                     ; MFP ISRB
	rte


mfp_dcd:	; from: mfp_vectors
	bclr	#$1,$fffa11                     ; MFP ISRB
	rte


mfp_cts:	; from: mfp_vectors
	bclr	#$2,$fffa11                     ; MFP ISRB
	rte


mfp_blitter:	; from: mfp_vectors
	bclr	#$3,$fffa11                     ; MFP ISRB
	rte


mfp_timer_d:	; from: mfp_vectors
	bclr	#$4,$fffa11                     ; MFP ISRB
	rte


timerc_handler:	; from: mfp_vectors
	bclr	#$5,$fffa11                     ; MFP ISRB
	move.w	#$2300,sr
	movem.l	d0-d7/a0-a6,-(sp)
	jsr	snd_tick
	bsr.w	keyboard_decode
	movem.l	(sp)+,d0-d7/a0-a6
	rte

acia_abort:	; from: midi_flush
	movem.l	(sp)+,d0-d1/a0

acia_handler:	; from: mfp_vectors
	movem.l	d0-d1/a0,-(sp)
acia_loop:
	bsr.s	midi_flush
	bsr.s	keyboard_acia_read
	btst	#$4,$fffa01                     ; MFP GPIP
	beq.s	acia_loop
	movem.l	(sp)+,d0-d1/a0
	bclr	#$6,$fffa11                     ; MFP ISRB
	rte


midi_flush:	; from: acia_handler
	move.b	$fffc04,d0                      ; MIDI ACIA control
	bpl.s	midi_flush_exit
	move.w	sr,d1
	btst	#$7,d1
	beq.s	acia_abort
	btst	#$0,d0
	beq.s	midi_flush_exit
	tst.b	$fffc06                         ; MIDI ACIA data
midi_flush_exit:
	rts


keyboard_acia_read:	; from: acia_handler
	move.b	$fffc00,d0                      ; keyboard ACIA control
	bpl.s	kbd_read_exit
	btst	#$0,d0
	beq.s	kbd_overrun
	lea	kbd_ring(pc),a0
	move.w	kbd_head(pc),d1
	move.b	$fffc02,$0(a0,d1.w)             ; keyboard ACIA data
	addq.w	#1,d1
	andi.w	#$1f,d1
	move.w	d1,kbd_head
kbd_overrun:
	andi.b	#$30,d0
	beq.s	kbd_read_exit
	clr.l	kbd_head
kbd_read_exit:
	rts

kbd_ring:	; from: keyboard_acia_read, keyboard_decode
	dcb.b	32,$00
kbd_head:	; from: keyboard_acia_read, keyboard_decode
	dc.w	$0000
kbd_tail:	; from: keyboard_decode
	dc.w	$0000

mfp_fdc:	; from: mfp_vectors
	bclr	#$7,$fffa11                     ; MFP ISRB
	rte


;----------------------------------------------------------------------
; Timer B: toggle frame_flag, stir random_pool with the registers, next palette split.
;----------------------------------------------------------------------
timerb_handler:	; from: mfp_vectors
	not.w	frame_flag
	add.w	d0,random_pool
	add.w	d3,random_pool+2
	add.w	d4,random_pool+4
	add.w	d6,random_pool+6
	add.w	d1,random_pool+8
	add.w	d2,random_pool+10
	add.w	d0,random_pool+12
	movem.l	d0-d3/a0,-(sp)
	move.w	sp,d1
	move.b	#$0,$fffa1b                     ; MFP TBCR
	movea.l	split_ptr,a0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8240                   ; palette 0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8250
	move.w	(a0)+,d0
	beq.s	timerb_exit
	move.b	d0,$fffa21                      ; MFP TBDR
	move.b	#$8,$fffa1b                     ; MFP TBCR
	move.l	a0,split_ptr
timerb_exit:
	movem.l	(sp)+,d0-d3/a0
	bclr	#$0,$fffa0f                     ; MFP ISRA
	rte


mfp_tx_error:	; from: mfp_vectors
	bclr	#$1,$fffa0f                     ; MFP ISRA
	rte


mfp_tx_empty:	; from: mfp_vectors
	bclr	#$2,$fffa0f                     ; MFP ISRA
	rte


mfp_rx_error:	; from: mfp_vectors
	bclr	#$3,$fffa0f                     ; MFP ISRA
	rte


mfp_rx_full:	; from: mfp_vectors
	bclr	#$4,$fffa0f                     ; MFP ISRA
	rte


mfp_timer_a:	; from: mfp_vectors
	bclr	#$5,$fffa0f                     ; MFP ISRA
	rte


mfp_ring:	; from: mfp_vectors
	bclr	#$6,$fffa0f                     ; MFP ISRA
	rte


mfp_mono:	; from: mfp_vectors
	bclr	#$7,$fffa0f                     ; MFP ISRA
	rte

split_ptr:	; from: timerb_handler, vbl_handler
	dc.w	$0000,$0000

;----------------------------------------------------------------------
; VBL: restart the palette split, panel tick, count frames.
;----------------------------------------------------------------------
vbl_handler:	; from: hw_init
	movem.l	d0-d7/a0-a6,-(sp)
	move.b	#$0,$fffa1b                     ; MFP TBCR
	lea	palette(pc),a0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8240                   ; palette 0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8250
	move.w	(a0)+,d0
	move.l	a0,split_ptr
	move.b	d0,$fffa21                      ; MFP TBDR
	jsr	panel_tick
	move.b	#$8,$fffa1b                     ; MFP TBCR
	addq.w	#1,vbl_count
	movem.l	(sp)+,d0-d7/a0-a6
	rte


ikbd_send:	; from: hw_init, ikbd_joystick_mode
	btst	#$1,$fffc00                     ; keyboard ACIA control
	beq.s	ikbd_send
	move.b	(a0)+,$fffc02                   ; keyboard ACIA data
	dbra	d0,ikbd_send
	rts


keyboard_decode:	; from: timerc_handler
	lea	kbd_ring,a0
	movem.w	kbd_head,d0-d1
	lea	key_queue,a1
	movem.w	key_queue_head,d2-d3
	lea	key_bitmap,a2
next_packet:
	cmp.w	d0,d1
	beq.s	packets_done
	move.b	$0(a0,d1.w),d4
	cmpi.b	#$f6,d4
	bcc.w	packet_header
	addq.b	#1,d1
	andi.w	#$1f,d1
	bclr	#$7,d4
	beq.s	key_down
	ext.w	d4
	move.b	scancode_ascii(pc,d4.w),d4
	move.w	d4,d5
	lsr.w	#3,d5
	bclr	d4,$0(a2,d5.w)
	bra.s	packet_done

key_down:
	ext.w	d4
	move.b	scancode_ascii(pc,d4.w),d4
	move.w	d4,d5
	lsr.w	#3,d5
	bset	d4,$0(a2,d5.w)
	tst.b	d4
	beq.s	packet_done
	move.b	d4,$0(a1,d2.w)
	addq.b	#1,d2
	andi.w	#$1f,d2
packet_done:
	bra.s	next_packet

packets_done:
	move.w	d1,kbd_tail
	move.w	d2,key_queue_head
	rts

scancode_ascii:	; from: keyboard_decode
	dc.w	$001b
	dc.b	'1234567890-='
	dc.w	$0809
	dc.b	'QWERTYUIOP[]'
	dc.w	$0d00
	dc.b	'ASDFGHJKL;''`',0
	dc.b	'#ZXCVBNM,./',0
	dc.b	$00,$00,$20,$00,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8a,$00,$00
	dc.b	$80,$8c,$00,$2d,$8e,$00,$8f,$2b,$00,$8d,$00,$80,$7f,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$8b
	dc.b	'()/*7894561230.'
	dc.w	$0d00,$0000,$0000,$0000,$0000,$0000,$0000
packet_lengths:	; from: keyboard_decode
	dc.w	$0806,$0303,$0303,$0703,$0202
packet_header:
	move.b	d0,d5
	sub.b	d1,d5
	andi.w	#$1f,d5
	subi.b	#$f6,d4
	andi.w	#$ff,d4
	cmp.b	packet_lengths(pc,d4.w),d5
	bcs.w	packets_done
	addi.b	#$f6,d4
	cmpi.b	#$f7,d4
	bcs.s	skip_packet
	cmpi.b	#$f8,d4
	bcs.s	skip_packet
	cmpi.b	#$fc,d4
	bcs.w	mouse_packet
	cmpi.b	#$fd,d4
	bcs.s	skip_packet
	cmpi.b	#$fe,d4
	bcs.s	joy_both_packet
	beq.s	joy0_packet
	bra.s	joy1_packet

skip_packet:
	subi.b	#$f6,d4
	add.b	packet_lengths(pc,d4.w),d1
	andi.w	#$1f,d1
	bra.w	packet_done

joy0_packet:
	addq.w	#1,d1
	andi.w	#$1f,d1
	move.b	$0(a0,d1.w),joy0_dirs
	bclr	#$7,joy0_dirs
	sne	joy0_fire
	addq.w	#1,d1
	andi.w	#$1f,d1
	bra.w	packet_done

joy1_packet:
	addq.w	#1,d1
	andi.w	#$1f,d1
	move.b	$0(a0,d1.w),joy1_dirs
	bclr	#$7,joy1_dirs
	sne	joy1_fire
	addq.w	#1,d1
	andi.w	#$1f,d1
	bra.w	packet_done

joy_both_packet:
	addq.w	#1,d1
	andi.w	#$1f,d1
	move.b	$0(a0,d1.w),joy0_dirs
	bclr	#$7,joy0_dirs
	sne	joy0_fire
	addq.w	#1,d1
	andi.w	#$1f,d1
	addq.w	#1,d1
	andi.w	#$1f,d1
	move.b	$0(a0,d1.w),joy1_dirs
	bclr	#$7,joy1_dirs
	sne	joy1_fire
	addq.w	#1,d1
	andi.w	#$1f,d1
	bra.w	packet_done

mouse_packet:
	asr.b	#1,d4
	scs	mouse_right
	asr.b	#1,d4
	scs	mouse_left
	addq.w	#1,d1
	andi.w	#$1f,d1
	move.b	$0(a0,d1.w),d4
	ext.w	d4
	add.w	d4,mouse_x
	addq.w	#1,d1
	andi.w	#$1f,d1
	move.b	$0(a0,d1.w),d4
	ext.w	d4
	add.w	d4,mouse_y
	addq.w	#1,d1
	andi.w	#$1f,d1
	move.w	mouse_max_x,d4
	move.w	mouse_x,d5
	bpl.s	mouse_x_min
	clr.w	d5
mouse_x_min:
	cmp.w	d5,d4
	bcc.s	mouse_x_store
	move.w	d4,d5
mouse_x_store:
	move.w	d5,mouse_x
	move.w	mouse_max_y,d4
	move.w	mouse_y,d5
	bpl.s	mouse_y_min
	clr.w	d5
mouse_y_min:
	cmp.w	d5,d4
	bcc.s	mouse_y_store
	move.w	d4,d5
mouse_y_store:
	move.w	d5,mouse_y
	bra.w	packet_done

key_queue:	; from: keyboard_decode, get_key, random
	dcb.b	32,$00
key_queue_head:	; from: keyboard_decode, get_key
	dc.w	$0000
key_queue_tail:	; from: get_key
	dc.w	$0000
key_bitmap:	; from: keyboard_decode
	dcb.b	34,$00
joy0_fire:	; from: keyboard_decode
	dc.b	$00
joy0_dirs:	; from: keyboard_decode
	dc.b	$00,$00,$00
joy1_fire:	; from: keyboard_decode, random, cursor_update, unused_debug_input
	dc.b	$00
joy1_dirs:	; from: keyboard_decode
	dc.b	$00,$00,$00,$00,$00
mouse_max_x:	; from: keyboard_decode
	dc.w	$0000
mouse_max_y:	; from: keyboard_decode
	dc.w	$0000
mouse_left:	; from: keyboard_decode
	dc.b	$00
mouse_right:	; from: keyboard_decode
	dc.b	$00
mouse_x:	; from: keyboard_decode
	dc.w	$0000
mouse_y:	; from: keyboard_decode
	dc.w	$0000,$0000,$0000,$0000
unused_flush_keys:
	move.l	d0,-(sp)
	bsr.s	get_key
flush_keys_loop:
	bne.s	flush_keys_loop
	move.l	(sp)+,d0
	rts


get_key:	; from: keyboard_decode, handle_keys
	movem.l	d1-d2/a0,-(sp)
	lea	key_queue,a0
	moveq	#0,d0
	movem.w	key_queue_head,d1-d2
	cmp.w	d1,d2
	beq.s	get_key_exit
	move.b	$0(a0,d2.w),d0
	addq.w	#1,d2
	andi.w	#$1f,d2
	move.w	d2,key_queue_tail
get_key_exit:
	tst.b	d0
	movem.l	(sp)+,d1-d2/a0
	rts


ikbd_joystick_mode:	; from: hw_init
	movem.l	d0/a0,-(sp)
	lea	ikbd_joy_cmds(pc),a0
	moveq	#1,d0
	bsr.w	ikbd_send
	movem.l	(sp)+,d0/a0
	rts

ikbd_joy_cmds:	; from: ikbd_joystick_mode
	dc.w	$1214
vbl_count:	; from: vbl_handler, flip_screens, fade_in, fade_out
	dc.w	$0000
flip_wait:	; from: flip_screens
	dc.w	$0000
screen_front:	; from: level_start, hw_init, flip_screens, dissolve_in, init_puzzle, is_selected, ...
	dc.w	$0007,$0000
screen_back:	; from: level_start, print_text, init_puzzle, is_selected, draw_batcave
	dc.w	$0007,$8000

;----------------------------------------------------------------------
; Wait flip_wait frames, swap screen_front / screen_back and set the video base.
;----------------------------------------------------------------------
flip_screens:	; from: cursor_update, copy_front_to_back
	movem.l	d0-d1,-(sp)
	move.w	flip_wait,d0
flip_wait_loop:
	cmp.w	vbl_count,d0
	bhi.s	flip_wait_loop
	movem.l	screen_front,d0-d1
	exg	d0,d1
	movem.l	d0-d1,screen_front
	ror.l	#8,d0
	move.b	d0,$ff8203                      ; video base mid
	ror.l	#8,d0
	move.b	d0,$ff8201                      ; video base high
	move.w	vbl_count,d0
flip_sync_loop:
	cmp.w	vbl_count,d0
	beq.s	flip_sync_loop
	clr.w	vbl_count
	movem.l	(sp)+,d0-d1
	rts

clear_screens:	; from: hw_init
	lea	$70000,a0
	lea	$78000,a1
	move.w	#$17bf,d7
clear_screens_loop:
	clr.l	(a0)+
	clr.l	(a1)+
	dbra	d7,clear_screens_loop
	rts

	dc.w	$2079,$0002,$883e,$3e3c,$17bf,$4298,$51cf,$fffc
	dc.w	$4e75

clear_back_dissolve:	; from: level_start, is_selected
	move.w	#$17c0,d0
	lea	$78000,a0
clear_back_loop:
	clr.l	(a0)+
	dbra	d0,clear_back_loop

dissolve_in:	; from: is_selected, draw_batcave
	movem.l	screen_front,a0-a1
	clr.w	d2
dissolve_next_cell:
	moveq	#127,d3
	and.w	d2,d3
	move.l	#$f000f00,d5
	lsr.w	#1,d3
	bcc.s	dissolve_cell
	move.l	#$f000f000,d5
dissolve_cell:
	cmpi.w	#$28,d3
	bcc.s	dissolve_advance
	move.w	d2,d4
	lsr.w	#5,d4
	andi.w	#$fc,d4
	cmpi.w	#$98,d4
	bcc.s	dissolve_advance
	mulu.w	#$a0,d4
	move.w	d3,d0
	andi.w	#$fffe,d3
	lsl.w	#2,d3
	add.w	d3,d4
	btst	#$0,d0
	beq.s	dissolve_cell_rows
	lsr.l	#8,d5
dissolve_cell_rows:
	moveq	#3,d7
dissolve_row_loop:
	move.l	d5,d6
	not.l	d6
	move.l	d6,d0
	and.l	$0(a0,d4.w),d6
	move.l	d6,$0(a0,d4.w)
	and.l	$4(a0,d4.w),d0
	move.l	d0,$4(a0,d4.w)
	move.l	d5,d6
	and.l	$0(a1,d4.w),d6
	or.l	$0(a0,d4.w),d6
	move.l	d6,$0(a0,d4.w)
	move.l	d5,d6
	and.l	$4(a1,d4.w),d6
	or.l	$4(a0,d4.w),d6
	move.l	d6,$4(a0,d4.w)
	addi.w	#$a0,d4
	dbra	d7,dissolve_row_loop
dissolve_advance:
	mulu.w	#$555,d2
	addq.w	#1,d2
	andi.w	#$1fff,d2
	bne.w	dissolve_next_cell
	rts


fade_in:	; from: level_restart
	moveq	#15,d7
fade_in_pass:
	lea	current_palette,a0
	lea	target_palette,a1
	moveq	#15,d6
fade_in_entry:
	move.w	(a0),d0
	move.w	(a1)+,d1
	eor.w	d0,d1
	moveq	#15,d2
	and.w	d1,d2
	beq.s	fade_in_green
	addq.w	#1,d0
fade_in_green:
	moveq	#-16,d2
	and.b	d1,d2
	beq.s	fade_in_red
	addi.w	#$10,d0
fade_in_red:
	andi.w	#$f00,d1
	beq.s	fade_in_store
	addi.w	#$100,d0
fade_in_store:
	move.w	d0,(a0)
	addq.w	#2,a0
	dbra	d6,fade_in_entry
	move.w	vbl_count,d0
	addq.w	#2,d0
fade_in_wait:
	cmp.w	vbl_count,d0
	bne.s	fade_in_wait
	dbra	d7,fade_in_pass
	rts


fade_out:	; from: level_start
	moveq	#15,d7
fade_out_pass:
	lea	current_palette,a0
	moveq	#15,d6
fade_out_entry:
	move.w	(a0),d0
	moveq	#15,d1
	and.w	d0,d1
	beq.s	fade_out_green
	subq.w	#1,d0
fade_out_green:
	move.w	#$f0,d1
	and.w	d0,d1
	beq.s	fade_out_red
	subi.w	#$10,d0
fade_out_red:
	move.w	#$f00,d1
	and.w	d0,d1
	beq.s	fade_out_store
	subi.w	#$100,d0
fade_out_store:
	move.w	d0,(a0)
	addq.w	#2,a0
	dbra	d6,fade_out_entry
	move.w	vbl_count,d0
	addq.w	#2,d0
fade_out_wait:
	cmp.w	vbl_count,d0
	bne.s	fade_out_wait
	dbra	d7,fade_out_pass
	rts


print_text_bold:	; from: is_selected, draw_batcave
	moveq	#-1,d6
	bra.s	text_position


print_text:	; from: show_matches
	moveq	#0,d6
text_position:	; from: print_text_bold
	move.b	(a0)+,d0
	cmpi.b	#$ff,d0
	beq.w	print_exit
	andi.w	#$ff,d0
	mulu.w	#$a0,d0
	move.b	(a0)+,d1
	ext.w	d1
	move.w	d1,d5
	andi.w	#$fe,d1
	andi.w	#$1,d5
	lsl.w	#2,d1
	add.w	d5,d1
	add.w	d1,d0
	movea.l	screen_back,a1
	lea	$0(a1,d0.w),a1
next_char:
	moveq	#0,d0
	move.b	(a0)+,d0
	beq.s	text_position
	cmpi.b	#$20,d0
	beq.w	advance_column
	moveq	#-51,d1
	cmpi.b	#$41,d0
	bcc.s	char_index
	moveq	#-44,d1
	cmpi.b	#$30,d0
	bcc.s	char_index
	moveq	#0,d1
	cmpi.b	#$21,d0
	beq.s	draw_char
	moveq	#1,d1
	cmpi.b	#$28,d0
	beq.s	draw_char
	moveq	#2,d1
	cmpi.b	#$29,d0
	beq.s	draw_char
	moveq	#3,d1
	bra.s	draw_char

char_index:
	add.b	d0,d1
	andi.w	#$ff,d1
draw_char:
	mulu.w	#$28,d1
	lea	font,a2
	lea	$0(a2,d1.w),a2
	moveq	#7,d7
	movea.l	a1,a3
	tst.w	d6
	bmi.s	char_row_bold_loop
char_row_loop:
	move.b	(a2)+,d1
	and.b	d1,(a3)
	move.b	(a2)+,d2
	or.b	d2,(a3)
	and.b	d1,$2(a3)
	move.b	(a2)+,d2
	or.b	d2,$2(a3)
	and.b	d1,$4(a3)
	move.b	(a2)+,d2
	or.b	d2,$4(a3)
	and.b	d1,$6(a3)
	move.b	(a2)+,d2
	or.b	d2,$6(a3)
	lea	$a0(a3),a3
	dbra	d7,char_row_loop
advance_column:
	addq.l	#1,a1
	bchg	#$0,d5
	beq.w	next_char
	addq.w	#6,a1
	bra.w	next_char

char_row_bold_loop:
	move.b	(a2)+,d1
	and.b	d1,(a3)
	move.b	(a2)+,d2
	or.b	d2,(a3)
	and.b	d1,$2(a3)
	move.b	(a2)+,d2
	or.b	d2,$2(a3)
	and.b	d1,$4(a3)
	move.b	(a2)+,d2
	or.b	d2,$4(a3)
	and.b	d1,$6(a3)
	move.b	(a2)+,d2
	or.b	d2,$6(a3)
	lea	$a0(a3),a3
	lea	-$5(a2),a2
	move.b	(a2)+,d1
	and.b	d1,(a3)
	move.b	(a2)+,d2
	or.b	d2,(a3)
	and.b	d1,$2(a3)
	move.b	(a2)+,d2
	or.b	d2,$2(a3)
	and.b	d1,$4(a3)
	move.b	(a2)+,d2
	or.b	d2,$4(a3)
	and.b	d1,$6(a3)
	move.b	(a2)+,d2
	or.b	d2,$6(a3)
	lea	$a0(a3),a3
	dbra	d7,char_row_bold_loop
	bra.s	advance_column

print_exit:
	rts


; Font, 40 bytes per character, unscrambled at level start.
font:	; from: level_start, print_text
	incbin	"data/l3_font.bin"		; $640 bytes of data
spare_counter:	; from: level_restart
	dc.w	$0000,$0000,$0000,$0000

wait_frames:	; from: level_start, main_loop, cursor_update, is_selected, reveal_answer, draw_batcave
	tst.w	frame_flag
	beq.s	wait_frames
	clr.w	frame_flag
	dbra	d0,wait_frames
	rts

	dc.w	$303c,$000f,$5489,$32d8,$5489,$51c8,$fffa,$7001
	dc.w	$6000,$ffda
keys_exit:	; from: handle_keys, play_sound
	rts


;----------------------------------------------------------------------
; F10 toggles cheat_skip (cheat on), F2 toggles music, ESC aborts the level.
;----------------------------------------------------------------------
handle_keys:	; from: main_loop
	bsr.w	get_key
	cmpi.b	#$8a,d0
	beq.w	cheat_toggle
	cmpi.b	#$82,d0
	beq.w	toggle_music
	cmpi.b	#$1b,d0
	beq.w	abort_level
	bra.w	keys_exit

toggle_music:
	jsr	snd_stop
	bchg	#$0,game_flags

;----------------------------------------------------------------------
; Play effect d0 when effects are on, else tune 3 once.
;----------------------------------------------------------------------
play_sound:	; from: level_restart, cursor_update
	btst	#$0,game_flags
	beq.s	play_tune_once
	move.w	d0,last_tune
	jsr	snd_play_sfx
	rts

play_tune_once:
	moveq	#3,d0
	cmp.w	last_tune,d0
	beq.w	keys_exit
	move.w	d0,last_tune
	jmp	snd_play_tune

last_tune:	; from: play_sound
	dc.w	$ffff,$4279,$0002,$87a6,$4239,$0002,$8786,$4279
	dc.w	$0002,$916a,$4e75
abort_level:	; from: handle_keys
	move.w	#$9999,panel_time
	bset	#$1,panel_flags
	jmp	end_level

cheat_toggle:	; from: handle_keys
	btst	#$7,game_flags
	beq.s	cheat_exit
	not.w	cheat_skip
	jmp	end_level

cheat_exit:
	rts


;----------------------------------------------------------------------
; Draw the eight items on the $78000 screen at item_x / item_y.
;----------------------------------------------------------------------
draw_all_items:	; from: draw_batcave
	move.l	#$78000,draw_screen
	lea	item_x,a0
	lea	item_y,a1
	move.w	#$1,d0
	moveq	#0,d1
draw_items_loop:
	bsr.s	draw_item
	addq.w	#1,d1
	addq.w	#1,d0
	cmpi.w	#$9,d0
	bne.s	draw_items_loop
	clr.w	fire_latch
	move.l	#$70000,draw_screen
	rts


draw_selected_items:	; from: show_matches
	lea	item_x,a0
	lea	item_y,a1
	move.w	selection+4,d0
	bsr.w	draw_item_number
	move.w	selection+2,d0
	bsr.w	draw_item_number
	move.w	selection,d0

draw_item_number:	; from: draw_selected_items
	move.w	d0,d1
	subi.w	#$1,d1

draw_item:	; from: draw_all_items
	asl.w	#1,d1
	move.w	$0(a0,d1.w),sprite_x
	move.w	$0(a1,d1.w),sprite_y
	move.w	d0,sprite_number
	movem.l	d0-d1/a0-a1,-(sp)
	bsr.w	draw_sprite
	movem.l	(sp)+,d0-d1/a0-a1
	lsr.w	#1,d1
	rts

item_x:	; from: draw_all_items, draw_selected_items, reveal_answer
	dc.w	$0010,$0010,$0010,$0010,$0118,$0118,$0118,$0118
item_y:	; from: draw_all_items, draw_selected_items
	dc.w	$0005,$002a,$004e,$0074,$0005,$002a,$004f,$0073

;----------------------------------------------------------------------
; New puzzle: counters, cursor at the first item, answer, 89 seconds, energy bar.
;----------------------------------------------------------------------
init_puzzle:	; from: level_restart
	clr.l	slot_index
	clr.w	tries_left
	clr.l	move_timer_y
	clr.w	spare_flag
	move.w	#$3,picks_left
	move.w	#$1,cursor_item
	move.w	#$73,spare_value
	move.w	#$5,tries_left
	move.w	#$0,cursor_x
	move.w	#$12,cursor_y
	bsr.w	pick_answer
	move.w	#$59,d0
	jsr	panel_set_time
	move.w	#$9999,panel_time
	jsr	panel_init_energy
	move.l	#$70000,screen_front
	move.l	#$78000,screen_back
	move.w	#$6e0c,matches_text
	clr.l	selection
	clr.w	selection+4
	bra.w	clear_sprite_vars


;----------------------------------------------------------------------
; Choose three distinct random items as the answer.
;----------------------------------------------------------------------
pick_answer:	; from: init_puzzle
	clr.l	answer
	clr.w	answer+4
	bsr.w	random_item
	move.w	d0,answer
	bsr.w	random_item
	move.w	d0,answer+2
	bsr.w	random_item
	move.w	d0,answer+4
	rts


random_item:	; from: pick_answer
	bsr.w	random
	move.w	random_value,d0
	andi.w	#$7,d0
	moveq	#0,d7
	bsr.w	is_answer
	tst.w	d7
	bne.s	random_item
	rts


;----------------------------------------------------------------------
; Random number from the MFP timers, the joystick and the keyboard, mixed into random_pool.
;----------------------------------------------------------------------
random:	; from: random_item, unused_debug_random
	movem.l	d0-d2/a0,-(sp)
	move.b	$fffa21,d0                      ; MFP TBDR
	and.b	$fffa23,d0                      ; MFP TCDR
	or.b	$fffa25,d0                      ; MFP TDDR
	lea	random_pool,a0
	moveq	#7,d1
random_pool_loop:
	add.w	d0,(a0)+
	dbra	d1,random_pool_loop
	move.b	$fffa23,d1                      ; MFP TCDR
	move.b	$fffa21,d2                      ; MFP TBDR
	or.b	joy1_fire,d0
	and.w	key_queue,d1
	lea	random_pool,a0
	eor.w	d1,d0
	or.w	d2,d0
	move.w	d0,d1
	andi.w	#$7,d0
	asl.w	#1,d0
	eor.w	d1,$0(a0,d0.w)
	move.w	$0(a0,d0.w),d0
	move.w	d0,random_value
	movem.l	(sp)+,d0-d2/a0
	rts

random_value:	; from: random_item, random, unused_debug_random
	dc.w	$1164
random_pool:	; from: timerb_handler, random
	dc.w	$f051,$ffe0,$cf01,$337f,$feef,$0506,$0838,$0012
	dc.w	$0839,$0006,$00df,$f002,$6600,$fff6,$4e75

;----------------------------------------------------------------------
; Move the cursor between the item slots (slot_x/slot_y) and handle a selection:
; after three picks compare with answer; "SMILEX SUCCESSFULLY ANALYSED" on a full match.
;----------------------------------------------------------------------
cursor_update:	; from: main_loop
	tst.w	move_timer_y
	beq.w	cursor_move_x
	move.w	cursor_dy,d0
	add.w	d0,cursor_y
	subi.w	#$1,move_timer_y
cursor_move_x:
	tst.w	move_timer_x
	beq.w	cursor_move_exit
	move.w	cursor_dx,d0
	add.w	d0,cursor_x
	subi.w	#$1,move_timer_x
cursor_move_exit:
	rts

read_input:	; from: frame_update
	clr.l	joy_flags
	clr.w	fire_pressed
	move.w	joy1_fire,d0
	btst	#$3,d0
	sne	joy_flags
	btst	#$2,d0
	sne	joy_flags+1
	btst	#$1,d0
	sne	joy_flags+2
	btst	#$0,d0
	sne	joy_flags+3
	tst.b	joy1_fire
	sne	fire_pressed
	tst.w	move_timer_x
	bne.s	input_vertical
	clr.w	cursor_dx
	tst.b	joy_flags
	beq.s	input_left
	move.w	#$10,cursor_dx
input_left:
	tst.b	joy_flags+1
	beq.s	input_vertical
	move.w	#$fff0,cursor_dx
input_vertical:
	tst.w	move_timer_y
	bne.s	input_start_x
	clr.w	cursor_dy
	tst.b	joy_flags+2
	beq.s	input_up
	move.w	#$4,cursor_dy
input_up:
	tst.b	joy_flags+3
	beq.s	input_start_x
	move.w	#$fffc,cursor_dy
input_start_x:
	tst.w	move_timer_x
	bne.s	input_start_y
	tst.w	cursor_dx
	beq.s	input_start_y
	bpl.w	input_start_right
	cmpi.w	#$80,cursor_x
	blt.w	input_start_y
	move.w	#$11,move_timer_x
	bra.w	input_start_y

input_start_right:
	cmpi.w	#$80,cursor_x
	bgt.w	input_start_y
	move.w	#$11,move_timer_x
input_start_y:
	tst.w	move_timer_y
	bne.s	input_select
	tst.w	cursor_dy
	beq.s	input_select
	bpl.w	input_down_row
	cmpi.w	#$20,cursor_y
	blt.w	input_select
	subi.w	#$1,cursor_item
	bra.w	input_row_timer

input_down_row:
	cmpi.w	#$71,cursor_y
	bgt.w	input_select
	addi.w	#$1,cursor_item
input_row_timer:
	move.w	#$9,move_timer_y
	rts

input_select:
	move.w	cursor_dx,d0
	or.w	cursor_dy,d0
	or.w	move_timer_x,d0
	or.w	move_timer_y,d0
	bne.w	cursor_select_exit
	tst.w	fire_pressed
	beq.w	select_release
	tst.w	fire_latch
	bne.w	cursor_select_exit
	lea	selection,a2
	lea	slot_x,a0
	lea	slot_y,a1
	move.w	slot_index,d2
	move.w	selection_index,d1
	bsr.w	cursor_item_index
	moveq	#0,d7
	move.w	sprite_number,d0
	bsr.w	is_selected
	tst.w	d7
	bne.w	select_exit
	bsr.w	copy_front_to_back
	move.w	sprite_number,$0(a2,d1.w)
	move.w	$0(a0,d2.w),sprite_x
	move.w	$0(a1,d2.w),sprite_y
	bsr.w	draw_sprite
	bsr.w	restore_cursor_bg
	moveq	#11,d0
	bsr.w	play_sound
	bsr.w	draw_cursor
	subi.w	#$1,picks_left
	bne.w	select_done
	bsr.w	show_matches
	cmpi.b	#$33,matches_text+2
	bne.s	wrong_answer
	bsr.w	draw_cursor_masked
	moveq	#1,d0
	bsr.w	wait_frames
	bsr.w	flip_screens
	bra.w	level_complete

wrong_answer:
	moveq	#12,d0
	bsr.w	play_sound
	subi.w	#$1,tries_left
	bpl.w	try_again
	move.w	#$80,d0
	jsr	panel_lose_energy
	bsr.w	draw_cursor_masked
	moveq	#1,d0
	bsr.w	wait_frames
	bsr.w	flip_screens
	bra.w	lose_game

try_again:
	moveq	#6,d0
	jsr	panel_lose_energy
	move.w	#$3,picks_left
	move.w	#$fffe,selection_index
	clr.l	selection
	clr.w	selection+4
select_done:
	bsr.w	draw_cursor_masked
	moveq	#1,d0
	bsr.w	wait_frames
	bsr.w	flip_screens
	not.w	fire_latch
	addi.w	#$2,slot_index
	addi.w	#$2,selection_index
select_exit:
	rts

slot_x:	; from: cursor_update
	dc.w	$0058,$0058,$0058,$0070,$0070,$0070,$0088,$0088
	dc.w	$0088,$00a0,$00a0,$00a0,$00b8,$00b8,$00b8,$00d0
	dc.w	$00d0,$00d0,$00e8,$00e8,$00e8
slot_y:	; from: cursor_update
	dc.w	$0013,$0031,$004f,$0013,$0031,$004f,$0013,$0031
	dc.w	$004f,$0013,$0031,$004f,$0013,$0031,$004f,$0013
	dc.w	$0031,$004f,$0013,$0031,$004f
answer:	; from: pick_answer, is_answer
	dc.w	$0006,$0007,$0008
selection:	; from: draw_selected_items, init_puzzle, cursor_update, count_matches, is_selected
	dc.w	$0000,$0000,$0000

cursor_item_index:	; from: cursor_update
	move.w	cursor_item,sprite_number
	cmpi.w	#$80,cursor_x
	blt.s	item_index_exit
	addi.w	#$4,sprite_number
item_index_exit:
	rts


copy_front_to_back:	; from: cursor_update
	movem.l	d7/a0-a1,-(sp)
	lea	$70000,a0
	lea	$78000,a1
	bra.w	copy_screen_words

	dc.w	$48e7,$01c0,$41f9,$0007,$8000,$43f9,$0007,$0000
copy_screen_words:
	move.w	#$17c0,d7
copy_front_loop:
	move.l	(a0)+,(a1)+
	dbra	d7,copy_front_loop
	bsr.w	flip_screens
	movem.l	(sp)+,d7/a0-a1
	rts


;----------------------------------------------------------------------
; After the third pick: count the matching items, score 256 per match and print the count.
;----------------------------------------------------------------------
show_matches:	; from: cursor_update
	movem.l	d0-d7/a0-a6,-(sp)
	bsr.w	draw_selected_items
	clr.w	fire_latch
	move.b	#$30,d7
	bsr.w	count_matches
	move.b	d7,matches_text+2
	moveq	#0,d0
	move.b	d7,d0
	subi.b	#$30,d0
	asl.l	#8,d0
	jsr	panel_add_score
	lea	matches_text,a0
	bsr.w	print_text
	movem.l	(sp)+,d0-d7/a0-a6
	addi.b	#$3,matches_text+1
	rts

matches_text:	; from: init_puzzle, show_matches
	dc.w	$6e0c,$3000,$ff39
spare_value:	; from: init_puzzle
	dc.w	$0073

count_matches:	; from: show_matches
	move.w	selection,d0
	bsr.w	is_answer
	move.w	selection+2,d0
	bsr.w	is_answer
	move.w	selection+4,d0

is_answer:	; from: random_item, count_matches
	cmp.w	answer,d0
	beq.s	answer_match
	cmp.w	answer+2,d0
	beq.s	answer_match
	cmp.w	answer+4,d0
	beq.s	answer_match
	rts

answer_match:
	addq.w	#1,d7
	rts


is_selected:	; from: cursor_update
	cmp.w	selection,d0
	beq.s	selected_match
	cmp.w	selection+2,d0
	beq.s	selected_match
	cmp.w	selection+4,d0
	beq.s	selected_match
	rts

selected_match:
	addq.w	#1,d7
	rts

level_complete:	; from: cursor_update
	jsr	snd_stop
	move.w	#$d,d3
	bsr.w	reveal_answer
	moveq	#2,d0
	moveq	#0,d0
	move.w	panel_time_bcd,d0
	asl.l	#8,d0
	asl.l	#4,d0
	jsr	panel_add_score
	move.w	#$ffff,cheat_skip
	move.w	#$9999,panel_time
	move.w	#$c8,d0
	bsr.w	wait_frames
	move.w	#$17c0,d0
	lea	$78000,a0
complete_clear_loop:
	clr.l	(a0)+
	dbra	d0,complete_clear_loop
	move.l	#$78000,screen_back
	lea	success_text,a0
	bsr.w	print_text_bold
	move.l	#$70000,screen_front
	move.l	#$78000,screen_back
	bsr.w	dissolve_in
	move.w	#$c8,d0
	bsr.w	wait_frames
	lea	cursor_gfx,a0
	bra.w	level_restart

	dc.w	$33fc,$0001,$0002,$8080,$6000,$001a
lose_game:	; from: main_loop, cursor_update
	move.w	#$80,d0
	jsr	panel_lose_energy
	move.w	#$b,d3
	bsr.w	reveal_answer
	jsr	snd_stop
	move.w	#$9999,panel_time
	move.w	#$c8,d0
	bsr.w	wait_frames
end_level:	; from: play_sound
	move.w	#$17c0,d0
	lea	$78000,a0
end_clear_loop:
	clr.l	(a0)+
	dbra	d0,end_clear_loop
	move.l	#$70000,screen_front
	move.l	#$78000,screen_back
	btst	#$0,panel_flags
	bne.s	end_time_out
	btst	#$1,panel_flags
	bne.s	end_game_over
	bra.w	end_restart

end_game_over:
	moveq	#8,d0
	jsr	snd_play_tune
	lea	game_over_text,a0
	bra.w	end_print_text

end_time_out:
	lea	time_out_text,a0
end_print_text:
	bsr.w	print_text_bold
	move.l	#$70000,screen_front
	move.l	#$78000,screen_back
	bsr.w	dissolve_in
	move.w	#$c8,d0
	bsr.w	wait_frames
end_restart:
	move.l	#$70000,screen_front
	move.l	#$78000,screen_back
	bsr.w	clear_back_dissolve
	bra.w	level_restart


;----------------------------------------------------------------------
; Reveal: sweep sprite d3 over the items, then the big picture d3+1 for a wrong (11) or right (13) answer.
;----------------------------------------------------------------------
reveal_answer:	; from: is_selected
	move.w	#$9999,panel_time
	bsr.w	clear_sprite_vars
	move.w	#$25,d0
	bsr.w	wait_frames
	movem.l	d3,-(sp)
	lea	$63800,a0
	lea	$70000,a1
	bsr.w	copy_screen
	movem.l	(sp)+,d3
	lea	item_x,a0
	lea	reveal_y,a1
	moveq	#0,d2
reveal_sweep_loop:
	move.w	#$5,d0
	bsr.w	wait_frames
	bsr.w	draw_item_at
	addq.w	#2,d2
	cmpi.w	#$12,d2
	bne.s	reveal_sweep_loop
	move.w	#$4,d0
	bsr.w	wait_frames
	addi.w	#$1,d3
	cmpi.w	#$c,d3
	bne.s	reveal_win_picture
	move.w	#$80,sprite_x
	move.w	#$10,sprite_y
	bra.w	reveal_draw_picture

reveal_win_picture:
	move.w	#$80,sprite_x
	move.w	#$2d,sprite_y
reveal_draw_picture:
	move.w	d3,sprite_number
	bsr.w	draw_sprite
	rts

	dc.w	$303c,$0060,$6000,$f750

draw_item_at:	; from: reveal_answer
	move.w	$0(a0,d2.w),sprite_x
	move.w	$0(a1,d2.w),sprite_y
	move.w	d3,sprite_number
	movem.l	d2-d3/a0-a1,-(sp)
	bsr.w	draw_sprite
	movem.l	(sp)+,d2-d3/a0-a1
	rts

reveal_y:	; from: reveal_answer
	dc.w	$0005,$002a,$004e,$0074,$0073,$004f,$002a,$0005
	dc.w	$3039,$0002,$9b0a,$3200,$41f9,$0002,$9af6,$d040
	dc.w	$33f0,$00fe,$0002,$a0ca,$33f9,$0002,$a0c8,$0002
	dc.w	$a0c6,$0679,$0003,$0002,$a0c6,$0c79,$0080,$0002
	dc.w	$a0c8,$6d00,$0004,$5841,$33c1,$0002,$a0f8,$6100
	dc.w	$02fe
cursor_select_exit:	; from: cursor_update
	rts


;----------------------------------------------------------------------
; Draw the cursor sprite (10) at cursor_x and the row of cursor_item.
;----------------------------------------------------------------------
draw_cursor:	; from: cursor_update
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	cursor_item,d0
	move.w	d0,d1
	lea	row_y,a0
	add.w	d0,d0
	move.w	-$2(a0,d0.w),sprite_y
	move.w	cursor_x,sprite_x
	addi.w	#$10,sprite_x
	cmpi.w	#$80,cursor_x
	blt.w	cursor_draw_sprite
	subi.w	#$4,d1
	subi.w	#$8,sprite_x
cursor_draw_sprite:
	move.w	#$a,sprite_number
	bsr.w	draw_sprite
	movem.l	(sp)+,d0-d7/a0-a6
	rts

select_release:	; from: cursor_update
	clr.w	fire_latch
	rts

row_y:	; from: draw_cursor
	dc.w	$0005,$002a,$004f,$0074
picks_left:	; from: init_puzzle, cursor_update
	dc.w	$0003
slot_index:	; from: init_puzzle, cursor_update
	dc.w	$0000
selection_index:	; from: cursor_update
	dc.w	$0000
tries_left:	; from: init_puzzle, cursor_update
	dc.w	$0000
move_timer_y:	; from: init_puzzle, cursor_update
	dc.w	$0000
move_timer_x:	; from: cursor_update
	dc.w	$0000
cursor_item:	; from: init_puzzle, cursor_update, cursor_item_index, draw_cursor
	dc.w	$0001
cursor_dx:	; from: cursor_update, unused_debug_input
	dc.w	$0000
cursor_dy:	; from: cursor_update
	dc.w	$0000
fire_pressed:	; from: cursor_update
	dc.w	$0000
fire_latch:	; from: draw_all_items, cursor_update, show_matches, draw_cursor
	dc.w	$0000
joy_flags:	; from: cursor_update
	dc.w	$0000,$0000
draw_size:	; from: frame_update
	dc.w	$0000,$0000
draw_screen:	; from: draw_all_items, frame_update, sprite_clip
	dc.w	$0000,$0000

;----------------------------------------------------------------------
; Per frame: restore the screen under the frame, draw the frame at the cursor, read the joystick.
;----------------------------------------------------------------------
frame_update:	; from: main_loop
	move.l	#$1a20,draw_size
	move.l	#$70000,draw_screen
	bsr.w	restore_cursor_bg
	bsr.w	draw_cursor_masked
	bra.w	read_input


;----------------------------------------------------------------------
; Put the saved screen area back from cursor_background (interleaved planes).
;----------------------------------------------------------------------
restore_cursor_bg:	; from: cursor_update, frame_update
	move.l	cursor_bg_addr,d0
	beq.s	restore_bg_exit
	exg	d0,a1
	moveq	#0,d1
	move.w	bg_plane_size,d1
	lea	cursor_background,a0
	moveq	#0,d0
	move.w	d1,d2
	add.w	d1,d2
	move.w	d2,d3
	add.w	d1,d3
	move.w	bg_height,d7
	subq.w	#4,d7
restore_bg_loop:
	move.w	$0(a0,d0.w),(a1)
	move.w	$0(a0,d1.w),$2(a1)
	move.w	$0(a0,d2.w),$4(a1)
	move.w	$0(a0,d3.w),$6(a1)
	move.w	$2(a0,d0.w),$8(a1)
	move.w	$2(a0,d1.w),$a(a1)
	move.w	$2(a0,d2.w),$c(a1)
	move.w	$2(a0,d3.w),$e(a1)
	move.w	$4(a0,d0.w),$10(a1)
	move.w	$4(a0,d1.w),$12(a1)
	move.w	$4(a0,d2.w),$14(a1)
	move.w	$4(a0,d3.w),$16(a1)
	lea	$a0(a1),a1
	lea	$6(a0),a0
	dbra	d7,restore_bg_loop
restore_bg_exit:
	rts

cursor_bg_addr:	; from: restore_cursor_bg, draw_cursor_masked
	dc.w	$0000,$0000

;----------------------------------------------------------------------
; Clip the frame sprite at the cursor, save the screen under it and draw it through its mask.
;----------------------------------------------------------------------
draw_cursor_masked:	; from: cursor_update, frame_update
	move.l	#cursor_background,cursor_bg_base
	lea	cursor_x,a0
	lea	cursor_spare,a1
	lea	cursor_size,a2
	lea	cursor_dest,a3
	lea	cursor_line_width,a4
	lea	cursor_clip_flag,a5
	lea	cursor_sprite_number,a6
	clr.l	clip_dest
	bsr.w	sprite_clip
	lsr.w	#6,d4
	move.l	cursor_bg_base,(a3)
	move.l	clip_dest,d0
	beq.w	draw_masked_exit
	movea.l	d0,a1
	move.l	d0,cursor_bg_addr
	lea	frame_gfx+6,a0
	lea	frame_mask+6,a2
	move.w	#$3,d0
	move.w	#$5a,d1
	bsr.w	save_bg_and_mask
draw_masked_exit:
	rts


;----------------------------------------------------------------------
; Save the screen area at a1 (d0 words x d1 lines) to cursor_background and mask a0/a2 over it.
;----------------------------------------------------------------------
save_bg_and_mask:	; from: draw_cursor_masked
	move.w	d0,bg_width
	move.w	d1,bg_height
	asl.w	#1,d0
	mulu.w	d0,d1
	move.w	d1,bg_plane_size
	moveq	#0,d0
	move.w	d1,d2
	add.w	d1,d2
	move.w	d2,d3
	add.w	d1,d3
	movem.l	a0-a1,-(sp)
	move.w	d4,bg_height
	lea	cursor_background,a0
	move.w	bg_height,d7
	subq.w	#4,d7
save_bg_loop:
	move.w	(a1),$0(a0,d0.w)
	move.w	$2(a1),$0(a0,d1.w)
	move.w	$4(a1),$0(a0,d2.w)
	move.w	$6(a1),$0(a0,d3.w)
	move.w	$8(a1),$2(a0,d0.w)
	move.w	$a(a1),$2(a0,d1.w)
	move.w	$c(a1),$2(a0,d2.w)
	move.w	$e(a1),$2(a0,d3.w)
	move.w	$10(a1),$4(a0,d0.w)
	move.w	$12(a1),$4(a0,d1.w)
	move.w	$14(a1),$4(a0,d2.w)
	move.w	$16(a1),$4(a0,d3.w)
	lea	$a0(a1),a1
	lea	$6(a0),a0
	dbra	d7,save_bg_loop
	movem.l	(sp)+,a0-a1
	move.w	bg_height,d7
	subq.w	#4,d7
	move.w	bg_width,d6
	subq.w	#1,d6
mask_frame_loop:
	move.w	d6,d5
	move.w	(a2)+,d4
	move.w	(a1),d0
	and.w	d4,d0
	or.w	(a0),d0
	move.w	d0,(a1)
	move.w	$2(a1),d0
	and.w	d4,d0
	or.w	$0(a0,d1.w),d0
	move.w	d0,$2(a1)
	move.w	$4(a1),d0
	and.w	d4,d0
	or.w	$0(a0,d2.w),d0
	move.w	d0,$4(a1)
	move.w	$6(a1),d0
	and.w	d4,d0
	or.w	$0(a0,d3.w),d0
	move.w	d0,$6(a1)
	move.w	(a2)+,d4
	move.w	$8(a1),d0
	and.w	d4,d0
	or.w	$2(a0),d0
	move.w	d0,$8(a1)
	move.w	$a(a1),d0
	and.w	d4,d0
	or.w	$2(a0,d1.w),d0
	move.w	d0,$a(a1)
	move.w	$c(a1),d0
	and.w	d4,d0
	or.w	$2(a0,d2.w),d0
	move.w	d0,$c(a1)
	move.w	$e(a1),d0
	and.w	d4,d0
	or.w	$2(a0,d3.w),d0
	move.w	d0,$e(a1)
	move.w	(a2)+,d4
	move.w	$10(a1),d0
	and.w	d4,d0
	or.w	$4(a0),d0
	move.w	d0,$10(a1)
	move.w	$12(a1),d0
	and.w	d4,d0
	or.w	$4(a0,d1.w),d0
	move.w	d0,$12(a1)
	move.w	$14(a1),d0
	and.w	d4,d0
	or.w	$4(a0,d2.w),d0
	move.w	d0,$14(a1)
	move.w	$16(a1),d0
	and.w	d4,d0
	or.w	$4(a0,d3.w),d0
	move.w	d0,$16(a1)
	lea	$a0(a1),a1
	lea	$6(a0),a0
	dbra	d7,mask_frame_loop
	rts

bg_width:	; from: save_bg_and_mask
	dc.w	$0000
bg_height:	; from: restore_cursor_bg, save_bg_and_mask
	dc.w	$0000
bg_plane_size:	; from: restore_cursor_bg, save_bg_and_mask
	dc.w	$0000

;----------------------------------------------------------------------
; Draw sprite sprite_number (sprite_table: width, height, graphic, mask) at sprite_x/sprite_y.
;----------------------------------------------------------------------
draw_sprite:	; from: draw_item, cursor_update, reveal_answer, draw_item_at, draw_cursor
	lea	sprite_x,a0
	lea	sprite_size,a2
	lea	sprite_dest,a3
	lea	sprite_line_width,a4
	lea	sprite_clip_flag,a5
	lea	sprite_number,a6
	moveq	#0,d7
	bsr.w	sprite_clip
	move.l	clip_dest,d0
	beq.w	draw_sprite_exit
	moveq	#0,d0
	move.w	(a2),d0
	move.w	d0,d1
	andi.w	#$3f,d0
	lsr.w	#6,d1
	move.w	d0,sprite_cols
	move.w	d1,sprite_rows
	asl.w	#1,d0
	mulu.w	d1,d0
	move.w	d0,d1
	move.w	d1,d2
	add.w	d0,d2
	move.w	d2,d3
	add.w	d0,d3
	moveq	#0,d0
	movea.l	clip_gfx_ptr,a0
	movea.l	clip_mask_ptr,a1
	movea.l	clip_dest,a2
	move.w	sprite_rows,d7
	subq.w	#2,d7
	tst.w	sprite_odd_x
	bne.w	sprite_odd_row_loop
sprite_row_loop:
	movem.l	a0-a2,-(sp)
	move.w	sprite_cols,d6
	move.w	d6,d5
	andi.w	#$1,d5
	eori.w	#$1,d5
	lsr.w	#1,d6
	add.w	d5,d6
sprite_col_loop:
	move.b	(a2),d0
	and.b	(a1),d0
	or.b	(a0),d0
	move.b	d0,(a2)
	move.b	$2(a2),d0
	and.b	(a1),d0
	or.b	$0(a0,d1.w),d0
	move.b	d0,$2(a2)
	move.b	$4(a2),d0
	and.b	(a1),d0
	or.b	$0(a0,d2.w),d0
	move.b	d0,$4(a2)
	move.b	$6(a2),d0
	and.b	(a1),d0
	or.b	$0(a0,d3.w),d0
	move.b	d0,$6(a2)
	move.b	$1(a2),d0
	and.b	$1(a1),d0
	or.b	$1(a0),d0
	move.b	d0,$1(a2)
	move.b	$3(a2),d0
	and.b	$1(a1),d0
	or.b	$1(a0,d1.w),d0
	move.b	d0,$3(a2)
	move.b	$5(a2),d0
	and.b	$1(a1),d0
	or.b	$1(a0,d2.w),d0
	move.b	d0,$5(a2)
	move.b	$7(a2),d0
	and.b	$1(a1),d0
	or.b	$1(a0,d3.w),d0
	move.b	d0,$7(a2)
	lea	$2(a0),a0
	lea	$2(a1),a1
	lea	$8(a2),a2
	dbra	d6,sprite_col_loop
	movem.l	(sp)+,a0-a2
	clr.l	d6
	move.w	sprite_cols,d6
	add.w	d6,d6
	adda.l	d6,a0
	adda.l	d6,a1
	lea	$a0(a2),a2
	dbra	d7,sprite_row_loop
draw_sprite_exit:
	rts

sprite_odd_row_loop:
	movem.l	a0-a2,-(sp)
	move.w	sprite_cols,d6
	lsr.w	#1,d6
sprite_odd_col_loop:
	move.b	$1(a2),d0
	and.b	(a1),d0
	or.b	(a0),d0
	move.b	d0,$1(a2)
	move.b	$3(a2),d0
	and.b	(a1),d0
	or.b	$0(a0,d1.w),d0
	move.b	d0,$3(a2)
	move.b	$5(a2),d0
	and.b	(a1),d0
	or.b	$0(a0,d2.w),d0
	move.b	d0,$5(a2)
	move.b	$7(a2),d0
	and.b	(a1),d0
	or.b	$0(a0,d3.w),d0
	move.b	d0,$7(a2)
	lea	$8(a2),a2
	move.b	(a2),d0
	and.b	$1(a1),d0
	or.b	$1(a0),d0
	move.b	d0,(a2)
	move.b	$2(a2),d0
	and.b	$1(a1),d0
	or.b	$1(a0,d1.w),d0
	move.b	d0,$2(a2)
	move.b	$4(a2),d0
	and.b	$1(a1),d0
	or.b	$1(a0,d2.w),d0
	move.b	d0,$4(a2)
	move.b	$6(a2),d0
	and.b	$1(a1),d0
	or.b	$1(a0,d3.w),d0
	move.b	d0,$6(a2)
	lea	$2(a0),a0
	lea	$2(a1),a1
	dbra	d6,sprite_odd_col_loop
	movem.l	(sp)+,a0-a2
	clr.l	d6
	move.w	sprite_cols,d6
	add.w	d6,d6
	adda.l	d6,a0
	adda.l	d6,a1
	lea	$a0(a2),a2
	dbra	d7,sprite_odd_row_loop
	rts

sprite_cols:	; from: draw_sprite
	dc.w	$0000
sprite_rows:	; from: draw_sprite
	dc.w	$0000

;----------------------------------------------------------------------
; Clip sprite (a6) at (a0) x/y to the screen: sets clip_width/height, the data pointers and
; clip_dest, or clears clip_dest when it is off screen.
;----------------------------------------------------------------------
sprite_clip:	; from: draw_cursor_masked, draw_sprite
	moveq	#0,d0
	move.w	#$a0,(a4)
	move.w	(a4),line_bytes
	movem.l	a0,-(sp)
	move.w	(a6),d0
	mulu.w	#$c,d0
	lea	sprite_table,a0
	move.l	$0(a0,d0.w),clip_width
	move.l	$4(a0,d0.w),clip_gfx_ptr
	move.l	$8(a0,d0.w),clip_mask_ptr
	movem.l	(sp)+,a0
	moveq	#0,d0
	move.w	(a0),d0
	move.w	d0,sprite_odd_x
	andi.w	#$8,sprite_odd_x
	andi.w	#$fff0,d0
	lsr.w	#3,d0
	ext.w	d0
	move.w	$4(a0),d1
	addi.w	#$100,d1
	addi.w	#$100,d0
	move.w	clip_height,d4
	move.w	d1,d3
	cmpi.w	#$19b,d3
	bgt.w	sprite_off_screen
	add.w	d4,d3
	cmpi.w	#$19b,d3
	blt.w	sprite_clip_top
	subi.w	#$19b,d3
	sub.w	d3,d4
	beq.s	sprite_off_screen
	bpl.s	sprite_clip_top
sprite_off_screen:
	clr.l	clip_dest
	rts

sprite_clip_top:
	cmpi.w	#$100,d1
	bgt.w	sprite_clip_x
	move.w	d1,d3
	add.w	d4,d3
	subi.w	#$100,d3
	bmi.w	sprite_off_screen
	move.w	d3,d4
	beq.w	sprite_off_screen
	sub.w	clip_height,d3
	neg.w	d3
	mulu.w	clip_width,d3
	add.l	d3,clip_gfx_ptr
	add.l	d3,clip_mask_ptr
	move.w	#$100,d1
sprite_clip_x:
	clr.w	(a5)
	cmpi.w	#$130,d0
	bgt.w	sprite_off_screen
	cmpi.w	#$100,d0
	bgt.w	sprite_clip_right
	move.w	d0,d3
	subi.w	#$100,d3
	bmi.w	sprite_off_screen
	nop
	move.w	#$100,d0
sprite_clip_right:
	move.w	d0,d3
	add.w	clip_width,d3
	cmpi.w	#$130,d3
	blt.w	sprite_visible
	bra.w	sprite_off_screen

sprite_visible:
	move.w	clip_width,d6
	sub.w	d6,(a4)
	subi.w	#$100,d0
	subi.w	#$100,d1
	asl.w	#2,d0
	mulu.w	line_bytes,d1
	add.l	d1,d0
	move.l	draw_screen,d1
	add.l	d0,d1
	move.l	d1,clip_dest
	move.w	clip_width,d5
	mulu.w	d4,d5
	move.l	d5,clip_size
	move.w	clip_width,d5
	lsr.w	#1,d5
	asl.w	#6,d4
	or.w	d4,d5
	move.w	d5,(a2)
	rts

sprite_odd_x:	; from: draw_sprite, sprite_clip
	dc.w	$0000

clear_sprite_vars:	; from: init_puzzle, reveal_answer
	lea	sprite_size,a0
	move.w	#$2,d7
clear_sprite_loop:
	clr.w	(a0)+
	dbra	d7,clear_sprite_loop
	rts

sprite_x:	; from: draw_item, cursor_update, reveal_answer, draw_item_at, draw_cursor, draw_sprite
	dc.w	$0000
cursor_x:	; from: init_puzzle, cursor_update, cursor_item_index, draw_cursor, draw_cursor_masked
	dc.w	$0000
sprite_y:	; from: draw_item, cursor_update, reveal_answer, draw_item_at, draw_cursor
	dc.w	$0000
cursor_y:	; from: init_puzzle, cursor_update
	dc.w	$0000
sprite_dest:	; from: draw_sprite
	dc.w	$0000,$0000
cursor_dest:	; from: draw_cursor_masked
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000
cursor_spare:	; from: draw_cursor_masked
	dc.w	$0000,$0000,$0000,$0000
sprite_size:	; from: draw_sprite, clear_sprite_vars
	dc.w	$0000
cursor_size:	; from: draw_cursor_masked
	dc.w	$0000,$0000
sprite_line_width:	; from: draw_sprite
	dc.w	$0000
cursor_line_width:	; from: draw_cursor_masked
	dc.w	$0000,$0000
sprite_clip_flag:	; from: draw_sprite
	dc.w	$0000
cursor_clip_flag:	; from: draw_cursor_masked
	dc.w	$0000,$0000
sprite_number:	; from: draw_item, cursor_update, cursor_item_index, reveal_answer, draw_item_at, draw_cursor, ...
	dc.w	$0000
cursor_sprite_number:	; from: draw_cursor_masked
	dc.w	$0000
sprite_table:	; from: sprite_clip
; sprite 0: highlight frame
	dc.w	6                               ; width in words
	dc.w	90                              ; height in lines
	dc.l	frame_gfx                       ; graphic
	dc.l	frame_mask                      ; mask
; sprite 1: item 1
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	item_sprites                    ; graphic
	dc.l	item_mask                       ; mask
; sprite 2: item 2
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	item_sprites+$2d0               ; graphic
	dc.l	item_mask                       ; mask
; sprite 3: item 3
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	item_sprites+$5a0               ; graphic
	dc.l	item_mask                       ; mask
; sprite 4: item 4
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	item_sprites+$870               ; graphic
	dc.l	item_mask                       ; mask
; sprite 5: item 5
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	item_sprites+$b40               ; graphic
	dc.l	item_mask                       ; mask
; sprite 6: item 6
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	item_sprites+$e10               ; graphic
	dc.l	item_mask                       ; mask
; sprite 7: item 7
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	item_sprites+$10e0              ; graphic
	dc.l	item_mask                       ; mask
; sprite 8: item 8
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	item_sprites+$13b0              ; graphic
	dc.l	item_mask                       ; mask
; sprite 9: unused
	dc.w	4                               ; width in words
	dc.w	8                               ; height in lines
	dc.l	$0                              ; graphic
	dc.l	$0                              ; mask
; sprite 10: cursor
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	cursor_gfx                      ; graphic
	dc.l	cursor_mask                     ; mask
; sprite 11: wrong answer sweep
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	fail_sprite                     ; graphic
	dc.l	item_mask                       ; mask
; sprite 12: wrong answer picture
	dc.w	12                              ; width in words
	dc.w	104                             ; height in lines
	dc.l	fail_picture                    ; graphic
	dc.l	cursor_gfx                      ; mask
; sprite 13: right answer sweep
	dc.w	6                               ; width in words
	dc.w	30                              ; height in lines
	dc.l	success_sprite                  ; graphic
	dc.l	item_mask                       ; mask
; sprite 14: right answer picture
	dc.w	12                              ; width in words
	dc.w	42                              ; height in lines
	dc.l	success_picture                 ; graphic
	dc.l	cursor_gfx                      ; mask
cursor_bg_base:	; from: draw_cursor_masked
	dc.w	$0000,$0000,$0000
clip_width:	; from: sprite_clip
	dc.w	$0000
clip_height:	; from: sprite_clip
	dc.w	$0000
clip_size:	; from: sprite_clip
	dc.w	$0000,$0000
clip_gfx_ptr:	; from: draw_sprite, sprite_clip
	dcb.b	16,$00
clip_mask_ptr:	; from: draw_sprite, sprite_clip
	dc.w	$0000,$0000
clip_dest:	; from: draw_cursor_masked, draw_sprite, sprite_clip
	dc.w	$0000,$0000,$0000,$0000
unused_rts:
	rts


;----------------------------------------------------------------------
; Not called by anything: debug routines that print joy1_fire and cursor_dx in hex.
;----------------------------------------------------------------------
unused_debug_input:
	move.w	#$10b0,d1
	move.w	joy1_fire,d0
	bsr.w	unused_print_hex
	move.w	#$10b8,d1
	move.w	cursor_dx,d0
	bsr.w	unused_print_hex
	rts


;----------------------------------------------------------------------
; Not called by anything: debug, print a random number.
;----------------------------------------------------------------------
unused_debug_random:
	bsr.w	random
	move.w	random_value,d0
	movem.l	d0,-(sp)
	andi.w	#$7,d0
	asl.w	#2,d0
	asl.w	#8,d0
	ori.w	#$a0,d0
	move.w	d0,d1
	movem.l	(sp)+,d0
	bsr.w	unused_print_hex
	rts


;----------------------------------------------------------------------
; Not called by anything: print d0 in hex at position d1, all registers kept.
;----------------------------------------------------------------------
unused_debug_hex:
	movem.l	d0-d7/a0-a6,-(sp)
	bsr.w	unused_print_hex
	movem.l	(sp)+,d0-d7/a0-a6
	rts


;----------------------------------------------------------------------
; Not reached: cycle the background colour forever (debug).
;----------------------------------------------------------------------
unused_colour_cycle:
	andi.w	#$7,d0
	move.w	d0,$ff8240                      ; palette 0
	addq.w	#1,d0
	bra.s	unused_colour_cycle

debug_text:	; from: unused_print_hex
	dc.w	$0000
debug_digits:	; from: unused_print_hex
	dc.w	$3030,$3030,$ff00
debug_flag:	; from: unused_colour_cycle
	dc.w	$0000
unused_print_hex_clear:
	clr.w	debug_flag

;----------------------------------------------------------------------
; Not called by anything: convert d0 to four hex digits in debug_text and print it at d1.
;----------------------------------------------------------------------
unused_print_hex:	; from: unused_debug_input, unused_debug_random, unused_debug_hex
	move.l	#$70000,debug_screen
	lea	debug_digits,a6
	lea	hex_digits,a5
	move.w	d1,debug_text
	move.w	d0,d1
	lsr.w	#8,d0
	lsr.w	#4,d0
	move.b	$0(a5,d0.w),d2
	move.b	d2,(a6)+
	move.w	d1,d0
	lsr.w	#8,d0
	andi.w	#$f,d0
	move.b	$0(a5,d0.w),d2
	move.b	d2,(a6)+
	move.w	d1,d0
	lsr.w	#4,d0
	andi.w	#$f,d0
	move.b	$0(a5,d0.w),d2
	move.b	d2,(a6)+
	move.w	d1,d0
	andi.w	#$f,d0
	move.b	$0(a5,d0.w),d2
	move.b	d2,(a6)+
	lea	debug_text,a6
	bra.w	unused_print_text

	dc.w	$4e75
hex_digits:	; from: unused_print_hex
	dc.b	'0123456789ABCDEF'
debug_x:	; from: unused_print_text
	dc.b	$00
debug_col:	; from: unused_print_text
	dc.b	$00
debug_row:	; from: unused_print_text
	dc.w	$0000

;----------------------------------------------------------------------
; Not called by anything: a text printer of its own (col, row, string, $ff) on debug_screen.
;----------------------------------------------------------------------
unused_print_text:	; from: unused_print_hex
	move.b	(a6)+,debug_col
	move.b	(a6)+,debug_row
	moveq	#0,d0
	moveq	#0,d1
	move.b	debug_col,d0
	move.b	d0,d1
	andi.w	#$1,d1
	andi.w	#$fff8,d0
	asl.w	#2,d0
	add.w	d1,d0
	move.w	d0,debug_x
	moveq	#0,d0
	moveq	#0,d1
	move.b	debug_row,d1
	mulu.w	#$a0,d1
	add.w	debug_x,d1
debug_next_char:
	move.b	(a6)+,d0
	andi.w	#$ff,d0
	cmpi.b	#$ff,d0
	beq.w	debug_text_end
	andi.w	#$ff,d0
	cmpi.b	#$20,d0
	beq.w	debug_digit
	cmpi.b	#$2f,d0
	ble.w	debug_blank
	cmpi.b	#$39,d0
	ble.w	debug_digit
	cmpi.b	#$40,d0
	ble.w	debug_digit
	cmpi.b	#$5c,d0
	ble.w	debug_letter
	cmpi.b	#$60,d0
	ble.w	debug_blank
	cmpi.b	#$7a,d0
	bgt.w	debug_blank
	subi.b	#$60,d0
	bra.w	debug_draw_char

debug_digit:
	andi.w	#$3f,d0
	bra.w	debug_draw_char

debug_letter:
	andi.w	#$3f,d0
	addi.w	#$40,d0
	bra.w	debug_draw_char

debug_blank:
	move.b	#$0,d0
debug_draw_char:
	asl.w	#3,d0
	lea	$40000,a0
	adda.w	d0,a0
	andi.l	#$ffff,d1
	movea.l	debug_screen,a1
	adda.l	d1,a1
	move.w	#$ffff,debug_printed
	btst	#$0,d1
	bne.s	debug_char_odd
	moveq	#7,d7
debug_char_loop:
	move.b	(a0),(a1)
	move.b	(a0),$2(a1)
	move.b	(a0),$4(a1)
	move.b	(a0)+,$6(a1)
	lea	$a0(a1),a1
	dbra	d7,debug_char_loop
	addq.w	#1,d1
	bra.w	debug_next_char

debug_char_odd:
	moveq	#7,d7
debug_char_odd_loop:
	move.b	(a0),(a1)
	move.b	(a0),$2(a1)
	move.b	(a0),$4(a1)
	move.b	(a0)+,$6(a1)
	lea	$a0(a1),a1
	dbra	d7,debug_char_odd_loop
	andi.w	#$fffe,d1
	addi.l	#$8,debug_screen
	bra.w	debug_next_char

debug_text_end:
	move.l	#$78000,debug_screen
	clr.w	spare_flag
	rts


;----------------------------------------------------------------------
; Show the Batcave: title text, picture from $63800, the items, dissolve in.
;----------------------------------------------------------------------
draw_batcave:	; from: level_restart
	move.l	#$70000,screen_back
	lea	batcave_text,a0
	bsr.w	print_text_bold
	lea	batcave_palette,a0
	move.w	#$b4,d0
	bsr.w	wait_frames
	lea	$63800,a0
	lea	$78000,a1
	bsr.w	copy_screen
	bsr.w	draw_all_items
	move.l	#$70000,screen_front
	move.l	#$78000,screen_back
	bra.w	dissolve_in

batcave_text:	; from: draw_batcave
	dc.w	$460f
	dc.b	'THE BATCAVE',0
	dc.w	$ff56
success_text:	; from: is_selected
	dc.w	$1406
	dc.b	'SMILEX SUCCESSFULLY ANALYSED',0
	dc.b	$3c,$0a
	dc.b	'NOW THWART THE JOKERS',0
	dc.b	$50,$0e
	dc.b	'CARNIVAL PLOT.',0
	dc.w	$ff54
time_out_text:	; from: is_selected
	dc.w	$4611
	dc.b	'TIME OUT',0
	dc.b	$ff
game_over_text:	; from: is_selected
	dc.w	$4610
	dc.b	'GAME OVER',0
	dc.w	$ff45

;----------------------------------------------------------------------
; Unpack the Batcave picture: 32 byte palette, then run length coded words.
;----------------------------------------------------------------------
unpack_picture:	; from: level_start
	movem.l	d0-d1/d7/a0-a3,-(sp)
	move.b	(a0)+,d0
	cmpi.b	#$3,d0
	bcs.s	copy_palette
	adda.l	#$4,a0
copy_palette:
	moveq	#31,d0
palette_loop:
	move.b	(a0)+,(a2)+
	dbra	d0,palette_loop
	move.b	(a0)+,d7
	asl.w	#8,d7
	move.b	(a0)+,d7
	addq.l	#2,a0
	lea	$0(a0,d7.w),a2
	subq.w	#1,d7
	bmi.s	unpack_exit
	lea	$7d00(a1),a3
next_run:
	move.b	(a0)+,d0
	bmi.s	literal_short
	beq.s	repeat_long
	cmpi.b	#$1,d0
	bne.s	repeat_short
	move.b	(a0)+,d0
	asl.w	#8,d0
	move.b	(a0)+,d0
	subq.w	#2,d7
	bra.s	literal_run

literal_short:
	neg.b	d0
	ext.w	d0
literal_run:
	subq.w	#1,d0
literal_loop:
	move.b	(a2)+,(a1)+
	move.b	(a2)+,(a1)+
	bsr.s	next_picture_line
	dbra	d0,literal_loop
	bra.s	run_done

repeat_long:
	move.b	(a0)+,d0
	asl.w	#8,d0
	move.b	(a0)+,d0
	subq.w	#2,d7
	bra.s	repeat_run

repeat_short:
	ext.w	d0
repeat_run:
	subq.w	#1,d0
	move.b	(a2)+,d1
	asl.w	#8,d1
	move.b	(a2)+,d1
repeat_loop:
	move.w	d1,(a1)+
	bsr.s	next_picture_line
	dbra	d0,repeat_loop
run_done:
	dbra	d7,next_run
unpack_exit:
	movem.l	(sp)+,d0-d1/d7/a0-a3
	rts


next_picture_line:	; from: unpack_picture
	movem.l	d0,-(sp)
	lea	$9e(a1),a1
	move.l	a1,d0
	sub.l	a3,d0
	bcs.s	next_line_exit
	suba.w	#$7cf8,a1
	cmpi.w	#$98,d0
	bcs.s	next_line_exit
	suba.w	#$9e,a1
next_line_exit:
	movem.l	(sp)+,d0
	rts


;----------------------------------------------------------------------
; Copy a 32000 byte screen from a0 to a1.
;----------------------------------------------------------------------
copy_screen:	; from: reveal_answer, draw_batcave
	movem.l	d0/a0-a1,-(sp)
	move.w	#$11f,d0
copy_screen_loop:
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	dbra	d0,copy_screen_loop
	movem.l	(sp)+,d0/a0-a1
	rts

debug_screen:	; from: unused_print_hex, unused_print_text
	dc.w	$0000,$0000
line_bytes:	; from: sprite_clip
	dc.w	$0000
frame_flag:	; from: timerb_handler, wait_frames
	dc.w	$0000
spare_flag:	; from: init_puzzle, unused_print_text
	dc.w	$0000

; Buffer: the screen area under the frame, saved by save_bg_and_mask and put back by restore_cursor_bg.
cursor_background:	; from: restore_cursor_bg, save_bg_and_mask
	dc.w	$0000,$0000,$0301,$4e75,$0000,$0000,$0000,$0000
	dc.w	$0000,$0100,$0000,$008f,$7100,$0000,$0085,$5100
	dc.w	$0000,$00a5,$5500,$0000,$0085,$5500,$0000,$00a5
	dc.w	$5100,$0000,$00a5,$5500,$0000,$00a5,$5140,$0000
	dc.w	$0085,$5100,$0000,$0085,$0900,$0000,$008f,$5180
	dc.w	$0000,$008a,$5100,$0000,$008a,$51c0,$0000,$008a
	dc.w	$5100,$0000,$008a,$5120,$0000,$008a,$5140,$0000
	dc.w	$008a,$5110,$0000,$008a,$5008,$0000,$0006,$3980
	dc.w	$0000,$0192,$5480,$17d0,$012a,$a82a,$800a,$aad5
	dc.w	$a31f,$ea0b,$ffc5,$9600,$0000,$002a,$4cbf,$ffff
	dc.w	$fd12,$3980,$0000,$0186,$5000,$0002,$e00a,$5100
	dc.w	$0000,$108a,$5100,$0001,$848a,$5100,$0003,$488a
	dc.w	$5100,$0004,$208a,$5100,$0006,$268a,$5100,$c704
	dc.w	$208a,$5101,$2bc2,$428a,$5101,$fc71,$808a,$5103
	dc.w	$000c,$008a,$5104,$0003,$048a,$8901,$d5d8,$808e
	dc.w	$0107,$fdfd,$808f,$7101,$1555,$0085,$5105,$1555
	dc.w	$00a5,$5501,$d7dd,$0085,$5504,$5551,$00a5,$5104
	dc.w	$5551,$00a5,$5505,$dd51,$00a5,$5144,$0001,$0085
	dc.w	$5102,$0002,$0085,$0903,$fffe,$008f,$5181,$fffc
	dc.w	$008a,$5100,$0000,$008a,$51c0,$0000,$008a,$5100
	dc.w	$0000,$008a,$5120,$0000,$008a,$5140,$0000,$008a
	dc.w	$5110,$0000,$008a,$5008,$0000,$0006,$3980,$0000
	dc.w	$0192,$5480,$17d0,$012a,$282a,$800a,$aad5,$231f
	dc.w	$ea0b,$ffc5,$17ff,$ffff,$ffea,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$147f,$fa0a,$ff18,$0aff,$ffff
	dc.w	$fffd,$0000,$0000,$0000,$0000,$0000,$0000,$147f
	dc.w	$fa0a,$ff18,$0aff,$ffff,$fffd,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$147f,$fa0a,$ff18,$0aff,$ffff
	dc.w	$fffd,$0000,$0000,$0000,$0000,$0000,$0000,$147f
	dc.w	$fa0a,$ff18,$0aff,$ffff,$fffd,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$147f,$fa0a,$ff18,$0aff,$ffff
	dc.w	$fffd,$0000,$0000,$0000,$0000,$0000,$0000,$147f
	dc.w	$fa0a,$ff18,$0aff,$ffff,$fffd,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$147f,$fa0a,$ff18,$0011,$0a20
	dc.w	$0000,$0091,$0000,$0000,$0000,$0000,$0000,$ab00
	dc.w	$0000,$0ad1,$df00,$0000,$04f1,$db40,$0000,$00d1
	dc.w	$db00,$0000,$04f1,$db40,$0000,$00d1,$dba0,$0000
	dc.w	$00f1,$df40,$0000,$00f1,$dfe0,$0000,$00f1,$df50
	dc.w	$0000,$00f1,$fba0,$0000,$00cf,$dbd0,$0000,$00db
	dc.w	$dba0,$0000,$00db,$dbd0,$0000,$00db,$dba0,$0000
	dc.w	$00db,$dbb0,$0000,$00db,$db88,$0000,$00db,$db70
	dc.w	$0000,$00db,$de08,$0000,$007f,$ff00,$0000,$00f3
	dc.w	$c780,$0000,$01e3,$93ff,$d55f,$ffc9,$9f00,$15f4
	dc.w	$0039,$87ff,$ffff,$ffe3,$cfbf,$ffff,$fdf3,$ff00
	dc.w	$0000,$00ff,$da00,$0007,$e05b,$db00,$0000,$1cdb
	dc.w	$db00,$0001,$82db,$db00,$0002,$5adb,$db00,$0006
	dc.w	$2adb,$db00,$0004,$36db,$db00,$c004,$2adb,$db01
	dc.w	$a402,$56db,$db00,$0381,$8adb,$db00,$fff0,$14db
	dc.w	$db03,$fffc,$0edb,$fb06,$2a27,$04ce,$ab05,$dfdf
	dc.w	$0ad1,$df07,$1777,$04f1,$d345,$d7df,$00d1,$d305
	dc.w	$d5df,$04f1,$d344,$5553,$00d1,$d3a5,$dd51,$00f1
	dc.w	$d745,$dd53,$00f1,$d3e4,$0001,$00f1,$df53,$dfd2
	dc.w	$00f1,$fba1,$fffc,$00cf,$dbd0,$0000,$00db,$dba0
	dc.w	$0000,$00db,$dbd0,$0000,$00db,$dba0,$0000,$00db
	dc.w	$dbb0,$0000,$00db,$db88,$0000,$00db,$db70,$0000
	dc.w	$00db,$de08,$0000,$007f,$ff00,$0000,$00f3,$c780
	dc.w	$0000,$01e3,$93ff,$d55f,$ffc9,$9f00,$15f4,$0039
	dc.w	$87ff,$ffff,$ffe3,$ffff,$ffff,$ffff,$0000,$0000
	dc.w	$0000,$3380,$05f5,$001f,$18ff,$ffff,$fffc,$1fff
	dc.w	$ffff,$ffff,$0000,$0000,$0000,$3380,$05f5,$001f
	dc.w	$18ff,$ffff,$fffc,$1fff,$ffff,$ffff,$0000,$0000
	dc.w	$0000,$3380,$05f5,$001f,$18ff,$ffff,$fffc,$1fff
	dc.w	$ffff,$ffff,$0000,$0000,$0000,$3380,$05f5,$001f
	dc.w	$18ff,$ffff,$fffc,$1fff,$ffff,$ffff,$0000,$0000
	dc.w	$0000,$3380,$05f5,$001f,$18ff,$ffff,$fffc,$1fff
	dc.w	$ffff,$ffff,$0000,$0000,$0000,$3380,$05f5,$001f
	dc.w	$18ff,$ffff,$fffc,$1fff,$ffff,$ffff,$0000,$0000
	dc.w	$0000,$3380,$05f5,$001f,$00bb,$1b60,$0000,$01bb
	dc.w	$ffff,$ffff,$0000,$0000,$0000,$7000,$0000,$000e
	dc.w	$2000,$0000,$000e,$2400,$0000,$002e,$2400,$0000
	dc.w	$002e,$2400,$0000,$002e,$2400,$0000,$000e,$2000
	dc.w	$0000,$000e,$2000,$0000,$000e,$2000,$0000,$000e
	dc.w	$0040,$0000,$0010,$2000,$0000,$0004,$2040,$0000
	dc.w	$0004,$2000,$0000,$0004,$2040,$0000,$0004,$2040
	dc.w	$0000,$0004,$2060,$0000,$0004,$2020,$0000,$0004
	dc.w	$2110,$0000,$0080,$0080,$0000,$010c,$387f,$ffff
	dc.w	$fe1c,$7c00,$2aa0,$003e,$7cff,$ffff,$fffe,$7800
	dc.w	$0000,$001c,$3040,$0000,$020c,$0080,$0000,$0100
	dc.w	$2100,$0000,$1084,$2000,$0000,$0804,$2000,$0000
	dc.w	$0c04,$2000,$0001,$0404,$2000,$0002,$0404,$2000
	dc.w	$0002,$0004,$2000,$0700,$4404,$2000,$8fc0,$8004
	dc.w	$2001,$fff0,$0404,$2003,$fffc,$0004,$2007,$ffff
	dc.w	$0004,$0007,$ffff,$8011,$7002,$2222,$800e,$2006
	dc.w	$eaaa,$000e,$2402,$eaaa,$002e,$2406,$2a22,$002e
	dc.w	$2403,$aaae,$002e,$2403,$aaae,$000e,$2002,$22ae
	dc.w	$000e,$2003,$fffe,$000e,$2001,$fffc,$000e,$0040
	dc.w	$0000,$0010,$2000,$0000,$0004,$2040,$0000,$0004
	dc.w	$2000,$0000,$0004,$2040,$0000,$0004,$2040,$0000
	dc.w	$0004,$2060,$0000,$0004,$2020,$0000,$0004,$2110
	dc.w	$0000,$0080,$0080,$0000,$010c,$387f,$ffff,$fe1c
	dc.w	$7c00,$2aa0,$003e,$7cff,$ffff,$fffe,$7800,$0000
	dc.w	$001c,$0000,$0000,$0000,$0000,$0000,$0000,$0fff
	dc.w	$ffff,$ffe7,$0700,$0000,$0003,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0fff,$ffff,$ffe7,$0700,$0000
	dc.w	$0003,$0000,$0000,$0000,$0000,$0000,$0000,$0fff
	dc.w	$ffff,$ffe7,$0700,$0000,$0003,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0fff,$ffff,$ffe7,$0700,$0000
	dc.w	$0003,$0000,$0000,$0000,$0000,$0000,$0000,$0fff
	dc.w	$ffff,$ffe7,$0700,$0000,$0003,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0fff,$ffff,$ffe7,$0700,$0000
	dc.w	$0003,$0000,$0000,$0000,$0000,$0000,$0000,$0fff
	dc.w	$ffff,$ffe7,$0040,$0400,$0000,$0040
	dcb.b	233,$00
	dc.b	$05,$dd,$dd,$00,$00,$00,$01,$fd,$dd,$00,$00,$00,$07,$3d,$55,$00
	dc.b	$00,$00,$03,$fd,$fd,$00,$00,$00,$07,$ff,$fd,$00,$00,$00,$06,$77
	dc.b	$ff,$00,$00,$00,$07,$ff,$fd,$00,$00,$00,$07,$ff,$ff,$00,$00,$00
	dc.b	$02,$20,$2e,$00,$00,$00,$03,$ff,$fe,$00,$00,$00,$01,$ff,$fc
	dcb.b	8316,$00

; Sprite 10, the cursor (mostly empty, the shape is in cursor_mask); also the mask of sprites 12 and 14.
cursor_gfx:	; from: is_selected
	incbin	"data/l3_curs.bin"		; $640 bytes of data
item_mask:
	incbin	"data/l3_itemm.bin"		; $c0 bytes of data
cursor_mask:
	incbin	"data/l3_cursm.bin"		; $c0 bytes of data
batcave_palette:	; from: draw_batcave
	dc.w	$0000,$0130,$0111,$0333,$0555,$0777,$0bbb,$0008
	dc.w	$0a04,$0703,$0000,$0b50,$0f70,$0250,$0f00,$0005
	ifeq	CONFIG-RETAIL_2DISK
	dc.b	$0f
file_padding:
	dcb.b	17,$00
	endc
	ifeq	CONFIG-RETAIL_1DISK
	dc.b	$af
	endc
	ifeq	CONFIG-BUDGET_1DISK
	dc.b	$0f
file_padding:
	dcb.b	31,$00
	endc

	end
