; MSTETEST.S  -  the Atari Mega STE test cartridge, "MEGA-STE Field Service Diagnostic Rev. 1.5,
;               1991, Atari Corp., MAY 24, 1991"
; Devpac source of the cartridge, disassembled by Darren Birks, 17 November 2026.
; 64K at $FA0000; the code is $0004-$8AE5, unused zeros to $A7FF, texts and tables $A800-$EC0B,
; the rest $FF.
;
; This source rebuilds the cartridge's 64K byte for byte with
;   vasmm68k_mot -devpac -m68000 -Fbin -o MSTETEST.IMG MSTETEST.S
; (the dump is "MegaSTE Test v1.5.img").
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; A diagnostic cartridge ($FA52235F at its start): TOS runs it at reset, before TOS sets anything up,
; so it uses no TOS at all. Its variables are in low RAM (the equates below), and it has its own
; exception and MFP vectors, text console (screen and RS232 terminal), keyboard, floppy and ACSI code.
;
; Start-up: the MMU is set and RAM sized and tested (errors go to RS232 by stack-free code), then the
; screen, keyboard and RS232 are set up, then three checks:
;   check_vme_ram    a word written to $AF0000; a bus error means no VME RAM ($234)
;   check_fpu        waits for the 68881's response register at $FFFFFA40 to read $0802 (idle, no time
;                    out); a bus error means no FPU, and the background goes red
;   check_bus_error  a word written to address 0 must take a bus error
; then the SCU masks, the T test (timing_test, failures only), and a Timer A check at 8 MHz: a second
; Timer A interrupt within about 250 us of the first means a CPU or MFP clock fault, and the machine
; beeps for ever. Then 16 MHz with the cache on, and the menu.
;
; The menu runs tests by letter (several letters and a repeat count can be typed):
;   R RAM, O O.S. ROM, M MIDI, S serial, T timing, D DMA port, I SCC, L real-time clock, F floppy,
;   P printer/mouse/joystick ports, G short BLiT, Y long BLiT, V VME, Q all unattended tests,
;   Z unattended internal tests, A audio, C colour, K keyboard, H high resolution, J hard disk,
;   E examine/modify memory, B RS232 rate, X 50/60 Hz.
;
;=======================================================================
; BUGS IN THE CARTRIDGE (each is commented where it is)
;=======================================================================
;   fdc_interrupt clears ISRB bit 0, not bit 7: bclr #$80 on a memory byte takes the bit modulo 8.
;   The VME and FPU checks leave their own handler in the bus error vector when the device is found.
;   The RAM test normally ends at 8 MHz with the cache off: its saved $FF8E21 byte is overwritten.
;   The cache test writes the bytes at addresses 0 and 3 to $FF8E21, where #0 and #3 were meant.
;   dma_sound_test leaves through its caller's caller, so GPIP7 stays disabled after the audio test.
;   play_dma_sound's time-out reads $1E.w where Timer A's data register was meant.
;   The T1-T3 time-outs never fire: the routine that counts them down ($161E) is never installed.
;   The RS232 test sends only $55,$AA (a 0 ends its string) and sends the "No loopback connector"
;   text down the line; the short BLiT test's G6 and G7 texts are swapped; hd_known_bad_sector's
;   full-list branch goes into the RAM test's code; the SCC interrupt test compares with the word
;   at $200, not #$200; the random track test retries for ever.
;
; Two andi.b #$f,d0 and ten cmpi.b have their immediate word assembled with $FF in the high byte;
; they are kept as dc.w with the instruction in the comment.

last_fault_pc	equ	$200                    ; PC of the last bus/address error reported; the same PC twice hangs
ram_top	equ	$204                            ; the end of RAM from the start-up sizing (byte $205: its 64K bank, used
                                                ;   by T4)
interrupt_events	equ	$208            ; bits cleared by the interrupt handlers (0 BUSY/FDC, 1 DCD, 2 CTS, 6
                                                ;   RI); the T test: timer B counts and the HBL wait
timer_a_count	equ	$20a                    ; set to 1 when timer A starts; only the uninstalled timer A routine at
                                                ;   $161E counts it down
status_end_column	equ	$20c            ; the column after the last status-line text (show_status_at)
status_saved_column	equ	$20e            ; the cursor column kept while the status line is written
status_saved_row	equ	$210            ; the cursor line kept while the status line is written
repeat_count	equ	$212                    ; passes left to run (the number typed after the test letters, 1 if
                                                ;   none)
test_cycle	equ	$216                    ; the test cycle, in BCD (low byte $219 also the floppy sector ID)
scratch_long	equ	$21a                    ; scratch: the RAM test's saved cache byte and screen address, T4's last
                                                ;   counter read, the H test's VBL count
first_test_ptr	equ	$21e                    ; address of the first typed test letter in test_letters (letters are
                                                ;   kept last-typed first)
test_ptr	equ	$222                    ; address of the test letter running now
test_letters_ptr	equ	$226            ; the letters of the Q or Z sequence
run_done_message	equ	$22a            ; the "Tests Completed" text of the Q or Z sequence
rs232_rate	equ	$22e                    ; MFP Timer D data for the RS232 port: 2 = 19200 ... $40 = 600 baud
key_list_column	equ	$230                    ; keyboard test: where the next key name goes
key_list_row	equ	$232                    ; keyboard test: where the next key name goes
vme_ram_found	equ	$234                    ; $5E if the start-up write to VME $AF0000 completed, 0 on a bus error
ikbd_data_first	equ	$236                    ; the first data byte of an IKBD packet: mouse dy, joystick 0
ikbd_data_second	equ	$237            ; the second data byte of an IKBD packet: mouse dx, joystick 1
startup_checks_done	equ	$238            ; 0 during the start-up T test (failures only shown), $EA after it (T
                                                ;   also shows "Pass")
line_buffer	equ	$239                    ; the typed command line
test_letters	equ	$259                    ; test letters of the command line, last typed first
number_digits	equ	$269                    ; digits typed for a number (repeat count, track)
run_test_count	equ	$279                    ; tests in the Q or Z sequence
drive_a_type	equ	$27a                    ; drive A: bit 6 high density; cleared at each menu start
drive_b_type	equ	$27b                    ; drive B: as drive_a_type
exerciser_drive_type	equ	$27c            ; the type of the drive the exerciser runs on
keyboard_revision	equ	$27d            ; IKBD reset reply low nibble + 1; negative = not shown
ikbd_clock_packet	equ	$27e            ; 6 bytes of the IKBD time-of-day packet ($FC), last byte first
memory_utility_active	equ	$284            ; $FF while the E memory utility runs: a bus error returns to its prompt
sequence_index	equ	$285                    ; Q/Z: index of the letter running now
timer_irq_flags	equ	$286                    ; MFP timer interrupt bits (T0); the keyboard test's mouse idle count
pass_count	equ	$287                    ; passes or loops counted by a test
rs232_rx_byte	equ	$288                    ; last byte from the MFP receive interrupt
rs232_tx_byte	equ	$289                    ; next byte - 1 sent by the transmit-empty interrupt, stops at $FF
rs232_rx_status	equ	$28a                    ; MFP RSR error bits (overrun, parity, frame) from the receive
                                                ;   interrupts
rs232_tx_status	equ	$28b                    ; MFP TSR from the transmit interrupts
key_release	equ	$28c                    ; the last key release (break code) from the keyboard
unattended	equ	$28d                    ; non-zero: running unattended, no keys waited for
clock_flags	equ	$28e                    ; clock display flags
mode_flags	equ	$28f                    ; bit 0 keyboard dead, 1 RS232 terminal off (text to the screen only), 3
                                                ;   Q/Z sequence, 4 several tests, 5 repeat count given, 6 a test ran
                                                ;   this pass, 7 the test waited for its own key
us_keyboard	equ	$290                    ; keyboard test: $FF U.S. layout, 0 European (from the ROM's os_conf)
line_count	equ	$292                    ; T4 timer B lines (2 per interrupt); STE scroll HBL line count
vbl_flag	equ	$294                    ; set by the VBL handler, counted down or waited on
colour_bar_index	equ	$296            ; the colour test's shade step
floppy_motor_watch	equ	$297            ; non-zero while floppy_motor_vbl waits for the motor to stop
test_index_byte	equ	$298                    ; keyboard test: arrows shown plain (bits 0-3); floppy: the index into a
                                                ;   track table
cycle_random	equ	$299                    ; the exerciser cycle's random byte (timer A data) in each sector
scroll_top	equ	$29a                    ; text rows above it are not scrolled
screen_base	equ	$29c                    ; the screen the text goes to
screen_planes	equ	$2a0                    ; 4, 2 or 1
screen_height	equ	$2a2                    ; 200 or 400
screen_width	equ	$2a4                    ; 320 or 640
screen_line_bytes	equ	$2a6            ; bytes per scan line (160 or 80)
char_height	equ	$2a8                    ; the font's height in lines
text_row_bytes	equ	$2aa                    ; bytes per text line (1280)
last_column	equ	$2ac                    ; the last text column
last_row	equ	$2ae                    ; the last text row
font_address	equ	$2b0                    ; the 8x8 or 8x16 font
font_line_step	equ	$2b4                    ; bytes from one line of the font to the next
font_char_step	equ	$2b6                    ; bytes from one character of the font to the next
font_first_char	equ	$2b8                    ; 0
font_last_char	equ	$2ba                    ; $7F
text_foreground	equ	$2bc                    ; plane bits of the text colour ($FFFF)
text_background	equ	$2be                    ; plane bits of the background (0)
cursor_column	equ	$2c0
cursor_row	equ	$2c2
cursor_address	equ	$2c4                    ; the screen address of the cursor's cell
cursor_flags	equ	$2c8                    ; bit 0 blink mode, 1 drawn, 2 on, 4 inverse text
cursor_blink_rate	equ	$2c9            ; $1E
cursor_hide_count	equ	$2ca            ; the cursor is hidden while non-zero
saved_cursor_column	equ	$2cc            ; save_cursor's column
saved_cursor_row	equ	$2ce            ; save_cursor's row
draw_crossings	equ	$31a                    ; x 8, polygon edge crossings on the current fill line
draw_crossing_count	equ	$326
draw_bytes_per_line	equ	$328            ; Line-A style drawing variables from $32A (blit_long_test): bytes per
                                                ;   line
draw_planes	equ	$32a
draw_line_width	equ	$32c                    ; bytes per line
draw_contrl	equ	$32e                    ; CONTRL (CONTRL[1] = point count)
draw_ptsin	equ	$336                    ; PTSIN, the polygon's points
draw_colour_bits	equ	$342            ; x 4, colour bit per plane
draw_last_line	equ	$34a                    ; 0: the last pixel of a line is left out in XOR mode
draw_line_mask	equ	$34c                    ; the line style
draw_write_mode	equ	$34e                    ; 0 replace, 1 transparent, 2 XOR, 3 reverse transparent
draw_x1	equ	$350
draw_y1	equ	$352
draw_x2	equ	$354
draw_y2	equ	$356
draw_pattern	equ	$358                    ; fill patterns
draw_pattern_mask	equ	$35c            ; pattern lines - 1
draw_multi_fill	equ	$35e                    ; non-zero: a pattern per plane
draw_clip	equ	$360                    ; non-zero: clipping on
draw_clip_xmin	equ	$362
draw_clip_ymin	equ	$364
draw_clip_xmax	equ	$366
draw_clip_ymax	equ	$368
blit_long_corners	equ	$3b4            ; the triangle being drawn
blit_long_saved_screen	equ	$3b8            ; the screen before the long BLiT test
blit_long_points	equ	$3bc            ; x 8, the first polygon's points
blit_long_triangle	equ	$3cc            ; x 8, the moving triangle's corners (x,y x3, then the first again)
kbd_buffer_record	equ	$45c            ; the keyboard ACIA's buffer record (14 bytes, copied from
                                                ;   acia_buffer_records_init)
kbd_iorec_head	equ	$462                    ; keyboard buffer head (next word to read)
kbd_iorec_tail	equ	$464                    ; keyboard buffer tail (last word written)
aux_buffer_record	equ	$46a            ; a second buffer record set up beside the keyboard's
kbd_acia_status	equ	$478                    ; last keyboard ACIA status (kbd_iorec+$1C)
release_ring_write	equ	$47a            ; key release ring: write pointer
release_ring_read	equ	$47e            ; key release ring: read pointer
release_ring	equ	$482                    ; 8 bytes of key release codes
kbd_byte_hook	equ	$48a                    ; routine called with each keyboard byte
midi_byte_hook	equ	$48e                    ; routine called with each MIDI byte
ikbd_packet_type	equ	$492            ; the IKBD packet being received
ikbd_packet_count	equ	$493            ; IKBD packet bytes still to come
shift_held	equ	$494                    ; shift keys held
ikbd_packet_header	equ	$495            ; the header byte of the IKBD packet (mouse buttons)
saved_colour0	equ	$49e                    ; colour 0 kept by a test
saved_resolution	equ	$4a0            ; H test: the resolution kept
memory_utility_start	equ	$4a2            ; E: first address
memory_utility_end	equ	$4a6            ; E: last address
star_countdown	equ	$4aa                    ; RAM test: VBLs to the next blink of the '*'
star_inverse	equ	$4ac                    ; RAM test: the '*' blink state
rom_sum_u207	equ	$4b2                    ; ROM test: sum of the odd bytes
rom_sum_u206	equ	$4b8                    ; ROM test: sum of the even bytes
rom_crc_u207	equ	$4be                    ; ROM test: CRC of the odd bytes
rom_crc_u206	equ	$4c4                    ; ROM test: CRC of the even bytes
scroll_position	equ	$4cc                    ; STE scroll: the screen address shown
colour_test_mode	equ	$4d0            ; colour test: non-zero after Space, the CMY bars (colour_bars_ste_cmy)
counter_expected	equ	$4d2            ; T4: where the video counter should be
counter_end	equ	$4d6                    ; T4: the end of the screen tried
scroll_restart	equ	$4da                    ; STE scroll: nonzero = start again at $20000
scroll_step	equ	$4dc                    ; STE scroll: VBL count (vertical) or pixel 0-15 (sideways)
saved_video_base	equ	$4de            ; the screen base kept by a test
sound_step	equ	$4e6                    ; DMA sound test: offset of the volume/tone step
bass_sound	equ	$4ea                    ; DMA sound test: which of the two bass sounds
dma_block_count	equ	$4ec                    ; D test: blocks in the transfer
dma_test_address	equ	$4ee            ; D test: the transfer address
dma_command	equ	$4f2                    ; D test: $10 write out, $08 read back
dma_table_index	equ	$4f3                    ; D test: offset into the address table (step 4)
blit_source_word	equ	$4f4            ; short BLiT op test source fill; in the long test a long: the old bus
                                                ;   error vector
blit_dest_word	equ	$4f6                    ; short BLiT op test destination fill
blit_lines	equ	$4f8                    ; short BLiT test line count (400); in the long test a long: the stack
                                                ;   for the bus error exit
blit_words	equ	$4fa                    ; short BLiT test words per line (x count)
saved_vbl_vector	equ	$4fc            ; the VBL vector kept by a test
saved_vector	equ	$500                    ; a vector kept by a test (timer B, HBL)
midi_buffer_record	equ	$618            ; the MIDI ACIA's buffer record
rtc_image	equ	$636                    ; 26 bytes: the 13 clock registers read (odd bytes), masked
rtc_saved	equ	$650                    ; 26 bytes: the time kept during the clock test (2 seconds on), and the
                                                ;   set-time image
test_errors	equ	$676                    ; the running test's error bits 0-7 (RAM bit 0, RS232 S0-S5, short BLiT
                                                ;   G1-G8, clock registers, SCC A, floppy drive A); non-zero skips the
                                                ;   start-up timer A check
test_errors_high	equ	$677            ; error bits 8-15 (ROM CRC, RS232 S6-SB, short BLiT G9-G12, SCC B
                                                ;   loopback, P BUSY, floppy drive B)
test_errors_extra	equ	$678            ; MIDI errors; P fire button errors; SCC A without its loopback plug
test_errors_last	equ	$679            ; P joystick direction errors; SCC B without its loopback plug
scc_a_async_errors	equ	$67a            ; port A async loopback errors
scc_b_async_errors	equ	$67b            ; port B async loopback errors
scc_a_modem_errors	equ	$67c            ; port A modem line errors (bit 0 DCD, 1 SYNC, 2 CTS)
scc_b_modem_errors	equ	$67d            ; port B modem line errors
scc_a_interrupt_errors	equ	$67e            ; port A interrupt test errors
scc_b_interrupt_errors	equ	$67f            ; port B interrupt test errors
scc_rx_int_errors	equ	$680            ; RR1 errors seen by the receive interrupts
scc_ext_int_seen	equ	$681            ; set by an external/status interrupt
scc_special_byte	equ	$682            ; the byte read by the special receive interrupt
scc_tx_int_seen	equ	$683                    ; set by a transmit interrupt
scc_rx_int_seen	equ	$684                    ; set by a receive interrupt
scc_tx_buffer	equ	$686                    ; 512 bytes sent in the SCC interrupt test ($FF..0, then $E5)
scc_rx_buffer	equ	$896                    ; 512 bytes received in the SCC interrupt test
scc_tx_pointer	equ	$a96                    ; the next byte to send ($886 at the end)
scc_rx_pointer	equ	$a9a                    ; where the next byte received goes ($A96 when all 512 are in)
fd_fill_word	equ	$a9e                    ; the word a track is formatted with
fd_interleave	equ	$aa0                    ; set to 1, copied to $B8C by the format routine and not used
fd_side	equ	$aa2                            ; floppy side
fd_track	equ	$aa4                    ; floppy track
fd_sector	equ	$aa6                    ; floppy sector
fd_count	equ	$aa8                    ; sectors to transfer
fd_drive	equ	$aaa                    ; floppy drive
fd_buffer	equ	$aac                    ; floppy buffer
floppy_retry	equ	$ab0                    ; set after the first failure of a write or read (soft error)
speed_ticks	equ	$ab2                    ; speed test: timer A ticks (651 us) in a revolution
speed_max	equ	$ac8                    ; speed test: the highest, BCD ms
speed_min	equ	$aca                    ; speed test: the lowest, BCD ms
bad_tracks	equ	$acc                    ; 160 bad track marks ($FF), side 1 from +80
read_errors	equ	$b6c                    ; exerciser read error count
write_errors	equ	$b6e                    ; exerciser write error count
format_errors	equ	$b70                    ; exerciser format error count
floppy_quiet	equ	$b72                    ; nonzero: errors not shown (drive type detection)
fd_retries	equ	$b76                    ; set to 2, not counted down
fd_cur_drive	equ	$b78
fd_cur_track	equ	$b7a
fd_cur_sector	equ	$b7c                    ; the sector being transferred
fd_cur_side	equ	$b7e
fd_sectors_left	equ	$b80                    ; sectors left
fd_cur_buffer	equ	$b82                    ; where the DMA is
fd_buffer_end	equ	$b86                    ; the end of the transfer
fd_format_sectors	equ	$b8a
fd_format_interleave	equ	$b8c            ; not used
fd_format_fill	equ	$b8e
dma_address_read	equ	$b90            ; the DMA address read back after a transfer
fd_default_error	equ	$b94            ; the error a floppy operation returns by default
fd_error	equ	$b96                    ; the floppy error code
fd_drive_a	equ	$bbc                    ; drive A: its head's track
fd_drive_b	equ	$bc0                    ; drive B: its head's track
acsi_timeout	equ	$bc4                    ; rounds left while waiting for the ACSI unit
hd_counter_a	equ	$bc8                    ; cleared at the hard disk test's start, not used further
hd_counter_b	equ	$bca                    ; cleared at the hard disk test's start, not used further
hd_counter_c	equ	$bcc                    ; cleared at the hard disk test's start, not used further
hd_counter_d	equ	$bce                    ; cleared at the hard disk test's start, not used further
hd_sectors_left	equ	$bd0                    ; sectors still to read (68 at the start)
hd_cylinder	equ	$bd2                    ; the cylinder shown in the status line (600)
hd_first_sector	equ	$bd4                    ; the test area's first sector ($9F1C)
hd_sector	equ	$bd8                    ; the next sector to read
acsi_sector	equ	$bdc                    ; the sector for the command (bytes $BDD-$BDF sent)
acsi_count	equ	$be0                    ; the sector count for the command
acsi_unit	equ	$be2                    ; the ACSI unit (0); its low byte is also sent as the LUN
acsi_dma_address	equ	$be4            ; the DMA address for the command
hd_bad_sectors	equ	$bee                    ; 32 longs: the known bad sector list
hd_bad_sectors_end	equ	$c6e            ; the end of the known bad sector list
vme_saved_vectors	equ	$c72            ; 8 longs: the vectors $300-$338 (8 bytes apart) kept during the VME
                                                ;   interrupt test
vme_saved_sr	equ	$c92                    ; the status register kept during the VME interrupt test
vme_saved_scu_mask	equ	$c94            ; the SCU's VME interrupt mask kept during the VME interrupt test
vme_int_counts	equ	$c9a                    ; 8 longs: the Xycom card's interrupts counted (B transmit, external,
                                                ;   receive, special; A the same)

	org	$fa0000
	dc.w	$fa52,$235f

;------------------------------------------------------------------------------
; cold_start: entered from TOS at reset (diagnostic cartridge) and from the GPIP7 monitor-change
; handler; nothing is set up and there is no RAM yet. Sizes the two RAM banks with the TOS method,
; sets the MMU, tests the low 2K, clears the variables, installs the exception and MFP vectors, finds
; a good 1K for the stack below $20000, then runs the start-up checks (VME RAM, FPU, timing, bus error
; handling) and enters the menu. Errors before the stack exists are sent to the RS232 port by
; register-only code at ram_fail_report.
;------------------------------------------------------------------------------
cold_start:	; from: monitor_change_handler, hd_park_fail_cycle
	move.w	#$a,$ffff8000.w                 ; MMU config, both banks 2M while sizing
	move.l	#$200,d2                        ; ST: bank repeats after $200 (128K banks)...
	move.l	#$400,d3                        ; ...or $400 (512K banks)
	clr.l	d6                              ; d6 bit 29 marks an STE palette
	movea.l	#$ffff8240,a0                   ; colour 0
	move.w	#$fff,(a0)                      ; write a 12-bit colour
	cmpi.w	#$fff,(a0)                      ; reads back intact only on a 4-bit STE palette
	bne.s	size_bank0                      ; ST palette: keep the ST offsets
	move.l	#$20000,d2                      ; STE: 128K banks repeat after $20000...
	move.l	#$80000,d3                      ; ...512K banks after $80000
	bset	#$1d,d6                         ; remember the STE palette
size_bank0:
	movea.l	#$10,a0                         ; bank 0 test address
	move.l	#$a5a51234,(a0)                 ; write two test longs
	move.l	#$5a5a8765,4(a0)                ; at $10 and $14
	cmpi.l	#$a5a51234,0(a0,d2.l)           ; seen again one 128K repeat higher?
	bne.s	size_bank0_not_128k             ; no
	cmpi.l	#$5a5a8765,4(a0,d2.l)           ; second long too?
	bne.s	size_bank0_not_128k             ; no
	move.l	#$20000,d1                      ; bank 0 is 128K
	moveq	#0,d0                           ; MMU bank 0 = 128K
	bra.s	size_bank1                      ; on to bank 1
size_bank0_not_128k:
	cmpi.l	#$a5a51234,0(a0,d3.l)           ; seen again one 512K repeat higher?
	bne.s	size_bank0_not_512k             ; no
	cmpi.l	#$5a5a8765,4(a0,d3.l)           ; second long too?
	bne.s	size_bank0_not_512k             ; no
	move.l	#$80000,d1                      ; bank 0 is 512K
	moveq	#4,d0                           ; MMU bank 0 = 512K
	bra.s	size_bank1                      ; on to bank 1
size_bank0_not_512k:
	cmpi.l	#$a5a51234,(a0)                 ; still there with no repeat?
	bne.s	size_bank0_fail                 ; no
	cmpi.l	#$5a5a8765,4(a0)                ; second long too?
	bne.s	size_bank0_fail                 ; no: bank 0 does not work
	move.l	#$200000,d1                     ; bank 0 is 2M
	moveq	#8,d0                           ; MMU bank 0 = 2M
	bra.s	size_bank1                      ; on to bank 1
size_bank0_fail:
	move.l	#$20000,d1                      ; 128K for the report
	moveq	#0,d0                           ; MMU value 0
	lea	msg_memory_configuration_error,a5 ; "I4 Memory configuration error"
	bra.w	ram_fail_report                 ; report it on RS232 and loop
size_bank1:
	movea.l	#$200000,a0                     ; bank 1 starts at 2M
	move.l	#$a5a51234,(a0)                 ; write the test longs into bank 1
	move.l	#$5a5a8765,4(a0)                ; second test long
	cmpi.l	#$a5a51234,0(a0,d2.l)           ; repeat after 128K?
	bne.s	size_bank1_not_128k             ; no
	cmpi.l	#$5a5a8765,4(a0,d2.l)           ; second long too?
	bne.s	size_bank1_not_128k             ; no
	addi.l	#$20000,d1                      ; bank 1 128K: add it (MMU bits stay 0)
	bra.s	size_banks_done                 ; done
size_bank1_not_128k:
	cmpi.l	#$a5a51234,0(a0,d3.l)           ; repeat after 512K?
	bne.s	size_bank1_not_512k             ; no
	addi.l	#$80000,d1                      ; bank 1 512K
	addq.l	#1,d0                           ; MMU bank 1 = 512K
	bra.s	size_banks_done                 ; done
size_bank1_not_512k:
	cmpi.l	#$a5a51234,(a0)                 ; still there with no repeat?
	bne.s	size_banks_done                 ; none of these: bank 1 adds nothing
	cmpi.l	#$5a5a8765,4(a0)                ; second long too?
	bne.s	size_banks_done                 ; no: bank 1 empty
	addi.l	#$200000,d1                     ; bank 1 2M
	addq.l	#2,d0                           ; MMU bank 1 = 2M
size_banks_done:
	move.w	d0,$ffff8000.w                  ; MMU config, set the found bank sizes in the MMU
	move.l	d1,d5                           ; d5 = total RAM in bytes

;------------------------------------------------------------------------------
; low_ram_test: tests the data lines at $8, then the RAM $8-$7FF (disturbance, address in address,
; inverted address) before anything is kept in RAM. Also re-entered after an error report to
; loop the test for a scope. Fails go to ram_data_line_fail, ram_disturb_fail, ram_address_fail.
;------------------------------------------------------------------------------
low_ram_test:	; from: bus_error_caught
	moveq	#0,d6                           ; data pattern 0
low_ram_test_retry:	; from: ram_fail_report
	move.w	d6,d0                           ; first data pattern 0
	movea.l	#$8,a0                          ; test word at $8
data_line_test_fixed:
	move.w	d0,(a0)                         ; write the pattern
	nop                                     ; let the bus settle
	move.w	(a0),d1                         ; read it back
	cmp.w	d0,d1                           ; read back right?
	bne.w	ram_data_line_fail              ; "I1 RAM/data line error"
	tst.w	d0                              ; 0 done: try all ones
	beq.s	data_line_test_walk1            ; all ones done too: walking one
	moveq	#-1,d0                          ; then $FFFF
	bra.s	data_line_test_fixed            ; now test $FFFF
data_line_test_walk1:
	moveq	#1,d0                           ; walking one from bit 0
	movea.l	#$8,a0                          ; test word at $8
data_line_walk1_next:
	move.w	d0,(a0)                         ; write the pattern
	nop                                     ; let the bus settle
	move.w	(a0),d1                         ; read it back
	cmp.w	d0,d1                           ; read back right?
	bne.w	ram_data_line_fail              ; "I1 RAM/data line error"
	lsl.w	#1,d0                           ; next bit
	cmpi.w	#$0,d0                          ; until the bit falls out
	bne.s	data_line_walk1_next            ; more bits
	move.w	#$fffe,d0                       ; then a walking zero
data_line_walk0_next:
	move.w	d0,(a0)                         ; write the pattern
	nop                                     ; let the bus settle
	move.w	(a0),d1                         ; read it back
	cmp.w	d0,d1                           ; read back right?
	bne.w	ram_data_line_fail              ; "I1 RAM/data line error"
	rol.w	#1,d0                           ; next bit
	cmpi.w	#$fffe,d0                       ; round to the start again
	bne.s	data_line_walk0_next            ; more bits
	movea.l	#$40000,a3                      ; fill limit: 256K
	movea.l	#$8,a0                          ; start of the test area
	movea.l	a0,sp                           ; keep the start of the test area in sp
	movea.l	#$800,a1                        ; end of the area under test
ram_fill_low_zero:
	move.l	#$0,(a0)+                       ; $8-$7FF all zeros
	cmpa.l	a0,a1                           ; end of the low area?
	bgt.s	ram_fill_low_zero               ; more
ram_fill_high_ones:
	move.l	#$ffffffff,(a1)+                ; $800-$3FFFF all ones
	cmpa.l	a1,a3                           ; end of the 256K?
	bgt.s	ram_fill_high_ones              ; more
	movea.l	sp,a0                           ; start again at $8
	movea.l	#$800,a1                        ; up to $800
	moveq	#0,d0
ram_check_low_zero:
	move.w	(a0),d1                         ; low area must still be zero
	bne.w	ram_disturb_fail                ; "I2 RAM disturbance"
	adda.l	#$2,a0                          ; next word
	cmpa.l	a0,a1                           ; end?
	bgt.s	ram_check_low_zero              ; more
	movea.l	sp,a0                           ; start again at $8
ram_fill_address:
	move.w	a0,(a0)+                        ; each word holds its own address
	cmpa.l	a0,a1                           ; end?
	bgt.s	ram_fill_address                ; more
	movea.l	sp,a0                           ; start again at $8
ram_check_address:
	move.w	(a0),d1                         ; read the word
	move.w	a0,d0                           ; its address
	cmp.w	d0,d1                           ; the same?
	bne.w	ram_address_fail                ; "I3 RAM address check"
	adda.l	#$2,a0                          ; next word
	cmpa.l	a0,a1                           ; end?
	bgt.s	ram_check_address               ; more
	movea.l	sp,a0                           ; start again at $8
ram_fill_inverse_address:
	move.w	a0,d0                           ; each word holds its inverted address
	eori.w	#$ffff,d0                       ; inverted
	move.w	d0,(a0)+                        ; store it
	cmpa.l	a0,a1                           ; end?
	bgt.s	ram_fill_inverse_address        ; more
	movea.l	sp,a0                           ; start again at $8
ram_check_inverse_address:
	move.w	(a0),d1                         ; read the word
	eori.w	#$ffff,d1                       ; invert it back
	move.w	a0,d0                           ; its address
	cmp.w	d0,d1                           ; the same?
	bne.w	ram_address_fail                ; "I3 RAM address check"
	adda.l	#$2,a0                          ; next word
	cmpa.l	a0,a1                           ; end?
	bgt.s	ram_check_inverse_address       ; more
	movea.l	#$8,a0                          ; low RAM good: clear $8-$FFF
	clr.l	d0                              ; zero
clear_low_ram:
	move.l	d0,(a0)+                        ; clear a long
	cmpa.l	#$1000,a0                       ; up to $FFF
	blt.s	clear_low_ram                   ; more
	move.l	d5,ram_top.w                    ; keep the RAM size
	movea.l	#exception_vectors,a0           ; exception vectors $8-$2F
	movea.l	#$8,a1                          ; from the bus error vector on
	moveq	#9,d0                           ; 10 vectors
install_exception_vectors:
	move.l	(a0)+,(a1)+                     ; copy a vector
	dbra	d0,install_exception_vectors    ; loop
	movea.l	#$60,a1                         ; spurious, autovectors and NMI $60-$7F
	movea.l	#interrupt_vectors,a0           ; "interrupt_vectors" table
	moveq	#7,d0                           ; 8 vectors
install_autovectors:
	move.l	(a0)+,(a1)+                     ; copy a vector
	dbra	d0,install_autovectors          ; loop
	movea.l	#mfp_vectors,a0                 ; the 16 MFP vectors $100-$13F
	movea.l	#$100,a1                        ; MFP vectors at $100
	moveq	#15,d0                          ; 16 vectors
install_mfp_vectors:
	move.l	(a0)+,(a1)+                     ; copy a vector
	dbra	d0,install_mfp_vectors          ; loop
	movea.l	#$200,sp                        ; temporary stack in low RAM
	movea.l	#$800,a6                        ; error records go below $800
	movea.l	#$1fc00,a0                      ; first try $1FC00-$1FFFF for the stack
	movea.l	#$20000,a1                      ; block end
find_stack_block:
	bsr.w	test_ram_range                  ; test this 1K
	move.w	a6,d0                           ; error record pointer
	andi.w	#$3ff,d0                        ; a6 unmoved: no error recorded
	beq.s	stack_block_good                ; block good
	suba.w	#$400,a0                        ; try the 1K below
	suba.w	#$400,a1
	cmpa.l	#$1f000,a0                      ; below $1F000?
	blt.w	stack_block_fail                ; no good block: fatal
	bra.s	find_stack_block                ; test it
stack_block_good:
	movea.l	a1,sp                           ; stack at the top of the good block
	bsr.w	mfp_reset                       ; MFP all off
	moveq	#15,d0                          ; interrupt 15: GPIP7 monitor change
	bsr.w	mfp_enable_interrupt            ; enable it
	move.w	#$2,rs232_rate.w                ; RS232 at 19200 baud
	bsr.w	video_setup                     ; screen at $10000, resolution from the monitor, RS232 on
	bsr.w	init_text_screen                ; screen output set-up
	bsr.w	clear_screen                    ; clear the screen
	lea	msg_hello_world,a5              ; "Hello World"
	bsr.w	print_string                    ; print it
	lea	msg_looking_for_vme_ram,a5      ; "Looking for VME RAM"
	bsr.w	print_string                    ; print it

;------------------------------------------------------------------------------
; VME RAM: one word written into VME A24 space at $AF0000. A bus error means no VME RAM; any write
; that completes counts as found (it is not read back). $234 = $5E found, 0 not found.
;------------------------------------------------------------------------------
check_vme_ram:
	movea.l	sp,a6                           ; keep sp for the bus error
	move.l	#vme_ram_none,$8.w              ; bus error: no VME RAM
	move.w	#$fa5e,d0                       ; test word
	movea.l	#$af0000,a0                     ; VME A24 space
	move.w	d0,(a0)                         ; bus error here if no VME card
	move.b	d0,vme_ram_found.w              ; found: VME flag = $5E
	bra.s	check_fpu                       ; on to the FPU
vme_ram_none:
	movea.l	a6,sp                           ; drop the bus error frame
	move.l	#bus_error_handler,$8.w         ; bus error vector, normal bus error handler back
	clr.b	d0
	move.b	d0,vme_ram_found.w              ; VME flag = 0
	lea	msg_vme_ram_not_found,a5        ; "VME RAM not found"
	bsr.w	print_string                    ; print it

;------------------------------------------------------------------------------
; check_fpu: reads the response register of a 68881 in peripheral mode at $FFFFFA40 until it says
; idle ($0802). A bus error means no FPU: "FPU not found" and a red background. There is no
; timeout: an FPU that never answers $0802 hangs here. The result is not kept.
;------------------------------------------------------------------------------
check_fpu:	; from: check_vme_ram
	lea	msg_looking_for_fpu,a5          ; "Looking for FPU"
	bsr.w	print_string                    ; print it
	movea.l	$8.w,a4                         ; keep the bus error vector
	move.l	#check_fpu_none,$8.w            ; bus error: no FPU
	movea.l	sp,a6                           ; keep sp for the bus error
check_fpu_wait_idle:
	cmpi.w	#$802,$fffffa40.w               ; FPU response, response CIR = idle?
	bne.s	check_fpu_wait_idle             ; wait for it
	lea	msg_fpu_idle,a5                 ; "FPU idle"
	bsr.w	print_string                    ; print it
	bra.s	startup_beep
check_fpu_none:
	movea.l	a6,sp                           ; drop the bus error frame
	lea	msg_fpu_not_found,a5            ; "FPU not found"
	bsr.w	print_string                    ; print it
	move.l	a4,$8.w                         ; old bus error vector back
	move.w	#$500,$ffff8240.w               ; palette 0, red: error
	bsr.w	print_newline                   ; new line
startup_beep:
	lea	$ffff8800.w,a0                  ; PSG register select
	lea	$ffff8802.w,a1                  ; PSG write data
	bsr.w	psg_sound_off                   ; PSG volumes off
	move.b	#$8,(a0)                        ; volume A 0
	move.b	#$0,(a1)
	move.b	#$9,(a0)                        ; volume B 0
	move.b	#$0,(a1)
	move.b	#$a,(a0)                        ; volume C 0
	move.b	#$0,(a1)
	move.b	#$7,(a0)                        ; mixer: all tones and noise on, port A and B outputs
	move.b	#$c0,(a1)
	move.b	#$f,(a0)                        ; port B
	move.b	#$c0,(a1)                       ; all bits high
	move.b	#$e,(a0)                        ; port A
	move.b	#$66,(a1)                       ; $66: both drives deselected, side 0, strobe high
	move.w	#$e8,d0                         ; LMC1992 master volume 0 dB
	bsr.w	lmc1992_write                   ; to the LMC1992
	move.w	#$154,d0                        ; left volume 0 dB
	bsr.w	lmc1992_write                   ; to the LMC1992
	move.w	#$114,d0                        ; right volume 0 dB
	bsr.w	lmc1992_write                   ; to the LMC1992
	move.w	#$86,d0                         ; treble flat
	bsr.w	lmc1992_write                   ; to the LMC1992
	move.w	#$46,d0                         ; bass flat
	bsr.w	lmc1992_write                   ; to the LMC1992
	move.w	#$1,d0                          ; mix the YM in
	bsr.w	lmc1992_write                   ; to the LMC1992
	moveq	#0,d2                           ; channel A
	moveq	#4,d7                           ; tone period high = 4
	moveq	#-30,d6                         ; tone period low = $E2
	bsr.w	psg_tone_loud                   ; start the tone, volume 15
	move.w	#$190,d1                        ; 401 delays, about 0.9 s
startup_beep_wait:
	bsr.w	delay                           ; wait
	dbra	d1,startup_beep_wait            ; loop

;------------------------------------------------------------------------------
; check_bus_error: a word write to address $000000 must take a bus error (on the ST the first 8
; bytes are ROM, and a write there gets no DTACK even in supervisor mode). bus_error_caught sets
; d7, drops the 8 bytes of 68000 group 0 information (status word, access address, instruction)
; and returns with rte to the stacked PC. The nop after the write makes either PC the 68000 can
; stack land well: $3C8 runs as ori.b #$71,d0 (the nop is its data), $3CA runs the nop. If the
; write completes without a bus error: "I7 Bus error not detected" and a red background; start-up
; carries on either way. Neither the access address nor the status word is checked.
;------------------------------------------------------------------------------
check_bus_error:
	lea	msg_checking_bus_error_handling,a5 ; "Checking Bus error handling"
	bsr.w	print_string                    ; print it
	movea.l	$8.w,a4                         ; keep the bus error vector
	move.l	#bus_error_caught,$8.w          ; bus error vector
	clr.w	d7                              ; d7 = 0: no bus error yet
	move.w	d0,$0.w                         ; write to ROM at 0: must bus error
	nop                                     ; rte lands here (or on the write's second word)
	move.l	a4,$8.w                         ; bus error vector back
	tst.w	d7                              ; bus error taken?
	bne.w	startup_scu_setup               ; yes: right
	lea	msg_bus_error_not_detected,a5   ; "I7 Bus error not detected"
	bsr.w	print_string                    ; print it
	move.w	#$500,$ffff8240.w               ; palette 0, red: error
startup_scu_setup:
	move.w	#$2400,sr                       ; interrupts at level 5 and up (MFP)
	move.b	#$14,$ff8e01                    ; SCU system mask: HBL (2) and VBL (4)
	move.b	#$40,$ff8e0d                    ; SCU VME mask: MFP (6) only
	move.b	#$2,mode_flags.w                ; menu flags: RS232 terminal off
	clr.b	startup_checks_done.w           ; timing test: report fails only
	bsr.w	timing_test                     ; T timing test
	move.b	#$ea,startup_checks_done.w      ; from now the timing test also reports Pass
	move.b	#$0,$ff8e21                     ; Mega STE cache and CPU speed, 8 MHz, cache off
	tst.b	test_errors.w                   ; a test failed?
	bne.s	startup_done                    ; skip the Timer A check
	move.b	#$4,$fffffa1f.w                 ; MFP TADR, Timer A data 4
	move.b	#$d,d0                          ; interrupt 13: Timer A
	bsr.w	mfp_enable_interrupt            ; enable it
	move.b	#$7,$fffffa19.w                 ; MFP TACR, Timer A /200 = 3072 Hz, every 325 us
	move.b	#$1,timer_irq_flags.w           ; flag: Timer A handler clears it
	move.w	#$c8,d7                         ; ~2000 cycle wait, 250 us at 8 MHz
timer_a_check_sync:
	tst.b	timer_irq_flags.w               ; wait for one Timer A interrupt
	bne.s	timer_a_check_sync
	move.b	#$1,timer_irq_flags.w           ; set the flag again
timer_a_check_wait:
	dbra	d7,timer_a_check_wait           ; wait shorter than one Timer A period
	move.b	#$0,$fffffa19.w                 ; MFP TACR, Timer A stop
	tst.b	timer_irq_flags.w               ; no interrupt in that time?
	bne.s	startup_done                    ; right: on to the menu
	move.w	#$e8,d0                         ; Timer A came too soon: CPU or MFP clock wrong
	bsr.w	lmc1992_write                   ; LMC1992 master volume 0 dB
	move.w	#$154,d0
	bsr.w	lmc1992_write                   ; left 0 dB
	move.w	#$114,d0
	bsr.w	lmc1992_write                   ; right 0 dB
	move.w	#$1,d0
	bsr.w	lmc1992_write                   ; mix the YM in
	moveq	#0,d2                           ; channel A
timer_a_check_fail_beep:
	bsr.w	audio_test_step                 ; error beep for ever
	bra.s	timer_a_check_fail_beep
startup_done:
	bsr.w	mfp_disable_interrupt           ; interrupt 15 off again
	bsr.w	keyboard_setup                  ; keyboard and ACIA set-up
	move.b	#$3,$ff8e21                     ; Mega STE cache and CPU speed, 16 MHz, cache on
	bra.w	menu_start                      ; to the menu

;------------------------------------------------------------------------------
; bus_error_caught: bus error handler for the start-up bus error check and the T timing test: sets d7
; to -1, drops the 8 bytes of 68000 group 0 information and returns to the stacked PC.
;------------------------------------------------------------------------------
bus_error_caught:	; from: check_bus_error, timing_test
	moveq	#-1,d7                          ; bus error seen
	adda.w	#$8,sp                          ; leave SR and PC
	rte                                     ; back after the faulting access
stack_block_fail:	; from: low_ram_test
	move.b	#$2,mode_flags.w                ; RS232 terminal off
	moveq	#2,d0                           ; 19200 baud
	bsr.w	rs232_setup_rate                ; set up the RS232 port
	bsr.w	print_ram_errors                ; print the RAM error records
	bra.w	low_ram_test                    ; test the low RAM again, for ever
ram_data_line_fail:	; from: low_ram_test
	movea.l	#msg_ram_data_line_error,a5     ; "I1 RAM/data line error"
	bra.s	ram_fail_report                 ; report it
ram_disturb_fail:	; from: low_ram_test
	movea.l	#msg_ram_disturbance,a5         ; "I2 RAM disturbance"
	bra.s	ram_fail_report                 ; report it
ram_address_fail:	; from: low_ram_test
	movea.l	#msg_ram_address_check,a5       ; "I3 RAM address check"

;------------------------------------------------------------------------------
; ram_fail_report: reports a RAM error on RS232 without using RAM: no stack, the "subroutines" below
; return with jmp (a0)/(a1)/(a2). Prints the text at a5, then the written (d0) and read (d1) words in
; binary, then "00" and the low word of the failing address in hex (meant to be the address's top
; byte, but swap d2 leaves 0 there). Then a red screen and the low RAM test again, for a scope loop.
; In: a5 the text, d0 written, d1 read, a0 the address. Out: never returns.
;------------------------------------------------------------------------------
ram_fail_report:	; from: cold_start, bus_error_caught
	move.l	a0,d5                           ; keep the failing address
	lea	$fffffa01.w,a4                  ; MFP GPIP
	move.b	#$11,$1c(a4)                    ; Timer C and D /4
	move.b	#$2,$24(a4)                     ; Timer D data 2: 19200 baud
	move.b	#$98,$28(a4)                    ; UCR: /16, 8 bits, 2 stop, no parity
	move.b	#$1,$2a(a4)                     ; receiver on
	move.b	#$1,$2c(a4)                     ; transmitter on
	move.l	#$7d0,d7                        ; 2001 loops
ram_fail_report_delay:
	dbra	d7,ram_fail_report_delay        ; let the port settle
	lea	ram_fail_report_values,a0       ; return address
	bra.w	rs232_raw_print_text            ; print the error text
ram_fail_report_values:
	cmp.w	d0,d1                           ; read back what was written?
	beq.s	ram_fail_report_done            ; then no values to show
	lea	ram_fail_report_space1,a0       ; return address
	bra.w	rs232_raw_print_binary          ; the written word in binary
ram_fail_report_space1:
	lea	ram_fail_report_read,a2         ; return address
	moveq	#32,d3                          ; space
	bra.w	rs232_raw_send                  ; send it
ram_fail_report_read:
	move.w	d1,d0                           ; the read word
	lea	ram_fail_report_space2,a0       ; return address
	bra.w	rs232_raw_print_binary          ; the read word in binary
ram_fail_report_space2:
	lea	ram_fail_report_address,a2      ; return address
	moveq	#32,d3                          ; space
	bra.w	rs232_raw_send                  ; send it
ram_fail_report_address:
	move.l	d5,d1                           ; failing address
	beq.s	ram_fail_report_done            ; none: done
	swap	d2                              ; the byte printed is 0 (d2 = $FFFF here)
	lea	ram_fail_report_address_low,a1  ; return address
	bra.w	rs232_raw_print_hex_byte        ; one byte in hex
ram_fail_report_address_low:
	lea	ram_fail_report_done,a0         ; return address
	bra.w	rs232_raw_print_hex_word        ; the address low word in hex
	lea	ram_fail_report_done,a0         ; not reached: CR/LF
	bra.s	rs232_raw_newline
ram_fail_report_done:
	move.w	#$500,$ffff8240.w               ; palette 0, red
	move.b	#$1,$ffff8201.w                 ; video base high, screen at $10000
	clr.b	$ffff8203.w                     ; video base mid
	lea	$10000,a0                       ; clear the screen
	moveq	#0,d0
ram_fail_clear_screen:
	move.w	d0,(a0)+                        ; clear a word
	cmpa.l	#$18000,a0                      ; end of the screen?
	bne.s	ram_fail_clear_screen           ; more
	lsl.w	#1,d6                           ; next data pattern
	bra.w	low_ram_test_retry              ; run the test again
rs232_raw_print_text:
	move.b	(a5)+,d2                        ; next character
	cmpi.b	#$0,d2                          ; end of the text?
	beq.s	rs232_raw_print_text_done       ; end of text
rs232_raw_print_text_wait:
	tst.b	$2c(a4)                         ; transmitter empty?
	bpl.s	rs232_raw_print_text_wait       ; wait
	move.b	d2,$2e(a4)                      ; send it
	bra.s	rs232_raw_print_text            ; next character
rs232_raw_print_text_done:
	jmp	(a0)                            ; return
rs232_raw_newline:
	tst.b	$2c(a4)                         ; transmitter empty?
	bpl.s	rs232_raw_newline               ; wait
	move.b	#$d,$2e(a4)                     ; CR
rs232_raw_newline_lf:
	tst.b	$2c(a4)                         ; transmitter empty?
	bpl.s	rs232_raw_newline_lf            ; wait
	move.b	#$a,$2e(a4)                     ; LF
	jmp	(a0)                            ; return
rs232_raw_print_binary:
	andi.b	#$fe,ccr                        ; clear carry
	moveq	#15,d2                          ; 16 bits
rs232_raw_print_binary_bit:
	tst.b	$2c(a4)                         ; transmitter empty?
	bpl.s	rs232_raw_print_binary_bit      ; wait
	lsl.w	#1,d0                           ; next bit out at the top
	bcc.s	rs232_raw_print_binary_zero     ; 0 bit
	move.b	#$31,$2e(a4)                    ; "1"
	bra.s	rs232_raw_print_binary_next
rs232_raw_print_binary_zero:
	move.b	#$30,$2e(a4)                    ; "0"
rs232_raw_print_binary_next:
	dbra	d2,rs232_raw_print_binary_bit   ; next bit
	jmp	(a0)                            ; return
rs232_raw_print_hex_word:
	move.w	d1,d2                           ; high byte first
	lsr.w	#8,d2
	lea	rs232_raw_print_hex_word_low,a1 ; return address
	bra.s	rs232_raw_print_hex_byte
rs232_raw_print_hex_word_low:
	move.w	d1,d2                           ; then the low byte
	lea	rs232_raw_print_hex_word_done,a1 ; return address
	bra.s	rs232_raw_print_hex_byte
rs232_raw_print_hex_word_done:
	jmp	(a0)                            ; return
rs232_raw_print_hex_byte:
	move.b	d2,d3                           ; high digit
	lsr.b	#4,d3
	lea	rs232_raw_print_hex_byte_low,a2 ; return address
	bra.s	rs232_raw_print_digit
rs232_raw_print_hex_byte_low:
	move.b	d2,d3                           ; low digit
	lea	rs232_raw_print_hex_byte_done,a2 ; return address
	bra.s	rs232_raw_print_digit
rs232_raw_print_hex_byte_done:
	jmp	(a1)                            ; return
rs232_raw_print_digit:
	andi.b	#$f,d3
	cmp.b	#$9,d3                          ; 0-9?
	bls.s	rs232_raw_print_digit_number    ; yes
	and.w	#$7,d3                          ; A-F: $A..$F -> 'A'..'F'
	subq.w	#1,d3
	ori.b	#$40,d3
rs232_raw_send:
	tst.b	$2c(a4)                         ; transmitter empty?
	bpl.s	rs232_raw_send                  ; wait
	move.b	d3,$2e(a4)                      ; send d3
	jmp	(a2)                            ; return
rs232_raw_print_digit_number:
	ori.b	#$30,d3                         ; '0'..'9'
	bra.s	rs232_raw_send                  ; send it

;------------------------------------------------------------------------------
; start_timer_a: starts MFP Timer A. In: d0 control (prescale), d1 data. Sets $20A to 1 (the Timer A
; count-down handler counts it to 0). Changes a0.
;------------------------------------------------------------------------------
start_timer_a:	; from: timing_test
	lea	$fffffa01.w,a0                  ; MFP GPIP
	move.b	#$0,$18(a0)                     ; Timer A stop
	move.b	d1,$1e(a0)                      ; data
	move.b	d0,$18(a0)                      ; start
	move.b	#$1,timer_a_count.w             ; Timer A count
	rts

;------------------------------------------------------------------------------
; video_setup: screen at $10000 and waits for the video counter to be there (the VBL reload); high
; resolution on a mono monitor (GPIP7 low), else medium with colour 3 = $666; background $003 (blue);
; then falls into rs232_setup. Changes d0, a0-a2.
;------------------------------------------------------------------------------
video_setup:	; from: low_ram_test, colour_test
	movea.l	#$ff8200,a2                     ; video registers
	move.b	#$1,1(a2)                       ; screen at $010000
	clr.b	3(a2)
video_setup_wait_high:
	cmpi.b	#$1,5(a2)                       ; video counter high = 1?
	bne.s	video_setup_wait_high           ; wait
video_setup_wait_mid:
	cmpi.b	#$0,7(a2)                       ; video counter mid = 0?
	bne.s	video_setup_wait_mid            ; wait
video_setup_wait_low:
	cmpi.b	#$0,9(a2)                       ; video counter low = 0?
	bne.s	video_setup_wait_low            ; wait
	lea	$fffffa01.w,a0                  ; MFP GPIP
	lea	$ffff8240.w,a1                  ; palette 0
	btst	#$7,0(a0)                       ; GPIP7: colour monitor?
	bne.s	video_setup_colour              ; yes
	move.b	#$2,$60(a2)                     ; mono: high resolution
	bra.s	video_setup_background
video_setup_colour:
	move.b	#$1,$60(a2)                     ; colour: medium resolution
	move.w	#$666,6(a1)                     ; colour 3 grey
video_setup_background:
	move.w	#$3,(a1)                        ; background blue

;------------------------------------------------------------------------------
; rs232_setup: sets the RS232 port to the rate in $22E. rs232_setup_rate: In d0 the Timer D data
; (2 = 19200 baud ... $40 = 600). 8 bits, 2 stop bits, no parity; reads UDR to drop a waiting byte.
; Changes d0, a0.
;------------------------------------------------------------------------------
rs232_setup:	; from: read_command_line, bus_error_handler, rs232_test, timing_test
	move.w	rs232_rate.w,d0                 ; Timer D data from the rate setting

rs232_setup_rate:	; from: bus_error_caught, rs232_test
	lea	$fffffa01.w,a0                  ; MFP GPIP
	move.b	#$11,$1c(a0)                    ; Timer C and D /4
	move.b	d0,$24(a0)                      ; Timer D data: baud rate
	move.b	#$98,$28(a0)                    ; UCR: /16, 8 bits, 2 stop, no parity
	move.b	#$1,$2a(a0)                     ; receiver on
	move.b	#$1,$2c(a0)                     ; transmitter on
	move.b	$2e(a0),d0                      ; drop any waiting byte
	bsr.w	delay                           ; wait
	rts

;------------------------------------------------------------------------------
; mfp_reset: all MFP interrupts off (enable, mask, pending, in-service), AER, DDR and GPIP cleared,
; vector base $40 with software end of interrupt. Changes a0.
;------------------------------------------------------------------------------
mfp_reset:	; from: low_ram_test
	movea.l	#$fffffa01,a0                   ; MFP
	clr.b	$12(a0)                         ; IMRA
	clr.b	$14(a0)                         ; IMRB
	clr.b	6(a0)                           ; IERA
	clr.b	8(a0)                           ; IERB
	clr.b	$a(a0)                          ; IPRA
	clr.b	$c(a0)                          ; IPRB
	clr.b	$e(a0)                          ; ISRA
	clr.b	$10(a0)                         ; ISRB
	clr.b	2(a0)                           ; AER
	clr.b	4(a0)                           ; DDR
	clr.b	0(a0)                           ; GPIP
	move.b	#$48,$16(a0)                    ; VR: vectors $100, software end of interrupt
	rts

;------------------------------------------------------------------------------
; keyboard_setup: clears the menu and IKBD packet state, sets the keyboard buffer record at $45C and a
; second one at $46A from acia_buffer_records_init, the key release ring $482-$489, resets the MIDI ACIA
; (left reset) and the keyboard ACIA (/64, 8N1, receive interrupt) and installs acia_interrupt as MFP
; interrupt 6. Changes d0, a0-a2.
;------------------------------------------------------------------------------
keyboard_setup:	; from: check_bus_error
	clr.b	mode_flags.w                    ; menu flags
	clr.b	shift_held.w                    ; shift state
	clr.b	ikbd_packet_type.w              ; IKBD packet type
	clr.b	ikbd_packet_count.w             ; IKBD packet bytes to come
	movea.l	#$45c,a0                        ; keyboard buffer record
	movea.l	#acia_buffer_records_init,a1    ; "acia_buffer_records_init"
	moveq	#29,d0                          ; 30 bytes
	bsr.w	copy_bytes
	move.l	#$482,release_ring_write.w      ; release ring write pointer
	move.l	#$482,release_ring_read.w       ; release ring read pointer
	move.l	#acia_service_done,kbd_byte_hook.w ; keyboard ACIA hook: rts
	bsr.w	midi_registers                  ; a1 = MIDI ACIA
	move.b	#$3,0(a1)                       ; MIDI ACIA master reset
	bsr.w	keyboard_acia_regs              ; a1 = keyboard ACIA
	move.b	#$3,0(a1)                       ; keyboard ACIA master reset
	move.b	#$96,0(a1)                      ; /64, 8N1, receive interrupt on
	moveq	#6,d0                           ; MFP interrupt 6: ACIA
	movea.l	#acia_interrupt,a2              ; the handler
	bsr.w	mfp_install_handler
	rts

;------------------------------------------------------------------------------
; acia_buffer_records_init: 30 bytes copied to $45c at start-up (keyboard_setup, d0 = 29). Two
; buffer records, each a long buffer address, then words size, head, tail, low mark and high
; mark: the keyboard receive buffer (64 bytes at $3dc, record at $45c, used with the keyboard
; ACIA $FFFC00) and a second 64-byte buffer at $41c (record at $46a); then a spare word.
;------------------------------------------------------------------------------
acia_buffer_records_init:	; from: keyboard_setup
	dc.l	$000003dc                       ; keyboard buffer at $3dc
	dc.w	$0040,$0000,$0000,$0010,$0030   ; size 64, head, tail, low mark 16, high mark 48
	dc.l	$0000041c                       ; second buffer at $41c
	dc.w	$0040,$0000,$0000,$0010,$0030,$0000 ; size 64, head, tail, low mark 16, high mark 48, spare word

;------------------------------------------------------------------------------
; mfp_install_handler: In d0 the MFP interrupt (0-15), a2 the handler. Turns the interrupt off, puts a2
; in vector $100+d0*4 and turns it on (enable and mask). Keeps all registers.
;------------------------------------------------------------------------------
mfp_install_handler:	; from: keyboard_setup, mono_monitor_test, floppy_speed_test
	movem.l	d0-d2/a0-a3,-(sp)               ; save registers
	bsr.w	mfp_disable_interrupt           ; off while the vector changes
	move.l	d0,d2                           ; interrupt number
	asl.w	#2,d2                           ; vector offset
	addi.l	#$100,d2                        ; MFP vectors at $100
	movea.l	d2,a3                           ; the vector
	move.l	a2,(a3)                         ; new handler
	bsr.w	mfp_enable_interrupt
	movem.l	(sp)+,d0-d2/a0-a3               ; restore registers
	rts

;------------------------------------------------------------------------------
; mfp_disable_interrupt: In d0 the MFP interrupt (0-15). Clears its mask, enable, pending and in-service
; bits with interrupts off. Keeps all registers.
;------------------------------------------------------------------------------
mfp_disable_interrupt:                          ; from: check_bus_error, mfp_install_handler, colour_test,
                                                ;   reset_keyboard_and_check, rs232_test, dma_sound_test, 2 more
	movem.l	d0-d1/a0-a1,-(sp)               ; save registers
	move.w	sr,-(sp)                        ; keep the interrupt level
	move.w	#$2700,sr                       ; no interrupts
	movea.l	#$fffffa01,a0                   ; MFP
	lea	$12(a0),a1                      ; mask
	bsr.w	mfp_bit_register                ; bit and register
	bclr	d1,(a1)                         ; mask off
	lea	6(a0),a1                        ; enable
	bsr.w	mfp_bit_register                ; bit and register
	bclr	d1,(a1)                         ; enable off
	lea	$a(a0),a1                       ; pending
	bsr.w	mfp_bit_register                ; bit and register
	bclr	d1,(a1)                         ; pending off
	lea	$e(a0),a1                       ; in service
	bsr.w	mfp_bit_register                ; bit and register
	bclr	d1,(a1)                         ; in service off
	move.w	(sp)+,sr                        ; interrupt level back
	movem.l	(sp)+,d0-d1/a0-a1               ; restore registers
	rts

;------------------------------------------------------------------------------
; mfp_enable_interrupt: In d0 the MFP interrupt (0-15). Sets its enable and mask bits with interrupts
; off. Keeps all registers.
;------------------------------------------------------------------------------
mfp_enable_interrupt:                           ; from: low_ram_test, check_bus_error, mfp_install_handler, colour_test,
                                                ;   reset_keyboard_and_check, rs232_test, 2 more
	movem.l	d0-d1/a0-a1,-(sp)               ; save registers
	move.w	sr,-(sp)                        ; keep the interrupt level
	move.w	#$2700,sr                       ; no interrupts
	movea.l	#$fffffa01,a0                   ; MFP
	lea	6(a0),a1                        ; enable
	bsr.w	mfp_bit_register                ; bit and register
	bset	d1,(a1)                         ; enable on
	lea	$12(a0),a1                      ; mask
	bsr.w	mfp_bit_register                ; bit and register
	bset	d1,(a1)                         ; mask on
	move.w	(sp)+,sr                        ; interrupt level back
	movem.l	(sp)+,d0-d1/a0-a1               ; restore registers
	rts

;------------------------------------------------------------------------------
; mfp_bit_register: In d0 the MFP interrupt, a1 the A register of a pair. Out: d1 the bit; a1 moved to
; the B register for interrupts 0-7.
;------------------------------------------------------------------------------
mfp_bit_register:	; from: mfp_disable_interrupt, mfp_enable_interrupt
	move.b	d0,d1                           ; bit = interrupt number
	cmp.b	#$8,d0                          ; 8-15: A register, bit d0-8
	blt.s	mfp_bit_register_b              ; 0-7
	subq.w	#8,d1                           ; 8-15: bit 0-7
mfp_bit_register_b:
	cmp.b	#$8,d0
	bge.s	mfp_bit_register_done           ; 8-15: A register
	addq.w	#2,a1                           ; 0-7: B register
mfp_bit_register_done:
	rts

;------------------------------------------------------------------------------
; delay: waits 1000 loops, about 2.25 ms at 8 MHz. Keeps all registers.
;------------------------------------------------------------------------------
delay:	; from: check_fpu, rs232_setup_rate, menu, pause_clear_status, colour_test, rs232_test, 7 more
	move.l	d0,-(sp)
	move.l	#$3e8,d0                        ; 1000 loops
delay_loop:
	subq.l	#1,d0
	bne.s	delay_loop
	move.l	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; copy_bytes: copies d0+1 bytes from a1 to a0. Out: a0, a1 past the end; d0 = -1.
;------------------------------------------------------------------------------
copy_bytes:	; from: keyboard_setup, midi_test, run_bus_test_in_ram
	move.b	(a1)+,(a0)+                     ; copy a byte
	dbra	d0,copy_bytes                   ; loop
	rts

;------------------------------------------------------------------------------
; menu_start: first entry to the menu after start-up. Looks for the BLiTTER, resets the keyboard and
; reads its version, turns the mouse off and plays the pass or fail sound for start-up. A red screen
; (start-up error) is left as it is so its messages stay visible; otherwise falls into menu.
;------------------------------------------------------------------------------
menu_start:	; from: check_bus_error
	clr.b	drive_a_type.w                  ; cleared at each menu start
	clr.b	drive_b_type.w                  ; cleared at each menu start
	bsr.w	blit_check_present              ; BLiTTER present? (bus error test)
	clr.b	mode_flags.w                    ; menu flags clear: RS232 terminal on
	bsr.w	reset_keyboard_and_check        ; IKBD reset, read its version
	beq.s	menu_start_keyboard_ok          ; answered
	btst	#$0,mode_flags.w                ; keyboard failed?
	beq.s	menu_start_keyboard_ok          ; no
	lea	msg_keyboard_failed,a5          ; "Keyboard failed, connect RS232 terminal"
	bsr.w	print_string                    ; print it
menu_start_keyboard_ok:
	moveq	#18,d1                          ; IKBD $12: mouse off
	bsr.w	ikbd_send                       ; send it
	bsr.w	result_sound                    ; pass or fail sound
	bsr.w	screen_is_red                   ; screen red?
	beq.s	menu_check_terminal             ; yes: keep the start-up messages

;------------------------------------------------------------------------------
; menu: clears the screen, blue background, sound off, then decides whether the RS232 port has a
; terminal, prints the title, RAM size, keyboard revision, 50/60 Hz and TOS version and the menu, reads
; a command line and runs the tests in it. Re-entered after every command and from the tests.
;------------------------------------------------------------------------------
menu:	; from: run_q_tests, floppy_menu_jump_table
	bsr.w	clear_screen                    ; clear the screen
	move.w	#$3,$ffff8240.w                 ; palette 0, background blue
	andi.b	#$c7,mode_flags.w               ; no sequence, single test, no repeat count
	moveq	#18,d1                          ; IKBD $12: mouse off
	bsr.w	ikbd_send                       ; send it
	bsr.w	sound_quiet                     ; sound off
menu_check_terminal:	; from: menu_start
	bclr	#$1,mode_flags.w                ; RS232 terminal on
	move.b	$fffffa2f.w,d0                  ; MFP UDR, drop any waiting byte
	move.b	#$d,d0                          ; (rs232_send sends d1, not d0)
	bsr.w	serial_put_char                 ; send a byte on RS232
	moveq	#40,d0                          ; 41 delays, about 90 ms
menu_check_terminal_wait:
	bsr.s	delay                           ; wait
	dbra	d0,menu_check_terminal_wait     ; loop
	bsr.w	rs232_byte_waiting              ; a byte came straight back?
	beq.s	menu_title                      ; no: a terminal may be there
	move.b	$fffffa2f.w,d0                  ; MFP UDR, drop it
	bset	#$1,mode_flags.w                ; loopback or echo: RS232 terminal off
menu_title:
	movea.l	#msg_title,a5                   ; "MEGA-STE Field Service Diagnostic Rev. 1.5 ... 1991, Atari Corp."
	bsr.w	print_string                    ; print it
	bsr.w	put_tab                         ; tab
	move.l	ram_top.w,d0                    ; RAM size
	swap	d0                              ; in units of 64K
	andi.l	#$fe,d0                         ; even
	moveq	#0,d1
	lea	ram_size_codes,a0               ; sizes 256K, 512K, 1M, 2M, 4M
	moveq	#4,d1                           ; 5 sizes
menu_ram_size_find:
	cmp.b	0(a0,d1.w),d0                   ; this size?
	beq.s	menu_ram_size_print             ; found
	dbra	d1,menu_ram_size_find           ; next size
	bra.s	menu_keyboard_rev               ; other size: print none
menu_ram_size_print:
	lea	ram_size_texts,a0               ; "256k RAM" ... "4M RAM" texts
	lsl.w	#2,d1                           ; text pointer offset
	movea.l	0(a0,d1.w),a5
	bsr.w	print_string                    ; print it
menu_keyboard_rev:
	tst.b	keyboard_revision.w             ; keyboard revision known?
	bmi.s	menu_frequency                  ; no
	lea	msg_keyboard_rev,a5             ; " Keyboard rev. "
	bsr.w	print_string                    ; print it
	move.b	keyboard_revision.w,d0          ; revision number
	bsr.w	word_to_bcd                     ; to BCD
	bsr.w	print_hex_digit                 ; one digit
menu_frequency:
	bsr.w	put_tab                         ; tab
	move.b	$ffff820a.w,d0                  ; sync mode
	btst	#$1,d0                          ; 50 Hz?
	beq.s	menu_frequency_60               ; no: 60 Hz
	lea	msg_50_hz,a5                    ; "50 Hz"
	bra.s	menu_frequency_print
menu_frequency_60:
	lea	msg_60_hz,a5                    ; "60 Hz"
menu_frequency_print:
	bsr.w	print_string                    ; print it
	bsr.w	print_tos_version               ; TOS version from the ROM header
	bsr.w	print_newline                   ; new line
	movea.l	#menu_text,a5                   ; the menu text ($05 toggles inverse)
	bsr.w	print_menu_string
	btst	#$0,mode_flags.w                ; keyboard failed?
	bne.s	menu_read_command               ; yes: leave them
	moveq	#26,d1                          ; IKBD $1A: joysticks off
	bsr.w	ikbd_send                       ; send it
menu_read_command:
	bsr.w	read_command_line               ; read a command line
	tst.w	d0                              ; anything to run?
	beq.w	menu                            ; empty or a direct command: menu again
	move.l	#$1,test_cycle.w                ; cycle 1
	bclr	#$6,mode_flags.w                ; no test has run yet
	lea	test_letters.w,a6               ; test letters list
	lea	number_digits.w,a3              ; repeat count digits
menu_parse_count:
	move.b	-(a4),d0                        ; from the end of the line back
	cmpi.b	#$30,d0                         ; a digit?
	blt.s	menu_parse_letter               ; no
	cmpi.b	#$39,d0
	bgt.s	menu_parse_letter               ; no
	move.b	d0,(a3)+                        ; keep it (lowest digit first)
	bra.s	menu_parse_count                ; next character
menu_parse_letters:
	cmpa.l	#$239,a4                        ; start of the line reached?
	ble.s	menu_parse_done                 ; yes: done
	move.b	-(a4),d0                        ; previous character
menu_parse_letter:
	lea	menu_test_letters,a0            ; "ROMSTDILFPGYVQZ"
	moveq	#0,d7                           ; letter index
menu_parse_letter_find:
	cmp.b	0(a0,d7.w),d0                   ; a test letter?
	beq.s	menu_parse_letter_keep          ; found
	addq.w	#1,d7                           ; next letter
	cmpi.b	#$f,d7                          ; 15 letters
	bne.s	menu_parse_letter_find
	bra.s	menu_parse_letters              ; not a test: skip it
menu_parse_letter_keep:
	move.b	d0,(a6)+                        ; keep it (last typed first)
	bra.s	menu_parse_letters              ; next character
menu_parse_done:
	bclr	#$5,mode_flags.w                ; no repeat count yet
	cmpa.l	#$269,a3                        ; any digits?
	bne.s	menu_parse_count_value          ; yes
	move.l	#$1,repeat_count.w              ; none: one pass
	bra.s	menu_set_flags
menu_parse_count_value:
	lea	number_digits.w,a0              ; digits
	clr.l	repeat_count.w
	bsr.w	decimal_to_number               ; digits to a number
	move.l	d2,repeat_count.w               ; repeat count
menu_set_flags:
	bset	#$5,mode_flags.w                ; repeat count given
	bset	#$4,mode_flags.w                ; more than one test
	cmpi.l	#$1,repeat_count.w              ; one pass?
	bne.s	menu_set_flags_single           ; no
	bclr	#$5,mode_flags.w                ; no repeat
menu_set_flags_single:
	cmpa.l	#$25a,a6                        ; only one letter?
	bgt.s	menu_set_sequence_flag          ; no
	bclr	#$4,mode_flags.w                ; single test
menu_set_sequence_flag:
	clr.b	unattended.w
	move.b	mode_flags.w,d0
	andi.b	#$38,d0                         ; sequence, several tests or a repeat?
	beq.w	menu_set_first_test             ; no
	move.b	#$ff,unattended.w               ; tests must not wait for keys
menu_set_first_test:
	suba.l	#$1,a6                          ; the first letter typed
	move.l	a6,first_test_ptr.w
menu_run_pass:
	move.l	first_test_ptr.w,test_ptr.w     ; start of a pass
menu_run_test:
	movea.l	test_ptr.w,a0                   ; current letter pointer
	move.b	(a0),d0                         ; the letter
	lea	menu_test_letters,a1            ; "ROMSTDILFPGYVQZ"
	clr.l	d2                              ; letter index
menu_run_test_find:
	cmp.b	0(a1,d2.w),d0                   ; this letter?
	beq.s	menu_run_test_found
	addq.w	#1,d2                           ; next letter
	cmpi.b	#$f,d2                          ; all 15 tried?
	beq.w	menu                            ; not found: menu
	bra.s	menu_run_test_find
menu_run_test_found:
	btst	#$6,mode_flags.w                ; first test of the pass?
	bne.s	menu_run_test_clear_status      ; no
	bsr.w	clear_screen                    ; yes: clear the screen
	move.w	#$2,scroll_top.w                ; status line row 2
	bsr.w	print_newline                   ; new line
	bsr.w	print_newline                   ; new line
	bra.s	menu_run_test_call
menu_run_test_clear_status:
	bsr.w	clear_status_line               ; clear the status line
menu_run_test_call:
	bset	#$6,mode_flags.w                ; a test has run
	lea	test_routines,a0                ; test entry table
	lsl.b	#2,d2                           ; table offset
	movea.l	0(a0,d2.w),a1                   ; the test
	jsr	(a1)                            ; run the test
	bsr.w	screen_is_red                   ; screen red (failed)?
	beq.s	menu_run_test_next              ; yes: stay red
	move.w	#$51,$ffff8240.w                ; palette 0, pass colour
menu_run_test_next:
	move.b	mode_flags.w,d0
	andi.b	#$30,d0                         ; several tests or a repeat?
	beq.s	menu_run_end                    ; no: wait for Space
	bsr.w	check_esc                       ; ESC pressed?
	beq.s	menu_run_test_pause             ; no, or RET after it: go on
	bne.w	menu                            ; other key: menu
menu_run_test_pause:
	move.w	#$12c,d1                        ; 301 delays, about 0.7 s
menu_run_test_pause_loop:
	bsr.w	delay                           ; wait
	dbra	d1,menu_run_test_pause_loop     ; loop
menu_run_test_advance:	; from: run_q_tests
	subi.l	#$1,test_ptr.w                  ; next letter
	move.l	test_ptr.w,d0
	cmp.l	#$259,d0                        ; letters left?
	bge.w	menu_run_test                   ; more
	bsr.w	print_cycle                     ; "Cycle: n", one more
	subi.l	#$1,repeat_count.w              ; one pass less
	tst.l	repeat_count.w                  ; passes left?
	beq.s	menu_run_end                    ; all done
	bsr.w	result_sound                    ; pass or fail sound
	bra.w	menu_run_pass                   ; next pass
menu_run_end:	; from: run_q_tests
	bclr	#$7,mode_flags.w                ; did the test wait already?
	bne.s	menu_run_end_menu               ; yes: menu
	bsr.w	result_sound                    ; pass or fail sound
menu_run_end_wait:
	bsr.w	get_key                         ; wait for Space
	cmpi.b	#$20,d0                         ; Space?
	bne.s	menu_run_end_wait               ; no: wait
menu_run_end_menu:
	bra.w	menu                            ; to the menu

;------------------------------------------------------------------------------
; run_q_tests: Q, all unattended tests: runs "ROMSTDILPFYV" in order, prints "Q Tests Completed", then
; repeats for the repeat count. run_z_tests: Z, internal unattended tests "ROTFLG", "Z Tests
; Completed". The result of each test shows as the background colour and a "Pass" line.
;------------------------------------------------------------------------------
run_q_tests:	; from: test_routines
	move.l	#q_test_letters,test_letters_ptr.w ; letters to run
	move.b	#$c,run_test_count.w            ; 12 tests
	move.l	#msg_q_tests_completed,run_done_message.w ; "Q Tests Completed"
	bra.s	run_sequence                    ; run them
run_z_tests:	; from: test_routines
	move.l	#z_test_letters,test_letters_ptr.w ; letters to run
	move.b	#$6,run_test_count.w            ; 6 tests
	move.l	#msg_z_tests_completed,run_done_message.w ; "Z Tests Completed"
run_sequence:
	move.b	#$ff,unattended.w               ; tests must not wait for keys
	bset	#$3,mode_flags.w                ; sequence running
	bsr.w	print_newline                   ; new line
	bsr.w	print_newline                   ; new line
	move.w	#$2,scroll_top.w                ; status line row 2
run_sequence_pass:
	clr.b	sequence_index.w                ; first test
run_sequence_next:
	clr.l	d0
	move.b	sequence_index.w,d0             ; index in the letters
	movea.l	test_letters_ptr.w,a0           ; letters to run
	move.b	0(a0,d0.w),d1                   ; the test letter
	lea	menu_test_letters,a1            ; "ROMSTDILFPGYVQZ"
	clr.l	d2                              ; letter index
run_sequence_find:
	cmp.b	0(a1,d2.w),d1                   ; this letter?
	beq.s	run_sequence_call               ; found
	addq.w	#1,d2                           ; next letter
	bra.s	run_sequence_find
run_sequence_call:
	lea	test_routines,a0                ; test entry table
	lsl.w	#2,d2                           ; table offset
	movea.l	0(a0,d2.w),a1                   ; the test
	jsr	(a1)                            ; run the test
	bsr.w	screen_is_red                   ; screen red (failed)?
	beq.s	run_sequence_check_esc          ; yes: stay red
	move.w	#$51,$ffff8240.w                ; palette 0, no: pass colour...
	lea	msg_pass,a5                     ; ..."Pass" at the top right
	bsr.w	show_result
run_sequence_check_esc:
	bsr.w	check_esc                       ; ESC pressed?
	bne.w	menu                            ; quit to the menu
	bsr.w	pause_clear_status              ; pause, clear the status line
	bclr	#$7,mode_flags.w                ; no wait flag from the test
	addi.b	#$1,sequence_index.w            ; next test
	move.b	run_test_count.w,d0             ; number of tests
	cmp.b	sequence_index.w,d0             ; all done?
	bne.s	run_sequence_next               ; more
	movea.l	run_done_message.w,a5           ; "Q/Z Tests Completed"
	bsr.w	show_status                     ; at the top left
	btst	#$4,mode_flags.w                ; more letters after Q or Z?
	bne.w	menu_run_test_advance           ; run them
	bsr.w	print_cycle                     ; "Cycle: n", one more
	subi.l	#$1,repeat_count.w              ; one pass less
	tst.l	repeat_count.w                  ; passes left?
	bne.w	run_sequence_pass               ; yes: again
	bsr.w	screen_is_red                   ; screen red?
	beq.s	run_sequence_done               ; yes: stay red
	move.w	#$51,$ffff8240.w                ; palette 0, no: pass colour...
	lea	msg_pass,a5                     ; ..."Pass" at the top right
	bsr.w	show_result
run_sequence_done:
	bra.w	menu_run_end                    ; wait for Space

;------------------------------------------------------------------------------
; pause_clear_status: waits 301 delays (about 0.7 s), then clear_status_line. Changes d0, d1, a0.
;------------------------------------------------------------------------------
pause_clear_status:	; from: run_q_tests
	move.w	#$12c,d1                        ; 301 delays
pause_clear_status_loop:
	bsr.w	delay                           ; wait
	dbra	d1,pause_clear_status_loop      ; loop
	bsr.w	clear_status_line
	rts

;------------------------------------------------------------------------------
; clear_status_line: blanks the top line (145 spaces from the home position) and puts the cursor back.
; Changes d0, d1, a0.
;------------------------------------------------------------------------------
clear_status_line:	; from: menu, pause_clear_status, detect_drive_types
	bsr.w	save_cursor                     ; keep the cursor
	bsr.w	cursor_home                     ; cursor home
	move.w	#$91,d1                         ; 145 spaces
	bsr.w	print_spaces
	bsr.w	restore_cursor                  ; cursor back
	rts

;------------------------------------------------------------------------------
; check_esc: if a key is waiting and it is ESC, asks "Stopped. Press RET to continue, other key to
; quit." Out: Z set to go on (no key, or RET), Z clear to quit. Other keys are dropped. ask_stopped
; asks at once. Changes d0, d1, a0-a3.
;------------------------------------------------------------------------------
check_esc:	; from: menu, run_q_tests, floppy_exerciser
	bsr.w	key_waiting                     ; key waiting?
	beq.s	check_esc_continue              ; no: go on
	bsr.w	get_key                         ; read it
	cmp.b	#$1b,d0                         ; ESC?
	bne.s	check_esc                       ; no: drop it, look again

ask_stopped:	; from: floppy_exerciser
	lea	msg_stopped_ret_continue,a5     ; "Stopped. Press RET to continue, other key to quit."
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; the answer
	move.b	d0,-(sp)                        ; keep the answer
	move.w	cursor_row.w,d1                 ; column 0 of the cursor row
	clr.w	d0                              ; column 0
	bsr.w	set_cursor                      ; cursor there
	bsr.w	clear_to_line_end               ; clear the question
	move.b	(sp)+,d0                        ; the answer
	cmpi.b	#$d,d0                          ; RET?
	beq.s	check_esc_continue              ; go on
	andi.b	#$1b,ccr                        ; Z clear: quit
	rts
check_esc_continue:	; from: check_esc
	ori.b	#$4,ccr                         ; Z set: go on
	rts

;------------------------------------------------------------------------------
; print_cycle: prints "Cycle: " and the BCD pass number $216 at column 66 of row 1, then adds 1 to
; it (BCD). Changes d0, d1, a0, a1.
;------------------------------------------------------------------------------
print_cycle:	; from: menu, run_q_tests, floppy_exerciser
	bsr.w	save_cursor                     ; keep the cursor
	moveq	#66,d0                          ; column 66
	moveq	#1,d1                           ; row 1
	bsr.w	set_cursor                      ; cursor there
	lea	msg_cycle,a5                    ; "Cycle: "
	bsr.w	print_string                    ; print it
	movea.l	test_cycle.w,a0                 ; BCD pass number
	bsr.w	print_hex_address               ; in hex = decimal
	bsr.w	print_newline                   ; new line
	move.l	#$1,scratch_long.w              ; BCD 1
	lea	first_test_ptr.w,a1             ; source end
	lea	scratch_long.w,a0               ; destination end
	moveq	#2,d0                           ; 3 bytes
print_cycle_add:
	abcd	-(a1),-(a0)                     ; pass number + 1, BCD
	dbra	d0,print_cycle_add              ; loop
	bsr.w	restore_cursor                  ; cursor back
	rts

;------------------------------------------------------------------------------
; screen_is_red: Out: Z set if the background is red ($500 in the 3-bit colour bits): a test failed.
; Changes d0.
;------------------------------------------------------------------------------
screen_is_red:	; from: menu_start, menu, run_q_tests, result_sound, floppy_quick_test, floppy_interchange
	move.w	$ffff8240.w,d0                  ; palette 0
	andi.w	#$777,d0                        ; 3-bit colour
	cmpi.w	#$500,d0                        ; red?
	rts

;------------------------------------------------------------------------------
; read_command_line: reads the menu command line into $239-$258 with echo and backspace. Keys that
; act at once (no RET): ? or Help help, E memory utility, B RS232 rate, X 50/60 Hz, J hard disk,
; H high resolution, A audio, C colour, K keyboard, $ credits, ! 8 MHz cache off, @ 16 MHz cache off,
; # 16 MHz cache on, % 8 MHz floppy clock, ^ 16 MHz floppy clock (high density). Typed on the
; keyboard, RET waits for the Return or Enter key to be released.
; Out: d0 = 0 for an empty line, a direct command or a full buffer, else non-zero with a4 the end
; of the line. Changes d0, d1, a0-a4.
;------------------------------------------------------------------------------
read_command_line:	; from: menu, floppy_alignment
	lea	line_buffer.w,a4                ; line buffer
	moveq	#63,d0                          ; clear 64 bytes (the line, letters and digits)
read_command_clear:
	clr.b	(a4)+                           ; clear a byte
	dbra	d0,read_command_clear           ; loop
	lea	line_buffer.w,a4                ; start of the line
	bsr.w	flush_input                     ; drop waiting keys
read_command_key:
	bsr.w	get_key                         ; next key (d0 ASCII, d1 scan code)
	cmpi.b	#$1b,d0                         ; ESC: kept in the line
	beq.w	read_command_store
	cmpi.b	#$62,d1                         ; Help key?
	beq.w	cmd_help                        ; help
	cmpi.b	#$3f,d0                         ; "?"
	beq.w	cmd_help                        ; help
	cmpi.b	#$45,d0                         ; "E"
	beq.w	cmd_examine_memory              ; memory utility
	cmpi.b	#$42,d0                         ; "B"
	beq.w	cmd_rs232_rate                  ; RS232 rate
	cmpi.b	#$58,d0                         ; "X"
	beq.w	cmd_toggle_50_60hz              ; 50/60 Hz
	cmpi.b	#$4a,d0                         ; "J"
	beq.w	cmd_hard_disk                   ; hard disk
	cmpi.b	#$48,d0                         ; "H"
	beq.w	cmd_high_res                    ; high resolution
	cmpi.b	#$41,d0                         ; "A"
	beq.w	cmd_audio                       ; audio
	cmpi.b	#$43,d0                         ; "C"
	beq.w	cmd_colour                      ; colour
	cmpi.b	#$4b,d0                         ; "K"
	beq.w	cmd_keyboard                    ; keyboard
	cmpi.b	#$24,d0                         ; "$"
	beq.w	cmd_credits                     ; credits
	cmpi.b	#$21,d0                         ; "!"
	beq.w	cmd_cpu_8mhz                    ; 8 MHz
	cmpi.b	#$40,d0                         ; "@"
	beq.w	cmd_cpu_16mhz                   ; 16 MHz
	cmpi.b	#$23,d0                         ; "#"
	beq.w	cmd_cpu_16mhz_cache             ; 16 MHz with cache
	cmpi.b	#$25,d0                         ; "%"
	beq.w	cmd_floppy_8mhz                 ; 8 MHz floppy clock
	cmpi.b	#$5e,d0                         ; "^"
	beq.w	cmd_floppy_16mhz                ; 16 MHz floppy clock
	cmpi.b	#$8,d0                          ; backspace?
	bne.w	read_command_not_backspace      ; no
	cmpa.l	#$239,a4                        ; line empty?
	beq.w	read_command_key                ; yes: ignore
	bsr.w	put_backspace                   ; rub out on screen
	clr.b	-(a4)                           ; and in the line
	bra.w	read_command_key
read_command_not_backspace:
	cmpi.b	#$d,d0                          ; RET?
	beq.w	read_command_wait_release       ; yes
read_command_store:
	move.b	d0,(a4)+                        ; into the line
	move.b	d0,d1
	bsr.w	put_char                        ; echo it
	cmpa.l	#$258,a4                        ; line full?
	ble.w	read_command_key                ; no: next key
	lea	msg_keyboard_buffer_full,a5     ; "Keyboard buffer full"
	bsr.w	print_string                    ; print it
read_command_none:
	moveq	#0,d0                           ; nothing to run
	rts
read_command_wait_release:
	cmpa.l	#$239,a4                        ; empty line?
	beq.s	read_command_none               ; yes: nothing to run
	tst.b	d1                              ; RET from RS232: done
	beq.s	read_command_done
	cmpi.b	#$9c,key_release.w              ; Return released?
	beq.s	read_command_done
	cmpi.b	#$f2,key_release.w              ; keypad Enter released?
	bne.s	read_command_wait_release       ; wait
read_command_done:
	rts                                     ; d0 = RET: run the line
cmd_examine_memory:
	bsr.w	memory_utility                  ; E: memory utility
	bra.w	read_command_direct_done
cmd_audio:
	bsr.w	clear_screen                    ; A: audio
	bsr.w	audio_test                      ; audio test
	bra.w	read_command_direct_done
cmd_high_res:
	bsr.w	clear_screen                    ; H: high resolution
	bsr.w	mono_monitor_test               ; high resolution test
	bra.w	read_command_direct_done
cmd_hard_disk:
	bsr.w	clear_screen                    ; J: hard disk
	bsr.w	hd_test                         ; hard disk test
	bra.w	read_command_direct_done
cmd_colour:
	bsr.w	clear_screen                    ; C: colour
	bsr.w	colour_test                     ; colour test
	bra.w	read_command_direct_done
cmd_keyboard:
	bsr.w	clear_screen                    ; K: keyboard
	bsr.w	keyboard_test                   ; keyboard test
	bra.w	read_command_direct_done
cmd_credits:
	bsr.w	clear_screen                    ; $: the date
	lea	msg_date,a5                     ; "MAY 24, 1991"
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; wait for a key
	cmpi.b	#$2a,d0                         ; "*" next?
	bne.s	cmd_credits_done                ; no
	lea	msg_author,a5                   ; " by TF"
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; any key
cmd_credits_done:
	bra.w	read_command_direct_done
cmd_toggle_50_60hz:
	btst	#$1,$ffff8260.w                 ; shift mode, X: not in high resolution
	bne.w	read_command_direct_done        ; yes: no change
	move.b	$ffff820a.w,d0                  ; sync mode
	eori.b	#$2,d0                          ; 50 <-> 60 Hz
	move.b	d0,$ffff820a.w                  ; sync mode
	bra.w	read_command_direct_done
cmd_help:
	bsr.w	clear_screen                    ; clear the screen
	lea	help_text,a5                    ; "RUNNING UNATTENDED TESTS ..." help page 1
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; any key
	lea	help_text_miscellaneous,a5      ; "MISCELANEOUS ..." help page 2
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; any key
read_command_direct_done:
	moveq	#0,d0                           ; direct command done: back to the menu
	rts
cmd_cpu_8mhz:
	bsr.w	clear_screen                    ; !
	lea	msg_clock_8_meg_cache_off,a5    ; "System clock set to  8 meg - cache off"
	bsr.w	print_string                    ; print it
	move.b	#$0,$ff8e21                     ; Mega STE cache and CPU speed, 8 MHz, cache off
	bsr.w	get_key                         ; any key
	bra.s	read_command_direct_done
cmd_cpu_16mhz:
	bsr.w	clear_screen                    ; @
	lea	msg_clock_16_meg_cache_off,a5   ; "System clock set to 16 meg - cache off"
	bsr.w	print_string                    ; print it
	move.b	#$2,$ff8e21                     ; Mega STE cache and CPU speed, 16 MHz, cache off
	bsr.w	get_key                         ; any key
	bra.s	read_command_direct_done
cmd_cpu_16mhz_cache:
	bsr.w	clear_screen                    ; #
	lea	msg_clock_16_meg_cache_on,a5    ; "System clock set to 16 meg - cache on"
	bsr.w	print_string                    ; print it
	move.b	#$3,$ff8e21                     ; Mega STE cache and CPU speed, 16 MHz, cache on
	bsr.w	get_key                         ; any key
	bra.s	read_command_direct_done
cmd_floppy_8mhz:
	bsr.w	clear_screen                    ; %
	lea	msg_floppy_clock_8_meg,a5       ; "8 meg floppy clock set"
	bsr.w	print_string                    ; print it
	move.w	#$0,$ffff860e                   ; floppy control: 8 MHz, double density
	bsr.w	get_key                         ; any key
	bra.s	read_command_direct_done
cmd_floppy_16mhz:
	bsr.w	clear_screen                    ; ^
	lea	msg_floppy_clock_16_meg_hd,a5   ; "16 meg floppy clock set - HIGH DENSITY"
	bsr.w	print_string                    ; print it
	move.w	#$3,$ffff860e                   ; floppy control: 16 MHz, high density
	bsr.w	get_key                         ; any key
	bra.w	read_command_direct_done
cmd_rs232_rate:
	bsr.w	clear_screen                    ; B: RS232 rate
	lea	msg_increase_decrease,a5        ; "Increase ..., Decrease ..."
	bsr.w	print_string                    ; print it
cmd_rs232_rate_show:
	moveq	#0,d0                           ; column 0
	moveq	#1,d1                           ; row 1
	bsr.w	set_cursor                      ; cursor there
	clr.l	d0
	move.w	rs232_rate.w,d0                 ; the rate setting
	bsr.w	print_rs232_rate                ; print its baud rate
cmd_rs232_rate_key:
	bsr.w	get_key                         ; wait for a key
	cmp.b	#$d,d0                          ; RET or Space: done
	beq.s	cmd_rs232_rate_done             ; RET
	cmp.b	#$20,d0                         ; Space?
	bne.s	cmd_rs232_rate_change           ; no: arrows?
cmd_rs232_rate_done:
	bra.w	read_command_direct_done
cmd_rs232_rate_change:
	move.w	rs232_rate.w,d0                 ; Timer D data
	cmp.b	#$48,d1                         ; up arrow?
	beq.s	cmd_rs232_rate_up
	cmp.b	#$50,d1                         ; down arrow?
	bne.s	cmd_rs232_rate_key              ; other key: ignore
	lsl.w	#1,d0                           ; down: double the divider
	cmp.w	#$40,d0                         ; 600 baud is the lowest
	bls.s	cmd_rs232_rate_set
	move.w	#$2,d0                          ; wrap to 19200
	bra.s	cmd_rs232_rate_set
cmd_rs232_rate_up:
	lsr.w	#1,d0                           ; up: halve the divider
	cmp.w	#$1,d0                          ; 19200 is the highest
	bhi.s	cmd_rs232_rate_set
	move.w	#$40,d0                         ; wrap to 600
cmd_rs232_rate_set:
	move.w	d0,rs232_rate.w                 ; new rate
	bsr.w	rs232_setup                     ; set the port
	bra.s	cmd_rs232_rate_show             ; show it

;------------------------------------------------------------------------------
; word_to_bcd: In d0.w a number. Out: d1 the same in BCD (4 bits a digit). Changes d0, d2, d3.
;------------------------------------------------------------------------------
word_to_bcd:	; from: menu, ticks_to_ms, print_sector_number, print_track_number, hd_test, hd_print_cycle, 1 more
	clr.l	d3                              ; digit position
	clr.l	d1                              ; result
word_to_bcd_loop:
	andi.l	#$ffff,d0
	divu.w	#$a,d0                          ; divide by 10
	move.l	d0,d2
	swap	d2                              ; remainder: the next digit
	bsr.w	word_to_bcd_digit               ; add it
	cmp.w	#$a,d0                          ; more digits?
	bge.s	word_to_bcd_loop                ; 10 or more: next digit
	move.w	d0,d2                           ; the top digit
	bsr.w	word_to_bcd_digit
	rts

;------------------------------------------------------------------------------
; word_to_bcd_digit: ors digit d2 into d1 at bit d3, d3 += 4.
;------------------------------------------------------------------------------
word_to_bcd_digit:	; from: word_to_bcd
	andi.l	#$ff,d2
	lsl.w	d3,d2                           ; to its position
	or.l	d2,d1
	add.w	#$4,d3                          ; next position
	rts

;------------------------------------------------------------------------------
; decimal_to_number: In a0 the start, a3 the end of decimal digits stored lowest digit first.
; Out: d2 the number. Changes d0, d1, a0.
;------------------------------------------------------------------------------
decimal_to_number:	; from: menu, floppy_alignment
	clr.l	d2
	clr.l	d0
	cmpa.l	a0,a3                           ; no digits?
	beq.s	decimal_to_number_done
	moveq	#1,d1                           ; units
decimal_to_number_loop:
	move.b	(a0)+,d0                        ; digit
	andi.l	#$f,d0                          ; digit value
	mulu.w	d1,d0                           ; times its place
	add.l	d0,d2                           ; add it
	mulu.w	#$a,d1                          ; next place
	cmpa.l	a0,a3                           ; end?
	bhi.s	decimal_to_number_loop          ; more
decimal_to_number_done:
	rts

;------------------------------------------------------------------------------
; keyboard_acia_regs: Out: a0 the keyboard buffer record $45C, a1 the keyboard ACIA.
;------------------------------------------------------------------------------
keyboard_acia_regs:	; from: keyboard_setup, ikbd_send, key_waiting, acia_interrupt
	movea.l	#$45c,a0                        ; keyboard buffer record
	movea.l	#$fffffc00,a1                   ; keyboard ACIA
	rts

;------------------------------------------------------------------------------
; ikbd_send: sends d1 to the IKBD. Waits up to 65480 polls for the ACIA to be ready. Out: Z set if
; sent, Z clear on a timeout. Keeps all registers.
;------------------------------------------------------------------------------
ikbd_send:	; from: menu_start, menu, reset_keyboard_and_check, printer_joystick_test, read_joysticks
	movem.l	d7/a0-a1,-(sp)                  ; save registers
	bsr.s	keyboard_acia_regs              ; a1 = keyboard ACIA
	moveq	#-56,d7                         ; 65480 tries
ikbd_send_wait:
	btst	#$1,0(a1)                       ; transmit register empty?
	bne.s	ikbd_send_byte                  ; yes
	subq.w	#1,d7
	beq.s	ikbd_send_timeout               ; timeout
	bra.s	ikbd_send_wait
ikbd_send_byte:
	move.b	d1,2(a1)                        ; send it
	ori.b	#$4,ccr                         ; Z set: sent
ikbd_send_done:
	movem.l	(sp)+,d7/a0-a1                  ; restore registers
	rts
ikbd_send_timeout:
	andi.b	#$fb,ccr                        ; Z clear: timeout
	bra.s	ikbd_send_done

;------------------------------------------------------------------------------
; flush_input: empties the keyboard buffer and drops a waiting RS232 byte. Keeps all registers.
;------------------------------------------------------------------------------
flush_input:	; from: read_command_line, read_line, rtc_test
	move.w	d0,-(sp)
	clr.w	kbd_iorec_head.w                ; head 0
	clr.w	kbd_iorec_tail.w                ; tail 0
	move.b	$fffffa2f.w,d0                  ; MFP UDR, drop the RS232 byte
	move.w	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; key_waiting: Out: d0 = -1 a key in the keyboard buffer, $7F a byte from the RS232 terminal (only
; when the terminal is on), 0 none. rs232_byte_waiting looks at the RS232 port only. Changes a0-a3.
;------------------------------------------------------------------------------
key_waiting:	; from: check_esc, get_key, memory_utility, ram_test, keyboard_test, reset_keyboard_and_check, 7 more
	moveq	#0,d0                           ; nothing yet
	bsr.s	keyboard_acia_regs              ; keyboard buffer record
	lea	6(a0),a2                        ; head
	lea	8(a0),a3                        ; tail
	cmpm.w	(a3)+,(a2)+                     ; buffer empty?
	beq.s	key_waiting_rs232               ; yes: try RS232
	moveq	#-1,d0                          ; keyboard key
	rts
key_waiting_rs232:
	btst	#$1,mode_flags.w                ; RS232 terminal off?
	bne.s	key_waiting_none                ; yes: none

rs232_byte_waiting:	; from: menu, memory_utility
	tst.b	$fffffa2b.w                     ; MFP RSR, byte received?
	bpl.s	key_waiting_none                ; no
	moveq	#127,d0                         ; RS232 byte
	rts
key_waiting_none:	; from: key_waiting
	moveq	#0,d0                           ; nothing
	rts

;------------------------------------------------------------------------------
; get_key: waits for a key from the keyboard or the RS232 terminal. Out: d0 the ASCII code, a-z in
; upper case; d1 the scan code (0 for RS232). Keeps a0-a3.
;------------------------------------------------------------------------------
get_key:	; from: menu, check_esc, ask_stopped, read_command_line, memory_utility, read_line, 18 more
	movem.l	a0-a3,-(sp)                     ; save registers
get_key_wait:
	bsr.s	key_waiting
	tst.w	d0
	beq.s	get_key_wait                    ; wait
	bmi.s	get_key_keyboard                ; keyboard
	btst	#$1,mode_flags.w                ; RS232 terminal off?
	bne.s	get_key_wait                    ; yes: ignore it
	move.b	$fffffa2f.w,d0                  ; MFP UDR, the RS232 byte
	clr.b	d1                              ; no scan code
	bra.s	get_key_upper
get_key_keyboard:
	movea.l	#$45c,a0                        ; keyboard buffer record
	move.w	sr,-(sp)                        ; keep the interrupt level
	ori.w	#$700,sr                        ; no interrupts
	move.w	6(a0),d1                        ; head
	cmp.w	8(a0),d1                        ; = tail: empty
	beq.s	get_key_scan                    ; nothing
	addq.w	#2,d1                           ; next word
	cmp.w	4(a0),d1                        ; past the end?
	bcs.s	get_key_take
	moveq	#0,d1                           ; wrap to 0
get_key_take:
	movea.l	0(a0),a1                        ; buffer
	move.w	0(a1,d1.w),d0                   ; scan code and ASCII
	move.w	d1,6(a0)                        ; new head
get_key_scan:
	move.w	(sp)+,sr                        ; interrupt level back
	move.w	d0,d1
	and.w	#$7f,d0                         ; d0 ASCII
	lsr.w	#8,d1                           ; d1 scan code
get_key_upper:
	cmpi.b	#$61,d0                         ; lower case?
	blt.s	get_key_done
	cmpi.b	#$7a,d0
	bgt.s	get_key_done
	andi.b	#$df,d0                         ; to upper case
get_key_done:
	movem.l	(sp)+,a0-a3                     ; restore registers
	rts

;------------------------------------------------------------------------------
; bus_error_handler: the normal bus error handler. Red screen, RS232 set up again, then the text,
; " Access Address: " and " Program Counter: " from the 68000 group 0 frame. The first fault at a
; PC is reported and execution carries on with rte after the faulting access (in the memory utility
; it goes back to the prompt); a second fault at the same PC hangs. address_error_handler: the same
; for address errors. d7 is set to $FFFF.
;------------------------------------------------------------------------------
bus_error_handler:	; from: check_vme_ram, vme_interrupt_test, exception_vectors
	movea.l	#msg_bus_error,a5               ; "EB Bus Error "
exception_report:
	move.w	#$500,$ffff8240.w               ; palette 0, red
	bsr.w	rs232_setup                     ; RS232 at the set rate
	move.w	#$ffff,d7                       ; fault flag for the caller
	bsr.w	print_string                    ; the error text
	lea	msg_access_address,a5           ; " Access Address: "
	bsr.w	print_string                    ; print it
	movea.l	2(sp),a0                        ; access address from the frame
	bsr.w	print_hex_address               ; print it
	lea	msg_program_counter,a5          ; " Program Counter: "
	bsr.w	print_string                    ; print it
	movea.l	$a(sp),a0                       ; PC from the frame
	move.l	a0,d0
	cmp.l	last_fault_pc.w,d0              ; same PC as last time?
	beq.s	exception_report_repeat         ; then hang
	move.l	a0,last_fault_pc.w              ; keep it
	bsr.w	print_hex_address               ; print the PC
	bsr.w	print_newline                   ; new line
	tst.b	memory_utility_active.w         ; memory utility running?
	beq.s	exception_report_return         ; no
	move.l	#memory_utility_prompt,$a(sp)   ; yes: back to its prompt
exception_report_return:
	adda.w	#$8,sp                          ; leave SR and PC
	rte                                     ; carry on
exception_report_repeat:
	bsr.w	print_hex_address               ; print the PC
	bra.s	exception_halt_loop             ; hang
address_error_handler:	; from: exception_vectors
	movea.l	#msg_address_error,a5           ; "EA Address Error "
	bra.s	exception_report
illegal_handler:	; from: exception_vectors
	movea.l	#msg_bad_instruction_fetch,a5   ; "E9 Bad instruction fetch"
	bra.s	exception_halt

;------------------------------------------------------------------------------
; exception_error_handler: zero divide, CHK, TRAPV, privilege and trace: "E8 Exception error", hang.
; illegal_handler, line_a_handler, line_f_handler: "E9 Bad instruction fetch", hang.
;------------------------------------------------------------------------------
exception_error_handler:	; from: exception_vectors
	movea.l	#msg_exception_error,a5         ; "E8 Exception error"
	bra.s	exception_halt
line_a_handler:	; from: exception_vectors
	movea.l	#msg_bad_instruction_fetch,a5   ; "E9 Bad instruction fetch"
	bra.s	exception_halt
line_f_handler:	; from: exception_vectors
	movea.l	#msg_bad_instruction_fetch,a5   ; "E9 Bad instruction fetch"
exception_halt:	; from: bus_error_handler
	move.w	#$500,$ffff8240.w               ; palette 0, red
	bsr.w	print_newline                   ; new line
	bsr.w	print_string                    ; print the text
exception_halt_loop:	; from: bus_error_handler
	bra.s	exception_halt_loop             ; hang

;------------------------------------------------------------------------------
; spurious_handler: "E7 Spurious Interrupt", red, carry on.
;------------------------------------------------------------------------------
spurious_handler:	; from: interrupt_vectors
	move.w	#$500,$ffff8240.w               ; palette 0, red
	movea.l	#msg_spurious_interrupt,a5      ; "E7 Spurious Interrupt"
	bsr.w	print_string                    ; print it
	rte                                     ; carry on

;------------------------------------------------------------------------------
; autovector_handler: levels 1, 3, 5, 6 and 7: "E6 Autovector error", red, carry on.
;------------------------------------------------------------------------------
autovector_handler:	; from: interrupt_vectors
	move.w	#$500,$ffff8240.w               ; palette 0, red
	movea.l	#msg_autovector_error,a5        ; "E6 Autovector error"
	bsr.w	print_string                    ; print it
	rte                                     ; carry on

;------------------------------------------------------------------------------
; vbl_handler: clears the VBL flag $294.
;------------------------------------------------------------------------------
vbl_handler:                                    ; from: test_ram_range, colour_test, floppy_menu_jump_table,
                                                ;   floppy_quick_test, detect_drive_types, floppy_motor_vbl, 2 more
	clr.b	vbl_flag.w                      ; VBL seen
	rte

;------------------------------------------------------------------------------
; hbl_handler: clears the interrupt flags word $208.
;------------------------------------------------------------------------------
hbl_handler:	; from: interrupt_vectors
	clr.w	interrupt_events.w
	rte

;------------------------------------------------------------------------------
; monitor_change_handler: MFP GPIP7 (monitor plugged or changed): returns to cold_start, so the whole
; cartridge starts again with the resolution for the new monitor.
;------------------------------------------------------------------------------
monitor_change_handler:	; from: mono_monitor_test, mfp_vectors
	bclr	#$7,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	move.w	(sp)+,d1                        ; SR
	move.l	(sp)+,d0                        ; drop the PC
	move.l	#cold_start,-(sp)               ; return to cold_start
	move.w	d1,-(sp)                        ; SR back
	rte                                     ; to cold_start

;------------------------------------------------------------------------------
; high_res_switch_handler: MFP GPIP7 handler of the H test: waits for a VBL, then high resolution
; and a blue background.
;------------------------------------------------------------------------------
high_res_switch_handler:	; from: mono_monitor_test
	move.w	d0,-(sp)
	move.w	sr,d0                           ; keep the interrupt level
	move.w	#$2200,sr                       ; let the VBL in
	move.b	#$1,vbl_flag.w                  ; the VBL handler clears it
high_res_switch_wait_vbl:
	tst.b	vbl_flag.w                      ; wait for the VBL
	bne.s	high_res_switch_wait_vbl
	move.w	d0,sr                           ; interrupt level back
	move.b	#$2,$ffff8260.w                 ; shift mode, high resolution
	move.w	#$3,$ffff8240.w                 ; palette 0, background blue
	bclr	#$7,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	move.w	(sp)+,d0
	rte

;------------------------------------------------------------------------------
; ring_indicator_handler: MFP GPIP6 (RS232 RI): clears bit 6 of $208.
;------------------------------------------------------------------------------
ring_indicator_handler:	; from: mfp_vectors
	bclr	#$6,interrupt_events.w          ; RI seen
	bclr	#$6,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte

;------------------------------------------------------------------------------
; rs232_receive_handler: MFP receive buffer full: keeps the byte in $288 and ors the overrun, parity
; and frame error bits into $28A.
;------------------------------------------------------------------------------
rs232_receive_handler:	; from: mfp_vectors
	move.l	d0,-(sp)
	move.b	$fffffa2b.w,d0                  ; MFP RSR
	andi.b	#$70,d0                         ; error bits
	or.b	d0,rs232_rx_status.w
	move.b	$fffffa2f.w,rs232_rx_byte.w     ; MFP UDR, the byte
	bclr	#$4,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	move.l	(sp)+,d0
	rte

;------------------------------------------------------------------------------
; rs232_transmit_handler: MFP transmit buffer empty: keeps TSR in $28B and sends the next byte of the
; count in $289 until it reaches $FF.
;------------------------------------------------------------------------------
rs232_transmit_handler:	; from: mfp_vectors
	move.b	$fffffa2d.w,rs232_tx_status.w   ; MFP TSR
	cmpi.b	#$ff,rs232_tx_byte.w            ; last byte sent?
	beq.s	rs232_transmit_done             ; yes: stop
	addi.b	#$1,rs232_tx_byte.w             ; next value
	move.b	rs232_tx_byte.w,$fffffa2f.w     ; MFP UDR, send it
rs232_transmit_done:
	bclr	#$2,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte

;------------------------------------------------------------------------------
; rs232_receive_error_handler: MFP receive error: keeps RSR in $28A.
;------------------------------------------------------------------------------
rs232_receive_error_handler:	; from: mfp_vectors
	move.b	$fffffa2b.w,rs232_rx_status.w   ; MFP RSR
	bclr	#$3,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte

;------------------------------------------------------------------------------
; rs232_transmit_error_handler: MFP transmit error: keeps TSR in $28B.
;------------------------------------------------------------------------------
rs232_transmit_error_handler:	; from: mfp_vectors
	move.b	$fffffa2d.w,rs232_tx_status.w   ; MFP TSR
	bclr	#$1,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte

;------------------------------------------------------------------------------
; timer_b_count_handler: Timer B handler of the T test: counts $208 down and turns Timer B off when
; it reaches 0.
;------------------------------------------------------------------------------
timer_b_count_handler:	; from: timing_test
	tst.b	interrupt_events.w              ; count left?
	beq.s	timer_b_count_done              ; none: Timer B off
	subi.b	#$1,interrupt_events.w          ; count down
	beq.s	timer_b_count_done              ; reached 0
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte
timer_b_count_done:
	bclr	#$0,$fffffa07.w                 ; MFP IERA, Timer B off
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte

;------------------------------------------------------------------------------
; colour_bands_handler: a Timer B handler that sets all 16 colours to the next entry of
; colour_bars_st on each of 64 lines (ramps of red, green, blue, cyan, yellow, magenta, grey).
; Nothing installs it: its address is not in the cartridge.
;------------------------------------------------------------------------------
colour_bands_handler:
	movem.l	d0-d1/a0,-(sp)                  ; save registers
	cmpi.b	#$3f,vbl_flag.w                 ; 64 lines done?
	bgt.s	colour_bands_done               ; yes: nothing
	cmpi.b	#$0,vbl_flag.w                  ; first line?
	bne.s	colour_bands_line               ; no
	clr.b	colour_bar_index.w              ; start of the table
colour_bands_line:
	moveq	#33,d0                          ; wait into the line
colour_bands_delay:
	dbra	d0,colour_bands_delay           ; loop
	movea.l	#colour_bars_st,a0
	moveq	#0,d0
	move.b	colour_bar_index.w,d0           ; table offset
	move.w	0(a0,d0.w),d1                   ; this line's colour
	moveq	#15,d0                          ; 16 colours
	movea.l	#$ffff8240,a0
colour_bands_set:
	move.w	d1,(a0)+                        ; set a colour
	dbra	d0,colour_bands_set             ; loop
	addq.b	#2,colour_bar_index.w           ; next entry
colour_bands_done:
	movea.l	#$fffffa01,a0                   ; MFP
	bclr	#$0,$e(a0)                      ; end of interrupt (ISRA bit 0)
	addq.b	#1,vbl_flag.w                   ; line count
	movem.l	(sp)+,d0-d1/a0                  ; restore registers
	rte

;------------------------------------------------------------------------------
; colour_bars_st: one colour a line for an ST colour bar screen, read by the Timer B handler
; at $11f6, which nothing installs (the colour test uses colour_bars_ste_rgb). The handler sets
; all 16 palette registers to the word at offset ($296) and adds 2 each line, for 64 lines.
; Seven ramps - red, green, blue, cyan, yellow, magenta and white - each a
; black line and then the 8 ST levels 0 to 7; one black word at the end.
;------------------------------------------------------------------------------
colour_bars_st:	; from: colour_bands_handler
	dc.w	$0000,$0000,$0100,$0200,$0300,$0400,$0500,$0600
	dc.w	$0700,$0000,$0000,$0010,$0020,$0030,$0040,$0050
	dc.w	$0060,$0070,$0000,$0000,$0001,$0002,$0003,$0004
	dc.w	$0005,$0006,$0007,$0000,$0000,$0011,$0022,$0033
	dc.w	$0044,$0055,$0066,$0077,$0000,$0000,$0110,$0220
	dc.w	$0330,$0440,$0550,$0660,$0770,$0000,$0000,$0101
	dc.w	$0202,$0303,$0404,$0505,$0606,$0707,$0000,$0000
	dc.w	$0111,$0222,$0333,$0444,$0555,$0666,$0777,$0000

;------------------------------------------------------------------------------
; fdc_interrupt: MFP GPIP5 (FDC/ACSI) interrupt handler, installed at $11c from the MFP vector
; table at start-up.
; The bit number $80 in the second bclr is taken modulo 8 on a memory byte, so it clears ISRB
; bit 0 (GPIP0), not bit 7 (GPIP5).
;------------------------------------------------------------------------------
fdc_interrupt:	; from: mfp_vectors
	bclr	#$0,interrupt_events.w          ; clear event bit 0
	bclr	#$80,$fffffa11.w                ; MFP ISRB, clear ISRB bit 0 (meant: bit 7)
	rte                                     ; rte

;------------------------------------------------------------------------------
; acia_interrupt: MFP GPIP4 (keyboard and MIDI ACIAs) interrupt handler, installed at $118 by
; keyboard_setup and by the MFP vector table. Services the MIDI ACIA (buffer record $618, hook at $48e) and
; the keyboard ACIA (buffer record $45c, hook at $48a), then clears ISRB bit 6 and goes round
; again while GPIP4 is still low (another byte waiting).
;------------------------------------------------------------------------------
acia_interrupt:	; from: keyboard_setup, mfp_vectors
	movem.l	d0-d7/a0-a6,-(sp)               ; save all
acia_interrupt_next:
	bsr.w	midi_registers                  ; a0 = MIDI buffer record $618, a1 = MIDI ACIA
	movea.l	midi_byte_hook.w,a3             ; the MIDI hook
	bsr.w	acia_service                    ; service the MIDI ACIA
	bsr.w	keyboard_acia_regs              ; a0 = keyboard buffer record $45c, a1 = keyboard ACIA
	movea.l	kbd_byte_hook.w,a3              ; the keyboard hook
	bsr.w	acia_service                    ; service the keyboard ACIA
	movea.l	#$fffffa01,a1                   ; the MFP
	bclr	#$6,$10(a1)                     ; clear ISRB bit 6 (ACIA)
	btst	#$4,0(a1)                       ; GPIP4 still low?
	bne.s	acia_interrupt_done             ; no: done
	bra.s	acia_interrupt_next             ; yes: service both again
acia_interrupt_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; restore
	rte                                     ; rte

;------------------------------------------------------------------------------
; acia_service: services one ACIA. In: a0 = its buffer record, a1 = the ACIA. It
; reads the status, stores a received byte through $1344 and, on a receive error, resets the
; ACIA and sets it up again ($96: divide by 64, 8 bits, 1 stop, receive interrupt on).
;------------------------------------------------------------------------------
acia_service:	; from: acia_interrupt
	bsr.w	midi_read_status                ; d7 = ACIA status, also kept at $1c(a0)
	btst	#$7,d7                          ; is this ACIA interrupting?
	beq.s	acia_service_done               ; no: return
	btst	#$0,d7                          ; receive register full?
	beq.s	acia_service_reset              ; no: reset the ACIA
	movem.l	a0-a3,-(sp)                     ; movem.l a0-a3,-(sp)
	bsr.w	ikbd_receive_byte               ; store the received byte
	movem.l	(sp)+,a0-a3                     ; movem.l (sp)+,a0-a3
	andi.b	#$7c,d7                         ; error and line status bits
	tst.b	d7                              ; tst.b d7
	beq.s	acia_service_done               ; none: return
acia_service_reset:
	move.b	#$3,0(a1)                       ; master reset
	move.b	#$96,0(a1)                      ; divide by 64, 8 bits, 1 stop, receive interrupt on

;------------------------------------------------------------------------------
; acia_service_done: the rts that ends acia_service; its address is also the keyboard hook in $48A.
;------------------------------------------------------------------------------
acia_service_done:	; from: keyboard_setup, acia_service
	rts

;------------------------------------------------------------------------------
; ikbd_receive_byte: In a0 the buffer record, a1 the ACIA. Reads the received byte. MIDI: the byte goes
; into the MIDI buffer. Keyboard: bytes of a packet ($FC clock: 6 bytes to $27E-$283; $FD joystick:
; 2 bytes to $236-$237; other $F4-$FF headers: 2 bytes) are kept, last byte first; with $492 bit 3
; set, $F0-$F3 (the reset reply) goes into the buffer as $Fx00. Shift presses and releases set
; $494; other releases go to $28C and the release ring; presses go into the keyboard buffer as scan
; code and ASCII from the key maps. Changes d0, d1, a0, a2.
;------------------------------------------------------------------------------
ikbd_receive_byte:	; from: acia_service
	moveq	#0,d0
	move.b	2(a1),d0                        ; the byte
	cmpa.l	#$45c,a0                        ; keyboard?
	bne.w	midi_buffer_put                 ; no: MIDI
	tst.b	ikbd_packet_count.w             ; inside a packet?
	beq.w	ikbd_header                     ; no: a header or a key
	subi.b	#$1,ikbd_packet_count.w         ; one byte less
	bne.w	ikbd_packet_byte                ; more to come
	clr.b	ikbd_packet_type.w              ; packet complete
ikbd_packet_byte:
	btst	#$1,ikbd_packet_type.w          ; clock packet?
	bne.w	ikbd_packet_clock               ; yes
	lea	ikbd_data_first.w,a0            ; joystick/mouse bytes
	bra.s	ikbd_packet_store
ikbd_packet_clock:
	lea	ikbd_clock_packet.w,a0          ; clock bytes
ikbd_packet_store:
	moveq	#0,d1
	move.b	ikbd_packet_count.w,d1          ; bytes left = place
	move.b	d0,0(a0,d1.w)                   ; keep it
	rts
ikbd_header:
	move.b	d0,d1
	andi.w	#$f0,d1                         ; top four bits
	cmpi.b	#$f0,d1                         ; $F0-$FF?
	bne.s	ikbd_key                        ; no: a key
	cmpi.b	#$f3,d0                         ; $F0-$F3?
	bgt.s	ikbd_header_not_reply           ; no: a header
	btst	#$3,ikbd_packet_type.w          ; waiting for the reset reply?
	beq.w	ikbd_key                        ; no: a key
	clr.b	ikbd_packet_type.w              ; reply taken
	lsl.w	#8,d0                           ; $Fx00
	bra.w	keyboard_buffer_put             ; into the keyboard buffer
ikbd_header_not_reply:
	cmpi.b	#$fc,d0                         ; $FC clock?
	bne.s	ikbd_header_not_clock           ; no
	bset	#$1,ikbd_packet_type.w          ; clock packet
	move.b	#$6,ikbd_packet_count.w         ; 6 bytes to come
	rts
ikbd_header_not_clock:
	cmpi.b	#$fd,d0                         ; $FD joysticks?
	bne.s	ikbd_header_other               ; no
	bset	#$0,ikbd_packet_type.w          ; joystick packet
	move.b	#$2,ikbd_packet_count.w         ; 2 bytes to come
	rts
ikbd_header_other:
	move.b	#$2,ikbd_packet_count.w         ; 2 bytes to come
	move.b	d0,ikbd_packet_header.w         ; keep the header
	rts
ikbd_key:
	moveq	#0,d1
	move.b	d0,d1                           ; d1 scan code
	cmpi.b	#$2a,d0                         ; left shift pressed?
	bne.s	ikbd_key_not_lshift             ; no
	bset	#$7,shift_held.w                ; shifted
ikbd_key_make:
	andi.w	#$ff,d0
	bra.s	ikbd_key_translate
ikbd_key_not_lshift:
	cmpi.b	#$36,d0                         ; right shift pressed?
	bne.s	ikbd_key_not_rshift             ; no
	bset	#$7,shift_held.w                ; shifted
	bra.s	ikbd_key_make
ikbd_key_not_rshift:
	cmpi.b	#$aa,d0                         ; left shift released?
	bne.s	ikbd_key_not_lshift_up          ; no
	bclr	#$7,shift_held.w                ; unshifted
ikbd_key_not_lshift_up:
	cmpi.b	#$b6,d0                         ; right shift released?
	bne.s	ikbd_key_release_check          ; no
	bclr	#$7,shift_held.w                ; unshifted
ikbd_key_release_check:
	btst	#$7,d0                          ; release?
	beq.s	ikbd_key_translate              ; no: a press
	move.b	d0,key_release.w                ; last release code
	movea.l	release_ring_write.w,a0         ; release ring
	move.b	d0,(a0)+                        ; into the ring
	cmpa.l	#$48a,a0                        ; end of the ring?
	bne.s	ikbd_key_release_next           ; no
	movea.l	#$482,a0                        ; wrap
ikbd_key_release_next:
	move.l	a0,release_ring_write.w         ; new write pointer
	rts
ikbd_key_translate:
	move.l	a0,-(sp)
	movea.l	#keyboard_ascii_unshifted,a0    ; key maps
	add.b	shift_held.w,d0                 ; +$80 when shifted
	adda.w	d0,a0
	move.b	(a0),d0                         ; ASCII
	asl.w	#8,d1                           ; scan code high
	add.w	d1,d0                           ; scan code and ASCII
	movea.l	(sp)+,a0
keyboard_buffer_put:
	move.w	8(a0),d1                        ; tail
	addq.w	#2,d1                           ; next word
	cmp.w	4(a0),d1                        ; past the end?
	bcs.s	keyboard_buffer_put_check       ; no
	moveq	#0,d1                           ; wrap to 0
keyboard_buffer_put_check:
	cmp.w	6(a0),d1                        ; = head: full
	beq.s	keyboard_buffer_put_done        ; drop it
	movea.l	0(a0),a2                        ; buffer
	move.w	d0,0(a2,d1.w)                   ; store it
	move.w	d1,8(a0)                        ; new tail
keyboard_buffer_put_done:
	rts
midi_buffer_put:
	move.w	8(a0),d1                        ; tail
	addq.w	#1,d1                           ; next byte
	cmp.w	4(a0),d1                        ; past the end?
	bcs.s	midi_buffer_put_check           ; no
	moveq	#0,d1                           ; wrap to 0
midi_buffer_put_check:
	cmp.w	6(a0),d1                        ; = head: full
	beq.s	midi_buffer_put_done            ; drop it
	movea.l	0(a0),a2                        ; buffer
	move.b	d0,0(a2,d1.w)                   ; store it
	move.w	d1,8(a0)                        ; new tail
midi_buffer_put_done:
	rts

;------------------------------------------------------------------------------
; keyboard_ascii_unshifted: scan code to ASCII, 128 bytes, used by the keyboard handler at
; $1444 (offset = scan code + ($494)). $494 bit 7 is set while a shift key is held, which
; selects keyboard_ascii_shifted 128 bytes on. 0 = no character.
;------------------------------------------------------------------------------
keyboard_ascii_unshifted:	; from: ikbd_receive_byte
	dc.b	$00
	dc.b	27,'1234567890-='
	dc.b	$08
	dc.b	9,'QWERTYUIOP[]',13,0
	dc.b	'ASDFGHJKL;',$27,'`',0
	dc.b	'\ZXCVBNM,./',0
	dc.b	$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$2d,$00,$00,$00,$2b,$00,$00,$00,$00,$7f,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	'()/*7894561230.',13,0
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; keyboard_ascii_shifted: scan code to ASCII with shift held.
;------------------------------------------------------------------------------
keyboard_ascii_shifted:
	dc.b	$00
	dc.b	27,'!@#$%^&*()_+'
	dc.b	$08
	dc.b	9,'QWERTYUIOP{}',13,0
	dc.b	'ASDFGHJKL:"~',0
	dc.b	'|ZXCVBNM<>?',0
	dc.b	$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$37,$38,$00,$2d,$34,$00,$36,$2b,$00,$32,$00,$30,$7f,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	'()/*7894561230.',13,0
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; keyboard_ascii_caps: a third table (capitals, number pad as numbers); nothing selects it,
; since ($494) is only ever 0 or $80.
;------------------------------------------------------------------------------
keyboard_ascii_caps:
	dc.b	$00
	dc.b	27,'1234567890-='
	dc.b	$08
	dc.b	9,'QWERTYUIOP[]',13,0
	dc.b	'ASDFGHJKL;',$27,'`',0
	dc.b	'\ZXCVBNM,./',0
	dc.b	$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$38,$00,$2d,$34,$00,$36,$2b,$00,$32,$00,$00,$7f,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	'()/*7894561230.',13,0
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; timer_a_count_handler: a Timer A handler that counts $20A down and clears $286. Nothing installs it:
; its address is not in the cartridge.
;------------------------------------------------------------------------------
timer_a_count_handler:
	tst.b	timer_a_count.w                 ; count left?
	beq.s	timer_a_count_done              ; no
	subi.b	#$1,timer_a_count.w             ; count down
timer_a_count_done:
	clr.b	timer_irq_flags.w               ; interrupt seen
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte

;------------------------------------------------------------------------------
; timer_a_handler, timer_b_handler, timer_c_handler, timer_d_handler: the MFP timer interrupts. Each
; clears bit 1 of $286 if its in-service bit is set, clears that bit, and clears bit 0 of $286.
; timer_c_handler goes on into the Timer D check.
;------------------------------------------------------------------------------
timer_a_handler:	; from: timing_test, mfp_vectors
	btst	#$5,$fffffa0f.w                 ; MFP ISRA, Timer A in service?
	beq.s	timer_handler_done              ; no
	bclr	#$1,timer_irq_flags.w           ; interrupt seen
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	bra.s	timer_handler_done
timer_b_handler:	; from: timing_test, mfp_vectors
	btst	#$0,$fffffa0f.w                 ; MFP ISRA, Timer B in service?
	beq.s	timer_handler_done              ; no
	bclr	#$1,timer_irq_flags.w           ; interrupt seen
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	bra.s	timer_handler_done
timer_c_handler:	; from: timing_test, mfp_vectors
	btst	#$5,$fffffa11.w                 ; MFP ISRB, Timer C in service?
	beq.s	timer_handler_done              ; no
	bclr	#$1,timer_irq_flags.w           ; interrupt seen
	bclr	#$5,$fffffa11.w                 ; MFP ISRB, end of interrupt
timer_d_handler:	; from: timing_test, mfp_vectors
	btst	#$4,$fffffa11.w                 ; MFP ISRB, Timer D in service?
	beq.s	timer_handler_done              ; no
	bclr	#$1,timer_irq_flags.w           ; interrupt seen
	bclr	#$4,$fffffa11.w                 ; MFP ISRB, end of interrupt
timer_handler_done:
	bclr	#$0,timer_irq_flags.w           ; interrupt seen
	rte

;------------------------------------------------------------------------------
; blitter_done_handler: MFP GPIP3 (BLiTTER done): end of interrupt only.
;------------------------------------------------------------------------------
blitter_done_handler:	; from: mfp_vectors
	bclr	#$3,$fffffa11.w                 ; MFP ISRB, end of interrupt
	rte

;------------------------------------------------------------------------------
; cts_handler, dcd_handler, centronics_busy_handler: MFP GPIP2/1/0: clear bit 2/1/0 of $208.
;------------------------------------------------------------------------------
cts_handler:	; from: mfp_vectors
	bclr	#$2,interrupt_events.w          ; CTS seen
	bclr	#$2,$fffffa11.w                 ; MFP ISRB, end of interrupt
	rte
dcd_handler:	; from: mfp_vectors
	bclr	#$1,interrupt_events.w          ; DCD seen
	bclr	#$1,$fffffa11.w                 ; MFP ISRB, end of interrupt
	rte
centronics_busy_handler:	; from: mfp_vectors
	bclr	#$0,interrupt_events.w          ; BUSY seen
	bclr	#$0,$fffffa11.w                 ; MFP ISRB, end of interrupt
	rte

;------------------------------------------------------------------------------
; memory_utility: E, "Write/Read Memory Utility". Commands W address<,address>=data (a byte for
; 1-2 hex digits, else a word, repeated up to the end address), R address<,address> (bytes) and
; RW (words), ? help, ESC exit. Reads go on 16 to a line until the end address or a key (ESC ends,
; another key pauses). $284 is set while it runs so a bus error comes back to the prompt.
;------------------------------------------------------------------------------
memory_utility:	; from: read_command_line
	bsr.w	clear_screen                    ; clear the screen
	lea	memory_utility_text,a5          ; "Write/Read Memory Utility ..."
	bsr.w	print_string                    ; print it
memory_utility_prompt:	; from: bus_error_handler
	lea	msg_memory_prompt,a5            ; ">"
	bsr.w	print_string                    ; print it
	bsr.w	read_line                       ; read a line
	lea	line_buffer.w,a2                ; from the start of it
	move.b	#$ff,memory_utility_active.w    ; bus errors return to the prompt
memory_utility_command:
	cmpa.l	a2,a4                           ; end of the line?
	beq.s	memory_utility_bad_command      ; yes: nothing valid found
	move.b	(a2)+,d0                        ; next character
	cmpi.b	#$1b,d0                         ; ESC: exit
	beq.s	memory_utility_exit
	cmpi.b	#$3f,d0                         ; "?"
	beq.w	memory_utility_help
	cmpi.b	#$57,d0                         ; "W"
	beq.s	memory_utility_write
	cmpi.b	#$52,d0                         ; "R"
	beq.w	memory_utility_read
	bne.s	memory_utility_command          ; skip other characters
memory_utility_bad_command:
	lea	msg_not_a_valid_command,a5      ; "Not a valid command: W,R,RW,?,<esc>"
memory_utility_message:
	bsr.w	print_newline                   ; new line
	bsr.w	print_string                    ; print the message
	bra.s	memory_utility_prompt
memory_utility_bad_address:
	lea	msg_invalid_address,a5          ; "Invalid address given."
	bra.s	memory_utility_message
memory_utility_no_equals:
	lea	msg_no_equals_in_write,a5       ; "No "=" in write command"
	bra.s	memory_utility_message
memory_utility_bad_data:
	lea	msg_invalid_write_data,a5       ; "Invalid data in write command"
	bra.s	memory_utility_message
memory_utility_exit:
	clr.b	memory_utility_active.w         ; bus errors back to the normal report
	rts
memory_utility_write:
	bsr.w	parse_hex_address               ; first address
	bne.s	memory_utility_bad_address      ; none
	move.l	a0,memory_utility_start.w       ; start
	move.l	a0,memory_utility_end.w         ; end = start + 1
	addi.l	#$1,memory_utility_end.w        ; (a byte write then also writes the next byte)
	cmpi.b	#$3d,d0                         ; "=" next?
	beq.s	memory_utility_write_data       ; yes
	bsr.w	parse_hex_address               ; second address
	bne.s	memory_utility_bad_address      ; none
	move.l	a0,memory_utility_end.w         ; end
	cmpi.b	#$3d,d0                         ; "="?
	bne.s	memory_utility_no_equals        ; no
memory_utility_write_data:
	bsr.w	parse_hex_data                  ; the data
	bne.s	memory_utility_bad_data         ; none
	movea.l	memory_utility_start.w,a4       ; from the start
memory_utility_write_loop:
	cmpi.b	#$2,d3                          ; 2 digits or fewer?
	bgt.s	memory_utility_write_word       ; no
	move.b	d1,(a4)+                        ; write a byte
	bra.s	memory_utility_write_next
memory_utility_write_word:
	move.w	d1,(a4)+                        ; write a word
memory_utility_write_next:
	bsr.w	key_waiting                     ; key waiting?
	tst.w	d0
	bne.w	memory_utility_prompt           ; stop
	bsr.w	rs232_byte_waiting              ; RS232 byte?
	tst.w	d0
	bne.w	memory_utility_prompt           ; stop
	cmpa.l	memory_utility_end.w,a4         ; end address reached?
	ble.s	memory_utility_write_loop       ; no: next write
	bra.w	memory_utility_prompt           ; done
memory_utility_read:
	move.b	(a2)+,d3                        ; "RW"?
	cmpi.b	#$57,d3                         ; "W"?
	beq.s	memory_utility_read_address     ; yes
	move.b	-(a2),d3                        ; no: back to the address
memory_utility_read_address:
	bsr.w	parse_hex_address               ; first address
	bne.w	memory_utility_bad_address      ; none
	move.l	a0,memory_utility_start.w       ; start
	move.l	a0,memory_utility_end.w         ; end = start
	cmpi.b	#$57,d3                         ; words?
	bne.s	memory_utility_read_end         ; no
	addi.l	#$1,memory_utility_end.w        ; one word
	bra.s	memory_utility_read_start
memory_utility_read_end:
	tst.b	(a2)                            ; more on the line?
	beq.s	memory_utility_read_start       ; no: one byte
	bsr.w	parse_hex_address               ; second address
	bne.w	memory_utility_bad_address      ; none
	move.l	a0,memory_utility_end.w         ; end
memory_utility_read_start:
	movea.l	memory_utility_start.w,a4       ; from the start
memory_utility_read_line:
	moveq	#15,d0                          ; 16 values a line
	bsr.w	print_newline                   ; new line
memory_utility_read_value:
	move.l	a4,d1
	tst.b	d1                              ; at a 256-byte boundary?
	bne.s	memory_utility_read_byte_or_word ; no
	bsr.w	print_newline                   ; new line
	movea.l	a4,a0                           ; print the address
	bsr.w	print_hex_address               ; print it
	bsr.w	print_newline                   ; new line
memory_utility_read_byte_or_word:
	cmpi.b	#$57,d3                         ; words?
	bne.s	memory_utility_read_byte        ; no
	move.w	(a4)+,d1                        ; read a word
	bsr.w	print_hex_word                  ; print it
	bra.s	memory_utility_read_space
memory_utility_read_byte:
	move.b	(a4)+,d1                        ; read a byte
	bsr.w	print_hex_byte                  ; print it
memory_utility_read_space:
	bsr.w	print_space                     ; space
	cmpa.l	memory_utility_end.w,a4         ; end address passed?
	bgt.s	memory_utility_read_done        ; yes: done
	dbra	d0,memory_utility_read_value    ; next value
	bsr.w	key_waiting                     ; key waiting?
	tst.w	d0
	bne.s	memory_utility_read_paused      ; yes: pause
	bsr.w	rs232_byte_waiting
	tst.w	d0                              ; RS232 byte?
	bne.s	memory_utility_read_paused      ; yes: pause
	bra.s	memory_utility_read_line        ; next line
memory_utility_read_done:
	bsr.w	print_newline                   ; new line
	bra.w	memory_utility_prompt
memory_utility_read_paused:
	movea.l	a4,a0
	suba.l	#$1,a0                          ; the last address read
	bsr.w	print_hex_address               ; print it
	bsr.w	get_key                         ; the key
	cmpi.b	#$1b,d0                         ; ESC: prompt
	beq.w	memory_utility_prompt
	bsr.w	get_key                         ; wait for another key
	bra.s	memory_utility_read_line        ; go on
memory_utility_help:
	bsr.w	clear_screen                    ; clear the screen
	lea	memory_utility_help_text,a5     ; "Commands are: W-write memory, R-read byte, RW-read word. ..."
	bsr.w	print_string                    ; print it
	bra.w	memory_utility_prompt

;------------------------------------------------------------------------------
; read_line: reads a line into $239-$258 with echo and backspace; ESC ends it at once (and is stored).
; Out: d0 = 0 for an empty line or a full buffer; a4 the end of the line. Typed on the keyboard, RET
; waits for the Return or Enter key to be released. Changes d0, d1, a0-a4.
;------------------------------------------------------------------------------
read_line:	; from: memory_utility, rtc_set_from_input, rtc_read_digits
	lea	line_buffer.w,a4                ; line buffer
	moveq	#63,d0                          ; clear 64 bytes
read_line_clear:
	clr.b	(a4)+                           ; clear a byte
	dbra	d0,read_line_clear              ; loop
	lea	line_buffer.w,a4                ; start of the line
	bsr.w	flush_input                     ; drop waiting keys
read_line_key:
	bsr.w	get_key                         ; next key
	cmpi.b	#$1b,d0                         ; ESC?
	bne.s	read_line_not_esc               ; no
	move.b	d0,(a4)+                        ; keep it and end
	rts
read_line_not_esc:
	cmpi.b	#$8,d0                          ; backspace?
	bne.s	read_line_not_backspace         ; no
	cmpa.l	#$239,a4                        ; line empty?
	beq.s	read_line_key                   ; yes: ignore
	bsr.w	put_backspace                   ; rub out on screen
	clr.b	-(a4)                           ; and in the line
	bra.s	read_line_key
read_line_not_backspace:
	cmpi.b	#$d,d0                          ; RET?
	beq.s	read_line_wait_release          ; yes
	move.b	d0,(a4)+                        ; into the line
	move.b	d0,d1
	bsr.w	put_char                        ; echo it
	cmpa.l	#$258,a4                        ; line full?
	ble.s	read_line_key                   ; no: next key
	lea	msg_keyboard_buffer_full,a5     ; "Keyboard buffer full"
	bsr.w	print_string                    ; print it
read_line_empty:
	moveq	#0,d0                           ; nothing
	rts
read_line_wait_release:
	cmpa.l	#$239,a4                        ; empty line?
	beq.s	read_line_empty                 ; yes: nothing
	tst.b	d1                              ; RET from RS232: done
	beq.s	read_line_done
	cmpi.b	#$9c,key_release.w              ; Return released?
	beq.s	read_line_done
	cmpi.b	#$f2,key_release.w              ; keypad Enter released?
	bne.s	read_line_wait_release          ; wait
read_line_done:
	rts

;------------------------------------------------------------------------------
; parse_hex_address: reads hex digits from a2. Out: a0 the value, d7 = 0 and Z set if there was at
; least one digit, else d7 = -1. d0 holds the character after the digits ("=", "," or 0); a2 is
; past it. Changes d0-d2.
;------------------------------------------------------------------------------
parse_hex_address:	; from: memory_utility
	clr.l	d0
	clr.l	d1                              ; value
	clr.l	d2                              ; digit count
	move.b	(a2)+,d0                        ; first character
	bsr.w	hex_digit_value                 ; hex digit?
	beq.s	parse_hex_address_digit         ; yes
parse_hex_address_next:
	move.b	(a2)+,d0                        ; next character
	beq.s	parse_hex_address_end           ; end of the line
	bsr.w	hex_digit_value                 ; hex digit?
	bne.s	parse_hex_address_end           ; not a digit: end
parse_hex_address_digit:
	lsl.l	#4,d1                           ; add the digit
	or.l	d0,d1
	addq.w	#1,d2
	bra.s	parse_hex_address_next
parse_hex_address_end:
	tst.l	d2                              ; any digits?
	beq.s	parse_hex_address_none          ; no
	movea.l	d1,a0                           ; the address
	moveq	#0,d7                           ; found
	rts
parse_hex_address_none:
	moveq	#-1,d7                          ; not found
	rts

;------------------------------------------------------------------------------
; parse_hex_data: reads hex digits from a2 up to the first non-digit. Out: d1 the value, d3 the
; number of digits, d7 = 0 and Z set if there was one, else d7 = -1. Changes d0, a2.
;------------------------------------------------------------------------------
parse_hex_data:	; from: memory_utility
	clr.l	d3                              ; digit count
	clr.l	d1                              ; value
parse_hex_data_next:
	move.b	(a2)+,d0                        ; next character
	bsr.w	hex_digit_value                 ; hex digit?
	bne.s	parse_hex_data_end              ; no
	lsl.l	#4,d1                           ; add it
	or.b	d0,d1
	addq.w	#1,d3
	bra.s	parse_hex_data_next
parse_hex_data_end:
	tst.b	d3                              ; any digits?
	bne.s	parse_hex_data_done             ; yes
	moveq	#-1,d7                          ; none
	rts
parse_hex_data_done:
	moveq	#0,d7                           ; found
	rts

;------------------------------------------------------------------------------
; hex_digit_value: turns an ASCII hex digit into its value.
;  In:  d0.b the character ('0'-'9' or 'A'-'F', capitals only)
;  Out: d0.b its value 0-15 and d7 = 0 (Z set), or d7 = -1 (Z clear) when it is no hex digit
;------------------------------------------------------------------------------
hex_digit_value:	; from: parse_hex_address, parse_hex_data
	cmpi.b	#$30,d0                         ; below '0'?
	blt.s	hex_digit_value_bad             ; no digit
	cmpi.b	#$39,d0                         ; above '9'?
	bgt.s	hex_digit_value_letter          ; a letter?
	dc.w	$0200,$ff0f                     ; andi.b	#$f,d0, '0'-'9': the low nibble is the value
	moveq	#0,d7                           ; a digit
	rts
hex_digit_value_letter:
	cmpi.b	#$41,d0                         ; below 'A'?
	blt.s	hex_digit_value_bad             ; no digit
	cmpi.b	#$46,d0                         ; above 'F'?
	bgt.s	hex_digit_value_bad             ; no digit
	dc.w	$0200,$ff0f                     ; andi.b	#$f,d0, 'A'-'F' give 1-6
	addi.b	#$1,d0                          ; 2-7
	ori.b	#$8,d0                          ; $A-$F
	moveq	#0,d7                           ; a digit
	rts
hex_digit_value_bad:
	moveq	#-1,d7                          ; no hex digit
	rts

;------------------------------------------------------------------------------
; ram_test: the R test.  Tests all the RAM in five steps, keeping the cartridge's variables and the
; screen out of the way of the step running:
;  1 a 256-byte area at $500-$FFF that holds is found for the error list (none: R0 and Fail)
;  2 $10-$3FF is copied to $1000-$1FFF (the first copy that verifies), tested, and copied back
;  3 the screen ($10000) is copied to $20000 and shown there; RAM from the error list to $20000 is tested
;  4 the screen goes back to $10000; $20000 to the top of RAM is tested, a blinking '*' showing it runs
;  5 the last 256 bytes of each 64K are marked with the 64K's number and checked (address lines)
; then the cache test (8K written with the cache off and on, compared).  Errors are kept in a list
; (record_ram_error) and printed after each step (print_ram_errors); at the end the memory size and
; Pass, or Fail, are printed.  Called by jsr from the menu; the stack moves, so the return address is
; kept in d5.  Changes every register, $676, $21A, the screen address and the vectors at $70.
; The cache/speed register is restored from $21A at the end, but the 32K block test (test_32k_blocks)
; has written the screen address long there, so $FF8E21 gets that long's top byte (normally 0: 8 MHz,
; cache off).
;------------------------------------------------------------------------------
ram_test:	; from: test_routines
	move.l	(sp)+,d5                        ; the return address, kept while the stack moves
	move.l	ram_top.w,d6                    ; the top of RAM
	move.b	$ff8e21,scratch_long.w          ; Mega STE cache and CPU speed, keep the cache/speed setting
	movea.l	#msg_testing_ram,a5             ; "Testing Ram"
	bsr.w	show_status                     ; on the status line
	clr.b	test_errors.w                   ; no errors yet
	bclr	#$6,$fffffa15.w                 ; MFP IMRB, mask the keyboard/MIDI interrupt
	ori.w	#$700,sr                        ; no interrupts
	movea.l	#$500,a6                        ; look for a good 256-byte area from $500
ram_test_find_safe_block:
	move.w	#$100,d2                        ; check its words from offset $100 down
ram_test_safe_block_word:
	move.w	0(a6,d2.w),d0                   ; read a word
	eori.w	#$ffff,d0                       ; invert it
	move.w	d0,0(a6,d2.w)                   ; write it back
	move.w	0(a6,d2.w),d1                   ; read it again
	cmp.w	d0,d1                           ; held?
	beq.s	ram_test_safe_block_next_word   ; held: the next word
	adda.l	#$100,a6                        ; this area is bad: the next 256 bytes
	cmpa.l	#$1000,a6                       ; up to $1000
	bge.w	ram_test_no_safe_block          ; none holds: R0 and Fail
	bra.s	ram_test_find_safe_block        ; try that area
ram_test_safe_block_next_word:
	subq.w	#2,d2                           ; the next word down
	bne.s	ram_test_safe_block_word        ; to offset 2
	movea.l	a6,a4                           ; the good area
	adda.l	#$100,a6                        ; a6: the error list's top (it grows down)
	adda.l	#$38,a4                         ; a4: its bottom, room for 20 errors
	movea.l	#$10,a0                         ; copy $10-$3FF
	movea.l	#$1000,a1                       ; to the first of $1000, $1400, $1800, $1C00 that verifies
	clr.l	d0
	ori.w	#$1f8,d0                        ; $1F8 words
ram_test_save_low_memory:
	bsr.w	copy_and_verify                 ; copy and compare
	beq.s	ram_test_low_memory             ; the copy holds
	adda.l	#$400,a1                        ; else try the next 1K
	cmpa.l	#$2000,a1                       ; up to $2000
	bne.s	ram_test_save_low_memory
	bra.s	ram_test_below_screen           ; no good copy: the low memory test is left out
ram_test_low_memory:
	movea.l	a1,a5                           ; the copy's address
	movea.l	#$10,a0                         ; test from $10
	movea.l	a6,a1                           ; up to the error list less 1K
	suba.l	#$400,a1
	bsr.w	test_ram_range                  ; test that range
	movea.l	a5,a0                           ; copy the saved low memory
	movea.l	#$10,a1                         ; back to $10
	clr.l	d0
	move.w	#$1f8,d0                        ; $1F8 words
	bsr.w	copy_and_verify                 ; copy and compare
	bsr.w	print_ram_errors                ; print the errors found so far
	bset	#$6,$fffffa15.w                 ; MFP IMRB, unmask the keyboard/MIDI interrupt
	move.w	#$2400,sr                       ; IPL 4
ram_test_below_screen:
	movea.l	#$10000,a0                      ; copy the screen at $10000
	movea.l	#$20000,a1                      ; to $20000
	move.l	#$4000,d0                       ; 32K
	bsr.w	copy_words                      ; copy
	move.b	#$2,$ffff8201.w                 ; video base high, and show it there
	movea.l	#$500,sp                        ; the stack below the error list area
	movea.l	a6,a0                           ; test from the error list
	movea.l	#$20000,a1                      ; up to $20000
	bsr.w	test_ram_range                  ; test it
	btst	#$7,mode_flags.w                ; stopping allowed?
	beq.s	ram_test_upper_ram              ; no
	bsr.w	key_waiting                     ; a key waiting?
	tst.b	d0
	bne.w	ram_test_cache                  ; yes: straight to the cache test
ram_test_upper_ram:
	bsr.w	print_ram_errors                ; print the errors found so far
	movea.l	#$20000,sp                      ; the stack at $20000, below the range tested next
	movea.l	#$20000,a0                      ; copy the screen back
	movea.l	#$10000,a1                      ; to $10000
	move.l	#$4000,d0                       ; 32K
	bsr.w	copy_words                      ; copy
	move.b	#$1,$ffff8201.w                 ; video base high, and show it there
	lea	ram_test_vbl,a0                 ; the VBL routine that blinks the '*'
	move.l	a0,$70.w                        ; VBL vector
	move.w	#$1e,star_countdown.w           ; blink every 30 VBLs
	clr.b	star_inverse.w                  ; '*' shown first
	move.w	#$2200,sr                       ; IPL 2: VBLs on
	movea.l	#$20000,a0                      ; test from $20000
	movea.l	ram_top.w,a1                    ; to the top of RAM
	bsr.w	test_ram_range                  ; test it
	move.w	#$2400,sr                       ; IPL 4
	move.w	#$3,d7                          ; errors given as R3
	movea.l	#$ff00,a0                       ; the last 256 bytes of the first 64K
	moveq	#0,d0                           ; the 64K's number
	moveq	#0,d1
ram_test_bank_mark_write:
	move.w	d0,(a0)+                        ; mark a word with the 64K's number
	move.w	a0,d1                           ; the low word of the address
	cmpi.w	#$0,d1                          ; to the end of this 64K
	bne.s	ram_test_bank_mark_write
	addq.w	#1,d0                           ; the next 64K's number
	adda.l	#$ff00,a0                       ; its last 256 bytes
	cmpa.l	ram_top.w,a0                    ; to the top of RAM
	ble.s	ram_test_bank_mark_write
	movea.l	#$ff00,a0                       ; check them, from the first 64K
	moveq	#0,d0                           ; the first 64K's number
ram_test_bank_mark_check:
	cmp.w	(a0)+,d0                        ; still the 64K's number?
	beq.s	ram_test_bank_mark_next         ; yes
	suba.l	#$2,a0                          ; back to the bad word
	move.w	(a0),d1                         ; what was read
	bsr.w	record_ram_error                ; record the error
	adda.l	#$2,a0                          ; on past it
ram_test_bank_mark_next:
	move.w	a0,d1                           ; the low word of the address
	cmpi.w	#$0,d1                          ; to the end of this 64K
	bne.s	ram_test_bank_mark_check
	addq.w	#1,d0                           ; the next 64K's number
	adda.l	#$ff00,a0                       ; its last 256 bytes
	cmpa.l	ram_top.w,a0                    ; to the top of RAM
	ble.s	ram_test_bank_mark_check
ram_test_cache:
	bsr.w	print_ram_errors                ; print the errors found so far
	movea.l	#$2000,a0                       ; 8K blocks at $2000, $4000 (written with the cache on)
	movea.l	#$4000,a1
	movea.l	#$6000,a2                       ; and $6000, $8000 (written with it off)
	movea.l	#$8000,a3
	move.l	#$fff,d0                        ; $1000 words each
	move.w	#$aaaa,d1                       ; pattern 1
	move.w	#$5555,d2                       ; pattern 2
	move.b	$0.w,$ff8e21                    ; Mega STE cache and CPU speed, cache off, 8 MHz; reads the byte at
                                                ;   address 0 where #0 was meant
	movem.l	d0/a0-a3,-(sp)                  ; keep the counters and addresses
	add.l	#$1000,d0                       ; $2000 words: $2000-$5FFF
ram_test_cache_clear:
	move.w	#$0,(a0)+                       ; cleared
	dbra	d0,ram_test_cache_clear
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_fill_aaaa:
	move.w	d1,(a2)+                        ; $6000-$7FFF: $AAAA, cache off
	dbra	d0,ram_test_cache_fill_aaaa
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_fill_5555:
	move.w	d2,(a3)+                        ; $8000-$9FFF: $5555, cache off
	dbra	d0,ram_test_cache_fill_5555
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	move.b	$3.w,$ff8e21                    ; Mega STE cache and CPU speed, cache on, 16 MHz; reads the byte at
                                                ;   address 3 where #3 was meant
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_write_aaaa:
	move.w	d1,(a0)+                        ; $2000-$3FFF: $AAAA, cache on
	dbra	d0,ram_test_cache_write_aaaa
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_write_5555:
	move.w	d2,(a1)+                        ; $4000-$5FFF: $5555, cache on
	dbra	d0,ram_test_cache_write_5555
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_check_5555:
	cmpm.w	(a1)+,(a3)+                     ; $4000 block against $8000 block
	beq.s	ram_test_cache_next_5555        ; the same
	move.w	-(a3),d0                        ; written
	move.w	-(a1),d1                        ; read
	movea.l	a1,a0                           ; the bad address
	bra.w	ram_test_cache_error            ; a cache error
ram_test_cache_next_5555:
	dbra	d0,ram_test_cache_check_5555    ; the next word
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_check_aaaa:
	cmpm.w	(a0)+,(a2)+                     ; $2000 block against $6000 block
	beq.s	ram_test_cache_next_aaaa        ; the same
	move.w	-(a2),d0                        ; written
	move.w	-(a0),d1                        ; read (a0 the bad address)
	bra.w	ram_test_cache_error            ; a cache error
ram_test_cache_next_aaaa:
	dbra	d0,ram_test_cache_check_aaaa    ; the next word
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_recheck_aaaa:
	cmpm.w	(a0)+,(a2)+                     ; the $2000 block again
	beq.s	ram_test_cache_renext_aaaa      ; the same
	move.w	-(a2),d0                        ; written
	move.w	-(a0),d1                        ; read
	bra.w	ram_test_cache_error            ; a cache error
ram_test_cache_renext_aaaa:
	dbra	d0,ram_test_cache_recheck_aaaa  ; the next word
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_recheck_5555:
	cmpm.w	(a1)+,(a3)+                     ; the $4000 block again
	beq.s	ram_test_cache_renext_5555      ; the same
	move.w	-(a3),d0                        ; written
	move.w	-(a1),d1                        ; read
	movea.l	a1,a0                           ; the bad address
	bra.w	ram_test_cache_error            ; a cache error
ram_test_cache_renext_5555:
	dbra	d0,ram_test_cache_recheck_5555  ; the next word
	movem.l	(sp)+,d0/a0-a3                  ; back to the starts
	movem.l	d0/a0-a3,-(sp)                  ; keep them
ram_test_cache_last_check_5555:
	cmpm.w	(a1)+,(a3)+                     ; the $4000 block a third time
	beq.s	ram_test_cache_last_next_5555   ; the same
	move.w	-(a3),d0                        ; written
	move.w	-(a1),d1                        ; read
	movea.l	a1,a0                           ; the bad address
	bra.w	ram_test_cache_error            ; a cache error
ram_test_cache_last_next_5555:
	dbra	d0,ram_test_cache_last_check_5555 ; the next word
	movem.l	(sp)+,d0/a0-a3
	ori.w	#$4,sr                          ; Z set: the cache test passed
	bra.s	ram_test_result                 ; the result
ram_test_cache_error:
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	moveq	#1,d7                           ; printed as R1
	bsr.w	print_ram_error                 ; print the error at once ($676 is not set)
	movem.l	(sp)+,d0/a0-a3                  ; the counters and addresses off the stack
	andi.w	#$fffb,sr                       ; Z clear: the cache test failed
ram_test_result:
	tst.b	test_errors.w                   ; any error in the list?
	beq.s	ram_test_show_size              ; no
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bra.s	ram_test_print_result           ; print it
ram_test_show_size:
	move.l	ram_top.w,d0                    ; the top of RAM
	swap	d0                              ; in 64K
	andi.l	#$fe,d0                         ; 64K units, even
	moveq	#4,d1                           ; look it up in the sizes 4, 8, $10, $20, $40
	lea	ram_size_codes,a0               ; 4 (256K) to $40 (4M)
ram_test_find_size:
	cmp.b	0(a0,d1.w),d0                   ; this size?
	beq.w	ram_test_size_text              ; found
	dbra	d1,ram_test_find_size           ; not found leaves d1 = -1 and the long before the size texts is used
ram_test_size_text:
	movea.l	#ram_size_texts,a0              ; the size texts "256k RAM" to "4M RAM"
	lsl.w	#2,d1                           ; a long index
	movea.l	0(a0,d1.w),a5                   ; the size text
	moveq	#40,d0                          ; at column 40
	moveq	#0,d1                           ; of the status line
	bsr.w	show_status_at                  ; print it there
	movea.l	#msg_pass,a5                    ; "Pass"
ram_test_print_result:
	bsr.w	show_result                     ; print the result
	move.b	scratch_long.w,$ff8e21          ; Mega STE cache and CPU speed, restore the cache/speed setting (see the
                                                ;   header)
	move.l	d5,-(sp)                        ; the return address back
	rts                                     ; back to the menu
ram_test_no_safe_block:
	movea.l	a6,a0                           ; the last area tried
	movem.l	d0-d1/a0,-(sp)                  ; (pushed and popped again: does nothing)
	movem.l	(sp)+,d0-d1/a0
	moveq	#0,d7                           ; printed as R0
	bsr.w	print_ram_error                 ; print it
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bra.s	ram_test_print_result           ; print the result

;------------------------------------------------------------------------------
; test_ram_range: runs the RAM tests on a0-a1: the $AAAA/$5555 patterns (R1), each word holding its
; own address and then its address byte-swapped (R2), and the 32K block test (R3), each only while the
; error list has room.
;  In:  a0 start, a1 end, a6/a4 the error list's top and bottom
;  Out: errors added to the error list; a0 kept.  Leaves the VBL vector at the routine that only
;       clears $294 and the IPL at 4.
;------------------------------------------------------------------------------
test_ram_range:	; from: low_ram_test, ram_test
	move.l	a0,-(sp)                        ; keep the start
	bsr.w	test_alternating_patterns       ; the pattern test
	cmpa.l	a4,a6                           ; error list full?
	ble.s	test_ram_range_done             ; yes: stop
	bsr.w	test_address_in_word            ; the address test
	cmpa.l	a4,a6                           ; error list full?
	ble.s	test_ram_range_done             ; yes: stop
	move.w	#$2600,sr                       ; IPL 6
	move.l	#vbl_handler,$70.w              ; VBL vector, a VBL routine that clears $294
	bsr.w	test_32k_blocks                 ; the 32K block test
test_ram_range_done:
	movea.l	(sp)+,a0                        ; the start back
	rts

;------------------------------------------------------------------------------
; test_alternating_patterns: fills a0-a1 with $AAAA,$5555,... and checks it, then with $5555,$AAAA,...
;  In:  a0 start, a1 end.  Out: errors recorded as R1.  Changes d0-d2, a2, d7, the upper word of d0.
;------------------------------------------------------------------------------
test_alternating_patterns:	; from: test_ram_range, vme_test
	moveq	#1,d7                           ; errors are R1
	move.w	#$aaaa,d0                       ; even words
	move.w	#$5555,d2                       ; odd words
	bsr.w	test_pattern_pair               ; fill and check
	lsr.w	#1,d0                           ; $5555
	lsl.w	#1,d2                           ; $AAAA
	bsr.w	test_pattern_pair               ; fill and check the other way round
	rts

;------------------------------------------------------------------------------
; test_pattern_pair: fills a0-a1 with d0 in the even words and d2 in the odd ones, then checks them.
;  In:  a0 start, a1 end, d0/d2 the patterns, d7 the error code.  Out: errors recorded (record_ram_error);
;       after an odd-word error the upper word of d0 holds d2.  Changes d1, a2.
;------------------------------------------------------------------------------
test_pattern_pair:	; from: test_alternating_patterns, hd_known_bad_sector
	movea.l	a0,a2                           ; keep the start
test_pattern_pair_fill:
	move.w	d0,(a0)+                        ; even word
	move.w	d2,(a0)+                        ; odd word
	cmpa.l	a0,a1                           ; to the end
	bne.s	test_pattern_pair_fill
	movea.l	a2,a0                           ; check from the start
test_pattern_pair_check:
	move.w	(a0)+,d1                        ; even word
	cmp.w	d0,d1                           ; the even pattern?
	beq.s	test_pattern_pair_check_odd     ; held
	suba.l	#$2,a0                          ; back to the bad word
	bsr.w	record_ram_error                ; record it (d0 written, d1 read)
	adda.l	#$2,a0                          ; on again
test_pattern_pair_check_odd:
	move.w	(a0)+,d1                        ; odd word
	cmp.w	d1,d2                           ; the odd pattern?
	beq.s	test_pattern_pair_next          ; held
	suba.l	#$2,a0                          ; back to the bad word
	swap	d0                              ; keep d0 in the upper word
	move.w	d2,d0                           ; the odd pattern as the value written
	bsr.w	record_ram_error                ; record it
	swap	d0                              ; d0 back
	adda.l	#$2,a0                          ; on again
test_pattern_pair_next:
	cmpa.l	a0,a1                           ; to the end
	bne.s	test_pattern_pair_check
	movea.l	a2,a0                           ; a0 back to the start
	rts

;------------------------------------------------------------------------------
; test_address_in_word: writes each word of a0-a1 with the low word of its own address and checks it,
; then the same with the address byte-swapped.
;  In:  a0 start, a1 end.  Out: errors recorded as R2.  Changes d0, d1, d7, a2.
;------------------------------------------------------------------------------
test_address_in_word:	; from: test_ram_range
	movea.l	a0,a2                           ; keep the start
	moveq	#2,d7                           ; errors are R2
test_address_fill:
	move.w	a0,(a0)+                        ; the word's own address
	cmpa.l	a0,a1                           ; to the end
	bgt.s	test_address_fill
	movea.l	a2,a0                           ; check from the start
test_address_check:
	move.w	(a0),d1                         ; read
	cmp.w	a0,d1                           ; its address?
	beq.s	test_address_check_next         ; yes
	move.w	a0,d0                           ; the value written
	bsr.w	record_ram_error                ; record it
test_address_check_next:
	adda.l	#$2,a0                          ; the next word
	cmpa.l	a0,a1                           ; to the end
	bgt.s	test_address_check
	movea.l	a2,a0                           ; now byte-swapped
test_swapped_address_fill:
	move.w	a0,d0                           ; the address
	rol.w	#8,d0                           ; the address with its bytes swapped
	move.w	d0,(a0)+                        ; written
	cmpa.l	a0,a1                           ; to the end
	bgt.s	test_swapped_address_fill
	movea.l	a2,a0                           ; check from the start
test_swapped_address_check:
	move.w	a0,d0                           ; the address
	rol.w	#8,d0                           ; the value written
	move.w	(a0)+,d1                        ; read
	cmp.w	d1,d0                           ; the same?
	beq.s	test_swapped_address_next       ; held
	suba.l	#$2,a0                          ; back to the bad word
	bsr.w	record_ram_error                ; record it
	adda.l	#$2,a0                          ; on again
test_swapped_address_next:
	cmpa.l	a0,a1                           ; to the end
	bgt.s	test_swapped_address_check
	movea.l	a2,a0                           ; a0 back to the start
	rts

;------------------------------------------------------------------------------
; test_32k_blocks: tests a0-a1 in 32K blocks, each shown as the screen while it runs: a count up from
; the bottom and a count down from $FFFF at the top, then checked.  Left out for a range starting below
; $400 or shorter than 32K.  Stops at the first bad block.
;  In:  a0 start, a1 end.  Out: errors recorded as R3; a0/a1 kept.  Writes the screen address to $21A.l;
;       changes d0-d4, d7, a2, a3; leaves the IPL at 4.
;------------------------------------------------------------------------------
test_32k_blocks:	; from: test_ram_range
	cmpa.l	#$400,a0                        ; starts below $400 (the low memory test)?
	blt.s	test_32k_blocks_skip            ; yes: left out
	adda.l	#$8000,a0                       ; the first block's end
	cmpa.l	a0,a1                           ; at least 32K?
	bge.s	test_32k_blocks_start           ; yes
	suba.l	#$8000,a0                       ; start back
test_32k_blocks_skip:
	rts
test_32k_blocks_start:
	moveq	#3,d7                           ; errors are R3
	suba.l	#$8000,a0                       ; the start back
	move.l	a0,d3                           ; keep the start
	move.l	a1,d4                           ; and the end
	movea.l	a0,a1                           ; the block's end
	adda.l	#$8000,a1
	move.w	#$2200,sr                       ; IPL 2: VBLs on
	move.b	$ffff8201.w,d0                  ; video base high, keep the screen address
	lsl.w	#8,d0
	move.b	$ffff8203.w,d0                  ; video base mid
	move.l	d0,scratch_long.w               ; in $21A (over the saved cache/speed byte)
test_32k_blocks_next:
	move.l	a0,d0                           ; show this block
	bsr.w	show_32k_block                  ; show it
	bsr.w	fill_32k_block                  ; fill it
	bsr.w	check_32k_block                 ; and check it
	tst.l	d7                              ; bad block?
	bmi.s	test_32k_blocks_end             ; yes: stop
	adda.l	#$8000,a0                       ; the next 32K
	adda.l	#$8000,a1
	cmpa.l	d4,a1                           ; while it ends within the range
	ble.s	test_32k_blocks_next
test_32k_blocks_end:
	move.l	scratch_long.w,d0               ; the screen address back
	move.b	d0,$ffff8203.w                  ; video base mid
	lsr.l	#8,d0
	move.b	d0,$ffff8201.w                  ; video base high
	move.w	#$2400,sr                       ; IPL 4
	movea.l	d4,a1                           ; the end back
	movea.l	d3,a0                           ; and the start
	rts

;------------------------------------------------------------------------------
; fill_32k_block: fills a0-a1 with 0,1,2,... from the bottom and $FFFF,$FFFE,... from the top, until
; the two meet.  In: a0 start, a1 end.  Changes d0, d1, a2, a3.
;------------------------------------------------------------------------------
fill_32k_block:	; from: test_32k_blocks
	movea.l	a0,a2                           ; from the bottom
	movea.l	a1,a3                           ; from the top
	moveq	#0,d0                           ; count up from 0
	moveq	#-1,d1                          ; count down from $FFFF
fill_32k_block_loop:
	move.w	d0,(a2)+                        ; a word at the bottom
	move.w	d1,-(a3)                        ; a word at the top
	add.w	#$1,d0                          ; up
	sub.w	#$1,d1                          ; down
	cmpa.l	a2,a3                           ; until they meet
	bgt.s	fill_32k_block_loop
	rts

;------------------------------------------------------------------------------
; check_32k_block: checks the block fill_32k_block wrote: the lower 16K counting up from 0, the upper 16K
; counting down from $FFFF at the top.
;  In:  a0 start, a1 end.  Out: a0/a1 kept; the first bad word recorded and bit 31 of d7 set.
;  An error in the upper half is recorded with the address 2 too high.  Changes d0, d1, a2, a3.
;------------------------------------------------------------------------------
check_32k_block:	; from: test_32k_blocks
	movea.l	a0,a2                           ; keep the start
	movea.l	a1,a3                           ; and the end
	suba.l	#$4000,a1                       ; the middle
	moveq	#0,d0                           ; the count expected
check_32k_block_lower:
	move.w	(a0)+,d1                        ; read
	cmp.w	d0,d1                           ; the count?
	bne.s	check_32k_block_lower_error     ; no: error
	add.l	#$1,d0                          ; the next count
	cmpa.l	a0,a1                           ; to the middle
	bne.s	check_32k_block_lower
	movea.l	a3,a0                           ; the upper half, from the top down
	movea.l	a2,a1                           ; the start
	adda.l	#$4000,a1                       ; to the middle
	moveq	#-1,d0                          ; the count expected
check_32k_block_upper:
	move.w	-(a0),d1                        ; read
	cmp.w	d0,d1                           ; the count?
	bne.s	check_32k_block_upper_error     ; no: error
	sub.w	#$1,d0                          ; the next count
	cmpa.l	a0,a1                           ; to the middle
	bne.s	check_32k_block_upper
check_32k_block_done:
	movea.l	a2,a0                           ; the start back
	movea.l	a3,a1                           ; and the end
	rts
check_32k_block_lower_error:
	suba.l	#$2,a0                          ; back to the bad word
	bsr.w	record_ram_error                ; record it
	adda.l	#$2,a0
	bra.s	check_32k_block_stop
check_32k_block_upper_error:
	adda.l	#$2,a0                          ; one word past the bad one
	bsr.w	record_ram_error                ; record it
	suba.l	#$2,a0
check_32k_block_stop:
	bset	#$1f,d7                         ; mark the block bad
	bra.s	check_32k_block_done

;------------------------------------------------------------------------------
; show_32k_block: waits for a VBL, then makes the screen start at d0 (a 256-byte boundary).
;  In:  d0.l the address.  Changes d0; leaves the IPL at 4.
;------------------------------------------------------------------------------
show_32k_block:	; from: test_32k_blocks
	move.w	#$2200,sr                       ; IPL 2: VBLs on
	move.b	#$1,vbl_flag.w                  ; set; the VBL clears it
show_32k_block_wait_vbl:
	tst.b	vbl_flag.w                      ; the VBL yet?
	bne.s	show_32k_block_wait_vbl         ; no
	move.w	#$2400,sr                       ; IPL 4
	lsr.l	#8,d0                           ; the address in 256 bytes
	move.b	d0,$ffff8203.w                  ; video base mid, screen address middle byte
	lsr.l	#8,d0                           ; in 64K
	move.b	d0,$ffff8201.w                  ; video base high, high byte
	rts

;------------------------------------------------------------------------------
; copy_and_verify: copies d0 words from a0 to a1 and compares the copy.  An error is printed at once
; (as R1, red background) without going into the error list.
;  In:  a0 from, a1 to, d0 words.  Out: Z set when the copy holds.  Changes d0, d1, d7.
;------------------------------------------------------------------------------
copy_and_verify:	; from: ram_test
	movem.l	a0-a1,-(sp)                     ; keep the addresses
	bsr.w	copy_words                      ; copy
	subq.w	#1,d0                           ; for dbra
copy_and_verify_loop:
	cmpm.w	(a0)+,(a1)+                     ; compare
	bne.s	copy_and_verify_error           ; differs
	dbra	d0,copy_and_verify_loop         ; the next word
	movem.l	(sp)+,a0-a1                     ; the addresses back
	ori.w	#$4,sr                          ; Z set: the copy holds
	rts
copy_and_verify_error:
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	move.w	(a0),d0                         ; the word copied
	move.w	(a1),d1                         ; the word read back
	movea.l	a1,a0                           ; its address
	moveq	#1,d7                           ; printed as R1
	bsr.w	print_ram_error                 ; print it
	movem.l	(sp)+,a0-a1                     ; the addresses back
	andi.w	#$fffb,sr                       ; Z clear: the copy failed
	rts

;------------------------------------------------------------------------------
; copy_words: copies d0 words from a0 to a1.  Registers kept.
;------------------------------------------------------------------------------
copy_words:	; from: ram_test, copy_and_verify
	movem.l	d0/a0-a1,-(sp)                  ; keep the count and addresses
	subq.w	#1,d0                           ; for dbra
copy_words_loop:
	move.w	(a0)+,(a1)+                     ; a word
	dbra	d0,copy_words_loop              ; the next
	movem.l	(sp)+,d0/a0-a1
	rts

;------------------------------------------------------------------------------
; record_ram_error: puts an error in the error list (10 bytes, pushed down from a6), when a6 is still
; above a4, sets $676 bit 0 and turns the background red.
;  In:  d7 the error code (0-3, the text R0-R3), a0 the address, d0 the value written, d1 the value read.
;------------------------------------------------------------------------------
record_ram_error:	; from: ram_test, test_pattern_pair, test_address_in_word, check_32k_block
	cmpa.l	a4,a6                           ; list full?
	ble.s	record_ram_error_full           ; yes: dropped
	move.w	d7,-(a6)                        ; the error code
	move.l	a0,-(a6)                        ; the address
	move.w	d0,-(a6)                        ; written
	move.w	d1,-(a6)                        ; read
	bset	#$0,test_errors.w               ; a RAM error
	move.w	#$500,$ffff8240.w               ; palette 0, red background
record_ram_error_full:
	rts

;------------------------------------------------------------------------------
; print_ram_errors: prints and takes off every error in the error list, newest first.
;  In:  a6/a4 the list.  Out: the list empty.  Changes d0, d1, d7, a0.
;------------------------------------------------------------------------------
print_ram_errors:	; from: bus_error_caught, ram_test, vme_test
	move.l	a4,d0                           ; the list's top: a4 + 200
	add.w	#$c8,d0
	cmpa.w	d0,a6                           ; anything in the list?
	bge.s	print_ram_errors_done           ; no
	move.w	(a6)+,d1                        ; read
	move.w	(a6)+,d0                        ; written
	movea.l	(a6)+,a0                        ; the address
	move.w	(a6)+,d7                        ; the error code
	bsr.w	print_ram_error                 ; print it
	bra.s	print_ram_errors                ; the next error
print_ram_errors_done:
	rts

;------------------------------------------------------------------------------
; print_ram_error: prints one RAM error: "Rn RAM address=" (or "Cache RAM " for codes above 4), the
; address, " W:" the value written, " R:" the value read, then the numbers of the bad bits.
;  In:  d7 the code, a0 the address, d0 written, d1 read.  Changes d7.
;------------------------------------------------------------------------------
print_ram_error:	; from: ram_test, copy_and_verify, print_ram_errors
	movem.l	d0-d1/a0,-(sp)
	move.l	a6,-(sp)                        ; keep the error list's top
	cmpi.w	#$0,d7                          ; code 0?
	bne.s	print_ram_error_pattern
	movea.l	#msg_r0_ram_address,a5          ; "R0 RAM address="
	bra.s	print_ram_error_details
print_ram_error_pattern:
	cmpi.w	#$1,d7                          ; code 1?
	bne.s	print_ram_error_address
	movea.l	#msg_r1_ram_address,a5          ; "R1 RAM address="
	bra.s	print_ram_error_details
print_ram_error_address:
	cmpi.w	#$2,d7                          ; code 2?
	bne.s	print_ram_error_block
	movea.l	#msg_r2_ram_address,a5          ; "R2 RAM address="
	bra.s	print_ram_error_details
print_ram_error_block:
	cmpi.w	#$3,d7                          ; code 3?
	bne.s	print_ram_error_spare
	movea.l	#msg_r3_ram_address,a5          ; "R3 RAM address="
	bra.s	print_ram_error_details
print_ram_error_spare:
	cmpi.w	#$4,d7                          ; code 4? (no test uses it)
	bne.s	print_ram_error_cache_text
	movea.l	#msg_r4_ram_address,a5          ; "R4 RAM address="
	bra.s	print_ram_error_details
print_ram_error_cache_text:
	movea.l	#msg_cache_ram,a5               ; "Cache RAM " (no test uses it)
print_ram_error_details:
	bsr.w	print_string                    ; print the text
	move.w	d0,d7                           ; the bad bits
	eor.w	d1,d7
	move.w	d1,-(sp)                        ; keep read
	move.w	d0,-(sp)                        ; keep written
	bsr.w	print_hex_address               ; the address
	bsr.w	print_space                     ; a space
	lea	msg_written,a5                  ; " W:"
	bsr.w	print_string
	move.w	(sp)+,d1                        ; written
	bsr.w	print_hex_word                  ; the value written
	bsr.w	print_space                     ; a space
	lea	msg_read,a5                     ; " R:"
	bsr.w	print_string
	move.w	(sp)+,d1                        ; read
	bsr.w	print_hex_word                  ; the value read
	bsr.w	print_bad_bits                  ; and the bad bits
	movea.l	(sp)+,a6                        ; the error list's top back
	movem.l	(sp)+,d0-d1/a0
	rts

;------------------------------------------------------------------------------
; print_bad_bits: prints "  bad bits: " and the number (0-15) of every bit set in d7, then a new line.
;  In:  d7 the bits.  Changes d1.
;------------------------------------------------------------------------------
print_bad_bits:	; from: print_ram_error
	lea	msg_bad_bits,a5                 ; "  bad bits: "
	bsr.w	print_string
	moveq	#0,d1                           ; from bit 0
print_bad_bits_loop:
	btst	d1,d7                           ; bad?
	beq.s	print_bad_bits_next             ; no
	move.w	d1,-(sp)                        ; keep the bit number
	bsr.w	print_decimal_teen              ; its number in decimal
	bsr.w	print_space                     ; a space
	move.w	(sp)+,d1
print_bad_bits_next:
	addq.w	#1,d1                           ; the next bit
	cmpi.w	#$10,d1                         ; to bit 15
	bne.s	print_bad_bits_loop
	bsr.w	print_newline                   ; new line
	rts

;------------------------------------------------------------------------------
; ram_test_vbl: the VBL routine while the RAM above $20000 is tested: every 30 VBLs prints the
; '*' at column 13 of the status line, inverse and plain in turn, to show the test is running.
;------------------------------------------------------------------------------
ram_test_vbl:	; from: ram_test, vme_test
	subi.w	#$1,star_countdown.w            ; 30 VBLs yet?
	bne.s	ram_test_vbl_exit               ; no
	move.w	#$1e,star_countdown.w           ; the next 30
	movem.l	d0-d7/a0-a6,-(sp)
	bsr.w	inverse_on                      ; inverse
	eori.w	#$ff,star_inverse.w             ; turn about
	bne.s	ram_test_vbl_star               ; inverse this time
	bsr.w	inverse_off                     ; plain this time
ram_test_vbl_star:
	lea	msg_asterisk,a5                 ; "*"
	move.w	#$d,d0                          ; column 13
	move.w	#$0,d1                          ; of the status line
	bsr.w	show_status_at                  ; print it
	bsr.w	inverse_off                     ; plain again
	movem.l	(sp)+,d0-d7/a0-a6
ram_test_vbl_exit:
	rte

;------------------------------------------------------------------------------
; rom_test: the O test.  Prints the TOS version, country and PAL/NTSC, then the byte sums and the
; CRC-16s (CCITT) of the two ROM chips, u206 the even bytes and u207 the odd bytes of the 256K at
; $E00000.  The CRCs are compared with the ones stored in the last four bytes of the ROM; a mismatch is
; printed (inverse) with the stored value and gives Fail.  Changes d0-d6, a0, a2, a5, $676, $677,
; $4B2, $4B8, $4BE, $4C4.
;------------------------------------------------------------------------------
rom_test:	; from: test_routines
	lea	msg_rom_test,a5                 ; "ROM checksum/crc test"
	bsr.w	show_status                     ; on the status line
	clr.b	test_errors.w                   ; no errors yet
	clr.b	test_errors_high.w
	bsr.w	print_tos_version               ; the TOS version, country, PAL/NTSC
	movea.l	#$e00000,a0                     ; the ROM
	move.l	#$20000,d4                      ; $20000 byte pairs
	bsr.w	rom_checksums                   ; sum the even and the odd bytes
	move.w	d1,rom_sum_u206.w               ; u206 sum
	move.w	d2,rom_sum_u207.w               ; u207 sum
	lea	msg_prom_header,a5              ; the "PROM  u206  u207" heading
	bsr.w	print_string
	lea	msg_calculated_checksums,a5     ; "Calculated ROM checksums"
	bsr.w	print_string
	move.w	rom_sum_u206.w,d1               ; u206 sum
	move.w	rom_sum_u207.w,d2               ; u207 sum
	bsr.w	print_two_words                 ; print both
	lea	$e00000,a0                      ; the even bytes
	move.l	#$1fffe,d2                      ; all but the stored CRCs
	bsr.w	rom_crc                         ; CRC of u206
	move.w	d0,rom_crc_u206.w
	adda.l	#$1,a0                          ; the odd bytes
	move.l	#$1fffe,d2                      ; all but the stored CRCs
	bsr.w	rom_crc                         ; CRC of u207
	move.w	d0,rom_crc_u207.w
	lea	msg_calculated_crcs,a5          ; "Calculated ROM CRCs"
	bsr.w	print_string
	move.w	rom_crc_u206.w,d1               ; u206 CRC
	move.w	rom_crc_u207.w,d2               ; u207 CRC
	bsr.w	print_two_words                 ; print both
	lea	$e00000,a0                      ; the stored CRCs
	adda.l	#$3fffc,a0                      ; in the last 4 bytes
	move.b	(a0),d1                         ; u206's stored CRC, high byte
	lsl.w	#8,d1
	move.b	2(a0),d1                        ; low byte
	move.b	1(a0),d2                        ; u207's stored CRC, high byte
	lsl.w	#8,d2
	move.b	3(a0),d2                        ; low byte
	bsr.w	inverse_on                      ; mismatches inverse
	clr.l	d6                              ; no CRC errors
	cmp.w	rom_crc_u206.w,d1               ; u206 right?
	beq.s	rom_test_check_u207             ; yes
	bset	#$1,d6                          ; a CRC error
	lea	msg_crc_mismatch,a5             ; "CRC  mismatch  in   u20"
	bsr.w	print_string
	lea	msg_u206_tab,a5                 ; "6"
	bsr.w	print_string
	bsr.w	print_hex_word                  ; the stored CRC
	bsr.w	print_newline                   ; new line
rom_test_check_u207:
	cmp.w	rom_crc_u207.w,d2               ; u207 right?
	beq.s	rom_test_result                 ; yes
	bset	#$1,d6                          ; a CRC error
	lea	msg_crc_mismatch,a5             ; "CRC  mismatch  in   u20"
	bsr.w	print_string
	lea	msg_u207_tab,a5                 ; "7"
	bsr.w	print_string
	move.w	d2,d1                           ; the stored CRC
	bsr.w	print_hex_word
	bsr.w	print_newline                   ; new line
rom_test_result:
	bsr.w	inverse_off                     ; plain again
	move.b	d6,test_errors_high.w           ; the CRC errors
	tst.b	test_errors.w                   ; any error?
	bne.s	rom_test_fail                   ; yes
	tst.b	test_errors_high.w
	bne.s	rom_test_fail                   ; yes
	lea	msg_pass,a5                     ; "Pass"
	bra.s	rom_test_print_result
rom_test_fail:
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
	move.w	#$500,$ffff8240.w               ; palette 0, red background
rom_test_print_result:
	bsr.w	show_result                     ; print the result
	rts

;------------------------------------------------------------------------------
; print_tos_version: prints "Version " and the TOS version from the ROM header as n.nn, the country
; (from the header's os_conf bits 1-4) and "PAL" or "NTSC" (os_conf bit 0).  Changes d0-d2, a0, a5.
;------------------------------------------------------------------------------
print_tos_version:	; from: menu, rom_test
	lea	msg_version,a5                  ; "Version "
	bsr.w	print_string
	move.w	$e00002,d1                      ; the TOS version
	move.w	d1,d2
	lsr.w	#8,d1                           ; major
	bsr.w	print_hex_digit                 ; one digit
	move.w	#$2e,d1                         ; '.'
	bsr.w	put_char
	move.w	d2,d1
	lsr.w	#4,d1                           ; minor, first digit
	bsr.w	print_hex_digit
	move.w	d2,d1
	bsr.w	print_hex_digit                 ; second digit
	bsr.w	print_space                     ; a space
	clr.l	d0
	move.w	$e0001c,d0                      ; os_conf
	andi.w	#$1e,d0                         ; the country code times 2
	lsl.w	#1,d0                           ; times 4: a long index
	lea	country_names,a0                ; the country names, "USA " first
	movea.l	0(a0,d0.w),a5
	bsr.w	print_string                    ; the country
	btst	#$0,$e0001d                     ; PAL?
	beq.w	print_tos_version_ntsc          ; no
	lea	msg_pal,a5                      ; "PAL"
	bra.w	print_tos_version_standard
print_tos_version_ntsc:
	lea	msg_ntsc,a5                     ; "NTSC"
print_tos_version_standard:
	bsr.w	print_string                    ; print it
	rts

;------------------------------------------------------------------------------
; print_two_words: prints d1, a tab, d2 in hex and a new line.  Changes d1.
;------------------------------------------------------------------------------
print_two_words:	; from: rom_test
	bsr.w	print_hex_word                  ; d1
	bsr.w	put_tab                         ; tab
	move.w	d2,d1                           ; d2
	bsr.w	print_hex_word
	bsr.w	print_newline                   ; new line
	rts

;------------------------------------------------------------------------------
; rom_checksums: sums the even and the odd bytes from a0, d4 pairs.
;  Out: d1 the even bytes' sum (u206), d2 the odd bytes' sum (u207); a0 past the end; d0, d4 changed.
;------------------------------------------------------------------------------
rom_checksums:	; from: rom_test
	moveq	#0,d1                           ; even sum
	moveq	#0,d0
	moveq	#0,d2                           ; odd sum
rom_checksums_loop:
	move.b	(a0)+,d0                        ; even byte
	add.w	d0,d1
	move.b	(a0)+,d0                        ; odd byte
	add.w	d0,d2
	subi.l	#$1,d4                          ; the next pair
	bne.s	rom_checksums_loop
	rts

;------------------------------------------------------------------------------
; rom_crc: the CRC-16 (CCITT, polynomial $1021, from 0, high bit first) of every other byte from a0.
;  In:  a0 the first byte, d2.l the bytes.  Out: d0 the CRC; a0 kept; d1-d4, a2 changed.
;------------------------------------------------------------------------------
rom_crc:	; from: rom_test
	move.l	a0,-(sp)                        ; keep the start
	clr.w	d0                              ; the CRC from 0
	clr.w	d1
	clr.w	d3
	lea	crc16_table,a2                  ; the CRC table
rom_crc_loop:
	move.w	d0,d1
	lsl.w	#8,d0                           ; CRC shifted 8 left
	lsr.w	#8,d1                           ; its high byte
	move.b	(a0)+,d3                        ; the byte
	adda.l	#$1,a0                          ; skip the other chip's byte
	eor.b	d3,d1                           ; the table index
	lsl.w	#1,d1                           ; a word index
	move.w	0(a2,d1.w),d4                   ; the table entry
	eor.w	d4,d0                           ; into the CRC
	sub.l	#$1,d2                          ; the next byte
	bne.s	rom_crc_loop
	movea.l	(sp)+,a0                        ; the start back
	rts

;------------------------------------------------------------------------------
; colour_test: the C test.  Not on a monochrome monitor ("No color--Monochrome monitor").  Draws 16
; bars (colours 0-15) on a low resolution screen at $20000; a timer B interrupt every 2 lines sets all
; 16 colours to the next shade of a table: red, green, blue and grey ramps first, then after Space
; yellow, cyan, magenta and grey; a second Space ends it (500 delays each when unattended).  Then the
; screen and vectors are put back.  Runs at 8 MHz, cache off.  Out: $28F bit 7 set (no wait for Space
; after it).  Changes d0-d3, d6, a0, a2, $49E, $4D0, $4DE, $4FC, $500, $21A.
;------------------------------------------------------------------------------
colour_test:	; from: read_command_line
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.b	#$3,d0
	cmpi.b	#$2,d0                          ; high?
	bne.s	colour_test_colour_monitor      ; no
	lea	msg_no_colour_monochrome,a5     ; "No color--Monochrome monitor"
	bsr.w	print_string
	rts
colour_test_colour_monitor:
	move.b	$ff8e21,scratch_long.w          ; Mega STE cache and CPU speed, keep the cache/speed setting
	move.b	#$0,$ff8e21                     ; Mega STE cache and CPU speed, 8 MHz, cache off
	move.w	$ffff8240.w,saved_colour0.w     ; palette 0, keep colour 0
	movea.l	#$20000,a0                      ; clear the screen at $20000
colour_test_clear_screen:
	clr.l	(a0)+
	cmpa.l	#$28000,a0                      ; 32K
	bne.s	colour_test_clear_screen
	movea.l	#$20000,a0                      ; the screen's top
	move.l	#$c7,d0                         ; 200 lines
	moveq	#0,d1                           ; from line 0
colour_test_draw_line:
	moveq	#1,d2                           ; colour 1 first
	add.l	#$28,d1                         ; 80 pixels of colour 0 at the left of each line
colour_test_draw_bar:
	clr.l	d3                              ; plane 0
colour_test_draw_plane:
	btst	d3,d2                           ; this plane in the colour?
	beq.s	colour_test_next_plane          ; no
	move.w	#$ffff,0(a0,d1.w)               ; 16 pixels set in it
colour_test_next_plane:
	addq.w	#2,d1                           ; the next word
	addq.w	#1,d3                           ; the next plane
	cmpi.b	#$4,d3                          ; 4 planes
	bne.s	colour_test_draw_plane
	addq.w	#1,d2                           ; the next colour
	cmpi.w	#$10,d2                         ; to 15
	bne.s	colour_test_draw_bar
	dbra	d0,colour_test_draw_line        ; the next line
	bsr.w	save_screen_settings            ; keep the screen address and colour 0
	move.b	#$2,$ffff8201.w                 ; video base high, the screen at $20000
	clr.b	$ffff8203.w                     ; video base mid
	move.w	#$0,$ffff8260.w                 ; shift mode, low resolution
	move.l	$70.w,saved_vbl_vector.w        ; keep the VBL vector
	move.l	$120.w,saved_vector.w           ; MFP timer B, keep the timer B vector
	move.l	#vbl_handler,$70.w              ; VBL vector, a VBL routine that clears $294
	movea.l	#$fffffa01,a0                   ; the MFP
	clr.b	6(a0)                           ; no timer A, RS232 or DMA interrupts
	move.b	#$40,8(a0)                      ; only the keyboard/MIDI interrupt of IERB
	move.b	#$2,$20(a0)                     ; timer B: every 2 lines
	move.b	#$8,$1a(a0)                     ; counting display enable ends
	move.l	#colour_test_timer_b,$120.w     ; MFP timer B, the colour change routine
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_enable_interrupt            ; enable it
	move.w	#$2200,sr                       ; IPL 2: VBLs on
	clr.w	colour_test_mode.w              ; no Space yet
	move.b	mode_flags.w,d0                 ; unattended?
	andi.b	#$38,d0
	bne.s	colour_test_unattended          ; yes: no keys
colour_test_wait_space:
	bsr.w	get_key                         ; wait for a key
	cmpi.w	#$20,d0                         ; Space?
	bne.s	colour_test_wait_space          ; no
	addi.w	#$1,colour_test_mode.w          ; count it
	cmpi.w	#$2,colour_test_mode.w          ; the second ends the test
	bne.s	colour_test_wait_space
	bra.s	colour_test_end
colour_test_unattended:
	move.w	#$1f4,d1                        ; 500 delays
colour_test_unattended_wait:
	bsr.w	delay
	dbra	d1,colour_test_unattended_wait
colour_test_end:
	move.w	#$2400,sr                       ; IPL 4
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_disable_interrupt           ; disable it
	bsr.w	video_setup                     ; the normal screen set-up
	move.l	saved_vbl_vector.w,$70.w        ; the VBL vector back
	move.l	saved_vector.w,$120.w           ; MFP timer B, the timer B vector back
	bsr.w	ste_scroll_test                 ; the screen back
	bset	#$7,mode_flags.w                ; the test waited for its own key
	move.b	scratch_long.w,$ff8e21          ; Mega STE cache and CPU speed, the cache/speed setting back
	rts

;------------------------------------------------------------------------------
; save_screen_settings: keeps the screen address in $4DE.l and colour 0 in $49E.  Changes d0.
;------------------------------------------------------------------------------
save_screen_settings:	; from: colour_test, ste_scroll_test
	clr.l	saved_video_base.w
	move.b	$ffff8201.w,d0                  ; video base high, high byte
	lsl.w	#8,d0
	move.b	$ffff8203.w,d0                  ; video base mid, middle byte
	lsl.l	#8,d0
	move.b	$ffff820d.w,d0                  ; video base low, low byte
	move.l	d0,saved_video_base.w           ; kept
	move.w	$ffff8240.w,saved_colour0.w     ; palette 0, colour 0
	rts

;------------------------------------------------------------------------------
; restore_medium_screen: after a VBL sets medium resolution, the screen address from $4DE, colour 0 from
; $49E and colour 3 to $666.  Changes d6.
;------------------------------------------------------------------------------
restore_medium_screen:	; from: ste_scroll_test
	move.w	#$1,vbl_flag.w                  ; set; the VBL clears it
	move.w	sr,d6                           ; keep the IPL
	move.w	#$2200,sr                       ; IPL 2: VBLs on
restore_medium_screen_wait_vbl:
	cmpi.b	#$0,vbl_flag.w                  ; the VBL yet?
	bne.s	restore_medium_screen_wait_vbl  ; no
	move.b	#$1,$ffff8260.w                 ; shift mode, medium resolution
	move.b	saved_video_base+1.w,$ffff8201.w ; video base high, the screen address back
	move.b	saved_video_base+2.w,$ffff8203.w ; video base mid
	move.b	saved_video_base+3.w,$ffff820d.w ; video base low
	move.w	saved_colour0.w,$ffff8240.w     ; palette 0, colour 0 back
	move.w	#$666,$ffff8246.w               ; palette 3, colour 3 grey
	move.w	d6,sr                           ; IPL back
	rts

;------------------------------------------------------------------------------
; colour_test_timer_b: the colour test's timer B routine (every 2 lines): until the 69th of the frame,
; waits a little and sets all 16 colours to the next shade of the table ($2414, or $249E after Space).
; $294 counts the interrupts (the VBL clears it), $296 is the offset of the next shade.
;------------------------------------------------------------------------------
colour_test_timer_b:	; from: colour_test
	movem.l	d0-d1/a0,-(sp)
	cmpi.b	#$44,vbl_flag.w                 ; past the 68th?
	bgt.s	colour_test_timer_b_count       ; yes: no change
	cmpi.b	#$0,vbl_flag.w                  ; the first of the frame?
	bne.s	colour_test_timer_b_band
	clr.b	colour_bar_index.w              ; yes: the first shade
colour_test_timer_b_band:
	moveq	#30,d0                          ; a short wait
colour_test_timer_b_wait:
	dbra	d0,colour_test_timer_b_wait
	movea.l	#colour_bars_ste_rgb,a0         ; red, green, blue and grey
	cmpi.w	#$0,colour_test_mode.w          ; Space pressed?
	beq.s	colour_test_timer_b_set         ; no
	movea.l	#colour_bars_ste_cmy,a0         ; yellow, cyan, magenta and grey
colour_test_timer_b_set:
	moveq	#0,d0
	move.b	colour_bar_index.w,d0           ; the shade offset
	move.w	0(a0,d0.w),d1                   ; the shade
	movea.l	#$ffff8240,a0                   ; to all 16 colours
	move.w	d1,(a0)+                        ; colour 0
	move.w	d1,(a0)+                        ; colour 1
	move.w	d1,(a0)+                        ; colour 2
	move.w	d1,(a0)+                        ; colour 3
	move.w	d1,(a0)+                        ; colour 4
	move.w	d1,(a0)+                        ; colour 5
	move.w	d1,(a0)+                        ; colour 6
	move.w	d1,(a0)+                        ; colour 7
	move.w	d1,(a0)+                        ; colour 8
	move.w	d1,(a0)+                        ; colour 9
	move.w	d1,(a0)+                        ; colour 10
	move.w	d1,(a0)+                        ; colour 11
	move.w	d1,(a0)+                        ; colour 12
	move.w	d1,(a0)+                        ; colour 13
	move.w	d1,(a0)+                        ; colour 14
	move.w	d1,(a0)+                        ; colour 15
	addq.b	#2,colour_bar_index.w           ; the next shade
colour_test_timer_b_count:
	movea.l	#$fffffa01,a0                   ; the MFP
	bclr	#$0,$e(a0)                      ; timer B in service ends
	addq.b	#1,vbl_flag.w                   ; count the interrupt
	movem.l	(sp)+,d0-d1/a0
	rte

;------------------------------------------------------------------------------
; colour_bars_ste_rgb: one colour a line for the colour test (C) screen. Its Timer B handler
; at $2398 sets all 16 palette registers to the word at offset ($296) and adds 2 each line, for
; 69 lines; it uses this table while $4d0 is 0, colour_bars_ste_cmy otherwise. Four ramps - red, green,
; blue and white - each a black line and then the 16 STE levels in brightness order
; (0,8,1,9,...,7,F); one black word at the end.
;------------------------------------------------------------------------------
colour_bars_ste_rgb:	; from: colour_test_timer_b
	dc.w	$0000,$0000,$0800,$0100,$0900,$0200,$0a00,$0300
	dc.w	$0b00,$0400,$0c00,$0500,$0d00,$0600,$0e00,$0700
	dc.w	$0f00,$0000,$0000,$0080,$0010,$0090,$0020,$00a0
	dc.w	$0030,$00b0,$0040,$00c0,$0050,$00d0,$0060,$00e0
	dc.w	$0070,$00f0,$0000,$0000,$0008,$0001,$0009,$0002
	dc.w	$000a,$0003,$000b,$0004,$000c,$0005,$000d,$0006
	dc.w	$000e,$0007,$000f,$0000,$0000,$0888,$0111,$0999
	dc.w	$0222,$0aaa,$0333,$0bbb,$0444,$0ccc,$0555,$0ddd
	dc.w	$0666,$0eee,$0777,$0fff,$0000

;------------------------------------------------------------------------------
; colour_bars_ste_cmy: as colour_bars_ste_rgb, with cyan, yellow, magenta and white ramps.
;------------------------------------------------------------------------------
colour_bars_ste_cmy:	; from: colour_test_timer_b
	dc.w	$0000,$0000,$0088,$0011,$0099,$0022,$00aa,$0033
	dc.w	$00bb,$0044,$00cc,$0055,$00dd,$0066,$00ee,$0077
	dc.w	$00ff,$0000,$0000,$0880,$0110,$0990,$0220,$0aa0
	dc.w	$0330,$0bb0,$0440,$0cc0,$0550,$0dd0,$0660,$0ee0
	dc.w	$0770,$0ff0,$0000,$0000,$0808,$0101,$0909,$0202
	dc.w	$0a0a,$0303,$0b0b,$0404,$0c0c,$0505,$0d0d,$0606
	dc.w	$0e0e,$0707,$0f0f,$0000,$0000,$0888,$0111,$0999
	dc.w	$0222,$0aaa,$0333,$0bbb,$0444,$0ccc,$0555,$0ddd
	dc.w	$0666,$0eee,$0777,$0fff,$0000

;------------------------------------------------------------------------------
; keyboard_test: the K test.  Resets the keyboard (reset_keyboard_and_check); a failure gives Fail.
; Unattended it ends there with Pass.  Otherwise draws the keyboard (U.S. or European, from the ROM's
; country) and the mouse, all inverse: a key pressed is shown plain until it is let go (with a click)
; and its name is added to a list below; mouse buttons are plain while held and the arrows plain while
; the mouse moves.  Shift Esc ends it, setting $28F bit 7.  Changes every data register, a0, a5.
;------------------------------------------------------------------------------
keyboard_test:	; from: read_command_line
	movea.l	#msg_keyboard_test,a5           ; "Keyboard test"
	bsr.w	show_status                     ; on the status line
	bsr.w	reset_keyboard_and_check        ; reset the keyboard
	tst.w	d0                              ; failed?
	bne.s	keyboard_test_fail              ; yes
	move.b	mode_flags.w,d1                 ; unattended?
	andi.b	#$38,d1
	beq.s	keyboard_test_screen            ; no: the interactive part
	tst.w	d0                              ; (already known to be 0)
	bne.s	keyboard_test_fail
	lea	msg_pass,a5                     ; "Pass"
	bra.s	keyboard_test_print_result
keyboard_test_fail:
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
keyboard_test_print_result:
	bsr.w	show_result                     ; print the result
	rts
keyboard_test_screen:
	bsr.w	clear_screen                    ; clear the screen
	move.w	#$0,key_list_column.w           ; the key name list at column 0
	move.w	#$10,key_list_row.w             ; row 16
	move.w	#$10,scroll_top.w
	move.b	#$ff,us_keyboard.w              ; U.S. layout
	tst.b	$e0001d                         ; the ROM's os_conf low byte (country and PAL)
	beq.s	keyboard_test_layout_text       ; 0: U.S.
	clr.b	us_keyboard.w                   ; else European
keyboard_test_layout_text:
	bclr	#$4,cursor_flags.w              ; plain
	lea	msg_european_keyboard,a5        ; "European keyboard (U.K. keytops shown)"
	tst.b	us_keyboard.w                   ; U.S.?
	beq.s	keyboard_test_print_layout      ; no
	lea	msg_us_keyboard,a5              ; "U.S. keyboard"
keyboard_test_print_layout:
	bsr.w	print_string
	lea	msg_shift_esc_to_exit,a5        ; "Hit shift Esc to exit"
	bsr.w	print_string
	bset	#$4,cursor_flags.w              ; inverse
	moveq	#1,d2                           ; from scan code 1
keyboard_test_draw_keys:
	bsr.w	draw_key                        ; draw the key
	addi.b	#$1,d2                          ; the next scan code
	cmpi.b	#$73,d2                         ; to $72
	bne.s	keyboard_test_draw_keys
	moveq	#58,d0                          ; column 58
	moveq	#4,d1                           ; row 4
	bsr.w	set_cursor
	lea	msg_mouse,a5                    ; "MOUSE"
	bsr.w	print_string
	bsr.w	draw_mouse_left_button          ; "L"
	bsr.w	draw_mouse_right_button         ; "R"
	bsr.w	draw_mouse_left_arrow           ; left arrow
	bsr.w	draw_mouse_right_arrow          ; right arrow
	bsr.w	draw_mouse_up_arrow             ; up arrow
	bsr.w	draw_mouse_down_arrow           ; down arrow
keyboard_test_loop:
	bsr.w	key_waiting                     ; a key pressed?
	tst.w	d0
	bne.s	keyboard_test_key_down          ; yes
	bsr.w	keyboard_test_mouse             ; show the mouse
	movea.l	release_ring_read.w,a0          ; the key releases buffer
	cmpa.l	release_ring_write.w,a0         ; anything in it?
	beq.s	keyboard_test_loop              ; no
	move.b	(a0)+,d2                        ; a released key
	andi.b	#$7f,d2                         ; its scan code
	cmpa.l	#$48a,a0                        ; the buffer's end?
	bne.w	keyboard_test_release_next
	movea.l	#$482,a0                        ; wrap to its start
keyboard_test_release_next:
	move.l	a0,release_ring_read.w          ; taken
	bset	#$4,cursor_flags.w              ; inverse
	bsr.w	draw_key                        ; draw the key up
	bra.s	keyboard_test_loop
keyboard_test_key_down:
	bsr.w	get_key                         ; read it: d0 ASCII, d1 scan code
	bsr.w	keyboard_key_click              ; a click
	cmpi.b	#$1b,d0                         ; Esc?
	bne.s	keyboard_test_show_key          ; no
	btst	#$7,shift_held.w                ; with Shift?
	beq.w	keyboard_test_show_key          ; no
	bclr	#$4,cursor_flags.w              ; plain
	bset	#$7,mode_flags.w                ; the test waited for its own key
	rts
keyboard_test_show_key:
	bclr	#$4,cursor_flags.w              ; plain
	move.b	d1,d2                           ; the scan code
	bsr.w	draw_key                        ; draw the key down
	bset	#$4,cursor_flags.w              ; inverse
	andi.w	#$ff,d2
	cmpi.b	#$1c,d2                         ; Return?
	bne.w	keyboard_test_not_return
	lea	msg_last_key_return,a5          ; "RT"
	bra.w	keyboard_test_print_name
keyboard_test_not_return:
	cmpi.b	#$72,d2                         ; keypad Enter?
	bne.w	keyboard_test_not_enter
	lea	msg_last_key_enter,a5           ; "ENTER"
	bra.w	keyboard_test_print_name
keyboard_test_not_enter:
	cmpi.b	#$39,d2                         ; Space?
	bne.w	keyboard_test_key_name
	lea	msg_last_key_space,a5           ; "SPACE"
	bra.w	keyboard_test_print_name
keyboard_test_key_name:
	lsl.w	#2,d2                           ; the scan code's name
	lea	keytop_texts,a0                 ; the key names
	movea.l	0(a0,d2.w),a5
keyboard_test_print_name:
	move.w	key_list_row.w,d1               ; the list's place
	move.w	key_list_column.w,d0
	bsr.w	set_cursor
	bsr.w	print_string                    ; the name (inverse)
	bsr.w	print_space                     ; and a space
	move.w	cursor_column.w,key_list_column.w ; the list's next place
	move.w	cursor_row.w,key_list_row.w
	bra.w	keyboard_test_loop              ; the next key

;------------------------------------------------------------------------------
; keyboard_test_mouse: shows the last mouse packet: the buttons plain while held, an arrow plain for
; each direction moved; 5 calls with no packet after a move turn the arrows inverse again.
;  In:  $495 the packet header (bit 1 left, bit 0 right button), $237 x and $236 y movement.
;  Changes d0, d1, a0, a5, $298, $286.
;------------------------------------------------------------------------------
keyboard_test_mouse:	; from: keyboard_test
	tst.b	ikbd_packet_header.w            ; a packet?
	beq.w	keyboard_test_mouse_idle        ; no
	bset	#$4,cursor_flags.w              ; inverse
	btst	#$0,ikbd_packet_header.w        ; right button?
	beq.s	keyboard_test_mouse_right       ; no
	bclr	#$4,cursor_flags.w              ; plain
keyboard_test_mouse_right:
	bsr.w	draw_mouse_right_button         ; "R"
	bset	#$4,cursor_flags.w              ; inverse
	btst	#$1,ikbd_packet_header.w        ; left button?
	beq.s	keyboard_test_mouse_left        ; no
	bclr	#$4,cursor_flags.w              ; plain
keyboard_test_mouse_left:
	bsr.w	draw_mouse_left_button          ; "L"
	tst.b	ikbd_data_second.w              ; x movement?
	beq.s	keyboard_test_mouse_y           ; no
	bclr	#$4,cursor_flags.w              ; plain
	btst	#$7,ikbd_data_second.w          ; left?
	beq.s	keyboard_test_mouse_right_move  ; no
	bsr.w	draw_mouse_left_arrow           ; the left arrow
	bset	#$0,test_index_byte.w           ; lit
	bra.s	keyboard_test_mouse_y
keyboard_test_mouse_right_move:
	bsr.w	draw_mouse_right_arrow          ; the right arrow
	bset	#$1,test_index_byte.w           ; lit
keyboard_test_mouse_y:
	clr.b	ikbd_data_second.w              ; x taken
	tst.b	ikbd_data_first.w               ; y movement?
	beq.s	keyboard_test_mouse_done        ; no
	bclr	#$4,cursor_flags.w              ; plain
	btst	#$7,ikbd_data_first.w           ; up?
	bne.s	keyboard_test_mouse_up          ; yes
	bsr.w	draw_mouse_down_arrow           ; the down arrow
	bset	#$3,test_index_byte.w           ; lit
	bra.s	keyboard_test_mouse_done
keyboard_test_mouse_up:
	bsr.w	draw_mouse_up_arrow             ; the up arrow
	bset	#$2,test_index_byte.w           ; lit
keyboard_test_mouse_done:
	clr.b	ikbd_data_first.w               ; y taken
	clr.b	ikbd_packet_header.w            ; packet taken
	move.b	#$5,timer_irq_flags.w           ; 5 calls before the arrows go out
	rts
keyboard_test_mouse_idle:
	tst.b	test_index_byte.w               ; arrows lit?
	beq.w	keyboard_test_mouse_exit        ; no
	subi.b	#$1,timer_irq_flags.w           ; 5 calls yet?
	bne.w	keyboard_test_mouse_exit        ; no
	bset	#$4,cursor_flags.w              ; inverse
	btst	#$0,test_index_byte.w           ; left lit?
	beq.w	keyboard_test_idle_right
	bsr.w	draw_mouse_left_arrow           ; inverse again
keyboard_test_idle_right:
	btst	#$1,test_index_byte.w           ; right lit?
	beq.w	keyboard_test_idle_up
	bsr.w	draw_mouse_right_arrow          ; inverse again
keyboard_test_idle_up:
	btst	#$2,test_index_byte.w           ; up lit?
	beq.w	keyboard_test_idle_down
	bsr.w	draw_mouse_up_arrow             ; inverse again
keyboard_test_idle_down:
	btst	#$3,test_index_byte.w           ; down lit?
	beq.w	keyboard_test_idle_clear
	bsr.w	draw_mouse_down_arrow           ; inverse again
keyboard_test_idle_clear:
	clr.b	test_index_byte.w               ; none lit
keyboard_test_mouse_exit:
	rts

;------------------------------------------------------------------------------
; draw_mouse_right_button: "R" at column 61, row 6.  Changes d0, d1.
;------------------------------------------------------------------------------
draw_mouse_right_button:	; from: keyboard_test, keyboard_test_mouse
	moveq	#61,d0                          ; column 61
	moveq	#6,d1                           ; row 6
	bsr.w	set_cursor
	move.b	#$52,d1                         ; 'R'
	bsr.w	put_char
	rts

;------------------------------------------------------------------------------
; draw_mouse_left_button: "L" at column 59, row 6.  Changes d0, d1.
;------------------------------------------------------------------------------
draw_mouse_left_button:	; from: keyboard_test, keyboard_test_mouse
	moveq	#59,d0                          ; column 59
	moveq	#6,d1                           ; row 6
	bsr.w	set_cursor
	move.b	#$4c,d1                         ; 'L'
	bsr.w	put_char
	rts

;------------------------------------------------------------------------------
; draw_mouse_left_arrow: the left arrow (character 4) at column 58, row 10.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
draw_mouse_left_arrow:	; from: keyboard_test, keyboard_test_mouse
	moveq	#58,d0                          ; column 58
	moveq	#10,d1                          ; row 10
	bsr.w	set_cursor
	lea	keytop_left_arrow,a5            ; the left arrow
	bsr.w	print_string
	rts

;------------------------------------------------------------------------------
; draw_mouse_right_arrow: the right arrow (character 3) at column 62, row 10.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
draw_mouse_right_arrow:	; from: keyboard_test, keyboard_test_mouse
	moveq	#62,d0                          ; column 62
	moveq	#10,d1                          ; row 10
	bsr.w	set_cursor
	lea	keytop_right_arrow,a5           ; the right arrow
	bsr.w	print_string
	rts

;------------------------------------------------------------------------------
; draw_mouse_down_arrow: the down arrow (character 2) at column 60, row 12.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
draw_mouse_down_arrow:	; from: keyboard_test, keyboard_test_mouse
	moveq	#60,d0                          ; column 60
	moveq	#12,d1                          ; row 12
	bsr.w	set_cursor
	lea	keytop_down_arrow,a5            ; the down arrow
	bsr.w	print_string
	rts

;------------------------------------------------------------------------------
; draw_mouse_up_arrow: the up arrow (character 1) at column 60, row 8.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
draw_mouse_up_arrow:	; from: keyboard_test, keyboard_test_mouse
	moveq	#60,d0                          ; column 60
	moveq	#8,d1                           ; row 8
	bsr.w	set_cursor
	lea	keytop_up_arrow,a5              ; the up arrow
	bsr.w	print_string
	rts

;------------------------------------------------------------------------------
; draw_key: draws the keytop of a scan code at its place on the keyboard picture (inverse or plain as
; $2C8 bit 4 says).  Scan codes above $72, or with no place, draw nothing.  The European '#' ($2B)
; and '\' ($60) keytops are never used: the scan code has been doubled before it is compared with
; $2B00 and $6000.
;  In:  d2.b the scan code.  Changes d0, d1, a0, a5.
;------------------------------------------------------------------------------
draw_key:	; from: keyboard_test
	move.l	d2,-(sp)                        ; keep the scan code
	cmpi.b	#$72,d2                         ; above $72?
	bgt.s	draw_key_done                   ; yes: nothing
	andi.l	#$ff,d2
	lsl.b	#1,d2                           ; a word index
	lea	keyboard_layout,a0              ; the keys' places
	move.w	0(a0,d2.w),d1                   ; column in the high byte, row in the low
	beq.s	draw_key_done                   ; no place
	move.l	d2,-(sp)
	move.w	d1,d0
	andi.w	#$ff,d1                         ; row
	lsr.w	#8,d0                           ; column
	bsr.w	set_cursor                      ; the cursor there
	move.l	(sp)+,d2
	tst.b	us_keyboard.w                   ; U.S.?
	bne.s	draw_key_name                   ; yes
	cmpi.w	#$2b00,d2                       ; never true (see the header)
	beq.s	draw_key_hash
	cmpi.w	#$6000,d2                       ; never true
	beq.s	draw_key_backslash
draw_key_name:
	lsl.w	#1,d2                           ; a long index
	lea	keytop_texts,a0                 ; the key names
	movea.l	0(a0,d2.w),a5                   ; the name
	beq.s	draw_key_done                   ; no name
draw_key_print:
	bsr.w	print_string                    ; print it
draw_key_done:
	move.l	(sp)+,d2                        ; the scan code back
	rts
draw_key_hash:
	lea	keytop_hash,a5                  ; "#"
	bra.s	draw_key_print
draw_key_backslash:
	lea	keytop_backslash,a5             ; "\"
	bra.s	draw_key_print

;------------------------------------------------------------------------------
; reset_keyboard_and_check: resets the keyboard ($80,$01) and waits for its $Fx reply.  No reply: "K1
; Keyboard not responding" and $28F bit 0 set; a reply that is no $Fx: "K2 Keyboard status error"; a key
; release seen before the reply: "K0 Stuck key: " and the key's name.  On an error the keyboard
; interrupt is left disabled (K1, K2) and the background turned red.  The revision (reply low nibble + 1)
; goes in $27D.
;  Out: d0 = 0 and Z set when the keyboard answered, -1 on an error.  Changes d1, d7, a0, a5.
;------------------------------------------------------------------------------
reset_keyboard_and_check:	; from: menu_start, keyboard_test
	moveq	#6,d0                           ; the keyboard/MIDI interrupt
	bsr.w	mfp_enable_interrupt            ; enable it
	moveq	#-128,d1                        ; reset
	bsr.w	ikbd_send
	moveq	#1,d1
	bsr.w	ikbd_send
	clr.b	key_release.w                   ; no key released yet
	clr.w	kbd_iorec_head.w                ; empty the key buffer
	clr.w	kbd_iorec_tail.w
	bset	#$3,ikbd_packet_type.w          ; take the reply into the key buffer
	move.l	#$c350,d7                       ; 50000 tries
reset_keyboard_wait:
	bsr.w	key_waiting                     ; a reply?
	tst.w	d0
	bne.s	reset_keyboard_reply            ; yes
	sub.l	#$1,d7
	bne.s	reset_keyboard_wait
	lea	msg_keyboard_not_responding,a5  ; "K1 Keyboard not responding"
	bsr.w	print_string
	bra.s	reset_keyboard_failed
reset_keyboard_status_error:
	lea	msg_keyboard_status_error,a5    ; "K2 Keyboard status error"
reset_keyboard_failed:
	bset	#$0,mode_flags.w                ; no keyboard
	moveq	#6,d0                           ; the keyboard/MIDI interrupt
	bsr.w	mfp_disable_interrupt           ; disable it
reset_keyboard_fail:
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	moveq	#-1,d0                          ; failed
	rts
reset_keyboard_reply:
	bsr.w	get_key                         ; read it (d1 the byte)
	move.b	d1,keyboard_revision.w
	andi.b	#$f0,d1
	cmp.b	#$f0,d1                         ; a $Fx status byte?
	bne.s	reset_keyboard_status_error     ; no
	cmpi.b	#$f0,key_release.w              ; a key released before it?
	blt.w	reset_keyboard_stuck_key        ; yes
	andi.b	#$f,keyboard_revision.w         ; the revision
	addi.b	#$1,keyboard_revision.w         ; plus 1
	bclr	#$0,mode_flags.w                ; the keyboard works
	moveq	#0,d0
	rts
reset_keyboard_stuck_key:
	lea	msg_stuck_key,a5                ; "K0 Stuck key: "
	bsr.w	print_string
	move.b	key_release.w,d1                ; the released key
	andi.w	#$7f,d1
	lsl.w	#2,d1                           ; a long index
	lea	keytop_texts,a0                 ; the key names
	movea.l	0(a0,d1.w),a5
	bsr.w	print_string                    ; its name
	bsr.w	print_newline                   ; new line
	bra.s	reset_keyboard_fail

;------------------------------------------------------------------------------
; keyboard_key_click: a click on the sound chip (tone A with the envelope), then the volumes off.
;  Changes d7, a0-a2.
;------------------------------------------------------------------------------
keyboard_key_click:	; from: keyboard_test
	lea	$ffff8800.w,a1                  ; PSG register select
	lea	$ffff8802.w,a2                  ; PSG write data
	lea	key_click_psg_settings,a0       ; the register/value pairs
keyboard_key_click_registers:
	move.b	(a0)+,(a1)                      ; the register
	move.b	(a0)+,(a2)                      ; its value
	cmpa.l	#keyboard_layout,a0             ; all 7 pairs
	bne.s	keyboard_key_click_registers
	move.l	#$c00,d7                        ; let it sound
keyboard_key_click_hold:
	sub.l	#$1,d7
	bne.s	keyboard_key_click_hold
	bsr.w	psg_sound_off                   ; volumes off
	rts

;------------------------------------------------------------------------------
; midi_test: the M test (needs a MIDI loopback cable).  Sends every byte 0-255 out of the MIDI port 8
; times and checks each comes back.  Errors: "M0 MIDI not received", "M1 MIDI data mismatch",
; "M2 MIDI framing", "M3 MIDI parity" (its text is picked but never printed), "M4 MIDI data overrun";
; $678 keeps them.  The MIDI buffer record at $618 is set from the table at $C440.
;  Changes d0-d3, d7, a0, a1, a5, $287.
;------------------------------------------------------------------------------
midi_test:	; from: test_routines
	movea.l	#msg_testing_midi,a5            ; "Testing MIDI"
	bsr.w	show_status                     ; on the status line
	clr.b	test_errors_extra.w             ; no errors yet
	movea.l	#$618,a0                        ; the MIDI buffer record
	movea.l	#midi_buffer_records_init,a1    ; from its table
	moveq	#29,d0                          ; 30 bytes
	bsr.w	copy_bytes
	bsr.w	midi_registers                  ; a0 the record, a1 the ACIA
	move.b	#$3,0(a1)                       ; master reset
	move.b	#$95,0(a1)                      ; receive interrupt, 8 bits no parity 1 stop, divide by 16
	move.b	#$8,pass_count.w                ; 8 passes
midi_test_pass:
	moveq	#0,d2                           ; byte 0 first
midi_test_byte:
	bsr.w	midi_send                       ; send it
	bsr.w	midi_receive                    ; and read it back
	tst.b	test_errors_extra.w             ; any error?
	bne.s	midi_test_receive_error         ; yes
	cmp.b	d0,d2                           ; the same byte?
	bne.s	midi_test_mismatch              ; no
	add.b	#$1,d2                          ; the next byte
	bcc.s	midi_test_byte                  ; to 255
	subi.b	#$1,pass_count.w                ; the next pass
	bne.s	midi_test_pass
	movea.l	#msg_pass,a5                    ; "Pass"
	bsr.w	show_result                     ; print it
	rts
midi_test_receive_error:
	move.b	0(a1),d3                        ; the ACIA status
	btst	#$4,d3                          ; framing error?
	beq.s	midi_test_overrun               ; no
	bset	#$2,test_errors_extra.w         ; framing
	movea.l	#msg_midi_framing,a5            ; "M2 MIDI framing"
	bsr.w	print_string
midi_test_overrun:
	btst	#$5,d3                          ; overrun?
	beq.s	midi_test_parity                ; no
	bset	#$0,test_errors_extra.w         ; overrun
	movea.l	#msg_midi_data_overrun,a5       ; "M4 MIDI data overrun"
	bsr.w	print_string
midi_test_parity:
	btst	#$6,d3                          ; parity error?
	beq.s	midi_test_nothing               ; no
	bset	#$1,test_errors_extra.w         ; parity
	movea.l	#msg_midi_parity,a5             ; "M3 MIDI parity", not printed
midi_test_nothing:
	andi.b	#$70,d3                         ; any of the three?
	bne.s	midi_test_fail                  ; yes
	movea.l	#msg_midi_not_received,a5       ; "M0 MIDI not received"
	bsr.w	print_string
	bset	#$4,test_errors_extra.w         ; not received
	bra.s	midi_test_fail
midi_test_mismatch:
	movea.l	#msg_midi_data_mismatch,a5      ; "M1 MIDI data mismatch"
	bsr.w	print_string
	bset	#$3,test_errors_extra.w         ; mismatch
midi_test_fail:
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bsr.w	show_result                     ; print it
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	btst	#$7,$fffffc04.w                 ; MIDI ACIA control, ACIA interrupt request?
	beq.s	midi_test_exit                  ; no
	move.b	#$3,$fffffc04.w                 ; MIDI ACIA control, master reset
midi_test_exit:
	rts

;------------------------------------------------------------------------------
; midi_send: sends d2 out of the MIDI ACIA when its transmit register is empty.  Registers kept.
;------------------------------------------------------------------------------
midi_send:	; from: midi_test
	movem.l	d7/a0-a1,-(sp)
	bsr.w	midi_registers                  ; a0 the record, a1 the ACIA
midi_send_wait:
	bsr.w	midi_read_status                ; read the status
	btst	#$1,d7                          ; transmit register empty?
	beq.s	midi_send_wait                  ; no: wait
	move.b	d2,2(a1)                        ; send the byte
	movem.l	(sp)+,d7/a0-a1
	rts

;------------------------------------------------------------------------------
; midi_buffer_empty: Out: d0 = 0 when the MIDI input buffer holds a byte, -1 when it is empty;
; a0 the record, a1 the ACIA, a2/a3 changed.
;------------------------------------------------------------------------------
midi_buffer_empty:	; from: midi_receive
	bsr.w	midi_registers
	moveq	#-1,d0                          ; empty
	lea	6(a0),a2                        ; the head
	lea	8(a0),a3                        ; the tail
	cmpm.w	(a3)+,(a2)+                     ; the same?
	bne.s	midi_buffer_empty_exit          ; yes: empty
	moveq	#0,d0                           ; a byte waits
midi_buffer_empty_exit:
	rts

;------------------------------------------------------------------------------
; midi_receive: waits for a byte in the MIDI input buffer (the interrupt routine fills it) and takes it.
;  Out: d0.b the byte, or $678 bit 4 set on a timeout or an error in the status.  d2 kept; d3 changed.
;------------------------------------------------------------------------------
midi_receive:	; from: midi_test
	move.b	d2,-(sp)                        ; keep the byte sent
	move.w	#$2710,d3                       ; 10000 tries
midi_receive_wait:
	subi.w	#$1,d3
	beq.s	midi_receive_timeout            ; out of tries
	bsr.s	midi_buffer_empty               ; a byte in the buffer?
	tst.w	d0
	beq.s	midi_receive_wait               ; no
	move.b	$1c(a0),d0                      ; the status read last
	andi.b	#$70,d0                         ; framing, overrun or parity?
	bne.s	midi_receive_timeout            ; yes
	bsr.w	midi_get_input                  ; take the byte
midi_receive_exit:
	move.b	#$0,$fffffa1f.w                 ; MFP TADR, timer A data 0
	move.b	(sp)+,d2                        ; the byte sent back
	rts
midi_receive_timeout:
	bset	#$4,test_errors_extra.w         ; an error
	bra.s	midi_receive_exit

;------------------------------------------------------------------------------
; midi_put_output: (not called) puts d1 in the MIDI output buffer of the record at a0.
;  Out: C set when the buffer is full.
;------------------------------------------------------------------------------
midi_put_output:
	movem.l	d1-d2/a0-a1,-(sp)
	move.w	sr,-(sp)                        ; keep the IPL
	ori.w	#$700,sr                        ; no interrupts
	move.w	$16(a0),d2                      ; the output tail
	bsr.w	midi_output_next                ; moved on
	cmp.w	$14(a0),d2                      ; full?
	beq.s	midi_put_output_full            ; yes
	movea.l	$e(a0),a1                       ; the output buffer
	move.b	d1,0(a1,d2.w)                   ; the byte in
	move.w	d2,$16(a0)                      ; the new tail
	move.w	(sp)+,sr                        ; IPL back
	andi.b	#$fe,ccr                        ; C clear: put
	bra.s	midi_put_output_exit
midi_put_output_full:
	move.w	(sp)+,sr                        ; IPL back
	ori.b	#$1,ccr                         ; C set: full
midi_put_output_exit:
	movem.l	(sp)+,d1-d2/a0-a1
	rts

;------------------------------------------------------------------------------
; midi_get_input: takes the next byte from the MIDI input buffer of the record at a0.
;  Out: d0.b the byte and C clear, or C set when the buffer is empty.
;------------------------------------------------------------------------------
midi_get_input:	; from: midi_receive
	movem.l	d1/a0-a1,-(sp)
	move.w	sr,-(sp)                        ; keep the IPL
	ori.w	#$700,sr                        ; no interrupts
	move.w	6(a0),d1                        ; the head
	cmp.w	8(a0),d1                        ; the same as the tail?
	beq.s	midi_get_input_empty            ; yes: empty
	bsr.w	midi_input_next                 ; moved on
	movea.l	0(a0),a1                        ; the input buffer
	move.b	0(a1,d1.w),d0                   ; the byte
	move.w	d1,6(a0)                        ; the new head
	move.w	(sp)+,sr                        ; IPL back
	andi.b	#$fe,ccr                        ; C clear: a byte
	bra.s	midi_get_input_exit
midi_get_input_empty:
	move.w	(sp)+,sr                        ; IPL back
	ori.b	#$1,ccr                         ; C set: empty
midi_get_input_exit:
	movem.l	(sp)+,d1/a0-a1
	rts

;------------------------------------------------------------------------------
; midi_input_next: moves the input index d1 on one, wrapping at the buffer size.
;------------------------------------------------------------------------------
midi_input_next:	; from: midi_get_input
	addq.w	#1,d1
	cmp.w	4(a0),d1                        ; past the end?
	bcs.w	midi_input_next_exit
	moveq	#0,d1                           ; back to 0
midi_input_next_exit:
	rts

;------------------------------------------------------------------------------
; midi_output_next: moves the output index d2 on one, wrapping at the buffer size.
;------------------------------------------------------------------------------
midi_output_next:	; from: midi_put_output
	addq.w	#1,d2
	cmp.w	$12(a0),d2                      ; past the end?
	bcs.w	midi_output_next_exit
	moveq	#0,d2                           ; back to 0
midi_output_next_exit:
	rts

;------------------------------------------------------------------------------
; midi_registers: Out: a0 the MIDI buffer record ($618), a1 the MIDI ACIA control register.
;------------------------------------------------------------------------------
midi_registers:	; from: keyboard_setup, acia_interrupt, midi_test, midi_send, midi_buffer_empty
	movea.l	#$618,a0                        ; the MIDI buffer record
	movea.l	#$fffffc04,a1                   ; the MIDI ACIA
	rts

;------------------------------------------------------------------------------
; midi_read_status: Out: d7 the MIDI ACIA status, also kept at offset $1C of the record.
;------------------------------------------------------------------------------
midi_read_status:	; from: acia_service, midi_send
	move.b	0(a1),d7                        ; the status
	move.b	d7,$1c(a0)                      ; kept in the record
	rts

;------------------------------------------------------------------------------
; rs232_test: the S test (needs the RS232 loopback connector: DTR to RI and DCD, RTS to CTS, TxD to
; RxD).  At 8 MHz, cache off, with RS232 keys ignored:
;  1 DTR and RTS are pulsed and the RI, DCD and CTS interrupts must clear their bits in $208
;  2 a text is sent and read back polled at 19200 bps, then $55,$AA at each rate 300-19200 bps (the $00
;    after them ends the string, so $FF,$E5,$D1 are never sent); an error prints the rate
;  3 bytes 1-255 go out and in by the transmit/receive interrupts at 19200 bps
;  4 a transmit underrun and a receive overrun must raise the error interrupts
; The errors are kept in $676 (bits 0-7) and $677 (bits 0-4 printed as S6, S9, SA, SB; bits 6 and 7,
; the error interrupts, give Fail with no text) and printed from the table of "S0".."SC" texts.
; Ends at 16 MHz with the cache on, whatever it was before.  Changes d0-d7, a0, a5, $287-$28A.
;------------------------------------------------------------------------------
rs232_test:	; from: test_routines
	clr.b	test_errors.w                   ; no errors yet
	clr.b	test_errors_high.w
	movea.l	#msg_testing_rs232_loopback,a5  ; "Testing RS232 loopback"
	bsr.w	show_status                     ; on the status line
	move.b	#$0,$ff8e21                     ; Mega STE cache and CPU speed, 8 MHz, cache off
	move.b	mode_flags.w,-(sp)              ; keep the flags
	bset	#$1,mode_flags.w                ; RS232 keys ignored
	lea	$ffff8802.w,a0                  ; PSG write data
	move.b	#$7,$ffff8800.w                 ; PSG register select, sound chip register 7
	move.b	#$c0,(a0)                       ; ports A and B output
	move.b	#$e,$ffff8800.w                 ; PSG register select, register 14, port A
	move.b	#$18,(a0)                       ; DTR and RTS off
	bset	#$6,interrupt_events.w          ; wait for the RI interrupt
	moveq	#14,d0                          ; RI
	bsr.w	mfp_enable_interrupt            ; enable it
	bclr	#$4,(a0)                        ; DTR on
	bsr.w	delay
	btst	#$6,interrupt_events.w          ; the interrupt cleared it?
	beq.s	rs232_test_dcd                  ; yes
	bset	#$0,test_errors_high.w          ; "S9 RS232 RI-DTR not connected"
rs232_test_dcd:
	moveq	#14,d0                          ; RI
	bsr.w	mfp_disable_interrupt           ; disable it
	bset	#$4,(a0)                        ; DTR off
	bset	#$1,interrupt_events.w          ; wait for the DCD interrupt
	moveq	#1,d0                           ; DCD
	bsr.w	mfp_enable_interrupt            ; enable it
	bclr	#$4,(a0)                        ; DTR on
	bsr.w	delay
	btst	#$1,interrupt_events.w          ; the interrupt cleared it?
	beq.s	rs232_test_cts                  ; yes
	bset	#$1,test_errors_high.w          ; "SA RS232 DCD-DTR not connected"
rs232_test_cts:
	moveq	#1,d0                           ; DCD
	bsr.w	mfp_disable_interrupt           ; disable it
	bset	#$2,interrupt_events.w          ; wait for the CTS interrupt
	moveq	#2,d0                           ; CTS
	bsr.w	mfp_enable_interrupt            ; enable it
	bclr	#$3,(a0)                        ; RTS on
	bsr.w	delay
	btst	#$2,interrupt_events.w          ; the interrupt cleared it?
	beq.s	rs232_test_loopback             ; yes
	bset	#$2,test_errors_high.w          ; "SB RS232 RTS-CTS not connected"
rs232_test_loopback:
	moveq	#2,d0                           ; CTS
	bsr.w	mfp_disable_interrupt           ; disable it
	moveq	#2,d0                           ; 19200 bps
	bsr.w	rs232_setup_rate
	move.w	#$3e8,d7                        ; a short timeout
	lea	msg_no_loopback_connector,a5    ; the text "No loopback connector" as data
	bsr.w	rs232_send_text                 ; send it and read it back
	tst.b	test_errors.w                   ; an error?
	bne.w	rs232_test_fail                 ; yes: no connector
	move.b	#$9c,$28(a0)                    ; odd parity (set back to none by the rate set-up below)
	lea	rs232_test_bytes,a5             ; $55,$AA (the $00 after them ends it)
	move.l	#$7d00,d7                       ; a long timeout
	move.b	#$40,pass_count.w               ; 300 bps first
rs232_test_rate:
	move.b	pass_count.w,d0                 ; the rate's timer D data
	bsr.w	rs232_setup_rate                ; set it
	bsr.w	rs232_send_text                 ; send and read back
	tst.b	test_errors.w                   ; an error?
	beq.s	rs232_test_next_rate            ; no
	move.b	pass_count.w,d0                 ; the rate
	bsr.w	print_rs232_rate                ; print the rate
	bra.w	rs232_test_fail
rs232_test_next_rate:
	move.b	pass_count.w,d1
	lsr.b	#1,d1                           ; double the rate
	move.b	d1,pass_count.w
	tst.b	pass_count.w                    ; past 19200?
	bne.s	rs232_test_rate                 ; no
	moveq	#9,d0                           ; interrupts 9-12: transmit error, transmit empty, receive error,
                                                ;   receive full
rs232_test_enable_interrupts:
	bsr.w	mfp_enable_interrupt            ; enable it
	addq.w	#1,d0                           ; the next
	cmpi.b	#$d,d0
	bne.s	rs232_test_enable_interrupts
	moveq	#2,d0                           ; 19200 bps
	bsr.w	rs232_setup_rate
	clr.b	rs232_tx_byte.w                 ; the first byte to send
	clr.b	rs232_rx_byte.w                 ; nothing received
	clr.b	rs232_rx_status.w               ; no receive errors
	move.w	#$d2f0,d3                       ; timeout
	move.b	rs232_tx_byte.w,$2e(a0)         ; send the first; the interrupts send and read the rest
rs232_test_irq_wait:
	cmpi.b	#$ff,rs232_rx_byte.w            ; $FF received?
	beq.s	rs232_test_irq_done             ; yes
	subi.w	#$1,d3
	bne.s	rs232_test_irq_wait
	bset	#$5,test_errors.w               ; "S5 RS232 IRQ"
	moveq	#10,d0                          ; transmit empty
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#12,d0                          ; receive full
	bsr.w	mfp_disable_interrupt           ; off
	bra.w	rs232_test_fail
rs232_test_irq_done:
	bsr.w	delay
	btst	#$6,rs232_tx_status.w           ; transmit underrun seen by the error interrupt?
	bne.s	rs232_test_error_interrupts     ; yes
	bset	#$6,test_errors_high.w          ; a transmit error interrupt failure (no text)
rs232_test_error_interrupts:
	moveq	#9,d0                           ; transmit error
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#10,d0                          ; transmit empty
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#12,d0                          ; receive full
	bsr.w	mfp_disable_interrupt           ; off (receive error stays on)
rs232_test_overrun_wait_empty:
	tst.b	$2c(a0)                         ; transmit buffer empty?
	bpl.s	rs232_test_overrun_wait_empty
	move.b	#$55,$2e(a0)                    ; send $55
rs232_test_overrun_wait_full:
	btst	#$7,$2a(a0)                     ; received?
	beq.s	rs232_test_overrun_wait_full
	move.b	#$aa,$2e(a0)                    ; send $AA, which overruns the unread $55
	bsr.w	delay
	tst.b	$2e(a0)                         ; read the receive buffer
	bsr.w	delay
	btst	#$6,rs232_rx_status.w           ; overrun seen by the error interrupt?
	bne.s	rs232_test_overrun_checked      ; yes
	bset	#$7,test_errors_high.w          ; a receive error interrupt failure (no text)
rs232_test_overrun_checked:
	moveq	#11,d0                          ; receive error
	bsr.w	mfp_disable_interrupt           ; off
	tst.b	$2e(a0)                         ; empty the receiver
	tst.b	$2a(a0)
	move.b	test_errors.w,d0                ; any error?
	or.b	test_errors_high.w,d0
	bne.s	rs232_test_fail                 ; yes
	tst.b	test_errors.w
	beq.s	rs232_test_pass
rs232_test_fail:
	moveq	#0,d1                           ; from the first text
	moveq	#0,d0                           ; from bit 0
	move.b	test_errors_high.w,d2           ; $677 bits 0-4 as bits 8-12
	lsl.w	#8,d2
	move.b	test_errors.w,d2                ; $676 as bits 0-7
	lea	rs232_error_messages,a0         ; the "S" error texts
rs232_test_print_errors:
	btst	d0,d2                           ; this error?
	beq.s	rs232_test_next_error           ; no
	movea.l	0(a0,d1.w),a5                   ; the text
	bsr.w	print_string                    ; print its text
rs232_test_next_error:
	addq.w	#4,d1                           ; the next text
	addq.w	#1,d0                           ; the next bit
	cmp.w	#$d,d0                          ; 13 errors
	bne.s	rs232_test_print_errors
	bsr.w	rs232_setup                     ; the RS232 set-up back
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	bra.s	rs232_test_print_result
rs232_test_pass:
	movea.l	#msg_pass,a5                    ; "Pass"
rs232_test_print_result:
	bsr.w	show_result                     ; print the result
	move.b	(sp)+,mode_flags.w              ; the flags back
	move.w	rs232_rate.w,d0                 ; the rate chosen
	bsr.w	rs232_setup_rate                ; set it
	move.b	#$3,$ff8e21                     ; Mega STE cache and CPU speed, 16 MHz, cache on
	rts

;------------------------------------------------------------------------------
; rs232_send_text: sends the bytes of a 0-ended string out of the MFP USART, polled, and checks that each
; comes back the same.  Errors go in $676: bit 4 not received, bit 3 mismatch, bits 0-2 overrun,
; parity, framing; $677 bit 3 when the transmitter never empties.
;  In:  a5 the string, d7 the timeout.  Changes d0-d3, d6, a0.
;------------------------------------------------------------------------------
rs232_send_text:	; from: rs232_test
	lea	$fffffa01.w,a0                  ; MFP GPIP, the MFP
	move.b	$2a(a0),d0                      ; clear the receive status
	move.b	$2e(a0),d0                      ; and the receive buffer
	clr.l	d0                              ; from the first byte
rs232_send_text_byte:
	move.l	d7,d3                           ; the timeout
rs232_send_text_wait_empty:
	tst.b	$2c(a0)                         ; transmit buffer empty?
	bmi.w	rs232_send_text_send            ; yes
	subi.w	#$1,d3
	bne.s	rs232_send_text_wait_empty
	bset	#$3,test_errors_high.w          ; "S6 RS232 transmit error (68901)"
	bra.s	rs232_send_text_done
rs232_send_text_send:
	move.b	0(a5,d0.w),d1                   ; the next byte
	addq.w	#1,d0
	cmpi.b	#$0,d1                          ; the end?
	beq.s	rs232_send_text_done            ; yes
	move.b	d1,$2e(a0)                      ; send it
	move.w	d7,d3                           ; the timeout
rs232_send_text_wait_full:
	subi.w	#$1,d3
	bne.s	rs232_send_text_check
	bset	#$4,test_errors.w               ; "S0 RS232 not received"
	bra.s	rs232_send_text_byte            ; the next byte
rs232_send_text_check:
	move.b	$2a(a0),d6                      ; receive status
	bpl.s	rs232_send_text_wait_full       ; nothing yet
	bsr.w	rs232_receive_errors            ; its errors
	move.b	$2e(a0),d2                      ; the byte received
	cmp.b	d2,d1                           ; the same?
	beq.s	rs232_send_text_next
	bset	#$3,test_errors.w               ; "S1 RS232 data mismatch"
rs232_send_text_next:
	bra.s	rs232_send_text_byte
rs232_send_text_done:
	rts

;------------------------------------------------------------------------------
; rs232_receive_errors: turns the MFP receive status d6 into $676 bits: framing bit 2, parity bit 1,
; overrun bit 0.
;------------------------------------------------------------------------------
rs232_receive_errors:	; from: rs232_send_text
	btst	#$4,d6                          ; framing error?
	beq.s	rs232_receive_errors_parity
	bset	#$2,test_errors.w               ; "S2 RS232 framing"
rs232_receive_errors_parity:
	btst	#$5,d6                          ; parity error?
	beq.s	rs232_receive_errors_overrun
	bset	#$1,test_errors.w               ; "S3 RS232 parity"
rs232_receive_errors_overrun:
	btst	#$6,d6                          ; overrun?
	beq.w	rs232_receive_errors_done
	bset	#$0,test_errors.w               ; "S4 RS232 data overrun"
rs232_receive_errors_done:
	rts

;------------------------------------------------------------------------------
; print_rs232_rate: prints the rate of a timer D data value ("19.2k bps" to "300 bps"); a value not
; in the table prints nothing.  In: d0.b the value.  Changes d0, d1, a0, a5.
;------------------------------------------------------------------------------
print_rs232_rate:	; from: read_command_line, rs232_test
	andi.b	#$7f,d0
	lea	rs232_rate_codes,a0             ; the values 1, 2, 4 ... $40
	clr.l	d1
print_rs232_rate_find:
	cmp.b	0(a0,d1.w),d0                   ; this one?
	beq.w	print_rs232_rate_text           ; yes
	addq.w	#1,d1
	cmp.w	#$7,d1                          ; 7 values
	bne.s	print_rs232_rate_find
	rts                                     ; not found
print_rs232_rate_text:
	lea	rs232_rate_texts,a0             ; the rate texts
	lsl.w	#2,d1                           ; a long index
	movea.l	0(a0,d1.w),a5                   ; the text
	bsr.w	print_string                    ; print it
	rts

;------------------------------------------------------------------------------
; audio_test: the A test.  "Listen for low to high sweep:": channels A, B and C of the sound chip in
; turn sweep from about 100 Hz to 14 kHz (period $4E2 down to 9, volume 12) with the LMC1992 at 0 dB and
; the sound chip mixed in, the channel's name on row 1.  Then the DMA sound test (dma_sound_test), which
; returns straight to the caller, so $28F bit 7 is never set here.  Changes d0-d7, a0-a2, a5, a6.
;------------------------------------------------------------------------------
audio_test:	; from: read_command_line
	lea	msg_listen_for_sweep,a5         ; "Listen for low to high sweep:"
	bsr.w	show_status                     ; on the status line
	bsr.w	psg_sound_off                   ; quiet
	move.l	#$4e20,d0                       ; a wait
audio_test_settle:
	dbra	d0,audio_test_settle
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write
	move.w	#$86,d0                         ; treble 0 dB
	bsr.w	lmc1992_write
	move.w	#$46,d0                         ; bass 0 dB
	bsr.w	lmc1992_write
	move.w	#$1,d0                          ; sound chip mixed with DMA sound
	bsr.w	lmc1992_write
	moveq	#0,d2                           ; channel A first
audio_test_channel:	; from: audio_test_step
	bsr.w	print_channel_name              ; its name
	moveq	#4,d7                           ; period $4E2 (d7 high byte, d6 low)
	moveq	#-30,d6

audio_test_step:	; from: check_bus_error
	bsr.w	psg_tone_soft                   ; sound the period
	move.l	#$3e8,d3                        ; a wait
audio_test_step_hold:
	dbra	d3,audio_test_step_hold
	movea.l	#psg_volume_registers,a0        ; the volume registers
	move.b	0(a0,d2.w),$ffff8800.w          ; PSG register select, this channel's
	move.b	#$0,$ffff8802.w                 ; PSG write data, off
	subq.b	#1,d6                           ; a higher tone
	bcc.s	audio_test_step_check           ; borrow?
	subq.b	#1,d7                           ; then the high byte
audio_test_step_check:
	tst.w	d7                              ; down to period 9
	bne.s	audio_test_step
	cmpi.b	#$9,d6
	bne.s	audio_test_step
	addq.b	#1,d2                           ; the next channel
	cmpi.b	#$3,d2
	blt.s	audio_test_channel
	bsr.w	psg_sound_off                   ; quiet
	bsr.w	dma_sound_test                  ; the DMA sound test (returns to this routine's caller)
	bset	#$7,mode_flags.w                ; not reached
	rts

;------------------------------------------------------------------------------
; psg_sound_off: the three sound chip volumes to 0.
;------------------------------------------------------------------------------
psg_sound_off:	; from: check_fpu, keyboard_key_click, audio_test, audio_test_step, sound_quiet
	move.b	#$8,$ffff8800.w                 ; PSG register select, channel A volume
	move.b	#$0,$ffff8802.w                 ; PSG write data, 0
	move.b	#$9,$ffff8800.w                 ; PSG register select, channel B volume
	move.b	#$0,$ffff8802.w                 ; PSG write data, 0
	move.b	#$a,$ffff8800.w                 ; PSG register select, channel C volume
	move.b	#$0,$ffff8802.w                 ; PSG write data, 0
	rts

;------------------------------------------------------------------------------
; psg_tone_soft: sounds a tone on a sound chip channel at volume 12, the others' tones off.
;  In:  d2 the channel (0-2), d7/d6 the period's high and low bytes.  Changes d3, a0-a2.
;------------------------------------------------------------------------------
psg_tone_soft:	; from: audio_test_step
	lea	$ffff8800.w,a1                  ; PSG register select
	lea	$ffff8802.w,a2                  ; PSG write data
	move.b	#$7,(a1)                        ; mixer
	movea.l	#psg_mixer_tone_only,a0         ; only this channel's tone
	move.b	0(a0,d2.w),(a2)
	movea.l	#psg_period_registers,a0        ; its period registers
	move.b	0(a0,d2.w),d3
	move.b	d3,(a1)
	move.b	d6,(a2)                         ; low byte
	addq.b	#1,d3
	move.b	d3,(a1)
	move.b	d7,(a2)                         ; high byte
	movea.l	#psg_volume_registers,a0        ; its volume register
	move.b	0(a0,d2.w),(a1)
	move.b	#$c,(a2)                        ; 12
	rts

;------------------------------------------------------------------------------
; psg_tone_loud: as psg_tone_soft at volume 15.
;  In:  d2 the channel (0-2), d7/d6 the period's high and low bytes.  Changes d3, a0-a2.
;------------------------------------------------------------------------------
psg_tone_loud:	; from: check_fpu, pass_tone, fail_sweeps
	lea	$ffff8800.w,a1                  ; PSG register select
	lea	$ffff8802.w,a2                  ; PSG write data
	move.b	#$7,(a1)                        ; mixer
	movea.l	#psg_mixer_tone_only,a0         ; only this channel's tone
	move.b	0(a0,d2.w),(a2)
	movea.l	#psg_period_registers,a0        ; its period registers
	move.b	0(a0,d2.w),d3
	move.b	d3,(a1)
	move.b	d6,(a2)                         ; low byte
	addq.b	#1,d3
	move.b	d3,(a1)
	move.b	d7,(a2)                         ; high byte
	movea.l	#psg_volume_registers,a0        ; its volume register
	move.b	0(a0,d2.w),(a1)
	move.b	#$f,(a2)                        ; 15
	rts

;------------------------------------------------------------------------------
; print_channel_name: prints "Channel A", "B" or "C" at column 0, row 1, the cursor kept.
;  In:  d2 the channel.  Registers kept.
;------------------------------------------------------------------------------
print_channel_name:	; from: audio_test
	movem.l	d0-d7,-(sp)
	lea	psg_channel_names,a6            ; the channel names
	lsl.w	#2,d2                           ; a long index
	movea.l	0(a6,d2.w),a5                   ; the name
	bsr.w	save_cursor                     ; keep the cursor
	moveq	#0,d0                           ; column 0
	moveq	#1,d1                           ; row 1
	bsr.w	set_cursor
	bsr.w	print_string                    ; print it
	bsr.w	restore_cursor                  ; the cursor back
	movem.l	(sp)+,d0-d7
	rts

;------------------------------------------------------------------------------
; dma_sound_test: the DMA sound part of the A test ("Testing DMA sound. Check waveforms with
; oscilloscope.").  The sounds are copied to $40000; each stage plays over and over until a key (Esc
; ends the test):
;  "Mono 1 kHz tone"  48 samples at 50 kHz, the master volume stepped up from -80 dB to 0 dB
;  "Stereo 1 kHz/500 Hz tones"  at 25 kHz, left rising while right falls
;  "Treble attenuation"  the treble stepped from +2 dB down to -10 dB
;  "Bass attenuation"  the bass stepped from 0 dB down to -10 dB, two sounds at 6 and 12 kHz
; The LMC1992 takes the DMA sound only.  A stage that times out prints "DMA sound timed-out" (the treble
; and bass stages do not look).  Then "DONE!" at column 66 of the status line.  The return address is
; taken off the stack into $21A at the start and the end leaves through print_at, so it returns to the
; caller's caller; the code that would put it back ($31DE) is never reached, and the GPIP 7 interrupt
; disabled here stays off.  Changes d0-d7, a0, a1, a5, $4E6, $4EA, $21A.
;------------------------------------------------------------------------------
dma_sound_test:	; from: audio_test_step
	move.l	(sp)+,scratch_long.w            ; the return address off the stack
	lea	msg_testing_dma_sound,a5        ; "Testing DMA sound. Check waveforms with oscilloscope."
	bsr.w	show_status                     ; on the status line
	moveq	#15,d0                          ; the GPIP 7 interrupt
	bsr.w	mfp_disable_interrupt           ; disable it
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write
	move.w	#$86,d0                         ; treble 0 dB
	bsr.w	lmc1992_write
	move.w	#$46,d0                         ; bass 0 dB
	bsr.w	lmc1992_write
	move.w	#$2,d0                          ; DMA sound only
	bsr.w	lmc1992_write
	lea	dma_sound_samples,a0            ; the sounds
	movea.l	#$40000,a1                      ; to $40000
	move.w	#$214,d7                        ; $215 words
dma_sound_test_copy:
	move.w	(a0)+,(a1)+
	dbra	d7,dma_sound_test_copy
	clr.w	d0                              ; (not used)
	move.w	#$1,d1                          ; (not used)
	lea	msg_mono_1khz_tone,a5           ; "Mono 1 kHz tone"
	bsr.w	print_string
dma_sound_test_mono:
	clr.w	sound_step.w                    ; the first step
dma_sound_test_mono_step:
	move.w	sound_step.w,d1
	lea	lmc_master_volume_steps,a0      ; the master volumes
	move.w	0(a0,d1.w),d0
	bsr.w	lmc1992_write
	lea	dma_sound_mono_1khz,a1          ; the mono sound
	movea.l	(a1)+,a0                        ; its address
	move.l	(a1)+,d1                        ; frames to play
	move.w	(a1)+,d0                        ; the mode: mono, 50 kHz
	bsr.w	play_dma_sound                  ; play it
	bne.w	dma_sound_test_timeout          ; timed out
	bsr.w	key_waiting                     ; a key?
	tst.w	d0
	bne.s	dma_sound_test_mono_key         ; yes
	addi.w	#$2,sound_step.w                ; the next step
	cmpi.w	#$10,sound_step.w               ; 8 steps
	bne.s	dma_sound_test_mono_step
	bra.s	dma_sound_test_mono             ; over again
dma_sound_test_mono_key:
	bsr.w	get_key                         ; read the key
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	dma_sound_test_done             ; yes: the end
	lea	msg_stereo_tones,a5             ; "Stereo 1 kHz/500 Hz tones"
	bsr.w	print_string
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write
dma_sound_test_stereo:
	clr.w	sound_step.w                    ; the first step
dma_sound_test_stereo_step:
	move.w	sound_step.w,d1
	lea	lmc_left_volume_steps,a0        ; the left volumes
	move.w	0(a0,d1.w),d0
	bsr.w	lmc1992_write
	lea	lmc_right_volume_steps,a0       ; the right volumes
	move.w	0(a0,d1.w),d0
	bsr.w	lmc1992_write
	lea	dma_sound_stereo_tones,a1       ; the stereo sound
	movea.l	(a1)+,a0                        ; its address
	move.l	(a1)+,d1                        ; frames to play
	move.w	(a1)+,d0                        ; the mode: stereo, 25 kHz
	bsr.w	play_dma_sound                  ; play it
	bne.w	dma_sound_test_timeout          ; timed out
	bsr.w	key_waiting                     ; a key?
	tst.w	d0
	bne.s	dma_sound_test_stereo_key       ; yes
	addi.w	#$2,sound_step.w                ; the next step
	cmpi.w	#$10,sound_step.w               ; 8 steps
	bne.s	dma_sound_test_stereo_step
	bra.s	dma_sound_test_stereo           ; over again
dma_sound_test_stereo_key:
	bsr.w	get_key                         ; read the key
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	dma_sound_test_done             ; yes: the end
	lea	msg_treble_attenuation,a5       ; "Treble attenuation"
	bsr.w	print_string
	clr.w	sound_step.w                    ; the first step
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write
dma_sound_test_treble_step:
	lea	lmc_treble_steps,a0             ; the treble values
	move.w	sound_step.w,d1
	move.w	0(a0,d1.w),d0
	add.w	#$80,d0                         ; the treble command
	bsr.w	lmc1992_write
	lea	dma_sound_treble,a1             ; the sound
	movea.l	(a1)+,a0                        ; its address
	move.l	(a1)+,d1                        ; frames to play
	move.w	(a1)+,d0                        ; the mode
	bsr.w	play_dma_sound                  ; play it (a timeout is not looked at)
	bsr.w	key_waiting                     ; a key?
	tst.w	d0
	bne.s	dma_sound_test_treble_key       ; yes
	addi.w	#$2,sound_step.w                ; the next step
	cmpi.w	#$14,sound_step.w               ; 10 steps
	bne.s	dma_sound_test_treble_step
	clr.w	sound_step.w                    ; over again
	bra.s	dma_sound_test_treble_step
dma_sound_test_treble_key:
	bsr.w	get_key                         ; read the key
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	dma_sound_test_done             ; yes: the end
	lea	msg_bass_attenuation,a5         ; "Bass attenuation"
	bsr.w	print_string
	clr.w	sound_step.w                    ; the first step
	clr.w	bass_sound.w                    ; the first sound
dma_sound_test_bass_step:
	lea	lmc_bass_steps,a0               ; the bass values
	move.w	sound_step.w,d1
	move.w	0(a0,d1.w),d0
	add.w	#$40,d0                         ; the bass command
	bsr.w	lmc1992_write
	move.w	bass_sound.w,d3                 ; the sound's entry
	mulu.w	#$a,d3                          ; 10 bytes each
	lea	dma_sound_bass,a1               ; the two bass sounds
	movea.l	0(a1,d3.w),a0                   ; its address
	move.l	4(a1,d3.w),d1                   ; frames to play
	move.w	8(a1,d3.w),d0                   ; the mode
	bsr.w	play_dma_sound                  ; play it (a timeout is not looked at)
	addi.w	#$1,bass_sound.w                ; the other sound
	cmpi.w	#$2,bass_sound.w                ; both sounds?
	bne.s	dma_sound_test_bass_step        ; no
	clr.w	bass_sound.w                    ; the first sound again
	addi.w	#$2,sound_step.w                ; the next step
	cmpi.w	#$14,sound_step.w               ; 10 steps
	bne.s	dma_sound_test_bass_key
	clr.w	sound_step.w                    ; over again
dma_sound_test_bass_key:
	bsr.w	key_waiting                     ; a key?
	tst.w	d0
	beq.s	dma_sound_test_bass_step        ; no
	bsr.w	get_key                         ; read it
dma_sound_test_done:	; from: dma_sound_test_restore
	lea	msg_done,a5                     ; "DONE!"
	moveq	#66,d0                          ; column 66
	moveq	#0,d1                           ; of the status line
	bra.w	show_status_at                  ; print it; returns to the caller's caller

;------------------------------------------------------------------------------
; dma_sound_test_restore: never reached (see dma_sound_test).
;------------------------------------------------------------------------------
dma_sound_test_restore:
	move.w	#$12c,d1                        ; 300 delays
dma_sound_test_restore_wait:
	bsr.w	delay
	dbra	d1,dma_sound_test_restore_wait
	move.w	#$c0,d0                         ; master volume -80 dB
	bsr.w	lmc1992_write
	moveq	#15,d0                          ; the GPIP 7 interrupt
	bsr.w	mfp_enable_interrupt            ; enable it
	move.l	scratch_long.w,-(sp)            ; the return address back
	rts
dma_sound_test_timeout:	; from: dma_sound_test
	lea	msg_dma_sound_timed_out,a5      ; "DMA sound timed-out"
	bsr.w	print_string
	bra.s	dma_sound_test_done

;------------------------------------------------------------------------------
; result_sound: the sound after a test: a short low tone when the background is not red, three rising
; sweeps (channels A, B, C) when it is (a failure).  Changes d0-d3, d6, d7, a0-a2.
;------------------------------------------------------------------------------
result_sound:	; from: menu_start, menu
	bsr.w	screen_is_red                   ; red background?
	bne.s	result_sound_pass               ; no
	bsr.w	fail_sweeps                     ; the failure sweeps
	rts
result_sound_pass:
	bsr.w	pass_tone                       ; the short tone
	rts

;------------------------------------------------------------------------------
; pass_tone: about 100 Hz on channel A at volume 15 for 100 delays, with the LMC1992 at 0 dB and the
; sound chip mixed in.  Changes d0-d3, d6, d7, a0-a2.
;------------------------------------------------------------------------------
pass_tone:	; from: result_sound
	bsr.w	pass_tone_prepare               ; (does nothing)
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write
	move.w	#$1,d0                          ; sound chip mixed with DMA sound
	bsr.w	lmc1992_write
	moveq	#0,d2                           ; channel A
	moveq	#4,d7                           ; period $4E2
	moveq	#-30,d6
	bsr.w	psg_tone_loud                   ; sound it
	move.w	#$64,d1                         ; 100 delays
pass_tone_hold:
	bsr.w	delay
	dbra	d1,pass_tone_hold
	bsr.w	sound_quiet                     ; quiet
	rts

;------------------------------------------------------------------------------
; fail_sweeps: channels A, B and C in turn sweep from period $4E2 down to 9 at volume 15, as the A test
; does.  Changes d0-d3, d6, d7, a0-a2.
;------------------------------------------------------------------------------
fail_sweeps:	; from: result_sound
	moveq	#0,d2                           ; channel A first
fail_sweeps_channel:
	moveq	#4,d7                           ; period $4E2
	moveq	#-30,d6
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write
	move.w	#$1,d0                          ; sound chip mixed with DMA sound
	bsr.w	lmc1992_write
fail_sweeps_step:
	bsr.w	psg_tone_loud                   ; sound the period
	moveq	#100,d3                         ; a wait
fail_sweeps_step_hold:
	dbra	d3,fail_sweeps_step_hold
	movea.l	#psg_volume_registers,a0        ; the volume registers
	move.b	0(a0,d2.w),$ffff8800.w          ; PSG register select, this channel's
	move.b	#$0,$ffff8802.w                 ; PSG write data, off
	subq.b	#1,d6                           ; a higher tone
	bcc.s	fail_sweeps_step_check          ; borrow?
	subq.b	#1,d7                           ; then the high byte
fail_sweeps_step_check:
	tst.w	d7                              ; down to period 9
	bne.s	fail_sweeps_step
	cmpi.b	#$9,d6
	bne.s	fail_sweeps_step
	addq.b	#1,d2                           ; the next channel
	cmpi.b	#$3,d2
	blt.s	fail_sweeps_channel
	bsr.w	sound_quiet                     ; quiet
	rts

;------------------------------------------------------------------------------
; sound_quiet: the sound chip volumes off.
;------------------------------------------------------------------------------
sound_quiet:	; from: menu, pass_tone, fail_sweeps
	bsr.w	psg_sound_off
	rts

;------------------------------------------------------------------------------
; pass_tone_prepare: does nothing.
;------------------------------------------------------------------------------
pass_tone_prepare:	; from: pass_tone
	rts

;------------------------------------------------------------------------------
; microwire_send: sends d0 to the Microwire (all 11 bits) and waits until it has gone out.
;------------------------------------------------------------------------------
microwire_send:	; from: lmc1992_write
	move.w	#$7ff,$ffff8924.w               ; Microwire mask, all 11 bits
	move.w	d0,$ffff8922.w                  ; Microwire data, the command
microwire_send_wait_data:
	tst.w	$ffff8922.w                     ; Microwire data, shifted out?
	bne.s	microwire_send_wait_data
microwire_send_wait_mask:
	cmpi.w	#$7ff,$ffff8924.w               ; Microwire mask, the mask back?
	bne.s	microwire_send_wait_mask
	rts

;------------------------------------------------------------------------------
; lmc1992_write: sends a command to the LMC1992 (address %10).
;  In:  d0 the function (bits 8-6) and value (bits 5-0).  Changes d0.
;------------------------------------------------------------------------------
lmc1992_write:                                  ; from: check_fpu, check_bus_error, audio_test, dma_sound_test,
                                                ;   dma_sound_test_restore, pass_tone, 1 more
	or.w	#$400,d0                        ; the LMC1992's address
	bra.s	microwire_send                  ; send it

;------------------------------------------------------------------------------
; play_dma_sound: plays a DMA sound frame over and over, counting the frames with timer A (event
; count on the DMA sound end of frame) and timing out after 240 timer B periods (about 5 s).
;  In:  a0 the sound (a long length, then the samples), d1.l the frames to play, d0 the sound mode.
;  Out: Z set when all the frames played, clear on a timeout.  Registers kept.  The timeout path
;  reads $1E.w where timer A's data register ($FFFFFA1F) was meant; only Z is used.
;------------------------------------------------------------------------------
play_dma_sound:	; from: dma_sound_test
	movem.l	d0-d7/a0-a6,-(sp)
	lea	$ffff8900.w,a5                  ; the DMA sound registers
	move.w	#$0,(a5)                        ; stop
	move.w	d0,$20(a5)                      ; the mode
	move.l	(a0)+,d3                        ; the length
	move.l	a0,d2                           ; the start
	add.l	d2,d3                           ; the end
	lea	$fffffa01.w,a0                  ; MFP GPIP, the MFP
	move.b	#$10,$18(a0)                    ; reset timer A
	move.b	#$10,$1a(a0)                    ; reset timer B
	andi.b	#$de,6(a0)                      ; timers A and B not enabled
	andi.b	#$de,$12(a0)                    ; and masked
	move.b	#$de,$a(a0)                     ; nothing pending for them
	ori.b	#$21,6(a0)                      ; enabled (masked: polled in IPRA)
	andi.b	#$ef,2(a0)                      ; timer A counts falling edges
	move.b	#$8,$18(a0)                     ; timer A event count mode
	subq.l	#1,d1                           ; the first count
	move.l	#$100,d6                        ; at most 256 frames a count
	cmp.l	d6,d1
	bpl.s	play_dma_sound_start
	move.l	d1,d6                           ; fewer left
play_dma_sound_start:
	move.b	d6,$fffffa1f.w                  ; MFP TADR, timer A count
	movep.l	d3,$d(a5)                       ; the end address
	asl.l	#8,d2                           ; the start address for the movep
	movep.l	d2,3(a5)                        ; the start address
	move.w	#$3,(a5)                        ; play, repeating
	move.b	#$0,$fffffa21.w                 ; MFP TBDR, timer B: 256
	move.w	#$f0,d7                         ; 240 timer B periods
	move.b	#$7,$fffffa1b.w                 ; MFP TBCR, delay mode, divide by 200
play_dma_sound_wait:
	btst	#$5,$fffffa0b.w                 ; MFP IPRA, timer A done?
	beq.s	play_dma_sound_tick             ; no
	move.b	#$df,$fffffa0b.w                ; MFP IPRA, clear it
	sub.l	d6,d1                           ; those frames played
	bne.s	play_dma_sound_more             ; more?
	move.b	#$0,$fffffa19.w                 ; MFP TACR, timer A off
	move.b	#$0,$fffffa1b.w                 ; MFP TBCR, timer B off
	move.w	#$1,$ffff8900.w                 ; stop at the end of this frame
	moveq	#0,d0                           ; Z set: done
	bra.w	play_dma_sound_exit
play_dma_sound_more:
	cmp.l	d6,d1                           ; at most a full count
	bpl.s	play_dma_sound_reload
	move.l	d1,d6                           ; fewer left
play_dma_sound_reload:
	move.b	#$0,$fffffa19.w                 ; MFP TACR, timer A off
	move.b	d6,$fffffa1f.w                  ; MFP TADR, the next count
	move.b	#$8,$fffffa19.w                 ; MFP TACR, event count mode again
play_dma_sound_tick:
	btst	#$0,$fffffa0b.w                 ; MFP IPRA, timer B period over?
	beq.s	play_dma_sound_wait             ; no
	move.b	#$fe,$fffffa0b.w                ; MFP IPRA, clear it
	subq.l	#1,d7                           ; timed out?
	bne.s	play_dma_sound_wait             ; no
	move.b	#$0,$fffffa19.w                 ; MFP TACR, timer A off
	move.b	$1e.w,d6                        ; meant to be timer A's count
	move.w	#$0,$ffff8900.w                 ; stop
	move.b	#$0,$fffffa1b.w                 ; MFP TBCR, timer B off
	move.l	#$100,d0                        ; the frames played in this count:
	sub.l	d6,d0                           ; 256 less the count left
	sub.l	d0,d1                           ; the frames left
	move.l	d1,d0                           ; Z clear (frames were left)
play_dma_sound_exit:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; timing_test: the T test, "Testing MFP, Glue timing, Video", also run once at start-up.
;  T0 the four MFP timers interrupt (and are in service); T1-T3, ten times over, the VBL, the HBL
;  and the display enable (timer B event count) each arrive while timer A runs; T4 the video
;  counter follows the screen at video bases from $1000 up to the end of RAM; T5/T6 a PSG and a
;  1772 access from RAM must not bus error.  The CPU runs at 8 MHz with no cache while it tests.
;  In: $204 the end of RAM, $238 $EA after start-up (then "Pass" is shown).  Out: $676 the error bits
;  (bit 0 T0, 1 T1, 2 T2, 3 T3, 4 T4, 5 T5/T6), the screen at $10000, 16 MHz and cache on.
;  Changes all registers, the MFP timers and their vectors ($120 left on the default timer B routine).
;------------------------------------------------------------------------------
timing_test:	; from: check_bus_error, test_routines
	lea	msg_testing_mfp_glue_video,a5   ; the title
	bsr.w	show_status                     ; on the top line
	move.b	#$0,$ff8e21                     ; Mega STE cache and CPU speed, 8 MHz, no cache
	bsr.w	delay                           ; a pause
	movea.l	#$fffffa01,a0                   ; the MFP
	clr.b	$18(a0)                         ; timer A stopped
	clr.b	$1a(a0)                         ; timer B stopped
	clr.b	$1c(a0)                         ; timers C and D stopped
	bclr	#$6,$14(a0)                     ; the ACIA interrupt masked
	move.b	#$4,$1e(a0)                     ; timer A data 4
	move.b	#$4,$20(a0)                     ; timer B data 4
	move.b	#$4,$22(a0)                     ; timer C data 4
	move.b	#$4,$24(a0)                     ; timer D data 4
	move.l	#timer_d_handler,$110.w         ; MFP timer D, the T0 interrupt routines
	move.l	#timer_c_handler,$114.w         ; MFP timer C, (each clears $286 bits)
	move.l	#timer_b_handler,$120.w         ; MFP timer B
	move.l	#timer_a_handler,$134.w         ; MFP timer A
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the ACIA status read
	move.b	$fffffc02.w,d0                  ; keyboard ACIA data, and its data, any interrupt cleared
	clr.b	test_errors.w                   ; no errors yet
	moveq	#13,d0                          ; timer A (interrupt 13)
	bsr.w	mfp_enable_interrupt            ; enabled
	moveq	#24,d1                          ; its control register
	move.b	#$7,$18(a0)                     ; running, /200
	bsr.w	check_mfp_timer                 ; interrupted and in service?
	moveq	#13,d0                          ; timer A
	bsr.w	mfp_disable_interrupt           ; disabled
	moveq	#8,d0                           ; timer B (interrupt 8)
	bsr.w	mfp_enable_interrupt            ; enabled
	moveq	#26,d1                          ; its control register
	move.b	#$7,$1a(a0)                     ; running, /200
	bsr.w	check_mfp_timer                 ; interrupted?
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_disable_interrupt           ; disabled
	moveq	#5,d0                           ; timer C (interrupt 5)
	bsr.w	mfp_enable_interrupt            ; enabled
	moveq	#28,d1                          ; timers C/D control
	move.b	#$70,$1c(a0)                    ; timer C running, /200
	bsr.w	check_mfp_timer                 ; interrupted?
	moveq	#5,d0                           ; timer C
	bsr.w	mfp_disable_interrupt           ; disabled
	moveq	#4,d0                           ; timer D (interrupt 4)
	bsr.w	mfp_enable_interrupt            ; enabled
	moveq	#28,d1                          ; timers C/D control
	move.b	#$7,$1c(a0)                     ; timer D running, /200
	bsr.w	check_mfp_timer                 ; interrupted?
	moveq	#4,d0                           ; timer D
	bsr.w	mfp_disable_interrupt           ; disabled
	bsr.w	rs232_setup                     ; timer D back as the RS232 baud clock
	tst.b	test_errors.w                   ; a timer failed?
	beq.s	timing_sync_tests               ; no
	movea.l	#msg_mfp_timer,a5               ; "T0 MFP timer"
	bsr.w	print_string                    ; shown
timing_sync_tests:
	move.b	#$a,pass_count.w                ; T1-T3 ten times
timing_sync_loop:
	move.b	#$7,d0                          ; timer A /200
	move.b	#$af,d1                         ; 175 counts: 14.2 ms
	bsr.w	start_timer_a                   ; started, $20A = 1 (the time-out flag)
	move.b	#$1,vbl_flag.w                  ; the VBL routine clears $294
	move.w	#$2200,sr                       ; VBL and MFP interrupts on
timing_vbl_first_wait:
	tst.b	vbl_flag.w                      ; the VBL came?
	beq.s	timing_vbl_period               ; yes
	tst.b	timer_a_count.w                 ; time-out flag still set? (nothing clears it here: the routine that
                                                ;   counts it down is not installed)
	bne.s	timing_vbl_first_wait           ; yes: wait on
timing_vbl_fail:
	movea.l	#msg_vertical_sync,a5           ; "T1 Vertical Sync"
	bsr.w	print_string                    ; shown
	bset	#$1,test_errors.w               ; error bit 1
	bra.w	timing_sync_next                ; on to the next round
timing_vbl_period:
	clr.b	$fffffa19.w                     ; MFP TACR, timer A stopped
	move.b	#$af,$fffffa1f.w                ; MFP TADR, 175 counts again
	move.b	#$7,$fffffa19.w                 ; MFP TACR, restarted, /200
	move.b	#$1,vbl_flag.w                  ; wait for the next VBL
	move.b	#$1,timer_a_count.w             ; time-out flag
timing_vbl_period_wait:
	tst.b	vbl_flag.w                      ; the VBL came?
	beq.s	timing_hbl_test                 ; yes: T2
	tst.b	timer_a_count.w                 ; time-out?
	bne.s	timing_vbl_period_wait          ; no: wait on
	bra.s	timing_vbl_fail                 ; yes: T1 fails
timing_hbl_test:
	move.b	#$8,$fffffa1b.w                 ; MFP TBCR, timer B: event count (display enable)
	move.b	#$1,$fffffa21.w                 ; MFP TBDR, every line
	move.l	#timer_b_count_handler,$120.w   ; MFP timer B, timer B routine: counts $208 down
	bset	#$0,$fffffa13.w                 ; MFP IMRA, timer B unmasked
	move.b	#$1,d0                          ; timer A /4
	move.b	#$f,d1                          ; 15 counts: 24 us
	move.b	#$1,interrupt_events.w          ; the HBL routine clears $208
	bsr.w	start_timer_a                   ; timer A started, time-out flag set
	move.w	#$2000,sr                       ; all interrupts on, the HBL too
timing_hbl_wait:
	tst.b	interrupt_events.w              ; the HBL came?
	beq.s	timing_de_test                  ; yes: T3
	tst.b	timer_a_count.w                 ; time-out?
	bne.s	timing_hbl_wait                 ; no: wait on
	movea.l	#msg_horizontal_sync,a5         ; "T2 Horizontal Sync"
	bset	#$2,test_errors.w               ; error bit 2
timing_print_fail:
	bsr.w	print_string                    ; the error shown
	bra.s	timing_sync_next                ; on to the next round
timing_de_fail:
	movea.l	#msg_display_enable,a5          ; "T3 Display Enable"
	bset	#$3,test_errors.w               ; error bit 3
	bra.s	timing_print_fail               ; shown
timing_de_test:
	move.w	#$2400,sr                       ; the HBL off
	clr.b	$fffffa19.w                     ; MFP TACR, timer A stopped
	move.b	#$1,interrupt_events.w          ; one timer B interrupt wanted
	move.b	#$1,timer_a_count.w             ; time-out flag
	move.b	#$d,$fffffa1f.w                 ; MFP TADR, 13 counts: 1.06 ms
	move.b	#$7,$fffffa19.w                 ; MFP TACR, timer A restarted, /200
	bset	#$0,$fffffa07.w                 ; MFP IERA, timer B interrupt on
	bset	#$5,$fffffa07.w                 ; MFP IERA, timer A interrupt on
timing_de_wait:
	tst.b	interrupt_events.w              ; timer B came (a line ended)?
	beq.s	timing_sync_next                ; yes
	tst.b	timer_a_count.w                 ; time-out?
	bne.s	timing_de_wait                  ; no: wait on
	bra.s	timing_de_fail                  ; yes: T3 fails
timing_sync_next:
	move.w	#$2400,sr                       ; the HBL off
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_disable_interrupt           ; disabled
	moveq	#13,d0                          ; timer A
	bsr.w	mfp_disable_interrupt           ; disabled
	move.l	#timer_b_handler,$120.w         ; MFP timer B, the default timer B routine back
	subi.b	#$1,pass_count.w                ; the next round
	bne.w	timing_sync_loop                ; ten done?
	lea	$ffff8201.w,a0                  ; video base high, T4: the video base and counter registers
	lea	$ffff8203.w,a1                  ; video base mid
	lea	$ffff8205.w,a2                  ; video count high
	lea	$ffff8207.w,a3                  ; video count mid
	lea	$ffff8209.w,a4                  ; video count low
	move.l	#timerb_count_lines,$120.w      ; MFP timer B, timer B routine: two more lines in $292
	move.w	#$2200,sr                       ; VBL and MFP interrupts on
	clr.l	d0                              ; the first table entry
	clr.l	d4
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	beq.w	timing_colour_line_bytes        ; no
	move.l	#$a0,d5                         ; two mono lines: 160 bytes
	bra.s	timing_counter_next_base
timing_colour_line_bytes:
	move.l	#$140,d5                        ; two colour lines: 320 bytes
timing_counter_next_base:
	lea	video_counter_test_bases,a6     ; the screen addresses to try, /256
	clr.l	d1
	move.w	0(a6,d0.w),d1                   ; the next one
	move.w	d1,d7
	lsr.w	#8,d7                           ; its 64K bank
	cmp.b	ram_top+1.w,d7                  ; past the end of RAM?
	bge.w	timing_bus_tests                ; yes: T4 done
	clr.l	counter_end.w                   ; the end address
	clr.l	counter_expected.w              ; the expected counter
	lsl.l	#8,d1                           ; the screen address
	move.l	d1,counter_expected.w           ; the counter should start there
	add.l	#$7bc0,d1                       ; the end: 198 colour lines on
	move.l	d1,counter_end.w
	move.l	counter_expected.w,d1           ; the screen address
	lsr.l	#8,d1                           ; /256 for the base registers
	move.b	#$1,vbl_flag.w                  ; wait for a VBL
timing_counter_vbl_wait:
	tst.b	vbl_flag.w
	bne.s	timing_counter_vbl_wait
	move.b	d1,(a1)                         ; base mid
	lsr.w	#8,d1
	move.b	d1,(a0)                         ; base high
	move.b	#$1,vbl_flag.w                  ; one more VBL: the new base in use
timing_counter_vbl_settle:
	tst.b	vbl_flag.w
	bne.s	timing_counter_vbl_settle
	clr.w	line_count.w                    ; no lines counted yet
	clr.l	d6                              ; the count seen last
	move.b	#$2,$fffffa21.w                 ; MFP TBDR, timer B every two lines
	move.b	#$8,$fffffa1b.w                 ; MFP TBCR, event count
	bset	#$0,$fffffa13.w                 ; MFP IMRA, timer B unmasked
	bset	#$0,$fffffa07.w                 ; MFP IERA, and enabled
timing_counter_wait_line:
	clr.l	d4
	cmp.w	line_count.w,d6                 ; two more lines gone?
	beq.s	timing_counter_wait_line        ; no: wait
	move.b	(a4),d2                         ; the video counter low
	move.b	(a3),d3                         ; mid
	move.b	(a2),d4                         ; high
	lsl.w	#8,d4                           ; made into one address
	move.b	d3,d4
	lsl.l	#8,d4
	move.b	d2,d4
	move.l	d4,scratch_long.w               ; kept for the result
	move.w	line_count.w,d6                 ; this count seen
	cmp.l	counter_expected.w,d4           ; behind where it should be?
	blt.s	timing_counter_fail             ; yes: T4 fails
	add.l	d5,counter_expected.w           ; two lines on
	cmp.l	counter_expected.w,d4           ; more than two lines on?
	bgt.s	timing_counter_fail             ; yes: T4 fails
	move.l	counter_expected.w,d1           ; the expected address
	cmp.l	counter_end.w,d1                ; at the end of the screen?
	blt.s	timing_counter_wait_line        ; no: the next two lines
	add.w	#$2,d0                          ; the next screen address
	bra.w	timing_counter_next_base
timing_counter_fail:
	lea	msg_video_counter,a5            ; "T4 Video Counter in Memory Controller"
	bsr.w	print_string                    ; shown
	bset	#$4,test_errors.w               ; error bit 4
timing_bus_tests:
	move.w	#$2400,sr                       ; the HBL off
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_disable_interrupt           ; disabled
	move.b	#$1,(a0)                        ; the screen back at $10000
	move.b	#$0,(a1)
	movea.l	$8.w,a4                         ; the bus error vector kept
	move.l	#bus_error_caught,$8.w          ; bus error vector, a bus error sets d7 and goes on
	lea	msg_psg_bus_test,a5             ; "T5 PSG Bus Test", shown on a bus error
	lea	psg_bus_test_code,a1            ; its code
	move.l	#$e,d0                          ; 15 bytes of it
	bsr.w	run_bus_test_in_ram             ; run from RAM
	lea	msg_1772_bus_test,a5            ; "T6 1772 Bus Test"
	lea	fdc_bus_test_code,a1            ; its code
	move.l	#$1c,d0                         ; 29 bytes of it
	bsr.w	run_bus_test_in_ram             ; run from RAM
	move.l	a4,$8.w                         ; the bus error vector back
	tst.b	test_errors.w                   ; any error?
	bne.s	timing_test_failed              ; yes
	cmpi.b	#$ea,startup_checks_done.w      ; the start-up run?
	bne.w	timing_test_done                ; yes: no result shown
	lea	msg_pass,a5                     ; "Pass"
	bra.s	timing_test_result
timing_test_failed:
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
timing_test_result:
	bsr.w	show_result                     ; the result shown
timing_test_done:
	bset	#$6,$fffffa15.w                 ; MFP IMRB, the ACIA interrupt unmasked
	move.b	#$3,$ff8e21                     ; Mega STE cache and CPU speed, 16 MHz, cache on
	rts

;------------------------------------------------------------------------------
; run_bus_test_in_ram: copies a short test routine to $4000 and runs it there; the bus error vector must
;  already set d7.  In: a1 the routine, d0 its length - 1, a5 the text shown if it bus errors.
;  Out: d7 -1 after a bus error, then the text shown and $676 bit 5 set.  Changes d0, d7, a0, a1.
;------------------------------------------------------------------------------
run_bus_test_in_ram:	; from: timing_test
	movea.l	#$4000,a0                       ; at $4000
	bsr.w	copy_bytes                      ; copied
	clr.l	d7                              ; no bus error yet
	movea.l	#$4000,a0
	jsr	(a0)                            ; run
	tst.w	d7                              ; a bus error?
	beq.w	run_bus_test_in_ram_done        ; no
	bsr.w	print_string                    ; the test's name shown
	bset	#$5,test_errors.w               ; error bit 5
run_bus_test_in_ram_done:
	rts

;------------------------------------------------------------------------------
; psg_bus_test_code: run from RAM by T5: one PSG register select and write.
;------------------------------------------------------------------------------
psg_bus_test_code:	; from: timing_test
	move.b	#$0,$ffff8800.w                 ; PSG register select, register 0
	move.b	#$0,$ffff8802.w                 ; PSG write data, written 0
	rts

;------------------------------------------------------------------------------
; fdc_bus_test_code: run from RAM by T6: the 1772 status register read with pauses round it.
;------------------------------------------------------------------------------
fdc_bus_test_code:	; from: timing_test
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the FDC status register
	move.w	#$20,d6                         ; a pause
fdc_bus_test_delay:
	dbra	d6,fdc_bus_test_delay
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, the 1772 read
	move.w	#$20,d6                         ; a pause
fdc_bus_test_settle:
	dbra	d6,fdc_bus_test_settle
	rts

;------------------------------------------------------------------------------
; timerb_count_lines: the timer B routine for T4: two more lines counted in $292.
;------------------------------------------------------------------------------
timerb_count_lines:	; from: timing_test
	addi.w	#$2,line_count.w                ; two lines
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, timer B served
	rte

;------------------------------------------------------------------------------
; check_mfp_timer: waits while an MFP timer runs and checks that its interrupt came and was in service
;  (the T0 routines clear $286 bit 0 always, bit 1 when the timer's in-service bit was set), then
;  stops the timer.  In: a0 $FFFFFA01, d1 the offset of its control register (24 A, 26 B, 28 C/D),
;  the timer started.  Out: $676 bit 0 set on an error.  Changes d2.
;------------------------------------------------------------------------------
check_mfp_timer:	; from: timing_test
	moveq	#-41,d2                         ; 65496 loops
	move.b	#$3,timer_irq_flags.w           ; interrupt and in-service bits to be cleared
check_mfp_timer_wait:
	dbra	d2,check_mfp_timer_wait
	tst.b	timer_irq_flags.w               ; both cleared?
	beq.s	check_mfp_timer_stop            ; yes
	bset	#$0,test_errors.w               ; error bit 0: T0
check_mfp_timer_stop:
	clr.b	0(a0,d1.w)                      ; the timer stopped
	rts

;------------------------------------------------------------------------------
; dma_port_test: the D test, "DMA Port Test", with a loopback device on the ACSI/DMA port: blocks are
;  written out (command $10) and read back 2K higher (command $08), then compared.  First one block at
;  $1000, then four blocks at each address of a table ($1000, $1800, $2000, $4000 ... $8000000) below the
;  end of RAM.  Each block's words hold their own addresses.  Errors: D0 time-out, D1 DMA count,
;  D2 data mismatch, D3 status; then "Fail at cycle:" and a red background, else "Pass".
;  Changes all registers, $4EC-$4F3, $B90, the RAM tested.
;------------------------------------------------------------------------------
dma_port_test:	; from: test_routines
	movea.l	#msg_dma_port_test,a5           ; the title
	bsr.w	show_status                     ; on the top line
	move.w	#$80,$ffff8606.w                ; DMA mode / status, FDC status
	nop
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, read: its interrupt cleared
	move.b	#$e,$ffff8800.w                 ; PSG port A
	move.b	#$27,$ffff8802.w                ; PSG write data, floppies deselected
	movea.l	dma_port_test_buffers,a3        ; the first address, $1000
	movea.l	a3,a4                           ; one block on
	adda.l	#$200,a4
	move.l	a3,dma_test_address.w           ; the transfer address
dma_port_fill_first:
	move.w	a3,d0                           ; each word its address
	move.w	d0,(a3)+
	cmpa.l	a3,a4                           ; the block filled?
	bne.s	dma_port_fill_first
	move.w	#$1,dma_block_count.w           ; one block
	move.b	#$10,dma_command.w              ; command $10: written out
	bsr.w	acsi_loopback_transfer          ; sent
	tst.b	test_errors.w                   ; an error?
	bne.w	dma_port_fail                   ; yes
	addi.l	#$800,dma_test_address.w        ; read back 2K higher
	move.b	#$8,dma_command.w               ; command $08: read back
	bsr.w	acsi_loopback_transfer          ; sent
	tst.b	test_errors.w                   ; an error?
	bne.w	dma_port_fail                   ; yes
	bsr.w	compare_dma_blocks              ; the two blocks compared
	btst	#$7,test_errors.w               ; mismatch?
	bne.w	dma_port_fail                   ; yes
	clr.b	dma_table_index.w               ; the first table entry
dma_port_next_block:
	clr.l	d0
	move.b	dma_table_index.w,d0            ; the entry
	lea	dma_port_test_buffers,a2        ; the addresses to test
	movea.l	0(a2,d0.w),a3                   ; this one
	cmpa.l	ram_top.w,a3                    ; past the end of RAM?
	bge.s	dma_port_pass                   ; yes: all done
	move.l	a3,dma_test_address.w           ; the transfer address
	movea.l	a3,a4                           ; four blocks on
	adda.l	#$800,a4
dma_port_fill_block:
	move.w	a3,d0                           ; each word its address
	move.w	d0,(a3)+
	cmpa.l	a3,a4                           ; filled?
	bne.s	dma_port_fill_block
	move.w	#$4,dma_block_count.w           ; four blocks
	move.b	#$10,dma_command.w              ; written out
	bsr.w	acsi_loopback_transfer          ; sent
	tst.b	test_errors.w                   ; an error?
	bne.s	dma_port_fail                   ; yes
	addi.l	#$800,dma_test_address          ; read back 2K higher
	move.b	#$8,dma_command.w               ; read back
	bsr.w	acsi_loopback_transfer          ; sent
	tst.b	test_errors.w                   ; an error?
	bne.s	dma_port_fail                   ; yes
	bsr.w	compare_dma_blocks              ; compared
	btst	#$7,test_errors.w               ; mismatch?
	bne.s	dma_port_fail                   ; yes
	addi.b	#$4,dma_table_index.w           ; the next entry
	cmpi.b	#$4c,dma_table_index.w          ; all 19 done?
	bne.s	dma_port_next_block             ; no
dma_port_pass:
	movea.l	#msg_pass,a5                    ; "Pass"
dma_port_result:
	bsr.w	show_result                     ; the result shown
	rts
dma_port_fail:
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bra.s	dma_port_result

;------------------------------------------------------------------------------
; acsi_loopback_transfer: one DMA transfer with the loopback device on the ACSI port.
;  In: $4EE the address, $4EC the block count, $4F2 the command: $10 write out (memory to the port),
;  $08 read in.  The command byte sent is (count - 1) * 64 + command.  Waits for the port's interrupt
;  (GPIP5), then checks the DMA address reached the end and the DMA status says no error.
;  Out: $676 cleared, then bit 0 time-out (D0), bit 1 count (D1), bit 2 status (D3).  Changes d0-d2, a0, a1, $B90.
;------------------------------------------------------------------------------
acsi_loopback_transfer:	; from: dma_port_test
	clr.b	test_errors.w                   ; no errors
	move.b	dma_test_address+3.w,$ffff860d.w ; DMA base low, the DMA address
	move.b	dma_test_address+2.w,$ffff860b.w ; DMA base mid
	move.b	dma_test_address+1.w,$ffff8609.w ; DMA base high, set
	move.w	dma_block_count.w,d0            ; the block count
	subq.w	#1,d0                           ; minus one
	lsl.b	#6,d0                           ; in bits 6-7
	or.b	dma_command.w,d0                ; and the command: the command byte
	lea	$ffff8606.w,a0                  ; DMA mode
	lea	$ffff8604.w,a1                  ; DMA data
	cmpi.b	#$8,dma_command.w               ; read in?
	bne.s	acsi_loopback_write             ; no: write out
	move.w	#$190,(a0)                      ; FIFO cleared, read direction
	move.w	#$90,(a0)                       ; sector count register
	nop
	move.w	dma_block_count.w,(a1)          ; the block count
	nop
	move.w	#$88,(a0)                       ; ACSI, first command byte
	nop
	move.w	(a1),d1                         ; status read
	move.w	d0,(a1)                         ; the command byte
	nop
	move.w	#$8,(a0)                        ; DMA on, from the port
	bra.s	acsi_loopback_started           ; wait
acsi_loopback_write:
	move.w	#$90,(a0)                       ; FIFO cleared, write direction
	move.w	#$190,(a0)                      ; sector count register
	nop
	move.w	dma_block_count.w,(a1)          ; the block count
	nop
	move.w	#$188,(a0)                      ; ACSI, first command byte
	nop
	move.w	(a1),d1                         ; status read
	move.w	d0,(a1)                         ; the command byte
	nop
	move.w	#$108,(a0)                      ; DMA on, to the port
acsi_loopback_started:
	move.w	#$1f4,d2                        ; time-out count
acsi_loopback_wait:
	subq.w	#1,d2                           ; time-out?
	beq.w	acsi_loopback_timeout           ; yes
	btst	#$5,$fffffa01.w                 ; MFP GPIP, the port's interrupt (GPIP5) low?
	bne.s	acsi_loopback_wait              ; no: wait
	clr.l	d0                              ; the end address expected
	move.w	dma_block_count.w,d0            ; blocks
	mulu.w	#$200,d0                        ; *512
	add.l	dma_test_address.w,d0           ; from the start
	clr.l	dma_address_read.w              ; the DMA address read back
	move.b	$ffff860d.w,dma_address_read+3.w ; DMA base low, low
	move.b	$ffff860b.w,dma_address_read+2.w ; DMA base mid, mid
	move.b	$ffff8609.w,dma_address_read+1.w ; DMA base high, high
	cmp.l	dma_address_read,d0             ; where it should be?
	beq.s	acsi_loopback_check_status      ; yes
	bset	#$1,test_errors.w               ; error bit 1
	movea.l	#msg_dma_count_error,a5         ; "D1 DMA count error"
	bsr.w	print_string                    ; shown
acsi_loopback_check_status:
	move.w	(a0),d0                         ; the DMA status
	andi.w	#$7,d0                          ; its three bits
	cmpi.w	#$1,d0                          ; no error only?
	beq.s	acsi_loopback_done              ; yes
	bset	#$2,test_errors.w               ; error bit 2
	lea	msg_dma_not_responding,a5       ; "D3 DMA not responding"
	bsr.w	print_string                    ; shown
acsi_loopback_done:
	move.w	#$88,(a0)                       ; ACSI register
	nop
	move.w	(a1),d1                         ; read: the interrupt cleared
	rts
acsi_loopback_timeout:
	bset	#$0,test_errors.w               ; error bit 0
	movea.l	#msg_dma_time_out,a5            ; "D0 DMA time-out"
	bsr.w	print_string                    ; shown
	bra.s	acsi_loopback_done              ; the port released

;------------------------------------------------------------------------------
; compare_dma_blocks: compares the blocks read back at $4EE with those written 2K lower.
;  In: $4EE, $4EC the block count.  Out: $676 bit 7 and "D2 DMA data mismatch" on the first difference.
;  Changes d0, a0-a2.
;------------------------------------------------------------------------------
compare_dma_blocks:	; from: dma_port_test
	movea.l	dma_test_address.w,a0           ; the blocks read back
	movea.l	a0,a1                           ; those written
	suba.l	#$800,a1
	moveq	#0,d0                           ; the length
	move.w	dma_block_count.w,d0            ; blocks
	mulu.w	#$200,d0                        ; *512
	movea.l	a0,a2                           ; the end
	adda.l	d0,a2                           ; of the blocks read back
compare_dma_blocks_loop:
	cmpm.b	(a0)+,(a1)+                     ; the same?
	bne.s	compare_dma_blocks_mismatch     ; no
	cmpa.l	a0,a2                           ; all of them?
	bne.s	compare_dma_blocks_loop         ; no
	rts
compare_dma_blocks_mismatch:
	bset	#$7,test_errors.w               ; error bit 7
	movea.l	#msg_dma_data_mismatch,a5       ; "D2 DMA data mismatch"
	bsr.w	print_string                    ; shown
	rts

;------------------------------------------------------------------------------
; printer_joystick_test: the P test, "Printer/Joystick Port test", with loopback plugs on the printer and
;  joystick ports.  P0 each printer data bit is strobed out and must read back the same; P1 data bit 7
;  must show on BUSY (GPIP0); then through the keyboard processor (joystick interrogation) data bits 7/6
;  must show as the fire buttons (J3/J4) and $F8-$FF as the joystick directions ($01-$80 wanted,
;  J0 port 0 low nibble, J1 port 1 high nibble); J2 when the keyboard processor does not answer.
;  Out: $676 P0 bits, $677 P1 bits, $678 fire bits, $679 direction bits, the result shown.
;  Changes all registers, PSG registers 7, 14, 15.
;------------------------------------------------------------------------------
printer_joystick_test:	; from: test_routines
	movea.l	#msg_printer_joystick_test,a5   ; the title
	bsr.w	show_status                     ; on the top line
	move.w	#$2700,sr                       ; no interrupts
	clr.b	test_errors.w                   ; no errors
	clr.b	test_errors_high.w
	clr.b	test_errors_extra.w
	clr.b	test_errors_last.w
	lea	$ffff8802.w,a0                  ; PSG data
	lea	$ffff8800.w,a1                  ; PSG select
	move.b	#$1,d0                          ; data bit 0 first
printer_data_loop:
	move.b	#$7,(a1)                        ; PSG mixer
	move.b	#$c0,(a0)                       ; ports A and B output
	move.b	#$e,(a1)                        ; port A
	move.b	#$27,(a0)                       ; floppies deselected, strobe high
	move.b	#$f,(a1)                        ; port B: printer data
	move.b	d0,(a0)                         ; the bit out
	bsr.w	printer_strobe_readback         ; strobed, port B made an input
	move.b	#$f,(a1)                        ; port B
	move.b	(a1),d1                         ; read back
	cmp.b	d0,d1                           ; the same?
	beq.s	printer_data_next               ; yes
	or.b	d0,test_errors.w                ; the bit marked bad
printer_data_next:
	lsl.b	#1,d0                           ; the next bit
	bne.s	printer_data_loop               ; eight done?
	move.b	#$80,d0                         ; data bit 7 set
	bsr.w	printer_send_busy_bit           ; out
	btst	#$0,$fffffa01.w                 ; MFP GPIP, BUSY high?
	beq.s	printer_busy_low                ; no
	bset	#$0,test_errors_high.w          ; error: BUSY did not follow
printer_busy_low:
	move.b	#$0,d0                          ; data bit 7 clear
	bsr.w	printer_send_busy_bit           ; out
	btst	#$0,$fffffa01.w                 ; MFP GPIP, BUSY low?
	bne.s	joystick_port_tests             ; no
	bset	#$1,test_errors_high.w          ; error: BUSY did not follow
joystick_port_tests:
	move.w	#$2400,sr                       ; interrupts on: the keyboard processor answers
	moveq	#21,d1                          ; $15: joystick interrogation mode
	bsr.w	ikbd_send                       ; sent
	bne.w	joystick_timeout                ; time-out
	move.b	#$7,(a1)                        ; PSG mixer
	move.b	#$c0,(a0)                       ; ports A and B output
	move.b	#$e,(a1)                        ; port A
	move.b	#$27,(a0)                       ; floppies deselected, strobe high
	move.b	#$f,(a1)                        ; port B
	move.b	#$80,(a0)                       ; data bit 7
	bsr.w	read_joysticks                  ; the joysticks asked for
	beq.w	joystick_timeout                ; no answer
	btst	#$7,d0                          ; fire on joystick 1?
	bne.s	joystick_fire_zero              ; yes
	bset	#$0,test_errors_extra.w         ; error: fire line (J3)
joystick_fire_zero:
	move.b	#$40,(a0)                       ; data bit 6
	bsr.w	read_joysticks                  ; the joysticks asked for
	beq.w	joystick_timeout                ; no answer
	btst	#$7,d1                          ; fire on joystick 0?
	bne.s	joystick_directions             ; yes
	bset	#$1,test_errors_extra.w         ; error: fire line (J4)
joystick_directions:
	move.b	#$f,(a1)                        ; port B
	moveq	#0,d2                           ; the first of eight
	movea.l	#printer_port_test_out,a2       ; the bytes sent
	movea.l	#printer_port_test_in,a3        ; the bytes wanted back
joystick_directions_loop:
	move.b	0(a2,d2.w),d1                   ; this byte
	move.b	d1,(a0)                         ; out
	bsr.w	read_joysticks                  ; the joysticks asked for
	beq.w	joystick_timeout                ; no answer
	andi.b	#$f,d0                          ; joystick 1 directions
	lsl.b	#4,d1                           ; joystick 0 directions
	or.b	d1,d0                           ; the high nibble
	cmp.b	0(a3,d2.w),d0                   ; as wanted?
	beq.s	joystick_directions_next        ; yes
	bset	d0,test_errors_last.w           ; error: a direction bit (numbered by the value read, not the one
                                                ;   wanted)
joystick_directions_next:
	addq.w	#1,d2                           ; the next
	cmpi.b	#$8,d2                          ; eight done?
	bne.s	joystick_directions_loop        ; no
	move.b	#$c0,(a0)                       ; data back to $C0
	move.b	#$1a,d1                         ; $1A: joysticks off
	bsr.w	ikbd_send                       ; sent
	move.w	#$12c,d0                        ; a pause
joystick_end_delay:
	bsr.w	delay
	dbra	d0,joystick_end_delay           ; of 301 delays
	clr.w	6(a0)                           ; a0 is the PSG data register here: these clear $FFFF8808
	clr.w	8(a0)                           ; and $FFFF880A (PSG mirrors), not the keyboard buffer pointers
	tst.b	test_errors.w                   ; printer data errors?
	beq.s	printer_report_busy             ; no
	movea.l	#msg_printer_port_error,a5      ; "P0 Printer port error "
	bsr.w	print_string                    ; shown
	moveq	#7,d0                           ; from bit 7
printer_error_bits:
	move.b	#$30,d1                         ; '0'
	btst	d0,test_errors.w                ; this bit bad?
	beq.s	printer_error_bit_print         ; no
	move.b	#$31,d1                         ; '1'
printer_error_bit_print:
	bsr.w	put_char                        ; shown
	lsr.b	#1,d0                           ; the next bit: halved, so only bits 7, 3 and 1 are shown
	bne.s	printer_error_bits              ; done?
	bsr.w	print_newline                   ; a new line
printer_report_busy:
	tst.b	test_errors_high.w              ; BUSY errors?
	beq.s	printer_report_left             ; no
	movea.l	#msg_busy_line_error,a5         ; "P1 Busy line error"
	bsr.w	print_string                    ; shown
printer_report_left:
	btst	#$0,test_errors_extra.w         ; joystick 1 fire error?
	beq.s	printer_report_right            ; no
	movea.l	#msg_left_button_line_error,a5  ; "J3 Left button line error"
	bsr.w	print_string                    ; shown
printer_report_right:
	btst	#$1,test_errors_extra.w         ; joystick 0 fire error?
	beq.s	printer_report_joy0             ; no
	movea.l	#msg_right_button_line_error,a5 ; "J4 Right button line error"
	bsr.w	print_string                    ; shown
printer_report_joy0:
	move.b	test_errors_last.w,d0           ; the direction errors
	andi.b	#$f,d0                          ; port 0's?
	beq.s	printer_report_joy1             ; none
	movea.l	#msg_joystick_port_0_error,a5   ; "J0 Joystick Port 0 error"
	bsr.w	print_string                    ; shown
printer_report_joy1:
	move.b	test_errors_last.w,d0           ; the direction errors
	andi.b	#$f0,d0                         ; port 1's?
	beq.s	printer_report_result           ; none
	movea.l	#msg_joystick_port_1_error,a5   ; "J1 Joystick Port 1 error"
	bsr.w	print_string                    ; shown
printer_report_result:
	moveq	#0,d0                           ; any error at all?
	or.b	test_errors.w,d0
	or.b	test_errors_high.w,d0
	or.b	test_errors_extra.w,d0
	or.b	test_errors_last.w,d0
	beq.s	printer_joystick_pass           ; no
printer_joystick_fail:
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
printer_joystick_result:
	bsr.w	show_result                     ; the result shown
	move.w	#$2400,sr                       ; interrupts on
	rts
printer_joystick_pass:
	movea.l	#msg_pass,a5                    ; "Pass"
	bra.s	printer_joystick_result
joystick_timeout:
	movea.l	#msg_joystick_time_out,a5       ; "J2 Joystick time-out"
	bsr.w	print_string                    ; shown
	bra.s	printer_joystick_fail           ; fail

;------------------------------------------------------------------------------
; printer_strobe_readback: pulses GPIP0 (BUSY, made an output for it) low and high so the loopback plug
;  takes the printer data, then makes port B an input and port A $00.  In: a0 PSG data, a1 PSG select.
;------------------------------------------------------------------------------
printer_strobe_readback:	; from: printer_joystick_test, printer_send_busy_bit
	bset	#$0,$fffffa05.w                 ; MFP DDR, GPIP0 an output
	bclr	#$0,$fffffa01.w                 ; MFP GPIP, low
	bset	#$0,$fffffa01.w                 ; MFP GPIP, high: the strobe
	bclr	#$0,$fffffa05.w                 ; MFP DDR, an input again
	move.b	#$7,(a1)                        ; PSG mixer
	move.b	#$40,(a0)                       ; port A output, port B input
	move.b	#$e,(a1)                        ; port A
	move.b	#$0,(a0)                        ; all low
	rts

;------------------------------------------------------------------------------
; printer_send_busy_bit: puts d0 on the printer data and strobes it for the BUSY check.
;  In: d0 the data byte, a0 PSG data, a1 PSG select.
;------------------------------------------------------------------------------
printer_send_busy_bit:	; from: printer_joystick_test
	move.b	#$e,(a1)                        ; port A
	move.b	#$20,(a0)                       ; strobe high, drives selected
	move.b	#$7,(a1)                        ; PSG mixer
	move.b	#$c0,(a0)                       ; ports A and B output
	move.b	#$f,(a1)                        ; port B
	move.b	d0,(a0)                         ; the data
	bsr.s	printer_strobe_readback         ; strobed
	rts

;------------------------------------------------------------------------------
; read_joysticks: asks the keyboard processor for the joysticks ($16) and waits for the answer that the
;  keyboard routine puts at $236/$237.  Out: d0 joystick 1, d1 joystick 0, Z set when nothing came
;  (or the command was not taken).  Changes d0, d1.
;------------------------------------------------------------------------------
read_joysticks:	; from: printer_joystick_test
	move.w	#$2710,d0                       ; a pause
	move.w	#$ffff,ikbd_data_first.w        ; nothing yet
read_joysticks_delay:
	dbra	d0,read_joysticks_delay
	moveq	#22,d1                          ; $16: interrogate joysticks
	bsr.w	ikbd_send                       ; sent
	bne.s	read_joysticks_check            ; time-out
	move.w	#$2710,d0                       ; a pause for the answer
read_joysticks_wait:
	dbra	d0,read_joysticks_wait
	move.b	ikbd_data_second.w,d0           ; joystick 1
	move.b	ikbd_data_first.w,d1            ; joystick 0
read_joysticks_check:
	cmpi.w	#$ffff,ikbd_data_first.w        ; nothing came?
	rts

;------------------------------------------------------------------------------
; mono_monitor_test: the H test.  Asks for a monochrome monitor, waits until GPIP7 says one is
;  connected (ESC returns), then shows a stripe pattern at $20000 and flashes the background while
;  waiting: started in high resolution, for a key; else until the monitor is taken off again.
;  GPIP7 meanwhile switches to high resolution (the interrupt routine installed here); at the end the
;  default mono detect routine (a restart) is back.  Out: $28F bit 7 set unless bit 4.
;  Changes d0, a0, the screen at $10000, $49E, $4A0, $21A.
;------------------------------------------------------------------------------
mono_monitor_test:	; from: read_command_line
	moveq	#15,d0                          ; interrupt 15: GPIP7
	movea.l	#high_res_switch_handler,a2     ; the high resolution switch
	bsr.w	mfp_install_handler             ; installed
	movea.l	#msg_connect_mono_monitor,a5    ; "Connect monochrome monitor"
	bsr.w	show_status                     ; on the top line
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.b	#$3,d0
	move.b	d0,saved_resolution.w           ; kept
	move.w	$ffff8240.w,d0                  ; palette 0, the background colour
	andi.w	#$777,d0
	move.w	d0,saved_colour0.w              ; kept
mono_monitor_wait:
	btst	#$7,$fffffa01.w                 ; MFP GPIP, a mono monitor?
	beq.s	mono_monitor_pattern            ; yes
	bsr.w	key_waiting                     ; a key?
	tst.w	d0
	beq.s	mono_monitor_wait               ; no
	bsr.w	get_key                         ; the key
	cmpi.b	#$1b,d0                         ; ESC?
	bne.s	mono_monitor_wait               ; no: wait on
	rts
mono_monitor_pattern:
	move.w	#$3,$ffff8240.w                 ; palette 0, the background blue
	movea.l	#$20000,a0                      ; the pattern screen
	move.b	#$2,$ffff8201.w                 ; video base high, at $20000
	clr.b	$ffff8203.w                     ; video base mid
	moveq	#39,d0                          ; 40 words
mono_pattern_top:
	move.w	#$0,(a0)+                       ; clear first
	dbra	d0,mono_pattern_top
mono_pattern_rows:
	moveq	#79,d0                          ; 160 bytes
mono_pattern_stripes:
	move.w	#$6666,(a0)+                    ; of stripes
	dbra	d0,mono_pattern_stripes
	moveq	#79,d0                          ; 160 bytes
mono_pattern_gap:
	move.w	#$0,(a0)+                       ; clear
	dbra	d0,mono_pattern_gap
	cmpa.l	#$28000,a0                      ; the 32K screen done?
	blt.s	mono_pattern_rows               ; no
	move.l	$70.w,-(sp)                     ; the VBL vector kept
	move.l	#mono_vbl_flash,$70.w           ; VBL vector, the flashing routine
	move.l	#$78,scratch_long.w             ; 120 VBLs to a flash
	move.w	#$2200,sr                       ; VBLs on
mono_monitor_wait_flash:
	cmpi.l	#$1,scratch_long.w              ; wait to the first flash
	bne.s	mono_monitor_wait_flash
	cmpi.b	#$2,saved_resolution.w          ; started in high resolution?
	bne.s	mono_monitor_wait_unplug        ; no
	bsr.w	get_key                         ; wait for a key
	move.w	#$2700,sr                       ; no interrupts
	move.b	#$1,$ffff8201.w                 ; video base high, the screen at $10000
	bne.s	mono_monitor_restore            ; (always taken)
mono_monitor_wait_unplug:
	btst	#$7,$fffffa01.w                 ; MFP GPIP, the monitor taken off?
	beq.s	mono_monitor_wait_unplug        ; no
	move.w	#$2700,sr                       ; no interrupts
	bsr.w	delay                           ; a pause
	move.b	saved_resolution.w,$ffff8260.w  ; shift mode, the resolution back
	move.b	#$1,$ffff8201.w                 ; video base high, the screen at $10000
mono_monitor_restore:
	move.l	(sp)+,$70.w                     ; the VBL vector back
	move.l	#monitor_change_handler,$13c.w  ; MFP monochrome detect, mono detect: a restart again
	btst	#$4,mode_flags.w                ; bit 4 set?
	bne.s	mono_monitor_done               ; yes
	bset	#$7,mode_flags.w                ; flag bit 7
mono_monitor_done:
	move.w	saved_colour0.w,$ffff8240.w     ; palette 0, the background colour back
	move.w	#$2400,sr                       ; interrupts on
	rts

;------------------------------------------------------------------------------
; mono_vbl_flash: the VBL routine of the H test: $294 cleared, and every 120 VBLs the background
;  colour's blue bit 0 flipped; $21A counts down to it.
;------------------------------------------------------------------------------
mono_vbl_flash:	; from: mono_monitor_test
	move.w	d0,-(sp)
	clr.b	vbl_flag.w                      ; the VBL flag
	subi.l	#$1,scratch_long.w              ; the count
	bne.s	mono_vbl_flash_done             ; not yet
	move.w	$ffff8240.w,d0                  ; palette 0, the background
	eori.w	#$1,d0                          ; flipped
	move.w	d0,$ffff8240.w                  ; palette 0, written
	move.l	#$78,scratch_long.w             ; 120 VBLs to the next
mono_vbl_flash_done:
	move.w	(sp)+,d0
	rte

;------------------------------------------------------------------------------
; ste_scroll_test: the STE hardware scroll part of the colour test, in medium resolution.  First a
;  triangle (line n has n pixels, up to 640 and down again) scrolled up a line every two VBLs through
;  the video base low register; SPACE goes on.  Then a double-width picture (line offset $50 words)
;  scrolled sideways a pixel per frame with the pixel scroll register, the base stepped 4 bytes each 16
;  pixels by an HBL routine at line 235; SPACE (on release) ends.  The screen, palette and vectors are
;  put back.  Out: $28F bit 7 set.  Changes all registers, $20000-$84000.
;------------------------------------------------------------------------------
ste_scroll_test:	; from: colour_test
	bsr.w	save_screen_settings            ; the screen and colour kept
	move.w	#$0,d4                          ; from the start
	lea	$20000,a0                       ; at $20000
	move.l	#$32000,d7                      ; $64000 bytes
	bsr.w	clear_screen_words              ; cleared
	move.w	#$1,d4                          ; line 1: one pixel
	lea	$20000,a0                       ; the first line
ste_scroll_triangle_up:
	bsr.w	draw_triangle_line              ; one line drawn
	add.w	#$1,d4                          ; one pixel longer
	cmpi.w	#$281,d4                        ; 640 pixels?
	bne.s	ste_scroll_triangle_up          ; no
	sub.w	#$2,d4                          ; back down
ste_scroll_triangle_down:
	bsr.w	draw_triangle_line              ; one line drawn
	sub.w	#$1,d4                          ; one pixel shorter
	bne.s	ste_scroll_triangle_down        ; down to none?
	move.l	$70.w,saved_vbl_vector.w        ; the VBL vector kept
	move.l	#vscroll_vbl,$70.w              ; VBL vector, the vertical scroll routine
	move.w	#$666,$ffff8240.w               ; palette 0, background grey
	move.w	#$0,$ffff8246.w                 ; palette 3, colour 3 black
	move.w	#$ff,scroll_restart.w           ; start at the top
	move.w	#$2200,sr                       ; VBLs on
ste_scroll_wait_space:
	bsr.w	get_key                         ; a key
	cmpi.b	#$20,d0                         ; SPACE?
	bne.s	ste_scroll_wait_space           ; no
	move.w	#$2400,sr                       ; VBLs off
	move.w	#$0,d4                          ; from the start
	lea	$20000,a0                       ; at $20000
	move.l	#$19000,d7                      ; $32000 bytes
	bsr.w	clear_screen_words              ; cleared
ste_scroll_draw_rows:
	bsr.w	draw_hscroll_row                ; two lines of the picture
	add.w	#$1,d4                          ; the next
	cmpi.w	#$ca,d4                         ; 202 done?
	bne.s	ste_scroll_draw_rows            ; no
	move.w	#$ffff,line_count.w             ; line count
	move.l	#hscroll_vbl,$70.w              ; VBL vector, VBL: the line count cleared
	move.l	$68.w,saved_vector.w            ; the HBL vector kept
	move.l	#hscroll_hbl,$68.w              ; HBL vector, the sideways scroll routine
	move.w	#$ff,scroll_restart.w           ; start at the left
	move.w	#$50,$ff820e                    ; line offset 80 words: double-width lines
	move.w	#$2000,sr                       ; HBLs on
	clr.b	key_release.w                   ; no key released yet
ste_hscroll_wait_space:
	bsr.w	get_key                         ; a key
	cmpi.b	#$20,d0                         ; SPACE?
	bne.s	ste_hscroll_wait_space          ; no
	bset	#$7,d1                          ; its release code
ste_hscroll_wait_release:
	cmp.b	key_release.w,d1                ; released?
	bne.s	ste_hscroll_wait_release        ; no
	move.w	#$2400,sr                       ; interrupts back
	move.w	#$0,$ff8264                     ; hscroll (no prefetch), no pixel scroll
	move.w	#$0,$ff820e                     ; no line offset
	move.l	saved_vbl_vector.w,$70.w        ; the VBL vector back
	move.l	saved_vector.w,$68.w            ; the HBL vector back
	bsr.w	restore_medium_screen           ; the screen and colour back
	bset	#$7,mode_flags.w                ; flag bit 7
	rts

;------------------------------------------------------------------------------
; clear_screen_words: clears d7 words from a0.  In: a0, d7.  Out: a0 unchanged, d7 0.
;------------------------------------------------------------------------------
clear_screen_words:	; from: ste_scroll_test
	move.l	a0,-(sp)
clear_screen_words_loop:
	clr.w	(a0)+                           ; a word cleared
	sub.l	#$1,d7                          ; count
	bne.s	clear_screen_words_loop         ; more?
	movea.l	(sp)+,a0                        ; a0 back
	rts

;------------------------------------------------------------------------------
; draw_triangle_line: one medium resolution line of the triangle: d4 pixels in colour 3 from the left.
;  In: a0 the line, d4 the pixel count.  Out: a0 the next line (160 bytes on).  Changes d0, d1, a1.
;------------------------------------------------------------------------------
draw_triangle_line:	; from: ste_scroll_test
	move.w	d4,-(sp)                        ; the count kept
	movea.l	a0,a1                           ; the line
	move.w	#$a0,d0                         ; 160 bytes
	adda.w	d0,a1                           ; the next line
draw_triangle_line_blocks:
	cmpi.w	#$10,d4                         ; 16 pixels or more left?
	blt.w	draw_triangle_line_end          ; no
	move.w	#$ffff,d0                       ; all set
	move.w	d0,(a0)+                        ; plane 0
	move.w	d0,(a0)+                        ; plane 1
	subi.w	#$10,d4                         ; 16 fewer
	beq.s	draw_triangle_line_end          ; none left
	cmpa.l	a0,a1                           ; the line full?
	bne.s	draw_triangle_line_blocks       ; no
draw_triangle_line_end:
	tst.w	d4                              ; pixels left over?
	beq.s	draw_triangle_line_done         ; no
	clr.w	d0                              ; the last block
draw_triangle_line_bits:
	move.w	#$10,d1                         ; from the left
	sub.w	d4,d1                           ; this pixel
	bset	d1,d0                           ; set
	subq.w	#1,d4                           ; the next
	bne.s	draw_triangle_line_bits         ; more?
	move.w	d0,(a0)+                        ; plane 0
	move.w	d0,(a0)+                        ; plane 1
draw_triangle_line_done:
	movea.l	a1,a0                           ; the next line
	move.w	(sp)+,d4                        ; the count back
	rts

;------------------------------------------------------------------------------
; draw_hscroll_row: two lines of the sideways scroll picture: from pixel d4 to the middle of the
;  320-byte double-width line set in colour 3, mirrored from the right edge, the same in both halves
;  (the second at +160) and on the next line.  In: a0 the line, d4 the start pixel.
;  Out: a0 two lines (320 bytes) on.  Changes d0-d3, a1-a3.
;------------------------------------------------------------------------------
draw_hscroll_row:	; from: ste_scroll_test
	move.w	d4,-(sp)                        ; the count kept
	movea.l	a0,a1                           ; the left end
	movea.l	a0,a2                           ; the middle
	move.l	#$a0,d0                         ; 160 bytes
	adda.l	d0,a1                           ; the right end of the first half
	lsr.w	#1,d0                           ; 80 bytes
	adda.l	d0,a2                           ; the middle
	movea.l	a0,a3                           ; the line
	lsl.w	#2,d0                           ; 320 bytes
	adda.w	d0,a3                           ; the next pair of lines
	clr.l	d2
	clr.l	d3
	move.w	d4,d2                           ; the start pixel
	divu.w	#$10,d2                         ; in 16-pixel blocks
	move.w	d2,d3
	lsl.l	#2,d3                           ; 4 bytes a block
	adda.l	d3,a0                           ; the left block
	suba.l	d3,a1                           ; the right block
	swap	d2                              ; the pixel in the block
	move.w	#$f,d1                          ; from the left
	sub.w	d2,d1                           ; the bit
	clr.w	d0                              ; the left edge's mask
	clr.w	d3                              ; the right edge's
draw_hscroll_row_edge:
	bset	d1,d0                           ; left edge: from this pixel on
	bset	d2,d3                           ; right edge: up to its mirror
	addq.w	#1,d2
	dbra	d1,draw_hscroll_row_edge        ; to the end of the block
	move.w	d0,$a0(a0)                      ; left edge, plane 0, second half
	move.w	d0,(a0)+                        ; first half
	move.w	d0,$a0(a0)                      ; plane 1, second half
	move.w	d0,(a0)+                        ; first half
	move.w	d3,-(a1)                        ; right edge, plane 1
	move.w	d3,$a0(a1)                      ; second half
	move.w	d3,-(a1)                        ; plane 0
	move.w	d3,$a0(a1)                      ; second half
	moveq	#-1,d0                          ; all set
draw_hscroll_row_fill:
	cmpa.l	a0,a2                           ; at the middle?
	ble.s	draw_hscroll_row_done           ; yes
	move.w	d0,$a0(a0)                      ; from the left, second half
	move.w	d0,(a0)+                        ; first half
	move.w	d0,-(a1)                        ; from the right
	move.w	d0,$a0(a1)                      ; second half
	bra.s	draw_hscroll_row_fill           ; on
draw_hscroll_row_done:
	movea.l	a3,a0                           ; two lines on
	move.w	(sp)+,d4                        ; the count back
	rts

;------------------------------------------------------------------------------
; hscroll_vbl: the VBL routine of the sideways scroll: the HBL count cleared.
;------------------------------------------------------------------------------
hscroll_vbl:	; from: ste_scroll_test
	clr.w	line_count.w                    ; line count
	rte

;------------------------------------------------------------------------------
; hscroll_hbl: the HBL routine of the sideways scroll: at line 235 the picture moves one pixel: the pixel
;  scroll register 1-15 with the line offset $4E, at 0 the base 4 bytes on (one 16-pixel block) with
;  offset $50.  Only the base low byte is written, so the picture steps back within 256 bytes; past
;  $40140, or when $4DA is set, it starts again at $20000.
;------------------------------------------------------------------------------
hscroll_hbl:	; from: ste_scroll_test
	move.l	d0,-(sp)
	addi.w	#$1,line_count.w                ; one more line
	cmpi.w	#$eb,line_count.w               ; line 235?
	bne.w	hscroll_hbl_done                ; no
	cmpi.w	#$0,scroll_restart.w            ; start again?
	beq.s	hscroll_hbl_step                ; no
hscroll_hbl_restart:
	move.b	#$2,$ffff8201.w                 ; video base high, the screen at $20000
	move.b	#$0,$ffff8203.w                 ; video base mid
	move.b	#$0,$ffff820d.w                 ; video base low
	move.l	#$20000,scroll_position.w       ; the position
	move.w	#$0,$ff8264                     ; hscroll (no prefetch), no pixel scroll
	move.w	#$50,$ff820e                    ; line offset 80 words
	clr.w	scroll_restart.w                ; started
	move.w	#$0,scroll_step.w               ; pixel 0
	bra.s	hscroll_hbl_done
hscroll_hbl_step:
	move.w	scroll_step.w,d0                ; the pixel
	add.w	#$1,d0                          ; one on
	andi.w	#$f,d0                          ; in the block
	move.w	d0,scroll_step.w                ; kept
	tst.w	d0                              ; the next block?
	beq.s	hscroll_hbl_next_block          ; yes
	move.w	d0,$ff8264                      ; hscroll (no prefetch), the pixel scroll
	move.w	#$4e,$ff820e                    ; line offset one block less (the extra fetch)
	bra.s	hscroll_hbl_done
hscroll_hbl_next_block:
	addi.l	#$4,scroll_position.w           ; one block on
	move.w	#$0,$ff8264                     ; hscroll (no prefetch), no pixel scroll
	move.w	#$50,$ff820e                    ; line offset 80 words
	move.b	scroll_position+3.w,$ffff820d.w ; video base low, base low only
	cmpi.l	#$40140,scroll_position.w       ; at the end?
	bge.w	hscroll_hbl_restart             ; yes: again
hscroll_hbl_done:
	move.l	(sp)+,d0
	rte

;------------------------------------------------------------------------------
; vscroll_vbl: the VBL routine of the triangle scroll: every second VBL the screen base one line (160 bytes)
;  on, through high, mid and low; at $52000, or when $4DA is set, back to $20000.
;------------------------------------------------------------------------------
vscroll_vbl:	; from: ste_scroll_test
	movem.l	d0-d1,-(sp)
	cmpi.w	#$0,scroll_restart.w            ; start again?
	beq.s	vscroll_vbl_step                ; no
vscroll_vbl_restart:
	move.b	#$2,$ffff8201.w                 ; video base high, the screen at $20000
	move.b	#$0,$ffff8203.w                 ; video base mid
	move.b	#$0,$ffff820d.w                 ; video base low
	move.l	#$20000,scroll_position.w       ; the position
	clr.w	scroll_restart.w                ; started
	clr.w	scroll_step.w                   ; VBL count
	bra.s	vscroll_vbl_done
vscroll_vbl_step:
	move.l	scroll_position.w,d0            ; the position
	cmp.l	#$52000,d0                      ; at the end?
	bge.s	vscroll_vbl_restart             ; yes
	addi.w	#$1,scroll_step.w               ; one more VBL
	cmpi.w	#$2,scroll_step.w               ; the second?
	bne.s	vscroll_vbl_done                ; no
	clr.w	scroll_step.w                   ; counted again
	add.l	#$a0,d0                         ; one line on
	move.l	d0,scroll_position.w            ; the position
	move.b	scroll_position+1.w,$ffff8201.w ; video base high, base high
	move.b	scroll_position+2.w,$ffff8203.w ; video base mid, mid
	move.b	scroll_position+3.w,$ffff820d.w ; video base low, low
vscroll_vbl_done:
	movem.l	(sp)+,d0-d1
	rte

;------------------------------------------------------------------------------
; floppy_menu: the F test.  Sets the default floppy parameters (drive A, side 0, track 0, sector 1, 9
;  sectors, format fill $E5E5) and runs timer A freely (/4, 63) as a random number source.
;  Unattended ($28D set) it runs the quick test on the installed drives; else it shows the menu
;  "Floppy disk drive routines:" and runs choice 1-7 from floppy_menu_table, any other key back to the
;  main menu with the drives deselected.  Floppy variables: $AA2 side, $AA4 track, $AA6 first sector,
;  $AA8 sector count, $AAA drive (0 A, 1 B), $AAC the buffer, $27A/$27B drive A/B type (bit 7 found,
;  bit 6 high density, bit 1 double sided, bit 0 single), $676/$677 drive A/B errors.
;------------------------------------------------------------------------------
floppy_menu:                                    ; from: floppy_quick_test, floppy_alignment, floppy_interchange,
                                                ;   floppy_exerciser, floppy_copy_protect, floppy_speed_test, 2 more
	clr.b	floppy_quiet.w                  ; errors shown
	move.b	#$3f,$fffffa1f.w                ; MFP TADR, timer A data 63
	move.b	#$1,$fffffa19.w                 ; MFP TACR, timer A /4, free running: random numbers
	move.w	#$e5e5,fd_fill_word.w           ; format fill
	move.w	#$1,fd_interleave.w             ; $AA0 1
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$0,fd_track.w                  ; track 0
	move.w	#$1,fd_sector.w                 ; sector 1
	move.w	#$9,fd_count.w                  ; 9 sectors
	move.w	#$0,fd_drive.w                  ; drive A
	clr.b	test_errors.w                   ; no drive A errors
	clr.b	test_errors_high.w              ; no drive B errors
	tst.b	unattended.w                    ; unattended?
	bne.s	floppy_unattended               ; yes
	move.w	#$3,$ffff8240.w                 ; palette 0, the background blue
	bsr.w	clear_screen                    ; the screen cleared
	lea	floppy_menu_text,a5             ; "Floppy disk drive routines:" and choices 1-7
	bsr.w	print_string                    ; shown
	bsr.w	get_key                         ; a key
	cmpi.b	#$30,d0                         ; below '1'?
	bls.w	floppy_menu_quit                ; yes: back to the main menu
	cmpi.b	#$37,d0                         ; above '7'?
	bhi.w	floppy_menu_quit                ; yes: back to the main menu
	andi.l	#$f,d0                          ; the digit
	subq.w	#1,d0                           ; 0-6
	lsl.w	#2,d0                           ; *4
	lea	floppy_menu_jump_table,a5       ; the choices
	bsr.w	clear_screen                    ; the screen cleared
	movea.l	0(a5,d0.w),a0                   ; this choice
	jmp	(a0)                            ; run

;------------------------------------------------------------------------------
; floppy_menu_jump_table: the floppy menu choices 1 to 7 (key - '1', times 4).
;------------------------------------------------------------------------------
floppy_menu_jump_table:
	dc.l	floppy_quick_test               ; 1 quick test
	dc.l	floppy_alignment                ; 2 read alignment disk
	dc.l	floppy_interchange              ; 3 disk interchange test
	dc.l	floppy_exerciser                ; 4 disk exerciser
	dc.l	floppy_copy_protect             ; 5 check copy protect tracks 80-82
	dc.l	floppy_speed_test               ; 6 test speed
	dc.l	floppy_install_drives           ; 7 install disk drives
floppy_menu_quit:	; from: floppy_menu
	move.l	#vbl_handler,$70.w              ; VBL vector, the VBL routine back
	move.b	#$6,d0                          ; both drives deselected
	bsr.w	psg_select_drive_side           ; on the PSG port
	bra.w	menu                            ; the main menu
floppy_unattended:	; from: floppy_menu
	cmpi.l	#$1,test_cycle.w                ; the first cycle?
	bne.s	floppy_unattended_drives        ; no
	bsr.w	detect_drive_types              ; yes: the drive types found
floppy_unattended_drives:
	move.b	drive_a_type.w,d0               ; any drive?
	or.b	drive_b_type.w,d0
	bne.s	floppy_quick_drives             ; yes: the quick test
	rts

;------------------------------------------------------------------------------
; floppy_quick_test: choice 1 and the unattended floppy test.  Shows each drive's type on lines 0/1, runs
;  quick_test_drive and random_track_test on each drive found, shows "Pass" or "Fail " at column 50, and
;  "Fail at cycle:" after an error.  From the menu it then waits for a key and goes back to it;
;  unattended ($28F bits 3-5) it deselects the drives and returns.  Detects the drives first when no
;  types are set.
;------------------------------------------------------------------------------
floppy_quick_test:	; from: floppy_menu_jump_table
	bsr.w	clear_screen                    ; the screen cleared
	bsr.w	print_newline                   ; two new lines
	bsr.w	print_newline
	move.b	drive_a_type.w,d0               ; any drive types?
	or.b	drive_b_type.w,d0
	bne.s	floppy_quick_drives             ; yes
	bsr.w	detect_drive_types              ; found and their types set
	move.b	drive_a_type.w,d0               ; any drive now?
	or.b	drive_b_type.w,d0
	bne.s	floppy_quick_drives             ; yes
	rts
floppy_quick_drives:	; from: floppy_menu_jump_table
	move.w	#$2,scroll_top.w                ; output from line 2
	bsr.w	save_cursor                     ; the cursor kept
	bsr.w	cursor_home                     ; to the top left
	tst.b	drive_a_type.w                  ; drive A?
	beq.s	floppy_quick_show_b             ; no
	lea	msg_disk_a,a5                   ; "Disk A: "
	bsr.w	print_string                    ; shown
	lea	msg_high_density,a5             ; "High Density "
	btst	#$6,drive_a_type.w              ; high density?
	bne.s	floppy_quick_show_type_a        ; yes
	lea	msg_single_sided,a5             ; "SS "
	btst	#$1,drive_a_type.w              ; double sided?
	beq.s	floppy_quick_show_type_a        ; no
	lea	msg_double_sided,a5             ; "DS "
floppy_quick_show_type_a:
	bsr.w	print_string                    ; shown
floppy_quick_show_b:
	tst.b	drive_b_type.w                  ; drive B?
	beq.s	floppy_quick_drive_a            ; no
	moveq	#0,d0                           ; line 1
	moveq	#1,d1
	bsr.w	set_cursor                      ; the cursor there
	lea	msg_disk_b,a5                   ; "Disk B: "
	bsr.w	print_string                    ; shown
	lea	msg_single_sided,a5             ; "SS "
	btst	#$1,drive_b_type.w              ; double sided?
	beq.s	floppy_quick_show_type_b        ; no
	lea	msg_double_sided,a5             ; "DS "
floppy_quick_show_type_b:
	bsr.w	print_string                    ; shown
floppy_quick_drive_a:
	bsr.w	restore_cursor                  ; the cursor back
	tst.b	test_errors.w                   ; drive A already failed?
	bne.s	floppy_quick_fail_a             ; yes
	cmpi.b	#$0,drive_a_type.w              ; drive A?
	beq.s	floppy_quick_drive_b            ; no
	move.w	#$0,fd_drive.w                  ; drive A
	bsr.w	quick_test_drive                ; tracks 0, 1, 79 and the sides
	tst.b	test_errors.w                   ; failed?
	bne.s	floppy_quick_fail_a             ; yes
	bsr.w	random_track_test               ; a random track
	lea	msg_pass,a5                     ; "Pass"
	tst.b	test_errors.w                   ; failed?
	beq.s	floppy_quick_result_a           ; no
floppy_quick_fail_a:
	lea	msg_fail,a5                     ; "Fail "
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
floppy_quick_result_a:
	moveq	#50,d0                          ; column 50
	moveq	#0,d1                           ; line 0
	bsr.w	show_status_at                  ; the result shown there
	tst.b	test_errors_high.w              ; drive B already failed?
	bne.s	floppy_quick_fail_b             ; yes
floppy_quick_drive_b:
	cmpi.b	#$0,drive_b_type.w              ; drive B?
	beq.s	floppy_quick_summary            ; no
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	quick_test_drive                ; tracks 0, 1, 79 and the sides
	tst.b	test_errors_high.w              ; failed?
	bne.s	floppy_quick_fail_b             ; yes
	bsr.w	random_track_test               ; a random track
	lea	msg_pass,a5                     ; "Pass"
	tst.b	test_errors_high.w              ; failed?
	beq.s	floppy_quick_result_b           ; no
floppy_quick_fail_b:
	lea	msg_fail,a5                     ; "Fail "
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
floppy_quick_result_b:
	moveq	#50,d0                          ; column 50
	moveq	#1,d1                           ; line 1
	bsr.w	show_status_at                  ; the result shown there
floppy_quick_summary:
	move.b	test_errors.w,d0                ; any errors?
	or.b	test_errors_high.w,d0
	beq.s	floppy_quick_end                ; no
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
	bsr.w	show_result                     ; and the cycle shown
floppy_quick_end:
	move.b	mode_flags.w,d0                 ; the unattended modes
	andi.b	#$38,d0
	bne.s	floppy_quick_unattended_end     ; unattended
	bsr.w	screen_is_red                   ; the background red?
	beq.s	floppy_quick_wait_key           ; yes
	move.w	#$51,$ffff8240.w                ; palette 0, no: green
floppy_quick_wait_key:
	bsr.w	get_key                         ; a key
	bra.w	floppy_menu                     ; the menu
floppy_quick_unattended_end:
	move.l	#vbl_handler,$70.w              ; VBL vector, the VBL routine back
	move.b	#$6,d0                          ; both drives deselected
	bsr.w	psg_select_drive_side           ; on the PSG port
	rts

;------------------------------------------------------------------------------
; floppy_alignment: choice 2, "Read analog alignment disk".  Asks for drive A or B and a track (default
;  40, up to 79), then reads the track over and over: up/down arrows side 1/0, right/left arrows the
;  next/previous track (wrapping at 79 to 0), SPACE stops, ESC the floppy menu.  Reads only.
;------------------------------------------------------------------------------
floppy_alignment:	; from: floppy_menu_jump_table
	lea	msg_read_alignment_disk,a5      ; "Read analog alignment disk", "Disk A or B?"
	bsr.w	print_string                    ; shown
	move.w	#$0,fd_drive.w                  ; drive A
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$28,fd_track.w                 ; track 40
	move.w	#$1,fd_sector.w                 ; sector 1
floppy_alignment_drive:
	bsr.w	get_key                         ; a key
	cmp.b	#$41,d0                         ; 'A'?
	beq.s	floppy_alignment_track          ; yes
	cmp.b	#$42,d0                         ; 'B'?
	bne.s	floppy_alignment_drive          ; no: ask again
	move.w	#$1,fd_drive.w                  ; drive B
floppy_alignment_track:
	lea	msg_enter_track_number,a5       ; "Enter track number (if none entered, default=40): "
	bsr.w	print_string                    ; shown
	bsr.w	read_command_line               ; a line typed
	tst.w	d0                              ; nothing?
	beq.w	floppy_alignment_start          ; then track 40
	bsr.w	print_newline                   ; a new line
	lea	number_digits.w,a3              ; the digits reversed to $269
floppy_alignment_reverse:
	move.b	-(a4),d0                        ; from the last
	move.b	d0,(a3)+                        ; to the first
	cmpa.l	#$239,a4                        ; all of them?
	bne.s	floppy_alignment_reverse        ; no
	lea	number_digits.w,a0              ; the reversed digits
	bsr.w	decimal_to_number               ; made a number
	cmp.w	#$4f,d2                         ; past track 79?
	bhi.s	floppy_alignment_track          ; yes: ask again
	move.w	d2,fd_track.w                   ; the track
floppy_alignment_start:
	bsr.w	clear_screen                    ; the screen cleared
	move.w	#$1,fd_interleave.w             ; $AA0 1
	move.w	#$0,fd_side.w                   ; side 0
	bsr.w	restore_drive                   ; to track 0
	beq.w	floppy_alignment_read           ; done
	lea	msg_drive_not_ready,a5          ; "FD Drive not ready "
	bsr.w	print_string                    ; shown
	bsr.w	print_drive_side_track          ; with the drive, side and track
	bsr.w	print_newline                   ; a new line
	bra.w	floppy_alignment_stopped        ; stopped
floppy_alignment_read:
	lea	msg_reading,a5                  ; "Reading    "
	bsr.w	show_floppy_status              ; the status line
	bsr.w	read_alignment_track            ; the track read
	bsr.w	key_waiting                     ; a key?
	beq.s	floppy_alignment_read           ; no: again
	bsr.w	get_key                         ; the key
	cmpi.b	#$48,d1                         ; up arrow?
	beq.s	floppy_alignment_side1          ; side 1
	cmpi.b	#$50,d1                         ; down arrow?
	beq.s	floppy_alignment_side0          ; side 0
	cmpi.b	#$4d,d1                         ; right arrow?
	beq.w	floppy_alignment_track_up       ; the next track
	cmpi.b	#$4b,d1                         ; left arrow?
	beq.w	floppy_alignment_track_down     ; the track before
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_alignment_quit           ; the floppy menu
	cmpi.b	#$20,d0                         ; SPACE?
	bne.s	floppy_alignment_read           ; no: read on
floppy_alignment_stopped:
	lea	msg_stopped_esc_quit,a5         ; "Stopped. ESC to quit, any other key to continue."
	bsr.w	print_string                    ; shown
	bsr.w	get_key                         ; a key
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_alignment_quit           ; yes
	bsr.w	clear_screen                    ; the screen cleared
	bra.s	floppy_alignment_read           ; read on
floppy_alignment_quit:
	bra.w	floppy_menu                     ; the floppy menu
floppy_alignment_side0:
	move.w	#$0,fd_side.w                   ; side 0
	bra.s	floppy_alignment_read
floppy_alignment_side1:
	move.w	#$1,fd_side.w                   ; side 1
	bra.s	floppy_alignment_read
floppy_alignment_track_up:
	cmpi.w	#$4f,fd_track.w                 ; at track 79?
	beq.w	floppy_alignment_wrap_low       ; yes
	addi.w	#$1,fd_track.w                  ; one track on
	bra.w	floppy_alignment_read
floppy_alignment_wrap_low:
	move.w	#$0,fd_track.w                  ; back to track 0
	bra.w	floppy_alignment_read
floppy_alignment_track_down:
	cmpi.w	#$0,fd_track.w                  ; at track 0?
	beq.w	floppy_alignment_wrap_high      ; yes
	subi.w	#$1,fd_track.w                  ; one track back
	bra.w	floppy_alignment_read
floppy_alignment_wrap_high:
	move.w	#$4f,d0                         ; 79 into d0, not the track: the track stays 0
	bra.w	floppy_alignment_read

;------------------------------------------------------------------------------
; floppy_interchange: choice 3, "Disk interchange test" (writes both disks).  Tracks 0, 39 and 79 are
;  formatted and written with $AAAA on drive A and $BBBB on drive B; after the disks are swapped
;  drive A must read $BBBB and drive B $AAAA ("Disks were not swapped!" when A still reads $AAAA).
;  ESC at a prompt goes back to the floppy menu.
;------------------------------------------------------------------------------
floppy_interchange:	; from: floppy_menu_jump_table
	move.w	#$3,$ffff8240.w                 ; palette 0, the background blue
	lea	msg_disk_interchange_test,a5    ; "Disk interchange test", "Insert disks in both drives, ..."
	bsr.w	print_string                    ; shown
	bsr.w	get_key                         ; a key
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_menu                     ; yes: the floppy menu
floppy_interchange_start:
	bsr.w	show_drive_lines                ; the drive lines
	move.b	#$0,test_index_byte.w           ; the first track
	move.w	#$1,fd_sector.w                 ; sector 1
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$0,fd_drive.w                  ; drive A
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	beq.s	floppy_interchange_drive_b      ; yes
	bsr.w	print_a_not_selected            ; "Disk A: F0 Not selected "
	bra.s	floppy_interchange_not_selected ; wait
floppy_interchange_drive_b:
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	restore_drive                   ; to track 0
	beq.s	floppy_interchange_write        ; done
	bsr.w	print_b_not_selected            ; "Disk B: F0 Not selected "
floppy_interchange_not_selected:
	bsr.w	get_key                         ; a key
	bra.s	floppy_interchange              ; start again
floppy_interchange_write:
	clr.l	d2
	lea	floppy_interchange_tracks,a2    ; tracks 0, 39, 79
	move.b	test_index_byte.w,d2            ; this one
	move.b	0(a2,d2.w),fd_track+1.w         ; the track
	move.w	#$0,fd_drive.w                  ; drive A
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_format_error ; yes
	bsr.w	fill_buffer_aa                  ; the buffer $AAAA
	bsr.w	floppy_write_sectors            ; written
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_write_error  ; yes
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_format_error ; yes
	bsr.w	fill_buffer_bb                  ; the buffer $BBBB
	bsr.w	floppy_write_sectors            ; written
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_write_error  ; yes
	addi.b	#$1,test_index_byte.w           ; the next track
	cmpi.b	#$3,test_index_byte.w           ; three done?
	bne.s	floppy_interchange_write        ; no
floppy_interchange_swap:
	lea	msg_swap_disks,a5               ; "Swap disks A and B, Hit any key when ready"
	bsr.w	print_string                    ; shown
	bsr.w	get_key                         ; a key
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_menu                     ; yes: the floppy menu
	bsr.w	show_drive_lines                ; the drive lines
	move.w	#$0,test_index_byte.w           ; the first track
	move.l	#$4000,fd_buffer.w              ; read to $4000
floppy_interchange_read_a:
	move.w	#$0,fd_drive.w                  ; drive A
	clr.l	d2
	lea	floppy_interchange_tracks,a2    ; tracks 0, 39, 79
	move.b	test_index_byte.w,d2            ; this one
	move.b	0(a2,d2.w),fd_track+1.w         ; the track
	bsr.w	read_track_checked              ; read
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_mark_fail    ; yes
	lea	$4000.w,a0                      ; the data read
	move.l	#$8ff,d0                        ; 9 sectors of words
floppy_interchange_check_a:
	cmpi.w	#$bbbb,(a0)+                    ; drive B's data?
	beq.s	floppy_interchange_next_a       ; yes
	suba.l	#$2,a0                          ; back to this word
	cmpi.w	#$aaaa,(a0)                     ; drive A's own data?
	bne.w	floppy_interchange_read_error   ; no: a read error
	lea	msg_disks_not_swapped,a5        ; "Disks were not swapped!"
	bsr.w	print_string                    ; shown
	bra.s	floppy_interchange_swap         ; ask again
floppy_interchange_next_a:
	dbra	d0,floppy_interchange_check_a   ; the next word
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	read_track_checked              ; read
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_mark_fail    ; yes
	lea	$4000.w,a0                      ; the data read
	move.l	#$8ff,d0                        ; 9 sectors of words
floppy_interchange_check_b:
	cmpi.w	#$aaaa,(a0)+                    ; drive A's data?
	bne.s	floppy_interchange_read_error   ; no: a read error
	dbra	d0,floppy_interchange_check_b   ; the next word
floppy_interchange_next_track:
	addi.b	#$1,test_index_byte.w           ; the next track
	cmpi.b	#$3,test_index_byte.w           ; three done?
	bne.w	floppy_interchange_read_a       ; no
	bsr.w	screen_is_red                   ; the background red?
	beq.s	floppy_interchange_repeat       ; yes: failed
	move.w	#$51,$ffff8240.w                ; palette 0, green
	lea	msg_pass,a5                     ; "Pass"
	bsr.w	show_result                     ; shown
	bsr.w	get_key                         ; a key
	bra.w	floppy_menu                     ; the floppy menu
floppy_interchange_format_error:
	lea	msg_error_formatting,a5         ; "Error formating "
floppy_interchange_error:
	bsr.w	print_string                    ; shown
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
floppy_interchange_repeat:
	lea	msg_esc_quit_key_repeat,a5      ; "Hit esc to quit, any other key to repeat"
	bsr.w	print_string                    ; shown
	bsr.w	get_key                         ; a key
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_menu                     ; yes: the floppy menu
	bra.w	floppy_interchange_start        ; again
floppy_interchange_write_error:
	lea	msg_error_writing,a5            ; "Error writing"
	bsr.w	print_floppy_error              ; the FDC error shown
	bra.s	floppy_interchange_error        ; and the text
floppy_interchange_read_error:
	lea	msg_error_reading,a5            ; "Error reading"
	bsr.w	print_string                    ; shown
	bsr.w	print_drive_name                ; the drive
	bsr.w	print_track_number              ; the track
	bsr.w	print_newline                   ; a new line
floppy_interchange_mark_fail:
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	bra.w	floppy_interchange_next_track   ; the next track

;------------------------------------------------------------------------------
; show_drive_lines: clears the screen (blue) and puts "Disk A: " and "Disk B: " on lines 0 and 1, the
;  output from line 2 on.
;------------------------------------------------------------------------------
show_drive_lines:	; from: floppy_interchange
	bsr.w	clear_screen                    ; the screen cleared
	move.w	#$3,$ffff8240.w                 ; palette 0, the background blue
	lea	msg_disk_a,a5                   ; "Disk A: "
	bsr.w	print_string                    ; shown
	bsr.w	print_newline                   ; a new line
	lea	msg_disk_b,a5                   ; "Disk B: "
	bsr.w	print_string                    ; shown
	bsr.w	print_newline                   ; a new line
	move.w	#$2,scroll_top.w                ; output from line 2
	rts

;------------------------------------------------------------------------------
; floppy_exerciser: choice 4, "Disk Exerciser" (writes the disk).  For the drive asked for (its sides
;  found when it has no type): every track formatted; then over and over, a new cycle each time: every
;  track written with sector data marked with the cycle and a random byte, then read back in a mixed
;  track order and compared.  Both sides on a double sided drive.  Tracks that failed to format are
;  marked and skipped.  After 5 format, 20 write or 20 read errors it stops to ask; ESC quits.
;------------------------------------------------------------------------------
floppy_exerciser:	; from: floppy_menu_jump_table
	bsr.w	clear_screen                    ; the screen cleared
	lea	msg_disk_exerciser,a5           ; "Disk Exerciser"
	bsr.w	print_string                    ; shown
	lea	msg_disk_a_or_b,a5              ; "Disk A or B?"
	bsr.w	print_string                    ; shown
	bsr.w	print_newline                   ; two new lines
	bsr.w	print_newline
	move.w	#$0,fd_drive.w                  ; drive A
	bsr.w	get_key                         ; a key
	cmp.b	#$41,d0                         ; 'A'?
	bne.s	floppy_exerciser_drive_b        ; no
	move.b	drive_a_type.w,d0               ; drive A's type
	tst.b	d0                              ; installed?
	bne.s	floppy_exerciser_start          ; yes
	bra.s	floppy_exerciser_detect         ; no: its sides found
floppy_exerciser_drive_b:
	cmp.b	#$42,d0                         ; 'B'?
	bne.w	floppy_menu                     ; no: the floppy menu
	move.w	#$1,fd_drive.w                  ; drive B
	move.b	drive_b_type.w,d0               ; its type
	tst.b	d0                              ; installed?
	bne.s	floppy_exerciser_start          ; yes
floppy_exerciser_detect:
	bsr.w	detect_drive_sides              ; its sides found
floppy_exerciser_start:
	move.b	d0,exerciser_drive_type.w       ; the type used
	move.l	#$1,test_cycle.w                ; cycle 1
	bsr.w	clear_screen                    ; the screen cleared
	lea	msg_disk_exerciser,a5           ; "Disk Exerciser"
	bsr.w	print_string                    ; shown
	bsr.w	print_newline                   ; a new line
	move.w	#$2,scroll_top.w                ; output from line 2
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$0,fd_track.w                  ; track 0
	move.w	#$1,fd_sector.w                 ; sector 1
	move.w	#$9,fd_count.w                  ; 9 sectors
	clr.w	write_errors.w                  ; no write errors
	clr.w	read_errors.w                   ; no read errors
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	beq.s	floppy_exerciser_clear_marks    ; yes
	tst.w	fd_drive.w                      ; drive B?
	beq.s	floppy_exerciser_not_a          ; no
	bsr.w	print_b_not_selected            ; "Disk B: F0 Not selected "
	bra.s	floppy_exerciser_not_selected   ; wait
floppy_exerciser_not_a:
	bsr.w	print_a_not_selected            ; "Disk A: F0 Not selected "
floppy_exerciser_not_selected:
	bsr.w	get_key                         ; a key
	bra.w	floppy_exerciser                ; start again
floppy_exerciser_clear_marks:
	lea	bad_tracks.w,a2                 ; the bad track marks
	moveq	#79,d0                          ; 80 of them (side 0 only; side 1's are not cleared)
floppy_exerciser_clear_loop:
	clr.b	(a2)+                           ; cleared
	dbra	d0,floppy_exerciser_clear_loop
floppy_exerciser_format_side:
	clr.w	format_errors.w                 ; no format errors
floppy_exerciser_format_track:
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; an error?
	beq.s	floppy_exerciser_format_esc     ; no
	cmpi.w	#$5,format_errors.w             ; five errors yet?
	blt.w	floppy_exerciser_format_esc     ; no
	bsr.w	ask_stopped                     ; stopped: RET goes on
	beq.s	floppy_exerciser_format_next    ; on
	bra.w	floppy_menu                     ; the floppy menu
floppy_exerciser_format_esc:
	bsr.w	check_esc                       ; ESC?
	bne.w	floppy_menu                     ; yes: the floppy menu
floppy_exerciser_format_next:
	addi.w	#$1,fd_track.w                  ; the next track
	cmpi.w	#$50,fd_track.w                 ; 80 done?
	bne.s	floppy_exerciser_format_track   ; no
	tst.w	fd_side.w                       ; side 1 done?
	bne.s	floppy_exerciser_cycle          ; yes
	btst	#$1,exerciser_drive_type.w      ; double sided?
	beq.s	floppy_exerciser_cycle          ; no
	move.w	#$1,fd_side.w                   ; side 1
	move.w	#$0,fd_track.w                  ; from track 0
	bra.s	floppy_exerciser_format_side    ; formatted too
floppy_exerciser_cycle:
	move.b	$fffffa1f.w,cycle_random.w      ; MFP TADR, a random byte for this cycle's data
	move.w	#$0,fd_side.w                   ; side 0
	bsr.w	print_cycle                     ; the cycle shown and counted
	clr.w	write_errors.w                  ; no write errors
	clr.w	read_errors.w                   ; no read errors
floppy_exerciser_write_side:
	move.w	#$0,fd_track.w                  ; track 0
	move.l	#$2000,fd_buffer.w              ; the data at $2000
floppy_exerciser_write_track:
	bsr.w	write_track_checked             ; written
	tst.w	d0                              ; an error?
	beq.s	floppy_exerciser_write_esc      ; no
	cmpi.w	#$14,write_errors.w             ; 20 errors yet?
	blt.w	floppy_exerciser_write_esc      ; no
	bsr.w	ask_stopped                     ; stopped: RET goes on
	beq.s	floppy_exerciser_write_next     ; on
	bra.w	floppy_menu                     ; the floppy menu
floppy_exerciser_write_esc:
	bsr.w	check_esc                       ; ESC?
	bne.w	floppy_menu                     ; yes: the floppy menu
floppy_exerciser_write_next:
	addi.w	#$1,fd_track.w                  ; the next track
	cmpi.w	#$50,fd_track.w                 ; 80 done?
	bne.s	floppy_exerciser_write_track    ; no
	tst.w	fd_side.w                       ; side 1 done?
	bne.s	floppy_exerciser_read_pass      ; yes
	btst	#$1,exerciser_drive_type.w      ; double sided?
	beq.s	floppy_exerciser_read_pass      ; no
	move.w	#$1,fd_side.w                   ; side 1
	bra.s	floppy_exerciser_write_side     ; written too
floppy_exerciser_read_pass:
	move.w	#$0,fd_side.w                   ; side 0
floppy_exerciser_read_side:
	move.b	#$0,test_index_byte.w           ; the first of the track order
floppy_exerciser_read_track:
	lea	floppy_exerciser_tracks,a2      ; the mixed track order
	clr.l	d2
	move.b	test_index_byte.w,d2            ; the next
	move.b	0(a2,d2.w),fd_track+1.w         ; the track
	bsr.w	read_track_checked              ; read to $4000
	beq.s	floppy_exerciser_read_compare   ; read (Z)?
	cmpi.w	#$14,read_errors.w              ; 20 read errors yet?
	blt.s	floppy_exerciser_read_side      ; no: the read pass again from the start
	bsr.w	ask_stopped                     ; stopped: RET reads again
	beq.s	floppy_exerciser_read_side      ; from the start
	bra.w	floppy_menu                     ; the floppy menu
floppy_exerciser_read_compare:
	bsr.w	compare_sector_data             ; compared with what was written
	bsr.w	check_esc                       ; ESC?
	bne.w	floppy_menu                     ; yes: the floppy menu
	addi.b	#$1,test_index_byte.w           ; the next
	cmpi.b	#$50,test_index_byte.w          ; 80 done?
	bne.s	floppy_exerciser_read_track     ; no
	tst.w	fd_side.w                       ; side 1 done?
	bne.w	floppy_exerciser_cycle          ; yes: the next cycle
	btst	#$1,exerciser_drive_type.w      ; double sided?
	beq.w	floppy_exerciser_cycle          ; no: the next cycle
	move.w	#$1,fd_side.w                   ; side 1
	bra.s	floppy_exerciser_read_side      ; read too

;------------------------------------------------------------------------------
; floppy_copy_protect: choice 5, "Check Tracks 80-82" (writes the disk).  Tracks 80-82 of side 0 are
;  formatted and written, then read back: "Copy protect tracks PASS" (green) or the error and
;  "Copy protect tracks FAIL" (red); a key goes back to the floppy menu.
;------------------------------------------------------------------------------
floppy_copy_protect:	; from: floppy_menu_jump_table
	lea	msg_disk_a_or_b,a5              ; "Disk A or B?"
	bsr.w	print_string                    ; shown
	bsr.w	get_key                         ; a key
	cmp.b	#$41,d0                         ; 'A'?
	beq.s	floppy_copy_protect_start       ; yes
	cmp.b	#$42,d0                         ; 'B'?
	bne.w	floppy_menu                     ; no: the floppy menu
	move.w	#$1,fd_drive.w                  ; drive B
floppy_copy_protect_start:
	bsr.w	clear_screen                    ; the screen cleared
	lea	msg_check_tracks_80_82,a5       ; "Check Tracks 80-82"
	bsr.w	print_string                    ; shown
	move.w	#$0,fd_track.w                  ; track 0
	bsr.w	restore_drive                   ; to track 0
	move.w	#$50,fd_track.w                 ; track 80
floppy_copy_protect_write:
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; an error?
	bne.s	floppy_copy_protect_fail        ; yes
	bsr.w	write_track_checked             ; written
	tst.w	d0                              ; an error?
	bne.s	floppy_copy_protect_fail        ; yes
	addi.w	#$1,fd_track.w                  ; the next
	cmpi.w	#$53,fd_track.w                 ; to 82
	bne.s	floppy_copy_protect_write       ; no
	move.w	#$50,fd_track.w                 ; track 80
floppy_copy_protect_read:
	bsr.w	read_track_checked              ; read
	tst.w	d0                              ; an error?
	bne.s	floppy_copy_protect_fail        ; yes
	addi.w	#$1,fd_track.w                  ; the next
	cmpi.w	#$53,fd_track.w                 ; to 82
	bne.s	floppy_copy_protect_read        ; no
	lea	msg_copy_protect_pass,a5        ; "Copy protect tracks PASS"
	move.w	#$51,$ffff8240.w                ; palette 0, green
floppy_copy_protect_result:
	bsr.w	print_string                    ; shown
	bsr.w	get_key                         ; a key
	bra.w	floppy_menu                     ; the floppy menu
floppy_copy_protect_fail:
	bsr.w	print_floppy_error              ; the FDC error shown
	lea	msg_copy_protect_fail,a5        ; "Copy protect tracks FAIL"
	move.w	#$500,$ffff8240.w               ; palette 0, red
	bra.s	floppy_copy_protect_result

;------------------------------------------------------------------------------
; floppy_speed_test: choice 6, "Floppy disk speed test".  Timer A (/200, 8: 651 us) counts in $AB2 the
;  ticks from one index pulse to the next while the drive is kept seeking to track 0; each revolution is
;  shown in ms with the highest and lowest, red when outside 196-204 ms.  A key goes back to the floppy
;  menu; "Time-out waiting for index" when no index comes.
;------------------------------------------------------------------------------
floppy_speed_test:	; from: floppy_menu_jump_table
	bsr.w	clear_screen                    ; the screen cleared
	lea	msg_floppy_speed_test,a5        ; "Floppy disk speed test"
	bsr.w	print_string                    ; shown
	lea	msg_disk_a_or_b,a5              ; "Disk A or B?"
	bsr.w	print_string                    ; shown
	clr.w	fd_drive.w                      ; drive A
	bsr.w	get_key                         ; a key
	cmpi.b	#$42,d0                         ; 'B'?
	bne.w	floppy_speed_start              ; no
	move.w	#$1,fd_drive.w                  ; drive B
floppy_speed_start:
	bsr.w	clear_screen                    ; the screen cleared
	lea	msg_testing_speed,a5            ; "Testing speed", "Allowable range = 196 - 204 milliseconds/revolution"
	bsr.w	print_string                    ; shown
	move.w	#$0,d0                          ; column 0
	move.w	#$3,d1                          ; line 3
	bsr.w	set_cursor                      ; the cursor there
	lea	msg_speed_header,a5             ; "Max      Min      Current speed"
	bsr.w	print_string                    ; shown
	move.b	#$0,$fffffa19.w                 ; MFP TACR, timer A stopped
	move.b	#$8,$fffffa1f.w                 ; MFP TADR, 8 counts: 651 us
	lea	speed_timer_a,a2                ; the tick counter
	moveq	#13,d0                          ; interrupt 13: timer A
	bsr.w	mfp_install_handler             ; installed and enabled
	clr.w	fd_side.w                       ; side 0
	clr.w	fd_track.w                      ; track 0
	bsr.w	restore_drive                   ; to track 0
	clr.b	floppy_motor_watch.w            ; motor watch off
	move.w	#$0,speed_max.w                 ; the highest so far
	move.w	#$ffff,speed_min.w              ; the lowest so far
floppy_speed_loop:
	move.w	#$0,d7                          ; track 0
	bsr.w	floppy_seek_command             ; a seek: the motor kept on
	moveq	#22,d0                          ; column 22
	moveq	#4,d1                           ; line 4
	bsr.w	set_cursor                      ; the cursor there
	lea	keytop_left_arrow,a5            ; an arrow while it measures
	bsr.w	print_string                    ; shown
	move.b	#$7,$fffffa19.w                 ; MFP TACR, timer A running, /200
	bsr.w	wait_index_on                   ; wait for the index pulse
	tst.w	d5                              ; time-out?
	beq.w	floppy_speed_no_index           ; yes
	clr.w	speed_ticks.w                   ; the ticks counted from here
	bsr.w	wait_index_off                  ; wait for its end
	tst.w	d5                              ; time-out?
	beq.w	floppy_speed_no_index           ; yes
	bsr.w	wait_index_on                   ; wait for the next index pulse
	move.w	speed_ticks.w,-(sp)             ; one revolution's ticks
	bsr.w	wait_index_off                  ; wait for its end
	moveq	#22,d0                          ; column 22
	moveq	#4,d1                           ; line 4
	bsr.w	set_cursor                      ; the cursor there
	bsr.w	print_space                     ; the arrow cleared
	clr.b	$fffffa19.w                     ; MFP TACR, timer A stopped
	move.w	(sp)+,d0                        ; the ticks
	bsr.w	ticks_to_ms                     ; made ms, in BCD
	cmp.w	#$205,d1                        ; 205 ms or more?
	bge.w	floppy_speed_bad                ; yes: bad
	cmp.w	#$195,d1                        ; more than 195 ms?
	bgt.w	floppy_speed_max                ; yes: good
floppy_speed_bad:
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
floppy_speed_max:
	cmp.w	speed_max.w,d1                  ; above the highest?
	bls.w	floppy_speed_min                ; no
	move.w	d1,speed_max.w                  ; the highest
floppy_speed_min:
	cmp.w	speed_min.w,d1                  ; below the lowest?
	bhi.w	floppy_speed_show               ; no
	move.w	d1,speed_min.w                  ; the lowest
floppy_speed_show:
	move.w	d1,-(sp)                        ; this one kept
	moveq	#0,d0                           ; column 0
	moveq	#4,d1                           ; line 4
	bsr.w	set_cursor                      ; the cursor there
	move.w	speed_max.w,d1                  ; the highest
	bsr.w	print_hex_word                  ; shown
	bsr.w	put_tab                         ; a tab
	move.w	speed_min.w,d1                  ; the lowest
	bsr.w	print_hex_word                  ; shown
	bsr.w	put_tab                         ; a tab
	move.w	(sp)+,d1                        ; this one
	bsr.w	print_hex_word                  ; shown
	bsr.w	print_newline                   ; a new line
	bsr.w	key_waiting                     ; a key?
	tst.w	d0
	beq.w	floppy_speed_loop               ; no: again
floppy_speed_quit:
	bsr.w	get_key                         ; the key taken
	moveq	#13,d0                          ; timer A
	bsr.w	mfp_disable_interrupt           ; disabled
	bsr.w	restore_drive                   ; to track 0
	bra.w	floppy_menu                     ; the floppy menu
floppy_speed_no_index:
	lea	msg_index_time_out,a5           ; "Time-out waiting for index"
	bsr.w	print_string                    ; shown
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	bra.s	floppy_speed_quit

;------------------------------------------------------------------------------
; ticks_to_ms: timer A ticks (651 us each) made milliseconds, rounded, in BCD.
;  In: d0 the ticks.  Out: d1 the BCD milliseconds.  Changes d0, d2, d3.
;------------------------------------------------------------------------------
ticks_to_ms:	; from: floppy_speed_test
	andi.w	#$ffff,d0                       ; the ticks
	move.l	#$28b,d2                        ; 651 us each
	mulu.w	d2,d0                           ; in us
	move.l	#$3e8,d2                        ; /1000
	divu.w	d2,d0                           ; ms
	bsr.w	ticks_to_ms_round               ; rounded
	bsr.w	word_to_bcd                     ; in BCD
	rts

;------------------------------------------------------------------------------
; ticks_to_ms_round: rounds the quotient of a divide by d2.  In: d0 remainder:quotient, d2 the divisor.
;  Out: d0 the rounded quotient.  Changes d2.
;------------------------------------------------------------------------------
ticks_to_ms_round:	; from: ticks_to_ms
	swap	d0                              ; the remainder
	lsr.w	#1,d2                           ; half the divisor
	cmp.w	d2,d0                           ; below it?
	blt.w	ticks_to_ms_down                ; yes: down
	swap	d0                              ; the quotient
	addi.w	#$1,d0                          ; up
ticks_to_ms_done:
	andi.l	#$ffff,d0                       ; only the quotient
	rts
ticks_to_ms_down:
	swap	d0                              ; the quotient
	bra.s	ticks_to_ms_done

;------------------------------------------------------------------------------
; speed_timer_a: timer A routine of the speed test: one more tick.
;------------------------------------------------------------------------------
speed_timer_a:	; from: floppy_speed_test
	addi.w	#$1,speed_ticks.w               ; one more
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA, timer A served
	rte

;------------------------------------------------------------------------------
; wait_index_on: waits until the FDC status shows the index pulse.  Needs a6 the DMA mode register.
;  Out: d5 0 on a time-out.  Changes d0, d5.
;------------------------------------------------------------------------------
wait_index_on:	; from: floppy_speed_test
	move.l	#$186a0,d5                      ; 100000 tries
wait_index_on_loop:
	move.w	#$80,(a6)                       ; FDC status
	bsr.w	fdc_read_d0                     ; read
	btst	#$1,d0                          ; index?
	bne.w	wait_index_on_done              ; yes
	subq.w	#1,d5                           ; more tries?
	bne.s	wait_index_on_loop
wait_index_on_done:
	rts

;------------------------------------------------------------------------------
; wait_index_off: waits until the FDC status no longer shows the index pulse.  Needs a6 the DMA mode
;  register.  Out: d5 0 on a time-out.  Changes d0, d5.
;------------------------------------------------------------------------------
wait_index_off:	; from: floppy_speed_test
	move.l	#$186a0,d5                      ; 100000 tries
wait_index_off_loop:
	move.w	#$80,(a6)                       ; FDC status
	bsr.w	fdc_read_d0                     ; read
	btst	#$1,d0                          ; index gone?
	beq.w	wait_index_off_done             ; yes
	subq.w	#1,d5                           ; more tries?
	bne.s	wait_index_off_loop
wait_index_off_done:
	rts

;------------------------------------------------------------------------------
; floppy_install_drives: choice 7, "Install disk drives": asks the type of drive A and B (1 single sided,
;  2 double sided, 3 high density, any other key none) into $27A/$27B, then the floppy menu.
;------------------------------------------------------------------------------
floppy_install_drives:	; from: floppy_menu_jump_table
	bsr.w	clear_screen                    ; the screen cleared
	lea	msg_drive_type_menu,a5          ; "1  Single sided" ... "Any other key will de-install this drive."
	bsr.w	print_string                    ; shown
	lea	msg_disk_a,a5                   ; "Disk A: "
	bsr.w	ask_drive_type                  ; asked
	move.b	d2,drive_a_type.w               ; drive A's type
	lea	msg_disk_b,a5                   ; "Disk B: "
	bsr.w	ask_drive_type                  ; asked
	move.b	d2,drive_b_type.w               ; drive B's type
	bra.w	floppy_menu                     ; the floppy menu

;------------------------------------------------------------------------------
; detect_drive_sides: finds the sides of drive $AAA quietly (by writing track 79).
;  Out: d0 0 not found or not writable, 1 single sided, 2 double sided.
;------------------------------------------------------------------------------
detect_drive_sides:	; from: floppy_exerciser
	bsr.w	restore_drive                   ; to track 0
	bne.s	detect_drive_sides_none         ; no drive
	move.b	#$1,floppy_quiet.w              ; quiet
	bsr.w	probe_drive_sides               ; its sides
	clr.b	floppy_quiet.w                  ; errors shown again
	rts
detect_drive_sides_none:
	clr.w	d0                              ; none
	rts

;------------------------------------------------------------------------------
; detect_drive_types: "Checking drive type...": finds which drives answer and, by writing track 79,
;  whether drive A is high density and each drive single or double sided.  Out: $27A/$27B the types
;  (bit 7 found, bit 6 high density, bit 1 double sided, bit 0 single sided), $676/$677 1 when a drive
;  cannot be written ("Cannot write drive A/B", red); "No floppies " when none answers.
;  Changes d0-d7, a0-a6.
;------------------------------------------------------------------------------
detect_drive_types:	; from: floppy_menu_jump_table, floppy_quick_test
	lea	msg_checking_drive_type,a5      ; "Checking drive type..."
	bsr.w	show_status                     ; on the top line
	clr.b	drive_a_type.w                  ; no drive A
	clr.b	drive_b_type.w                  ; no drive B
	clr.w	fd_drive.w                      ; drive A
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	bne.s	detect_drive_b                  ; no
	bset	#$7,drive_a_type.w              ; drive A found
detect_drive_b:
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	bne.s	detect_drive_any                ; no
	bset	#$7,drive_b_type.w              ; drive B found
detect_drive_any:
	tst.b	drive_a_type.w                  ; drive A?
	bne.s	detect_drive_a_type             ; yes
	tst.b	drive_b_type.w                  ; drive B?
	bne.s	detect_drive_b_type             ; yes
	lea	msg_no_floppies,a5              ; "No floppies "
	bsr.w	show_status                     ; on the top line
	move.l	#vbl_handler,$70.w              ; VBL vector, the VBL routine back
	rts
detect_drive_a_type:
	move.b	#$1,floppy_quiet.w              ; quiet
	clr.w	fd_drive.w                      ; drive A
	move.w	#$3,$ffff860e.w                 ; high density
	bset	#$6,drive_a_type.w              ; tried as high density
	bsr.w	probe_high_density              ; 18 sectors written and read?
	beq.s	detect_drive_a_sides            ; yes
	move.w	#$0,$ffff860e.w                 ; no: double density
	bclr	#$6,drive_a_type.w              ; not high density
detect_drive_a_sides:
	bsr.w	probe_drive_sides               ; its sides
	tst.w	d0                              ; not writable?
	beq.s	detect_drive_a_unwritable       ; yes
	cmp.b	#$1,d0                          ; single sided?
	beq.s	detect_drive_a_single           ; yes
	ori.b	#$3,drive_a_type.w              ; double sided
	bra.s	detect_drive_b_type             ; on to drive B
detect_drive_a_single:
	ori.b	#$1,drive_a_type.w              ; single sided
	bra.s	detect_drive_b_type
detect_drive_a_unwritable:
	lea	msg_cannot_write_drive_a,a5     ; "Cannot write drive A"
	bsr.w	print_string                    ; shown
	move.b	#$1,test_errors.w               ; drive A error
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	ori.b	#$80,drive_a_type.w             ; found only
detect_drive_b_type:
	btst	#$7,drive_b_type.w              ; drive B found?
	beq.s	detect_drive_types_done         ; no
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	probe_drive_sides               ; its sides
	tst.w	d0                              ; not writable?
	beq.s	detect_drive_b_unwritable       ; yes
	cmp.b	#$1,d0                          ; single sided?
	beq.s	detect_drive_b_single           ; yes
	move.b	#$3,drive_b_type.w              ; double sided
	bra.s	detect_drive_types_done         ; done
detect_drive_b_single:
	move.b	#$1,drive_b_type.w              ; single sided
	bra.s	detect_drive_types_done
detect_drive_b_unwritable:
	lea	msg_cannot_write_drive_b,a5     ; "Cannot write drive B"
	bsr.w	print_string                    ; shown
	move.b	#$1,test_errors_high.w          ; drive B error
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	move.b	#$80,drive_b_type.w             ; found only
detect_drive_types_done:
	clr.b	floppy_quiet.w                  ; errors shown again
	bsr.w	clear_status_line               ; the top line cleared
	rts

;------------------------------------------------------------------------------
; ask_drive_type: shows a5 ("Disk A: "/"Disk B: ") and reads the type key.
;  Out: d2 1 single sided ('1'), 3 double sided ('2'), $43 high density ('3'), 0 any other key.
;  Changes d0, d1, d2.
;------------------------------------------------------------------------------
ask_drive_type:	; from: floppy_install_drives
	bsr.w	print_string                    ; the drive's name
	clr.b	d2                              ; none
	bsr.w	get_key                         ; a key
	cmpi.b	#$31,d0                         ; '1'?
	bne.s	ask_drive_type_two              ; no
	move.b	#$1,d2                          ; single sided
	move.w	d0,d1                           ; echoed
	bsr.w	put_char
	bra.s	ask_drive_type_done             ; done
ask_drive_type_two:
	cmpi.b	#$32,d0                         ; '2'?
	bne.s	ask_drive_type_three            ; no
	move.b	#$3,d2                          ; double sided
	move.w	d0,d1                           ; echoed
	bsr.w	put_char
ask_drive_type_three:
	cmpi.b	#$33,d0                         ; '3'?
	bne.s	ask_drive_type_done             ; no
	move.b	#$43,d2                         ; high density, double sided
	move.w	d0,d1                           ; echoed
	bsr.w	put_char
ask_drive_type_done:
	bsr.w	print_newline                   ; a new line
	rts

;------------------------------------------------------------------------------
; show_floppy_status: the status line of drive $AAA (line 0 drive A, 1 drive B) at column 22: a5
;  ("Formatting", "Writing", "Reading"), the side and the track; the cursor kept.  In: a5.
;------------------------------------------------------------------------------
show_floppy_status:	; from: floppy_alignment, format_track_checked, write_track_checked, read_track_checked
	bsr.w	save_cursor                     ; the cursor kept
	moveq	#22,d0                          ; column 22
	move.w	fd_drive.w,d1                   ; the drive's line
	bsr.w	set_cursor                      ; the cursor there
	bsr.w	print_string                    ; the text
	bsr.w	print_side_number               ; the side
	bsr.w	print_track_number              ; the track
	bsr.w	print_newline                   ; a new line
	bsr.w	restore_cursor                  ; the cursor back
	rts

;------------------------------------------------------------------------------
; print_sector_number: "Sector " and the sector $B7C in decimal.
;------------------------------------------------------------------------------
print_sector_number:	; from: compare_sector_data
	lea	msg_sector,a5                   ; "Sector "
	bsr.w	print_string                    ; shown
	move.w	fd_cur_sector.w,d0              ; the sector
	bsr.w	word_to_bcd                     ; in BCD
	bsr.w	print_hex_byte                  ; shown
	bsr.w	print_space                     ; a space
	rts

;------------------------------------------------------------------------------
; print_track_number: "Track " and the track $AA4 in decimal, then 10 spaces.
;------------------------------------------------------------------------------
print_track_number:	; from: floppy_interchange, show_floppy_status, print_drive_side_track, compare_sector_data
	lea	msg_track,a5                    ; "Track "
	bsr.w	print_string                    ; shown
	move.w	fd_track.w,d0                   ; the track
	bsr.w	word_to_bcd                     ; in BCD
	bsr.w	print_hex_byte                  ; shown
	moveq	#10,d1                          ; 10 spaces
	bsr.w	print_spaces
	rts

;------------------------------------------------------------------------------
; print_side_number: "Side " and the side $AA2.
;------------------------------------------------------------------------------
print_side_number:	; from: show_floppy_status, print_drive_side_track
	lea	msg_side,a5                     ; "Side "
	bsr.w	print_string                    ; shown
	move.w	fd_side.w,d1                    ; the side
	bsr.w	print_hex_digit                 ; shown
	bsr.w	print_space                     ; a space
	rts

;------------------------------------------------------------------------------
; print_drive_name: "Disk A: " or "Disk B: " for the drive $AAA.
;------------------------------------------------------------------------------
print_drive_name:	; from: floppy_interchange, print_drive_side_track
	lea	msg_disk_b,a5                   ; "Disk B: "
	tst.w	fd_drive.w                      ; drive B?
	bne.s	print_drive_name_text           ; yes
	lea	msg_disk_a,a5                   ; "Disk A: "
print_drive_name_text:
	bsr.w	print_string                    ; shown
	rts

;------------------------------------------------------------------------------
; probe_high_density: track 79 side 0 formatted with 18 sectors (drive A in high density) and read.
;  Out: Z set when both worked.
;------------------------------------------------------------------------------
probe_high_density:	; from: detect_drive_types
	move.w	#$e5e5,fd_fill_word.w           ; format fill
	move.w	#$1,fd_interleave.w             ; $AA0 1
	move.w	#$4f,fd_track.w                 ; track 79
	move.w	#$0,fd_side.w                   ; side 0
	bsr.w	set_sector_count                ; 9 or 18 sectors
	bsr.w	floppy_format_track             ; formatted
	bne.s	probe_high_density_done         ; failed
	bsr.w	read_sectors                    ; read
probe_high_density_done:
	rts

;------------------------------------------------------------------------------
; probe_drive_sides: finds a drive's sides on track 79: formats and writes side 0, then probe_side_one.
;  Out: d0 0 not writable, 1 single sided, 2 double sided.
;------------------------------------------------------------------------------
probe_drive_sides:	; from: detect_drive_sides, detect_drive_types
	move.w	#$e5e5,fd_fill_word.w           ; format fill
	move.w	#$1,fd_interleave.w             ; $AA0 1
	move.w	#$4f,fd_track.w                 ; track 79
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$9,fd_count.w                  ; 9 sectors
	bsr.w	set_sector_count                ; 9 or 18 sectors
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; failed?
	beq.s	probe_drive_write               ; no
	moveq	#0,d0                           ; not writable
	rts
probe_drive_write:
	bsr.w	build_sector_data               ; the sector data
	move.w	#$1,fd_sector.w                 ; sector 1
	move.w	#$1,fd_count.w                  ; one sector
	bsr.w	floppy_write_sectors            ; written
	tst.w	d0                              ; failed?
	beq.s	probe_side_one                  ; no: side 1 tried
	moveq	#0,d0                           ; not writable
	rts

;------------------------------------------------------------------------------
; probe_side_one: formats track 79 side 1, then reads sector 1 of side 0: a single sided drive formats
;  side 0 again and the read fails.  Out: d0 1 single sided, 2 double sided.
;------------------------------------------------------------------------------
probe_side_one:	; from: probe_drive_sides, quick_test_drive
	move.w	#$1,fd_side.w                   ; side 1
	move.w	#$4f,fd_track.w                 ; track 79
	bsr.w	set_sector_count                ; 9 or 18 sectors
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; failed?
	bne.s	probe_side_one_single           ; yes: single sided
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$1,fd_count.w                  ; one sector
	bsr.w	read_track_checked              ; read
	tst.w	d0                              ; failed?
	bne.s	probe_side_one_single           ; yes: single sided
	moveq	#2,d0                           ; double sided
	rts
probe_side_one_single:
	moveq	#1,d0                           ; single sided
	rts

;------------------------------------------------------------------------------
; quick_test_drive: the quick test of drive $AAA: to track 0, tracks 0, 1 and 79 formatted, written, read
;  and compared on side 0, and on a double sided drive side 1 checked ("FC Side select error--single
;  sided drive" when it fails with an FDC error).  Out: $676/$677 (by the drive) 1 on an error,
;  "F0 Not selected" when the drive does not answer.
;------------------------------------------------------------------------------
quick_test_drive:	; from: floppy_quick_test
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	bne.s	quick_test_not_selected         ; no
	move.w	#$0,fd_side.w                   ; side 0
	bsr.w	quick_test_tracks               ; tracks 0, 1, 79
	bne.s	quick_test_drive_done           ; failed
	lea	drive_a_type.w,a0               ; the drive types
	move.w	fd_drive.w,d0                   ; this drive
	move.b	0(a0,d0.w),d1                   ; its type
	btst	#$1,d1                          ; double sided?
	beq.s	quick_test_drive_done           ; no: done
	bsr.s	probe_side_one                  ; side 1 tried
	cmpi.b	#$2,d0                          ; double sided?
	beq.s	quick_test_drive_done           ; yes: done
	cmpi.b	#$0,d0                          ; not writable? (never 0 here)
	beq.s	quick_test_drive_fail           ; yes
	cmpi.w	#$0,fd_error.w                  ; an FDC error?
	beq.s	quick_test_drive_fail           ; no
	lea	msg_side_select_error,a5        ; "FC Side select error--single sided drive"
	bsr.w	print_string                    ; shown
quick_test_drive_fail:
	lea	test_errors.w,a0                ; the drives' errors
	clr.l	d0                              ; this drive's
	move.w	fd_drive.w,d0
	move.b	#$1,0(a0,d0.w)                  ; failed
quick_test_drive_done:
	rts
quick_test_not_selected:
	tst.w	fd_drive.w                      ; drive B?
	bne.s	quick_test_b_not_selected       ; yes
	bsr.w	print_a_not_selected            ; "Disk A: F0 Not selected "
	move.b	#$1,test_errors.w               ; drive A error
	rts
quick_test_b_not_selected:
	bsr.w	print_b_not_selected            ; "Disk B: F0 Not selected "
	move.b	#$1,test_errors_high.w          ; drive B error
	rts

;------------------------------------------------------------------------------
; quick_test_tracks: tracks 0, 1 and 79 of side $AA2 formatted and written, then read and compared.
;  Out: d0 0 and Z when all good; NE after a format, write or read error or a stopped compare.
;------------------------------------------------------------------------------
quick_test_tracks:	; from: quick_test_drive
	move.w	#$1,fd_interleave.w             ; $AA0 1
	bsr.w	set_sector_count                ; 9 or 18 sectors
	clr.b	pass_count.w                    ; the first track
	moveq	#0,d0
quick_test_write_track:
	lea	floppy_quick_test_tracks,a0     ; tracks 0, 1, 79
	move.b	pass_count.w,d0                 ; the next
	move.b	0(a0,d0.w),fd_track+1.w         ; the track
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; failed?
	beq.s	quick_test_write_data           ; no
	rts
quick_test_write_data:
	bsr.w	build_sector_data               ; the sector data
	move.w	#$1,fd_sector.w                 ; sector 1
	bsr.w	write_track_checked             ; written
	tst.w	d0                              ; failed?
	beq.s	quick_test_write_next           ; no
	rts
quick_test_write_next:
	addi.b	#$1,pass_count.w                ; the next track
	cmpi.b	#$3,pass_count.w                ; three done?
	bne.s	quick_test_write_track          ; no
	clr.b	pass_count.w                    ; the first track
	moveq	#0,d0
quick_test_read_track:
	lea	floppy_quick_test_tracks,a0     ; tracks 0, 1, 79
	move.b	pass_count.w,d0                 ; the next
	move.b	0(a0,d0.w),fd_track+1.w         ; the track
	move.l	#$4000,fd_buffer.w              ; read to $4000
	clr.w	floppy_retry.w                  ; no retry yet
	bsr.w	read_track_checked              ; read
	tst.w	d0                              ; failed?
	beq.s	quick_test_read_compare         ; no
	rts
quick_test_read_compare:
	bsr.w	compare_sector_data             ; compared
	bne.s	print_drive_side_track          ; stopped: where it was shown
	addi.b	#$1,pass_count.w                ; the next track
	cmpi.b	#$3,pass_count.w                ; three done?
	bne.s	quick_test_read_track           ; no
	rts

;------------------------------------------------------------------------------
; print_drive_side_track: the drive name, side and track.  Out: Z clear.
;------------------------------------------------------------------------------
print_drive_side_track:	; from: floppy_alignment, quick_test_tracks, random_track_test, print_floppy_error
	bsr.w	print_drive_name                ; "Disk A: "/"Disk B: "
	bsr.w	print_side_number               ; the side
	bsr.w	print_track_number              ; the track
	move.w	#$0,ccr                         ; Z clear: an error for the caller
	rts

;------------------------------------------------------------------------------
; random_track_test: a random track of side 0 (timer A's count, 0-63) formatted, written, read and
;  compared.  A failed format tries another track, but the try count is set again each time, so it
;  never runs out.  Out: $676/$677 (by the drive) bit 2 after a write or read error.
;------------------------------------------------------------------------------
random_track_test:	; from: floppy_quick_test
	move.b	#$3,test_index_byte.w           ; three tries
	move.b	$fffffa1f.w,d0                  ; MFP TADR, timer A's count: random
	andi.w	#$3f,d0                         ; 0-63
	cmpi.b	#$4f,d0                         ; above 79? (never)
	bgt.s	random_track_test               ; yes
	move.w	d0,fd_track.w                   ; the track
	move.w	#$1,fd_sector.w                 ; sector 1
	bsr.w	set_sector_count                ; 9 or 18 sectors
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; failed?
	beq.s	random_track_write              ; no
	subi.b	#$1,test_index_byte.w           ; one try less
	bne.s	random_track_test               ; another track
random_track_write:
	bsr.w	build_sector_data               ; the sector data
	bsr.w	write_track_checked             ; written
	tst.w	d0                              ; failed?
	bne.s	random_track_failed             ; yes
	move.l	#$4000,fd_buffer.w              ; read to $4000
	bsr.w	read_track_checked              ; read
	tst.w	d0                              ; failed?
	bne.s	random_track_failed             ; yes
	bsr.w	compare_sector_data             ; compared
	bne.s	print_drive_side_track          ; stopped: where it was shown
	rts
random_track_failed:
	tst.w	fd_drive.w                      ; drive B?
	beq.s	random_track_failed_a           ; no
	bset	#$2,test_errors_high.w          ; drive B error bit 2
	rts
random_track_failed_a:
	bset	#$2,test_errors.w               ; drive A error bit 2
	rts

;------------------------------------------------------------------------------
; set_sector_count: 9 sectors a track, 18 on drive A when it is high density.
;------------------------------------------------------------------------------
set_sector_count:                               ; from: probe_high_density, probe_drive_sides, probe_side_one,
                                                ;   quick_test_tracks, random_track_test
	move.w	#$9,fd_count.w                  ; 9 sectors
	tst.w	fd_drive.w                      ; drive B?
	bne.s	set_sector_count_done           ; yes
	btst	#$6,drive_a_type.w              ; drive A high density?
	beq.s	set_sector_count_done           ; no
	move.w	#$12,fd_count.w                 ; 18 sectors
set_sector_count_done:
	rts

;------------------------------------------------------------------------------
; print_floppy_error: shows the floppy error code $B96 as its text with the drive, side and track; for
;  -16 "Bad Sector: " with the list of bad sectors at $B82.  Nothing when it is 0.
;  Out: d0 the code.  Changes d1, a2, a5.
;------------------------------------------------------------------------------
print_floppy_error:                             ; from: floppy_interchange, floppy_copy_protect, format_track_checked,
                                                ;   write_track_checked, read_track_checked
	move.w	fd_error.w,d0                   ; the error code
	tst.w	d0                              ; none?
	beq.w	floppy_error_done               ; yes
	dc.w	$0c00,$fffa                     ; cmpi.b	#$fa,d0, -6?
	bne.s	floppy_error_not_seek           ; no
	lea	msg_seek_error,a5               ; "F4 Seek error "
	bra.w	floppy_error_print              ; shown
floppy_error_not_seek:
	dc.w	$0c00,$ffef                     ; cmpi.b	#$ef,d0, -17?
	bne.s	floppy_error_not_dma            ; no
	lea	msg_floppy_dma_error,a5         ; "F7 DMA error "
	bra.w	floppy_error_print              ; shown
floppy_error_not_dma:
	dc.w	$0c00,$fff8                     ; cmpi.b	#$f8,d0, -8?
	bne.s	floppy_error_not_rnf            ; no
	lea	msg_record_not_found,a5         ; "FA Record not found "
	bra.w	floppy_error_print              ; shown
floppy_error_not_rnf:
	dc.w	$0c00,$fffc                     ; cmpi.b	#$fc,d0, -4?
	bne.s	floppy_error_not_crc            ; no
	lea	msg_crc_error,a5                ; "F9 CRC error "
	bra.s	floppy_error_print              ; shown
floppy_error_not_crc:
	dc.w	$0c00,$ffee                     ; cmpi.b	#$ee,d0, -18?
	bne.s	floppy_error_not_count          ; no
	lea	msg_floppy_dma_count_error,a5   ; "F8 DMA count error "
	bra.s	floppy_error_print              ; shown
floppy_error_not_count:
	dc.w	$0c00,$fffe                     ; cmpi.b	#$fe,d0, -2?
	bne.s	floppy_error_not_ready          ; no
	lea	msg_drive_not_ready,a5          ; "FD Drive not ready "
	bra.s	floppy_error_print              ; shown
floppy_error_not_ready:
	dc.w	$0c00,$fff3                     ; cmpi.b	#$f3,d0, -13?
	bne.s	floppy_error_not_protect        ; no
	lea	msg_write_protected,a5          ; "F5 Write Protected "
	bra.s	floppy_error_print              ; shown
floppy_error_not_protect:
	dc.w	$0c00,$fff1                     ; cmpi.b	#$f1,d0, -15?
	bne.s	floppy_error_not_lost           ; no
	lea	msg_lost_data,a5                ; "FB Lost data "
	bra.s	floppy_error_print              ; shown
floppy_error_not_lost:
	dc.w	$0c00,$fff5                     ; cmpi.b	#$f5,d0, -11?
	bne.s	floppy_error_not_read           ; no
	lea	msg_error_reading,a5            ; "Error reading"
	bra.s	floppy_error_print              ; shown
floppy_error_not_read:
	dc.w	$0c00,$fff0                     ; cmpi.b	#$f0,d0, -16?
	bne.s	floppy_error_write              ; no
	lea	msg_bad_sector,a5               ; "Bad Sector: "
	bsr.w	print_string                    ; shown
	bsr.w	print_drive_side_track          ; where
	lea	msg_sector,a5                   ; "Sector "
	bsr.w	print_string                    ; shown
	movea.l	fd_cur_buffer.w,a2              ; the bad sector list
floppy_error_bad_sector_list:
	move.w	(a2)+,d1                        ; the next
	beq.s	floppy_error_newline            ; 0 ends it
	bsr.w	print_hex_byte                  ; shown
	bsr.w	print_space                     ; a space
	bra.s	floppy_error_bad_sector_list    ; on
floppy_error_write:
	lea	msg_error_writing,a5            ; any other: "Error writing"
floppy_error_print:
	bsr.w	print_string                    ; the error shown
	bsr.w	print_drive_side_track          ; where
floppy_error_newline:
	bsr.w	print_newline                   ; a new line
floppy_error_done:
	move.w	fd_error.w,d0                   ; the code
	rts

;------------------------------------------------------------------------------
; build_sector_data: nine 512-byte test sectors at $2000.  Each starts with an ID byte (the cycle's low 6
;  bits, bit 7 drive B, bit 6 side 1, one more each sector), the track, the first sector and the cycle's
;  random byte $299, then 254 words counting up from $BDC6.  Changes d0-d4, a0.
;------------------------------------------------------------------------------
build_sector_data:                              ; from: probe_drive_sides, quick_test_tracks, random_track_test,
                                                ;   compare_sector_data, write_track_checked
	movea.l	#$2000,a0                       ; the buffer
	move.w	#$bdc6,d4                       ; the first data word
	move.b	fd_sector+1.w,d1                ; the first sector
	move.b	test_cycle+3.w,d0               ; the cycle
	andi.b	#$3f,d0                         ; its low 6 bits
	tst.w	fd_drive.w                      ; drive B?
	beq.s	build_sector_data_side          ; no
	bset	#$7,d0                          ; bit 7: drive B
build_sector_data_side:
	tst.w	fd_side.w                       ; side 1?
	beq.s	build_sector_data_sectors       ; no
	bset	#$6,d0                          ; bit 6: side 1
build_sector_data_sectors:
	moveq	#8,d2                           ; 9 sectors
build_sector_data_sector:
	move.l	#$fd,d3                         ; 254 words
	move.b	d0,(a0)+                        ; the ID byte
	move.b	fd_track.w,(a0)+                ; the track
	move.b	d1,(a0)+                        ; the first sector
	move.b	cycle_random.w,(a0)+            ; the random byte
build_sector_data_words:
	move.w	d4,(a0)+                        ; a data word
	add.w	#$1,d4                          ; the next value
	dbra	d3,build_sector_data_words      ; the sector's words
	addq.w	#1,d0                           ; the next ID
	dbra	d2,build_sector_data_sector     ; the next sector
	rts

;------------------------------------------------------------------------------
; fill_buffer_aa: the 9-sector buffer at $2000 filled with $AA (drive A's interchange data).
;------------------------------------------------------------------------------
fill_buffer_aa:	; from: floppy_interchange
	move.w	#$aaaa,d1                       ; $AA
	bra.s	fill_buffer_byte

;------------------------------------------------------------------------------
; fill_buffer_bb: the 9-sector buffer at $2000 filled with $BB (drive B's interchange data).
;------------------------------------------------------------------------------
fill_buffer_bb:	; from: floppy_interchange
	move.w	#$bbbb,d1                       ; $BB
fill_buffer_byte:	; from: fill_buffer_aa
	move.l	#$11ff,d0                       ; 4608 bytes
	lea	$2000.w,a0                      ; from $2000
fill_buffer_loop:
	move.b	d1,(a0)+                        ; a byte
	dbra	d0,fill_buffer_loop             ; more?
	rts

;------------------------------------------------------------------------------
; compare_sector_data: the sectors read at $4000 compared with the data built again at $2000.  Each
;  difference: $676 bit 0 (whichever drive), red, "F6 Read compare error " with the two words, the track
;  and the sector; a key waiting then stops it.  Out: Z when it reached the end.  Changes d0-d4, a0, a1.
;------------------------------------------------------------------------------
compare_sector_data:	; from: floppy_exerciser, quick_test_tracks, random_track_test
	bsr.s	build_sector_data               ; the data written, built again
	lea	$2000.w,a0                      ; written
	lea	$4000.w,a1                      ; read
compare_sector_data_loop:
	cmpm.w	(a0)+,(a1)+                     ; the same?
	beq.s	compare_sector_data_next        ; yes
	bset	#$0,test_errors.w               ; error bit 0 of drive A
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	lea	msg_read_compare_error,a5       ; "F6 Read compare error "
	bsr.w	print_string                    ; shown
	suba.l	#$2,a0                          ; back to the words
	suba.l	#$2,a1
	move.w	(a0)+,d1                        ; written
	bsr.w	print_hex_word                  ; shown
	bsr.w	print_space                     ; a space
	move.w	(a1)+,d1                        ; read
	bsr.w	print_hex_word                  ; shown
	bsr.w	print_space                     ; a space
	bsr.w	print_track_number              ; the track
	bsr.w	print_sector_number             ; the sector
	bsr.w	print_newline                   ; a new line
	movem.l	a0-a1,-(sp)                     ; kept
	bsr.w	key_waiting                     ; a key?
	movem.l	(sp)+,a0-a1                     ; back
	tst.w	d0                              ; a key?
	beq.s	compare_sector_data_next        ; no: go on
	rts                                     ; yes: stopped
compare_sector_data_next:
	cmpa.l	#$3200,a0                       ; 9 sectors done?
	blt.s	compare_sector_data_loop        ; no
	rts

;------------------------------------------------------------------------------
; format_track_checked: formats track $AA4 side $AA2 of drive $AAA, showing "Formatting".  A failure
;  marks the track bad (skipped by the write and read), shows the error, counts it in $B70, flags the
;  drive and steps it to track 0; quiet ($B72) it only returns.  A -16 with one bad sector is let
;  through.  Out: d0 0 when formatted, else the error code with Z clear.
;------------------------------------------------------------------------------
format_track_checked:                           ; from: floppy_interchange, floppy_exerciser, floppy_copy_protect,
                                                ;   probe_drive_sides, probe_side_one, quick_test_tracks, 1 more
	lea	msg_formatting,a5               ; "Formatting "
	bsr.w	show_floppy_status              ; the status line
	lea	bad_tracks.w,a2                 ; the bad track marks
	clr.l	d2                              ; the track
	move.w	fd_track.w,d2
	tst.w	fd_side.w                       ; side 1?
	beq.s	format_track_unmark             ; no
	add.w	#$50,d2                         ; side 1's marks 80 on
format_track_unmark:
	clr.b	0(a2,d2.w)                      ; not bad
	bsr.w	floppy_format_track             ; formatted
	tst.w	d0                              ; failed?
	beq.s	format_track_done               ; no
	tst.b	floppy_quiet.w                  ; quiet?
	beq.s	format_track_failed             ; no
	rts
format_track_failed:
	lea	bad_tracks.w,a2                 ; the bad track marks
	clr.l	d2                              ; the track
	move.w	fd_track.w,d2
	tst.w	fd_side.w                       ; side 1?
	beq.s	format_track_mark               ; no
	add.w	#$50,d2                         ; side 1's marks 80 on
format_track_mark:
	move.b	#$ff,0(a2,d2.w)                 ; marked bad
	bsr.w	print_floppy_error              ; the error shown
	move.w	fd_error.w,d0                   ; the error code
	cmpi.w	#$fff0,fd_error.w               ; bad sectors?
	bne.s	format_track_count_error        ; no
	movea.l	fd_cur_buffer.w,a2              ; the list
	adda.l	#$2,a2                          ; a second one?
	tst.w	(a2)
	beq.s	format_track_done               ; no: let through
format_track_count_error:
	bsr.w	flag_drive_error                ; this drive failed
	addi.w	#$1,format_errors.w             ; a format error counted
	move.w	d0,-(sp)                        ; the code kept
	bsr.w	restore_drive                   ; to track 0
	move.w	(sp)+,d0                        ; the code
	andi.b	#$1b,ccr                        ; Z clear: failed
format_track_done:
	rts

;------------------------------------------------------------------------------
; write_track_checked: writes the sectors at $2000 (built again first) to track $AA4 side $AA2 of drive
;  $AAA, showing "Writing", skipping a track marked bad.  A failure shows the error, counts it in $B6E
;  and tries once more: "Soft Error" when that works, else "Hard error" and the drive flagged.
;  Out: d0 0 when written, else the error code.
;------------------------------------------------------------------------------
write_track_checked:	; from: floppy_exerciser, floppy_copy_protect, quick_test_tracks, random_track_test
	move.l	#$2000,fd_buffer.w              ; the buffer
	clr.w	floppy_retry.w                  ; no retry yet
	lea	bad_tracks.w,a2                 ; the bad track marks
	clr.l	d2                              ; the track
	move.w	fd_track.w,d2
	tst.w	fd_side.w                       ; side 1?
	beq.s	write_track_check_mark          ; no
	add.w	#$50,d2                         ; side 1's marks 80 on
write_track_check_mark:
	tst.b	0(a2,d2.w)                      ; marked bad?
	bne.s	write_track_written             ; yes: skipped
	lea	msg_writing,a5                  ; "Writing    "
	bsr.w	show_floppy_status              ; the status line
	bsr.w	build_sector_data               ; the sector data
write_track_try:
	bsr.w	floppy_write_sectors            ; written
	tst.w	d0                              ; failed?
	beq.s	write_track_written             ; no
	bsr.w	print_floppy_error              ; the error shown
	move.w	d0,-(sp)                        ; the code kept
	bsr.w	restore_drive                   ; to track 0
	move.w	(sp)+,d0                        ; the code
	addi.w	#$1,write_errors.w              ; a write error counted
	tst.w	floppy_retry.w                  ; the retry failed too?
	beq.s	write_track_retry               ; no
	bsr.w	flag_drive_error                ; this drive failed
	lea	msg_hard_error,a5               ; "Hard error"
	bsr.w	print_string                    ; shown
	bra.s	write_track_done                ; done
write_track_retry:
	move.w	#$1,floppy_retry.w              ; retrying
	bra.s	write_track_try                 ; once more
write_track_written:
	tst.w	floppy_retry.w                  ; after a retry?
	beq.s	write_track_done                ; no
	lea	msg_soft_error,a5               ; "Soft Error"
	bsr.w	print_string                    ; shown
write_track_done:
	rts

;------------------------------------------------------------------------------
; read_track_checked: reads track $AA4 side $AA2 of drive $AAA to $4000, showing "Reading", skipping a
;  track marked bad.  A failure shows the error, counts it in $B6C and tries once more: "Soft Error"
;  when that works, else "Hard error" and the drive flagged; quiet ($B72) it only returns.
;  Out: d0 0 when read, else the error code.
;------------------------------------------------------------------------------
read_track_checked:                             ; from: floppy_interchange, floppy_exerciser, floppy_copy_protect,
                                                ;   probe_side_one, quick_test_tracks, random_track_test
	move.l	#$4000,fd_buffer.w              ; the buffer
	lea	bad_tracks.w,a2                 ; the bad track marks
	clr.l	d2                              ; the track
	move.w	fd_track.w,d2
	tst.w	fd_side.w                       ; side 1?
	beq.s	read_track_check_mark           ; no
	add.w	#$50,d2                         ; side 1's marks 80 on
read_track_check_mark:
	tst.b	0(a2,d2.w)                      ; marked bad?
	bne.s	read_track_read                 ; yes: skipped
	move.w	#$0,floppy_retry.w              ; no retry yet
	lea	msg_reading,a5                  ; "Reading    "
	bsr.w	show_floppy_status              ; the status line
read_track_try:
	bsr.w	read_sectors                    ; read
	tst.w	d0                              ; failed?
	beq.s	read_track_read                 ; no
	tst.b	floppy_quiet.w                  ; quiet?
	beq.s	read_track_failed               ; no
	rts
read_track_failed:
	move.w	d0,-(sp)                        ; the code kept
	bsr.w	print_floppy_error              ; the error shown
	bsr.w	restore_drive                   ; to track 0
	move.w	(sp)+,d0                        ; the code
	addi.w	#$1,read_errors.w               ; a read error counted
	tst.w	floppy_retry.w                  ; the retry failed too?
	beq.s	read_track_retry                ; no
	bsr.w	flag_drive_error                ; this drive failed
	lea	msg_hard_error,a5               ; "Hard error"
	bsr.w	print_string                    ; shown
	rts
read_track_retry:
	move.w	#$1,floppy_retry.w              ; retrying
	bra.s	read_track_try                  ; once more
read_track_read:
	clr.l	d0                              ; read
	tst.w	floppy_retry.w                  ; after a retry?
	beq.s	read_track_done                 ; no
	lea	msg_soft_error,a5               ; "Soft Error"
	bsr.w	print_string                    ; shown
read_track_done:
	rts

;------------------------------------------------------------------------------
; flag_drive_error: the drive $AAA's error byte ($676 A, $677 B) set to 1, the background red.
;------------------------------------------------------------------------------
flag_drive_error:	; from: format_track_checked, write_track_checked, read_track_checked
	movem.l	d0/a0,-(sp)                     ; kept
	lea	test_errors.w,a0                ; the drives' errors
	clr.l	d0                              ; this drive's
	move.w	fd_drive.w,d0
	move.b	#$1,0(a0,d0.w)                  ; failed
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	movem.l	(sp)+,d0/a0                     ; back
	rts

;------------------------------------------------------------------------------
; print_b_not_selected: "Disk B: F0 Not selected ", the background red.
;------------------------------------------------------------------------------
print_b_not_selected:	; from: floppy_interchange, floppy_exerciser, quick_test_drive
	lea	msg_disk_b,a5                   ; "Disk B: "
	bra.s	print_not_selected

;------------------------------------------------------------------------------
; print_a_not_selected: "Disk A: F0 Not selected ", the background red.
;------------------------------------------------------------------------------
print_a_not_selected:	; from: floppy_interchange, floppy_exerciser, quick_test_drive
	lea	msg_disk_a,a5                   ; "Disk A: "
print_not_selected:	; from: print_b_not_selected
	bsr.w	print_string                    ; shown
	lea	msg_not_selected,a5             ; "F0 Not selected "
	bsr.w	print_string                    ; shown
	bsr.w	print_newline                   ; a new line
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	rts

;------------------------------------------------------------------------------
; restore_drive: drive $AAA stepped to track 0 (a restore; when it fails, a seek to track 10 and another
;  restore).  The drive is deselected later by the VBL motor watch.  Out: d0 0 and Z when track 0 was
;  reached, else the error code (-6).
;------------------------------------------------------------------------------
restore_drive:                                  ; from: floppy_alignment, floppy_interchange, floppy_exerciser,
                                                ;   floppy_copy_protect, floppy_speed_test, detect_drive_sides, 5 more
	lea	fd_drive_a.w,a1                 ; drive A's head position
	tst.w	fd_drive.w                      ; drive B?
	beq.s	restore_drive_select            ; no
	lea	fd_drive_b.w,a1                 ; drive B's
restore_drive_select:
	move.w	#$3,2(a1)                       ; step rate 3
	clr.w	0(a1)                           ; track 0
	bsr.w	floppy_set_up                   ; the transfer set up
	bsr.w	floppy_select                   ; drive and side selected
	move.w	#$ff00,0(a1)                    ; the head position not known
	bsr.w	floppy_restore                  ; restore: at track 0?
	beq.s	restore_drive_result            ; yes
	moveq	#10,d7                          ; to track 10
	bsr.w	floppy_seek_d7                  ; sought
	bne.s	restore_drive_failed            ; failed
	bsr.w	floppy_restore                  ; restore again
restore_drive_result:
	beq.w	floppy_exit_ok                  ; done
restore_drive_failed:
	bra.w	floppy_exit_error               ; failed

;------------------------------------------------------------------------------
; read_alignment_track: reads the sectors of track $AA4 side $AA2 to $4000 with one multiple-sector read
;  ($90), for the alignment disk; only a time-out (-2) is an error, the status is not checked.
;  Out: d0 0 or the error code.
;------------------------------------------------------------------------------
read_alignment_track:	; from: floppy_alignment
	move.w	#$fff5,d0                       ; "Error reading" code
	move.l	#$4000,fd_buffer.w              ; to $4000
	bsr.w	floppy_set_up                   ; the transfer set up
	bsr.w	floppy_select                   ; drive and side selected
	bsr.w	floppy_seek_verify              ; to the track
	bne.w	floppy_exit_error               ; failed
	move.w	#$90,(a6)                       ; FIFO cleared, read
	move.w	#$190,(a6)
	nop
	move.w	#$90,(a6)                       ; sector count register
	move.w	fd_sectors_left.w,$ffff8604.w   ; DMA sector count / FDC access, the sectors
	move.w	#$80,(a6)                       ; FDC command register
	move.w	#$90,d7                         ; read multiple sectors
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; time-out count
	movea.l	fd_buffer_end.w,a2              ; the end address
read_alignment_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, the FDC done (GPIP5 low)?
	beq.s	read_alignment_done             ; yes
	subq.l	#1,d7                           ; time-out?
	bne.s	read_alignment_wait             ; no
	move.w	#$fffe,fd_error.w               ; -2: drive not ready
	bsr.w	floppy_force_interrupt          ; the FDC stopped
	bra.w	floppy_exit_error               ; failed
read_alignment_done:
	move.w	#$90,(a6)                       ; DMA status
	move.w	(a6),d0                         ; read
	move.w	#$80,(a6)                       ; FDC status
	bsr.w	fdc_read_d0                     ; read
	bra.w	floppy_exit_ok                  ; done

;------------------------------------------------------------------------------
; read_sectors: reads $B80 sectors from sector $B7C of track $AA4 side $AA2 of drive $AAA to $AAC, one
;  read command ($80) each, then checks the DMA address reached the end.  Out: d0 0, or the error code
;  in d0 and $B96: -2 time-out, -17 DMA error, -13/-8/-4/-15 from the FDC status, -18 DMA count.
;------------------------------------------------------------------------------
read_sectors:	; from: probe_high_density, read_track_checked
	move.w	#$fff5,d0                       ; "Error reading" code
	bsr.w	floppy_set_up                   ; the transfer set up
	bsr.w	floppy_select                   ; drive and side selected
	bsr.w	floppy_seek_verify              ; to the track
	bne.w	floppy_exit_error               ; failed
read_sectors_next:
	move.w	#$90,(a6)                       ; FIFO cleared, read
	move.w	#$190,(a6)
	nop
	move.w	#$90,(a6)                       ; sector count register
	move.w	fd_sectors_left.w,$ffff8604.w   ; DMA sector count / FDC access, the sectors left
	move.w	#$80,(a6)                       ; FDC command register
	move.w	#$80,d7                         ; read sector
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; time-out count
	movea.l	fd_buffer_end.w,a2              ; the end address
read_sectors_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, the FDC done (GPIP5 low)?
	beq.s	read_sectors_dma_status         ; yes
	subq.l	#1,d7                           ; time-out?
	bne.s	read_sectors_wait               ; no
	move.w	#$fffe,fd_error.w               ; -2: drive not ready
	bsr.w	floppy_force_interrupt          ; the FDC stopped
	bra.w	floppy_exit_error               ; failed
read_sectors_dma_status:
	move.w	#$90,(a6)                       ; DMA status
	move.w	(a6),d0                         ; read
	btst	#$0,d0                          ; no DMA error?
	bne.s	read_sectors_fdc_status         ; yes
	move.w	#$ffef,fd_error.w               ; -17: DMA error
	bra.w	floppy_exit_error               ; failed
read_sectors_fdc_status:
	move.w	#$80,(a6)                       ; FDC status
	bsr.w	fdc_read_d0                     ; read
	and.b	#$1c,d0                         ; record not found, CRC, lost data?
	beq.s	read_sectors_advance            ; no
	bsr.w	fdc_status_error                ; the code for it
	bra.w	floppy_exit_error               ; failed
read_sectors_advance:
	addq.w	#1,fd_cur_sector.w              ; the next sector
	addi.l	#$200,fd_cur_buffer.w           ; 512 bytes on
	subq.w	#1,fd_sectors_left.w            ; the last?
	beq.s	read_sectors_check_count        ; yes
	bsr.w	floppy_set_sector_dma           ; its number and the DMA address
	bra.w	read_sectors_next               ; read it
read_sectors_check_count:
	move.b	$ffff8609.w,dma_address_read+1.w ; DMA base high, the DMA address
	move.b	$ffff860b.w,dma_address_read+2.w ; DMA base mid
	move.b	$ffff860d.w,dma_address_read+3.w ; DMA base low, read back
	cmpa.l	dma_address_read.w,a2           ; at the end?
	beq.w	floppy_exit_ok                  ; yes: done
	move.w	#$ffee,fd_error.w               ; -18: DMA count error
	bra.w	floppy_exit_error               ; failed

;------------------------------------------------------------------------------
; fdc_status_error: the floppy error code for an FDC status into $B96: -13 write protected, -8 record not
;  found, -4 CRC, -15 lost data, else the operation's own code $B94.  In: d0 the status.  Changes d1.
;------------------------------------------------------------------------------
fdc_status_error:                               ; from: read_sectors, floppy_write_sectors, floppy_wipe_track,
                                                ;   floppy_write_format, floppy_verify_track
	moveq	#-13,d1                         ; -13
	btst	#$6,d0                          ; write protected?
	bne.s	fdc_status_error_store          ; yes
	moveq	#-8,d1                          ; -8
	btst	#$4,d0                          ; record not found?
	bne.s	fdc_status_error_store          ; yes
	moveq	#-4,d1                          ; -4
	btst	#$3,d0                          ; CRC error?
	bne.s	fdc_status_error_store          ; yes
	moveq	#-15,d1                         ; -15
	btst	#$2,d0                          ; lost data?
	bne.s	fdc_status_error_store          ; yes
	move.w	fd_default_error.w,d1           ; the operation's code
fdc_status_error_store:
	move.w	d1,fd_error.w                   ; the error code
	rts

;------------------------------------------------------------------------------
; floppy_write_sectors: writes the sectors set in the floppy parameters ($AAA drive, $AA4 track,
; $AA2 side, $AA6 first sector, $AA8 count, $AAC buffer), one write sector command at a time.
; Out: d0.l 0 or a negative error code (-10 write fault, -13 write protected, -8 not found, -4 CRC,
; -15 lost data, -2 not ready, -6 seek error).  Ends through floppy_exit (VBL watches the motor).
;------------------------------------------------------------------------------
floppy_write_sectors:	; from: floppy_interchange, probe_drive_sides, write_track_checked
	moveq	#-10,d0                         ; -10: write fault unless the status says otherwise
	bsr.w	floppy_set_up                   ; the parameters taken, the drive's track known
	bsr.w	floppy_select                   ; drive and side selected, sector and DMA address set
	bsr.w	floppy_seek_verify              ; to the track
	bne.w	floppy_exit_error               ; seek failed
floppy_write_next:
	move.w	#$190,(a6)                      ; DMA to write: the direction toggled to clear the DMA status
	move.w	#$90,(a6)
	move.w	#$190,(a6)
	move.w	#$1,d7                          ; one sector
	bsr.w	fdc_write_d7                    ; into the sector count
	move.w	#$180,(a6)                      ; the FDC command register
	move.w	#$a0,d7                         ; write sector
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; the time-out
floppy_write_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt (active low)?
	beq.s	floppy_write_status             ; yes: done
	subq.l	#1,d7                           ; the time-out counted down
	bne.s	floppy_write_wait               ; keep waiting
	move.w	#$fffe,fd_error.w               ; -2: not ready
	bsr.w	floppy_force_interrupt          ; the command stopped
	bra.w	floppy_exit_error               ; failed
floppy_write_status:
	move.w	#$180,(a6)                      ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	bsr.w	fdc_status_error                ; error code from the status
	and.b	#$5c,d0                         ; write protect, not found, CRC or lost data?
	bne.w	floppy_exit_error               ; yes: failed
	addq.w	#1,fd_cur_sector.w              ; the next sector
	addi.l	#$200,fd_cur_buffer.w           ; the next 512 bytes
	subq.w	#1,fd_sectors_left.w            ; one less to do
	beq.w	floppy_exit_ok                  ; all written: OK
	bsr.w	floppy_set_sector_dma           ; the sector and the DMA address set
	bra.s	floppy_write_next               ; the next sector

;------------------------------------------------------------------------------
; floppy_format_track: formats one track ($AAA drive, $AA4 track, $AA2 side, $AA8 sectors per
; track, $A9E fill word; $AA0 interleave is copied but not used, the sectors are numbered in order).
; The track image is built at $2000.  The track is first written blank, then formatted, then every
; sector is read back; the numbers of the bad sectors are listed at $2000, ending with 0.
; Out: d0.l 0, -16 when a sector is bad, or the error code.
;------------------------------------------------------------------------------
floppy_format_track:	; from: probe_high_density, format_track_checked
	moveq	#-10,d0                         ; -10: write fault
	move.l	#$2000,fd_buffer.w              ; the track image at $2000
	bsr.w	floppy_set_up                   ; the parameters taken
	bsr.w	floppy_select                   ; drive and side selected
	move.w	fd_count.w,fd_format_sectors.w  ; sectors per track
	move.w	fd_interleave.w,fd_format_interleave.w ; interleave
	move.w	fd_fill_word.w,fd_format_fill.w ; fill word
	bsr.w	floppy_seek_track               ; seek to the track (-6 if not found)
	bne.w	floppy_exit_error               ; failed
	move.w	fd_cur_track.w,0(a1)            ; the drive's track
	bsr.w	floppy_wipe_track               ; write a blank track
	move.w	#$1,fd_cur_sector.w             ; the sectors from 1
	bsr.w	floppy_write_format             ; format the track
	bne.w	floppy_exit_error               ; failed
	move.w	fd_format_sectors.w,fd_sectors_left.w ; sectors to verify
	bsr.w	floppy_verify_track             ; read them back, the bad ones listed
	movea.l	fd_cur_buffer.w,a2              ; the list
	tst.w	(a2)                            ; empty?
	beq.w	floppy_exit_ok                  ; yes: OK
	move.w	#$fff0,fd_error.w               ; -16: bad sectors
	bra.w	floppy_exit_error               ; failed

;------------------------------------------------------------------------------
; floppy_wipe_track: writes a track of nothing but $00 bytes (6,881 of them) from the buffer at $B82
; with a write track command, wiping the old format.  Out: d7 = 1 on a time-out or a DMA error;
; $B96 the error code.  Uses d0-d1, d3, d7, a2.
;------------------------------------------------------------------------------
floppy_wipe_track:	; from: floppy_format_track
	move.w	#$fff6,fd_default_error.w       ; -10: write fault
	move.w	#$1,d3                          ; sector 1 (not used)
	movea.l	fd_cur_buffer.w,a2              ; the track image
	move.w	#$3b,d1                         ; 60 bytes
	move.b	#$0,d0                          ; of $00
	bsr.w	floppy_fill_bytes               ; filled
	move.w	#$154d,d1                       ; 5,454 bytes
	move.b	#$0,d0                          ; of $00
	bsr.w	floppy_fill_bytes               ; filled
	move.w	#$578,d1                        ; 1,401 bytes
	move.b	#$0,d0                          ; of $00
	bsr.w	floppy_fill_bytes               ; filled
	move.b	fd_cur_buffer+3.w,$ffff860d.w   ; DMA base low, the DMA address: the image
	move.b	fd_cur_buffer+2.w,$ffff860b.w   ; DMA base mid
	move.b	fd_cur_buffer+1.w,$ffff8609.w   ; DMA base high
	move.w	#$190,(a6)                      ; DMA to write, the status cleared
	move.w	#$90,(a6)
	move.w	#$190,(a6)
	move.w	#$1f,d7                         ; 31 sectors of DMA
	bsr.w	fdc_write_d7                    ; into the sector count
	move.w	#$180,(a6)                      ; the FDC command register
	move.w	#$f0,d7                         ; write track
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; the time-out
floppy_wipe_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt?
	beq.s	floppy_wipe_status              ; yes
	subq.l	#1,d7                           ; the time-out counted down
	bne.s	floppy_wipe_wait                ; keep waiting
	move.w	#$fffe,fd_error.w               ; -2: not ready
	bsr.w	floppy_force_interrupt          ; the command stopped
floppy_wipe_failed:
	moveq	#1,d7                           ; failed
	rts
floppy_wipe_status:
	move.w	#$190,(a6)                      ; the DMA status
	move.w	(a6),d0                         ; read
	btst	#$0,d0                          ; DMA error?
	beq.s	floppy_wipe_failed              ; yes
	move.w	#$180,(a6)                      ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	and.b	#$44,d0                         ; write protect or lost data?
	beq.s	floppy_wipe_end                 ; no
	bsr.w	fdc_status_error                ; error code from the status
floppy_wipe_end:
	rts

;------------------------------------------------------------------------------
; floppy_write_format: builds the formatted track at $B82 ($B80 sectors from sector $B7C, 512 bytes
; each filled with the word at $B8E) and writes it with a write track command.
; Out: d7 = 1 on a time-out or DMA error; $B96 the error code.  Uses d0-d1, d3, d7, a2.
;------------------------------------------------------------------------------
floppy_write_format:	; from: floppy_format_track
	move.w	fd_cur_sector.w,d3              ; the first sector number
	move.w	#$fff6,fd_default_error.w       ; -10: write fault
	movea.l	fd_cur_buffer.w,a2              ; the track image
	move.w	#$3b,d1                         ; the track's first gap: 60 bytes
	move.b	#$4e,d0                         ; of $4E
	bsr.w	floppy_fill_bytes               ; filled
floppy_format_sector:
	move.w	#$b,d1                          ; 12 bytes
	clr.b	d0                              ; of $00
	bsr.w	floppy_fill_bytes               ; filled
	move.w	#$2,d1                          ; 3 bytes
	move.b	#$f5,d0                         ; of $F5 (the sync marks)
	bsr.w	floppy_fill_bytes               ; filled
	move.b	#$fe,(a2)+                      ; the ID address mark
	move.b	fd_cur_track+1.w,(a2)+          ; the track
	move.b	fd_cur_side+1.w,(a2)+           ; the side
	move.b	d3,(a2)+                        ; the sector
	move.b	#$2,(a2)+                       ; size 2: 512 bytes
	move.b	#$f7,(a2)+                      ; $F7: the CRC written here
	move.w	#$15,d1                         ; 22 bytes
	move.b	#$4e,d0                         ; of $4E
	bsr.w	floppy_fill_bytes               ; filled
	move.w	#$b,d1                          ; 12 bytes
	clr.b	d0                              ; of $00
	bsr.w	floppy_fill_bytes               ; filled
	move.w	#$2,d1                          ; 3 bytes
	move.b	#$f5,d0                         ; of $F5
	bsr.w	floppy_fill_bytes               ; filled
	move.b	#$fb,(a2)+                      ; the data address mark
	move.w	#$ff,d1                         ; 256 words
floppy_format_fill:
	move.b	fd_format_fill.w,(a2)+          ; of the fill word
	move.b	fd_format_fill+1.w,(a2)+        ; (the fill word's low byte)
	dbra	d1,floppy_format_fill           ; the next word
	move.b	#$f7,(a2)+                      ; the data CRC
	move.w	#$27,d1                         ; 40 bytes
	move.b	#$4e,d0                         ; of $4E
	bsr.w	floppy_fill_bytes               ; filled
	add.w	#$1,d3                          ; the next sector number
	subi.w	#$1,fd_sectors_left.w           ; one less to do
	bne.s	floppy_format_sector            ; the next sector
	move.w	#$578,d1                        ; the end of the track: 1,401 bytes
	move.b	#$4e,d0                         ; of $4E
	bsr.w	floppy_fill_bytes               ; filled
	move.b	fd_cur_buffer+3.w,$ffff860d.w   ; DMA base low, the DMA address: the image
	move.b	fd_cur_buffer+2.w,$ffff860b.w   ; DMA base mid
	move.b	fd_cur_buffer+1.w,$ffff8609.w   ; DMA base high
	move.w	#$190,(a6)                      ; DMA to write, the status cleared
	move.w	#$90,(a6)
	move.w	#$190,(a6)
	move.w	#$1f,d7                         ; 31 sectors of DMA
	bsr.w	fdc_write_d7                    ; into the sector count
	move.w	#$180,(a6)                      ; the FDC command register
	move.w	#$f0,d7                         ; write track
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; the time-out
floppy_format_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt?
	beq.s	floppy_format_status            ; yes
	subq.l	#1,d7                           ; the time-out counted down
	bne.s	floppy_format_wait              ; keep waiting
	move.w	#$fffe,fd_error.w               ; -2: not ready
	bsr.w	floppy_force_interrupt          ; the command stopped
floppy_format_failed:
	moveq	#1,d7                           ; failed
	rts
floppy_format_status:
	move.w	#$190,(a6)                      ; the DMA status
	move.w	(a6),d0                         ; read
	btst	#$0,d0                          ; DMA error?
	beq.s	floppy_format_failed            ; yes
	move.w	#$180,(a6)                      ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	and.b	#$44,d0                         ; write protect or lost data?
	beq.s	floppy_format_end               ; no
	bsr.w	fdc_status_error                ; error code from the status
floppy_format_end:
	rts

;------------------------------------------------------------------------------
; floppy_fill_bytes: stores d0.b d1+1 times at a2 and on.
;------------------------------------------------------------------------------
floppy_fill_bytes:	; from: floppy_wipe_track, floppy_write_format
	move.b	d0,(a2)+                        ; the byte stored
	dbra	d1,floppy_fill_bytes            ; the next
	rts

;------------------------------------------------------------------------------
; floppy_verify_sectors: reads back the sectors in the floppy parameters and lists the bad ones at
; the buffer.  Not called.  Out: d0.l 0 or the error code.
;------------------------------------------------------------------------------
floppy_verify_sectors:
	moveq	#-11,d0                         ; -11: read fault
	bsr.w	floppy_set_up                   ; the parameters taken
	bsr.w	floppy_select                   ; drive and side selected
	bsr.w	floppy_seek_verify              ; to the track
	bne.w	floppy_exit_error               ; failed
	bsr.w	floppy_verify_track             ; the sectors read back
	bra.w	floppy_exit_ok                  ; OK

;------------------------------------------------------------------------------
; floppy_verify_track: reads $B80 sectors from $B7C one at a time into the buffer at $B82+512 and
; lists each sector that fails (time-out, DMA error, not found, CRC, lost data) at $B82, ending
; with a 0 word.  Uses d0, d7, a2.
;------------------------------------------------------------------------------
floppy_verify_track:	; from: floppy_format_track, floppy_verify_sectors
	move.w	#$fff5,fd_default_error.w       ; -11: read fault
	movea.l	fd_cur_buffer.w,a2              ; the bad sector list
	addi.l	#$200,fd_cur_buffer.w           ; the data read past it
floppy_verify_next:
	move.w	#$2,fd_retries.w                ; 2 tries (not counted down here)
	move.w	#$84,(a6)                       ; the sector register
	move.w	fd_cur_sector.w,d7              ; the sector
	bsr.w	fdc_write_d7                    ; sent
	move.b	fd_cur_buffer+3.w,$ffff860d.w   ; DMA base low, the DMA address
	move.b	fd_cur_buffer+2.w,$ffff860b.w   ; DMA base mid
	move.b	fd_cur_buffer+1.w,$ffff8609.w   ; DMA base high
	move.w	#$90,(a6)                       ; DMA to read, the status cleared
	move.w	#$190,(a6)
	move.w	#$90,(a6)
	move.w	#$1,d7                          ; one sector
	bsr.w	fdc_write_d7                    ; into the sector count
	move.w	#$80,(a6)                       ; the FDC command register
	move.w	#$80,d7                         ; read sector
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; the time-out
floppy_verify_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt?
	beq.s	floppy_verify_status            ; yes
	subq.l	#1,d7                           ; the time-out counted down
	bne.s	floppy_verify_wait              ; keep waiting
	bsr.w	floppy_force_interrupt          ; the command stopped
	bra.s	floppy_verify_bad               ; a bad sector
floppy_verify_status:
	move.w	#$90,(a6)                       ; the DMA status
	move.w	(a6),d0                         ; read
	btst	#$0,d0                          ; DMA error?
	beq.s	floppy_verify_bad               ; yes: a bad sector
	move.w	#$80,(a6)                       ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	bsr.w	fdc_status_error                ; error code from the status
	and.b	#$1c,d0                         ; not found, CRC or lost data?
	bne.s	floppy_verify_bad               ; yes: a bad sector
floppy_verify_advance:
	addq.w	#1,fd_cur_sector.w              ; the next sector
	subq.w	#1,fd_sectors_left.w            ; one less to do
	bne.w	floppy_verify_next              ; the next sector
	subi.l	#$200,fd_cur_buffer.w           ; the buffer back to the list
	clr.w	(a2)                            ; the list ended
	rts
floppy_verify_bad:
	move.w	fd_cur_sector.w,(a2)+           ; the sector listed
	bra.s	floppy_verify_advance           ; on to the next

;------------------------------------------------------------------------------
; floppy_set_up: starts a floppy call.  In: d0 the default error code.  Interrupts at IPL 4 (the
; VBL's motor watch is off), a6 = the DMA mode register, the floppy parameters copied to the
; working ones ($B76-$B86), the density set ($FF860E: 3 high density for drive A when bit 6 of $27A
; is set, else 0), a1 = the drive's block ($BBC drive A, $BC0 drive B: track, step rate).
; When the drive's track is not known the head is restored (once more after a seek to track 10);
; when that fails the track stays unknown ($FF00).
;------------------------------------------------------------------------------
floppy_set_up:                                  ; from: restore_drive, read_alignment_track, read_sectors,
                                                ;   floppy_write_sectors, floppy_format_track, floppy_verify_sectors
	move.w	#$2400,sr                       ; no VBL
	clr.b	floppy_motor_watch.w            ; no motor watch
	movea.l	#$0,a5                          ; a5 = 0
	lea	$ffff8606.w,a6                  ; DMA mode / status, a6: the DMA mode register
	move.w	d0,fd_default_error.w           ; the default error
	move.w	d0,fd_error.w                   ; the error
	move.l	fd_buffer.w,fd_cur_buffer.w     ; buffer
	move.w	fd_drive.w,fd_cur_drive.w       ; drive
	move.w	fd_sector.w,fd_cur_sector.w     ; first sector
	move.w	fd_track.w,fd_cur_track.w       ; track
	move.w	fd_side.w,fd_cur_side.w         ; side
	move.w	fd_count.w,fd_sectors_left.w    ; count
	move.w	#$2,fd_retries.w                ; 2 tries
	lea	fd_drive_a.w,a1                 ; drive A's block
	tst.w	fd_drive.w                      ; drive A?
	bne.w	floppy_set_up_dd                ; no: double density
	btst	#$6,drive_a_type.w              ; high density drive A?
	beq.s	floppy_set_up_dd                ; no
	move.w	#$3,$ffff860e.w                 ; high density
	move.w	#$0,2(a1)                       ; step rate 0
	bra.s	floppy_set_up_drive             ; the drive set
floppy_set_up_dd:
	move.w	#$0,$ffff860e.w                 ; double density
	move.w	#$3,2(a1)                       ; step rate 3
floppy_set_up_drive:
	lea	fd_drive_a.w,a1                 ; drive A's block
	tst.w	fd_cur_drive.w                  ; drive B?
	beq.s	floppy_set_up_end_address       ; no
	lea	fd_drive_b.w,a1                 ; drive B's block
floppy_set_up_end_address:
	moveq	#0,d7                           ; the buffer's length
	move.w	fd_sectors_left.w,d7            ; the count
	lsl.w	#8,d7                           ; times 512
	lsl.w	#1,d7
	movea.l	fd_cur_buffer.w,a0              ; the buffer
	adda.l	d7,a0                           ; past its end
	move.l	a0,fd_buffer_end.w              ; the end of the buffer
	tst.w	0(a1)                           ; the track known?
	bpl.s	floppy_set_up_done              ; yes
	bsr.w	floppy_select                   ; drive and side selected
	clr.w	0(a1)                           ; at track 0 for now
	bsr.w	floppy_restore                  ; restore
	beq.s	floppy_set_up_done              ; at track 0: done
	moveq	#10,d7                          ; else out to track 10
	bsr.w	floppy_seek_d7                  ; seek to track 10
	bne.s	floppy_set_up_unknown_track     ; failed
	bsr.w	floppy_restore                  ; and restore again
	beq.s	floppy_set_up_done              ; at track 0: done
floppy_set_up_unknown_track:
	move.w	#$ff00,0(a1)                    ; the track not known
floppy_set_up_done:
	rts

;------------------------------------------------------------------------------
; floppy_exit_error / floppy_exit_ok: the end of every floppy call.  The track register is reloaded
; with a seek to the same track, bit 7 of $297 set and the VBL vector pointed at floppy_motor_vbl,
; which deselects the drive once the motor has stopped.  Out: d0.l the error code ($B96) or 0.
;------------------------------------------------------------------------------
floppy_exit_error:                              ; from: restore_drive, read_alignment_track, read_sectors,
                                                ;   floppy_write_sectors, floppy_format_track, floppy_verify_sectors
	move.w	fd_error.w,d0                   ; the error
	ext.l	d0                              ; as a long
	bra.s	floppy_exit
floppy_exit_ok:                                 ; from: restore_drive, read_alignment_track, read_sectors,
                                                ;   floppy_write_sectors, floppy_format_track, floppy_verify_sectors
	clr.l	d0                              ; OK
	clr.w	fd_error.w                      ; no error
floppy_exit:
	move.l	d0,-(sp)                        ; the result kept
	move.w	#$86,(a6)                       ; the data register
	move.w	0(a1),d7                        ; the drive's track
	bsr.w	fdc_write_d7                    ; sent
	move.w	#$10,d6                         ; seek
	bsr.w	floppy_command                  ; sent
	bset	#$7,floppy_motor_watch.w        ; the motor watched
	move.l	#floppy_motor_vbl,$70.w         ; VBL vector, by the VBL
	move.w	#$2200,sr                       ; the VBL on
	move.l	(sp)+,d0                        ; the result
	rts

;------------------------------------------------------------------------------
; floppy_motor_vbl: VBL handler while a floppy call has ended: once the FDC's motor-on bit is clear
; the drives are deselected and the program's own VBL handler put back.
;------------------------------------------------------------------------------
floppy_motor_vbl:	; from: floppy_exit_error
	movem.l	d0-d7,-(sp)                     ; kept
	btst	#$7,floppy_motor_watch.w        ; watching?
	beq.s	floppy_motor_vbl_end            ; no
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the FDC status register
	bsr.w	fdc_read_d0                     ; read
	btst	#$7,d0                          ; the motor still on?
	bne.s	floppy_motor_vbl_end            ; yes
	move.b	#$6,d0                          ; both drives deselected
	bsr.w	psg_select_drive_side
	move.l	#vbl_handler,$70.w              ; VBL vector, the usual VBL handler back
	move.w	#$2400,sr                       ; IPL 4 (the rte puts the old sr back)
	clr.b	floppy_motor_watch.w            ; watch over
floppy_motor_vbl_end:
	movem.l	(sp)+,d0-d7
	rte

;------------------------------------------------------------------------------
; floppy_seek_track: seeks to the track at $B7A (-6 on failure).  floppy_seek_d7 seeks to track
; d7 (-6 on failure); floppy_seek_command seeks to d7 leaving the error alone.
; Out: d6 = 0 (Z set) when the command ended, d7 the status.
;------------------------------------------------------------------------------
floppy_seek_track:	; from: floppy_format_track
	move.w	fd_cur_track.w,d7               ; the track

floppy_seek_d7:	; from: restore_drive, floppy_set_up
	move.w	#$fffa,fd_error.w               ; -6: seek error

floppy_seek_command:	; from: floppy_speed_test
	move.w	#$86,(a6)                       ; the data register
	bsr.w	fdc_write_d7                    ; the track
	move.w	#$10,d6                         ; seek
	bra.s	floppy_command                  ; sent

;------------------------------------------------------------------------------
; floppy_reseek: restores the head, steps it to track 5 and seeks to the track at $B7A again.
; Not called.
;------------------------------------------------------------------------------
floppy_reseek:
	move.w	#$fffa,fd_error.w               ; -6: seek error
	bsr.w	floppy_restore                  ; restore
	bne.s	floppy_seek_end                 ; failed
	clr.w	0(a1)                           ; at track 0
	move.w	#$82,(a6)                       ; the track register
	clr.w	d7                              ; 0
	bsr.w	fdc_write_d7                    ; sent
	move.w	#$86,(a6)                       ; the data register
	move.w	#$5,d7                          ; track 5
	bsr.w	fdc_write_d7                    ; sent
	move.w	#$10,d6                         ; seek
	bsr.w	floppy_command                  ; sent
	bne.s	floppy_seek_end                 ; failed
	move.w	#$5,0(a1)                       ; at track 5

;------------------------------------------------------------------------------
; floppy_seek_verify: seeks to the track at $B7A with verify.  Out: Z set when the head is there
; (no seek error, no CRC error) and the drive's track updated; $B96 = -6.
;------------------------------------------------------------------------------
floppy_seek_verify:	; from: read_alignment_track, read_sectors, floppy_write_sectors, floppy_verify_sectors
	move.w	#$fffa,fd_error.w               ; -6: seek error
	move.w	#$86,(a6)                       ; the data register
	move.w	fd_cur_track.w,d7               ; the track
	bsr.w	fdc_write_d7                    ; sent
	moveq	#20,d6                          ; seek with verify
	bsr.w	floppy_command                  ; sent
	bne.s	floppy_seek_end                 ; failed
	move.w	fd_cur_track.w,0(a1)            ; the drive's track
	and.b	#$18,d7                         ; seek error or CRC error?
floppy_seek_end:	; from: floppy_reseek
	rts

;------------------------------------------------------------------------------
; floppy_restore: steps the head to track 0.  Out: Z set when the track 0 signal came and the
; drive's track set to 0.
;------------------------------------------------------------------------------
floppy_restore:	; from: restore_drive, floppy_set_up, floppy_reseek
	clr.w	d6                              ; restore
	bsr.w	floppy_command                  ; sent
	bne.s	floppy_restore_end              ; failed
	btst	#$2,d7                          ; at track 0?
	eori.b	#$4,ccr                         ; Z set when it is
	bne.s	floppy_restore_end              ; no
	clr.w	0(a1)                           ; the drive's track 0
floppy_restore_end:
	rts

;------------------------------------------------------------------------------
; floppy_command: sends the type I command d6 with the drive's step rate and waits for the FDC
; interrupt ($40000 tries, $60000 when the motor was off and must spin up).
; Out: d7 the status and d6 = 0 (Z set), or d6 = 1 on a time-out (the command stopped).
;------------------------------------------------------------------------------
floppy_command:	; from: floppy_exit_error, floppy_seek_command, floppy_reseek, floppy_seek_verify, floppy_restore
	move.w	2(a1),d0                        ; the drive's step rate
	and.b	#$3,d0                          ; the step rate bits
	or.b	d0,d6                           ; into the command
	move.l	#$40000,d7                      ; the time-out
	move.w	#$80,(a6)                       ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	btst	#$7,d0                          ; the motor on?
	bne.s	floppy_command_send             ; yes
	move.l	#$60000,d7                      ; longer: the motor spins up
floppy_command_send:
	bsr.w	fdc_write_command               ; the command sent
floppy_command_wait:
	subq.l	#1,d7                           ; the time-out counted down
	beq.s	floppy_command_timeout          ; time-out
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt?
	bne.s	floppy_command_wait             ; not yet
	bsr.w	fdc_read_d7                     ; the status
	clr.w	d6                              ; done
	rts
floppy_command_timeout:
	bsr.w	floppy_force_interrupt          ; the command stopped
	moveq	#1,d6                           ; failed
	rts

;------------------------------------------------------------------------------
; floppy_force_interrupt: stops the FDC's command (force interrupt $D0) and reads the status into d7.
;------------------------------------------------------------------------------
floppy_force_interrupt:                         ; from: read_alignment_track, read_sectors, floppy_write_sectors,
                                                ;   floppy_wipe_track, floppy_write_format, floppy_verify_track, 2 more
	move.w	#$80,(a6)                       ; the FDC command register
	move.w	#$d0,d7                         ; force interrupt
	bsr.w	fdc_write_d7                    ; sent
	move.w	#$14,d7                         ; a short wait
floppy_force_interrupt_delay:
	dbra	d7,floppy_force_interrupt_delay
	bsr.w	fdc_read_d7                     ; the status read
	rts

;------------------------------------------------------------------------------
; floppy_select: selects the drive ($B78) and side ($B7E), loads the track register with the
; drive's track, then floppy_set_sector_dma sets the sector register ($B7C) and the DMA address
; ($B82).  Uses d0-d2, d7.
;------------------------------------------------------------------------------
floppy_select:                                  ; from: restore_drive, read_alignment_track, read_sectors,
                                                ;   floppy_write_sectors, floppy_format_track, floppy_verify_sectors, 1
                                                ;   more
	move.w	fd_cur_drive.w,d0               ; the drive
	addq.b	#1,d0                           ; drive 0 or 1 to 1 or 2
	lsl.b	#1,d0                           ; the drive's select bit
	or.w	fd_cur_side.w,d0                ; the side
	eori.b	#$7,d0                          ; active low
	and.b	#$7,d0                          ; the 3 bits
	bsr.w	psg_select_drive_side           ; to the sound chip's port A
	move.w	#$82,(a6)                       ; the track register
	move.w	0(a1),d7                        ; the drive's track
	bsr.w	fdc_write_d7                    ; sent
	clr.b	dma_address_read.w

floppy_set_sector_dma:	; from: read_sectors, floppy_write_sectors
	move.w	#$84,(a6)                       ; the sector register
	move.w	fd_cur_sector.w,d7              ; the sector
	bsr.w	fdc_write_d7                    ; sent
	move.b	fd_cur_buffer+3.w,$ffff860d.w   ; DMA base low, the DMA address
	move.b	fd_cur_buffer+2.w,$ffff860b.w   ; DMA base mid
	move.b	fd_cur_buffer+1.w,$ffff8609.w   ; DMA base high
	rts

;------------------------------------------------------------------------------
; psg_select_drive_side: puts d0 into bits 0-2 of the sound chip's port A (bit 0 side, bits 1-2 the
; drive selects, active low).  Out: d2 the old port A.  Uses d1.
;------------------------------------------------------------------------------
psg_select_drive_side:	; from: floppy_menu_jump_table, floppy_quick_test, floppy_motor_vbl, floppy_select
	move.w	sr,-(sp)                        ; the sr kept
	ori.w	#$700,sr                        ; interrupts off
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	$ffff8800.w,d1                  ; PSG register select, read
	move.b	d1,d2                           ; the old value
	and.b	#$f8,d1                         ; side and drive bits cleared
	or.b	d0,d1                           ; the new ones
	move.b	d1,$ffff8802.w                  ; PSG write data, written
	move.w	(sp)+,sr                        ; the interrupts back
	rts

;------------------------------------------------------------------------------
; fdc_write_command: writes d6 to the DMA chip's selected register (the FDC command register),
; with a short wait before and after.  fdc_write_d7 writes d7, fdc_read_d7 and fdc_read_d0 read
; it into d7 or d0, and fdc_delay is the short wait.
;------------------------------------------------------------------------------
fdc_write_command:	; from: floppy_command
	bsr.w	fdc_delay
	move.w	d6,$ffff8604.w                  ; DMA sector count / FDC access, the command
	bra.s	fdc_delay

fdc_write_d7:                                   ; from: read_alignment_track, read_sectors, floppy_write_sectors,
                                                ;   floppy_wipe_track, floppy_write_format, floppy_verify_track, 7 more
	bsr.w	fdc_delay
	move.w	d7,$ffff8604.w                  ; DMA sector count / FDC access, written
	bra.s	fdc_delay

fdc_read_d7:	; from: floppy_command, floppy_force_interrupt
	bsr.w	fdc_delay
	move.w	$ffff8604.w,d7                  ; DMA sector count / FDC access, read
	bra.s	fdc_delay

fdc_read_d0:                                    ; from: wait_index_on, wait_index_off, read_alignment_track,
                                                ;   read_sectors, floppy_write_sectors, floppy_wipe_track, 4 more
	bsr.w	fdc_delay
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, read

fdc_delay:	; from: fdc_write_command, fdc_write_d7, fdc_read_d7, fdc_read_d0
	move.w	sr,-(sp)
	move.w	d7,-(sp)                        ; d7 kept
	move.w	#$14,d7                         ; 21 loops
fdc_delay_loop:
	dbra	d7,fdc_delay_loop               ; the wait
	move.w	(sp)+,d7
	move.w	(sp)+,sr
	rts

;------------------------------------------------------------------------------
; blit_short_test: menu G.  Checks the BLiTTER's halftone RAM, end masks, the 16 operations, the
; halftone operations, skew, FXSR, reverse BLiTs, smudge and the x and y counts, with the source at
; $60000 and the destination at $70000.  Each failure sets a bit in $676 (G1-G8) or $677 (G9-G12),
; and the matching "Gn ..." line is printed, then "Pass" or "Fail at cycle:" with the background red.
;------------------------------------------------------------------------------
blit_short_test:	; from: test_routines
	clr.b	test_errors.w                   ; no failures
	clr.b	test_errors_high.w
	lea	msg_testing_blitter,a5          ; "Testing Blitter"
	bsr.w	show_status                     ; on the status line
	bsr.w	blit_check_present              ; a BLiTTER there?
	beq.w	blit_halftone_test              ; yes
	move.w	#$500,$ffff8240.w               ; palette 0, no: the background red
	lea	msg_no_blitter,a5               ; "No Blitter installed"
	bsr.w	print_string                    ; printed
	rts
blit_halftone_test:
	lea	$ffff8a00.w,a0                  ; BLiTTER halftone RAM, G1: each halftone word
blit_halftone_next_word:
	moveq	#0,d0                           ; from $0000
blit_halftone_next_value:
	move.w	d0,(a0)                         ; the value written
	move.w	#$ffff,d1                       ; the other words: $FFFF
	moveq	#0,d2                           ; and 0
	lea	$ffff8a00.w,a1                  ; BLiTTER halftone RAM, the other 15 words
	moveq	#15,d7                          ; 16 words
blit_halftone_others:
	cmpa.w	a0,a1                           ; the word under test?
	beq.w	blit_halftone_skip              ; yes: left alone
	move.w	d2,(a1)                         ; the others written 0 and $FFFF
	move.w	d1,(a1)
blit_halftone_skip:
	adda.w	#$2,a1                          ; the next word
	dbra	d7,blit_halftone_others
	cmp.w	(a0),d0                         ; the value kept?
	bne.w	blit_halftone_failed            ; no
	add.w	#$101,d0                        ; the next value: $0101 more
	cmp.w	#$100,d0                        ; up to $FFFF
	bne.s	blit_halftone_next_value        ; the next value
	adda.w	#$2,a0                          ; the next word
	cmpa.l	#$ffff8a20,a0                   ; all 16?
	beq.w	blit_endmask_test               ; yes
	bne.s	blit_halftone_next_word         ; the next word
blit_halftone_failed:
	bset	#$0,test_errors.w               ; G1 halftone RAM failed
	bra.w	blit_short_report               ; the report
blit_endmask_test:
	lea	$ffff8a00.w,a6                  ; BLiTTER halftone RAM, G2: the registers
	moveq	#2,d1                           ; increments 2
	bsr.w	blit_set_increments
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution (not used)
	andi.w	#$3,d0
	lsl.w	#1,d0
	move.w	#$190,blit_lines.w              ; 400 lines
	move.w	#$28,blit_words.w               ; 40 words
	move.w	#$0,$3c(a6)                     ; control 0
	move.b	#$f,$3b(a6)                     ; op 15: all ones
	moveq	#1,d0                           ; end masks from bit 0
	move.w	d0,$28(a6)                      ; end mask 1
	move.w	d0,$2a(a6)                      ; end mask 2
	move.w	d0,$2c(a6)                      ; end mask 3
blit_endmask_next_bit:
	moveq	#0,d0                           ; the destination cleared
	lea	$70000,a0                       ; the destination
	move.w	blit_words.w,d1                 ; one line's words
	bsr.w	blit_fill_words                 ; cleared
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	move.w	$2a(a6),d0                      ; the line should be the mask
	move.w	blit_words.w,d1
	lea	$70000,a0
	bsr.w	blit_check_words                ; checked
	beq.w	blit_endmask_shift              ; yes
	bset	#$1,test_errors.w               ; G2 endmask failed
	bra.w	blit_short_report               ; the report
blit_endmask_shift:
	lsl.w	$28(a6)                         ; the next bit
	lsl.w	$2a(a6)
	lsl.w	$2c(a6)
	bcc.s	blit_endmask_next_bit           ; all 16
	move.b	#$2,$3a(a6)                     ; G3: HOP 2, source only
	move.w	#$ffff,d0                       ; full masks
	move.w	d0,$28(a6)                      ; end mask 1
	move.w	d0,$2a(a6)                      ; end mask 2
	move.w	d0,$2c(a6)                      ; end mask 3
	move.w	#$aaaa,blit_source_word.w       ; source $AAAA, destination $5555
	move.w	#$5555,blit_dest_word.w
	bsr.w	blit_op_test                    ; the 16 operations
	not.w	blit_dest_word.w                ; source $5555, destination $AAAA
	not.w	blit_source_word.w
	bsr.w	blit_op_test                    ; the 16 operations
	clr.w	blit_source_word.w              ; source $0000, destination $FFFF
	move.w	#$ffff,blit_dest_word.w
	bsr.w	blit_op_test                    ; the 16 operations
	not.w	blit_source_word.w              ; source $FFFF, destination $0000
	not.w	blit_dest_word.w
	bsr.w	blit_op_test                    ; the 16 operations
	not.w	blit_source_word.w              ; source $0000, destination $0000
	bsr.w	blit_op_test                    ; the 16 operations
	move.w	#$ffff,blit_source_word.w       ; source $FFFF, destination $FFFF
	move.w	#$ffff,blit_dest_word.w
	bsr.w	blit_op_test                    ; the 16 operations
	tst.b	test_errors.w                   ; any failure so far?
	bne.w	blit_short_report               ; yes: the report
	move.w	#$0,$3c(a6)                     ; G4: control 0
	move.b	#$3,$3b(a6)                     ; op 3: the source
	moveq	#0,d0                           ; the halftone RAM 0
	moveq	#16,d1                          ; 16 words
	lea	$ffff8a00.w,a0                  ; BLiTTER halftone RAM
	bsr.w	blit_fill_words                 ; cleared
	lea	$60000,a0                       ; the source 0
	move.w	blit_words.w,d1                 ; 16 lines' words
	lsl.w	#4,d1
	bsr.w	blit_fill_words                 ; cleared
	lea	$70000,a0                       ; the destination 0
	bsr.w	blit_fill_words                 ; cleared
	move.b	#$0,$3a(a6)                     ; HOP 0: all ones
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	moveq	#-1,d0                          ; all $FFFF?
	lea	$70000,a0                       ; the destination
	move.w	blit_words.w,d1
	bsr.w	blit_check_words                ; checked
	beq.w	blit_hop_lines_test             ; yes
	bset	#$3,test_errors.w               ; G4 halftone op failed
	bra.w	blit_short_report               ; the report
blit_hop_lines_test:
	moveq	#1,d0                           ; the halftone RAM: 1, 2, 4 .. $8000
	lea	$ffff8a00.w,a0                  ; BLiTTER halftone RAM
	move.b	#$1,$3a(a6)                     ; HOP 1: the halftone only
blit_hop_lines_fill:
	move.w	d0,(a0)+
	lsl.w	#1,d0                           ; the next bit
	bcc.s	blit_hop_lines_fill             ; 16 words
	move.w	blit_lines.w,$38(a6)            ; 400 lines
	move.w	#$0,$3c(a6)                     ; from halftone line 0
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; each line should be its halftone word
blit_hop_lines_group:
	moveq	#1,d0                           ; line 0's word
blit_hop_lines_line:
	move.w	blit_words.w,d1                 ; the words in a line
	subq.w	#1,d1
blit_hop_lines_word:
	cmp.w	(a0)+,d0                        ; right?
	beq.w	blit_hop_lines_next_word        ; yes
	bset	#$3,test_errors.w               ; G4 halftone op failed
	bra.w	blit_skew_test                  ; the skew test
blit_hop_lines_next_word:
	dbra	d1,blit_hop_lines_word          ; the next word
	lsl.w	#1,d0                           ; the next line's word
	bcc.s	blit_hop_lines_line             ; 16 lines
	cmpa.l	#$77d00,a0                      ; all 400 lines?
	bne.s	blit_hop_lines_group            ; no
	move.b	#$3,$3a(a6)                     ; HOP 3: source AND halftone
	move.w	#$aaaa,d0                       ; the halftone RAM $AAAA
	lea	$ffff8a00.w,a0                  ; BLiTTER halftone RAM
	moveq	#16,d1                          ; 16 words
	bsr.w	blit_fill_words                 ; filled
	move.w	#$5555,d0                       ; the source $5555
	lea	$60000,a0
	move.w	#$28,d1                         ; 40 words
	bsr.w	blit_fill_words                 ; filled
	move.w	#$ffff,d0                       ; the destination $FFFF
	move.w	#$28,d1                         ; 40 words
	lea	$70000,a0
	bsr.w	blit_fill_words                 ; filled
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	moveq	#0,d0                           ; all 0?
	lea	$70000,a0                       ; the destination
	moveq	#39,d1                          ; 40 words
blit_hop_and_check:
	cmp.w	(a0)+,d0
	beq.w	blit_hop_and_next               ; yes
	bset	#$3,test_errors.w               ; G4 halftone op failed
blit_hop_and_next:
	dbra	d1,blit_hop_and_check           ; the next word
blit_skew_test:
	move.b	#$3,$3b(a6)                     ; G5: op 3, the source
	move.b	#$2,$3a(a6)                     ; HOP 2, source only
	move.w	#$1,$28(a6)                     ; the first word's mask
	move.w	#$ffff,$2a(a6)                  ; the middle words' mask
	move.w	#$fffe,$2c(a6)                  ; the last word's mask
	moveq	#0,d0                           ; the destination 0
	lea	$70000,a0
	move.w	blit_words.w,d1
	bsr.w	blit_fill_words                 ; filled
	move.w	#$aaaa,d0                       ; the source $AAAA
	lea	$60000,a0
	bsr.w	blit_fill_words                 ; filled
	move.b	#$4f,$3d(a6)                    ; NFSR, skew 15
	addi.w	#$1,blit_words.w                ; one word more
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	bsr.w	blit_check_skew                 ; 1, $5555 .., $5554?
	beq.w	blit_fxsr_test                  ; yes
	bset	#$4,test_errors.w               ; G5 skew failed
blit_fxsr_test:
	lea	$60000,a0                       ; G7: the source $1234 x4, $5555
	move.w	#$1234,d0                       ; $1234
	moveq	#3,d7                           ; 4 words
blit_fxsr_fill:
	move.w	d0,(a0)+
	dbra	d7,blit_fxsr_fill
	move.w	#$5555,(a0)                     ; then $5555
	move.b	#$84,$3d(a6)                    ; FXSR, skew 4
	move.w	#$1,$38(a6)                     ; one line
	move.w	#$4,blit_words.w                ; 4 words
	lea	$70000,a0                       ; the destination 0
	move.w	#$10,d1                         ; 16 words
	moveq	#0,d0
	bsr.w	blit_fill_words                 ; filled
	move.w	#$ffff,$28(a6)                  ; full masks
	move.w	#$ffff,$2a(a6)
	move.w	#$ffff,$2c(a6)
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; $4123 x3, $4555?
	moveq	#2,d7                           ; 3 words
blit_fxsr_check:
	cmpi.w	#$4123,(a0)+                    ; $4123?
	bne.w	blit_fxsr_failed                ; no
	dbra	d7,blit_fxsr_check
	cmpi.w	#$4555,(a0)+                    ; then $4555?
	beq.w	blit_reverse_test               ; yes
blit_fxsr_failed:
	bset	#$5,test_errors.w               ; G7 force extra source read failed
blit_reverse_test:
	move.w	#$fffe,d1                       ; G6: increments -2
	bsr.w	blit_set_increments
	move.w	#$fffe,$28(a6)                  ; the masks for right to left
	move.w	#$ffff,$2a(a6)
	move.w	#$1,$2c(a6)
	move.w	#$aaaa,d0                       ; the source $AAAA, 80 words down to $60000
	move.w	#$50,d1                         ; 80 words
	lea	$60000,a0                       ; the source's top
	bsr.w	blit_fill_words_down            ; filled
	moveq	#0,d0                           ; the destination 0, 96 words down to $70000
	lea	$70000,a0                       ; the destination's top
	add.w	#$10,d1                         ; 96 words
	bsr.w	blit_fill_words_down            ; filled
	move.w	#$2,$38(a6)                     ; 2 lines
	move.b	#$4f,$3d(a6)                    ; NFSR, skew 15
	bsr.w	blit_start                      ; BLiT
	bsr.w	blit_check_reverse              ; $5554, $5555 .., 1 going down?
	beq.w	blit_smudge_test                ; yes
	bset	#$6,test_errors.w               ; G6 reverse blt failed
blit_smudge_test:
	lea	0(a6),a0                        ; G8: the halftone RAM
	moveq	#2,d1                           ; increments 2
	bsr.w	blit_set_increments             ; increments 2
	moveq	#0,d0                           ; 0, $1111 .. $FFFF
blit_smudge_halftone:
	move.w	d0,(a0)+
	add.w	#$1111,d0                       ; the next word
	cmpi.w	#$1110,d0                       ; 16 words?
	bne.s	blit_smudge_halftone            ; no
	lea	$60000,a0                       ; the source 0 .. 15
	moveq	#0,d0
blit_smudge_source:
	move.w	d0,(a0)+
	addq.w	#1,d0
	cmpi.w	#$10,d0                         ; 16 words?
	bne.s	blit_smudge_source              ; no
	lea	$70000,a0                       ; the destination 0
	move.w	#$20,d1                         ; 32 words
	moveq	#0,d0
	bsr.w	blit_fill_words                 ; cleared
	move.b	#$1,$3a(a6)                     ; HOP 1: the halftone only
	move.b	#$3,$3b(a6)                     ; op 3
	move.b	#$0,$3d(a6)                     ; no skew
	move.b	#$20,$3c(a6)                    ; smudge: the source picks the halftone word
	move.w	#$ffff,$28(a6)                  ; full masks
	move.w	#$ffff,$2a(a6)
	move.w	#$ffff,$2c(a6)
	move.w	#$10,blit_words.w               ; 16 words
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; 0, $1111 .. $FFFF?
	moveq	#0,d0
blit_smudge_check:
	cmp.w	(a0)+,d0                        ; right?
	bne.w	blit_smudge_failed              ; no
	add.w	#$1111,d0                       ; the next one
	cmpi.w	#$1110,d0                       ; all 16?
	bne.s	blit_smudge_check               ; no
	bra.w	blit_x_count_test               ; yes
blit_smudge_failed:
	bset	#$7,test_errors.w               ; G8 smudge failed
blit_x_count_test:
	move.b	#$3,$3b(a6)                     ; G9: op 3
	move.b	#$2,$3a(a6)                     ; HOP 2
	move.w	#$ffff,d0                       ; full masks
	move.w	d0,$28(a6)
	move.w	d0,$2a(a6)
	move.w	d0,$2c(a6)
	move.w	#$3ffe,$20(a6)                  ; x increments $3FFE
	move.w	#$3ffe,$2e(a6)
	move.w	#$2,$22(a6)                     ; y increments 2
	move.w	#$2,$30(a6)
	move.w	#$2,$38(a6)                     ; 2 lines
	move.w	#$2,blit_words.w                ; 2 words
	move.w	#$aaaa,d0                       ; the source words at 0, $3FFE, $4000, $7FFE
	lea	$60000,a0
	move.w	d0,(a0)                         ; the first line's words
	move.w	d0,$3ffe(a0)
	move.w	d0,$4000(a0)                    ; the second line's
	move.w	d0,$7ffe(a0)
	lea	$70000,a0                       ; the destination's cleared
	moveq	#0,d0
	move.w	d0,(a0)
	move.w	d0,$3ffe(a0)
	move.w	d0,$4000(a0)
	move.w	d0,$7ffe(a0)
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; all four copied?
	move.w	#$aaaa,d0
	cmp.w	(a0),d0
	bne.w	blit_x_count_failed             ; no
	cmp.w	$3ffe(a0),d0
	bne.w	blit_x_count_failed             ; no
	cmp.w	$4000(a0),d0
	bne.w	blit_x_count_failed             ; no
	cmp.w	$7ffe(a0),d0
	beq.w	blit_y_count_test               ; yes
blit_x_count_failed:
	bset	#$0,test_errors_high.w          ; G9 x count failed
blit_y_count_test:
	move.w	#$3ffe,$22(a6)                  ; G10: y increments $3FFE
	move.w	#$3ffe,$30(a6)
	move.w	#$2,$20(a6)                     ; x increments 2
	move.w	#$2,$2e(a6)
	move.w	#$2,$38(a6)                     ; 2 lines
	move.w	#$2,blit_words.w                ; 2 words
	move.w	#$aaaa,d0                       ; the source words at 0, 2, $4000, $4002
	lea	$60000,a0
	move.w	d0,(a0)                         ; the first line's words
	move.w	d0,2(a0)
	move.w	d0,$4000(a0)                    ; the second line's
	move.w	d0,$4002(a0)
	lea	$70000,a0                       ; the destination's cleared
	moveq	#0,d0
	move.w	d0,(a0)
	move.w	d0,2(a0)
	move.w	d0,$4000(a0)
	move.w	d0,$4002(a0)
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; all four copied?
	move.w	#$aaaa,d0
	cmp.w	(a0),d0
	bne.w	blit_y_count_failed             ; no
	cmp.w	2(a0),d0
	bne.w	blit_y_count_failed             ; no
	cmp.w	$4000(a0),d0
	bne.w	blit_y_count_failed             ; no
	cmp.w	$4002(a0),d0
	beq.w	blit_short_report               ; yes
blit_y_count_failed:
	bset	#$1,test_errors_high.w          ; G10 y count failed
blit_short_report:
	move.b	test_errors_high.w,d3           ; the failure bits, $676 low
	lsl.w	#8,d3                           ; $677 high
	move.b	test_errors.w,d3
	moveq	#0,d1                           ; bit 0 first
	moveq	#0,d2
	lea	blit_error_messages(pc),a0      ; the "Gn" texts
blit_short_report_next:
	btst	d1,d3                           ; failed?
	beq.w	blit_short_report_skip          ; no
	movea.l	0(a0,d2.w),a5                   ; its text
	bsr.w	print_string                    ; printed
blit_short_report_skip:
	add.l	#$4,d2                          ; the next text
	addq.w	#1,d1                           ; the next bit
	cmp.l	#$30,d2                         ; all 12?
	blt.s	blit_short_report_next          ; no
	move.b	test_errors.w,d0                ; any failure?
	or.b	test_errors_high.w,d0
	beq.w	blit_short_pass                 ; no
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
	bra.w	blit_short_result
blit_short_pass:
	lea	msg_pass,a5                     ; "Pass"
blit_short_result:
	bsr.w	show_result                     ; the result
	rts

;------------------------------------------------------------------------------
; blit_error_messages: the short BLiT test's error texts, one for each error bit: bits 0-7 in
; $676, bits 8-11 in $677. Bits 5 and 6 point at G7 and G6 (the other way round to their
; numbers).
;------------------------------------------------------------------------------
blit_error_messages:	; from: blit_short_test
	dc.l	msg_blit_halftone_ram           ; bit 0: G1 halftone RAM
	dc.l	msg_blit_endmask                ; bit 1: G2 endmask
	dc.l	msg_blit_operation              ; bit 2: G3 operation
	dc.l	msg_blit_halftone_op            ; bit 3: G4 halftone op
	dc.l	msg_blit_skew                   ; bit 4: G5 skew
	dc.l	msg_blit_fxsr                   ; bit 5: G7 force extra source read
	dc.l	msg_blit_reverse                ; bit 6: G6 reverse blt
	dc.l	msg_blit_smudge                 ; bit 7: G8 smudge
	dc.l	msg_blit_x_count                ; bit 8: G9 x count
	dc.l	msg_blit_y_count                ; bit 9: G10 y count
	dc.l	msg_blit_time_out               ; bit 10: G11 time-out
	dc.l	msg_blit_address_count          ; bit 11: G12 address count

;------------------------------------------------------------------------------
; blit_op_test: G3.  BLiTs one line of $4FA words with each of the 16 operations, the source filled
; with $4F4 and the destination with $4F6, and checks the result against blit_op_result.  Sets bit 2
; of $676 on a mismatch.
;------------------------------------------------------------------------------
blit_op_test:	; from: blit_short_test
	moveq	#0,d0                           ; op 0
blit_op_test_next:
	move.b	d0,$3b(a6)                      ; the operation
	move.w	blit_source_word.w,d0           ; the source
	move.w	blit_words.w,d1
	lea	$60000,a0
	bsr.w	blit_fill_words                 ; filled
	move.w	blit_dest_word.w,d0             ; the destination
	lea	$70000,a0
	bsr.w	blit_fill_words                 ; filled
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	bsr.w	blit_op_result                  ; the expected word
	lea	$70000,a0                       ; the line all that?
	move.w	blit_words.w,d1
	bsr.w	blit_check_words                ; checked
	beq.w	blit_op_test_step               ; yes
	bset	#$2,test_errors.w               ; G3 operation failed
blit_op_test_step:
	move.b	$3b(a6),d0                      ; the next operation
	addq.w	#1,d0
	cmpi.b	#$10,d0                         ; all 16?
	bne.s	blit_op_test_next               ; no
	rts

;------------------------------------------------------------------------------
; blit_start: BLiTs $4FA words a line from $60000 to $70000 (the other registers already set) and
; waits for the busy bit to clear.  A time-out sets bit 2 of $677 (G11).
;------------------------------------------------------------------------------
blit_start:	; from: blit_short_test, blit_op_test
	move.l	#$70000,$32(a6)                 ; the destination
	move.l	#$60000,$24(a6)                 ; the source
	move.w	blit_words.w,$36(a6)            ; the x count
	bset	#$7,$3c(a6)                     ; busy: go
	move.l	#$100000,d7                     ; the time-out (counted as a word: 65,536)
blit_start_wait:
	btst	#$7,$3c(a6)                     ; still busy?
	beq.w	blit_start_end                  ; no
	subq.w	#1,d7                           ; the time-out counted down
	bne.s	blit_start_wait
	bset	#$2,test_errors_high.w          ; G11 time-out
	andi.b	#$1f,ccr                        ; (no flag changed)
blit_start_end:
	rts

;------------------------------------------------------------------------------
; blit_set_increments: d1 into the source and destination x and y increments.
;------------------------------------------------------------------------------
blit_set_increments:	; from: blit_short_test
	move.w	d1,$20(a6)                      ; source x
	move.w	d1,$2e(a6)                      ; destination x
	move.w	d1,$22(a6)                      ; source y
	move.w	d1,$30(a6)                      ; destination y
	rts

;------------------------------------------------------------------------------
; blit_op_result: works out the operation's result in the CPU.  In: the BLiTTER's op register,
; $4F4 the source word, $4F6 the destination word.  Out: d0.w the result.  Uses d1-d2, a0-a1.
;------------------------------------------------------------------------------
blit_op_result:	; from: blit_op_test
	clr.l	d2
	move.b	$3b(a6),d2                      ; the operation
	lsl.w	#2,d2
	move.w	blit_source_word.w,d0           ; source
	move.w	blit_dest_word.w,d1             ; destination
	lea	blit_op_emulation_table,a0      ; the table
	movea.l	0(a0,d2.w),a1                   ; its routine
	jmp	(a1)                            ; the result made

;------------------------------------------------------------------------------
; blit_op_emulation_table: the 16 BLiTTER logic operations done in software to work out the
; expected result. Entered with d0 = source word, d1 = destination word; returns d0.
;------------------------------------------------------------------------------
blit_op_emulation_table:
	dc.l	blit_op_zero                    ; 0: all zeros
	dc.l	blit_op_and                     ; 1: S and D
	dc.l	blit_op_and_not_dest            ; 2: S and not D
	dc.l	blit_op_source                  ; 3: S
	dc.l	blit_op_not_source_and          ; 4: not S and D
	dc.l	blit_op_dest                    ; 5: D
	dc.l	blit_op_xor                     ; 6: S xor D
	dc.l	blit_op_or                      ; 7: S or D
	dc.l	blit_op_nor                     ; 8: not S and not D
	dc.l	blit_op_xnor                    ; 9: not S xor D
	dc.l	blit_op_not_dest                ; 10: not D
	dc.l	blit_op_or_not_dest             ; 11: S or not D
	dc.l	blit_op_not_source              ; 12: not S
	dc.l	blit_op_not_source_or           ; 13: not S or D
	dc.l	blit_op_nand                    ; 14: not S or not D
	dc.l	blit_op_one                     ; 15: all ones
blit_op_zero:
	moveq	#0,d0                           ; 0
	rts
blit_op_and:
	and.w	d1,d0                           ; S AND D
	rts
blit_op_and_not_dest:
	not.w	d1
	and.w	d1,d0                           ; S AND NOT D
	rts
blit_op_source:
	rts
blit_op_not_source_and:
	not.w	d0
	and.w	d1,d0                           ; NOT S AND D
	rts
blit_op_dest:
	move.w	d1,d0                           ; D
	rts
blit_op_xor:
	eor.w	d1,d0                           ; S XOR D
	rts
blit_op_or:
	or.w	d1,d0                           ; S OR D
	rts
blit_op_nor:
	not.w	d0
	not.w	d1
	and.w	d1,d0                           ; NOT S AND NOT D
	rts
blit_op_xnor:
	not.w	d0
	eor.w	d1,d0                           ; NOT S XOR D
	rts
blit_op_not_dest:
	not.w	d1
	move.w	d1,d0                           ; NOT D
	rts
blit_op_or_not_dest:
	not.w	d1
	or.w	d1,d0                           ; S OR NOT D
	rts
blit_op_not_source:
	not.w	d0                              ; NOT S
	rts
blit_op_not_source_or:
	not.w	d0
	or.w	d1,d0                           ; NOT S OR D
	rts
blit_op_nand:
	not.w	d0
	not.w	d1
	or.w	d1,d0                           ; NOT S OR NOT D
	rts
blit_op_one:
	moveq	#-1,d0                          ; all ones
	rts

;------------------------------------------------------------------------------
; blit_check_words: checks d1 words from a0 against d0.  Out: Z set when all match, else a0 at
; the first wrong word.
;------------------------------------------------------------------------------
blit_check_words:	; from: blit_short_test, blit_op_test
	subq.w	#1,d1
blit_check_words_loop:
	cmp.w	(a0)+,d0                        ; the same?
	bne.w	blit_check_words_wrong          ; wrong
	dbra	d1,blit_check_words_loop        ; the next
	rts
blit_check_words_wrong:
	subq.w	#2,a0                           ; a0 back at it
	rts

;------------------------------------------------------------------------------
; blit_check_skew: checks the G5 result at $70000: 1, then $5555 words, then $5554 ($4FA words in
; all).  Out: Z set when right.
;------------------------------------------------------------------------------
blit_check_skew:	; from: blit_short_test
	lea	$70000,a0                       ; the result
	move.w	blit_words.w,d7
	subq.w	#3,d7                           ; the middle words
	cmpi.w	#$1,(a0)+                       ; the first
	bne.w	blit_check_skew_end             ; wrong
blit_check_skew_loop:
	cmpi.w	#$5555,(a0)+                    ; $5555?
	bne.w	blit_check_skew_end             ; wrong
	dbra	d7,blit_check_skew_loop         ; the next
	cmpi.w	#$5554,(a0)+                    ; the last
blit_check_skew_end:
	rts

;------------------------------------------------------------------------------
; blit_check_reverse: checks the G6 result going down from $70000: $5554, $5555 words, then 1
; ($4FA words in all).  Out: Z set when right.
;------------------------------------------------------------------------------
blit_check_reverse:	; from: blit_short_test
	lea	$70000,a0                       ; the result
	adda.l	#$2,a0                          ; its last word
	move.w	blit_words.w,d7
	subq.w	#3,d7                           ; the middle words
	cmpi.w	#$5554,-(a0)                    ; the last
	bne.w	blit_check_reverse_end          ; wrong
blit_check_reverse_loop:
	cmpi.w	#$5555,-(a0)                    ; $5555?
	bne.w	blit_check_reverse_end          ; wrong
	dbra	d7,blit_check_reverse_loop      ; the next
	cmpi.w	#$1,-(a0)                       ; the first
blit_check_reverse_end:
	rts

;------------------------------------------------------------------------------
; blit_fill_words: fills d1 words from a0 up with d0.  d1 and a0 kept.
;------------------------------------------------------------------------------
blit_fill_words:	; from: blit_short_test, blit_op_test
	movem.l	d1/a0,-(sp)                     ; kept
	subq.w	#1,d1
blit_fill_words_loop:
	move.w	d0,(a0)+                        ; stored
	dbra	d1,blit_fill_words_loop         ; the next
	movem.l	(sp)+,d1/a0                     ; back
	rts

;------------------------------------------------------------------------------
; blit_fill_words_down: fills d1 words with d0 going down, ending at the word at a0.  d1 and a0
; kept.
;------------------------------------------------------------------------------
blit_fill_words_down:	; from: blit_short_test
	movem.l	d1/a0,-(sp)                     ; kept
	subq.w	#1,d1
	adda.l	#$2,a0                          ; past the top word
blit_fill_words_down_loop:
	move.w	d0,-(a0)                        ; stored going down
	dbra	d1,blit_fill_words_down_loop    ; the next
	movem.l	(sp)+,d1/a0                     ; back
	rts

;------------------------------------------------------------------------------
; blit_check_present: reads the BLiTTER's halftone RAM with the bus error vector caught.
; Out: Z set and bit 0 of $28E set when the BLiTTER is there; Z clear and the bit clear when not.
; Uses d0, d7, a0, a4.
;------------------------------------------------------------------------------
blit_check_present:	; from: menu_start, blit_short_test, blit_long_test
	ori.b	#$1,clock_flags.w               ; the BLiTTER found
	movea.l	$8.w,a4                         ; the old bus error vector
	lea	blit_check_present_bus_error(pc),a0 ; the probe's handler
	move.l	a0,$8.w                         ; bus error vector, caught
	clr.w	d7                              ; no bus error yet
	move.b	$ffff8a00.w,d0                  ; BLiTTER halftone RAM, the halftone RAM read
	nop
	move.l	a4,$8.w                         ; the bus error vector back
	tst.w	d7                              ; a bus error?
	beq.w	blit_check_present_end          ; no
	andi.b	#$fe,clock_flags.w              ; no BLiTTER
	andi.b	#$fb,ccr                        ; Z clear
blit_check_present_end:
	rts
blit_check_present_bus_error:
	move.w	#$ff,d7                         ; noted
	adda.w	#$8,sp                          ; the bus error frame's extra 8 bytes dropped
	rte                                     ; on past the read

;------------------------------------------------------------------------------
; blit_long_test: menu Y.  Shows a screen of its own at $70000 and, with Line-A style drawing
; through the BLiTTER, fills and outlines a triangle whose third corner is moved left, up, right and
; down a pixel at a time, redrawing it each step.  Esc stops it.  A bus error during a BLiT prints
; "Replace Blitter" and ends the test.  The old screen is put back, then "Pass" unless stopped.
;------------------------------------------------------------------------------
blit_long_test:	; from: test_routines
	lea	msg_testing_blitter,a5          ; "Testing Blitter"
	bsr.w	show_status                     ; on the status line
	bsr.s	blit_check_present              ; a BLiTTER there?
	beq.s	blit_long_present               ; yes
	move.w	#$500,$ffff8240.w               ; palette 0, no: the background red
	lea	msg_no_blitter,a5               ; "No Blitter installed"
	bsr.w	print_string                    ; printed
	rts
blit_long_present:
	move.l	sp,blit_lines.w                 ; the stack kept for the bus error
	bsr.w	blit_long_set_up                ; the screen and the drawing set up
	movea.l	a0,a5                           ; a5: the drawing variables
	lea	blit_long_triangle.w,a1         ; the triangle's corners
	move.l	a1,blit_long_corners.w          ; the corners in use
	bsr.w	blit_long_draw_triangle         ; outlined
	bsr.w	blit_long_draw                  ; filled and outlined
	bsr.w	blit_long_move_left             ; the corner left
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_finish                ; yes
	bsr.w	blit_long_move_up               ; up
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_finish                ; yes
	bsr.w	blit_long_move_right            ; right
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_finish                ; yes
	bsr.w	blit_long_move_down             ; down
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_finish                ; yes
	bsr.w	blit_long_move_left             ; left again
	move.b	#$0,d0                          ; passed
blit_long_finish:	; from: blit_long_bus_error
	move.l	blit_long_saved_screen.w,screen_base.w ; the old screen back
	move.l	blit_long_saved_screen.w,d1
	swap	d1                              ; its high byte
	move.b	d1,$ffff8201.w                  ; video base high, the video base
blit_long_finish_wait_screen:
	cmp.b	$ffff8205.w,d1                  ; video count high, until the video counter is there
	bne.s	blit_long_finish_wait_screen
	movea.l	blit_source_word.w,a4           ; the old bus error vector back
	move.l	a4,$8.w                         ; bus error vector
	cmp.b	#$0,d0                          ; stopped or failed?
	bne.s	blit_long_end                   ; yes
	lea	msg_pass,a5                     ; "Pass"
	bsr.w	show_result                     ; shown
blit_long_end:
	rts

;------------------------------------------------------------------------------
; blit_long_set_up: moves the screen to $70000 (the old one kept at $3B8), clears it and sets up the
; drawing variables at $32A: one plane, 80 bytes a line, the triangle at $3BC and $3CC, the fill
; patterns, clipping to 320 x 200.  The bus error vector points at blit_long_bus_error (the old one
; kept at $4F4).  Out: a0 = $32A.  Uses d0-d1, a1-a5.
;------------------------------------------------------------------------------
blit_long_set_up:	; from: blit_long_test
	move.l	#$70000,d0                      ; the test screen
	move.l	screen_base.w,blit_long_saved_screen.w ; the old screen kept
	move.l	d0,screen_base.w                ; the screen used for the text
	movea.l	d0,a5
	swap	d0                              ; its high byte
	move.b	d0,$ffff8201.w                  ; video base high, the video base
blit_long_set_up_wait_screen:
	cmp.b	$ffff8205.w,d0                  ; video count high, until the video counter is there
	bne.s	blit_long_set_up_wait_screen
	moveq	#0,d0                           ; cleared
	move.l	#$2000,d1                       ; 32K
blit_long_set_up_clear:
	move.l	d0,(a5)+                        ; cleared
	dbra	d1,blit_long_set_up_clear
	lea	msg_testing_blitter,a5          ; "Testing Blitter"
	bsr.w	show_status                     ; on the status line
	lea	draw_planes.w,a0                ; the drawing variables
	lea	long_blit_shape_1,a2            ; the first triangle
	moveq	#7,d0                           ; 8 words each
	lea	blit_long_points.w,a1           ; the points
	move.l	a1,$c(a0)                       ; the points
	lea	blit_long_triangle.w,a3         ; the moving triangle
	lea	long_blit_shape_2,a4            ; its corners
blit_long_set_up_points:
	move.w	(a2)+,(a1)+                     ; copied
	move.w	(a4)+,(a3)+
	dbra	d0,blit_long_set_up_points
	lea	long_blit_word_pair,a1          ; the point count
	move.l	a1,4(a0)                        ; CONTRL
	move.w	#$1,0(a0)                       ; 1 plane
	move.w	#$50,-$2(a0)                    ; 80 bytes a line
	move.w	#$50,2(a0)                      ; 80 bytes a line
	move.w	#$1,$18(a0)                     ; colour bits all 1
	move.w	#$1,$1a(a0)
	move.w	#$1,$1c(a0)
	move.w	#$1,$1e(a0)
	move.w	#$0,$24(a0)                     ; replace mode
	lea	long_blit_fill_pattern,a1       ; the fill patterns
	move.l	a1,$2e(a0)
	move.w	#$f,$32(a0)                     ; 16 lines of pattern
	move.w	#$0,$34(a0)                     ; one plane of pattern
	move.w	#$1,$36(a0)                     ; clipping on
	move.w	#$0,$38(a0)                     ; x from 0
	move.w	#$13f,$3c(a0)                   ; to 319
	move.w	#$0,$3a(a0)                     ; y from 0
	move.w	#$c7,$3e(a0)                    ; to 199
	move.w	#$ffff,$22(a0)                  ; solid lines
	move.w	#$0,$20(a0)                     ; not the last line
	movea.l	$8.w,a4                         ; the old bus error vector
	move.l	a4,blit_source_word.w           ; kept
	lea	blit_long_bus_error,a4          ; caught
	move.l	a4,$8.w                         ; bus error vector
	rts

;------------------------------------------------------------------------------
; blit_long_bus_error: bus error during the long BLiT test: the BLiTTER stopped, the background red,
; the old screen back and "Replace Blitter / Bus error has occurred during BLiT test!" printed, then
; the test ends with d0 = $FF.
;------------------------------------------------------------------------------
blit_long_bus_error:	; from: blit_long_set_up
	lea	$ff8a3c,a5                      ; the BLiTTER control
	bclr	#$7,(a5)                        ; stopped
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	move.l	blit_long_saved_screen.w,screen_base.w ; the old screen
	move.l	blit_long_saved_screen.w,d0
	swap	d0                              ; its high byte
	move.b	d0,$ffff8201.w                  ; video base high, the video base
blit_long_bus_error_wait_screen:
	cmp.b	$ffff8205.w,d0                  ; video count high, until the video counter is there
	bne.s	blit_long_bus_error_wait_screen
	lea	msg_replace_blitter,a5          ; "Replace Blitter"
	bsr.w	print_string                    ; printed
	movea.l	blit_lines.w,sp                 ; the test's stack
	move.b	#$ff,d0                         ; failed
	lea	blit_long_finish,a1
	jmp	(a1)                            ; the test ends

;------------------------------------------------------------------------------
; blit_long_move_left: moves the third corner of the triangle at $3CC left to x 1, redrawing each
; step.  Out: d0 = 27 when Esc was pressed.
;------------------------------------------------------------------------------
blit_long_move_left:	; from: blit_long_test
	lea	blit_long_triangle.w,a1         ; the moving triangle
	move.w	8(a1),d0                        ; its x
	cmp.w	#$1,d0                          ; at 1?
	ble.w	blit_long_move_left_end         ; yes
	sub.w	#$1,d0                          ; one left
	move.w	d0,8(a1)
	bsr.w	blit_long_draw                  ; redrawn
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_move_left_end         ; yes
	bra.s	blit_long_move_left             ; again
blit_long_move_left_end:
	rts

;------------------------------------------------------------------------------
; blit_long_move_up: moves the third corner up to y 20.  Out: d0 = 27 when Esc was pressed.
;------------------------------------------------------------------------------
blit_long_move_up:	; from: blit_long_test
	lea	blit_long_triangle.w,a1         ; the moving triangle
	move.w	$a(a1),d0                       ; its y
	cmp.w	#$14,d0                         ; at 20?
	ble.w	blit_long_move_up_end           ; yes
	sub.w	#$1,d0                          ; one up
	move.w	d0,$a(a1)
	bsr.w	blit_long_draw                  ; redrawn
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_move_up_end           ; yes
	bra.s	blit_long_move_up               ; again
blit_long_move_up_end:
	rts

;------------------------------------------------------------------------------
; blit_long_move_right: moves the third corner right to x 319.  Out: d0 = 27 when Esc was pressed.
;------------------------------------------------------------------------------
blit_long_move_right:	; from: blit_long_test
	lea	blit_long_triangle.w,a1         ; the moving triangle
	move.w	8(a1),d0                        ; its x
	cmp.w	#$13f,d0                        ; at 319?
	bge.w	blit_long_move_right_end        ; yes
	add.w	#$1,d0                          ; one right
	move.w	d0,8(a1)
	bsr.w	blit_long_draw                  ; redrawn
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_move_right_end        ; yes
	bra.s	blit_long_move_right            ; again
blit_long_move_right_end:
	rts

;------------------------------------------------------------------------------
; blit_long_move_down: moves the third corner down to y 190.  Out: d0 = 27 when Esc was pressed.
;------------------------------------------------------------------------------
blit_long_move_down:	; from: blit_long_test
	lea	blit_long_triangle.w,a1         ; the moving triangle
	move.w	$a(a1),d0                       ; its y
	cmp.w	#$be,d0                         ; at 190?
	bge.w	blit_long_move_down_end         ; yes
	add.w	#$1,d0                          ; one down
	move.w	d0,$a(a1)
	bsr.w	blit_long_draw                  ; redrawn
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_move_down_end         ; yes
	bra.s	blit_long_move_down             ; again
blit_long_move_down_end:
	rts

;------------------------------------------------------------------------------
; blit_long_draw: fills the triangle at $3CC row by row over the 200 lines in replace mode, then
; again in reverse transparent mode, then outlines it.  Out: d0 the key pressed, or 0.
; In: a5 the drawing variables.
;------------------------------------------------------------------------------
blit_long_draw:                                 ; from: blit_long_test, blit_long_move_left, blit_long_move_up,
                                                ;   blit_long_move_right, blit_long_move_down
	moveq	#0,d3                           ; the first pass
blit_long_draw_pass:
	lea	blit_long_triangle.w,a2         ; the points
	move.l	a2,$c(a5)                       ; PTSIN
	move.w	#$0,$28(a5)                     ; from line 0
	move.w	#$c7,d4                         ; 200 lines
	sub.w	#$0,d4                          ; (from line 0)
blit_long_draw_row:
	movem.l	d3-d4/a5,-(sp)                  ; kept
	bsr.w	blit_fill_row                   ; the row filled
	movem.l	(sp)+,d3-d4/a5
	addq.w	#1,$28(a5)                      ; the next line
	dbra	d4,blit_long_draw_row           ; the next line
	cmp.w	#$0,d3                          ; the second pass done?
	bne.w	blit_long_draw_outline          ; yes
	moveq	#15,d3                          ; the second pass
	move.w	#$3,$24(a5)                     ; reverse transparent
	bra.s	blit_long_draw_pass             ; again
blit_long_draw_outline:
	move.w	#$0,$24(a5)                     ; replace
	bsr.w	blit_long_draw_triangle         ; the outline, the outline
	moveq	#0,d0                           ; a key?
	bsr.w	key_waiting
	beq.w	blit_long_draw_end              ; no
	bsr.w	get_key                         ; read it
blit_long_draw_end:
	rts

;------------------------------------------------------------------------------
; blit_long_draw_triangle: draws the three sides of the triangle at ($3B4): corner 1 to 2, 1 to 3,
; 2 to 3.  In: a5 the drawing variables.  Uses a2.
;------------------------------------------------------------------------------
blit_long_draw_triangle:	; from: blit_long_test, blit_long_draw
	movea.l	blit_long_corners.w,a2          ; the corners
	move.w	(a2),$26(a5)                    ; x1
	move.w	2(a2),$28(a5)                   ; y1
	move.w	4(a2),$2a(a5)                   ; x2
	move.w	6(a2),$2c(a5)                   ; y2
	movem.l	a0-a5,-(sp)                     ; kept
	bsr.w	blit_draw_line                  ; the line
	movem.l	(sp)+,a0-a5
	move.w	(a2),$26(a5)                    ; corner 1
	move.w	2(a2),$28(a5)                   ; y1
	move.w	8(a2),$2a(a5)                   ; to corner 3
	move.w	$a(a2),$2c(a5)                  ; y2
	movem.l	a0-a5,-(sp)                     ; kept
	bsr.w	blit_draw_line                  ; the line
	movem.l	(sp)+,a0-a5
	move.w	4(a2),$26(a5)                   ; corner 2
	move.w	6(a2),$28(a5)                   ; y1
	move.w	8(a2),$2a(a5)                   ; to corner 3
	move.w	$a(a2),$2c(a5)                  ; y2
	movem.l	a0-a5,-(sp)                     ; kept
	bsr.w	blit_draw_line                  ; the line
	movem.l	(sp)+,a0-a5
	rts

;------------------------------------------------------------------------------
; blit_fill_row: fills one scan line (y1, $352) of the polygon whose points are at PTSIN ($336),
; their count in CONTRL[1]: the x where each edge crosses the line is worked out, the crossings are
; sorted and each pair filled as a span (clipped when clipping is on).  Uses d0-d7, a0-a5.
;------------------------------------------------------------------------------
blit_fill_row:	; from: blit_long_draw
	lea	draw_planes.w,a4                ; the drawing variables
	movea.l	4(a4),a0                        ; CONTRL
	move.w	2(a0),d0                        ; the point count
	subq.w	#1,d0                           ; edges - 1
	movea.l	$c(a4),a0                       ; PTSIN
	lea	-$10(a4),a1                     ; the crossings
	clr.w	-$4(a4)                         ; none yet
blit_fill_row_edge:
	move.w	6(a0),d1                        ; the edge's height
	move.w	2(a0),d2                        ; its first y
	sub.w	d2,d1
	beq.w	blit_fill_row_next_edge         ; flat: skipped
	move.w	$28(a4),d3                      ; the line
	move.w	d3,d4
	sub.w	d2,d4                           ; from the first end
	sub.w	6(a0),d3                        ; from the second end
	move.w	d4,d2
	eor.w	d3,d2                           ; on opposite sides?
	bpl.w	blit_fill_row_next_edge         ; the line not between them: skipped
	move.w	4(a0),d2                        ; the edge's width
	sub.w	0(a0),d2
	add.w	d2,d2                           ; doubled
	muls.w	d2,d4                           ; times the line's distance from the first end
	divs.w	d1,d4                           ; the x offset, doubled
	bpl.w	blit_fill_row_round             ; positive?
	neg.w	d4                              ; rounded for negatives
	addq.w	#1,d4
	asr.w	#1,d4                           ; halved
	neg.w	d4
	bra.w	blit_fill_row_crossing
blit_fill_row_round:
	addq.w	#1,d4                           ; rounded
	asr.w	#1,d4                           ; halved
blit_fill_row_crossing:
	add.w	0(a0),d4                        ; plus the first end's x
	move.w	d4,(a1)+                        ; the crossing kept
	addq.w	#1,-$4(a4)                      ; counted
blit_fill_row_next_edge:
	lea	4(a0),a0                        ; the next edge
	dbra	d0,blit_fill_row_edge
	move.w	-$4(a4),d0                      ; any crossings?
	bne.w	blit_fill_row_spans             ; yes
	rts
blit_fill_row_spans:
	lea	-$10(a4),a0                     ; the crossings
	bsr.w	blit_sort_crossings             ; sorted
	move.w	-$4(a4),d0                      ; the crossings
	asr.w	#1,d0                           ; pairs
	subq.w	#1,d0
	tst.w	$36(a4)                         ; clipping?
	bne.w	blit_fill_row_clip_span         ; yes
blit_fill_row_span:
	move.w	(a1)+,$26(a4)                   ; from x
	move.w	(a1)+,$2a(a4)                   ; to x
	move.w	d0,-(sp)                        ; kept
	move.l	a1,-(sp)
	bsr.w	blit_fill_span                  ; the span filled
	movea.l	(sp)+,a1
	move.w	(sp)+,d0
	dbra	d0,blit_fill_row_span           ; the next pair
	rts
blit_fill_row_clip_span:
	move.w	(a1)+,$26(a4)                   ; from x
	move.w	(a1)+,$2a(a4)                   ; to x
	move.w	$38(a4),d1                      ; the left clip
	move.w	$26(a4),d2                      ; from x
	move.w	$2a(a4),d3                      ; to x
	cmp.w	d1,d2                           ; left of it?
	bge.w	blit_fill_row_clip_right        ; no
	cmp.w	d1,d3
	blt.w	blit_fill_row_clip_next         ; all left of it: skipped
	move.w	d1,$26(a4)                      ; clipped
blit_fill_row_clip_right:
	move.w	$3c(a4),d1                      ; the right clip
	cmp.w	d1,d3                           ; right of it?
	ble.w	blit_fill_row_clip_draw         ; no
	cmp.w	d1,d2
	bgt.w	blit_fill_row_clip_next         ; all right of it: skipped
	move.w	d1,$2a(a4)                      ; clipped
blit_fill_row_clip_draw:
	move.w	d0,-(sp)                        ; kept
	move.l	a1,-(sp)
	bsr.w	blit_fill_span                  ; the span filled
	lea	draw_planes.w,a4                ; the variables again
	movea.l	(sp)+,a1
	move.w	(sp)+,d0
blit_fill_row_clip_next:
	dbra	d0,blit_fill_row_clip_span      ; the next pair
	rts

;------------------------------------------------------------------------------
; blit_sort_crossings: sorts d0 words at a0 into ascending order (bubble sort).  Uses d0-d2, a0-a1.
;------------------------------------------------------------------------------
blit_sort_crossings:	; from: blit_fill_row
	subq.w	#2,d0                           ; fewer than 2: done
	bcs.w	blit_sort_crossings_end
	move.w	d0,d1                           ; passes
	movea.l	a0,a1                           ; the start
blit_sort_crossings_pass:
	move.w	d1,d0
	movea.l	a1,a0                           ; from the start
blit_sort_crossings_compare:
	move.w	(a0)+,d2                        ; this one
	cmp.w	(a0),d2                         ; in order?
	ble.w	blit_sort_crossings_next        ; yes
	move.w	(a0),-$2(a0)                    ; swapped
	move.w	d2,(a0)
blit_sort_crossings_next:
	dbra	d0,blit_sort_crossings_compare  ; the next pair
	dbra	d1,blit_sort_crossings_pass     ; the next pass
blit_sort_crossings_end:
	rts

;------------------------------------------------------------------------------
; blit_draw_line: draws a line from (x1,y1) to (x2,y2) ($350-$356) with the colour bits, line mask
; ($34C), writing mode ($34E) and last-line flag ($34A).  Horizontal lines are a BLiTTER span,
; vertical lines a BLiTTER column with the line mask in the halftone RAM, any other line is drawn by
; the CPU with the routines at blit_line_y_replace and on.  The line mask is rotated by the line's
; length.  Uses d0-d7, a0-a5.
;------------------------------------------------------------------------------
blit_draw_line:	; from: blit_long_draw_triangle
	lea	draw_planes.w,a4                ; the drawing variables
	moveq	#2,d0                           ; XOR mode is 2
	movem.w	$26(a4),d4-d7                   ; x1, y1, x2, y2
	cmp.w	d5,d7                           ; horizontal?
	beq.w	blit_line_horizontal            ; yes
	cmp.w	d4,d6                           ; vertical?
	bne.w	blit_line_diagonal              ; no: the CPU draws it
	lea	$ff8a3c,a5                      ; BLiTTER control, the BLiTTER
	not.w	d4                              ; the pixel's bit
	and.w	#$f,d4
	clr.w	d0
	bset	d4,d0
	move.w	d0,-$14(a5)                     ; end mask 1
	move.w	0(a4),d0                        ; planes
	move.w	d0,d1                           ; bytes per word group
	add.w	d1,d1
	subq.w	#1,d0                           ; planes - 1
	movea.l	screen_base.w,a1                ; the screen
	asr.w	#4,d6                           ; x's word
	muls.w	d6,d1                           ; times the word group size
	adda.l	d1,a1
	move.w	-$2(a4),d2                      ; bytes per line
	muls.w	d5,d2                           ; times y1
	adda.l	d2,a1                           ; the first pixel's word
	moveq	#7,d2                           ; 16 halftone words
	move.w	2(a4),d1                        ; bytes per line
	lea	$22(a4),a3                      ; the line mask
	move.w	(a3),d3
	sub.w	d5,d7                           ; the height
	bge.w	blit_line_vertical_down         ; downwards?
	neg.w	d7                              ; upwards
	neg.w	d1                              ; going up
	lea	-$1c(a5),a0                     ; the halftone RAM filled from the end
blit_line_vertical_up_mask:
	add.w	d3,d3                           ; each mask bit
	subx.w	d4,d4                           ; to a 0 or $FFFF word
	move.w	d4,-(a0)
	add.w	d3,d3
	subx.w	d4,d4
	move.w	d4,-(a0)
	dbra	d2,blit_line_vertical_up_mask   ; 16 times
	move.w	#$8f00,d2                       ; busy, from halftone line 15
	bra.w	blit_line_vertical_set_up
blit_line_vertical_down:
	lea	-$3c(a5),a0                     ; the halftone RAM filled from the start
blit_line_vertical_down_mask:
	add.w	d3,d3                           ; each mask bit
	subx.w	d4,d4                           ; to a 0 or $FFFF word
	move.w	d4,(a0)+
	add.w	d3,d3
	subx.w	d4,d4
	move.w	d4,(a0)+
	dbra	d2,blit_line_vertical_down_mask ; 16 times
	move.w	#$8000,d2                       ; busy, from halftone line 0
blit_line_vertical_set_up:
	move.w	d1,-$c(a5)                      ; destination y increment
	addq.w	#1,d7                           ; the pixel count
	lea	blit_mode_operations(pc),a2     ; the writing mode's operations
	move.w	$24(a4),d1
	lsl.w	#2,d1                           ; 4 bytes a mode
	adda.w	d1,a2
	subq.w	#8,d1                           ; XOR?
	bne.w	blit_line_vertical_count        ; no
	tst.w	$20(a4)                         ; the last pixel drawn?
	bne.w	blit_line_vertical_count        ; yes
	subq.w	#1,d7                           ; no: one less
blit_line_vertical_count:
	move.w	d7,d1
	move.w	(a3),d3                         ; the line mask
	and.w	#$f,d1
	rol.w	d1,d3                           ; rotated by the length
	move.w	d3,(a3)                         ; kept
	lea	$18(a4),a3                      ; the colour bits
	moveq	#2,d4                           ; the offset for a set bit
	move.w	#$1,-$6(a5)                     ; one word wide
blit_line_vertical_plane:
	move.l	a1,-$a(a5)                      ; destination
	move.w	d7,-$4(a5)                      ; y count
	tst.w	(a3)+                           ; this plane's colour bit
	sne	d3
	and.w	d4,d3                           ; 0 or 2
	move.w	0(a2,d3.w),-$2(a5)              ; HOP and operation
	move.w	d2,(a5)                         ; go
	moveq	#7,d1
blit_line_vertical_wait:
	bset	d1,(a5)                         ; restarted until done
	nop
	bne.s	blit_line_vertical_wait
	addq.w	#2,a1                           ; the next plane
	dbra	d0,blit_line_vertical_plane
	rts
blit_line_horizontal:
	cmp.w	$24(a4),d0                      ; XOR mode?
	bne.w	blit_line_horizontal_draw       ; no
	tst.w	$20(a4)                         ; the last pixel drawn?
	bne.w	blit_line_horizontal_draw       ; yes
	cmp.w	d4,d6                           ; one pixel?
	beq.w	blit_line_horizontal_draw       ; yes
	blt.w	blit_line_horizontal_drop_last  ; right to left
	subq.w	#2,d6                           ; left to right: one back
blit_line_horizontal_drop_last:
	addq.w	#1,d6                           ; the last pixel dropped
	move.w	d6,$2a(a4)                      ; x2 changed
blit_line_horizontal_draw:
	cmp.w	d4,d6                           ; left to right?
	bge.w	blit_line_horizontal_ordered    ; yes
	exg	d4,d6
blit_line_horizontal_ordered:
	move.w	d6,d1                           ; the length
	sub.w	d4,d1
	addq.w	#1,d1
	and.w	#$f,d1                          ; the rotation
	lea	$22(a4),a0                      ; the line mask as the pattern
	clr.w	d0                              ; no pattern step
	move.w	d1,-(sp)                        ; kept
	bsr.w	blit_span                       ; the span
	move.w	(sp)+,d1
	move.w	(a0),d0                         ; the line mask
	rol.w	d1,d0                           ; rotated by the length
	move.w	d0,(a0)                         ; kept
	rts
blit_line_diagonal:
	lea	-$14(sp),sp                     ; room for the plane code
	move.w	0(a4),d3                        ; planes
	cmp.w	#$8,d3                          ; more than 8?
	bhi.w	blit_line_diagonal_end          ; yes: nothing drawn
	cmp.w	$24(a4),d0                      ; XOR mode?
	beq.w	blit_line_diagonal_order        ; yes: no plane code
	movea.l	sp,a2                           ; built on the stack
	bsr.w	blit_line_plane_code            ; the plane code built
blit_line_diagonal_order:
	cmp.w	d4,d6                           ; left to right?
	bge.w	blit_line_diagonal_set_up       ; yes
	exg	d4,d6                           ; swapped
	exg	d5,d7
blit_line_diagonal_set_up:
	sub.w	d4,d6                           ; dx
	moveq	#0,d1
	movea.l	d1,a5                           ; the routine index
	move.w	d4,d0                           ; the first pixel's bit
	not.w	d0
	and.w	#$f,d0
	bset	d0,d1
	movea.l	screen_base.w,a0                ; the screen
	move.w	0(a4),d3                        ; planes
	add.w	d3,d3                           ; bytes per word group
	move.w	-$2(a4),d2                      ; bytes per line
	muls.w	d5,d2                           ; times y1
	adda.l	d2,a0
	asr.w	#4,d4                           ; x's word
	muls.w	d3,d4                           ; times the word group size
	adda.l	d4,a0                           ; the first pixel's word
	move.w	2(a4),d0                        ; bytes per line
	sub.w	d5,d7                           ; dy
	bge.w	blit_line_diagonal_down         ; downwards?
	neg.w	d7
	neg.w	d0                              ; upwards
blit_line_diagonal_down:
	movea.w	d0,a1                           ; the line step
	cmp.w	d6,d7                           ; steeper than 45 degrees?
	bgt.w	blit_line_diagonal_y_major      ; yes
	exg	d6,d7                           ; no: x steps every pixel
	lea	$10(a5),a5                      ; the x major routines
blit_line_diagonal_y_major:
	move.w	d6,d4                           ; the Bresenham terms
	add.w	d4,d4                           ; 2 dx
	move.w	d4,d5
	sub.w	d7,d4                           ; 2 dx - dy: the error term
	move.w	d4,d6
	sub.w	d7,d6                           ; 2 dx - 2 dy
	move.w	$24(a4),d0                      ; the writing mode
	lsl.w	#2,d0                           ; 4 bytes a mode
	adda.w	d0,a5
	subq.w	#8,d0                           ; XOR?
	bne.w	blit_line_diagonal_mask         ; no
	tst.w	$20(a4)                         ; the last pixel drawn?
	bne.w	blit_line_diagonal_mask         ; yes
	subq.w	#1,d7                           ; no: one less
blit_line_diagonal_mask:
	lea	$22(a4),a3                      ; the line mask
	move.w	(a3),d0
	move.w	d7,d2                           ; the length
	addq.w	#1,d2
	and.w	#$f,d2
	rol.w	d2,d0                           ; rotated by the length
	move.w	(a3),d2                         ; the mask now
	move.w	d0,(a3)
	move.w	d1,d0                           ; the bit
	not.w	d0                              ; and the mask to clear it
	lea	blit_line_routines(pc,a5.w),a5  ; the routine
	movea.l	a5,a3
	adda.w	(a5)+,a3                        ; its step part
	movea.l	a3,a4                           ; its clear-a-pixel part
	suba.w	d3,a4                           ; back by the planes
	adda.w	(a5),a5                         ; its start
	jsr	(a5)                            ; the line drawn
blit_line_diagonal_end:
	lea	$14(sp),sp                      ; the stack space freed
	rts
blit_line_routines:
	dc.w	$006a,$004a,$0094,$0088,$00cc,$00b0,$008c,$007e ; pairs of offsets (step part, start), y major then x
                                                ;   major, by writing mode
	dc.w	$0102,$00e2,$012c,$0120,$0164,$0148,$0124,$0116

;------------------------------------------------------------------------------
; blit_line_plane_code: builds the per-plane code at a2 for the CPU line routines: "and.w d0,(a5)+"
; for each plane whose colour bit is 0, "or.w d1,(a5)+" for each one whose bit is 1, then
; "jmp (a3)".  In: d3 the planes.  Uses d0-d3, a0-a1.
;------------------------------------------------------------------------------
blit_line_plane_code:	; from: blit_draw_line
	subq.w	#1,d3                           ; planes - 1
	movem.w	blit_line_opcodes(pc),d0-d2     ; the three instructions
	movea.l	a2,a0
	lea	$18(a4),a1                      ; the colour bits
blit_line_plane_code_plane:
	tst.w	(a1)+                           ; bit set?
	bne.s	blit_line_plane_code_set        ; yes
	move.w	d0,(a0)+                        ; "and.w d0,(a5)+": cleared
	dbra	d3,blit_line_plane_code_plane   ; the next plane
	move.w	d2,(a0)+                        ; "jmp (a3)"
	rts
blit_line_plane_code_set:
	move.w	d1,(a0)+                        ; "or.w d1,(a5)+": set
	dbra	d3,blit_line_plane_code_plane   ; the next plane
	move.w	d2,(a0)+                        ; "jmp (a3)"
	rts

;------------------------------------------------------------------------------
; blit_line_opcodes: "and.w d0,(a5)+", "or.w d1,(a5)+" and "jmp (a3)", then the CPU line routines
; (code, reached only through blit_line_routines, so shown as words).  Each one rotates the line
; mask: in replace mode a set bit runs the plane code built on the stack and a clear one jumps into
; the run of "and.w d0,(a5)+" to clear the pixel in each plane; in transparent modes a clear bit
; leaves the pixel; in XOR mode a set bit runs "eor.w d1,(a5)+" for each plane.  Then the
; Bresenham terms are stepped, over d7 pixels.
;------------------------------------------------------------------------------
blit_line_opcodes:	; from: blit_line_plane_code
	dc.w	$c15d,$835d,$4ed3
blit_line_y_replace:
	dc.w	$e35a,$6400,$0006,$2a48,$4ed2,$2a48,$4ed4,$c15d
	dc.w	$c15d,$c15d,$c15d,$c15d,$c15d,$c15d,$c15d
blit_line_y_replace_step:
	dc.w	$d0c9
	dc.b	'JDk',0
	dc.w	$0014,$e258,$e259,$6400,$0004,$d0c3,$d846,$51cf
	dc.w	$ffcc,$4e75,$d845,$51cf,$ffc4,$4e75
blit_line_y_reverse:
	dc.w	$4642
blit_line_y_transparent:
	dc.w	$e35a,$6400,$0006,$2a48,$4ed2
blit_line_y_transparent_step:
	dc.w	$d0c9
	dc.b	'JDk',0
	dc.w	$0014,$e258,$e259,$6400,$0004,$d0c3,$d846,$51cf
	dc.w	$ffe0,$4e75,$d845,$51cf,$ffd8,$4e75
blit_line_y_xor:
	dc.w	$e35a,$6400,$0016,$2a48,$4ed4,$b35d,$b35d,$b35d
	dc.w	$b35d,$b35d,$b35d,$b35d,$b35d
blit_line_y_xor_step:
	dc.w	$d0c9
	dc.b	'JDk',0
	dc.w	$0012,$e259,$6400,$0004,$d0c3,$d846,$51cf,$ffd2
	dc.w	$4e75,$d845,$51cf,$ffca,$4e75
blit_line_x_replace:
	dc.w	$e35a,$6400,$0006,$2a48,$4ed2,$2a48,$4ed4,$c15d
	dc.w	$c15d,$c15d,$c15d,$c15d,$c15d,$c15d,$c15d
blit_line_x_replace_step:
	dc.w	$e258,$e259,$6400,$0004,$d0c3
	dc.b	'JDk',0
	dc.w	$000c,$d846,$d0c9,$51cf,$ffcc,$4e75,$d845,$51cf
	dc.w	$ffc4,$4e75
blit_line_x_reverse:
	dc.w	$4642
blit_line_x_transparent:
	dc.w	$e35a,$6400,$0006,$2a48,$4ed2
blit_line_x_transparent_step:
	dc.w	$e258,$e259,$6400,$0004,$d0c3
	dc.b	'JDk',0
	dc.w	$000c,$d846,$d0c9,$51cf,$ffe0,$4e75,$d845,$51cf
	dc.w	$ffd8,$4e75
blit_line_x_xor:
	dc.w	$e35a,$6400,$0016,$2a48,$4ed4,$b35d,$b35d,$b35d
	dc.w	$b35d,$b35d,$b35d,$b35d,$b35d
blit_line_x_xor_step:
	dc.w	$e259,$6400,$0004,$d0c3
	dc.b	'JDk',0
	dc.w	$000c,$d846,$d0c9,$51cf,$ffd2,$4e75,$d845,$51cf
	dc.w	$ffca,$4e75
blit_mode_operations:	; from: blit_draw_line, blit_span
	dc.w	$0100,$0103,$0104,$0107,$0106,$0106,$0101,$010d ; HOP 1 and the op for a 0 and a 1 colour bit: replace,
                                                ;   transparent, XOR, reverse transparent
blit_left_masks:	; from: blit_span
	dc.w	$ffff                           ; the first word's mask by x AND 15 (runs on into the next table)
blit_right_masks:	; from: blit_span
	dc.w	$7fff,$3fff,$1fff,$0fff,$07ff,$03ff,$01ff,$00ff ; inverted: the last word's mask by x AND 15
	dc.w	$007f,$003f,$001f,$000f,$0007,$0003,$0001,$0000

;------------------------------------------------------------------------------
; blit_fill_span: fills from x1 to x2 ($350, $354) on line y1 ($352) with the fill pattern's line
; (y1 AND the pattern mask; a new pattern per plane when multi-fill is set).  blit_span is the same
; with a0 the pattern word and d0 the step to the next plane's pattern.  The BLiTTER does each
; plane with HOP 1 and the writing mode's operation.  Uses d0-d7, a0-a5.
;------------------------------------------------------------------------------
blit_fill_span:	; from: blit_fill_row
	lea	draw_planes.w,a4                ; the drawing variables
	movem.w	$26(a4),d4-d6                   ; x1, y1, x2
	move.w	d5,d0                           ; the pattern line
	and.w	$32(a4),d0                      ; the pattern mask
	add.w	d0,d0
	movea.l	$2e(a4),a0                      ; the patterns
	adda.w	d0,a0                           ; the pattern line
	tst.w	$34(a4)                         ; multi-fill?
	sne	d0
	and.w	#$20,d0                         ; then 32 bytes to the next plane's

blit_span:	; from: blit_draw_line
	move.w	d4,d1                           ; the first word
	asr.w	#4,d1                           ; x1's word
	move.w	d6,d2                           ; the last word
	asr.w	#4,d2                           ; x2's word
	moveq	#15,d3
	and.w	d3,d4
	add.w	d4,d4
	move.w	blit_left_masks(pc,d4.w),d4     ; the left mask
	and.w	d3,d6
	add.w	d6,d6
	move.w	blit_right_masks(pc,d6.w),d6    ; the right mask
	not.w	d6
	sub.w	d1,d2                           ; words - 1
	bne.w	blit_span_set_up                ; more than one?
	and.w	d6,d4                           ; one word: both masks in one
blit_span_set_up:
	lea	$ff8a3c,a5                      ; BLiTTER control, the BLiTTER
	clr.w	-$1c(a5)                        ; source x increment 0
	addq.w	#1,d2                           ; words
	move.w	d2,-$6(a5)                      ; x count
	lea	-$14(a5),a3                     ; end masks
	move.w	d4,(a3)+                        ; end mask 1
	move.w	#$ffff,(a3)+                    ; end mask 2
	move.w	d6,(a3)+                        ; end mask 3
	move.w	(a4),d2                         ; planes
	move.w	d2,d7
	subq.w	#1,d7                           ; planes - 1
	add.w	d2,d2                           ; bytes per word group
	move.w	d2,(a3)+                        ; destination x increment
	movea.l	screen_base.w,a1                ; the screen
	muls.w	-$2(a4),d5                      ; times y1
	adda.l	d5,a1
	muls.w	d2,d1                           ; x's word
	adda.l	d1,a1                           ; the first word
	lea	-$3c(a5),a2                     ; the halftone RAM
	lea	$18(a4),a3                      ; the colour bits
	move.w	$24(a4),d2                      ; the writing mode
	add.w	d2,d2
	add.w	d2,d2                           ; 4 bytes a mode
	lea	blit_mode_operations(pc),a4     ; its operations
	adda.w	d2,a4
	moveq	#2,d3                           ; the offset for a set bit
	move.w	#$8000,d4                       ; busy
	moveq	#1,d6                           ; one line
blit_span_plane:
	move.w	(a0),(a2)                       ; the pattern word
	adda.w	d0,a0                           ; the next plane's
	move.l	a1,-$a(a5)                      ; destination
	move.w	d6,-$4(a5)                      ; y count
	tst.w	(a3)+                           ; this plane's colour bit
	sne	d2
	and.w	d3,d2                           ; 0 or 2
	move.w	0(a4,d2.w),-$2(a5)              ; HOP and operation
	move.w	d4,(a5)                         ; go
	moveq	#7,d5
blit_span_wait:
	bset	d5,(a5)                         ; restarted until done
	nop
	bne.s	blit_span_wait
	addq.l	#2,a1                           ; the next plane
	dbra	d7,blit_span_plane
	rts

;------------------------------------------------------------------------------
; put_tab: prints a tab (5 spaces).  d1 kept.
;------------------------------------------------------------------------------
put_tab:	; from: menu, print_two_words, floppy_speed_test
	move.w	d1,-(sp)
	move.w	#$9,d1                          ; tab
	bsr.w	put_char
	move.w	(sp)+,d1
	rts

;------------------------------------------------------------------------------
; put_backspace: moves the cursor back one, rubbing out the character there.  Changes d1.
;------------------------------------------------------------------------------
put_backspace:	; from: read_command_line, read_line
	move.w	#$8,d1                          ; backspace
	bsr.w	put_char
	rts

;------------------------------------------------------------------------------
; show_result: ends a test.  In: a5 "Pass" or a failure text.  "Pass" goes on the status line at
; column 66; anything else is printed with the cycle count ($216) in hex and a new line.
;------------------------------------------------------------------------------
show_result:	; from: run_q_tests, ram_test, rom_test, keyboard_test, midi_test, rs232_test, 11 more
	cmpa.l	#msg_pass,a5                    ; "Pass"?
	bne.s	show_result_fail                ; no
	moveq	#66,d0                          ; column 66
	moveq	#0,d1                           ; on the top line
	bra.s	show_status_at
show_result_fail:
	bsr.w	print_string                    ; the failure text
	movea.l	test_cycle.w,a0                 ; the cycle
	bsr.w	print_hex_address               ; in hex
	bsr.w	print_newline
	rts

;------------------------------------------------------------------------------
; show_status_after: prints a5 on the status line after the last status text.  Not called.
;------------------------------------------------------------------------------
show_status_after:
	moveq	#0,d1                           ; the top line
	move.w	status_end_column.w,d0          ; after the last text
	bra.s	show_status_at

;------------------------------------------------------------------------------
; show_status: clears the status line (the top line) and prints a5 at its start.  All registers kept.
;------------------------------------------------------------------------------
show_status:	; from: run_q_tests, ram_test, rom_test, keyboard_test, midi_test, rs232_test, 13 more
	movem.l	d0-d1,-(sp)
	moveq	#0,d0                           ; column 0
	moveq	#0,d1                           ; the top line
	bsr.w	show_status_at
	movem.l	(sp)+,d0-d1
	rts

;------------------------------------------------------------------------------
; show_status_at: clears the top line and prints a5 there at column d0, line d1, the cursor put back
; afterwards; $20C = the column after the text.  All registers kept.
;------------------------------------------------------------------------------
show_status_at:                                 ; from: ram_test, ram_test_vbl, dma_sound_test, floppy_quick_test,
                                                ;   show_result, show_status_after, 1 more
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	a5,-(sp)                        ; the text
	movem.l	d0-d1,-(sp)                     ; the place
	move.w	cursor_column.w,status_saved_column.w ; the cursor kept
	move.w	cursor_row.w,status_saved_row.w
	bsr.w	set_cursor                      ; to the top line's start
	bsr.w	clear_to_line_end               ; cleared to its end
	movem.l	(sp)+,d0-d1
	bsr.w	set_cursor                      ; to the place
	movea.l	(sp)+,a5
	bsr.w	print_string                    ; printed
	move.w	cursor_column.w,status_end_column.w ; the column after it
	move.w	status_saved_column.w,d0        ; the cursor back
	move.w	status_saved_row.w,d1
	bsr.w	set_cursor
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; print_string: prints the 0-ended text at a5 on the screen (and the RS232 terminal).  All
; registers kept.
;------------------------------------------------------------------------------
print_string:	; from: low_ram_test, check_vme_ram, check_fpu, check_bus_error, menu_start, menu, 76 more
	movem.l	d0-d7/a0-a6,-(sp)
print_string_loop:
	move.b	(a5)+,d1                        ; the next character
	cmp.b	#$0,d1                          ; the end?
	beq.s	print_string_end                ; yes
	move.l	a5,-(sp)
	bsr.w	put_char                        ; printed
	movea.l	(sp)+,a5
	bra.s	print_string_loop
print_string_end:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; print_menu_string: prints the 0-ended text at a5; a 5 byte shows the next character in inverse
; (the menu's letters).  All registers kept.
;------------------------------------------------------------------------------
print_menu_string:	; from: menu
	movem.l	d0-d7/a0-a6,-(sp)
print_menu_string_loop:
	move.b	(a5)+,d1                        ; the next character
	cmp.b	#$0,d1                          ; the end?
	beq.s	print_menu_string_end           ; yes
	cmp.b	#$5,d1                          ; 5?
	bne.w	print_menu_string_char          ; no
	bsr.w	inverse_on                      ; the next character in inverse
	bra.s	print_menu_string_loop
print_menu_string_char:
	move.l	a5,-(sp)
	bsr.w	put_char                        ; printed
	movea.l	(sp)+,a5
	bsr.w	inverse_off                     ; back to normal
	bra.s	print_menu_string_loop
print_menu_string_end:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; serial_put_char: sends d1.b out of the MFP's RS232 port, turning the transmitter on first if it was
; off.  Gives up after a time-out when the port never empties.  All registers kept.
;------------------------------------------------------------------------------
serial_put_char:	; from: menu, clear_screen, put_char
	move.w	d0,-(sp)
	btst	#$0,$fffffa2d.w                 ; MFP TSR, the transmitter on?
	bne.s	serial_put_char_timed           ; yes
	move.b	#$1,$fffffa2d.w                 ; MFP TSR, turned on
	bsr.w	delay                           ; a short wait
serial_put_char_timed:
	move.l	#$a53c,d0                       ; the time-out (counted as a word)
serial_put_char_wait:
	subi.w	#$1,d0
	beq.s	serial_put_char_end             ; time-out: not sent
	tst.b	$fffffa2d.w                     ; MFP TSR, the buffer empty?
	bpl.s	serial_put_char_wait            ; not yet
	move.w	#$3e8,d0                        ; a short wait
serial_put_char_delay:
	dbra	d0,serial_put_char_delay
	move.b	d1,$fffffa2f.w                  ; MFP UDR, sent
serial_put_char_end:
	move.w	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; print_hex_long: prints d1.l as 8 hex digits.  Not called.
;------------------------------------------------------------------------------
print_hex_long:
	move.l	d1,-(sp)
	swap	d1                              ; the high word
	bsr.w	print_hex_word
	swap	d1                              ; the low word
	bsr.w	print_hex_word
	move.l	(sp)+,d1
	rts

;------------------------------------------------------------------------------
; print_hex_address: prints a0 as 6 hex digits.  Uses d1.
;------------------------------------------------------------------------------
print_hex_address:	; from: print_cycle, bus_error_handler, memory_utility, print_ram_error, show_result, hd_test
	move.l	a0,d1
	swap	d1                              ; the high byte
	move.l	a0,-(sp)
	bsr.w	print_hex_byte
	move.l	(sp)+,d1                        ; the low word
	bsr.w	print_hex_word
	rts

;------------------------------------------------------------------------------
; print_hex_short: prints d1.w with as few hex digits as it needs (1-4).  Not called.
;------------------------------------------------------------------------------
print_hex_short:
	cmpi.w	#$fff,d1                        ; more than 3 digits?
	bhi.w	print_hex_word                  ; yes: 4
	cmpi.w	#$ff,d1                         ; more than 2?
	bls.w	print_hex_short_byte            ; no
	move.w	d1,-(sp)                        ; 3: the top digit
	lsr.w	#8,d1
	bsr.w	print_hex_digit
	bra.s	print_hex_word_low              ; then the low byte

;------------------------------------------------------------------------------
; print_hex_word: prints d1.w as 4 hex digits; print_hex_byte prints d1.b as 2, print_hex_digit
; prints d1's low 4 bits as one.  d1 kept.
;------------------------------------------------------------------------------
print_hex_word:                                 ; from: memory_utility, print_ram_error, rom_test, print_two_words,
                                                ;   floppy_speed_test, compare_sector_data, 6 more
	move.w	d1,-(sp)
	lsr.w	#8,d1                           ; the high byte
	bsr.w	print_hex_byte
print_hex_word_low:	; from: print_hex_short
	move.w	(sp)+,d1                        ; the low byte
	bsr.w	print_hex_byte
	rts
print_hex_short_byte:	; from: print_hex_short
	cmpi.b	#$f,d1                          ; one digit only?
	bls.w	print_hex_byte_low              ; yes

print_hex_byte:                                 ; from: memory_utility, print_sector_number, print_track_number,
                                                ;   print_floppy_error, print_hex_address, print_hex_word, 2 more
	move.b	d1,-(sp)
	lsr.w	#4,d1                           ; the high digit
	bsr.w	print_hex_digit
	move.b	(sp)+,d1
print_hex_byte_low:	; from: print_hex_word
	bsr.w	print_hex_digit                 ; the low digit
	rts

print_hex_digit:                                ; from: menu, print_tos_version, print_side_number, print_hex_short,
                                                ;   print_hex_byte, print_decimal_teen
	move.l	d1,-(sp)
	andi.b	#$f,d1
	cmp.b	#$9,d1                          ; 0-9?
	bls.s	print_hex_digit_numeral         ; yes
	and.w	#$7,d1                          ; "A"-"F"
	subq.w	#1,d1
	ori.b	#$40,d1
print_hex_digit_put:
	bsr.w	put_char
	move.l	(sp)+,d1
	rts
print_hex_digit_numeral:
	ori.b	#$30,d1                         ; "0"-"9"
	bra.s	print_hex_digit_put

;------------------------------------------------------------------------------
; print_decimal_teen: prints d1.b (0-19) in decimal.
;------------------------------------------------------------------------------
print_decimal_teen:	; from: print_bad_bits
	cmpi.b	#$a,d1                          ; 10 or more?
	blt.w	print_decimal_teen_units        ; no
	move.l	d1,-(sp)
	moveq	#1,d1                           ; "1"
	bsr.s	print_hex_digit
	move.l	(sp)+,d1
	subi.b	#$a,d1                          ; the units
print_decimal_teen_units:
	bsr.s	print_hex_digit
	rts

;------------------------------------------------------------------------------
; print_spaces: prints d1 spaces (d1 at least 1).  d1 ends at 0.
;------------------------------------------------------------------------------
print_spaces:	; from: clear_status_line, print_track_number, put_char
	bsr.w	print_space
	subq.w	#1,d1
	bne.s	print_spaces
	rts

;------------------------------------------------------------------------------
; print_space: prints a space.  All registers kept.
;------------------------------------------------------------------------------
print_space:                                    ; from: memory_utility, print_ram_error, print_bad_bits,
                                                ;   print_tos_version, keyboard_test, floppy_speed_test, 8 more
	move.l	d1,-(sp)
	move.b	#$20,d1
	bsr.w	put_char
	move.l	(sp)+,d1
	rts

;------------------------------------------------------------------------------
; print_newline: prints a carriage return and a line feed.  All registers kept.
;------------------------------------------------------------------------------
print_newline:	; from: check_fpu, menu, run_q_tests, print_cycle, bus_error_handler, exception_error_handler, 26 more
	move.l	d1,-(sp)
	moveq	#13,d1                          ; CR
	bsr.w	put_char
	moveq	#10,d1                          ; LF
	bsr.w	put_char
	move.l	(sp)+,d1
	rts

;------------------------------------------------------------------------------
; clear_screen: clears the screen (no lines kept at the top), sends CR LF to the RS232 terminal
; when it is on, and homes the cursor.  All registers kept.
;------------------------------------------------------------------------------
clear_screen:	; from: low_ram_test, menu, read_command_line, memory_utility, keyboard_test, floppy_menu, 8 more
	movem.l	d0-d7/a0-a6,-(sp)
	clr.w	scroll_top.w                    ; scrolling from the top line
	btst	#$1,mode_flags.w                ; the terminal off?
	bne.s	clear_screen_home               ; yes
	move.b	#$d,d1                          ; CR
	bsr.w	serial_put_char
	move.b	#$a,d1                          ; LF
	bsr.w	serial_put_char
clear_screen_home:
	bsr.w	cursor_home                     ; the cursor home
	bsr.w	clear_to_screen_end             ; cleared to the end
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; init_text_screen: sets the text output up for the resolution: the screen and font values,
; foreground all planes set, background 0, the cursor home, the cursor flags and blink rate, and
; clears 32K of screen.  Uses d0-d1, a0.
;------------------------------------------------------------------------------
init_text_screen:	; from: low_ram_test
	bsr.w	get_screen_mode                 ; the screen
	bsr.w	set_font                        ; the font
	move.w	#$ffff,text_foreground.w        ; foreground
	moveq	#0,d0
	move.w	d0,scroll_top.w                 ; scrolling from the top line
	move.w	d0,text_background.w            ; background
	move.w	d0,cursor_column.w              ; column 0
	move.w	d0,cursor_row.w                 ; line 0
	move.l	screen_base.w,cursor_address.w  ; the cursor's address
	move.b	#$9,cursor_flags.w              ; the cursor flags
	move.b	#$1e,cursor_blink_rate.w        ; blink rate
	move.w	#$1,cursor_hide_count.w         ; blink count
	move.w	#$1fff,d0                       ; 32K
	movea.l	screen_base.w,a0                ; the screen
	moveq	#0,d1
init_text_screen_clear:
	move.l	d1,(a0)+                        ; cleared
	dbra	d0,init_text_screen_clear
	rts

;------------------------------------------------------------------------------
; get_screen_mode: reads the screen address from the video base registers into $29C and sets the
; planes, bytes per line, height and width for the resolution (left alone for resolution 3).
; Uses d0-d1.
;------------------------------------------------------------------------------
get_screen_mode:	; from: init_text_screen
	moveq	#0,d0
	move.b	$ffff8201.w,d0                  ; video base high, the screen
	asl.l	#8,d0
	move.b	$ffff8203.w,d0                  ; video base mid
	asl.l	#8,d0
	move.l	d0,screen_base.w
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	moveq	#3,d1
	and.w	d1,d0
	cmp.w	d1,d0                           ; 3?
	beq.s	get_screen_mode_end             ; yes: unchanged
	move.b	screen_planes_by_res(pc,d0.w),d1 ; planes
	move.w	d1,screen_planes.w
	move.b	screen_line_bytes_by_res(pc,d0.w),d1 ; bytes per line
	move.w	d1,screen_line_bytes.w
	asl.w	#1,d0
	move.w	screen_lines_by_res(pc,d0.w),d1 ; height
	move.w	d1,screen_height.w
	move.w	screen_width_by_res(pc,d0.w),d1 ; width
	move.w	d1,screen_width.w
get_screen_mode_end:
	rts

;------------------------------------------------------------------------------
; screen_planes_by_res and the tables after it: screen geometry by resolution (shift mode
; 0 low, 1 medium, 2 high), read by $6d6a into $2a0-$2a6.
;------------------------------------------------------------------------------
screen_planes_by_res:	; from: get_screen_mode
	dc.b	$04,$02,$01                     ; bit planes -> $2a0
screen_line_bytes_by_res:	; from: get_screen_mode
	dc.b	$a0,$a0,$50                     ; bytes a screen line -> $2a6
screen_lines_by_res:	; from: get_screen_mode
	dc.w	$00c8,$00c8,$0190               ; screen lines -> $2a2
screen_width_by_res:	; from: get_screen_mode
	dc.w	$0140,$0280,$0280               ; pixels a line -> $2a4

;------------------------------------------------------------------------------
; set_font: sets the font for the resolution: the cell height, bytes per text line, the last column
; and line, the font's address (8x8 or 8x16), its form width 128, characters 0-127.  Uses d0-d1.
;------------------------------------------------------------------------------
set_font:	; from: init_text_screen
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	moveq	#3,d1
	and.w	d1,d0
	cmp.w	d1,d0                           ; 3?
	beq.s	set_font_end                    ; yes: unchanged
	asl.w	#1,d0
	move.w	char_height_by_res(pc,d0.w),char_height.w ; the cell height
	move.w	text_row_bytes_by_res(pc,d0.w),text_row_bytes.w ; bytes per text line
	move.w	text_last_column_by_res(pc,d0.w),last_column.w ; the last column
	move.w	text_last_row_by_res(pc,d0.w),last_row.w ; the last line
	move.w	#$80,font_line_step.w           ; font form width
	move.w	#$1,font_char_step.w            ; one byte a character
	move.w	#$0,font_first_char.w           ; the first character
	move.w	#$7f,font_last_char.w           ; the last character
	asl.w	#1,d0
	move.l	font_by_res(pc,d0.w),font_address.w ; the font
set_font_end:
	rts

;------------------------------------------------------------------------------
; text_last_row_by_res and the tables after it: text screen layout by resolution (shift mode
; 0 low, 1 medium, 2 high), read by $6dbe into $2a8-$2b0.
;------------------------------------------------------------------------------
text_last_row_by_res:	; from: set_font
	dc.w	$0018,$0018,$0018               ; last text row (25 rows) -> $2ae
char_height_by_res:	; from: set_font
	dc.w	$0008,$0008,$0010               ; character height in lines -> $2a8
text_row_bytes_by_res:	; from: set_font
	dc.w	$0500,$0500,$0500               ; bytes a text row (height x line bytes) -> $2aa
text_last_column_by_res:	; from: set_font
	dc.w	$0027,$004f,$004f               ; last text column -> $2ac
font_by_res:	; from: set_font
	dc.l	font_8x8                        ; 8x8 font for low resolution -> $2b0
	dc.l	font_8x8                        ; 8x8 font for medium resolution
	dc.l	font_8x16                       ; 8x16 font for high resolution

;------------------------------------------------------------------------------
; put_char: the character in d1 out to the RS232 terminal (unless $28F bit 1 is set) and onto the screen
; at the cursor.  Control codes: 8 backspace (back, a space, back), 9 tab (5 spaces), 10 line feed,
; 13 carriage return.  Codes from the font's first ($2B8) to its last ($2BA) are drawn in the colours
; ($2BC foreground, $2BE background, swapped while inverse, $2C8 bit 4), the cursor moves on, to the next
; line at the last column when wrap ($2C8 bit 3) is on, and the screen scrolls from the line in $29A at the
; bottom.  All registers are kept.
;------------------------------------------------------------------------------
put_char:                                       ; from: read_command_line, read_line, print_tos_version,
                                                ;   draw_mouse_right_button, draw_mouse_left_button,
                                                ;   printer_joystick_test, 12 more
	movem.l	d0-d7/a0-a6,-(sp)               ; all kept
	andi.w	#$ff,d1                         ; the character only
	btst	#$1,mode_flags.w                ; the terminal off?
	bne.s	put_char_screen                 ; yes: the screen only
	cmp.b	#$9,d1                          ; a tab?
	bne.w	put_char_to_serial              ; no: sent as it is
	moveq	#5,d1                           ; 5 spaces,
	bsr.w	print_spaces                    ; each to the terminal and the screen
	bra.w	put_char_done                   ; done
put_char_to_serial:
	bsr.w	serial_put_char                 ; to the RS232 terminal
put_char_screen:
	cmp.b	#$a,d1                          ; line feed?
	bne.s	put_char_cr
	bsr.w	line_feed                       ; the next line
	bra.w	put_char_done
put_char_cr:
	cmp.b	#$d,d1                          ; carriage return?
	bne.s	put_char_backspace
	bsr.w	carriage_return                 ; column 0
	bra.w	put_char_done
put_char_backspace:
	cmp.b	#$8,d1                          ; backspace?
	bne.s	put_char_tab
	bsr.w	cursor_back                     ; back one
	move.w	#$20,d1                         ; a space over the character
	bsr.s	put_char                        ; drawn
	bsr.w	cursor_back                     ; back again
	bra.w	put_char_done
put_char_tab:
	cmp.b	#$9,d1                          ; tab (the terminal off)?
	bne.s	put_char_glyph
	moveq	#5,d1                           ; 5 spaces
	bsr.w	print_spaces
	bra.w	put_char_done
put_char_glyph:
	move.w	font_first_char.w,d3            ; the font's first character
	cmp.w	d3,d1                           ; below it?
	bcs.w	put_char_done                   ; yes: not shown
	cmp.w	font_last_char.w,d1             ; past the last?
	bhi.w	put_char_done                   ; yes: not shown
	sub.w	d3,d1                           ; the index in the font
	move.w	font_char_step.w,d3             ; bytes per character in the font
	mulu.w	d1,d3                           ; times the index
	movea.l	font_address.w,a0               ; the font
	adda.l	d3,a0                           ; a0: the glyph
	movea.l	cursor_address.w,a1             ; a1: the cursor's place on the screen
	move.w	text_background.w,d7            ; the background colour
	swap	d7                              ; in the high word
	move.w	text_foreground.w,d7            ; the foreground in the low word
	btst	#$4,cursor_flags.w              ; inverse?
	beq.s	put_char_draw                   ; no
	swap	d7                              ; yes: the colours swapped
put_char_draw:
	bclr	#$2,cursor_flags.w              ; the cursor off the screen (it is drawn over); Z clear if it was on
	move.w	sr,-(sp)                        ; kept
	bsr.w	draw_glyph                      ; the glyph drawn
	movea.l	cursor_address.w,a1             ; the cursor's place
	move.w	cursor_column.w,d0              ; its column
	move.w	cursor_row.w,d1                 ; its row
	bsr.w	next_column                     ; on one column
	beq.s	put_char_store                  ; no new line needed: stored
	move.w	text_row_bytes.w,d0             ; bytes per text row
	mulu.w	d1,d0                           ; times the row
	movea.l	screen_base.w,a1                ; the screen
	adda.l	d0,a1                           ; the start of this row, column 0
	clr.w	d0
	cmp.w	last_row.w,d1                   ; the last row?
	bcc.w	put_char_scroll                 ; yes: scroll
	adda.w	text_row_bytes.w,a1             ; no: the next row
	addq.w	#1,d1                           ; row + 1
	bra.s	put_char_store
put_char_scroll:
	movem.l	d0-d1/a1,-(sp)
	move.w	scroll_top.w,d1                 ; the scroll region's first row
	bsr.w	scroll_up                       ; up one row, the last row cleared
	movem.l	(sp)+,d0-d1/a1
put_char_store:
	move.l	a1,cursor_address.w             ; the cursor's new place
	move.w	d0,cursor_column.w              ; column
	move.w	d1,cursor_row.w                 ; row
	move.w	(sp)+,ccr                       ; was the cursor on?
	beq.s	put_char_done                   ; no
	bsr.w	invert_cell                     ; the cursor drawn at the new place
	bset	#$1,cursor_flags.w              ; and marked drawn
put_char_done:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; cursor_back: the cursor back one place; from column 0 to the row above, at the column in the byte at
; $2AC, which is the high byte of the last-column word (0): column 0 of that row, not its end.
; Changes d0, d1, a0, a1.
;------------------------------------------------------------------------------
cursor_back:	; from: put_char
	move.w	cursor_column.w,d0              ; the column
	move.w	cursor_row.w,d1                 ; the row
	tst.w	d0                              ; column 0?
	beq.s	cursor_back_up_line             ; yes: the row above
	subq.w	#1,d0                           ; one column back
	bra.s	cursor_back_set
cursor_back_up_line:
	subq.w	#1,d1                           ; the row above
	move.b	last_column.w,d0                ; the high byte of the last column: 0
cursor_back_set:
	bsr.w	set_cursor                      ; the cursor there
	rts

;------------------------------------------------------------------------------
; draw_glyph: one character drawn from the font in every plane.  a0 the glyph, a1 the screen place, d7 the
; background colour (high word) and foreground (low word): plane by plane a background bit and a
; foreground bit pick a byte of 0, $FF, the glyph or the glyph inverted for each line of the character.
; Changes d3-d7, a1-a5.
;------------------------------------------------------------------------------
draw_glyph:	; from: put_char
	movea.w	font_line_step.w,a2             ; the font's line step
	movea.w	screen_line_bytes.w,a3          ; the screen's line step
	move.w	char_height.w,d4                ; lines per character
	move.w	screen_planes.w,d6              ; planes
	bra.s	draw_glyph_next_plane           ; the first plane
draw_glyph_plane:
	move.w	d4,d5                           ; the lines
	movea.l	a0,a4                           ; the glyph
	movea.l	a1,a5                           ; the screen
	asr.l	#1,d7                           ; the next plane's colour bits: foreground into X/C, background into bit
                                                ;   15
	btst	#$f,d7                          ; the background bit
	beq.s	draw_glyph_bg_clear             ; clear
	bcc.w	draw_glyph_invert_next          ; set, foreground clear: the glyph inverted
	moveq	#-1,d3                          ; both set: $FF
	bra.s	draw_glyph_fill_next
draw_glyph_bg_clear:
	bcs.w	draw_glyph_copy_next            ; the foreground set: the glyph
	moveq	#0,d3                           ; both clear: 0
	bra.s	draw_glyph_fill_next
draw_glyph_fill_line:
	move.b	d3,(a5)                         ; the fill byte
	adda.w	a3,a5                           ; the next line
draw_glyph_fill_next:
	dbra	d5,draw_glyph_fill_line         ; every line
	bra.s	draw_glyph_plane_done           ; the plane done
draw_glyph_copy_line:
	move.b	(a4),(a5)                       ; the glyph's line
	adda.w	a3,a5                           ; the next screen line
	adda.w	a2,a4                           ; the next font line
draw_glyph_copy_next:
	dbra	d5,draw_glyph_copy_line
	bra.s	draw_glyph_plane_done
draw_glyph_invert_line:
	move.b	(a4),d3                         ; the glyph's line
	not.b	d3                              ; inverted
	move.b	d3,(a5)
	adda.w	a3,a5                           ; the next screen line
	adda.w	a2,a4                           ; the next font line
draw_glyph_invert_next:
	dbra	d5,draw_glyph_invert_line
draw_glyph_plane_done:
	lea	2(a1),a1                        ; the next plane's word
draw_glyph_next_plane:
	dbra	d6,draw_glyph_plane             ; every plane
	rts

;------------------------------------------------------------------------------
; clear_text_block: a block of character cells filled with the background colour ($2BE).  d1 the top row
; (high word) and left column (low), d2 the bottom row and right column; the left column is taken down to
; a word (an even column) and the width in column pairs.  Changes d0-d5, a1, a2.
;------------------------------------------------------------------------------
clear_text_block:	; from: scroll_up, clear_to_screen_end, clear_to_line_end
	sub.l	d1,d2                           ; rows and columns across
	move.w	d1,d0                           ; the left column
	swap	d1                              ; the top row
	bsr.w	cell_address                    ; a1: the block's first cell
	asr.w	#1,d2                           ; the width in column pairs (16 pixels)
	move.w	screen_planes.w,d3              ; planes
	cmpi.w	#$4,d3                          ; 4 (low resolution)?
	bne.s	clear_text_block_size           ; no
	subq.w	#1,d3                           ; 3: 8 bytes a pair
clear_text_block_size:
	move.w	d2,d1                           ; the pairs
	addq.w	#1,d1                           ; + 1
	asl.w	d3,d1                           ; in bytes
	movea.w	screen_line_bytes.w,a2          ; the screen's line
	suba.w	d1,a2                           ; less the block: the step to the next line
	move.w	d2,d1                           ; the pairs - 1 (the dbra count)
	swap	d2                              ; the rows
	addq.w	#1,d2                           ; + 1
	mulu.w	char_height.w,d2                ; in lines
	subq.w	#1,d2                           ; - 1 (the dbra count)
	clr.l	d0                              ; the plane words
	move.w	text_background.w,d5            ; the background colour
	cmpi.w	#$2,screen_planes.w             ; planes: 1 (high)?
	bmi.w	clear_text_block_high           ; yes
	beq.s	clear_text_block_medium         ; 2: medium
	asr.w	#1,d5                           ; plane 0's bit
	negx.w	d0                              ; as $0000 or $FFFF
	swap	d0                              ; into the high word
	asr.w	#1,d5                           ; plane 1's bit
	negx.w	d0                              ; as $0000 or $FFFF
	clr.l	d3                              ; the next two planes
	asr.w	#1,d5                           ; plane 2's bit
	negx.w	d3                              ; as $0000 or $FFFF
	swap	d3                              ; into the high word
	asr.w	#1,d5                           ; plane 3's bit
	negx.w	d3                              ; as $0000 or $FFFF
clear_text_block_low_line:
	move.w	d1,d5                           ; the pairs
clear_text_block_low_word:
	move.l	d0,(a1)+                        ; planes 0 and 1
	move.l	d3,(a1)+                        ; planes 2 and 3
	dbra	d5,clear_text_block_low_word    ; across
	adda.l	a2,a1                           ; the next line
	dbra	d2,clear_text_block_low_line    ; every line
	rts
clear_text_block_medium:
	asr.w	#1,d5                           ; plane 0's bit
	negx.w	d0                              ; as $0000 or $FFFF
	swap	d0                              ; into the high word
	asr.w	#1,d5                           ; plane 1's bit
	negx.w	d0                              ; as $0000 or $FFFF
clear_text_block_medium_line:
	move.w	d1,d5                           ; the pairs
clear_text_block_medium_word:
	move.l	d0,(a1)+                        ; both planes
	dbra	d5,clear_text_block_medium_word ; across
	adda.l	a2,a1                           ; the next line
	dbra	d2,clear_text_block_medium_line ; every line
	rts
clear_text_block_high:
	asr.w	#1,d5                           ; the one plane's bit
	negx.w	d0                              ; as $0000 or $FFFF
clear_text_block_high_line:
	move.w	d1,d5                           ; the pairs
clear_text_block_high_word:
	move.w	d0,(a1)+                        ; the word
	dbra	d5,clear_text_block_high_word   ; across
	adda.l	a2,a1                           ; the next line
	dbra	d2,clear_text_block_high_line   ; every line
	rts

;------------------------------------------------------------------------------
; cell_address: a1 = the screen address of column d0, row d1 (each kept to the last column and row).
; Changes d0, d1, d3, d5.
;------------------------------------------------------------------------------
cell_address:	; from: clear_text_block, cursor_draw, set_cursor
	move.w	last_column.w,d3                ; the last column
	cmp.w	d0,d3                           ; d0 past it?
	bpl.w	cell_address_row                ; no
	move.w	d3,d0                           ; yes: the last
cell_address_row:
	move.w	last_row.w,d3                   ; the last row
	cmp.w	d1,d3                           ; d1 past it?
	bpl.w	cell_address_calc               ; no
	move.w	d3,d1                           ; yes: the last
cell_address_calc:
	move.w	screen_planes.w,d3              ; planes
	move.w	d0,d5                           ; the column
	bclr	#$0,d5                          ; its column pair
	mulu.w	d5,d3                           ; times the planes: the pair's word group in bytes
	btst	#$0,d0                          ; an odd column?
	beq.s	cell_address_add                ; no
	addq.l	#1,d3                           ; yes: the right-hand byte
cell_address_add:
	move.w	text_row_bytes.w,d5             ; bytes per text row
	mulu.w	d1,d5                           ; times the row
	movea.l	screen_base.w,a1                ; the screen
	adda.l	d5,a1                           ; the row
	adda.l	d3,a1                           ; the column
	rts

;------------------------------------------------------------------------------
; invert_cell: the character cell at a1 inverted in every plane (draws or takes off the cursor).
; Changes d4-d6, a1, a2, a4.
;------------------------------------------------------------------------------
invert_cell:	; from: put_char, cursor_draw, set_cursor
	movea.w	screen_line_bytes.w,a2          ; the screen's line step
	move.w	char_height.w,d4                ; lines per character
	move.w	screen_planes.w,d6              ; planes
	bra.w	invert_cell_next_plane          ; the first plane
invert_cell_plane:
	move.w	d4,d5                           ; the lines
	movea.l	a1,a4                           ; this plane
	bra.w	invert_cell_next_line           ; the first line
invert_cell_line:
	not.b	(a4)                            ; inverted
	adda.w	a2,a4                           ; the next line
invert_cell_next_line:
	dbra	d5,invert_cell_line
	lea	2(a1),a1                        ; the next plane's word
invert_cell_next_plane:
	dbra	d6,invert_cell_plane
	rts

;------------------------------------------------------------------------------
; next_column: column d0 and the screen place a1 moved on one character.  At the last column nothing
; moves: d3 = 1 (Z clear, a new line needed) when wrap ($2C8 bit 3) is on, else 0.  Otherwise d3 = 0, Z set.
;------------------------------------------------------------------------------
next_column:	; from: put_char
	cmp.w	last_column.w,d0                ; the last column?
	bne.s	next_column_advance             ; no
	btst	#$3,cursor_flags.w              ; wrap on?
	bne.s	next_column_wrap                ; yes
	clr.w	d3                              ; no: stays at the last column
	rts
next_column_wrap:
	move.b	#$1,d3                          ; a new line
	rts
next_column_advance:
	addq.w	#1,d0                           ; the next column
	btst	#$0,d0                          ; odd: the same word group
	beq.s	next_column_word                ; no
	lea	1(a1),a1                        ; the right-hand byte
	clr.w	d3                              ; no new line
	rts
next_column_word:
	move.w	screen_planes.w,d3              ; planes
	asl.w	#1,d3                           ; * 2
	subq.w	#1,d3                           ; - 1
	adda.w	d3,a1                           ; the next word group's left-hand byte
	clr.w	d3                              ; no new line
	rts

;------------------------------------------------------------------------------
; scroll_up: the rows from d1 to the last moved up one, the last row cleared.  Changes d1-d5, a1-a3.
;------------------------------------------------------------------------------
scroll_up:	; from: put_char, line_feed
	movea.l	screen_base.w,a3                ; the screen
	move.w	text_row_bytes.w,d3             ; bytes per text row
	mulu.w	d1,d3                           ; times the first row
	lea	0(a3,d3.w),a3                   ; a3: row d1
	neg.w	d1                              ; the rows
	add.w	last_row.w,d1                   ; from it to the last
	move.w	text_row_bytes.w,d3             ; bytes per text row
	lea	0(a3,d3.w),a2                   ; a2: the row below
	mulu.w	d1,d3                           ; bytes to move
	asr.w	#2,d3                           ; in longs
	bra.w	scroll_up_next                  ; the first
scroll_up_copy:
	move.l	(a2)+,(a3)+                     ; up one row
scroll_up_next:
	dbra	d3,scroll_up_copy
	move.w	last_row.w,d1                   ; the last row
scroll_clear_last_row:	; from: scroll_down
	move.w	d1,d2                           ; the bottom row the same
	swap	d1                              ; the top row in the high word
	swap	d2                              ; the bottom row in the high word
	clr.w	d1                              ; from column 0
	move.w	last_column.w,d2                ; to the last column
	bra.w	clear_text_block                ; cleared

;------------------------------------------------------------------------------
; scroll_down: (not reached) the rows from d1 to the last moved down one; it then clears the last row
; (scroll_clear_last_row), not row d1.
;------------------------------------------------------------------------------
scroll_down:
	movea.l	screen_base.w,a3                ; the screen
	move.w	last_row.w,d3                   ; the last row
	mulu.w	text_row_bytes.w,d3             ; in bytes
	lea	0(a3,d3.w),a3                   ; a3: the last row's start
	move.w	text_row_bytes.w,d3             ; bytes per text row
	lea	0(a3,d3.w),a2                   ; a2: its end
	move.w	d1,d0                           ; the first row
	neg.w	d0                              ; from it
	add.w	last_row.w,d0                   ; to the last
	mulu.w	d0,d3                           ; bytes to move
	asr.w	#2,d3                           ; in longs
	bra.w	scroll_down_next                ; the first
scroll_down_copy:
	move.l	-(a3),-(a2)                     ; down one row, from the end
scroll_down_next:
	dbra	d3,scroll_down_copy
	bra.s	scroll_clear_last_row           ; the last row cleared
cursor_at_bottom:	; from: clear_to_screen_end, line_feed
	rts                                     ; the cursor at the last row: nothing

;------------------------------------------------------------------------------
; cursor_home: the cursor to column 0, row 0.  Changes d0, d1, a0, a1.
;------------------------------------------------------------------------------
cursor_home:	; from: clear_status_line, floppy_quick_test, clear_screen, restore_cursor
	moveq	#0,d0                           ; column 0
	move.w	d0,d1                           ; row 0
	bra.w	set_cursor                      ; the cursor there

;------------------------------------------------------------------------------
; clear_to_screen_end: from the cursor to the end of its row, then every row below it, cleared.
; The cursor stays.  Changes d0-d5, a0-a2.
;------------------------------------------------------------------------------
clear_to_screen_end:	; from: clear_screen
	bsr.w	clear_to_line_end               ; the rest of this row
	move.w	cursor_row.w,d1                 ; the cursor's row
	cmp.w	last_row.w,d1                   ; the last?
	beq.s	cursor_at_bottom                ; yes: done
	addq.w	#1,d1                           ; the row below
	swap	d1                              ; in the high word
	move.w	#$0,d1                          ; from column 0
	move.w	last_row.w,d2                   ; to the last row
	swap	d2                              ; in the high word
	move.w	last_column.w,d2                ; and the last column
	bra.w	clear_text_block                ; cleared

;------------------------------------------------------------------------------
; clear_to_line_end: from the cursor to the end of its row cleared (from an odd column a space is printed
; first, as the block clears whole word groups).  Wrap is kept off meanwhile; the cursor stays.
; Changes d0-d5, a0-a2.
;------------------------------------------------------------------------------
clear_to_line_end:	; from: ask_stopped, show_status_at, clear_to_screen_end, hd_stopped_menu
	bclr	#$3,cursor_flags.w              ; wrap off; Z clear if it was on
	move.w	sr,-(sp)                        ; kept
	bsr.w	cursor_hide                     ; the cursor off
	bsr.w	save_cursor                     ; its place kept
	move.w	cursor_column.w,d1              ; the column
	btst	#$0,d1                          ; odd?
	beq.s	clear_to_line_end_fill          ; no: cleared from here
	cmp.w	last_column.w,d1                ; the last column?
	beq.s	clear_to_line_end_last          ; yes: a space is all
	move.w	#$20,d1                         ; a space for the odd column
	bsr.w	put_char                        ; printed
	move.w	cursor_column.w,d1              ; now an even column
clear_to_line_end_fill:
	swap	d1                              ; the column in the high word
	move.w	cursor_row.w,d1                 ; the row
	move.w	d1,d2                           ; the same row
	swap	d1                              ; the row in the high word, the column in the low
	swap	d2                              ; the row in the high word
	move.w	last_column.w,d2                ; to the last column
	bsr.w	clear_text_block                ; cleared
clear_to_line_end_restore:
	move.w	(sp)+,ccr                       ; was wrap on?
	beq.s	clear_to_line_end_show          ; no
	bset	#$3,cursor_flags.w              ; on again
clear_to_line_end_show:
	bsr.w	restore_cursor                  ; the cursor back to its place
	bra.w	cursor_show                     ; the cursor on
clear_to_line_end_last:
	move.w	#$20,d1                         ; a space at the last column
	bsr.w	put_char                        ; printed
	bra.s	clear_to_line_end_restore

;------------------------------------------------------------------------------
; inverse_on: text from now on in inverse video ($2C8 bit 4).
;------------------------------------------------------------------------------
inverse_on:	; from: ram_test_vbl, rom_test, print_menu_string
	bset	#$4,cursor_flags.w
	rts

;------------------------------------------------------------------------------
; inverse_off: text from now on normal ($2C8 bit 4 cleared).
;------------------------------------------------------------------------------
inverse_off:	; from: ram_test_vbl, rom_test, print_menu_string
	bclr	#$4,cursor_flags.w
	rts

;------------------------------------------------------------------------------
; cursor_show: one cursor_hide undone ($2CA counts them); at 0 the cursor is drawn.  In blink mode
; ($2C8 bit 0) it is drawn and marked in bit 1, otherwise marked on in bit 2.  Changes d0-d6, a0-a4.
;------------------------------------------------------------------------------
cursor_show:	; from: clear_to_line_end, line_feed
	subq.w	#1,cursor_hide_count.w          ; one hide undone
	bne.s	cursor_hide_done                ; still hidden
	lea	cursor_flags.w,a0               ; the cursor flags
	btst	#$0,(a0)                        ; blink mode?
	bne.s	cursor_show_blink               ; yes
	bset	#$2,(a0)                        ; on

;------------------------------------------------------------------------------
; cursor_draw: the cell at the cursor ($2C0 column, $2C2 row) inverted: the cursor drawn or taken off.
; Changes d0, d1, d3-d6, a1, a2, a4.
;------------------------------------------------------------------------------
cursor_draw:	; from: cursor_hide
	move.w	cursor_column.w,d0              ; the column
	move.w	cursor_row.w,d1                 ; the row
	bsr.w	cell_address                    ; its screen place
	bra.w	invert_cell                     ; inverted
cursor_show_blink:	; from: cursor_show
	bsr.s	cursor_draw                     ; drawn
	bset	#$1,(a0)                        ; and marked drawn
cursor_hide_done:	; from: cursor_show, cursor_hide
	rts

;------------------------------------------------------------------------------
; cursor_hide: the cursor taken off the screen, and one more hide counted in $2CA (cursor_show undoes it).
; Changes d0, d1, d3-d6, a0-a2, a4.
;------------------------------------------------------------------------------
cursor_hide:	; from: clear_to_line_end, line_feed
	addq.w	#1,cursor_hide_count.w          ; one more hide
	lea	cursor_flags.w,a0               ; the cursor flags
	bclr	#$2,(a0)                        ; off; was it on?
	beq.s	cursor_hide_done                ; no: done
	btst	#$0,(a0)                        ; blink mode?
	beq.s	cursor_draw                     ; no: taken off
	bclr	#$1,(a0)                        ; drawn just now?
	bne.s	cursor_draw                     ; yes: taken off
	rts

;------------------------------------------------------------------------------
; save_cursor: the cursor's column and row kept in $2CC/$2CE for restore_cursor ($2C8 bit 5 marks them).
; Changes a0.
;------------------------------------------------------------------------------
save_cursor:                                    ; from: clear_status_line, print_cycle, print_channel_name,
                                                ;   floppy_quick_test, show_floppy_status, clear_to_line_end, 1 more
	bset	#$5,cursor_flags.w              ; a place kept
	lea	saved_cursor_column.w,a0        ; the place
	move.w	cursor_column.w,(a0)+           ; the column
	move.w	cursor_row.w,(a0)               ; the row
	rts

;------------------------------------------------------------------------------
; restore_cursor: the cursor back to the place save_cursor kept, or home if none.  Changes d0, d1, a0, a1.
;------------------------------------------------------------------------------
restore_cursor:                                 ; from: clear_status_line, print_cycle, print_channel_name,
                                                ;   floppy_quick_test, show_floppy_status, clear_to_line_end, 1 more
	bclr	#$5,cursor_flags.w              ; a place kept?
	beq.w	cursor_home                     ; no: home
	lea	saved_cursor_column.w,a0        ; the place
	move.w	(a0)+,d0                        ; the column
	move.w	(a0),d1                         ; the row
	bra.w	set_cursor                      ; the cursor there

;------------------------------------------------------------------------------
; wrap_on: (not called) wrap to the next line at the last column ($2C8 bit 3).
;------------------------------------------------------------------------------
wrap_on:
	bset	#$3,cursor_flags.w
	rts

;------------------------------------------------------------------------------
; wrap_off: (not called) no wrap: the last column is written over.
;------------------------------------------------------------------------------
wrap_off:
	bclr	#$3,cursor_flags.w
	rts

;------------------------------------------------------------------------------
; set_cursor: the cursor to column d0, row d1 ($2C0, $2C2, and its screen place $2C4); if it is drawn it
; is taken off at the old place and drawn at the new.  Changes d3, d5, a0-a2, a4.
;------------------------------------------------------------------------------
set_cursor:                                     ; from: ask_stopped, print_cycle, read_command_line, keyboard_test,
                                                ;   draw_mouse_right_button, draw_mouse_left_button, 18 more
	move.w	d0,cursor_column.w              ; the column
	move.w	d1,cursor_row.w                 ; the row
	lea	cursor_flags.w,a0               ; the cursor flags
	btst	#$2,(a0)                        ; on?
	beq.s	set_cursor_address              ; no: only the place
	btst	#$0,(a0)                        ; blink mode?
	beq.s	set_cursor_move_drawn           ; no: moved drawn
	bclr	#$2,(a0)                        ; not on for now
	btst	#$1,(a0)                        ; drawn?
	beq.s	set_cursor_mark_on              ; no: only the place
set_cursor_move_drawn:
	movea.l	cursor_address.w,a1             ; the old place
	bsr.w	invert_cell                     ; taken off
	bsr.w	cell_address                    ; the new place
	move.l	a1,cursor_address.w             ; kept
	bsr.w	invert_cell                     ; drawn there
	bset	#$2,cursor_flags.w              ; on
	rts
set_cursor_mark_on:
	bset	#$2,(a0)                        ; on again
set_cursor_address:
	bsr.w	cell_address                    ; the new place
	move.l	a1,cursor_address.w             ; kept
	rts

;------------------------------------------------------------------------------
; carriage_return: the cursor to column 0 of its row.
;------------------------------------------------------------------------------
carriage_return:	; from: put_char
	move.w	cursor_row.w,d1                 ; the row
	clr.w	d0                              ; column 0
	bra.s	set_cursor                      ; the cursor there

;------------------------------------------------------------------------------
; line_feed: the cursor down a row in its column; on the last row the screen scrolls up from the row in
; $29A instead.
;------------------------------------------------------------------------------
line_feed:	; from: put_char
	move.w	cursor_row.w,d0                 ; the row
	cmp.w	last_row.w,d0                   ; the last?
	bne.s	line_feed_down                  ; no: down one
	bsr.w	cursor_hide                     ; the cursor off
	move.w	scroll_top.w,d1                 ; the scroll region's first row
	bsr.w	scroll_up                       ; up one row
	bra.w	cursor_show                     ; the cursor on
line_feed_down:
	move.w	cursor_row.w,d1                 ; the row
	cmp.w	last_row.w,d1                   ; the last?
	beq.w	cursor_at_bottom                ; yes: nothing
	addq.w	#1,d1                           ; the row below
	move.w	cursor_column.w,d0              ; the same column
	bra.w	set_cursor                      ; the cursor there

;------------------------------------------------------------------------------
; hd_test: J, the "Hard Disk DMA Exerciser" on ACSI unit 0.  S starts it: 68 sectors from sector $9F1C
; ("cylinder 600") are read and kept at $51020, then each cycle writes a pattern from $48810, reads it
; back to $40008 and compares; read errors, compare errors and data DMAed past the guard longs
; ($18020000 at $40000, $48808 and $51010) are reported, the screen going red.  The kept data is
; written back when the test is stopped.  P parks the heads (a STOP UNIT command), Q quits.
; Uses $B90-$C6E (the variables), $216 (the cycle count, as a word).
;------------------------------------------------------------------------------
hd_test:	; from: read_command_line
	lea	hd_exerciser_title,a5           ; "Hard Disk DMA Exerciser", the warning, "Hit <Esc> key to stop
                                                ;   program."
	bsr.w	print_string                    ; printed
	move.l	#$bee,hd_bad_sectors_end.w      ; the known bad sector list emptied
	lea	msg_hd_commands,a5              ; "Q=quit, P=Park heads, S=start"
	bsr.w	print_string                    ; printed
hd_test_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$51,d0                         ; Q?
	beq.w	hd_test_quit                    ; yes: quit
	cmp.b	#$50,d0                         ; P?
	beq.w	hd_park_heads                   ; yes: park the heads
	cmp.b	#$53,d0                         ; S?
	bne.s	hd_test_key                     ; no: again
	bsr.w	clear_screen                    ; the screen cleared
	bsr.w	print_newline                   ; a new line
hd_test_clear_irq:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, the FDC/ACSI interrupt line (GPIP 5) high?
	bne.w	hd_test_start                   ; yes: free
	bsr.w	floppy_force_interrupt          ; no: an FDC Force Interrupt
	bra.s	hd_test_clear_irq               ; until it is
hd_test_start:
	clr.w	test_cycle.w                    ; the cycle count
	clr.w	hd_counter_a.w                  ; counters (not used further here)
	clr.w	hd_counter_b.w
	clr.w	hd_counter_c.w
	clr.w	hd_counter_d.w
	move.l	#$18020000,$40000               ; a guard long before the read buffer
	move.l	#$18020000,$48808               ; between the read and write buffers
	move.l	#$18020000,$51010               ; after the write buffer
	move.w	#$258,hd_cylinder.w             ; "cylinder 600" in the status line
	move.l	#$9f1c,hd_first_sector.w        ; the first sector
	move.w	#$44,hd_sectors_left.w          ; 68 sectors
	move.l	hd_first_sector.w,hd_sector.w   ; from the first
	move.w	#$0,acsi_unit.w                 ; unit 0
	move.l	#$51020,acsi_dma_address.w      ; to the keep buffer
	move.w	hd_sectors_left.w,acsi_count.w  ; the count for the command
	move.l	hd_sector.w,acsi_sector.w       ; the sector for the command
	bsr.w	acsi_read_sectors               ; the disk's data read and kept
	tst.w	d0                              ; an error?
	beq.s	hd_test_cycle                   ; no
	bsr.w	get_key                         ; yes: a key
	bra.w	hd_test                         ; and again from the start
hd_test_cycle:
	addi.w	#$1,test_cycle.w                ; the next cycle
	move.w	#$258,hd_cylinder.w             ; "cylinder 600"
	move.l	#$9f1c,hd_first_sector.w        ; the first sector
	lea	msg_writing_cylinder,a5         ; "Writing cylinder   "
	bsr.w	hd_status_line                  ; in the status line with the cycle
	bsr.w	hd_fill_write_buffer            ; the write buffer filled with this cycle's pattern
	move.w	#$44,hd_sectors_left.w          ; 68 sectors
	move.l	hd_first_sector.w,hd_sector.w   ; from the first
	move.w	#$0,acsi_unit.w                 ; unit 0
	move.l	#$48810,acsi_dma_address.w      ; from the write buffer
	move.w	hd_sectors_left.w,acsi_count.w  ; the count for the command
	move.l	hd_sector.w,acsi_sector.w       ; the sector for the command
	bsr.w	acsi_write_sectors              ; written
	tst.w	d0                              ; timed out?
	bpl.w	hd_test_read_phase              ; no
	bsr.w	hd_pause                        ; yes: half a second
hd_test_read_phase:
	movea.l	#$40008,a0                      ; the read buffer
	move.l	#$87ff,d1                       ; $8800 bytes (68 sectors)
	moveq	#0,d0                           ; cleared
hd_test_clear_byte:
	move.b	d0,(a0)+
	dbra	d1,hd_test_clear_byte
	lea	msg_reading_cylinder,a5         ; "Reading cylinder   "
	bsr.w	hd_status_line                  ; in the status line with the cycle
	move.w	#$44,hd_sectors_left.w          ; 68 sectors
	move.l	hd_first_sector.w,hd_sector.w   ; from the first
	move.w	#$0,acsi_unit.w                 ; unit 0
	move.l	#$40008,acsi_dma_address.w      ; to the read buffer
hd_test_read:
	move.w	hd_sectors_left.w,acsi_count.w  ; the sectors left for the command
	move.l	hd_sector.w,acsi_sector.w       ; the sector for the command
	bsr.w	acsi_read_sectors               ; read
	tst.w	d0                              ; timed out?
	bpl.w	hd_test_read_done               ; no: check the DMA address
	bsr.w	hd_pause                        ; yes: half a second
	bsr.w	hd_get_dma_address              ; the DMA address reached
hd_test_read_error:
	move.l	dma_address_read.w,d0           ; the DMA address reached
	sub.l	#$40008,d0                      ; less the buffer: the bytes read
	tst.l	d0                              ; none?
	beq.w	hd_test_skip_sector             ; yes
	divs.w	#$200,d0                        ; in sectors
	andi.l	#$ffff,d0                       ; the quotient only
	add.l	d0,hd_sector.w                  ; the sectors read skipped
hd_test_skip_sector:
	addi.l	#$1,hd_sector.w                 ; and the failed one too
	move.w	hd_sectors_left.w,d1            ; the sectors left
	sub.l	d0,d1                           ; less those read
	move.w	d1,hd_sectors_left.w            ; stored
	subi.w	#$1,hd_sectors_left.w           ; less the failed one (the rest are read to the buffer's start again)
	bsr.w	hd_known_bad_sector             ; the failed sector in the known bad list?
	beq.s	hd_test_read                    ; yes: the rest read
	lea	msg_read_error_on_sector,a5     ; "Read error on sector  "
	bsr.w	print_string                    ; printed
	move.l	hd_sector.w,d0                  ; the sector
	subq.w	#1,d0                           ; the failed one
	bsr.w	word_to_bcd                     ; in decimal digits
	movea.l	d1,a0                           ; to print
	bsr.w	print_hex_address               ; printed
	bsr.w	print_space                     ; a space
	bsr.w	hd_print_cycle                  ; " Cycle: " and the cycle
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
hd_test_read_done:
	bsr.w	hd_get_dma_address              ; the DMA address reached
	move.l	#$40008,d0                      ; the read buffer
	clr.l	d1                              ; the sectors read
	move.w	hd_sectors_left.w,d1
	mulu.w	#$200,d1                        ; in bytes
	add.l	d1,d0                           ; where the DMA should end
	cmp.l	dma_address_read.w,d0           ; there?
	bne.s	hd_test_read_error              ; no: as a read error
	movea.l	#$48810,a0                      ; the write buffer
	move.w	#$44,d0                         ; 68 sectors
	sub.w	hd_sectors_left.w,d0            ; less those left
	mulu.w	#$200,d0                        ; in bytes
	adda.l	d0,a0                           ; where the last read began in the pattern
	movea.l	#$40008,a1                      ; the read buffer
	moveq	#67,d6                          ; 68 sectors
hd_test_compare_sector:
	move.l	#$ff,d7                         ; 256 words a sector
hd_test_compare_word:
	cmpm.w	(a0)+,(a1)+                     ; the same?
	beq.w	hd_test_compare_next            ; yes
	movem.l	d7/a0-a1,-(sp)                  ; kept
	lea	msg_hd_data_compare_error,a5    ; "Data compare error (wrote, read, hex offset): "
	bsr.w	print_string                    ; printed
	suba.w	#$2,a0                          ; back to the word written
	suba.w	#$2,a1                          ; and the word read
	move.w	(a0),d0                         ; written
	bsr.w	print_hex_word                  ; printed
	bsr.w	print_space                     ; a space
	move.w	(a1),d0                         ; read
	bsr.w	print_hex_word                  ; printed
	bsr.w	print_space                     ; a space
	move.l	a1,d0                           ; the place
	sub.l	#$40008,d0                      ; its offset in the buffer
	bsr.w	print_hex_word                  ; printed
	bsr.w	print_space                     ; a space
	bsr.w	hd_print_cycle                  ; " Cycle: " and the cycle
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	bsr.w	key_waiting                     ; a key waiting?
	tst.w	d0                              ; no
	beq.s	hd_test_compare_key
	bsr.w	hd_stopped_menu                 ; yes: "Stopped." and its keys
hd_test_compare_key:
	movem.l	(sp)+,d7/a0-a1                  ; the places back
	cmpi.b	#$d,d0                          ; RETURN: go on comparing
	beq.s	hd_test_compare_next            ; yes
	bsr.w	hd_restore_data                 ; otherwise the kept data written back
	bra.s	hd_test_dispatch_key            ; and the key acted on
hd_test_compare_next:
	dbra	d7,hd_test_compare_word         ; every word of the sector
	dbra	d6,hd_test_compare_sector       ; every sector
	cmpi.l	#$18020000,$40000               ; the guard before the read buffer kept?
	bne.s	hd_test_guard_error             ; no
	cmpi.l	#$18020000,$48808               ; the guard between the buffers kept?
	bne.s	hd_test_guard_error             ; no
	cmpi.l	#$18020000,$51010               ; the guard after the write buffer kept?
	beq.s	hd_test_check_key               ; yes
hd_test_guard_error:
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	lea	msg_dma_address_error,a5        ; "DMA address error -- Data written outside data buffers"
	bsr.w	print_string                    ; printed
hd_test_check_key:
	bsr.w	key_waiting                     ; a key waiting?
	tst.w	d0                              ; none
	beq.w	hd_test_next_cycle              ; none: the next cycle
	bsr.w	hd_restore_data                 ; yes: the kept data written back
	bsr.w	get_key                         ; the key
	cmp.b	#$1b,d0                         ; Esc?
	bne.s	hd_test_check_key               ; no: a key waiting? (else the cycles go on)
	bsr.w	hd_stopped_menu                 ; yes: "Stopped." and its keys
hd_test_dispatch_key:
	cmp.b	#$53,d0                         ; S?
	beq.w	hd_test                         ; yes: from the start
	cmp.b	#$50,d0                         ; P?
	beq.w	hd_park_heads                   ; yes: park the heads
	cmp.b	#$51,d0                         ; Q?
	beq.w	hd_test_quit                    ; yes: quit
hd_test_next_cycle:
	subi.w	#$1,hd_sectors_left.w           ; (set again in the cycle)
	bra.w	hd_test_cycle                   ; the next cycle

;------------------------------------------------------------------------------
; hd_restore_data: the 68 sectors kept at $51020 written back from sector $9F1C on unit 0; "Error restoring
; data" if the write times out.  Changes d0-d7, a0-a5.
;------------------------------------------------------------------------------
hd_restore_data:	; from: hd_test
	move.w	#$258,hd_cylinder.w             ; "cylinder 600"
	move.l	#$9f1c,hd_sector.w              ; the first sector
	move.w	#$0,acsi_unit.w                 ; unit 0
	move.l	#$51020,acsi_dma_address.w      ; from the keep buffer
	move.w	#$44,acsi_count.w               ; 68 sectors
	move.l	hd_sector.w,acsi_sector.w       ; the sector for the command
	bsr.w	acsi_write_sectors              ; written
	tst.w	d0                              ; timed out?
	bpl.w	hd_restore_data_done            ; no
	lea	msg_error_restoring_data,a5     ; "Error restoring data"
	bsr.w	print_string                    ; printed
hd_restore_data_done:
	rts

;------------------------------------------------------------------------------
; hd_park_heads: after a pause, a STOP UNIT command ($1B) to unit 0 parks the heads: "HEADS ARE PARKED", or
; "Error -- Heads not parked!" and red.  Then P parks again, Q quits, RETURN restarts the cartridge.
;------------------------------------------------------------------------------
hd_park_heads:	; from: hd_test, hd_park_fail_cycle
	moveq	#50,d1                          ; 51 times
hd_park_delay_outer:
	move.l	#$186a0,d0                      ; 100000
hd_park_delay:
	dbra	d0,hd_park_delay
	dbra	d1,hd_park_delay_outer          ; the pause
	lea	acsi_stop_unit,a0               ; the STOP UNIT command
	bsr.w	acsi_command                    ; sent
	tst.w	d0                              ; status 0?
	beq.w	hd_park_ok                      ; yes: parked
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	lea	msg_heads_not_parked,a5         ; "Error -- Heads not parked!"
	bsr.w	print_string                    ; printed
	bra.w	hd_park_key                     ; a key
hd_park_ok:
	lea	msg_heads_are_parked,a5         ; "HEADS ARE PARKED"
	bsr.w	print_string                    ; printed
	bra.w	hd_park_key                     ; a key

;------------------------------------------------------------------------------
; (not reached) "Fail at cycle:" and red.
;------------------------------------------------------------------------------
hd_park_fail_cycle:
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
	bsr.w	print_string                    ; printed
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
hd_park_key:	; from: hd_park_heads
	bsr.w	get_key                         ; a key
	cmp.b	#$50,d0                         ; P?
	beq.s	hd_park_heads                   ; yes: park again
	cmp.b	#$51,d0                         ; Q?
	beq.w	hd_test_quit                    ; yes: quit
	cmp.b	#$d,d0                          ; RETURN?
	beq.w	cold_start                      ; yes: the cartridge from its start
	bne.s	hd_park_key                     ; no: again
hd_test_quit:	; from: hd_test
	bset	#$7,mode_flags.w                ; the test ended, back to the menu
	rts

;------------------------------------------------------------------------------
; scaled_count: (not called) d0 = (d0 + 17) / 17; above 3 it is taken as its remainder by 4; then doubled.
;------------------------------------------------------------------------------
scaled_count:
	add.l	#$11,d0                         ; + 17
	divu.w	#$11,d0                         ; / 17
	andi.l	#$ffff,d0                       ; the quotient
	cmp.l	#$3,d0                          ; 3 or less?
	ble.w	scaled_count_double             ; yes
	divu.w	#$4,d0                          ; no: / 4
	swap	d0                              ; the remainder
	andi.l	#$f,d0                          ; only
scaled_count_double:
	lsl.w	#1,d0                           ; doubled
	rts

;------------------------------------------------------------------------------
; hd_get_dma_address: the DMA address register read into $B90.
;------------------------------------------------------------------------------
hd_get_dma_address:	; from: hd_test
	clr.l	dma_address_read.w              ; the high byte clear
	move.b	$ffff8609.w,dma_address_read+1.w ; DMA base high, high
	move.b	$ffff860b.w,dma_address_read+2.w ; DMA base mid, mid
	move.b	$ffff860d.w,dma_address_read+3.w ; DMA base low, low
	rts

;------------------------------------------------------------------------------
; hd_fill_write_buffer: the write buffer ($48810-$5100F, 68 sectors) filled: each sector starts with the
; cycle, its sector number and the pattern's low word, then the pattern long chosen by the cycle (one of
; 8 in hd_test_patterns).  Changes d0, d2, d6, a0-a2.
;------------------------------------------------------------------------------
hd_fill_write_buffer:	; from: hd_test
	lea	$48810,a0                       ; the buffer
	lea	$48810,a1                       ; the sector ends from here
	lea	hd_test_patterns,a2             ; the patterns
	move.w	test_cycle.w,d6                 ; the cycle
	andi.w	#$7,d6                          ; one of 8
	lsl.w	#2,d6                           ; a long each
	move.l	0(a2,d6.w),d0                   ; the pattern
	move.l	hd_first_sector.w,d2            ; the first sector number
hd_fill_sector:
	adda.l	#$200,a1                        ; this sector's end
	move.w	test_cycle.w,(a0)+              ; the cycle
	move.w	d2,(a0)+                        ; the sector number
	move.w	d0,(a0)+                        ; the pattern's low word
hd_fill_long:
	move.l	d0,(a0)+                        ; the pattern
	cmpa.l	a0,a1                           ; to the sector's end
	bgt.s	hd_fill_long
	add.w	#$1,d2                          ; the next sector number
	cmpa.l	#$51010,a1                      ; the buffer's end?
	blt.s	hd_fill_sector                  ; no
	rts

;------------------------------------------------------------------------------
; hd_test_patterns: the hard disk exerciser's data patterns, one long for each cycle (cycle
; number ($216) and 7). $76dc fills each 512-byte sector with the cycle, the sector number
; and then this pattern.
;------------------------------------------------------------------------------
hd_test_patterns:	; from: hd_fill_write_buffer
	dc.l	$ff00aa55,$99ee66dd,$a56bffee,$a5a5a5a5
	dc.l	$11223344,$55667788,$0f0f0f0f,$fedcba98

;------------------------------------------------------------------------------
; hd_known_bad_sector: is the failed sector ($BD8 - 1) in the known bad sector list ($BEE up to $C6E)?
; Z set if it is.  At the list's end the beq jumps to $1CE4 (the RAM test's pattern routine) instead of the
; code at $7760 that adds the sector, so the list stays empty: that routine writes the patterns d0/d2 from
; a0 up to a1 and returns with Z set, and the read goes on.
;------------------------------------------------------------------------------
hd_known_bad_sector:	; from: hd_test
	move.l	hd_sector.w,d0                  ; the sector read last
	sub.l	#$1,d0                          ; the failed one
	lea	hd_bad_sectors.w,a2             ; the list
hd_known_bad_next:
	cmpa.l	hd_bad_sectors_end.w,a2         ; the list's end?
	beq.w	test_pattern_pair               ; yes: into the RAM test's pattern routine
	cmp.l	(a2)+,d0                        ; this one?
	beq.w	hd_known_bad_done               ; yes: Z set
	bra.s	hd_known_bad_next               ; the next
hd_add_bad_sector:
	move.l	d0,(a2)+                        ; (not reached) added
	move.l	a2,hd_bad_sectors_end.w         ; the list's new end
	andi.b	#$1b,ccr                        ; Z clear
hd_known_bad_done:
	rts

;------------------------------------------------------------------------------
; acsi_command: a 6-byte ACSI command with no data sent from a0 to unit $BE2; d0 = the status byte, or
; -1 when the unit does not answer ("Controller not responding").  Changes d1, a0, a5; leaves the interrupt
; mask at 4.
;------------------------------------------------------------------------------
acsi_command:	; from: hd_park_heads
	move.w	#$88,$ffff8606.w                ; DMA mode / status, the ACSI, A1 low: the first byte
	clr.l	d0                              ; the high word clear
	move.w	acsi_unit.w,d0                  ; the unit
	lsl.w	#5,d0                           ; in bits 7-5
	or.b	(a0)+,d0                        ; with the opcode
	swap	d0                              ; into the data word
	move.w	#$8a,d0                         ; the mode: ACSI, A1 high next
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, sent
	moveq	#4,d1                           ; 5 more bytes
acsi_command_byte:
	bsr.w	acsi_wait                       ; the unit ready?
	bmi.w	acsi_fail                       ; no: -1
	move.b	(a0)+,d0                        ; the next byte
	swap	d0                              ; into the data word
	move.w	#$8a,d0                         ; the mode
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, sent
	dbra	d1,acsi_command_byte            ; each
	bsr.w	acsi_wait_long                  ; the command done (the long wait)?
	bmi.w	acsi_fail                       ; no: -1
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, the status
	andi.w	#$ff,d0                         ; its byte
	bra.w	acsi_exit                       ; out

;------------------------------------------------------------------------------
; acsi_write_sectors: a WRITE ($0A) of $BE0 sectors from sector $BDC on unit $BE2, DMA from $BE4.  d0 = the
; status byte (a "Command error" and the sense data printed if it is not 0), or -1 on a timeout.
; Changes d0-d2, d7, a4, a5.
;------------------------------------------------------------------------------
acsi_write_sectors:	; from: hd_test, hd_restore_data
	move.w	#$2700,sr                       ; no interrupts
	bsr.w	acsi_set_dma_address            ; the DMA address
	move.w	#$88,$ffff8606.w                ; DMA mode / status, the ACSI, A1 low
	clr.l	d0                              ; the high word clear
	move.w	acsi_unit.w,d0                  ; the unit
	lsl.w	#5,d0                           ; in bits 7-5
	swap	d0                              ; into the data word
	ori.l	#$a008a,d0                      ; with WRITE ($0A), the mode
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, the first byte sent
	bsr.w	acsi_send_address               ; the address and the count
	bmi.w	acsi_fail                       ; no answer: -1
	move.w	#$90,$ffff8606.w                ; DMA mode / status, the DMA FIFO cleared and set to write: read
	nop
	move.w	#$190,$ffff8606.w               ; DMA mode / status, then write
	nop
	move.w	acsi_count.w,$ffff8604.w        ; DMA sector count / FDC access, the sector count
	nop
	move.w	#$18a,$ffff8606.w               ; DMA mode / status, write, A1 low
	nop
	move.l	#$100,$ffff8604.w               ; DMA sector count / FDC access, the last byte (0); the DMA starts
	move.w	#$18a,d0                        ; write mode
	bsr.w	acsi_status                     ; the status at the end
	beq.w	acsi_write_done                 ; 0: good
	bsr.w	acsi_command_error              ; else "Command error" and the sense data
acsi_write_done:
	bra.w	acsi_exit

;------------------------------------------------------------------------------
; acsi_read_sectors: a READ ($08) of $BE0 sectors from sector $BDC on unit $BE2, DMA to $BE4.  d0 = the
; status byte (a "Command error" and the sense data printed if it is not 0), or -1 on a timeout.
; Changes d0-d2, d7, a4, a5.
;------------------------------------------------------------------------------
acsi_read_sectors:	; from: hd_test
	move.w	#$2700,sr                       ; no interrupts
	move.w	#$88,$ffff8606.w                ; DMA mode / status, the ACSI, A1 low
	clr.l	d0                              ; the high word clear
	move.w	acsi_unit.w,d0                  ; the unit
	lsl.w	#5,d0                           ; in bits 7-5
	swap	d0                              ; into the data word
	ori.l	#$8008a,d0                      ; with READ ($08), the mode
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, the first byte sent
	bsr.w	acsi_set_dma_address            ; the DMA address
	bsr.w	acsi_send_address               ; the address and the count
	bmi.w	acsi_fail                       ; no answer: -1
	move.w	#$190,$ffff8606.w               ; DMA mode / status, the DMA FIFO cleared and set to read: write
	nop
	move.w	#$90,$ffff8606.w                ; DMA mode / status, then read
	nop
	move.w	acsi_count.w,$ffff8604.w        ; DMA sector count / FDC access, the sector count
	nop
	move.w	#$8a,$ffff8606.w                ; DMA mode / status, read, A1 low
	nop
	move.l	#$0,$ffff8604.w                 ; DMA sector count / FDC access, the last byte (0); the DMA starts
	move.w	#$8a,d0                         ; read mode
	bsr.w	acsi_status                     ; the status at the end
	beq.w	acsi_read_done                  ; 0: good
	bsr.w	acsi_command_error              ; else "Command error" and the sense data
acsi_read_done:
	bra.w	acsi_exit
acsi_fail:	; from: acsi_command, acsi_write_sectors
	moveq	#-1,d0                          ; -1: no answer
acsi_exit:	; from: acsi_command, acsi_write_sectors
	move.w	#$2400,sr                       ; interrupts back on
	tst.w	$ffff8604.w                     ; DMA sector count / FDC access, (a read of the DMA register)
	rts

;------------------------------------------------------------------------------
; acsi_command_error: "Command error", red, then a REQUEST SENSE; when its four rounds all worked,
; " Status = " and d7 + 1 sense bytes from $59820 in hex (d7 as the caller left it).  d0 is kept.
;------------------------------------------------------------------------------
acsi_command_error:	; from: acsi_write_sectors, acsi_read_sectors
	move.w	d0,-(sp)                        ; the status kept
	lea	msg_command_error,a5            ; "Command error"
	bsr.w	print_string                    ; printed
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	bsr.w	acsi_request_sense              ; the sense data read
	cmp.l	#$ffff,d2                       ; all four rounds done?
	bne.s	acsi_command_error_done         ; no
	lea	msg_status,a5                   ; " Status = "
	bsr.w	print_string                    ; printed
	lea	$59820,a4                       ; the sense data
	clr.w	d4                              ; from the first byte
acsi_command_error_byte:
	move.b	0(a4,d4.w),d0                   ; a byte
	bsr.w	print_hex_byte                  ; in hex
	bsr.w	print_space                     ; a space
	addi.w	#$1,d4                          ; the next
	dbra	d7,acsi_command_error_byte      ; d7 + 1 of them
	bsr.w	print_newline                   ; a new line
acsi_command_error_done:
	move.w	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; acsi_status: waits (the long timeout) for the unit to finish, then the mode d0 is set and d0 = the status
; byte; -1 on a timeout.  Changes d1; interrupts back on.
;------------------------------------------------------------------------------
acsi_status:	; from: acsi_write_sectors, acsi_read_sectors, acsi_request_sense
	move.w	#$2400,sr                       ; interrupts on
	move.w	d0,d1                           ; the mode
	bsr.w	acsi_wait_long                  ; the end of the command
	bmi.w	acsi_status_done                ; timed out
	move.w	d1,$ffff8606.w                  ; DMA mode / status, the mode
	nop
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, the status
	and.w	#$ff,d0                         ; its byte
acsi_status_done:
	rts

;------------------------------------------------------------------------------
; acsi_request_sense: REQUEST SENSE ($03) on unit $BE2 with one sector's DMA to $59820, four times with
; 2 ticks between; d2 = $FFFF when all four worked.  Changes d0-d2, a5.
;------------------------------------------------------------------------------
acsi_request_sense:	; from: acsi_command_error
	move.l	#$59820,acsi_dma_address.w      ; the sense buffer
	bsr.w	acsi_set_dma_address            ; the DMA address
	move.w	#$190,$ffff8606.w               ; DMA mode / status, the DMA FIFO cleared and set to read: write
	nop
	move.w	#$90,$ffff8606.w                ; DMA mode / status, then read
	nop
	move.w	#$1,$ffff8604.w                 ; DMA sector count / FDC access, one sector
	nop
	move.w	#$3,d2                          ; 4 rounds
acsi_request_sense_loop:
	move.w	#$88,$ffff8606.w                ; DMA mode / status, the ACSI, A1 low
	move.w	acsi_unit.w,d0                  ; the unit
	lsl.b	#5,d0                           ; in bits 7-5
	swap	d0                              ; into the data word
	or.l	#$3008a,d0                      ; with REQUEST SENSE ($03), the mode
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, the first byte sent
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_request_sense_done         ; no
	move.l	#$8a,$ffff8604.w                ; DMA sector count / FDC access, a 0 byte
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_request_sense_done         ; no
	move.l	#$8a,$ffff8604.w                ; DMA sector count / FDC access, a 0 byte
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_request_sense_done         ; no
	move.l	#$8a,$ffff8604.w                ; DMA sector count / FDC access, a 0 byte
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_request_sense_done         ; no
	move.l	#$8a,$ffff8604.w                ; DMA sector count / FDC access, a 0 byte
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_request_sense_done         ; no
	move.w	#$8a,$ffff8606.w                ; DMA mode / status, read, A1 low
	nop
	move.l	#$0,$ffff8604.w                 ; DMA sector count / FDC access, the last byte (0)
	move.w	#$8a,d0                         ; read mode
	bsr.w	acsi_status                     ; the status at the end
	bmi.w	acsi_request_sense_done         ; timed out
	move.l	$4ba.w,d1                       ; the 200 Hz count
	addq.l	#2,d1                           ; + 2
acsi_request_sense_wait:
	cmp.l	$4ba.w,d1                       ; 2 ticks
	bcc.s	acsi_request_sense_wait
	dbra	d2,acsi_request_sense_loop      ; each round
acsi_request_sense_done:
	rts

;------------------------------------------------------------------------------
; acsi_set_dma_address: the DMA address register set to $BE4 (low byte first).
;------------------------------------------------------------------------------
acsi_set_dma_address:	; from: acsi_write_sectors, acsi_read_sectors, acsi_request_sense
	move.b	acsi_dma_address+3.w,$ffff860d.w ; DMA base low, low
	move.b	acsi_dma_address+2.w,$ffff860b.w ; DMA base mid, mid
	move.b	acsi_dma_address+1.w,$ffff8609.w ; DMA base high, high
	rts

;------------------------------------------------------------------------------
; acsi_send_address: command bytes 2-5 sent: the unit (bits 7-5, from the low byte of $BE2) with the
; sector's high byte, its mid and low bytes ($BDD-$BDF), and the count ($BE0).  d0 -1 (N set) when the
; unit does not answer.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
acsi_send_address:	; from: acsi_write_sectors, acsi_read_sectors
	move.w	#$8a,$ffff8606.w                ; DMA mode / status, ACSI, A1 high
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_send_address_done          ; no
	move.b	acsi_sector+1.w,d0              ; the sector's high byte
	move.b	acsi_unit+1.w,d1                ; the unit
	lsl.b	#5,d1                           ; in bits 7-5
	or.b	d1,d0                           ; together
	swap	d0                              ; into the data word
	move.w	#$8a,d0                         ; the mode
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, sent
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_send_address_done          ; no
	move.b	acsi_sector+2.w,d0              ; the sector's mid byte
	swap	d0                              ; into the data word
	move.w	#$8a,d0                         ; the mode
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, sent
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_send_address_done          ; no
	move.b	acsi_sector+3.w,d0              ; the sector's low byte
	swap	d0                              ; into the data word
	move.w	#$8a,d0                         ; the mode
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, sent
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_send_address_done          ; no
	move.w	acsi_count.w,d0                 ; the count
	swap	d0                              ; into the data word
	move.w	#$8a,d0                         ; the mode
	move.l	d0,$ffff8604.w                  ; DMA sector count / FDC access, sent
	bsr.w	acsi_wait                       ; ready?
acsi_send_address_done:
	rts

;------------------------------------------------------------------------------
; acsi_wait_long: as acsi_wait with the long timeout ($6DDD0 rounds) for the end of a command; a timeout
; prints "Operation timed-out".
;------------------------------------------------------------------------------
acsi_wait_long:	; from: acsi_command, acsi_status
	move.l	#$6ddd0,acsi_timeout.w          ; the long timeout
	move.w	d1,-(sp)                        ; kept
	move.w	#$1,d1                          ; "Operation timed-out" if it runs out
	bra.w	acsi_wait_loop

;------------------------------------------------------------------------------
; acsi_wait: waits for the unit's interrupt (GPIP 5 low): d0 = 0 (Z set), or -1 (N set) after $3A98 rounds
; with "Controller not responding" printed.  d1 kept.
;------------------------------------------------------------------------------
acsi_wait:	; from: acsi_command, acsi_request_sense, acsi_send_address
	move.l	#$3a98,acsi_timeout.w           ; the short timeout
	move.w	d1,-(sp)                        ; kept
	move.w	#$0,d1                          ; "Controller not responding" if it runs out
acsi_wait_loop:	; from: acsi_wait_long
	subq.l	#1,acsi_timeout.w               ; one round
	bmi.w	acsi_wait_timeout               ; run out
	move.b	$fffffa01.w,d0                  ; MFP GPIP, the MFP's inputs
	and.b	#$20,d0                         ; the FDC/ACSI interrupt (low when the unit is ready)
	bne.s	acsi_wait_loop                  ; not yet
	move.w	(sp)+,d1
	moveq	#0,d0                           ; 0: ready
	rts
acsi_wait_timeout:
	lea	msg_controller_not_responding,a5 ; "Controller not responding"
	tst.w	d1                              ; the long wait?
	beq.w	acsi_wait_print                 ; no
	lea	msg_operation_timed_out,a5      ; "Operation timed-out"
acsi_wait_print:
	bsr.w	print_string                    ; printed
	move.w	(sp)+,d1
	moveq	#-1,d0                          ; -1
	rts

;------------------------------------------------------------------------------
; hd_pause: waits 100 ticks of the 200 Hz count (half a second).  Changes d7.
;------------------------------------------------------------------------------
hd_pause:	; from: hd_test
	move.l	$4ba.w,d7                       ; the 200 Hz count
	addi.w	#$64,d7                         ; + 100
hd_pause_loop:
	cmp.l	$4ba.w,d7
	bne.s	hd_pause_loop
	rts

;------------------------------------------------------------------------------
; hd_print_cycle: " Cycle: " and the cycle count ($216 word) in decimal, then a new line.
;------------------------------------------------------------------------------
hd_print_cycle:	; from: hd_test, hd_status_line
	lea	msg_hd_cycle,a5                 ; " Cycle: "
	bsr.w	print_string                    ; printed
	move.w	test_cycle.w,d0                 ; the cycle
	bsr.w	word_to_bcd                     ; in decimal digits
	bsr.w	print_hex_word                  ; printed
	bsr.w	print_newline                   ; a new line
	rts

;------------------------------------------------------------------------------
; hd_status_line: the status line at the top: the text at a5, the cylinder ($BD2) in decimal,
; "<<  Hit <Esc> key to stop.  >>" and the cycle; the cursor goes back.
;------------------------------------------------------------------------------
hd_status_line:	; from: hd_test
	bsr.w	save_cursor                     ; the cursor's place kept
	moveq	#0,d0                           ; column 0
	moveq	#0,d1                           ; row 0
	bsr.w	set_cursor                      ; the cursor there
	bsr.w	print_string                    ; the text
	move.w	hd_cylinder.w,d0                ; the cylinder
	bsr.w	word_to_bcd                     ; in decimal digits
	bsr.w	print_hex_word                  ; printed
	lea	msg_hit_esc_to_stop,a5          ; "   <<  Hit <Esc> key to stop.  >>   "
	bsr.w	print_string                    ; printed
	bsr.s	hd_print_cycle                  ; " Cycle: " and the cycle
	bsr.w	restore_cursor                  ; the cursor back
	rts

;------------------------------------------------------------------------------
; hd_stopped_menu: "Stopped. RETURN=continue, S=restart, Q=quit, P=park heads"; waits for one of those
; keys, clears the line and returns it in d0.
;------------------------------------------------------------------------------
hd_stopped_menu:	; from: hd_test
	lea	msg_hd_stopped_menu,a5          ; "Stopped. RETURN=continue, ..."
	bsr.w	print_string                    ; printed
hd_stopped_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$d,d0                          ; RETURN?
	beq.w	hd_stopped_clear
	cmp.b	#$51,d0                         ; Q?
	beq.w	hd_stopped_clear
	cmp.b	#$50,d0                         ; P?
	beq.w	hd_stopped_clear
	cmp.b	#$53,d0                         ; S?
	bne.s	hd_stopped_key                  ; none of them: again
hd_stopped_clear:
	move.b	d0,-(sp)                        ; the key kept
	move.w	cursor_row.w,d1                 ; this row
	clr.w	d0                              ; column 0
	bsr.w	set_cursor                      ; the cursor there
	bsr.w	clear_to_line_end               ; the line cleared
	move.b	(sp)+,d0                        ; the key
	rts

;------------------------------------------------------------------------------
; rtc_test: L, "Testing real-time clock".  No clock: "C0 No clock installed" and red.  Otherwise, at 8 MHz
; without the cache, the time is kept (2 seconds on), then the clock is set to 23:59:59 Sat 31/12/99 and
; 23:59:59 19/06/87, and must read back the same and, a second later, 00:00:00 01/01/00 and 20/06/87
; ("C1 clock increment error" otherwise).  The kept time is set back; when attended a VBL routine
; showing the time is put in and taken out again.  The CPU goes back to 16 MHz with the cache.
;------------------------------------------------------------------------------
rtc_test:	; from: test_routines
	lea	msg_testing_rtc,a5              ; "Testing real-time clock"
	bsr.w	show_status                     ; in the top line
	bsr.w	rtc_detect                      ; a clock there?
	beq.w	rtc_test_found                  ; yes
	lea	msg_no_clock,a5                 ; "C0 No clock installed"
	bsr.w	print_string                    ; printed
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	rts
rtc_test_found:
	move.b	#$0,$ff8e21                     ; Mega STE cache and CPU speed, 8 MHz, no cache (the timing loop)
	move.b	#$1,1(a0)                       ; bank 1 register 0: the clock output
	move.b	#$1,$15(a0)                     ; bank 1 register 10: 24-hour mode
	move.b	#$0,$1b(a0)                     ; bank 0, the timer stopped
	bsr.w	rtc_read                        ; the time read
	lea	rtc_image.w,a0                  ; the registers read
	lea	rtc_saved.w,a1                  ; kept here
	moveq	#12,d7                          ; 13 registers
rtc_test_save:
	move.w	(a0)+,(a1)+
	dbra	d7,rtc_test_save                ; each
	addi.w	#$2,rtc_saved.w                 ; the kept seconds 2 on
	lea	rtc_test_1_start,a1             ; 23:59:59 Sat 31/12/99
	lea	rtc_test_1_end,a2               ; then 00:00:00 01/01/00
	bsr.w	rtc_check_increment             ; written, read, a second, read
	bne.w	rtc_test_fail                   ; wrong
	lea	rtc_test_2_start,a1             ; 23:59:59 19/06/87
	lea	rtc_test_2_end,a2               ; then 20/06/87
	bsr.w	rtc_check_increment             ; written, read, a second, read
	bne.w	rtc_test_fail                   ; wrong
	lea	msg_pass,a5                     ; "Pass"
	bra.w	rtc_test_result                 ; to the result
rtc_test_fail:
	lea	msg_clock_increment_error,a5    ; "C1 clock increment error"
	bsr.w	print_string                    ; printed
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
rtc_test_result:
	bsr.w	show_result                     ; the result printed
	lea	rtc_saved.w,a1                  ; the kept time
	bsr.w	rtc_write_time                  ; set back
	tst.b	unattended.w                    ; unattended?
	bne.w	rtc_test_done                   ; yes: done
	move.l	$70.w,-(sp)                     ; VBL vector, the VBL kept
	move.l	#rtc_clock_vbl,$70.w            ; VBL vector, the time shown from the VBL
	move.b	#$1e,vbl_flag.w                 ; every 30 VBLs
	move.w	#$2200,sr                       ; VBLs on
	bsr.w	flush_input                     ; the input flushed (no wait: the display goes again at once)
	move.w	#$2400,sr                       ; VBLs off
	move.l	(sp)+,$70.w                     ; VBL vector, the VBL back
rtc_test_done:
	move.b	#$3,$ff8e21                     ; Mega STE cache and CPU speed, 16 MHz, the cache on
	rts

;------------------------------------------------------------------------------
; rtc_clock_vbl: the VBL routine of rtc_test: every 30 VBLs the time is read and shown on row 1.
;------------------------------------------------------------------------------
rtc_clock_vbl:	; from: rtc_test
	subi.b	#$1,vbl_flag.w                  ; one VBL
	bne.w	rtc_clock_vbl_exit              ; not yet
	move.b	#$1e,vbl_flag.w                 ; 30 again
	movem.l	d0-d7/a0-a6,-(sp)               ; all kept
	bsr.w	rtc_read                        ; the time read
	bsr.w	rtc_show_time                   ; and shown
	movem.l	(sp)+,d0-d7/a0-a6               ; back
rtc_clock_vbl_exit:
	rte

;------------------------------------------------------------------------------
; rtc_check_increment: the clock set to the 13 registers at a1 (odd bytes), read back and compared, then
; set again and run for about a second and compared with a2.  Z set if both matched ($676 holds the
; registers that did not, as bits).  Leaves the timer running.  Changes d0-d2, d7, a0-a3.
;------------------------------------------------------------------------------
rtc_check_increment:	; from: rtc_test
	movem.l	a1-a2,-(sp)                     ; kept
	bsr.w	rtc_write_time                  ; the clock set
	bsr.w	rtc_read                        ; read
	bsr.w	rtc_compare                     ; compared
	bsr.w	rtc_show_time                   ; shown
	movem.l	(sp)+,a1-a2                     ; back
	tst.b	test_errors.w                   ; all the same?
	bne.w	rtc_check_increment_done        ; no: Z clear
	move.b	#$0,$1b(a0)                     ; the timer stopped
	bsr.w	rtc_write_time                  ; the clock set again
	move.b	#$8,$1b(a0)                     ; the timer started
	move.l	#$6d538,d7                      ; about a second at 8 MHz
rtc_check_increment_wait:
	subq.l	#1,d7
	bne.s	rtc_check_increment_wait
	move.b	#$0,$1b(a0)                     ; the timer stopped
	movem.l	a1-a2,-(sp)                     ; kept
	movea.l	a2,a1                           ; the time it must show now
	bsr.w	rtc_read                        ; read
	bsr.w	rtc_compare                     ; compared
	bsr.w	rtc_show_time                   ; shown
	move.b	#$8,$1b(a0)                     ; the timer started
	movem.l	(sp)+,a1-a2                     ; back
	tst.b	test_errors.w                   ; all the same?
rtc_check_increment_done:
	rts

;------------------------------------------------------------------------------
; rtc_set_from_input: (not reached) "Enter time: hhmmss", "Enter date: mmddyy" and the day typed in and
; written to the clock.
;------------------------------------------------------------------------------
rtc_set_from_input:
	lea	msg_enter_time,a5               ; "Enter time: hhmmss"
	bsr.w	print_string                    ; printed
	lea	$66a.w,a1                       ; the digits' end
	bsr.w	rtc_read_digits                 ; typed in
	beq.w	rtc_set_date                    ; nothing: the date
	lea	rtc_saved.w,a0                  ; the clock image
	move.w	#$1,d1                          ; the seconds' units
rtc_set_time_digit:
	move.b	-(a1),0(a0,d1.w)                ; the digits backwards
	add.w	#$2,d1                          ; the next register
	cmp.w	#$d,d1                          ; the hours' tens done?
	bne.s	rtc_set_time_digit              ; no
	bsr.w	print_newline                   ; a new line
	lea	rtc_saved.w,a1                  ; the clock image
	bsr.w	rtc_write_time                  ; written
rtc_set_date:
	lea	msg_enter_date,a5               ; "Enter date: mmddyy"
	bsr.w	print_string                    ; printed
	lea	$66a.w,a1                       ; the digits' end
	bsr.w	rtc_read_digits                 ; typed in
	beq.w	rtc_set_day                     ; nothing: the day
	lea	rtc_saved.w,a0                  ; the clock image
	move.b	-(a1),$17(a0)                   ; the year's units
	move.b	-(a1),$19(a0)                   ; its tens
	move.b	-(a1),$f(a0)                    ; the day's units
	move.b	-(a1),$11(a0)                   ; its tens
	move.b	-(a1),$13(a0)                   ; the month's units
	move.b	-(a1),$15(a0)                   ; its tens
	bsr.w	print_newline                   ; a new line
	lea	rtc_saved.w,a1                  ; the clock image
	bsr.w	rtc_write_date                  ; the date written
rtc_set_day:
	lea	msg_enter_day,a5                ; "Day: Sun=1 Mon=2 ..."
	bsr.w	print_string                    ; printed
	bsr.w	read_line                       ; a line typed
	lea	line_buffer.w,a0                ; the line
	move.b	(a0)+,d0                        ; the first character
	bsr.w	rtc_is_digit                    ; a digit?
	bne.w	rtc_set_done                    ; no
	andi.b	#$7,d0                          ; 0-7
	bsr.w	rtc_write_day                   ; the day written
rtc_set_done:
	rts

;------------------------------------------------------------------------------
; rtc_read_digits: a line typed in; its digits stored as values from a1 up (a1 left after them).  Z set
; when nothing was typed.  Changes d0, a0, a1, a4.
;------------------------------------------------------------------------------
rtc_read_digits:	; from: rtc_set_from_input
	bsr.w	read_line                       ; a line typed
	bsr.w	print_newline                   ; a new line
	tst.w	d0                              ; anything?
	bne.w	rtc_read_digits_scan            ; yes
	rts                                     ; no: Z set
rtc_read_digits_scan:
	lea	line_buffer.w,a0                ; the line
rtc_read_digits_next:
	cmpa.l	a0,a4                           ; its end?
	beq.w	rtc_read_digits_done            ; yes
	move.b	(a0)+,d0                        ; a character
	bsr.w	rtc_is_digit                    ; a digit?
	bne.s	rtc_read_digits_next            ; no: skipped
	andi.b	#$f,d0                          ; its value
	move.b	d0,(a1)+                        ; stored
	bpl.s	rtc_read_digits_next            ; the next
rtc_read_digits_done:
	andi.b	#$fb,ccr                        ; Z clear
	rts

;------------------------------------------------------------------------------
; rtc_is_digit: Z set when d0 is '0'-'9'.
;------------------------------------------------------------------------------
rtc_is_digit:	; from: rtc_set_from_input, rtc_read_digits
	cmpi.b	#$30,d0                         ; below '0'?
	blt.w	rtc_is_digit_done               ; yes: Z clear
	cmpi.b	#$39,d0                         ; above '9'?
	bgt.w	rtc_is_digit_done               ; yes: Z clear
	ori.b	#$4,ccr                         ; a digit: Z set
rtc_is_digit_done:
	rts

;------------------------------------------------------------------------------
; rtc_write_time: the 13 time and date registers written from a1's odd bytes, the seconds' divider reset
; first.  Changes d0, d1, d7, a0.
;------------------------------------------------------------------------------
rtc_write_time:	; from: rtc_test, rtc_check_increment, rtc_set_from_input
	lea	$fffc20,a0                      ; the clock
	move.b	#$2,$1f(a0)                     ; the divider reset
	moveq	#12,d7                          ; 13 registers
	moveq	#1,d0                           ; the first's odd byte
rtc_write_time_reg:
	move.b	0(a1,d0.w),d1                   ; the value
	move.b	d1,0(a0,d0.w)                   ; written
	addq.w	#2,d0                           ; the next register
	dbra	d7,rtc_write_time_reg
	rts

;------------------------------------------------------------------------------
; rtc_write_date: the date registers (7-12: day, month, year) written from a1's odd bytes.
; Changes d0, d1, d7, a0.
;------------------------------------------------------------------------------
rtc_write_date:	; from: rtc_set_from_input
	lea	$fffc20,a0                      ; the clock
	move.b	#$2,$1f(a0)                     ; the divider reset
	moveq	#5,d7                           ; 6 registers
	moveq	#15,d0                          ; from the day's units
rtc_write_date_reg:
	move.b	0(a1,d0.w),d1                   ; the value
	move.b	d1,0(a0,d0.w)                   ; written
	addq.w	#2,d0                           ; the next register
	dbra	d7,rtc_write_date_reg
	rts

;------------------------------------------------------------------------------
; rtc_write_day: the day of the week (register 6) set to d0.  Changes a0.
;------------------------------------------------------------------------------
rtc_write_day:	; from: rtc_set_from_input
	lea	$fffc20,a0                      ; the clock
	move.b	#$2,$1f(a0)                     ; the divider reset
	move.b	d0,$d(a0)                       ; the day
	rts

;------------------------------------------------------------------------------
; rtc_compare: the 13 registers read ($636) compared with a1's; each one different sets bit (number & 7)
; of $676.  Changes d0-d2, d7, a3.
;------------------------------------------------------------------------------
rtc_compare:	; from: rtc_check_increment
	move.b	#$0,test_errors.w               ; none different yet
	moveq	#12,d7                          ; 13 registers
	moveq	#1,d0                           ; the first's odd byte
	lea	rtc_image.w,a3                  ; the registers read
rtc_compare_reg:
	move.b	0(a3,d0.w),d2                   ; read
	cmp.b	0(a1,d0.w),d2                   ; the same?
	beq.w	rtc_compare_next                ; yes
	move.b	d0,d1                           ; the register's number
	subq.w	#1,d1
	lsr.w	#1,d1
	bset	d1,test_errors.w                ; marked
rtc_compare_next:
	addq.w	#2,d0                           ; the next
	dbra	d7,rtc_compare_reg
	rts

;------------------------------------------------------------------------------
; rtc_read: the 13 time and date registers read into $636 (odd bytes), each masked to its digit's bits.
; Changes d0, d2, d7, a0, a2, a3.
;------------------------------------------------------------------------------
rtc_read:	; from: rtc_test, rtc_clock_vbl, rtc_check_increment
	moveq	#12,d7                          ; 13 registers
	moveq	#1,d0                           ; the first's odd byte
	lea	$fffc20,a0                      ; the clock
	lea	rtc_register_masks,a2           ; the masks
	lea	rtc_image.w,a3                  ; the image
rtc_read_reg:
	move.b	0(a0,d0.w),d2                   ; read
	and.b	0(a2,d0.w),d2                   ; masked
	move.b	d2,0(a3,d0.w)                   ; stored
	addq.w	#2,d0                           ; the next
	dbra	d7,rtc_read_reg
	rts

;------------------------------------------------------------------------------
; rtc_show_time: (attended only) the time read ($636) shown at row 1: "hh:mm:ss mm/dd/yy day".  The cursor
; goes back.  Changes d0, d1, d7, a3-a5.
;------------------------------------------------------------------------------
rtc_show_time:	; from: rtc_clock_vbl, rtc_check_increment
	tst.b	unattended.w                    ; unattended?
	beq.w	rtc_show_time_print             ; no
	rts                                     ; yes: nothing
rtc_show_time_print:
	movem.l	a0-a2,-(sp)                     ; kept
	move.w	cursor_column.w,status_saved_column.w ; the cursor's place kept
	move.w	cursor_row.w,status_saved_row.w
	moveq	#0,d0                           ; column 0
	moveq	#1,d1                           ; row 1
	bsr.w	set_cursor                      ; the cursor there
	lea	rtc_image.w,a3                  ; the time read
	move.b	$b(a3),d1                       ; the hours' tens
	lsl.w	#4,d1
	or.b	9(a3),d1                        ; and units
	bsr.w	print_hex_byte                  ; printed
	move.b	#$3a,d1                         ; ':'
	bsr.w	put_char
	move.b	7(a3),d1                        ; the minutes' tens
	lsl.w	#4,d1
	or.b	5(a3),d1                        ; and units
	bsr.w	print_hex_byte                  ; printed
	move.b	#$3a,d1                         ; ':'
	bsr.w	put_char
	move.b	3(a3),d1                        ; the seconds' tens
	lsl.w	#4,d1
	or.b	1(a3),d1                        ; and units
	bsr.w	print_hex_byte                  ; printed
	bsr.w	print_space                     ; a space
	move.b	$15(a3),d1                      ; the month's tens
	lsl.w	#4,d1
	or.b	$13(a3),d1                      ; and units
	bsr.w	print_hex_byte                  ; printed
	move.b	#$2f,d1                         ; '/'
	bsr.w	put_char
	move.b	$11(a3),d1                      ; the day's tens
	lsl.w	#4,d1
	or.b	$f(a3),d1                       ; and units
	bsr.w	print_hex_byte                  ; printed
	move.b	#$2f,d1                         ; '/'
	bsr.w	put_char
	move.b	$19(a3),d1                      ; the year's tens
	lsl.w	#4,d1
	or.b	$17(a3),d1                      ; and units
	bsr.w	print_hex_byte                  ; printed
	bsr.w	print_space                     ; a space
	move.b	$d(a3),d1                       ; the day of the week
	andi.w	#$7,d1                          ; 0-7
	lsl.w	#2,d1                           ; a pointer each
	lea	day_names,a4                    ; the day names
	movea.l	0(a4,d1.w),a5                   ; this one
	bsr.w	print_string                    ; printed
	bsr.w	print_newline                   ; a new line
	move.w	status_saved_column.w,d0        ; the cursor back
	move.w	status_saved_row.w,d1
	bsr.w	set_cursor
	movem.l	(sp)+,a0-a2                     ; back
	rts

;------------------------------------------------------------------------------
; rtc_detect: is there a clock?  $A and 5 written to bank 1 registers 2 and 3 (the alarm minutes) must
; read back.  Z set and $28E bit 1 set when they do; a0 = the clock.
;------------------------------------------------------------------------------
rtc_detect:	; from: rtc_test
	lea	$fffc20,a0                      ; the clock
	ori.b	#$2,clock_flags.w               ; a clock (until shown otherwise)
	move.b	#$0,$1d(a0)                     ; the test register 0
	move.b	#$9,$1b(a0)                     ; bank 1, the timer on
	move.w	#$a05,d0                        ; $A and 5
	movep.w	d0,5(a0)                        ; to registers 2 and 3
	movep.w	5(a0),d1                        ; read back
	andi.w	#$f0f,d1                        ; their 4 bits
	cmpi.w	#$a05,d1                        ; the same?
	beq.w	rtc_detect_done                 ; yes: Z set
	andi.b	#$fd,clock_flags.w              ; no clock
	andi.b	#$fb,ccr                        ; Z clear
rtc_detect_done:
	rts

;------------------------------------------------------------------------------
; scc_test: I, "Testing SCC".  Each channel: internal loopback, then the break test for a loopback plug
; ("Port A/B has no loopback connector"); the LAN (channel A through PSG port A bit 7) loopback and its
; DTR/DCD lines; then on each plugged port async loopback, modem lines (DTR to DCD and SYNC, RTS to
; CTS), and 512 bytes by interrupt (vectors $180-$1BC, the SCU's level 5 enabled).  Results in $676-$67F,
; the errors printed by bits, then "Pass" or "Fail at cycle:".
;------------------------------------------------------------------------------
scc_test:	; from: test_routines
	movea.l	#msg_testing_scc,a5             ; "Testing SCC"
	bsr.w	show_status                     ; in the top line
	bsr.w	scc_select_serial               ; the serial port, not the LAN
	lea	$ff8c81,a0                      ; SCC A control, channel A's control
	bsr.w	scc_reset                       ; the SCC reset
	lea	test_errors.w,a0                ; the results
	moveq	#10,d7                          ; 11 bytes
scc_test_clear_results:
	clr.b	(a0)+                           ; cleared
	dbra	d7,scc_test_clear_results
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bsr.w	scc_init_channel                ; set up
	lea	$ff8c85,a0                      ; SCC B control, channel B
	bsr.w	scc_init_channel                ; set up
	lea	$ff8c81,a0                      ; SCC A control, channel A
	move.b	#$e,(a0)                        ; WR14
	move.b	#$13,(a0)                       ; local loopback, the baud rate generator on
	bsr.w	scc_loopback                    ; 256 bytes looped back
	move.b	#$e,(a0)                        ; WR14
	move.b	#$3,(a0)                        ; no loopback
	move.b	d6,test_errors.w                ; the result
	beq.s	scc_test_b_loopback             ; good
	lea	msg_scc_a_internal_loopback,a5  ; "SCC A internal loopback: "
	bsr.w	print_string                    ; printed
	move.b	test_errors.w,d0                ; the error bits
	lea	scc_error_messages,a0           ; the error texts
	bsr.w	print_error_bits                ; printed
scc_test_b_loopback:
	lea	$ff8c85,a0                      ; SCC B control, channel B
	move.b	#$e,(a0)                        ; WR14
	move.b	#$13,(a0)                       ; local loopback, the baud rate generator on
	bsr.w	scc_loopback                    ; 256 bytes looped back
	move.b	#$e,(a0)                        ; WR14
	move.b	#$3,(a0)                        ; no loopback
	move.b	d6,test_errors_high.w           ; the result
	beq.s	scc_test_a_connector            ; good
	lea	msg_scc_b_internal_loopback,a5  ; "SCC B internal loopback: "
	bsr.w	print_string                    ; printed
	move.b	test_errors_high.w,d0           ; the error bits
	lea	scc_error_messages,a0           ; the error texts
	bsr.w	print_error_bits                ; printed
scc_test_a_connector:
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bsr.w	scc_set_break_mode              ; sending a break
	bsr.w	scc_check_break                 ; does it come back?
	move.b	d6,test_errors_extra.w          ; 1: no plug
	beq.s	scc_test_b_connector            ; a plug
	lea	msg_port_a_no_loopback,a5       ; "Port A has no loopback connector"
	bsr.w	print_string                    ; printed
scc_test_b_connector:
	lea	$ff8c85,a0                      ; SCC B control, channel B
	bsr.w	scc_set_break_mode              ; sending a break
	bsr.w	scc_check_break                 ; does it come back?
	move.b	d6,test_errors_last.w           ; 1: no plug
	beq.s	scc_test_lan                    ; a plug
	lea	msg_port_b_no_loopback,a5       ; "Port B has no loopback connector"
	bsr.w	print_string                    ; printed
scc_test_lan:
	bsr.w	scc_select_lan                  ; channel A to the LAN
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bsr.w	scc_set_async_mode              ; async, DTR and RTS on
	bsr.w	scc_loopback                    ; 256 bytes looped back
	move.b	d6,test_errors.w                ; the result
	beq.s	scc_test_lan_lines              ; good
	lea	msg_lan_no_loopback,a5          ; "LAN has no loopback connector"
	bsr.w	print_string                    ; printed
	bra.s	scc_test_a_async                ; the lines skipped
scc_test_lan_lines:
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bsr.w	scc_lan_lines                   ; DCD must follow DTR
scc_test_a_async:
	bsr.w	scc_select_serial               ; channel A to the serial port
	cmpi.b	#$1,test_errors_extra.w         ; port A plugged?
	beq.s	scc_test_b_async                ; no
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bsr.w	scc_set_async_mode              ; async, DTR and RTS on
	bsr.w	scc_loopback                    ; 256 bytes through the plug
	move.b	d6,scc_a_async_errors.w         ; the result
	beq.s	scc_test_b_async                ; good
	lea	msg_port_a_async_mode,a5        ; "Port A async mode: "
	bsr.w	print_string                    ; printed
	lea	scc_error_messages,a0           ; the error texts
	move.b	scc_a_async_errors.w,d0         ; the error bits
	bsr.w	print_error_bits                ; printed
scc_test_b_async:
	cmpi.b	#$1,test_errors_last.w          ; port B plugged?
	beq.s	scc_test_a_modem                ; no
	lea	$ff8c85,a0                      ; SCC B control, channel B
	bsr.w	scc_set_async_mode              ; async, DTR and RTS on
	bsr.w	scc_loopback                    ; 256 bytes through the plug
	move.b	d6,scc_b_async_errors.w         ; the result
	beq.s	scc_test_a_modem                ; good
	lea	msg_port_b_async_mode,a5        ; "Port B async mode: "
	bsr.w	print_string                    ; printed
	move.b	scc_b_async_errors.w,d0         ; the error bits
	lea	scc_error_messages,a0           ; the error texts
	bsr.w	print_error_bits                ; printed
scc_test_a_modem:
	cmpi.b	#$1,test_errors_extra.w         ; port A plugged?
	beq.s	scc_test_b_modem                ; no
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bsr.w	scc_set_async_mode              ; async, DTR and RTS on
	bsr.w	scc_modem_lines                 ; the modem lines
	move.b	d6,scc_a_modem_errors.w         ; the result
	beq.s	scc_test_b_modem                ; good
	lea	msg_port_a_modem_control_error,a5 ; "Port A modem control error: "
	bsr.w	print_string                    ; printed
	move.b	d6,d0                           ; the error bits
	lea	scc_modem_error_messages,a0     ; the line names
	bsr.w	print_error_bits                ; printed
	bsr.w	print_newline                   ; a new line
scc_test_b_modem:
	cmpi.b	#$1,test_errors_last.w          ; port B plugged?
	beq.s	scc_test_interrupts             ; no
	lea	$ff8c85,a0                      ; SCC B control, channel B
	bsr.w	scc_set_async_mode              ; async, DTR and RTS on
	bsr.w	scc_modem_lines                 ; the modem lines
	move.b	d6,scc_b_modem_errors.w         ; the result
	beq.s	scc_test_interrupts             ; good
	lea	msg_port_b_modem_control_error,a5 ; "Port B modem control error: "
	bsr.w	print_string                    ; printed
	move.b	d6,d0                           ; the error bits
	lea	scc_modem_error_messages,a0     ; the line names
	bsr.w	print_error_bits                ; printed
	bsr.w	print_newline                   ; a new line
scc_test_interrupts:
	lea	$ff8c81,a0                      ; SCC A control, channel A
	move.b	#$2,(a0)                        ; WR2
	move.b	#$60,(a0)                       ; the vector $60 ($180)
	lea	scc_vectors,a0                  ; the interrupt routines
	lea	$180.w,a1                       ; their vectors
	move.w	#$7,d7                          ; 8 (status in bits 3-1: 8 bytes apart)
scc_test_vectors:
	move.l	(a0),(a1)                       ; put in
	adda.l	#$4,a0                          ; the next routine
	adda.l	#$8,a1                          ; the next vector
	dbra	d7,scc_test_vectors             ; each
	bset	#$5,$ff8e0d                     ; SCU VME interrupt mask, the SCU passes the SCC's level 5
	bsr.w	scc_fill_tx_buffer              ; the transmit buffer filled
	cmpi.b	#$1,test_errors_extra.w         ; port A plugged?
	beq.s	scc_test_b_interrupts           ; no
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bsr.w	scc_set_async_mode              ; async, DTR and RTS on
	bsr.w	scc_interrupt_test              ; 512 bytes by interrupt
	move.b	d6,scc_a_interrupt_errors.w     ; the result
	move.b	d6,d0                           ; the error bits
	beq.s	scc_test_b_interrupts           ; good
	lea	msg_scc_interrupt_error,a5      ; "SCC interrupt error:"
	bsr.w	print_string                    ; printed
	lea	scc_error_messages,a0           ; the error texts
	bsr.w	print_error_bits                ; printed
scc_test_b_interrupts:
	cmpi.b	#$1,test_errors_last.w          ; port B plugged?
	beq.s	scc_test_result                 ; no
	lea	$ff8c85,a0                      ; SCC B control, channel B
	bsr.w	scc_set_async_mode              ; async, DTR and RTS on
	bsr.w	scc_interrupt_test              ; 512 bytes by interrupt
	move.b	d6,scc_b_interrupt_errors.w     ; the result
	move.b	d6,d0                           ; the error bits
	beq.s	scc_test_result                 ; good
	lea	msg_scc_interrupt_error,a5      ; "SCC interrupt error:"
	bsr.w	print_string                    ; printed
	lea	scc_error_messages,a0           ; the error texts
	bsr.w	print_error_bits                ; printed
scc_test_result:
	move.b	test_errors.w,d0                ; every result together
	or.b	test_errors_high.w,d0
	or.b	test_errors_extra.w,d0
	or.b	test_errors_last.w,d0
	or.b	scc_a_async_errors.w,d0
	or.b	scc_b_async_errors.w,d0
	or.b	scc_a_modem_errors.w,d0
	or.b	scc_b_modem_errors.w,d0
	or.b	scc_a_interrupt_errors.w,d0
	or.b	scc_b_interrupt_errors.w,d0
	beq.s	scc_test_pass                   ; all good
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bsr.w	show_result                     ; the result printed
	bra.s	scc_test_done                   ; done
scc_test_pass:
	movea.l	#msg_pass,a5                    ; "Pass"
	bsr.w	show_result                     ; the result printed
scc_test_done:
	rts

;------------------------------------------------------------------------------
; scc_check_break: d6 = 0 when RR0 shows a break (the channel's break comes back through a loopback plug)
; within 65536 polls, else 1.  Changes d0, d7.
;------------------------------------------------------------------------------
scc_check_break:	; from: scc_test
	clr.b	d6                              ; a plug (until shown otherwise)
	moveq	#-1,d7                          ; 65536 polls
scc_check_break_poll:
	move.b	#$0,(a0)                        ; RR0
	move.b	(a0),d0                         ; read
	btst	#$7,d0                          ; break/abort?
	bne.s	scc_check_break_done            ; yes
	dbra	d7,scc_check_break_poll         ; again
	move.b	#$1,d6                          ; none: no plug
scc_check_break_done:
	rts

;------------------------------------------------------------------------------
; scc_loopback: the bytes 0-255 sent and received on the channel at a0.  d6 the errors: bit 0 the
; transmitter never empty, 1 nothing received, 4-6 RR1's parity, overrun and framing errors, 7 a byte
; received wrong.  Changes d0, d1, d7.
;------------------------------------------------------------------------------
scc_loopback:	; from: scc_test
	moveq	#0,d6                           ; no errors
	moveq	#0,d1                           ; the first byte
	bsr.w	scc_flush_rx                    ; the receiver emptied
	move.b	#$0,(a0)                        ; WR0
	move.b	#$30,(a0)                       ; error reset
scc_loopback_byte:
	move.b	d1,2(a0)                        ; sent
	moveq	#-1,d7                          ; 65536 polls
scc_loopback_tx_wait:
	move.b	#$0,(a0)                        ; RR0
	move.b	(a0),d0                         ; read
	btst	#$2,d0                          ; the transmit buffer empty?
	bne.s	scc_loopback_rx                 ; yes
	dbra	d7,scc_loopback_tx_wait         ; again
	ori.b	#$1,d6                          ; never: bit 0
	bra.s	scc_loopback_end                ; the end
scc_loopback_rx:
	move.l	#$ffffff,d7                     ; 65536 polls (dbra counts the low word)
scc_loopback_rx_wait:
	move.b	(a0),d0                         ; RR0
	btst	#$0,d0                          ; a byte received?
	bne.s	scc_loopback_got                ; yes
	dbra	d7,scc_loopback_rx_wait         ; again
	ori.b	#$2,d6                          ; never: bit 1
	bra.s	scc_loopback_end                ; the end
scc_loopback_got:
	move.b	#$1,(a0)                        ; RR1
	move.b	(a0),d0                         ; read
	andi.b	#$70,d0                         ; the parity, overrun and framing errors
	or.b	d0,d6                           ; kept
	move.b	2(a0),d0                        ; the byte received
	cmp.b	d0,d1                           ; the one sent?
	beq.s	scc_loopback_next               ; yes
	ori.b	#$80,d6                         ; no: bit 7
scc_loopback_next:
	addi.b	#$1,d1                          ; the next byte
	bne.s	scc_loopback_byte               ; to 255
scc_loopback_end:
	move.b	#$0,(a0)                        ; WR0
	move.b	#$30,(a0)                       ; error reset
	rts

;------------------------------------------------------------------------------
; scc_flush_rx: every byte waiting in the channel's receiver read and dropped.  Changes d0.
;------------------------------------------------------------------------------
scc_flush_rx:	; from: scc_loopback, scc_interrupt_test
	move.b	#$0,(a0)                        ; RR0
	move.b	(a0),d0                         ; read
	btst	#$0,d0                          ; a byte waiting?
	beq.s	scc_flush_rx_done               ; no
	move.b	2(a0),d0                        ; read
	bra.s	scc_flush_rx                    ; again
scc_flush_rx_done:
	rts

;------------------------------------------------------------------------------
; scc_modem_lines: the handshake lines through the loopback plug: with DTR and RTS off DCD, SYNC and CTS
; must be off; DTR on must turn on DCD and SYNC; RTS on must turn on CTS.  d6 the lines wrong:
; bit 0 DCD, 1 SYNC, 2 CTS.  Changes d0, d7.
;------------------------------------------------------------------------------
scc_modem_lines:	; from: scc_test
	moveq	#0,d6                           ; no errors
	move.b	#$5,(a0)                        ; WR5
	move.b	#$68,(a0)                       ; DTR and RTS off, the transmitter on
	bsr.w	scc_delay                       ; a pause
	move.b	#$0,(a0)                        ; RR0
	move.b	(a0),d0                         ; read
	andi.b	#$38,d0                         ; DCD, SYNC, CTS
	beq.s	scc_modem_lines_dtr             ; all off: good
	or.b	d0,d6                           ; on: wrong
scc_modem_lines_dtr:
	move.b	#$5,(a0)                        ; WR5
	move.b	#$e8,(a0)                       ; DTR on
	bsr.w	scc_delay                       ; a pause
	move.b	#$0,(a0)                        ; RR0
	move.b	(a0),d0                         ; read
	andi.b	#$38,d0                         ; DCD, SYNC, CTS
	eori.b	#$18,d0                         ; DCD and SYNC must be on
	or.b	d0,d6                           ; those wrong
	move.b	#$5,(a0)                        ; WR5
	move.b	#$6a,(a0)                       ; RTS on, DTR off
	bsr.w	scc_delay                       ; a pause
	move.b	#$0,(a0)                        ; RR0
	move.b	(a0),d0                         ; read
	andi.b	#$38,d0                         ; DCD, SYNC, CTS
	eori.b	#$20,d0                         ; CTS only must be on
	or.b	d0,d6                           ; those wrong
	lsr.b	#3,d6                           ; to bits 0-2
	rts

;------------------------------------------------------------------------------
; scc_delay: a pause of 65536 dbra rounds.  Changes d7.
;------------------------------------------------------------------------------
scc_delay:	; from: scc_modem_lines, scc_lan_lines, scc_interrupt_test
	move.w	#$ffff,d7
scc_delay_loop:
	dbra	d7,scc_delay_loop
	rts

;------------------------------------------------------------------------------
; scc_lan_lines: the LAN's lines through its loopback plug: with DTR off DCD must be off ("LAN ERROR: DCD
; IS ACTIVE WITHOUT RTS ON", $676 = 8), with DTR on it must be on ("LAN ERROR: RTS IS ACTIVE BUT DCD IS
; NOT RESPONDING", $676 bit 0).  Changes d0, d6, d7.
;------------------------------------------------------------------------------
scc_lan_lines:	; from: scc_test
	moveq	#0,d6                           ; no errors
	move.b	#$5,(a0)                        ; WR5
	move.b	#$68,(a0)                       ; DTR and RTS off, the transmitter on
	bsr.s	scc_delay                       ; a pause
	move.b	#$0,(a0)                        ; RR0
	move.b	(a0),d0                         ; read
	andi.b	#$8,d0                          ; DCD?
	beq.s	scc_lan_lines_on                ; off: good
	move.b	d0,test_errors.w                ; on: wrong
	lea	msg_lan_dcd_without_rts,a5      ; "LAN ERROR: DCD IS ACTIVE WITHOUT RTS ON"
	bsr.w	print_string                    ; printed
scc_lan_lines_on:
	move.b	#$5,(a0)                        ; WR5
	move.b	#$e8,(a0)                       ; DTR on
	bsr.s	scc_delay                       ; a pause
	move.b	#$0,(a0)                        ; RR0
	move.b	(a0),d0                         ; read
	andi.b	#$8,d0                          ; DCD?
	bne.s	scc_lan_lines_done              ; on: good
	ori.b	#$1,test_errors.w               ; off: wrong
	lea	msg_lan_dcd_not_responding,a5   ; "LAN ERROR: RTS IS ACTIVE BUT DCD IS NOT RESPONDING"
	bsr.w	print_string                    ; printed
scc_lan_lines_done:
	rts

;------------------------------------------------------------------------------
; scc_interrupt_test: 512 bytes from $686 sent and received at $896 by the SCC's interrupts (scc_..._int,
; pointers $A96 and $A9A).  d6: 1 not all sent (or the receive errors from $680), 2 not all received, $80
; a byte wrong; "No Tx interrupt" / "No Rx interrupt" when none came.  The compare counts the word at $200,
; not $200.  Changes d0, d7, a1, a2.
;------------------------------------------------------------------------------
scc_interrupt_test:	; from: scc_test
	moveq	#0,d6                           ; no errors
	move.b	d6,scc_tx_int_seen.w            ; no Tx interrupt yet
	move.b	d6,scc_rx_int_seen.w            ; no Rx interrupt yet
	bsr.w	scc_flush_rx                    ; the receiver emptied
	move.l	#$687,scc_tx_pointer.w          ; the next byte to send: the second
	move.l	#$896,scc_rx_pointer.w          ; the receive buffer
	clr.b	scc_rx_int_errors.w             ; no receive errors
	move.b	#$f,(a0)                        ; WR15
	move.b	#$0,(a0)                        ; no external interrupts
	move.b	#$0,(a0)                        ; WR0
	move.b	#$10,(a0)                       ; reset the external/status interrupts
	move.b	#$0,(a0)                        ; WR0
	move.b	#$10,(a0)                       ; again
	move.b	#$1,(a0)                        ; WR1
	move.b	#$13,(a0)                       ; interrupts on: Rx on every byte, Tx, external
	move.b	#$9,(a0)                        ; WR9
	move.b	#$9,(a0)                        ; the master enable, the status in the vector
	lea	scc_tx_buffer.w,a1              ; the buffer
	move.b	(a1)+,2(a0)                     ; the first byte sent; the interrupts send the rest
scc_interrupt_test_wait:
	move.l	scc_tx_pointer.w,scratch_long.w ; where sending is
	bsr.w	scc_delay                       ; a pause
	move.l	scratch_long.w,d0               ; where it was
	cmp.l	scc_tx_pointer.w,d0             ; still moving?
	bne.s	scc_interrupt_test_wait         ; yes: wait on
	cmpi.l	#$886,scratch_long.w            ; all sent?
	beq.s	scc_interrupt_test_stop         ; yes
	move.b	#$1,d6                          ; no: 1
	cmpi.b	#$0,scc_rx_int_errors.w         ; receive errors?
	beq.s	scc_interrupt_test_stop         ; no
	move.b	scc_rx_int_errors.w,d6          ; yes: those
scc_interrupt_test_stop:
	move.b	#$9,(a0)                        ; WR9
	move.b	#$1,(a0)                        ; the master enable off
	tst.b	d6                              ; an error yet?
	bne.s	scc_interrupt_test_tx_seen      ; yes
	move.l	scc_rx_pointer.w,d0             ; where receiving ended
	cmp.l	#$a96,d0                        ; all 512 in?
	beq.s	scc_interrupt_test_compare      ; yes
	or.b	#$2,d6                          ; no: 2
	bra.s	scc_interrupt_test_tx_seen      ; the end
scc_interrupt_test_compare:
	lea	scc_tx_buffer.w,a1              ; sent
	lea	scc_rx_buffer.w,a2              ; received
	move.w	last_fault_pc.w,d7              ; the count: the word at $200
scc_interrupt_test_byte:
	cmpm.b	(a1)+,(a2)+                     ; the same?
	beq.s	scc_interrupt_test_next         ; yes
	move.b	#$80,d6                         ; no: $80
scc_interrupt_test_next:
	dbra	d7,scc_interrupt_test_byte
scc_interrupt_test_tx_seen:
	cmpi.b	#$0,scc_tx_int_seen.w           ; a Tx interrupt?
	bne.s	scc_interrupt_test_rx_seen      ; yes
	lea	msg_no_tx_interrupt,a5          ; "No Tx interrupt"
	bsr.w	print_string                    ; printed
scc_interrupt_test_rx_seen:
	cmpi.b	#$0,scc_rx_int_seen.w           ; an Rx interrupt?
	bne.s	scc_interrupt_test_done         ; yes
	lea	msg_no_rx_interrupt,a5          ; "No Rx interrupt"
	bsr.w	print_string                    ; printed
scc_interrupt_test_done:
	rts

;------------------------------------------------------------------------------
; scc_fill_tx_buffer: the transmit buffer $686: 256 bytes $FF down to 0, then 256 bytes $E5.
; Changes d0, d1, a0.
;------------------------------------------------------------------------------
scc_fill_tx_buffer:	; from: scc_test
	lea	scc_tx_buffer.w,a0              ; the buffer
	move.w	#$ff,d0                         ; 256
scc_fill_tx_count:
	move.b	d0,(a0)+                        ; $FF, $FE, ... 0
	dbra	d0,scc_fill_tx_count
	move.w	#$ff,d0                         ; 256
	move.b	#$e5,d1                         ; $E5
scc_fill_tx_e5:
	move.b	d1,(a0)+
	dbra	d0,scc_fill_tx_e5
	rts

;------------------------------------------------------------------------------
; scc_clear_rx_buffer: (not called) the receive buffer $896 cleared (512 bytes).
;------------------------------------------------------------------------------
scc_clear_rx_buffer:
	lea	scc_rx_buffer.w,a0              ; the buffer
	clr.w	d0                              ; 0
	move.w	#$ff,d7                         ; 256 words
scc_clear_rx_word:
	move.w	d0,(a0)+
	dbra	d7,scc_clear_rx_word
	rts

;------------------------------------------------------------------------------
; scc_set_baud: (not called) the channel's baud rate time constant set to d2:d1 (the generator off meanwhile).
;------------------------------------------------------------------------------
scc_set_baud:
	move.b	#$e,(a0)                        ; WR14
	move.b	#$2,(a0)                        ; the generator off
	move.b	#$c,(a0)                        ; WR12
	move.b	d1,(a0)                         ; the low byte
	move.b	#$d,(a0)                        ; WR13
	move.b	d2,(a0)                         ; the high byte
	move.b	#$e,(a0)                        ; WR14
	move.b	#$3,(a0)                        ; the generator on
	rts

;------------------------------------------------------------------------------
; print_error_bits: for each bit set in d0 (0 to 7) the text from the pointer table at a0 printed.
; Changes d1, d2, a5.
;------------------------------------------------------------------------------
print_error_bits:	; from: scc_test
	moveq	#0,d1                           ; bit 0
	moveq	#0,d2                           ; the first pointer
print_error_bits_test:
	btst	d1,d0                           ; set?
	bne.s	print_error_bits_print          ; yes
print_error_bits_next:
	addq.w	#4,d2                           ; the next pointer
	addq.w	#1,d1                           ; the next bit
	cmp.b	#$8,d1                          ; all 8?
	bne.s	print_error_bits_test
	rts
print_error_bits_print:
	movea.l	0(a0,d2.w),a5                   ; its text
	move.l	a0,-(sp)                        ; kept
	bsr.w	print_string                    ; printed
	movea.l	(sp)+,a0                        ; back
	bra.s	print_error_bits_next

;------------------------------------------------------------------------------
; scc_a_tx_int, scc_b_tx_int: the transmit buffer empty: $683 set, the next byte from $A96 sent, or the
; transmit interrupt reset after the last ($886).  Then (scc_int_next) any other interrupt pending in RR3
; is served before the rte.
;------------------------------------------------------------------------------
scc_a_tx_int:	; from: scc_vectors
	movem.l	d0/a0-a1,-(sp)                  ; kept
scc_a_tx_more:
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bra.s	scc_tx_int
scc_b_tx_int:	; from: scc_vectors
	movem.l	d0/a0-a1,-(sp)                  ; kept
scc_b_tx_more:
	lea	$ff8c85,a0                      ; SCC B control, channel B
scc_tx_int:
	move.b	#$1,scc_tx_int_seen.w           ; a Tx interrupt came
	movea.l	scc_tx_pointer.w,a1             ; the next byte
	cmpa.l	#$886,a1                        ; all sent?
	bne.s	scc_tx_send                     ; no
	move.b	#$0,(a0)                        ; WR0
	move.b	#$28,(a0)                       ; the transmit interrupt reset
	bra.s	scc_int_next
scc_tx_send:
	move.b	(a1)+,2(a0)                     ; sent
	move.l	a1,scc_tx_pointer.w             ; the next
scc_int_next:	; from: scc_a_rx_int
	move.b	#$0,(a0)                        ; WR0
	move.b	#$38,(a0)                       ; the highest interrupt under service reset
	move.b	#$3,$ff8c81                     ; SCC A control, RR3 (channel A)
	move.b	$ff8c81,d0                      ; SCC A control, the interrupts pending
	btst	#$5,d0                          ; A received?
	bne.s	scc_a_rx_more                   ; yes
	btst	#$2,d0                          ; B received?
	bne.s	scc_b_rx_more                   ; yes
	btst	#$4,d0                          ; A transmit?
	bne.s	scc_a_tx_more                   ; yes
	btst	#$1,d0                          ; B transmit?
	bne.s	scc_b_tx_more                   ; yes
	movem.l	(sp)+,d0/a0-a1                  ; back
	rte

;------------------------------------------------------------------------------
; scc_a_rx_int, scc_b_rx_int: a byte received: $684 set, RR1's errors added to $680 (and reset), the byte
; stored at $A9A on.
;------------------------------------------------------------------------------
scc_a_rx_int:	; from: scc_vectors
	movem.l	d0/a0-a1,-(sp)                  ; kept
scc_a_rx_more:	; from: scc_a_tx_int
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bra.s	scc_rx_int
scc_b_rx_int:	; from: scc_vectors
	movem.l	d0/a0-a1,-(sp)                  ; kept
scc_b_rx_more:	; from: scc_a_tx_int
	lea	$ff8c85,a0                      ; SCC B control, channel B
scc_rx_int:
	move.b	#$1,scc_rx_int_seen.w           ; an Rx interrupt came
	move.b	#$1,(a0)                        ; RR1
	move.b	(a0),d0                         ; read
	andi.b	#$70,d0                         ; parity, overrun, framing
	beq.s	scc_rx_store                    ; none
	or.b	d0,scc_rx_int_errors.w          ; added
	move.b	#$0,(a0)                        ; WR0
	move.b	#$30,(a0)                       ; error reset
scc_rx_store:
	movea.l	scc_rx_pointer.w,a1             ; the receive place
	move.b	#$8,(a0)                        ; RR8
	move.b	(a0),d0                         ; the byte
	move.b	d0,(a1)+                        ; stored
	move.l	a1,scc_rx_pointer.w             ; the next place
	bra.s	scc_int_next                    ; anything else pending

;------------------------------------------------------------------------------
; scc_a_ext_int, scc_b_ext_int: an external/status interrupt: $681 set, the interrupt reset.
;------------------------------------------------------------------------------
scc_a_ext_int:	; from: scc_vectors
	move.l	a0,-(sp)                        ; kept
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bra.s	scc_ext_int
scc_b_ext_int:	; from: scc_vectors
	move.l	a0,-(sp)                        ; kept
	lea	$ff8c85,a0                      ; SCC B control, channel B
scc_ext_int:	; from: scc_a_ext_int_spare
	move.b	#$1,scc_ext_int_seen.w          ; one came
	move.b	#$0,(a0)                        ; WR0
	move.b	#$10,(a0)                       ; the external/status interrupts reset
	move.b	#$0,(a0)                        ; WR0
	move.b	#$38,(a0)                       ; the highest interrupt under service reset
	movea.l	(sp)+,a0                        ; back
	rte

;------------------------------------------------------------------------------
; (not reached) as scc_a_ext_int.
;------------------------------------------------------------------------------
scc_a_ext_int_spare:
	move.l	a0,-(sp)                        ; kept
	lea	$ff8c81,a0                      ; SCC A control, channel A
	bra.s	scc_ext_int

;------------------------------------------------------------------------------
; scc_special_int: a special receive condition (the vector for both channels, but it reads channel B):
; the byte read into $682, RR1 read, the errors and the interrupt reset.
;------------------------------------------------------------------------------
scc_special_int:	; from: scc_vectors
	move.l	a0,-(sp)                        ; kept
	lea	$ff8c85,a0                      ; SCC B control, channel B
	move.b	#$8,(a0)                        ; RR8
	move.b	(a0),d0                         ; the byte
	move.b	d0,scc_special_byte.w           ; kept
	move.b	#$1,(a0)                        ; RR1
	move.b	(a0),d0                         ; read
	move.b	#$0,(a0)                        ; WR0
	move.b	#$30,(a0)                       ; error reset
	move.b	#$0,(a0)                        ; WR0
	move.b	#$38,(a0)                       ; the highest interrupt under service reset
	movea.l	(sp)+,a0                        ; back
	rte

;------------------------------------------------------------------------------
; scc_init_channel: the channel at a0 reset (WR9) and set up from its register list: 16x
; clock, 1 stop bit, 8 bits, the baud rate generator (time constant $18), receiver and transmitter on.
;------------------------------------------------------------------------------
scc_init_channel:	; from: scc_test
	movem.l	d0-d1,-(sp)                     ; kept
	cmpa.w	#$8c81,a0                       ; channel A?
	beq.s	scc_init_channel_a              ; yes
	move.b	#$9,(a0)                        ; WR9
	move.b	#$40,(a0)                       ; channel B reset
	bra.s	scc_init_channel_table          ; the registers
scc_init_channel_a:
	move.b	#$9,(a0)                        ; WR9
	move.b	#$80,(a0)                       ; channel A reset
scc_init_channel_table:
	lea	scc_setup_loopback,a1           ; 13 register and value pairs
	move.w	#$19,d0                         ; 26 bytes
scc_init_channel_reg:
	move.b	(a1)+,d1                        ; a byte
	move.b	d1,(a0)                         ; to the control port
	dbra	d0,scc_init_channel_reg         ; each
	movem.l	(sp)+,d0-d1                     ; back
	rts

;------------------------------------------------------------------------------
; scc_set_break_mode: the SCC reset, the channel set up as scc_init_channel but sending a break.
;------------------------------------------------------------------------------
scc_set_break_mode:	; from: scc_test
	movem.l	d0-d1,-(sp)                     ; kept
	bsr.w	scc_reset                       ; the SCC reset
	lea	scc_setup_break,a1              ; the register list with a break
	move.w	#$19,d0                         ; 26 bytes
scc_set_break_mode_reg:
	move.b	(a1)+,d1                        ; a byte
	move.b	d1,(a0)                         ; to the control port
	dbra	d0,scc_set_break_mode_reg       ; each
	movem.l	(sp)+,d0-d1                     ; back
	rts

;------------------------------------------------------------------------------
; scc_set_async_mode: the SCC reset, the channel set up as scc_init_channel with DTR and RTS on.
;------------------------------------------------------------------------------
scc_set_async_mode:	; from: scc_test
	movem.l	d0-d1,-(sp)                     ; kept
	bsr.w	scc_reset                       ; the SCC reset
	lea	scc_setup_async,a1              ; the register list with DTR and RTS
	move.w	#$19,d0                         ; 26 bytes
scc_set_async_mode_reg:
	move.b	(a1)+,d1                        ; a byte
	move.b	d1,(a0)                         ; to the control port
	dbra	d0,scc_set_async_mode_reg       ; each
	movem.l	(sp)+,d0-d1                     ; back
	rts

;------------------------------------------------------------------------------
; scc_reset: a hardware reset of the whole SCC (WR9 $C0) and a pause.  Changes d2.
;------------------------------------------------------------------------------
scc_reset:	; from: scc_test, scc_set_break_mode, scc_set_async_mode
	move.b	#$9,(a0)                        ; WR9
	move.b	#$c0,(a0)                       ; the hardware reset
	move.w	#$ffff,d2                       ; 65536 rounds
scc_reset_delay:
	dbra	d2,scc_reset_delay
	rts

;------------------------------------------------------------------------------
; scc_select_serial: PSG port A bit 7 set: SCC channel A to the serial port (not the LAN).  Changes d0.
;------------------------------------------------------------------------------
scc_select_serial:	; from: scc_test
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	$ffff8800.w,d0                  ; PSG register select, its bits
	bset	#$7,d0                          ; the serial port
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	d0,$ffff8802.w                  ; PSG write data, written
	rts

;------------------------------------------------------------------------------
; scc_select_lan: PSG port A bit 7 cleared: SCC channel A to the LAN.  Changes d0.
;------------------------------------------------------------------------------
scc_select_lan:	; from: scc_test
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	$ffff8800.w,d0                  ; PSG register select, its bits
	bclr	#$7,d0                          ; the LAN
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	d0,$ffff8802.w                  ; PSG write data, written
	rts

;------------------------------------------------------------------------------
; vme_test: V.  With a VME RAM board (found at start, $234): "VME RAM test", $AF0000-$BF0000 tested by the
; RAM test's patterns with the "testing" blink in the VBL, the errors listed, "Pass" or "Fail at cycle:".
; Without one, the VME interrupt test (vme_interrupt_test).
;------------------------------------------------------------------------------
vme_test:	; from: test_routines
	move.b	vme_ram_found.w,d0              ; a VME RAM board?
	beq.w	vme_interrupt_test              ; no: the interrupt test
	lea	msg_vme_ram_test,a5             ; "VME RAM test"
	bsr.w	show_status                     ; in the top line
	lea	ram_test_vbl,a0                 ; the blinking VBL
	move.l	a0,$70.w                        ; VBL vector, put in
	move.w	#$1e,star_countdown.w           ; every 30 VBLs
	clr.b	star_inverse.w                  ; the blink state
	move.w	#$2200,sr                       ; VBLs on
	movea.l	#$af0000,a0                     ; from $AF0000
	movea.l	#$bf0000,a1                     ; to $BF0000
	clr.w	test_errors.w                   ; no errors
	movea.l	#$538,a4                        ; the error list
	movea.l	#$600,a6                        ; its end
	bsr.w	test_alternating_patterns       ; the patterns written and checked
	move.l	#vbl_handler,$70.w              ; VBL vector, the plain VBL
	bsr.w	print_ram_errors                ; the errors listed
	lea	msg_pass,a5                     ; "Pass"
	tst.b	test_errors.w                   ; errors?
	beq.s	vme_test_result                 ; no
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
vme_test_result:
	bsr.w	show_result                     ; the result printed
	move.w	#$2400,sr                       ; VBLs off
	rts

;------------------------------------------------------------------------------
; vme_interrupt_test: "Generate VMEbus Interrupts using a Xycom SCC Card": the card's two SCCs ($DF0001-
; $DF000F) set up, vectors $300-$33C taken over, channel A of the first SCC in local loopback sends $2000
; bytes, which must give $2000 receive interrupts at VME level 6 and no others (the counts at $C9A
; against the table of expected counts); wrong counts are printed in hex.  "No VME board found in
; system" when $DF000D takes a bus error.
;------------------------------------------------------------------------------
vme_interrupt_test:	; from: vme_test
	movea.l	sp,a6                           ; the stack kept
	move.l	#vme_no_board,$8.w              ; bus error vector, a bus error: no board
	move.b	$df000d,d0                      ; the card's first SCC, channel A control
	bra.s	vme_board_found                 ; there
vme_no_board:
	movea.l	a6,sp                           ; the stack back
	move.l	#bus_error_handler,$8.w         ; bus error vector, the normal bus error routine
	lea	msg_no_vme_board,a5             ; "No VME board found in system"
	bsr.w	print_string                    ; printed
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	rts
vme_board_found:
	lea	msg_vme_interrupts,a5           ; "Generate VMEbus Interrupts using a Xycom SCC Card"
	bsr.w	print_string                    ; printed
	move.b	$df000d,d0                      ; the first SCC's register pointer reset
	nop
	nop
	move.b	#$9,$df000d                     ; WR9
	nop
	nop
	move.b	#$c0,$df000d                    ; the hardware reset
	move.b	$df0005,d0                      ; the second SCC
	nop
	nop
	move.b	#$9,$df0005                     ; WR9
	nop
	nop
	move.b	#$c0,$df0005                    ; the hardware reset
	lea	vme_scc_setup,a0                ; the register list
	movea.l	#$df000d,a1                     ; the first SCC, channel A
	move.w	#$27,d0                         ; 40 bytes
vme_init_first_a:
	move.b	(a0)+,(a1)                      ; each
	dbra	d0,vme_init_first_a
	lea	vme_scc_setup,a0                ; the register list
	movea.l	#$df0009,a1                     ; the first SCC, channel B
	move.w	#$27,d0                         ; 40 bytes
vme_init_first_b:
	move.b	(a0)+,(a1)                      ; each
	dbra	d0,vme_init_first_b
	lea	vme_scc_setup,a0                ; the register list
	movea.l	#$df0005,a1                     ; the second SCC, channel A
	move.w	#$27,d0                         ; 40 bytes
vme_init_second_a:
	move.b	(a0)+,(a1)                      ; each
	dbra	d0,vme_init_second_a
	lea	vme_scc_setup,a0                ; the register list
	movea.l	#$df0001,a1                     ; the second SCC, channel B
	move.w	#$27,d0                         ; 40 bytes
vme_init_second_b:
	move.b	(a0)+,(a1)                      ; each
	dbra	d0,vme_init_second_b
	move.w	#$7,d4                          ; 8 vectors
	lea	vme_saved_vectors.w,a3          ; kept here
	lea	vme_scc_vectors,a4              ; the counting routines
	lea	$300.w,a1                       ; the vectors for $C0 ($300 on, 8 bytes apart)
vme_set_vectors:
	move.l	(a1),(a3)+                      ; kept
	move.l	(a4)+,(a1)+                     ; the counting routine
	adda.l	#$4,a1                          ; the next vector
	dbra	d4,vme_set_vectors              ; each
	move.b	#$e,$df000d                     ; WR14
	nop
	nop
	move.b	#$2,$df000d                     ; the generator from the clock
	nop
	nop
	move.b	#$3,$df000d                     ; WR3
	nop
	nop
	move.b	#$c0,$df000d                    ; 8 bits, the receiver off
	nop
	nop
	move.b	#$5,$df000d                     ; WR5
	nop
	nop
	move.b	#$e2,$df000d                    ; DTR, 8 bits, RTS
	nop
	nop
	move.b	#$e,$df000d                     ; WR14
	nop
	nop
	move.b	#$12,$df000d                    ; local loopback
	nop
	nop
	move.b	#$e,$df000d                     ; WR14
	nop
	nop
	move.b	#$13,$df000d                    ; local loopback, the generator on
	nop
	nop
	move.b	#$3,$df000d                     ; WR3
	nop
	nop
	move.b	#$c1,$df000d                    ; the receiver on
	nop
	nop
	move.b	#$5,$df000d                     ; WR5
	nop
	nop
	move.b	#$ea,$df000d                    ; the transmitter on
	nop
	nop
	move.b	#$2,$df000d                     ; WR2
	nop
	nop
	move.b	#$c0,$df000d                    ; the vector $C0
	nop
	nop
	move.b	#$1,$df000d                     ; WR1
	nop
	nop
	move.b	#$10,$df000d                    ; an interrupt on every byte received
	nop
	nop
	move.b	#$f,$df000d                     ; WR15
	nop
	nop
	move.b	#$b8,$df000d                    ; break, CTS, SYNC and DCD interrupts
	nop
	nop
	move.b	#$9,$df000d                     ; WR9
	nop
	nop
	move.b	#$9,$df000d                     ; the master enable, the status in the vector
	nop
	nop
	move.b	$ffff8e0d.w,vme_saved_scu_mask.w ; SCU VME interrupt mask, the SCU's VME interrupt mask kept
	bset	#$6,$ffff8e0d.w                 ; SCU VME interrupt mask, level 6 passed
	move.w	sr,vme_saved_sr.w               ; the interrupt mask kept
	move.w	#$2100,sr                       ; level 2 and up
	move.w	#$7,d0                          ; 8 counts
	lea	vme_int_counts.w,a0             ; the counts
vme_clear_counts:
	clr.l	(a0)+                           ; cleared
	dbra	d0,vme_clear_counts
	move.w	#$1fff,d3                       ; $2000 bytes
vme_send_byte:
	btst	#$2,$df000d                     ; the transmit buffer empty?
	beq.s	vme_send_byte                   ; no: wait
	move.b	d3,$df000f                      ; the byte sent
	dbra	d3,vme_send_byte                ; each
	jsr	delay                           ; a moment for the last
	move.w	#$7,d3                          ; 8 counts
	lea	vme_int_counts.w,a3             ; the counts
	lea	vme_interrupt_counts_expected,a4 ; those expected
vme_check_count:
	move.l	(a3)+,d5                        ; a count
	cmp.l	(a4)+,d5                        ; as expected?
	bne.s	vme_counts_wrong                ; no
	dbra	d3,vme_check_count              ; each
	bra.s	vme_counts_right                ; all right
vme_counts_wrong:
	bsr.w	print_newline                   ; a new line
	move.w	#$7,d3                          ; 8 counts
	lea	vme_int_counts.w,a3             ; the counts
vme_print_count:
	move.l	(a3)+,d5                        ; a count
	bsr.w	vme_print_long                  ; in hex
	move.w	#$20,d1                         ; a space
	bsr.w	put_char                        ; printed
	dbra	d3,vme_print_count              ; each
	bsr.w	print_newline                   ; a new line
	move.w	#$500,$ffff8240.w               ; palette 0, the screen red
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bsr.w	show_result                     ; the result printed
	bra.s	vme_reset_scc                   ; the card reset
vme_counts_right:
	bsr.w	print_newline                   ; a new line
	movea.l	#msg_pass,a5                    ; "Pass"
	bsr.w	show_result                     ; the result printed
vme_reset_scc:
	move.b	#$9,$df000d                     ; WR9
	nop
	nop
	move.b	#$0,$df000d                     ; no interrupts
	nop
	nop
	move.b	#$1,$df000d                     ; WR1
	nop
	nop
	move.b	#$0,$df000d                     ; none
	nop
	nop
	move.b	#$f,$df000d                     ; WR15
	nop
	nop
	move.b	#$0,$df000d                     ; none
	nop
	nop
	move.b	#$e,$df000d                     ; WR14
	nop
	nop
	move.b	#$12,$df000d                    ; local loopback
	nop
	nop
	move.b	#$e,$df000d                     ; WR14
	nop
	nop
	move.b	#$2,$df000d                     ; the loopback off
	nop
	nop
	move.b	#$e,$df000d                     ; WR14
	nop
	nop
	move.b	#$3,$df000d                     ; the generator on
	nop
	nop
	move.b	vme_saved_scu_mask.w,$ffff8e0d.w ; SCU VME interrupt mask, the SCU's mask back
	move.w	vme_saved_sr.w,sr               ; the interrupt mask back
	move.w	#$7,d4                          ; 8 vectors
	movea.l	#$c72,a3                        ; those kept
	lea	$300.w,a1                       ; from $300
vme_restore_vectors:
	move.l	(a3)+,(a1)+                     ; back
	adda.l	#$4,a1                          ; the next vector
	dbra	d4,vme_restore_vectors          ; each
	rts

;------------------------------------------------------------------------------
; The Xycom card's interrupt routines (the first SCC, vector $C0 with the status): each counts its kind
; in $C9A-$CB6 (channel B transmit, external, receive, special; channel A the same), clears the cause and
; resets the interrupt under service before the rte.
;------------------------------------------------------------------------------
vme_b_tx_int:	; from: vme_scc_vectors
	addq.l	#1,vme_int_counts.w             ; B transmit counted
	move.b	#$28,$df0009                    ; the transmit interrupt reset
	bra.w	vme_int_exit                    ; done
vme_b_ext_int:	; from: vme_scc_vectors
	addq.l	#1,$c9e.w                       ; B external/status counted
	move.b	#$10,$df0009                    ; the external/status interrupts reset
	bra.w	vme_int_exit                    ; done
vme_b_special_int:	; from: vme_scc_vectors
	addq.l	#1,$ca6.w                       ; B special receive counted
	bra.s	vme_b_rx_read                   ; the byte read
vme_b_rx_int:	; from: vme_scc_vectors
	addq.l	#1,$ca2.w                       ; B received counted
vme_b_rx_read:
	move.w	d0,-(sp)                        ; kept
	move.b	#$1,$df0009                     ; RR1
	move.b	$df0009,d0                      ; the errors
	andi.b	#$70,d0                         ; parity, overrun, framing
	beq.s	vme_b_rx_data                   ; none
	move.b	#$30,$df0009                    ; error reset
vme_b_rx_data:
	tst.b	$df000b                         ; the byte read
	move.w	(sp)+,d0                        ; back
	bra.s	vme_int_exit                    ; done
vme_a_tx_int:	; from: vme_scc_vectors
	addq.l	#1,$caa.w                       ; A transmit counted
	move.b	#$28,$df000d                    ; the transmit interrupt reset
	bra.s	vme_int_exit                    ; done
vme_a_ext_int:	; from: vme_scc_vectors
	addq.l	#1,$cae.w                       ; A external/status counted
	move.b	#$10,$df000d                    ; the external/status interrupts reset
	bra.s	vme_int_exit                    ; done
vme_a_special_int:	; from: vme_scc_vectors
	addq.l	#1,$cb6.w                       ; A special receive counted
	bra.s	vme_a_rx_read                   ; the byte read
vme_a_rx_int:	; from: vme_scc_vectors
	addq.l	#1,$cb2.w                       ; A received counted
vme_a_rx_read:
	move.w	d0,-(sp)                        ; kept
	move.b	#$1,$df000d                     ; RR1
	move.b	$df000d,d0                      ; the errors
	andi.b	#$70,d0                         ; parity, overrun, framing
	beq.s	vme_a_rx_data                   ; none
	move.b	#$30,$df000d                    ; error reset
vme_a_rx_data:
	tst.b	$df000f                         ; the byte read
	move.w	(sp)+,d0                        ; back
vme_int_exit:
	move.b	#$38,$df000d                    ; the highest interrupt under service reset
	rte

;------------------------------------------------------------------------------
; vme_print_long: d5 printed as 8 hex digits (the word, byte and digit routines run on into each other).
; Changes d1.
;------------------------------------------------------------------------------
vme_print_long:	; from: vme_interrupt_test
	move.w	d5,-(sp)                        ; kept
	swap	d5                              ; the high word
	bsr.w	vme_print_word                  ; printed
	move.w	(sp)+,d5                        ; back: the low word

vme_print_word:	; from: vme_print_long
	move.w	d5,-(sp)                        ; kept
	asr.w	#8,d5                           ; the high byte
	bsr.w	vme_print_byte                  ; printed
	move.w	(sp)+,d5                        ; back: the low byte

vme_print_byte:	; from: vme_print_word
	move.w	d5,-(sp)                        ; kept
	asr.w	#4,d5                           ; the high digit
	bsr.w	vme_print_digit                 ; printed
	move.w	(sp)+,d5                        ; back: the low digit

vme_print_digit:	; from: vme_print_byte
	andi.b	#$f,d5                          ; the digit
	addi.b	#$30,d5                         ; '0'-'9'
	cmpi.b	#$39,d5                         ; a letter?
	ble.s	vme_print_digit_out             ; no
	addi.b	#$7,d5                          ; 'A'-'F'
vme_print_digit_out:
	move.w	d5,d1                           ; the character
	bsr.w	put_char                        ; printed
	rts

;------------------------------------------------------------------------------
; unused_space: zeros from the end of the code to the texts at $A800.
;------------------------------------------------------------------------------
unused_space:
	dcb.b	7450,0

;------------------------------------------------------------------------------
; Start-up self test texts (I codes), printed by the reset code before the menu.
;------------------------------------------------------------------------------
msg_ram_data_line_error:	; from: bus_error_caught
	dc.b	13,10,'I1 RAM/data line error ',0
msg_ram_disturbance:	; from: bus_error_caught
	dc.b	13,10,'I2 RAM disturbance   ',0
msg_ram_address_check:	; from: bus_error_caught
	dc.b	13,10,'I3 RAM address check ',0
msg_memory_configuration_error:	; from: cold_start
	dc.b	13,10,'I4 Memory configuration error',13,10,0
msg_hello_world:	; from: low_ram_test
	dc.b	13,10,'Hello World',0           ; printed on the RS232 port at start-up
msg_ram_sizing_error:
	dc.b	13,10,'I5 Ram sizing error',13,10,0 ; no reference
msg_looking_for_vme_ram:	; from: low_ram_test
	dc.b	13,10,'Looking for VME RAM',0
msg_vme_ram_not_found:	; from: check_vme_ram
	dc.b	13,10,'VME RAM not found',0
msg_looking_for_fpu:	; from: check_fpu
	dc.b	13,10,'Looking for FPU',0
msg_fpu_idle:	; from: check_fpu
	dc.b	13,10,'FPU idle',0
msg_fpu_not_found:	; from: check_fpu
	dc.b	13,10,'FPU not found',0
msg_checking_bus_error_handling:	; from: check_bus_error
	dc.b	13,10,'Checking Bus error handling',0
msg_bus_error_not_detected:	; from: check_bus_error
	dc.b	'I7 Bus error not detected',0
	dc.b	$00

;------------------------------------------------------------------------------
; menu_test_letters: the 15 test letters, in the order of test_routines. The menu input
; keeps only these letters; no 0 at the end (the count is fixed at 15).
;------------------------------------------------------------------------------
menu_test_letters:	; from: menu, run_q_tests
	dc.b	'ROMSTDILFPGYVQZ'

;------------------------------------------------------------------------------
; q_test_letters: the tests that Q runs, in order (12 letters, the count is set in $279).
;------------------------------------------------------------------------------
q_test_letters:	; from: run_q_tests
	dc.b	'ROMSTDILPFYV'

;------------------------------------------------------------------------------
; z_test_letters: the tests that Z runs, in order (6 letters).
;------------------------------------------------------------------------------
z_test_letters:	; from: run_q_tests
	dc.b	'ROTFLG',0

;------------------------------------------------------------------------------
; test_routines: the routine for each letter of menu_test_letters.
;------------------------------------------------------------------------------
test_routines:	; from: menu, run_q_tests
	dc.l	ram_test                        ; R RAM
	dc.l	rom_test                        ; O O.S. ROM
	dc.l	midi_test                       ; M MIDI
	dc.l	rs232_test                      ; S serial port
	dc.l	timing_test                     ; T timing
	dc.l	dma_port_test                   ; D DMA port
	dc.l	scc_test                        ; I SCC
	dc.l	rtc_test                        ; L real-time clock
	dc.l	floppy_menu                     ; F floppy disk
	dc.l	printer_joystick_test           ; P printer/mouse/joystick ports
	dc.l	blit_short_test                 ; G short BLiT
	dc.l	blit_long_test                  ; Y long BLiT
	dc.l	vme_test                        ; V VME
	dc.l	run_q_tests                     ; Q all unattended tests
	dc.l	run_z_tests                     ; Z unattended internal tests

;------------------------------------------------------------------------------
; ram_size_codes: the top of RAM in 64K units (bits 16-23 of ($204), bit 0 cleared) for
; 256K, 512K, 1M, 2M and 4M; the index picks the text from ram_size_texts.
;------------------------------------------------------------------------------
ram_size_codes:	; from: menu, ram_test
	dc.b	$04,$08,$10,$20,$40

;------------------------------------------------------------------------------
; msg_title: the menu title; $06 is the copyright sign in the font.
;------------------------------------------------------------------------------
msg_title:	; from: menu
	dc.b	13,10,9,9,'MEGA-STE Field Service Diagnostic Rev. 1.5',13,10,9,9,9,9
	dc.b	$06
	dc.b	' 1991, Atari Corp.',13,10,0
msg_date:	; from: read_command_line
	dc.b	13,10,9,'MAY 24, 1991',13,10,0
msg_author:	; from: read_command_line
	dc.b	9,' by TF',13,10,0
msg_increase_decrease:	; from: read_command_line
	dc.b	'Increase '                     ; $01 and $02 are the up and down arrows in the font
	dc.b	$01
	dc.b	', Decrease '
	dc.w	$020d,$0a00
msg_50_hz:	; from: menu
	dc.b	'50 Hz  ',0
msg_60_hz:	; from: menu
	dc.b	'60 Hz  ',0
msg_clock_8_meg_cache_off:	; from: read_command_line
	dc.b	13,10,9,'System clock set to  8 meg - cache off',13,10,0
msg_clock_16_meg_cache_off:	; from: read_command_line
	dc.b	13,10,9,'System clock set to 16 meg - cache off',13,10,0
msg_clock_16_meg_cache_on:	; from: read_command_line
	dc.b	13,10,9,'System clock set to 16 meg - cache on',13,10,0
msg_floppy_clock_8_meg:	; from: read_command_line
	dc.b	13,10,9,'8 meg floppy clock set',13,10,0
msg_floppy_clock_16_meg_hd:	; from: read_command_line
	dc.b	13,10,9,'16 meg floppy clock set - HIGH DENSITY',13,10,0
msg_write_dmalow:
	dc.b	13,10,9,'write to dmalow register $ffff860d',13,10,0 ; no reference
	dc.b	$00

;------------------------------------------------------------------------------
; ram_size_texts: the RAM size texts, in the order of ram_size_codes.
;------------------------------------------------------------------------------
ram_size_texts:	; from: menu, ram_test
	dc.l	msg_256k_ram
	dc.l	msg_512k_ram
	dc.l	msg_1m_ram
	dc.l	msg_2m_ram
	dc.l	msg_4m_ram
msg_256k_ram:
	dc.b	'256k RAM',0
msg_512k_ram:
	dc.b	'512k RAM',0
msg_1m_ram:
	dc.b	'1M RAM  ',0
msg_2m_ram:
	dc.b	'2M RAM  ',0
msg_4m_ram:
	dc.b	'4M RAM  ',0
msg_keyboard_rev:	; from: menu
	dc.b	' Keyboard rev. ',0

;------------------------------------------------------------------------------
; menu_text: the main menu, printed by $6bc2: a $05 shows the next character in inverse.
;------------------------------------------------------------------------------
menu_text:	; from: menu
	dc.b	$0d,$0a,$09,$05,$55,$05,$4e,$05,$41,$05,$54,$05,$54,$05,$45,$05
	dc.b	$4e,$05,$44,$05,$45,$05,$44,$0d,$0a,$09,$05
	dc.b	'R RAM        ',9,9
	dc.b	$05
	dc.b	'O O.S. ROM     ',9
	dc.b	$05
	dc.b	'M MIDI',13,10,9
	dc.b	$05
	dc.b	'S Serial Port',9,9
	dc.b	$05
	dc.b	'T Timing       ',9
	dc.b	$05
	dc.b	'D DMA Port',13,10,9
	dc.b	$05
	dc.b	'I SCC        ',9,9
	dc.b	$05
	dc.b	'L Real-time clock',13,10,9
	dc.b	$05
	dc.b	'F Floppy Disk',9,9
	dc.b	$05
	dc.b	'P Printer/Mouse/Joy Ports',13,10,9
	dc.b	$05
	dc.b	'G Short BLiT ',9,9
	dc.b	$05
	dc.b	'Y Long BLiT    ',9
	dc.b	$05
	dc.b	'V VME',13,10,10,9
	dc.b	$05
	dc.b	'Q Run all unattended tests (R,O,M,S,T,D,I,L,F,P,Y,V)',13,10,9
	dc.b	$05
	dc.b	'Z Run unattended internal tests (R,O,T,F,L,G)',13,10,10,9
	dc.w	$054f,$0550,$0545,$0552,$0541,$0554,$054f,$0552
	dc.w	$0d0a,$0905
	dc.b	'A Audio      ',9,9
	dc.b	$05
	dc.b	'C Color        ',9
	dc.b	$05
	dc.b	'K Keyboard',13,10,9
	dc.b	$05
	dc.b	'H High resolution ',9
	dc.b	$05
	dc.b	'J Hard Disk Write/Read',13,10,10,9
	dc.b	$05
	dc.b	'E Examine/Modify memory',13,10,9
	dc.b	$05
	dc.b	'B Set RS232 rate',13,10,9
	dc.b	$05
	dc.b	'X Toggle video output--50/60 Hz',13,10,9
	dc.b	$05
	dc.b	'? Help ',13,10,10,9,'Enter letter(s), and RETURN: ',0
msg_pass:	; from: run_q_tests, ram_test, rom_test, keyboard_test, midi_test, rs232_test, 12 more
	dc.b	'Pass',0
msg_fail_at_cycle:	; from: ram_test, rom_test, keyboard_test, midi_test, rs232_test, timing_test, 9 more
	dc.b	'Fail at cycle:',0
msg_q_tests_completed:	; from: run_q_tests
	dc.b	'Q Tests Completed',0
msg_z_tests_completed:	; from: run_q_tests
	dc.b	'Z Tests Completed',0
msg_keyboard_failed:	; from: menu_start
	dc.b	'Keyboard failed, connect RS232 terminal',13,10,0
msg_cycle:	; from: print_cycle
	dc.b	'Cycle: ',0
msg_stopped_ret_continue:	; from: ask_stopped
	dc.b	'Stopped. Press RET to continue, other key to quit.',0
msg_keyboard_buffer_full:	; from: read_command_line, read_line
	dc.b	'Keyboard buffer full',13,10,0

;------------------------------------------------------------------------------
; help_text: the first help page (the ? key).
;------------------------------------------------------------------------------
help_text:	; from: read_command_line
	dc.b	'RUNNING UNATTENDED TESTS',13,10
	dc.b	'Select a single test or any combination of tests by typing the c'
	dc.b	'orresponding',13,10
	dc.b	'letter or letters, then typing the RETURN key. To run repeated c'
	dc.b	'ycles of the',13,10
	dc.b	'test or  (tests),  follow the last letter with the number of  cy'
	dc.b	'cles to run.',13,10
	dc.b	'For example, "RSM25",  will run RAM,  Serial, and MIDI tests 25 '
	dc.b	'times.  If 0',13,10,'is entered, testing will be continuous.',13,10,10
	dc.b	'Use the ESC key to quit the test cycle.  In some cases there wil'
	dc.b	'l be a delay',13,10,'before control returns to the keyboard.',13,10,10
	dc.b	'An RS232  terminal may  be  used for  input and  display.  (The '
	dc.b	'Serial RS232',13,10
	dc.b	'will  not pass if a  terminal  is installed in  place of the loo'
	dc.b	'pback plug.)',13,10
	dc.b	'Normally a  color monitor is  used  for  all tests  accept high '
	dc.b	' resolution.',13,10
	dc.b	'If an error occurs,  an error message will be  displayed and the'
	dc.b	' screen will',13,10
	dc.b	'turn red. When the test completes,  Pass or Fail will be display'
	dc.b	'ed,  and the',13,10
	dc.b	'screen will  turn green  or  red.  If  multiple  tests are run a'
	dc.b	'nd an  error',13,10
	dc.b	'occurs on any test,  the  screen will remain red,  although succ'
	dc.b	'essive tests',13,10
	dc.b	'pass.  Once the test  has halted,  the  SPACE BAR  is used  to r'
	dc.b	'eturn to the',13,10,'menu.',13,10,10,10,0

;------------------------------------------------------------------------------
; help_text_miscellaneous: the second help page.
;------------------------------------------------------------------------------
help_text_miscellaneous:	; from: read_command_line
	dc.b	'MISCELANEOUS',13,10
	dc.b	'The DMA  and  Printer/joystick/game  port tests  require that  t'
	dc.b	'he port test',13,10,'fixtures be connected.',13,10,10
	dc.b	'The O.S. ROM test  calculates a  checksum/CRC  of the ROMs  and '
	dc.b	'compares the',13,10,'resultant CRC with the value found in the ROMs.'
	dc.b	13,10,10
	dc.b	'If the  RAM test  fails,  the error code, address,  data written'
	dc.b	',  data read',13,10,'and bad bits (0-15) are displayed.',13,10,10
	dc.b	'The  short  Bliter test  does  not  display  any  graphics  on  '
	dc.b	'the  screen.',13,10
	dc.b	'The long Bliter  test  while appearing  not to  finish the recta'
	dc.b	'ngle is  ok.',13,10,10,'OPERATOR REQUIRED TESTS',13,10
	dc.b	'The Audio,Color,Keyboard,High resolution  and Hard disk tests ha'
	dc.b	've few error',13,10
	dc.b	'messages. The operator must determine if  the output results are'
	dc.b	' acceptable.',13,10,10
	dc.b	'The Gen/lock test is run twice. Toggling the switch on the gen/l'
	dc.b	'ock  fixture',13,10
	dc.b	'should switch between the normal menu and no menu. With no menu '
	dc.b	'a "sweeping"',13,10
	dc.b	'cycle  should  be  heard.   Reset the computer  between each  ch'
	dc.b	'ange of  the',13,10
	dc.b	'gen/lock switch.  NOTE - RUN THIS TEST ONLY WITH A COLOR MONITOR',0
	dc.b	$00

;------------------------------------------------------------------------------
; exception_vectors: copied to $8-$2f at reset.
;------------------------------------------------------------------------------
exception_vectors:	; from: low_ram_test
	dc.l	bus_error_handler               ; $08 bus error
	dc.l	address_error_handler           ; $0c address error
	dc.l	illegal_handler                 ; $10 illegal instruction
	dc.l	exception_error_handler         ; $14 zero divide
	dc.l	exception_error_handler         ; $18 CHK
	dc.l	exception_error_handler         ; $1c TRAPV
	dc.l	exception_error_handler         ; $20 privilege violation
	dc.l	exception_error_handler         ; $24 trace
	dc.l	line_a_handler                  ; $28 line A
	dc.l	line_f_handler                  ; $2c line F

;------------------------------------------------------------------------------
; interrupt_vectors: copied to $60-$7f at reset.
;------------------------------------------------------------------------------
interrupt_vectors:	; from: low_ram_test
	dc.l	spurious_handler                ; $60 spurious interrupt
	dc.l	autovector_handler              ; $64 level 1
	dc.l	hbl_handler                     ; $68 level 2 (HBL)
	dc.l	autovector_handler              ; $6c level 3
	dc.l	vbl_handler                     ; $70 level 4 (VBL)
	dc.l	autovector_handler              ; $74 level 5
	dc.l	autovector_handler              ; $78 level 6
	dc.l	autovector_handler              ; $7c level 7

;------------------------------------------------------------------------------
; mfp_vectors: copied to $100-$13f at reset (MFP vector base $40).
;------------------------------------------------------------------------------
mfp_vectors:	; from: low_ram_test
	dc.l	centronics_busy_handler         ; $100 GPIP0 printer busy
	dc.l	dcd_handler                     ; $104 GPIP1 RS232 DCD
	dc.l	cts_handler                     ; $108 GPIP2 RS232 CTS
	dc.l	blitter_done_handler            ; $10c GPIP3 BLiTTER
	dc.l	timer_d_handler                 ; $110 timer D
	dc.l	timer_c_handler                 ; $114 timer C
	dc.l	acia_interrupt                  ; $118 GPIP4 keyboard/MIDI ACIAs
	dc.l	fdc_interrupt                   ; $11c GPIP5 FDC/ACSI
	dc.l	timer_b_handler                 ; $120 timer B
	dc.l	rs232_transmit_error_handler    ; $124 RS232 transmit error
	dc.l	rs232_transmit_handler          ; $128 RS232 transmit buffer empty
	dc.l	rs232_receive_error_handler     ; $12c RS232 receive error
	dc.l	rs232_receive_handler           ; $130 RS232 receive buffer full
	dc.l	timer_a_handler                 ; $134 timer A
	dc.l	ring_indicator_handler          ; $138 GPIP6 RS232 ring indicator
	dc.l	monitor_change_handler          ; $13c GPIP7 monochrome monitor detect

;------------------------------------------------------------------------------
; Exception texts (E codes), printed by the exception handlers.
;------------------------------------------------------------------------------
msg_autovector_error:	; from: autovector_handler
	dc.b	'E6 Autovector error',13,10,0
msg_spurious_interrupt:	; from: spurious_handler
	dc.b	'E7 Spurious Interrupt',13,10,0
msg_exception_error:	; from: exception_error_handler
	dc.b	'E8 Exception error',13,10,0
msg_bad_instruction_fetch:	; from: bus_error_handler, exception_error_handler
	dc.b	'E9 Bad instruction fetch ',13,10,0
msg_bus_error:	; from: bus_error_handler
	dc.b	13,10,'EB Bus Error ',0
msg_address_error:	; from: bus_error_handler
	dc.b	'EA Address Error ',0
msg_access_address:	; from: bus_error_handler
	dc.b	' Access Address: ',0
msg_program_counter:	; from: bus_error_handler
	dc.b	' Program Counter: ',0

;------------------------------------------------------------------------------
; Texts of the examine/modify memory utility (E).
;------------------------------------------------------------------------------
memory_utility_text:	; from: memory_utility
	dc.b	9,'Write/Read Memory Utility',13,10,9
	dc.b	'Type ? for help, hit ESC key to exit.',13,10,9
	dc.b	'Altering system memory ($8-$400), or system stack ($1ff00-20000)',13,10
	dc.b	9,'may cause a crash or unusual behavior.',13,10,9
	dc.b	'Byte access of a word-size register will cause a bus error.',13,10,0
msg_memory_prompt:	; from: memory_utility
	dc.b	13,10,'>',0
msg_not_a_valid_command:	; from: memory_utility
	dc.b	'Not a valid command: W,R,RW,?,<esc>',13,10,0
msg_invalid_address:	; from: memory_utility
	dc.b	'Invalid address given.',13,10,0
msg_no_equals_in_write:	; from: memory_utility
	dc.b	'No "=" in write command',13,10,0
msg_invalid_write_data:	; from: memory_utility
	dc.b	'Invalid data in write command',13,10,0
memory_utility_help_text:	; from: memory_utility
	dc.b	'Commands are: W-write memory, R-read byte, RW-read word.',13,10
	dc.b	'Syntax:',13,10,'W (address)<,address>=(data).',13,10
	dc.b	'  Second address is optional.',13,10,'R (address)<,address>',13,10
	dc.b	'RW (address)',13,10,'Address can be 1-6 hexadecimal digits',13,10
	dc.b	'Data can be 1-4 hexadecimal digits',13,10,13,10,'Examples:',13,10
	dc.b	'  W 200=3 writes 3 into location 200',13,10
	dc.b	'  W7000,7FFF=0 writes 0 into 7000-7FFF',13,10
	dc.b	'  W500=377 writes 0377 into 500 (word)',13,10
	dc.b	'  RW FF8200  reads a word from FF8200',13,10
	dc.b	'  R2000 3000 reads locations 2000 through 3000',13,10,0

;------------------------------------------------------------------------------
; RAM test texts (R codes).
;------------------------------------------------------------------------------
msg_testing_ram:	; from: ram_test
	dc.b	'Testing Ram',13,10,0
msg_r0_ram_address:	; from: print_ram_error
	dc.b	'R0 RAM address=',0
msg_r1_ram_address:	; from: print_ram_error
	dc.b	'R1 RAM address=',0
msg_r2_ram_address:	; from: print_ram_error
	dc.b	'R2 RAM address=',0
msg_r3_ram_address:	; from: print_ram_error
	dc.b	'R3 RAM address=',0
msg_r4_ram_address:	; from: print_ram_error
	dc.b	'R4 RAM address=',0
msg_cache_ram:	; from: print_ram_error
	dc.b	'Cache RAM ',0
msg_written:	; from: print_ram_error
	dc.b	' W:',0
msg_read:	; from: print_ram_error
	dc.b	' R:',0
msg_bad_bits:	; from: print_bad_bits
	dc.b	'  bad bits: ',0
msg_asterisk:	; from: ram_test_vbl
	dc.b	$2a,$00                         ; '*',0

;------------------------------------------------------------------------------
; crc16_table: CRC-16 table (polynomial $1021), 256 words, used by the ROM CRC at $21da.
;------------------------------------------------------------------------------
crc16_table:	; from: rom_crc
	dc.w	$0000,$1021,$2042,$3063,$4084,$50a5,$60c6,$70e7
	dc.w	$8108,$9129,$a14a,$b16b,$c18c,$d1ad,$e1ce,$f1ef
	dc.w	$1231,$0210,$3273,$2252,$52b5,$4294,$72f7,$62d6
	dc.w	$9339,$8318,$b37b,$a35a,$d3bd,$c39c,$f3ff,$e3de
	dc.w	$2462,$3443,$0420,$1401,$64e6,$74c7,$44a4,$5485
	dc.w	$a56a,$b54b,$8528,$9509,$e5ee,$f5cf,$c5ac,$d58d
	dc.w	$3653,$2672,$1611,$0630,$76d7,$66f6,$5695,$46b4
	dc.w	$b75b,$a77a,$9719,$8738,$f7df,$e7fe,$d79d,$c7bc
	dc.w	$48c4,$58e5,$6886,$78a7,$0840,$1861,$2802,$3823
	dc.w	$c9cc,$d9ed,$e98e,$f9af,$8948,$9969,$a90a,$b92b
	dc.w	$5af5,$4ad4,$7ab7,$6a96,$1a71,$0a50,$3a33,$2a12
	dc.w	$dbfd,$cbdc,$fbbf,$eb9e,$9b79,$8b58,$bb3b,$ab1a
	dc.w	$6ca6,$7c87,$4ce4,$5cc5,$2c22,$3c03,$0c60,$1c41
	dc.w	$edae,$fd8f,$cdec,$ddcd,$ad2a,$bd0b,$8d68,$9d49
	dc.w	$7e97,$6eb6,$5ed5,$4ef4,$3e13,$2e32,$1e51,$0e70
	dc.w	$ff9f,$efbe,$dfdd,$cffc,$bf1b,$af3a,$9f59,$8f78
	dc.w	$9188,$81a9,$b1ca,$a1eb,$d10c,$c12d,$f14e,$e16f
	dc.w	$1080,$00a1,$30c2,$20e3,$5004,$4025,$7046,$6067
	dc.w	$83b9,$9398,$a3fb,$b3da,$c33d,$d31c,$e37f,$f35e
	dc.w	$02b1,$1290,$22f3,$32d2,$4235,$5214,$6277,$7256
	dc.w	$b5ea,$a5cb,$95a8,$8589,$f56e,$e54f,$d52c,$c50d
	dc.w	$34e2,$24c3,$14a0,$0481,$7466,$6447,$5424,$4405
	dc.w	$a7db,$b7fa,$8799,$97b8,$e75f,$f77e,$c71d,$d73c
	dc.w	$26d3,$36f2,$0691,$16b0,$6657,$7676,$4615,$5634
	dc.w	$d94c,$c96d,$f90e,$e92f,$99c8,$89e9,$b98a,$a9ab
	dc.w	$5844,$4865,$7806,$6827,$18c0,$08e1,$3882,$28a3
	dc.w	$cb7d,$db5c,$eb3f,$fb1e,$8bf9,$9bd8,$abbb,$bb9a
	dc.w	$4a75,$5a54,$6a37,$7a16,$0af1,$1ad0,$2ab3,$3a92
	dc.w	$fd2e,$ed0f,$dd6c,$cd4d,$bdaa,$ad8b,$9de8,$8dc9
	dc.w	$7c26,$6c07,$5c64,$4c45,$3ca2,$2c83,$1ce0,$0cc1
	dc.w	$ef1f,$ff3e,$cf5d,$df7c,$af9b,$bfba,$8fd9,$9ff8
	dc.w	$6e17,$7e36,$4e55,$5e74,$2e93,$3eb2,$0ed1,$1ef0

;------------------------------------------------------------------------------
; country_names: the TOS country names by country code 0-15 (from the ROM header), used by
; $213e; code 15 and over shows "Unassigned country code".
;------------------------------------------------------------------------------
country_names:	; from: print_tos_version
	dc.l	msg_country_usa                 ; 0 USA
	dc.l	msg_country_german              ; 1 Germany
	dc.l	msg_country_french              ; 2 France
	dc.l	msg_country_uk                  ; 3 UK
	dc.l	msg_country_spanish             ; 4 Spain
	dc.l	msg_country_italian             ; 5 Italy
	dc.l	msg_country_swedish             ; 6 Sweden
	dc.l	msg_country_swiss_french        ; 7 Swiss French
	dc.l	msg_country_swiss_german        ; 8 Swiss German
	dc.l	msg_country_turkish             ; 9 Turkey
	dc.l	msg_country_finnish             ; 10 Finland
	dc.l	msg_country_norwegian           ; 11 Norway
	dc.l	msg_country_danish              ; 12 Denmark
	dc.l	msg_country_arabic              ; 13 Saudi Arabia
	dc.l	msg_country_dutch               ; 14 Holland
	dc.l	msg_country_unassigned          ; 15 unassigned

;------------------------------------------------------------------------------
; O.S. ROM test texts.
;------------------------------------------------------------------------------
msg_rom_test:	; from: rom_test
	dc.b	'ROM checksum/crc test',13,10,0
msg_version:	; from: print_tos_version
	dc.b	'Version ',0
msg_high_rom_checksum:
	dc.b	'High ROM checksum, crc',13,10,0 ; no reference
msg_low_rom_checksum:
	dc.b	'Low ROM checksum, crc',13,10,0 ; no reference
msg_prom_header:	; from: rom_test
	dc.b	13,10,'PROM                    ',9,'u206',9,'u207',13,10,0
msg_calculated_checksums:	; from: rom_test
	dc.b	'Calculated ROM checksums',9,0
msg_calculated_crcs:	; from: rom_test
	dc.b	'Calculated ROM CRCs     ',9,0
msg_crc_mismatch:	; from: rom_test
	dc.b	'CRC  mismatch  in   u20',0
msg_u206_tab:	; from: rom_test
	dc.b	$36,$09,$00                     ; '6',9,0 - ends "u20" with 6
msg_u207_tab:	; from: rom_test
	dc.b	'7',9,9,'     ',0
msg_pal:	; from: print_tos_version
	dc.b	'PAL',13,10,0
msg_ntsc:	; from: print_tos_version
	dc.b	'NTSC',13,10,0
msg_country_usa:	; from: country_names
	dc.b	'USA ',0
msg_country_german:	; from: country_names
	dc.b	'German ',0
msg_country_french:	; from: country_names
	dc.b	'French ',0
msg_country_uk:	; from: country_names
	dc.b	'UK ',0
msg_country_spanish:	; from: country_names
	dc.b	'Spanish ',0
msg_country_italian:	; from: country_names
	dc.b	'Italian ',0
msg_country_swedish:	; from: country_names
	dc.b	'Swedish ',0
msg_country_swiss_french:	; from: country_names
	dc.b	'Swiss French ',0
msg_country_swiss_german:	; from: country_names
	dc.b	'Swiss German ',0
msg_country_turkish:	; from: country_names
	dc.b	'Turkish ',0
msg_country_finnish:	; from: country_names
	dc.b	'Finnish ',0
msg_country_norwegian:	; from: country_names
	dc.b	'Norwegian ',0
msg_country_danish:	; from: country_names
	dc.b	'Danish ',0
msg_country_arabic:	; from: country_names
	dc.b	'Arabic ',0
msg_country_dutch:	; from: country_names
	dc.b	'Dutch ',0
msg_country_unassigned:	; from: country_names
	dc.b	'Unassigned country code',13,10,0
msg_new_version_number:
	dc.b	'New version number',13,10,0    ; no reference
msg_no_colour_monochrome:	; from: colour_test
	dc.b	'No color--Monochrome monitor',0

;------------------------------------------------------------------------------
; key_click_psg_settings: PSG register/value pairs for the key click of the keyboard test,
; written by $2952 up to keyboard_layout.
;------------------------------------------------------------------------------
key_click_psg_settings:	; from: keyboard_key_click
	dc.b	$00,$3b,$06,$00,$07,$fe,$08,$10,$0d,$03,$0b,$80,$0c,$01 ; tone A period $3b, noise 0, mixer: tone A
                                                ;   only, A volume from the envelope, envelope shape 3, envelope period
                                                ;   $0180

;------------------------------------------------------------------------------
; keyboard_layout: where each key is drawn on the keyboard test screen, by scan code
; $00-$72: high byte the text column, low byte the text row; 0 = no key.
;------------------------------------------------------------------------------
keyboard_layout:	; from: draw_key, keyboard_key_click
	dc.w	$0000,$0506,$0706,$0906,$0b06,$0d06,$0f06,$1106
	dc.w	$1306,$1506,$1706,$1906,$1b06,$1d06,$2106,$0508
	dc.w	$0808,$0a08,$0c08,$0e08,$1008,$1208,$1408,$1608
	dc.w	$1808,$1a08,$1c08,$1e08,$2008,$050a,$090a,$0b0a
	dc.w	$0d0a,$0f0a,$110a,$130a,$150a,$170a,$190a,$1b0a
	dc.w	$1d0a,$1f06,$050c,$220a,$0a0c,$0c0c,$0e0c,$100c
	dc.w	$120c,$140c,$160c,$180c,$1a0c,$1c0c,$1e0c,$0000
	dc.w	$070e,$0b0e,$1d0e,$0604,$0904,$0c04,$0f04,$1204
	dc.w	$1504,$1804,$1b04,$1e04,$2104,$0000,$0000,$2a08
	dc.w	$2808,$0000,$3408,$260a,$0000,$2a0a,$340a,$0000
	dc.w	$280a,$0000,$2608,$2208,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$080c,$2906,$2606,$2e06,$3006,$3206,$3406,$2e08
	dc.w	$3008,$3208,$2e0a,$300a,$320a,$2e0c,$300c,$320c
	dc.w	$2e0e,$320e,$340c

;------------------------------------------------------------------------------
; keytop_texts: the text drawn for each key, by scan code $00-$72 (0 = no key). The same
; texts show the pressed key; Return, Enter and Space use the longer msg_last_key texts.
;------------------------------------------------------------------------------
keytop_texts:	; from: keyboard_test, draw_key, reset_keyboard_and_check
	dc.l	$00000000
	dc.l	keytop_esc                      ; $01 Esc
	dc.l	keytop_1                        ; $02 1
	dc.l	keytop_2                        ; $03 2
	dc.l	keytop_3                        ; $04 3
	dc.l	keytop_4                        ; $05 4
	dc.l	keytop_5                        ; $06 5
	dc.l	keytop_6                        ; $07 6
	dc.l	keytop_7                        ; $08 7
	dc.l	keytop_8                        ; $09 8
	dc.l	keytop_9                        ; $0a 9
	dc.l	keytop_0                        ; $0b 0
	dc.l	keytop_minus                    ; $0c -
	dc.l	keytop_equals                   ; $0d =
	dc.l	keytop_backspace                ; $0e Backspace
	dc.l	keytop_tab                      ; $0f Tab
	dc.l	keytop_q                        ; $10 Q
	dc.l	keytop_w                        ; $11 W
	dc.l	keytop_e                        ; $12 E
	dc.l	keytop_r                        ; $13 R
	dc.l	keytop_t                        ; $14 T
	dc.l	keytop_y                        ; $15 Y
	dc.l	keytop_u                        ; $16 U
	dc.l	keytop_i                        ; $17 I
	dc.l	keytop_o                        ; $18 O
	dc.l	keytop_p                        ; $19 P
	dc.l	keytop_left_bracket             ; $1a [
	dc.l	keytop_right_bracket            ; $1b ]
	dc.l	keytop_return                   ; $1c Return
	dc.l	keytop_control                  ; $1d Control
	dc.l	keytop_a                        ; $1e A
	dc.l	keytop_s                        ; $1f S
	dc.l	keytop_d                        ; $20 D
	dc.l	keytop_f                        ; $21 F
	dc.l	keytop_g                        ; $22 G
	dc.l	keytop_h                        ; $23 H
	dc.l	keytop_j                        ; $24 J
	dc.l	keytop_k                        ; $25 K
	dc.l	keytop_l                        ; $26 L
	dc.l	keytop_semicolon                ; $27 ;
	dc.l	keytop_apostrophe               ; $28 '
	dc.l	keytop_backquote                ; $29 `
	dc.l	keytop_left_shift               ; $2a left Shift
	dc.l	keytop_backslash                ; $2b \ (# European)
	dc.l	keytop_z                        ; $2c Z
	dc.l	keytop_x                        ; $2d X
	dc.l	keytop_c                        ; $2e C
	dc.l	keytop_v                        ; $2f V
	dc.l	keytop_b                        ; $30 B
	dc.l	keytop_n                        ; $31 N
	dc.l	keytop_m                        ; $32 M
	dc.l	keytop_comma                    ; $33 ,
	dc.l	keytop_period                   ; $34 .
	dc.l	keytop_slash                    ; $35 /
	dc.l	keytop_right_shift              ; $36 right Shift
	dc.l	$00000000
	dc.l	keytop_alternate                ; $38 Alternate
	dc.l	keytop_space                    ; $39 Space
	dc.l	keytop_caps_lock                ; $3a Caps Lock
	dc.l	keytop_f1                       ; $3b F1
	dc.l	keytop_f2                       ; $3c F2
	dc.l	keytop_f3                       ; $3d F3
	dc.l	keytop_f4                       ; $3e F4
	dc.l	keytop_f5                       ; $3f F5
	dc.l	keytop_f6                       ; $40 F6
	dc.l	keytop_f7                       ; $41 F7
	dc.l	keytop_f8                       ; $42 F8
	dc.l	keytop_f9                       ; $43 F9
	dc.l	keytop_f10                      ; $44 F10
	dc.l	$00000000,$00000000
	dc.l	keytop_clr_home                 ; $47 Clr/Home
	dc.l	keytop_up_arrow                 ; $48 up arrow
	dc.l	$00000000
	dc.l	keytop_minus                    ; $4a keypad -
	dc.l	keytop_left_arrow               ; $4b left arrow
	dc.l	$00000000
	dc.l	keytop_right_arrow              ; $4d right arrow
	dc.l	keytop_kp_plus                  ; $4e keypad +
	dc.l	$00000000
	dc.l	keytop_down_arrow               ; $50 down arrow
	dc.l	$00000000
	dc.l	keytop_insert                   ; $52 Insert
	dc.l	keytop_delete                   ; $53 Delete
	dc.l	$00000000,$00000000,$00000000,$00000000
	dc.l	$00000000,$00000000,$00000000,$00000000
	dc.l	$00000000,$00000000,$00000000,$00000000
	dc.l	keytop_iso                      ; $60 ISO key
	dc.l	keytop_undo                     ; $61 Undo
	dc.l	keytop_help                     ; $62 Help
	dc.l	keytop_kp_left_paren            ; $63 keypad (
	dc.l	keytop_kp_right_paren           ; $64 keypad )
	dc.l	keytop_slash                    ; $65 keypad /
	dc.l	keytop_kp_star                  ; $66 keypad *
	dc.l	keytop_7                        ; $67 keypad 7
	dc.l	keytop_8                        ; $68 keypad 8
	dc.l	keytop_9                        ; $69 keypad 9
	dc.l	keytop_4                        ; $6a keypad 4
	dc.l	keytop_5                        ; $6b keypad 5
	dc.l	keytop_6                        ; $6c keypad 6
	dc.l	keytop_1                        ; $6d keypad 1
	dc.l	keytop_2                        ; $6e keypad 2
	dc.l	keytop_3                        ; $6f keypad 3
	dc.l	keytop_kp_0                     ; $70 keypad 0
	dc.l	keytop_period                   ; $71 keypad .
	dc.l	keytop_enter                    ; $72 Enter
keytop_esc:
	dc.b	$1b,$00                         ; 27,0
keytop_1:
	dc.b	$31,$00                         ; '1',0 (also keypad 1)
keytop_2:
	dc.b	$32,$00                         ; '2',0 (also keypad 2)
keytop_3:
	dc.b	$33,$00                         ; '3',0 (also keypad 3)
keytop_4:
	dc.b	$34,$00                         ; '4',0 (also keypad 4)
keytop_5:
	dc.b	$35,$00                         ; '5',0 (also keypad 5)
keytop_6:
	dc.b	$36,$00                         ; '6',0 (also keypad 6)
keytop_7:
	dc.b	$37,$00                         ; '7',0 (also keypad 7)
keytop_8:
	dc.b	$38,$00                         ; '8',0 (also keypad 8)
keytop_9:
	dc.b	$39,$00                         ; '9',0 (also keypad 9)
keytop_0:
	dc.b	$30,$00                         ; '0',0
keytop_minus:
	dc.b	$2d,$00                         ; '-',0 (also keypad -)
keytop_kp_plus:
	dc.b	$2b,$00                         ; '+',0
keytop_equals:
	dc.b	$3d,$00                         ; '=',0
keytop_backspace:
	dc.b	$42,$53,$00                     ; 'BS',0
keytop_tab:
	dc.b	$54,$42,$00                     ; 'TB',0
keytop_q:
	dc.b	$51,$00                         ; 'Q',0
keytop_w:
	dc.b	$57,$00                         ; 'W',0
keytop_e:
	dc.b	$45,$00                         ; 'E',0
keytop_r:
	dc.b	$52,$00                         ; 'R',0
keytop_t:
	dc.b	$54,$00                         ; 'T',0
keytop_y:
	dc.b	$59,$00                         ; 'Y',0
keytop_u:
	dc.b	$55,$00                         ; 'U',0
keytop_i:
	dc.b	$49,$00                         ; 'I',0
keytop_o:
	dc.b	$4f,$00                         ; 'O',0
keytop_p:
	dc.b	$50,$00                         ; 'P',0
keytop_left_bracket:
	dc.b	$5b,$00                         ; '[',0
keytop_right_bracket:
	dc.b	$5d,$00                         ; ']',0
keytop_return:
	dc.w	$200a,$0820,$0a08,$0852,$5400   ; ' ',10,8,' ',10,8,8,'RT',0: the key drawn over three rows
keytop_control:
	dc.b	'CTL',0
keytop_a:
	dc.b	$41,$00                         ; 'A',0
keytop_s:
	dc.b	$53,$00                         ; 'S',0
keytop_d:
	dc.b	$44,$00                         ; 'D',0
keytop_f:
	dc.b	$46,$00                         ; 'F',0
keytop_g:
	dc.b	$47,$00                         ; 'G',0
keytop_h:
	dc.b	$48,$00                         ; 'H',0 (also Clr/Home)
keytop_j:
	dc.b	$4a,$00                         ; 'J',0
keytop_k:
	dc.b	$4b,$00                         ; 'K',0
keytop_l:
	dc.b	$4c,$00                         ; 'L',0
keytop_semicolon:
	dc.b	$3b,$00                         ; ';',0
keytop_apostrophe:
	dc.b	$27,$00                         ; $27,0
keytop_backquote:
	dc.b	$60,$00                         ; '`',0
keytop_left_shift:
	dc.b	' SH ',0
keytop_backslash:	; from: draw_key
	dc.b	$5c,$00                         ; '\',0: scan code $2b; on the European layout the ISO key $60
keytop_z:
	dc.b	$5a,$00                         ; 'Z',0
keytop_x:
	dc.b	$58,$00                         ; 'X',0
keytop_c:
	dc.b	$43,$00                         ; 'C',0
keytop_v:
	dc.b	$56,$00                         ; 'V',0
keytop_b:
	dc.b	$42,$00                         ; 'B',0
keytop_n:
	dc.b	$4e,$00                         ; 'N',0
keytop_m:
	dc.b	$4d,$00                         ; 'M',0
keytop_comma:
	dc.b	$2c,$00                         ; ',',0
keytop_period:
	dc.b	$2e,$00                         ; also keypad .
keytop_slash:
	dc.b	$2f,$00                         ; also keypad /
keytop_right_shift:
	dc.b	$53,$48,$00                     ; 'SH',0
keytop_alternate:
	dc.b	$41,$4c,$00                     ; 'AL',0
keytop_space:
	dc.b	'      SPACE      ',0
keytop_caps_lock:
	dc.b	$43,$4c,$00                     ; 'CL',0
keytop_f1:
	dc.b	$46,$31,$00                     ; 'F1',0
keytop_f2:
	dc.b	$46,$32,$00                     ; 'F2',0
keytop_f3:
	dc.b	$46,$33,$00                     ; 'F3',0
keytop_f4:
	dc.b	$46,$34,$00                     ; 'F4',0
keytop_f5:
	dc.b	$46,$35,$00                     ; 'F5',0
keytop_f6:
	dc.b	$46,$36,$00                     ; 'F6',0
keytop_f7:
	dc.b	$46,$37,$00                     ; 'F7',0
keytop_f8:
	dc.b	$46,$38,$00                     ; 'F8',0
keytop_f9:
	dc.b	$46,$39,$00                     ; 'F9',0
keytop_f10:
	dc.b	'F10',0
keytop_clr_home:
	dc.b	$48,$00                         ; 'H'
keytop_up_arrow:	; from: draw_mouse_up_arrow
	dc.b	$01,$00                         ; $01 = up arrow in the font
keytop_left_arrow:	; from: draw_mouse_left_arrow, floppy_speed_test
	dc.b	$04,$00                         ; $04 = left arrow in the font
keytop_right_arrow:	; from: draw_mouse_right_arrow
	dc.b	$03,$00                         ; $03 = right arrow in the font
keytop_down_arrow:	; from: draw_mouse_down_arrow
	dc.b	$02,$00                         ; $02 = down arrow in the font
keytop_insert:
	dc.b	$49,$00                         ; 'I'
keytop_delete:
	dc.b	$44,$00                         ; 'D'
keytop_iso:
	dc.b	$20,$00                         ; ' ': scan code $60, blank on the U.S. layout
keytop_undo:
	dc.b	$55,$4e,$00                     ; 'UN',0
keytop_help:
	dc.b	$48,$50,$00                     ; 'HP',0
keytop_kp_left_paren:
	dc.b	$28,$00                         ; '(',0
keytop_kp_right_paren:
	dc.b	$29,$00                         ; ')',0
keytop_kp_star:
	dc.b	$2a,$00                         ; '*',0
keytop_kp_0:
	dc.b	'0  ',0
keytop_enter:
	dc.b	$45,$0a,$08,$20,$0a,$08,$20,$00 ; 'E',10,8,' ',10,8,' ',0: the key drawn over three rows
keytop_hash:	; from: draw_key
	dc.b	$23,$00                         ; '#',0: scan code $2b on the European layout

;------------------------------------------------------------------------------
; Keyboard test texts (K codes).
;------------------------------------------------------------------------------
msg_keyboard_test:	; from: keyboard_test
	dc.b	'Keyboard test',0
msg_mouse:	; from: keyboard_test
	dc.b	'MOUSE',0
msg_last_key_return:	; from: keyboard_test
	dc.b	$52,$54,$00                     ; shown as the last key pressed
msg_last_key_enter:	; from: keyboard_test
	dc.b	'ENTER',0
msg_last_key_space:	; from: keyboard_test
	dc.b	'SPACE',0
msg_stuck_key:	; from: reset_keyboard_and_check
	dc.b	13,10,'K0 Stuck key: ',0
msg_keyboard_not_responding:	; from: reset_keyboard_and_check
	dc.b	13,10,'K1 Keyboard not responding',13,10,0
msg_keyboard_status_error:	; from: reset_keyboard_and_check
	dc.b	13,10,'K2 Keyboard status error',13,10,0
msg_european_keyboard:	; from: keyboard_test
	dc.b	9,'European keyboard (U.K. keytops shown)',13,10,9
	dc.b	'Press keys and watch screen to verify closure',13,10,0
msg_us_keyboard:	; from: keyboard_test
	dc.b	9,'U.S. keyboard',13,10,9
	dc.b	'Press keys and watch screen to verify closure',13,10,0
msg_shift_esc_to_exit:	; from: keyboard_test
	dc.b	9,'Hit shift Esc to exit',0
	dc.b	$00

;------------------------------------------------------------------------------
; midi_buffer_records_init: 30 bytes copied to $618 by the MIDI test: two buffer records
; like acia_buffer_records_init (long buffer address, words size, head, tail, low mark, high
; mark) for 128-byte buffers at $518 and $598, then a spare word.
;------------------------------------------------------------------------------
midi_buffer_records_init:	; from: midi_test
	dc.l	$00000518                       ; buffer at $518
	dc.w	$0080,$0000,$0000,$0010,$0030   ; size 128, head, tail, low mark 16, high mark 48
	dc.l	$00000598                       ; buffer at $598
	dc.w	$0080,$0000,$0000,$0020,$0060,$0000 ; size 128, head, tail, low mark 32, high mark 96, spare word

;------------------------------------------------------------------------------
; MIDI test texts (M codes).
;------------------------------------------------------------------------------
msg_testing_midi:	; from: midi_test
	dc.b	'Testing MIDI',13,10,0
msg_midi_data_overrun:	; from: midi_test
	dc.b	'M4 MIDI data overrun',13,10,0
msg_midi_parity:	; from: midi_test
	dc.b	'M3 MIDI parity',13,10,0
msg_midi_framing:	; from: midi_test
	dc.b	'M2 MIDI framing',13,10,0
msg_midi_data_mismatch:	; from: midi_test
	dc.b	'M1 MIDI data mismatch',13,10,0
msg_midi_not_received:	; from: midi_test
	dc.b	'M0 MIDI not received',13,10,0

;------------------------------------------------------------------------------
; bit_masks_unused: the same bytes as rs232_rate_codes; no reference.
;------------------------------------------------------------------------------
bit_masks_unused:
	dc.b	$01,$02,$04,$08,$10,$20,$40,$00

;------------------------------------------------------------------------------
; rs232_error_messages: the RS232 test's error texts, one for each error bit: bits 0-7 in
; $676, bits 8-12 in $677.
;------------------------------------------------------------------------------
rs232_error_messages:	; from: rs232_test
	dc.l	msg_rs232_data_overrun          ; bit 0: S4 data overrun
	dc.l	msg_rs232_parity                ; bit 1: S3 parity
	dc.l	msg_rs232_framing               ; bit 2: S2 framing
	dc.l	msg_rs232_data_mismatch         ; bit 3: S1 data mismatch
	dc.l	msg_rs232_not_received          ; bit 4: S0 not received
	dc.l	msg_rs232_irq                   ; bit 5: S5 IRQ
	dc.l	msg_rs232_transmit_error_interrupt ; bit 6: S7 transmit error interrupt
	dc.l	msg_rs232_receive_error_interrupt ; bit 7: S8 receive error interrupt
	dc.l	msg_rs232_ri_dtr                ; bit 8: S9 RI-DTR not connected
	dc.l	msg_rs232_dcd_dtr               ; bit 9: SA DCD-DTR not connected
	dc.l	msg_rs232_rts_cts               ; bit 10: SB RTS-CTS not connected
	dc.l	msg_rs232_transmit_error        ; bit 11: S6 transmit error (68901)
	dc.l	msg_rs232_input_shorted         ; bit 12: SC input shorted to output

;------------------------------------------------------------------------------
; rs232_rate_codes: the MFP timer D data value for each RS232 rate, in the order of
; rs232_rate_texts; $2e3a looks the value up to print the rate.
;------------------------------------------------------------------------------
rs232_rate_codes:	; from: print_rs232_rate
	dc.b	$01,$02,$04,$08,$10,$20,$40,$00 ; 19200, 9600, 4800, 2400, 1200, 600, 300 bps, unused

;------------------------------------------------------------------------------
; rs232_rate_texts: the rate texts for rs232_rate_codes.
;------------------------------------------------------------------------------
rs232_rate_texts:	; from: print_rs232_rate
	dc.l	msg_19200_bps
	dc.l	msg_9600_bps
	dc.l	msg_4800_bps
	dc.l	msg_2400_bps
	dc.l	msg_1200_bps
	dc.l	msg_600_bps
	dc.l	msg_300_bps
msg_19200_bps:
	dc.b	'19.2k bps',0
msg_9600_bps:
	dc.b	'9600 bps ',0
msg_4800_bps:
	dc.b	'4800 bps ',0
msg_2400_bps:
	dc.b	'2400 bps ',0
msg_1200_bps:
	dc.b	'1200 bps ',0
msg_600_bps:
	dc.b	'600 bps  ',0
msg_300_bps:
	dc.b	'300 bps  ',0
msg_no_loopback_connector:	; from: rs232_test
	dc.b	'No loopback connector',13,10,0 ; also sent out as the first loopback test data

;------------------------------------------------------------------------------
; rs232_test_bytes: the bytes sent by the RS232 loopback test ($2db0 sends up to a 0), so
; only $55 and $aa are sent; $ff,$e5,$d1 after the 0 are never used.
;------------------------------------------------------------------------------
rs232_test_bytes:	; from: rs232_test
	dc.b	$55,$aa,$00,$ff,$e5,$d1,$00

;------------------------------------------------------------------------------
; RS232 test texts (S codes).
;------------------------------------------------------------------------------
msg_testing_rs232_loopback:	; from: rs232_test
	dc.b	'Testing RS232 loopback',13,10,0
msg_hold_down_button:
	dc.b	'Hold down button (or remove loopback), and press key.',13,10 ; no reference
	dc.b	'Press ESC to skip this test.',13,10,0
msg_rs232_not_received:	; from: rs232_error_messages
	dc.b	'S0 RS232 not received',13,10,0
msg_rs232_data_mismatch:	; from: rs232_error_messages
	dc.b	'S1 RS232 data mismatch',13,10,0
msg_rs232_framing:	; from: rs232_error_messages
	dc.b	'S2 RS232 framing',13,10,0
msg_rs232_parity:	; from: rs232_error_messages
	dc.b	'S3 RS232 parity',13,10,0
msg_rs232_data_overrun:	; from: rs232_error_messages
	dc.b	'S4 RS232 data overrun',13,10,0
msg_rs232_irq:	; from: rs232_error_messages
	dc.b	'S5 RS232 IRQ',13,10,0
msg_rs232_transmit_error:	; from: rs232_error_messages
	dc.b	'S6 RS232 transmit error (68901)',13,10,0
msg_rs232_transmit_error_interrupt:	; from: rs232_error_messages
	dc.b	'S7 RS232 Transmit error interrupt',13,10,0
msg_rs232_receive_error_interrupt:	; from: rs232_error_messages
	dc.b	'S8 RS232 Receive error interrupt',13,10,0
msg_rs232_ri_dtr:	; from: rs232_error_messages
	dc.b	'S9 RS232 RI-DTR not connected',13,10,0
msg_rs232_dcd_dtr:	; from: rs232_error_messages
	dc.b	'SA RS232 DCD-DTR not connected',13,10,0
msg_rs232_rts_cts:	; from: rs232_error_messages
	dc.b	'SB RS232 RTS-CTS not connected',13,10,0
msg_rs232_input_shorted:	; from: rs232_error_messages
	dc.b	'SC RS232 input shorted to output',13,10,0
	dc.b	$00

;------------------------------------------------------------------------------
; dma_sound_mono_1khz and the three after it: the DMA sound test's plays, each a long sample
; block address (in the copy at $40000; the block starts with its length), a long count of
; frames to play and the sound mode word; read by $2fc8 for $32e4.
;------------------------------------------------------------------------------
dma_sound_mono_1khz:	; from: dma_sound_test
	dc.l	$00040000,$00000320             ; block 1 at $40000, 800 frames
	dc.w	$0083                           ; mono, 50066 Hz
dma_sound_stereo_tones:	; from: dma_sound_test
	dc.l	$00040034,$00000320             ; block 2 at $40034, 800 frames
	dc.w	$0002                           ; stereo, 25033 Hz
dma_sound_treble:	; from: dma_sound_test
	dc.l	$00040098,$00000bb8             ; block 3 at $40098, 3000 frames
	dc.w	$0083                           ; mono, 50066 Hz

;------------------------------------------------------------------------------
; dma_sound_bass: two plays of 10 bytes each ($2fc8 steps 10 bytes) for the bass test.
;------------------------------------------------------------------------------
dma_sound_bass:	; from: dma_sound_test
	dc.l	$000400a4,$0000000a             ; block 4 at $400a4, 10 frames
	dc.w	$0080                           ; mono, 6258 Hz
	dc.l	$00040120,$0000000a             ; block 5 at $40120, 10 frames
	dc.w	$0081                           ; mono, 12517 Hz

;------------------------------------------------------------------------------
; dma_sound_samples: copied to $40000 ($42c bytes) by $2fc8. Five blocks, each a long
; length and then that many signed 8-bit samples.
;------------------------------------------------------------------------------
dma_sound_samples:	; from: dma_sound_test
	dc.l	$00000030                       ; 48 bytes: one cycle of a sine (1 kHz at 50 kHz)
	dc.b	$00,$11,$21,$31,$40,$4d,$5a,$65,$6e,$74,$7b,$7e,$7f,$7e,$7b,$74
	dc.b	$6e,$65,$5a,$4d,$40,$31,$21,$11,$00,$ef,$df,$cf,$c0,$b3,$a6,$9c
	dc.b	$92,$8c,$85,$82,$81,$82,$85,$8b,$92,$9b,$a6,$b3,$c0,$cf,$df,$ef
dma_sound_samples_stereo:
	dc.l	$00000060                       ; 96 bytes: left/right pairs, left one sine cycle (500 Hz at 25 kHz),
                                                ;   right two (1 kHz)
	dc.b	$00,$00,$10,$21,$21,$3f,$31,$5a,$3f,$6e,$4d,$7b,$5a,$7f,$65,$7b
	dc.b	$6e,$6e,$75,$5a,$7b,$3f,$7d,$21,$7f,$00,$7e,$df,$7c,$c1,$75,$a6
	dc.b	$6e,$92,$65,$85,$5a,$80,$4d,$85,$3f,$92,$31,$a6,$21,$c1,$10,$df
	dc.b	$00,$00,$f0,$21,$df,$3f,$cf,$5a,$c1,$6e,$b3,$7b,$a6,$7f,$9b,$7b
	dc.b	$92,$6e,$8b,$5a,$85,$3f,$83,$21,$80,$00,$82,$df,$84,$c1,$89,$a6
	dc.b	$91,$92,$9c,$85,$a6,$80,$b3,$85,$c1,$92,$cc,$a6,$df,$c1,$f0,$df
dma_sound_samples_square:
	dc.l	$00000008                       ; 8 bytes: square wave (12.5 kHz at 50 kHz)
	dc.b	$7f,$7f,$80,$80,$7f,$7f,$80,$80
dma_sound_samples_low_sine:
	dc.l	$00000078                       ; 120 bytes: one cycle of a sine (52 Hz at 6258 Hz)
	dc.b	$00,$07,$0d,$14,$1a,$21,$27,$2d,$34,$3a,$3f,$45,$4b,$50,$55,$5a
	dc.b	$5e,$63,$67,$6b,$6e,$71,$74,$76,$79,$7b,$7c,$7d,$7e,$7e,$7f,$7f
	dc.b	$7e,$7d,$7c,$7b,$79,$76,$74,$71,$6e,$6b,$67,$63,$5e,$5a,$55,$50
	dc.b	$4b,$45,$3f,$3a,$34,$2d,$27,$21,$1a,$14,$0d,$07,$00,$f9,$f3,$ec
	dc.b	$e6,$df,$d9,$d3,$cc,$c6,$c1,$bb,$b5,$b0,$ab,$a6,$a2,$9d,$99,$95
	dc.b	$92,$8f,$8c,$8a,$87,$85,$83,$82,$81,$81,$80,$80,$81,$82,$83,$84
	dc.b	$85,$87,$8a,$8c,$92,$95,$99,$9d,$a2,$a6,$ab,$b0,$b5,$bb,$c1,$c6
	dc.b	$cc,$d3,$d9,$df,$e6,$ec,$f3,$f9
dma_sound_samples_long_sine:
	dc.l	$000000f0                       ; 240 bytes: one cycle of a sine (52 Hz at 12517 Hz)
	dc.b	$00,$03,$07,$0a,$0d,$11,$14,$17,$1a,$1e,$21,$24,$27,$2a,$2d,$30
	dc.b	$34,$37,$3a,$3d,$3f,$41,$45,$48,$4b,$4d,$50,$53,$55,$58,$5a,$5c
	dc.b	$5e,$60,$63,$65,$67,$68,$6b,$6d,$6e,$70,$71,$72,$74,$75,$76,$77
	dc.b	$78,$79,$7a,$7a,$7b,$7b,$7c,$7c,$7d,$7d,$7e,$7e,$7f,$7f,$7e,$7e
	dc.b	$7d,$7d,$7c,$7c,$7b,$7b,$79,$78,$77,$76,$75,$74,$72,$71,$70,$6f
	dc.b	$6e,$6d,$6b,$68,$67,$65,$63,$60,$5e,$5c,$5a,$58,$55,$53,$50,$4d
	dc.b	$4b,$48,$45,$41,$3f,$3d,$3a,$37,$34,$30,$2d,$2a,$27,$24,$21,$1e
	dc.b	$1a,$17,$14,$11,$0d,$0a,$07,$03,$00,$fd,$f9,$f6,$f3,$ef,$ec,$e9
	dc.b	$e6,$e2,$df,$dc,$d9,$d6,$d3,$d0,$cc,$c9,$c6,$c3,$c1,$bf,$bb,$b8
	dc.b	$b5,$b3,$b0,$ad,$ab,$a8,$a6,$a4,$a2,$a0,$9d,$9b,$99,$98,$95,$93
	dc.b	$92,$90,$8f,$8e,$8c,$8b,$8a,$89,$88,$87,$86,$86,$85,$85,$84,$84
	dc.b	$83,$83,$82,$82,$81,$81,$82,$82,$83,$83,$84,$84,$85,$85,$87,$88
	dc.b	$89,$8a,$8b,$8c,$8e,$8f,$90,$91,$92,$93,$95,$98,$99,$9b,$9d,$a0
	dc.b	$a2,$a4,$a6,$a8,$ab,$ad,$b0,$b3,$b5,$b8,$bb,$bf,$c1,$c3,$c6,$c9
	dc.b	$cc,$d0,$d3,$d6,$d9,$dc,$df,$e2,$e6,$e9,$ec,$ef,$f3,$f6,$f9,$fd

;------------------------------------------------------------------------------
; psg_mixer_tone_only and the two after it: PSG settings by channel (A, B, C) for the PSG
; sweeps: the mixer value that turns on only that channel's tone, its period register and
; its volume register.
;------------------------------------------------------------------------------
psg_mixer_tone_only:	; from: psg_tone_soft, psg_tone_loud
	dc.b	$fe,$fd,$fb
psg_period_registers:	; from: psg_tone_soft, psg_tone_loud
	dc.b	$00,$02,$04
psg_volume_registers:	; from: audio_test_step, psg_tone_soft, psg_tone_loud, fail_sweeps
	dc.b	$08,$09,$0a,$00                 ; and a pad byte

;------------------------------------------------------------------------------
; lmc_master_volume_steps: Microwire master volume commands (bits 0-8; $400 is added) for
; the mono tone: master volume 0, 16, 24, 32, 36, 40, 40, 40.
;------------------------------------------------------------------------------
lmc_master_volume_steps:	; from: dma_sound_test
	dc.w	$00c0,$00d0,$00d8,$00e0,$00e4,$00e8,$00e8,$00e8

;------------------------------------------------------------------------------
; lmc_left_volume_steps and lmc_right_volume_steps: Microwire left and right volume commands
; for the stereo tones: the left goes 0 to 20 while the right goes 20 to 0.
;------------------------------------------------------------------------------
lmc_left_volume_steps:	; from: dma_sound_test
	dc.w	$0140,$0148,$014a,$014c,$0150,$0154,$0154,$0154
lmc_right_volume_steps:	; from: dma_sound_test
	dc.w	$0114,$0114,$0114,$0110,$010c,$010a,$0108,$0100

;------------------------------------------------------------------------------
; lmc_treble_steps: treble values 7 down to 1 for the treble test ($80 is added).
;------------------------------------------------------------------------------
lmc_treble_steps:	; from: dma_sound_test
	dc.w	$0007,$0007,$0007,$0007,$0006,$0005,$0004,$0003
	dc.w	$0002,$0001

;------------------------------------------------------------------------------
; lmc_bass_steps: bass values 6 down to 1 for the bass test ($40 is added).
;------------------------------------------------------------------------------
lmc_bass_steps:	; from: dma_sound_test
	dc.w	$0006,$0006,$0006,$0006,$0006,$0005,$0004,$0003
	dc.w	$0002,$0001

;------------------------------------------------------------------------------
; Audio test texts.
;------------------------------------------------------------------------------
msg_listen_for_sweep:	; from: audio_test
	dc.b	'Listen for low to high sweep:',13,10,0

;------------------------------------------------------------------------------
; psg_channel_names: the channel names for the PSG sweeps, by channel.
;------------------------------------------------------------------------------
psg_channel_names:	; from: print_channel_name
	dc.l	msg_channel_a
	dc.l	msg_channel_b
	dc.l	msg_channel_c
msg_channel_a:
	dc.b	'Channel A',0
msg_channel_b:
	dc.b	'Channel B',0
msg_channel_c:
	dc.b	'Channel C',0
msg_testing_dma_sound:	; from: dma_sound_test
	dc.b	'Testing DMA sound. Check waveforms with oscilloscope.',13,10,0
msg_dma_sound_timed_out:	; from: dma_sound_test_restore
	dc.b	'DMA sound timed-out',13,10,0
msg_mono_1khz_tone:	; from: dma_sound_test
	dc.b	13,10,'Mono 1 kHz tone',13,10,0
msg_stereo_tones:	; from: dma_sound_test
	dc.b	'Stereo 1 kHz/500 Hz tones',13,10,0
msg_treble_attenuation:	; from: dma_sound_test
	dc.b	'Treble attenuation',13,10,0
msg_bass_attenuation:	; from: dma_sound_test
	dc.b	'Bass attenuation',13,10,0
msg_done:	; from: dma_sound_test
	dc.b	'DONE!',0

;------------------------------------------------------------------------------
; Timing test texts (T codes).
;------------------------------------------------------------------------------
msg_testing_mfp_glue_video:	; from: timing_test
	dc.b	'Testing MFP, Glue timing, Video',13,10,0
msg_mfp_timer:	; from: timing_test
	dc.b	13,10,'T0 MFP timer',13,10,0
msg_vertical_sync:	; from: timing_test
	dc.b	13,10,'T1 Vertical Sync',13,10,0
msg_horizontal_sync:	; from: timing_test
	dc.b	13,10,'T2 Horizontal Sync',13,10,0
msg_display_enable:	; from: timing_test
	dc.b	13,10,'T3 Display Enable',13,10,0
msg_video_counter:	; from: timing_test
	dc.b	13,10,'T4 Video Counter in Memory Controller',13,10,0
msg_psg_bus_test:	; from: timing_test
	dc.b	'T5 PSG Bus Test ',9,0
msg_1772_bus_test:	; from: timing_test
	dc.b	'T6 1772 Bus Test',9,0
	dc.b	$00

;------------------------------------------------------------------------------
; video_counter_test_bases: the screen addresses (in 256-byte units, high and middle byte) at
; which the T4 video counter test runs; entries at or above the top of RAM end the test.
;------------------------------------------------------------------------------
video_counter_test_bases:	; from: timing_test
	dc.w	$0010,$0011,$0012,$0014,$0018,$0020,$0040,$0080
	dc.w	$0100,$0200,$0300,$0400,$0500,$0600,$0700,$0800
	dc.w	$1000,$2000,$3000,$4000

;------------------------------------------------------------------------------
; dma_port_test_buffers: the buffer addresses for the DMA port test, indexed by $4f3 (steps of
; 4); the first long is also the first buffer; addresses at or above the top of RAM end it.
;------------------------------------------------------------------------------
dma_port_test_buffers:	; from: dma_port_test
	dc.l	$00001000,$00001800,$00002000,$00004000
	dc.l	$00008000,$00018000,$00020000,$00040000
	dc.l	$00050000,$00060000,$00070000,$00080000
	dc.l	$00090000,$000a0000,$000b0000,$000c0000
	dc.l	$000d0000,$000e0000,$000f0000

;------------------------------------------------------------------------------
; DMA port test texts (D codes).
;------------------------------------------------------------------------------
msg_dma_port_test:	; from: dma_port_test
	dc.b	'DMA Port Test',13,10,0
msg_dma_time_out:	; from: acsi_loopback_transfer
	dc.b	'D0 DMA time-out',13,10,0
msg_dma_count_error:	; from: acsi_loopback_transfer
	dc.b	'D1 DMA count error',13,10,0
msg_dma_data_mismatch:	; from: compare_dma_blocks
	dc.b	'D2 DMA data mismatch',13,10,0
msg_dma_not_responding:	; from: acsi_loopback_transfer
	dc.b	'D3 DMA not responding',13,10,0

;------------------------------------------------------------------------------
; printer_port_test_out: the 8 values written to the printer port by the port test; the
; fixture's answer, joined with them, must match printer_port_test_in.
;------------------------------------------------------------------------------
printer_port_test_out:	; from: printer_joystick_test
	dc.b	$f8,$f9,$fa,$fb,$fc,$fd,$fe,$ff
printer_port_test_in:	; from: printer_joystick_test
	dc.b	$01,$02,$04,$08,$10,$20,$40,$80

;------------------------------------------------------------------------------
; Printer and joystick port test texts (P and J codes).
;------------------------------------------------------------------------------
msg_printer_joystick_test:	; from: printer_joystick_test
	dc.b	'Printer/Joystick Port test',13,10,0
msg_printer_port_error:	; from: printer_joystick_test
	dc.b	'P0 Printer port error ',0
msg_busy_line_error:	; from: printer_joystick_test
	dc.b	'P1 Busy line error',13,10,0
msg_right_button_line_error:	; from: printer_joystick_test
	dc.b	'J4 Right button line error',13,10,0
msg_left_button_line_error:	; from: printer_joystick_test
	dc.b	'J3 Left button line error',13,10,0
msg_joystick_port_0_error:	; from: printer_joystick_test
	dc.b	'J0 Joystick Port 0 error',13,10,0
msg_joystick_port_1_error:	; from: printer_joystick_test
	dc.b	'J1 Joystick Port 1 error',13,10,0
msg_joystick_time_out:	; from: printer_joystick_test
	dc.b	'J2 Joystick time-out',13,10,0
msg_connect_mono_monitor:	; from: mono_monitor_test
	dc.b	'Connect monochrome monitor',13,10,0
msg_disconnect_mono_monitor:
	dc.b	'Disconnect monochrome monitor',13,10,0 ; no reference
msg_press_key_for_menu:
	dc.b	'Press any key to return to menu',13,10,0 ; no reference

;------------------------------------------------------------------------------
; floppy_exerciser_tracks: the 80 tracks 0-79 in a jumbled order, read in turn by the disk
; exerciser so that every read needs a long seek.
;------------------------------------------------------------------------------
floppy_exerciser_tracks:	; from: floppy_exerciser
	dc.b	$00,$4f,$2e,$20,$01,$0a,$3c,$16,$43,$2c,$3b,$2d,$11,$21,$2f,$14
	dc.b	$4a,$15,$42,$44,$12,$48,$38,$47,$10,$49,$04,$22,$45,$1b,$3a,$39
	dc.b	$06,$46,$27,$30,$35,$08,$4b,$4c,$1c,$1d,$26,$4d,$17,$09,$28,$41
	dc.b	$1a,$3d,$4e,$25,$0c,$34,$13,$31,$0e,$0f,$36,$23,$24,$1e,$0d,$05
	dc.b	$33,$07,$3f,$19,$37,$3e,$0b,$40,$2a,$29,$18,$32,$1f,$2b,$03,$02

;------------------------------------------------------------------------------
; floppy_quick_test_tracks: tracks 0, 1 and 79, formatted, written and read by the quick test.
;------------------------------------------------------------------------------
floppy_quick_test_tracks:	; from: quick_test_tracks
	dc.b	$00,$01,$4f

;------------------------------------------------------------------------------
; floppy_interchange_tracks: tracks 0, 39 and 79, for the disk interchange test.
;------------------------------------------------------------------------------
floppy_interchange_tracks:	; from: floppy_interchange
	dc.b	$00,$27,$4f

;------------------------------------------------------------------------------
; Floppy test texts (F codes).
;------------------------------------------------------------------------------
floppy_menu_text:	; from: floppy_menu
	dc.b	9,'Floppy disk drive routines:',13,10,9
	dc.b	'(WARNING--all choices except 2,6,7 write to the disk)',13,10,9
	dc.b	'1 Quick Test',13,10,9,'2 Read Alignment Disk',13,10,9
	dc.b	'3 Disk Interchange Test',13,10,9,'4 Disk Exerciser',13,10,9
	dc.b	'5 Check copy protect tracks (80-82)',13,10,9,'6 Test Speed',13,10,9
	dc.b	'7 Install disk drives',13,10,0
msg_drive_type_menu:	; from: floppy_install_drives
	dc.b	'1  Single sided',13,10,'2  Double sided',13,10,'3  High Density',13,10
	dc.b	'Any other key will de-install this drive.',13,10,0
msg_enter_track_number:	; from: floppy_alignment
	dc.b	'Enter track number (if none entered, default=40): ',0
msg_select_sides:
	dc.b	'Select single sided (1) or double sided (2)',13,10,0 ; no reference
msg_read_alignment_disk:	; from: floppy_alignment
	dc.b	'Read analog alignment disk',13,10
msg_disk_a_or_b:	; from: floppy_exerciser, floppy_copy_protect, floppy_speed_test
	dc.b	'Disk A or B?',13,10,0
msg_disk_exerciser:	; from: floppy_exerciser
	dc.b	'Disk Exerciser',13,10,0
msg_disk_interchange_test:	; from: floppy_interchange
	dc.b	'Disk interchange test',13,10
	dc.b	'Insert disks in both drives, hit any key to start',13,10,0
msg_swap_disks:	; from: floppy_interchange
	dc.b	'Swap disks A and B, Hit any key when ready',13,13,10,0
msg_disks_not_swapped:	; from: floppy_interchange
	dc.b	'Disks were not swapped!',13,10,0
msg_esc_quit_key_repeat:	; from: floppy_interchange
	dc.b	'Hit esc to quit, any other key to repeat',13,10,0
msg_checking_drive_type:	; from: detect_drive_types
	dc.b	'Checking drive type...',13,10,0
msg_disk_a:                                     ; from: floppy_quick_test, show_drive_lines, floppy_install_drives,
                                                ;   print_drive_name, print_a_not_selected
	dc.b	'Disk A: ',0
msg_disk_b:                                     ; from: floppy_quick_test, show_drive_lines, floppy_install_drives,
                                                ;   print_drive_name, print_b_not_selected
	dc.b	'Disk B: ',0
msg_cannot_write_drive_a:	; from: detect_drive_types
	dc.b	'Cannot write drive A',13,10,0
msg_cannot_write_drive_b:	; from: detect_drive_types
	dc.b	'Cannot write drive B',13,10,0
msg_high_density:	; from: floppy_quick_test
	dc.b	'High Density ',13,10,0
msg_single_sided:	; from: floppy_quick_test
	dc.b	'SS ',13,10,0
msg_double_sided:	; from: floppy_quick_test
	dc.b	'DS ',13,10,0
msg_no_floppies:	; from: detect_drive_types
	dc.b	'No floppies ',13,10,0
msg_sector:	; from: print_sector_number, print_floppy_error
	dc.b	'Sector ',0
msg_track:	; from: print_track_number
	dc.b	'Track ',0
msg_side:	; from: print_side_number
	dc.b	'Side ',0
msg_formatting:	; from: format_track_checked
	dc.b	'Formatting ',0
msg_writing:	; from: write_track_checked
	dc.b	'Writing    ',0
msg_reading:	; from: floppy_alignment, read_track_checked
	dc.b	'Reading    ',0
msg_check_tracks_80_82:	; from: floppy_copy_protect
	dc.b	'Check Tracks 80-82',13,10,0
msg_copy_protect_pass:	; from: floppy_copy_protect
	dc.b	'Copy protect tracks PASS                         ',13,10,0
msg_copy_protect_fail:	; from: floppy_copy_protect
	dc.b	'Copy protect tracks FAIL                         ',13,10,0
msg_floppy_speed_test:	; from: floppy_speed_test
	dc.b	'Floppy disk speed test',13,10,0
msg_testing_speed:	; from: floppy_speed_test
	dc.b	'Testing speed',9,'Allowable range = 196 - 204 milliseconds/revolution'
	dc.b	13,10,0
msg_index_time_out:	; from: floppy_speed_test
	dc.b	'Time-out waiting for index',13,10,0
msg_speed_header:	; from: floppy_speed_test
	dc.b	'Max      Min      Current speed',0
msg_soft_error:	; from: write_track_checked, read_track_checked
	dc.b	'Soft Error',13,10,0
msg_bad_sector:	; from: print_floppy_error
	dc.b	'Bad Sector: ',0
msg_not_selected:	; from: print_a_not_selected
	dc.b	'F0 Not selected ',0
msg_side_0:
	dc.b	'Side 0 ',0                     ; no reference
msg_side_1:
	dc.b	'Side 1 ',0                     ; no reference
msg_error_formatting:	; from: floppy_interchange
	dc.b	'Error formating ',0
msg_error_writing:	; from: floppy_interchange, print_floppy_error
	dc.b	'Error writing',13,10,0
msg_error_reading:	; from: floppy_interchange, print_floppy_error
	dc.b	'Error reading',13,10,0
msg_seek_error:	; from: print_floppy_error
	dc.b	'F4 Seek error ',0
msg_write_protected:	; from: print_floppy_error
	dc.b	'F5 Write Protected ',0
msg_read_compare_error:	; from: compare_sector_data
	dc.b	'F6 Read compare error ',0
msg_floppy_dma_error:	; from: print_floppy_error
	dc.b	'F7 DMA error ',0
msg_floppy_dma_count_error:	; from: print_floppy_error
	dc.b	'F8 DMA count error ',0
msg_crc_error:	; from: print_floppy_error
	dc.b	'F9 CRC error ',0
msg_record_not_found:	; from: print_floppy_error
	dc.b	'FA Record not found ',0
msg_lost_data:	; from: print_floppy_error
	dc.b	'FB Lost data ',0
msg_side_select_error:	; from: quick_test_drive
	dc.b	'FC Side select error--single sided drive',13,10,0
msg_drive_not_ready:	; from: floppy_alignment, print_floppy_error
	dc.b	'FD Drive not ready ',0
msg_stopped_esc_quit:	; from: floppy_alignment
	dc.b	'Stopped. ESC to quit, any other key to continue.',0
msg_hard_error:	; from: write_track_checked, read_track_checked
	dc.b	'Hard error',13,10,0
msg_fail:	; from: floppy_quick_test
	dc.b	'Fail ',0
	dc.b	$00

;------------------------------------------------------------------------------
; BLiTTER test texts (G codes).
;------------------------------------------------------------------------------
msg_testing_blitter:	; from: blit_short_test, blit_long_test, blit_long_set_up
	dc.b	'Testing Blitter',13,10,0
msg_blit_halftone_ram:	; from: blit_error_messages
	dc.b	'G1 halftone RAM',13,10,0
msg_blit_endmask:	; from: blit_error_messages
	dc.b	'G2 endmask',13,10,0
msg_blit_operation:	; from: blit_error_messages
	dc.b	'G3 operation ',13,10,0
msg_blit_halftone_op:	; from: blit_error_messages
	dc.b	'G4 halftone op',13,10,0
msg_blit_skew:	; from: blit_error_messages
	dc.b	'G5 skew',13,10,0
msg_blit_reverse:	; from: blit_error_messages
	dc.b	'G6 reverse blt',13,10,0
msg_blit_fxsr:	; from: blit_error_messages
	dc.b	'G7 force extra source read',13,10,0
msg_blit_smudge:	; from: blit_error_messages
	dc.b	'G8 smudge',13,10,0
msg_blit_x_count:	; from: blit_error_messages
	dc.b	'G9 x count',13,10,0
msg_blit_y_count:	; from: blit_error_messages
	dc.b	'G10 y count',13,10,0
msg_blit_time_out:	; from: blit_error_messages
	dc.b	'G11 time-out',13,10,0
msg_blit_address_count:	; from: blit_error_messages
	dc.b	'G12 address count',13,10,0
msg_no_blitter:	; from: blit_short_test, blit_long_test
	dc.b	'No Blitter installed',13,10,0

;------------------------------------------------------------------------------
; long_blit_word_pair: two words (0, 3) whose address the long BLiT test puts at $32e.
;------------------------------------------------------------------------------
long_blit_word_pair:	; from: blit_long_set_up
	dc.w	$0000,$0003

;------------------------------------------------------------------------------
; long_blit_shape_1 and long_blit_shape_2: two triangles for the long BLiT test, x,y corner
; pairs with the first corner repeated at the end; copied to $3bc and $3cc.
;------------------------------------------------------------------------------
long_blit_shape_1:	; from: blit_long_set_up
	dc.w	$00a0,$0064,$00a0,$0082,$0050,$0082,$00a0,$0064 ; (160,100) (160,130) (80,130) (160,100)
long_blit_shape_2:	; from: blit_long_set_up
	dc.w	$00a0,$0064,$00a0,$0096,$001e,$0096,$00a0,$0064 ; (160,100) (160,150) (30,150) (160,100)

;------------------------------------------------------------------------------
; long_blit_fill_pattern: the 16-line fill pattern for the long BLiT test (address at $358).
;------------------------------------------------------------------------------
long_blit_fill_pattern:	; from: blit_long_set_up
	dc.w	$0000,$5555,$aaaa,$5555,$ffff,$5555,$5555,$ffff
	dc.w	$5555,$0000,$aaaa,$0000,$1c73,$e38c,$ff00,$00ff

;------------------------------------------------------------------------------
; msg_replace_blitter: a blank line, then the bus error message of the long BLiT test.
;------------------------------------------------------------------------------
msg_replace_blitter:	; from: blit_long_bus_error
	dcb.w	23,$2020
	dc.b	13,10,'-------->      Replace Blitter     <----------',13,10
	dc.b	'>>>> Bus error has occurred during BLiT test! <<<<<',13,10,0

;------------------------------------------------------------------------------
; acsi_stop_unit: ACSI START/STOP UNIT command blocks (6 bytes; the device number is ORed into
; the first). The first stops the unit (parks the heads) for $75e6; the second starts it
; and has no reference.
;------------------------------------------------------------------------------
acsi_stop_unit:	; from: hd_park_heads
	dc.b	$1b,$00,$00,$00,$00,$00
acsi_start_unit:
	dc.b	$1b,$00,$00,$00,$01,$00

;------------------------------------------------------------------------------
; Hard disk exerciser texts.
;------------------------------------------------------------------------------
hd_exerciser_title:	; from: hd_test
	dc.b	9,9,9,'Hard Disk DMA Exerciser',13,10
	dc.b	'WARNING: abnormal termination may result in lost data.',13,10
	dc.b	'Hit <Esc> key to stop program.',13,10,0
msg_hd_commands:	; from: hd_test
	dc.b	'Q=quit, P=Park heads, S=start',13,10,0
msg_hd_cycle:	; from: hd_print_cycle
	dc.b	' Cycle: ',0
msg_writing_cylinder:	; from: hd_test
	dc.b	'Writing cylinder   ',0
msg_reading_cylinder:	; from: hd_test
	dc.b	'Reading cylinder   ',0
msg_read_error_on_sector:	; from: hd_test
	dc.b	'Read error on sector  ',0
msg_write_error_on_sector:
	dc.b	'Write error on sector ',0      ; no reference
msg_hd_data_compare_error:	; from: hd_test
	dc.b	'Data compare error (wrote, read, hex offset): ',0
msg_controller_not_responding:	; from: acsi_wait
	dc.b	'Controller not responding',13,10,0
msg_operation_timed_out:	; from: acsi_wait
	dc.b	'Operation timed-out',13,10,0
msg_command_error:	; from: acsi_command_error
	dc.b	'Command error',13,10,0
msg_status:	; from: acsi_command_error
	dc.b	' Status = ',0
msg_hd_dma_count_error:
	dc.b	'DMA count error',13,10,0       ; no reference
msg_blank_29:
	dcb.w	14,$2020                        ; 29 spaces; no reference
	dc.w	$2000
msg_hit_esc_to_stop:	; from: hd_status_line
	dc.b	'   <<  Hit <Esc> key to stop.  >>   ',0
msg_error_restoring_data:	; from: hd_restore_data
	dc.b	'Error restoring data',13,10,0
msg_stopped_press_return:
	dc.b	'Stopped. Press RETURN to continue.',13,10,0 ; no reference
msg_hd_stopped_menu:	; from: hd_stopped_menu
	dc.b	'Stopped. RETURN=continue, S=restart, Q=quit, P=park heads',0
msg_heads_not_parked:	; from: hd_park_heads
	dc.b	'Error -- Heads not parked!',13,10,0
msg_bad_sector_list_error:
	dc.b	'Error -- unable to write bad sector list',13,10,0 ; no reference
msg_heads_are_parked:	; from: hd_park_heads
	dc.b	13,10,'   ',13,10,'          HEADS ARE PARKED',13,10,0
msg_dma_address_error:	; from: hd_test
	dc.b	'DMA address error -- Data written outside data buffers',0

;------------------------------------------------------------------------------
; day_names: day of the week names by the clock's day register (1 = Sunday; 0 also Sunday).
;------------------------------------------------------------------------------
day_names:	; from: rtc_show_time
	dc.l	msg_sun
	dc.l	msg_sun
	dc.l	msg_mon
	dc.l	msg_tue
	dc.l	msg_wed
	dc.l	msg_thu
	dc.l	msg_fri
	dc.l	msg_sat
msg_sun:
	dc.b	'SUN',0
msg_mon:
	dc.b	'MON',0
msg_tue:
	dc.b	'TUE',0
msg_wed:
	dc.b	'WED',0
msg_thu:
	dc.b	'THU',0
msg_fri:
	dc.b	'FRI',0
msg_sat:
	dc.b	'SAT',0

;------------------------------------------------------------------------------
; Real-time clock test texts (C codes).
;------------------------------------------------------------------------------
msg_testing_rtc:	; from: rtc_test
	dc.b	'Testing real-time clock',13,10,0
msg_rtc_passed:
	dc.b	'Real-time clock passed ',13,10,0 ; no reference
msg_no_clock:	; from: rtc_test
	dc.b	'C0 No clock installed',13,10,0
msg_clock_increment_error:	; from: rtc_test
	dc.b	'C1 clock increment error',13,10,0
msg_enter_time:	; from: rtc_set_from_input
	dc.b	'Enter time: hhmmss',13,10,0
msg_enter_date:	; from: rtc_set_from_input
	dc.b	'Enter date: mmddyy',13,10,0
msg_enter_day:	; from: rtc_set_from_input
	dc.b	'Day: Sun=1 Mon=2 Tue=3 Wed=4 Thr=5 Fri=6 Sat=7',13,10,0

;------------------------------------------------------------------------------
; rtc_test_1_start and the three after it: RP5C15 clock register values for the increment
; test, one word per register (the low byte goes to the odd address): seconds, minutes and
; hours (units, tens), day of week, date, month and year (units, tens). Each start time is
; set, and one second later the clock must read the end time.
;------------------------------------------------------------------------------
rtc_test_1_start:	; from: rtc_test
	dc.w	$0009,$0005,$0009,$0005,$0003,$0002,$0007,$0001 ; 23:59:59, day 7, 31/12/99
	dc.w	$0003,$0002,$0001,$0009,$0009
rtc_test_1_end:	; from: rtc_test
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0001,$0001 ; 00:00:00, day 1, 01/01/00
	dc.w	$0000,$0001,$0000,$0000,$0000
rtc_test_2_start:	; from: rtc_test
	dc.w	$0009,$0005,$0009,$0005,$0003,$0002,$0002,$0009 ; 23:59:59, day 2, 19/06/87
	dc.w	$0001,$0006,$0000,$0007,$0008
rtc_test_2_end:	; from: rtc_test
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0003,$0000 ; 00:00:00, day 3, 20/06/87
	dc.w	$0002,$0006,$0000,$0007,$0008

;------------------------------------------------------------------------------
; rtc_register_masks: the bits that count in each clock register, in the same order.
;------------------------------------------------------------------------------
rtc_register_masks:	; from: rtc_read
	dc.w	$000f,$0007,$000f,$0007,$000f,$0003,$0007,$000f
	dc.w	$0003,$000f,$0001,$000f,$000f

;------------------------------------------------------------------------------
; scc_vectors: SCC interrupt handlers, copied to $180, $188 ... $1b8 (every other vector from
; vector $60), status in vector bits 1-3.
;------------------------------------------------------------------------------
scc_vectors:	; from: scc_test
	dc.l	scc_b_tx_int                    ; $180 channel B transmit buffer empty
	dc.l	scc_b_ext_int                   ; $188 channel B external/status
	dc.l	scc_b_rx_int                    ; $190 channel B receive character
	dc.l	scc_special_int                 ; $198 channel B special receive
	dc.l	scc_a_tx_int                    ; $1a0 channel A transmit buffer empty
	dc.l	scc_a_ext_int                   ; $1a8 channel A external/status
	dc.l	scc_a_rx_int                    ; $1b0 channel A receive character
	dc.l	scc_special_int                 ; $1b8 channel A special receive

;------------------------------------------------------------------------------
; scc_error_messages: SCC test error texts, one for each bit of the error byte ($8456).
;------------------------------------------------------------------------------
scc_error_messages:	; from: scc_test
	dc.l	msg_transmitter_time_out        ; bit 0: transmitter time-out
	dc.l	msg_receiver_time_out           ; bit 1: receiver time-out
	dc.l	msg_bad_index                   ; bit 2: bad index
	dc.l	msg_bad_index                   ; bit 3: bad index
	dc.l	msg_parity_error                ; bit 4: parity error
	dc.l	msg_overrun                     ; bit 5: overrun
	dc.l	msg_framing_error               ; bit 6: framing error
	dc.l	msg_data_compare_error          ; bit 7: data compare error

;------------------------------------------------------------------------------
; scc_modem_error_messages: SCC modem control error texts, one for each bit. The second
; eight entries (from scc_dma_error_messages) are never reached: $8456 stops at bit 7.
;------------------------------------------------------------------------------
scc_modem_error_messages:	; from: scc_test
	dc.l	msg_dtr_dcd                     ; bit 0: DTR-DCD
	dc.l	msg_dtr_dsr                     ; bit 1: DTR-DSR
	dc.l	msg_rts_cts                     ; bit 2: RTS-CTS
	dc.l	msg_bad_index                   ; bits 3-7: bad index
	dc.l	msg_bad_index
	dc.l	msg_bad_index
	dc.l	msg_bad_index
	dc.l	msg_bad_index

;------------------------------------------------------------------------------
; scc_dma_error_messages: error texts for an SCC DMA test that is not in this version.
;------------------------------------------------------------------------------
scc_dma_error_messages:
	dc.l	msg_transmitter_time_out
	dc.l	msg_receiver_time_out
	dc.l	msg_non_zero_dma_count
	dc.l	msg_scc_dma_bus_error
	dc.l	msg_parity_error
	dc.l	msg_overrun
	dc.l	msg_framing_error
	dc.l	msg_data_compare_error

;------------------------------------------------------------------------------
; SCC test texts.
;------------------------------------------------------------------------------
msg_testing_scc:	; from: scc_test
	dc.b	'Testing SCC',13,10,0
msg_scc_dma_output:
	dc.b	'SCC DMA output:',13,10,0       ; no reference
msg_scc_dma_input:
	dc.b	'SCC DMA input:',13,10,0        ; no reference
msg_non_zero_dma_count:	; from: scc_dma_error_messages
	dc.b	'Non-zero DMA count',13,10,0
msg_scc_dma_bus_error:	; from: scc_dma_error_messages
	dc.b	'DMA Bus Error',13,10,0
msg_crlf:
	dc.w	$0d0a                           ; no reference
	dc.b	$00
msg_bad_index:	; from: scc_error_messages, scc_modem_error_messages
	dc.b	'bad index--programming error',13,10,0
msg_scc_a_internal_loopback:	; from: scc_test
	dc.b	'SCC A internal loopback: ',13,10,0
msg_scc_b_internal_loopback:	; from: scc_test
	dc.b	'SCC B internal loopback: ',13,10,0
msg_port_a_async_mode:	; from: scc_test
	dc.b	'Port A async mode: ',13,10,0
msg_port_b_async_mode:	; from: scc_test
	dc.b	'Port B async mode: ',13,10,0
msg_transmitter_time_out:	; from: scc_error_messages, scc_dma_error_messages
	dc.b	'Transmitter time-out',13,10,0
msg_receiver_time_out:	; from: scc_error_messages, scc_dma_error_messages
	dc.b	'Receiver time-out',13,10,0
msg_overrun:	; from: scc_error_messages, scc_dma_error_messages
	dc.b	'Overrun',13,10,0
msg_framing_error:	; from: scc_error_messages, scc_dma_error_messages
	dc.b	'Framing error',13,10,0
msg_parity_error:	; from: scc_error_messages, scc_dma_error_messages
	dc.b	'Parity error',13,10,0
msg_data_compare_error:	; from: scc_error_messages, scc_dma_error_messages
	dc.b	'Data compare error',13,10,0
msg_port_a_modem_control_error:	; from: scc_test
	dc.b	'Port A modem control error: ',0
msg_port_b_modem_control_error:	; from: scc_test
	dc.b	'Port B modem control error: ',0
msg_scc_interrupt_error:	; from: scc_test
	dc.b	'SCC interrupt error:',13,10,0
msg_dtr_dcd:	; from: scc_modem_error_messages
	dc.b	'DTR-DCD ',0
msg_dtr_dsr:	; from: scc_modem_error_messages
	dc.b	'DTR-DSR ',0
msg_rts_cts:	; from: scc_modem_error_messages
	dc.b	'RTS-CTS ',0
msg_port_a_no_loopback:	; from: scc_test
	dc.b	'Port A has no loopback connector',13,10,0
msg_port_b_no_loopback:	; from: scc_test
	dc.b	'Port B has no loopback connector',13,10,0
msg_lan_no_loopback:	; from: scc_test
	dc.b	'LAN has no loopback connector',13,10,0
msg_scc_test_done:
	dc.b	'SCC test done',13,10,0         ; no reference
msg_no_tx_interrupt:	; from: scc_interrupt_test
	dc.b	'No Tx interrupt',13,10,0
msg_no_rx_interrupt:	; from: scc_interrupt_test
	dc.b	'No Rx interrupt',13,10,0
msg_lan_dcd_without_rts:	; from: scc_lan_lines
	dc.b	'LAN ERROR: DCD IS ACTIVE WITHOUT RTS ON',13,10,0
msg_lan_dcd_not_responding:	; from: scc_lan_lines
	dc.b	'LAN ERROR: RTS IS ACTIVE BUT DCD IS NOT RESPONDING',13,10,0

;------------------------------------------------------------------------------
; scc_setup_loopback, scc_setup_break and scc_setup_async: SCC register/value pairs (13
; pairs, written to the channel's control register): WR4 $44 (x16 clock, 1 stop bit, no
; parity), receiver off, WR5 transmitter settings, WR9-WR11 (clocks from the baud rate
; generator), time constant 24 (9600 baud from the 8 MHz PCLK), baud rate generator on,
; receiver on, WR5 with the transmitter on, WR15 0.
; scc_setup_loopback (internal loopback test): WR5 $60/$68, 8 bits, DTR and RTS off.
;------------------------------------------------------------------------------
scc_setup_loopback:	; from: scc_init_channel
	dc.b	$04,$44,$03,$c0,$05,$60,$09,$00,$0a,$00,$0b,$50,$0c,$18,$0d,$00
	dc.b	$0e,$02,$0e,$03,$03,$c1,$05,$68,$0f,$00

;------------------------------------------------------------------------------
; scc_setup_break: WR5 $70/$78, 8 bits with send break.
;------------------------------------------------------------------------------
scc_setup_break:	; from: scc_set_break_mode
	dc.b	$04,$44,$03,$c0,$05,$70,$09,$00,$0a,$00,$0b,$50,$0c,$18,$0d,$00
	dc.b	$0e,$02,$0e,$03,$03,$c1,$05,$78,$0f,$00

;------------------------------------------------------------------------------
; scc_setup_async (async and modem control tests): WR5 $e2/$ea, 8 bits, DTR and RTS on.
;------------------------------------------------------------------------------
scc_setup_async:	; from: scc_set_async_mode
	dc.b	$04,$44,$03,$c0,$05,$e2,$09,$00,$0a,$00,$0b,$50,$0c,$18,$0d,$00
	dc.b	$0e,$02,$0e,$03,$03,$c1,$05,$ea,$0f,$00

;------------------------------------------------------------------------------
; vme_scc_vectors: interrupt handlers for the Xycom VME SCC card, put at $300, $308 ... $338
; (the old vectors are kept at $c72).
;------------------------------------------------------------------------------
vme_scc_vectors:	; from: vme_interrupt_test
	dc.l	vme_b_tx_int
	dc.l	vme_b_ext_int
	dc.l	vme_b_rx_int
	dc.l	vme_b_special_int
	dc.l	vme_a_tx_int
	dc.l	vme_a_ext_int
	dc.l	vme_a_rx_int
	dc.l	vme_a_special_int

;------------------------------------------------------------------------------
; vme_interrupt_counts_expected: the interrupt counts the VME interrupt test must find at
; $c9a, one long for each handler: only the seventh counts, $2000 interrupts.
;------------------------------------------------------------------------------
vme_interrupt_counts_expected:	; from: vme_interrupt_test
	dc.l	$00000000,$00000000,$00000000,$00000000
	dc.l	$00000000,$00000000,$00002000,$00000000

;------------------------------------------------------------------------------
; VME test texts.
;------------------------------------------------------------------------------
msg_vme_interrupts:	; from: vme_interrupt_test
	dc.b	'Generate VMEbus Interrupts using a Xycom SCC Card',13,10,0
msg_initializing_8530s:
	dc.b	' initializing 8530s',13,10,0   ; no reference
msg_interrupt_vectors_established:
	dc.b	' interrupt vectors established',13,10,0 ; no reference
msg_8530_loopback:
	dc.b	' 8530 in loopback mode',13,10,0 ; no reference
msg_interrupt_vector_set:
	dc.b	' interrupt vector set to 0x',0 ; no reference
msg_enable_vme_level_6:
	dc.b	' enable level 6 VME interrupts',13,10,0 ; no reference
msg_pass_hex:
	dc.b	'Pass: 0x',0                    ; no reference
msg_vme_ram_test:	; from: vme_test
	dc.b	'VME RAM test ',13,10,0
msg_install_other_vme_pcb:
	dc.b	13,10,10,10,9,9,'To complete this test',13,10,9,9,9 ; no reference
	dc.b	'1.) Power down the system',13,10,9,9,9
	dc.b	'2.) Install the other VME test PCB',13,10,9,9,9
	dc.b	'3.) Power the system up and the test will continue',13,10,0
msg_end_of_vme_tests:
	dc.b	13,10,10,10,9,9,'This ends the VME tests',13,10,0 ; no reference
msg_no_vme_board:	; from: vme_interrupt_test
	dc.b	'No VME board found in system',13,10,0

;------------------------------------------------------------------------------
; vme_scc_setup: 40 bytes of SCC register/value pairs written to each of the four control
; registers of the Xycom card ($DF0001/5/9/D).
;------------------------------------------------------------------------------
vme_scc_setup:	; from: vme_interrupt_test
	dc.b	$04,$44,$03,$c0,$05,$e2,$01,$44,$06,$00,$07,$00,$09,$00,$0a,$00
	dc.b	$0b,$56,$0c,$04,$0d,$00,$0e,$02,$0e,$03,$03,$c1,$05,$ea,$0f,$00
	dc.b	$00,$10,$00,$10,$09,$00,$01,$00,$00

;------------------------------------------------------------------------------
; font_8x8: the 8x8 font for low and medium resolution, 128 characters, stored by scan
; line: 8 lines of 128 bytes (one byte per character).
;------------------------------------------------------------------------------
font_8x8:	; from: text_last_row_by_res
	dc.b	$00,$18,$3c,$18,$18,$ff,$3c,$e7,$01,$d8,$c0,$cc,$f8,$f0,$0d,$b0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$00,$03,$c0,$48
	dc.b	$00,$00,$00,$00,$18,$00,$1c,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$06,$00,$60,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0e,$18,$70,$00,$10
	dc.b	$00,$3c,$24,$1c,$38,$ff,$42,$c3,$03,$d8,$c0,$cc,$c0,$c0,$0d,$b0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$36,$60,$1c,$07,$e0,$92
	dc.b	$00,$18,$66,$66,$3e,$66,$36,$18,$0e,$70,$66,$18,$00,$00,$00,$06
	dc.b	$3c,$18,$3c,$7e,$0c,$7e,$3c,$7e,$3c,$3c,$00,$00,$0c,$00,$30,$3c
	dc.b	$3c,$18,$7c,$3c,$78,$7e,$7e,$3e,$66,$7e,$06,$66,$60,$63,$66,$3c
	dc.b	$7c,$3c,$7c,$3c,$7e,$66,$66,$63,$66,$66,$7e,$1e,$40,$78,$08,$00
	dc.b	$c0,$00,$60,$00,$06,$00,$0e,$00,$60,$18,$06,$60,$38,$00,$00,$00
	dc.b	$00,$00,$00,$00,$18,$00,$00,$00,$00,$00,$00,$18,$18,$18,$30,$18
	dc.b	$00,$66,$24,$f6,$6f,$ff,$99,$a5,$06,$f8,$de,$78,$fe,$df,$0d,$b0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7f,$78,$1c,$0e,$70,$24
	dc.b	$00,$18,$66,$ff,$60,$6c,$1c,$18,$1c,$38,$3c,$18,$00,$00,$00,$0c
	dc.b	$66,$38,$66,$0c,$1c,$60,$60,$06,$66,$66,$18,$18,$18,$7e,$18,$66
	dc.b	$66,$3c,$66,$66,$6c,$60,$60,$60,$66,$18,$06,$6c,$60,$77,$76,$66
	dc.b	$66,$66,$66,$60,$18,$66,$66,$63,$66,$66,$0c,$18,$60,$18,$1c,$00
	dc.b	$60,$3c,$60,$3c,$06,$3c,$18,$3e,$60,$00,$00,$60,$18,$66,$7c,$3c
	dc.b	$7c,$3e,$7c,$3e,$7e,$66,$66,$63,$66,$66,$7e,$18,$18,$18,$79,$1c
	dc.b	$00,$c3,$e7,$83,$c1,$ff,$a1,$7e,$8c,$df,$d8,$7f,$d8,$db,$0d,$b0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7f,$60,$77,$1c,$38,$48
	dc.b	$00,$18,$66,$66,$3c,$18,$38,$18,$18,$18,$ff,$7e,$00,$7e,$00,$18
	dc.b	$6e,$18,$0c,$18,$3c,$7c,$7c,$0c,$3c,$3e,$18,$18,$30,$00,$0c,$0c
	dc.b	$6e,$66,$7c,$60,$66,$7c,$7c,$60,$7e,$18,$06,$78,$60,$7f,$7e,$66
	dc.b	$66,$66,$66,$3c,$18,$66,$66,$6b,$3c,$3c,$18,$18,$30,$18,$36,$00
	dc.b	$30,$06,$7c,$60,$3e,$66,$3e,$66,$7c,$38,$06,$6c,$18,$7f,$66,$66
	dc.b	$66,$66,$66,$60,$18,$66,$66,$6b,$3c,$66,$0c,$30,$18,$0c,$4f,$1e
	dc.b	$00,$e7,$c3,$83,$c1,$ff,$a1,$7e,$d8,$de,$fe,$36,$de,$ff,$0d,$b0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3e,$7e,$77,$38,$1c,$92
	dc.b	$00,$18,$00,$66,$06,$30,$6f,$00,$18,$18,$3c,$18,$00,$00,$00,$30
	dc.b	$76,$18,$18,$0c,$6c,$06,$66,$18,$66,$06,$00,$00,$18,$00,$18,$18
	dc.b	$6e,$66,$66,$60,$66,$60,$60,$6e,$66,$18,$06,$78,$60,$6b,$7e,$66
	dc.b	$7c,$66,$7c,$06,$18,$66,$66,$7f,$3c,$18,$30,$18,$18,$18,$63,$00
	dc.b	$00,$3e,$66,$60,$66,$7e,$18,$66,$66,$18,$06,$78,$18,$7f,$66,$66
	dc.b	$66,$66,$60,$3c,$18,$66,$66,$7f,$18,$66,$18,$18,$18,$18,$06,$1c
	dc.b	$00,$24,$66,$f6,$6f,$ff,$99,$a5,$70,$06,$18,$06,$18,$1e,$19,$98
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1c,$18,$08,$70,$0e,$24
	dc.b	$00,$00,$00,$ff,$7c,$66,$66,$00,$1c,$38,$66,$18,$18,$00,$18,$60
	dc.b	$66,$18,$30,$66,$7e,$66,$66,$30,$66,$0c,$18,$18,$0c,$7e,$30,$00
	dc.b	$60,$7e,$66,$66,$6c,$60,$60,$66,$66,$18,$66,$6c,$60,$63,$6e,$66
	dc.b	$60,$6c,$6c,$06,$18,$66,$3c,$77,$66,$18,$60,$18,$0c,$18,$00,$00
	dc.b	$00,$66,$66,$60,$66,$60,$18,$3e,$66,$18,$06,$6c,$18,$6b,$66,$66
	dc.b	$7c,$3e,$60,$06,$18,$66,$3c,$3e,$3c,$3e,$30,$18,$18,$18,$00,$18
	dc.b	$00,$24,$3c,$1c,$38,$ff,$42,$c3,$20,$06,$18,$06,$18,$1b,$39,$9c
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$1e,$1c,$e0,$07,$48
	dc.b	$00,$18,$00,$66,$18,$46,$3b,$00,$0e,$70,$00,$00,$18,$00,$18,$40
	dc.b	$3c,$7e,$7e,$3c,$0c,$3c,$3c,$30,$3c,$38,$18,$18,$06,$00,$60,$18
	dc.b	$3e,$66,$7c,$3c,$78,$7e,$60,$3e,$66,$7e,$3c,$66,$7e,$63,$66,$3c
	dc.b	$60,$36,$66,$3c,$18,$7e,$18,$63,$66,$18,$7e,$1e,$06,$78,$00,$ff
	dc.b	$00,$3e,$7c,$3c,$3e,$3c,$18,$06,$66,$3c,$06,$66,$3c,$63,$66,$3c
	dc.b	$60,$06,$60,$7c,$0e,$3e,$18,$36,$66,$0c,$7e,$0e,$18,$70,$00,$10
	dc.b	$00,$3c,$18,$18,$18,$ff,$3c,$e7,$00,$00,$00,$00,$00,$00,$61,$86
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$c0,$03,$92
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$7c,$00,$00,$3c,$00,$00,$00,$00,$00
	dc.b	$60,$06,$00,$00,$00,$00,$00,$00,$00,$78,$00,$00,$18,$00,$00,$00

;------------------------------------------------------------------------------
; font_8x16: the 8x16 font for high resolution, 128 characters: 16 lines of 128 bytes.
;------------------------------------------------------------------------------
font_8x16:	; from: text_last_row_by_res
	dc.b	$00,$00,$00,$00,$00,$ff,$00,$e7,$00,$6c,$60,$66,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$00,$03,$c0,$00
	dc.b	$00,$00,$00,$00,$18,$00,$38,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$06,$00,$60,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$ff,$00,$c3,$00,$6c,$60,$66,$78,$7c,$05,$a0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$00,$03,$c0,$00
	dc.b	$00,$00,$00,$00,$18,$00,$7c,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$06,$00,$60,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$00
	dc.b	$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$18,$e0,$00,$00
	dc.b	$00,$00,$00,$00,$00,$ff,$3c,$c3,$01,$6c,$60,$66,$60,$7c,$05,$a0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$18,$07,$e0,$22
	dc.b	$00,$18,$66,$66,$3e,$66,$6c,$18,$06,$60,$66,$00,$00,$00,$00,$06
	dc.b	$3c,$18,$3c,$7e,$0c,$7e,$1c,$7e,$3c,$3c,$00,$00,$0c,$00,$30,$3c
	dc.b	$1c,$18,$7c,$3c,$78,$7e,$7e,$3e,$66,$7e,$06,$66,$60,$63,$66,$3c
	dc.b	$7c,$3c,$7c,$3e,$7e,$66,$66,$63,$66,$66,$7e,$1e,$40,$78,$08,$00
	dc.b	$70,$00,$60,$00,$06,$00,$0e,$00,$60,$18,$0c,$60,$38,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0c,$18,$30,$00,$00
	dc.b	$00,$18,$3c,$00,$00,$ff,$42,$bd,$01,$7c,$60,$66,$60,$60,$05,$a0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$3c,$07,$e0,$77
	dc.b	$00,$18,$66,$66,$7e,$66,$6c,$18,$0c,$30,$66,$18,$00,$00,$00,$06
	dc.b	$7e,$18,$7e,$7e,$0c,$7e,$3c,$7e,$7e,$7e,$00,$00,$0c,$00,$30,$7e
	dc.b	$3e,$3c,$7e,$7e,$7c,$7e,$7e,$7e,$66,$7e,$06,$66,$60,$63,$66,$7e
	dc.b	$7e,$7e,$7e,$7e,$7e,$66,$66,$63,$66,$66,$7e,$1e,$40,$78,$1c,$00
	dc.b	$38,$00,$60,$00,$06,$00,$1e,$00,$60,$18,$0c,$60,$38,$00,$00,$00
	dc.b	$00,$00,$00,$00,$18,$00,$00,$00,$00,$00,$00,$0c,$18,$30,$00,$00
	dc.b	$00,$3c,$24,$38,$1c,$ff,$81,$bd,$03,$6c,$60,$3c,$78,$60,$05,$a0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$3c,$0e,$70,$77
	dc.b	$00,$18,$66,$ff,$60,$6c,$38,$18,$1c,$38,$3c,$18,$00,$00,$00,$0c
	dc.b	$66,$38,$66,$0c,$1c,$60,$70,$06,$66,$66,$18,$18,$18,$7e,$18,$66
	dc.b	$73,$7e,$66,$66,$6e,$60,$60,$60,$66,$18,$06,$6c,$60,$77,$66,$66
	dc.b	$66,$66,$66,$60,$18,$66,$66,$63,$66,$66,$0c,$18,$60,$18,$1c,$00
	dc.b	$1c,$00,$60,$00,$06,$00,$18,$00,$60,$00,$00,$60,$18,$00,$00,$00
	dc.b	$00,$00,$00,$00,$18,$00,$00,$00,$00,$00,$00,$0c,$18,$30,$00,$00
	dc.b	$00,$66,$24,$2c,$34,$ff,$99,$24,$03,$6c,$60,$18,$60,$60,$0d,$b0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$18,$0e,$70,$7f
	dc.b	$00,$18,$66,$ff,$60,$0c,$38,$18,$18,$18,$3c,$18,$00,$00,$00,$0c
	dc.b	$66,$38,$66,$0c,$1c,$60,$60,$06,$66,$66,$18,$18,$18,$7e,$18,$66
	dc.b	$61,$66,$66,$66,$66,$60,$60,$60,$66,$18,$06,$6c,$60,$77,$76,$66
	dc.b	$66,$66,$66,$60,$18,$66,$66,$63,$3c,$66,$0c,$18,$60,$18,$36,$00
	dc.b	$0c,$3c,$7c,$3c,$3e,$3c,$18,$3c,$7c,$38,$0c,$66,$18,$36,$3c,$3c
	dc.b	$7c,$3e,$7c,$3e,$7e,$66,$66,$63,$66,$66,$7e,$0c,$18,$30,$31,$00
	dc.b	$00,$c3,$24,$e6,$67,$ff,$a5,$24,$06,$6c,$78,$18,$6f,$7e,$0d,$b0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$66,$1c,$38,$7f
	dc.b	$00,$18,$66,$66,$7c,$18,$70,$18,$18,$18,$ff,$7e,$00,$7e,$00,$18
	dc.b	$66,$18,$0c,$18,$3c,$7c,$60,$0c,$3c,$7e,$18,$18,$30,$00,$0c,$0c
	dc.b	$6d,$66,$7e,$60,$66,$7c,$7c,$6e,$7e,$18,$06,$78,$60,$7f,$76,$66
	dc.b	$66,$66,$66,$70,$18,$66,$66,$63,$3c,$3c,$18,$18,$30,$18,$36,$00
	dc.b	$04,$3e,$7e,$7c,$7e,$7e,$7e,$7e,$7e,$38,$0c,$6e,$18,$7f,$7e,$7e
	dc.b	$7e,$7e,$7e,$7e,$7e,$66,$66,$63,$66,$66,$7e,$1c,$18,$38,$79,$00
	dc.b	$00,$81,$e7,$83,$c1,$ff,$a1,$24,$06,$00,$00,$00,$6c,$7f,$1d,$b8
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$ff,$1c,$38,$7f
	dc.b	$00,$18,$66,$66,$3e,$18,$70,$18,$18,$18,$ff,$7e,$00,$7e,$00,$18
	dc.b	$6e,$18,$0c,$18,$3c,$7e,$7c,$0c,$3c,$3e,$18,$18,$30,$00,$0c,$0c
	dc.b	$6b,$66,$7c,$60,$66,$7c,$7c,$6e,$7e,$18,$06,$78,$60,$6b,$7e,$66
	dc.b	$66,$66,$7e,$38,$18,$66,$66,$6b,$18,$3c,$18,$18,$30,$18,$63,$00
	dc.b	$00,$06,$66,$60,$66,$66,$7e,$66,$66,$18,$0c,$7c,$18,$7f,$66,$66
	dc.b	$66,$66,$66,$60,$18,$66,$66,$6b,$3c,$66,$0c,$78,$18,$1e,$5f,$00
	dc.b	$00,$e7,$81,$81,$81,$ff,$a1,$24,$8c,$3f,$0f,$3f,$6c,$1b,$39,$9c
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7e,$ff,$38,$1c,$3e
	dc.b	$00,$18,$00,$ff,$06,$30,$de,$00,$18,$18,$3c,$18,$00,$00,$00,$30
	dc.b	$76,$18,$18,$0c,$6c,$06,$7e,$18,$66,$06,$00,$00,$18,$7e,$18,$18
	dc.b	$6b,$7e,$66,$60,$66,$60,$60,$66,$66,$18,$06,$6c,$60,$6b,$7e,$66
	dc.b	$7e,$66,$7c,$1c,$18,$66,$66,$6b,$18,$18,$30,$18,$18,$18,$63,$00
	dc.b	$00,$3e,$66,$60,$66,$66,$18,$66,$66,$18,$0c,$78,$18,$6b,$66,$66
	dc.b	$66,$66,$60,$70,$18,$66,$66,$6b,$3c,$66,$18,$78,$18,$1e,$4e,$00
	dc.b	$00,$24,$c3,$83,$c1,$ff,$a5,$bd,$8c,$0c,$0c,$0c,$6f,$1b,$79,$9e
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7e,$ff,$38,$1c,$3e
	dc.b	$00,$18,$00,$ff,$06,$36,$de,$00,$18,$18,$3c,$18,$00,$00,$00,$30
	dc.b	$66,$18,$18,$0c,$6c,$06,$66,$18,$66,$06,$00,$00,$18,$7e,$18,$18
	dc.b	$6e,$7e,$66,$60,$66,$60,$60,$66,$66,$18,$06,$6c,$60,$63,$6e,$66
	dc.b	$7c,$66,$6c,$0e,$18,$66,$66,$7f,$3c,$18,$30,$18,$18,$18,$00,$00
	dc.b	$00,$7e,$66,$60,$66,$7e,$18,$66,$66,$18,$0c,$7c,$18,$6b,$66,$66
	dc.b	$66,$66,$60,$3c,$18,$66,$66,$7f,$18,$66,$18,$1c,$18,$38,$00,$00
	dc.b	$00,$24,$66,$e6,$67,$ff,$99,$bd,$d8,$0c,$0c,$0c,$0c,$1e,$71,$8e
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$66,$70,$0e,$1c
	dc.b	$00,$00,$00,$66,$7e,$66,$cc,$00,$18,$18,$66,$18,$18,$00,$18,$60
	dc.b	$66,$18,$30,$66,$7e,$06,$66,$30,$66,$0c,$18,$18,$0c,$00,$30,$18
	dc.b	$60,$66,$66,$66,$66,$60,$60,$66,$66,$18,$66,$66,$60,$63,$6e,$66
	dc.b	$60,$66,$66,$06,$18,$66,$3c,$7f,$3c,$18,$60,$18,$0c,$18,$00,$00
	dc.b	$00,$66,$66,$60,$66,$60,$18,$7e,$66,$18,$0c,$6c,$18,$6b,$66,$66
	dc.b	$66,$66,$60,$0e,$18,$66,$3c,$7f,$3c,$7e,$30,$0c,$18,$30,$00,$00
	dc.b	$00,$24,$3c,$2c,$34,$ff,$81,$c3,$58,$0c,$0e,$0c,$0c,$1e,$71,$8e
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$70,$0e,$1c
	dc.b	$00,$00,$00,$66,$7c,$66,$cc,$00,$1c,$38,$66,$00,$18,$00,$18,$60
	dc.b	$66,$18,$30,$66,$7e,$66,$66,$30,$66,$0c,$18,$18,$0c,$00,$30,$00
	dc.b	$71,$66,$66,$66,$6e,$60,$60,$66,$66,$18,$66,$66,$60,$63,$66,$66
	dc.b	$60,$6a,$66,$06,$18,$66,$3c,$77,$66,$18,$60,$18,$0c,$18,$00,$00
	dc.b	$00,$66,$66,$60,$66,$60,$18,$3e,$66,$18,$0c,$66,$18,$63,$66,$66
	dc.b	$7e,$7e,$60,$06,$18,$66,$3c,$77,$3c,$3e,$30,$0c,$18,$30,$00,$00
	dc.b	$00,$3c,$18,$38,$1c,$ff,$42,$c3,$70,$0c,$0c,$0c,$0c,$1b,$61,$86
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1e,$3c,$e0,$07,$08
	dc.b	$00,$18,$00,$00,$18,$00,$fe,$00,$0c,$30,$00,$00,$18,$00,$18,$40
	dc.b	$7e,$7e,$7e,$7e,$0c,$7e,$7e,$30,$7e,$38,$18,$18,$06,$00,$60,$18
	dc.b	$3f,$66,$7e,$7e,$7c,$7e,$60,$7e,$66,$7e,$7e,$63,$7e,$63,$66,$7e
	dc.b	$60,$7c,$63,$7e,$18,$7e,$18,$63,$66,$18,$7e,$1e,$06,$78,$00,$ff
	dc.b	$00,$7e,$7e,$7e,$7e,$7e,$18,$06,$66,$3c,$0c,$67,$3c,$63,$66,$7e
	dc.b	$7c,$3e,$60,$7e,$1e,$7e,$18,$63,$66,$06,$7e,$0c,$18,$30,$00,$00
	dc.b	$00,$00,$00,$00,$00,$ff,$3c,$e7,$30,$0c,$0c,$0c,$0c,$1b,$41,$82
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1e,$3c,$e0,$07,$08
	dc.b	$00,$18,$00,$00,$18,$00,$76,$00,$06,$60,$00,$00,$18,$00,$18,$40
	dc.b	$3c,$7e,$7e,$3c,$0c,$3c,$3c,$30,$3c,$38,$18,$18,$06,$00,$60,$18
	dc.b	$1e,$66,$7c,$3c,$78,$7e,$60,$3c,$66,$7e,$3c,$63,$7e,$63,$66,$3c
	dc.b	$60,$36,$63,$7c,$18,$3c,$18,$41,$66,$18,$7e,$1e,$06,$78,$00,$ff
	dc.b	$00,$3e,$7c,$3e,$3e,$3e,$18,$06,$66,$3c,$0c,$63,$3c,$63,$66,$3c
	dc.b	$60,$06,$60,$7c,$0e,$3e,$18,$41,$66,$06,$7e,$0c,$18,$30,$00,$00
	dc.b	$00,$00,$00,$00,$00,$ff,$00,$00,$20,$0c,$0c,$0c,$0c,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$c0,$03,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$7e,$00,$00,$7c,$00,$00,$00,$00,$00
	dc.b	$60,$06,$00,$00,$00,$00,$00,$00,$00,$7e,$00,$07,$18,$e0,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$c0,$03,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$7c,$00,$00,$78,$00,$00,$00,$00,$00
	dc.b	$60,$06,$00,$00,$00,$00,$00,$00,$00,$7c,$00,$00,$00,$00,$00,$00
	dcb.b	5108,$ff

	end
