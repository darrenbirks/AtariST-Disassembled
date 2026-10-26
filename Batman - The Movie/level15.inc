; Batman The Movie (Ocean, 1989) - level 1 and level 5 code, all versions
;
; The platform level engine with the data of both levels that use it.  level1.s and
; level5.s assemble it: each sets BUILD_LEVEL and includes this file, and their headers
; describe the level's map.
;
; Entry at $2200 (level_start): converts the level graphics (GFX_B_BLOCKS,
; GFX_A_BLOCKS) to screen planes, builds the sprite tables, installs the interrupt
; handlers and starts the level at level_begin.  main_loop runs once per frame:
; joystick, player state, scrolling, enemies, bullets, redraw, flip.
;
; The player is a state machine: the jsr at call_player_state is self modifying,
; player_state_lo (the low word of its operand) is written with the address of the
; current state routine (state_* labels).  player_input dispatches the idle state on
; the joystick bits of joy_state (0 right, 1 left, 2 down, 3 up, 4 fire) through
; player_input_table.  Enemies are 10 records of $16 bytes in enemies, updated through
; enemy_type_table (indexed by type).  A map tile is 16 x 16 pixels, and positions are
; in units of 2 pixels.
;
; The parts only one level has are in blocks:
;   "ifeq BUILD_LEVEL-1" ... "endc"               only level 1
;   "ifeq BUILD_LEVEL-5" ... "endc"               only level 5
;   "ifeq BUILD_LEVEL-1" ... "else" ... "endc"    level 1's lines, then level 5's
; and the parts not every version has are in config blocks, as in the other sources.
;
; Labels are named for what they do or hold; unused_ marks code that nothing
; calls.  A label still ending in its address (tab_ table, dat_ data) is one
; whose use is not known yet.  "; from:" lists the routines or modules that
; refer to a label (documentation only).  A routine only one level runs says so
; in its header.

; constants
	include	"config.s"			; CONFIG: which version to assemble

	ifeq	BUILD_LEVEL-1
MAP_ROW_LENGTH	equ	$cc             ; tiles a map row
MAP_ROWS	equ	42              ; map rows
TILE_OPEN	equ	$28             ; tile numbers below this are walls
TILE_FLOOR	equ	$e2             ; from here: floor to stand on
TILE_LADDER	equ	$fa             ; from here: ladders
FLOOR_WALK_END	equ	$fc             ; floor ends here for walking (ladders $fa-$fb count)
FLOOR_LAND_END	equ	$fb             ; and here for landing from a fall
LEVEL_TIME	equ	$900            ; the time limit, minutes and seconds in BCD (9:00)
TILE_CACHE_SLOTS	equ	96      ; tiles the tile cache holds, $400 bytes each
SPAWN_OFFSET_X	equ	$50             ; added to an object's x when it appears, and taken off scroll_x for the trigger test
	else
MAP_ROW_LENGTH	equ	$5c             ; tiles a map row
MAP_ROWS	equ	204             ; map rows
TILE_OPEN	equ	$18             ; tile numbers below this are walls
TILE_DEADLY	equ	$ca             ; from here: deadly floor
TILE_FLOOR	equ	$cd             ; from here: floor to stand on
TILE_LADDER	equ	$f8             ; from here: ladders
FLOOR_WALK_END	equ	$fb             ; floor ends here (ladders $f8-$fa count)
LEVEL_TIME	equ	$1200           ; the time limit, minutes and seconds in BCD (12:00)
TILE_CACHE_SLOTS	equ	72      ; tiles the tile cache holds, $400 bytes each
SPAWN_OFFSET_X	equ	$8              ; added to an object's x when it appears, and taken off scroll_x for the trigger test
	endc
VAT_DEPTH	equ	$d4             ; Jack's y when his fall reaches the vat (vat_watch, never run on level 5)
VAT_SPLASH_X	equ	$5e0            ; where Jack's splash in the vat is drawn (vat_splash, never run on level 5)
	ifeq	BUILD_LEVEL-1
ENDING_SCROLL_X	equ	$0              ; level_complete pans the view after a falling boss until scroll_x gets here (never run on level 1)
	else
ENDING_SCROLL_X	equ	$240            ; level_complete pans the view after the falling Joker until scroll_x gets here
	endc
CLIMB_COLUMN_ROWS	equ	10      ; map rows of the column boss_climb_watch swings, from map_climb_column down: the rope ladder (never run on level 1)
MAP_START	equ	$7400           ; level1.map or level5.map loads here: tile count, row length and rows, then the map
	ifeq	BUILD_LEVEL-1
map_tile_count	equ	MAP_START       ; the tile count, the row length and the rows
map_tiles	equ	MAP_START+6     ; the map: a tile number per cell, MAP_ROW_LENGTH a row
	endc
TILE_TABLE	equ	MAP_START+6+MAP_ROW_LENGTH*MAP_ROWS ; the tile table: a word per tile, its own block and the one to its right
TILE_REFS	equ	TILE_TABLE+$200 ; the tile cache: a reference count per tile (work space in the map file)
TILE_SLOTS	equ	TILE_REFS+$100  ; the tile cache: the slot of each tile
	ifeq	BUILD_LEVEL-1
MAP_BLOCK_COUNT	equ	82              ; the 16 x 16 graphics blocks in level1.map, $80 bytes each
	else
MAP_BLOCK_COUNT	equ	100             ; the 16 x 16 graphics blocks in level5.map, $80 bytes each
	endc
TILE_CACHE	equ	TILE_REFS+$200+MAP_BLOCK_COUNT*$80 ; the tile cache: TILE_CACHE_SLOTS tiles of $400 bytes, after the map file
GFX_A	equ	$50000                  ; level1a.gfx or level5a.gfx loads here: its sprite set count at +2
	ifeq	BUILD_LEVEL-1
GFX_A_BLOCKS	equ	GFX_A+$1f4      ; level1a.gfx's block graphics, converted at level start
	else
GFX_A_BLOCKS	equ	GFX_A+$1e4      ; level5a.gfx's block graphics, converted at level start
	endc
GFX_A_BLOCK_COUNT	equ	$1961   ; and how many
GFX_B	equ	$60000                  ; level1b.gfx or level5b.gfx loads here: its sprite set count at +2
	ifeq	BUILD_LEVEL-1
GFX_B_BLOCKS	equ	GFX_B+$19c      ; level1b.gfx's block graphics, converted at level start
GFX_B_BLOCK_COUNT	equ	$741    ; and how many
SPRITE_HEADERS	equ	$2427e          ; the sprite headers, 8 bytes each (x/y offset, width code, height, data)
	else
GFX_B_BLOCKS	equ	GFX_B+$1b4      ; level5b.gfx's block graphics, converted at level start
GFX_B_BLOCK_COUNT	equ	$801    ; and how many
SPRITE_HEADERS	equ	$21356          ; the sprite headers, 8 bytes each (x/y offset, width code, height, data)
	endc
SPRITE_PACKED	equ	SPRITE_HEADERS+$1200 ; where pack_sprites packs the sprite data
	ifeq	BUILD_LEVEL-1
SPRITE_DATA	equ	$23382          ; draw_sprite adds a header's data offset to this
SPRITE_SHIFTED	equ	$48800          ; the shifted copies of the sprites
	else
SPRITE_DATA	equ	$23eaa          ; draw_sprite adds a header's data offset to this
SPRITE_SHIFTED	equ	$46400          ; the shifted copies of the sprites
	endc
SCREEN_FRONT	equ	$70000          ; the screens (they swap every frame); the front one is scratch while the level starts
SCREEN_BACK	equ	$78000          ; and the other
STACK_TOP	equ	$6d3e8          ; the stack, below the sound driver at $6d400
	ifeq	BUILD_LEVEL-1
map_climb_column	equ	map_tiles+$3a ; the column boss_climb_watch swings (never run on level 1)
	endc
SCROLL_Y_LIMIT	equ	MAP_ROWS*8-$60  ; the view scrolls down no further than scroll_y = this + 8: the map less the view
	ifeq	BUILD_LEVEL-1
SPRITE_HEADER_COUNT	equ	62      ; sprite headers in a set; draw_sprite keeps 8 shifted copies of them
SPRITE_COUNT	equ	$223            ; the sprites shift_sprite_loop shifts
JACK_SPRITE	equ	$803d           ; Jack Napier's sprite base
SPLASH_SPRITE	equ	$30             ; the sprite base of Jack's splash in the vat
CLIMB_SPRITE	equ	$0              ; the climbing boss's sprite base (0: level 1 has no climb)
LANDED_SPRITE	equ	51              ; the sprite of the boss landed at the end (complete_boss_landed)
BULLET_SPRITE	equ	$34             ; the bullet sprites start here
LEVEL_TUNE	equ	1               ; the level's music (play_tune)
	else
SPRITE_HEADER_COUNT	equ	60      ; sprite headers in a set; draw_sprite keeps 8 shifted copies of them
SPRITE_COUNT	equ	$216            ; the sprites shift_sprite_loop shifts
JACK_SPRITE	equ	$0              ; Jack Napier's sprite base (0: level 5 has no Jack)
SPLASH_SPRITE	equ	$0              ; the sprite base of Jack's splash in the vat (0: level 5 has no vat)
CLIMB_SPRITE	equ	$6a             ; the climbing boss's sprite base
LANDED_SPRITE	equ	54              ; the sprite of the boss landed at the end (complete_boss_landed)
BULLET_SPRITE	equ	$37             ; the bullet sprites start here
LEVEL_TUNE	equ	2               ; the level's music (play_tune)
	endc
LOADER_FRONT_END	equ	$200    ; the loader's jmp table at $200 (a jmp a long): entry 0, the front end
	ifeq	BUILD_LEVEL-1
NEXT_SCENE	equ	$208            ; where the level goes when it is done: level 2
	else
NEXT_SCENE	equ	LOADER_FRONT_END ; where the level goes when it is done: the front end
	endc

; symbols in other modules
panel_tick	equ	$6b800		; panel.s
panel_set_time	equ	$6b80e		; panel.s
panel_add_score	equ	$6b82a		; panel.s
	ifeq	BUILD_LEVEL-1
panel_reset_lives	equ	$6b838		; panel.s
	endc
panel_add_life	equ	$6b846		; panel.s
panel_init_energy	equ	$6b854		; panel.s
panel_lose_life	equ	$6b862		; panel.s
panel_lose_energy	equ	$6b870		; panel.s
panel_flags	equ	$6b874		; panel.s
game_flags	equ	$6b875		; panel.s
panel_copy	equ	$6c874		; panel.s
snd_reset	equ	$6d400		; sound.s
snd_stop	equ	$6d404		; sound.s
snd_stop_music	equ	$6d408		; sound.s
snd_play_tune	equ	$6d410		; sound.s
snd_play_sfx	equ	$6d414		; sound.s
snd_tick	equ	$6d418		; sound.s

; addresses inside instructions (self modifying code)
	ifeq	BUILD_LEVEL-1
	ifeq	CONFIG-RETAIL_2DISK
player_state_vec	equ	$2b3c		; call_player_state+2
player_state_lo	equ	$2b3e		; call_player_state+4
	endc
	ifne	CONFIG-RETAIL_2DISK
player_state_vec	equ	$2b58		; call_player_state+2
player_state_lo	equ	$2b5a		; call_player_state+4
	endc
	else
	ifeq	CONFIG-RETAIL_2DISK
player_state_vec	equ	$2b36		; call_player_state+2
player_state_lo	equ	$2b38		; call_player_state+4
	endc
	ifne	CONFIG-RETAIL_2DISK
player_state_vec	equ	$2b52		; call_player_state+2
player_state_lo	equ	$2b54		; call_player_state+4
	endc
	endc

	opt	o-
	org	$2200

	ifne	CONFIG-RETAIL_2DISK

;----------------------------------------------------------------------
; Level entry: stack at STACK_TOP, convert graphics, build sprite tables, install handlers.
;----------------------------------------------------------------------
level_start:
	lea	GFX_B_BLOCKS,a0
	move.w	#GFX_B_BLOCK_COUNT-1,d7
	bsr.w	convert_level_gfx
	lea	GFX_A_BLOCKS,a0
	move.w	#GFX_A_BLOCK_COUNT-1,d7
	bsr.w	convert_level_gfx
	bsr.w	build_sprite_tables
	endc
	moveq	#0,d0
	move.w	#$2700,sr
	move.b	d0,$fffa07                      ; MFP IERA
	move.b	d0,$fffa09                      ; MFP IERB
	move.b	#$2,$ff820a                     ; sync mode
	lea	$ff8240,a0                      ; palette 0
	moveq	#15,d1
clear_palette_loop:
	move.w	d0,(a0)+
	dbra	d1,clear_palette_loop
	ifeq	BUILD_LEVEL-1
	lea	STACK_TOP,sp
	else
	ifeq	CONFIG-RETAIL_2DISK
	lea	STACK_TOP-8,sp
	endc
	ifne	CONFIG-RETAIL_2DISK
	lea	STACK_TOP,sp
	endc
	endc
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
	bra.w	level_begin

mfp_vectors:	; from: level_start
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
ikbd_init_cmds:	; from: level_start
	dc.w	$8010,$121a
palette_split:	; from: vbl_handler
	dc.w	$0000,$0223,$0445,$0667,$0024,$0146,$0632,$0511
	dc.w	$0353,$0652,$0763,$0744,$0300,$0131,$0334,$0357
	dc.w	$0098
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
; Timer C (200 Hz): panel tick (when not paused), lose a life when the time is up, sound tick, keyboard.
;----------------------------------------------------------------------
timerc_handler:	; from: mfp_vectors
	bclr	#$5,$fffa11                     ; MFP ISRB
	move.w	#$2300,sr
	movem.l	d0-d7/a0-a6,-(sp)
	tst.b	panel_flags
	bne.s	timerc_sound
	jsr	panel_tick
	btst	#$0,panel_flags
	beq.s	timerc_sound
	jsr	panel_lose_life
	moveq	#1,d6
	bsr.w	player_knockback
timerc_sound:
	jsr	snd_tick
	bsr.w	keyboard_handler
	movem.l	(sp)+,d0-d7/a0-a6
	rte

acia_abort:	; from: midi_flush
	movem.l	(sp)+,d0-d1/a0
	rte


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

kbd_ring:	; from: keyboard_acia_read, keyboard_handler
	dcb.b	32,$00
kbd_head:	; from: keyboard_acia_read, keyboard_handler
	dc.w	$0000
kbd_tail:	; from: keyboard_handler
	dc.w	$0000

mfp_fdc:	; from: mfp_vectors
	bclr	#$7,$fffa11                     ; MFP ISRB
	rte


;----------------------------------------------------------------------
; Timer B: palette split from split_ptr (full palette, next line count).
;----------------------------------------------------------------------
timerb_handler:	; from: mfp_vectors
	movem.l	d0-d3/a0,-(sp)
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
; VBL: set palette_split, restart timer B, count frames in flip_request.
;----------------------------------------------------------------------
vbl_handler:	; from: level_start
	movem.l	d0-d7/a0-a6,-(sp)
	move.b	#$0,$fffa1b                     ; MFP TBCR
	lea	palette_split(pc),a0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8240                   ; palette 0
	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,$ff8250
	move.w	(a0)+,d0
	move.l	a0,split_ptr
	move.b	d0,$fffa21                      ; MFP TBDR
	move.b	#$8,$fffa1b                     ; MFP TBCR
	addq.w	#1,flip_request.w
	movem.l	(sp)+,d0-d7/a0-a6
	rte

	dc.w	$0000

ikbd_send:	; from: level_start, ikbd_joystick_mode
	btst	#$1,$fffc00                     ; keyboard ACIA control
	beq.s	ikbd_send
	move.b	(a0)+,$fffc02                   ; keyboard ACIA data
	dbra	d0,ikbd_send
	rts


;----------------------------------------------------------------------
; Decode IKBD packets: keys to key_queue / key_bitmap, joystick to joy0 / joy_fire+joy_dirs, mouse.
;----------------------------------------------------------------------
keyboard_handler:	; from: timerc_handler
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

scancode_ascii:	; from: keyboard_handler
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
packet_lengths:	; from: keyboard_handler
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
	move.b	$0(a0,d1.w),joy_dirs
	bclr	#$7,joy_dirs
	sne	joy_fire
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
	move.b	$0(a0,d1.w),joy_dirs
	bclr	#$7,joy_dirs
	sne	joy_fire
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

key_queue:	; from: keyboard_handler, get_key
	dcb.b	32,$00
key_queue_head:	; from: keyboard_handler, get_key
	dc.w	$0000
key_queue_tail:	; from: get_key
	dc.w	$0000
key_bitmap:	; from: keyboard_handler
	dcb.b	34,$00
joy0_fire:	; from: keyboard_handler
	dc.b	$00
joy0_dirs:	; from: keyboard_handler
	dc.b	$00,$00,$00
joy_fire:	; from: keyboard_handler, read_joystick
	dc.b	$00
joy_dirs:	; from: keyboard_handler, read_joystick
	dc.b	$00,$00,$00,$00,$00
mouse_max_x:	; from: keyboard_handler
	dc.w	$0000
mouse_max_y:	; from: keyboard_handler
	dc.w	$0000
mouse_left:	; from: keyboard_handler
	dc.b	$00
mouse_right:	; from: keyboard_handler
	dc.b	$00
mouse_x:	; from: keyboard_handler
	dc.w	$0000
mouse_y:	; from: keyboard_handler
	dc.w	$0000,$0000,$0000,$0000
unused_flush_keys:
	move.l	d0,-(sp)
	bsr.s	get_key
flush_keys_loop:
	bne.s	flush_keys_loop
	move.l	(sp)+,d0
	rts


get_key:	; from: keyboard_handler, main_loop
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


ikbd_joystick_mode:	; from: level_begin
	movem.l	d0/a0,-(sp)
	lea	ikbd_joy_cmds(pc),a0
	moveq	#1,d0
	bsr.w	ikbd_send
	movem.l	(sp)+,d0/a0
	rts

ikbd_joy_cmds:	; from: ikbd_joystick_mode
	dc.w	$1214
flip_request:	; from: vbl_handler, wait_vbl_flip, level_begin, main_loop, wait_frames, fade_in, ...
	dc.w	$0000
frame_count:	; from: wait_vbl_flip
	dc.w	$0000
screen_front:	; from: wait_vbl_flip, dissolve_in
	dc.w	$0007,$0000
screen_back:	; from: draw_sprite, redraw_tiles, clear_back_screen, draw_player, clear_and_dissolve, print_text
	dc.w	$0007,$8000

;----------------------------------------------------------------------
; Wait for the frame count, swap screen_front / screen_back and set the video base; counts frame_toggle.
;----------------------------------------------------------------------
wait_vbl_flip:	; from: level_begin, main_loop, tile_cache_free, vat_splash, level_complete
	move.w	frame_count.w,d1
flip_wait_loop:
	move.w	flip_request.w,d0
	cmp.w	d0,d1
	bpl.s	flip_wait_loop
	addi.w	#$1,d0
	btst	#$1,$ff820a                     ; sync mode
	bne.s	flip_set_frame
	addq.w	#1,d0
flip_set_frame:
	move.w	d0,frame_count.w
	movem.l	screen_front,d0-d1
	exg	d0,d1
	movem.l	d0-d1,screen_front
	ror.l	#8,d0
	move.b	d0,$ff8203                      ; video base mid
	ror.l	#8,d0
	move.b	d0,$ff8201                      ; video base high
	move.w	flip_request.w,d0
flip_sync_loop:
	cmp.w	flip_request.w,d0
	beq.s	flip_sync_loop
	addq.w	#1,frame_toggle.w
	rts


clear_screens:	; from: level_start, level_begin
	lea	SCREEN_FRONT,a0
	move.w	#$17bf,d0
clear_front_loop:
	move.l	#$0,(a0)+
	dbra	d0,clear_front_loop
	lea	SCREEN_BACK,a0
	move.w	#$17bf,d0
clear_back_loop:
	move.l	#$0,(a0)+
	dbra	d0,clear_back_loop
	rts

	dc.w	$0000,$3030,$3030,$00ff

;----------------------------------------------------------------------
; Start (or restart) the level: time $900, objects from the map in map_tiles,
; enemy/bullet lists cleared, player state player_input.
;----------------------------------------------------------------------
level_begin:	; from: level_start
	jsr	snd_reset
	bsr.w	ikbd_joystick_mode
	clr.l	flip_request
	bset	#$0,panel_flags
	bsr.w	wait_vbl_flip
	ifeq	CONFIG-RETAIL_2DISK
	bsr.w	build_sprite_tables
	endc
	bsr.w	build_tile_order
	clr.w	checkpoint.w
	ifeq	BUILD_LEVEL-1
	jsr	panel_reset_lives
	endc
level_restart:	; from: state_dying
	jsr	panel_copy
	clr.w	rope_length.w
	clr.l	flip_request
	bsr.w	clear_screens
	jsr	panel_init_energy
	bset	#$0,panel_flags
	bsr.w	fade_in
	move.w	#LEVEL_TIME,d0
	jsr	panel_set_time
	lea	map_tiles,a0
	movea.l	object_stack,a5
place_objects_loop:
	movem.w	(a5)+,d2-d5
	tst.w	d3
	beq.s	objects_placed
	move.b	d5,$4(a0,d3.w)
	move.b	d2,$1(a0,d3.w)
	lsr.w	#8,d2
	move.b	d2,$0(a0,d3.w)
	move.b	d4,$3(a0,d3.w)
	lsr.w	#8,d4
	move.b	d4,$2(a0,d3.w)
	bra.s	place_objects_loop

objects_placed:
	move.l	#object_stack+$60,object_stack
	lea	bullets.w,a0
	moveq	#39,d7
clear_bullets_loop:
	clr.l	(a0)+
	dbra	d7,clear_bullets_loop
	lea	spawn_table.w,a0
reset_spawn_groups:
	bclr	#$7,(a0)
	move.w	$4(a0),d0
	mulu.w	#$6,d0
	lea	$6(a0,d0.w),a0
	cmpa.w	#spawn_singles,a0
	bcs.s	reset_spawn_groups
reset_spawn_singles:
	bclr	#$7,$4(a0)
	addq.w	#6,a0
	cmpa.w	#checkpoint_starts,a0
	bcs.s	reset_spawn_singles
	lea	enemies.w,a0
	moveq	#109,d7
clear_enemies_loop:
	clr.w	(a0)+
	dbra	d7,clear_enemies_loop
	clr.w	player_frame_legs.w
	lea	anim_idle.w,a0
	bsr.w	set_player_anim
	move.w	#player_input,player_state_lo.w
	lea	checkpoint_starts.w,a0
	move.w	checkpoint.w,d6
checkpoint_loop:
	moveq	#6,d7
	lea	scroll_x.w,a1
copy_start_loop:
	move.w	(a0)+,(a1)+
	dbra	d7,copy_start_loop
	dbra	d6,checkpoint_loop
	lea	level_name_text.w,a0
	bsr.w	print_text
	bsr.w	wait_vbl_flip
	bsr.w	init_tile_cache
	bsr.w	redraw_tiles
	bsr.w	draw_player
	bsr.w	dissolve_in
	bsr.w	draw_player
	clr.l	flip_request.w
	bclr	#$0,panel_flags
	btst	#$0,game_flags
	bne.s	main_loop
	moveq	#LEVEL_TUNE,d0
	jsr	play_tune

;----------------------------------------------------------------------
; Main loop, once per frame.  F1 pause, ESC abort (jmp $200), F2 music, F10 cheat skip.
;----------------------------------------------------------------------
main_loop:	; from: level_begin
	bsr.w	get_key
	beq.s	frame_update
	cmpi.w	#$81,d0
	bne.s	key_f2
pause_loop:
	bset	#$0,panel_flags
	bsr.w	get_key
	beq.s	pause_loop
	bclr	#$0,panel_flags
	clr.l	flip_request.w
	cmpi.w	#$1b,d0
	bne.s	key_f2
	bsr.w	clear_and_dissolve
	bset	#$5,game_flags
	bra.w	leave_level

key_f2:
	cmpi.w	#$82,d0
	bne.s	key_f10
	bchg	#$0,game_flags
	bne.s	music_on
	jsr	snd_stop_music
	bra.w	frame_update

music_on:
	moveq	#LEVEL_TUNE,d0
	jsr	play_tune
	bra.s	frame_update

key_f10:
	cmpi.w	#$8a,d0
	bne.s	frame_update
	btst	#$7,game_flags
	ifeq	BUILD_LEVEL-1
	bne.w	end_sequence
	else
	bne.w	set_complete_flag
	endc
frame_update:
	clr.l	d0
	clr.l	d1
	bsr.w	read_joystick
	movem.w	player_x.w,d0-d1
	tst.w	throw_cooldown.w
	bmi.s	call_player_state
	subq.w	#1,throw_cooldown.w
call_player_state:
	jsr	player_input                    ; self modified: player_state_lo is the current state routine
	bsr.w	update_scroll
	bsr.w	score_distance
	bsr.w	spawn_enemies
	bsr.w	redraw_tiles
	bsr.w	draw_player
	bsr.w	update_enemies
	bsr.w	update_bullets
	bsr.w	draw_bullets
	bsr.w	wait_vbl_flip
	bra.w	main_loop


;----------------------------------------------------------------------
; Sprite blitter: d0/d1 position, d2 sprite number (bit 15 = flipped), through sprite_shift_table.
; Sprite headers at SPRITE_HEADERS (8 bytes: x/y offset, width code, height, data), data at SPRITE_DATA.
;----------------------------------------------------------------------
draw_sprite:	; from: draw_enemy, draw_enemy_frame, draw_bullets, draw_player, level_complete, draw_enemy_sprite
	movea.l	#SPRITE_HEADERS,a1
	clr.w	d7
	add.w	d1,d1
	asl.w	#3,d2
	lea	-$8(a1,d2.w),a1
	bcc.s	sprite_normal_header
	move.b	(a1)+,d4
	ext.w	d4
	sub.w	d4,d1
	move.b	(a1)+,d4
	ext.w	d4
	add.w	d4,d0
	moveq	#7,d4
	and.w	d0,d4
	beq.s	sprite_aligned
	eor.w	d4,d0
	neg.w	d4
	addq.w	#8,d4
	mulu.w	#SPRITE_HEADER_COUNT*8,d4
	adda.l	d4,a1
	bra.s	sprite_flipped_header

sprite_aligned:
	subq.w	#8,d0
sprite_flipped_header:
	clr.w	d2
	move.b	(a1)+,d2
	moveq	#62,d4
	and.w	d2,d4
	lsl.w	#2,d4
	cmpi.b	#$40,d2
	bcc.s	sprite_flip_width
	addq.w	#8,d0
sprite_flip_width:
	sub.w	d4,d0
	btst	#$0,d2
	beq.s	sprite_flip_bits
	bset	#$2,d4
sprite_flip_bits:
	roxl.b	#1,d2
	roxr.b	#1,d4
	roxl.b	#1,d2
	roxr.b	#1,d4
	move.w	d4,d2
	move.b	(a1)+,d7
	movea.l	(a1)+,a0
	adda.l	#SPRITE_DATA,a0
	bra.s	sprite_clip_y

sprite_normal_header:
	move.b	(a1)+,d4
	ext.w	d4
	sub.w	d4,d1
	move.b	(a1)+,d4
	ext.w	d4
	sub.w	d4,d0
	moveq	#7,d4
	and.w	d0,d4
	eor.w	d4,d0
	mulu.w	#SPRITE_HEADER_COUNT*8,d4
	adda.l	d4,a1
	clr.w	d2
	move.b	(a1)+,d2
	move.b	(a1)+,d7
	movea.l	(a1)+,a0
sprite_clip_y:
	tst.w	d1
	bpl.s	sprite_clip_bottom
	neg.w	d1
	sub.w	d1,d7
	bls.w	sprite_exit
	move.w	d2,d4
	rol.b	#2,d4
	lea	sprite_widths.w,a1
	move.b	-$4(a1,d4.w),d4
	mulu.w	d4,d1
	adda.l	d1,a0
	moveq	#0,d1
	bra.s	sprite_setup_x

sprite_clip_bottom:
	move.w	#$97,d6
	sub.w	d1,d6
	bls.w	sprite_exit
	cmp.w	d7,d6
	bpl.s	sprite_setup_x
	move.w	d6,d7
sprite_setup_x:
	move.w	d0,d3
	tst.b	d2
	bpl.s	sprite_clip_x
	addq.w	#4,d0
sprite_clip_x:
	subq.w	#1,d7
	moveq	#0,d6
	moveq	#63,d5
	and.w	d2,d5
	asr.w	#2,d0
	bpl.s	sprite_clip_right
	add.w	d0,d5
	ble.s	sprite_exit
	lea	sprite_widths.w,a1
	move.w	d2,d6
	rol.b	#2,d6
	move.b	-$4(a1,d6.w),d6
	andi.w	#$40,d2
	or.w	d5,d2
	move.w	d2,d5
	rol.b	#2,d5
	sub.b	-$4(a1,d5.w),d6
	adda.l	d6,a0
	moveq	#0,d3
sprite_clip_right:
	moveq	#36,d4
	sub.w	d0,d4
	ble.s	sprite_exit
	sub.w	d4,d5
	bls.s	sprite_screen_address
	lea	sprite_widths.w,a1
	move.w	d2,d6
	rol.b	#2,d6
	move.b	-$4(a1,d6.w),d6
	andi.w	#$80,d2
	or.w	d4,d2
	move.w	d2,d5
	rol.b	#2,d5
	sub.b	-$4(a1,d5.w),d6
sprite_screen_address:
	movea.l	screen_back.w,a2
	addq.w	#8,a2
	andi.w	#$fff8,d3
	adda.w	d3,a2
	mulu.w	#$a0,d1
	adda.l	d1,a2
	moveq	#-113,d0
	and.w	d2,d0
	rol.b	#3,d0
sprite_jump:
	movea.l	sprite_jump(pc,d0.w),a1
	jmp	(a1)

sprite_exit:
	rts

sprite_shift_table:
	dc.l	blit_even
	dc.l	blit_odd
	dc.l	blit_full_1
	dc.l	blit_odd_odd
	dc.l	blit_full_1_even
	dc.l	blit_odd_full_1
	dc.l	blit_full_2
	dc.l	blit_odd_full_1_even
	dc.l	blit_full_2_even
	dc.l	blit_odd_full_2
	dc.l	blit_full_3
	dc.l	blit_odd_full_2_even
	dc.l	blit_full_3_even
	dc.l	blit_odd_full_3
	dc.l	blit_full_4
	dc.l	blit_odd_full_3_even

blit_odd_odd:	; from: sprite_shift_table
	movep.l	$1(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$1(a2)
	movep.l	$8(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$8(a2)
	lea	$a0(a2),a2
	dbra	d7,blit_odd_odd
	rts


blit_odd:	; from: sprite_shift_table
	movep.l	$1(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$1(a2)
	lea	$a0(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_odd
	rts


blit_even:	; from: sprite_shift_table
	movep.l	$0(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$0(a2)
	lea	$a0(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_even
	rts


blit_full_1:	; from: sprite_shift_table
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	lea	$98(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_full_1
	rts


blit_full_1_even:	; from: sprite_shift_table
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movep.l	$0(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$0(a2)
	lea	$98(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_full_1_even
	rts


blit_odd_full_1:	; from: sprite_shift_table
	addq.w	#8,a2
blit_odd_full_1_loop:
	movep.l	-$7(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,-$7(a2)
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	lea	$98(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_odd_full_1_loop
	rts


blit_full_2:	; from: sprite_shift_table
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	lea	$90(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_full_2
	rts


blit_odd_full_1_even:	; from: sprite_shift_table
	addq.w	#8,a2
blit_odd_full_1_even_loop:
	movep.l	-$7(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,-$7(a2)
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movep.l	$0(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$0(a2)
	lea	$98(a2),a2
	dbra	d7,blit_odd_full_1_even_loop
	rts


blit_odd_full_2:	; from: sprite_shift_table
	addq.w	#8,a2
blit_odd_full_2_loop:
	movep.l	-$7(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,-$7(a2)
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	lea	$90(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_odd_full_2_loop
	rts


blit_full_2_even:	; from: sprite_shift_table
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movep.l	$0(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$0(a2)
	lea	$90(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_full_2_even
	rts


blit_odd_full_2_even:	; from: sprite_shift_table
	addq.w	#8,a2
blit_odd_full_2_even_loop:
	movep.l	-$7(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,-$7(a2)
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movep.l	$0(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$0(a2)
	lea	$90(a2),a2
	dbra	d7,blit_odd_full_2_even_loop
	rts


blit_full_3:	; from: sprite_shift_table
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	lea	$88(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_full_3
	rts


blit_odd_full_3:	; from: sprite_shift_table
	addq.w	#8,a2
blit_odd_full_3_loop:
	movep.l	-$7(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,-$7(a2)
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	lea	$88(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_odd_full_3_loop
	rts


blit_full_3_even:	; from: sprite_shift_table
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movep.l	$0(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$0(a2)
	lea	$88(a2),a2
	adda.l	d6,a0
	dbra	d7,blit_full_3_even
	rts


blit_odd_full_3_even:	; from: sprite_shift_table
	addq.w	#8,a2
blit_odd_full_3_even_loop:
	movep.l	-$7(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,-$7(a2)
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movep.l	$0(a2),d0
	move.w	(a0),d1
	swap	d1
	move.w	(a0)+,d1
	and.l	d1,d0
	or.l	(a0)+,d0
	movep.l	d0,$0(a2)
	lea	$88(a2),a2
	dbra	d7,blit_odd_full_3_even_loop
	rts


blit_full_4:	; from: sprite_shift_table
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	movem.l	(a2),d0-d1
	move.w	(a0),d2
	swap	d2
	move.w	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	d0,(a2)+
	move.l	d1,(a2)+
	ifeq	CONFIG-RETAIL_2DISK
	lea	$88(a2),a2                      ; bug: 64 pixel wide sprites shear 16 pixels right per line (136, not 128)
	endc
	ifne	CONFIG-RETAIL_2DISK
	lea	$80(a2),a2
	endc
	adda.l	d6,a0
	dbra	d7,blit_full_4
	rts

sprite_widths:	; from: draw_sprite, build_sprite_tables
	dc.w	$0606,$0606,$0a0c,$0c0c,$1010,$1010,$1416,$1616
	dc.w	$1a1a,$1a1a
	dc.b	$1e
	dc.b	'   $$$$(***'

;----------------------------------------------------------------------
; Read the joystick into joy_state (bits 0 right, 1 left, 2 down, 3 up, 4 fire).
;----------------------------------------------------------------------
read_joystick:	; from: main_loop
	clr.w	d0
	move.b	joy_dirs.w,d0
	move.b	joy_dir_table(pc,d0.w),d1
	tst.b	joy_fire.w
	sne	d0
	tst.b	fire_latch.w
	bne.s	joy_store
	andi.w	#$10,d0
	or.w	d0,d1
joy_store:
	move.b	d0,fire_latch.w
	move.b	d1,joy_state.w
	rts

joy_dir_table:	; from: read_joystick
	dc.w	$0008,$040c,$020a,$060e,$0109,$050d,$030b,$070f

;----------------------------------------------------------------------
; Draw the whole 20 x 10 tile window of the map to the back screen from the tile cache.
;----------------------------------------------------------------------
redraw_tiles:	; from: level_begin, main_loop, tile_cache_free
	movea.l	screen_back.w,a0
	addq.w	#8,a0
	movem.w	scroll_x.w,d0-d1
	moveq	#7,d2
	and.w	d0,d2
	lsl.w	#7,d2
	addi.l	#TILE_CACHE,d2
	movea.l	d2,a4
	lsr.w	#3,d1
	lsr.w	#3,d0
	mulu.w	#MAP_ROW_LENGTH,d1
	addq.w	#1,d1
	add.w	d0,d1
	addi.l	#map_tiles,d1
	movea.l	d1,a6
	move.w	#$a0,d4
	lea	TILE_SLOTS,a5
	moveq	#7,d0
	and.w	scroll_y.w,d0
	beq.s	tiles_aligned
	moveq	#8,d1
	sub.w	d0,d1
	lsl.w	#4,d0
	move.b	d0,partial_row_loop-3.w
	bsr.w	draw_partial_row
	subi.w	#$88,d4
	adda.w	d4,a0
	lea	MAP_ROW_LENGTH-18(a6),a6
tiles_aligned:
	moveq	#7,d7
	moveq	#7,d0
	and.w	scroll_y.w,d0
	subq.w	#1,d0
	cmpi.w	#$3,d0
	bcs.s	tiles_row
	addq.w	#1,d7
tiles_row:
	moveq	#17,d6
tiles_col_loop:
	moveq	#0,d0
	move.b	(a6)+,d0
	move.b	$0(a5,d0.w),d0
	swap	d0
	lsr.l	#6,d0
	lea	$0(a4,d0.l),a1
	movem.l	(a1)+,d0-d5/a2-a3
	movem.l	d0-d1,(a0)
	movem.l	d2-d3,$a0(a0)
	movem.l	d4-d5,$140(a0)
	movem.l	a2-a3,$1e0(a0)
	movem.l	(a1)+,d0-d5/a2-a3
	movem.l	d0-d1,$280(a0)
	movem.l	d2-d3,$320(a0)
	movem.l	d4-d5,$3c0(a0)
	movem.l	a2-a3,$460(a0)
	movem.l	(a1)+,d0-d5/a2-a3
	movem.l	d0-d1,$500(a0)
	movem.l	d2-d3,$5a0(a0)
	movem.l	d4-d5,$640(a0)
	movem.l	a2-a3,$6e0(a0)
	movem.l	(a1)+,d0-d5/a2-a3
	movem.l	d0-d1,$780(a0)
	movem.l	d2-d3,$820(a0)
	movem.l	d4-d5,$8c0(a0)
	movem.l	a2-a3,$960(a0)
	addq.w	#8,a0
	dbra	d6,tiles_col_loop
	lea	$970(a0),a0
	lea	MAP_ROW_LENGTH-18(a6),a6
	dbra	d7,tiles_row
	clr.b	partial_row_loop-3.w
	moveq	#7,d1
	and.w	scroll_y.w,d1
	eori.w	#$4,d1
	beq.s	tiles_exit
	bsr.w	draw_partial_row
tiles_exit:
	rts


draw_partial_row:	; from: redraw_tiles
	move.w	d1,d5
	subq.w	#1,d5
	move.w	#$140,d4
	mulu.w	d1,d4
	subq.w	#8,d4
	moveq	#17,d6
partial_col_loop:
	moveq	#0,d0
	move.b	(a6)+,d0
	move.b	$0(a5,d0.w),d0
	swap	d0
	lsr.l	#6,d0
	lea	$0(a4,d0.l),a1
	move.w	d5,d7
partial_row_loop:
	movem.l	(a1)+,d0-d3
	movem.l	d0-d1,(a0)
	movem.l	d2-d3,$a0(a0)
	lea	$140(a0),a0
	dbra	d7,partial_row_loop
	suba.w	d4,a0
	dbra	d6,partial_col_loop
	rts

tile_free_list:	; from: init_tile_cache
	ifeq	BUILD_LEVEL-1
	dcb.b	96,$00
	else
	dcb.b	72,$00
	endc
	dc.w	$ffff
tile_free_ptr:	; from: init_tile_cache, tile_cache_get, tile_cache_free
	dc.w	$0000,$0000

;----------------------------------------------------------------------
; Reset the tile cache: free list, reference counts at TILE_REFS, cache every tile of the start window.
;----------------------------------------------------------------------
init_tile_cache:	; from: level_begin
	moveq	#TILE_CACHE_SLOTS-1,d7
	lea	tile_free_list.w,a0
	move.l	a0,tile_free_ptr.w
free_list_loop:
	move.b	d7,(a0)+
	dbra	d7,free_list_loop
	lea	TILE_REFS,a0
	moveq	#TILE_CACHE_SLOTS-1,d7
clear_refs_loop:
	move.l	#$ffffffff,(a0)+
	dbra	d7,clear_refs_loop
	moveq	#0,d0
	movem.w	scroll_x.w,d0-d1
	lsr.w	#3,d1
	lsr.w	#3,d0
	subq.w	#1,d0
	subq.w	#1,d1
	mulu.w	#MAP_ROW_LENGTH,d1
	add.w	d1,d0
	addi.w	#map_tiles,d0
	movea.l	d0,a6
	addi.w	#MAP_ROW_LENGTH+1,d0
	move.l	d0,map_row_ptr.w
	moveq	#10,d6
cache_rows_loop:
	moveq	#19,d7
cache_cols_loop:
	clr.w	d0
	move.b	(a6)+,d0
	movem.w	d6-d7,-(sp)
	bsr.w	tile_cache_free
	movem.w	(sp)+,d6-d7
	dbra	d7,cache_cols_loop
	lea	MAP_ROW_LENGTH-20(a6),a6
	dbra	d6,cache_rows_loop
	moveq	#9,d7
cache_last_row_loop:
	clr.w	d0
	move.b	(a6)+,d0
	movem.w	d6-d7,-(sp)
	bsr.w	tile_cache_free
	movem.w	(sp)+,d6-d7
	dbra	d7,cache_last_row_loop
	rts


scroll_left:	; from: update_scroll
	subq.w	#1,scroll_x.w
	moveq	#7,d0
	move.w	d0,d1
	and.w	scroll_x.w,d0
	cmp.w	d1,d0
	bne.s	left_in_column
	subq.w	#1,map_col.w
left_in_column:
	and.w	scroll_y.w,d1
	lsl.w	#3,d1
	add.w	d0,d1
	add.w	d1,d1
	move.w	d1,d0
	lsl.w	#2,d1
	add.w	d0,d1
	lea	hscroll_redraw_table.w,a6
	adda.w	d1,a6
	move.w	(a6)+,d5
	movea.l	map_row_ptr.w,a5
	movem.w	d5/a6,-(sp)
	lea	$2(a6,d5.w),a6
	adda.w	d5,a6
left_get_loop:
	moveq	#0,d0
	move.w	(a6)+,d1
	move.b	$0(a5,d1.w),d0
	bsr.w	tile_cache_get
	dbra	d5,left_get_loop
	movem.w	(sp)+,d5/a6
left_free_loop:
	moveq	#0,d0
	move.w	(a6)+,d1
	move.b	$0(a5,d1.w),d0
	bsr.w	tile_cache_free
	dbra	d5,left_free_loop
	rts


scroll_right:	; from: update_scroll
	moveq	#7,d0
	move.w	d0,d1
	and.w	scroll_x.w,d0
	and.w	scroll_y.w,d1
	lsl.w	#3,d1
	add.w	d0,d1
	add.w	d1,d1
	move.w	d1,d0
	lsl.w	#2,d1
	add.w	d0,d1
	lea	hscroll_redraw_table.w,a6
	adda.w	d1,a6
	move.w	(a6)+,d7
	move.w	d7,-(sp)
	movea.l	map_row_ptr.w,a5
right_get_loop:
	moveq	#0,d0
	move.w	(a6)+,d1
	move.b	$0(a5,d1.w),d0
	bsr.w	tile_cache_get
	dbra	d7,right_get_loop
	move.w	(sp)+,d5
right_free_loop:
	moveq	#0,d0
	move.w	(a6)+,d1
	move.b	$0(a5,d1.w),d0
	bsr.w	tile_cache_free
	dbra	d5,right_free_loop
	addq.w	#1,scroll_x.w
	moveq	#7,d0
	and.w	scroll_x.w,d0
	bne.s	scroll_right_exit
	addq.w	#1,map_col.w
scroll_right_exit:
	rts


scroll_up:	; from: update_scroll
	moveq	#7,d0
	move.w	d0,d1
	and.w	scroll_x.w,d0
	and.w	scroll_y.w,d1
	lsl.w	#3,d0
	add.w	d1,d0
	lsl.w	#4,d0
	lea	vscroll_redraw_table.w,a6
	adda.w	d0,a6
	move.w	(a6)+,d7
	move.w	d7,-(sp)
	movea.l	map_row_ptr.w,a5
up_get_loop:
	moveq	#0,d0
	move.w	(a6)+,d1
	move.b	$0(a5,d1.w),d0
	bsr.w	tile_cache_get
	dbra	d7,up_get_loop
	move.w	(sp)+,d5
up_free_loop:
	moveq	#0,d0
	move.w	(a6)+,d1
	move.b	$0(a5,d1.w),d0
	bsr.w	tile_cache_free
	dbra	d5,up_free_loop
	addq.w	#1,scroll_y.w
	moveq	#7,d0
	and.w	scroll_y.w,d0
	bne.s	scroll_up_exit
	addi.l	#MAP_ROW_LENGTH,map_row_ptr.w
scroll_up_exit:
	rts


scroll_down:	; from: update_scroll
	subq.w	#1,scroll_y.w
	moveq	#7,d0
	move.w	d0,d1
	and.w	scroll_y.w,d1
	cmp.w	d0,d1
	bne.s	down_in_row
	subi.l	#MAP_ROW_LENGTH,map_row_ptr.w
down_in_row:
	and.w	scroll_x.w,d0
	lsl.w	#3,d0
	add.w	d1,d0
	lsl.w	#4,d0
	lea	vscroll_redraw_table.w,a6
	adda.w	d0,a6
	move.w	(a6)+,d5
	movea.l	map_row_ptr.w,a5
	movem.w	d5/a6,-(sp)
	lea	$2(a6,d5.w),a6
	adda.w	d5,a6
down_get_loop:
	moveq	#0,d0
	move.w	(a6)+,d1
	move.b	$0(a5,d1.w),d0
	bsr.w	tile_cache_get
	dbra	d5,down_get_loop
	movem.w	(sp)+,d5/a6
down_free_loop:
	moveq	#0,d0
	move.w	(a6)+,d1
	move.b	$0(a5,d1.w),d0
	bsr.w	tile_cache_free
	dbra	d5,down_free_loop
	rts


;----------------------------------------------------------------------
; Release one tile reference (d0 = tile); a count reaching 0 frees its cache slot.
;----------------------------------------------------------------------
tile_cache_get:	; from: scroll_left, scroll_right, scroll_up, scroll_down, object_use_start, object_use_anim
	lea	TILE_REFS,a2
	subq.b	#1,$0(a2,d0.w)
	bcc.s	cache_exit
	addi.w	#$100,d0
	move.b	$0(a2,d0.w),d0
	movea.l	tile_free_ptr.w,a1
	move.b	d0,-(a1)
	move.l	a1,tile_free_ptr.w
cache_exit:	; from: tile_cache_free
	rts


;----------------------------------------------------------------------
; Take a tile reference (d0 = tile); a new tile is converted into a free cache slot (8 shifts).
;----------------------------------------------------------------------
tile_cache_free:	; from: init_tile_cache, scroll_left, scroll_right, scroll_up, scroll_down, object_use_start, ...
	lea	TILE_REFS,a2
	addq.b	#1,$0(a2,d0.w)
	bne.s	cache_exit
	moveq	#0,d1
	movea.l	tile_free_ptr.w,a1
	move.b	(a1)+,d1
	bpl.s	cache_load_tile
	bsr.w	redraw_tiles
	bsr.w	wait_vbl_flip
	illegal

unused_after_illegal:
	bsr.w	redraw_tiles
	bsr.w	wait_vbl_flip
cache_load_tile:
	move.l	a1,tile_free_ptr.w
	lea	$100(a2),a2
	move.b	d1,$0(a2,d0.w)
	swap	d1
	lsr.l	#6,d1
	addi.l	#TILE_CACHE,d1
	movea.l	d1,a1
	add.w	d0,d0
	lea	-$300(a2),a2
	move.w	$0(a2,d0.w),d1
	lea	$400(a2),a3
	clr.w	d2
	move.b	d1,d2
	clr.b	d1
	lsr.w	#1,d1
	lea	$0(a3,d1.w),a2
	asl.w	#7,d2
	lea	$0(a3,d2.w),a3
	moveq	#15,d7
cache_shift_loop:
	movem.w	(a3)+,d0-d3
	swap	d0
	swap	d1
	swap	d2
	swap	d3
	move.w	(a2)+,d0
	move.w	(a2)+,d1
	move.w	(a2)+,d2
	move.w	(a2)+,d3
	movem.w	d0-d3,(a1)
	moveq	#2,d4
	rol.l	d4,d0
	rol.l	d4,d1
	rol.l	d4,d2
	rol.l	d4,d3
	movem.w	d0-d3,$80(a1)
	rol.l	d4,d0
	rol.l	d4,d1
	rol.l	d4,d2
	rol.l	d4,d3
	movem.w	d0-d3,$100(a1)
	rol.l	d4,d0
	rol.l	d4,d1
	rol.l	d4,d2
	rol.l	d4,d3
	movem.w	d0-d3,$180(a1)
	rol.l	d4,d0
	rol.l	d4,d1
	rol.l	d4,d2
	rol.l	d4,d3
	movem.w	d0-d3,$200(a1)
	rol.l	d4,d0
	rol.l	d4,d1
	rol.l	d4,d2
	rol.l	d4,d3
	movem.w	d0-d3,$280(a1)
	rol.l	d4,d0
	rol.l	d4,d1
	rol.l	d4,d2
	rol.l	d4,d3
	movem.w	d0-d3,$300(a1)
	rol.l	d4,d0
	rol.l	d4,d1
	rol.l	d4,d2
	rol.l	d4,d3
	movem.w	d0-d3,$380(a1)
	addq.w	#8,a1
	dbra	d7,cache_shift_loop
	rts


; Which screen tiles to redraw for each vertical scroll step: 64 lists of 16 bytes,
; indexed by (scroll_x & 7) * 8 + (scroll_y & 7); a count word then tile entries.
vscroll_redraw_table:	; from: scroll_up, scroll_down
	ifeq	BUILD_LEVEL-1
	dc.w	$0002,$ff33,$ff34,$ff35,$0801,$0802,$0803,$0000
	dc.w	$0001,$ff36,$ff37,$0804,$0805,$0000,$0000,$0000
	dc.w	$0002,$ff38,$ff39,$ff3a,$0806,$0807,$0808,$0000
	dc.w	$0001,$ff3b,$ff3c,$0809,$080a,$0000,$0000,$0000
	dc.w	$0002,$ff3d,$ff3e,$ff3f,$08c3,$08c4,$08c5,$0000
	dc.w	$0001,$ff40,$ff41,$08c6,$08c7,$0000,$0000,$0000
	dc.w	$0002,$ff42,$ff43,$ff44,$08c8,$08c9,$08ca,$0000
	dc.w	$0001,$ff45,$ff46,$08cb,$08cc,$0000,$0000,$0000
	dc.w	$0002,$ff36,$ff34,$ff35,$0801,$0802,$0803,$0000
	dc.w	$0001,$ff38,$ff37,$0804,$0805,$0000,$0000,$0000
	dc.w	$0002,$ff3b,$ff39,$ff3a,$0806,$0807,$0808,$0000
	dc.w	$0001,$ff3d,$ff3c,$0809,$080a,$0000,$0000,$0000
	dc.w	$0002,$ff40,$ff3e,$ff3f,$08c3,$08c4,$08c5,$0000
	dc.w	$0001,$ff42,$ff41,$08c6,$08c7,$0000,$0000,$0000
	dc.w	$0002,$ff45,$ff43,$ff44,$08c8,$08c9,$08ca,$0000
	dc.w	$0002,$ff46,$ff47,$00cb,$00df,$08cb,$08cc,$0000
	dc.w	$0002,$ff36,$ff34,$ff35,$0801,$0802,$0803,$0000
	dc.w	$0001,$ff38,$ff37,$0804,$0805,$0000,$0000,$0000
	dc.w	$0002,$ff3b,$ff39,$ff3a,$0806,$0807,$0808,$0000
	dc.w	$0001,$ff3d,$ff3c,$0809,$080a,$0000,$0000,$0000
	dc.w	$0002,$ff40,$ff3e,$ff3f,$08c3,$08c4,$08c5,$0000
	dc.w	$0001,$ff42,$ff41,$08c6,$08c7,$0000,$0000,$0000
	dc.w	$0002,$ff45,$ff43,$ff44,$08c8,$08c9,$08ca,$0000
	dc.w	$0002,$ff46,$ff47,$0197,$01ab,$08cb,$08cc,$0000
	dc.w	$0002,$ff36,$ff34,$ff35,$0801,$0802,$0803,$0000
	dc.w	$0001,$ff38,$ff37,$0804,$0805,$0000,$0000,$0000
	dc.w	$0002,$ff3b,$ff39,$ff3a,$0806,$0807,$0808,$0000
	dc.w	$0001,$ff3d,$ff3c,$0809,$080a,$0000,$0000,$0000
	dc.w	$0002,$ff40,$ff3e,$ff3f,$08c3,$08c4,$08c5,$0000
	dc.w	$0001,$ff42,$ff41,$08c6,$08c7,$0000,$0000,$0000
	dc.w	$0002,$ff45,$ff43,$ff44,$08c8,$08c9,$08ca,$0000
	dc.w	$0002,$ff46,$ff47,$032f,$0343,$08cb,$08cc,$0000
	dc.w	$0002,$ff36,$ff34,$ff35,$0801,$0802,$0803,$0000
	dc.w	$0001,$ff38,$ff37,$0804,$0805,$0000,$0000,$0000
	dc.w	$0002,$ff3b,$ff39,$ff3a,$0806,$0807,$0808,$0000
	dc.w	$0001,$ff3d,$ff3c,$0809,$080a,$0000,$0000,$0000
	dc.w	$0002,$ff40,$ff3e,$ff3f,$08c3,$08c4,$08c5,$0000
	dc.w	$0001,$ff42,$ff41,$08c6,$08c7,$0000,$0000,$0000
	dc.w	$0002,$ff45,$ff43,$ff44,$08c8,$08c9,$08ca,$0000
	dc.w	$0002,$ff46,$ff47,$03fb,$040f,$08cb,$08cc,$0000
	dc.w	$0002,$ff36,$ff34,$ff35,$0801,$0802,$0803,$0000
	dc.w	$0001,$ff38,$ff37,$0804,$0805,$0000,$0000,$0000
	dc.w	$0002,$ff3b,$ff39,$ff3a,$0806,$0807,$0808,$0000
	dc.w	$0001,$ff3d,$ff3c,$0809,$080a,$0000,$0000,$0000
	dc.w	$0002,$ff40,$ff3e,$ff3f,$08c3,$08c4,$08c5,$0000
	dc.w	$0001,$ff42,$ff41,$08c6,$08c7,$0000,$0000,$0000
	dc.w	$0002,$ff45,$ff43,$ff44,$08c8,$08c9,$08ca,$0000
	dc.w	$0002,$ff46,$ff47,$0593,$05a7,$08cb,$08cc,$0000
	dc.w	$0002,$ff36,$ff34,$ff35,$0801,$0802,$0803,$0000
	dc.w	$0001,$ff38,$ff37,$0804,$0805,$0000,$0000,$0000
	dc.w	$0002,$ff3b,$ff39,$ff3a,$0806,$0807,$0808,$0000
	dc.w	$0001,$ff3d,$ff3c,$0809,$080a,$0000,$0000,$0000
	dc.w	$0002,$ff40,$ff3e,$ff3f,$08c3,$08c4,$08c5,$0000
	dc.w	$0001,$ff42,$ff41,$08c6,$08c7,$0000,$0000,$0000
	dc.w	$0002,$ff45,$ff43,$ff44,$08c8,$08c9,$08ca,$0000
	dc.w	$0002,$ff46,$ff47,$065f,$0673,$08cb,$08cc,$0000
	dc.w	$0002,$ff36,$ff34,$ff35,$0801,$0802,$0803,$0000
	dc.w	$0001,$ff38,$ff37,$0804,$0805,$0000,$0000,$0000
	dc.w	$0002,$ff3b,$ff39,$ff3a,$0806,$0807,$0808,$0000
	dc.w	$0001,$ff3d,$ff3c,$0809,$080a,$0000,$0000,$0000
	dc.w	$0002,$ff40,$ff3e,$ff3f,$08c3,$08c4,$08c5,$0000
	dc.w	$0001,$ff42,$ff41,$08c6,$08c7,$0000,$0000,$0000
	dc.w	$0002,$ff45,$ff43,$ff44,$08c8,$08c9,$08ca,$0000
	dc.w	$0002,$ff46,$ff47,$07f7,$080b,$08cb,$08cc,$0000
	else
	dc.w	$0002,$ffa3,$ffa4,$ffa5,$03a1,$03a2,$03a3,$0000
	dc.w	$0001,$ffa6,$ffa7,$03a4,$03a5,$0000,$0000,$0000
	dc.w	$0002,$ffa8,$ffa9,$ffaa,$03a6,$03a7,$03a8,$0000
	dc.w	$0001,$ffab,$ffac,$03a9,$03aa,$0000,$0000,$0000
	dc.w	$0002,$ffad,$ffae,$ffaf,$03f3,$03f4,$03f5,$0000
	dc.w	$0001,$ffb0,$ffb1,$03f6,$03f7,$0000,$0000,$0000
	dc.w	$0002,$ffb2,$ffb3,$ffb4,$03f8,$03f9,$03fa,$0000
	dc.w	$0001,$ffb5,$ffb6,$03fb,$03fc,$0000,$0000,$0000
	dc.w	$0002,$ffa6,$ffa4,$ffa5,$03a1,$03a2,$03a3,$0000
	dc.w	$0001,$ffa8,$ffa7,$03a4,$03a5,$0000,$0000,$0000
	dc.w	$0002,$ffab,$ffa9,$ffaa,$03a6,$03a7,$03a8,$0000
	dc.w	$0001,$ffad,$ffac,$03a9,$03aa,$0000,$0000,$0000
	dc.w	$0002,$ffb0,$ffae,$ffaf,$03f3,$03f4,$03f5,$0000
	dc.w	$0001,$ffb2,$ffb1,$03f6,$03f7,$0000,$0000,$0000
	dc.w	$0002,$ffb5,$ffb3,$ffb4,$03f8,$03f9,$03fa,$0000
	dc.w	$0002,$ffb6,$ffb7,$005b,$006f,$03fb,$03fc,$0000
	dc.w	$0002,$ffa6,$ffa4,$ffa5,$03a1,$03a2,$03a3,$0000
	dc.w	$0001,$ffa8,$ffa7,$03a4,$03a5,$0000,$0000,$0000
	dc.w	$0002,$ffab,$ffa9,$ffaa,$03a6,$03a7,$03a8,$0000
	dc.w	$0001,$ffad,$ffac,$03a9,$03aa,$0000,$0000,$0000
	dc.w	$0002,$ffb0,$ffae,$ffaf,$03f3,$03f4,$03f5,$0000
	dc.w	$0001,$ffb2,$ffb1,$03f6,$03f7,$0000,$0000,$0000
	dc.w	$0002,$ffb5,$ffb3,$ffb4,$03f8,$03f9,$03fa,$0000
	dc.w	$0002,$ffb6,$ffb7,$00b7,$00cb,$03fb,$03fc,$0000
	dc.w	$0002,$ffa6,$ffa4,$ffa5,$03a1,$03a2,$03a3,$0000
	dc.w	$0001,$ffa8,$ffa7,$03a4,$03a5,$0000,$0000,$0000
	dc.w	$0002,$ffab,$ffa9,$ffaa,$03a6,$03a7,$03a8,$0000
	dc.w	$0001,$ffad,$ffac,$03a9,$03aa,$0000,$0000,$0000
	dc.w	$0002,$ffb0,$ffae,$ffaf,$03f3,$03f4,$03f5,$0000
	dc.w	$0001,$ffb2,$ffb1,$03f6,$03f7,$0000,$0000,$0000
	dc.w	$0002,$ffb5,$ffb3,$ffb4,$03f8,$03f9,$03fa,$0000
	dc.w	$0002,$ffb6,$ffb7,$016f,$0183,$03fb,$03fc,$0000
	dc.w	$0002,$ffa6,$ffa4,$ffa5,$03a1,$03a2,$03a3,$0000
	dc.w	$0001,$ffa8,$ffa7,$03a4,$03a5,$0000,$0000,$0000
	dc.w	$0002,$ffab,$ffa9,$ffaa,$03a6,$03a7,$03a8,$0000
	dc.w	$0001,$ffad,$ffac,$03a9,$03aa,$0000,$0000,$0000
	dc.w	$0002,$ffb0,$ffae,$ffaf,$03f3,$03f4,$03f5,$0000
	dc.w	$0001,$ffb2,$ffb1,$03f6,$03f7,$0000,$0000,$0000
	dc.w	$0002,$ffb5,$ffb3,$ffb4,$03f8,$03f9,$03fa,$0000
	dc.w	$0002,$ffb6,$ffb7,$01cb,$01df,$03fb,$03fc,$0000
	dc.w	$0002,$ffa6,$ffa4,$ffa5,$03a1,$03a2,$03a3,$0000
	dc.w	$0001,$ffa8,$ffa7,$03a4,$03a5,$0000,$0000,$0000
	dc.w	$0002,$ffab,$ffa9,$ffaa,$03a6,$03a7,$03a8,$0000
	dc.w	$0001,$ffad,$ffac,$03a9,$03aa,$0000,$0000,$0000
	dc.w	$0002,$ffb0,$ffae,$ffaf,$03f3,$03f4,$03f5,$0000
	dc.w	$0001,$ffb2,$ffb1,$03f6,$03f7,$0000,$0000,$0000
	dc.w	$0002,$ffb5,$ffb3,$ffb4,$03f8,$03f9,$03fa,$0000
	dc.w	$0002,$ffb6,$ffb7,$0283,$0297,$03fb,$03fc,$0000
	dc.w	$0002,$ffa6,$ffa4,$ffa5,$03a1,$03a2,$03a3,$0000
	dc.w	$0001,$ffa8,$ffa7,$03a4,$03a5,$0000,$0000,$0000
	dc.w	$0002,$ffab,$ffa9,$ffaa,$03a6,$03a7,$03a8,$0000
	dc.w	$0001,$ffad,$ffac,$03a9,$03aa,$0000,$0000,$0000
	dc.w	$0002,$ffb0,$ffae,$ffaf,$03f3,$03f4,$03f5,$0000
	dc.w	$0001,$ffb2,$ffb1,$03f6,$03f7,$0000,$0000,$0000
	dc.w	$0002,$ffb5,$ffb3,$ffb4,$03f8,$03f9,$03fa,$0000
	dc.w	$0002,$ffb6,$ffb7,$02df,$02f3,$03fb,$03fc,$0000
	dc.w	$0002,$ffa6,$ffa4,$ffa5,$03a1,$03a2,$03a3,$0000
	dc.w	$0001,$ffa8,$ffa7,$03a4,$03a5,$0000,$0000,$0000
	dc.w	$0002,$ffab,$ffa9,$ffaa,$03a6,$03a7,$03a8,$0000
	dc.w	$0001,$ffad,$ffac,$03a9,$03aa,$0000,$0000,$0000
	dc.w	$0002,$ffb0,$ffae,$ffaf,$03f3,$03f4,$03f5,$0000
	dc.w	$0001,$ffb2,$ffb1,$03f6,$03f7,$0000,$0000,$0000
	dc.w	$0002,$ffb5,$ffb3,$ffb4,$03f8,$03f9,$03fa,$0000
	dc.w	$0002,$ffb6,$ffb7,$0397,$03ab,$03fb,$03fc,$0000
	endc

; The same for horizontal scrolling (scroll_left / scroll_right).
hscroll_redraw_table:	; from: scroll_left, scroll_right
	ifeq	BUILD_LEVEL-1
	dc.w	$0001,$ff33,$ffff,$ff47,$0013,$0000,$00cb,$00df
	dc.w	$0000,$0000,$0001,$0197,$0263,$01ab,$0277,$0000
	dc.w	$032f,$0343,$0000,$0000,$0001,$03fb,$04c7,$040f
	dc.w	$04db,$0000,$0593,$05a7,$0000,$0000,$0001,$065f
	dc.w	$072b,$0673,$073f,$0000,$07f7,$0801,$0000,$0000
	dc.w	$0001,$ff36,$ffff,$ff47,$0013,$0000,$00cb,$00df
	dc.w	$0000,$0000,$0001,$0197,$0263,$01ab,$0277,$0000
	dc.w	$032f,$0343,$0000,$0000,$0001,$03fb,$04c7,$040f
	dc.w	$04db,$0000,$0593,$05a7,$0000,$0000,$0001,$065f
	dc.w	$072b,$0673,$073f,$0000,$07f7,$0804,$0000,$0000
	dc.w	$0001,$ff38,$ffff,$ff47,$0013,$0000,$00cb,$00df
	dc.w	$0000,$0000,$0001,$0197,$0263,$01ab,$0277,$0000
	dc.w	$032f,$0343,$0000,$0000,$0001,$03fb,$04c7,$040f
	dc.w	$04db,$0000,$0593,$05a7,$0000,$0000,$0001,$065f
	dc.w	$072b,$0673,$073f,$0000,$07f7,$0806,$0000,$0000
	dc.w	$0001,$ff3b,$ffff,$ff47,$0013,$0000,$00cb,$00df
	dc.w	$0000,$0000,$0001,$0197,$0263,$01ab,$0277,$0000
	dc.w	$032f,$0343,$0000,$0000,$0001,$03fb,$04c7,$040f
	dc.w	$04db,$0000,$0593,$05a7,$0000,$0000,$0001,$065f
	dc.w	$072b,$0673,$073f,$0000,$07f7,$0809,$0000,$0000
	dc.w	$0001,$ff3d,$ffff,$ff47,$0013,$0000,$00cb,$00df
	dc.w	$0000,$0000,$0001,$0197,$0263,$01ab,$0277,$0000
	dc.w	$032f,$0343,$0000,$0000,$0001,$03fb,$04c7,$040f
	dc.w	$04db,$0000,$0593,$05a7,$0000,$0000,$0001,$065f
	dc.w	$072b,$0673,$073f,$0000,$07f7,$080b,$0000,$0000
	dc.w	$0001,$ff40,$ffff,$ff47,$0013,$0000,$00cb,$00df
	dc.w	$0000,$0000,$0001,$0197,$0263,$01ab,$0277,$0000
	dc.w	$032f,$0343,$0000,$0000,$0001,$03fb,$04c7,$040f
	dc.w	$04db,$0000,$0593,$05a7,$0000,$0000,$0001,$065f
	dc.w	$072b,$0673,$073f,$0001,$07f7,$08c3,$080b,$08c6
	dc.w	$0001,$ff42,$ffff,$ff47,$0013,$0000,$00cb,$00df
	dc.w	$0000,$0000,$0001,$0197,$0263,$01ab,$0277,$0000
	dc.w	$032f,$0343,$0000,$0000,$0001,$03fb,$04c7,$040f
	dc.w	$04db,$0000,$0593,$05a7,$0000,$0000,$0001,$065f
	dc.w	$072b,$0673,$073f,$0001,$07f7,$08c3,$080b,$08c8
	dc.w	$0001,$ff45,$ffff,$ff47,$0013,$0000,$00cb,$00df
	dc.w	$0000,$0000,$0001,$0197,$0263,$01ab,$0277,$0000
	dc.w	$032f,$0343,$0000,$0000,$0001,$03fb,$04c7,$040f
	dc.w	$04db,$0000,$0593,$05a7,$0000,$0000,$0001,$065f
	dc.w	$072b,$0673,$073f,$0001,$07f7,$08c3,$080b,$08cb
	else
	dc.w	$0001,$ffa3,$ffff,$ffb7,$0013,$0000,$005b,$006f
	dc.w	$0000,$0000,$0001,$00b7,$0113,$00cb,$0127,$0000
	dc.w	$016f,$0183,$0000,$0000,$0001,$01cb,$0227,$01df
	dc.w	$023b,$0000,$0283,$0297,$0000,$0000,$0001,$02df
	dc.w	$033b,$02f3,$034f,$0000,$0397,$03a1,$0000,$0000
	dc.w	$0001,$ffa6,$ffff,$ffb7,$0013,$0000,$005b,$006f
	dc.w	$0000,$0000,$0001,$00b7,$0113,$00cb,$0127,$0000
	dc.w	$016f,$0183,$0000,$0000,$0001,$01cb,$0227,$01df
	dc.w	$023b,$0000,$0283,$0297,$0000,$0000,$0001,$02df
	dc.w	$033b,$02f3,$034f,$0000,$0397,$03a4,$0000,$0000
	dc.w	$0001,$ffa8,$ffff,$ffb7,$0013,$0000,$005b,$006f
	dc.w	$0000,$0000,$0001,$00b7,$0113,$00cb,$0127,$0000
	dc.w	$016f,$0183,$0000,$0000,$0001,$01cb,$0227,$01df
	dc.w	$023b,$0000,$0283,$0297,$0000,$0000,$0001,$02df
	dc.w	$033b,$02f3,$034f,$0000,$0397,$03a6,$0000,$0000
	dc.w	$0001,$ffab,$ffff,$ffb7,$0013,$0000,$005b,$006f
	dc.w	$0000,$0000,$0001,$00b7,$0113,$00cb,$0127,$0000
	dc.w	$016f,$0183,$0000,$0000,$0001,$01cb,$0227,$01df
	dc.w	$023b,$0000,$0283,$0297,$0000,$0000,$0001,$02df
	dc.w	$033b,$02f3,$034f,$0000,$0397,$03a9,$0000,$0000
	dc.w	$0001,$ffad,$ffff,$ffb7,$0013,$0000,$005b,$006f
	dc.w	$0000,$0000,$0001,$00b7,$0113,$00cb,$0127,$0000
	dc.w	$016f,$0183,$0000,$0000,$0001,$01cb,$0227,$01df
	dc.w	$023b,$0000,$0283,$0297,$0000,$0000,$0001,$02df
	dc.w	$033b,$02f3,$034f,$0000,$0397,$03ab,$0000,$0000
	dc.w	$0001,$ffb0,$ffff,$ffb7,$0013,$0000,$005b,$006f
	dc.w	$0000,$0000,$0001,$00b7,$0113,$00cb,$0127,$0000
	dc.w	$016f,$0183,$0000,$0000,$0001,$01cb,$0227,$01df
	dc.w	$023b,$0000,$0283,$0297,$0000,$0000,$0001,$02df
	dc.w	$033b,$02f3,$034f,$0001,$0397,$03f3,$03ab,$03f6
	dc.w	$0001,$ffb2,$ffff,$ffb7,$0013,$0000,$005b,$006f
	dc.w	$0000,$0000,$0001,$00b7,$0113,$00cb,$0127,$0000
	dc.w	$016f,$0183,$0000,$0000,$0001,$01cb,$0227,$01df
	dc.w	$023b,$0000,$0283,$0297,$0000,$0000,$0001,$02df
	dc.w	$033b,$02f3,$034f,$0001,$0397,$03f3,$03ab,$03f8
	dc.w	$0001,$ffb5,$ffff,$ffb7,$0013,$0000,$005b,$006f
	dc.w	$0000,$0000,$0001,$00b7,$0113,$00cb,$0127,$0000
	dc.w	$016f,$0183,$0000,$0000,$0001,$01cb,$0227,$01df
	dc.w	$023b,$0000,$0283,$0297,$0000,$0000,$0001,$02df
	dc.w	$033b,$02f3,$034f,$0001,$0397,$03f3,$03ab,$03fb
	endc

;----------------------------------------------------------------------
; Sort the map tiles by use so that the most used tiles get cache slots first; the map is remapped.
;----------------------------------------------------------------------
build_tile_order:	; from: level_begin
	bra.w	tile_order_init


;----------------------------------------------------------------------
; Not called by anything: turn the map upside down, swapping each of the top half of
; the rows with the one as far from the bottom (MAP_ROWS rows of MAP_ROW_LENGTH bytes).
;----------------------------------------------------------------------
unused_flip_map:
	lea	map_tiles,a0
	tst.b	(a0)
	lea	TILE_TABLE-MAP_ROW_LENGTH,a1
	move.w	#MAP_ROW_LENGTH,d6
	move.w	#MAP_ROWS/2-1,d7
flip_map_row_loop:
	move.w	d6,d5
	subq.w	#1,d5
flip_map_byte_loop:
	move.b	(a0),d0
	move.b	(a1),(a0)
	move.b	d0,(a1)+
	addq.w	#1,a0
	dbra	d5,flip_map_byte_loop
	suba.w	d6,a1
	suba.w	d6,a1
	dbra	d7,flip_map_row_loop
	rts
	ifne	CONFIG-RETAIL_2DISK


;----------------------------------------------------------------------
; Convert the level graphics from 4 bitplanes to the 4 plane + mask format of the blitter.
;----------------------------------------------------------------------
convert_level_gfx:	; from: level_start
	move.w	d7,-(sp)
convert_block_loop:
	movem.l	(a0)+,d0-d1
	moveq	#7,d6
convert_bits_loop:
	add.l	d0,d0
	addx.w	d2,d2
	add.l	d0,d0
	addx.w	d3,d3
	add.l	d0,d0
	addx.w	d4,d4
	add.l	d0,d0
	addx.w	d5,d5
	dbra	d6,convert_bits_loop
	moveq	#7,d6
convert_bits_second:
	add.l	d1,d1
	addx.w	d2,d2
	add.l	d1,d1
	addx.w	d3,d3
	add.l	d1,d1
	addx.w	d4,d4
	add.l	d1,d1
	addx.w	d5,d5
	dbra	d6,convert_bits_second
	movem.w	d2-d5,-$8(a0)
	dbra	d7,convert_block_loop
	move.w	(sp)+,d7
	lea	$2(a0,d7.w),a1
	adda.w	d7,a1
convert_mask_loop:
	movem.w	-$8(a0),d1-d4
	move.w	d1,d0
	and.w	d2,d0
	and.w	d3,d0
	and.w	d4,d0
	eor.w	d0,d1
	eor.w	d0,d2
	eor.w	d0,d3
	eor.w	d0,d4
	movem.w	d0-d4,-(a1)
	subq.l	#8,a0
	dbra	d7,convert_mask_loop
	rts
	endc

tile_order_init:	; from: build_tile_order
	lea	SCREEN_FRONT,a0
	move.w	map_tile_count,d7
	subq.w	#1,d7
	lea	$1(a0,d7.w),a0
tile_order_fill_loop:
	move.b	d7,-(a0)
	dbra	d7,tile_order_fill_loop
tile_order_sort_pass:
	lea	SCREEN_FRONT,a0
	lea	TILE_TABLE,a6
	move.w	map_tile_count,d7
	subq.w	#2,d7
	clr.w	d1
tile_order_compare:
	move.w	(a6)+,d0
	addq.w	#1,a0
	cmp.w	(a6),d0
	bls.s	tile_order_next
	st	d1
	move.w	(a6),-$2(a6)
	move.w	d0,(a6)
	move.b	(a0),d0
	move.b	-$1(a0),(a0)
	move.b	d0,-$1(a0)
tile_order_next:
	dbra	d7,tile_order_compare
	tst.b	d1
	bne.s	tile_order_sort_pass
	clr.w	d0
	move.w	#$ff,d7
	lea	SCREEN_FRONT+$100,a0
	movea.l	a0,a1
tile_order_invert_loop:
	move.b	-(a0),d0
	move.b	d7,$0(a1,d0.w)
	dbra	d7,tile_order_invert_loop
	lea	map_tiles,a0
	move.w	#MAP_ROW_LENGTH*MAP_ROWS-1,d7
tile_order_remap_loop:
	clr.w	d0
	move.b	(a0),d0
	move.b	$0(a1,d0.w),(a0)+
	dbra	d7,tile_order_remap_loop
	rts


;----------------------------------------------------------------------
; Build the sprite tables: unscramble the font, load the two sprite sets, pack and preshift them.
;----------------------------------------------------------------------
build_sprite_tables:	; from: level_start
	move.w	#$13f,d7
	lea	font.w,a0
unscramble_font_loop:
	move.b	$4(a0),d0
	and.b	$1(a0),d0
	not.b	d0
	and.b	$2(a0),d0
	and.b	$3(a0),d0
	eor.b	d0,$1(a0)
	addq.w	#5,a0
	dbra	d7,unscramble_font_loop
	tst.b	GFX_A+6
	lea	SPRITE_HEADERS,a1
	lea	GFX_B+2,a0
	lea	sprite_heights,a2
	bsr.w	load_sprite_sets
	move.l	a1,-(sp)
	lea	GFX_A+2,a0
	bsr.w	load_sprite_sets
	move.l	a1,-(sp)
	move.w	GFX_A+2,d7
	add.w	GFX_B+2,d7
	subq.w	#1,d7
	lea	SPRITE_PACKED,a0
	lea	SPRITE_HEADERS,a1
	bsr.w	pack_sprites
	movea.l	a0,a6
	movea.l	a1,a2
	moveq	#6,d7
sprite_set_loop:
	movem.l	(sp)+,a0-a1
	move.w	#SPRITE_HEADER_COUNT-1,d0
copy_header_loop:
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	dbra	d0,copy_header_loop
	movem.l	a0-a1,-(sp)
	move.w	#SPRITE_HEADER_COUNT-1,d6
	lea	SCREEN_FRONT,a0
sprite_loop:
	move.w	d6,-(sp)
	clr.w	d6
	move.b	$3(a1),d6
	subq.w	#1,d6
	movea.l	$4(a1),a2
	move.l	a0,$4(a1)
sprite_row_loop:
	moveq	#-1,d0
	moveq	#0,d1
	move.l	d1,d2
	move.l	d1,d3
	move.l	d1,d4
	moveq	#63,d5
	and.b	$2(a1),d5
	btst	#$7,$2(a1)
	beq.s	sprite_row_cols
	subq.w	#1,d5
	move.b	(a2)+,d0
	swap	d0
	move.b	(a2)+,d0
	lsr.w	#2,d0
	move.b	d0,(a0)+
	move.b	d0,(a0)+
	move.b	(a2),d1
	swap	d1
	move.b	(a2)+,d1
	lsr.w	#2,d1
	move.b	d1,(a0)+
	move.b	(a2),d2
	swap	d2
	move.b	(a2)+,d2
	lsr.w	#2,d2
	move.b	d2,(a0)+
	move.b	(a2),d3
	swap	d3
	move.b	(a2)+,d3
	lsr.w	#2,d3
	move.b	d3,(a0)+
	move.b	(a2),d4
	swap	d4
	move.b	(a2)+,d4
	lsr.w	#2,d4
	move.b	d4,(a0)+
sprite_row_cols:
	subq.w	#2,d5
	bcs.s	sprite_row_tail
	move.w	(a2)+,d0
	move.w	(a2)+,d1
	move.w	(a2)+,d2
	move.w	(a2)+,d3
	move.w	(a2)+,d4
	lsr.l	#2,d0
	lsr.l	#2,d1
	lsr.l	#2,d2
	lsr.l	#2,d3
	lsr.l	#2,d4
	move.w	d0,(a0)+
	move.w	d1,(a0)+
	move.w	d2,(a0)+
	move.w	d3,(a0)+
	move.w	d4,(a0)+
	movem.w	-$a(a2),d0-d4
	swap	d0
	swap	d1
	swap	d2
	swap	d3
	swap	d4
	bra.s	sprite_row_cols

sprite_row_tail:
	btst	#$6,$2(a1)
	beq.s	sprite_row_tail_narrow
	cmpa.l	#SCREEN_FRONT+$3000,a0
	nop
	move.b	(a2)+,d0
	addq.l	#1,a2
	lsl.w	#8,d0
	lsr.l	#2,d0
	ori.w	#$3f,d0
	move.w	d0,(a0)+
	move.b	(a2)+,d1
	lsl.w	#8,d1
	lsr.l	#2,d1
	move.w	d1,(a0)+
	move.b	(a2)+,d2
	lsl.w	#8,d2
	lsr.l	#2,d2
	move.w	d2,(a0)+
	move.b	(a2)+,d3
	lsl.w	#8,d3
	lsr.l	#2,d3
	move.w	d3,(a0)+
	move.b	(a2)+,d4
	lsl.w	#8,d4
	lsr.l	#2,d4
	move.w	d4,(a0)+
	bra.s	sprite_row_done

sprite_row_tail_narrow:
	swap	d0
	lsl.w	#6,d0
	ori.w	#$3f,d0
	move.b	d0,(a0)+
	move.b	d0,(a0)+
	swap	d1
	lsl.w	#6,d1
	move.b	d1,(a0)+
	swap	d2
	lsl.w	#6,d2
	move.b	d2,(a0)+
	swap	d3
	lsl.w	#6,d3
	move.b	d3,(a0)+
	swap	d4
	lsl.w	#6,d4
	move.b	d4,(a0)+
sprite_row_done:
	dbra	d6,sprite_row_loop
	addq.b	#1,$2(a1)
	bchg	#$6,$2(a1)
	addq.w	#8,a1
	move.w	(sp)+,d6
	dbra	d6,sprite_loop
	movea.l	$4(sp),a1
	movea.l	a6,a0
	move.w	d7,-(sp)
	move.w	#SPRITE_HEADER_COUNT-1,d7
	bsr.w	pack_sprites
	move.w	(sp)+,d7
	movea.l	a0,a6
	dbra	d7,sprite_set_loop
	addq.l	#8,sp
	move.w	#$ff,d7
	lea	SCREEN_FRONT,a3
reverse_table_loop:
	move.w	d7,d5
	moveq	#7,d6
reverse_bits_loop:
	roxr.w	#1,d5
	roxl.w	#1,d4
	dbra	d6,reverse_bits_loop
	move.b	d4,$0(a3,d7.w)
	dbra	d7,reverse_table_loop
	lea	SPRITE_SHIFTED,a0
	lea	sprite_widths.w,a4
	lea	SPRITE_HEADERS,a1
	move.w	#SPRITE_COUNT-1,d7
	clr.w	d0
shift_sprite_loop:
	clr.w	d6
	move.b	$3(a1),d6
	subq.w	#1,d6
	clr.w	d5
	move.b	$2(a1),d5
	movea.l	$4(a1),a2
	moveq	#0,d2
	move.w	d5,d4
	rol.b	#2,d4
	move.b	-$4(a4,d4.w),d2
shift_row_loop:
	adda.l	d2,a0
	moveq	#63,d4
	and.w	d5,d4
	btst	#$7,d5
	beq.s	shift_cols
	subq.w	#1,d4
	subq.w	#6,a0
	moveq	#5,d3
shift_left_edge_loop:
	move.b	(a2)+,d0
	move.b	$0(a3,d0.w),(a0)+
	dbra	d3,shift_left_edge_loop
	subq.w	#6,a0
shift_cols:
	subq.w	#2,d4
	bcs.s	shift_right_edge
	lea	-$a(a0),a0
	moveq	#4,d3
shift_col_loop:
	move.b	(a2)+,d0
	move.b	$0(a3,d0.w),$1(a0)
	move.b	(a2)+,d0
	move.b	$0(a3,d0.w),(a0)
	addq.w	#2,a0
	dbra	d3,shift_col_loop
	lea	-$a(a0),a0
	bra.s	shift_cols

shift_right_edge:
	btst	#$6,d5
	beq.s	shift_next_row
	subq.w	#6,a0
	moveq	#5,d3
shift_right_edge_loop:
	move.b	(a2)+,d0
	move.b	$0(a3,d0.w),(a0)+
	dbra	d3,shift_right_edge_loop
	subq.w	#6,a0
shift_next_row:
	adda.l	d2,a0
	dbra	d6,shift_row_loop
	addq.w	#8,a1
	dbra	d7,shift_sprite_loop
	rts


pack_sprites:	; from: build_sprite_tables
	clr.w	d6
	clr.w	d5
	move.b	$2(a1),d5
	move.b	$3(a1),d6
	movea.l	$4(a1),a2
	move.w	d5,d4
	move.l	a0,$4(a1)
	subq.w	#1,d6
	movem.l	d6/a2,-(sp)
	clr.w	d0
	btst	#$6,d5
	beq.s	pack_width_right
	addq.w	#1,d0
pack_width_right:
	btst	#$7,d5
	beq.s	pack_width_left
	addq.w	#1,d0
pack_width_left:
	andi.w	#$3f,d5
	mulu.w	#$5,d5
	add.w	d0,d5
	moveq	#-1,d0
	move.w	d0,d1
pack_scan_left_loop:
	and.b	(a2),d1
	adda.l	d5,a2
	cmp.b	d1,d0
	bne.s	pack_scan_right
	dbra	d6,pack_scan_left_loop
	bchg	#$7,d4
	subq.w	#1,d4
pack_scan_right:
	movem.l	(sp),d6/a2
	adda.l	d5,a2
	subq.l	#5,a2
	btst	#$6,$2(a1)
	bne.s	pack_scan_right_entry
	subq.l	#4,a2
pack_scan_right_entry:
	moveq	#-1,d0
	move.w	d0,d1
pack_scan_right_loop:
	and.b	(a2),d1
	adda.l	d5,a2
	cmp.b	d1,d0
	bne.s	pack_copy
	dbra	d6,pack_scan_right_loop
	subq.w	#1,d4
	bchg	#$6,d4
pack_copy:
	movem.l	(sp)+,d6/a2
	move.b	$2(a1),d5
pack_row_loop:
	moveq	#63,d3
	and.w	d5,d3
	btst	#$7,d5
	beq.s	pack_left_edge
	subq.w	#1,d3
	btst	#$7,d4
	beq.s	pack_skip_left
	move.w	(a2)+,(a0)+
	move.l	(a2)+,(a0)+
	bra.s	pack_cols_loop

pack_skip_left:
	addq.w	#6,a2
	bra.s	pack_cols_loop

pack_left_edge:
	btst	#$7,d4
	beq.s	pack_cols_loop
	subq.w	#2,d3
	move.b	$1(a2),d0
	move.b	d0,(a0)+
	move.b	d0,(a0)+
	movep.l	$3(a2),d0
	move.l	d0,(a0)+
	lea	$a(a2),a2
pack_cols_loop:
	subq.w	#2,d3
	bcs.s	pack_right_edge
	move.w	(a2)+,(a0)+
	move.l	(a2)+,(a0)+
	move.l	(a2)+,(a0)+
	bra.s	pack_cols_loop

pack_right_edge:
	btst	#$6,d5
	beq.s	pack_shrink_right
	move.w	(a2)+,(a0)+
	move.l	(a2)+,(a0)+
	btst	#$6,d4
	bne.s	pack_next_row
	subq.l	#6,a0
	bra.s	pack_next_row

pack_shrink_right:
	btst	#$6,d4
	beq.s	pack_next_row
	move.b	-$a(a0),-$9(a0)
	move.b	-$6(a0),-$7(a0)
	move.b	-$4(a0),-$6(a0)
	move.b	-$2(a0),-$5(a0)
	subq.w	#4,a0
pack_next_row:
	dbra	d6,pack_row_loop
	move.b	d4,$2(a1)
	addq.w	#8,a1
	dbra	d7,pack_sprites
	rts


load_sprite_sets:	; from: build_sprite_tables
	move.w	(a0)+,d7
	clr.l	d0
	move.w	d7,d0
	subq.w	#1,d7
	move.w	d7,d6
	asl.w	#3,d0
	add.l	a0,d0
	movea.l	d0,a5
sprite_header_loop:
	lea	$2(a0),a0
	move.w	(a2)+,(a1)+
	clr.w	d0
	clr.w	d1
	move.b	(a0)+,d0
	lsr.b	#4,d0
	addq.w	#1,d0
	add.w	d0,d0
	move.b	d0,(a1)+
	move.b	(a0)+,d1
	addq.w	#1,d1
	move.b	d1,(a1)+
	move.l	(a0)+,d2
	add.l	a5,d2
	move.l	d2,(a1)+
	movea.l	d2,a4
	lea	SCREEN_FRONT,a3
	lsr.w	#1,d0
	subq.w	#1,d0
	subq.w	#1,d1
	move.w	d1,d6
sprite_copy_rows:
	move.w	d0,d5
sprite_copy_cols:
	move.w	(a4)+,(a3)+
	move.l	(a4)+,(a3)+
	move.l	(a4)+,(a3)+
	dbra	d5,sprite_copy_cols
	dbra	d6,sprite_copy_rows
	movea.l	-$4(a1),a4
	move.w	d0,d5
	addq.w	#1,d5
	mulu.w	#$a,d5
	suba.l	d5,a3
	add.w	d5,d5
sprite_back_rows:
	move.w	d0,d4
sprite_back_cols:
	move.w	(a3)+,(a4)+
	move.l	(a3)+,(a4)+
	move.l	(a3)+,(a4)+
	dbra	d4,sprite_back_cols
	suba.l	d5,a3
	dbra	d1,sprite_back_rows
	dbra	d7,sprite_header_loop
	rts

map_row_ptr:	; from: init_tile_cache, scroll_left, scroll_right, scroll_up, scroll_down
	dc.w	$0000
map_col:	; from: scroll_left, scroll_right
	dc.w	$0000
sprite_heights:	; from: build_sprite_tables, draw_enemy, draw_player
	dc.w	$2a08,$2008,$2008,$2008,$1508,$1508,$1508,$1508
	dc.w	$1508,$1508,$1508,$1508,$2c10,$1908,$1008,$2b08
	dc.w	$2210,$0a08,$2908,$1a08,$0908,$2508,$1c08,$0508
	ifeq	BUILD_LEVEL-1
	dc.w	$2408,$1a08,$1c08,$1408,$1208,$2c08,$1b08,$1908
	dc.w	$1908,$1908,$1908,$2908,$1b08,$0300,$2908,$2008
	dc.w	$1208,$2a08,$1c08,$2a08,$2a00,$1d08,$0d08,$2a08
	dc.w	$0c08,$1f08,$2010,$0200,$0201,$0202,$0000,$0100
	dc.w	$0100,$0101,$0404,$0907,$0906,$2005,$1208,$1200
	dc.w	$2903,$2206,$2204,$1507,$1506,$1504,$1506,$1507
	dc.w	$1504,$2904,$25fd,$1305,$2904,$2cfd,$2904,$1bfd
	dc.w	$2004,$1cfd,$0c07,$2805,$1503,$1503,$1503,$1503
	dc.w	$0301,$0601,$0400,$04fa,$1d05,$1108,$0809,$2903
	dc.w	$2006,$2004,$1507,$1506,$1504,$1506,$1507,$1504
	dc.w	$2906,$1306,$2a07,$2904,$2efc,$2904,$25fb,$0600
	dc.w	$0402
	else
	dc.w	$2408,$1a08,$1c08,$1408,$1208,$2a08,$1b08,$0e08
	dc.w	$0e08,$0e08,$0e08,$2908,$1b08,$0300,$2908,$2008
	dc.w	$1208,$2a08,$1c08,$2a08,$2a00,$1d08,$0d08,$2a08
	dc.w	$2a08,$1508,$1508,$1508,$1508,$0b08,$0200,$0201
	dc.w	$0202,$0000,$0100,$0100,$0101,$0604,$0b07,$0b06
	dc.w	$1d05,$1308,$0809,$2904,$2006,$2004,$1505,$1505
	dc.w	$1503,$1506,$1506,$1504,$2904,$25fd,$1506,$2b04
	dc.w	$2ffe,$2904,$19fd,$2202,$1efc,$1005,$2805,$1504
	dc.w	$1504,$2906,$1503,$1503,$1505,$0a08,$0009,$2903
	dc.w	$2005,$2004,$2906,$1506,$2906,$2a07,$2903,$2efc
	dc.w	$2903,$24fc,$2706,$1304,$1303,$190b,$0908,$0908
	dc.w	$0908,$0808
	endc
enemies:	; from: level_begin, spawn_enemy, update_enemies, vat_watch, boss_climb_watch
	ifeq	BUILD_LEVEL-1
	dc.w	$0000,$0119,$003a,$006f
	dcb.b	17,$00
	dc.b	$a0,$00,$38,$00,$3d
	dcb.b	17,$00
	dc.b	$a0,$00,$38,$00,$3d
	dcb.b	17,$00
	dc.b	$a0,$00,$38,$00,$3d
	dcb.b	17,$00
	dc.b	$a0,$00,$38,$00,$3d
	dcb.b	17,$00
	dc.b	$a0,$00,$38,$00,$3d
	dcb.b	17,$00
	dc.b	$a0,$00,$38,$00,$3d
	dcb.b	17,$00
	dc.b	$a0,$00,$38,$00,$3d
	dcb.b	17,$00
	dc.b	$a0,$00,$38,$00,$3d,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00
	else
	dc.w	$0000,$0119,$003a
	dcb.b	19,$00
	dc.b	$a0,$00,$38
	dcb.b	19,$00
	dc.b	$a0,$00,$38
	dcb.b	19,$00
	dc.b	$a0,$00,$38
	dcb.b	19,$00
	dc.b	$a0,$00,$38
	dcb.b	19,$00
	dc.b	$a0,$00,$38
	dcb.b	19,$00
	dc.b	$a0,$00,$38
	dcb.b	19,$00
	dc.b	$a0,$00,$38
	dcb.b	19,$00
	dc.b	$a0,$00,$38
	dcb.b	16,$00
	endc
enemies_last:	; from: rope_hook
	ifeq	BUILD_LEVEL-1
	dc.w	$0000,$00a0,$0038,$003d,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000
	else
	dc.w	$0000,$00a0,$0038
	dcb.b	16,$00
	endc
level_name_text:	; from: level_begin
	dc.w	$5009
	ifeq	BUILD_LEVEL-1
	dc.b	'AXIS CHEMICAL FACTORY',0
	dc.b	$ff
jack_dead_text:	; from: level_complete
	dc.b	$40,$0e
	dc.b	'JACK IS DEAD',0
	dc.b	$ff
joker_lives_text:	; from: level_complete
	dc.b	$60,$0b
	dc.b	'THE JOKER LIVES...',0
	dc.w	$ff03
	else
	dc.b	'GOTHAM CITY CATHEDRAL',0
	dc.b	$ff
end_text:	; from: level_complete
	dc.b	$40,$10
	dc.b	'THE END.',0
	dc.b	$ff
end_blank_text:	; from: level_complete
	dc.b	$60,$0b,$20,$00,$ff
	endc

;----------------------------------------------------------------------
; Score 100 points for every 100 pixels scrolled to the right.
;----------------------------------------------------------------------
score_distance:	; from: main_loop
	clr.l	d0
	ifeq	BUILD_LEVEL-1
	move.w	scroll_x.w,d1
	sub.w	score_scroll_x.w,d1
	bls.s	score_distance_exit
	move.w	scroll_x.w,score_scroll_x.w
	else
	move.w	scroll_y.w,d1
	add.w	player_y.w,d1
	sub.w	score_scroll_x.w,d1
	bpl.s	score_distance_exit
	add.w	d1,score_scroll_x.w
	neg.w	d1
	endc
	lsl.w	#4,d1
	move.b	d1,d0
	bra.s	distance_loop

distance_hundreds:
	addi.w	#$100,d0
distance_loop:
	subi.w	#$64,d1
	bcc.s	distance_hundreds
	jmp	panel_add_score

score_distance_exit:
	rts


;----------------------------------------------------------------------
; Spawn the enemies of spawn_table that come into view (groups, then single objects).
;----------------------------------------------------------------------
spawn_enemies:	; from: main_loop
	movem.w	scroll_x.w,d0-d1
	subq.w	#8,d1
	subi.w	#SPAWN_OFFSET_X,d0
	lea	spawn_table.w,a0
spawn_group_loop:
	movem.w	(a0)+,d2-d3
	sub.w	d0,d2
	cmpi.w	#$98,d2
	bcc.s	spawn_next_group
	sub.w	d1,d3
	cmpi.w	#$50,d3
	bcc.s	spawn_next_group
	bset	#$7,-$4(a0)
	move.w	(a0)+,d7
	subq.w	#1,d7
spawn_group_members:
	bsr.w	spawn_enemy
	dbra	d7,spawn_group_members
	bra.s	spawn_groups_done

spawn_next_group:
	move.w	(a0),d2
	add.w	d2,d2
	add.w	(a0),d2
	add.w	d2,d2
	lea	$2(a0,d2.w),a0
spawn_groups_done:
	cmpa.w	#spawn_singles,a0
	bcs.s	spawn_group_loop
	subi.w	#$10,d0
	subq.w	#8,d1
spawn_single_loop:
	movem.w	$2(a0),d2-d3
	sub.w	d0,d2
	cmpi.w	#$c0,d2
	bcc.s	spawn_single_next
	sub.w	d1,d3
	cmpi.w	#$60,d3
	bcc.s	spawn_single_next
	bsr.w	spawn_enemy
	bset	#$7,-$2(a0)
	bra.s	spawn_single_check

spawn_single_next:
	addq.w	#6,a0
spawn_single_check:
	cmpa.w	#checkpoint_starts,a0
	bcs.s	spawn_single_loop
	rts


;----------------------------------------------------------------------
; Put an enemy (a0 -> type, x, y) into a free slot of enemies, sprite base from type_sprite_table.
;----------------------------------------------------------------------
spawn_enemy:	; from: spawn_enemies
	movem.w	(a0)+,d2-d4
	addq.w	#8,d4
	addi.w	#SPAWN_OFFSET_X,d3
	cmp.w	$22,d0
	lea	enemies.w,a6
	moveq	#9,d6
find_enemy_slot:
	tst.w	(a6)
	beq.s	init_enemy
	lea	$16(a6),a6
	dbra	d6,find_enemy_slot
	rts

init_enemy:
	move.w	a0,$14(a6)
	bset	#$f,d2
	movem.w	d2-d4,(a6)
	clr.l	$8(a6)
	bclr	#$f,d2
	clr.l	$10(a6)
	lea	type_sprite_table.w,a5
type_sprite_loop:
	cmp.w	(a5)+,d2
	bcs.s	type_sprite_found
	addq.w	#2,a5
	bra.s	type_sprite_loop

type_sprite_found:
	move.w	(a5),$6(a6)
	rts

unused_next_word:
	ifeq	BUILD_LEVEL-1
	movea.l	dat_06302,a1
	move.w	(a1)+,d2
	move.l	a1,dat_06302
	else
	movea.l	dat_0633e,a1
	move.w	(a1)+,d2
	move.l	a1,dat_0633e
	endc
	rts


;----------------------------------------------------------------------
; Update the 10 enemy records: each type runs its routine from enemy_type_table, then touch test.
;----------------------------------------------------------------------
update_enemies:	; from: main_loop
	lea	enemies.w,a6
	moveq	#9,d7
enemy_loop:
	move.w	(a6),d6
	beq.w	enemy_next
	movem.w	$2(a6),d0-d1
	move.w	d0,d4
	movem.w	scroll_x.w,d2-d3
	sub.w	d2,d0
	sub.w	d3,d1
	cmpi.w	#$140,d0
	bcs.s	enemy_check_y
	cmpi.w	#$ff60,d0
	bcs.s	enemy_remove
enemy_check_y:
	cmpi.w	#$a0,d1
	bcs.s	enemy_on_screen
	cmpi.w	#$ffb0,d1
	bcs.s	enemy_remove
enemy_on_screen:
	bclr	#$7,(a6)
	beq.s	enemy_run
	cmpi.w	#$50,d1
	bcc.s	enemy_run
	cmpi.w	#$a0,d0
	bcc.s	enemy_run
enemy_remove:
	cmpi.w	#$14,d6
	bcs.s	enemy_clear
	lea	$0.w,a0
	movea.l	d0,a0
	movea.w	$14(a6),a0
	bclr	#$7,-$2(a0)
enemy_clear:
	clr.w	(a6)
	bra.s	enemy_next

enemy_run:
	lea	enemy_type_table.w,a0
	add.w	d6,d6
	adda.w	d6,a0
	movea.w	(a0),a0
	move.w	d7,-(sp)
	jsr	(a0)
	movem.w	$e(a6),d0-d2
	sub.w	player_x.w,d0
	addq.w	#6,d0
	cmpi.w	#$d,d0
	bcc.s	enemy_restore
	sub.w	player_top_y.w,d1
	subq.w	#6,d1
	bmi.s	enemy_restore
	sub.w	player_y.w,d2
	bpl.s	enemy_restore
	move.w	(a6),d0
	subq.w	#2,d0
	bmi.s	enemy_restore
	move.w	#$1,(a6)
	moveq	#4,d0
	jsr	play_sfx
	move.w	#$fffe,$a(a6)
	tst.w	on_ground.w
	bmi.s	enemy_restore
	tst.w	rope_length.w
	beq.s	enemy_hurt_player
	tst.w	fall_dx.w
	bne.s	enemy_restore
enemy_hurt_player:
	moveq	#5,d6
	bsr.w	player_damage
enemy_restore:
	move.w	(sp)+,d7
enemy_next:
	lea	$16(a6),a6
	dbra	d7,enemy_loop
	rts


;----------------------------------------------------------------------
; Aim a bullet from an enemy at the player (bullet speed d3).
;----------------------------------------------------------------------
aim_shot:	; from: thug_shoot_right, thug_shoot_left
	addi.w	#$2,(a6)
	movem.w	player_x.w,d2
	move.w	player_top_y.w,d3
	addi.w	#$15,d3
	sub.w	d1,d3
	asl.w	#3,d3
	ext.l	d3
	sub.w	d0,d2
	bpl.s	aim_abs
	neg.w	d2
aim_abs:
	beq.s	aim_divide
	divs.w	d2,d3
aim_divide:
	asr.w	#2,d2
	sub.w	d2,d3
	bsr.w	new_bullet
	cmpi.w	#$8,d3
	bcs.s	aim_store
	bmi.s	aim_clamp_neg
	moveq	#8,d3
	bra.s	aim_store

aim_clamp_neg:
	cmpi.w	#$ffe8,d3
	bcc.s	aim_store
	moveq	#-24,d3
aim_store:
	move.w	d3,$6(a0)
	cmpi.w	#$73,d1
	bpl.s	aim_exit
	movem.w	d0-d1,-(sp)
	moveq	#3,d0
	jsr	play_sfx
	movem.w	(sp)+,d0-d1
aim_exit:
	rts


;----------------------------------------------------------------------
; Enemy types 2-7: thugs walking and shooting, turning at edges and towards the player.
;----------------------------------------------------------------------
thug_shoot_right:	; from: enemy_type_table
	move.w	$8(a6),d2
	cmpi.w	#$7,d2
	bne.s	thug_shoot_right_frame
	subq.w	#5,d0
	bsr.w	aim_shot
	move.w	#$d,(a0)+
	move.w	d1,d3
	subi.w	#$11,d3
	movem.w	d0/d3,(a0)
	addq.w	#5,d0
	moveq	#8,d2
thug_shoot_right_frame:
	addq.w	#1,$8(a6)
	lea	thug_shoot_right_frames.w,a5
	andi.w	#$fe,d2
	adda.w	d2,a5
	add.w	d2,d2
	adda.w	d2,a5
	bra.w	draw_enemy_set


thug_pause_right:	; from: enemy_type_table
	lea	thug_pause_right_frames.w,a5
	bsr.w	draw_enemy_set
	subq.w	#1,$8(a6)
	bne.s	thug_pause_right_exit
	move.w	#$20,$8(a6)
	move.w	#$2,(a6)
thug_pause_right_exit:
	rts


thug_walk_left:	; from: enemy_type_table
	cmpi.w	#$ffc0,d0
	bmi.s	thug_left_turn
	subq.w	#1,$8(a6)
	bpl.s	thug_left_step
	move.w	d0,d2
	sub.w	player_x.w,d2
	cmpi.w	#$30,d2
	bcc.s	thug_left_step
thug_left_shoot:
	clr.w	$8(a6)
	move.w	#$5,(a6)
	bra.w	goon_left_draw

thug_left_step:
	moveq	#7,d2
	and.w	d4,d2
	bne.w	goon_left_step
	subi.w	#$c,d0
	bsr.w	map_tile_at
	addi.w	#$c,d0
	cmpi.b	#TILE_FLOOR,d2
	bcc.w	goon_left_step
	tst.w	$8(a6)
	bpl.s	thug_left_turn
	move.w	d0,d2
	sub.w	player_x.w,d2
	cmpi.w	#$40,d2
	bcs.s	thug_left_shoot
thug_left_turn:
	move.w	#$2,(a6)
	bra.w	goon_left_draw


thug_shoot_left:	; from: enemy_type_table
	move.w	$8(a6),d2
	cmpi.w	#$7,d2
	bne.s	thug_shoot_left_frame
	addq.w	#5,d0
	bsr.w	aim_shot
	move.w	#$c,(a0)+
	move.w	d1,d3
	subi.w	#$11,d3
	movem.w	d0/d3,(a0)
	subq.w	#5,d0
	moveq	#8,d2
thug_shoot_left_frame:
	addq.w	#1,$8(a6)
	lea	thug_shoot_left_frames.w,a5
	andi.w	#$fe,d2
	adda.w	d2,a5
	add.w	d2,d2
	adda.w	d2,a5
	bra.w	draw_enemy_set


thug_pause_left:	; from: enemy_type_table
	lea	thug_pause_left_frames.w,a5
	bsr.w	draw_enemy_set
	subq.w	#1,$8(a6)
	bne.s	thug_pause_left_exit
	move.w	#$20,$8(a6)
	move.w	#$3,(a6)
thug_pause_left_exit:
	rts


thug_walk_right:	; from: enemy_type_table
	cmpi.w	#$e0,d0
	bpl.s	thug_right_turn
	subq.w	#1,$8(a6)
	bpl.s	thug_right_step
	move.w	player_x.w,d2
	sub.w	d0,d2
	cmpi.w	#$30,d2
	bcc.s	thug_right_step
thug_right_shoot:
	clr.w	$8(a6)
	move.w	#$4,(a6)
	bra.w	goon_right_draw

thug_right_step:
	moveq	#7,d2
	and.w	d4,d2
	bne.w	goon_right_step
	addq.w	#8,d0
	bsr.w	map_tile_at
	subq.w	#8,d0
	cmpi.b	#TILE_FLOOR,d2
	bcc.w	goon_right_step
	tst.w	$8(a6)
	bpl.s	thug_right_turn
	move.w	player_x.w,d2
	sub.w	d0,d2
	cmpi.w	#$40,d2
	bcs.s	thug_right_shoot
thug_right_turn:
	move.w	#$3,(a6)
	bra.w	goon_right_draw


check_jump_ladder:	; from: goon_walk_right, goon_walk_left
	move.w	player_y.w,d5
	sub.w	d1,d5
	addi.w	#$10,d5
	ifeq	BUILD_LEVEL-5
	btst	#$2,$3(a6)
	beq.s	jump_ladder_exit
	endc
	cmpi.w	#$20,d5
	bcs.s	jump_ladder_exit
	bpl.s	jump_ladder_check
	move.w	#MAP_ROW_LENGTH,d2
	add.w	d2,d2
	add.w	d2,d2
	sub.w	d2,d3
	clr.w	d2
	move.b	$0(a0,d3.w),d2
jump_ladder_check:
	cmpi.b	#TILE_LADDER,d2
	ifeq	BUILD_LEVEL-5
	bcs.s	jump_ladder_exit
	move.b	$1(a0,d3.w),d2
	btst	#$0,$1(a6)
	bne.s	jump_ladder_other_side
	move.b	-$1(a0,d3.w),d2
jump_ladder_other_side:
	cmpi.b	#TILE_LADDER,d2
	endc
	bcs.s	jump_ladder_exit
	move.w	#$2,$8(a6)
	move.w	#$d,$c(a6)
	subq.w	#8,d5
	bpl.s	jump_ladder_exit
	move.w	#$c,$c(a6)
jump_ladder_exit:
	rts


;----------------------------------------------------------------------
; Enemy types 14/15: the 3 sprite goon, walks, jumps gaps and climbs ladders.
;----------------------------------------------------------------------
goon_walk_right:	; from: enemy_type_table
	move.w	d4,d2
	addq.w	#4,d2
	andi.w	#$7,d2
	bne.w	goon_right_step
	cmpi.w	#$140,d0
	bpl.s	goon_right_edge
	addq.w	#7,d0
	bsr.w	map_tile_at
	subq.w	#7,d0
	cmpi.b	#TILE_FLOOR,d2
	bcc.s	goon_right_decide
goon_right_edge:
	move.w	#$f,(a6)
	clr.w	$8(a6)
	bra.w	goon_right_step

goon_right_decide:
	bsr.w	check_jump_ladder
	subq.w	#1,$8(a6)
	beq.w	goon_jump_done
	bpl.s	goon_right_step
	move.w	player_x.w,d2
	sub.w	d0,d2
	bmi.s	goon_right_step
	cmpi.w	#$20,d5
	bpl.s	goon_right_jump_up
	bcc.s	goon_right_jump_down
	cmpi.w	#$38,d2
	bcc.s	goon_right_step
	move.w	#$10,$c(a6)
	move.l	#$10000,$8(a6)
	bra.s	goon_right_step

goon_right_jump_down:
	subi.w	#$10,d5
	add.w	d5,d2
	ble.s	goon_right_step
	subq.w	#4,d2
	lsr.w	#3,d2
	addq.w	#1,d2
	cmpi.w	#$8,d2
	bcc.s	goon_right_step
	move.w	d2,$8(a6)
	move.l	#$50010,$a(a6)
	bra.s	goon_right_step

goon_right_jump_up:
	subq.w	#8,d5
	sub.w	d5,d2
	bls.s	goon_right_step
	subq.w	#4,d2
	lsr.w	#3,d2
	addq.w	#1,d2
	cmpi.w	#$8,d2
	bcc.s	goon_right_step
	move.w	d2,$8(a6)
	move.l	#$70010,$a(a6)
goon_right_step:	; from: thug_walk_right
	addq.w	#1,d4
	move.w	d4,$2(a6)
goon_right_draw:	; from: thug_walk_right
	divu.w	#$12,d4
	swap	d4
	moveq	#7,d2
	move.b	goon_right_frames(pc,d4.w),d2
	ifeq	BUILD_LEVEL-1
	move.w	d2,-(sp)
	bsr.w	draw_enemy_frame
	else
	ifeq	CONFIG-RETAIL_2DISK
	addi.w	#$40,d2                         ; bug: thugs walking right always show the same legs:
	move.w	d2,-(sp)                        ; the frame is saved after the $40 is added
	endc
	ifne	CONFIG-RETAIL_2DISK
	move.w	d2,-(sp)
	addi.w	#$40,d2
	endc
	bsr.w	draw_enemy_sprite
	endc
	move.w	(sp)+,d4
	moveq	#5,d2
	cmpi.w	#$a,d4
	bcc.s	goon_right_legs
	addq.w	#1,d2
goon_right_legs:
	bsr.w	draw_enemy_frame
	moveq	#4,d2
	bra.w	draw_enemy

goon_right_frames:	; from: goon_walk_right
	dc.w	$0707,$0708,$0808,$0909,$090a,$0a0a,$0b0b,$0b0c
	dc.w	$0c0c

goon_walk_left:	; from: enemy_type_table
	move.w	d4,d2
	addq.w	#4,d2
	ifeq	BUILD_LEVEL-1
	andi.w	#$7,d2
	else
	andi.w	#$3,d2
	endc
	bne.w	goon_left_step
	cmpi.w	#$ff60,d0
	bmi.s	goon_left_edge
	subq.w	#7,d0
	bsr.w	map_tile_at
	addq.w	#7,d0
	cmpi.b	#TILE_FLOOR,d2
	bcc.s	goon_left_decide
	move.w	$6(a6),d2
	cmpi.w	#JACK_SPRITE,d2
	beq.w	jack_start
goon_left_edge:
	move.w	#$e,(a6)
	clr.w	$8(a6)
	bra.w	goon_left_step

goon_left_decide:
	bsr.w	check_jump_ladder
	subq.w	#1,$8(a6)
	beq.w	goon_jump_done
	bpl.s	goon_left_step
	move.w	d0,d2
	sub.w	player_x.w,d2
	bmi.s	goon_left_step
	cmpi.w	#$20,d5
	bpl.s	goon_left_jump_up
	bcc.s	goon_left_jump_down
	cmpi.w	#$38,d2
	bcc.s	goon_left_step
	move.w	#$10,$c(a6)
	move.l	#$10001,$8(a6)
	bra.s	goon_left_step

goon_left_jump_down:
	subi.w	#$10,d5
	add.w	d5,d2
	ble.s	goon_left_step
	subq.w	#4,d2
	ifeq	BUILD_LEVEL-1
	lsr.w	#3,d2
	else
	lsr.w	#2,d2
	endc
	addq.w	#1,d2
	cmpi.w	#$8,d2
	bcc.s	goon_left_step
	move.w	d2,$8(a6)
	move.l	#$40010,$a(a6)
	bra.s	goon_left_step

goon_left_jump_up:
	subq.w	#8,d5
	sub.w	d5,d2
	bls.s	goon_left_step
	subq.w	#4,d2
	ifeq	BUILD_LEVEL-1
	lsr.w	#3,d2
	else
	lsr.w	#2,d2
	endc
	addq.w	#1,d2
	cmpi.w	#$8,d2
	bcc.s	goon_left_step
	move.w	d2,$8(a6)
	move.l	#$60010,$a(a6)
goon_left_step:	; from: thug_walk_left
	subq.w	#1,d4
	move.w	d4,$2(a6)
goon_left_draw:	; from: thug_walk_left
	divu.w	#$12,d4
	swap	d4
	move.w	#$e00c,d2
	move.b	goon_left_frames(pc,d4.w),d2
	move.w	d2,-(sp)
	ifeq	BUILD_LEVEL-1
	bsr.w	draw_enemy_frame
	else
	addi.w	#$40,d2
	bsr.w	draw_enemy_sprite
	endc
	move.w	(sp)+,d4
	move.w	#$e005,d2
	cmpi.w	#$e00a,d4
	bcc.s	goon_left_legs
	addq.w	#1,d2
goon_left_legs:
	bsr.w	draw_enemy_frame
	move.w	#$e004,d2
	bra.w	draw_enemy

goon_left_frames:	; from: goon_walk_left
	dc.w	$0c0c,$0c0b,$0b0b,$0a0a,$0a09,$0909,$0808,$0807
	dc.w	$0707
goon_jump_done:	; from: goon_walk_right
	move.w	$c(a6),d6
	move.w	d6,(a6)
	cmpi.w	#$10,d6
	bne.s	goon_run_type
	move.w	#$2,$8(a6)
	move.w	$a(a6),d2
	cmpi.w	#$2,d2
	bcc.s	goon_run_type
	move.w	$12(a6),d2
	addq.w	#4,d2
	sub.w	player_top_y.w,d2
	bpl.s	goon_run_type
	addq.w	#2,$a(a6)
goon_run_type:
	lea	enemy_type_table.w,a0
	add.w	d6,d6
	adda.w	d6,a0
	movea.w	(a0),a0
	jmp	(a0)


;----------------------------------------------------------------------
; Enemy types 12/13: climbing a ladder down / up.
;----------------------------------------------------------------------
climb_down:	; from: enemy_type_table
	move.w	$4(a6),d4
	btst	#$0,frame_toggle+1.w
	bne.s	climb_draw
	addq.w	#1,d4
	move.w	d4,$4(a6)
	addq.w	#1,d1
	andi.w	#$7,d4
	bne.s	climb_draw
	bsr.w	map_tile_at
	ifeq	BUILD_LEVEL-1
	bra.s	climb_check
	else
	cmpi.b	#TILE_LADDER,d2
	bcc.s	climb_draw
	bsr.w	climb_turn
climb_draw:
	not.w	d4
	andi.w	#$6,d4
	lsr.w	#1,d4
	move.w	d4,d2
	bclr	#$1,d2
	beq.s	climb_down_frame
	ori.w	#$e000,d2
climb_down_frame:
	addi.w	#$1b,d2
	move.w	d2,-(sp)
	bsr.w	draw_enemy_frame
	move.w	(sp)+,d2
	andi.w	#$e000,d2
	addi.w	#$1a,d2
	bra.w	draw_enemy
	endc


climb_up:	; from: enemy_type_table
	move.w	$4(a6),d4
	btst	#$0,frame_toggle+1.w
	ifeq	BUILD_LEVEL-1
	bne.s	climb_draw
	else
	bne.s	climb_up_frame
	endc
	subq.w	#1,d4
	move.w	d4,$4(a6)
	subq.w	#1,d1
	andi.w	#$7,d4
	ifeq	BUILD_LEVEL-1
	bne.s	climb_draw
	subi.w	#$18,d1
	bsr.w	map_tile_at
	addi.w	#$18,d1
climb_check:	; from: climb_down
	cmpi.b	#TILE_LADDER,d2
	bcc.s	climb_draw
	bsr.s	climb_turn
climb_draw:	; from: climb_down
	not.w	d4
	andi.w	#$7,d4
	move.w	d4,d2
	bclr	#$2,d2
	else
	bne.s	climb_up_frame
	subq.w	#8,d1
	bsr.w	map_tile_at
	addq.w	#8,d1
	cmpi.b	#TILE_LADDER,d2
	bcc.s	climb_up_frame
	bsr.s	climb_turn
climb_up_frame:
	not.w	d4
	andi.w	#$6,d4
	lsr.w	#1,d4
	move.w	d4,d2
	bclr	#$1,d2
	endc
	beq.s	climb_flip
	ori.w	#$e000,d2
climb_flip:
	addi.w	#$18,d2
	move.w	d2,-(sp)
	bsr.w	draw_enemy_frame
	move.w	(sp)+,d2
	andi.w	#$e000,d2
	addi.w	#$17,d2
	bra.w	draw_enemy


climb_turn:	; from: climb_up, climb_down
	moveq	#7,d2
	moveq	#76,d3
	sub.w	d0,d3
	add.w	d3,d3
	addx.w	d2,d2
	move.w	d2,(a6)
	rts


;----------------------------------------------------------------------
; Enemy types 16-18: Jack Napier (sprite base $803d): waits, shoots and turns.  A goon walking left with his sprite (type 23) becomes him at a floor edge (jack_start).  Never run on level 5: no level 5 object has sprite base $803d.
;----------------------------------------------------------------------
jack_start:	; from: goon_walk_left
	move.w	#$ffff,$8(a6)
	moveq	#6,d2
	cmp.w	player_top_y.w,d1
	bmi.s	jack_set_type
	moveq	#1,d2
	move.w	$12(a6),d3
	addq.w	#4,d3
	cmp.w	player_top_y.w,d3
	bpl.s	jack_set_type
	addq.w	#2,d2
jack_set_type:
	move.w	d2,$a(a6)
	move.w	#$10,(a6)

jack_wait:	; from: enemy_type_table
	bsr.w	draw_jack
	subq.w	#1,$8(a6)
	bpl.s	jack_exit
	addq.w	#1,(a6)
	move.w	#$3,$8(a6)
jack_exit:	; from: jack_shoot, jack_turn
	rts


jack_shoot:	; from: enemy_type_table
	bsr.w	draw_jack
	btst	#$0,frame_toggle+1
	bne.s	jack_exit
	bsr.w	new_bullet
	sub.w	(a5)+,d1
	add.w	scroll_dy.w,d1
	add.w	(a5)+,d0
	add.w	scroll_dx.w,d0
	move.w	(a5),(a0)+
	movem.w	d0-d1,(a0)
	moveq	#2,d2
	bsr.w	play_sfx_on_screen
	subq.w	#1,$8(a6)
	bne.s	jack_exit
	move.w	#$6,$8(a6)
	addq.w	#1,(a6)
	rts


jack_turn:	; from: enemy_type_table
	bsr.w	draw_jack
	subq.w	#1,$8(a6)
	bne.s	jack_exit
	move.w	#$4,$8(a6)
	move.w	$a(a6),d2
	move.w	$6(a6),d3
	cmpi.w	#JACK_SPRITE,d3
	bne.s	jack_turn_store
	move.w	#$1,d2
jack_turn_store:
	not.w	d2
	andi.w	#$1,d2
	addi.w	#$e,d2
	move.w	d2,(a6)
	move.w	d2,$c(a6)
	move.w	$2(a6),d4
sfx_exit:	; from: play_sfx_on_screen
	rts


play_sfx_on_screen:	; from: jack_shoot, grenade_right, attack_frame, faller
	cmpi.w	#$a0,d0
	bcc.s	sfx_exit
	cmpi.w	#$59,d1
	bcc.s	sfx_exit
	movem.w	d0-d1,-(sp)
	move.w	d2,d0
	jsr	play_sfx
	movem.w	(sp)+,d0-d1
	rts

thug_shoot_right_frames:	; from: thug_shoot_right
	ifeq	BUILD_LEVEL-1
	dc.w	$e004,$e005,$e008,$e00d,$e00e,$0000,$e00f,$e00e
	dc.w	$0000,$e010,$e011,$e00e
	else
	dc.w	$e007,$e008,$0000,$e009,$e008,$0000,$e00a,$e008
	dc.w	$0000,$e00b,$e00c,$e008
	endc
thug_pause_right_frames:	; from: thug_pause_right
	ifeq	BUILD_LEVEL-1
	dc.w	$e012,$e013,$e00e
	else
	dc.w	$e00d,$e00e,$e008
	endc
thug_shoot_left_frames:	; from: thug_shoot_left
	ifeq	BUILD_LEVEL-1
	dc.w	$0004,$0005,$0008,$000d,$000e,$0000,$000f,$000e
	dc.w	$0000,$0010,$0011,$000e
	else
	dc.w	$0007,$0008,$0000,$0009,$0008,$0000,$000a,$0008
	dc.w	$0000,$000b,$000c,$0008
	endc
thug_pause_left_frames:	; from: thug_pause_left
	ifeq	BUILD_LEVEL-1
	dc.w	$0012,$0013,$000e
	else
	dc.w	$000d,$000e,$0008
	endc
jack_frames:	; from: draw_jack
	dc.w	$000d,$000e,$000f,$0012,$0008,$8006,$e00d,$e00e
	dc.w	$e00f,$0012,$fff8,$8007,$0014,$0015,$0016,$000e
	dc.w	$0008,$8006,$e014,$e015,$e016,$000e,$fff8,$8007
	ifeq	BUILD_LEVEL-1
	dc.w	$e010,$e011,$e00f,$0012,$fffd,$800b,$0010,$0011
	dc.w	$000f,$0012,$0003,$800a,$e012,$e013,$e00f,$000c
	dc.w	$fffb,$8009,$0012,$0013,$000f,$000c,$0005,$8008
	else
	dc.w	$e010,$e011,$e00f,$0014,$fffe,$800b,$0010,$0011
	dc.w	$000f,$0014,$0002,$800a,$e012,$e013,$e00f,$000b
	dc.w	$fffb,$8009,$0012,$0013,$000f,$000b,$0005,$8008
	endc

draw_jack:	; from: jack_wait, jack_shoot, jack_turn
	move.w	$a(a6),d2
	mulu.w	#$c,d2
	lea	jack_frames(pc,d2.w),a5

draw_enemy_set:	; from: thug_shoot_right, thug_pause_right, thug_shoot_left, thug_pause_left, thug_fall
	move.w	(a5)+,d2
	bsr.s	draw_enemy
	move.w	(a5)+,d2
	bsr.s	draw_enemy_frame
	move.w	(a5)+,d2
	bne.s	draw_enemy_frame
	rts


draw_enemy:	; from: goon_walk_right, goon_walk_left, climb_up, draw_enemy_set, boss_climb, climb_down
	add.w	$6(a6),d2
	move.w	d2,d3
	andi.w	#$1fff,d3
	lsl.w	#1,d3
	lea	sprite_heights.w,a0
	move.w	d1,d4
	add.w	d4,d4
	move.b	-$2(a0,d3.w),d5
	ext.w	d5
	sub.w	d5,d4
	asr.w	#1,d4
	movem.w	d0-d1/d4,$e(a6)
	movem.w	d0-d1/a5-a6,-(sp)
	bsr.w	draw_sprite
	movem.w	(sp)+,d0-d1/a5-a6
	rts


draw_enemy_frame:	; from: goon_walk_right, goon_walk_left, climb_up, draw_enemy_set, vat_splash, attacker_right, climb_down, ...
	add.w	$6(a6),d2
	ifeq	BUILD_LEVEL-5

draw_enemy_sprite:	; from: goon_walk_right, goon_walk_left
	endc
	movem.w	d0-d1/a5-a6,-(sp)
	bsr.w	draw_sprite
	movem.w	(sp)+,d0-d1/a5-a6
	rts


;----------------------------------------------------------------------
; Enemy type 1: a knocked thug falling off the screen (350 points).
;----------------------------------------------------------------------
thug_fall:	; from: enemy_type_table
	move.w	$a(a6),d2
	addq.w	#1,d2
	cmpi.w	#$e,d2
	bpl.s	thug_fall_move
	move.w	d2,$a(a6)
thug_fall_move:
	asr.w	#1,d2
	add.w	d2,$4(a6)
	lea	thug_fall_frames.w,a5
	cmpi.w	#$64,d1
	bmi.w	draw_enemy_set
	clr.w	(a6)
	move.l	#$350,d0
	jmp	panel_add_score


;----------------------------------------------------------------------
; Draw the 20 bullets (sprite BULLET_SPRITE + type).
;----------------------------------------------------------------------
draw_bullets:	; from: main_loop
	lea	bullet_table.w,a5
	lea	bullets.w,a6
	moveq	#19,d7
bullets_draw_loop:
	move.w	(a6)+,d2
	beq.s	bullets_draw_next
	movem.w	(a6),d0-d1
	move.l	a6,-(sp)
	move.w	d7,-(sp)
	btst	#$f,d2
	beq.s	bullet_sprite
	ext.w	d2
	move.w	d2,-$2(a6)
	moveq	#4,d2
bullet_sprite:
	ror.w	#1,d2
	bpl.s	bullet_sprite_offset
	ori.w	#$e000,d2
bullet_sprite_offset:
	addi.w	#BULLET_SPRITE,d2
	bsr.w	draw_sprite
	move.w	(sp)+,d7
	movea.l	(sp)+,a6
bullets_draw_next:
	addq.w	#6,a6
	dbra	d7,bullets_draw_loop
	rts


new_bullet:	; from: aim_shot, jack_shoot, throw_batarang, fire_rope_up
	lea	bullets.w,a0
	moveq	#19,d7
bullet_slot_loop:
	tst.w	(a0)
	beq.s	new_bullet_exit
	lea	$8(a0),a0
	dbra	d7,bullet_slot_loop
	movea.l	#$fffffff8,a0
new_bullet_exit:
	rts


;----------------------------------------------------------------------
; Move the bullets: each type runs its routine from bullet_table.
;----------------------------------------------------------------------
update_bullets:	; from: main_loop
	lea	bullet_table.w,a5
	lea	bullets.w,a6
	moveq	#19,d7
bullets_update_loop:
	move.w	(a6)+,d6
	beq.s	bullets_update_next
	cmpi.w	#$f,d6
	bne.s	bullet_run
	nop
bullet_run:
	movem.w	(a6),d0-d1
	sub.w	scroll_dx.w,d0
	sub.w	scroll_dy.w,d1
	asl.w	#1,d6
	clr.l	d2
	movea.l	d2,a0
	movea.w	-$2(a5,d6.w),a0
	jsr	(a0)
bullets_update_next:
	addq.w	#6,a6
	dbra	d7,bullets_update_loop
	rts


;----------------------------------------------------------------------
; Bullet step: store the position, remove it on a wall, hurt the player on contact.
;----------------------------------------------------------------------
bullet_move:	; from: bullet_up_left, bullet_up_right, bullet_down_left, bullet_down_right, bullet_left, bullet_right
	movem.w	d0-d1,(a6)
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	bcs.s	bullet_hit_wall
	sub.w	player_x.w,d0
	addq.w	#4,d0
	cmpi.w	#$9,d0
	bcc.s	bullet_exit
	cmp.w	player_y.w,d1
	bpl.s	bullet_exit
	cmp.w	player_top_y.w,d1
	bmi.s	bullet_exit
	moveq	#1,d6
	bsr.w	player_damage
	moveq	#4,d0
	jsr	play_sfx
bullet_hit_wall:
	move.w	#$4,-$2(a6)
bullet_exit:
	rts


bullet_up_left:	; from: bullet_table
	subq.w	#3,d0
	cmpi.w	#$fff6,d0
	bmi.s	bullet_remove
	subq.w	#3,d1
	cmpi.w	#$54,d1
	bcs.s	bullet_move
	bra.s	bullet_remove


bullet_up_right:	; from: bullet_table
	addq.w	#3,d0
	cmpi.w	#$a8,d0
	bpl.s	bullet_remove
	subq.w	#3,d1
	cmpi.w	#$50,d1
	bcs.s	bullet_move
	bra.s	bullet_remove


bullet_down_left:	; from: bullet_table
	subq.w	#3,d0
	cmpi.w	#$fff6,d0
	bmi.s	bullet_remove
	addq.w	#3,d1
	cmpi.w	#$50,d1
	bcs.s	bullet_move
	bra.s	bullet_remove


bullet_down_right:	; from: bullet_table
	addq.w	#3,d0
	cmpi.w	#$a8,d0
	bpl.s	bullet_remove
	addq.w	#3,d1
	cmpi.w	#$54,d1
	bcs.w	bullet_move
	bra.s	bullet_remove


bullet_left:	; from: bullet_table
	subq.w	#5,d0
	cmpi.w	#$fff6,d0
	bpl.w	bullet_move
	bra.s	bullet_remove


bullet_right:	; from: bullet_table
	addq.w	#5,d0
	cmpi.w	#$a8,d0
	bmi.w	bullet_move

bullet_remove:	; from: bullet_up_left, bullet_up_right, bullet_down_left, bullet_down_right, bullet_left, batarang_right, ...
	clr.w	-$2(a6)
	rts


batarang_right:	; from: bullet_table
	addq.w	#4,d0
	cmpi.w	#$a8,d0
	bpl.s	bullet_remove
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	movem.w	d0-d1,(a6)
	bcc.s	hit_enemies
	bcs.s	bullet_remove

batarang_left:	; from: bullet_table
	subq.w	#4,d0
	cmpi.w	#$fff6,d0
	bmi.s	bullet_remove
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	movem.w	d0-d1,(a6)
	bcc.s	hit_enemies
	bra.s	bullet_remove


;----------------------------------------------------------------------
; Bullet type: the rope hook, knocks enemies the rope end touches.
;----------------------------------------------------------------------
rope_hook:	; from: bullet_table
	move.w	rope_length.w,d0
	beq.s	bullet_remove
	movem.w	player_x.w,d0-d1
	add.w	rope_end.w,d0
	sub.w	rope_end+2.w,d1
	subi.w	#$c,d1
	addq.w	#5,d0
	tst.w	player_frame_legs.w
	bpl.s	rope_hook_pos
	subq.w	#7,d0
rope_hook_pos:
	movem.w	d0-d1,(a6)
hit_enemies:	; from: batarang_right, batarang_left
	lea	enemies_last.w,a4
	moveq	#9,d6
hit_enemy_loop:
	move.w	(a4),d2
	subq.w	#2,d2
	bmi.s	hit_enemy_next
	move.w	$e(a4),d2
	sub.w	d0,d2
	addq.w	#4,d2
	cmpi.w	#$8,d2
	bcc.s	hit_enemy_next
	cmp.w	$10(a4),d1
	bpl.s	hit_enemy_next
	cmp.w	$12(a4),d1
	bpl.s	enemy_knocked
hit_enemy_next:
	lea	-$16(a4),a4
	dbra	d6,hit_enemy_loop
	rts

enemy_knocked:
	move.w	#$1,(a4)
	move.w	#$fffc,$a(a4)
	bsr.w	bullet_remove
	moveq	#4,d0
	jmp	play_sfx


;----------------------------------------------------------------------
; Bullet types: grenades flying right / left with gravity, exploding on the floor.
;----------------------------------------------------------------------
grenade_right:	; from: bullet_table
	addq.w	#2,d0
	move.w	$4(a6),d2
	cmpi.w	#$28,d2
	bpl.s	grenade_gravity
	addq.w	#1,$4(a6)
grenade_gravity:
	asr.w	#2,d2
	bpl.s	grenade_fall
	addq.w	#1,d2
grenade_fall:
	add.w	d2,d1
	cmpi.w	#$60,d1
	bpl.w	bullet_remove
grenade_move:	; from: grenade_left
	movem.w	d0-d1,(a6)
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	bcs.s	grenade_explode
	sub.w	player_x.w,d0
	addq.w	#3,d0
	cmpi.w	#$7,d0
	bcc.s	grenade_exit
	cmp.w	player_y.w,d1
	bpl.s	grenade_exit
	cmp.w	player_top_y.w,d1
	bmi.s	grenade_exit
	moveq	#4,d6
	bsr.w	player_damage
	movem.w	(a6),d0-d1
grenade_explode:
	move.w	#$e,-$2(a6)
	move.w	#$2,$4(a6)
	moveq	#5,d2
	bra.w	play_sfx_on_screen

grenade_exit:
	rts


grenade_left:	; from: bullet_table
	subq.w	#2,d0
	move.w	$4(a6),d2
	cmpi.w	#$28,d2
	bpl.s	grenade_left_gravity
	addq.w	#1,$4(a6)
grenade_left_gravity:
	asr.w	#2,d2
	bpl.s	grenade_left_fall
	addq.w	#1,d2
grenade_left_fall:
	add.w	d2,d1
	cmpi.w	#$60,d1
	bpl.w	bullet_remove
	bra.s	grenade_move


explosion_anim:	; from: bullet_table
	movem.w	d0-d1,(a6)
	subq.w	#1,$4(a6)
	bne.s	explosion_exit
	move.w	#$2,$4(a6)
	move.w	-$2(a6),d2
	addq.w	#1,d2
	cmpi.w	#$14,d2
	bne.s	explosion_frame
	clr.w	d2
explosion_frame:
	move.w	d2,-$2(a6)
explosion_exit:
	rts

bullet_table:	; from: draw_bullets, update_bullets
	dc.w	rope_hook
	dc.w	batarang_right
	dc.w	batarang_left
	dc.w	bullet_remove
	dc.w	bullet_remove
	dc.w	bullet_right
	dc.w	bullet_left
	dc.w	bullet_down_right
	dc.w	bullet_down_left
	dc.w	bullet_up_right
	dc.w	bullet_up_left
	dc.w	grenade_right
	dc.w	grenade_left
	dc.w	explosion_anim
	dc.w	explosion_anim
	dc.w	explosion_anim
	dc.w	explosion_anim
	dc.w	explosion_anim
	dc.w	explosion_anim
	dc.w	explosion_anim
	dc.w	explosion_anim
	dc.w	explosion_anim
	dc.w	explosion_anim
bullets:	; from: level_begin, draw_bullets, new_bullet, update_bullets
	dcb.b	160,$00
scroll_dy_last:	; from: update_scroll
	dc.w	$0000

;----------------------------------------------------------------------
; Scroll the map to keep the player in view (scroll_x/scroll_y), keeping the tile cache in step.
;----------------------------------------------------------------------
update_scroll:	; from: main_loop
	movem.w	player_y.w,d1-d2
	move.w	d1,d0
	sub.w	d2,d0
	move.w	scroll_dy.w,scroll_dy_last.w
	move.w	d0,scroll_dy.w
	beq.w	scroll_horizontal
	tst.w	on_ground.w
	beq.s	scroll_clamp
	bmi.s	scroll_rope_dy
	cmpi.w	#$4,d0
	bcs.s	scroll_clamp
	cmpi.w	#$fffd,d0
	bcc.s	scroll_clamp
	bpl.s	scroll_dy_pos
	moveq	#-2,d0
	bra.s	scroll_clamp

scroll_dy_pos:
	moveq	#2,d0
	bra.s	scroll_clamp

scroll_rope_dy:
	cmpi.w	#$8,d0
	bcs.s	scroll_clamp
	cmpi.w	#$fffd,d0
	bcc.s	scroll_clamp
	bmi.s	scroll_dy_neg
	moveq	#8,d0
	bra.s	scroll_clamp

scroll_dy_neg:
	moveq	#-3,d0
scroll_clamp:
	move.w	scroll_y.w,d1
	subq.w	#8,d1
	move.w	d1,d3
	add.w	d0,d1
	cmpi.w	#SCROLL_Y_LIMIT+1,d1
	bcs.s	scroll_vertical
	bmi.s	scroll_top
	move.w	#SCROLL_Y_LIMIT,d2
	sub.w	d2,d1
	sub.w	d1,d0
	move.w	d2,d1
	bra.s	scroll_vertical

scroll_top:
	sub.w	d1,d0
	clr.w	d1
scroll_vertical:
	sub.w	d0,player_y.w
	sub.w	d3,d1
	move.w	d1,scroll_dy.w
	beq.s	scroll_horizontal
	bmi.s	scroll_down_loop
scroll_up_loop:
	subq.w	#1,d0
	move.w	d0,-(sp)
	bsr.w	scroll_up
	move.w	(sp)+,d0
	bne.s	scroll_up_loop
	bra.s	scroll_horizontal

scroll_down_loop:
	addq.w	#1,d0
	move.w	d0,-(sp)
	bsr.w	scroll_down
	move.w	(sp)+,d0
	bne.s	scroll_down_loop
scroll_horizontal:
	move.w	player_x.w,d0
	move.w	camera_x.w,d1
	sub.w	d1,d0
	move.w	d1,player_x.w
	move.w	d0,scroll_dx.w
	beq.s	scroll_exit
	bpl.s	scroll_right_loop
scroll_left_loop:
	addq.w	#1,d0
	move.w	d0,-(sp)
	bsr.w	scroll_left
	move.w	(sp)+,d0
	bne.s	scroll_left_loop
	rts

scroll_right_loop:
	subq.w	#1,d0
	move.w	d0,-(sp)
	bsr.w	scroll_right
	move.w	(sp)+,d0
	bne.s	scroll_right_loop
scroll_exit:
	rts


;----------------------------------------------------------------------
; Idle player state: dispatch on joy_state through player_input_table.
;----------------------------------------------------------------------
player_input:	; from: level_begin, main_loop, state_knocked_wait, throw_batarang, state_rope_retract, walk_left, ...
	clr.w	d2
	move.b	joy_state.w,d2
	asl.w	#2,d2
	movea.l	player_input_table(pc,d2.w),a0
	jmp	(a0)

player_input_table:	; from: player_input
	dc.l	player_idle
	dc.l	walk_right
	dc.l	walk_left
	dc.l	player_idle
	dc.l	crouch
	dc.l	walk_right_down
	dc.l	walk_left_down
	dc.l	player_idle
	dc.l	push_up
	dc.l	walk_right_up
	dc.l	walk_left_up
	dc.l	player_idle
	dc.l	player_idle
	dc.l	player_idle
	dc.l	player_idle
	dc.l	player_idle
	dc.l	throw_batarang
	dc.l	throw_batarang
	dc.l	throw_batarang
	dc.l	throw_batarang
	dc.l	drop_down
	dc.l	drop_down
	dc.l	drop_down
	dc.l	drop_down
	dc.l	fire_rope_up
	dc.l	fire_rope_right
	dc.l	fire_rope_left
	dc.l	player_idle
	dc.l	player_idle
	dc.l	player_idle
	dc.l	player_idle
	dc.l	player_idle

;----------------------------------------------------------------------
; Hurt the player: d6 = energy loss, then knock back according to the current state.
;----------------------------------------------------------------------
player_damage:	; from: update_enemies, bullet_move, grenade_right, state_rope_swing, state_landed, attack_hit_right, ...
	tst.b	panel_flags
	bne.s	player_exit
	movem.l	d0-d7/a5-a6,-(sp)
	move.w	d6,d0
	jsr	panel_lose_energy
	movem.l	(sp)+,d0-d7/a5-a6

;----------------------------------------------------------------------
; Knock the player back according to the current state.
;----------------------------------------------------------------------
player_knockback:	; from: timerc_handler
	move.w	player_state_lo.w,d2
	cmpi.w	#state_falling,d2
	beq.s	player_exit
	move.w	#state_rope_hit,d3
	cmp.w	d3,d2
	beq.s	knock_set_state
	cmpi.w	#state_rope_swing,d2
	beq.s	knock_set_state
	cmpi.w	#state_rope_climb,d2
	beq.s	knock_on_rope_climb
	move.w	#state_knocked,d3
	cmpi.w	#state_ladder,d2
	beq.s	knock_set_state
	cmp.w	d2,d3
	beq.s	knock_set_state
	lea	knocked_frames.w,a0
	bsr.w	set_player_anim
	move.w	#state_knocked_wait,d3
knock_set_state:
	move.w	d3,player_state_lo.w
	move.w	knock_timer.w,d2
	add.w	d6,d6
	add.w	d6,d6
	add.w	d6,d2
	cmpi.w	#$c,d2
	bcs.s	knock_store_timer
	moveq	#12,d2
knock_store_timer:
	move.w	d2,knock_timer.w
player_exit:	; from: player_damage, state_knocked, state_knocked_wait, state_dying
	rts

knock_on_rope_climb:
	move.w	state_timer.w,d2
	add.w	d6,d2
	add.w	d6,d2
	add.w	d6,d2
	move.w	d2,state_timer.w
	rts


;----------------------------------------------------------------------
; State: knocked back, then back to the ladder.
;----------------------------------------------------------------------
state_knocked:
	subq.w	#1,knock_timer.w
	bne.s	player_exit
	move.w	#state_ladder,player_state_lo.w
	bra.s	knocked_check_dead


;----------------------------------------------------------------------
; State: knocked back, waiting; dies when a panel flag says so.
;----------------------------------------------------------------------
state_knocked_wait:
	bsr.w	draw_player
	tst.w	rope_length.w
	beq.s	knocked_wait_count
	bsr.w	state_rope_retract
knocked_wait_count:
	subq.w	#1,knock_timer.w
	bne.s	player_exit
	move.w	#player_input,player_state_lo.w
	tst.w	rope_length.w
	beq.s	knocked_wait_anim
	bsr.w	rope_miss
knocked_wait_anim:
	bsr.w	set_idle_anim
knocked_check_dead:	; from: state_knocked
	tst.b	panel_flags
	beq.s	player_exit
player_dies:	; from: state_landed
	clr.w	rope_length.w
	move.w	#state_dying,player_state_lo.w
	move.w	#anim_crouched+$3,anim_script.w
	move.b	game_flags,saved_game_flags.w
	bclr	#$0,game_flags
	jsr	snd_stop
	moveq	#10,d0
	jsr	play_tune
	rts

saved_game_flags:	; from: state_knocked_wait, state_dying, level_complete
	dc.w	$0000

;----------------------------------------------------------------------
; State: dying animation, then TIME UP / GAME OVER texts, restart or leave the level.
;----------------------------------------------------------------------
state_dying:	; from: state_knocked_wait
	movea.w	anim_script.w,a0
	bsr.w	set_player_anim
	move.w	a0,anim_script.w
	tst.b	(a0)
	bne.w	player_exit
	move.w	#$32,d0
	bsr.w	wait_frames
	move.b	saved_game_flags.w,game_flags
	bsr.w	clear_back_screen
	btst	#$0,panel_flags
	beq.s	dying_game_over
	lea	time_up_text.w,a0
	bsr.w	print_text
dying_game_over:
	btst	#$1,panel_flags
	beq.s	dying_dissolve
	lea	game_over_text.w,a0
	bsr.w	print_text
dying_dissolve:
	bsr.w	dissolve_in
	move.w	#$1e,d0
	bsr.w	wait_frames
	btst	#$1,panel_flags
	beq.w	level_restart
leave_level:	; from: main_loop
	jsr	snd_stop
	bsr.w	fade_out
	bra.w	LOADER_FRONT_END

game_over_text:	; from: state_dying
	dc.w	$570f
	dc.b	'GAME  OVER',0
	dc.b	$ff
time_up_text:	; from: state_dying
	dc.w	$3b10
	dc.b	'TIME  UP',0
	dc.b	$ff

clear_back_screen:	; from: state_dying, level_complete
	movea.l	screen_back,a0
	move.w	#$2f7f,d7
clear_back_loop_b:
	clr.w	(a0)+
	dbra	d7,clear_back_loop_b
	rts


;----------------------------------------------------------------------
; State: hit while on the rope, shorten the rope and swing on.
;----------------------------------------------------------------------
state_rope_hit:
	moveq	#16,d3
	tst.b	panel_flags
	bne.s	rope_hit_store
	lea	rope_length.w,a0
	move.w	(a0),d2
	cmpi.w	#$50,d2
	bcc.s	rope_hit_store
	addq.w	#1,(a0)
	clr.w	d3
	subq.w	#1,knock_timer.w
	bne.s	rope_hit_store
	move.w	#state_rope_swing,player_state_lo.w
rope_hit_store:
	move.b	d3,joy_state.w

;----------------------------------------------------------------------
; Swinging on the rope: up/down change rope_length, fire lets go (start_fall).
;----------------------------------------------------------------------
state_rope_swing:	; from: state_rope_hit, fire_rope_up
	lea	rope_length.w,a0
	move.w	(a0),d5
	move.b	joy_state.w,d4
	btst	#$3,d4
	beq.s	swing_lengthen
	move.w	#$48,player_ref_y.w
	subq.w	#1,d5
	bhi.s	swing_store_length
	clr.w	(a0)
	move.w	#state_rope_climb,player_state_lo.w
	move.w	#$5,state_timer.w
	move.w	#anim_rope_hang+$10,anim_script.w
	move.w	d1,d2
	add.w	scroll_y.w,d2
	subq.w	#4,d2
	andi.w	#$7,d2
	sub.w	d2,d1
	move.w	d1,player_y.w
	rts

swing_store_length:
	move.w	d5,(a0)
swing_lengthen:
	btst	#$2,d4
	beq.w	swing_physics
	move.w	#$28,player_ref_y.w
	addq.w	#1,d5
	cmpi.w	#$50,d5
	bcc.s	swing_physics
	move.w	d5,(a0)
swing_physics:
	lea	rope_angle.w,a0
	movem.w	(a0),d2-d3
	clr.w	d7
	moveq	#7,d6
	cmpi.w	#$28,d5
	bcc.s	swing_input
	moveq	#3,d6
	cmpi.w	#$14,d6
	bcc.s	swing_input
	moveq	#1,d6
swing_input:
	and.w	frame_toggle.w,d6
	bne.s	swing_angle
	andi.w	#$3,d4
	asr.w	#1,d4
	subx.w	d7,d4
	move.w	d4,d7
swing_angle:
	move.w	d2,d4
	ext.l	d4
	divs.w	d5,d4
	sub.w	d7,d4
	add.w	d4,d3
	sub.w	d3,d2
	addi.w	#$80,d2
	cmpi.w	#$100,d2
	bcc.s	swing_clamp
	subi.w	#$80,d2
	bra.s	swing_store_angle

swing_clamp:
	clr.w	d3
	subi.w	#$80,d2
	bpl.s	swing_clamp_pos
	moveq	#-127,d2
	bra.s	swing_store_angle

swing_clamp_pos:
	moveq	#127,d2
swing_store_angle:
	movem.w	d2-d3,(a0)
swing_move:
	lea	rope_angle.w,a0
	lea	player_x.w,a2
	bsr.w	rope_vector
	movem.w	player_x.w,d0-d1
	movem.w	rope_anchor.w,d5-d6
	sub.w	d3,d5
	move.w	d5,fall_dx.w
	move.w	d5,scroll_dx.w
	sub.w	d6,d4
	move.w	d4,fall_dy.w
	add.w	d4,d1
	add.w	d5,d0
	subq.w	#4,d1
	subq.w	#5,d0
	bsr.w	map_tile_at
	moveq	#2,d7
swing_tile_loop:
	move.b	$0(a0,d3.w),d2
	cmpi.b	#TILE_OPEN,d2
	bcs.s	swing_blocked
	move.b	$1(a0,d3.w),d2
	cmpi.b	#TILE_OPEN,d2
	bcs.s	swing_blocked
	subi.w	#MAP_ROW_LENGTH,d3
	dbra	d7,swing_tile_loop
	movem.w	player_x.w,d0-d1
	add.w	d4,d1
	add.w	d5,d0
	movem.w	d0-d1,player_x.w
	move.l	rope_end.w,rope_anchor.w
	btst	#$4,joy_state.w
	bne.s	swing_let_go
	rts

swing_blocked:
	tst.w	d4
	bmi.s	swing_hit_wall
	subq.w	#2,rope_length.w
	bra.w	swing_move

swing_hit_wall:
	movem.w	d0-d7,-(sp)
	moveq	#2,d6
	bsr.w	player_damage
	movem.w	(sp)+,d0-d7
	clr.w	d4
	clr.w	d5
	bra.s	swing_fall

swing_let_go:
	movem.w	fall_dx.w,d4-d5
	subq.w	#3,d5
	cmpi.w	#$fffa,d5
	bpl.s	swing_dx_clamp
	moveq	#-6,d5
swing_dx_clamp:
	subq.w	#2,d4
	cmpi.w	#$fffc,d4
	bcc.s	swing_dx_adjust
	smi	d4
	asl.w	#2,d4
swing_dx_adjust:
	addq.w	#2,d4
swing_fall:
	movem.w	d4-d5,fall_dx.w
	clr.w	rope_length.w
	movem.w	player_x.w,d0-d1
	bra.w	fall_with_velocity


;----------------------------------------------------------------------
; Fire: throw a batarang (new_bullet) and play effect 9.
;----------------------------------------------------------------------
throw_batarang:	; from: player_input_table
	tst.w	throw_cooldown.w
	bpl.s	throw_exit
	move.w	#anim_rope_hang+$3,anim_script
	move.w	#state_throwing,player_state_lo.w
	moveq	#9,d0
	jsr	play_sfx
state_throwing:
	movea.w	anim_script.w,a0
	bsr.w	set_player_anim
	move.w	a0,anim_script.w
	tst.b	(a0)
	bne.s	throw_exit
	move.w	#$3,throw_cooldown.w
	move.w	#$8,state_timer.w
	move.w	#state_throw_done,player_state_lo.w
	bsr.w	new_bullet
	subi.w	#$7,d0
	move.w	player_frame_legs.w,d2
	spl	d2
	ext.w	d2
	bpl.s	throw_set_bullet
	addi.w	#$e,d0
throw_set_bullet:
	addq.w	#3,d2
	move.w	d2,(a0)+
	subi.w	#$10,d1
	movem.w	d0-d1,(a0)
throw_exit:
	rts

state_throw_done:
	move.b	joy_state,d4
	bne.w	throw_resume_input
	subq.w	#1,state_timer.w
	bne.s	throw_exit
	lea	anim_idle.w,a0
	bra.w	set_player_anim

throw_resume_input:
	move.w	#player_input,player_state_lo.w
	bra.w	player_input

state_rope_climb:	; from: state_rope_swing
	subq.w	#1,state_timer.w
	bne.s	throw_exit
	move.w	#$6,state_timer.w
	subq.w	#4,player_y.w
	subq.w	#4,d1
	move.w	player_frame_legs.w,d2
	bmi.s	climb_left_side
	addq.w	#7,d0
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	bcs.s	climb_anim
	addq.w	#1,player_x.w
	bra.s	climb_anim

climb_left_side:
	subq.w	#6,d0
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	bcs.s	climb_anim
	subq.w	#1,player_x.w
climb_anim:
	movea.w	anim_script.w,a0
	tst.b	(a0)
	beq.s	climb_top
	bsr.w	set_player_anim
	move.w	a0,anim_script.w
	rts

climb_top:
	move.w	#crouch_stand,player_state_lo.w
	bra.w	crouch_stand


rope_vector:	; from: state_rope_swing, fire_rope_up, state_rope_retract
	lea	$7c(a0),a1
	move.w	(a0),d2
	asr.w	#1,d2
	move.w	d2,d4
	bpl.s	vector_abs
	neg.w	d4
vector_abs:
	clr.w	d3
	move.b	-$40(a1,d4.w),d3
	mulu.w	$4(a0),d3
	btst	#$f,d2
	beq.s	vector_shift
	neg.w	d3
vector_shift:
	asr.w	#8,d3
	move.w	d3,$6(a0)
	move.w	d4,d2
	neg.w	d2
	clr.w	d4
	move.b	$3f(a1,d2.w),d4
	mulu.w	$4(a0),d4
	lsr.w	#8,d4
	move.w	d4,$8(a0)
	rts


fire_rope_right:	; from: player_input_table
	clr.w	player_frame_legs.w
	moveq	#127,d0
	bra.s	rope_launch


fire_rope_left:	; from: player_input_table
	move.w	#$e000,player_frame_legs.w
	moveq	#-127,d0
	bra.s	rope_launch


;----------------------------------------------------------------------
; Fire + up: launch the batrope (rope_angle 0 = straight up, +-127 = diagonal).
;----------------------------------------------------------------------
fire_rope_up:	; from: player_input_table
	clr.w	d0
rope_launch:	; from: fire_rope_right, fire_rope_left
	move.w	#$48,player_ref_y.w
	lea	rope_angle.w,a0
	move.w	d0,(a0)+
	clr.l	(a0)+
	bsr.w	new_bullet
	move.w	#$1,(a0)
	move.w	#state_rope_extend,player_state_lo.w
	lea	anim_rope_launch.w,a0
	bsr.w	set_player_anim
	moveq	#1,d0
	jsr	play_sfx
	movem.w	player_x.w,d0-d1
	bclr	#$4,joy_state.w
state_rope_extend:
	lea	rope_angle.w,a0
	btst	#$4,joy_state
	bne.s	retract_fast
	move.w	$4(a0),d2
	addq.w	#2,d2
	cmpi.w	#$28,d2
	bcc.s	extend_store_length
	addq.w	#1,d2
	cmpi.w	#$14,d2
	bcc.s	extend_store_length
	addq.w	#1,d2
extend_store_length:
	move.w	d2,$4(a0)
	bsr.w	rope_vector
	addq.w	#3,d3
	move.w	player_frame_legs.w,d7
	bpl.s	extend_check_wall
	subq.w	#7,d3
extend_check_wall:
	addi.w	#$a,d4
	sub.w	d4,d1
	bcs.s	rope_miss
	move.w	scroll_y.w,d5
	add.w	d1,d5
	btst	#$2,d5
	bne.s	rope_extend_exit
	add.w	d3,d0
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	bcs.s	rope_miss
	cmpi.b	#TILE_LADDER,d2
	bcc.s	rope_miss
	cmpi.b	#TILE_FLOOR,d2
	bcs.s	rope_extend_exit
	move.w	#state_rope_swing,player_state_lo.w
	move.l	rope_end.w,rope_anchor.w
	lea	anim_rope_hang.w,a0
	bra.w	set_player_anim


rope_miss:	; from: state_knocked_wait, fire_rope_up
	move.w	#state_rope_retract,player_state_lo.w
rope_extend_exit:	; from: fire_rope_up
	rts


state_rope_retract:	; from: state_knocked_wait, rope_miss
	lea	rope_angle.w,a0
	btst	#$4,joy_state
	beq.s	retract_shorten
retract_fast:	; from: fire_rope_up
	move.w	#$2,$4(a0)
retract_shorten:
	subq.w	#3,$4(a0)
	bls.s	retract_done
	bra.w	rope_vector

retract_done:
	clr.w	$4(a0)
	move.w	#player_input,player_state_lo.w
	lea	anim_idle.w,a0
	bra.w	set_player_anim

ladder_exit:	; from: ladder_below, ladder_above
	rts


ladder_below:	; from: walk_right_down, walk_left_down, crouch
	move.w	#$28,player_ref_y.w
	ifeq	BUILD_LEVEL-1
	move.w	scroll_x.w,d2
	add.w	d0,d2
	andi.w	#$7,d2
	subq.w	#4,d2
	bne.s	ladder_exit
	bsr.w	map_tile_at
	cmpi.b	#TILE_LADDER,d2
	bcs.s	ladder_exit
	else
	addq.w	#4,d0
	bsr.w	map_tile_at
	subq.w	#4,d0
	cmpi.b	#$f9,d2
	bne.s	ladder_exit
	endc
	bra.s	on_ladder


push_up:	; from: player_input_table
	bsr.s	ladder_above
	bra.w	set_idle_anim


ladder_above:	; from: push_up, walk_right_up, walk_left_up
	move.w	#$48,player_ref_y.w
	ifeq	BUILD_LEVEL-1
	move.w	scroll_x.w,d2
	add.w	d0,d2
	andi.w	#$7,d2
	subq.w	#4,d2
	bne.s	ladder_exit
	subi.w	#$c,d1
	bsr.w	map_tile_at
	addi.w	#$c,d1
	cmpi.b	#TILE_LADDER,d2
	bcs.s	ladder_exit
	else
	addq.w	#4,d0
	subq.w	#4,d1
	bsr.w	map_tile_at
	addq.w	#4,d1
	subq.w	#4,d0
	cmpi.b	#$fe,d2
	bne.s	ladder_exit
	endc
on_ladder:	; from: ladder_below
	addq.w	#4,sp
	andi.b	#$c,joy_state.w
	move.w	#state_ladder,player_state_lo.w
	bra.w	state_ladder


walk_right_down:	; from: player_input_table
	bsr.s	ladder_below
	bra.s	walk_right


walk_right_up:	; from: player_input_table
	bsr.s	ladder_above

walk_right:	; from: player_input_table, walk_right_down
	addq.w	#4,d0
	subq.w	#2,d1
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	bcs.s	player_idle
	addq.w	#1,player_x.w
	addq.w	#7,d1
	subq.w	#5,d0
	bsr.w	map_tile_at
	subi.b	#TILE_FLOOR,d2
	cmpi.b	#FLOOR_WALK_END-TILE_FLOOR,d2
	bcc.w	start_fall
	lea	player_frames.w,a0
	add.w	scroll_x.w,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	addq.w	#5,d0
	move.w	d0,(a0)+
	andi.w	#$6,d0
	lsr.w	#1,d0
	bne.s	walk_right_frame
	moveq	#2,d0
walk_right_frame:
	addq.w	#1,d0
	move.w	d0,(a0)+
	move.w	#$1,(a0)

player_idle:	; from: player_input_table, walk_right, walk_left, enemy_type_table, vat_watch, boss_climb_watch
	rts


walk_left_down:	; from: player_input_table
	bsr.w	ladder_below
	bra.s	walk_left


walk_left_up:	; from: player_input_table
	bsr.w	ladder_above

walk_left:	; from: player_input_table, walk_left_down
	subq.w	#5,d0
	subq.w	#2,d1
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	bcs.s	player_idle
	subq.w	#1,player_x.w
	addq.w	#7,d1
	addq.w	#5,d0
	bsr.w	map_tile_at
	subi.b	#TILE_FLOOR,d2
	cmpi.b	#FLOOR_WALK_END-TILE_FLOOR,d2
	bcc.w	start_fall
	lea	player_frames.w,a0
	add.w	scroll_x.w,d0
	not.w	d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	addi.w	#$e005,d0
	move.w	d0,(a0)+
	andi.w	#$e006,d0
	lsr.b	#1,d0
	bne.s	walk_left_frame
	move.w	#$e002,d0
walk_left_frame:
	addq.w	#1,d0
	move.w	d0,(a0)+
	move.w	#$e001,(a0)
ladder_idle:	; from: state_ladder
	rts

ladder_step_off:	; from: state_ladder
	add.w	d5,d3
	move.b	$0(a0,d3.w),d2
	subi.b	#TILE_FLOOR,d2
	ifeq	BUILD_LEVEL-1
	cmpi.b	#FLOOR_LAND_END-TILE_FLOOR,d2
	else
	cmpi.b	#$2d,d2
	endc
	bcc.s	ladder_down
	andi.b	#$3,joy_state.w
	move.w	#player_input,player_state_lo.w
	bra.w	player_input


;----------------------------------------------------------------------
; On a ladder: up/down climb, left/right step off.
;----------------------------------------------------------------------
state_ladder:	; from: state_knocked, ladder_above
	btst	#$4,joy_state.w
	bne.w	start_fall
	btst	#$0,frame_toggle+1.w
	bne.s	ladder_idle
	clr.w	d4
	move.b	joy_state.w,d4
	move.w	scroll_y.w,d2
	add.w	d1,d2
	andi.w	#$7,d2
	beq.s	ladder_aligned
	btst	#$2,d4
	beq.s	ladder_up_input
	addq.w	#1,d1
	move.w	#$28,player_ref_y.w
ladder_up_input:
	btst	#$3,d4
	beq.s	ladder_store_y
	subq.w	#1,d1
	move.w	#$48,player_ref_y.w
ladder_store_y:
	move.w	d1,player_y.w
	bra.s	ladder_anim

ladder_aligned:
	bsr.w	map_tile_at
	moveq	#1,d5
	asr.w	#1,d4
	bcs.s	ladder_step_off
	moveq	#-1,d5
	asr.w	#1,d4
	bcs.s	ladder_step_off
ladder_down:	; from: walk_left
	asr.w	#1,d4
	bcc.s	ladder_up
	move.w	#$28,player_ref_y.w
	cmpi.b	#TILE_LADDER,d2
	bcs.w	ladder_leave
	addq.w	#1,player_y.w
	bra.s	ladder_anim

ladder_up:
	asr.w	#1,d4
	bcc.s	ladder_done
	move.w	#$48,player_ref_y.w
	move.w	#MAP_ROW_LENGTH,d5
	sub.w	d5,d3
	ifeq	BUILD_LEVEL-1
	sub.w	d5,d3
	sub.w	d5,d3
	endc
	move.b	$0(a0,d3.w),d2
	cmpi.b	#TILE_LADDER,d2
	bcs.s	ladder_leave
	subq.w	#1,d1
	move.w	d1,player_y.w
ladder_anim:
	ifeq	BUILD_LEVEL-5
	moveq	#30,d3
	moveq	#32,d4
	btst	#$3,joy_state.w
	bne.s	ladder_anim_frames
	btst	#$2,joy_state.w
	beq.s	ladder_done
	moveq	#49,d3
	moveq	#50,d4
ladder_anim_frames:
	endc
	move.w	scroll_y.w,d2
	add.w	player_y.w,d2
	addq.w	#2,d2
	not.w	d2
	andi.w	#$7,d2
	bclr	#$2,d2
	beq.s	ladder_anim_flip
	ifeq	BUILD_LEVEL-1
	addi.w	#$e000,d2
	else
	addi.w	#$e000,d4
	addi.w	#$e000,d3
	endc
ladder_anim_flip:
	ifeq	BUILD_LEVEL-1
	addi.w	#$20,d2
	else
	add.w	d4,d2
	endc
	lea	player_frames.w,a0
	clr.w	(a0)+
	move.w	d2,(a0)+
	ifeq	BUILD_LEVEL-1
	andi.w	#$e000,d2
	addi.w	#$1e,d2
	move.w	d2,(a0)
	else
	move.w	d3,(a0)
	endc
ladder_done:
	rts

ladder_leave:
	move.w	#player_input,player_state_lo.w
	rts


drop_down:	; from: player_input_table, crouch, object_use_anim
	addi.w	#$8,d1
	bsr.w	map_tile_at
	movem.w	player_x.w,d0-d1
	cmpi.b	#TILE_OPEN,d2
	bcs.s	crouch
	move.w	#$8000,fall_distance_patch.w
	bra.w	start_fall


crouch:	; from: player_input_table, drop_down
	bsr.w	ladder_below
	lea	anim_crouch.w,a0
	bsr.s	set_player_anim
	move.w	#state_crouching,player_state_lo.w
	rts

state_crouching:
	lea	anim_crouched.w,a0
	bsr.s	set_player_anim
	btst	#$2,joy_state.w
	bne.s	crouch_fire_check
crouch_stand:	; from: throw_batarang
	move.w	#state_uncrouch,player_state_lo.w
	lea	anim_crouch.w,a0
	bra.s	set_player_anim

crouch_fire_check:
	btst	#$4,joy_state.w
	bne.s	drop_down
	rts


;----------------------------------------------------------------------
; State: standing up from a crouch.
;----------------------------------------------------------------------
state_uncrouch:
	move.w	#player_input,player_state_lo.w

set_idle_anim:	; from: state_knocked_wait, push_up
	lea	anim_idle.w,a0
	bra.w	set_player_anim


set_player_anim:	; from: level_begin, player_knockback, state_dying, throw_batarang, fire_rope_up, state_rope_retract, ...
	move.w	d7,-(sp)
	lea	player_frame_legs.w,a1
	move.w	(a1),d7
	andi.w	#$e000,d7
	add.b	(a0)+,d7
	move.w	d7,(a1)
	add.b	(a0)+,d7
	move.w	d7,-(a1)
	add.b	(a0)+,d7
	move.w	d7,-(a1)
	move.w	(sp)+,d7
	rts

fall_frames:	; from: start_fall
	dc.w	$0d01
	dc.b	$01
knocked_frames:	; from: player_knockback, start_fall
	dc.b	$10,$01,$01

;----------------------------------------------------------------------
; Start falling with velocity fall_dx/fall_dy; state_falling tracks fall_distance.
;----------------------------------------------------------------------
start_fall:	; from: walk_right, walk_left, state_ladder, drop_down
	movem.w	player_x.w,d0-d1
	clr.l	fall_dx.w
fall_with_velocity:	; from: state_rope_swing
	move.w	player_y.w,player_ref_y.w
	lea	fall_frames(pc),a0
	bsr.w	set_player_anim
	move.w	#state_falling,player_state_lo.w
	move.w	#$ffff,on_ground.w
	clr.w	fall_distance.w
state_falling:
	movem.w	fall_dx.w,d4-d5
	move.w	d4,scroll_dx.w
	beq.s	fall_gravity
	subi.w	#$10,d1
	subq.w	#4,d0
	add.w	d4,d0
	bsr.w	map_tile_at
	movem.w	player_x.w,d0-d1
	moveq	#1,d7
fall_tile_loop:
	cmpi.b	#TILE_OPEN,d2
	bcs.s	fall_stop_x
	move.b	$1(a0,d3.w),d2
	cmpi.b	#TILE_OPEN,d2
	bcs.s	fall_stop_x
	addi.w	#MAP_ROW_LENGTH,d3
	move.b	$0(a0,d3.w),d2
	dbra	d7,fall_tile_loop
	add.w	d0,d4
	move.w	d4,player_x.w
	bra.s	fall_gravity

fall_stop_x:
	clr.w	fall_dx.w
fall_gravity:
	cmpi.w	#$10,d5
	bpl.s	fall_move_y
	addq.w	#1,d5
fall_move_y:
	move.w	d5,fall_dy.w
	asr.w	#2,d5
	add.w	d5,d1
	move.w	d1,player_y.w
	btst	#$f,d1
	beq.s	fall_check_floor
fall_exit:
	rts

fall_check_floor:
	bsr.w	map_tile_at
	cmpi.b	#TILE_OPEN,d2
	bcc.s	fall_check_floor_tile
	subq.w	#7,player_y.w
	movem.w	player_x.w,d0-d1
	bra.s	state_falling

fall_check_floor_tile:
	ifeq	BUILD_LEVEL-1
	subi.b	#TILE_FLOOR,d2
	cmpi.b	#FLOOR_LAND_END-TILE_FLOOR,d2
	else
	subi.b	#TILE_DEADLY,d2
	subq.w	#TILE_FLOOR-TILE_DEADLY,d2
	bcc.s	fall_floor_range
	addq.w	#3,d2
	move.w	#$70,fall_distance.w            ; tiles $ca-$cc: landing counts as a fall of $70, which costs a life
fall_floor_range:
	cmpi.b	#FLOOR_WALK_END-TILE_FLOOR,d2
	endc
fall_distance_patch:	; from: drop_down
	nop
	move.w	sr,d6
	add.w	fall_distance.w,d5
	move.w	d5,fall_distance.w
	cmpi.w	#$8,d5
	bcs.s	fall_restore_sr
	move.w	#$4e71,fall_distance_patch.w
fall_restore_sr:
	move.w	d6,sr
	bcc.s	fall_exit
	move.w	#$28,player_ref_y.w
	lea	knocked_frames.w,a0
	bsr.w	set_player_anim
	move.l	#state_landed,player_state_vec.w
	clr.w	fall_dy.w
	move.w	#$1,on_ground.w
	move.w	#$2,state_timer.w
	move.w	scroll_y.w,d0
	add.w	d1,d0
	andi.w	#$7,d0
	sub.w	d0,d1
	move.w	d1,player_y.w
landed_exit:	; from: state_landed
	rts


;----------------------------------------------------------------------
; Landed: a fall of $50 or more costs 90 energy and a life.
;----------------------------------------------------------------------
state_landed:	; from: start_fall
	subq.w	#1,state_timer.w
	bne.s	landed_exit
	tst.b	panel_flags
	bne.w	player_dies
	move.l	#player_input,player_state_vec.w
	lea	anim_idle.w,a0
	cmpi.w	#$50,fall_distance.w
	bmi.w	set_player_anim
	moveq	#90,d6
	bsr.w	player_damage
	move.b	#$4,panel_flags
	btst	#$7,game_flags
	bne.s	landed_dead_exit
	jmp	panel_lose_life

landed_dead_exit:
	rts


;----------------------------------------------------------------------
; Return in d2 the map tile at player relative position d0/d1 (map_tiles, MAP_ROW_LENGTH bytes a row).
;----------------------------------------------------------------------
map_tile_at:	; from: thug_walk_left, thug_walk_right, goon_walk_right, goon_walk_left, climb_down, climb_up, ...
	movem.w	scroll_x.w,d2-d3
	add.w	d0,d2
	addi.w	#$8,d2
	add.w	d1,d3
	lsr.w	#3,d2
	lsr.w	#3,d3
	mulu.w	#MAP_ROW_LENGTH,d3
	add.w	d2,d3
	lea	map_tiles,a0
	clr.w	d2
	move.b	$0(a0,d3.w),d2
	rts

rope_pattern_right:	; from: draw_player
	ror.l	#1,d6
	ror.l	#1,d5
	bcs.s	rope_right_exit
	move.w	d5,d0
	move.l	#$fffefffe,d5
	andi.l	#$10001,d6
	btst	#$0,d0
	beq.s	rope_right_exit
	move.l	#$3fff3fff,d5
	move.l	#$c000,d6
	addq.l	#8,a0
rope_right_exit:
	rts

rope_pattern_left:	; from: draw_player
	add.l	d6,d6
	rol.l	#1,d5
	bcs.s	rope_pattern_exit
	move.w	d5,d0
	move.l	#$7fff7fff,d5
	andi.l	#$80008000,d6
	btst	#$f,d0
	beq.s	rope_pattern_exit
	move.l	#$fffcfffc,d5
	moveq	#3,d6
	subq.l	#8,a0
rope_pattern_exit:
	rts


draw_player:	; from: level_begin, main_loop, state_knocked_wait
	move.w	rope_length.w,d2
	beq.w	draw_player_sprites
	movem.w	player_x.w,d0-d1
	subi.w	#$c,d1
	addq.w	#4,d0
	tst.w	player_frame_legs.w
	bmi.s	rope_mask
	addq.w	#7,d0
rope_mask:
	move.l	#$c000,d6
	moveq	#7,d2
	and.w	d0,d2
	eor.w	d2,d0
	beq.s	rope_setup
	ror.w	d2,d6
	ror.w	d2,d6
rope_setup:
	move.w	d6,d5
	swap	d5
	move.w	d6,d5
	not.l	d5
	lea	rope_pattern_right.w,a1
	movem.w	rope_end.w,d3-d4
	tst.w	d3
	bpl.s	rope_height
	neg.w	d3
	lea	rope_pattern_left.w,a1
rope_height:
	move.w	d4,d7
	cmp.w	d4,d1
	bcc.s	rope_draw_setup
	move.w	d1,d7
rope_draw_setup:
	add.w	d7,d7
	mulu.w	#$140,d1
	add.w	d0,d1
	movea.l	screen_back.w,a0
	adda.w	d1,a0
	move.w	d3,d2
	lsr.w	#1,d2
rope_draw_loop:
	movem.l	(a0),d0-d1
	and.l	d5,d0
	and.l	d5,d1
	or.l	d6,d0
	or.l	d6,d1
	movem.l	d0-d1,(a0)
	add.w	d3,d2
	cmp.w	d4,d2
	bcs.s	rope_next_row
	sub.w	d4,d2
	jsr	(a1)
rope_next_row:
	swap	d6
	lea	-$a0(a0),a0
	dbra	d7,rope_draw_loop
draw_player_sprites:
	movem.w	player_x.w,d0-d1
	move.w	player_frame_legs.w,d2
	clr.w	d4
	move.b	d2,d4
	beq.w	draw_player_exit
	move.w	d1,d3
	lea	sprite_heights.w,a0
	add.w	d4,d4
	add.w	d3,d3
	sub.b	-$2(a0,d4.w),d3
	asr.w	#1,d3
	move.w	d3,player_top_y.w
	bsr.w	draw_sprite
	movem.w	player_x.w,d0-d1
	move.w	player_frame_body.w,d2
	move.b	d2,d2
	beq.w	draw_player_exit
	bsr.w	draw_sprite
	movem.w	player_x.w,d0-d1
	move.w	player_frames.w,d2
	move.b	d2,d2
	beq.w	draw_player_exit
	bsr.w	draw_sprite
draw_player_exit:
	rts

type_sprite_table:	; from: spawn_enemy
	ifeq	BUILD_LEVEL-1
	dc.w	$0004,$005c,$0012,$003d,$0015,$006f,$0017,$0058
	dc.w	$0018,$803d,$001b,$0000,$001f,$0000,$00ff,$0000
	else
	dc.w	$0004,$005c,$0012,$0040,$0015,$0000,$0017,$0000
	dc.w	$0018,$0000,$001b,$0000,$001f,$006e,$0020,$006a
	dc.w	$0021,$0000,$00ff,$0000
	endc
enemy_type_table:	; from: update_enemies, goon_walk_left
	dc.w	player_idle
	dc.w	thug_fall
	dc.w	thug_walk_right
	dc.w	thug_walk_left
	dc.w	thug_shoot_left
	dc.w	thug_shoot_right
	dc.w	thug_pause_left
	dc.w	thug_pause_right
	dc.w	player_idle
	dc.w	player_idle
	dc.w	player_idle
	dc.w	player_idle
	dc.w	climb_up
	dc.w	climb_down
	dc.w	goon_walk_right
	dc.w	goon_walk_left
	dc.w	jack_wait
	dc.w	jack_shoot
	dc.w	jack_turn
	dc.w	$0000
	dc.w	faller
	dc.w	attacker_right
	dc.w	attacker_left
	dc.w	goon_walk_left
	dc.w	vat_watch
	dc.w	vat_splash
	dc.w	object_use_start
	dc.w	object_use_anim
	dc.w	$0000
	dc.w	crawler_right
	dc.w	crawler_left
	dc.w	boss_climb
	dc.w	boss_climb_watch
	dc.w	level_complete
	dc.w	checkpoint_1
	dc.w	checkpoint_2
	dc.w	checkpoint_3

checkpoint_1:	; from: enemy_type_table
	moveq	#1,d0
	cmp.w	checkpoint.w,d0
	bcs.s	checkpoint_done
	bra.s	checkpoint_set


checkpoint_2:	; from: enemy_type_table
	moveq	#2,d0                           ; never run on level 1: no level 1 object has type 35
	cmp.w	checkpoint.w,d0
	bcs.s	checkpoint_done
	bra.s	checkpoint_set


checkpoint_3:	; from: enemy_type_table
	moveq	#3,d0                           ; never run: neither level has an object of type 36
	cmp.w	checkpoint.w,d0
checkpoint_set:	; from: checkpoint_1, checkpoint_2
	move.w	d0,checkpoint.w
checkpoint_done:	; from: checkpoint_1, checkpoint_2
	clr.w	(a6)
	rts


;----------------------------------------------------------------------
; Enemy type 25: Jack's splash in the vat: two mirrored halves of sprite $30 drawn at x VAT_SPLASH_X, then the level ends.  Never run on level 5: only type 24 makes an object type 25.
;----------------------------------------------------------------------
vat_splash:	; from: enemy_type_table
	move.w	#VAT_SPLASH_X,d0
	sub.w	scroll_x.w,d0
	addq.w	#2,$a(a6)
	movea.l	$8(a6),a5
	move.w	(a5),d2
	bmi.s	vat_splash_done
	move.w	d2,-(sp)
	bsr.w	draw_enemy_frame
	move.w	(sp)+,d2
	addi.w	#$e000,d2
	bra.w	draw_enemy_frame

vat_splash_done:
	bsr.w	wait_vbl_flip
	moveq	#30,d0
	bsr.w	wait_frames
	bra.w	end_sequence

	dc.w	$0001,$0001,$0001,$0001,$0002,$0002,$0002,$0002
	dc.w	$0003,$0003,$0003,$0003,$0002,$0002,$0002,$0002
	dc.w	$0001,$0001,$0001,$0001,$ffff

;----------------------------------------------------------------------
; Enemy type 24: watches Jack Napier (sprite base $803d).  Knocked off (type 1), the music stops and the view follows his fall; at y VAT_DEPTH he is in the vat and becomes type 25, the splash.  Gone, his group can appear again.  Never run on level 5: no level 5 object has type 24.
;----------------------------------------------------------------------
vat_watch:	; from: enemy_type_table
	move.w	#$98,$4(a6)
	lea	enemies.w,a5
	move.w	#JACK_SPRITE,d2
	moveq	#9,d7
find_jack_loop:
	cmp.w	$6(a5),d2
	beq.s	jack_found
	lea	$16(a5),a5
	dbra	d7,find_jack_loop
	bra.s	jack_gone

jack_found:
	move.w	(a5),d2
	bne.s	jack_knocked_check
jack_gone:
	ifeq	BUILD_LEVEL-1
	bclr	#$7,spawn_table+732
	else
	bclr	#$7,spawn_table
	endc
	clr.w	(a6)
vat_watch_exit:
	rts

jack_knocked_check:
	subq.w	#1,d2
	bne.s	vat_watch_exit
	jsr	snd_stop_music
	bset	#$0,panel_flags
	move.w	#player_idle,player_state_lo.w
	clr.w	on_ground.w
	clr.w	rope_length.w
	move.w	$4(a5),d0
	cmpi.w	#VAT_DEPTH,d0
	bcs.s	jack_fall_follow
	move.w	#SPLASH_SPRITE,$6(a5)
	move.l	#vat_splash_done+12,$8(a5)
	move.w	#$19,(a5)
	clr.w	(a6)
	moveq	#7,d0
	jmp	play_sfx

jack_fall_follow:
	tst.w	player_y.w
	bpl.s	jack_fall_scroll_y
	moveq	#7,d1
	and.w	scroll_x.w,d1
	beq.s	jack_fall_scroll_y
	subq.w	#1,camera_x.w
jack_fall_scroll_y:
	subi.w	#$18,d0
	sub.w	scroll_y.w,d0
	neg.w	d0
	add.w	player_y.w,d0
	move.w	d0,player_ref_y.w
attack_exit_b:	; from: attacker_right, attacker_left
	rts


;----------------------------------------------------------------------
; Enemy types 21/22: attackers hitting the player when close (right / left).  Never run on level 5: no level 5 object has type 21 or 22.
;----------------------------------------------------------------------
attacker_right:	; from: enemy_type_table
	bsr.s	attack_frame
	cmpi.w	#$8,d2
	bcc.s	attack_exit_b
	addq.w	#1,d2
	asr.w	#1,d2
	bcs.w	draw_enemy_frame
	cmpi.w	#$2,d2
	bne.w	draw_enemy_frame
	bsr.s	attack_hit_right
	moveq	#2,d2
	bra.w	draw_enemy_frame


attacker_left:	; from: enemy_type_table
	bsr.s	attack_frame
	ori.w	#$c000,d2
	cmpi.w	#$c008,d2
	bcc.s	attack_exit_b
	addq.w	#1,d2
	asr.w	#1,d2
	bcs.w	draw_enemy_frame
	cmpi.w	#$e002,d2
	bne.w	draw_enemy_frame
	bsr.s	attack_hit_left
	move.w	#$e002,d2
	bra.w	draw_enemy_frame


attack_frame:	; from: attacker_right, attacker_left
	move.w	$8(a6),d2
	addq.b	#4,d2
	bcc.s	attack_store_frame
	moveq	#8,d2
	bsr.w	play_sfx_on_screen
	clr.w	d2
attack_store_frame:
	move.w	d2,$8(a6)
	cmpi.w	#$37,d2
	bcc.s	attack_exit
	lsr.w	#3,d2
	addq.w	#1,d2
attack_exit:	; from: attack_hit_right, faller
	rts


attack_hit_left:	; from: attacker_left
	movem.w	player_x.w,d3-d4
	addi.w	#$10,d3
	bra.s	attack_hit_test


attack_hit_right:	; from: attacker_right
	movem.w	player_x.w,d3-d4
	addq.w	#4,d3
attack_hit_test:	; from: attack_hit_left
	sub.w	d0,d3
	cmpi.w	#$16,d3
	bcc.s	attack_exit
	cmp.w	d1,d4
	bmi.s	attack_exit
	cmp.w	player_top_y.w,d1
	bmi.s	attack_exit
	moveq	#3,d6
	bra.w	player_damage


;----------------------------------------------------------------------
; Enemy type 20: something falling from above, lands and flips.  Never run on level 5: no level 5 object has type 20.
;----------------------------------------------------------------------
faller:	; from: enemy_type_table
	move.w	$c(a6),d3
	addq.b	#6,d3
	move.w	d3,$c(a6)
	cmpi.b	#$20,d3
	bcs.s	attack_exit
	moveq	#1,d2
	cmpi.b	#$40,d3
	bcs.w	draw_enemy_frame
	move.w	$a(a6),d5
	cmpi.w	#$10,d5
	bcc.w	faller_speed
	addq.w	#1,d5
faller_speed:
	move.w	d5,$a(a6)
	lsr.w	#1,d5
	add.w	$8(a6),d5
	move.w	d5,$8(a6)
	add.w	d5,d1
	bsr.w	map_tile_at
	cmpi.b	#TILE_FLOOR,d2
	bcs.s	faller_hit_player
	move.w	scroll_y.w,d3
	add.w	d1,d3
	andi.w	#$7,d3
	not.w	d3
	add.w	d3,d1
faller_land:
	moveq	#4,d2
	eor.w	d2,$2(a6)
	clr.l	$8(a6)
	clr.w	$c(a6)
	moveq	#6,d2
	bsr.w	play_sfx_on_screen
	moveq	#2,d2
	bra.w	draw_enemy_frame

faller_hit_player:
	moveq	#1,d2
	move.w	player_x.w,d3
	sub.w	d0,d3
	addq.w	#3,d3
	cmpi.w	#$7,d3
	bcc.w	draw_enemy_frame
	cmp.w	player_top_y.w,d1
	bmi.w	draw_enemy_frame
	cmp.w	player_y.w,d1
	bpl.w	draw_enemy_frame
	moveq	#4,d6
	bsr.w	player_damage
	bra.s	faller_land

boss_climb_exit:	; from: boss_climb, boss_climb_watch
	rts


;----------------------------------------------------------------------
; Enemy type 31: a boss climbing away, 2 units up every 4 frames; at the top he escapes and the player takes 90 damage.  Never run on level 1: no level 1 object has type 31.  Level 5 places it: the Joker on the rope ladder.
;----------------------------------------------------------------------
boss_climb:	; from: enemy_type_table
	move.w	$4(a6),d2
	not.w	d2
	andi.w	#$6,d2
	lsr.w	#1,d2
	bclr	#$1,d2
	beq.s	boss_climb_draw
	addi.w	#$e000,d2
boss_climb_draw:
	move.w	d2,-(sp)
	addq.w	#2,d2
	bsr.w	draw_enemy_frame
	move.w	(sp)+,d2
	andi.w	#$e000,d2
	addq.w	#1,d2
	bsr.w	draw_enemy
	moveq	#3,d2
	and.b	frame_toggle+1.w,d2
	bne.s	boss_climb_exit
	subq.w	#2,$4(a6)
	bmi.s	boss_escapes
	rts


;----------------------------------------------------------------------
; Enemy type 32: watches a climbing boss (sprite $6a), with sound 10 and a column of map tiles swinging (CLIMB_COLUMN_ROWS rows from map_climb_column); knocked off (type 1) completes the level, gone costs the player 90 damage.  Never run on level 1: no level 1 object has type 32.  Level 5 places it: the rope ladder.
;----------------------------------------------------------------------
boss_climb_watch:	; from: enemy_type_table
	btst	#$0,frame_toggle+1.w
	beq.s	climb_column_animate
	movem.l	d0-d1/a6,-(sp)
	moveq	#10,d0
	jsr	play_sfx
	movem.l	(sp)+,d0-d1/a6
climb_column_animate:
	move.w	frame_toggle.w,d2
	lsr.w	#2,d2
	andi.w	#$7,d2
	ifeq	CONFIG-RETAIL_2DISK
	move.w	#$6cc7,d2
	move.w	#$6bc6,d3
	endc
	ifne	CONFIG-RETAIL_2DISK
	move.w	#$6bc6,d3
	move.w	#$6ac5,d2
	endc
	moveq	#CLIMB_COLUMN_ROWS-1,d7
	lea	map_climb_column.w,a0
	btst	#$3,frame_toggle+1.w
	beq.s	climb_column_row_loop
	exg	d2,d3
climb_column_row_loop:
	move.w	d2,(a0)
	exg	d2,d3
	lea	MAP_ROW_LENGTH(a0),a0
	dbra	d7,climb_column_row_loop
	lea	enemies.w,a5
	move.w	#CLIMB_SPRITE,d2
	moveq	#9,d7
find_climbing_boss:
	cmp.w	$6(a5),d2
	beq.s	climbing_boss_check
	lea	$16(a5),a5
	dbra	d7,find_climbing_boss
boss_escapes:	; from: boss_climb
	moveq	#90,d6
	bra.w	player_damage

climbing_boss_check:
	move.w	(a5),d2
	beq.s	boss_escapes
	subq.w	#1,d2
	bne.w	boss_climb_exit
	move.w	#player_idle,player_state_lo.w
	move.w	#$21,(a5)
	clr.w	rope_length.w
	move.w	#$ffff,on_ground.w
	move.b	#$1,panel_flags
	rts


;----------------------------------------------------------------------
; Enemy type 33, level complete: the knocked-off boss falls while the view pans after him until scroll_x reaches ENDING_SCROLL_X; landed, the level ends (end_sequence).  Never run on level 1: only type 32 makes an object type 33.  Level 5: the Joker, knocked off the rope ladder.
;----------------------------------------------------------------------
level_complete:	; from: enemy_type_table
	move.w	scroll_x.w,d2
	cmpi.w	#ENDING_SCROLL_X,d2
	bcc.s	complete_boss_fall
	tst.w	player_y.w
	bmi.s	complete_scroll_follow
	tst.w	player_x.w
	bmi.s	complete_scroll_follow
	addq.w	#6,$2(a6)
	subq.w	#8,camera_x.w
	bra.s	complete_boss_fall

complete_scroll_follow:
	addq.w	#2,$2(a6)
	moveq	#104,d2
	sub.w	d0,d2
	cmpi.w	#$fffd,d2
	bcc.s	complete_scroll_store
	moveq	#-2,d2
complete_scroll_store:
	add.w	d2,camera_x.w
complete_boss_fall:
	cmpi.w	#$48,d1
	bcc.s	complete_boss_landed
	move.w	$a(a6),d3
	cmpi.w	#$e,d3
	bpl.s	complete_boss_move
	addq.w	#1,d3
	move.w	d3,$a(a6)
complete_boss_move:
	asr.w	#1,d3
	add.w	d3,$4(a6)
	moveq	#24,d2
	sub.w	d1,d2
	add.w	player_y.w,d2
	move.w	d2,player_ref_y.w
	moveq	#4,d2
	bsr.w	draw_enemy_frame
	jsr	snd_stop
	move.l	#$210,d0
	jmp	panel_add_score

complete_boss_landed:
	moveq	#72,d1
	andi.w	#$f8,d0
	moveq	#LANDED_SPRITE,d2
	bsr.w	draw_sprite
	bsr.w	wait_vbl_flip
	ifeq	BUILD_LEVEL-5
set_complete_flag:	; from: main_loop
	endc
	bset	#$6,game_flags
end_sequence:	; from: main_loop, vat_splash
	jsr	snd_stop
	btst	#$2,panel_flags
	beq.s	end_no_life
	jsr	panel_add_life
end_no_life:
	move.b	game_flags,saved_game_flags.w
	bclr	#$0,game_flags
	jsr	snd_stop
	moveq	#9,d0
	jsr	play_tune
	move.w	#$fa,d0
	bsr.s	wait_frames
	move.b	saved_game_flags.w,game_flags
	bsr.w	clear_back_screen
	ifeq	BUILD_LEVEL-1
	lea	jack_dead_text.w,a0
	else
	lea	end_text.w,a0
	endc
	bsr.w	print_text
	bsr.w	dissolve_in
	moveq	#100,d0
	bsr.w	wait_frames
	bsr.w	clear_back_screen
	ifeq	BUILD_LEVEL-1
	lea	joker_lives_text.w,a0
	else
	lea	end_blank_text.w,a0
	endc
	bsr.w	print_text
	bsr.w	dissolve_in
	moveq	#100,d0
	bsr.w	wait_frames
	bsr.w	clear_and_dissolve
	bsr.w	fade_out
	bra.w	NEXT_SCENE


wait_frames:	; from: state_dying, vat_splash, level_complete
	add.w	flip_request.w,d0
wait_frames_loop:
	cmp.w	flip_request.w,d0
	bpl.s	wait_frames_loop
	rts


player_at_object:	; from: object_use_start, object_use_anim
	movem.w	player_x.w,d2-d3
	sub.w	d1,d3
	cmpi.w	#$1,d3
	bcc.s	at_object_exit
	sub.w	d0,d2
	cmpi.w	#$20,d2
	bcc.s	at_object_exit
	move.b	player_frame_legs+1.w,d2
	cmpi.b	#$24,d2
at_object_exit:	; from: object_use_start, object_use_anim
	rts


;----------------------------------------------------------------------
; Enemy types 26/27: an object the player uses (crouch in front of it): tiles are swapped
; with an animation from use_anim_tiles.  Never run on level 1: no level 1 object has type 26.
;----------------------------------------------------------------------
object_use_start:	; from: enemy_type_table
	bsr.s	player_at_object
	bcc.s	at_object_exit
	addq.w	#1,(a6)
	move.w	#$19,$8(a6)
	subq.w	#8,d0
	bsr.w	map_tile_at
	move.w	d3,$a(a6)
	move.w	use_toggle.w,d4
	move.w	d4,$6(a6)
	lea	use_tile_buffer.w,a5
	adda.w	d4,a5
	eori.w	#$6,d4
	move.w	d4,use_toggle.w
	moveq	#0,d4
	cmpi.b	#TILE_OPEN,d2
	bcs.s	use_tile_above
	moveq	#3,d4
	cmpi.b	#TILE_FLOOR,d2
	bcs.s	use_tile_above
	moveq	#94,d4
use_tile_above:
	move.b	d4,(a5)
	move.w	$5(a0,d3.w),d4
	moveq	#0,d5
	cmpi.b	#TILE_OPEN,d4
	bcs.s	use_tile_below
	moveq	#9,d5
	cmpi.b	#TILE_FLOOR,d4
	bcs.s	use_tile_below
	moveq	#94,d5
use_tile_below:
	move.b	d5,$5(a5)
	lea	$0,a1
	lsl.w	#8,d2
	move.b	$1(a0,d3.w),d2
	move.b	$2(a0,d3.w),d4
	lsl.w	#8,d4
	move.b	$3(a0,d3.w),d4
	move.b	$4(a0,d3.w),d5
	movea.l	object_stack.w,a5
	movem.w	d2-d5,-(a5)
	move.l	a5,object_stack.w
	adda.w	d3,a0
	move.w	#TILE_FLOOR,d6
	tst.w	$6(a6)
	beq.s	use_replace_tiles
	addq.w	#5,d6
use_replace_tiles:
	moveq	#4,d7
use_replace_loop:
	clr.w	d0
	move.b	(a0),d0
	bsr.w	tile_cache_get
	movem.l	d6-d7/a0,-(sp)
	move.w	d6,d0
	bsr.w	tile_cache_free
	movem.l	(sp)+,d6-d7/a0
	move.b	d6,(a0)+
	addq.w	#1,d6
	dbra	d7,use_replace_loop

object_use_anim:	; from: enemy_type_table
	lea	use_tile_buffer.w,a5
	adda.w	$6(a6),a5
	move.w	#$18,player_ref_y.w
	subq.w	#1,$8(a6)
	beq.w	object_use_end
	move.w	$8(a6),d2
	moveq	#3,d3
	and.w	d2,d3
	bne.w	at_object_exit
	move.l	use_anim_tiles(pc,d2.l),d2
	lea	$1(a5),a2
	move.l	d2,(a2)
	subq.w	#1,a2
	lea	TILE_TABLE,a1
	move.w	$a(a6),d3
	lea	map_tiles.w,a0
	clr.w	d0
	move.b	$0(a0,d3.l),d0
	adda.w	d0,a1
	adda.w	d0,a1
	moveq	#4,d7
use_copy_tiles_loop:
	move.b	(a2)+,(a1)+
	move.b	(a2),(a1)+
	dbra	d7,use_copy_tiles_loop
	moveq	#4,d7
use_refresh_loop:
	lea	TILE_REFS,a2
	tst.b	$0(a2,d0.l)
	bmi.s	use_refresh_next
	movem.w	d0/d7,-(sp)
	bsr.w	tile_cache_get
	move.w	(sp),d0
	bsr.w	tile_cache_free
	movem.w	(sp)+,d0/d7
use_refresh_next:
	addq.w	#1,d0
	dbra	d7,use_refresh_loop
	rts

	dc.b	$00
use_tile_buffer:	; from: object_use_start, object_use_anim
	ifeq	BUILD_LEVEL-1
	dc.b	$00,$53,$53,$53,$53,$09,$00,$53,$53,$53,$53,$09,$04
	else
	dc.b	$00,$53,$53,$53,$53,$09,$00,$53,$53,$53,$53,$09,$00
	endc
use_toggle:	; from: object_use_start
	dc.w	$0000
use_anim_tiles:	; from: object_use_anim
	dc.b	'OOOOTOOOSTOTRSTSQRSR^QRQ^^Q^'
object_use_end:
	movem.w	d0-d1,-(sp)
	lea	map_tiles.w,a0
	move.w	$a(a6),d3
	clr.w	d0
	move.b	$0(a0,d3.w),d0
	moveq	#4,d7
	lea	TILE_REFS,a2
end_get_loop:
	tst.b	$0(a2,d0.w)
	bmi.s	end_get_next
	move.w	d0,-(sp)
	bsr.w	tile_cache_get
	move.w	(sp)+,d0
end_get_next:
	addq.w	#1,d0
	dbra	d7,end_get_loop
	lea	map_tiles.w,a0
	move.w	$a(a6),d3
	move.b	-$1(a0,d3.w),d1
	moveq	#6,d0
	cmpi.b	#TILE_OPEN,d1
	bcs.s	end_tile_store
	moveq	#47,d0
	cmpi.b	#TILE_FLOOR,d1
	bcs.s	end_tile_store
	move.w	#$f1,d0
end_tile_store:
	move.w	d0,-(sp)
	move.b	d0,$0(a0,d3.w)
	move.b	#$c8,$1(a0,d3.w)
	move.b	#$c8,$2(a0,d3.w)
	move.b	#$c8,$3(a0,d3.w)
	move.b	$5(a0,d3.w),d1
	move.w	#$c7,d0
	cmpi.b	#TILE_FLOOR,d1
	bcs.s	end_tile_below
	addq.b	#2,d0
end_tile_below:
	move.b	d0,$4(a0,d3.w)
	bsr.w	tile_cache_free
	move.w	#$c8,d0
	bsr.w	tile_cache_free
	move.w	#$c8,d0
	bsr.w	tile_cache_free
	move.w	#$c8,d0
	bsr.w	tile_cache_free
	move.w	(sp)+,d0
	bsr.w	tile_cache_free
	clr.w	(a6)
	movem.w	(sp)+,d0-d1
	bsr.w	player_at_object
	bcc.s	use_end_exit
	move.w	#drop_down,player_state_lo.w
	clr.w	rope_length.w
use_end_exit:
	rts

object_stack:	; from: level_begin, object_use_start
	dc.l	object_stack+$60
	dcb.b	108,$00

;----------------------------------------------------------------------
; Enemy types 29/30: crawlers moving right / left along the floor.  Never run on level 1: no level 1 object has type 29 or 30.
;----------------------------------------------------------------------
crawler_right:	; from: enemy_type_table
	cmpi.w	#$c0,d0
	bpl.s	crawler_right_turn
	andi.w	#$7,d4
	bne.s	crawler_right_move
	addq.w	#8,d0
	bsr.w	map_tile_at
	subq.w	#8,d0
	cmpi.b	#TILE_FLOOR,d2
	bcs.s	crawler_right_turn
crawler_right_move:
	addq.w	#1,$2(a6)
	subq.w	#1,$8(a6)
	bpl.s	crawler_right_draw
	movem.w	player_x.w,d2-d3
	sub.w	d0,d2
	cmpi.w	#$8,d2
	bcc.s	crawler_right_draw
	sub.w	d1,d3
	cmpi.w	#$13,d3
	bcc.s	crawler_right_draw
	move.w	#$19,$8(a6)
	moveq	#2,d6
	bsr.w	player_damage
crawler_right_turn:
	move.w	#$1e,(a6)
crawler_right_draw:
	ifeq	BUILD_LEVEL-1
	move.w	d4,d2
	else
	ifeq	CONFIG-RETAIL_2DISK
	move.w	d4,d2                           ; bug: crawlers show the wrong frame: d4 is x & 7 before the move
	endc
	ifne	CONFIG-RETAIL_2DISK
	moveq	#7,d2
	and.w	$2(a6),d2
	endc
	endc
	lsr.w	#1,d2
	addq.w	#1,d2
	bra.w	draw_enemy_frame


crawler_left:	; from: enemy_type_table
	cmpi.w	#$ffc0,d0
	bmi.s	crawler_left_turn
	andi.w	#$7,d4
	bne.s	crawler_left_move
	subi.w	#$10,d0
	bsr.w	map_tile_at
	addi.w	#$10,d0
	cmpi.b	#TILE_FLOOR,d2
	bcs.s	crawler_left_turn
crawler_left_move:
	subq.w	#1,$2(a6)
	subq.w	#1,$8(a6)
	bpl.s	crawler_left_draw
	movem.w	player_x.w,d2-d3
	sub.w	d0,d2
	addi.w	#$a,d2
	bcc.s	crawler_left_draw
	sub.w	d1,d3
	cmpi.w	#$13,d3
	bcc.s	crawler_left_draw
	move.w	#$19,$8(a6)
	moveq	#2,d6
	bsr.w	player_damage
crawler_left_turn:
	move.w	#$1d,(a6)
crawler_left_draw:
	ifeq	BUILD_LEVEL-1
	move.w	#$e003,d2
	lsr.w	#1,d4
	eor.w	d4,d2
	else
	ifeq	CONFIG-RETAIL_2DISK
	move.w	#$e003,d2                       ; bug: crawlers show the wrong frame, taken from d4
	lsr.w	#1,d4                           ; as the movement left it, not from the x position
	eor.w	d4,d2
	endc
	ifne	CONFIG-RETAIL_2DISK
	moveq	#7,d2
	and.w	$2(a6),d2
	lsr.w	#1,d2
	eori.w	#$e003,d2
	endc
	endc
	addq.w	#1,d2
	bra.w	draw_enemy_frame

thug_fall_frames:	; from: thug_fall
	dc.w	$0001,$0002,$0003,$0004,$0005,$0007
player_frames:	; from: walk_right, walk_left, state_ladder, draw_player
	dc.w	$0005
player_frame_body:	; from: draw_player
	dc.w	$0002
player_frame_legs:	; from: level_begin, rope_hook, throw_batarang, fire_rope_right, fire_rope_left, fire_rope_up, ...
	dc.w	$0001
player_top_y:	; from: update_enemies, aim_shot, goon_walk_left, jack_start, bullet_move, grenade_right, ...
	dc.w	$0000
state_timer:	; from: player_knockback, state_rope_swing, throw_batarang, start_fall, state_landed
	dc.w	$0000
throw_cooldown:	; from: main_loop, throw_batarang
	dc.w	$0000
fall_dx:	; from: update_enemies, state_rope_swing, start_fall
	dc.w	$0000
fall_dy:	; from: state_rope_swing, start_fall
	dc.w	$0000
fall_distance:	; from: start_fall, state_landed
	dc.w	$0000
on_ground:	; from: update_enemies, update_scroll, start_fall, vat_watch, boss_climb_watch
	dc.w	$0001
checkpoint:	; from: level_begin, checkpoint_1, checkpoint_2, checkpoint_3
	dc.w	$0000,$0001,$0000,$0000,$0000
knock_timer:	; from: player_knockback, state_knocked, state_knocked_wait, state_rope_hit
	dc.w	$0000
joy_state:	; from: read_joystick, player_input, state_rope_hit, state_rope_swing, throw_batarang, fire_rope_up, ...
	dc.b	$00
fire_latch:	; from: read_joystick
	dc.b	$00
scroll_dx:	; from: jack_shoot, update_bullets, update_scroll, state_rope_swing, start_fall
	dc.w	$0000
scroll_dy:	; from: jack_shoot, update_bullets, update_scroll
	dc.w	$0000,$0000
rope_angle:	; from: state_rope_swing, fire_rope_up, state_rope_retract
	dc.w	$0000,$0000
rope_length:	; from: level_begin, update_enemies, rope_hook, state_knocked_wait, state_rope_hit, state_rope_swing, ...
	dc.w	$0000
rope_end:	; from: rope_hook, state_rope_swing, fire_rope_up, draw_player
	dc.w	$0000,$0034,$0000,$0000
	ifeq	BUILD_LEVEL-1
dat_06302:	; from: spawn_enemy
	else
dat_0633e:	; from: spawn_enemy
	endc
	dc.l	spawn_enemies
anim_script:	; from: state_knocked_wait, state_dying, state_rope_swing, throw_batarang
	dc.w	$0000
rope_anchor:	; from: state_rope_swing, fire_rope_up
	dc.w	$0000,$0000
frame_toggle:	; from: wait_vbl_flip, state_rope_swing, boss_climb_watch
	dc.w	$0000,$2221,$201f,$1e1d,$1c1b,$1a19,$1817,$1615
	dc.w	$1413,$1211,$100f,$0e0d,$0c0b,$0a09,$0807,$0605
	dc.w	$0403,$0201,$0003,$0609,$0d10,$1316,$191c
	dc.b	$1f
	dc.b	'"%),/258;>ADGJMPSVY\_bdgjmpsux{~'
	dc.b	$80,$83,$86,$88,$8b,$8e,$90,$93,$95,$98,$9a,$9d,$9f,$a2,$a4,$a7
	dc.b	$a9,$ab,$ae,$b0,$b2,$b4,$b7,$b9,$bb,$bd,$bf,$c1,$c3,$c5,$c7,$c9
	dc.b	$cb,$cd,$cf,$d0,$d2,$d4,$d6,$d7,$d9,$db,$dc,$de,$df,$e1,$e2,$e4
	dc.b	$e5,$e7,$e8,$e9,$ea,$ec,$ed,$ee,$ef,$f0,$f1,$f2,$f3,$f4,$f5,$f6
	dc.b	$f7,$f7,$f8,$f9,$f9,$fa,$fb,$fb,$fc,$fc,$fd,$fd,$fd,$fe,$fe,$fe
	dc.b	$ff,$ff,$ff,$ff,$ff
anim_rope_launch:	; from: fire_rope_up
	dc.w	$30d2
	dc.b	$04
anim_idle:	; from: level_begin, throw_batarang, state_rope_retract, set_idle_anim, state_landed
	dc.b	$01,$02,$07
anim_crouch:	; from: crouch
	dc.w	$1901
	dc.b	$e6
anim_crouched:	; from: crouch
	dc.b	$1f,$e1,$00,$19,$01,$e6,$19,$01,$e6,$19,$01,$e6,$1b,$01,$e4,$1b
	dc.b	$01,$e4,$1b,$01,$e4,$1b,$01,$e4,$1b,$01,$e4,$1b,$01,$e4,$1b,$01
	dc.b	$e4,$1b,$01,$e4,$1d,$e3,$00,$1d,$e3,$00,$1d,$e3,$00,$1d,$e3,$00
	dc.b	$1d,$e3,$00,$1d,$e3,$00,$1d,$e3,$00,$1d,$e3,$00,$00
anim_rope_hang:	; from: fire_rope_up
	dc.w	$2401,$0127,$0101,$2a01,$fe2c,$fdd7,$2d01,$0100
	ifeq	BUILD_LEVEL-1
	dc.w	$1301,$0116,$0101,$00e4
	else
	dc.w	$1301,$0116,$0101,$0000
	endc

;----------------------------------------------------------------------
; The bad guys and other objects of the level, and where the player starts.  The code
; finds each table's end by the label after it, so a table can grow or shrink; keep
; spawn_table, spawn_singles and checkpoint_starts in this order, with scroll_x to
; camera_x straight after them, as a start copies its 7 words there.
;
; Positions are map positions in 2 pixel units: 8 units make one 16 pixel map cell.
;
; spawn_table: groups.  A group is its trigger x and y, the number of objects, then each
;   object's type, x and y.  The whole group appears when the trigger point comes into view.
; spawn_singles: single objects, type, x and y, each appearing when it comes into view.
;   The game marks what has appeared in the top bit of a group's trigger x and of a single's
;   y, and clears the marks at the level's start and at each restart; keep them clear here.
; checkpoint_starts: where the player starts, then where a restart puts the player after
;   each checkpoint: scroll_x, scroll_y, score_scroll_x, player_x, player_y, player_ref_y
;   and camera_x.
;
; An object's type picks its routine in enemy_type_table.
;----------------------------------------------------------------------
	ifeq	BUILD_LEVEL-1
spawn_table:	; from: level_begin, spawn_enemies
	dc.w	$02c1,$0081,$0001	; group: trigger x, y, 1 object
	dc.w	$0022,$0240,$00c0	;   checkpoint_1
	dc.w	$0040,$00f0,$0002	; group: trigger x, y, 2 objects
	dc.w	$0003,$00c0,$0118	;   thug_walk_left
	dc.w	$000f,$00a0,$0118	;   goon_walk_left
	dc.w	$0040,$00e2,$0001	; group: trigger x, y, 1 object
	dc.w	$0002,$0008,$00d8	;   thug_walk_right
	dc.w	$00a8,$00f0,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0010,$0118	;   goon_walk_right
	dc.w	$000f,$00c8,$0118	;   goon_walk_left
	dc.w	$000f,$00c8,$0138	;   goon_walk_left
	dc.w	$00e0,$00f0,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$00f0,$00d8	;   goon_walk_left
	dc.w	$00e0,$00a7,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0080,$0098	;   thug_walk_left
	dc.w	$0038,$0078,$0001	; group: trigger x, y, 1 object
	dc.w	$000e,$0008,$0098	;   goon_walk_right
	dc.w	$0024,$0078,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$00c8,$0098	;   goon_walk_left
	dc.w	$0040,$001f,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$00b0,$0018	;   thug_walk_left
	dc.w	$00a8,$0010,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0008,$0018	;   goon_walk_right
	dc.w	$000f,$00d0,$0018	;   goon_walk_left
	dc.w	$000f,$00d0,$0038	;   goon_walk_left
	dc.w	$00d8,$0040,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0008,$0018	;   goon_walk_right
	dc.w	$000f,$00f0,$0018	;   goon_walk_left
	dc.w	$000f,$00f0,$0058	;   goon_walk_left
	dc.w	$0128,$0040,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$0140,$0078	;   goon_walk_right
	dc.w	$000e,$0088,$0018	;   goon_walk_right
	dc.w	$0178,$0040,$0002	; group: trigger x, y, 2 objects
	dc.w	$0003,$0190,$0038	;   thug_walk_left
	dc.w	$000f,$01b0,$0018	;   goon_walk_left
	dc.w	$01bc,$0011,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$01d0,$0018	;   goon_walk_left
	dc.w	$000f,$01b0,$0078	;   goon_walk_left
	dc.w	$0168,$00b0,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0160,$00f8	;   goon_walk_left
	dc.w	$0003,$0150,$0118	;   thug_walk_left
	dc.w	$0190,$0111,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$0138,$0138	;   goon_walk_right
	dc.w	$000f,$0178,$0138	;   goon_walk_left
	dc.w	$01e8,$0100,$0004	; group: trigger x, y, 4 objects
	dc.w	$000f,$0150,$0118	;   goon_walk_left
	dc.w	$000f,$0140,$0138	;   goon_walk_left
	dc.w	$000e,$0200,$0138	;   goon_walk_right
	dc.w	$0003,$0220,$0118	;   thug_walk_left
	dc.w	$0220,$00ef,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0188,$00b8	;   goon_walk_left
	dc.w	$000f,$0200,$00d8	;   goon_walk_left
	dc.w	$0240,$003b,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$0250,$0038	;   goon_walk_left
	dc.w	$0280,$007b,$0001	; group: trigger x, y, 1 object
	dc.w	$000e,$0250,$0098	;   goon_walk_right
	dc.w	$02b0,$0071,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$02d0,$00b8	;   goon_walk_left
	dc.w	$02f0,$0071,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$0258,$0098	;   goon_walk_right
	dc.w	$000f,$0300,$0078	;   goon_walk_left
	dc.w	$02e0,$00c2,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0250,$00d8	;   goon_walk_right
	dc.w	$000f,$0250,$00f8	;   goon_walk_left
	dc.w	$000f,$0300,$00d8	;   goon_walk_left
	dc.w	$025c,$00cf,$0003	; group: trigger x, y, 3 objects
	dc.w	$000f,$0300,$00d8	;   goon_walk_left
	dc.w	$000f,$02e8,$0118	;   goon_walk_left
	dc.w	$000f,$0230,$00d8	;   goon_walk_left
	dc.w	$02f8,$0120,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0250,$0118	;   goon_walk_right
	dc.w	$000e,$0250,$0138	;   goon_walk_right
	dc.w	$000f,$0320,$0138	;   goon_walk_left
	dc.w	$0318,$0120,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0340,$0138	;   goon_walk_right
	dc.w	$0003,$0260,$0118	;   thug_walk_left
	dc.w	$000f,$0260,$0138	;   goon_walk_left
	dc.w	$0360,$0118,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0378,$00f8	;   goon_walk_left
	dc.w	$000f,$0378,$0118	;   goon_walk_left
	dc.w	$02f0,$0048,$0003	; group: trigger x, y, 3 objects
	dc.w	$000f,$0288,$0038	;   goon_walk_left
	dc.w	$000e,$0310,$0038	;   goon_walk_right
	dc.w	$000f,$0288,$0018	;   goon_walk_left
	dc.w	$0360,$0038,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0370,$0018	;   thug_walk_left
	dc.w	$03b0,$00b0,$0002	; group: trigger x, y, 2 objects
	dc.w	$0003,$03c0,$00b8	;   thug_walk_left
	dc.w	$000f,$03e0,$00d8	;   goon_walk_left
	dc.w	$03f0,$0102,$0001	; group: trigger x, y, 1 object
	dc.w	$000e,$03c0,$0138	;   goon_walk_right
	dc.w	$0450,$00f2,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$03b8,$0138	;   goon_walk_right
	dc.w	$000f,$0460,$0138	;   goon_walk_left
	dc.w	$0003,$0470,$00f8	;   thug_walk_left
	dc.w	$0468,$00c6,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0470,$00b8	;   thug_walk_left
	dc.w	$0468,$00a6,$0001	; group: trigger x, y, 1 object
	dc.w	$000e,$0400,$0078	;   goon_walk_right
	dc.w	$03a0,$0050,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$0440,$0098	;   goon_walk_left
	dc.w	$03d0,$0020,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$0420,$0018	;   goon_walk_left
	dc.w	$0430,$0001,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0450,$0018	;   goon_walk_left
	dc.w	$000f,$0440,$0038	;   goon_walk_left
	dc.w	$0480,$0012,$0002	; group: trigger x, y, 2 objects
	dc.w	$0003,$0490,$0058	;   thug_walk_left
	dc.w	$000e,$03e0,$0018	;   goon_walk_right
	dc.w	$04b8,$0093,$0001	; group: trigger x, y, 1 object
	dc.w	$0002,$04a4,$00b8	;   thug_walk_right
	dc.w	$04d8,$0110,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$04a4,$0138	;   goon_walk_right
	dc.w	$000f,$0500,$0118	;   goon_walk_left
	dc.w	$0530,$00f0,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0580,$00f0	;   thug_walk_left
	dc.w	$05b0,$00c8,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0540,$00b8	;   goon_walk_left
	dc.w	$000f,$0580,$00b8	;   goon_walk_left
	dc.w	$0580,$0090,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$0568,$0078	;   goon_walk_right
	dc.w	$000f,$0568,$0078	;   goon_walk_left
	dc.w	$0574,$0030,$0003	; group: trigger x, y, 3 objects
	dc.w	$0018,$0520,$0018	;   vat_watch
	dc.w	$0017,$05a0,$0018	;   goon_walk_left
	dc.w	$0002,$0530,$0018	;   thug_walk_right
spawn_singles:
	dc.w	$0014,$0118,$0038	; faller
	dc.w	$0015,$00c8,$0028	; attacker_right
	dc.w	$0014,$0070,$0068	; faller
	dc.w	$0014,$01b0,$0110	; faller
	dc.w	$0014,$01f0,$0038	; faller
	dc.w	$0015,$01ef,$0078	; attacker_right
	dc.w	$0015,$0217,$0028	; attacker_right
	dc.w	$0014,$0270,$0060	; faller
	dc.w	$0016,$0298,$0090	; attacker_left
	dc.w	$0014,$0310,$0120	; faller
	dc.w	$0016,$0372,$0038	; attacker_left
	dc.w	$0014,$0378,$0098	; faller
	dc.w	$0014,$0398,$0090	; faller
	dc.w	$0015,$0400,$0130	; attacker_right
	dc.w	$0014,$0458,$0078	; faller
	dc.w	$0016,$04ec,$0044	; attacker_left
	dc.w	$0014,$03d0,$0030	; faller
	dc.w	$0014,$03e0,$0030	; faller
	dc.w	$0014,$0510,$0100	; faller
	dc.w	$0014,$0570,$00d8	; faller
	dc.w	$0014,$0580,$0108	; faller
checkpoint_starts:	; from: level_begin
	dc.w	$0020,$00f8,$0020,$0048,$0048,$0048,$0048	; start
	dc.w	$0258,$0008,$0258,$0048,$0038,$0038,$0048	; after checkpoint 1
	else
spawn_table:	; from: level_begin, spawn_enemies, vat_watch
	dc.w	$0050,$041e,$0001	; group: trigger x, y, 1 object
	dc.w	$0022,$0080,$0400	;   checkpoint_1
	dc.w	$0190,$0260,$0001	; group: trigger x, y, 1 object
	dc.w	$0023,$0160,$0260	;   checkpoint_2
	dc.w	$0040,$0610,$0003	; group: trigger x, y, 3 objects
	dc.w	$0003,$00a8,$0628	;   thug_walk_left
	dc.w	$000f,$00a8,$0648	;   goon_walk_left
	dc.w	$000f,$00b8,$0648	;   goon_walk_left
	dc.w	$0080,$05f0,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0040,$05e8	;   goon_walk_right
	dc.w	$000f,$00c0,$05e8	;   goon_walk_left
	dc.w	$000f,$00c0,$05a8	;   goon_walk_left
	dc.w	$00e0,$0580,$0002	; group: trigger x, y, 2 objects
	dc.w	$0002,$0040,$05a8	;   thug_walk_right
	dc.w	$0003,$00f0,$05a8	;   thug_walk_left
	dc.w	$0130,$05d2,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$0128,$05e8	;   goon_walk_right
	dc.w	$0002,$00a4,$05a8	;   thug_walk_right
	dc.w	$0130,$0612,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$0140,$0648	;   goon_walk_left
	dc.w	$01a6,$0640,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$01c0,$0648	;   goon_walk_left
	dc.w	$000e,$0100,$0648	;   goon_walk_right
	dc.w	$0144,$0580,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$00a2,$05a8	;   goon_walk_right
	dc.w	$000f,$00a0,$05a8	;   goon_walk_left
	dc.w	$01fa,$0640,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0160,$0628	;   goon_walk_right
	dc.w	$000f,$0208,$0628	;   goon_walk_left
	dc.w	$0002,$0240,$0648	;   thug_walk_right
	dc.w	$0220,$0600,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0240,$05e8	;   goon_walk_left
	dc.w	$0003,$0260,$0648	;   thug_walk_left
	dc.w	$02b0,$057a,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$0230,$05e8	;   goon_walk_left
	dc.w	$0070,$04f0,$0001	; group: trigger x, y, 1 object
	dc.w	$0002,$0110,$0548	;   thug_walk_right
	dc.w	$0050,$04ce,$0003	; group: trigger x, y, 3 objects
	dc.w	$000f,$0110,$04e8	;   goon_walk_left
	dc.w	$000f,$0108,$04e8	;   goon_walk_left
	dc.w	$000f,$0118,$04e8	;   goon_walk_left
	dc.w	$0150,$04ce,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0160,$04e8	;   goon_walk_left
	dc.w	$000f,$0060,$04e8	;   goon_walk_left
	dc.w	$0180,$04ff,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$019f,$0528	;   thug_walk_left
	dc.w	$01a0,$0500,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$01d0,$0548	;   thug_walk_left
	dc.w	$01f8,$0530,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$0150,$0528	;   goon_walk_right
	dc.w	$0002,$0150,$0548	;   thug_walk_right
	dc.w	$01a0,$05c5,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$01b8,$05e8	;   goon_walk_left
	dc.w	$01e0,$0583,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0200,$05a8	;   thug_walk_left
	dc.w	$0201,$0580,$0003	; group: trigger x, y, 3 objects
	dc.w	$000f,$0220,$05a8	;   goon_walk_left
	dc.w	$000f,$022c,$05a8	;   goon_walk_left
	dc.w	$000f,$0238,$05a8	;   goon_walk_left
	dc.w	$0218,$0570,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0240,$0568	;   goon_walk_left
	dc.w	$000f,$0260,$05a8	;   goon_walk_left
	dc.w	$0218,$0549,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0230,$0548	;   goon_walk_left
	dc.w	$000f,$0210,$0528	;   goon_walk_left
	dc.w	$0240,$051f,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$01f8,$0508	;   goon_walk_left
	dc.w	$000f,$01e0,$0508	;   goon_walk_left
	dc.w	$0240,$04f0,$0003	; group: trigger x, y, 3 objects
	dc.w	$000f,$0250,$04e8	;   goon_walk_left
	dc.w	$000f,$0238,$04e8	;   goon_walk_left
	dc.w	$000f,$0220,$04e8	;   goon_walk_left
	dc.w	$01ab,$04a0,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0258,$04e8	;   thug_walk_left
	dc.w	$0130,$0440,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0148,$04a8	;   goon_walk_left
	dc.w	$000e,$01a0,$04a8	;   goon_walk_right
	dc.w	$00e0,$0468,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$00d0,$0468	;   goon_walk_left
	dc.w	$000e,$0068,$04a8	;   goon_walk_right
	dc.w	$0088,$0481,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0068,$04a8	;   goon_walk_left
	dc.w	$000f,$0088,$0468	;   goon_walk_left
	dc.w	$0080,$03c0,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0120,$0408	;   thug_walk_left
	dc.w	$0159,$03e0,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0188,$03e8	;   goon_walk_right
	dc.w	$000e,$0180,$0408	;   goon_walk_right
	dc.w	$0002,$01a0,$03e8	;   thug_walk_right
	dc.w	$01b4,$03e0,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$00f4,$0408	;   goon_walk_right
	dc.w	$000e,$00e8,$0408	;   goon_walk_right
	dc.w	$01f8,$0411,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$0238,$0448	;   goon_walk_left
	dc.w	$0240,$03e4,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$0200,$03e8	;   goon_walk_right
	dc.w	$000e,$0210,$03e8	;   goon_walk_right
	dc.w	$000e,$0220,$03e8	;   goon_walk_right
	dc.w	$0240,$03c0,$0003	; group: trigger x, y, 3 objects
	dc.w	$000f,$0240,$03a8	;   goon_walk_left
	dc.w	$000f,$0230,$03a8	;   goon_walk_left
	dc.w	$000f,$0220,$03a8	;   goon_walk_left
	dc.w	$01e0,$0390,$0006	; group: trigger x, y, 6 objects
	dc.w	$0002,$01f0,$0388	;   thug_walk_right
	dc.w	$000e,$01a0,$03a8	;   goon_walk_right
	dc.w	$000e,$01f0,$0348	;   goon_walk_right
	dc.w	$000e,$0200,$0348	;   goon_walk_right
	dc.w	$000e,$01f0,$03a8	;   goon_walk_right
	dc.w	$000e,$01f8,$03a8	;   goon_walk_right
	dc.w	$01a0,$02a8,$0001	; group: trigger x, y, 1 object
	dc.w	$0002,$01a0,$0288	;   thug_walk_right
	dc.w	$015e,$0250,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0218,$0288	;   goon_walk_left
	dc.w	$000f,$020c,$0288	;   goon_walk_left
	dc.w	$010c,$02c0,$0002	; group: trigger x, y, 2 objects
	dc.w	$0002,$00e0,$02e8	;   thug_walk_right
	dc.w	$0002,$00f0,$02e8	;   thug_walk_right
	dc.w	$00ea,$03aa,$0003	; group: trigger x, y, 3 objects
	dc.w	$000f,$0110,$03a8	;   goon_walk_left
	dc.w	$000f,$0100,$03a8	;   goon_walk_left
	dc.w	$0003,$01c0,$03a8	;   thug_walk_left
	dc.w	$00ea,$0398,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$013c,$0408	;   goon_walk_left
	dc.w	$000f,$014c,$0408	;   goon_walk_left
	dc.w	$00d0,$0330,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$01ac,$0348	;   goon_walk_left
	dc.w	$000f,$01a0,$0348	;   goon_walk_left
	dc.w	$00b0,$0380,$0002	; group: trigger x, y, 2 objects
	dc.w	$0003,$015c,$03a8	;   thug_walk_left
	dc.w	$000e,$0088,$019e	;   goon_walk_right
	dc.w	$0070,$0380,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0128,$03a8	;   goon_walk_left
	dc.w	$000f,$0138,$03a8	;   goon_walk_left
	dc.w	$0126,$0350,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0158,$0348	;   thug_walk_left
	dc.w	$0189,$0350,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$00e8,$0348	;   goon_walk_right
	dc.w	$000f,$0198,$0348	;   goon_walk_left
	dc.w	$00c0,$029b,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$0120,$0288	;   goon_walk_right
	dc.w	$000e,$0140,$0268	;   goon_walk_right
	dc.w	$00c0,$025e,$0003	; group: trigger x, y, 3 objects
	dc.w	$0003,$0150,$0268	;   thug_walk_left
	dc.w	$000f,$00f0,$0248	;   goon_walk_left
	dc.w	$000e,$00f0,$0248	;   goon_walk_right
	dc.w	$00cc,$021f,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$00f0,$0208	;   goon_walk_left
	dc.w	$000e,$00f0,$0208	;   goon_walk_right
	dc.w	$00cc,$01d0,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$00f0,$01c8	;   goon_walk_left
	dc.w	$0146,$01a0,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0160,$01c8	;   thug_walk_left
	dc.w	$018a,$0190,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$01a0,$01a8	;   goon_walk_left
	dc.w	$01b3,$0180,$0001	; group: trigger x, y, 1 object
	dc.w	$000f,$01d8,$01c8	;   goon_walk_left
	dc.w	$0210,$018c,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$00a8,$0288	;   goon_walk_right
	dc.w	$000f,$0198,$0248	;   goon_walk_left
	dc.w	$0002,$01c8,$0228	;   thug_walk_right
	dc.w	$01c0,$01f1,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$01c8,$01e8	;   goon_walk_right
	dc.w	$000e,$01d8,$01e8	;   goon_walk_right
	dc.w	$0235,$01f8,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$01c8,$01e8	;   goon_walk_right
	dc.w	$000e,$01d8,$01e8	;   goon_walk_right
	dc.w	$0235,$01ce,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$0180,$01a8	;   goon_walk_right
	dc.w	$000e,$0188,$01a8	;   goon_walk_right
	dc.w	$0200,$019f,$0001	; group: trigger x, y, 1 object
	dc.w	$0003,$0160,$01a8	;   thug_walk_left
	dc.w	$014c,$0170,$0002	; group: trigger x, y, 2 objects
	dc.w	$000f,$0120,$0168	;   goon_walk_left
	dc.w	$0003,$0130,$0168	;   thug_walk_left
	dc.w	$018a,$0100,$0002	; group: trigger x, y, 2 objects
	dc.w	$0002,$00e8,$0128	;   thug_walk_right
	dc.w	$0003,$01a0,$0128	;   thug_walk_left
	dc.w	$0124,$0120,$0003	; group: trigger x, y, 3 objects
	dc.w	$0002,$00e8,$0128	;   thug_walk_right
	dc.w	$000f,$0124,$0128	;   goon_walk_left
	dc.w	$000f,$01a0,$01a8	;   goon_walk_left
	dc.w	$01b0,$0100,$0002	; group: trigger x, y, 2 objects
	dc.w	$000e,$01d0,$0108	;   goon_walk_right
	dc.w	$0003,$01d0,$0148	;   thug_walk_left
	dc.w	$0194,$00c8,$0001	; group: trigger x, y, 1 object
	dc.w	$0002,$0140,$00c8	;   thug_walk_right
	dc.w	$0180,$0080,$0004	; group: trigger x, y, 4 objects
	dc.w	$000e,$0120,$00c8	;   goon_walk_right
	dc.w	$000e,$0114,$00c8	;   goon_walk_right
	dc.w	$000e,$0108,$00c8	;   goon_walk_right
	dc.w	$0002,$00f0,$00a8	;   thug_walk_right
	dc.w	$0107,$00a0,$0003	; group: trigger x, y, 3 objects
	dc.w	$000e,$00e8,$00c8	;   goon_walk_right
	dc.w	$000e,$00e8,$00a8	;   goon_walk_right
	dc.w	$0003,$01c0,$00c8	;   thug_walk_left
	dc.w	$0140,$000f,$0002	; group: trigger x, y, 2 objects
	dc.w	$0003,$0168,$0048	;   thug_walk_left
	dc.w	$0003,$0178,$0048	;   thug_walk_left
	dc.w	$0184,$0020,$0003	; group: trigger x, y, 3 objects
	dc.w	$000f,$01b0,$0048	;   goon_walk_left
	dc.w	$000f,$01a0,$0048	;   goon_walk_left
	dc.w	$000e,$00e8,$0048	;   goon_walk_right
	dc.w	$01a6,$0020,$0002	; group: trigger x, y, 2 objects
	dc.w	$0020,$01cc,$0048	;   boss_climb_watch
	ifeq	CONFIG-RETAIL_2DISK
	dc.w	$001f,$01cc,$0038	;   boss_climb
	endc
	ifne	CONFIG-RETAIL_2DISK
	dc.w	$001f,$01cc,$0040	;   boss_climb
	endc
spawn_singles:
	dc.w	$001d,$0120,$0088	; crawler_right
	dc.w	$001d,$0120,$00a8	; crawler_right
	dc.w	$001d,$0180,$0248	; crawler_right
	dc.w	$001d,$01b0,$01c8	; crawler_right
	dc.w	$001e,$0190,$0348	; crawler_left
	dc.w	$001e,$0180,$02a8	; crawler_left
	dc.w	$001e,$01f0,$02c8	; crawler_left
	dc.w	$001e,$0220,$0648	; crawler_left
	dc.w	$001d,$0200,$0628	; crawler_right
	dc.w	$001d,$0220,$05e8	; crawler_right
	dc.w	$001e,$0140,$04e8	; crawler_left
	dc.w	$001a,$00a0,$0550	; object_use_start
	dc.w	$001a,$00a0,$0570	; object_use_start
	dc.w	$001a,$0120,$0588	; object_use_start
	dc.w	$001a,$01c0,$0408	; object_use_start
	dc.w	$001a,$01c0,$0428	; object_use_start
	dc.w	$001a,$0160,$01c8	; object_use_start
	dc.w	$001d,$0240,$0488	; crawler_right
	dc.w	$001d,$0120,$04a8	; crawler_right
checkpoint_starts:	; from: level_begin
	dc.w	$0010,$0608,$0650,$0048,$0048,$0048,$0048	; start
	ifeq	CONFIG-RETAIL_2DISK
	dc.w	$0048,$0044,$0470,$0048,$0028,$0028,$0048	; after checkpoint 1 - bug: respawn outside the cathedral after a death past checkpoint 1: scroll_y $0044, not $0448
	endc
	ifne	CONFIG-RETAIL_2DISK
	dc.w	$0048,$0448,$0470,$0048,$0028,$0028,$0048	; after checkpoint 1
	endc
	dc.w	$01a0,$0268,$0290,$0048,$0028,$0028,$0048	; after checkpoint 2
	endc
scroll_x:	; from: level_begin, redraw_tiles, init_tile_cache, scroll_left, scroll_right, scroll_up, ...
	dc.w	$0008
scroll_y:	; from: redraw_tiles, scroll_left, scroll_right, scroll_up, scroll_down, update_scroll, score_distance, ...
	dc.w	$0008
score_scroll_x:	; from: score_distance
	dc.w	$0000
player_x:	; from: main_loop, update_enemies, aim_shot, thug_walk_left, thug_walk_right, goon_walk_right, ...
	dc.w	$0048
player_y:	; from: update_enemies, check_jump_ladder, bullet_move, grenade_right, update_scroll, state_rope_swing, score_distance, ...
	dc.w	$0048
player_ref_y:	; from: state_rope_swing, fire_rope_up, ladder_below, ladder_above, state_ladder, start_fall, ...
	dc.w	$0048
camera_x:	; from: update_scroll, vat_watch, level_complete
	dc.w	$0048

play_tune:	; from: level_begin, main_loop, state_knocked_wait, level_complete
	btst	#$0,game_flags
	bne.s	sound_off_exit
	jmp	snd_play_tune

sound_off_exit:	; from: play_sfx
	rts


play_sfx:	; from: update_enemies, aim_shot, play_sfx_on_screen, bullet_move, rope_hook, throw_batarang, ...
	btst	#$0,game_flags
	beq.s	sound_off_exit
	movem.l	d1-d7/a0-a6,-(sp)
	jsr	snd_play_sfx
	movem.l	(sp)+,d1-d7/a0-a6
	rts


clear_and_dissolve:	; from: main_loop, level_complete
	movea.l	screen_back.w,a0
	move.w	#$17bf,d7
clear_dissolve_loop:
	clr.l	(a0)+
	dbra	d7,clear_dissolve_loop

;----------------------------------------------------------------------
; Dissolve the back screen into the front one.
;----------------------------------------------------------------------
dissolve_in:	; from: level_begin, state_dying, level_complete
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


fade_in:	; from: level_begin
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
	move.w	flip_request,d0
	addq.w	#2,d0
fade_in_wait:
	cmp.w	flip_request,d0
	bne.s	fade_in_wait
	dbra	d7,fade_in_pass
	rts


fade_out:	; from: state_dying, level_complete
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
	move.w	flip_request,d0
	addq.w	#2,d0
fade_out_wait:
	cmp.w	flip_request,d0
	bne.s	fade_out_wait
	dbra	d7,fade_out_pass
	rts


print_text:	; from: level_begin, state_dying, level_complete
	moveq	#-1,d6
	bra.w	text_position

text_position:
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


; Font, 40 bytes per character (the same font is in every module).
font:	; from: build_sprite_tables, print_text
	incbin	"data/font.bin"		; $640 bytes of data

; Filler after the 40 characters of the font: one byte on level 1, up to the map on level 5.
font_filler:
	ifeq	BUILD_LEVEL-1
	dc.b	$e7
	ifne	CONFIG-RETAIL_1DISK
file_padding:
	ifeq	CONFIG-RETAIL_2DISK
	dc.b	$21,$00,$9c,$00,$63,$63,$00,$39,$c6,$c6,$00,$00,$18,$e6,$e7,$01
	dc.b	$00,$08,$f6,$f7,$01,$00,$00,$de,$ff,$21,$00,$10,$ce,$ef,$21,$00
	dc.b	$18,$c6,$e7,$21,$00,$18,$c6,$e7,$21,$00,$9c,$00,$63,$63,$00,$83
	dc.b	$7c,$7c,$00,$00,$01,$c6,$fe,$38,$00,$18,$c6,$e7,$21,$00,$18,$c6
	dc.b	$e7,$21,$00,$18,$c6,$e7,$21,$00,$18,$c6,$e7,$21,$00,$80,$7c,$7f
	dc.b	$03,$00,$c1,$00,$3e,$3e,$00,$03,$fc,$fc,$00,$00,$01,$c6,$fe,$38
	dc.b	$00,$18,$c6,$e7,$21,$00,$00,$fc,$ff,$03,$00,$01,$c0,$fe,$3e,$00
	dc.b	$1f,$c0,$e0,$20,$00,$1f,$c0,$e0,$20,$00,$9f,$00,$60,$60,$00,$83
	dc.b	$7c,$7c,$00,$00,$01,$c6,$fe,$38,$00,$18,$c6,$e7,$21,$00,$18,$c6
	dc.b	$e7,$21,$00,$00,$da,$ff,$25,$00,$00,$cc,$ff,$33,$00,$81,$76,$7e
	dc.b	$08,$00,$c4,$00,$3b,$3b,$00,$03,$fc,$fc,$00,$00,$01,$c6,$fe,$38
	dc.b	$00,$18,$c6,$e7,$21,$00,$00,$fc,$ff,$03,$00,$01,$cc,$fe,$32,$00
	dc.b	$18,$c6,$e7,$21,$00,$18,$c6,$e7,$21,$00,$9c,$00,$63,$63,$00,$83
	dc.b	$7c,$7c,$00,$00,$01,$c6,$fe,$38,$00,$1c,$c0,$e3,$23,$00,$83,$7c
	dc.b	$7c,$00,$00,$c1,$06,$3e,$38,$00,$38,$c6,$c7,$01,$00,$80,$7c,$7f
	dc.b	$03,$00,$c1,$00,$3e,$3e,$00,$03,$fc,$fc,$00,$00,$81,$30,$7e,$4e
	dc.b	$00,$c7,$30,$38,$08,$00,$c7,$30,$38,$08,$00,$c7,$30,$38,$08,$00
	dc.b	$c7,$30,$38,$08,$00,$c7,$30,$38,$08,$00,$e7,$00,$18,$18,$00,$39
	dc.b	$c6,$c6,$00,$00,$18,$c6,$e7,$21,$00,$18,$c6,$e7,$21,$00,$18,$c6
	dc.b	$e7,$21,$00,$18,$c6,$e7,$21,$00,$18,$c6,$e7,$21,$00,$80,$7c,$7f
	dc.b	$03,$00,$c1,$00,$3e,$3e,$00,$39,$c6,$c6,$00,$00,$18,$c6,$e7,$21
	dc.b	$00,$18,$c6,$e7,$21,$00,$80,$6c,$7f,$13,$00,$81,$7c,$7e,$02,$00
	dc.b	$c1,$38,$3e,$06,$00,$e3,$10,$1c,$0c,$00,$f7,$00,$08,$08,$00,$39
	dc.b	$c6,$c6,$00,$00,$18,$c6,$e7,$21,$00,$08,$d6,$f7,$21,$00,$00,$d6
	dc.b	$ff,$29,$00,$00,$fe,$ff,$01,$00,$80,$7c,$7f,$03,$00,$81,$6c,$7e
	dc.b	$12,$00,$c9,$00,$36,$36,$00,$39,$c6,$c6,$00,$00,$18,$c6,$e7,$21
	dc.b	$00,$10,$ee,$ef,$01,$00,$80,$7c,$7f,$03,$00,$01,$ee,$fe,$10,$00
	dc.b	$18,$c6,$e7,$21,$00,$18,$c6,$e7,$21,$00,$9c,$00,$63,$63,$00,$33
	dc.b	$cc,$cc,$00,$00,$11,$cc,$ee,$22,$00,$11,$cc,$ee,$22,$00,$81,$78
	dc.b	$7e,$06,$00,$c3,$30,$3c,$0c,$00,$c7,$30,$38,$08,$00,$c7,$30,$38
	dc.b	$08,$00,$e7,$00,$18,$18,$00,$03,$fc,$fc,$00,$00,$01,$cc,$fe,$32
	dc.b	$00,$81,$18,$7e,$66,$00,$c3,$30,$3c,$0c,$00,$87,$60,$78,$18,$00
	dc.b	$03,$cc,$fc,$30,$00,$01,$fc,$fe,$02,$00,$81,$00,$7e,$7e
	dcb.b	635,$00
	endc
	ifeq	CONFIG-BUDGET_1DISK
	dcb.b	31,$00
	endc
	endc
	else
	ifeq	CONFIG-RETAIL_2DISK
	dcb.b	510,$00
	endc
	ifne	CONFIG-RETAIL_2DISK
	dcb.b	112,$00
	dcb.b	260,$1a
	endc

; From here on the module is overwritten by level5.map when the level loads.
map_tile_count:	; from: convert_level_gfx
	ifeq	CONFIG-RETAIL_2DISK
	dc.w	$0000,$0000,$0000
	endc
	ifne	CONFIG-RETAIL_2DISK
	dc.w	$1a1a,$1a1a,$1a1a
	endc
map_tiles:	; from: level_begin, unused_flip_map, convert_level_gfx, map_tile_at, object_use_anim
	ifeq	CONFIG-RETAIL_2DISK
	dcb.b	58,$00
	endc
	ifne	CONFIG-RETAIL_2DISK
	dcb.b	58,$1a
	endc
map_climb_column:	; from: boss_climb_watch
	ifeq	CONFIG-RETAIL_2DISK
	dcb.b	60,$00
	dcb.b	384,$1a
	endc
	ifeq	CONFIG-RETAIL_1DISK
	dcb.b	444,$1a
	endc
	ifeq	CONFIG-BUDGET_1DISK
	dcb.b	444,$1a
file_padding:
	dcb.b	31,$00
	endc
	endc
