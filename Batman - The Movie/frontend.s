; Batman The Movie (Ocean, 1989) - front end, all versions
; Module frontend: frontend.bin, loaded at $20000, in scenes front.
; Size: RETAIL_2DISK 9212 bytes, RETAIL_1DISK 8551 bytes, BUDGET_1DISK 8582 bytes.
;
; Front end.  $20000 is the cold entry after boot, $20004 the entry after a
; level (game_flags bit5 = aborted -> restart, bit6 = level complete -> well
; done picture and tune 3, else game over picture and tune 2).  The screen is
; at $10000; pictures come from frontend.gfx and are decoded by decode_picture.
; The credits are a script interpreted by run_credits; the cheat code is typed
; as MAJJJJ (sets game_flags bit7).
;
; The module carries code that nothing calls (labels unused_*): a flip/fade/
; dissolve set and a sprite clipping routine copied from the level engines.
;
; Labels are named for what they do or hold; unused_ marks code that nothing
; calls.  A label still ending in its address (tab_ table, dat_ data) is one
; whose use is not known yet.  "; from:" lists the routines or modules that
; refer to a label (documentation only).

	include	"config.s"			; CONFIG: which version to assemble

; symbols in other modules
panel_reset_score	equ	$6b81c		; panel.s
panel_reset_lives	equ	$6b838		; panel.s
panel_flags	equ	$6b874		; panel.s
game_flags	equ	$6b875		; panel.s
panel_next_life_score	equ	$6b878		; panel.s
panel_score	equ	$6b87c		; panel.s
hiscore_text	equ	$6cf00		; panel.s
hiscore_last_name	equ	$6cf71		; panel.s
hiscore_entry_line	equ	$6cf88		; panel.s
hiscore_values	equ	$6cfa4		; panel.s
hiscore_last_value	equ	$6cfb4		; panel.s
snd_reset	equ	$6d400		; sound.s
snd_stop	equ	$6d404		; sound.s
snd_stop_music	equ	$6d408		; sound.s
snd_play_tune	equ	$6d410		; sound.s
snd_tick	equ	$6d418		; sound.s

	opt	o-
	org	$20000

front_entry:
	bra.w	front_init

front_after_level:
	bra.w	level_result


;----------------------------------------------------------------------
; Cold start: stack and screen at $10000, hardware init, then the title loop.
;----------------------------------------------------------------------
front_init:	; from: front_entry
	clr.l	panel_score

;----------------------------------------------------------------------
; Title: decode the title picture, start the music, run the high score / credits script.
;----------------------------------------------------------------------
front_main:	; from: level_result, unused_wait_restart
	lea	$10000,sp
	move.l	hiscore_values,panel_next_life_score
	clr.w	unused_flag
	bsr.w	hw_init
	jsr	snd_stop
	lea	$40000,a0                       ; frontend_gfx +$dc6
	lea	$18000,a1
	lea	picture_palette,a2
	bsr.w	decode_picture
	andi.w	#$f89f,panel_flags
	bsr.w	start_title_music
	lea	$18000,a0
	bsr.w	copy_picture
	bsr.w	hiscore_entry

;----------------------------------------------------------------------
; Fire was pressed in the credits: reset score and lives, leave through loader vector 1.
;----------------------------------------------------------------------
start_game:	; from: draw_entry_char
	moveq	#1,d0
	bsr.w	wait_frames
	move.l	hiscore_values,panel_next_life_score
	clr.l	panel_score
	jsr	panel_reset_score
	jsr	panel_reset_lives
	jsr	snd_stop_music
	jmp	$204                            ; loader section 1 (jmp $1004)


;----------------------------------------------------------------------
; Not reached: jmp to unused_colour_cycle (a debug loop).
;----------------------------------------------------------------------
unused_jump:
	jmp	unused_colour_cycle

unused_flag:	; from: front_main
	dc.w	$0000

handle_keys:	; from: timerc_handler
	bra.w	check_keys


;----------------------------------------------------------------------
; Hardware init: IKBD commands, VBL vector, MFP vectors to $100, timer C at 200 Hz.
;----------------------------------------------------------------------
hw_init:	; from: front_main, level_result
	jsr	snd_reset
	moveq	#0,d0
	move.w	#$2700,sr
	move.b	d0,$fffa07                      ; MFP IERA
	move.b	d0,$fffa09                      ; MFP IERB
	lea	$ff8240,a0                      ; palette 0
	moveq	#15,d1
clear_palette_loop:
	move.w	d0,(a0)+
	dbra	d1,clear_palette_loop
	move.l	#$10000,d0
	ror.l	#8,d0
	move.b	d0,$ff8203                      ; video base mid
	ror.l	#8,d0
	move.b	d0,$ff8201                      ; video base high
	lea	vbl_handler,a0
	move.l	a0,$70                          ; VBL vector
	lea	mfp_vectors,a0
	lea	$100,a1                         ; MFP vector 0 (Centronics busy)
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
	bra.w	clear_screen

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

; Not used: a palette and timer B split line copied from the level engines.
unused_palette_split:
	dc.w	$0000,$0001,$0444,$0777,$0030,$0400,$0600,$0666
	dc.w	$0555,$0333,$0000,$0630,$0751,$0770,$0774,$0222
	dc.w	$0098
unused_fade_palette:	; from: unused_fade_in, unused_fade_out
	dcb.b	34,$00

; Palette of the picture on screen, filled by decode_picture and set by vbl_handler.
picture_palette:	; from: front_main, vbl_handler, level_result
	dcb.b	32,$00
unused_target_palette:	; from: unused_fade_in
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
; Timer C: sound driver tick, keyboard decode, key handling.
;----------------------------------------------------------------------
timerc_handler:	; from: mfp_vectors
	bclr	#$5,$fffa11                     ; MFP ISRB
	move.w	#$2300,sr
	movem.l	d0-d7/a0-a6,-(sp)
	jsr	snd_tick
	bsr.w	keyboard_decode
	bsr.w	handle_keys
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
; Timer B: the palette split (split_ptr) copied from the level engines; the split line is 0 here.
;----------------------------------------------------------------------
timerb_handler:	; from: mfp_vectors
	movem.l	d0-d7/a0-a6,-(sp)
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
	movem.l	(sp)+,d0-d7/a0-a6
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
; VBL: set picture_palette, restart timer B for the split, toggle vbl_flag, cheat text, count frames.
;----------------------------------------------------------------------
vbl_handler:	; from: hw_init
	movem.l	d0-d7/a0-a6,-(sp)
	move.b	#$0,$fffa1b                     ; MFP TBCR
	lea	picture_palette(pc),a0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8240                   ; palette 0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8250
	move.w	(a0)+,d0
	move.l	a0,split_ptr
	move.b	d0,$fffa21                      ; MFP TBDR
	move.b	#$8,$fffa1b                     ; MFP TBCR
	not.w	vbl_flag
	bsr.w	draw_cheat_text
	addq.w	#1,vbl_count
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
	dc.b	$00,$00,$00
joy1_fire:	; from: keyboard_decode, draw_entry_char, hiscore_entry, entry_show_char
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

;----------------------------------------------------------------------
; Not called by anything: wait until no key is queued.
;----------------------------------------------------------------------
unused_flush_keys:
	move.l	d0,-(sp)
	bsr.s	get_key
flush_keys_loop:
	bne.s	flush_keys_loop
	move.l	(sp)+,d0
	rts


get_key:	; from: unused_flush_keys, check_keys
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
vbl_count:	; from: vbl_handler, unused_flip_screens, unused_fade_in, unused_fade_out
	dc.w	$0000
flip_wait:	; from: unused_flip_screens
	dc.w	$0000
screen_front:	; from: unused_flip_screens, unused_dissolve_in, run_credits, draw_entry_char
	dc.w	$0001,$0000
screen_back:	; from: print_text, draw_cheat_text
	dc.w	$0001,$8000

;----------------------------------------------------------------------
; Not called by anything: swap screen_front / screen_back and set the video base (level engine copy).
;----------------------------------------------------------------------
unused_flip_screens:
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
	rts


;----------------------------------------------------------------------
; Clear the $10000 screen.
;----------------------------------------------------------------------
clear_screen:	; from: hw_init
	lea	$10000,a0
	move.w	#$1f40,d7
clear_screen_loop:
	clr.l	(a0)+
	dbra	d7,clear_screen_loop
	rts


;----------------------------------------------------------------------
; Not called by anything: dissolve the back screen into the front one (level engine copy).
;----------------------------------------------------------------------
unused_dissolve_in:
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
	cmpi.w	#$c7,d4
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


;----------------------------------------------------------------------
; Not called by anything: fade unused_fade_palette up to unused_target_palette.
;----------------------------------------------------------------------
unused_fade_in:
	moveq	#15,d7
fade_in_pass:
	lea	unused_fade_palette,a0
	lea	unused_target_palette,a1
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


;----------------------------------------------------------------------
; Not called by anything: fade unused_fade_palette down to black.
;----------------------------------------------------------------------
unused_fade_out:
	moveq	#15,d7
fade_out_pass:
	lea	unused_fade_palette,a0
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


;----------------------------------------------------------------------
; Print text at a0 in bold (d6 = -1): byte row, byte column pairs then zero terminated strings, $ff ends.
;----------------------------------------------------------------------
print_text_bold:	; from: draw_cheat_text
	moveq	#-1,d6
	bra.s	text_position


;----------------------------------------------------------------------
; Not called directly (draw_cheat_text enters print_text_bold+2): the plain weight entry, d6 = 0.
;----------------------------------------------------------------------
print_text:
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

font:	; from: print_text
	incbin	"data/fe_font.bin"		; $640 bytes of data
no_key:	; from: check_keys
	clr.w	key_down_flag
	rts

toggle_music:	; from: check_keys
	jsr	snd_stop
	bchg	#$0,game_flags

start_title_music:	; from: front_main
	btst	#$0,game_flags
	beq.s	play_title_tune
	rts

play_title_tune:
	moveq	#4,d0
	jsr	snd_play_tune
	rts


;----------------------------------------------------------------------
; F2 toggles music (game_flags bit0); typing MAJJJJ enables the cheat (game_flags bit7).
;----------------------------------------------------------------------
check_keys:	; from: handle_keys
	bsr.w	get_key
	beq.s	no_key
	cmpi.b	#$82,d0
	beq.s	toggle_music
	move.b	d0,last_key
	lea	cheat_buffer_tail,a0
	moveq	#5,d0
shift_cheat_loop:
	move.b	(a0),-$1(a0)
	addq.l	#1,a0
	dbra	d0,shift_cheat_loop
	move.b	last_key,cheat_buffer_last
	lea	cheat_buffer,a0
	lea	cheat_code,a1
	moveq	#5,d0
compare_cheat_loop:
	cmpm.b	(a0)+,(a1)+
	bne.s	check_keys_exit
	dbra	d0,compare_cheat_loop
	bchg	#$7,game_flags
	move.w	#$1,wait_count

;----------------------------------------------------------------------
; Not called by anything: invert both screens.
;----------------------------------------------------------------------
unused_invert_screens:
	rts

	dc.w	$203c,$0000,$1ef0,$41f9,$0001,$0000,$43f9,$0001
	dc.w	$8000,$4698,$4699,$51c8,$fffa
check_keys_exit:	; from: check_keys
	rts

cheat_buffer:	; from: check_keys
	dc.b	$20
cheat_buffer_tail:	; from: check_keys
	dc.b	$20,$20,$20,$20
cheat_buffer_last:	; from: check_keys
	dc.b	$20
cheat_code:	; from: check_keys
	dc.w	$4d41,$4a4a,$4a4a

draw_cheat_text:	; from: vbl_handler
	btst	#$7,game_flags
	beq.s	cheat_text_exit
	lea	cheat_text,a0
	move.l	#$10000,screen_back
	bsr.w	print_text_bold
	lea	cheat_mode_text,a0
	move.l	#$10000,screen_back
	bra.w	print_text_bold

cheat_text_exit:
	rts

vbl_flag:	; from: vbl_handler, wait_frames
	dc.w	$0000,$0000
	dc.b	$00
last_key:	; from: check_keys
	dc.b	$00,$00,$00
key_down_flag:	; from: print_text
	dc.w	$0000,$0000,$0000,$0000

;----------------------------------------------------------------------
; Wait d0+1 frames (vbl_flag is toggled by the VBL).
;----------------------------------------------------------------------
wait_frames:	; from: start_game, draw_entry_char, hiscore_entry, level_result, unused_wait_restart
	tst.w	vbl_flag
	bne.s	wait_frames
	subi.w	#$1,vbl_flag
	dbra	d0,wait_frames
credits_exit:	; from: run_credits
	rts

text_col:	; from: run_credits, draw_entry_char
	dc.b	$00
text_col_start:	; from: run_credits
	dc.b	$00
text_row:	; from: run_credits, draw_entry_char
	dc.b	$00
text_row_start:	; from: run_credits
	dc.b	$00
script_start:	; from: run_credits, draw_entry_char
	dc.w	$0000,$0000,$0647,$0001,$33c7,$00ff,$8240,$4e75

;----------------------------------------------------------------------
; Credits script interpreter (a6): $ff end, $0d newline, $0a line feed, 1 clear, 2 wait, 3 high score
; text, 4 return, 5 high score entry, letters/digits in the big font at $3f1ea in frontend_gfx.
;----------------------------------------------------------------------
run_credits:	; from: draw_entry_char, hiscore_entry, entry_show_char
	move.l	a6,script_start
	move.b	(a6)+,text_col_start
	move.b	(a6)+,text_row_start
script_position:	; from: draw_entry_char
	moveq	#0,d0
	moveq	#0,d1
	move.w	text_row,d0
	move.w	text_col,d1
	mulu.w	#$a0,d0
	ext.w	d1
	move.w	d1,d5
	andi.w	#$fe,d1
	andi.w	#$1,d5
	lsl.w	#2,d1
	add.w	d5,d1
	add.w	d1,d0
	movea.l	screen_front,a2
	lea	$0(a2,d0.w),a2
script_same_line:
	movea.l	a2,a3
script_next:	; from: draw_entry_char
	tst.w	wait_count
	bne.w	wait_loop
	move.b	(a6)+,d0
	dc.w	$0c00,$ffff                     ; cmpi.b #$ff,d0
	beq.w	credits_exit
	cmpi.b	#$d,d0
	beq.w	script_newline
	cmpi.b	#$a,d0
	beq.w	script_linefeed
	cmpi.b	#$1,d0
	beq.w	script_clear
	cmpi.b	#$2,d0
	beq.w	script_wait
	cmpi.b	#$3,d0
	beq.w	script_hiscores
	cmpi.b	#$4,d0
	beq.w	script_return
	cmpi.b	#$5,d0
	beq.w	hiscore_entry
	cmpi.b	#$40,d0
	beq.w	char_copyright
	cmpi.b	#$26,d0
	beq.w	char_ampersand
	cmpi.b	#$2e,d0
	beq.w	char_dot
	andi.w	#$3f,d0
	beq.w	script_restart
	cmpi.b	#$20,d0
	beq.w	char_space
	cmpi.b	#$30,d0
	blt.w	draw_big_char
	subi.w	#$14,d0
	bra.w	draw_big_char

char_ampersand:
	move.w	#$2c,d0
	bra.w	draw_big_char

char_dot:
	move.w	#$2a,d0
	bra.w	draw_big_char

char_copyright:
	move.w	#$2b,d0
	bra.w	draw_big_char

char_space:
	bra.w	advance_big_column

draw_big_char:
	mulu.w	#$50,d0
	addi.l	#$3f1ea,d0
	exg	d0,a1
	movea.l	a3,a2
	moveq	#7,d7
big_char_loop:
	move.b	$10(a1),(a3)
	move.b	$20(a1),$2(a3)
	move.b	$30(a1),$4(a3)
	move.b	$40(a1),$6(a3)
	lea	$a0(a3),a3
	lea	$2(a1),a1
	dbra	d7,big_char_loop
advance_big_column:
	addi.w	#$1,text_col
	bra.w	script_position

	dc.w	$6000,$ff20,$4e75
entry_col:	; from: draw_entry_char, hiscore_entry, entry_show_char
	dc.w	$0000
entry_row:	; from: draw_entry_char, hiscore_entry
	dc.w	$0000

;----------------------------------------------------------------------
; Draw big character d0 at entry_col / entry_row (name entry).
;----------------------------------------------------------------------
draw_entry_char:	; from: entry_show_char
	movem.l	d0,-(sp)
	moveq	#0,d0
	moveq	#0,d1
	move.w	entry_row,d0
	move.w	entry_col,d1
	mulu.w	#$a0,d0
	ext.w	d1
	move.w	d1,d5
	andi.w	#$fe,d1
	andi.w	#$1,d5
	lsl.w	#2,d1
	add.w	d5,d1
	add.w	d1,d0
	movea.l	screen_front,a2
	lea	$0(a2,d0.w),a2
	movem.l	(sp)+,d0
	andi.l	#$3f,d0
	mulu.w	#$50,d0
	addi.l	#$3f1ea,d0
	exg	d0,a1
	moveq	#0,d1
	moveq	#7,d7
entry_char_loop:
	move.b	$10(a1),(a2)
	move.b	$20(a1),$2(a2)
	move.b	$30(a1),$4(a2)
	move.b	$40(a1),$6(a2)
	lea	$a0(a2),a2
	lea	$2(a1),a1
	dbra	d7,entry_char_loop
	rts

script_newline:	; from: run_credits
	move.w	#$7,text_col
	addi.w	#$8,text_row
	bra.w	script_position

script_linefeed:	; from: run_credits
	adda.l	#$140,a3
	movea.l	a3,a2
	bra.w	script_next

script_clear:	; from: run_credits
	bsr.w	restore_picture
	move.w	#$7,text_col
	clr.w	text_row
	bra.w	script_position

script_wait:	; from: run_credits
	move.b	(a6)+,d0
	move.b	d0,wait_count
	move.b	(a6)+,d0
	move.b	d0,wait_count_lo
wait_loop:	; from: run_credits
	moveq	#0,d0
	bsr.w	wait_frames
	tst.b	joy1_fire
	bne.s	fire_pressed
	subi.w	#$1,wait_count
	bra.w	script_next

fire_pressed:
	jmp	start_game

script_restart:	; from: run_credits
	movea.l	script_start,a6
	bra.w	run_credits

script_hiscores:	; from: run_credits
	move.l	a6,script_return_ptr
	movea.l	#hiscore_text,a6
	bra.w	script_next

script_return:	; from: run_credits
	movea.l	script_return_ptr,a6
	bra.w	script_next


;----------------------------------------------------------------------
; High score name entry into the panel module table (hiscore_values / the name lines above
; hiscore_last_name); joystick left/right picks a letter, fire enters it, three letters.
;----------------------------------------------------------------------
hiscore_entry:	; from: front_main, run_credits
	lea	hiscore_last_value,a5
	lea	hiscore_last_name,a4
	moveq	#0,d0
shift_scores_loop:
	move.l	(a5),d6
	cmp.l	panel_score,d6
	bgt.w	insert_score
	move.l	(a5),$4(a5)
	move.b	$a(a4),$21(a4)
	move.b	$b(a4),$22(a4)
	move.b	$c(a4),$23(a4)
	move.b	$f(a4),$26(a4)
	move.b	$10(a4),$27(a4)
	move.b	$11(a4),$28(a4)
	move.b	$12(a4),$29(a4)
	move.b	$13(a4),$2a(a4)
	move.b	$14(a4),$2b(a4)
	subq.l	#4,a5
	suba.l	#$17,a4
	addq.w	#1,d0
	cmpi.w	#$5,d0
	bne.w	shift_scores_loop
insert_score:
	tst.w	d0
	beq.w	run_title_script
	adda.l	#$4,a5
	adda.l	#$17,a4
	move.l	panel_score,(a5)
	move.b	#$20,$a(a4)
	move.b	#$20,$b(a4)
	move.b	#$20,$c(a4)
	movem.l	d0,-(sp)
	move.b	$3(a5),d0
	move.b	d0,d1
	andi.b	#$f,d0
	addi.w	#$30,d0
	lsr.b	#4,d1
	addi.w	#$30,d1
	move.b	d0,$14(a4)
	move.b	d1,$13(a4)
	move.b	$2(a5),d0
	move.b	d0,d1
	andi.b	#$f,d0
	addi.w	#$30,d0
	lsr.b	#4,d1
	addi.w	#$30,d1
	move.b	d0,$12(a4)
	move.b	d1,$11(a4)
	move.b	$1(a5),d0
	move.b	d0,d1
	andi.b	#$f,d0
	addi.w	#$30,d0
	lsr.b	#4,d1
	addi.w	#$30,d1
	move.b	d0,$10(a4)
	move.b	d1,$f(a4)
	adda.l	#$a,a4
	lea	hiscore_columns,a0
	movem.l	(sp)+,d0
	asl.w	#1,d0
	move.w	$0(a0,d0.w),entry_row
	move.w	#$11,entry_col
	move.w	#$3,entry_chars_left
	move.b	#$4,hiscore_entry_line
	lea	entry_script,a6
	bsr.w	run_credits
	moveq	#1,d6
	bsr.w	entry_show_char
entry_poll:	; from: entry_show_char
	moveq	#4,d0
	bsr.w	wait_frames
	clr.l	entry_left
	clr.w	entry_spare
	move.w	joy1_fire,d0
	btst	#$3,d0
	sne	entry_right
	btst	#$2,d0
	sne	entry_left
	tst.b	joy1_fire
	bne.w	entry_accept
	move.w	entry_left,d0
	or.w	entry_right,d0
	beq.s	entry_poll
	tst.w	entry_left
	bne.w	entry_prev_char
	cmpi.w	#$1b,d6
	beq.w	entry_poll
	addq.w	#1,d6
	bra.w	entry_show_char

entry_prev_char:
	cmpi.w	#$1,d6
	beq.w	entry_poll
	subq.w	#1,d6

entry_show_char:	; from: hiscore_entry
	move.b	d6,d0
	bsr.w	draw_entry_char
	bra.w	entry_poll

entry_accept:	; from: hiscore_entry
	tst.b	joy1_fire
	bne.w	entry_accept
	addi.w	#$1,entry_col
	move.b	d6,d0
	cmpi.b	#$1c,d0
	bne.w	entry_store_char
	move.w	#$ffe0,d0
entry_store_char:
	addi.b	#$40,d0
	move.b	d0,(a4)+
	subi.w	#$1,entry_chars_left
	beq.w	entry_done
	move.b	d6,d0
	bsr.w	draw_entry_char
	bra.w	entry_poll

entry_done:
	tst.b	joy1_fire
	bne.s	entry_done
	move.w	#$60,wait_count
run_title_script:	; from: hiscore_entry
	lea	credits_script,a6
	bra.w	run_credits

hiscore_columns:	; from: hiscore_entry
	dc.w	$0058,$0060,$0050,$0040,$0030,$0020
entry_chars_left:	; from: hiscore_entry, entry_show_char
	dc.w	$0000
entry_left:	; from: hiscore_entry
	dc.w	$0000
entry_right:	; from: hiscore_entry
	dc.w	$0000
entry_spare:	; from: hiscore_entry
	dc.w	$0000
script_return_ptr:	; from: draw_entry_char
	dc.w	$0000,$0000
wait_count:	; from: check_keys, run_credits, draw_entry_char, entry_show_char
	dc.b	$00
wait_count_lo:	; from: draw_entry_char
	dc.b	$00
credits_script:	; from: entry_show_char
	dc.w	$0101,$010d,$0d0d,$0d0d
	dc.b	$0d
	dc.b	'      OCEAN SOFTWARE'
	dc.b	$0d,$0d
	dc.b	'         PRESENTS   '
	dc.b	$0d,$02,$00,$80,$01,$0d,$0d,$0d,$0d,$0d,$0d
	dc.b	'          BATMAN'
	dc.w	$0d0d
	dc.b	'        THE MOVIE.'
	dc.w	$0200,$8001,$0d0d
	dc.b	'   TM & @ DC COMICS INC.'
	dc.b	$0d
	dc.b	'           1989 '
	dc.b	$0d,$0d,$0d
	dc.b	'   @ OCEAN SOFTWARE 1989'
	dc.w	$0d0d
	dc.b	$0d
	dc.b	'     ESC..ABORT GAME'
	dc.b	$0d,$0d
	dc.b	'      F1..PAUSE GAME'
	dc.b	$0d,$0d
	dc.b	'      F2..TOGGLE MUSIC & FX'
	dc.w	$0d02,$0100,$010d
	dc.b	'   CODING BY'
	dc.b	$0d
	dc.b	'            MIKE LAMB'
	dc.b	$0d
	dc.b	'            JOBBEEEE'
	dc.b	$0d
	dc.b	'            SHORTY'
	dc.w	$0d0d
	dc.b	'   GRAPHICS BY'
	dc.b	$0d
	dc.b	'            DAWN DRAKE'
	dc.b	$0d
	dc.b	'            BILL HARBISON'
	dc.b	$0d
	dc.b	'            JOHN PALMER'
	dc.b	$0d,$0d
	dc.b	'   MUSIC AND FX BY'
	dc.b	$0d
	dc.b	'            JON DUNN'
	dc.b	$0d
	dc.b	'            MATTHEW CANNON'
	dc.b	$02,$01,$00,$01,$03,$02,$00,$f0,$01,$00,$00
entry_script:	; from: hiscore_entry
	dc.w	$0c30,$010d,$03ff

;----------------------------------------------------------------------
; Copy the top of the picture at $18000 back to the screen (clears the credits text).
;----------------------------------------------------------------------
restore_picture:	; from: draw_entry_char
	lea	$18000,a0
	bra.w	copy_picture_top

	dc.w	$0000,$0000
unused_sprite_screen:	; from: unused_sprite_clip
	dc.w	$0000,$0000

;----------------------------------------------------------------------
; Not called by anything: a copy of the level 3 sprite_clip routine (see level3.s) with its
; variables at unused_sprite_width ...; left over from the shared code base.
;----------------------------------------------------------------------
unused_sprite_clip:
	moveq	#0,d0
	move.w	#$28,(a4)
	movem.l	a0,-(sp)
	move.w	(a6),d0
	mulu.w	#$1c,d0
	lea	unused_sprite_table,a0
	move.l	$0(a0,d0.l),unused_sprite_width
	move.l	$4(a0,d0.l),unused_plane_1
	move.l	$8(a0,d0.l),unused_plane_2
	move.l	$c(a0,d0.l),unused_plane_3
	move.l	$10(a0,d0.l),unused_plane_4
	move.l	$14(a0,d0.l),unused_plane_5
	move.l	$18(a0,d0.l),unused_plane_6
	movem.l	(sp)+,a0
	move.w	(a0),d0
	move.w	d0,d2
	andi.w	#$f,d2
	lsr.w	#3,d0
	move.w	$4(a0),d1
	addi.w	#$100,d1
	ext.w	d0
	addi.w	#$100,d0
	move.w	unused_sprite_height,d4
	move.w	d1,d3
	cmpi.w	#$1c7,d3
	bgt.w	sprite_clipped_out
	add.w	d4,d3
	cmpi.w	#$1c7,d3
	blt.w	clip_top
	subi.w	#$1c7,d3
	sub.w	d3,d4
	beq.s	sprite_clipped_out
	bpl.s	clip_top
sprite_clipped_out:
	clr.l	unused_sprite_dest
	rts

clip_top:
	cmpi.w	#$100,d1
	bgt.w	clip_left
	move.w	d1,d3
	add.w	d4,d3
	subi.w	#$100,d3
	bmi.w	sprite_clipped_out
	move.w	d3,d4
	beq.w	sprite_clipped_out
	sub.w	unused_sprite_height,d3
	neg.w	d3
	mulu.w	unused_sprite_width,d3
	add.l	d3,unused_plane_1
	add.l	d3,unused_plane_2
	add.l	d3,unused_plane_3
	add.l	d3,unused_plane_4
	add.l	d3,unused_plane_5
	add.l	d3,unused_plane_6
	move.w	#$100,d1
clip_left:
	clr.w	(a5)
	cmpi.w	#$128,d0
	bgt.w	sprite_clipped_out
	cmpi.w	#$100,d0
	bgt.w	clip_right
	move.w	d0,d3
	subi.w	#$100,d3
	bmi.w	sprite_clipped_out
	nop
	move.w	#$100,d0
clip_right:
	move.w	d0,d3
	add.w	unused_sprite_width,d3
	cmpi.w	#$128,d3
	blt.w	sprite_visible
	bra.w	sprite_clipped_out

sprite_visible:
	move.w	unused_sprite_width,d6
	sub.w	d6,(a4)
	subi.w	#$100,d0
	subi.w	#$100,d1
	mulu.w	#$28,d1
	add.l	d1,d0
	move.l	unused_sprite_screen,d1
	add.l	d0,d1
	move.l	d1,unused_sprite_dest
	asl.w	#8,d2
	asl.w	#4,d2
	move.w	d2,unused_sprite_buffer
	move.w	unused_sprite_width,d5
	mulu.w	d4,d5
	move.l	d5,unused_sprite_size
	move.w	unused_sprite_width,d5
	lsr.w	#1,d5
	asl.w	#6,d4
	or.w	d4,d5
	move.w	d5,(a2)
	rts


;----------------------------------------------------------------------
; Not called by anything: clears the three words at unused_sprite_pos.
;----------------------------------------------------------------------
unused_clear_vars:
	lea	unused_sprite_pos,a0
	move.w	#$2,d7
clear_vars_loop:
	clr.w	(a0)+
	dbra	d7,clear_vars_loop
	rts


; Not used: the rest of the unused sprite code data.
unused_sprite_sizes:
	dc.w	$0000,$0018,$0000,$0012
	dcb.b	24,$00
unused_sprite_pos:	; from: unused_clear_vars
	dcb.b	22,$00
unused_sprite_table:	; from: unused_sprite_clip
	dc.w	$000c,$001c,$0005,$0000,$0005,$0150,$0005,$02a0
	dc.w	$0005,$03f0,$0005,$0540,$0002,$19d8,$0000,$0000
	dc.w	$0000
unused_sprite_width:	; from: unused_sprite_clip
	dc.w	$0000
unused_sprite_height:	; from: unused_sprite_clip
	dc.w	$0000
unused_sprite_size:	; from: unused_sprite_clip
	dc.w	$0000,$0000
unused_plane_1:	; from: unused_sprite_clip
	dc.w	$0000,$0000
unused_plane_2:	; from: unused_sprite_clip
	dc.w	$0000,$0000
unused_plane_3:	; from: unused_sprite_clip
	dc.w	$0000,$0000
unused_plane_4:	; from: unused_sprite_clip
	dc.w	$0000,$0000
unused_plane_5:	; from: unused_sprite_clip
	dc.w	$0000,$0000
unused_plane_6:	; from: unused_sprite_clip
	dc.w	$0000,$0000
unused_sprite_dest:	; from: unused_sprite_clip
	dc.w	$0000,$0000,$0000

; Work area of the unused sprite code: $2aa bytes of $ff then zeros.
unused_sprite_buffer:	; from: unused_sprite_clip
	dc.w	$0000
	dcb.b	680,$ff
	dcb.b	680,$00
	dc.w	$4e75

;----------------------------------------------------------------------
; Not called by anything: copy 32 words from a0 to every other word at a1.
;----------------------------------------------------------------------
unused_copy_words:
	move.w	#$1f,d0
copy_words_loop:
	move.w	(a0)+,(a1)
	addq.l	#4,a1
	dbra	d0,copy_words_loop
	rts


;----------------------------------------------------------------------
; Decode a packed picture from frontend_gfx to $18000, then copy_picture moves it to the screen.
;----------------------------------------------------------------------
decode_picture:	; from: front_main, level_result
	movem.l	d0-d1/d7/a0-a3,-(sp)
	move.b	(a0)+,d0
	cmpi.b	#$3,d0
	bcs.s	copy_palette
	adda.l	#$4,a0
copy_palette:
	moveq	#31,d0
copy_palette_loop:
	move.b	(a0)+,(a2)+
	dbra	d0,copy_palette_loop
	move.b	(a0)+,d7
	asl.w	#8,d7
	move.b	(a0)+,d7
	addq.l	#2,a0
	lea	$0(a0,d7.w),a2
	subq.w	#1,d7
	bmi.s	decode_exit
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
decode_exit:
	movem.l	(sp)+,d0-d1/d7/a0-a3
	rts


next_picture_line:	; from: decode_picture
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
; Copy the picture at a0 to the screen at $10000 (32000 bytes).
;----------------------------------------------------------------------
copy_picture:	; from: front_main, level_result
	movem.l	d0/a0-a1,-(sp)
	lea	$10000,a1
	move.w	#$17c,d0
copy_picture_loop:
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	dbra	d0,copy_picture_loop
	movem.l	(sp)+,d0/a0-a1
	rts


;----------------------------------------------------------------------
; Copy the top $dd*84 bytes of the picture at a0 to the screen.
;----------------------------------------------------------------------
copy_picture_top:	; from: restore_picture
	movem.l	d0/a0-a1,-(sp)
	lea	$10000,a1
	move.w	#$dc,d0
copy_top_loop:
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	movem.l	(a0)+,d1-d7
	movem.l	d1-d7,(a1)
	adda.l	#$1c,a1
	dbra	d0,copy_top_loop
	movem.l	(sp)+,d0/a0-a1
	rts

	dc.w	$4e75

;----------------------------------------------------------------------
; After a level: bit5 abort -> restart; bit6 complete -> picture frontend_gfx+$7202 and tune 3;
; else game over picture frontend_gfx+$4188 and tune 2.
;----------------------------------------------------------------------
level_result:	; from: front_entry
	bsr.w	hw_init
	btst	#$5,game_flags
	beq.s	not_aborted
	clr.l	panel_score
	bra.w	front_main

not_aborted:
	btst	#$6,game_flags
	beq.w	show_game_over
	lea	$4643c,a0                       ; frontend_gfx +$7202
	lea	$18000,a1
	lea	picture_palette,a2
	bsr.w	decode_picture
	lea	$18000,a0
	bsr.w	copy_picture
	move.w	#$64,d0
	bsr.w	wait_frames
	moveq	#3,d0
	jsr	snd_play_tune
	move.w	#$200,d0
	bsr.w	wait_frames
	bra.w	front_main

show_game_over:
	bsr.w	hw_init
	lea	$433c2,a0                       ; frontend_gfx +$4188
	lea	$18000,a1
	lea	picture_palette,a2
	bsr.w	decode_picture
	lea	$18000,a0
	bsr.w	copy_picture
	move.w	#$14,d0
	bsr.w	wait_frames
	moveq	#2,d0
	jsr	snd_play_tune
	move.w	#$200,d0
	bsr.w	wait_frames
	bra.w	front_main


;----------------------------------------------------------------------
; Not reached: wait $200 frames and restart the title.
;----------------------------------------------------------------------
unused_wait_restart:
	move.w	#$200,d0
	bsr.w	wait_frames
	bra.w	front_main


;----------------------------------------------------------------------
; Not reached: cycle the background colour forever (debug).
;----------------------------------------------------------------------
unused_colour_cycle:	; from: unused_jump
	move.w	d0,$ff8240                      ; palette 0
	addq.w	#1,d0
	bra.w	unused_colour_cycle


; Not used: two palettes.
unused_palettes:
	dc.w	$0000,$0521,$0310,$0731,$0831,$0a41,$0b51,$0d61
	dc.w	$0e70,$0f80,$0f90,$0fa0,$0fb0,$0fc0,$0fe0,$0ff0
	dc.w	$0045,$0900,$0fff,$0033,$0067,$0222,$0333,$0444
	dc.w	$0f99,$0666,$0706,$0504,$099a,$0403,$0302,$0dde
cheat_text:	; from: draw_cheat_text
	dc.w	$0000
	dc.b	'CHEAT',0
	dc.b	$ff
cheat_mode_text:	; from: draw_cheat_text
	dc.b	$12,$00
	dc.b	'MODE.',0
	dc.b	$ff,$00
	ifne	CONFIG-RETAIL_1DISK
file_padding:
	ifeq	CONFIG-RETAIL_2DISK
	dcb.b	21,$00
	dcb.b	640,$1a
	endc
	ifeq	CONFIG-BUDGET_1DISK
	dcb.b	31,$00
	endc
	endc

	end
