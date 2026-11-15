; RIPPER.S  -  The Ultimate Ripper cartridge, "THE ULTIMATE RIPPER VERSION 1.2 BY U.D, Copyright 1990-91,
;              EDITED BY : EURO SOFT"
; Devpac source of the cartridge, disassembled by Darren Birks, 14 November 2026.
; 64K at $FA0000; the code and data are $0000-$F2A5, the rest $FF.
;
; This source rebuilds the cartridge's 64K byte for byte with
;   vasmm68k_mot -devpac -m68000 -Fbin -o RIPPER.IMG RIPPER.S
; The dump, Ultimate Ripper 1.2.bin, is 128K: these 64K twice ($FA0000 and the same again at $FB0000), so
;   copy /b RIPPER.IMG+RIPPER.IMG "Ultimate Ripper 1.2.bin"
; gives it whole.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; A ripper for pictures, music, samples, memory and disks on a diagnostic cartridge ($FA52235F at its start):
; TOS runs it at reset, before it clears the memory.  start reads a key at once:
;   F1   the first 128K kept at $60000/$80000, then as F2
;   F2   the memory kept (TOS steered by trace_reset so that it does not clear it), then the ripper
;   F7   the same, but trace_game follows TOS into the game and hooks the game's first VBL routine (vbl_hook):
;        from then on the game can be stopped for in_game_search, a search and replace in its memory
;   F8   'DUM ' marked: TOS's start loads and runs a:\dump2.tos instead
;   F9   a jump through $30
;   F10  a normal boot
; trace_reset and trace_game single step TOS, steering it at the instructions they know (no memory clear,
; the screen at $10000, the boot sector check), the background flashing as they go.
;
; The ripper itself runs under TOS, from main_menu:
;   F1 picture_ripper   the memory shown as a picture (address, planes, width, resolution, palette, superposed
;                       planes, columns, modulo), 10 settings kept, a raster bar for the colours, saved as Degas
;   F2 memory_ripper    hex dump or disassembly, bookmarks, search, fill, edit, copy, print, and saving as a
;                       binary or as an assembler source (labels L<address>, a DATA section of DC.B)
;   F3 disk_utility     directory, path, rename, format, delete, create a folder, free space
;   F4 external_call    a program loaded and run (Pexec), the load address
;   F5 external_loader  a file read to an address, or whole tracks read with its own floppy controller code
;   F6 music_ripper     Soundtracker, Quartet, TCB Tracker, chip music and soundtrack routines searched for,
;                       played with a VU meter, saved as a binary or as a resident program (music_program);
;                       the sample ripper draws, plays (sound chip or STE DMA sound, with the LMC1992
;                       controls) and saves samples, also as a resident player program
;   F7 disk_ripper      sectors, whole tracks and ID fields read, sectors written, the disk searched, the
;                       buffer edited, all through its own floppy controller code (the fdc_ routines)
;   F9 info             the title and credits
;   F10                 quit (a reset)
;   Control C           the calculator: a op b in hex or decimal
;   Shift F1-F10        module_keys: straight to another module
; Its variables are in RAM at $D000-$E779 (the equates below), cleared by init_variables.  The screen is its
; own (ripper_screen): medium resolution on a colour monitor, high on mono.
;
; Some things in it:
;   - The memory ripper's search has no end check: it stops when found or when ESC is pressed (escape_watch,
;     a vblqueue routine that sets search_stop).
;   - The in-game search goes from $200 to 4 Mb whatever the memory size.
;   - The sample program (ym_program) pushes the arguments for Jenabint(13) but never makes the call.
;   - The disassembler prints MOVE to CCR with .B (dis_move_to_ccr).
;   - critical_error_handler returns -1 for every critical error, with no alert.
;   - Most texts are English, but a few are French: "RANGE ERREUR", "FIND ADRESSE", "F1 : REMPLACE",
;     "ERREUR DE SYNTAXE".
;   - Some routines and branches are never reached (marked "not reached" or "not called"), among them
;     ripper_shrink, fdc_step_out and a "DISK ERROR !!!" message.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$0003  the diagnostic cartridge's mark
;   $0004-$0653  the start: the reset keys, trace_reset, trace_boot, trace_game, the set-up
;   $0654-$0c15  the main menu, the modules, the calculator, quit_to_reset, reserve_memory
;   $0c16-$0e51  init_variables
;   $0e52-$1409  the game's VBL hook and the in-game search, the error and timer C handlers
;   $140a-$3119  the disk ripper
;   $311a-$34c5  module_keys, info, external_call, show_gemdos_error
;   $34c6-$5d43  the music ripper, the sample ripper and its players, the music searches, the VU meter,
;                show_error
;   $5d44-$658f  the memory ripper, save_source
;   $6590-$7be5  the disassembler
;   $7be6-$83bf  the memory ripper's copy, edit, search and fill
;   $83c0-$8a35  the keyboard, the line input, the text output, the cursor
;   $8a36-$91b5  the font
;   $91b6-$94d5  boxes and lines
;   $94d6-$97d5  the hex dumps and printing
;   $97d6-$b565  the picture ripper
;   $b566-$be07  the disk utility
;   $be08-$c313  the external loader, the floppy controller routines, read_file, build_music_program
;   $c314-$c3df  music_program
;   $c3e0-$f2a5  the texts, the tables, the error messages
;   $f2a6-$ffff  $FF
;
;=======================================================================

control_line	equ	$d000                   ; the STE control picked
ste_volume	equ	$d002
ste_right	equ	$d004
ste_left	equ	$d006
ste_treble	equ	$d008
ste_bass	equ	$d00a
ste_stereo	equ	$d00c
ste_frequency	equ	$d00e
ym_replay	equ	$d010                   ; 1: the sound chip replays samples, 0: the STE DMA sound
calc_first_negative	equ	$d012
calc_second_negative	equ	$d014
calc_operator	equ	$d016
calc_first	equ	$d018
calc_second	equ	$d01c
number_negative	equ	$d020
columns_drawn	equ	$d022                   ; columns marked so far
picture_columns_on	equ	$d024
picture_modulo	equ	$d026
text_normal	equ	$d028                   ; 1 normal text, 0 inverse
text_column	equ	$d02a
text_row	equ	$d02c
cursor_drawn	equ	$d056
cursor_off	equ	$d058
cursor_place	equ	$d05a
hex_text	equ	$d05c                   ; hex digits made by put_hex_address
line_from_x	equ	$d070
line_to_x	equ	$d072
line_from_y	equ	$d074
line_to_y	equ	$d076
line_step	equ	$d078
sample_position	equ	$d07a
sample_last	equ	$d07e
saved_iera	equ	$d082
saved_ierb	equ	$d083
saved_imra	equ	$d084
saved_imrb	equ	$d085
saved_tadr	equ	$d086
saved_tacr	equ	$d087
saved_timer_a	equ	$d088
sample_playing	equ	$d08c
path_line	equ	$d090                   ; "PATH = " and the path
path	equ	$d09d
colour_marker_text	equ	$d11d
colour_unmarker_text	equ	$d124
setting_marker_text	equ	$d12b
setting_unmarker_text	equ	$d132
sample_marker_text	equ	$d139
sample_unmarker_text	equ	$d140
edit_cursor_text	equ	$d147
setting_row	equ	$d14e
colour_row	equ	$d14f
raster_pointer	equ	$d150                   ; the next raster colour
raster_colours	equ	$d154                   ; 25 raster colours
picture_palette	equ	$d15c                   ; the picture's 16 colours
raster_end	equ	$d186
colour_value_text	equ	$d188
drive_letter	equ	$d18d
superposed_count	equ	$d190
superposed	equ	$d192
superposed_width	equ	$d194
picture_width	equ	$d196
picture_screen	equ	$d198                   ; where the picture is shown
ripper_screen	equ	$d19c                   ; the ripper's own screen
picture_planes	equ	$d1a0
plane_masks	equ	$d1a2                   ; the four planes' masks ($FFFF used)
dir_attribute	equ	$d1aa
format_track_number	equ	$d1ac
format_two_sides	equ	$d1ae
dta	equ	$d1b0                           ; the disk utility's DTA
saving_picture	equ	$d1de
printing_off	equ	$d1e0
picture_resolution	equ	$d1e2
colours_mode	equ	$d1e4
ym_frequency_index	equ	$d1e6
sample_marker_index	equ	$d1e7
input_buffer	equ	$d1e8                   ; a line typed: its maximum, its count, the text
name_buffer	equ	$d1f4
replace_buffer	equ	$d210
fill_bytes	equ	$d23c
memory_address	equ	$d266                   ; the memory ripper's address
search_value	equ	$d26a
search_stop	equ	$d26e                   ; minus to stop a search (ESC)
range_end	equ	$d270
sample_unsigned	equ	$d274
sample_sign	equ	$d276
range_start	equ	$d278
copy_destination	equ	$d27c
last_search_kind	equ	$d280           ; the last search: 'O' byte, 'M' word, 'L' long, 'T' text, -1 none
last_search_value	equ	$d282
boot_info_line	equ	$d2a2
track_mode	equ	$d2a4                   ; 1: the whole track read
head_track	equ	$d2a6
track	equ	$d2a8
sector	equ	$d2aa
side	equ	$d2ac
track_count	equ	$d2ae
sectors_per_track	equ	$d2b0
side_count	equ	$d2b2
first_sector	equ	$d2b4
buffer_view	equ	$d2b6
source_buffer_end	equ	$d2ba
buffer_length	equ	$d2be                   ; the bytes in the disk buffer
data_end	equ	$d2c4
empty_string	equ	$d2c8
free_ram	equ	$d2ca
load_address	equ	$d2ce
saved_mediach	equ	$d2d2
saved_critic	equ	$d2d6
saved_timer_c	equ	$d2da
vu_level_a	equ	$d2de
vu_level_b	equ	$d2e0
vu_level_c	equ	$d2e2
line_count	equ	$d2e4
disassembly_view	equ	$d2e6           ; disassembly instead of hex
music_kind	equ	$d2e8                   ; the music found (also save_source's file handle)
sample_start	equ	$d2ea
sample_end	equ	$d2ee
next_page_address	equ	$d2f2
next_line_address	equ	$d2f6
bookmarks	equ	$d2fa                   ; the memory ripper's 10 bookmarks
picture_settings	equ	$d322           ; the picture ripper's 10 settings, 120 bytes each
dump_text	equ	$d7d2                   ; a screen of text (its ESC head first)
dump_lines	equ	$d7da
disk_buffer	equ	$dfaa                   ; the disk buffer (also the work buffer for building programs)
ids_seen	equ	$e108
id_buffer	equ	$e234
variables_end	equ	$e77a

	org	$fa0000

;------------------------------------------------------------------------------
; cartridge_magic: $FA52235F: a diagnostic cartridge, run by TOS at reset with a6 the address to go back to.
;------------------------------------------------------------------------------
cartridge_magic:
	dc.w	$fa52,$235f

;------------------------------------------------------------------------------
; start: the memory size from the controller (or found by writing 'DUM ' past each size), then the reset key
; read from the keyboard at once: F1 keeps the first 128K at $60000/$80000 then goes on as F2, F2 keeps the
; memory (the palette and screen saved at $140, the vectors and memory variables set so TOS will not clear
; it) and traces TOS's start with trace_reset, F7 the same with trace_boot (the game hooked), F8 marks a
; dump to load, F9 goes to $30, F10 a normal boot.  Any other key waits.
;------------------------------------------------------------------------------
start:
	move.w	#$2700,sr                       ; interrupts off
	clr.b	$fffffa09.w                     ; MFP IERB, MFP interrupts off
	clr.b	$fffffa07.w                     ; MFP IERA
	moveq	#0,d0
	move.b	$ffff8001.w,d0                  ; memory config, the memory configuration
	tst.w	d0                              ; set (a warm reset)?
	beq.s	find_memory                     ; no: find the size
	move.l	#$52495020,$250.w               ; 'RIP ': the memory kept
	cmp.b	#$4,d0                          ; 512K?
	bne.s	start_one_mb
	move.l	#$80000,d1
	bra.w	reset_keys
start_one_mb:
	cmp.b	#$5,d0                          ; 1 Mb?
	bne.s	start_two_mb
	move.l	#$100000,d1
	bra.w	reset_keys
start_two_mb:
	cmp.b	#$8,d0                          ; 2 Mb?
	bne.s	start_four_mb
	move.l	#$200000,d1
	bra.w	reset_keys
start_four_mb:
	cmp.b	#$a,d0                          ; 4 Mb?
	bne.s	start_two_half_mb
	move.l	#$400000,d1
	bra.w	reset_keys
start_two_half_mb:
	cmp.b	#$6,d0                          ; 2.5 Mb?
	bne.s	find_memory
	move.l	#$280000,d1
	bra.w	reset_keys
find_memory:
	clr.l	$250.w                          ; not kept
	moveq	#4,d0                           ; 512K
	move.l	#$44554d20,d7                   ; 'DUM '
	move.l	#$80000,d1
	lea	$85000,a0                       ; past 512K
	move.l	(a0),d3                         ; kept
	move.l	d7,(a0)                         ; written
	nop
	nop
	nop
	nop
	cmp.l	(a0),d7                         ; there?
	bne.s	find_memory_restore_half        ; no: 512K
	moveq	#5,d0                           ; 1 Mb
	move.l	#$100000,d1
	lea	$105000,a0                      ; past 1 Mb
	move.l	(a0),d4
	move.l	d7,(a0)
	nop
	nop
	nop
	nop
	cmp.l	(a0),d7                         ; there?
	bne.s	find_memory_restore_one         ; no
	moveq	#8,d0                           ; 2 Mb
	move.l	#$200000,d1
	lea	$205000,a0                      ; past 2 Mb
	move.l	(a0),d5
	move.l	d7,(a0)
	nop
	nop
	nop
	nop
	cmp.l	(a0),d7                         ; there?
	bne.s	find_memory_restore_two         ; no
	moveq	#6,d0                           ; 2.5 Mb
	move.l	#$280000,d1
	lea	$305000,a0                      ; past 3 Mb
	move.l	(a0),d6
	move.l	d7,(a0)
	nop
	nop
	nop
	nop
	cmp.l	(a0),d7                         ; there?
	bne.s	find_memory_restore             ; no
	moveq	#10,d0                          ; 4 Mb
	move.l	#$400000,d1
find_memory_restore:
	move.l	d6,$305000                      ; the memory put back
find_memory_restore_two:
	move.l	d5,$205000
find_memory_restore_one:
	move.l	d4,$105000
find_memory_restore_half:
	move.l	d3,$85000
	move.b	d0,$ffff8001.w                  ; memory config, the configuration set
reset_keys:
	move.b	#$3,$fffffc00.w                 ; keyboard ACIA control, keyboard ACIA reset
	move.b	#$96,$fffffc00.w                ; keyboard ACIA control, 8N1, /64
	clr.l	$254.w                          ; no 'SAVE'
	clr.l	$258.w                          ; no 'DUM '
reset_key:
	move.b	$fffffc02.w,d7                  ; keyboard ACIA data, the key
	cmp.b	#$43,d7                         ; F9?
	bne.s	reset_key_f8                    ; no
	movea.l	$30,a0                          ; to $30
	jmp	(a0)
reset_key_f8:
	cmp.b	#$42,d7                         ; F8?
	bne.s	reset_key_f7                    ; no
	move.l	#$44554d20,$258.w               ; 'DUM ': load the dump
reset_key_f7:
	cmp.b	#$41,d7                         ; F7?
	bne.s	reset_key_f10                   ; no
	bra.w	trace_boot                      ; the game hooked
reset_key_f10:
	cmp.b	#$44,d7                         ; F10?
	bne.s	reset_key_f2                    ; no
	clr.l	$420.w                          ; memvalid, a normal boot
	bra.w	reset_return
reset_key_f2:
	cmp.b	#$3c,d7                         ; F2?
	beq.s	keep_memory
	cmp.b	#$3b,d7                         ; F1?
	bne.s	reset_key                       ; no: another key
	move.l	#$53415645,$254.w               ; 'SAVE'
	lea	$60000,a4                       ; the copy at $60000
	cmp.b	#$4,d0                          ; 512K?
	beq.s	keep_low_memory                 ; yes
	lea	$80000,a4                       ; else at $80000
keep_low_memory:
	suba.l	a5,a5
keep_low_memory_long:
	move.l	(a5)+,(a4)+                     ; the first 128K copied
	cmpa.l	#$20000,a5
	blt.s	keep_low_memory_long
keep_memory:
	lea	$140.w,a0                       ; the palette and the screen kept at $140
	lea	$ffff8240.w,a1                  ; palette 0
	moveq	#7,d7                           ; 8 longs
keep_memory_palette:
	move.l	(a1)+,(a0)+
	dbra	d7,keep_memory_palette
	moveq	#0,d7
	move.b	$ffff8201.w,d7                  ; video base high, the screen's address
	lsl.l	#8,d7
	move.b	$ffff8203.w,d7                  ; video base mid
	lsl.l	#8,d7
	move.l	d7,(a0)+
	move.l	$44e.w,(a0)+                    ; _v_bas_ad, and _v_bas_ad
	lea	$400.w,a0                       ; etv_timer, the system's area cleared
	lea	$10000,a1                       ; to $10000
keep_memory_clear:
	clr.l	(a0)+
	cmpa.l	a1,a0
	blt.s	keep_memory_clear
	move.l	#trace_return,$14.w             ; divide by zero: rte
	clr.l	$45e.w                          ; screenpt, no screen to set
	clr.l	$45a.w                          ; colorptr, no palette to set
	move.l	#$752019f3,$420.w               ; memvalid, memvalid
	move.l	#$237698aa,$43a.w               ; memval2, memval2
	move.l	#$5555aaaa,$51a.w               ; memval3, memval3: the memory kept
	move.l	d1,$42e.w                       ; phystop, phystop
	move.b	d0,$424.w                       ; memcntlr, memcntlr
	clr.l	$5a4.w                          ; ramtop, ramtop
	move.l	#$1357bd13,$5a8.w               ; ramvalid, ramvalid
	move.l	#$ffffffff,$2c.w                ; Line F
	clr.l	$426.w                          ; resvalid, no reset vector
	lea	$400.w,sp                       ; etv_timer, a stack
	lea	trace_reset(pc),a0              ; trace
	move.l	a0,$24.w
	clr.w	$ffff8240.w                     ; palette 0, the background black
	move.w	#$a700,sr                       ; tracing, interrupts off
reset_return:
	jmp	(a6)                            ; back to TOS

;------------------------------------------------------------------------------
; trace_reset: TOS's start stepped through after an F1/F2 reset: at its known instructions it is steered
; (no memory clear, the screen at $10000, the boot sector check, ...) and with 'DUM ' the dump file loaded
; and run instead.  The background flashes as it goes.
;------------------------------------------------------------------------------
trace_reset:	; from: start
	not.w	$ffff8240.w                     ; palette 0, flashed
	move.l	a0,-(sp)
	movea.l	6(sp),a0                        ; the next pc
	move.l	a0,$240.w                       ; kept
	cmpi.l	#$b00466fa,(a0)                 ; the boot device test?
	beq.w	trace_reset_boot_device
	cmpi.w	#$42c0,(a0)                     ; move sr?
	beq.w	trace_reset_move_sr
	cmpi.l	#$2b48044e,(a0)                 ; "move.l a0,_v_bas_ad(a5)"?
	beq.w	trace_reset_screen
	cmpi.w	#$46fc,(a0)                     ; move to sr?
	beq.w	trace_reset_move_to_sr
	cmpi.l	#$b07c1234,(a0)                 ; the boot sector checksum test?
	beq.s	trace_reset_boot
	cmpi.l	#$48e27f10,(a0)                 ; a movem?
	beq.s	trace_reset_movem
	cmpi.w	#$f200,(a0)                     ; a Line F call?
	beq.w	trace_reset_line_f
	cmpi.l	#$3038fa40,(a0)
	beq.w	trace_reset_bus
	cmpi.l	#$11f8044f,(a0)
	beq.w	trace_reset_screen_clear
	cmpi.l	#$323c1f3f,(a0)                 ; the memory clear loop?
	beq.s	trace_reset_clear_loop
trace_reset_done:
	movea.l	(sp)+,a0
trace_return:	; from: start, trace_boot
	rte
trace_reset_screen_clear:
	moveq	#0,d1
	movea.l	(sp)+,a0
	lea	$10000,a0
	rte
trace_reset_bus:
	move.l	$8.w,6(sp)                      ; bus error vector, to the bus error vector's routine
	bra.s	trace_reset_done
trace_reset_line_f:
	move.l	$2c.w,6(sp)                     ; to the Line F vector's routine
	bra.s	trace_reset_done
trace_reset_clear_loop:
	cmpi.l	#$20c051c9,4(a0)
	bne.s	trace_reset_done
	addi.l	#$a,6(sp)                       ; past it
	bra.s	trace_reset_done
trace_reset_movem:
	addi.l	#$24,6(sp)                      ; past it
	bra.s	trace_reset_done
trace_reset_boot:
	lea	dump_name(pc),a0                ; "a:\dump2.tos"
	lea	$11000,a1                       ; to $11000
	move.l	#$30000,d2                      ; 196K
	bra.s	load_dump
trace_reset_screen:
	addq.l	#4,6(sp)                        ; past it
	movea.l	(sp)+,a0
	move.l	a0,$44e.w                       ; _v_bas_ad, the screen
	lea	$10000,a0                       ; at $10000
	moveq	#0,d1
	rte
trace_reset_boot_device:
	bclr	#$f,4(sp)                       ; trace off
	move.l	a6,d6
	lea	trace_reset_trace_on(pc),a6
	bra.s	trace_reset_done
trace_reset_trace_on:
	ori.w	#$8000,sr                       ; trace on again
	movea.l	d6,a6
	jmp	(a6)
trace_reset_move_sr:
	movea.l	(sp)+,a0
	suba.l	#$6,sp
	move.w	6(sp),(sp)
	move.l	8(sp),2(sp)
	move.l	$10,2(sp)                       ; illegal instr vector, to the illegal instruction routine
	bra.w	trace_return
trace_reset_move_to_sr:
	move.w	2(a0),4(sp)                     ; the new sr
	bset	#$f,4(sp)                       ; with trace
	addq.l	#4,6(sp)                        ; past it
	bra.w	trace_reset_done
load_dump:
	cmpi.l	#$44554d20,$258.w               ; a dump to load?
	bne.w	ripper_start_from_boot          ; no: the ripper
	move.w	#$2,-(sp)                       ; read/write
	move.l	a0,-(sp)                        ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.w	d0,d1                           ; the handle
	move.l	a1,-(sp)                        ; the buffer
	move.l	d2,-(sp)                        ; the length
	move.w	d1,-(sp)
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	lea	$c(sp),sp
	move.w	d1,-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	jmp	$11000                          ; run it
dump_name:
	dc.b	'a:\dump2.tos',0
	dc.b	$00

;------------------------------------------------------------------------------
; trace_boot (F7 at reset): the system's area cleared and the memory kept, then TOS started with
; trace_game, which hooks the game's VBL routine once there is one.
;------------------------------------------------------------------------------
trace_boot:	; from: start
	move.w	#$2700,sr                       ; interrupts off
	lea	$400.w,a0                       ; etv_timer
	lea	$10000,a1                       ; to $10000
trace_boot_clear:
	clr.l	(a0)+
	cmpa.l	a1,a0
	blt.s	trace_boot_clear
	move.l	#trace_return,$14.w             ; divide by zero: rte
	move.l	#$752019f3,$420.w               ; memvalid, memvalid
	move.l	#$237698aa,$43a.w               ; memval2, memval2
	move.l	#$5555aaaa,$51a.w               ; memval3, memval3
	move.l	d1,$42e.w                       ; phystop, phystop
	move.b	d0,$424.w                       ; memcntlr, memcntlr
	clr.l	$5a4.w                          ; ramtop, ramtop
	move.l	#$1357bd13,$5a8.w               ; ramvalid, ramvalid
	move.l	#$ffffffff,$2c.w                ; Line F
	lea	trace_game(pc),a0               ; trace
	move.l	a0,$24.w
	clr.l	$70.w                           ; VBL vector, no VBL routine yet
	clr.l	$74.w
	clr.l	$426.w                          ; resvalid, no reset vector
	clr.w	$ffff8240.w                     ; palette 0, the background black
	lea	$400.w,sp                       ; etv_timer, a stack
	move.w	#$a700,sr                       ; tracing, interrupts off
	jmp	(a6)                            ; back to TOS

;------------------------------------------------------------------------------
; trace_game: TOS and the game stepped through, steered as trace_reset; once a VBL routine is set that is
; not just rte, 'RIP ' is put in the disk buffer and the VBL vector taken by vbl_hook, and tracing stops.
;------------------------------------------------------------------------------
trace_game:	; from: trace_boot
	not.w	$ffff8240.w                     ; palette 0, flashed
	move.l	a0,-(sp)
	movea.l	6(sp),a0                        ; the next pc
	move.l	a0,$240.w                       ; kept
	cmpi.w	#$46fc,(a0)                     ; move to sr?
	beq.w	trace_game_move_to_sr
	cmpi.l	#$b00466fa,(a0)                 ; the boot device test?
	beq.s	trace_game_boot_device
	cmpi.w	#$42c0,(a0)                     ; move sr?
	beq.w	trace_game_move_sr
	cmpi.w	#$f200,(a0)                     ; a Line F call?
	beq.w	trace_game_line_f
	cmpi.l	#$3038fa40,(a0)
	beq.w	trace_game_bus
	tst.l	$70.w                           ; VBL vector, a VBL routine?
	beq.s	trace_game_done                 ; no
	movea.l	$70.w,a0                        ; VBL vector
	cmpi.w	#$4e73,(a0)                     ; only rte?
	beq.s	trace_game_done                 ; yes
	movea.l	$4c6,a0                         ; _dskbufp, the disk buffer
	move.l	#$52495020,(a0)                 ; 'RIP '
	move.l	$70.w,$c8.w                     ; VBL vector, the game's VBL kept
	move.l	#vbl_hook,$70.w                 ; VBL vector, taken
	bclr	#$f,4(sp)                       ; trace off
	move.w	#$777,$ffff8240.w               ; palette 0, the background white
trace_game_done:
	movea.l	(sp)+,a0
trace_game_return:
	rte
trace_game_move_to_sr:
	move.w	2(a0),4(sp)                     ; the new sr
	bset	#$f,4(sp)                       ; with trace
	addq.l	#4,6(sp)                        ; past it
	bra.s	trace_game_done
trace_game_boot_device:
	bclr	#$f,4(sp)                       ; trace off
	move.l	a6,d6
	lea	trace_game_trace_on(pc),a6
	bra.s	trace_game_done
trace_game_trace_on:
	ori.w	#$8000,sr                       ; trace on again
	movea.l	d6,a6
	jmp	(a6)
trace_game_line_f:
	move.l	$2c.w,6(sp)                     ; to the Line F routine
	bra.s	trace_game_done
trace_game_bus:
	move.l	$8.w,6(sp)                      ; bus error vector, to the bus error routine
	bra.s	trace_game_done
trace_game_move_sr:
	movea.l	(sp)+,a0
	subq.l	#6,sp
	move.w	6(sp),(sp)
	move.l	8(sp),2(sp)
	move.l	$10.w,2(sp)                     ; illegal instr vector, to the illegal instruction routine
	bra.s	trace_game_return
ripper_start_from_boot:	; from: trace_reset
	bra.w	ripper

;------------------------------------------------------------------------------
; ripper_shrink: as a program: its memory shrunk (not reached).
;------------------------------------------------------------------------------
ripper_shrink:
	lea	ripper_shrink(pc),a5
	suba.l	#$100,a5                        ; the basepage
	move.l	$c(a5),d0                       ; text
	add.l	$14(a5),d0                      ; + data
	add.l	$1c(a5),d0                      ; + bss
	addi.l	#$300,d0                        ; + $300
	move.l	d0,-(sp)
	pea	(a5)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp

;------------------------------------------------------------------------------
; ripper: the ripper itself: supervisor mode, memory taken below $10000, the variables set, its own critical
; error and timer C handlers, the mouse on, the kept palette and screen address taken, the window and
; resolution set, then the main menu.
;------------------------------------------------------------------------------
ripper:	; from: trace_game
	move.w	sr,d0
	btst	#$d,d0                          ; supervisor?
	bne.s	ripper_go                       ; yes
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
ripper_go:
	bsr.w	reserve_memory                  ; the memory below $10000 taken
	bsr.w	init_variables                  ; the variables set
	move.l	$114,saved_timer_c              ; timer C kept
	move.l	$404.w,saved_critic             ; etv_critic, the critical error handler kept
	move.l	#critical_error_handler,$404.w  ; etv_critic, its own
	move.l	#timer_c_handler,$114.w         ; its own timer C
	move.b	#$12,$fffffc02.w                ; keyboard ACIA data, the mouse off (IKBD)
	dc.w	$a00a                           ; Line-A $a, show mouse
	lea	$400.w,sp                       ; etv_timer, a stack
	move.l	sp,usp
	lea	$140.w,a0                       ; the kept palette and screen
	movem.l	(a0)+,d0-d7
	movem.l	d0-d7,picture_palette           ; kept
	movem.l	$ffff8240.w,d0-d7               ; palette 0, the palette now
	movem.l	d0-d7,-(sp)                     ; kept on the stack
	move.l	(a0)+,d0                        ; the video address kept
	move.l	(a0)+,d1                        ; _v_bas_ad kept
	btst	#$0,d0                          ; odd?
	bne.s	ripper_screen_variable          ; yes
	cmp.l	#$400000,d0                     ; in memory?
	bge.s	ripper_screen_variable          ; no
	tst.l	d0                              ; 0?
	beq.s	ripper_screen_variable          ; yes
	move.l	d0,memory_address               ; the memory address
	bra.s	ripper_window
ripper_screen_variable:
	btst	#$0,d1                          ; odd?
	bne.s	ripper_window                   ; yes
	cmp.l	#$400000,d1                     ; in memory?
	bge.s	ripper_window                   ; no
	tst.w	d1                              ; 0?
	beq.s	ripper_window                   ; yes
	move.l	d1,memory_address               ; the memory address
ripper_window:
	move.w	#$28,ste_volume                 ; the windows' sizes
	move.w	#$14,ste_right
	move.w	#$14,ste_left
	move.w	#$6,ste_treble
	move.w	#$6,ste_bass
	move.l	#ignore_fault,$8.w              ; bus error vector, bus error: ignored
	move.l	#ignore_fault,$c.w              ; address error vector, address error: ignored
	move.l	#escape_watch,$4d2.w            ; the VBL routine of the in-memory search
	move.l	$70.w,$c8.w                     ; VBL vector, the VBL kept
	clr.w	$ffff8242.w                     ; colour 1 black
	move.w	#$9,sectors_per_track
	move.w	#$50,track_count
	move.w	#$2,side_count
	move.w	#$1,first_sector
	moveq	#0,d0
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.w	#$3,d0
	move.w	d0,picture_resolution           ; kept
	cmp.b	#$2,d0                          ; high?
	bne.s	ripper_medium                   ; no
	clr.w	plane_masks+2
	clr.w	plane_masks+4
	clr.w	plane_masks+6
	move.w	#$1,picture_planes              ; 1 plane
	move.w	#$280,picture_width             ; 640 pixels
ripper_medium:
	cmp.b	#$1,d0                          ; medium?
	bne.s	ripper_low                      ; no
	clr.w	plane_masks+4
	clr.w	plane_masks+6
	move.w	#$2,picture_planes              ; 2 planes
	move.w	#$280,picture_width             ; 640 pixels
ripper_low:
	move.w	#$10,superposed_width
	move.w	#$4,superposed_count

;------------------------------------------------------------------------------
; main_menu: the menu: F1 picture, F2 memory, F3 disk utility, F4 external call, F5 external loader, F6
; music, F7 disk ripper, F9 info, F10 quit (asks), Control C the calculator.
;------------------------------------------------------------------------------
main_menu:	; from: modules, disk_ripper, info, external_call
	jsr	stop_raster                     ; the screen set
	movea.l	ripper_screen,a0                ; the ripper's screen
	jsr	show_ripper_screen              ; shown
	move.w	#$4,-(sp)                       ; Epson
	move.w	#$21,-(sp)
	trap	#14                             ; Setprt
	addq.l	#4,sp
main_menu_draw:
	lea	text_ultimate_ripper_f1,a0      ; the menu
	bsr.w	print
	moveq	#0,d4                           ; the frame
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#22,d7
	jsr	draw_box
	moveq	#28,d4                          ; the box
	move.w	#$c8,d5
	move.w	#$1b8,d6
	move.w	#$be,d7
	jsr	draw_box
main_menu_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$3,d0                          ; Control C?
	bne.s	main_menu_function              ; no
	moveq	#0,d0                           ; the calculator
	bra.w	run_module
main_menu_function:
	swap	d0                              ; its scan code
	cmp.b	#$3b,d0                         ; F1?
	beq.w	menu_picture_ripper             ; the picture ripper
	cmp.b	#$3c,d0                         ; F2?
	beq.w	menu_memory_ripper              ; the memory ripper
	cmp.b	#$3d,d0                         ; F3?
	beq.w	menu_disk_utility               ; the disk utility
	cmp.b	#$3e,d0                         ; F4?
	beq.w	external_call                   ; external call
	cmp.b	#$3f,d0                         ; F5?
	beq.w	menu_external_loader            ; external loader
	cmp.b	#$40,d0                         ; F6?
	beq.w	menu_music_ripper               ; the music ripper
	cmp.b	#$41,d0                         ; F7?
	beq.w	disk_ripper                     ; the disk ripper
	cmp.b	#$43,d0                         ; F9?
	beq.w	info                            ; info
	cmp.b	#$44,d0                         ; F10?
	bne.s	main_menu_key                   ; no: another key
	lea	text_confirm_y_n_at_de95,a0     ; "CONFIRM (Y/N) ?"
	bsr.w	print
main_menu_quit_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$79,d0                         ; 'y'?
	beq.s	main_menu_quit                  ; yes
	cmp.b	#$59,d0                         ; 'Y'?
	beq.s	main_menu_quit                  ; yes
	cmp.b	#$6e,d0                         ; 'n'?
	beq.w	main_menu_draw                  ; yes: the menu
	cmp.b	#$4e,d0                         ; 'N'?
	bne.s	main_menu_quit_key              ; no: another key
	bra.w	main_menu_draw                  ; the menu
main_menu_quit:
	jsr	stop_raster                     ; the screen set back
	clr.l	$4d2.w                          ; no in-memory search
	move.l	saved_timer_c,$114.w            ; timer C back
	move.l	saved_critic,$404.w             ; etv_critic, the critical error handler back
	movem.l	(sp)+,d0-d7                     ; the palette back
	movem.l	d0-d7,$ffff8240.w               ; palette 0
	move.b	#$7,$484.w                      ; conterm, key click and repeat
	dc.w	$a009                           ; Line-A $9, hide mouse
	move.b	#$8,$fffffc02.w                 ; keyboard ACIA data, the mouse on (IKBD)
	move.l	#$7770000,$ffff8240             ; palette 0, white on black
	bra.w	quit_to_reset                   ; reset
	clr.l	-(sp)                           ; Pterm0 (not reached)
	trap	#1                              ; GEMDOS

;------------------------------------------------------------------------------
; run_module: the module d0 (0 the menu, 1-8) with the calculator's box cleared first.
;------------------------------------------------------------------------------
run_module:	; from: main_menu, disk_ripper, external_call, music_ripper, sample_ripper, memory_ripper, 3 more
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	bsr.w	calculator                      ; the calculator
	moveq	#80,d4
	move.w	#$64,d5
	move.w	#$226,d6
	move.w	#$79,d7
	bsr.w	clear_area                      ; the box
	lea	space_cursor_off,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7/a0-a6
	lea	modules,a0                      ; the modules
	add.w	d0,d0
	add.w	d0,d0                           ; * 4
	movea.l	0(a0,d0.w),a0                   ; its address
	jmp	(a0)                            ; run
modules:
	dc.l	main_menu
	dc.l	picture_ripper_screen
	dc.l	memory_ripper_draw
	dc.l	disk_utility
	dc.l	external_call
	dc.l	external_loader
	dc.l	music_ripper
	dc.l	disk_ripper_module
	dc.l	sample_ripper_redraw

;------------------------------------------------------------------------------
; calculator (Control C): "EXPRESSION :" a op b (op + - * /, numbers in hex, $hex or #decimal, signed),
; then "RESULT : $hex decimal".
;------------------------------------------------------------------------------
calculator:	; from: run_module
	moveq	#80,d4
	move.w	#$64,d5
	move.w	#$21c,d6
	move.w	#$78,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_expression,a0              ; "EXPRESSION :"
	bsr.w	print
	lea	input_buffer,a0                 ; the input buffer
	move.w	#$16,d0                         ; 23 bytes
calculator_clear:
	clr.b	(a0)+                           ; cleared
	dbra	d0,calculator_clear
	move.w	#$1400,input_buffer             ; 20 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	calculator_done                 ; no
	lea	input_buffer+2,a0               ; the text
	bsr.w	parse_number                    ; the first number
	tst.w	d0
	bmi.w	calculator_error                ; bad
	move.l	d2,calc_first                   ; kept
	bsr.w	parse_operator                  ; the operator
	tst.w	d0
	bmi.w	calculator_error                ; bad
	cmpi.w	#$5,calc_operator               ; none (the end)?
	beq.s	calculator_result               ; yes: the number alone
	bsr.w	parse_number                    ; the second number
	tst.w	d0
	bmi.w	calculator_error                ; bad
	tst.w	d2                              ; 0?
	bne.s	calculator_second               ; no
	cmpi.w	#$4,calc_operator               ; a division?
	beq.w	calculator_done                 ; yes: nothing
calculator_second:
	move.l	d2,calc_second                  ; kept
	bsr.w	calculate                       ; worked out
calculator_result:
	bsr.w	print_result                    ; "RESULT :"
	bsr.w	get_key                         ; a key
calculator_done:
	rts
calculator_error:
	lea	text_syntax_error,a0            ; "SYNTAX ERROR !!!!!"
	bsr.w	print
	bsr.w	get_key                         ; a key
	bra.w	calculator                      ; again

;------------------------------------------------------------------------------
; parse_number: a number at a0: '-' or '+', then '#' decimal or '$'/nothing hex.  d2 the value, d0 0 or -1.
;------------------------------------------------------------------------------
parse_number:	; from: calculator
	move.w	#$0,number_negative             ; not negative
	cmpi.b	#$2d,(a0)                       ; '-'?
	bne.w	parse_number_plus               ; no
	move.w	#$1,number_negative             ; negative
	addq.l	#1,a0
	bra.w	parse_number_negative
parse_number_plus:
	cmpi.b	#$2b,(a0)                       ; '+'?
	bne.w	parse_number_unsigned           ; no
	addq.l	#1,a0
parse_number_unsigned:
	bra.w	parse_number_kind
parse_number_negative:
	cmpi.b	#$23,(a0)                       ; '#'?
	beq.w	parse_decimal                   ; decimal
	cmpi.b	#$24,(a0)                       ; '$'?
	bne.w	parse_number_hex_go             ; no
	addq.l	#1,a0
parse_number_hex_go:
	bra.w	parse_hex                       ; hex
parse_number_kind:
	cmpi.b	#$23,(a0)                       ; '#'?
	beq.w	parse_decimal                   ; decimal
	cmpi.b	#$24,(a0)                       ; '$'?
	bne.w	parse_number_hex_go             ; no
	addq.l	#1,a0
	bra.w	parse_hex                       ; hex
parse_decimal:
	addq.l	#1,a0
	moveq	#0,d0
	move.b	(a0)+,d0                        ; the first digit
	subi.w	#$30,d0
	bmi.w	parse_number_bad                ; none: bad
	cmp.w	#$9,d0
	bgt.w	parse_number_bad
	moveq	#0,d2
	move.w	d0,d2
parse_decimal_digit:
	moveq	#0,d0
	move.b	(a0)+,d0                        ; the next
	subi.w	#$30,d0
	bmi.w	parse_decimal_end               ; the end
	cmp.w	#$9,d0
	bgt.w	parse_decimal_end
	move.l	d2,d1
	add.l	d2,d2                           ; *2
	lsl.l	#3,d1                           ; *8
	add.l	d1,d2                           ; *10
	add.l	d0,d2                           ; + the digit
	bra.s	parse_decimal_digit
parse_decimal_end:
	subq.l	#1,a0                           ; back to the end
	moveq	#0,d0
	tst.w	number_negative                 ; negative?
	beq.s	parse_number_done               ; no
	move.l	d2,d1
	moveq	#0,d2
	sub.l	d1,d2                           ; negated
parse_number_done:
	rts
parse_hex:
	moveq	#0,d0
	moveq	#0,d2
	move.b	(a0)+,d0                        ; the first
	lea	hex_digit_pairs,a5              ; the hex digits
parse_hex_first:
	tst.b	(a5)                            ; the table's end?
	bmi.w	parse_number_bad                ; yes: bad
	cmp.b	(a5),d0                         ; this one?
	beq.s	parse_hex_first_found           ; yes
	addq.l	#2,a5
	bra.s	parse_hex_first
parse_hex_first_found:
	move.b	1(a5),d2                        ; its value
parse_hex_next:
	moveq	#0,d0
	move.b	(a0)+,d0                        ; the next
	lea	hex_digit_pairs,a5
parse_hex_find:
	tst.b	(a5)                            ; the table's end?
	bmi.w	parse_hex_end                   ; yes: the end
	cmp.b	(a5),d0                         ; this one?
	beq.s	parse_hex_found                 ; yes
	addq.l	#2,a5
	bra.s	parse_hex_find
parse_hex_found:
	move.b	1(a5),d0
	lsl.l	#4,d2
	or.w	d0,d2                           ; in
	bra.s	parse_hex_next
parse_hex_end:
	moveq	#0,d0
	subq.l	#1,a0                           ; back to the end
	tst.w	number_negative                 ; negative?
	beq.s	parse_hex_done                  ; no
	move.l	d2,d1
	moveq	#0,d2
	sub.l	d1,d2                           ; negated
parse_hex_done:
	rts
parse_number_bad:
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; parse_operator: the operator at a0 into calc_operator: 1 +, 2 -, 3 *, 4 /, 5 the end.
;------------------------------------------------------------------------------
parse_operator:	; from: calculator
	move.w	#$0,calc_operator               ; none
	move.b	(a0)+,d0                        ; the character
	cmp.b	#$2b,d0                         ; '+'?
	bne.s	parse_operator_minus            ; no
	move.w	#$1,calc_operator
	bra.s	parse_operator_ok
parse_operator_minus:
	cmp.b	#$2d,d0                         ; '-'?
	bne.s	parse_operator_times            ; no
	move.w	#$2,calc_operator
	bra.s	parse_operator_ok
parse_operator_times:
	cmp.b	#$2a,d0                         ; '*'?
	bne.s	parse_operator_divide           ; no
	move.w	#$3,calc_operator
parse_operator_ok:
	moveq	#0,d0
	rts
parse_operator_divide:
	cmp.b	#$2f,d0                         ; '/'?
	bne.s	parse_operator_end              ; no
	move.w	#$4,calc_operator
	bra.s	parse_operator_ok
parse_operator_end:
	tst.w	d0                              ; the end?
	bne.s	parse_operator_bad              ; no
	move.w	#$5,calc_operator
	bra.s	parse_operator_ok
parse_operator_bad:
	moveq	#-1,d0                          ; -1
	rts
	rts                                     ; (not reached)

;------------------------------------------------------------------------------
; calculate: d2 = calc_first op calc_second (32-bit multiply and divide, signed).
;------------------------------------------------------------------------------
calculate:	; from: calculator
	cmpi.w	#$1,calc_operator               ; +?
	bne.s	calculate_minus                 ; no
	move.l	calc_first,d0
	move.l	calc_second,d2
	add.l	d0,d2                           ; added
	rts
calculate_minus:
	cmpi.w	#$2,calc_operator               ; -?
	bne.s	calculate_signs                 ; no
	move.l	calc_second,d0
	move.l	calc_first,d2
	sub.l	d0,d2                           ; subtracted
	rts
calculate_signs:
	move.l	calc_first,d0
	move.l	calc_second,d1
	clr.w	calc_first_negative             ; both positive
	clr.w	calc_second_negative
	btst	#$1f,d0                         ; negative?
	beq.s	calculate_sign_second           ; no
	neg.l	d0                              ; made positive
	move.l	d0,calc_first
	move.w	#$ffff,calc_first_negative
calculate_sign_second:
	btst	#$1f,d1                         ; negative?
	beq.s	calculate_multiply              ; no
	neg.l	d1                              ; made positive
	move.l	d1,calc_second
	move.w	#$ffff,calc_second_negative
calculate_multiply:
	cmpi.w	#$3,calc_operator               ; *?
	bne.s	calculate_divide                ; no
	move.l	calc_second,d0
	move.l	d0,d1
	swap	d1                              ; a word?
	tst.w	d1                              ; no
	bne.s	calculate_multiply_long
	move.l	calc_first,d2
	move.l	d2,d1
	mulu.w	d0,d2                           ; low * low
	swap	d1
	mulu.w	d0,d1                           ; high * low
	swap	d1
	clr.w	d1
	add.l	d1,d2
	bra.w	calculate_sign
calculate_multiply_long:
	move.l	calc_first,d2
	mulu.w	d2,d0
	mulu.w	d2,d1
	swap	d1
	clr.w	d1
	add.l	d1,d0
	move.l	d0,d2
	bra.w	calculate_sign
calculate_sign:
	move.w	calc_first_negative,d0          ; the signs
	cmp.w	calc_second_negative,d0         ; the same?
	beq.s	calculate_sign_done             ; yes
	neg.l	d2                              ; negated
calculate_sign_done:
	rts
calculate_divide:
	move.l	calc_second,d0                  ; the divisor
	move.l	calc_first,d2                   ; the dividend
	move.l	d2,d3
	swap	d3
	tst.w	d3                              ; a word?
	beq.s	calculate_divide_word           ; yes
	moveq	#0,d5
	move.l	d2,d1
calculate_divide_shift:
	addq.w	#4,d5
	lsr.l	#4,d1
	move.l	d1,d3
	swap	d3
	tst.w	d3
	bne.s	calculate_divide_shift
	ror.l	d5,d2
	swap	d2
	move.w	d2,d1
	clr.w	d2
	swap	d2
	andi.l	#$ffff,d1
	moveq	#16,d6
	sub.w	d5,d6
	divu.w	d0,d2
	swap	d2
	swap	d1
	add.w	d2,d1
	rol.l	d5,d1
	swap	d2
	divu.w	d0,d1
	ror.w	d5,d1
	swap	d1
	move.w	d2,d1
	rol.l	d5,d1
	moveq	#16,d6
	sub.w	d5,d6
	lsl.l	d6,d1
	lsr.l	d6,d1
	move.l	d1,d2
	bra.w	calculate_sign
calculate_divide_word:
	divu.w	d0,d2
	beq.s	calculate_done
	swap	d2
	clr.w	d2                              ; the quotient
	swap	d2
calculate_done:
	bra.w	calculate_sign

;------------------------------------------------------------------------------
; print_result: "RESULT : $" the value in hex, then in decimal.
;------------------------------------------------------------------------------
print_result:	; from: calculator
	lea	text_result,a0                  ; "RESULT : $"
	bsr.w	print
	movea.l	d2,a6
	move.l	d2,-(sp)
	lea	hex_text,a4                     ; the text
	lea	hex_digits,a5                   ; the digits
	jsr	put_hex_address                 ; in hex
	clr.b	(a4)                            ; ended
	lea	hex_text,a0
	bsr.w	print                           ; printed
	move.l	(sp)+,d2
	lea	position_13_39,a0
	bsr.w	print
	bsr.w	to_decimal                      ; in decimal
	lea	input_buffer+2,a0
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; to_decimal: d2 in decimal digits into input_buffer+2 (from the powers of ten before quit_to_reset).
;------------------------------------------------------------------------------
to_decimal:	; from: print_result
	move.l	d2,d0
	lea	quit_to_reset,a0                ; the powers' end
	lea	input_buffer+2,a1               ; the text
	move.l	-(a0),d2                        ; the largest
	moveq	#0,d1
to_decimal_count:
	cmp.l	d2,d0
	bcs.s	to_decimal_digit
	sub.l	d2,d0
	addi.w	#$1,d1
	bra.s	to_decimal_count
to_decimal_digit:
	addi.w	#$30,d1
	move.b	d1,(a1)+                        ; the digit
	moveq	#0,d1
	cmp.l	#$1,d2                          ; the last?
	beq.w	to_decimal_done                 ; yes
	move.l	-(a0),d2                        ; the next power
	bra.w	to_decimal_count
to_decimal_done:
	clr.b	(a1)                            ; ended
	rts
powers_of_ten:
	dc.w	$0000,$0001,$0000,$000a,$0000,$0064,$0000,$03e8
	dc.w	$0000,$2710,$0001,$86a0,$000f,$4240,$0098,$9680
	dc.w	$05f5,$e100,$3b9a,$ca00

;------------------------------------------------------------------------------
; quit_to_reset: memvalid and resvalid cleared and the ROM's start run after its first jmp: a cold boot.
;------------------------------------------------------------------------------
quit_to_reset:	; from: main_menu, to_decimal
	movea.l	$4.w,a0                         ; the reset address
quit_to_reset_find:
	cmpi.w	#$4ef9,(a0)+                    ; its jmp
	bne.s	quit_to_reset_find
	addq.l	#4,a0                           ; past it
	clr.l	$420.w                          ; memvalid, memvalid
	clr.l	$426.w                          ; resvalid, resvalid
	move.w	#$2700,sr
	reset
	suba.l	a5,a5
	jmp	(a0)

;------------------------------------------------------------------------------
; reserve_memory: the free memory below $10000 taken, so that loads go above.
;------------------------------------------------------------------------------
reserve_memory:	; from: ripper
	move.l	#$ffffffff,-(sp)
	move.w	#$48,-(sp)                      ; Malloc(-1)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	subi.l	#$3e8,d0                        ; less 1000
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	move.l	d0,d7                           ; the block
	move.l	d0,-(sp)
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	move.l	#$10000,d0
	sub.l	d7,d0                           ; up to $10000
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; init_variables: the variables at $D000-$E779 cleared, then the texts (the ESC sequences) and the defaults set.
;------------------------------------------------------------------------------
init_variables:	; from: ripper
	lea	control_line,a0
	lea	variables_end,a1
init_variables_clear:
	clr.b	(a0)+                           ; cleared
	cmpa.l	a1,a0
	bne.s	init_variables_clear
	lea	dump_text,a0                    ; the dump text's head: ESC Y, row 3 column 0, cursor off, right
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$23,(a0)+
	move.b	#$20,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$66,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	lea	picture_width,a0
	move.w	#$140,(a0)                      ; 320
	lea	picture_screen,a0
	move.l	#$10000,d0                      ; $10000
	move.l	d0,(a0)
	lea	ripper_screen,a0
	move.l	d0,(a0)                         ; the ripper's screen
	lea	picture_planes,a0
	move.w	#$4,(a0)                        ; 4 planes
	lea	plane_masks,a0
	move.w	#$ffff,(a0)+                    ; the planes all used
	move.w	#$ffff,(a0)+
	move.w	#$ffff,(a0)+
	move.w	#$ffff,(a0)+
	lea	drive_letter,a0
	move.b	#$41,(a0)                       ; drive 'A'
	lea	raster_pointer,a0
	move.l	#raster_colours,(a0)
	move.w	#$ffff,raster_end
	lea	edit_cursor_text,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$23,(a0)+
	move.b	#$2b,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$65,(a0)+
	clr.b	(a0)
	lea	sample_marker_text,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$23,(a0)+
	move.b	#$42,(a0)+
	move.b	#$3c,(a0)+
	move.b	#$2d,(a0)+
	move.b	#$0,(a0)+
	lea	sample_unmarker_text,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$23,(a0)+
	move.b	#$42,(a0)+
	move.b	#$20,(a0)+
	move.b	#$20,(a0)+
	move.b	#$0,(a0)+
	lea	colour_marker_text,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$25,(a0)+
	move.b	#$68,(a0)+
	move.b	#$3c,(a0)+
	move.b	#$2d,(a0)+
	move.b	#$0,(a0)+
	lea	colour_unmarker_text,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$25,(a0)+
	move.b	#$68,(a0)+
	move.b	#$20,(a0)+
	move.b	#$20,(a0)+
	move.b	#$0,(a0)+
	lea	setting_marker_text,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$25,(a0)+
	move.b	#$4a,(a0)+
	move.b	#$3c,(a0)+
	move.b	#$2d,(a0)+
	move.b	#$0,(a0)+
	lea	setting_unmarker_text,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$25,(a0)+
	move.b	#$4a,(a0)+
	move.b	#$20,(a0)+
	move.b	#$20,(a0)+
	move.b	#$0,(a0)+
	lea	path_line,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$22,(a0)+
	move.b	#$21,(a0)+
	move.b	#$50,(a0)+
	move.b	#$41,(a0)+
	move.b	#$54,(a0)+
	move.b	#$48,(a0)+
	move.b	#$20,(a0)+
	move.b	#$3d,(a0)+
	move.b	#$20,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$66,(a0)+
	move.b	#$41,(a0)+
	move.b	#$3a,(a0)+
	move.b	#$5c,(a0)+
	move.b	#$2a,(a0)+
	move.b	#$2e,(a0)+
	move.b	#$2a,(a0)+
	lea	line_from_x,a0
	move.w	#$1,(a0)+
	move.w	#$1,(a0)+
	move.w	#$1,(a0)+
	move.w	#$1,(a0)+
	move.w	#$a0,(a0)+
	lea	text_normal,a0
	move.w	#$1,(a0)                        ; normal text
	lea	colour_value_text,a0
	move.b	#$1b,(a0)+
	move.b	#$59,(a0)+
	move.b	#$25,(a0)+
	move.b	#$63,(a0)+
	move.b	#$0,(a0)+
	rts
hook_fdc:	; from: vbl_hook
	bsr.w	hook_search                     ; the search hooked
	move.l	$cc.w,-(sp)                     ; then the FDC routine
	rts
hook_timer_c:	; from: vbl_hook
	bsr.w	hook_search                     ; the search hooked
	move.l	$d0.w,-(sp)                     ; then timer C
	rts
hook_gemdos:	; from: vbl_hook
	bsr.w	hook_search                     ; the search hooked
	move.l	$c0.w,-(sp)                     ; then GEMDOS
	rts
hook_xbios:	; from: vbl_hook
	bsr.w	hook_search                     ; the search hooked
	move.l	$c4.w,-(sp)                     ; then XBIOS
	rts

;------------------------------------------------------------------------------
; vbl_hook: the game's first VBL: unless 'RIP ' is in the disk buffer, the VBL, GEMDOS, XBIOS, FDC and timer C
; vectors taken, each calling hook_search first.  Then the game's VBL routine.
;------------------------------------------------------------------------------
vbl_hook:	; from: trace_game
	move.l	a0,-(sp)
	movea.l	$4c6.w,a0                       ; _dskbufp, the disk buffer
	cmpi.l	#$52495020,(a0)                 ; 'RIP '?
	beq.s	vbl_hook_done                   ; yes
	move.l	#vbl_search,$70.w               ; VBL vector, the VBL
	move.l	$84.w,$c0.w                     ; trap #1 (GEMDOS), GEMDOS kept
	move.l	$b8.w,$c4.w                     ; trap #14 (XBIOS), XBIOS kept
	move.l	#hook_gemdos,$84.w              ; trap #1 (GEMDOS), GEMDOS
	move.l	#hook_xbios,$b8.w               ; trap #14 (XBIOS), XBIOS
	move.l	$118.w,$cc.w                    ; MFP FDC/HDC, FDC kept
	move.l	#hook_fdc,$118.w                ; MFP FDC/HDC, FDC
	move.l	$114.w,$d0.w                    ; timer C kept
	move.l	#hook_timer_c,$114.w            ; timer C
vbl_hook_done:
	movea.l	(sp)+,a0
	move.l	$c8.w,-(sp)                     ; the game's VBL
	rts
vbl_search:
	bsr.w	hook_search                     ; the search hooked
	move.l	$c8.w,-(sp)                     ; the game's VBL
	rts

;------------------------------------------------------------------------------
; hook_search: the MFP's ring indicator interrupt (vector $138) set pending and enabled: in_game_search runs
; at once (as an interrupt at level 6 when allowed).
;------------------------------------------------------------------------------
hook_search:	; from: init_variables, vbl_hook
	move.w	sr,-(sp)
	move.w	#$2700,sr                       ; interrupts off
	move.l	#in_game_search,$138.w          ; the vector
	bclr	#$6,$fffffa05.w                 ; MFP DDR, input
	bset	#$6,$fffffa0b.w                 ; MFP IPRA, pending
	bclr	#$6,$fffffa0f.w                 ; MFP ISRA, not in service
	bset	#$6,$fffffa13.w                 ; MFP IMRA, unmasked
	bset	#$6,$fffffa07.w                 ; MFP IERA, enabled
	rte

;------------------------------------------------------------------------------
; in_game_search: the game stopped: its top 8 screen lines and $140-$199 kept in a free part of memory, then
; "F1 : SEARCH & REPLACE    F10 : BACK TO PROGRAM" on its screen, read by scan code.  F10 puts it all back.
;------------------------------------------------------------------------------
in_game_search:	; from: hook_search
	move.w	#$2700,sr
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	move.l	$ffff8240.w,-(sp)               ; palette 0, the palette
	move.b	$fffffa21.w,-(sp)               ; MFP TBDR, timer B's count
	move.l	#$777,$ffff8240.w               ; palette 0, white on black
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.w	#$3,d0
	cmp.b	#$2,d0                          ; high?
	beq.s	in_game_search_screen           ; yes
	move.b	d0,$138.w                       ; kept
	moveq	#1,d0                           ; medium
	bsr.w	set_resolution                  ; set
in_game_search_screen:
	moveq	#0,d0                           ; the screen
	move.b	$ffff8201.w,d0                  ; video base high
	lsl.l	#8,d0
	move.b	$ffff8203.w,d0                  ; video base mid
	lsl.l	#8,d0
	movea.l	d0,a6
	bsr.w	keep_game_screen                ; its top kept
	move.l	d0,-(sp)                        ; where
in_game_search_menu:
	bsr.w	clear_game_line                 ; the line cleared
	lea	text_f1_search_replace,a0       ; "F1 : SEARCH & REPLACE ..."
	bsr.w	draw_line_text
in_game_search_key:
	bsr.w	read_scan_code                  ; a key
	cmp.b	#$3b,d0                         ; F1?
	bne.s	in_game_search_f10              ; no
	bsr.w	search_replace                  ; search and replace
	bra.s	in_game_search_menu
in_game_search_f10:
	cmp.b	#$44,d0                         ; F10?
	bne.s	in_game_search_key              ; no
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.w	#$3,d0
	cmp.b	#$2,d0                          ; high?
	beq.s	in_game_search_back             ; yes
	move.b	$138.w,d0                       ; back
	bsr.w	set_resolution
in_game_search_back:
	move.l	(sp)+,d0
	bsr.w	restore_game_screen             ; the top back
	move.b	(sp)+,d0                        ; timer B's count
in_game_search_wait:
	cmp.b	$fffffa21.w,d0                  ; MFP TBDR
	bne.s	in_game_search_wait             ; wait for it
	move.l	(sp)+,$ffff8240.w               ; palette 0, the palette
	movem.l	(sp)+,d0-d7/a0-a6
	rte

;------------------------------------------------------------------------------
; search_replace: "SEARCH :" and "REPLACE :" typed in hex (at $142 and $16E), packed, then searched from
; $200 to 4 Mb: F1 replaces, F2 goes on, F10 leaves.
;------------------------------------------------------------------------------
search_replace:	; from: in_game_search
	bsr.w	clear_game_line                 ; the line cleared
	lea	text_search_at_ed1b,a0          ; "SEARCH  : "
	bsr.w	draw_line_text
	lea	$144.w,a0                       ; the search text
	bsr.w	input_hex_text                  ; typed
	tst.w	d7                              ; any?
	beq.w	search_replace_done             ; no
	move.w	d7,d6
	move.w	d6,$142.w                       ; its length
	bsr.w	clear_game_line
	lea	text_replace_at_ed2a,a0         ; "REPLACE : "
	bsr.w	draw_line_text
	lea	$170.w,a0
	bsr.w	input_hex_text                  ; typed
	tst.w	d7                              ; any?
	beq.w	search_replace_done             ; no
	move.w	d7,d5                           ; its length
	move.w	d5,$16e
	lea	$140.w,a0                       ; the search
	bsr.w	hex_to_bytes                    ; as bytes
	lea	$16c.w,a0                       ; the replacement
	bsr.w	hex_to_bytes                    ; as bytes
	bsr.w	clear_game_line
	lea	text_search_at_ef03,a0          ; " SEARCH ..."
	bsr.w	draw_line_text
	bsr.w	search_bytes                    ; searched
search_replace_found:
	tst.l	d0                              ; not found?
	bmi.s	search_replace_none             ; yes
	bsr.w	clear_game_line
search_replace_show:
	lea	text_f1_replace_f2,a0           ; "F1 : REPLACE  F2 : CONT  F10 : QUIT  FIND ADDRESS : $"
	bsr.w	draw_line_text
	bsr.w	show_found_address              ; the address
search_replace_key:
	bsr.w	read_scan_code                  ; a key
	cmp.b	#$3b,d0                         ; F1?
	bne.s	search_replace_continue         ; no
	bsr.w	replace_bytes                   ; replaced
	bsr.w	clear_game_line
	lea	text_replace_ok,a0              ; " REPLACE OK !"
	bsr.w	draw_line_text
	bsr.w	read_scan_code                  ; a key
	bra.s	search_replace_show
search_replace_continue:
	cmp.b	#$3c,d0                         ; F2?
	bne.s	search_replace_quit             ; no
	move.l	a2,-(sp)
	bsr.w	clear_game_line
	lea	text_search_at_ef03,a0          ; " SEARCH ..."
	bsr.w	draw_line_text
	movea.l	(sp)+,a2
	addq.l	#1,a2                           ; on from the next
	movea.l	a2,a1
	bsr.w	search_bytes_from               ; searched
	bra.s	search_replace_found
search_replace_quit:
	cmp.b	#$44,d0                         ; F10?
	bne.s	search_replace_key              ; no
	bra.s	search_replace_done
search_replace_none:
	bsr.w	clear_game_line
	lea	text_sorry_not_found_at_ef1d,a0 ; " SORRY NOT FOUND"
	bsr.w	draw_line_text
	bsr.w	read_scan_code                  ; a key
search_replace_done:
	rts

;------------------------------------------------------------------------------
; show_found_address: the address found (a2) in 8 hex digits at the line's end.
;------------------------------------------------------------------------------
show_found_address:	; from: search_replace
	move.l	a2,d0
	lea	hex_digit_texts,a1              ; the digits
	moveq	#3,d1                           ; 4 byte pairs
	movea.l	a6,a5
	move.b	$ffff8260.w,d2                  ; shift mode, the resolution
	andi.w	#$3,d2
	cmp.w	#$2,d2                          ; high?
	beq.s	show_found_address_high         ; yes
	lea	$74(a5),a5                      ; its place
show_found_address_digit:
	rol.l	#4,d0
	move.w	d0,d2
	andi.w	#$f,d2
	add.w	d2,d2
	lea	0(a1,d2.w),a0
	bsr.w	draw_text_at                    ; printed
	addq.l	#1,a5
	rol.l	#4,d0
	move.w	d0,d2
	andi.w	#$f,d2
	add.w	d2,d2
	lea	0(a1,d2.w),a0
	bsr.w	draw_text_at                    ; printed
	addq.l	#3,a5                           ; the next pair
	dbra	d1,show_found_address_digit
	rts
show_found_address_high:
	lea	$3a(a5),a5                      ; its place
show_found_address_high_digit:
	rol.l	#4,d0
	move.w	d0,d2
	andi.w	#$f,d2
	add.w	d2,d2
	lea	0(a1,d2.w),a0
	bsr.w	draw_text_at
	addq.l	#1,a5
	rol.l	#4,d0
	move.w	d0,d2
	andi.w	#$f,d2
	add.w	d2,d2
	lea	0(a1,d2.w),a0
	bsr.w	draw_text_at
	addq.l	#1,a5
	dbra	d1,show_found_address_high_digit
	rts
hex_digit_texts:
	dc.w	$3000,$3100,$3200,$3300,$3400,$3500,$3600,$3700
	dc.w	$3800,$3900,$4100,$4200,$4300,$4400,$4500,$4600

;------------------------------------------------------------------------------
; replace_bytes: the replacement bytes written at the address found.
;------------------------------------------------------------------------------
replace_bytes:	; from: search_replace
	movea.l	a2,a3
	lea	$16e.w,a4                       ; the replacement
	moveq	#0,d0
	move.b	$16d.w,d0                       ; its length
	subq.w	#1,d0
replace_bytes_byte:
	move.b	(a4)+,(a3)+
	dbra	d0,replace_bytes_byte
	rts

;------------------------------------------------------------------------------
; search_bytes: the search bytes looked for from $200 (or from a1): a2 = the place, d0 0 or -1 at 4 Mb.
;------------------------------------------------------------------------------
search_bytes:	; from: search_replace
	lea	$200.w,a1                       ; from $200

search_bytes_from:	; from: search_replace
	moveq	#0,d0
	move.b	$141.w,d0                       ; the length
	lea	$142.w,a0                       ; the bytes
	move.b	(a0)+,d1                        ; the first
search_bytes_find:
	cmpa.l	#$400000,a1                     ; 4 Mb?
	bge.s	search_bytes_none               ; yes
	cmp.b	(a1)+,d1                        ; the first?
	bne.s	search_bytes_find               ; no
	movea.l	a1,a2
search_bytes_rest:
	subq.w	#1,d0
	beq.s	search_bytes_found              ; all?
	move.b	(a0)+,d1
	cmp.b	(a1)+,d1                        ; the next?
	bne.s	search_bytes_from               ; no: on
	bra.s	search_bytes_rest
search_bytes_found:
	subq.l	#1,a2                           ; its start
	moveq	#0,d0
	rts
search_bytes_none:
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; read_scan_code: a key pressed (its scan code) from the keyboard ACIA, the rest of its packet dropped.
;------------------------------------------------------------------------------
read_scan_code:	; from: in_game_search, search_replace, read_hex_key
	moveq	#0,d0
	btst	#$0,$fffffc00.w                 ; keyboard ACIA control, a byte?
	beq.s	read_scan_code                  ; no
	move.b	$fffffc02.w,d0                  ; keyboard ACIA data
	btst	#$7,d0                          ; a release?
	bne.s	read_scan_code                  ; yes: again
read_scan_code_drop:
	btst	#$0,$fffffc00.w                 ; keyboard ACIA control, more?
	beq.s	read_scan_code_done             ; no
	move.b	$fffffc02.w,d1                  ; keyboard ACIA data, dropped
	bra.s	read_scan_code_drop
read_scan_code_done:
	rts

;------------------------------------------------------------------------------
; read_hex_key: a hex digit from its scan code (the row of digits or the keypad, A-F), or Return, Enter or
; Backspace.
;------------------------------------------------------------------------------
read_hex_key:	; from: input_hex_text
	bsr.w	read_scan_code
	cmp.b	#$8,d0                          ; '7'?
	beq.s	read_hex_key_7
	cmp.b	#$67,d0
	bne.s	read_hex_key_8
read_hex_key_7:
	move.b	#$37,d0
	bra.w	read_hex_key_done
read_hex_key_8:
	cmp.b	#$9,d0                          ; '8'?
	beq.s	read_hex_key_8_set
	cmp.b	#$68,d0
	bne.s	read_hex_key_9
read_hex_key_8_set:
	move.b	#$38,d0
	bra.w	read_hex_key_done
read_hex_key_9:
	cmp.b	#$a,d0                          ; '9'?
	beq.s	read_hex_key_9_set
	cmp.b	#$69,d0
	bne.s	read_hex_key_4
read_hex_key_9_set:
	move.b	#$39,d0
	bra.w	read_hex_key_done
read_hex_key_4:
	cmp.b	#$5,d0                          ; '4'?
	beq.s	read_hex_key_4_set
	cmp.b	#$6a,d0
	bne.s	read_hex_key_5
read_hex_key_4_set:
	move.b	#$34,d0
	bra.w	read_hex_key_done
read_hex_key_5:
	cmp.b	#$6,d0                          ; '5'?
	beq.s	read_hex_key_5_set
	cmp.b	#$6b,d0
	bne.s	read_hex_key_6
read_hex_key_5_set:
	move.b	#$35,d0
	bra.w	read_hex_key_done
read_hex_key_6:
	cmp.b	#$7,d0                          ; '6'?
	beq.s	read_hex_key_6_set
	cmp.b	#$6c,d0
	bne.s	read_hex_key_1
read_hex_key_6_set:
	move.b	#$36,d0
	bra.w	read_hex_key_done
read_hex_key_1:
	cmp.b	#$2,d0                          ; '1'?
	beq.s	read_hex_key_1_set
	cmp.b	#$6d,d0
	bne.s	read_hex_key_2
read_hex_key_1_set:
	move.b	#$31,d0
	bra.w	read_hex_key_done
read_hex_key_2:
	cmp.b	#$3,d0                          ; '2'?
	beq.s	read_hex_key_2_set
	cmp.b	#$6e,d0
	bne.s	read_hex_key_3
read_hex_key_2_set:
	move.b	#$32,d0
	bra.w	read_hex_key_done
read_hex_key_3:
	cmp.b	#$4,d0                          ; '3'?
	beq.s	read_hex_key_3_set
	cmp.b	#$6f,d0
	bne.s	read_hex_key_0
read_hex_key_3_set:
	move.b	#$33,d0
	bra.w	read_hex_key_done
read_hex_key_0:
	cmp.b	#$b,d0                          ; '0'?
	beq.s	read_hex_key_0_set
	cmp.b	#$70,d0
	bne.s	read_hex_key_a
read_hex_key_0_set:
	move.b	#$30,d0
	bra.w	read_hex_key_done
read_hex_key_a:
	cmp.b	#$10,d0                         ; 'A'?
	bne.s	read_hex_key_b
	move.b	#$41,d0
	bra.s	read_hex_key_done
read_hex_key_b:
	cmp.b	#$30,d0                         ; 'B'?
	bne.s	read_hex_key_c
	move.b	#$42,d0
	bra.s	read_hex_key_done
read_hex_key_c:
	cmp.b	#$2e,d0                         ; 'C'?
	bne.s	read_hex_key_d
	move.b	#$43,d0
	bra.s	read_hex_key_done
read_hex_key_d:
	cmp.b	#$20,d0                         ; 'D'?
	bne.s	read_hex_key_e
	move.b	#$44,d0
	bra.s	read_hex_key_done
read_hex_key_e:
	cmp.b	#$12,d0                         ; 'E'?
	bne.s	read_hex_key_f
	move.b	#$45,d0
	bra.s	read_hex_key_done
read_hex_key_f:
	cmp.b	#$21,d0                         ; 'F'?
	bne.s	read_hex_key_end
	move.b	#$46,d0
	bra.s	read_hex_key_done
read_hex_key_end:
	cmp.b	#$1c,d0                         ; Return?
	beq.s	read_hex_key_done
	cmp.b	#$72,d0                         ; Enter?
	beq.s	read_hex_key_done
	cmp.b	#$e,d0                          ; Backspace?
	beq.s	read_hex_key_done
	bra.w	read_hex_key                    ; none: again
read_hex_key_done:
	rts

;------------------------------------------------------------------------------
; input_hex_text: up to 40 hex digits typed into a0, shown at the line's column 24: d7 their count.
;------------------------------------------------------------------------------
input_hex_text:	; from: search_replace
	moveq	#0,d7                           ; none yet
	movea.l	a0,a4
input_hex_text_key:
	bsr.w	read_hex_key                    ; a key
	cmp.b	#$1c,d0                         ; Return?
	beq.s	input_hex_text_done
	cmp.b	#$72,d0                         ; Enter?
	beq.s	input_hex_text_done
	cmp.b	#$e,d0                          ; Backspace?
	bne.s	input_hex_text_digit            ; no
	tst.w	d7                              ; any?
	beq.s	input_hex_text_key              ; no
	subq.w	#1,d7
	subq.l	#1,a4                           ; one back
	move.b	#$20,(a4)                       ; a space
	bra.s	input_hex_text_show
input_hex_text_digit:
	move.b	d0,(a4)+                        ; in
	clr.b	(a4)                            ; ended
	addq.w	#1,d7
	cmp.b	#$28,d7                         ; 40?
	beq.s	input_hex_text_done             ; yes
input_hex_text_show:
	movea.l	a6,a5
	lea	$18(a5),a5                      ; column 24
	bsr.w	draw_text_at                    ; shown
	bra.s	input_hex_text_key
input_hex_text_done:
	clr.b	(a4)                            ; ended
	movea.l	a6,a5
	lea	$18(a5),a5
	bsr.w	draw_text_at                    ; shown
	rts

;------------------------------------------------------------------------------
; draw_line_text: the text at a0 drawn at the start of the game's screen (a6).
;------------------------------------------------------------------------------
draw_line_text:	; from: in_game_search, search_replace
	movea.l	a6,a5

;------------------------------------------------------------------------------
; draw_text_at: the text at a0 drawn at a5 in the game's screen, two characters a word pair.
;------------------------------------------------------------------------------
draw_text_at:	; from: show_found_address, input_hex_text
	movem.l	d0-d1/a0-a2/a5,-(sp)            ; saved
draw_text_at_char:
	tst.b	(a0)                            ; the end?
	beq.s	draw_text_at_done               ; yes
	bsr.w	draw_game_char                  ; drawn
	addq.l	#1,a5
	addq.l	#1,a0
	tst.b	(a0)                            ; the end?
	beq.s	draw_text_at_done               ; yes
	bsr.w	draw_game_char                  ; drawn
	move.b	$ffff8260.w,d1                  ; shift mode, the resolution
	andi.w	#$3,d1
	cmp.b	#$2,d1                          ; high?
	bne.s	draw_text_at_medium             ; no
	addq.l	#1,a5                           ; the next byte
	bra.s	draw_text_at_next
draw_text_at_medium:
	addq.l	#3,a5                           ; the next word pair
draw_text_at_next:
	addq.l	#1,a0
	bra.s	draw_text_at_char
draw_text_at_done:
	movem.l	(sp)+,d0-d1/a0-a2/a5
	rts

;------------------------------------------------------------------------------
; draw_game_char: the character at a0 drawn at a5 in the game's screen from the font.
;------------------------------------------------------------------------------
draw_game_char:	; from: draw_text_at
	move.l	a5,-(sp)
	moveq	#0,d0
	move.b	(a0),d0
	subi.b	#$20,d0                         ; from ' '
	mulu.w	#$8,d0                          ; 8 bytes each
	lea	font,a1                         ; the font
	lea	0(a1,d0.w),a1
	moveq	#7,d0                           ; 8 lines
	btst	#$1,$ffff8260.w                 ; shift mode, high?
	bne.s	draw_game_char_high             ; yes
draw_game_char_line:
	move.b	(a1)+,(a5)
	lea	$a0(a5),a5
	dbra	d0,draw_game_char_line
	movea.l	(sp)+,a5
	rts
draw_game_char_high:
	move.b	(a1),(a5)                       ; each line twice
	lea	$50(a5),a5
	move.b	(a1)+,(a5)
	lea	$50(a5),a5
	dbra	d0,draw_game_char_high
	movea.l	(sp)+,a5
	rts

;------------------------------------------------------------------------------
; keep_game_screen: a free (zero) part of memory found from $1000, and $140-$199 and the screen's first $500
; bytes copied there: d0 = it, or -1 if none.
;------------------------------------------------------------------------------
keep_game_screen:	; from: in_game_search
	lea	$1000.w,a0
	lea	$80000,a1                       ; to 512K
keep_game_screen_find:
	move.w	#$559,d0                        ; $55A bytes
	cmpa.l	a1,a0                           ; the end?
	bge.s	keep_game_screen_none           ; yes: none
	tst.b	(a0)+                           ; 0?
	bne.s	keep_game_screen_find           ; no
	movea.l	a0,a2                           ; the start
keep_game_screen_zeros:
	tst.b	(a0)+                           ; 0?
	bne.s	keep_game_screen_find           ; no: again
	subq.w	#1,d0
	bge.s	keep_game_screen_zeros          ; long enough?
	move.l	a2,d0
	subq.l	#1,d0
	movea.l	d0,a1
	move.w	#$59,d1                         ; 90 bytes
	lea	$140.w,a0                       ; from $140
keep_game_screen_low:
	move.b	(a0)+,(a1)+                     ; copied
	dbra	d1,keep_game_screen_low
	movea.l	a6,a0                           ; the screen
	move.w	#$4ff,d1                        ; $500 bytes
keep_game_screen_top:
	move.b	(a0)+,(a1)+                     ; copied
	dbra	d1,keep_game_screen_top
	rts
keep_game_screen_none:
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; restore_game_screen: $140-$199 and the screen's top put back from d0, and that memory cleared again.
;------------------------------------------------------------------------------
restore_game_screen:	; from: in_game_search
	cmp.l	#$ffffffff,d0                   ; none?
	beq.s	restore_game_screen_done        ; yes
	movea.l	d0,a0
	move.w	#$59,d0                         ; 90 bytes
	lea	$140.w,a1                       ; to $140
restore_game_screen_low:
	move.b	(a0),(a1)+
	clr.b	(a0)+                           ; cleared
	dbra	d0,restore_game_screen_low
	movea.l	a6,a1                           ; the screen
	move.w	#$4ff,d0                        ; $500 bytes
restore_game_screen_top:
	move.b	(a0),(a1)+
	clr.b	(a0)+                           ; cleared
	dbra	d0,restore_game_screen_top
restore_game_screen_done:
	rts

;------------------------------------------------------------------------------
; clear_game_line: the game screen's first 8 lines cleared.
;------------------------------------------------------------------------------
clear_game_line:	; from: in_game_search, search_replace
	movea.l	a6,a0
	moveq	#7,d1                           ; 8 lines
clear_game_line_line:
	move.w	#$27,d0
clear_game_line_long:
	clr.l	(a0)+
	dbra	d0,clear_game_line_long
	dbra	d1,clear_game_line_line
	rts

;------------------------------------------------------------------------------
; set_resolution: the resolution d0 set in the vertical blank.
;------------------------------------------------------------------------------
set_resolution:	; from: in_game_search
	lea	$ffff8209.w,a0                  ; video count low, the video counter
set_resolution_wait:
	tst.b	(a0)
	bne.s	set_resolution_wait             ; not 0: wait
	move.b	d0,$ffff8260.w                  ; shift mode, set
	rts

;------------------------------------------------------------------------------
; timer_c_handler: timer C with the IPL at 5, then TOS's timer C.
;------------------------------------------------------------------------------
timer_c_handler:	; from: ripper
	move.w	#$2500,sr
	move.l	saved_timer_c,-(sp)             ; TOS's
	rts

;------------------------------------------------------------------------------
; critical_error_handler: -1 for every critical error (no alert).
;------------------------------------------------------------------------------
critical_error_handler:	; from: ripper
	moveq	#-1,d0
	rts

;------------------------------------------------------------------------------
; media_changed: d0 2 (changed), and hdv_mediach set to say unchanged next time.
;------------------------------------------------------------------------------
media_changed:	; from: force_media_change
	moveq	#2,d0                           ; changed
	move.l	#media_unchanged,$47e.w         ; hdv_mediach
	rts
media_unchanged:
	moveq	#0,d0                           ; unchanged
	rts

;------------------------------------------------------------------------------
; disk_ripper (F7): its screen and boxes, the floppy locked, the drive and track set, then disk_ripper_keys.
; F1 read a track, F2 boot info, F3 sectors, F4..F6, F7 edit the buffer, F8 hex/disassembly, F9 the buffer and
; memory, F10 back; D drive, T track, S sector, I side, P print, the cursor keys and +/- to move.
;------------------------------------------------------------------------------
disk_ripper:	; from: main_menu, module_keys
	jsr	stop_raster                     ; the screen set
	lea	text_disk_ripper_f1readf2writef3searchf4idf5read,a0 ; its title
	bsr.w	print
	moveq	#0,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#12,d7
	bsr.w	draw_box                        ; the top box
	moveq	#14,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#32,d7
	bsr.w	draw_box                        ; the middle box
	moveq	#34,d4
	moveq	#0,d5
	move.w	#$27f,d6
	move.w	#$b4,d7
	bsr.w	draw_box                        ; the bottom box
	move.w	#$ffff,$43e.w                   ; flock, the floppy locked
	bsr.w	select_drive                    ; the menu
	jsr	fdc_restore                     ; the drive set
	clr.w	track_mode                      ; track 0
	clr.w	track
	clr.w	head_track
	clr.w	side                            ; side 0
	move.w	#$1,sector                      ; sector 1
	clr.w	buffer_length                   ; not in hex
	bsr.w	show_disk_settings              ; the settings shown
	moveq	#64,d0                          ; F6
	bra.w	disk_ripper_function_key
disk_ripper_keys:                               ; from: toggle_hex_disassembly, change_drive, set_track, set_sector,
                                                ;   toggle_side, edit_buffer, 8 more
	bsr.w	get_key                         ; a key
	clr.w	$43e.w                          ; flock, unlocked meanwhile
	cmp.b	#$3,d0                          ; Control C?
	bne.s	disk_ripper_key                 ; no
	moveq	#7,d0                           ; the calculator, then here
	bra.w	run_module
disk_ripper_key:
	moveq	#7,d1
	bsr.w	module_keys                     ; the help line
	move.w	#$ffff,$43e.w                   ; flock, locked
	cmp.l	#$4e000b,d0                     ; Control N?
	beq.w	next_track                      ; the next track
	cmp.l	#$4a001f,d0                     ; Control J?
	beq.w	previous_track                  ; the track before
	cmp.b	#$2b,d0                         ; '+'?
	beq.w	next_sector                     ; the next sector
	cmp.b	#$2d,d0                         ; '-'?
	beq.w	previous_sector                 ; the sector before
	cmp.b	#$64,d0                         ; 'd'?
	beq.w	change_drive
	cmp.b	#$44,d0                         ; 'D'?
	beq.w	change_drive                    ; the drive
	cmp.b	#$74,d0                         ; 't'?
	beq.w	set_track
	cmp.b	#$54,d0                         ; 'T'?
	beq.w	set_track                       ; the track
	cmp.b	#$73,d0                         ; 's'?
	beq.w	set_sector
	cmp.b	#$53,d0                         ; 'S'?
	beq.w	set_sector                      ; the sector
	cmp.b	#$69,d0                         ; 'i'?
	beq.w	toggle_side
	cmp.b	#$49,d0                         ; 'I'?
	beq.w	toggle_side                     ; the side
	cmp.b	#$70,d0                         ; 'p'?
	bne.s	disk_ripper_print               ; no
	bsr.w	print_buffer                    ; printed
	bra.w	disk_ripper_keys
disk_ripper_print:
	cmp.b	#$50,d0                         ; 'P'?
	bne.s	disk_ripper_function            ; no
	bsr.w	print_buffer                    ; printed
	bra.w	disk_ripper_keys
disk_ripper_function:
	cmp.l	#$610000,d0                     ; Shift Home?
	bne.s	disk_ripper_scan                ; no
	move.l	#$500032,d0                     ; as right
disk_ripper_scan:
	swap	d0                              ; its scan code
disk_ripper_function_key:
	cmp.b	#$3b,d0                         ; F1?
	beq.w	read_sectors                    ; read a track
	cmp.b	#$3c,d0                         ; F2?
	beq.w	write_sector                    ; boot info
	cmp.b	#$3d,d0                         ; F3?
	beq.w	disk_search
	cmp.b	#$3e,d0                         ; F4?
	beq.w	track_info
	cmp.b	#$3f,d0                         ; F5?
	beq.w	read_track
	cmp.b	#$40,d0                         ; F6?
	beq.w	boot_info
	cmp.b	#$41,d0                         ; F7?
	beq.w	edit_buffer                     ; edit the buffer
	cmp.b	#$42,d0                         ; F8?
	beq.w	toggle_hex_disassembly          ; hex or disassembly
	cmp.b	#$43,d0                         ; F9?
	beq.w	buffer_memory_menu              ; the buffer and memory
	cmp.l	#$320050,d0                     ; Shift down?
	beq.w	page_down_buffer                ; a page down
	cmp.l	#$380048,d0                     ; Shift up?
	beq.w	page_up_buffer                  ; a page up
	cmp.w	#$50,d0                         ; down?
	beq.w	line_down_buffer                ; a line down
	cmp.w	#$48,d0                         ; up?
	beq.w	line_up_buffer                  ; a line up
	cmp.b	#$44,d0                         ; F10?
	bne.w	disk_ripper_keys                ; no: another key
	clr.w	$43e.w                          ; flock, unlocked
	bra.w	main_menu                       ; the main menu

;------------------------------------------------------------------------------
; buffer_memory_menu (F9): F1 memory to the disk buffer, F2 the disk buffer to memory.
;------------------------------------------------------------------------------
buffer_memory_menu:	; from: disk_ripper
	moveq	#80,d4
	move.w	#$c8,d5
	move.w	#$1e0,d6
	move.w	#$78,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_f1_memory_disk,a0          ; the menu
	bsr.w	print
buffer_memory_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; escape?
	beq.w	buffer_memory_done              ; yes
	swap	d0
	cmp.b	#$3b,d0                         ; F1?
	beq.w	memory_to_buffer                ; memory to the buffer
	cmp.b	#$3c,d0                         ; F2?
	beq.w	buffer_to_memory                ; the buffer to memory
	bra.w	buffer_memory_key
buffer_memory_done:
	bra.w	show_buffer                     ; back
memory_to_buffer:
	moveq	#90,d4
	move.w	#$d2,d5
	move.w	#$1d6,d6
	move.w	#$6e,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_start_address_at_e9c4,a0   ; "COPY ADDRESS : $"
	bsr.w	print
	move.w	#$800,input_buffer              ; 8 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	buffer_memory_done              ; no
	bsr.w	hex_from_input                  ; the address
	tst.l	d0                              ; bad?
	bmi.w	buffer_memory_done              ; yes
	movea.l	d2,a0
	move.w	buffer_length,d0                ; the buffer's length
	subq.w	#1,d0
	lea	disk_buffer,a1                  ; the buffer
memory_to_buffer_copy:
	move.b	(a0)+,(a1)+                     ; copied
	dbra	d0,memory_to_buffer_copy
	bra.w	buffer_memory_done
buffer_to_memory:
	moveq	#90,d4
	move.w	#$c8,d5
	move.w	#$1e0,d6
	move.w	#$6e,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_copy_address_at_e9ac,a0    ; "START ADDRESS : $"
	bsr.w	print
	move.w	#$800,input_buffer              ; 8 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	buffer_memory_done              ; no
	bsr.w	hex_from_input                  ; the address
	tst.l	d0                              ; bad?
	bmi.w	buffer_memory_done              ; yes
	cmp.l	#$17d00,d2                      ; above $17D00?
	bge.s	buffer_to_memory_copy           ; yes
	lea	text_address_17d00_y,a0         ; "ADDRESS < $17D00 ? (Y/N)"
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$79,d0                         ; 'y'?
	beq.s	buffer_to_memory_copy
	cmp.b	#$59,d0                         ; 'Y'?
	beq.s	buffer_to_memory_copy
	cmp.b	#$6e,d0                         ; 'n'?
	beq.w	buffer_memory_done
	cmp.b	#$4e,d0                         ; 'N'?
	beq.w	buffer_memory_done
	bra.w	buffer_memory_done
buffer_to_memory_copy:
	movea.l	d2,a0
	move.w	buffer_length,d0                ; the buffer's length
	subq.w	#1,d0
	lea	disk_buffer,a1                  ; the buffer
buffer_to_memory_byte:
	move.b	(a1)+,(a0)+                     ; copied
	dbra	d0,buffer_to_memory_byte
	bra.w	buffer_memory_done

;------------------------------------------------------------------------------
; toggle_hex_disassembly (F8): the buffer shown in hex or disassembled; for hex the view kept on 16 bytes
; and within the buffer's last 256.
;------------------------------------------------------------------------------
toggle_hex_disassembly:	; from: disk_ripper
	not.w	disassembly_view                ; changed
	tst.w	disassembly_view                ; hex?
	bne.s	toggle_hex_done                 ; no
	move.l	buffer_view,d0                  ; the view
	movea.l	d0,a0
	subi.l	#disk_buffer,d0                 ; from the buffer
	andi.w	#$f,d0                          ; on 16
	suba.w	d0,a0
	lea	disk_buffer,a1                  ; the buffer
	tst.w	buffer_length                   ; any read?
	bne.s	toggle_hex_end                  ; yes
	lea	disk_buffer,a0                  ; no: its start
	bra.s	toggle_hex_set
toggle_hex_end:
	adda.w	buffer_length,a1                ; its end
	suba.l	#$100,a1                        ; less 256
	cmpa.l	a0,a1                           ; past?
	ble.s	toggle_hex_last                 ; no
	bra.s	toggle_hex_set
toggle_hex_last:
	movea.l	a1,a0                           ; the last 256
toggle_hex_set:
	move.l	a0,buffer_view
toggle_hex_done:
	bsr.w	draw_buffer                     ; shown
	bra.w	disk_ripper_keys

;------------------------------------------------------------------------------
; print_buffer (P): the disk buffer to the printer, as a hex dump or a disassembly.
;------------------------------------------------------------------------------
print_buffer:	; from: disk_ripper
	move.w	#$11,-(sp)
	trap	#1                              ; Cprnos
	addq.l	#2,sp
	tst.l	d0                              ; ready?
	beq.w	print_buffer_not_ready          ; no
	lea	text_please_wait_printing,a0    ; "PLEASE WAIT ... PRINTING ..."
	bsr.w	print
	tst.w	disassembly_view                ; disassembly?
	bne.w	print_buffer_disassembly        ; yes
	jsr	printer_new_line                ; a new line
	lea	disk_buffer,a6                  ; the buffer
	movea.l	a6,a5
	adda.w	buffer_length,a5                ; its end
	subq.l	#1,a5
	move.l	a5,range_end
	bsr.w	print_dump                      ; printed
	rts
print_buffer_not_ready:
	lea	text_printer_not_ready,a0       ; "PRINTER NOT READY !"
	bsr.w	print
	bsr.w	get_key                         ; a key
	lea	position_24_0_at_e30e,a0        ; the line cleared
	bsr.w	print
	rts
print_buffer_disassembly:
	bsr.w	printer_new_line                ; a new line
	move.l	buffer_view,-(sp)               ; the view kept
	movea.l	#disk_buffer,a5                 ; from the buffer's start
	move.l	a5,buffer_view
	adda.w	buffer_length,a5                ; its end
	subq.l	#1,a5
	move.l	a5,range_end
print_buffer_page:
	movea.l	buffer_view,a5
	cmpa.l	range_end,a5                    ; the end?
	bge.w	print_buffer_done               ; yes
	lea	dump_lines,a6                   ; the text
	move.b	#$b,(a6)+                       ; $0B, CR, right
	move.b	#$d,(a6)+
	move.b	#$1b,(a6)+
	move.b	#$43,(a6)+
	moveq	#15,d1                          ; 16 lines
print_buffer_line:
	moveq	#77,d0                          ; 78 spaces
print_buffer_space:
	move.b	#$20,(a6)+
	dbra	d0,print_buffer_space
	move.b	#$b,(a6)+                       ; $0B, CR, right
	move.b	#$d,(a6)+
	move.b	#$1b,(a6)+
	move.b	#$43,(a6)+
	dbra	d1,print_buffer_line
	lea	dump_lines+4,a6
	movea.l	buffer_view,a5
	bsr.w	disassemble_buffer              ; 16 lines disassembled
	move.l	a5,buffer_view
	pea	dump_lines                      ; the text
	move.l	#$500,-(sp)                     ; $500 bytes
	move.w	#$3,-(sp)                       ; the printer
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	bra.w	print_buffer_page               ; the next page
print_buffer_done:
	move.l	(sp)+,buffer_view               ; the view back
	lea	position_24_0_at_e30e,a0        ; the line cleared
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; draw_buffer_disassembly: 16 lines of the buffer disassembled from the view, printed in the middle box.
;------------------------------------------------------------------------------
draw_buffer_disassembly:	; from: draw_buffer
	lea	dump_lines,a6                   ; the text
	move.b	#$1b,(a6)+                      ; ESC Y row 5 column 0, cursor off, right
	move.b	#$59,(a6)+
	move.b	#$25,(a6)+
	move.b	#$20,(a6)+
	move.b	#$1b,(a6)+
	move.b	#$66,(a6)+
	move.b	#$1b,(a6)+
	move.b	#$43,(a6)+
	move.l	a6,-(sp)
	moveq	#15,d1                          ; 16 lines
draw_buffer_disassembly_line:
	moveq	#77,d0                          ; 78 spaces
draw_buffer_disassembly_space:
	move.b	#$20,(a6)+
	dbra	d0,draw_buffer_disassembly_space
	move.b	#$b,(a6)+                       ; $0B, CR, right
	move.b	#$d,(a6)+
	move.b	#$1b,(a6)+
	move.b	#$43,(a6)+
	dbra	d1,draw_buffer_disassembly_line
	move.b	#$0,(a6)+                       ; ended
	movea.l	(sp)+,a6
	movea.l	buffer_view,a5                  ; the view
	bsr.w	disassemble_buffer              ; disassembled
	lea	dump_lines,a0
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; disassemble_buffer: 16 lines from a5 into the text at a6: the offset in the buffer, then the instruction; it
; stops at the buffer's end.
;------------------------------------------------------------------------------
disassemble_buffer:	; from: print_buffer, draw_buffer_disassembly
	clr.w	line_count                      ; no lines yet
disassemble_buffer_next:
	move.l	a6,-(sp)
	movem.l	a0-a5,-(sp)                     ; saved
	movea.l	a6,a4
	movea.l	a5,a6
	suba.l	#disk_buffer,a6                 ; the offset
	cmpa.w	buffer_length,a6                ; past the end?
	bge.s	disassemble_buffer_end          ; yes
	lea	hex_digits,a5                   ; the digits
	bsr.w	put_hex_address                 ; printed
	move.b	#$20,(a4)+                      ; two spaces
	move.b	#$20,(a4)+
	movea.l	a4,a6
	movem.l	(sp)+,a0-a5
	movea.l	a5,a4
	bsr.w	dis_instruction                 ; disassembled
	lea	2(a4),a5
	bsr.w	dis_end                         ; its operands
	move.b	#$20,(a6)
	movea.l	(sp)+,a6
	lea	$52(a6),a6                      ; the next line
	addq.w	#1,line_count
	cmpi.w	#$10,line_count                 ; 16?
	bne.s	disassemble_buffer_next         ; no
	clr.b	(a6)+                           ; ended
	rts
disassemble_buffer_end:
	movem.l	(sp)+,a0-a5
	movea.l	(sp)+,a6
	rts

;------------------------------------------------------------------------------
; change_drive (D): A and B in turn when there are two drives.
;------------------------------------------------------------------------------
change_drive:	; from: disk_ripper
	cmpi.w	#$1,$4a6.w                      ; _nflops, two drives?
	ble.s	change_drive_set                ; no
	cmpi.b	#$41,drive_letter               ; A?
	beq.s	change_drive_b                  ; yes
	move.b	#$41,drive_letter
	bra.s	change_drive_set
change_drive_b:
	move.b	#$42,drive_letter               ; B
change_drive_set:
	bsr.w	select_drive                    ; the menu
	jsr	fdc_restore                     ; the drive set
	clr.w	track                           ; track 0
	clr.w	head_track
	clr.w	side                            ; side 0
	bsr.w	show_disk_settings              ; shown
	bra.w	disk_ripper_keys

;------------------------------------------------------------------------------
; set_track (T): the track typed in hex (up to $51).
;------------------------------------------------------------------------------
set_track:	; from: disk_ripper
	lea	position_3_33,a0                ; "RACK : $"
	bsr.w	print
	lea	input_buffer,a0                 ; cursor on
	move.b	#$1b,(a0)
	move.b	#$65,1(a0)
	clr.b	2(a0)
	bsr.w	print
	move.w	#$200,input_buffer              ; 2 characters
	bsr.w	input_hex
	tst.l	d0                              ; given?
	bmi.s	set_track_done                  ; no
	cmp.w	#$51,d2                         ; up to $51?
	bgt.s	set_track_done                  ; no
	move.w	d2,track                        ; the track
set_track_done:
	bsr.w	show_disk_settings              ; shown
	bra.w	disk_ripper_keys

;------------------------------------------------------------------------------
; set_sector (S): the sector typed in hex.
;------------------------------------------------------------------------------
set_sector:	; from: disk_ripper
	lea	position_3_54_at_eec6,a0        ; "ECTOR : $"
	bsr.w	print
	lea	input_buffer,a0                 ; cursor on
	move.b	#$1b,(a0)
	move.b	#$65,1(a0)
	clr.b	2(a0)
	bsr.w	print
	move.w	#$200,input_buffer              ; 2 characters
	bsr.w	input_hex
	tst.l	d0                              ; given?
	bmi.s	set_sector_done                 ; no
	move.w	d2,sector                       ; the sector
set_sector_done:
	bsr.w	show_disk_settings              ; shown
	bra.w	disk_ripper_keys

;------------------------------------------------------------------------------
; toggle_side (I): side 0 or 1.
;------------------------------------------------------------------------------
toggle_side:	; from: disk_ripper
	not.w	side
	bsr.w	show_disk_settings              ; shown
	bra.w	disk_ripper_keys

;------------------------------------------------------------------------------
; show_buffer_length: "LENGTH : $" the bytes in the buffer.
;------------------------------------------------------------------------------
show_buffer_length:	; from: show_buffer, disk_search, read_track
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	lea	text_length,a0                  ; "LENGTH : $"
	bsr.w	print
	movea.w	buffer_length,a6                ; the length
	lea	hex_text,a4                     ; the text
	lea	hex_digits,a5                   ; the digits
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)                            ; ended
	lea	hex_text+4,a0                   ; the last 4 digits
	bsr.w	print
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; edit_buffer (F7): the hex dump edited in place: the cursor keys move, hex digits change nibbles; TAB goes to the
; characters (typed straight in), escape leaves.  Only in hex view, with data in the buffer.
;------------------------------------------------------------------------------
edit_buffer:	; from: disk_ripper
	tst.w	buffer_length                   ; data?
	beq.w	disk_ripper_keys                ; no
	tst.w	disassembly_view                ; hex view?
	bne.w	disk_ripper_keys                ; no
	tst.w	track_mode
	bne.w	disk_ripper_keys
	move.b	#$25,edit_cursor_text+2         ; row 5
	move.b	#$2b,edit_cursor_text+3         ; column 11
edit_buffer_hex:	; from: disk_search
	lea	edit_cursor_text,a0             ; the cursor placed
	bsr.w	print
edit_buffer_hex_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; escape?
	beq.s	edit_buffer_done                ; yes
	cmp.b	#$9,d0                          ; TAB?
	beq.s	edit_buffer_to_chars            ; the characters
	swap	d0
	cmp.b	#$50,d0                         ; down?
	beq.w	edit_buffer_hex_down
	cmp.b	#$48,d0                         ; up?
	beq.w	edit_buffer_hex_up
	cmp.b	#$4b,d0                         ; left?
	beq.w	edit_buffer_hex_left
	cmp.b	#$4d,d0                         ; right?
	beq.w	edit_buffer_hex_right
	swap	d0
	cmp.w	#$20,d0                         ; a character?
	bge.w	edit_buffer_digit               ; a digit
	bra.s	edit_buffer_hex_key
edit_buffer_done:
	bsr.w	draw_buffer                     ; the screen again
	bra.w	disk_ripper_keys
edit_buffer_to_chars:	; from: disk_search
	moveq	#0,d0                           ; the hex column
	move.b	edit_cursor_text+3,d0
	subi.b	#$2b,d0
	divu.w	#$3,d0                          ; / 3: the byte
	addi.b	#$5d,d0                         ; its character column (93 up)
	move.b	d0,edit_cursor_text+3
edit_buffer_chars:
	lea	edit_cursor_text,a0             ; the cursor placed
	bsr.w	print
edit_buffer_chars_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; escape?
	beq.s	edit_buffer_chars_done          ; yes
	cmp.b	#$9,d0                          ; TAB?
	beq.w	edit_buffer_to_hex              ; the hex
	swap	d0
	cmp.b	#$50,d0                         ; down?
	beq.w	edit_buffer_chars_down
	cmp.b	#$48,d0                         ; up?
	beq.w	edit_buffer_chars_up
	cmp.b	#$4b,d0                         ; left?
	beq.w	edit_buffer_chars_left
	cmp.b	#$4d,d0                         ; right?
	beq.w	edit_buffer_chars_right
	swap	d0
	cmp.w	#$20,d0                         ; a character?
	bge.w	edit_buffer_char                ; yes
	bra.s	edit_buffer_chars_key
edit_buffer_chars_done:
	bsr.w	draw_buffer
	bra.w	disk_ripper_keys
edit_buffer_to_hex:
	moveq	#0,d0                           ; the character column
	move.b	edit_cursor_text+3,d0
	subi.w	#$5d,d0
	mulu.w	#$3,d0                          ; * 3
	addi.b	#$2b,d0                         ; the hex column (43 up)
	move.b	d0,edit_cursor_text+3
	bra.w	edit_buffer_hex
edit_buffer_chars_down:
	cmpi.b	#$34,edit_cursor_text+2         ; the last row?
	beq.w	edit_buffer_chars_wrap_down     ; yes
	addq.b	#1,edit_cursor_text+2           ; down
	bra.w	edit_buffer_chars
edit_buffer_chars_wrap_down:
	move.b	#$25,edit_cursor_text+2         ; the first row
	bra.w	edit_buffer_chars
edit_buffer_chars_up:
	cmpi.b	#$25,edit_cursor_text+2         ; the first row?
	beq.w	edit_buffer_chars_wrap_up       ; yes
	subq.b	#1,edit_cursor_text+2           ; up
	bra.w	edit_buffer_chars
edit_buffer_chars_wrap_up:
	move.b	#$34,edit_cursor_text+2         ; the last row
	bra.w	edit_buffer_chars
edit_buffer_chars_left:
	cmpi.b	#$5d,edit_cursor_text+3         ; the first column?
	beq.w	edit_buffer_chars_wrap_left     ; yes
	subq.b	#1,edit_cursor_text+3           ; left
	bra.w	edit_buffer_chars
edit_buffer_chars_wrap_left:
	move.b	#$6c,edit_cursor_text+3         ; the last column
	bra.w	edit_buffer_chars_up            ; and up
edit_buffer_chars_right:
	cmpi.b	#$6c,edit_cursor_text+3         ; the last column?
	beq.s	edit_buffer_chars_wrap_right    ; yes
	addq.b	#1,edit_cursor_text+3           ; right
	bra.w	edit_buffer_chars
edit_buffer_chars_wrap_right:
	move.b	#$5d,edit_cursor_text+3         ; the first column
	bra.w	edit_buffer_chars_down          ; and down
edit_buffer_char:
	move.w	d0,d6                           ; the character
	move.l	a0,-(sp)
	lea	input_buffer+2,a0
	move.b	d0,(a0)
	clr.b	1(a0)                           ; ended
	bsr.w	print                           ; shown
	movea.l	(sp)+,a0
	movea.l	buffer_view,a6                  ; the view
	moveq	#0,d1
	move.b	edit_cursor_text+3,d1           ; the column
	subi.w	#$5d,d1
	adda.w	d1,a6
	move.b	edit_cursor_text+2,d1           ; the row
	subi.w	#$25,d1
	mulu.w	#$10,d1                         ; 16 bytes a row
	adda.w	d1,a6
	move.b	d6,(a6)                         ; written
	nop
	nop
	cmpi.b	#$6c,edit_cursor_text+3         ; the last column?
	beq.w	edit_buffer_char_wrap           ; yes
	addq.b	#1,edit_cursor_text+3           ; right
	bra.w	edit_buffer_chars
edit_buffer_char_wrap:
	move.b	#$5d,edit_cursor_text+3         ; the first column
	cmpi.b	#$34,edit_cursor_text+2         ; the last row?
	beq.s	edit_buffer_char_top            ; yes
	addq.b	#1,edit_cursor_text+2           ; down
	bra.w	edit_buffer_chars
edit_buffer_char_top:
	move.b	#$25,edit_cursor_text+2         ; the first row
	bra.w	edit_buffer_chars
edit_buffer_hex_down:
	cmpi.b	#$34,edit_cursor_text+2         ; the last row?
	beq.s	edit_buffer_hex_wrap_down       ; yes
	addq.b	#1,edit_cursor_text+2           ; down
	bra.w	edit_buffer_hex
edit_buffer_hex_wrap_down:
	move.b	#$25,edit_cursor_text+2         ; the first row
	bra.w	edit_buffer_hex
edit_buffer_hex_up:
	cmpi.b	#$25,edit_cursor_text+2         ; the first row?
	beq.s	edit_buffer_hex_wrap_up         ; yes
	subq.b	#1,edit_cursor_text+2           ; up
	bra.w	edit_buffer_hex
edit_buffer_hex_wrap_up:
	move.b	#$34,edit_cursor_text+2         ; the last row
	bra.w	edit_buffer_hex
edit_buffer_hex_left:
	cmpi.b	#$2b,edit_cursor_text+3         ; the first byte?
	beq.s	edit_buffer_hex_wrap_left       ; yes
	subq.b	#3,edit_cursor_text+3           ; a byte left
	bra.w	edit_buffer_hex
edit_buffer_hex_wrap_left:
	move.b	#$58,edit_cursor_text+3         ; the last byte
	bra.w	edit_buffer_hex_up              ; and up
edit_buffer_hex_right:
	cmpi.b	#$58,edit_cursor_text+3         ; the last byte?
	beq.s	edit_buffer_hex_wrap_right      ; yes
	addq.b	#3,edit_cursor_text+3           ; a byte right
	bra.w	edit_buffer_hex
edit_buffer_hex_wrap_right:
	move.b	#$2b,edit_cursor_text+3         ; the first byte
	bra.w	edit_buffer_hex_down            ; and down
edit_buffer_digit:
	lea	hex_digit_pairs,a0              ; the hex digits
edit_buffer_digit_find:
	cmp.b	(a0),d0                         ; this one?
	beq.s	edit_buffer_digit_high          ; yes
	addq.l	#2,a0
	tst.b	(a0)                            ; the table's end?
	bge.s	edit_buffer_digit_find          ; no
	bra.w	edit_buffer_hex                 ; not a digit
edit_buffer_digit_high:
	cmp.b	#$61,d0                         ; small?
	blt.s	edit_buffer_digit_show          ; no
	subi.b	#$20,d0                         ; in capitals
edit_buffer_digit_show:
	move.l	a0,-(sp)
	lea	input_buffer+2,a0
	move.b	d0,(a0)
	clr.b	1(a0)                           ; ended
	bsr.w	print                           ; shown
	movea.l	(sp)+,a0
	move.b	1(a0),d0                        ; its value
	movea.l	buffer_view,a6                  ; the view
	moveq	#0,d1
	move.b	edit_cursor_text+3,d1           ; the column
	subi.w	#$2b,d1
	divu.w	#$3,d1                          ; / 3: the byte
	adda.w	d1,a6
	move.b	edit_cursor_text+2,d1           ; the row
	subi.w	#$25,d1
	mulu.w	#$10,d1                         ; 16 bytes a row
	adda.w	d1,a6
	lsl.w	#4,d0                           ; the high nibble
	andi.b	#$f,(a6)
	or.b	d0,(a6)                         ; set
	bsr.w	get_key                         ; the second digit
	lea	hex_digit_pairs,a0
edit_buffer_digit_low_find:
	cmp.b	(a0),d0                         ; this one?
	beq.s	edit_buffer_digit_low           ; yes
	addq.l	#2,a0
	tst.b	(a0)                            ; the table's end?
	bge.s	edit_buffer_digit_low_find      ; no
	bra.w	edit_buffer_hex                 ; not a digit
edit_buffer_digit_low:
	cmp.b	#$61,d0                         ; small?
	blt.s	edit_buffer_digit_low_show      ; no
	subi.b	#$20,d0                         ; in capitals
edit_buffer_digit_low_show:
	move.l	a0,-(sp)
	lea	input_buffer+2,a0
	move.b	d0,(a0)
	clr.b	1(a0)                           ; ended
	bsr.w	print                           ; shown
	movea.l	(sp)+,a0
	move.b	1(a0),d0                        ; its value
	movea.l	buffer_view,a6                  ; the view
	moveq	#0,d1
	move.b	edit_cursor_text+3,d1
	subi.w	#$2b,d1
	divu.w	#$3,d1
	adda.w	d1,a6
	move.b	edit_cursor_text+2,d1
	subi.w	#$25,d1
	mulu.w	#$10,d1
	adda.w	d1,a6
	andi.b	#$f0,(a6)                       ; the low nibble
	or.b	d0,(a6)                         ; set
	move.b	edit_cursor_text+3,d1
	cmpi.b	#$58,edit_cursor_text+3         ; the last byte?
	beq.s	edit_buffer_digit_wrap          ; yes
	addq.b	#3,edit_cursor_text+3           ; a byte right
	bra.w	edit_buffer_hex
edit_buffer_digit_wrap:
	move.b	#$2b,edit_cursor_text+3         ; the first byte
	cmpi.b	#$34,edit_cursor_text+2         ; the last row?
	beq.s	edit_buffer_digit_top           ; yes
	addq.b	#1,edit_cursor_text+2           ; down
	bra.w	edit_buffer_hex
edit_buffer_digit_top:
	move.b	#$25,edit_cursor_text+2         ; the first row
	bra.w	edit_buffer_hex

;------------------------------------------------------------------------------
; next_track (Control N): the next track (back to 0 past the last), read again.
;------------------------------------------------------------------------------
next_track:	; from: disk_ripper
	move.w	track,d0
	addq.w	#1,d0
	cmp.w	track_count,d0                  ; past the last?
	blt.s	next_track_set                  ; no
	clr.w	d0                              ; 0
next_track_set:
	move.w	d0,track
	bra.w	reread

;------------------------------------------------------------------------------
; previous_track (Control J): the track before (the last before 0), read again.
;------------------------------------------------------------------------------
previous_track:	; from: disk_ripper
	move.w	track,d0
	subq.w	#1,d0
	bpl.s	previous_track_set
	move.w	track_count,d0                  ; the last
	subq.w	#1,d0
previous_track_set:
	move.w	d0,track
	bra.w	reread

;------------------------------------------------------------------------------
; next_sector (+): the next sector, then the other side or the next track.
;------------------------------------------------------------------------------
next_sector:	; from: disk_ripper
	move.w	sector,d0
	addq.w	#1,d0
	move.w	sectors_per_track,d7            ; sectors a track
	add.w	first_sector,d7                 ; + the first
	subq.w	#1,d7
	cmp.w	d7,d0                           ; past the last?
	ble.s	next_sector_set                 ; no
	move.w	first_sector,d0                 ; back to the first
	cmpi.w	#$2,side_count                  ; double sided?
	bne.s	next_sector_track               ; no
	tst.w	side                            ; side 0?
	bne.s	next_sector_side                ; no
	not.w	side                            ; side 1
	bra.s	next_sector_set
next_sector_side:
	not.w	side                            ; side 0
next_sector_track:
	move.w	track,d1                        ; the next track
	addq.w	#1,d1
	cmp.w	track_count,d1                  ; past the last?
	blt.s	next_sector_track_set           ; no
	clr.w	d1                              ; 0
next_sector_track_set:
	move.w	d1,track
next_sector_set:
	move.w	d0,sector
	bra.w	reread

;------------------------------------------------------------------------------
; previous_sector (-): the sector before, then the other side or the track before.
;------------------------------------------------------------------------------
previous_sector:	; from: disk_ripper
	move.w	sector,d0
	subq.w	#1,d0
	cmp.w	first_sector,d0                 ; before the first?
	bge.s	previous_sector_set             ; no
	move.w	first_sector,d0                 ; the last
	add.w	sectors_per_track,d0
	subq.w	#1,d0
	cmpi.w	#$2,side_count                  ; double sided?
	bne.s	previous_sector_track           ; no
	tst.w	side                            ; side 1?
	beq.s	previous_sector_side            ; no
	not.w	side                            ; side 0
	bra.w	previous_sector_set
previous_sector_side:
	not.w	side                            ; side 1
previous_sector_track:
	move.w	track,d1                        ; the track before
	subq.w	#1,d1
	bge.s	previous_sector_track_set
	move.w	track_count,d1                  ; the last
	subq.w	#1,d1
previous_sector_track_set:
	move.w	d1,track
previous_sector_set:
	move.w	d0,sector
	bra.w	reread
reread:	; from: next_track, previous_track, next_sector
	bsr.w	show_disk_settings              ; shown
	tst.w	track_mode                      ; sectors?
	bne.s	reread_sector                   ; yes
	bra.w	read_sectors                    ; the track read
reread_sector:
	bra.w	read_track                      ; the sector read

;------------------------------------------------------------------------------
; page_up_buffer (Shift up): the view 256 bytes (32 in disassembly) back.
;------------------------------------------------------------------------------
page_up_buffer:	; from: disk_ripper
	tst.w	buffer_length                   ; data?
	beq.w	disk_ripper_keys                ; no
	tst.w	disassembly_view                ; disassembly?
	bne.s	page_up_buffer_disassembly      ; yes
	movea.l	buffer_view,a0                  ; the view
	lea	disk_buffer,a1                  ; the buffer
	cmpa.l	a0,a1                           ; at its start?
	beq.w	disk_ripper_keys                ; yes
	suba.l	#$100,a0                        ; 256 back
	cmpa.l	a0,a1                           ; before the start?
	ble.s	page_up_buffer_set              ; no
	movea.l	a1,a0                           ; the start
page_up_buffer_set:
	move.l	a0,buffer_view
	bsr.w	draw_buffer                     ; shown
	bra.w	disk_ripper_keys
page_up_buffer_disassembly:
	movea.l	buffer_view,a0
	lea	disk_buffer,a1
	cmpa.l	a0,a1                           ; at its start?
	beq.w	disk_ripper_keys                ; yes
	suba.l	#$20,a0                         ; 32 back
	cmpa.l	a0,a1
	ble.s	page_up_buffer_set
	movea.l	a1,a0
	bra.s	page_up_buffer_set

;------------------------------------------------------------------------------
; page_down_buffer (Shift down): the view 256 bytes (32) on, not past the buffer's last page.
;------------------------------------------------------------------------------
page_down_buffer:	; from: disk_ripper
	tst.w	buffer_length                   ; data?
	beq.w	disk_ripper_keys                ; no
	tst.w	disassembly_view                ; disassembly?
	bne.s	page_down_buffer_disassembly    ; yes
	movea.l	buffer_view,a0                  ; the view
	lea	disk_buffer,a1                  ; the buffer's
	adda.w	buffer_length,a1                ; end
	suba.l	#$100,a1                        ; less 256
	cmpa.l	a0,a1                           ; there already?
	ble.w	disk_ripper_keys                ; yes
	adda.l	#$100,a0                        ; 256 on
	cmpa.l	a0,a1                           ; past it?
	bge.s	page_down_buffer_set            ; no
	movea.l	a1,a0                           ; the last page
page_down_buffer_set:
	move.l	a0,buffer_view
	bsr.w	draw_buffer                     ; shown
	bra.w	disk_ripper_keys
page_down_buffer_disassembly:
	movea.l	buffer_view,a0
	lea	disk_buffer,a1
	adda.w	buffer_length,a1
	suba.l	#$20,a1                         ; less 32
	cmpa.l	a0,a1                           ; there already?
	ble.w	disk_ripper_keys                ; yes
	adda.l	#$20,a0                         ; 32 on
	cmpa.l	a0,a1
	bge.s	page_down_buffer_set
	movea.l	a1,a0
	bra.s	page_down_buffer_set

;------------------------------------------------------------------------------
; line_down_buffer (down): the view a line (16 bytes) on, or a word in disassembly.
;------------------------------------------------------------------------------
line_down_buffer:	; from: disk_ripper
	tst.w	buffer_length                   ; data?
	beq.w	disk_ripper_keys                ; no
	tst.w	disassembly_view                ; disassembly?
	bne.s	line_down_buffer_disassembly    ; yes
	move.l	buffer_view,d0                  ; the view
	movea.l	d0,a0
	subi.l	#disk_buffer,d0
	andi.w	#$f,d0                          ; on 16
	suba.w	d0,a0
	lea	disk_buffer,a1                  ; the buffer's
	adda.w	buffer_length,a1                ; end
	suba.l	#$100,a1                        ; less 256
	cmpa.l	a0,a1
	ble.w	line_down_buffer_last
	adda.l	#$10,a0                         ; 16 on
	bra.s	line_down_buffer_set
line_down_buffer_last:
	movea.l	a1,a0
line_down_buffer_set:
	move.l	a0,buffer_view
	bsr.w	draw_buffer                     ; shown
	bra.w	disk_ripper_keys
line_down_buffer_disassembly:
	movea.l	buffer_view,a0
	lea	disk_buffer,a1
	adda.w	buffer_length,a1
	suba.l	#$20,a1                         ; less 32
	cmpa.l	a0,a1
	ble.w	disk_ripper_keys
	addq.l	#2,a0                           ; a word on
	bra.w	line_down_buffer_set

;------------------------------------------------------------------------------
; line_up_buffer (up): the view a line (16 bytes) back, or a word in disassembly.
;------------------------------------------------------------------------------
line_up_buffer:	; from: disk_ripper
	tst.w	buffer_length                   ; data?
	beq.w	disk_ripper_keys                ; no
	tst.w	disassembly_view                ; disassembly?
	bne.s	line_up_buffer_disassembly      ; yes
	move.l	buffer_view,d0                  ; the view
	movea.l	d0,a0
	subi.l	#disk_buffer,d0
	andi.w	#$f,d0                          ; on 16
	suba.w	d0,a0
	lea	disk_buffer,a1                  ; the buffer
	cmpa.l	a0,a1                           ; at its start?
	bge.s	line_up_buffer_first            ; yes
	suba.l	#$10,a0                         ; 16 back
	bra.s	line_up_buffer_set
line_up_buffer_first:
	movea.l	a1,a0
line_up_buffer_set:
	move.l	a0,buffer_view
	bsr.w	draw_buffer                     ; shown
	bra.w	disk_ripper_keys
line_up_buffer_disassembly:
	movea.l	buffer_view,a0
	lea	disk_buffer,a1
	cmpa.l	a0,a1                           ; at its start?
	bge.w	disk_ripper_keys                ; yes
	subq.l	#2,a0                           ; a word back
	bra.s	line_up_buffer_set

;------------------------------------------------------------------------------
; seek_to_track: the head stepped in or out to the track wanted.
;------------------------------------------------------------------------------
seek_to_track:	; from: read_sectors, write_sector, disk_search, search_buffer, track_info, read_track
	move.w	track,d0                        ; wanted
	move.w	head_track,d1                   ; where it is
	sub.w	d0,d1
	beq.s	seek_to_track_done              ; there
	bmi.s	seek_to_track_out
seek_to_track_in:
	jsr	fdc_step_out_track              ; a step in
	subq.w	#1,d1
	bne.s	seek_to_track_in
	move.w	track,head_track                ; there
	rts
seek_to_track_out:
	jsr	fdc_step_in                     ; a step out
	addq.w	#1,d1
	bne.s	seek_to_track_out
	move.w	track,head_track                ; there
seek_to_track_done:
	rts

;------------------------------------------------------------------------------
; show_sector_status: the FDC status d7 as a message: SECTOR OK, BAD CRC DATA, ...
;------------------------------------------------------------------------------
show_sector_status:	; from: read_sectors, write_sector, disk_search, search_buffer
	cmp.b	#$80,d7                         ; $80 (the motor on): SECTOR OK
	bne.s	show_sector_status_a0
	lea	text_sector_ok,a0
	bra.s	show_sector_status_print
show_sector_status_a0:
	cmp.b	#$a0,d7                         ; $A0: CLEAR DATA MARK (deleted data)
	bne.s	show_sector_status_90
	lea	text_clear_data_mark,a0
	bra.s	show_sector_status_print
show_sector_status_90:
	cmp.b	#$90,d7                         ; $90: record not found
	bne.s	show_sector_status_98
	lea	text_sector_not_found_at_eb13,a0
	bra.s	show_sector_status_print
show_sector_status_98:
	cmp.b	#$98,d7                         ; $98: BAD ID CRC
	bne.s	show_sector_status_88
	lea	text_bad_id_crc,a0
	bra.s	show_sector_status_print
show_sector_status_88:
	cmp.b	#$88,d7                         ; $88: CRC error
	bne.s	show_sector_status_84
	lea	text_bad_crc_data,a0
	bra.s	show_sector_status_print
show_sector_status_84:
	cmp.b	#$84,d7                         ; $84: lost data
	bne.s	show_sector_status_c0
	lea	text_bad_data_request,a0
	bra.s	show_sector_status_print
show_sector_status_c0:
	cmp.b	#$c0,d7                         ; $C0: write protect
	bne.s	show_sector_status_other
	lea	text_write_protect,a0
	bra.s	show_sector_status_print
show_sector_status_other:
	lea	text_disk_error,a0              ; anything else
show_sector_status_print:
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; read_sectors (F1): the buffer filled with '*', then the track's sectors read into it from the sector set; the
; status and the length shown.
;------------------------------------------------------------------------------
read_sectors:	; from: disk_ripper, previous_sector, disk_ripper_module, boot_info
	bsr.w	select_drive_side               ; the drive and side
	bsr.w	seek_to_track                   ; the head on the track
	lea	disk_buffer,a0                  ; the buffer
	move.w	#$3ff,d0                        ; 1K
read_sectors_fill:
	move.b	#$2a,(a0)+                      ; '*'
	dbra	d0,read_sectors_fill
	move.l	#disk_buffer,d2
	move.w	sector,d1                       ; the sector
	jsr	fdc_read_sectors                ; read
	bsr.w	show_sector_status              ; its status
	move.w	d2,buffer_length                ; the length read

;------------------------------------------------------------------------------
; show_buffer: the buffer shown from its start, with its length.
;------------------------------------------------------------------------------
show_buffer:	; from: buffer_memory_menu, write_sector
	clr.w	track_mode
	move.l	#disk_buffer,buffer_view        ; the view at the start
	bsr.w	draw_buffer                     ; shown
	bsr.w	show_buffer_length              ; the length
	bra.w	disk_ripper_keys

;------------------------------------------------------------------------------
; write_sector (F2): "CONFIRM WRITE SECTOR (Y/N) ?", then the buffer written from the sector set.
;------------------------------------------------------------------------------
write_sector:	; from: disk_ripper
	moveq	#90,d4
	move.w	#$c8,d5
	move.w	#$1b8,d6
	move.w	#$6e,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_confirm_write_sector,a0    ; "CONFIRM WRITE SECTOR (Y/N) ?"
	bsr.w	print
write_sector_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$79,d0                         ; 'y'?
	beq.s	write_sector_go
	cmp.b	#$59,d0                         ; 'Y'?
	beq.s	write_sector_go
	cmp.b	#$6e,d0                         ; 'n'?
	beq.s	write_sector_done
	cmp.b	#$4e,d0                         ; 'N'?
	beq.s	write_sector_done
	bra.s	write_sector_key                ; another key
write_sector_go:
	bsr.w	select_drive_side               ; the drive and side
	bsr.w	seek_to_track                   ; the head on the track
	move.l	#disk_buffer,d2                 ; the buffer
	move.w	sector,d1                       ; the sector
	jsr	fdc_write_sectors               ; written
	bsr.w	show_sector_status              ; its status
write_sector_done:
	moveq	#90,d4
	move.w	#$c8,d5
	move.w	#$1c2,d6
	move.w	#$6e,d7
	bsr.w	clear_area                      ; the box cleared
	bra.w	show_buffer

;------------------------------------------------------------------------------
; disk_search (F3): "SEARCH (H)EXA/(T)EXT ?", the search and replace texts, then the disk searched sector by
; sector from the one set: found, F1 replace and save, F2 continue, F3 edit there, F4 stop; ESC stops the search.
;------------------------------------------------------------------------------
disk_search:	; from: disk_ripper
	moveq	#90,d4
	move.w	#$c8,d5
	move.w	#$19a,d6
	move.w	#$6e,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_search_h_exa,a0            ; "SEARCH (H)EXA/(T)EXT ?"
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$74,d0                         ; 't'?
	beq.w	disk_search_text
	cmp.b	#$54,d0                         ; 'T'?
	beq.w	disk_search_text
	cmp.b	#$68,d0                         ; 'h'?
	beq.w	disk_search_hex
	cmp.b	#$48,d0                         ; 'H'?
	beq.w	disk_search_hex
	bsr.w	draw_buffer                     ; other: back
	bra.w	disk_ripper_keys
disk_search_text:
	bsr.w	draw_input_box                  ; the box
	lea	text_search,a0                  ; "SEARCH  : "
	bsr.w	print
	lea	text_replace,a0                 ; "REPLACE : "
	bsr.w	print
	lea	position_11_24,a0               ; the search's line
	bsr.w	print
	move.w	#$2500,input_buffer             ; 37 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	disk_search_escape              ; no
	lea	position_13_24,a0               ; the replacement's line
	bsr.w	print
	move.w	#$2500,replace_buffer           ; 37 characters
	pea	replace_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	bra.w	disk_search_go
disk_search_escape:
	bsr.w	draw_buffer
	bra.w	disk_ripper_keys
disk_search_go:	; from: next_sector_wrap
	moveq	#60,d4
	move.w	#$64,d5
	move.w	#$21c,d6
	move.w	#$4a,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_please_wait_searching,a0   ; "PLEASE WAIT ... SEARCHING ..."
	bsr.w	print
disk_search_sector:
	bsr.w	show_disk_settings              ; shown
	bsr.w	select_drive_side               ; the drive and side
	bsr.w	seek_to_track                   ; the head on the track
	move.l	#disk_buffer,d2                 ; the buffer
	move.w	sector,d1                       ; the sector
	jsr	fdc_read_sectors                ; read
	clr.w	track_mode
	bsr.w	show_sector_status              ; its status
	move.w	d2,buffer_length                ; the length
	bsr.w	show_buffer_length
	cmpi.b	#$1,$fffffc02.w                 ; keyboard ACIA data, ESC pressed?
	beq.s	disk_search_stopped             ; yes: stopped
	tst.w	d2                              ; anything read?
	beq.w	disk_search_next                ; no
	bsr.w	search_buffer                   ; searched
disk_search_found_test:
	tst.w	d7                              ; found?
	beq.w	disk_search_found               ; yes
disk_search_next:
	bsr.w	next_sector_wrap                ; the next sector
	tst.w	d1                              ; the disk's end?
	bne.s	disk_search_sector              ; no
	bsr.w	show_disk_settings
	bsr.w	select_drive_side
	bsr.w	seek_to_track
	lea	text_sorry_not_found,a0         ; "SORRY NOT FOUND !"
	bsr.w	print
	bsr.w	get_key                         ; a key
disk_search_stopped:
	move.l	#disk_buffer,d2                 ; the buffer
	move.w	sector,d1                       ; the sector
	jsr	fdc_read_sectors                ; read again
	clr.w	track_mode
	bsr.w	show_sector_status              ; its status
	move.l	#disk_buffer,buffer_view        ; the view at the start
	bsr.w	draw_buffer                     ; shown
	bsr.w	show_buffer_length
	bra.w	disk_ripper_keys
disk_search_found:
	movem.l	d1-d7/a0-a6,-(sp)
	lea	text_f1_replace_save,a0         ; REPLACE & SAVE, CONTINUE, ...
	bsr.w	print
	movem.l	(sp)+,d1-d7/a0-a6
disk_search_found_key:
	movem.l	d6-d7/a0-a2,-(sp)
	bsr.w	get_key                         ; a key
	movem.l	(sp)+,d6-d7/a0-a2
	swap	d0                              ; its scan code
	cmp.b	#$3b,d0                         ; F1?
	beq.w	disk_search_replace             ; replace and save
	cmp.b	#$3c,d0                         ; F2?
	beq.w	disk_search_continue            ; continue
	cmp.b	#$3d,d0                         ; F3?
	beq.w	disk_search_edit                ; edit there
	cmp.b	#$3e,d0                         ; F4?
	bne.s	disk_search_found_key           ; no: another key
	move.l	#disk_buffer,buffer_view        ; stopped: the buffer from its start
	bsr.w	draw_buffer                     ; shown
	bsr.w	show_buffer_length
	bra.w	disk_ripper_keys
disk_search_replace:
	move.l	a0,-(sp)
	lea	text_confirm_y_n_at_ed6d,a0     ; "CONFIRM (Y/N) ?"
	bsr.w	print
	movea.l	(sp)+,a0
disk_search_replace_key:
	movem.l	d6-d7/a0-a2,-(sp)
	bsr.w	get_key                         ; a key
	movem.l	(sp)+,d6-d7/a0-a2
	cmp.b	#$79,d0                         ; 'y'?
	beq.s	disk_search_replace_yes
	cmp.b	#$59,d0                         ; 'Y'?
	beq.s	disk_search_replace_yes
	cmp.b	#$6e,d0                         ; 'n'?
	beq.s	disk_search_replace_no
	cmp.b	#$4e,d0                         ; 'N'?
	bne.s	disk_search_replace_key         ; another key
disk_search_replace_no:
	bra.w	disk_search_found
disk_search_replace_yes:
	movem.l	d6-d7/a0-a2,-(sp)
	lea	replace_buffer+1,a1             ; the replacement
	tst.b	(a1)                            ; any?
	beq.s	disk_search_no_replace          ; no: "SORRY NO REPLACE !"
	move.b	(a1)+,d0                        ; its length
	subq.w	#1,d0
disk_search_replace_byte:
	move.b	(a1)+,(a0)+                     ; put in
	dbra	d0,disk_search_replace_byte
	moveq	#0,d0
	subq.w	#1,a0                           ; its last byte
	lea	disk_buffer,a1                  ; the buffer's
	adda.w	buffer_length,a1                ; end
	cmpa.l	a1,a0                           ; past it?
	ble.s	disk_search_replace_write       ; no
	moveq	#1,d0                           ; yes: the next sector too
disk_search_replace_write:
	move.l	d0,-(sp)
	bsr.w	select_drive_side               ; the drive and side
	bsr.w	seek_to_track                   ; the head on the track
	move.l	#disk_buffer,d2                 ; the buffer
	move.w	sector,d1                       ; the sector
	jsr	fdc_write_sectors               ; written
	bsr.w	show_sector_status              ; its status
	move.l	(sp)+,d0
	tst.w	d0                              ; the next sector too?
	beq.s	disk_search_replace_done        ; no
	bsr.w	next_sector_wrap                ; the next sector
	bsr.w	select_drive_side               ; the drive and side
	bsr.w	seek_to_track                   ; the head on the track
	move.l	#disk_buffer,d2                 ; its part of the buffer
	add.w	buffer_length,d2
	move.w	sector,d1                       ; the sector
	jsr	fdc_write_sectors               ; written
	bsr.w	show_sector_status              ; its status
disk_search_replace_done:
	bsr.w	show_disk_settings              ; shown
	movem.l	(sp)+,d6-d7/a0-a2
	bra.w	disk_search_found
disk_search_no_replace:
	movem.l	d6-d7/a0-a2,-(sp)
	lea	text_sorry_no_replace,a0        ; "SORRY NO REPLACE !"
	bsr.w	print
	bsr.w	get_key                         ; a key
	movem.l	(sp)+,d6-d7/a0-a2
	bra.w	disk_search_found
disk_search_continue:
	move.l	a0,-(sp)
	lea	text_please_wait_searching,a0   ; "PLEASE WAIT ... SEARCHING ..."
	bsr.w	print
	movea.l	(sp)+,a0
	moveq	#0,d5
	move.b	input_buffer+1,d5               ; the search's length
	adda.w	d5,a0                           ; on past it
	lea	disk_buffer,a2                  ; the buffer's
	adda.w	buffer_length,a2                ; end
	pea	disk_search_found_test          ; then back to disk_search_found_test
	bra.w	search_buffer_from              ; searched on
disk_search_edit:
	lea	disk_buffer,a1                  ; the buffer
	move.l	a0,d0
	sub.l	a1,d0                           ; the place in it
disk_search_edit_page:
	subi.l	#$100,d0                        ; by 256
	blt.s	disk_search_edit_row
	adda.l	#$100,a1
	bra.s	disk_search_edit_page
disk_search_edit_row:
	addi.l	#$100,d0
	move.b	#$25,edit_cursor_text+2         ; row 5
	move.b	#$2b,edit_cursor_text+3         ; column 11
disk_search_edit_line:
	subi.l	#$10,d0                         ; by 16
	blt.s	disk_search_edit_column
	addi.b	#$1,edit_cursor_text+2          ; a row down
	bra.s	disk_search_edit_line
disk_search_edit_column:
	addi.w	#$10,d0
	mulu.w	#$3,d0                          ; 3 columns a byte
	add.b	d0,edit_cursor_text+3
	move.l	a1,buffer_view                  ; the view
	bsr.w	draw_buffer                     ; shown
	bsr.w	show_buffer_length              ; the length
	cmpi.b	#$24,input_buffer               ; a text search?
	beq.s	disk_search_edit_text           ; yes
	bra.w	edit_buffer_to_chars            ; hex: the hex columns
disk_search_edit_text:
	bra.w	edit_buffer_hex                 ; the characters

;------------------------------------------------------------------------------
; search_buffer: the search text looked for in the buffer from a0 to a2; one that runs past the end is followed
; into the next sector.  d7 0 when found (a0 at it).
;------------------------------------------------------------------------------
search_buffer:	; from: disk_search
	lea	disk_buffer,a0                  ; the buffer
	movea.l	a0,a2
	adda.w	buffer_length,a2                ; its end
search_buffer_from:	; from: disk_search
	lea	input_buffer+2,a1               ; the search text
	moveq	#0,d7
	move.b	input_buffer+1,d7               ; its length
	move.b	(a1),d6                         ; its first byte
search_buffer_byte:
	cmpa.l	a2,a0                           ; the end?
	beq.s	search_buffer_end               ; yes
	cmp.b	(a0)+,d6                        ; the same?
	bne.s	search_buffer_from              ; no: from the start again
	addq.l	#1,a1
	move.b	(a1),d6                         ; the next
	subq.w	#1,d7                           ; all?
	bne.s	search_buffer_byte              ; no
search_buffer_end:
	tst.w	d7                              ; found?
	beq.s	search_buffer_done              ; yes
	cmp.b	input_buffer+1,d7               ; none of it?
	beq.s	search_buffer_done              ; yes
	move.b	input_buffer+1,d6
	sub.w	d7,d6                           ; back to its start
	suba.w	d6,a0
	movem.l	d7/a0,-(sp)                     ; saved
	bsr.w	next_sector_wrap                ; the next sector
	bsr.w	select_drive_side               ; the drive and side
	bsr.w	seek_to_track                   ; the head on the track
	move.l	#disk_buffer,d2                 ; after the buffer's data
	add.w	buffer_length,d2
	move.l	d2,-(sp)
	move.w	sector,d1                       ; the sector
	jsr	fdc_read_sectors                ; read
	clr.w	track_mode
	bsr.w	show_sector_status              ; its status
	movea.l	(sp)+,a0
	movem.l	(sp)+,d7/a2
search_buffer_rest:
	move.b	(a1),d6                         ; the rest
	cmp.b	(a0)+,d6                        ; the same?
	bne.s	search_buffer_back              ; no
	addq.l	#1,a1
	subq.w	#1,d7
	bne.s	search_buffer_rest              ; all?
search_buffer_back:
	movem.l	d7/a2,-(sp)
	bsr.w	previous_sector_wrap            ; back a sector
	movem.l	(sp)+,d7/a2
	movea.l	a2,a0
	rts
search_buffer_done:
	moveq	#0,d6
	move.b	input_buffer+1,d6               ; the length
	suba.w	d6,a0                           ; back to its start
	rts

;------------------------------------------------------------------------------
; previous_sector_wrap: the sector before, the other side or the track before.
;------------------------------------------------------------------------------
previous_sector_wrap:	; from: search_buffer
	move.w	sector,d0
	subq.w	#1,d0
	cmp.w	first_sector,d0                 ; before the first?
	bge.s	previous_sector_wrap_set        ; no
	move.w	first_sector,d0                 ; the last
	add.w	sectors_per_track,d0
	subq.w	#1,d0
	cmpi.w	#$2,side_count                  ; double sided?
	bne.s	previous_sector_wrap_track      ; no
	tst.w	side                            ; side 1?
	beq.s	previous_sector_wrap_side       ; no
	not.w	side                            ; side 0
	bra.w	previous_sector_wrap_set
previous_sector_wrap_side:
	not.w	side                            ; side 1
previous_sector_wrap_track:
	move.w	track,d1                        ; the track before
	subq.w	#1,d1
	bge.s	previous_sector_wrap_track_set
	move.w	track_count,d1                  ; the last
	subq.w	#1,d1
previous_sector_wrap_track_set:
	move.w	d1,track
previous_sector_wrap_set:
	move.w	d0,sector
	rts

;------------------------------------------------------------------------------
; next_sector_wrap: the next sector, the other side or the next track; d1 0 when back at the disk's start.
;------------------------------------------------------------------------------
next_sector_wrap:	; from: disk_search, search_buffer
	moveq	#-1,d1
	move.w	sector,d0
	addq.w	#1,d0
	move.w	sectors_per_track,d7            ; sectors a track
	add.w	first_sector,d7                 ; + the first
	subq.w	#1,d7
	cmp.w	d7,d0                           ; past the last?
	ble.s	next_sector_wrap_set            ; no
	move.w	first_sector,d0                 ; the first
	cmpi.w	#$2,side_count                  ; double sided?
	bne.s	next_sector_wrap_track          ; no
	tst.w	side                            ; side 0?
	bne.s	next_sector_wrap_side           ; no
	not.w	side                            ; side 1
	bra.s	next_sector_wrap_set
next_sector_wrap_side:
	not.w	side                            ; side 0
next_sector_wrap_track:
	move.w	track,d1                        ; the next track
	addq.w	#1,d1
	cmp.w	track_count,d1                  ; past the last?
	blt.s	next_sector_wrap_track_set      ; no
	clr.w	d1                              ; 0
next_sector_wrap_track_set:
	move.w	d1,track
next_sector_wrap_set:
	move.w	d0,sector
	rts
disk_search_hex:	; from: disk_search
	bsr.w	draw_input_box                  ; the box
	lea	text_search,a0                  ; "SEARCH  : "
	bsr.w	print
	lea	dollar_text,a0                  ; "$"
	bsr.w	print
	lea	text_replace,a0                 ; "REPLACE : "
	bsr.w	print
	lea	dollar_text,a0                  ; "$"
	bsr.w	print
disk_search_hex_search:
	lea	position_11_24,a0               ; the search's line
	bsr.w	print
	move.w	#$2500,input_buffer+2           ; 37 characters
	pea	input_buffer+2
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	disk_search_hex_escape          ; no
	lea	input_buffer,a0
	bsr.w	hex_to_bytes                    ; as bytes
	tst.l	d7                              ; bad?
	bmi.s	disk_search_hex_search          ; yes: again
disk_search_hex_replace:
	lea	position_13_24,a0               ; the replacement's line
	bsr.w	print
	move.w	#$2500,replace_buffer+2         ; 37 characters
	pea	replace_buffer+2
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	lea	replace_buffer,a0
	bsr.w	hex_to_bytes                    ; as bytes
	tst.l	d7                              ; bad?
	bmi.s	disk_search_hex_replace         ; yes: again
	bra.w	disk_search_go                  ; searched
disk_search_hex_escape:
	bsr.w	draw_buffer
	bra.w	disk_ripper_keys

;------------------------------------------------------------------------------
; hex_to_bytes: the hex digits typed in the line at a0 (its maximum and count first) packed into bytes in place;
; d7 -1 for a bad digit.  An odd count takes the first digit alone.
;------------------------------------------------------------------------------
hex_to_bytes:	; from: search_replace, next_sector_wrap
	move.l	a0,-(sp)
	movea.l	a0,a1
	lea	2(a0),a1                        ; the text
	move.w	(a1),(a0)
	subi.w	#$100,(a0)
	clr.w	(a1)
	moveq	#0,d0
	move.b	1(a0),d0                        ; the count
	addq.l	#2,a0
	addq.l	#2,a1
	moveq	#0,d2
	moveq	#0,d4                           ; the bytes
	tst.w	d0                              ; none?
	beq.s	hex_to_bytes_done               ; yes
	btst	#$0,d0                          ; odd?
	bne.s	hex_to_bytes_low                ; yes: the first alone
hex_to_bytes_high:
	lea	hex_digit_pairs,a5              ; the digits
	move.b	(a1)+,d7
hex_to_bytes_high_find:
	cmp.b	(a5),d7                         ; this one?
	beq.s	hex_to_bytes_high_found         ; yes
	addq.l	#2,a5
	tst.b	(a5)                            ; the end?
	bge.s	hex_to_bytes_high_find          ; no
	moveq	#-1,d7                          ; bad
	bra.s	hex_to_bytes_done
hex_to_bytes_high_found:
	move.b	1(a5),d6
	move.b	d6,d2                           ; the high nibble
	lsl.w	#4,d2
	subq.w	#1,d0
hex_to_bytes_low:
	move.b	(a1)+,d7
	lea	hex_digit_pairs,a5              ; the digits
hex_to_bytes_low_find:
	cmp.b	(a5),d7                         ; this one?
	beq.s	hex_to_bytes_low_found          ; yes
	addq.l	#2,a5
	tst.b	(a5)                            ; the end?
	bge.s	hex_to_bytes_low_find           ; no
	moveq	#-1,d7                          ; bad
	bra.s	hex_to_bytes_done
hex_to_bytes_low_found:
	move.b	1(a5),d6
	or.b	d6,d2                           ; the low nibble
	move.b	d2,(a0)+                        ; a byte
	addq.w	#1,d4                           ; counted
	subq.w	#1,d0
	bne.s	hex_to_bytes_high               ; more?
	moveq	#0,d7
	clr.b	(a0)+                           ; ended
hex_to_bytes_done:
	movea.l	(sp)+,a0
	move.b	d4,1(a0)                        ; the bytes' count
	rts

;------------------------------------------------------------------------------
; draw_input_box: the box for the search's lines.
;------------------------------------------------------------------------------
draw_input_box:	; from: disk_search, next_sector_wrap
	moveq	#80,d4
	move.w	#$64,d5
	move.w	#$21c,d6
	move.w	#$78,d7
	bsr.w	clear_box_area                  ; the box
	rts

;------------------------------------------------------------------------------
; track_info (F4): the track's ID fields read and listed: TRACK SIDE SECTOR LGTH CRC and the read tests.
;------------------------------------------------------------------------------
track_info:	; from: disk_ripper
	bsr.w	select_drive_side               ; the drive and side
	bsr.w	seek_to_track                   ; the head on the track
	move.l	#disk_buffer,d2                 ; the buffer
	jsr	fdc_read_ids                    ; the IDs read
	move.l	d0,-(sp)                        ; the status kept
	moveq	#38,d4
	move.w	#$64,d5
	move.w	#$226,d6
	move.w	#$aa,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_track_side_sector,a0       ; "TRACK  SIDE  SECTOR  LGTH  CRC ..."
	bsr.w	print
	move.l	(sp)+,d0
	cmp.b	#$90,d0                         ; record not found?
	bne.s	track_info_list                 ; no
	lea	text_sector_not_found_press,a0  ; "SECTOR NOT FOUND (PRESS A KEY)"
	bsr.w	print
	bra.s	track_info_done
track_info_list:
	bsr.w	list_track_ids                  ; listed
track_info_done:
	bsr.w	get_key                         ; a key
	lea	position_20_13,a0               ; the line cleared
	bsr.w	print
	moveq	#38,d4
	move.w	#$64,d5
	move.w	#$230,d6
	move.w	#$ab,d7
	bsr.w	clear_area                      ; the box cleared

;------------------------------------------------------------------------------
; disk_ripper_module: from run_module: the sectors read again, or the whole track.
;------------------------------------------------------------------------------
disk_ripper_module:	; from: modules
	tst.w	track_mode                      ; the track mode?
	bne.s	disk_ripper_module_track        ; yes
	bra.w	read_sectors                    ; the sectors
disk_ripper_module_track:
	bra.w	read_track                      ; the track

;------------------------------------------------------------------------------
; list_track_ids: the ID fields read (6 bytes each in the buffer, their statuses after at +$12C) listed, 48 at
; most, each once (the IDs seen kept at $E108); a page at a time (SPACE to continue).
;------------------------------------------------------------------------------
list_track_ids:	; from: track_info
	lea	disk_buffer,a0                  ; the IDs
	lea	$12c(a0),a1                     ; their statuses
	lea	$15e(a0),a2                     ; the IDs seen
	move.w	#$31,d0                         ; 50
list_track_ids_clear:
	clr.l	(a2)+                           ; cleared
	clr.w	(a2)+
	dbra	d0,list_track_ids_clear
	lea	$15e(a0),a2
	move.l	(a0),(a2)                       ; the first seen
	move.w	4(a0),4(a2)
	move.l	(a0),d7
	moveq	#0,d0                           ; the count
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	move.b	(a0),d1                         ; the track
	move.b	1(a0),d2                        ; the side
	move.b	2(a0),d3                        ; the sector
	move.b	3(a0),d4                        ; the size
	move.b	4(a0),d5                        ; the CRC
	lsl.l	#8,d5
	move.b	5(a0),d5
	move.b	#$1b,(a0)                       ; the text: ESC Y, row 7
	move.b	#$59,1(a0)
	move.b	#$27,2(a0)
	move.b	#$2d,3(a0)
	clr.b	4(a0)
	addq.l	#6,a0
	move.b	(a1)+,d6                        ; its status
	bra.s	list_track_ids_line
list_track_ids_next:
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	move.b	(a0)+,d1                        ; the track
	move.b	(a0)+,d2                        ; the side
	move.b	(a0)+,d3                        ; the sector
	move.b	(a0)+,d4                        ; the size
	move.b	(a0)+,d5                        ; the CRC
	lsl.l	#8,d5
	move.b	(a0)+,d5
	move.b	(a1)+,d6                        ; its status
list_track_ids_line:
	bsr.w	list_track_id                   ; listed
	addq.w	#1,d0                           ; one more
	lea	disk_buffer,a3                  ; the text
	addi.b	#$1,2(a3)                       ; the next row
	cmpi.b	#$34,2(a3)                      ; past row 20?
	blt.s	list_track_ids_check            ; no
	movem.l	d0-d6/a0-a6,-(sp)
	lea	text_space_to_continue,a0       ; "SPACE TO CONTINUE (OTHER FOR STOPP)"
	bsr.w	print
	bsr.w	get_key                         ; a key
	move.w	d0,d7
	lea	position_20_13,a0               ; the line cleared
	bsr.w	print
	movem.l	(sp)+,d0-d6/a0-a6
	cmp.b	#$20,d7                         ; Space?
	bne.s	list_track_ids_done             ; no: stopped
	movem.l	d0-d7/a0-a6,-(sp)
	moveq	#38,d4
	move.w	#$64,d5
	move.w	#$226,d6
	move.w	#$aa,d7
	bsr.w	clear_box_area                  ; the box again
	lea	text_track_side_sector,a0       ; the head
	bsr.w	print
	movem.l	(sp)+,d0-d7/a0-a6
	move.b	#$27,2(a3)                      ; row 7 again
list_track_ids_check:
	cmp.w	#$30,d0                         ; 48?
	beq.s	list_track_ids_done             ; yes: done
	lea	ids_seen,a4                     ; the IDs seen
list_track_ids_seen:
	move.l	(a4),d6
	cmp.l	(a0),d6                         ; seen?
	beq.s	list_track_ids_seen_check       ; yes
list_track_ids_seen_next:
	addq.l	#6,a4
	tst.l	2(a4)                           ; the end?
	bne.s	list_track_ids_seen             ; no
	move.l	(a0),(a4)+                      ; kept
	move.w	4(a0),(a4)
	bra.w	list_track_ids_next             ; the next
list_track_ids_seen_check:
	move.w	4(a4),d6
	cmp.w	4(a0),d6                        ; the same?
	bne.s	list_track_ids_seen_next        ; no
	addq.w	#1,d0                           ; skipped
	addq.l	#6,a0
	addq.l	#1,a1
	bra.s	list_track_ids_check
list_track_ids_done:
	rts

;------------------------------------------------------------------------------
; list_track_id: one ID: the track (d1), side (d2), sector (d3), size (d4: 128-1024), CRC (d5), the ID's
; CRC error (bit 3 of d6) and record not found (bit 4), then the sector read: its status.
;------------------------------------------------------------------------------
list_track_id:	; from: list_track_ids
	movem.l	d0-d7/a0-a6,-(sp)
	lea	disk_buffer,a0                  ; the text
	move.b	#$2d,3(a0)                      ; column 13
	bsr.w	print
	lea	dollar_text,a0                  ; "$"
	bsr.w	print
	suba.l	a6,a6
	movea.w	d1,a6                           ; the track
	lea	hex_text,a4
	lea	hex_digits,a5                   ; the digits
	movem.l	d0-d7,-(sp)
	bsr.w	put_hex_address                 ; in hex
	movem.l	(sp)+,d0-d7
	clr.b	(a4)                            ; ended
	lea	hex_text+6,a0                   ; the last 2 digits
	bsr.w	print
	lea	disk_buffer,a0
	move.b	#$35,3(a0)                      ; column 21
	bsr.w	print
	suba.l	a6,a6
	movea.w	d2,a6                           ; the side
	lea	hex_text,a4
	lea	hex_digits,a5
	movem.l	d0-d7,-(sp)
	bsr.w	put_hex_address
	movem.l	(sp)+,d0-d7
	clr.b	(a4)
	lea	hex_text+7,a0                   ; the last digit
	bsr.w	print
	lea	disk_buffer,a0
	move.b	#$3b,3(a0)                      ; column 27
	bsr.w	print
	lea	dollar_text,a0                  ; "$"
	bsr.w	print
	suba.l	a6,a6
	movea.w	d3,a6                           ; the sector
	lea	hex_text,a4
	lea	hex_digits,a5
	movem.l	d0-d7,-(sp)
	bsr.w	put_hex_address
	movem.l	(sp)+,d0-d7
	clr.b	(a4)
	lea	hex_text+6,a0
	bsr.w	print
	lea	disk_buffer,a0
	move.b	#$42,3(a0)                      ; column 34
	bsr.w	print
	tst.w	d4                              ; size 0?
	bne.s	list_track_id_256               ; no
	lea	text_128,a0                     ; "128 "
list_track_id_256:
	cmp.w	#$1,d4                          ; 1?
	bne.s	list_track_id_512               ; no
	lea	text_256,a0                     ; "256 "
list_track_id_512:
	cmp.w	#$2,d4                          ; 2?
	bne.s	list_track_id_1024              ; no
	lea	text_512,a0                     ; "512 "
list_track_id_1024:
	cmp.w	#$3,d4                          ; 3?
	bne.s	list_track_id_size              ; no
	lea	text_1024,a0                    ; "1024"
list_track_id_size:
	bsr.w	print
	lea	disk_buffer,a0
	move.b	#$47,3(a0)                      ; column 39
	bsr.w	print
	lea	dollar_text,a0                  ; "$"
	bsr.w	print
	suba.l	a6,a6
	movea.w	d5,a6                           ; the CRC
	lea	hex_text,a4
	lea	hex_digits,a5
	movem.l	d0-d7,-(sp)
	bsr.w	put_hex_address
	movem.l	(sp)+,d0-d7
	clr.b	(a4)
	lea	hex_text+4,a0                   ; the last 4 digits
	bsr.w	print
	lea	disk_buffer,a0
	move.b	#$4f,3(a0)                      ; column 47
	bsr.w	print
	lea	text_ok,a0                      ; "OK"
	btst	#$3,d6                          ; the ID's CRC bad?
	beq.s	list_track_id_rnf               ; no
	lea	text_bad,a0                     ; "ER"
list_track_id_rnf:
	bsr.w	print
	lea	disk_buffer,a0
	move.b	#$56,3(a0)                      ; column 54
	bsr.w	print
	lea	text_ok,a0                      ; "OK"
	btst	#$4,d6                          ; not found?
	beq.s	list_track_id_read              ; no
	lea	text_bad,a0                     ; "ER"
list_track_id_read:
	bsr.w	print
	lea	disk_buffer,a0
	move.b	#$5c,3(a0)                      ; column 60
	bsr.w	print
	move.l	#id_buffer,d2                   ; a buffer
	move.w	d3,d1                           ; the sector
	jsr	fdc_read_sectors                ; read
	tst.l	d2                              ; any?
	beq.s	list_track_id_lost              ; no
	cmp.b	#$80,d7                         ; all right?
	beq.s	list_track_id_ok                ; yes
	cmp.b	#$a0,d7                         ; $A0?
	bne.s	list_track_id_90                ; no
	lea	text_dam_f8,a0
	bra.s	list_track_id_print
list_track_id_90:
	cmp.b	#$90,d7                         ; $90?
	bne.s	list_track_id_98                ; no
	lea	text_bad_dam,a0
	bra.s	list_track_id_print
list_track_id_98:
	cmp.b	#$98,d7                         ; $98?
	bne.s	list_track_id_88                ; no
	lea	text_bad_idc,a0
	bra.s	list_track_id_print
list_track_id_88:
	cmp.b	#$88,d7                         ; $88?
	bne.s	list_track_id_84                ; no
	lea	text_bad_dac,a0
	bra.s	list_track_id_print
list_track_id_84:
	cmp.b	#$84,d7                         ; $84?
	bne.s	list_track_id_ok                ; no
list_track_id_lost:
	lea	text_bad_dar,a0
	bra.s	list_track_id_print
list_track_id_ok:
	lea	text_ok,a0                      ; "OK"
list_track_id_print:
	bsr.w	print
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; read_track (F5): the whole track read raw into the buffer (Read Track), its length shown.
;------------------------------------------------------------------------------
read_track:	; from: disk_ripper, previous_sector, disk_ripper_module, boot_info
	move.w	#$1,track_mode                  ; the track mode
	bsr.w	select_drive_side               ; the drive and side
	bsr.w	seek_to_track                   ; the head on the track
	move.l	#disk_buffer,d2                 ; the buffer
	jsr	fdc_read_track                  ; read
	lea	position_21_28,a0
	bsr.w	print
	move.w	d2,buffer_length                ; the length
	move.l	#disk_buffer,buffer_view        ; the view at the start
	bsr.w	draw_buffer                     ; shown
	bsr.w	show_buffer_length
	bra.w	disk_ripper_keys

;------------------------------------------------------------------------------
; boot_info (F6): the disk's layout (tracks, sectors a track, sides, first sector) shown to change with the cursor
; keys, or F1 TAKES BOOT INFO from the boot sector.  Another key reads.
;------------------------------------------------------------------------------
boot_info:	; from: disk_ripper
	moveq	#50,d4
	move.w	#$c8,d5
	move.w	#$1b8,d6
	move.w	#$9a,d7
	bsr.w	clear_box_area                  ; the box
	lea	position_10_51,a0               ; the menu
	bsr.w	print
	clr.w	boot_info_line                  ; the first line
	lea	arrow_text,a0                   ; its marker
	bsr.w	print
boot_info_draw:	; from: boot_info_unmark
	lea	text_nbr_of_tracks,a0           ; "NBR OF TRACKS : "
	bsr.w	print
	moveq	#0,d0
	move.w	track_count,d0                  ; the tracks
	bsr.w	to_decimal_digits               ; in decimal
	movea.w	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+6,a0
	bsr.w	print
	lea	text_sectors_track,a0           ; "SECTORS/TRACK : "
	bsr.w	print
	moveq	#0,d0
	move.w	sectors_per_track,d0
	bsr.w	to_decimal_digits               ; in decimal
	movea.w	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+6,a0
	bsr.w	print
	lea	text_nbr_sides,a0               ; "NBR SIDES     : "
	bsr.w	print
	movea.w	side_count,a6                   ; the sides
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+7,a0
	bsr.w	print
	lea	text_f1_takes_boot,a0
	bsr.w	print
	lea	text_init_sector,a0             ; "INIT SECTOR   : "
	bsr.w	print
	moveq	#0,d0
	move.w	first_sector,d0                 ; the first sector
	bsr.w	to_decimal_digits               ; in decimal
	movea.w	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+5,a0
	bsr.w	print
boot_info_key:	; from: boot_info_unmark
	bsr.w	get_key                         ; a key
	swap	d0
	cmp.b	#$3b,d0                         ; F1?
	beq.w	boot_info_take                  ; from the boot sector
	cmp.b	#$50,d0                         ; down?
	beq.w	boot_info_down
	cmp.b	#$48,d0                         ; up?
	beq.w	boot_info_up
	cmp.b	#$4b,d0                         ; left?
	beq.w	boot_info_left
	cmp.b	#$4d,d0                         ; right?
	beq.w	boot_info_right
	tst.w	track_mode                      ; other: read
	bne.s	boot_info_read_track
	bra.w	read_sectors
boot_info_read_track:
	bra.w	read_track
boot_info_take:
	bsr.w	select_drive                    ; the menu
	jsr	fdc_restore                     ; the drive set
	clr.w	head_track                      ; track 0
	move.l	#disk_buffer,d2                 ; the buffer
	move.w	#$1,d1                          ; sector 1
	jsr	fdc_read_sectors                ; read
	tst.w	d2                              ; read?
	beq.w	boot_info_bad                   ; no
	lea	disk_buffer,a0                  ; the boot sector
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	move.b	$18(a0),d1                      ; sectors a track
	move.b	$1a(a0),d2                      ; sides
	move.b	$14(a0),d3                      ; sectors, high byte
	tst.w	d2                              ; sides?
	ble.s	boot_info_bad                   ; none
	cmp.w	#$2,d2                          ; more than 2?
	bgt.s	boot_info_bad
	lsl.w	#8,d3
	move.b	$13(a0),d3                      ; sectors
	divu.w	d1,d3                           ; / sectors a track
	divu.w	d2,d3                           ; / sides: the tracks
	tst.w	d3
	ble.s	boot_info_bad                   ; none
	cmp.w	#$54,d3                         ; more than 84?
	bgt.w	boot_info_bad
	tst.w	d1
	ble.s	boot_info_bad                   ; none
	cmp.w	#$c,d1                          ; more than 12?
	bgt.s	boot_info_bad
	move.w	d1,sectors_per_track            ; set
	move.w	d2,side_count
	move.w	d3,track_count
	move.w	#$1,first_sector                ; from sector 1
	bra.w	boot_info_draw                  ; shown
boot_info_bad:
	lea	text_error_boot,a0              ; "ERROR BOOT"
	bsr.w	print
	bsr.w	get_key                         ; a key
	lea	position_18_28,a0               ; the line cleared
	bsr.w	print
	bra.w	boot_info_draw

;------------------------------------------------------------------------------
; boot_info_unmark: the current line's marker taken off.
;------------------------------------------------------------------------------
boot_info_unmark:
	move.w	boot_info_line,d0               ; the line
	mulu.w	#$5,d0                          ; 5 bytes a line
	lea	position_10_51,a0               ; its position
	adda.w	d0,a0
	bsr.w	print
	lea	no_arrow_text,a0                ; no marker
	bsr.w	print
	rts
boot_info_down:	; from: boot_info
	bsr.w	boot_info_unmark                ; unmarked
	move.w	boot_info_line,d0
	addq.w	#1,d0                           ; the next line
	move.w	d0,d1
	mulu.w	#$5,d0
	lea	position_10_51,a0
	adda.w	d0,a0
	tst.b	(a0)                            ; the end?
	bge.s	boot_info_mark                  ; no
	clr.w	d1                              ; back to the first
	clr.w	d0
	lea	position_10_51,a0
boot_info_mark:
	move.w	d1,boot_info_line
	bsr.w	print
	lea	arrow_text,a0                   ; its marker
	bsr.w	print
	bra.w	boot_info_key
boot_info_up:	; from: boot_info
	bsr.w	boot_info_unmark                ; unmarked
	move.w	boot_info_line,d0
	subq.w	#1,d0                           ; the line before
	bge.s	boot_info_up_mark
	move.w	#$14,d0                         ; the last
	divu.w	#$5,d0
	subq.w	#1,d0
boot_info_up_mark:
	move.w	d0,boot_info_line
	mulu.w	#$5,d0
	lea	position_10_51,a0
	adda.w	d0,a0
	bsr.w	print
	lea	arrow_text,a0                   ; its marker
	bsr.w	print
	bra.w	boot_info_key
boot_info_right:	; from: boot_info
	moveq	#1,d1                           ; +1
	bsr.w	boot_info_change                ; changed
	bra.w	boot_info_draw
boot_info_left:	; from: boot_info
	moveq	#-1,d1                          ; -1
	bsr.w	boot_info_change                ; changed
	bra.w	boot_info_draw

;------------------------------------------------------------------------------
; boot_info_change: the current line's value changed by d1: the tracks (0-83), sectors (1-99), the sides (1 or 2),
; or the first sector (0-255), each wrapping.
;------------------------------------------------------------------------------
boot_info_change:	; from: boot_info_unmark
	move.w	boot_info_line,d0               ; the line
	tst.w	d0                              ; the tracks?
	bne.s	boot_info_sectors               ; no
	add.w	d1,track_count
	tst.w	track_count
	bge.s	boot_info_tracks_top
	move.w	#$53,track_count                ; 83
boot_info_tracks_top:
	cmpi.w	#$53,track_count                ; past 83?
	ble.s	boot_info_sectors               ; no
	clr.w	track_count                     ; 0
boot_info_sectors:
	cmp.w	#$1,d0                          ; the sectors?
	bne.s	boot_info_first                 ; no
	add.w	d1,sectors_per_track
	cmpi.w	#$1,sectors_per_track
	bge.s	boot_info_sectors_top
	move.w	#$63,sectors_per_track          ; 99
boot_info_sectors_top:
	cmpi.w	#$63,sectors_per_track          ; past 99?
	ble.s	boot_info_first                 ; no
	move.w	#$1,sectors_per_track           ; 1
boot_info_first:
	cmp.w	#$3,d0                          ; the first sector?
	bne.s	boot_info_sides                 ; no
	add.w	d1,first_sector
	tst.w	first_sector
	bge.s	boot_info_first_top
	move.w	#$ff,first_sector               ; 255
boot_info_first_top:
	cmpi.w	#$ff,first_sector               ; past 255?
	ble.s	boot_info_sides                 ; no
	clr.w	first_sector                    ; 0
boot_info_sides:
	cmp.w	#$2,d0                          ; the sides?
	bne.s	boot_info_change_done           ; no
	cmpi.w	#$1,side_count                  ; one?
	bne.s	boot_info_sides_one             ; no
	move.w	#$2,side_count                  ; two
	bra.s	boot_info_change_done
boot_info_sides_one:
	move.w	#$1,side_count                  ; one
boot_info_change_done:
	rts

;------------------------------------------------------------------------------
; clear_area: the area cleared without a box.
;------------------------------------------------------------------------------
clear_area:	; from: run_module, write_sector, track_info, sample_controls
	moveq	#-1,d0                          ; no box
	bra.s	clear_area_go

;------------------------------------------------------------------------------
; clear_box_area: the area from line d4 to d7, x d5 to d6 (on 16) cleared, then a box drawn round it.
;------------------------------------------------------------------------------
clear_box_area:	; from: calculator, buffer_memory_menu, write_sector, disk_search, draw_input_box, track_info, 3 more
	moveq	#0,d0                           ; a box
clear_area_go:	; from: clear_area
	andi.w	#$fff0,d5                       ; on 16
	andi.w	#$fff0,d6
	movem.l	d4-d7,-(sp)                     ; kept
	movea.l	ripper_screen,a0                ; the screen
	move.b	$ffff8260.w,d1                  ; shift mode, the resolution
	andi.w	#$3,d1
	cmp.b	#$2,d1                          ; high?
	beq.s	clear_area_high                 ; yes
	sub.w	d4,d7                           ; the height
	mulu.w	#$a0,d4                         ; the first line
	sub.w	d5,d6                           ; the width
	lsr.w	#2,d5
	add.w	d5,d4
	adda.w	d4,a0
	subq.w	#1,d7
	lsr.w	#4,d6                           ; in 16 pixels
	subq.w	#1,d6
clear_area_line:
	movem.l	d6/a0,-(sp)
clear_area_long:
	clr.l	(a0)+                           ; cleared
	dbra	d6,clear_area_long
	movem.l	(sp)+,d6/a0
	lea	$a0(a0),a0                      ; the next line
	dbra	d7,clear_area_line
clear_area_done:
	movem.l	(sp)+,d4-d7
	tst.w	d0                              ; a box?
	bne.s	clear_area_end                  ; no
	bsr.w	draw_box                        ; drawn
clear_area_end:
	rts
clear_area_high:
	sub.w	d4,d7                           ; the height
	mulu.w	#$a0,d4
	sub.w	d5,d6
	lsr.w	#3,d5
	add.w	d5,d4
	adda.w	d4,a0
	subq.w	#1,d7
	lsr.w	#4,d6                           ; in 16 pixels
	subq.w	#1,d6
clear_area_high_line:
	movem.l	d6/a0,-(sp)
clear_area_high_word:
	clr.w	(a0)                            ; each line twice
	clr.w	$50(a0)
	addq.l	#2,a0
	dbra	d6,clear_area_high_word
	movem.l	(sp)+,d6/a0
	lea	$a0(a0),a0                      ; the next line
	dbra	d7,clear_area_high_line
	bra.s	clear_area_done

;------------------------------------------------------------------------------
; select_drive_side: the drive set and side 1 if wanted, else select_drive.
;------------------------------------------------------------------------------
select_drive_side:	; from: read_sectors, write_sector, disk_search, search_buffer, track_info, read_track
	tst.w	side                            ; side 1?
	bne.s	select_drive_side_one           ; yes

;------------------------------------------------------------------------------
; select_drive: drive A or B selected, side 0 (the sound chip's port A).
;------------------------------------------------------------------------------
select_drive:	; from: disk_ripper, change_drive, boot_info
	cmpi.b	#$41,drive_letter               ; A?
	bne.s	select_drive_b                  ; no
	move.l	#$e0e0505,$ffff8800.w           ; PSG register select, drive A, side 0
	rts
select_drive_b:
	move.l	#$e0e0303,$ffff8800.w           ; PSG register select, drive B, side 0
	rts
select_drive_side_one:	; from: select_drive_side
	cmpi.b	#$41,drive_letter               ; A?
	bne.s	select_drive_b_side_one         ; no
	move.l	#$e0e0404,$ffff8800.w           ; PSG register select, drive A, side 1
	rts
select_drive_b_side_one:
	move.l	#$e0e0202,$ffff8800.w           ; PSG register select, drive B, side 1
	rts

;------------------------------------------------------------------------------
; show_disk_settings: "DRIVE :", "TRACK : $", "SECTOR : $" and "SIDE" shown.
;------------------------------------------------------------------------------
show_disk_settings:	; from: disk_ripper, change_drive, set_track, set_sector, toggle_side, previous_sector, 1 more
	lea	position_3_14,a0                ; "DRIVE :"
	bsr.w	print
	lea	drive_letter,a0                 ; the drive's letter
	bsr.w	print
	lea	position_3_33,a0                ; "TRACK : $"
	bsr.w	print
	movea.w	track,a6                        ; the track
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text+6,a0                   ; the last 2 digits
	bsr.w	print
	lea	position_3_54_at_eec6,a0        ; "SECTOR : $"
	bsr.w	print
	movea.w	sector,a6                       ; the sector
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+6,a0
	bsr.w	print
	lea	position_3_72,a0                ; the side
	bsr.w	print
	suba.l	a6,a6                           ; 0
	tst.w	side                            ; side 1?
	beq.s	show_disk_settings_side         ; no
	addq.l	#1,a6                           ; 1
show_disk_settings_side:
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+7,a0                   ; the last digit
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; draw_buffer: the buffer shown from the view: 16 lines of offset, 16 hex bytes and their characters, or
; disassembled in disassembly view.
;------------------------------------------------------------------------------
draw_buffer:                                    ; from: toggle_hex_disassembly, edit_buffer, page_up_buffer,
                                                ;   page_down_buffer, line_down_buffer, line_up_buffer, 4 more
	tst.w	disassembly_view                ; disassembly?
	beq.s	draw_buffer_hex                 ; no
	bra.w	draw_buffer_disassembly         ; disassembled
draw_buffer_hex:
	lea	dump_lines,a4                   ; the text: ESC Y row 5 column 0, cursor off, right
	move.b	#$1b,(a4)+
	move.b	#$59,(a4)+
	move.b	#$25,(a4)+
	move.b	#$20,(a4)+
	move.b	#$1b,(a4)+
	move.b	#$66,(a4)+
	move.b	#$1b,(a4)+
	move.b	#$43,(a4)+
	lea	hex_digits,a5                   ; the digits
	movea.l	buffer_view,a6                  ; the view
	moveq	#15,d6                          ; 16 lines
	movea.l	buffer_view,a3
	suba.l	#disk_buffer,a3                 ; the offset in the buffer
draw_buffer_line:
	movem.l	a3/a6,-(sp)
	move.w	#$f,d7                          ; 16 bytes
	move.l	a6,-(sp)
	movea.l	a3,a6                           ; the offset
	bsr.w	put_hex_address
	movea.l	(sp)+,a6
draw_buffer_hex_byte:
	bsr.w	put_hex_byte
	dbra	d7,draw_buffer_hex_byte
	movem.l	(sp)+,a3/a6
	lea	$10(a3),a3                      ; on 16
	move.b	#$20,(a4)+                      ; two spaces
	move.b	#$20,(a4)+
	moveq	#15,d7                          ; 16 characters
draw_buffer_char:
	move.w	#$ff,d0
	move.b	(a6),d0
	addq.l	#1,a6
	cmp.w	#$20,d0                         ; a control character?
	bge.s	draw_buffer_char_put            ; no
	move.b	#$2e,d0                         ; '.'
draw_buffer_char_put:
	move.b	d0,(a4)+
	dbra	d7,draw_buffer_char
	move.b	#$b,(a4)+                       ; $0B, CR, right
	move.b	#$d,(a4)+
	move.b	#$1b,(a4)+
	move.b	#$43,(a4)+
	dbra	d6,draw_buffer_line
	move.b	#$0,(a4)                        ; ended
	lea	dump_lines,a0
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; module_keys: Shift F1 to Shift F10 jump straight to another module (the stack reset), except the one in d1;
; other keys back to the caller.
;------------------------------------------------------------------------------
module_keys:	; from: disk_ripper, external_call, music_ripper, memory_ripper, picture_ripper, disk_utility, 1 more
	movea.l	(sp)+,a0                        ; the caller
	cmp.l	#$540000,d0                     ; Shift F1?
	bne.s	module_keys_f2                  ; no
	cmp.w	#$1,d1                          ; the picture ripper already?
	beq.w	module_keys_back                ; yes
	lea	$3e0.w,sp                       ; the stack reset
	bra.w	menu_picture_ripper             ; the picture ripper
module_keys_f2:
	cmp.l	#$550000,d0                     ; Shift F2?
	bne.s	module_keys_f3                  ; no
	cmp.w	#$2,d1
	beq.w	module_keys_back
	lea	$3e0.w,sp
	bra.w	menu_memory_ripper              ; the memory ripper
module_keys_f3:
	cmp.l	#$560000,d0                     ; Shift F3?
	bne.s	module_keys_f4                  ; no
	cmp.w	#$3,d1
	beq.w	module_keys_back
	lea	$3e0.w,sp
	bra.w	menu_disk_utility               ; the disk utility
module_keys_f4:
	cmp.l	#$570000,d0                     ; Shift F4?
	bne.s	module_keys_f5                  ; no
	cmp.w	#$4,d1
	beq.w	module_keys_back
	lea	$3e0.w,sp
	bra.w	external_call                   ; external call
module_keys_f5:
	cmp.l	#$580000,d0                     ; Shift F5?
	bne.s	module_keys_f6                  ; no
	cmp.w	#$5,d1
	beq.w	module_keys_back
	lea	$3e0.w,sp
	bra.w	menu_external_loader            ; external loader
module_keys_f6:
	cmp.l	#$590000,d0                     ; Shift F6?
	bne.s	module_keys_f7                  ; no
	cmp.w	#$6,d1
	beq.w	module_keys_back
	lea	$3e0.w,sp
	bra.w	menu_music_ripper               ; the music ripper
module_keys_f7:
	cmp.l	#$5a0000,d0                     ; Shift F7?
	bne.s	module_keys_f9                  ; no
	cmp.w	#$7,d1
	beq.w	module_keys_back
	lea	$3e0.w,sp
	bra.w	disk_ripper                     ; the disk ripper
module_keys_f9:
	cmp.l	#$5c0000,d0                     ; Shift F9?
	bne.s	module_keys_back                ; no
	cmp.w	#$9,d1
	beq.w	module_keys_back
	lea	$3e0.w,sp
	bra.w	info                            ; info
module_keys_back:
	jmp	(a0)                            ; back

;------------------------------------------------------------------------------
; info (F9): THE ULTIMATE RIPPER, VERSION 1.2, by U.D, Euro Soft, until a key.
;------------------------------------------------------------------------------
info:	; from: main_menu, module_keys
	bsr.w	stop_raster                     ; the screen set
	lea	text_the_ultimate_ripper,a0     ; the text
	bsr.w	print
	moveq	#28,d4
	move.w	#$a0,d5
	move.w	#$1e0,d6
	move.w	#$8c,d7
	bsr.w	draw_box                        ; the box
	bsr.w	get_key                         ; a key
	bra.w	main_menu
menu_external_loader:	; from: main_menu, module_keys
	bsr.w	stop_raster                     ; the screen set
	jsr	external_loader                 ; external loader
	bra.w	main_menu
menu_music_ripper:	; from: main_menu, module_keys
	bsr.w	stop_raster                     ; the screen set
	bsr.w	music_ripper                    ; the music ripper
	bra.w	main_menu
menu_picture_ripper:	; from: main_menu, module_keys
	bsr.w	stop_raster                     ; the screen set
	bsr.w	picture_ripper                  ; the picture ripper
	bra.w	main_menu
menu_memory_ripper:	; from: main_menu, module_keys
	bsr.w	stop_raster                     ; the screen set
	bsr.w	memory_ripper                   ; the memory ripper
	bra.w	main_menu
menu_disk_utility:	; from: main_menu, module_keys
	bsr.w	stop_raster                     ; the screen set
	jsr	disk_utility                    ; the disk utility
	bra.w	main_menu

;------------------------------------------------------------------------------
; external_call (F4): the free RAM, its start and the load address shown; F1 LOAD & EXECUTE a program (Pexec),
; F2 LOAD ADDRESS changes where the free part starts, F10 back.
;------------------------------------------------------------------------------
external_call:	; from: main_menu, modules, module_keys
	bsr.w	stop_raster                     ; the screen set
	lea	text_external_call,a0           ; its title
	bsr.w	print
	lea	text_f1_load_executef2,a0       ; the menu
	bsr.w	print
	moveq	#0,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#22,d7
	bsr.w	draw_box                        ; the top box
	moveq	#35,d4
	move.w	#$dc,d5
	move.w	#$1b8,d6
	moveq	#105,d7
	bsr.w	draw_box                        ; the menu's box
	moveq	#120,d4
	move.w	#$b4,d5
	move.w	#$1e0,d6
	move.w	#$af,d7
	bsr.w	draw_box                        ; the details' box
	lea	text_free_ram,a0                ; "FREE RAM      : $"
	bsr.w	print
	move.l	#$ffffffff,-(sp)
	move.w	#$48,-(sp)                      ; Malloc(-1)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	move.l	d0,free_ram                     ; the free RAM
	movea.l	d0,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	lea	text_start_free_ram,a0          ; "START FREE RAM: $"
	bsr.w	print
	move.l	free_ram,d0
	subi.l	#$3e8,d0                        ; less 1000
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	move.l	d0,range_start                  ; its start
	movea.l	d0,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	lea	text_start_load_ram,a0          ; "START LOAD RAM: $"
	bsr.w	print
	move.l	range_start,load_address        ; the load address
	movea.l	load_address,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	move.l	range_start,-(sp)               ; the block
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
external_call_key:
	lea	position_24_0_at_e30e,a0        ; the line cleared
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$3,d0                          ; Control C?
	bne.s	external_call_function          ; no
	moveq	#4,d0                           ; the calculator, then here
	bra.w	run_module
external_call_function:
	moveq	#4,d1
	bsr.w	module_keys                     ; the module keys
	swap	d0
	cmp.b	#$3b,d0                         ; F1?
	beq.w	external_call_execute           ; load and execute
	cmp.b	#$3c,d0                         ; F2?
	beq.w	external_call_address           ; the load address
	cmp.b	#$44,d0                         ; F10?
	bne.s	external_call_key               ; no: another key
	bra.w	main_menu
external_call_execute:
	movea.l	range_start,a0                  ; the free start
	move.l	load_address,d0                 ; the load address
	sub.l	a0,d0                           ; the room before it
	move.l	d0,-(sp)
	move.w	#$48,-(sp)                      ; Malloc: taken
	trap	#1                              ; Malloc
	addq.l	#6,sp
	lea	text_enter_filename,a0          ; "ENTER FILENAME : "
	bsr.w	print
	move.w	#$3d00,name_buffer              ; 61 characters
	pea	name_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.s	external_call_free              ; no
	lea	name_buffer+2,a0                ; the name
	pea	empty_string                    ; no environment
	pea	empty_string                    ; no command line
	move.l	a0,-(sp)
	move.w	#$0,-(sp)                       ; load and go
	move.w	#$4b,-(sp)
	trap	#1                              ; Pexec
	adda.l	#$10,sp
	tst.w	d0                              ; an error?
	bpl.s	external_call_free              ; no
	bsr.w	show_error                      ; the error shown
external_call_free:
	move.l	range_start,-(sp)               ; the block
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	bra.w	external_call                   ; the screen again
external_call_address:
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	external_call_key               ; no
	cmp.l	range_start,d2                  ; below the free start?
	blt.w	external_call_key               ; yes: no
	tst.l	d2                              ; negative?
	bmi.w	external_call_key               ; yes: no
	move.l	d2,d6
	sub.l	range_start,d6                  ; from the free start
	cmp.l	free_ram,d6                     ; past the free RAM?
	bpl.w	external_call_key               ; yes: no
	move.l	d2,load_address                 ; the load address
	lea	text_start_load_ram,a0          ; "START LOAD RAM: $"
	bsr.w	print
	movea.l	load_address,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	bra.w	external_call_key

;------------------------------------------------------------------------------
; show_gemdos_error: the GEMDOS or BIOS error d0 named ("... (PRESS A KEY TO CONTINUE)") until a key.
;------------------------------------------------------------------------------
show_gemdos_error:	; from: set_path
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	move.l	d0,-(sp)
	lea	position_23_1,a0                ; the line
	bsr.w	print
	move.l	(sp)+,d0
	lea	error_numbers,a0                ; the error numbers
	move.w	d0,d1
	neg.w	d1                              ; positive
	moveq	#0,d2
show_gemdos_error_find:
	cmp.w	(a0),d1                         ; this one?
	beq.s	show_gemdos_error_text          ; yes
	addq.w	#1,d2
	tst.w	(a0)+                           ; the end?
	bpl.s	show_gemdos_error_find          ; no
	moveq	#2,d2                           ; "UNKNOW ERROR" (the third)
show_gemdos_error_text:
	lea	error_texts,a0                  ; the texts
	add.w	d2,d2
	add.w	d2,d2                           ; * 4
	movea.l	0(a0,d2.w),a0                   ; its text
	bsr.w	print
	bsr.w	get_key                         ; a key
	lea	position_23_1_at_e317,a0        ; the line cleared
	bsr.w	print
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; music_ripper (F6): MUSIC RIPPER: F1 SEARCH, F2 (the music found, saved), F3 SAMPLE RIPPER, F10 back; the
; music player's VBL routine is in vblqueue while the menu waits.
;------------------------------------------------------------------------------
music_ripper:	; from: modules, info, sample_ripper, music_save
	clr.w	music_kind
	lea	text_music_ripper_f1,a0         ; its title
	bsr.w	print
	moveq	#0,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#22,d7
	bsr.w	draw_box                        ; the top box
	moveq	#35,d4
	move.w	#$dc,d5
	move.w	#$1b8,d6
	moveq	#105,d7
	bsr.w	draw_box                        ; the menu's box
	moveq	#120,d4
	move.w	#$b4,d5
	move.w	#$1e0,d6
	move.w	#$af,d7
	bsr.w	draw_box                        ; the details' box
	moveq	#40,d4
	move.w	#$14,d5
	move.w	#$8c,d6
	moveq	#100,d7
	bsr.w	draw_box                        ; the left box
	moveq	#40,d4
	move.w	#$1f4,d5
	move.w	#$26c,d6
	moveq	#100,d7
	bsr.w	draw_box                        ; the right box
music_ripper_key:	; from: music_search, find_soundtracker
	lea	position_24_0_at_e30e,a0        ; the line cleared
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$3,d0                          ; Control C?
	bne.s	music_ripper_function           ; no
	moveq	#6,d0                           ; the calculator, then here
	bra.w	run_module
music_ripper_function:
	clr.l	$4da.w                          ; the player stopped
	moveq	#6,d1                           ; the module keys
	bsr.w	module_keys
	move.l	#vu_meter,$4da.w                ; the player again
	swap	d0
	cmp.b	#$3b,d0                         ; F1?
	beq.w	music_search                    ; search
	cmp.b	#$3c,d0                         ; F2?
	beq.w	music_save
	cmp.b	#$3d,d0                         ; F3?
	beq.w	sample_ripper                   ; the sample ripper
	cmp.b	#$44,d0                         ; F10?
	bne.s	music_ripper_key                ; no: another key
	clr.l	$4da.w                          ; the player stopped
	rts

;------------------------------------------------------------------------------
; sample_ripper (F3): SAMPLE RIPPER: the start and end address, the frequency, PLAY and the sign (or the STE
; controls), changed with the keys; the frame and boxes drawn, the sample's range kept in order.
;------------------------------------------------------------------------------
sample_ripper:	; from: music_ripper
	move.w	#$1,ym_replay
	clr.l	$4da.w                          ; the player stopped
	clr.b	$484.w                          ; conterm, no key click
	clr.w	sample_unsigned
	move.w	#$80,sample_sign                ; signed
	move.l	sample_start,d0                 ; the start
	tst.l	d0
	bge.s	sample_ripper_start_set
	clr.l	d0
sample_ripper_start_set:
	move.l	d0,sample_start
	movea.l	d0,a0
	cmpa.l	sample_end,a0                   ; past the end?
	ble.s	sample_ripper_screen            ; no
	addq.l	#1,a0
	move.l	a0,sample_end                   ; the end one past
sample_ripper_screen:
	lea	text_sample_ripper_f1,a0        ; its title
	bsr.w	print
	moveq	#0,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#20,d7
	bsr.w	draw_box                        ; the top box
	moveq	#22,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#43,d7
	bsr.w	draw_box                        ; the next box
	bsr.w	show_sample_details             ; the sample drawn
sample_ripper_redraw:	; from: modules, sample_end_right, sample_set_start, sample_set_end
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.w	#$3,d0
	cmp.b	#$2,d0                          ; high?
	bne.s	sample_ripper_boxes             ; no
	bsr.w	clear_wave_area
sample_ripper_boxes:
	moveq	#49,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#114,d7
	bsr.w	draw_box                        ; the box
sample_ripper_menu:	; from: sample_controls
	moveq	#114,d4
	moveq	#0,d5
	move.w	#$27f,d6
	move.w	#$b3,d7
	bsr.w	draw_box                        ; the menu's box
	bsr.w	draw_sample                     ; the menu
	bra.w	sample_ripper_sign
sample_ripper_key:                              ; from: sample_toggle_controls, sample_toggle_end, sample_end_right,
                                                ;   sample_set_start, sample_set_end, sample_save, 1 more
	lea	position_24_0_at_e30e,a0        ; the line cleared
	bsr.w	print
sample_ripper_wait:	; from: sample_play
	bsr.w	wait_key                        ; a key
	cmp.b	#$3,d0                          ; Control C?
	bne.s	sample_ripper_shift_right       ; no
	moveq	#8,d0                           ; the calculator, then here
	bra.w	run_module
sample_ripper_shift_right:
	cmp.b	#$36,d0                         ; Shift (right)?
	bne.s	sample_ripper_shift_left        ; no
	swap	d0
	cmp.b	#$4d,d0                         ; right?
	beq.w	sample_end_shift_right
	bra.s	sample_ripper_key
sample_ripper_shift_left:
	cmp.b	#$34,d0                         ; Shift (left)?
	bne.s	sample_ripper_arrows            ; no
	swap	d0
	cmp.b	#$4b,d0                         ; left?
	beq.w	sample_end_shift_left
	bra.s	sample_ripper_key
sample_ripper_arrows:
	swap	d0
	cmp.b	#$4b,d0                         ; left?
	beq.w	sample_end_left
	cmp.b	#$4d,d0                         ; right?
	beq.w	sample_end_right
	cmp.b	#$48,d0                         ; up?
	beq.w	sample_toggle_end
	cmp.b	#$50,d0                         ; down?
	beq.w	sample_toggle_end
	cmp.b	#$3b,d0                         ; F1?
	beq.w	sample_set_start
	cmp.b	#$3c,d0                         ; F2?
	beq.w	sample_set_end
	cmp.b	#$3d,d0                         ; F3?
	beq.w	sample_frequency
	cmp.b	#$3e,d0                         ; F4?
	beq.w	sample_play
	cmp.b	#$3f,d0                         ; F5?
	beq.w	sample_save
	cmp.b	#$40,d0                         ; F6?
	beq.w	sample_ripper_f6
	cmp.b	#$41,d0                         ; F7?
	beq.w	sample_toggle_controls
	cmp.b	#$44,d0                         ; F10?
	bne.w	sample_ripper_key               ; no: another key
	move.b	#$7,$484.w                      ; conterm, key click back
	bra.w	music_ripper                    ; the music ripper
sample_ripper_f6:
	tst.w	ym_replay                       ; the sound chip?
	beq.w	sample_controls                 ; no (STE): the controls
	not.w	sample_unsigned                 ; the sign changed
sample_ripper_sign:	; from: sample_toggle_controls
	tst.w	ym_replay
	beq.w	sample_ripper_key               ; no
	lea	position_4_60,a0                ; "SIGN : "
	bsr.w	print
	lea	text_on,a0                      ; "+"
	move.w	#$80,sample_sign
	tst.w	sample_unsigned
	beq.s	sample_ripper_sign_show
	lea	text_off,a0                     ; "-"
	move.w	#$0,sample_sign
sample_ripper_sign_show:
	bsr.w	print
	bra.w	sample_ripper_key

;------------------------------------------------------------------------------
; sample_controls: the STE sound's GENERAL VOLUME, VOLUME (RIGHT), VOLUME (LEFT), TREBLE, BASS and STEREO:
; up and down pick one, left and right change it; any other key leaves.
;------------------------------------------------------------------------------
sample_controls:	; from: sample_ripper
	moveq	#73,d4
	move.w	#$c8,d5
	move.w	#$1ae,d6
	move.w	#$82,d7
	bsr.w	clear_box_area                  ; the box
	lea	text_general_volume_volume,a0   ; the names
	bsr.w	print
	bsr.w	show_sample_controls            ; the values
sample_controls_key:
	bsr.w	wait_key                        ; a key
	swap	d0
	cmp.b	#$4d,d0                         ; right?
	beq.w	sample_controls_right
	cmp.b	#$4b,d0                         ; left?
	beq.w	sample_controls_left
	cmp.b	#$50,d0                         ; down?
	beq.w	sample_controls_down
	cmp.b	#$48,d0                         ; up?
	beq.w	sample_controls_up
	moveq	#73,d4
	move.w	#$c8,d5
	move.w	#$1b8,d6
	move.w	#$83,d7
	bsr.w	clear_area                      ; cleared
	bra.w	sample_ripper_menu
sample_controls_right:
	cmpi.w	#$0,control_line                ; the volume?
	beq.w	sample_volume_up
	cmpi.w	#$1,control_line                ; the right?
	beq.w	sample_right_up
	cmpi.w	#$2,control_line                ; the left?
	beq.w	sample_left_up
	cmpi.w	#$3,control_line                ; the treble?
	beq.w	sample_treble_up
	cmpi.w	#$4,control_line                ; the bass?
	beq.w	sample_bass_up
	cmpi.w	#$5,control_line                ; stereo?
	beq.w	sample_stereo
	bra.w	sample_controls_key
sample_controls_left:
	cmpi.w	#$0,control_line                ; the volume?
	beq.w	sample_volume_down
	cmpi.w	#$1,control_line                ; the right?
	beq.w	sample_right_down
	cmpi.w	#$2,control_line                ; the left?
	beq.w	sample_left_down
	cmpi.w	#$3,control_line                ; the treble?
	beq.w	sample_treble_down
	cmpi.w	#$4,control_line                ; the bass?
	beq.w	sample_bass_down
	cmpi.w	#$5,control_line                ; stereo?
	beq.w	sample_stereo
	bra.w	sample_controls_key
sample_volume_down:
	moveq	#-1,d0                          ; -1
	bra.s	sample_volume_change
sample_volume_up:
	moveq	#1,d0                           ; +1
sample_volume_change:
	move.w	ste_volume,d1
	add.w	d0,d1
	tst.w	d1                              ; below 0?
	bge.s	sample_volume_top               ; no
	move.w	#$28,d1                         ; 40
sample_volume_top:
	cmp.w	#$28,d1                         ; past 40?
	ble.s	sample_volume_set               ; no
	clr.w	d1                              ; 0
sample_volume_set:
	move.w	d1,ste_volume
	bsr.w	show_volume                     ; shown
	bra.w	sample_controls_key
sample_right_down:
	moveq	#-1,d0                          ; -1
	bra.s	sample_right_change
sample_right_up:
	moveq	#1,d0                           ; +1
sample_right_change:
	move.w	ste_right,d1
	add.w	d0,d1
	tst.w	d1                              ; below 0?
	bge.s	sample_right_top                ; no
	move.w	#$14,d1                         ; 20
sample_right_top:
	cmp.w	#$14,d1                         ; past 20?
	ble.s	sample_right_set                ; no
	clr.w	d1                              ; 0
sample_right_set:
	move.w	d1,ste_right
	bsr.w	show_right                      ; shown
	bra.w	sample_controls_key
sample_left_down:
	moveq	#-1,d0                          ; -1
	bra.s	sample_left_change
sample_left_up:
	moveq	#1,d0                           ; +1
sample_left_change:
	move.w	ste_left,d1
	add.w	d0,d1
	tst.w	d1                              ; below 0?
	bge.s	sample_left_top                 ; no
	move.w	#$14,d1                         ; 20
sample_left_top:
	cmp.w	#$14,d1                         ; past 20?
	ble.s	sample_left_set                 ; no
	clr.w	d1                              ; 0
sample_left_set:
	move.w	d1,ste_left
	bsr.w	show_left                       ; shown
	bra.w	sample_controls_key
sample_treble_down:
	moveq	#-1,d0                          ; -1
	bra.s	sample_treble_change
sample_treble_up:
	moveq	#1,d0                           ; +1
sample_treble_change:
	move.w	ste_treble,d1
	add.w	d0,d1
	tst.w	d1                              ; below 0?
	bge.s	sample_treble_top               ; no
	move.w	#$c,d1                          ; 12
sample_treble_top:
	cmp.w	#$c,d1                          ; past 12?
	ble.s	sample_treble_set               ; no
	clr.w	d1                              ; 0
sample_treble_set:
	move.w	d1,ste_treble
	bsr.w	show_treble                     ; shown
	bra.w	sample_controls_key
sample_bass_down:
	moveq	#-1,d0                          ; -1
	bra.s	sample_bass_change
sample_bass_up:
	moveq	#1,d0                           ; +1
sample_bass_change:
	move.w	ste_bass,d1
	add.w	d0,d1
	tst.w	d1                              ; below 0?
	bge.s	sample_bass_top                 ; no
	move.w	#$c,d1                          ; 12
sample_bass_top:
	cmp.w	#$c,d1                          ; past 12?
	ble.s	sample_bass_set                 ; no
	clr.w	d1                              ; 0
sample_bass_set:
	move.w	d1,ste_bass
	bsr.w	show_bass                       ; shown
	bra.w	sample_controls_key
sample_stereo:
	not.w	ste_stereo                      ; on or off
	bsr.w	show_stereo                     ; shown
	bra.w	sample_controls_key
sample_controls_up:
	bsr.w	sample_controls_unmark          ; unmarked
	move.w	control_line,d0
	tst.w	d0                              ; the first?
	beq.s	sample_controls_last            ; yes: the last
	subq.w	#1,d0
	move.w	d0,control_line
	mulu.w	#$5,d0                          ; 5 bytes a line
	lea	position_10_47,a0
	lea	0(a0,d0.w),a0
	tst.b	(a0)                            ; the end?
	bge.s	sample_controls_mark            ; no
sample_controls_last:
	lea	position_15_47,a0               ; the last
	move.w	#$5,d0
	move.w	d0,control_line
sample_controls_mark:
	bsr.w	print
	lea	arrow_text,a0                   ; its marker
	bsr.w	print
	bra.w	sample_controls_key
sample_controls_down:
	bsr.w	sample_controls_unmark          ; unmarked
	move.w	control_line,d0
	addq.w	#1,d0                           ; the next
	move.w	d0,control_line
	mulu.w	#$5,d0
	lea	position_10_47,a0
	lea	0(a0,d0.w),a0
	tst.b	(a0)                            ; the end?
	bge.s	sample_controls_mark_down       ; no
	clr.w	d0                              ; the first
	lea	position_10_47,a0
	move.w	d0,control_line
sample_controls_mark_down:
	bsr.w	print
	lea	arrow_text,a0                   ; its marker
	bsr.w	print
	bra.w	sample_controls_key

;------------------------------------------------------------------------------
; show_sample_controls: the six values and the current line's marker.
;------------------------------------------------------------------------------
show_sample_controls:	; from: sample_controls
	bsr.w	show_volume                     ; the volume
	bsr.w	show_right                      ; the right
	bsr.w	show_left                       ; the left
	bsr.w	show_treble                     ; the treble
	bsr.w	show_bass                       ; the bass
	bsr.w	show_stereo                     ; stereo
	bsr.w	sample_controls_marker          ; the marker
	rts

sample_controls_unmark:	; from: sample_controls
	lea	position_10_47,a0               ; the lines
	move.w	control_line,d0                 ; the current
	mulu.w	#$5,d0                          ; 5 bytes a line
	lea	0(a0,d0.w),a0
	bsr.w	print
	lea	no_arrow_text,a0                ; no marker
	bsr.w	print
	rts

sample_controls_marker:	; from: show_sample_controls
	lea	position_10_47,a0               ; the lines
	move.w	control_line,d0                 ; the current
	mulu.w	#$5,d0
	lea	0(a0,d0.w),a0
	bsr.w	print
	lea	arrow_text,a0                   ; its marker
	bsr.w	print
	rts

show_volume:	; from: sample_controls, show_sample_controls
	lea	position_10_42,a0               ; its place
	bsr.w	print
	move.w	ste_volume,d0                   ; the volume
	bsr.w	show_decimal_word               ; shown
	rts

show_right:	; from: sample_controls, show_sample_controls
	lea	position_11_42,a0               ; its place
	bsr.w	print
	move.w	ste_right,d0                    ; the right
	bsr.w	show_decimal_word               ; shown
	rts

show_left:	; from: sample_controls, show_sample_controls
	lea	position_12_42,a0               ; its place
	bsr.w	print
	move.w	ste_left,d0                     ; the left
	bsr.w	show_decimal_word               ; shown
	rts

show_treble:	; from: sample_controls, show_sample_controls
	lea	position_13_42,a0               ; its place
	bsr.w	print
	move.w	ste_treble,d0                   ; the treble
	bsr.w	show_decimal_word               ; shown
	rts

show_bass:	; from: sample_controls, show_sample_controls
	lea	position_14_42,a0               ; its place
	bsr.w	print
	move.w	ste_bass,d0                     ; the bass
	bsr.w	show_decimal_word               ; shown
	rts

show_stereo:	; from: sample_controls, show_sample_controls
	lea	position_15_42,a0               ; its place
	bsr.w	print
	lea	text_on,a0                      ; "ON"
	tst.w	ste_stereo                      ; on?
	bne.s	show_stereo_text                ; yes
	lea	text_off,a0                     ; "OFF"
show_stereo_text:
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; show_decimal_word: d0 in decimal (two digits).
;------------------------------------------------------------------------------
show_decimal_word:	; from: show_volume, show_right, show_left, show_treble, show_bass
	bsr.w	to_decimal_digits               ; in decimal
	movea.l	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex digits
	clr.b	(a4)
	lea	hex_text+6,a0                   ; the last 2
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; sample_average: the average of d0 samples at a0 (d3 its negation), a0 past them.
;------------------------------------------------------------------------------
sample_average:	; from: draw_sample
	movea.l	a0,a1
	move.w	d0,d7                           ; the count
	beq.s	sample_average_go
	subq.w	#1,d7
sample_average_go:
	moveq	#0,d6
	moveq	#0,d5
	moveq	#0,d4
sample_average_byte:
	move.b	(a1)+,d4
	add.w	d4,d6                           ; the sum
	addq.w	#1,d5                           ; counted
	dbra	d7,sample_average_byte
	divs.w	d5,d6                           ; the average
	move.w	d6,d3
	neg.w	d3
	adda.w	d0,a0                           ; past them
	rts

;------------------------------------------------------------------------------
; sample_toggle_controls (F7): the replay through the sound chip (with its sign) or the STE DMA sound (with
; its controls), the STE only with TOS 1.06 or later.
;------------------------------------------------------------------------------
sample_toggle_controls:	; from: sample_ripper
	move.w	$2.w,d0                         ; TOS's version
	cmp.w	#$106,d0                        ; below 1.06?
	blt.w	sample_ripper_key               ; yes: no
	tst.w	ym_replay                       ; the sound chip now?
	beq.w	sample_ym_mode                  ; no
	clr.w	ym_replay                       ; the STE now
	lea	text_sample_ripper_f1_start_address,a0 ; "CONTROL"
	bsr.w	print
	move.l	sample_start,range_start
	bsr.w	show_sample_start               ; the start
	bsr.w	show_sample_end                 ; the end
	bsr.w	show_ste_frequency              ; the STE frequency
	bsr.w	show_sample_marker
	bra.w	sample_ripper_key
sample_ym_mode:
	move.w	#$1,ym_replay                   ; the sound chip now
	lea	text_sample_ripper_f1_start,a0  ; "SIGN"
	bsr.w	print
	move.l	sample_start,range_start
	bsr.w	show_sample_start               ; the start
	bsr.w	show_sample_end                 ; the end
	bsr.w	show_frequency                  ; the frequency
	bsr.w	show_sample_marker
	bra.w	sample_ripper_sign              ; the sign

;------------------------------------------------------------------------------
; draw_sample: the sample from the start to the end drawn as a wave across 640 pixels: each step the average
; of its share of the samples, a line from the last point.
;------------------------------------------------------------------------------
draw_sample:	; from: sample_ripper
	movea.l	range_start,a0                  ; the start
	move.l	sample_end,d0                   ; the end
	sub.l	a0,d0                           ; the length
	move.w	#$280,d1                        ; 640 pixels
	divu.w	d1,d0                           ; samples a pixel
	moveq	#2,d2                           ; x
	move.b	(a0),d1                         ; the first sample
	ext.w	d1
	lsr.w	#1,d1                           ; halved
	ext.w	d1
	neg.w	d1
	addi.w	#$72,d1                         ; about line 114
	move.w	d1,line_from_y                  ; the last y
	move.w	#$1,line_from_x                 ; the last x
draw_sample_step:
	bsr.w	sample_average                  ; the next average
	ext.w	d3
	lsr.l	#1,d3                           ; halved
	ext.w	d3
	addi.w	#$72,d3
	move.w	d3,line_to_y                    ; y
	move.w	d2,line_to_x                    ; x
	movem.l	d0/d2/a0,-(sp)
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.w	#$3,d0
	cmp.b	#$2,d0                          ; high?
	bne.s	draw_sample_medium              ; no
	bsr.w	draw_line_high                  ; the line (high)
	bra.s	draw_sample_next
draw_sample_medium:
	bsr.w	draw_line_medium                ; the line (medium)
draw_sample_next:
	movem.l	(sp)+,d0/d2/a0
	move.w	line_to_x,line_from_x           ; the last point
	move.w	line_to_y,line_from_y
	addq.w	#1,d2                           ; the next x
	cmp.w	#$27f,d2                        ; the right?
	blt.s	draw_sample_step                ; no
	rts

;------------------------------------------------------------------------------
; clear_wave_area: the wave's area cleared (high resolution).
;------------------------------------------------------------------------------
clear_wave_area:	; from: sample_ripper
	movea.l	ripper_screen,a5                ; the screen
	adda.l	#$1f40,a5                       ; from line 50
	move.w	#$103,d0                        ; 260 lines
clear_wave_area_line:
	moveq	#19,d1
clear_wave_area_long:
	clr.l	(a5)+                           ; cleared
	dbra	d1,clear_wave_area_long
	dbra	d0,clear_wave_area_line
	rts

;------------------------------------------------------------------------------
; draw_line_medium: a line from (x0,y0) to (x1,y1) in plane 1 of the medium resolution screen (Bresenham).
;------------------------------------------------------------------------------
draw_line_medium:	; from: draw_sample
	movea.l	ripper_screen,a5                ; the screen
	addq.l	#2,a5                           ; plane 1
	movem.w	line_from_x,d0-d1/d4-d5/d7      ; the points
	exg	d1,d5
	exg	d4,d1
	cmp.w	d5,d0                           ; left to right
	bpl.s	draw_line_medium_dx
	exg	d0,d5
	exg	d1,d4
draw_line_medium_dx:
	sub.w	d0,d5                           ; dx
	neg.w	d5
	sub.w	d1,d4                           ; dy
	bpl.s	draw_line_medium_address
	neg.w	d4
	neg.w	d7                              ; up
draw_line_medium_address:
	lsl.w	#5,d1                           ; the line * 160
	move.w	d1,d2
	add.w	d1,d1
	add.w	d1,d1
	add.w	d2,d1
	move.w	d0,d2
	andi.w	#$f,d0
	sub.w	d0,d2
	lsr.w	#2,d2                           ; its word pair
	add.w	d2,d1
	adda.w	d1,a5
	add.w	d0,d0
	move.w	line_bits(pc,d0.w),d0           ; the bit
	cmp.w	d4,d5                           ; steeper?
	bmi.s	draw_line_medium_steep          ; yes
	add.w	d4,d4
	move.w	d4,d3
	sub.w	d5,d4
	move.w	d4,d6
	sub.w	d5,d6
	neg.w	d4
	bpl.s	draw_line_medium_x
draw_line_medium_flat:
	or.w	d0,(a5)                         ; the pixel
	adda.w	d7,a5
	add.w	d0,d0                           ; the next bit
	bcc.s	draw_line_medium_flat_error
	subq.w	#4,a5                           ; the word to the left
	moveq	#1,d0
draw_line_medium_flat_error:
	sub.w	d6,d4
	bpl.s	draw_line_medium_x_next
draw_line_medium_flat_next:
	dbra	d5,draw_line_medium_flat
	rts
draw_line_medium_x:
	or.w	d0,(a5)                         ; the pixel
	add.w	d0,d0
	bcc.s	draw_line_medium_x_error
	subq.w	#4,a5
	moveq	#1,d0
draw_line_medium_x_error:
	sub.w	d3,d4
	bmi.s	draw_line_medium_flat_next
draw_line_medium_x_next:
	dbra	d5,draw_line_medium_x
	rts
draw_line_medium_steep:
	add.w	d5,d5
	move.w	d5,d3
	sub.w	d4,d5
	move.w	d5,d6
	sub.w	d4,d6
	neg.w	d5
	bpl.s	draw_line_medium_y
draw_line_medium_steep_pixel:
	or.w	d0,(a5)                         ; the pixel
	adda.w	d7,a5
	add.w	d0,d0                           ; the next bit
	bcc.s	draw_line_medium_steep_error
	subq.w	#4,a5
	moveq	#1,d0
draw_line_medium_steep_error:
	sub.w	d6,d5
	bpl.s	draw_line_medium_y_next
draw_line_medium_steep_next:
	dbra	d4,draw_line_medium_steep_pixel
	rts
draw_line_medium_y:
	or.w	d0,(a5)                         ; the pixel
	adda.w	d7,a5
	sub.w	d3,d5
	bmi.s	draw_line_medium_steep_next
draw_line_medium_y_next:
	dbra	d4,draw_line_medium_y
	rts

;------------------------------------------------------------------------------
; line_bits: each pixel's bit in a word.
;------------------------------------------------------------------------------
line_bits:	; from: draw_line_medium, draw_line_high
	dc.w	$8000,$4000,$2000,$1000,$0800,$0400,$0200,$0100
	dc.w	$0080,$0040,$0020,$0010,$0008,$0004,$0002,$0001

;------------------------------------------------------------------------------
; draw_line_high: the same in high resolution, each line drawn twice (two lines a point).
;------------------------------------------------------------------------------
draw_line_high:	; from: draw_sample
	movea.l	ripper_screen,a5                ; the screen
	movem.w	line_from_x,d0-d1/d4-d5/d7      ; the points
	exg	d1,d5
	exg	d4,d1
	cmp.w	d5,d0                           ; left to right
	bpl.s	draw_line_high_dx
	exg	d0,d5
	exg	d1,d4
draw_line_high_dx:
	sub.w	d0,d5                           ; dx
	neg.w	d5
	sub.w	d1,d4                           ; dy
	bpl.s	draw_line_high_address
	neg.w	d4
	neg.w	d7                              ; up
draw_line_high_address:
	lsl.w	#5,d1                           ; the line * 160
	move.w	d1,d2
	add.w	d1,d1
	add.w	d1,d1
	add.w	d2,d1
	move.w	d0,d2
	andi.w	#$f,d0
	sub.w	d0,d2
	lsr.w	#3,d2                           ; its word
	add.w	d2,d1
	adda.w	d1,a5
	add.w	d0,d0
	move.w	line_bits(pc,d0.w),d0           ; the bit
	cmp.w	d4,d5                           ; steeper?
	bmi.s	draw_line_high_steep            ; yes
	add.w	d4,d4
	move.w	d4,d3
	sub.w	d5,d4
	move.w	d4,d6
	sub.w	d5,d6
	neg.w	d4
	bpl.s	draw_line_high_x
draw_line_high_flat:
	or.w	d0,(a5)                         ; the pixel, twice
	or.w	d0,$50(a5)
	adda.w	d7,a5
	add.w	d0,d0
	bcc.s	draw_line_high_flat_error
	subq.w	#2,a5
	moveq	#1,d0
draw_line_high_flat_error:
	sub.w	d6,d4
	bpl.s	draw_line_high_x_next
draw_line_high_flat_next:
	dbra	d5,draw_line_high_flat
	rts
draw_line_high_x:
	or.w	d0,(a5)                         ; the pixel, twice
	or.w	d0,$50(a5)
	add.w	d0,d0
	bcc.s	draw_line_high_x_error
	subq.w	#2,a5
	moveq	#1,d0
draw_line_high_x_error:
	sub.w	d3,d4
	bmi.s	draw_line_high_flat_next
draw_line_high_x_next:
	dbra	d5,draw_line_high_x
	rts
draw_line_high_steep:
	add.w	d5,d5
	move.w	d5,d3
	sub.w	d4,d5
	move.w	d5,d6
	sub.w	d4,d6
	neg.w	d5
	bpl.s	draw_line_high_y
draw_line_high_steep_pixel:
	or.w	d0,(a5)                         ; the pixel, twice
	or.w	d0,$50(a5)
	adda.w	d7,a5
	add.w	d0,d0
	bcc.s	draw_line_high_steep_error
	subq.w	#2,a5
	moveq	#1,d0
draw_line_high_steep_error:
	sub.w	d6,d5
	bpl.s	draw_line_high_y_next
draw_line_high_steep_next:
	dbra	d4,draw_line_high_steep_pixel
	rts
draw_line_high_y:
	or.w	d0,(a5)                         ; the pixel, twice
	or.w	d0,$50(a5)
	adda.w	d7,a5
	sub.w	d3,d5
	bmi.s	draw_line_high_steep_next
draw_line_high_y_next:
	dbra	d4,draw_line_high_y
	rts

;------------------------------------------------------------------------------
; sample_toggle_end (up, down): the moving end (start or end) changed over.
;------------------------------------------------------------------------------
sample_toggle_end:	; from: sample_ripper
	move.b	sample_marker_text+2,sample_unmarker_text+2 ; the marker off
	lea	sample_unmarker_text,a0
	bsr.w	print
	moveq	#0,d0
	moveq	#0,d1
	move.b	sample_marker_index,d0          ; which
	lea	sample_markers,a0               ; the marker's columns
	addq.w	#1,d0                           ; the next
	move.b	0(a0,d0.w),d1
	bge.s	sample_toggle_end_set           ; the end?
	clr.w	d0                              ; yes: the first
	move.b	0(a0,d0.w),d1
sample_toggle_end_set:
	move.b	d0,sample_marker_index
	move.b	d1,sample_marker_text+2         ; its column
	bsr.w	show_sample_marker              ; the marker
	bra.w	sample_ripper_key
	bra.w	sample_ripper_key               ; (not reached)

;------------------------------------------------------------------------------
; sample_end_right etc.: the start or the end moved by 1 (left/right) or 256 (Shift), within the other end.
;------------------------------------------------------------------------------
sample_end_right:	; from: sample_ripper
	moveq	#1,d7                           ; +1
sample_end_move:
	cmpi.b	#$23,sample_marker_text+2       ; the start marked?
	beq.s	sample_move_start               ; yes
	bra.s	sample_move_end                 ; the end
sample_end_left:	; from: sample_ripper
	moveq	#-1,d7                          ; -1
	bra.s	sample_end_move
sample_end_shift_left:	; from: sample_ripper
	move.w	#$ff00,d7                       ; -256
	ext.l	d7
	bra.s	sample_end_move
sample_end_shift_right:	; from: sample_ripper
	move.w	#$100,d7                        ; +256
	ext.l	d7
	bra.s	sample_end_move
sample_move_start:
	move.l	range_start,d6                  ; the start
	add.l	d7,d6                           ; moved
	cmp.l	sample_end,d6                   ; past the end?
	bge.w	sample_ripper_key               ; yes: no
	tst.l	d6                              ; negative?
	bmi.w	sample_ripper_key               ; yes: no
	move.l	d6,range_start                  ; set
	move.l	d6,sample_start                 ; and kept
	bsr.w	show_sample_start               ; shown
	bra.w	sample_ripper_redraw            ; the wave again
sample_move_end:
	move.l	sample_end,d6                   ; the end
	add.l	d7,d6                           ; moved
	cmp.l	range_start,d6                  ; before the start?
	ble.w	sample_ripper_key               ; yes: no
	move.l	d6,sample_end                   ; set
	bsr.w	show_sample_end                 ; shown
	bra.w	sample_ripper_redraw            ; the wave again

;------------------------------------------------------------------------------
; show_sample_start: "START ADDRESS: $" and the start.
;------------------------------------------------------------------------------
show_sample_start:	; from: sample_toggle_controls, sample_end_right, show_sample_details, sample_set_start
	lea	position_3_24,a0                ; its place
	bsr.w	print
	movea.l	range_start,a6                  ; the start
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; show_sample_end: "END ADDRESS : $" and the end.
;------------------------------------------------------------------------------
show_sample_end:	; from: sample_toggle_controls, sample_end_right, show_sample_details, sample_set_end
	lea	position_4_24,a0                ; its place
	bsr.w	print
	movea.l	sample_end,a6                   ; the end
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; show_frequency: the replay frequency's name (2.5 to 25 KHz).
;------------------------------------------------------------------------------
show_frequency:	; from: sample_toggle_controls, show_sample_details, sample_frequency
	lea	position_3_54,a0                ; its place
	bsr.w	print
	moveq	#0,d0
	move.b	ym_frequency_index,d0           ; the frequency
	lea	ym_frequencies,a0
	move.b	0(a0,d0.w),d0
	mulu.w	#$9,d0                          ; 9 bytes a name
	lea	text_khz,a0
	lea	0(a0,d0.w),a0
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; show_ste_frequency: the STE DMA sound's frequency name (6.25 to 50 KHz).
;------------------------------------------------------------------------------
show_ste_frequency:	; from: sample_toggle_controls, sample_frequency
	lea	position_3_54,a0                ; its place
	bsr.w	print
	moveq	#0,d0
	move.w	ste_frequency,d0                ; the frequency
	mulu.w	#$9,d0                          ; 9 bytes a name
	lea	text_khz_at_d7a2,a0
	lea	0(a0,d0.w),a0
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; show_sample_marker: the marker for the end being moved.
;------------------------------------------------------------------------------
show_sample_marker:	; from: sample_toggle_controls, sample_toggle_end, show_sample_details
	lea	sample_marker_text,a0
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; show_sample_details: the start, the end, the frequency and the marker shown.
;------------------------------------------------------------------------------
show_sample_details:	; from: sample_ripper
	move.l	sample_start,range_start        ; the start
	bsr.w	show_sample_start
	bsr.w	show_sample_end
	bsr.w	show_frequency
	bsr.w	show_sample_marker
	rts

;------------------------------------------------------------------------------
; sample_set_start (F1): "START ADDRESS : $", before the end.
;------------------------------------------------------------------------------
sample_set_start:	; from: sample_ripper
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	sample_ripper_key               ; no
	cmp.l	sample_end,d2                   ; before the end?
	bge.w	sample_ripper_key               ; no
	tst.l	d2                              ; negative?
	bmi.w	sample_ripper_key               ; yes
	move.l	d2,range_start                  ; set
	move.l	d2,sample_start                 ; and kept
	bsr.w	show_sample_start               ; shown
	bra.w	sample_ripper_redraw            ; the wave again

;------------------------------------------------------------------------------
; sample_set_end (F2): "END ADDRESS : $", after the start and within 4 Mb.
;------------------------------------------------------------------------------
sample_set_end:	; from: sample_ripper
	lea	text_end_address,a0             ; "END ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	sample_ripper_key               ; no
	cmp.l	range_start,d2                  ; after the start?
	ble.w	sample_ripper_key               ; no
	cmp.l	#$400000,d2                     ; within 4 Mb?
	bgt.w	sample_ripper_key               ; no
	move.l	d2,sample_end                   ; set
	bsr.w	show_sample_end                 ; shown
	bra.w	sample_ripper_redraw            ; the wave again

;------------------------------------------------------------------------------
; sample_save (F5): "SAVE (B)INARY / (E)XECUTABLE ?": binary (a range to a file) or executable (the sample with
; a player as a program).
;------------------------------------------------------------------------------
sample_save:	; from: sample_ripper
	lea	text_save_b_inary,a0            ; the question
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$62,d0                         ; 'b'?
	beq.s	sample_save_binary
	cmp.b	#$42,d0                         ; 'B'?
	beq.s	sample_save_binary
	cmp.b	#$65,d0                         ; 'e'?
	beq.s	sample_save_program
	cmp.b	#$45,d0                         ; 'E'?
	beq.s	sample_save_program
	bra.w	sample_ripper_key               ; no
sample_save_binary:
	bsr.w	save_binary                     ; saved as binary
	bra.w	sample_ripper_key
sample_save_program:
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	sample_ripper_key               ; no
	move.l	d2,range_start                  ; the start
	lea	text_end_address,a0             ; "END ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	sample_ripper_key               ; no
	move.l	d2,range_end                    ; the end
	sub.l	range_start,d2                  ; the length
	ble.w	sample_ripper_key               ; none
	lea	text_enter_filename,a0          ; "ENTER FILENAME : "
	bsr.w	print
	move.w	#$3d00,input_buffer             ; 61 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	sample_ripper_key               ; no
	bsr.w	build_sample_program            ; the player built in the buffer
	move.l	a0,d3                           ; its end
	subi.l	#disk_buffer,d3                 ; its length
	lea	input_buffer+2,a0               ; the name
	lea	disk_buffer,a1                  ; the buffer
	bsr.w	create_file                     ; written
	tst.l	d0                              ; an error?
	bmi.w	sample_ripper_key               ; yes
	movea.l	range_start,a1                  ; the sample
	move.l	range_end,d3
	sub.l	a1,d3                           ; its length
	bsr.w	append_file                     ; added to the file
	bra.w	sample_ripper_key

;------------------------------------------------------------------------------
; build_sample_program: a program header ($601A) in the buffer, then the sound chip player (YM replay) or
; the STE DMA player copied after it with the settings poked in; its text length covers the sample too.
;------------------------------------------------------------------------------
build_sample_program:	; from: sample_save
	lea	disk_buffer,a0                  ; the buffer
	move.w	#$601a,(a0)+                    ; bra.s: a program
	moveq	#25,d0                          ; the rest of the header
build_sample_program_clear:
	clr.b	(a0)+                           ; cleared
	dbra	d0,build_sample_program_clear
	tst.w	ym_replay                       ; the YM?
	beq.w	build_sample_program_ste        ; no: STE
	lea	ym_program,a1                   ; the YM player
	lea	ste_program,a2                  ; its end
	moveq	#0,d7                           ; its length
build_sample_program_ym:
	move.b	(a1)+,(a0)+                     ; copied
	addq.w	#1,d7
	cmpa.l	a1,a2
	bne.s	build_sample_program_ym
	add.l	range_end,d7                    ; + the sample's end
	sub.l	range_start,d7                  ; less its start
	btst	#$0,d7                          ; odd?
	beq.s	build_sample_program_ym_length  ; no
	addq.l	#1,d7                           ; made even
build_sample_program_ym_length:
	move.l	d7,disk_buffer+2                ; the text length
	moveq	#0,d0
	move.b	ym_frequency_index,d0           ; the frequency
	add.w	d0,d0
	add.w	d0,d0
	lea	ym_timer_settings,a1            ; the timer settings
	movem.w	0(a1,d0.w),d0-d1                ; data and control
	lea	disk_buffer,a2
	move.w	d0,$7e(a2)                      ; into the player
	move.w	d1,$82(a2)
	move.w	#$80,$13e(a2)                   ; signed
	tst.w	sample_unsigned                 ; unsigned?
	beq.s	build_sample_program_ym_done    ; no
	clr.w	$13e(a2)
build_sample_program_ym_done:
	rts
build_sample_program_ste:
	lea	ste_program,a1                  ; the STE player
	lea	music_save,a2                   ; its end
	moveq	#0,d7
build_sample_program_ste_copy:
	move.b	(a1)+,(a0)+                     ; copied
	addq.w	#1,d7
	cmpa.l	a1,a2
	bne.s	build_sample_program_ste_copy
	add.l	range_end,d7                    ; + the sample's end
	sub.l	range_start,d7                  ; less its start
	btst	#$0,d7                          ; odd?
	beq.s	build_sample_program_ste_length ; no
	addq.l	#1,d7                           ; made even
build_sample_program_ste_length:
	move.l	d7,disk_buffer+2                ; the text length
	lea	disk_buffer,a2
	move.w	ste_volume,$62(a2)              ; the volume
	move.w	ste_left,$6e(a2)                ; the left
	move.w	ste_right,$7a(a2)               ; the right
	move.w	ste_treble,$86(a2)              ; the treble
	move.w	ste_bass,$92(a2)                ; the bass
	move.w	ste_stereo,$a6(a2)              ; stereo
	move.w	ste_frequency,$b0(a2)           ; the frequency
	move.l	range_end,d0                    ; the sample's length
	sub.l	range_start,d0
	move.l	d0,$13a(a2)
	rts

;------------------------------------------------------------------------------
; sample_frequency (F3): the next replay frequency (the YM's timer table, or the STE's four).
;------------------------------------------------------------------------------
sample_frequency:	; from: sample_ripper
	tst.w	ym_replay                       ; the YM?
	beq.w	sample_frequency_ste            ; no
	moveq	#0,d0
	move.b	ym_frequency_index,d0           ; the frequency
	addq.w	#1,d0                           ; the next
	lea	ym_frequencies,a0               ; the YM's frequencies
	move.b	0(a0,d0.w),d1
	bge.s	sample_frequency_set            ; the end?
	clr.w	d0                              ; yes: the first
	move.b	0(a0,d0.w),d1
sample_frequency_set:
	move.b	d0,ym_frequency_index
	bsr.w	show_frequency                  ; shown
	bra.w	sample_ripper_key
sample_frequency_ste:
	move.w	ste_frequency,d0
	addq.w	#1,d0                           ; the next
	cmp.w	#$4,d0                          ; 4?
	bne.s	sample_frequency_ste_set        ; no
	clr.w	d0                              ; 0
sample_frequency_ste_set:
	move.w	d0,ste_frequency
	bsr.w	show_ste_frequency              ; shown
	bra.w	sample_ripper_key

;------------------------------------------------------------------------------
; sample_play (F4): the sample played from the start to the end: through the sound chip with timer A, or by
; the STE's DMA sound with the LMC1992 set; the playing position shown until ESC or the end.
;------------------------------------------------------------------------------
sample_play:	; from: sample_ripper
	tst.w	ym_replay                       ; the YM?
	beq.w	sample_play_ste                 ; no: STE
	bsr.w	sound_save                      ; the sound chip and MFP kept
	bsr.w	flush_keyboard                  ; the keyboard emptied
	moveq	#0,d0
	move.b	ym_frequency_index,d0           ; the frequency
	add.w	d0,d0
	add.w	d0,d0
	lea	ym_timer_settings,a1            ; the timer settings
	movem.w	0(a1,d0.w),d0-d1
	movea.l	range_start,a0                  ; the start
	movea.l	sample_end,a1                   ; the end
	move.w	#$1,sample_playing              ; playing
	move.l	#$8080000,$ffff8800.w           ; PSG register select, the volumes 0
	move.l	#$9090000,$ffff8800.w           ; PSG register select
	move.l	#$a0a0000,$ffff8800.w           ; PSG register select
	move.w	#$2500,sr                       ; interrupts on (level 5)
	bsr.w	start_timer_a_player            ; timer A started
	lea	text_playing_position,a0        ; "PLAYING POSITION : $"
	bsr.w	print
sample_play_ym_wait:
	cmpi.b	#$1,$fffffc02.w                 ; keyboard ACIA data, ESC pressed?
	beq.s	sample_play_ym_stop             ; yes
	lea	position_24_42,a0               ; the position's place
	bsr.w	print
	movea.l	sample_position,a6              ; the position
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text+2,a0
	bsr.w	print
	tst.w	sample_playing                  ; still playing?
	bne.s	sample_play_ym_wait             ; yes
sample_play_ym_stop:
	move.w	#$2700,sr                       ; interrupts off
	clr.b	$fffffa07.w                     ; MFP IERA
	clr.b	$fffffa19.w                     ; MFP TACR, timer A stopped
	bsr.w	sound_restore                   ; the MFP back
	move.w	#$2300,sr
	bsr.w	flush_keyboard                  ; the keyboard emptied
	moveq	#3,d0
	bsr.w	send_ikbd                       ; to the keyboard
	move.b	#$96,$fffffc00.w                ; keyboard ACIA control, the ACIA's interrupt on
	lea	position_24_42,a0               ; the position
	bsr.w	print
	movea.l	sample_position,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text+2,a0
	bsr.w	print
	bra.w	sample_ripper_wait
sample_play_ste:
	move.w	ste_volume,d0                   ; the volume
	ori.w	#$4c0,d0                        ; LMC1992 master volume
	bsr.w	microwire_write
	move.w	ste_left,d0                     ; the left
	ori.w	#$540,d0                        ; left volume
	bsr.w	microwire_write
	move.w	ste_right,d0                    ; the right
	ori.w	#$500,d0                        ; right volume
	bsr.w	microwire_write
	move.w	ste_treble,d0                   ; the treble
	ori.w	#$480,d0                        ; treble
	bsr.w	microwire_write
	move.w	ste_bass,d0                     ; the bass
	ori.w	#$440,d0                        ; bass
	bsr.w	microwire_write
	move.w	#$401,d0                        ; mix: the DMA sound and the sound chip
	bsr.w	microwire_write
	move.w	ste_stereo,d0                   ; stereo
	not.w	d0
	andi.w	#$1,d0
	lsl.w	#7,d0                           ; mono bit
	move.w	ste_frequency,d1                ; the frequency
	or.b	d1,d0
	move.b	d0,$ffff8921.w                  ; the DMA mode
	clr.b	$ffff8901.w                     ; stopped
	lea	range_start,a0                  ; the start
	lea	sample_end,a1                   ; the end
	move.b	3(a0),$ffff8907.w               ; the frame start
	move.b	2(a0),$ffff8905.w
	move.b	1(a0),$ffff8903.w
	move.b	3(a1),$ffff8913.w               ; the frame end
	move.b	2(a1),$ffff8911.w
	move.b	1(a1),$ffff890f.w
	move.b	#$1,$ffff8901.w                 ; played once
	lea	text_playing_position,a0        ; "PLAYING POSITION : $"
	bsr.w	print
sample_play_ste_wait:
	cmpi.b	#$1,$fffffc02.w                 ; keyboard ACIA data, ESC pressed?
	beq.s	sample_play_ste_escape          ; yes
	lea	position_24_42,a0               ; the position's place
	bsr.w	print
	moveq	#0,d0
	move.b	$ffff8909.w,d0                  ; the frame counter
	lsl.w	#8,d0
	move.b	$ffff890b.w,d0
	lsl.l	#8,d0
	move.b	$ffff890d.w,d0
	movea.l	d0,a6
	move.l	d0,-(sp)                        ; kept
	cmp.l	d1,d0                           ; the same as last time (the end)?
	beq.s	sample_play_ste_end             ; yes
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text+2,a0
	bsr.w	print
	move.l	(sp)+,d1
	bra.w	sample_play_ste_wait
sample_play_ste_end:
	lea	4(sp),sp
	bra.s	sample_play_ste_stop
sample_play_ste_escape:
	bsr.w	wait_key                        ; the key
sample_play_ste_stop:
	clr.b	$ffff8901.w                     ; stopped
	moveq	#40,d0                          ; the volume back to 40
	ori.w	#$4c0,d0
	bsr.w	microwire_write
	moveq	#20,d0                          ; the left 20
	ori.w	#$540,d0
	bsr.w	microwire_write
	moveq	#20,d0                          ; the right 20
	ori.w	#$500,d0
	bsr.w	microwire_write
	moveq	#6,d0                           ; the treble 6
	ori.w	#$480,d0
	bsr.w	microwire_write
	moveq	#6,d0                           ; the bass 6
	ori.w	#$440,d0
	bsr.w	microwire_write
	bra.w	sample_ripper_wait

;------------------------------------------------------------------------------
; microwire_write: d0 sent to the LMC1992 through the Microwire.
;------------------------------------------------------------------------------
microwire_write:	; from: sample_play
	move.w	#$28,d1                         ; a wait
microwire_write_delay:
	dbra	d1,microwire_write_delay
	move.w	#$7ff,$ffff8924.w               ; the mask
microwire_write_wait:
	cmpi.w	#$7ff,$ffff8924.w               ; ready?
	bne.s	microwire_write_wait            ; no
	move.w	d0,$ffff8922.w                  ; the data
	rts

;------------------------------------------------------------------------------
; flush_keyboard: the keyboard ACIA emptied.
;------------------------------------------------------------------------------
flush_keyboard:	; from: sample_play
	btst	#$0,$fffffc00.w                 ; keyboard ACIA control, a byte?
	beq.s	flush_keyboard_done             ; no
	move.b	$fffffc02.w,d0                  ; keyboard ACIA data, dropped
	bra.s	flush_keyboard
flush_keyboard_done:
	rts

;------------------------------------------------------------------------------
; send_ikbd: d0 sent to the keyboard.
;------------------------------------------------------------------------------
send_ikbd:	; from: sample_play
	movem.l	d1/a0,-(sp)
	lea	$fffffc00.w,a0                  ; keyboard ACIA control, the ACIA
send_ikbd_wait:
	move.b	(a0),d1
	btst	#$1,d1                          ; ready to send?
	beq.s	send_ikbd_wait                  ; no
	move.b	d0,(a0)                         ; sent
	movem.l	(sp)+,d1/a0
	rts

;------------------------------------------------------------------------------
; start_timer_a_player: the MFP's interrupts off, timer A at the sound chip player (ym_sample_player) with
; the sample from a0 to a1, the data d0 and the control d1.
;------------------------------------------------------------------------------
start_timer_a_player:	; from: sample_play
	move.w	sr,-(sp)
	move.w	#$2700,sr                       ; interrupts off
	clr.b	$fffffa07.w                     ; MFP IERA, the MFP's
	clr.b	$fffffa13.w                     ; MFP IMRA
	clr.b	$fffffa09.w                     ; MFP IERB
	clr.b	$fffffa15.w                     ; MFP IMRB
	lea	ym_sample_player,a2             ; the player
	move.l	a2,$134.w                       ; MFP timer A, timer A
	move.l	a0,sample_position              ; the position
	subq.l	#1,a1                           ; the end
	move.l	a1,sample_last
	movea.l	sample_position,a4
	lea	$ffff8800.w,a5                  ; PSG register select, the sound chip
	lea	sample_volumes,a3               ; the sample to volume table
	movea.l	sample_last,a6
	move.w	#$80,d4                         ; the sign
	move.b	d0,$fffffa1f.w                  ; MFP TADR, the timer's data
	move.b	d1,$fffffa19.w                  ; MFP TACR, and control
	bset	#$5,$fffffa13.w                 ; MFP IMRA, unmasked
	bset	#$5,$fffffa07.w                 ; MFP IERA, enabled
	move.w	(sp)+,sr
	rts

;------------------------------------------------------------------------------
; sound_save: the sound chip and the MFP kept, key click off.
;------------------------------------------------------------------------------
sound_save:	; from: sample_play
	bsr.w	keep_sound_state                ; kept
	clr.w	$484.w                          ; conterm, no click
	rts

;------------------------------------------------------------------------------
; sound_restore: timer A off and the MFP put back.
;------------------------------------------------------------------------------
sound_restore:	; from: sample_play
	bclr	#$5,$fffffa07.w                 ; MFP IERA
	bsr.w	restore_sound_state             ; put back
	rts

;------------------------------------------------------------------------------
; keep_sound_state: the volumes 0, the mixer's tone and noise off, timer A's vector and the MFP's registers
; kept.
;------------------------------------------------------------------------------
keep_sound_state:	; from: sound_save
	move.w	sr,-(sp)
	move.w	#$2700,sr                       ; interrupts off
	move.l	#$8080000,$ffff8800.w           ; PSG register select, the volumes 0
	move.l	#$9090000,$ffff8800.w           ; PSG register select
	move.l	#$a0a0000,$ffff8800.w           ; PSG register select
	move.b	#$7,$ffff8800.w                 ; PSG register select, the mixer
	move.b	$ffff8800.w,d0                  ; PSG register select
	andi.b	#$c0,d0                         ; the ports' bits kept
	ori.b	#$3b,d0                         ; tone and noise off
	move.b	d0,$ffff8802.w                  ; PSG write data
	move.l	$134.w,saved_timer_a            ; MFP timer A, timer A
	move.b	$fffffa07.w,saved_iera          ; MFP IERA, IERA
	move.b	$fffffa09.w,saved_ierb          ; MFP IERB, IERB
	move.b	$fffffa13.w,saved_imra          ; MFP IMRA, IMRA
	move.b	$fffffa15.w,saved_imrb          ; MFP IMRB, IMRB
	move.b	$fffffa19.w,saved_tacr          ; MFP TACR, TACR
	move.b	$fffffa1f.w,saved_tadr          ; MFP TADR, TADR
	move.w	(sp)+,sr
	rts

;------------------------------------------------------------------------------
; restore_sound_state: the volumes 0 and the MFP put back.
;------------------------------------------------------------------------------
restore_sound_state:	; from: sound_restore
	move.w	sr,-(sp)
	move.w	#$2700,sr                       ; interrupts off
	move.l	#$8080000,$ffff8800.w           ; PSG register select, the volumes 0
	move.l	#$9090000,$ffff8800.w           ; PSG register select
	move.l	#$a0a0000,$ffff8800.w           ; PSG register select
	clr.b	$fffffa19.w                     ; MFP TACR, timer A stopped
	move.l	saved_timer_a,$134.w            ; MFP timer A, its vector
	move.b	saved_imra,$fffffa13.w          ; MFP IMRA, IMRA
	move.b	saved_imrb,$fffffa15.w          ; MFP IMRB, IMRB
	move.b	saved_iera,$fffffa07.w          ; MFP IERA, IERA
	move.b	saved_ierb,$fffffa09.w          ; MFP IERB, IERB
	move.w	(sp)+,sr
	rts

;------------------------------------------------------------------------------
; ym_sample_player: timer A's interrupt while a sample plays: the next sample (with the sign added) to the
; three volume registers from sample_volumes; at the end playing stops.
;------------------------------------------------------------------------------
ym_sample_player:	; from: start_timer_a_player
	movem.l	d6/a3-a4,-(sp)                  ; saved
	lea	sample_volumes(pc),a3           ; the volumes
	movea.l	sample_position,a4              ; the position
	cmpa.l	sample_last,a4                  ; the end?
	bgt.s	ym_sample_player_end            ; yes
	move.w	sample_sign,d6                  ; the sign
	add.b	(a4)+,d6                        ; + the sample
	move.l	a4,sample_position              ; on
	lea	$ffff8800.w,a4                  ; PSG register select, the sound chip
	lsl.w	#3,d6                           ; 8 bytes a value
	adda.w	d6,a3
	move.l	(a3)+,d6                        ; registers 8 and 9
	movep.l	d6,0(a4)
	move.w	(a3),d6                         ; register 10
	movep.w	d6,0(a4)
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA, in service cleared
	movem.l	(sp)+,d6/a3-a4
	rte
ym_sample_player_end:
	clr.w	sample_playing                  ; not playing
	bclr	#$5,$fffa07                     ; MFP IERA, timer A off
	bclr	#$5,$fffa0f                     ; MFP ISRA, in service cleared
	movem.l	(sp)+,d6/a3-a4
	rte

;------------------------------------------------------------------------------
; ym_program: the start of the YM sample program saved by the sample ripper (its sample after it): shrunk,
; then timer A set (Xbtimer) to play the sample over and over, and resident (Ptermres).  The ripper pokes its
; timer settings and sign in.
;------------------------------------------------------------------------------
ym_program:	; from: build_sample_program
	movea.l	sp,a5
	movea.l	4(a5),a5                        ; the basepage
	move.l	$c(a5),d0                       ; text
	add.l	$14(a5),d0                      ; + data
	add.l	$1c(a5),d0                      ; + bss
	addi.l	#$300,d0                        ; + $300
	move.l	d0,-(sp)
	lea	ym_program_length(pc),a0        ; kept
	move.l	d0,(a0)
	pea	(a5)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	lea	ym_program_old_stack(pc),a0     ; the old stack kept
	move.l	d0,(a0)
	andi.b	#$fe,$484.w                     ; conterm, no key click
	bsr.w	ym_program_init_sound           ; the sound chip set
	lea	ym_program(pc),a0               ; the program's start
	move.l	a0,d0
	lea	ym_program_length(pc),a1        ; its length
	movea.l	(a1),a1
	adda.l	d0,a1                           ; its end
	suba.l	#$300,a1                        ; less $300: the sample's end
	lea	ste_program(pc),a0              ; the sample's start (after the code)
	move.b	#$5,d0                          ; timer data (poked)
	move.b	#$5,d1                          ; timer control (poked)
	bsr.w	ym_program_start_timer          ; started
	move.l	ym_program_old_stack(pc),-(sp)  ; the old stack
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	move.w	#$d,-(sp)                       ; (Jenabint(13) pushed but not called)
	move.w	#$1a,-(sp)
	addq.l	#4,sp
	clr.w	-(sp)                           ; kept 0
	move.l	ym_program_length(pc),-(sp)     ; the length to keep
	move.w	#$31,-(sp)
	trap	#1                              ; Ptermres

ym_program_start_timer:	; from: ym_program
	move.w	sr,-(sp)
	move.w	#$2500,sr                       ; interrupts at 5
	lea	ym_program_position(pc),a2      ; the position
	move.l	a0,(a2)
	lea	ym_program_loop(pc),a2          ; the loop's start
	move.l	a0,(a2)
	subq.w	#1,a1                           ; the end
	lea	ym_program_end(pc),a2
	move.l	a1,(a2)
	pea	ym_program_player(pc)           ; the handler
	move.w	d0,-(sp)                        ; data
	move.w	d1,-(sp)                        ; control
	clr.w	-(sp)                           ; timer A
	move.w	#$1f,-(sp)
	trap	#14                             ; Xbtimer
	lea	$c(sp),sp
	rte                                     ; (sr back from the stack)

ym_program_init_sound:	; from: ym_program
	move.w	sr,-(sp)
	move.w	#$2700,sr                       ; interrupts off
	bclr	#$5,$fffffa07.w                 ; MFP IERA, timer A's interrupt off
	move.b	#$5,$fffffa19.w                 ; MFP TACR
	move.b	#$5,$fffffa1f.w                 ; MFP TADR
	bset	#$5,$fffffa13.w                 ; MFP IMRA, unmasked
	move.l	#$8080000,$ffff8800.w           ; PSG register select, the volumes 0
	move.l	#$9090000,$ffff8800.w           ; PSG register select
	move.l	#$a0a0000,$ffff8800.w           ; PSG register select
	move.b	#$7,$ffff8800.w                 ; PSG register select, the mixer
	move.b	$ffff8800.w,d0                  ; PSG register select
	andi.b	#$c0,d0
	ori.b	#$3b,d0                         ; tone and noise off
	move.b	d0,$ffff8802.w                  ; PSG write data
	rte                                     ; (sr back from the stack)

;------------------------------------------------------------------------------
; ym_program_player: the program's timer A routine: the next sample to the volumes, back to the start at the end.
;------------------------------------------------------------------------------
ym_program_player:	; from: ym_program_start_timer
	movem.l	d6/a3-a4,-(sp)                  ; saved
	lea	ym_program_position(pc),a3      ; the position
	movea.l	(a3),a4
	cmpa.l	ym_program_end(pc),a4           ; the end?
	bne.s	ym_program_player_play          ; no
	movea.l	ym_program_loop(pc),a4          ; back to the start
ym_program_player_play:
	move.w	#$80,d6                         ; the sign (poked)
	add.b	(a4)+,d6                        ; + the sample
	move.l	a4,(a3)                         ; on
	lea	$ffff8800.w,a4                  ; PSG register select, the sound chip
	lea	sample_volumes(pc),a3           ; the volumes
	lsl.w	#3,d6                           ; 8 bytes a value
	adda.w	d6,a3
	move.l	(a3)+,d6                        ; registers 8 and 9
	movep.l	d6,0(a4)
	move.w	(a3),d6                         ; register 10
	movep.w	d6,0(a4)
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA, in service cleared
	movem.l	(sp)+,d6/a3-a4
	rte

;------------------------------------------------------------------------------
; sample_volumes: for each sample value, the three volume registers' values (8 bytes each).
;------------------------------------------------------------------------------
sample_volumes:	; from: start_timer_a_player, ym_sample_player, ym_program_player
	dc.w	$080c,$090b,$0a09,$0000,$080c,$090b,$0a09,$0000
	dc.w	$080d,$0908,$0a08,$0000,$080b,$090b,$0a0b,$0000
	dc.w	$080d,$0909,$0a05,$0000,$080c,$090b,$0a08,$0000
	dc.w	$080d,$0909,$0a02,$0000,$080d,$0908,$0a06,$0000
	dc.w	$080c,$090b,$0a07,$0000,$080d,$0907,$0a07,$0000
	dc.w	$080c,$090b,$0a06,$0000,$080c
	dc.b	9,10,10,9,0
	dc.b	$00,$08,$0b,$09,$0b,$0a,$0a,$00,$00,$08,$0c,$09,$0b,$0a,$02,$00
	dc.b	$00,$08,$0c,$09,$0b,$0a,$00,$00,$00,$08,$0c,$09,$0a,$0a,$08,$00
	dc.b	$00,$08,$0d,$09,$06,$0a,$04,$00,$00,$08,$0d,$09,$05,$0a,$05,$00
	dc.b	$00,$08,$0d,$09,$05,$0a,$04,$00,$00,$08,$0c
	dc.b	9,9,10,9,0
	dc.b	$00,$08,$0d,$09,$04,$0a,$03,$00,$00,$08,$0b,$09,$0b,$0a,$09,$00
	dc.b	$00,$08,$0c,$09,$0a,$0a,$05,$00,$00,$08,$0b
	dc.b	9,10,10,10,0
	dc.b	$00,$08,$0c,$09,$09,$0a,$08,$00,$00,$08,$0b,$09,$0b,$0a,$08,$00
	dc.b	$00,$08,$0c
	dc.b	9,10,10,0
	dc.w	$0000,$080c
	dc.b	9,10,10,0
	dc.w	$0000,$080c,$0909,$0a07,$0000,$080b,$090b,$0a07
	dc.w	$0000,$080c,$0909,$0a06,$0000,$080b,$090b,$0a06
	dc.w	$0000,$080b
	dc.b	9,10,10,9,0
	dc.b	$00,$08,$0b,$09,$0b,$0a,$05,$00,$00,$08
	dc.b	10,9,10,10,10,0
	dc.b	$00,$08,$0b,$09,$0b,$0a,$02,$00,$00,$08,$0b,$09,$0a,$0a,$08,$00
	dc.b	$00,$08,$0c,$09,$07,$0a,$07,$00,$00,$08,$0c,$09,$08,$0a,$04,$00
	dc.b	$00,$08,$0c,$09,$07,$0a,$06,$00,$00,$08,$0b
	dc.b	9,9,10,9,0
	dc.b	$00,$08,$0c,$09,$06,$0a,$06,$00,$00,$08
	dc.b	10,9,10,10,9,0
	dc.b	$00,$08,$0c,$09,$07,$0a,$03,$00,$00,$08,$0b,$09,$0a,$0a,$05,$00
	dc.b	$00,$08,$0b,$09,$09,$0a,$08,$00,$00,$08,$0b,$09,$0a,$0a,$03,$00
	dc.b	$00,$08,$0a,$09,$0a,$0a,$08,$00,$00,$08,$0b
	dc.b	9,10,10,0
	dc.w	$0000,$080b,$0909,$0a07,$0000,$080b,$0908,$0a08
	dc.w	$0000,$080a,$090a,$0a07,$0000
	dc.b	$08
	dc.b	10,9,9,10,9,0
	dc.b	$00,$08,$0c,$09,$01,$0a,$01,$00,$00,$08,$0a,$09,$0a,$0a,$06,$00
	dc.b	$00,$08,$0b,$09,$08,$0a,$07,$00,$00,$08,$0a,$09,$0a,$0a,$05,$00
	dc.b	$00,$08,$0a,$09,$09,$0a,$08,$00,$00,$08,$0a,$09,$0a,$0a,$02,$00
	dc.b	$00,$08,$0a,$09,$0a,$0a,$01,$00,$00,$08
	dc.b	10,9,10,10,0
	dc.w	$0000
	dc.b	$08
	dc.b	9,9,9,10,9,0
	dc.b	$00,$08,$0a,$09,$08,$0a,$08,$00,$00,$08,$0b,$09,$08,$0a,$01,$00
	dc.b	$00,$08,$0a,$09,$09,$0a,$06,$00,$00,$08,$0b,$09,$07,$0a,$04,$00
	dc.b	$00,$08,$0a,$09,$09,$0a,$05,$00,$00,$08,$09,$09,$09,$0a,$08,$00
	dc.b	$00,$08,$0a,$09,$09,$0a,$03,$00,$00,$08,$0a,$09,$08,$0a,$06,$00
	dc.b	$00,$08
	dc.b	10,9,9,10,0
	dc.w	$0000,$0809,$0909,$0a07,$0000,$0809,$0908,$0a08
	dc.w	$0000,$080a,$0908,$0a04,$0000,$0809,$0909,$0a06
	dc.w	$0000,$080a,$0908,$0a01,$0000,$0809,$0909,$0a05
	dc.w	$0000,$0809,$0908,$0a07,$0000,$0808,$0908,$0a08
	dc.w	$0000,$0809,$0909,$0a02,$0000,$0809,$0908,$0a06
	dc.w	$0000
	dc.b	$08
	dc.b	9,9,9,10,0
	dc.w	$0000,$0809,$0907,$0a07,$0000,$0808,$0908,$0a07
	dc.w	$0000,$0809,$0907,$0a06,$0000,$0809,$0908,$0a02
	dc.w	$0000,$0808,$0908,$0a06,$0000,$0809,$0906,$0a06
	dc.w	$0000,$0808,$0907,$0a07,$0000,$0808,$0908,$0a04
	dc.w	$0000,$0808,$0907,$0a06,$0000,$0808,$0908,$0a02
	dc.w	$0000,$0807,$0907,$0a07,$0000,$0808,$0906,$0a06
	dc.w	$0000,$0808,$0907,$0a04,$0000,$0807,$0907,$0a06
	dc.w	$0000,$0808,$0906,$0a05,$0000,$0808,$0906,$0a04
	dc.w	$0000,$0807,$0906,$0a06,$0000,$0807,$0907,$0a04
	dc.w	$0000,$0808,$0905,$0a04,$0000,$0806,$0906,$0a06
	dc.w	$0000,$0807,$0906,$0a04,$0000,$0807,$0905,$0a05
	dc.w	$0000,$0806,$0906,$0a05,$0000,$0806,$0906,$0a04
	dc.w	$0000,$0806,$0905,$0a05,$0000,$0806,$0906,$0a02
	dc.w	$0000,$0806,$0905,$0a04,$0000,$0805,$0905,$0a05
	dc.w	$0000,$0806,$0905,$0a02,$0000,$0805,$0905,$0a04
	dc.w	$0000,$0805,$0904,$0a04,$0000,$0805,$0905,$0a02
	dc.w	$0000,$0804,$0904,$0a04,$0000,$0804,$0904,$0a03
	dc.w	$0000,$0804,$0904,$0a02,$0000,$0804,$0903,$0a03
	dc.w	$0000,$0803,$0903,$0a03,$0000,$0803,$0903,$0a02
	dc.w	$0000,$0803,$0902,$0a02,$0000,$0802,$0902,$0a02
	dc.w	$0000,$0802,$0902,$0a01,$0000,$0801,$0901,$0a01
	dc.w	$0000,$0802,$0901,$0a00,$0000,$0801,$0901,$0a00
	dc.w	$0000,$0801,$0900,$0a00,$0000,$0800,$0900,$0a00
	dc.w	$0000,$080e,$090d,$0a0c,$0000,$080f,$0903,$0a00
	dc.w	$0000,$080f,$0903,$0a00,$0000,$080f,$0903,$0a00
	dc.w	$0000,$080f,$0903,$0a00,$0000,$080f,$0903,$0a00
	dc.w	$0000,$080f,$0903,$0a00,$0000,$080e,$090d,$0a0b
	dc.w	$0000,$080e,$090d,$0a0b,$0000,$080e,$090d,$0a0b
	dc.w	$0000,$080e,$090d,$0a0b,$0000,$080e,$090d,$0a0b
	dc.w	$0000,$080e,$090d,$0a0b,$0000,$080e,$090d,$0a0b
	dc.w	$0000,$080e
	dc.b	9,13,10,10,0
	dc.b	$00,$08,$0e
	dc.b	9,13,10,10,0
	dc.b	$00,$08,$0e
	dc.b	9,13,10,10,0
	dc.b	$00,$08,$0e
	dc.b	9,13,10,10,0
	dc.b	$00,$08,$0e,$09,$0c,$0a,$0c,$00,$00,$08,$0e
	dc.b	9,13,10,0
	dc.w	$0000
	dc.b	$08
	dc.b	13,9,13,10,13,0
	dc.b	$00,$08
	dc.b	13,9,13,10,13,0
	dc.b	$00,$08
	dc.b	13,9,13,10,13,0
	dc.b	$00,$08
	dc.b	13,9,13,10,13,0
	dc.b	$00,$08
	dc.b	13,9,13,10,13,0
	dc.b	$00,$08
	dc.b	13,9,13,10,13,0
	dc.b	$00,$08,$0e,$09,$0c,$0a,$0b,$00,$00,$08,$0e,$09,$0c,$0a,$0b,$00
	dc.b	$00,$08,$0e,$09,$0c,$0a,$0b,$00,$00,$08,$0e,$09,$0c,$0a,$0b,$00
	dc.b	$00,$08,$0e,$09,$0c,$0a,$0b,$00,$00,$08,$0e,$09,$0c,$0a,$0b,$00
	dc.b	$00,$08,$0e,$09,$0c,$0a,$0b,$00,$00,$08,$0e,$09,$0c,$0a,$0b,$00
	dc.b	$00,$08,$0e,$09,$0c,$0a,$0a,$00,$00,$08,$0e,$09,$0c,$0a,$0a,$00
	dc.b	$00,$08,$0e,$09,$0c,$0a,$0a,$00,$00,$08,$0e,$09,$0c,$0a,$0a,$00
	dc.b	$00,$08,$0d,$09,$0d,$0a,$0c,$00,$00,$08,$0d,$09,$0d,$0a,$0c,$00
	dc.b	$00,$08,$0e,$09,$0c,$0a,$09,$00,$00,$08,$0e,$09,$0c,$0a,$09,$00
	dc.b	$00,$08,$0e,$09,$0c,$0a,$05,$00,$00,$08,$0e,$09,$0c,$0a,$00,$00
	dc.b	$00,$08,$0e,$09,$0c,$0a,$00,$00,$00,$08,$0e,$09,$0b,$0a,$0b,$00
	dc.b	$00,$08,$0e,$09,$0b,$0a,$0b,$00,$00,$08,$0e,$09,$0b,$0a,$0b,$00
	dc.b	$00,$08,$0e,$09,$0b,$0a,$0b,$00,$00,$08,$0e,$09,$0b,$0a,$0a,$00
	dc.b	$00,$08,$0e,$09,$0b,$0a,$0a,$00,$00,$08,$0e,$09,$0b,$0a,$0a,$00
	dc.b	$00,$08,$0d,$09,$0d,$0a,$0b,$00,$00,$08,$0d,$09,$0d,$0a,$0b,$00
	dc.b	$00,$08,$0d,$09,$0d,$0a,$0b,$00,$00,$08,$0e,$09,$0b,$0a,$09,$00
	dc.b	$00,$08,$0e,$09,$0b,$0a,$09,$00,$00,$08,$0e,$09,$0b,$0a,$09,$00
	dc.b	$00,$08,$0d,$09,$0c,$0a,$0c,$00,$00,$08
	dc.b	13,9,13,10,10,0
	dc.b	$00,$08,$0e,$09,$0b,$0a,$07,$00,$00,$08,$0e,$09,$0b,$0a,$00,$00
	dc.b	$00,$08,$0e,$09,$0b,$0a,$00,$00,$00,$08
	dc.b	13,9,13,10,9,0
	dc.b	$00,$08
	dc.b	13,9,13,10,9,0
	dc.b	$00,$08,$0e
	dc.b	9,10,10,9,0
	dc.b	$00,$08,$0d,$09,$0d,$0a,$08,$00,$00,$08,$0d,$09,$0d,$0a,$07,$00
	dc.b	$00,$08,$0d,$09,$0d,$0a,$04,$00,$00,$08
	dc.b	13,9,13,10,0
	dc.w	$0000,$080e,$090a,$0a04,$0000,$080e
	dc.b	9,9,10,9,0
	dc.b	$00,$08,$0e
	dc.b	9,9,10,9,0
	dc.b	$00,$08,$0d,$09,$0c,$0a,$0b,$00,$00,$08,$0e,$09,$09,$0a,$08,$00
	dc.b	$00,$08,$0e,$09,$09,$0a,$08,$00,$00,$08,$0e,$09,$09,$0a,$07,$00
	dc.b	$00,$08,$0e,$09,$08,$0a,$08,$00,$00,$08,$0e,$09,$09,$0a,$01,$00
	dc.b	$00,$08,$0c,$09,$0c,$0a,$0c,$00,$00,$08,$0d,$09,$0c,$0a,$0a,$00
	dc.b	$00,$08,$0e,$09,$08,$0a,$06,$00,$00,$08,$0e,$09,$07,$0a,$07,$00
	dc.b	$00,$08,$0e,$09,$08,$0a,$00,$00,$00,$08,$0e,$09,$07,$0a,$05,$00
	dc.b	$00,$08,$0e,$09,$06,$0a,$06,$00,$00,$08,$0d,$09,$0c,$0a,$09,$00
	dc.b	$00,$08,$0e,$09,$05,$0a,$05,$00,$00,$08,$0e,$09,$04,$0a,$04,$00
	dc.b	$00,$08,$0d,$09,$0c,$0a,$08,$00,$00,$08,$0d,$09,$0b,$0a,$0b,$00
	dc.b	$00,$08,$0e,$09,$00,$0a,$00,$00,$00,$08,$0d,$09,$0c,$0a,$06,$00
	dc.b	$00,$08,$0d,$09,$0c,$0a,$05,$00,$00,$08,$0d,$09,$0c,$0a,$02,$00
	dc.b	$00,$08,$0c,$09,$0c,$0a,$0b,$00,$00,$08,$0c,$09,$0c,$0a,$0b,$00
	dc.b	$00,$08,$0d,$09,$0b,$0a,$0a,$00,$00,$08,$0d,$09,$0b,$0a,$0a,$00
	dc.b	$00,$08,$0d,$09,$0b,$0a,$0a,$00,$00,$08,$0d,$09,$0b,$0a,$0a,$00
	dc.b	$00,$08,$0c,$09,$0c,$0a,$0a,$00,$00,$08,$0c,$09,$0c,$0a,$0a,$00
	dc.b	$00,$08,$0c,$09,$0c,$0a,$0a,$00,$00,$08,$0d,$09,$0b,$0a,$09,$00
	dc.b	$00,$08,$0d,$09,$0b,$0a,$09,$00,$00,$08
	dc.b	13,9,10,10,10,0
	dc.b	$00,$08
	dc.b	13,9,10,10,10,0
	dc.b	$00,$08
	dc.b	13,9,10,10,10,0
	dc.b	$00,$08,$0c,$09,$0c,$0a,$09,$00,$00,$08,$0c,$09,$0c,$0a,$09,$00
	dc.b	$00,$08,$0c,$09,$0c,$0a,$09,$00,$00,$08,$0d,$09,$0b,$0a,$06,$00
	dc.b	$00,$08,$0c,$09,$0b,$0a,$0b,$00,$00,$08,$0c,$09,$0c,$0a,$08,$00
	dc.b	$00,$08,$0d,$09,$0b,$0a,$00,$00,$00,$08,$0d,$09,$0b,$0a,$00,$00
	dc.b	$00,$08,$0c,$09,$0c,$0a,$07,$00,$00,$08,$0c,$09,$0c,$0a,$06,$00
	dc.b	$00,$08,$0c,$09,$0c,$0a,$05,$00,$00,$08,$0c,$09,$0c,$0a,$03,$00
	dc.b	$00,$08,$0c,$09,$0c,$0a,$01,$00,$00,$08,$0c,$09,$0b,$0a,$0a,$00
	dc.b	$00,$08,$0d,$09,$0a,$0a,$05,$00,$00,$08,$0d,$09,$0a,$0a,$04,$00
	dc.b	$00,$08,$0d,$09,$0a,$0a,$02,$00,$00,$08,$0d,$09,$09,$0a,$08,$00
	dc.b	$00,$08,$0d,$09,$09,$0a,$08,$00,$00
ym_program_loop:	; from: ym_program_start_timer, ym_program_player
	dc.w	$0000,$0000
ym_program_position:	; from: ym_program_start_timer, ym_program_player
	dc.w	$0000,$0000
ym_program_end:	; from: ym_program_start_timer, ym_program_player
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000
ym_program_old_stack:	; from: ym_program
	dc.w	$0000,$0000
ym_program_length:	; from: ym_program
	dc.w	$0000,$0000

;------------------------------------------------------------------------------
; ste_program: the STE sample program saved by the sample ripper: shrunk, the LMC1992 set (the ripper pokes
; the volumes, tones, stereo and frequency into the immediates), the DMA sound looping the sample after it, then
; resident.
;------------------------------------------------------------------------------
ste_program:	; from: build_sample_program, ym_program
	movea.l	sp,a5
	movea.l	4(a5),a5                        ; the basepage
	move.l	$c(a5),d0                       ; text
	add.l	$14(a5),d0                      ; + data
	add.l	$1c(a5),d0                      ; + bss
	addi.l	#$300,d0                        ; + $300
	move.l	d0,-(sp)
	lea	ste_program_length(pc),a0       ; kept
	move.l	d0,(a0)
	pea	(a5)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	lea	ste_program_old_stack(pc),a0    ; the old stack kept
	move.l	d0,(a0)
	andi.b	#$fe,$484.w                     ; conterm, no key click
	move.w	#$0,d0                          ; the volume (poked)
	ori.w	#$4c0,d0                        ; master volume
	bsr.w	ste_program_microwire
	move.w	#$0,d0                          ; the left (poked)
	ori.w	#$540,d0                        ; left volume
	bsr.w	ste_program_microwire
	move.w	#$0,d0                          ; the right (poked)
	ori.w	#$500,d0                        ; right volume
	bsr.w	ste_program_microwire
	move.w	#$0,d0                          ; the treble (poked)
	ori.w	#$480,d0                        ; treble
	bsr.w	ste_program_microwire
	move.w	#$0,d0                          ; the bass (poked)
	ori.w	#$440,d0                        ; bass
	bsr.w	ste_program_microwire
	move.w	#$401,d0                        ; mix
	bsr.w	ste_program_microwire
	move.w	#$0,d0                          ; stereo (poked)
	eori.w	#$1,d0
	lsl.w	#7,d0                           ; mono bit
	move.w	#$0,d1                          ; the frequency (poked)
	or.b	d1,d0
	move.b	d0,$ffff8921.w                  ; the DMA mode
	lea	music_save(pc),a0               ; the sample: after the code
	lea	ste_program_start(pc),a1
	move.l	a0,(a1)                         ; its start
	lea	ste_program_sample_length(pc),a3 ; its length (poked)
	move.l	(a3),d0
	adda.l	d0,a0                           ; its end
	lea	ste_program_end(pc),a2
	move.l	a0,(a2)
	move.b	1(a1),$ffff8903.w               ; the frame start
	move.b	2(a1),$ffff8905.w
	move.b	3(a1),$ffff8907.w
	move.b	1(a2),$ffff890f.w               ; the frame end
	move.b	2(a2),$ffff8911.w
	move.b	3(a2),$ffff8913.w
	move.b	#$3,$ffff8901.w                 ; played, repeating
	move.l	ste_program_old_stack(pc),-(sp) ; the old stack
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	clr.w	-(sp)
	move.l	ste_program_length(pc),-(sp)    ; the length to keep
	move.w	#$31,-(sp)
	trap	#1                              ; Ptermres

;------------------------------------------------------------------------------
; ste_program_microwire: d0 to the LMC1992.
;------------------------------------------------------------------------------
ste_program_microwire:	; from: ste_program
	move.w	#$28,d1                         ; a wait
ste_program_microwire_delay:
	dbra	d1,ste_program_microwire_delay
	move.w	#$7ff,$ffff8924.w               ; the mask
ste_program_microwire_wait:
	cmpi.w	#$7ff,$ffff8924.w               ; ready?
	bne.s	ste_program_microwire_wait      ; no
	move.w	d0,$ffff8922.w                  ; the data
	rts
ste_program_start:	; from: ste_program
	dc.w	$0000,$0000
ste_program_end:	; from: ste_program
	dc.w	$0000,$0000,$0000,$0000
ste_program_sample_length:	; from: ste_program
	dc.w	$0000,$0000,$0000
ste_program_old_stack:	; from: ste_program
	dc.w	$0000,$0000
ste_program_length:	; from: ste_program
	dc.w	$0000,$0000

;------------------------------------------------------------------------------
; music_save (F2): the music found saved: "SAVE (B)INARY / (E)XECUTABLE ?" (binary with nothing found), or a
; range saved as a program with a player.
;------------------------------------------------------------------------------
music_save:	; from: music_ripper, build_sample_program, ste_program
	tst.w	music_kind                      ; found?
	beq.s	music_save_binary               ; no: binary
	lea	text_save_b_inary,a0            ; "SAVE (B)INARY / (E)XECUTABLE ?"
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$62,d0                         ; 'b'?
	beq.s	music_save_binary
	cmp.b	#$42,d0                         ; 'B'?
	beq.s	music_save_binary
	cmp.b	#$45,d0                         ; 'E'?
	beq.s	music_save_program
	cmp.b	#$65,d0                         ; 'e'?
	beq.s	music_save_program
	bra.w	music_ripper                    ; other: back
music_save_binary:
	bsr.w	save_binary                     ; saved as binary
	bra.w	music_ripper
music_save_program:
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	music_ripper                    ; no
	move.l	d2,range_start                  ; the start
	lea	text_end_address,a0             ; "END ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	music_ripper                    ; no
	move.l	d2,range_end                    ; the end
	sub.l	range_start,d2                  ; the length
	ble.w	music_ripper                    ; none
	lea	text_enter_filename,a0          ; "ENTER FILENAME : "
	bsr.w	print
	move.w	#$3d00,input_buffer             ; 61 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	music_ripper                    ; no
	bsr.w	build_music_program             ; the player built in the buffer
	move.l	a0,d3                           ; its end
	subi.l	#disk_buffer,d3                 ; its length
	lea	input_buffer+2,a0               ; the name
	lea	disk_buffer,a1                  ; the buffer
	bsr.w	create_file                     ; written
	tst.l	d0                              ; an error?
	bmi.w	music_ripper                    ; yes
	movea.l	range_start,a1                  ; the music
	move.l	range_end,d3
	sub.l	a1,d3                           ; its length
	bsr.w	append_file                     ; added
	bra.w	music_ripper

;------------------------------------------------------------------------------
; create_file: the file at a0 created and d3 bytes from a1 written; d1 = the handle; errors shown.
;------------------------------------------------------------------------------
create_file:	; from: sample_save, music_save
	bsr.w	force_media_change              ; the path set
	move.w	#$0,-(sp)                       ; normal file
	move.l	a0,-(sp)                        ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	cmp.l	#$ffffffff,d0                   ; -1?
	bne.s	create_file_handle              ; no
	move.l	#$fffffff3,d0                   ; as -13 (write protected)
create_file_handle:
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes: shown
	move.w	d0,d1                           ; the handle
	move.l	a1,-(sp)                        ; the data
	move.l	d3,-(sp)                        ; its length
	move.w	d1,-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	cmp.l	d0,d3                           ; all written?
	ble.s	create_file_done                ; yes
	move.l	#$ffffffbc,d0                   ; -68: disk full
	bra.w	show_error                      ; shown
create_file_done:
	rts

;------------------------------------------------------------------------------
; append_file: d3 bytes from a1 written to the file d1, then 6 zero bytes (an empty relocation table), closed.
;------------------------------------------------------------------------------
append_file:	; from: sample_save, music_save
	move.l	a1,-(sp)                        ; the data
	move.l	d3,-(sp)                        ; its length
	move.w	d1,-(sp)                        ; the handle
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	cmp.l	d0,d3                           ; all written?
	ble.s	append_file_close               ; yes
	move.l	#$ffffffbc,d0                   ; -68: disk full
	bra.w	show_error                      ; shown
append_file_close:
	pea	six_zeros                       ; 6 zero bytes
	move.l	#$6,-(sp)
	move.w	d1,-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	move.w	d1,-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	rts
six_zeros:
	dc.w	$0000,$0000,$0000

;------------------------------------------------------------------------------
; music_search (F1): "START ADDRESS : $" and "END ADDRESS : $", then "SEARCHING...": Soundtracker (M.K.),
; Quartet, TCB Tracker (AN COOL.), Chip music and Soundtrack routines looked for in turn; the first found is
; shown with its estimated start and end, or "SORRY, NO MUSIC FOUND !".
;------------------------------------------------------------------------------
music_search:	; from: music_ripper
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	music_ripper_key                ; no
	move.l	d2,range_start                  ; the start
	lea	text_end_address,a0             ; "END ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	music_ripper_key                ; no
	move.l	d2,range_end                    ; the end
	cmp.l	#$400000,d2                     ; within 4 Mb?
	bgt.w	music_ripper_key                ; no
	sub.l	range_start,d2
	ble.w	music_ripper_key                ; none
	lea	text_searching,a0               ; "SEARCHING..."
	bsr.w	print
	bsr.w	find_soundtracker               ; Soundtracker?
	tst.l	d0
	beq.w	found_soundtracker              ; found
	bsr.w	find_quartet                    ; Quartet?
	tst.l	d0
	beq.w	found_quartet                   ; found
	bsr.w	find_tcb_tracker                ; TCB Tracker?
	tst.l	d0
	beq.w	found_tcb_tracker               ; found
	bsr.w	find_chip_music                 ; chip music?
	tst.l	d0
	beq.w	show_estimate_play              ; found
	bsr.w	find_soundtrack                 ; soundtrack?
	tst.l	d0
	beq.w	show_estimate_play              ; found
	lea	text_sorry_no_music,a0          ; "SORRY, NO MUSIC FOUND !"
	bsr.w	print
	bra.w	music_ripper_key

;------------------------------------------------------------------------------
; find_tcb_tracker: "AN COOL." (TCB Tracker) looked for: d6 its start, d7 its end (from its pattern count and
; sample offsets), d5 $100.  d0 0 if found.
;------------------------------------------------------------------------------
find_tcb_tracker:	; from: music_search
	move.l	range_start,d0                  ; the start
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
	movea.l	range_end,a1                    ; the end
find_tcb_tracker_next:
	cmpi.l	#$414e2043,(a0)                 ; "AN C"?
	beq.s	find_tcb_tracker_check          ; yes
find_tcb_tracker_on:
	addq.l	#2,a0
	cmpa.l	a1,a0                           ; the end?
	ble.s	find_tcb_tracker_next           ; no
	bra.w	find_tcb_tracker_none           ; not found
find_tcb_tracker_check:
	cmpi.l	#$4f4f4c2e,4(a0)                ; "OOL."?
	bne.s	find_tcb_tracker_on             ; no
	movea.l	a0,a1                           ; the start
	addq.l	#8,a0
	move.l	(a0),d0                         ; the patterns
	cmp.l	#$80,d0                         ; fewer than 128?
	bge.s	find_tcb_tracker_on             ; no
	lea	$132(a1),a0                     ; the samples
	mulu.w	#$200,d0                        ; 512 bytes a pattern
	adda.l	d0,a0
	move.l	(a0),d0                         ; the samples' length
	adda.l	d0,a0                           ; the end
	move.l	a1,d6
	move.l	a0,d7
	move.l	#$100,d5
	moveq	#0,d0                           ; found
	rts
find_tcb_tracker_none:
	moveq	#-1,d0                          ; -1
	rts
found_tcb_tracker:	; from: music_search
	lea	text_tcb_tracker,a0             ; "'TCB TRACKER'"
	bsr.w	print
	bra.w	show_estimate                   ; shown

;------------------------------------------------------------------------------
; find_soundtracker: "M.K." (Soundtracker) looked for: d6 its start ($438 before), d7 its end (the patterns
; and 31 samples), d5 $100; one more than 250K long is passed over.  d0 0 if found.
;------------------------------------------------------------------------------
find_soundtracker:	; from: music_search
	move.l	range_start,d0                  ; the start
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
find_soundtracker_from:
	movea.l	range_end,a1                    ; the end
find_soundtracker_next:
	cmpi.l	#$4d2e4b2e,(a0)                 ; "M.K."?
	beq.s	find_soundtracker_found         ; yes
	addq.l	#2,a0
	cmpa.l	a1,a0                           ; the end?
	ble.s	find_soundtracker_next          ; no
	bra.w	find_soundtracker_none          ; not found
find_soundtracker_found:
	lea	-$438(a0),a0                    ; the module's start
	move.l	a0,d6
	move.w	#$43c,d2                        ; its header
	move.w	#$3b8,d3                        ; the song positions
	adda.w	d3,a0
	moveq	#0,d0
	moveq	#0,d1
	move.b	(a0)+,d0                        ; the first
	move.w	#$7e,d4                         ; 128
find_soundtracker_highest:
	move.b	(a0)+,d5
	cmp.b	d5,d0                           ; the highest pattern
	bge.s	find_soundtracker_next_position
	move.b	d5,d0
find_soundtracker_next_position:
	dbra	d4,find_soundtracker_highest
	addq.w	#1,d0                           ; the patterns
	mulu.w	#$400,d0                        ; 1K each
	movea.l	d6,a0
	adda.l	d0,a0
	adda.w	d2,a0                           ; + the header
	movea.l	d6,a1                           ; the samples
	lea	$14(a1),a1
	move.w	#$1e,d0                         ; 31
find_soundtracker_samples:
	moveq	#0,d1
	move.w	$16(a1),d1                      ; its length (words)
	lsl.l	#1,d1                           ; in bytes
	adda.l	d1,a0
	lea	$1e(a1),a1
	dbra	d0,find_soundtracker_samples
	cmpa.l	#$400000,a0                     ; past 4 Mb?
	ble.s	find_soundtracker_end           ; no
find_soundtracker_again:
	movea.l	d6,a0
	adda.l	#$43a,a0                        ; on past it
	bra.w	find_soundtracker_from
find_soundtracker_end:
	move.l	a0,d7                           ; the end
	move.l	d7,d1
	sub.l	d6,d1                           ; the length
	cmp.l	#$3d090,d1                      ; more than 250K?
	bgt.s	find_soundtracker_again         ; yes: on
	move.w	#$100,d5
	moveq	#0,d0                           ; found
	rts
find_soundtracker_none:
	moveq	#-1,d0                          ; -1
	rts
found_soundtracker:	; from: music_search
	lea	text_soundtrack_amiga,a0        ; "SOUNDTRACK AMIGA"
	bsr.w	print
show_estimate:	; from: find_tcb_tracker
	movem.l	d0-d7,-(sp)
	lea	text_estimated_start_address,a0 ; "ESTIMATED START ADDRESS:$"
	bsr.w	print
	movea.l	d6,a6                           ; the start
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,-(sp)
	lea	text_estimated_end_address,a0   ; "ESTIMATED END ADDRESS  :$"
	bsr.w	print
	movea.l	d7,a6                           ; the end
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,-(sp)
	lea	text_estimation,a0              ; "ESTIMATION             :    % "
	bsr.w	print
	movea.l	d5,a6                           ; the estimate
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text+5,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	bra.w	music_ripper_key
show_estimate_play:	; from: music_search
	movem.l	d0-d7,-(sp)
	lea	text_estimated_start_address,a0 ; "ESTIMATED START ADDRESS:$"
	bsr.w	print
	movea.l	d6,a6                           ; the start
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,-(sp)
	lea	text_estimated_end_address,a0   ; "ESTIMATED END ADDRESS  :$"
	bsr.w	print
	movea.l	d7,a6                           ; the end
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,-(sp)
	lea	text_estimation,a0              ; "ESTIMATION             :    % "
	bsr.w	print
	movea.l	d5,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+5,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	cmp.w	#$100,d5                        ; sure?
	bne.s	show_estimate_done              ; no
	movea.l	d4,a0                           ; its play routine
	jsr	(a0)                            ; started
show_estimate_done:
	bra.w	music_ripper_key
found_quartet:	; from: music_search
	move.l	a0,d5                           ; the voice set
	tst.l	d5                              ; found?
	bne.s	found_quartet_show              ; yes
	bsr.w	find_quartet_music              ; looked for
found_quartet_show:
	movem.l	d0-d7,-(sp)
	lea	text_quartet_music,a0           ; "'QUARTET' MUSIC"
	bsr.w	print
	lea	text_voice_set_start,a0         ; "VOICE SET START ADDRESS:$"
	bsr.w	print
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,-(sp)
	movea.l	d6,a6                           ; the start
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,-(sp)
	lea	text_voice_set_end,a0           ; "VOICE SET END ADDRESS  :$"
	bsr.w	print
	movea.l	d7,a6                           ; the end
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,-(sp)
	lea	text_quartet_start_address,a0   ; "QUARTET START ADDRESS  :$"
	bsr.w	print
	movea.l	d5,a6                           ; the music
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	movem.l	(sp)+,d0-d7
	bra.w	music_ripper_key

;------------------------------------------------------------------------------
; find_quartet_music: the Quartet music looked for ($00560777 with a $46 within $400 after): d5 its start.
;------------------------------------------------------------------------------
find_quartet_music:	; from: find_soundtracker
	movem.l	d0-d4/d6-d7/a0-a6,-(sp)         ; saved
	move.l	range_start,d0                  ; the start
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
	movea.l	range_end,a1                    ; the end
	move.l	#$560777,d0                     ; the signature
find_quartet_music_next:
	cmp.l	(a0),d0                         ; there?
	beq.s	find_quartet_music_check        ; yes
find_quartet_music_on:
	addq.l	#2,a0
	cmpa.l	a1,a0                           ; the end?
	ble.s	find_quartet_music_next         ; no
	bra.s	find_quartet_music_done         ; none
find_quartet_music_check:
	movea.l	a0,a2
	lea	$400(a2),a3                     ; $400 on
find_quartet_music_note:
	cmpi.w	#$46,(a2)                       ; $46?
	beq.s	find_quartet_music_found        ; yes
	lea	$c(a2),a2                       ; 12 on
	cmpa.l	a3,a2
	ble.s	find_quartet_music_note
	bra.s	find_quartet_music_on           ; not this one
find_quartet_music_found:
	suba.l	#$10,a0                         ; its start
	move.l	a0,d5
find_quartet_music_done:
	movem.l	(sp)+,d0-d4/d6-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; find_quartet: a Quartet voice set ("2BIT" after its offsets) looked for: d6 its start, d7 its end, d5 $100,
; then the music.  d0 0 if found.
;------------------------------------------------------------------------------
find_quartet:	; from: music_search
	move.l	range_start,d0                  ; the start
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
	movea.l	range_end,a1                    ; the end
find_quartet_next:
	cmpi.b	#$32,(a0)+                      ; '2'?
	beq.s	find_quartet_check              ; yes
	cmpa.l	a1,a0                           ; the end?
	bge.w	find_quartet_none               ; yes: none
	bra.s	find_quartet_next
find_quartet_check:
	cmpi.b	#$42,(a0)                       ; "BIT"?
	bne.s	find_quartet_next
	cmpi.b	#$49,1(a0)
	bne.s	find_quartet_next
	cmpi.b	#$54,2(a0)
	bne.s	find_quartet_next
	subq.l	#1,a0
	move.l	a0,d7
	andi.l	#$fffffffe,d7                   ; even
	movea.l	d7,a0
	suba.l	#$50,a0                         ; the offsets
	moveq	#1,d7
	move.l	a0,d6
	subi.l	#$8e,d6                         ; the voice set's start
	move.l	(a0)+,d1                        ; the first offset
find_quartet_offset:
	move.l	(a0)+,d2                        ; the next
	tst.l	d2                              ; 0?
	beq.s	find_quartet_last               ; yes: the end
	cmp.l	#$32424954,d2                   ; "2BIT"?
	beq.s	find_quartet_last               ; yes: the end
	addq.w	#1,d7
	cmp.w	#$15,d7                         ; 21?
	beq.s	find_quartet_last               ; yes
	cmp.l	d2,d1
	bgt.s	find_quartet_offset             ; the largest
	move.l	d2,d1
	bra.s	find_quartet_offset
find_quartet_last:
	movea.l	d6,a0
	adda.l	d1,a0                           ; the last voice
	cmpa.l	#$400000,a0                     ; past 4 Mb?
	bge.w	find_quartet_none               ; yes: none
	moveq	#0,d2
find_quartet_skip:
	cmpi.w	#$ffff,(a0)                     ; $FFFF?
	bne.s	find_quartet_length             ; no
	addq.l	#2,a0
	cmpa.l	#$400000,a0
	bge.w	find_quartet_none
	bra.s	find_quartet_skip
find_quartet_length:
	move.w	(a0)+,d2                        ; its length
	tst.w	(a0)+
	bne.s	find_quartet_end
find_quartet_length_next:
	move.w	(a0)+,d1
	tst.w	(a0)+
	bne.s	find_quartet_end
	cmp.w	d1,d2
	bge.s	find_quartet_length_next
	move.w	d1,d2                           ; the largest
	bra.s	find_quartet_length_next
find_quartet_end:
	subq.l	#4,d2
	adda.l	d2,a0
	move.l	a0,d7                           ; the end
	move.w	#$100,d5                        ; sure
	moveq	#0,d0                           ; found
	bsr.w	find_quartet_player             ; the player looked for
	rts

;------------------------------------------------------------------------------
; find_quartet_player: a pointer to the voice set (after bra or before movem) looked for: a0 the player, or 0.
;------------------------------------------------------------------------------
find_quartet_player:	; from: find_quartet
	move.l	range_start,d0                  ; the start
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
	movea.l	range_end,a1                    ; the end
find_quartet_player_next:
	cmp.l	(a0),d6                         ; the voice set's address?
	beq.s	find_quartet_player_check       ; yes
find_quartet_player_on:
	addq.l	#2,a0
	cmpa.l	a1,a0                           ; the end?
	ble.s	find_quartet_player_next        ; no
	suba.l	a0,a0                           ; none
	bra.s	find_quartet_player_done
find_quartet_player_check:
	move.l	-$4(a0),d0                      ; the long before
	btst	#$0,d0                          ; odd?
	bne.s	find_quartet_player_on
	andi.l	#$ff000000,d0
	bne.s	find_quartet_player_on
	cmpi.w	#$6000,-$8(a0)                  ; a bra before?
	beq.s	find_quartet_player_found       ; yes
	cmpi.l	#$48e7fffe,4(a0)                ; a movem after?
	beq.s	find_quartet_player_found       ; yes
	bra.s	find_quartet_player_on
find_quartet_player_found:
	subq.l	#4,a0
	movea.l	(a0),a0
find_quartet_player_done:
	moveq	#0,d0
	rts
find_quartet_none:	; from: find_quartet
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; find_chip_music: three "movem.l d0-a6,-(sp) / bsr / movem.l (sp)+,d0-a6 / rts" in a row (a chip music's
; entries), then the nops after: d6 its start, d7 its end, d4 its play routine.
;------------------------------------------------------------------------------
find_chip_music:	; from: music_search
	move.l	range_start,d0                  ; the start
	andi.w	#$fffe,d0                       ; even
	movea.l	d0,a0
	movea.l	range_end,a1                    ; the end
find_chip_music_next:
	cmpi.l	#$48e7fffe,(a0)                 ; movem.l d0-a6,-(sp)?
	beq.s	find_chip_music_entry           ; yes
	addq.l	#2,a0
	moveq	#0,d5                           ; none in a row
	cmpa.l	a1,a0                           ; the end?
	ble.s	find_chip_music_next            ; no
	bra.w	find_chip_music_none            ; none
find_chip_music_entry:
	addq.l	#4,a0
	tst.w	d5                              ; the first?
	bne.s	find_chip_music_bsr             ; no
	move.l	a0,d6                           ; the start
	subq.l	#4,d6
find_chip_music_bsr:
	cmpi.w	#$6100,(a0)+                    ; bsr?
	bne.s	find_chip_music_next            ; no
	addq.l	#2,a0
	cmpi.l	#$4cdf7fff,(a0)+                ; movem.l (sp)+,d0-a6?
	bne.s	find_chip_music_next            ; no
	cmpi.w	#$4e75,(a0)+                    ; rts?
	bne.s	find_chip_music_next            ; no
	addq.w	#1,d5                           ; one more
	cmp.w	#$3,d5                          ; three?
	bne.s	find_chip_music_next            ; no
	move.w	#$2710,d4                       ; 10000
find_chip_music_nops:
	cmpi.w	#$4e71,(a0)+                    ; nops
	dbeq	d4,find_chip_music_nops
	tst.w	d4                              ; none?
	bne.w	found_chip_music
	move.l	a0,d7                           ; the end
	move.w	#$80,d5
	moveq	#0,d0                           ; found
	lea	text_chip_music_at_dcaa,a0      ; "CHIP MUSIC"
	bsr.w	print
	move.l	#play_chip_music,d4             ; its play routine
	rts

;------------------------------------------------------------------------------
; vu_meter: a VBL routine while music plays: the three channels' volumes shown as bars (falling by one a frame).
;------------------------------------------------------------------------------
vu_meter:	; from: music_ripper
	lea	$ffff8800.w,a6                  ; PSG register select, the sound chip
	moveq	#8,d1                           ; channel A
	lea	vu_level_a,a5                   ; its level
	bsr.w	vu_level
	moveq	#9,d1                           ; channel B
	lea	vu_level_b,a5
	bsr.w	vu_level
	moveq	#10,d1                          ; channel C
	lea	vu_level_c,a5
	bsr.w	vu_level
	movea.l	ripper_screen,a0                ; the screen
	lea	$1f40(a0),a0                    ; the bars' place
	moveq	#8,d4
	move.w	vu_level_a,d0
	bsr.w	draw_vu_bar                     ; drawn
	movea.l	ripper_screen,a0
	move.w	vu_level_b,d0
	lea	$1f40(a0),a0
	moveq	#16,d4
	bsr.w	draw_vu_bar                     ; drawn
	movea.l	ripper_screen,a0
	move.w	vu_level_c,d0
	lea	$1f40(a0),a0
	moveq	#24,d4
	bsr.w	draw_vu_bar                     ; drawn
	rts

;------------------------------------------------------------------------------
; draw_vu_bar: a bar of d0 (0-15) at a0+d4.
;------------------------------------------------------------------------------
draw_vu_bar:	; from: vu_meter
	move.b	$ffff8260.w,d3                  ; shift mode, the resolution
	andi.w	#$3,d3
	cmp.b	#$2,d3                          ; high?
	beq.s	draw_vu_bar_high                ; yes
	adda.w	d4,a0
	moveq	#15,d1
	sub.w	d0,d1                           ; the empty part
	tst.w	d1
	beq.s	draw_vu_bar_full
	subq.w	#1,d0
draw_vu_bar_empty:
	clr.l	(a0)                            ; cleared
	clr.l	$78(a0)
	clr.l	4(a0)
	clr.l	$7c(a0)
	clr.l	$a0(a0)
	clr.l	$118(a0)
	clr.l	$a4(a0)
	clr.l	$11c(a0)
	lea	$1e0(a0),a0
	dbra	d1,draw_vu_bar_empty
	tst.w	d0
	bmi.s	draw_vu_bar_done
draw_vu_bar_full:
	move.l	#$7fff0000,(a0)                 ; set
	move.l	#$7fff0000,$78(a0)
	move.l	#$fffe0000,4(a0)
	move.l	#$fffe0000,$7c(a0)
	move.l	#$7fff0000,$a0(a0)
	move.l	#$7fff0000,$118(a0)
	move.l	#$fffe0000,$a4(a0)
	move.l	#$fffe0000,$11c(a0)
	lea	$1e0(a0),a0
	dbra	d0,draw_vu_bar_full
draw_vu_bar_done:
	rts
draw_vu_bar_high:
	lsr.w	#1,d4
	adda.w	d4,a0
	moveq	#15,d1
	sub.w	d0,d1
	tst.w	d1
	beq.s	draw_vu_bar_high_full
	subq.w	#1,d0
draw_vu_bar_high_empty:
	clr.w	(a0)                            ; cleared
	clr.w	$3c(a0)
	clr.w	2(a0)
	clr.w	$3e(a0)
	clr.w	$50(a0)
	clr.w	$a0(a0)
	clr.w	$8c(a0)
	clr.w	$dc(a0)
	clr.w	$52(a0)
	clr.w	$a2(a0)
	clr.w	$8e(a0)
	clr.w	$de(a0)
	lea	$1e0(a0),a0
	dbra	d1,draw_vu_bar_high_empty
	tst.w	d0
	bmi.s	draw_vu_bar_high_done
draw_vu_bar_high_full:
	move.w	#$7fff,(a0)                     ; set
	move.w	#$7fff,$3c(a0)
	move.w	#$fffe,2(a0)
	move.w	#$fffe,$3e(a0)
	move.w	#$7fff,$a0(a0)
	move.w	#$7fff,$50(a0)
	move.w	#$7fff,$8c(a0)
	move.w	#$7fff,$dc(a0)
	move.w	#$fffe,$a2(a0)
	move.w	#$fffe,$52(a0)
	move.w	#$fffe,$8e(a0)
	move.w	#$fffe,$de(a0)
	lea	$1e0(a0),a0
	dbra	d0,draw_vu_bar_high_full
draw_vu_bar_high_done:
	rts

;------------------------------------------------------------------------------
; vu_level: the channel's volume (register d1), or the last less one if it is lower.
;------------------------------------------------------------------------------
vu_level:	; from: vu_meter
	move.b	d1,(a6)                         ; the register
	move.b	(a6),d0                         ; its volume
	andi.w	#$f,d0
	cmp.w	(a5),d0                         ; louder?
	bge.s	vu_level_set                    ; yes
	move.w	(a5),d0                         ; falling
	subq.w	#1,d0
	bge.s	vu_level_set
	moveq	#0,d0
vu_level_set:
	move.w	d0,(a5)
	rts

;------------------------------------------------------------------------------
; play_chip_music: "PLAY MUSIC ? (Y/N)", then the music started (tune 0) and its VBL routine set; +/- other
; songs, ESC stops.
;------------------------------------------------------------------------------
play_chip_music:	; from: find_chip_music, play_soundtrack
	movem.l	d1-d7,-(sp)
	lea	text_play_music_y,a0            ; "PLAY MUSIC ? (Y/N)"
	bsr.w	print
	bsr.w	get_key                         ; a key
	movem.l	(sp)+,d1-d7
	cmp.b	#$79,d0                         ; 'y'?
	beq.s	play_chip_music_go
	cmp.b	#$59,d0                         ; 'Y'?
	bne.s	play_chip_music_stop            ; no
play_chip_music_go:
	moveq	#0,d0                           ; tune 0
	move.l	d0,d4
	movea.l	d6,a0                           ; the music
	jsr	(a0)                            ; started
	clr.b	$484.w                          ; conterm, no key click
	lea	$e(a0),a0                       ; its VBL routine
	move.l	a0,$4d6.w                       ; in the VBL queue
	lea	text_playing_press_esc,a0       ; "PLAYING ... PRESS ESC TO STOP OR +/- FOR OTHER SONGS"
	bsr.w	print
play_chip_music_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; ESC?
	beq.s	play_chip_music_stop            ; yes
	cmp.b	#$2b,d0                         ; '+'?
	bne.s	play_chip_music_minus           ; no
	addq.l	#1,d4                           ; the next tune
	move.l	d4,d0
	movea.l	d6,a0
	jsr	(a0)                            ; started
	bra.s	play_chip_music_key
play_chip_music_minus:
	cmp.b	#$2d,d0                         ; '-'?
	bne.s	play_chip_music_key             ; no
	subq.l	#1,d4                           ; the tune before
	move.l	d4,d0
	movea.l	d6,a0
	jsr	(a0)                            ; started
	bra.s	play_chip_music_key
play_chip_music_stop:
	move.b	#$7,$484.w                      ; conterm, key click
	clr.l	$4d6.w                          ; out of the VBL queue
	move.l	#$8080000,$ffff8800.w           ; PSG register select, the volumes 0
	move.l	#$9090000,$ffff8800.w           ; PSG register select
	move.l	#$a0a0000,$ffff8800.w           ; PSG register select
	rts

;------------------------------------------------------------------------------
; play_soundtrack: the same for the soundtrack routines (tune 1 first, the VBL routine 8 on).
;------------------------------------------------------------------------------
play_soundtrack:	; from: find_soundtrack
	movem.l	d1-d7,-(sp)
	lea	text_play_music_y,a0            ; "PLAY MUSIC ? (Y/N)"
	bsr.w	print
	bsr.w	get_key                         ; a key
	movem.l	(sp)+,d1-d7
	cmp.b	#$79,d0                         ; 'y'?
	beq.s	play_soundtrack_go
	cmp.b	#$59,d0                         ; 'Y'?
	bne.s	play_soundtrack_stop            ; no
play_soundtrack_go:
	moveq	#1,d0                           ; tune 1
	move.l	d0,d4
	movea.l	d6,a0                           ; the music
	jsr	(a0)                            ; started
	clr.b	$484.w                          ; conterm, no key click
	lea	8(a0),a0                        ; its VBL routine
	move.l	a0,$4d6.w                       ; in the VBL queue
	lea	text_playing_press_esc,a0       ; "PLAYING ..."
	bsr.w	print
play_soundtrack_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; ESC?
	beq.s	play_soundtrack_stop            ; yes
	cmp.b	#$2b,d0                         ; '+'?
	bne.s	play_soundtrack_minus           ; no
	addq.l	#1,d4                           ; the next tune
	move.l	d4,d0
	movea.l	d6,a0
	jsr	(a0)                            ; started
	bra.s	play_soundtrack_key
play_soundtrack_minus:
	cmp.b	#$2d,d0                         ; '-'?
	bne.s	play_soundtrack_key             ; no
	subq.l	#1,d4                           ; the tune before
	move.l	d4,d0
	movea.l	d6,a0
	jsr	(a0)                            ; started
	bra.s	play_soundtrack_key
play_soundtrack_stop:
	move.b	#$7,$484.w                      ; conterm, key click
	clr.l	$4d6.w                          ; out of the VBL queue
	move.l	#$8080000,$ffff8800.w           ; PSG register select, the volumes 0
	move.l	#$9090000,$ffff8800.w           ; PSG register select
	move.l	#$a0a0000,$ffff8800.w           ; PSG register select
	rts
found_chip_music:	; from: find_chip_music
	move.l	a0,d7                           ; the end
	move.w	#$100,d5                        ; sure
	moveq	#0,d0
	lea	text_chip_music_at_dcaa,a0      ; "CHIP MUSIC"
	bsr.w	print
	move.l	#play_chip_music,d4             ; its player
	move.w	#$2,music_kind                  ; the kind
	rts
find_chip_music_none:	; from: find_chip_music
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; find_soundtrack: a soundtrack routine: a table of bra, then "TFM" or "COS" or a sound chip write, the start
; found back to its movem, the end by its data: d6, d7, d5 the estimate, d4 the player.
;------------------------------------------------------------------------------
find_soundtrack:	; from: music_search
	move.l	range_start,d0                  ; the start
	andi.w	#$fffe,d0                       ; even
	movea.l	d0,a0
	movea.l	range_end,a1                    ; the end
	moveq	#0,d5                           ; none yet
find_soundtrack_bra:
	cmpi.w	#$6000,(a0)+                    ; bra?
	beq.s	find_soundtrack_check           ; yes
find_soundtrack_on:
	cmpa.l	a1,a0                           ; the end?
	ble.s	find_soundtrack_bra             ; no
	bra.w	find_soundtrack_texts           ; none: the texts
find_soundtrack_check:
	move.w	(a0),d0                         ; an even displacement?
	btst	#$0,d0
	bne.s	find_soundtrack_on              ; no
	cmpi.w	#$6000,2(a0)                    ; bra again?
	bne.s	find_soundtrack_on              ; no
	move.w	4(a0),d0
	btst	#$0,d0
	bne.s	find_soundtrack_on
	cmpi.w	#$6000,6(a0)                    ; bra again?
	bne.s	find_soundtrack_on              ; no
	move.w	8(a0),d0
	btst	#$0,d0
	bne.s	find_soundtrack_on
	cmpi.w	#$6000,$a(a0)                   ; a fourth bra?
	beq.s	find_soundtrack_on              ; yes: no
	movea.l	a0,a3
	lea	$64(a3),a2                      ; 100 bytes on
find_soundtrack_rts:
	cmpi.w	#$4e75,(a3)                     ; rts?
	beq.s	find_soundtrack_table           ; yes
	addq.l	#2,a3
	cmpa.l	a2,a3
	ble.s	find_soundtrack_rts
	addq.l	#4,a0
	bra.s	find_soundtrack_bra
find_soundtrack_table:
	move.l	a0,d6                           ; its start
	subq.l	#2,d6
	addq.l	#2,d5                           ; sure
	bra.s	find_soundtrack_tfm
find_soundtrack_texts:
	move.l	range_start,d0                  ; from the start
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
find_soundtrack_tfm:
	cmpi.b	#$54,(a0)+                      ; 'T'?
	beq.s	find_soundtrack_tfm_check       ; yes
	cmpa.l	a1,a0                           ; the end?
	ble.s	find_soundtrack_tfm             ; no
	bra.s	find_soundtrack_cos
find_soundtrack_tfm_check:
	cmpi.b	#$46,(a0)                       ; "FM"?
	bne.s	find_soundtrack_tfm
	cmpi.b	#$4d,1(a0)
	bne.s	find_soundtrack_tfm
	lea	-$2(a0),a1
	clr.b	-$2(a0)                         ; cut
	tst.w	d5                              ; a table found?
	beq.w	find_soundtrack_start           ; no
	movea.l	d6,a5
	lea	$200(a5),a4                     ; 512 on
find_soundtrack_tfm_move:
	cmpi.w	#$3e3a,(a5)                     ; "move.w ...(pc),d7"?
	beq.s	find_soundtrack_tfm_bne         ; yes
find_soundtrack_tfm_on:
	addq.l	#2,a5
	cmpa.l	a4,a5
	ble.s	find_soundtrack_tfm_move        ; no
	bra.w	find_soundtrack_start
find_soundtrack_tfm_bne:
	cmpi.b	#$66,4(a5)                      ; bne after?
	bne.s	find_soundtrack_tfm_on          ; no
	moveq	#0,d0
	move.w	2(a5),d0                        ; the displacement
	addq.l	#2,d0
	adda.l	d0,a5
	clr.w	(a5)                            ; patched out
	bra.w	find_soundtrack_start
find_soundtrack_cos:
	move.l	range_start,d0                  ; from the start
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
find_soundtrack_cos_next:
	cmpi.b	#$43,(a0)+                      ; 'C'?
	beq.s	find_soundtrack_cos_check       ; yes
	cmpa.l	a1,a0                           ; the end?
	ble.s	find_soundtrack_cos_next        ; no
	bra.s	find_soundtrack_psg
find_soundtrack_cos_check:
	cmpi.b	#$4f,(a0)                       ; "OS"?
	bne.s	find_soundtrack_cos_next
	cmpi.b	#$53,1(a0)
	bne.s	find_soundtrack_cos_next
	lea	-$2(a0),a1
	clr.b	-$2(a0)                         ; cut
	tst.w	d5                              ; a table found?
	beq.w	find_soundtrack_start           ; no
	movea.l	d6,a5
	lea	$200(a5),a4                     ; 512 on
find_soundtrack_cos_move:
	cmpi.w	#$3e3a,(a5)                     ; "move.w ...(pc),d7"?
	beq.s	find_soundtrack_cos_bne         ; yes
find_soundtrack_cos_on:
	addq.l	#2,a5
	cmpa.l	a4,a5
	ble.s	find_soundtrack_cos_move        ; no
	bra.w	find_soundtrack_start
find_soundtrack_cos_bne:
	cmpi.b	#$66,4(a5)                      ; bne after?
	bne.s	find_soundtrack_cos_on          ; no
	moveq	#0,d0
	move.w	2(a5),d0                        ; the displacement
	addq.l	#2,d0
	adda.l	d0,a5
	clr.w	(a5)                            ; patched out
	bra.w	find_soundtrack_start
find_soundtrack_psg:
	tst.w	d5                              ; a table found?
	beq.w	find_soundtrack_none            ; no: none
	moveq	#0,d5
	movea.l	d6,a0
	lea	$300(a0),a2                     ; $300 on
find_soundtrack_psg_next:
	cmpi.w	#$8800,(a0)+                    ; the sound chip ($8800)?
	beq.s	find_soundtrack_start           ; yes
	cmpa.l	a2,a0
	ble.s	find_soundtrack_psg_next
	bra.w	find_soundtrack_none            ; none
find_soundtrack_start:
	tst.w	d5                              ; a table?
	bne.s	find_soundtrack_end             ; yes
	move.l	a0,d0
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
	movea.l	a0,a2
	suba.l	#$7d0,a2                        ; $7D0 back at most
find_soundtrack_movem:
	cmpi.w	#$48e7,(a0)                     ; movem?
	beq.s	find_soundtrack_movem_check     ; yes
	subq.l	#2,a0
	cmpa.l	a2,a0
	bge.s	find_soundtrack_movem
	bra.s	find_soundtrack_found_start
find_soundtrack_movem_check:
	subq.l	#2,a0
	cmpi.w	#$fffe,4(a0)                    ; "movem ..., bsr"?
	bne.s	find_soundtrack_movem           ; no
	cmpi.b	#$61,5(a0)
	bne.s	find_soundtrack_movem           ; no
find_soundtrack_movem_back:
	movea.l	a0,a1
	movea.l	a0,a2
	suba.l	#$1e,a2                         ; 30 back
find_soundtrack_movem_again:
	cmpi.w	#$48e7,(a1)                     ; another?
	beq.s	find_soundtrack_movem_before    ; yes
	subq.l	#2,a1
	cmpa.l	a2,a1
	bge.s	find_soundtrack_movem_again
	bra.s	find_soundtrack_found_start
find_soundtrack_movem_before:
	subq.l	#2,a1
	cmpi.w	#$fffe,4(a1)
	bne.s	find_soundtrack_movem_again
	cmpi.b	#$61,5(a1)
	bne.s	find_soundtrack_movem_again
	movea.l	a1,a0
	bra.s	find_soundtrack_movem_back
find_soundtrack_found_start:
	addq.l	#2,a0
	move.l	a0,d6                           ; the start
find_soundtrack_end:
	move.l	a0,d0
	andi.l	#$fffffffe,d0                   ; even
	movea.l	d0,a0
	movea.l	a0,a3
	adda.l	#$7530,a3                       ; 30000 on at most
	move.l	a3,d7
	adda.l	#$500,a0                        ; from $500 on
find_soundtrack_end_next:
	tst.w	(a0)
	bne.s	find_soundtrack_end_check
find_soundtrack_end_on:
	addq.l	#2,a0
	cmpa.l	a3,a0
	ble.s	find_soundtrack_end_next
	bra.w	find_soundtrack_no_end
find_soundtrack_end_check:
	move.w	(a0),d1
	andi.w	#$fff0,d1
	bne.s	find_soundtrack_end_on
	moveq	#0,d0
find_soundtrack_zeros:
	addq.l	#2,a0                           ; 7 zero words?
	tst.w	(a0)
	bne.s	find_soundtrack_end_on
	addq.w	#1,d0
	cmp.w	#$7,d0
	bne.s	find_soundtrack_zeros
	move.l	a0,d7                           ; the end
	moveq	#0,d0
	tst.w	d5                              ; a table?
	bne.s	find_soundtrack_sure            ; yes
	moveq	#80,d5                          ; 80%
	bra.s	find_soundtrack_kind
find_soundtrack_no_end:
	moveq	#0,d0
	tst.w	d5                              ; a table?
	bne.s	find_soundtrack_sure            ; yes
	moveq	#48,d5                          ; 48%
	bra.s	find_soundtrack_kind
find_soundtrack_sure:
	move.w	#$100,d5                        ; sure
find_soundtrack_kind:
	movea.l	d6,a0
	cmpi.w	#$6000,-$4(a0)                  ; a bra before?
	beq.s	find_soundtrack_chip            ; yes
	lea	text_chip_music,a0              ; "SOUNDTRACK"
	bsr.w	print
	move.l	#play_soundtrack,d4             ; its player
	move.w	#$1,music_kind                  ; the kind
find_soundtrack_rte:
	rts                                     ; (not reached)
find_soundtrack_chip:
	movea.l	d6,a1
	movea.l	d7,a2
	movea.l	a1,a3
	lea	$1000(a3),a4                    ; $1000 on
find_soundtrack_chip_rte:
	cmpi.w	#$4e73,(a3)+                    ; rte?
	beq.s	find_soundtrack_chip_found      ; yes
	cmpa.l	a4,a3
	ble.s	find_soundtrack_chip_rte
	bra.s	find_soundtrack_steps
find_soundtrack_chip_found:
	lea	text_soundtrack,a0              ; "CHIP MUSIC"
	bsr.w	print
	move.l	#play_soundtrack,d4             ; its player
	movea.l	d6,a0
	move.w	#$98,d5
	rts
find_soundtrack_steps:
	cmpi.w	#$1,(a1)+                       ; 1?
	beq.s	find_soundtrack_steps_check     ; yes
	cmpa.l	a2,a1
	ble.s	find_soundtrack_steps
	lea	text_chip_music,a0              ; "SOUNDTRACK"
	bsr.w	print
	move.l	#play_soundtrack,d4
	movea.l	d6,a0
	move.w	#$1,music_kind
	rts
find_soundtrack_steps_check:
	cmpi.w	#$203,(a1)+                     ; 2, 3?
	bne.s	find_soundtrack_steps           ; no
	cmpi.w	#$405,(a1)                      ; 4, 5?
	bne.s	find_soundtrack_steps           ; no
	cmpi.w	#$607,2(a1)                     ; 6, 7?
	bne.s	find_soundtrack_steps           ; no
	clr.w	-$6(a1)                         ; patched
	subq.l	#4,d6
	lea	text_chip_music,a0              ; "SOUNDTRACK"
	bsr.w	print
	move.l	#play_soundtrack,d4
	movea.l	d6,a0
	move.w	#$1,music_kind
	rts
find_soundtrack_none:
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; show_error: the error d0 named on the message line until a key (the printer's error first if printing).
;------------------------------------------------------------------------------
show_error:	; from: external_call, create_file, append_file, save_source, save_file, read_file
	tst.w	saving_picture                  ; printing?
	beq.s	show_error_text                 ; no
	clr.w	printing_off
	clr.w	saving_picture
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	d0,-(sp)
	bsr.w	draw_settings                   ; the printer stopped
	bra.s	show_error_find
show_error_text:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	d0,-(sp)
show_error_find:
	lea	position_24_0,a0                ; the line
	bsr.w	print
	move.l	(sp)+,d0
	lea	error_numbers,a0                ; the error numbers
	move.w	d0,d1
	neg.w	d1                              ; positive
	moveq	#0,d2
show_error_next:
	cmp.w	(a0),d1                         ; this one?
	beq.s	show_error_found                ; yes
	addq.w	#1,d2
	tst.w	(a0)+                           ; the end?
	bpl.s	show_error_next                 ; no
	moveq	#2,d2                           ; "UNKNOW ERROR"
show_error_found:
	lea	error_texts,a0                  ; the texts
	add.w	d2,d2
	add.w	d2,d2                           ; * 4
	movea.l	0(a0,d2.w),a0                   ; its text
	bsr.w	print
	bsr.w	get_key                         ; a key
	lea	position_24_0_at_e30e,a0        ; the line cleared
	bsr.w	print
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; memory_ripper (F2): MEMORY RIPPER: 20 lines of the memory in hex (or disassembled): the cursor keys,
; Space/F1 and F2 a page, 0-9 go to a bookmark (Control 0-9 set it), P print, F3 the address, F4 search, F5
; fill, F6 edit, F7 copy, F8 hex or disassembly, F9 save (binary or source), a search again, F10 back.
;------------------------------------------------------------------------------
memory_ripper:	; from: info
	move.b	#$ff,last_search_kind           ; no search yet
	lea	text_memory_ripper_f1up,a0      ; its title
	bsr.w	print
	moveq	#0,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#18,d7
	bsr.w	draw_box                        ; the top box
	moveq	#20,d4
	moveq	#0,d5
	move.w	#$27f,d6
	move.w	#$b9,d7
	bsr.w	draw_box                        ; the dump's box
memory_ripper_draw:	; from: modules, search_again
	tst.w	disassembly_view                ; disassembly?
	bne.s	memory_ripper_disassembly       ; yes
	bsr.w	draw_memory_dump                ; the hex dump
	bra.w	memory_ripper_key
memory_ripper_disassembly:
	move.l	memory_address,d0               ; the address
	andi.w	#$fffe,d0                       ; even
	move.l	d0,memory_address
	bsr.w	draw_memory_disassembly         ; disassembled
memory_ripper_key:
	lea	position_24_0_at_deb0,a0        ; the help line
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$3,d0                          ; Control C?
	bne.s	memory_ripper_function          ; no
	moveq	#2,d0                           ; the calculator, then here
	bra.w	run_module
memory_ripper_function:
	moveq	#2,d1
	bsr.w	module_keys                     ; the module keys
	cmp.b	#$70,d0                         ; 'p'?
	bne.s	memory_ripper_print             ; no
	clr.w	buffer_length                   ; not the disk buffer
	bsr.w	print_memory                    ; printed
	bra.w	memory_ripper_draw
memory_ripper_print:
	cmp.b	#$50,d0                         ; 'P'?
	bne.s	memory_ripper_space             ; no
	clr.w	buffer_length
	bsr.w	print_memory                    ; printed
	bra.w	memory_ripper_draw
memory_ripper_space:
	cmp.b	#$20,d0                         ; Space?
	beq.w	memory_ripper_page_down         ; a page on
	cmp.l	#$500032,d0                     ; Shift down?
	beq.w	memory_ripper_page_down         ; a page on
	cmp.l	#$480038,d0                     ; Shift up?
	beq.w	memory_ripper_page_up           ; a page back
	cmp.l	#$4d0036,d0                     ; Shift right?
	beq.w	memory_ripper_scan
	cmp.l	#$4b0034,d0                     ; Shift left?
	beq.w	memory_ripper_scan
	cmp.l	#$6e0000,d0                     ; Shift Insert?
	bne.s	memory_ripper_undo              ; no
	move.l	#$6d0012,d0                     ; as Control 4
memory_ripper_undo:
	cmp.l	#$6c001e,d0                     ; Shift Home?
	bne.s	memory_ripper_digit             ; no
	move.l	#$6d0016,d0                     ; as Control 8
memory_ripper_digit:
	cmp.b	#$39,d0                         ; '0'-'9'?
	bgt.s	memory_ripper_mark
	cmp.b	#$30,d0
	blt.s	memory_ripper_mark
	lea	bookmarks,a0                    ; the bookmarks
	move.w	d0,d1
	subi.w	#$30,d1
	lsl.w	#2,d1
	move.l	0(a0,d1.w),memory_address       ; go there
	tst.w	disassembly_view                ; disassembly?
	bne.s	memory_ripper_digit_disassembly ; yes
	subi.l	#$140,memory_address            ; a page back (shown from it)
	moveq	#59,d0
	bra.s	memory_ripper_page_down
memory_ripper_digit_disassembly:
	moveq	#59,d0
	bra.w	memory_ripper_draw
	bra.s	memory_ripper_page_down         ; (not reached)
memory_ripper_mark:
	cmp.b	#$19,d0                         ; $10-$19?
	bgt.s	memory_ripper_scan
	cmp.b	#$10,d0
	blt.s	memory_ripper_scan
	lea	bookmarks,a0                    ; the bookmarks
	move.w	d0,d1
	subi.w	#$10,d1
	lsl.w	#2,d1
	move.l	memory_address,0(a0,d1.w)       ; set there
memory_ripper_scan:
	swap	d0                              ; its scan code
	cmp.b	#$3b,d0                         ; F1?
	bne.s	memory_ripper_f2                ; no
memory_ripper_page_down:
	tst.w	disassembly_view                ; disassembly?
	bne.s	memory_ripper_page_down_disassembly ; yes
	addi.l	#$140,memory_address            ; 320 bytes on
	bra.w	memory_ripper_draw
memory_ripper_page_down_disassembly:
	move.l	next_page_address,memory_address ; from the next page
	bra.w	memory_ripper_draw
memory_ripper_f2:
	cmp.b	#$3c,d0                         ; F2?
	bne.s	memory_ripper_down              ; no
memory_ripper_page_up:
	tst.w	disassembly_view                ; disassembly?
	bne.s	memory_ripper_page_up_disassembly ; yes
	subi.l	#$140,memory_address            ; 320 bytes back
	bra.w	memory_ripper_draw
memory_ripper_page_up_disassembly:
	subi.l	#$28,memory_address             ; 40 bytes back
	bra.w	memory_ripper_draw
memory_ripper_down:
	cmp.b	#$50,d0                         ; down?
	bne.s	memory_ripper_up                ; no
	tst.w	disassembly_view                ; disassembly?
	bne.s	memory_ripper_down_disassembly  ; yes
	addi.l	#$10,memory_address             ; 16 bytes on
	bra.w	memory_ripper_draw
memory_ripper_down_disassembly:
	move.l	next_line_address,memory_address ; the next instruction
	bra.w	memory_ripper_draw
memory_ripper_up:
	cmp.b	#$48,d0                         ; up?
	bne.s	memory_ripper_f3                ; no
	tst.w	disassembly_view                ; disassembly?
	bne.s	memory_ripper_up_disassembly    ; yes
	subi.l	#$10,memory_address             ; 16 bytes back
	bra.w	memory_ripper_draw
memory_ripper_up_disassembly:
	subi.l	#$2,memory_address              ; a word back
	bra.w	memory_ripper_draw
memory_ripper_f3:
	cmp.b	#$3d,d0                         ; F3?
	bne.s	memory_ripper_f4                ; no
	bsr.w	new_dump_address                ; "NEW DUMP ADDRESS : $"
	bra.w	memory_ripper_draw
memory_ripper_f4:
	cmp.b	#$3e,d0                         ; F4?
	bne.s	memory_ripper_f5                ; no
	bsr.w	search_memory                   ; search
	bra.w	memory_ripper_draw
memory_ripper_f5:
	cmp.b	#$3f,d0                         ; F5?
	bne.s	memory_ripper_f6                ; no
	bsr.w	fill_memory                     ; fill
	bra.w	memory_ripper_draw
memory_ripper_f6:
	cmp.b	#$40,d0                         ; F6?
	bne.s	memory_ripper_f7                ; no
	tst.w	disassembly_view                ; disassembly?
	bne.w	memory_ripper_draw              ; yes: no
	bsr.w	edit_memory                     ; copy
	bra.w	memory_ripper_draw
memory_ripper_f7:
	cmp.b	#$41,d0                         ; F7?
	bne.s	memory_ripper_f8                ; no
	bsr.w	copy_memory
	bra.w	memory_ripper_draw
memory_ripper_f8:
	cmp.b	#$42,d0                         ; F8?
	bne.s	memory_ripper_f9                ; no
	not.w	disassembly_view                ; hex or disassembly
	bra.w	memory_ripper_draw
memory_ripper_f9:
	cmp.b	#$43,d0                         ; F9?
	bne.s	memory_ripper_again             ; no
	lea	text_save_b_inary_s,a0          ; "SAVE (B)INARY / (S)OURCE ?"
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$73,d0                         ; 's'?
	beq.s	memory_ripper_source
	cmp.b	#$53,d0                         ; 'S'?
	beq.s	memory_ripper_source
	cmp.b	#$62,d0                         ; 'b'?
	beq.s	memory_ripper_binary
	cmp.b	#$42,d0                         ; 'B'?
	beq.s	memory_ripper_binary
	bra.w	memory_ripper_draw              ; other: back
memory_ripper_source:
	bsr.w	save_source                     ; as source
	bra.w	memory_ripper_draw
memory_ripper_binary:
	bsr.w	save_binary                     ; as binary
	bra.w	memory_ripper_draw
memory_ripper_again:
	cmp.b	#$61,d0                         ; 'a'?
	bne.w	memory_ripper_left              ; no
	bsr.w	search_again                    ; the search again
	bra.w	memory_ripper_draw
memory_ripper_left:
	cmp.b	#$4b,d0                         ; left?
	bne.s	memory_ripper_right             ; no
	tst.w	disassembly_view                ; disassembly?
	bne.s	memory_ripper_left_disassembly  ; yes
	subq.l	#1,memory_address               ; a byte back
	bra.w	memory_ripper_draw
memory_ripper_left_disassembly:
	subq.l	#2,memory_address               ; a word back
	bra.w	memory_ripper_draw
memory_ripper_right:
	cmp.b	#$4d,d0                         ; right?
	bne.s	memory_ripper_f10               ; no
	tst.w	disassembly_view                ; disassembly?
	bne.s	memory_ripper_right_disassembly ; yes
	addq.l	#1,memory_address               ; a byte on
	bra.w	memory_ripper_draw
memory_ripper_right_disassembly:
	addq.l	#2,memory_address               ; a word on
	bra.w	memory_ripper_draw
memory_ripper_f10:
	cmp.b	#$44,d0                         ; F10?
	beq.s	memory_ripper_done              ; yes
	bra.w	memory_ripper_key               ; no: another key
memory_ripper_done:
	rts

;------------------------------------------------------------------------------
; save_source: the memory saved as an assembler source: the text section disassembled (labels L+address for
; the addresses in range, two tabs, the instruction), then "SECTION DATA" as DC.B lines.
;------------------------------------------------------------------------------
save_source:	; from: memory_ripper
	lea	text_start_address_section,a0   ; "START ADDRESS SECTION TEXT : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	save_source_done                ; no
	move.l	d2,range_start                  ; the start
	lea	text_end_address_section,a0     ; "END ADDRESS SECTION TEXT : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	save_source_done                ; no
	move.l	d2,range_end                    ; the text's end
	sub.l	range_start,d2
	ble.w	save_source_done                ; none
	move.l	range_end,data_end              ; no data unless given
	lea	text_end_address_section_data,a0 ; "END ADDRESS SECTION DATA : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.s	save_source_name                ; no
	move.l	d2,data_end                     ; the data's end
	sub.l	range_end,d2
	bgt.s	save_source_name                ; after the text?
	move.l	range_end,data_end              ; no: no data
save_source_name:
	lea	text_enter_filename,a0          ; "ENTER FILENAME : "
	bsr.w	print
	move.w	#$3d00,input_buffer             ; 61 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.s	save_source_done                ; no
	bsr.w	force_media_change              ; the path set
	lea	input_buffer+2,a0               ; the name
	move.w	#$0,-(sp)                       ; normal file
	move.l	a0,-(sp)
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	cmp.l	#$ffffffff,d0                   ; -1?
	bne.s	save_source_open                ; no
	move.l	#$fffffff3,d0                   ; as -13
save_source_open:
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	move.w	d0,music_kind                   ; the handle
	bsr.w	save_source_text                ; the text
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	bsr.w	save_source_data                ; the data
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	move.w	music_kind,d1                   ; the handle
	move.w	d1,-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
save_source_done:
	rts

;------------------------------------------------------------------------------
; save_source_text: the text section disassembled, 20 lines at a time into the buffer, then written.
;------------------------------------------------------------------------------
save_source_text:	; from: save_source
	movea.l	range_start,a5                  ; the start
	movea.l	range_end,a1                    ; the end
save_source_text_block:
	lea	disk_buffer,a2                  ; the buffer
	move.l	a2,source_buffer_end
	clr.w	line_count                      ; no lines
save_source_text_line:
	cmpa.l	range_end,a5                    ; the end?
	bge.s	save_source_text_end            ; yes
	lea	dump_lines,a6                   ; the line
	movem.l	a0-a5,-(sp)                     ; saved
	movea.l	a6,a4
	movea.l	a5,a6                           ; the address
	lea	hex_digits,a5                   ; the digits
	bsr.w	put_hex_address                 ; in hex
	move.b	#$20,(a4)+                      ; two spaces
	move.b	#$20,(a4)+
	movea.l	a4,a6
	movem.l	(sp)+,a0-a5
	movea.l	a5,a4
	bsr.w	dis_instruction                 ; disassembled
	lea	2(a4),a5
	bsr.w	dis_end                         ; its operands
	move.b	#$20,(a6)+                      ; a space
	clr.b	(a6)+                           ; ended
	bsr.w	source_line                     ; as a source line
	addq.w	#1,line_count                   ; one more
	cmpi.w	#$14,line_count                 ; 20?
	bne.s	save_source_text_line           ; no
	bsr.w	write_source_buffer             ; written
	tst.l	d0                              ; an error?
	bmi.s	save_source_text_done           ; yes
	bra.s	save_source_text_block          ; the next block
save_source_text_end:
	bsr.w	write_source_buffer             ; written
save_source_text_done:
	rts

;------------------------------------------------------------------------------
; write_source_buffer: the buffer up to its end written to the file; d0 -68 if not all.
;------------------------------------------------------------------------------
write_source_buffer:	; from: save_source_text, save_source_data
	movem.l	d1-d7/a0-a6,-(sp)
	lea	disk_buffer,a1                  ; the buffer
	move.l	a1,d0
	move.l	source_buffer_end,d3            ; its end
	sub.l	d0,d3                           ; the length
	move.w	music_kind,d1                   ; the handle
	move.l	a1,-(sp)
	move.l	d3,-(sp)
	move.w	d1,-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	cmp.l	d0,d3                           ; all?
	ble.s	write_source_buffer_done        ; yes
	move.l	#$ffffffbc,d0                   ; -68: disk full
write_source_buffer_done:
	movem.l	(sp)+,d1-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; source_line: the disassembled line made a source line: 'L' and the address without its leading zeros, two
; tabs, the mnemonic, a tab and the operands, each "$address" in the text's range made a label.
;------------------------------------------------------------------------------
source_line:	; from: save_source_text
	movem.l	d0-d7/a0-a6,-(sp)
	movea.l	source_buffer_end,a0            ; the buffer's end
	lea	dump_lines,a1                   ; the line
	move.b	#$4c,(a0)+                      ; 'L'
source_line_zeros:
	cmpi.b	#$30,(a1)+                      ; leading zeros skipped
	beq.s	source_line_zeros
	subq.l	#1,a1
source_line_address:
	cmpi.b	#$20,(a1)                       ; its end?
	beq.s	source_line_mnemonic            ; yes
	move.b	(a1)+,(a0)+                     ; copied
	bra.s	source_line_address
source_line_mnemonic:
	move.b	#$9,(a0)+                       ; two tabs
	move.b	#$9,(a0)+
source_line_skip:
	cmpi.b	#$20,(a1)+                      ; spaces skipped
	beq.s	source_line_skip
	subq.l	#1,a1
source_line_copy_mnemonic:
	cmpi.b	#$20,(a1)                       ; its end?
	beq.s	source_line_operands            ; yes
	move.b	(a1)+,(a0)+                     ; copied
	bra.s	source_line_copy_mnemonic
source_line_operands:
	tst.b	1(a1)                           ; any operands?
	beq.s	source_line_end                 ; no
	move.b	#$9,(a0)+                       ; a tab
source_line_skip_operands:
	cmpi.b	#$20,(a1)+                      ; spaces skipped
	beq.s	source_line_skip_operands
	subq.l	#1,a1
	movea.l	a1,a2
source_line_find_dollar:
	cmpi.b	#$24,(a2)                       ; '$'?
	beq.s	source_line_dollar              ; yes
source_line_next_char:
	tst.b	(a2)+
	bne.s	source_line_find_dollar
source_line_copy:
	move.b	(a1)+,(a0)+                     ; copied
	bne.s	source_line_copy
	subq.l	#1,a0
	bra.s	source_line_end
source_line_dollar:
	cmpi.b	#$23,-$1(a2)                    ; '#$' (immediate)?
	beq.s	source_line_next_char           ; yes: left
	bsr.w	address_in_text                 ; in the text's range?
	tst.l	d0                              ; no
	bne.s	source_line_next_char
	move.b	#$4c,(a2)                       ; '$' to 'L'
	bra.s	source_line_next_char
source_line_end:
	move.b	#$d,(a0)+                       ; CR
	move.b	#$a,(a0)+                       ; LF
	move.l	a0,source_buffer_end            ; the buffer's end
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; address_in_text: the hex after the '$' at a2: d0 0 if it is between the text's start and the data's end.
;------------------------------------------------------------------------------
address_in_text:	; from: source_line
	move.l	a2,-(sp)
	addq.l	#1,a2
	moveq	#0,d7
address_in_text_digit:
	moveq	#0,d0
	move.b	(a2)+,d0
	cmp.b	#$30,d0                         ; '0'-'9'?
	blt.s	address_in_text_letter
	cmp.b	#$39,d0
	bgt.s	address_in_text_letter
	subi.b	#$30,d0
address_in_text_add:
	lsl.l	#4,d7
	or.b	d0,d7                           ; in
	bra.s	address_in_text_digit
address_in_text_letter:
	cmp.b	#$41,d0                         ; 'A'-'F'?
	blt.s	address_in_text_end
	cmp.b	#$46,d0
	bgt.s	address_in_text_end
	subi.b	#$41,d0
	addi.w	#$a,d0
	bra.s	address_in_text_add
address_in_text_end:
	cmp.l	range_start,d7                  ; before the start?
	blt.s	address_in_text_no              ; yes
	cmp.l	data_end,d7                     ; past the end?
	bgt.s	address_in_text_no              ; yes
	clr.l	d0                              ; in
	movea.l	(sp)+,a2
	rts
address_in_text_no:
	moveq	#-1,d0                          ; out
	movea.l	(sp)+,a2
	rts
	rts                                     ; (not reached)

;------------------------------------------------------------------------------
; save_source_data: "SECTION DATA", then each byte as "Laddress DC.B $xx".
;------------------------------------------------------------------------------
save_source_data:	; from: save_source
	cmpa.l	data_end,a5                     ; any data?
	bge.s	save_source_data_done           ; no
	lea	disk_buffer,a1                  ; the buffer
	move.w	#$909,(a1)+                     ; two tabs
	move.l	#$53454354,(a1)+                ; "SECTION DATA"
	move.l	#$494f4e20,(a1)+
	move.l	#$44415441,(a1)+
	move.w	#$d0a,(a1)+                     ; CR LF
	bra.s	save_source_data_start
save_source_data_block:
	lea	disk_buffer,a1                  ; the buffer
save_source_data_start:
	move.l	a1,source_buffer_end
	clr.w	line_count                      ; no lines
save_source_data_line:
	cmpa.l	data_end,a5                     ; the end?
	bgt.s	save_source_data_end            ; yes
	movea.l	a5,a0
	bsr.w	data_line                       ; the line
	addq.l	#1,a5
	addq.w	#1,line_count                   ; one more
	cmpi.w	#$32,line_count                 ; 50?
	bne.s	save_source_data_line           ; no
	bsr.w	write_source_buffer             ; written
	tst.l	d0                              ; an error?
	bmi.s	save_source_data_done           ; yes
	bra.s	save_source_data_block          ; the next block
save_source_data_end:
	bsr.w	write_source_buffer             ; written
save_source_data_done:
	rts

;------------------------------------------------------------------------------
; data_line: "L" the address (no leading zeros), two tabs, "DC.B", a tab, "$" and the byte at a0.
;------------------------------------------------------------------------------
data_line:	; from: save_source_data
	movea.l	source_buffer_end,a1            ; the buffer's end
	move.b	#$4c,(a1)+                      ; 'L'
	move.l	a0,d0
	moveq	#0,d2
data_line_zeros:
	cmp.w	#$8,d2                          ; 8 digits?
	beq.s	data_line_end                   ; yes
	rol.l	#4,d0
	addq.w	#1,d2
	move.b	d0,d1
	andi.w	#$f,d1
	beq.s	data_line_zeros                 ; a leading zero
data_line_digit:
	cmp.b	#$9,d1
	bgt.s	data_line_letter
	addi.b	#$30,d1
	bra.s	data_line_put
data_line_letter:
	subi.b	#$a,d1
	addi.b	#$41,d1
data_line_put:
	move.b	d1,(a1)+
	rol.l	#4,d0
	addq.w	#1,d2
	move.b	d0,d1
	andi.w	#$f,d1
	cmp.w	#$9,d2                          ; all?
	beq.s	data_line_end                   ; yes
	bra.s	data_line_digit
data_line_end:
	move.b	#$9,(a1)+                       ; two tabs
	move.b	#$9,(a1)+
	move.b	#$44,(a1)+                      ; "DC.B"
	move.b	#$43,(a1)+
	move.b	#$2e,(a1)+
	move.b	#$42,(a1)+
	move.b	#$9,(a1)+                       ; a tab
	move.b	#$24,(a1)+                      ; '$'
	move.b	(a0),d0                         ; the byte
	move.b	d0,d1
	andi.w	#$f0,d1                         ; the high digit
	lsr.w	#4,d1
	cmp.w	#$9,d1
	bgt.s	data_line_high_letter
	addi.b	#$30,d1
	bra.s	data_line_high_put
data_line_high_letter:
	subi.b	#$a,d1
	addi.b	#$41,d1
data_line_high_put:
	move.b	d1,(a1)+
	move.b	d0,d1                           ; the low digit
	andi.w	#$f,d1
	cmp.w	#$9,d1
	bgt.s	data_line_low_letter
	addi.b	#$30,d1
	bra.s	data_line_low_put
data_line_low_letter:
	subi.b	#$a,d1
	addi.b	#$41,d1
data_line_low_put:
	move.b	d1,(a1)+
	move.b	#$d,(a1)+                       ; CR
	move.b	#$a,(a1)+                       ; LF
	move.l	a1,source_buffer_end            ; the buffer's end
	rts

;------------------------------------------------------------------------------
; search_again ('a'): the last search on from one past the address: bytes, words, longs or text.
;------------------------------------------------------------------------------
search_again:	; from: memory_ripper
	tst.b	last_search_kind                ; none yet?
	bmi.w	memory_ripper_draw              ; yes
	move.w	last_search_kind,d0             ; the kind
	cmp.w	#$4f,d0                         ; bytes ('O')?
	bne.s	search_again_word               ; no
	addq.l	#1,memory_address               ; one on
	move.l	last_search_value,d2            ; the value
	bra.w	search_byte                     ; searched
	rts                                     ; (not reached)
search_again_word:
	cmp.w	#$4d,d0                         ; words ('M')?
	bne.s	search_again_long               ; no
	addq.l	#2,memory_address               ; a word on
	move.l	last_search_value,d2            ; the value
	bra.w	search_word                     ; searched
	rts                                     ; (not reached)
search_again_long:
	cmp.w	#$4c,d0                         ; longs ('L')?
	bne.s	search_again_text               ; no
	addq.l	#2,memory_address               ; a word on
	move.l	last_search_value,d2            ; the value
	bra.w	search_long                     ; searched
	rts                                     ; (not reached)
search_again_text:
	cmp.w	#$54,d0                         ; text ('T')?
	bne.s	search_again_done               ; no
	addq.l	#1,memory_address               ; one on
	lea	input_buffer+2,a0               ; the text into the input buffer
	lea	last_search_value,a1
	move.b	(a1)+,d0
search_again_copy:
	move.b	(a1)+,(a0)+
	bne.s	search_again_copy
	bra.w	search_text                     ; searched
search_again_done:
	rts

;------------------------------------------------------------------------------
; save_binary: "START ADDRESS : $", "END ADDRESS : $" and the name, then the memory saved as it is.
;------------------------------------------------------------------------------
save_binary:	; from: sample_save, music_save, memory_ripper
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	save_binary_done                ; no
	move.l	d2,range_start                  ; the start
	lea	text_end_address,a0             ; "END ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	save_binary_done                ; no
	move.l	d2,range_end                    ; the end
	lea	text_enter_filename,a0          ; "ENTER FILENAME : "
	bsr.w	print
	move.w	#$3d00,input_buffer             ; 61 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.s	save_binary_done                ; no
	lea	input_buffer+2,a0               ; the name
	movea.l	range_start,a1                  ; the start
	move.l	range_end,d3
	sub.l	a1,d3                           ; the length
	ble.s	save_binary_done                ; none
	bsr.w	save_file                       ; saved
save_binary_done:
	rts

;------------------------------------------------------------------------------
; draw_memory_disassembly: 20 lines of the memory disassembled from the address, printed.
;------------------------------------------------------------------------------
draw_memory_disassembly:	; from: memory_ripper
	lea	dump_lines,a6                   ; the text
	moveq	#19,d1                          ; 20 lines
draw_memory_disassembly_line:
	moveq	#77,d0                          ; 78 spaces
draw_memory_disassembly_space:
	move.b	#$20,(a6)+
	dbra	d0,draw_memory_disassembly_space
	move.b	#$b,(a6)+                       ; $0B, CR, right
	move.b	#$d,(a6)+
	move.b	#$1b,(a6)+
	move.b	#$43,(a6)+
	dbra	d1,draw_memory_disassembly_line
	move.b	#$0,(a6)+                       ; ended
	lea	dump_lines,a6
	movea.l	memory_address,a5               ; the address
	bsr.w	disassemble_memory              ; disassembled
	move.l	a5,next_page_address            ; the next page's address
	lea	dump_text,a0                    ; the text with its position
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; disassemble_memory: 20 lines from a5 into the text at a6: the address and the instruction; the second line's
; address kept (for a line down).
;------------------------------------------------------------------------------
disassemble_memory:	; from: draw_memory_disassembly
	clr.w	line_count                      ; no lines yet
disassemble_memory_next:
	move.l	a6,-(sp)
	movem.l	a0-a5,-(sp)                     ; saved
	movea.l	a6,a4
	movea.l	a5,a6
	lea	hex_digits,a5                   ; the digits
	bsr.w	put_hex_address                 ; the address
	move.b	#$20,(a4)+                      ; two spaces
	move.b	#$20,(a4)+
	movea.l	a4,a6
	movem.l	(sp)+,a0-a5
	movea.l	a5,a4
	bsr.w	dis_instruction                 ; disassembled
	lea	2(a4),a5
	tst.w	line_count                      ; the first line?
	bne.s	disassemble_memory_operands     ; no
	move.l	a5,next_line_address            ; the next instruction's address
disassemble_memory_operands:
	bsr.w	dis_end                         ; its operands
	move.b	#$20,(a6)
	movea.l	(sp)+,a6
	lea	$52(a6),a6                      ; the next line
	addq.w	#1,line_count
	cmpi.w	#$14,line_count                 ; 20?
	bne.s	disassemble_memory_next         ; no
	clr.b	(a6)+                           ; ended
	rts

;------------------------------------------------------------------------------
; dis_instruction: the instruction at a5 disassembled into the text at a6: its top four bits pick the routine
; from dis_lines; a4 is left on its last extension word (a5 = a4 + 2 after).
;------------------------------------------------------------------------------
dis_instruction:	; from: disassemble_buffer, save_source_text, disassemble_memory, disassemble_lines
	move.w	(a5),d0                         ; the opcode
	lsr.w	#8,d0
	lsr.w	#4,d0                           ; its top four bits
	andi.w	#$f,d0
	lea	dis_lines,a0                    ; the lines' routines
	lsl.w	#2,d0                           ; * 4
	movea.l	0(a0,d0.w),a0
	jsr	(a0)                            ; disassembled
	rts

;------------------------------------------------------------------------------
; dis_put_text: the text at a0 copied to a6 (a6 left on its end).
;------------------------------------------------------------------------------
dis_put_text:	; from: dis_put_pc, dis_ea, dis_ea_indirect, dis_movep, dis_bit_static, dis_bset_dynamic, 14 more
	move.b	(a0)+,(a6)+
	bne.s	dis_put_text
	subq.l	#1,a6
	rts

;------------------------------------------------------------------------------
; dis_put_space, dis_put_immediate ("#$"), dis_put_dollar, dis_put_comma, dis_put_open, dis_put_close,
; dis_put_plus, dis_put_minus: one or two characters put at a6.
;------------------------------------------------------------------------------
dis_put_space:                                  ; from: dis_movep, dis_bit_static, dis_bset_dynamic,
                                                ;   dis_immediate_instruction, dis_line_1, dis_line_4, 9 more
	move.b	#$20,(a6)+
	rts

dis_put_immediate:                              ; from: dis_ea, dis_bit_static, dis_immediate_instruction, dis_line_4,
                                                ;   dis_register_list, dis_size_long, 2 more
	move.b	#$23,(a6)+
	move.b	#$24,(a6)+
	rts

;------------------------------------------------------------------------------
; dis_put_pc: "(PC)".
;------------------------------------------------------------------------------
dis_put_pc:	; from: dis_ea
	bsr.w	dis_put_open
	lea	dis_pc_text,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_close
	rts

dis_put_dollar:	; from: dis_ea, dis_ea_indirect, dis_condition, dis_line_6
	move.b	#$24,(a6)+
	rts

dis_put_comma:	; from: dis_move_operands, dis_ea, dis_ea_indirect, dis_movep, dis_bit_static, dis_bset_dynamic, 10 more
	move.b	#$2c,(a6)+
	rts

dis_put_open:	; from: dis_put_pc, dis_ea, dis_ea_indirect
	move.b	#$28,(a6)+
	rts

dis_put_close:	; from: dis_put_pc, dis_ea, dis_ea_indirect
	move.b	#$29,(a6)+
	rts

dis_put_plus:	; from: dis_ea_indirect
	move.b	#$2b,(a6)+
	rts

dis_put_minus:	; from: dis_ea_indirect
	move.b	#$2d,(a6)+
	rts

;------------------------------------------------------------------------------
; dis_move_operands: MOVE's source and destination (the destination's mode and register swapped).
;------------------------------------------------------------------------------
dis_move_operands:	; from: dis_line_1
	move.w	(a5),d0                         ; the source
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma                   ; ','
	move.w	(a5),d0                         ; the destination
	lsr.w	#6,d0
	move.w	d0,d1
	andi.w	#$7,d1                          ; its register
	andi.w	#$38,d0                         ; its mode
	lsr.w	#3,d0
	lsl.w	#3,d1
	or.w	d1,d0                           ; as a source
	bsr.w	dis_ea
	rts

;------------------------------------------------------------------------------
; dis_ea: the effective address d0 (mode bits 3-5, register 0-2), its extension words from a4+2.
;------------------------------------------------------------------------------
dis_ea:                                         ; from: dis_move_operands, dis_movep, dis_bit_static, dis_bset_dynamic,
                                                ;   dis_immediate_instruction, dis_line_4, 8 more
	move.w	d0,d1
	lsr.w	#3,d1                           ; the mode
	andi.w	#$7,d1
	beq.w	dis_ea_register                 ; Dn
	cmp.w	#$1,d1
	beq.w	dis_ea_register                 ; An
	cmp.w	#$2,d1
	beq.w	dis_ea_indirect                 ; (An)
	cmp.w	#$3,d1
	beq.w	dis_ea_postincrement            ; (An)+
	cmp.w	#$4,d1
	beq.w	dis_ea_predecrement             ; -(An)
	cmp.w	#$5,d1
	beq.w	dis_ea_displacement             ; d16(An)
	cmp.w	#$6,d1
	beq.w	dis_ea_index                    ; d8(An,Xn)
	move.w	d0,d1                           ; mode 7
	andi.w	#$7,d1                          ; the register
	beq.w	dis_ea_absolute_word            ; abs.w
	cmp.w	#$1,d1
	beq.w	dis_ea_absolute_long            ; abs.l
	cmp.w	#$2,d1
	beq.w	dis_ea_pc_displacement          ; d16(PC)
	cmp.w	#$3,d1
	beq.w	dis_ea_pc_index                 ; d8(PC,Xn)
	cmp.w	#$4,d1
	beq.w	dis_ea_immediate                ; #imm
	rts
dis_ea_absolute_word:
	lea	2(a4),a4                        ; the extension
	bsr.w	dis_put_dollar                  ; '$'
	move.w	(a4),d0                         ; the word
	bge.w	dis_ea_absolute_word_value      ; negative?
	move.b	#$46,(a6)+                      ; "FFFF" first
	move.b	#$46,(a6)+
	move.b	#$46,(a6)+
	move.b	#$46,(a6)+
dis_ea_absolute_word_value:
	bsr.w	dis_hex_word                    ; the word
	lea	dis_word_text,a0                ; ".W"
	bsr.w	dis_put_text
	rts
dis_ea_absolute_long:
	bsr.w	dis_put_dollar                  ; '$'
	lea	2(a4),a4                        ; the extension
	move.l	(a4),d0                         ; the long
	bsr.w	dis_hex_long
	lea	2(a4),a4
	rts
dis_ea_pc_displacement:
	bsr.w	dis_put_dollar                  ; '$'
	move.l	a5,d0                           ; the extension's address
	addq.l	#2,d0
	tst.w	$43e.w                          ; flock, in the disk buffer?
	beq.s	dis_ea_pc_relative              ; no
	subi.l	#disk_buffer,d0                 ; as an offset in it
dis_ea_pc_relative:
	lea	2(a4),a4                        ; the extension
	moveq	#0,d1
	move.w	(a4),d1                         ; the displacement
	ext.l	d1
	add.l	d1,d0                           ; the target
	bsr.w	dis_hex_long
	bsr.w	dis_put_pc                      ; "(PC)"
	rts
dis_ea_pc_index:
	bsr.w	dis_put_dollar                  ; '$'
	move.l	a5,d0                           ; the extension's address
	addq.l	#2,d0
	tst.w	$43e.w                          ; flock, in the disk buffer?
	beq.s	dis_ea_pc_index_relative        ; no
	subi.l	#disk_buffer,d0                 ; as an offset
dis_ea_pc_index_relative:
	lea	2(a4),a4                        ; the extension
	moveq	#0,d1
	move.w	(a4),d1                         ; the displacement
	ext.l	d1
	add.l	d1,d0                           ; the target
	bsr.w	dis_hex_long
	bsr.w	dis_put_open                    ; '('
	lea	dis_pc_text,a0                  ; "PC"
	bsr.w	dis_put_text
	bsr.w	dis_put_comma                   ; ','
	move.w	(a4),d0                         ; the index register
	lsr.w	#8,d0
	lsr.w	#4,d0
	andi.w	#$f,d0
	lea	dis_data_registers,a0
	mulu.w	#$3,d0                          ; 3 bytes a name
	lea	0(a0,d0.w),a0
	bsr.w	dis_put_text
	move.w	(a4),d0                         ; its size
	lsr.w	#8,d0
	lsr.w	#3,d0
	lea	dis_long_text,a0                ; ".L"
	andi.w	#$1,d0
	bne.s	dis_ea_pc_index_size
	lea	dis_word_text,a0                ; ".W"
dis_ea_pc_index_size:
	bsr.w	dis_put_text
	bsr.w	dis_put_close                   ; ')'
	rts
dis_ea_immediate:
	bsr.w	dis_put_immediate               ; "#$"
	move.w	(a5),d0                         ; the size from the opcode
	lea	2(a4),a4                        ; the extension
	lsr.w	#8,d0                           ; MOVE's sizes
	lsr.w	#4,d0
	andi.w	#$f,d0
	cmp.b	#$1,d0                          ; byte?
	beq.s	dis_ea_immediate_byte
	cmp.b	#$3,d0                          ; word?
	beq.s	dis_ea_immediate_word
	cmp.w	#$2,d0                          ; long?
	beq.s	dis_ea_immediate_long
	move.w	(a5),d0                         ; the other lines' sizes
	lsr.w	#6,d0
	andi.w	#$7,d0
	beq.s	dis_ea_immediate_byte
	cmp.w	#$1,d0
	beq.s	dis_ea_immediate_word
	cmp.w	#$2,d0
	beq.s	dis_ea_immediate_long
	cmp.w	#$4,d0
	beq.s	dis_ea_immediate_byte
	cmp.w	#$5,d0
	beq.s	dis_ea_immediate_word
	cmp.w	#$6,d0
	beq.s	dis_ea_immediate_long
	cmp.w	#$3,d0
	beq.s	dis_ea_immediate_word
	cmp.w	#$7,d0
	beq.s	dis_ea_immediate_long
	rts
dis_ea_immediate_byte:
	move.w	(a4),d0                         ; a byte
	bsr.w	dis_hex_byte
	rts
dis_ea_immediate_word:
	move.w	(a4),d0                         ; a word
	bsr.w	dis_hex_word
	rts
dis_ea_immediate_long:
	move.l	(a4),d0                         ; a long
	bsr.w	dis_hex_long
	lea	2(a4),a4
	rts

;------------------------------------------------------------------------------
; dis_ea_indirect: "(An)" (and the postincrement, predecrement, displacement and index forms after).
;------------------------------------------------------------------------------
dis_ea_indirect:	; from: dis_ea
	bsr.w	dis_put_open                    ; '('
	andi.w	#$7,d0
	lea	dis_address_registers,a0        ; the address registers
	mulu.w	#$3,d0                          ; 3 bytes a name
	lea	0(a0,d0.w),a0
	bsr.w	dis_put_text
	bsr.w	dis_put_close                   ; ')'
	rts
dis_ea_postincrement:	; from: dis_ea
	bsr.w	dis_ea_indirect                 ; (An)
	bsr.w	dis_put_plus                    ; '+'
	rts
dis_ea_predecrement:	; from: dis_ea
	bsr.w	dis_put_minus                   ; '-'
	bsr.w	dis_ea_indirect                 ; (An)
	rts
dis_ea_displacement:	; from: dis_ea
	move.l	d0,-(sp)
	lea	2(a4),a4                        ; the extension
	move.w	(a4),d0
	bsr.w	dis_put_dollar                  ; '$'
	btst	#$f,d0                          ; negative?
	beq.s	dis_ea_displacement_value       ; no
	move.b	#$46,(a6)+                      ; "FFFF" first
	move.b	#$46,(a6)+
	move.b	#$46,(a6)+
	move.b	#$46,(a6)+
dis_ea_displacement_value:
	bsr.w	dis_hex_word                    ; the displacement
	move.l	(sp)+,d0
	bsr.w	dis_ea_indirect                 ; (An)
	rts
dis_ea_index:	; from: dis_ea
	move.l	d0,-(sp)
	lea	2(a4),a4                        ; the extension
	bsr.w	dis_put_dollar                  ; '$'
	move.w	(a4),d0
	bsr.w	dis_hex_byte                    ; its displacement byte
	bsr.w	dis_put_open                    ; '('
	move.l	(sp)+,d0
	andi.w	#$f,d0                          ; An
	lea	dis_address_registers,a0
	mulu.w	#$3,d0
	lea	0(a0,d0.w),a0
	bsr.w	dis_put_text
	bsr.w	dis_put_comma                   ; ','
	move.w	(a4),d0                         ; the index register
	lsr.w	#8,d0
	lsr.w	#4,d0
	andi.w	#$f,d0
	mulu.w	#$3,d0
	lea	dis_data_registers,a0
	lea	0(a0,d0.w),a0
	bsr.w	dis_put_text
	move.w	(a4),d0                         ; its size
	lsr.w	#8,d0
	lsr.w	#3,d0
	lea	dis_long_text,a0
	andi.w	#$1,d0
	bne.s	dis_ea_index_size
	lea	dis_word_text,a0
dis_ea_index_size:
	bsr.w	dis_put_text
	bsr.w	dis_put_close                   ; ')'
	rts
dis_ea_register:	; from: dis_ea
	andi.w	#$f,d0                          ; Dn or An
	lea	dis_data_registers,a0           ; the registers
	mulu.w	#$3,d0                          ; 3 bytes a name
	lea	0(a0,d0.w),a0
	bsr.w	dis_put_text
	rts

;------------------------------------------------------------------------------
; dis_line_0: line 0: the immediates (ORI, ANDI, SUBI, ADDI, EORI, CMPI), BTST to BSET, MOVEP.
;------------------------------------------------------------------------------
dis_line_0:	; from: dis_lines
	move.w	(a5),d0
	lsr.w	#8,d0
	andi.w	#$f,d0
	beq.w	dis_ori
	cmp.w	#$2,d0
	beq.w	dis_andi
	cmp.w	#$6,d0
	beq.w	dis_addi
	cmp.w	#$4,d0
	beq.w	dis_subi
	cmp.w	#$a,d0
	beq.w	dis_eori
	cmp.w	#$c,d0
	beq.w	dis_cmpi
	cmp.w	#$8,d0
	beq.w	dis_bit_static
	move.w	(a5),d0
	andi.w	#$38,d0
	cmp.w	#$8,d0
	beq.w	dis_movep
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$7,d0
	cmp.w	#$7,d0
	beq.w	dis_bset_dynamic
	cmp.w	#$4,d0
	beq.w	dis_btst_dynamic
	cmp.w	#$6,d0
	beq.w	dis_bclr_dynamic
	cmp.w	#$5,d0
	beq.w	dis_bchg_dynamic
	bra.w	dis_line_a
	rts

;------------------------------------------------------------------------------
; dis_movep: "MOVEP.W/.L Dn,d(An)" or the other way.
;------------------------------------------------------------------------------
dis_movep:	; from: dis_line_0, dis_bit_static
	lea	text_movep,a0
	bsr.w	dis_put_text
	move.b	#$2e,(a6)+
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$1,d0
	beq.s	dis_movep_word
	move.b	#$4c,(a6)+
	bra.s	dis_movep_operands
dis_movep_word:
	move.b	#$57,(a6)+
dis_movep_operands:
	bsr.w	dis_put_space
	move.w	(a5),d0
	lsr.w	#7,d0
	andi.w	#$3,d0
	cmp.w	#$2,d0
	beq.w	dis_movep_to_register
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$7,d0
	ori.w	#$28,d0
	bsr.w	dis_ea
	rts
dis_movep_to_register:
	move.w	(a5),d0
	andi.w	#$7,d0
	ori.w	#$28,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	rts

;------------------------------------------------------------------------------
; dis_bit_static: BTST, BCHG, BCLR, BSET with "#$n".
;------------------------------------------------------------------------------
dis_bit_static:	; from: dis_line_0
	move.w	(a5),d0
	andi.w	#$38,d0
	cmp.w	#$8,d0
	beq.w	dis_movep
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$3,d0
	beq.w	dis_btst_static
	cmp.w	#$3,d0
	beq.w	dis_bset_static
	cmp.w	#$2,d0
	beq.w	dis_bclr_static
	cmp.w	#$1,d0
	beq.w	dis_bchg_static
dis_btst_static:
	lea	text_btst,a0
	bra.w	dis_bit_static_operands
dis_bset_static:
	lea	text_bset,a0
dis_bit_static_operands:
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	bsr.w	dis_put_immediate
	lea	2(a4),a4
	move.w	(a4),d0
	bsr.w	dis_hex_byte
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_bclr_static:
	lea	text_bclr,a0
	bra.w	dis_bit_static_operands
dis_bchg_static:
	lea	text_bchg,a0
	bra.w	dis_bit_static_operands

;------------------------------------------------------------------------------
; dis_bset_dynamic etc.: the bit instructions with Dn.
;------------------------------------------------------------------------------
dis_bset_dynamic:	; from: dis_line_0
	lea	text_bset,a0
dis_bit_dynamic_operands:
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_btst_dynamic:	; from: dis_line_0
	lea	text_btst,a0
	bra.w	dis_bit_dynamic_operands
dis_bclr_dynamic:	; from: dis_line_0
	lea	text_bclr,a0
	bra.w	dis_bit_dynamic_operands
dis_bchg_dynamic:	; from: dis_line_0
	lea	text_bchg,a0
	bra.w	dis_bit_dynamic_operands

;------------------------------------------------------------------------------
; dis_immediate_operand: the immediate of the size in bits 6-7.
;------------------------------------------------------------------------------
dis_immediate_operand:	; from: dis_immediate_instruction
	move.w	(a5),d0
	andi.w	#$c0,d0
	beq.w	dis_immediate_byte
	cmp.w	#$40,d0
	beq.w	dis_immediate_word
	cmp.w	#$80,d0
	beq.w	dis_immediate_long
	bra.w	dis_immediate_word
dis_immediate_byte:
	lea	2(a4),a4
	move.w	(a4),d0
	bsr.w	dis_hex_byte
	rts
dis_immediate_word:
	lea	2(a4),a4
	move.w	(a4),d0
	bsr.w	dis_hex_word
	rts
dis_immediate_long:
	lea	2(a4),a4
	move.l	(a4),d0
	bsr.w	dis_hex_long
	lea	2(a4),a4
	rts
dis_addi:	; from: dis_line_0
	lea	text_addi,a0

;------------------------------------------------------------------------------
; dis_immediate_instruction: the immediate instruction's name, size, "#$n,ea" (or to CCR or SR).
;------------------------------------------------------------------------------
dis_immediate_instruction:
	bsr.w	dis_put_text
	bsr.w	dis_size
	bsr.w	dis_put_space
	bsr.w	dis_put_immediate
	bsr.w	dis_immediate_operand
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_immediate_ccr:
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	bsr.w	dis_put_immediate
	lea	2(a4),a4
	move.w	(a4),d0
	bsr.w	dis_hex_byte
	bsr.w	dis_put_comma
	lea	text_ccr,a0
	bsr.w	dis_put_text
	rts
dis_immediate_sr:
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	bsr.w	dis_put_immediate
	lea	2(a4),a4
	move.w	(a4),d0
	bsr.w	dis_hex_word
	bsr.w	dis_put_comma
	lea	text_sr,a0
	bsr.w	dis_put_text
	rts
dis_subi:	; from: dis_line_0
	lea	text_subi,a0
	bra.w	dis_immediate_instruction
dis_cmpi:	; from: dis_line_0
	lea	text_cmpi,a0
	bra.w	dis_immediate_instruction
dis_andi:	; from: dis_line_0
	lea	text_andi,a0
	move.w	(a5),d0
	andi.w	#$7c,d0
	cmp.w	#$3c,d0
	beq.w	dis_immediate_ccr
	cmp.w	#$7c,d0
	beq.w	dis_immediate_sr
	bra.w	dis_immediate_instruction
dis_eori:	; from: dis_line_0
	lea	text_eori,a0
	move.w	(a5),d0
	andi.w	#$7c,d0
	cmp.w	#$3c,d0
	beq.w	dis_immediate_ccr
	cmp.w	#$7c,d0
	beq.w	dis_immediate_sr
	bra.w	dis_immediate_instruction
dis_ori:	; from: dis_line_0
	lea	text_ori,a0
	move.w	(a5),d0
	andi.w	#$7c,d0
	cmp.w	#$3c,d0
	beq.w	dis_immediate_ccr
	cmp.w	#$7c,d0
	beq.w	dis_immediate_sr
	bra.w	dis_immediate_instruction

;------------------------------------------------------------------------------
; dis_line_1, dis_line_2, dis_line_3: MOVE.B, MOVE.L, MOVE.W (MOVEA for an address register).
;------------------------------------------------------------------------------
dis_line_1:	; from: dis_lines
	lea	text_move,a0
	bsr.w	dis_put_text
	lea	text_b,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	bsr.w	dis_move_operands
	rts
dis_line_3:	; from: dis_lines
	lea	text_move,a0
	bsr.w	dis_put_text
	lea	dis_word_text,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	bsr.w	dis_move_operands
	rts
dis_line_2:	; from: dis_lines
	lea	text_move,a0
	bsr.w	dis_put_text
	lea	dis_long_text,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	bsr.w	dis_move_operands
	rts

;------------------------------------------------------------------------------
; dis_line_4: line 4: ILLEGAL, NEGX, MOVE from SR, CHK, LEA, CLR, NEG, NOT, NBCD, SWAP, PEA, EXT, MOVEM,
; TST, TAS, TRAP, LINK, UNLK, MOVE USP, the fixed ones (RESET, NOP, STOP, RTE, RTS, TRAPV, RTR), JSR, JMP.
;------------------------------------------------------------------------------
dis_line_4:	; from: dis_lines
	move.w	(a5),d0
	cmp.w	#$4afc,d0
	beq.w	dis_illegal
	andi.w	#$ff0,d0
	cmp.w	#$e70,d0
	beq.w	dis_line_4_fixed
	cmp.w	#$e40,d0
	beq.w	dis_trap
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$3f,d0
	cmp.w	#$1b,d0
	beq.w	dis_move_to_sr
	cmp.w	#$3,d0
	beq.w	dis_move_from_sr
	cmp.w	#$13,d0
	beq.w	dis_move_to_ccr
	cmp.w	#$21,d0
	beq.w	dis_line_4_misc
	cmp.w	#$2b,d0
	beq.w	dis_tas
	cmp.w	#$3b,d0
	beq.w	dis_jmp
	cmp.w	#$3a,d0
	beq.w	dis_jsr
	cmp.w	#$39,d0
	beq.w	dis_line_4_e
	move.w	(a5),d0
	lsr.w	#8,d0
	andi.w	#$f,d0
	beq.w	dis_negx
	cmp.w	#$8,d0
	bne.w	dis_line_4_size
	move.w	(a5),d0
	andi.w	#$38,d0
	beq.w	dis_ext
dis_line_4_size:
	cmp.w	#$2,d0
	beq.w	dis_clr
	cmp.w	#$4,d0
	beq.w	dis_neg
	cmp.w	#$6,d0
	beq.w	dis_not
	cmp.w	#$a,d0
	beq.w	dis_tst
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$7,d0
	beq.w	dis_nbcd
	cmp.w	#$6,d0
	beq.w	dis_chk
	cmp.w	#$7,d0
	beq.w	dis_lea
	move.w	(a5),d0
	lsr.w	#7,d0
	andi.w	#$7,d0
	cmp.w	#$1,d0
	beq.w	dis_movem
	bra.w	dis_line_a
	rts
dis_illegal:
	lea	text_illegal,a0
	bsr.w	dis_put_text
	rts
dis_line_4_misc:
	move.w	(a5),d0
	lsr.w	#3,d0
	andi.w	#$7,d0
	beq.w	dis_swap
	lea	text_pea,a0
dis_ea_instruction:
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_swap:
	lea	text_swap,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	rts
dis_tas:
	lea	text_tas,a0
	bra.w	dis_ea_instruction
dis_jmp:
	lea	text_jmp,a0
	bra.w	dis_ea_instruction
dis_jsr:
	lea	text_jsr,a0
	bra.w	dis_ea_instruction
dis_line_4_e:
	move.w	(a5),d0
	lsr.w	#3,d0
	andi.w	#$7,d0
	cmp.w	#$2,d0
	beq.w	dis_link
	cmp.w	#$3,d0
	beq.w	dis_unlk
	move.w	(a5),d0
	lsr.w	#4,d0
	andi.w	#$7,d0
	cmp.w	#$6,d0
	beq.w	dis_move_to_usp
	bra.w	dis_line_a
dis_link:
	lea	text_link,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$7,d0
	ori.w	#$8,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	lea	2(a4),a4
	bsr.w	dis_put_immediate
	move.w	(a4),d0
	bsr.w	dis_hex_word
	rts
dis_unlk:
	lea	text_unlk,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$7,d0
	ori.w	#$8,d0
	bsr.w	dis_ea
	rts
dis_move_to_usp:
	lea	text_move,a0
	bsr.w	dis_put_text
	bsr.w	dis_size_long
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$8,d0
	bne.w	dis_move_from_usp
	move.w	(a5),d0
	andi.w	#$7,d0
	ori.w	#$8,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	lea	text_usp,a0
	bsr.w	dis_put_text
	rts
dis_move_from_usp:
	lea	text_usp,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$7,d0
	ori.w	#$8,d0
	bsr.w	dis_ea
	rts
dis_move_to_sr:
	lea	text_move,a0
	bsr.w	dis_put_text
	bsr.w	dis_size_word
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	lea	text_sr,a0
	bsr.w	dis_put_text
	rts
dis_move_from_sr:
	lea	text_move,a0
	bsr.w	dis_put_text
	bsr.w	dis_size_word
	bsr.w	dis_put_space
	lea	text_sr,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_move_to_ccr:
	lea	text_move,a0
	bsr.w	dis_put_text
	bsr.w	dis_size_byte
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	lea	text_ccr,a0
	bsr.w	dis_put_text
	rts
dis_negx:
	lea	text_negx,a0
dis_size_instruction:
	bsr.w	dis_put_text
	bsr.w	dis_size
dis_size_operand:
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_chk:
	lea	text_chk,a0
	bsr.w	dis_put_text
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	rts
dis_clr:
	lea	text_clr,a0
	bra.w	dis_size_instruction
dis_ext:
	lea	text_ext,a0
	bra.w	dis_size_instruction
dis_lea:
	lea	text_lea,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	ori.w	#$8,d0
	bsr.w	dis_ea
	rts
dis_neg:
	lea	text_neg,a0
	bra.w	dis_size_instruction
dis_not:
	lea	text_not,a0
	bra.w	dis_size_instruction
dis_nbcd:
	lea	text_nbcd,a0
	bsr.w	dis_put_text
	bra.w	dis_size_operand
dis_tst:
	lea	text_tst,a0
	bra.w	dis_size_instruction
dis_movem:
	lea	text_movem,a0
	bsr.w	dis_put_text
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$1,d0
	beq.s	dis_movem_word
	bsr.w	dis_size_long
	bra.s	dis_movem_operands
dis_movem_word:
	bsr.w	dis_size_word
dis_movem_operands:
	bsr.w	dis_put_space
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#2,d0
	andi.w	#$1,d0
	beq.w	dis_movem_to_memory
	bra.w	dis_movem_from_memory

;------------------------------------------------------------------------------
; dis_register_list: MOVEM's register list ("D0-D3/A0") from its mask (reversed for -(An)).
;------------------------------------------------------------------------------
dis_register_list:
	move.w	(a5),d0
	andi.w	#$38,d0
	cmp.w	#$20,d0
	beq.w	dis_register_list_reversed
	moveq	#0,d0
	moveq	#0,d4
	moveq	#1,d1
	moveq	#1,d5
dis_register_list_set:
	moveq	#7,d3
dis_register_list_bit:
	move.w	2(a5),d2
	and.w	d1,d2
	bne.s	dis_register_list_register
	lsl.w	#1,d1
	addq.w	#1,d0
	dbra	d3,dis_register_list_bit
	bra.s	dis_register_list_run
dis_register_list_register:
	movem.l	d0-d7,-(sp)
	bsr.w	dis_ea
	movem.l	(sp)+,d0-d7
	moveq	#0,d4
dis_register_list_next:
	lsl.w	#1,d1
	addq.w	#1,d0
	move.w	2(a5),d2
	and.w	d1,d2
	beq.s	dis_register_list_run
	addq.w	#1,d4
	dbra	d3,dis_register_list_next
dis_register_list_run:
	tst.w	d4
	beq.s	dis_register_list_separator
	moveq	#0,d4
	subq.w	#1,d0
	move.b	#$2d,(a6)+
	movem.l	d0-d7,-(sp)
	bsr.w	dis_ea
	movem.l	(sp)+,d0-d7
	addq.w	#1,d0
dis_register_list_separator:
	tst.w	d3
	bmi.s	dis_register_list_slash
	move.b	#$2f,(a6)+
	dbra	d3,dis_register_list_bit
dis_register_list_slash:
	move.b	-$1(a6),d6
	cmp.b	#$2f,d6
	beq.s	dis_register_list_address
	move.b	#$2f,(a6)+
dis_register_list_address:
	moveq	#8,d0
	dbra	d5,dis_register_list_set
	subq.l	#1,a6
	rts
dis_register_list_reversed:
	moveq	#0,d0
	moveq	#0,d4
	move.w	#$8000,d1
	moveq	#1,d5
dis_register_list_reversed_set:
	moveq	#7,d3
dis_register_list_reversed_bit:
	move.w	2(a5),d2
	and.w	d1,d2
	bne.s	dis_register_list_reversed_register
	lsr.w	#1,d1
	addq.w	#1,d0
	dbra	d3,dis_register_list_reversed_bit
	bra.s	dis_register_list_reversed_run
dis_register_list_reversed_register:
	movem.l	d0-d7,-(sp)
	bsr.w	dis_ea
	movem.l	(sp)+,d0-d7
	moveq	#0,d4
dis_register_list_reversed_next:
	lsr.w	#1,d1
	addq.w	#1,d0
	move.w	2(a5),d2
	and.w	d1,d2
	beq.s	dis_register_list_reversed_run
	addq.w	#1,d4
	dbra	d3,dis_register_list_reversed_next
dis_register_list_reversed_run:
	tst.w	d4
	beq.s	dis_register_list_reversed_separator
	moveq	#0,d4
	subq.w	#1,d0
	move.b	#$2d,(a6)+
	movem.l	d0-d7,-(sp)
	bsr.w	dis_ea
	movem.l	(sp)+,d0-d7
	addq.w	#1,d0
dis_register_list_reversed_separator:
	tst.w	d3
	bmi.s	dis_register_list_reversed_slash
	move.b	#$2f,(a6)+
	dbra	d3,dis_register_list_reversed_bit
dis_register_list_reversed_slash:
	move.b	-$1(a6),d6
	cmp.b	#$2f,d6
	beq.s	dis_register_list_reversed_address
	move.b	#$2f,(a6)+
dis_register_list_reversed_address:
	moveq	#8,d0
	dbra	d5,dis_register_list_reversed_set
	subq.l	#1,a6
	rts
dis_movem_to_memory:	; from: dis_line_4
	bsr.w	dis_register_list
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	lea	2(a5),a4
	bsr.w	dis_ea
	rts
dis_movem_from_memory:	; from: dis_line_4
	move.w	(a5),d0
	andi.w	#$3f,d0
	lea	2(a5),a4
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	bsr.w	dis_register_list
	rts
dis_trap:	; from: dis_line_4
	lea	text_trap,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	bsr.w	dis_put_immediate
	move.w	(a5),d0
	andi.w	#$f,d0
	bsr.w	dis_hex_byte
	rts
dis_line_4_fixed:	; from: dis_line_4
	move.w	(a5),d0
	cmp.w	#$4e75,d0
	beq.w	dis_rts
	cmp.w	#$4e71,d0
	beq.w	dis_nop
	cmp.w	#$4e70,d0
	beq.w	dis_reset
	cmp.w	#$4e73,d0
	beq.w	dis_rte
	cmp.w	#$4e77,d0
	beq.w	dis_rtr
	cmp.w	#$4e76,d0
	beq.w	dis_trapv
	cmp.w	#$4e72,d0
	beq.w	dis_stop
dis_rts:
	lea	text_rts,a0
	bra.w	dis_fixed_text
dis_nop:
	lea	text_nop,a0
	bra.w	dis_fixed_text
dis_rtr:
	lea	text_rtr,a0
	bra.w	dis_fixed_text
dis_trapv:
	lea	text_trapv,a0
	bra.w	dis_fixed_text
dis_rte:
	lea	text_rte,a0
	bra.w	dis_fixed_text
dis_reset:
	lea	text_reset,a0
	bra.w	dis_fixed_text
dis_stop:
	lea	text_stop,a0
	bsr.w	dis_put_text
	lea	2(a4),a4
	move.w	(a4),d0
	bsr.w	dis_put_immediate
	bsr.w	dis_hex_word
	rts
dis_fixed_text:
	bsr.w	dis_put_text
	rts

;------------------------------------------------------------------------------
; dis_line_5: line 5: ADDQ, SUBQ, Scc, DBcc.
;------------------------------------------------------------------------------
dis_line_5:	; from: dis_lines
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$3,d0
	cmp.w	#$2,d0
	ble.w	dis_quick
	bra.s	dis_line_5_size
	rts
dis_line_5_size:
	move.w	(a5),d0
	lsr.w	#4,d0
	andi.w	#$1,d0
	beq.s	dis_dbcc
	bra.s	dis_scc

;------------------------------------------------------------------------------
; dis_condition: the condition's name from bits 8-11.
;------------------------------------------------------------------------------
dis_condition:
	lea	dis_conditions,a0
	move.w	(a5),d0
	lsr.w	#8,d0
	andi.w	#$f,d0
	mulu.w	#$3,d0
	lea	0(a0,d0.w),a0
	bsr.w	dis_put_text
	rts
dis_dbcc:	; from: dis_line_5
	move.b	#$44,(a6)+
	move.b	#$42,(a6)+
	bsr.w	dis_condition
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	bsr.w	dis_put_dollar
	moveq	#0,d0
	lea	2(a4),a4
	move.w	(a4),d0
	ext.l	d0
	add.l	a4,d0
	tst.w	$43e.w                          ; flock
	beq.s	dis_dbcc_target
	subi.l	#disk_buffer,d0
dis_dbcc_target:
	bsr.w	dis_hex_long
	rts
dis_scc:	; from: dis_line_5
	move.b	#$53,(a6)+
	bsr.w	dis_condition
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_quick:	; from: dis_line_5
	move.w	(a5),d0
	lsr.w	#8,d0
	andi.w	#$1,d0
	beq.s	dis_addq
	bra.s	dis_subq
	rts

;------------------------------------------------------------------------------
; dis_size: ".B", ".W", ".L" from bits 6-7 (".?" for 3).
;------------------------------------------------------------------------------
dis_size:	; from: dis_immediate_instruction, dis_line_4, dis_size_long, dis_line_b, dis_line_c, dis_line_d, 1 more
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$3,d0
	beq.s	dis_size_byte
	cmp.w	#$1,d0
	beq.s	dis_size_word
	cmp.w	#$2,d0
	beq.s	dis_size_long
	rts

dis_size_word:	; from: dis_line_4, dis_size, dis_line_9_kind
	move.b	#$2e,(a6)+
	move.b	#$57,(a6)+
	rts

dis_size_byte:	; from: dis_line_4, dis_size
	move.b	#$2e,(a6)+
	move.b	#$42,(a6)+
	rts

dis_size_long:	; from: dis_line_4, dis_size, dis_line_9_kind
	move.b	#$2e,(a6)+
	move.b	#$4c,(a6)+
	rts
dis_size_bad:	; from: dis_line_9_kind
	move.b	#$2e,(a6)+
	move.b	#$3f,(a6)+
	rts
dis_addq:	; from: dis_condition
	lea	text_addq,a0
	bsr.w	dis_put_text
	bsr.w	dis_size
	bsr.w	dis_put_space
	bsr.w	dis_put_immediate
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bne.s	dis_addq_operands
	moveq	#8,d0
dis_addq_operands:
	bsr.w	dis_hex_byte
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_subq:	; from: dis_condition
	lea	text_subq,a0
	bsr.w	dis_put_text
	bsr.w	dis_size
	bsr.w	dis_put_space
	bsr.w	dis_put_immediate
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bne.s	dis_subq_operands
	moveq	#8,d0
dis_subq_operands:
	bsr.w	dis_hex_byte
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts

;------------------------------------------------------------------------------
; dis_line_6: line 6: BRA, BSR, Bcc, with .S for a short branch.
;------------------------------------------------------------------------------
dis_line_6:	; from: dis_lines
	move.b	#$42,(a6)+
	move.w	(a5),d0
	lsr.w	#8,d0
	andi.w	#$f,d0
	mulu.w	#$3,d0
	lea	text_ra,a0
	lea	0(a0,d0.w),a0
	bsr.w	dis_put_text
	move.w	(a5),d0
	andi.w	#$ff,d0
	bne.s	dis_bcc_short
	bsr.w	dis_put_space
	bsr.w	dis_put_dollar
	lea	2(a4),a4
	moveq	#0,d0
	move.w	(a4),d0
	ext.l	d0
	add.l	a4,d0
	tst.w	$43e.w                          ; flock
	beq.s	dis_bcc_word
	subi.l	#disk_buffer,d0
dis_bcc_word:
	bsr.w	dis_hex_long
	rts
dis_bcc_short:
	move.b	#$2e,(a6)+
	move.b	#$53,(a6)+
	bsr.w	dis_put_space
	bsr.w	dis_put_dollar
	move.w	(a5),d0
	andi.w	#$ff,d0
	ext.w	d0
	ext.l	d0
	add.l	a5,d0
	addq.l	#2,d0
	tst.w	$43e.w                          ; flock
	beq.s	dis_bcc_short_target
	subi.l	#disk_buffer,d0
dis_bcc_short_target:
	bsr.w	dis_hex_long
	rts

;------------------------------------------------------------------------------
; dis_line_7: line 7: MOVEQ.
;------------------------------------------------------------------------------
dis_line_7:	; from: dis_lines
	move.w	(a5),d0
	andi.w	#$100,d0
	bne.w	dis_line_a
	lea	text_moveq,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	bsr.w	dis_put_immediate
	move.w	(a5),d0
	andi.w	#$ff,d0
	bsr.w	dis_hex_byte
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	rts

;------------------------------------------------------------------------------
; dis_line_8: line 8: OR, DIVU, DIVS, SBCD.
;------------------------------------------------------------------------------
dis_line_8:	; from: dis_lines
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$7,d0
	cmp.w	#$5,d0
	beq.w	dis_line_8_sbcd
	cmp.w	#$6,d0
	beq.w	dis_line_8_sbcd
	cmp.w	#$2,d0
	ble.w	dis_or
	cmp.w	#$3,d0
	beq.w	dis_divu
	cmp.w	#$7,d0
	beq.w	dis_divs
	cmp.w	#$4,d0
	beq.w	dis_line_8_sbcd
	bra.w	dis_line_a
	rts
dis_divu:
	lea	text_divu,a0
	bra.w	dis_size_ea_dn
dis_divs:
	lea	text_divs,a0
	bra.w	dis_size_ea_dn
	rts
dis_sbcd:
	lea	text_sbcd,a0
	bsr.w	dis_put_text
	bra.w	dis_addx_registers
dis_or:
	lea	text_or,a0
	bra.w	dis_size_ea_dn
dis_line_8_sbcd:
	move.w	(a5),d0
	andi.w	#$f0,d0
	beq.s	dis_sbcd
	lea	text_or,a0
	bra.w	dis_size_dn_ea

;------------------------------------------------------------------------------
; dis_line_9: line 9: SUB, SUBA, SUBX.
;------------------------------------------------------------------------------
dis_line_9:	; from: dis_lines
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$7,d0
	cmp.w	#$2,d0
	ble.w	dis_sub
	cmp.w	#$4,d0
	beq.w	dis_subx
	cmp.w	#$5,d0
	beq.w	dis_subx
	cmp.w	#$6,d0
	beq.w	dis_subx
	cmp.w	#$3,d0
	beq.w	dis_suba
	cmp.w	#$7,d0
	beq.w	dis_suba

dis_line_9_kind:	; from: dis_line_d
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$7,d0
	cmp.w	#$3,d0
	beq.w	dis_size_word
	cmp.w	#$7,d0
	beq.w	dis_size_long
	bra.w	dis_size_bad
dis_suba:	; from: dis_line_9
	lea	text_suba,a0
	bra.w	dis_adda_operands
dis_subx_form:
	lea	text_subx,a0
	bra.w	dis_addx_operands
dis_sub:	; from: dis_line_9
	lea	text_sub,a0
	bra.w	dis_size_ea_dn
dis_subx:	; from: dis_line_9
	move.w	(a5),d0
	andi.w	#$30,d0
	beq.s	dis_subx_form
	lea	text_sub,a0
	bra.w	dis_size_dn_ea

;------------------------------------------------------------------------------
; dis_line_a: line A (and F): "DC.W $xxxx".
;------------------------------------------------------------------------------
dis_line_a:	; from: dis_line_0, dis_line_4, dis_line_7, dis_line_8, dis_lines
	lea	text_dc_w,a0
	bsr.w	dis_put_text
	move.w	(a5),d0
	bsr.w	dis_hex_word
	rts

;------------------------------------------------------------------------------
; dis_line_b: line B: CMP, CMPA, CMPM, EOR.
;------------------------------------------------------------------------------
dis_line_b:	; from: dis_lines
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$7,d0
	cmp.w	#$2,d0
	ble.w	dis_cmp
	cmp.w	#$3,d0
	beq.w	dis_cmpa
	cmp.w	#$7,d0
	beq.w	dis_cmpa
	bra.w	dis_line_b_eor
	rts
dis_line_b_eor:
	move.w	(a5),d0
	andi.w	#$38,d0
	cmp.w	#$8,d0
	beq.w	dis_cmpm
	lea	text_eor,a0
	bra.w	dis_size_dn_ea
dis_cmp:
	lea	text_cmp,a0
	bra.w	dis_size_ea_dn
dis_cmpa:
	lea	text_cmpa,a0
	bra.w	dis_adda_operands
dis_cmpm:
	lea	text_cmpm,a0
	bsr.w	dis_put_text
	bsr.w	dis_size
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	ori.w	#$18,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	ori.w	#$18,d0
	bsr.w	dis_ea
	rts

;------------------------------------------------------------------------------
; dis_line_c: line C: AND, MULU, MULS, ABCD, EXG.
;------------------------------------------------------------------------------
dis_line_c:	; from: dis_lines
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$7,d0
	cmp.w	#$2,d0
	ble.w	dis_and
	cmp.w	#$4,d0
	beq.w	dis_line_c_abcd
	cmp.w	#$5,d0
	beq.w	dis_line_c_and
	cmp.w	#$3,d0
	beq.w	dis_mulu
	cmp.w	#$6,d0
	beq.w	dis_line_c_and
	cmp.w	#$7,d0
	beq.w	dis_muls
	rts
dis_and:
	lea	text_and,a0
	bsr.w	dis_put_text
	bsr.w	dis_size
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$100,d0
	bne.s	dis_line_c_exg
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	rts
dis_line_c_exg:
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_line_c_abcd:
	move.w	(a5),d0
	andi.w	#$f0,d0
	bne.w	dis_and
	lea	text_abcd,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	move.w	(a5),d0
	move.w	d0,d1
	andi.w	#$7,d0
	move.w	#$0,-(sp)
	andi.w	#$8,d1
	beq.s	dis_abcd_registers
	move.w	#$20,(sp)
dis_abcd_registers:
	move.w	(sp),d1
	or.w	d1,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	move.w	(sp)+,d1
	or.w	d1,d0
	bsr.w	dis_ea
	rts
dis_line_c_and:
	move.w	(a5),d0
	andi.w	#$3f,d0
	andi.w	#$10,d0
	bne.w	dis_and
	lea	text_exg,a0
	bsr.w	dis_put_text
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	rts
dis_mulu:
	lea	text_mulu,a0
	bra.w	dis_size_ea_dn
dis_muls:
	lea	text_muls,a0
	bra.w	dis_size_ea_dn

;------------------------------------------------------------------------------
; dis_line_d: line D: ADD, ADDA, ADDX.
;------------------------------------------------------------------------------
dis_line_d:	; from: dis_lines
	move.w	(a5),d0
	lsr.w	#6,d0
	andi.w	#$7,d0
	cmp.w	#$2,d0
	ble.s	dis_add
	cmp.w	#$3,d0
	beq.w	dis_adda
	cmp.w	#$4,d0
	beq.w	dis_addx
	cmp.w	#$5,d0
	beq.w	dis_addx
	cmp.w	#$6,d0
	beq.w	dis_addx
	cmp.w	#$7,d0
	beq.w	dis_adda
	rts
dis_add:
	lea	text_add,a0
dis_size_ea_dn:	; from: dis_line_8, dis_line_9_kind, dis_line_b, dis_line_c
	bsr.w	dis_put_text
	bsr.w	dis_size
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	rts
dis_addx:
	move.w	(a5),d0
	andi.w	#$30,d0
	beq.w	dis_addx_form
	lea	text_add,a0
dis_size_dn_ea:	; from: dis_line_8, dis_line_9_kind, dis_line_b
	bsr.w	dis_put_text
	bsr.w	dis_size
	bsr.w	dis_put_space
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_addx_form:
	lea	text_addx,a0
dis_addx_operands:	; from: dis_line_9_kind
	bsr.w	dis_put_text
	bsr.w	dis_size
dis_addx_registers:	; from: dis_line_8
	bsr.w	dis_put_space
	move.w	(a5),d0
	move.w	d0,d1
	move.w	#$0,-(sp)
	andi.w	#$7,d0
	andi.w	#$8,d1
	beq.s	dis_addx_predecrement
	move.w	#$20,(sp)
dis_addx_predecrement:
	move.w	(sp),d1
	or.w	d1,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(sp)+,d1
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	or.w	d1,d0
	bsr.w	dis_ea
	rts
dis_adda:
	lea	text_adda,a0
dis_adda_operands:	; from: dis_line_9_kind, dis_line_b
	bsr.w	dis_put_text
	bsr.w	dis_line_9_kind
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	bsr.w	dis_put_comma
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	ori.w	#$8,d0
	bsr.w	dis_ea
	rts

;------------------------------------------------------------------------------
; dis_line_e: line E: the shifts and rotates (AS, LS, ROX, RO; L or R; a count, a register or memory).
;------------------------------------------------------------------------------
dis_line_e:	; from: dis_lines
	move.w	(a5),d0
	lsr.w	#3,d0
	andi.w	#$3,d0
	beq.w	dis_lsd
	cmp.w	#$1,d0
	beq.w	dis_asd
	cmp.w	#$2,d0
	beq.w	dis_roxd
	cmp.w	#$3,d0
	beq.w	dis_rod
	rts

dis_shift_direction:
	move.w	(a5),d0
	lsr.w	#8,d0
	andi.w	#$1,d0
	beq.w	dis_r
	lea	text_l,a0
	bsr.w	dis_put_text
	rts
dis_r:
	lea	text_r,a0
	bsr.w	dis_put_text
	rts
dis_asd:	; from: dis_line_e
	move.w	(a5),d0
	andi.w	#$ec0,d0
	cmp.w	#$2c0,d0
	beq.w	dis_ls
	cmp.w	#$c0,d0
	beq.w	dis_as
	cmp.w	#$6c0,d0
	beq.w	dis_ro
	cmp.w	#$4c0,d0
	beq.w	dis_rox
	lea	text_ls,a0
dis_shift_register:
	bsr.w	dis_put_text
	bsr.w	dis_shift_direction
	bsr.w	dis_size
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$20,d0
	beq.w	dis_shift_immediate
	bra.w	dis_shift_count
dis_shift_count:
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bsr.w	dis_ea
dis_shift_dy:
	bsr.w	dis_put_comma
	move.w	(a5),d0
	andi.w	#$7,d0
	bsr.w	dis_ea
	rts
dis_shift_immediate:
	move.w	(a5),d0
	lsr.w	#8,d0
	lsr.w	#1,d0
	andi.w	#$7,d0
	bne.s	dis_shift_quick
	moveq	#8,d0
dis_shift_quick:
	bsr.w	dis_put_immediate
	bsr.w	dis_hex_byte
	bra.w	dis_shift_dy
dis_ls:
	lea	text_ls,a0
dis_shift_memory:
	bsr.w	dis_put_text
	bsr.w	dis_shift_direction
	bsr.w	dis_put_space
	move.w	(a5),d0
	andi.w	#$3f,d0
	bsr.w	dis_ea
	rts
dis_roxd:	; from: dis_line_e
	move.w	(a5),d0
	andi.w	#$ec0,d0
	cmp.w	#$2c0,d0
	beq.w	dis_ls
	cmp.w	#$c0,d0
	beq.w	dis_as
	cmp.w	#$6c0,d0
	beq.w	dis_ro
	cmp.w	#$4c0,d0
	beq.w	dis_rox
	lea	text_rox,a0
	bra.w	dis_shift_register
	rts
dis_rox:
	lea	text_rox,a0
	bra.w	dis_shift_memory
dis_rod:	; from: dis_line_e
	move.w	(a5),d0
	andi.w	#$ec0,d0
	cmp.w	#$2c0,d0
	beq.w	dis_ls
	cmp.w	#$c0,d0
	beq.w	dis_as
	cmp.w	#$6c0,d0
	beq.w	dis_ro
	cmp.w	#$4c0,d0
	beq.w	dis_rox
	lea	text_ro,a0
	bra.w	dis_shift_register
	rts
dis_ro:
	lea	text_ro,a0
	bra.w	dis_shift_memory
dis_lsd:	; from: dis_line_e
	move.w	(a5),d0
	andi.w	#$ec0,d0
	cmp.w	#$2c0,d0
	beq.w	dis_ls
	cmp.w	#$c0,d0
	beq.w	dis_as
	cmp.w	#$6c0,d0
	beq.w	dis_ro
	cmp.w	#$4c0,d0
	beq.w	dis_rox
	lea	text_as,a0
	bra.w	dis_shift_register
dis_as:
	lea	text_as,a0
	bra.w	dis_shift_memory

;------------------------------------------------------------------------------
; dis_end: (nothing more).
;------------------------------------------------------------------------------
dis_end:	; from: disassemble_buffer, save_source_text, disassemble_memory, disassemble_lines
	rts

;------------------------------------------------------------------------------
; dis_hex_byte, dis_hex_word, dis_hex_long: d0 in hex at a6 without leading zeros ('0' for 0).
;------------------------------------------------------------------------------
dis_hex_byte:                                   ; from: dis_ea, dis_ea_indirect, dis_bit_static, dis_immediate_operand,
                                                ;   dis_immediate_instruction, dis_register_list, 3 more
	tst.b	d0
	beq.w	dis_hex_zero
	move.l	d7,-(sp)
	moveq	#0,d7
	bsr.w	dis_hex_digits
	move.l	(sp)+,d7
	rts

dis_hex_digits:	; from: dis_hex_byte, dis_hex_word_digits
	movem.l	d0-d1/a0,-(sp)
	move.w	d0,d1
	andi.w	#$f0,d1
	lsr.w	#4,d1
	andi.w	#$f,d0
	lea	dis_hex_digits_text,a0
	tst.w	d7
	bne.s	dis_hex_digit_put
	tst.w	d1
	beq.s	dis_hex_digit_next
dis_hex_digit_put:
	moveq	#1,d7
	move.b	0(a0,d1.w),(a6)+
dis_hex_digit_next:
	tst.w	d7
	bne.s	dis_hex_digit_last
	tst.w	d0
	beq.s	dis_hex_digits_done
dis_hex_digit_last:
	moveq	#1,d7
	move.b	0(a0,d0.w),(a6)+
dis_hex_digits_done:
	movem.l	(sp)+,d0-d1/a0
	rts

dis_hex_word_digits:	; from: dis_hex_word, dis_hex_long
	movem.l	d0-d1,-(sp)
	move.w	d0,d1
	lsr.w	#8,d0
	bsr.w	dis_hex_digits
	move.w	d1,d0
	bsr.w	dis_hex_digits
	movem.l	(sp)+,d0-d1
	rts

dis_hex_word:                                   ; from: dis_ea, dis_ea_indirect, dis_immediate_operand,
                                                ;   dis_immediate_instruction, dis_line_4, dis_register_list, 1 more
	tst.w	d0
	beq.s	dis_hex_zero
	move.l	d7,-(sp)
	moveq	#0,d7
	bsr.w	dis_hex_word_digits
	move.l	(sp)+,d7
	rts

dis_hex_long:	; from: dis_ea, dis_immediate_operand, dis_condition, dis_line_6
	tst.l	d0
	beq.s	dis_hex_zero
	movem.l	d0/d7,-(sp)
	moveq	#0,d7
	swap	d0
	bsr.w	dis_hex_word_digits
	swap	d0
	bsr.w	dis_hex_word_digits
	movem.l	(sp)+,d0/d7
	rts
dis_hex_zero:	; from: dis_hex_byte, dis_hex_word
	move.b	#$30,(a6)+
	rts
dis_lines:
	dc.l	dis_line_0
	dc.l	dis_line_1
	dc.l	dis_line_2
	dc.l	dis_line_3
	dc.l	dis_line_4
	dc.l	dis_line_5
	dc.l	dis_line_6
	dc.l	dis_line_7
	dc.l	dis_line_8
	dc.l	dis_line_9
	dc.l	dis_line_a
	dc.l	dis_line_b
	dc.l	dis_line_c
	dc.l	dis_line_d
	dc.l	dis_line_e
	dc.l	dis_line_a

;------------------------------------------------------------------------------
; dis_hex_digits_text and the rest: the names and characters the disassembler puts in.
;------------------------------------------------------------------------------
dis_hex_digits_text:	; from: dis_hex_digits
	dc.b	'0123456789ABCDEF',0
	dc.b	$23,$00,$24,$00,$28,$00,$29,$00,$2b,$00,$2d,$00,$2c,$00
dis_data_registers:	; from: dis_ea, dis_ea_indirect
	dc.b	$44,$30,$00,$44,$31,$00,$44,$32,$00,$44,$33,$00,$44,$34,$00,$44
	dc.b	$35,$00,$44,$36,$00,$44,$37,$00
dis_address_registers:	; from: dis_ea_indirect
	dc.b	$41,$30,$00,$41,$31,$00,$41,$32,$00,$41,$33,$00,$41,$34,$00,$41
	dc.b	$35,$00,$41,$36,$00,$41,$37,$00
dis_pc_text:	; from: dis_put_pc, dis_ea
	dc.b	$50,$43,$00
text_sr:	; from: dis_immediate_instruction, dis_line_4
	dc.w	$5352
	dc.b	$00
text_usp:	; from: dis_line_4
	dc.b	'USP',0
text_ccr:	; from: dis_immediate_instruction, dis_line_4
	dc.b	'CCR',0
dis_conditions:	; from: dis_condition
	dc.b	$54,$00,$00,$46,$00,$00,$48,$49,$00,$4c,$53,$00,$43,$43,$00,$43
	dc.b	$53,$00,$4e,$45,$00,$45,$51,$00,$56,$43,$00,$56,$53,$00,$50,$4c
	dc.b	$00,$4d,$49,$00,$47,$45,$00,$4c,$54,$00,$47,$54,$00,$4c,$45,$00
text_ra:	; from: dis_line_6
	dc.b	$52,$41,$00,$53,$52,$00,$48,$49,$00,$4c,$53,$00,$43,$43,$00,$43
	dc.b	$53,$00,$4e,$45,$00,$45,$51,$00,$56,$43,$00,$56,$53,$00,$50,$4c
	dc.b	$00,$4d,$49,$00,$47,$45,$00,$4c,$54,$00,$47,$54,$00,$4c,$45,$00
text_b:	; from: dis_line_1
	dc.b	$2e,$42,$00
dis_word_text:	; from: dis_ea, dis_ea_indirect, dis_line_1
	dc.w	$2e57
	dc.b	$00
dis_long_text:	; from: dis_ea, dis_ea_indirect, dis_line_1
	dc.b	$2e,$4c,$00,$2e,$53,$00
text_dc_w:	; from: dis_line_a
	dc.b	'DC.W $',0
text_abcd:	; from: dis_line_c
	dc.b	'ABCD',0
text_add:	; from: dis_line_d
	dc.b	'ADD',0
text_adda:	; from: dis_line_d
	dc.b	'ADDA',0
text_addi:	; from: dis_immediate_operand
	dc.b	'ADDI',0
text_addq:	; from: dis_size_long
	dc.b	'ADDQ',0
text_addx:	; from: dis_line_d
	dc.b	'ADDX',0
text_and:	; from: dis_line_c
	dc.b	'AND',0
text_andi:	; from: dis_immediate_instruction
	dc.b	'ANDI',0
text_as:	; from: dis_shift_direction
	dc.w	$4153,$0042
	dc.b	$00
text_bchg:	; from: dis_bit_static, dis_bset_dynamic
	dc.b	'BCHG',0
text_bclr:	; from: dis_bit_static, dis_bset_dynamic
	dc.b	'BCLR',0
	dc.b	'BRA',0
text_bset:	; from: dis_bit_static, dis_bset_dynamic
	dc.b	'BSET',0
	dc.b	'BSR',0
text_btst:	; from: dis_bit_static, dis_bset_dynamic
	dc.b	'BTST',0
text_chk:	; from: dis_line_4
	dc.b	'CHK',0
text_clr:	; from: dis_line_4
	dc.b	'CLR',0
text_cmp:	; from: dis_line_b
	dc.b	'CMP',0
text_cmpa:	; from: dis_line_b
	dc.b	'CMPA',0
text_cmpi:	; from: dis_immediate_instruction
	dc.b	'CMPI',0
text_cmpm:	; from: dis_line_b
	dc.b	'CMPM',0
	dc.w	$4442
	dc.b	$00
text_divs:	; from: dis_line_8
	dc.b	'DIVS',0
text_divu:	; from: dis_line_8
	dc.b	'DIVU',0
text_eor:	; from: dis_line_b
	dc.b	'EOR',0
text_eori:	; from: dis_immediate_instruction
	dc.b	'EORI',0
text_exg:	; from: dis_line_c
	dc.b	'EXG',0
text_ext:	; from: dis_line_4
	dc.b	'EXT',0
text_illegal:	; from: dis_line_4
	dc.b	'ILLEGAL',0
text_jmp:	; from: dis_line_4
	dc.b	'JMP',0
text_jsr:	; from: dis_line_4
	dc.b	'JSR',0
text_lea:	; from: dis_line_4
	dc.b	'LEA',0
text_link:	; from: dis_line_4
	dc.b	'LINK',0
text_ls:	; from: dis_shift_direction
	dc.b	$4c,$53,$00
text_move:	; from: dis_line_1, dis_line_4
	dc.b	'MOVE',0
	dc.b	'MOVEA',0
text_movem:	; from: dis_line_4
	dc.b	'MOVEM',0
text_movep:	; from: dis_movep
	dc.b	'MOVEP',0
text_moveq:	; from: dis_line_7
	dc.b	'MOVEQ',0
text_muls:	; from: dis_line_c
	dc.b	'MULS',0
text_mulu:	; from: dis_line_c
	dc.b	'MULU',0
text_nbcd:	; from: dis_line_4
	dc.b	'NBCD',0
text_neg:	; from: dis_line_4
	dc.b	'NEG',0
text_negx:	; from: dis_line_4
	dc.b	'NEGX',0
text_nop:	; from: dis_register_list
	dc.b	'NOP',0
text_not:	; from: dis_line_4
	dc.b	'NOT',0
text_or:	; from: dis_line_8
	dc.b	$4f,$52,$00
text_ori:	; from: dis_immediate_instruction
	dc.b	'ORI',0
text_pea:	; from: dis_line_4
	dc.b	'PEA',0
text_reset:	; from: dis_register_list
	dc.b	'RESET',0
text_ro:	; from: dis_shift_direction
	dc.w	$524f
	dc.b	$00
text_rox:	; from: dis_shift_direction
	dc.b	'ROX',0
text_rte:	; from: dis_register_list
	dc.b	'RTE',0
text_rtr:	; from: dis_register_list
	dc.b	'RTR',0
text_rts:	; from: dis_register_list
	dc.b	'RTS',0
text_sbcd:	; from: dis_line_8
	dc.b	'SBCD',0
	dc.w	$5300
text_stop:	; from: dis_register_list
	dc.b	'STOP',0
text_sub:	; from: dis_line_9_kind
	dc.b	'SUB',0
text_suba:	; from: dis_line_9_kind
	dc.b	'SUBA',0
text_subi:	; from: dis_immediate_instruction
	dc.b	'SUBI',0
text_subq:	; from: dis_size_long
	dc.b	'SUBQ',0
text_subx:	; from: dis_line_9_kind
	dc.b	'SUBX',0
text_swap:	; from: dis_line_4
	dc.b	'SWAP',0
text_tas:	; from: dis_line_4
	dc.b	'TAS',0
text_trap:	; from: dis_register_list
	dc.b	'TRAP',0
text_trapv:	; from: dis_register_list
	dc.b	'TRAPV',0
text_tst:	; from: dis_line_4
	dc.b	'TST',0
text_unlk:	; from: dis_line_4
	dc.b	'UNLK',0
text_r:	; from: dis_shift_direction
	dc.w	$5200
text_l:	; from: dis_shift_direction
	dc.w	$4c00

;------------------------------------------------------------------------------
; escape_watch: a VBL routine (vblqueue): ESC pressed sets search_stop, which ends a search.
;------------------------------------------------------------------------------
escape_watch:	; from: ripper
	move.l	#raster_colours,raster_pointer
	cmpi.b	#$1,$fffffc02.w                 ; keyboard ACIA data, ESC?
	bne.s	escape_watch_done               ; no
	move.w	#$ffff,search_stop              ; stop
escape_watch_done:
	rts

;------------------------------------------------------------------------------
; copy_memory (F7): "START ADDRESS : $", "END ADDRESS : $", "COPY ADDRESS : $": the bytes copied, from the end
; when the copy overlaps forward.
;------------------------------------------------------------------------------
copy_memory:	; from: memory_ripper
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.s	copy_memory_done                ; no
	move.l	d2,range_start                  ; the start
	lea	text_end_address,a0             ; "END ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.s	copy_memory_done                ; no
	move.l	d2,range_end                    ; the end
	lea	text_copy_address,a0            ; "COPY ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.s	copy_memory_done                ; no
	move.l	d2,copy_destination             ; the destination
	movea.l	range_start,a0
	movea.l	range_end,a1
	cmpa.l	a1,a0                           ; the start before the end?
	bge.s	copy_memory_done                ; no
	movea.l	copy_destination,a2
	cmpa.l	a0,a2                           ; above the start?
	bgt.s	copy_memory_overlap             ; yes
	bra.s	copy_memory_forward             ; no: forward
copy_memory_done:
	rts
copy_memory_overlap:
	cmpa.l	a1,a2                           ; past the end?
	bge.s	copy_memory_forward             ; yes: forward
	move.l	a1,d0
	sub.l	a0,d0                           ; the length
	adda.l	d0,a2                           ; the destination's end
copy_memory_back:
	subq.l	#1,a1
	subq.l	#1,a2
	move.b	(a1),(a2)                       ; copied
	cmpa.l	a1,a0                           ; the start?
	bne.s	copy_memory_back                ; no
	rts
copy_memory_forward:
	move.b	(a0),(a2)                       ; copied
	addq.l	#1,a2
	addq.l	#1,a0
	cmpa.l	a1,a0                           ; the end?
	bne.s	copy_memory_forward             ; no
	rts

;------------------------------------------------------------------------------
; edit_memory (F6): the hex dump edited in place, as edit_buffer does for the disk buffer.
;------------------------------------------------------------------------------
edit_memory:	; from: memory_ripper
	move.b	#$23,edit_cursor_text+2         ; row 3
	move.b	#$2b,edit_cursor_text+3         ; column 11
edit_memory_hex:
	lea	edit_cursor_text,a0             ; the cursor placed
	bsr.w	print
edit_memory_hex_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; escape?
	beq.s	edit_memory_done                ; yes
	cmp.b	#$9,d0                          ; TAB?
	beq.s	edit_memory_to_chars            ; the characters
	swap	d0
	cmp.b	#$50,d0                         ; down?
	beq.w	edit_memory_hex_down
	cmp.b	#$48,d0                         ; up?
	beq.w	edit_memory_hex_up
	cmp.b	#$4b,d0                         ; left?
	beq.w	edit_memory_hex_left
	cmp.b	#$4d,d0                         ; right?
	beq.w	edit_memory_hex_right
	swap	d0
	cmp.w	#$20,d0                         ; a character?
	bge.w	edit_memory_digit               ; a digit
	bra.s	edit_memory_hex_key
edit_memory_done:
	rts
edit_memory_to_chars:
	moveq	#0,d0
	move.b	edit_cursor_text+3,d0
	subi.b	#$2b,d0
	divu.w	#$3,d0                          ; / 3: the byte
	addi.b	#$5d,d0                         ; its character column
	move.b	d0,edit_cursor_text+3
edit_memory_chars:
	lea	edit_cursor_text,a0             ; the cursor placed
	bsr.w	print
edit_memory_chars_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; escape?
	beq.s	edit_memory_done                ; yes
	cmp.b	#$9,d0                          ; TAB?
	beq.w	edit_memory_to_hex              ; the hex
	swap	d0
	cmp.b	#$50,d0                         ; down?
	beq.w	edit_memory_chars_down
	cmp.b	#$48,d0                         ; up?
	beq.w	edit_memory_chars_up
	cmp.b	#$4b,d0                         ; left?
	beq.w	edit_memory_chars_left
	cmp.b	#$4d,d0                         ; right?
	beq.w	edit_memory_chars_right
	swap	d0
	cmp.w	#$20,d0                         ; a character?
	bge.w	edit_memory_char                ; yes
	bra.s	edit_memory_chars_key
	rts                                     ; (not reached)
edit_memory_char:
	move.w	d0,d6                           ; the character
	move.l	a0,-(sp)
	lea	input_buffer+2,a0
	move.b	d0,(a0)
	clr.b	1(a0)                           ; ended
	bsr.w	print                           ; shown
	movea.l	(sp)+,a0
	movea.l	memory_address,a6               ; the address
	moveq	#0,d1
	move.b	edit_cursor_text+3,d1           ; the column
	subi.w	#$5d,d1
	adda.w	d1,a6
	move.b	edit_cursor_text+2,d1           ; the row
	subi.w	#$23,d1
	mulu.w	#$10,d1                         ; 16 bytes a row
	adda.w	d1,a6
	move.b	d6,(a6)                         ; written
	nop
	nop
	cmpi.b	#$6c,edit_cursor_text+3         ; the last column?
	beq.w	edit_memory_char_wrap           ; yes
	addq.b	#1,edit_cursor_text+3           ; right
	bra.w	edit_memory_chars
edit_memory_char_wrap:
	move.b	#$5d,edit_cursor_text+3         ; the first column
	cmpi.b	#$36,edit_cursor_text+2         ; the last row?
	beq.s	edit_memory_char_top            ; yes
	addq.b	#1,edit_cursor_text+2           ; down
	bra.w	edit_memory_chars
edit_memory_char_top:
	move.b	#$23,edit_cursor_text+2         ; the first row
	bra.w	edit_memory_chars
edit_memory_digit:
	lea	hex_digit_pairs,a0              ; the hex digits
edit_memory_digit_find:
	cmp.b	(a0),d0                         ; this one?
	beq.s	edit_memory_digit_high          ; yes
	addq.l	#2,a0
	tst.b	(a0)                            ; the table's end?
	bge.s	edit_memory_digit_find          ; no
	bra.w	edit_memory_hex                 ; not a digit
edit_memory_digit_high:
	cmp.b	#$61,d0                         ; small?
	blt.s	edit_memory_digit_show          ; no
	subi.b	#$20,d0                         ; in capitals
edit_memory_digit_show:
	move.l	a0,-(sp)
	lea	input_buffer+2,a0
	move.b	d0,(a0)
	clr.b	1(a0)                           ; ended
	bsr.w	print                           ; shown
	movea.l	(sp)+,a0
	move.b	1(a0),d0                        ; its value
	movea.l	memory_address,a6               ; the address
	moveq	#0,d1
	move.b	edit_cursor_text+3,d1           ; the column
	subi.w	#$2b,d1
	divu.w	#$3,d1                          ; / 3: the byte
	adda.w	d1,a6
	move.b	edit_cursor_text+2,d1           ; the row
	subi.w	#$23,d1
	mulu.w	#$10,d1                         ; 16 bytes a row
	adda.w	d1,a6
	lsl.w	#4,d0                           ; the high nibble
	andi.b	#$f,(a6)
	or.b	d0,(a6)                         ; set
	bsr.w	get_key                         ; the second digit
	lea	hex_digit_pairs,a0
edit_memory_digit_low_find:
	cmp.b	(a0),d0                         ; this one?
	beq.s	edit_memory_digit_low           ; yes
	addq.l	#2,a0
	tst.b	(a0)                            ; the table's end?
	bge.s	edit_memory_digit_low_find      ; no
	bra.w	edit_memory_hex                 ; not a digit
edit_memory_digit_low:
	cmp.b	#$61,d0                         ; small?
	blt.s	edit_memory_digit_low_show      ; no
	subi.b	#$20,d0                         ; in capitals
edit_memory_digit_low_show:
	move.l	a0,-(sp)
	lea	input_buffer+2,a0
	move.b	d0,(a0)
	clr.b	1(a0)                           ; ended
	bsr.w	print                           ; shown
	movea.l	(sp)+,a0
	move.b	1(a0),d0                        ; its value
	movea.l	memory_address,a6               ; the address
	moveq	#0,d1
	move.b	edit_cursor_text+3,d1
	subi.w	#$2b,d1
	divu.w	#$3,d1
	adda.w	d1,a6
	move.b	edit_cursor_text+2,d1
	subi.w	#$23,d1
	mulu.w	#$10,d1
	adda.w	d1,a6
	andi.b	#$f0,(a6)                       ; the low nibble
	or.b	d0,(a6)                         ; set
	move.b	edit_cursor_text+3,d1
	cmpi.b	#$58,edit_cursor_text+3         ; the last byte?
	beq.w	edit_memory_digit_wrap          ; yes
	addq.b	#3,edit_cursor_text+3           ; a byte right
	bra.w	edit_memory_hex
edit_memory_digit_wrap:
	move.b	#$2b,edit_cursor_text+3         ; the first byte
	cmpi.b	#$36,edit_cursor_text+2         ; the last row?
	beq.s	edit_memory_digit_top           ; yes
	addq.b	#1,edit_cursor_text+2           ; down
	bra.w	edit_memory_hex
edit_memory_digit_top:
	move.b	#$23,edit_cursor_text+2         ; the first row
	bra.w	edit_memory_hex
edit_memory_to_hex:
	moveq	#0,d0
	move.b	edit_cursor_text+3,d0
	subi.w	#$5d,d0
	mulu.w	#$3,d0                          ; * 3
	addi.b	#$2b,d0                         ; the hex column
	move.b	d0,edit_cursor_text+3
	bra.w	edit_memory_hex
edit_memory_hex_right:
	cmpi.b	#$58,edit_cursor_text+3         ; the last byte?
	beq.s	edit_memory_hex_wrap_right      ; yes
	addq.b	#3,edit_cursor_text+3           ; a byte right
	bra.w	edit_memory_hex
edit_memory_hex_wrap_right:
	move.b	#$2b,edit_cursor_text+3         ; the first byte
	bra.w	edit_memory_hex_down            ; and down
edit_memory_hex_left:
	cmpi.b	#$2b,edit_cursor_text+3         ; the first byte?
	beq.s	edit_memory_hex_wrap_left       ; yes
	subq.b	#3,edit_cursor_text+3           ; a byte left
	bra.w	edit_memory_hex
edit_memory_hex_wrap_left:
	move.b	#$58,edit_cursor_text+3         ; the last byte
	bra.w	edit_memory_hex_up              ; and up
edit_memory_hex_up:
	cmpi.b	#$23,edit_cursor_text+2         ; the first row?
	beq.s	edit_memory_hex_wrap_up         ; yes
	subq.b	#1,edit_cursor_text+2           ; up
	bra.w	edit_memory_hex
edit_memory_hex_wrap_up:
	move.b	#$36,edit_cursor_text+2         ; the last row
	bra.w	edit_memory_hex
edit_memory_hex_down:
	cmpi.b	#$36,edit_cursor_text+2         ; the last row?
	beq.s	edit_memory_hex_wrap_down       ; yes
	addq.b	#1,edit_cursor_text+2           ; down
	bra.w	edit_memory_hex
edit_memory_hex_wrap_down:
	move.b	#$23,edit_cursor_text+2         ; the first row
	bra.w	edit_memory_hex
edit_memory_chars_right:
	cmpi.b	#$6c,edit_cursor_text+3         ; the last column?
	beq.s	edit_memory_chars_wrap_right    ; yes
	addq.b	#1,edit_cursor_text+3           ; right
	bra.w	edit_memory_chars
edit_memory_chars_wrap_right:
	move.b	#$5d,edit_cursor_text+3         ; the first column
	bra.w	edit_memory_chars_down          ; and down
edit_memory_chars_left:
	cmpi.b	#$5d,edit_cursor_text+3         ; the first column?
	beq.s	edit_memory_chars_wrap_left     ; yes
	subq.b	#1,edit_cursor_text+3           ; left
	bra.w	edit_memory_chars
edit_memory_chars_wrap_left:
	move.b	#$6c,edit_cursor_text+3         ; the last column
	bra.w	edit_memory_chars_up            ; and up
edit_memory_chars_up:
	cmpi.b	#$23,edit_cursor_text+2         ; the first row?
	beq.s	edit_memory_chars_wrap_up       ; yes
	subq.b	#1,edit_cursor_text+2           ; up
	bra.w	edit_memory_chars
edit_memory_chars_wrap_up:
	move.b	#$36,edit_cursor_text+2         ; the last row
	bra.w	edit_memory_chars
edit_memory_chars_down:
	cmpi.b	#$36,edit_cursor_text+2         ; the last row?
	beq.s	edit_memory_chars_wrap_down     ; yes
	addq.b	#1,edit_cursor_text+2           ; down
	bra.w	edit_memory_chars
edit_memory_chars_wrap_down:
	move.b	#$23,edit_cursor_text+2         ; the first row
	bra.w	edit_memory_chars

;------------------------------------------------------------------------------
; search_memory (F4): "(B)yte (W)ord (L)ong (T)ext ?", the value, then the memory searched from the address
; (words and longs on even addresses); the search has no end: it stops when found or at ESC (escape_watch).
;------------------------------------------------------------------------------
search_memory:	; from: memory_ripper
	lea	text_b_yte_w,a0                 ; the question
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$62,d0                         ; 'b'?
	bne.s	search_memory_b                 ; no
	move.w	#$200,input_buffer              ; 2 digits
	bra.w	search_memory_byte
search_memory_b:
	cmp.b	#$42,d0                         ; 'B'?
	bne.s	search_memory_w                 ; no
	move.w	#$200,input_buffer              ; 2 digits
	bra.w	search_memory_byte
search_memory_w:
	cmp.b	#$77,d0                         ; 'w'?
	bne.s	search_memory_word_key          ; no
	move.w	#$400,input_buffer              ; 4 digits
	bra.w	search_memory_word
search_memory_word_key:
	cmp.b	#$57,d0                         ; 'W'?
	bne.s	search_memory_l                 ; no
	move.w	#$400,input_buffer              ; 4 digits
	bra.w	search_memory_word
search_memory_l:
	cmp.b	#$6c,d0                         ; 'l'?
	bne.s	search_memory_long_key          ; no
	move.w	#$800,input_buffer              ; 8 digits
	bra.w	search_memory_long
search_memory_long_key:
	cmp.b	#$4c,d0                         ; 'L'?
	bne.s	search_memory_t                 ; no
	move.w	#$800,input_buffer              ; 8 digits
	bra.w	search_memory_long
search_memory_t:
	cmp.b	#$74,d0                         ; 't'?
	bne.s	search_memory_text_key          ; no
	move.w	#$2000,input_buffer             ; 32 characters
	bra.s	search_memory_text
search_memory_text_key:
	cmp.b	#$54,d0                         ; 'T'?
	bne.s	search_memory_done              ; no
	move.w	#$2000,input_buffer             ; 32 characters
	bra.s	search_memory_text
search_memory_done:
	rts
search_memory_text:
	lea	text_text_to_find,a0            ; "TEXT TO FIND :  "
	bsr.w	print
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.w	d0                              ; any?
	beq.s	search_memory_found             ; no
	subq.w	#1,d0                           ; for dbra
search_text:	; from: search_again
	movem.l	d0-d7/a0-a6,-(sp)
	lea	text_searching_at_dfd1,a0       ; "SEARCHING ..."
	bsr.w	print
	movem.l	(sp)+,d0-d7/a0-a6
	move.w	#$54,last_search_kind           ; text ('T')
	lea	input_buffer+2,a0               ; the text
	lea	last_search_value,a1            ; kept for search_again
	move.b	d0,(a1)+                        ; its length
search_text_keep:
	move.b	(a0)+,(a1)+
	bne.s	search_text_keep
	clr.w	search_stop                     ; not stopped
	movea.l	memory_address,a6               ; the address
	subq.l	#1,a6
search_text_next:
	tst.w	search_stop                     ; stopped?
	bmi.s	search_memory_found             ; yes
	move.w	d0,d1
	lea	input_buffer+2,a0               ; the text
	addq.l	#1,a6                           ; on
search_text_compare:
	move.b	(a0),d2
	cmp.b	(a6),d2                         ; the same?
	bne.s	search_text_next                ; no
	addq.l	#1,a6
	addq.l	#1,a0
	dbra	d1,search_text_compare          ; all?
	suba.w	d0,a6                           ; back to its start
	subq.l	#1,a6
search_memory_found:
	move.l	a6,memory_address               ; the address
	rts
search_memory_byte:
	lea	text_data_to_find,a0            ; "DATA TO FIND : $"
	bsr.w	print
	bsr.w	input_hex                       ; the value
	tst.l	d0                              ; given?
	bmi.w	search_memory_done              ; no
search_byte:	; from: search_again
	lea	text_searching_at_dfd1,a0       ; "SEARCHING ..."
	bsr.w	print
	move.l	d2,search_value
	move.w	#$4f,last_search_kind           ; byte ('O')
	move.l	d2,last_search_value            ; kept for search_again
	move.b	search_value+3,d0               ; the byte
	movea.l	memory_address,a6               ; the address
	clr.w	search_stop                     ; not stopped
search_byte_next:
	tst.w	search_stop                     ; stopped?
	bmi.s	search_byte_found               ; yes
	cmp.b	(a6)+,d0                        ; found?
	bne.s	search_byte_next                ; no
search_byte_found:
	subq.l	#1,a6
	move.l	a6,memory_address               ; the address
	rts
search_memory_word:
	lea	text_data_to_find,a0            ; "DATA TO FIND : $"
	bsr.w	print
	bsr.w	input_hex                       ; the value
	tst.l	d0                              ; given?
	bmi.w	search_memory_done              ; no
search_word:	; from: search_again
	lea	text_searching_at_dfd1,a0       ; "SEARCHING ..."
	bsr.w	print
	move.l	d2,search_value
	move.w	search_value+2,d0               ; the word
	move.w	#$4d,last_search_kind           ; word ('M')
	move.l	d2,last_search_value            ; kept for search_again
	move.l	memory_address,d1               ; the address
	andi.l	#$fffffffe,d1                   ; even
	movea.l	d1,a6
	clr.w	search_stop                     ; not stopped
search_word_next:
	tst.w	search_stop                     ; stopped?
	bmi.s	search_word_found               ; yes
	cmp.w	(a6)+,d0                        ; found?
	bne.s	search_word_next                ; no
search_word_found:
	subq.l	#2,a6
	move.l	a6,memory_address               ; the address
	rts
search_memory_long:
	lea	text_data_to_find,a0            ; "DATA TO FIND : $"
	bsr.w	print
	bsr.w	input_hex                       ; the value
	tst.l	d0                              ; given?
	bmi.w	search_memory_done              ; no
search_long:	; from: search_again
	lea	text_searching_at_dfd1,a0       ; "SEARCHING ..."
	bsr.w	print
	move.l	d2,search_value
	move.l	search_value,d0                 ; the long
	move.w	#$4c,last_search_kind           ; long ('L')
	move.l	d2,last_search_value            ; kept for search_again
	move.l	memory_address,d1               ; the address
	andi.l	#$fffffffe,d1                   ; even
	movea.l	d1,a6
	move.w	d0,d1                           ; its low word
	swap	d0                              ; its high word
	clr.w	search_stop                     ; not stopped
search_long_next:
	tst.w	search_stop                     ; stopped?
	bmi.s	search_long_found               ; yes
	cmp.w	(a6)+,d0                        ; the high word?
	bne.s	search_long_next                ; no
	cmp.w	(a6)+,d1                        ; the low word?
	bne.s	search_long_next                ; no
search_long_found:
	subq.l	#4,a6
	move.l	a6,memory_address               ; the address
	rts

;------------------------------------------------------------------------------
; fill_memory (F5): "START ADDRESS : $", "END ADDRESS : $", "(H)exa (T)ext ?", then the memory filled with the
; text or the hex bytes over and over up to the end (ESC stops it).
;------------------------------------------------------------------------------
fill_memory:	; from: memory_ripper
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	fill_memory_done                ; no
	move.l	d2,range_start                  ; the start
	lea	text_end_address,a0             ; "END ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	fill_memory_done                ; no
	move.l	d2,range_end                    ; the end
	move.l	range_start,d0
	sub.l	d2,d0                           ; before the end?
	bge.w	fill_memory_done                ; no
	lea	text_h_exa_t,a0                 ; "(H)exa (T)ext ?"
	bsr.w	print
	bsr.w	get_key                         ; a key
	cmp.b	#$68,d0                         ; 'h'?
	beq.s	fill_memory_hex
	cmp.b	#$48,d0                         ; 'H'?
	beq.s	fill_memory_hex
	cmp.b	#$74,d0                         ; 't'?
	beq.s	fill_memory_text
	cmp.b	#$54,d0                         ; 'T'?
	bne.s	fill_memory_done                ; no
fill_memory_text:
	move.w	#$2000,input_buffer             ; 32 characters
	lea	text_text_to_fill,a0            ; "TEXT TO FILL : "
	bsr.w	print
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	beq.s	fill_memory_done                ; no
	subq.w	#1,d0                           ; for dbra
	clr.w	search_stop                     ; not stopped
	movea.l	range_start,a2                  ; the start
	movea.l	range_end,a3                    ; the end
fill_memory_text_again:
	tst.w	search_stop                     ; stopped?
	bmi.s	fill_memory_done                ; yes
	move.w	d0,d1
	lea	input_buffer+2,a0               ; the text
fill_memory_text_byte:
	move.b	(a0),(a2)                       ; put
	addq.l	#1,a0
	addq.l	#1,a2
	cmpa.l	a3,a2                           ; the end?
	beq.s	fill_memory_done                ; yes
	dbra	d1,fill_memory_text_byte
	bra.s	fill_memory_text_again          ; again
fill_memory_done:
	rts
fill_memory_hex:
	move.w	#$800,input_buffer              ; 8 digits
	lea	text_data_to_fill,a0            ; "DATA TO FILL : $"
	bsr.w	print
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	beq.s	fill_memory_done                ; no
	move.l	d0,-(sp)
	bsr.w	hex_from_input                  ; the value
	tst.l	d0                              ; bad?
	bmi.s	fill_memory_done                ; yes
	move.l	(sp)+,d0                        ; the count
	addq.w	#1,d0
	lsr.w	#1,d0                           ; bytes
	lea	fill_bytes,a0                   ; the bytes' end
	adda.w	d0,a0
	subq.l	#1,d0
	move.w	d0,d1
fill_memory_hex_byte:
	move.b	d2,-(a0)                        ; into bytes
	lsr.l	#8,d2
	dbra	d1,fill_memory_hex_byte
	movea.l	range_start,a1                  ; the start
	movea.l	range_end,a2                    ; the end
	clr.w	search_stop                     ; not stopped
fill_memory_hex_again:
	tst.w	search_stop                     ; stopped?
	bmi.s	fill_memory_done                ; yes
	move.w	d0,d1
	lea	fill_bytes,a0                   ; the bytes
fill_memory_hex_put:
	move.b	(a0),(a1)                       ; put
	addq.l	#1,a0
	addq.l	#1,a1
	cmpa.l	a2,a1                           ; the end?
	beq.s	fill_memory_done                ; yes
	dbra	d1,fill_memory_hex_put
	bra.s	fill_memory_hex_again           ; again
	rts                                     ; (not reached)

;------------------------------------------------------------------------------
; get_key: a key (Crawcin) with Shift/Alternate state in the high byte (conterm bit 1 for the moment).
; Shift Home, Shift Insert and Shift Undo come back as cursor keys.
;------------------------------------------------------------------------------
get_key:	; from: main_menu, calculator, disk_ripper, buffer_memory_menu, print_buffer, edit_buffer, 28 more
	bset	#$1,$484.w                      ; conterm, Shift state in the return
	move.w	#$7,-(sp)
	trap	#1                              ; Crawcin
	addq.l	#2,sp
	bclr	#$1,$484.w                      ; conterm
	cmp.l	#$470000,d0                     ; Shift Home?
	bne.s	get_key_insert                  ; no
	move.l	#$4d0036,d0                     ; as right
get_key_insert:
	cmp.l	#$520000,d0                     ; Shift Insert?
	bne.s	get_key_undo                    ; no
	move.l	#$4b0034,d0                     ; as left
get_key_undo:
	cmp.l	#$620000,d0                     ; Shift Undo?
	bne.s	get_key_done                    ; no
	move.l	#$480038,d0                     ; as down
get_key_done:
	rts

;------------------------------------------------------------------------------
; wait_key: a key (Crawcin).
;------------------------------------------------------------------------------
wait_key:	; from: sample_ripper, sample_controls, sample_play
	move.w	#$7,-(sp)
	trap	#1                              ; Crawcin
	addq.l	#2,sp
	rts

;------------------------------------------------------------------------------
; input_hex_long: up to 8 hex digits typed (input_hex with the length 8): d2 the value, d0 0 or -1.
;------------------------------------------------------------------------------
input_hex_long:	; from: external_call, sample_set_start, sample_set_end, sample_save, music_save, music_search, 8 more
	move.w	#$800,input_buffer              ; 8 characters

;------------------------------------------------------------------------------
; input_hex: hex digits typed into input_buffer: d2 the value, d0 0 or -1 (escape, nothing, or a bad digit).
;------------------------------------------------------------------------------
input_hex:	; from: set_track, set_sector, search_memory, external_loader
	pea	input_buffer                    ; the buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.w	d0                              ; none?
	beq.s	hex_from_input_bad              ; yes: -1

;------------------------------------------------------------------------------
; hex_from_input: d0 characters of input_buffer as hex into d2.
;------------------------------------------------------------------------------
hex_from_input:	; from: buffer_memory_menu, fill_memory
	lea	input_buffer+2,a0               ; the characters
	subq.w	#1,d0                           ; for dbra
	clr.l	d2                              ; the value
hex_from_input_char:
	lea	hex_digit_pairs,a1              ; the digits table
	move.b	(a0)+,d1                        ; the character
hex_from_input_find:
	cmp.b	(a1),d1                         ; this digit?
	bne.s	hex_from_input_next             ; no
	lsl.l	#4,d2
	add.b	1(a1),d2                        ; its value
	bra.s	hex_from_input_more
hex_from_input_next:
	addq.l	#2,a1                           ; the next in the table
	tst.b	(a1)                            ; its end?
	bmi.s	hex_from_input_bad              ; yes: not a digit
	bra.s	hex_from_input_find
hex_from_input_more:
	dbra	d0,hex_from_input_char
	clr.l	d0                              ; 0
	rts
hex_from_input_bad:	; from: input_hex
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; new_dump_address: "NEW DUMP ADDRESS : $", the memory address set.
;------------------------------------------------------------------------------
new_dump_address:	; from: memory_ripper
	lea	text_new_dump_address,a0        ; the question
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.s	new_dump_address_done           ; no
	move.l	d2,memory_address               ; the memory address
new_dump_address_done:
	rts

;------------------------------------------------------------------------------
; input_line: up to (buffer) characters typed into the buffer at 4(sp) (its first byte the maximum, the second
; the count, then the text), echoed; Return ends, Backspace takes one back, escape gives -1.  d0 = the count.
;------------------------------------------------------------------------------
input_line:                                     ; from: calculator, buffer_memory_menu, disk_search, next_sector_wrap,
                                                ;   external_call, sample_save, 12 more
	movea.l	6(sp),a0                        ; the buffer
	moveq	#0,d7
	move.b	(a0),d7                         ; the maximum
	subq.w	#1,d7                           ; for dbra
	tst.w	d7
	bmi.s	input_line_done                 ; none
	move.l	a0,-(sp)
	lea	cursor_on_text,a0               ; the cursor shown
	bsr.w	print
	movea.l	(sp)+,a0
	lea	1(a0),a1                        ; the count
	clr.b	(a1)                            ; none yet
	lea	2(a0),a0                        ; the text
	clr.b	(a0)                            ; ended
input_line_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; escape?
	bne.s	input_line_char                 ; no
	moveq	#-1,d0                          ; -1
	rts
input_line_char:
	cmp.b	#$d,d0                          ; Return?
	beq.w	input_line_done                 ; yes
	cmp.b	#$8,d0                          ; Backspace?
	beq.w	input_line_backspace            ; yes
	move.b	d0,(a0)                         ; in
	clr.b	1(a0)                           ; ended
	addq.b	#1,(a1)                         ; counted
	bsr.w	print                           ; echoed
	addq.l	#1,a0
	dbra	d7,input_line_key               ; the next
input_line_done:
	moveq	#0,d0
	move.b	(a1),d0                         ; the count
	rts
input_line_backspace:
	tst.b	(a1)                            ; any?
	beq.s	input_line_again                ; no
	move.l	a0,-(sp)
	lea	rub_out_text,a0                 ; back, a space, back
	bsr.w	print
	movea.l	(sp)+,a0
	subq.b	#1,(a1)                         ; one less
	subq.l	#1,a0
	clr.b	(a0)                            ; ended
	addq.w	#1,d7                           ; one more allowed
input_line_again:
	bra.w	input_line_key

;------------------------------------------------------------------------------
; print: the text at a0 on the ripper's screen (not while printing_off is set), every register kept.
;------------------------------------------------------------------------------
print:	; from: main_menu, run_module, calculator, print_result, disk_ripper, buffer_memory_menu, 99 more
	tst.w	printing_off                    ; off?
	bne.s	print_done                      ; yes
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	bsr.w	print_text
	movem.l	(sp)+,d0-d7/a0-a6
print_done:
	rts

;------------------------------------------------------------------------------
; print_text: the text at a0: ESC codes, 13 to column 0, 11 a line down, the rest characters (the cursor taken
; off first and put back after unless it is off).
;------------------------------------------------------------------------------
print_text:	; from: print
	cmpi.b	#$1b,(a0)                       ; ESC?
	bne.s	print_text_char                 ; no
	bsr.w	print_escape                    ; its code
	bra.s	print_text
print_text_char:
	cmpi.b	#$d,(a0)                        ; 13?
	beq.s	print_text_return               ; yes
	cmpi.b	#$b,(a0)                        ; 11?
	beq.s	print_text_line_down            ; yes
	tst.w	cursor_off                      ; the cursor off?
	bne.s	print_text_draw                 ; yes
	tst.w	cursor_drawn                    ; shown?
	beq.s	print_text_draw                 ; no
	bsr.w	cursor_off_old                  ; taken off
print_text_draw:
	move.w	#$1,cursor_drawn                ; shown (again after)
	bsr.w	char_address                    ; its place
	bsr.w	draw_char                       ; drawn
	bsr.w	cursor_keep_place               ; the cursor's place
	tst.w	cursor_off                      ; the cursor off?
	bne.s	print_text_next                 ; yes
	bsr.w	cursor_draw                     ; the cursor
print_text_next:
	tst.b	(a0)                            ; more?
	bne.s	print_text                      ; yes
	rts
print_text_line_down:
	addi.w	#$1,text_row                    ; a row down
	addq.l	#1,a0
	bra.w	print_text
print_text_return:
	clr.w	text_column                     ; column 0
	addq.l	#1,a0
	bra.w	print_text

;------------------------------------------------------------------------------
; print_escape: an ESC code: l clear the line, p inverse, q normal, A up, B down, C right, D left, E clear the
; screen, H home, K clear to the end of the line, J clear to the end of the screen, Y row column, e cursor on,
; f cursor off.
;------------------------------------------------------------------------------
print_escape:	; from: print_text
	addq.l	#1,a0
	move.b	(a0)+,d0                        ; the code
	cmp.b	#$6c,d0                         ; 'l'?
	beq.w	escape_clear_line
	cmp.b	#$70,d0                         ; 'p'?
	beq.w	escape_inverse
	cmp.b	#$71,d0                         ; 'q'?
	beq.w	escape_normal
	cmp.b	#$41,d0                         ; 'A'?
	beq.w	escape_up
	cmp.b	#$42,d0                         ; 'B'?
	beq.w	escape_down
	cmp.b	#$43,d0                         ; 'C'?
	beq.w	escape_right
	cmp.b	#$44,d0                         ; 'D'?
	beq.w	escape_left
	cmp.b	#$45,d0                         ; 'E'?
	beq.w	escape_clear_screen
	cmp.b	#$48,d0                         ; 'H'?
	beq.w	escape_home
	cmp.b	#$4b,d0                         ; 'K'?
	beq.w	escape_clear_to_end
	cmp.b	#$4a,d0                         ; 'J'?
	beq.w	escape_clear_to_bottom
	cmp.b	#$59,d0                         ; 'Y'?
	beq.w	escape_position
	cmp.b	#$65,d0                         ; 'e'?
	beq.w	escape_cursor_on
	cmp.b	#$66,d0                         ; 'f'?
	beq.w	escape_cursor_off
	rts
	bsr.w	cursor_keep_place               ; (not called)
	bsr.w	cursor_redraw
	rts
	bsr.w	cursor_off_old
	rts

;------------------------------------------------------------------------------
; cursor_redraw: the cursor off at its old place and on at the new.
;------------------------------------------------------------------------------
cursor_redraw:	; from: print_escape
	bsr.w	cursor_off_old                  ; off
	bsr.w	cursor_keep_place
	bsr.w	cursor_draw                     ; on
	rts

;------------------------------------------------------------------------------
; cursor_off_old: the cursor's block inverted at its last place.
;------------------------------------------------------------------------------
cursor_off_old:	; from: print_text, print_escape, cursor_redraw, cursor_draw
	movem.l	d0-d2/a0-a6,-(sp)               ; saved
	lea	cursor_place,a0                 ; its last place
	moveq	#0,d0
	moveq	#0,d1
	move.b	(a0)+,d0                        ; column
	move.b	(a0)+,d1                        ; row
	movea.l	ripper_screen,a6                ; the screen
	mulu.w	#$500,d1                        ; 8 lines a row
	adda.l	d1,a6
	move.w	d0,d2
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	cursor_off_old_high             ; yes
	lsr.w	#1,d0                           ; medium: 2 columns a word pair
	mulu.w	#$4,d0
	adda.l	d0,a6
	andi.w	#$1,d2                          ; odd column
	adda.w	d2,a6
	moveq	#7,d0                           ; 8 lines
cursor_off_old_line:
	not.b	(a6)                            ; inverted
	lea	$a0(a6),a6
	dbra	d0,cursor_off_old_line
	movem.l	(sp)+,d0-d2/a0-a6
	rts
cursor_off_old_high:
	lea	0(a6,d2.w),a6
	moveq	#7,d0                           ; 8 lines (doubled)
cursor_off_old_high_line:
	not.b	(a6)                            ; inverted
	lea	$50(a6),a6
	not.b	(a6)
	lea	$50(a6),a6
	dbra	d0,cursor_off_old_high_line
	movem.l	(sp)+,d0-d2/a0-a6
	rts

;------------------------------------------------------------------------------
; cursor_keep_place: the cursor's place kept (for cursor_off_old).
;------------------------------------------------------------------------------
cursor_keep_place:	; from: print_text, print_escape, cursor_redraw
	movem.l	d0/a0,-(sp)
	moveq	#0,d0
	lea	cursor_place,a0
	move.w	text_column,d0                  ; the column
	move.b	d0,(a0)+
	move.w	text_row,d0                     ; the row
	move.b	d0,(a0)+
	movem.l	(sp)+,d0/a0
	rts

;------------------------------------------------------------------------------
; cursor_draw: the cursor's block inverted at the column and row.
;------------------------------------------------------------------------------
cursor_draw:	; from: print_text, cursor_redraw
	movem.l	d0-d2/a0-a6,-(sp)               ; saved
	moveq	#0,d0
	moveq	#0,d1
	move.w	text_column,d0                  ; column
	move.w	text_row,d1                     ; row
	movea.l	ripper_screen,a6                ; the screen
	mulu.w	#$500,d1                        ; 8 lines a row
	adda.l	d1,a6
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	cursor_draw_high                ; yes
	move.w	d0,d2
	lsr.w	#1,d0                           ; medium
	mulu.w	#$4,d0
	adda.l	d0,a6
	andi.w	#$1,d2                          ; odd column
	adda.w	d2,a6
	moveq	#7,d0                           ; 8 lines
cursor_draw_line:
	not.b	(a6)                            ; inverted
	lea	$a0(a6),a6
	dbra	d0,cursor_draw_line
	movem.l	(sp)+,d0-d2/a0-a6
	rts
cursor_draw_high:
	adda.l	d0,a6
	moveq	#7,d0                           ; 8 lines (doubled)
cursor_draw_high_line:
	not.b	(a6)                            ; inverted
	lea	$50(a6),a6
	not.b	(a6)
	lea	$50(a6),a6
	dbra	d0,cursor_draw_high_line
	movem.l	(sp)+,d0-d2/a0-a6
	rts
escape_cursor_on:	; from: print_escape
	tst.w	cursor_off                      ; off?
	beq.s	escape_cursor_on_done           ; no
	clr.w	cursor_off                      ; on
	bsr.w	cursor_off_old                  ; drawn
escape_cursor_on_done:
	rts
escape_cursor_off:	; from: print_escape
	tst.w	cursor_off                      ; off already?
	bne.s	escape_cursor_off_done          ; yes
	move.w	#$1,cursor_off                  ; off
	bsr.w	cursor_off_old                  ; taken away
escape_cursor_off_done:
	rts
escape_inverse:	; from: print_escape
	clr.w	text_normal                     ; inverse
	rts
escape_normal:	; from: print_escape
	move.w	#$1,text_normal                 ; normal
	rts
escape_clear_line:	; from: print_escape
	movem.l	d0-d1/a6,-(sp)                  ; saved
	clr.w	text_column                     ; column 0
	movea.l	ripper_screen,a6                ; the screen
	move.w	text_row,d0                     ; the row
	mulu.w	#$500,d0                        ; 8 lines a row
	adda.l	d0,a6
	moveq	#7,d1                           ; 8 lines
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	escape_clear_line_high          ; yes
escape_clear_line_medium:
	moveq	#39,d0                          ; 40 word pairs
escape_clear_line_word:
	clr.w	(a6)                            ; plane 0 cleared
	addq.l	#4,a6
	dbra	d0,escape_clear_line_word
	dbra	d1,escape_clear_line_medium
	movem.l	(sp)+,d0-d1/a6
	rts
escape_clear_line_high:
	moveq	#39,d0
escape_clear_line_long:
	clr.l	(a6)+                           ; cleared
	dbra	d0,escape_clear_line_long
	dbra	d1,escape_clear_line_high
	movem.l	(sp)+,d0-d1/a6
	rts

;------------------------------------------------------------------------------
; escape_clear_to_end (ESC K): the row cleared from the cursor to its end.
;------------------------------------------------------------------------------
escape_clear_to_end:	; from: print_escape
	movem.l	d0-d1/a4-a6,-(sp)               ; saved
	movea.l	ripper_screen,a6                ; the screen
	move.w	text_row,d0                     ; the row
	mulu.w	#$500,d0
	adda.l	d0,a6
	lea	$a0(a6),a5                      ; the row's first line end
	move.w	text_column,d0                  ; the column
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	escape_clear_to_end_high        ; yes
	lsr.w	#1,d0                           ; medium
	mulu.w	#$4,d0
	adda.l	d0,a6
	move.w	text_column,d0
	andi.w	#$1,d0                          ; odd column
	adda.w	d0,a6
	movea.l	a6,a4
	cmpa.l	a5,a6                           ; at the end?
	beq.s	escape_clear_to_end_done        ; yes
	moveq	#7,d0                           ; 8 lines
escape_clear_to_end_line:
	move.w	a6,d1
	btst	#$0,d1                          ; an odd byte first?
	beq.s	escape_clear_to_end_word        ; no
	clr.b	(a6)                            ; cleared
	addq.l	#3,a6                           ; to the next pair
escape_clear_to_end_word:
	clr.w	(a6)                            ; cleared
	addq.l	#4,a6
	cmpa.l	a6,a5                           ; the line's end?
	bne.s	escape_clear_to_end_word        ; no
	lea	$a0(a5),a5                      ; the next line
	lea	$a0(a4),a4
	movea.l	a4,a6
	dbra	d0,escape_clear_to_end_line
escape_clear_to_end_done:
	movem.l	(sp)+,d0-d1/a4-a6
	rts
escape_clear_to_end_high:
	lea	$50(a6),a5                      ; the line's end
	lea	0(a6,d0.w),a6                   ; the column
	movea.l	a6,a4
	cmpa.l	a5,a6                           ; at the end?
	beq.s	escape_clear_to_end_high_done   ; yes
	moveq	#15,d0                          ; 16 lines
escape_clear_to_end_byte:
	clr.b	(a6)+                           ; cleared
	cmpa.l	a6,a5                           ; the line's end?
	bne.s	escape_clear_to_end_byte        ; no
	lea	$50(a5),a5                      ; the next line
	lea	$50(a4),a4
	movea.l	a4,a6
	dbra	d0,escape_clear_to_end_byte
escape_clear_to_end_high_done:
	movem.l	(sp)+,d0-d1/a4-a6
	rts
escape_up:	; from: print_escape
	tst.w	text_row                        ; row 0?
	beq.s	escape_up_done                  ; yes
	subi.w	#$1,text_row                    ; up
escape_up_done:
	rts
escape_down:	; from: print_escape
	cmpi.w	#$18,text_row                   ; row 24?
	beq.s	escape_down_done                ; yes
	addi.w	#$1,text_row                    ; down
escape_down_done:
	rts
escape_right:	; from: print_escape
	cmpi.w	#$4f,text_column                ; column 79?
	beq.s	escape_right_done               ; yes
	addi.w	#$1,text_column                 ; right
escape_right_done:
	rts
escape_left:	; from: print_escape
	tst.w	text_column                     ; column 0?
	beq.s	escape_left_done                ; yes
	subi.w	#$1,text_column                 ; left
escape_left_done:
	rts
escape_clear_screen:	; from: print_escape
	clr.w	text_column                     ; home
	clr.w	text_row
	bsr.w	fill_screen                     ; the screen filled
	clr.w	cursor_drawn                    ; the cursor not drawn
	rts
escape_home:	; from: print_escape
	clr.w	text_column                     ; home
	clr.w	text_row
	rts
escape_clear_to_bottom:	; from: print_escape
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	bsr.w	escape_clear_to_end             ; to the end of this row
	movea.l	ripper_screen,a6                ; the screen
	lea	$7d00(a6),a5                    ; its end
	move.w	text_row,d0                     ; the next row
	addq.w	#1,d0
	mulu.w	#$500,d0
	adda.l	d0,a6
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	escape_clear_to_bottom_high     ; yes
escape_clear_to_bottom_medium:
	moveq	#3,d0                           ; 40 word pairs a line, by 10
escape_clear_to_bottom_words:
	clr.w	(a6)                            ; plane 0 cleared
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	clr.w	(a6)
	addq.l	#4,a6
	dbra	d0,escape_clear_to_bottom_words
	cmpa.l	a6,a5                           ; the end?
	bne.s	escape_clear_to_bottom_medium   ; no
	movem.l	(sp)+,d0-d7/a0-a6
	rts
escape_clear_to_bottom_high:
	moveq	#3,d0
escape_clear_to_bottom_longs:
	clr.l	(a6)+                           ; cleared
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	dbra	d0,escape_clear_to_bottom_longs
	cmpa.l	a6,a5                           ; the end?
	bne.s	escape_clear_to_bottom_high     ; no
	movem.l	(sp)+,d0-d7/a0-a6
	rts
escape_position:	; from: print_escape
	move.l	d0,-(sp)
	moveq	#0,d0
	move.b	(a0)+,d0                        ; the row
	subi.b	#$20,d0                         ; from ' '
	move.w	d0,text_row
	move.b	(a0)+,d0                        ; the column
	subi.b	#$20,d0                         ; from ' '
	move.w	d0,text_column
	move.l	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; fill_screen: the screen filled: a grey stipple in medium resolution, cleared in high.
;------------------------------------------------------------------------------
fill_screen:	; from: escape_clear_to_end
	movem.l	d0-d7/a0-a3,-(sp)               ; saved
	movea.l	ripper_screen,a0                ; the screen
	move.w	#$31f,d0
	moveq	#0,d6
	moveq	#0,d7
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	fill_screen_rows                ; yes: cleared
	move.l	#$aaaa,d6                       ; medium: alternate lines
	move.l	#$5555,d7
fill_screen_rows:
	move.w	#$63,d1                         ; 100 line pairs
fill_screen_even:
	move.w	#$27,d0                         ; 40 longs
fill_screen_even_long:
	move.l	d6,(a0)+
	dbra	d0,fill_screen_even_long
	move.w	#$27,d0
fill_screen_odd_long:
	move.l	d7,(a0)+
	dbra	d0,fill_screen_odd_long
	dbra	d1,fill_screen_even
	movem.l	(sp)+,d0-d7/a0-a3
	rts

;------------------------------------------------------------------------------
; char_address: a6 = the screen byte of the column and row (the column past 79 is a new line, the row past 24
; row 0).
;------------------------------------------------------------------------------
char_address:	; from: print_text
	movea.l	ripper_screen,a6                ; the screen
	move.w	text_column,d0
	move.w	text_row,d1
	cmp.w	#$4f,d0                         ; past 79?
	ble.s	char_address_row                ; no
	clr.w	d0                              ; column 0
	move.w	d0,text_column
	addi.w	#$1,d1                          ; next row
	move.w	d1,text_row
char_address_row:
	cmp.w	#$18,d1                         ; past 24?
	ble.s	char_address_medium             ; no
	clr.w	d1                              ; row 0
	move.w	d1,text_row
char_address_medium:
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	char_address_high               ; yes
	mulu.w	#$500,d1                        ; 8 lines a row
	adda.l	d1,a6
	move.w	d0,d2
	lsr.w	#1,d2                           ; 2 columns a word pair
	mulu.w	#$4,d2
	lea	0(a6,d2.w),a6
	andi.w	#$1,d0                          ; odd column
	lea	0(a6,d0.w),a6
	rts
char_address_high:
	mulu.w	#$500,d1
	adda.l	d1,a6
	move.w	d0,d2
	lea	0(a6,d2.w),a6                   ; the column's byte
	rts

;------------------------------------------------------------------------------
; draw_char: the character at a0 drawn at a6 from the font (inverted unless text_normal is set), the column on.
;------------------------------------------------------------------------------
draw_char:	; from: print_text
	tst.b	(a0)                            ; the end?
	beq.s	draw_char_done                  ; yes
	move.b	(a0)+,d0                        ; the character
	subi.b	#$20,d0                         ; from ' '
	mulu.w	#$8,d0                          ; 8 bytes each
	lea	font,a1                         ; the font
	lea	0(a1,d0.w),a1
	moveq	#7,d0                           ; 8 lines
	tst.w	text_normal                     ; normal?
	beq.s	draw_char_inverse               ; no
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	draw_char_high                  ; yes
draw_char_line:
	move.b	(a1)+,(a6)
	lea	$a0(a6),a6
	dbra	d0,draw_char_line
	addi.w	#$1,text_column                 ; the next column
draw_char_done:
	rts
draw_char_high:
	move.b	(a1),(a6)                       ; each line twice
	lea	$50(a6),a6
	move.b	(a1)+,(a6)
	lea	$50(a6),a6
	dbra	d0,draw_char_high
	addi.w	#$1,text_column                 ; the next column
	rts
draw_char_inverse:
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	draw_char_inverse_high          ; yes
draw_char_inverse_line:
	move.b	(a1)+,d1
	not.b	d1                              ; inverted
	move.b	d1,(a6)
	lea	$a0(a6),a6
	dbra	d0,draw_char_inverse_line
	addi.w	#$1,text_column                 ; the next column
	rts
draw_char_inverse_high:
	move.b	(a1),d1                         ; each line twice
	not.b	d1
	move.b	d1,(a6)
	lea	$50(a6),a6
	move.b	(a1)+,d1
	not.b	d1
	move.b	d1,(a6)
	lea	$50(a6),a6
	dbra	d0,draw_char_inverse_high
	addi.w	#$1,text_column                 ; the next column
	rts
cursor_on_text:	; from: input_line
	dc.b	' ',27,'D',0
rub_out_text:	; from: input_line
	dc.w	$1b44,$0000

;------------------------------------------------------------------------------
; font: the ripper's 8x8 font, from Space.
;------------------------------------------------------------------------------
font:	; from: draw_game_char, draw_char
	dc.w	$0000,$0000,$0000,$0000,$1818,$1818,$1800,$1800
	dc.b	'fff',0
	dc.w	$0000,$0000,$006c,$fe6c,$6cfe,$6c00,$183e,$603c
	dc.w	$067c,$1800,$0066,$6c18
	dc.b	'0fF',0
	dc.w	$386c,$3870,$decc,$7600,$1818,$1800,$0000,$0000
	dc.w	$0e1c,$1818,$181c,$0e00,$7038,$1818,$1838,$7000
	dc.w	$0066,$3cff,$3c66,$0000,$0018,$187e,$1818,$0000
	dc.w	$0000,$0000
	dc.b	$00
	dc.b	'00`',0
	dc.b	$00,$00,$7e,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$00,$02
	dc.b	$06,$0c,$18
	dc.b	'0`@',0
	dc.b	'<fnvff<',0
	dc.w	$1838,$1818,$1818,$7e00,$3c66,$060c,$1830,$7e00
	dc.w	$7e0c,$180c,$0666,$3c00,$0c1c,$3c6c,$7e0c,$0c00
	dc.w	$7e60,$7c06,$0666,$3c00
	dc.b	'<``|ff<',0
	dc.w	$7e06,$0c18
	dc.b	'000',0
	dc.b	'<ff<ff<',0
	dc.w	$3c66,$663e,$060c,$3800,$0018,$1800,$1818,$0000
	dc.w	$0018,$1800,$1818,$3000,$060c,$1830,$180c,$0600
	dc.w	$0000,$7e00,$007e,$0000,$6030,$180c,$1830,$6000
	dc.w	$3c66,$060c,$1800,$1800
	dc.b	'<fnjn`>',0
	dc.b	$18
	dc.b	'<ff~ff',0
	dc.b	'|ff|ff|',0
	dc.b	'<f```f<',0
	dc.b	'xlffflx',0
	dc.b	'~``|``~',0
	dc.b	'~``|```',0
	dc.b	'>``nff>',0
	dc.b	'fff~fff',0
	dc.w	$3c18,$1818,$1818,$3c00,$0606,$0606,$0666,$3c00
	dc.b	'flxpxlf',0
	dc.b	'``````~',0
	dc.w	$c6ee,$fed6,$c6c6,$c600
	dc.b	'fv~~nff',0
	dc.b	'<fffff<',0
	dc.b	'|ff|```',0
	dc.b	'<fffvl6',0
	dc.b	'|ff|lff',0
	dc.w	$3c66,$603c,$0666,$3c00,$7e18,$1818,$1818,$1800
	dc.b	'ffffff>',0
	dc.w	$6666,$6666,$663c,$1800,$c6c6,$c6d6,$feee,$c600
	dc.w	$6666,$3c18
	dc.b	'<ff',0
	dc.w	$6666,$663c,$1818,$1800,$7e06,$0c18
	dc.b	'0`~',0
	dc.w	$1e18,$1818,$1818,$1e00,$4060,$3018,$0c06,$0200
	dc.w	$7818,$1818,$1818,$7800,$1038,$6cc6,$0000,$0000
	dc.w	$0000,$0000,$0000,$fe00,$00c0,$6030,$0000,$0000
	dc.w	$0000,$3c06
	dc.b	'>f>',0
	dc.b	'``|fff|',0
	dc.w	$0000
	dc.b	'<```<',0
	dc.w	$0606
	dc.b	'>fff>',0
	dc.w	$0000
	dc.b	'<f~`<',0
	dc.b	$1c
	dc.b	'0|0000',0
	dc.w	$0000,$3e66,$663e
	dc.b	$06
	dc.b	'|``|ffff',0
	dc.w	$1800,$3818,$1818,$3c00,$1800,$1818,$1818
	dc.b	$18
	dc.b	'p``flxlf',0
	dc.w	$3818,$1818,$1818,$3c00,$0000,$ecfe,$d6c6,$c600
	dc.w	$0000
	dc.b	'|ffff',0
	dc.w	$0000
	dc.b	'<fff<',0
	dc.w	$0000
	dc.b	'|fff|`',0
	dc.b	$00,$3e,$66,$66,$66,$3e,$06,$00,$00
	dc.b	'|f```',0
	dc.w	$0000,$3e60,$3c06,$7c00,$0018,$7e18,$1818,$0e00
	dc.w	$0000
	dc.b	'ffff>',0
	dc.w	$0000,$6666,$663c,$1800,$0000,$c6c6,$d67c,$6c00
	dc.w	$0000,$663c,$183c,$6600,$0000,$6666,$663e,$067c
	dc.w	$0000,$7e0c,$1830,$7e00,$0e18,$1830,$1818,$0e00
	dc.w	$1818,$1818,$1818,$1818,$7018,$180c,$1818,$7000
	dc.w	$0060,$f29e,$0c00,$0000,$0018
	dc.b	$18
	dc.b	'44b~',0
	dc.w	$003c,$6660,$663c,$0838,$6600
	dc.b	$00
	dc.b	'fff>',0
	dc.w	$0c18
	dc.b	$00
	dc.b	'<~`<',0
	dc.w	$1866,$003c,$067e,$3e00,$6600,$3c06
	dc.b	'>f>',0
	dc.w	$3018,$003c,$067e,$3e00,$1818,$003c,$067e,$3e00
	dc.w	$0000,$3c60,$603c,$0818,$1866
	dc.b	$00
	dc.b	'<~`<',0
	dc.w	$6600
	dc.b	'<f~`<',0
	dc.w	$3018
	dc.b	$00
	dc.b	'<~`<',0
	dc.w	$6600,$0038,$1818,$3c00,$1866,$0038,$1818,$3c00
	dc.w	$6030,$0038,$1818,$3c00,$6600
	dc.b	$18
	dc.b	'<f~f',0
	dc.w	$1800
	dc.b	$18
	dc.b	'<f~f',0
	dc.w	$0c18
	dc.b	'~`|`~',0
	dc.w	$0000,$7e1b,$7fd8,$7e00,$3f78,$d8de,$f8d8,$df00
	dc.w	$1866
	dc.b	$00
	dc.b	'<ff<',0
	dc.w	$6600
	dc.b	$00
	dc.b	'<ff<',0
	dc.w	$3018
	dc.b	$00
	dc.b	'<ff<',0
	dc.w	$1866
	dc.b	$00
	dc.b	'fff>',0
	dc.w	$3018
	dc.b	$00
	dc.b	'fff>',0
	dc.w	$6600,$6666,$663e,$067c,$6600
	dc.b	'<fff<',0
	dc.w	$6600
	dc.b	'ffff>',0
	dc.w	$1818,$3c60,$603c,$1818
	dc.b	$1c
	dc.b	':0|00~',0
	dc.w	$6666,$3c18,$3c18,$1800,$1c36,$667c,$6666,$7c60
	dc.b	$1e
	dc.b	'0|000`',0
	dc.w	$0c18,$003c,$067e,$3e00,$0c18,$0038,$1818,$3c00
	dc.w	$0c18
	dc.b	$00
	dc.b	'<ff<',0
	dc.w	$0c18
	dc.b	$00
	dc.b	'fff>',0
	dc.w	$3458
	dc.b	$00
	dc.b	'|fff',0
	dc.w	$3458
	dc.b	$00
	dc.b	'fvnf',0
	dc.w	$003c
	dc.b	$06
	dc.b	'>f>',0
	dc.b	$3c,$00
	dc.b	'<fff<',0
	dc.b	$3c,$00,$18,$00,$18
	dc.b	'0`f<',0
	dc.b	$00,$00
	dc.b	'>000',0
	dc.w	$0000,$007c,$0c0c,$0c00,$c6cc,$d836,$6bc3,$860f
	dc.w	$c6cc,$d836,$6ed6,$9f06,$0018,$0018,$1818,$1818
	dc.w	$1b36,$6cd8
	dc.b	'l6',27,0
	dc.w	$d86c,$361b,$366c,$d800,$3458,$003c,$067e,$3e00
	dc.w	$3458
	dc.b	$00
	dc.b	'<ff<',0
	dc.b	$02
	dc.b	'<fnvf<@',0
	dc.b	$02
	dc.b	'<nvf<@',0
	dc.b	$00,$7e,$db,$df,$d8,$7e,$00,$7f,$d8,$d8,$de,$d8,$d8,$7f,$00,$30
	dc.b	$18,$00,$18
	dc.b	'<f~f4X',0
	dc.b	$18
	dc.b	'<f~f4X<ffff<f',0
	dc.w	$0000,$0000,$0000,$0c18,$3000,$0000,$0000,$0010
	dc.w	$3810,$1010,$0000,$7aca,$caca,$7a0a,$0a0a,$7ec3
	dc.w	$bdb1,$b1bd,$c37e,$7ec3,$bda5,$b9ad,$c37e
	dc.b	$f1
	dc.b	'[_UQ',0
	dc.w	$0000,$6600,$e666,$66f6,$061c,$f666,$6666,$66f6
	dc.w	$061c
	dc.b	$00
	dc.b	'fv<nf',0
	dc.b	$00,$00,$7c,$0c,$0c,$0c,$7e,$00,$00,$00,$1e,$06,$0e,$1e,$36,$00
	dc.b	$00,$00,$7e,$0c,$0c,$0c,$0c,$00,$00,$00,$7c,$06
	dc.b	'fff',0
	dc.b	$00,$00,$1c,$0c,$0c,$0c,$0c,$00,$00,$00,$1e,$0c,$06,$06,$06,$00
	dc.b	$00,$00
	dc.b	'~6666',0
	dc.b	$00
	dc.b	'`nfff~',0
	dc.b	$00,$00,$3c,$0c,$0c,$00,$00,$00,$00,$00,$3e,$06,$06,$06,$3e,$00
	dc.b	$00,$60,$7e,$06,$06,$06,$0e,$00,$00,$00
	dc.b	'l>ffn',0
	dc.b	$00,$00,$1c,$0c,$0c,$0c,$3c,$00,$00,$00,$3e,$36,$36,$36,$1c,$00
	dc.b	$00,$00
	dc.b	'6666~',0
	dc.b	$00,$00,$7e,$66,$76,$06,$7e,$00,$00,$00,$66,$66,$3c,$0e,$7e,$00
	dc.b	$00,$00,$3e,$06
	dc.b	'6640',0
	dc.w	$0078,$0c0c,$0c0c,$0000,$00d6,$d6d6,$d6fe,$0000
	dc.w	$007c,$6c6c,$6cec,$0000,$001c,$0c0c,$0c0c,$0c00
	dc.w	$003e,$0606,$0606,$0600,$00fe
	dc.b	'fff~',0
	dc.b	$00,$00,$7e,$66,$76,$06,$06,$06,$00,$00,$36,$36,$1c,$0c,$0c,$0c
	dc.b	$00,$0e,$1b,$3c,$66,$66,$3c,$d8,$70,$00,$10,$38,$6c,$c6,$82,$00
	dc.b	$00,$66,$f7,$99,$99,$ef,$66,$00,$00,$00,$00,$76,$dc,$c8,$dc,$76
	dc.b	$00,$1c
	dc.b	'6f|ff|`',0
	dc.b	$fe,$66,$62,$60,$60,$60,$f8,$00,$00,$fe,$6c,$6c,$6c,$6c,$48,$fe
	dc.b	$66,$30,$18,$30,$66,$fe,$00,$00,$1e
	dc.b	'8lll8',0
	dc.w	$0000,$6c6c,$6c6c,$7fc0,$0000,$7e18,$1818,$1810
	dc.w	$3c18,$3c66,$663c,$183c
	dc.b	$00
	dc.b	'<f~ff<',0
	dc.b	$00
	dc.b	'<fff$f',0
	dc.w	$1c36,$78dc,$ccec,$7800,$0c18
	dc.b	'8TT80`',0
	dc.b	$10,$7c,$d6,$d6,$d6,$7c,$10
	dc.b	'>p`~`p>',0
	dc.b	'<ffffff',0
	dc.w	$007e,$007e,$007e,$0000,$1818,$7e18,$1800,$7e00
	dc.w	$3018,$0c18,$3000,$7e00,$0c18,$3018,$0c00,$7e00
	dc.w	$000e,$1b1b,$1818,$1818,$1818,$1818,$d8d8,$7000
	dc.w	$1818,$007e,$0018,$1800,$0032,$4c00,$324c,$0000
	dc.b	'8l8',0
	dc.w	$0000,$0000
	dc.b	'8|8',0
	dc.w	$0000,$0000,$0000,$0000,$1818,$0000,$0000,$0f18
	dc.w	$d870,$3000
	dc.b	'8llll',0
	dc.w	$0000,$386c,$1830,$7c00,$0000,$780c,$380c,$7800
	dc.w	$0000,$00fe,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	122,0

;------------------------------------------------------------------------------
; draw_box: a box on the screen: d4 the top line, d5 the left x, d6 the right x, d7 the bottom line: the inside
; cleared (medium resolution), the two sides and the top and bottom.
;------------------------------------------------------------------------------
draw_box:	; from: main_menu, disk_ripper, clear_box_area, info, external_call, music_ripper, 5 more
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	draw_box_sides                  ; yes: not cleared
	move.w	d4,d0
	move.w	d5,d1
	move.w	d6,d2
	move.w	d7,d3
	bsr.w	clear_box                       ; the inside cleared
draw_box_sides:
	move.w	d4,d0
	move.w	d7,d1
	move.w	d5,d2
	bsr.w	draw_left_side                  ; the left side
	move.w	d4,d0
	move.w	d7,d1
	move.w	d6,d2
	bsr.w	draw_right_side                 ; the right side
	move.w	d4,d0
	move.w	d5,d1
	move.w	d6,d2
	bsr.w	draw_horizontal                 ; the top
	move.w	d7,d0
	move.w	d5,d1
	move.w	d6,d2
	bsr.w	draw_horizontal                 ; the bottom
	rts

;------------------------------------------------------------------------------
; clear_box: the inside of the box (lines d0+1 to d3-1, x d1 to d2 by 16) cleared in plane 1.
;------------------------------------------------------------------------------
clear_box:	; from: draw_box
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	movea.l	ripper_screen,a0                ; the screen
	sub.w	d0,d3                           ; the height
	subq.w	#2,d3
	ble.s	clear_box_done                  ; none
	move.w	d3,d7
	addq.w	#1,d0                           ; from the next line
	mulu.w	#$a0,d0
	adda.l	d0,a0
	move.w	d1,d0
	addi.w	#$10,d0                         ; from the next 16 pixels
	andi.w	#$fff0,d0
	move.w	d0,d3
	lsr.w	#2,d0
	lea	0(a0,d0.w),a0
	sub.w	d3,d2                           ; the width
	andi.w	#$fff0,d2
	beq.s	clear_box_done                  ; none
	lsr.w	#4,d2                           ; in 16 pixels
	subq.w	#1,d2
	move.w	d2,d3
	addq.l	#2,a0                           ; plane 1
clear_box_line:
	movea.l	a0,a1
	move.w	d3,d2
clear_box_word:
	clr.w	(a0)                            ; cleared
	addq.l	#4,a0
	dbra	d2,clear_box_word
	lea	$a0(a1),a0                      ; the next line
	dbra	d7,clear_box_line
clear_box_done:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; draw_left_side: a vertical line at x d2 from line d0 to d1 (the box's left side in medium resolution).
;------------------------------------------------------------------------------
draw_left_side:	; from: draw_box
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.w	draw_side_high                  ; yes
	movem.l	d0-d3/a0-a1,-(sp)               ; saved
	movea.l	ripper_screen,a0                ; the screen
	sub.w	d0,d1                           ; the height
	subq.w	#1,d1
	mulu.w	#$a0,d0
	adda.l	d0,a0                           ; the first line
	move.w	d2,d0
	andi.w	#$fff0,d0
	lsr.w	#2,d0                           ; its word pair
	adda.l	d0,a0
	andi.w	#$f,d2                          ; the bit
	lea	pixel_bits,a1                   ; the bits
	lsl.w	#1,d2
	move.w	0(a1,d2.w),d0
	lea	left_side_masks,a1              ; the masks
	move.w	0(a1,d2.w),d2
	move.w	d2,d3
	swap	d2
	move.w	d3,d2
	move.w	d0,d3
	swap	d3
	move.w	d0,d3
	not.l	d3
draw_left_side_line:
	and.w	d2,2(a0)                        ; plane 1
	and.l	d3,(a0)                         ; plane 0
	or.w	d0,(a0)                         ; the bit set
	lea	$a0(a0),a0                      ; the next line
	dbra	d1,draw_left_side_line
	movem.l	(sp)+,d0-d3/a0-a1
	rts

;------------------------------------------------------------------------------
; draw_right_side: the same for the right side.
;------------------------------------------------------------------------------
draw_right_side:	; from: draw_box
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	draw_side_high                  ; yes
	movem.l	d0-d3/a0-a1,-(sp)               ; saved
	movea.l	ripper_screen,a0                ; the screen
	sub.w	d0,d1                           ; the height
	subq.w	#1,d1
	mulu.w	#$a0,d0
	adda.l	d0,a0
	move.w	d2,d0
	andi.w	#$fff0,d0
	lsr.w	#2,d0
	adda.l	d0,a0
	andi.w	#$f,d2                          ; the bit
	lea	pixel_bits,a1                   ; the bits
	lsl.w	#1,d2
	move.w	0(a1,d2.w),d0
	lea	right_side_masks,a1             ; the masks
	move.w	0(a1,d2.w),d2
	move.w	d2,d3
	swap	d2
	move.w	d3,d2
	move.w	d0,d3
	swap	d3
	move.w	d0,d3
	not.l	d3
draw_right_side_line:
	and.w	d2,2(a0)                        ; plane 1
	and.l	d3,(a0)                         ; plane 0
	or.w	d0,(a0)                         ; the bit set
	lea	$a0(a0),a0                      ; the next line
	dbra	d1,draw_right_side_line
	movem.l	(sp)+,d0-d3/a0-a1
	rts
draw_side_high:	; from: draw_left_side
	movem.l	d0-d2/a0-a1,-(sp)               ; saved
	movea.l	ripper_screen,a0                ; the screen
	sub.w	d0,d1                           ; the height
	subq.w	#1,d1
	mulu.w	#$a0,d0
	adda.l	d0,a0
	move.w	d2,d0
	andi.w	#$fff0,d0
	lsr.w	#3,d0                           ; its word
	adda.l	d0,a0
	andi.w	#$f,d2                          ; the bit
	lea	pixel_bits,a1                   ; the bits
	lsl.w	#1,d2
	move.w	0(a1,d2.w),d2
draw_side_high_line:
	or.w	d2,(a0)                         ; each line twice
	lea	$50(a0),a0
	or.w	d2,(a0)
	lea	$50(a0),a0
	dbra	d1,draw_side_high_line
	movem.l	(sp)+,d0-d2/a0-a1
	rts

;------------------------------------------------------------------------------
; draw_horizontal: a line on line d0 from x d1 to d2.
;------------------------------------------------------------------------------
draw_horizontal:	; from: draw_box
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	bne.s	draw_horizontal_high            ; yes
	movem.l	d0-d2/a0-a1,-(sp)               ; saved
	movea.l	ripper_screen,a0                ; the screen
	mulu.w	#$a0,d0                         ; the line
	adda.l	d0,a0
	movea.l	a0,a2
	move.w	d1,d0                           ; the left
	andi.w	#$fff0,d0
	lsr.w	#2,d0
	adda.l	d0,a0                           ; its word pair
	andi.w	#$f,d1
	lea	left_masks,a1                   ; the left's bits
	lsl.w	#1,d1
	move.w	0(a1,d1.w),d1
	move.w	d2,d0                           ; the right
	andi.w	#$fff0,d0
	lsr.w	#2,d0
	adda.l	d0,a2                           ; its word pair
	or.w	d1,(a0)                         ; the left word
	addq.l	#4,a0
	cmpa.l	a2,a0                           ; the right one?
	bge.s	draw_horizontal_right           ; yes
	move.l	#$ffff0000,d1                   ; plane 0 full
draw_horizontal_middle:
	move.l	d1,(a0)+
	cmpa.l	a2,a0
	blt.s	draw_horizontal_middle
draw_horizontal_right:
	andi.w	#$f,d2
	lea	right_masks,a1                  ; the right's bits
	lsl.w	#1,d2
	move.w	0(a1,d2.w),d2
	or.w	d2,(a0)+                        ; the right word
	movem.l	(sp)+,d0-d2/a0-a1
	rts
draw_horizontal_high:
	movem.l	d0-d2/a0-a1,-(sp)               ; saved
	movea.l	ripper_screen,a0                ; the screen
	mulu.w	#$a0,d0                         ; the line
	adda.l	d0,a0
	movea.l	a0,a2
	move.w	d1,d0                           ; the left
	andi.w	#$fff0,d0
	lsr.w	#3,d0
	adda.l	d0,a0                           ; its word
	andi.w	#$f,d1
	lea	left_masks,a1                   ; the left's bits
	lsl.w	#1,d1
	move.w	0(a1,d1.w),d1
	move.w	d2,d0                           ; the right
	andi.w	#$fff0,d0
	lsr.w	#3,d0
	adda.l	d0,a2                           ; its word
	or.w	d1,(a0)                         ; the left word
	addq.l	#2,a0
	cmpa.l	a2,a0                           ; the right one?
	bge.s	draw_horizontal_high_right      ; yes
	move.w	#$ffff,d1                       ; full
draw_horizontal_high_middle:
	move.w	d1,(a0)
	addq.l	#2,a0
	cmpa.l	a2,a0
	blt.s	draw_horizontal_high_middle
draw_horizontal_high_right:
	andi.w	#$f,d2
	lea	right_masks,a1                  ; the right's bits
	lsl.w	#1,d2
	move.w	0(a1,d2.w),d2
	or.w	d2,(a0)                         ; the right word
	movem.l	(sp)+,d0-d2/a0-a1
	rts

;------------------------------------------------------------------------------
; left_masks: a line's bits from each x to the right of its word.
;------------------------------------------------------------------------------
left_masks:	; from: draw_horizontal
	dc.w	$ffff,$7fff,$3fff,$1fff,$0fff,$07ff,$03ff,$01ff
	dc.w	$00ff,$007f,$003f,$001f,$000f,$0007,$0003,$0001

;------------------------------------------------------------------------------
; right_masks: a line's bits from the left of its word to each x.
;------------------------------------------------------------------------------
right_masks:	; from: draw_horizontal
	dc.w	$0000,$8000,$c000,$e000,$f000,$f800,$fc00,$fe00
	dc.w	$ff00,$ff80,$ffc0,$ffe0,$fff0,$fff8,$fffc,$fffe

;------------------------------------------------------------------------------
; pixel_bits: each x's bit.
;------------------------------------------------------------------------------
pixel_bits:	; from: draw_left_side, draw_right_side
	dc.w	$8000,$4000,$2000,$1000,$0800,$0400,$0200,$0100
	dc.w	$0080,$0040,$0020,$0010,$0008,$0004,$0002,$0001
left_side_masks:	; from: draw_left_side
	dc.w	$8000,$c000,$e000,$f000,$f800,$fc00,$fe00,$ff00
	dc.w	$ff80,$ffc0,$ffe0,$fff0,$fff8,$fffc,$fffe,$ffff
right_side_masks:	; from: draw_right_side
	dc.w	$ffff,$7fff,$3fff,$1fff,$0fff,$07ff,$03ff,$01ff
	dc.w	$00ff,$007f,$003f,$001f,$000f,$0007,$0003,$0001
	dc.w	$4879,$0000,$d1e8,$3f3c,$000a,$6100,$ef62,$5c8f
	dc.w	$4e75

;------------------------------------------------------------------------------
; ignore_fault: a bus or address error: the long frame dropped and rte.
;------------------------------------------------------------------------------
ignore_fault:	; from: ripper
	addq.l	#8,sp
	rte

;------------------------------------------------------------------------------
; put_hex_byte: the byte at a6 as two hex digits (digits a5) and a space into a4; a6 on.
;------------------------------------------------------------------------------
put_hex_byte:	; from: draw_buffer, draw_memory_dump, print_dump
	move.w	#$ff,d2
	move.b	(a6),d2                         ; the byte
	addq.l	#1,a6
	move.w	d2,d1
	andi.w	#$f,d2                          ; low
	lsr.w	#4,d1                           ; high
	move.b	0(a5,d1.w),(a4)+
	move.b	0(a5,d2.w),(a4)+
	move.b	#$20,(a4)+                      ; a space
	rts

;------------------------------------------------------------------------------
; put_hex_address: a6 as 8 hex digits (digits a5) and two spaces into a4.
;------------------------------------------------------------------------------
put_hex_address:                                ; from: print_result, disassemble_buffer, show_buffer_length,
                                                ;   list_track_id, boot_info, show_disk_settings, 20 more
	move.l	a6,d0
	clr.l	d1
	clr.l	d2
	clr.l	d3
	clr.l	d4
	moveq	#1,d5                           ; two words
put_hex_address_word:
	swap	d0                              ; the next word
	move.w	d0,d1
	move.w	d0,d2
	move.w	d0,d3
	andi.w	#$f,d1                          ; digit 3
	lsr.w	#4,d2                           ; digit 2
	andi.w	#$f,d2
	lsr.w	#8,d3
	move.w	d3,d4
	lsr.w	#4,d4
	andi.w	#$f,d3                          ; digit 1
	andi.w	#$f,d4                          ; digit 0
	move.b	0(a5,d4.w),(a4)+
	move.b	0(a5,d3.w),(a4)+
	move.b	0(a5,d2.w),(a4)+
	move.b	0(a5,d1.w),(a4)+
	dbra	d5,put_hex_address_word
	move.b	#$20,(a4)+                      ; two spaces
	move.b	#$20,(a4)+
	rts

;------------------------------------------------------------------------------
; draw_memory_dump: 20 lines of 16 bytes from the memory address, in hex and as characters, into the dump text,
; then printed.
;------------------------------------------------------------------------------
draw_memory_dump:	; from: memory_ripper
	lea	dump_lines,a4                   ; the text
	lea	hex_digits,a5                   ; the digits
	movea.l	memory_address,a6               ; the memory address
	moveq	#19,d6                          ; 20 lines
draw_memory_dump_line:
	move.l	a6,-(sp)                        ; kept
	move.w	#$f,d7                          ; 16 bytes
	bsr.w	put_hex_address                 ; the address
draw_memory_dump_hex:
	bsr.w	put_hex_byte
	dbra	d7,draw_memory_dump_hex
	movea.l	(sp)+,a6                        ; back
	move.b	#$20,(a4)+                      ; two spaces
	move.b	#$20,(a4)+
	moveq	#15,d7                          ; 16 characters
draw_memory_dump_char:
	move.w	#$ff,d0
	move.b	(a6),d0
	addq.l	#1,a6
	cmp.w	#$20,d0                         ; a control character?
	bge.s	draw_memory_dump_put            ; no
	move.b	#$2e,d0                         ; '.'
draw_memory_dump_put:
	move.b	d0,(a4)+
	dbra	d7,draw_memory_dump_char
	move.b	#$b,(a4)+                       ; a line down
	move.b	#$d,(a4)+                       ; column 0
	move.b	#$1b,(a4)+
	move.b	#$43,(a4)+                      ; right a column
	dbra	d6,draw_memory_dump_line
	move.b	#$0,(a4)                        ; ended
	lea	dump_text,a0                    ; the text with its position
	bsr.w	print                           ; printed
	rts

;------------------------------------------------------------------------------
; print_memory: to the printer from a start to an end address, as a hex dump or a disassembly.
;------------------------------------------------------------------------------
print_memory:	; from: memory_ripper
	move.w	#$11,-(sp)
	trap	#1                              ; Cprnos
	addq.l	#2,sp
	tst.l	d0                              ; ready?
	beq.w	printer_not_ready               ; no: "PRINTER NOT READY !"
	lea	text_start_address,a0           ; "START ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; escape?
	bmi.w	print_memory_done               ; yes
	move.l	d2,range_start                  ; the start
	lea	text_end_address,a0             ; "END ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; escape?
	bmi.w	print_memory_done               ; yes
	move.l	d2,range_end                    ; the end
	move.l	range_start,d0
	sub.l	d2,d0                           ; past the start?
	bge.w	print_memory_done               ; no: done
	lea	text_please_wait_printing,a0    ; "PLEASE WAIT ... PRINTING ..."
	bsr.w	print
	bsr.w	printer_new_line                ; a new line to the printer
	tst.w	disassembly_view                ; disassembly?
	bne.w	print_disassembly               ; yes
	movea.l	range_start,a6                  ; from the start

;------------------------------------------------------------------------------
; print_dump: 20 lines of hex dump from a6 to the printer, again until the end.
;------------------------------------------------------------------------------
print_dump:	; from: print_buffer
	cmpa.l	range_end,a6                    ; the end?
	bgt.w	print_memory_done               ; yes
	lea	dump_lines,a4                   ; the text
	lea	hex_digits,a5                   ; the digits
	moveq	#19,d6                          ; 20 lines
print_dump_clear:
	move.w	#$4f,d5                         ; 80 spaces
print_dump_space:
	move.b	#$20,(a4)+
	dbra	d5,print_dump_space
	dbra	d6,print_dump_clear
	lea	dump_lines,a4
	moveq	#19,d6                          ; 20 lines
print_dump_line:
	move.l	a6,-(sp)
	move.w	#$f,d7                          ; 16 bytes
	move.l	a6,-(sp)
	tst.w	buffer_length                   ; from the disk buffer?
	beq.s	print_dump_address              ; no
	suba.l	#disk_buffer,a6                 ; the address in it
print_dump_address:
	bsr.w	put_hex_address
	movea.l	(sp)+,a6
print_dump_hex:
	bsr.w	put_hex_byte
	dbra	d7,print_dump_hex
	movea.l	(sp)+,a6
	move.b	#$20,(a4)+                      ; two spaces
	move.b	#$20,(a4)+
	moveq	#15,d7                          ; 16 characters
print_dump_char:
	move.w	#$ff,d0
	move.b	(a6),d0
	addq.l	#1,a6
	cmp.w	#$20,d0                         ; a control character?
	bge.s	print_dump_put                  ; no
	move.b	#$2e,d0                         ; '.'
print_dump_put:
	move.b	d0,(a4)+
	dbra	d7,print_dump_char
	move.b	#$d,(a4)+                       ; CR
	move.b	#$b,(a4)+                       ; line feed
	cmpa.l	range_end,a6                    ; the end?
	bgt.w	print_dump_write                ; yes
	dbra	d6,print_dump_line
print_dump_write:
	pea	dump_lines                      ; the text
	move.l	#$640,-(sp)                     ; 1600 bytes
	move.w	#$3,-(sp)                       ; the printer
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	bsr.w	printer_return                  ; a CR
	bra.w	print_dump                      ; the next page
print_memory_done:	; from: print_memory
	lea	position_24_0_at_e30e,a0        ; the line cleared
	bsr.w	print
	rts
printer_not_ready:	; from: print_memory
	lea	text_printer_not_ready,a0       ; "PRINTER NOT READY !"
	bsr.w	print
	bsr.w	get_key                         ; a key
	rts
print_disassembly:	; from: print_memory
	movea.l	range_start,a5                  ; the start
print_disassembly_page:
	cmpa.l	range_end,a5                    ; the end?
	bge.w	print_disassembly_done          ; yes
	lea	dump_lines,a6                   ; the text
	moveq	#19,d1                          ; 20 lines
print_disassembly_clear:
	moveq	#77,d0                          ; 78 spaces
print_disassembly_space:
	move.b	#$20,(a6)+
	dbra	d0,print_disassembly_space
	move.b	#$d,(a6)+                       ; CR
	move.b	#$a,(a6)+                       ; line feed
	dbra	d1,print_disassembly_clear
	lea	dump_lines,a6                   ; the text
	bsr.w	disassemble_lines               ; 20 lines disassembled
	pea	dump_lines                      ; the text
	move.l	#$640,-(sp)                     ; 1600 bytes
	move.w	#$3,-(sp)                       ; the printer
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	bra.w	print_disassembly_page          ; the next page
print_disassembly_done:
	rts

;------------------------------------------------------------------------------
; disassemble_lines: 20 lines from a5 into the text at a6: the address, then the instruction.
;------------------------------------------------------------------------------
disassemble_lines:	; from: print_dump
	clr.w	line_count                      ; no lines yet
disassemble_lines_next:
	cmpa.l	range_end,a5                    ; the end?
	bge.w	disassemble_lines_done          ; yes
	move.l	a6,-(sp)
	movem.l	a0-a5,-(sp)                     ; saved
	movea.l	a6,a4
	movea.l	a5,a6                           ; the address
	lea	hex_digits,a5                   ; the digits
	bsr.w	put_hex_address                 ; printed
	move.b	#$20,(a4)+                      ; two spaces
	move.b	#$20,(a4)+
	movea.l	a4,a6                           ; the instruction's place
	movem.l	(sp)+,a0-a5
	movea.l	a5,a4                           ; the instruction
	bsr.w	dis_instruction                 ; disassembled
	lea	2(a4),a5
	bsr.w	dis_end                         ; its operands
	move.b	#$20,(a6)
	movea.l	(sp)+,a6
	lea	$50(a6),a6                      ; the next line
	addq.w	#1,line_count                   ; one more
	cmpi.w	#$14,line_count                 ; 20?
	bne.s	disassemble_lines_next          ; no
disassemble_lines_done:
	rts

;------------------------------------------------------------------------------
; printer_new_line: CR and $0B to the printer.
;------------------------------------------------------------------------------
printer_new_line:	; from: print_buffer, print_memory
	pea	printer_codes
	move.l	#$2,-(sp)                       ; 2 bytes
	move.w	#$3,-(sp)                       ; the printer
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	rts

;------------------------------------------------------------------------------
; printer_return: a CR to the printer.
;------------------------------------------------------------------------------
printer_return:	; from: print_dump
	pea	printer_codes
	move.l	#$1,-(sp)                       ; 1 byte
	move.w	#$3,-(sp)                       ; the printer
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	rts
printer_codes:	; from: printer_new_line
	dc.w	$0d0b

;------------------------------------------------------------------------------
; picture_ripper (F1): PICTURE RIPPER: the memory shown as a picture with its address, planes, width,
; resolution, the planes used, the palette, superposed planes, their count and columns, modulo; the cursor
; keys move through the settings and change them; 0-9 recall a setting kept, Control 0-9 keep one; F1 show
; the picture (F1 again back), F2 a new screen address, F3 save it as a Degas picture, F4 the colours, F10
; back.
;------------------------------------------------------------------------------
picture_ripper:	; from: info
	clr.w	colours_mode                    ; not the colours
	move.l	memory_address,d0               ; the address
	andi.w	#$fffe,d0                       ; even
	move.l	d0,memory_address
picture_ripper_screen:	; from: modules, save_picture, show_picture
	clr.w	printing_off                    ; the screen shown
	clr.w	saving_picture
	bsr.w	draw_settings                   ; the settings' screen
picture_ripper_key:	; from: colour_up, colour_down, save_picture, setting_up, show_settings, setting_down, 4 more
	tst.w	printing_off                    ; the picture shown?
	bne.w	show_picture                    ; yes: its keys
	bsr.w	get_key                         ; a key
	cmp.b	#$3,d0                          ; Control C?
	bne.s	picture_ripper_function         ; no
	moveq	#1,d0                           ; the calculator, then here
	jmp	run_module
picture_ripper_function:
	moveq	#1,d1
	bsr.w	module_keys                     ; the module keys
	swap	d0
picture_ripper_keys:	; from: show_picture
	swap	d0
	cmp.l	#$4b0034,d0                     ; Shift left?
	beq.w	picture_ripper_scan
	cmp.l	#$4d0036,d0                     ; Shift right?
	beq.w	picture_ripper_scan
	cmp.l	#$480038,d0                     ; Shift up?
	beq.w	picture_ripper_scan
	cmp.l	#$500032,d0                     ; Shift down?
	beq.w	picture_ripper_scan
	cmp.l	#$610000,d0                     ; Shift Home?
	bne.s	picture_ripper_insert           ; no
	move.l	#$500032,d0                     ; as Shift down
picture_ripper_insert:
	cmp.l	#$6e0000,d0                     ; Shift Insert?
	bne.s	picture_ripper_undo             ; no
	move.l	#$6d0012,d0                     ; as Control 4
picture_ripper_undo:
	cmp.l	#$6c001e,d0                     ; Shift Undo?
	bne.s	picture_ripper_digit            ; no
	move.l	#$6d0016,d0                     ; as Control 8
picture_ripper_digit:
	cmp.b	#$39,d0                         ; '0'-'9'?
	bgt.w	picture_ripper_keep
	cmp.b	#$30,d0
	blt.w	picture_ripper_keep
	move.w	d0,d1
	subi.w	#$30,d1
	mulu.w	#$78,d1                         ; 120 bytes a setting
	lea	picture_settings,a0             ; the settings kept
	adda.w	d1,a0
	tst.w	6(a0)                           ; one kept there?
	beq.w	picture_ripper_scan             ; no
	move.l	(a0)+,memory_address            ; the address
	move.w	(a0)+,picture_planes            ; the planes
	move.w	(a0)+,picture_width             ; the width
	move.w	(a0)+,picture_resolution        ; the resolution
	move.w	(a0)+,plane_masks               ; the planes used
	move.w	(a0)+,plane_masks+2
	move.w	(a0)+,plane_masks+4
	move.w	(a0)+,plane_masks+6
	lea	picture_palette,a1              ; the palette
	moveq	#7,d1
picture_ripper_digit_palette:
	move.l	(a0)+,(a1)+
	dbra	d1,picture_ripper_digit_palette
	move.w	(a0)+,superposed_width          ; the superposed planes
	move.w	(a0)+,superposed
	move.w	(a0)+,superposed_count
	move.w	(a0)+,picture_modulo            ; the modulo
	move.w	(a0)+,picture_columns_on
	tst.w	printing_off                    ; the picture shown?
	bne.w	picture_ripper_scan             ; yes
	move.l	d0,-(sp)
	bsr.w	show_resolution                 ; the settings shown again
	bsr.w	show_planes
	bsr.w	show_columns_value
	bsr.w	show_screen_address
	bsr.w	show_settings
	bsr.w	show_palette
	bsr.w	show_width
	bsr.w	show_superposed
	bsr.w	show_count
	bsr.w	show_modulo
	bsr.w	show_columns
	move.l	(sp)+,d0
	bra.s	picture_ripper_scan
picture_ripper_keep:
	cmp.b	#$19,d0                         ; $10-$19?
	bgt.s	picture_ripper_scan
	cmp.b	#$10,d0
	blt.s	picture_ripper_scan
	move.w	d0,d1
	subi.w	#$10,d1
	mulu.w	#$78,d1                         ; 120 bytes a setting
	lea	picture_settings,a0             ; the settings kept
	adda.w	d1,a0
	move.l	memory_address,(a0)+            ; the address
	move.w	picture_planes,(a0)+            ; the planes
	move.w	picture_width,(a0)+             ; the width
	move.w	picture_resolution,(a0)+        ; the resolution
	move.w	plane_masks,(a0)+               ; the planes used
	move.w	plane_masks+2,(a0)+
	move.w	plane_masks+4,(a0)+
	move.w	plane_masks+6,(a0)+
	lea	picture_palette,a1              ; the palette
	moveq	#7,d1
picture_ripper_keep_palette:
	move.l	(a1)+,(a0)+
	dbra	d1,picture_ripper_keep_palette
	move.w	superposed_width,(a0)+          ; the superposed planes
	move.w	superposed,(a0)+
	move.w	superposed_count,(a0)+
	move.w	picture_modulo,(a0)+            ; the modulo
	move.w	picture_columns_on,(a0)+
picture_ripper_scan:
	swap	d0
	cmp.l	#$36004d,d0                     ; Shift right?
	beq.w	address_up
	cmp.l	#$34004b,d0                     ; Shift left?
	beq.w	address_down
	cmp.l	#$380048,d0                     ; Shift up?
	beq.w	address_page_up
	cmp.l	#$320050,d0                     ; Shift down?
	beq.w	address_page_down
	cmp.b	#$73,d0                         ; 's'?
	beq.w	colour_down                     ; a colour less
	cmp.b	#$74,d0                         ; 't'?
	beq.w	colour_up                       ; a colour more
	cmp.b	#$3b,d0                         ; F1?
	beq.w	show_picture                    ; the picture
	cmp.b	#$3c,d0                         ; F2?
	beq.w	new_screen                      ; the screen address
	cmp.b	#$3d,d0                         ; F3?
	beq.w	save_picture                    ; save
	cmp.b	#$3e,d0                         ; F4?
	beq.w	toggle_colours                  ; the colours
	cmp.b	#$44,d0                         ; F10?
	beq.w	picture_ripper_done             ; back
	cmp.b	#$48,d0                         ; up?
	bne.s	picture_ripper_down             ; no
	tst.w	colours_mode                    ; the colours?
	bne.w	colour_row_up                   ; yes
	moveq	#0,d7
	lea	setting_rows,a6                 ; the settings' rows
	move.b	setting_row,d7                  ; the row
	subq.b	#1,d7                           ; up
	ext.w	d7
	move.b	0(a6,d7.w),d6                   ; its row character
	cmp.b	#$ff,d6                         ; the first passed?
	bne.w	picture_ripper_row_up           ; no
	move.b	#$c,d7                          ; the last
	ext.w	d7
	move.b	0(a6,d7.w),d6
picture_ripper_row_up:
	lea	setting_unmarker_text,a0        ; the marker off
	bsr.w	print
	move.b	d7,setting_row                  ; the row
	move.b	d6,setting_marker_text+2
	move.b	d6,setting_unmarker_text+2
	bsr.w	marker_setting                  ; the marker on
	bra.w	picture_ripper_key
picture_ripper_down:
	cmp.b	#$50,d0                         ; down?
	bne.s	picture_ripper_right            ; no
	tst.w	colours_mode                    ; the colours?
	bne.w	colour_row_down                 ; yes
	moveq	#0,d7
	lea	setting_rows,a6                 ; the settings' rows
	move.b	setting_row,d7                  ; the row
	addq.b	#1,d7                           ; down
	move.b	0(a6,d7.w),d6                   ; its row character
	cmp.b	#$ff,d6                         ; the last passed?
	bne.s	picture_ripper_row_down         ; no
	move.b	#$0,d7                          ; the first
	move.b	0(a6,d7.w),d6
picture_ripper_row_down:
	lea	setting_unmarker_text,a0        ; the marker off
	bsr.w	print
	move.b	d7,setting_row                  ; the row
	move.b	d6,setting_marker_text+2
	move.b	d6,setting_unmarker_text+2
	bsr.w	marker_setting                  ; the marker on
	bra.w	picture_ripper_key
picture_ripper_right:
	cmp.b	#$4d,d0                         ; right?
	beq.w	setting_up                      ; the setting up
	cmp.b	#$4b,d0                         ; left?
	beq.w	setting_down                    ; the setting down
	bra.w	picture_ripper_key
picture_ripper_done:
	clr.w	printing_off
	clr.w	saving_picture
	rts

;------------------------------------------------------------------------------
; colour_up ('t', right in the colours): the current colour's value up (a colour a step, wrapping past $EFF/$FFF).
;------------------------------------------------------------------------------
colour_up:	; from: picture_ripper, setting_up
	moveq	#0,d7
	move.b	#$25,colour_value_text+2        ; the row
	move.b	colour_row,d7                   ; the colour
	add.b	d7,colour_value_text+2
	lsl.w	#1,d7
	lea	picture_palette,a0              ; the palette
	move.w	0(a0,d7.w),d1                   ; its value
	cmp.b	#$74,d0                         ; 't'?
	bne.s	colour_up_one                   ; no: by 1
	move.w	#$100,d2                        ; by $100 (red)
	cmp.w	#$eff,d1
	ble.s	colour_up_set
	addi.w	#$f000,d1                       ; wrapped
	bra.s	colour_up_set
colour_up_one:
	moveq	#1,d2
	cmp.w	#$fff,d1                        ; the top?
	bne.w	colour_up_set                   ; no
	move.w	#$ffff,d1
colour_up_set:
	add.w	d2,d1
	move.w	d1,0(a0,d7.w)                   ; set
	move.w	d1,d4
	movea.l	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	colour_value_text,a0            ; its place
	bsr.w	print
	lea	hex_text+5,a0                   ; the last 3 digits
	bsr.w	print
	bra.w	picture_ripper_key

;------------------------------------------------------------------------------
; colour_down ('s', left in the colours): the current colour's value down.
;------------------------------------------------------------------------------
colour_down:	; from: picture_ripper, setting_down
	moveq	#0,d7
	move.b	#$25,colour_value_text+2        ; the row
	move.b	colour_row,d7                   ; the colour
	add.b	d7,colour_value_text+2
	lsl.w	#1,d7
	lea	picture_palette,a0              ; the palette
	move.w	0(a0,d7.w),d1                   ; its value
	cmp.b	#$73,d0                         ; 's'?
	bne.s	colour_down_one                 ; no: by 1
	move.w	#$100,d2                        ; by $100 (red)
	cmp.w	#$100,d1
	bge.s	colour_down_set
	addi.w	#$1000,d1                       ; wrapped
	bra.s	colour_down_set
colour_down_one:
	move.w	#$1,d2
	cmp.w	#$0,d1                          ; 0?
	bne.w	colour_down_set                 ; no
	move.w	#$1000,d1
colour_down_set:
	sub.w	d2,d1
	move.w	d1,0(a0,d7.w)                   ; set
	move.w	d1,d4
	movea.l	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	colour_value_text,a0            ; its place
	bsr.w	print
	lea	hex_text+5,a0                   ; the last 3 digits
	bsr.w	print
	bra.w	picture_ripper_key
colour_row_up:	; from: picture_ripper
	moveq	#0,d7
	lea	colour_rows,a6                  ; the colours' rows
	move.b	colour_row,d7                   ; the colour
	subq.b	#1,d7                           ; up
	ext.w	d7
	move.b	0(a6,d7.w),d6                   ; its row
	cmp.b	#$ff,d6                         ; the first passed?
	bne.s	colour_row_up_set               ; no
	move.b	#$f,d7                          ; the last
	ext.w	d7
	move.b	0(a6,d7.w),d6
colour_row_up_set:
	lea	colour_unmarker_text,a0         ; the marker off
	bsr.w	print
	move.b	d7,colour_row
	move.b	d6,colour_marker_text+2
	move.b	d6,colour_unmarker_text+2
	bsr.w	marker_colour                   ; the marker on
	bra.w	picture_ripper_key
colour_row_down:	; from: picture_ripper
	moveq	#0,d7
	lea	colour_rows,a6                  ; the colours' rows
	move.b	colour_row,d7                   ; the colour
	addq.b	#1,d7                           ; down
	move.b	0(a6,d7.w),d6                   ; its row
	cmp.b	#$ff,d6                         ; the last passed?
	bne.s	colour_row_down_set             ; no
	move.b	#$0,d7                          ; the first
	move.b	0(a6,d7.w),d6
colour_row_down_set:
	lea	colour_unmarker_text,a0         ; the marker off
	bsr.w	print
	move.b	d7,colour_row
	move.b	d6,colour_marker_text+2
	move.b	d6,colour_unmarker_text+2
	bsr.w	marker_colour                   ; the marker on
	bra.w	picture_ripper_key

;------------------------------------------------------------------------------
; save_picture (F3): "ENTER PICTURE'S NAME :", then the picture saved as a Degas file (.PI1, .PI2 or .PI3 by its
; resolution): the resolution word and the palette put in front of the screen it is shown on.
;------------------------------------------------------------------------------
save_picture:	; from: picture_ripper
	tst.w	printing_off                    ; the picture shown?
	bne.w	picture_ripper_key              ; yes: no
	lea	text_enter_picture_s,a0         ; "ENTER PICTURE'S NAME : "
	bsr.w	print
	move.w	#$3d00,input_buffer             ; 61 characters
	pea	input_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	move.l	a0,-(sp)
	lea	position_24_17,a0
	bsr.w	print
	movea.l	(sp)+,a0
	tst.l	d0                              ; any?
	ble.w	picture_ripper_key              ; no
	moveq	#8,d0                           ; 8 characters
	lea	input_buffer+1,a0               ; the name
save_picture_name:
	addq.l	#1,a0
	cmpi.b	#$2e,(a0)                       ; '.'?
	beq.w	save_picture_extension          ; yes
	cmpi.b	#$5c,(a0)                       ; '\'?
	bne.s	save_picture_name_next          ; no
	moveq	#8,d0                           ; a folder: 8 again
save_picture_name_next:
	tst.b	(a0)                            ; the end?
	dbeq	d0,save_picture_name
save_picture_extension:
	move.b	#$2e,(a0)+                      ; ".PI"
	move.b	#$50,(a0)+
	move.b	#$49,(a0)+
	move.b	#$31,(a0)                       ; '1'
	move.w	picture_resolution,d0           ; + the resolution
	add.b	d0,(a0)+
	clr.b	(a0)                            ; ended
	move.w	#$ffff,saving_picture           ; the screen only, no keys
	bsr.w	show_picture                    ; the picture drawn
	movea.l	picture_screen,a0               ; the screen
	suba.l	#$22,a0                         ; the 34 bytes before it
	movem.l	(a0)+,d0-d7                     ; kept
	movem.l	d0-d7,-(sp)
	move.w	(a0),-(sp)
	movea.l	picture_screen,a0
	suba.l	#$22,a0
	clr.b	(a0)+                           ; 0
	move.w	picture_resolution,d0           ; the resolution
	move.b	d0,(a0)+
	lea	picture_palette,a1              ; the palette
	movem.l	(a1),d0-d7
	movem.l	d0-d7,(a0)
	lea	input_buffer+2,a0               ; the name
	move.l	#$7d22,d3                       ; 32034 bytes
	movea.l	picture_screen,a1               ; the header
	suba.l	#$22,a1
	bsr.w	save_file                       ; saved
	movea.l	picture_screen,a0
	move.w	(sp)+,d0
	move.w	d0,-(a0)                        ; the 34 bytes back
	movea.l	picture_screen,a0
	suba.l	#$22,a0
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,(a0)
	clr.w	saving_picture
	bra.w	picture_ripper_screen           ; the settings again

;------------------------------------------------------------------------------
; force_media_change: hdv_mediach made to say "changed" and a file opened, so that GEMDOS reads the disk again.
;------------------------------------------------------------------------------
force_media_change:	; from: create_file, save_source, save_file
	move.w	#$2300,sr                       ; interrupts on
	movem.l	d3/a0-a1,-(sp)
	move.l	$47e.w,saved_mediach            ; hdv_mediach, kept
	move.l	#media_changed,$47e.w           ; hdv_mediach, "changed"
	clr.w	-(sp)
	pea	media_change_name               ; the name ($01)
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.l	saved_mediach,$47e.w            ; hdv_mediach, back
	movem.l	(sp)+,d3/a0-a1
	rts
media_change_name:
	dc.w	$0100

;------------------------------------------------------------------------------
; save_file: d3 bytes from a1 saved as the file named at a0 (errors shown).
;------------------------------------------------------------------------------
save_file:	; from: save_binary, save_picture
	bsr.w	force_media_change              ; the media change
	move.w	#$0,-(sp)                       ; normal file
	move.l	a0,-(sp)                        ; the name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	tst.l	d0
	cmp.l	#$ffffffff,d0                   ; -1?
	bne.s	save_file_handle                ; no
	move.l	#$fffffff3,d0                   ; as -13
save_file_handle:
	bmi.w	show_error                      ; an error?
	move.w	d0,d1                           ; the handle
	move.l	a1,-(sp)                        ; the data
	move.l	d3,-(sp)                        ; its length
	move.w	d1,-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	tst.l	d0                              ; an error?
	bmi.w	show_error
	cmp.l	d0,d3                           ; all?
	ble.s	save_file_close                 ; yes
	move.l	#$ffffffbc,d0                   ; -68: disk full
	bra.w	show_error
save_file_close:
	move.w	d1,-(sp)                        ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.l	d0                              ; an error?
	bmi.w	show_error
	rts
disk_error_message:
	lea	text_disk_error_press,a0        ; "DISK ERROR !!!" (not called)
	bsr.w	print
	bsr.w	get_key                         ; a key
	rts

;------------------------------------------------------------------------------
; setting_up (right): the current setting up: the address, planes, width, resolution, planes used, superposed,
; their count, columns, modulo.
;------------------------------------------------------------------------------
setting_up:	; from: picture_ripper
	tst.w	colours_mode                    ; the colours?
	bne.w	colour_up                       ; yes: a colour up
	cmpi.b	#$36,setting_marker_text+2      ; modulo?
	beq.w	modulo_up
	cmpi.b	#$35,setting_marker_text+2      ; superposed?
	beq.w	superposed_columns_toggle
	cmpi.b	#$33,setting_marker_text+2      ; columns?
	beq.w	columns_up
	cmpi.b	#$32,setting_marker_text+2      ; count?
	beq.w	superposed_toggle
	cmpi.b	#$34,setting_marker_text+2      ; the planes' count?
	beq.w	count_up
	cmpi.b	#$25,setting_marker_text+2      ; the address?
	beq.w	address_up
	cmpi.b	#$27,setting_marker_text+2      ; the planes?
	beq.w	planes_up
	cmpi.b	#$29,setting_marker_text+2      ; the width?
	beq.w	width_up
	cmpi.b	#$2b,setting_marker_text+2      ; the resolution?
	bne.w	setting_up_plane                ; no: the planes used
	cmpi.w	#$1,picture_resolution          ; medium or high already?
	bge.w	picture_ripper_key              ; yes
	addq.w	#1,picture_resolution           ; one up
	bsr.w	show_resolution                 ; shown
	move.w	#$2,picture_planes              ; 2 planes
	bsr.w	show_planes
	move.w	#$0,plane_masks+4
	move.w	#$0,plane_masks+6
	bsr.w	show_settings                   ; the settings
	clr.w	superposed                      ; not superposed
	bsr.w	show_superposed
	bra.w	picture_ripper_key

;------------------------------------------------------------------------------
; show_settings: the planes used (ON/OFF) and the palette shown.
;------------------------------------------------------------------------------
show_settings:	; from: picture_ripper, setting_up, draw_settings
	lea	position_13_32,a0
	bsr.w	print
	lea	text_on,a0
	tst.w	plane_masks
	bmi.s	show_settings_plane_two
	lea	text_off,a0
show_settings_plane_two:
	bsr.w	print
	lea	position_14_32,a0
	bsr.w	print
	lea	text_on,a0
	tst.w	plane_masks+2
	bmi.s	show_settings_plane_three
	lea	text_off,a0
show_settings_plane_three:
	bsr.w	print
	lea	position_15_32,a0
	bsr.w	print
	lea	text_on,a0
	tst.w	plane_masks+4
	bmi.s	show_settings_plane_four
	lea	text_off,a0
show_settings_plane_four:
	bsr.w	print
	lea	position_16_32,a0
	bsr.w	print
	lea	text_on,a0
	tst.w	plane_masks+6
	bmi.s	show_settings_palette
	lea	text_off,a0
show_settings_palette:
	bsr.w	print
	moveq	#0,d7
	moveq	#0,d3
	moveq	#1,d4
	moveq	#2,d5
	moveq	#3,d6
show_settings_colour:
	lea	position_5_56,a0
	move.w	d7,d2
	mulu.w	#$6,d2
	adda.w	d2,a0
	bsr.w	print
	btst	d3,d7
	bne.s	show_settings_colour_off_one
show_settings_colour_plane_one:
	btst	d4,d7
	bne.s	show_settings_colour_off_two
show_settings_colour_plane_two:
	btst	d5,d7
	bne.s	show_settings_colour_off_three
show_settings_colour_plane_three:
	btst	d6,d7
	bne.s	show_settings_colour_off_four
show_settings_colour_next:
	addq.w	#1,d7
	cmp.w	#$10,d7
	bne.s	show_settings_colour
	rts
show_settings_colour_off_one:
	tst.w	plane_masks
	bne.s	show_settings_colour_plane_one
	lea	marker_star,a0
	bsr.w	print
	bra.s	show_settings_colour_next
show_settings_colour_off_two:
	tst.w	plane_masks+2
	bne.s	show_settings_colour_plane_two
	lea	marker_star,a0
	bsr.w	print
	bra.s	show_settings_colour_next
show_settings_colour_off_three:
	tst.w	plane_masks+4
	bne.s	show_settings_colour_plane_three
	lea	marker_star,a0
	bsr.w	print
	bra.s	show_settings_colour_next
show_settings_colour_off_four:
	tst.w	plane_masks+6
	bne.s	show_settings_colour_next
	lea	marker_star,a0
	bsr.w	print
	bra.s	show_settings_colour_next
setting_up_plane:	; from: setting_up, setting_down
	cmpi.b	#$2d,setting_marker_text+2      ; plane 1?
	bne.s	setting_up_plane_two
	not.w	plane_masks
	bsr.w	show_settings
	bra.w	picture_ripper_key
setting_up_plane_two:
	cmpi.b	#$2e,setting_marker_text+2      ; plane 2?
	bne.s	setting_up_plane_three
	cmpi.w	#$2,picture_resolution
	beq.w	picture_ripper_key
	not.w	plane_masks+2
	bsr.w	show_settings
	bra.w	picture_ripper_key
setting_up_plane_three:
	cmpi.b	#$2f,setting_marker_text+2      ; plane 3?
	bne.s	setting_up_plane_four
	cmpi.w	#$1,picture_resolution
	bge.w	picture_ripper_key
	not.w	plane_masks+4
	bsr.w	show_settings
	bra.w	picture_ripper_key
setting_up_plane_four:
	cmpi.b	#$30,setting_marker_text+2      ; plane 4?
	bne.s	setting_up_done
	cmpi.w	#$1,picture_resolution
	bge.w	picture_ripper_key
	not.w	plane_masks+6
	bsr.w	show_settings
setting_up_done:
	bra.w	picture_ripper_key
address_up:	; from: picture_ripper, setting_up
	swap	d0                              ; Shift right: a line on
	cmp.w	#$36,d0
	bne.s	address_up_word
	moveq	#0,d0
	move.w	picture_width,d0
	lsr.w	#3,d0
	mulu.w	picture_planes,d0
	add.w	picture_modulo,d0
	mulu.w	#$c8,d0
	move.b	$ffff8260.w,d1                  ; shift mode
	andi.w	#$3,d1
	cmp.b	#$2,d1
	bne.s	address_up_line
	mulu.w	#$2,d0
address_up_line:
	subq.l	#2,d0
	add.l	d0,memory_address
address_up_word:
	addq.l	#2,memory_address               ; a word on
	bsr.w	show_screen_address
	bra.w	picture_ripper_key
planes_up:	; from: setting_up
	cmpi.w	#$0,picture_resolution
	bne.s	planes_up_medium
	cmpi.w	#$4,picture_planes
	beq.w	picture_ripper_key
	addq.w	#1,picture_planes
	cmpi.w	#$2,picture_planes
	bne.s	planes_up_show
	move.w	#$2,superposed_count
	bsr.w	show_count
planes_up_show:
	bsr.w	show_planes
	tst.w	superposed
	beq.w	picture_ripper_key
	clr.w	superposed
	bra.w	superposed_toggle
planes_up_medium:
	cmpi.w	#$1,picture_resolution
	bne.w	picture_ripper_key
	cmpi.w	#$2,picture_planes
	beq.w	picture_ripper_key
	addq.w	#1,picture_planes
	bsr.w	show_planes
	bra.w	picture_ripper_key
superposed_toggle:	; from: setting_up, setting_down
	tst.w	picture_resolution
	bne.s	superposed_off
	cmpi.w	#$2,picture_planes
	bgt.s	superposed_off
	move.w	picture_width,d0
	move.w	superposed_width,d1
	mulu.w	superposed_count,d1
	cmp.w	d0,d1
	bgt.s	superposed_off
	not.w	superposed
	bsr.w	show_superposed
	bra.w	picture_ripper_key
superposed_off:
	clr.w	superposed
	bsr.w	show_superposed
	bra.w	picture_ripper_key
width_up:	; from: setting_up
	cmpi.w	#$2700,picture_width
	beq.w	picture_ripper_key
	addi.w	#$10,picture_width
	bsr.w	show_columns_value
	tst.w	picture_resolution
	bne.w	picture_ripper_key
	cmpi.w	#$2,picture_planes
	bgt.w	picture_ripper_key
	tst.w	superposed
	beq.w	picture_ripper_key
	clr.w	superposed
	bra.w	superposed_toggle
columns_up:	; from: setting_up
	cmpi.w	#$140,superposed_width
	beq.w	picture_ripper_key
	addi.w	#$10,superposed_width
	bsr.w	show_width
	tst.w	picture_resolution
	bne.w	picture_ripper_key
	cmpi.w	#$2,picture_planes
	bgt.w	picture_ripper_key
	tst.w	superposed
	beq.w	picture_ripper_key
	clr.w	superposed
	bra.w	superposed_toggle

;------------------------------------------------------------------------------
; setting_down (left): the current setting down.
;------------------------------------------------------------------------------
setting_down:	; from: picture_ripper
	tst.w	colours_mode
	bne.w	colour_down
	cmpi.b	#$36,setting_marker_text+2
	beq.w	modulo_down
	cmpi.b	#$35,setting_marker_text+2
	beq.w	superposed_columns_toggle
	cmpi.b	#$33,setting_marker_text+2
	beq.w	columns_down
	cmpi.b	#$32,setting_marker_text+2
	beq.w	superposed_toggle
	cmpi.b	#$34,setting_marker_text+2
	beq.w	count_down
	cmpi.b	#$25,setting_marker_text+2
	beq.w	address_down
	cmpi.b	#$27,setting_marker_text+2
	beq.w	planes_down
	cmpi.b	#$29,setting_marker_text+2
	beq.w	width_down
	cmpi.b	#$2b,setting_marker_text+2
	bne.w	setting_up_plane
	cmpi.w	#$2,picture_resolution
	beq.w	picture_ripper_key
	tst.w	picture_resolution
	beq.w	picture_ripper_key
	subq.w	#1,picture_resolution
	bsr.w	show_resolution
	bra.w	picture_ripper_key
count_down:
	cmpi.w	#$1,picture_planes
	bne.w	picture_ripper_key
	move.w	superposed_count,d0
	cmp.w	#$2,d0
	ble.w	picture_ripper_key
	subq.w	#1,d0
	move.w	d0,superposed_count
	bsr.w	show_count
	tst.w	superposed
	beq.w	picture_ripper_key
	clr.w	superposed
	bra.w	superposed_toggle
count_up:	; from: setting_up
	cmpi.w	#$1,picture_planes
	bne.w	picture_ripper_key
	move.w	superposed_count,d0
	cmp.w	#$4,d0
	bge.w	picture_ripper_key
	addq.w	#1,d0
	move.w	d0,superposed_count
	bsr.w	show_count
	tst.w	superposed
	beq.w	picture_ripper_key
	clr.w	superposed
	bra.w	superposed_toggle
address_down:	; from: picture_ripper
	swap	d0
	cmp.w	#$34,d0
	bne.s	address_down_word
	moveq	#0,d0
	move.w	picture_width,d0
	lsr.w	#3,d0
	mulu.w	picture_planes,d0
	add.w	picture_modulo,d0
	mulu.w	#$c8,d0
	move.b	$ffff8260.w,d1                  ; shift mode
	andi.w	#$3,d1
	cmp.b	#$2,d1
	bne.s	address_down_line
	mulu.w	#$2,d0
address_down_line:
	subi.l	#$2,d0
	sub.l	d0,memory_address
address_down_word:
	subq.l	#2,memory_address
	bsr.w	show_screen_address
	bra.w	picture_ripper_key
address_page_down:	; from: picture_ripper
	moveq	#0,d0
	move.w	picture_width,d0
	lsr.w	#3,d0
	mulu.w	picture_planes,d0
	add.l	d0,memory_address
	moveq	#0,d0
	move.w	picture_modulo,d0
	add.l	d0,memory_address
	bsr.w	show_screen_address
	bra.w	picture_ripper_key
address_page_up:	; from: picture_ripper
	moveq	#0,d0
	move.w	picture_width,d0
	lsr.w	#3,d0
	mulu.w	picture_planes,d0
	sub.l	d0,memory_address
	moveq	#0,d0
	move.w	picture_modulo,d0
	sub.l	d0,memory_address
	bsr.w	show_screen_address
	bra.w	picture_ripper_key
planes_down:
	cmpi.w	#$1,picture_planes
	beq.w	picture_ripper_key
	subq.w	#1,picture_planes
	cmpi.w	#$2,picture_planes
	bne.s	planes_down_show
	move.w	#$2,superposed_count
	bsr.w	show_count
planes_down_show:
	bsr.w	show_planes
	bra.w	picture_ripper_key
width_down:
	cmpi.w	#$10,picture_width
	beq.w	picture_ripper_key
	subi.w	#$10,picture_width
	bsr.w	show_columns_value
	tst.w	picture_resolution
	bne.w	picture_ripper_key
	cmpi.w	#$2,picture_planes
	bgt.w	picture_ripper_key
	tst.w	superposed
	beq.w	picture_ripper_key
	clr.w	superposed
	bra.w	superposed_toggle
columns_down:
	cmpi.w	#$10,superposed_width
	beq.w	picture_ripper_key
	subi.w	#$10,superposed_width
	bsr.w	show_width
	tst.w	picture_resolution
	bne.w	picture_ripper_key
	cmpi.w	#$2,picture_planes
	bgt.w	picture_ripper_key
	tst.w	superposed
	beq.w	picture_ripper_key
	clr.w	superposed
	bra.w	superposed_toggle

;------------------------------------------------------------------------------
; show_picture (F1): the raster colours off, the picture's screen and palette set, the memory drawn there by
; its resolution, planes and superposition; F1 again goes back to the settings, another key is a setting key.
;------------------------------------------------------------------------------
show_picture:	; from: picture_ripper, save_picture
	bsr.w	stop_raster
	bsr.w	show_picture_screen
	movem.l	picture_palette,d0-d7
	movem.l	d0-d7,$ffff8240.w               ; palette 0
	move.w	#$ffff,printing_off
	cmpi.w	#$2,picture_resolution
	beq.s	show_picture_high
	cmpi.w	#$1,picture_resolution
	beq.w	show_picture_medium
	cmpi.w	#$4,picture_planes
	beq.s	show_picture_four
	cmpi.w	#$3,picture_planes
	beq.s	show_picture_three
	cmpi.w	#$2,picture_planes
	beq.s	show_picture_two
	bra.s	show_picture_one
show_picture_high:
	bsr.w	show_high
	bra.s	show_picture_key
show_picture_four:
	bsr.w	show_four
	bra.s	show_picture_key
show_picture_three:
	bsr.w	show_three
	bra.s	show_picture_key
show_picture_two:
	tst.w	superposed
	bne.s	show_picture_two_superposed
	bsr.w	show_two
	bra.s	show_picture_key
show_picture_two_superposed:
	bsr.w	show_two_superposed
	bra.w	show_picture_key
show_picture_one:
	tst.w	superposed
	bne.s	show_picture_superposed
	bsr.w	show_one
	bra.s	show_picture_key
show_picture_superposed:
	cmpi.w	#$4,superposed_count
	bne.s	show_picture_superposed_three
	bsr.w	show_superposed_four
	bra.w	show_picture_key
show_picture_superposed_three:
	cmpi.w	#$3,superposed_count
	bne.s	show_picture_superposed_two
	bsr.w	show_superposed_three
	bra.w	show_picture_key
show_picture_superposed_two:
	bsr.w	show_superposed_two
	bra.w	show_picture_key
show_picture_medium:
	cmpi.w	#$1,picture_planes
	beq.s	show_picture_medium_one
	bsr.w	show_medium_two
	bra.s	show_picture_key
show_picture_medium_one:
	bsr.w	show_medium_one
show_picture_key:
	tst.w	saving_picture
	bne.s	show_picture_done
	bsr.w	get_key
	swap	d0
	cmp.b	#$3b,d0
	beq.s	show_picture_back
	bra.w	picture_ripper_keys
show_picture_done:
	rts
show_picture_back:
	move.l	#$7770000,$ffff8240.w           ; palette 0
	move.l	#$5550000,$ffff8244.w
	clr.w	printing_off
	movea.l	ripper_screen,a0
	bsr.w	show_ripper_screen
	bra.w	picture_ripper_screen

;------------------------------------------------------------------------------
; new_screen (F2): "NEW SCREEN ADDRESS : $": where the picture is shown.
;------------------------------------------------------------------------------
new_screen:	; from: picture_ripper
	lea	text_new_screen_address,a0
	bsr.w	print
	bsr.w	input_hex_long
	move.l	d0,-(sp)
	lea	position_24_17,a0
	bsr.w	print
	move.l	(sp)+,d0
	tst.l	d0
	bmi.w	picture_ripper_key
	andi.l	#$fffffffe,d2
	move.l	d2,memory_address
	bsr.w	show_screen_address
	bra.w	picture_ripper_key

;------------------------------------------------------------------------------
; draw_settings: the picture ripper's settings screen drawn.
;------------------------------------------------------------------------------
draw_settings:	; from: show_error, picture_ripper
	movea.l	ripper_screen,a0
	bsr.w	show_ripper_screen
	lea	text_picture_ripper_f1,a0
	bsr.w	print
	bsr.w	show_resolution
	bsr.w	show_planes
	bsr.w	show_columns_value
	bsr.w	show_screen_address
	bsr.w	show_width
	bsr.w	show_superposed
	bsr.w	show_count
	bsr.w	show_modulo
	bsr.w	show_columns
	tst.w	colours_mode
	bne.s	draw_settings_values
	bsr.w	marker_setting
	bra.s	draw_settings_rest
draw_settings_values:
	bsr.w	marker_colour
draw_settings_rest:
	bsr.w	show_settings
	bsr.w	show_palette
	moveq	#28,d4
	move.w	#$1a4,d5
	move.w	#$258,d6
	move.w	#$ac,d7
	bsr.w	draw_box
	moveq	#5,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#26,d7
	bsr.w	draw_box
	moveq	#28,d4
	moveq	#120,d5
	move.w	#$168,d6
	move.w	#$be,d7
	bsr.w	draw_box
	bsr.w	draw_raster_bar
	rts
modulo_up:	; from: setting_up
	cmpi.w	#$140,picture_modulo
	beq.s	modulo_wrap
	addq.w	#2,picture_modulo
	bra.s	modulo_show
modulo_wrap:
	move.w	#$0,picture_modulo
modulo_show:
	bsr.w	show_modulo
	bra.w	picture_ripper_key
modulo_down:	; from: setting_down
	tst.w	picture_modulo
	beq.s	modulo_wrap_down
	subq.w	#2,picture_modulo
	bra.s	modulo_down_show
modulo_wrap_down:
	move.w	#$140,picture_modulo
modulo_down_show:
	bsr.w	show_modulo
	bra.w	picture_ripper_key

show_modulo:	; from: picture_ripper, draw_settings
	lea	position_22_32,a0
	bsr.w	print
	moveq	#0,d0
	move.w	picture_modulo,d0
	bsr.w	to_decimal_digits
	movea.l	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+5,a0
	bsr.w	print
	rts
superposed_columns_toggle:	; from: setting_up, setting_down
	not.w	picture_columns_on
	bsr.w	show_columns
	bra.w	picture_ripper_key

show_columns:	; from: picture_ripper, draw_settings, show_modulo
	lea	position_21_32,a0
	bsr.w	print
	lea	text_off,a0
	tst.w	picture_columns_on
	beq.s	show_columns_done
	lea	text_on,a0
show_columns_done:
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; draw_raster_bar: the colour bars (medium resolution) and the raster colours started.
;------------------------------------------------------------------------------
draw_raster_bar:	; from: draw_settings
	moveq	#0,d0
	move.b	$ffff8260.w,d0                  ; shift mode
	andi.w	#$3,d0
	cmp.b	#$2,d0
	beq.s	draw_raster_bar_done
	movea.l	ripper_screen,a0
	adda.l	#$19a0,a0
	adda.l	#$78,a0
	moveq	#15,d1
draw_raster_bar_row:
	moveq	#5,d0
draw_raster_bar_line:
	move.l	#$ffffffff,(a0)
	move.l	#$ffffffff,4(a0)
	move.l	#$ffffffff,8(a0)
	lea	$a0(a0),a0
	dbra	d0,draw_raster_bar_line
	lea	$140(a0),a0
	dbra	d1,draw_raster_bar_row
	bsr.w	start_raster
draw_raster_bar_done:
	rts

;------------------------------------------------------------------------------
; start_raster: timer B every 8 lines changes colour 3 from the raster table (raster_colour).
;------------------------------------------------------------------------------
start_raster:	; from: draw_raster_bar
	move.w	#$2300,sr
	bsr.w	stop_raster
	move.w	#$25,-(sp)
	trap	#14                             ; Vsync
	addq.l	#2,sp
	pea	raster_colour(pc)
	move.w	#$8,-(sp)
	move.w	#$8,-(sp)
	move.w	#$1,-(sp)
	move.w	#$1f,-(sp)
	trap	#14                             ; Xbtimer
	lea	$c(sp),sp
	rts

;------------------------------------------------------------------------------
; stop_raster: timer B's interrupt off, the raster table from its start, colour 3 black.
;------------------------------------------------------------------------------
stop_raster:	; from: main_menu, disk_ripper, info, external_call, show_picture, start_raster
	move.w	#$8,-(sp)
	move.w	#$1a,-(sp)
	trap	#14                             ; Jdisint
	addq.l	#4,sp
	move.l	#raster_colours,raster_pointer
	clr.w	$ffff8246.w
	rts

;------------------------------------------------------------------------------
; raster_colour: timer B: colour 3 the next of the 25 raster colours.
;------------------------------------------------------------------------------
raster_colour:	; from: start_raster
	move.l	a0,-(sp)
	movea.l	raster_pointer,a0
	move.w	(a0)+,$ffff8246.w
	cmpa.l	#raster_end,a0
	blt.s	raster_colour_set
	lea	raster_colours,a0
raster_colour_set:
	move.l	a0,raster_pointer
	movea.l	(sp)+,a0
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA
	rte

show_superposed:	; from: picture_ripper, setting_up, show_settings, draw_settings
	lea	position_18_32,a0
	bsr.w	print
	lea	text_off,a0
	tst.w	superposed
	beq.s	show_superposed_done
	lea	text_on,a0
show_superposed_done:
	bsr.w	print
	rts

show_width:	; from: picture_ripper, show_settings, setting_down, draw_settings
	lea	position_19_32,a0
	bsr.w	print
	moveq	#0,d0
	move.w	superposed_width,d0
	bsr.w	to_decimal_digits
	movea.l	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+5,a0
	bsr.w	print
	rts

show_palette:	; from: picture_ripper, draw_settings
	move.b	#$25,colour_value_text+2
	lea	picture_palette,a0
	moveq	#15,d0
show_palette_colour:
	move.w	(a0)+,d4
	movem.l	d0/a0,-(sp)
	movea.l	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	colour_value_text,a0
	bsr.w	print
	lea	hex_text+5,a0
	bsr.w	print
	addq.b	#1,colour_value_text+2
	movem.l	(sp)+,d0/a0
	dbra	d0,show_palette_colour
	rts

;------------------------------------------------------------------------------
; toggle_colours (F4): the cursor in the colours or the settings.
;------------------------------------------------------------------------------
toggle_colours:	; from: picture_ripper
	not.w	colours_mode
	beq.s	toggle_colours_settings
	lea	setting_unmarker_text,a0
	bsr.w	print
	bsr.w	marker_colour
	bra.w	picture_ripper_key
toggle_colours_settings:
	lea	colour_unmarker_text,a0
	bsr.w	print
	bsr.w	marker_setting
	bra.w	picture_ripper_key

marker_colour:	; from: colour_down, draw_settings, toggle_colours
	lea	colour_marker_text,a0
	bsr.w	print
	rts

marker_setting:	; from: picture_ripper, draw_settings, toggle_colours
	lea	setting_marker_text,a0
	bsr.w	print
	rts

show_resolution:	; from: picture_ripper, setting_up, setting_down, draw_settings
	tst.w	picture_resolution
	bne.s	show_resolution_medium
	lea	text_low,a0
	bra.s	show_resolution_text
show_resolution_medium:
	cmpi.w	#$1,picture_resolution
	bne.s	show_resolution_high
	lea	text_medium,a0
	clr.w	plane_masks+4
	clr.w	plane_masks+6
	bra.s	show_resolution_text
show_resolution_high:
	lea	text_high,a0
show_resolution_text:
	bsr.w	print
	rts

show_planes:	; from: picture_ripper, setting_up, show_settings, setting_down, draw_settings
	lea	position_7_32,a0
	bsr.w	print
	lea	hex_digit_pairs,a0
	move.w	picture_planes,d0
	add.w	d0,d0
	move.b	0(a0,d0.w),d0
	lea	hex_text,a1
	move.b	d0,(a1)+
	clr.b	(a1)
	lea	hex_text,a0
	bsr.w	print
	rts

show_count:	; from: picture_ripper, show_settings, setting_down, draw_settings
	cmpi.w	#$2,picture_planes
	bne.s	show_count_value
	move.w	#$2,superposed_count
show_count_value:
	lea	position_20_32,a0
	bsr.w	print
	lea	hex_digit_pairs,a0
	move.w	superposed_count,d0
	add.w	d0,d0
	move.b	0(a0,d0.w),d0
	lea	hex_text,a1
	move.b	d0,(a1)+
	clr.b	(a1)
	lea	hex_text,a0
	bsr.w	print
	rts

show_columns_value:	; from: picture_ripper, show_settings, setting_down, draw_settings
	lea	position_9_32,a0
	bsr.w	print
	moveq	#0,d0
	move.w	picture_width,d0
	bsr.w	to_decimal_digits
	movea.l	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text+4,a0
	bsr.w	print
	rts

show_screen_address:	; from: picture_ripper, show_settings, setting_down, new_screen, draw_settings
	lea	position_5_32,a0
	bsr.w	print
	lea	hex_digits,a5
	lea	hex_text,a4
	movea.l	memory_address,a6
	bsr.w	put_hex_address
	clr.b	(a4)
	lea	hex_text,a0
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; to_decimal_digits: d0 as decimal digits in d4 (BCD, shown as hex).
;------------------------------------------------------------------------------
to_decimal_digits:	; from: boot_info, show_decimal_word, show_modulo, show_width, show_columns_value, free_space
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	move.w	d0,d1
	move.w	#$2710,d2
	move.w	#$2710,d3
	moveq	#16,d5
	moveq	#0,d4
to_decimal_digits_next:
	move.w	d0,-(sp)
	move.w	d0,d1
to_decimal_digits_divide:
	divu.w	d2,d1
	cmp.w	#$a,d1
	bge.s	to_decimal_digits_divide
	move.w	d1,d6
	mulu.w	d2,d6
	andi.l	#$f,d1
	lsl.l	d5,d1
	add.w	d1,d4
	divu.w	#$a,d3
	divu.w	#$a,d2
	subq.w	#4,d5
	move.w	(sp)+,d0
	sub.w	d6,d0
	tst.w	d0
	bne.s	to_decimal_digits_next
	rts

;------------------------------------------------------------------------------
; show_ripper_screen: the ripper's screen at a0 with its colours (white text, grey).
;------------------------------------------------------------------------------
show_ripper_screen:	; from: main_menu, show_picture, draw_settings
	move.l	#$7770000,$ffff8240.w           ; palette 0
	move.l	#$5550000,$ffff8244.w
	move.b	$ffff8260.w,d0                  ; shift mode
	andi.w	#$3,d0
	cmp.b	#$2,d0
	beq.s	set_screen_resolution
	moveq	#1,d0
set_screen_resolution:
	move.w	d0,-(sp)
	move.l	a0,-(sp)
	move.l	a0,-(sp)
	move.w	#$5,-(sp)
	trap	#14                             ; Setscreen
	lea	$c(sp),sp
	rts
	move.w	#$ffff,-(sp)
	move.l	a0,-(sp)
	move.l	a0,-(sp)
	move.w	#$5,-(sp)
	trap	#14                             ; Setscreen
	lea	$c(sp),sp
	rts

show_picture_screen:	; from: show_picture
	movea.l	picture_screen,a0
	bsr.w	set_picture_screen
	rts

set_picture_screen:	; from: show_picture_screen
	move.b	$ffff8260.w,d0                  ; shift mode
	andi.w	#$3,d0
	cmp.b	#$2,d0
	beq.s	set_picture_screen_address
	move.w	picture_resolution,d0
	move.l	a0,-(sp)
	move.w	d0,-(sp)
	move.l	#$ffffffff,-(sp)
	move.l	#$ffffffff,-(sp)
	move.w	#$5,-(sp)
	trap	#14                             ; Setscreen
	lea	$c(sp),sp
	movea.l	(sp)+,a0
set_picture_screen_address:
	move.l	a0,d0
	lsr.w	#8,d0
	move.b	d0,$ffff8203.w                  ; video base mid
	swap	d0
	move.b	d0,$ffff8201.w                  ; video base high
	rts

;------------------------------------------------------------------------------
; show_high, show_four, show_three, show_two, show_one, ...: one wrapper for each kind: the picture copied,
; then its columns marked if wanted.
;------------------------------------------------------------------------------
show_high:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_high
	tst.w	picture_columns_on
	beq.s	show_high_done
	cmpi.w	#$140,picture_width
	bgt.s	show_high_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_high_columns:
	move.w	picture_width,d0
	lsr.w	#3,d0
	add.w	d0,d7
	move.l	picture_screen,d1
	addi.l	#$50,d1
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d1
	blt.s	show_high_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_high_width
	move.l	(sp)+,d7
	bra.s	show_high_columns
show_high_done:
	rts
	rts

;------------------------------------------------------------------------------
; copy_high and the copy_ routines: the picture copied line by line from the memory address to the screen: the
; width's words of each plane (and'ed with the planes used), the rest of the line cleared, the modulo skipped.
;------------------------------------------------------------------------------
copy_high:	; from: show_high
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_high_width:	; from: show_high
	move.w	picture_width,d0
	lsr.w	#4,d0
	move.w	d0,d4
	moveq	#40,d3
	sub.w	d0,d3
	bge.s	copy_high_lines
	moveq	#40,d0
	subi.w	#$28,d4
copy_high_lines:
	subq.w	#1,d0
	move.w	#$18f,d2
	move.w	plane_masks,d6
copy_high_line:
	movem.l	d0/d3,-(sp)
copy_high_word:
	move.w	(a1)+,(a0)
	and.w	d6,(a0)+
	dbra	d0,copy_high_word
	tst.w	d3
	beq.s	copy_high_next
	bmi.s	copy_high_skip
	tst.w	columns_drawn
	beq.s	copy_high_clear
	add.w	d3,d3
	adda.w	d3,a0
	bra.s	copy_high_next
copy_high_clear:
	subq.w	#1,d3
copy_high_clear_word:
	clr.w	(a0)+
	dbra	d3,copy_high_clear_word
	bra.s	copy_high_next
copy_high_skip:
	move.w	d4,d0
	add.w	d0,d0
	adda.w	d0,a1
copy_high_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0/d3
	dbra	d2,copy_high_line
	rts

show_medium_two:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_medium_two
	tst.w	picture_columns_on
	beq.s	show_medium_two_done
	cmpi.w	#$140,picture_width
	bgt.s	show_medium_two_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_medium_two_columns:
	move.w	picture_width,d0
	lsr.w	#2,d0
	add.w	d0,d7
	move.l	picture_screen,d1
	addi.l	#$a0,d1
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d1
	blt.s	show_medium_two_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_medium_two_width
	move.l	(sp)+,d7
	bra.s	show_medium_two_columns
show_medium_two_done:
	rts

show_medium_one:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_medium_one
	tst.w	picture_columns_on
	beq.s	show_medium_one_done
	cmpi.w	#$a0,picture_width
	bgt.s	show_medium_one_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_medium_one_columns:
	move.w	picture_width,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d1
	addi.l	#$a0,d1
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d1
	blt.s	show_medium_one_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_medium_one_width
	move.l	(sp)+,d7
	bra.s	show_medium_one_columns
show_medium_one_done:
	rts

show_four:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_four
	tst.w	picture_columns_on
	beq.s	show_four_done
	cmpi.w	#$a0,picture_width
	bgt.s	show_four_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_four_columns:
	move.w	picture_width,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d1
	addi.l	#$a0,d1
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d1
	blt.s	show_four_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_four_width
	move.l	(sp)+,d7
	bra.s	show_four_columns
show_four_done:
	rts

show_three:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_three
	tst.w	picture_columns_on
	beq.s	show_three_done
	cmpi.w	#$a0,picture_width
	bgt.s	show_three_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_three_columns:
	move.w	picture_width,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d1
	addi.l	#$a0,d1
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d1
	blt.s	show_three_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_three_width
	move.l	(sp)+,d7
	bra.s	show_three_columns
show_three_done:
	rts

show_two:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_two
	tst.w	picture_columns_on
	beq.s	show_two_done
	cmpi.w	#$a0,picture_width
	bgt.s	show_two_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_two_columns:
	move.w	picture_width,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d1
	addi.l	#$a0,d1
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d1
	blt.s	show_two_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_two_width
	move.l	(sp)+,d7
	bra.s	show_two_columns
show_two_done:
	rts

show_one:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_one
	tst.w	picture_columns_on
	beq.s	show_one_done
	cmpi.w	#$a0,picture_width
	bgt.s	show_one_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_one_columns:
	move.w	picture_width,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d1
	addi.l	#$a0,d1
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d1
	blt.s	show_one_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_one_width
	move.l	(sp)+,d7
	bra.s	show_one_columns
show_one_done:
	rts

copy_four:	; from: show_four
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_four_width:	; from: show_four
	move.w	picture_width,d0
	lsr.w	#4,d0
	move.w	d0,d4
	moveq	#20,d3
	sub.w	d0,d3
	bge.s	copy_four_lines
	moveq	#20,d0
	subi.w	#$14,d4
copy_four_lines:
	subq.w	#1,d0
	move.w	plane_masks,d6
	swap	d6
	move.w	plane_masks+2,d6
	move.w	plane_masks+4,d1
	swap	d1
	move.w	plane_masks+6,d1
	move.w	#$c7,d2
copy_four_line:
	movem.l	d0/d3,-(sp)
copy_four_word:
	move.l	(a1)+,(a0)
	and.l	d6,(a0)+
	move.l	(a1)+,(a0)
	and.l	d1,(a0)+
	dbra	d0,copy_four_word
	tst.w	d3
	beq.s	copy_four_next
	bmi.s	copy_four_skip
	tst.w	columns_drawn
	beq.s	copy_four_clear
	add.w	d3,d3
	add.w	d3,d3
	add.w	d3,d3
	adda.w	d3,a0
	bra.s	copy_four_next
copy_four_clear:
	subq.w	#1,d3
copy_four_clear_long:
	clr.l	(a0)+
	clr.l	(a0)+
	dbra	d3,copy_four_clear_long
	bra.s	copy_four_next
copy_four_skip:
	move.w	d4,d0
	lsl.w	#3,d0
	adda.w	d0,a1
copy_four_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0/d3
	dbra	d2,copy_four_line
	rts

copy_three:	; from: show_three
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_three_width:	; from: show_three
	move.w	picture_width,d0
	lsr.w	#4,d0
	move.w	d0,d4
	moveq	#20,d3
	sub.w	d0,d3
	bge.s	copy_three_lines
	moveq	#20,d0
	subi.w	#$14,d4
copy_three_lines:
	subq.w	#1,d0
	move.w	plane_masks,d6
	swap	d6
	move.w	plane_masks+2,d6
	moveq	#0,d1
	move.w	plane_masks+4,d1
	swap	d1
	move.w	#$c7,d2
copy_three_line:
	movem.l	d0/d3,-(sp)
copy_three_word:
	move.l	(a1)+,(a0)
	and.l	d6,(a0)+
	move.w	(a1)+,(a0)
	and.l	d1,(a0)+
	dbra	d0,copy_three_word
	tst.w	d3
	beq.s	copy_three_next
	bmi.s	copy_three_skip
	tst.w	columns_drawn
	beq.s	copy_three_clear
	add.w	d3,d3
	add.w	d3,d3
	add.w	d3,d3
	adda.w	d3,a0
	bra.s	copy_three_next
copy_three_clear:
	subq.w	#1,d3
copy_three_clear_long:
	clr.l	(a0)+
	clr.l	(a0)+
	dbra	d3,copy_three_clear_long
	bra.s	copy_three_next
copy_three_skip:
	move.w	d4,d0
	add.w	d0,d0
	move.w	d0,d3
	add.w	d0,d0
	add.w	d3,d0
	adda.w	d0,a1
copy_three_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0/d3
	dbra	d2,copy_three_line
	rts

copy_two:	; from: show_two
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_two_width:	; from: show_two
	move.w	picture_width,d0
	lsr.w	#4,d0
	move.w	d0,d4
	moveq	#20,d3
	sub.w	d0,d3
	bge.s	copy_two_lines
	moveq	#20,d0
	subi.w	#$14,d4
copy_two_lines:
	subq.w	#1,d0
	move.w	#$c7,d2
	move.w	plane_masks,d6
	swap	d6
	move.w	plane_masks+2,d6
copy_two_line:
	movem.l	d0/d3,-(sp)
copy_two_word:
	move.l	(a1)+,(a0)
	and.l	d6,(a0)+
	clr.l	(a0)+
	dbra	d0,copy_two_word
	tst.w	d3
	beq.s	copy_two_next
	bmi.s	copy_two_skip
	tst.w	columns_drawn
	beq.s	copy_two_clear
	add.w	d3,d3
	add.w	d3,d3
	add.w	d3,d3
	adda.w	d3,a0
	bra.s	copy_two_next
copy_two_clear:
	subq.w	#1,d3
copy_two_clear_long:
	clr.l	(a0)+
	clr.l	(a0)+
	dbra	d3,copy_two_clear_long
	bra.s	copy_two_next
copy_two_skip:
	move.w	d4,d0
	add.w	d0,d0
	add.w	d0,d0
	adda.w	d0,a1
copy_two_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0/d3
	dbra	d2,copy_two_line
	rts

show_superposed_four:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_superposed_four
	tst.w	picture_columns_on
	beq.s	show_superposed_four_done
	move.w	picture_width,d0
	move.w	superposed_width,d1
	mulu.w	#$3,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	cmp.w	#$a0,d0
	bgt.s	show_superposed_four_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_superposed_four_columns:
	move.w	picture_width,d0
	move.w	superposed_width,d1
	mulu.w	#$3,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d2
	addi.l	#$a0,d2
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d2
	blt.s	show_superposed_four_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_superposed_four_width
	move.l	(sp)+,d7
	bra.s	show_superposed_four_columns
show_superposed_four_done:
	rts

;------------------------------------------------------------------------------
; copy_superposed_four and the other superposed copies: planes stored one after the other (each the width
; given), taken a word from each into the screen's interleaved planes.
;------------------------------------------------------------------------------
copy_superposed_four:	; from: show_superposed_four
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_superposed_four_width:	; from: show_superposed_four
	move.w	picture_width,d0
	move.w	superposed_width,d1
	lsr.w	#3,d1
	lsr.w	#4,d0
	move.w	d0,d4
	move.w	d0,d7
	lsr.w	#2,d0
	lsl.w	#2,d0
	sub.w	d0,d7
	lsr.w	#2,d0
	moveq	#20,d3
	sub.w	d0,d3
	bge.s	copy_superposed_four_extra
	moveq	#20,d0
	subi.w	#$50,d4
	moveq	#-1,d7
	bra.s	copy_superposed_four_lines
copy_superposed_four_extra:
	sub.w	d7,d3
	bge.s	copy_superposed_four_lines
	move.w	d3,d4
	not.w	d4
	sub.w	d4,d7
copy_superposed_four_lines:
	subq.w	#1,d0
	subq.w	#1,d7
	moveq	#0,d6
	move.w	plane_masks,d6
	swap	d6
	move.w	plane_masks+2,d6
	move.w	plane_masks+4,d5
	swap	d5
	move.w	plane_masks+6,d5
	move.w	#$c7,d2
copy_superposed_four_line:
	movem.l	d0-d1/d7,-(sp)
	move.l	a0,-(sp)
	movea.l	a1,a3
	adda.w	d1,a3
copy_superposed_four_word:
	move.w	(a1),(a0)
	lea	0(a1,d1.w),a5
	lea	2(a0),a6
	move.w	(a5),(a6)
	add.w	d1,d1
	and.l	d6,(a0)+
	lea	0(a1,d1.w),a5
	move.w	(a5),(a0)
	lsr.w	#1,d1
	mulu.w	#$3,d1
	lea	0(a1,d1.w),a5
	lea	2(a0),a6
	move.w	(a5),(a6)
	divu.w	#$3,d1
	addq.l	#2,a1
	and.l	d5,(a0)+
	cmpa.l	a1,a3
	bne.s	copy_superposed_four_more
	mulu.w	#$4,d0
	add.w	d0,d7
	bra.s	copy_superposed_four_rest
copy_superposed_four_more:
	dbra	d0,copy_superposed_four_word
copy_superposed_four_rest:
	adda.w	d1,a1
	adda.w	d1,a1
	adda.w	d1,a1
	tst.w	d7
	bmi.s	copy_superposed_four_clear
copy_superposed_four_last:
	move.w	(a1)+,(a0)
	move.w	plane_masks,d0
	and.w	d0,(a0)+
	clr.w	(a0)+
	clr.l	(a0)+
	dbra	d7,copy_superposed_four_last
copy_superposed_four_clear:
	movea.l	(sp)+,a0
	lea	$a0(a0),a0
	tst.w	d3
	bmi.s	copy_superposed_four_skip
	bra.s	copy_superposed_four_next
copy_superposed_four_skip:
	moveq	#0,d0
	move.w	d4,d0
	add.w	d0,d0
	adda.l	d0,a1
copy_superposed_four_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0-d1/d7
	dbra	d2,copy_superposed_four_line
	rts

show_two_superposed:	; from: show_picture
	bsr.w	copy_two_superposed
	tst.w	picture_columns_on
	beq.s	show_two_superposed_done
	move.w	picture_width,d0
	move.w	superposed_width,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	cmp.w	#$a0,d0
	bgt.s	show_two_superposed_done
	moveq	#0,d7
show_two_superposed_columns:
	move.w	picture_width,d0
	move.w	superposed_width,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d2
	addi.l	#$a0,d2
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d2
	blt.s	show_two_superposed_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_two_superposed_width
	move.l	(sp)+,d7
	bra.s	show_two_superposed_columns
show_two_superposed_done:
	rts

copy_two_superposed:	; from: show_two_superposed
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_two_superposed_width:	; from: show_two_superposed
	move.w	picture_width,d0
	move.w	superposed_width,d1
	lsr.w	#2,d1
	lsr.w	#4,d0
	move.w	plane_masks,d6
	swap	d6
	move.w	plane_masks+2,d6
	move.w	plane_masks+4,d5
	swap	d5
	move.w	plane_masks+6,d5
	move.w	#$c7,d2
copy_two_superposed_line:
	movea.l	a1,a3
	adda.w	d1,a3
	movem.l	d0/a0,-(sp)
	lea	$a0(a0),a2
copy_two_superposed_word:
	move.l	(a1),(a0)
	and.l	d6,(a0)+
	move.l	0(a1,d1.w),(a0)
	and.l	d5,(a0)+
	addq.l	#4,a1
	subq.w	#2,d0
	cmpa.l	a1,a3
	bne.s	copy_two_superposed_word
	adda.w	d1,a1
	tst.w	d0
	ble.s	copy_two_superposed_next
copy_two_superposed_last:
	move.l	(a1)+,(a0)
	and.l	d6,(a0)+
	clr.l	(a0)+
	subq.w	#1,d0
	cmpa.l	a0,a2
	beq.s	copy_two_superposed_skip
	tst.w	d0
	bne.s	copy_two_superposed_last
	bra.s	copy_two_superposed_next
copy_two_superposed_skip:
	mulu.w	#$4,d0
	adda.l	d0,a1
copy_two_superposed_next:
	movem.l	(sp)+,d0/a0
	adda.w	picture_modulo,a1
	lea	$a0(a0),a0
	dbra	d2,copy_two_superposed_line
	rts

show_superposed_three:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_superposed_three
	tst.w	picture_columns_on
	beq.s	show_superposed_three_done
	move.w	picture_width,d0
	move.w	superposed_width,d1
	mulu.w	#$2,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	cmp.w	#$a0,d0
	bgt.s	show_superposed_three_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_superposed_three_columns:
	move.w	picture_width,d0
	move.w	superposed_width,d1
	mulu.w	#$2,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d2
	addi.l	#$a0,d2
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d2
	blt.s	show_superposed_three_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_superposed_three_width
	move.l	(sp)+,d7
	bra.s	show_superposed_three_columns
show_superposed_three_done:
	rts

copy_superposed_three:	; from: show_superposed_three
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_superposed_three_width:	; from: show_superposed_three
	move.w	picture_width,d0
	move.w	superposed_width,d1
	lsr.w	#3,d1
	lsr.w	#4,d0
	move.w	d0,d4
	move.w	d0,d7
	andi.l	#$ffff,d0
	divu.w	#$3,d0
	mulu.w	#$3,d0
	sub.w	d0,d7
	divu.w	#$3,d0
	moveq	#20,d3
	sub.w	d0,d3
	bge.s	copy_superposed_three_extra
	moveq	#20,d0
	subi.w	#$3c,d4
	moveq	#-1,d7
	bra.s	copy_superposed_three_lines
copy_superposed_three_extra:
	sub.w	d7,d3
	bge.s	copy_superposed_three_lines
	move.w	d3,d4
	not.w	d4
	sub.w	d4,d7
copy_superposed_three_lines:
	subq.w	#1,d0
	subq.w	#1,d7
	moveq	#0,d6
	move.w	plane_masks,d6
	swap	d6
	move.w	plane_masks+2,d6
	move.w	plane_masks+4,d5
	swap	d5
	move.w	plane_masks+6,d5
	move.w	#$c7,d2
copy_superposed_three_line:
	movem.l	d0-d1/d7,-(sp)
	move.l	a0,-(sp)
	movea.l	a1,a3
	adda.w	d1,a3
copy_superposed_three_word:
	move.w	(a1),(a0)
	lea	0(a1,d1.w),a5
	lea	2(a0),a6
	move.w	(a5),(a6)
	add.w	d1,d1
	and.l	d6,(a0)+
	lea	0(a1,d1.w),a5
	move.w	(a5),(a0)
	lsr.w	#1,d1
	clr.w	2(a0)
	addq.l	#2,a1
	and.l	d5,(a0)+
	cmpa.l	a1,a3
	bne.s	copy_superposed_three_more
	mulu.w	#$3,d0
	add.w	d0,d7
	bra.s	copy_superposed_three_rest
copy_superposed_three_more:
	dbra	d0,copy_superposed_three_word
copy_superposed_three_rest:
	adda.w	d1,a1
	adda.w	d1,a1
	tst.w	d7
	bmi.s	copy_superposed_three_clear
copy_superposed_three_last:
	move.w	(a1)+,(a0)
	move.w	plane_masks,d0
	and.w	d0,(a0)+
	clr.w	(a0)+
	clr.l	(a0)+
	dbra	d7,copy_superposed_three_last
copy_superposed_three_clear:
	movea.l	(sp)+,a0
	lea	$a0(a0),a0
	tst.w	d3
	bmi.s	copy_superposed_three_skip
	bra.s	copy_superposed_three_next
copy_superposed_three_skip:
	moveq	#0,d0
	move.w	d4,d0
	add.w	d0,d0
	adda.l	d0,a1
copy_superposed_three_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0-d1/d7
	dbra	d2,copy_superposed_three_line
	rts

show_superposed_two:	; from: show_picture
	clr.w	columns_drawn
	bsr.w	copy_superposed_two
	tst.w	picture_columns_on
	beq.s	show_superposed_two_done
	move.w	picture_width,d0
	move.w	superposed_width,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	cmp.w	#$a0,d0
	bgt.s	show_superposed_two_done
	move.w	#$1,columns_drawn
	moveq	#0,d7
show_superposed_two_columns:
	move.w	picture_width,d0
	move.w	superposed_width,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	add.w	d0,d7
	move.l	picture_screen,d2
	addi.l	#$a0,d2
	move.l	picture_screen,d6
	add.w	d7,d6
	add.w	d0,d6
	sub.l	d6,d2
	blt.s	show_superposed_two_done
	movea.l	picture_screen,a0
	adda.w	d7,a0
	move.l	d7,-(sp)
	bsr.w	copy_superposed_two_width
	move.l	(sp)+,d7
	bra.s	show_superposed_two_columns
show_superposed_two_done:
	rts

copy_superposed_two:	; from: show_superposed_two
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_superposed_two_width:	; from: show_superposed_two
	move.w	picture_width,d0
	move.w	superposed_width,d1
	lsr.w	#3,d1
	lsr.w	#4,d0
	move.w	d0,d4
	move.w	d0,d7
	lsr.w	#1,d0
	lsl.w	#1,d0
	sub.w	d0,d7
	lsr.w	#1,d0
	moveq	#20,d3
	sub.w	d0,d3
	bge.s	copy_superposed_two_extra
	moveq	#20,d0
	subi.w	#$28,d4
	moveq	#-1,d7
	bra.s	copy_superposed_two_lines
copy_superposed_two_extra:
	sub.w	d7,d3
	bge.s	copy_superposed_two_lines
	move.w	d3,d4
	not.w	d4
	sub.w	d4,d7
copy_superposed_two_lines:
	subq.w	#1,d0
	subq.w	#1,d7
	moveq	#0,d6
	move.w	plane_masks,d6
	swap	d6
	move.w	plane_masks+2,d6
	move.w	plane_masks+4,d5
	swap	d5
	move.w	plane_masks+6,d5
	move.w	#$c7,d2
copy_superposed_two_line:
	movem.l	d0-d1/d7,-(sp)
	move.l	a0,-(sp)
	movea.l	a1,a3
	adda.w	d1,a3
copy_superposed_two_word:
	move.w	(a1),(a0)
	lea	0(a1,d1.w),a5
	lea	2(a0),a6
	move.w	(a5),(a6)
	and.l	d6,(a0)+
	clr.l	(a0)+
	addq.l	#2,a1
	cmpa.l	a1,a3
	bne.s	copy_superposed_two_more
	mulu.w	#$2,d0
	add.w	d0,d7
	bra.s	copy_superposed_two_rest
copy_superposed_two_more:
	dbra	d0,copy_superposed_two_word
copy_superposed_two_rest:
	adda.w	d1,a1
	tst.w	d7
	bmi.s	copy_superposed_two_clear
copy_superposed_two_last:
	move.w	(a1)+,(a0)
	move.w	plane_masks,d0
	and.w	d0,(a0)+
	clr.w	(a0)+
	clr.l	(a0)+
	dbra	d7,copy_superposed_two_last
copy_superposed_two_clear:
	movea.l	(sp)+,a0
	lea	$a0(a0),a0
	tst.w	d3
	bmi.s	copy_superposed_two_skip
	bra.s	copy_superposed_two_next
copy_superposed_two_skip:
	moveq	#0,d0
	move.w	d4,d0
	add.w	d0,d0
	adda.l	d0,a1
copy_superposed_two_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0-d1/d7
	dbra	d2,copy_superposed_two_line
	rts

copy_one:	; from: show_one
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_one_width:	; from: show_one
	move.w	picture_width,d0
	lsr.w	#4,d0
	move.w	d0,d4
	moveq	#20,d3
	sub.w	d0,d3
	bge.s	copy_one_lines
	moveq	#20,d0
	subi.w	#$14,d4
copy_one_lines:
	subq.w	#1,d0
	moveq	#0,d6
	move.w	plane_masks,d6
	swap	d6
	move.w	#$c7,d2
copy_one_line:
	movem.l	d0/d3,-(sp)
copy_one_word:
	move.w	(a1)+,(a0)
	and.l	d6,(a0)+
	clr.l	(a0)+
	dbra	d0,copy_one_word
	tst.w	d3
	beq.s	copy_one_next
	bmi.s	copy_one_skip
	tst.w	columns_drawn
	beq.s	copy_one_clear
	add.w	d3,d3
	add.w	d3,d3
	add.w	d3,d3
	adda.w	d3,a0
	bra.s	copy_one_next
copy_one_clear:
	subq.w	#1,d3
copy_one_clear_long:
	clr.l	(a0)+
	clr.l	(a0)+
	dbra	d3,copy_one_clear_long
	bra.s	copy_one_next
copy_one_skip:
	moveq	#0,d0
	move.w	d4,d0
	add.w	d0,d0
	adda.l	d0,a1
copy_one_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0/d3
	dbra	d2,copy_one_line
	rts

copy_medium_two:	; from: show_medium_two
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_medium_two_width:	; from: show_medium_two
	move.w	picture_width,d0
	lsr.w	#4,d0
	move.w	d0,d4
	moveq	#40,d3
	sub.w	d0,d3
	bge.s	copy_medium_two_lines
	moveq	#40,d0
	subi.w	#$28,d4
copy_medium_two_lines:
	subq.w	#1,d0
	move.w	plane_masks,d6
	swap	d6
	move.w	plane_masks+2,d6
	move.w	#$c7,d2
copy_medium_two_line:
	movem.l	d0/d3,-(sp)
copy_medium_two_word:
	move.l	(a1)+,(a0)
	and.l	d6,(a0)+
	dbra	d0,copy_medium_two_word
	tst.w	d3
	beq.s	copy_medium_two_next
	bmi.s	copy_medium_two_skip
	tst.w	columns_drawn
	beq.s	copy_medium_two_clear
	add.w	d3,d3
	add.w	d3,d3
	adda.w	d3,a0
	bra.s	copy_medium_two_next
copy_medium_two_clear:
	subq.w	#1,d3
copy_medium_two_clear_long:
	clr.l	(a0)+
	dbra	d3,copy_medium_two_clear_long
	bra.s	copy_medium_two_next
copy_medium_two_skip:
	move.w	d4,d0
	add.w	d0,d0
	add.w	d0,d0
	adda.w	d0,a1
copy_medium_two_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0/d3
	dbra	d2,copy_medium_two_line
	rts

copy_medium_one:	; from: show_medium_one
	movea.l	picture_screen,a0
	movea.l	memory_address,a1

copy_medium_one_width:	; from: show_medium_one
	move.w	picture_width,d0
	lsr.w	#4,d0
	move.w	d0,d4
	moveq	#40,d3
	sub.w	d0,d3
	bge.s	copy_medium_one_lines
	moveq	#40,d0
	subi.w	#$28,d4
copy_medium_one_lines:
	subq.w	#1,d0
	moveq	#0,d6
	move.w	plane_masks,d6
	swap	d6
	move.w	#$c7,d2
copy_medium_one_line:
	movem.l	d0/d3,-(sp)
copy_medium_one_word:
	move.w	(a1)+,(a0)
	and.l	d6,(a0)+
	dbra	d0,copy_medium_one_word
	tst.w	d3
	beq.s	copy_medium_one_next
	bmi.s	copy_medium_one_skip
	tst.w	columns_drawn
	beq.s	copy_medium_one_clear
	add.w	d3,d3
	add.w	d3,d3
	adda.w	d3,a0
	bra.s	copy_medium_one_next
copy_medium_one_clear:
	subq.w	#1,d3
copy_medium_one_clear_long:
	clr.l	(a0)+
	dbra	d3,copy_medium_one_clear_long
	bra.s	copy_medium_one_next
copy_medium_one_skip:
	move.w	d4,d0
	add.w	d0,d0
	adda.w	d0,a1
copy_medium_one_next:
	adda.w	picture_modulo,a1
	movem.l	(sp)+,d0/d3
	dbra	d2,copy_medium_one_line
	rts

;------------------------------------------------------------------------------
; disk_utility (F3): DISK UTILITY: F1 the directory, F2 a new path, F3 rename, F4 format, F5 delete, F6 create a
; folder, F7 the free space, F10 back.  The path is shown as "PATH = A:\*.*".
;------------------------------------------------------------------------------
disk_utility:	; from: modules, info
	lea	text_disk_utility_f1,a0         ; its title
	bsr.w	print
	moveq	#0,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#25,d7
	bsr.w	draw_box                        ; the top box
	moveq	#27,d4
	moveq	#0,d5
	move.w	#$27f,d6
	move.w	#$c7,d7
	bsr.w	draw_box                        ; the box
disk_utility_menu:	; from: set_path, new_path, show_directory, list_files_page_full, format_disk
	bsr.w	show_path                       ; the path shown
disk_utility_key:	; from: free_space
	bsr.w	get_key                         ; a key
	cmp.b	#$3,d0                          ; Control C?
	bne.s	disk_utility_function           ; no
	moveq	#3,d0                           ; the calculator, then here
	jmp	run_module
disk_utility_function:
	moveq	#3,d1
	jsr	module_keys                     ; the module keys
	swap	d0
	cmp.w	#$3b,d0                         ; F1?
	beq.w	show_directory                  ; the directory
	cmp.w	#$3c,d0                         ; F2?
	beq.w	new_path                        ; the path
	cmp.w	#$3d,d0                         ; F3?
	beq.w	rename_file                     ; rename
	cmp.w	#$3e,d0                         ; F4?
	beq.w	format_disk                     ; format
	cmp.w	#$3f,d0                         ; F5?
	beq.w	delete_file                     ; delete
	cmp.w	#$40,d0                         ; F6?
	beq.w	create_folder                   ; create a folder
	cmp.w	#$41,d0                         ; F7?
	beq.w	free_space                      ; the free space
	cmp.w	#$44,d0                         ; F10?
	bne.w	disk_utility_menu               ; no: another key
	rts

;------------------------------------------------------------------------------
; show_path: "PATH = " and the path.
;------------------------------------------------------------------------------
show_path:	; from: disk_utility
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	path_line,a0                    ; the path's text
	clr.b	$54(a0)                         ; ended
	bsr.w	print
	rts

;------------------------------------------------------------------------------
; set_path: the drive and folder of the path made current (Dsetdrv, Dsetpath), the "*.*" taken off for it and
; put back.
;------------------------------------------------------------------------------
set_path:	; from: free_space, rename_file, create_folder, delete_file, show_directory
	lea	path,a0                         ; the path
set_path_find:
	cmpi.b	#$2a,(a0)+                      ; '*'?
	bne.s	set_path_find                   ; no
	cmpi.b	#$2e,(a0)                       ; '.' after it?
	bne.s	set_path_find                   ; no
	move.b	#$0,-(a0)                       ; cut there
	lea	path,a1                         ; the drive
	moveq	#0,d0
	move.b	(a1),d0
	subi.b	#$41,d0                         ; letter to number
	cmp.b	#$10,d0                         ; below 16?
	blt.s	set_path_drive                  ; yes
	moveq	#0,d0                           ; else A
	move.b	#$41,(a1)
set_path_drive:
	move.w	d0,-(sp)
	move.w	#$e,-(sp)
	trap	#1                              ; Dsetdrv
	addq.l	#4,sp
	tst.w	d0                              ; an error?
	bmi.w	set_path_error                  ; yes
	pea	path                            ; the path
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.w	d0                              ; an error?
	bmi.w	set_path_error                  ; yes
	lea	path,a0
set_path_end:
	cmpi.b	#$0,(a0)+                       ; to its end
	bne.s	set_path_end
	move.b	#$2a,-(a0)                      ; the '*' back
	rts
set_path_error:
	jsr	show_gemdos_error               ; shown
	rts
disk_utility_error:	; from: free_space, rename_file, create_folder, delete_file, new_path, show_directory, 1 more
	jsr	show_gemdos_error               ; shown
	bra.w	disk_utility_menu               ; the menu

;------------------------------------------------------------------------------
; free_space (F7): "FREE SPACE :" the free clusters (Dfree) in decimal.
;------------------------------------------------------------------------------
free_space:	; from: disk_utility
	bsr.w	set_path                        ; the path set
	clr.w	-(sp)                           ; the current drive
	move.l	#disk_buffer,-(sp)              ; the buffer
	move.w	#$36,-(sp)
	trap	#1                              ; Dfree
	addq.l	#8,sp
	tst.w	d0                              ; an error?
	bmi.w	disk_utility_error              ; yes
	lea	disk_buffer,a0
	move.l	(a0),d0                         ; the free clusters
	bsr.w	to_decimal_digits               ; in decimal
	movea.l	d4,a6
	lea	hex_text,a4
	lea	hex_digits,a5
	bsr.w	put_hex_address                 ; in hex
	clr.b	(a4)
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_free_space,a0              ; "FREE SPACE : "
	bsr.w	print
	lea	hex_text+2,a0                   ; the number
	bsr.w	print
	lea	text_k_bytes,a0
	bsr.w	print
	bra.w	disk_utility_key

;------------------------------------------------------------------------------
; rename_file (F3): "ENTER SOURCE NAME :" and "ENTER NEW NAME :", then Frename, then the directory.
;------------------------------------------------------------------------------
rename_file:	; from: disk_utility
	bsr.w	set_path                        ; the path set
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_enter_source_name,a0       ; "ENTER SOURCE NAME : "
	bsr.w	print
	lea	disk_buffer,a0                  ; the buffer
	moveq	#100,d0                         ; 100 bytes
rename_file_clear:
	clr.b	(a0)+                           ; cleared
	dbra	d0,rename_file_clear
	lea	disk_buffer,a0
	move.w	#$3a00,(a0)                     ; 58 characters
	move.l	#disk_buffer,-(sp)
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.s	rename_file_done                ; no
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_enter_new_name,a0          ; "ENTER NEW NAME : "
	bsr.w	print
	lea	disk_buffer,a0
	adda.l	#$c8,a0                         ; the second line
	moveq	#100,d0                         ; 100 bytes
rename_file_clear_new:
	clr.b	(a0)+                           ; cleared
	dbra	d0,rename_file_clear_new
	lea	disk_buffer,a0
	adda.l	#$c8,a0
	move.w	#$3a00,(a0)                     ; 58 characters
	lea	disk_buffer,a0
	lea	$c8(a0),a0
	move.l	a0,-(sp)
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.s	rename_file_done                ; no
	lea	disk_buffer,a0
	lea	$ca(a0),a0                      ; the new name
	lea	disk_buffer,a1
	addq.l	#2,a1                           ; the old name
	move.l	a0,-(sp)
	move.l	a1,-(sp)
	clr.w	-(sp)
	move.w	#$56,-(sp)
	trap	#1                              ; Frename
	lea	$c(sp),sp
	tst.w	d0                              ; an error?
	bmi.w	disk_utility_error              ; yes
rename_file_done:
	bra.w	show_directory                  ; the directory

;------------------------------------------------------------------------------
; create_folder (F6): "ENTER NEW FOLDER :", then Dcreate, then the directory.
;------------------------------------------------------------------------------
create_folder:	; from: disk_utility
	bsr.w	set_path                        ; the path set
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_enter_new_folder,a0        ; "ENTER NEW FOLDER : "
	bsr.w	print
	lea	disk_buffer,a0                  ; the buffer
	move.w	#$c00,(a0)+                     ; 12 characters
	moveq	#100,d0                         ; 100 bytes
create_folder_clear:
	clr.b	(a0)+                           ; cleared
	dbra	d0,create_folder_clear
	move.l	#disk_buffer,-(sp)
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.w	d0                              ; any?
	ble.s	create_folder_done              ; no
	lea	disk_buffer,a0
	lea	2(a0),a0                        ; the name
	move.l	a0,-(sp)
	move.w	#$39,-(sp)
	trap	#1                              ; Dcreate
	addq.l	#6,sp
	tst.w	d0                              ; an error?
	bmi.w	disk_utility_error              ; yes
create_folder_done:
	bra.w	show_directory                  ; the directory

;------------------------------------------------------------------------------
; delete_file (F5): "ENTER FILE TO ERASE :", "CONFIRM (y/n)?", then Fdelete, then the directory.
;------------------------------------------------------------------------------
delete_file:	; from: disk_utility
	bsr.w	set_path                        ; the path set
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_enter_file_to,a0           ; "ENTER FILE TO ERASE :"
	bsr.w	print
	lea	disk_buffer,a0                  ; the buffer
	moveq	#100,d0                         ; 100 bytes
delete_file_clear:
	clr.b	(a0)+                           ; cleared
	dbra	d0,delete_file_clear
	lea	disk_buffer,a0
	move.w	#$3000,(a0)                     ; 48 characters
	move.l	#disk_buffer,-(sp)
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	delete_file_done                ; no
	bsr.w	ask_confirm                     ; sure?
	tst.l	d0                              ; no
	bmi.s	delete_file_done
	lea	disk_buffer,a0
	addq.l	#2,a0                           ; the name
	move.l	a0,-(sp)
	move.w	#$41,-(sp)
	trap	#1                              ; Fdelete
	addq.l	#6,sp
	tst.w	d0                              ; an error?
	bmi.w	disk_utility_error              ; yes
delete_file_done:
	bra.w	show_directory                  ; the directory

;------------------------------------------------------------------------------
; ask_confirm: "CONFIRM (y/n)?": d0 0 for yes, -1 for no.
;------------------------------------------------------------------------------
ask_confirm:	; from: delete_file, format_disk
	lea	text_confirm_y_n,a0
	bsr.w	print
ask_confirm_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$79,d0                         ; 'y'?
	beq.s	ask_confirm_yes
	cmp.b	#$59,d0                         ; 'Y'?
	beq.s	ask_confirm_yes
	cmp.b	#$6e,d0                         ; 'n'?
	beq.s	ask_confirm_no
	cmp.b	#$4e,d0                         ; 'N'?
	beq.s	ask_confirm_no
	bra.s	ask_confirm_key                 ; another key
ask_confirm_yes:
	moveq	#0,d0
	rts
ask_confirm_no:
	moveq	#-1,d0
	rts

;------------------------------------------------------------------------------
; new_path (F2): "ENTER NEW PATH :": a drive (if there) and a folder, set and kept with "\*.*", then the
; directory.
;------------------------------------------------------------------------------
new_path:	; from: disk_utility
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_enter_new_path,a0          ; "ENTER NEW PATH : "
	bsr.w	print
	lea	disk_buffer,a0                  ; the buffer
	move.w	#$3800,(a0)+                    ; 56 characters
	moveq	#100,d0                         ; 100 bytes
new_path_clear:
	clr.b	(a0)+                           ; cleared
	dbra	d0,new_path_clear
	move.l	#disk_buffer,-(sp)
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.w	d0                              ; any?
	ble.w	new_path_done                   ; no
	lea	disk_buffer,a0
	addq.l	#2,a0                           ; the path typed
	cmpi.b	#$3a,1(a0)                      ; a drive?
	bne.s	new_path_set                    ; no
	move.b	(a0),d0                         ; its letter
	cmp.b	#$61,d0                         ; small?
	blt.s	new_path_drive                  ; no
	subi.b	#$20,d0                         ; in capitals
	move.b	d0,(a0)
new_path_drive:
	cmp.b	#$41,d0                         ; A-P?
	blt.w	new_path_done
	cmp.b	#$50,d0
	bgt.w	new_path_done
	move.l	a0,-(sp)
	moveq	#0,d1
	subi.b	#$41,d0
	move.w	d0,d3
	move.w	#$a,-(sp)
	trap	#13                             ; Drvmap
	addq.l	#2,sp
	movea.l	(sp)+,a0
	btst	d3,d0                           ; there?
	beq.w	new_path_done                   ; no
new_path_set:
	move.l	a0,-(sp)
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.w	d0                              ; an error?
	bmi.w	disk_utility_error              ; yes
	lea	path,a1                         ; the kept path
	cmpi.b	#$3a,1(a0)                      ; with a drive?
	beq.s	new_path_copy                   ; yes: all of it
	cmpi.b	#$5c,(a0)                       ; from the root?
	bne.s	new_path_append                 ; no
	addq.l	#2,a1                           ; after "A:"
	bra.s	new_path_copy
new_path_append:
	cmpi.b	#$2a,(a1)+                      ; to the "*"
	bne.s	new_path_append
	subq.l	#1,a1
new_path_copy:
	move.b	(a0)+,d0
	cmp.b	#$61,d0                         ; small?
	blt.s	new_path_put                    ; no
	subi.b	#$20,d0                         ; in capitals
new_path_put:
	move.b	d0,(a1)+
	bne.s	new_path_copy
	subq.l	#2,a1
	cmpi.b	#$5c,(a1)+                      ; a '\' at the end?
	beq.s	new_path_mask                   ; yes
	move.b	#$5c,(a1)+                      ; '\'
new_path_mask:
	move.b	#$2a,(a1)+                      ; "*.*"
	move.b	#$2e,(a1)+
	move.b	#$2a,(a1)+
	move.b	#$0,(a1)+                       ; ended
	bra.s	show_directory
new_path_done:
	bra.w	disk_utility_menu

;------------------------------------------------------------------------------
; show_directory (F1): the files of the path listed, four to a line: volume labels, folders, files, read-only,
; hidden and system files in turn, each marked (<Lab>, <Dir>, <___>, <Pro>, <Hid>, <Sys>); SPACE for the next page,
; ESC to stop.
;------------------------------------------------------------------------------
show_directory:	; from: disk_utility, rename_file, create_folder, delete_file, new_path
	bsr.w	set_path                        ; the path set
	pea	dta                             ; the DTA
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.l	#6,sp
	tst.w	d0
	bmi.w	disk_utility_error
	lea	disk_buffer,a6                  ; the text: cursor off, ESC Y row 4 column 4
	move.b	#$1b,(a6)+
	move.b	#$66,(a6)+
	move.b	#$1b,(a6)+
	move.b	#$59,(a6)+
	move.b	#$24,(a6)+
	move.b	#$24,(a6)+
	movea.l	a6,a0
	moveq	#19,d1                          ; 20 lines
show_directory_line:
	moveq	#74,d0                          ; 75 spaces
show_directory_space:
	move.b	#$20,(a0)+
	dbra	d0,show_directory_space
	move.b	#$b,(a0)+                       ; $0B, CR, 4 right
	move.b	#$d,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	dbra	d1,show_directory_line
	move.b	#$0,(a0)+                       ; ended
	moveq	#0,d7                           ; the column
	moveq	#0,d6                           ; the count
	move.w	#$8,dir_attribute               ; volume labels
	bsr.w	list_files                      ; listed
	move.w	#$10,dir_attribute              ; folders
	bsr.w	list_files
	move.w	#$0,dir_attribute               ; files
	bsr.w	list_files
	move.w	#$1,dir_attribute               ; read-only
	bsr.w	list_files
	move.w	#$2,dir_attribute               ; hidden
	bsr.w	list_files
	move.w	#$4,dir_attribute               ; system
	bsr.w	list_files
	lea	disk_buffer,a0                  ; the text
	bsr.w	print                           ; printed
	bra.w	disk_utility_menu

;------------------------------------------------------------------------------
; list_files: the files with the attribute dir_attribute put in the text, 13 columns each; a page full shows it.
;------------------------------------------------------------------------------
list_files:	; from: show_directory
	move.w	dir_attribute,-(sp)             ; the attribute
	pea	path                            ; the path
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.w	d0
	bmi.w	list_files_done                 ; none?
list_files_next:
	lea	dta+30,a0                       ; its name
	move.b	dta+21,d0                       ; its attribute
	andi.w	#$1f,d0
	cmp.w	dir_attribute,d0                ; the one wanted?
	bne.w	list_files_more                 ; no
	cmpi.w	#$10,dir_attribute              ; a folder?
	bne.s	list_files_label                ; no
	move.b	#$3c,(a6)+                      ; "<Dir>"
	move.b	#$44,(a6)+
	move.b	#$69,(a6)+
	move.b	#$72,(a6)+
	move.b	#$3e,(a6)+
list_files_label:
	cmpi.w	#$8,dir_attribute               ; a label?
	bne.s	list_files_plain                ; no
	move.b	#$3c,(a6)+                      ; "<Lab>"
	move.b	#$4c,(a6)+
	move.b	#$61,(a6)+
	move.b	#$62,(a6)+
	move.b	#$3e,(a6)+
list_files_plain:
	cmpi.w	#$0,dir_attribute               ; a file?
	bne.s	list_files_read_only            ; no
	move.b	#$3c,(a6)+                      ; "<___>"
	move.b	#$5f,(a6)+
	move.b	#$5f,(a6)+
	move.b	#$5f,(a6)+
	move.b	#$3e,(a6)+
list_files_read_only:
	cmpi.w	#$1,dir_attribute               ; read-only?
	bne.s	list_files_hidden               ; no
	move.b	#$3c,(a6)+                      ; "<Pro>"
	move.b	#$50,(a6)+
	move.b	#$72,(a6)+
	move.b	#$6f,(a6)+
	move.b	#$3e,(a6)+
list_files_hidden:
	cmpi.w	#$2,dir_attribute               ; hidden?
	bne.s	list_files_system               ; no
	move.b	#$3c,(a6)+                      ; "<Hid>"
	move.b	#$48,(a6)+
	move.b	#$69,(a6)+
	move.b	#$64,(a6)+
	move.b	#$3e,(a6)+
list_files_system:
	cmpi.w	#$4,dir_attribute               ; system?
	bne.s	list_files_name                 ; no
	move.b	#$3c,(a6)+                      ; "<Sys>"
	move.b	#$53,(a6)+
	move.b	#$79,(a6)+
	move.b	#$73,(a6)+
	move.b	#$3e,(a6)+
list_files_name:
	movea.l	a6,a1
list_files_copy:
	move.b	(a0)+,(a1)+                     ; the name
	bne.s	list_files_copy
	move.b	#$20,-(a1)                      ; a space for its 0
	lea	$d(a6),a6                       ; 13 on
	addq.w	#1,d7                           ; the column
	addq.w	#1,d6                           ; the count
	cmp.b	#$4,d7                          ; four?
	bne.s	list_files_page                 ; no
	moveq	#0,d7                           ; the next line
	lea	$d(a6),a6
list_files_page:
	cmp.b	#$4c,d6                         ; 76?
	blt.s	list_files_more                 ; no
	bsr.w	list_files_page_full            ; a page
list_files_more:
	move.w	#$4f,-(sp)
	trap	#1                              ; Fsnext
	addq.l	#2,sp
	tst.l	d0                              ; another?
	bge.w	list_files_next                 ; yes
list_files_done:
	rts

;------------------------------------------------------------------------------
; list_files_page_full: the page printed, "<ESC> TO EXIT <SPACE> TO CONTINUE"; ESC goes back to the menu (the
; caller's return dropped), SPACE starts a new page.
;------------------------------------------------------------------------------
list_files_page_full:	; from: list_files
	lea	disk_buffer,a0                  ; the page
	bsr.w	print
	lea	text_esc_to_exit,a0
	bsr.w	print
list_files_page_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$20,d0                         ; Space?
	beq.s	list_files_new_page             ; yes
	cmp.b	#$1b,d0                         ; ESC?
	bne.s	list_files_page_key             ; no
	addq.l	#8,sp                           ; out of list_files
	lea	position_23_1_at_e317,a0        ; the line cleared
	bsr.w	print
	bra.w	disk_utility_menu               ; the menu
list_files_new_page:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	position_23_1_at_e317,a0        ; the line cleared
	bsr.w	print
	movem.l	(sp)+,d0-d7/a0-a6
	lea	disk_buffer,a6                  ; the text again
	move.b	#$1b,(a6)+
	move.b	#$66,(a6)+
	move.b	#$1b,(a6)+
	move.b	#$59,(a6)+
	move.b	#$24,(a6)+
	move.b	#$24,(a6)+
	movea.l	a6,a0
	moveq	#19,d1                          ; 20 lines
list_files_new_line:
	moveq	#74,d0                          ; 75 spaces
list_files_new_space:
	move.b	#$20,(a0)+
	dbra	d0,list_files_new_space
	move.b	#$b,(a0)+                       ; $0B, CR, 4 right
	move.b	#$d,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	move.b	#$1b,(a0)+
	move.b	#$43,(a0)+
	dbra	d1,list_files_new_line
	move.b	#$0,(a0)+                       ; ended
	moveq	#0,d7
	moveq	#0,d6
	rts

;------------------------------------------------------------------------------
; format_track: the track format_track_number formatted (Flopfmt, 9 sectors, $87654321), side 1 too if two
; sides.
;------------------------------------------------------------------------------
format_track:	; from: format_disk
	move.w	#$0,-(sp)                       ; the fill value
	move.l	#$87654321,-(sp)                ; the magic
	move.w	#$1,-(sp)                       ; interleave 1
	move.w	#$0,-(sp)                       ; side 0
	move.w	format_track_number,-(sp)       ; the track
	move.w	#$9,-(sp)                       ; 9 sectors
	move.w	#$0,-(sp)                       ; drive A
	clr.l	-(sp)
	move.l	#disk_buffer,-(sp)              ; the buffer
	move.w	#$a,-(sp)
	trap	#14                             ; Flopfmt, XBIOS
	lea	$1a(sp),sp
	tst.l	d0                              ; an error?
	bmi.s	format_track_done               ; yes
	tst.w	format_two_sides                ; two sides?
	beq.s	format_track_done               ; no
	move.w	#$0,-(sp)                       ; side 1
	move.l	#$87654321,-(sp)
	move.w	#$1,-(sp)
	move.w	#$1,-(sp)
	move.w	format_track_number,-(sp)
	move.w	#$9,-(sp)
	move.w	#$0,-(sp)
	clr.l	-(sp)
	move.l	#disk_buffer,-(sp)
	move.w	#$a,-(sp)
	trap	#14                             ; Flopfmt, XBIOS
	lea	$1a(sp),sp
format_track_done:
	rts

;------------------------------------------------------------------------------
; write_boot_and_fats: a boot sector made (Protobt, random serial, 1 or 2 sides), the media byte $F8 for one
; side, 3 sectors a FAT; written, then the two FATs' first sectors.
;------------------------------------------------------------------------------
write_boot_and_fats:	; from: format_disk
	move.w	#$11,-(sp)
	trap	#14                             ; Random, XBIOS
	addq.l	#2,sp
	move.l	d0,d1                           ; the serial
	clr.w	-(sp)                           ; not executable
	move.w	format_two_sides,d0             ; the sides
	addq.w	#2,d0                           ; the disk type (2 or 3)
	move.w	d0,-(sp)
	move.l	d1,-(sp)
	move.l	#disk_buffer,-(sp)              ; the buffer
	move.w	#$12,-(sp)
	trap	#14                             ; Protobt, XBIOS
	lea	$e(sp),sp
	tst.l	d0                              ; an error?
	bmi.w	write_boot_and_fats_done        ; yes
	tst.w	format_two_sides                ; two sides?
	bne.s	write_boot_and_fats_spf         ; yes
	move.b	#$f8,disk_buffer+21             ; the media byte $F8
write_boot_and_fats_spf:
	move.b	#$3,disk_buffer+22              ; 3 sectors a FAT
	move.w	#$1,-(sp)                       ; 1 sector
	move.w	#$0,-(sp)                       ; side 0
	move.w	#$0,-(sp)                       ; track 0
	move.w	#$1,-(sp)                       ; sector 1
	move.w	#$0,-(sp)                       ; drive A
	clr.l	-(sp)
	move.l	#disk_buffer,-(sp)              ; the boot sector
	move.w	#$9,-(sp)
	trap	#14                             ; Flopwr, XBIOS
	lea	$14(sp),sp
	lea	disk_buffer,a0
	move.w	#$1ff,d0                        ; 512 bytes
write_boot_and_fats_clear:
	clr.b	(a0)+                           ; cleared
	dbra	d0,write_boot_and_fats_clear
	lea	disk_buffer,a0
	move.l	#$f9ffff00,(a0)                 ; the FAT's start
	tst.w	format_two_sides                ; two sides?
	bne.s	write_boot_and_fats_fat         ; yes
	move.l	#$f8ffff00,(a0)                 ; one side: $F8
write_boot_and_fats_fat:
	move.w	#$1,-(sp)                       ; 1 sector
	move.w	#$0,-(sp)
	move.w	#$0,-(sp)
	move.w	#$2,-(sp)                       ; sector 2
	move.w	#$0,-(sp)
	clr.l	-(sp)
	move.l	#disk_buffer,-(sp)
	move.w	#$9,-(sp)
	trap	#14                             ; Flopwr, the first FAT
	lea	$14(sp),sp
	move.w	#$1,-(sp)                       ; 1 sector
	move.w	#$0,-(sp)
	move.w	#$0,-(sp)
	move.w	#$4,-(sp)                       ; sector 4
	move.w	#$0,-(sp)
	clr.l	-(sp)
	move.l	#disk_buffer,-(sp)
	move.w	#$9,-(sp)
	trap	#14                             ; Flopwr, the second FAT
	lea	$14(sp),sp
write_boot_and_fats_done:
	rts

;------------------------------------------------------------------------------
; format_disk (F4): "NUMBER OF SIDES :" 1 or 2, "ENTER DISK TO FORMAT IN DRIVE A", confirm, then 80 tracks
; formatted and the boot sector and FATs written.
;------------------------------------------------------------------------------
format_disk:	; from: disk_utility
	clr.w	format_two_sides                ; one side
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_number_of_sides,a0         ; "NUMBER OF SIDES : "
	bsr.w	print
format_disk_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d0                         ; ESC?
	beq.w	disk_utility_menu               ; yes
	cmp.b	#$31,d0                         ; '1'?
	beq.s	format_disk_confirm             ; yes
	cmp.b	#$32,d0                         ; '2'?
	bne.s	format_disk_key                 ; no: another key
	move.w	#$1,format_two_sides            ; two sides
format_disk_confirm:
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_enter_disk_to,a0           ; "ENTER DISK TO FORMAT IN DRIVE A"
	bsr.w	print
	bsr.w	ask_confirm                     ; sure?
	tst.l	d0
	bmi.w	disk_utility_menu               ; no
	lea	position_2_1,a0                 ; the line cleared
	bsr.w	print
	lea	text_please_wait_formating,a0   ; "PLEASE WAIT ...FORMATING..."
	bsr.w	print
	clr.w	format_track_number             ; track 0
	moveq	#79,d7                          ; 80 tracks
format_disk_track:
	bsr.w	format_track                    ; formatted
	tst.l	d0                              ; an error?
	bmi.w	disk_utility_error              ; yes
	addq.w	#1,format_track_number          ; the next
	dbra	d7,format_disk_track
	bsr.w	write_boot_and_fats             ; the boot sector and FATs
	tst.l	d0                              ; an error?
	bmi.w	disk_utility_error              ; yes
	bra.w	disk_utility_menu

;------------------------------------------------------------------------------
; external_loader (F5): EXTERNAL LOADER: F1 LOAD FILE (a file read to an address), F2 LOAD TRACK (tracks read
; straight from the floppy controller to an address), F10 back.
;------------------------------------------------------------------------------
external_loader:	; from: modules, info
	lea	text_external_loader_f1,a0      ; its title
	bsr.w	print
	moveq	#0,d4
	moveq	#0,d5
	move.w	#$27f,d6
	moveq	#22,d7
	bsr.w	draw_box                        ; the top box
	moveq	#40,d4
	move.w	#$dc,d5
	move.w	#$1a4,d6
	moveq	#98,d7
	bsr.w	draw_box                        ; the menu's box
external_loader_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$3,d0                          ; Control C?
	bne.s	external_loader_function        ; no
	moveq	#5,d0                           ; the calculator, then here
	jmp	run_module
external_loader_function:
	moveq	#5,d1
	jsr	module_keys                     ; the module keys
	swap	d0
	cmp.b	#$3b,d0                         ; F1?
	beq.w	load_file                       ; load a file
	cmp.b	#$3c,d0                         ; F2?
	beq.w	load_tracks                     ; load tracks
	cmp.b	#$44,d0                         ; F10?
	bne.s	external_loader_key             ; no: another key
	rts
load_file:
	lea	text_enter_filename,a0          ; "ENTER FILENAME : "
	bsr.w	print
	move.w	#$3d00,name_buffer              ; 61 characters
	pea	name_buffer
	move.w	#$a,-(sp)
	bsr.w	input_line                      ; typed
	addq.l	#6,sp
	tst.l	d0                              ; any?
	ble.w	external_loader                 ; no
	lea	text_enter_buffer_address,a0    ; "ENTER BUFFER ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	tst.l	d0                              ; given?
	bmi.w	external_loader                 ; no
	lea	text_please_wait_loading,a0     ; "PLEASE WAIT ... LOADING ..."
	bsr.w	print
	lea	name_buffer+2,a0                ; the name
	movea.l	d2,a1                           ; the address
	move.l	d2,memory_address               ; the memory address too
	move.l	#$900000,d2                     ; up to 9 Mb
	bsr.w	read_file                       ; read
	bra.w	external_loader
load_tracks:
	move.w	#$200,input_buffer              ; 2 digits
	lea	text_enter_first_track,a0       ; "ENTER FIRST TRACK : $"
	bsr.w	print
	bsr.w	input_hex                       ; the value
	tst.l	d0                              ; given?
	bmi.w	external_loader                 ; no
	move.w	d2,-(sp)
	move.w	#$200,input_buffer              ; 2 digits
	lea	text_enter_end_track,a0         ; "ENTER END TRACK : $"
	bsr.w	print
	bsr.w	input_hex                       ; the value
	move.w	(sp)+,d1
	tst.l	d0                              ; given?
	bmi.w	external_loader                 ; no
	cmp.w	d1,d2                           ; before the first?
	blt.w	external_loader                 ; yes
	movem.w	d1-d2,-(sp)
	lea	text_enter_buffer_address,a0    ; "ENTER BUFFER ADDRESS : $"
	bsr.w	print
	bsr.w	input_hex_long                  ; the value
	move.l	d2,d4
	movem.w	(sp)+,d1-d2
	tst.l	d0                              ; given?
	bmi.w	external_loader                 ; no
	movem.l	d1-d4,-(sp)
	lea	text_enter_side,a0              ; "ENTER SIDE (0/1) : $0"
	bsr.w	print                           ; 1 digit
	move.w	#$100,input_buffer
	bsr.w	input_hex                       ; the value
	move.l	d2,d5
	movem.l	(sp)+,d1-d4
	tst.l	d0                              ; given?
	bmi.w	external_loader                 ; no
	move.l	#$e0e0505,$ffff8800.w           ; PSG register select, drive A, side 0
	tst.w	d5                              ; side 1?
	beq.s	load_tracks_go                  ; no
	move.l	#$e0e0404,$ffff8800.w           ; PSG register select, drive A, side 1
load_tracks_go:
	move.w	#$ffff,$43e.w                   ; flock, the floppy locked
	move.l	d1,d3                           ; the first track
	sub.w	d1,d2                           ; the count
	move.w	d2,d1
	move.l	d4,d2                           ; the address
	move.l	d4,memory_address               ; the memory address too
	lea	text_please_wait_loading,a0     ; "PLEASE WAIT ... LOADING ..."
	bsr.w	print
	bsr.w	read_tracks                     ; read
	move.l	#$e0e0303,$ffff8800.w           ; PSG register select, deselected
	clr.w	$43e.w                          ; flock, unlocked
	bra.w	external_loader

;------------------------------------------------------------------------------
; read_tracks: the head restored and stepped to track d0, then d1+1 tracks read (Read Track) to d2.
;------------------------------------------------------------------------------
read_tracks:	; from: external_loader
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	bsr.w	fdc_restore                     ; restore
	move.w	d3,d0                           ; the first track
	bsr.w	fdc_seek                        ; seek
	bsr.w	read_tracks_dma                 ; read
	movem.l	(sp)+,d0-d7/a0-a6
	rts

read_tracks_dma:	; from: read_tracks
	move.b	d2,$ffff860d.w                  ; DMA base low, the DMA address
	lsr.l	#8,d2
	move.b	d2,$ffff860b.w                  ; DMA base mid
	lsr.l	#8,d2
	move.b	d2,$ffff8609.w                  ; DMA base high
read_tracks_track:
	move.w	#$90,$ff8606                    ; DMA mode / status, the DMA toggled to read
	move.w	#$190,$ff8606                   ; DMA mode / status
	move.w	#$90,$ff8606                    ; DMA mode / status
	moveq	#9,d0                           ; 9 sectors
	bsr.w	fdc_write                       ; the sector count
	move.w	#$84,$ff8606                    ; DMA mode / status, the sector register
	moveq	#1,d0                           ; 1
	bsr.w	fdc_write
	move.w	#$80,$ff8606                    ; DMA mode / status, the command register
	move.w	#$90,d0                         ; read multiple
	bsr.w	fdc_write
	bsr.w	fdc_wait                        ; done
	bsr.w	fdc_step_in                     ; a step in
	dbra	d1,read_tracks_track            ; the next track
	rts

;------------------------------------------------------------------------------
; fdc_read_sectors: the track's sectors from d1 read to d2 (Read Multiple Sectors): d2 the bytes read, d7 the status.
;------------------------------------------------------------------------------
fdc_read_sectors:	; from: read_sectors, disk_search, search_buffer, list_track_id, boot_info
	move.l	d2,-(sp)                        ; kept
	move.b	d2,$ffff860d.w                  ; DMA base low, the DMA address
	lsr.l	#8,d2
	move.b	d2,$ffff860b.w                  ; DMA base mid
	lsr.l	#8,d2
	move.b	d2,$ffff8609.w                  ; DMA base high
	move.w	#$90,$ff8606                    ; DMA mode / status, the DMA toggled to read
	move.w	#$190,$ff8606                   ; DMA mode / status
	move.w	#$90,$ff8606                    ; DMA mode / status
	moveq	#2,d0                           ; 2 sectors' count
	bsr.w	fdc_write
	move.w	#$84,$ff8606                    ; DMA mode / status, the sector register
	move.w	d1,d0                           ; the first sector
	bsr.w	fdc_write
	move.w	#$80,$ff8606                    ; DMA mode / status, the command register
	move.w	#$80,d0                         ; read multiple
	bsr.w	fdc_write
	bsr.w	fdc_wait                        ; done
	move.l	(sp)+,d1                        ; the start
	moveq	#0,d2                           ; the DMA address now
	move.b	$ffff8609.w,d2                  ; DMA base high
	lsl.l	#8,d2
	move.b	$ffff860b.w,d2                  ; DMA base mid
	lsl.l	#8,d2
	move.b	$ffff860d.w,d2                  ; DMA base low
	sub.l	d1,d2                           ; the bytes read
	rts

;------------------------------------------------------------------------------
; fdc_read_track: the whole track read raw to d2 (Read Track): d2 the bytes read.
;------------------------------------------------------------------------------
fdc_read_track:	; from: read_track
	move.l	d2,-(sp)                        ; kept
	move.b	d2,$ffff860d.w                  ; DMA base low, the DMA address
	lsr.l	#8,d2
	move.b	d2,$ffff860b.w                  ; DMA base mid
	lsr.l	#8,d2
	move.b	d2,$ffff8609.w                  ; DMA base high
	move.w	#$90,$ff8606                    ; DMA mode / status, the DMA toggled to read
	move.w	#$190,$ff8606                   ; DMA mode / status
	move.w	#$90,$ff8606                    ; DMA mode / status
	moveq	#14,d0                          ; 14 sectors' count
	bsr.w	fdc_write
	move.w	#$80,$ff8606                    ; DMA mode / status, the command register
	move.w	#$e0,d0                         ; read track
	bsr.w	fdc_write
	bsr.w	fdc_wait                        ; done
	move.l	(sp)+,d1                        ; the start
	moveq	#0,d2                           ; the DMA address now
	move.b	$ffff8609.w,d2                  ; DMA base high
	lsl.l	#8,d2
	move.b	$ffff860b.w,d2                  ; DMA base mid
	lsl.l	#8,d2
	move.b	$ffff860d.w,d2                  ; DMA base low
	sub.l	d1,d2                           ; the bytes read
	rts

;------------------------------------------------------------------------------
; fdc_write_sectors: sectors from d1 written from d2 (Write Multiple Sectors): d2 the bytes written.
;------------------------------------------------------------------------------
fdc_write_sectors:	; from: write_sector, disk_search
	move.l	d2,-(sp)                        ; kept
	move.b	d2,$ffff860d.w                  ; DMA base low, the DMA address
	lsr.l	#8,d2
	move.b	d2,$ffff860b.w                  ; DMA base mid
	lsr.l	#8,d2
	move.b	d2,$ffff8609.w                  ; DMA base high
	move.w	#$190,$ff8606                   ; DMA mode / status, the DMA toggled to write
	move.w	#$90,$ff8606                    ; DMA mode / status
	move.w	#$190,$ff8606                   ; DMA mode / status
	moveq	#2,d0                           ; 2 sectors' count
	bsr.w	fdc_write
	move.w	#$184,$ff8606                   ; DMA mode / status, the sector register
	move.w	d1,d0                           ; the first sector
	bsr.w	fdc_write
	move.w	#$180,$ff8606                   ; DMA mode / status, the command register
	move.w	#$a0,d0                         ; write multiple
	bsr.w	fdc_write
	bsr.w	fdc_wait                        ; done
	move.l	(sp)+,d1                        ; the start
	moveq	#0,d2                           ; the DMA address now
	move.b	$ffff8609.w,d2                  ; DMA base high
	lsl.l	#8,d2
	move.b	$ffff860b.w,d2                  ; DMA base mid
	lsl.l	#8,d2
	move.b	$ffff860d.w,d2                  ; DMA base low
	sub.l	d1,d2                           ; the bytes written
	rts

;------------------------------------------------------------------------------
; fdc_read_ids: up to 50 ID fields read (Read Address) to d2, their statuses at d2+$12C, until record not found.
;------------------------------------------------------------------------------
fdc_read_ids:	; from: track_info
	movem.l	d4/a4,-(sp)                     ; saved
	movea.l	d2,a4
	lea	$12c(a4),a4                     ; the statuses
	move.b	d2,$ffff860d.w                  ; DMA base low, the DMA address
	lsr.l	#8,d2
	move.b	d2,$ffff860b.w                  ; DMA base mid
	lsr.l	#8,d2
	move.b	d2,$ffff8609.w                  ; DMA base high
	move.w	#$90,$ff8606                    ; DMA mode / status, the DMA toggled to read
	move.w	#$190,$ff8606                   ; DMA mode / status
	move.w	#$90,$ff8606                    ; DMA mode / status
	moveq	#1,d0                           ; 1 sector's count
	bsr.w	fdc_write
	moveq	#49,d4                          ; 50
	move.w	#$80,$ff8606                    ; DMA mode / status, the command register
fdc_read_ids_next:
	move.w	#$c0,d0                         ; read address
	bsr.w	fdc_write
	bsr.w	fdc_wait_short                  ; done
	cmp.b	#$90,d0                         ; record not found?
	beq.s	fdc_read_ids_done               ; yes: the end
	move.b	d0,(a4)+                        ; its status
	tst.l	d7                              ; timeout?
	bmi.s	fdc_read_ids_done               ; yes
	dbra	d4,fdc_read_ids_next            ; the next
fdc_read_ids_done:
	movem.l	(sp)+,d4/a4
	rts
fdc_step_out:
	move.w	#$80,$ff8606                    ; DMA mode / status, (not called) step out
	move.w	#$31,d0
	bsr.w	fdc_write
	bsr.w	fdc_wait
	rts

;------------------------------------------------------------------------------
; fdc_step_in: a step in.
;------------------------------------------------------------------------------
fdc_step_in:	; from: seek_to_track, read_tracks_dma
	move.w	#$80,$ff8606                    ; DMA mode / status, the command register
	move.w	#$51,d0                         ; step in
	bsr.w	fdc_write
	bsr.w	fdc_wait                        ; done
	rts

;------------------------------------------------------------------------------
; fdc_step_out_track: a step out.
;------------------------------------------------------------------------------
fdc_step_out_track:	; from: seek_to_track
	move.w	#$80,$ff8606                    ; DMA mode / status, the command register
	move.w	#$71,d0                         ; step out
	bsr.w	fdc_write
	bsr.w	fdc_wait                        ; done
	rts

;------------------------------------------------------------------------------
; fdc_seek: the head to track d0 (Seek).
;------------------------------------------------------------------------------
fdc_seek:	; from: read_tracks
	move.w	#$86,$ff8606                    ; DMA mode / status, the data register
	bsr.w	fdc_write                       ; the track
	move.w	#$80,$ff8606                    ; DMA mode / status, the command register
	move.w	#$11,d0                         ; seek
	bsr.w	fdc_write
	bsr.w	fdc_wait                        ; done
	rts

;------------------------------------------------------------------------------
; fdc_restore: the head to track 0 (Restore).
;------------------------------------------------------------------------------
fdc_restore:	; from: disk_ripper, change_drive, boot_info, read_tracks
	move.w	#$80,$ff8606                    ; DMA mode / status, the command register
	move.w	#$1,d0                          ; restore
	bsr.w	fdc_write
	bsr.w	fdc_wait                        ; done
	rts

;------------------------------------------------------------------------------
; fdc_wait: a short wait, then the FDC interrupt waited for (or a timeout): d7 the status.
;------------------------------------------------------------------------------
fdc_wait:                                       ; from: read_tracks_dma, fdc_read_sectors, fdc_read_track,
                                                ;   fdc_write_sectors, fdc_read_ids, fdc_step_in, 3 more
	move.w	#$150,d7
fdc_wait_delay:
	dbra	d7,fdc_wait_delay
	move.l	#$50000,d7                      ; the timeout
fdc_wait_done:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, done?
	beq.s	fdc_wait_status                 ; yes
	subq.l	#1,d7
	bne.s	fdc_wait_done                   ; no: wait
fdc_wait_status:
	move.w	$ffff8604.w,d7                  ; DMA sector count / FDC access, the status
	andi.w	#$ff,d7
	rts

;------------------------------------------------------------------------------
; fdc_wait_short: the same with a shorter timeout: d0 the status.
;------------------------------------------------------------------------------
fdc_wait_short:	; from: fdc_read_ids
	move.w	#$150,d7
fdc_wait_short_delay:
	dbra	d7,fdc_wait_short_delay
	move.l	#$28000,d7                      ; the timeout
fdc_wait_short_done:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, done?
	beq.s	fdc_wait_short_status           ; yes
	subq.l	#1,d7
	bne.s	fdc_wait_short_done             ; no: wait
fdc_wait_short_status:
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, the status
	andi.w	#$ff,d0
	rts

;------------------------------------------------------------------------------
; fdc_write: d0 to the FDC register selected, after a wait.
;------------------------------------------------------------------------------
fdc_write:                                      ; from: read_tracks_dma, fdc_read_sectors, fdc_read_track,
                                                ;   fdc_write_sectors, fdc_read_ids, fdc_step_in, 3 more
	bsr.w	fdc_delay                       ; a wait
	move.w	d0,$ff8604                      ; DMA sector count / FDC access, written

;------------------------------------------------------------------------------
; fdc_delay: a short wait.
;------------------------------------------------------------------------------
fdc_delay:	; from: fdc_write
	moveq	#32,d7
fdc_delay_loop:
	dbra	d7,fdc_delay_loop
	rts

;------------------------------------------------------------------------------
; read_file: the file at a0 read to a1, up to d2 bytes (errors shown).
;------------------------------------------------------------------------------
read_file:	; from: external_loader
	move.w	#$2,-(sp)                       ; read/write
	move.l	a0,-(sp)                        ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	lea	8(sp),sp
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	move.w	d0,d1                           ; the handle
	move.l	a1,-(sp)                        ; the address
	move.l	d2,-(sp)                        ; the length
	move.w	d1,-(sp)
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	lea	$c(sp),sp
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	move.w	d1,-(sp)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.l	d0                              ; an error?
	bmi.w	show_error                      ; yes
	rts

;------------------------------------------------------------------------------
; build_music_program: a program header and music_program in the buffer, its text length covering the music too
; (a soundtrack's VBL routine 6 further on for one kind).
;------------------------------------------------------------------------------
build_music_program:	; from: music_save
	lea	disk_buffer,a0                  ; the buffer
	move.w	#$601a,(a0)+                    ; bra.s: a program
	moveq	#25,d0                          ; the rest of the header
build_music_program_clear:
	clr.b	(a0)+                           ; cleared
	dbra	d0,build_music_program_clear
	lea	music_program,a1                ; the program
	lea	text_disk_utility_f1,a2         ; its end
	moveq	#0,d7                           ; its length
build_music_program_copy:
	move.b	(a1)+,(a0)+                     ; copied
	addq.w	#1,d7
	cmpa.l	a1,a2
	bne.s	build_music_program_copy
	add.l	range_end,d7                    ; + the music's end
	sub.l	range_start,d7                  ; less its start
	btst	#$0,d7                          ; odd?
	beq.s	build_music_program_length      ; no
	addq.l	#1,d7                           ; even
build_music_program_length:
	move.l	d7,disk_buffer+2                ; the text length
	cmpi.w	#$2,music_kind                  ; a soundtrack?
	bne.s	build_music_program_done        ; no
	lea	disk_buffer,a2
	adda.l	#$1c,a2
	adda.l	#$54,a2                         ; the VBL offset's place
	addi.l	#$6,2(a2)                       ; 6 more
build_music_program_done:
	rts

;------------------------------------------------------------------------------
; music_program: the program saved with a music: shrunk, the music started (tune 1), its VBL routine (8 into it)
; run from vblqueue every frame, keypad + and - change the tune every 5th frame; resident.
;------------------------------------------------------------------------------
music_program:	; from: build_music_program
	movea.l	sp,a5
	movea.l	4(a5),a5                        ; the basepage
	move.l	$c(a5),d0                       ; text
	add.l	$14(a5),d0                      ; + data
	add.l	$1c(a5),d0                      ; + bss
	addi.l	#$300,d0                        ; + $300
	move.l	d0,-(sp)
	lea	music_program_length(pc),a0     ; kept
	move.l	d0,(a0)
	pea	(a5)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	lea	music_program_old_stack(pc),a0  ; the old stack kept
	move.l	d0,(a0)
	andi.b	#$fe,$484.w                     ; conterm, no key click
	lea	music_program_tune(pc),a0       ; the tune
	moveq	#1,d0                           ; 1
	move.w	d0,(a0)
	bsr.w	text_disk_utility_f1            ; the music started (it is after the program)
	lea	text_disk_utility_f1(pc),a0     ; its VBL routine
	adda.l	#$8,a0                          ; 8 on
	lea	music_program_music_vbl(pc),a1  ; kept
	move.l	a0,(a1)
	lea	music_program_vbl(pc),a0        ; the program's VBL routine
	move.l	a0,$4da.w                       ; in vblqueue
	move.l	music_program_old_stack(pc),-(sp) ; the old stack
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	clr.w	-(sp)
	move.l	music_program_length(pc),-(sp)  ; the length to keep
	move.w	#$31,-(sp)
	trap	#1                              ; Ptermres

;------------------------------------------------------------------------------
; music_program_vbl: every 5th frame keypad + (the next tune) or - (the tune before), then the music's VBL.
;------------------------------------------------------------------------------
music_program_vbl:	; from: music_program
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	lea	music_program_frames(pc),a0     ; the frame count
	addq.w	#1,(a0)                         ; one more
	cmpi.w	#$5,(a0)                        ; 5?
	bne.s	music_program_play              ; no
	clr.w	(a0)
	move.b	$fffffc02.w,d0                  ; keyboard ACIA data, the key
	cmp.b	#$4e,d0                         ; keypad +?
	bne.s	music_program_minus             ; no
	lea	music_program_tune(pc),a0       ; the next tune
	addq.w	#1,(a0)
	move.w	(a0),d0
	bsr.w	text_disk_utility_f1            ; started
	bra.s	music_program_play
music_program_minus:
	cmp.b	#$4a,d0                         ; keypad -?
	bne.s	music_program_play              ; no
	lea	music_program_tune(pc),a0       ; the tune before
	move.w	(a0),d0
	subq.w	#1,d0
	bmi.s	music_program_play
	move.w	d0,(a0)
	bsr.w	text_disk_utility_f1            ; started
music_program_play:
	movea.l	music_program_music_vbl(pc),a0  ; the music's VBL
	jsr	(a0)
	movem.l	(sp)+,d0-d7/a0-a6
	rts
music_program_frames:
	dc.w	$0000
music_program_tune:	; from: music_program
	dc.w	$0000
music_program_music_vbl:	; from: music_program
	dc.w	$0000,$0000
music_program_old_stack:	; from: music_program
	dc.w	$0000,$0000
music_program_length:	; from: music_program
	dc.w	$0000,$0000
text_disk_utility_f1:	; from: disk_utility, build_music_program, music_program
	dc.b	27,'f',27,'E                                    DISK UTILITY'
	dc.b	$0b
	dc.b	13,' ',27,'pF1',27,'q DIR ',27,'pF2',27,'q PATH ',27,'pF3',27
	dc.b	'q RENAME ',27,'pF4',27,'q FORMAT ',27,'pF5',27,'q DELETE ',27,'pF6',27
	dc.b	'q CREATE FOLDER ',27,'pF7',27,'q FREE ',27,'pF10',27,'q QUIT',0
text_esc_to_exit:	; from: list_files_page_full
	dc.b	27,'Y74<ESC> TO EXIT <SPACE> TO CONTINUE',0
text_enter_new_path:	; from: new_path
	dc.b	27,'Y"!ENTER NEW PATH : ',27,'e',0
position_2_1:	; from: show_path, free_space, rename_file, create_folder, delete_file, new_path, 1 more
	dc.b	27,'Y"!                                                             '
	dc.b	'                 ',0
text_enter_new_folder:	; from: create_folder
	dc.b	27,'Y"!ENTER NEW FOLDER : ',27,'e',0
	dc.b	27,'Y"!WARNING ERROR',0
text_number_of_sides:	; from: format_disk
	dc.b	27,'Y"!NUMBER OF SIDES : ',27,'e',0
text_enter_disk_to:	; from: format_disk
	dc.b	27,'Y"!ENTER DISK TO FORMAT IN DRIVE A',0
text_enter_file_to:	; from: delete_file
	dc.b	27,'Y"!ENTER FILE TO ERASE :',27,'e',0
text_confirm_y_n:	; from: ask_confirm
	dc.b	27,'Y"\',27,'fCONFIRM (y/n)?',0
	dc.b	27,'Y"!ENTER FILENAME : ',27,'e',0
text_enter_source_name:	; from: rename_file
	dc.b	27,'Y"!ENTER SOURCE NAME : ',27,'e',0
text_enter_new_name:	; from: rename_file
	dc.b	27,'Y"!ENTER NEW NAME : ',27,'e',0
text_free_space:	; from: free_space
	dc.b	27,'Y"!FREE SPACE : ',0
text_k_bytes:	; from: free_space
	dc.b	'K-BYTES',0
text_please_wait_formating:	; from: format_disk
	dc.b	27,'Y"!PLEASE WAIT ...FORMATING...',0
text_picture_ripper_f1:	; from: draw_settings
	dc.w	$1b66,$1b45
	dc.b	$0b
	dc.b	13,'                                  PICTURE RIPPER'
	dc.b	$0b
	dc.b	13,'     ',27,'pF1',27,'q SWITCH SCREEN ',27,'pF2',27,'q NEW SCREEN ',27
	dc.b	'pF3',27,'q SAVE ',27,'pF4',27,'q COLORS ',27,'p->',27,'q UP ',27,'p<-'
	dc.b	27,'q DOWN ',27,'pF10',27,'q QUIT '
	dc.b	$0b,$0b
	dc.b	13,'                                                          PAL   '
	dc.b	'   COL'
	dc.b	$0b
	dc.b	13,'                 ADDR SCREEN : $                           0    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                                                           1    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 NBR PLANES  :                             2    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                                                           3    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 WIDTH       :                             4    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                                                           5    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 RESOLUTION  :                             6    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                                                           7    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 PLANE 1     :                             8    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 PLANE 2     :                             9    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 PLANE 3     :                            10    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 PLANE 4     :                            11    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                                                          12    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 SUPERPO     :                            13    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 NBR SUPERPO :                            14    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 NBR PLANES  :                            15    '
	dc.b	'  $'
	dc.b	$0b
	dc.b	13,'                 COLUMNS     :'
	dc.b	$0b
	dc.b	13,'                 MODULO      :',0
	dc.b	$00
marker_star:	; from: show_settings
	dc.b	27,'D*',0
position_5_56:	; from: show_settings
	dc.b	27,'Y%X ',0
	dc.b	27,'Y&X ',0
	dc.b	27,'Y',$27,'X ',0
	dc.b	27,'Y(X ',0
	dc.b	27,'Y)X ',0
	dc.b	27,'Y*X ',0
	dc.b	27,'Y+X ',0
	dc.b	27,'Y,X ',0
	dc.b	27,'Y-X ',0
	dc.b	27,'Y.X ',0
	dc.b	27,'Y/X ',0
	dc.b	27,'Y0X ',0
	dc.b	27,'Y1X ',0
	dc.b	27,'Y2X ',0
	dc.b	27,'Y3X ',0
	dc.b	27,'Y4X ',0
	dc.b	$ff
colour_rows:	; from: colour_down
	dc.b	'%&',$27,'()*+,-./01234'
	dc.b	$ff
setting_rows:	; from: picture_ripper
	dc.b	'%',$27,')+-./023456'
	dc.b	$ff
text_low:	; from: show_resolution
	dc.b	27,'Y+@LOW       ',0
text_medium:	; from: show_resolution
	dc.b	27,'Y+@MEDIUM    ',0
text_high:	; from: show_resolution
	dc.b	27,'Y+@HIGH      ',0
position_13_32:	; from: show_settings
	dc.b	27,'Y-@',0
position_14_32:	; from: show_settings
	dc.b	27,'Y.@',0
position_15_32:	; from: show_settings
	dc.b	27,'Y/@',0
position_16_32:	; from: show_settings
	dc.b	27,'Y0@',0
text_on:	; from: sample_ripper, show_stereo, show_settings, show_columns, show_superposed
	dc.b	'ON ',0
text_off:	; from: sample_ripper, show_stereo, show_settings, show_columns, show_superposed
	dc.b	'OFF',0
text_new_screen_address:	; from: new_screen
	dc.b	27,'Y81NEW SCREEN ADDRESS : $',27,'e',0
position_24_17:	; from: save_picture, new_screen
	dc.b	27,'Y81',27,'f',27,'l',0
text_enter_picture_s:	; from: save_picture
	dc.b	27,'Y81ENTER PICTURE',$27,'S NAME : ',27,'e',0
position_7_32:	; from: show_planes
	dc.b	27,'Y',$27,'@',0
position_9_32:	; from: show_columns_value
	dc.b	27,'Y)@',0
position_21_32:	; from: show_columns
	dc.b	27,'Y5@',0
position_22_32:	; from: show_modulo
	dc.b	27,'Y6@',0
position_19_32:	; from: show_width
	dc.b	27,'Y3@',0
position_18_32:	; from: show_superposed
	dc.b	27,'Y2@',0
position_20_32:	; from: show_count
	dc.b	27,'Y4@',0
position_5_32:	; from: show_screen_address
	dc.b	27,'Y%@',0
error_numbers:	; from: show_gemdos_error, show_error
	dc.b	$00,$00,$01,$00,$02,$00,$03,$00,$04,$00,$05,$00,$06,$00,$07,$00
	dc.b	$08,$00,$09,$00,$0a,$00,$0b,$00,$0c,$00,$0d,$00,$0e,$00,$0f,$00
	dc.b	$10,$00,$11,$00,$20,$00,$21,$00,$22,$00,$23,$00,$24,$00,$25,$00
	dc.b	$27,$00,$28,$00,$2e,$00,$30,$00,$31,$00,$40,$00,$41,$00,$42,$00
	dc.b	$43,$00,$44,$ff,$ff
error_texts:	; from: show_gemdos_error, show_error
	dc.l	text_general_error_press
	dc.l	text_disk_not_ready
	dc.l	text_unknow_error_press
	dc.l	text_crc_error_press
	dc.l	text_request_error_press
	dc.l	text_track_not_found
	dc.l	text_wrong_boot_press
	dc.l	text_sector_not_found
	dc.l	text_paper_out_press
	dc.l	text_write_error_press
	dc.l	text_read_error_press
	dc.l	text_general_error_press_a
	dc.l	text_disk_protected_press
	dc.l	text_disk_changed_press
	dc.l	text_unknow_peripherical_press
	dc.l	text_bad_sectors_press
	dc.l	text_insert_disk_press
	dc.l	text_wrong_number_press
	dc.l	text_file_not_found
	dc.l	text_path_not_found
	dc.l	text_too_much_open
	dc.l	text_acces_disable_press
	dc.l	text_wrong_handle_press
	dc.l	text_out_of_memory
	dc.l	text_address_error_press
	dc.l	text_wrong_disk_unit
	dc.l	text_bad_rename_press
	dc.l	text_no_more_files
	dc.l	text_range_erreur_press
	dc.l	text_internal_error_press
	dc.l	text_non_executable_press
	dc.l	text_memory_block_error
	dc.l	text_disk_full_press
position_24_0:	; from: show_error
	dc.b	27,'f',27,'Y8 ',0
position_23_1:	; from: show_gemdos_error
	dc.b	27,'f',27,'Y7!',0
text_general_error_press:
	dcb.w	8,$2020
	dc.b	'GENERAL ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_disk_not_ready:
	dcb.w	8,$2020
	dc.b	'DISK NOT READY (PRESS A KEY TO CONTINUE)  ',0
text_unknow_error_press:
	dc.b	'                UNKNOW ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_crc_error_press:
	dcb.w	8,$2020
	dc.b	'CRC ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_request_error_press:
	dcb.w	8,$2020
	dc.b	'REQUEST ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_track_not_found:
	dcb.w	8,$2020
	dc.b	'TRACK NOT FOUND !!! (PRESS A KEY TO CONTINUE)  ',0
text_wrong_boot_press:
	dcb.w	8,$2020
	dc.b	'WRONG BOOT !!! (PRESS A KEY TO CONTINUE)  ',0
text_sector_not_found:
	dc.b	'                SECTOR NOT FOUND !!! (PRESS A KEY TO CONTINUE)  ',0
text_paper_out_press:
	dcb.w	8,$2020
	dc.b	'PAPER OUT !!! (PRESS A KEY TO CONTINUE)  ',0
text_write_error_press:
	dcb.w	8,$2020
	dc.b	'WRITE ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_read_error_press:
	dcb.w	8,$2020
	dc.b	'READ ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_general_error_press_a:
	dc.b	'                GENERAL ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_disk_protected_press:
	dc.b	'                DISK PROTECTED !!! (PRESS A KEY TO CONTINUE)  ',0
text_disk_changed_press:
	dcb.w	8,$2020
	dc.b	'DISK CHANGED !!! (PRESS A KEY TO CONTINUE)  ',0
text_unknow_peripherical_press:
	dc.b	'                UNKNOW PERIPHERICAL !!! (PRESS A KEY TO CONTINUE',')  '
	dc.b	0
text_bad_sectors_press:
	dc.b	'    /           BAD SECTORS !!! (PRESS A KEY TO CONTINUE)  ',0
text_insert_disk_press:
	dc.b	'                INSERT DISK !!! (PRESS A KEY TO CONTINUE)  ',0
text_wrong_number_press:
	dc.b	'                WRONG NUMBER !!! (PRESS A KEY TO CONTINUE)  ',0
text_file_not_found:
	dcb.w	8,$2020
	dc.b	'FILE NOT FOUND !!! (PRESS A KEY TO CONTINUE)  ',0
text_path_not_found:
	dc.b	'                PATH NOT FOUND !!! (PRESS A KEY TO CONTINUE)  ',0
text_too_much_open:
	dcb.w	8,$2020
	dc.b	'TOO MUCH OPEN FILES !!! (PRESS A KEY TO CONTINUE)  ',0
text_acces_disable_press:
	dcb.w	8,$2020
	dc.b	'ACCES DISABLE !!! (PRESS A KEY TO CONTINUE)  ',0
text_wrong_handle_press:
	dcb.w	8,$2020
	dc.b	'WRONG HANDLE !!! (PRESS A KEY TO CONTINUE)  ',0
text_out_of_memory:
	dc.b	'                OUT OF MEMORY !!! (PRESS A KEY TO CONTINUE)  ',0
text_address_error_press:
	dc.b	'                ADDRESS ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_wrong_disk_unit:
	dc.b	'                WRONG DISK UNIT !!! (PRESS A KEY TO CONTINUE)  ',0
text_bad_rename_press:
	dc.b	'                BAD RENAME !!! (PRESS A KEY TO CONTINUE)  ',0
text_no_more_files:
	dcb.w	8,$2020
	dc.b	'NO MORE FILES !!! (PRESS A KEY TO CONTINUE)  ',0
text_range_erreur_press:
	dcb.w	8,$2020
	dc.b	'RANGE ERREUR !!! (PRESS A KEY TO CONTINUE)  ',0
text_internal_error_press:
	dc.b	'                INTERNAL ERROR !!! (PRESS A KEY TO CONTINUE)  ',0
text_non_executable_press:
	dcb.w	8,$2020
	dc.b	'NON EXECUTABLE !!! (PRESS A KEY TO CONTINUE)  ',0
text_memory_block_error:
	dc.b	'                MEMORY BLOCK ERROR !!! (PRESS A KEY TO CONTINUE)','  '
	dc.b	0
text_disk_full_press:
	dcb.w	8,$2020
	dc.b	'DISK FULL !!! (PRESS A KEY TO CONTINUE)  ',0
text_disk_error_press:	; from: save_file
	dc.b	27,'f',27,'Y8               DISK ERROR !!! (PRESS A KEY TO CONTINUE)  '
	dc.b	0
text_play_music_y:	; from: play_chip_music, play_soundtrack
	dc.b	27,'f',27,'Y8                               PLAY MUSIC ? (Y/N)  ',0
text_playing_press_esc:	; from: play_chip_music, play_soundtrack
	dc.b	27,'f',27
	dc.b	'Y8             PLAYING ... PRESS ESC TO STOP OR +/- FOR OTHER SO','NGS'
	dc.b	0
text_searching:	; from: music_search
	dc.b	27,'f',27,'Y8                                 SEARCHING...',0
hex_digit_pairs:                                ; from: parse_number, edit_buffer, hex_to_bytes, edit_memory,
                                                ;   hex_from_input, show_planes, 1 more
	dc.w	$3000,$3101,$3202,$3303,$3404,$3505,$3606,$3707
	dc.w	$3808,$3909,$610a,$410a,$620b,$420b,$630c,$430c
	dc.w	$640d,$440d,$650e,$450e,$660f,$460f
	dc.b	$ff
hex_digits:                                     ; from: print_result, disassemble_buffer, show_buffer_length,
                                                ;   list_track_id, boot_info, show_disk_settings, 20 more
	dc.b	'0123456789ABCDEF ',0
	dc.b	$0b,$0d,$00,$1b,$45,$00
position_3_24:	; from: show_sample_start
	dc.b	27,'Y#8',0
position_4_24:	; from: show_sample_end
	dc.b	27,'Y$8',0
position_3_54:	; from: show_frequency, show_ste_frequency
	dc.b	27,'Y#V',0
ym_frequencies:	; from: show_frequency, sample_frequency
	dc.w	$0001,$0203,$0405,$0607,$0809,$ffff
sample_markers:	; from: sample_toggle_end
	dc.w	$2324,$ff00
ym_timer_settings:	; from: build_sample_program, sample_play
	dc.w	$000a,$0006,$0005,$0006,$0005,$0005,$0004,$0005
	dc.w	$0002,$0006,$0029,$0001,$0024,$0001,$001f,$0001
	dc.w	$000b,$0002,$0001,$0006
text_khz:	; from: show_frequency
	dc.b	'2,5 KHZ ',0
	dc.b	'5 KHZ   ',0
	dc.b	'7,5 KHZ ',0
	dc.b	'10 KHZ  ',0
	dc.b	'12,5 KHZ',0
	dc.b	'15 KHZ  ',0
	dc.b	'17,5 KHZ',0
	dc.b	'20 KHZ  ',0
	dc.b	'22,5 KHZ',0
	dc.b	'25 KHZ  ',0
text_khz_at_d7a2:	; from: show_ste_frequency
	dc.b	'6,25 KHZ',0
	dc.b	'12,5 kHZ',0
	dc.b	'25 KHZ  ',0
	dc.b	'50 KHZ  ',0
text_sample_ripper_f1:	; from: sample_ripper
	dc.w	$1b66,$1b45
text_sample_ripper_f1_start:	; from: sample_toggle_controls
	dc.w	$1b48
	dc.b	$0b
	dc.b	13,27,'C                                SAMPLE RIPPER'
	dc.b	$0b,$0b
	dc.b	13,27,'C   ',27,'pF1',27,'q  START ADDRESS: $               ',27,'pF3'
	dc.b	27,'q FREQUENCY :           ',27,'pF5',27,'q SAVE'
	dc.b	$0b
	dc.b	13,27,'C   ',27,'pF2',27,'q  END ADDRESS  : $               ',27,'pF4'
	dc.b	27,'q PLAY   ',27,'pF6',27,'q  SIGN :     ',27,'pF7',27,'q STE ',27
	dc.b	'pF10',27,'q QUIT',0
text_sample_ripper_f1_start_address:	; from: sample_toggle_controls
	dc.b	$1b,$66,$1b,$48,$0b
	dc.b	13,27,'C                                SAMPLE RIPPER'
	dc.w	$0b0b
	dc.b	13,27,'C   ',27,'pF1',27,'q  START ADDRESS: $               ',27,'pF3'
	dc.b	27,'q FREQUENCY :           ',27,'pF5',27,'q SAVE'
	dc.b	$0b
	dc.b	13,27,'C   ',27,'pF2',27,'q  END ADDRESS  : $               ',27,'pF4'
	dc.b	27,'q PLAY   ',27,'pF6',27,'q  CONTROL    ',27,'pF7',27,'q STF ',27
	dc.b	'pF10',27,'q QUIT',0
text_general_volume_volume:	; from: sample_controls
	dc.b	27,'Y*:GENERAL VOLUME:',27,'Y+:VOLUME (RIGHT):',27,'Y,:VOLUME (LEFT) :'
	dc.b	27,'Y-:TREBLE        :',27,'Y.:BASS          :',27,'Y/:STEREO        :'
	dc.b	0
	dc.b	$ff
position_10_47:	; from: sample_controls, sample_controls_unmark, sample_controls_marker
	dc.b	27,'Y*O',0
	dc.b	27,'Y+O',0
	dc.b	27,'Y,O',0
	dc.b	27,'Y-O',0
	dc.b	27,'Y.O',0
position_15_47:	; from: sample_controls
	dc.b	27,'Y/O',0
	dc.b	$ff
position_10_42:	; from: show_volume
	dc.b	27,'Y*J',0
position_11_42:	; from: show_right
	dc.b	27,'Y+J',0
position_12_42:	; from: show_left
	dc.b	27,'Y,J',0
position_13_42:	; from: show_treble
	dc.b	27,'Y-J',0
position_14_42:	; from: show_bass
	dc.b	27,'Y.J',0
position_15_42:	; from: show_stereo
	dc.b	27,'Y/J',0
position_4_60:	; from: sample_ripper
	dc.b	27,'Y$\',0
text_playing_position:	; from: sample_play
	dc.b	27,'Y86PLAYING POSITION : $',0
position_24_42:	; from: sample_play
	dc.b	27,'Y8J',0
text_music_ripper_f1:	; from: music_ripper
	dc.w	$1b66,$1b45
	dc.b	$0b
	dc.b	13,'                                  MUSIC RIPPER'
	dc.w	$0b0b,$0b0b
	dc.b	13,'                                    ',27,'pF1',27,'q  SEARCH'
	dc.b	$0b,$0b
	dc.b	13,'                                    ',27,'pF2',27,'q  SAVE'
	dc.w	$0b0b
	dc.b	13,'                                    ',27,'pF3',27,'q  SAMPLE RIPPER'
	dc.w	$0b0b
	dc.b	13,'                                    ',27,'pF10',27,'q QUIT',0
text_estimated_start_address:	; from: find_soundtracker
	dc.b	27,'f',27,'Y09ESTIMATED START ADDRESS:$',0
text_estimated_end_address:	; from: find_soundtracker
	dc.b	27,'Y29ESTIMATED END ADDRESS  :$',0
text_estimation:	; from: find_soundtracker
	dc.b	27,'Y49ESTIMATION             :    % ',0
text_voice_set_start:	; from: find_soundtracker
	dc.b	27,'f',27,'Y09VOICE SET START ADDRESS:$',0
text_voice_set_end:	; from: find_soundtracker
	dc.b	27,'Y29VOICE SET END ADDRESS  :$',0
text_quartet_start_address:	; from: find_soundtracker
	dc.b	27,'Y49QUARTET START ADDRESS  :$',0
text_soundtrack_amiga:	; from: find_soundtracker
	dc.b	27,'Y.9         SOUNDTRACK AMIGA ',0
text_chip_music:	; from: find_soundtrack
	dc.b	27,'Y.9            CHIP MUSIC    ',0
text_soundtrack:	; from: find_soundtrack
	dc.b	27,'Y.9            SOUNDTRACK    ',0
text_chip_music_at_dcaa:	; from: find_chip_music, play_soundtrack
	dc.b	27,'Y.9            CHIP MUSIC    ',0
text_quartet_music:	; from: find_soundtracker
	dc.b	27,'Y.9         ',$27,'QUARTET',$27,' MUSIC',0
text_tcb_tracker:	; from: find_tcb_tracker
	dc.b	27,'Y.9            TCB TRACKER   ',0
text_sorry_no_music:	; from: music_search
	dc.b	27,'f',27,'Y.9                                 ',27
	dc.b	'Y09                                 ',27
	dc.b	'Y29     SORRY, NO MUSIC FOUND  !    ',27
	dc.b	'Y49                                 ',0
	dc.b	27,'f',27,'Y.9                                 ',27
	dc.b	'Y09                                 ',27
	dc.b	'Y29                                 ',27
	dc.b	'Y49                                 ',0
	dc.b	27,'f',27,'Y84',27,'l<SPACE> TO CONTINUE',0
text_save_b_inary:	; from: sample_save, music_save
	dc.b	27,'f',27,'Y89SAVE (B)INARY / (E)XECUTABLE ?',0
text_save_b_inary_s:	; from: memory_ripper
	dc.b	27,'f',27,'Y89SAVE (B)INARY / (S)OURCE ?',0
text_confirm_y_n_at_de95:	; from: main_menu
	dc.b	27,'f',27,'Y8;     CONFIRM (Y/N) ?',0
position_24_0_at_deb0:	; from: memory_ripper
	dc.b	27,'f',27
	dc.b	'Y8                                                              '
	dc.b	'                 ',0
text_new_dump_address:	; from: new_dump_address
	dc.b	27,'f',27,'Y8 ',27,'lNEW DUMP ADDRESS : $',27,'e',0
text_start_address_section:	; from: save_source
	dc.b	27,'f',27,'Y8 ',27,'lSTART ADDRESS SECTION TEXT : $',27,'e',0
text_start_address:                             ; from: external_call, sample_set_start, sample_save, music_save,
                                                ;   music_search, save_binary, 3 more
	dc.b	27,'f',27,'Y8 ',27,'lSTART ADDRESS : $',27,'e',0
text_end_address_section:	; from: save_source
	dc.b	27,'f',27,'Y8 ',27,'lEND ADDRESS SECTION TEXT : $',27,'e',0
text_end_address_section_data:	; from: save_source
	dc.b	27,'f',27,'Y8 ',27,'lEND ADDRESS SECTION DATA : $',27,'e',0
text_end_address:	; from: sample_set_end, sample_save, music_save, music_search, save_binary, copy_memory, 2 more
	dc.b	27,'f',27,'Y8 ',27,'lEND ADDRESS : $',27,'e',0
text_searching_at_dfd1:	; from: search_memory
	dc.b	27,'f',27,'Y8 ',27
	dc.b	'lSEARCHING ...                                              ',0
text_copy_address:	; from: copy_memory
	dc.b	27,'f',27,'Y8 ',27,'lCOPY ADDRESS : $',27,'e',0
text_text_to_find:	; from: search_memory
	dc.b	27,'f',27,'Y8 ',27,'lTEXT TO FIND :  ',27,'e',0
text_data_to_find:	; from: search_memory
	dc.b	27,'f',27,'Y8 ',27,'lDATA TO FIND : $',27,'e',0
text_data_to_fill:	; from: fill_memory
	dc.b	27,'f',27,'Y8 ',27,'lDATA TO FILL : $',27,'e',0
text_text_to_fill:	; from: fill_memory
	dc.b	27,'f',27,'Y8 ',27,'lTEXT TO FILL : ',27,'e',0
text_h_exa_t:	; from: fill_memory
	dc.b	27,'f',27,'Y8 ',27,'l(H)exa (T)ext ?',0
text_b_yte_w:	; from: search_memory
	dc.b	27,'f',27,'Y8 ',27,'l(B)yte (W)ord (L)ong (T)ext ?',0
text_memory_ripper_f1up:	; from: memory_ripper
	dc.b	27,'f',27,'E                                  MEMORY RIPPER'
	dc.b	$0b
	dc.b	13,'  ',27,'pF1',27,'qUP ',27,'pF2',27,'qDOWN ',27,'pF3',27,'qADDRESS '
	dc.b	27,'pF4',27,'qSEARCH ',27,'pF5',27,'qFILL ',27,'pF6',27,'qEDIT ',27
	dc.b	'pF7',27,'qCOPY ',27,'pF8',27,'qHEXA/SYM ',27,'pF9',27,'qSAVE ',27
	dc.b	'pF10',27,'qQUIT',0
text_external_loader_f1:	; from: external_loader
	dc.w	$1b66,$1b45
	dc.b	$0b
	dc.b	'                                 EXTERNAL LOADER'
	dc.b	$0b,$0d,$0b,$0b,$0b
	dc.b	27,'Y&@',27,'pF1',27,'q  LOAD FILE'
	dc.b	$0b,$0b
	dc.b	13,27,'Y(@',27,'pF2',27,'q  LOAD TRACK'
	dc.w	$0b0b
	dc.b	13,27,'Y*@',27,'pF10',27,'q QUIT',0
text_enter_filename:	; from: external_call, sample_save, music_save, save_source, save_binary, external_loader
	dc.b	27,'Y8 ENTER FILENAME : ',27,'e',27,'K',0
text_enter_first_track:	; from: external_loader
	dc.b	27,'Y8 ENTER FIRST TRACK : $',27,'e',27,'K',0
text_enter_end_track:	; from: external_loader
	dc.b	27,'Y8 ENTER END TRACK : $',27,'e',27,'K',0
text_enter_buffer_address:	; from: external_loader
	dc.b	27,'Y8 ENTER BUFFER ADDRESS : $',27,'e',27,'K',0
text_enter_side:	; from: external_loader
	dc.b	27,'Y8 ENTER SIDE (0/1) : $0',27,'D',27,'K',0
text_please_wait_printing:	; from: print_buffer, print_memory
	dc.b	27,'Y8 PLEASE WAIT ... PRINTING ...',27,'f',0
text_printer_not_ready:	; from: print_buffer, print_dump
	dc.b	27,'Y8 PRINTER NOT READY ! (PRESS A KEY TO CONTINUE)',0
text_please_wait_loading:	; from: external_loader
	dc.b	27,'f',27,'Y8 PLEASE WAIT ... LOADING ...',27,'K',0
position_24_0_at_e30e:	; from: print_buffer, external_call, music_ripper, sample_ripper, show_error, print_dump
	dc.b	27,'f',27,'Y8 ',27,'K',0
position_23_1_at_e317:	; from: show_gemdos_error, list_files_page_full
	dc.b	27,'f',27
	dc.b	'Y7!                                                             '
	dc.b	'                 ',0
text_ultimate_ripper_f1:	; from: main_menu
	dc.w	$1b66,$1b45
	dc.b	$0b
	dc.b	13,'                                ULTIMATE RIPPER'
	dc.b	$0b,$0d,$0b,$0b,$0b
	dcb.w	15,$2020
	dc.b	' ',27,'pF1',27,'q  PICTURE RIPPER'
	dc.b	$0b,$0b
	dc.b	13,'                               ',27,'pF2',27,'q  MEMORY RIPPER'
	dc.w	$0b0b
	dc.b	13,'                               ',27,'pF3',27,'q  DISK UTILITY'
	dc.w	$0b0b
	dc.b	13,'                               ',27,'pF4',27,'q  EXTERNAL CALL'
	dc.b	$0b,$0b
	dc.b	13,'                               ',27,'pF5',27,'q  EXTERNAL LOADER'
	dc.w	$0b0b
	dc.b	13,'                               ',27,'pF6',27,'q  MUSIC RIPPER'
	dc.w	$0b0b
	dc.b	13,'                               ',27,'pF7',27,'q  DISK RIPPER'
	dc.b	$0b,$0b
	dc.b	13,'                               ',27,'pF9',27,'q  INFO RIPPER'
	dc.w	$0b0b
	dc.b	13,'                               ',27,'pF10',27,'q QUIT',0
text_external_call:	; from: external_call
	dc.b	$1b,$66,$1b,$45,$0b
	dc.b	13,'                                   EXTERNAL CALL'
	dc.b	$0b,$0b,$0b,$0b,$0b,$0d,$00
text_f1_load_executef2:	; from: external_call
	dc.b	27,'Y&@',27,'pF1',27,'q  LOAD & EXECUTE',27,'Y(@',27,'pF2',27
	dc.b	'q  LOAD ADDRESS',27,'Y*@',27,'pF10',27,'q QUIT',0
text_free_ram:	; from: external_call
	dc.b	27,'Y0: FREE RAM      : $',0
text_start_free_ram:	; from: external_call
	dc.b	27,'Y2: START FREE RAM: $',0
text_start_load_ram:	; from: external_call
	dc.b	27,'Y4: START LOAD RAM: $',0
text_the_ultimate_ripper:	; from: info
	dc.w	$1b45,$0b0b,$0b0b
	dc.b	$0b
	dc.b	13,'                               THE ULTIMATE RIPPER'
	dc.b	$0b
	dc.b	13,'                                   VERSION 1.2'
	dc.b	$0b
	dc.b	13,'                         WRITEN IN 100% 68000 ASSEMBLEUR'
	dc.b	$0b
	dc.b	13,'                                     BY U.D'
	dc.b	$0b,$0b
	dc.b	13,'                                 Copyright 1990-91'
	dc.b	$0b
	dc.b	13,'                               EDITED BY : EURO SOFT'
	dc.b	$0b
	dc.b	13,'                               190, RUE DE LEZENNES'
	dc.b	$0b
	dc.b	13,'                              59650 VILLENEUVE D',$27,'ASCQ'
	dc.b	$0b
	dc.b	13,'                                       FRANCE'
	dc.b	$0b
	dc.b	13,'                     THANKS TO : FRANCOIS, THIERRY, XAVIER'
	dc.b	$0b,$0d,$00
text_disk_ripper_f1readf2writef3searchf4idf5read:	; from: disk_ripper
	dc.b	27,'E                                  DISK RIPPER'
	dc.b	$0b,$0b
	dc.b	13,'  ',27,'pF1',27,'qREAD',27,'pF2',27,'qWRITE',27,'pF3',27,'qSEARCH'
	dc.b	27,'pF4',27,'qID',27,'pF5',27,'qREAD TRACK',27,'pF6',27,'qBOOT-INF',27
	dc.b	'pF7',27,'qEDIT',27,'pF8',27,'qHEX/SYM',27,'pF9',27,'qCOPY',27,'pF10',27
	dc.b	'qQUIT'
	dc.b	$0b
	dc.b	13,'      ',27,'pD',27,'qRIVE :           ',27,'pT',27
	dc.b	'qRACK : $           ',27,'pS',27,'qECTOR : $           S',27,'pI',27
	dc.b	'qDE : ',0
text_f1_memory_disk:	; from: buffer_memory_menu
	dc.b	27,'Y+:',27,'pF1',27,'q MEMORY       -> DISK BUFFER',27,'Y-:',27,'pF2'
	dc.b	27,'q DISK BUFFER  -> MEMORY',0
text_copy_address_at_e9ac:	; from: buffer_memory_menu
	dc.b	27,'Y,: COPY ADDRESS : $',27,'e',0
text_start_address_at_e9c4:	; from: buffer_memory_menu
	dc.b	27,'Y,;START ADDRESS : $',27,'e',0
text_address_17d00_y:	; from: buffer_memory_menu
	dc.b	27,'Y,:   ADDRESS < $17D00 ? (Y/N)    ',27,'f',0
text_f1_takes_boot:	; from: boot_info
	dc.b	27,'Y(:    ',27,'pF1',27,'q TAKES BOOT INFO',0
text_nbr_of_tracks:	; from: boot_info
	dc.b	27,'Y*>NBR OF TRACKS : ',0
text_sectors_track:	; from: boot_info
	dc.b	27,'Y,>SECTORS/TRACK : ',0
text_nbr_sides:	; from: boot_info
	dc.b	27,'Y.>NBR SIDES     : ',0
text_init_sector:	; from: boot_info
	dc.b	27,'Y0>INIT SECTOR   : ',0
text_error_boot:	; from: boot_info
	dc.b	27,'Y2<     ERROR BOOT ',0
position_18_28:	; from: boot_info
	dc.b	27,'Y2<                        ',0
text_sector_ok:	; from: show_sector_status
	dc.b	27,'Y5<',27,'pSECTOR OK !',27,'q       ',0
text_bad_crc_data:	; from: show_sector_status
	dc.b	27,'Y5<',27,'pBAD CRC DATA!',27,'q     ',0
text_bad_data_request:	; from: show_sector_status
	dc.b	27,'Y5<',27,'pBAD DATA REQUEST !',27,'q',0
text_bad_id_crc:	; from: show_sector_status
	dc.b	27,'Y5<',27,'pBAD ID CRC !',27,'q      ',0
text_sector_not_found_at_eb13:	; from: show_sector_status
	dc.b	27,'Y5<',27,'pSECTOR NOT FOUND',27,'q  ',0
text_clear_data_mark:	; from: show_sector_status
	dc.b	27,'Y5<',27,'pCLEAR DATA MARK !',27,'q ',0
text_write_protect:	; from: show_sector_status
	dc.b	27,'Y5<',27,'pWRITE PROTECT !',27,'q   ',0
text_disk_error:	; from: show_sector_status
	dc.b	27,'Y5<',27,'pDISK ERROR !',27,'q      ',0
position_21_28:	; from: read_track
	dc.b	27,'Y5<                  ',0
text_length:	; from: show_buffer_length
	dc.b	27,'Y5!LENGTH : $',0
text_track_side_sector:	; from: track_info, list_track_ids
	dc.b	27,'Y%-TRACK  SIDE  SECTOR  LGTH  CRC   T-CRC  T-RNF  T-READ',0
text_space_to_continue:	; from: list_track_ids
	dc.b	27,'Y4-      SPACE TO CONTINUE (OTHER FOR STOPP)     ',0
position_20_13:	; from: track_info, list_track_ids
	dc.b	27,'Y4-                                               ',0
text_sector_not_found_press:	; from: track_info
	dc.b	27,'Y4-     SECTOR NOT FOUND (PRESS A KEY)            ',0
text_confirm_write_sector:	; from: write_sector
	dc.b	27,'Y,9CONFIRM WRITE SECTOR (Y/N) ?',0
text_search_h_exa:	; from: disk_search
	dc.b	27,'Y,9 SEARCH (H)EXA/(T)EXT ?',0
position_11_24:	; from: disk_search, next_sector_wrap
	dc.b	27,'Y+8                                     ',27,'Y+8',27,'e',0
position_13_24:	; from: disk_search, next_sector_wrap
	dc.b	27,'Y-8                                     ',27,'Y-8',27,'e',0
text_search:	; from: disk_search, next_sector_wrap
	dc.b	$1b,$59,$2b,$2d
text_search_at_ed1b:	; from: search_replace
	dc.b	'SEARCH  : ',0
text_replace:	; from: disk_search, next_sector_wrap
	dc.w	$1b59,$2d2d
text_replace_at_ed2a:	; from: search_replace
	dc.b	'REPLACE : ',0
text_please_wait_searching:	; from: disk_search
	dc.b	27,'Y(-           PLEASE WAIT ... SEARCHING ...           ',0
text_confirm_y_n_at_ed6d:	; from: disk_search
	dc.b	27,'Y(-                  CONFIRM (Y/N) ?                  ',0
text_sorry_no_replace:	; from: disk_search
	dc.b	27,'Y(-                SORRY NO REPLACE !                 ',0
text_sorry_not_found:	; from: disk_search
	dc.b	27,'Y(-                SORRY NOT FOUND  !                 ',0
text_f1_replace_save:	; from: disk_search
	dc.b	27,'Y(.   ',27,'pF1',27,'q REPLACE & SAVE ',27,'pF2',27,'q CONTINUE ',27
	dc.b	'pF3',27,'q EDIT ',27,'pF4',27,'q STOP',0
text_ok:	; from: list_track_id
	dc.w	$4f4b
	dc.b	$00
text_bad:	; from: list_track_id
	dc.b	'BAD',0
text_bad_dar:	; from: list_track_id
	dc.b	'BAD DAR',0
text_bad_dac:	; from: list_track_id
	dc.b	'BAD DAC',0
text_bad_idc:	; from: list_track_id
	dc.b	'BAD IDC',0
text_bad_dam:	; from: list_track_id
	dc.b	'BAD DAM',0
text_dam_f8:	; from: list_track_id
	dc.b	'DAM $F8',0
text_128:	; from: list_track_id
	dc.b	'128',0
text_256:	; from: list_track_id
	dc.b	'256',0
text_512:	; from: list_track_id
	dc.b	'512',0
text_1024:	; from: list_track_id
	dc.b	'1024',0
dollar_text:	; from: next_sector_wrap, list_track_id
	dc.w	$2400
position_10_51:	; from: boot_info, boot_info_unmark
	dc.b	27,'Y*S',0
	dc.b	27,'Y,S',0
	dc.b	27,'Y.S',0
	dc.b	27,'Y0S',0
	dc.b	$ff
arrow_text:	; from: boot_info, boot_info_unmark, sample_controls, sample_controls_marker
	dc.b	$3c,$2d,$00
no_arrow_text:	; from: boot_info_unmark, sample_controls_unmark
	dc.w	$2020,$0000
position_3_14:	; from: show_disk_settings
	dc.b	27,'f',27,'Y#.',0
position_3_33:	; from: set_track, show_disk_settings
	dc.b	27,'f',27,'Y#A',0
position_3_54_at_eec6:	; from: set_sector, show_disk_settings
	dc.b	27,'f',27,'Y#V',0
position_3_72:	; from: show_disk_settings
	dc.b	27,'f',27,'Y#h',0
text_f1_search_replace:	; from: in_game_search
	dc.b	'F1 : SEARCH & REPLACE    F10 : BACK TO PROGRAM',0
text_search_at_ef03:	; from: search_replace
	dc.b	' SEARCH ...',0
text_replace_ok:	; from: search_replace
	dc.b	' REPLACE OK !',0
text_sorry_not_found_at_ef1d:	; from: search_replace
	dc.b	' SORRY NOT FOUND',0
text_f1_replace_f2:	; from: search_replace
	dc.b	'F1 : REPLACE  F2 : CONT  F10 : QUIT      FIND ADDRESS : $',0
text_expression:	; from: calculator
	dc.b	27,'Y+/EXPRESSION :  ',27,'e',0
text_result:	; from: print_result
	dc.b	27,'f',27,'Y-/RESULT     : $',0
position_13_39:	; from: print_result
	dc.b	27,'f',27,'Y-G#',0
text_syntax_error:	; from: calculator
	dc.b	27,'f',27,'Y-/SYNTAX ERROR !!!!!'
space_cursor_off:	; from: run_module
	dc.b	' ',27,'f ',0
	dc.b	$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
	dc.b	$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
	dc.b	'               ',27,'Y-8',27,'e',0
	dc.b	27,'Y+-CHERCHE : ',0
	dc.b	27,'Y--REMPLACE: ',0
	dc.b	27,'Y(-      SVP PATIENTEZ ... RECHERCHE EN COURS ...      ',0
	dc.b	27,'Y(-                 CONFIRMEZ (O/N) ?                  ',0
	dc.b	27,'Y(-            DESOLE PAS DE REMPLACEMENT !            ',0
	dc.b	27,'Y(-                DESOLE PAS TROUVE  !                ',0
	dc.b	27,'Y(.',27,'pF1',27,'qREMPLACER & SAUVER ',27,'pF2',27,'qCONTINUER ',27
	dc.b	'pF3',27,'qEDITER ',27,'pF4',27,'qSTOPPER',0
	dc.b	$4f,$4b,$00
	dc.b	'BAD',0
	dc.b	'BAD DAR',0
	dc.b	'BAD DAC',0
	dc.b	'BAD IDC',0
	dc.b	'BAD DAM',0
	dc.b	'DAM $F8',0
	dc.b	'128',0
	dc.b	'256',0
	dc.b	'512',0
	dc.b	'1024',0
	dc.b	$24,$00
	dc.b	27,'Y*S',0
	dc.b	27,'Y,S',0
	dc.b	27,'Y.S',0
	dc.b	27,'Y0S',0
	dc.b	$ff,$3c,$2d,$00,$20,$20,$00
	dc.b	27,'f',27,'Y#.',0
	dc.b	27,'f',27,'Y#A',0
	dc.b	27,'f',27,'Y#V',0
	dc.b	27,'f',27,'Y#h',0
	dc.b	'F1 : CHERCHE & REMPLACE    F10 : RETOUR PROGRAMME',0
	dc.b	' RECHERCHE ...',0
	dc.b	' REMPLACEMENT OK !',0
	dc.b	' DESOLE PAS TROUVE',0
	dc.b	'F1 : REMPLACE  F2 : CONT  F10 : QUIT      FIND ADRESSE : $',0
	dc.b	27,'Y+/OPERATION :  ',27,'e',0
	dc.b	27,'f',27,'Y-/RESULTAT  : $',0
	dc.b	27,'f',27,'Y-G#',0
	dc.b	27,'f',27,'Y-/ERREUR DE SYNTAXE !!!!! ',27,'f ',0
	dc.w	$0000,$0000,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dcb.b	3390,$ff

	end
