; Batman The Movie (Ocean, 1989) - sound driver (resident PRG), all versions
; Module sound: sound.prg, loaded at $6d400, in scenes front, level1, level2, level3, level4, level5.
; Size: RETAIL_2DISK 9510 bytes, RETAIL_1DISK 9510 bytes, BUDGET_1DISK 9510 bytes.
; The file is a GEMDOS PRG without relocations; the 28 byte header is left out, so
; the text segment starts at $6d400 and its $400 byte BSS follows the code.
;
; Resident PSG sound driver.  Entry points at $6d400: three resets, play
; tune (d0 = 1..10), play effect (d0 = 1..20) and the 50 Hz tick.  Three music
; channels and three effect channels of $4a bytes each are mixed into a PSG
; register shadow that the tick writes out.  Tunes 1-10: 1 title, 2 game over,
; 3 well done, 4-5 level music, etc.  Samples are played on MFP timer A.
;
; Labels are named for what they do or hold; unused_ marks code that nothing
; calls.  A label still ending in its address (tab_ table, dat_ data) is one
; whose use is not known yet.  "; from:" lists the routines or modules that
; refer to a label (documentation only).

	include	"config.s"			; CONFIG: which version to assemble

	opt	o-
	org	$6d400


snd_reset:	; from: level1, frontend, level2_gfx
	bra.w	snd_init_channels


snd_stop:	; from: level1, frontend, level2_gfx
	bra.w	snd_init_channels


snd_stop_music:	; from: level1, frontend, level2_gfx
	bra.w	snd_init_channels

	dc.w	$6000,$03e6

;----------------------------------------------------------------------
; Play tune d0 (1..10) from snd_tune_table.
;----------------------------------------------------------------------
snd_play_tune:	; from: level1, frontend, level2_gfx
	bra.w	play_tune_body


;----------------------------------------------------------------------
; Play sound effect d0 (1..20) from snd_sfx_table.
;----------------------------------------------------------------------
snd_play_sfx:	; from: level1, level2_gfx
	bra.w	play_sfx_body


;----------------------------------------------------------------------
; Driver tick, called at 50 Hz from the level timer C / VBL handlers.
;----------------------------------------------------------------------
snd_tick:	; from: level1, frontend, level2_gfx
	bra.w	snd_tick_body

snd_tick_count:	; from: play_tune_body, snd_tick_body
	dc.w	$0000
snd_music_on:	; from: snd_tick_body
	dc.b	$01
snd_sfx_on:	; from: snd_tick_body
	dc.b	$01
snd_tune_playing:	; from: play_tune_body, snd_init_channels, snd_tick_body
	dc.b	$00
snd_sfx_playing:	; from: level1, play_sfx_body, snd_init_channels, unused_sfx_take_channels, snd_tick_body
	dc.b	$00
snd_disabled:	; from: unused_snd_pause, unused_snd_resume, snd_init_channels, snd_tick_body
	dc.w	$0000
sample_channel:	; from: play_sfx_body, snd_init_channels, unused_sfx_take_channels, snd_tick_body, snd_sequence_channel, cmd_end, ...
	dc.w	$0000
sample_end:	; from: snd_sample_start
	dc.w	$0000,$0000
sample_pos:
	dc.w	$0000,$0000,$0000
snd_music_chan_a:	; from: play_tune_body, snd_init_channels, unused_sfx_take_channels, snd_tick_body
	dcb.b	71,$00
	dc.b	$09,$08,$00
snd_music_chan_b:	; from: snd_init_channels, snd_tick_body
	dcb.b	70,$00
	dc.w	$0112,$0900
snd_music_chan_c:	; from: snd_init_channels, snd_tick_body
	dcb.b	70,$00
	dc.w	$0224,$0a00
snd_sfx_chan_a:	; from: play_sfx_body, snd_init_channels, snd_tick_body
	dcb.b	71,$00
	dc.b	$09,$08,$00
snd_sfx_chan_b:	; from: snd_init_channels, snd_tick_body
	dcb.b	70,$00
	dc.w	$0112,$0900
snd_sfx_chan_c:	; from: snd_init_channels, snd_tick_body
	dcb.b	70,$00
	dc.w	$0224,$0a00
psg_a_fine:	; from: snd_tick_body
	dc.b	$00
psg_a_coarse:	; from: snd_tick_body
	dc.b	$00
psg_b_fine:	; from: snd_tick_body
	dc.b	$00
psg_b_coarse:	; from: snd_tick_body
	dc.b	$00
psg_c_fine:	; from: snd_tick_body
	dc.b	$00
psg_c_coarse:	; from: snd_tick_body
	dc.b	$00
psg_noise:	; from: snd_tick_body, snd_sequence_channel
	dc.b	$00
psg_mixer:	; from: snd_tick_body, snd_sequence_channel
	dc.b	$00
psg_vol_a:	; from: snd_init_channels, snd_tick_body
	dc.b	$00
psg_vol_b:	; from: snd_init_channels, snd_tick_body
	dc.b	$00
psg_vol_c:	; from: snd_init_channels, snd_tick_body
	dc.w	$0000

;----------------------------------------------------------------------
; Not called by anything: pause.  Keep the timer A control in snd_disabled (-1 when timer A
; was stopped), stop timer A and silence the PSG.
;----------------------------------------------------------------------
unused_snd_pause:
	move.b	$fffffa19.w,d0                  ; MFP TACR
	bne.w	snd_pause_store
	moveq	#-1,d0
snd_pause_store:
	move.b	d0,snd_disabled
	clr.b	$fffffa19.w                     ; MFP TACR
	bra.w	psg_silence


;----------------------------------------------------------------------
; Not called by anything: resume after unused_snd_pause.  Restart timer A as it was and clear
; snd_disabled.
;----------------------------------------------------------------------
unused_snd_resume:
	move.b	snd_disabled,d0
	bmi.w	snd_resume_clear
	move.b	d0,$fffffa19.w                  ; MFP TACR
snd_resume_clear:
	clr.b	snd_disabled
	rts


;----------------------------------------------------------------------
; Start tune d0: 8 bytes per tune in snd_tune_table (three pattern list offsets), each channel
; record gets its list; list bytes: pattern number, $80 end, $81 jump, $82 repeat count, $83 transpose.
;----------------------------------------------------------------------
play_tune_body:	; from: snd_play_tune
	bsr.w	snd_init_channels
	clr.w	snd_tick_count
	subq.w	#1,d0
	bmi.w	play_tune_exit
	cmp.w	#$a,d0
	bcc.w	play_tune_exit
	lea	snd_tune_table(pc),a0
	asl.w	#3,d0
	lea	$0(a0,d0.w),a0
	lea	snd_music_chan_a,a1
	moveq	#2,d7
tune_channel_loop:
	move.w	(a0)+,d0
	beq.w	tune_next_channel
	lea	-$2(a0,d0.w),a2
	move.l	a2,$6(a1)
	move.b	#$0,$41(a1)
	move.b	#$1,$e(a1)
	move.b	#$1,$3f(a1)
	move.w	#$8000,(a1)
tune_list_byte:
	move.b	(a2)+,d0
	bpl.w	tune_set_pattern
	andi.b	#$7f,d0
	bne.w	tune_cmd_jump
	clr.w	(a1)
	bra.w	tune_next_channel

tune_cmd_jump:
	subq.b	#1,d0
	bne.w	tune_cmd_repeat
	move.b	(a2),d0
	ext.w	d0
	adda.w	d0,a2
	bra.s	tune_list_byte

tune_cmd_repeat:
	subq.b	#1,d0
	bne.w	tune_cmd_transpose
	move.b	(a2)+,$e(a1)
	bra.s	tune_list_byte

tune_cmd_transpose:
	subq.b	#1,d0
	bne.s	tune_list_byte
	move.b	(a2)+,$41(a1)
	bra.s	tune_list_byte

tune_set_pattern:
	move.l	a2,$a(a1)
	lea	pattern_data(pc),a2
	ext.w	d0
	add.w	d0,d0
	adda.w	d0,a2
	adda.w	(a2),a2
	move.l	a2,$2(a1)
tune_next_channel:
	lea	$4a(a1),a1
	dbra	d7,tune_channel_loop
	move.b	#$1,snd_tune_playing
play_tune_exit:
	rts


;----------------------------------------------------------------------
; Start effect d0: 8 bytes per effect in snd_sfx_table (three pattern offsets) on the effect channels.
;----------------------------------------------------------------------
play_sfx_body:	; from: snd_play_sfx
	clr.b	snd_sfx_playing
	subq.w	#1,d0
	bmi.w	stop_sfx_channels
	cmp.w	#$14,d0
	bcc.w	stop_sfx_channels
	lea	snd_sfx_table(pc),a0
	asl.w	#3,d0
	lea	$0(a0,d0.w),a0
	lea	snd_sfx_chan_a,a1
	moveq	#2,d7
sfx_channel_loop:
	move.w	(a0)+,d0
	beq.w	sfx_next_channel
	lea	-$2(a0,d0.w),a2
	move.l	a2,$2(a1)
	btst	#$8,$1(a1)
	beq.w	sfx_start_channel
	moveq	#0,d0
	move.b	d0,$fffffa19.w                  ; MFP TACR
	move.w	d0,sample_channel
sfx_start_channel:
	move.w	#$8000,(a1)
	move.b	#$1,$3f(a1)
sfx_next_channel:
	lea	$4a(a1),a1
	dbra	d7,sfx_channel_loop
	move.b	#$1,snd_sfx_playing
	rts


;----------------------------------------------------------------------
; Silence the PSG: volumes 0, mixer $f8, tone and noise registers 0.
;----------------------------------------------------------------------
psg_silence:	; from: unused_snd_pause, snd_init_channels
	lea	$ffff8800.w,a0                  ; PSG register select
	move.w	#$a00,d0
	moveq	#2,d1
	move.w	#$100,d2
psg_volume_loop:
	movep.w	d0,$0(a0)
	sub.w	d2,d0
	dbra	d1,psg_volume_loop
	move.w	#$7f8,d0
	movep.w	d0,$0(a0)
	move.w	#$600,d0
	moveq	#6,d1
psg_clear_loop:
	movep.w	d0,$0(a0)
	sub.w	d2,d0
	dbra	d1,psg_clear_loop
	rts


snd_init_channels:	; from: snd_reset, snd_stop, snd_stop_music, play_tune_body
	movem.l	d0-d2/a0,-(sp)
	moveq	#0,d0
	move.w	d0,snd_tune_playing
	move.b	d0,$fffffa19.w                  ; MFP TACR
	move.w	d0,sample_channel
	bsr.s	psg_silence
	moveq	#0,d0
	move.w	d0,snd_music_chan_a
	move.w	d0,snd_music_chan_b
	move.w	d0,snd_music_chan_c
	move.w	d0,snd_sfx_chan_a
	move.w	d0,snd_sfx_chan_b
	move.w	d0,snd_sfx_chan_c
	move.b	d0,snd_disabled
	move.b	d0,psg_vol_a
	move.b	d0,psg_vol_b
	move.b	d0,psg_vol_c
	movem.l	(sp)+,d0-d2/a0
	rts

stop_sfx_channels:	; from: play_sfx_body, unused_sfx_take_channels
	clr.b	snd_sfx_playing
	lea	snd_sfx_chan_a,a1
	moveq	#2,d7
stop_sfx_loop:
	btst	#$0,(a1)
	beq.w	stop_sfx_next
	moveq	#0,d0
	move.b	d0,$fffffa19.w                  ; MFP TACR
	move.w	d0,sample_channel
stop_sfx_next:
	clr.w	(a1)
	lea	$4a(a1),a1
	dbra	d7,stop_sfx_loop
	rts


;----------------------------------------------------------------------
; Not called by anything: for sound effect d0 (1-20), stop the music on each channel the
; effect uses (and timer A when that channel plays a sample), then set snd_sfx_playing.
;----------------------------------------------------------------------
unused_sfx_take_channels:
	clr.b	snd_sfx_playing
	subq.w	#1,d0
	bmi.s	stop_sfx_channels
	cmp.w	#$14,d0
	bcc.s	stop_sfx_channels
	lea	snd_sfx_table(pc),a0
	asl.w	#2,d0
	lea	$0(a0,d0.w),a0
	lea	snd_music_chan_a,a1
	moveq	#2,d7
take_channel_loop:
	move.w	(a0)+,d0
	beq.w	take_channel_next
	bclr	#$0,(a1)
	beq.w	take_channel_clear
	moveq	#0,d0
	move.b	d0,$fffffa19.w                  ; MFP TACR
	move.w	d0,sample_channel
take_channel_clear:
	clr.w	(a1)
take_channel_next:
	lea	$4a(a1),a1
	dbra	d7,take_channel_loop
	move.b	#$1,snd_sfx_playing
	rts


;----------------------------------------------------------------------
; Driver tick: sequence the three music and three effect channels into the PSG shadow,
; then write registers 0-7 and the volumes (except the one a sample is playing on).
;----------------------------------------------------------------------
snd_tick_body:	; from: snd_tick
	tst.b	snd_disabled
	bne.w	tick_exit
	move.b	#$ff,psg_mixer
	bclr	#$0,snd_tune_playing
	beq.w	tick_sfx
	addq.w	#1,snd_tick_count
	lea	snd_music_chan_a,a1
	move.w	(a1),d7
	bpl.w	tick_music_b
	bset	#$0,snd_tune_playing
	movea.l	$2(a1),a2
	bsr.w	snd_sequence_channel
	move.l	a2,$2(a1)
	move.w	d7,(a1)
	move.b	d1,psg_vol_a
	move.b	d0,psg_a_fine
	lsr.w	#8,d0
	move.b	d0,psg_a_coarse
	btst	#$5,d7
	beq.w	tick_music_b
	move.b	d0,psg_noise
tick_music_b:
	lea	snd_music_chan_b,a1
	move.w	(a1),d7
	bpl.w	tick_music_c
	bset	#$0,snd_tune_playing
	movea.l	$2(a1),a2
	bsr.w	snd_sequence_channel
	move.l	a2,$2(a1)
	move.w	d7,(a1)
	move.b	d1,psg_vol_b
	move.b	d0,psg_b_fine
	lsr.w	#8,d0
	move.b	d0,psg_b_coarse
	btst	#$5,d7
	beq.w	tick_music_c
	move.b	d0,psg_noise
tick_music_c:
	lea	snd_music_chan_c,a1
	move.w	(a1),d7
	bpl.w	tick_music_done
	bset	#$0,snd_tune_playing
	movea.l	$2(a1),a2
	bsr.w	snd_sequence_channel
	move.l	a2,$2(a1)
	move.w	d7,(a1)
	move.b	d1,psg_vol_c
	move.b	d0,psg_c_fine
	lsr.w	#8,d0
	move.b	d0,psg_c_coarse
	btst	#$5,d7
	beq.w	tick_music_done
	move.b	d0,psg_noise
tick_music_done:
	tst.b	snd_music_on
	bne.w	tick_sfx
	move.b	#$ff,psg_mixer
tick_sfx:
	tst.b	snd_sfx_on
	beq.w	tick_write_psg
	bclr	#$0,snd_sfx_playing
	beq.w	tick_write_psg
	lea	snd_sfx_chan_a,a1
	move.w	(a1),d7
	bpl.w	tick_sfx_b
	bset	#$0,snd_sfx_playing
	movea.l	$2(a1),a2
	bsr.w	snd_sequence_channel
	move.l	a2,$2(a1)
	move.w	d7,(a1)
	move.b	d1,psg_vol_a
	move.b	d0,psg_a_fine
	lsr.w	#8,d0
	move.b	d0,psg_a_coarse
	btst	#$5,d7
	beq.w	tick_sfx_b
	move.b	d0,psg_noise
tick_sfx_b:
	lea	snd_sfx_chan_b,a1
	move.w	(a1),d7
	bpl.w	tick_sfx_c
	bset	#$0,snd_sfx_playing
	movea.l	$2(a1),a2
	bsr.w	snd_sequence_channel
	move.l	a2,$2(a1)
	move.w	d7,(a1)
	move.b	d1,psg_vol_b
	move.b	d0,psg_b_fine
	lsr.w	#8,d0
	move.b	d0,psg_b_coarse
	btst	#$5,d7
	beq.w	tick_sfx_c
	move.b	d0,psg_noise
tick_sfx_c:
	lea	snd_sfx_chan_c,a1
	move.w	(a1),d7
	bpl.w	tick_write_psg
	bset	#$0,snd_sfx_playing
	movea.l	$2(a1),a2
	bsr.w	snd_sequence_channel
	move.l	a2,$2(a1)
	move.w	d7,(a1)
	move.b	d1,psg_vol_c
	move.b	d0,psg_c_fine
	lsr.w	#8,d0
	move.b	d0,psg_c_coarse
	btst	#$5,d7
	beq.w	tick_write_psg
	move.b	d0,psg_noise
tick_write_psg:
	move.b	snd_music_on,d0
	and.b	snd_tune_playing,d0
	move.b	snd_sfx_on,d1
	and.b	snd_sfx_playing,d1
	or.b	d1,d0
	beq.w	tick_exit
	lea	$ffff8800.w,a0                  ; PSG register select
	lea	psg_a_fine,a2
	moveq	#0,d0
	move.w	#$100,d1
	moveq	#7,d2
psg_write_loop:
	move.b	(a2)+,d0
	movep.w	d0,$0(a0)
	add.w	d1,d0
	dbra	d2,psg_write_loop
	move.w	sample_channel,d2
	move.w	#$800,d0
	cmp.w	d2,d0
	beq.w	psg_write_vol_b
	move.b	(a2)+,d0
	movep.w	d0,$0(a0)
psg_write_vol_b:
	move.w	#$900,d0
	cmp.w	d2,d0
	beq.w	psg_write_vol_c
	move.b	(a2)+,d0
	movep.w	d0,$0(a0)
psg_write_vol_c:
	move.w	#$a00,d0
	cmp.w	d2,d0
	beq.w	tick_exit
	move.b	(a2)+,d0
	movep.w	d0,$0(a0)
tick_exit:
	rts


;----------------------------------------------------------------------
; Run one channel (a1 record, a2 pattern position, d7 flags): a new note every note length,
; then per tick portamento, arpeggio, vibrato, release and volume envelope; bytes $80-$8f are
; commands, $90-$af volume envelope, $b0-$cf vibrato, $d0-$ef arpeggio, $f0-$f7 release, $f8-$ff drum.
;----------------------------------------------------------------------
snd_sequence_channel:	; from: snd_tick_body
	subq.b	#1,$3f(a1)
	bne.w	seq_update
seq_next_byte:	; from: cmd_jump, cmd_next_pattern, cmd_tone_only, cmd_noise_only, cmd_tone_noise, cmd_fixed_length, ...
	move.b	(a2)+,d0
	bmi.w	seq_command
	add.b	$41(a1),d0
	move.b	d0,$42(a1)
	btst	#$0,d7
	beq.w	seq_note
	add.b	$10(a1),d0
	move.b	$11(a1),$12(a1)
seq_note:
	move.b	d0,$43(a1)
	lea	snd_period_table(pc),a0
	ext.w	d0
	add.w	d0,d0
	move.w	$0(a0,d0.w),$44(a1)
	moveq	#1,d0
	move.l	$1c(a1),$20(a1)
	move.b	$24(a1),$25(a1)
	move.b	d0,$27(a1)
	move.l	$28(a1),$2c(a1)
	move.w	d0,$30(a1)
	move.l	$34(a1),$38(a1)
	move.b	d0,$3c(a1)
	moveq	#0,d0
	move.b	d0,$3d(a1)
	move.b	d0,$40(a1)
	bset	#$3,d7
	bclr	#$7,d7
	bclr	#$8,d7
	beq.w	seq_note_length
	moveq	#0,d0
	move.b	d0,$fffffa19.w                  ; MFP TACR
	move.w	d0,sample_channel
seq_note_length:	; from: cmd_hold, cmd_hold_sample, snd_sample_start
	move.b	$3e(a1),d0
	btst	#$6,d7
	bne.w	seq_store_length
	move.b	(a2)+,d0
seq_store_length:
	move.b	d0,$3f(a1)
seq_update:
	btst	#$8,d7
	beq.s	seq_not_sample
	move.b	psg_mixer,d0
	move.b	$47(a1),d1
	or.b	d1,d0
	andi.b	#$7,d1
	eor.b	d1,d0
	move.b	d0,psg_mixer
	moveq	#0,d0
	moveq	#0,d1
	bra.w	seq_exit

seq_not_sample:
	btst	#$7,d7
	beq.s	seq_tone
	movea.l	$18(a1),a0
	move.b	psg_mixer,d0
	move.b	$47(a1),d1
	or.b	d1,d0
	and.b	(a0)+,d1
	beq.w	seq_drum_silent
	eor.b	d1,d0
	move.b	d0,psg_mixer
	move.b	(a0)+,d1
	move.w	(a0)+,d0
	move.b	d0,psg_noise
	move.l	a0,$18(a1)
	bra.w	seq_exit

seq_drum_silent:
	moveq	#0,d0
	moveq	#0,d1
	bra.w	seq_exit

seq_tone:
	move.b	psg_mixer,d0
	or.b	$47(a1),d0
	move.b	$f(a1),d1
	eor.b	d1,d0
	move.b	d0,psg_mixer
	move.w	$44(a1),d0
	btst	#$0,d7
	beq.w	seq_arpeggio
	subq.b	#1,$12(a1)
	bcc.w	seq_arpeggio
	lea	snd_period_table(pc),a0
	move.b	$42(a1),d2
	move.b	d2,$43(a1)
	ext.w	d2
	add.w	d2,d2
	move.w	$0(a0,d2.w),d0
seq_arpeggio:
	btst	#$1,d7
	beq.w	seq_vibrato
	subq.b	#1,$27(a1)
	bne.w	seq_vibrato
	movea.l	$20(a1),a0
	move.b	(a0)+,d0
	subq.b	#1,$25(a1)
	bne.w	seq_arpeggio_store
	movea.l	$1c(a1),a0
	move.b	$24(a1),$25(a1)
seq_arpeggio_store:
	move.l	a0,$20(a1)
	move.b	$26(a1),$27(a1)
	lea	snd_period_table(pc),a0
	add.b	$43(a1),d0
	ext.w	d0
	add.w	d0,d0
	move.w	$0(a0,d0.w),d0
seq_vibrato:
	btst	#$2,d7
	beq.w	seq_store_period
	subq.w	#1,$30(a1)
	bne.w	seq_vibrato_add
	movea.l	$2c(a1),a0
	move.w	(a0)+,$30(a1)
	bpl.w	seq_vibrato_store
	adda.w	(a0),a0
	move.w	(a0)+,$30(a1)
seq_vibrato_store:
	move.w	(a0)+,$32(a1)
	move.l	a0,$2c(a1)
seq_vibrato_add:
	add.w	$32(a1),d0
seq_store_period:
	move.w	d0,$44(a1)
	btst	#$4,d7
	beq.w	seq_envelope
	move.b	$13(a1),d1
	cmp.b	$3f(a1),d1
	bne.w	seq_envelope
	move.l	$14(a1),$38(a1)
	move.b	#$1,$3c(a1)
seq_envelope:
	btst	#$3,d7
	beq.w	seq_volume
	subq.b	#1,$3c(a1)
	bne.w	seq_volume
	movea.l	$38(a1),a0
	move.b	(a0)+,$3c(a1)
	beq.w	seq_volume
	bpl.w	seq_envelope_store
	move.b	(a0),d2
	ext.w	d2
	adda.w	d2,a0
	move.b	(a0)+,$3c(a1)
seq_envelope_store:
	move.b	(a0)+,$40(a1)
	move.l	a0,$38(a1)
seq_volume:
	move.b	$40(a1),d1
seq_exit:	; from: cmd_end
	rts

seq_command:
	cmp.b	#$90,d0
	bcs.w	seq_control
	addi.b	#$20,d0
	bcs.w	seq_envelope_set
	addi.b	#$20,d0
	bcs.w	seq_vibrato_set
	addi.b	#$20,d0
	bcs.w	seq_arpeggio_set
	addi.b	#$8,d0
	bcs.w	seq_release_set
	addi.b	#$8,d0
	bcs.w	seq_drum_set
	bra.w	seq_next_byte

seq_drum_set:
	lea	drum_patterns(pc),a0
	ext.w	d0
	add.w	d0,d0
	adda.w	d0,a0
	adda.w	(a0),a0
	move.l	a0,$18(a1)
	bset	#$7,d7
	bclr	#$8,d7
	beq.w	seq_note_length
	moveq	#0,d0
	move.b	d0,$fffffa19.w                  ; MFP TACR
	move.w	d0,sample_channel
	bra.w	seq_note_length

seq_release_set:
	beq.w	seq_release_off
	bset	#$4,d7
	lea	release_envelopes(pc),a0
	ext.w	d0
	add.w	d0,d0
	adda.w	d0,a0
	adda.w	(a0),a0
	move.b	(a0)+,$13(a1)
	move.l	a0,$14(a1)
	bra.w	seq_next_byte

seq_release_off:
	bclr	#$4,d7
	bra.w	seq_next_byte

seq_arpeggio_set:
	beq.w	seq_arpeggio_off
	bset	#$1,d7
	bclr	#$2,d7
	lea	arpeggio_shapes(pc),a0
	ext.w	d0
	add.w	d0,d0
	adda.w	d0,a0
	adda.w	(a0),a0
	move.b	(a0)+,$26(a1)
	move.b	(a0)+,$24(a1)
	move.l	a0,$1c(a1)
	move.b	#$1,$27(a1)
	bra.w	seq_next_byte

seq_arpeggio_off:
	bclr	#$1,d7
	bra.w	seq_next_byte

seq_vibrato_set:
	beq.w	seq_vibrato_off
	bset	#$2,d7
	bclr	#$1,d7
	lea	vibrato_shapes(pc),a0
	ext.w	d0
	add.w	d0,d0
	adda.w	d0,a0
	adda.w	(a0),a0
	move.l	a0,$28(a1)
	bra.w	seq_next_byte

seq_vibrato_off:
	bclr	#$2,d7
	bra.w	seq_next_byte

seq_envelope_set:
	lea	volume_envelopes(pc),a0
	ext.w	d0
	add.w	d0,d0
	adda.w	d0,a0
	adda.w	(a0),a0
	move.l	a0,$34(a1)
	bra.w	seq_next_byte

seq_control:
	lea	snd_command_table(pc),a0
	subi.b	#$80,d0
	ext.w	d0
	add.w	d0,d0
	adda.w	d0,a0
	move.w	(a0),d0
	beq.w	seq_next_byte
	jmp	$0(a0,d0.w)

snd_command_table:	; from: snd_sequence_channel
	dc.w	cmd_end-*
	dc.w	cmd_jump-*
	dc.w	cmd_next_pattern-*
	dc.w	cmd_tone_only-*
	dc.w	cmd_noise_only-*
	dc.w	cmd_tone_noise-*
	dc.w	cmd_hold-*
	dc.w	cmd_hold_sample-*
	dc.w	cmd_fixed_length-*
	dc.w	cmd_variable_length-*
	dc.w	cmd_portamento-*
	dc.w	cmd_portamento_off-*
	dc.w	cmd_sfx_vibrato-*
	dc.w	snd_sample_start-*
	dc.w	$0000,$0000

;----------------------------------------------------------------------
; Pattern commands $80-$8d: end, jump, next pattern, mixer modes, hold, note length modes,
; portamento on/off, effect vibrato, sample start.
;----------------------------------------------------------------------
cmd_end:	; from: snd_command_table, cmd_next_pattern
	bclr	#$8,d7
	beq.w	cmd_end_silence
	move.b	d0,$fffffa19.w                  ; MFP TACR
	move.w	d0,sample_channel
cmd_end_silence:
	moveq	#0,d7
	moveq	#0,d0
	moveq	#0,d1
	bra.w	seq_exit


cmd_jump:	; from: snd_command_table
	move.b	(a2),d0
	ext.w	d0
	adda.w	d0,a2
	bra.w	seq_next_byte


cmd_next_pattern:	; from: snd_command_table
	movea.l	$a(a1),a2
	move.b	-$1(a2),d0
	subq.b	#1,$e(a1)
	bne.w	pattern_set
	move.b	#$1,$e(a1)
	move.b	#$0,$41(a1)
pattern_list_byte:
	move.b	(a2)+,d0
	bpl.w	pattern_set
	andi.b	#$7f,d0
	beq.s	cmd_end
	subq.b	#1,d0
	bne.w	list_cmd_repeat
	move.b	(a2),d0
	ext.w	d0
	adda.w	d0,a2
	bra.s	pattern_list_byte

list_cmd_repeat:
	subq.b	#1,d0
	bne.w	list_cmd_transpose
	move.b	(a2)+,$e(a1)
	bra.s	pattern_list_byte

list_cmd_transpose:
	subq.b	#1,d0
	bne.s	pattern_list_byte
	move.b	(a2)+,$41(a1)
	bra.s	pattern_list_byte

pattern_set:
	move.l	a2,$a(a1)
	lea	pattern_data(pc),a2
	ext.w	d0
	add.w	d0,d0
	adda.w	d0,a2
	adda.w	(a2),a2
	bra.w	seq_next_byte


cmd_tone_only:	; from: snd_command_table
	moveq	#7,d0
	and.b	$47(a1),d0
	move.b	d0,$f(a1)
	bclr	#$5,d7
	bra.w	seq_next_byte


cmd_noise_only:	; from: snd_command_table
	moveq	#56,d0
	and.b	$47(a1),d0
	move.b	d0,$f(a1)
	bset	#$5,d7
	bra.w	seq_next_byte


cmd_tone_noise:	; from: snd_command_table
	moveq	#63,d0
	and.b	$47(a1),d0
	move.b	d0,$f(a1)
	bset	#$5,d7
	bra.w	seq_next_byte


cmd_hold:	; from: snd_command_table
	bra.w	seq_note_length


cmd_hold_sample:	; from: snd_command_table, snd_sample_start
	bra.w	seq_note_length


cmd_fixed_length:	; from: snd_command_table
	move.b	(a2)+,$3e(a1)
	bset	#$6,d7
	bra.w	seq_next_byte


cmd_variable_length:	; from: snd_command_table
	bclr	#$6,d7
	bra.w	seq_next_byte


cmd_portamento:	; from: snd_command_table
	bset	#$0,d7
	bclr	#$1,d7
	move.b	(a2)+,$10(a1)
	move.b	(a2)+,$11(a1)
	bra.w	seq_next_byte


cmd_portamento_off:	; from: snd_command_table
	bclr	#$0,d7
	bra.w	seq_next_byte


cmd_sfx_vibrato:	; from: snd_command_table
	bset	#$2,d7
	bclr	#$1,d7
	lea	sfx_vibrato_shapes(pc),a0
	moveq	#0,d0
	move.b	(a2)+,d0
	add.w	d0,d0
	adda.w	d0,a0
	adda.w	(a0),a0
	move.l	a0,$28(a1)
	bra.w	seq_next_byte


;----------------------------------------------------------------------
; Start a 4 bit sample on timer A: sample number, timer data and control bytes follow.
;----------------------------------------------------------------------
snd_sample_start:	; from: snd_command_table
	bclr	#$7,d7
	btst	#$8,d7
	bne.w	sample_setup
	tst.w	sample_channel
	bne.w	sample_skip
sample_setup:
	move.b	#$0,$fffffa19.w                 ; MFP TACR
	lea	snd_sample_data(pc),a0
	move.b	(a2)+,d0
	ext.w	d0
	asl.w	#2,d0
	adda.w	d0,a0
	movem.l	(a0),d0-d1
	add.l	a0,d0
	lea	$4(a0,d1.l),a0
	movem.l	d0/a0,sample_end
	move.w	$48(a1),sample_channel
	move.b	(a2)+,$fffffa1f.w               ; MFP TADR
	lea	snd_sample_timer_a(pc),a0
	move.l	a0,$134.w                       ; MFP timer A
	move.b	(a2)+,$fffffa19.w               ; MFP TACR
	bset	#$8,d7
	bra.w	seq_note_length

sample_skip:
	addq.l	#3,a2
	bra.w	cmd_hold_sample


;----------------------------------------------------------------------
; Timer A: write the low nibble of the sample byte as the channel volume, then the high one
; (sample_irq_high) and advance; the border colour shows the time used.
;----------------------------------------------------------------------
snd_sample_timer_a:	; from: snd_sample_start, snd_sample_stop
	move.w	#$700,$ffff8240.w               ; palette 0
	movem.l	d0/a0-a1,-(sp)
	lea	sample_channel(pc),a0
	move.w	(a0)+,d0
	movea.l	(a0)+,a1
	cmpa.l	(a0),a1
	beq.w	sample_write_psg
	move.b	(a1),d0
	andi.b	#$f,d0
	lea	snd_sample_stop(pc),a1
	move.l	a1,$134.w                       ; MFP timer A
sample_write_psg:
	lea	$ffff8800.w,a0                  ; PSG register select
	movep.w	d0,$0(a0)
	movem.l	(sp)+,d0/a0-a1
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA
	move.w	#$777,$ffff8240.w               ; palette 0
	rte


snd_sample_stop:	; from: snd_sample_timer_a
	move.w	#$700,$ffff8240.w               ; palette 0
	movem.l	d0/a0-a1,-(sp)
	lea	snd_sample_timer_a(pc),a0
	move.l	a0,$134.w                       ; MFP timer A
	lea	sample_channel(pc),a0
	move.w	(a0)+,d0
	movea.l	(a0),a1
	move.b	(a1)+,d0
	move.l	a1,(a0)
	lsr.b	#4,d0
	lea	$ffff8800.w,a0                  ; PSG register select
	movep.w	d0,$0(a0)
	movem.l	(sp)+,d0/a0-a1
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA
	move.w	#$777,$ffff8240.w               ; palette 0
	rte


; Note periods, one word per semitone.
snd_period_table:	; from: snd_sequence_channel
	dc.w	$0ef8,$0e10,$0d60,$0c80,$0bd8,$0b28,$0a88,$09f0
	dc.w	$0960,$08e0,$0858,$07e0,$077c,$0708,$06b0,$0640
	dc.w	$05ec,$0594,$0544,$04f8,$04b0,$0470,$042c,$03f0
	dc.w	$03be,$0384,$0358,$0320,$02f6,$02ca,$02a2,$027c
	dc.w	$0258,$0238,$0216,$01f8,$01df,$01c2,$01ac,$0190
	dc.w	$017b,$0165,$0151,$013e,$012c,$011c,$010b,$00fc
	dc.w	$00ef,$00e1,$00d6,$00c8,$00bd,$00b2,$00a8,$009f
	dc.w	$0096,$008e,$0085,$007e,$0077,$0070,$006b,$0064
	dc.w	$005e,$0059,$0054,$004f,$004b,$0047,$0042,$003f
	dc.w	$003b,$0038,$0035,$0032,$002f,$002c,$002a,$0027
	dc.w	$0025,$0023,$0021,$001f,$001d,$001c,$001a,$0019
	dc.w	$0017,$0016,$0015,$0013,$0012,$0011,$0010
arpeggio_shapes:	; from: snd_sequence_channel
	dc.w	$000f,$002e,$002f,$0031,$0034,$0047,$004a,$004e
	dc.w	$0054,$0057,$005a,$005d,$0060,$0063,$0066,$0069
	dc.w	$007c,$007f,$0082,$0085,$0088,$008b,$008d,$008f
	dc.w	$0101,$0002,$0200,$0c02,$0300,$0307,$0113,$000c
	dc.w	$010b,$020a,$0309,$0408,$0507,$0605,$0403,$0201
	dc.w	$0003,$0300,$0307,$0204,$000c,$0307,$0106,$0003
	dc.w	$0507,$0c03,$0803,$0003,$0708,$0300,$0407,$0203
	dc.w	$0005,$0902,$0300,$0407,$0203,$0005,$0802,$0300
	dc.w	$0308,$0203,$0004,$0901,$1300,$1802,$0b02,$0a03
	dc.w	$0904,$0805,$0706,$0504,$0302,$0100,$0203,$0005
	dc.w	$0702,$0300,$0307,$0203,$0001,$0702,$0300,$0509
	dc.w	$0103,$0018,$0c01,$0200,$0102,$0200,$0c03,$0300
vibrato_shapes:	; from: snd_sequence_channel
	dc.w	$0c02,$000a,$001c,$002e,$0040,$0052,$000f,$0000
	dc.w	$0002,$ffff,$0004,$0001,$0002,$ffff,$ffff,$fff2
	dc.w	$0005,$0000,$0002,$ffe7,$0002,$0032,$0002,$ffe7
	dc.w	$ffff,$fff2,$000c,$0000,$0003,$ffff,$0003,$0002
	dc.w	$0003,$ffff,$ffff,$ffee,$0001,$0000,$0005,$fffb
	dc.w	$000a,$0005,$0005,$fffb,$ffff,$fff2,$0001,$fffb
	dc.w	$0001,$000a,$0001,$fffb,$ffff,$fff2
volume_envelopes:	; from: snd_sequence_channel
	dc.w	$0030,$0041,$0052,$0067,$0076,$0089,$009e,$00a9
	dc.w	$00bc,$00f9,$0104,$0111,$0112,$0133,$0134,$0141
	dc.w	$0160,$0175,$0192,$01a7,$01b6,$01ca,$01d5,$01ec
	dc.w	$010c,$010a,$0109,$0108,$0106,$0104,$0102,$0101
	dc.w	$0100,$0001,$0d01,$0c01,$0b01,$0a01,$0901,$0801
	dc.w	$0701,$0601,$0500,$010e,$010d,$010c,$010b,$010a
	dc.w	$0109,$0108,$0207,$0206,$0205,$0204,$0002,$0f02
	dc.w	$0d02,$0c02,$0a02,$0602,$0402,$0202,$0000,$010e
	dc.w	$010c,$030a,$0208,$0206,$0204,$0202,$0201,$0101
	dc.w	$0100,$0001,$0a01,$0a01,$0801,$0601,$0601,$0401
	dc.w	$0401,$0201,$0201,$0001,$0000,$010d,$080c,$080b
	dc.w	$080a,$0408,$0406,$0001,$0f01,$0e01,$0d01,$0a01
	dc.w	$0901,$0701,$0501,$0301,$0101,$0000,$0501,$0502
	dc.w	$0503,$0504,$0505,$0506,$0507,$0508,$0509,$050a
	dc.w	$050b,$050c,$050d,$050e,$050f,$050e,$050d,$050c
	dc.w	$050b,$050a,$0509,$0508,$0507,$0507,$0506,$0505
	dc.w	$0504,$0503,$0502,$0501,$0500,$0001,$0f01,$0a01
	dc.w	$0501,$0301,$0201,$0000,$020c,$020a,$0208,$0206
	dc.w	$0204,$0202,$0200,$0001,$0000,$0308,$0309,$030a
	dc.w	$030b,$030c,$010d,$010e,$010f,$010e,$010d,$010a
	dc.w	$0109,$0107,$0105,$0103,$0101,$0100,$0001,$0a00
	dc.w	$0103,$0105,$0107,$010c,$010f,$010e,$0100,$0008
	dc.w	$0404,$0b02,$0c02,$0d01,$0e01,$0f03,$0e08,$0d08
	dc.w	$0a08,$0908,$0708,$0509,$0309,$0209,$0101,$0000
	dc.w	$030f,$030e,$030d,$020a,$0209,$0507,$0705,$0703
	dc.w	$0702,$0701,$0700,$0001,$0e01,$0d01,$0c01,$0b01
	dc.w	$0a03,$0903,$0802,$0702,$0602,$0502,$0401,$0301
	dc.w	$0201,$0101,$0000,$010a,$0109,$0308,$0307,$0306
	dc.w	$0305,$0304,$0103,$0202,$0201,$0100,$0001,$0702
	dc.w	$0603,$0503,$0401,$0302,$0202,$0101,$0000,$010f
	dc.w	$010e,$070d,$070a,$0709,$0707,$0705,$0703,$0702
	dc.w	$0701,$0000,$040f,$010e,$010a,$0109,$0106,$0100
	dc.w	$0004,$0f03,$0e02,$0d02,$0c02,$0b02,$0a01,$0901
	dc.w	$0802,$0702,$0602,$0502,$0400,$070f,$010e,$010d
	dc.w	$070a,$0709,$0108,$0107,$0106,$0105,$0104,$0103
	dc.w	$0102,$0102,$0100
release_envelopes:	; from: snd_sequence_channel
	dc.w	$0000,$0004,$0014,$1404,$0804,$0702,$0602,$0502
	dc.w	$0402,$0302,$0202,$0100,$12ff,$ef00
drum_patterns:	; from: snd_sequence_channel
	dc.w	$0006,$001e,$0042,$3f0d,$0200,$070c,$0300,$070b
	dc.w	$0400,$0707,$0500,$3805,$0000,$3802,$0000,$0000
	dc.w	$3f0f,$0200,$070d,$0230,$070c,$0380,$380a,$0001
	dc.w	$3809,$0001,$3809,$0001,$3807,$0001,$3806,$0001
	dc.w	$3806,$0001,$0000,$3f0e,$0801,$070d,$0040,$070b
	dc.w	$0080,$070a,$0040,$0000
snd_tune_table:	; from: play_tune_body
	dc.w	$0120,$0146,$0154,$0000,$03b0,$03d9,$0422,$0000
	dc.w	$0799,$07bc,$07df,$0000,$0a28,$0a44,$0a8b,$0000
	dc.w	$0ce3,$0cf0,$0d00,$0000,$0e78,$0e84,$0e90,$0000
	dc.w	$1155,$1155,$1155,$0000,$1180,$1180,$1180,$0000
	dc.w	$11dd,$11dd,$11dd,$0000,$126c,$126c,$126c,$0000
pattern_data:	; from: play_tune_body, cmd_next_pattern
	incbin	"data/sn_tunes.bin"		; $128e bytes of data
sfx_vibrato_shapes:	; from: cmd_sfx_vibrato
	dc.w	$0018,$001a,$001c,$001e,$0020,$0022,$0024,$002a
	dc.w	$002c,$002e,$0030,$0032,$007f,$0080,$007f,$00ff
	dc.w	$007f,$0022,$007f,$0002,$007f,$fff2,$007f,$ffec
	dc.w	$0001,$0011,$ffff,$fffa,$007f,$0234,$007f,$00b8
	dc.w	$007f,$ffff,$007f,$0002,$007f,$0001
snd_sfx_table:	; from: play_sfx_body, unused_sfx_take_channels
	dc.w	$00a0,$0000,$0000,$0000,$009f,$0000,$0000,$0000
	dc.w	$0000,$009c,$0000,$0000,$0000,$009d,$0000,$0000
	dc.w	$009e,$00a8,$0000,$0000,$0000,$0000,$00a5,$0000
	dc.w	$00a8,$0000,$0000,$0000,$0000,$0000,$00a4,$0000
	dc.w	$00a5,$0000,$0000,$0000,$0000,$0000,$009f,$0000
	dc.w	$00a3,$00b3,$00bd,$0000,$00a5,$00c3,$00c9,$0000
	dc.w	$00cd,$00d2,$0000,$0000,$00d3,$00d9,$0000,$0000
	dc.w	$00db,$00e6,$0000,$0000,$00ed,$00f5,$0000,$0000
	dc.w	$00f9,$00fe,$0000,$0000,$0101,$0000,$0000,$0000
	dc.w	$0100,$0000,$0000,$0000,$00ff,$0105,$0000,$0000
	dc.w	$84ec,$a0c0,$5f1e,$80e3,$c0a0,$840c,$1080,$8c01
	dc.w	$83f0,$8c03,$3423,$8083,$e18c,$003c,$0f80,$f083
	dc.w	$8c02,$1304,$8c0a,$8400,$5080,$f783,$8c0b,$0805
	dc.w	$8083,$e08c,$053b,$0880,$84ef,$a71f,$020c,$4180
	dc.w	$84ed,$5317,$8084,$a7ee,$2114,$8084,$ee8c,$0254
	dc.w	$0581,$fd83,$f1a2,$8804,$3735,$3037,$8083,$e2c2
	dc.w	$180c,$1318,$8083,$f2a2,$8718,$8804,$3735,$3037
	dc.w	$8083,$f3a2,$8730,$8804,$3735,$3037,$8083,$e2c2
	dc.w	$240c,$1f18,$8083,$e2c2,$290c,$1818,$8083,$f48c
	dc.w	$0659,$0880,$83f4,$8c06,$5808,$8083,$f68a,$0c02
	dc.w	$5117,$8083,$f68a,$0c02,$5217,$8084,$f68c,$0711
	dc.w	$0183,$4a05,$8400,$0180,$84f6,$8c07,$1101,$8348
	dc.w	$0584,$0001,$8084,$f58c,$0800,$0183,$1a09,$8084
	dc.w	$f58c,$0800,$0183,$1b09,$8084,$ee8c,$0956,$0f80
	dc.w	$84ee,$8c09,$8703,$560f,$8084,$f58c,$0900,$0f80
	dc.w	$84f0,$a0c0,$0028,$8083,$e2a0,$8c08,$300a,$8083
	dc.w	$e2a0,$8c08,$320a
	dc.b	$80
snd_sample_data:	; from: snd_sample_start
	dc.b	$00

	ds.b	$400		; BSS

	end
