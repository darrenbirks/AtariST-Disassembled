; STETEST.S  -  the Atari STE test cartridge, "STe Field Service Diagnostic Rev. 1.9, 1991, Atari Corp."
; Devpac source of the cartridge, disassembled by Darren Birks, 17 November 2026.
; 64K at $FA0000; the code is $0004-$7B55, unused zeros to $7FFF, texts, tables and two fonts
; $8000-$BBE1, data left over from a Mega STE build $BBE2-$ED63, the rest $FF.
;
; This source rebuilds the cartridge's 64K byte for byte with
;   vasmm68k_mot -devpac -m68000 -Fbin -o STETEST.IMG STETEST.S
; (the dump is "STE Test v1.9.img").
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; A diagnostic cartridge ($FA52235F at its start): TOS runs it at reset, before TOS sets anything up,
; so it uses no TOS at all. Its variables are in low RAM (the equates below), and it has its own
; exception and MFP vectors, text console (screen and RS232 terminal), keyboard, floppy and ACSI code.
; It is the STE version of the Mega STE diagnostic (Cartridges\MegaSTE Test 1.5): most of the code is
; the same, but there is no VME, FPU, SCU, SCC, real-time clock or 16 MHz, the variables sit at other
; addresses, and the P test also checks the STE joypads, paddles and light gun.
;
; Start-up: the MMU is set to 2M banks and the RAM sized through the bank mapping (a bank repeats after
; $20000 if it is 128K and after $80000 if 512K), then written back to the MMU and tested; then the
; screen, keyboard and RS232, the bus error check (a word written to address 0), the T test
; (timing_test, failures only) and a Timer A check (a second Timer A interrupt within the wait means
; a CPU or MFP clock fault: the machine beeps for ever). Then the menu.
;
; Text goes to the screen and, unless mode_flags bit 1 is set, also to RS232: each character waits for
; the MFP's transmitter buffer empty (TSR bit 7, with a time-out of about 0.2 s), then about 1.25 ms.
; The 50/60 Hz shown is bit 1 of $FF820A as found at reset; only the X command changes it.
;
; The menu runs tests by letter (several letters and a repeat count can be typed):
;   R RAM, O O.S. ROM, G short BLiT, M MIDI, S serial, T timing, D DMA port, P printer/mouse/joystick and
;   game ports, F floppy, Y long BLiT, Q all unattended tests (ROMSTDPFY), Z unattended internal tests
;   (ROTFG), A audio, C colour, K keyboard, H high resolution, J hard disk, E examine/modify memory,
;   B RS232 rate, X 50/60 Hz.
;
;=======================================================================
; BUGS IN THE CARTRIDGE (each is commented where it is)
;=======================================================================
;   fdc_interrupt clears ISRB bit 0, not bit 7: bclr #$80 on a memory byte takes the bit modulo 8.
;   The hard disk test waits on $4BA as if it were TOS's 200 Hz count, which nothing counts here.
;   hd_known_bad_sector's full-list branch goes into the RAM test's code.
;   The T1-T3 time-outs never fire: Timer A's vector is still the T0 routine, which never counts them.
;   dma_sound_test leaves through its caller's caller, so GPIP7 stays disabled after the audio test.
;   The RS232 test sends only $55,$AA (a 0 ends its string) and sends "No loopback connector" down the
;   line; the short BLiT test's G6 and G7 texts are swapped; detect_drive_types loses drive B's bit 7;
;   the random track test retries for ever; the alignment test never wraps below track 0.
;   The 8 longs at leftover_mste_scc_vectors are the Mega STE's SCC vectors, read by nothing.
;
; Two andi.b and ten cmpi.b have their immediate word assembled with $FF in the high byte; they are
; kept as dc.w with the instruction in the comment.

last_fault_pc	equ	$200                    ; PC of the last bus/address error reported (a second fault at the same
                                                ;   PC hangs)
ram_top	equ	$204                            ; the end of RAM (the D test stops its address table there)
interrupt_events	equ	$208            ; flags the interrupt routines clear: bit 6 RI, bit 1 DCD, bit 2 CTS,
                                                ;   bit 0 BUSY; the HBL routine clears the word; the timer B count
                                                ;   routine counts its high byte down
timer_a_count	equ	$20a                    ; time-out flag set by start_timer_a, counted down by the timer A count
                                                ;   routine
status_end_column	equ	$20c            ; the column after the last status-line text (show_status_at)
status_saved_column	equ	$20e            ; the cursor column kept while the status line is written
status_saved_row	equ	$210            ; the cursor row kept while the status line is written
repeat_count	equ	$212                    ; passes left of the menu command line (0 typed = for ever)
test_cycle	equ	$216                    ; the test cycle count; its low byte goes into each floppy test sector's
                                                ;   ID
scratch_long	equ	$21a                    ; the 32K block test's screen address, dma_sound_test's return address,
                                                ;   the timing test's video counter read
first_test_ptr	equ	$21e                    ; pointer to the first letter typed in the letter list (letters kept
                                                ;   last typed first)
test_ptr	equ	$222                    ; pointer to the letter of the test running now (counts down to $257)
test_letters_ptr	equ	$226            ; Q/Z sequence: the letters to run ("ROMSTDPFY" or "ROTFG")
run_done_message	equ	$22a            ; Q/Z sequence: "Q Tests Completed" or "Z Tests Completed"
rs232_rate	equ	$22e                    ; MFP Timer D data for the RS232 rate (2 = 19200 ... $40 = 600 baud)
key_list_column	equ	$230                    ; the keyboard test's column for the next key name
key_list_row	equ	$232                    ; the keyboard test's row for the next key name
ikbd_data_first	equ	$234                    ; x2, the 2 bytes of an IKBD joystick ($FD) or other $F4-$FF packet,
                                                ;   last byte first
ikbd_data_second	equ	$235            ; the first byte of a 2-byte IKBD packet: mouse X move, or joystick 0
startup_checks_done	equ	$236            ; 0 during the start-up T test (failures only shown), $EA after it
line_buffer	equ	$237                    ; x32, the menu / memory utility command line ($237-$256; 64 bytes
                                                ;   $237-$276 cleared)
test_letters	equ	$257                    ; x16, the test letters of the command line, last typed first
number_digits	equ	$267                    ; x16, the repeat count digits of the command line, lowest first
test_sequence_count	equ	$277            ; the number of letters in the Q (9) or Z (5) test sequence
drive_a_type	equ	$278                    ; floppy A: 0 none, bit 7 found, bit 0 single sided, bits 0+1 double
                                                ;   sided ($80 found but not writable)
drive_b_type	equ	$279                    ; floppy B: as drive_a_type (detection writes 1 or 3 without bit 7)
exerciser_drive_type	equ	$27a            ; type of the drive the floppy exerciser runs on (not used in
                                                ;   $0000-$17FF)
keyboard_revision	equ	$27b            ; IKBD reset reply low nibble + 1, shown on the menu ("Keyboard rev.")
ikbd_clock_packet	equ	$27c            ; x6, the 6 bytes of an IKBD $FC clock packet ($27C-$281), last byte
                                                ;   first
memory_utility_active	equ	$282            ; $FF while a memory utility command runs: bus/address errors return to
                                                ;   its prompt
test_sequence_index	equ	$283            ; the index of the running letter in the Q/Z sequence
timer_irq_flags	equ	$284                    ; bits the T0 timer routines clear (set to 3 by check_mfp_timer); the
                                                ;   keyboard test's countdown before the mouse arrows go back inverse
pass_count	equ	$285                    ; a test's round counter: MIDI passes, RS232 rate (timer D data), timing
                                                ;   rounds
rs232_received	equ	$286                    ; the last byte the RS232 receive interrupt read
rs232_sent	equ	$287                    ; the last byte the RS232 transmit interrupt sent (it stops at $FF)
rs232_rx_errors	equ	$288                    ; the RS232 receive status errors seen by the interrupts (bit 6 overrun)
rs232_tx_status	equ	$289                    ; the transmit status the transmit interrupts read last (bit 6 underrun)
key_release	equ	$28a                    ; the last key release byte from the keyboard (0 cleared before the
                                                ;   reset)
unattended	equ	$28b                    ; non-zero: running unattended (the floppy menu runs the quick test
                                                ;   without asking)
hardware_flags	equ	$28c                    ; bit 0 set when a BLiTTER answered (blit_check_present); bit 7 set at
                                                ;   start-up when the palette holds 12 bits (STE)
mode_flags	equ	$28d                    ; bit 0 keyboard failed, 1 RS232 not a terminal (loopback plug /
                                                ;   start-up: screen only), 3 Q/Z running, 4 several letters, 5 repeat
                                                ;   count, 6 test screen up, 7 back to menu without waiting
us_keyboard	equ	$28e                    ; $FF a U.S. keyboard (ROM country 0), 0 European
line_count	equ	$290                    ; T4: display lines counted by timer B (2 per interrupt); STE sideways
                                                ;   scroll: HBL lines since the VBL
vbl_flag	equ	$292                    ; set before a wait; the VBL routine clears it (the colour test counts
                                                ;   its timer B interrupts here, byte)
colour_shade	equ	$294                    ; colour_bands_handler: byte offset into colour_bars_st
floppy_motor_watch	equ	$295            ; non-zero while the floppy VBL routine waits for the motor to stop (the
                                                ;   speed test clears it)
test_index_byte	equ	$296                    ; keyboard test: bits 0-3 the left, right, up, down arrows drawn plain
                                                ;   (other tests use it as an index)
cycle_random	equ	$297                    ; the exerciser cycle's random byte (MFP timer A data) written into each
                                                ;   test sector
scroll_top	equ	$298                    ; text rows above it are not scrolled (the floppy tests keep 2 status
                                                ;   rows)
screen_base	equ	$29a                    ; the screen the text and the drawing go to (the long BLiT test moves it
                                                ;   to $70000)
screen_planes	equ	$29e                    ; 4, 2 or 1
screen_height	equ	$2a0                    ; 200 or 400
screen_width	equ	$2a2                    ; 320 or 640
screen_line_bytes	equ	$2a4            ; bytes per scan line (160 or 80)
char_height	equ	$2a6                    ; the font's height in lines (8 or 16)
text_row_bytes	equ	$2a8                    ; bytes per text row (1280)
last_column	equ	$2aa                    ; the last text column (39 or 79)
last_row	equ	$2ac                    ; the last text row (24)
font_address	equ	$2ae                    ; the 8x8 or 8x16 font
font_line_step	equ	$2b2                    ; bytes from one line of the font to the next ($80)
font_char_step	equ	$2b4                    ; bytes from one character of the font to the next (1)
font_first_char	equ	$2b6                    ; 0
font_last_char	equ	$2b8                    ; $7F
text_foreground	equ	$2ba                    ; plane bits of the text colour ($FFFF)
text_background	equ	$2bc                    ; plane bits of the background (0)
cursor_column	equ	$2be                    ; the text cursor's column
cursor_row	equ	$2c0                    ; the text cursor's row
cursor_address	equ	$2c2                    ; the screen address of the cursor's cell
cursor_flags	equ	$2c6                    ; text and cursor flags: bit 4 inverse text, bits 0-2 the cursor's state
cursor_blink_rate	equ	$2c7            ; $1E
cursor_hide_count	equ	$2c8            ; the cursor is hidden while non-zero (1 after init_text_screen)
saved_cursor_column	equ	$2ca            ; save_cursor's column
saved_cursor_row	equ	$2cc            ; save_cursor's row
draw_crossings	equ	$318                    ; the x crossings of the row being filled (up to 6 words)
draw_crossing_count	equ	$324            ; crossings found for the row
draw_bytes_per_line	equ	$326            ; drawing variables (a4 = $328 in the BLiTTER line/span code, offsets as
                                                ;   the Mega STE's from $32A): bytes per line
draw_planes	equ	$328                    ; planes (1); the drawing variables' base (a4/a5 point here)
draw_line_step	equ	$32a                    ; bytes from one line to the next for lines (80)
draw_contrl	equ	$32c                    ; CONTRL: the word pair giving the point count
draw_ptsin	equ	$334                    ; PTSIN: the polygon's points
draw_colour_bits	equ	$340            ; 4 words: the colour bit of each plane
draw_last_line	equ	$348                    ; 0: the last pixel of a line is left out in XOR mode ($20(a4))
draw_line_mask	equ	$34a                    ; the line style mask, rotated by each line's length
draw_write_mode	equ	$34c                    ; 0 replace, 1 transparent, 2 XOR, 3 reverse transparent ($24(a4))
draw_x1	equ	$34e
draw_y1	equ	$350                            ; also the row being filled
draw_x2	equ	$352
draw_y2	equ	$354
draw_pattern	equ	$356                    ; fill patterns ($2E(a4))
draw_pattern_mask	equ	$35a            ; pattern lines - 1 ($32(a4))
draw_multi_fill	equ	$35c                    ; non-zero: a pattern per plane ($34(a4))
draw_clip	equ	$35e                    ; non-zero: clipping on
draw_clip_xmin	equ	$360
draw_clip_ymin	equ	$362
draw_clip_xmax	equ	$364
draw_clip_ymax	equ	$366
blit_long_corners	equ	$3b2            ; points at the triangle's corners ($3CA) for blit_long_outline
blit_long_saved_screen	equ	$3b6            ; the screen before the long BLiT test
blit_long_points	equ	$3ba            ; 8 words: the triangle's points (PTSIN at first)
blit_long_triangle	equ	$3ca            ; 8 words: the triangle's corners, the third one moved by the test
kbd_buffer	equ	$3da                    ; x64, keyboard buffer (scan code/ASCII words)
aux_buffer	equ	$41a                    ; x64, buffer of the second record at $468
kbd_iorec	equ	$45a                    ; 14 bytes, keyboard buffer record: buffer l, size w, head w, tail w,
                                                ;   low w, high w
kbd_buffer_head	equ	$460                    ; the key buffer's head (record at $45A)
kbd_buffer_tail	equ	$462                    ; keyboard buffer tail (write offset)
aux_iorec	equ	$468                    ; 14 bytes, second buffer record (buffer $41A, 64 bytes), set up but not
                                                ;   used in $0000-$17FF
kbd_acia_status	equ	$476                    ; keyboard ACIA status kept by acia_service (record + $1C)
release_ring_write	equ	$478            ; the key release ring's write pointer ($480-$487)
release_ring_read	equ	$47c            ; the key release ring's read pointer
release_ring	equ	$480                    ; x8, key release codes
kbd_service_hook	equ	$488            ; keyboard hook (acia_service_done), loaded by acia_interrupt but not
                                                ;   called
midi_service_hook	equ	$48c            ; MIDI hook, loaded by acia_interrupt but not called
ikbd_packet_flags	equ	$490            ; bit 3 the reset reply awaited (goes to the key buffer), bit 1 a clock
                                                ;   packet, bit 0 a joystick packet
ikbd_bytes_left	equ	$491                    ; the bytes of the IKBD packet still to come
shift_held	equ	$492                    ; $80 while a shift key is held (shifted key map), else 0
ikbd_packet_header	equ	$493            ; the last mouse packet's header (bit 0 right button, bit 1 left), 0
                                                ;   when used
test_errors	equ	$49a                    ; the running test's error bits 0-7 (RS232: overrun, parity, framing,
                                                ;   mismatch, not received, IRQ, Tx/Rx error interrupts; also the short
                                                ;   BLiT and ROM tests)
test_errors_high	equ	$49b            ; the running test's error bits 8-15 (RS232: RI-DTR, DCD-DTR, RTS-CTS,
                                                ;   transmit stuck, input shorted)
test_errors_extra	equ	$49c            ; P: bit 0 left (joystick 1) fire error, bit 1 right (joystick 0) fire
                                                ;   error, bit 7 keyboard time-out
test_errors_last	equ	$49d            ; P: joystick direction error bits (low nibble port 0, high nibble port
                                                ;   1)
joypad_output_errors	equ	$49e            ; J5: STE joypad output bits that did not read back at $FF9203
joypad_input_errors	equ	$49f            ; J5: STE joypad input bits wrong at $FF9202
joypad_fire_errors	equ	$4a0            ; J6: STE fire button bits wrong
paddle_errors	equ	$4a1                    ; J7: bits 0-3 paddle not high enough, bits 4-7 not low enough
light_gun_error	equ	$4a2                    ; J8: 1 when a light gun position was wrong
saved_colour0	equ	$4a6                    ; colour 0 kept by the H and colour/scroll tests
saved_resolution	equ	$4a8            ; H test: the resolution kept
memory_utility_start	equ	$4aa            ; memory utility: start address
memory_utility_end	equ	$4ae            ; memory utility: end address
star_countdown	equ	$4b2                    ; VBLs to the next '*' blink in ram_test
star_inverse	equ	$4b4                    ; ram_test's '*' inverse ($FF) or plain (0)
rom_sum_high	equ	$4ba                    ; the ROM test's high ROM sum; the hard disk test waits on it as if it
                                                ;   were TOS's 200 Hz count, which nothing counts here
rom_sum_low	equ	$4c0                    ; the Low ROM's (odd bytes) sum
rom_crc_high	equ	$4c6                    ; the High ROM's CRC
rom_crc_low	equ	$4cc                    ; the Low ROM's CRC
rom_mismatch_texts	equ	$4d0            ; 1: "cs error"/"crc error" printed (TOS 1.62 or older)
scroll_position	equ	$4d4                    ; STE scroll tests: the screen address shown
colour_test_spaces	equ	$4d8            ; Spaces pressed in the colour test
counter_expected	equ	$4da            ; the timing test's T4: the video counter expected next
counter_end	equ	$4de                    ; the timing test's T4: the screen's end
scroll_restart	equ	$4e2                    ; STE scroll tests: non-zero = start again at $20000
scroll_step	equ	$4e4                    ; STE scroll tests: VBL count (vertical) or pixel 0-15 (sideways)
saved_screen_address	equ	$4e6            ; the screen address kept by save_screen_state
dma_step	equ	$4ee                    ; the DMA sound test's step offset (volume, treble or bass)
unused_line_count	equ	$4f0            ; counted by a timer B routine and cleared by a VBL routine that nothing
                                                ;   installs
dma_bass_sound	equ	$4f2                    ; the DMA sound test's bass sound (0 or 1)
dma_block_count	equ	$4f4                    ; D test: blocks in the transfer
dma_test_address	equ	$4f6            ; D test: the transfer address
dma_command	equ	$4fa                    ; D test: $10 write out, $08 read back
dma_table_index	equ	$4fb                    ; D test: offset into the address table (step 4)
blit_source_word	equ	$4fc            ; the short BLiT test's source fill word; the long test keeps the old
                                                ;   bus error vector here (l)
blit_dest_word	equ	$4fe                    ; the short BLiT test's destination fill word
blit_lines	equ	$500                    ; the lines a BLiT (y count); the long test keeps sp here (l) for its
                                                ;   bus error handler
blit_words	equ	$502                    ; the words a line (x count)
saved_vbl_vector	equ	$504            ; the VBL vector kept by the colour and scroll tests
saved_vector	equ	$508                    ; the timer B vector kept by the colour test (the HBL vector in the
                                                ;   scroll test)
midi_buffer_record	equ	$620            ; 30 bytes, the MIDI buffer record (input and output buffer records,
                                                ;   ACIA status at +$1C), set from midi_record_init
fd_fill_word	equ	$67e                    ; the data word of formatted sectors ($E5E5)
fd_interleave	equ	$680                    ; the format interleave (copied, not used)
fd_side	equ	$682                            ; the side for the next floppy call
fd_track	equ	$684                    ; the track (byte $685 written directly)
fd_sector	equ	$686                    ; the first sector for the next floppy call
fd_count	equ	$688                    ; the sector count for the next floppy call
fd_drive	equ	$68a                    ; 0 drive A, 1 drive B
fd_buffer	equ	$68c                    ; the transfer buffer ($2000 write, $4000 read)
fd_retried	equ	$690                    ; set after the first failure of a read or write: the second is a hard
                                                ;   error
speed_ticks	equ	$692                    ; speed test: timer A ticks (651 us) counted by its interrupt routine
speed_max	equ	$6a8                    ; speed test: the longest turn, BCD ms
speed_min	equ	$6aa                    ; speed test: the shortest turn, BCD ms
fd_bad_tracks	equ	$6ac                    ; 160 bytes: $FF marks a track that failed to format (side 1 from +80)
fd_read_errors	equ	$74c                    ; floppy exerciser read errors
fd_write_errors	equ	$74e                    ; floppy exerciser write errors
fd_format_errors	equ	$750            ; floppy exerciser format errors
fd_probing	equ	$752                    ; 1 while the drives are probed: failures return without a report
fdc_tries	equ	$756                    ; set to 2, never read
fdc_drive	equ	$758                    ; the call's drive
fdc_track	equ	$75a                    ; the call's track (low byte at $75B goes into the format IDs)
fd_cur_sector	equ	$75c                    ; the sector being transferred
fdc_side	equ	$75e                    ; the call's side (low byte at $75F goes into the format IDs)
fdc_count	equ	$760                    ; sectors still to transfer
fd_cur_buffer	equ	$762                    ; the current sector's buffer; after a format the bad sector list
                                                ;   (words, 0 ends)
fdc_buffer_end	equ	$766                    ; the buffer's end, for the DMA count check
fdc_format_count	equ	$76a            ; the sectors read back after a format
fdc_interleave	equ	$76c                    ; the interleave (not used)
fdc_fill_word	equ	$76e                    ; the format's data word
dma_address_read	equ	$770            ; the DMA address read back after a read (high byte cleared)
fdc_default_error	equ	$774            ; the call's own error code
fd_error	equ	$776                    ; the last floppy error code (0 none, -2 not ready ... -18)
drive_a_head	equ	$79c                    ; drive A's track ($FF00 not known), then its step rate (w)
drive_b_head	equ	$7a0                    ; drive B's track ($FF00 not known), then its step rate (w)
acsi_timeout	equ	$7a4                    ; rounds left while waiting for the ACSI unit
hd_counter_a	equ	$7a8                    ; cleared at the hard disk test's start, not used further
hd_counter_b	equ	$7aa                    ; cleared at the hard disk test's start, not used further
hd_counter_c	equ	$7ac                    ; cleared at the hard disk test's start, not used further
hd_counter_d	equ	$7ae                    ; cleared at the hard disk test's start, not used further
hd_sectors_left	equ	$7b0                    ; sectors still to read (68 at the start)
hd_cylinder	equ	$7b2                    ; the cylinder shown in the status line (600)
hd_first_sector	equ	$7b4                    ; the test area's first sector ($9F1C)
hd_sector	equ	$7b8                    ; the next sector to read
acsi_sector	equ	$7bc                    ; the sector for the command (bytes $7BD-$7BF sent)
acsi_count	equ	$7c0                    ; the sector count for the command
acsi_unit	equ	$7c2                    ; the ACSI unit (0); its low byte is also sent as the LUN
acsi_dma_address	equ	$7c4            ; the DMA address for the command
hd_bad_sectors	equ	$7ce                    ; x 32, the known bad sector list
hd_bad_sectors_end	equ	$84e            ; the end of the known bad sector list

	org	$fa0000
	dc.w	$fa52,$235f

;------------------------------------------------------------------------------
; cold_start: entered from TOS at reset (diagnostic cartridge) and from the GPIP7 monitor-change
; handler; nothing is set up and RAM cannot be trusted yet. Sizes the two RAM banks: the MMU is
; set to 2M + 2M ($0A to $FF8001), two test longs go at the start of each bank ($10/$14 for bank 0,
; $200000/$200004 for bank 1) and are looked for again one bank-size repeat higher. A bank smaller
; than the 2M the MMU was told shows its contents again further up (on the STE MMU a 128K bank
; repeats after $20000, a 512K bank after $80000; on the ST MMU after $200 and $400, chosen when the
; palette has only 3 bits a gun). A bank whose test long reads back only at its own address counts
; as 2M; one where it does not read back at all counts as empty (bank 0 empty: "I4 Memory
; configuration error" on RS232). The found sizes go into the MMU and the total into d5 (later $204).
; Then the low RAM test, the variables cleared, the exception and MFP vectors installed, a good 1K
; for the stack found below $20000, and the start-up checks (bus error, timing, Timer A) before
; the menu. Errors before the stack exists are sent to the RS232 port by register-only code at
; ram_fail_report.
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
	bne.w	ram_data_line_fail              ; wrong: report it
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
	bne.w	ram_data_line_fail              ; wrong: report it
	lsl.w	#1,d0                           ; next bit
	cmpi.w	#$0,d0                          ; until the bit falls out
	bne.s	data_line_walk1_next            ; more bits
	move.w	#$fffe,d0                       ; then a walking zero
data_line_walk0_next:
	move.w	d0,(a0)                         ; write the pattern
	nop                                     ; let the bus settle
	move.w	(a0),d1                         ; read it back
	cmp.w	d0,d1                           ; read back right?
	bne.w	ram_data_line_fail              ; wrong: report it
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
	moveq	#0,d0                           ; (not used)
ram_check_low_zero:
	move.w	(a0),d1                         ; low area must still be zero
	bne.w	ram_disturb_fail                ; not zero: disturbed by the ones above
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
	bne.w	ram_address_fail                ; wrong: address line fault
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
	bne.w	ram_address_fail                ; wrong: address line fault
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
	movea.l	#exception_vectors_table,a0     ; exception vector table (bus error to line F)
	movea.l	#$8,a1                          ; from the bus error vector on
	moveq	#9,d0                           ; 10 vectors
install_exception_vectors:
	move.l	(a0)+,(a1)+                     ; copy a vector
	dbra	d0,install_exception_vectors    ; loop
	movea.l	#$60,a1                         ; spurious, autovectors and NMI $60-$7F
	movea.l	#autovectors_table,a0           ; vector table for $60-$7C (spurious, autovectors)
	moveq	#7,d0                           ; 8 vectors
install_autovectors:
	move.l	(a0)+,(a1)+                     ; copy a vector
	dbra	d0,install_autovectors          ; loop
	movea.l	#mfp_vectors_table,a0           ; the 16 MFP vector table
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
	bsr.w	test_ram_range                  ; test this 1K (errors recorded below $800)
	move.w	a6,d0                           ; error record pointer
	andi.w	#$3ff,d0                        ; a6 unmoved: no error recorded
	beq.s	stack_block_good                ; block good
	suba.w	#$400,a0                        ; try the 1K below
	suba.w	#$400,a1                        ; block end 1K lower too
	cmpa.l	#$1f000,a0                      ; below $1F000?
	blt.w	stack_block_fail                ; no good block: report the errors and start again
	bra.s	find_stack_block                ; test it
stack_block_good:
	movea.l	a1,sp                           ; stack at the top of the good block
	bsr.w	mfp_reset                       ; all MFP interrupts off, vectors at $100
	move.w	#$2,rs232_rate.w                ; RS232 at 19200 baud
	bsr.w	video_setup                     ; screen at $10000, resolution from the monitor, RS232 on
	bsr.w	init_text_screen                ; text screen set-up
	bsr.w	clear_screen                    ; clear the screen
startup_beep:
	lea	$ffff8800.w,a0                  ; PSG register select
	lea	$ffff8802.w,a1                  ; PSG write data
	bsr.w	psg_sound_off                   ; all PSG voices silent
	move.b	#$7,(a0)                        ; mixer: all tones and noise on, port A and B outputs
	move.b	#$c0,(a1)
	move.b	#$f,(a0)                        ; port B
	move.b	#$c0,(a1)                       ; all bits high
	move.b	#$e,(a0)                        ; port A
	move.b	#$66,(a1)                       ; $66: both drives deselected, side 0, strobe high
	move.w	#$e8,d0                         ; LMC1992 master volume 0 dB
	bsr.w	lmc1992_write                   ; LMC1992 write
	move.w	#$154,d0                        ; left volume 0 dB
	bsr.w	lmc1992_write                   ; LMC1992 write
	move.w	#$114,d0                        ; right volume 0 dB
	bsr.w	lmc1992_write                   ; LMC1992 write
	move.w	#$86,d0                         ; treble flat
	bsr.w	lmc1992_write                   ; LMC1992 write
	move.w	#$46,d0                         ; bass flat
	bsr.w	lmc1992_write                   ; LMC1992 write
	move.w	#$1,d0                          ; mix the YM in
	bsr.w	lmc1992_write                   ; LMC1992 write
	moveq	#0,d2                           ; channel A
	moveq	#4,d7                           ; tone period high = 4
	moveq	#-30,d6                         ; tone period low = $E2
	bsr.w	psg_tone_loud                   ; the start-up beep on channel A

;------------------------------------------------------------------------------
; check_bus_error: a word write to address $000000 must take a bus error (the first 8 bytes are
; ROM, and a write there gets no DTACK even in supervisor mode). bus_error_caught sets d7, drops
; the 8 bytes of 68000 group 0 information (status word, access address, instruction) and returns
; with rte to the stacked PC; the nop after the write gives the stacked PC a harmless place to land.
; If the write completes without a bus error: "I7 Bus error not detected" and a red background;
; start-up carries on either way. Neither the access address nor the status word is checked.
;------------------------------------------------------------------------------
check_bus_error:
	lea	msg_checking_exceptions,a5      ; "Checking Bus error handling"
	bsr.w	print_string                    ; print it
	movea.l	$8.w,a4                         ; keep the bus error vector
	move.l	#bus_error_caught,$8.w          ; bus error vector
	clr.w	d7                              ; d7 = 0: no bus error yet
	move.w	d0,$0.w                         ; write to ROM at 0: must bus error
	nop                                     ; rte lands here (or on the write's second word)
	move.l	a4,$8.w                         ; bus error vector back
	bsr.w	clear_screen                    ; clear the screen
	tst.w	d7                              ; bus error taken?
	bne.w	startup_timing_checks           ; yes: right
	lea	msg_bus_error_not_detected,a5   ; "I7 Bus error not detected"
	bsr.w	print_string                    ; print it
	move.w	#$500,$ffff8240.w               ; palette 0, red: error

;------------------------------------------------------------------------------
; startup_timing_checks: runs the T timing test with the screen only ($28D = 2: no RS232 output),
; $236 = $EA afterwards marks the start-up checks done. Then, unless the RAM test of the stack
; block recorded errors ($49A), a Timer A check: Timer A at /100 with data 1 (one interrupt every
; 40.7 us) is caught once, then must not fire again within 7 dbra loops (about 14 us). If it does,
; the CPU or MFP clock is wrong and the cartridge sounds the audio test tone for ever.
;------------------------------------------------------------------------------
startup_timing_checks:	; from: check_bus_error
	move.w	#$2400,sr                       ; interrupts at level 4 and up (VBL, MFP)
	move.b	#$2,mode_flags.w                ; mode flags: bit 1, screen only, no RS232 output
	clr.b	startup_checks_done.w           ; start-up checks not done yet
	bsr.w	timing_test                     ; the T timing test
	move.b	#$ea,startup_checks_done.w      ; start-up checks done
	tst.b	test_errors.w                   ; RAM errors found in the stack search?
	bne.s	startup_keyboard_setup          ; yes: skip the Timer A check
	bsr.w	clear_screen                    ; clear the screen
	move.b	#$1,$fffffa1f.w                 ; MFP TADR, Timer A data 1
	move.w	#$d,d0                          ; MFP interrupt 13: Timer A
	movea.l	#timer_a_count_handler,a2       ; the counting handler
	bsr.w	mfp_install_handler             ; install and enable it
	move.b	#$6,$fffffa19.w                 ; MFP TACR, Timer A on, prescale /100
	move.b	#$1,timer_irq_flags.w           ; flag for the handler to clear
timer_a_check_sync:
	tst.b	timer_irq_flags.w               ; wait for a Timer A interrupt
	bne.s	timer_a_check_sync              ; not yet
	move.b	#$1,timer_irq_flags.w           ; set the flag again, right after an interrupt
	move.w	#$6,d7                          ; 7 loops
timer_a_check_wait:
	dbra	d7,timer_a_check_wait           ; wait shorter than one Timer A period
	move.b	#$0,$fffffa19.w                 ; MFP TACR, Timer A stop
	tst.b	timer_irq_flags.w               ; flag still set (no interrupt so soon)?
	bne.s	startup_keyboard_setup          ; right: on to the menu
	move.w	#$e8,d0                         ; Timer A came too soon: CPU or MFP clock wrong
	bsr.w	lmc1992_write                   ; LMC1992 write: master volume 0 dB
	move.w	#$154,d0                        ; left volume 0 dB
	bsr.w	lmc1992_write                   ; LMC1992 write
	move.w	#$114,d0                        ; right volume 0 dB
	bsr.w	lmc1992_write                   ; LMC1992 write
	move.w	#$1,d0                          ; mix the YM in
	bsr.w	lmc1992_write                   ; LMC1992 write
	moveq	#0,d2                           ; channel A
timer_a_fail_alarm:
	bsr.w	audio_test_step                 ; sound the audio test tone
	bra.s	timer_a_fail_alarm              ; for ever
startup_keyboard_setup:
	bsr.w	mfp_disable_interrupt           ; MFP interrupt 15 (GPIP7, monitor change) off...
	moveq	#15,d0                          ; ...interrupt 15
	bsr.w	mfp_enable_interrupt            ; ...and on again: a monitor change restarts the cartridge
	bsr.w	keyboard_setup                  ; keyboard ACIA, buffers and interrupt
	clr.b	hardware_flags.w                ; machine flags: none yet
	movea.l	#$ffff8240,a0                   ; colour 0
	move.w	#$fff,(a0)                      ; write a 12-bit colour
	cmpi.w	#$fff,(a0)                      ; reads back intact only on an STE palette
	bne.s	startup_to_menu                 ; ST palette: flag stays clear
	move.b	#$80,hardware_flags.w           ; machine flags bit 7: STE palette
startup_to_menu:
	bra.w	menu_start                      ; on to the menu

;------------------------------------------------------------------------------
; bus_error_caught: bus error handler for the start-up bus error check and the T timing test: sets d7
; to -1, drops the 8 bytes of 68000 group 0 information and returns to the stacked PC.
;------------------------------------------------------------------------------
bus_error_caught:	; from: check_bus_error, timing_test
	moveq	#-1,d7                          ; bus error seen
	adda.w	#$8,sp                          ; leave SR and PC
	rte                                     ; back after the faulting access
stack_block_fail:	; from: low_ram_test
	move.b	#$2,mode_flags.w                ; mode flags: screen only
	moveq	#2,d0                           ; 19200 baud
	bsr.w	rs232_setup_rate                ; RS232 at 19200 baud
	bsr.w	print_ram_errors                ; the recorded RAM errors (screen and RS232)
	bra.w	low_ram_test                    ; test low RAM again
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
	bra.s	rs232_raw_newline               ; CR/LF
ram_fail_report_done:
	move.w	#$500,$ffff8240.w               ; palette 0, red
	move.b	#$1,$ffff8201.w                 ; video base high, screen at $10000
	clr.b	$ffff8203.w                     ; video base mid
	lea	$10000,a0                       ; clear the screen
	moveq	#0,d0                           ; zero
ram_fail_clear_screen:
	move.w	d0,(a0)+                        ; clear a word
	cmpa.l	#$18000,a0                      ; end of the screen?
	bne.s	ram_fail_clear_screen           ; more
	lsl.w	#1,d6                           ; next data pattern
	bra.w	low_ram_test_retry              ; test low RAM again with it

;------------------------------------------------------------------------------
; rs232_raw_print_text: sends the 0-ended text at a5 to RS232 without RAM. In: a4 = $FFFFFA01, a0
; the return address. Changes d2, a5.
;------------------------------------------------------------------------------
rs232_raw_print_text:	; from: ram_fail_report
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

;------------------------------------------------------------------------------
; rs232_raw_newline: sends CR, LF. In: a4 = $FFFFFA01, a0 the return address.
;------------------------------------------------------------------------------
rs232_raw_newline:	; from: ram_fail_report
	tst.b	$2c(a4)                         ; transmitter empty?
	bpl.s	rs232_raw_newline               ; wait
	move.b	#$d,$2e(a4)                     ; CR
rs232_raw_newline_lf:
	tst.b	$2c(a4)                         ; transmitter empty?
	bpl.s	rs232_raw_newline_lf            ; wait
	move.b	#$a,$2e(a4)                     ; LF
	jmp	(a0)                            ; return

;------------------------------------------------------------------------------
; rs232_raw_print_binary: sends d0.w as 16 binary digits. In: a4 = $FFFFFA01, a0 the return
; address. Changes d0, d2.
;------------------------------------------------------------------------------
rs232_raw_print_binary:	; from: ram_fail_report
	andi.b	#$fe,ccr                        ; clear carry
	moveq	#15,d2                          ; 16 bits
rs232_raw_print_binary_bit:
	tst.b	$2c(a4)                         ; transmitter empty?
	bpl.s	rs232_raw_print_binary_bit      ; wait
	lsl.w	#1,d0                           ; next bit out at the top
	bcc.s	rs232_raw_print_binary_zero     ; 0 bit
	move.b	#$31,$2e(a4)                    ; "1"
	bra.s	rs232_raw_print_binary_next     ; next bit
rs232_raw_print_binary_zero:
	move.b	#$30,$2e(a4)                    ; "0"
rs232_raw_print_binary_next:
	dbra	d2,rs232_raw_print_binary_bit   ; next bit
	jmp	(a0)                            ; return

;------------------------------------------------------------------------------
; rs232_raw_print_hex_word: sends d1.w as 4 hex digits. In: a4 = $FFFFFA01, a0 the return address.
; Changes d2, d3, a1, a2.
;------------------------------------------------------------------------------
rs232_raw_print_hex_word:	; from: ram_fail_report
	move.w	d1,d2                           ; high byte first
	lsr.w	#8,d2                           ; high byte
	lea	rs232_raw_print_hex_word_low,a1 ; return address
	bra.s	rs232_raw_print_hex_byte        ; print it
rs232_raw_print_hex_word_low:
	move.w	d1,d2                           ; then the low byte
	lea	rs232_raw_print_hex_word_done,a1 ; return address
	bra.s	rs232_raw_print_hex_byte        ; print it
rs232_raw_print_hex_word_done:
	jmp	(a0)                            ; return

;------------------------------------------------------------------------------
; rs232_raw_print_hex_byte: sends d2.b as 2 hex digits. In: a4 = $FFFFFA01, a1 the return address.
; Changes d3, a2. rs232_raw_print_digit: sends the low 4 bits of d3 as a hex digit (a2 the
; return); rs232_raw_send: sends d3 (a2 the return).
;------------------------------------------------------------------------------
rs232_raw_print_hex_byte:	; from: ram_fail_report, rs232_raw_print_hex_word
	move.b	d2,d3                           ; high digit
	lsr.b	#4,d3                           ; high digit
	lea	rs232_raw_print_hex_byte_low,a2 ; return address
	bra.s	rs232_raw_print_digit           ; send it
rs232_raw_print_hex_byte_low:
	move.b	d2,d3                           ; low digit
	lea	rs232_raw_print_hex_byte_done,a2 ; return address
	bra.s	rs232_raw_print_digit           ; send it
rs232_raw_print_hex_byte_done:
	jmp	(a1)                            ; return
rs232_raw_print_digit:
	andi.b	#$f,d3                          ; one digit
	cmp.b	#$9,d3                          ; 0-9?
	bls.s	rs232_raw_print_digit_number    ; yes
	and.w	#$7,d3                          ; A-F: $A..$F -> 'A'..'F'
	subq.w	#1,d3                           ; the letter's place in the alphabet
	ori.b	#$40,d3                         ; 'A'..'F'
rs232_raw_send:	; from: ram_fail_report
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
	rts                                     ; done

;------------------------------------------------------------------------------
; video_setup: screen at $10000 and waits for the video counter to be there (the VBL reload); high
; resolution on a mono monitor (GPIP7 low), else medium with colour 3 = $666; background $003 (blue);
; then falls into rs232_setup. Changes d0, a0-a2.
;------------------------------------------------------------------------------
video_setup:	; from: low_ram_test, colour_test
	movea.l	#$ff8200,a2                     ; video registers
	move.b	#$1,1(a2)                       ; video base high: screen at $010000
	clr.b	3(a2)                           ; video base mid
video_setup_wait_high:
	cmpi.b	#$1,5(a2)                       ; video counter high = 1?
	bne.s	video_setup_wait_high           ; wait
video_setup_wait_mid:
	cmpi.b	#$0,7(a2)                       ; video counter mid = 0?
	bne.s	video_setup_wait_mid            ; wait
video_setup_wait_low:
	cmpi.b	#$0,9(a2)                       ; video counter low = 0?
	bne.s	video_setup_wait_low            ; wait
	move.w	#$fff,d0                        ; white
	lea	$ffff8240.w,a1                  ; palette 0
	move.w	#$1e,d1                         ; 16 colours, from the last
video_setup_palette_loop:
	move.w	d0,0(a1,d1.w)                   ; all colours white
	sub.w	#$2,d1                          ; next colour
	bpl.s	video_setup_palette_loop        ; down to colour 0
	lea	$fffffa01.w,a0                  ; MFP GPIP
	btst	#$7,0(a0)                       ; GPIP7: colour monitor?
	bne.s	video_setup_colour              ; yes
	move.b	#$2,$60(a2)                     ; mono: high resolution
	bra.s	video_setup_background          ; on to the background
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
rs232_setup:	; from: cmd_rs232_rate, bus_error_handler, rs232_test, timing_test
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
	rts                                     ; done

;------------------------------------------------------------------------------
; mfp_reset: all MFP interrupts off (enable, mask, pending, in-service), AER, DDR and GPIP cleared,
; vector base $100 ($40 in VR, vector number times 4) with software end of interrupt. Changes a0.
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
	rts                                     ; done

;------------------------------------------------------------------------------
; keyboard_setup: clears the mode flags ($28D) and the IKBD packet state ($490-$492), copies the
; two buffer records to $45A (keyboard: buffer $3DA, 64 bytes) and $468 (second record: buffer $41A,
; 64 bytes), points the key release ring pointers ($478, $47C) at the ring $480-$487, puts
; acia_service_done in the keyboard hook $488, master-resets the MIDI ACIA (left reset), resets the
; keyboard ACIA to /64 8N1 with the receive interrupt and installs acia_interrupt on MFP interrupt 6.
; Changes d0, a0-a2.
;------------------------------------------------------------------------------
keyboard_setup:	; from: startup_timing_checks
	clr.b	mode_flags.w                    ; mode flags clear
	clr.b	shift_held.w                    ; no shift held
	clr.b	ikbd_packet_flags.w             ; no IKBD packet under way
	clr.b	ikbd_bytes_left.w               ; no packet bytes left
	movea.l	#$45a,a0                        ; the keyboard buffer record
	movea.l	#iorec_init_records,a1          ; the two initial buffer records
	moveq	#29,d0                          ; 30 bytes
	bsr.w	copy_bytes                      ; copy them
	move.l	#$480,release_ring_write.w      ; release ring write pointer
	move.l	#$480,release_ring_read.w       ; release ring read pointer
	move.l	#acia_service_done,kbd_service_hook.w ; keyboard hook: nothing to do
	bsr.w	midi_record_and_acia            ; a0 MIDI record, a1 MIDI ACIA
	move.b	#$3,0(a1)                       ; MIDI ACIA master reset
	bsr.w	keyboard_record                 ; a0 keyboard record, a1 keyboard ACIA
	move.b	#$3,0(a1)                       ; keyboard ACIA master reset
	move.b	#$96,0(a1)                      ; /64, 8N1, receive interrupt on
	moveq	#6,d0                           ; MFP interrupt 6: ACIA
	movea.l	#acia_interrupt,a2              ; the handler
	bsr.w	mfp_install_handler             ; install it
	rts                                     ; done

;------------------------------------------------------------------------------
; iorec_init_records: the two buffer records copied to $45A by keyboard_setup. Each is buffer
; address (long), size, head, tail, low mark, high mark: $3DA 64 bytes (keyboard) and $41A 64 bytes.
;------------------------------------------------------------------------------
iorec_init_records:	; from: keyboard_setup
	dc.w	$0000,$03da,$0040,$0000,$0000,$0010,$0030,$0000
	dc.w	$041a,$0040,$0000,$0000,$0010,$0030,$0000 ; the buffer record: size 64, head, tail, low mark 16, high
                                                ;   mark 48, spare word

;------------------------------------------------------------------------------
; mfp_install_handler: In d0 the MFP interrupt (0-15), a2 the handler. Turns the interrupt off, puts a2
; in vector $100+d0*4 and turns it on (enable and mask). Keeps all registers.
;------------------------------------------------------------------------------
mfp_install_handler:	; from: startup_timing_checks, keyboard_setup, mono_monitor_test, floppy_speed_test
	movem.l	d0-d2/a0-a3,-(sp)               ; save registers
	bsr.w	mfp_disable_interrupt           ; off while the vector changes
	move.l	d0,d2                           ; interrupt number
	asl.w	#2,d2                           ; vector offset
	addi.l	#$100,d2                        ; MFP vectors at $100
	movea.l	d2,a3                           ; the vector
	move.l	a2,(a3)                         ; new handler
	bsr.w	mfp_enable_interrupt            ; turn it on
	movem.l	(sp)+,d0-d2/a0-a3               ; restore registers
	rts                                     ; done

;------------------------------------------------------------------------------
; mfp_disable_interrupt: In d0 the MFP interrupt (0-15). Clears its mask, enable, pending and in-service
; bits with interrupts off. Keeps all registers.
;------------------------------------------------------------------------------
mfp_disable_interrupt:                          ; from: startup_timing_checks, mfp_install_handler, colour_test,
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
	rts                                     ; done

;------------------------------------------------------------------------------
; mfp_enable_interrupt: In d0 the MFP interrupt (0-15). Sets its enable and mask bits with interrupts
; off. Keeps all registers.
;------------------------------------------------------------------------------
mfp_enable_interrupt:                           ; from: startup_timing_checks, mfp_install_handler, colour_test,
                                                ;   reset_keyboard_and_check, rs232_test, dma_sound_test_restore, 1 more
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
	rts                                     ; done

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
	cmp.b	#$8,d0                          ; 0-7?
	bge.s	mfp_bit_register_done           ; 8-15: A register
	addq.w	#2,a1                           ; 0-7: B register
mfp_bit_register_done:
	rts                                     ; done

;------------------------------------------------------------------------------
; delay: waits 1000 loops, about 2.25 ms at 8 MHz. Keeps all registers.
;------------------------------------------------------------------------------
delay:                                          ; from: rs232_setup_rate, menu_start, pause_clear_status, colour_test,
                                                ;   rs232_test, dma_sound_test_restore, 6 more
	move.l	d0,-(sp)                        ; keep d0
	move.l	#$3e8,d0                        ; 1000 loops
delay_loop:
	subq.l	#1,d0                           ; count down
	bne.s	delay_loop                      ; to 0
	move.l	(sp)+,d0                        ; d0 back
	rts                                     ; done

;------------------------------------------------------------------------------
; copy_bytes: copies d0+1 bytes from a1 to a0. Out: a0, a1 past the end; d0 = -1.
;------------------------------------------------------------------------------
copy_bytes:	; from: keyboard_setup, midi_test, run_bus_test_in_ram
	move.b	(a1)+,(a0)+                     ; copy a byte
	dbra	d0,copy_bytes                   ; loop
	rts                                     ; done

;------------------------------------------------------------------------------
; menu_start: once after start-up: drive types cleared, BLiTTER looked for (machine flags bit 0),
; the keyboard reset and checked (no answer: mode flags bit 0 and "Keyboard failed, connect RS232
; terminal"), the mouse off and the result sound. A red screen keeps the start-up messages.
; main_menu: the menu loop: clear screen, blue background, sound off; then menu_check_terminal sends a
; byte to RS232 and waits 90 ms: a byte coming back means the loopback plug is in, and RS232 is then
; not used as a terminal (mode flags bit 1). The title, RAM size, keyboard revision, 50/60 Hz and TOS
; version line and the menu follow. A command line is read and run: the letters (from
; "ROGMSTDPFYQZ") are kept, last first, at $257, a trailing number at $267 is the repeat count
; (0 = for ever). Mode flags: bit 3 Q/Z running, bit 4 several letters, bit 5 repeat count, bit 6
; test screen up. With one test and no repeat the result waits for Space; otherwise ESC is checked
; between tests.
;------------------------------------------------------------------------------
menu_start:	; from: startup_timing_checks
	clr.b	drive_a_type.w                  ; drive A type unknown
	clr.b	drive_b_type.w                  ; drive B type unknown
	bsr.w	blit_check_present              ; BLiTTER there? (machine flags bit 0)
	clr.b	mode_flags.w                    ; mode flags clear
	bsr.w	reset_keyboard_and_check        ; reset the keyboard, read its revision
	beq.s	menu_start_keyboard_ok          ; answered
	btst	#$0,mode_flags.w                ; keyboard failed?
	beq.s	menu_start_keyboard_ok          ; no
	lea	msg_keyboard_failed,a5          ; "Keyboard failed, connect RS232 terminal"
	bsr.w	print_string                    ; print it
menu_start_keyboard_ok:
	moveq	#18,d1                          ; IKBD $12: mouse off
	bsr.w	ikbd_send                       ; send it
	bsr.w	result_sound                    ; pass tone or fail sweeps
	bsr.w	screen_is_red                   ; screen red (a start-up check failed)?
	beq.s	menu_check_terminal             ; yes: keep the start-up messages
main_menu:	; from: menu_wait_space, run_q_tests, floppy_menu_choices
	bsr.w	clear_screen                    ; clear the screen
	move.w	#$3,$ffff8240.w                 ; palette 0, background blue
	andi.b	#$c7,mode_flags.w               ; mode flags: Q/Z, several and repeat off
	moveq	#18,d1                          ; IKBD $12: mouse off
	bsr.w	ikbd_send                       ; send it
	bsr.w	psg_sound_off                   ; all PSG voices silent
menu_check_terminal:
	bclr	#$1,mode_flags.w                ; assume a terminal
	move.b	$fffffa2f.w,d0                  ; MFP UDR, drop any waiting byte
	move.b	#$d,d0                          ; (rs232_send sends d1, not d0)
	bsr.w	serial_put_char                 ; out to RS232
	moveq	#40,d0                          ; 41 delays, about 90 ms
menu_check_terminal_wait:
	bsr.s	delay                           ; wait
	dbra	d0,menu_check_terminal_wait     ; loop
	bsr.w	rs232_byte_waiting              ; a byte back (loopback plug)?
	beq.s	menu_title                      ; no: a terminal may be there
	move.b	$fffffa2f.w,d0                  ; MFP UDR, drop it
	bset	#$1,mode_flags.w                ; mode flags bit 1: no terminal, screen only
menu_title:
	movea.l	#msg_title,a5                   ; "STe Field Service Diagnostic Rev. 1.9 ... 1991, Atari Corp."
	bsr.w	print_string                    ; print it
	bsr.w	put_tab                         ; tab
	move.l	ram_top.w,d0                    ; RAM size
	swap	d0                              ; in units of 64K
	andi.l	#$fe,d0                         ; even
	moveq	#0,d1                           ; (not used)
	lea	ram_size_codes,a0               ; sizes 256K, 512K, 1M, 2M, 4M
	moveq	#4,d1                           ; 5 sizes
menu_ram_size_find:
	cmp.b	0(a0,d1.w),d0                   ; this size?
	beq.s	menu_ram_size_print             ; found
	dbra	d1,menu_ram_size_find           ; next size
	bra.s	menu_keyboard_revision          ; other size: print none
menu_ram_size_print:
	lea	ram_size_texts,a0               ; "256k RAM" ... "4M RAM" texts
	lsl.w	#2,d1                           ; text pointer offset
	movea.l	0(a0,d1.w),a5                   ; its text
	bsr.w	print_string                    ; print it
menu_keyboard_revision:
	tst.b	keyboard_revision.w             ; keyboard revision kept?
	bmi.s	menu_frequency                  ; no (a bad reply byte)
	lea	msg_keyboard_rev,a5             ; " Keyboard rev. "
	bsr.w	print_string                    ; print it
	move.b	keyboard_revision.w,d0          ; the revision
	bsr.w	word_to_bcd                     ; in BCD
	bsr.w	print_hex_digit                 ; one digit
menu_frequency:
	bsr.w	put_tab                         ; tab
	move.b	$ffff820a.w,d0                  ; sync mode
	btst	#$1,d0                          ; bit 1 set: 50 Hz
	beq.s	menu_frequency_60               ; no: 60 Hz
	lea	msg_50_hz,a5                    ; "50 Hz"
	bra.s	menu_frequency_print            ; print it
menu_frequency_60:
	lea	msg_60_hz,a5                    ; "60 Hz"
menu_frequency_print:
	bsr.w	print_string                    ; print it
	bsr.w	print_tos_version               ; TOS version from the ROM header
	bsr.w	print_newline                   ; new line
	movea.l	#menu_text,a5                   ; the menu text ($05 shows the next letter inverse)
	bsr.w	print_menu_string               ; print it
	btst	#$0,mode_flags.w                ; keyboard failed?
	bne.s	menu_read_command               ; yes: leave it alone
	moveq	#26,d1                          ; IKBD $1A: joysticks off
	bsr.w	ikbd_send                       ; send it
menu_read_command:
	bsr.w	read_command                    ; read a command line (direct commands run there)
	tst.w	d0                              ; anything to run?
	beq.w	main_menu                       ; empty or a direct command: menu again
	move.l	#$1,test_cycle.w                ; cycle 1
	bclr	#$6,mode_flags.w                ; mode flags: test screen not up yet
	lea	test_letters.w,a6               ; letters kept from $257 up
	lea	number_digits.w,a3              ; repeat count digits from $267 up
menu_parse_count:
	move.b	-(a4),d0                        ; from the end of the line back
	cmpi.b	#$30,d0                         ; a digit?
	blt.s	menu_parse_letter               ; no
	cmpi.b	#$39,d0                         ; '9'
	bgt.s	menu_parse_letter               ; no
	move.b	d0,(a3)+                        ; keep it (lowest digit first)
	bra.s	menu_parse_count                ; next character
menu_parse_letter_next:
	cmpa.l	#$237,a4                        ; line start?
	ble.w	menu_parse_done                 ; yes: all read
	move.b	-(a4),d0                        ; previous character
menu_parse_letter:
	lea	test_letters_all,a0             ; "ROGMSTDPFYQZ"
	moveq	#0,d7                           ; letter index
menu_parse_letter_find:
	cmp.b	0(a0,d7.w),d0                   ; a test letter?
	beq.s	menu_parse_letter_keep          ; found
	addq.w	#1,d7                           ; next letter
	cmpi.b	#$c,d7                          ; 12 letters, tried them all? (12 letters)
	bne.s	menu_parse_letter_find          ; no
	bra.s	menu_parse_letter_next          ; not a test letter: skip it
menu_parse_letter_keep:
	move.b	d0,(a6)+                        ; keep it (last typed first)
	bra.s	menu_parse_letter_next          ; next character
menu_parse_done:
	bclr	#$5,mode_flags.w                ; repeat count off
	cmpa.l	#$267,a3                        ; any digits?
	bne.s	menu_parse_repeat_count         ; yes
	move.l	#$1,repeat_count.w              ; none: one pass
	bra.s	menu_set_flags                  ; on
menu_parse_repeat_count:
	lea	number_digits.w,a0              ; the digits, lowest first
	clr.l	repeat_count.w                  ; clear the count
	bsr.w	decimal_to_number               ; to a number
	move.l	d2,repeat_count.w               ; repeat count
menu_set_flags:
	bset	#$5,mode_flags.w                ; mode flags bit 5: repeat count
	bset	#$4,mode_flags.w                ; mode flags bit 4: several letters
	cmpi.l	#$1,repeat_count.w              ; one pass?
	bne.s	menu_check_letter_count         ; no
	bclr	#$5,mode_flags.w                ; one pass: no repeat
menu_check_letter_count:
	cmpa.l	#$258,a6                        ; more than one letter?
	bgt.s	menu_set_unattended             ; no
	bclr	#$4,mode_flags.w                ; one letter only
menu_set_unattended:
	clr.b	unattended.w                    ; unattended off
	move.b	mode_flags.w,d0                 ; mode flags
	andi.b	#$38,d0                         ; sequence, several tests or a repeat?
	beq.w	menu_set_first_test             ; no
	move.b	#$ff,unattended.w               ; unattended on
menu_set_first_test:
	suba.l	#$1,a6                          ; the first letter typed
	move.l	a6,first_test_ptr.w             ; start of the letters
menu_run_pass:	; from: menu_run_test_advance
	move.l	first_test_ptr.w,test_ptr.w     ; start of a pass
menu_run_test:	; from: menu_run_test_advance
	movea.l	test_ptr.w,a0                   ; current letter pointer
	move.b	(a0),d0                         ; the letter
	lea	test_letters_all,a1             ; "ROGMSTDPFYQZ"
	clr.l	d2                              ; letter index
menu_run_test_find:
	cmp.b	0(a1,d2.w),d0                   ; this letter?
	beq.s	menu_run_test_found             ; found
	addq.w	#1,d2                           ; next letter
	cmpi.b	#$c,d2                          ; 12 letters
	beq.w	main_menu                       ; not a test letter: back to the menu
	bra.s	menu_run_test_find              ; next
menu_run_test_found:
	btst	#$6,mode_flags.w                ; test screen already up?
	bne.s	menu_run_test_clear_status      ; no
	bsr.w	clear_screen                    ; clear the screen
	move.w	#$2,scroll_top.w                ; scroll top: keep the 2 top lines
	bsr.w	print_newline                   ; new line
	bsr.w	print_newline                   ; new line
	bra.s	menu_run_test_call              ; on
menu_run_test_clear_status:
	bsr.w	clear_status_line               ; clear the status line
menu_run_test_call:
	bset	#$6,mode_flags.w                ; mode flags bit 6: test screen up
	lea	test_routines,a0                ; test entry table (12 longs, same order)
	lsl.b	#2,d2                           ; table offset
	movea.l	0(a0,d2.w),a1                   ; the test
	jsr	(a1)                            ; run the test (R O G M S T D P F Y Q Z)
	bsr.w	screen_is_red                   ; screen red (failed)?
	beq.s	menu_run_test_result            ; yes: stay red
	move.w	#$51,$ffff8240.w                ; palette 0, pass colour
menu_run_test_result:
	move.b	mode_flags.w,d0
	andi.b	#$30,d0                         ; several tests or a repeat?
	beq.s	menu_wait_space                 ; no: wait for Space
	bsr.w	check_esc                       ; ESC? Z set: go on
	beq.s	menu_run_test_pause             ; no, or RET after it: go on
	bne.w	main_menu                       ; quit: back to the menu
menu_run_test_pause:
	move.w	#$12c,d1                        ; 301 delays, about 0.7 s
menu_run_test_pause_loop:
	bsr.w	delay                           ; wait
	dbra	d1,menu_run_test_pause_loop     ; loop

;------------------------------------------------------------------------------
; menu_run_test_advance: the next letter of the pass; after the last one "Cycle: n", one pass less,
; and the next pass while passes are left.
;------------------------------------------------------------------------------
menu_run_test_advance:	; from: run_q_tests
	subi.l	#$1,test_ptr.w                  ; next letter
	move.l	test_ptr.w,d0                   ; at the last letter?
	cmp.l	#$257,d0                        ; the letters start at $257
	bge.w	menu_run_test                   ; more
	bsr.w	print_cycle                     ; "Cycle: n" at the top, n + 1
	subi.l	#$1,repeat_count.w              ; one pass less
	tst.l	repeat_count.w                  ; passes left?
	beq.s	menu_wait_space                 ; all done
	bsr.w	result_sound                    ; pass tone or fail sweeps
	bra.w	menu_run_pass                   ; next pass

;------------------------------------------------------------------------------
; menu_wait_space: unless mode flags bit 7 was set (back to the menu at once), the result sound,
; then waits for Space and goes back to the menu.
;------------------------------------------------------------------------------
menu_wait_space:	; from: menu_start, menu_run_test_advance, run_q_tests
	bclr	#$7,mode_flags.w                ; mode flags bit 7 set?
	bne.s	menu_wait_space_done            ; yes: straight to the menu
	bsr.w	result_sound                    ; pass tone or fail sweeps
menu_wait_space_key:
	bsr.w	get_key                         ; wait for a key
	cmpi.b	#$20,d0                         ; Space?
	bne.s	menu_wait_space_key             ; no: wait
menu_wait_space_done:
	bra.w	main_menu                       ; back to the menu

;------------------------------------------------------------------------------
; run_q_tests: Q, all unattended tests: runs "ROMSTDPFY" (9 tests) in order with a "Pass" line and
; background colour for each, ESC to stop; then "Q Tests Completed" and the next pass while the
; repeat count lasts. run_z_tests: Z, the internal tests "ROTFG" (5), "Z Tests Completed". If Q or Z
; was typed with other letters, the run goes on with the next letter instead.
;------------------------------------------------------------------------------
run_q_tests:	; from: test_routines
	move.l	#test_letters_q,test_letters_ptr.w ; "ROMSTDPFY"
	move.b	#$9,test_sequence_count.w       ; 9 tests
	move.l	#msg_q_tests_completed,run_done_message.w ; "Q Tests Completed"
	bra.s	run_sequence_start              ; run them
run_z_tests:	; from: test_routines
	move.l	#test_letters_z,test_letters_ptr.w ; "ROTFG"
	move.b	#$5,test_sequence_count.w       ; 5 tests
	move.l	#msg_z_tests_completed,run_done_message.w ; "Z Tests Completed"
run_sequence_start:
	move.b	#$ff,unattended.w               ; unattended on
	bset	#$3,mode_flags.w                ; mode flags bit 3: Q/Z running
	bsr.w	print_newline                   ; new line
	bsr.w	print_newline                   ; new line
	move.w	#$2,scroll_top.w                ; scroll top: keep the 2 top lines
run_sequence_pass:
	clr.b	test_sequence_index.w           ; from the first test
run_sequence_next:
	clr.l	d0                              ; index
	move.b	test_sequence_index.w,d0        ; which test
	movea.l	test_letters_ptr.w,a0           ; letters to run
	move.b	0(a0,d0.w),d1                   ; the test letter
	lea	test_letters_all,a1             ; "ROGMSTDPFYQZ"
	clr.l	d2                              ; letter index
run_sequence_find:
	cmp.b	0(a1,d2.w),d1                   ; this letter?
	beq.s	run_sequence_call               ; found
	addq.w	#1,d2                           ; next letter
	bra.s	run_sequence_find               ; next
run_sequence_call:
	lea	test_routines,a0                ; test entry table (12 longs, same order)
	lsl.w	#2,d2                           ; table offset
	movea.l	0(a0,d2.w),a1                   ; the test
	jsr	(a1)                            ; run the test
	bsr.w	screen_is_red                   ; screen red (failed)?
	beq.s	run_sequence_check_esc          ; yes: stay red
	move.w	#$51,$ffff8240.w                ; palette 0, no: pass colour...
	lea	msg_pass,a5                     ; ..."Pass" at the top right
	bsr.w	show_result                     ; show it
run_sequence_check_esc:
	bsr.w	check_esc                       ; ESC pressed?
	bne.w	main_menu                       ; quit: back to the menu
	bsr.w	pause_clear_status              ; pause, clear the status line
	bclr	#$7,mode_flags.w                ; mode flags bit 7 off
	addi.b	#$1,test_sequence_index.w       ; next test
	move.b	test_sequence_count.w,d0        ; number of tests
	cmp.b	test_sequence_index.w,d0        ; all run?
	bne.s	run_sequence_next               ; more
	movea.l	run_done_message.w,a5           ; "Q/Z Tests Completed"
	bsr.w	show_status                     ; show it in the status line
	btst	#$4,mode_flags.w                ; several letters typed?
	bne.w	menu_run_test_advance           ; run them
	bsr.w	print_cycle                     ; "Cycle: n", one more
	subi.l	#$1,repeat_count.w              ; one pass less
	tst.l	repeat_count.w                  ; passes left?
	bne.w	run_sequence_pass               ; yes: again
	bsr.w	screen_is_red                   ; screen red?
	beq.s	run_sequence_done               ; yes: stay red
	move.w	#$51,$ffff8240.w                ; palette 0, no: pass colour...
	lea	msg_pass,a5                     ; ..."Pass" at the top right
	bsr.w	show_result                     ; show it
run_sequence_done:
	bra.w	menu_wait_space                 ; wait for Space

;------------------------------------------------------------------------------
; pause_clear_status: waits 301 delays (about 0.7 s), then clear_status_line. Changes d0, d1, a0.
;------------------------------------------------------------------------------
pause_clear_status:	; from: run_q_tests
	move.w	#$12c,d1                        ; 301 delays
pause_clear_status_loop:
	bsr.w	delay                           ; wait
	dbra	d1,pause_clear_status_loop      ; loop
	bsr.w	clear_status_line               ; clear the status line
	rts                                     ; done

;------------------------------------------------------------------------------
; clear_status_line: blanks the top line (145 spaces from home) and puts the cursor back.
; Changes d0, d1, a0.
;------------------------------------------------------------------------------
clear_status_line:	; from: menu_start, pause_clear_status, detect_drive_types
	bsr.w	save_cursor                     ; keep the cursor
	bsr.w	cursor_home                     ; home
	move.w	#$91,d1                         ; 145 spaces
	bsr.w	print_spaces                    ; print them
	bsr.w	restore_cursor                  ; cursor back
	rts                                     ; done

;------------------------------------------------------------------------------
; check_esc: drops waiting keys up to an ESC. With an ESC: "Stopped. Press RET to continue, other
; key to quit.", waits for a key and clears that line again. Out: Z set to go on (no ESC, or RET),
; Z clear to quit. ask_stopped: the question only. Changes d0, d1, a0-a3, a5.
;------------------------------------------------------------------------------
check_esc:	; from: menu_start, run_q_tests, floppy_exerciser
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
	move.w	cursor_row.w,d1                 ; the cursor row
	clr.w	d0                              ; column 0
	bsr.w	set_cursor                      ; cursor to the line start
	bsr.w	clear_to_line_end               ; clear the line
	move.b	(sp)+,d0                        ; the answer
	cmpi.b	#$d,d0                          ; RET?
	beq.s	check_esc_continue              ; go on
	andi.b	#$1b,ccr                        ; Z clear: quit
	rts                                     ; done
check_esc_continue:	; from: check_esc
	ori.b	#$4,ccr                         ; Z set: go on
	rts                                     ; done

;------------------------------------------------------------------------------
; print_cycle: "Cycle: n" at column 66, row 1 with the BCD pass number in $216, then adds 1 to it
; (BCD). The cursor is put back. Changes d0, d1, a0, a1, a5.
;------------------------------------------------------------------------------
print_cycle:	; from: menu_run_test_advance, run_q_tests, floppy_exerciser
	bsr.w	save_cursor                     ; keep the cursor
	moveq	#66,d0                          ; column 66
	moveq	#1,d1                           ; row 1
	bsr.w	set_cursor                      ; cursor there
	lea	msg_cycle,a5                    ; "Cycle: "
	bsr.w	print_string                    ; print it
	movea.l	test_cycle.w,a0                 ; BCD pass number
	bsr.w	print_hex_address               ; 6 BCD digits
	bsr.w	print_newline                   ; new line
	move.l	#$1,scratch_long.w              ; BCD 1
	lea	first_test_ptr.w,a1             ; source end
	lea	scratch_long.w,a0               ; destination end
	moveq	#2,d0                           ; 3 bytes
print_cycle_add:
	abcd	-(a1),-(a0)                     ; pass number + 1, BCD
	dbra	d0,print_cycle_add              ; loop
	bsr.w	restore_cursor                  ; cursor back
	rts                                     ; done

;------------------------------------------------------------------------------
; screen_is_red: Out: Z set if the background is red ($500 in the 3-bit colour bits): a test failed.
; Changes d0.
;------------------------------------------------------------------------------
screen_is_red:	; from: menu_start, run_q_tests, result_sound, floppy_quick_test, floppy_interchange
	move.w	$ffff8240.w,d0                  ; palette 0
	andi.w	#$777,d0                        ; 3-bit colour
	cmpi.w	#$500,d0                        ; red?
	rts                                     ; Z set: red

;------------------------------------------------------------------------------
; read_command: reads a menu command line into $237-$256 (echoed), from the keyboard or the RS232
; terminal. Direct commands run at once and return d0 = 0: Help key or "?" help pages, E memory
; utility, B RS232 rate, X 50/60 Hz, J hard disk, H high resolution, A audio, C colour, K keyboard,
; "$" date. Backspace edits; more than 32 characters: "Keyboard buffer full", d0 = 0. RET ends the
; line; from the keyboard it then waits for the Return (or keypad Enter) release.
; Out: d0 = 0 nothing to run, else the line is in $237 and a4 points past its end. Changes d1, a4.
;------------------------------------------------------------------------------
read_command:	; from: menu_start, floppy_alignment
	lea	line_buffer.w,a4                ; the line buffer
	moveq	#63,d0                          ; clear 64 bytes (the line, letters and digits)
read_command_clear:
	clr.b	(a4)+                           ; clear a byte
	dbra	d0,read_command_clear           ; loop
	lea	line_buffer.w,a4                ; start of the line
	bsr.w	flush_input                     ; drop waiting keys
read_command_key:
	bsr.w	get_key                         ; next key
	cmpi.b	#$1b,d0                         ; ESC: kept in the line
	beq.w	read_command_store              ; keep it
	cmpi.b	#$62,d1                         ; Help key?
	beq.w	read_command_help               ; help pages
	cmpi.b	#$3f,d0                         ; "?"
	beq.w	read_command_help               ; help pages
	cmpi.b	#$45,d0                         ; "E"
	beq.w	read_command_memory_utility     ; memory utility
	cmpi.b	#$42,d0                         ; "B"
	beq.w	cmd_rs232_rate                  ; RS232 rate
	cmpi.b	#$58,d0                         ; "X"
	beq.w	cmd_toggle_50_60hz              ; toggle 50/60 Hz
	cmpi.b	#$4a,d0                         ; "J"
	beq.w	read_command_hard_disk          ; hard disk test
	cmpi.b	#$48,d0                         ; "H"
	beq.w	read_command_high_res           ; high resolution test
	cmpi.b	#$41,d0                         ; "A"
	beq.w	read_command_audio              ; audio test
	cmpi.b	#$43,d0                         ; "C"
	beq.w	read_command_colour             ; colour test
	cmpi.b	#$4b,d0                         ; "K"
	beq.w	read_command_keyboard           ; keyboard test
	cmpi.b	#$24,d0                         ; "$"
	beq.w	read_command_date               ; date
	cmpi.b	#$8,d0                          ; backspace?
	bne.w	read_command_not_backspace      ; no
	cmpa.l	#$237,a4                        ; line empty?
	beq.s	read_command_key                ; yes: ignore it
	bsr.w	put_backspace                   ; back one on the screen
	clr.b	-(a4)                           ; and in the line
	bra.s	read_command_key                ; next key
read_command_not_backspace:
	cmpi.b	#$d,d0                          ; RET?
	beq.s	read_command_return             ; yes: end of the line
read_command_store:
	move.b	d0,(a4)+                        ; into the line
	move.b	d0,d1                           ; print it
	bsr.w	put_char                        ; echo it
	cmpa.l	#$256,a4                        ; line full?
	ble.w	read_command_key                ; no: next key
	lea	msg_keyboard_buffer_full,a5     ; "Keyboard buffer full"
	bsr.w	print_string                    ; print it
read_command_none:
	moveq	#0,d0                           ; nothing to run
	rts                                     ; done
read_command_return:
	cmpa.l	#$237,a4                        ; line empty?
	beq.s	read_command_none               ; yes: nothing to run
	tst.b	d1                              ; RET from RS232: done
	beq.s	read_command_done               ; yes
	cmpi.b	#$9c,key_release.w              ; Return released?
	beq.s	read_command_done               ; yes
	cmpi.b	#$f2,key_release.w              ; keypad Enter released?
	bne.s	read_command_return             ; wait
read_command_done:
	rts                                     ; d0 = RET: run the line
read_command_memory_utility:
	bsr.w	memory_utility                  ; E: examine/modify memory
	bra.w	read_command_direct_done        ; back to the menu
read_command_audio:
	bsr.w	clear_screen                    ; clear the screen
	bsr.w	audio_test                      ; A: audio test
	bra.w	read_command_direct_done        ; back to the menu
read_command_high_res:
	bsr.w	clear_screen                    ; clear the screen
	bsr.w	mono_monitor_test               ; H: high resolution test
	bra.w	read_command_direct_done        ; back to the menu
read_command_hard_disk:
	bsr.w	clear_screen                    ; clear the screen
	bsr.w	hd_test                         ; J: hard disk write/read test
	bra.w	read_command_direct_done        ; back to the menu
read_command_colour:
	bsr.w	clear_screen                    ; clear the screen
	bsr.w	colour_test                     ; C: colour test
	bra.w	read_command_direct_done        ; back to the menu
read_command_keyboard:
	bsr.w	clear_screen                    ; clear the screen
	bsr.w	keyboard_test                   ; K: keyboard test
	bra.w	read_command_direct_done        ; back to the menu
read_command_date:
	bsr.w	clear_screen                    ; clear the screen
	lea	msg_date,a5                     ; "MAY 24, 1991"
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; wait for a key
	cmpi.b	#$2a,d0                         ; "*" next?
	bne.s	read_command_date_done          ; no
	lea	msg_author,a5                   ; " by TF"
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; wait for a key
read_command_date_done:
	bra.w	read_command_direct_done        ; back to the menu
cmd_toggle_50_60hz:
	btst	#$1,$ffff8260.w                 ; shift mode, X: not in high resolution
	bne.w	read_command_direct_done        ; high resolution: no change
	move.b	$ffff820a.w,d0                  ; sync mode
	eori.b	#$2,d0                          ; 50 <-> 60 Hz
	move.b	d0,$ffff820a.w                  ; sync mode
	bra.s	read_command_direct_done        ; back to the menu
read_command_help:
	bsr.w	clear_screen                    ; clear the screen
	lea	help_text,a5                    ; help page 1
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; wait for a key
	lea	help_notes_text,a5              ; help page 2
	bsr.w	print_string                    ; print it
	bsr.w	get_key                         ; wait for a key
read_command_direct_done:	; from: cmd_rs232_rate
	moveq	#0,d0                           ; direct command done: back to the menu
	rts                                     ; done

;------------------------------------------------------------------------------
; cmd_rs232_rate: B: the RS232 rate. Up arrow faster, down arrow slower (Timer D data 2 to $40,
; 19200 to 600 baud, wrapping round), RET or Space back to the menu. The port is set at once.
;------------------------------------------------------------------------------
cmd_rs232_rate:	; from: read_command
	bsr.w	clear_screen                    ; clear the screen
	lea	msg_increase_decrease,a5        ; "Increase (up arrow), Decrease (down arrow)"
	bsr.w	print_string                    ; print it
cmd_rs232_rate_show:
	moveq	#0,d0                           ; column 0
	moveq	#1,d1                           ; row 1
	bsr.w	set_cursor                      ; cursor there
	clr.l	d0                              ; the rate setting
	move.w	rs232_rate.w,d0                 ; the rate setting
	bsr.w	print_rs232_rate                ; print the baud rate
cmd_rs232_rate_key:
	bsr.w	get_key                         ; wait for a key
	cmp.b	#$d,d0                          ; RET or Space: done
	beq.s	cmd_rs232_rate_done             ; RET
	cmp.b	#$20,d0                         ; Space?
	bne.s	cmd_rs232_rate_change           ; no: an arrow?
cmd_rs232_rate_done:
	bra.s	read_command_direct_done        ; back to the menu
cmd_rs232_rate_change:
	move.w	rs232_rate.w,d0                 ; Timer D data
	cmp.b	#$48,d1                         ; up arrow?
	beq.s	cmd_rs232_rate_up               ; faster
	cmp.b	#$50,d1                         ; down arrow?
	bne.s	cmd_rs232_rate_key              ; other key: ignore it
	lsl.w	#1,d0                           ; down: double the divider
	cmp.w	#$40,d0                         ; 600 baud is the lowest
	bls.s	cmd_rs232_rate_set              ; yes
	move.w	#$2,d0                          ; wrap to 19200
	bra.s	cmd_rs232_rate_set              ; set it
cmd_rs232_rate_up:
	lsr.w	#1,d0                           ; up: halve the divider
	cmp.w	#$1,d0                          ; 19200 is the highest
	bhi.s	cmd_rs232_rate_set              ; yes
	move.w	#$40,d0                         ; wrap to 600
cmd_rs232_rate_set:
	move.w	d0,rs232_rate.w                 ; new rate
	bsr.w	rs232_setup                     ; set the port
	bra.s	cmd_rs232_rate_show             ; show it

;------------------------------------------------------------------------------
; word_to_bcd: In d0.w a number. Out: d1 the same in BCD (4 bits a digit). Changes d0, d2, d3.
;------------------------------------------------------------------------------
word_to_bcd:                                    ; from: menu_start, ticks_to_ms, print_sector_number,
                                                ;   print_track_number, hd_test, hd_print_cycle, 1 more
	clr.l	d3                              ; digit position
	clr.l	d1                              ; result
word_to_bcd_loop:
	andi.l	#$ffff,d0                       ; the number as a word
	divu.w	#$a,d0                          ; divide by 10
	move.l	d0,d2                           ; quotient and remainder
	swap	d2                              ; remainder: the next digit
	bsr.w	word_to_bcd_digit               ; add it
	cmp.w	#$a,d0                          ; more digits?
	bge.s	word_to_bcd_loop                ; 10 or more: next digit
	move.w	d0,d2                           ; the top digit
	bsr.w	word_to_bcd_digit               ; the top digit
	rts                                     ; done

;------------------------------------------------------------------------------
; word_to_bcd_digit: ors digit d2 into d1 at bit d3, d3 += 4.
;------------------------------------------------------------------------------
word_to_bcd_digit:	; from: word_to_bcd
	andi.l	#$ff,d2                         ; one digit
	lsl.w	d3,d2                           ; to its position
	or.l	d2,d1                           ; into the result
	add.w	#$4,d3                          ; next position
	rts                                     ; done

;------------------------------------------------------------------------------
; decimal_to_number: In a0 the start, a3 the end of decimal digits stored lowest digit first.
; Out: d2 the number. Changes d0, d1, a0.
;------------------------------------------------------------------------------
decimal_to_number:	; from: menu_start, floppy_alignment
	clr.l	d2                              ; result
	clr.l	d0                              ; digit
	cmpa.l	a0,a3                           ; no digits?
	beq.s	decimal_to_number_done          ; yes: 0
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
	rts                                     ; done

;------------------------------------------------------------------------------
; keyboard_record: Out: a0 = $45A, the keyboard buffer record; a1 = $FFFFFC00, the keyboard ACIA.
;------------------------------------------------------------------------------
keyboard_record:	; from: keyboard_setup, ikbd_send, key_waiting, acia_interrupt
	movea.l	#$45a,a0                        ; keyboard buffer record
	movea.l	#$fffffc00,a1                   ; keyboard ACIA
	rts                                     ; done

;------------------------------------------------------------------------------
; ikbd_send: sends d1 to the IKBD. Waits up to 65480 polls for the ACIA to be ready. Out: Z set if
; sent, Z clear on a timeout. Keeps all registers.
;------------------------------------------------------------------------------
ikbd_send:	; from: menu_start, reset_keyboard_and_check, printer_joystick_test, read_joysticks
	movem.l	d7/a0-a1,-(sp)                  ; save registers
	bsr.s	keyboard_record                 ; a1 = keyboard ACIA
	moveq	#-56,d7                         ; 65480 tries
ikbd_send_wait:
	btst	#$1,0(a1)                       ; transmit register empty?
	bne.s	ikbd_send_byte                  ; yes
	subq.w	#1,d7                           ; count down
	beq.s	ikbd_send_timeout               ; timeout
	bra.s	ikbd_send_wait                  ; wait more
ikbd_send_byte:
	move.b	d1,2(a1)                        ; send it
	ori.b	#$4,ccr                         ; Z set: sent
ikbd_send_done:
	movem.l	(sp)+,d7/a0-a1                  ; restore registers
	rts                                     ; done
ikbd_send_timeout:
	andi.b	#$fb,ccr                        ; Z clear: timeout
	bra.s	ikbd_send_done                  ; restore and return

;------------------------------------------------------------------------------
; flush_input: empties the keyboard buffer and drops a waiting RS232 byte. Keeps all registers.
;------------------------------------------------------------------------------
flush_input:	; from: read_command, read_line
	move.w	d0,-(sp)                        ; keep d0
	clr.w	kbd_buffer_head.w               ; head 0
	clr.w	kbd_buffer_tail.w               ; tail 0
	move.b	$fffffa2f.w,d0                  ; MFP UDR, drop the RS232 byte
	move.w	(sp)+,d0                        ; d0 back
	rts                                     ; done

;------------------------------------------------------------------------------
; key_waiting: Out: d0 = -1 a key in the keyboard buffer, $7F a byte from the RS232 terminal (only
; when the terminal is on), 0 none. rs232_byte_waiting looks at the RS232 port only. Changes a0-a3.
;------------------------------------------------------------------------------
key_waiting:	; from: check_esc, get_key, memory_utility, ram_test, keyboard_test, reset_keyboard_and_check, 7 more
	moveq	#0,d0                           ; nothing yet
	bsr.s	keyboard_record                 ; keyboard buffer record
	lea	6(a0),a2                        ; head
	lea	8(a0),a3                        ; tail
	cmpm.w	(a3)+,(a2)+                     ; buffer empty?
	beq.s	key_waiting_rs232               ; yes: try RS232
	moveq	#-1,d0                          ; keyboard key
	rts                                     ; done
key_waiting_rs232:
	btst	#$1,mode_flags.w                ; RS232 not a terminal (loopback plug)?
	bne.s	key_waiting_none                ; yes: none

rs232_byte_waiting:	; from: menu_start, memory_utility
	tst.b	$fffffa2b.w                     ; MFP RSR, byte received?
	bpl.s	key_waiting_none                ; no
	moveq	#127,d0                         ; RS232 byte
	rts                                     ; done
key_waiting_none:	; from: key_waiting
	moveq	#0,d0                           ; nothing
	rts                                     ; done

;------------------------------------------------------------------------------
; get_key: waits for a key from the keyboard or the RS232 terminal. Out: d0 the ASCII code, a-z in
; upper case; d1 the scan code (0 for RS232). Keeps a0-a3.
;------------------------------------------------------------------------------
get_key:	; from: menu_wait_space, check_esc, ask_stopped, read_command, cmd_rs232_rate, memory_utility, 19 more
	movem.l	a0-a3,-(sp)                     ; save registers
get_key_wait:
	bsr.s	key_waiting                     ; anything?
	tst.w	d0                              ; d0: -1 keyboard, $7F RS232
	beq.s	get_key_wait                    ; wait
	bmi.s	get_key_keyboard                ; keyboard
	btst	#$1,mode_flags.w                ; RS232 not a terminal?
	bne.s	get_key_wait                    ; yes: ignore it
	move.b	$fffffa2f.w,d0                  ; MFP UDR, the RS232 byte
	clr.b	d1                              ; no scan code
	bra.s	get_key_upper                   ; make upper case
get_key_keyboard:
	movea.l	#$45a,a0                        ; keyboard buffer record
	move.w	sr,-(sp)                        ; keep the interrupt level
	ori.w	#$700,sr                        ; no interrupts
	move.w	6(a0),d1                        ; head
	cmp.w	8(a0),d1                        ; = tail: empty
	beq.s	get_key_scan                    ; nothing
	addq.w	#2,d1                           ; next word
	cmp.w	4(a0),d1                        ; past the end?
	bcs.s	get_key_take                    ; no
	moveq	#0,d1                           ; wrap to 0
get_key_take:
	movea.l	0(a0),a1                        ; buffer
	move.w	0(a1,d1.w),d0                   ; scan code and ASCII
	move.w	d1,6(a0)                        ; new head
get_key_scan:
	move.w	(sp)+,sr                        ; interrupt level back
	move.w	d0,d1                           ; both
	and.w	#$7f,d0                         ; d0 ASCII
	lsr.w	#8,d1                           ; d1 scan code
get_key_upper:
	cmpi.b	#$61,d0                         ; lower case?
	blt.s	get_key_done                    ; no
	cmpi.b	#$7a,d0                         ; 'z'
	bgt.s	get_key_done                    ; no
	andi.b	#$df,d0                         ; to upper case
get_key_done:
	movem.l	(sp)+,a0-a3                     ; restore registers
	rts                                     ; done

;------------------------------------------------------------------------------
; bus_error_handler: the normal bus error handler. Red screen, RS232 set up again, then the text,
; " Access Address: " and " Program Counter: " from the 68000 group 0 frame. The first fault at a
; PC is reported and execution carries on with rte after the faulting access (in the memory utility,
; $282 set, it goes back to the prompt); a second fault at the same PC hangs. address_error_handler:
; the same for address errors. d7 is set to $FFFF.
;------------------------------------------------------------------------------
bus_error_handler:	; from: exception_vectors_table
	movea.l	#msg_bus_error,a5               ; "EB Bus Error "
exception_report:
	move.w	#$500,$ffff8240.w               ; palette 0, red
	bsr.w	rs232_setup                     ; RS232 at the set rate
	move.w	#$ffff,d7                       ; fault flag for the caller
	bsr.w	print_string                    ; print the error text
	lea	msg_access_address,a5           ; " Access Address: "
	bsr.w	print_string                    ; print it
	movea.l	2(sp),a0                        ; access address from the frame
	bsr.w	print_hex_address               ; print it
	lea	msg_program_counter,a5          ; " Program Counter: "
	bsr.w	print_string                    ; print it
	movea.l	$a(sp),a0                       ; PC from the frame
	move.l	a0,d0                           ; the PC
	cmp.l	last_fault_pc.w,d0              ; same PC as last time?
	beq.s	exception_report_hang           ; then hang
	move.l	a0,last_fault_pc.w              ; keep it
	bsr.w	print_hex_address               ; print it
	bsr.w	print_newline                   ; new line
	tst.b	memory_utility_active.w         ; memory utility running?
	beq.s	exception_report_return         ; no
	move.l	#memory_utility_prompt,$a(sp)   ; yes: back to its prompt
exception_report_return:
	adda.w	#$8,sp                          ; leave SR and PC
	rte                                     ; carry on
exception_report_hang:
	bsr.w	print_hex_address               ; print the PC
	bra.s	exception_halt_loop             ; hang
address_error_handler:	; from: exception_vectors_table
	movea.l	#msg_address_error,a5           ; "EA Address Error "
	bra.s	exception_report                ; report it
illegal_handler:	; from: exception_vectors_table
	movea.l	#msg_bad_instruction_fetch,a5   ; "E9 Bad instruction fetch"
	bra.s	exception_halt                  ; hang

;------------------------------------------------------------------------------
; exception_error_handler: zero divide, CHK, TRAPV, privilege and trace: "E8 Exception error", hang.
; illegal_handler, line_a_handler, line_f_handler: "E9 Bad instruction fetch", hang.
;------------------------------------------------------------------------------
exception_error_handler:	; from: exception_vectors_table
	movea.l	#msg_exception_error,a5         ; "E8 Exception error"
	bra.s	exception_halt                  ; hang
line_a_handler:	; from: exception_vectors_table
	movea.l	#msg_bad_instruction_fetch,a5   ; "E9 Bad instruction fetch"
	bra.s	exception_halt                  ; hang
line_f_handler:	; from: exception_vectors_table
	movea.l	#msg_bad_instruction_fetch,a5   ; "E9 Bad instruction fetch"
exception_halt:	; from: bus_error_handler
	move.w	#$500,$ffff8240.w               ; palette 0, red
	bsr.w	print_newline                   ; new line
	bsr.w	print_string                    ; print the error text
exception_halt_loop:	; from: bus_error_handler
	bra.s	exception_halt_loop             ; hang

;------------------------------------------------------------------------------
; spurious_handler: "E7 Spurious Interrupt", red, carry on.
;------------------------------------------------------------------------------
spurious_handler:	; from: autovectors_table
	move.w	#$500,$ffff8240.w               ; palette 0, red
	movea.l	#msg_spurious_interrupt,a5      ; "E7 Spurious Interrupt"
	bsr.w	print_string                    ; print it
	rte                                     ; carry on

;------------------------------------------------------------------------------
; autovector_handler: levels 1, 3, 5, 6 and 7: "E6 Autovector error", red, carry on.
;------------------------------------------------------------------------------
autovector_handler:	; from: autovectors_table
	move.w	#$500,$ffff8240.w               ; palette 0, red
	movea.l	#msg_autovector_error,a5        ; "E6 Autovector error"
	bsr.w	print_string                    ; print it
	rte                                     ; carry on

;------------------------------------------------------------------------------
; vbl_handler: the level 4 autovector (VBL): clears $292, the line count the VBL waits poll.
;------------------------------------------------------------------------------
vbl_handler:                                    ; from: test_ram_range, colour_test, floppy_menu_choices,
                                                ;   floppy_quick_test, detect_drive_types, floppy_motor_vbl, 1 more
	clr.b	vbl_flag.w                      ; a new frame
	rte                                     ; done

;------------------------------------------------------------------------------
; hbl_handler: the level 2 autovector (HBL): clears the interrupt flags word $208.
;------------------------------------------------------------------------------
hbl_handler:	; from: autovectors_table
	clr.w	interrupt_events.w              ; all flags clear
	rte                                     ; done

;------------------------------------------------------------------------------
; monitor_change_handler: MFP GPIP7 (monitor plugged or changed): returns to cold_start, so the whole
; cartridge starts again with the resolution for the new monitor.
;------------------------------------------------------------------------------
monitor_change_handler:	; from: mono_monitor_test, mfp_vectors_table
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
	move.w	d0,-(sp)                        ; keep d0
	move.w	sr,d0                           ; keep the interrupt level
	move.w	#$2200,sr                       ; let the VBL in
	move.b	#$1,vbl_flag.w                  ; wait for a VBL to clear it
high_res_switch_wait_vbl:
	tst.b	vbl_flag.w                      ; cleared by the VBL?
	bne.s	high_res_switch_wait_vbl        ; not yet
	move.w	d0,sr                           ; interrupt level back
	move.b	#$2,$ffff8260.w                 ; shift mode, high resolution
	move.w	#$3,$ffff8240.w                 ; palette 0, background blue
	bclr	#$7,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	move.w	(sp)+,d0                        ; d0 back
	rte                                     ; done

;------------------------------------------------------------------------------
; ring_indicator_handler: MFP GPIP6 (RS232 RI): clears bit 6 of $208.
;------------------------------------------------------------------------------
ring_indicator_handler:	; from: mfp_vectors_table
	bclr	#$6,interrupt_events.w          ; RI seen
	bclr	#$6,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte                                     ; done

;------------------------------------------------------------------------------
; rs232_receive_handler: MFP receive buffer full: keeps the byte in $286 and ors the overrun, parity
; and frame error bits into $288.
;------------------------------------------------------------------------------
rs232_receive_handler:	; from: mfp_vectors_table
	move.l	d0,-(sp)                        ; keep d0
	move.b	$fffffa2b.w,d0                  ; MFP RSR
	andi.b	#$70,d0                         ; error bits
	or.b	d0,rs232_rx_errors.w            ; kept
	move.b	$fffffa2f.w,rs232_received.w    ; MFP UDR
	bclr	#$4,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	move.l	(sp)+,d0                        ; d0 back
	rte                                     ; done

;------------------------------------------------------------------------------
; rs232_transmit_handler: MFP transmit buffer empty: keeps the transmitter status in $289 and sends
; the next byte of the count $01..$FF in $287; stops after $FF.
;------------------------------------------------------------------------------
rs232_transmit_handler:	; from: mfp_vectors_table
	move.b	$fffffa2d.w,rs232_tx_status.w   ; MFP TSR
	cmpi.b	#$ff,rs232_sent.w               ; all bytes sent?
	beq.s	rs232_transmit_done             ; yes: stop
	addi.b	#$1,rs232_sent.w                ; next byte
	move.b	rs232_sent.w,$fffffa2f.w        ; MFP UDR
rs232_transmit_done:
	bclr	#$2,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte                                     ; done

;------------------------------------------------------------------------------
; rs232_receive_error_handler: MFP receive error: keeps the receiver status in $288.
;------------------------------------------------------------------------------
rs232_receive_error_handler:	; from: mfp_vectors_table
	move.b	$fffffa2b.w,rs232_rx_errors.w   ; MFP RSR
	bclr	#$3,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte                                     ; done

;------------------------------------------------------------------------------
; rs232_transmit_error_handler: MFP transmit error: keeps the transmitter status in $289.
;------------------------------------------------------------------------------
rs232_transmit_error_handler:	; from: mfp_vectors_table
	move.b	$fffffa2d.w,rs232_tx_status.w   ; MFP TSR
	bclr	#$1,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte                                     ; done

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
	rte                                     ; done
timer_b_count_done:
	bclr	#$0,$fffffa07.w                 ; MFP IERA, Timer B off
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte                                     ; done

;------------------------------------------------------------------------------
; colour_bands_handler: a Timer B handler that sets all 16 colours to the next entry of
; colour_bars_st on each of 64 lines: $292 counts the lines (cleared by the VBL), $294 is the
; byte offset into the table. Nothing installs it: its address is not in the cartridge.
;------------------------------------------------------------------------------
colour_bands_handler:
	movem.l	d0-d1/a0,-(sp)                  ; save registers
	cmpi.b	#$3f,vbl_flag.w                 ; past line 63?
	bgt.s	colour_bands_done               ; yes: nothing
	cmpi.b	#$0,vbl_flag.w                  ; first line of the frame?
	bne.s	colour_bands_line               ; no
	clr.b	colour_shade.w                  ; start of the table
colour_bands_line:
	moveq	#33,d0                          ; wait into the line
colour_bands_delay:
	dbra	d0,colour_bands_delay           ; loop
	movea.l	#colour_bars_st,a0              ; the colours
	moveq	#0,d0                           ; table offset
	move.b	colour_shade.w,d0               ; this line's offset
	move.w	0(a0,d0.w),d1                   ; this line's colour
	moveq	#15,d0                          ; 16 colours
	movea.l	#$ffff8240,a0                   ; colour 0
colour_bands_set:
	move.w	d1,(a0)+                        ; set a colour
	dbra	d0,colour_bands_set             ; loop
	addq.b	#2,colour_shade.w               ; next entry
colour_bands_done:
	movea.l	#$fffffa01,a0                   ; MFP
	bclr	#$0,$e(a0)                      ; end of interrupt (ISRA bit 0)
	addq.b	#1,vbl_flag.w                   ; one more line
	movem.l	(sp)+,d0-d1/a0                  ; restore registers
	rte                                     ; done

;------------------------------------------------------------------------------
; colour_bars_st: one colour a line for colour_bands_handler, which nothing installs. The handler
; sets all 16 palette registers to the word at offset ($294) and adds 2 each line, for 64 lines.
; Seven ramps - red, green, blue, cyan, yellow, magenta and white - each a black line and then the 8
; ST levels 0 to 7; one black word at the end.
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
fdc_interrupt:	; from: mfp_vectors_table
	bclr	#$0,interrupt_events.w          ; clear event bit 0
	bclr	#$80,$fffffa11.w                ; MFP ISRB, clear ISRB bit 0 (meant: bit 7)
	rte                                     ; rte

;------------------------------------------------------------------------------
; acia_interrupt: MFP GPIP4 (keyboard and MIDI ACIAs) interrupt handler, installed at $118 by
; keyboard_setup and by the MFP vector table. Services the MIDI ACIA (buffer record $620) and the
; keyboard ACIA (buffer record $45A), then clears ISRB bit 6 and goes round again while GPIP4 is
; still low (another byte waiting). The hooks $48C and $488 are loaded into a3 but not called.
;------------------------------------------------------------------------------
acia_interrupt:	; from: keyboard_setup, mfp_vectors_table
	movem.l	d0-d7/a0-a6,-(sp)               ; save all
acia_interrupt_loop:
	bsr.w	midi_record_and_acia            ; a0 MIDI record, a1 MIDI ACIA
	movea.l	midi_service_hook.w,a3          ; MIDI hook (not used)
	bsr.w	acia_service                    ; service the MIDI ACIA
	bsr.w	keyboard_record                 ; a0 = keyboard buffer record $45c, a1 = keyboard ACIA
	movea.l	kbd_service_hook.w,a3           ; keyboard hook (not used)
	bsr.w	acia_service                    ; service the keyboard ACIA
	movea.l	#$fffffa01,a1                   ; the MFP
	bclr	#$6,$10(a1)                     ; clear ISRB bit 6 (ACIA)
	btst	#$4,0(a1)                       ; GPIP4 still low?
	bne.s	acia_interrupt_done             ; no: done
	bra.s	acia_interrupt_loop             ; yes: service both again
acia_interrupt_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; restore
	rte                                     ; rte

;------------------------------------------------------------------------------
; acia_service: In a0 the buffer record, a1 the ACIA. If this ACIA is interrupting, a received byte
; goes to ikbd_receive_byte; a receive error (or an interrupt with nothing received) master-resets
; the ACIA and sets it to /64 8N1 with the receive interrupt again. Changes d0, d1, d7, a2.
;------------------------------------------------------------------------------
acia_service:	; from: acia_interrupt
	bsr.w	midi_read_status                ; status, kept at record + $1C
	btst	#$7,d7                          ; is this ACIA interrupting?
	beq.s	acia_service_done               ; no: return
acia_service_receive:
	btst	#$0,d7                          ; receive register full?
	beq.s	acia_service_reset              ; no: reset the ACIA
	movem.l	a0-a3,-(sp)                     ; keep the registers
	bsr.w	ikbd_receive_byte               ; store the received byte
	movem.l	(sp)+,a0-a3                     ; registers back
	andi.b	#$7c,d7                         ; error and line status bits
	tst.b	d7                              ; any?
	beq.s	acia_service_done               ; none: return
acia_service_reset:
	move.b	#$3,0(a1)                       ; master reset
	move.b	#$96,0(a1)                      ; divide by 64, 8 bits, 1 stop, receive interrupt on

;------------------------------------------------------------------------------
; acia_service_done: the rts that ends acia_service; its address is also the keyboard hook in $488.
;------------------------------------------------------------------------------
acia_service_done:	; from: keyboard_setup, acia_service
	rts                                     ; done

;------------------------------------------------------------------------------
; ikbd_receive_byte: In a0 the buffer record, a1 the ACIA. Reads the received byte. MIDI: the byte goes
; into the MIDI buffer. Keyboard: bytes of a packet ($FC clock: 6 bytes to $27C-$281; $FD joystick
; and other $F4-$FF headers: 2 bytes to $234-$235) are kept, last byte first; with $490 bit 3 set,
; $F0-$F3 (the reset reply) goes into the keyboard buffer as $Fx00. Shift presses and releases set
; and clear $492 (the shifted key map offset, $80); other releases go to $28A and the release ring
; $480-$487; presses go into the keyboard buffer as scan code and ASCII from the key maps.
; Changes d0, d1, a0, a2.
;------------------------------------------------------------------------------
ikbd_receive_byte:	; from: acia_service
	moveq	#0,d0                           ; clear the top bits
	move.b	2(a1),d0                        ; the byte
	cmpa.l	#$45a,a0                        ; the keyboard record?
	bne.w	midi_buffer_put                 ; no: MIDI
	tst.b	ikbd_bytes_left.w               ; packet bytes left?
	beq.w	ikbd_header                     ; no: a header or a key
	subi.b	#$1,ikbd_bytes_left.w           ; one less
	bne.w	ikbd_packet_select              ; more to come
	clr.b	ikbd_packet_flags.w             ; packet complete
ikbd_packet_select:
	btst	#$1,ikbd_packet_flags.w         ; clock packet?
	bne.w	ikbd_packet_clock               ; yes
	lea	ikbd_data_first.w,a0            ; joystick or mouse bytes
	bra.s	ikbd_packet_store               ; store it
ikbd_packet_clock:
	lea	ikbd_clock_packet.w,a0          ; clock bytes
ikbd_packet_store:
	moveq	#0,d1                           ; index
	move.b	ikbd_bytes_left.w,d1            ; = bytes left
	move.b	d0,0(a0,d1.w)                   ; keep it
	rts                                     ; done
ikbd_header:
	move.b	d0,d1                           ; the header
	andi.w	#$f0,d1                         ; top four bits
	cmpi.b	#$f0,d1                         ; $F0-$FF?
	bne.s	ikbd_key                        ; no: a key
	cmpi.b	#$f3,d0                         ; $F0-$F3?
	bgt.s	ikbd_header_not_reply           ; no: a header
	btst	#$3,ikbd_packet_flags.w         ; waiting for the reset reply?
	beq.w	ikbd_key                        ; no: a key
	clr.b	ikbd_packet_flags.w             ; reply taken
	lsl.w	#8,d0                           ; $Fx00
	bra.w	keyboard_buffer_put             ; into the keyboard buffer
ikbd_header_not_reply:
	cmpi.b	#$fc,d0                         ; $FC clock?
	bne.s	ikbd_header_not_clock           ; no
	bset	#$1,ikbd_packet_flags.w         ; clock packet
	move.b	#$6,ikbd_bytes_left.w           ; 6 bytes
	rts                                     ; done
ikbd_header_not_clock:
	cmpi.b	#$fd,d0                         ; $FD joysticks?
	bne.s	ikbd_header_other               ; no
	bset	#$0,ikbd_packet_flags.w         ; joystick packet
	move.b	#$2,ikbd_bytes_left.w           ; 2 bytes
	rts                                     ; done
ikbd_header_other:
	move.b	#$2,ikbd_bytes_left.w           ; 2 bytes
	move.b	d0,ikbd_packet_header.w         ; keep the header
	rts                                     ; done
ikbd_key:
	moveq	#0,d1
	move.b	d0,d1                           ; d1 scan code
	cmpi.b	#$2a,d0                         ; left shift pressed?
	bne.s	ikbd_key_not_lshift             ; no
	bset	#$7,shift_held.w                ; shift held: shifted key map
ikbd_key_make:
	andi.w	#$ff,d0                         ; the scan code as a word
	bra.s	ikbd_key_translate              ; translate it
ikbd_key_not_lshift:
	cmpi.b	#$36,d0                         ; right shift pressed?
	bne.s	ikbd_key_not_rshift             ; no
	bset	#$7,shift_held.w                ; shift held: shifted key map
	bra.s	ikbd_key_make                   ; translate it
ikbd_key_not_rshift:
	cmpi.b	#$aa,d0                         ; left shift released?
	bne.s	ikbd_key_not_lshift_up          ; no
	bclr	#$7,shift_held.w                ; shift up: normal key map
ikbd_key_not_lshift_up:
	cmpi.b	#$b6,d0                         ; right shift released?
	bne.s	ikbd_key_release_check          ; no
	bclr	#$7,shift_held.w                ; shift up: normal key map
ikbd_key_release_check:
	btst	#$7,d0                          ; release?
	beq.s	ikbd_key_translate              ; no: a press
	move.b	d0,key_release.w                ; last key released
	movea.l	release_ring_write.w,a0         ; release ring write pointer
	move.b	d0,(a0)+                        ; into the ring
	cmpa.l	#$488,a0                        ; end of the ring?
	bne.s	ikbd_key_release_keep           ; no
	movea.l	#$480,a0                        ; wrap to the start
ikbd_key_release_keep:
	move.l	a0,release_ring_write.w         ; new write pointer
	rts                                     ; done
ikbd_key_translate:
	move.l	a0,-(sp)                        ; keep a0
	movea.l	#keyboard_ascii,a0              ; key maps
	add.b	shift_held.w,d0                 ; +$80 with shift held
	adda.w	d0,a0                           ; this key's entry
	move.b	(a0),d0                         ; ASCII
	asl.w	#8,d1                           ; scan code high
	add.w	d1,d0                           ; scan code and ASCII
	movea.l	(sp)+,a0                        ; a0 back
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
	rts                                     ; done
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
	rts                                     ; done

;------------------------------------------------------------------------------
; keyboard_ascii: scan code to ASCII, no shift (128 bytes). keyboard_ascii_shifted follows at +$80
; (the offset in $492). The third map at +$100 is never reached: $492 is only 0 or $80.
;------------------------------------------------------------------------------
keyboard_ascii:	; from: ikbd_receive_byte
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
; keyboard_ascii_arrows_as_digits: a third key map, the unshifted one with the cursor keys giving
; 8, 4, 6, 2. Not used.
;------------------------------------------------------------------------------
keyboard_ascii_arrows_as_digits:
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
; timer_a_count_handler: the Timer A handler of the start-up Timer A check: counts $20A down and
; clears the flag byte $284.
;------------------------------------------------------------------------------
timer_a_count_handler:	; from: startup_timing_checks
	tst.b	timer_a_count.w                 ; count left?
	beq.s	timer_a_count_clear             ; no
	subi.b	#$1,timer_a_count.w             ; count down
timer_a_count_clear:
	clr.b	timer_irq_flags.w               ; flag clear: the interrupt came
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	rte                                     ; done

;------------------------------------------------------------------------------
; timer_a_handler, timer_b_handler, timer_c_handler, timer_d_handler: the MFP timer interrupts. Each
; clears bit 1 of $284 if its in-service bit is set, clears that bit, and clears bit 0 of $284.
; timer_c_handler goes on into the Timer D check.
;------------------------------------------------------------------------------
timer_a_handler:	; from: timing_test, mfp_vectors_table
	btst	#$5,$fffffa0f.w                 ; MFP ISRA, Timer A in service?
	beq.s	timer_handler_done              ; no
	bclr	#$1,timer_irq_flags.w           ; bit 1 off: in service
	bclr	#$5,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	bra.s	timer_handler_done              ; done
timer_b_handler:	; from: timing_test, mfp_vectors_table
	btst	#$0,$fffffa0f.w                 ; MFP ISRA, Timer B in service?
	beq.s	timer_handler_done              ; no
	bclr	#$1,timer_irq_flags.w           ; bit 1 off: in service
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, end of interrupt
	bra.s	timer_handler_done              ; done
timer_c_handler:	; from: timing_test, mfp_vectors_table
	btst	#$5,$fffffa11.w                 ; MFP ISRB, Timer C in service?
	beq.s	timer_handler_done              ; no
	bclr	#$1,timer_irq_flags.w           ; bit 1 off: in service
	bclr	#$5,$fffffa11.w                 ; MFP ISRB, end of interrupt
timer_d_handler:	; from: timing_test, mfp_vectors_table
	btst	#$4,$fffffa11.w                 ; MFP ISRB, Timer D in service?
	beq.s	timer_handler_done              ; no
	bclr	#$1,timer_irq_flags.w           ; bit 1 off: in service
	bclr	#$4,$fffffa11.w                 ; MFP ISRB, end of interrupt
timer_handler_done:
	bclr	#$0,timer_irq_flags.w           ; bit 0 off: an interrupt came
	rte                                     ; done

;------------------------------------------------------------------------------
; blitter_done_handler: MFP GPIP3 (BLiTTER done): end of interrupt only.
;------------------------------------------------------------------------------
blitter_done_handler:	; from: mfp_vectors_table
	bclr	#$3,$fffffa11.w                 ; MFP ISRB, end of interrupt
	rte                                     ; done

;------------------------------------------------------------------------------
; cts_handler, dcd_handler, centronics_busy_handler: MFP GPIP2/1/0: clear bit 2/1/0 of $208.
;------------------------------------------------------------------------------
cts_handler:	; from: mfp_vectors_table
	bclr	#$2,interrupt_events.w          ; CTS seen
	bclr	#$2,$fffffa11.w                 ; MFP ISRB, end of interrupt
	rte                                     ; done
dcd_handler:	; from: mfp_vectors_table
	bclr	#$1,interrupt_events.w          ; DCD seen
	bclr	#$1,$fffffa11.w                 ; MFP ISRB, end of interrupt
	rte                                     ; done
centronics_busy_handler:	; from: mfp_vectors_table
	bclr	#$0,interrupt_events.w          ; BUSY seen
	bclr	#$0,$fffffa11.w                 ; MFP ISRB, end of interrupt
	rte                                     ; done

;------------------------------------------------------------------------------
; memory_utility: E: examine/modify memory. Commands: W start[,end]=data (bytes for 1-2 digits, else
; words, repeated up to end), R start[,end] bytes, RW start words, ? help, ESC back to the menu.
; $282 is $FF while a command runs, so a bus or address error goes back to the prompt. A key or an
; RS232 byte stops a long write or read. $4AA start, $4AE end. Changes most registers.
;------------------------------------------------------------------------------
memory_utility:	; from: read_command
	bsr.w	clear_screen                    ; clear the screen
	lea	memory_utility_text,a5          ; "Write/Read Memory Utility ..."
	bsr.w	print_string                    ; print it
memory_utility_prompt:	; from: bus_error_handler
	lea	msg_memory_prompt,a5            ; ">"
	bsr.w	print_string                    ; print it
	bsr.w	read_line                       ; read a line
	lea	line_buffer.w,a2                ; start of the line
	move.b	#$ff,memory_utility_active.w    ; exceptions back to the prompt
memory_utility_command:
	cmpa.l	a2,a4                           ; end of the line?
	beq.s	memory_utility_bad_command      ; yes: nothing valid found
	move.b	(a2)+,d0                        ; next character
	cmpi.b	#$1b,d0                         ; ESC: exit
	beq.s	memory_utility_exit             ; back to the menu
	cmpi.b	#$3f,d0                         ; "?"
	beq.w	memory_utility_help             ; help
	cmpi.b	#$57,d0                         ; "W"
	beq.s	memory_utility_write            ; write
	cmpi.b	#$52,d0                         ; "R"
	beq.w	memory_utility_read             ; read
	bne.s	memory_utility_command          ; skip other characters
memory_utility_bad_command:
	lea	msg_not_a_valid_command,a5      ; "Not a valid command: W,R,RW,?,<esc>"
memory_utility_error:
	bsr.w	print_newline                   ; new line
	bsr.w	print_string                    ; the error
	bra.s	memory_utility_prompt           ; prompt again
memory_utility_bad_address:
	lea	msg_invalid_address,a5          ; "Invalid address given."
	bra.s	memory_utility_error            ; print it
memory_utility_no_equals:
	lea	msg_no_equals_in_write,a5       ; "No "=" in write command"
	bra.s	memory_utility_error            ; print it
memory_utility_bad_data:
	lea	msg_invalid_write_data,a5       ; "Invalid data in write command"
	bra.s	memory_utility_error            ; print it
memory_utility_exit:
	clr.b	memory_utility_active.w         ; exceptions report again
	rts                                     ; back to the menu
memory_utility_write:
	bsr.w	parse_hex_address               ; first address
	bne.s	memory_utility_bad_address      ; none
	move.l	a0,memory_utility_start.w       ; start
	move.l	a0,memory_utility_end.w         ; end = start + 1
	addi.l	#$1,memory_utility_end.w        ; one word
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
	movea.l	memory_utility_start.w,a4       ; start
memory_utility_write_loop:
	cmpi.b	#$2,d3                          ; 2 digits or fewer?
	bgt.s	memory_utility_write_word       ; no
	move.b	d1,(a4)+                        ; write a byte
	bra.s	memory_utility_write_next       ; next
memory_utility_write_word:
	move.w	d1,(a4)+                        ; write a word
memory_utility_write_next:
	bsr.w	key_waiting                     ; key waiting?
	tst.w	d0                              ; key?
	bne.w	memory_utility_prompt           ; stop
	bsr.w	rs232_byte_waiting              ; RS232 byte?
	tst.w	d0                              ; RS232 byte?
	bne.w	memory_utility_prompt           ; stop
	cmpa.l	memory_utility_end.w,a4         ; past the end?
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
	bra.s	memory_utility_read_start       ; read it
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
	move.l	a4,d1                           ; the address
	tst.b	d1                              ; at a 256-byte boundary?
	bne.s	memory_utility_read_byte_or_word ; no
	bsr.w	print_newline                   ; new line
	movea.l	a4,a0                           ; print the address
	bsr.w	print_hex_address               ; the address
	bsr.w	print_newline                   ; new line
memory_utility_read_byte_or_word:
	cmpi.b	#$57,d3                         ; words?
	bne.s	memory_utility_read_byte        ; no
	move.w	(a4)+,d1                        ; read a word
	bsr.w	print_hex_word                  ; print it
	bra.s	memory_utility_read_space       ; then a space
memory_utility_read_byte:
	move.b	(a4)+,d1                        ; read a byte
	bsr.w	print_hex_byte                  ; print it
memory_utility_read_space:
	bsr.w	print_space                     ; space
	cmpa.l	memory_utility_end.w,a4         ; past the end?
	bgt.s	memory_utility_read_done        ; yes: done
	dbra	d0,memory_utility_read_value    ; next value
	bsr.w	key_waiting                     ; key waiting?
	tst.w	d0                              ; key?
	bne.s	memory_utility_read_paused      ; yes: pause
	bsr.w	rs232_byte_waiting              ; RS232 byte?
	tst.w	d0                              ; RS232 byte?
	bne.s	memory_utility_read_paused      ; yes: pause
	bra.s	memory_utility_read_line        ; next line
memory_utility_read_done:
	bsr.w	print_newline                   ; new line
	bra.w	memory_utility_prompt           ; prompt again
memory_utility_read_paused:
	movea.l	a4,a0
	suba.l	#$1,a0                          ; the last address read
	bsr.w	print_hex_address               ; print where it stopped
	bsr.w	get_key                         ; the key
	cmpi.b	#$1b,d0                         ; ESC: prompt
	beq.w	memory_utility_prompt           ; ESC: prompt
	bsr.w	get_key                         ; wait for another key
	bra.s	memory_utility_read_line        ; go on
memory_utility_help:
	bsr.w	clear_screen                    ; clear the screen
	lea	memory_utility_help_text,a5     ; "Commands are: W-write memory, R-read byte, RW-read word. ..."
	bsr.w	print_string                    ; print it
	bra.w	memory_utility_prompt           ; prompt again

;------------------------------------------------------------------------------
; read_line: reads a line into $237-$256 (echoed) from the keyboard or RS232 terminal; ESC is kept
; and ends the line at once. Backspace edits; RET ends it (from the keyboard after the Return or
; keypad Enter release); a full line gives "Keyboard buffer full" and d0 = 0.
; Out: d0 = 0 nothing read, else a4 points past the end of the line. Changes d1, a4.
;------------------------------------------------------------------------------
read_line:	; from: memory_utility
	lea	line_buffer.w,a4                ; the line buffer
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
	rts                                     ; done
read_line_not_esc:
	cmpi.b	#$8,d0                          ; backspace?
	bne.s	read_line_not_backspace         ; no
	cmpa.l	#$237,a4                        ; line empty?
	beq.s	read_line_key                   ; yes: ignore
	bsr.w	put_backspace                   ; back one on the screen
	clr.b	-(a4)                           ; and in the line
	bra.s	read_line_key                   ; next key
read_line_not_backspace:
	cmpi.b	#$d,d0                          ; RET?
	beq.s	read_line_return                ; yes
	move.b	d0,(a4)+                        ; into the line
	move.b	d0,d1                           ; print it
	bsr.w	put_char                        ; echo it
	cmpa.l	#$256,a4                        ; line full?
	ble.s	read_line_key                   ; no: next key
	lea	msg_keyboard_buffer_full,a5     ; "Keyboard buffer full"
	bsr.w	print_string                    ; print it
read_line_empty:
	moveq	#0,d0                           ; nothing
	rts                                     ; done
read_line_return:
	cmpa.l	#$237,a4                        ; line empty?
	beq.s	read_line_empty                 ; yes: nothing
	tst.b	d1                              ; RET from RS232: done
	beq.s	read_line_done                  ; yes
	cmpi.b	#$9c,key_release.w              ; Return released?
	beq.s	read_line_done                  ; yes
	cmpi.b	#$f2,key_release.w              ; keypad Enter released?
	bne.s	read_line_return                ; wait
read_line_done:
	rts                                     ; done

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
	or.l	d0,d1                           ; add the digit
	addq.w	#1,d2                           ; add the digit
	bra.s	parse_hex_address_next          ; one more digit
parse_hex_address_end:
	tst.l	d2                              ; any digits?
	beq.s	parse_hex_address_none          ; no
	movea.l	d1,a0                           ; the address
	moveq	#0,d7                           ; found
	rts                                     ; done
parse_hex_address_none:
	moveq	#-1,d7                          ; not found
	rts                                     ; done

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
	or.b	d0,d1                           ; add the digit
	addq.w	#1,d3                           ; one more digit
	bra.s	parse_hex_data_next             ; next
parse_hex_data_end:
	tst.b	d3                              ; any digits?
	bne.s	parse_hex_data_done             ; yes
	moveq	#-1,d7                          ; none
	rts                                     ; done
parse_hex_data_done:
	moveq	#0,d7                           ; found
	rts                                     ; done

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
	rts                                     ; done
hex_digit_value_letter:
	cmpi.b	#$41,d0                         ; below 'A'?
	blt.s	hex_digit_value_bad             ; no digit
	cmpi.b	#$46,d0                         ; above 'F'?
	bgt.s	hex_digit_value_bad             ; no digit
	dc.w	$0200,$ff0f                     ; andi.b	#$f,d0, 'A'-'F' give 1-6
	addi.b	#$1,d0                          ; 2-7
	ori.b	#$8,d0                          ; $A-$F
	moveq	#0,d7                           ; a digit
	rts                                     ; done
hex_digit_value_bad:
	moveq	#-1,d7                          ; no hex digit
	rts

;------------------------------------------------------------------------------
; ram_test: the R test.  Tests all the RAM in five steps, keeping the cartridge's variables and the
; screen out of the way of the step running:
;  1 a 256-byte area at $500-$FFF that holds is found for the error list (none: R0 and Fail)
;  2 $10-$3FF is copied to the first of $1000, $1400, $1800, $1C00 where the copy verifies; $10 up to
;    1K below the error list's top is tested and the copy put back (no good copy: step 2 left out)
;  3 the screen ($10000) is copied to $20000 and shown there; RAM from the error list's top to $20000
;    is tested with the stack at $500
;  4 the screen goes back to $10000; $20000 to the top of RAM is tested, a blinking '*' after
;    "Testing Ram" showing it runs
;  5 the last 256 bytes of each 64K are marked with the 64K's number and checked (address lines)
; With $28D bit 7 set, a key waiting after step 3 leaves out steps 4 and 5.  Errors are kept in a
; list (record_ram_error) and printed after each step (print_ram_errors); at the end the memory size
; and Pass, or Fail, are printed.  Steps 1 and 2 run with no interrupts and the keyboard masked.  The
; stack moves, so the return address is kept in d5.
;  In:  $204 the top of RAM.  Out: $49A bit 0 set on an error.
;  Changes every register, $49A, $49C.l (the stack kept in step 3), $4B2, $4B4, $21A, the screen
;  address and the VBL vector (left at the routine that clears $292).
;------------------------------------------------------------------------------
ram_test:	; from: test_routines
	move.l	(sp)+,d5                        ; the return address, kept while the stack moves
	move.l	ram_top.w,d6                    ; the top of RAM
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
	bge.w	ram_test_no_safe_block          ; none by $1000: R0 and Fail
	bra.s	ram_test_find_safe_block        ; try that area
ram_test_safe_block_next_word:
	subq.w	#2,d2                           ; the next word down
	bne.s	ram_test_safe_block_word        ; to offset 2
	movea.l	a6,a4                           ; the good area
	adda.l	#$100,a6                        ; a6: the error list's top (it grows down)
	adda.l	#$38,a4                         ; a4: its bottom, room for 20 errors
	movea.l	#$10,a0                         ; copy $10-$3FF
	movea.l	#$1000,a1                       ; to the first of $1000, $1400, $1800, $1C00 that verifies
	clr.l	d0                              ; d0 the word count
	ori.w	#$1f8,d0                        ; $1F8 words
ram_test_save_low_memory:
	bsr.w	copy_and_verify                 ; copy $10-$3FF and check the copy
	beq.s	ram_test_low_memory             ; the copy holds
	adda.l	#$400,a1                        ; else try the next 1K
	cmpa.l	#$2000,a1                       ; up to $2000
	bne.s	ram_test_save_low_memory        ; not yet: the next 1K
	bra.s	ram_test_below_screen           ; (the IPL stays 7 and the keyboard masked)
ram_test_low_memory:
	movea.l	a1,a5                           ; the copy's address
	movea.l	#$10,a0                         ; test from $10
	movea.l	a6,a1                           ; up to the error list less 1K
	suba.l	#$400,a1                        ; its top: 1K below the list's top
	bsr.w	test_ram_range                  ; test $10 up to there
	movea.l	a5,a0                           ; copy the saved low memory
	movea.l	#$10,a1                         ; back to $10
	clr.l	d0                              ; d0 the word count
	move.w	#$1f8,d0                        ; $1F8 words
	bsr.w	copy_and_verify                 ; copied back and checked
	bsr.w	print_ram_errors                ; step 2's errors printed
	bset	#$6,$fffffa15.w                 ; MFP IMRB, unmask the keyboard/MIDI interrupt
	move.w	#$2400,sr                       ; IPL 4
ram_test_below_screen:
	movea.l	#$10000,a0                      ; copy the screen at $10000
	movea.l	#$20000,a1                      ; to $20000
	move.l	#$4000,d0                       ; 32K
	bsr.w	copy_words                      ; copied
	move.b	#$2,$ffff8201.w                 ; video base high, and show it there
	move.l	sp,test_errors_extra.w          ; the stack kept
	movea.l	#$500,sp                        ; the stack below the error list area
	movea.l	a6,a0                           ; test from the error list
	movea.l	#$20000,a1                      ; up to $20000
	bsr.w	test_ram_range                  ; tested
	movea.l	test_errors_extra.w,sp          ; the stack back
	movea.l	#$20000,a0                      ; copy the screen back
	movea.l	#$10000,a1                      ; to $10000
	move.l	#$4000,d0                       ; 32K
	bsr.w	copy_words                      ; copied
	move.b	#$1,$ffff8201.w                 ; video base high, and show it there
	bsr.w	print_ram_errors                ; step 3's errors printed
	btst	#$7,mode_flags.w                ; $28D bit 7 set?
	beq.s	ram_test_above_screen           ; no: steps 4 and 5
	bsr.w	key_waiting                     ; a key waiting?
	tst.b	d0                              ; (d0 = 0: none)
	bne.w	ram_test_report                 ; yes: steps 4 and 5 left out
ram_test_above_screen:
	lea	ram_test_star_vbl,a0            ; the VBL routine that blinks the '*'
	move.l	a0,$70.w                        ; VBL vector
	move.w	#$1e,star_countdown.w           ; the '*' blinks every 30 VBLs ($4B2)
	clr.b	star_inverse.w                  ; the '*' shown plain first ($4B4)
	move.w	#$2200,sr                       ; IPL 2: VBLs on
	movea.l	#$20000,a0                      ; test from $20000
	movea.l	ram_top.w,a1                    ; to the top of RAM
	bsr.w	test_ram_range                  ; tested
	move.w	#$2400,sr                       ; IPL 4
	move.w	#$4,d7                          ; errors are R4
	movea.l	#$ff00,a0                       ; the last 256 bytes of the first 64K
	moveq	#0,d0                           ; the 64K's number
	moveq	#0,d1                           ; (d1 the address's low word)
ram_test_bank_mark_write:
	move.w	d0,(a0)+                        ; mark a word with the 64K's number
	move.w	a0,d1                           ; the low word of the address
	cmpi.w	#$0,d1                          ; to the end of this 64K
	bne.s	ram_test_bank_mark_write        ; not yet: the next word
	addq.w	#1,d0                           ; the next 64K's number
	adda.l	#$ff00,a0                       ; its last 256 bytes
	cmpa.l	ram_top.w,a0                    ; to the top of RAM
	ble.s	ram_test_bank_mark_write        ; not yet: the next 64K
	movea.l	#$ff00,a0                       ; check them, from the first 64K
	moveq	#0,d0                           ; the first 64K's number
ram_test_bank_mark_check:
	cmp.w	(a0)+,d0                        ; still the 64K's number?
	beq.s	ram_test_bank_mark_next         ; yes
	suba.l	#$2,a0                          ; back to the bad word
	move.w	(a0),d1                         ; what was read
	bsr.w	record_ram_error                ; record it (d0 written, d1 read)
	adda.l	#$2,a0                          ; on past it
ram_test_bank_mark_next:
	move.w	a0,d1                           ; the low word of the address
	cmpi.w	#$0,d1                          ; to the end of this 64K
	bne.s	ram_test_bank_mark_check        ; not yet: the next word
	addq.w	#1,d0                           ; the next 64K's number
	adda.l	#$ff00,a0                       ; its last 256 bytes
	cmpa.l	ram_top.w,a0                    ; to the top of RAM
	ble.s	ram_test_bank_mark_check        ; not yet: the next 64K
ram_test_report:
	bsr.w	print_ram_errors                ; the last errors printed
	tst.b	test_errors.w                   ; any error?
	beq.s	ram_test_show_size              ; no
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bra.s	ram_test_show_result            ; print it
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
	bsr.w	show_status_at                  ; "256k RAM" to "4M RAM" at column 40
	movea.l	#msg_pass,a5                    ; "Pass"
ram_test_show_result:	; from: ram_test_no_safe_block
	bsr.w	show_result                     ; "Pass", or "Fail at cycle:" and the cycle
	move.l	d5,-(sp)                        ; the return address back
	rts                                     ; back to the menu

;------------------------------------------------------------------------------
; ram_test_no_safe_block: no 256 bytes at $500-$FFF hold: R0 is printed with the address $1000,
; then Fail.
;------------------------------------------------------------------------------
ram_test_no_safe_block:	; from: ram_test
	movea.l	a6,a0                           ; the last area tried
	movem.l	d0-d1/a0,-(sp)                  ; (pushed and popped again: does nothing)
	movem.l	(sp)+,d0-d1/a0                  ; (d0, d1 and a0 kept)
	moveq	#0,d7                           ; printed as R0
	bsr.w	print_ram_error                 ; print it
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bra.s	ram_test_show_result            ; shown

;------------------------------------------------------------------------------
; test_ram_range: runs the RAM tests on a0-a1: the $AAAA/$5555 patterns (R1), each word holding its
; own address and then its address byte-swapped (R2), and the 32K block test (R3), each only while the
; error list has room.
;  In:  a0 start, a1 end, a6/a4 the error list's top and bottom
;  Out: errors added to the error list; a0 kept.  Leaves the VBL vector at the routine that only
;       clears $292 and the IPL at 4.
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
	move.l	#vbl_handler,$70.w              ; VBL vector, the routine that only clears $292
	bsr.w	test_32k_blocks                 ; the 32K block test
test_ram_range_done:
	movea.l	(sp)+,a0                        ; the start back
	rts

;------------------------------------------------------------------------------
; test_alternating_patterns: fills a0-a1 with $AAAA,$5555,... and checks it, then with $5555,$AAAA,...
;  In:  a0 start, a1 end.  Out: errors recorded as R1.  Changes d0-d2, a2, d7, the upper word of d0.
;------------------------------------------------------------------------------
test_alternating_patterns:	; from: test_ram_range
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
	bne.s	test_pattern_pair_fill          ; not yet: the next pair
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
	bne.s	test_pattern_pair_check         ; not yet: the next pair
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
	bgt.s	test_address_fill               ; not yet
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
	bgt.s	test_address_check              ; not yet
	movea.l	a2,a0                           ; now byte-swapped
test_swapped_address_fill:
	move.w	a0,d0                           ; the address
	rol.w	#8,d0                           ; the address with its bytes swapped
	move.w	d0,(a0)+                        ; written
	cmpa.l	a0,a1                           ; to the end
	bgt.s	test_swapped_address_fill       ; not yet
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
	bgt.s	test_swapped_address_check      ; not yet
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
	adda.l	#$8000,a1                       ; 32K on
	move.w	#$2200,sr                       ; IPL 2: VBLs on
	move.b	$ffff8201.w,d0                  ; video base high, keep the screen address
	lsl.w	#8,d0                           ; (high byte into bits 8-15)
	move.b	$ffff8203.w,d0                  ; video base mid
	move.l	d0,scratch_long.w               ; kept in $21A
test_32k_blocks_next:
	move.l	a0,d0                           ; show this block
	bsr.w	show_32k_block                  ; show it
	bsr.w	fill_32k_block                  ; fill it
	bsr.w	check_32k_block                 ; and check it
	tst.l	d7                              ; bad block?
	bmi.s	test_32k_blocks_end             ; yes: stop
	adda.l	#$8000,a0                       ; the next 32K
	adda.l	#$8000,a1                       ; and its end
	cmpa.l	d4,a1                           ; while it ends within the range
	ble.s	test_32k_blocks_next            ; (ble: a block ending at the range's end is tested too)
test_32k_blocks_end:
	move.l	scratch_long.w,d0               ; the screen address back
	move.b	d0,$ffff8203.w                  ; video base mid
	lsr.l	#8,d0                           ; (the high byte)
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
	bgt.s	fill_32k_block_loop             ; not yet
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
	bne.s	check_32k_block_lower           ; not yet
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
	bne.s	check_32k_block_upper           ; not yet
check_32k_block_done:
	movea.l	a2,a0                           ; the start back
	movea.l	a3,a1                           ; and the end
	rts
check_32k_block_lower_error:
	suba.l	#$2,a0                          ; back to the bad word
	bsr.w	record_ram_error                ; record it
	adda.l	#$2,a0                          ; (a0 back on)
	bra.s	check_32k_block_stop            ; the block is bad
check_32k_block_upper_error:
	adda.l	#$2,a0                          ; one word past the bad one
	bsr.w	record_ram_error                ; record it
	suba.l	#$2,a0                          ; (a0 back on)
check_32k_block_stop:
	bset	#$1f,d7                         ; mark the block bad
	bra.s	check_32k_block_done            ; (a0/a1 back)

;------------------------------------------------------------------------------
; show_32k_block: waits for a VBL, then makes the screen start at d0 (a 256-byte boundary).
;  In:  d0.l the address.  Changes d0; leaves the IPL at 4.
;------------------------------------------------------------------------------
show_32k_block:	; from: test_32k_blocks
	move.w	#$2200,sr                       ; IPL 2: VBLs on
	move.b	#$1,vbl_flag.w                  ; $292 set: the VBL clears it
show_32k_block_wait_vbl:
	tst.b	vbl_flag.w                      ; the VBL yet?
	bne.s	show_32k_block_wait_vbl         ; not yet
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
	movem.l	(sp)+,d0/a0-a1                  ; the count and addresses back
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
	bset	#$0,test_errors.w               ; $49A bit 0: a RAM error
	move.w	#$500,$ffff8240.w               ; palette 0, red background
record_ram_error_full:
	rts

;------------------------------------------------------------------------------
; print_ram_errors: prints and takes off every error in the error list, newest first.
;  In:  a6/a4 the list.  Out: the list empty.  Changes d0, d1, d7, a0.
;------------------------------------------------------------------------------
print_ram_errors:	; from: bus_error_caught, ram_test
	move.l	a4,d0                           ; the list's top: a4 + 200
	add.w	#$c8,d0                         ; (a full list holds 20)
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
; print_ram_error: prints one RAM error: "Rn RAM address=" (code 0-3 R0-R3, 4 and up R4), the
; address, " W:" the value written, " R:" the value read, then the numbers of the bad bits.
;  In:  d7 the code, a0 the address, d0 written, d1 read.  Changes d7.
;------------------------------------------------------------------------------
print_ram_error:	; from: ram_test_no_safe_block, copy_and_verify, print_ram_errors
	movem.l	d0-d1/a0,-(sp)                  ; keep the value read, written and the address
	move.l	a6,-(sp)                        ; keep the error list's top
	cmpi.w	#$0,d7                          ; code 0?
	bne.s	print_ram_error_pattern         ; no
	movea.l	#msg_r0_ram_address,a5          ; "R0 RAM address="
	bra.s	print_ram_error_print           ; printed
print_ram_error_pattern:
	cmpi.w	#$1,d7                          ; code 1?
	bne.s	print_ram_error_address         ; no
	movea.l	#msg_r1_ram_address,a5          ; "R1 RAM address="
	bra.s	print_ram_error_print           ; printed
print_ram_error_address:
	cmpi.w	#$2,d7                          ; code 2?
	bne.s	print_ram_error_block           ; no
	movea.l	#msg_r2_ram_address,a5          ; "R2 RAM address="
	bra.s	print_ram_error_print           ; printed
print_ram_error_block:
	cmpi.w	#$3,d7                          ; code 3?
	bne.s	print_ram_error_r4_text         ; no: R4
	movea.l	#msg_r3_ram_address,a5          ; "R3 RAM address="
	bra.s	print_ram_error_print           ; printed
print_ram_error_r4_text:
	movea.l	#msg_r4_ram_address,a5          ; "R4 RAM address=" (code 4: the 64K marks)
print_ram_error_print:
	bsr.w	print_string                    ; the "Rn RAM address=" text
	move.w	d0,d7                           ; the bad bits
	eor.w	d1,d7                           ; (the bits that differ)
	move.w	d1,-(sp)                        ; keep read
	move.w	d0,-(sp)                        ; keep written
	bsr.w	print_hex_address               ; the address
	bsr.w	print_space                     ; a space
	lea	msg_written_data,a5             ; " W:"
	bsr.w	print_string                    ; printed
	move.w	(sp)+,d1                        ; written
	bsr.w	print_hex_word                  ; in hex
	bsr.w	print_space                     ; a space
	lea	msg_read_data,a5                ; " R:"
	bsr.w	print_string                    ; printed
	move.w	(sp)+,d1                        ; read
	bsr.w	print_hex_word                  ; in hex
	bsr.w	print_bad_bits                  ; and the bad bits
	movea.l	(sp)+,a6                        ; the error list's top back
	movem.l	(sp)+,d0-d1/a0                  ; the registers back
	rts

;------------------------------------------------------------------------------
; print_bad_bits: prints "  bad bits: " and the number (0-15) of every bit set in d7, then a new line.
;  In:  d7 the bits.  Changes d1.
;------------------------------------------------------------------------------
print_bad_bits:	; from: print_ram_error
	lea	msg_bad_bits,a5                 ; "  bad bits: "
	bsr.w	print_string                    ; printed
	moveq	#0,d1                           ; from bit 0
print_bad_bits_loop:
	btst	d1,d7                           ; bad?
	beq.s	print_bad_bits_next             ; no
	move.w	d1,-(sp)                        ; keep the bit number
	bsr.w	print_decimal_teen              ; in decimal
	bsr.w	print_space                     ; a space
	move.w	(sp)+,d1                        ; the bit number back
print_bad_bits_next:
	addq.w	#1,d1                           ; the next bit
	cmpi.w	#$10,d1                         ; to bit 15
	bne.s	print_bad_bits_loop             ; not yet
	bsr.w	print_newline                   ; the line ended
	rts

;------------------------------------------------------------------------------
; ram_test_star_vbl: ram_test's VBL routine for step 4: every 30 VBLs prints the '*' at column 13 of
; the status line, plain and inverse in turn ($4B4), so the screen shows the test running.
; Registers kept.
;------------------------------------------------------------------------------
ram_test_star_vbl:	; from: ram_test
	subi.w	#$1,star_countdown.w            ; one VBL less ($4B2)
	bne.s	ram_test_vbl_exit               ; not the 30th: out
	move.w	#$1e,star_countdown.w           ; 30 VBLs again
	movem.l	d0-d7/a0-a6,-(sp)               ; registers kept
	bsr.w	inverse_on                      ; inverse text
	eori.w	#$ff,star_inverse.w             ; $4B4 flipped
	bne.s	ram_test_vbl_star               ; now $FF: inverse this time
	bsr.w	inverse_off                     ; now 0: plain text
ram_test_vbl_star:
	lea	msg_ram_test_star,a5            ; "*"
	move.w	#$d,d0                          ; column 13
	move.w	#$0,d1                          ; of the status line
	bsr.w	show_status_at                  ; printed
	bsr.w	inverse_off                     ; inverse off
	movem.l	(sp)+,d0-d7/a0-a6               ; registers back
ram_test_vbl_exit:
	rte

;------------------------------------------------------------------------------
; rom_test: the O test.  Prints the TOS version, country and PAL/NTSC (print_tos_version), then for
; each ROM chip, the "High ROM" (the even bytes of the 256K at $E00000) and the "Low ROM" (the odd
; bytes), its byte sum and its CRC-16 (CCITT).  Each is compared with a table of the values expected
; for the ROM's country: one set of tables for TOS 1.62, another for any other version.  A mismatch
; sets a bit (check_rom_sums) and gives Fail; with TOS 1.62 or older "  cs error  " or "  crc error "
; is printed after the value, with a newer TOS only the values.
;  Out: $49A the High ROM's mismatch bits, $49B the Low ROM's (bit 0 sum, bit 1 CRC).
;  Changes d0-d6, a0-a2, a5, $49A, $49B, $4BA, $4C0, $4C6, $4CC, $4D0.
; The code from $1E28 on is shown as data: the long at $1E2A (part of a bsr.w and a move.b) was taken
; for an address.  It is: bsr.w check_rom_sums / move.b d6,$49A.w / lea "Low ROM checksum, crc",a5 /
; bsr.w print_string / the same table choice for the Low ROM / move.w $4C0.w,d1 / move.w $4CC.w,d2 /
; bsr.w check_rom_sums / move.b d6,$49B.w / Pass if $49A and $49B are both 0, else Fail with the
; background red / bsr.w show_result / rts.
;------------------------------------------------------------------------------
rom_test:	; from: test_routines
	lea	msg_rom_checksum_test,a5        ; "ROM checksum/crc test"
	bsr.w	show_status                     ; on the status line
	clr.b	test_errors.w                   ; no mismatches yet
	clr.b	test_errors_high.w              ; (the Low ROM's)
	bsr.w	print_tos_version               ; the version, country and PAL/NTSC
	movea.l	#$e00000,a0                     ; the ROM
	move.l	#$20000,d4                      ; $20000 byte pairs
	bsr.w	rom_checksums                   ; summed
	move.w	d1,rom_sum_high.w               ; the High ROM's sum ($4BA)
	move.w	d2,rom_sum_low.w                ; the Low ROM's sum ($4C0)
	lea	$e00000,a0                      ; the High ROM's bytes, from $E00000
	move.l	#$20000,d2                      ; $20000 of them
	bsr.w	rom_crc                         ; its CRC
	move.w	d0,rom_crc_high.w               ; kept ($4C6)
	adda.l	#$1,a0                          ; the Low ROM's bytes, from $E00001
	move.l	#$20000,d2                      ; $20000 of them
	bsr.w	rom_crc                         ; its CRC
	move.w	d0,rom_crc_low.w                ; kept ($4CC)
	clr.b	rom_mismatch_texts.w            ; $4D0: mismatches printed only for TOS 1.62 and older
	move.w	$e00002,d0                      ; the TOS version
	cmp.w	#$162,d0                        ; 1.62?
	bgt.w	rom_test_high_rom               ; newer: no mismatch texts
	move.b	#$1,rom_mismatch_texts.w        ; 1.62 or older: mismatch texts printed
rom_test_high_rom:
	lea	msg_high_rom_checksum,a5        ; "High ROM checksum, crc"
	bsr.w	print_string                    ; printed
	cmpi.w	#$162,$e00002                   ; TOS 1.62?
	beq.w	rom_test_high_tables_162        ; yes: its tables
	lea	tos106_high_rom_checksums,a0    ; the High ROM sums by country, other versions
	lea	tos106_high_rom_crcs,a1         ; the High ROM CRCs by country, other versions
	bra.s	rom_test_check_high             ; checked
rom_test_high_tables_162:
	lea	tos162_high_rom_checksums,a0    ; the High ROM sums by country, TOS 1.62
	lea	tos162_high_rom_crcs,a1         ; the High ROM CRCs by country, TOS 1.62
rom_test_check_high:
	move.w	rom_sum_high.w,d1               ; the High ROM's sum
	move.w	rom_crc_high.w,d2               ; and CRC
	bsr.w	check_rom_sums                  ; bsr.w check_rom_sums: printed and compared, printed and compared
	move.b	d6,test_errors.w                ; the High ROM's errors
	lea	msg_low_rom_checksum,a5         ; "Low ROM checksum"
	bsr.w	print_string                    ; printed
	cmpi.w	#$162,$e00002                   ; TOS 1.62?
	beq.w	rom_test_tables_162             ; yes: its tables
	lea	tos106_low_rom_checksums,a0     ; any other TOS: the 1.06 tables
	lea	tos106_low_rom_crcs,a1
	bra.s	rom_test_check_low
rom_test_tables_162:
	lea	tos162_low_rom_checksums,a0     ; the TOS 1.62 tables
	lea	tos162_low_rom_crcs,a1
rom_test_check_low:
	move.w	rom_sum_low.w,d1                ; the Low ROM's sum
	move.w	rom_crc_low.w,d2                ; and CRC
	bsr.w	check_rom_sums                  ; printed and compared
	move.b	d6,test_errors_high.w           ; the Low ROM's errors
	tst.b	test_errors.w                   ; any High ROM error?
	bne.s	rom_test_fail                   ; yes: fail
	tst.b	test_errors_high.w              ; any Low ROM error?
	bne.s	rom_test_fail                   ; yes: fail
	lea	msg_pass,a5                     ; "Pass"
	bra.s	rom_test_result
rom_test_fail:
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
	move.w	#$500,$ffff8240.w               ; palette 0, red
rom_test_result:
	bsr.w	show_result                     ; on the status line
	rts

;------------------------------------------------------------------------------
; print_tos_version: prints "Version " and the TOS version (as "1.62"), and for a version above 1.62
; "New version number" (and colour 0 turned $551), then the country name from the ROM's os_conf and
; "PAL" or "NTSC".  Changes d0-d2, a0, a5.
;------------------------------------------------------------------------------
print_tos_version:	; from: menu_start, rom_test
	lea	msg_version,a5                  ; "Calculated ROM checksums"
	bsr.w	print_string                    ; printed
	move.w	$e00002,d1                      ; the TOS version
	move.w	d1,d2                           ; kept
	lsr.w	#8,d1                           ; major
	bsr.w	print_hex_digit                 ; printed
	move.w	#$2e,d1                         ; '.'
	bsr.w	put_char                        ; printed
	move.w	d2,d1                           ; the version again
	lsr.w	#4,d1                           ; minor, first digit
	bsr.w	print_hex_digit                 ; printed
	move.w	d2,d1                           ; the version again
	bsr.w	print_hex_digit                 ; minor, second digit
	bsr.w	print_space                     ; a space
	clr.l	d0                              ; (the high word clear)
	move.w	$e00002,d0                      ; the version again
	cmpi.w	#$162,d0                        ; above 1.62?
	ble.w	print_tos_country               ; no
	lea	msg_new_version_number,a5       ; "New version number"
	bsr.w	print_string                    ; printed
	move.w	#$551,$ffff8240.w               ; palette 0, colour 0 $551
print_tos_country:
	move.w	$e0001c,d0                      ; os_conf
	andi.w	#$1e,d0                         ; the country code times 2
	lsl.w	#1,d0                           ; times 4: a long index
	lea	country_names,a0                ; the country names, "USA " first
	movea.l	0(a0,d0.w),a5                   ; the country's name
	bsr.w	print_string                    ; printed
	btst	#$0,$e0001d                     ; PAL?
	beq.w	print_tos_version_ntsc          ; no
	lea	msg_pal,a5                      ; "PAL"
	bra.w	print_tos_standard              ; printed
print_tos_version_ntsc:
	lea	msg_ntsc,a5                     ; "NTSC"
print_tos_standard:
	bsr.w	print_string                    ; "PAL" or "NTSC" printed
	rts

;------------------------------------------------------------------------------
; check_rom_sums: prints a ROM chip's byte sum and CRC and compares them with the values expected for
; the ROM's country (os_conf bits 1-4).  After each value "  cs error  " or "  crc error " is printed
; on a mismatch when $4D0 is set, else 12 spaces; then a new line.  Only reached from the part of
; rom_test shown as data.
;  In:  d1 the sum, d2 the CRC, a0 the sums table, a1 the CRCs table (a word for each country).
;  Out: d6 bit 0 set on a sum mismatch, bit 1 on a CRC mismatch.  Changes d0, d1, d3, a5.
;------------------------------------------------------------------------------
check_rom_sums:	; from: rom_test
	clr.w	d6                              ; no mismatch yet
	move.l	d1,-(sp)                        ; keep the sum
	bsr.w	print_hex_word                  ; printed
	move.w	$e0001c,d0                      ; the ROM's country
	andi.w	#$1e,d0                         ; times 2: a word index
	move.w	0(a0,d0.w),d3                   ; the sum expected
	lea	msg_rom_value_ok,a5             ; 12 spaces
	move.l	(sp)+,d1                        ; the sum back
	cmp.w	d3,d1                           ; as expected?
	beq.s	check_rom_sums_crc              ; yes
	bset	#$0,d6                          ; a sum mismatch
	tst.b	rom_mismatch_texts.w            ; mismatch texts printed?
	beq.s	check_rom_sums_crc              ; no: the spaces
	lea	msg_rom_cs_error,a5             ; "  cs error  "
check_rom_sums_crc:
	bsr.w	print_string                    ; the spaces or the error
	move.w	d2,d1                           ; the CRC
	bsr.w	print_hex_word                  ; printed
	move.w	0(a1,d0.w),d3                   ; the CRC expected
	lea	msg_rom_value_ok,a5             ; 12 spaces
	cmp.w	d3,d2                           ; as expected?
	beq.s	check_rom_sums_done             ; yes
	bset	#$1,d6                          ; a CRC mismatch
	tst.b	rom_mismatch_texts.w            ; mismatch texts printed?
	beq.s	check_rom_sums_done             ; no: the spaces
	lea	msg_rom_crc_error,a5            ; "  crc error "
check_rom_sums_done:
	bsr.w	print_string                    ; the spaces or the error
	bsr.w	print_newline                   ; the line ended
	rts

;------------------------------------------------------------------------------
; rom_checksums: sums the even and the odd bytes from a0, d4 pairs.
;  Out: d1 the even bytes' sum (u206), d2 the odd bytes' sum (u207); a0 past the end; d0, d4 changed.
;------------------------------------------------------------------------------
rom_checksums:	; from: rom_test
	moveq	#0,d1                           ; even sum
	moveq	#0,d0                           ; (the high byte clear)
	moveq	#0,d2                           ; odd sum
rom_checksums_loop:
	move.b	(a0)+,d0                        ; even byte
	add.w	d0,d1                           ; into the even sum
	move.b	(a0)+,d0                        ; odd byte
	add.w	d0,d2                           ; into the odd sum
	subi.l	#$1,d4                          ; the next pair
	bne.s	rom_checksums_loop              ; not yet
	rts

;------------------------------------------------------------------------------
; rom_crc: the CRC-16 (CCITT, polynomial $1021, from 0, high bit first) of every other byte from a0.
;  In:  a0 the first byte, d2.l the bytes.  Out: d0 the CRC; a0 kept; d1-d4, a2 changed.
;------------------------------------------------------------------------------
rom_crc:	; from: rom_test
	move.l	a0,-(sp)                        ; keep the start
	clr.w	d0                              ; the CRC from 0
	clr.w	d1                              ; (the high byte clear)
	clr.w	d3                              ; (the high byte clear)
	lea	crc16_table,a2                  ; the CRC table
rom_crc_loop:
	move.w	d0,d1                           ; the CRC
	lsl.w	#8,d0                           ; CRC shifted 8 left
	lsr.w	#8,d1                           ; its high byte
	move.b	(a0)+,d3                        ; the byte
	adda.l	#$1,a0                          ; skip the other chip's byte
	eor.b	d3,d1                           ; the table index
	lsl.w	#1,d1                           ; a word index
	move.w	0(a2,d1.w),d4                   ; the table entry
	eor.w	d4,d0                           ; into the CRC
	sub.w	#$1,d2                          ; one byte less
	bne.s	rom_crc_loop                    ; not yet
	movea.l	(sp)+,a0                        ; the start back
	rts

;------------------------------------------------------------------------------
; colour_test: the C test.  Not on a monochrome monitor ("No color--Monochrome monitor").  Draws 16
; bars (colours 0-15) on a low resolution screen at $20000; a timer B interrupt every 2 lines sets all
; 16 colours to the next shade of a table: red, green, blue and grey ramps first, then after Space
; cyan, yellow, magenta and grey; a second Space ends it (500 delays when unattended).  Then the
; screen and the vectors are put back and the STE scroll part at $3E5A runs.
;  Out: $28D bit 7 set (no wait for Space after it).
;  Changes d0-d3, d6, a0, a2, $292, $294, $4A6, $4D8, $4E6, $504, $508.
;------------------------------------------------------------------------------
colour_test:	; from: read_command
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.b	#$3,d0                          ; the resolution bits
	cmpi.b	#$2,d0                          ; high?
	bne.s	colour_test_draw                ; no
	lea	msg_no_colour_monochrome,a5     ; "No color--Monochrome monitor"
	bsr.w	print_string                    ; printed
	rts
colour_test_draw:
	move.w	$ffff8240.w,saved_colour0.w     ; palette 0 kept in $4A6
	movea.l	#$20000,a0                      ; clear the screen at $20000
colour_test_clear_screen:
	clr.l	(a0)+                           ; a long cleared
	cmpa.l	#$28000,a0                      ; 32K
	bne.s	colour_test_clear_screen        ; not yet
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
	bne.s	colour_test_draw_plane          ; not yet
	addq.w	#1,d2                           ; the next colour
	cmpi.w	#$10,d2                         ; to 15
	bne.s	colour_test_draw_bar            ; not yet
	dbra	d0,colour_test_draw_line        ; the next line
	bsr.w	save_screen_state               ; the screen address and colour 0 kept
	move.b	#$2,$ffff8201.w                 ; video base high, the screen at $20000
	clr.b	$ffff8203.w                     ; video base mid
	move.w	#$0,$ffff8260.w                 ; shift mode, low resolution
	move.l	$70.w,saved_vbl_vector.w        ; VBL vector
	move.l	$120.w,saved_vector.w           ; MFP timer B
	move.l	#vbl_handler,$70.w              ; VBL vector, a VBL routine that clears $294
	movea.l	#$fffffa01,a0                   ; the MFP
	clr.b	6(a0)                           ; no timer A, RS232 or DMA interrupts
	move.b	#$40,8(a0)                      ; only the keyboard/MIDI interrupt of IERB
	move.b	#$2,$20(a0)                     ; timer B: every 2 lines
	move.b	#$8,$1a(a0)                     ; counting display enable ends
	move.l	#colour_test_timer_b,$120.w     ; MFP timer B, the colour change routine
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_enable_interrupt            ; its interrupt on
	move.w	#$2200,sr                       ; IPL 2: VBLs on
	clr.w	colour_test_spaces.w            ; (the interrupt routine draws the shades)
	move.b	mode_flags.w,d0                 ; the mode flags
	andi.b	#$38,d0                         ; an unattended run?
	bne.s	colour_test_unattended          ; yes: no keys
colour_test_wait_space:
	bsr.w	get_key                         ; a key
	cmpi.w	#$20,d0                         ; Space?
	bne.s	colour_test_wait_space          ; no: wait on
	addi.w	#$1,colour_test_spaces.w        ; one more Space ($4D8)
	cmpi.w	#$2,colour_test_spaces.w        ; the second?
	bne.s	colour_test_wait_space          ; no: wait for it
	bra.s	colour_test_end                 ; the end
colour_test_unattended:
	move.w	#$1f4,d1                        ; 500 delays
colour_test_unattended_wait:
	bsr.w	delay                           ; a delay
	dbra	d1,colour_test_unattended_wait  ; 500 of them
colour_test_end:
	move.w	#$2400,sr                       ; IPL 4
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_disable_interrupt           ; its interrupt off
	bsr.w	video_setup                     ; the screen set up again
	move.l	saved_vbl_vector.w,$70.w        ; VBL vector
	move.l	saved_vector.w,$120.w           ; MFP timer B
	bsr.w	ste_scroll_test                 ; the STE scroll part
	bset	#$7,mode_flags.w                ; no wait for Space after the test
	rts

;------------------------------------------------------------------------------
; save_screen_state: keeps the screen address (high, middle and low bytes) in $4E6.l and colour 0
; in $4A6.  Changes d0.
;------------------------------------------------------------------------------
save_screen_state:	; from: colour_test, ste_scroll_test
	clr.l	saved_screen_address.w          ; (the long cleared)
	move.b	$ffff8201.w,d0                  ; video base high, high byte
	lsl.w	#8,d0                           ; (high byte into bits 8-15)
	move.b	$ffff8203.w,d0                  ; video base mid, middle byte
	lsl.l	#8,d0                           ; (into bits 16-23)
	move.b	$ffff820d.w,d0                  ; video base low, low byte
	move.l	d0,saved_screen_address.w       ; kept in $4E6
	move.w	$ffff8240.w,saved_colour0.w     ; palette 0, kept in $4A6
	rts

;------------------------------------------------------------------------------
; restore_screen_state: waits for a VBL, then sets medium resolution and puts back the screen address
; ($4E6) and colour 0 ($4A6) kept by save_screen_state; colour 3 grey.  Changes d6, $292.
;------------------------------------------------------------------------------
restore_screen_state:	; from: ste_scroll_test
	move.w	#$1,vbl_flag.w                  ; $292 set: the VBL clears it
	move.w	sr,d6                           ; keep the IPL
	move.w	#$2200,sr                       ; IPL 2: VBLs on
restore_screen_state_wait_vbl:
	cmpi.b	#$0,vbl_flag.w                  ; the VBL yet?
	bne.s	restore_screen_state_wait_vbl   ; no
	move.b	#$1,$ffff8260.w                 ; shift mode, medium resolution
	move.b	saved_screen_address+1.w,$ffff8201.w ; video base high, from $4E7
	move.b	saved_screen_address+2.w,$ffff8203.w ; video base mid, from $4E8
	move.b	saved_screen_address+3.w,$ffff820d.w ; video base low, from $4E9
	move.w	saved_colour0.w,$ffff8240.w     ; palette 0, colour 0 back
	move.w	#$666,$ffff8246.w               ; palette 3, colour 3 grey
	move.w	d6,sr                           ; IPL back
	rts

;------------------------------------------------------------------------------
; colour_test_timer_b: the colour test's timer B routine (every 2 lines): until the 69th interrupt of
; the frame, waits a little and sets all 16 colours to the next shade of the table (colour_test_shades_rgb,
; or colour_test_shades_cmy once $4D8 is not 0).  $292 counts the interrupts (the VBL clears it), $294
; is the offset of the next shade.  Registers kept.
;------------------------------------------------------------------------------
colour_test_timer_b:	; from: colour_test
	movem.l	d0-d1/a0,-(sp)                  ; registers kept
	cmpi.b	#$44,vbl_flag.w                 ; past the 69th interrupt of the frame ($292)?
	bgt.s	colour_test_timer_b_count       ; yes: no change
	cmpi.b	#$0,vbl_flag.w                  ; the first of the frame?
	bne.s	colour_test_timer_b_band        ; no
	clr.b	colour_shade.w                  ; yes: from the first shade ($294)
colour_test_timer_b_band:
	moveq	#30,d0                          ; a short wait
colour_test_timer_b_wait:
	dbra	d0,colour_test_timer_b_wait     ; wait into the line
	movea.l	#colour_test_shades_rgb,a0      ; red, green, blue and grey
	cmpi.w	#$0,colour_test_spaces.w        ; after the first Space?
	beq.s	colour_test_timer_b_set         ; no
	movea.l	#colour_test_shades_cmy,a0      ; yellow, cyan, magenta and grey
colour_test_timer_b_set:
	moveq	#0,d0                           ; (the high bytes clear)
	move.b	colour_shade.w,d0               ; the shade's offset
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
	addq.b	#2,colour_shade.w               ; the next shade
colour_test_timer_b_count:
	movea.l	#$fffffa01,a0                   ; the MFP
	bclr	#$0,$e(a0)                      ; timer B in service ends
	addq.b	#1,vbl_flag.w                   ; one more interrupt this frame
	movem.l	(sp)+,d0-d1/a0                  ; registers back
	rte

;------------------------------------------------------------------------------
; colour_test_shades_rgb: 69 shades for the colour test: black, a red ramp, a green ramp, a blue ramp, a
; grey ramp (16 steps each, with the STE's fourth colour bit).
;------------------------------------------------------------------------------
colour_test_shades_rgb:	; from: colour_test_timer_b
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
; colour_test_shades_cmy: 69 shades for the colour test after Space: black, a cyan ramp, a yellow ramp, a
; magenta ramp, a grey ramp.
;------------------------------------------------------------------------------
colour_test_shades_cmy:	; from: colour_test_timer_b
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
; and its name is added to a list below row 16; mouse buttons are plain while held and the arrows plain
; while the mouse moves (keyboard_test_mouse).  Shift Esc ends it, setting $28D bit 7.
;  Changes every data register, a0, a5, $230, $232, $28E, $298, $2C6.
;------------------------------------------------------------------------------
keyboard_test:	; from: read_command
	movea.l	#msg_keyboard_test,a5           ; "Keyboard test"
	bsr.w	show_status                     ; on the status line
	bsr.w	reset_keyboard_and_check        ; reset the keyboard
	tst.w	d0                              ; failed?
	bne.s	keyboard_test_fail              ; yes
	move.b	mode_flags.w,d1                 ; the mode flags
	andi.b	#$38,d1                         ; an unattended run?
	beq.s	keyboard_test_interactive       ; no: the interactive part
	tst.w	d0                              ; (already known to be 0)
	bne.s	keyboard_test_fail              ; (not taken)
	lea	msg_pass,a5                     ; "Pass"
	bra.s	keyboard_test_result            ; shown
keyboard_test_fail:
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
keyboard_test_result:
	bsr.w	show_result                     ; "Pass", or "Fail at cycle:" and the cycle
	rts
keyboard_test_interactive:
	bsr.w	clear_screen                    ; a clear screen
	move.w	#$0,key_list_column.w           ; the key name list at column 0
	move.w	#$10,key_list_row.w             ; row 16
	move.w	#$10,scroll_top.w               ; text scrolls from row 16 down ($298)
	move.b	#$ff,us_keyboard.w              ; $28E: a U.S. keyboard
	tst.b	$e0001d                         ; the ROM's os_conf low byte (country and PAL)
	beq.s	keyboard_test_title             ; 0: U.S.
	clr.b	us_keyboard.w                   ; else European
keyboard_test_title:
	bclr	#$4,cursor_flags.w              ; plain text
	lea	msg_european_keyboard,a5        ; "European keyboard (U.K. keytops shown)"
	tst.b	us_keyboard.w                   ; U.S.?
	beq.s	keyboard_test_print_title       ; no
	lea	msg_us_keyboard,a5              ; "U.S. keyboard"
keyboard_test_print_title:
	bsr.w	print_string                    ; printed
	lea	msg_hit_shift_esc,a5            ; "Hit shift Esc to exit"
	bsr.w	print_string                    ; printed
	bset	#$4,cursor_flags.w              ; inverse text
	moveq	#1,d2                           ; from scan code 1
keyboard_test_draw_keys:
	bsr.w	draw_key                        ; draw the key
	addi.b	#$1,d2                          ; the next scan code
	cmpi.b	#$73,d2                         ; to $72
	bne.s	keyboard_test_draw_keys         ; not yet
	moveq	#58,d0                          ; column 58
	moveq	#4,d1                           ; row 4
	bsr.w	set_cursor                      ; the cursor there
	lea	msg_mouse,a5                    ; "MOUSE"
	bsr.w	print_string                    ; printed
	bsr.w	draw_mouse_left_button          ; "L"
	bsr.w	draw_mouse_right_button         ; "R"
	bsr.w	draw_mouse_left_arrow           ; left arrow
	bsr.w	draw_mouse_right_arrow          ; right arrow
	bsr.w	draw_mouse_up_arrow             ; up arrow
	bsr.w	draw_mouse_down_arrow           ; down arrow
keyboard_test_loop:
	bsr.w	key_waiting                     ; a key pressed?
	tst.w	d0                              ; (d0 not 0: yes)
	bne.s	keyboard_test_key               ; yes
	bsr.w	keyboard_test_mouse             ; the mouse shown
	movea.l	release_ring_read.w,a0          ; the key release ring's read pointer ($47C)
	cmpa.l	release_ring_write.w,a0         ; the same as its write pointer ($478)?
	beq.s	keyboard_test_loop              ; yes: no key let go
	move.b	(a0)+,d2                        ; a released key
	andi.b	#$7f,d2                         ; its scan code
	cmpa.l	#$488,a0                        ; past the ring's end ($480-$487)?
	bne.w	keyboard_test_release_next      ; no
	movea.l	#$480,a0                        ; back to its start
keyboard_test_release_next:
	move.l	a0,release_ring_read.w          ; the read pointer moved on
	bset	#$4,cursor_flags.w              ; inverse text
	bsr.w	draw_key                        ; draw the key up
	bra.s	keyboard_test_loop              ; the next event
keyboard_test_key:
	bsr.w	get_key                         ; the key (d0 ASCII, d1 scan code)
	bsr.w	keyboard_key_click              ; a click
	cmpi.b	#$1b,d0                         ; Esc?
	bne.s	keyboard_test_key_down          ; no
	btst	#$7,shift_held.w                ; shift held ($492 bit 7)?
	beq.w	keyboard_test_key_down          ; no: an Esc key like any other
	bclr	#$4,cursor_flags.w              ; plain text again
	bset	#$7,mode_flags.w                ; no wait for Space after the test
	rts
keyboard_test_key_down:
	bclr	#$4,cursor_flags.w              ; plain text
	move.b	d1,d2                           ; the scan code
	bsr.w	draw_key                        ; draw the key down
	bset	#$4,cursor_flags.w              ; inverse again
	andi.w	#$ff,d2                         ; the scan code as a word
	cmpi.b	#$1c,d2                         ; Return?
	bne.w	keyboard_test_not_return        ; no
	lea	msg_key_list_return,a5          ; "RT"
	bra.w	keyboard_test_print_name        ; printed
keyboard_test_not_return:
	cmpi.b	#$72,d2                         ; keypad Enter?
	bne.w	keyboard_test_not_enter         ; no
	lea	msg_key_list_enter,a5           ; "ENTER"
	bra.w	keyboard_test_print_name        ; printed
keyboard_test_not_enter:
	cmpi.b	#$39,d2                         ; Space?
	bne.w	keyboard_test_key_name          ; no
	lea	msg_key_list_space,a5           ; "SPACE"
	bra.w	keyboard_test_print_name        ; printed
keyboard_test_key_name:
	lsl.w	#2,d2                           ; the scan code's name
	lea	key_names,a0                    ; the key names
	movea.l	0(a0,d2.w),a5                   ; the key names, a long each
keyboard_test_print_name:
	move.w	key_list_row.w,d1               ; the list's place
	move.w	key_list_column.w,d0            ; (column and row)
	bsr.w	set_cursor                      ; the cursor there
	bsr.w	print_string                    ; the name printed
	bsr.w	print_space                     ; and a space
	move.w	cursor_column.w,key_list_column.w ; the list's column: the cursor's ($2BE)
	move.w	cursor_row.w,key_list_row.w     ; the list's row: the cursor's ($2C0)
	bra.w	keyboard_test_loop              ; the next key

;------------------------------------------------------------------------------
; keyboard_test_mouse: shows the last mouse packet in the keyboard test.  A packet ($493 its header,
; $235 the X move, $234 the Y move): each button drawn plain while held, inverse when not, and the
; arrow of each direction moved drawn plain (its bit set in $296); then the packet is cleared and $284
; set to 5.  No packet: $284 counted down, and at 0 the plain arrows drawn inverse again.
;  Changes d0, d1, a5, $234, $235, $284, $296, $493.
;------------------------------------------------------------------------------
keyboard_test_mouse:	; from: keyboard_test
	tst.b	ikbd_packet_header.w            ; a mouse packet ($493 the header)?
	beq.w	keyboard_test_mouse_idle        ; no
	bset	#$4,cursor_flags.w              ; inverse
	btst	#$0,ikbd_packet_header.w        ; the right button held?
	beq.s	keyboard_test_mouse_right       ; no
	bclr	#$4,cursor_flags.w              ; yes: plain
keyboard_test_mouse_right:
	bsr.w	draw_mouse_right_button         ; "R"
	bset	#$4,cursor_flags.w              ; inverse
	btst	#$1,ikbd_packet_header.w        ; the left button held?
	beq.s	keyboard_test_mouse_left        ; no
	bclr	#$4,cursor_flags.w              ; yes: plain
keyboard_test_mouse_left:
	bsr.w	draw_mouse_left_button          ; "L"
	tst.b	ikbd_data_second.w              ; a move in X ($235)?
	beq.s	keyboard_test_mouse_y           ; no
	bclr	#$4,cursor_flags.w              ; plain
	btst	#$7,ikbd_data_second.w          ; to the left (negative)?
	beq.s	keyboard_test_mouse_right_move  ; no
	bsr.w	draw_mouse_left_arrow           ; the left arrow
	bset	#$0,test_index_byte.w           ; $296 bit 0: the left arrow plain
	bra.s	keyboard_test_mouse_y           ; on to Y
keyboard_test_mouse_right_move:
	bsr.w	draw_mouse_right_arrow          ; the right arrow
	bset	#$1,test_index_byte.w           ; $296 bit 1: the right arrow plain
keyboard_test_mouse_y:
	clr.b	ikbd_data_second.w              ; the X move used
	tst.b	ikbd_data_first.w               ; a move in Y ($234)?
	beq.s	keyboard_test_mouse_used        ; no
	bclr	#$4,cursor_flags.w              ; plain
	btst	#$7,ikbd_data_first.w           ; up (negative)?
	bne.s	keyboard_test_mouse_up          ; yes
	bsr.w	draw_mouse_down_arrow           ; the down arrow
	bset	#$3,test_index_byte.w           ; $296 bit 3: the down arrow plain
	bra.s	keyboard_test_mouse_used        ; done
keyboard_test_mouse_up:
	bsr.w	draw_mouse_up_arrow             ; the up arrow
	bset	#$2,test_index_byte.w           ; $296 bit 2: the up arrow plain
keyboard_test_mouse_used:
	clr.b	ikbd_data_first.w               ; the Y move used
	clr.b	ikbd_packet_header.w            ; the packet used
	move.b	#$5,timer_irq_flags.w           ; 5 calls with no packet before the arrows go back ($284)
	rts
keyboard_test_mouse_idle:
	tst.b	test_index_byte.w               ; any arrow plain ($296)?
	beq.w	keyboard_test_mouse_exit        ; no
	subi.b	#$1,timer_irq_flags.w           ; one call less ($284)
	bne.w	keyboard_test_mouse_exit        ; not yet 0
	bset	#$4,cursor_flags.w              ; inverse
	btst	#$0,test_index_byte.w           ; the left arrow plain?
	beq.w	keyboard_test_mouse_idle_right  ; no
	bsr.w	draw_mouse_left_arrow           ; inverse again
keyboard_test_mouse_idle_right:
	btst	#$1,test_index_byte.w           ; the right arrow plain?
	beq.w	keyboard_test_mouse_idle_up     ; no
	bsr.w	draw_mouse_right_arrow          ; inverse again
keyboard_test_mouse_idle_up:
	btst	#$2,test_index_byte.w           ; the up arrow plain?
	beq.w	keyboard_test_mouse_idle_down   ; no
	bsr.w	draw_mouse_up_arrow             ; inverse again
keyboard_test_mouse_idle_down:
	btst	#$3,test_index_byte.w           ; the down arrow plain?
	beq.w	keyboard_test_mouse_idle_done   ; no
	bsr.w	draw_mouse_down_arrow           ; inverse again
keyboard_test_mouse_idle_done:
	clr.b	test_index_byte.w               ; all inverse now
keyboard_test_mouse_exit:
	rts

;------------------------------------------------------------------------------
; draw_mouse_right_button: "R" at column 61, row 6.  Changes d0, d1.
;------------------------------------------------------------------------------
draw_mouse_right_button:	; from: keyboard_test, keyboard_test_mouse
	moveq	#61,d0                          ; column 61
	moveq	#6,d1                           ; row 6
	bsr.w	set_cursor                      ; the cursor there
	move.b	#$52,d1                         ; 'R'
	bsr.w	put_char                        ; drawn
	rts

;------------------------------------------------------------------------------
; draw_mouse_left_button: "L" at column 59, row 6.  Changes d0, d1.
;------------------------------------------------------------------------------
draw_mouse_left_button:	; from: keyboard_test, keyboard_test_mouse
	moveq	#59,d0                          ; column 59
	moveq	#6,d1                           ; row 6
	bsr.w	set_cursor                      ; the cursor there
	move.b	#$4c,d1                         ; 'L'
	bsr.w	put_char                        ; drawn
	rts

;------------------------------------------------------------------------------
; draw_mouse_left_arrow: the left arrow (character 4) at column 58, row 10.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
draw_mouse_left_arrow:	; from: keyboard_test, keyboard_test_mouse
	moveq	#58,d0                          ; column 58
	moveq	#10,d1                          ; row 10
	bsr.w	set_cursor                      ; the cursor there
	lea	key_text_left_arrow,a5          ; the left arrow
	bsr.w	print_string                    ; drawn
	rts

;------------------------------------------------------------------------------
; draw_mouse_right_arrow: the right arrow (character 3) at column 62, row 10.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
draw_mouse_right_arrow:	; from: keyboard_test, keyboard_test_mouse
	moveq	#62,d0                          ; column 62
	moveq	#10,d1                          ; row 10
	bsr.w	set_cursor                      ; the cursor there
	lea	key_text_right_arrow,a5         ; the right arrow
	bsr.w	print_string                    ; drawn
	rts

;------------------------------------------------------------------------------
; draw_mouse_down_arrow: the down arrow (character 2) at column 60, row 12.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
draw_mouse_down_arrow:	; from: keyboard_test, keyboard_test_mouse
	moveq	#60,d0                          ; column 60
	moveq	#12,d1                          ; row 12
	bsr.w	set_cursor                      ; the cursor there
	lea	key_text_down_arrow,a5          ; the down arrow
	bsr.w	print_string                    ; drawn
	rts

;------------------------------------------------------------------------------
; draw_mouse_up_arrow: the up arrow (character 1) at column 60, row 8.  Changes d0, d1, a5.
;------------------------------------------------------------------------------
draw_mouse_up_arrow:	; from: keyboard_test, keyboard_test_mouse
	moveq	#60,d0                          ; column 60
	moveq	#8,d1                           ; row 8
	bsr.w	set_cursor                      ; the cursor there
	lea	key_text_up_arrow,a5            ; the up arrow
	bsr.w	print_string                    ; drawn
	rts

;------------------------------------------------------------------------------
; draw_key: draws the keytop of a scan code at its place on the keyboard picture (inverse or plain as
; $2C6 bit 4 says).  Scan codes above $72, or with no place, draw nothing.  The European '#' ($2B)
; and '\' ($60) keytops are never used: the scan code has been doubled before it is compared with
; $2B00 and $6000.
;  In:  d2.b the scan code.  Changes d0, d1, a0, a5.
;------------------------------------------------------------------------------
draw_key:	; from: keyboard_test
	move.l	d2,-(sp)                        ; keep the scan code
	cmpi.b	#$72,d2                         ; above $72?
	bgt.s	draw_key_done                   ; yes: nothing
	andi.l	#$ff,d2                         ; (the upper bytes clear)
	lsl.b	#1,d2                           ; a word index
	lea	key_positions,a0                ; the keys' places
	move.w	0(a0,d2.w),d1                   ; column in the high byte, row in the low
	beq.s	draw_key_done                   ; no place
	move.l	d2,-(sp)                        ; keep the index
	move.w	d1,d0                           ; (column in the high byte)
	andi.w	#$ff,d1                         ; row
	lsr.w	#8,d0                           ; column
	bsr.w	set_cursor                      ; the cursor there
	move.l	(sp)+,d2                        ; the index back
	tst.b	us_keyboard.w                   ; a U.S. keyboard ($28E)?
	bne.s	draw_key_name                   ; yes
	cmpi.w	#$2b00,d2                       ; never true (see the header)
	beq.s	draw_key_hash                   ; (never)
	cmpi.w	#$6000,d2                       ; never true
	beq.s	draw_key_backslash              ; (never)
draw_key_name:
	lsl.w	#1,d2                           ; a long index
	lea	key_names,a0                    ; the key names
	movea.l	0(a0,d2.w),a5                   ; the name
	beq.s	draw_key_done                   ; no name
draw_key_print:
	bsr.w	print_string                    ; the keytop printed
draw_key_done:
	move.l	(sp)+,d2                        ; the scan code back
	rts
draw_key_hash:
	lea	key_text_hash,a5                ; "#"
	bra.s	draw_key_print                  ; printed
draw_key_backslash:
	lea	key_text_backslash,a5           ; "\"
	bra.s	draw_key_print                  ; printed

;------------------------------------------------------------------------------
; reset_keyboard_and_check: resets the keyboard ($80,$01) and waits for its $Fx reply.  No reply: "K1
; Keyboard not responding" and $28D bit 0 set; a reply that is no $Fx: "K2 Keyboard status error"; a key
; release seen before the reply: "K0 Stuck key: " and the key's name.  On an error the keyboard
; interrupt is left disabled (K1, K2) and the background turned red.  The keyboard's revision (the
; reply's low nibble + 1) goes in $27B.
;  Out: d0 = 0 when the keyboard answered, -1 on an error.  Changes d1, d7, a0, a5, $28A, $490.
;------------------------------------------------------------------------------
reset_keyboard_and_check:	; from: menu_start, keyboard_test
	moveq	#6,d0                           ; the keyboard/MIDI interrupt
	bsr.w	mfp_enable_interrupt            ; on
	moveq	#-128,d1                        ; reset
	bsr.w	ikbd_send                       ; sent
	moveq	#1,d1                           ; the second reset byte
	bsr.w	ikbd_send                       ; sent
	clr.b	key_release.w                   ; no key let go yet ($28A)
	clr.w	kbd_buffer_head.w               ; the key buffer's head
	clr.w	kbd_buffer_tail.w               ; empty the key buffer
	bset	#$3,ikbd_packet_flags.w         ; $490 bit 3: the $Fx reply goes to the key buffer
	move.l	#$c350,d7                       ; 50000 tries
reset_keyboard_wait:
	bsr.w	key_waiting                     ; a key (the reply)?
	tst.w	d0                              ; (d0 not 0: yes)
	bne.s	reset_keyboard_reply            ; yes
	sub.l	#$1,d7                          ; one try less
	bne.s	reset_keyboard_wait             ; not yet
	lea	msg_keyboard_not_responding,a5  ; "K1 Keyboard not responding"
	bsr.w	print_string                    ; printed
	bra.s	reset_keyboard_no_reply         ; on to the failure
reset_keyboard_status_error:
	lea	msg_keyboard_status_error,a5    ; "K2 Keyboard status error"
reset_keyboard_no_reply:
	bset	#$0,mode_flags.w                ; $28D bit 0: the keyboard failed
	moveq	#6,d0                           ; the keyboard/MIDI interrupt
	bsr.w	mfp_disable_interrupt           ; off
reset_keyboard_fail:
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	moveq	#-1,d0                          ; failed
	rts
reset_keyboard_reply:
	bsr.w	get_key                         ; the reply (d1 its scan code byte)
	move.b	d1,keyboard_revision.w          ; kept in $27B
	andi.b	#$f0,d1                         ; its top nibble
	cmp.b	#$f0,d1                         ; a $Fx status byte?
	bne.s	reset_keyboard_status_error     ; no
	cmpi.b	#$f0,key_release.w              ; a key released ($80-$EF) before it ($28A)?
	blt.w	reset_keyboard_stuck_key        ; yes
	andi.b	#$f,keyboard_revision.w         ; the low nibble
	addi.b	#$1,keyboard_revision.w         ; +1: the keyboard's revision
	bclr	#$0,mode_flags.w                ; the keyboard works
	moveq	#0,d0                           ; answered
	rts
reset_keyboard_stuck_key:
	lea	msg_stuck_key,a5                ; "K0 Stuck key: "
	bsr.w	print_string                    ; printed
	move.b	key_release.w,d1                ; the key released
	andi.w	#$7f,d1                         ; its scan code
	lsl.w	#2,d1                           ; a long index
	lea	key_names,a0                    ; the key names
	movea.l	0(a0,d1.w),a5                   ; its name
	bsr.w	print_string                    ; printed
	bsr.w	print_newline                   ; the line ended
	bra.s	reset_keyboard_fail             ; Fail

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
	cmpa.l	#key_positions,a0               ; all 7 pairs
	bne.s	keyboard_key_click_registers    ; not yet
	move.l	#$c00,d7                        ; let it sound
keyboard_key_click_wait:
	sub.l	#$1,d7                          ; let it sound
	bne.s	keyboard_key_click_wait         ; not yet
	bsr.w	psg_sound_off                   ; the volumes off
	rts

;------------------------------------------------------------------------------
; midi_test: the M test (needs a MIDI loopback cable).  Sends every byte 0-255 out of the MIDI port 8
; times and checks each comes back.  Errors: "M0 MIDI not received", "M1 MIDI data mismatch",
; "M2 MIDI framing", "M3 MIDI parity" (its text is picked but never printed), "M4 MIDI data overrun";
; $49C keeps them.  The MIDI buffer record at $620 is set from the table at $9AF0 first.
;  Changes d0-d3, d7, a0, a1, a5, $285, $49C.
;------------------------------------------------------------------------------
midi_test:	; from: test_routines
	movea.l	#msg_testing_midi,a5            ; "Testing MIDI"
	bsr.w	show_status                     ; on the status line
	clr.b	test_errors_extra.w             ; no MIDI errors yet ($49C)
	movea.l	#$620,a0                        ; the MIDI buffer record set up
	movea.l	#midi_record_init,a1            ; from its table
	moveq	#29,d0                          ; 30 bytes
	bsr.w	copy_bytes                      ; copied
	bsr.w	midi_record_and_acia            ; a0 the record, a1 the ACIA
	move.b	#$3,0(a1)                       ; master reset
	move.b	#$95,0(a1)                      ; receive interrupt, 8 bits no parity 1 stop, divide by 16
	move.b	#$8,pass_count.w                ; 8 passes ($285)
midi_test_pass:
	moveq	#0,d2                           ; byte 0 first
midi_test_byte:
	bsr.w	midi_send                       ; send it
	bsr.w	midi_receive                    ; and read it back
	tst.b	test_errors_extra.w             ; an error or no byte?
	bne.s	midi_test_receive_error         ; yes
	cmp.b	d0,d2                           ; the same byte?
	bne.s	midi_test_mismatch              ; no
	add.b	#$1,d2                          ; the next byte
	bcc.s	midi_test_byte                  ; to 255
	subi.b	#$1,pass_count.w                ; one pass less
	bne.s	midi_test_pass                  ; not yet
	movea.l	#msg_pass,a5                    ; "Pass"
	bsr.w	show_result                     ; shown
	rts
midi_test_receive_error:
	move.b	0(a1),d3                        ; the ACIA status
	btst	#$4,d3                          ; framing error?
	beq.s	midi_test_overrun               ; no
	bset	#$2,test_errors_extra.w         ; $49C bit 2: framing
	movea.l	#msg_midi_framing,a5            ; "M2 MIDI framing"
	bsr.w	print_string                    ; printed
midi_test_overrun:
	btst	#$5,d3                          ; overrun?
	beq.s	midi_test_parity                ; no
	bset	#$0,test_errors_extra.w         ; $49C bit 0: overrun
	movea.l	#msg_midi_data_overrun,a5       ; "M4 MIDI data overrun"
	bsr.w	print_string                    ; printed
midi_test_parity:
	btst	#$6,d3                          ; parity error?
	beq.s	midi_test_nothing               ; no
	bset	#$1,test_errors_extra.w         ; $49C bit 1: parity
	movea.l	#msg_midi_parity,a5             ; "M3 MIDI parity", not printed
midi_test_nothing:
	andi.b	#$70,d3                         ; any of the three?
	bne.s	midi_test_fail                  ; yes
	movea.l	#msg_midi_not_received,a5       ; "M0 MIDI not received"
	bsr.w	print_string                    ; printed
	bset	#$4,test_errors_extra.w         ; $49C bit 4: not received
	bra.s	midi_test_fail                  ; Fail
midi_test_mismatch:
	movea.l	#msg_midi_data_mismatch,a5      ; "M1 MIDI data mismatch"
	bsr.w	print_string                    ; printed
	bset	#$3,test_errors_extra.w         ; $49C bit 3: mismatch
midi_test_fail:
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bsr.w	show_result                     ; shown with the cycle
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
	movem.l	d7/a0-a1,-(sp)                  ; registers kept
	bsr.w	midi_record_and_acia            ; a0 the record, a1 the ACIA
midi_send_wait:
	bsr.w	midi_read_status                ; read the status
	btst	#$1,d7                          ; transmit register empty?
	beq.s	midi_send_wait                  ; no: wait
	move.b	d2,2(a1)                        ; send the byte
	movem.l	(sp)+,d7/a0-a1                  ; registers back
	rts

;------------------------------------------------------------------------------
; midi_buffer_empty: Out: d0 = 0 when the MIDI input buffer holds a byte, -1 when it is empty;
; a0 the record, a1 the ACIA, a2/a3 changed.
;------------------------------------------------------------------------------
midi_buffer_empty:	; from: midi_receive
	bsr.w	midi_record_and_acia            ; a0 the record, a1 the ACIA
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
	subi.w	#$1,d3                          ; one try less
	beq.s	midi_receive_fail               ; out of tries: not received
	bsr.s	midi_buffer_empty               ; a byte in the buffer?
	tst.w	d0                              ; (d0 = 0: a byte)
	beq.s	midi_receive_wait               ; no: wait on
	move.b	$1c(a0),d0                      ; the status read last
	andi.b	#$70,d0                         ; framing, overrun or parity?
	bne.s	midi_receive_fail               ; yes
	bsr.w	midi_get_input                  ; take the byte
midi_receive_exit:
	move.b	#$0,$fffffa1f.w                 ; MFP TADR, timer A data 0
	move.b	(sp)+,d2                        ; the byte sent back
	rts
midi_receive_fail:
	bset	#$4,test_errors_extra.w         ; $49C bit 4: not received or bad
	bra.s	midi_receive_exit               ; out

;------------------------------------------------------------------------------
; midi_put_output: (not called) puts d1 in the MIDI output buffer of the record at a0.
;  Out: C set when the buffer is full.
;------------------------------------------------------------------------------
midi_put_output:
	movem.l	d1-d2/a0-a1,-(sp)               ; registers kept
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
	bra.s	midi_put_output_exit            ; out
midi_put_output_full:
	move.w	(sp)+,sr                        ; IPL back
	ori.b	#$1,ccr                         ; C set: full
midi_put_output_exit:
	movem.l	(sp)+,d1-d2/a0-a1               ; registers back
	rts

;------------------------------------------------------------------------------
; midi_get_input: takes the next byte from the MIDI input buffer of the record at a0.
;  Out: d0.b the byte and C clear, or C set when the buffer is empty.
;------------------------------------------------------------------------------
midi_get_input:	; from: midi_receive
	movem.l	d1/a0-a1,-(sp)                  ; registers kept
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
	bra.s	midi_get_input_exit             ; out
midi_get_input_empty:
	move.w	(sp)+,sr                        ; IPL back
	ori.b	#$1,ccr                         ; C set: empty
midi_get_input_exit:
	movem.l	(sp)+,d1/a0-a1                  ; registers back
	rts

;------------------------------------------------------------------------------
; midi_input_next: moves the input index d1 on one, wrapping at the buffer size.
;------------------------------------------------------------------------------
midi_input_next:	; from: midi_get_input
	addq.w	#1,d1                           ; the next index
	cmp.w	4(a0),d1                        ; past the end?
	bcs.w	midi_input_next_exit            ; not past it
	moveq	#0,d1                           ; back to 0
midi_input_next_exit:
	rts

;------------------------------------------------------------------------------
; midi_output_next: moves the output index d2 on one, wrapping at the buffer size.
;------------------------------------------------------------------------------
midi_output_next:	; from: midi_put_output
	addq.w	#1,d2                           ; the next index
	cmp.w	$12(a0),d2                      ; past the end?
	bcs.w	midi_output_next_exit           ; not past it
	moveq	#0,d2                           ; back to 0
midi_output_next_exit:
	rts

;------------------------------------------------------------------------------
; midi_record_and_acia: Out: a0 the MIDI buffer record ($620), a1 the MIDI ACIA ($FFFFFC04).
;------------------------------------------------------------------------------
midi_record_and_acia:	; from: keyboard_setup, acia_interrupt, midi_test, midi_send, midi_buffer_empty
	movea.l	#$620,a0                        ; the MIDI buffer record
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
; rs232_test: the S test (needs an RS232 loopback connector).  With the RS232 input to the menu off
; ($28D bit 1):
;  - the handshake lines: DTR on must bring the RI and DCD interrupts, RTS on the CTS interrupt
;    (each interrupt routine clears its bit of $208); a missing one sets $49B bit 0, 1 or 2
;  - polled: "No loopback connector" sent at 9600 bps and checked (rs232_send_text); nothing back
;    fails at once; then $55,$AA at every rate from 300 bps up to 19.2k bps, a failing rate printed
;  - by interrupt at 9600 bps: the transmit interrupt sends 1-255 after a 0, the receive interrupt
;    keeps each byte in $286, until $FF arrives ($49A bit 5 on a timeout); the transmit error
;    interrupt must have seen an underrun ($289 bit 6, else $49B bit 6)
;  - an overrun: $55 left unread under $AA must bring the receive error interrupt ($288 bit 6, else
;    $49B bit 7)
; Each error bit of $49A (bits 0-7) and $49B (bits 0-4, as bits 8-12) prints its "S" text, then Fail;
; else Pass.  The mode flags and the RS232 rate chosen ($22E) are put back at the end.
;  Changes d0-d3, d6, d7, a0, a5, $208, $285-$288, $49A, $49B.
;------------------------------------------------------------------------------
rs232_test:	; from: test_routines
	clr.b	test_errors.w                   ; no errors yet
	clr.b	test_errors_high.w              ; ($49B too)
	movea.l	#msg_testing_rs232_loopback,a5  ; "Testing RS232 loopback"
	bsr.w	show_status                     ; on the status line
	move.b	mode_flags.w,-(sp)              ; the mode flags kept
	bset	#$1,mode_flags.w                ; no RS232 input to the menu
	lea	$ffff8802.w,a0                  ; PSG write data
	move.b	#$7,$ffff8800.w                 ; PSG register select, sound chip register 7
	move.b	#$c0,(a0)                       ; ports A and B output
	move.b	#$e,$ffff8800.w                 ; PSG register select, register 14, port A
	move.b	#$18,(a0)                       ; DTR and RTS off
	bset	#$6,interrupt_events.w          ; wait for the RI interrupt
	moveq	#14,d0                          ; RI
	bsr.w	mfp_enable_interrupt            ; its interrupt on
	bclr	#$4,(a0)                        ; DTR on
	bsr.w	delay                           ; wait
	btst	#$6,interrupt_events.w          ; the interrupt cleared it?
	beq.s	rs232_test_dcd                  ; yes
	bset	#$0,test_errors_high.w          ; $49B bit 0: no RI
rs232_test_dcd:
	moveq	#14,d0                          ; RI
	bsr.w	mfp_disable_interrupt           ; off
	bset	#$4,(a0)                        ; DTR off
	bset	#$1,interrupt_events.w          ; wait for the DCD interrupt
	moveq	#1,d0                           ; DCD
	bsr.w	mfp_enable_interrupt            ; its interrupt on
	bclr	#$4,(a0)                        ; DTR on
	bsr.w	delay                           ; wait
	btst	#$1,interrupt_events.w          ; the interrupt cleared it?
	beq.s	rs232_test_cts                  ; yes
	bset	#$1,test_errors_high.w          ; $49B bit 1: no DCD
rs232_test_cts:
	moveq	#1,d0                           ; DCD
	bsr.w	mfp_disable_interrupt           ; off
	bset	#$2,interrupt_events.w          ; wait for the CTS interrupt
	moveq	#2,d0                           ; CTS
	bsr.w	mfp_enable_interrupt            ; its interrupt on
	bclr	#$3,(a0)                        ; RTS on
	bsr.w	delay                           ; wait
	btst	#$2,interrupt_events.w          ; the interrupt cleared it?
	beq.s	rs232_test_loopback             ; yes
	bset	#$2,test_errors_high.w          ; $49B bit 2: no CTS
rs232_test_loopback:
	moveq	#2,d0                           ; CTS
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#2,d0                           ; 9600 bps
	bsr.w	rs232_setup_rate                ; the USART at that rate
	move.w	#$3e8,d7                        ; a short timeout
	lea	rs232_loopback_text,a5          ; the text "No loopback connector" as data
	bsr.w	rs232_send_text                 ; sent and checked
	tst.b	test_errors.w                   ; anything wrong?
	bne.w	rs232_test_fail                 ; yes: no connector
	move.b	#$9c,$28(a0)                    ; odd parity (set back to none by the rate set-up below)
	lea	rs232_loopback_bytes,a5         ; $55,$AA (the $00 after them ends it)
	move.l	#$7d00,d7                       ; a long timeout
	move.b	#$40,pass_count.w               ; from 300 bps ($285: timer D data $40)
rs232_test_rate:
	move.b	pass_count.w,d0                 ; this rate
	bsr.w	rs232_setup_rate                ; the USART at it
	bsr.w	rs232_send_text                 ; $55,$AA sent and checked
	tst.b	test_errors.w                   ; anything wrong?
	beq.s	rs232_test_next_rate            ; no
	move.b	pass_count.w,d0                 ; the rate
	bsr.w	print_rs232_rate                ; printed
	bra.w	rs232_test_fail                 ; Fail
rs232_test_next_rate:
	move.b	pass_count.w,d1                 ; the timer D data
	lsr.b	#1,d1                           ; double the rate
	move.b	d1,pass_count.w                 ; kept ($285)
	tst.b	pass_count.w                    ; all done?
	bne.s	rs232_test_rate                 ; no: the next rate
	moveq	#9,d0                           ; interrupts 9-12 on: transmit error, transmit empty, receive error,
                                                ;   receive full
rs232_test_interrupts_on:
	bsr.w	mfp_enable_interrupt            ; on
	addq.w	#1,d0                           ; the next
	cmpi.b	#$d,d0                          ; to 12
	bne.s	rs232_test_interrupts_on        ; not yet
	moveq	#2,d0                           ; 9600 bps
	bsr.w	rs232_setup_rate                ; the USART at that rate
	clr.b	rs232_sent.w                    ; the byte sent last ($287): 0
	clr.b	rs232_received.w                ; the byte received last ($286)
	clr.b	rs232_rx_errors.w               ; no receive errors ($288)
	move.w	#$d2f0,d3                       ; timeout
	move.b	rs232_sent.w,$2e(a0)            ; 0 sent: the transmit interrupt sends the rest
rs232_test_wait_last:
	cmpi.b	#$ff,rs232_received.w           ; $FF received ($286)?
	beq.s	rs232_test_check_underrun       ; yes
	subi.w	#$1,d3                          ; one try less
	bne.s	rs232_test_wait_last            ; not yet
	bset	#$5,test_errors.w               ; $49A bit 5: the bytes did not all come back
	moveq	#10,d0                          ; transmit empty
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#12,d0                          ; receive full
	bsr.w	mfp_disable_interrupt           ; off
	bra.w	rs232_test_fail                 ; Fail
rs232_test_check_underrun:
	bsr.w	delay                           ; wait
	btst	#$6,rs232_tx_status.w           ; the transmit error interrupt saw an underrun ($289)?
	bne.s	rs232_test_error_interrupts     ; yes
	bset	#$6,test_errors_high.w          ; $49B bit 6: no underrun
rs232_test_error_interrupts:
	moveq	#9,d0                           ; transmit error
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#10,d0                          ; transmit empty
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#12,d0                          ; receive full
	bsr.w	mfp_disable_interrupt           ; off
rs232_test_overrun_wait_empty:
	tst.b	$2c(a0)                         ; transmit buffer empty?
	bpl.s	rs232_test_overrun_wait_empty   ; not yet
	move.b	#$55,$2e(a0)                    ; send $55
rs232_test_overrun_wait_full:
	btst	#$7,$2a(a0)                     ; received?
	beq.s	rs232_test_overrun_wait_full    ; not yet
	move.b	#$aa,$2e(a0)                    ; send $AA, which overruns the unread $55
	bsr.w	delay                           ; wait
	tst.b	$2e(a0)                         ; read the receive buffer
	bsr.w	delay                           ; wait
	btst	#$6,rs232_rx_errors.w           ; the receive error interrupt saw the overrun ($288)?
	bne.s	rs232_test_overrun_checked      ; yes
	bset	#$7,test_errors_high.w          ; $49B bit 7: no overrun
rs232_test_overrun_checked:
	moveq	#11,d0                          ; receive error
	bsr.w	mfp_disable_interrupt           ; off
	tst.b	$2e(a0)                         ; empty the receiver
	tst.b	$2a(a0)                         ; and its status
	move.b	test_errors.w,d0                ; any error?
	or.b	test_errors_high.w,d0           ; (in either byte)
	bne.s	rs232_test_fail                 ; yes: Fail
	tst.b	test_errors.w                   ; (always 0 here)
	beq.s	rs232_test_pass                 ; Pass
rs232_test_fail:
	moveq	#0,d1                           ; from the first text
	moveq	#0,d0                           ; from bit 0
	move.b	test_errors_high.w,d2           ; $49B as bits 8-15
	lsl.w	#8,d2                           ; (into the high byte)
	move.b	test_errors.w,d2                ; $49A as bits 0-7
	lea	rs232_error_texts,a0            ; the "S" error texts
rs232_test_print_errors:
	btst	d0,d2                           ; this error?
	beq.s	rs232_test_next_error           ; no
	movea.l	0(a0,d1.w),a5                   ; the text
	bsr.w	print_string                    ; printed
rs232_test_next_error:
	addq.w	#4,d1                           ; the next text
	addq.w	#1,d0                           ; the next bit
	cmp.w	#$d,d0                          ; 13 errors
	bne.s	rs232_test_print_errors         ; not yet
	bsr.w	rs232_setup                     ; the USART at the rate chosen
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	move.w	#$500,$ffff8240.w               ; palette 0, red background
	bra.s	rs232_test_result               ; shown
rs232_test_pass:
	movea.l	#msg_pass,a5                    ; "Pass"
rs232_test_result:
	bsr.w	show_result                     ; "Pass", or "Fail at cycle:" and the cycle
	move.b	(sp)+,mode_flags.w              ; the mode flags back
	move.w	rs232_rate.w,d0                 ; the rate chosen
	bsr.w	rs232_setup_rate                ; the USART at it
	rts

;------------------------------------------------------------------------------
; rs232_send_text: sends the bytes of a 0-ended string out of the MFP USART, polled, and checks that each
; comes back the same.  Errors go in $49A: bit 4 not received, bit 3 mismatch, bits 0-2 overrun,
; parity, framing; $49B bit 3 when the transmitter never empties.
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
	subi.w	#$1,d3                          ; one try less
	bne.s	rs232_send_text_wait_empty      ; not yet
	bset	#$3,test_errors_high.w          ; $49B bit 3: the transmitter never empties
	bra.s	rs232_send_text_done            ; out
rs232_send_text_send:
	move.b	0(a5,d0.w),d1                   ; the next byte
	addq.w	#1,d0                           ; (the index on)
	cmpi.b	#$0,d1                          ; the end?
	beq.s	rs232_send_text_done            ; yes
	move.b	d1,$2e(a0)                      ; send it
	move.w	d7,d3                           ; the timeout
rs232_send_text_wait_receive:
	subi.w	#$1,d3                          ; one try less
	bne.s	rs232_send_text_check           ; not out of tries
	bset	#$4,test_errors.w               ; $49A bit 4: not received
	bra.s	rs232_send_text_byte            ; the next byte
rs232_send_text_check:
	move.b	$2a(a0),d6                      ; receive status
	bpl.s	rs232_send_text_wait_receive    ; nothing yet
	bsr.w	rs232_receive_errors            ; its errors
	move.b	$2e(a0),d2                      ; the byte received
	cmp.b	d2,d1                           ; the same?
	beq.s	rs232_send_text_next            ; yes
	bset	#$3,test_errors.w               ; $49A bit 3: a different byte
rs232_send_text_next:
	bra.s	rs232_send_text_byte            ; the next byte
rs232_send_text_done:
	rts

;------------------------------------------------------------------------------
; rs232_receive_errors: turns the MFP receive status d6 into $676 bits: framing bit 2, parity bit 1,
; overrun bit 0.
;------------------------------------------------------------------------------
rs232_receive_errors:	; from: rs232_send_text
	btst	#$4,d6                          ; framing error?
	beq.s	rs232_receive_errors_parity     ; no
	bset	#$2,test_errors.w               ; $49A bit 2
rs232_receive_errors_parity:
	btst	#$5,d6                          ; parity error?
	beq.s	rs232_receive_errors_overrun    ; no
	bset	#$1,test_errors.w               ; $49A bit 1
rs232_receive_errors_overrun:
	btst	#$6,d6                          ; overrun?
	beq.w	rs232_receive_errors_done       ; no
	bset	#$0,test_errors.w               ; $49A bit 0
rs232_receive_errors_done:
	rts

;------------------------------------------------------------------------------
; print_rs232_rate: prints the rate of a timer D data value ("19.2k bps" to "300 bps"); a value not
; in the table prints nothing.  In: d0.b the value.  Changes d0, d1, a0, a5.
;------------------------------------------------------------------------------
print_rs232_rate:	; from: cmd_rs232_rate, rs232_test
	andi.b	#$7f,d0                         ; (the top bit dropped)
	lea	rs232_rate_codes,a0             ; the values 1, 2, 4 ... $40
	clr.l	d1                              ; from the first
print_rs232_rate_find:
	cmp.b	0(a0,d1.w),d0                   ; this one?
	beq.w	print_rs232_rate_text           ; yes
	addq.w	#1,d1                           ; the next
	cmp.w	#$7,d1                          ; 7 values
	bne.s	print_rs232_rate_find           ; not yet
	rts                                     ; not found
print_rs232_rate_text:
	lea	rs232_rate_texts,a0             ; the rate texts
	lsl.w	#2,d1                           ; a long index
	movea.l	0(a0,d1.w),a5                   ; the text
	bsr.w	print_string                    ; printed
	rts

;------------------------------------------------------------------------------
; audio_test: the A test.  "Listen for low to high sweep:": channels A, B and C of the sound chip in
; turn sweep from about 100 Hz to 14 kHz (period $4E2 down to 9, volume 12) with the LMC1992 at 0 dB and
; the sound chip mixed in, the channel's name on row 1.  Then the DMA sound test (dma_sound_test), which
; returns straight to the caller, so $28D bit 7 is never set here.  Changes d0-d7, a0-a2, a5, a6.
;------------------------------------------------------------------------------
audio_test:	; from: read_command
	lea	msg_listen_sweep,a5             ; "Listen for low to high sweep:"
	bsr.w	show_status                     ; on the status line
	bsr.w	psg_sound_off                   ; quiet
	move.l	#$4e20,d0                       ; a wait
audio_test_settle:
	dbra	d0,audio_test_settle            ; wait
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$86,d0                         ; treble 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$46,d0                         ; bass 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$1,d0                          ; sound chip mixed with DMA sound
	bsr.w	lmc1992_write                   ; sent
	moveq	#0,d2                           ; channel A first
audio_test_channel:	; from: audio_test_step
	bsr.w	print_channel_name              ; its name
	moveq	#4,d7                           ; period $4E2 (d7 high byte, d6 low)
	moveq	#-30,d6                         ; ($E2)

audio_test_step:	; from: startup_timing_checks
	bsr.w	psg_tone_soft                   ; sound the period
	move.l	#$3e8,d3                        ; a wait
audio_test_step_hold:
	dbra	d3,audio_test_step_hold         ; wait
	movea.l	#psg_volume_registers,a0        ; the volume registers
	move.b	0(a0,d2.w),$ffff8800.w          ; PSG register select, this channel's
	move.b	#$0,$ffff8802.w                 ; PSG write data, off
	subq.b	#1,d6                           ; a higher tone
	bcc.s	audio_test_step_check           ; borrow?
	subq.b	#1,d7                           ; then the high byte
audio_test_step_check:
	tst.w	d7                              ; down to period 9
	bne.s	audio_test_step                 ; not yet
	cmpi.b	#$9,d6                          ; period 9 yet?
	bne.s	audio_test_step                 ; not yet
	addq.b	#1,d2                           ; the next channel
	cmpi.b	#$3,d2                          ; all three?
	blt.s	audio_test_channel              ; not yet
	bsr.w	psg_sound_off                   ; quiet
	bsr.w	dma_sound_test                  ; the DMA sound test (returns to this routine's caller)
	bset	#$7,mode_flags.w                ; (never reached)
	rts

;------------------------------------------------------------------------------
; psg_sound_off: the three sound chip volumes to 0.
;------------------------------------------------------------------------------
psg_sound_off:	; from: low_ram_test, menu_start, keyboard_key_click, audio_test, audio_test_step, sound_quiet
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
	move.b	0(a0,d2.w),(a2)                 ; in the mixer
	movea.l	#psg_period_registers,a0        ; its period registers
	move.b	0(a0,d2.w),d3                   ; the low byte's register
	move.b	d3,(a1)                         ; selected
	move.b	d6,(a2)                         ; low byte
	addq.b	#1,d3                           ; the high byte's register
	move.b	d3,(a1)                         ; selected
	move.b	d7,(a2)                         ; high byte
	movea.l	#psg_volume_registers,a0        ; its volume register
	move.b	0(a0,d2.w),(a1)                 ; selected
	move.b	#$c,(a2)                        ; 12
	rts

;------------------------------------------------------------------------------
; psg_tone_loud: as psg_tone_soft at volume 15.
;  In:  d2 the channel (0-2), d7/d6 the period's high and low bytes.  Changes d3, a0-a2.
;------------------------------------------------------------------------------
psg_tone_loud:	; from: low_ram_test, pass_tone, fail_sweeps
	lea	$ffff8800.w,a1                  ; PSG register select
	lea	$ffff8802.w,a2                  ; PSG write data
	move.b	#$7,(a1)                        ; mixer
	movea.l	#psg_mixer_tone_only,a0         ; only this channel's tone
	move.b	0(a0,d2.w),(a2)                 ; in the mixer
	movea.l	#psg_period_registers,a0        ; its period registers
	move.b	0(a0,d2.w),d3                   ; the low byte's register
	move.b	d3,(a1)                         ; selected
	move.b	d6,(a2)                         ; low byte
	addq.b	#1,d3                           ; the high byte's register
	move.b	d3,(a1)                         ; selected
	move.b	d7,(a2)                         ; high byte
	movea.l	#psg_volume_registers,a0        ; its volume register
	move.b	0(a0,d2.w),(a1)                 ; selected
	move.b	#$f,(a2)                        ; 15
	rts

;------------------------------------------------------------------------------
; print_channel_name: prints "Channel A", "B" or "C" at column 0, row 1, the cursor kept.
;  In:  d2 the channel.  Registers kept.
;------------------------------------------------------------------------------
print_channel_name:	; from: audio_test
	movem.l	d0-d7,-(sp)                     ; registers kept
	lea	psg_channel_names,a6            ; the channel names
	lsl.w	#2,d2                           ; a long index
	movea.l	0(a6,d2.w),a5                   ; the name
	bsr.w	save_cursor                     ; the cursor kept
	moveq	#0,d0                           ; column 0
	moveq	#1,d1                           ; row 1
	bsr.w	set_cursor                      ; the cursor there
	bsr.w	print_string                    ; the name printed
	bsr.w	restore_cursor                  ; the cursor back
	movem.l	(sp)+,d0-d7                     ; registers back
	rts

;------------------------------------------------------------------------------
; dma_sound_test: the DMA sound part of the A test ("Testing DMA sound. Check waveforms with
; oscilloscope.").  The sounds are copied to $40000; each stage plays over and over until a key (Esc
; ends the test):
;  "Mono 1 kHz tone"  48 samples at 50 kHz, the master volume stepped up from -80 dB to 0 dB
;  "Stereo 1 kHz/500 Hz tones"  at 25 kHz, left rising from -40 dB while right falls to -40 dB
;  "Treble attenuation"  the treble stepped from +2 dB down to -10 dB
;  "Bass attenuation"  the bass stepped from 0 dB down to -10 dB, two sounds at 6 and 12 kHz
; The LMC1992 takes the DMA sound only.  A stage that times out prints "DMA sound timed-out" (the treble
; and bass stages do not look).  Then "DONE!" at column 66 of the status line.  The return address is
; taken off the stack into $21A at the start and the end leaves through show_status_at, so it returns
; to the caller's caller; the code that would put it back (dma_sound_test_restore) is never reached,
; and the GPIP 7 interrupt disabled here stays off.  Changes d0-d7, a0, a1, a5, $4EE, $4F2, $21A.
;------------------------------------------------------------------------------
dma_sound_test:	; from: audio_test_step
	move.l	(sp)+,scratch_long.w            ; the return address off the stack
	lea	msg_testing_dma_sound,a5        ; "Testing DMA sound. Check waveforms with oscilloscope."
	bsr.w	show_status                     ; on the status line
	moveq	#15,d0                          ; the GPIP 7 interrupt
	bsr.w	mfp_disable_interrupt           ; off
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$86,d0                         ; treble 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$46,d0                         ; bass 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$2,d0                          ; DMA sound only
	bsr.w	lmc1992_write                   ; sent
	lea	dma_sound_samples,a0            ; the sounds
	movea.l	#$40000,a1                      ; to $40000
	move.w	#$214,d7                        ; $215 words
dma_sound_test_copy:
	move.w	(a0)+,(a1)+                     ; a word
	dbra	d7,dma_sound_test_copy          ; all of them
	clr.w	d0                              ; (not used)
	move.w	#$1,d1                          ; (not used)
	lea	msg_mono_1khz_tone,a5           ; "Mono 1 kHz tone"
	bsr.w	print_string                    ; printed
dma_sound_mono_again:
	clr.w	dma_step.w                      ; from the first volume ($4EE)
dma_sound_mono_step:
	move.w	dma_step.w,d1                   ; this step's offset
	lea	lmc_master_volume_steps,a0      ; the master volumes
	move.w	0(a0,d1.w),d0                   ; this step's
	bsr.w	lmc1992_write                   ; sent
	lea	dma_sound_mono_tone,a1          ; the mono sound
	movea.l	(a1)+,a0                        ; its address
	move.l	(a1)+,d1                        ; frames to play
	move.w	(a1)+,d0                        ; the mode: mono, 50 kHz
	bsr.w	play_dma_sound                  ; play it
	bne.w	dma_sound_test_timeout          ; timed out
	bsr.w	key_waiting                     ; a key?
	tst.w	d0                              ; (d0 not 0: yes)
	bne.s	dma_sound_mono_key              ; yes
	addi.w	#$2,dma_step.w                  ; the next volume
	cmpi.w	#$10,dma_step.w                 ; all 8?
	bne.s	dma_sound_mono_step             ; not yet
	bra.s	dma_sound_mono_again            ; over again
dma_sound_mono_key:
	bsr.w	get_key                         ; the key
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	dma_sound_test_done             ; yes: the end
	lea	msg_stereo_tones,a5             ; "Stereo 1 kHz/500 Hz tones"
	bsr.w	print_string                    ; printed
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write                   ; sent
dma_sound_stereo_again:
	clr.w	dma_step.w                      ; from the first volumes
dma_sound_stereo_step:
	move.w	dma_step.w,d1                   ; this step's offset
	lea	lmc_left_volume_steps,a0        ; the left volumes
	move.w	0(a0,d1.w),d0                   ; this step's
	bsr.w	lmc1992_write                   ; sent
	lea	lmc_right_volume_steps,a0       ; the right volumes
	move.w	0(a0,d1.w),d0                   ; this step's
	bsr.w	lmc1992_write                   ; sent
	lea	dma_sound_stereo_tones,a1       ; the stereo sound
	movea.l	(a1)+,a0                        ; its address
	move.l	(a1)+,d1                        ; frames to play
	move.w	(a1)+,d0                        ; the mode: stereo, 25 kHz
	bsr.w	play_dma_sound                  ; play it
	bne.w	dma_sound_test_timeout          ; timed out
	bsr.w	key_waiting                     ; a key?
	tst.w	d0                              ; (d0 not 0: yes)
	bne.s	dma_sound_stereo_key            ; yes
	addi.w	#$2,dma_step.w                  ; the next volumes
	cmpi.w	#$10,dma_step.w                 ; all 8?
	bne.s	dma_sound_stereo_step           ; not yet
	bra.s	dma_sound_stereo_again          ; over again
dma_sound_stereo_key:
	bsr.w	get_key                         ; the key
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	dma_sound_test_done             ; yes: the end
	lea	msg_treble_attenuation,a5       ; "Treble attenuation"
	bsr.w	print_string                    ; printed
	clr.w	dma_step.w                      ; from the first treble value
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write                   ; sent
dma_sound_test_treble_step:
	lea	lmc_treble_steps,a0             ; the treble values
	move.w	dma_step.w,d1                   ; this step's offset
	move.w	0(a0,d1.w),d0                   ; this step's value
	add.w	#$80,d0                         ; the treble command
	bsr.w	lmc1992_write                   ; sent
	lea	dma_sound_treble_tone,a1        ; the sound
	movea.l	(a1)+,a0                        ; its address
	move.l	(a1)+,d1                        ; frames to play
	move.w	(a1)+,d0                        ; the mode
	bsr.w	play_dma_sound                  ; play it (a timeout is not looked at)
	bsr.w	key_waiting                     ; a key?
	tst.w	d0                              ; (d0 not 0: yes)
	bne.s	dma_sound_treble_key            ; yes
	addi.w	#$2,dma_step.w                  ; the next treble value
	cmpi.w	#$14,dma_step.w                 ; all 10?
	bne.s	dma_sound_test_treble_step      ; not yet
	clr.w	dma_step.w                      ; from the first again
	bra.s	dma_sound_test_treble_step      ; over again
dma_sound_treble_key:
	bsr.w	get_key                         ; the key
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	dma_sound_test_done             ; yes: the end
	lea	msg_bass_attenuation,a5         ; "Bass attenuation"
	bsr.w	print_string                    ; printed
	clr.w	dma_step.w                      ; from the first bass value ($4EE)
	clr.w	dma_bass_sound.w                ; the first sound ($4F2)
dma_sound_test_bass_step:
	lea	lmc_bass_steps,a0               ; the bass values
	move.w	dma_step.w,d1                   ; this step's offset
	move.w	0(a0,d1.w),d0                   ; this step's value
	add.w	#$40,d0                         ; the bass command
	bsr.w	lmc1992_write                   ; sent
	move.w	dma_bass_sound.w,d3             ; the sound's number
	mulu.w	#$a,d3                          ; 10 bytes each
	lea	dma_sound_bass_tones,a1         ; the two bass sounds
	movea.l	0(a1,d3.w),a0                   ; its address
	move.l	4(a1,d3.w),d1                   ; frames to play
	move.w	8(a1,d3.w),d0                   ; the mode
	bsr.w	play_dma_sound                  ; play it (a timeout is not looked at)
	addi.w	#$1,dma_bass_sound.w            ; the next sound
	cmpi.w	#$2,dma_bass_sound.w            ; both played?
	bne.s	dma_sound_test_bass_step        ; no
	clr.w	dma_bass_sound.w                ; the first sound again
	addi.w	#$2,dma_step.w                  ; the next bass value
	cmpi.w	#$14,dma_step.w                 ; all 10?
	bne.s	dma_sound_bass_key              ; no
	clr.w	dma_step.w                      ; from the first again
dma_sound_bass_key:
	bsr.w	key_waiting                     ; a key?
	tst.w	d0                              ; (d0 not 0: yes)
	beq.s	dma_sound_test_bass_step        ; no: on playing
	bsr.w	get_key                         ; the key, which ends the test
dma_sound_test_done:	; from: dma_sound_test_restore
	lea	msg_done,a5                     ; "DONE!"
	moveq	#66,d0                          ; column 66
	moveq	#0,d1                           ; of the status line
	bra.w	show_status_at                  ; printed; the return is to the caller's caller

;------------------------------------------------------------------------------
; dma_sound_test_restore: never reached (see dma_sound_test).
;------------------------------------------------------------------------------
dma_sound_test_restore:
	move.w	#$12c,d1                        ; 300 delays
dma_sound_test_restore_wait:
	bsr.w	delay                           ; a delay
	dbra	d1,dma_sound_test_restore_wait  ; 300 of them
	move.w	#$c0,d0                         ; master volume -80 dB
	bsr.w	lmc1992_write                   ; sent
	moveq	#15,d0                          ; the GPIP 7 interrupt
	bsr.w	mfp_enable_interrupt            ; on again
	move.l	scratch_long.w,-(sp)            ; the return address back
	rts
dma_sound_test_timeout:	; from: dma_sound_test
	lea	msg_dma_sound_timed_out,a5      ; "DMA sound timed-out"
	bsr.w	print_string                    ; printed
	bra.s	dma_sound_test_done             ; the end

;------------------------------------------------------------------------------
; result_sound: after a test, a sound for its result: a red background (a failure) gives the three
; fail_sweeps, anything else the short pass_tone.  Changes d0-d3, d6, d7, a0-a2.
;------------------------------------------------------------------------------
result_sound:	; from: menu_start, menu_run_test_advance, menu_wait_space
	bsr.w	screen_is_red                   ; the background red?
	bne.s	result_sound_pass               ; no: passed
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
	bsr.w	lmc1992_write                   ; sent
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$1,d0                          ; sound chip mixed with DMA sound
	bsr.w	lmc1992_write                   ; sent
	moveq	#0,d2                           ; channel A
	moveq	#4,d7                           ; period $4E2
	moveq	#-30,d6                         ; ($E2)
	bsr.w	psg_tone_loud                   ; sound it
	move.w	#$64,d1                         ; 100 delays
pass_tone_hold:
	bsr.w	delay                           ; a delay
	dbra	d1,pass_tone_hold               ; 100 of them
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
	moveq	#-30,d6                         ; ($E2)
	move.w	#$e8,d0                         ; master volume 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$154,d0                        ; left 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$114,d0                        ; right 0 dB
	bsr.w	lmc1992_write                   ; sent
	move.w	#$1,d0                          ; sound chip mixed with DMA sound
	bsr.w	lmc1992_write                   ; sent
fail_sweeps_step:
	bsr.w	psg_tone_loud                   ; sound the period
	moveq	#100,d3                         ; a wait
fail_sweeps_step_hold:
	dbra	d3,fail_sweeps_step_hold        ; wait
	movea.l	#psg_volume_registers,a0        ; the volume registers
	move.b	0(a0,d2.w),$ffff8800.w          ; PSG register select, this channel's
	move.b	#$0,$ffff8802.w                 ; PSG write data, off
	subq.b	#1,d6                           ; a higher tone
	bcc.s	fail_sweeps_step_check          ; borrow?
	subq.b	#1,d7                           ; then the high byte
fail_sweeps_step_check:
	tst.w	d7                              ; down to period 9
	bne.s	fail_sweeps_step                ; not yet
	cmpi.b	#$9,d6                          ; period 9 yet?
	bne.s	fail_sweeps_step                ; not yet
	addq.b	#1,d2                           ; the next channel
	cmpi.b	#$3,d2                          ; all three?
	blt.s	fail_sweeps_channel             ; not yet
	bsr.w	sound_quiet                     ; quiet
	rts

;------------------------------------------------------------------------------
; sound_quiet: the sound chip volumes off.
;------------------------------------------------------------------------------
sound_quiet:	; from: pass_tone, fail_sweeps
	bsr.w	psg_sound_off                   ; the volumes off
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
	bne.s	microwire_send_wait_data        ; not yet
microwire_send_wait_mask:
	cmpi.w	#$7ff,$ffff8924.w               ; Microwire mask, the mask back?
	bne.s	microwire_send_wait_mask        ; not yet
	rts

;------------------------------------------------------------------------------
; lmc1992_write: sends a command to the LMC1992 (address %10).
;  In:  d0 the function (bits 8-6) and value (bits 5-0).  Changes d0.
;------------------------------------------------------------------------------
lmc1992_write:                                  ; from: low_ram_test, startup_timing_checks, audio_test, dma_sound_test,
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
	movem.l	d0-d7/a0-a6,-(sp)               ; registers kept
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
	cmp.l	d6,d1                           ; more than 256 left?
	bpl.s	play_dma_sound_start            ; yes: 256 first
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
	bra.w	play_dma_sound_exit             ; out
play_dma_sound_more:
	cmp.l	d6,d1                           ; at most a full count
	bpl.s	play_dma_sound_reload           ; yes: 256
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
	movem.l	(sp)+,d0-d7/a0-a6               ; registers back
	rts

;------------------------------------------------------------------------------
; timing_test: the T test, "Testing MFP, Glue timing, Video", also run once at start-up.
;  T0 each of the four MFP timers (/200, data 4) must interrupt and be in service within a wait
;     (check_mfp_timer: the T0 routines clear the bits of $284)
;  T1-T3, ten times over: the VBL (clears $292), the HBL (clears $208) and a timer B event count
;     interrupt (counts $208 down) must each arrive.  Timer A is started as a time-out, but its
;     vector is still the T0 routine, which does not clear $20A, so a missing interrupt hangs the
;     test instead of failing it
;  T4 the video counter follows the screen two lines at a time (timer B every 2 lines adds 2 to
;     $290) at video bases from $1000 up to the end of RAM ($4DA the address expected, $4DE the end)
;  T5/T6 a PSG and a 1772 access, run from RAM at $4000, must not bus error
;  In: $204 the end of RAM, $236 $EA after start-up (then the result is shown).  Out: $49A the error
;  bits (bit 0 T0, 1 T1, 2 T2, 3 T3, 4 T4, 5 T5/T6), the screen at $10000.
;  Changes all registers, $208, $20A, $21A, $284, $285, $290, $292, $4DA, $4DE, the MFP timers and
;  their vectors ($120 left on the default timer B routine).
;------------------------------------------------------------------------------
timing_test:	; from: startup_timing_checks, test_routines
	lea	msg_testing_timing,a5           ; the title
	bsr.w	show_status                     ; on the status line
	bsr.w	delay                           ; a delay
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
	bsr.w	mfp_enable_interrupt            ; on
	moveq	#24,d1                          ; its control register
	move.b	#$7,$18(a0)                     ; running, /200
	bsr.w	check_mfp_timer                 ; checked: T0
	moveq	#13,d0                          ; timer A
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#8,d0                           ; timer B (interrupt 8)
	bsr.w	mfp_enable_interrupt            ; on
	moveq	#26,d1                          ; its control register
	move.b	#$7,$1a(a0)                     ; running, /200
	bsr.w	check_mfp_timer                 ; checked: T0
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#5,d0                           ; timer C (interrupt 5)
	bsr.w	mfp_enable_interrupt            ; on
	moveq	#28,d1                          ; timers C/D control
	move.b	#$70,$1c(a0)                    ; timer C running, /200
	bsr.w	check_mfp_timer                 ; checked: T0
	moveq	#5,d0                           ; timer C
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#4,d0                           ; timer D (interrupt 4)
	bsr.w	mfp_enable_interrupt            ; on
	moveq	#28,d1                          ; timers C/D control
	move.b	#$7,$1c(a0)                     ; timer D running, /200
	bsr.w	check_mfp_timer                 ; checked: T0
	moveq	#4,d0                           ; timer D
	bsr.w	mfp_disable_interrupt           ; off
	bsr.w	rs232_setup                     ; the USART back at the rate chosen (timer D)
	tst.b	test_errors.w                   ; a T0 error?
	beq.s	timing_sync_rounds              ; no
	movea.l	#msg_mfp_timer_error,a5         ; "T0 MFP timer"
	bsr.w	print_string                    ; printed
timing_sync_rounds:
	move.b	#$a,pass_count.w                ; ten rounds ($285)
timing_sync_loop:
	move.b	#$7,d0                          ; timer A /200
	move.b	#$af,d1                         ; 175 counts: 14.2 ms
	bsr.w	start_timer_a                   ; started, $20A set
	move.b	#$1,vbl_flag.w                  ; $292 set: the VBL clears it
	move.w	#$2200,sr                       ; VBL and MFP interrupts on
timing_sync_wait_vbl:
	tst.b	vbl_flag.w                      ; the VBL yet (in step with it)?
	beq.s	timing_vbl_period               ; yes: time the next
	tst.b	timer_a_count.w                 ; time-out flag still set? (nothing clears it here: the routine that
                                                ;   counts it down is not installed)
	bne.s	timing_sync_wait_vbl            ; yes: wait on
timing_vbl_fail:
	movea.l	#msg_vertical_sync_error,a5     ; "T1 Vertical Sync"
	bsr.w	print_string                    ; printed
	bset	#$1,test_errors.w               ; $49A bit 1: T1
	bra.w	timing_sync_next                ; on to the next round
timing_vbl_period:
	clr.b	$fffffa19.w                     ; MFP TACR, timer A stopped
	move.b	#$af,$fffffa1f.w                ; MFP TADR, 175 counts again
	move.b	#$7,$fffffa19.w                 ; MFP TACR, restarted, /200
	move.b	#$1,vbl_flag.w                  ; $292 set again
	move.b	#$1,timer_a_count.w             ; time-out flag
timing_vbl_wait:
	tst.b	vbl_flag.w                      ; the next VBL yet?
	beq.s	timing_hbl_test                 ; yes: T2
	tst.b	timer_a_count.w                 ; time-out?
	bne.s	timing_vbl_wait                 ; no: wait on
	bra.s	timing_vbl_fail                 ; yes: T1 fails
timing_hbl_test:
	move.b	#$8,$fffffa1b.w                 ; MFP TBCR, timer B: event count (display enable)
	move.b	#$1,$fffffa21.w                 ; MFP TBDR, every line
	move.l	#timer_b_count_handler,$120.w   ; MFP timer B, timer B routine: counts $208 down
	bset	#$0,$fffffa13.w                 ; MFP IMRA, timer B unmasked
	move.b	#$1,d0                          ; timer A /4
	move.b	#$f,d1                          ; 15 counts: 24 us
	move.b	#$1,interrupt_events.w          ; the HBL routine clears $208
	bsr.w	start_timer_a                   ; started
	move.w	#$2000,sr                       ; all interrupts on, the HBL too
timing_hbl_wait:
	tst.b	interrupt_events.w              ; the HBL came?
	beq.s	timing_de_test                  ; yes: T3
	tst.b	timer_a_count.w                 ; time-out?
	bne.s	timing_hbl_wait                 ; no: wait on
	movea.l	#msg_horizontal_sync_error,a5   ; "T2 Horizontal Sync"
	bset	#$2,test_errors.w               ; $49A bit 2: T2
timing_sync_print:
	bsr.w	print_string                    ; the error printed
	bra.s	timing_sync_next                ; on to the next round
timing_de_fail:
	movea.l	#msg_display_enable_error,a5    ; "T3 Display Enable"
	bset	#$3,test_errors.w               ; $49A bit 3: T3
	bra.s	timing_sync_print               ; shown
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
	bsr.w	mfp_disable_interrupt           ; off
	moveq	#13,d0                          ; timer A
	bsr.w	mfp_disable_interrupt           ; off
	move.l	#timer_b_handler,$120.w         ; MFP timer B, the default timer B routine back
	subi.b	#$1,pass_count.w                ; one round less
	bne.w	timing_sync_loop                ; ten done?
	lea	$ffff8201.w,a0                  ; video base high, T4: the video base and counter registers
	lea	$ffff8203.w,a1                  ; video base mid
	lea	$ffff8205.w,a2                  ; video count high
	lea	$ffff8207.w,a3                  ; video count mid
	lea	$ffff8209.w,a4                  ; video count low
	move.l	#timing_counter_timer_b,$120.w  ; MFP timer B, timer B routine: two more lines in $292
	move.w	#$2200,sr                       ; VBL and MFP interrupts on
	clr.l	d0                              ; the first table entry
	clr.l	d4                              ; (d4 the counter read)
	btst	#$1,$ffff8260.w                 ; shift mode, high resolution?
	beq.w	timing_colour_line_bytes        ; no
	move.l	#$a0,d5                         ; two mono lines: 160 bytes
	bra.s	timing_counter_next_base        ; on
timing_colour_line_bytes:
	move.l	#$140,d5                        ; two colour lines: 320 bytes
timing_counter_next_base:
	lea	video_counter_test_bases,a6     ; the screen addresses to try, /256
	clr.l	d1                              ; (the high word clear)
	move.w	0(a6,d0.w),d1                   ; the next one
	move.w	d1,d7                           ; (kept)
	lsr.w	#8,d7                           ; its 64K bank
	cmp.b	ram_top+1.w,d7                  ; past the end of RAM?
	bge.w	timing_bus_tests                ; yes: T4 done
	clr.l	counter_end.w                   ; the end cleared ($4DE)
	clr.l	counter_expected.w              ; the address expected cleared ($4DA)
	lsl.l	#8,d1                           ; the screen address
	move.l	d1,counter_expected.w           ; the address expected: the screen's start
	add.l	#$7bc0,d1                       ; the end: 198 colour lines on
	move.l	d1,counter_end.w                ; the end ($4DE)
	move.l	counter_expected.w,d1           ; the screen address
	lsr.l	#8,d1                           ; /256 for the base registers
	move.b	#$1,vbl_flag.w                  ; $292 set: the VBL clears it
timing_counter_wait_vbl:
	tst.b	vbl_flag.w                      ; the VBL yet?
	bne.s	timing_counter_wait_vbl         ; not yet
	move.b	d1,(a1)                         ; base mid
	lsr.w	#8,d1                           ; (the high byte)
	move.b	d1,(a0)                         ; base high
	move.b	#$1,vbl_flag.w                  ; $292 set again
timing_counter_wait_frame:
	tst.b	vbl_flag.w                      ; the next VBL yet?
	bne.s	timing_counter_wait_frame       ; not yet
	clr.w	line_count.w                    ; no lines counted yet
	clr.l	d6                              ; the count seen last
	move.b	#$2,$fffffa21.w                 ; MFP TBDR, timer B every two lines
	move.b	#$8,$fffffa1b.w                 ; MFP TBCR, event count
	bset	#$0,$fffffa13.w                 ; MFP IMRA, timer B unmasked
	bset	#$0,$fffffa07.w                 ; MFP IERA, and enabled
timing_counter_wait_line:
	clr.l	d4                              ; the counter built in d4
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
	move.w	line_count.w,d6
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
	lea	msg_video_counter_error,a5      ; "T4 Video Counter in Memory Controller"
	bsr.w	print_string
	bset	#$4,test_errors.w               ; error bit 4: T4
timing_bus_tests:
	move.w	#$2400,sr                       ; the HBL off
	moveq	#8,d0                           ; timer B
	bsr.w	mfp_disable_interrupt
	move.b	#$1,(a0)                        ; the screen back at $10000
	move.b	#$0,(a1)
	movea.l	$8.w,a4                         ; the bus error vector kept
	move.l	#bus_error_caught,$8.w          ; bus error vector, a bus error sets d7 and goes on
	lea	msg_psg_bus_test,a5             ; "T5 PSG Bus Test", shown on a bus error
	lea	psg_bus_test_code,a1            ; its code
	move.l	#$e,d0                          ; 15 bytes of it
	bsr.w	run_bus_test_in_ram
	lea	msg_1772_bus_test,a5            ; "T6 1772 Bus Test"
	lea	fdc_bus_test_code,a1            ; its code
	move.l	#$1c,d0                         ; 29 bytes of it
	bsr.w	run_bus_test_in_ram
	move.l	a4,$8.w                         ; the bus error vector back
	tst.b	test_errors.w                   ; a T test failed?
	bne.s	timing_test_failed              ; yes
	cmpi.b	#$ea,startup_checks_done.w      ; the start-up checks over ($EA)?
	bne.w	timing_test_done                ; no: the start-up run shows failures only
	lea	msg_pass,a5                     ; "Pass"
	bra.s	timing_test_show                ; shown
timing_test_failed:
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
timing_test_show:
	bsr.w	show_result                     ; the result shown
timing_test_done:
	bset	#$6,$fffffa15.w                 ; MFP IMRB, the ACIA interrupt unmasked
	rts

;------------------------------------------------------------------------------
; run_bus_test_in_ram: copies a short test routine to $4000 and runs it there; the bus error vector must
;  already set d7.  In: a1 the routine, d0 its length - 1, a5 the text shown if it bus errors.
;  Out: d7 -1 after a bus error, then the text shown and $49A bit 5 set.  Changes d0, d7, a0, a1.
;------------------------------------------------------------------------------
run_bus_test_in_ram:	; from: timing_test
	movea.l	#$4000,a0                       ; at $4000
	bsr.w	copy_bytes
	clr.l	d7                              ; no bus error yet
	movea.l	#$4000,a0
	jsr	(a0)                            ; run
	tst.w	d7                              ; a bus error?
	beq.w	run_bus_test_in_ram_done        ; no
	bsr.w	print_string                    ; the test's name shown
	bset	#$5,test_errors.w               ; error bit 5: T5/T6
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
; timing_counter_timer_b: the timer B routine of T4 (timer B counts every second display line): two
;  more lines counted in $290.
;------------------------------------------------------------------------------
timing_counter_timer_b:	; from: timing_test
	addi.w	#$2,line_count.w                ; two more lines
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, timer B served
	rte

;------------------------------------------------------------------------------
; check_mfp_timer: waits while an MFP timer runs and checks that its interrupt came (the T0 timer routines
;  clear $284 bit 0 always, bit 1 when the timer's in-service bit was set), then stops the timer.
;  In: a0 $FFFFFA01, d1 the offset of its control register (24 A, 26 B, 28 C/D), the timer started.
;  Out: $49A bit 0 set on an error.  Changes d2.
;------------------------------------------------------------------------------
check_mfp_timer:	; from: timing_test
	moveq	#-41,d2                         ; 65496 loops
	move.b	#$3,timer_irq_flags.w           ; $284 bits 0 and 1 set: the timer routine clears them
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
;  Changes all registers, $49A, $4F4-$4FB, $770, the RAM tested.
;------------------------------------------------------------------------------
dma_port_test:	; from: test_routines
	movea.l	#msg_dma_port_test,a5           ; the title
	bsr.w	show_status
	move.w	#$80,$ffff8606.w                ; DMA mode / status, FDC status
	nop
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, read: its interrupt cleared
	move.b	#$e,$ffff8800.w                 ; PSG port A
	move.b	#$27,$ffff8802.w                ; PSG write data, floppies deselected
	movea.l	dma_port_test_addresses,a3      ; the first address, $1000
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
	move.b	dma_table_index.w,d0            ; the table offset
	lea	dma_port_test_addresses,a2      ; the addresses to test
	movea.l	0(a2,d0.w),a3                   ; this one
	cmpa.l	ram_top.w,a3                    ; past the end of RAM?
	bge.s	dma_port_pass                   ; yes: all done
	move.l	a3,dma_test_address.w
	movea.l	a3,a4                           ; four blocks on
	adda.l	#$800,a4
dma_port_fill_block:
	move.w	a3,d0                           ; each word its address
	move.w	d0,(a3)+
	cmpa.l	a3,a4                           ; filled?
	bne.s	dma_port_fill_block
	move.w	#$4,dma_block_count.w           ; four blocks
	move.b	#$10,dma_command.w              ; command $10: written out
	bsr.w	acsi_loopback_transfer          ; sent
	tst.b	test_errors.w                   ; an error?
	bne.s	dma_port_fail                   ; yes
	addi.l	#$800,dma_test_address          ; read back 2K higher
	move.b	#$8,dma_command.w               ; command $08: read back
	bsr.w	acsi_loopback_transfer          ; sent
	tst.b	test_errors.w                   ; an error?
	bne.s	dma_port_fail                   ; yes
	bsr.w	compare_dma_blocks              ; compared
	btst	#$7,test_errors.w               ; mismatch?
	bne.s	dma_port_fail                   ; yes
	addi.b	#$4,dma_table_index.w           ; the next address
	cmpi.b	#$4c,dma_table_index.w          ; all 19 done?
	bne.s	dma_port_next_block             ; no
dma_port_pass:
	movea.l	#msg_pass,a5                    ; "Pass"
dma_port_show:
	bsr.w	show_result                     ; the result shown
	rts
dma_port_fail:
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
	bra.s	dma_port_show

;------------------------------------------------------------------------------
; acsi_loopback_transfer: one DMA transfer through the loopback device: the DMA address from $4F7-$4F9,
;  the sector count $4F4, and a command byte (count - 1 in bits 6-7, the command $4FA) sent as the
;  first ACSI byte; command $08 reads from the port, any other writes to it.  Waits for GPIP5, then
;  checks the DMA address reached and the DMA status.  Out: $49A bit 0 time-out (D0), bit 1 count (D1),
;  bit 2 status (D3).  Changes d0-d2, a0, a1, $770.
;------------------------------------------------------------------------------
acsi_loopback_transfer:	; from: dma_port_test
	clr.b	test_errors.w                   ; no errors yet
	move.b	dma_test_address+3.w,$ffff860d.w ; DMA base low
	move.b	dma_test_address+2.w,$ffff860b.w ; DMA base mid
	move.b	dma_test_address+1.w,$ffff8609.w ; DMA base high
	move.w	dma_block_count.w,d0            ; the block count
	subq.w	#1,d0                           ; minus one
	lsl.b	#6,d0                           ; in bits 6-7
	or.b	dma_command.w,d0                ; with the command
	lea	$ffff8606.w,a0                  ; DMA mode
	lea	$ffff8604.w,a1                  ; DMA data
	cmpi.b	#$8,dma_command.w               ; reading back?
	bne.s	acsi_loopback_write             ; no: write out
	move.w	#$190,(a0)                      ; FIFO cleared, read direction
	move.w	#$90,(a0)                       ; sector count register
	nop
	move.w	dma_block_count.w,(a1)
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
	move.w	dma_block_count.w,(a1)
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
	move.w	dma_block_count.w,d0
	mulu.w	#$200,d0                        ; *512
	add.l	dma_test_address.w,d0
	clr.l	dma_address_read.w
	move.b	$ffff860d.w,dma_address_read+3.w ; DMA base low
	move.b	$ffff860b.w,dma_address_read+2.w ; DMA base mid
	move.b	$ffff8609.w,dma_address_read+1.w ; DMA base high
	cmp.l	dma_address_read,d0
	beq.s	acsi_loopback_check_status      ; yes
	bset	#$1,test_errors.w
	movea.l	#msg_dma_count_error,a5         ; "D1 DMA count error"
	bsr.w	print_string
acsi_loopback_check_status:
	move.w	(a0),d0                         ; the DMA status
	andi.w	#$7,d0                          ; its three bits
	cmpi.w	#$1,d0                          ; no error only?
	beq.s	acsi_loopback_done              ; yes
	bset	#$2,test_errors.w
	lea	msg_dma_not_responding,a5       ; "D3 DMA not responding"
	bsr.w	print_string
acsi_loopback_done:
	move.w	#$88,(a0)                       ; ACSI register
	nop
	move.w	(a1),d1                         ; read: the interrupt cleared
	rts
acsi_loopback_timeout:
	bset	#$0,test_errors.w               ; error bit 0: D0
	movea.l	#msg_dma_time_out,a5            ; "D0 DMA time-out"
	bsr.w	print_string
	bra.s	acsi_loopback_done              ; the port released

;------------------------------------------------------------------------------
; compare_dma_blocks: compares the blocks read back at $4F6 with those written 2K lower.
;  Out: $49A bit 7 and "D2 DMA data mismatch" at the first difference.  Changes d0, a0-a2.
;------------------------------------------------------------------------------
compare_dma_blocks:	; from: dma_port_test
	movea.l	dma_test_address.w,a0           ; the blocks read back
	movea.l	a0,a1                           ; those written
	suba.l	#$800,a1
	moveq	#0,d0                           ; the length
	move.w	dma_block_count.w,d0
	mulu.w	#$200,d0                        ; *512
	movea.l	a0,a2                           ; the end
	adda.l	d0,a2                           ; of the blocks read back
compare_dma_blocks_loop:
	cmpm.b	(a0)+,(a1)+                     ; the same?
	bne.s	compare_dma_blocks_fail         ; no
	cmpa.l	a0,a2                           ; all of them?
	bne.s	compare_dma_blocks_loop         ; no
	rts
compare_dma_blocks_fail:
	bset	#$7,test_errors.w               ; error bit 7: D2
	movea.l	#msg_dma_data_mismatch,a5       ; "D2 DMA data mismatch"
	bsr.w	print_string
	rts

;------------------------------------------------------------------------------
; printer_joystick_test: the P test, "Printer/Joystick Port test", with loopback plugs on the printer and
;  joystick ports.  P0 each printer data bit is strobed out and must read back the same; P1 data bit 7
;  must show inverted on BUSY (GPIP0); then through the keyboard processor (joystick interrogation)
;  data bits 7/6 must show as the fire buttons (J3/J4) and $F8-$FF as the joystick directions ($01-$80
;  wanted, J0 port 0 low nibble, J1 port 1 high nibble); J2 when the keyboard processor does not answer.
;  Then, unless GPIP7 is low (monochrome monitor), the STE enhanced joystick ports through the plug:
;  J5 the outputs at $FF9203 and inputs at $FF9202, J6 the fire buttons at $FF9201, J7 the four
;  paddles high and low, J8 three light gun positions.  Out: error bytes $49A-$4A2, the result shown.
;  Changes all registers, PSG registers 7, 14, 15.
;------------------------------------------------------------------------------
printer_joystick_test:	; from: test_routines
	movea.l	#msg_printer_joystick_test,a5   ; the title
	bsr.w	show_status
	lea	test_errors.w,a0                ; the error bytes $49A-$4A2
	moveq	#8,d7                           ; 9 of them
printer_joystick_clear_errors:
	clr.b	(a0)+                           ; cleared
	dbra	d7,printer_joystick_clear_errors
	move.w	#$2700,sr                       ; no interrupts
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
	bsr.w	printer_strobe_readback
	move.b	#$f,(a1)                        ; port B
	move.b	(a1),d1                         ; read back
	cmp.b	d0,d1                           ; the same?
	beq.s	printer_data_next               ; yes
	or.b	d0,test_errors.w                ; this data bit failed
printer_data_next:
	lsl.b	#1,d0                           ; the next bit
	bne.s	printer_data_loop               ; eight done?
	move.b	#$80,d0                         ; data bit 7 set
	bsr.w	printer_send_busy_bit
	btst	#$0,$fffffa01.w                 ; MFP GPIP, BUSY high?
	beq.s	printer_busy_low                ; no
	bset	#$0,test_errors_high.w          ; error: BUSY high with bit 7 set
printer_busy_low:
	move.b	#$0,d0                          ; data bit 7 clear
	bsr.w	printer_send_busy_bit
	btst	#$0,$fffffa01.w                 ; MFP GPIP, BUSY high?
	bne.s	joystick_port_tests             ; yes: right
	bset	#$1,test_errors_high.w          ; error: BUSY low with bit 7 clear
joystick_port_tests:
	move.w	#$2400,sr                       ; interrupts on: the keyboard processor answers
	moveq	#21,d1                          ; $15: joystick interrogation mode
	bsr.w	ikbd_send
	bne.w	joystick_timeout                ; not taken: J2
	move.b	#$7,(a1)                        ; PSG mixer
	move.b	#$c0,(a0)                       ; ports A and B output
	move.b	#$e,(a1)                        ; port A
	move.b	#$27,(a0)                       ; floppies deselected, strobe high
	move.b	#$f,(a1)                        ; port B
	move.b	#$80,(a0)                       ; data bit 7
	bsr.w	read_joysticks
	beq.w	joystick_timeout                ; no answer: J2
	btst	#$7,d0                          ; fire on joystick 1?
	bne.s	joystick_fire_zero              ; yes
	bset	#$0,test_errors_extra.w         ; error: J3
joystick_fire_zero:
	move.b	#$40,(a0)                       ; data bit 6
	bsr.w	read_joysticks
	beq.w	joystick_timeout                ; no answer: J2
	btst	#$7,d1                          ; fire on joystick 0?
	bne.s	joystick_directions_start       ; yes
	bset	#$1,test_errors_extra.w         ; error: J4
joystick_directions_start:
	moveq	#0,d2                           ; the first of eight
	movea.l	#joystick_bytes_sent,a2         ; the bytes sent
	movea.l	#joystick_bytes_wanted,a3       ; the bytes wanted back
joystick_directions_loop:
	move.b	0(a2,d2.w),d1                   ; this byte
	move.b	#$f,(a1)
	move.b	d1,(a0)                         ; out
	bsr.w	read_joysticks
	beq.w	joystick_timeout                ; no answer: J2
	andi.b	#$f,d0                          ; joystick 1 directions
	lsl.b	#4,d1                           ; joystick 0 directions
	or.b	d1,d0                           ; the high nibble
	cmp.b	0(a3,d2.w),d0                   ; as wanted?
	beq.s	joystick_directions_next        ; yes
	bset	d0,test_errors_last.w           ; error: the bit of the value read
joystick_directions_next:
	addq.w	#1,d2                           ; the next
	cmpi.b	#$8,d2                          ; eight done?
	bne.s	joystick_directions_loop
	move.b	#$c0,(a0)                       ; data back to $C0
	move.b	#$1a,d1                         ; $1A: joysticks off
	bsr.w	ikbd_send
	move.w	#$12c,d0                        ; a pause
printer_joystick_pause:
	bsr.w	delay
	dbra	d0,printer_joystick_pause       ; of 301 delays
	clr.w	6(a0)                           ; a0 is the PSG data register here: these clear $FFFF8808
	clr.w	8(a0)                           ; and $FFFF880A (PSG mirrors), not the keyboard buffer pointers
	tst.b	test_errors.w                   ; printer data errors?
	beq.s	printer_busy_report             ; no
	movea.l	#msg_printer_port_error,a5      ; "P0 Printer port error "
	bsr.w	print_string
	moveq	#7,d0                           ; from bit 7
printer_error_bits:
	move.b	#$30,d1                         ; '0'
	btst	d0,test_errors.w
	beq.s	printer_error_bit_show          ; no
	move.b	#$31,d1                         ; '1'
printer_error_bit_show:
	bsr.w	put_char
	lsr.b	#1,d0                           ; the next bit: halved, so only bits 7, 3 and 1 are shown
	bne.s	printer_error_bits              ; done?
	bsr.w	print_newline
printer_busy_report:
	tst.b	test_errors_high.w              ; BUSY errors?
	beq.s	joystick_left_button_report     ; no
	movea.l	#msg_busy_line_error,a5         ; "P1 Busy line error"
	bsr.w	print_string
joystick_left_button_report:
	btst	#$0,test_errors_extra.w         ; J3 error?
	beq.s	joystick_right_button_report    ; no
	movea.l	#msg_left_button_line_error,a5  ; "J3 Left button line error"
	bsr.w	print_string
joystick_right_button_report:
	btst	#$1,test_errors_extra.w         ; J4 error?
	beq.s	joystick_port_0_report          ; no
	movea.l	#msg_right_button_line_error,a5 ; "J4 Right button line error"
	bsr.w	print_string
joystick_port_0_report:
	move.b	test_errors_last.w,d0
	andi.b	#$f,d0                          ; port 0's?
	beq.s	joystick_port_1_report          ; none
	movea.l	#msg_joystick_port_0_error,a5   ; "J0 Joystick Port 0 error"
	bsr.w	print_string
joystick_port_1_report:
	move.b	test_errors_last.w,d0
	andi.b	#$f0,d0                         ; port 1's?
	beq.s	ste_joypad_tests                ; none
	movea.l	#msg_joystick_port_1_error,a5   ; "J1 Joystick Port 1 error"
	bsr.w	print_string
	bra.s	ste_joypad_tests                ; on to the STE ports
joystick_timeout:
	movea.l	#msg_joystick_time_out,a5       ; "J2 Joystick time-out"
	bsr.w	print_string
	bset	#$7,test_errors_extra.w         ; bit 7: J2
ste_joypad_tests:
	lea	$fffffa01.w,a0                  ; MFP GPIP
	btst	#$7,0(a0)                       ; GPIP7 low (monochrome monitor)?
	beq.w	printer_joystick_pass           ; yes: the STE port tests skipped
	lea	$ffff8802.w,a1                  ; PSG write data
	lea	$ffff8800.w,a2                  ; PSG register select
	move.b	#$7,(a2)                        ; PSG mixer
	move.b	#$c0,(a1)                       ; ports A and B output
	move.b	#$f,(a2)                        ; port B
	move.b	#$0,(a1)                        ; the plug's control lines low
	moveq	#1,d0                           ; output bit 0 first
joypad_output_loop:
	move.b	d0,$ff9203                      ; the bit on the joypad outputs
	move.b	#$f,(a2)                        ; port B
	move.b	#$2,(a1)                        ; printer data bit 1 high
	nop
	move.b	#$0,(a1)                        ; and low: the plug clocked
	move.b	$ff9203,d1                      ; read (not used)
	move.b	#$f,(a2)                        ; port B
	move.b	#$1,(a1)                        ; printer data bit 0 high
	nop
	move.b	$ff9203,d1                      ; the outputs read back
	move.b	#$f,(a2)                        ; port B
	move.b	#$0,(a1)                        ; bit 0 low
	cmp.b	d0,d1                           ; the same?
	beq.s	joypad_output_next              ; yes
	eor.b	d0,d1                           ; the bits wrong
	or.b	d1,joypad_output_errors.w       ; J5 output errors
joypad_output_next:
	lsl.w	#1,d0                           ; the next bit
	cmp.w	#$100,d0                        ; eight done?
	blt.s	joypad_output_loop
	move.w	#$1,d0                          ; output bit 0 first
joypad_input_loop:
	move.b	d0,$ff9203                      ; the bit on the joypad outputs
	move.b	#$f,(a2)                        ; port B
	move.b	#$2,(a1)                        ; printer data bit 1 high
	nop
	move.b	#$0,(a1)                        ; and low: the plug clocked
	move.b	$ff9203,d1                      ; read (not used)
	move.b	#$f,(a2)                        ; port B
	move.b	#$4,(a1)                        ; printer data bit 2 high
	nop
	move.b	$ff9202,d1                      ; joypad directions, the joypad inputs read
	move.b	#$f,(a2)                        ; port B
	move.b	#$0,(a1)                        ; bit 2 low
	cmp.b	d0,d1                           ; as sent?
	beq.s	joypad_input_next               ; yes
	eor.b	d0,d1                           ; the bits wrong
	or.b	d1,joypad_input_errors.w        ; J5 input errors
joypad_input_next:
	lsl.w	#1,d0                           ; the next bit
	cmp.w	#$100,d0                        ; eight done?
	blt.s	joypad_input_loop
	tst.w	joypad_output_errors.w          ; J5 errors?
	beq.s	joypad_fire_tests               ; none
	lea	msg_aux_joystick_direction,a5   ; "J5 Aux joystick direction "
	bsr.w	print_string
	move.w	joypad_output_errors.w,d1       ; the error bits
	bsr.w	print_hex_word                  ; in hex
	bsr.w	print_newline
joypad_fire_tests:
	lea	$ff9201,a0                      ; the fire buttons ($FF9201)
	move.b	#$fe,d0                         ; select line 0 low first
joypad_fire_loop:
	move.b	d0,2(a0)                        ; onto the outputs ($FF9203)
	nop
	move.b	(a0),d1                         ; the fire inputs
	not.b	d1                              ; inverted
	or.b	#$f0,d1                         ; the top nibble set
	cmp.b	d0,d1                           ; the pattern sent?
	beq.s	joypad_fire_next                ; yes
	eor.b	d0,d1                           ; the bits wrong
	or.b	d1,joypad_fire_errors.w         ; J6 errors
joypad_fire_next:
	rol.b	#1,d0                           ; the next line low
	cmp.b	#$ef,d0                         ; four done?
	bne.s	joypad_fire_loop
	cmpi.b	#$0,joypad_fire_errors.w        ; J6 errors?
	beq.s	paddle_tests                    ; none
	lea	msg_aux_fire_button,a5          ; "J6 Aux fire button "
	bsr.w	print_string
	move.b	joypad_fire_errors.w,d1         ; the error bits
	bsr.w	print_hex_byte                  ; in hex
	bsr.w	print_newline
paddle_tests:
	lea	$ff9211,a0                      ; paddle 0 X ($FF9211)
	lea	$ff9203,a1                      ; the joypad outputs
	lea	$ffff8800.w,a2                  ; PSG register select
	lea	$ffff8802.w,a3                  ; PSG write data
	move.b	#$ff,(a1)                       ; outputs all high
	move.b	#$f,(a2)                        ; port B
	move.b	#$0,(a3)                        ; printer data 0
	clr.w	d6                              ; no errors yet
	bsr.w	read_paddles                    ; the four paddles read
	move.b	#$80,d7                         ; each must be above $80
	cmp.b	d7,d0                           ; paddle 0 X
	bhi.s	paddle_high_check_0y            ; above: right
	bset	#$0,d6                          ; error bit 0
paddle_high_check_0y:
	cmp.b	d7,d1                           ; paddle 0 Y
	bhi.s	paddle_high_check_1x
	bset	#$1,d6                          ; error bit 1
paddle_high_check_1x:
	cmp.b	d7,d2                           ; paddle 1 X
	bhi.s	paddle_high_check_1y
	bset	#$2,d6                          ; error bit 2
paddle_high_check_1y:
	cmp.b	d7,d3                           ; paddle 1 Y
	bhi.s	paddle_low_tests
	bset	#$3,d6                          ; error bit 3
paddle_low_tests:
	move.b	#$0,(a1)                        ; outputs all low
	move.b	#$f,(a2)                        ; port B
	move.b	#$2,(a3)                        ; printer data bit 1
	bsr.w	read_paddles                    ; read again
	move.b	#$10,d7                         ; each must be $10 or less
	cmp.b	d7,d0                           ; paddle 0 X
	bls.s	paddle_low_check_0y             ; right
	bset	#$4,d6                          ; error bit 4
paddle_low_check_0y:
	cmp.b	d7,d1                           ; paddle 0 Y
	bls.s	paddle_low_check_1x
	bset	#$5,d6                          ; error bit 5
paddle_low_check_1x:
	cmp.b	d7,d2                           ; paddle 1 X
	bls.s	paddle_low_check_1y
	bset	#$6,d6                          ; error bit 6
paddle_low_check_1y:
	cmp.b	d7,d3                           ; paddle 1 Y
	bls.s	paddle_errors_store
	bset	#$7,d6                          ; error bit 7
paddle_errors_store:
	move.b	d6,paddle_errors.w              ; J7 errors kept
	beq.s	light_gun_test                  ; none
	lea	msg_paddle,a5                   ; "J7 Paddle "
	bsr.w	print_string
	move.b	paddle_errors.w,d1              ; the error bits
	bsr.w	print_hex_byte                  ; in hex
	bsr.w	print_newline
light_gun_test:
	bsr.w	read_light_gun                  ; three light gun positions
	cmp.w	#$8,d0                          ; X at the top: 8 or less?
	bhi.w	light_gun_fail
	cmp.w	#$0,d1                          ; Y 0?
	bne.w	light_gun_fail
	cmp.w	#$138,d2                        ; X one line on: above $138?
	bls.w	light_gun_fail
	cmp.w	#$0,d3                          ; Y still 0?
	bne.w	light_gun_fail
	cmp.w	#$120,d4                        ; X near the end: above $120?
	bls.w	light_gun_fail
	cmp.w	#$c7,d5                         ; Y 199?
	bne.w	light_gun_fail
	bra.s	printer_joystick_pass           ; all right
light_gun_fail:
	lea	msg_light_gun,a5                ; "J8 Light gun "
	bsr.w	print_string
	bsr.w	print_light_gun_values          ; the six values
	move.b	#$1,light_gun_error.w           ; J8 error
printer_joystick_pass:
	movea.l	#msg_pass,a5                    ; "Pass" unless an error byte is set
printer_report_result:
	moveq	#0,d0                           ; any error at all?
	or.b	test_errors.w,d0
	or.b	test_errors_high.w,d0
	or.b	test_errors_extra.w,d0
	or.b	test_errors_last.w,d0
	or.b	joypad_output_errors.w,d0
	or.b	joypad_input_errors.w,d0
	or.b	joypad_fire_errors.w,d0
	or.b	paddle_errors.w,d0
	or.b	light_gun_error.w,d0
	beq.s	printer_joystick_show           ; none
printer_joystick_fail:
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	movea.l	#msg_fail_at_cycle,a5           ; "Fail at cycle:"
printer_joystick_show:
	bsr.w	show_result                     ; the result shown
	rts

;------------------------------------------------------------------------------
; unused_vbl_clear_count: a VBL routine that clears $4F0; nothing installs it.
;------------------------------------------------------------------------------
unused_vbl_clear_count:
	clr.w	unused_line_count.w             ; line count cleared
	rte

;------------------------------------------------------------------------------
; unused_timer_b_count: a timer B routine that counts $4F0 up; nothing installs it.
;------------------------------------------------------------------------------
unused_timer_b_count:
	addi.w	#$1,unused_line_count.w         ; one more
	bclr	#$0,$fffffa0f.w                 ; MFP ISRA, timer B served
	rte

;------------------------------------------------------------------------------
; read_light_gun: latches the light gun position three times through the test plug (joypad output bit 0
;  pulsed high): at the start of the display, about one line (160 bytes) later and $7C4E bytes
;  later, each when the video counter reaches that address.  Out: d0/d1 the first X/Y, d2/d3 the
;  second, d4/d5 the third, each 10 bits.  Changes d6, d7, a0, a5.
;------------------------------------------------------------------------------
read_light_gun:	; from: printer_joystick_test
	move.b	$ffff8203.w,d7                  ; video base mid, the screen base mid
read_light_gun_wait_mid:
	move.b	$ffff8207.w,d6                  ; video count mid, the counter mid
	cmp.b	d6,d7                           ; the same?
	bne.s	read_light_gun_wait_mid
	lsl.w	#8,d7                           ; mid in the high byte
	move.b	$ffff820d.w,d7                  ; video base low, the base low below it
read_light_gun_wait_start:
	move.b	$ffff8209.w,d6                  ; video count low, the counter low
	cmp.b	d6,d7                           ; the display start reached?
	bne.s	read_light_gun_wait_start
	move.b	#$1,$ff9203                     ; output bit 0 high: the plug fires the light gun input
	move.w	$ff9220,d0                      ; light pen X
	move.w	$ff9222,d1                      ; light pen Y
	move.b	#$0,$ff9203                     ; output low
	add.w	#$a0,d7                         ; 160 bytes on
read_light_gun_wait_line:
	move.b	$ffff8209.w,d6                  ; video count low
	cmp.b	d6,d7                           ; reached? (low byte only)
	bne.s	read_light_gun_wait_line        ; no
	move.b	#$1,$ff9203                     ; fired again
	move.w	$ff9220,d2                      ; X
	move.w	$ff9222,d3                      ; Y
	move.b	#$0,$ff9203                     ; output low
	add.w	#$7c4e,d7                       ; $7C4E bytes on: near the end of the screen
	move.w	d7,d5                           ; its mid byte
	lsr.w	#8,d5
read_light_gun_wait_end_mid:
	move.b	$ffff8207.w,d6                  ; video count mid
	cmp.b	d6,d5                           ; reached?
	bne.s	read_light_gun_wait_end_mid     ; no
	lsl.w	#8,d6                           ; mid in the high byte
	lea	$ffff8209.w,a0                  ; video count low, the counter low
	movea.l	#$8,a5                          ; an address for a dummy read
read_light_gun_wait_end:
	move.b	(a5),d6                         ; a dummy read
	move.b	(a0),d6                         ; the counter low
	cmp.w	d6,d7                           ; reached?
	bhi.s	read_light_gun_wait_end         ; no
	move.b	#$1,$ff9203                     ; fired a third time
	move.w	$ff9220,d4                      ; X
	move.w	$ff9222,d5                      ; Y
	move.b	#$0,$ff9203                     ; output low
	move.w	#$3ff,d7                        ; 10 bits each
	and.w	d7,d0
	and.w	d7,d1
	and.w	d7,d2
	and.w	d7,d3
	and.w	d7,d4
	and.w	d7,d5
	rts

;------------------------------------------------------------------------------
; print_light_gun_values: prints d0-d5 (the three light gun X/Y pairs) as hex words with spaces, then
;  a new line.  Changes d1.
;------------------------------------------------------------------------------
print_light_gun_values:	; from: printer_joystick_test
	move.w	d1,-(sp)                        ; Y kept
	move.w	d0,d1                           ; first X
	bsr.w	print_hex_word
	bsr.w	print_space
	move.w	(sp)+,d1                        ; first Y
	bsr.w	print_hex_word
	bsr.w	print_space
	move.w	d2,d1                           ; second X
	bsr.w	print_hex_word
	bsr.w	print_space
	move.w	d3,d1                           ; second Y
	bsr.w	print_hex_word
	bsr.w	print_space
	move.w	d4,d1                           ; third X
	bsr.w	print_hex_word
	bsr.w	print_space
	move.w	d5,d1                           ; third Y
	bsr.w	print_hex_word
	bsr.w	print_newline
	rts

;------------------------------------------------------------------------------
; read_paddles: waits, then reads the four STE paddle positions.  In: a0 $FF9211.
;  Out: d0 paddle 0 X, d1 paddle 0 Y, d2 paddle 1 X, d3 paddle 1 Y.
;------------------------------------------------------------------------------
read_paddles:	; from: printer_joystick_test
	bsr.w	delay                           ; let the paddles settle
	move.b	(a0),d0                         ; paddle 0 X
	move.b	2(a0),d1                        ; paddle 0 Y
	move.b	4(a0),d2                        ; paddle 1 X
	move.b	6(a0),d3                        ; paddle 1 Y
	rts

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
;  keyboard routine puts at $234/$235.  Out: d0 joystick 1, d1 joystick 0, Z set when nothing came
;  (or the command was not taken).  Changes d0, d1.
;------------------------------------------------------------------------------
read_joysticks:	; from: printer_joystick_test
	move.w	#$2710,d0                       ; a pause
	move.w	#$ffff,ikbd_data_first.w        ; nothing yet
read_joysticks_delay:
	dbra	d0,read_joysticks_delay
	moveq	#22,d1                          ; $16: interrogate joysticks
	bsr.w	ikbd_send
	bne.s	read_joysticks_check            ; time-out
	move.w	#$2710,d0                       ; a pause for the answer
read_joysticks_wait:
	dbra	d0,read_joysticks_wait
	move.b	ikbd_data_second.w,d0           ; joystick 1
	move.b	ikbd_data_first.w,d1            ; joystick 0
read_joysticks_check:
	cmpi.w	#$ffff,ikbd_data_first.w        ; still nothing?
	rts

;------------------------------------------------------------------------------
; mono_monitor_test: the H test.  Asks for a monochrome monitor, waits until GPIP7 says one is
;  connected (ESC returns), then shows a stripe pattern at $20000 and flashes the background while
;  waiting: started in high resolution, for a key; else until the monitor is taken off again.
;  GPIP7 meanwhile switches to high resolution (the interrupt routine installed here); at the end the
;  default mono detect routine (a restart) is back.  Out: $28D bit 7 set unless bit 4.
;  Changes d0, a0, the screen at $20000, $4A6, $4A8, $21A.
;------------------------------------------------------------------------------
mono_monitor_test:	; from: read_command
	moveq	#15,d0                          ; interrupt 15: GPIP7
	movea.l	#high_res_switch_handler,a2     ; the high resolution switch
	bsr.w	mfp_install_handler
	movea.l	#msg_connect_mono_monitor,a5    ; "Connect monochrome monitor"
	bsr.w	show_status
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	andi.b	#$3,d0
	move.b	d0,saved_resolution.w           ; kept
	move.w	$ffff8240.w,d0                  ; palette 0, the background colour
	andi.w	#$777,d0
	move.w	d0,saved_colour0.w              ; kept
mono_monitor_wait:
	btst	#$7,$fffffa01.w                 ; MFP GPIP, a mono monitor?
	beq.s	mono_monitor_pattern            ; yes
	bsr.w	key_waiting
	tst.w	d0                              ; a key?
	beq.s	mono_monitor_wait               ; no
	bsr.w	get_key
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
	cmpi.b	#$2,saved_resolution.w
	bne.s	mono_monitor_wait_unplug        ; no
	bsr.w	get_key
	move.w	#$2700,sr                       ; no interrupts
	move.b	#$1,$ffff8201.w                 ; video base high, the screen at $10000
	bne.s	mono_monitor_restore            ; (always taken)
mono_monitor_wait_unplug:
	btst	#$7,$fffffa01.w                 ; MFP GPIP, the monitor taken off?
	beq.s	mono_monitor_wait_unplug        ; no
	move.w	#$2700,sr                       ; no interrupts
	bsr.w	delay
	move.b	saved_resolution.w,$ffff8260.w  ; shift mode
	move.b	#$1,$ffff8201.w                 ; video base high, the screen at $10000
mono_monitor_restore:
	move.l	(sp)+,$70.w                     ; the VBL vector back
	move.l	#monitor_change_handler,$13c.w  ; MFP monochrome detect, mono detect: a restart again
	btst	#$4,mode_flags.w                ; several tests?
	bne.s	mono_monitor_restore_colour     ; yes
	bset	#$7,mode_flags.w                ; the test waited for its own key
mono_monitor_restore_colour:
	move.w	saved_colour0.w,$ffff8240.w     ; palette 0
	move.w	#$2400,sr                       ; interrupts on
	rts

;------------------------------------------------------------------------------
; mono_vbl_flash: the VBL routine of the H test: $292 cleared, and every 120 VBLs the background
;  colour's blue bit 0 flipped; $21A counts down to it.
;------------------------------------------------------------------------------
mono_vbl_flash:	; from: mono_monitor_test
	move.w	d0,-(sp)
	clr.b	vbl_flag.w
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
; ste_scroll_test: the STE video part of the colour test, in medium resolution.  A triangle (lines 1 to
;  640 pixels wide and back) is drawn from $20000 and scrolled up by the VBL routine, which moves the
;  screen base one line every second VBL (the STE base low register) until SPACE.  Then a 640-pixel wide
;  picture with 320-byte lines (line offset 80 words) is drawn and scrolled sideways by the HBL routine
;  with the pixel scroll register until SPACE is pressed and released.  Out: $28D bit 7 set.
;  Changes d0-d7, a0-a3, $290, $4D4, $4E2, $4E4, $504, $508, the RAM from $20000 to $84000.
;------------------------------------------------------------------------------
ste_scroll_test:	; from: colour_test
	bsr.w	save_screen_state               ; the screen base and colour 0 kept
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
	move.l	$70.w,saved_vbl_vector.w        ; VBL vector
	move.l	#vscroll_vbl,$70.w              ; VBL vector, the vertical scroll routine
	move.w	#$666,$ffff8240.w               ; palette 0, background grey
	move.w	#$0,$ffff8246.w                 ; palette 3, colour 3 black
	move.w	#$ff,scroll_restart.w           ; start again at the first VBL
	move.w	#$2200,sr                       ; VBLs on
ste_scroll_wait_space_v:
	bsr.w	get_key
	cmpi.b	#$20,d0                         ; SPACE?
	bne.s	ste_scroll_wait_space_v         ; no
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
	move.w	#$ffff,line_count.w             ; no lines counted
	move.l	#scroll_vbl_clear_lines,$70.w   ; VBL vector, the line count cleared
	move.l	$68.w,saved_vector.w            ; HBL vector
	move.l	#hscroll_hbl,$68.w              ; HBL vector, the sideways scroll routine
	move.w	#$ff,scroll_restart.w           ; start again at the first scroll
	move.w	#$50,$ff820e                    ; line offset 80 words: double-width lines
	move.w	#$2000,sr                       ; HBLs on
	clr.b	key_release.w                   ; no key released yet
ste_scroll_wait_space_h:
	bsr.w	get_key
	cmpi.b	#$20,d0                         ; SPACE?
	bne.s	ste_scroll_wait_space_h         ; no
	bset	#$7,d1                          ; its release code
ste_scroll_wait_release:
	cmp.b	key_release.w,d1                ; SPACE released?
	bne.s	ste_scroll_wait_release         ; no
	move.w	#$2400,sr                       ; interrupts back
	move.w	#$0,$ff8264                     ; hscroll (no prefetch), no pixel scroll
	move.w	#$0,$ff820e                     ; no line offset
	move.l	saved_vbl_vector.w,$70.w        ; VBL vector
	move.l	saved_vector.w,$68.w            ; HBL vector
	bsr.w	restore_screen_state            ; the screen back
	bset	#$7,mode_flags.w                ; the test waited for its own key
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
; scroll_vbl_clear_lines: the VBL routine of the sideways scroll: the HBL line count $290 cleared.
;------------------------------------------------------------------------------
scroll_vbl_clear_lines:	; from: ste_scroll_test
	clr.w	line_count.w
	rte

;------------------------------------------------------------------------------
; hscroll_hbl: the HBL routine of the sideways scroll: at line 235 the picture moves one pixel: the pixel
;  scroll register 1-15 with the line offset $4E, at 0 the base 4 bytes on (one 16-pixel block) with
;  offset $50.  Only the base low byte is written, so the picture steps back within 256 bytes; past
;  $40140 in $4D4, or when $4E2 is set, it starts again at $20000.  $4E4 holds the pixel.
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
	move.l	#$20000,scroll_position.w       ; the address kept
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
	addi.l	#$4,scroll_position.w           ; 4 bytes on: the next block
	move.w	#$0,$ff8264                     ; hscroll (no prefetch), no pixel scroll
	move.w	#$50,$ff820e                    ; line offset 80 words
	move.b	scroll_position+3.w,$ffff820d.w ; video base low
	cmpi.l	#$40140,scroll_position.w       ; past $40140?
	bge.w	hscroll_hbl_restart             ; yes: again
hscroll_hbl_done:
	move.l	(sp)+,d0
	rte

;------------------------------------------------------------------------------
; vscroll_vbl: the VBL routine of the triangle scroll: every second VBL ($4E4 counts) the screen base one
;  line (160 bytes) on, through high, mid and low; at $52000 in $4D4, or when $4E2 is set, back to $20000.
;------------------------------------------------------------------------------
vscroll_vbl:	; from: ste_scroll_test
	movem.l	d0-d1,-(sp)
	cmpi.w	#$0,scroll_restart.w            ; start again?
	beq.s	vscroll_vbl_step                ; no
vscroll_vbl_restart:
	move.b	#$2,$ffff8201.w                 ; video base high, the screen at $20000
	move.b	#$0,$ffff8203.w                 ; video base mid
	move.b	#$0,$ffff820d.w                 ; video base low
	move.l	#$20000,scroll_position.w       ; the address kept
	clr.w	scroll_restart.w                ; started
	clr.w	scroll_step.w                   ; VBL count 0
	bra.s	vscroll_vbl_done
vscroll_vbl_step:
	move.l	scroll_position.w,d0            ; the address shown
	cmp.l	#$52000,d0                      ; at the end?
	bge.s	vscroll_vbl_restart             ; yes
	addi.w	#$1,scroll_step.w               ; one more VBL
	cmpi.w	#$2,scroll_step.w               ; the second?
	bne.s	vscroll_vbl_done                ; no
	clr.w	scroll_step.w                   ; counted again
	add.l	#$a0,d0                         ; one line on
	move.l	d0,scroll_position.w
	move.b	scroll_position+1.w,$ffff8201.w ; video base high
	move.b	scroll_position+2.w,$ffff8203.w ; video base mid
	move.b	scroll_position+3.w,$ffff820d.w ; video base low
vscroll_vbl_done:
	movem.l	(sp)+,d0-d1
	rte

;------------------------------------------------------------------------------
; floppy_menu: the F test.  Sets the floppy defaults (fill $E5E5, interleave 1, side 0, track 0, sector 1,
;  9 sectors, drive A), starts timer A free running (its data register is the random number), clears
;  the drive error bytes $49A/$49B.  Unattended it runs the quick test on the installed drives (looking
;  for them on the first cycle); else it shows the floppy menu and jumps to choice 1-7, any other key
;  goes back to the main menu.  The choices come back here.
;------------------------------------------------------------------------------
floppy_menu:                                    ; from: floppy_quick_test, floppy_alignment, floppy_interchange,
                                                ;   floppy_exerciser, floppy_copy_protect, floppy_speed_test, 2 more
	clr.b	fd_probing.w                    ; errors shown
	move.b	#$3f,$fffffa1f.w                ; MFP TADR, timer A data 63
	move.b	#$1,$fffffa19.w                 ; MFP TACR, timer A /4, free running: random numbers
	move.w	#$e5e5,fd_fill_word.w           ; fill $E5E5
	move.w	#$1,fd_interleave.w             ; interleave 1
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
	bsr.w	clear_screen
	lea	floppy_menu_text,a5             ; "Floppy disk drive routines:" and choices 1-7
	bsr.w	print_string
	bsr.w	get_key
	cmpi.b	#$30,d0                         ; below '1'?
	bls.w	floppy_menu_quit                ; yes: back to the main menu
	cmpi.b	#$37,d0                         ; above '7'?
	bhi.w	floppy_menu_quit                ; yes: back to the main menu
	andi.l	#$f,d0                          ; the digit
	subq.w	#1,d0                           ; 0-6
	lsl.w	#2,d0                           ; *4
	lea	floppy_menu_choices,a5          ; the choices
	bsr.w	clear_screen
	movea.l	0(a5,d0.w),a0                   ; this choice
	jmp	(a0)                            ; run

;------------------------------------------------------------------------------
; floppy_menu_choices: the routine for each floppy menu choice 1-7 (the digit typed - 1, times 4).
;------------------------------------------------------------------------------
floppy_menu_choices:
	dc.l	floppy_quick_test
	dc.l	floppy_alignment
	dc.l	floppy_interchange
	dc.l	floppy_exerciser
	dc.l	floppy_copy_protect
	dc.l	floppy_speed_test
	dc.l	floppy_install_drives
floppy_menu_quit:	; from: floppy_menu
	move.l	#vbl_handler,$70.w              ; VBL vector, the VBL routine back
	move.b	#$6,d0                          ; both drives deselected
	bsr.w	psg_select_drive_side
	bra.w	main_menu                       ; the main menu
floppy_unattended:	; from: floppy_menu
	cmpi.l	#$1,test_cycle.w                ; the first cycle?
	bne.s	floppy_unattended_check         ; no
	bsr.w	detect_drive_types
floppy_unattended_check:
	move.b	drive_a_type.w,d0               ; drive A's type
	or.b	drive_b_type.w,d0               ; or B's: any installed?
	bne.s	floppy_quick_test_run           ; yes: the quick test
	rts                                     ; none: nothing tested

;------------------------------------------------------------------------------
; floppy_quick_test: choice 1, "Quick Test" (writes the disks), also run unattended.  Looks for the drives
;  when none is installed.  On each installed drive: tracks 0, 1 and 79 formatted, written, read and
;  compared, the second side checked on a double sided drive, then a random track; "Pass" or "Fail"
;  on the drive's status line.  Unattended it returns; else it waits for a key (green on a pass) and
;  goes back to the floppy menu.
;------------------------------------------------------------------------------
floppy_quick_test:	; from: floppy_menu_choices
	bsr.w	clear_screen
	bsr.w	print_newline
	bsr.w	print_newline
	move.b	drive_a_type.w,d0               ; drive A's type
	or.b	drive_b_type.w,d0               ; any drive installed?
	bne.s	floppy_quick_test_run           ; yes
	bsr.w	detect_drive_types              ; no: look for them
	move.b	drive_a_type.w,d0               ; again
	or.b	drive_b_type.w,d0               ; any found?
	bne.s	floppy_quick_test_run           ; yes
	rts                                     ; none
floppy_quick_test_run:	; from: floppy_menu_choices
	move.w	#$2,scroll_top.w                ; two status lines kept
	bsr.w	save_cursor                     ; the cursor kept
	bsr.w	cursor_home                     ; to the top
	tst.b	drive_a_type.w                  ; drive A installed?
	beq.s	floppy_quick_show_b             ; no
	lea	msg_disk_a,a5                   ; "Disk A: "
	bsr.w	print_string
	lea	msg_single_sided,a5             ; "SS "
	btst	#$1,drive_a_type.w              ; double sided?
	beq.s	floppy_quick_show_a_type        ; no
	lea	msg_double_sided,a5             ; "DS "
floppy_quick_show_a_type:
	bsr.w	print_string                    ; the type
floppy_quick_show_b:
	tst.b	drive_b_type.w                  ; drive B installed?
	beq.s	floppy_quick_test_a             ; no
	moveq	#0,d0                           ; column 0
	moveq	#1,d1                           ; line 1
	bsr.w	set_cursor                      ; the cursor there
	lea	msg_disk_b,a5                   ; "Disk B: "
	bsr.w	print_string
	lea	msg_single_sided,a5             ; "SS "
	btst	#$1,drive_b_type.w
	beq.s	floppy_quick_show_b_type        ; no
	lea	msg_double_sided,a5             ; "DS "
floppy_quick_show_b_type:
	bsr.w	print_string                    ; the type
floppy_quick_test_a:
	bsr.w	restore_cursor                  ; the cursor back
	tst.b	test_errors.w                   ; drive A already failed?
	bne.s	floppy_quick_fail_a             ; yes
	cmpi.b	#$0,drive_a_type.w              ; drive A installed?
	beq.s	floppy_quick_test_b             ; no
	move.w	#$0,fd_drive.w                  ; drive A
	bsr.w	floppy_quick_test_drive         ; tracks 0, 1, 79 and the sides
	tst.b	test_errors.w                   ; failed?
	bne.s	floppy_quick_fail_a             ; yes
	bsr.w	floppy_random_track_test        ; a random track
	lea	msg_pass,a5                     ; "Pass"
	tst.b	test_errors.w                   ; failed?
	beq.s	floppy_quick_result_a           ; no
floppy_quick_fail_a:
	lea	msg_fail,a5                     ; "Fail "
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
floppy_quick_result_a:
	moveq	#50,d0                          ; column 50
	moveq	#0,d1                           ; line 0
	bsr.w	show_status_at
	tst.b	test_errors_high.w              ; drive B already failed?
	bne.s	floppy_quick_fail_b             ; yes
floppy_quick_test_b:
	cmpi.b	#$0,drive_b_type.w              ; drive B installed?
	beq.s	floppy_quick_test_end           ; no
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	floppy_quick_test_drive         ; tracks 0, 1, 79 and the sides
	tst.b	test_errors_high.w              ; failed?
	bne.s	floppy_quick_fail_b             ; yes
	bsr.w	floppy_random_track_test        ; a random track
	lea	msg_pass,a5                     ; "Pass"
	tst.b	test_errors_high.w              ; failed?
	beq.s	floppy_quick_result_b           ; no
floppy_quick_fail_b:
	lea	msg_fail,a5                     ; "Fail "
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
floppy_quick_result_b:
	moveq	#50,d0                          ; column 50
	moveq	#1,d1                           ; line 1
	bsr.w	show_status_at
floppy_quick_test_end:
	move.b	test_errors.w,d0                ; an error on either drive?
	or.b	test_errors_high.w,d0
	beq.s	floppy_quick_test_wait          ; no
	lea	msg_fail_at_cycle,a5            ; "Fail at cycle:"
	bsr.w	show_result
floppy_quick_test_wait:
	move.b	mode_flags.w,d0                 ; the mode
	andi.b	#$38,d0                         ; Q/Z, several tests or a repeat count?
	bne.s	floppy_quick_unattended_end     ; unattended
	bsr.w	screen_is_red                   ; failed (red)?
	beq.s	floppy_quick_test_key           ; yes
	move.w	#$51,$ffff8240.w                ; palette 0, no: green
floppy_quick_test_key:
	bsr.w	get_key                         ; a key
	bra.w	floppy_menu                     ; the floppy menu
floppy_quick_unattended_end:
	move.l	#vbl_handler,$70.w              ; VBL vector, the VBL routine back
	move.b	#$6,d0                          ; both drives deselected
	bsr.w	psg_select_drive_side
	rts

;------------------------------------------------------------------------------
; floppy_alignment: choice 2, "Read analog alignment disk".  Asks for drive A or B and a track (default
;  40, up to 79), then reads the track over and over: up/down arrows side 1/0, right/left arrows the
;  next/previous track (wrapping at 79 to 0; at 0 the left arrow does nothing), SPACE stops, ESC the
;  floppy menu.  Reads only.
;------------------------------------------------------------------------------
floppy_alignment:	; from: floppy_menu_choices
	lea	msg_read_alignment_disk,a5      ; "Read analog alignment disk", "Disk A or B?"
	bsr.w	print_string
	move.w	#$0,fd_drive.w                  ; drive A
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$28,fd_track.w                 ; track 40
	move.w	#$1,fd_sector.w                 ; sector 1
floppy_alignment_ask_drive:
	bsr.w	get_key                         ; A or B
	cmp.b	#$41,d0                         ; 'A'?
	beq.s	floppy_alignment_track          ; yes
	cmp.b	#$42,d0                         ; 'B'?
	bne.s	floppy_alignment_ask_drive      ; no: ask again
	move.w	#$1,fd_drive.w                  ; drive B
floppy_alignment_track:
	lea	msg_enter_track_number,a5       ; "Enter track number (if none entered, default=40): "
	bsr.w	print_string
	bsr.w	read_command                    ; the line typed
	tst.w	d0                              ; nothing?
	beq.w	floppy_alignment_start          ; then track 40
	bsr.w	print_newline
	lea	number_digits.w,a3              ; the digits copied reversed to $267
floppy_alignment_reverse:
	move.b	-(a4),d0                        ; from the last
	move.b	d0,(a3)+                        ; to the first
	cmpa.l	#$237,a4                        ; all copied?
	bne.s	floppy_alignment_reverse        ; no
	lea	number_digits.w,a0              ; the number
	bsr.w	decimal_to_number
	cmp.w	#$4f,d2                         ; past track 79?
	bhi.s	floppy_alignment_track          ; yes: ask again
	move.w	d2,fd_track.w                   ; the track
floppy_alignment_start:
	bsr.w	clear_screen
	move.w	#$1,fd_interleave.w             ; interleave 1
	move.w	#$0,fd_side.w                   ; side 0
	bsr.w	restore_drive                   ; the drive to track 0
	beq.w	floppy_alignment_read           ; done
	lea	msg_drive_not_ready,a5          ; "FD Drive not ready "
	bsr.w	print_string
	bsr.w	print_drive_side_track          ; drive, side and track shown
	bsr.w	print_newline
	bra.w	floppy_alignment_stopped        ; stopped
floppy_alignment_read:
	lea	msg_reading,a5                  ; "Reading    "
	bsr.w	print_floppy_action             ; "Reading", side and track shown
	bsr.w	read_alignment_track            ; the track read
	bsr.w	key_waiting                     ; a key?
	beq.s	floppy_alignment_read           ; no: again
	bsr.w	get_key
	cmpi.b	#$48,d1                         ; up arrow?
	beq.s	floppy_alignment_side_1         ; side 1
	cmpi.b	#$50,d1                         ; down arrow?
	beq.s	floppy_alignment_side_0         ; side 0
	cmpi.b	#$4d,d1                         ; right arrow?
	beq.w	floppy_alignment_next_track     ; the next track
	cmpi.b	#$4b,d1                         ; left arrow?
	beq.w	floppy_alignment_prev_track     ; the track before
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_alignment_quit           ; the floppy menu
	cmpi.b	#$20,d0                         ; SPACE?
	bne.s	floppy_alignment_read           ; no: read on
floppy_alignment_stopped:
	lea	msg_stopped_esc_quit,a5         ; "Stopped. ESC to quit, any other key to continue."
	bsr.w	print_string
	bsr.w	get_key
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_alignment_quit           ; yes
	bsr.w	clear_screen
	bra.s	floppy_alignment_read           ; read on
floppy_alignment_quit:
	bra.w	floppy_menu                     ; the floppy menu
floppy_alignment_side_0:
	move.w	#$0,fd_side.w                   ; side 0
	bra.s	floppy_alignment_read
floppy_alignment_side_1:
	move.w	#$1,fd_side.w                   ; side 1
	bra.s	floppy_alignment_read
floppy_alignment_next_track:
	cmpi.w	#$4f,fd_track.w                 ; at track 79?
	beq.w	floppy_alignment_wrap_low       ; yes
	addi.w	#$1,fd_track.w                  ; one on
	bra.w	floppy_alignment_read
floppy_alignment_wrap_low:
	move.w	#$0,fd_track.w                  ; track 0
	bra.w	floppy_alignment_read
floppy_alignment_prev_track:
	cmpi.w	#$0,fd_track.w                  ; at track 0?
	beq.w	floppy_alignment_wrap_high      ; yes
	subi.w	#$1,fd_track.w                  ; one back
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
floppy_interchange:	; from: floppy_menu_choices
	move.w	#$3,$ffff8240.w                 ; palette 0, the background blue
	lea	msg_disk_interchange_test,a5    ; "Disk interchange test", "Insert disks in both drives, ..."
	bsr.w	print_string
	bsr.w	get_key
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_menu                     ; yes: the floppy menu
floppy_interchange_start:
	bsr.w	floppy_interchange_drive_lines  ; the drive lines shown
	move.b	#$0,test_index_byte.w           ; the first of three tracks
	move.w	#$1,fd_sector.w                 ; sector 1
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$0,fd_drive.w                  ; drive A
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	beq.s	floppy_interchange_restore_b    ; yes
	bsr.w	print_a_not_selected
	bra.s	floppy_interchange_not_ready    ; wait
floppy_interchange_restore_b:
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	restore_drive                   ; to track 0
	beq.s	floppy_interchange_write        ; done
	bsr.w	print_b_not_selected
floppy_interchange_not_ready:
	bsr.w	get_key                         ; a key
	bra.s	floppy_interchange              ; start again
floppy_interchange_write:
	clr.l	d2
	lea	interchange_test_track_list,a2  ; tracks 0, 39, 79
	move.b	test_index_byte.w,d2
	move.b	0(a2,d2.w),fd_track+1.w         ; this track
	move.w	#$0,fd_drive.w                  ; drive A
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_format_error ; yes
	bsr.w	fill_buffer_aa                  ; $AAAA
	bsr.w	floppy_write_sectors            ; written
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_write_error  ; yes
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_format_error ; yes
	bsr.w	fill_buffer_bb                  ; $BBBB
	bsr.w	floppy_write_sectors            ; written
	tst.w	d0                              ; an error?
	bne.w	floppy_interchange_write_error  ; yes
	addi.b	#$1,test_index_byte.w           ; the next track
	cmpi.b	#$3,test_index_byte.w           ; three done?
	bne.s	floppy_interchange_write        ; no
floppy_interchange_swap:
	lea	msg_swap_disks,a5               ; "Swap disks A and B, Hit any key when ready"
	bsr.w	print_string
	bsr.w	get_key
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_menu                     ; yes: the floppy menu
	bsr.w	floppy_interchange_drive_lines  ; the drive lines again
	move.w	#$0,test_index_byte.w           ; the first track
	move.l	#$4000,fd_buffer.w              ; read to $4000
floppy_interchange_read_track:
	move.w	#$0,fd_drive.w                  ; drive A
	clr.l	d2
	lea	interchange_test_track_list,a2  ; tracks 0, 39, 79
	move.b	test_index_byte.w,d2
	move.b	0(a2,d2.w),fd_track+1.w         ; this track
	bsr.w	read_track                      ; read
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
	bsr.w	print_string
	bra.s	floppy_interchange_swap         ; ask again
floppy_interchange_next_a:
	dbra	d0,floppy_interchange_check_a   ; the next word
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	read_track                      ; read
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
	cmpi.b	#$3,test_index_byte.w
	bne.w	floppy_interchange_read_track   ; three done?
	bsr.w	screen_is_red                   ; red: something failed?
	beq.s	floppy_interchange_repeat       ; yes: failed
	move.w	#$51,$ffff8240.w                ; palette 0, green
	lea	msg_pass,a5                     ; "Pass"
	bsr.w	show_result
	bsr.w	get_key
	bra.w	floppy_menu
floppy_interchange_format_error:
	lea	msg_error_formatting,a5         ; "Error formating "
floppy_interchange_show_error:
	bsr.w	print_string                    ; the error shown
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
floppy_interchange_repeat:
	lea	msg_esc_quit_any_key_repeat,a5  ; "Hit esc to quit, any other key to repeat"
	bsr.w	print_string
	bsr.w	get_key
	cmpi.b	#$1b,d0                         ; ESC?
	beq.w	floppy_menu                     ; yes: the floppy menu
	bra.w	floppy_interchange_start        ; again
floppy_interchange_write_error:
	lea	msg_error_writing,a5            ; "Error writing"
	bsr.w	print_floppy_error              ; the error from $776 and where
	bra.s	floppy_interchange_show_error   ; then a5 shown again (print_floppy_error leaves it at "Track ")
floppy_interchange_read_error:
	lea	msg_error_reading,a5            ; "Error reading"
	bsr.w	print_string
	bsr.w	print_drive_name
	bsr.w	print_track_number
	bsr.w	print_newline
floppy_interchange_mark_fail:
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	bra.w	floppy_interchange_next_track   ; the next track

;------------------------------------------------------------------------------
; floppy_interchange_drive_lines: clears the screen (blue) and shows "Disk A: " and "Disk B: " on the two
;  status lines, which are then kept from scrolling ($298 = 2).
;------------------------------------------------------------------------------
floppy_interchange_drive_lines:	; from: floppy_interchange
	bsr.w	clear_screen
	move.w	#$3,$ffff8240.w                 ; palette 0, the background blue
	lea	msg_disk_a,a5                   ; "Disk A: "
	bsr.w	print_string
	bsr.w	print_newline
	lea	msg_disk_b,a5                   ; "Disk B: "
	bsr.w	print_string
	bsr.w	print_newline
	move.w	#$2,scroll_top.w                ; two status lines kept
	rts

;------------------------------------------------------------------------------
; floppy_exerciser: choice 4, "Disk Exerciser" (writes the disk).  Asks for drive A or B (its sides from
;  the installed type, else tried), formats every track (both sides on a double sided drive), then
;  cycles until stopped: every track written ($2000, the cycle's random byte from timer A in the data),
;  then read back in a mixed order (the table of 80 tracks) and compared.  5 format, 20 write or
;  20 read errors ask "Stopped..."; ESC at any time too.  RET goes on, any other key the floppy menu.
;------------------------------------------------------------------------------
floppy_exerciser:	; from: floppy_menu_choices
	bsr.w	clear_screen
	lea	msg_disk_exerciser,a5           ; "Disk Exerciser"
	bsr.w	print_string
	lea	msg_disk_a_or_b,a5              ; "Disk A or B?"
	bsr.w	print_string
	bsr.w	print_newline
	bsr.w	print_newline
	move.w	#$0,fd_drive.w                  ; drive A
	bsr.w	get_key
	cmp.b	#$41,d0                         ; 'A'?
	bne.s	floppy_exerciser_drive_b        ; no
	move.b	drive_a_type.w,d0               ; drive A's type
	tst.b	d0                              ; installed?
	bne.s	floppy_exerciser_start          ; yes
	bra.s	floppy_exerciser_detect         ; no: its sides found
floppy_exerciser_drive_b:
	cmp.b	#$42,d0                         ; 'B'?
	bne.w	floppy_menu
	move.w	#$1,fd_drive.w                  ; drive B
	move.b	drive_b_type.w,d0               ; drive B's type
	tst.b	d0                              ; installed?
	bne.s	floppy_exerciser_start          ; yes
floppy_exerciser_detect:
	bsr.w	probe_drive_sides_restored      ; its sides found
floppy_exerciser_start:
	move.b	d0,exerciser_drive_type.w       ; its type kept
	move.l	#$1,test_cycle.w                ; cycle 1
	bsr.w	clear_screen
	lea	msg_disk_exerciser,a5           ; "Disk Exerciser"
	bsr.w	print_string
	bsr.w	print_newline
	move.w	#$2,scroll_top.w                ; two status lines kept
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$0,fd_track.w                  ; track 0
	move.w	#$1,fd_sector.w                 ; sector 1
	move.w	#$9,fd_count.w                  ; 9 sectors
	clr.w	fd_write_errors.w               ; no write errors
	clr.w	fd_read_errors.w                ; no read errors
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	beq.s	floppy_exerciser_clear_marks    ; yes
	tst.w	fd_drive.w                      ; drive B?
	beq.s	floppy_exerciser_a_not_ready    ; no
	bsr.w	print_b_not_selected
	bra.s	floppy_exerciser_not_ready_key  ; wait
floppy_exerciser_a_not_ready:
	bsr.w	print_a_not_selected
floppy_exerciser_not_ready_key:
	bsr.w	get_key                         ; a key
	bra.w	floppy_exerciser                ; start again
floppy_exerciser_clear_marks:
	lea	fd_bad_tracks.w,a2              ; the bad track marks
	moveq	#79,d0                          ; 80 of them (side 0 only; side 1's are not cleared)
floppy_exerciser_clear_loop:
	clr.b	(a2)+                           ; cleared
	dbra	d0,floppy_exerciser_clear_loop
floppy_exerciser_format_side:
	clr.w	fd_format_errors.w              ; no format errors
floppy_exerciser_format_track:
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; an error?
	beq.s	floppy_exerciser_format_esc     ; no
	cmpi.w	#$5,fd_format_errors.w          ; 5 format errors or more?
	blt.w	floppy_exerciser_format_esc     ; no
	bsr.w	ask_stopped                     ; "Stopped..."
	beq.s	floppy_exerciser_format_next    ; RET: on
	bra.w	floppy_menu                     ; else the floppy menu
floppy_exerciser_format_esc:
	bsr.w	check_esc                       ; ESC: "Stopped..."
	bne.w	floppy_menu                     ; quit: the floppy menu
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
	move.b	$fffffa1f.w,cycle_random.w      ; MFP TADR, this cycle's random byte
	move.w	#$0,fd_side.w                   ; side 0
	bsr.w	print_cycle                     ; "Cycle: " shown, the cycle counted
	clr.w	fd_write_errors.w               ; no write errors
	clr.w	fd_read_errors.w                ; no read errors
floppy_exerciser_write_side:
	move.w	#$0,fd_track.w                  ; track 0
	move.l	#$2000,fd_buffer.w              ; written from $2000
floppy_exerciser_write_track:
	bsr.w	write_track                     ; written
	tst.w	d0                              ; an error?
	beq.s	floppy_exerciser_write_esc      ; no
	cmpi.w	#$14,fd_write_errors.w          ; 20 write errors or more?
	blt.w	floppy_exerciser_write_esc      ; no
	bsr.w	ask_stopped                     ; "Stopped..."
	beq.s	floppy_exerciser_write_next     ; RET: on
	bra.w	floppy_menu                     ; else the floppy menu
floppy_exerciser_write_esc:
	bsr.w	check_esc                       ; ESC: "Stopped..."
	bne.w	floppy_menu                     ; quit: the floppy menu
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
	move.b	#$0,test_index_byte.w           ; the first of the mixed order
floppy_exerciser_read_track:
	lea	floppy_exerciser_track_order,a2 ; the mixed track order
	clr.l	d2
	move.b	test_index_byte.w,d2
	move.b	0(a2,d2.w),fd_track+1.w         ; this track
	bsr.w	read_track                      ; read
	beq.s	floppy_exerciser_read_check     ; read (Z)?
	cmpi.w	#$14,fd_read_errors.w           ; 20 read errors or more?
	blt.s	floppy_exerciser_read_side      ; no: the read pass again from the start
	bsr.w	ask_stopped                     ; "Stopped..."
	beq.s	floppy_exerciser_read_side      ; RET: the side again from the first track
	bra.w	floppy_menu                     ; else the floppy menu
floppy_exerciser_read_check:
	bsr.w	compare_sector_data             ; compared with the data written
	bsr.w	check_esc                       ; ESC: "Stopped..."
	bne.w	floppy_menu                     ; quit: the floppy menu
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
floppy_copy_protect:	; from: floppy_menu_choices
	lea	msg_disk_a_or_b,a5              ; "Disk A or B?"
	bsr.w	print_string
	bsr.w	get_key
	cmp.b	#$41,d0                         ; 'A'?
	beq.s	floppy_copy_protect_start       ; yes
	cmp.b	#$42,d0                         ; 'B'?
	bne.w	floppy_menu
	move.w	#$1,fd_drive.w                  ; drive B
floppy_copy_protect_start:
	bsr.w	clear_screen
	lea	msg_check_tracks_80_82,a5       ; "Check Tracks 80-82"
	bsr.w	print_string
	move.w	#$0,fd_track.w                  ; track 0
	bsr.w	restore_drive                   ; the drive to track 0
	move.w	#$50,fd_track.w                 ; track 80
floppy_copy_protect_write:
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; an error?
	bne.s	floppy_copy_protect_fail        ; yes
	bsr.w	write_track                     ; written
	tst.w	d0                              ; an error?
	bne.s	floppy_copy_protect_fail        ; yes
	addi.w	#$1,fd_track.w                  ; the next
	cmpi.w	#$53,fd_track.w                 ; past 82?
	bne.s	floppy_copy_protect_write       ; no
	move.w	#$50,fd_track.w                 ; track 80 again
floppy_copy_protect_read:
	bsr.w	read_track                      ; read
	tst.w	d0                              ; an error?
	bne.s	floppy_copy_protect_fail        ; yes
	addi.w	#$1,fd_track.w                  ; the next
	cmpi.w	#$53,fd_track.w                 ; past 82?
	bne.s	floppy_copy_protect_read        ; no
	lea	msg_copy_protect_pass,a5        ; "Copy protect tracks PASS"
	move.w	#$51,$ffff8240.w                ; palette 0, green
floppy_copy_protect_show:
	bsr.w	print_string                    ; the result
	bsr.w	get_key
	bra.w	floppy_menu                     ; the floppy menu
floppy_copy_protect_fail:
	bsr.w	print_floppy_error              ; the error from $776 and where
	lea	msg_copy_protect_fail,a5        ; "Copy protect tracks FAIL"
	move.w	#$500,$ffff8240.w               ; palette 0, red
	bra.s	floppy_copy_protect_show

;------------------------------------------------------------------------------
; floppy_speed_test: choice 6, "Floppy disk speed test".  Asks for drive A or B, then over and over: track 0,
;  timer A (/200, 8 counts: 651 us a tick) counted from one index pulse to the next, made milliseconds;
;  outside 196-204 the background goes red.  Max, min and the current time are shown (BCD) until a
;  key; "Time-out waiting for index" when no index pulse comes.  Back to the floppy menu.
;------------------------------------------------------------------------------
floppy_speed_test:	; from: floppy_menu_choices
	bsr.w	clear_screen
	lea	msg_floppy_speed_test,a5        ; "Floppy disk speed test"
	bsr.w	print_string
	lea	msg_disk_a_or_b,a5              ; "Disk A or B?"
	bsr.w	print_string
	clr.w	fd_drive.w                      ; drive A
	bsr.w	get_key
	cmpi.b	#$42,d0                         ; 'B'?
	bne.w	floppy_speed_start              ; no
	move.w	#$1,fd_drive.w                  ; drive B
floppy_speed_start:
	bsr.w	clear_screen
	lea	msg_testing_speed,a5            ; "Testing speed", "Allowable range = 196 - 204 milliseconds/revolution"
	bsr.w	print_string
	move.w	#$0,d0                          ; column 0
	move.w	#$3,d1                          ; line 3
	bsr.w	set_cursor
	lea	msg_speed_heading,a5            ; "Max      Min      Current speed"
	bsr.w	print_string
	move.b	#$0,$fffffa19.w                 ; MFP TACR, timer A stopped
	move.b	#$8,$fffffa1f.w                 ; MFP TADR, 8 counts: 651 us
	lea	floppy_speed_tick,a2            ; the tick counter
	moveq	#13,d0                          ; interrupt 13: timer A
	bsr.w	mfp_install_handler
	clr.w	fd_side.w                       ; side 0
	clr.w	fd_track.w                      ; track 0
	bsr.w	restore_drive                   ; the drive to track 0
	clr.b	floppy_motor_watch.w            ; the motor watch off
	move.w	#$0,speed_max.w                 ; max 0
	move.w	#$ffff,speed_min.w              ; min $FFFF
floppy_speed_loop:
	move.w	#$0,d7                          ; track 0
	bsr.w	floppy_seek_command
	moveq	#22,d0                          ; column 22
	moveq	#4,d1                           ; line 4
	bsr.w	set_cursor
	lea	key_text_left_arrow,a5          ; an arrow while it measures
	bsr.w	print_string
	move.b	#$7,$fffffa19.w                 ; MFP TACR, timer A running, /200
	bsr.w	wait_index_on                   ; wait for the index pulse
	tst.w	d5                              ; time-out?
	beq.w	floppy_speed_no_index           ; yes
	clr.w	speed_ticks.w                   ; no ticks yet
	bsr.w	wait_index_off                  ; wait for its end
	tst.w	d5                              ; time-out?
	beq.w	floppy_speed_no_index           ; yes
	bsr.w	wait_index_on                   ; wait for the next index pulse
	move.w	speed_ticks.w,-(sp)             ; the ticks of one turn
	bsr.w	wait_index_off                  ; wait for its end
	moveq	#22,d0                          ; column 22
	moveq	#4,d1                           ; line 4
	bsr.w	set_cursor
	bsr.w	print_space
	clr.b	$fffffa19.w                     ; MFP TACR, timer A stopped
	move.w	(sp)+,d0                        ; the ticks
	bsr.w	ticks_to_ms                     ; made ms, in BCD
	cmp.w	#$205,d1                        ; 205 ms or more?
	bge.w	floppy_speed_bad                ; yes: bad
	cmp.w	#$195,d1                        ; more than 195 ms?
	bgt.w	floppy_speed_check_max          ; yes: good
floppy_speed_bad:
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
floppy_speed_check_max:
	cmp.w	speed_max.w,d1                  ; above the max?
	bls.w	floppy_speed_check_min          ; no
	move.w	d1,speed_max.w                  ; the new max
floppy_speed_check_min:
	cmp.w	speed_min.w,d1                  ; below the min?
	bhi.w	floppy_speed_show               ; no
	move.w	d1,speed_min.w                  ; the new min
floppy_speed_show:
	move.w	d1,-(sp)                        ; this one kept
	moveq	#0,d0                           ; column 0
	moveq	#4,d1                           ; line 4
	bsr.w	set_cursor
	move.w	speed_max.w,d1                  ; max
	bsr.w	print_hex_word
	bsr.w	put_tab
	move.w	speed_min.w,d1                  ; min
	bsr.w	print_hex_word
	bsr.w	put_tab
	move.w	(sp)+,d1                        ; this one
	bsr.w	print_hex_word
	bsr.w	print_newline
	bsr.w	key_waiting                     ; a key?
	tst.w	d0
	beq.w	floppy_speed_loop               ; no: again
floppy_speed_quit:
	bsr.w	get_key                         ; the key taken
	moveq	#13,d0                          ; timer A
	bsr.w	mfp_disable_interrupt
	bsr.w	restore_drive                   ; the drive to track 0
	bra.w	floppy_menu                     ; the floppy menu
floppy_speed_no_index:
	lea	msg_index_time_out,a5           ; "Time-out waiting for index"
	bsr.w	print_string
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
	bsr.w	word_to_bcd
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
; floppy_speed_tick: the timer A routine of the speed test: one more tick in $692.
;------------------------------------------------------------------------------
floppy_speed_tick:	; from: floppy_speed_test
	addi.w	#$1,speed_ticks.w               ; one more tick
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
	bsr.w	fdc_read_d0
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
	bsr.w	fdc_read_d0
	btst	#$1,d0                          ; index gone?
	beq.w	wait_index_off_done             ; yes
	subq.w	#1,d5                           ; more tries?
	bne.s	wait_index_off_loop
wait_index_off_done:
	rts

;------------------------------------------------------------------------------
; floppy_install_drives: choice 7, "Install disk drives": asks the type of drive A and then drive B (1/S single
;  sided, 2/D double sided, any other key not installed) and keeps them at $278/$279.
;------------------------------------------------------------------------------
floppy_install_drives:	; from: floppy_menu_choices
	bsr.w	clear_screen
	lea	msg_drive_side_choice,a5        ; "1  Single sided" ... "Any other key will de-install this drive."
	bsr.w	print_string
	lea	msg_disk_a,a5                   ; "Disk A: "
	bsr.w	ask_drive_type                  ; asked
	move.b	d2,drive_a_type.w               ; drive A's type
	lea	msg_disk_b,a5                   ; "Disk B: "
	bsr.w	ask_drive_type                  ; asked
	move.b	d2,drive_b_type.w               ; drive B's type
	bra.w	floppy_menu                     ; the floppy menu

;------------------------------------------------------------------------------
; probe_drive_sides_restored: steps drive $68A to track 0 and, if it answers, finds its sides with no
;  error messages.  Out: d0 0 no drive or not writable, 1 single sided, 2 double sided.
;------------------------------------------------------------------------------
probe_drive_sides_restored:	; from: floppy_exerciser
	bsr.w	restore_drive                   ; to track 0
	bne.s	detect_drive_sides_none         ; no drive
	move.b	#$1,fd_probing.w                ; quiet
	bsr.w	probe_drive_sides               ; sides found
	clr.b	fd_probing.w                    ; errors shown again
	rts
detect_drive_sides_none:
	clr.w	d0                              ; none
	rts

;------------------------------------------------------------------------------
; detect_drive_types: "Checking...": finds which drives answer and, by writing track 79, whether
;  each is single or double sided.  Out: $278/$279 the types (bit 7 found, bit 0 single sided, bits 0
;  and 1 double sided; drive B's bit 7 is dropped once its sides are known), $49A/$49B 1 when a drive
;  cannot be written ("Cannot write drive A/B", red); "No floppies " when none answers.
;  Changes d0-d7, a0-a6.
;------------------------------------------------------------------------------
detect_drive_types:	; from: floppy_menu_choices, floppy_quick_test
	lea	msg_checking_drives,a5          ; "Checking drive type..."
	bsr.w	show_status
	clr.b	drive_a_type.w                  ; drive A none
	clr.b	drive_b_type.w                  ; drive B none
	clr.w	fd_drive.w                      ; drive A
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	bne.s	detect_drive_b_restore          ; no
	bset	#$7,drive_a_type.w              ; found
detect_drive_b_restore:
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	bne.s	detect_drive_types_any          ; no
	bset	#$7,drive_b_type.w              ; found
detect_drive_types_any:
	tst.b	drive_a_type.w                  ; drive A found?
	bne.s	detect_drive_a_sides            ; yes
	tst.b	drive_b_type.w                  ; drive B?
	bne.s	detect_drive_b_sides            ; yes
	lea	msg_no_floppies,a5              ; "No floppies "
	bsr.w	show_status
	move.l	#vbl_handler,$70.w              ; VBL vector, the VBL routine back
	rts
detect_drive_a_sides:
	move.b	#$1,fd_probing.w                ; quiet
	clr.w	fd_drive.w                      ; drive A
	bsr.w	probe_drive_sides               ; formatted, written, sides tried
	tst.w	d0                              ; not writable?
	beq.s	detect_drive_a_unwritable       ; yes
	cmp.b	#$1,d0                          ; single sided?
	beq.s	detect_drive_a_single           ; yes
	ori.b	#$3,drive_a_type.w              ; double sided (bits 0, 1)
	bra.s	detect_drive_b_sides            ; on to drive B
detect_drive_a_single:
	ori.b	#$1,drive_a_type.w              ; single sided (bit 0)
	bra.s	detect_drive_b_sides
detect_drive_a_unwritable:
	lea	msg_cannot_write_drive_a,a5     ; "Cannot write drive A"
	bsr.w	print_string
	move.b	#$1,test_errors.w               ; drive A error
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	ori.b	#$80,drive_a_type.w             ; found but not writable
detect_drive_b_sides:
	btst	#$7,drive_b_type.w              ; drive B found?
	beq.s	detect_drive_types_done         ; no
	move.w	#$1,fd_drive.w                  ; drive B
	bsr.w	probe_drive_sides               ; formatted, written, sides tried
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
	bsr.w	print_string
	move.b	#$1,test_errors_high.w          ; drive B error
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	move.b	#$80,drive_b_type.w             ; found but not writable
detect_drive_types_done:
	clr.b	fd_probing.w                    ; errors shown again
	bsr.w	clear_status_line               ; the status line cleared
	rts

;------------------------------------------------------------------------------
; ask_drive_type: shows a5 ("Disk A: " or "Disk B: ") and reads a key: 1 or S single sided, 2 or D double
;  sided (the key echoed), any other none.  Out: d2 1 single, 3 double, 0 none.  Changes d0, d1.
;------------------------------------------------------------------------------
ask_drive_type:	; from: floppy_install_drives
	bsr.w	print_string                    ; the drive
	clr.b	d2                              ; none
	bsr.w	get_key
	cmpi.b	#$31,d0                         ; '1'?
	beq.s	ask_drive_type_single           ; yes
	cmpi.b	#$53,d0                         ; 'S'?
	bne.s	ask_drive_type_two              ; no
ask_drive_type_single:
	move.b	#$1,d2                          ; single sided
	move.w	d0,d1                           ; echoed
	bsr.w	put_char
	bra.s	ask_drive_type_done
ask_drive_type_two:
	cmpi.b	#$32,d0                         ; '2'?
	beq.s	ask_drive_type_double
	cmpi.b	#$44,d0                         ; 'D'?
	bne.s	ask_drive_type_done             ; no
ask_drive_type_double:
	move.b	#$3,d2                          ; double sided
	move.w	d0,d1                           ; echoed
	bsr.w	put_char
ask_drive_type_done:
	bsr.w	print_newline                   ; new line
	rts

;------------------------------------------------------------------------------
; print_floppy_action: shows a5 ("Formatting", "Writing", "Reading"), the side and the track at column 19
;  of the drive's status line (row 0 drive A, 1 drive B), the cursor kept.  In: a5 the text.
;  Changes d0, d1.
;------------------------------------------------------------------------------
print_floppy_action:	; from: floppy_alignment, format_track_checked, write_track, read_track
	bsr.w	save_cursor                     ; the cursor kept
	moveq	#19,d0                          ; column 19
	move.w	fd_drive.w,d1                   ; row: the drive
	bsr.w	set_cursor                      ; there
	bsr.w	print_string                    ; the action
	bsr.w	print_side_number               ; the side
	bsr.w	print_track_number              ; the track
	bsr.w	print_newline
	bsr.w	restore_cursor                  ; the cursor back
	rts

;------------------------------------------------------------------------------
; print_sector_number: "Sector " and the sector $75C in decimal.
;------------------------------------------------------------------------------
print_sector_number:	; from: compare_sector_data
	lea	msg_sector,a5                   ; "Sector "
	bsr.w	print_string
	move.w	fd_cur_sector.w,d0
	bsr.w	word_to_bcd
	bsr.w	print_hex_byte
	bsr.w	print_space
	rts

;------------------------------------------------------------------------------
; print_track_number: "Track " and the track $684 in decimal, then 10 spaces.
;------------------------------------------------------------------------------
print_track_number:	; from: floppy_interchange, print_floppy_action, print_drive_side_track, compare_sector_data
	lea	msg_track,a5                    ; "Track "
	bsr.w	print_string
	move.w	fd_track.w,d0
	bsr.w	word_to_bcd
	bsr.w	print_hex_byte
	moveq	#10,d1                          ; 10 spaces
	bsr.w	print_spaces
	rts

;------------------------------------------------------------------------------
; print_side_number: "Side " and the side $682.
;------------------------------------------------------------------------------
print_side_number:	; from: print_floppy_action, print_drive_side_track
	lea	msg_side,a5                     ; "Side "
	bsr.w	print_string
	move.w	fd_side.w,d1
	bsr.w	print_hex_digit
	bsr.w	print_space
	rts

;------------------------------------------------------------------------------
; print_drive_name: "Disk A: " or "Disk B: " for the drive $68A.
;------------------------------------------------------------------------------
print_drive_name:	; from: floppy_interchange, print_drive_side_track
	lea	msg_disk_b,a5                   ; "Disk B: "
	tst.w	fd_drive.w
	bne.s	print_drive_name_show           ; yes
	lea	msg_disk_a,a5                   ; "Disk A: "
print_drive_name_show:
	bsr.w	print_string
	rts

;------------------------------------------------------------------------------
; probe_drive_sides: formats track 79 side 0 of drive $68A and writes sector 1, then tries side 1
;  (probe_side_one).  Out: d0 0 when it cannot be formatted or written, 1 single sided, 2 double sided.
;  Changes the floppy settings $67E-$688.
;------------------------------------------------------------------------------
probe_drive_sides:	; from: probe_drive_sides_restored, detect_drive_types
	move.w	#$e5e5,fd_fill_word.w           ; fill $E5E5
	move.w	#$1,fd_interleave.w             ; interleave 1
	move.w	#$4f,fd_track.w                 ; track 79
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$9,fd_count.w                  ; 9 sectors
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; failed?
	beq.s	probe_drive_sides_write         ; no
	moveq	#0,d0                           ; not writable
	rts
probe_drive_sides_write:
	bsr.w	build_sector_data               ; the test data
	move.w	#$1,fd_sector.w                 ; sector 1
	move.w	#$1,fd_count.w                  ; one sector
	bsr.w	floppy_write_sectors            ; written
	tst.w	d0                              ; failed?
	beq.s	probe_side_one                  ; no: side 1 tried
	moveq	#0,d0                           ; not writable
	rts

;------------------------------------------------------------------------------
; probe_side_one: formats track 79 on side 1, then reads sector 1 of track 79 side 0 back: a single sided
;  drive formats side 0 instead, so the sector written there is gone and the read fails.
;  Out: d0 2 double sided, 1 single sided.
;------------------------------------------------------------------------------
probe_side_one:	; from: probe_drive_sides, floppy_quick_test_drive
	move.w	#$1,fd_side.w                   ; side 1
	move.w	#$4f,fd_track.w                 ; track 79
	move.w	#$9,fd_count.w                  ; 9 sectors
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; failed?
	bne.s	probe_side_one_single           ; yes: single sided
	move.w	#$0,fd_side.w                   ; side 0
	move.w	#$1,fd_count.w                  ; one sector
	bsr.w	read_track                      ; read back
	tst.w	d0                              ; failed?
	bne.s	probe_side_one_single           ; yes: single sided
	moveq	#2,d0                           ; double sided
	rts
probe_side_one_single:
	moveq	#1,d0                           ; single sided
	rts

;------------------------------------------------------------------------------
; floppy_quick_test_drive: the quick test of drive $68A: to track 0 ("F0 Not selected" if it does not
;  answer), tracks 0, 1 and 79 written and read back, then on a double sided drive side 1 tried
;  ("FC Side select error--single sided drive" when it acts single sided).  Out: $49A/$49B non-zero
;  on an error.
;------------------------------------------------------------------------------
floppy_quick_test_drive:	; from: floppy_quick_test
	bsr.w	restore_drive                   ; to track 0
	tst.w	d0                              ; done?
	bne.s	floppy_quick_not_selected       ; no
	move.w	#$0,fd_side.w                   ; side 0
	bsr.w	quick_test_tracks               ; tracks 0, 1, 79
	bne.s	quick_test_drive_done           ; failed
	lea	drive_a_type.w,a0               ; the types
	move.w	fd_drive.w,d0
	move.b	0(a0,d0.w),d1                   ; its type
	btst	#$1,d1                          ; double sided?
	beq.s	quick_test_drive_done           ; no: done
	bsr.s	probe_side_one                  ; side 1 tried
	cmpi.b	#$2,d0                          ; double sided?
	beq.s	quick_test_drive_done           ; yes: done
	cmpi.b	#$0,d0                          ; not writable? (never 0 here)
	beq.s	floppy_quick_test_drive_fail    ; yes
	cmpi.w	#$0,fd_error.w                  ; an FDC error code?
	beq.s	floppy_quick_test_drive_fail    ; no
	lea	msg_side_select_error,a5        ; "FC Side select error--single sided drive"
	bsr.w	print_string
floppy_quick_test_drive_fail:
	lea	test_errors.w,a0                ; the error bytes
	clr.l	d0                              ; this drive's
	move.w	fd_drive.w,d0
	move.b	#$1,0(a0,d0.w)                  ; failed
quick_test_drive_done:
	rts
floppy_quick_not_selected:
	tst.w	fd_drive.w                      ; drive B?
	bne.s	floppy_quick_b_not_selected     ; yes
	bsr.w	print_a_not_selected
	move.b	#$1,test_errors.w               ; drive A failed
	rts
floppy_quick_b_not_selected:
	bsr.w	print_b_not_selected
	move.b	#$1,test_errors_high.w          ; drive B failed
	rts

;------------------------------------------------------------------------------
; quick_test_tracks: tracks 0, 1 and 79 formatted and written (9 sectors from $2000), then read back to
;  $4000 and compared.  Out: Z clear on an error (shown with where it was).  Changes d0-d2, a0-a2.
;------------------------------------------------------------------------------
quick_test_tracks:	; from: floppy_quick_test_drive
	move.w	#$1,fd_interleave.w             ; interleave 1
	move.w	#$9,fd_count.w                  ; 9 sectors
	clr.b	pass_count.w                    ; the first of three
	moveq	#0,d0
quick_test_write_track:
	lea	quick_test_track_list,a0        ; tracks 0, 1, 79
	move.b	pass_count.w,d0
	move.b	0(a0,d0.w),fd_track+1.w         ; this track
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; failed?
	beq.s	quick_test_tracks_write         ; no
	rts
quick_test_tracks_write:
	bsr.w	build_sector_data               ; the test data
	move.w	#$1,fd_sector.w                 ; sector 1
	bsr.w	write_track                     ; written
	tst.w	d0                              ; failed?
	beq.s	quick_test_tracks_next_write    ; no
	rts
quick_test_tracks_next_write:
	addi.b	#$1,pass_count.w                ; the next
	cmpi.b	#$3,pass_count.w                ; three done?
	bne.s	quick_test_write_track          ; no
	clr.b	pass_count.w                    ; the first again
	moveq	#0,d0
quick_test_read_track:
	lea	quick_test_track_list,a0        ; tracks 0, 1, 79
	move.b	pass_count.w,d0
	move.b	0(a0,d0.w),fd_track+1.w         ; this track
	move.l	#$4000,fd_buffer.w              ; read to $4000
	clr.w	fd_retried.w                    ; not retried yet
	bsr.w	read_track                      ; read
	tst.w	d0                              ; failed?
	beq.s	quick_test_tracks_compare       ; no
	rts
quick_test_tracks_compare:
	bsr.w	compare_sector_data             ; compared
	bne.s	print_drive_side_track          ; stopped: where it was shown
	addi.b	#$1,pass_count.w                ; the next
	cmpi.b	#$3,pass_count.w                ; three done?
	bne.s	quick_test_read_track           ; no
	rts

;------------------------------------------------------------------------------
; print_drive_side_track: shows the drive, side and track of an error.  Out: Z clear (an error for the
;  caller).
;------------------------------------------------------------------------------
print_drive_side_track:	; from: floppy_alignment, quick_test_tracks, floppy_random_track_test, print_floppy_error
	bsr.w	print_drive_name
	bsr.w	print_side_number
	bsr.w	print_track_number
	move.w	#$0,ccr                         ; Z clear: an error for the caller
	rts

;------------------------------------------------------------------------------
; floppy_random_track_test: a random track 0-63 (timer A's data register) formatted, written and read
;  back.  A track that fails to format makes it pick another; the try count is set back to 3 each time,
;  so it picks until one formats.  Out: $49A/$49B bit 2 when the write or read fails, Z clear on a
;  compare error.
;------------------------------------------------------------------------------
floppy_random_track_test:	; from: floppy_quick_test
	move.b	#$3,test_index_byte.w           ; three tries
	move.b	$fffffa1f.w,d0                  ; MFP TADR, timer A's count: random
	andi.w	#$3f,d0                         ; 0-63
	cmpi.b	#$4f,d0                         ; above 79? (never)
	bgt.s	floppy_random_track_test        ; yes
	move.w	d0,fd_track.w                   ; the track
	move.w	#$9,fd_count.w                  ; 9 sectors
	move.w	#$1,fd_sector.w                 ; sector 1
	bsr.w	format_track_checked            ; formatted
	tst.w	d0                              ; failed?
	beq.s	floppy_random_track_write       ; no
	subi.b	#$1,test_index_byte.w           ; one try less
	bne.s	floppy_random_track_test        ; tries left: another track (the count set to 3 again)
floppy_random_track_write:
	bsr.w	build_sector_data               ; the test data
	bsr.w	write_track                     ; written
	tst.w	d0                              ; failed?
	bne.s	floppy_random_track_fail        ; yes
	move.l	#$4000,fd_buffer.w              ; read to $4000
	bsr.w	read_track                      ; read
	tst.w	d0                              ; failed?
	bne.s	floppy_random_track_fail        ; yes
	bsr.w	compare_sector_data             ; compared
	bne.s	print_drive_side_track          ; wrong: where it was shown
	rts
floppy_random_track_fail:
	tst.w	fd_drive.w                      ; drive B?
	beq.s	floppy_random_track_fail_a      ; no
	bset	#$2,test_errors_high.w          ; drive B error bit 2
	rts
floppy_random_track_fail_a:
	bset	#$2,test_errors.w               ; drive A error bit 2
	rts

;------------------------------------------------------------------------------
; print_floppy_error: shows the text for the floppy error code $776 (F4 seek, F5 write protected, F7 DMA,
;  F8 DMA count, F9 CRC, FA record not found, FB lost data, FD not ready, "Error reading", -16 "Bad
;  Sector: " with the bad sector list at $762, any other "Error writing"), then the drive, side and
;  track.  Nothing when $776 is 0.  Out: d0 the code.  Changes d1, a2, a5.
;------------------------------------------------------------------------------
print_floppy_error:	; from: floppy_interchange, floppy_copy_protect, format_track_checked, write_track, read_track
	move.w	fd_error.w,d0                   ; the error code
	tst.w	d0                              ; none?
	beq.w	floppy_error_end                ; yes
	dc.w	$0c00,$fffa                     ; cmpi.b	#$fa,d0, -6?
	bne.s	floppy_error_not_seek           ; no
	lea	msg_seek_error,a5               ; "F4 Seek error "
	bra.w	print_floppy_error_show         ; shown
floppy_error_not_seek:
	dc.w	$0c00,$ffef                     ; cmpi.b	#$ef,d0, -17?
	bne.s	floppy_error_not_dma            ; no
	lea	msg_floppy_dma_error,a5         ; "F7 DMA error "
	bra.w	print_floppy_error_show         ; shown
floppy_error_not_dma:
	dc.w	$0c00,$fff8                     ; cmpi.b	#$f8,d0, -8?
	bne.s	floppy_error_not_rnf            ; no
	lea	msg_record_not_found,a5         ; "FA Record not found "
	bra.w	print_floppy_error_show         ; shown
floppy_error_not_rnf:
	dc.w	$0c00,$fffc                     ; cmpi.b	#$fc,d0, -4?
	bne.s	floppy_error_not_crc            ; no
	lea	msg_floppy_crc_error,a5         ; "F9 CRC error "
	bra.s	print_floppy_error_show         ; shown
floppy_error_not_crc:
	dc.w	$0c00,$ffee                     ; cmpi.b	#$ee,d0, -18?
	bne.s	floppy_error_not_count          ; no
	lea	msg_floppy_dma_count_error,a5   ; "F8 DMA count error "
	bra.s	print_floppy_error_show         ; shown
floppy_error_not_count:
	dc.w	$0c00,$fffe                     ; cmpi.b	#$fe,d0, -2?
	bne.s	floppy_error_not_ready          ; no
	lea	msg_drive_not_ready,a5          ; "FD Drive not ready "
	bra.s	print_floppy_error_show         ; shown
floppy_error_not_ready:
	dc.w	$0c00,$fff3                     ; cmpi.b	#$f3,d0, -13?
	bne.s	floppy_error_not_protect        ; no
	lea	msg_write_protected,a5          ; "F5 Write Protected "
	bra.s	print_floppy_error_show         ; shown
floppy_error_not_protect:
	dc.w	$0c00,$fff1                     ; cmpi.b	#$f1,d0, -15?
	bne.s	floppy_error_not_lost           ; no
	lea	msg_lost_data,a5                ; "FB Lost data "
	bra.s	print_floppy_error_show         ; shown
floppy_error_not_lost:
	dc.w	$0c00,$fff5                     ; cmpi.b	#$f5,d0, -11?
	bne.s	floppy_error_not_read           ; no
	lea	msg_error_reading,a5            ; "Error reading"
	bra.s	print_floppy_error_show         ; shown
floppy_error_not_read:
	dc.w	$0c00,$fff0                     ; cmpi.b	#$f0,d0, -16?
	bne.s	floppy_error_write              ; no
	lea	msg_bad_sector,a5               ; "Bad Sector: "
	bsr.w	print_string
	bsr.w	print_drive_side_track
	lea	msg_sector,a5                   ; "Sector "
	bsr.w	print_string
	movea.l	fd_cur_buffer.w,a2
floppy_error_bad_sector_list:
	move.w	(a2)+,d1                        ; the next
	beq.s	floppy_error_newline            ; 0 ends it
	bsr.w	print_hex_byte
	bsr.w	print_space
	bra.s	floppy_error_bad_sector_list    ; on
floppy_error_write:
	lea	msg_error_writing,a5            ; any other: "Error writing"
print_floppy_error_show:
	bsr.w	print_string                    ; the text
	bsr.w	print_drive_side_track          ; where
floppy_error_newline:
	bsr.w	print_newline                   ; the line ended
floppy_error_end:
	move.w	fd_error.w,d0                   ; d0: the error code again
	rts                                     ; Z clear for an error

;------------------------------------------------------------------------------
; build_sector_data: nine 512-byte test sectors at $2000.  Each starts with an ID byte (the cycle's low 6
;  bits, bit 7 drive B, bit 6 side 1, one more each sector), the high byte of the track word $684 (always 0),
;  the first sector number ($687) and the cycle's random byte $297, then 254 words counting up from $BDC6.
;  Changes d0-d4, a0.
;------------------------------------------------------------------------------
build_sector_data:                              ; from: probe_drive_sides, quick_test_tracks, floppy_random_track_test,
                                                ;   compare_sector_data, write_track
	movea.l	#$2000,a0                       ; the buffer
	move.w	#$bdc6,d4                       ; the first data word
	move.b	fd_sector+1.w,d1                ; d1: the first sector number
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
	move.b	fd_track.w,(a0)+                ; the track word's high byte (0)
	move.b	d1,(a0)+                        ; the first sector
	move.b	cycle_random.w,(a0)+            ; the cycle's random byte
build_sector_data_words:
	move.w	d4,(a0)+                        ; a data word
	add.w	#$1,d4                          ; the next value
	dbra	d3,build_sector_data_words      ; the sector's words
	addq.w	#1,d0                           ; the next ID
	dbra	d2,build_sector_data_sector     ; the next sector
	rts                                     ; $2000-$31FF built

;------------------------------------------------------------------------------
; fill_buffer_aa: the 9-sector buffer at $2000 filled with $AA (drive A's interchange data).  Changes d0, d1, a0.
;------------------------------------------------------------------------------
fill_buffer_aa:	; from: floppy_interchange
	move.w	#$aaaa,d1                       ; $AA
	bra.s	fill_buffer_byte                ; on to the fill

;------------------------------------------------------------------------------
; fill_buffer_bb: the 9-sector buffer at $2000 filled with $BB (drive B's interchange data).  Changes d0, d1, a0.
;------------------------------------------------------------------------------
fill_buffer_bb:	; from: floppy_interchange
	move.w	#$bbbb,d1                       ; $BB
fill_buffer_byte:	; from: fill_buffer_aa
	move.l	#$11ff,d0                       ; 4608 bytes
	lea	$2000.w,a0                      ; from $2000
fill_buffer_loop:
	move.b	d1,(a0)+                        ; a byte
	dbra	d0,fill_buffer_loop             ; more?
	rts                                     ; $2000-$31FF filled

;------------------------------------------------------------------------------
; compare_sector_data: the sectors read at $4000 compared with the data built again at $2000.  At each
;  difference: bit 0 of $49A (whichever drive), the background red, "F6 Read compare error " with the two
;  words, the track and the sector; a key waiting then stops it, else it goes on comparing.
;  Out: Z set when it reached the end.  Changes d0-d4, a0, a1.
;------------------------------------------------------------------------------
compare_sector_data:	; from: floppy_exerciser, quick_test_tracks, floppy_random_track_test
	bsr.s	build_sector_data               ; the data written, built again
	lea	$2000.w,a0                      ; written
	lea	$4000.w,a1                      ; read
compare_sector_data_loop:
	cmpm.w	(a0)+,(a1)+                     ; the same?
	beq.s	compare_sector_data_next        ; yes
	bset	#$0,test_errors.w               ; compare error noted
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	lea	msg_read_compare_error,a5       ; "F6 Read compare error "
	bsr.w	print_string                    ; printed
	suba.l	#$2,a0                          ; back to the words
	suba.l	#$2,a1                          ; (both)
	move.w	(a0)+,d1                        ; written
	bsr.w	print_hex_word                  ; as hex
	bsr.w	print_space                     ; a space
	move.w	(a1)+,d1                        ; read
	bsr.w	print_hex_word                  ; as hex
	bsr.w	print_space                     ; a space
	bsr.w	print_track_number              ; "Track nn"
	bsr.w	print_sector_number             ; "Sector nn"
	bsr.w	print_newline                   ; the line ended
	movem.l	a0-a1,-(sp)                     ; kept
	bsr.w	key_waiting                     ; a key pressed?
	movem.l	(sp)+,a0-a1                     ; back
	tst.w	d0                              ; a key?
	beq.s	compare_sector_data_next        ; no: go on
	rts                                     ; yes: stopped
compare_sector_data_next:
	cmpa.l	#$3200,a0                       ; 9 sectors done?
	blt.s	compare_sector_data_loop        ; no
	rts                                     ; Z: all compared

;------------------------------------------------------------------------------
; format_track_checked: formats track $684 side $682 of drive $68A, showing "Formatting".  The track's bad
;  mark ($6AC table, side 1 from entry 80) is cleared first.  A failure marks the track bad (then the write
;  and read skip it), shows the error, counts it in $750, flags the drive and steps it to track 0; while
;  drives are probed ($752) it only returns.  A -16 (bad sectors) with only one bad sector is let through.
;  Out: d0 0 when formatted, else the error code with Z clear.
;------------------------------------------------------------------------------
format_track_checked:                           ; from: floppy_interchange, floppy_exerciser, floppy_copy_protect,
                                                ;   probe_drive_sides, probe_side_one, quick_test_tracks, 1 more
	lea	msg_formatting,a5               ; "Formatting "
	bsr.w	print_floppy_action             ; on the status line
	lea	fd_bad_tracks.w,a2              ; the bad track table
	clr.l	d2                              ; the track
	move.w	fd_track.w,d2                   ; the track
	tst.w	fd_side.w                       ; side 1?
	beq.s	format_track_unmark             ; no
	add.w	#$50,d2                         ; side 1's marks 80 on
format_track_unmark:
	clr.b	0(a2,d2.w)                      ; not bad
	bsr.w	floppy_format_track             ; formatted, then each sector read back
	tst.w	d0                              ; failed?
	beq.s	format_track_done               ; no
	tst.b	fd_probing.w                    ; probing the drives?
	beq.s	format_track_failed             ; no
	rts                                     ; yes: no report
format_track_failed:
	lea	fd_bad_tracks.w,a2              ; the bad track table
	clr.l	d2                              ; the track
	move.w	fd_track.w,d2                   ; the track
	tst.w	fd_side.w                       ; side 1?
	beq.s	format_track_mark               ; no
	add.w	#$50,d2                         ; side 1's marks 80 on
format_track_mark:
	move.b	#$ff,0(a2,d2.w)                 ; marked bad
	bsr.w	print_floppy_error              ; the error shown
	move.w	fd_error.w,d0                   ; d0: the error code
	cmpi.w	#$fff0,fd_error.w               ; bad sectors?
	bne.s	format_track_count_error        ; no
	movea.l	fd_cur_buffer.w,a2              ; the list of bad sector numbers
	adda.l	#$2,a2                          ; a second one?
	tst.w	(a2)                            ; a second bad sector?
	beq.s	format_track_done               ; no: let through
format_track_count_error:
	bsr.w	flag_drive_error                ; this drive failed
	addi.w	#$1,fd_format_errors.w          ; one more format error
	move.w	d0,-(sp)                        ; the code kept
	bsr.w	restore_drive                   ; to track 0
	move.w	(sp)+,d0                        ; the code
	andi.b	#$1b,ccr                        ; Z clear: failed
format_track_done:
	rts                                     ; Z: formatted

;------------------------------------------------------------------------------
; write_track: writes the nine test sectors (build_sector_data) to track $684 side $682 of drive $68A,
;  showing "Writing".  A track marked bad is skipped.  A failure shows the error, steps to track 0, counts
;  it in $74E and tries once more; a second failure is a "Hard error" (the drive flagged), a success at the
;  second try a "Soft Error".  Out: d0 0 or the error code.
;------------------------------------------------------------------------------
write_track:	; from: floppy_exerciser, floppy_copy_protect, quick_test_tracks, floppy_random_track_test
	move.l	#$2000,fd_buffer.w              ; the buffer at $2000
	clr.w	fd_retried.w                    ; no retry yet
	lea	fd_bad_tracks.w,a2              ; the bad track table
	clr.l	d2                              ; the track
	move.w	fd_track.w,d2                   ; the track
	tst.w	fd_side.w                       ; side 1?
	beq.s	write_track_check_mark          ; no
	add.w	#$50,d2                         ; side 1's marks 80 on
write_track_check_mark:
	tst.b	0(a2,d2.w)                      ; marked bad?
	bne.s	write_track_written             ; yes: skipped
	lea	msg_writing,a5                  ; "Writing    "
	bsr.w	print_floppy_action             ; on the status line
	bsr.w	build_sector_data               ; the sector data
write_track_try:
	bsr.w	floppy_write_sectors            ; written
	tst.w	d0                              ; failed?
	beq.s	write_track_written             ; no
	bsr.w	print_floppy_error              ; the error shown
	move.w	d0,-(sp)                        ; the code kept
	bsr.w	restore_drive                   ; to track 0
	move.w	(sp)+,d0                        ; the code
	addi.w	#$1,fd_write_errors.w           ; one more write error
	tst.w	fd_retried.w                    ; the second try?
	beq.s	write_track_retry               ; no
	bsr.w	flag_drive_error                ; this drive failed
	lea	msg_hard_error,a5               ; "Hard error"
	bsr.w	print_string                    ; printed
	bra.s	write_track_done                ; done
write_track_retry:
	move.w	#$1,fd_retried.w                ; the second try
	bra.s	write_track_try                 ; once more
write_track_written:
	tst.w	fd_retried.w                    ; written at the second try?
	beq.s	write_track_done                ; no
	lea	msg_soft_error,a5               ; "Soft Error"
	bsr.w	print_string                    ; printed
write_track_done:
	rts                                     ; d0: 0 or the error code

;------------------------------------------------------------------------------
; read_track: reads the nine sectors of track $684 side $682 of drive $68A to $4000, showing "Reading".
;  A track marked bad is skipped (d0 0).  A failure shows the error, steps to track 0, counts it in $74C and
;  tries once more; a second failure is a "Hard error" (the drive flagged), a success at the second try a
;  "Soft Error".  While drives are probed ($752) a failure only returns.  Out: d0 0 or the error code.
;------------------------------------------------------------------------------
read_track:                                     ; from: floppy_interchange, floppy_exerciser, floppy_copy_protect,
                                                ;   probe_side_one, quick_test_tracks, floppy_random_track_test
	move.l	#$4000,fd_buffer.w              ; the buffer at $4000
	lea	fd_bad_tracks.w,a2              ; the bad track table
	clr.l	d2                              ; the track
	move.w	fd_track.w,d2                   ; the track
	tst.w	fd_side.w                       ; side 1?
	beq.s	read_track_check_mark           ; no
	add.w	#$50,d2                         ; side 1's marks 80 on
read_track_check_mark:
	tst.b	0(a2,d2.w)                      ; marked bad?
	bne.s	read_track_read                 ; yes: skipped
	move.w	#$0,fd_retried.w                ; no retry yet
	lea	msg_reading,a5                  ; "Reading    "
	bsr.w	print_floppy_action             ; on the status line
read_track_try:
	bsr.w	read_sectors                    ; read
	tst.w	d0                              ; failed?
	beq.s	read_track_read                 ; no
	tst.b	fd_probing.w                    ; probing the drives?
	beq.s	read_track_failed               ; no
	rts                                     ; yes: no report
read_track_failed:
	move.w	d0,-(sp)                        ; the code kept
	bsr.w	print_floppy_error              ; the error shown
	bsr.w	restore_drive                   ; to track 0
	move.w	(sp)+,d0                        ; the code
	addi.w	#$1,fd_read_errors.w            ; one more read error
	tst.w	fd_retried.w                    ; the second try?
	beq.s	read_track_retry                ; no
	bsr.w	flag_drive_error                ; this drive failed
	lea	msg_hard_error,a5               ; "Hard error"
	bsr.w	print_string                    ; printed
	rts                                     ; d0: the error code
read_track_retry:
	move.w	#$1,fd_retried.w                ; the second try
	bra.s	read_track_try                  ; once more
read_track_read:
	clr.l	d0                              ; read
	tst.w	fd_retried.w                    ; read at the second try?
	beq.s	read_track_done                 ; no
	lea	msg_soft_error,a5               ; "Soft Error"
	bsr.w	print_string                    ; printed
read_track_done:
	rts                                     ; d0: 0

;------------------------------------------------------------------------------
; flag_drive_error: the error byte of drive $68A ($49A drive A, $49B drive B) set to 1, the background red.
;  Changes nothing else.
;------------------------------------------------------------------------------
flag_drive_error:	; from: format_track_checked, write_track, read_track
	movem.l	d0/a0,-(sp)                     ; kept
	lea	test_errors.w,a0                ; the drives' error bytes
	clr.l	d0                              ; this drive's
	move.w	fd_drive.w,d0                   ; the drive
	move.b	#$1,0(a0,d0.w)                  ; failed
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	movem.l	(sp)+,d0/a0                     ; back
	rts                                     ; d0, a0 kept

;------------------------------------------------------------------------------
; print_b_not_selected: "Disk B: F0 Not selected ", the background red.  Changes a5.
;------------------------------------------------------------------------------
print_b_not_selected:	; from: floppy_interchange, floppy_exerciser, floppy_quick_test_drive
	lea	msg_disk_b,a5                   ; "Disk B: "
	bra.s	print_not_selected              ; on to the message

;------------------------------------------------------------------------------
; print_a_not_selected: "Disk A: F0 Not selected ", the background red.  Changes a5.
;------------------------------------------------------------------------------
print_a_not_selected:	; from: floppy_interchange, floppy_exerciser, floppy_quick_test_drive
	lea	msg_disk_a,a5                   ; "Disk A: "
print_not_selected:	; from: print_b_not_selected
	bsr.w	print_string                    ; the drive printed
	lea	msg_not_selected,a5             ; "F0 Not selected "
	bsr.w	print_string                    ; printed
	bsr.w	print_newline                   ; the line ended
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	rts                                     ; done

;------------------------------------------------------------------------------
; restore_drive: steps drive $68A to track 0 with step rate 3 (restore; when the track 0 signal does not
;  come, a seek to track 10 and a restore again).  In: d0 the error code for a failure.  Out: d0.l 0 when
;  at track 0, else the error code (Z clear), through floppy_exit.  When it fails the drive's track is left
;  unknown ($FF00), so the next floppy call restores it again.
;------------------------------------------------------------------------------
restore_drive:                                  ; from: floppy_alignment, floppy_interchange, floppy_exerciser,
                                                ;   floppy_copy_protect, floppy_speed_test, probe_drive_sides_restored,
                                                ;   5 more
	lea	drive_a_head.w,a1               ; drive A's head block
	tst.w	fd_drive.w                      ; drive B?
	beq.s	restore_drive_select            ; no
	lea	drive_b_head.w,a1               ; drive B's head block
restore_drive_select:
	move.w	#$3,2(a1)                       ; step rate 3
	clr.w	0(a1)                           ; track 0
	bsr.w	floppy_set_up                   ; the call set up
	bsr.w	floppy_select_drive             ; drive and side selected
	move.w	#$ff00,0(a1)                    ; the head position not known
	bsr.w	floppy_restore                  ; to track 0
	beq.s	restore_drive_result            ; yes
	moveq	#10,d7                          ; to track 10
	bsr.w	floppy_seek                     ; out to track 10
	bne.s	restore_drive_failed            ; failed
	bsr.w	floppy_restore                  ; and back to track 0
restore_drive_result:
	beq.w	floppy_exit_ok                  ; at track 0: OK
restore_drive_failed:
	bra.w	floppy_exit_error               ; the error code

;------------------------------------------------------------------------------
; read_alignment_track: reads the $688 sectors of track $684 side $682 to $4000 with one multiple-sector
;  read command ($90), for the alignment disk; only a time-out (-2) or a failed seek (-6) is an error, the
;  status is read but not checked.  Out: d0.l 0 or the error code.
;------------------------------------------------------------------------------
read_alignment_track:	; from: floppy_alignment
	move.w	#$fff5,d0                       ; "Error reading" code
	move.l	#$4000,fd_buffer.w              ; the buffer at $4000
	bsr.w	floppy_set_up                   ; the call set up
	bsr.w	floppy_select_drive             ; drive and side selected
	bsr.w	floppy_seek_verify              ; to the track, verified
	bne.w	floppy_exit_error               ; failed
	move.w	#$90,(a6)                       ; FIFO cleared, read
	move.w	#$190,(a6)                      ; (the direction toggled)
	nop                                     ; (a pause)
	move.w	#$90,(a6)                       ; sector count register
	move.w	fdc_count.w,$ffff8604.w         ; DMA sector count / FDC access
	move.w	#$80,(a6)                       ; FDC command register
	move.w	#$90,d7                         ; read multiple sectors
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; time-out count
	movea.l	fdc_buffer_end.w,a2             ; the buffer's end (not used)
read_alignment_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, the FDC done (GPIP5 low)?
	beq.s	read_alignment_done             ; yes
	subq.l	#1,d7                           ; time-out?
	bne.s	read_alignment_wait             ; no
	move.w	#$fffe,fd_error.w               ; -2: time-out
	bsr.w	floppy_force_interrupt          ; the command stopped
	bra.w	floppy_exit_error               ; failed
read_alignment_done:
	move.w	#$90,(a6)                       ; DMA status
	move.w	(a6),d0                         ; read
	move.w	#$80,(a6)                       ; FDC status
	bsr.w	fdc_read_d0                     ; read (not checked)
	bra.w	floppy_exit_ok                  ; OK

;------------------------------------------------------------------------------
; read_sectors: reads $688 sectors from sector $686 of track $684 side $682 of drive $68A to the buffer
;  $68C, one read sector command ($80) each, then checks the DMA address reached the buffer's end.
;  Out: d0.l 0, or the error code in d0 and $776: -2 time-out, -6 seek error, -17 DMA error,
;  -13/-8/-4/-15 from the FDC status, -18 DMA count.
;------------------------------------------------------------------------------
read_sectors:	; from: read_track
	move.w	#$fff5,d0                       ; "Error reading" code
	bsr.w	floppy_set_up                   ; the call set up
	bsr.w	floppy_select_drive             ; drive and side selected
	bsr.w	floppy_seek_verify              ; to the track, verified
	bne.w	floppy_exit_error               ; failed
read_sectors_next:
	move.w	#$90,(a6)                       ; FIFO cleared, read
	move.w	#$190,(a6)                      ; (the direction toggled)
	nop                                     ; (a pause)
	move.w	#$90,(a6)                       ; sector count register
	move.w	fdc_count.w,$ffff8604.w         ; DMA sector count / FDC access
	move.w	#$80,(a6)                       ; FDC command register
	move.w	#$80,d7                         ; read sector
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; time-out count
	movea.l	fdc_buffer_end.w,a2             ; the buffer's end
read_sectors_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, the FDC done (GPIP5 low)?
	beq.s	read_sectors_dma_status         ; yes
	subq.l	#1,d7                           ; time-out?
	bne.s	read_sectors_wait               ; no
	move.w	#$fffe,fd_error.w               ; -2: time-out
	bsr.w	floppy_force_interrupt          ; the command stopped
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
	beq.s	read_sectors_step               ; no
	bsr.w	fdc_status_error                ; the code for it
	bra.w	floppy_exit_error               ; failed
read_sectors_step:
	addq.w	#1,fd_cur_sector.w              ; the next sector
	addi.l	#$200,fd_cur_buffer.w           ; 512 bytes on
	subq.w	#1,fdc_count.w                  ; all read?
	beq.s	read_sectors_check_dma          ; yes
	bsr.w	floppy_set_sector_dma           ; the sector number and DMA address
	bra.w	read_sectors_next               ; read it
read_sectors_check_dma:
	move.b	$ffff8609.w,dma_address_read+1.w ; DMA base high
	move.b	$ffff860b.w,dma_address_read+2.w ; DMA base mid
	move.b	$ffff860d.w,dma_address_read+3.w ; DMA base low
	cmpa.l	dma_address_read.w,a2           ; the DMA address at the buffer's end?
	beq.w	floppy_exit_ok                  ; yes: OK
	move.w	#$ffee,fd_error.w               ; -18: DMA count error
	bra.w	floppy_exit_error               ; failed

;------------------------------------------------------------------------------
; fdc_status_error: the floppy error code for an FDC status into $776: -13 write protected, -8 record
;  not found, -4 CRC, -15 lost data, else the call's own code $774.  In: d0 the status.
;  Out: d1 and $776 the code (Z clear).  Changes d1.
;------------------------------------------------------------------------------
fdc_status_error:                               ; from: read_sectors, floppy_write_sectors, floppy_wipe_track,
                                                ;   floppy_format_write, floppy_verify_list
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
	move.w	fdc_default_error.w,d1          ; none of them: the call's own code
fdc_status_error_store:
	move.w	d1,fd_error.w                   ; the error code
	rts                                     ; Z clear

;------------------------------------------------------------------------------
; floppy_write_sectors: writes $688 sectors from sector $686 of track $684 side $682 of drive $68A from the
;  buffer $68C, one write sector command ($A0) at a time.
;  Out: d0.l 0 or a negative error code (-10 write fault, -13 write protected, -8 not found, -4 CRC,
;  -15 lost data, -2 time-out, -6 seek error).  Ends through floppy_exit (the VBL watches the motor).
;------------------------------------------------------------------------------
floppy_write_sectors:	; from: floppy_interchange, probe_drive_sides, write_track
	moveq	#-10,d0                         ; -10: write fault unless the status says otherwise
	bsr.w	floppy_set_up                   ; the call set up
	bsr.w	floppy_select_drive             ; drive and side selected
	bsr.w	floppy_seek_verify              ; to the track, verified
	bne.w	floppy_exit_error               ; failed
floppy_write_next:
	move.w	#$190,(a6)                      ; DMA to write: the direction toggled to clear the DMA status
	move.w	#$90,(a6)
	move.w	#$190,(a6)                      ; DMA to write
	move.w	#$1,d7                          ; one sector
	bsr.w	fdc_write_d7                    ; the sector count
	move.w	#$180,(a6)                      ; the FDC command register
	move.w	#$a0,d7                         ; write sector
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; the time-out
floppy_write_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt (active low)?
	beq.s	floppy_write_status             ; yes: done
	subq.l	#1,d7                           ; the time-out counted down
	bne.s	floppy_write_wait               ; keep waiting
	move.w	#$fffe,fd_error.w               ; -2: time-out
	bsr.w	floppy_force_interrupt          ; the command stopped
	bra.w	floppy_exit_error               ; failed
floppy_write_status:
	move.w	#$180,(a6)                      ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	bsr.w	fdc_status_error                ; error code from the status
	and.b	#$5c,d0                         ; write protect, not found, CRC or lost data?
	bne.w	floppy_exit_error               ; failed
	addq.w	#1,fd_cur_sector.w              ; the next sector
	addi.l	#$200,fd_cur_buffer.w           ; 512 bytes on
	subq.w	#1,fdc_count.w                  ; all written?
	beq.w	floppy_exit_ok                  ; yes: OK
	bsr.w	floppy_set_sector_dma           ; the sector number and DMA address
	bra.s	floppy_write_next               ; the next sector

;------------------------------------------------------------------------------
; floppy_format_track: formats track $684 side $682 of drive $68A with nine sectors, every data word
;  $67E ($688 is the sector count for the read back, $680 the interleave, copied but not used).  The track
;  image is built at $2000.  The track is formatted with sectors 10-18 first and those are read back, then
;  formatted again with sectors 1-9 and those are read back, so an old format cannot pass for a new one.
;  The numbers of the bad sectors are listed at $2000, ending with 0.
;  Out: d0.l 0, -16 when a sector is bad, or the error code.
;------------------------------------------------------------------------------
floppy_format_track:	; from: format_track_checked
	moveq	#-10,d0                         ; -10: write fault
	move.l	#$2000,fd_buffer.w              ; the track image at $2000
	bsr.w	floppy_set_up                   ; the call set up
	bsr.w	floppy_select_drive             ; drive and side selected
	move.w	fd_count.w,fdc_format_count.w   ; the sectors to read back
	move.w	fd_interleave.w,fdc_interleave.w ; the interleave (not used)
	move.w	fd_fill_word.w,fdc_fill_word.w  ; the data word
	bsr.w	floppy_seek_track               ; to the track, no verify
	bne.w	floppy_exit_error               ; failed
	move.w	fdc_track.w,0(a1)               ; the drive is there
	move.w	#$a,fd_cur_sector.w             ; sectors numbered from 10
	bsr.w	floppy_format_write             ; the track written
	bne.w	floppy_exit_error               ; failed
	move.w	fdc_format_count.w,fdc_count.w  ; the sectors to read back
	bsr.w	floppy_verify_list              ; read back, the bad ones listed
	movea.l	fd_cur_buffer.w,a2              ; the list
	tst.w	(a2)                            ; empty?
	beq.s	floppy_format_track_from_1
	move.w	#$fff0,fd_error.w               ; -16: bad sectors
	bra.w	floppy_exit_error               ; failed
floppy_format_track_from_1:
	move.w	#$1,fd_cur_sector.w             ; sectors numbered from 1
	bsr.w	floppy_format_write             ; format the track
	bne.w	floppy_exit_error               ; failed
	move.w	fdc_format_count.w,fdc_count.w  ; the sectors to read back
	bsr.w	floppy_verify_list              ; read back, the bad ones listed
	movea.l	fd_cur_buffer.w,a2              ; the list
	tst.w	(a2)                            ; empty?
	beq.w	floppy_exit_ok                  ; empty: OK
	move.w	#$fff0,fd_error.w               ; -16: bad sectors
	bra.w	floppy_exit_error               ; failed

;------------------------------------------------------------------------------
; floppy_wipe_track: not reached.  Writes a blank track (all $00) from the track image buffer.
;  Out: d7 1 (Z clear) on a time-out or DMA error, else Z from the FDC status check.
;------------------------------------------------------------------------------
floppy_wipe_track:
	move.w	#$fff6,fdc_default_error.w      ; -10: write fault
	move.w	#$1,d3                          ; sector 1 (not used)
	movea.l	fd_cur_buffer.w,a2              ; the buffer
	move.w	#$3b,d1                         ; 60 bytes
	move.b	#$0,d0                          ; of $00
	bsr.w	floppy_fill_bytes               ; filled
	move.w	#$154d,d1                       ; 5,454 bytes
	move.b	#$0,d0                          ; of $00
	bsr.w	floppy_fill_bytes               ; filled
	move.w	#$578,d1                        ; 1,401 bytes
	move.b	#$0,d0                          ; of $00
	bsr.w	floppy_fill_bytes               ; filled
	move.b	fd_cur_buffer+3.w,$ffff860d.w   ; DMA base low
	move.b	fd_cur_buffer+2.w,$ffff860b.w   ; DMA base mid
	move.b	fd_cur_buffer+1.w,$ffff8609.w   ; DMA base high
	move.w	#$190,(a6)                      ; DMA to write, the status cleared
	move.w	#$90,(a6)
	move.w	#$190,(a6)                      ; (the direction toggled)
	move.w	#$1f,d7                         ; 31 sectors of DMA
	bsr.w	fdc_write_d7                    ; sent
	move.w	#$180,(a6)                      ; the FDC command register
	move.w	#$f0,d7                         ; write track
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; the time-out
floppy_wipe_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt?
	beq.s	floppy_wipe_status              ; yes
	subq.l	#1,d7                           ; the time-out counted down
	bne.s	floppy_wipe_wait                ; keep waiting
	move.w	#$fffe,fd_error.w               ; -2: time-out
	bsr.w	floppy_force_interrupt          ; the command stopped
floppy_wipe_failed:
	moveq	#1,d7                           ; failed
	rts                                     ; Z clear
floppy_wipe_status:
	move.w	#$190,(a6)                      ; the DMA status
	move.w	(a6),d0                         ; read
	btst	#$0,d0                          ; DMA error?
	beq.s	floppy_wipe_failed              ; yes
	move.w	#$180,(a6)                      ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	and.b	#$44,d0                         ; write protect or lost data?
	beq.s	floppy_wipe_end                 ; no
	bsr.w	fdc_status_error                ; its error code
floppy_wipe_end:
	rts                                     ; Z: written

;------------------------------------------------------------------------------
; floppy_format_write: builds the image of a nine-sector track in the buffer $762 and writes it with
;  write track ($F0).  Each sector: gap, sync, the ID (track $75B, side $75F, sector, size 2), gap, sync,
;  the data mark and 256 copies of the data word $76E, then a gap.  In: $75C the first sector number,
;  numbered up from it.  Out: Z set when written; else Z clear and $776 the error code (-2 time-out,
;  -10 DMA error, or from the FDC status).  Changes d0, d1, d3, d7, a2.
;------------------------------------------------------------------------------
floppy_format_write:	; from: floppy_format_track
	move.w	fd_cur_sector.w,d3              ; d3: the first sector number
	move.w	#$9,fdc_count.w                 ; 9 sectors
	move.w	#$fff6,fdc_default_error.w      ; -10: write fault
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
	move.b	fdc_track+1.w,(a2)+             ; the track
	move.b	fdc_side+1.w,(a2)+              ; the side
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
floppy_format_data_word:
	move.b	fdc_fill_word.w,(a2)+           ; the data word's high byte
	move.b	fdc_fill_word+1.w,(a2)+         ; and its low byte
	dbra	d1,floppy_format_data_word      ; the next word
	move.b	#$f7,(a2)+                      ; the data CRC
	move.w	#$27,d1                         ; 40 bytes
	move.b	#$4e,d0                         ; of $4E
	bsr.w	floppy_fill_bytes               ; filled
	add.w	#$1,d3                          ; the next sector number
	subi.w	#$1,fdc_count.w                 ; all 9?
	bne.s	floppy_format_sector            ; the next sector
	move.w	#$578,d1                        ; the end of the track: 1,401 bytes
	move.b	#$4e,d0                         ; of $4E
	bsr.w	floppy_fill_bytes               ; filled
	move.b	fd_cur_buffer+3.w,$ffff860d.w   ; DMA base low
	move.b	fd_cur_buffer+2.w,$ffff860b.w   ; DMA base mid
	move.b	fd_cur_buffer+1.w,$ffff8609.w   ; DMA base high
	move.w	#$190,(a6)                      ; DMA to write, the status cleared
	move.w	#$90,(a6)
	move.w	#$190,(a6)                      ; (the direction toggled)
	move.w	#$1f,d7                         ; 31 sectors of DMA
	bsr.w	fdc_write_d7                    ; sent
	move.w	#$180,(a6)                      ; the FDC command register
	move.w	#$f0,d7                         ; write track
	bsr.w	fdc_write_d7                    ; sent
	move.l	#$40000,d7                      ; the time-out
floppy_format_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, FDC interrupt?
	beq.s	floppy_format_status            ; yes
	subq.l	#1,d7                           ; the time-out counted down
	bne.s	floppy_format_wait              ; keep waiting
	move.w	#$fffe,fd_error.w               ; -2: time-out
	bsr.w	floppy_force_interrupt          ; the command stopped
floppy_format_failed:
	moveq	#1,d7                           ; failed
	rts                                     ; Z clear
floppy_format_status:
	move.w	#$190,(a6)                      ; the DMA status
	move.w	(a6),d0                         ; read
	btst	#$0,d0                          ; DMA error?
	beq.s	floppy_format_failed            ; yes
	move.w	#$180,(a6)                      ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	and.b	#$44,d0                         ; write protect or lost data?
	beq.s	floppy_format_end               ; no
	bsr.w	fdc_status_error                ; its error code
floppy_format_end:
	rts                                     ; Z: written

;------------------------------------------------------------------------------
; floppy_fill_bytes: stores d0.b d1+1 times at a2 and on.  Out: a2 past them, d1 -1.
;------------------------------------------------------------------------------
floppy_fill_bytes:	; from: floppy_wipe_track, floppy_format_write
	move.b	d0,(a2)+                        ; the byte stored
	dbra	d1,floppy_fill_bytes            ; the next
	rts                                     ; done

;------------------------------------------------------------------------------
; floppy_verify_sectors: reads back $688 sectors from sector $686 of the track and lists the bad ones at
;  the buffer $68C.  Not called.  Out: d0.l 0 or the error code.
;------------------------------------------------------------------------------
floppy_verify_sectors:
	moveq	#-11,d0                         ; -11: read fault
	bsr.w	floppy_set_up                   ; the parameters taken
	bsr.w	floppy_select_drive             ; drive and side selected
	bsr.w	floppy_seek_verify              ; to the track, verified
	bne.w	floppy_exit_error               ; failed
	bsr.w	floppy_verify_list              ; the sectors read back
	bra.w	floppy_exit_ok                  ; OK

;------------------------------------------------------------------------------
; floppy_verify_list: reads $760 sectors from sector $75C one at a time to the buffer $762 + 512, and lists
;  the numbers of those that fail (time-out, DMA error, not found, CRC, lost data) as words at the buffer
;  $762, ending with 0.  Out: $75C past the last sector, $760 0.  Changes d0, d1, d7, a2.
;------------------------------------------------------------------------------
floppy_verify_list:	; from: floppy_format_track, floppy_verify_sectors
	move.w	#$fff5,fdc_default_error.w      ; -11: read fault
	movea.l	fd_cur_buffer.w,a2              ; a2: the list
	addi.l	#$200,fd_cur_buffer.w           ; the sectors read past it
floppy_verify_list_next:
	move.w	#$2,fdc_tries.w                 ; (not read)
	move.w	#$84,(a6)                       ; the sector register
	move.w	fd_cur_sector.w,d7              ; the sector
	bsr.w	fdc_write_d7                    ; sent
	move.b	fd_cur_buffer+3.w,$ffff860d.w   ; DMA base low
	move.b	fd_cur_buffer+2.w,$ffff860b.w   ; DMA base mid
	move.b	fd_cur_buffer+1.w,$ffff8609.w   ; DMA base high
	move.w	#$90,(a6)                       ; DMA to read, the status cleared
	move.w	#$190,(a6)                      ; (the direction toggled)
	move.w	#$90,(a6)
	move.w	#$1,d7                          ; one sector
	bsr.w	fdc_write_d7                    ; sent
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
	bra.s	floppy_verify_list_bad          ; a bad sector
floppy_verify_status:
	move.w	#$90,(a6)                       ; the DMA status
	move.w	(a6),d0                         ; read
	btst	#$0,d0                          ; DMA error?
	beq.s	floppy_verify_list_bad          ; yes: a bad sector
	move.w	#$80,(a6)                       ; the FDC status register
	bsr.w	fdc_read_d0                     ; read
	bsr.w	fdc_status_error                ; its error code
	and.b	#$1c,d0                         ; not found, CRC or lost data?
	bne.s	floppy_verify_list_bad          ; yes: a bad sector
floppy_verify_list_step:
	addq.w	#1,fd_cur_sector.w              ; the next sector
	subq.w	#1,fdc_count.w                  ; all read?
	bne.w	floppy_verify_list_next         ; the next sector
	subi.l	#$200,fd_cur_buffer.w           ; the buffer back
	clr.w	(a2)                            ; the list ended
	rts                                     ; done
floppy_verify_list_bad:
	move.w	fd_cur_sector.w,(a2)+           ; its number listed
	bra.s	floppy_verify_list_step         ; on to the next

;------------------------------------------------------------------------------
; floppy_set_up: starts a floppy call.  In: d0 the default error code.  Interrupts at IPL 4 (the VBL's
;  motor watch off, $295 cleared), a5 = 0, a6 = the DMA mode register, the floppy parameters ($68A drive,
;  $684 track, $682 side, $686 sector, $688 count, $68C buffer) copied to the working ones ($758-$762), the
;  buffer's end into $766, a1 = the drive's head block ($79C drive A, $7A0 drive B: track, step rate).
;  When the drive's track is not known the head is restored (once more after a seek to track 10); when
;  that fails the track stays unknown ($FF00).  Changes d0, d1, d2, d6, d7, a0.
;------------------------------------------------------------------------------
floppy_set_up:                                  ; from: restore_drive, read_alignment_track, read_sectors,
                                                ;   floppy_write_sectors, floppy_format_track, floppy_verify_sectors
	move.w	#$2400,sr                       ; no VBL
	clr.b	floppy_motor_watch.w            ; the motor watch off
	movea.l	#$0,a5                          ; a5 = 0
	lea	$ffff8606.w,a6                  ; DMA mode / status, a6: the DMA mode register
	move.w	d0,fdc_default_error.w          ; the call's own error code
	move.w	d0,fd_error.w                   ; the error code so far
	move.l	fd_buffer.w,fd_cur_buffer.w     ; the buffer
	move.w	fd_drive.w,fdc_drive.w          ; the drive
	move.w	fd_sector.w,fd_cur_sector.w     ; the first sector
	move.w	fd_track.w,fdc_track.w          ; the track
	move.w	fd_side.w,fdc_side.w            ; the side
	move.w	fd_count.w,fdc_count.w          ; the sector count
	move.w	#$2,fdc_tries.w                 ; (not read)
	lea	drive_a_head.w,a1               ; drive A's head block
	tst.w	fdc_drive.w                     ; drive B?
	beq.s	floppy_set_up_end_address       ; no
	lea	drive_b_head.w,a1               ; drive B's head block
floppy_set_up_end_address:
	moveq	#0,d7                           ; the buffer's length
	move.w	fdc_count.w,d7                  ; the sectors
	lsl.w	#8,d7                           ; times 512
	lsl.w	#1,d7                           ; (512 a sector)
	movea.l	fd_cur_buffer.w,a0              ; the buffer
	adda.l	d7,a0                           ; past its end
	move.l	a0,fdc_buffer_end.w             ; its end
	tst.w	0(a1)                           ; the track known?
	bpl.s	floppy_set_up_done              ; yes
	bsr.w	floppy_select_drive             ; drive and side selected
	clr.w	0(a1)                           ; at track 0 for now
	bsr.w	floppy_restore                  ; restore
	beq.s	floppy_set_up_done              ; at track 0: done
	moveq	#10,d7                          ; else out to track 10
	bsr.w	floppy_seek                     ; seek to track 10
	bne.s	floppy_set_up_unknown_track     ; failed
	bsr.w	floppy_restore                  ; and restore again
	beq.s	floppy_set_up_done              ; at track 0: done
floppy_set_up_unknown_track:
	move.w	#$ff00,0(a1)                    ; the track not known
floppy_set_up_done:
	rts                                     ; a1: the head block
floppy_exit_error:                              ; from: restore_drive, read_alignment_track, read_sectors,
                                                ;   floppy_write_sectors, floppy_format_track, floppy_verify_sectors
	move.w	fd_error.w,d0                   ; the error code
	ext.l	d0                              ; as a long
	bra.s	floppy_exit                     ; on to the end

;------------------------------------------------------------------------------
; floppy_exit_ok: ends a floppy call with d0.l 0; floppy_exit_error with the error code $776 in d0.l;
;  floppy_exit with d0.l.  A seek to the track the head is on is sent, then the VBL is pointed at
;  floppy_motor_vbl, which deselects the drive when the motor has stopped.  Out: d0.l, IPL 2.
;------------------------------------------------------------------------------
floppy_exit_ok:                                 ; from: restore_drive, read_alignment_track, read_sectors,
                                                ;   floppy_write_sectors, floppy_format_track, floppy_verify_sectors
	clr.l	d0                              ; OK
	clr.w	fd_error.w                      ; no error
floppy_exit:	; from: floppy_set_up
	move.l	d0,-(sp)                        ; the result kept
	move.w	#$86,(a6)                       ; the data register
	move.w	0(a1),d7                        ; the drive's track
	bsr.w	fdc_write_d7                    ; sent
	move.w	#$10,d6                         ; seek
	bsr.w	floppy_command                  ; sent
	bset	#$7,floppy_motor_watch.w        ; the motor watch on
	move.l	#floppy_motor_vbl,$70.w         ; VBL vector, by the VBL
	move.w	#$2200,sr                       ; the VBL on
	move.l	(sp)+,d0                        ; the result
	rts                                     ; d0.l: 0 or the error code

;------------------------------------------------------------------------------
; floppy_motor_vbl: VBL handler while a floppy call has ended: once the FDC's motor-on bit is clear
; the drives are deselected and the program's own VBL handler put back.
;------------------------------------------------------------------------------
floppy_motor_vbl:	; from: floppy_exit_ok
	movem.l	d0-d7,-(sp)                     ; kept
	btst	#$7,floppy_motor_watch.w        ; the motor watch on?
	beq.s	floppy_motor_vbl_end            ; no
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the FDC status register
	bsr.w	fdc_read_d0                     ; read
	btst	#$7,d0                          ; the motor still on?
	bne.s	floppy_motor_vbl_end            ; yes
	move.b	#$6,d0                          ; both drives deselected
	bsr.w	psg_select_drive_side           ; deselected
	move.l	#vbl_handler,$70.w              ; VBL vector, the usual VBL handler back
	move.w	#$2400,sr                       ; IPL 4 (the rte puts the old sr back)
	clr.b	floppy_motor_watch.w            ; the motor watch off
floppy_motor_vbl_end:
	movem.l	(sp)+,d0-d7                     ; back
	rte                                     ; done

;------------------------------------------------------------------------------
; floppy_seek_track: seeks (no verify) to the call's track $75A.  floppy_seek seeks to track d7 with
;  -6 (seek error) as the error code, floppy_seek_command without setting it.
;  Out: d6 0 (Z set) when the FDC answered, d7 the status.
;------------------------------------------------------------------------------
floppy_seek_track:	; from: floppy_format_track
	move.w	fdc_track.w,d7                  ; the track

floppy_seek:	; from: restore_drive, floppy_set_up
	move.w	#$fffa,fd_error.w               ; -6: seek error

floppy_seek_command:	; from: floppy_speed_test
	move.w	#$86,(a6)                       ; the data register
	bsr.w	fdc_write_d7                    ; the track
	move.w	#$10,d6                         ; seek
	bra.s	floppy_command                  ; sent

;------------------------------------------------------------------------------
; floppy_seek_track_5: not reached.  Restores the head, tells the FDC it is at track 0, seeks to track 5,
;  then on to floppy_seek_verify.
;------------------------------------------------------------------------------
floppy_seek_track_5:
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
; floppy_seek_verify: seeks with verify to the call's track $75A.  Out: Z set when the head is there and
;  the ID read back (the drive's track then set), else Z clear; $776 = -6 (seek error).  Changes d0, d6, d7.
;------------------------------------------------------------------------------
floppy_seek_verify:	; from: read_alignment_track, read_sectors, floppy_write_sectors, floppy_verify_sectors
	move.w	#$fffa,fd_error.w               ; -6: seek error
	move.w	#$86,(a6)                       ; the data register
	move.w	fdc_track.w,d7                  ; the track
	bsr.w	fdc_write_d7                    ; sent
	moveq	#20,d6                          ; seek with verify
	bsr.w	floppy_command                  ; sent
	bne.s	floppy_seek_end                 ; failed
	move.w	fdc_track.w,0(a1)               ; the drive is there
	and.b	#$18,d7                         ; seek error or CRC error?
floppy_seek_end:	; from: floppy_seek_track_5
	rts                                     ; Z: there

;------------------------------------------------------------------------------
; floppy_restore: steps the head to track 0.  Out: Z set when the track 0 signal came and the
; drive's track set to 0.
;------------------------------------------------------------------------------
floppy_restore:	; from: restore_drive, floppy_set_up, floppy_seek_track_5
	clr.w	d6                              ; restore
	bsr.w	floppy_command                  ; sent
	bne.s	floppy_restore_end              ; failed
	btst	#$2,d7                          ; at track 0?
	eori.b	#$4,ccr                         ; Z set when it is
	bne.s	floppy_restore_end              ; no
	clr.w	0(a1)                           ; the drive's track 0
floppy_restore_end:
	rts                                     ; Z: at track 0

;------------------------------------------------------------------------------
; floppy_command: sends the type I command d6 with the drive's step rate and waits for the FDC
; interrupt ($40000 tries, $60000 when the motor was off and must spin up).
; Out: d7 the status and d6 = 0 (Z set), or d6 = 1 on a time-out (the command stopped).
;------------------------------------------------------------------------------
floppy_command:	; from: floppy_exit_ok, floppy_seek_command, floppy_seek_track_5, floppy_seek_verify, floppy_restore
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
	rts                                     ; Z set
floppy_command_timeout:
	bsr.w	floppy_force_interrupt          ; the command stopped
	moveq	#1,d6                           ; failed
	rts                                     ; Z clear

;------------------------------------------------------------------------------
; floppy_force_interrupt: stops the FDC's command (force interrupt $D0) and reads the status into d7.
;------------------------------------------------------------------------------
floppy_force_interrupt:                         ; from: read_alignment_track, read_sectors, floppy_write_sectors,
                                                ;   floppy_wipe_track, floppy_format_write, floppy_verify_list, 2 more
	move.w	#$80,(a6)                       ; the FDC command register
	move.w	#$d0,d7                         ; force interrupt
	bsr.w	fdc_write_d7                    ; sent
	move.w	#$f,d7                          ; a short wait
floppy_force_interrupt_delay:
	dbra	d7,floppy_force_interrupt_delay ; the wait
	bsr.w	fdc_read_d7                     ; the status read
	rts                                     ; d7: the status

;------------------------------------------------------------------------------
; floppy_select_drive: selects drive $758 and side $75E through the sound chip, writes the drive's track
;  into the FDC's track register and clears $770 (the high byte of the DMA address read back), then as
;  floppy_set_sector_dma.  In: a1 the head block, a6 the DMA mode register.  Changes d0-d2, d7.
;------------------------------------------------------------------------------
floppy_select_drive:                            ; from: restore_drive, read_alignment_track, read_sectors,
                                                ;   floppy_write_sectors, floppy_format_track, floppy_verify_sectors, 1
                                                ;   more
	move.w	fdc_drive.w,d0                  ; the drive
	addq.b	#1,d0                           ; drive 0 or 1 to 1 or 2
	lsl.b	#1,d0                           ; the drive's select bit
	or.w	fdc_side.w,d0                   ; the side in bit 0
	eori.b	#$7,d0                          ; active low
	and.b	#$7,d0                          ; the 3 bits
	bsr.w	psg_select_drive_side           ; to the sound chip's port A
	move.w	#$82,(a6)                       ; the track register
	move.w	0(a1),d7                        ; the drive's track
	bsr.w	fdc_write_d7                    ; sent
	clr.b	dma_address_read.w              ; the DMA address read back: high byte 0

;------------------------------------------------------------------------------
; floppy_set_sector_dma: the sector $75C into the FDC's sector register and the buffer $762 into the
;  DMA address.  Changes d7.
;------------------------------------------------------------------------------
floppy_set_sector_dma:	; from: read_sectors, floppy_write_sectors
	move.w	#$84,(a6)                       ; the sector register
	move.w	fd_cur_sector.w,d7              ; the sector
	bsr.w	fdc_write_d7                    ; sent
	move.b	fd_cur_buffer+3.w,$ffff860d.w   ; DMA base low
	move.b	fd_cur_buffer+2.w,$ffff860b.w   ; DMA base mid
	move.b	fd_cur_buffer+1.w,$ffff8609.w   ; DMA base high
	rts                                     ; done

;------------------------------------------------------------------------------
; psg_select_drive_side: puts d0 into bits 0-2 of the sound chip's port A (bit 0 side, bits 1-2 the
; drive selects, active low).  Out: d2 the old port A.  Uses d1.
;------------------------------------------------------------------------------
psg_select_drive_side:	; from: floppy_menu_choices, floppy_quick_test, floppy_motor_vbl, floppy_select_drive
	move.w	sr,-(sp)                        ; the sr kept
	ori.w	#$700,sr                        ; interrupts off
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	$ffff8800.w,d1                  ; PSG register select, read
	move.b	d1,d2                           ; the old value
	and.b	#$f8,d1                         ; side and drive bits cleared
	or.b	d0,d1                           ; the new ones
	move.b	d1,$ffff8802.w                  ; PSG write data, written
	move.w	(sp)+,sr                        ; the interrupts back
	rts                                     ; done

;------------------------------------------------------------------------------
; fdc_write_command: writes d6 to the DMA chip's selected register (the FDC command register),
; with a short wait before and after.  fdc_write_d7 writes d7, fdc_read_d7 and fdc_read_d0 read
; it into d7 or d0, and fdc_delay is the short wait.
;------------------------------------------------------------------------------
fdc_write_command:	; from: floppy_command
	bsr.w	fdc_delay                       ; the wait
	move.w	d6,$ffff8604.w                  ; DMA sector count / FDC access, the command
	bra.s	fdc_delay                       ; the wait

fdc_write_d7:                                   ; from: read_alignment_track, read_sectors, floppy_write_sectors,
                                                ;   floppy_wipe_track, floppy_format_write, floppy_verify_list, 7 more
	bsr.w	fdc_delay                       ; the wait
	move.w	d7,$ffff8604.w                  ; DMA sector count / FDC access, written
	bra.s	fdc_delay                       ; the wait

fdc_read_d7:	; from: floppy_command, floppy_force_interrupt
	bsr.w	fdc_delay                       ; the wait
	move.w	$ffff8604.w,d7                  ; DMA sector count / FDC access, read
	bra.s	fdc_delay                       ; the wait

fdc_read_d0:                                    ; from: wait_index_on, wait_index_off, read_alignment_track,
                                                ;   read_sectors, floppy_write_sectors, floppy_wipe_track, 4 more
	bsr.w	fdc_delay                       ; the wait
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, read

fdc_delay:	; from: fdc_write_command, fdc_write_d7, fdc_read_d7, fdc_read_d0
	move.w	sr,-(sp)                        ; sr kept
	move.w	d7,-(sp)                        ; d7 kept
	move.w	#$5,d7                          ; 6 loops
fdc_delay_loop:
	dbra	d7,fdc_delay_loop               ; the wait
	move.w	(sp)+,d7                        ; back
	move.w	(sp)+,sr                        ; sr back
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_short_test: menu G, "Testing Blitter".  Without a BLiTTER: "No Blitter installed", the background
;  red.  Else the tests G1-G12, each failure a bit in $49A (G1-G8) or $49B (G9-G12):
;    G1  halftone RAM: each of the 16 words holds 0, $0101 .. $FFFF while the others are written
;    G2  end masks: one line BLiTted with op 15 (all ones) for each end mask bit
;    G3  the 16 operations with six source and destination patterns (blit_op_test)
;    G4  HOP 0 (all ones), HOP 1 (each line its halftone word), HOP 3 (source AND halftone)
;    G5  skew 15 with NFSR          G6  the same going down (negative increments)
;    G7  skew 4 with FXSR           G8  smudge (the source picks the halftone word)
;    G9  x increments of $3FFE      G10 y increments of $3FFE
;    G11 a BLiT that does not end   G12 the address counts (not tested here)
;  Then the failed tests' texts, and "Pass" or "Fail at cycle:".  The source is at $60000, the
;  destination at $70000; $4FC/$4FE are the source/destination words, $500 the lines, $502 the words.
;------------------------------------------------------------------------------
blit_short_test:	; from: test_routines
	clr.b	test_errors.w                   ; no failures yet
	clr.b	test_errors_high.w              ; (both bytes)
	lea	msg_testing_blitter,a5          ; "Testing Blitter"
	bsr.w	show_status                     ; on the status line
	bsr.w	blit_check_present              ; a BLiTTER there?
	beq.w	blit_halftone_test              ; yes
	move.w	#$500,$ffff8240.w               ; palette 0, no: the background red
	lea	msg_no_blitter,a5               ; "No Blitter installed"
	bsr.w	print_string                    ; printed
	rts                                     ; done
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
	move.w	d1,(a1)                         ; (each other word written 0 then $FFFF)
blit_halftone_skip:
	adda.w	#$2,a1                          ; the next word
	dbra	d7,blit_halftone_others         ; all 16
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
	bset	#$0,test_errors.w               ; G1 failed
	bra.w	blit_short_report               ; the report
blit_endmask_test:
	lea	$ffff8a00.w,a6                  ; BLiTTER halftone RAM, G2: the registers
	moveq	#2,d1                           ; increments 2
	bsr.w	blit_set_increments             ; all four
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution (not used)
	andi.w	#$3,d0                          ; (not used)
	lsl.w	#1,d0                           ; (not used)
	move.w	#$190,blit_lines.w              ; 400 lines
	move.w	#$28,blit_words.w               ; 40 words a line
	move.w	#$0,$3c(a6)                     ; control 0
	move.b	#$f,$3b(a6)                     ; op 15: all ones
	moveq	#1,d0                           ; end masks from bit 0
	move.w	d0,$28(a6)                      ; end mask 1
	move.w	d0,$2a(a6)                      ; end mask 2
	move.w	d0,$2c(a6)                      ; end mask 3
blit_endmask_next_bit:
	moveq	#0,d0                           ; the destination cleared
	lea	$70000,a0                       ; the destination
	move.w	blit_words.w,d1                 ; 40 words
	bsr.w	blit_fill_words                 ; cleared
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	move.w	$2a(a6),d0                      ; the line should be the mask
	move.w	blit_words.w,d1                 ; 40 words
	lea	$70000,a0                       ; the destination
	bsr.w	blit_check_words                ; checked
	beq.w	blit_endmask_shift              ; yes
	bset	#$1,test_errors.w               ; G2 failed
	bra.w	blit_short_report               ; the report
blit_endmask_shift:
	lsl.w	$28(a6)                         ; the next bit
	lsl.w	$2a(a6)                         ; (end mask 2)
	lsl.w	$2c(a6)                         ; (end mask 3)
	bcc.s	blit_endmask_next_bit           ; all 16
	move.b	#$2,$3a(a6)                     ; G3: HOP 2, source only
	move.w	#$ffff,d0                       ; full masks
	move.w	d0,$28(a6)                      ; end mask 1
	move.w	d0,$2a(a6)                      ; end mask 2
	move.w	d0,$2c(a6)                      ; end mask 3
	move.w	#$aaaa,blit_source_word.w       ; source $AAAA
	move.w	#$5555,blit_dest_word.w         ; destination $5555
	bsr.w	blit_op_test                    ; the 16 operations
	not.w	blit_dest_word.w                ; source $5555
	not.w	blit_source_word.w              ; destination $AAAA
	bsr.w	blit_op_test                    ; the 16 operations
	clr.w	blit_source_word.w              ; source 0
	move.w	#$ffff,blit_dest_word.w         ; destination $FFFF
	bsr.w	blit_op_test                    ; the 16 operations
	not.w	blit_source_word.w              ; source $FFFF
	not.w	blit_dest_word.w                ; destination 0
	bsr.w	blit_op_test                    ; the 16 operations
	not.w	blit_source_word.w              ; source 0, destination 0
	bsr.w	blit_op_test                    ; the 16 operations
	move.w	#$ffff,blit_source_word.w       ; source $FFFF
	move.w	#$ffff,blit_dest_word.w         ; destination $FFFF
	bsr.w	blit_op_test                    ; the 16 operations
	tst.b	test_errors.w                   ; G3 failed?
	bne.w	blit_short_report               ; yes: the report
	move.w	#$0,$3c(a6)                     ; G4: control 0
	move.b	#$3,$3b(a6)                     ; op 3: the source
	moveq	#0,d0                           ; the halftone RAM 0
	moveq	#16,d1                          ; 16 words
	lea	$ffff8a00.w,a0                  ; BLiTTER halftone RAM
	bsr.w	blit_fill_words                 ; cleared
	lea	$60000,a0                       ; the source 0
	move.w	blit_words.w,d1                 ; the whole screen's words
	lsl.w	#4,d1                           ; (16 times 40)
	bsr.w	blit_fill_words                 ; cleared
	lea	$70000,a0                       ; the destination 0
	bsr.w	blit_fill_words                 ; cleared
	move.b	#$0,$3a(a6)                     ; HOP 0: all ones
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	moveq	#-1,d0                          ; all $FFFF?
	lea	$70000,a0                       ; the destination
	move.w	blit_words.w,d1                 ; 40 words
	bsr.w	blit_check_words                ; checked
	beq.w	blit_hop_lines_test             ; yes
	bset	#$3,test_errors.w               ; G4 failed
	bra.w	blit_short_report               ; the report
blit_hop_lines_test:
	moveq	#1,d0                           ; the halftone RAM: 1, 2, 4 .. $8000
	lea	$ffff8a00.w,a0                  ; BLiTTER halftone RAM
	move.b	#$1,$3a(a6)                     ; HOP 1: the halftone only
blit_hop_lines_fill:
	move.w	d0,(a0)+                        ; the halftone word
	lsl.w	#1,d0                           ; the next bit
	bcc.s	blit_hop_lines_fill             ; 16 words
	move.w	blit_lines.w,$38(a6)            ; 400 lines
	move.w	#$0,$3c(a6)                     ; from halftone line 0
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; each line should be its halftone word
blit_hop_lines_group:
	moveq	#1,d0                           ; line 0's word
blit_hop_lines_line:
	move.w	blit_words.w,d1                 ; 40 words a line
	subq.w	#1,d1                           ; (for dbra)
blit_hop_lines_word:
	cmp.w	(a0)+,d0                        ; right?
	beq.w	blit_hop_lines_next_word        ; yes
	bset	#$3,test_errors.w               ; G4 failed
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
	lea	$60000,a0                       ; the source
	move.w	#$28,d1                         ; 40 words
	bsr.w	blit_fill_words                 ; filled
	move.w	#$ffff,d0                       ; the destination $FFFF
	move.w	#$28,d1                         ; 40 words
	lea	$70000,a0                       ; the destination
	bsr.w	blit_fill_words                 ; filled
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	moveq	#0,d0                           ; all 0?
	lea	$70000,a0                       ; the destination
	moveq	#39,d1                          ; 40 words
blit_hop_and_check:
	cmp.w	(a0)+,d0                        ; 0?
	beq.w	blit_hop_and_next               ; yes
	bset	#$3,test_errors.w               ; G4 failed
blit_hop_and_next:
	dbra	d1,blit_hop_and_check           ; the next word
blit_skew_test:
	move.b	#$3,$3b(a6)                     ; G5: op 3, the source
	move.b	#$2,$3a(a6)                     ; HOP 2, source only
	move.w	#$1,$28(a6)                     ; the first word's mask
	move.w	#$ffff,$2a(a6)                  ; the middle words' mask
	move.w	#$fffe,$2c(a6)                  ; the last word's mask
	moveq	#0,d0                           ; the destination 0
	lea	$70000,a0                       ; the destination
	move.w	blit_words.w,d1                 ; 40 words
	bsr.w	blit_fill_words                 ; filled
	move.w	#$aaaa,d0                       ; the source $AAAA
	lea	$60000,a0                       ; the source
	bsr.w	blit_fill_words                 ; filled
	move.b	#$4f,$3d(a6)                    ; NFSR, skew 15
	addi.w	#$1,blit_words.w                ; 41 words a line
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	bsr.w	blit_check_skew                 ; 1, $5555 .., $5554?
	beq.w	blit_fxsr_test                  ; yes
	bset	#$4,test_errors.w               ; G5 failed
blit_fxsr_test:
	lea	$60000,a0                       ; G7: the source $1234 x4, $5555
	move.w	#$1234,d0                       ; $1234
	moveq	#3,d7                           ; 4 words
blit_fxsr_fill:
	move.w	d0,(a0)+                        ; $1234
	dbra	d7,blit_fxsr_fill               ; 4 words
	move.w	#$5555,(a0)                     ; then $5555
	move.b	#$84,$3d(a6)                    ; FXSR, skew 4
	move.w	#$1,$38(a6)                     ; one line
	move.w	#$4,blit_words.w                ; 4 words a line
	lea	$70000,a0                       ; the destination 0
	move.w	#$10,d1                         ; 16 words
	moveq	#0,d0                           ; of 0
	bsr.w	blit_fill_words                 ; filled
	move.w	#$ffff,$28(a6)                  ; full masks
	move.w	#$ffff,$2a(a6)                  ; (end mask 2)
	move.w	#$ffff,$2c(a6)                  ; (end mask 3)
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; $4123 x3, $4555?
	moveq	#2,d7                           ; 3 words
blit_fxsr_check:
	cmpi.w	#$4123,(a0)+                    ; $4123?
	bne.w	blit_fxsr_failed                ; no
	dbra	d7,blit_fxsr_check              ; 3 words
	cmpi.w	#$4555,(a0)+                    ; then $4555?
	beq.w	blit_reverse_test               ; yes
blit_fxsr_failed:
	bset	#$5,test_errors.w               ; G7 failed
blit_reverse_test:
	move.w	#$fffe,d1                       ; G6: increments -2
	bsr.w	blit_set_increments             ; all four
	move.w	#$fffe,$28(a6)                  ; the masks for right to left
	move.w	#$ffff,$2a(a6)                  ; (the middle words)
	move.w	#$1,$2c(a6)                     ; (the first word, at the right)
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
	bset	#$6,test_errors.w               ; G6 failed
blit_smudge_test:
	lea	0(a6),a0                        ; G8: the halftone RAM
	moveq	#2,d1                           ; increments 2
	bsr.w	blit_set_increments             ; increments 2
	moveq	#0,d0                           ; 0, $1111 .. $FFFF
blit_smudge_halftone:
	move.w	d0,(a0)+                        ; a halftone word
	add.w	#$1111,d0                       ; the next word
	cmpi.w	#$1110,d0                       ; 16 words?
	bne.s	blit_smudge_halftone            ; no
	lea	$60000,a0                       ; the source 0 .. 15
	moveq	#0,d0                           ; from 0
blit_smudge_source:
	move.w	d0,(a0)+                        ; a source word
	addq.w	#1,d0                           ; the next value
	cmpi.w	#$10,d0                         ; 16 words?
	bne.s	blit_smudge_source              ; no
	lea	$70000,a0                       ; the destination 0
	move.w	#$20,d1                         ; 32 words
	moveq	#0,d0                           ; of 0
	bsr.w	blit_fill_words                 ; cleared
	move.b	#$1,$3a(a6)                     ; HOP 1: the halftone only
	move.b	#$3,$3b(a6)                     ; op 3
	move.b	#$0,$3d(a6)                     ; no skew
	move.b	#$20,$3c(a6)                    ; smudge: the source picks the halftone word
	move.w	#$ffff,$28(a6)                  ; full masks
	move.w	#$ffff,$2a(a6)                  ; (end mask 2)
	move.w	#$ffff,$2c(a6)                  ; (end mask 3)
	move.w	#$10,blit_words.w               ; 16 words a line
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; 0, $1111 .. $FFFF?
	moveq	#0,d0                           ; from 0
blit_smudge_check:
	cmp.w	(a0)+,d0                        ; right?
	bne.w	blit_smudge_failed              ; no
	add.w	#$1111,d0                       ; the next one
	cmpi.w	#$1110,d0                       ; all 16?
	bne.s	blit_smudge_check               ; no
	bra.w	blit_x_count_test               ; yes
blit_smudge_failed:
	bset	#$7,test_errors.w               ; G8 failed
blit_x_count_test:
	move.b	#$3,$3b(a6)                     ; G9: op 3
	move.b	#$2,$3a(a6)                     ; HOP 2
	move.w	#$ffff,d0                       ; full masks
	move.w	d0,$28(a6)                      ; end mask 1
	move.w	d0,$2a(a6)                      ; end mask 2
	move.w	d0,$2c(a6)                      ; end mask 3
	move.w	#$3ffe,$20(a6)                  ; x increments $3FFE
	move.w	#$3ffe,$2e(a6)                  ; (destination)
	move.w	#$2,$22(a6)                     ; y increments 2
	move.w	#$2,$30(a6)                     ; (destination)
	move.w	#$2,$38(a6)                     ; 2 lines
	move.w	#$2,blit_words.w                ; 2 words a line
	move.w	#$aaaa,d0                       ; the source words at 0, $3FFE, $4000, $7FFE
	lea	$60000,a0                       ; the source
	move.w	d0,(a0)                         ; the first line's words
	move.w	d0,$3ffe(a0)                    ; then $3FFE on
	move.w	d0,$4000(a0)                    ; the second line's
	move.w	d0,$7ffe(a0)                    ; then $3FFE on
	lea	$70000,a0                       ; the destination's cleared
	moveq	#0,d0                           ; 0
	move.w	d0,(a0)                         ; the four words
	move.w	d0,$3ffe(a0)
	move.w	d0,$4000(a0)
	move.w	d0,$7ffe(a0)
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; all four copied?
	move.w	#$aaaa,d0                       ; $AAAA?
	cmp.w	(a0),d0                         ; the first
	bne.w	blit_x_count_failed             ; no
	cmp.w	$3ffe(a0),d0                    ; the second
	bne.w	blit_x_count_failed             ; no
	cmp.w	$4000(a0),d0                    ; the third
	bne.w	blit_x_count_failed             ; no
	cmp.w	$7ffe(a0),d0                    ; the fourth
	beq.w	blit_y_count_test               ; yes
blit_x_count_failed:
	bset	#$0,test_errors_high.w          ; G9 failed
blit_y_count_test:
	move.w	#$3ffe,$22(a6)                  ; G10: y increments $3FFE
	move.w	#$3ffe,$30(a6)                  ; (destination)
	move.w	#$2,$20(a6)                     ; x increments 2
	move.w	#$2,$2e(a6)                     ; (destination)
	move.w	#$2,$38(a6)                     ; 2 lines
	move.w	#$2,blit_words.w                ; 2 words a line
	move.w	#$aaaa,d0                       ; the source words at 0, 2, $4000, $4002
	lea	$60000,a0                       ; the source
	move.w	d0,(a0)                         ; the first line's words
	move.w	d0,2(a0)                        ; the next word
	move.w	d0,$4000(a0)                    ; the second line's
	move.w	d0,$4002(a0)                    ; the next word
	lea	$70000,a0                       ; the destination's cleared
	moveq	#0,d0                           ; 0
	move.w	d0,(a0)                         ; the four words
	move.w	d0,2(a0)
	move.w	d0,$4000(a0)
	move.w	d0,$4002(a0)
	bsr.w	blit_start                      ; BLiT
	lea	$70000,a0                       ; all four copied?
	move.w	#$aaaa,d0                       ; $AAAA?
	cmp.w	(a0),d0                         ; the first
	bne.w	blit_y_count_failed             ; no
	cmp.w	2(a0),d0                        ; the second
	bne.w	blit_y_count_failed             ; no
	cmp.w	$4000(a0),d0                    ; the third
	bne.w	blit_y_count_failed             ; no
	cmp.w	$4002(a0),d0                    ; the fourth
	beq.w	blit_short_report               ; yes
blit_y_count_failed:
	bset	#$1,test_errors_high.w          ; G10 failed
blit_short_report:
	move.b	test_errors_high.w,d3           ; $49B in the high byte
	lsl.w	#8,d3                           ; (moved up)
	move.b	test_errors.w,d3                ; $49A in the low byte
	moveq	#0,d1                           ; bit 0 first
	moveq	#0,d2                           ; the text's offset
	lea	blit_short_error_texts(pc),a0   ; the "Gn" texts, one for each bit
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
	bra.w	blit_short_result               ; shown
blit_short_pass:
	lea	msg_pass,a5                     ; "Pass"
blit_short_result:
	bsr.w	show_result                     ; the result
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_short_error_texts: the texts for the 12 failure bits, bit 0 of $49A first, then $49B.
;------------------------------------------------------------------------------
blit_short_error_texts:	; from: blit_short_test
	dc.l	msg_blit_halftone_ram           ; bit 0: G1 halftone RAM
	dc.l	msg_blit_endmask                ; bit 1: G2 end masks
	dc.l	msg_blit_operation              ; bit 2: G3 operations
	dc.l	msg_blit_halftone_op            ; bit 3: G4 halftone operations
	dc.l	msg_blit_skew                   ; bit 4: G5 skew
	dc.l	msg_blit_fxsr                   ; bit 5: G7 FXSR
	dc.l	msg_blit_reverse                ; bit 6: G6 reverse
	dc.l	msg_blit_smudge                 ; bit 7: G8 smudge
	dc.l	msg_blit_x_count                ; bit 8: G9 x count
	dc.l	msg_blit_y_count                ; bit 9: G10 y count
	dc.l	msg_blit_time_out               ; bit 10: G11 time-out
	dc.l	msg_blit_address_count          ; bit 11: G12 address count

;------------------------------------------------------------------------------
; blit_op_test: G3.  BLiTs one line of $502 words with each of the 16 operations, the source filled with
;  $4FC and the destination with $4FE, and checks the result against blit_op_result.  Sets bit 2 of $49A
;  on a mismatch.  In: a6 the BLiTTER.  Changes d0-d2, d7, a0, a1.
;------------------------------------------------------------------------------
blit_op_test:	; from: blit_short_test
	moveq	#0,d0                           ; op 0
blit_op_test_next:
	move.b	d0,$3b(a6)                      ; the operation
	move.w	blit_source_word.w,d0           ; the source word
	move.w	blit_words.w,d1                 ; the line's words
	lea	$60000,a0                       ; the source
	bsr.w	blit_fill_words                 ; filled
	move.w	blit_dest_word.w,d0             ; the destination word
	lea	$70000,a0                       ; the destination
	bsr.w	blit_fill_words                 ; filled
	move.w	#$1,$38(a6)                     ; one line
	bsr.w	blit_start                      ; BLiT
	bsr.w	blit_op_result                  ; the expected word
	lea	$70000,a0                       ; the line all that?
	move.w	blit_words.w,d1                 ; the line's words
	bsr.w	blit_check_words                ; checked
	beq.w	blit_op_test_step               ; yes
	bset	#$2,test_errors.w               ; G3 failed
blit_op_test_step:
	move.b	$3b(a6),d0                      ; the next operation
	addq.w	#1,d0                           ; (the next)
	cmpi.b	#$10,d0                         ; all 16?
	bne.s	blit_op_test_next               ; no
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_start: BLiTs $500 lines of $502 words from $60000 to $70000 (the other registers already set) and
;  waits for the busy bit to clear; after 65,536 polls it gives up and sets bit 2 of $49B (G11).
;  In: a6 the BLiTTER.  Changes d7.
;------------------------------------------------------------------------------
blit_start:	; from: blit_short_test, blit_op_test
	move.l	#$70000,$32(a6)                 ; the destination
	move.l	#$60000,$24(a6)                 ; the source
	move.w	blit_words.w,$36(a6)            ; the words a line
	bset	#$7,$3c(a6)                     ; busy: go
	move.l	#$100000,d7                     ; the time-out (counted as a word: 65,536)
blit_start_wait:
	btst	#$7,$3c(a6)                     ; still busy?
	beq.w	blit_start_end                  ; no
	subq.w	#1,d7                           ; the time-out counted down
	bne.s	blit_start_wait                 ; keep waiting
	bset	#$2,test_errors_high.w          ; G11: time-out
	andi.b	#$1f,ccr                        ; (no flag changed)
blit_start_end:
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_set_increments: d1 into the source and destination x and y increments.  In: a6 the BLiTTER.
;------------------------------------------------------------------------------
blit_set_increments:	; from: blit_short_test
	move.w	d1,$20(a6)                      ; source x
	move.w	d1,$2e(a6)                      ; destination x
	move.w	d1,$22(a6)                      ; source y
	move.w	d1,$30(a6)                      ; destination y
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_op_result: works out the operation's result in the CPU.  In: the BLiTTER's op register, $4FC the
;  source word, $4FE the destination word.  Out: d0.w the result.  Uses d1-d2, a0-a1.
;------------------------------------------------------------------------------
blit_op_result:	; from: blit_op_test
	clr.l	d2                              ; the offset
	move.b	$3b(a6),d2                      ; the operation
	lsl.w	#2,d2                           ; 4 bytes each
	move.w	blit_source_word.w,d0           ; S: the source word
	move.w	blit_dest_word.w,d1             ; D: the destination word
	lea	blit_op_routines,a0             ; the table
	movea.l	0(a0,d2.w),a1                   ; its routine
	jmp	(a1)                            ; the result made

;------------------------------------------------------------------------------
; blit_op_routines: a routine for each BLiTTER logic operation 0-15 (the op register times 4); each
; makes in d0 the result from the source word (d0) and the destination word (d1), which
; blit_op_result returns to be compared with the BLiTTER's.
;------------------------------------------------------------------------------
blit_op_routines:
	dc.l	blit_op_zero                    ; op 0: all zeros
	dc.l	blit_op_and                     ; op 1: S AND D
	dc.l	blit_op_and_not_dest            ; op 2: S AND NOT D
	dc.l	blit_op_source                  ; op 3: S
	dc.l	blit_op_not_source_and          ; op 4: NOT S AND D
	dc.l	blit_op_dest                    ; op 5: D
	dc.l	blit_op_xor                     ; op 6: S XOR D
	dc.l	blit_op_or                      ; op 7: S OR D
	dc.l	blit_op_nor                     ; op 8: NOT S AND NOT D
	dc.l	blit_op_xnor                    ; op 9: NOT S XOR D
	dc.l	blit_op_not_dest                ; op 10: NOT D
	dc.l	blit_op_or_not_dest             ; op 11: S OR NOT D
	dc.l	blit_op_not_source              ; op 12: NOT S
	dc.l	blit_op_not_source_or           ; op 13: NOT S OR D
	dc.l	blit_op_nand                    ; op 14: NOT S OR NOT D
	dc.l	blit_op_one                     ; op 15: all ones
blit_op_zero:
	moveq	#0,d0                           ; 0
	rts                                     ; d0: the result
blit_op_and:
	and.w	d1,d0                           ; S AND D
	rts                                     ; d0: the result
blit_op_and_not_dest:
	not.w	d1                              ; NOT D
	and.w	d1,d0                           ; S AND NOT D
	rts                                     ; d0: the result
blit_op_source:
	rts                                     ; d0: S, the result
blit_op_not_source_and:
	not.w	d0                              ; NOT S
	and.w	d1,d0                           ; NOT S AND D
	rts                                     ; d0: the result
blit_op_dest:
	move.w	d1,d0                           ; D
	rts                                     ; d0: the result
blit_op_xor:
	eor.w	d1,d0                           ; S XOR D
	rts                                     ; d0: the result
blit_op_or:
	or.w	d1,d0                           ; S OR D
	rts                                     ; d0: the result
blit_op_nor:
	not.w	d0                              ; NOT S
	not.w	d1                              ; NOT D
	and.w	d1,d0                           ; NOT S AND NOT D
	rts                                     ; d0: the result
blit_op_xnor:
	not.w	d0                              ; NOT S
	eor.w	d1,d0                           ; NOT S XOR D
	rts                                     ; d0: the result
blit_op_not_dest:
	not.w	d1                              ; NOT D
	move.w	d1,d0                           ; NOT D
	rts                                     ; d0: the result
blit_op_or_not_dest:
	not.w	d1                              ; NOT D
	or.w	d1,d0                           ; S OR NOT D
	rts                                     ; d0: the result
blit_op_not_source:
	not.w	d0                              ; NOT S
	rts                                     ; d0: the result
blit_op_not_source_or:
	not.w	d0                              ; NOT S
	or.w	d1,d0                           ; NOT S OR D
	rts                                     ; d0: the result
blit_op_nand:
	not.w	d0                              ; NOT S
	not.w	d1                              ; NOT D
	or.w	d1,d0                           ; NOT S OR NOT D
	rts                                     ; d0: the result
blit_op_one:
	moveq	#-1,d0                          ; all ones
	rts                                     ; d0: the result

;------------------------------------------------------------------------------
; blit_check_words: checks d1 words from a0 against d0.  Out: Z set when all match, else a0 at
; the first wrong word.
;------------------------------------------------------------------------------
blit_check_words:	; from: blit_short_test, blit_op_test
	subq.w	#1,d1                           ; (for dbra)
blit_check_words_loop:
	cmp.w	(a0)+,d0                        ; the same?
	bne.w	blit_check_words_wrong          ; wrong
	dbra	d1,blit_check_words_loop        ; the next
	rts                                     ; Z: all right
blit_check_words_wrong:
	subq.w	#2,a0                           ; a0 back at it
	rts                                     ; Z clear

;------------------------------------------------------------------------------
; blit_check_skew: checks the G5 result at $70000: 1, then $5555 words, then $5554 ($502 words in all).
;  Out: Z set when right.  Changes d7, a0.
;------------------------------------------------------------------------------
blit_check_skew:	; from: blit_short_test
	lea	$70000,a0                       ; the result
	move.w	blit_words.w,d7                 ; the words a line
	subq.w	#3,d7                           ; the middle words
	cmpi.w	#$1,(a0)+                       ; the first
	bne.w	blit_check_skew_end             ; wrong
blit_check_skew_loop:
	cmpi.w	#$5555,(a0)+                    ; $5555?
	bne.w	blit_check_skew_end             ; wrong
	dbra	d7,blit_check_skew_loop         ; the next
	cmpi.w	#$5554,(a0)+                    ; the last
blit_check_skew_end:
	rts                                     ; Z: right

;------------------------------------------------------------------------------
; blit_check_reverse: checks the G6 result going down from $70000: $5554, $5555 words, then 1 ($502 words
;  in all).  Out: Z set when right.  Changes d7, a0.
;------------------------------------------------------------------------------
blit_check_reverse:	; from: blit_short_test
	lea	$70000,a0                       ; the result
	adda.l	#$2,a0                          ; its last word
	move.w	blit_words.w,d7                 ; the words a line
	subq.w	#3,d7                           ; the middle words
	cmpi.w	#$5554,-(a0)                    ; the last
	bne.w	blit_check_reverse_end          ; wrong
blit_check_reverse_loop:
	cmpi.w	#$5555,-(a0)                    ; $5555?
	bne.w	blit_check_reverse_end          ; wrong
	dbra	d7,blit_check_reverse_loop      ; the next
	cmpi.w	#$1,-(a0)                       ; the first
blit_check_reverse_end:
	rts                                     ; Z: right

;------------------------------------------------------------------------------
; blit_fill_words: fills d1 words from a0 up with d0.  d1 and a0 kept.
;------------------------------------------------------------------------------
blit_fill_words:	; from: blit_short_test, blit_op_test
	movem.l	d1/a0,-(sp)                     ; kept
	subq.w	#1,d1                           ; (for dbra)
blit_fill_words_loop:
	move.w	d0,(a0)+                        ; stored
	dbra	d1,blit_fill_words_loop         ; the next
	movem.l	(sp)+,d1/a0                     ; back
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_fill_words_down: fills d1 words with d0 going down, the first one written at a0.  d1 and a0 kept.
;------------------------------------------------------------------------------
blit_fill_words_down:	; from: blit_short_test
	movem.l	d1/a0,-(sp)                     ; kept
	subq.w	#1,d1                           ; (for dbra)
	adda.l	#$2,a0                          ; past the top word
blit_fill_words_down_loop:
	move.w	d0,-(a0)                        ; stored going down
	dbra	d1,blit_fill_words_down_loop    ; the next
	movem.l	(sp)+,d1/a0                     ; back
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_check_present: reads the BLiTTER's halftone RAM with the bus error vector caught.  Bit 0 of $28C set
;  when a BLiTTER answered, cleared when the read caused a bus error.  Out: Z set when there is a BLiTTER.
;  Changes d0, d7, a0, a4.
;------------------------------------------------------------------------------
blit_check_present:	; from: menu_start, blit_short_test, blit_long_test
	ori.b	#$1,hardware_flags.w            ; a BLiTTER, unless the read fails
	movea.l	$8.w,a4                         ; the old bus error vector
	lea	blit_check_present_bus_error(pc),a0 ; the probe's handler
	move.l	a0,$8.w                         ; bus error vector, caught
	clr.w	d7                              ; no bus error yet
	move.b	$ffff8a00.w,d0                  ; BLiTTER halftone RAM, the halftone RAM read
	nop                                     ; (the bus error comes here)
	move.l	a4,$8.w                         ; the bus error vector back
	tst.w	d7                              ; a bus error?
	beq.w	blit_check_present_end          ; no
	andi.b	#$fe,hardware_flags.w           ; no BLiTTER
	andi.b	#$fb,ccr                        ; Z clear
blit_check_present_end:
	rts                                     ; Z: a BLiTTER
blit_check_present_bus_error:
	move.w	#$ff,d7                         ; noted
	adda.w	#$8,sp                          ; the bus error frame's extra 8 bytes dropped
	rte                                     ; on past the read

;------------------------------------------------------------------------------
; blit_long_test: menu Y.  Shows a screen of its own at $70000 and, with Line-A style drawing through the
;  BLiTTER, fills and outlines a triangle whose third corner is moved left, up, right and down a pixel at
;  a time, redrawing it each step.  Esc stops it.  A bus error during a BLiT prints "Replace Blitter"
;  and ends the test.  The old screen is put back, then "Pass" unless stopped.  sp is kept at $500 for
;  the bus error, the old bus error vector at $4FC.
;------------------------------------------------------------------------------
blit_long_test:	; from: test_routines
	lea	msg_testing_blitter,a5          ; "Testing Blitter"
	bsr.w	show_status                     ; on the status line
	bsr.s	blit_check_present              ; a BLiTTER there?
	beq.s	blit_long_run                   ; yes
	move.w	#$500,$ffff8240.w               ; palette 0, no: the background red
	lea	msg_no_blitter,a5               ; "No Blitter installed"
	bsr.w	print_string                    ; printed
	rts                                     ; done
blit_long_run:
	move.l	sp,blit_lines.w                 ; sp kept for the bus error
	bsr.w	blit_long_set_up                ; the screen and the drawing set up
	movea.l	a0,a5                           ; a5: the drawing variables
	lea	blit_long_triangle.w,a1         ; the triangle's corners
	move.l	a1,blit_long_corners.w          ; for the outline
	bsr.w	blit_long_outline               ; outlined
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
	move.l	blit_long_saved_screen.w,d1     ; its address
	swap	d1                              ; its high byte
	move.b	d1,$ffff8201.w                  ; video base high, the video base
blit_long_finish_wait_screen:
	cmp.b	$ffff8205.w,d1                  ; video count high, until the video counter is there
	bne.s	blit_long_finish_wait_screen    ; (wait)
	movea.l	blit_source_word.w,a4           ; the old bus error vector
	move.l	a4,$8.w                         ; bus error vector
	cmp.b	#$0,d0                          ; stopped or failed?
	bne.s	blit_long_end                   ; yes
	lea	msg_pass,a5                     ; "Pass"
	bsr.w	show_result                     ; shown
blit_long_end:
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_long_set_up: moves the screen to $70000 (the old one kept at $3B6), clears it and sets up the
;  drawing variables at $328 (bytes per line at $326): one plane, 80 bytes a line, the triangle's points
;  at $3BA and its corners at $3CA, the fill patterns, clipping to 320 x 200.  The bus error vector points
;  at blit_long_bus_error (the old one kept at $4FC).  Out: a0 = $328.  Uses d0-d1, a1-a5.
;------------------------------------------------------------------------------
blit_long_set_up:	; from: blit_long_test
	move.l	#$70000,d0                      ; the test screen
	move.l	screen_base.w,blit_long_saved_screen.w ; the old screen kept
	move.l	d0,screen_base.w                ; the screen at $70000
	movea.l	d0,a5                           ; a5: the screen
	swap	d0                              ; its high byte
	move.b	d0,$ffff8201.w                  ; video base high, the video base
blit_long_set_up_wait_screen:
	cmp.b	$ffff8205.w,d0                  ; video count high, until the video counter is there
	bne.s	blit_long_set_up_wait_screen    ; (wait)
	moveq	#0,d0                           ; cleared
	move.l	#$2000,d1                       ; 32K
blit_long_set_up_clear:
	move.l	d0,(a5)+                        ; cleared
	dbra	d1,blit_long_set_up_clear       ; (32K and 4 bytes)
	lea	msg_testing_blitter,a5          ; "Testing Blitter"
	bsr.w	show_status                     ; on the status line
	lea	draw_planes.w,a0                ; a0: the drawing variables
	lea	long_blit_shape_1,a2            ; the first triangle
	moveq	#7,d0                           ; 8 words each
	lea	blit_long_points.w,a1           ; the points
	move.l	a1,$c(a0)                       ; the points
	lea	blit_long_triangle.w,a3         ; the corners
	lea	long_blit_shape_2,a4            ; its corners
blit_long_set_up_points:
	move.w	(a2)+,(a1)+                     ; copied
	move.w	(a4)+,(a3)+                     ; the corners copied
	dbra	d0,blit_long_set_up_points      ; 8 words
	lea	long_blit_word_pair,a1          ; the point count
	move.l	a1,4(a0)                        ; CONTRL
	move.w	#$1,0(a0)                       ; 1 plane
	move.w	#$50,-$2(a0)                    ; 80 bytes a line
	move.w	#$50,2(a0)                      ; 80 bytes a line
	move.w	#$1,$18(a0)                     ; colour bits all 1
	move.w	#$1,$1a(a0)                     ; (plane 1)
	move.w	#$1,$1c(a0)                     ; (plane 2)
	move.w	#$1,$1e(a0)                     ; (plane 3)
	move.w	#$0,$24(a0)                     ; replace mode
	lea	long_blit_fill_pattern,a1       ; the fill patterns
	move.l	a1,$2e(a0)                      ; the fill pattern
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
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_long_bus_error: bus error during the long BLiT test: the BLiTTER stopped, the background red, the
;  old screen back and "Replace Blitter / Bus error has occurred during BLiT test!" printed, then the
;  test ends with d0 = $FF (sp from $500).
;------------------------------------------------------------------------------
blit_long_bus_error:	; from: blit_long_set_up
	lea	$ff8a3c,a5                      ; the BLiTTER control
	bclr	#$7,(a5)                        ; stopped
	move.w	#$500,$ffff8240.w               ; palette 0, the background red
	move.l	blit_long_saved_screen.w,screen_base.w ; the old screen back
	move.l	blit_long_saved_screen.w,d0     ; its address
	swap	d0                              ; its high byte
	move.b	d0,$ffff8201.w                  ; video base high, the video base
blit_long_bus_error_wait_screen:
	cmp.b	$ffff8205.w,d0                  ; video count high, until the video counter is there
	bne.s	blit_long_bus_error_wait_screen ; (wait)
	lea	msg_replace_blitter,a5          ; "Replace Blitter"
	bsr.w	print_string                    ; printed
	movea.l	blit_lines.w,sp                 ; the test's sp
	move.b	#$ff,d0                         ; failed
	lea	blit_long_finish,a1             ; the end of the test
	jmp	(a1)                            ; the test ends

;------------------------------------------------------------------------------
; blit_long_move_left: moves the triangle's third corner ($3CA+8) left a pixel at a time to x 1, redrawing
;  it each step.  Out: d0 $1B when Esc stopped it.  blit_long_move_up goes up to y 20,
;  blit_long_move_right right to x 319 and blit_long_move_down down to y 190 the same way.
;------------------------------------------------------------------------------
blit_long_move_left:	; from: blit_long_test
	lea	blit_long_triangle.w,a1         ; the triangle's corners
	move.w	8(a1),d0                        ; its x
	cmp.w	#$1,d0                          ; at 1?
	ble.w	blit_long_move_left_end         ; yes
	sub.w	#$1,d0                          ; one left
	move.w	d0,8(a1)                        ; kept
	bsr.w	blit_long_draw                  ; redrawn
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_move_left_end         ; yes
	bra.s	blit_long_move_left             ; again
blit_long_move_left_end:
	rts

blit_long_move_up:	; from: blit_long_test
	lea	blit_long_triangle.w,a1         ; the triangle's corners
	move.w	$a(a1),d0                       ; its y
	cmp.w	#$14,d0                         ; at 20?
	ble.w	blit_long_move_up_end           ; yes
	sub.w	#$1,d0                          ; one up
	move.w	d0,$a(a1)                       ; kept
	bsr.w	blit_long_draw                  ; redrawn
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_move_up_end           ; yes
	bra.s	blit_long_move_up               ; again
blit_long_move_up_end:
	rts

blit_long_move_right:	; from: blit_long_test
	lea	blit_long_triangle.w,a1         ; the triangle's corners
	move.w	8(a1),d0                        ; its x
	cmp.w	#$13f,d0                        ; at 319?
	bge.w	blit_long_move_right_end        ; yes
	add.w	#$1,d0                          ; one right
	move.w	d0,8(a1)                        ; kept
	bsr.w	blit_long_draw                  ; redrawn
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_move_right_end        ; yes
	bra.s	blit_long_move_right            ; again
blit_long_move_right_end:
	rts

blit_long_move_down:	; from: blit_long_test
	lea	blit_long_triangle.w,a1         ; the triangle's corners
	move.w	$a(a1),d0                       ; its y
	cmp.w	#$be,d0                         ; at 190?
	bge.w	blit_long_move_down_end         ; yes
	add.w	#$1,d0                          ; one down
	move.w	d0,$a(a1)                       ; kept
	bsr.w	blit_long_draw                  ; redrawn
	cmpi.b	#$1b,d0                         ; Esc?
	beq.w	blit_long_move_down_end         ; yes
	bra.s	blit_long_move_down             ; again
blit_long_move_down_end:
	rts

;------------------------------------------------------------------------------
; blit_long_draw: fills the triangle at $3CA row by row over the 200 lines in replace mode, then again in
;  reverse transparent mode, then outlines it.  In: a5 the drawing variables.  Out: d0 the key pressed, or
;  0.  Changes d1-d7, a0-a4.
;------------------------------------------------------------------------------
blit_long_draw:                                 ; from: blit_long_test, blit_long_move_left, blit_long_move_up,
                                                ;   blit_long_move_right, blit_long_move_down
	moveq	#0,d3                           ; the first pass
blit_long_draw_pass:
	lea	blit_long_triangle.w,a2         ; the corners
	move.l	a2,$c(a5)                       ; PTSIN
	move.w	#$0,$28(a5)                     ; from line 0
	move.w	#$c7,d4                         ; 200 lines
	sub.w	#$0,d4                          ; (from line 0)
blit_long_draw_row:
	movem.l	d3-d4/a5,-(sp)                  ; kept
	bsr.w	blit_fill_row                   ; the row filled
	movem.l	(sp)+,d3-d4/a5                  ; back
	addq.w	#1,$28(a5)                      ; the next line
	dbra	d4,blit_long_draw_row           ; the next line
	cmp.w	#$0,d3                          ; the second pass done?
	bne.w	blit_long_draw_outline          ; yes
	moveq	#15,d3                          ; the second pass
	move.w	#$3,$24(a5)                     ; reverse transparent
	bra.s	blit_long_draw_pass             ; again
blit_long_draw_outline:
	move.w	#$0,$24(a5)                     ; replace
	bsr.w	blit_long_outline               ; the outline, the outline
	moveq	#0,d0                           ; a key?
	bsr.w	key_waiting                     ; a key?
	beq.w	blit_long_draw_end              ; no
	bsr.w	get_key                         ; d0: the key
blit_long_draw_end:
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_long_outline: draws the three sides of the triangle whose corners $3B2 points at (x1,y1 x2,y2
;  x3,y3): 1 to 2, 1 to 3, 2 to 3.  In: a5 the drawing variables.  Changes d0-d7, a2.
;------------------------------------------------------------------------------
blit_long_outline:	; from: blit_long_test, blit_long_draw
	movea.l	blit_long_corners.w,a2          ; the corners
	move.w	(a2),$26(a5)                    ; x1
	move.w	2(a2),$28(a5)                   ; y1
	move.w	4(a2),$2a(a5)                   ; x2
	move.w	6(a2),$2c(a5)                   ; y2
	movem.l	a0-a5,-(sp)                     ; kept
	bsr.w	blit_line                       ; the line
	movem.l	(sp)+,a0-a5                     ; back
	move.w	(a2),$26(a5)                    ; corner 1
	move.w	2(a2),$28(a5)                   ; y1
	move.w	8(a2),$2a(a5)                   ; to corner 3
	move.w	$a(a2),$2c(a5)                  ; y2
	movem.l	a0-a5,-(sp)                     ; kept
	bsr.w	blit_line                       ; the line
	movem.l	(sp)+,a0-a5                     ; back
	move.w	4(a2),$26(a5)                   ; corner 2
	move.w	6(a2),$28(a5)                   ; y1
	move.w	8(a2),$2a(a5)                   ; to corner 3
	move.w	$a(a2),$2c(a5)                  ; y2
	movem.l	a0-a5,-(sp)                     ; kept
	bsr.w	blit_line                       ; the line
	movem.l	(sp)+,a0-a5                     ; back
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_fill_row: fills one row of the polygon at PTSIN (the drawing variables at $328): every edge that
;  crosses the line y1 ($350) gives an x (kept at $318, the count at $324); they are sorted and each pair
;  filled as a span with the pattern (blit_fill_span), clipped when clipping is on.  Changes d0-d7, a0-a4.
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
	sub.w	d2,d1                           ; the height
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
	neg.w	d4                              ; negative again
	bra.w	blit_fill_row_crossing          ; on
blit_fill_row_round:
	addq.w	#1,d4                           ; rounded
	asr.w	#1,d4                           ; halved
blit_fill_row_crossing:
	add.w	0(a0),d4                        ; plus the first end's x
	move.w	d4,(a1)+                        ; the crossing kept
	addq.w	#1,-$4(a4)                      ; counted
blit_fill_row_next_edge:
	lea	4(a0),a0                        ; the next edge
	dbra	d0,blit_fill_row_edge           ; the next edge
	move.w	-$4(a4),d0                      ; any crossings?
	bne.w	blit_fill_row_spans             ; yes
	rts                                     ; none: nothing filled
blit_fill_row_spans:
	lea	-$10(a4),a0                     ; the crossings
	bsr.w	blit_sort_crossings             ; sorted
	move.w	-$4(a4),d0                      ; the crossings
	asr.w	#1,d0                           ; pairs
	subq.w	#1,d0                           ; (for dbra; a1 back at the crossings, set by the sort)
	tst.w	$36(a4)                         ; clipping?
	bne.w	blit_fill_row_clip_span         ; yes
blit_fill_row_span:
	move.w	(a1)+,$26(a4)                   ; from x
	move.w	(a1)+,$2a(a4)                   ; to x
	move.w	d0,-(sp)                        ; kept
	move.l	a1,-(sp)                        ; kept
	bsr.w	blit_fill_span                  ; the span filled
	movea.l	(sp)+,a1                        ; back
	move.w	(sp)+,d0
	dbra	d0,blit_fill_row_span           ; the next pair
	rts                                     ; done
blit_fill_row_clip_span:
	move.w	(a1)+,$26(a4)                   ; from x
	move.w	(a1)+,$2a(a4)                   ; to x
	move.w	$38(a4),d1                      ; the left clip
	move.w	$26(a4),d2                      ; from x
	move.w	$2a(a4),d3                      ; to x
	cmp.w	d1,d2                           ; left of it?
	bge.w	blit_fill_row_clip_right        ; no
	cmp.w	d1,d3                           ; the right end left of it too?
	blt.w	blit_fill_row_clip_next         ; all left of it: skipped
	move.w	d1,$26(a4)                      ; clipped
blit_fill_row_clip_right:
	move.w	$3c(a4),d1                      ; the right clip
	cmp.w	d1,d3                           ; right of it?
	ble.w	blit_fill_row_clip_draw         ; no
	cmp.w	d1,d2                           ; the left end right of it too?
	bgt.w	blit_fill_row_clip_next         ; all right of it: skipped
	move.w	d1,$2a(a4)                      ; clipped
blit_fill_row_clip_draw:
	move.w	d0,-(sp)                        ; kept
	move.l	a1,-(sp)                        ; kept
	bsr.w	blit_fill_span                  ; the span filled
	lea	draw_planes.w,a4                ; the drawing variables again
	movea.l	(sp)+,a1                        ; back
	move.w	(sp)+,d0
blit_fill_row_clip_next:
	dbra	d0,blit_fill_row_clip_span      ; the next pair
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_sort_crossings: sorts d0 words at a0 into ascending order (bubble sort).  Out: a1 = a0 on entry when
;  d0 is 2 or more.  Uses d0-d2, a0-a1.
;------------------------------------------------------------------------------
blit_sort_crossings:	; from: blit_fill_row
	subq.w	#2,d0                           ; fewer than 2: done
	bcs.w	blit_sort_crossings_end         ; (fewer than 2)
	move.w	d0,d1                           ; passes
	movea.l	a0,a1                           ; the start
blit_sort_crossings_pass:
	move.w	d1,d0                           ; the comparisons
	movea.l	a1,a0                           ; from the start
blit_sort_crossings_compare:
	move.w	(a0)+,d2                        ; this one
	cmp.w	(a0),d2                         ; in order?
	ble.w	blit_sort_crossings_next        ; yes
	move.w	(a0),-$2(a0)                    ; swapped
	move.w	d2,(a0)                         ; (swapped)
blit_sort_crossings_next:
	dbra	d0,blit_sort_crossings_compare  ; the next pair
	dbra	d1,blit_sort_crossings_pass     ; the next pass
blit_sort_crossings_end:
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_line: draws a line from x1,y1 to x2,y2 ($34E-$354) with the line mask $34A, the writing mode $34C
;  and the colour bits $340 onto the screen at $29A, as Line-A's line does.  A vertical line is BLiTted
;  one plane at a time, the line mask spread into the halftone RAM; a horizontal one goes to blit_span; any
;  other is drawn by the CPU (blit_line_routines).  The line mask is rotated by the line's length.  In XOR
;  mode the last pixel is left out unless $348 is set.  Changes d0-d7, a0-a5.
;------------------------------------------------------------------------------
blit_line:	; from: blit_long_outline
	lea	draw_planes.w,a4                ; the drawing variables
	moveq	#2,d0                           ; XOR mode is 2
	movem.w	$26(a4),d4-d7                   ; x1, y1, x2, y2
	cmp.w	d5,d7                           ; horizontal?
	beq.w	blit_line_horizontal            ; yes
	cmp.w	d4,d6                           ; vertical?
	bne.w	blit_line_diagonal              ; no: the CPU draws it
	lea	$ff8a3c,a5                      ; BLiTTER control, the BLiTTER
	not.w	d4                              ; the pixel's bit
	and.w	#$f,d4                          ; (0-15 from the left)
	clr.w	d0
	bset	d4,d0                           ; its mask
	move.w	d0,-$14(a5)                     ; end mask 1
	move.w	0(a4),d0                        ; planes
	move.w	d0,d1                           ; bytes per word group
	add.w	d1,d1                           ; (2 bytes a plane)
	subq.w	#1,d0                           ; planes - 1
	movea.l	screen_base.w,a1                ; the screen
	asr.w	#4,d6                           ; x's word
	muls.w	d6,d1                           ; times the word group size
	adda.l	d1,a1                           ; the word's column
	move.w	-$2(a4),d2                      ; bytes per line
	muls.w	d5,d2                           ; times y1
	adda.l	d2,a1                           ; the first pixel's word
	moveq	#7,d2                           ; 16 halftone words
	move.w	2(a4),d1                        ; bytes per line
	lea	$22(a4),a3                      ; the line mask
	move.w	(a3),d3                         ; the line mask
	sub.w	d5,d7                           ; the height
	bge.w	blit_line_vertical_down         ; downwards?
	neg.w	d7                              ; upwards
	neg.w	d1                              ; going up
	lea	-$1c(a5),a0                     ; the halftone RAM filled from the end
blit_line_vertical_up_mask:
	add.w	d3,d3                           ; each mask bit
	subx.w	d4,d4                           ; to a 0 or $FFFF word
	move.w	d4,-(a0)                        ; (twice a loop)
	add.w	d3,d3
	subx.w	d4,d4
	move.w	d4,-(a0)
	dbra	d2,blit_line_vertical_up_mask   ; 16 times
	move.w	#$8f00,d2                       ; busy, from halftone line 15
	bra.w	blit_line_vertical_set_up       ; on
blit_line_vertical_down:
	lea	-$3c(a5),a0                     ; the halftone RAM filled from the start
blit_line_vertical_down_mask:
	add.w	d3,d3                           ; each mask bit
	subx.w	d4,d4                           ; to a 0 or $FFFF word
	move.w	d4,(a0)+                        ; (twice a loop)
	add.w	d3,d3
	subx.w	d4,d4
	move.w	d4,(a0)+
	dbra	d2,blit_line_vertical_down_mask ; 16 times
	move.w	#$8000,d2                       ; busy, from halftone line 0
blit_line_vertical_set_up:
	move.w	d1,-$c(a5)                      ; destination y increment
	addq.w	#1,d7                           ; the pixel count
	lea	blit_mode_operations(pc),a2     ; the writing mode's operations
	move.w	$24(a4),d1                      ; the writing mode
	lsl.w	#2,d1                           ; 4 bytes a mode
	adda.w	d1,a2                           ; its entry
	subq.w	#8,d1                           ; XOR?
	bne.w	blit_line_vertical_count        ; no
	tst.w	$20(a4)                         ; the last pixel drawn?
	bne.w	blit_line_vertical_count        ; yes
	subq.w	#1,d7                           ; no: one less
blit_line_vertical_count:
	move.w	d7,d1                           ; the count
	move.w	(a3),d3                         ; the line mask
	and.w	#$f,d1                          ; its low 4 bits
	rol.w	d1,d3                           ; rotated by the length
	move.w	d3,(a3)                         ; kept
	lea	$18(a4),a3                      ; the colour bits
	moveq	#2,d4                           ; the offset for a set bit
	move.w	#$1,-$6(a5)                     ; one word wide
blit_line_vertical_plane:
	move.l	a1,-$a(a5)                      ; destination
	move.w	d7,-$4(a5)                      ; y count
	tst.w	(a3)+                           ; this plane's colour bit
	sne	d3                              ; $FF when set
	and.w	d4,d3                           ; 0 or 2
	move.w	0(a2,d3.w),-$2(a5)              ; HOP and operation
	move.w	d2,(a5)                         ; go
	moveq	#7,d1                           ; the busy bit
blit_line_vertical_wait:
	bset	d1,(a5)                         ; restarted until done
	nop                                     ; (the BLiTTER runs)
	bne.s	blit_line_vertical_wait         ; still busy
	addq.w	#2,a1                           ; the next plane
	dbra	d0,blit_line_vertical_plane     ; the next plane
	rts                                     ; done
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
	exg	d4,d6                           ; left to right
blit_line_horizontal_ordered:
	move.w	d6,d1                           ; the length
	sub.w	d4,d1
	addq.w	#1,d1                           ; (pixels)
	and.w	#$f,d1                          ; the rotation
	lea	$22(a4),a0                      ; the line mask as the pattern
	clr.w	d0                              ; no pattern step
	move.w	d1,-(sp)                        ; kept
	bsr.w	blit_span                       ; the span
	move.w	(sp)+,d1                        ; back
	move.w	(a0),d0                         ; the line mask
	rol.w	d1,d0                           ; rotated by the length
	move.w	d0,(a0)                         ; kept
	rts                                     ; done
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
	exg	d5,d7                           ; with y1 and y2
blit_line_diagonal_set_up:
	sub.w	d4,d6                           ; dx
	moveq	#0,d1                           ; the pixel's bit to come
	movea.l	d1,a5                           ; the routine index
	move.w	d4,d0                           ; the first pixel's bit
	not.w	d0                              ; x1 AND 15 counted from the left
	and.w	#$f,d0                          ; AND 15
	bset	d0,d1                           ; d1: the first pixel's bit
	movea.l	screen_base.w,a0                ; the screen
	move.w	0(a4),d3                        ; planes
	add.w	d3,d3                           ; bytes per word group
	move.w	-$2(a4),d2                      ; bytes per line
	muls.w	d5,d2                           ; times y1
	adda.l	d2,a0                           ; the first pixel's line
	asr.w	#4,d4                           ; x's word
	muls.w	d3,d4                           ; times the word group size
	adda.l	d4,a0                           ; the first pixel's word
	move.w	2(a4),d0                        ; bytes per line
	sub.w	d5,d7                           ; dy
	bge.w	blit_line_diagonal_down         ; downwards?
	neg.w	d7                              ; dy made positive
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
	move.w	d4,d5                           ; d5: 2 dx, added while the error is positive
	sub.w	d7,d4                           ; 2 dx - dy: the error term
	move.w	d4,d6                           ; d6 = 2 dx - 2 dy
	sub.w	d7,d6                           ; 2 dx - 2 dy
	move.w	$24(a4),d0                      ; the writing mode
	lsl.w	#2,d0                           ; 4 bytes a mode
	adda.w	d0,a5                           ; the mode's routine pair
	subq.w	#8,d0                           ; XOR?
	bne.w	blit_line_diagonal_mask         ; no
	tst.w	$20(a4)                         ; the last pixel drawn?
	bne.w	blit_line_diagonal_mask         ; yes
	subq.w	#1,d7                           ; no: one less
blit_line_diagonal_mask:
	lea	$22(a4),a3                      ; the line mask
	move.w	(a3),d0                         ; the line mask
	move.w	d7,d2                           ; the length
	addq.w	#1,d2                           ; the length
	and.w	#$f,d2                          ; AND 15
	rol.w	d2,d0                           ; rotated by the length
	move.w	(a3),d2                         ; the mask now
	move.w	d0,(a3)                         ; the line mask for the next line
	move.w	d1,d0                           ; the bit
	not.w	d0                              ; and the mask to clear it
	lea	blit_line_routines(pc,a5.w),a5  ; the routine
	movea.l	a5,a3                           ; a3: the routine pair
	adda.w	(a5)+,a3                        ; its step part
	movea.l	a3,a4                           ; its clear-a-pixel part
	suba.w	d3,a4                           ; back by the planes
	adda.w	(a5),a5                         ; its start
	jsr	(a5)                            ; the line drawn
blit_line_diagonal_end:
	lea	$14(sp),sp                      ; the stack space freed
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_line_routines: two word offsets for each writing mode (replace, transparent, XOR, reverse
; transparent), y major lines first, then x major: the CPU line routine's step part and its start,
; each relative to its own word (the routines are in blit_line_opcodes).
;------------------------------------------------------------------------------
blit_line_routines:	; from: blit_line
	dc.w	$006a,$004a,$0094,$0088,$00cc,$00b0,$008c,$007e ; pairs of offsets (step part, start), y major then x
                                                ;   major, by writing mode
	dc.w	$0102,$00e2,$012c,$0120,$0164,$0148,$0124,$0116 ; then x major: replace, transparent, XOR, reverse
                                                ;   transparent

;------------------------------------------------------------------------------
; blit_line_plane_code: builds the per-plane code at a2 for the CPU line routines: "and.w d0,(a5)+"
; for each plane whose colour bit is 0, "or.w d1,(a5)+" for each one whose bit is 1, then
; "jmp (a3)".  In: d3 the planes.  Uses d0-d3, a0-a1.
;------------------------------------------------------------------------------
blit_line_plane_code:	; from: blit_line
	subq.w	#1,d3                           ; planes - 1
	movem.w	blit_line_opcodes(pc),d0-d2     ; the three instructions
	movea.l	a2,a0                           ; where the plane code goes
	lea	$18(a4),a1                      ; the colour bits
blit_line_plane_code_plane:
	tst.w	(a1)+                           ; bit set?
	bne.s	blit_line_plane_code_set        ; yes
	move.w	d0,(a0)+                        ; "and.w d0,(a5)+": cleared
	dbra	d3,blit_line_plane_code_plane   ; the next plane
	move.w	d2,(a0)+                        ; "jmp (a3)"
	rts                                     ; done
blit_line_plane_code_set:
	move.w	d1,(a0)+                        ; "or.w d1,(a5)+": set
	dbra	d3,blit_line_plane_code_plane   ; the next plane
	move.w	d2,(a0)+                        ; "jmp (a3)"
	rts                                     ; done

;------------------------------------------------------------------------------
; blit_line_opcodes: "and.w d0,(a5)+", "or.w d1,(a5)+" and "jmp (a3)", then the CPU line routines
; (code, reached only through blit_line_routines, so shown as words).  Each one rotates the line
; mask: in replace mode a set bit runs the plane code built on the stack and a clear one jumps into
; the run of "and.w d0,(a5)+" to clear the pixel in each plane; in transparent modes a clear bit
; leaves the pixel; in XOR mode a set bit runs "eor.w d1,(a5)+" for each plane.  Then the
; Bresenham terms are stepped, over d7 pixels.
;------------------------------------------------------------------------------
blit_line_opcodes:	; from: blit_line_plane_code
	dc.w	$c15d,$835d,$4ed3               ; and.w d0,(a5)+ / or.w d1,(a5)+ / jmp (a3)
blit_line_y_replace:
	dc.w	$e35a,$6400,$0006,$2a48,$4ed2,$2a48,$4ed4,$c15d ; rol.w #1,d2; bcc.w +6; movea.l a0,a5; jmp (a2);
                                                ;   movea.l a0,a5; jmp (a4); and.w d0,(a5)+...
	dc.w	$c15d,$c15d,$c15d,$c15d,$c15d,$c15d,$c15d ; ...and.w d0,(a5)+ for 8 planes: the pixel cleared
blit_line_y_replace_step:
	dc.w	$d0c9                           ; adda.w a1,a0: the next line
	dc.b	'JDk',0                         ; tst.w d4 (error term)
	dc.w	$0014,$e258,$e259,$6400,$0004,$d0c3,$d846,$51cf ; bmi.w; ror.w #1,d0; ror.w #1,d1; bcc.w; adda.w d3,a0
                                                ;   (next word group); add.w d6,d4; dbra d7
	dc.w	$ffcc,$4e75,$d845,$51cf,$ffc4,$4e75 ; ...; rts; add.w d5,d4; dbra d7; rts
blit_line_y_reverse:
	dc.w	$4642                           ; not.w d2: the mask inverted, then as transparent
blit_line_y_transparent:
	dc.w	$e35a,$6400,$0006,$2a48,$4ed2   ; rol.w #1,d2; bcc.w +6 (bit clear: pixel left); movea.l a0,a5; jmp (a2)
blit_line_y_transparent_step:
	dc.w	$d0c9                           ; adda.w a1,a0: the next line
	dc.b	'JDk',0                         ; tst.w d4 (error term)
	dc.w	$0014,$e258,$e259,$6400,$0004,$d0c3,$d846,$51cf ; bmi.w; ror.w #1,d0; ror.w #1,d1; bcc.w; adda.w d3,a0;
                                                ;   add.w d6,d4; dbra d7
	dc.w	$ffe0,$4e75,$d845,$51cf,$ffd8,$4e75 ; ...; rts; add.w d5,d4; dbra d7; rts
blit_line_y_xor:
	dc.w	$e35a,$6400,$0016,$2a48,$4ed4,$b35d,$b35d,$b35d ; rol.w #1,d2; bcc.w +$16; movea.l a0,a5; jmp (a4);
                                                ;   eor.w d1,(a5)+...
	dc.w	$b35d,$b35d,$b35d,$b35d,$b35d   ; ...eor.w d1,(a5)+ for 8 planes
blit_line_y_xor_step:
	dc.w	$d0c9                           ; adda.w a1,a0: the next line
	dc.b	'JDk',0                         ; tst.w d4 (error term)
	dc.w	$0012,$e259,$6400,$0004,$d0c3,$d846,$51cf,$ffd2 ; bmi.w; ror.w #1,d1; bcc.w; adda.w d3,a0; add.w d6,d4;
                                                ;   dbra d7
	dc.w	$4e75,$d845,$51cf,$ffca,$4e75   ; rts; add.w d5,d4; dbra d7; rts
blit_line_x_replace:
	dc.w	$e35a,$6400,$0006,$2a48,$4ed2,$2a48,$4ed4,$c15d ; rol.w #1,d2; bcc.w +6; movea.l a0,a5; jmp (a2);
                                                ;   movea.l a0,a5; jmp (a4); and.w d0,(a5)+...
	dc.w	$c15d,$c15d,$c15d,$c15d,$c15d,$c15d,$c15d ; ...and.w d0,(a5)+ for 8 planes: the pixel cleared
blit_line_x_replace_step:
	dc.w	$e258,$e259,$6400,$0004,$d0c3   ; ror.w #1,d0; ror.w #1,d1; bcc.w; adda.w d3,a0: the next pixel along
	dc.b	'JDk',0                         ; tst.w d4 (error term)
	dc.w	$000c,$d846,$d0c9,$51cf,$ffcc,$4e75,$d845,$51cf ; bmi.w; add.w d6,d4; adda.w a1,a0 (next line); dbra d7;
                                                ;   rts; add.w d5,d4; dbra d7
	dc.w	$ffc4,$4e75                     ; ...; rts
blit_line_x_reverse:
	dc.w	$4642                           ; not.w d2: the mask inverted, then as transparent
blit_line_x_transparent:
	dc.w	$e35a,$6400,$0006,$2a48,$4ed2   ; rol.w #1,d2; bcc.w +6 (bit clear: pixel left); movea.l a0,a5; jmp (a2)
blit_line_x_transparent_step:
	dc.w	$e258,$e259,$6400,$0004,$d0c3   ; ror.w #1,d0; ror.w #1,d1; bcc.w; adda.w d3,a0: the next pixel along
	dc.b	'JDk',0                         ; tst.w d4 (error term)
	dc.w	$000c,$d846,$d0c9,$51cf,$ffe0,$4e75,$d845,$51cf ; bmi.w; add.w d6,d4; adda.w a1,a0 (next line); dbra d7;
                                                ;   rts; add.w d5,d4; dbra d7
	dc.w	$ffd8,$4e75                     ; ...; rts
blit_line_x_xor:
	dc.w	$e35a,$6400,$0016,$2a48,$4ed4,$b35d,$b35d,$b35d ; rol.w #1,d2; bcc.w +$16; movea.l a0,a5; jmp (a4);
                                                ;   eor.w d1,(a5)+...
	dc.w	$b35d,$b35d,$b35d,$b35d,$b35d   ; ...eor.w d1,(a5)+ for 8 planes
blit_line_x_xor_step:
	dc.w	$e259,$6400,$0004,$d0c3         ; ror.w #1,d1; bcc.w; adda.w d3,a0: the next pixel along
	dc.b	'JDk',0                         ; tst.w d4 (error term)
	dc.w	$000c,$d846,$d0c9,$51cf,$ffd2,$4e75,$d845,$51cf ; bmi.w; add.w d6,d4; adda.w a1,a0 (next line); dbra d7;
                                                ;   rts; add.w d5,d4; dbra d7
	dc.w	$ffca,$4e75                     ; ...; rts
blit_mode_operations:	; from: blit_line, blit_span
	dc.w	$0100,$0103,$0104,$0107,$0106,$0106,$0101,$010d ; HOP 1 and the op for a 0 and a 1 colour bit: replace,
                                                ;   transparent, XOR, reverse transparent
blit_left_masks:	; from: blit_span
	dc.w	$ffff                           ; the first word's mask by x AND 15 (runs on into the next table)
blit_right_masks:	; from: blit_span
	dc.w	$7fff,$3fff,$1fff,$0fff,$07ff,$03ff,$01ff,$00ff ; inverted: the last word's mask by x AND 15
	dc.w	$007f,$003f,$001f,$000f,$0007,$0003,$0001,$0000 ; (16 entries; x2 AND 15 = 15 gives 0, inverted $FFFF)

;------------------------------------------------------------------------------
; blit_fill_span: fills from x1 to x2 ($34E, $352) on line y1 ($350) with the fill pattern's line
; (y1 AND the pattern mask; a new pattern per plane when multi-fill is set).  blit_span is the same
; with a0 the pattern word and d0 the step to the next plane's pattern.  The BLiTTER does each
; plane with HOP 1 and the writing mode's operation.  Uses d0-d7, a0-a5.
;------------------------------------------------------------------------------
blit_fill_span:	; from: blit_fill_row
	lea	draw_planes.w,a4                ; the drawing variables
	movem.w	$26(a4),d4-d6                   ; x1, y1, x2
	move.w	d5,d0                           ; the pattern line
	and.w	$32(a4),d0                      ; the pattern mask
	add.w	d0,d0                           ; a word a line
	movea.l	$2e(a4),a0                      ; the patterns
	adda.w	d0,a0                           ; the pattern line
	tst.w	$34(a4)                         ; multi-fill?
	sne	d0                              ; multi-fill?
	and.w	#$20,d0                         ; then 32 bytes to the next plane's

blit_span:	; from: blit_line
	move.w	d4,d1                           ; the first word
	asr.w	#4,d1                           ; x1's word
	move.w	d6,d2                           ; the last word
	asr.w	#4,d2                           ; x2's word
	moveq	#15,d3                          ; the bit mask
	and.w	d3,d4                           ; x1 AND 15
	add.w	d4,d4                           ; as a word index
	move.w	blit_left_masks(pc,d4.w),d4     ; the left mask
	and.w	d3,d6                           ; x2 AND 15
	add.w	d6,d6                           ; as a word index
	move.w	blit_right_masks(pc,d6.w),d6    ; the right mask
	not.w	d6                              ; the right mask
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
	move.w	d2,d7                           ; the plane count
	subq.w	#1,d7                           ; planes - 1
	add.w	d2,d2                           ; bytes per word group
	move.w	d2,(a3)+                        ; destination x increment
	movea.l	screen_base.w,a1                ; the screen
	muls.w	-$2(a4),d5                      ; times y1
	adda.l	d5,a1                           ; the line
	muls.w	d2,d1                           ; x's word
	adda.l	d1,a1                           ; the first word
	lea	-$3c(a5),a2                     ; the halftone RAM
	lea	$18(a4),a3                      ; the colour bits
	move.w	$24(a4),d2                      ; the writing mode
	add.w	d2,d2                           ; the mode
	add.w	d2,d2                           ; 4 bytes a mode
	lea	blit_mode_operations(pc),a4     ; its operations
	adda.w	d2,a4                           ; the mode's pair of operations
	moveq	#2,d3                           ; the offset for a set bit
	move.w	#$8000,d4                       ; busy
	moveq	#1,d6                           ; one line
blit_span_plane:
	move.w	(a0),(a2)                       ; the pattern word
	adda.w	d0,a0                           ; the next plane's
	move.l	a1,-$a(a5)                      ; destination
	move.w	d6,-$4(a5)                      ; y count
	tst.w	(a3)+                           ; this plane's colour bit
	sne	d2                              ; set?
	and.w	d3,d2                           ; 0 or 2
	move.w	0(a4,d2.w),-$2(a5)              ; HOP and operation
	move.w	d4,(a5)                         ; go
	moveq	#7,d5                           ; the BUSY bit (bit 7 of the control byte)
blit_span_wait:
	bset	d5,(a5)                         ; restarted until done
	nop                                     ; (the bset restarts the BLiTTER while it is busy)
	bne.s	blit_span_wait                  ; still busy
	addq.l	#2,a1                           ; the next plane
	dbra	d7,blit_span_plane              ; each plane
	rts                                     ; done

;------------------------------------------------------------------------------
; put_tab: prints a tab (5 spaces).  d1 kept.
;------------------------------------------------------------------------------
put_tab:	; from: menu_start, floppy_speed_test
	move.w	d1,-(sp)                        ; kept
	move.w	#$9,d1                          ; tab
	bsr.w	put_char                        ; printed
	move.w	(sp)+,d1                        ; back
	rts

;------------------------------------------------------------------------------
; put_backspace: moves the cursor back one, rubbing out the character there.  Changes d1.
;------------------------------------------------------------------------------
put_backspace:	; from: read_command, read_line
	move.w	#$8,d1                          ; backspace
	bsr.w	put_char                        ; printed
	rts

;------------------------------------------------------------------------------
; show_result: ends a test.  In: a5 "Pass" or a failure text.  "Pass" goes on the status line at
; column 66; anything else is printed with the cycle count ($216) in hex and a new line.
;------------------------------------------------------------------------------
show_result:	; from: run_q_tests, ram_test, rom_test, keyboard_test, midi_test, rs232_test, 7 more
	cmpa.l	#msg_pass,a5                    ; "Pass"?
	bne.s	show_result_fail                ; no
	moveq	#66,d0                          ; column 66
	moveq	#0,d1                           ; on the top line
	bra.s	show_status_at                  ; printed there
show_result_fail:
	bsr.w	print_string                    ; the failure text
	movea.l	test_cycle.w,a0                 ; the cycle
	bsr.w	print_hex_address               ; in hex
	bsr.w	print_newline                   ; and a new line
	rts

;------------------------------------------------------------------------------
; show_status_after: prints a5 on the status line after the last status text.  Not called.
;------------------------------------------------------------------------------
show_status_after:
	moveq	#0,d1                           ; the top line
	move.w	status_end_column.w,d0          ; after the last text
	bra.s	show_status_at                  ; printed there

;------------------------------------------------------------------------------
; show_status: clears the status line (the top line) and prints a5 at its start.  All registers kept.
;------------------------------------------------------------------------------
show_status:	; from: run_q_tests, ram_test, rom_test, keyboard_test, midi_test, rs232_test, 10 more
	movem.l	d0-d1,-(sp)                     ; kept
	moveq	#0,d0                           ; column 0
	moveq	#0,d1                           ; the top line
	bsr.w	show_status_at                  ; printed there
	movem.l	(sp)+,d0-d1                     ; back
	rts

;------------------------------------------------------------------------------
; show_status_at: clears the top line and prints a5 there at column d0, line d1, the cursor put back
; afterwards; $20C = the column after the text.  All registers kept.
;------------------------------------------------------------------------------
show_status_at:                                 ; from: ram_test, ram_test_star_vbl, dma_sound_test, floppy_quick_test,
                                                ;   show_result, show_status_after, 1 more
	movem.l	d0-d7/a0-a6,-(sp)               ; all kept
	move.l	a5,-(sp)                        ; the text
	movem.l	d0-d1,-(sp)                     ; the place
	move.w	cursor_column.w,status_saved_column.w ; the cursor kept
	move.w	cursor_row.w,status_saved_row.w ; the cursor's row kept
	bsr.w	set_cursor                      ; to the top line's start
	bsr.w	clear_to_line_end               ; cleared to its end
	movem.l	(sp)+,d0-d1                     ; the place
	bsr.w	set_cursor                      ; to the place
	movea.l	(sp)+,a5                        ; the text
	bsr.w	print_string                    ; printed
	move.w	cursor_column.w,status_end_column.w ; the column after it
	move.w	status_saved_column.w,d0        ; the cursor back
	move.w	status_saved_row.w,d1           ; and row
	bsr.w	set_cursor                      ; the cursor back
	movem.l	(sp)+,d0-d7/a0-a6               ; all back
	rts

;------------------------------------------------------------------------------
; print_string: prints the 0-ended text at a5 on the screen (and the RS232 terminal).  All
; registers kept.
;------------------------------------------------------------------------------
print_string:	; from: check_bus_error, menu_start, ask_stopped, print_cycle, read_command, cmd_rs232_rate, 66 more
	movem.l	d0-d7/a0-a6,-(sp)               ; all kept
print_string_loop:
	move.b	(a5)+,d1                        ; the next character
	cmp.b	#$0,d1                          ; the end?
	beq.s	print_string_end                ; yes
	move.l	a5,-(sp)                        ; kept
	bsr.w	put_char                        ; printed
	movea.l	(sp)+,a5                        ; back
	bra.s	print_string_loop               ; the next
print_string_end:
	movem.l	(sp)+,d0-d7/a0-a6               ; all back
	rts

;------------------------------------------------------------------------------
; print_menu_string: prints the 0-ended text at a5; a 5 byte shows the next character in inverse
; (the menu's letters).  All registers kept.
;------------------------------------------------------------------------------
print_menu_string:	; from: menu_start
	movem.l	d0-d7/a0-a6,-(sp)               ; all kept
print_menu_string_loop:
	move.b	(a5)+,d1                        ; the next character
	cmp.b	#$0,d1                          ; the end?
	beq.s	print_menu_string_end           ; yes
	cmp.b	#$5,d1                          ; 5?
	bne.w	print_menu_string_char          ; no
	bsr.w	inverse_on                      ; the next character in inverse
	bra.s	print_menu_string_loop          ; the next
print_menu_string_char:
	move.l	a5,-(sp)                        ; kept
	bsr.w	put_char                        ; printed
	movea.l	(sp)+,a5                        ; back
	bsr.w	inverse_off                     ; back to normal
	bra.s	print_menu_string_loop          ; the next
print_menu_string_end:
	movem.l	(sp)+,d0-d7/a0-a6               ; all back
	rts

;------------------------------------------------------------------------------
; serial_put_char: sends d1.b out of the MFP's RS232 port, turning the transmitter on first if it was
; off.  Gives up after a time-out when the port never empties.  All registers kept.
;------------------------------------------------------------------------------
serial_put_char:	; from: menu_start, clear_screen, put_char
	move.w	d0,-(sp)                        ; kept
	btst	#$0,$fffffa2d.w                 ; MFP TSR, the transmitter on?
	bne.s	serial_put_char_timed           ; yes
	move.b	#$1,$fffffa2d.w                 ; MFP TSR, turned on
	bsr.w	delay                           ; a short wait
serial_put_char_timed:
	move.l	#$a53c,d0                       ; the time-out (counted as a word)
serial_put_char_wait:
	subi.w	#$1,d0                          ; one count gone
	beq.s	serial_put_char_end             ; time-out: not sent
	tst.b	$fffffa2d.w                     ; MFP TSR, the buffer empty?
	bpl.s	serial_put_char_wait            ; not yet
	move.w	#$3e8,d0                        ; a short wait
serial_put_char_delay:
	dbra	d0,serial_put_char_delay        ; the wait
	move.b	d1,$fffffa2f.w                  ; MFP UDR, sent
serial_put_char_end:
	move.w	(sp)+,d0                        ; back
	rts

;------------------------------------------------------------------------------
; print_hex_long: prints d1.l as 8 hex digits.  Not called.
;------------------------------------------------------------------------------
print_hex_long:
	move.l	d1,-(sp)                        ; kept
	swap	d1                              ; the high word
	bsr.w	print_hex_word                  ; printed
	swap	d1                              ; the low word
	bsr.w	print_hex_word                  ; printed
	move.l	(sp)+,d1                        ; back
	rts

;------------------------------------------------------------------------------
; print_hex_address: prints a0 as 6 hex digits.  Uses d1.
;------------------------------------------------------------------------------
print_hex_address:	; from: print_cycle, bus_error_handler, memory_utility, print_ram_error, show_result, hd_test
	move.l	a0,d1                           ; the address
	swap	d1                              ; the high byte
	move.l	a0,-(sp)                        ; kept
	bsr.w	print_hex_byte                  ; the high byte printed
	move.l	(sp)+,d1                        ; the low word
	bsr.w	print_hex_word                  ; printed
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
	lsr.w	#8,d1                           ; the top digit
	bsr.w	print_hex_digit                 ; printed
	bra.s	print_hex_word_low              ; then the low byte

;------------------------------------------------------------------------------
; print_hex_word: prints d1.w as 4 hex digits; print_hex_byte prints d1.b as 2, print_hex_digit
; prints d1's low 4 bits as one.  d1 kept.
;------------------------------------------------------------------------------
print_hex_word:                                 ; from: memory_utility, print_ram_error, check_rom_sums,
                                                ;   printer_joystick_test, print_light_gun_values, floppy_speed_test, 7
                                                ;   more
	move.w	d1,-(sp)                        ; kept
	lsr.w	#8,d1                           ; the high byte
	bsr.w	print_hex_byte                  ; printed
print_hex_word_low:	; from: print_hex_short
	move.w	(sp)+,d1                        ; the low byte
	bsr.w	print_hex_byte                  ; printed
	rts
print_hex_short_byte:	; from: print_hex_short
	cmpi.b	#$f,d1                          ; one digit only?
	bls.w	print_hex_byte_low              ; yes

print_hex_byte:                                 ; from: memory_utility, printer_joystick_test, print_sector_number,
                                                ;   print_track_number, print_floppy_error, print_hex_address, 2 more
	move.b	d1,-(sp)                        ; kept
	lsr.w	#4,d1                           ; the high digit
	bsr.w	print_hex_digit                 ; printed
	move.b	(sp)+,d1                        ; back
print_hex_byte_low:	; from: print_hex_word
	bsr.w	print_hex_digit                 ; the low digit
	rts

print_hex_digit:                                ; from: menu_start, print_tos_version, print_side_number,
                                                ;   print_hex_short, print_hex_byte, print_decimal_teen
	move.l	d1,-(sp)                        ; kept
	andi.b	#$f,d1                          ; the digit
	cmp.b	#$9,d1                          ; 0-9?
	bls.s	print_hex_digit_numeral         ; yes
	and.w	#$7,d1                          ; "A"-"F"
	subq.w	#1,d1                           ; 10-15 -> 1-6 ...
	ori.b	#$40,d1                         ; ... "A"-"F"
print_hex_digit_put:
	bsr.w	put_char                        ; printed
	move.l	(sp)+,d1                        ; back
	rts
print_hex_digit_numeral:
	ori.b	#$30,d1                         ; "0"-"9"
	bra.s	print_hex_digit_put             ; printed

;------------------------------------------------------------------------------
; print_decimal_teen: prints d1.b (0-19) in decimal.
;------------------------------------------------------------------------------
print_decimal_teen:	; from: print_bad_bits
	cmpi.b	#$a,d1                          ; 10 or more?
	blt.w	print_decimal_teen_units        ; no
	move.l	d1,-(sp)                        ; kept
	moveq	#1,d1                           ; "1"
	bsr.s	print_hex_digit                 ; printed
	move.l	(sp)+,d1                        ; back
	subi.b	#$a,d1                          ; the units
print_decimal_teen_units:
	bsr.s	print_hex_digit                 ; printed
	rts

;------------------------------------------------------------------------------
; print_spaces: prints d1 spaces (d1 at least 1).  d1 ends at 0.
;------------------------------------------------------------------------------
print_spaces:	; from: clear_status_line, print_track_number, put_char
	bsr.w	print_space                     ; one space
	subq.w	#1,d1                           ; the count
	bne.s	print_spaces                    ; more
	rts

;------------------------------------------------------------------------------
; print_space: prints a space.  All registers kept.
;------------------------------------------------------------------------------
print_space:                                    ; from: memory_utility, print_ram_error, print_bad_bits,
                                                ;   print_tos_version, keyboard_test, print_light_gun_values, 8 more
	move.l	d1,-(sp)                        ; kept
	move.b	#$20,d1                         ; a space
	bsr.w	put_char                        ; printed
	move.l	(sp)+,d1                        ; back
	rts

;------------------------------------------------------------------------------
; print_newline: prints a carriage return and a line feed.  All registers kept.
;------------------------------------------------------------------------------
print_newline:                                  ; from: menu_start, run_q_tests, print_cycle, bus_error_handler,
                                                ;   exception_error_handler, memory_utility, 20 more
	move.l	d1,-(sp)                        ; kept
	moveq	#13,d1                          ; CR
	bsr.w	put_char                        ; printed
	moveq	#10,d1                          ; LF
	bsr.w	put_char                        ; printed
	move.l	(sp)+,d1                        ; back
	rts

;------------------------------------------------------------------------------
; clear_screen: clears the screen (no lines kept at the top), sends CR LF to the RS232 terminal
; when it is on, and homes the cursor.  All registers kept.
;------------------------------------------------------------------------------
clear_screen:                                   ; from: low_ram_test, check_bus_error, startup_timing_checks,
                                                ;   menu_start, read_command, cmd_rs232_rate, 11 more
	movem.l	d0-d7/a0-a6,-(sp)               ; all kept
	clr.w	scroll_top.w                    ; scrolling from the top line
	btst	#$1,mode_flags.w                ; the terminal off?
	bne.s	clear_screen_home               ; yes
	move.b	#$d,d1                          ; CR
	bsr.w	serial_put_char                 ; to the terminal
	move.b	#$a,d1                          ; LF
	bsr.w	serial_put_char                 ; to the terminal
clear_screen_home:
	bsr.w	cursor_home                     ; the cursor home
	bsr.w	clear_to_screen_end             ; cleared to the end
	movem.l	(sp)+,d0-d7/a0-a6               ; all back
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
	moveq	#0,d0                           ; 0 for the rest
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
	moveq	#0,d1                           ; the clear long
init_text_screen_clear:
	move.l	d1,(a0)+                        ; cleared
	dbra	d0,init_text_screen_clear       ; 32K
	rts

;------------------------------------------------------------------------------
; get_screen_mode: reads the screen address from the video base registers into $29A and sets the
; planes, bytes per line, height and width for the resolution (left alone for resolution 3).
; Uses d0-d1.
;------------------------------------------------------------------------------
get_screen_mode:	; from: init_text_screen
	moveq	#0,d0                           ; the address built in d0
	move.b	$ffff8201.w,d0                  ; video base high, the screen
	asl.l	#8,d0                           ; in the next byte
	move.b	$ffff8203.w,d0                  ; video base mid
	asl.l	#8,d0                           ; in bits 23-8
	move.l	d0,screen_base.w                ; the screen's address
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	moveq	#3,d1                           ; the resolution bits
	and.w	d1,d0                           ; the resolution
	cmp.w	d1,d0                           ; 3?
	beq.s	get_screen_mode_end             ; yes: unchanged
	move.b	screen_planes_by_res(pc,d0.w),d1 ; planes
	move.w	d1,screen_planes.w              ; planes
	move.b	screen_line_bytes_by_res(pc,d0.w),d1 ; bytes per line
	move.w	d1,screen_line_bytes.w          ; bytes per line
	asl.w	#1,d0                           ; a word index
	move.w	screen_lines_by_res(pc,d0.w),d1 ; height
	move.w	d1,screen_height.w              ; height
	move.w	screen_width_by_res(pc,d0.w),d1 ; width
	move.w	d1,screen_width.w               ; width
get_screen_mode_end:
	rts

;------------------------------------------------------------------------------
; screen_planes_by_res and the tables after it: screen geometry by resolution (shift mode
; 0 low, 1 medium, 2 high), read by get_screen_mode into $29E-$2A4.
;------------------------------------------------------------------------------
screen_planes_by_res:	; from: get_screen_mode
	dc.b	$04,$02,$01                     ; low, medium, high, bit planes -> $29e
screen_line_bytes_by_res:	; from: get_screen_mode
	dc.b	$a0,$a0,$50                     ; bytes a screen line -> $2a4
screen_lines_by_res:	; from: get_screen_mode
	dc.w	$00c8,$00c8,$0190               ; screen lines -> $2a0
screen_width_by_res:	; from: get_screen_mode
	dc.w	$0140,$0280,$0280               ; pixels a line -> $2a2

;------------------------------------------------------------------------------
; set_font: sets the font for the resolution: the cell height, bytes per text line, the last column
; and line, the font's address (8x8 or 8x16), its form width 128, characters 0-127.  Uses d0-d1.
;------------------------------------------------------------------------------
set_font:	; from: init_text_screen
	move.b	$ffff8260.w,d0                  ; shift mode, the resolution
	moveq	#3,d1                           ; the resolution bits
	and.w	d1,d0                           ; the resolution
	cmp.w	d1,d0                           ; 3?
	beq.s	set_font_end                    ; yes: unchanged
	asl.w	#1,d0                           ; a word index
	move.w	char_height_by_res(pc,d0.w),char_height.w ; the cell height
	move.w	text_row_bytes_by_res(pc,d0.w),text_row_bytes.w ; bytes per text row
	move.w	text_last_column_by_res(pc,d0.w),last_column.w ; the last column
	move.w	text_last_row_by_res(pc,d0.w),last_row.w ; the last line
	move.w	#$80,font_line_step.w           ; font form width
	move.w	#$1,font_char_step.w            ; one byte a character
	move.w	#$0,font_first_char.w           ; the first character
	move.w	#$7f,font_last_char.w           ; the last character
	asl.w	#1,d0                           ; a long index
	move.l	font_by_res(pc,d0.w),font_address.w ; the font
set_font_end:
	rts

;------------------------------------------------------------------------------
; text_last_row_by_res and the tables after it: text screen layout by resolution (shift mode
; 0 low, 1 medium, 2 high), read by set_font into $2A6-$2AE.
;------------------------------------------------------------------------------
text_last_row_by_res:	; from: set_font
	dc.w	$0018,$0018,$0018               ; 24 for each resolution, last text row (25 rows) -> $2ac
char_height_by_res:	; from: set_font
	dc.w	$0008,$0008,$0010               ; character height in lines -> $2a6
text_row_bytes_by_res:	; from: set_font
	dc.w	$0500,$0500,$0500               ; bytes a text row (height x line bytes) -> $2a8
text_last_column_by_res:	; from: set_font
	dc.w	$0027,$004f,$004f               ; last text column -> $2aa

;------------------------------------------------------------------------------
; font_by_res: the font's address by resolution, read by set_font into $2AE.
;------------------------------------------------------------------------------
font_by_res:	; from: set_font
	dc.l	font_8x8                        ; 8x8 font for low resolution -> $2ae
	dc.l	font_8x8                        ; 8x8 font for medium resolution
	dc.l	font_8x16                       ; 8x16 font for high resolution

;------------------------------------------------------------------------------
; put_char: the character in d1 out to the RS232 terminal (unless $28D bit 1 is set) and onto the screen
; at the cursor.  Control codes: 8 backspace (back, a space, back), 9 tab (5 spaces), 10 line feed,
; 13 carriage return.  Codes from the font's first ($2B6) to its last ($2B8) are drawn in the colours
; ($2BA foreground, $2BC background, swapped while inverse, $2C6 bit 4), the cursor moves on, to the next
; line at the last column when wrap ($2C6 bit 3) is on, and the screen scrolls from the line in $298 at the
; bottom.  All registers are kept.
;------------------------------------------------------------------------------
put_char:                                       ; from: read_command, read_line, print_tos_version,
                                                ;   draw_mouse_right_button, draw_mouse_left_button,
                                                ;   printer_joystick_test, 9 more
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
	bne.s	put_char_cr                     ; no
	bsr.w	line_feed                       ; the next line
	bra.w	put_char_done                   ; done
put_char_cr:
	cmp.b	#$d,d1                          ; carriage return?
	bne.s	put_char_backspace              ; no
	bsr.w	carriage_return                 ; column 0
	bra.w	put_char_done                   ; done
put_char_backspace:
	cmp.b	#$8,d1                          ; backspace?
	bne.s	put_char_tab                    ; no
	bsr.w	cursor_back                     ; back one
	move.w	#$20,d1                         ; a space over the character
	bsr.s	put_char                        ; drawn
	bsr.w	cursor_back                     ; back again
	bra.w	put_char_done                   ; done
put_char_tab:
	cmp.b	#$9,d1                          ; tab (the terminal off)?
	bne.s	put_char_glyph                  ; no: a character
	moveq	#5,d1                           ; 5 spaces
	bsr.w	print_spaces                    ; printed
	bra.w	put_char_done                   ; done
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
	clr.w	d0                              ; column 0
	cmp.w	last_row.w,d1                   ; the last row?
	bcc.w	put_char_scroll                 ; yes: scroll
	adda.w	text_row_bytes.w,a1             ; no: the next row
	addq.w	#1,d1                           ; row + 1
	bra.s	put_char_store                  ; stored
put_char_scroll:
	movem.l	d0-d1/a1,-(sp)                  ; kept
	move.w	scroll_top.w,d1                 ; the scroll region's first row
	bsr.w	scroll_up                       ; up one row, the last row cleared
	movem.l	(sp)+,d0-d1/a1                  ; back
put_char_store:
	move.l	a1,cursor_address.w             ; the cursor's new place
	move.w	d0,cursor_column.w              ; column
	move.w	d1,cursor_row.w                 ; row
	move.w	(sp)+,ccr                       ; was the cursor on?
	beq.s	put_char_done                   ; no
	bsr.w	invert_cell                     ; the cursor drawn at the new place
	bset	#$1,cursor_flags.w              ; and marked drawn
put_char_done:
	movem.l	(sp)+,d0-d7/a0-a6               ; all back
	rts

;------------------------------------------------------------------------------
; cursor_back: the cursor back one place; from column 0 to the row above, at the column in the byte at
; $2AA, which is the high byte of the last-column word (0): column 0 of that row, not its end.
; Changes d0, d1, a0, a1.
;------------------------------------------------------------------------------
cursor_back:	; from: put_char
	move.w	cursor_column.w,d0              ; the column
	move.w	cursor_row.w,d1                 ; the row
	tst.w	d0                              ; column 0?
	beq.s	cursor_back_up_line             ; yes: the row above
	subq.w	#1,d0                           ; one column back
	bra.s	cursor_back_set                 ; set there
cursor_back_up_line:
	subq.w	#1,d1                           ; the row above
	move.b	last_column.w,d0                ; the high byte of the last column: 0
cursor_back_set:
	bsr.w	set_cursor                      ; the cursor there
	rts                                     ; done

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
	bra.s	draw_glyph_fill_next            ; filled
draw_glyph_bg_clear:
	bcs.w	draw_glyph_copy_next            ; the foreground set: the glyph
	moveq	#0,d3                           ; both clear: 0
	bra.s	draw_glyph_fill_next            ; filled
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
	dbra	d5,draw_glyph_copy_line         ; every line
	bra.s	draw_glyph_plane_done           ; the plane done
draw_glyph_invert_line:
	move.b	(a4),d3                         ; the glyph's line
	not.b	d3                              ; inverted
	move.b	d3,(a5)                         ; onto the screen
	adda.w	a3,a5                           ; the next screen line
	adda.w	a2,a4                           ; the next font line
draw_glyph_invert_next:
	dbra	d5,draw_glyph_invert_line       ; every line
draw_glyph_plane_done:
	lea	2(a1),a1                        ; the next plane's word
draw_glyph_next_plane:
	dbra	d6,draw_glyph_plane             ; every plane
	rts                                     ; done

;------------------------------------------------------------------------------
; clear_text_block: a block of character cells filled with the background colour ($2BC).  d1 the top row
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
	rts                                     ; done
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
	rts                                     ; done
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
	rts                                     ; done

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
	rts                                     ; done

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
	dbra	d5,invert_cell_line             ; every line
	lea	2(a1),a1                        ; the next plane's word
invert_cell_next_plane:
	dbra	d6,invert_cell_plane            ; every plane
	rts                                     ; done

;------------------------------------------------------------------------------
; next_column: column d0 and the screen place a1 moved on one character.  At the last column nothing
; moves: d3 = 1 (Z clear, a new line needed) when wrap ($2C6 bit 3) is on, else 0.  Otherwise d3 = 0, Z set.
;------------------------------------------------------------------------------
next_column:	; from: put_char
	cmp.w	last_column.w,d0                ; the last column?
	bne.s	next_column_advance             ; no
	btst	#$3,cursor_flags.w              ; wrap on?
	bne.s	next_column_wrap                ; yes
	clr.w	d3                              ; no: stays at the last column
	rts                                     ; Z set
next_column_wrap:
	move.b	#$1,d3                          ; a new line
	rts                                     ; Z clear
next_column_advance:
	addq.w	#1,d0                           ; the next column
	btst	#$0,d0                          ; odd: the same word group
	beq.s	next_column_word                ; no
	lea	1(a1),a1                        ; the right-hand byte
	clr.w	d3                              ; no new line
	rts                                     ; Z set
next_column_word:
	move.w	screen_planes.w,d3              ; planes
	asl.w	#1,d3                           ; * 2
	subq.w	#1,d3                           ; - 1
	adda.w	d3,a1                           ; the next word group's left-hand byte
	clr.w	d3                              ; no new line
	rts                                     ; Z set

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
	dbra	d3,scroll_up_copy               ; every long
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
	dbra	d3,scroll_down_copy             ; every long
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
	move.w	cursor_column.w,d1              ; the column, now even
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
	bra.s	clear_to_line_end_restore       ; wrap back

;------------------------------------------------------------------------------
; inverse_on: text from now on in inverse video ($2C6 bit 4).
;------------------------------------------------------------------------------
inverse_on:	; from: ram_test_star_vbl, print_menu_string
	bset	#$4,cursor_flags.w              ; inverse on
	rts

;------------------------------------------------------------------------------
; inverse_off: text from now on normal ($2C6 bit 4 cleared).
;------------------------------------------------------------------------------
inverse_off:	; from: ram_test_star_vbl, print_menu_string
	bclr	#$4,cursor_flags.w              ; inverse off
	rts

;------------------------------------------------------------------------------
; cursor_show: one cursor_hide undone ($2C8 counts them); at 0 the cursor is drawn.  In blink mode
; ($2C6 bit 0) it is drawn and marked in bit 1, otherwise marked on in bit 2.  Changes d0-d6, a0-a4.
;------------------------------------------------------------------------------
cursor_show:	; from: clear_to_line_end, line_feed
	subq.w	#1,cursor_hide_count.w          ; one hide undone
	bne.s	cursor_hide_done                ; still hidden
	lea	cursor_flags.w,a0               ; the cursor flags
	btst	#$0,(a0)                        ; blink mode?
	bne.s	cursor_show_blink               ; yes
	bset	#$2,(a0)                        ; on

;------------------------------------------------------------------------------
; cursor_draw: the cell at the cursor ($2BE column, $2C0 row) inverted: the cursor drawn or taken off.
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
	rts                                     ; done

;------------------------------------------------------------------------------
; cursor_hide: the cursor taken off the screen, and one more hide counted in $2C8 (cursor_show undoes it).
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
	rts                                     ; the cursor was not drawn: nothing to take off

;------------------------------------------------------------------------------
; save_cursor: the cursor's column and row kept in $2CA/$2CC for restore_cursor ($2C6 bit 5 marks them).
; Changes a0.
;------------------------------------------------------------------------------
save_cursor:                                    ; from: clear_status_line, print_cycle, print_channel_name,
                                                ;   floppy_quick_test, print_floppy_action, clear_to_line_end, 1 more
	bset	#$5,cursor_flags.w              ; a place kept
	lea	saved_cursor_column.w,a0        ; the place
	move.w	cursor_column.w,(a0)+           ; the column
	move.w	cursor_row.w,(a0)               ; the row
	rts                                     ; done

;------------------------------------------------------------------------------
; restore_cursor: the cursor back to the place save_cursor kept, or home if none.  Changes d0, d1, a0, a1.
;------------------------------------------------------------------------------
restore_cursor:                                 ; from: clear_status_line, print_cycle, print_channel_name,
                                                ;   floppy_quick_test, print_floppy_action, clear_to_line_end, 1 more
	bclr	#$5,cursor_flags.w              ; a place kept?
	beq.w	cursor_home                     ; no: home
	lea	saved_cursor_column.w,a0        ; the place
	move.w	(a0)+,d0                        ; the column
	move.w	(a0),d1                         ; the row
	bra.w	set_cursor                      ; the cursor there

;------------------------------------------------------------------------------
; wrap_on: (not called) wrap to the next line at the last column ($2C6 bit 3).
;------------------------------------------------------------------------------
wrap_on:
	bset	#$3,cursor_flags.w              ; wrap on
	rts

;------------------------------------------------------------------------------
; wrap_off: (not called) no wrap: the last column is written over.
;------------------------------------------------------------------------------
wrap_off:
	bclr	#$3,cursor_flags.w              ; wrap off
	rts

;------------------------------------------------------------------------------
; set_cursor: the cursor to column d0, row d1 ($2BE, $2C0, and its screen place $2C2); if it is drawn it
; is taken off at the old place and drawn at the new.  Changes d3, d5, a0-a2, a4.
;------------------------------------------------------------------------------
set_cursor:                                     ; from: ask_stopped, print_cycle, cmd_rs232_rate, keyboard_test,
                                                ;   draw_mouse_right_button, draw_mouse_left_button, 17 more
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
	rts                                     ; done
set_cursor_mark_on:
	bset	#$2,(a0)                        ; on again
set_cursor_address:
	bsr.w	cell_address                    ; the new place
	move.l	a1,cursor_address.w             ; kept
	rts                                     ; done

;------------------------------------------------------------------------------
; carriage_return: the cursor to column 0 of its row.
;------------------------------------------------------------------------------
carriage_return:	; from: put_char
	move.w	cursor_row.w,d1                 ; the row
	clr.w	d0                              ; column 0
	bra.s	set_cursor                      ; the cursor there

;------------------------------------------------------------------------------
; line_feed: the cursor down a row in its column; on the last row the screen scrolls up from the row in
; $298 instead.
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
; Uses $770-$84E (the variables), $216 (the cycle count, as a word).
;------------------------------------------------------------------------------
hd_test:	; from: read_command
	lea	hd_exerciser_title,a5           ; "Hard Disk DMA Exerciser", the warning, "Hit <Esc> key to stop
                                                ;   program."
	bsr.w	print_string                    ; printed
	move.l	#$7ce,hd_bad_sectors_end.w      ; the known bad sector list emptied
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
	clr.w	hd_counter_b.w                  ; counters (not used further here)
	clr.w	hd_counter_c.w                  ; counters (not used further here)
	clr.w	hd_counter_d.w                  ; counters (not used further here)
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
	move.b	d0,(a0)+                        ; cleared
	dbra	d1,hd_test_clear_byte           ; every byte
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
	move.w	hd_sectors_left.w,d1            ; the sectors in the command
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
	beq.s	hd_test_compare_key             ; none
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
	rts                                     ; done

;------------------------------------------------------------------------------
; hd_park_heads: after a pause, a STOP UNIT command ($1B) to unit 0 parks the heads: "HEADS ARE PARKED", or
; "Error -- Heads not parked!" and red.  Then P parks again, Q quits, RETURN restarts the cartridge.
;------------------------------------------------------------------------------
hd_park_heads:	; from: hd_test, hd_park_fail_cycle
	moveq	#50,d1                          ; 51 times
hd_park_delay_outer:
	move.l	#$186a0,d0                      ; 100000
hd_park_delay:
	dbra	d0,hd_park_delay                ; the inner pause
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
	rts                                     ; back to the menu

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
	rts                                     ; done

;------------------------------------------------------------------------------
; hd_get_dma_address: the DMA address register read into $770.
;------------------------------------------------------------------------------
hd_get_dma_address:	; from: hd_test
	clr.l	dma_address_read.w              ; the high byte clear
	move.b	$ffff8609.w,dma_address_read+1.w ; DMA base high, high
	move.b	$ffff860b.w,dma_address_read+2.w ; DMA base mid, mid
	move.b	$ffff860d.w,dma_address_read+3.w ; DMA base low, low
	rts                                     ; done

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
	bgt.s	hd_fill_long                    ; up to it
	add.w	#$1,d2                          ; the next sector number
	cmpa.l	#$51010,a1                      ; the buffer's end?
	blt.s	hd_fill_sector                  ; no
	rts

;------------------------------------------------------------------------------
; hd_test_patterns: the hard disk exerciser's data patterns, one long for each cycle (cycle
; number ($216) AND 7).  hd_fill_write_buffer fills each 512-byte sector with the cycle, the sector
; number and then this pattern.
;------------------------------------------------------------------------------
hd_test_patterns:	; from: hd_fill_write_buffer
	dc.l	$ff00aa55,$99ee66dd,$a56bffee,$a5a5a5a5 ; cycles 0-3
	dc.l	$11223344,$55667788,$0f0f0f0f,$fedcba98 ; cycles 4-7

;------------------------------------------------------------------------------
; hd_known_bad_sector: is the failed sector ($7B8 - 1) in the known bad sector list ($7CE up to $84E)?
; Z set if it is.  At the list's end the beq jumps to $1A62 (the RAM test's pattern routine) instead of the
; code at $779C that adds the sector, so the list stays empty: that routine writes the patterns d0/d2 from
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
	rts                                     ; done

;------------------------------------------------------------------------------
; acsi_command: a 6-byte ACSI command with no data sent from a0 to unit $7C2; d0 = the status byte, or
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
; acsi_write_sectors: a WRITE ($0A) of $7C0 sectors from sector $7BC on unit $7C2, DMA from $7C4.  d0 = the
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
	nop                                     ; (a short wait)
	move.w	#$190,$ffff8606.w               ; DMA mode / status, then write
	nop                                     ; (a short wait)
	move.w	acsi_count.w,$ffff8604.w        ; DMA sector count / FDC access, the sector count
	nop                                     ; (a short wait)
	move.w	#$18a,$ffff8606.w               ; DMA mode / status, write, A1 low
	nop                                     ; (a short wait)
	move.l	#$100,$ffff8604.w               ; DMA sector count / FDC access, the last byte (0); the DMA starts
	move.w	#$18a,d0                        ; write mode
	bsr.w	acsi_status                     ; the status at the end
	beq.w	acsi_write_done                 ; 0: good
	bsr.w	acsi_command_error              ; else "Command error" and the sense data
acsi_write_done:
	bra.w	acsi_exit                       ; out

;------------------------------------------------------------------------------
; acsi_read_sectors: a READ ($08) of $7C0 sectors from sector $7BC on unit $7C2, DMA to $7C4.  d0 = the
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
	nop                                     ; (a short wait)
	move.w	#$90,$ffff8606.w                ; DMA mode / status, then read
	nop                                     ; (a short wait)
	move.w	acsi_count.w,$ffff8604.w        ; DMA sector count / FDC access, the sector count
	nop                                     ; (a short wait)
	move.w	#$8a,$ffff8606.w                ; DMA mode / status, read, A1 low
	nop                                     ; (a short wait)
	move.l	#$0,$ffff8604.w                 ; DMA sector count / FDC access, the last byte (0); the DMA starts
	move.w	#$8a,d0                         ; read mode
	bsr.w	acsi_status                     ; the status at the end
	beq.w	acsi_read_done                  ; 0: good
	bsr.w	acsi_command_error              ; else "Command error" and the sense data
acsi_read_done:
	bra.w	acsi_exit                       ; out
acsi_fail:	; from: acsi_command, acsi_write_sectors
	moveq	#-1,d0                          ; -1: no answer
acsi_exit:	; from: acsi_command, acsi_write_sectors
	move.w	#$2400,sr                       ; interrupts back on
	tst.w	$ffff8604.w                     ; DMA sector count / FDC access, (a read of the DMA register)
	rts                                     ; done

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
	move.w	(sp)+,d0                        ; the status back
	rts                                     ; done

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
	nop                                     ; (a short wait)
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, the status
	and.w	#$ff,d0                         ; its byte
acsi_status_done:
	rts                                     ; done

;------------------------------------------------------------------------------
; acsi_request_sense: REQUEST SENSE ($03) on unit $7C2 with one sector's DMA to $59820, four times with
; 2 ticks between; d2 = $FFFF when all four worked.  Changes d0-d2, a5.
;------------------------------------------------------------------------------
acsi_request_sense:	; from: acsi_command_error
	move.l	#$59820,acsi_dma_address.w      ; the sense buffer
	bsr.w	acsi_set_dma_address            ; the DMA address
	move.w	#$190,$ffff8606.w               ; DMA mode / status, the DMA FIFO cleared and set to read: write
	nop                                     ; (a short wait)
	move.w	#$90,$ffff8606.w                ; DMA mode / status, then read
	nop                                     ; (a short wait)
	move.w	#$1,$ffff8604.w                 ; DMA sector count / FDC access, one sector
	nop                                     ; (a short wait)
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
	nop                                     ; (a short wait)
	move.l	#$0,$ffff8604.w                 ; DMA sector count / FDC access, the last byte (0)
	move.w	#$8a,d0                         ; read mode
	bsr.w	acsi_status                     ; the status at the end
	bmi.w	acsi_request_sense_done         ; timed out
	move.l	rom_sum_high.w,d1               ; the long at $4BA (TOS's 200 Hz count, which nothing here counts)
	addq.l	#2,d1                           ; + 2
acsi_request_sense_wait:
	cmp.l	rom_sum_high.w,d1               ; 2 ticks (never: $4BA does not change, so this loops for ever)
	bcc.s	acsi_request_sense_wait         ; until then
	dbra	d2,acsi_request_sense_loop      ; each round
acsi_request_sense_done:
	rts                                     ; done

;------------------------------------------------------------------------------
; acsi_set_dma_address: the DMA address register set to $7C4 (low byte first).
;------------------------------------------------------------------------------
acsi_set_dma_address:	; from: acsi_write_sectors, acsi_read_sectors, acsi_request_sense
	move.b	acsi_dma_address+3.w,$ffff860d.w ; DMA base low, low
	move.b	acsi_dma_address+2.w,$ffff860b.w ; DMA base mid, mid
	move.b	acsi_dma_address+1.w,$ffff8609.w ; DMA base high, high
	rts                                     ; done

;------------------------------------------------------------------------------
; acsi_send_address: command bytes 2-5 sent: the unit (bits 7-5, from the low byte of $7C2) with the
; sector's high byte, its mid and low bytes ($7BD-$7BF), and the count ($7C0).  d0 -1 (N set) when the
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

;------------------------------------------------------------------------------
; (this label and those at $7A42, $7AF4 and $7B20 come only from the 8 longs at $DB0A in the texts, the
; Mega STE cartridge's SCC vector table left in place: nothing reads it, and its other entries point into
; the middle of instructions at $7AA4, $7AB0 and $7AEA)
;------------------------------------------------------------------------------
acsi_send_address_wait_low:
	bsr.w	acsi_wait                       ; ready?
	bmi.w	acsi_send_address_done          ; no
	move.b	acsi_sector+3.w,d0              ; the sector's low byte
acsi_send_address_low_byte:
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
acsi_send_address_done:	; from: acsi_send_address
	rts                                     ; done

;------------------------------------------------------------------------------
; acsi_wait_long: as acsi_wait with the long timeout ($6DDD0 rounds) for the end of a command; a timeout
; prints "Operation timed-out".
;------------------------------------------------------------------------------
acsi_wait_long:	; from: acsi_command, acsi_status
	move.l	#$6ddd0,acsi_timeout.w          ; the long timeout
	move.w	d1,-(sp)                        ; kept
	move.w	#$1,d1                          ; "Operation timed-out" if it runs out
	bra.w	acsi_wait_loop                  ; to the wait

;------------------------------------------------------------------------------
; acsi_wait: waits for the unit's interrupt (GPIP 5 low): d0 = 0 (Z set), or -1 (N set) after $3A98 rounds
; with "Controller not responding" printed.  d1 kept.
;------------------------------------------------------------------------------
acsi_wait:	; from: acsi_command, acsi_request_sense, acsi_send_address, acsi_send_address_wait_low
	move.l	#$3a98,acsi_timeout.w           ; the short timeout
	move.w	d1,-(sp)                        ; kept
	move.w	#$0,d1                          ; "Controller not responding" if it runs out
acsi_wait_loop:	; from: acsi_wait_long
	subq.l	#1,acsi_timeout.w               ; one round
	bmi.w	acsi_wait_timeout               ; run out
	move.b	$fffffa01.w,d0                  ; MFP GPIP, the MFP's inputs
	and.b	#$20,d0                         ; the FDC/ACSI interrupt (low when the unit is ready)
	bne.s	acsi_wait_loop                  ; not yet
	move.w	(sp)+,d1                        ; back
	moveq	#0,d0                           ; 0: ready
	rts                                     ; done
acsi_wait_timeout:
	lea	msg_controller_not_responding,a5 ; "Controller not responding"
	tst.w	d1                              ; the long wait?
	beq.w	acsi_wait_print                 ; no
acsi_wait_timeout_long:
	lea	msg_operation_timed_out,a5      ; "Operation timed-out"
acsi_wait_print:
	bsr.w	print_string                    ; printed
	move.w	(sp)+,d1                        ; back
	moveq	#-1,d0                          ; -1
	rts                                     ; done

;------------------------------------------------------------------------------
; hd_pause: meant to wait 100 ticks of the 200 Hz count at $4BA (TOS's _hz_200).  Nothing in the
; cartridge counts $4BA (the ROM test stores a checksum word there), so the count never matches and this
; loops for ever; only addi.w is used on the low word as well.  Changes d7.
;------------------------------------------------------------------------------
hd_pause:	; from: hd_test
	move.l	rom_sum_high.w,d7               ; the 200 Hz count
	addi.w	#$64,d7                         ; + 100
hd_pause_loop:
	cmp.l	rom_sum_high.w,d7               ; 100 ticks gone? (never: $4BA does not change)
	bne.s	hd_pause_loop                   ; not yet
	rts                                     ; done

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
	rts                                     ; done

;------------------------------------------------------------------------------
; hd_status_line: the status line at the top: the text at a5, the cylinder ($7B2) in decimal,
; "<<  Hit <Esc> key to stop.  >>" and the cycle; the cursor goes back.
;------------------------------------------------------------------------------
hd_status_line:	; from: hd_test
	bsr.w	save_cursor                     ; the cursor's place kept
	moveq	#0,d0                           ; column 0
	moveq	#0,d1                           ; row 0
	bsr.w	set_cursor                      ; the cursor there
hd_status_line_text:
	bsr.w	print_string                    ; the text
	move.w	hd_cylinder.w,d0                ; the cylinder
	bsr.w	word_to_bcd                     ; in decimal digits
	bsr.w	print_hex_word                  ; printed
	lea	msg_hit_esc_to_stop,a5          ; "   <<  Hit <Esc> key to stop.  >>   "
	bsr.w	print_string                    ; printed
	bsr.s	hd_print_cycle                  ; " Cycle: " and the cycle
	bsr.w	restore_cursor                  ; the cursor back
	rts                                     ; done

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
	beq.w	hd_stopped_clear                ; yes
	cmp.b	#$51,d0                         ; Q?
	beq.w	hd_stopped_clear                ; yes
	cmp.b	#$50,d0                         ; P?
	beq.w	hd_stopped_clear                ; yes
	cmp.b	#$53,d0                         ; S?
	bne.s	hd_stopped_key                  ; none of them: again
hd_stopped_clear:
	move.b	d0,-(sp)                        ; the key kept
	move.w	cursor_row.w,d1                 ; this row
	clr.w	d0                              ; column 0
	bsr.w	set_cursor                      ; the cursor there
	bsr.w	clear_to_line_end               ; the line cleared
	move.b	(sp)+,d0                        ; the key
	rts                                     ; done
	dcb.b	1194,0                          ; unused: the end of the code area, zeros to $7FFF

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
msg_ram_sizing_error:
	dc.b	13,10,'I5 Ram sizing error',13,10,0 ; no reference
msg_checking_exceptions:	; from: check_bus_error
	dc.b	13,10,'I6 Checking exception handling...',13,10,0
msg_bus_error_not_detected:	; from: check_bus_error
	dc.b	13,10,'I7 Bus error not detected',13,10,0

;------------------------------------------------------------------------------
; test_letters_all: the 12 menu letters that run a test, in the order of test_routines (no end
; byte: the menu code counts 12). test_letters_q and test_letters_z: the letters the Q and Z
; entries of test_routines run in turn (9 and 5; the count is put in $277).
;------------------------------------------------------------------------------
test_letters_all:	; from: menu_start, run_q_tests
	dc.b	'ROGMSTDPFYQZ'                  ; R O G M S T D P F Y Q Z
test_letters_q:	; from: run_q_tests
	dc.b	'ROMSTDPFY'                     ; Q: RAM, ROM, MIDI, serial, timing, DMA, printer, floppy, long BLiT
test_letters_z:	; from: run_q_tests
	dc.b	$52,$4f,$54,$46,$47             ; "ROTFG", Z: RAM, ROM, timing, floppy, short BLiT

;------------------------------------------------------------------------------
; test_routines: the test for each letter of test_letters_all (the menu and the Q/Z sequence
; take the letter's index times 4).
;------------------------------------------------------------------------------
test_routines:	; from: menu_start, run_q_tests
	dc.l	ram_test                        ; R RAM
	dc.l	rom_test                        ; O O.S. ROM
	dc.l	blit_short_test                 ; G short BLiT
	dc.l	midi_test                       ; M MIDI
	dc.l	rs232_test                      ; S serial (RS232 loopback)
	dc.l	timing_test                     ; T timing
	dc.l	dma_port_test                   ; D DMA port
	dc.l	printer_joystick_test           ; P printer/joystick ports
	dc.l	floppy_menu                     ; F floppy
	dc.l	blit_long_test                  ; Y long BLiT
	dc.l	run_q_tests                     ; Q all unattended tests
	dc.l	run_z_tests                     ; Z unattended internal tests

;------------------------------------------------------------------------------
; ram_size_codes: bits 16-23 of the RAM size ($204) with bit 16 cleared, for 256K, 512K, 1M, 2M
; and 4M; the index found picks the text from ram_size_texts (the menu title and the RAM test).
;------------------------------------------------------------------------------
ram_size_codes:	; from: menu_start, ram_test
	dc.b	$04,$08,$10,$20,$40             ; 256K, 512K, 1M, 2M, 4M

;------------------------------------------------------------------------------
; msg_title: the menu title, cartridge name and revision, then (after tabs) $06, the font's
; copyright sign, with "1991, Atari Corp."
;------------------------------------------------------------------------------
msg_title:	; from: menu_start
	dc.b	13,10,9,9,'STe Field Service Diagnostic Rev. 1.9',13,10,9,9,9,9
	dc.b	$06
	dc.b	' 1991, Atari Corp.',13,10,0
msg_date:	; from: read_command, leftover_mste_scc_vectors
	dc.b	13,10,9,'MAY 24, 1991',13,10,0  ; the hidden date screen (a menu key); a "*" key then shows msg_author
msg_author:	; from: read_command
	dc.b	9,' by TF',13,10,0
msg_increase_decrease:	; from: cmd_rs232_rate
	dc.b	'Increase '                     ; $01 and $02 are the up and down arrows in the font
	dc.b	$01
	dc.b	', Decrease '
	dc.b	$02,$0d,$0a,$00
msg_50_hz:	; from: menu_start
	dc.b	'50 Hz  ',0
msg_60_hz:	; from: menu_start
	dc.b	'60 Hz  ',0
	dc.b	$00                             ; pad

;------------------------------------------------------------------------------
; ram_size_texts: pointers to the RAM size texts, in the order of ram_size_codes.
;------------------------------------------------------------------------------
ram_size_texts:	; from: menu_start, ram_test
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
msg_keyboard_rev:	; from: menu_start
	dc.b	' Keyboard rev. ',0             ; printed with the keyboard revision when the keyboard answered

;------------------------------------------------------------------------------
; menu_text: the main menu. Printed by print_menu_string: each $05 switches inverse video on or
; off, so each test letter is shown inverse.
;------------------------------------------------------------------------------
menu_text:	; from: menu_start
	dc.b	$09,$05,$55,$05,$4e,$05,$41,$05,$54,$05,$54,$05,$45,$05,$4e,$05
	dc.b	$44,$05,$45,$05,$44,$0d,$0a,$09,$05
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
	dc.b	'F Floppy Disk',9,9
	dc.b	$05
	dc.b	'P Printer/Mouse/Joy & Game Ports',13,10,9
	dc.b	$05
	dc.b	'G Short BLiT ',9,9
	dc.b	$05
	dc.b	'Y Long BLiT    ',13,10,10,9
	dc.b	$05
	dc.b	'Q Run all unattended tests (R,O,M,S,T,D,F,P,Y)',13,10,9
	dc.b	$05
	dc.b	'Z Run unattended internal tests (R,O,T,F,G)',13,10,10,9
	dc.b	$05,$4f,$05,$50,$05,$45,$05,$52,$05,$41,$05,$54,$05,$4f,$05,$52
	dc.b	$0d,$0a,$09,$05
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
	dc.b	'? Help',13,10,10,9,'Enter letter(s), and RETURN: ',0
msg_pass:	; from: run_q_tests, ram_test, rom_test, keyboard_test, midi_test, rs232_test, 8 more
	dc.b	'Pass',0
msg_fail_at_cycle:	; from: ram_test, ram_test_no_safe_block, rom_test, keyboard_test, midi_test, rs232_test, 6 more
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
msg_keyboard_buffer_full:	; from: read_command, read_line
	dc.b	'Keyboard buffer full',13,10,0

;------------------------------------------------------------------------------
; help_text: the first help page (the ? key): running unattended tests.
;------------------------------------------------------------------------------
help_text:	; from: read_command
	dc.b	'RUNNING UNATTENDED TESTS',13,10
	dc.b	'   Select a single test or any combination of tests by typing th'
	dc.b	'e corresponding',13,10
	dc.b	'letter or letters, then typing the RETURN key. To run repeated c'
	dc.b	'ycles of the',13,10
	dc.b	'test or (tests), follow the last letter with the number of cycle'
	dc.b	's to run.',13,10
	dc.b	'For example, "RSM25", will run RAM, Serial, and MIDI tests 25 ti'
	dc.b	'mes. If 0 is',13,10,'entered, testing will be continuous.',13,10,10
	dc.b	'   Use the ESC key to quit the test cycle. In some cases there w'
	dc.b	'ill be a delay',13,10,'before control returns to the keyboard.',13,10
	dc.b	10,'   An RS232 terminal may be used for input and display. The Seri'
	dc.b	'al RS232 test',13,10
	dc.b	'will not pass if a terminal is installed in place of the loopbac'
	dc.b	'k plug.',13,10
	dc.b	'Normally a color monitor is used for all tests accept high resol'
	dc.b	'ution.',13,10
	dc.b	'If an error occurs, an error message will be displayed and the s'
	dc.b	'creen will',13,10
	dc.b	'turn red. When the test completes, Pass or Fail will be displaye'
	dc.b	'd, and the ',13,10,'screen will turn green or red.',13,10
	dc.b	'If multiple tests are run and an error occurs on any test, the s'
	dc.b	'creen will',13,10
	dc.b	'remain red, although successive tests pass. Once the test has ha'
	dc.b	'lted, the ',13,10,'SPACE BAR is used to return to the menu.',13,10,10
	dc.b	'   The DMA and Printer/joystick/game port tests require that the'
	dc.b	' port test ',13,10,'fixtures be connected.',13,10,10,0

;------------------------------------------------------------------------------
; help_notes_text: the second help page: notes on the ROM, RAM and BLiT tests and the operator
; tests.
;------------------------------------------------------------------------------
help_notes_text:	; from: read_command
	dc.b	'   The O.S. ROM test calculates a checksum/CRC of the ROMs and c'
	dc.b	'ompares ',13,10,'the resultant CRC with the value found in the ROMs.'
	dc.b	13,10,10
	dc.b	'   If the RAM test fails, the error code, address, data written,'
	dc.b	' data read,',13,10,'and bad bits (0-15) are displayed.',13,10,10
	dc.b	'   The short Bliter test does not display any graphics on the sc'
	dc.b	'reen.',13,10
	dc.b	'The long Bliter test while appearing not to finish the rectangle'
	dc.b	' is ok.',13,10,10,'OPERATOR REQUIRED TESTS',13,10
	dc.b	'   The Audio,Color,Keyboard,High resolution and Hard disk tests '
	dc.b	'have few error',13,10
	dc.b	'messages. The operator must determine if the output results are '
	dc.b	'acceptable.',13,10,10
	dc.b	'   The Gen/lock test is run twice. Toggling the switch on the ge'
	dc.b	'n/lock fixtureshould switch between the normal menu and no menu.'
	dc.b	' With no menu a "sweeping"cycle should be heard. Reset the compu'
	dc.b	'ter between each change of the gen/lockswitch.  NOTE - RUN THIS '
	dc.b	'TEST ONLY WITH A COLOR MONITOR',0

;------------------------------------------------------------------------------
; exception_vectors_table: the handlers the reset code copies to vectors $8-$2F.
;------------------------------------------------------------------------------
exception_vectors_table:	; from: low_ram_test
	dc.l	bus_error_handler               ; $08 bus error
	dc.l	address_error_handler           ; $0C address error
	dc.l	illegal_handler                 ; $10 illegal instruction
	dc.l	exception_error_handler         ; $14 zero divide
	dc.l	exception_error_handler         ; $18 CHK
	dc.l	exception_error_handler         ; $1C TRAPV
	dc.l	exception_error_handler         ; $20 privilege violation
	dc.l	exception_error_handler         ; $24 trace
	dc.l	line_a_handler                  ; $28 line A
	dc.l	line_f_handler                  ; $2C line F

;------------------------------------------------------------------------------
; autovectors_table: the handlers copied to vectors $60-$7F (spurious interrupt and levels 1-7).
;------------------------------------------------------------------------------
autovectors_table:	; from: low_ram_test
	dc.l	spurious_handler                ; $60 spurious interrupt
	dc.l	autovector_handler              ; $64 level 1
	dc.l	hbl_handler                     ; $68 level 2, HBL
	dc.l	autovector_handler              ; $6C level 3
	dc.l	vbl_handler                     ; $70 level 4, VBL
	dc.l	autovector_handler              ; $74 level 5
	dc.l	autovector_handler              ; $78 level 6
	dc.l	autovector_handler              ; $7C level 7, NMI

;------------------------------------------------------------------------------
; mfp_vectors_table: the handlers copied to the 16 MFP vectors $100-$13F, MFP interrupt 0 first.
;------------------------------------------------------------------------------
mfp_vectors_table:	; from: low_ram_test
	dc.l	centronics_busy_handler         ; 0 GPIP 0, Centronics busy
	dc.l	dcd_handler                     ; 1 GPIP 1, RS232 DCD
	dc.l	cts_handler                     ; 2 GPIP 2, RS232 CTS
	dc.l	blitter_done_handler            ; 3 GPIP 3, BLiTTER done
	dc.l	timer_d_handler                 ; 4 Timer D
	dc.l	timer_c_handler                 ; 5 Timer C
	dc.l	acia_interrupt                  ; 6 GPIP 4, keyboard and MIDI ACIAs
	dc.l	fdc_interrupt                   ; 7 GPIP 5, FDC/hard disk
	dc.l	timer_b_handler                 ; 8 Timer B
	dc.l	rs232_transmit_error_handler    ; 9 RS232 transmit error
	dc.l	rs232_transmit_handler          ; 10 RS232 transmit buffer empty
	dc.l	rs232_receive_error_handler     ; 11 RS232 receive error
	dc.l	rs232_receive_handler           ; 12 RS232 receive buffer full
	dc.l	timer_a_handler                 ; 13 Timer A
	dc.l	ring_indicator_handler          ; 14 GPIP 6, RS232 ring indicator
	dc.l	monitor_change_handler          ; 15 GPIP 7, monochrome monitor detect

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
; RAM test texts (R codes). print_ram_error prints the R0-R3 texts for error codes 0-3 and the
; R4 text for any other code.
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
msg_written_data:	; from: print_ram_error
	dc.b	' W:',0
msg_read_data:	; from: print_ram_error
	dc.b	' R:',0
msg_bad_bits:	; from: print_bad_bits
	dc.b	'  bad bits: ',0
msg_ram_test_star:	; from: ram_test_star_vbl
	dc.b	$2a,$00,$00                     ; "*", blinked on the status line in the RAM test, and a pad

;------------------------------------------------------------------------------
; crc16_table: the CRC-16 (CCITT polynomial $1021) table, 256 words, for rom_crc: the CRC of each
; ROM chip (every other byte), index = CRC high byte XOR the data byte.
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
; ROM test expected values: one word for each country code (os_conf bits 1-4, from $E0001C),
; looked up with the country code times 2. The high ROM holds the even bytes, the low ROM the odd
; bytes. rom_test uses the four tos106_ tables for any TOS other than 1.62 (16 entries, 9 filled:
; USA to Swiss German) and the tos162_ tables for TOS 1.62 (9 entries each). A checksum is the sum
; of the chip's bytes, the CRC that of rom_crc.
;------------------------------------------------------------------------------
tos106_high_rom_checksums:	; from: rom_test
	dc.w	$2630,$e9e5,$0b23,$27fb,$2a76,$6878,$9afc,$059b
	dc.w	$d76f,$0000,$0000,$0000,$0000,$0000,$0000,$0000
tos106_low_rom_checksums:	; from: rom_test
	dc.w	$2db0,$fb24,$6ff8,$2dba,$7697,$d984,$0e5c,$58fe
	dc.w	$1479,$0000,$0000,$0000,$0000,$0000,$0000,$0000
tos106_high_rom_crcs:	; from: rom_test
	dc.w	$724e,$dcfe,$7383,$6f14,$5ffb,$1862,$8877,$fe94
	dc.w	$fe94,$0000,$0000,$0000,$0000,$0000,$0000,$0000
tos106_low_rom_crcs:	; from: rom_test
	dc.w	$9e0e,$02de,$986d,$288e,$a95f,$ebed,$3b69,$531a
	dc.w	$cc67,$0000,$0000,$0000,$0000,$0000,$0000,$0000
tos162_high_rom_checksums:	; from: rom_test
	dc.w	$e082,$9f32,$c0c4,$e24d,$dfd9,$1df8,$509d,$baee
	dc.w	$8cdc
tos162_low_rom_checksums:	; from: rom_test
	dc.w	$e421,$b49e,$d536,$e42b,$19b8,$5fe2,$739a,$fc20
	dc.w	$b7a0
tos162_high_rom_crcs:	; from: rom_test
	dc.w	$7521,$ba1f,$9a6d,$614e,$df51,$8f5e,$27f7,$7e3e
	dc.w	$7e3e
tos162_low_rom_crcs:	; from: rom_test
	dc.w	$6cad,$821c,$d6d4,$87ec,$2c5c,$1ef3,$9875,$c3cb
	dc.w	$5cb6

;------------------------------------------------------------------------------
; country_names: the name printed for each country code (os_conf bits 1-4), USA (0) first.
;------------------------------------------------------------------------------
country_names:	; from: print_tos_version
	dc.l	msg_country_usa
	dc.l	msg_country_german
	dc.l	msg_country_french
	dc.l	msg_country_uk
	dc.l	msg_country_spanish
	dc.l	msg_country_italian
	dc.l	msg_country_swedish
	dc.l	msg_country_swiss_french
	dc.l	msg_country_swiss_german
	dc.l	msg_country_turkish
	dc.l	msg_country_finnish
	dc.l	msg_country_norwegian
	dc.l	msg_country_danish
	dc.l	msg_country_arabic
	dc.l	msg_country_dutch
	dc.l	msg_country_unassigned

;------------------------------------------------------------------------------
; O.S. ROM test texts.
;------------------------------------------------------------------------------
msg_rom_checksum_test:	; from: rom_test
	dc.b	'ROM checksum test',13,10,0
msg_version:	; from: print_tos_version
	dc.b	'Version ',0
msg_high_rom_checksum:	; from: rom_test
	dc.b	'High ROM checksum, crc',13,10,0 ; the heading of the high ROM line
msg_low_rom_checksum:	; from: rom_test
	dc.b	'Low ROM checksum, crc',13,10,0 ; the heading of the low ROM line
msg_rom_value_ok:	; from: check_rom_sums
	dc.b	'            ',0                ; printed after a checksum or CRC that matches
msg_rom_cs_error:	; from: check_rom_sums
	dc.b	'  cs error  ',0
msg_rom_crc_error:	; from: check_rom_sums
	dc.b	'  crc error ',0
	dc.b	'  no checksum listed',13,10,0  ; no reference
	dc.b	9,'checksum   crc',13,10,0      ; no reference
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
msg_new_version_number:	; from: print_tos_version
	dc.b	'New version number',13,10,0    ; printed after the version when TOS is newer than 1.62
msg_no_colour_monochrome:	; from: colour_test
	dc.b	'No color--Monochrome monitor',0 ; the colour test in high resolution
	dc.b	$00                             ; pad

;------------------------------------------------------------------------------
; key_click_psg_settings: sound chip register/value pairs for the keyboard test's key click: tone
; A period $3B, noise period 0, mixer tone A only, A volume from the envelope, envelope shape 3,
; envelope period $180. keyboard_key_click writes pairs until it reaches key_positions.
;------------------------------------------------------------------------------
key_click_psg_settings:	; from: keyboard_key_click
	dc.b	$00,$3b,$06,$00,$07,$fe,$08,$10,$0d,$03,$0b,$80,$0c,$01

;------------------------------------------------------------------------------
; key_positions: where draw_key prints each key, one word for each scan code 0-$72: the text column
; in the high byte, the row in the low byte; 0 = not drawn.
;------------------------------------------------------------------------------
key_positions:	; from: draw_key, keyboard_key_click
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
; key_names: the text drawn for each scan code 0-$72 (and printed in the key list and for a stuck
; key); 0 = none. The cursor keys use the arrow characters 1-4 of the font, Return and keypad
; Enter are drawn over two rows with line feeds and backspaces.
;------------------------------------------------------------------------------
key_names:	; from: keyboard_test, draw_key, reset_keyboard_and_check
	dc.l	$00000000
	dc.l	key_text_esc
	dc.l	key_text_1
	dc.l	key_text_2
	dc.l	key_text_3
	dc.l	key_text_4
	dc.l	key_text_5
	dc.l	key_text_6
	dc.l	key_text_7
	dc.l	key_text_8
	dc.l	key_text_9
	dc.l	key_text_0
	dc.l	key_text_minus
	dc.l	key_text_equals
	dc.l	key_text_backspace
	dc.l	key_text_tab
	dc.l	key_text_q
	dc.l	key_text_w
	dc.l	key_text_e
	dc.l	key_text_r
	dc.l	key_text_t
	dc.l	key_text_y
	dc.l	key_text_u
	dc.l	key_text_i
	dc.l	key_text_o
	dc.l	key_text_p
	dc.l	key_text_left_bracket
	dc.l	key_text_right_bracket
	dc.l	key_text_return
	dc.l	key_text_control
	dc.l	key_text_a
	dc.l	key_text_s
	dc.l	key_text_d
	dc.l	key_text_f
	dc.l	key_text_g
	dc.l	key_text_h
	dc.l	key_text_j
	dc.l	key_text_k
	dc.l	key_text_l
	dc.l	key_text_semicolon
	dc.l	key_text_apostrophe
	dc.l	key_text_backquote
	dc.l	key_text_left_shift
	dc.l	key_text_backslash
	dc.l	key_text_z
	dc.l	key_text_x
	dc.l	key_text_c
	dc.l	key_text_v
	dc.l	key_text_b
	dc.l	key_text_n
	dc.l	key_text_m
	dc.l	key_text_comma
	dc.l	key_text_full_stop
	dc.l	key_text_slash
	dc.l	key_text_right_shift
	dc.l	$00000000
	dc.l	key_text_alternate
	dc.l	key_text_space
	dc.l	key_text_caps_lock
	dc.l	key_text_f1
	dc.l	key_text_f2
	dc.l	key_text_f3
	dc.l	key_text_f4
	dc.l	key_text_f5
	dc.l	key_text_f6
	dc.l	key_text_f7
	dc.l	key_text_f8
	dc.l	key_text_f9
	dc.l	key_text_f10
	dc.l	$00000000,$00000000
	dc.l	key_text_clr_home
	dc.l	key_text_up_arrow
	dc.l	$00000000
	dc.l	key_text_minus
	dc.l	key_text_left_arrow
	dc.l	$00000000
	dc.l	key_text_right_arrow
	dc.l	key_text_plus
	dc.l	$00000000
	dc.l	key_text_down_arrow
	dc.l	$00000000
	dc.l	key_text_insert
	dc.l	key_text_delete
	dc.l	$00000000,$00000000,$00000000,$00000000
	dc.l	$00000000,$00000000,$00000000,$00000000
	dc.l	$00000000,$00000000,$00000000,$00000000
	dc.l	key_text_iso
	dc.l	key_text_undo
	dc.l	key_text_help
	dc.l	key_text_left_paren
	dc.l	key_text_right_paren
	dc.l	key_text_slash
	dc.l	key_text_asterisk
	dc.l	key_text_7
	dc.l	key_text_8
	dc.l	key_text_9
	dc.l	key_text_4
	dc.l	key_text_5
	dc.l	key_text_6
	dc.l	key_text_1
	dc.l	key_text_2
	dc.l	key_text_3
	dc.l	key_text_keypad_0
	dc.l	key_text_full_stop
	dc.l	key_text_keypad_enter
key_text_esc:
	dc.w	$1b00                           ; the Esc character of the font
key_text_1:
	dc.w	$3100                           ; "1", also keypad 1
key_text_2:
	dc.w	$3200                           ; "2", also keypad 2
key_text_3:
	dc.w	$3300                           ; "3", also keypad 3
key_text_4:
	dc.w	$3400                           ; "4", also keypad 4
key_text_5:
	dc.w	$3500                           ; "5", also keypad 5
key_text_6:
	dc.w	$3600                           ; "6", also keypad 6
key_text_7:
	dc.w	$3700                           ; "7", also keypad 7
key_text_8:
	dc.w	$3800                           ; "8", also keypad 8
key_text_9:
	dc.w	$3900                           ; "9", also keypad 9
key_text_0:
	dc.w	$3000                           ; "0"
key_text_minus:
	dc.w	$2d00                           ; "-", also keypad -
key_text_plus:
	dc.w	$2b00                           ; "+", keypad
key_text_equals:
	dc.w	$3d00                           ; "="
key_text_backspace:
	dc.w	$4253                           ; "BS"
	dc.b	$00
key_text_tab:
	dc.b	$54,$42,$00                     ; "TB"
key_text_q:
	dc.w	$5100                           ; "Q"
key_text_w:
	dc.w	$5700                           ; "W"
key_text_e:
	dc.w	$4500                           ; "E"
key_text_r:
	dc.w	$5200                           ; "R"
key_text_t:
	dc.w	$5400                           ; "T"
key_text_y:
	dc.w	$5900                           ; "Y"
key_text_u:
	dc.w	$5500                           ; "U"
key_text_i:
	dc.w	$4900                           ; "I"
key_text_o:
	dc.w	$4f00                           ; "O"
key_text_p:
	dc.w	$5000                           ; "P"
key_text_left_bracket:
	dc.w	$5b00                           ; "["
key_text_right_bracket:
	dc.w	$5d00                           ; "]"
key_text_return:
	dc.w	$200a,$0820,$0a08,$0852,$5400   ; Return over two rows, "RT"
key_text_control:
	dc.b	'CTL',0
key_text_a:
	dc.w	$4100                           ; "A"
key_text_s:
	dc.w	$5300                           ; "S"
key_text_d:
	dc.w	$4400                           ; "D"
key_text_f:
	dc.w	$4600                           ; "F"
key_text_g:
	dc.w	$4700                           ; "G"
key_text_h:
	dc.w	$4800                           ; "H"
key_text_j:
	dc.w	$4a00                           ; "J"
key_text_k:
	dc.w	$4b00                           ; "K"
key_text_l:
	dc.w	$4c00                           ; "L"
key_text_semicolon:
	dc.w	$3b00                           ; ";"
key_text_apostrophe:
	dc.w	$2700                           ; "'"
key_text_backquote:
	dc.w	$6000                           ; "`"
key_text_left_shift:
	dc.b	' SH ',0
key_text_backslash:	; from: draw_key
	dc.b	$5c,$00                         ; "\"
key_text_z:
	dc.b	$5a,$00                         ; "Z"
key_text_x:
	dc.b	$58,$00                         ; "X"
key_text_c:
	dc.b	$43,$00                         ; "C"
key_text_v:
	dc.b	$56,$00                         ; "V"
key_text_b:
	dc.b	$42,$00                         ; "B"
key_text_n:
	dc.b	$4e,$00                         ; "N"
key_text_m:
	dc.b	$4d,$00                         ; "M"
key_text_comma:
	dc.b	$2c,$00                         ; ","
key_text_full_stop:
	dc.b	$2e,$00                         ; ".", also keypad .
key_text_slash:
	dc.b	$2f,$00                         ; "/", also keypad /
key_text_right_shift:
	dc.b	$53,$48,$00                     ; "SH"
key_text_alternate:
	dc.w	$414c                           ; "AL"
	dc.b	$00
key_text_space:
	dc.b	'      SPACE      ',0
key_text_caps_lock:
	dc.b	$43,$4c,$00                     ; "CL"
key_text_f1:
	dc.w	$4631                           ; "F1"
	dc.b	$00
key_text_f2:
	dc.b	$46,$32,$00                     ; "F2"
key_text_f3:
	dc.w	$4633                           ; "F3"
	dc.b	$00
key_text_f4:
	dc.b	$46,$34,$00                     ; "F4"
key_text_f5:
	dc.w	$4635                           ; "F5"
	dc.b	$00
key_text_f6:
	dc.b	$46,$36,$00                     ; "F6"
key_text_f7:
	dc.w	$4637                           ; "F7"
	dc.b	$00
key_text_f8:
	dc.b	$46,$38,$00                     ; "F8"
key_text_f9:
	dc.w	$4639                           ; "F9"
	dc.b	$00
key_text_f10:
	dc.b	'F10',0
key_text_clr_home:
	dc.b	$48,$00                         ; "H"
key_text_up_arrow:	; from: draw_mouse_up_arrow
	dc.b	$01,$00                         ; font character 1, also the mouse up arrow
key_text_left_arrow:	; from: draw_mouse_left_arrow, floppy_speed_test
	dc.b	$04,$00                         ; font character 4, also the mouse left arrow and the speed test
key_text_right_arrow:	; from: draw_mouse_right_arrow
	dc.b	$03,$00                         ; font character 3, also the mouse right arrow
key_text_down_arrow:	; from: draw_mouse_down_arrow
	dc.b	$02,$00                         ; font character 2, also the mouse down arrow
key_text_insert:
	dc.b	$49,$00                         ; "I"
key_text_delete:
	dc.b	$44,$00                         ; "D"
key_text_iso:
	dc.b	$20,$00                         ; " ", the key left of Z (scan code $60)
key_text_undo:
	dc.b	$55,$4e,$00                     ; "UN"
key_text_help:
	dc.w	$4850                           ; "HP"
	dc.b	$00
key_text_left_paren:
	dc.b	$28,$00                         ; "(", keypad
key_text_right_paren:
	dc.b	$29,$00                         ; ")", keypad
key_text_asterisk:
	dc.b	$2a,$00                         ; "*", keypad
key_text_keypad_0:
	dc.b	'0  ',0
key_text_keypad_enter:
	dc.b	$45,$0a,$08,$20,$0a,$08,$20,$00 ; "E" over two rows
key_text_hash:	; from: draw_key
	dc.b	$23,$00                         ; "#", for a U.K. keyboard (draw_key never reaches it)

;------------------------------------------------------------------------------
; Keyboard test texts (K codes).
;------------------------------------------------------------------------------
msg_keyboard_test:	; from: keyboard_test
	dc.b	'Keyboard test',0
msg_mouse:	; from: keyboard_test
	dc.b	'MOUSE',0
msg_key_list_return:	; from: keyboard_test
	dc.b	$52,$54,$00                     ; "RT"
msg_key_list_enter:	; from: keyboard_test
	dc.b	'ENTER',0
msg_key_list_space:	; from: keyboard_test
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
msg_hit_shift_esc:	; from: keyboard_test
	dc.b	9,'Hit shift Esc to exit',0
	dc.b	$00                             ; pad

;------------------------------------------------------------------------------
; midi_record_init: copied to the MIDI record at $620 by midi_test (30 bytes): the input
; buffer (address, size, head, tail, low and high water marks), the same for the output buffer,
; then the ACIA status word (offset $1C).
;------------------------------------------------------------------------------
midi_record_init:	; from: midi_test
	dc.l	$00000520                       ; input buffer $520
	dc.w	$0080,$0000,$0000,$0010,$0030   ; size 128, head, tail, low 16, high 48
	dc.l	$000005a0                       ; output buffer $5A0
	dc.w	$0080,$0000,$0000,$0020,$0060   ; size 128, head, tail, low 32, high 96
	dc.w	$0000                           ; the last ACIA status

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
	dc.b	$01,$02,$04,$08,$10,$20,$40,$00 ; the rate codes again (as rs232_rate_codes); no reference

;------------------------------------------------------------------------------
; rs232_error_texts: the texts printed for the RS232 loopback test's error bits: bits 0-7 of $49A
; then bits 0-4 of $49B (13 texts, printed for each bit set).
;------------------------------------------------------------------------------
rs232_error_texts:	; from: rs232_test
	dc.l	msg_rs232_data_overrun          ; $49A bit 0, overrun
	dc.l	msg_rs232_parity                ; bit 1, parity
	dc.l	msg_rs232_framing               ; bit 2, framing
	dc.l	msg_rs232_data_mismatch         ; bit 3, data mismatch
	dc.l	msg_rs232_not_received          ; bit 4, not received
	dc.l	msg_rs232_irq                   ; bit 5, IRQ
	dc.l	msg_rs232_transmit_error_interrupt ; bit 6, transmit error interrupt
	dc.l	msg_rs232_receive_error_interrupt ; bit 7, receive error interrupt
	dc.l	msg_rs232_ri_dtr                ; $49B bit 0, RI not looped to DTR
	dc.l	msg_rs232_dcd_dtr               ; bit 1, DCD not looped to DTR
	dc.l	msg_rs232_rts_cts               ; bit 2, CTS not looped to RTS
	dc.l	msg_rs232_transmit_error        ; bit 3, transmit buffer never empty
	dc.l	msg_rs232_input_shorted         ; bit 4, input shorted to output

;------------------------------------------------------------------------------
; rs232_rate_codes: the Timer D data values for the RS232 rates (Timer D /4: 19200 bps / value),
; 1 = 19200 ... $40 = 300; print_rs232_rate finds the rate's index here and prints that text of
; rs232_rate_texts.
;------------------------------------------------------------------------------
rs232_rate_codes:	; from: print_rs232_rate
	dc.b	$01,$02,$04,$08,$10,$20,$40,$00 ; 7 codes and a pad byte
rs232_rate_texts:	; from: print_rs232_rate
	dc.l	msg_rate_19200
	dc.l	msg_rate_9600
	dc.l	msg_rate_4800
	dc.l	msg_rate_2400
	dc.l	msg_rate_1200
	dc.l	msg_rate_600
	dc.l	msg_rate_300
msg_rate_19200:
	dc.b	'19.2k bps',0
msg_rate_9600:
	dc.b	'9600 bps ',0
msg_rate_4800:
	dc.b	'4800 bps ',0
msg_rate_2400:
	dc.b	'2400 bps ',0
msg_rate_1200:
	dc.b	'1200 bps ',0
msg_rate_600:
	dc.b	'600 bps  ',0
msg_rate_300:
	dc.b	'300 bps  ',0
rs232_loopback_text:	; from: rs232_test
	dc.b	'No loopback connector',13,10,0 ; sent through the loopback plug at 19200 bps, not printed
rs232_loopback_bytes:	; from: rs232_test
	dc.b	$55,$aa,$00,$ff,$e5,$d1,$00     ; sent at each rate; the 0 ends it, so only $55 and $AA go

;------------------------------------------------------------------------------
; RS232 test texts (S codes).
;------------------------------------------------------------------------------
msg_testing_rs232_loopback:	; from: rs232_test
	dc.b	'Testing RS232 loopback',13,10,0
	dc.b	'Hold down button (or remove loopback), and press key.',13,10 ; no reference
	dc.b	'Press ESC to skip this test.',13,10,0
msg_rs232_not_received:	; from: rs232_error_texts
	dc.b	'S0 RS232 not received',13,10,0
msg_rs232_data_mismatch:	; from: rs232_error_texts
	dc.b	'S1 RS232 data mismatch',13,10,0
msg_rs232_framing:	; from: rs232_error_texts
	dc.b	'S2 RS232 framing',13,10,0
msg_rs232_parity:	; from: rs232_error_texts
	dc.b	'S3 RS232 parity',13,10,0
msg_rs232_data_overrun:	; from: rs232_error_texts
	dc.b	'S4 RS232 data overrun',13,10,0
msg_rs232_irq:	; from: rs232_error_texts
	dc.b	'S5 RS232 IRQ',13,10,0
msg_rs232_transmit_error:	; from: rs232_error_texts
	dc.b	'S6 RS232 transmit error (68901)',13,10,0
msg_rs232_transmit_error_interrupt:	; from: rs232_error_texts
	dc.b	'S7 RS232 Transmit error interrupt',13,10,0
msg_rs232_receive_error_interrupt:	; from: rs232_error_texts
	dc.b	'S8 RS232 Receive error interrupt',13,10,0
msg_rs232_ri_dtr:	; from: rs232_error_texts
	dc.b	'S9 RS232 RI-DTR not connected',13,10,0
msg_rs232_dcd_dtr:	; from: rs232_error_texts
	dc.b	'SA RS232 DCD-DTR not connected',13,10,0
msg_rs232_rts_cts:	; from: rs232_error_texts
	dc.b	'SB RS232 RTS-CTS not connected',13,10,0
msg_rs232_input_shorted:	; from: rs232_error_texts
	dc.b	'SC RS232 input shorted to output',13,10,0
	dc.b	$00                             ; pad

;------------------------------------------------------------------------------
; DMA sound descriptors for dma_sound_test: the sound's address once dma_sound_samples is copied
; to $40000 (play_dma_sound reads the length long there, the samples follow), the number of
; frames to play (counted with Timer A on the DMA sound end-of-frame signal) and the sound mode.
;------------------------------------------------------------------------------
dma_sound_mono_tone:	; from: dma_sound_test
	dc.l	$00040000,$00000320             ; $40000, 800 frames
	dc.w	$0083                           ; mono, 50 kHz
dma_sound_stereo_tones:	; from: dma_sound_test
	dc.l	$00040034,$00000320             ; $40034, 800 frames
	dc.w	$0002                           ; stereo, 25 kHz
dma_sound_treble_tone:	; from: dma_sound_test
	dc.l	$00040098,$00000bb8             ; $40098, 3000 frames
	dc.w	$0083                           ; mono, 50 kHz

;------------------------------------------------------------------------------
; dma_sound_bass_tones: two descriptors of 10 bytes, played in turn.
;------------------------------------------------------------------------------
dma_sound_bass_tones:	; from: dma_sound_test
	dc.l	$000400a4,$0000000a             ; $400A4, 10 frames
	dc.w	$0080                           ; mono, 6.25 kHz
	dc.l	$00040120,$0000000a             ; $40120, 10 frames
	dc.w	$0081                           ; mono, 12.5 kHz

;------------------------------------------------------------------------------
; dma_sound_samples: the DMA sounds, copied to $40000 by dma_sound_test: each a length long and
; that many signed 8-bit samples. dma_sound_test copies $215 words, twice the $214 bytes here, so
; the tables after it are copied too.
;------------------------------------------------------------------------------
dma_sound_samples:	; from: dma_sound_test
	dc.l	$00000030                       ; 48 bytes: one sine cycle, 1 kHz at 50 kHz mono
	dc.b	$00,$11,$21,$31,$40,$4d,$5a,$65,$6e,$74,$7b,$7e,$7f,$7e,$7b,$74
	dc.b	$6e,$65,$5a,$4d,$40,$31,$21,$11,$00,$ef,$df,$cf,$c0,$b3,$a6,$9c
	dc.b	$92,$8c,$85,$82,$81,$82,$85,$8b,$92,$9b,$a6,$b3,$c0,$cf,$df,$ef
	dc.l	$00000060                       ; 96 bytes: stereo pairs (left, right), 500 Hz left and 1 kHz right at
                                                ;   25 kHz
	dc.w	$0000,$1021,$213f,$315a,$3f6e,$4d7b,$5a7f,$657b
	dc.w	$6e6e,$755a,$7b3f,$7d21,$7f00,$7edf,$7cc1,$75a6
	dc.w	$6e92,$6585,$5a80,$4d85,$3f92,$31a6,$21c1,$10df
	dc.w	$0000,$f021,$df3f,$cf5a,$c16e,$b37b,$a67f,$9b7b
	dc.w	$926e,$8b5a,$853f,$8321,$8000,$82df,$84c1,$89a6
	dc.w	$9192,$9c85,$a680,$b385,$c192,$cca6,$dfc1,$f0df
	dc.l	$00000008                       ; 8 bytes: a square wave, 6.25 kHz at 50 kHz
	dc.b	$7f,$7f,$80,$80,$7f,$7f,$80,$80
	dc.l	$00000078                       ; 120 bytes: one sine cycle, 52 Hz at 6.25 kHz
	dc.b	$00,$07,$0d,$14,$1a,$21,$27,$2d,$34,$3a,$3f,$45,$4b,$50,$55,$5a
	dc.b	$5e,$63,$67,$6b,$6e,$71,$74,$76,$79,$7b,$7c,$7d,$7e,$7e,$7f,$7f
	dc.b	$7e,$7d,$7c,$7b,$79,$76,$74,$71,$6e,$6b,$67,$63,$5e,$5a,$55,$50
	dc.b	$4b,$45,$3f,$3a,$34,$2d,$27,$21,$1a,$14,$0d,$07,$00,$f9,$f3,$ec
	dc.b	$e6,$df,$d9,$d3,$cc,$c6,$c1,$bb,$b5,$b0,$ab,$a6,$a2,$9d,$99,$95
	dc.b	$92,$8f,$8c,$8a,$87,$85,$83,$82,$81,$81,$80,$80,$81,$82,$83,$84
	dc.b	$85,$87,$8a,$8c,$92,$95,$99,$9d,$a2,$a6,$ab,$b0,$b5,$bb,$c1,$c6
	dc.b	$cc,$d3,$d9,$df,$e6,$ec,$f3,$f9
	dc.l	$000000f0                       ; 240 bytes: one sine cycle, 52 Hz at 12.5 kHz
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
; PSG tables for the sound chip tone routines, indexed by the channel (0-2): psg_mixer_tone_only
; the mixer value (register 7) with only that channel's tone on, psg_period_registers the
; channel's period low register, psg_volume_registers its volume register.
;------------------------------------------------------------------------------
psg_mixer_tone_only:	; from: psg_tone_soft, psg_tone_loud
	dc.b	$fe,$fd,$fb
psg_period_registers:	; from: psg_tone_soft, psg_tone_loud
	dc.b	$00,$02,$04
psg_volume_registers:	; from: audio_test_step, psg_tone_soft, psg_tone_loud, fail_sweeps
	dc.b	$08,$09,$0a,$00                 ; and a pad byte

;------------------------------------------------------------------------------
; LMC1992 command steps for dma_sound_test, one word per step: lmc_master_volume_steps
; (-80 dB up to 0 dB, 8 steps), lmc_left_volume_steps (-40 dB up to 0 dB) with
; lmc_right_volume_steps (0 dB down to -40 dB) at the same time, then lmc_treble_steps and
; lmc_bass_steps (10 steps of the 0-12 value, 6 = 0 dB; $80 or $40 is added for the command).
;------------------------------------------------------------------------------
lmc_master_volume_steps:	; from: dma_sound_test
	dc.w	$00c0,$00d0,$00d8,$00e0,$00e4,$00e8,$00e8,$00e8
lmc_left_volume_steps:	; from: dma_sound_test
	dc.w	$0140,$0148,$014a,$014c,$0150,$0154,$0154,$0154
lmc_right_volume_steps:	; from: dma_sound_test
	dc.w	$0114,$0114,$0114,$0110,$010c,$010a,$0108,$0100
lmc_treble_steps:	; from: dma_sound_test
	dc.w	$0007,$0007,$0007,$0007,$0006,$0005,$0004,$0003 ; +2 dB down to -10 dB
	dc.w	$0002,$0001
lmc_bass_steps:	; from: dma_sound_test
	dc.w	$0006,$0006,$0006,$0006,$0006,$0005,$0004,$0003 ; 0 dB down to -10 dB
	dc.w	$0002,$0001

;------------------------------------------------------------------------------
; Audio test texts.
;------------------------------------------------------------------------------
msg_listen_sweep:	; from: audio_test
	dc.b	'Listen for low to high sweep:',13,10,0
psg_channel_names:	; from: print_channel_name
	dc.l	msg_channel_a                   ; the name of each channel, printed as its sweep starts
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
msg_testing_timing:	; from: timing_test
	dc.b	'Testing MFP, Glue timing, Video',13,10,0
msg_mfp_timer_error:	; from: timing_test
	dc.b	13,10,'T0 MFP timer',13,10,0
msg_vertical_sync_error:	; from: timing_test
	dc.b	13,10,'T1 Vertical Sync',13,10,0
msg_horizontal_sync_error:	; from: timing_test
	dc.b	13,10,'T2 Horizontal Sync',13,10,0
msg_display_enable_error:	; from: timing_test
	dc.b	13,10,'T3 Display Enable',13,10,0
msg_video_counter_error:	; from: timing_test
	dc.b	13,10,'T4 Video Counter in Memory Controller',13,10,0
msg_psg_bus_test:	; from: timing_test
	dc.b	'T5 PSG Bus Test ',9,0
msg_1772_bus_test:	; from: timing_test
	dc.b	'T6 1772 Bus Test',9,0
	dc.b	$00                             ; pad

;------------------------------------------------------------------------------
; video_counter_test_bases: the screen addresses / 256 at which the T4 video counter test runs (the
; high byte is the 64K bank); the test ends at the first one at or above the top of RAM.
;------------------------------------------------------------------------------
video_counter_test_bases:	; from: timing_test
	dc.w	$0010,$0011,$0012,$0014,$0018,$0020,$0040,$0080
	dc.w	$0100,$0200,$0300,$0400,$0500,$0600,$0700,$0800
	dc.w	$1000,$2000,$3000,$4000

;------------------------------------------------------------------------------
; dma_port_test_addresses: the RAM addresses dma_port_test sends through the DMA port loopback;
; it stops at the first one at or above the top of RAM. The first ($1000) is also the start of
; its first transfer.
;------------------------------------------------------------------------------
dma_port_test_addresses:	; from: dma_port_test
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
; joystick_bytes_sent and joystick_bytes_wanted: printer_joystick_test writes each of the eight
; bytes to the printer port and compares the joystick directions read through the test plug
; (joystick 0 in the high nibble, joystick 1 in the low) with the byte wanted.
;------------------------------------------------------------------------------
joystick_bytes_sent:	; from: printer_joystick_test
	dc.b	$f8,$f9,$fa,$fb,$fc,$fd,$fe,$ff
joystick_bytes_wanted:	; from: printer_joystick_test
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
msg_joystick_port_0_error:	; from: printer_joystick_test
	dc.b	'J0 Joystick Port 0 error',13,10,0
msg_joystick_port_1_error:	; from: printer_joystick_test
	dc.b	'J1 Joystick Port 1 error',13,10,0
msg_joystick_time_out:	; from: printer_joystick_test
	dc.b	'J2 Joystick time-out',13,10,0
msg_left_button_line_error:	; from: printer_joystick_test
	dc.b	'J3 Left button line error',13,10,0
msg_right_button_line_error:	; from: printer_joystick_test
	dc.b	'J4 Right button line error',13,10,0
msg_aux_joystick_direction:	; from: printer_joystick_test
	dc.b	'J5 Aux joystick direction ',0
msg_aux_fire_button:	; from: printer_joystick_test
	dc.b	'J6 Aux fire button ',13,10,0
msg_paddle:	; from: printer_joystick_test
	dc.b	'J7 Paddle ',0
msg_light_gun:	; from: printer_joystick_test
	dc.b	'J8 Light gun ',0

;------------------------------------------------------------------------------
; High resolution test texts.
;------------------------------------------------------------------------------
msg_connect_mono_monitor:	; from: mono_monitor_test
	dc.b	'Connect monochrome monitor',13,10,0
	dc.b	'Disconnect monochrome monitor',13,10,0 ; no reference
	dc.b	'Press any key to return to menu',13,10,0 ; no reference

;------------------------------------------------------------------------------
; floppy_exerciser_track_order: the 80 tracks in the mixed order the disk exerciser reads them,
; one byte each (indexed by the step count at $296).
;------------------------------------------------------------------------------
floppy_exerciser_track_order:	; from: floppy_exerciser
	dc.b	$00,$4f,$2e,$20,$01,$0a,$3c,$16,$43,$2c,$3b,$2d,$11,$21,$2f,$14
	dc.b	$4a,$15,$42,$44,$12,$48,$38,$47,$10,$49,$04,$22,$45,$1b,$3a,$39
	dc.b	$06,$46,$27,$30,$35,$08,$4b,$4c,$1c,$1d,$26,$4d,$17,$09,$28,$41
	dc.b	$1a,$3d,$4e,$25,$0c,$34,$13,$31,$0e,$0f,$36,$23,$24,$1e,$0d,$05
	dc.b	$33,$07,$3f,$19,$37,$3e,$0b,$40,$2a,$29,$18,$32,$1f,$2b,$03,$02

;------------------------------------------------------------------------------
; quick_test_track_list: the tracks the floppy quick test formats, writes and reads: 0, 1 and 79.
;------------------------------------------------------------------------------
quick_test_track_list:	; from: quick_test_tracks
	dc.b	$00,$01,$4f

;------------------------------------------------------------------------------
; interchange_test_track_list: the tracks the disk interchange test writes and reads: 0, 39 and 79.
;------------------------------------------------------------------------------
interchange_test_track_list:	; from: floppy_interchange
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
msg_drive_side_choice:	; from: floppy_install_drives
	dc.b	'Type 1 or S to test single sided, 2 or D for double sided.',13,10
	dc.b	'Any other key will de-install this device.',13,10,0
msg_enter_track_number:	; from: floppy_alignment
	dc.b	'Enter track number (if none entered, default=40): ',0
	dc.b	'Select single sided (1) or double sided (2)',13,10,0 ; no reference
msg_read_alignment_disk:	; from: floppy_alignment
	dc.b	'Read analog alignment disk',13,10 ; runs on into msg_disk_a_or_b
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
msg_esc_quit_any_key_repeat:	; from: floppy_interchange
	dc.b	'Hit esc to quit, any other key to repeat',13,10,0
msg_checking_drives:	; from: detect_drive_types
	dc.b	'Checking...',13,10,0
msg_disk_a:                                     ; from: floppy_quick_test, floppy_interchange_drive_lines,
                                                ;   floppy_install_drives, print_drive_name, print_a_not_selected
	dc.b	'Disk A: ',0
msg_disk_b:                                     ; from: floppy_quick_test, floppy_interchange_drive_lines,
                                                ;   floppy_install_drives, print_drive_name, print_b_not_selected
	dc.b	'Disk B: ',0
msg_cannot_write_drive_a:	; from: detect_drive_types
	dc.b	'Cannot write drive A',13,10,0
msg_cannot_write_drive_b:	; from: detect_drive_types
	dc.b	'Cannot write drive B',13,10,0
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
msg_writing:	; from: write_track
	dc.b	'Writing    ',0
msg_reading:	; from: floppy_alignment, read_track
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
msg_speed_heading:	; from: floppy_speed_test
	dc.b	'Max      Min      Current speed',0
msg_soft_error:	; from: write_track, read_track
	dc.b	'Soft Error',13,10,0
msg_bad_sector:	; from: print_floppy_error
	dc.b	'Bad Sector: ',0
msg_not_selected:	; from: print_a_not_selected
	dc.b	'F0 Not selected ',0
	dc.b	'Side 0 ',0                     ; no reference
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
msg_floppy_crc_error:	; from: print_floppy_error
	dc.b	'F9 CRC error ',0
msg_record_not_found:	; from: print_floppy_error
	dc.b	'FA Record not found ',0
msg_lost_data:	; from: print_floppy_error
	dc.b	'FB Lost data ',0
msg_side_select_error:	; from: floppy_quick_test_drive
	dc.b	'FC Side select error--single sided drive',13,10,0
msg_drive_not_ready:	; from: floppy_alignment, print_floppy_error
	dc.b	'FD Drive not ready ',0
msg_stopped_esc_quit:	; from: floppy_alignment
	dc.b	'Stopped. ESC to quit, any other key to continue.',0
msg_hard_error:	; from: write_track, read_track
	dc.b	'Hard error',13,10,0
msg_fail:	; from: floppy_quick_test
	dc.b	'Fail ',0
	dc.b	$00                             ; pad

;------------------------------------------------------------------------------
; BLiTTER test texts (G codes).
;------------------------------------------------------------------------------
msg_testing_blitter:	; from: blit_short_test, blit_long_test, blit_long_set_up
	dc.b	'Testing Blitter',13,10,0
msg_blit_halftone_ram:	; from: blit_short_error_texts
	dc.b	'G1 halftone RAM',13,10,0
msg_blit_endmask:	; from: blit_short_error_texts
	dc.b	'G2 endmask',13,10,0
msg_blit_operation:	; from: blit_short_error_texts
	dc.b	'G3 operation ',13,10,0
msg_blit_halftone_op:	; from: blit_short_error_texts
	dc.b	'G4 halftone op',13,10,0
msg_blit_skew:	; from: blit_short_error_texts
	dc.b	'G5 skew',13,10,0
msg_blit_reverse:	; from: blit_short_error_texts
	dc.b	'G6 reverse blt',13,10,0
msg_blit_fxsr:	; from: blit_short_error_texts
	dc.b	'G7 force extra source read',13,10,0
msg_blit_smudge:	; from: blit_short_error_texts
	dc.b	'G8 smudge',13,10,0
msg_blit_x_count:	; from: blit_short_error_texts
	dc.b	'G9 x count',13,10,0
msg_blit_y_count:	; from: blit_short_error_texts
	dc.b	'G10 y count',13,10,0
msg_blit_time_out:	; from: blit_short_error_texts
	dc.b	'G11 time-out',13,10,0
msg_blit_address_count:	; from: blit_short_error_texts
	dc.b	'G12 address count',13,10,0
msg_no_blitter:	; from: blit_short_test, blit_long_test
	dc.b	'No Blitter installed',13,10,0
	dc.b	$00                             ; pad

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
; msg_replace_blitter: printed when a bus error stops the long BLiT test (46 spaces first).
;------------------------------------------------------------------------------
msg_replace_blitter:	; from: blit_long_bus_error
	dcb.w	23,$2020
	dc.b	13,10,'-------->      Replace Blitter     <----------',13,10
	dc.b	'>>>> Bus error has occurred during BLiT test! <<<<<',13,10,0

;------------------------------------------------------------------------------
; acsi_stop_unit and acsi_start_unit: ACSI START/STOP UNIT command blocks (6 bytes; the device
; number is ORed into the first). hd_park_heads sends the first to stop the unit and park the
; heads; the second has no reference.
;------------------------------------------------------------------------------
acsi_stop_unit:	; from: hd_park_heads
	dc.b	$1b,$00,$00,$00,$00,$00
acsi_start_unit:
	dc.b	$1b,$00,$00,$00,$01,$00         ; no reference

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
; font_8x8: the 8x8 font of characters 0-127, used in low and medium resolution. Laid out by
; scan line: the byte for character c, line r is at c + 128 * r. Characters 1-4 are arrows (up,
; down, right, left), 5 a solid block, 6 the copyright sign.
;------------------------------------------------------------------------------
font_8x8:	; from: font_by_res
	dc.w	$0018,$3c18,$18ff,$3ce7,$01d8,$c0cc,$f8f0,$0db0
	dc.w	$0000,$0000,$0000,$0000,$0000,$0078,$0003,$c048
	dc.w	$0000,$0000,$1800,$1c00,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0600,$6000
	dcb.b	59,0
	dc.b	$0e,$18,$70,$00,$10,$00,$3c,$24,$1c,$38,$ff,$42,$c3,$03,$d8,$c0
	dc.b	$cc,$c0,$c0,$0d,$b0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$36
	dc.b	$60,$1c,$07,$e0,$92,$00,$18,$66,$66,$3e,$66,$36,$18,$0e,$70,$66
	dc.b	$18,$00,$00,$00,$06,$3c,$18,$3c,$7e,$0c
	dc.b	'~<~<<',0
	dc.b	$00,$0c,$00,$30,$3c,$3c,$18
	dc.b	'|<x~~>f~'
	dc.b	$06
	dc.b	'f`cf<|<|<~ffcff~'
	dc.b	$1e,$40,$78,$08,$00,$c0,$00,$60,$00,$06,$00,$0e,$00,$60,$18,$06
	dc.b	$60,$38,$00,$00,$00,$00,$00,$00,$00,$18,$00,$00,$00,$00,$00,$00
	dc.b	$18,$18,$18,$30,$18,$00,$66,$24,$f6,$6f,$ff,$99,$a5,$06,$f8,$de
	dc.b	$78,$fe,$df,$0d,$b0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7f
	dc.b	$78,$1c,$0e,$70,$24,$00,$18,$66,$ff,$60,$6c,$1c,$18,$1c,$38,$3c
	dc.b	$18,$00,$00,$00,$0c,$66,$38,$66,$0c,$1c,$60,$60,$06,$66,$66,$18
	dc.b	$18,$18,$7e,$18
	dc.b	'ff<ffl```f'
	dc.b	$18,$06
	dc.b	'l`wvffff`'
	dc.w	$1866,$6663,$6666,$0c18,$6018,$1c00,$603c,$603c
	dc.w	$063c,$183e,$6000,$0060
	dc.b	$18
	dc.b	'f|<|>|>~ffcff~'
	dc.b	$18,$18,$18,$79,$1c,$00,$c3,$e7,$83,$c1,$ff,$a1,$7e,$8c,$df,$d8
	dc.b	$7f,$d8,$db,$0d,$b0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7f
	dc.b	$60,$77,$1c,$38,$48,$00,$18,$66,$66,$3c,$18,$38,$18,$18,$18,$ff
	dc.b	$7e,$00,$7e,$00,$18,$6e,$18,$0c,$18,$3c,$7c,$7c,$0c,$3c,$3e,$18
	dc.b	$18,$30,$00,$0c,$0c
	dc.b	'nf|`f||`~'
	dc.b	$18,$06,$78,$60,$7f,$7e,$66,$66,$66,$66,$3c,$18,$66,$66,$6b,$3c
	dc.b	$3c,$18,$18,$30,$18,$36,$00,$30,$06
	dc.b	'|`>f>f|8'
	dc.w	$066c,$187f,$6666,$6666,$6660,$1866,$666b,$3c66
	dc.w	$0c30,$180c,$4f1e,$00e7,$c383,$c1ff,$a17e,$d8de
	dc.w	$fe36,$deff,$0db0,$0000,$0000,$0000,$0000,$0000
	dc.w	$3e7e,$7738,$1c92,$0018,$0066,$0630,$6f00,$1818
	dc.w	$3c18,$0000,$0030,$7618,$180c,$6c06,$6618,$6606
	dc.w	$0000,$1800,$1818
	dc.b	'nff`f``nf'
	dc.b	$18,$06
	dc.b	'x`k~f|f|'
	dc.b	$06,$18,$66,$66,$7f,$3c,$18,$30,$18,$18,$18,$63,$00,$00,$3e,$66
	dc.b	$60,$66,$7e,$18,$66,$66,$18,$06,$78,$18,$7f,$66,$66,$66,$66,$60
	dc.b	$3c,$18,$66,$66,$7f,$18,$66,$18,$18,$18,$18,$06,$1c,$00,$24,$66
	dc.b	$f6,$6f,$ff,$99,$a5,$70,$06,$18,$06,$18,$1e,$19,$98,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$1c,$18,$08,$70,$0e,$24,$00,$00,$00
	dc.b	$ff
	dc.b	'|ff',0
	dc.w	$1c38,$6618,$1800,$1860,$6618,$3066,$7e66,$6630
	dc.w	$660c,$1818,$0c7e,$3000
	dc.b	'`~ffl``ff'
	dc.b	$18
	dc.b	'fl`cnf`ll'
	dc.b	$06,$18,$66,$3c,$77,$66,$18,$60,$18,$0c,$18,$00,$00,$00,$66,$66
	dc.b	$60,$66,$60,$18,$3e,$66,$18,$06,$6c,$18,$6b,$66,$66,$7c,$3e,$60
	dc.b	$06,$18,$66,$3c,$3e,$3c,$3e,$30,$18,$18,$18,$00,$18,$00,$24,$3c
	dc.b	$1c,$38,$ff,$42,$c3,$20,$06,$18,$06,$18,$1b,$39,$9c,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$08,$1e,$1c,$e0,$07,$48,$00,$18,$00
	dc.b	$66,$18,$46,$3b,$00,$0e,$70,$00,$00,$18,$00,$18,$40,$3c,$7e,$7e
	dc.b	$3c,$0c,$3c,$3c,$30,$3c,$38,$18,$18,$06,$00,$60,$18
	dc.b	'>f|<x~`>f~<f~cf<`6f<'
	dc.w	$187e,$1863,$6618,$7e1e,$0678,$00ff,$003e,$7c3c
	dc.w	$3e3c,$1806,$663c,$0666,$3c63,$663c,$6006,$607c
	dc.w	$0e3e,$1836,$660c,$7e0e,$1870,$0010,$003c,$1818
	dc.w	$18ff,$3ce7,$0000,$0000,$0000,$6186,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$00c0,$0392,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$3000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0030,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	19,0
	dc.b	$7c,$00,$00,$3c,$00,$00,$00,$00,$00,$60,$06,$00,$00,$00,$00,$00
	dc.b	$00,$00,$78,$00,$00,$18,$00,$00,$00

;------------------------------------------------------------------------------
; font_8x16: the 8x16 font of characters 0-127, used in high resolution, laid out the same way
; (16 lines of 128 bytes).
;------------------------------------------------------------------------------
font_8x16:	; from: font_by_res
	dc.w	$0000,$0000,$00ff,$00e7
	dc.b	$00
	dc.b	'l`f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$00
	dc.b	$03,$c0,$00,$00,$00,$00,$00,$18,$00,$38,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$06
	dc.b	$00,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dcb.b	19,0
	dc.w	$4000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$00ff,$00c3,$006c,$6066,$787c,$05a0
	dc.w	$0000,$0000,$0000,$0000,$0000,$0078,$0003,$c000
	dc.w	$0000,$0000,$1800,$7c00,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0600,$6000
	dcb.b	30,0
	dc.w	$0800,$6000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0007,$18e0
	dc.w	$0000,$0000,$0000,$00ff,$3cc3,$016c,$6066,$607c
	dc.w	$05a0,$0000,$0000,$0000,$0000,$0000,$0060,$1807
	dc.w	$e022,$0018,$6666,$3e66,$6c18,$0660,$6600,$0000
	dc.w	$0006,$3c18,$3c7e,$0c7e
	dc.b	$1c
	dc.b	'~<<',0
	dc.b	$00,$0c,$00,$30,$3c,$1c,$18
	dc.b	'|<x~~>f~'
	dc.b	$06
	dc.b	'f`cf<|<|>~ffcff~'
	dc.b	$1e,$40,$78,$08,$00,$70,$00,$60,$00,$06,$00,$0e,$00,$60,$18,$0c
	dc.b	$60,$38,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$0c,$18,$30,$00,$00,$00,$18,$3c,$00,$00,$ff,$42,$bd,$01,$7c,$60
	dc.b	$66,$60,$60,$05,$a0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$60,$3c,$07,$e0,$77,$00,$18,$66,$66,$7e,$66,$6c,$18,$0c,$30,$66
	dc.b	$18,$00,$00,$00,$06,$7e,$18,$7e,$7e,$0c
	dc.b	'~<~~~',0
	dc.b	$00,$0c,$00
	dc.b	'0~><~~|~~~f~'
	dc.b	$06
	dc.b	'f`cf~~~~~~ffcff~'
	dc.b	$1e,$40,$78,$1c,$00,$38,$00,$60,$00,$06,$00,$1e,$00,$60,$18,$0c
	dc.b	$60,$38,$00,$00,$00,$00,$00,$00,$00,$18,$00,$00,$00,$00,$00,$00
	dc.b	$0c,$18,$30,$00,$00,$00,$3c,$24,$38,$1c,$ff,$81,$bd,$03,$6c,$60
	dc.b	$3c,$78,$60,$05,$a0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$78,$3c,$0e,$70,$77,$00,$18,$66,$ff,$60,$6c,$38,$18,$1c,$38,$3c
	dc.b	$18,$00,$00,$00,$0c,$66,$38,$66,$0c,$1c,$60,$70,$06,$66,$66,$18
	dc.b	$18,$18,$7e,$18
	dc.b	'fs~ffn```f'
	dc.b	$18,$06
	dc.b	'l`wfffff`'
	dc.w	$1866,$6663,$6666,$0c18,$6018,$1c00,$1c00,$6000
	dc.w	$0600,$1800,$6000,$0060,$1800,$0000,$0000,$0000
	dc.w	$1800,$0000,$0000,$000c,$1830,$0000,$0066,$242c
	dc.w	$34ff,$9924,$036c,$6018,$6060,$0db0,$0000,$0000
	dc.w	$0000,$0000,$0000,$0078,$180e,$707f,$0018,$66ff
	dc.w	$600c,$3818,$1818,$3c18,$0000,$000c,$6638,$660c
	dc.w	$1c60,$6006,$6666,$1818,$187e
	dc.b	$18
	dc.b	'faffff```f'
	dc.b	$18,$06
	dc.b	'l`wvffff`'
	dc.w	$1866,$6663,$3c66,$0c18,$6018,$3600,$0c3c,$7c3c
	dc.w	$3e3c,$183c,$7c38,$0c66
	dc.b	$18
	dc.b	'6<<|>|>~ffcff~'
	dc.b	$0c,$18,$30,$31,$00,$00,$c3,$24,$e6,$67,$ff,$a5,$24,$06,$6c,$78
	dc.b	$18,$6f,$7e,$0d,$b0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$60,$66,$1c,$38,$7f,$00,$18,$66,$66,$7c,$18,$70,$18,$18,$18,$ff
	dc.b	$7e,$00,$7e,$00,$18,$66,$18,$0c,$18,$3c,$7c,$60,$0c,$3c,$7e,$18
	dc.b	$18,$30,$00,$0c,$0c
	dc.b	'mf~`f||n~'
	dc.b	$18,$06,$78,$60,$7f,$76,$66,$66,$66,$66,$70,$18,$66,$66,$63,$3c
	dc.b	$3c,$18,$18,$30,$18,$36,$00,$04
	dc.b	'>~|~~~~~8'
	dc.w	$0c6e,$187f
	dc.b	'~~~~~~~ffcff~'
	dc.b	$1c,$18,$38,$79,$00,$00,$81,$e7,$83,$c1,$ff,$a1,$24,$06,$00,$00
	dc.b	$00,$6c,$7f,$1d,$b8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$60,$ff,$1c,$38,$7f,$00,$18,$66,$66,$3e,$18,$70,$18,$18,$18,$ff
	dc.b	$7e,$00,$7e,$00,$18,$6e,$18,$0c,$18,$3c,$7e,$7c,$0c,$3c,$3e,$18
	dc.b	$18,$30,$00,$0c,$0c
	dc.b	'kf|`f||n~'
	dc.b	$18,$06
	dc.b	'x`k~fff~8'
	dc.w	$1866,$666b,$183c,$1818,$3018,$6300,$0006,$6660
	dc.w	$6666,$7e66,$6618,$0c7c,$187f,$6666,$6666,$6660
	dc.w	$1866,$666b,$3c66,$0c78,$181e,$5f00,$00e7,$8181
	dc.w	$81ff,$a124,$8c3f,$0f3f,$6c1b,$399c,$0000,$0000
	dc.w	$0000,$0000,$0000,$007e,$ff38,$1c3e,$0018,$00ff
	dc.w	$0630,$de00,$1818,$3c18,$0000,$0030,$7618,$180c
	dc.w	$6c06,$7e18,$6606,$0000,$187e,$1818
	dc.b	'k~f`f``ff'
	dc.b	$18,$06
	dc.b	'l`k~f~f|'
	dc.b	$1c,$18,$66,$66,$6b,$18,$18,$30,$18,$18,$18,$63,$00,$00,$3e,$66
	dc.b	$60,$66,$66,$18,$66,$66,$18,$0c,$78,$18,$6b,$66,$66,$66,$66,$60
	dc.b	$70,$18,$66,$66,$6b,$3c,$66,$18,$78,$18,$1e,$4e,$00,$00,$24,$c3
	dc.b	$83,$c1,$ff,$a5,$bd,$8c,$0c,$0c,$0c,$6f,$1b,$79,$9e,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$7e,$ff,$38,$1c,$3e,$00,$18,$00
	dc.b	$ff,$06,$36,$de,$00,$18,$18,$3c,$18,$00,$00,$00,$30,$66,$18,$18
	dc.b	$0c,$6c,$06,$66,$18,$66,$06,$00,$00,$18,$7e,$18,$18
	dc.b	'n~f`f``ff'
	dc.b	$18,$06
	dc.b	'l`cnf|fl'
	dc.b	$0e,$18,$66,$66,$7f,$3c,$18,$30,$18,$18,$18,$00,$00,$00,$7e,$66
	dc.b	$60,$66,$7e,$18,$66,$66,$18,$0c,$7c,$18,$6b,$66,$66,$66,$66,$60
	dc.b	$3c,$18,$66,$66,$7f,$18,$66,$18,$1c,$18,$38,$00,$00,$00,$24,$66
	dc.b	$e6,$67,$ff,$99,$bd,$d8,$0c,$0c,$0c,$0c,$1e,$71,$8e,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$18,$66,$70,$0e,$1c,$00,$00,$00
	dc.b	$66,$7e,$66,$cc,$00,$18,$18,$66,$18,$18,$00,$18,$60,$66,$18,$30
	dc.b	$66,$7e,$06,$66,$30,$66,$0c,$18,$18,$0c,$00,$30,$18
	dc.b	'`ffff``ff'
	dc.b	$18
	dc.b	'ff`cnf`ff'
	dc.b	$06,$18,$66,$3c,$7f,$3c,$18,$60,$18,$0c,$18,$00,$00,$00,$66,$66
	dc.b	$60,$66,$60,$18,$7e,$66,$18,$0c,$6c,$18,$6b,$66,$66,$66,$66,$60
	dc.b	$0e,$18,$66,$3c,$7f,$3c,$7e,$30,$0c,$18,$30,$00,$00,$00,$24,$3c
	dc.b	$2c,$34,$ff,$81,$c3,$58,$0c,$0e,$0c,$0c,$1e,$71,$8e,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$70,$0e,$1c,$00,$00,$00
	dc.b	$66,$7c,$66,$cc,$00,$1c,$38,$66,$00,$18,$00,$18,$60,$66,$18,$30
	dc.b	$66,$7e,$66,$66,$30,$66,$0c,$18,$18,$0c,$00,$30,$00
	dc.b	'qfffn``ff'
	dc.b	$18
	dc.b	'ff`cff`jf'
	dc.b	$06,$18,$66,$3c,$77,$66,$18,$60,$18,$0c,$18,$00,$00,$00,$66,$66
	dc.b	$60,$66,$60,$18,$3e,$66,$18,$0c,$66,$18,$63,$66,$66,$7e,$7e,$60
	dc.b	$06,$18,$66,$3c,$77,$3c,$3e,$30,$0c,$18,$30,$00,$00,$00,$3c,$18
	dc.b	$38,$1c,$ff,$42,$c3,$70,$0c,$0c,$0c,$0c,$1b,$61,$86,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$1e,$3c,$e0,$07,$08,$00,$18,$00
	dc.b	$00,$18,$00,$fe,$00,$0c,$30,$00,$00,$18,$00,$18,$40,$7e,$7e,$7e
	dc.b	$7e,$0c,$7e,$7e,$30,$7e,$38,$18,$18,$06,$00,$60,$18
	dc.b	'?f~~|~`~f~~c~cf~`|c~'
	dc.w	$187e,$1863,$6618,$7e1e,$0678,$00ff,$007e,$7e7e
	dc.w	$7e7e,$1806,$663c
	dc.b	$0c
	dc.b	'g<cf~|>`~'
	dc.w	$1e7e,$1863,$6606,$7e0c,$1830,$0000,$0000,$0000
	dc.w	$00ff,$3ce7,$300c,$0c0c,$0c1b,$4182,$0000,$0000
	dc.w	$0000,$0000,$0000,$001e,$3ce0,$0708,$0018,$0000
	dc.w	$1800,$7600,$0660,$0000,$1800,$1840,$3c7e,$7e3c
	dc.w	$0c3c,$3c30,$3c38,$1818,$0600,$6018
	dc.b	$1e
	dc.b	'f|<x~`<f~<c~cf<`6c|'
	dc.w	$183c,$1841,$6618,$7e1e,$0678,$00ff,$003e,$7c3e
	dc.w	$3e3e,$1806,$663c,$0c63,$3c63,$663c,$6006,$607c
	dc.w	$0e3e,$1841,$6606,$7e0c,$1830,$0000,$0000,$0000
	dc.w	$00ff,$0000,$200c,$0c0c,$0c00,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$00c0,$0300,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$3000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0030,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	19,0
	dc.b	$7e,$00,$00,$7c,$00,$00,$00,$00,$00,$60,$06,$00,$00,$00,$00,$00
	dc.b	$00,$00,$7e,$00,$07,$18,$e0,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dcb.b	22,0
	dc.b	$c0,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00
	dcb.b	42,0
	dc.b	$7c,$00,$00,$78,$00,$00,$00,$00,$00,$60,$06,$00,$00,$00,$00,$00
	dc.b	$00,$00,$7c,$00,$00,$00,$00,$00,$00

;------------------------------------------------------------------------------
; leftover_mega_ste_data: $BBE2-$ED63 is not part of this program: nothing refers to it. It is
; a copy of the texts and tables of a Mega STE diagnostic cartridge build (from the end of its
; memory utility help text on: ROM, keyboard, MIDI, RS232, sound, timing, DMA, printer, RTC,
; SCSI, floppy, SCC and VME texts and its 8x8 and 8x16 fonts), left in the EPROM image past this
; program's end. Its pointers are that build's addresses, so they point at unrelated places here
; (and into this program's code). The rest of the 64K, $ED64-$FFFF, is $FF.
;------------------------------------------------------------------------------
leftover_mega_ste_data:
	dc.b	'address>',13,10,'RW (address)',13,10
	dc.b	'Address can be 1-6 hexadecimal digits',13,10
	dc.b	'Data can be 1-4 hexadecimal digits',13,10,13,10,'Examples:',13,10
	dc.b	'  W 200=3 writes 3 into location 200',13,10
	dc.b	'  W7000,7FFF=0 writes 0 into 7000-7FFF',13,10
	dc.b	'  W500=377 writes 0377 into 500 (word)',13,10
	dc.b	'  RW FF8200  reads a word from FF8200',13,10
	dc.b	'  R2000 3000 reads locations 2000 through 3000',13,10,0
	dc.b	'Testing Ram',13,10,0
	dc.b	'R0 RAM address=',0
	dc.b	'R1 RAM address=',0
	dc.b	'R2 RAM address=',0
	dc.b	'R3 RAM address=',0
	dc.b	'R4 RAM address=',0
	dc.b	' W:',0
	dc.b	' R:',0
	dc.b	'  bad bits: ',0
	dc.b	$2a,$00,$00,$00,$00,$10,$21,$20,$42,$30,$63,$40,$84,$50,$a5,$60
	dc.b	$c6,$70,$e7,$81,$08,$91,$29,$a1,$4a,$b1,$6b,$c1,$8c,$d1,$ad,$e1
	dc.b	$ce,$f1,$ef,$12,$31,$02,$10,$32,$73,$22,$52,$52,$b5,$42,$94,$72
	dc.b	$f7,$62,$d6,$93,$39,$83,$18,$b3,$7b,$a3,$5a,$d3,$bd,$c3,$9c,$f3
	dc.b	$ff,$e3,$de,$24,$62,$34,$43,$04,$20,$14,$01,$64,$e6,$74,$c7,$44
	dc.b	$a4,$54,$85,$a5,$6a,$b5,$4b,$85,$28,$95,$09,$e5,$ee,$f5,$cf,$c5
	dc.b	$ac,$d5,$8d,$36,$53,$26,$72,$16,$11,$06,$30,$76,$d7,$66,$f6,$56
	dc.b	$95,$46,$b4,$b7,$5b,$a7,$7a,$97,$19,$87,$38,$f7,$df,$e7,$fe,$d7
	dc.b	$9d,$c7,$bc,$48,$c4,$58,$e5,$68,$86,$78,$a7,$08,$40,$18,$61,$28
	dc.b	$02,$38,$23,$c9,$cc,$d9,$ed,$e9,$8e,$f9,$af,$89,$48,$99,$69,$a9
	dc.b	$0a,$b9,$2b,$5a,$f5,$4a,$d4,$7a,$b7,$6a,$96,$1a,$71,$0a,$50,$3a
	dc.b	$33,$2a,$12,$db,$fd,$cb,$dc,$fb,$bf,$eb,$9e,$9b,$79,$8b,$58,$bb
	dc.b	$3b,$ab,$1a,$6c,$a6,$7c,$87,$4c,$e4,$5c,$c5,$2c,$22,$3c,$03,$0c
	dc.b	$60,$1c,$41,$ed,$ae,$fd,$8f,$cd,$ec,$dd,$cd,$ad,$2a,$bd,$0b,$8d
	dc.b	$68,$9d,$49,$7e,$97,$6e,$b6,$5e,$d5,$4e,$f4,$3e,$13,$2e,$32,$1e
	dc.b	$51,$0e,$70,$ff,$9f,$ef,$be,$df,$dd,$cf,$fc,$bf,$1b,$af,$3a,$9f
	dc.b	$59,$8f,$78,$91,$88,$81,$a9,$b1,$ca,$a1,$eb,$d1,$0c,$c1,$2d,$f1
	dc.b	$4e,$e1,$6f,$10,$80,$00,$a1,$30,$c2,$20,$e3,$50,$04,$40,$25,$70
	dc.b	$46,$60,$67,$83,$b9,$93,$98,$a3,$fb,$b3,$da,$c3,$3d,$d3,$1c,$e3
	dc.b	$7f,$f3,$5e,$02,$b1,$12,$90,$22,$f3,$32,$d2,$42,$35,$52,$14,$62
	dc.b	$77,$72,$56,$b5,$ea,$a5,$cb,$95,$a8,$85,$89,$f5,$6e,$e5,$4f,$d5
	dc.b	$2c,$c5,$0d,$34,$e2,$24,$c3,$14,$a0,$04,$81,$74,$66,$64,$47,$54
	dc.b	$24,$44,$05,$a7,$db,$b7,$fa,$87,$99,$97,$b8,$e7,$5f,$f7,$7e,$c7
	dc.b	$1d,$d7,$3c,$26,$d3,$36,$f2,$06,$91,$16,$b0,$66,$57,$76,$76,$46
	dc.b	$15,$56,$34,$d9,$4c,$c9,$6d,$f9,$0e,$e9,$2f,$99,$c8,$89,$e9,$b9
	dc.b	$8a,$a9,$ab,$58,$44,$48,$65,$78,$06,$68,$27,$18,$c0,$08,$e1,$38
	dc.b	$82,$28,$a3,$cb,$7d,$db,$5c,$eb,$3f,$fb,$1e,$8b,$f9,$9b,$d8,$ab
	dc.b	$bb,$bb,$9a,$4a,$75,$5a,$54,$6a,$37,$7a,$16,$0a,$f1,$1a,$d0,$2a
	dc.b	$b3,$3a,$92,$fd,$2e,$ed,$0f,$dd,$6c,$cd,$4d,$bd,$aa,$ad,$8b,$9d
	dc.b	$e8,$8d,$c9,$7c,$26,$6c,$07,$5c,$64,$4c,$45,$3c,$a2,$2c,$83,$1c
	dc.b	$e0,$0c,$c1,$ef,$1f,$ff,$3e,$cf,$5d,$df,$7c,$af,$9b,$bf,$ba,$8f
	dc.b	$d9,$9f,$f8,$6e,$17,$7e,$36,$4e,$55,$5e,$74,$2e,$93,$3e,$b2,$0e
	dc.b	$d1,$1e,$f0
	dc.l	leftover_mega_ste_data+1216
	dc.l	leftover_mega_ste_data+1221
	dc.l	leftover_mega_ste_data+1229
	dc.l	leftover_mega_ste_data+1237
	dc.l	leftover_mega_ste_data+1241
	dc.l	leftover_mega_ste_data+1250
	dc.l	leftover_mega_ste_data+1259
	dc.l	leftover_mega_ste_data+1268
	dc.l	leftover_mega_ste_data+1282
	dc.l	leftover_mega_ste_data+1296
	dc.l	leftover_mega_ste_data+1305
	dc.l	leftover_mega_ste_data+1314
	dc.l	leftover_mega_ste_data+1325
	dc.l	leftover_mega_ste_data+1333
	dc.l	leftover_mega_ste_data+1341
	dc.l	leftover_mega_ste_data+1348
	dc.b	'ROM checksum/crc test',13,10,0
	dc.b	'Version ',0
	dc.b	13,10,'ROM                     ',9,'u601',9,'u602',9,'u603',9,'u604',13
	dc.b	10,0
	dc.b	'Calculated ROM checksums',9,0
	dc.b	'Calculated ROM CRCs     ',9,0
	dc.b	'CRC  mismatch  in   u60',0
	dc.w	$3109
	dc.b	$00
	dc.b	'2',9,9,'     ',0
	dc.b	'3',9,9,9,9,'    ',0
	dc.b	'4',9,9,9,9,9,9,'   ',0
	dc.b	'PAL',13,10,0
	dc.b	'NTSC',13,10,0
	dc.b	'USA ',0
	dc.b	'German ',0
	dc.b	'French ',0
	dc.b	'UK ',0
	dc.b	'Spanish ',0
	dc.b	'Italian ',0
	dc.b	'Swedish ',0
	dc.b	'Swiss French ',0
	dc.b	'Swiss German ',0
	dc.b	'Turkish ',0
	dc.b	'Finnish ',0
	dc.b	'Norwegian ',0
	dc.b	'Danish ',0
	dc.b	'Arabic ',0
	dc.b	'Dutch ',0
	dc.b	'Unassigned country code ',0
	dc.b	'New version number ',0
	dc.b	'No color--Monochrome monitor',0
	dc.w	$003b,$0600,$07fe,$0810,$0d03,$0b80,$0c01,$0000
	dc.w	$0506,$0706,$0906,$0b06,$0d06,$0f06,$1106,$1306
	dc.w	$1506,$1706,$1906,$1b06,$1d06,$2106,$0508,$0808
	dc.w	$0a08,$0c08,$0e08,$1008,$1208,$1408,$1608,$1808
	dc.w	$1a08,$1c08,$1e08,$2008,$050a,$090a,$0b0a,$0d0a
	dc.w	$0f0a,$110a,$130a,$150a,$170a,$190a,$1b0a,$1d0a
	dc.w	$1f06,$050c,$220a,$0a0c,$0c0c,$0e0c,$100c,$120c
	dc.w	$140c,$160c,$180c,$1a0c,$1c0c,$1e0c,$0000,$070e
	dc.w	$0b0e,$1d0e,$0604,$0904,$0c04,$0f04,$1204,$1504
	dc.w	$1804,$1b04,$1e04,$2104,$0000,$0000,$2a08,$2808
	dc.w	$0000,$3408,$260a,$0000
	dc.b	'*',10,'4',10,0
	dc.b	$00,$28,$0a,$00,$00,$26,$08,$22,$08,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$08,$0c,$29,$06,$26,$06,$2e,$06,$30,$06,$32,$06,$34,$06,$2e
	dc.b	$08,$30,$08,$32,$08,$2e,$0a,$30,$0a,$32,$0a,$2e,$0c,$30,$0c,$32
	dc.b	$0c,$2e,$0e,$32,$0e,$34,$0c,$00,$00,$00,$00
	dc.l	leftover_mega_ste_data+2126
	dc.l	leftover_mega_ste_data+2128
	dc.l	leftover_mega_ste_data+2130
	dc.l	leftover_mega_ste_data+2132
	dc.l	leftover_mega_ste_data+2134
	dc.l	leftover_mega_ste_data+2136
	dc.l	leftover_mega_ste_data+2138
	dc.l	leftover_mega_ste_data+2140
	dc.l	leftover_mega_ste_data+2142
	dc.l	leftover_mega_ste_data+2144
	dc.l	leftover_mega_ste_data+2146
	dc.l	leftover_mega_ste_data+2148
	dc.l	leftover_mega_ste_data+2152
	dc.l	leftover_mega_ste_data+2154
	dc.l	leftover_mega_ste_data+2157
	dc.l	leftover_mega_ste_data+2160
	dc.l	leftover_mega_ste_data+2162
	dc.l	leftover_mega_ste_data+2164
	dc.l	leftover_mega_ste_data+2166
	dc.l	leftover_mega_ste_data+2168
	dc.l	leftover_mega_ste_data+2170
	dc.l	leftover_mega_ste_data+2172
	dc.l	leftover_mega_ste_data+2174
	dc.l	leftover_mega_ste_data+2176
	dc.l	leftover_mega_ste_data+2178
	dc.l	leftover_mega_ste_data+2180
	dc.l	leftover_mega_ste_data+2182
	dc.l	leftover_mega_ste_data+2184
	dc.l	leftover_mega_ste_data+2194
	dc.l	leftover_mega_ste_data+2198
	dc.l	leftover_mega_ste_data+2200
	dc.l	leftover_mega_ste_data+2202
	dc.l	leftover_mega_ste_data+2204
	dc.l	leftover_mega_ste_data+2206
	dc.l	leftover_mega_ste_data+2208
	dc.l	leftover_mega_ste_data+2210
	dc.l	leftover_mega_ste_data+2212
	dc.l	leftover_mega_ste_data+2214
	dc.l	leftover_mega_ste_data+2216
	dc.l	leftover_mega_ste_data+2218
	dc.l	leftover_mega_ste_data+2220
	dc.l	leftover_mega_ste_data+2222
	dc.l	leftover_mega_ste_data+2227
	dc.l	leftover_mega_ste_data+2229
	dc.l	leftover_mega_ste_data+2231
	dc.l	leftover_mega_ste_data+2233
	dc.l	leftover_mega_ste_data+2235
	dc.l	leftover_mega_ste_data+2237
	dc.l	leftover_mega_ste_data+2239
	dc.l	leftover_mega_ste_data+2241
	dc.l	leftover_mega_ste_data+2243
	dc.l	leftover_mega_ste_data+2245
	dc.l	leftover_mega_ste_data+2247
	dc.l	leftover_mega_ste_data+2249
	dc.w	$0000,$0000
	dc.l	leftover_mega_ste_data+2252
	dc.l	leftover_mega_ste_data+2255
	dc.l	leftover_mega_ste_data+2273
	dc.l	leftover_mega_ste_data+2276
	dc.l	leftover_mega_ste_data+2279
	dc.l	leftover_mega_ste_data+2282
	dc.l	leftover_mega_ste_data+2285
	dc.l	leftover_mega_ste_data+2288
	dc.l	leftover_mega_ste_data+2291
	dc.l	leftover_mega_ste_data+2294
	dc.l	leftover_mega_ste_data+2297
	dc.l	leftover_mega_ste_data+2300
	dc.l	leftover_mega_ste_data+2303
	dc.w	$0000,$0000,$0000,$0000
	dc.l	leftover_mega_ste_data+2307
	dc.l	leftover_mega_ste_data+2309
	dc.w	$0000,$0000
	dc.l	leftover_mega_ste_data+2148
	dc.l	leftover_mega_ste_data+2311
	dc.w	$0000,$0000
	dc.l	leftover_mega_ste_data+2313
	dc.l	leftover_mega_ste_data+2150
	dc.w	$0000,$0000
	dc.l	leftover_mega_ste_data+2315
	dc.w	$0000,$0000
	dc.l	leftover_mega_ste_data+2317
	dc.l	leftover_mega_ste_data+2319
	dcb.b	48,0
	dc.l	leftover_mega_ste_data+2321
	dc.l	leftover_mega_ste_data+2323
	dc.l	leftover_mega_ste_data+2326
	dc.l	leftover_mega_ste_data+2329
	dc.l	leftover_mega_ste_data+2331
	dc.l	leftover_mega_ste_data+2247
	dc.l	leftover_mega_ste_data+2333
	dc.l	leftover_mega_ste_data+2140
	dc.l	leftover_mega_ste_data+2142
	dc.l	leftover_mega_ste_data+2144
	dc.l	leftover_mega_ste_data+2134
	dc.l	leftover_mega_ste_data+2136
	dc.l	leftover_mega_ste_data+2138
	dc.l	leftover_mega_ste_data+2128
	dc.l	leftover_mega_ste_data+2130
	dc.l	leftover_mega_ste_data+2132
	dc.l	leftover_mega_ste_data+2335
	dc.l	leftover_mega_ste_data+2245
	dc.l	leftover_mega_ste_data+2339
	dc.w	$1b00,$3100,$3200,$3300,$3400,$3500,$3600,$3700
	dc.w	$3800,$3900,$3000,$2d00,$2b00,$3d00,$4253,$0054
	dc.w	$4200,$5100,$5700,$4500,$5200,$5400,$5900,$5500
	dc.w	$4900,$4f00,$5000,$5b00,$5d00,$200a,$0820,$0a08
	dc.w	$0852,$5400
	dc.b	'CTL',0
	dc.w	$4100,$5300,$4400,$4600,$4700,$4800,$4a00,$4b00
	dc.w	$4c00,$3b00,$2700,$6000
	dc.b	' SH ',0
	dc.b	$5c,$00,$5a,$00,$58,$00,$43,$00,$56,$00,$42,$00,$4e,$00,$4d,$00
	dc.b	$2c,$00,$2e,$00,$2f,$00,$53,$48,$00,$41,$4c,$00
	dc.b	'      SPACE      ',0
	dc.b	$43,$4c,$00,$46,$31,$00,$46,$32,$00,$46,$33,$00,$46,$34,$00,$46
	dc.b	$35,$00,$46,$36,$00,$46,$37,$00,$46,$38,$00,$46,$39,$00
	dc.b	'F10',0
	dc.b	$48,$00,$01,$00,$04,$00,$03,$00,$02,$00,$49,$00,$44,$00,$20,$00
	dc.b	$55,$4e,$00,$48,$50,$00,$28,$00,$29,$00,$2a,$00
	dc.b	'0  ',0
	dc.b	$45,$0a,$08,$20,$0a,$08,$20,$00,$23,$00
	dc.b	'Keyboard test',0
	dc.b	'MOUSE',0
	dc.b	$52,$54,$00
	dc.b	'ENTER',0
	dc.b	'SPACE',0
	dc.b	13,10,'K0 Stuck key: ',0
	dc.b	13,10,'K1 Keyboard not responding',13,10,0
	dc.b	13,10,'K2 Keyboard status error',13,10,0
	dc.b	9,'European keyboard (U.K. keytops shown)',13,10,9
	dc.b	'Press keys and watch screen to verify closure',13,10,0
	dc.b	9,'U.S. keyboard',13,10,9
	dc.b	'Press keys and watch screen to verify closure',13,10,0
	dc.b	9,'Hit shift Esc to exit',0
	dc.b	$00,$00,$00,$09,$68,$00,$80,$00,$00,$00,$00,$00,$10,$00,$30,$00
	dc.b	$00,$09,$e8,$00,$80,$00,$00,$00,$00,$00,$20,$00,$60,$00,$00
	dc.b	'Testing MIDI',13,10,0
	dc.b	'M4 MIDI data overrun',13,10,0
	dc.b	'M3 MIDI parity',13,10,0
	dc.b	'M2 MIDI framing',13,10,0
	dc.b	'M1 MIDI data mismatch',13,10,0
	dc.b	'M0 MIDI not received',13,10,0
	dc.w	$0102,$0408,$1020,$4000
	dc.l	leftover_mega_ste_data+3184
	dc.l	leftover_mega_ste_data+3166
	dc.l	leftover_mega_ste_data+3147
	dc.l	leftover_mega_ste_data+3122
	dc.l	leftover_mega_ste_data+3098
	dc.l	leftover_mega_ste_data+3208
	dc.l	leftover_mega_ste_data+3257
	dc.l	leftover_mega_ste_data+3293
	dc.l	leftover_mega_ste_data+3328
	dc.l	leftover_mega_ste_data+3360
	dc.l	leftover_mega_ste_data+3393
	dc.l	leftover_mega_ste_data+3223
	dc.l	leftover_mega_ste_data+3426
	dc.w	$0102,$0408,$1020,$4000
	dc.l	leftover_mega_ste_data+2886
	dc.l	leftover_mega_ste_data+2896
	dc.l	leftover_mega_ste_data+2906
	dc.l	leftover_mega_ste_data+2916
	dc.l	leftover_mega_ste_data+2926
	dc.l	leftover_mega_ste_data+2936
	dc.l	leftover_mega_ste_data+2946
	dc.b	'19.2k bps',0
	dc.b	'9600 bps ',0
	dc.b	'4800 bps ',0
	dc.b	'2400 bps ',0
	dc.b	'1200 bps ',0
	dc.b	'600 bps  ',0
	dc.b	'300 bps  ',0
	dc.b	'No loopback connector',13,10,0
	dc.w	$55aa,$00ff,$e5d1
	dc.b	$00
	dc.b	'Testing RS232 loopback',13,10,0
	dc.b	'Hold down button (or remove loopback), and press key.',13,10
	dc.b	'Press ESC to skip this test.',13,10,0
	dc.b	'S0 RS232 not received',13,10,0
	dc.b	'S1 RS232 data mismatch',13,10,0
	dc.b	'S2 RS232 framing',13,10,0
	dc.b	'S3 RS232 parity',13,10,0
	dc.b	'S4 RS232 data overrun',13,10,0
	dc.b	'S5 RS232 IRQ',13,10,0
	dc.b	'S6 RS232 transmit error (68901)',13,10,0
	dc.b	'S7 RS232 Transmit error interrupt',13,10,0
	dc.b	'S8 RS232 Receive error interrupt',13,10,0
	dc.b	'S9 RS232 RI-DTR not connected',13,10,0
	dc.b	'SA RS232 DCD-DTR not connected',13,10,0
	dc.b	'SB RS232 RTS-CTS not connected',13,10,0
	dc.b	'SC RS232 input shorted to output',13,10,0
	dc.b	$00,$00,$04,$00,$00,$00,$00,$03,$20,$00,$83,$00,$04,$00,$34,$00
	dc.b	$00,$03,$20,$00,$02,$00,$04,$00,$98,$00,$00,$0b,$b8,$00,$83,$00
	dc.b	$04,$00,$a4,$00,$00,$00,$0a,$00,$80,$00,$04,$01,$20,$00,$00,$00
	dc.b	$0a,$00,$81,$00,$00,$00,$30,$00,$11
	dc.b	'!1@MZent{~'
	dc.b	$7f
	dc.b	'~{tneZM@1!'
	dc.b	$11,$00,$ef,$df,$cf,$c0,$b3,$a6,$9c,$92,$8c,$85,$82,$81,$82,$85
	dc.b	$8b,$92,$9b,$a6,$b3,$c0,$cf,$df,$ef,$00,$00,$00,$60,$00,$00,$10
	dc.b	'!!?1Z?nM{Z'
	dc.b	$7f
	dc.b	'e{nnuZ{?}!'
	dc.w	$7f00,$7edf,$7cc1,$75a6,$6e92,$6585,$5a80,$4d85
	dc.w	$3f92,$31a6,$21c1,$10df,$0000,$f021,$df3f,$cf5a
	dc.w	$c16e,$b37b,$a67f,$9b7b,$926e,$8b5a,$853f,$8321
	dc.w	$8000,$82df,$84c1,$89a6,$9192,$9c85,$a680,$b385
	dc.w	$c192,$cca6,$dfc1,$f0df,$0000,$0008,$7f7f,$8080
	dc.w	$7f7f,$8080,$0000,$0078,$0007,$0d14
	dc.b	$1a
	dc.b	'!',$27,'-4:?EKPUZ^cgknqtvy{|}~~'
	dc.w	$7f7f
	dc.b	'~}|{yvtqnkgc^ZUPKE?:4-',$27,'!'
	dc.w	$1a14,$0d07,$00f9,$f3ec,$e6df,$d9d3,$ccc6,$c1bb
	dc.w	$b5b0,$aba6,$a29d,$9995,$928f,$8c8a,$8785,$8382
	dc.w	$8181,$8080,$8182,$8384,$8587,$8a8c,$9295,$999d
	dc.w	$a2a6,$abb0,$b5bb,$c1c6,$ccd3,$d9df,$e6ec,$f3f9
	dc.w	$0000,$00f0,$0003,$070a,$0d11,$1417,$1a1e
	dc.b	'!$',$27,'*-047:=?AEHKMPSUXZ\^`ceghkmnpqrtuvwxyzz{{||}}~~'
	dc.w	$7f7f
	dc.b	'~~}}||{{yxwvutrqponmkhgec`^\ZXUSPMKHEA?=:740-*',$27,'$!'
	dc.b	$1e,$1a,$17,$14,$11,$0d,$0a,$07,$03,$00,$fd,$f9,$f6,$f3,$ef,$ec
	dc.b	$e9,$e6,$e2,$df,$dc,$d9,$d6,$d3,$d0,$cc,$c9,$c6,$c3,$c1,$bf,$bb
	dc.b	$b8,$b5,$b3,$b0,$ad,$ab,$a8,$a6,$a4,$a2,$a0,$9d,$9b,$99,$98,$95
	dc.b	$93,$92,$90,$8f,$8e,$8c,$8b,$8a,$89,$88,$87,$86,$86,$85,$85,$84
	dc.b	$84,$83,$83,$82,$82,$81,$81,$82,$82,$83,$83,$84,$84,$85,$85,$87
	dc.b	$88,$89,$8a,$8b,$8c,$8e,$8f,$90,$91,$92,$93,$95,$98,$99,$9b,$9d
	dc.b	$a0,$a2,$a4,$a6,$a8,$ab,$ad,$b0,$b3,$b5,$b8,$bb,$bf,$c1,$c3,$c6
	dc.b	$c9,$cc,$d0,$d3,$d6,$d9,$dc,$df,$e2,$e6,$e9,$ec,$ef,$f3,$f6,$f9
	dc.b	$fd,$fe,$fd,$fb,$00,$02,$04,$08,$09,$0a,$00,$00,$c0,$00,$d0,$00
	dc.b	$d8,$00,$e0,$00,$e4,$00,$e8,$00,$e8,$00,$e8,$01,$40,$01,$48,$01
	dc.b	$4a,$01,$4c,$01,$50,$01,$54,$01,$54,$01,$54,$01,$14,$01,$14,$01
	dc.b	$14,$01,$10,$01,$0c,$01,$0a,$01,$08,$01,$00,$00,$07,$00,$07,$00
	dc.b	$07,$00,$07,$00,$06,$00,$05,$00,$04,$00,$03,$00,$02,$00,$01,$00
	dc.b	$06,$00,$06,$00,$06,$00,$06,$00,$06,$00,$05,$00,$04,$00,$03,$00
	dc.b	$02,$00,$01
	dc.b	'Listen for low to high sweep:',13,10,0
	dc.l	leftover_mega_ste_data+4186
	dc.l	leftover_mega_ste_data+4196
	dc.l	leftover_mega_ste_data+4206
	dc.b	'Channel A',0
	dc.b	'Channel B',0
	dc.b	'Channel C',0
	dc.b	'Testing DMA sound. Check waveforms with oscilloscope.',13,10,0
	dc.b	'DMA sound timed-out',13,10,0
	dc.b	'Mono 1 kHz tone',13,10,0
	dc.b	'Stereo 1 kHz/500 Hz tones',13,10,0
	dc.b	'Bass attenuation',13,10,0
	dc.b	'Treble attenuation',13,10,0
	dc.b	'MCU msb (7) never set',13,10,0
	dc.b	'wait states never turned off',13,10,0
	dc.b	'checksums do not match',13,10,0
	dc.b	'Testing MFP, Glue timing, Video',13,10,0
	dc.b	13,10,'Wait states on ',0
	dc.b	'Wait states off   ',0
	dc.b	'Read time for ROM  =  ',0
	dc.b	13,10,'T0 MFP timer',13,10,0
	dc.b	13,10,'T1 Vertical Sync',13,10,0
	dc.b	13,10,'T2 Horizontal Sync',13,10,0
	dc.b	13,10,'T3 Display Enable',13,10,0
	dc.b	13,10,'T4 Video Counter in Memory Controller ',13,10,0
	dc.b	'T5 PSG Bus Test ',9,0
	dc.b	'T6 1772 Bus Test',9,0
	dc.w	$0020,$0040,$0080,$0100,$0200,$0300,$0400,$0500
	dc.w	$0600,$0700,$0800,$1000,$2000,$3000,$4000,$0000
	dc.w	$1000,$0000,$1800,$0000,$2000,$0000,$4000,$0000
	dc.w	$8000,$0001,$8000,$0002,$0000,$0004,$0000,$0005
	dc.w	$0000,$0006,$0000,$0007,$0000,$0008,$0000,$0009
	dc.w	$0000,$000a,$0000,$000b,$0000,$000c,$0000,$000d
	dc.w	$0000,$000e,$0000,$000f,$0000
	dc.b	'DMA Port Test',13,10,0
	dc.b	'D0 DMA time-out',13,10,0
	dc.b	'D1 DMA count error',13,10,0
	dc.b	'D2 DMA data mismatch',13,10,0
	dc.b	'D3 DMA not responding',13,10,0
	dc.w	$f8f9,$fafb,$fcfd,$feff,$0102,$0408,$1020,$4080
	dc.b	'Printer/Joystick Port test',13,10,0
	dc.b	'P0 Printer port error ',0
	dc.b	'P1 Busy line error',13,10,0
	dc.b	'J4 Right button line error',13,10,0
	dc.b	'J3 Left button line error',13,10,0
	dc.b	'J0 Joystick Port 0 error',13,10,0
	dc.b	'J1 Joystick Port 1 error',13,10,0
	dc.b	'J2 Joystick time-out',13,10,0
	dc.b	'HIGH RESOLUTION TEST NOT IMPLAMENTED AT THIS TIME',13,10,0
	dc.b	'Connect monochrome monitor',13,10,0
	dc.b	'Disconnect monochrome monitor',13,10,0
	dc.b	'Press any key to return to menu',13,10,0
	dc.w	$0002,$0406,$0708,$0901,$0305,$0210,$0289,$5959
	dc.w	$2307,$3112,$9900,$0000,$0101,$0100,$5959,$2301
	dc.w	$0902,$8900,$0000,$0210,$0289,$0100,$0002,$1002
	dc.w	$8900
	dc.l	leftover_mega_ste_data+5356
	dc.l	leftover_mega_ste_data+5372
	dc.l	leftover_mega_ste_data+5394
	dc.b	'RTC RAM error',13,10,0
	dc.b	'RTC time/date error',13,10,0
	dc.b	'RTC alarm error',13,10,0
	dc.b	'Testing RTC',13,10,0
	dc.b	'ERROR  - SCSI STATUS CODE -  ',0
	dc.b	'ERROR  - CANNOT SELECT SCSI DISK -  ',0
	dc.b	'ERROR DMA MODE -DMAC HAS ZERO COUNT-MFP2 SEES NO INTERRUPTS- ',0
	dc.b	'ERROR DMA MODE -DMAC HAS ZERO COUNT-MFP2 SEES DMAC IRQ- ',0
	dc.b	'ERROR DMA MODE -DMAC HAS ZERO COUNT-MFP2 SEES SCSI IRQ- ',0
	dc.b	'ERROR DMA MODE -DMAC HAS NOT COUNTED TO ZERO-MFP2 SEES BOTH SCSI'
	dc.b	' AND DMAC INTERRUPTS- ',0
	dc.b	'ERROR DMA MODE -DMAC HAS NOT COUNTED TO ZERO-MFP2 SEES DMAC INTE'
	dc.b	'RRUPT- ',0
	dc.b	'ERROR DMA MODE -DMAC HAS NOT COUNTED TO ZERO-MFP2 SEES SCSI INTE'
	dc.b	'RRUPT- ',0
	dc.b	'ERROR DMA MODE -DMAC HAS NOT CLEARED COUNT ZERO- ',0
	dc.b	'ERROR DMA MODE -5380 OR SCSI DISK IS NOT RESPONDING- ',0
	dc.b	'ERROR DMA MODE -BUS ERROR- ',0
	dc.b	'ERROR DMA MODE -READ AND WRITE BUFFERS DO NOT COMPARE- ',0
	dc.b	'ERROR PRG MODE -READ AND WRITE BUFFERS DO NOT COMPARE- ',0
	dc.b	13,10,'TESTING SCSI DRIVE ZERO',13,10
	dc.b	'READING/WRITING  TO ON BOARD ST RAM',13,10,0
	dc.b	13,10,10,'TESTING SCSI DRIVE ONE',13,10
	dc.b	'READING/WRITING  TO ON BOARD ST RAM',13,10,0
	dc.b	'READING/WRITING TO EXPANSION ST RAM',13,10,0
	dc.b	'READING/WRITING TO EXPANSION TT RAM',13,10,0
	dc.w	$004f,$2e20,$010a,$3c16,$432c,$3b2d,$1121,$2f14
	dc.w	$4a15,$4244,$1248,$3847,$1049,$0422,$451b,$3a39
	dc.w	$0646,$2730,$3508,$4b4c,$1c1d,$264d,$1709,$2841
	dc.w	$1a3d,$4e25,$0c34,$1331,$0e0f,$3623,$241e,$0d05
	dc.w	$3307,$3f19,$373e,$0b40,$2a29,$1832,$1f2b,$0302
	dc.w	$0001,$4f00
	dc.b	$27,'O',9,'Floppy disk drive routines:',13,10,9
	dc.b	'(WARNING--all choices except 2,6,7 write to the disk)',13,10,9
	dc.b	'1 Quick Test',13,10,9,'2 Read Alignment Disk',13,10,9
	dc.b	'3 Disk Interchange Test',13,10,9,'4 Disk Exerciser',13,10,9
	dc.b	'5 Check copy protect tracks (80-82)',13,10,9,'6 Test Speed',13,10,9
	dc.b	'7 Install disk drives',13,10,0
	dc.b	'1  Single sided',13,10,'2  Double sided',13,10,'3  High Density',13,10
	dc.b	'Any other key will de-install this drive.',13,10,0
	dc.b	'Enter track number (if none entered, default=40): ',0
	dc.b	'Select single sided (1) or double sided (2)',13,10,0
	dc.b	'Read analog alignment disk',13,10,'Disk A or B?',13,10,0
	dc.b	'Disk Exerciser',13,10,0
	dc.b	'Disk interchange test',13,10
	dc.b	'Insert disks in both drives, hit any key to start',13,10,0
	dc.b	'Swap disks A and B, Hit any key when ready',13,13,10,0
	dc.b	'Disks were not swapped!',13,10,0
	dc.b	'Hit esc to quit, any other key to repeat',13,10,0
	dc.b	'Checking drive type...',13,10,0
	dc.b	'Disk A: ',0
	dc.b	'Disk B: ',0
	dc.b	'Cannot write drive A',13,10,0
	dc.b	'Cannot write drive B',13,10,0
	dc.b	'High Density ',13,10,0
	dc.b	'SS ',13,10,0
	dc.b	'DS ',13,10,0
	dc.b	'No floppies ',13,10,0
	dc.b	'Sector ',0
	dc.b	'Track ',0
	dc.b	'Side ',0
	dc.b	'Formatting ',0
	dc.b	'Writing    ',0
	dc.b	'Reading    ',0
	dc.b	'Check Tracks 80-82',13,10,0
	dc.b	'Copy protect tracks PASS                         ',13,10,0
	dc.b	'Copy protect tracks FAIL                         ',13,10,0
	dc.b	'Floppy disk speed test',13,10,0
	dc.b	'Testing speed',9,'Allowable range = 196 - 204 milliseconds/revolution'
	dc.b	13,10,0
	dc.b	'Time-out waiting for index',13,10,0
	dc.b	'Max      Min      Current speed',0
	dc.b	'Soft Error',13,10,0
	dc.b	'Bad Sector: ',0
	dc.b	'F0 Not selected ',0
	dc.b	'Side 0 ',0
	dc.b	'Side 1 ',0
	dc.b	'Error formating ',0
	dc.b	'Error writing',13,10,0
	dc.b	'Error reading',13,10,0
	dc.b	'F4 Seek error ',0
	dc.b	'F5 Write Protected ',0
	dc.b	'F6 Read compare error ',0
	dc.b	'F7 DMA error ',0
	dc.b	'F8 DMA count error ',0
	dc.b	'F9 CRC error ',0
	dc.b	'FA Record not found ',0
	dc.b	'FB Lost data ',0
	dc.b	'FC Side select error--single sided drive',13,10,0
	dc.b	'FD Drive not ready ',0
	dc.b	'Stopped. ESC to quit, any other key to continue.',0
	dc.b	'Hard error',13,10,0
	dc.b	'Fail ',0
	dc.w	$0000

;------------------------------------------------------------------------------
; leftover_mste_scc_vectors: the Mega STE build's SCC vector table (8 longs, then its SCC error
; text pointers), part of the leftover data and read by nothing. The longs point at $7A36,
; $7A42, $7AF4 and $7B20 in this code and into the middle of instructions at $7AA4, $7AB0, $7AEA.
;------------------------------------------------------------------------------
leftover_mste_scc_vectors:
	dc.w	$00fa,$7a42,$00fa,$7af4,$00fa,$7ab0,$00fa,$7b20 ; unused
	dc.w	$00fa,$7a36,$00fa,$7aea,$00fa,$7aa4,$00fa,$7b20
	dc.l	leftover_mega_ste_data+8324
	dc.l	leftover_mega_ste_data+8347
	dc.l	leftover_mega_ste_data+8193
	dc.l	leftover_mega_ste_data+8193
	dc.l	leftover_mega_ste_data+8393
	dc.l	leftover_mega_ste_data+8367
	dc.l	leftover_mega_ste_data+8377
	dc.l	leftover_mega_ste_data+8408
	dc.l	leftover_mega_ste_data+8510
	dc.l	leftover_mega_ste_data+8519
	dc.l	leftover_mega_ste_data+8528
	dc.l	leftover_mega_ste_data+8193
	dc.l	leftover_mega_ste_data+8193
	dc.l	leftover_mega_ste_data+8193
	dc.l	leftover_mega_ste_data+8193
	dc.l	leftover_mega_ste_data+8193
	dc.l	leftover_mega_ste_data+8324
	dc.l	leftover_mega_ste_data+8347
	dc.l	leftover_mega_ste_data+8153
	dc.l	leftover_mega_ste_data+8174
	dc.l	leftover_mega_ste_data+8393
	dc.l	leftover_mega_ste_data+8367
	dc.l	leftover_mega_ste_data+8377
	dc.l	leftover_mega_ste_data+8408
	dc.b	'Testing SCC',13,10,0
	dc.b	'SCC DMA output:',13,10,0
	dc.b	'SCC DMA input:',13,10,0
	dc.b	'Non-zero DMA count',13,10,0
	dc.b	'DMA Bus Error',13,10,0
	dc.w	$0d0a
	dc.b	$00
	dc.b	'bad index--programming error',13,10,0
	dc.b	'SCC A internal loopback: ',13,10,0
	dc.b	'SCC B internal loopback: ',13,10,0
	dc.b	'Port A async mode: ',13,10,0
	dc.b	'Port B async mode: ',13,10,0
	dc.b	'Transmitter time-out',13,10,0
	dc.b	'Receiver time-out',13,10,0
	dc.b	'Overrun',13,10,0
	dc.b	'Framing error',13,10,0
	dc.b	'Parity error',13,10,0
	dc.b	'Data compare error',13,10,0
	dc.b	'Port A modem control error: ',0
	dc.b	'Port B modem control error: ',0
	dc.b	'SCC interrupt error:',13,10,0
	dc.b	'DTR-DCD ',0
	dc.b	'DTR-DSR ',0
	dc.b	'RTS-CTS ',0
	dc.b	'Port A has no loopback connector',13,10,0
	dc.b	'Port B has no loopback connector',13,10,0
	dc.b	'LAN has no loopback connector',13,10,0
	dc.b	'SCC test done',13,10,0
	dc.b	'No Tx interrupt',13,10,0
	dc.b	'No Rx interrupt',13,10,0
	dc.b	'LAN ERROR: DCD IS ACTIVE WITHOUT RTS ON',13,10,0
	dc.b	'LAN ERROR: RTS IS ACTIVE BUT DCD IS NOT RESPONDING',13,10,0
	dc.b	'NOT ABLE TO CLEAR D  PORT REGISTERS',13,10,0
	dc.b	'Transmitter time out on D port',13,10,0
	dc.b	'Port D has no loopback connecter',13,10,0
	dc.b	'RECEIVE STATUS ERROR ON D PORT',13,10,0
	dc.b	'DATA COMPARE ERROR ON D PORT',13,10,0
	dc.w	$0444,$03c0,$0560,$0900,$0a00,$0b50,$0c18,$0d00
	dc.w	$0e02,$0e03,$03c1,$0568,$0f00,$0444,$03c0,$0570
	dc.w	$0900,$0a00,$0b50,$0c18,$0d00,$0e02,$0e03,$03c1
	dc.w	$0578,$0f00,$0444,$03c0,$05e2,$0900,$0a00,$0b50
	dc.w	$0c18,$0d00,$0e02,$0e03,$03c1,$05ea,$0f00,$0444
	dc.w	$0140,$03c0,$0560,$0900,$0a00,$0b50,$0c18,$0d00
	dc.w	$0e02,$0e03,$03c1,$0568,$0f00
	dc.l	test_routines+12
	dc.l	test_routines+28
	dc.l	ram_size_codes+2
	dc.l	test_routines+44
	dc.l	msg_title+41
	dc.l	msg_title+55
	dc.l	msg_date+6
	dc.l	msg_date
	dcb.b	26,0
	dc.w	$2000,$0000,$0000
	dc.b	'Generate VMEbus Interrupts using a Xycom SCC Card',13,10,0
	dc.b	' initializing 8530s',13,10,0
	dc.b	' interrupt vectors established',13,10,0
	dc.b	' 8530 in loopback mode',13,10,0
	dc.b	' interrupt vector set to 0x',0
	dc.b	' enable level 6 VME interrupts',13,10,0
	dc.b	'Pass: 0x',0
	dc.b	'VME RAM test ',13,10,0
	dc.b	13,10,10,10,9,9,'To complete this test',13,10,9,9,9
	dc.b	'1.) Power down the system',13,10,9,9,9
	dc.b	'2.) Install the other VME test PCB',13,10,9,9,9
	dc.b	'3.) Power the system up and the test will continue',13,10,0
	dc.b	13,10,10,10,9,9,'This ends the VME tests',13,10,0
	dc.b	'No VME board found in system',13,10,0
	dc.b	$04,$44,$03,$c0,$05,$e2,$01,$44,$06,$00,$07,$00,$09,$00,$0a,$00
	dc.b	$0b,$56,$0c,$04,$0d,$00,$0e,$02,$0e,$03,$03,$c1,$05,$ea,$0f,$00
	dc.b	$00,$10,$00,$10,$09,$00,$01,$00,$00,$00,$18,$3c,$18,$18,$ff,$3c
	dc.b	$e7,$01,$d8,$c0,$cc,$f8,$f0,$0d,$b0,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$78,$00,$03,$c0,$48,$00,$00,$00,$00,$18,$00,$1c
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$06,$00,$60,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dcb.b	36,0
	dc.b	$0e,$18,$70,$00,$10,$00,$3c,$24,$1c,$38,$ff,$42,$c3,$03,$d8,$c0
	dc.b	$cc,$c0,$c0,$0d,$b0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$36
	dc.b	$60,$1c,$07,$e0,$92,$00,$18,$66,$66,$3e,$66,$36,$18,$0e,$70,$66
	dc.b	$18,$00,$00,$00,$06,$3c,$18,$3c,$7e,$0c
	dc.b	'~<~<<',0
	dc.b	$00,$0c,$00,$30,$3c,$3c,$18
	dc.b	'|<x~~>f~'
	dc.b	$06
	dc.b	'f`cf<|<|<~ffcff~'
	dc.b	$1e,$40,$78,$08,$00,$c0,$00,$60,$00,$06,$00,$0e,$00,$60,$18,$06
	dc.b	$60,$38,$00,$00,$00,$00,$00,$00,$00,$18,$00,$00,$00,$00,$00,$00
	dc.b	$18,$18,$18,$30,$18,$00,$66,$24,$f6,$6f,$ff,$99,$a5,$06,$f8,$de
	dc.b	$78,$fe,$df,$0d,$b0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7f
	dc.b	$78,$1c,$0e,$70,$24,$00,$18,$66,$ff,$60,$6c,$1c,$18,$1c,$38,$3c
	dc.b	$18,$00,$00,$00,$0c,$66,$38,$66,$0c,$1c,$60,$60,$06,$66,$66,$18
	dc.b	$18,$18,$7e,$18
	dc.b	'ff<ffl```f'
	dc.b	$18,$06
	dc.b	'l`wvffff`'
	dc.w	$1866,$6663,$6666,$0c18,$6018,$1c00,$603c,$603c
	dc.w	$063c,$183e,$6000,$0060
	dc.b	$18
	dc.b	'f|<|>|>~ffcff~'
	dc.b	$18,$18,$18,$79,$1c,$00,$c3,$e7,$83,$c1,$ff,$a1,$7e,$8c,$df,$d8
	dc.b	$7f,$d8,$db,$0d,$b0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7f
	dc.b	$60,$77,$1c,$38,$48,$00,$18,$66,$66,$3c,$18,$38,$18,$18,$18,$ff
	dc.b	$7e,$00,$7e,$00,$18,$6e,$18,$0c,$18,$3c,$7c,$7c,$0c,$3c,$3e,$18
	dc.b	$18,$30,$00,$0c,$0c
	dc.b	'nf|`f||`~'
	dc.b	$18,$06,$78,$60,$7f,$7e,$66,$66,$66,$66,$3c,$18,$66,$66,$6b,$3c
	dc.b	$3c,$18,$18,$30,$18,$36,$00,$30,$06
	dc.b	'|`>f>f|8'
	dc.w	$066c,$187f,$6666,$6666,$6660,$1866,$666b,$3c66
	dc.w	$0c30,$180c,$4f1e,$00e7,$c383,$c1ff,$a17e,$d8de
	dc.w	$fe36,$deff,$0db0,$0000,$0000,$0000,$0000,$0000
	dc.w	$3e7e,$7738,$1c92,$0018,$0066,$0630,$6f00,$1818
	dc.w	$3c18,$0000,$0030,$7618,$180c,$6c06,$6618,$6606
	dc.w	$0000,$1800,$1818
	dc.b	'nff`f``nf'
	dc.b	$18,$06
	dc.b	'x`k~f|f|'
	dc.b	$06,$18,$66,$66,$7f,$3c,$18,$30,$18,$18,$18,$63,$00,$00,$3e,$66
	dc.b	$60,$66,$7e,$18,$66,$66,$18,$06,$78,$18,$7f,$66,$66,$66,$66,$60
	dc.b	$3c,$18,$66,$66,$7f,$18,$66,$18,$18,$18,$18,$06,$1c,$00,$24,$66
	dc.b	$f6,$6f,$ff,$99,$a5,$70,$06,$18,$06,$18,$1e,$19,$98,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$1c,$18,$08,$70,$0e,$24,$00,$00,$00
	dc.b	$ff
	dc.b	'|ff',0
	dc.w	$1c38,$6618,$1800,$1860,$6618,$3066,$7e66,$6630
	dc.w	$660c,$1818,$0c7e,$3000
	dc.b	'`~ffl``ff'
	dc.b	$18
	dc.b	'fl`cnf`ll'
	dc.b	$06,$18,$66,$3c,$77,$66,$18,$60,$18,$0c,$18,$00,$00,$00,$66,$66
	dc.b	$60,$66,$60,$18,$3e,$66,$18,$06,$6c,$18,$6b,$66,$66,$7c,$3e,$60
	dc.b	$06,$18,$66,$3c,$3e,$3c,$3e,$30,$18,$18,$18,$00,$18,$00,$24,$3c
	dc.b	$1c,$38,$ff,$42,$c3,$20,$06,$18,$06,$18,$1b,$39,$9c,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$08,$1e,$1c,$e0,$07,$48,$00,$18,$00
	dc.b	$66,$18,$46,$3b,$00,$0e,$70,$00,$00,$18,$00,$18,$40,$3c,$7e,$7e
	dc.b	$3c,$0c,$3c,$3c,$30,$3c,$38,$18,$18,$06,$00,$60,$18
	dc.b	'>f|<x~`>f~<f~cf<`6f<'
	dc.w	$187e,$1863,$6618,$7e1e,$0678,$00ff,$003e,$7c3c
	dc.w	$3e3c,$1806,$663c,$0666,$3c63,$663c,$6006,$607c
	dc.w	$0e3e,$1836,$660c,$7e0e,$1870,$0010,$003c,$1818
	dc.w	$18ff,$3ce7,$0000,$0000,$0000,$6186,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$00c0,$0392,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$3000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0030,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	19,0
	dc.b	$7c,$00,$00,$3c,$00,$00,$00,$00,$00,$60,$06,$00,$00,$00,$00,$00
	dc.b	$00,$00,$78,$00,$00,$18,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00
	dc.b	$e7,$00
	dc.b	'l`f',0
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$00
	dc.b	$03,$c0,$00,$00,$00,$00,$00,$18,$00,$38,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$06
	dc.b	$00,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dcb.b	19,0
	dc.w	$4000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$00ff,$00c3,$006c,$6066,$787c,$05a0
	dc.w	$0000,$0000,$0000,$0000,$0000,$0078,$0003,$c000
	dc.w	$0000,$0000,$1800,$7c00,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0600,$6000
	dcb.b	30,0
	dc.w	$0800,$6000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0007,$18e0
	dc.w	$0000,$0000,$0000,$00ff,$3cc3,$016c,$6066,$607c
	dc.w	$05a0,$0000,$0000,$0000,$0000,$0000,$0060,$1807
	dc.w	$e022,$0018,$6666,$3e66,$6c18,$0660,$6600,$0000
	dc.w	$0006,$3c18,$3c7e,$0c7e
	dc.b	$1c
	dc.b	'~<<',0
	dc.b	$00,$0c,$00,$30,$3c,$1c,$18
	dc.b	'|<x~~>f~'
	dc.b	$06
	dc.b	'f`cf<|<|>~ffcff~'
	dc.b	$1e,$40,$78,$08,$00,$70,$00,$60,$00,$06,$00,$0e,$00,$60,$18,$0c
	dc.b	$60,$38,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$0c,$18,$30,$00,$00,$00,$18,$3c,$00,$00,$ff,$42,$bd,$01,$7c,$60
	dc.b	$66,$60,$60,$05,$a0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$60,$3c,$07,$e0,$77,$00,$18,$66,$66,$7e,$66,$6c,$18,$0c,$30,$66
	dc.b	$18,$00,$00,$00,$06,$7e,$18,$7e,$7e,$0c
	dc.b	'~<~~~',0
	dc.b	$00,$0c,$00
	dc.b	'0~><~~|~~~f~'
	dc.b	$06
	dc.b	'f`cf~~~~~~ffcff~'
	dc.b	$1e,$40,$78,$1c,$00,$38,$00,$60,$00,$06,$00,$1e,$00,$60,$18,$0c
	dc.b	$60,$38,$00,$00,$00,$00,$00,$00,$00,$18,$00,$00,$00,$00,$00,$00
	dc.b	$0c,$18,$30,$00,$00,$00,$3c,$24,$38,$1c,$ff,$81,$bd,$03,$6c,$60
	dc.b	$3c,$78,$60,$05,$a0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$78,$3c,$0e,$70,$77,$00,$18,$66,$ff,$60,$6c,$38,$18,$1c,$38,$3c
	dc.b	$18,$00,$00,$00,$0c,$66,$38,$66,$0c,$1c,$60,$70,$06,$66,$66,$18
	dc.b	$18,$18,$7e,$18
	dc.b	'fs~ffn```f'
	dc.b	$18,$06
	dc.b	'l`wfffff`'
	dc.w	$1866,$6663,$6666,$0c18,$6018,$1c00,$1c00,$6000
	dc.w	$0600,$1800,$6000,$0060,$1800,$0000,$0000,$0000
	dc.w	$1800,$0000,$0000,$000c,$1830,$0000,$0066,$242c
	dc.w	$34ff,$9924,$036c,$6018,$6060,$0db0,$0000,$0000
	dc.w	$0000,$0000,$0000,$0078,$180e,$707f,$0018,$66ff
	dc.w	$600c,$3818,$1818,$3c18,$0000,$000c,$6638,$660c
	dc.w	$1c60,$6006,$6666,$1818,$187e
	dc.b	$18
	dc.b	'faffff```f'
	dc.b	$18,$06
	dc.b	'l`wvffff`'
	dc.w	$1866,$6663,$3c66,$0c18,$6018,$3600,$0c3c,$7c3c
	dc.w	$3e3c,$183c,$7c38,$0c66
	dc.b	$18
	dc.b	'6<<|>|>~ffcff~'
	dc.b	$0c,$18,$30,$31,$00,$00,$c3,$24,$e6,$67,$ff,$a5,$24,$06,$6c,$78
	dc.b	$18,$6f,$7e,$0d,$b0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$60,$66,$1c,$38,$7f,$00,$18,$66,$66,$7c,$18,$70,$18,$18,$18,$ff
	dc.b	$7e,$00,$7e,$00,$18,$66,$18,$0c,$18,$3c,$7c,$60,$0c,$3c,$7e,$18
	dc.b	$18,$30,$00,$0c,$0c
	dc.b	'mf~`f||n~'
	dc.b	$18,$06,$78,$60,$7f,$76,$66,$66,$66,$66,$70,$18,$66,$66,$63,$3c
	dc.b	$3c,$18,$18,$30,$18,$36,$00,$04
	dc.b	'>~|~~~~~8'
	dc.w	$0c6e,$187f
	dc.b	'~~~~~~~ffcff~'
	dc.b	$1c,$18,$38,$79,$00,$00,$81,$e7,$83,$c1,$ff,$a1,$24,$06,$00,$00
	dc.b	$00,$6c,$7f,$1d,$b8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$60,$ff,$1c,$38,$7f,$00,$18,$66,$66,$3e,$18,$70,$18,$18,$18,$ff
	dc.b	$7e,$00,$7e,$00,$18,$6e,$18,$0c,$18,$3c,$7e,$7c,$0c,$3c,$3e,$18
	dc.b	$18,$30,$00,$0c,$0c
	dc.b	'kf|`f||n~'
	dc.b	$18,$06
	dc.b	'x`k~fff~8'
	dc.w	$1866,$666b,$183c,$1818,$3018,$6300,$0006,$6660
	dc.w	$6666,$7e66,$6618,$0c7c,$187f,$6666,$6666,$6660
	dc.w	$1866,$666b,$3c66,$0c78,$181e,$5f00,$00e7,$8181
	dc.w	$81ff,$a124,$8c3f,$0f3f,$6c1b,$399c,$0000,$0000
	dc.w	$0000,$0000,$0000,$007e,$ff38,$1c3e,$0018,$00ff
	dc.w	$0630,$de00,$1818,$3c18,$0000,$0030,$7618,$180c
	dc.w	$6c06,$7e18,$6606,$0000,$187e,$1818
	dc.b	'k~f`f``ff'
	dc.b	$18,$06
	dc.b	'l`k~f~f|'
	dc.b	$1c,$18,$66,$66,$6b,$18,$18,$30,$18,$18,$18,$63,$00,$00,$3e,$66
	dc.b	$60,$66,$66,$18,$66,$66,$18,$0c,$78,$18,$6b,$66,$66,$66,$66,$60
	dc.b	$70,$18,$66,$66,$6b,$3c,$66,$18,$78,$18,$1e,$4e,$00,$00,$24,$c3
	dc.b	$83,$c1,$ff,$a5,$bd,$8c,$0c,$0c,$0c,$6f,$1b,$79,$9e,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$7e,$ff,$38,$1c,$3e,$00,$18,$00
	dc.b	$ff,$06,$36,$de,$00,$18,$18,$3c,$18,$00,$00,$00,$30,$66,$18,$18
	dc.b	$0c,$6c,$06,$66,$18,$66,$06,$00,$00,$18,$7e,$18,$18
	dc.b	'n~f`f``ff'
	dc.b	$18,$06
	dc.b	'l`cnf|fl'
	dc.b	$0e,$18,$66,$66,$7f,$3c,$18,$30,$18,$18,$18,$00,$00,$00,$7e,$66
	dc.b	$60,$66,$7e,$18,$66,$66,$18,$0c,$7c,$18,$6b,$66,$66,$66,$66,$60
	dc.b	$3c,$18,$66,$66,$7f,$18,$66,$18,$1c,$18,$38,$00,$00,$00,$24,$66
	dc.b	$e6,$67,$ff,$99,$bd,$d8,$0c,$0c,$0c,$0c,$1e,$71,$8e,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$18,$66,$70,$0e,$1c,$00,$00,$00
	dc.b	$66,$7e,$66,$cc,$00,$18,$18,$66,$18,$18,$00,$18,$60,$66,$18,$30
	dc.b	$66,$7e,$06,$66,$30,$66,$0c,$18,$18,$0c,$00,$30,$18
	dc.b	'`ffff``ff'
	dc.b	$18
	dc.b	'ff`cnf`ff'
	dc.b	$06,$18,$66,$3c,$7f,$3c,$18,$60,$18,$0c,$18,$00,$00,$00,$66,$66
	dc.b	$60,$66,$60,$18,$7e,$66,$18,$0c,$6c,$18,$6b,$66,$66,$66,$66,$60
	dc.b	$0e,$18,$66,$3c,$7f,$3c,$7e,$30,$0c,$18,$30,$00,$00,$00,$24,$3c
	dc.b	$2c,$34,$ff,$81,$c3,$58,$0c,$0e,$0c,$0c,$1e,$71,$8e,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$70,$0e,$1c,$00,$00,$00
	dc.b	$66,$7c,$66,$cc,$00,$1c,$38,$66,$00,$18,$00,$18,$60,$66,$18,$30
	dc.b	$66,$7e,$66,$66,$30,$66,$0c,$18,$18,$0c,$00,$30,$00
	dc.b	'qfffn``ff'
	dc.b	$18
	dc.b	'ff`cff`jf'
	dc.b	$06,$18,$66,$3c,$77,$66,$18,$60,$18,$0c,$18,$00,$00,$00,$66,$66
	dc.b	$60,$66,$60,$18,$3e,$66,$18,$0c,$66,$18,$63,$66,$66,$7e,$7e,$60
	dc.b	$06,$18,$66,$3c,$77,$3c,$3e,$30,$0c,$18,$30,$00,$00,$00,$3c,$18
	dc.b	$38,$1c,$ff,$42,$c3,$70,$0c,$0c,$0c,$0c,$1b,$61,$86,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$1e,$3c,$e0,$07,$08,$00,$18,$00
	dc.b	$00,$18,$00,$fe,$00,$0c,$30,$00,$00,$18,$00,$18,$40,$7e,$7e,$7e
	dc.b	$7e,$0c,$7e,$7e,$30,$7e,$38,$18,$18,$06,$00,$60,$18
	dc.b	'?f~~|~`~f~~c~cf~`|c~'
	dc.w	$187e,$1863,$6618,$7e1e,$0678,$00ff,$007e,$7e7e
	dc.w	$7e7e,$1806,$663c
	dc.b	$0c
	dc.b	'g<cf~|>`~'
	dc.w	$1e7e,$1863,$6606,$7e0c,$1830,$0000,$0000,$0000
	dc.w	$00ff,$3ce7,$300c,$0c0c,$0c1b,$4182,$0000,$0000
	dc.w	$0000,$0000,$0000,$001e,$3ce0,$0708,$0018,$0000
	dc.w	$1800,$7600,$0660,$0000,$1800,$1840,$3c7e,$7e3c
	dc.w	$0c3c,$3c30,$3c38,$1818,$0600,$6018
	dc.b	$1e
	dc.b	'f|<x~`<f~<c~cf<`6c|'
	dc.w	$183c,$1841,$6618,$7e1e,$0678,$00ff,$003e,$7c3e
	dc.w	$3e3e,$1806,$663c,$0c63,$3c63,$663c,$6006,$607c
	dc.w	$0e3e,$1841,$6606,$7e0c,$1830,$0000,$0000,$0000
	dc.w	$00ff,$0000,$200c,$0c0c,$0c00,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$00c0,$0300,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$3000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0030,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	19,0
	dc.b	$7e,$00,$00,$7c,$00,$00,$00,$00,$00,$60,$06,$00,$00,$00,$00,$00
	dc.b	$00,$00,$7e,$00,$07,$18,$e0,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dcb.b	22,0
	dc.b	$c0,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00
	dcb.b	42,0
	dc.b	$7c,$00,$00,$78,$00,$00,$00,$00,$00,$60,$06,$00,$00,$00,$00,$00
	dc.b	$00,$00,$7c,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff
	dcb.b	4757,$ff

	end
