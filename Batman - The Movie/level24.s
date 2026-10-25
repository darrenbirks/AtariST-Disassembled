; Batman The Movie (Ocean, 1989) - level 2/4 code, all versions
; Module level24: level24.bin, loaded at $2200, in scenes level2, level4.
; Size: RETAIL_2DISK 33788 bytes, RETAIL_1DISK 33788 bytes, BUDGET_1DISK 33822 bytes.
;
; Pseudo 3D driving engine shared by level 2 (entry $2200, Batmobile
; through the streets of Gotham) and level 4 (entry $2202, Batwing over the
; carnival; is_batwing = 1).  The course is a stream of segments read by
; next_segment from five byte streams (curve, hill, left and right roadside,
; events); the road edges are projected by compute_road_edges and drawn by
; draw_road, scenery by draw_roadside and sprites by the sorted object list
; (update_objects / draw_objects).  Level 2 ends when distance_left reaches 0
; (grapple round corners with fire); level 4 when all balloons are cut.
; Graphics are unpacked at level start by unpack_gfx from the lists at
; gfx_list_common etc. (level24_gfx/level2_gfx/level4_gfx data), with extra buffers at
; $80000 when 1 MB is present (detect_1mb).
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
panel_lose_life	equ	$6b862		; panel.s
panel_lose_energy	equ	$6b870		; panel.s
panel_flags	equ	$6b874		; panel.s
game_flags	equ	$6b875		; panel.s
panel_score	equ	$6b87c		; panel.s
energy_steps_left	equ	$6b88e		; panel.s
panel_copy	equ	$6c874		; panel.s
snd_reset	equ	$6d400		; sound.s
snd_stop	equ	$6d404		; sound.s
snd_stop_music	equ	$6d408		; sound.s
snd_play_tune	equ	$6d410		; sound.s
snd_play_sfx	equ	$6d414		; sound.s
snd_tick	equ	$6d418		; sound.s
snd_sfx_playing	equ	$6d421		; sound.s

; addresses inside instructions (self modifying code)
strip_curve_left	equ	$6097		; roadside_wrap+17

	opt	o-
	org	$2200


;----------------------------------------------------------------------
; Level entry: $2200 level 2 (Batmobile), $2202 level 4 (Batwing, is_batwing = 1).
;----------------------------------------------------------------------
level_start:
	bra.s	level2_start

level4_start:
	move.w	#$1,is_batwing
	bra.s	level_common_start

level2_start:
	move.w	#$0,is_batwing
level_common_start:
	move.w	#$2700,sr
	pea	hw_init
	jmp	snd_reset


;----------------------------------------------------------------------
; Hardware init: black palette, stack $70000, VBL and MFP vectors, IKBD, timer C at 200 Hz.
;----------------------------------------------------------------------
hw_init:	; from: level_start
	moveq	#0,d0
	move.b	d0,$fffa07                      ; MFP IERA
	move.b	d0,$fffa09                      ; MFP IERB
	lea	$ff8240,a0                      ; palette 0
	moveq	#15,d1
clear_palette_loop:
	move.w	d0,(a0)+
	dbra	d1,clear_palette_loop
	lea	$70000,sp
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
	bsr.w	clear_screens
	bsr.w	flip_screens
	bra.w	start_level

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
palette_splits:	; from: vbl_handler
	dc.w	$0000,$0001,$0444,$0777,$0222,$0400,$0600,$0666
	dc.w	$0555,$0333,$0000,$0630,$0751,$0770,$0774,$0222
	dc.w	$0003,$0002,$0000,$0003,$0003,$0000,$0003,$0004
	dc.w	$0000,$0003,$0005,$0000,$0003,$0106,$0000,$0003
	dc.w	$0207,$0000,$0003,$0306,$0000,$0003,$0405,$0000
	dc.w	$0003,$0504,$0000,$0003,$0613,$0000,$0003,$0722
	dc.w	$0000,$0003,$0731,$0000,$0003,$0740,$0000,$0003
	dc.w	$0750,$0000,$0003,$0760,$0000
	dc.b	$00
split_line_a:	; from: flip_screens, play_sfx_restore
	dc.b	$14,$01,$11,$00,$00,$00
split_line_b:	; from: flip_screens, play_sfx_restore
	dc.b	$57,$00,$00,$00,$01
current_palette:	; from: fade_in, fade_out
	dcb.b	34,$00
target_palette:	; from: fade_in
	dc.w	$0000,$0030,$0777,$0004,$0511,$0222,$0431,$0333
	dc.w	$0444,$0555,$0520,$0630,$0740,$0750,$0760,$0777

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


;----------------------------------------------------------------------
; Timer C (200 Hz): keyboard, then the sound driver tick and, when not paused, the panel tick.
;----------------------------------------------------------------------
timerc_handler:	; from: mfp_vectors
	bclr	#$5,$fffa11                     ; MFP ISRB
	move.w	#$2300,sr
	movem.l	d0-d7/a0-a6,-(sp)
	bsr.w	keyboard_decode
	pea	timerc_after_sound
	tst.w	sound_paused
	bne.s	timerc_sound
	pea	panel_tick
timerc_sound:
	jmp	snd_tick


timerc_after_sound:	; from: timerc_handler
	bsr.w	engine_noise
	movem.l	(sp)+,d0-d7/a0-a6
	rte


;----------------------------------------------------------------------
; Engine noise on PSG channel A, pitched by speed (Batwing: a noise channel, Batmobile: tone + noise);
; skid_noise plays while a skid effect is requested.
;----------------------------------------------------------------------
engine_noise:	; from: timerc_after_sound
	btst	#$0,game_flags
	beq.w	noise_exit
	tst.w	sound_paused
	beq.s	noise_select
	moveq	#-1,d3
	moveq	#-1,d4
	bra.w	noise_exit

	dc.w	$6000,$00c6
noise_select:
	tst.w	is_batwing
	beq.s	batmobile_noise
	tst.w	sfx_active
	bne.w	noise_exit
	move.w	speed,d0
	lsr.w	#4,d0
	neg.w	d0
	addi.w	#$1f,d0
	cmpi.b	#$5,d0
	bcc.s	batwing_noise
	moveq	#5,d0
batwing_noise:
	moveq	#10,d2
	moveq	#54,d3
	moveq	#0,d4
	move.b	#$6,$ff8800                     ; PSG register select
	move.b	d0,$ff8802                      ; PSG write data
	addi.w	#$1e,d0
	bra.w	write_psg

skid_noise:
	bsr.w	random
	andi.w	#$7,d0
	addi.w	#$8c,d0
	moveq	#12,d2
	moveq	#62,d3
	moveq	#0,d4
	bra.s	write_psg

batmobile_noise:
	tst.w	sfx_requested
	bne.s	skid_noise
	tst.w	sfx_active
	bne.w	noise_exit
	move.w	speed,d0
	move.w	vehicle+60,d1
	cmpi.w	#$2,d1
	bcs.s	engine_period
	move.w	speed_saved,d0
engine_period:
	lsl.w	#2,d0
	neg.w	d0
	addi.w	#$a28,d0
	moveq	#12,d2
	moveq	#60,d3
	moveq	#0,d4
	move.w	d0,d1
	addi.w	#$190,d1
	move.b	#$2,$ff8800                     ; PSG register select
	move.b	d1,$ff8802                      ; PSG write data
	rol.w	#8,d1
	move.b	#$3,$ff8800                     ; PSG register select
	move.b	d1,$ff8802                      ; PSG write data
	move.b	#$9,$ff8800                     ; PSG register select
	move.b	#$d,$ff8802                     ; PSG write data
write_psg:
	move.b	#$0,$ff8800                     ; PSG register select
	move.b	d0,$ff8802                      ; PSG write data
	rol.w	#8,d0
	move.b	#$1,$ff8800                     ; PSG register select
	move.b	d0,$ff8802                      ; PSG write data
	move.b	#$8,$ff8800                     ; PSG register select
	move.b	d2,$ff8802                      ; PSG write data
	move.b	#$7,$ff8800                     ; PSG register select
	move.b	$ff8800,d0                      ; PSG register select
	and.b	d3,d0
	or.b	d4,d0
	move.b	d0,$ff8802                      ; PSG write data
noise_exit:
	rts


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
; Timer B: next palette split from split_ptr (colour 1, optional full palette, next line count).
;----------------------------------------------------------------------
timerb_handler:	; from: mfp_vectors
	move.l	a0,-(sp)
	move.b	#$0,$fffa1b                     ; MFP TBCR
	movea.l	split_ptr,a0
	move.w	(a0)+,$ff8242
	movem.l	d0-d3,-(sp)
	tst.w	(a0)+
	beq.s	split_next_line
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8240                   ; palette 0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8250
split_next_line:
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
; VBL: restart the palette split list, count frames and sample the joystick into joy_state.
;----------------------------------------------------------------------
vbl_handler:	; from: hw_init
	movem.l	d0-d7/a0-a6,-(sp)
	move.b	#$0,$fffa1b                     ; MFP TBCR
	lea	palette_splits(pc),a0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8240                   ; palette 0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8250
	move.w	(a0)+,d0
	move.l	a0,split_ptr
	move.b	d0,$fffa21                      ; MFP TBDR
	move.b	#$8,$fffa1b                     ; MFP TBCR
	addq.w	#1,vbl_count
	move.w	joy1_fire,joy_state
	movem.l	(sp)+,d0-d7/a0-a6
	rte


ikbd_send:	; from: hw_init, ikbd_joystick_mode
	btst	#$1,$fffc00                     ; keyboard ACIA control
	beq.s	ikbd_send
	move.b	(a0)+,$fffc02                   ; keyboard ACIA data
	dbra	d0,ikbd_send
	rts


;----------------------------------------------------------------------
; Decode IKBD packets: keys to key_queue / key_bitmap, joystick to joy0/joy1, mouse to mouse_x/y.
;----------------------------------------------------------------------
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

key_queue:	; from: keyboard_decode, get_key
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
	dc.b	$00
joy1_fire:	; from: vbl_handler, keyboard_decode, grapple_control, batwing_control
	dc.b	$00
joy1_dirs:	; from: keyboard_decode
	dc.b	$00
joy_state:	; from: vbl_handler, grapple_control, vehicle_control
	dc.w	$0000,$0000,$0000
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


get_key:	; from: keyboard_decode, hud_update, restart_level
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


ikbd_joystick_mode:	; from: level_setup
	movem.l	d0/a0,-(sp)
	lea	ikbd_joy_cmds(pc),a0
	moveq	#1,d0
	bsr.w	ikbd_send
	movem.l	(sp)+,d0/a0
	rts

ikbd_joy_cmds:	; from: ikbd_joystick_mode
	dc.w	$1214
vbl_count:	; from: vbl_handler, flip_screens, time_up_text, lose_life, game_over_text, level_complete_text, ...
	dc.w	$0000
flip_wait:	; from: flip_screens
	dc.w	$0002
screen_front:	; from: flip_screens, copy_panel_strips, dissolve_in
	dc.w	$0007,$0000
screen_back:	; from: copy_panel_strips, clear_back_screen, print_text, draw_objects, draw_sprite_clipped, draw_grapple_line, ...
	dc.w	$0007,$8000

;----------------------------------------------------------------------
; Wait flip_wait frames, swap screen_front / screen_back, set the video base and the two split lines
; from horizon_y.
;----------------------------------------------------------------------
flip_screens:	; from: hw_init, main_loop
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
	move.w	horizon_y,d1
	not.b	d1
	addi.b	#$98,d1
	subi.b	#$2d,d1
	move.b	d1,split_line_a
	neg.b	d1
	addi.b	#$6b,d1
	move.b	d1,split_line_b
	clr.w	vbl_count
	rts


clear_screens:	; from: hw_init, hud_count
	lea	$70000,a0
	lea	$78000,a1
	move.w	#$17bf,d7
clear_screens_loop:
	clr.l	(a0)+
	clr.l	(a1)+
	dbra	d7,clear_screens_loop
	rts

	rts


;----------------------------------------------------------------------
; Probe $88888 (bus error on a 512K machine) to decide where the extra graphics go; Z set = 1 MB.
;----------------------------------------------------------------------
detect_1mb:	; from: level_setup
	move.l	#bus_error_handler,$8           ; bus error vector
	move.l	sp,saved_sp
	lea	$88888,a0
	move.w	#$ff,d7
memory_test_loop:
	move.b	d7,(a0)
	cmp.b	(a0)+,d7
	bne.s	no_1mb
	dbra	d7,memory_test_loop
	not.w	d7
	rts


bus_error_handler:	; from: detect_1mb
	movea.l	saved_sp,sp
no_1mb:	; from: detect_1mb
	move.w	#$777,$ff8240                   ; palette 0
	moveq	#-1,d0
	rts

start_level:	; from: hw_init, restart_level
	pea	level_setup
	pea	panel_copy
	jmp	panel_init_energy


;----------------------------------------------------------------------
; Level setup: seed the random generator from the score, print the level name,
; build the road tables, unpack the graphics and set the start values.
;----------------------------------------------------------------------
level_setup:	; from: bus_error_handler
	lea	panel_score,a0
	lea	random_seed,a1
	move.l	(a0)+,(a1)+
	move.w	(a0),(a1)
	bsr.w	ikbd_joystick_mode
	tst.w	is_batwing
	bne.w	level4_setup
	bsr.w	fade_in
	lea	level2_name_text,a0
	bsr.w	print_text_bold
	bsr.w	dissolve_in
	bsr.w	build_road_batmobile
	bsr.w	build_shift_masks
	lea	gfx_list_common,a0
	lea	$30690,a6                       ; level2_gfx +$20258
	lea	scenery_columns_mid,a4
	bsr.w	unpack_gfx
	bsr.w	detect_1mb
	beq.s	level2_1mb
	lea	gfx_list_level2_512k,a0
	bra.s	level2_unpack_rest

level2_1mb:
	lea	gfx_list_level2_1mb,a0
	lea	$80000,a6
level2_unpack_rest:
	lea	scenery_map,a4
	bsr.w	unpack_gfx
	move.w	#$3e7,distance_left
level2_restart:	; from: lose_life
	move.w	#$230,d0
	move.w	#$1f4,d1
	cmp.w	distance_left,d1
	bcc.s	level2_set_distance
	move.w	#$500,d0
	move.w	#$3e7,d1
level2_set_distance:
	move.w	d1,distance_left
	bsr.w	reset_level_vars
	lea	vehicle,a0
	move.w	#$91,$10(a0)
	move.w	#$bc,$30(a0)
	move.w	#$84,$2e(a0)
	move.w	#$14,$2a(a0)
	move.w	#$fffc,$2c(a0)
	move.w	#$4,traffic_timer
	move.w	#$8,traffic_rate
	move.w	#$2,turn_ahead
	move.l	#course2_list,course_ptr
	bra.w	start_music

level4_setup:
	bsr.w	fade_in
	lea	level4_name_text,a0
	bsr.w	print_text_bold
	bsr.w	dissolve_in
	bsr.w	build_shift_masks
	bsr.w	build_road_batwing
	lea	gfx_list_common,a0
	lea	$37448,a6                       ; level4_gfx +$27010
	lea	scenery_columns_mid,a4
	bsr.w	unpack_gfx
	bsr.w	detect_1mb
	beq.s	level4_1mb
	lea	gfx_list_level4_512k,a0
	bra.s	level4_unpack_rest

level4_1mb:
	lea	gfx_list_level4_1mb,a0
	lea	$80000,a6
level4_unpack_rest:
	lea	scenery_map,a4
	bsr.w	unpack_gfx
	move.w	#$64,balloons_left
level4_restart:	; from: lose_life
	move.w	#$32,d1
	move.w	#$150,d0
	cmp.w	balloons_left,d1
	bcc.s	level4_set_balloons
	move.w	#$64,d1
	move.w	#$320,d0
level4_set_balloons:
	move.w	d1,balloons_left
	bsr.w	reset_level_vars
	lea	vehicle,a0
	move.w	#$64,$10(a0)
	move.w	#$78,speed
	move.w	#$c6,$30(a0)
	move.w	#$70,$2e(a0)
	move.w	#$1,$2a(a0)
	move.w	#$ffec,$2c(a0)
	move.l	#course4_list,course_ptr
	bra.w	start_music


;----------------------------------------------------------------------
; Clear the level variables from saved_sp on, restart_mode = 2, then set the time (d0, BCD minutes
; and seconds from the restart entry) and the energy bar.
;----------------------------------------------------------------------
reset_level_vars:	; from: level_setup
	lea	saved_sp,a0
	move.w	#$1bb,d7
clear_vars_loop:
	clr.w	(a0)+
	dbra	d7,clear_vars_loop
	move.w	#$2,restart_mode
	pea	panel_init_energy
	jmp	panel_set_time

start_music:	; from: level_setup
	bsr.w	init_course
	move.w	#$0,distance_tick
	btst	#$0,game_flags
	bne.s	main_loop
	moveq	#5,d0
	add.w	is_batwing,d0
	pea	main_loop
	jmp	snd_play_tune


;----------------------------------------------------------------------
; Main loop, once per frame: course, roadside, road, scenery, objects, vehicle, HUD, flip.
;----------------------------------------------------------------------
main_loop:	; from: reset_level_vars, grapple_control
	bsr.w	advance_course
	bsr.w	update_roadside_strips
	bsr.w	compute_hill_heights
	bsr.w	compute_road_edges
	bsr.w	interpolate_road_edges
	bsr.w	build_roadside_positions
	bsr.w	roadside_collision
	tst.w	is_batwing
	bne.s	main_batwing_spawn
	bsr.w	spawn_traffic
	bsr.w	spawn_roadblock
	bra.s	main_update

main_batwing_spawn:
	bsr.w	spawn_balloons
main_update:
	bsr.w	update_objects
	bsr.w	vehicle_control
	bsr.w	draw_road
	bsr.w	draw_roadside
	bsr.w	hud_update
	bsr.w	engine_sfx
	bsr.w	check_end
	pea	main_loop
	move.w	restart_mode,d0
	bne.w	after_restart
	bra.w	flip_screens


;----------------------------------------------------------------------
; End conditions: level_end_state set, or panel_flags (time up, game over, life lost) -> end_of_level.
;----------------------------------------------------------------------
check_end:	; from: main_loop
	tst.w	level_end_state
	bne.s	end_of_level
	move.b	panel_flags,d0
	andi.w	#$7,d0
	beq.s	check_end_exit
	tst.w	is_batwing
	beq.s	end_of_level
	tst.w	end_delay
	bne.s	check_end_exit
	move.w	#$19,end_delay
check_end_exit:
	rts

end_of_level:
	move.w	#$1,sound_paused
	pea	time_up
	jmp	snd_stop


time_up:	; from: check_end
	pea	time_up_text
	moveq	#10,d0
	jmp	snd_play_tune


time_up_text:	; from: time_up
	cmpi.w	#$1,level_end_state
	beq.s	time_up_lose_life
	btst	#$0,panel_flags
	beq.s	lose_life
	bsr.w	clear_back_screen
	lea	time_up_msg,a0
	bsr.w	print_text_bold
	bsr.w	dissolve_in
	clr.w	vbl_count
time_up_wait:
	cmpi.w	#$32,vbl_count
	bcs.s	time_up_wait
time_up_lose_life:
	pea	lose_life
	jmp	panel_lose_life


;----------------------------------------------------------------------
; Life lost: unless game over, reprint the level name and restart at level2_restart / level4_restart.
;----------------------------------------------------------------------
lose_life:	; from: time_up_text
	btst	#$1,panel_flags
	bne.w	game_over
	bsr.w	clear_back_screen
	lea	level2_name_text,a0
	lea	level2_restart,a1
	tst.w	is_batwing
	beq.s	restart_text
	lea	level4_name_text,a0
	lea	level4_restart,a1
restart_text:
	move.l	a1,(sp)
	bsr.w	print_text_bold
	bsr.w	dissolve_in
	clr.w	vbl_count
restart_wait:
	cmpi.w	#$32,vbl_count
	bcs.s	restart_wait
	move.w	#$0,level_end_state
	jmp	panel_init_energy

game_over:	; from: restart_level
	move.w	#$1,sound_paused
	pea	game_over_tune
	jmp	snd_stop


game_over_tune:	; from: lose_life
	pea	game_over_text
	moveq	#8,d0
	jmp	snd_play_tune


game_over_text:	; from: game_over_tune
	bsr.w	clear_back_screen
	lea	game_over_msg,a0
	bsr.w	print_text_bold
	bsr.w	dissolve_in
	clr.w	vbl_count
game_over_wait:
	cmpi.w	#$5a,vbl_count
	bcs.s	game_over_wait
	bsr.w	clear_back_screen
	bsr.w	dissolve_in
	bsr.w	fade_out
	jmp	$200                            ; loader section 0 (jmp $1000)

level_complete:	; from: hud_count, restart_level
	move.w	#$1,sound_paused
	pea	level_complete_text
	moveq	#9,d0
	jmp	snd_play_tune


level_complete_text:	; from: game_over_text
	bsr.w	clear_back_screen
	lea	level2_done_text,a0
	tst.w	is_batwing
	beq.s	complete_print
	lea	level4_done_text,a0
complete_print:
	bsr.w	print_text_bold
	bsr.w	dissolve_in
	clr.w	vbl_count
complete_wait:
	cmpi.w	#$69,vbl_count
	bcs.s	complete_wait
	bsr.w	clear_back_screen
	bsr.w	dissolve_in
	bsr.w	fade_out
	tst.w	is_batwing
	beq.s	complete_to_level3
	jmp	$214                            ; loader section 5 (jmp $1014)

complete_to_level3:
	jmp	$20c                            ; loader section 3 (jmp $100c)


;----------------------------------------------------------------------
; Start or stop the skid / wing effect depending on the vehicle state and the sound driver.
;----------------------------------------------------------------------
engine_sfx:	; from: main_loop
	btst	#$0,game_flags
	beq.w	engine_sfx_exit
	lea	vehicle,a6
	tst.w	is_batwing
	beq.s	batmobile_skid_sfx
	tst.w	$28(a6)
	beq.s	stop_engine_sfx
	tst.w	sfx_requested
	bne.s	engine_sfx_done
	move.w	#$1,sfx_requested
	move.w	#$1,sfx_active
	moveq	#18,d0
	jmp	snd_play_sfx

batmobile_skid_sfx:
	tst.w	$32(a6)
	beq.s	stop_engine_sfx
	tst.w	sfx_requested
	bne.s	engine_sfx_done
	tst.w	vehicle+24
	bne.s	stop_engine_sfx
	move.w	vehicle+60,d0
	cmpi.w	#$2,d0
	bcc.s	engine_sfx_done
	move.w	#$1,sfx_requested
	move.w	#$1,sfx_active
	rts

stop_engine_sfx:
	tst.w	sfx_requested
	beq.s	engine_sfx_done
	moveq	#0,d0
	pea	engine_sfx_done
	jmp	snd_play_sfx


engine_sfx_done:	; from: engine_sfx
	tst.b	snd_sfx_playing
	bne.s	engine_sfx_exit
	clr.w	sfx_requested
	clr.w	sfx_active
engine_sfx_exit:	; from: engine_sfx
	rts


;----------------------------------------------------------------------
; Play effect d0 (if effects are on) and note that an effect is active.
;----------------------------------------------------------------------
play_sfx:	; from: balloon_collide, balloon_cut, traffic_collide, advance_object, roadside_collision, grapple_control, ...
	btst	#$0,game_flags
	beq.s	play_sfx_exit
	movem.l	d1-d7/a0-a6,-(sp)
	move.w	#$1,sfx_active
	move.w	#$0,sfx_requested
	pea	play_sfx_restore
	jmp	snd_play_sfx


play_sfx_restore:	; from: play_sfx
	movem.l	(sp)+,d1-d7/a0-a6
play_sfx_exit:	; from: play_sfx
	rts

after_restart:	; from: main_loop
	move.w	#$0,restart_mode
	move.w	#$0,sound_paused
	move.w	horizon_y,d1
	not.b	d1
	addi.b	#$98,d1
	subi.b	#$2d,d1
	move.b	d1,split_line_a
	neg.b	d1
	addi.b	#$6b,d1
	move.b	d1,split_line_b
	cmpi.w	#$2,d0
	beq.w	dissolve_in

;----------------------------------------------------------------------
; Copy the screen in 8 pixel strips from back to front over a few frames (after the grapple swing).
;----------------------------------------------------------------------
copy_panel_strips:	; from: grapple_control
	moveq	#0,d0
	move.w	#$98,d1
next_strip:
	movea.l	screen_front,a0
	movea.l	screen_back,a1
	lea	$0(a0,d1.w),a2
	lea	$a0(a2),a2
	lea	$0(a1,d1.w),a3
	lea	$a0(a3),a3
	lea	$0(a0,d0.w),a0
	lea	$0(a1,d0.w),a1
	moveq	#75,d7
copy_strip_loop:
	move.l	(a1),(a0)
	move.l	$4(a1),$4(a0)
	move.l	(a3),(a2)
	move.l	$4(a3),$4(a2)
	lea	$140(a0),a0
	lea	$140(a1),a1
	lea	$140(a2),a2
	lea	$140(a3),a3
	dbra	d7,copy_strip_loop
	addq.w	#8,d0
	subq.w	#8,d1
	bmi.s	copy_strips_exit
strip_wait_vbl:
	tst.w	vbl_count
	beq.s	strip_wait_vbl
	move.w	#$0,vbl_count
	bra.s	next_strip

copy_strips_exit:
	rts


clear_back_screen:	; from: time_up_text, lose_life, game_over_text, level_complete_text, grapple_control
	movea.l	screen_back,a0
	move.w	#$17bf,d7
clear_back_loop:
	clr.l	(a0)+
	dbra	d7,clear_back_loop
	rts


dissolve_in:	; from: level_setup, time_up_text, lose_life, game_over_text, level_complete_text, play_sfx_restore, ...
	movem.l	screen_front.w,a0-a1
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


fade_in:	; from: level_setup
	moveq	#15,d7
fade_in_pass:
	lea	current_palette.w,a0
	lea	target_palette.w,a1
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


fade_out:	; from: game_over_text, level_complete_text
	moveq	#15,d7
fade_out_pass:
	lea	current_palette.w,a0
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

level2_name_text:	; from: level_setup, lose_life
	dc.w	$4407
	dc.b	'THE STREETS OF GOTHAM CITY',0
	dc.b	$ff
level2_done_text:	; from: level_complete_text
	dc.w	$3a07
	dc.b	'YOU HAVE ESCAPED THE JOKER',0
	dc.b	$4e,$06
	dc.b	'BUT WHAT SECRETS LIE AHEAD...',0
	dc.b	$ff
level4_name_text:	; from: level_setup, lose_life
	dc.w	$440a
	dc.b	'GOTHAM CITY CARNIVAL',0
	dc.b	$ff
level4_done_text:	; from: level_complete_text
	dc.w	$3a08
	dc.b	'THE CITY IS SAFE BUT THE',0
	dc.b	$4e,$08
	dc.b	'JOKER IS STILL AT LARGE.',0
	dc.w	$ff00
time_up_msg:	; from: time_up_text
	dc.w	$4410
	dc.b	'TIME UP',0
	dc.w	$ff00
game_over_msg:	; from: game_over_text
	dc.w	$440f
	dc.b	'GAME OVER',0
	dc.w	$ff00
speed_text:	; from: hud_update
	dc.w	$0201
	dc.b	'SPEED',0
	dc.w	$0c02
speed_digits:	; from: hud_update
	dc.w	$3030,$3000,$ff00
distance_text:	; from: restart_level
	dc.w	$021f
	dc.b	'DISTANCE',0
	dc.b	$0c,$21
distance_digits:	; from: restart_level
	dc.b	$39,$39,$2e,$39,$00,$ff,$00
balloons_text:	; from: hud_count
	dc.w	$021f
	dc.b	'BALLOONS',0
	dc.b	$0c,$22
balloons_digits:	; from: hud_count
	dc.b	$30,$30,$30,$00,$ff

;----------------------------------------------------------------------
; HUD and keys: F1 pause, F2 music, F8 greeting (cheat), F9 restart (cheat), F10 skip (cheat).
;----------------------------------------------------------------------
hud_update:	; from: main_loop
	move.w	speed,d0
	tst.w	vehicle+60
	beq.s	hud_speed
	cmpi.w	#$2,vehicle+60
	bcs.s	hud_speed
	move.w	speed_saved,d0
hud_speed:
	lsr.w	#1,d0
	lea	speed_digits,a0
	bsr.w	format_decimal
	lea	speed_text,a0
	bsr.w	print_text
	move.w	energy_steps_left,d0
	cmpi.w	#$12,d0
	bcc.s	hud_keys
	move.w	d0,damage_level
hud_keys:
	bsr.w	get_key
	beq.s	hud_count
	cmpi.w	#$81,d0
	beq.w	pause
	cmpi.w	#$82,d0
	beq.w	toggle_music
	cmpi.w	#$8a,d0
	beq.s	key_f10
	cmpi.w	#$89,d0
	beq.s	key_f9
	cmpi.w	#$88,d0
	beq.s	key_f8

hud_count:	; from: hud_update, restart_level
	tst.w	is_batwing
	beq.w	update_distance
	move.w	balloons_left,d0
	beq.w	level_complete
	lea	balloons_digits,a0
	bsr.w	format_decimal
	lea	balloons_text,a0
	bra.w	print_text

key_f10:	; from: hud_update
	btst	#$7,game_flags
	beq.s	hud_count
	bra.w	level_complete

key_f9:	; from: hud_update
	btst	#$7,game_flags
	beq.s	hud_count
	move.w	#$3e7,distance_left
	move.w	#$64,balloons_left
	bsr.w	clear_screens
	pea	restart_level
	jmp	snd_stop


restart_level:	; from: hud_count
	bra.w	start_level

key_f8:	; from: hud_update
	btst	#$7,game_flags
	beq.s	hud_count
	lea	greeting_text,a0
	bsr.w	print_text
	bsr.w	dissolve_in
	bra.w	pause

greeting_text:	; from: restart_level
	dc.w	$2002
	dc.b	'JUST A QUICK NOTE.',0
	dc.b	$30,$02
	dc.b	'HELLO TO...',0
	dc.b	$38,$02
	dc.b	'MUM DAD DEIRDRE LORRAINE',0
	dc.w	$4002
	dc.b	'PETER KATHTRINA',0
	dc.w	$4802
	dc.b	'FIONA ANNY AND AUDREY',0
	dc.w	$5802
	dc.b	'AND ALL MY FRIENDS EVERYWHERE...',0
	dc.b	$70,$02
	dc.b	'     HUGS AND KISSES... JOBBEEEE',0
	dc.w	$ff00
toggle_music:	; from: hud_update
	bchg	#$0,game_flags
	bne.s	music_on
	moveq	#5,d0
	add.w	is_batwing,d0
	pea	hud_count
	jmp	snd_stop_music

music_on:
	moveq	#5,d0
	add.w	is_batwing,d0
	pea	hud_count
	jmp	snd_play_tune

abort_level:
	bset	#$5,game_flags
	bra.w	game_over

pause:	; from: hud_update
	move.w	#$1,sound_paused
pause_wait_release:
	bsr.w	get_key
	cmpi.w	#$81,d0
	beq.s	pause_wait_release
pause_wait_key:
	bsr.w	get_key
	cmpi.w	#$1b,d0
	beq.s	abort_level
	cmpi.w	#$81,d0
	bne.s	pause_wait_key
	move.w	#$0,sound_paused
	bra.w	hud_count

update_distance:	; from: hud_count
	lea	distance_digits,a0
	move.w	distance_tick,d1
	move.w	distance_left,d0
	beq.w	level_complete
	subi.w	#$6,d1
	bmi.s	distance_print
	move.w	d1,distance_tick
	subq.w	#1,d0
	move.w	d0,distance_left
distance_print:
	bsr.w	format_decimal
	move.b	$2e,(a0)+
	move.b	d0,(a0)
	lea	distance_text,a0
	bsr.w	print_text
	move.w	turn_ahead,d0
	lsl.w	#4,d0
	lea	sprite_headers,a5
	lea	$2(a5,d0.w),a5
	moveq	#0,d3
	move.w	(a5)+,d4
	move.w	(a5)+,d5
	move.w	(a5)+,d7
	move.w	#$90,d0
	moveq	#2,d2
	add.w	d7,d2
	bsr.w	draw_sprite_clipped
	rts


;----------------------------------------------------------------------
; Print text at a0: byte row, byte column pairs then zero terminated strings, $ff ends; d6 = bold.
;----------------------------------------------------------------------
print_text_bold:	; from: level_setup, time_up_text, lose_life, game_over_text, level_complete_text
	moveq	#-1,d6
	bra.s	text_position


print_text:	; from: hud_update, hud_count, restart_level
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


;----------------------------------------------------------------------
; Random number in d0 from random_seed (3 words).
;----------------------------------------------------------------------
random:	; from: engine_noise, spawn_balloons, spawn_traffic, traffic_lanes, draw_batmobile, build_road_batmobile, ...
	movem.l	d1/a0,-(sp)
	lea	random_seed,a0
	addq.w	#3,(a0)
	move.w	(a0)+,d0
	subi.w	#$8d,(a0)
	add.w	(a0)+,d0
	rol.w	#1,d0
	move.w	(a0),d1
	rol.w	#1,d1
	add.w	d1,d0
	move.w	d0,(a0)
	movem.l	(sp)+,d1/a0
	rts

random_seed:	; from: level_setup, random
	dc.w	$0d80,$007b,$b26e
balloon_table:	; from: spawn_balloons
	dc.w	$0002,$f984,$0003,$0c74,$0000,$001e,$0000,$40c6
	dc.w	$0002,$f984,$0003,$2ae0,$0000,$001e,$0000,$40c6
	dc.w	$0002,$f984,$0003,$4274,$0000,$0028,$0000,$407e
	dc.w	$0002,$f984,$0003,$0c74,$0000,$0028,$0000,$40c6
	dc.w	$0002,$f984,$0003,$0c74,$0000,$0032,$0000,$40c6
	dc.w	$0002,$f984,$0003,$2ae0,$0000,$0032,$0000,$40c6
	dc.w	$0002,$f984,$0003,$4274,$0000,$0032,$0000,$407e
	dc.w	$0002,$f984,$0003,$4274,$0000,$0032,$0000,$407e

;----------------------------------------------------------------------
; Level 4: every traffic_timer segments spawn a balloon pair (balloon + string object) in a random lane.
;----------------------------------------------------------------------
spawn_balloons:	; from: main_loop
	move.w	segments_moved,d0
	beq.w	spawn_balloons_exit
	sub.w	d0,traffic_timer
	bcc.w	spawn_balloons_exit
	bsr.w	random
	andi.w	#$f,d0
	addi.w	#$a,d0
	move.w	d0,traffic_timer
	bsr.w	alloc_object
	movea.l	a6,a5
	pea	free_first_balloon
	bsr.w	alloc_object
	addq.l	#4,sp
	bsr.w	random
	andi.w	#$3,d0
	move.b	d0,$5(a5)
	move.b	d0,$5(a6)
	lea	lane_x,a0
	move.b	$0(a0,d0.w),d1
	bsr.w	random
	andi.w	#$7,d0
	lsl.w	#4,d0
	lea	balloon_table,a0
	lea	$0(a0,d0.w),a0
	move.l	(a0)+,$12(a6)
	move.b	d1,$3(a6)
	move.l	#balloon_collide,$16(a6)
	move.l	a5,$20(a6)
	move.l	(a0)+,$12(a5)
	add.w	(a0)+,d1
	move.b	d1,$3(a5)
	move.l	#balloon_string,$16(a5)
	move.w	(a0)+,$1c(a5)
	move.l	(a0),$20(a5)
	move.w	#$1,$1a(a5)
spawn_balloons_exit:
	rts


free_first_balloon:	; from: spawn_balloons
	move.b	#$0,$0(a5)
	rts


;----------------------------------------------------------------------
; Balloon hit by the Batwing: spin the vehicle, slow down, leave a floating balloon and lose energy.
;----------------------------------------------------------------------
balloon_collide:	; from: spawn_balloons
	move.b	$8(a1),d0
	beq.w	balloon_collide_exit
	move.b	#$0,$0(a1)
	lea	vehicle,a6
	tst.w	$3a(a6)
	bne.w	balloon_collide_exit
	move.w	#$5,$32(a6)
	move.w	#$4,$3a(a6)
	moveq	#0,d1
	cmpi.b	#$2,d0
	beq.s	balloon_speed_up
	cmpi.b	#$3,d0
	bne.s	balloon_spin
	moveq	#-1,d1
balloon_spin:
	move.w	d1,$38(a6)
	move.w	speed,d0
	ext.l	d0
	divu.w	#$c,d0
	move.w	d0,$36(a6)
	move.w	$6(a1),d1
	lsr.w	#6,d1
balloon_speed_up:
	move.w	speed,d0
	move.w	d0,d2
	ext.l	d0
	divu.w	#$3,d0
	move.w	$6(a1),d1
	lsr.w	#6,d1
	add.w	d1,d0
	move.w	d0,speed
	lea	floaters,a6
	moveq	#1,d6
find_floater_loop:
	tst.w	$0(a6)
	beq.s	add_floater
	lea	$6(a6),a6
	dbra	d6,find_floater_loop
add_floater:
	move.w	#$1,$0(a6)
	move.w	$10(a1),$2(a6)
	move.w	$26(a1),$4(a6)
	movem.l	d7/a1,-(sp)
	move.b	$2(a1),d0
	movea.l	$20(a1),a1
	beq.s	balloon_damage
	tst.b	$0(a1)
	beq.s	balloon_damage
	cmp.b	$2(a1),d0
	bne.s	balloon_damage
	bsr.w	balloon_cut
balloon_damage:
	movem.l	(sp)+,d7/a1
	moveq	#5,d0
	bsr.w	play_sfx
	moveq	#1,d0
	jmp	panel_lose_energy

balloon_collide_exit:
	rts


balloon_string:	; from: spawn_balloons
	move.b	$8(a1),d0
	bne.s	balloon_cut
	rts


;----------------------------------------------------------------------
; Balloon string cut: start an explosion (four pieces) and score.
;----------------------------------------------------------------------
balloon_cut:	; from: balloon_collide, balloon_string
	move.b	#$0,$0(a1)
	lea	explosions,a6
	moveq	#1,d6
find_explosion_loop:
	tst.w	$0(a6)
	beq.s	add_explosion
	lea	$14(a6),a6
	dbra	d6,find_explosion_loop
add_explosion:
	move.w	$10(a1),d0
	move.w	$26(a1),d1
	move.w	#$c,$0(a6)
	move.w	#$0,$2(a6)
	move.w	d0,$4(a6)
	move.w	d1,$6(a6)
	addi.w	#$28,d0
	move.w	d0,$8(a6)
	move.w	d1,$a(a6)
	subi.w	#$28,d1
	move.w	d0,$c(a6)
	move.w	d1,$e(a6)
	subi.w	#$28,d0
	move.w	d0,$10(a6)
	move.w	d1,$12(a6)
	moveq	#19,d0
	bsr.w	play_sfx
	moveq	#1,d0
	jmp	panel_lose_energy


;----------------------------------------------------------------------
; Level 2: when the course asks for it, spawn the four part road block that ends the level.
;----------------------------------------------------------------------
spawn_roadblock:	; from: main_loop
	tst.w	roadblock_due
	beq.w	spawn_roadblock_exit
	tst.w	segments_moved
	beq.w	spawn_roadblock_exit
	move.w	#$0,roadblock_due
	bsr.w	alloc_object
	move.b	#$0,$5(a6)
	move.b	lane_x,$3(a6)
	move.l	#$2b7a8,$12(a6)                 ; level2_gfx +$1b370
	move.l	#roadblock_reached,$16(a6)
	move.w	#$1,$24(a6)
	bsr.w	alloc_object
	move.b	#$1,$5(a6)
	move.b	lane_x+1,$3(a6)
	move.l	#$2b7a8,$12(a6)                 ; level2_gfx +$1b370
	move.l	#object_idle,$16(a6)
	move.w	#$1,$24(a6)
	move.b	#$15,$2(a6)
	bsr.w	alloc_object
	move.b	#$2,$5(a6)
	move.b	lane_x+2,$3(a6)
	move.l	#$2b7a8,$12(a6)                 ; level2_gfx +$1b370
	move.l	#object_idle,$16(a6)
	move.w	#$1,$24(a6)
	bsr.w	alloc_object
	move.b	#$3,$5(a6)
	move.b	lane_x+3,$3(a6)
	move.l	#$2b7a8,$12(a6)                 ; level2_gfx +$1b370
	move.l	#object_idle,$16(a6)
	move.w	#$1,$24(a6)
	move.b	#$15,$2(a6)
spawn_roadblock_exit:
	rts


roadblock_reached:	; from: spawn_roadblock
	move.b	$2(a1),d0
	ext.w	d0
	cmpi.w	#$4,d0
	bcc.s	roadblock_slow
	move.w	#$1,level_end_state
	moveq	#0,d0
	bra.s	roadblock_set_speed

roadblock_slow:
	lsl.w	#4,d0
	cmp.w	speed,d0
	bcc.s	roadblock_exit
roadblock_set_speed:
	move.w	d0,speed
roadblock_exit:
	rts


;----------------------------------------------------------------------
; Level 2: every traffic_timer segments spawn a car in a random lane with a random sprite.
;----------------------------------------------------------------------
spawn_traffic:	; from: main_loop
	move.w	segments_moved,d0
	beq.w	spawn_traffic_exit
	sub.w	d0,traffic_timer
	bcc.w	spawn_traffic_exit
	bsr.w	random
	andi.w	#$f,d0
	add.w	traffic_rate,d0
	move.w	d0,traffic_timer
	moveq	#3,d7
	bsr.w	alloc_object_n
	bsr.w	random
	andi.w	#$3,d0
	move.b	d0,$5(a6)
	lea	lane_x,a0
	move.b	$0(a0,d0.w),$3(a6)
	bsr.w	random
	andi.w	#$ff,d0
	addi.w	#$32,d0
	cmpi.w	#$96,d0
	bcc.w	traffic_set_speed
	addi.w	#$96,d0
traffic_set_speed:
	move.w	d0,$6(a6)
	bsr.w	random
	andi.w	#$7,d0
	lsl.w	#2,d0
	lea	traffic_sprites,a0
	move.l	$0(a0,d0.w),$12(a6)
	move.l	#traffic_collide,$16(a6)
spawn_traffic_exit:
	rts

traffic_sprites:	; from: spawn_traffic
	dc.w	$0002,$e380,$0002,$c910,$0002,$ee6c,$0002,$fc34
	dc.w	$0002,$ee6c,$0002,$e380,$0002,$c910,$0002,$fc34

;----------------------------------------------------------------------
; Traffic car hit: spin the Batmobile and lose energy.
;----------------------------------------------------------------------
traffic_collide:	; from: spawn_traffic
	bsr.w	traffic_lanes
	move.b	$8(a1),d0
	beq.s	traffic_collide_exit
	move.b	#$0,$8(a1)
	lea	vehicle,a6
	tst.w	$3a(a6)
	bne.s	traffic_collide_exit
	move.w	#$5,$32(a6)
	move.w	#$4,$3a(a6)
	moveq	#0,d1
	cmpi.b	#$2,d0
	beq.s	traffic_speed_up
	cmpi.b	#$3,d0
	bne.s	traffic_spin
	moveq	#-1,d1
traffic_spin:
	move.w	d1,$38(a6)
	move.w	speed,d0
	ext.l	d0
	divu.w	#$c,d0
	move.w	d0,$36(a6)
	move.w	$6(a1),d1
	lsr.w	#6,d1
traffic_speed_up:
	move.w	speed,d0
	move.w	d0,d2
	ext.l	d0
	divu.w	#$3,d0
	move.w	$6(a1),d1
	lsr.w	#6,d1
	add.w	d1,d0
	move.w	d0,speed
	addi.b	#$2,$2(a1)
	moveq	#15,d0
	bsr.w	play_sfx
	moveq	#3,d0
	jmp	panel_lose_energy

traffic_collide_exit:
	rts


;----------------------------------------------------------------------
; Keep traffic cars apart: change lane when another car is close ahead.
;----------------------------------------------------------------------
traffic_lanes:	; from: traffic_collide
	move.b	$5(a1),d2
	move.b	$2(a1),d0
	moveq	#7,d6
	lea	objects,a2
lanes_next_object:
	cmpa.l	a1,a2
	beq.s	lanes_next
	tst.b	$0(a2)
	beq.s	lanes_next
	move.b	$2(a2),d1
	sub.b	d0,d1
	bcs.s	lanes_next
	cmpi.b	#$3,d1
	bcc.s	lanes_next
	tst.w	$24(a2)
	beq.s	lanes_same_lane
	move.w	#$0,$6(a1)
	bra.s	lanes_next

lanes_same_lane:
	cmp.b	$5(a2),d2
	beq.s	lanes_change
lanes_next:
	lea	$2a(a2),a2
	dbra	d6,lanes_next_object
	bra.s	lanes_move_x

lanes_change:
	tst.b	d2
	bne.s	lanes_from_right
	moveq	#1,d2
	bra.s	lanes_store

lanes_from_right:
	cmpi.b	#$3,d2
	bne.s	lanes_random
	moveq	#2,d2
	bra.s	lanes_store

lanes_random:
	bsr.w	random
	addq.b	#1,d2
	btst	#$0,d0
	beq.s	lanes_store
	subq.b	#2,d2
lanes_store:
	move.b	d2,$5(a1)
lanes_move_x:
	lea	lane_x,a2
	ext.w	d2
	move.b	$0(a2,d2.w),d1
	move.b	$3(a1),d0
	cmp.b	d0,d1
	beq.s	lanes_exit
	bcc.s	lanes_move_right
	subq.b	#6,d0
	cmp.b	d0,d1
	bcs.s	lanes_store_x
	move.b	d1,d0
	bra.s	lanes_store_x

lanes_move_right:
	addq.b	#6,d0
	cmp.b	d0,d1
	bcc.s	lanes_store_x
	move.b	d1,d0
lanes_store_x:
	move.b	d0,$3(a1)
lanes_exit:
	rts


;----------------------------------------------------------------------
; Take a free object slot (8 slots of $2a bytes in objects); returns a6, or drops the return address.
;----------------------------------------------------------------------
alloc_object:	; from: spawn_balloons, spawn_roadblock
	moveq	#7,d7

alloc_object_n:	; from: spawn_traffic
	lea	objects,a6
alloc_next:
	tst.b	$0(a6)
	beq.s	alloc_clear
	lea	$2a(a6),a6
	dbra	d7,alloc_next
	addq.w	#4,sp
	rts

alloc_clear:
	moveq	#20,d7
	movea.l	a6,a4
alloc_clear_loop:
	move.w	#$0,(a4)+
	dbra	d7,alloc_clear_loop
	move.b	#$16,$2(a6)
	move.b	#$1,$0(a6)

object_idle:	; from: spawn_roadblock
	rts

lane_x:	; from: spawn_balloons, spawn_roadblock, spawn_traffic, traffic_lanes
	dc.w	$2864,$a4e2

;----------------------------------------------------------------------
; Update the 8 objects: perspective scale, z sort into sort_list, run each handler ($16(a6)).
;----------------------------------------------------------------------
update_objects:	; from: main_loop
	lea	sort_list,a0
	move.l	a0,sort_ptr
	moveq	#-1,d0
	move.w	d0,(a0)
	addq.w	#6,a0
	move.w	d0,(a0)
	addq.w	#6,a0
	move.w	d0,(a0)
	addq.w	#6,a0
	move.w	d0,(a0)
	addq.w	#6,a0
	move.w	d0,(a0)
	addq.w	#6,a0
	move.w	d0,(a0)
	addq.w	#6,a0
	move.w	d0,(a0)
	addq.w	#6,a0
	move.w	d0,(a0)
	addq.w	#6,a0
	move.w	d0,(a0)
	lea	road_width,a0
	lea	objects,a1
	moveq	#7,d7
next_object:	; from: advance_object
	tst.b	$0(a1)
	bne.s	update_object

advance_object:	; from: object_hit_test
	lea	$2a(a1),a1
	dbra	d7,next_object
	rts

update_object:	; from: update_objects
	moveq	#0,d1
	move.w	d1,d0
	move.b	$4(a1),d0
	move.b	$6(a1),d1
	sub.b	$7(a1),d0
	bcc.s	object_z
	addi.b	#$1,d1
object_z:
	add.b	$2(a1),d1
	tst.b	$1(a1)
	bne.s	object_behind
	cmpi.b	#$18,d1
	bcs.s	object_store_z
	move.b	#$0,$0(a1)
	bra.s	advance_object

object_behind:
	tst.b	d1
	ble.s	object_store_z
	cmpi.b	#$2,d1
	bcs.s	object_clamp_z
	cmpi.b	#$be,d0
	bcc.s	object_store_z
object_clamp_z:
	move.b	#$be,d0
	moveq	#1,d1
object_store_z:
	move.b	d1,$2(a1)
	move.b	d0,$4(a1)
	cmpi.b	#$14,d1
	bcc.w	object_handler
	tst.b	d1
	bne.s	object_project
	move.w	segment_fraction,d2
	andi.b	#$e0,d2
	not.b	d2
	cmp.b	d0,d2
	bcc.s	object_project
	tst.b	$1(a1)
	bne.s	advance_object
	move.b	#$0,$0(a1)
	bra.w	advance_object

object_project:
	move.b	$5b(a0,d1.w),d0
	move.b	d0,d2
	sub.b	$5a(a0,d1.w),d0
	move.b	$4(a1),d1
	mulu.w	d1,d0
	lsr.w	#8,d0
	move.w	d0,$a(a1)
	sub.b	d0,d2
	add.b	d2,d2
	andi.w	#$ff,d2
	lea	road_left_edge,a2
	lea	$0(a2,d2.w),a2
	move.w	$400(a2),d0
	move.w	(a2),d1
	sub.w	d1,d0
	moveq	#0,d2
	move.b	$3(a1),d2
	mulu.w	d2,d0
	lsr.l	#8,d0
	add.w	d1,d0
	move.b	$2(a1),d2
	move.w	d2,d3
	lsr.b	#2,d2
	add.w	d2,d0
	lsr.w	#1,d3
	cmpi.w	#$7,d3
	bcs.s	object_frame
	moveq	#7,d3
object_frame:
	asl.w	#4,d3
	movea.l	$12(a1),a2
	lea	$0(a2,d3.w),a2
	move.w	(a2),d3
	move.w	d3,$c(a1)
	move.w	$6(a2),$e(a1)
	move.w	d0,d6
	lsr.w	#1,d3
	sub.w	d3,d0
	move.w	d0,$10(a1)
	tst.w	$28(a1)
	beq.s	object_not_cut
	addq.w	#6,$1c(a1)
	cmpi.w	#$50,$1c(a1)
	bcs.s	object_balloon_height
	move.b	#$0,$0(a1)
	bra.w	advance_object

object_not_cut:
	tst.w	$1a(a1)
	beq.s	object_collision
object_balloon_height:
	move.w	segment_fraction,d1
	andi.w	#$e0,d1
	add.b	$2(a1),d1
	lea	hill_tables,a2
	move.b	$0(a2,d1.w),d1
	mulu.w	$1c(a1),d1
	lsr.w	#5,d1
	add.w	$a(a1),d1
	move.w	d1,$1e(a1)
object_collision:
	move.b	$2(a1),d1
	cmpi.b	#$2,d1
	bcc.w	object_sort
	ext.w	d1
	move.b	$1(a0,d1.w),d2
	andi.w	#$ff,d2
	addi.w	#$38,d2
	add.w	$a(a1),d2
	move.w	d2,$26(a1)
	lea	vehicle,a2
	move.w	$10(a2),d3
	add.w	$2c(a2),d3
	move.w	d3,d4
	sub.w	$2a(a2),d4
	tst.w	$1a(a1)
	beq.s	object_hit_test
	cmp.w	d4,d2
	bcs.s	object_hit_test
	move.w	d2,d5
	sub.w	$1e(a1),d5
	move.w	d5,$26(a1)
	bmi.s	object_string_check
	cmp.w	d3,d5
	bcc.s	object_hit_test
object_string_check:
	tst.b	d1
	beq.s	object_cut_string
	tst.b	segment_fraction+1
	bpl.s	object_hit_test
object_cut_string:
	subi.w	#$8,d6
	cmp.w	$30(a2),d6
	bcc.s	object_hit_test
	addi.w	#$10,d6
	cmp.w	$2e(a2),d6
	bcs.s	object_hit_test
	move.w	#$0,$1a(a1)
	move.w	#$1,$28(a1)
	subq.w	#1,balloons_left
	moveq	#20,d0
	bsr.w	play_sfx
	move.l	#$400,d0
	pea	object_hit_test
	jmp	panel_add_score


object_hit_test:	; from: advance_object
	sub.w	$1e(a1),d2
	bmi.s	object_sort
	tst.w	$28(a1)
	bne.s	object_sort
	cmp.w	d4,d2
	bcs.s	object_sort
	sub.w	$e(a1),d2
	bmi.s	object_hit_x
	cmp.w	d3,d2
	bcc.s	object_sort
object_hit_x:
	cmp.w	$30(a2),d0
	bcc.s	object_sort
	move.w	$c(a1),d2
	add.w	d2,d0
	cmp.w	$2e(a2),d0
	bcs.s	object_sort
	lsr.w	#1,d2
	sub.w	d2,d0
	moveq	#3,d1
	cmpi.w	#$b9,d0
	bcc.s	object_hit_side
	moveq	#2,d1
	cmpi.w	#$87,d0
	bcc.s	object_hit_side
	moveq	#1,d1
object_hit_side:
	move.b	d1,$8(a1)
object_sort:	; from: advance_object
	move.b	$2(a1),d0
	lsl.w	#8,d0
	move.b	$4(a1),d0
	not.b	d0
	lea	sort_list,a2
	moveq	#7,d6
sort_find_loop:
	move.w	(a2),d1
	bmi.s	sort_insert
	cmp.w	d0,d1
	bcs.s	sort_shift
	addq.l	#6,a2
	subq.w	#1,d6
	bra.s	sort_find_loop

sort_shift:
	subq.w	#1,d6
	bmi.s	sort_insert
	lea	sort_list_end,a3
	lea	-$6(a3),a2
sort_shift_loop:
	move.l	-(a2),-(a3)
	move.w	-(a2),-(a3)
	dbra	d6,sort_shift_loop
sort_insert:
	move.w	d0,(a2)+
	move.l	a1,(a2)
object_handler:	; from: advance_object
	movea.l	$16(a1),a2
	pea	advance_object
	jmp	(a2)


;----------------------------------------------------------------------
; Draw every object whose sort key matches row d7 (sort_list order), balloons with their string.
;----------------------------------------------------------------------
draw_objects:	; from: draw_roadside
	movea.l	sort_ptr,a4
	cmp.b	(a4),d7
	beq.s	draw_next_object
	rts

draw_next_object:
	movea.l	$2(a4),a6
	addq.l	#6,sort_ptr
	movea.l	$12(a6),a5
	lea	$0(a5,d5.w),a5
	move.w	(a5)+,d1
	move.w	$10(a6),d0
	bmi.s	object_left_clip
	cmpi.w	#$140,d0
	bcs.s	object_on_screen
	bra.w	draw_objects

object_left_clip:
	add.w	d0,d1
	bmi.s	draw_objects
	cmpi.w	#$10,d1
	bcs.s	draw_objects
object_on_screen:
	tst.w	$1a(a6)
	bne.s	draw_balloon_string
draw_plain_object:
	movem.l	d5-d7/a0-a3,-(sp)
	move.w	$a(a6),d6
	sub.w	$1e(a6),d6
	bsr.w	draw_scaled_sprite_d6
	movem.l	(sp)+,d5-d7/a0-a3
	bra.s	draw_objects

draw_balloon_string:
	movem.l	d0-d7/a0-a6,-(sp)
	movea.l	$20(a6),a5
	lsr.w	#1,d5
	lea	$0(a5,d5.w),a5
	lea	bridge_sprites,a4
	lea	$0(a4,d5.w),a4
	add.w	(a5),d0
	bmi.w	string_done
	cmpi.w	#$138,d0
	bcc.w	string_done
	move.w	$a(a6),d6
	move.w	$2(a5),d7
	beq.w	string_done
	add.w	d7,d6
	add.w	$4(a5),d7
	add.w	$1e(a6),d7
	moveq	#0,d2
	move.w	d2,d1
	move.b	(a1),d1
	move.b	$43(a1),d2
	sub.w	d2,d1
	bne.s	string_clip
string_top:
	add.w	d6,d2
	bmi.w	string_done
string_height:
	move.w	d2,d1
	addq.w	#1,d1
	sub.w	d7,d1
	bcc.s	string_draw_setup
	add.w	d1,d7
	bra.s	string_draw_setup

string_clip:
	tst.w	d6
	bmi.s	string_clip_neg
	sub.w	d6,d1
	bra.s	string_clip_apply

string_clip_neg:
	add.w	d6,d1
string_clip_apply:
	move.w	d1,d6
	beq.s	string_top
	bmi.s	string_top
	subq.w	#1,d7
	sub.w	d6,d7
	bcs.w	string_done
	addq.w	#1,d7
	bra.s	string_height

string_draw_setup:
	movea.l	screen_back,a0
	addq.w	#1,d2
	sub.w	d7,d2
	mulu.w	#$a0,d2
	move.w	d0,d4
	lsr.w	#1,d0
	andi.w	#$fff8,d0
	add.w	d2,d0
	lea	$0(a0,d0.w),a0
	andi.w	#$f,d4
	move.w	(a4)+,d0
	moveq	#-1,d1
	move.w	(a4)+,d1
	movea.l	(a4),a4
	subq.w	#1,d4
	bmi.s	string_rows
string_shift_loop:
	ror.l	#1,d1
	lea	$140(a4),a4
	dbra	d4,string_shift_loop
string_rows:
	subq.w	#1,d7
	move.l	d1,d4
	move.w	d1,d2
	swap	d1
	move.w	d1,d4
	move.w	d2,d1
	moveq	#0,d2
	tst.w	d0
	bmi.s	string_row_loop_wrap
string_row_loop:
	and.l	d1,(a0)
	and.l	d1,$4(a0)
	and.l	d4,$8(a0)
	and.l	d4,$c(a0)
	move.l	$0(a4,d2.w),d3
	or.w	d3,$8(a0)
	swap	d3
	or.w	d3,(a0)
	move.l	$4(a4,d2.w),d3
	or.w	d3,$a(a0)
	swap	d3
	or.w	d3,$2(a0)
	move.l	$8(a4,d2.w),d3
	or.w	d3,$c(a0)
	swap	d3
	or.w	d3,$4(a0)
	move.l	$c(a4,d2.w),d3
	or.w	d3,$e(a0)
	swap	d3
	or.w	d3,$6(a0)
	lea	$a0(a0),a0
	addi.w	#$10,d2
	and.w	d0,d2
	dbra	d7,string_row_loop
string_done:
	movem.l	(sp)+,d0-d7/a0-a6
	bra.w	draw_plain_object

string_row_loop_wrap:
	and.l	d1,(a0)
	and.l	d1,$4(a0)
	and.l	d4,$8(a0)
	and.l	d4,$c(a0)
	move.l	$0(a4,d2.w),d3
	or.w	d3,$8(a0)
	swap	d3
	or.w	d3,(a0)
	move.l	$4(a4,d2.w),d3
	or.w	d3,$a(a0)
	swap	d3
	or.w	d3,$2(a0)
	move.l	$8(a4,d2.w),d3
	or.w	d3,$c(a0)
	swap	d3
	or.w	d3,$4(a0)
	move.l	$c(a4,d2.w),d3
	or.w	d3,$e(a0)
	swap	d3
	or.w	d3,$6(a0)
	lea	$a0(a0),a0
	addi.w	#$10,d2
	cmpi.w	#$30,d2
	bne.s	string_wrap_next
	moveq	#0,d2
string_wrap_next:
	dbra	d7,string_row_loop_wrap
	bra.s	string_done

	dc.w	$0032,$ffdc,$000a,$0000,$0021,$ffe4,$0008,$0000
	dc.w	$0018,$ffea,$0006,$0000,$0013,$ffee,$0004,$0000
	dc.w	$0011,$fff2,$0002,$0000,$000e,$fff4,$0002,$0000
	dc.w	$000c,$fff6,$0002,$0000,$000b,$fff8,$0002,$0000
	dc.w	$000b,$fffa,$0002,$0000,$001d,$ffdc,$000a,$0000
	dc.w	$0013,$ffe4,$0008,$0000,$000e,$ffea,$0006,$0000
	dc.w	$000b,$ffee,$0004,$0000,$0009,$fff2,$0002,$0000
	dc.w	$0008,$fff4,$0002,$0000,$0007,$fff6,$0002,$0000
	dc.w	$0006,$fff8,$0002,$0000,$0006,$fffa,$0002,$0000
bridge_sprites:	; from: draw_objects
	dc.w	$0030,$07ff,$0002,$e584,$ffff,$07ff,$0002,$e5c4
	dc.w	$ffff,$0fff,$0002,$e5f4,$0010,$0fff,$0002,$e624
	dc.w	$0010,$1fff,$0002,$e644,$0010,$3fff,$0002,$e664
	dc.w	$0000,$3fff,$0002,$e684,$0010,$7fff,$0002,$e694
	dc.w	$0000,$7fff,$0002,$e6b4

;----------------------------------------------------------------------
; Draw the roadside scenery and the objects row by row from the horizon down, then the vehicle.
;----------------------------------------------------------------------
draw_roadside:	; from: main_loop
	tst.w	is_batwing
	beq.s	roadside_start
	bsr.w	draw_batwing
roadside_start:
	lea	line_heights,a0
	lea	line_min_heights,a1
	move.w	#$14,d7
	move.w	#$38,d0
heights_add_loop:
	add.b	d0,(a0)+
	add.b	d0,(a1)+
	dbra	d7,heights_add_loop
	lea	roadside_positions+78,a0
	lea	line_heights+19,a1
	lea	course_bytes,a2
	lea	scale_tables,a3
	move.w	segment_fraction,d0
	andi.w	#$e0,d0
	lea	$0(a3,d0.w),a3
	move.w	segment_index,d6
	addi.b	#$53,d6
	move.w	#$13,d7
roadside_row:
	tst.w	is_batwing
	beq.w	draw_vehicle_in_order
roadside_row_objects:	; from: batwing_control
	move.w	d7,d5
	lsr.w	#1,d5
	cmpi.w	#$8,d5
	bcs.s	roadside_scale_clamp
	moveq	#8,d5
roadside_scale_clamp:
	asl.w	#4,d5
	bsr.w	draw_objects
	move.b	$0(a2,d6.w),d0
	bne.s	roadside_right_sprite
roadside_left_side:
	addi.b	#$20,d6
	subq.w	#2,a0
	move.b	$0(a2,d6.w),d0
	bne.s	roadside_left_sprite
roadside_next_row:
	subi.b	#$21,d6
	subq.w	#2,a0
	subq.w	#1,a1
	dbra	d7,roadside_row
	tst.w	is_batwing
	beq.w	draw_batmobile
	bra.w	draw_batwing_objects

roadside_right_sprite:
	lsl.w	#4,d0
	andi.w	#$f0,d0
	lea	scenery_right_table,a4
	movea.l	$0(a4,d0.w),a5
	move.b	$4(a4,d0.w),d1
	move.b	$5(a4,d0.w),d2
	move.b	$0(a3,d7.w),d0
	ext.w	d0
	ext.w	d1
	mulu.w	d1,d0
	ext.w	d2
	beq.s	right_sprite_x
	divu.w	d2,d0
right_sprite_x:
	add.w	(a0),d0
	lea	$0(a5,d5.w),a5
	move.w	(a5)+,d1
	tst.w	d0
	bmi.s	right_sprite_clip
	cmpi.w	#$140,d0
	bcs.s	right_sprite_draw
	bra.s	roadside_left_side

right_sprite_clip:
	add.w	d0,d1
	bmi.s	roadside_left_side
	cmpi.w	#$0,d0
	bcs.s	roadside_left_side
right_sprite_draw:
	movem.l	d5-d7/a0-a3,-(sp)
	bsr.s	draw_scaled_sprite
	movem.l	(sp)+,d5-d7/a0-a3
	bra.s	roadside_left_side

roadside_left_sprite:
	lsl.w	#4,d0
	andi.w	#$f0,d0
	lea	scenery_left_table,a4
	movea.l	$0(a4,d0.w),a5
	move.b	$4(a4,d0.w),d1
	move.b	$5(a4,d0.w),d2
	move.b	$0(a3,d7.w),d0
	ext.w	d0
	ext.w	d1
	mulu.w	d1,d0
	ext.w	d2
	beq.s	left_sprite_x
	divu.w	d2,d0
left_sprite_x:
	neg.w	d0
	addi.w	#$a,d0
	add.w	(a0),d0
	lea	$0(a5,d5.w),a5
	move.w	(a5)+,d1
	sub.w	d1,d0
	bmi.s	left_sprite_clip
	cmpi.w	#$140,d0
	bcs.s	left_sprite_draw
	bra.w	roadside_next_row

left_sprite_clip:
	add.w	d0,d1
	bmi.w	roadside_next_row
	cmpi.w	#$10,d1
	bcs.w	roadside_next_row
left_sprite_draw:
	movem.l	d5-d7/a0-a3,-(sp)
	bsr.s	draw_scaled_sprite
	movem.l	(sp)+,d5-d7/a0-a3
	bra.w	roadside_next_row


;----------------------------------------------------------------------
; Draw a sprite from its header at a5 scaled to the row size, clipped at the screen sides.
;----------------------------------------------------------------------
draw_scaled_sprite:	; from: draw_roadside
	moveq	#0,d6

draw_scaled_sprite_d6:	; from: draw_objects
	move.w	(a5)+,d4
	move.w	(a5)+,d5
	move.w	(a5)+,d7
	movea.l	(a5)+,a4
	movea.l	(a5),a6
	move.w	d0,d1
	andi.w	#$e,d1
	lsl.w	#2,d1
	lea	$0(a4,d1.w),a4
	add.w	(a4)+,d5
	add.w	(a4)+,d4
	movea.l	(a4),a5
	moveq	#0,d3
	move.w	d3,d2
	move.w	d3,d1
	move.b	(a1),d1
	move.b	$43(a1),d2
	sub.w	d2,d1
	bne.s	scaled_offset
scaled_rows:	; from: draw_grapple_hook, draw_sprite_masked
	add.w	d6,d2
	bmi.s	scaled_exit
scaled_clip_bottom:
	move.w	d2,d1
	addq.w	#1,d1
	sub.w	d7,d1
	bcc.s	sprite_clip_x
	add.w	d1,d7
	neg.w	d1
	subq.w	#1,d1
scaled_skip_rows_loop:
	add.w	d5,d3
	dbra	d1,scaled_skip_rows_loop
	bra.s	sprite_clip_x

scaled_exit:
	rts

scaled_offset:
	tst.w	d6
	bmi.s	scaled_offset_neg
	sub.w	d6,d1
	bra.s	scaled_clip_top

scaled_offset_neg:
	add.w	d6,d1
scaled_clip_top:
	move.w	d1,d6
	beq.s	scaled_rows
	bmi.s	scaled_rows
	subq.w	#1,d7
	sub.w	d6,d7
	bcs.s	scaled_exit
	addq.w	#1,d7
	bra.s	scaled_clip_bottom


;----------------------------------------------------------------------
; Draw sprite header a5 at x d0, row d2, clipped at the sides; a6 = row blitter.
;----------------------------------------------------------------------
draw_sprite_clipped:	; from: restart_level
	lea	blit_rows,a6
sprite_relative_data:	; from: draw_sprite_cleared
	move.l	(a5),d1
	adda.l	d1,a5
sprite_clip_x:	; from: draw_scaled_sprite_d6
	move.w	d0,d1
	asr.w	#4,d1
	bmi.s	sprite_clip_left
	cmpi.w	#$0,d1
	bcs.s	sprite_clip_left
	moveq	#0,d6
	add.w	d4,d1
	subi.w	#$14,d1
	bcs.s	sprite_full_width
	sub.w	d4,d1
	neg.w	d1
	bra.s	sprite_screen_address

sprite_full_width:
	move.w	d4,d1
	bra.s	sprite_screen_address

sprite_clip_left:
	add.w	d4,d1
	subi.w	#$0,d1
	move.w	d1,d6
	neg.w	d6
	add.w	d4,d6
	andi.w	#$f,d0
	ori.w	#$0,d0
sprite_screen_address:
	movea.l	screen_back,a0
	addq.w	#1,d2
	sub.w	d7,d2
	mulu.w	#$a0,d2
	lsr.w	#1,d0
	andi.w	#$fff8,d0
	add.w	d2,d0
	lea	$0(a0,d0.w),a0
	subq.w	#1,d7
	jmp	(a6)


;----------------------------------------------------------------------
; Blit d7+1 rows of d1 8 byte columns from a5 to a0 with mask/data pairs (blit_cols_N).
;----------------------------------------------------------------------
blit_rows:	; from: draw_sprite_clipped, draw_sprite_masked, unpack_sprite16
	lsl.w	#2,d6
	beq.s	blit_rows_entry
	move.w	d6,d0
	lsl.w	#1,d6
	add.w	d0,d6
	add.w	d6,d3
blit_rows_entry:
	lea	$0(a5,d3.w),a5
	lea	blit_row_table-4,a1
	lsl.w	#2,d1
	movea.l	$0(a1,d1.w),a1
	bra.s	blit_row

blit_next_row:	; from: blit_cols_1
	lea	$a0(a0),a0
	lea	$0(a5,d5.w),a5
blit_row:
	movea.l	a0,a2
	movea.l	a5,a3
	jmp	(a1)


blit_cols_12:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_11:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_10:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_9:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_8:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_7:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_6:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_5:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_4:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_3:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_2:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+

blit_cols_1:	; from: blit_row_table
	movem.l	(a3)+,d0-d2
	and.l	d0,(a2)
	or.l	d1,(a2)+
	and.l	d0,(a2)
	or.l	d2,(a2)+
	dbra	d7,blit_next_row
	rts

blit_row_table:
	dc.l	blit_cols_1
	dc.l	blit_cols_2
	dc.l	blit_cols_3
	dc.l	blit_cols_4
	dc.l	blit_cols_5
	dc.l	blit_cols_6
	dc.l	blit_cols_7
	dc.l	blit_cols_8
	dc.l	blit_cols_9
	dc.l	blit_cols_10
	dc.l	blit_cols_11
	dc.l	blit_cols_12

blit_mask_rows:	; from: shift_sprite16
	lsl.w	#1,d6
	beq.s	blit_mask_entry
	move.w	d6,d0
	lsl.w	#1,d6
	add.w	d0,d6
	add.w	d6,d3
blit_mask_entry:
	lea	$0(a5,d3.w),a5
	lea	blit_mask_row_table-4,a1
	lsl.w	#2,d1
	movea.l	$0(a1,d1.w),a1
	bra.s	blit_mask_row

blit_mask_next_row:	; from: blit_mask_cols_1
	lea	$a0(a0),a0
	lea	$0(a5,d5.w),a5
blit_mask_row:
	movea.l	a0,a2
	movea.l	a5,a3
	jmp	(a1)


blit_mask_cols_8:	; from: blit_mask_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	(a3)+,d1
	and.l	d0,(a2)+
	and.l	d0,(a2)
	or.l	d1,(a2)+

blit_mask_cols_7:	; from: blit_mask_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	(a3)+,d1
	and.l	d0,(a2)+
	and.l	d0,(a2)
	or.l	d1,(a2)+

blit_mask_cols_6:	; from: blit_mask_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	(a3)+,d1
	and.l	d0,(a2)+
	and.l	d0,(a2)
	or.l	d1,(a2)+

blit_mask_cols_5:	; from: blit_mask_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	(a3)+,d1
	and.l	d0,(a2)+
	and.l	d0,(a2)
	or.l	d1,(a2)+

blit_mask_cols_4:	; from: blit_mask_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	(a3)+,d1
	and.l	d0,(a2)+
	and.l	d0,(a2)
	or.l	d1,(a2)+

blit_mask_cols_3:	; from: blit_mask_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	(a3)+,d1
	and.l	d0,(a2)+
	and.l	d0,(a2)
	or.l	d1,(a2)+

blit_mask_cols_2:	; from: blit_mask_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	(a3)+,d1
	and.l	d0,(a2)+
	and.l	d0,(a2)
	or.l	d1,(a2)+

blit_mask_cols_1:	; from: blit_mask_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	(a3)+,d1
	and.l	d0,(a2)+
	and.l	d0,(a2)
	or.l	d1,(a2)+
	dbra	d7,blit_mask_next_row
	rts

blit_mask_row_table:
	dc.l	blit_mask_cols_1
	dc.l	blit_mask_cols_2
	dc.l	blit_mask_cols_3
	dc.l	blit_mask_cols_4
	dc.l	blit_mask_cols_5
	dc.l	blit_mask_cols_6
	dc.l	blit_mask_cols_7
	dc.l	blit_mask_cols_8
blit_clear_rows:	; from: draw_sprite_cleared
	lsl.w	#2,d6
	beq.s	blit_clear_entry
	move.w	d6,d0
	lsl.w	#1,d6
	add.w	d0,d6
	add.w	d6,d3
blit_clear_entry:
	lea	$0(a5,d3.w),a5
	lea	blit_clear_row_table-4,a1
	lsl.w	#2,d1
	movea.l	$0(a1,d1.w),a1
	bra.s	blit_clear_row

blit_clear_next_row:	; from: blit_clear_cols_1
	lea	$a0(a0),a0
	lea	$0(a5,d5.w),a5
blit_clear_row:
	movea.l	a0,a2
	movea.l	a5,a3
	jmp	(a1)


blit_clear_cols_8:	; from: blit_clear_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)+
	and.l	d0,(a2)+

blit_clear_cols_7:	; from: blit_clear_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)+
	and.l	d0,(a2)+

blit_clear_cols_6:	; from: blit_clear_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)+
	and.l	d0,(a2)+

blit_clear_cols_5:	; from: blit_clear_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)+
	and.l	d0,(a2)+

blit_clear_cols_4:	; from: blit_clear_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)+
	and.l	d0,(a2)+

blit_clear_cols_3:	; from: blit_clear_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)+
	and.l	d0,(a2)+

blit_clear_cols_2:	; from: blit_clear_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)+
	and.l	d0,(a2)+

blit_clear_cols_1:	; from: blit_clear_row_table
	move.w	(a3)+,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)+
	and.l	d0,(a2)+
	dbra	d7,blit_clear_next_row
	rts

blit_clear_row_table:
	dc.l	blit_clear_cols_1
	dc.l	blit_clear_cols_2
	dc.l	blit_clear_cols_3
	dc.l	blit_clear_cols_4
	dc.l	blit_clear_cols_5
	dc.l	blit_clear_cols_6
	dc.l	blit_clear_cols_7
	dc.l	blit_clear_cols_8

;----------------------------------------------------------------------
; Hit test between the vehicle and the nearest roadside object on each side.
;----------------------------------------------------------------------
roadside_collision:	; from: main_loop
	lea	roadside_positions,a0
	lea	vehicle,a1
	tst.w	$3a(a1)
	bne.w	collision_exit
	moveq	#0,d1
	move.w	(a0)+,d0
	bmi.s	collision_right_side
	move.w	$2e(a1),d3
	addq.w	#5,d3
	cmp.w	d3,d0
	bcs.s	collision_right_side
	moveq	#0,d6
	moveq	#96,d2
	lea	scenery_left_table,a3
	moveq	#1,d1
	addi.w	#$37,d3
	cmp.w	d3,d0
	bcs.s	collision_check
	moveq	#2,d1
	bra.s	collision_check

collision_right_side:
	move.w	(a0)+,d0
	move.w	$30(a1),d3
	subq.w	#5,d3
	cmp.w	d3,d0
	bcc.s	collision_check
	moveq	#-1,d6
	moveq	#64,d2
	lea	scenery_right_table,a3
	moveq	#1,d1
	subi.w	#$37,d3
	cmp.w	d3,d0
	bcc.s	collision_check
	moveq	#2,d1
collision_check:
	move.w	d1,grapple_side
	beq.w	collision_exit
	lea	scale_tables,a2
	move.w	segment_fraction,d3
	andi.w	#$e0,d3
	lea	$0(a2,d3.w),a2
	lea	line_heights,a4
	lea	course_bytes,a5
	add.b	segment_index+1,d2
	move.b	$0(a5,d2.w),d1
	bne.s	collision_object
	move.b	$1(a5,d2.w),d1
	beq.w	collision_exit
	move.w	$2(a0),d0
	addq.l	#1,a2
	addq.l	#1,a4
collision_object:
	lsl.w	#4,d1
	lea	$0(a3,d1.w),a3
	move.b	$4(a3),d2
	move.b	$5(a3),d3
	move.b	(a2),d1
	ext.w	d2
	ext.w	d1
	mulu.w	d2,d1
	ext.w	d3
	beq.s	collision_left_x
	divu.w	d3,d1
collision_left_x:
	tst.w	d6
	bmi.s	collision_y
	neg.w	d1
	addi.w	#$a,d1
	sub.w	$c(a3),d0
collision_y:
	add.w	d1,d0
	add.w	$6(a3),d0
	move.b	(a4),d2
	andi.w	#$ff,d2
	addi.w	#$38,d2
	move.w	$10(a1),d3
	add.w	$2c(a1),d3
	move.w	d3,d4
	sub.w	$2a(a1),d4
	cmp.w	d4,d2
	bcs.s	collision_exit
	sub.w	$a(a3),d2
	bmi.s	collision_x
	cmp.w	d3,d2
	bcc.s	collision_exit
collision_x:
	moveq	#1,d1
	cmp.w	$30(a1),d0
	bcc.s	collision_exit
	add.w	$8(a3),d0
	cmp.w	$2e(a1),d0
	bcs.s	collision_exit
	cmpi.w	#$a0,d0
	bcs.s	collision_hit
	addq.b	#1,d1
collision_hit:
	move.w	#$4,$3a(a1)
	move.w	d6,$38(a1)
	move.w	speed,d0
	ext.l	d0
	divu.w	#$7,d0
	addi.w	#$12,d0
	move.w	d0,$36(a1)
	move.w	speed,d0
	ext.l	d0
	divu.w	#$3,d0
	move.w	d0,speed
	moveq	#15,d0
	bsr.w	play_sfx
	moveq	#3,d0
	jmp	panel_lose_energy

collision_exit:
	rts


build_roadside_positions:	; from: main_loop
	lea	roadside_row_steps,a0
	movea.l	a0,a1
	move.w	#$14,d7
	move.w	d7,d6
	moveq	#0,d0
positions_sum_loop:
	add.b	(a0),d0
	move.b	d0,(a0)+
	dbra	d7,positions_sum_loop
	lea	roadside_positions,a0
	lea	road_left_edge,a2
	lea	road_right_edge,a3
positions_copy_loop:
	move.b	(a1)+,d0
	lsl.w	#1,d0
	move.w	$0(a2,d0.w),(a0)+
	move.w	$0(a3,d0.w),(a0)+
	dbra	d6,positions_copy_loop
	rts

	dc.w	$ffce,$0000,$ffe2,$0000,$ffec,$0000,$fff6,$0000
	dc.w	$fff8,$0001,$fffc,$0001,$ffff,$0001,$0001,$0001
	dc.w	$0004,$0001,$0008,$0001,$000a,$0001,$0014,$0001
	dc.w	$001e,$0000,$0032,$0000

;----------------------------------------------------------------------
; Draw the grapple line from the Batmobile to the hook with draw_line_segment per row.
;----------------------------------------------------------------------
draw_grapple_line:	; from: draw_batmobile
	movea.l	screen_back,a5
	lea	line_masks,a4
	move.w	$40(a6),d0
	move.w	$4a(a6),d1
	move.w	$42(a6),d2
	move.w	$4c(a6),d3
	sub.w	d0,d1
	move.w	d2,d4
	sub.w	d3,d2
	bcc.s	line_setup
	add.w	d1,d0
	neg.w	d1
	move.w	d3,d4
	neg.w	d2
line_setup:
	move.w	d4,d3
	mulu.w	#$a0,d3
	lea	$0(a5,d3.w),a5
	move.w	d2,d7
	beq.w	line_horizontal
	subq.w	#1,d7
	bmi.s	line_exit
	moveq	#1,d4
	tst.w	d1
	bpl.w	line_steep
	neg.w	d1
	neg.w	d4
line_steep:
	cmp.w	d1,d2
	bcs.s	line_shallow
	move.b	d2,d3
	lsr.b	#1,d3
line_steep_loop:
	add.b	d1,d3
	cmp.b	d2,d3
	bcs.s	line_steep_next
	sub.b	d2,d3
	add.w	d4,d0
line_steep_next:
	lea	-$a0(a5),a5
	dbra	d7,line_steep_step
line_exit:
	rts

line_steep_step:
	add.b	d1,d3
	cmp.b	d2,d3
	bcs.s	line_steep_draw
	sub.b	d2,d3
	add.w	d4,d0
line_steep_draw:
	bsr.w	draw_line_segment
	lea	-$a0(a5),a5
	dbra	d7,line_steep_loop
	rts

line_shallow:
	moveq	#0,d3
line_shallow_loop:
	bsr.w	draw_line_segment
	add.w	d4,d0
	add.b	d2,d3
	bcs.s	line_shallow_next
	cmp.b	d1,d3
	bcs.s	line_shallow_step
line_shallow_next:
	sub.b	d1,d3
	lea	-$a0(a5),a5
	dbra	d7,line_shallow_step
	rts

line_shallow_step:
	add.w	d4,d0
	add.b	d2,d3
	bcs.s	line_shallow_next_row
	cmp.b	d1,d3
	bcs.s	line_shallow_loop
line_shallow_next_row:
	sub.b	d1,d3
	lea	-$a0(a5),a5
	dbra	d7,line_shallow_loop
	rts

line_horizontal:
	moveq	#2,d2
	tst.w	d1
	beq.s	line_horizontal_exit
	bpl.s	line_horizontal_setup
	neg.w	d2
	neg.w	d1
line_horizontal_setup:
	lsr.w	#1,d1
	subq.w	#1,d1
line_horizontal_loop:
	bsr.w	draw_line_segment
	add.w	d2,d0
	dbra	d1,line_horizontal_loop
line_horizontal_exit:
	rts


draw_line_segment:	; from: draw_grapple_line
	move.w	d0,d6
	lsl.w	#2,d6
	andi.w	#$3c,d6
	lea	$0(a4,d6.w),a2
	move.w	d0,d6
	lsr.w	#1,d6
	andi.w	#$fff8,d6
	lea	$0(a5,d6.w),a3
	move.l	$40(a2),d6
	not.l	d6
	cmpi.w	#$130,d0
	bcc.w	segment_right_edge
	and.w	d6,$8(a3)
	and.w	d6,$a(a3)
	and.w	d6,$c(a3)
	and.w	d6,$e(a3)
	and.w	d6,$a8(a3)
	and.w	d6,$aa(a3)
	and.w	d6,$ac(a3)
	and.w	d6,$ae(a3)
	swap	d6
	and.w	d6,(a3)
	and.w	d6,$2(a3)
	and.w	d6,$4(a3)
	and.w	d6,$6(a3)
	and.w	d6,$a0(a3)
	and.w	d6,$a2(a3)
	and.w	d6,$a4(a3)
	and.w	d6,$a6(a3)
	move.l	(a2),d5
	or.w	d5,$8(a3)
	swap	d5
	or.w	d5,(a3)
	move.l	$40(a2),d5
	or.w	d5,$a(a3)
	swap	d5
	or.w	d5,$2(a3)
	move.l	$80(a2),d5
	or.w	d5,$c(a3)
	swap	d5
	or.w	d5,$4(a3)
	move.l	$c0(a2),d5
	or.w	d5,$e(a3)
	swap	d5
	or.w	d5,$6(a3)
	lea	$a0(a3),a3
	lea	$100(a2),a2
	move.l	(a2),d5
	or.w	d5,$8(a3)
	swap	d5
	or.w	d5,(a3)
	move.l	$40(a2),d5
	or.w	d5,$a(a3)
	swap	d5
	or.w	d5,$2(a3)
	move.l	$80(a2),d5
	or.w	d5,$c(a3)
	swap	d5
	or.w	d5,$4(a3)
	move.l	$c0(a2),d5
	or.w	d5,$e(a3)
	swap	d5
	or.w	d5,$6(a3)
segment_exit:
	rts

segment_right_edge:
	cmpi.w	#$140,d0
	bcc.s	segment_exit
	swap	d6
	and.w	d6,(a3)
	and.w	d6,$2(a3)
	and.w	d6,$4(a3)
	and.w	d6,$6(a3)
	and.w	d6,$a0(a3)
	and.w	d6,$a2(a3)
	and.w	d6,$a4(a3)
	and.w	d6,$a6(a3)
	move.w	(a2),d5
	or.w	d5,(a3)
	move.w	$40(a2),d5
	or.w	d5,$2(a3)
	move.w	$80(a2),d5
	or.w	d5,$4(a3)
	move.w	$c0(a2),d5
	or.w	d5,$6(a3)
	lea	$a0(a3),a3
	lea	$100(a2),a2
	move.w	(a2),d5
	or.w	d5,(a3)
	move.w	$40(a2),d5
	or.w	d5,$2(a3)
	move.w	$80(a2),d5
	or.w	d5,$4(a3)
	move.w	$c0(a2),d5
	or.w	d5,$6(a3)
	rts


;----------------------------------------------------------------------
; Draw the hook sprite at the end of the grapple line.
;----------------------------------------------------------------------
draw_grapple_hook:	; from: draw_batmobile
	lea	vehicle,a6
	move.w	$3c(a6),d0
	beq.s	hook_exit
	cmpi.w	#$3,d0
	beq.s	hook_exit
	lea	$2c6c0,a5                       ; level2_gfx +$1c288
	move.w	$54(a6),d1
	add.w	$4e(a6),d1
	move.w	$4a(a6),d0
	move.w	$4c(a6),d2
	addq.w	#6,d2
	subq.w	#6,d0
	lsl.w	#4,d1
	lea	$0(a5,d1.w),a5
	move.w	(a5)+,d1
	cmpi.w	#$140,d0
	bcs.s	hook_draw
	bpl.s	hook_exit
	add.w	d0,d1
	cmpi.w	#$10,d1
	bgt.s	hook_draw
hook_exit:
	rts

hook_draw:
	moveq	#0,d3
	move.w	d3,d6
	move.w	(a5)+,d4
	move.w	(a5)+,d5
	move.w	(a5)+,d7
	movea.l	(a5)+,a4
	movea.l	(a5),a6
	move.w	d0,d1
	andi.w	#$e,d1
	lsl.w	#2,d1
	lea	$0(a4,d1.w),a4
	add.w	(a4)+,d5
	add.w	(a4)+,d4
	movea.l	(a4),a5
	bra.w	scaled_rows


;----------------------------------------------------------------------
; Level 2 grapple: fire near a corner lamp post hooks the Batmobile round the bend.
;----------------------------------------------------------------------
grapple_control:	; from: vehicle_control
	move.w	$3c(a6),d0
	bne.s	grapple_state
	tst.b	joy1_fire
	bne.s	grapple_fire
grapple_exit:
	rts

grapple_fire:
	cmpi.w	#$50,speed
	bcs.s	grapple_exit
	moveq	#9,d0
	bsr.w	play_sfx
	move.w	#$1,$3c(a6)
	move.w	#$e,$44(a6)
	move.w	#$7f,$4c(a6)
	move.w	#$7f,$42(a6)
	move.l	#$4772,$46(a6)
	move.w	#$7e,d0
	moveq	#0,d1
	btst	#$2,d5
	bne.s	grapple_set
	btst	#$3,d5
	bne.s	grapple_right
	cmpi.w	#$16d,road_position
	bcc.s	grapple_set
grapple_right:
	move.w	#$c0,d0
	moveq	#2,d1
grapple_set:
	move.w	d0,$4a(a6)
	move.w	d0,$40(a6)
	move.w	d1,$4e(a6)
grapple_state:
	cmpi.w	#$2,d0
	beq.w	grapple_swing
	cmpi.w	#$3,d0
	beq.w	grapple_retract
	subq.w	#1,$44(a6)
	bpl.s	grapple_extend
	move.w	#$0,$3c(a6)
	bra.w	grapple_extend_exit

grapple_extend:
	movea.l	$46(a6),a0
	move.w	(a0)+,d0
	tst.w	$4e(a6)
	beq.s	grapple_extend_x
	neg.w	d0
grapple_extend_x:
	add.w	d0,$4a(a6)
	move.w	(a0)+,$54(a6)
	move.l	a0,$46(a6)
	lea	course_bytes,a0
	move.w	segment_index,d0
	moveq	#0,d6
	addi.b	#$40,d0
	move.w	road_right_far,d1
	addi.w	#$24,d1
	tst.w	$4e(a6)
	bne.s	grapple_find_post
	addi.b	#$20,d0
	move.w	road_left_far,d1
	subi.w	#$24,d1
grapple_find_post:
	cmpi.b	#$1,$0(a0,d0.w)
	beq.s	grapple_post_check
	tst.b	speed
	beq.s	grapple_extend_exit
	move.b	speed+1,d2
	bmi.s	grapple_post_next
	cmp.b	segment_fraction+1,d2
	bcc.s	grapple_extend_exit
grapple_post_next:
	addi.b	#$1,d0
	cmpi.b	#$1,$0(a0,d0.w)
	bne.s	grapple_extend_exit
	moveq	#1,d6
grapple_post_check:
	tst.w	d1
	bmi.w	grapple_extend_exit
	move.w	d1,d2
	sub.w	$40(a6),d2
	tst.w	$4e(a6)
	bne.s	grapple_post_right
	cmpi.w	#$65,d1
	bcc.s	grapple_extend_exit
	neg.w	d2
	cmp.w	$4a(a6),d1
	bcc.s	grapple_hooked
grapple_extend_exit:
	rts

grapple_post_right:
	cmpi.w	#$d9,d1
	bcs.s	grapple_extend_exit
	cmp.w	$4a(a6),d1
	bcc.s	grapple_extend_exit
grapple_hooked:
	move.w	d1,$4a(a6)
	move.w	#$2,$3c(a6)
	move.w	d2,$50(a6)
	moveq	#0,d5
	move.w	d5,d0
	tst.w	d6
	beq.s	grapple_swing_setup
	move.w	#$fb,d0
grapple_swing_setup:
	move.w	speed,d1
	move.w	d1,speed_saved
	move.w	d0,speed
	move.w	d5,$4(a6)
	move.w	d5,$2(a6)
	move.w	d5,joy_state
	divu.w	#$a4,d1
	mulu.w	#$19,d1
	addi.w	#$32,d1
	move.w	#$4e,$44(a6)
	move.w	d1,$56(a6)
	move.w	d1,$52(a6)
	move.w	#$c0,segment_fraction
	move.w	#$1,$54(a6)
	moveq	#0,d6
	tst.w	$4e(a6)
	beq.s	grapple_swing_dir
	moveq	#-1,d6
grapple_swing_dir:
	move.w	d6,$38(a6)
	move.w	speed_saved,d0
	ext.l	d0
	divu.w	#$9,d0
	addq.w	#3,d0
	move.w	d0,$36(a6)
	moveq	#14,d0
	bra.w	play_sfx

grapple_swing:
	move.w	$52(a6),d0
	move.w	$44(a6),d7
	move.w	d0,d1
	mulu.w	#$13a,d1
	divu.w	#$3e8,d1
	mulu.w	d1,d1
	divu.w	#$5,d1
	andi.l	#$ffff,d1
	divu.w	#$64,d1
	move.w	d1,$46(a6)
	cmp.w	$50(a6),d1
	bcc.s	grapple_release
	tst.w	$4e(a6)
	beq.s	swing_left
	addi.w	#$c0,d1
	move.w	road_right_far,d4
	addi.w	#$24,d4
	bra.s	swing_position

swing_left:
	neg.w	d1
	addi.w	#$7e,d1
	move.w	road_left_far,d4
	subi.w	#$24,d4
swing_position:
	move.w	d1,$40(a6)
	move.w	d4,$4a(a6)
	move.w	d0,d2
	mulu.w	d7,d2
	divu.w	#$e,d2
	andi.l	#$ffff,d2
	divu.w	#$64,d2
	neg.w	d2
	addi.w	#$7f,d2
	move.w	d2,$42(a6)
	add.w	$56(a6),d0
	move.w	d0,$52(a6)
	subq.w	#1,d7
	move.w	d7,$44(a6)
swing_hold_speed:
	moveq	#0,d5
	move.w	d5,speed
	move.w	d5,joy_state
	rts

grapple_release:
	move.w	#$3,$3c(a6)
	tst.w	$4e(a6)
	beq.s	release_left
	addi.w	#$c0,d1
	bra.s	release_distance

release_left:
	neg.w	d1
	addi.w	#$7e,d1
release_distance:
	sub.w	$40(a6),d1
	bpl.s	release_store
	neg.w	d1
release_store:
	move.w	d1,$44(a6)
grapple_retract:
	move.w	$44(a6),d0
	addq.w	#2,d0
	move.w	d0,$44(a6)
	move.w	$40(a6),d1
	tst.w	$4e(a6)
	beq.s	retract_left
	add.w	d0,d1
	cmpi.w	#$1a4,d1
	bcc.s	grapple_done
	bra.s	retract_store

retract_left:
	sub.w	d0,d1
	bpl.s	retract_store
	cmpi.w	#$ff9c,d1
	bcs.s	grapple_done
retract_store:
	move.w	d1,$40(a6)
	bra.s	swing_hold_speed

grapple_done:
	move.w	#$0,$3c(a6)
	bsr.w	init_course
	move.w	speed_saved,speed
	lea	$8(sp),sp
	bsr.w	clear_back_screen
	bsr.w	copy_panel_strips
	move.w	#$1,restart_mode
	bra.w	main_loop

skid_table:	; from: update_curve
	dc.w	$0005,$fff4,$0005,$fff8,$0005,$fffc,$0000,$fffe
	dc.w	$0000,$ffff,$0000,$0001,$0000,$0002,$000a,$0004
	dc.w	$000a,$0008
dat_04d14:	; from: update_curve
	dc.w	$000a,$000c,$0010,$0002,$000c,$0004,$0008,$0006
	dc.w	$0004,$0008,$0000,$000a

;----------------------------------------------------------------------
; Vehicle control from joy_state: accelerate/brake, steer; Batwing has its own control.
;----------------------------------------------------------------------
vehicle_control:	; from: main_loop
	lea	vehicle,a6
	tst.w	$3a(a6)
	beq.s	control_timers
	subq.w	#1,$3a(a6)
control_timers:
	tst.w	$32(a6)
	beq.s	control_frame
	subq.w	#1,$32(a6)
control_frame:
	move.w	$22(a6),d0
	addq.w	#1,d0
	andi.w	#$3,d0
	move.w	d0,$22(a6)
	btst	#$0,d0
	beq.s	control_joystick
	addq.w	#1,$24(a6)
	andi.w	#$3,$24(a6)
control_joystick:
	move.w	joy_state,d5
	tst.w	level_end_state
	beq.w	control_vehicle
	moveq	#0,d5
control_vehicle:
	tst.w	is_batwing
	bne.w	batwing_control
	bsr.w	grapple_control
	move.w	$18(a6),d0
	beq.s	control_no_skid
	subq.w	#1,d0
	move.w	d0,$18(a6)
	bne.s	control_skid
	moveq	#16,d0
	bsr.w	play_sfx
control_skid:
	movea.l	$1c(a6),a0
	clr.w	joy_state
	move.w	(a0)+,$16(a6)
	move.w	$10(a6),d0
	add.w	(a0)+,d0
	move.w	d0,$10(a6)
	addi.w	#$7f,d0
	subi.w	#$91,d0
	move.w	d0,$4c(a6)
	move.w	d0,$42(a6)
	move.l	a0,$1c(a6)
	bra.w	control_steer

control_no_skid:
	tst.w	$36(a6)
	beq.s	control_speed
	move.w	$38(a6),d0
	addi.w	#$2,d0
	move.w	d5,d1
	andi.w	#$3,d1
	cmp.w	d5,d1
	beq.s	control_steer
control_speed:
	move.w	d5,d0
	move.w	speed,d2
	move.w	d2,d3
	move.w	#$fffb,d1
	andi.w	#$3,d0
	beq.s	speed_apply
	move.w	#$ffe7,d1
	btst	#$0,d0
	beq.s	speed_apply
	move.w	#$1c3,d1
	move.w	grapple_side,d0
	beq.s	speed_change
	move.w	#$78,d1
	cmpi.w	#$1,d0
	bcs.s	speed_change
	move.w	#$78,d1
speed_change:
	sub.w	d1,d2
	bcc.s	speed_brake
	addi.w	#$118,d1
	bcs.s	speed_decel
	addi.w	#$118,d1
	lsr.w	#6,d1
	ori.w	#$1,d1
	bra.s	speed_apply

speed_decel:
	subi.w	#$118,d1
	neg.w	d1
	lsr.w	#6,d1
	ori.w	#$1,d1
	bra.s	speed_apply

speed_brake:
	lsr.w	#6,d1
	ori.w	#$1,d1
	neg.w	d1
speed_apply:
	add.w	d3,d1
	bpl.s	speed_min
	moveq	#0,d1
speed_min:
	cmpi.w	#$1c2,d1
	bcs.s	speed_max
	move.w	#$1c2,d1
speed_max:
	move.w	d1,speed
control_steer:
	move.w	$2(a6),d0
	move.w	$4(a6),d1
	tst.w	$18(a6)
	bne.s	control_physics
	btst	#$2,d5
	bne.s	steer_left
	btst	#$3,d5
	bne.s	steer_right
	subq.w	#2,d0
	bcc.w	steer_centre
	moveq	#0,d0
steer_centre:
	subq.w	#2,d1
	bcc.s	steer_limit
	moveq	#0,d1
	bra.s	steer_limit

steer_right:
	addq.w	#3,d0
	cmpi.w	#$10,d0
	bcs.s	steer_right_apply
	moveq	#16,d0
steer_right_apply:
	sub.w	d0,d1
	bcc.s	steer_limit
	moveq	#0,d1
	bra.s	steer_limit

steer_left:
	addq.w	#3,d1
	cmpi.w	#$10,d1
	bcs.s	steer_left_apply
	moveq	#16,d1
steer_left_apply:
	sub.w	d1,d0
	bcc.s	steer_limit
	move.w	#$0,d0
steer_limit:
	move.w	speed,d2
	lsr.w	#4,d2
	move.w	d2,d3
	lsr.w	#2,d2
	add.w	d3,d2
	cmp.w	d2,d0
	bcs.s	steer_limit_left
	move.w	d2,d0
steer_limit_left:
	cmp.w	d2,d1
	bcs.s	steer_store
	move.w	d2,d1
steer_store:
	move.w	d0,$2(a6)
	move.w	d1,$4(a6)
	move.w	$36(a6),d2
	beq.s	control_physics
	exg	d0,d1
control_physics:
	bsr.w	steer_physics
	moveq	#2,d0
	moveq	#-1,d2
	tst.w	d1
	bpl.s	control_tilt
	neg.w	d1
	neg.w	d2
control_tilt:
	cmpi.w	#$8,d1
	bcs.s	control_spin
	add.w	d2,d0
	cmpi.w	#$10,d1
	bcs.s	control_spin
	add.w	d2,d0
control_spin:
	move.w	d0,$12(a6)
	move.w	$36(a6),d0
	beq.w	control_exit
	ext.l	d0
	move.w	d0,d1
	tst.w	$18(a6)
	bne.s	spin_frame
	mulu.w	#$4,d1
	divu.w	#$5,d1
	move.w	d1,$36(a6)
spin_frame:
	move.w	d0,d1
	lsr.w	#3,d1
	cmpi.w	#$3,d1
	bcs.s	spin_dir
	move.w	#$2,d1
spin_dir:
	addi.w	#$2,d1
	tst.w	$38(a6)
	bmi.s	spin_apply
	neg.w	d1
	addi.w	#$4,d1
	neg.w	d0
spin_apply:
	add.w	d0,road_position
	move.w	d1,$12(a6)
	move.w	#$2,$32(a6)
control_exit:
	rts


;----------------------------------------------------------------------
; Steering physics: the curve pushes the vehicle sideways, steering input moves road_position.
;----------------------------------------------------------------------
steer_physics:	; from: vehicle_control, batwing_control
	moveq	#0,d5
	move.w	$e(a6),d2
	beq.s	physics_steer
	bpl.s	physics_abs_curve
	neg.w	d2
physics_abs_curve:
	move.w	#$5e,d3
	divu.w	d2,d3
	move.w	d3,d2
	move.w	$a(a6),d3
	move.w	segment_fraction,d4
	sub.w	d3,d4
	beq.s	physics_steer
physics_curve_loop:
	sub.w	d2,d4
	bcs.s	physics_curve_push
	addq.w	#1,d5
	add.b	d2,d3
	bcs.s	physics_curve_loop
physics_curve_push:
	tst.w	d5
	beq.s	physics_store_frac
	add.w	d5,$c(a6)
	move.w	d5,d4
	lsl.w	#1,d5
	add.w	d4,d5
	tst.w	$e(a6)
	bpl.s	physics_store_frac
	neg.w	d5
physics_store_frac:
	move.w	d3,$a(a6)
physics_steer:
	add.w	$34(a6),d5
	move.w	#$0,$34(a6)
	sub.w	d0,d1
	add.w	d1,d5
	tst.w	d1
	beq.s	physics_clamp_min
	move.w	d1,d0
	andi.b	#$f,d0
	bne.s	physics_clamp_min
	tst.w	d5
	bpl.s	physics_steer_check
	tst.w	d1
	bmi.s	physics_clamp_min
	tst.w	d5
	bpl.s	physics_clamp_min
	bra.s	physics_skid_sfx

physics_steer_check:
	tst.w	d1
	bpl.s	physics_clamp_min
	tst.w	d5
	bmi.s	physics_clamp_min
physics_skid_sfx:
	move.w	#$2,$32(a6)
physics_clamp_min:
	move.w	#$28,d2
	add.w	road_position,d5
	bmi.s	physics_min
	cmp.w	d2,d5
	bcc.s	physics_clamp_max
physics_min:
	move.w	d2,d5
physics_clamp_max:
	move.w	#$305,d2
	cmp.w	d2,d5
	bcs.s	physics_store
	move.w	d2,d5
physics_store:
	move.w	d5,road_position
	addq.w	#1,$26(a6)
	andi.w	#$3,$26(a6)
	rts


;----------------------------------------------------------------------
; Batwing control: fire + up/down for speed, up/down for height, left/right for roll.
;----------------------------------------------------------------------
batwing_control:	; from: vehicle_control
	tst.w	end_delay
	beq.s	wing_speed
	rts

wing_speed:
	move.w	speed,d2
	move.w	d2,d3
	moveq	#0,d1
	tst.b	joy1_fire
	beq.s	wing_speed_apply
	move.w	d5,d0
	andi.w	#$3,d0
	beq.s	wing_speed_apply
	move.w	#$ffec,d1
	btst	#$0,d0
	beq.s	wing_speed_apply
	move.w	#$200,d1
	sub.w	d1,d2
	bcc.s	wing_brake
	addi.w	#$12c,d1
	bcs.s	wing_decel
	addi.w	#$12c,d1
	lsr.w	#6,d1
	ori.w	#$1,d1
	bra.s	wing_speed_apply

wing_decel:
	subi.w	#$12c,d1
	neg.w	d1
	lsr.w	#6,d1
	ori.w	#$1,d1
	bra.s	wing_speed_apply

wing_brake:
	lsr.w	#6,d1
	ori.w	#$1,d1
	neg.w	d1
wing_speed_apply:
	add.w	d3,d1
	bpl.s	wing_speed_max
	moveq	#120,d1
wing_speed_max:
	cmpi.w	#$1ff,d1
	bcs.s	wing_speed_min
	move.w	#$1ff,d1
wing_speed_min:
	cmpi.w	#$78,d1
	bcc.s	wing_altitude
	moveq	#120,d1
wing_altitude:
	move.w	d1,speed
	lea	course_bytes,a0
	move.w	segment_index,d0
	addi.b	#$20,d0
	moveq	#0,d1
	moveq	#4,d2
wing_ground_loop:
	move.b	$0(a0,d0.w),d3
	bmi.s	wing_ground_add
	asr.b	#1,d3
wing_ground_add:
	add.b	d3,d1
	addq.b	#1,d0
	dbra	d2,wing_ground_loop
	addi.b	#$87,d1
	move.w	d1,$20(a6)
	move.w	$6(a6),d0
	move.w	$8(a6),d1
	tst.b	joy1_fire
	bne.s	wing_level
	btst	#$0,d5
	bne.s	wing_climb
	btst	#$1,d5
	bne.s	wing_dive
wing_level:
	subq.w	#1,d0
	bcc.s	wing_level_apply
	moveq	#0,d0
wing_level_apply:
	subq.w	#1,d1
	bcc.s	wing_pitch_limit
	moveq	#0,d1
	bra.s	wing_pitch_limit

wing_climb:
	move.w	d0,d2
	addq.w	#1,d2
	cmpi.w	#$5,d2
	bcc.s	wing_climb_apply
	move.w	d2,d0
wing_climb_apply:
	sub.w	d0,d1
	bcc.s	wing_pitch_limit
	moveq	#0,d1
	bra.s	wing_pitch_limit

wing_dive:
	move.w	d1,d2
	addq.w	#1,d2
	cmpi.w	#$5,d2
	bcc.s	wing_dive_apply
	move.w	d2,d1
wing_dive_apply:
	sub.w	d1,d0
	bcc.s	wing_pitch_limit
	move.w	#$0,d0
wing_pitch_limit:
	move.w	speed,d2
	lsr.w	#4,d2
	move.w	d2,d3
	lsr.w	#2,d2
	add.w	d3,d2
	bra.s	wing_pitch_store

	dc.w	$b042,$6502,$3002,$b242,$6502,$3202
wing_pitch_store:
	move.w	d0,$6(a6)
	move.w	d1,$8(a6)
	sub.w	d1,d0
	move.w	d0,d1
	add.w	$10(a6),d0
	cmpi.w	#$26,d0
	bcc.s	wing_ground_check
	move.w	#$26,d0
wing_ground_check:
	move.w	$20(a6),d2
	cmp.w	d2,d0
	bcs.s	wing_height_store
	tst.w	$28(a6)
	bne.s	wing_ground_hit
	move.w	#$1,$28(a6)
wing_ground_hit:
	move.w	d2,d0
	subi.w	#$87,d2
	neg.w	d2
	bpl.s	wing_ground_bounce
	moveq	#0,d2
wing_ground_bounce:
	lsr.w	#1,d2
	add.w	$6(a6),d2
	cmpi.w	#$9,d2
	bcs.s	wing_ground_store
	moveq	#9,d2
wing_ground_store:
	move.w	#$0,$6(a6)
	move.w	d2,$8(a6)
wing_height_store:
	move.w	d0,$10(a6)
	moveq	#0,d0
	tst.w	d1
	beq.s	wing_pitch_frame_store
	moveq	#10,d2
	tst.w	d1
	bpl.s	wing_pitch_frame
	moveq	#5,d2
	neg.w	d1
wing_pitch_frame:
	cmpi.w	#$2,d1
	bcs.s	wing_pitch_frame_store
	move.w	d2,d0
wing_pitch_frame_store:
	move.w	d0,$1e(a6)
	move.w	$2(a6),d0
	move.w	$4(a6),d1
	btst	#$2,d5
	bne.s	wing_roll_left
	btst	#$3,d5
	bne.s	wing_roll_right
	subq.w	#3,d0
	bcc.s	wing_roll_centre
	moveq	#0,d0
wing_roll_centre:
	subq.w	#3,d1
	bcc.s	wing_roll_limit
	moveq	#0,d1
	bra.s	wing_roll_limit

wing_roll_right:
	addq.w	#4,d0
	cmpi.w	#$12,d0
	bcs.s	wing_roll_right_apply
	moveq	#18,d0
wing_roll_right_apply:
	sub.w	d0,d1
	bcc.s	wing_roll_limit
	moveq	#0,d1
	bra.s	wing_roll_limit

wing_roll_left:
	addq.w	#4,d1
	cmpi.w	#$12,d1
	bcs.s	wing_roll_left_apply
	moveq	#18,d1
wing_roll_left_apply:
	sub.w	d1,d0
	bcc.s	wing_roll_limit
	move.w	#$0,d0
wing_roll_limit:
	move.w	speed,d2
	lsr.w	#4,d2
	move.w	d2,d3
	lsr.w	#2,d2
	add.w	d3,d2
	bra.s	wing_roll_store

	dc.w	$b042,$6502,$3002,$b242,$6502,$3202
wing_roll_store:
	move.w	d0,$2(a6)
	move.w	d1,$4(a6)
	bsr.w	steer_physics
	moveq	#0,d0
	tst.w	d1
	beq.s	wing_roll_frame_store
	moveq	#3,d2
	tst.w	d1
	bpl.s	wing_roll_frame
	moveq	#1,d2
	neg.w	d1
wing_roll_frame:
	cmpi.w	#$6,d1
	bcs.s	wing_roll_frame_store
	move.w	d2,d0
	cmpi.w	#$c,d1
	bcs.s	wing_roll_frame_store
	addi.w	#$1,d0
wing_roll_frame_store:
	move.w	d0,$12(a6)
	move.w	$36(a6),d0
	beq.w	wing_control_exit
	ext.l	d0
	move.w	d0,d1
	mulu.w	#$4,d1
	divu.w	#$5,d1
	move.w	d1,$36(a6)
	move.w	d0,d1
	lsr.w	#3,d1
	cmpi.w	#$3,d1
	bcs.s	wing_spin_dir
	move.w	#$2,d1
wing_spin_dir:
	addi.w	#$2,d1
	tst.w	$38(a6)
	bmi.s	wing_spin_apply
	neg.w	d1
	addi.w	#$4,d1
	neg.w	d0
wing_spin_apply:
	add.w	d0,road_position
	move.w	d1,$12(a6)
wing_control_exit:
	rts

draw_vehicle_in_order:	; from: draw_roadside
	tst.w	d7
	bne.w	roadside_row_objects
	movem.l	d6-d7/a0-a3,-(sp)
	bsr.s	draw_batmobile
	movem.l	(sp)+,d6-d7/a0-a3
	bra.w	roadside_row_objects


;----------------------------------------------------------------------
; Draw the Batmobile: grapple, body, wheels, skid marks, exhaust smoke.
;----------------------------------------------------------------------
draw_batmobile:	; from: draw_roadside, batwing_control
	lea	vehicle,a6
	move.w	$3c(a6),d0
	cmpi.w	#$2,d0
	bcc.w	batmobile_swinging
	tst.w	d7
	bpl.w	batmobile_exit
	tst.w	d0
	beq.s	batmobile_body
	move.w	$12(a6),d0
	subi.w	#$2,d0
	beq.s	batmobile_draw_grapple
	ext.l	d0
	swap	d0
	move.w	$4e(a6),d1
	lsr.w	#1,d1
	add.w	d0,d1
	bne.s	batmobile_body
batmobile_draw_grapple:
	bsr.w	draw_grapple_line
	bsr.w	draw_grapple_hook
	lea	vehicle,a6
batmobile_body:
	move.w	$12(a6),d1
	add.w	$16(a6),d1
	move.w	d1,d3
	lsl.w	#2,d3
	lea	batmobile_wheel_offsets,a4
	move.w	#$74,d0
	add.w	$0(a4,d3.w),d0
	move.w	#$91,d2
	add.w	$2(a4,d3.w),d2
	lea	$21638,a5                       ; level2_gfx +$11200
	movem.l	d1-d3/a6,-(sp)
	bsr.w	draw_sprite_cleared
	movem.l	(sp)+,d1-d3/a6
	lea	batmobile_body_offsets,a4
	move.w	#$77,d0
	add.w	$0(a4,d3.w),d0
	move.w	$10(a6),d2
	add.w	$2(a4,d3.w),d2
	lea	$10438,a5                       ; level24_gfx +$4838
	bsr.w	draw_sprite_masked
	lea	vehicle,a6
	move.w	$26(a6),d0
	beq.s	batmobile_skid
	subq.w	#1,d0
	andi.w	#$1,d0
	move.w	d0,d1
	move.w	$12(a6),d2
	lsl.w	#1,d2
	add.w	d2,d0
	addi.w	#$1d,d0
	mulu.w	#$f,d1
	addi.w	#$69,d1
	add.w	$16(a6),d1
	lea	$10438,a5                       ; level24_gfx +$4838
	bsr.w	draw_batmobile_part
batmobile_skid:
	lea	vehicle,a6
	tst.w	$18(a6)
	bne.s	batmobile_smoke
	tst.w	speed
	beq.s	batmobile_smoke
	move.w	grapple_side,d0
	beq.s	skid_check_timer
	cmpi.w	#$2,d0
	beq.s	skid_both
	moveq	#1,d2
	cmpi.w	#$16d,road_position
	bcc.s	skid_draw
	moveq	#2,d2
	bra.s	skid_draw

skid_check_timer:
	tst.w	$32(a6)
	beq.s	batmobile_smoke
skid_both:
	moveq	#3,d2
skid_draw:
	move.w	$24(a6),d0
	move.w	$16(a6),d1
	lea	$10438,a5                       ; level24_gfx +$4838
	moveq	#21,d3
	move.w	$12(a6),d4
	beq.s	skid_left
	moveq	#53,d3
	cmpi.w	#$4,d4
	beq.s	skid_left
	moveq	#45,d3
skid_left:
	lsr.w	#1,d2
	bcc.s	skid_right
	movem.l	d0-d3/a5-a6,-(sp)
	add.w	d3,d0
	addq.w	#4,d0
	addi.w	#$4b,d1
	bsr.w	draw_batmobile_part
	movem.l	(sp)+,d0-d3/a5-a6
skid_right:
	lsr.w	#1,d2
	bcc.s	batmobile_smoke
	add.w	d3,d0
	addi.w	#$5a,d1
	bsr.w	draw_batmobile_part
batmobile_smoke:
	move.w	damage_level,d7
	beq.s	batmobile_grapple_front
	lsr.w	#2,d7
	neg.w	d7
	addq.w	#4,d7
	cmpi.w	#$4,d7
	bcs.s	smoke_setup
	moveq	#3,d7
smoke_setup:
	lea	smoke_anims,a0
smoke_loop:
	movem.l	d7/a0,-(sp)
	lea	vehicle,a6
	move.w	(a0),d0
	addq.w	#1,d0
	cmpi.w	#$c,d0
	bne.s	smoke_frame_limit
	bsr.w	random
	andi.w	#$f,d0
	addi.w	#$c,d0
smoke_frame_limit:
	cmpi.w	#$14,d0
	bcs.s	smoke_store
	moveq	#0,d0
smoke_store:
	move.w	d0,(a0)+
	lsr.w	#1,d0
	cmpi.w	#$6,d0
	bcc.s	smoke_next
	move.w	d0,d1
	lsl.w	#2,d1
	move.w	$0(a0,d1.w),d2
	move.w	$2(a0,d1.w),d3
	addi.w	#$27,d0
	move.w	#$87,d1
	add.w	$16(a6),d1
	lea	$10438,a5                       ; level24_gfx +$4838
	bsr.w	draw_smoke_part
smoke_next:
	movem.l	(sp)+,d7/a0
	lea	$1a(a0),a0
	dbra	d7,smoke_loop
batmobile_grapple_front:
	lea	vehicle,a6
	tst.w	$3c(a6)
	beq.w	batmobile_exit
	move.w	$12(a6),d0
	subi.w	#$2,d0
	beq.w	batmobile_exit
	ext.l	d0
	swap	d0
	move.w	$4e(a6),d1
	lsr.w	#1,d1
	add.w	d0,d1
	beq.w	batmobile_exit
	bsr.w	draw_grapple_line
	bra.w	draw_grapple_hook

batmobile_swinging:
	tst.w	d7
	bmi.w	draw_grapple_hook
	moveq	#5,d0
	cmpi.w	#$3,$3c(a6)
	beq.s	swing_frame
	move.w	$50(a6),d1
	move.w	d1,d2
	sub.w	$46(a6),d1
	lsr.w	#2,d2
	move.w	d2,d3
	cmp.w	d2,d1
	bcs.s	swing_frame
	moveq	#4,d0
	add.w	d3,d2
	cmp.w	d2,d1
	bcs.s	swing_frame
	moveq	#3,d0
	add.w	d3,d2
	cmp.w	d2,d1
	bcs.s	swing_frame
	moveq	#2,d0
	add.w	d3,d2
	cmp.w	d2,d1
	bcs.s	swing_frame
	moveq	#1,d0
	add.w	d3,d2
	cmp.w	d2,d1
	bcs.s	swing_frame
	moveq	#0,d0
swing_frame:
	lea	hook_frames_right,a4
	tst.w	$4e(a6)
	bne.s	swing_frame_entry
	lea	hook_frames_left,a4
swing_frame_entry:
	mulu.w	#$e,d0
	lea	$0(a4,d0.w),a4
	cmpi.w	#$3,$3c(a6)
	beq.s	swing_body
	tst.w	(a4)
	bne.s	swing_body
	movem.l	a4/a6,-(sp)
	bsr.w	draw_grapple_line
	movem.l	(sp)+,a4/a6
swing_body:
	move.w	$2(a4),d1
	bmi.s	swing_wheels
	move.w	$40(a6),d0
	move.w	$42(a6),d2
	add.w	$4(a4),d0
	add.w	$6(a4),d2
	movem.l	a4/a6,-(sp)
	lea	$21638,a5                       ; level2_gfx +$11200
	bsr.w	draw_sprite_cleared
	movem.l	(sp)+,a4/a6
swing_wheels:
	move.w	$8(a4),d1
	move.w	$40(a6),d0
	move.w	$42(a6),d2
	add.w	$a(a4),d0
	add.w	$c(a4),d2
	movem.l	a4/a6,-(sp)
	lea	$10438,a5                       ; level24_gfx +$4838
	bsr.w	draw_sprite_masked
	movem.l	(sp)+,a4/a6
	cmpi.w	#$3,$3c(a6)
	beq.s	batmobile_exit
	tst.w	(a4)
	bne.w	draw_grapple_line
batmobile_exit:
	rts


;----------------------------------------------------------------------
; Draw the Batwing shadow / body frame by height.
;----------------------------------------------------------------------
draw_batwing:	; from: draw_roadside
	lea	vehicle,a6
	move.w	$20(a6),d1
	move.w	d1,d2
	sub.w	$10(a6),d1
	lsr.w	#4,d1
	cmpi.w	#$4,d1
	bcs.s	batwing_frame
	move.w	#$4,d1
batwing_frame:
	move.w	d1,d3
	lsl.w	#2,d3
	lea	batwing_frame_offsets,a1
	move.w	#$6a,d0
	add.w	$0(a1,d3.w),d0
	lea	$1fb28,a5                       ; level2_gfx +$f6f0
	bra.w	draw_sprite_cleared


;----------------------------------------------------------------------
; Draw the Batwing level objects: floating balloons, explosions, then the Batwing itself.
;----------------------------------------------------------------------
draw_batwing_objects:	; from: draw_roadside
	lea	floaters,a6
	lea	$1ffc4,a5                       ; level2_gfx +$fb8c
	moveq	#2,d7
floater_loop:
	move.w	$0(a6),d1
	bne.s	floater_check
floater_next:
	lea	$6(a6),a6
	dbra	d7,floater_loop
	bra.s	explosions_draw

floater_check:
	cmpi.w	#$9,d1
	bcs.s	floater_draw
	move.w	#$0,$0(a6)
	bra.s	floater_next

floater_draw:
	addq.w	#1,$0(a6)
	subq.w	#1,d1
	lsr.w	#1,d1
	lea	floater_offsets,a0
	move.w	d1,d3
	lsl.w	#2,d3
	addi.w	#$11,d1
	move.w	$2(a6),d0
	add.w	$0(a0,d3.w),d0
	move.w	$4(a6),d2
	add.w	$2(a0,d3.w),d2
	movem.l	d7/a5-a6,-(sp)
	bsr.w	draw_sprite_masked
	movem.l	(sp)+,d7/a5-a6
	bra.s	floater_next

explosions_draw:
	lea	explosions,a6
	lea	$2be5c,a5                       ; level2_gfx +$1ba24
	moveq	#2,d7
explosion_loop:
	tst.w	$0(a6)
	bne.s	explosion_check
explosion_next:
	lea	$14(a6),a6
	dbra	d7,explosion_loop
	bra.w	batwing_body

explosion_check:
	subq.w	#1,$0(a6)
	move.w	$2(a6),d1
	cmpi.w	#$3,d1
	bcc.s	explosion_pieces
	addq.w	#1,$2(a6)
	move.w	$4(a6),d0
	move.w	$6(a6),d2
	movem.l	d7/a5-a6,-(sp)
	bsr.w	draw_sprite_masked
	movem.l	(sp)+,d7/a5-a6
	bra.s	explosion_next

explosion_pieces:
	move.w	$4(a6),d0
	move.w	$6(a6),d2
	moveq	#5,d1
	subi.w	#$10,$4(a6)
	addi.w	#$10,$6(a6)
	movem.l	d7/a5-a6,-(sp)
	bsr.w	draw_sprite_if_on_screen
	movem.l	(sp)+,d7/a5-a6
	move.w	$8(a6),d0
	move.w	$a(a6),d2
	moveq	#6,d1
	addi.w	#$10,$8(a6)
	addi.w	#$10,$a(a6)
	movem.l	d7/a5-a6,-(sp)
	bsr.w	draw_sprite_if_on_screen
	movem.l	(sp)+,d7/a5-a6
	move.w	$c(a6),d0
	move.w	$e(a6),d2
	moveq	#3,d1
	addi.w	#$10,$c(a6)
	subi.w	#$10,$e(a6)
	movem.l	d7/a5-a6,-(sp)
	bsr.w	draw_sprite_if_on_screen
	movem.l	(sp)+,d7/a5-a6
	move.w	$10(a6),d0
	move.w	$12(a6),d2
	moveq	#4,d1
	subi.w	#$10,$10(a6)
	subi.w	#$10,$12(a6)
	movem.l	d7/a5-a6,-(sp)
	bsr.w	draw_sprite_if_on_screen
	movem.l	(sp)+,d7/a5-a6
	bra.w	explosion_next

batwing_body:
	lea	vehicle,a6
	cmpi.w	#$a,$1e(a6)
	bne.s	batwing_fuselage
	bsr.w	draw_wing_flaps
batwing_fuselage:
	lea	vehicle,a6
	lea	batwing_y_offsets,a5
	move.w	$12(a6),d1
	add.w	$1e(a6),d1
	move.w	d1,d3
	lsl.w	#1,d3
	move.w	$0(a5,d3.w),d2
	move.w	#$62,d0
	add.w	$10(a6),d2
	lea	$10438,a5                       ; level24_gfx +$4838
	bsr.w	draw_sprite_masked
	lea	vehicle,a6
	move.w	$26(a6),d0
	beq.s	batwing_bounce
	move.w	#$7,d2
	move.w	$1e(a6),d1
	beq.s	batwing_tail
	move.w	#$d,d2
	cmpi.w	#$9,d1
	bcc.s	batwing_tail
	move.w	#$a,d2
batwing_tail:
	add.w	d2,d0
	moveq	#30,d1
	bsr.w	draw_wing_part
batwing_bounce:
	lea	vehicle,a6
	move.w	$28(a6),d0
	beq.s	batwing_flaps
	addi.w	#$ffff,d0
	moveq	#0,d1
	bsr.w	draw_wing_part
	lea	vehicle,a6
	move.w	$28(a6),d0
	move.w	d0,d1
	addq.w	#1,d1
	cmpi.w	#$5,d1
	bcs.w	bounce_frame_store
	moveq	#0,d1
bounce_frame_store:
	move.w	d1,$28(a6)
	addi.w	#$ffff,d0
	moveq	#15,d1
	bsr.w	draw_wing_part
batwing_flaps:
	lea	vehicle,a6
	cmpi.w	#$a,$1e(a6)
	beq.s	batwing_end_check
	bsr.s	draw_wing_flaps
batwing_end_check:
	tst.w	end_delay
	beq.s	batwing_draw_exit
	subq.w	#1,end_delay
	bne.s	end_balloons_setup
	move.w	#$2,level_end_state
end_balloons_setup:
	lea	end_balloon_anims,a1
	moveq	#5,d7
end_balloon_loop:
	movem.l	d7/a1,-(sp)
	move.w	(a1),d0
	addq.w	#1,d0
	cmpi.w	#$c,d0
	bcs.s	end_balloon_store
	moveq	#5,d0
	bsr.w	play_sfx
	moveq	#0,d0
end_balloon_store:
	move.w	d0,(a1)+
	cmpi.w	#$4,d0
	bcc.s	end_balloon_next
	move.w	d0,d1
	addi.w	#$11,d0
	lea	$1ffc4,a5                       ; level2_gfx +$fb8c
	lea	vehicle,a6
	bsr.s	draw_part
end_balloon_next:
	movem.l	(sp)+,d7/a1
	lea	$12(a1),a1
	dbra	d7,end_balloon_loop
batwing_draw_exit:	; from: draw_wing_flaps
	rts


draw_wing_flaps:	; from: draw_batwing_objects
	move.w	damage_level,d3
	beq.s	batwing_draw_exit
	move.w	$22(a6),d0
	addq.w	#4,d0
	moveq	#45,d1
	movem.l	d0-d3/a6,-(sp)
	bsr.s	draw_flap_part
	movem.l	(sp)+,d0-d3/a6
	moveq	#60,d1
	bra.s	draw_flap_part


draw_wing_part:	; from: draw_batwing_objects
	lea	$1ffc4,a5                       ; level2_gfx +$fb8c
	add.w	$1e(a6),d1

draw_batmobile_part:	; from: draw_batmobile
	add.w	$12(a6),d1
	lea	part_offsets,a1

draw_part:	; from: draw_batwing_objects
	lsl.w	#4,d0
	lsl.w	#2,d1
	lea	$2(a5,d0.w),a5
	move.w	(a5)+,d4
	move.w	(a5)+,d5
	move.w	(a5)+,d7
part_position:	; from: draw_flap_part
	move.w	#$62,d0
	move.w	$0(a1,d1.w),d2
	cmpi.w	#$64,d2
	beq.s	part_exit
	add.w	d2,d0
	move.w	$10(a6),d2
	add.w	$2(a1,d1.w),d2
	moveq	#0,d3
	move.w	d3,d6
	bra.w	masked_relative

part_exit:
	rts


draw_flap_part:	; from: draw_wing_flaps
	lea	$1ffc4,a5                       ; level2_gfx +$fb8c
	add.w	$1e(a6),d1
	add.w	$12(a6),d1
	lea	part_offsets,a1
	lsl.w	#4,d0
	lsl.w	#2,d1
	lea	$2(a5,d0.w),a5
	move.w	(a5)+,d4
	move.w	(a5)+,d5
	move.w	(a5)+,d7
	sub.w	d3,d7
	bra.s	part_position


draw_smoke_part:	; from: draw_batmobile
	add.w	$12(a6),d1
	lea	part_offsets,a1
	lsl.w	#4,d0
	lsl.w	#2,d1
	lea	$2(a5,d0.w),a5
	move.w	(a5)+,d4
	move.w	(a5)+,d5
	move.w	(a5)+,d7
	move.w	#$62,d0
	add.w	d2,d0
	move.w	$0(a1,d1.w),d2
	cmpi.w	#$64,d2
	beq.s	smoke_part_exit
	add.w	d2,d0
	move.w	$10(a6),d2
	add.w	d3,d2
	add.w	$2(a1,d1.w),d2
	moveq	#0,d3
	move.w	d3,d6
	bra.w	masked_relative

smoke_part_exit:
	rts


draw_sprite_cleared:	; from: draw_batmobile, draw_batwing
	lsl.w	#4,d1
	lea	$0(a5,d1.w),a5
	move.w	(a5)+,d1
	cmpi.w	#$140,d0
	bcs.s	cleared_draw
	bpl.s	cleared_exit
	add.w	d0,d1
	bpl.s	cleared_draw
cleared_exit:
	rts

cleared_draw:
	moveq	#0,d3
	move.w	(a5)+,d4
	move.w	(a5)+,d5
	move.w	(a5)+,d7
	lea	blit_clear_rows,a6
	bra.w	sprite_relative_data


draw_sprite_if_on_screen:	; from: draw_batwing_objects
	cmpi.w	#$98,d2
	bcs.s	draw_sprite_masked
	rts


draw_sprite_masked:	; from: draw_batmobile, draw_batwing_objects, draw_sprite_if_on_screen
	lsl.w	#4,d1
	lea	$0(a5,d1.w),a5
	move.w	(a5)+,d1
	cmpi.w	#$140,d0
	bcs.s	masked_draw
	bpl.s	masked_exit
	add.w	d0,d1
	cmpi.w	#$10,d1
	bgt.s	masked_draw
masked_exit:
	rts

masked_draw:
	moveq	#0,d3
	move.w	d3,d6
	move.w	(a5)+,d4
	move.w	(a5)+,d5
	move.w	(a5)+,d7
masked_relative:	; from: draw_part, draw_smoke_part
	move.l	(a5),d1
	adda.l	d1,a5
	lea	blit_rows,a6
	bra.w	scaled_rows

hook_frames_left:	; from: draw_batmobile
	dc.w	$0000,$000c,$fffb,$000c,$000c,$fffe,$000a,$0001
	dc.w	$000b,$fffb,$000e,$000b,$fffe,$000c,$0001,$000a
	dc.w	$fff7,$0010,$000a,$fffa,$000e,$0001,$ffff,$0000
	dc.w	$0000,$0012,$ffec,$000e,$0001,$ffff,$0000,$0000
	dc.w	$0013,$ffdc,$000e,$0001,$ffff,$0000,$0000,$0014
	dc.w	$ffc6,$0008
hook_frames_right:	; from: draw_batmobile
	dc.w	$0000,$000c,$ffbc,$000c,$000c,$ffbc,$000a,$0001
	dc.w	$000d,$ffbd,$000e,$000d,$ffbd,$000c,$0001,$000e
	dc.w	$ffb8,$0010,$000e,$ffb8,$000e,$0001,$ffff,$0000
	dc.w	$0000,$000f,$ffb2,$000e,$0001,$ffff,$0000,$0000
	dc.w	$0010,$ffb4,$000e,$0001,$ffff,$0000,$0000,$0011
	dc.w	$ffb6,$0008
batmobile_body_offsets:	; from: draw_batmobile
	dc.w	$0000,$0000,$0006,$0000,$0007,$0000,$0006,$0000
	dc.w	$0003,$0000,$0000,$0002,$0005,$0001,$0007,$0002
	dc.w	$0006,$0001,$0003,$0002,$0000,$fffe,$0006,$fffd
	dc.w	$0007,$fffd,$0006,$fffd,$0003,$fffe
batmobile_wheel_offsets:	; from: draw_batmobile
	dc.w	$0000,$0002,$0006,$0001,$0007,$0001,$0006,$0001
	dc.w	$0004,$0002,$0000,$0003,$0005,$0002,$0007,$0002
	dc.w	$0006,$0002,$0003,$0003,$0000,$0000,$0006,$ffff
	dc.w	$0007,$ffff,$0006,$ffff,$0004,$0000
batwing_y_offsets:	; from: draw_batwing_objects
	dc.w	$fffd,$ffff,$ffff,$ffff,$0000,$fffb,$fffc,$fffd
	dc.w	$fffc,$fffd,$fff8,$fff9,$fffb,$fff9,$fffb
part_offsets:	; from: draw_batmobile_part, draw_flap_part, draw_smoke_part
	dc.w	$0020,$0000,$0064,$0000,$0064,$0000,$0022,$0001
	dc.w	$0024,$0002,$0022,$fffe,$0064,$0000,$0064,$0000
	dc.w	$0022,$0000,$0024,$0001,$0020,$fffa,$0064,$0000
	dc.w	$0064,$0000,$0022,$fffb,$0024,$fffc,$0040,$0000
	dc.w	$0040,$0001,$0040,$0002,$0064,$0000,$0064,$0000
	dc.w	$0040,$fffe,$0040,$0000,$0040,$0001,$0064,$0000
	dc.w	$0064,$0000,$0040,$fffa,$0040,$fffb,$0040,$fffc
	dc.w	$0064,$0000,$0064,$0000,$0030,$fff3,$0030,$fff3
	dc.w	$0030,$fff3,$0030,$fff3,$0030,$fff3,$0030,$fff7
	dc.w	$0030,$fff7,$002f,$fff7,$0030,$fff7,$0031,$fff7
	dc.w	$0030,$ffec,$0030,$ffec,$0030,$ffec,$0030,$ffec
	dc.w	$0030,$ffec,$0010,$ffeb,$0010,$ffe7,$0010,$ffe4
	dc.w	$0010,$ffef,$0010,$fff2,$0010,$ffe9,$0010,$ffe5
	dc.w	$0010,$ffe2,$0010,$ffed,$0010,$fff0,$0010,$ffeb
	dc.w	$0010,$ffe7,$0010,$ffe4,$0010,$ffef,$0010,$fff2
	dc.w	$0052,$ffeb,$0052,$ffef,$0052,$fff2,$0052,$ffe7
	dc.w	$0052,$ffe4,$0052,$ffe9,$0052,$ffed,$0052,$fff0
	dc.w	$0052,$ffe5,$0052,$ffe2,$0052,$ffeb,$0052,$ffef
	dc.w	$0052,$fff2,$0052,$ffe7,$0052,$ffe4,$000e,$0000
	dc.w	$0008,$0000,$0004,$0000,$0000,$0000,$000c,$0000
	dc.w	$000e,$0003,$0008,$0003,$0004,$0003,$0000,$0003
	dc.w	$000c,$0003,$000e,$ffff,$0008,$ffff,$0004,$ffff
	dc.w	$0000,$ffff,$000c,$ffff,$0060,$0000,$005c,$0000
	dc.w	$005a,$0000,$0056,$0000,$0050,$0000,$0060,$0003
	dc.w	$005c,$0003,$005a,$0003,$0056,$0003,$0050,$0003
	dc.w	$0060,$ffff,$005c,$ffff,$005a,$ffff,$0056,$ffff
	dc.w	$0050,$ffff,$0045,$fffe,$003f,$fffe,$0039,$fffe
	dc.w	$0034,$fffe,$0030,$fffe,$0045,$0000,$003f,$0000
	dc.w	$0039,$0000,$0034,$0000,$0030,$0000,$0045,$fffb
	dc.w	$003f,$fffb,$0039,$fffb,$0034,$fffb,$0030,$fffb
	dc.w	$0044,$ffff,$002e,$ffff,$0039,$fffe,$0033,$ffff
	dc.w	$001f,$ffff,$0044,$0001,$002e,$0001,$0039,$0000
	dc.w	$0033,$0001,$001f,$0001,$0044,$fffc,$002e,$fffc
	dc.w	$0039,$fffb,$0033,$fffc,$001f,$fffc,$0048,$fff0
	dc.w	$0043,$fff0,$003d,$fff0,$0038,$fff0,$0033,$fff0
	dc.w	$0048,$fff2,$0043,$fff2,$003d,$fff2,$0038,$fff2
	dc.w	$0033,$fff2,$0048,$ffeb,$0043,$ffeb,$003d,$ffeb
	dc.w	$0038,$ffeb,$0033,$ffeb
end_balloon_anims:	; from: draw_batwing_objects
	dc.w	$0003,$0010,$fff4,$0010,$fff8,$0000,$fffc,$0000
	dc.w	$0000,$0007,$0024,$ffee,$0024,$fff2,$0014,$fff6
	dc.w	$0014,$fffa,$000a,$0038,$fffc,$0038,$0000,$0028
	dc.w	$0004,$0028,$0008,$0002,$004c,$fffe,$004c,$0002
	dc.w	$003c,$0006,$003c,$000a,$0005,$0042,$fff0,$0042
	dc.w	$fff4,$0032,$fff8,$0032,$fffc,$0000,$001a,$0002
	dc.w	$001a,$0006,$000a,$000a,$000a,$000e
floater_offsets:	; from: draw_batwing_objects
	dc.w	$0010,$fff4,$0010,$fff8,$0000,$fffc,$0000,$0000
batwing_frame_offsets:	; from: draw_batwing
	dc.w	$0000,$0000,$0010,$0000,$0010,$0000,$0010,$0000
	dc.w	$0010,$0000
smoke_anims:	; from: draw_batmobile
	dc.w	$0008,$fffe,$0000,$fffc,$0000,$fff8,$0002,$fff6
	dc.w	$0004,$fff5,$0006,$fff4,$0008,$000c,$ffee,$0008
	dc.w	$ffec,$0008,$ffe8,$000a,$ffe6,$000c,$ffe5,$000e
	dc.w	$ffe4,$0010,$0005,$000e,$0004,$000c,$0004,$0008
	dc.w	$0006,$0006,$0008,$0005,$000a,$0004,$000c,$0000
	dc.w	$0002,$0006,$0000,$0006,$fffc,$0008,$fffa,$000a
	dc.w	$fff9,$000c,$fff8,$000e

format_decimal:	; from: hud_update, hud_count, restart_level
	moveq	#-1,d1
hundreds_loop:
	addq.b	#1,d1
	subi.w	#$64,d0
	bcc.s	hundreds_loop
	addi.w	#$64,d0
	move.b	d1,d2
	addi.b	#$30,d1
	move.b	d1,(a0)+
	moveq	#-1,d1
tens_loop:
	addq.b	#1,d1
	subi.w	#$a,d0
	bcc.s	tens_loop
	addi.w	#$a,d0
	lsl.b	#4,d2
	or.b	d1,d2
	addi.b	#$30,d1
	move.b	d1,(a0)+
	lsl.w	#4,d2
	or.b	d0,d2
	addi.b	#$30,d0
	move.b	d0,(a0)
	rts


;----------------------------------------------------------------------
; Move along the course by speed: each $100 of fraction is one segment (score 16 per segment).
;----------------------------------------------------------------------
advance_course:	; from: main_loop
	move.w	#$0,segments_moved
	tst.b	speed
	beq.s	course_fraction
	bsr.s	course_step
course_fraction:
	move.w	speed,d0
	add.b	d0,segment_fraction+1
	bcs.s	course_step
	rts


course_step:	; from: advance_course
	move.l	#$10,d0
	pea	next_segment
	jmp	panel_add_score


;----------------------------------------------------------------------
; Advance to the next course segment: read one byte from each of the five course streams.
;----------------------------------------------------------------------
next_segment:	; from: course_step, init_course
	move.w	segment_index,d0
	addq.b	#1,d0
	move.w	d0,segment_index
	addq.w	#1,segments_moved
	addq.w	#1,distance_tick
fill_segment:	; from: next_course_block
	lea	course_bytes,a0
	move.w	segment_index,d0
	addi.b	#$1f,d0
	move.b	curve_count,d1
	subi.b	#$10,d1
	bcc.s	curve_byte
	movea.l	stream_curve,a1
	move.b	(a1)+,d1
	beq.w	next_course_block
	move.l	a1,stream_curve
	subi.b	#$10,d1
curve_byte:
	move.b	d1,curve_count
	andi.b	#$f,d1
	btst	#$3,d1
	beq.s	curve_byte_store
	andi.w	#$7,d1
	neg.b	d1
curve_byte_store:
	asl.b	#1,d1
	move.b	d1,$0(a0,d0.w)
	addi.b	#$20,d0
	move.b	hill_count,d1
	subi.b	#$10,d1
	bcc.s	hill_byte
	movea.l	stream_hill,a1
	move.b	(a1)+,d1
	beq.w	next_course_block
	move.l	a1,stream_hill
	subi.b	#$10,d1
hill_byte:
	move.b	d1,hill_count
	andi.b	#$f,d1
	subq.b	#8,d1
	move.b	d1,$0(a0,d0.w)
	addi.b	#$20,d0
	addi.w	#$1,segment_parity
	andi.w	#$1,segment_parity
	bne.s	roadside_bytes
	move.b	#$0,$0(a0,d0.w)
	addi.b	#$20,d0
	move.b	#$0,$0(a0,d0.w)
	bra.s	event_byte

roadside_bytes:
	move.b	left_count,d1
	subi.b	#$10,d1
	bcc.s	left_byte
	movea.l	stream_left,a1
	move.b	(a1)+,d1
	beq.w	next_course_block
	move.l	a1,stream_left
	subi.b	#$10,d1
left_byte:
	move.b	d1,left_count
	andi.b	#$f,d1
	move.b	d1,$0(a0,d0.w)
	addi.b	#$20,d0
	move.b	right_count,d1
	subi.b	#$10,d1
	bcc.s	right_byte
	movea.l	stream_right,a1
	move.b	(a1)+,d1
	beq.w	next_course_block
	move.l	a1,stream_right
	subi.b	#$10,d1
right_byte:
	move.b	d1,right_count
	andi.b	#$f,d1
	move.b	d1,$0(a0,d0.w)
event_byte:
	addi.b	#$20,d0
	move.b	event_count,d1
	subq.b	#1,d1
	bcc.s	event_repeat
	movea.l	stream_events,a1
	move.b	(a1)+,d1
	beq.w	next_course_block
	subq.b	#1,d1
	move.b	d1,event_count
	move.b	(a1)+,d1
	move.l	a1,stream_events
	cmpi.b	#$40,d1
	bcs.s	event_roadblock
	rol.b	#2,d1
	andi.w	#$3,d1
	subq.w	#1,d1
	move.w	d1,turn_ahead
	bra.s	event_clear

event_roadblock:
	cmpi.b	#$20,d1
	bne.s	event_store
	move.w	#$1,roadblock_due
event_clear:
	moveq	#0,d1
event_store:
	move.b	d1,event_value
	move.b	d1,$0(a0,d0.w)
	bra.s	segment_objects

event_repeat:
	move.b	d1,event_count
	move.b	event_value,$0(a0,d0.w)
segment_objects:
	bsr.w	update_curve
	lea	objects,a0
	moveq	#7,d7
object_age_loop:	; from: object_age_next
	tst.b	$0(a0)
	beq.s	object_age_next
	subq.b	#1,$2(a0)
	bpl.s	object_age_next
	move.b	#$0,$0(a0)
	tst.w	$1a(a0)
	beq.s	object_age_next
	tst.w	$28(a0)
	bne.s	object_age_next
	pea	object_age_next
	moveq	#1,d0
	jmp	panel_lose_energy


object_age_next:	; from: next_segment
	lea	$2a(a0),a0
	dbra	d7,object_age_loop
	rts


;----------------------------------------------------------------------
; Start the next block of the course: five stream pointers (curve, hill, left, right, events).
;----------------------------------------------------------------------
next_course_block:	; from: next_segment, init_course
	movea.l	course_block_ptr,a0
block_follow_link:
	move.l	(a0)+,d0
	bne.s	block_set_streams
	movea.l	(a0),a0
	bra.s	block_follow_link

block_set_streams:
	move.l	d0,stream_curve
	move.l	(a0)+,stream_hill
	move.l	(a0)+,stream_left
	move.l	(a0)+,stream_right
	move.l	(a0)+,stream_events
	move.l	a0,course_block_ptr
	moveq	#0,d0
	move.w	d0,segment_parity
	move.b	d0,curve_count
	move.b	d0,hill_count
	move.b	d0,left_count
	move.b	d0,right_count
	move.b	d0,event_count
	move.b	d0,event_value
	bra.w	fill_segment


;----------------------------------------------------------------------
; Start the course from course_ptr: clear course_bytes and prefill 32 segments.
;----------------------------------------------------------------------
init_course:	; from: reset_level_vars, grapple_control
	movea.l	course_ptr,a0
course_follow_link:
	move.l	(a0)+,d0
	bne.s	course_start
	movea.l	(a0),a0
	bra.s	course_follow_link

course_start:
	move.l	d0,course_block_ptr
	move.l	a0,course_ptr
	moveq	#0,d0
	move.w	d0,segment_index
	move.w	d0,segment_fraction
	lea	course_bytes,a0
	move.w	#$3f,d7
clear_course_loop:
	move.l	d0,(a0)+
	dbra	d7,clear_course_loop
	bsr.w	next_course_block
	moveq	#31,d7
prefill_loop:
	move.w	d7,-(sp)
	bsr.w	next_segment
	move.w	(sp)+,d7
	dbra	d7,prefill_loop
	lea	roadside_left,a0
	move.w	$8(a0),d1
	movea.l	a0,a1
	moveq	#15,d7
clear_roadside_loop:
	move.w	#$0,(a0)+
	dbra	d7,clear_roadside_loop
	move.w	#$58,$6(a1)
	addi.w	#$28,d1
	cmpi.w	#$a0,d1
	bcs.s	roadside_wrap
	subi.w	#$a0,d1
roadside_wrap:
	move.w	d1,$8(a1)
	move.w	d1,$18(a1)
	move.w	#$16d,road_position
	rts

	dc.w	$ffff,$ffff,$7f7f
	dc.b	$55
strip_shift_left:	; from: update_curve
	dc.b	$55,$00,$00,$01,$01,$02,$02,$03
strip_curve_right:	; from: update_roadside_strips
	dc.b	$03,$ff,$ff,$ff,$ff,$ff,$ff,$7f
strip_shift_right:	; from: update_curve
	dc.b	$7f
strip_scroll_right:	; from: update_roadside_strips, update_curve
	dc.w	$0000,$0101,$0202,$0303,$0401,$0301,$0201,$0101
	dc.w	$0301,$0201,$0201,$0102
strip_scroll_left:	; from: update_roadside_strips, update_curve
	dc.w	$0201,$0102,$0103,$0104,$0201,$0101,$0102,$0102
	dc.w	$0101,$0102,$0102,$0104,$0102,$0104,$0104,$0106

;----------------------------------------------------------------------
; Scroll the two roadside strips (far scenery) with the curve.
;----------------------------------------------------------------------
update_roadside_strips:	; from: main_loop
	lea	roadside_left,a0
	lea	strip_scroll_left,a1
	lea	strip_curve_left,a2
	move.w	#$a0,d7
	bsr.s	roadside_strip
	move.w	$6(a0),d0
	move.w	d0,-(sp)
	lea	roadside_right,a0
	lea	strip_scroll_right,a1
	lea	strip_curve_right,a2
	move.w	#$140,d7
	bsr.s	roadside_strip
	move.w	(sp)+,d0
	subi.w	#$58,d0
	asr.w	#1,d0
	addi.w	#$6e,d0
	move.w	d0,$6(a0)
	rts


roadside_strip:	; from: update_roadside_strips
	move.w	speed,d0
	bne.s	strip_active
	rts

strip_active:
	tst.w	$e(a0)
	beq.w	strip_apply_curve
	subq.w	#1,$c(a0)
	bne.s	strip_apply_curve
	lsr.w	#5,d0
	andi.w	#$fe,d0
	add.w	$a(a0),d0
	moveq	#0,d1
	move.b	$0(a1,d0.w),d1
	move.w	d1,$c(a0)
	move.b	$1(a1,d0.w),d1
	tst.w	$e(a0)
	bmi.w	strip_scroll_add
	neg.w	d1
strip_scroll_add:
	add.w	$8(a0),d1
	bpl.s	strip_wrap_high
	add.w	d7,d1
	bra.s	strip_store_scroll

strip_wrap_high:
	cmp.w	d7,d1
	bcs.s	strip_store_scroll
	sub.w	d7,d1
strip_store_scroll:
	move.w	d1,$8(a0)
strip_apply_curve:
	move.w	$2(a0),d0
	beq.s	strip_exit
	bpl.s	strip_curve_abs
	neg.w	d0
strip_curve_abs:
	move.b	$0(a2,d0.w),d0
	move.w	segment_fraction,d1
	sub.w	$4(a0),d1
	beq.s	strip_exit
	moveq	#0,d2
	move.w	d2,d3
strip_curve_loop:
	sub.b	d0,d1
	bcs.s	strip_curve_apply
	addq.w	#1,d2
	add.w	d0,d3
	bra.s	strip_curve_loop

strip_curve_apply:
	tst.w	d2
	beq.s	strip_exit
	add.w	d2,$0(a0)
	tst.w	$2(a0)
	bpl.s	strip_curve_store
	neg.w	d2
strip_curve_store:
	add.w	d2,$6(a0)
	add.w	d3,$4(a0)
strip_exit:
	rts


;----------------------------------------------------------------------
; Per segment: update the strip curves and the vehicle sideways push, pick a skid animation.
;----------------------------------------------------------------------
update_curve:	; from: next_segment
	lea	course_bytes,a6
	lea	roadside_left,a0
	lea	strip_scroll_left,a2
	lea	strip_shift_left,a3
	bsr.w	strip_curve
	lea	roadside_right,a0
	lea	strip_scroll_right,a2
	lea	strip_shift_right,a3
	bsr.w	strip_curve
	lea	vehicle,a1
	move.w	$e(a1),d0
	bpl.s	curve_abs
	neg.w	d0
curve_abs:
	sub.w	$c(a1),d0
	bcs.s	curve_reset
	beq.s	curve_reset
	move.w	d0,d1
	mulu.w	#$3,d0
	add.w	d1,d0
	tst.w	$e(a1)
	bpl.s	curve_push
	neg.w	d0
curve_push:
	add.w	d0,$34(a1)
curve_reset:
	move.w	#$0,$a(a1)
	move.w	#$0,$c(a1)
	move.w	$e(a0),$e(a1)
	move.w	segment_index,d0
	addi.b	#$21,d0
	moveq	#0,d1
	move.b	$0(a6,d0.w),d0
	beq.s	curve_sign
	moveq	#5,d1
	tst.b	d0
	bmi.s	curve_sign
	moveq	#10,d1
curve_sign:
	move.w	d1,$16(a1)
	move.w	$1a(a1),d1
	bpl.s	curve_store_sign
	tst.b	d0
	bmi.s	curve_store_sign
	neg.w	d1
	subq.w	#2,d1
	bcs.s	curve_store_sign
	tst.w	$18(a1)
	bne.s	curve_store_sign
	move.w	speed,d2
	lsr.w	#7,d2
	not.w	d2
	addq.w	#4,d2
	sub.w	d2,d1
	bcs.s	curve_store_sign
	beq.s	curve_store_sign
	lsl.w	#2,d1
	lea	dat_04d14,a2
	lea	$0(a2,d1.w),a2
	move.w	(a2)+,d1
	move.w	(a2),$18(a1)
	lea	skid_table,a2
	lea	$0(a2,d1.w),a2
	move.l	a2,$1c(a1)
curve_store_sign:
	tst.b	d0
	bpl.s	curve_store
	ori.w	#$ff00,d0
curve_store:
	move.w	d0,$1a(a1)
	rts


strip_curve:	; from: update_curve
	move.w	$0(a0),d0
	move.w	$2(a0),d1
	beq.s	strip_next_segment
	bpl.s	strip_abs
	neg.w	d1
strip_abs:
	move.b	$0(a3,d1.w),d1
	sub.w	d0,d1
	beq.s	strip_next_segment
	tst.w	$2(a0)
	bpl.s	strip_add
	neg.w	d1
strip_add:
	add.w	d1,$6(a0)
strip_next_segment:
	move.w	segment_index,d0
	addi.b	#$22,d0
	moveq	#0,d1
	move.w	d1,$4(a0)
	move.w	d1,$0(a0)
	move.b	$0(a6,d0.w),d1
	bpl.s	strip_curve_byte
	ori.w	#$ff00,d1
strip_curve_byte:
	move.w	d1,$2(a0)
	move.w	segment_index,d0
	move.b	$0(a6,d0.w),d0
	bpl.s	strip_hill_byte
	ori.w	#$ff00,d0
strip_hill_byte:
	move.w	d0,$e(a0)
	tst.w	d0
	beq.s	strip_hill_store
	bpl.s	strip_hill_abs
	neg.w	d0
strip_hill_abs:
	asl.w	#2,d0
	move.w	d0,$a(a0)
	tst.w	$c(a0)
	bne.s	strip_curve_exit
	move.w	speed,d1
	lsr.w	#5,d1
	andi.w	#$fe,d1
	add.w	d0,d1
	move.b	$0(a2,d1.w),d0
strip_hill_store:
	move.w	d0,$c(a0)
strip_curve_exit:
	rts


;----------------------------------------------------------------------
; Fill road_edge_q1 / road_centre / road_edge_q3 between the two edges (for the stripes).
;----------------------------------------------------------------------
interpolate_road_edges:	; from: main_loop
	lea	road_left_edge,a1
	lea	road_edge_q1,a2
	lea	road_centre,a3
	lea	road_edge_q3,a4
	lea	road_right_edge,a5
	move.w	#$6f,d7
interpolate_loop:
	move.w	(a1)+,d1
	move.w	(a5)+,d0
	sub.w	d1,d0
	asr.w	#1,d0
	move.w	d0,d2
	add.w	d1,d0
	move.w	d0,(a3)+
	move.w	d2,d1
	asr.w	#1,d2
	add.w	d2,d0
	move.w	d0,(a4)+
	sub.w	d1,d0
	move.w	d0,(a2)+
	dbra	d7,interpolate_loop
	rts


;----------------------------------------------------------------------
; Fill one segment of the road edge table between two rows.
;----------------------------------------------------------------------
road_edge_line:	; from: draw_road
	move.l	a4,d2
	subi.l	#road_width,d2
	cmpi.w	#$15,d2
	bcc.w	edge_exit
	lea	scale_tables,a1
	move.w	segment_fraction,d1
	andi.w	#$e0,d1
	add.b	d2,d1
	move.w	d7,d3
	lsl.w	#1,d3
	btst	#$0,d0
	bne.s	edge_right
	btst	#$1,d0
	bne.s	edge_left_up
	move.b	-$1(a1,d1.w),d1
	lea	$400(a5),a1
	move.w	(a1),d0
	add.w	d1,d0
	move.w	$0(a1,d3.w),d3
	cmpi.w	#$1,d2
	bne.s	edge_left_down
	move.w	segment_fraction,d2
	andi.w	#$e0,d2
	lsr.w	#2,d2
	sub.w	d2,d0
	lsr.w	#2,d2
	sub.w	d2,d0
edge_left_down:
	sub.w	d0,d3
	move.w	d3,d1
	bra.w	edge_fill

edge_left_up:
	move.b	$0(a1,d1.w),d1
	lea	$400(a5),a1
	move.w	(a1),d0
	move.w	$0(a1,d3.w),d3
	add.w	d1,d3
	cmpi.w	#$1,d2
	bne.s	edge_left_up_store
	move.w	segment_fraction,d2
	andi.w	#$e0,d2
	lsr.w	#2,d2
	add.w	d2,d0
	lsr.w	#2,d2
	add.w	d2,d0
edge_left_up_store:
	sub.w	d0,d3
	move.w	d3,d1
	bra.s	edge_fill

edge_right:
	btst	#$1,d0
	bne.s	edge_right_up
	move.w	(a5),d0
	move.b	-$1(a1,d1.w),d1
	sub.w	d1,d0
	move.w	$0(a5,d3.w),d3
	cmpi.w	#$1,d2
	bne.s	edge_right_down_store
	move.w	segment_fraction,d2
	andi.w	#$e0,d2
	lsr.w	#2,d2
	add.w	d2,d0
	lsr.w	#2,d2
	add.w	d2,d0
edge_right_down_store:
	sub.w	d0,d3
	move.w	d3,d1
	movea.l	a5,a1
	bra.s	edge_fill

edge_right_up:
	move.w	(a5),d0
	move.w	$0(a5,d3.w),d3
	move.b	$0(a1,d1.w),d1
	sub.w	d1,d3
	cmpi.w	#$1,d2
	bne.s	edge_right_up_store
	move.w	segment_fraction,d2
	andi.w	#$e0,d2
	lsr.w	#2,d2
	sub.w	d2,d0
	lsr.w	#2,d2
	sub.w	d2,d0
edge_right_up_store:
	sub.w	d0,d3
	move.w	d3,d1
	movea.l	a5,a1
edge_fill:
	cmpi.w	#$2,d7
	bcs.s	edge_single
	move.w	d7,d2
	subq.w	#1,d2
	tst.w	d1
	bpl.s	edge_fill_up
	neg.w	d1
	cmp.w	d1,d7
	bcs.s	edge_fill_down_steep
	move.b	d7,d3
	lsr.b	#1,d3
edge_fill_down_loop:
	add.b	d1,d3
	cmp.b	d7,d3
	bcs.s	edge_fill_down_store
	sub.b	d7,d3
	subq.w	#1,d0
edge_fill_down_store:
	move.w	d0,(a1)+
	dbra	d2,edge_fill_down_loop
edge_exit:
	rts

edge_fill_down_steep:
	moveq	#0,d3
edge_fill_down_steep_loop:
	subq.w	#1,d0
	add.b	d7,d3
	bcs.s	edge_fill_down_steep_store
	cmp.b	d1,d3
	bcs.s	edge_fill_down_steep_loop
edge_fill_down_steep_store:
	sub.b	d1,d3
	move.w	d0,(a1)+
	dbra	d2,edge_fill_down_steep_loop
	rts

edge_fill_up:
	cmp.w	d1,d7
	bcs.w	edge_fill_up_steep
	move.b	d7,d3
	lsr.b	#1,d3
edge_fill_up_loop:
	add.b	d1,d3
	cmp.b	d7,d3
	bcs.s	edge_fill_up_store
	sub.b	d7,d3
	addq.w	#1,d0
edge_fill_up_store:
	move.w	d0,(a1)+
	dbra	d2,edge_fill_up_loop
	rts

edge_fill_up_steep:
	moveq	#0,d3
edge_fill_up_steep_loop:
	addq.w	#1,d0
	add.b	d7,d3
	bcs.s	edge_fill_up_steep_store
	cmp.b	d1,d3
	bcs.s	edge_fill_up_steep_loop
edge_fill_up_steep_store:
	sub.b	d1,d3
	move.w	d0,(a1)+
	dbra	d2,edge_fill_up_steep_loop
	rts

edge_single:
	add.w	d1,d0
	move.w	d0,(a1)+
	rts


;----------------------------------------------------------------------
; Draw the road: one line per screen row from road_left_edge/road_right_edge with stripes.
;----------------------------------------------------------------------
draw_road:	; from: main_loop
	movea.l	screen_back,a0
	lea	$5f00(a0),a0
	lea	line_heights,a4
	lea	road_left_edge,a5
	moveq	#0,d5
	move.l	#$130,d6
	moveq	#96,d7
	sub.b	(a4),d7
	lea	course_bytes,a2
	move.w	segment_index,d4
	move.w	d4,d0
	move.w	d4,d1
	addi.b	#$80,d4
	andi.w	#$1,d0
	move.w	d0,stripe_phase
	andi.w	#$2,d1
	lsr.w	#1,d1
	move.w	d1,stripe_side
	move.w	#$2,stripe_count_down
road_next_segment:
	tst.w	stripe_side
	movea.l	a0,a3
	bne.s	road_segment_byte
	lea	$4(a0),a3
road_segment_byte:
	move.b	$0(a2,d4.w),d0
	andi.w	#$f,d0
	beq.s	road_clear_flags
	btst	#$3,d0
	beq.s	road_edge_segment
	andi.l	#$3,d0
	swap	d0
	or.l	d0,d5
	bra.s	road_rows

road_edge_segment:
	bsr.w	road_edge_line
	movea.l	a0,a3
road_clear_flags:
	andi.l	#$ffff,d5
road_rows:
	subq.b	#1,d7
road_row_loop:
	move.l	#$ffff0000,d0
	moveq	#0,d1
	move.l	d0,d2
	move.l	d1,d3
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	movem.l	d0-d3,-(a0)
	lea	-$a0(a3),a3
	move.w	(a5)+,d1
	btst	#$10,d5
	bne.s	road_left_stripe
	cmp.w	d6,d1
	bcc.s	road_left_stripe
	move.b	d1,d0
	lsl.b	#2,d0
	andi.w	#$3c,d0
	or.w	d5,d0
	lsr.w	#1,d1
	andi.w	#$fff8,d1
	lea	stripe_masks,a6
	move.l	$0(a6,d0.w),d0
	move.w	d0,$a(a3,d1.w)
	swap	d0
	move.w	d0,$2(a3,d1.w)
road_left_stripe:
	tst.w	stripe_side
	bne.w	road_right_edge_line
	tst.w	stripe_phase
	bne.w	road_right_edge_line
	lea	edge_masks,a6
	move.w	$fe(a5),d1
	cmp.w	d6,d1
	bcc.s	road_centre_stripe
	move.b	d1,d0
	lsl.b	#2,d0
	andi.w	#$3c,d0
	or.w	d5,d0
	lsr.w	#1,d1
	andi.w	#$fff8,d1
	move.l	$0(a6,d0.w),d0
	or.w	d0,$a(a0,d1.w)
	swap	d0
	move.w	d0,$2(a0,d1.w)
road_centre_stripe:
	move.w	$1fe(a5),d1
	cmp.w	d6,d1
	bcc.s	road_right_stripe
	move.b	d1,d0
	lsl.b	#2,d0
	andi.w	#$3c,d0
	or.w	d5,d0
	lsr.w	#1,d1
	andi.w	#$fff8,d1
	move.l	$0(a6,d0.w),d0
	or.w	d0,$a(a0,d1.w)
	swap	d0
	move.w	d0,$2(a0,d1.w)
road_right_stripe:
	move.w	$2fe(a5),d1
	cmp.w	d6,d1
	bcc.s	road_right_edge_line
	move.b	d1,d0
	lsl.b	#2,d0
	andi.w	#$3c,d0
	or.w	d5,d0
	lsr.w	#1,d1
	andi.w	#$fff8,d1
	move.l	$0(a6,d0.w),d0
	or.w	d0,$a(a0,d1.w)
	swap	d0
	move.w	d0,$2(a0,d1.w)
road_right_edge_line:
	btst	#$11,d5
	bne.s	road_next_row
	move.w	$3fe(a5),d1
	cmp.w	d6,d1
	bcc.s	road_next_row
	move.b	d1,d0
	lsl.b	#2,d0
	andi.w	#$3c,d0
	or.w	d5,d0
	lsr.w	#1,d1
	andi.w	#$fff8,d1
	lea	stripe_masks,a6
	move.l	$0(a6,d0.w),d0
	or.w	d0,$a(a3,d1.w)
	swap	d0
	move.w	d0,$2(a3,d1.w)
road_next_row:
	addi.l	#$10000,d6                      ; level24_gfx +$4400
	dbra	d7,road_row_loop
	not.w	d7
	bra.s	road_segment_height

road_skip_segment:
	addq.w	#2,a5
road_segment_height:
	bsr.s	stripe_toggle
	addq.b	#1,d4
	move.b	(a4)+,d7
	sub.b	(a4),d7
	beq.s	road_skip_segment
	bpl.s	road_segment_tall
road_segment_hidden:
	bsr.s	stripe_toggle
	move.b	(a4)+,d0
	sub.b	(a4),d0
	cmpi.b	#$e0,d0
	bcc.s	road_segment_add
	cmpi.b	#$50,d0
	bcc.s	draw_scenery
road_segment_add:
	addq.w	#2,a5
	addq.b	#1,d4
	add.b	d0,d7
	beq.s	road_segment_hidden
	bmi.s	road_segment_hidden
	bra.w	road_next_segment

road_segment_tall:
	cmpi.b	#$50,d7
	bcs.w	road_next_segment
	bra.s	draw_scenery


stripe_toggle:	; from: draw_road
	eori.w	#$1,stripe_phase
	bne.s	stripe_count
	eori.w	#$1,stripe_side
stripe_count:
	subq.w	#1,stripe_count_down
	bne.s	stripe_exit
	move.w	#$3,stripe_count_down
	cmpi.w	#$100,d5
	bcc.s	stripe_exit
	addi.w	#$40,d5
stripe_exit:
	rts


;----------------------------------------------------------------------
; Draw the far scenery: left strip, middle (sky) strip and the right strip, each from column tables.
;----------------------------------------------------------------------
draw_scenery:	; from: draw_road
	swap	d6
	move.w	d6,horizon_y
	lea	scenery_columns_left,a1
	lea	roadside_left,a2
	move.w	#$18,d7
	moveq	#0,d1
	move.w	$6(a2),d0
	bmi.w	scenery_mid
	sub.w	d6,d0
	beq.s	scenery_left_draw
	bcs.s	scenery_left_clip
	bra.s	scenery_left_draw

	dc.w	$0240,$000f,$0040,$0001,$dc40,$5340,$7200,$2401
	dc.w	$2601,$2801,$2a01,$2641,$2841,$2a41,$48e0,$7c1c
	dc.w	$48e0,$7c1c,$48e0,$7c1c,$48e0,$7c1c,$48e0,$7c1c
	dc.w	$51c8,$ffea,$7200,$601c
scenery_left_clip:
	add.w	d7,d0
	beq.w	scenery_mid
	bcc.w	scenery_mid
	move.w	d0,d7
	neg.w	d0
	addi.w	#$18,d0
	move.w	d0,d2
	asl.w	#2,d0
	add.w	d2,d0
	asl.w	#4,d0
	move.w	d0,d1
scenery_left_draw:
	add.w	d7,d6
	move.w	d6,-(sp)
	subq.b	#1,d7
	move.w	$8(a2),d0
	move.w	d0,d2
	andi.w	#$e,d2
	asl.w	#1,d2
	movea.l	$0(a1,d2.w),a1
	lea	$0(a1,d1.w),a1
	andi.w	#$fff0,d0
	lsr.w	#2,d0
	lea	scenery_blit_left,a3
	movea.l	$0(a3,d0.w),a4
	movea.l	$28(a3,d0.w),a3
	lsl.w	#1,d0
	neg.w	d0
	addi.w	#$50,d0
scenery_left_loop:
	lea	$0(a1,d0.w),a2
	jsr	(a4)
	movea.l	a1,a2
	jsr	copy_longs_20
	movea.l	a1,a2
	jsr	(a3)
	lea	$50(a1),a1
	lea	-$140(a0),a0
	dbra	d7,scenery_left_loop
	move.w	(sp)+,d6
scenery_mid:
	lea	scenery_columns_mid,a1
	lea	roadside_right,a2
	movem.l	d6/a0,-(sp)
	moveq	#32,d7
	moveq	#0,d1
	move.w	$6(a2),d0
	bmi.w	scenery_sky
	sub.w	d6,d0
	beq.s	scenery_mid_draw
	bcs.s	scenery_mid_clip
	add.w	d0,d6
	subq.w	#1,d0
	moveq	#0,d1
	move.l	d1,d2
	move.l	d1,d3
	move.l	d2,d4
	move.l	d1,d5
	movea.l	d2,a3
	movea.l	d1,a4
	movea.l	d2,a5
	lea	$a0(a0),a0
scenery_clear_loop:
	movem.l	d1-d5/a3-a5,-(a0)
	movem.l	d1-d5/a3-a5,-(a0)
	movem.l	d1-d5/a3-a5,-(a0)
	movem.l	d1-d5/a3-a5,-(a0)
	movem.l	d1-d5/a3-a5,-(a0)
	dbra	d0,scenery_clear_loop
	moveq	#0,d1
	bra.s	scenery_mid_draw

scenery_mid_clip:
	add.w	d7,d0
	beq.w	scenery_sky
	bcc.w	scenery_sky
	move.w	d0,d7
	neg.w	d0
	addi.w	#$20,d0
	move.w	d0,d2
	asl.w	#2,d0
	add.w	d2,d0
	asl.w	#3,d0
	move.w	d0,d1
scenery_mid_draw:
	add.w	d7,d6
	move.w	d6,-(sp)
	cmpi.w	#$97,d6
	bcs.s	scenery_mid_rows
	subi.w	#$98,d6
	sub.w	d6,d7
scenery_mid_rows:
	subq.b	#1,d7
	move.w	$8(a2),d0
	move.w	d0,d2
	andi.w	#$e,d2
	asl.w	#1,d2
	movea.l	$0(a1,d2.w),a1
	lea	$0(a1,d1.w),a1
	andi.w	#$fff0,d0
	lsr.w	#2,d0
	lea	scenery_blit_sky,a3
	movea.l	$0(a3,d0.w),a4
	movea.l	$50(a3,d0.w),a3
	lsr.w	#1,d0
	neg.w	d0
	addi.w	#$28,d0
	movea.w	#$0,a5
scenery_mid_loop:
	lea	$0(a1,d0.w),a2
	jsr	(a4)
	movea.l	a1,a2
	jsr	(a3)
	lea	$28(a1),a1
	lea	-$140(a0),a0
	dbra	d7,scenery_mid_loop
	move.w	(sp)+,d7
	subi.w	#$98,d7
	bcc.s	scenery_sky
	neg.w	d7
	lea	$a0(a0),a0
	move.l	#$ffff0000,d1
	moveq	#0,d2
	move.l	d1,d3
	move.l	d2,d4
	move.l	d1,d5
	movea.l	d2,a3
	movea.l	d1,a4
	movea.l	d2,a5
scenery_fill_loop:
	movem.l	d1-d5/a3-a5,-(a0)
	movem.l	d1-d5/a3-a5,-(a0)
	movem.l	d1-d5/a3-a5,-(a0)
	movem.l	d1-d5/a3-a5,-(a0)
	movem.l	d1-d5/a3-a5,-(a0)
	dbra	d7,scenery_fill_loop
	not.w	d7
	cmpa.l	screen_back,a0
	bne.s	scenery_fill_loop
scenery_sky:
	movem.l	(sp)+,d6/a0
	lea	scenery_columns_sky,a1
	lea	roadside_left,a2
	move.w	#$18,d7
	moveq	#0,d1
	move.w	$6(a2),d0
	addi.w	#$18,d0
	bmi.s	scenery_exit
	sub.w	d6,d0
	bcc.s	scenery_sky_draw
	add.w	d7,d0
	beq.s	scenery_exit
	bcc.s	scenery_exit
	move.w	d0,d7
	neg.w	d0
	addi.w	#$18,d0
	move.w	d0,d2
	asl.w	#4,d0
	sub.w	d2,d0
	asl.w	#3,d0
	move.w	d0,d1
scenery_sky_draw:
	subq.b	#1,d7
	move.w	$8(a2),d0
	move.w	d0,d2
	andi.w	#$e,d2
	asl.w	#1,d2
	movea.l	$0(a1,d2.w),a1
	lea	$0(a1,d1.w),a1
	andi.w	#$fff0,d0
	lsr.w	#2,d0
	lea	scenery_blit_mid,a3
	movea.l	$0(a3,d0.w),a4
	movea.l	$28(a3,d0.w),a3
	move.w	d0,d2
	lsl.w	#1,d0
	add.w	d2,d0
	neg.w	d0
	addi.w	#$78,d0
scenery_sky_loop:
	lea	$0(a1,d0.w),a2
	jsr	(a4)
	movea.l	a1,a2
	bsr.w	mask_longs_20
	movea.l	a1,a2
	jsr	(a3)
	lea	$78(a1),a1
	lea	-$140(a0),a0
	dbra	d7,scenery_sky_loop
scenery_exit:
	rts

scenery_blit_left:	; from: draw_scenery
	dc.l	copy_none
	dc.l	copy_longs_2
	dc.l	copy_longs_4
	dc.l	copy_longs_6
	dc.l	copy_longs_8
	dc.l	copy_longs_10
	dc.l	copy_longs_12
	dc.l	copy_longs_14
	dc.l	copy_longs_16
	dc.l	copy_longs_18
scenery_blit_left_r:
	dc.l	copy_longs_20
	dc.l	copy_longs_18
	dc.l	copy_longs_16
	dc.l	copy_longs_14
	dc.l	copy_longs_12
	dc.l	copy_longs_10
	dc.l	copy_longs_8
	dc.l	copy_longs_6
	dc.l	copy_longs_4
	dc.l	copy_longs_2
scenery_blit_mid:	; from: draw_scenery
	dc.l	copy_none
	dc.l	mask_longs_2
	dc.l	mask_longs_4
	dc.l	mask_longs_6
	dc.l	mask_longs_8
	dc.l	mask_longs_10
	dc.l	mask_longs_12
	dc.l	mask_longs_14
	dc.l	mask_longs_16
	dc.l	mask_longs_18
scenery_blit_mid_r:
	dc.l	mask_longs_20
	dc.l	mask_longs_18
	dc.l	mask_longs_16
	dc.l	mask_longs_14
	dc.l	mask_longs_12
	dc.l	mask_longs_10
	dc.l	mask_longs_8
	dc.l	mask_longs_6
	dc.l	mask_longs_4
	dc.l	mask_longs_2
scenery_blit_sky:	; from: draw_scenery
	dc.l	copy_none
	dc.l	sky_words_1
	dc.l	sky_words_2
	dc.l	sky_words_3
	dc.l	sky_words_4
	dc.l	sky_words_5
	dc.l	sky_words_6
	dc.l	sky_words_7
	dc.l	sky_words_8
	dc.l	sky_words_9
	dc.l	sky_words_10
	dc.l	sky_words_11
	dc.l	sky_words_12
	dc.l	sky_words_13
	dc.l	sky_words_14
	dc.l	sky_words_15
	dc.l	sky_words_16
	dc.l	sky_words_17
	dc.l	sky_words_18
	dc.l	sky_words_19
scenery_blit_sky_r:
	dc.l	sky_words_20
	dc.l	sky_words_19
	dc.l	sky_words_18
	dc.l	sky_words_17
	dc.l	sky_words_16
	dc.l	sky_words_15
	dc.l	sky_words_14
	dc.l	sky_words_13
	dc.l	sky_words_12
	dc.l	sky_words_11
	dc.l	sky_words_10
	dc.l	sky_words_9
	dc.l	sky_words_8
	dc.l	sky_words_7
	dc.l	sky_words_6
	dc.l	sky_words_5
	dc.l	sky_words_4
	dc.l	sky_words_3
	dc.l	sky_words_2
	dc.l	sky_words_1

copy_longs_20:	; from: draw_scenery, scenery_blit_left_r
	movem.l	(a2)+,d1-d6/a5-a6
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	move.l	a5,(a0)+
	move.l	a6,(a0)+

copy_longs_12:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d6/a5-a6
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	move.l	a5,(a0)+
	move.l	a6,(a0)+

copy_longs_4:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d4
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+

copy_none:	; from: scenery_blit_left, scenery_blit_mid, scenery_blit_sky
	rts


copy_longs_18:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d6/a5-a6
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	move.l	a5,(a0)+
	move.l	a6,(a0)+

copy_longs_10:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d6/a5-a6
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	move.l	a5,(a0)+
	move.l	a6,(a0)+

copy_longs_2:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d2
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	rts


copy_longs_16:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d6/a5-a6
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	move.l	a5,(a0)+
	move.l	a6,(a0)+

copy_longs_8:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d6/a5-a6
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	move.l	a5,(a0)+
	move.l	a6,(a0)+
	rts


copy_longs_14:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d6/a5-a6
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	move.l	a5,(a0)+
	move.l	a6,(a0)+

copy_longs_6:	; from: scenery_blit_left, scenery_blit_left_r
	movem.l	(a2)+,d1-d6
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d4,(a0)+
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	rts


mask_longs_20:	; from: draw_scenery, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+

mask_longs_16:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+

mask_longs_12:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+

mask_longs_8:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+

mask_longs_4:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+
	rts


mask_longs_18:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+

mask_longs_14:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+

mask_longs_10:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+

mask_longs_6:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d6
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	and.l	d4,(a0)
	or.l	d5,(a0)+
	and.l	d4,(a0)
	or.l	d6,(a0)+

mask_longs_2:	; from: scenery_blit_mid, scenery_blit_mid_r
	movem.l	(a2)+,d1-d3
	and.l	d1,(a0)
	or.l	d2,(a0)+
	and.l	d1,(a0)
	or.l	d3,(a0)+
	rts


sky_words_20:	; from: scenery_blit_sky_r
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+

sky_words_14:	; from: scenery_blit_sky, scenery_blit_sky_r, sky_words_15, sky_words_16
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+

sky_words_8:	; from: scenery_blit_sky, scenery_blit_sky_r, sky_words_9, sky_words_10, sky_words_11, sky_words_17
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+

sky_words_2:	; from: scenery_blit_sky, scenery_blit_sky_r, sky_words_3, sky_words_4, sky_words_5, sky_words_10, ...
	movem.w	(a2)+,d1-d2
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	rts


sky_words_3:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_2
	bra.w	sky_words_1


sky_words_4:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_2
	bra.w	sky_words_2


sky_words_5:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_2
	bsr.w	sky_words_2
	bra.w	sky_words_1


sky_words_9:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_8
	bra.w	sky_words_1


sky_words_10:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_8
	bra.w	sky_words_2


sky_words_11:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_8
	bsr.w	sky_words_2
	bra.w	sky_words_1


sky_words_15:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_14
	bra.w	sky_words_1


sky_words_16:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_14
	bra.w	sky_words_2


sky_words_17:	; from: scenery_blit_sky, scenery_blit_sky_r
	bsr.w	sky_words_8
	bsr.w	sky_words_8
	bra.w	sky_words_1


sky_words_19:	; from: scenery_blit_sky, scenery_blit_sky_r
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+

sky_words_13:	; from: scenery_blit_sky, scenery_blit_sky_r
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+

sky_words_7:	; from: scenery_blit_sky, scenery_blit_sky_r
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+

sky_words_1:	; from: scenery_blit_sky, scenery_blit_sky_r, sky_words_3, sky_words_5, sky_words_9, sky_words_11, ...
	move.w	(a2)+,d1
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	rts


sky_words_18:	; from: scenery_blit_sky, scenery_blit_sky_r
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+

sky_words_12:	; from: scenery_blit_sky, scenery_blit_sky_r
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+

sky_words_6:	; from: scenery_blit_sky, scenery_blit_sky_r
	movem.w	(a2)+,d1-d6
	move.w	d1,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d2,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d3,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d4,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d5,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	move.w	d6,(a0)+
	move.w	a5,(a0)+
	move.l	a5,(a0)+
	rts


;----------------------------------------------------------------------
; Build the 18 x 16 shift masks used for the road stripes.
;----------------------------------------------------------------------
build_shift_masks:	; from: level_setup
	lea	stripe_masks,a0
	lea	dat_0a228,a1
	moveq	#17,d7
masks_next:
	moveq	#0,d0
	move.w	(a1)+,d0
	swap	d0
	moveq	#15,d6
masks_shift_loop:
	move.l	d0,(a0)+
	lsr.l	#1,d0
	dbra	d6,masks_shift_loop
	dbra	d7,masks_next
	rts


;----------------------------------------------------------------------
; Project the road edges: curve bytes of the course through the perspective table into
; road_left_edge / road_right_edge, row by row.
;----------------------------------------------------------------------
compute_road_edges:	; from: main_loop
	move.w	road_position,d5
	move.w	d5,-(sp)
	lea	road_right_edge,a5
	bsr.w	compute_road_edge
	move.w	(sp)+,d5
	subi.w	#$1a9,d5
	lea	road_left_edge,a5

compute_road_edge:	; from: compute_road_edges
	lea	course_bytes,a0
	move.w	segment_index,d6
	move.b	$0(a0,d6.w),d2
	move.w	segment_fraction,d1
	andi.b	#$e0,d1
	lea	curve_tables,a1
	adda.w	d1,a1
	bsr.w	lerp3
	neg.b	d0
	addi.b	#$80,d0
	andi.w	#$fe,d0
	lea	perspective_table,a2
	lea	edge_deltas,a3
	moveq	#21,d7
	move.w	d5,d1
proj_row_loop:
	add.b	$0(a0,d6.w),d0
	addq.b	#1,d6
	moveq	#0,d2
	move.w	$0(a2,d0.w),d4
	sub.w	d1,d4
	addi.w	#$1e,d4
	ext.l	d4
	move.b	(a1)+,d3
	lsl.b	#1,d3
	bcc.s	proj_bit6
	move.l	d4,d2
	asl.l	#1,d2
proj_bit6:
	asl.b	#1,d3
	bcc.s	proj_bit5
	add.l	d4,d2
proj_bit5:
	asl.l	#1,d2
	asl.b	#1,d3
	bcc.s	proj_bit4
	add.l	d4,d2
proj_bit4:
	asl.l	#1,d2
	asl.b	#1,d3
	bcc.s	proj_bit3
	add.l	d4,d2
proj_bit3:
	asl.l	#1,d2
	asl.b	#1,d3
	bcc.s	proj_bit2
	add.l	d4,d2
proj_bit2:
	asl.l	#1,d2
	asl.b	#1,d3
	bcc.s	proj_bit1
	add.l	d4,d2
proj_bit1:
	asl.l	#1,d2
	asl.b	#1,d3
	bcc.s	proj_store_row
	add.l	d4,d2
proj_store_row:
	asr.l	#1,d2
	asr.l	#8,d2
	move.b	d2,(a3)+
	add.w	d2,d1
	asr.w	#8,d2
	move.b	d2,$15(a3)
	dbra	d7,proj_row_loop
	lea	road_width,a1
	moveq	#20,d7
proj_fill_rows:
	moveq	#0,d1
proj_fill_row:
	move.w	d1,d2
	subq.b	#2,d2
	add.b	(a1)+,d2
	sub.b	(a1),d2
	bmi.w	proj_fill_flat
	addq.b	#2,d2
	move.b	d2,$5a(a1)
	sub.b	d1,d2
	move.b	d2,d1
	subq.b	#1,d1
	move.b	$2d(a1),d3
	bpl.s	proj_fill_up
	move.b	$17(a1),d3
	neg.b	d3
	cmp.b	d3,d2
	bcs.s	proj_fill_down_steep
	move.b	d2,d4
	lsr.b	#1,d4
proj_fill_down_loop:
	add.b	d3,d4
	cmp.b	d2,d4
	bcs.s	proj_fill_down_store
	sub.b	d2,d4
	subq.w	#1,d5
proj_fill_down_store:
	move.w	d5,(a5)+
	dbra	d1,proj_fill_down_loop
	dbra	d7,proj_fill_rows
	rts

proj_fill_down_steep:
	moveq	#0,d4
proj_fill_down_steep_loop:
	subq.w	#1,d5
	add.b	d2,d4
	bcs.s	proj_fill_down_steep_store
	cmp.b	d3,d4
	bcs.s	proj_fill_down_steep_loop
proj_fill_down_steep_store:
	sub.b	d3,d4
	move.w	d5,(a5)+
	dbra	d1,proj_fill_down_steep_loop
	dbra	d7,proj_fill_rows
	rts

proj_fill_up:
	move.b	$17(a1),d3
	cmp.b	d3,d2
	bcs.w	proj_fill_up_steep
	move.b	d2,d4
	lsr.b	#1,d4
proj_fill_up_loop:
	add.b	d3,d4
	cmp.b	d2,d4
	bcs.s	proj_fill_up_store
	sub.b	d2,d4
	addq.w	#1,d5
proj_fill_up_store:
	move.w	d5,(a5)+
	dbra	d1,proj_fill_up_loop
	dbra	d7,proj_fill_rows
	rts

proj_fill_up_steep:
	moveq	#0,d4
proj_fill_up_steep_loop:
	addq.w	#1,d5
	add.b	d2,d4
	bcs.s	proj_fill_up_steep_store
	cmp.b	d3,d4
	bcs.s	proj_fill_up_steep_loop
proj_fill_up_steep_store:
	sub.b	d3,d4
	move.w	d5,(a5)+
	dbra	d1,proj_fill_up_steep_loop
	dbra	d7,proj_fill_rows
	rts

proj_fill_flat:
	move.b	#$1,$5a(a1)
	addq.b	#1,d2
	beq.s	proj_flat_store
	addq.b	#1,d2
proj_flat_store:
	move.w	d2,d1
	move.b	$2d(a1),d2
	lsl.w	#8,d2
	move.b	$17(a1),d2
	add.w	d2,d5
	move.w	d5,(a5)+
	dbra	d7,proj_fill_row
	rts


;----------------------------------------------------------------------
; Project the hill bytes of the course into line_heights (screen row of each segment).
;----------------------------------------------------------------------
compute_hill_heights:	; from: main_loop
	lea	course_bytes,a0
	move.w	segment_index,d6
	addi.b	#$20,d6
	move.b	$0(a0,d6.w),d2
	move.w	segment_fraction,d1
	andi.b	#$e0,d1
	lea	hill_tables,a1
	adda.w	d1,a1
	bsr.w	lerp3
	neg.b	d0
	moveq	#20,d7
	lea	line_heights,a2
hill_row_loop:
	moveq	#0,d1
	move.w	d1,d3
	move.b	(a1),d1
	asl.w	#1,d1
	add.b	$0(a0,d6.w),d0
	beq.s	hill_flat
	move.b	d0,d2
	bpl.s	hill_abs
	neg.w	d1
	neg.b	d2
hill_abs:
	add.b	d2,d2
	add.b	d2,d2
	bcc.s	hill_bit6
	move.w	d1,d3
	asl.w	#1,d3
hill_bit6:
	asl.b	#1,d2
	bcc.s	hill_bit5
	add.w	d1,d3
hill_bit5:
	asl.w	#1,d3
	asl.b	#1,d2
	bcc.s	hill_bit4
	add.w	d1,d3
hill_bit4:
	asl.w	#1,d3
	asl.b	#1,d2
	bcc.s	hill_bit3
	add.w	d1,d3
hill_bit3:
	asl.w	#1,d3
	asl.b	#1,d2
	bcc.s	hill_bit2
	add.w	d1,d3
hill_bit2:
	asl.w	#1,d3
	asl.b	#1,d2
	bcc.s	hill_bit1
	add.w	d1,d3
hill_bit1:
	asl.w	#1,d3
	asl.b	#1,d2
	bcc.s	hill_scale
	add.w	d1,d3
hill_scale:
	asr.w	#7,d3
hill_store:
	add.b	(a1)+,d3
	move.b	d3,(a2)+
	addq.b	#1,d6
	dbra	d7,hill_row_loop
	move.b	#$a0,(a2)
	lea	line_min_heights,a0
	lea	line_heights,a1
	move.w	#$14,d7
	move.b	#$60,d1
hill_min_loop:
	move.b	(a1)+,d2
	cmp.b	d1,d2
	bpl.s	hill_min_store
	move.b	d2,d1
hill_min_store:
	move.b	d1,(a0)+
	dbra	d7,hill_min_loop
	rts

hill_flat:
	move.b	d0,d3
	bra.s	hill_store


;----------------------------------------------------------------------
; Interpolate three table bytes by the segment fraction bits in d1.
;----------------------------------------------------------------------
lerp3:	; from: compute_road_edge, compute_hill_heights
	moveq	#2,d7
	moveq	#0,d0
lerp3_loop:
	rol.b	#1,d1
	bcc.w	lerp3_shift
	add.b	d2,d0
lerp3_shift:
	asl.b	#1,d0
	dbra	d7,lerp3_loop
	roxr.b	#1,d0
	asr.b	#3,d0
	moveq	#0,d7
	addx.b	d7,d0
	rts

perspective_table:	; from: compute_road_edge
	dc.w	$e100,$ec22,$f653,$f9b9,$fb6c,$fc72,$fd21,$fd9e
	dc.w	$fdfd,$fe46,$fe81,$feb1,$feda,$fefd,$ff1a,$ff34
	dc.w	$ff4b,$ff5f,$ff71,$ff82,$ff91,$ff9e,$ffaa,$ffb6
	dc.w	$ffc0,$ffca,$ffd3,$ffdc,$ffe4,$ffec,$fff3,$fffa
	dc.w	$0000,$0006,$000c,$0012,$0017,$001c,$0021,$0026
	dc.w	$002a,$002f,$0033,$0037,$003c,$0040,$0043,$0047
	dc.w	$004b,$004f,$0052,$0056,$0059,$005d,$0060,$0063
	dc.w	$0067,$006a,$006d,$0070,$0073,$0077,$007a,$007d
	dc.w	$0080,$0083,$0086,$0089,$008d,$0090,$0093,$0096
	dc.w	$0099,$009d,$00a0,$00a3,$00a7,$00aa,$00ae,$00b1
	dc.w	$00b5,$00b9,$00bd,$00c0,$00c4,$00c9,$00cd,$00d1
	dc.w	$00d6,$00da,$00df,$00e4,$00e9,$00ee,$00f4,$00fa
	dc.w	$0100,$0106,$010d,$0114,$011c,$0124,$012d,$0136
	dc.w	$0140,$014a,$0156,$0162,$016f,$017e,$018f,$01a1
	dc.w	$01b5,$01cc,$01e6,$0203,$0226,$024f,$027f,$02ba
	dc.w	$0303,$0362,$03df,$048e,$0594,$0747,$0aad,$14de
	dc.b	$60
hill_tables:	; from: advance_object, compute_hill_heights
	dc.b	$4a,$3c,$32,$2b,$25,$21,$1e,$1b,$18,$16,$15,$13,$12,$11,$10,$0f
	dc.b	$0e,$0d,$0c,$0b,$0a,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60
	dc.b	$4c,$3d,$33,$2c,$26,$22,$1e,$1b,$19,$17,$15,$13,$12,$11,$10,$0f
	dc.b	$0e,$0d,$0c,$0b,$0a,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60
	dc.b	$4f,$3f,$34,$2d,$27,$22,$1e,$1b,$19,$17,$15,$14,$12,$11,$10,$0f
	dc.b	$0e,$0d,$0c,$0b,$0a,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60
	dc.b	$51,$41,$35,$2d,$27,$23,$1f,$1c,$19,$17,$15,$14,$12,$11,$10,$0f
	dc.b	$0e,$0d,$0c,$0b,$0a,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60
	dc.b	$54,$42,$37,$2e,$28,$23,$1f,$1c,$1a,$17,$16,$14,$13,$11,$10,$0f
	dc.b	$0e,$0d,$0c,$0b,$0a,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	'`WD8/)$ '
	dc.w	$1d1a,$1816,$1413,$1110,$0f0e,$0d0c,$0b0a,$0000
	dc.w	$0000,$0000,$0000,$0000
	dc.b	'`YF90)$ '
	dc.w	$1d1a,$1816,$1413,$1210,$0f0e,$0d0c,$0b0a,$0000
	dc.w	$0000,$0000,$0000,$0000
	dc.b	'`]H;1*%!'
	dc.w	$1d1a,$1816,$1413,$1211,$100f,$0e0d,$0c0a,$0000
	dc.w	$0000,$0000,$0000,$0000
curve_tables:	; from: compute_road_edge
	dc.w	$ebc1,$aa8f
	dc.b	$8e
	dc.b	'n]fqU.a58<@DINU]f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$d5,$ca,$a7,$8c,$8b
	dc.b	'kxfKQYa58<@DINU]f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$b5,$cf,$b3,$89,$88,$83
	dc.b	'xfKQY0f8<@DINU]f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$a0,$ca,$bd,$9a,$88
	dc.b	'iucmQY0f8<@DINU]f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$db,$aa,$a7,$85,$80
	dc.b	'ucIv,]3k<@DINU]f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$df,$b5,$a4,$82
	dc.b	'|q`iNU]3k<@DINU]f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$4b,$db,$be,$a1,$95
	dc.b	'|q`iNU]35q@DINU]f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$e7,$b9,$ad,$92
	dc.b	'yn|iNU]358<@DINU]',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00
scale_tables:	; from: draw_roadside, roadside_collision, road_edge_line
	dc.w	$5343,$3830,$2924,$211d,$1a18,$1614,$1312,$100f
	dc.w	$0e0d,$0b0a,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$5644,$3931,$2a25,$211d,$1b19,$1614,$1312,$100f
	dc.w	$0e0d,$0b0a,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$5947,$3a32,$2b26,$211d,$1b19,$1615,$1312,$100f
	dc.w	$0e0d,$0b0a,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$5b49,$3b32,$2b26,$221e,$1b18,$1615,$1311,$100f
	dc.w	$0e0c,$0b0a,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$5f4a,$3e33,$2c27,$221e,$1c19,$1715,$1412,$100f
	dc.w	$0e0d,$0b0a,$0000,$0000,$0000,$0000,$0000,$0000
	dc.b	'bM?4-(# '
	dc.w	$1c1a,$1715,$1412,$100f,$0e0d,$0b0a,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000
	dc.b	'dO@6.(# '
	dc.w	$1c1a,$1715,$1413,$100f,$0e0d,$0b0a,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$6951,$4237,$2f29,$241f
	dc.w	$1c1a,$1715,$1413,$1110,$0f0e,$0c0c,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000

;----------------------------------------------------------------------
; Unpack a graphics list: (type, source) pairs, type 1-3 raw copies, 4-11 preshifted sprite sets.
;----------------------------------------------------------------------
unpack_gfx:	; from: level_setup, shift_sprite16, shift_sprite8, raw_shift_long
	move.w	(a0)+,d0
	beq.s	unpack_exit
	cmpi.w	#$4,d0
	bcs.w	unpack_raw
	movea.l	(a0)+,a5
	cmpi.w	#$4,d0
	beq.w	unpack_type_4
	cmpi.w	#$5,d0
	beq.w	unpack_type_5
	cmpi.w	#$6,d0
	beq.w	unpack_type_6
	cmpi.w	#$7,d0
	beq.w	unpack_type_7
	cmpi.w	#$8,d0
	beq.w	unpack_type_8
	cmpi.w	#$9,d0
	beq.w	unpack_type_9
	cmpi.w	#$a,d0
	beq.w	unpack_type_10
	cmpi.w	#$b,d0
	beq.w	unpack_type_11
unpack_exit:
	rts

shift_list_4:	; from: unpack_gfx
	dc.w	$0000,$0300,$0003,$0000,$0000,$0300,$0003,$0000
	dc.w	$0000,$0300,$0003,$0000,$0000,$0200,$0200,$0200
	dc.w	$0000,$0200,$0200,$0200,$0000,$0200,$0200,$0200
	dc.w	$0000,$0200,$0200,$0200,$0001,$0101,$0101,$0101
	dc.w	$0001,$0101,$0101,$0101
shift_list_7:	; from: unpack_gfx
	dcb.b	20,$00
	dc.w	$0400,$0000,$0000,$0000,$0400,$0000,$0000,$0300
	dc.w	$0003,$0000,$0000,$0200,$0200,$0200,$0000,$0200
	dc.w	$0200,$0200,$0000,$0200,$0200,$0200,$0001,$0101
	dc.w	$0101,$0101
shift_list_9:	; from: unpack_gfx
	dc.w	$0000,$0000,$0400,$0000,$0000,$0000,$0400,$0000
	dc.w	$0000,$0000,$0400,$0000,$0000,$0000,$0300,$0000
	dc.w	$0000,$0300,$0003,$0000,$0000,$0300,$0003,$0000
	dc.w	$0000,$0200,$0200,$0200,$0000,$0200,$0200,$0200
	dc.w	$0000,$0200,$0200,$0200
shift_list_10:	; from: unpack_gfx
	dc.w	$0000,$0200,$0200,$0200,$0000,$0200,$0200,$0200
	dc.w	$0000,$0200,$0200,$0200,$0001,$0101,$0101,$0100
	dc.w	$0001,$0101,$0101,$0100,$0001,$0101,$0101,$0100
	dc.w	$0001,$0101,$0101,$0100,$0001,$0101,$0101,$0100
	dc.w	$0001,$0101,$0101,$0100
unpack_type_10:
	move.l	a0,-(sp)
	lea	shift_list_10,a0
	bra.s	unpack_sprite_set

unpack_type_7:
	move.l	a0,-(sp)
	lea	shift_list_7,a0
	bra.s	unpack_sprite_set

unpack_type_9:
	move.l	a0,-(sp)
	lea	shift_list_9,a0
	bra.s	unpack_sprite_set

unpack_type_4:
	move.l	a0,-(sp)
	lea	shift_list_4,a0
unpack_sprite_set:
	moveq	#8,d7
unpack_set_loop:
	bsr.w	unpack_sprite16
	dbra	d7,unpack_set_loop
	movea.l	(sp)+,a0
	bra.w	unpack_gfx


;----------------------------------------------------------------------
; Build the 8 shifted copies of a 16 pixel sprite set (headers at a5, shifted data to a6).
;----------------------------------------------------------------------
unpack_sprite16:	; from: unpack_gfx, shift_sprite8
	move.w	d7,-(sp)
	addq.w	#2,a5
	move.w	(a5)+,d0
	addq.w	#2,a5
	move.w	(a5)+,d1
	subq.w	#1,d1
	movea.l	(a5),a3
	adda.l	a5,a3
	move.l	a4,(a5)+
	move.l	#blit_rows,(a5)+
	moveq	#7,d7
shift_entry_loop:
	move.b	(a0)+,d6
	bne.s	shift_first
	move.w	#$0,(a4)+
	move.w	#$0,(a4)+
	move.l	a3,(a4)+
	dbra	d7,shift_entry_loop
unpack_sprite16_exit:	; from: shift_count
	move.w	(sp)+,d7
	rts

shift_first:
	movea.l	a3,a1
	movea.l	a6,a2
	pea	shift_count
	bra.w	shift_sprite16_pad

shift_next_entry:	; from: shift_count
	move.b	(a0)+,d6
	beq.s	shift_entry_store
	movea.l	a6,a1
	movea.l	a2,a6
shift_copy:	; from: shift_count
	movea.l	a6,a2
	bsr.s	shift_sprite16

shift_count:	; from: unpack_sprite16
	movea.l	a6,a1
	subq.b	#1,d6
	bne.s	shift_copy
shift_entry_store:	; from: unpack_sprite16
	move.w	#$c,(a4)+
	move.w	#$1,(a4)+
	move.l	a6,(a4)+
	dbra	d7,shift_next_entry
	movea.l	a2,a6
	bra.s	unpack_sprite16_exit


shift_sprite16:	; from: unpack_sprite16
	move.w	d7,-(sp)
	move.w	d1,d7
shift16_row_loop:
	moveq	#0,d4
	moveq	#-1,d3
	move.w	d0,d5
shift16_col_loop:
	move.l	(a1)+,d2
	lsr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	roxl.b	#2,d3
	move.w	d2,(a2)+
	move.w	d2,(a2)+
	move.l	(a1)+,d2
	lsr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	swap	d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	swap	d2
	move.l	d2,(a2)+
	move.l	(a1)+,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	swap	d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	swap	d2
	move.l	d2,(a2)+
	dbra	d5,shift16_col_loop
	dbra	d7,shift16_row_loop
	move.w	(sp)+,d7
	rts

shift_sprite16_pad:	; from: unpack_sprite16
	move.w	d7,-(sp)
	move.w	d1,d7
shift16_pad_row_loop:
	moveq	#0,d4
	moveq	#-1,d3
	move.w	d0,d5
	subq.w	#1,d5
shift16_pad_col_loop:
	move.l	(a1)+,d2
	lsr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	roxl.b	#2,d3
	move.w	d2,(a2)+
	move.w	d2,(a2)+
	move.l	(a1)+,d2
	lsr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	swap	d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	swap	d2
	move.l	d2,(a2)+
	move.l	(a1)+,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	swap	d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	roxr.w	#1,d2
	roxr.b	#1,d4
	swap	d2
	move.l	d2,(a2)+
	dbra	d5,shift16_pad_col_loop
	ori.w	#$fffc,d3
	ror.w	#2,d3
	move.w	d3,(a2)+
	move.w	d3,(a2)+
	moveq	#0,d2
	lsr.b	#1,d4
	roxr.l	#1,d2
	lsr.b	#1,d4
	roxr.l	#1,d2
	lsr.b	#1,d4
	roxr.w	#1,d2
	lsr.b	#1,d4
	roxr.w	#1,d2
	swap	d2
	move.l	d2,(a2)+
	moveq	#0,d2
	lsr.b	#1,d4
	roxr.l	#1,d2
	lsr.b	#1,d4
	roxr.l	#1,d2
	lsr.b	#1,d4
	roxr.w	#1,d2
	lsr.b	#1,d4
	roxr.w	#1,d2
	swap	d2
	move.l	d2,(a2)+
	dbra	d7,shift16_pad_row_loop
	move.w	(sp)+,d7
	rts

shift_list_5:	; from: shift_sprite16
	dc.w	$0000,$0000,$0400,$0000,$0000,$0000,$0400,$0000
	dc.w	$0000,$0000,$0400,$0000,$0000,$0300,$0003,$0000
	dc.w	$0000,$0300,$0003,$0000,$0000,$0200,$0200,$0200
	dc.w	$0000,$0200,$0200,$0200,$0000,$0200,$0200,$0200
	dc.w	$0001,$0101,$0101,$0101
shift_list_8:	; from: shift_sprite16
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0400,$0000
	dc.w	$0000,$0000,$0400,$0000,$0000,$0000,$0400,$0000
	dc.w	$0000,$0000,$0400,$0000,$0000,$0300,$0003,$0000
	dc.w	$0000,$0300,$0003,$0000,$0000,$0200,$0200,$0200
	dc.w	$0000,$0200,$0200,$0200
shift_list_11:	; from: shift_sprite16
	dc.w	$0000,$0200,$0200,$0200,$0000,$0200,$0200,$0200
	dc.w	$0000,$0200,$0200,$0200,$0001,$0101,$0101,$0101
	dc.w	$0001,$0101,$0101,$0101,$0001,$0101,$0101,$0101
	dc.w	$0001,$0101,$0101,$0101,$0001,$0101,$0101,$0101
	dc.w	$0001,$0101,$0101,$0101
unpack_type_11:	; from: unpack_gfx
	move.l	a0,-(sp)
	lea	shift_list_11,a0
	bra.s	unpack_mask_set

unpack_type_8:	; from: unpack_gfx
	move.l	a0,-(sp)
	lea	shift_list_8,a0
	bra.s	unpack_mask_set

unpack_type_5:	; from: unpack_gfx
	move.l	a0,-(sp)
	lea	shift_list_5,a0
unpack_mask_set:
	moveq	#8,d7
mask_set_loop:
	move.w	d7,-(sp)
	addq.w	#2,a5
	move.w	(a5)+,d0
	addq.w	#2,a5
	move.w	(a5)+,d1
	subq.w	#1,d1
	move.l	(a5),d2
	lea	$0(a5,d2.w),a3
	move.l	a4,(a5)+
	move.l	#blit_mask_rows,(a5)+
	moveq	#7,d7
mask_entry_loop:
	move.b	(a0)+,d6
	bne.s	mask_first
	move.w	#$0,(a4)+
	move.w	#$0,(a4)+
	move.l	a3,(a4)+
	dbra	d7,mask_entry_loop
mask_set_next:	; from: mask_count
	move.w	(sp)+,d7
	dbra	d7,mask_set_loop
	movea.l	(sp)+,a0
	bra.w	unpack_gfx

mask_first:
	movea.l	a3,a1
	movea.l	a6,a2
	pea	mask_count
	bra.w	shift_sprite8_pad

mask_next_entry:	; from: mask_count
	move.b	(a0)+,d6
	beq.s	mask_entry_store
	movea.l	a6,a1
	movea.l	a2,a6
mask_copy:	; from: mask_count
	movea.l	a6,a2
	bsr.s	shift_sprite8

mask_count:	; from: shift_sprite16
	movea.l	a6,a1
	subq.b	#1,d6
	bne.s	mask_copy
mask_entry_store:	; from: shift_sprite16
	move.w	#$6,(a4)+
	move.w	#$1,(a4)+
	move.l	a6,(a4)+
	dbra	d7,mask_next_entry
	movea.l	a2,a6
	bra.s	mask_set_next


shift_sprite8:	; from: shift_sprite16
	move.w	d1,d4
shift8_row_loop:
	moveq	#3,d3
	move.w	d0,d5
shift8_col_loop:
	move.w	(a1)+,d2
	lsr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	move.w	d2,(a2)+
	move.l	(a1)+,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	swap	d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#3,d3
	swap	d2
	move.l	d2,(a2)+
	dbra	d5,shift8_col_loop
	dbra	d4,shift8_row_loop
	rts

shift_sprite8_pad:	; from: shift_sprite16
	move.w	d1,d4
shift8_pad_row_loop:
	moveq	#3,d3
	move.w	d0,d5
	subq.w	#1,d5
shift8_pad_col_loop:
	move.w	(a1)+,d2
	lsr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	move.w	d2,(a2)+
	move.l	(a1)+,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	swap	d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#1,d3
	roxr.w	#1,d2
	roxr.b	#3,d3
	swap	d2
	move.l	d2,(a2)+
	dbra	d5,shift8_pad_col_loop
	moveq	#-1,d2
	lsr.b	#1,d3
	roxr.w	#1,d2
	lsr.b	#1,d3
	roxr.w	#1,d2
	move.w	d2,(a2)+
	moveq	#0,d2
	lsr.b	#1,d3
	roxr.l	#1,d2
	lsr.b	#1,d3
	roxr.l	#1,d2
	lsr.b	#1,d3
	roxr.w	#1,d2
	lsr.b	#1,d3
	roxr.w	#1,d2
	swap	d2
	move.l	d2,(a2)+
	dbra	d4,shift8_pad_row_loop
	rts

unpack_type_6:	; from: unpack_gfx
	move.w	(a0)+,d7
type6_loop:
	bsr.w	unpack_sprite16
	subq.w	#8,a0
	dbra	d7,type6_loop
	addq.w	#8,a0
	bra.w	unpack_gfx

unpack_raw:	; from: unpack_gfx
	move.w	(a0)+,d1
	move.w	(a0)+,d2
	movea.l	(a0)+,a2
	moveq	#6,d7
	move.l	a2,(a4)+
	cmpi.w	#$2,d0
	beq.w	unpack_type_2
	cmpi.w	#$3,d0
	beq.w	unpack_type_3
raw_copy_shift:
	move.l	a6,(a4)+
	movea.l	a6,a5
	move.l	d2,-(sp)
raw_row_loop:
	move.w	d1,d3
	movea.l	a6,a3
	move.w	(a2),d5
raw_word_loop:
	move.w	(a2)+,d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	roxr.b	#7,d6
	move.w	d0,(a6)+
	dbra	d3,raw_word_loop
	roxr.b	#1,d6
	roxr.w	#1,d5
	roxr.b	#1,d6
	roxr.w	#1,d5
	move.w	d5,(a3)
	dbra	d2,raw_row_loop
	movea.l	a5,a2
	move.l	(sp)+,d2
	dbra	d7,raw_copy_shift
	bra.w	unpack_gfx

unpack_type_2:
	movem.l	d7/a2/a6,-(sp)
	bsr.s	raw_shift_long_first
	movem.l	(sp)+,d7/a2/a6
	lea	$4(a2),a2
	lea	$4(a6),a6
type2_loop:
	bsr.s	raw_shift_long
	dbra	d7,type2_loop
	bra.w	unpack_gfx


raw_shift_long_first:	; from: shift_sprite8
	move.l	a6,(a4)+
	bsr.s	raw_shift_long
	dbra	d7,raw_shift_long_first
	rts


raw_shift_long:	; from: shift_sprite8, raw_shift_long_first
	movea.l	a6,a5
	move.l	d2,-(sp)
raw_long_row_loop:
	move.w	d1,d3
	movea.l	a6,a3
	move.l	(a2),d5
raw_long_loop:
	move.l	(a2)+,d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	swap	d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	roxr.b	#5,d6
	swap	d0
	move.l	d0,(a6)+
	lea	$4(a2),a2
	lea	$4(a6),a6
	dbra	d3,raw_long_loop
	roxr.b	#1,d6
	roxr.w	#1,d5
	roxr.b	#1,d6
	roxr.w	#1,d5
	swap	d5
	roxr.b	#1,d6
	roxr.w	#1,d5
	roxr.b	#1,d6
	roxr.w	#1,d5
	swap	d5
	move.l	d5,(a3)
	dbra	d2,raw_long_row_loop
	movea.l	a5,a2
	move.l	(sp)+,d2
	rts

unpack_type_3:	; from: shift_sprite8
	movem.l	d7/a2/a6,-(sp)
	bsr.s	raw_shift_wide_first
	movem.l	(sp),d7/a2/a6
	lea	$4(a2),a2
	lea	$4(a6),a6
type3_loop:
	bsr.s	raw_shift_wide
	dbra	d7,type3_loop
	movem.l	(sp)+,d7/a2/a6
	lea	$8(a2),a2
	lea	$8(a6),a6
type3_second_loop:
	bsr.s	raw_shift_wide
	dbra	d7,type3_second_loop
	bra.w	unpack_gfx


raw_shift_wide_first:	; from: raw_shift_long
	move.l	a6,(a4)+
	bsr.s	raw_shift_wide
	dbra	d7,raw_shift_wide_first
	rts


raw_shift_wide:	; from: raw_shift_long, raw_shift_wide_first
	movea.l	a6,a5
	move.l	d2,-(sp)
wide_row_loop:
	move.w	d1,d3
	movea.l	a6,a3
	move.l	(a2),d5
wide_loop:
	move.l	(a2)+,d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	swap	d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	roxr.b	#1,d6
	roxr.w	#1,d0
	roxr.b	#5,d6
	swap	d0
	move.l	d0,(a6)+
	lea	$8(a2),a2
	lea	$8(a6),a6
	dbra	d3,wide_loop
	roxr.b	#1,d6
	roxr.w	#1,d5
	roxr.b	#1,d6
	roxr.w	#1,d5
	swap	d5
	roxr.b	#1,d6
	roxr.w	#1,d5
	roxr.b	#1,d6
	roxr.w	#1,d5
	swap	d5
	move.l	d5,(a3)
	dbra	d2,wide_row_loop
	movea.l	a5,a2
	move.l	(sp)+,d2
	rts

road_left_edge:	; from: advance_object, build_roadside_positions, interpolate_road_edges, draw_road, compute_road_edges
	dcb.b	42,$00
road_left_far:	; from: grapple_control
	dcb.b	214,$00
road_edge_q1:	; from: interpolate_road_edges
	dcb.b	256,$00
road_centre:	; from: interpolate_road_edges
	dcb.b	256,$00
road_edge_q3:	; from: interpolate_road_edges
	dcb.b	256,$00
road_right_edge:	; from: build_roadside_positions, interpolate_road_edges, compute_road_edges
	dcb.b	42,$00
road_right_far:	; from: grapple_control
	dcb.b	214,$00
roadside_positions:	; from: roadside_collision, build_roadside_positions
	dcb.b	90,$00
sort_list:	; from: update_objects, object_hit_test
	dcb.b	48,$00
sort_list_end:	; from: object_hit_test
	dc.w	$0000,$0000,$0000

;----------------------------------------------------------------------
; Build the Batmobile roadside scenery table from random patterns.
;----------------------------------------------------------------------
build_road_batmobile:	; from: level_setup
	lea	road_group_counts,a5
	lea	road_batmobile,a0
	lea	road_pattern_a,a1
	lea	road_pattern_ptrs,a2
	lea	road_patterns,a3
	lea	road_pattern_end,a4
road_next_group:
	move.w	(a5)+,d7
	bmi.s	build_road_exit
road_segment_loop:
	bsr.w	random
	andi.w	#$f,d0
	mulu.w	#$6,d0
	lea	$0(a1,d0.w),a6
	move.l	a6,(a0)+
	bsr.w	random
	andi.w	#$7,d0
	lsl.w	#2,d0
	move.l	$0(a2,d0.w),(a0)+
	bsr.w	random
	andi.w	#$7,d0
	mulu.w	#$1a,d0
	lea	$0(a3,d0.w),a6
	move.l	a6,(a0)+
	andi.w	#$7,d0
	mulu.w	#$1a,d0
	lea	$0(a3,d0.w),a6
	move.l	a6,(a0)+
	move.l	a4,(a0)+
	dbra	d7,road_segment_loop
	lea	$14(a0),a0
	bra.s	road_next_group

build_road_exit:
	rts


;----------------------------------------------------------------------
; Build the Batwing roadside scenery table from random patterns.
;----------------------------------------------------------------------
build_road_batwing:	; from: level_setup
	lea	road_batwing,a0
	lea	wing_pattern_a,a1
	lea	wing_pattern_ptrs,a2
	lea	wing_patterns,a3
	lea	road_pattern_end,a4
	moveq	#24,d7
wing_road_loop:
	bsr.w	random
	andi.w	#$f,d0
	mulu.w	#$6,d0
	lea	$0(a1,d0.w),a6
	move.l	a6,(a0)+
	bsr.w	random
	andi.w	#$7,d0
	lsl.w	#2,d0
	move.l	$0(a2,d0.w),(a0)+
	bsr.w	random
	andi.w	#$7,d0
	mulu.w	#$1a,d0
	lea	$0(a3,d0.w),a6
	move.l	a6,(a0)+
	andi.w	#$7,d0
	mulu.w	#$1a,d0
	lea	$0(a3,d0.w),a6
	move.l	a6,(a0)+
	move.l	a4,(a0)+
	dbra	d7,wing_road_loop
	rts


; Course of level 2: list of block pointers (0 then a pointer = jump).
course2_list:
	dc.w	$0000,$819c,$0000,$8228,$0000,$8278,$0000,$82dc
	dc.w	$0000,$8368,$0000,$83a4,$0000,$83e0,$0000,$8458
	dc.w	$0000,$8480,$0000,$84bc,$0000,$84e4,$0000,$8534
	dc.w	$0000,$8598,$0000,$85d4,$0000,$85fc,$0000,$0000
	dc.w	$0000,$812c

; Course of level 4.
course4_list:
	dc.w	$0000,$88dc,$0000,$0000,$0000,$8170
road_group_counts:	; from: build_road_batmobile
	dc.w	$0004,$0002,$0003,$0005,$0001,$0001,$0004,$0000
	dc.w	$0001,$0000,$0002,$0003,$0001,$0000,$0002,$ffff
	dc.w	$0000,$864c,$0000,$86ac
tab_081a4:
	dc.l	road_patterns
	dc.l	road_patterns
	dc.w	$0000,$87d6
road_batmobile:	; from: build_road_batmobile
	dcb.b	102,$00
	dc.w	$88c8,$0000,$88b4
tab_0821c:
	dc.l	dat_0887a
	dc.l	dat_0882e
	dc.l	dat_087da
	dcb.b	62,$00
	dc.w	$88c8,$0000,$88b4
tab_0826c:
	dc.l	dat_0882e
	dc.l	dat_0887a
	dc.l	dat_08804
	dcb.b	82,$00
	dc.w	$88c8,$0000,$88b4
tab_082d0:
	dc.l	dat_0887a
	dc.l	dat_0882e
	dc.l	dat_087da
	dcb.b	122,$00
	dc.w	$88c8,$0000,$88b4
tab_0835c:
	dc.l	dat_0887a
	dc.l	dat_0882e
	dc.l	dat_087da
	dcb.b	26,$00
	dc.w	$2b96,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$88c8,$0000,$88b4
tab_08398:
	dc.l	dat_0882e
	dc.l	dat_0887a
	dc.l	dat_08804
	dcb.b	42,$00
	dc.w	$88c8,$0000,$88b4
tab_083d4:
	dc.l	dat_0887a
	dc.l	dat_0882e
	dc.l	dat_087da
	dcb.b	102,$00
	dc.w	$88c8,$0000,$88b4
tab_0844c:
	dc.l	dat_0882e
	dc.l	dat_0887a
	dc.l	dat_08804
	dcb.b	22,$00
	dc.w	$88c8,$0000,$88b4
tab_08474:
	dc.l	dat_0882e
	dc.l	dat_0887a
	dc.l	dat_08804
	dcb.b	42,$00
	dc.w	$88c8,$0000,$88b4
tab_084b0:
	dc.l	dat_0887a
	dc.l	dat_0882e
	dc.l	dat_087da
	dcb.b	22,$00
	dc.w	$88c8,$0000,$88b4
tab_084d8:
	dc.l	dat_0882e
	dc.l	dat_0887a
	dc.l	dat_08804
	dcb.b	62,$00
	dc.w	$88c8,$0000,$88b4
tab_08528:
	dc.l	dat_0887a
	dc.l	dat_0882e
	dc.l	dat_087da
	dcb.b	82,$00
	dc.w	$88c8,$0000,$88b4
tab_0858c:
	dc.l	dat_0882e
	dc.l	dat_0887a
	dc.l	dat_08804
	dcb.b	42,$00
	dc.w	$88c8,$0000,$88b4
tab_085c8:
	dc.l	dat_0887a
	dc.l	dat_0882e
	dc.l	dat_087da
	dcb.b	22,$00
	dc.w	$88c8,$0000,$88b4
tab_085f0:
	dc.l	dat_0887a
	dc.l	dat_0882e
	dc.l	dat_087da
	dcb.b	62,$00
	dc.w	$88c8,$0000,$88b4
tab_08640:
	dc.l	dat_0882e
	dc.l	dat_0887a
	dc.l	dat_08804
road_pattern_a:	; from: build_road_batmobile
	dc.w	$f0f0,$f050,$0000,$f0f1,$f150,$0000,$f1f2,$f150
	dc.w	$0000,$f0f9,$f950,$0000,$f9fa,$f950,$0000,$f0f0
	dc.w	$f059,$0000,$f1f2,$f151,$0000,$f0f9,$fa5a,$0000
	dc.w	$f1f0,$f950,$0000,$f0f0,$f051,$0000,$f0f9,$fa5a
	dc.w	$0000,$f9f9,$f151,$0000,$f9f9,$f151,$0000,$f1f1
	dc.w	$f050,$0000,$f0f0,$f150,$0000,$f0f0,$f959,$0000
	dc.w	$f8f8,$f858,$0000
	dc.b	'8G6%$%6GHI:+,+:I8',0
	dc.w	$f827,$2635,$4441
	dc.b	$18
	dc.b	'OL;*)8',0
	dc.b	$e8
	dc.b	'''%#%''()+-+)'
	dc.w	$e800,$a4f6,$faac,$0000
road_pattern_ptrs:	; from: build_road_batmobile
	dc.w	$0000,$86ac,$0000,$86b2,$0000,$86ac,$0000,$86c4
	dc.w	$0000,$86d2,$0000,$86e0,$0000,$86ac,$0000,$86b2
road_patterns:	; from: build_road_batmobile, tab_081a4
	dc.w	$1210,$1010,$1210,$1218,$1210,$1618,$1618,$1210
	dc.w	$1610,$1016,$1010,$1016,$1200,$1012,$1018,$1016
	dc.w	$1016,$1016,$1216,$1016,$1010,$1210,$1216,$1010
	dc.w	$1016,$1200,$1019,$1019,$1014,$1014,$1614,$1610
	dc.w	$1610,$1610,$1810,$1610,$1610,$1610,$1000,$1810
	dc.w	$1210,$1010,$1210,$1410,$1610,$1010,$1610,$1610
	dc.w	$1410,$1410,$1610,$1000,$1210,$1210,$1010,$1210
	dc.w	$1012,$1012,$1010,$1910,$1910,$1916,$1910,$1610
	dc.w	$1000,$1610,$1610,$1010,$1810,$1010,$1018,$1010
	dc.w	$1410,$1410,$1810,$1410,$1410,$1000,$1210,$1210
	dc.w	$1016,$1016,$1216,$1016,$1016,$1016,$1016,$1010
	dc.w	$1610,$1010,$1000,$1812,$1618,$1010,$1014,$1012
	dc.w	$1014,$1014,$1014,$1016,$1016,$1010,$1910,$1000
road_pattern_end:	; from: build_road_batmobile, build_road_batwing
	dc.w	$32c0,$0000
dat_087da:	; from: tab_0821c, tab_082d0, tab_0835c, tab_083d4, tab_084b0, tab_08528, ...
	dc.w	$0140,$2300,$0107,$0309,$0105,$0900,$0140,$1700
	dc.w	$0107,$0309,$0105,$0900,$0140,$1700,$0107,$0309
	dc.w	$0105,$0900,$0800,$0120,$ff00
dat_08804:	; from: tab_0826c, tab_08398, tab_0844c, tab_08474, tab_084d8, tab_0858c, ...
	dc.w	$0180,$2300,$0106,$030a,$0104,$0900,$0180,$1700
	dc.w	$0106,$030a,$0104,$0900,$0180,$1700,$0106,$030a
	dc.w	$0104,$0900,$0800,$0120,$ff00
dat_0882e:	; from: tab_0821c, tab_0826c, tab_082d0, tab_0835c, tab_08398, tab_083d4, ...
	dc.w	$1019,$1019,$1019,$1019,$1019,$1019,$1010,$1010
	dc.w	$1011,$2012,$1019,$1019,$1012,$1014,$1014,$1010
	dc.w	$1010,$1011,$2012,$1019,$1019,$1010,$1014,$1014
	dc.w	$1010,$1010,$1011,$2019,$1014,$1014,$1016,$1016
	dc.w	$1016,$1016,$1016,$1016,$f0f0,$f000
dat_0887a:	; from: tab_0821c, tab_0826c, tab_082d0, tab_0835c, tab_08398, tab_083d4, ...
	dc.w	$1019,$1019,$1019,$1019,$1a19,$1019,$1a19,$1a19
	dc.w	$1a19,$1019,$1a19,$1019,$1a19,$1019,$1a19,$1019
	dc.w	$1019,$1019,$1019,$1a19,$1019,$1019,$1a19,$1a19
	dc.w	$1019,$1a19,$1019,$f0f0,$f000
	dcb.b	20,$f8
	dcb.b	20,$f0
	dc.w	$0000,$8aec,$0000,$8b4c
tab_088e4:
	dc.l	wing_patterns
	dc.l	wing_patterns
	dc.w	$0000,$87d6
road_batwing:	; from: build_road_batwing
	dcb.b	506,$00
	dc.w	$88f0
wing_pattern_a:	; from: build_road_batwing
	dc.w	$f0f0,$f050,$0000,$f0f1,$f150,$0000,$f1f2,$f150
	dc.w	$0000,$f0f9,$f950,$0000,$f9fa,$f950,$0000,$f0f0
	dc.w	$f059,$0000,$f1f2,$f151,$0000,$f0f0,$f050,$0000
	dc.w	$f1f0,$f950,$0000,$f0f0,$f051,$0000,$f0f9,$fa5a
	dc.w	$0000,$f9f9,$f151,$0000,$f0f0,$f050,$0000,$f1f1
	dc.w	$f050,$0000,$f0f0,$f150,$0000,$f0f0,$f959,$0000
	dc.w	$f8f8,$f858,$0000
	dc.b	'8G6%$%6GHI:+,+:I8',0
	dc.w	$f827,$2635,$4441
	dc.b	$18
	dc.b	'OL;*)8',0
	dc.b	$e8
	dc.b	'''%#%''()+-+)'
	dc.w	$e800,$a4f6,$faac,$0000
wing_pattern_ptrs:	; from: build_road_batwing
	dc.w	$0000,$8b4c,$0000,$8b52,$0000,$8b72,$0000,$8b64
	dc.w	$0000,$8b72,$0000,$8b80,$0000,$8b64,$0000,$8b52
wing_patterns:	; from: build_road_batwing, tab_088e4
	dc.w	$1b10,$1b10,$1b10,$1b10,$1b10,$1b10,$1b10,$1b10
	dc.w	$1b10,$1b10,$1b10,$1b10,$1000,$1915,$1910,$1915
	dc.w	$1915,$1910,$1915,$1615,$1015,$1615,$1016,$1010
	dc.w	$1610,$1000,$1010,$1310,$1310,$1310,$1010,$1310
	dc.w	$1310,$1310,$1910,$1910,$1910,$1910,$1900,$1010
	dc.w	$1013,$1010,$1013,$1013,$1013,$1013,$1613,$1610
	dc.w	$1610,$1610,$1610,$1000,$1110,$1010,$1110,$1110
	dc.w	$1110,$1110,$1110,$1010,$1110,$1011,$1010,$1110
	dc.w	$1000,$101b,$1013,$1013,$1013,$101b,$1010,$1b10
	dc.w	$1b10,$1b16,$1316,$1013,$1013,$1000,$1110
	dc.b	$11
	dcb.b	22,$10
	dc.b	$00,$10,$16,$10,$16,$10,$16,$10,$10,$10,$1b
scenery_right_table:	; from: draw_roadside, roadside_collision
	dc.w	$101b,$101b,$101b,$101b,$101b,$101b,$101b,$1000
	dc.w	$0000,$e17c,$0000,$0004,$0010,$005e,$0000,$0000
	dc.w	$0002,$2538,$0101,$0018,$0058,$0098,$0000,$0000
	dc.w	$0002,$2b8c,$0101,$0000,$0070,$0098,$0000,$0000
	dc.w	$0002,$2538,$0201,$0018,$0058,$0098,$0000,$0000
	dc.w	$0002,$2b8c,$0201,$0000,$0070,$0098,$0000,$0000
	dc.w	$0000,$e17c,$0102,$0004,$0010,$005e
	dcb.b	22,$00
	dc.w	$d3c0,$0102,$0002,$0012,$0019,$0000,$0000,$0000
	dc.w	$d990,$0102,$0002,$0006,$0028,$0000,$0000,$0002
	dc.w	$6e70,$0301,$0000,$0058,$0098,$0000,$0000
scenery_left_table:	; from: draw_roadside, roadside_collision
	dc.w	$0002,$2b8c,$0102,$0000,$0070,$0098,$0000,$0000
	dc.w	$0000,$e17c,$0001,$0004,$0010,$005e,$002c,$0000
	dc.w	$0002,$6e70,$0101,$0000,$0058,$0098,$0070,$0000
	dc.w	$0002,$74e8,$0101,$0000,$0070,$0098,$0070,$0000
	dc.w	$0002,$6e70,$0201,$0000,$0058,$0098,$0070,$0000
	dc.w	$0002,$74e8,$0201,$0000,$0070,$0098,$0070,$0000
	dc.w	$0000,$e17c,$0102,$0004,$0010,$005e,$002c
	dcb.b	20,$00
	dc.w	$d3c0,$0102,$0002,$0012,$0019,$0019,$0000,$0000
	dc.w	$d990,$0102,$0002,$0006,$0028,$0028,$0000,$0002
	dc.w	$6e70,$0301,$0000,$0058,$0098,$0070,$0000,$0002
	dc.w	$74e8,$0102,$0000,$0070,$0098,$0070,$0000
is_batwing:	; from: level_start, engine_noise, level_setup, reset_level_vars, main_loop, check_end, ...
	dc.w	$0000
sound_paused:	; from: timerc_handler, engine_noise, check_end, lose_life, game_over_text, play_sfx_restore, ...
	dc.w	$0001
distance_left:	; from: level_setup, hud_count, restart_level
	dc.w	$03e7
balloons_left:	; from: level_setup, hud_count, advance_object
	dc.w	$0064
horizon_y:	; from: flip_screens, play_sfx_restore, draw_scenery
	dc.w	$0056
saved_sp:	; from: detect_1mb, bus_error_handler, reset_level_vars
	dc.w	$0000,$0000
distance_tick:	; from: reset_level_vars, restart_level, next_segment
	dc.w	$0000
damage_level:	; from: hud_update, draw_batmobile, draw_wing_flaps
	dc.w	$0000
restart_mode:	; from: reset_level_vars, main_loop, play_sfx_restore, grapple_control
	dc.w	$0000
traffic_timer:	; from: level_setup, spawn_balloons, spawn_traffic
	dc.w	$0000
traffic_rate:	; from: level_setup, spawn_traffic
	dc.w	$0000
turn_ahead:	; from: level_setup, restart_level, next_segment
	dc.w	$0000
sfx_active:	; from: engine_noise, engine_sfx, engine_sfx_done, play_sfx
	dc.w	$0000
sfx_requested:	; from: engine_noise, engine_sfx, engine_sfx_done, play_sfx
	dc.w	$0000
end_delay:	; from: check_end, batwing_control, draw_batwing_objects
	dc.w	$0000
roadside_left:	; from: init_course, update_roadside_strips, update_curve, draw_scenery
	dcb.b	16,$00
roadside_right:	; from: update_roadside_strips, update_curve, draw_scenery
	dcb.b	16,$00
vehicle:	; from: level_setup, engine_sfx, balloon_collide, traffic_collide, advance_object, roadside_collision, ...
	dcb.b	100,$00
explosions:	; from: balloon_cut, draw_batwing_objects
	dcb.b	60,$00
floaters:	; from: balloon_collide, draw_batwing_objects
	dcb.b	18,$00
objects:	; from: traffic_lanes, alloc_object_n, update_objects, next_segment
	dcb.b	336,$00
sort_ptr:	; from: update_objects, draw_objects
	dc.w	$0000,$0000
grapple_side:	; from: roadside_collision, vehicle_control, draw_batmobile
	dc.w	$0000
roadblock_due:	; from: spawn_roadblock, next_segment
	dc.w	$0000
level_end_state:	; from: check_end, time_up_text, lose_life, roadblock_reached, vehicle_control, draw_batwing_objects
	dc.w	$0000
stripe_phase:	; from: draw_road, stripe_toggle
	dc.w	$0000
stripe_side:	; from: draw_road, stripe_toggle
	dc.w	$0000
stripe_count_down:	; from: draw_road, stripe_toggle
	dc.w	$0000
speed:	; from: engine_noise, level_setup, hud_update, balloon_collide, roadblock_reached, traffic_collide, ...
	dc.w	$0000
speed_saved:	; from: engine_noise, hud_update, grapple_control
	dc.w	$0000
segments_moved:	; from: spawn_balloons, spawn_roadblock, spawn_traffic, advance_course, next_segment
	dc.w	$0000
course_bytes:	; from: draw_roadside, roadside_collision, grapple_control, batwing_control, next_segment, init_course, ...
	dcb.b	256,$00
road_position:	; from: grapple_control, vehicle_control, steer_physics, batwing_control, draw_batmobile, init_course, ...
	dc.w	$0000
segment_index:	; from: draw_roadside, grapple_control, batwing_control, next_segment, init_course, update_curve, ...
	dc.w	$0000
segment_fraction:	; from: advance_object, draw_roadside, roadside_collision, grapple_control, steer_physics, init_course, ...
	dc.w	$0000
segment_parity:	; from: next_segment, next_course_block
	dc.w	$0000
course_ptr:	; from: level_setup, init_course
	dc.w	$0000,$0000
course_block_ptr:	; from: next_course_block, init_course
	dc.w	$0000,$0000
stream_curve:	; from: next_segment, next_course_block
	dc.w	$0000,$0000
stream_hill:	; from: next_segment, next_course_block
	dc.w	$0000,$0000
stream_events:	; from: next_segment, next_course_block
	dc.w	$0000,$0000
stream_right:	; from: next_segment, next_course_block
	dc.w	$0000,$0000
stream_left:	; from: next_segment, next_course_block
	dc.w	$0000,$0000
curve_count:	; from: next_segment, next_course_block
	dc.b	$00
hill_count:	; from: next_segment, next_course_block
	dc.b	$00
right_count:	; from: next_segment, next_course_block
	dc.b	$00
left_count:	; from: next_segment, next_course_block
	dc.b	$00
event_count:	; from: next_segment, next_course_block
	dc.b	$00
event_value:	; from: next_segment, next_course_block
	dc.b	$00
road_width:	; from: update_objects, compute_road_edge
	dc.b	$60
line_heights:	; from: draw_roadside, roadside_collision, draw_road, compute_hill_heights
	dcb.b	23,$00
edge_deltas:	; from: compute_road_edge
	dcb.b	44,$00
line_min_heights:	; from: draw_roadside, compute_hill_heights
	dcb.b	23,$00
roadside_row_steps:	; from: build_roadside_positions
	dcb.b	21,$00

; Font, 40 bytes per character.
font:	; from: print_text
	incbin	"data/font.bin"		; $640 bytes of data

; Sprite headers, 16 bytes each (x offset, width, height, lines, relative graphic pointer);
; update_distance draws entry turn_ahead (0 left, 1 straight, 2 right) as the turn arrow.
sprite_headers:	; from: restart_level
	dc.w	$0020,$0002,$0018,$000f,$0000,$0028,$0000,$0000
	dc.w	$0020,$0002,$0018,$000f,$0000,$0180,$0000,$0000
	dc.w	$0020,$0002,$0018,$001c,$0000,$02d8,$0000,$0000
	dc.w	$fffe,$fffe,$0000,$0000,$0000,$0001,$3fff,$3fff
	dc.w	$0000,$0000,$0000,$c000,$fff8,$fff8,$0001,$0000
	dc.w	$0001,$0006,$3fff,$3fff,$c000,$4000,$c000,$4000
	dc.w	$ffe0,$ffe0,$0006,$0001,$0007,$0018,$3fff,$3fff
	dc.w	$c000,$4000,$c000,$4000,$ff80,$ff80,$0018,$0007
	dc.w	$001f,$0060,$0003,$0003,$c000,$4000,$c000,$7ffc
	dc.w	$fe00,$fe00,$0060,$001f,$007f,$0180,$0003,$0003
	dc.w	$7ff8,$8000,$fff8,$0004,$f800,$f800,$0180,$047f
	dc.w	$01ff,$0200,$0003,$0003,$0000,$fff8,$fff8,$0004
	dc.w	$e000,$e000,$1600,$09ff,$07ff,$1000,$0003,$0003
	dc.w	$0000,$fffc,$fff8,$0000,$c000,$c000,$3800,$07ff
	dc.w	$1fff,$2000,$0003,$0003,$0000,$fffc,$fff8,$0000
	dc.w	$e000,$e000,$1800,$1fff,$1fff,$1800,$0003,$0003
	dc.w	$0004,$fff8,$fff8,$0004,$f800,$f800,$0600,$07ff
	dc.w	$07ff,$0600,$0003,$0003,$0004,$fff8,$fff8,$0004
	dc.w	$fe00,$fe00,$0180,$01ff,$01ff,$0180,$0003,$0003
	dc.w	$0004,$fffc,$fffc,$0004,$ff80,$ff80,$0060,$007f
	dc.w	$007f,$0060,$0003,$0003,$7ffc,$fffc,$fffc,$7ffc
	dc.w	$ffe0,$ffe0,$0018,$001f,$001f,$0018,$3fff,$3fff
	dc.w	$4000,$c000,$c000,$4000,$fff8,$fff8,$0006,$0007
	dc.w	$0007,$0006,$3fff,$3fff,$4000,$c000,$c000,$4000
	dc.w	$fffe,$fffe,$0001,$0001,$0001,$0001,$3fff,$3fff
	dc.w	$c000,$c000,$c000,$c000,$fffc,$fffc,$0000,$0000
	dc.w	$0000,$0003,$7fff,$7fff,$0000,$0000,$0000,$8000
	dc.w	$fffc,$fffc,$0003,$0002,$0003,$0002,$1fff,$1fff
	dc.w	$8000,$0000,$8000,$6000,$fffc,$fffc,$0003,$0002
	dc.w	$0003,$0002,$07ff,$07ff,$6000,$8000,$e000,$1800
	dc.w	$c000,$c000,$0003,$0002,$0003,$3ffe,$01ff,$01ff
	dc.w	$1800,$e000,$f800,$0600,$c000,$c000,$1ffe,$0001
	dc.w	$1fff,$2000,$007f,$007f,$0600,$f800,$fe00,$0180
	dc.w	$c000,$c000,$0000,$1fff,$1fff,$2000,$001f,$001f
	dc.w	$0180,$fe20,$ff80,$0040,$c000,$c000,$0000,$3fff
	dc.w	$1fff,$0000,$0007,$0007,$0068,$ff90,$ffe0,$0008
	dc.w	$c000,$c000,$0000,$3fff,$1fff,$0000,$0003,$0003
	dc.w	$001c,$ffe0,$fff8,$0004,$c000,$c000,$2000,$1fff
	dc.w	$1fff,$2000,$0007,$0007,$0018,$fff8,$fff8,$0018
	dc.w	$c000,$c000,$2000,$1fff,$1fff,$2000,$001f,$001f
	dc.w	$0060,$ffe0,$ffe0,$0060,$c000,$c000,$2000,$3fff
	dc.w	$3fff,$2000,$007f,$007f,$0180,$ff80,$ff80,$0180
	dc.w	$c000,$c000,$3ffe,$3fff,$3fff,$3ffe,$01ff,$01ff
	dc.w	$0600,$fe00,$fe00,$0600,$fffc,$fffc,$0002,$0003
	dc.w	$0003,$0002,$07ff,$07ff,$1800,$f800,$f800,$1800
	dc.w	$fffc,$fffc,$0002,$0003,$0003,$0002,$1fff,$1fff
	dc.w	$6000,$e000,$e000,$6000,$fffc,$fffc,$0003,$0003
	dc.w	$0003,$0003,$7fff,$7fff,$8000,$8000,$8000,$8000
	dc.w	$ffff,$ffff,$0000,$0000,$0000,$0000,$7fff,$7fff
	dc.w	$0000,$0000,$0000,$8000,$fffe,$fffe,$0000,$0000
	dc.w	$0000,$0001,$3fff,$3fff,$8000,$0000,$8000,$4000
	dc.w	$fffe,$fffe,$0000,$0000,$0000,$0001,$3fff,$3fff
	dc.w	$8000,$0000,$8000,$4000,$fffc,$fffc,$0001,$0000
	dc.w	$0001,$0002,$1fff,$1fff,$4000,$8000,$c000,$2000
	dc.w	$fffc,$fffc,$0001,$0000,$0001,$0002,$1fff,$1fff
	dc.w	$4000,$8000,$c000,$2000,$fff8,$fff8,$0002,$0001
	dc.w	$0003,$0004,$0fff,$0fff,$2000,$d000,$e000,$0000
	dc.w	$fff8,$fff8,$0002,$0001,$0003,$0004,$0fff,$0fff
	dc.w	$2000,$d000,$e000,$0000,$fff0,$fff0,$0004,$0003
	dc.w	$0007,$0008,$07ff,$07ff,$1000,$e800,$f000,$0000
	dc.w	$fff0,$fff0,$0004,$0003,$0007,$0008,$07ff,$07ff
	dc.w	$1000,$e800,$f000,$0000,$ffe0,$ffe0,$0008,$0007
	dc.w	$000f,$0010,$03ff,$03ff,$0c00,$f000,$f800,$0400
	dc.w	$ffe0,$ffe0,$0008,$0017,$000f,$0000,$03ff,$03ff
	dc.w	$0c00,$f000,$f800,$0400,$ffc0,$ffc0,$0010,$002f
	dc.w	$001f,$0000,$01ff,$01ff,$0600,$f800,$fc00,$0200
	dc.w	$ffc0,$ffc0,$0010,$002f,$001f,$0000,$01ff,$01ff
	dc.w	$0600,$f800,$fc00,$0200,$ff80,$ff80,$0060,$001f
	dc.w	$003f,$0040,$00ff,$00ff,$0300,$fc00,$fe00,$0100
	dc.w	$ff80,$ff80,$0060,$001f,$003f,$0040,$00ff,$00ff
	dc.w	$0300,$fc00,$fe00,$0100,$ff80,$ff80,$0078,$007f
	dc.w	$007f,$0078,$00ff,$00ff,$0f00,$ff00,$ff00,$0f00
	dc.w	$fff0,$fff0,$0008,$000f,$000f,$0008,$07ff,$07ff
	dc.w	$0800,$f800,$f800,$0800,$fff0,$fff0,$0008,$000f
	dc.w	$000f,$0008,$07ff,$07ff,$0800,$f800,$f800,$0800
	dc.w	$fff0,$fff0,$0008,$000f,$000f,$0008,$07ff,$07ff
	dc.w	$0800,$f800,$f800,$0800,$fff0,$fff0,$0008,$000f
	dc.w	$000f,$0008,$07ff,$07ff,$0800,$f800,$f800,$0800
	dc.w	$fff0,$fff0,$0008,$000f,$000f,$0008,$07ff,$07ff
	dc.w	$0800,$f800,$f800,$0800,$fff0,$fff0,$0008,$000f
	dc.w	$000f,$0008,$07ff,$07ff,$0800,$f800,$f800,$0800
	dc.w	$fff0,$fff0,$0008,$000f,$000f,$0008,$07ff,$07ff
	dc.w	$0800,$f800,$f800,$0800,$fff0,$fff0,$0008,$000f
	dc.w	$000f,$0008,$07ff,$07ff,$0800,$f800,$f800,$0800
	dc.w	$fff0,$fff0,$0008,$000f,$000f,$0008,$07ff,$07ff
	dc.w	$0800,$f800,$f800,$0800,$fff0,$fff0,$0008,$000f
	dc.w	$000f,$0008,$07ff,$07ff,$0800,$f800,$f800,$0800
	dc.w	$fff0,$fff0,$0008,$000f,$000f,$0008,$07ff,$07ff
	dc.w	$0800,$f800,$f800,$0800,$fff0,$fff0,$000f,$000f
	dc.w	$000f,$000f,$07ff,$07ff,$f800,$f800,$f800,$f800
stripe_masks:	; from: draw_road, build_shift_masks
	dcb.b	320,$00
edge_masks:	; from: draw_road
	dcb.b	320,$00
line_masks:	; from: draw_grapple_line
	dcb.b	512,$00
dat_0a228:	; from: build_shift_masks
	dc.w	$ffc0,$7f80,$3f00,$1e00,$0c00,$07c0,$0380,$0300
	dc.w	$0100,$0100,$a000,$e000,$a000,$a000,$4000,$e000
	dc.w	$0000,$0000
gfx_list_common:	; from: level_setup
	dc.w	$0001,$0013,$001f,$0000,$bc00,$0002,$0009,$0017
	dc.w	$0000,$c100,$0003,$0009,$0017,$0000,$c880,$0000
gfx_list_level2_512k:	; from: level_setup
	dc.w	$0005,$0002,$2538,$0005,$0002,$6e70,$0006,$0002
	dc.w	$c6c0,$0003,$0001,$0101,$0101,$0101,$0004,$0000
	dc.w	$e17c,$0004,$0000,$d990,$0004,$0000,$d3c0,$0004
	dc.w	$0002,$c910,$0007,$0002,$b7a8,$0004,$0002,$e380
	dc.w	$0004,$0002,$ee6c,$0004,$0002,$fc34,$0000
gfx_list_level2_1mb:	; from: level_setup
	dc.w	$000b,$0002,$2538,$000b,$0002,$6e70,$0006,$0002
	dc.w	$c6c0,$0003,$0001,$0101,$0101,$0101,$000a,$0000
	dc.w	$e17c,$000a,$0000,$d990,$000a,$0000,$d3c0,$000a
	dc.w	$0002,$c910,$0004,$0002,$b7a8,$000a,$0002,$e380
	dc.w	$000a,$0002,$ee6c,$000a,$0002,$fc34,$0000
gfx_list_level4_512k:	; from: level_setup
	dc.w	$0008,$0002,$2b8c,$0008,$0002,$74e8,$0009,$0000
	dc.w	$e17c,$0009,$0000,$d990,$0004,$0002,$f984,$0004
	dc.w	$0003,$0c74,$0004,$0003,$2ae0,$0004,$0003,$4274
	dc.w	$0000
gfx_list_level4_1mb:	; from: level_setup
	dc.w	$000b,$0002,$2b8c,$000b,$0002,$74e8,$000a,$0000
	dc.w	$e17c,$000a,$0000,$d990,$000a,$0002,$f984,$000a
	dc.w	$0003,$0c74,$000a,$0003,$2ae0,$000a,$0003,$4274
	dc.w	$0000
scenery_columns_mid:	; from: level_setup, draw_scenery
	dcb.b	32,$00
scenery_columns_left:	; from: draw_scenery
	dcb.b	32,$00
scenery_columns_sky:	; from: draw_scenery
	dcb.b	32,$00
scenery_map:	; from: level_setup
	dcb.b	48,$00
	dcb.b	512,$1a
	ifeq	CONFIG-BUDGET_1DISK
file_padding:
	dcb.b	31,$00
	dc.b	$ee,$ee,$ee
	endc

	end
