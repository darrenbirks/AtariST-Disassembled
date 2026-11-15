; LLS.S  -  The L.L.S. cartridge, "SUB HUMANS IN TURKEY L.L.S. CARTRIDGE"
; Devpac source of the cartridge, disassembled by Darren Birks, 14 November 2026.
; 64K at $FA0000; the code and data are $0000-$68E4, the rest $FF.
;
; This source rebuilds the cartridge's 64K byte for byte with
;   vasmm68k_mot -devpac -m68000 -Fbin -o LLS.IMG LLS.S
; LLS.BIN is 128K: these 64K twice ($FA0000 and the same again at $FB0000), so
;   copy /b LLS.IMG+LLS.IMG LLS.BIN
; gives it whole.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; A machine code monitor on a diagnostic cartridge ($FA52235F at its start): TOS runs it at reset, before it
; boots.  It clears the memory below its workspace at $E0000, resets the hardware, takes the exception vectors
; and enters itself with trap #15.  Running from there (R) goes back to TOS, which boots with the monitor still
; holding the vectors $8-$27: a bus or address error, an illegal instruction, CHK, TRAPV, a privilege
; violation, the traps #3-#12 or #15 bring it back up, with the exception named.
;
; Its screen is its own (medium resolution, plane 0, in the workspace from $400): the registers, two
; disassembly windows (W1, W3), two memory windows (W2, W4) and the watch area.  The commands come from
; key_table: single step, step over, skip, run with up to four breakpoints, set registers and labels,
; evaluate expressions (+ - * / & ! ^ << >> ~, [address].B/.W/.L, $hex, %binary, decimal, register and label
; names), edit memory, fill, copy, search, zoom, split and lock the windows, watches, view the program's screen,
; move the monitor or its workspace, binary load and save through GEMDOS, and its own floppy driver: read and
; write sectors, write a file onto a disk, format 80 tracks of 10 sectors on 2 sides (with disk_image on track
; 0: The Medway Boys Protector III boot sector and the volume label LLS_DISK.EGB), and load a disk's boot
; sector to trace it (F10).  H shows the help text.
;
; The workspace (a5, kept in $38.w, whose top byte holds the exception number) is laid out by the ws_
; equates below.  $30 and $34 are used to keep a0 and d0 in the exception entries.  The floppy commands use
; fixed memory: $EA000 (the drives' tracks and buffers) and $F0000-$F7FFF (write_file).
;
; Some things in it look unfinished:
;   - load_executable and go_download are not in key_table, so E and the download cannot be reached; the help
;     text lists them anyway, has F6 for loading the boot sector (it is F10) and *M where it is Control M.
;   - parse_term's division and's the quotient with $7FFF, so a quotient of $8000 or more is cut.
;   - dis_shift has a second bne after a bne (never taken).
;   - format_disk copies $1504 bytes of disk_image, although the 10 sectors it writes are $1400.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$01d1  the start-up, the hardware set-up, the way into the monitor
;   $01d2-$11a3  the command loop, key_table and the commands
;   $11a4-$1975  the floppy commands (sectors, write a file, format, the boot sector)
;   $1976-$1e65  the floppy driver
;   $1e66-$26ff  breakpoints, the keyboard, the expressions, the line editor
;   $2700-$2e47  the workspace, the screen and the windows
;   $2e48-$3569  the disassembler
;   $356a-$39eb  printing
;   $39ec-$3c9f  the exception entries and the monitor's entry
;   $3ca0-$5339  the names, the screen's texts, opcode_table, the key tables, the messages, the help, the fonts
;   $5400-$68e4  disk_image
;   $68e5-$ffff  $FF
;
;=======================================================================

ws_magic	equ	$0                      ; 'SHIT' once set up
ws_font	equ	$4                              ; the font in use
ws_rows	equ	$8                              ; the row table in use
ws_fault	equ	$c                      ; where a bus or address error in the monitor goes
ws_d0	equ	$10                             ; the program's d0-d7
ws_a0	equ	$30                             ; its a0-a6
ws_usp	equ	$4c                             ; its user stack
ws_ssp	equ	$50                             ; its supervisor stack
ws_pc	equ	$54                             ; its pc
ws_sr	equ	$58                             ; its status register (a word)
ws_vidptr	equ	$5a                     ; the address of the long holding its screen address
ws_column	equ	$5e                     ; the cursor's column (a word)
ws_column_low	equ	$5f
ws_row	equ	$60                             ; the cursor's row (a word)
ws_row_low	equ	$61
ws_inverse	equ	$62                     ; bit 0: inverse
ws_window	equ	$63                     ; the current window: 0 the watches, 1-4 W1-W4
ws_symtab	equ	$64                     ; the label table (12-byte entries)
ws_bad_instruction	equ	$68             ; set by disassemble for an instruction that cannot be
ws_locks	equ	$69                     ; W1's register lock (1 up, 0 none)
ws_lock_w2	equ	$6a
ws_lock_w3	equ	$6b
ws_lock_w4	equ	$6c
ws_w1	equ	$6e                             ; W1's base (W1-W4 a long each)
ws_w2	equ	$72
ws_w3	equ	$76
ws_w4	equ	$7a
ws_w1_end	equ	$7e                     ; the address after W1's last line (W1-W4)
ws_w2_end	equ	$82
ws_w3_end	equ	$86
ws_w4_end	equ	$8a
ws_w3_open	equ	$8e                     ; W3 shown (W1 split)
ws_w4_open	equ	$8f                     ; W4 shown (W2 split)
ws_scratch	equ	$90                     ; a long or word for the command in hand
ws_line_end	equ	$92                     ; the edited line's end column
ws_temp_breakpoint	equ	$94             ; the temporary breakpoint (-1 none)
ws_breakpoints	equ	$98                     ; the 4 breakpoints (-1 free)
ws_temp_breakpoint_word	equ	$a8             ; the word under the temporary breakpoint
ws_breakpoint_words	equ	$aa             ; the words under the breakpoints
ws_name	equ	$b2                             ; a name read (8 characters and a 0)
ws_bss	equ	$c2                             ; the loaded program's bss
ws_data	equ	$c6                             ; its data
ws_text	equ	$ca                             ; its text
ws_file_name	equ	$ce                     ; a file name typed
ws_monitor_screen	equ	$de             ; the monitor's screen shown
ws_saved_rez	equ	$df                     ; the program's resolution
ws_saved_palette	equ	$e0             ; its colours 0-1
ws_saved_palette_high	equ	$e4             ; its colours 2-3
ws_file_length	equ	$e8                     ; write_file: the length
ws_file_start	equ	$ec                     ; write_file: the start
ws_first_data_sector	equ	$f0             ; the disk's first data sector
ws_clusters	equ	$f2                     ; the free clusters taken
ws_dos_name	equ	$f4                     ; the name typed for write_file (12 bytes)
ws_dos_name_middle	equ	$f8
ws_dos_name_end	equ	$fc
ws_file_sectors	equ	$100                    ; the file's sectors
ws_fat_entries	equ	$102                    ; the FAT's entries
ws_fat_sectors	equ	$104                    ; sectors a FAT
ws_cluster_sectors	equ	$106            ; sectors a cluster
ws_directory_sectors	equ	$108            ; the directory's sectors
ws_fat_copy_sector	equ	$10a            ; the second FAT's sector
ws_key_wait	equ	$10c                    ; the key repeat wait
ws_token	equ	$10e                    ; the expression's current character (0 at the end)
ws_watch	equ	$110                    ; the current watch, from ws_watches
ws_error_stack	equ	$112                    ; the stack to go back to on an expression error
ws_mnemonic	equ	$116                    ; the mnemonic's place in ws_line
ws_search	equ	$11a                    ; the value or text searched for
ws_message	equ	$26a                    ; a message is on the message row
ws_errors_quiet	equ	$26b                    ; expression errors not flashed
ws_watch_editing	equ	$26c            ; a watch is being edited
ws_watch_check_only	equ	$26d            ; draw_watch checks only
ws_search_kind	equ	$26e                    ; the search: 1 byte, 2 word, 3 long, 4 text (bit 7 any case)
ws_stepping	equ	$26f                    ; stepping (no breakpoints set); also: input_file_values wants a length
ws_in_monitor	equ	$270                    ; in the monitor
ws_drawn	equ	$271                    ; the screen drawn
ws_shift	equ	$272                    ; bit 0 Alternate, 1 Control, 2 Shift, 3 Caps Lock
ws_key_held	equ	$273                    ; the key held, for the repeat
ws_value_error	equ	$274                    ; the expression had an error
ws_keep_program_screen	equ	$275            ; the program's screen shown while running
ws_watches	equ	$276                    ; the watches (256 bytes, each 0-ended, 0 0 at the end)
ws_line	equ	$376                            ; the line being edited or disassembled
ws_line_next	equ	$377
ws_line_label	equ	$37f                    ; a disassembly line's label place
ws_vectors	equ	$3c6                    ; the program's vectors $8-$27
ws_screen	equ	$400                    ; the monitor's screen (32000 bytes)

	org	$fa0000

;------------------------------------------------------------------------------
; cartridge_magic: $FA52235F: a diagnostic cartridge, which TOS runs at reset before anything else, with
; a6 the address to go back to.
;------------------------------------------------------------------------------
cartridge_magic:
	dc.w	$fa52,$235f

;------------------------------------------------------------------------------
; start: the area below the workspace cleared, the workspace at $E0000 (the stack below it), the hardware
; reset, the exception vectors taken, then the monitor entered with trap #15; when it runs the program,
; TOS goes on booting.
;------------------------------------------------------------------------------
start:
	move.l	a0,$30                          ; kept
	lea	$dfc00,a0                       ; $DFC00
	move.w	#$200,d0                        ; $201 longs, to $E0003 (the workspace's magic too)
start_clear:
	clr.l	(a0)+                           ; cleared
	dbra	d0,start_clear
	movea.l	$30,a0
	movea.l	#$e0000,sp                      ; the stack, below the workspace
	move.l	sp,$38.w                        ; the workspace (its top byte: the exception number)
	move.l	a1,$30
	bsr.w	init_hardware                   ; the hardware reset
	bclr	#$5,$fffffa09.w                 ; MFP IERB, Timer C interrupt off
	lea	exception_bus_error(pc),a1      ; bus error
	move.l	a1,$8.w                         ; bus error vector
	lea	exception_address_error(pc),a1  ; address error
	move.l	a1,$c.w                         ; address error vector
	lea	exception_ignore(pc),a1         ; divide by zero: ignored
	move.l	a1,$14.w
	lea	exception_trap_3(pc),a1         ; trap #3 to #12
	move.l	a1,$8c.w
	lea	exception_trap_4(pc),a1
	move.l	a1,$90.w
	lea	exception_trap_5(pc),a1
	move.l	a1,$94.w
	lea	exception_trap_6(pc),a1
	move.l	a1,$98.w
	lea	exception_trap_7(pc),a1
	move.l	a1,$9c.w
	lea	exception_trap_8(pc),a1
	move.l	a1,$a0.w
	lea	exception_trap_9(pc),a1
	move.l	a1,$a4.w
	lea	exception_trap_10(pc),a1
	move.l	a1,$a8.w
	lea	exception_trap_11(pc),a1
	move.l	a1,$ac.w
	lea	exception_trap_12(pc),a1
	move.l	a1,$b0.w
	lea	exception_trap_15(pc),a1        ; trap #15: enter the monitor
	move.l	a1,$bc.w
	lea	exception_chk(pc),a1            ; CHK
	move.l	a1,$18.w
	lea	exception_trapv(pc),a1          ; TRAPV
	move.l	a1,$1c.w
	lea	exception_privilege(pc),a1      ; privilege violation
	move.l	a1,$20.w
	lea	exception_illegal(pc),a1        ; illegal instruction
	move.l	a1,$10.w                        ; illegal instr vector
	bra.w	enter_monitor                   ; enter the monitor

;------------------------------------------------------------------------------
; init_hardware: interrupts off, the hardware reset, the MFP set up, the sound chip quiet, the keyboard ACIA
; reset and the keyboard's mouse off, then the resolution put back.
;------------------------------------------------------------------------------
init_hardware:	; from: start
	move.w	#$2700,sr
	move.b	$ffff8260.w,d7                  ; shift mode, the resolution
	andi.w	#$3,d7
	reset                                   ; the peripherals reset
	bsr.w	sync_to_vbl                     ; to the vertical blank, 50 Hz
	lea	$fffffa00.w,a0                  ; the MFP
	moveq	#0,d0
	movep.l	d0,1(a0)                        ; GPIP, AER, DDR, IERA cleared
	movep.l	d0,9(a0)                        ; IERB, IPRA, IPRB cleared
	movep.l	d0,$11(a0)                      ; ISRA, ISRB, IMRA, IMRB cleared
	move.b	#$48,$17(a0)                    ; vector $40, software end of interrupt
	bset	#$2,3(a0)                       ; AER: GPIP 2 (CTS) rising
	move.l	#$50ff0200,d0                   ; timer D data $50, ...
	movep.l	d0,$21(a0)
	move.l	#$51ff,d0                       ; timer C data $51, ...
	movep.l	d0,$19(a0)
	move.l	#$1e6448,d0                     ; IERB, IPRA, ...
	movep.l	d0,$11(a0)
	move.l	#$64000000,d0
	movep.l	d0,9(a0)                        ; IERA, IPRA, ...
	move.l	#$7704001e,d0
	movep.l	d0,1(a0)
	move.b	#$7,$ffff8800.w                 ; PSG register select, port A/B direction
	move.b	#$c0,$ffff8802.w                ; PSG write data, both outputs
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	#$7,$ffff8802.w                 ; PSG write data, drives off, side 0
	move.b	#$3,$fffffc00.w                 ; keyboard ACIA control, keyboard ACIA reset
	move.b	#$96,$fffffc00.w                ; keyboard ACIA control, 8N1, /64, receive interrupt
	move.b	#$80,$fffffc02.w                ; keyboard ACIA data, IKBD: set mouse ...
	move.b	#$1,$fffffc02.w                 ; keyboard ACIA data
	move.b	#$8,$fffffc02.w                 ; keyboard ACIA data
	move.b	#$1a,$fffffc02.w                ; keyboard ACIA data, and mouse off
	sf	$ffff820d.w                     ; STE fine scroll 0
	sf	$ffff8264.w
	move.b	d7,$ffff8260.w                  ; shift mode, the resolution back
	rts

;------------------------------------------------------------------------------
; sync_to_vbl: waits for the vertical blank with Timer B counting display lines, then sets 50 Hz.
;------------------------------------------------------------------------------
sync_to_vbl:	; from: init_hardware
	lea	$ffff8260.w,a2                  ; shift mode
	clr.b	(a2)                            ; low resolution
	moveq	#1,d2
	lea	$fffffa21.w,a0                  ; MFP TBDR
	lea	$fffffa1b.w,a1                  ; MFP TBCR
	move.b	#$10,(a1)                       ; stopped
	move.b	#$f0,(a0)                       ; 240 lines
	move.b	#$8,(a1)                        ; event count
sync_to_vbl_line:
	cmp.b	(a0),d2                         ; to the last line
	bne.s	sync_to_vbl_line
sync_to_vbl_blank:
	move.b	(a0),d4
	move.w	#$267,d3
sync_to_vbl_still:
	cmp.b	(a0),d4                         ; no line counted
	bne.s	sync_to_vbl_blank               ; one did: again
	dbra	d3,sync_to_vbl_still
	move.b	#$10,(a1)                       ; stopped
	move.b	#$2,$ffff820a.w                 ; sync mode, 50 Hz
	rts

;------------------------------------------------------------------------------
; enter_monitor: the monitor, then back to TOS (a6) when it runs the program.
;------------------------------------------------------------------------------
enter_monitor:	; from: start
	movea.l	$30,a1
	trap	#15                             ; the monitor
	movea.l	$30,a1
	jmp	(a6)                            ; back to TOS

;------------------------------------------------------------------------------
; init_workspace_keep: init_workspace with every register kept (not called).
;------------------------------------------------------------------------------
init_workspace_keep:
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	bsr.w	init_workspace
	movem.l	(sp)+,d0-d7/a0-a6
	rts

;------------------------------------------------------------------------------
; monitor_restart: the screen drawn again and the vectors taken again, then the command loop.
;------------------------------------------------------------------------------
monitor_restart:	; from: move_debugger, initialise_workspace, load_bootsector
	bsr.w	draw_screen                     ; drawn
	bsr.w	take_vectors                    ; the vectors

;------------------------------------------------------------------------------
; command_loop: a fault in a command does nothing (rte), the stack reset, a key, then its command from
; key_table.
;------------------------------------------------------------------------------
command_loop:	; from: next_window, step_over, skip_instruction, set_window_base, evaluate, fill_memory, 32 more
	lea	exception_ignore(pc),a0         ; faults: rte
	move.l	a0,ws_fault(a5)
	lea	ws_message(a5),sp               ; the stack reset
	bsr.w	get_key                         ; a key
	bsr.w	to_capitals                     ; in capitals
	bsr.w	clear_message                   ; the message line cleared
	lea	key_table(pc),a0                ; the commands
command_find:
	move.w	(a0)+,d1                        ; the key
	beq.s	command_loop                    ; the end: no command
	move.w	(a0)+,d2                        ; its offset
	cmp.w	d1,d0                           ; this one?
	bne.s	command_find                    ; no
	lea	key_table(pc,d2.w),a1           ; its routine
	jmp	(a1)                            ; run

;------------------------------------------------------------------------------
; key_table: each command's key and its routine's offset from key_table.  F1-F10 are $14-$1d, the cursor
; keys $01-$04 (up, down, left, right); Alternate adds $100 and Control $200.
;------------------------------------------------------------------------------
key_table:	; from: command_loop
	dc.w	$0015,step_over-key_table
	dc.w	$0242,breakpoint_here-key_table
	dc.w	$0243,quit_monitor-key_table
	dc.w	$0009,next_window-key_table
	dc.w	$024c,set_label-key_table
	dc.w	$0052,run_program-key_table
	dc.w	$0016,skip_instruction-key_table
	dc.w	$0048,help-key_table
	dc.w	$0257,set_workspace-key_table
	dc.w	$024d,move_debugger-key_table
	dc.w	$0014,single_step-key_table
	dc.w	$0047,find-key_table
	dc.w	$0049,copy_memory-key_table
	dc.w	$004d,set_window_base-key_table
	dc.w	$004e,search_next-key_table
	dc.w	$004f,evaluate-key_table
	dc.w	$0056,view_other_screen-key_table
	dc.w	$0057,fill_memory-key_table
	dc.w	$0042,binary_load_save-key_table
	dc.w	$0146,format_disk-key_table
	dc.w	$0017,read_sectors-key_table
	dc.w	$0018,write_sectors-key_table
	dc.w	$001a,write_file-key_table
	dc.w	$001d,load_bootsector-key_table
	dc.w	$0157,add_watch-key_table
	dc.w	$0145,edit_memory-key_table
	dc.w	$0152,set_register-key_table
	dc.w	$0149,initialise_workspace-key_table
	dc.w	$0153,split_window-key_table
	dc.w	$0144,delete_watch-key_table
	dc.w	$014c,lock_window-key_table
	dc.w	$005a,zoom_window-key_table
	dc.w	$0142,breakpoint_at-key_table
	dc.w	$0156,always_view_other-key_table
	dc.w	$0002,cursor_down-key_table
	dc.w	$0001,cursor_up-key_table
	dc.w	$0004,cursor_right-key_table
	dc.w	$0003,cursor_left-key_table
	dc.w	$0202,page_down-key_table
	dc.w	$0201,page_up-key_table
	dc.w	$0000,$0000                     ; the end

;------------------------------------------------------------------------------
; quit_monitor (^C): asks, puts the vectors $8-$27 back, the program's screen back and Pterm0 to TOS.
;------------------------------------------------------------------------------
quit_monitor:	; from: key_table
	lea	quit_question(pc),a0            ; "Are you sure you want to quit [Y/N] ? "
	bsr.w	ask_yes_no
	lea	ws_vectors(a5),a0               ; the vectors kept
	movea.w	#$8,a1                          ; from $8
	moveq	#7,d0                           ; 8
quit_monitor_vector:
	move.l	(a0)+,(a1)+                     ; put back
	dbra	d0,quit_monitor_vector
	sf	ws_drawn(a5)
	movea.l	ws_ssp(a5),sp                   ; the program's supervisor stack
	bsr.w	show_program_screen             ; its screen
	movea.l	ws_vidptr(a5),a0
	move.l	(a0),d0
	bsr.w	set_screen
	move.w	#$2200,sr                       ; interrupts on
	move.w	#$0,-(sp)
	trap	#1                              ; Pterm0
	rts

;------------------------------------------------------------------------------
; go_download: asks, then trap #0 (not called: F10 goes to download).
;------------------------------------------------------------------------------
go_download:
	lea	download_question(pc),a0        ; "Are you sure you want to go to download [Y/N] ? "
	bsr.w	ask_yes_no
	trap	#0

;------------------------------------------------------------------------------
; next_window (TAB): the next window: 0 (the watches), 1, 2, then 3 and 4 when the windows are split.
;------------------------------------------------------------------------------
next_window:	; from: key_table
	move.b	ws_window(a5),d0                ; the window
	addq.w	#1,d0                           ; the next
	cmp.w	#$3,d0                          ; 3?
	bcs.s	next_window_set                 ; below
	bne.s	next_window_four                ; over
	tst.b	ws_w3_open(a5)                  ; W3 open?
	bne.s	next_window_set                 ; yes
	addq.w	#1,d0                           ; no: 4
next_window_four:
	cmp.w	#$4,d0                          ; 4?
	bne.s	next_window_first               ; no: 0
	tst.b	ws_w4_open(a5)                  ; W4 open?
	bne.s	next_window_set                 ; yes
next_window_first:
	moveq	#0,d0                           ; 0
next_window_set:
	move.b	d0,ws_window(a5)
	bsr.w	draw_titles                     ; the titles
	bra.w	command_loop

;------------------------------------------------------------------------------
; single_step (F1): runs one instruction with the trace bit.
;------------------------------------------------------------------------------
single_step:	; from: key_table
	move.w	#$8000,d1                       ; trace
	st	ws_stepping(a5)                 ; stepping: no breakpoints
	bra.s	resume

;------------------------------------------------------------------------------
; set_breakpoints: ILLEGAL put at each breakpoint (their words kept); a breakpoint that will not take
; (ROM) gives "Cannot set temporary breakpoint!".  Then resume.
;------------------------------------------------------------------------------
set_breakpoints:	; from: step_over, run_program
	lea	breakpoint_failed(pc),a0        ; a fault: the message
	move.l	a0,ws_fault(a5)
	lea	ws_breakpoints(a5),a0           ; the breakpoints
	lea	ws_breakpoint_words(a5),a2      ; their words
	moveq	#3,d2                           ; 4
	move.w	#$4afc,d3                       ; ILLEGAL
set_breakpoints_next:
	move.l	(a0)+,d0                        ; the address
	bmi.s	set_breakpoints_skip            ; none
	movea.l	d0,a1
	move.w	(a1),(a2)                       ; its word kept
	move.w	d3,(a1)                         ; ILLEGAL
	cmp.w	(a1),d3                         ; taken?
	bne.w	breakpoint_failed               ; no
set_breakpoints_skip:
	addq.w	#2,a2
	dbra	d2,set_breakpoints_next

;------------------------------------------------------------------------------
; resume: trace and illegal instruction vectors taken, the program's registers back, and rte to it with
; d1 or'ed into its status register (the trace bit for a step).
;------------------------------------------------------------------------------
resume:	; from: single_step
	lea	exception_trace(pc),a1          ; trace
	move.l	a1,$24.w
	lea	exception_illegal(pc),a1        ; illegal instruction
	move.l	a1,$10.w                        ; illegal instr vector
	sf	ws_in_monitor(a5)               ; out of the monitor
	lea	ws_d0(a5),a0                    ; the registers
	movea.l	$40(a0),sp                      ; the program's supervisor stack
	movea.l	$3c(a0),a1                      ; its user stack
	move.l	a1,usp
	move.l	$44(a0),-(sp)                   ; its pc
	bclr	#$0,3(sp)                       ; even
	move.w	$48(a0),d0                      ; its status register
	andi.w	#$7fff,d0                       ; no trace
	or.w	d1,d0                           ; + d1
	move.w	d0,-(sp)
	movem.l	(a0),d0-d7                      ; d0-d7
	movem.l	$20(a0),a0-a6                   ; a0-a6
	rte                                     ; to the program

;------------------------------------------------------------------------------
; step_over (F2): a temporary breakpoint after the instruction at pc, then run.
;------------------------------------------------------------------------------
step_over:	; from: key_table
	move.l	ws_pc(a5),d0                    ; pc
	bclr	#$0,d0                          ; even
	movea.l	d0,a1
	bsr.w	disassemble                     ; over the instruction
	lea	breakpoint_failed(pc),a0        ; a fault: the message
	move.l	a0,ws_fault(a5)
	move.l	a1,ws_temp_breakpoint(a5)       ; the temporary breakpoint
	move.w	(a1),ws_temp_breakpoint_word(a5) ; its word kept
	move.w	#$4afc,(a1)                     ; ILLEGAL
	cmpi.w	#$4afc,(a1)                     ; taken?
	bne.s	breakpoint_failed               ; no
	bsr.w	show_program_screen             ; the program's screen
	sf	ws_stepping(a5)                 ; not stepping
	clr.b	ws_key_held(a5)                 ; no key
	clr.b	ws_shift(a5)                    ; no shift keys
	bra.w	set_breakpoints                 ; the breakpoints and run
breakpoint_failed:	; from: set_breakpoints
	lea	temporary_breakpoint_text(pc),a0 ; "Cannot set temporary breakpoint!"
	bsr.w	print_message
	st	ws_message(a5)                  ; a message shown
	lea	exception_ignore(pc),a0         ; faults: rte
	move.l	a0,ws_fault(a5)
	bra.w	command_loop

;------------------------------------------------------------------------------
; run_program (R): asks, then runs at full speed with the breakpoints set.
;------------------------------------------------------------------------------
run_program:	; from: key_table
	lea	run_question(pc),a0             ; "Are you sure you want to run [Y/N] ? "
	bsr.w	ask_yes_no
	sf	ws_drawn(a5)                    ; the screen to be drawn again
	bsr.w	show_program_screen             ; the program's screen
	moveq	#0,d1                           ; no trace
	clr.b	ws_key_held(a5)                 ; no key
	clr.b	ws_shift(a5)                    ; no shift keys
	bra.w	set_breakpoints

;------------------------------------------------------------------------------
; skip_instruction (F3): pc past the instruction at it.
;------------------------------------------------------------------------------
skip_instruction:	; from: key_table
	movea.l	ws_pc(a5),a1                    ; pc
	bsr.w	disassemble                     ; over the instruction
	move.l	a1,ws_pc(a5)
	bsr.w	redraw_windows                  ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; set_window_base (M): "Modify window base > ".
;------------------------------------------------------------------------------
set_window_base:	; from: key_table
	bsr.w	current_window                  ; the window's base
	movea.l	a0,a2
	lea	window_base_prompt(pc),a4       ; "Modify window base > "
	bsr.w	input_value                     ; the value
	bne.w	command_loop                    ; escape
	move.l	d0,(a2)                         ; set
	bsr.w	draw_windows                    ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; evaluate (O): "Enter expression > ", then "Result=$hex,decimal".
;------------------------------------------------------------------------------
evaluate:	; from: key_table
	lea	expression_prompt(pc),a4        ; "Enter expression > "
	bsr.w	input_value                     ; the value
	bne.w	command_loop                    ; escape
	move.l	d0,-(sp)                        ; kept
	lea	result_text(pc),a0              ; "Result=$"
	bsr.w	print_message
	move.l	(sp),d0
	bsr.w	print_hex_long                  ; in hex
	subi.w	#$1,ws_column(a5)
	moveq	#44,d0                          ; ','
	bsr.w	print_char
	bsr.w	print_space
	move.l	(sp)+,d0
	bsr.w	print_decimal                   ; in decimal
	bra.w	command_loop

;------------------------------------------------------------------------------
; fill_memory (W): "Fill start, end, with > ": bytes from start to end set.
;------------------------------------------------------------------------------
fill_memory:	; from: key_table
	lea	fill_prompt(pc),a0              ; "Fill start, end, with > "
	bsr.w	input_three_values              ; the three values
	bne.s	command_redraw                  ; escape
	movea.l	d4,a1                           ; start
	movea.l	d5,a0                           ; end
fill_memory_byte:
	cmpa.l	a0,a1                           ; past the end?
	bhi.s	command_redraw                  ; yes
	move.b	d6,(a1)+                        ; set
	bra.s	fill_memory_byte
command_redraw:	; from: copy_memory
	bsr.w	draw_windows                    ; drawn
command_done:	; from: find, input_search_value, set_register, set_label, ask_yes_no, edit_memory, 3 more
	bsr.w	clear_message                   ; the message line cleared
	bra.w	command_loop

;------------------------------------------------------------------------------
; copy_memory (I): "Copy start, end, dest > ", up or down as the areas overlap.
;------------------------------------------------------------------------------
copy_memory:	; from: key_table
	lea	copy_prompt(pc),a0              ; "Copy start, end, dest > "
	bsr.w	input_three_values              ; the three values
	bne.s	command_redraw                  ; escape
	movea.l	d4,a1                           ; start
	movea.l	d5,a0                           ; end
	movea.l	d6,a2                           ; dest
	cmpa.l	a2,a1                           ; below the start?
	bcs.s	copy_memory_down                ; no: from the end
copy_memory_up:
	cmpa.l	a0,a1                           ; past the end?
	bhi.s	command_redraw                  ; yes
	move.b	(a1)+,(a2)+                     ; copied
	bra.s	copy_memory_up
	bra.s	command_redraw                  ; (not reached)
copy_memory_down:
	move.l	a0,d0                           ; the end
	sub.l	a1,d0                           ; less the start
	adda.l	d0,a2                           ; the dest's end
copy_memory_down_byte:
	cmpa.l	a0,a1                           ; done?
	bhi.s	command_redraw                  ; yes
	move.b	-(a0),-(a2)                     ; copied
	bra.s	copy_memory_down_byte

;------------------------------------------------------------------------------
; input_three_values: the prompt a0, then three values with commas into d4, d5 and d6.  Z set if all
; three; escape clears it.  A bad value puts the cursor on it to edit.
;------------------------------------------------------------------------------
input_three_values:	; from: fill_memory, copy_memory
	bsr.w	print_message                   ; the prompt
	lea	command_fault(pc),a0            ; a fault: "Command aborted ..."
	move.l	a0,ws_fault(a5)
	clr.b	ws_line(a5)                     ; the line empty
	moveq	#0,d2
	move.w	ws_column(a5),ws_scratch(a5)    ; the column kept
input_three_values_edit:
	move.w	ws_scratch(a5),ws_column(a5)
	bsr.w	edit_line                       ; the line edited
	bne.s	input_three_values_done         ; escape
	lea	ws_line_next(a5),a1
	suba.l	a1,a0
	move.l	a0,d2                           ; the cursor
	lea	ws_line(a5),a0                  ; the line
	bsr.w	evaluate_next                   ; the first value
	tst.b	ws_value_error(a5)              ; an error?
	bne.s	input_three_values_bad          ; yes
	move.l	d0,d4
	cmpi.w	#$2c,ws_token(a5)               ; a comma?
	bne.s	input_three_values_bad          ; no
	bsr.w	evaluate_next                   ; the second value
	tst.b	ws_value_error(a5)              ; an error?
	bne.s	input_three_values_bad          ; yes
	move.l	d0,d5
	cmpi.w	#$2c,ws_token(a5)               ; a comma?
	bne.s	input_three_values_bad          ; no
	bsr.w	evaluate_next                   ; the third value
	tst.b	ws_value_error(a5)              ; an error?
	bne.s	input_three_values_bad          ; yes
	tst.w	ws_token(a5)                    ; the end of the line?
	bne.s	input_three_values_bad          ; no
	move.l	d0,d6
	moveq	#0,d0                           ; all three
input_three_values_done:
	rts
input_three_values_bad:
	bsr.w	flash_screen                    ; the error shown
	lea	ws_line_next(a5),a1
	suba.l	a1,a0                           ; the cursor where it is
	move.l	a0,d2
	bra.s	input_three_values_edit         ; edited again

;------------------------------------------------------------------------------
; search_next (N): the search again from one past the window's base.
;------------------------------------------------------------------------------
search_next:	; from: key_table
	bsr.w	current_window                  ; the window's base
	movea.l	a0,a2
	movea.l	(a2),a1
	addq.w	#1,a1                           ; one on
	move.l	a1,(a2)
	lea	searching_text(pc),a0           ; "Searching..."
	bsr.w	print_message
	move.l	ws_search(a5),d2                ; the value
	move.b	ws_search_kind(a5),d0           ; the kind
	andi.b	#$7f,d0                         ; not the case bit
	cmp.b	#$1,d0                          ; a byte?
	beq.w	find_byte_search
	cmp.b	#$2,d0                          ; a word?
	beq.w	find_word_search
	cmp.b	#$3,d0                          ; a long?
	beq.w	find_long_search
	cmp.b	#$4,d0                          ; text?
	beq.w	find_text_search
	bra.w	command_loop                    ; none yet

;------------------------------------------------------------------------------
; find (G): "Search for Byte, Word, Long, Text ? ", then the value, from the window's base.  The window
; shows it if found; ESC stops the search.
;------------------------------------------------------------------------------
find:	; from: key_table
	bsr.w	current_window                  ; the window's base
	movea.l	a0,a2
	lea	search_question(pc),a0          ; "Search for Byte, Word, Long, Text ? "
	bsr.w	print_message
find_key:
	bsr.w	get_key_cursor                  ; a key
	bsr.w	to_capitals                     ; in capitals
	cmp.w	#$42,d0                         ; 'B'?
	beq.s	find_byte
	cmp.w	#$57,d0                         ; 'W'?
	beq.w	find_word
	cmp.w	#$4c,d0                         ; 'L'?
	beq.w	find_long
	cmp.w	#$54,d0                         ; 'T'?
	beq.w	find_text
	cmp.b	#$1b,d0                         ; escape?
	beq.w	find_done
	cmp.w	#$243,d0                        ; ^C?
	beq.w	find_done
	bra.s	find_key                        ; another key
find_byte:
	lea	byte_prompt(pc),a0              ; "Byte to find > "
	move.l	#$ff,d2                         ; a byte
	bsr.w	input_search_value              ; the value
find_byte_search:	; from: search_next
	move.b	#$1,ws_search_kind(a5)          ; bytes
	moveq	#-1,d0                          ; 65536 between key checks
find_byte_next:
	move.b	(a1)+,d3
	cmp.b	d3,d2                           ; found?
	beq.s	find_byte_found                 ; yes
	dbra	d0,find_byte_next
	bsr.w	poll_ikbd                       ; a key?
	beq.s	find_byte_next                  ; no
	cmp.b	#$1,d0                          ; ESC pressed?
	beq.s	find_show                       ; yes: stopped
	bra.s	find_byte_next
find_text_found:
	movea.l	a3,a1                           ; the text's start
	bra.s	find_show
find_long_found:
	subq.w	#2,a1                           ; back to the start
find_word_found:
	subq.w	#1,a1
find_byte_found:
	subq.w	#1,a1
find_show:
	move.l	a1,(a2)                         ; into the window
	bsr.w	draw_windows                    ; drawn
find_done:
	bra.w	command_done
find_word:
	lea	word_prompt(pc),a0              ; "Word to find > "
	move.l	#$ffff,d2                       ; a word
	bsr.w	input_search_value              ; the value
	move.b	#$2,ws_search_kind(a5)          ; words
find_word_search:	; from: search_next
	move.b	(a1)+,d3
	lsl.w	#8,d3
	moveq	#-1,d0
find_word_next:
	move.b	(a1)+,d3
	cmp.w	d3,d2                           ; found?
	beq.s	find_word_found                 ; yes
	lsl.w	#8,d3
	dbra	d0,find_word_next
	bsr.w	poll_ikbd                       ; a key?
	beq.s	find_word_next                  ; no
	cmp.b	#$1,d0                          ; ESC pressed?
	beq.s	find_show                       ; yes: stopped
	bra.s	find_word_next
find_long:
	lea	long_prompt(pc),a0              ; "Longword to find > "
	moveq	#-1,d2                          ; a long
	bsr.w	input_search_value              ; the value
	move.b	#$3,ws_search_kind(a5)          ; longs
find_long_search:	; from: search_next
	move.b	(a1)+,d3
	lsl.l	#8,d3
	move.b	(a1)+,d3
	lsl.l	#8,d3
	move.b	(a1)+,d3
	lsl.l	#8,d3
	moveq	#-1,d0
find_long_next:
	move.b	(a1)+,d3
	cmp.l	d3,d2                           ; found?
	beq.s	find_long_found                 ; yes
	lsl.l	#8,d3
	dbra	d0,find_long_next
	bsr.w	poll_ikbd                       ; a key?
	beq.s	find_long_next                  ; no
	cmp.b	#$1,d0                          ; ESC pressed?
	beq.w	find_show                       ; yes: stopped
	bra.s	find_long_next
find_text:
	lea	string_prompt(pc),a0            ; "String to find > "
	bsr.w	print_message
	bsr.w	input_line                      ; the text
	bne.w	input_search_escape             ; escape
	move.b	#$4,ws_search_kind(a5)          ; text
	lea	case_question(pc),a0            ; "Search case sensitive [Y/N] ? "
	bsr.w	print_message
find_text_case:
	bsr.w	get_key_cursor                  ; a key
	bsr.w	to_capitals                     ; in capitals
	cmp.b	#$59,d0                         ; 'Y'?
	beq.s	find_text_go
	cmp.b	#$1b,d0                         ; escape?
	beq.w	find_done
	cmp.w	#$243,d0                        ; ^C?
	beq.w	find_done
	cmp.b	#$4e,d0                         ; 'N'?
	bne.s	find_text_case                  ; no: another key
	bset	#$7,ws_search_kind(a5)          ; not case sensitive
	lea	ws_line(a5),a0                  ; the text
find_text_capitals:
	move.b	(a0),d0
	beq.s	find_text_go                    ; the end
	bsr.w	to_capitals                     ; in capitals
	move.b	d0,(a0)+
	bra.s	find_text_capitals
find_text_go:
	lea	searching_text(pc),a0           ; "Searching..."
	bsr.w	print_message
	lea	ws_search(a5),a0                ; the text kept
	lea	ws_line(a5),a1
	moveq	#14,d0                          ; 15 bytes
find_text_copy:
	move.b	(a1)+,(a0)+
	beq.s	find_text_search
	dbra	d0,find_text_copy
	clr.b	(a1)+                           ; ended
find_text_search:	; from: search_next
	movea.l	(a2),a3                         ; from the base
	moveq	#-1,d1                          ; 65536 between key checks
find_text_place:
	lea	ws_search(a5),a0                ; the text
	movea.l	a3,a1
find_text_compare:
	move.b	(a1)+,d0
	btst	#$7,ws_search_kind(a5)          ; case sensitive?
	beq.s	find_text_byte                  ; yes
	bsr.w	to_capitals                     ; in capitals
find_text_byte:
	tst.b	(a0)                            ; the text's end?
	beq.w	find_text_found                 ; yes: found
	cmp.b	(a0)+,d0                        ; the same?
	beq.s	find_text_compare               ; yes: the next
	addq.w	#1,a3                           ; the next place
	dbra	d1,find_text_place
	bsr.w	poll_ikbd                       ; a key?
	beq.s	find_text_place                 ; no
	cmp.b	#$1,d0                          ; ESC pressed?
	beq.w	find_show                       ; yes: stopped
	bra.s	find_text_place

;------------------------------------------------------------------------------
; input_search_value: the prompt a0, the value and'ed with the mask d2 kept as the search's; a1 = the window's
; base.
;------------------------------------------------------------------------------
input_search_value:	; from: find
	movea.l	a0,a4                           ; the prompt
	bsr.w	clear_message                   ; the message line cleared
	move.l	d2,-(sp)                        ; the mask
	bsr.w	input_value                     ; the value
	bne.s	input_search_escape             ; escape
	move.l	d0,-(sp)
	lea	searching_text(pc),a0           ; "Searching..."
	bsr.w	print_message
	move.l	(sp)+,d2
	and.l	(sp)+,d2                        ; masked
	move.l	d2,ws_search(a5)                ; kept
	movea.l	(a2),a1                         ; from the base
	rts
input_search_escape:	; from: find
	bra.w	command_done

;------------------------------------------------------------------------------
; current_window: d1 the window (1-4), a0 its base's address, Z set for a disassembly window (1 or 3).
; With the watches (0) it goes back to the command loop.
;------------------------------------------------------------------------------
current_window:	; from: set_window_base, search_next, find, cursor_right, cursor_left, cursor_down, 7 more
	moveq	#0,d0
	move.b	ws_window(a5),d0                ; the window
	move.w	d0,d1
	subq.w	#1,d0
	bmi.w	command_loop                    ; the watches: none
	lsl.w	#2,d0
	lea	ws_w1(a5),a0                    ; the bases
	adda.l	d0,a0
	cmp.b	#$1,d1                          ; W1?
	beq.s	current_window_done
	cmp.b	#$3,d1                          ; W3?
current_window_done:
	rts

;------------------------------------------------------------------------------
; cursor_right: the window a byte on (a word for a disassembly).
;------------------------------------------------------------------------------
cursor_right:	; from: key_table
	bsr.s	current_window                  ; the window
	beq.s	cursor_right_word               ; disassembly?
	addi.l	#$1,(a0)
	bsr.w	draw_memory                     ; drawn
	bra.w	command_loop
cursor_right_word:
	addi.l	#$2,(a0)                        ; a word on
	bsr.w	draw_disassembly                ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; cursor_left: the window a byte back (a word for a disassembly).
;------------------------------------------------------------------------------
cursor_left:	; from: key_table
	bsr.s	current_window                  ; the window
	beq.s	cursor_left_word                ; disassembly?
	subi.l	#$1,(a0)
	bsr.w	draw_memory                     ; drawn
	bra.w	command_loop
cursor_left_word:
	subi.l	#$2,(a0)                        ; a word back
	bsr.w	draw_disassembly                ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; cursor_down: the window a line on (4 bytes, or an instruction), or the next watch.
;------------------------------------------------------------------------------
cursor_down:	; from: key_table
	tst.b	ws_window(a5)                   ; the watches?
	beq.w	cursor_down_watch               ; yes
	bsr.s	current_window                  ; the window
	beq.s	cursor_down_instruction         ; disassembly?
	addi.l	#$4,(a0)                        ; 4 bytes on
	bsr.w	draw_memory                     ; drawn
	bra.w	command_loop
cursor_down_instruction:
	movea.l	(a0),a1
	bsr.w	disassemble                     ; over an instruction
	move.l	a1,(a0)
	bsr.w	draw_disassembly                ; drawn
	bra.w	command_loop
cursor_down_watch:
	move.w	ws_watch(a5),d0                 ; the watch
	lea	ws_watches(a5),a0               ; the watches
	adda.w	d0,a0
	tst.b	(a0)                            ; any?
	beq.w	command_loop                    ; no
cursor_down_watch_end:
	addq.w	#1,d0
	tst.b	(a0)+                           ; to its end
	bne.s	cursor_down_watch_end
	tst.b	1(a0)                           ; another after it?
	beq.w	command_loop                    ; no
	move.w	d0,ws_watch(a5)                 ; the next
	bsr.w	draw_watches                    ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; cursor_up: the window a line back (4 bytes, or an instruction), or the watch before.
;------------------------------------------------------------------------------
cursor_up:	; from: key_table
	tst.b	ws_window(a5)                   ; the watches?
	beq.w	cursor_up_watch                 ; yes
	bsr.w	current_window                  ; the window
	beq.s	cursor_up_instruction           ; disassembly?
	subi.l	#$4,(a0)                        ; 4 bytes back
	bsr.w	draw_memory                     ; drawn
	bra.w	command_loop
cursor_up_instruction:	; from: page_up
	movea.l	(a0),a1
	bsr.w	instruction_back                ; back an instruction
	move.l	a1,(a0)
	bsr.w	draw_disassembly                ; drawn
	bra.w	command_loop
cursor_up_watch:
	move.w	ws_watch(a5),d0                 ; the watch
	beq.w	command_loop                    ; the first?
	lea	ws_watches(a5),a0               ; the watches
	adda.w	d0,a0
	subq.w	#1,a0
cursor_up_watch_start:
	subq.w	#1,a0
	subq.w	#1,d0
	beq.s	cursor_up_watch_set             ; the first
	tst.b	(a0)                            ; the one before's end?
	bne.s	cursor_up_watch_start           ; no
cursor_up_watch_set:
	move.w	d0,ws_watch(a5)
	bsr.w	draw_watches                    ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; page_down (Control down): the window from the address after its last line.
;------------------------------------------------------------------------------
page_down:	; from: key_table
	bsr.w	current_window                  ; the window
	beq.s	page_down_disassembly           ; disassembly?
	move.l	$10(a0),(a0)                    ; its end
	bsr.w	draw_memory                     ; drawn
	bra.w	command_loop
page_down_disassembly:
	move.l	$10(a0),(a0)                    ; its end
	bsr.w	draw_disassembly                ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; page_up (Control up): the window a page back (an instruction back from it for a disassembly).
;------------------------------------------------------------------------------
page_up:	; from: key_table
	bsr.w	current_window                  ; the window
	move.b	ws_window(a5),d0
	subq.w	#1,d0                           ; W1?
	beq.s	page_up_w1
	subq.w	#1,d0                           ; W2?
	beq.s	page_up_w2
	subq.w	#1,d0                           ; W3?
	beq.s	page_up_w3
	subq.w	#1,d0                           ; W4?
	beq.s	page_up_w4
	bra.w	command_loop
page_up_w2:
	subi.l	#$18,(a0)                       ; 6 lines
	tst.b	ws_w4_open(a5)                  ; split?
	bne.s	page_up_draw                    ; yes
	subi.l	#$14,(a0)                       ; 5 lines more
page_up_draw:
	bsr.w	draw_memory                     ; drawn
	bra.w	command_loop
page_up_w4:
	subi.l	#$14,(a0)                       ; 5 lines
	bra.s	page_up_draw
page_up_w1:
	subi.l	#$c,(a0)
	tst.b	ws_w3_open(a5)                  ; split?
	bne.s	page_up_w1_back                 ; yes
	subi.l	#$a,(a0)
page_up_w1_back:
	bra.w	cursor_up_instruction
page_up_w3:
	subi.l	#$14,(a0)
	bra.w	cursor_up_instruction

;------------------------------------------------------------------------------
; set_register (Alternate R): "Enter Register=Value > ".  A word register (SR) takes a word; the
; breakpoints and after cannot be set this way.
;------------------------------------------------------------------------------
set_register:	; from: key_table
	clr.b	ws_line(a5)                     ; the line empty
	moveq	#0,d2
set_register_edit:
	pea	set_register_bad(pc)            ; an error: back here
	move.l	sp,ws_error_stack(a5)           ; the stack for it
	lea	register_prompt(pc),a0          ; "$Enter Register=Value > "
	bsr.w	print_message
	bsr.w	edit_line                       ; the line edited
	bne.s	set_register_escape             ; escape
	lea	ws_line(a5),a0                  ; the line
	bsr.w	next_token                      ; spaces skipped
	bsr.w	read_name                       ; the name
	bne.w	expression_error                ; bad
	bsr.w	find_register                   ; the register
	bne.w	expression_error                ; not one
	lea	ws_breakpoints(a5),a2           ; the breakpoints
	cmpa.l	a2,a1                           ; a register?
	bcc.w	expression_error                ; no
	move.l	d1,-(sp)                        ; its size
	movea.l	a1,a2                           ; its place
	cmpi.w	#$3d,ws_token(a5)               ; '='?
	bne.w	expression_error                ; no
	bsr.w	evaluate_line                   ; the value
	bne.w	set_register_again              ; bad
	tst.w	ws_token(a5)                    ; the end of the line?
	bne.w	set_register_bad                ; no
	move.w	d0,(a2)                         ; a word
	move.l	(sp)+,d1
	bne.s	set_register_done               ; a word register?
	move.l	d0,(a2)                         ; no: a long
set_register_done:
	bsr.w	redraw_windows                  ; drawn
set_register_escape:
	bra.w	command_done
set_register_bad:
	bsr.w	flash_screen                    ; the error shown
set_register_again:
	lea	ws_line_next(a5),a3
	suba.l	a3,a0
	move.l	a0,d2                           ; the cursor
	movea.l	ws_error_stack(a5),sp
	bra.s	set_register_edit               ; edited again

;------------------------------------------------------------------------------
; set_label (Control L): "Enter Label=Value > ": a label in the label table set, or added at its end.
;------------------------------------------------------------------------------
set_label:	; from: key_table
	clr.b	ws_line(a5)                     ; the line empty
	moveq	#0,d2
	move.l	ws_symtab(a5),d0                ; the label table
	andi.l	#$fffffe,d0                     ; even
	beq.w	command_loop                    ; none: nothing
	move.l	d0,ws_symtab(a5)
set_label_edit:
	pea	set_label_bad(pc)               ; an error: back here
	move.l	sp,ws_error_stack(a5)           ; the stack for it
	lea	label_prompt(pc),a0             ; "Enter Label=Value > "
	bsr.w	print_message
	bsr.w	edit_line                       ; the line edited
	bne.s	set_label_escape                ; escape
	lea	ws_line(a5),a0                  ; the line
	bsr.w	next_token                      ; spaces skipped
	bsr.w	read_name                       ; the name
	bne.w	expression_error                ; bad
	bsr.w	find_register                   ; a register's name?
	beq.w	expression_error                ; yes: bad
	bsr.w	find_label                      ; in the table?
	beq.w	set_label_value                 ; yes
	lea	ws_name(a5),a2                  ; no: the name
	clr.l	(a1)                            ; added at the end
	clr.l	4(a1)
	moveq	#7,d1                           ; 8 characters
	movea.l	a1,a3
set_label_name:
	move.b	(a2)+,(a1)+                     ; copied
	dbeq	d1,set_label_name
	movea.l	a3,a1
set_label_value:
	lea	8(a1),a2                        ; its value
	cmpi.w	#$3d,ws_token(a5)               ; '='?
	bne.w	expression_error                ; no
	bsr.w	evaluate_line                   ; the value
	bne.w	set_label_again                 ; bad
	tst.w	ws_token(a5)                    ; the end of the line?
	bne.w	set_label_bad                   ; no
	move.l	d0,(a2)                         ; set
	bsr.w	draw_windows                    ; drawn
set_label_escape:
	bra.w	command_done
set_label_bad:
	bsr.w	flash_screen                    ; the error shown
set_label_again:
	lea	ws_line_next(a5),a3
	suba.l	a3,a0
	move.l	a0,d2                           ; the cursor
	movea.l	ws_error_stack(a5),sp
	bra.w	set_label_edit                  ; edited again

;------------------------------------------------------------------------------
; move_debugger (Control M): "Relocate DEBUGGER to > ": the code from monitor_restart to the font copied
; there and run, from its vectors' setting.
;------------------------------------------------------------------------------
move_debugger:	; from: key_table
	lea	relocate_prompt(pc),a4          ; "Relocate DEBUGGER to > "
	bsr.w	input_value                     ; the address
	bne.w	command_loop                    ; escape
	andi.l	#$fffffe,d0                     ; even
	movea.l	d0,a0
	lea	font_end(pc),a2                 ; the end
	lea	monitor_restart(pc),a1          ; the start
	move.l	a2,d0
	sub.l	a1,d0                           ; the length
	lsr.w	#2,d0                           ; in longs
	movea.l	a0,a2
move_debugger_long:
	move.l	(a1)+,(a0)+                     ; copied
	dbra	d0,move_debugger_long
	jmp	4(a2)                           ; run from setting the vectors

;------------------------------------------------------------------------------
; set_workspace (Control W): "Set DEBUGGER workspace > ": the workspace's first $400 bytes moved there (on a
; 256-byte boundary), then the screen drawn.
;------------------------------------------------------------------------------
set_workspace:	; from: key_table
	lea	workspace_prompt(pc),a4         ; "Set DEBUGGER workspace > "
	bsr.w	input_value                     ; the address
	bne.w	command_loop                    ; escape
	clr.b	d0                              ; on 256 bytes
	movea.l	d0,a0
	move.l	a0,$38.w                        ; the new workspace
	move.w	#$ff,d0                         ; 256 longs
set_workspace_long:
	move.l	(a5)+,(a0)+                     ; moved
	dbra	d0,set_workspace_long
	movea.l	$38.w,a5
	bsr.w	draw_frame                      ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; view_other_screen (V): the program's screen until a key.
;------------------------------------------------------------------------------
view_other_screen:	; from: key_table
	bsr.w	show_program_screen             ; the program's screen
	bsr.w	get_key                         ; a key
view_monitor_screen:	; from: always_view_other
	bsr.w	show_monitor_screen             ; the monitor's
	bra.w	command_loop

;------------------------------------------------------------------------------
; always_view_other (Alternate V): the program's screen kept up after each step, or not.
;------------------------------------------------------------------------------
always_view_other:	; from: key_table
	tst.b	ws_keep_program_screen(a5)      ; on?
	bne.s	view_monitor_screen             ; yes: off
	st	ws_keep_program_screen(a5)      ; on
	bsr.w	show_program_screen             ; the program's screen
	bra.w	command_loop

;------------------------------------------------------------------------------
; show_program_screen: the program's screen, palette and resolution back.
;------------------------------------------------------------------------------
show_program_screen:	; from: quit_monitor, step_over, run_program, view_other_screen, always_view_other
	movea.l	ws_vidptr(a5),a0                ; the program's screen pointer
	move.l	(a0),d0
	bsr.w	set_screen                      ; shown
	sf	ws_monitor_screen(a5)           ; the monitor's not shown
	move.l	ws_saved_palette(a5),$ffff8240.w ; palette 0, colours 0-1
	move.l	ws_saved_palette_high(a5),$ffff8244.w ; colours 2-3
	move.b	ws_saved_rez(a5),$ffff8260.w    ; shift mode, the resolution
	rts

;------------------------------------------------------------------------------
; show_monitor_screen: the monitor's screen (medium resolution, plane 0 only, white on black), with the
; program's palette and resolution kept.
;------------------------------------------------------------------------------
show_monitor_screen:	; from: view_other_screen, draw_frame, enter_monitor_saved
	sf	ws_keep_program_screen(a5)      ; not always the program's
	tst.b	ws_monitor_screen(a5)           ; shown already?
	bne.s	show_monitor_screen_set         ; yes
	st	ws_monitor_screen(a5)           ; shown
	move.b	$ffff8260.w,ws_saved_rez(a5)    ; shift mode, the program's resolution
	move.l	$ffff8240.w,ws_saved_palette(a5) ; palette 0, its colours 0-1
	move.l	$ffff8244.w,ws_saved_palette_high(a5) ; its colours 2-3
show_monitor_screen_set:
	lea	ws_screen(a5),a0                ; the monitor's screen
	move.l	a0,d0
	bsr.w	set_screen                      ; shown
	move.b	#$1,$ffff8260.w                 ; shift mode, medium resolution
	move.l	#$ffff,$ffff8240.w              ; palette 0, colour 0 black, the rest white
	move.l	#$ffffffff,$ffff8244.w
	rts

;------------------------------------------------------------------------------
; help (H): the list of commands until a key.
;------------------------------------------------------------------------------
help:	; from: key_table
	bsr.w	clear_screen                    ; the screen cleared
	lea	help_text(pc),a0                ; the help text
	bsr.w	print_text                      ; printed
	bsr.w	get_key                         ; a key
	bsr.w	draw_screen                     ; the screen drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; initialise_workspace (Alternate I): asks, then the workspace set up again.
;------------------------------------------------------------------------------
initialise_workspace:	; from: key_table
	lea	reinitialise_question(pc),a0    ; "Are you sure you want to reinitialise the workspace [Y/N] ? "
	bsr.w	ask_yes_no
	bsr.w	reinit_workspace
	bra.w	monitor_restart                 ; drawn

;------------------------------------------------------------------------------
; reinit_workspace: init_workspace with the label table and the program's screen pointer kept.
;------------------------------------------------------------------------------
reinit_workspace:	; from: initialise_workspace, enter_monitor_saved
	movem.l	d0-d7/a0-a4,-(sp)               ; saved
	movea.l	a5,a0                           ; the workspace
	movea.l	ws_symtab(a5),a1                ; the label table
	movea.l	ws_vidptr(a5),a2                ; the screen pointer
	bsr.w	init_workspace
	movem.l	(sp)+,d0-d7/a0-a4
	rts

;------------------------------------------------------------------------------
; ask_yes_no: the question a0; returns on Y, goes back to the command loop on N, escape or ^C.
;------------------------------------------------------------------------------
ask_yes_no:	; from: quit_monitor, go_download, run_program, initialise_workspace, format_disk, load_bootsector
	bsr.w	print_message                   ; the question
ask_yes_no_key:
	bsr.w	get_key_cursor                  ; a key
	bsr.w	to_capitals                     ; in capitals
	cmp.w	#$59,d0                         ; 'Y'?
	beq.s	ask_yes_no_yes                  ; yes
	cmp.w	#$4e,d0                         ; 'N'?
	beq.s	ask_yes_no_no
	cmp.b	#$1b,d0                         ; escape?
	beq.s	ask_yes_no_no
	cmp.w	#$243,d0                        ; ^C?
	bne.s	ask_yes_no_key                  ; no: another key
ask_yes_no_no:
	bra.w	command_done
ask_yes_no_yes:
	rts

;------------------------------------------------------------------------------
; edit_memory (Alternate E): in a memory window, hex digits typed over the longs shown, the cursor keys to move;
; Return keeps the long, escape leaves.  With the watches it edits the current watch.
;------------------------------------------------------------------------------
edit_memory:	; from: key_table
	tst.b	ws_window(a5)                   ; the watches?
	beq.w	edit_watch                      ; yes: edit the watch
	bsr.w	current_window                  ; the window
	beq.w	command_loop                    ; disassembly: no
	movea.l	(a0),a2                         ; its base
	movea.l	a0,a6
	lea	edit_memory_fault(pc),a0        ; a fault: "Edit aborted ..."
	move.l	a0,ws_fault(a5)
	lea	edit_memory_text(pc),a0         ; "Enter hexadecimal and then RETURN to accept or ESCAPE to abort."
	bsr.w	print_message
	movea.w	#$b,a3                          ; row 11
	movea.w	#$b,a4                          ; 12 lines
	tst.b	ws_w4_open(a5)                  ; split?
	beq.s	edit_memory_start               ; no
	movea.w	#$5,a4                          ; 6 lines
	cmpi.b	#$2,ws_window(a5)               ; W2?
	beq.s	edit_memory_start               ; yes
	movea.w	#$4,a4                          ; W4: 5 lines
	movea.w	#$12,a3                         ; from row 18
edit_memory_start:
	moveq	#0,d2                           ; the digit
	moveq	#0,d3                           ; the line
edit_memory_long:	; from: edit_memory_write
	movea.l	a2,a1
	move.b	(a1)+,d0                        ; the long, by bytes
	lsl.w	#8,d0
	move.b	(a1)+,d0
	swap	d0
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	move.l	d0,ws_scratch(a5)               ; being edited
edit_memory_key:	; from: edit_memory_write
	move.w	a3,d0                           ; the row
	add.w	d3,d0                           ; + the line
	move.w	d0,ws_row(a5)
	moveq	#65,d0                          ; column 65
	lea	digit_columns(pc),a0            ; + the digit's column
	add.b	0(a0,d2.w),d0
	move.w	d0,ws_column(a5)
	bsr.w	get_key_cursor                  ; a key
	cmp.b	#$1b,d0                         ; escape?
	beq.w	edit_memory_done                ; yes
	cmp.w	#$243,d0                        ; ^C?
	beq.w	edit_memory_done                ; yes
	cmp.w	#$3,d0                          ; left?
	beq.w	edit_memory_left
	cmp.w	#$4,d0                          ; right?
	beq.w	edit_memory_right
	cmp.w	#$2,d0                          ; down?
	beq.w	edit_memory_down
	cmp.w	#$1,d0                          ; up?
	beq.w	edit_memory_up
	cmp.w	#$d,d0                          ; Return?
	beq.s	edit_memory_return              ; yes
	bsr.w	to_capitals                     ; in capitals
	move.l	d0,d6
	cmp.w	#$30,d0                         ; '0'-'9'?
	bcs.s	edit_memory_key
	cmp.w	#$39,d0
	bls.s	edit_memory_digit
	cmp.w	#$41,d0                         ; 'A'-'F'?
	bcs.s	edit_memory_key
	cmp.w	#$46,d0
	bhi.s	edit_memory_key
	subq.w	#7,d0                           ; to 10-15
edit_memory_digit:
	andi.l	#$f,d0
	ror.l	#4,d0                           ; to the top
	move.l	#$fffffff,d4                    ; the mask
	move.w	d2,d1
	lsl.w	#2,d1                           ; its place
	ror.l	d1,d4
	lsr.l	d1,d0
	move.l	ws_scratch(a5),d5               ; the long
	and.l	d4,d5                           ; the digit out
	or.l	d0,d5                           ; the new one in
	move.l	d5,ws_scratch(a5)
	move.l	d6,d0
	bsr.w	print_char                      ; shown
	bra.s	edit_memory_right               ; the next digit
edit_memory_return:
	bsr.w	edit_memory_write               ; the long written
edit_memory_done:
	bsr.w	draw_windows                    ; drawn
	bra.w	command_done

;------------------------------------------------------------------------------
; edit_memory_write: the long being edited written at a2 by bytes, and the windows drawn.
;------------------------------------------------------------------------------
edit_memory_write:	; from: edit_memory
	move.l	ws_scratch(a5),d0
	movea.l	a2,a1
	rol.l	#8,d0
	move.b	d0,(a1)+
	rol.l	#8,d0
	move.b	d0,(a1)+
	rol.l	#8,d0
	move.b	d0,(a1)+
	rol.l	#8,d0
	move.b	d0,(a1)+
	movem.l	d2-d3/a2,-(sp)                  ; saved
	bsr.w	draw_memory                     ; drawn
	bsr.w	draw_disassembly
	movem.l	(sp)+,d2-d3/a2
	rts
edit_memory_fault:	; from: edit_memory
	lea	edit_fault_text(pc),a0          ; "Edit aborted due to BUS/ADDRESS error"
	bsr.w	print_message
	bsr.w	redraw_windows                  ; drawn
	bra.w	command_loop
edit_memory_left:	; from: edit_memory
	subq.w	#1,d2                           ; the digit before
	bpl.w	edit_memory_key
	moveq	#7,d2                           ; the last
	bra.s	edit_memory_up                  ; of the line before
edit_memory_right:	; from: edit_memory
	addq.w	#1,d2                           ; the next digit
	cmp.w	#$8,d2
	bcs.w	edit_memory_key
	moveq	#0,d2                           ; the first
	bra.s	edit_memory_down                ; of the next line
edit_memory_up:	; from: edit_memory
	bsr.w	edit_memory_write               ; kept
	subq.w	#4,a2                           ; the long before
	subq.w	#1,d3                           ; the line before
	bpl.w	edit_memory_long
	moveq	#0,d3                           ; the top: the window back
	move.l	a2,(a6)
	bra.s	edit_memory_scroll
edit_memory_down:	; from: edit_memory
	bsr.w	edit_memory_write               ; kept
	addq.w	#4,a2                           ; the next long
	addq.w	#1,d3                           ; the next line
	cmp.w	a4,d3                           ; the last?
	bls.w	edit_memory_long                ; no
	move.w	a4,d3                           ; the bottom: the window on
	addi.l	#$4,(a6)
edit_memory_scroll:
	movem.l	d2-d3/a2,-(sp)                  ; saved
	bsr.w	draw_memory                     ; drawn
	movem.l	(sp)+,d2-d3/a2
	bra.w	edit_memory_long

;------------------------------------------------------------------------------
; digit_columns: each hex digit's column from 65 (a space after the fourth).
;------------------------------------------------------------------------------
digit_columns:	; from: edit_memory
	dc.w	$0001,$0203,$0506,$0708

;------------------------------------------------------------------------------
; add_watch (Alternate W): "Add Watch > ": a watch put before the current one.
;------------------------------------------------------------------------------
add_watch:	; from: key_table
	lea	add_watch_prompt(pc),a4         ; "Add Watch > "
	clr.b	ws_line(a5)                     ; the line empty
	sf	ws_watch_editing(a5)            ; adding
	bra.s	watch_input

;------------------------------------------------------------------------------
; edit_watch: "Edit Watch > " with the current watch, which the new one takes the place of.
;------------------------------------------------------------------------------
edit_watch:	; from: edit_memory
	lea	edit_watch_prompt(pc),a4        ; "Edit Watch > "
	st	ws_watch_editing(a5)            ; editing
	lea	ws_watches(a5),a1               ; the watches
	lea	ws_line(a5),a2                  ; the line
	adda.w	ws_watch(a5),a1                 ; the current one
edit_watch_copy:
	move.b	(a1)+,(a2)+                     ; into the line
	tst.b	-$1(a2)
	bne.s	edit_watch_copy
watch_input:	; from: add_watch
	moveq	#0,d2
watch_input_edit:
	movea.l	a4,a0                           ; the prompt
	bsr.w	print_message
	bsr.w	edit_line                       ; the line edited
	bsr.w	clear_message                   ; the message line cleared
	tst.w	d0                              ; escape?
	bne.w	command_loop                    ; yes
	lea	ws_line(a5),a0                  ; the line
	tst.b	(a0)                            ; empty?
	beq.s	watch_input_done                ; yes
	st	ws_watch_check_only(a5)         ; checking only
	bsr.w	draw_watch                      ; the watch tried
	bne.s	watch_input_bad                 ; bad
	tst.b	ws_watch_editing(a5)            ; editing?
	beq.s	watch_input_insert              ; no
	bsr.w	remove_watch                    ; the old one out
watch_input_insert:
	lea	ws_line(a5),a0                  ; the line
	moveq	#0,d1
watch_input_length:
	addq.w	#1,d1                           ; its length
	tst.b	(a0)+
	bne.s	watch_input_length
	bsr.w	watches_length                  ; the watches' length
	add.w	d1,d0                           ; with the new one
	cmp.w	#$100,d0                        ; over 256?
	bcc.s	watch_full                      ; yes
	bsr.w	watches_length                  ; the watches' length
	lea	ws_watches(a5),a1               ; the watches
	lea	ws_line(a5),a0                  ; the line
	lea	0(a1,d0.w),a2                   ; their end
	adda.w	ws_watch(a5),a1                 ; the current one
	lea	0(a2,d1.w),a3                   ; the new end
	clr.b	(a3)                            ; two zeros
	clr.b	1(a3)
	bra.s	watch_input_moved
watch_input_move:
	move.b	-(a2),-(a3)                     ; moved up
watch_input_moved:
	cmpa.l	a2,a1
	bne.s	watch_input_move
	bra.s	watch_input_copied
watch_input_copy:
	move.b	(a0)+,(a1)+                     ; the new one in
watch_input_copied:
	dbra	d1,watch_input_copy
watch_input_done:
	bsr.w	draw_watches                    ; the watches drawn
	bra.w	command_loop
watch_input_bad:
	bsr.w	flash_screen                    ; the error shown
	lea	ws_line_next(a5),a1
	suba.l	a1,a0
	move.l	a0,d2                           ; the cursor
	bra.w	watch_input_edit                ; edited again
watch_full:
	lea	watch_full_text(pc),a0          ; "The WATCH buffer is full, line deleted!"
	bsr.w	print_message
	bra.w	command_loop

;------------------------------------------------------------------------------
; watches_length: d0 = the watches' length, to their double zero.
;------------------------------------------------------------------------------
watches_length:	; from: edit_watch
	moveq	#0,d0
	lea	ws_watches(a5),a2               ; the watches
watches_length_byte:
	tst.b	(a2)                            ; the end of one?
	beq.s	watches_length_end              ; yes
	addq.w	#1,a2
	addq.w	#1,d0
	bra.s	watches_length_byte
watches_length_end:
	addq.w	#1,a2
	addq.w	#1,d0
	tst.b	(a2)                            ; the end of all?
	beq.s	watches_length_done             ; yes
	bne.s	watches_length_byte             ; no: on
	addq.w	#1,a2
	addq.w	#1,d0
	bra.s	watches_length_byte
watches_length_done:
	rts

;------------------------------------------------------------------------------
; delete_watch (Alternate D): the current watch deleted.
;------------------------------------------------------------------------------
delete_watch:	; from: key_table
	bsr.w	remove_watch                    ; deleted
	bsr.w	draw_watches                    ; drawn
	bra.w	command_loop

;------------------------------------------------------------------------------
; remove_watch: the current watch taken out of the watches.
;------------------------------------------------------------------------------
remove_watch:	; from: edit_watch, delete_watch
	movem.l	d0-d1/a0-a2,-(sp)               ; saved
	lea	ws_watches(a5),a0               ; the watches
	adda.w	ws_watch(a5),a0                 ; the current one
	tst.b	(a0)                            ; any?
	beq.s	remove_watch_done               ; no
	movea.l	a0,a1
remove_watch_end:
	tst.b	(a1)+                           ; to its end
	bne.s	remove_watch_end
remove_watch_move:
	tst.b	(a1)                            ; the next
	beq.s	remove_watch_moved
	move.b	(a1)+,(a0)+                     ; moved down
	bra.s	remove_watch_move
remove_watch_moved:
	move.b	(a1)+,(a0)+
	tst.b	(a1)                            ; the end?
	bne.s	remove_watch_move               ; no
	clr.b	(a0)+
remove_watch_done:
	movem.l	(sp)+,d0-d1/a0-a2
	rts

;------------------------------------------------------------------------------
; zoom_window (Z): the window on the whole screen, a memory dump of 28 lines or a disassembly of 28, moved with
; the cursor keys (Control for pages) until escape.
;------------------------------------------------------------------------------
zoom_window:	; from: key_table
	bsr.w	current_window                  ; the window
	beq.w	zoom_disassembly                ; disassembly?
	movea.l	(a0),a1                         ; its base
	lea	zoom_rows(pc),a0                ; the zoom's line table
	move.l	a0,ws_rows(a5)
	bsr.w	clear_screen                    ; the screen cleared
zoom_memory:
	moveq	#27,d2                          ; 28 lines
	moveq	#0,d3
	move.l	a1,-(sp)                        ; kept
zoom_memory_line:
	movea.l	a1,a2
	move.w	d3,ws_row(a5)                   ; the row
	clr.w	ws_column(a5)                   ; the column
	move.l	a1,d0                           ; the address
	bsr.w	print_hex_long                  ; printed
	moveq	#7,d1                           ; 8 words
zoom_memory_word:
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word                  ; printed
	dbra	d1,zoom_memory_word
	movea.l	a2,a1
	moveq	#15,d1                          ; 16 characters
zoom_memory_char:
	move.b	(a1)+,d0
	bsr.w	print_char_dot                  ; printed
	dbra	d1,zoom_memory_char
	addq.w	#1,d3                           ; the next line
	dbra	d2,zoom_memory_line
	movea.l	(sp)+,a1
zoom_memory_key:
	bsr.w	get_key                         ; a key
	andi.w	#$feff,d0                       ; not Alternate
	cmp.w	#$d,d0                          ; Return?
	beq.s	zoom_memory_page_down
	cmp.w	#$20,d0                         ; Space?
	beq.s	zoom_memory_page_down
	cmp.w	#$202,d0                        ; Control down?
	beq.s	zoom_memory_page_down
	cmp.w	#$201,d0                        ; Control up?
	beq.s	zoom_memory_page_up
	cmp.w	#$2,d0                          ; down?
	beq.s	zoom_memory_down
	cmp.w	#$1,d0                          ; up?
	beq.s	zoom_memory_up
	cmp.w	#$4,d0                          ; right?
	beq.s	zoom_memory_right
	cmp.w	#$3,d0                          ; left?
	beq.s	zoom_memory_left
	cmp.b	#$1b,d0                         ; escape?
	beq.s	zoom_done
	cmp.w	#$243,d0                        ; ^C?
	bne.s	zoom_memory_key                 ; no: another key
zoom_done:
	bsr.w	draw_frame                      ; the screen drawn
	bra.w	command_loop
zoom_memory_page_down:
	adda.w	#$1b0,a1                        ; 27 lines on
	bra.w	zoom_memory
zoom_memory_down:
	adda.w	#$10,a1                         ; a line on
	bra.w	zoom_memory
zoom_memory_right:
	addq.w	#1,a1                           ; a byte on
	bra.w	zoom_memory
zoom_memory_up:
	suba.w	#$10,a1                         ; a line back
	bra.w	zoom_memory
zoom_memory_page_up:
	suba.w	#$1b0,a1                        ; 27 lines back
	bra.w	zoom_memory
zoom_memory_left:
	subq.w	#1,a1                           ; a byte back
	bra.w	zoom_memory
zoom_disassembly:
	movea.l	(a0),a1                         ; its base
	bsr.w	clear_screen                    ; the screen cleared
	lea	zoom_rows(pc),a0                ; the zoom's line table
	move.l	a0,ws_rows(a5)
zoom_disassembly_draw:
	moveq	#27,d2                          ; 28 lines
	moveq	#0,d1
	moveq	#20,d7
	movea.l	a1,a2
	bsr.w	draw_disassembly_line           ; drawn
	movea.l	a1,a3                           ; the next page
zoom_disassembly_key:
	bsr.w	get_key                         ; a key
	andi.w	#$feff,d0                       ; not Alternate
	cmp.w	#$d,d0                          ; Return?
	beq.s	zoom_disassembly_page_down
	cmp.w	#$20,d0                         ; Space?
	beq.s	zoom_disassembly_page_down
	cmp.w	#$202,d0                        ; Control down?
	beq.s	zoom_disassembly_page_down
	cmp.w	#$201,d0                        ; Control up?
	beq.s	zoom_disassembly_page_up
	cmp.w	#$2,d0                          ; down?
	beq.s	zoom_disassembly_down
	cmp.w	#$1,d0                          ; up?
	beq.s	zoom_disassembly_up
	cmp.w	#$4,d0                          ; right?
	beq.s	zoom_disassembly_right
	cmp.w	#$3,d0                          ; left?
	beq.s	zoom_disassembly_left
	cmp.b	#$1b,d0                         ; escape?
	beq.s	zoom_disassembly_done
	cmp.w	#$243,d0                        ; ^C?
	bne.s	zoom_disassembly_key            ; no: another key
zoom_disassembly_done:
	bsr.w	draw_frame                      ; the screen drawn
	bra.w	command_loop
zoom_disassembly_page_down:
	movea.l	a3,a1                           ; the next page
	bra.s	zoom_disassembly_draw
zoom_disassembly_down:
	movea.l	a2,a1
	bsr.w	disassemble                     ; an instruction on
	bra.s	zoom_disassembly_draw
zoom_disassembly_up:
	movea.l	a2,a1
zoom_disassembly_back:
	bsr.s	instruction_back                ; an instruction back
	bra.s	zoom_disassembly_draw
zoom_disassembly_left:
	lea	-$2(a2),a1                      ; a word back
	bra.s	zoom_disassembly_draw
zoom_disassembly_right:
	lea	2(a2),a1                        ; a word on
	bra.s	zoom_disassembly_draw
zoom_disassembly_page_up:
	movea.l	a2,a1
	suba.l	#$3c,a1                         ; $3c bytes back
	bra.s	zoom_disassembly_back           ; then an instruction back

;------------------------------------------------------------------------------
; instruction_back: a1 an instruction back: of the five words before, the furthest whose instruction ends at
; a1 (and decodes), or the word before.
;------------------------------------------------------------------------------
instruction_back:	; from: cursor_up, zoom_window
	move.l	a1,d2                           ; where it must end
	lea	-$2(a1),a3                      ; the word before, if none
	moveq	#4,d4                           ; 5 words
instruction_back_try:
	subq.w	#2,a1                           ; a word back
	movea.l	a1,a2
	bsr.w	disassemble                     ; its length
	move.l	a1,d0                           ; its end
	movea.l	a2,a1
	tst.b	ws_bad_instruction(a5)          ; bad?
	bne.s	instruction_back_next           ; yes
	cmp.l	d2,d0                           ; ends at a1?
	bne.s	instruction_back_next           ; no
	movea.l	a1,a3                           ; this one
instruction_back_next:
	dbra	d4,instruction_back_try
	movea.l	d2,a1
	movea.l	a3,a1                           ; the one found
	rts

;------------------------------------------------------------------------------
; split_window (Alternate S): W1 or W2 split in two (W3 or W4 shown under it), or joined again.
;------------------------------------------------------------------------------
split_window:	; from: key_table
	bsr.w	current_window                  ; the window
	beq.w	split_window_disassembly        ; disassembly?
	move.b	#$4,ws_window(a5)               ; W4
	not.b	ws_w4_open(a5)                  ; W4 open or closed
	bne.s	split_window_memory             ; open
	move.b	#$2,ws_window(a5)               ; closed: back to W2
split_window_memory:
	bsr.w	draw_memory                     ; drawn
split_window_titles:
	bsr.w	draw_lower_frame                ; the frame
	bsr.w	draw_titles                     ; the titles
	bra.w	command_loop
split_window_disassembly:
	move.b	#$3,ws_window(a5)               ; W3
	not.b	ws_w3_open(a5)                  ; W3 open or closed
	bne.s	split_window_disassembly_draw   ; open
	move.b	#$1,ws_window(a5)               ; closed: back to W1
split_window_disassembly_draw:
	bsr.w	draw_disassembly                ; drawn
	bra.s	split_window_titles

;------------------------------------------------------------------------------
; lock_window (Alternate L): "Lock window to register > ": the window follows the register (none to unlock).
;------------------------------------------------------------------------------
lock_window:	; from: key_table
	clr.l	d0
	move.b	ws_window(a5),d0                ; the window
	subq.b	#1,d0
	bmi.w	command_loop                    ; the watches: no
	lea	lock_prompt(pc),a0              ; "Lock window to register > "
	bsr.w	print_message
	bsr.w	input_line                      ; the line
	bne.s	lock_window_done                ; escape
	lea	ws_line(a5),a0                  ; the line
	bsr.w	next_token                      ; spaces skipped
	moveq	#0,d2                           ; none: unlocked
	tst.w	ws_token(a5)                    ; empty?
	beq.s	lock_window_set                 ; yes
	bsr.w	read_name                       ; the name
	bne.s	lock_window_bad                 ; bad
	bsr.w	find_register                   ; the register
	bne.s	lock_window_bad                 ; not one
	tst.w	d1                              ; a word register?
	bne.s	lock_window_bad                 ; yes: no
	tst.w	ws_token(a5)                    ; the end?
	bne.s	lock_window_bad                 ; no
lock_window_set:
	clr.b	d0
	move.b	ws_window(a5),d0                ; the window
	subq.w	#1,d0
	move.b	d2,$69(a5,d0.w)                 ; its register (0: none)
lock_window_done:
	bsr.w	draw_titles                     ; the titles
	bsr.w	redraw_windows                  ; drawn
	bra.w	command_done
lock_window_bad:
	bsr.w	flash_screen                    ; the error shown
command_escape:	; from: binary_load_save, load_executable, input_file_values
	bra.w	command_done

;------------------------------------------------------------------------------
; binary_load_save (B): "Binary Load/Save [L/S] ? ", then the file through GEMDOS (interrupts on while it runs).
;------------------------------------------------------------------------------
binary_load_save:	; from: key_table
	lea	binary_question(pc),a0          ; "Binary Load/Save [L/S] ? "
	bsr.w	print_message
binary_load_save_key:
	bsr.w	get_key_cursor                  ; a key
	bsr.w	to_capitals                     ; in capitals
	cmp.b	#$1b,d0                         ; escape?
	beq.w	command_escape                  ; yes
	cmp.w	#$4c,d0                         ; 'L'?
	beq.s	binary_load                     ; yes
	cmp.w	#$53,d0                         ; 'S'?
	bne.s	binary_load_save_key            ; no: another key
	lea	binary_save_prompt(pc),a4       ; "Binary Save File,start,length > "
	st	ws_stepping(a5)                 ; three values
	bsr.w	input_file_values               ; the name, start and length
	move.w	#$0,-(sp)                       ; normal file
	move.l	a0,-(sp)                        ; the name
	move.w	#$3c,-(sp)                      ; Fcreate
	move.w	#$2300,sr                       ; interrupts on
	trap	#1                              ; GEMDOS
	move.w	#$2700,sr                       ; interrupts off
	addq.w	#8,sp
	move.w	d0,ws_scratch(a5)               ; the handle
	bmi.w	binary_open_failed              ; "Cannot open file"
	move.l	d4,-(sp)                        ; the start
	move.l	d5,-(sp)                        ; the length
	move.w	ws_scratch(a5),-(sp)            ; the handle
	move.w	#$40,-(sp)                      ; Fwrite
	move.w	#$2300,sr                       ; interrupts on
	trap	#1                              ; GEMDOS
	move.w	#$2700,sr                       ; interrupts off
	adda.w	#$c,sp
	tst.l	d0                              ; written?
	bmi.w	binary_write_failed             ; no: "Cannot write to file"
	bra.s	binary_close                    ; closed
binary_load:
	lea	binary_load_prompt(pc),a4       ; "Binary Load File,start > "
	sf	ws_stepping(a5)                 ; two values
	bsr.w	input_file_values               ; the name and start
	move.w	#$0,-(sp)                       ; read
	move.l	a0,-(sp)                        ; the name
	move.w	#$3d,-(sp)                      ; Fopen
	move.w	#$2300,sr                       ; interrupts on
	trap	#1                              ; GEMDOS
	move.w	#$2700,sr                       ; interrupts off
	addq.w	#8,sp
	move.w	d0,ws_scratch(a5)               ; the handle
	bmi.s	binary_open_failed              ; "Cannot open file"
	move.l	d4,-(sp)                        ; the start
	move.l	#$100000,-(sp)                  ; up to 1 Mb
	move.w	ws_scratch(a5),-(sp)            ; the handle
	move.w	#$3f,-(sp)                      ; Fread
	move.w	#$2300,sr                       ; interrupts on
	trap	#1                              ; GEMDOS
	move.w	#$2700,sr                       ; interrupts off
	adda.w	#$c,sp
	tst.l	d0                              ; read?
	bmi.s	binary_read_failed              ; no: "Cannot read from file"
binary_close:
	move.w	ws_scratch(a5),-(sp)            ; the handle
	move.w	#$3e,-(sp)                      ; Fclose
	move.w	#$2300,sr                       ; interrupts on
	trap	#1                              ; GEMDOS
	move.w	#$2700,sr                       ; interrupts off
	bsr.w	draw_windows                    ; drawn
	bra.w	command_done
binary_open_failed:
	lea	open_failed_text(pc),a0         ; "Cannot open file"
	bsr.w	print_message
	bra.w	command_loop
binary_read_failed:
	lea	read_failed_text(pc),a0         ; "Cannot read from file"
	bsr.w	print_message
	bra.s	binary_close
binary_write_failed:
	lea	write_failed_text(pc),a0        ; "Cannot write to file"
	bsr.w	print_message
	bra.s	binary_close
load_failed:	; from: load_executable
	lea	load_failed_text(pc),a0         ; "Cannot load executable file"
	bsr.w	print_message
	bra.w	command_loop

;------------------------------------------------------------------------------
; load_executable: "Load an Executable File > ": Pexec 3 (load, don't go), pc at its text, the basepage's
; addresses kept as TEXT, DATA and BSS, the memory shrunk to it, and a user stack at its end with a return
; into trap #15.  Not in key_table, so not reached.
;------------------------------------------------------------------------------
load_executable:
	lea	executable_prompt(pc),a0        ; "Load an Executable File > "
	bsr.w	print_message
	bsr.w	input_line                      ; the line
	bne.w	command_escape                  ; escape
	lea	ws_line(a5),a0                  ; the line
load_executable_skip:
	cmpi.b	#$20,(a0)                       ; a space?
	bne.s	load_executable_go              ; no
	addq.w	#1,a0                           ; skipped
	bra.s	load_executable_skip
load_executable_go:
	clr.l	-(sp)                           ; no environment
	move.l	a0,-(sp)                        ; no command line (the name)
	move.l	a0,-(sp)                        ; the name
	move.w	#$3,-(sp)                       ; load, don't go
	move.w	#$4b,-(sp)                      ; Pexec
	move.w	#$2300,sr                       ; interrupts on
	trap	#1                              ; GEMDOS
	move.w	#$2700,sr                       ; interrupts off
	adda.w	#$10,sp
	tst.l	d0                              ; loaded?
	bmi.w	load_failed                     ; no
	movea.l	d0,a0                           ; its basepage
	move.l	8(a0),ws_text(a5)               ; TEXT
	move.l	8(a0),ws_pc(a5)                 ; pc
	move.l	$10(a0),ws_data(a5)             ; DATA
	move.l	$18(a0),ws_bss(a5)              ; BSS
	move.l	$c(a0),d0                       ; its text length
	add.l	$14(a0),d0                      ; + its data length
	add.l	$1c(a0),d0                      ; + its bss length
	addi.l	#$100,d0                        ; + the basepage
	move.l	d0,-(sp)
	move.l	a0,-(sp)                        ; the basepage
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink, GEMDOS
	addq.w	#4,sp
	movea.l	(sp)+,a0
	move.l	(sp)+,d0
	lea	0(a0,d0.l),a1                   ; its end
	move.l	a0,-(a1)                        ; the basepage
	lea	program_return(pc),a0           ; the return
	move.l	a0,-(a1)                        ; pushed
	move.l	a1,ws_usp(a5)                   ; the user stack
	bsr.w	redraw_windows                  ; drawn
	bra.w	command_done

;------------------------------------------------------------------------------
; program_return: where a program loaded with load_executable returns: the monitor.
;------------------------------------------------------------------------------
program_return:	; from: load_executable
	trap	#15

;------------------------------------------------------------------------------
; input_file_values: the prompt a4, then "name,start[,length]" (the length when ws_stepping is set):
; the name into ws_file_name, a0 = it, d4 = start, d5 = length.  A bad value puts the cursor on it to edit.
;------------------------------------------------------------------------------
input_file_values:	; from: binary_load_save, input_name_start_length
	movea.l	a4,a0                           ; the prompt
	bsr.w	print_message
	lea	command_fault(pc),a0            ; a fault: "Command aborted ..."
	move.l	a0,ws_fault(a5)
	clr.b	ws_line(a5)                     ; the line empty
	moveq	#0,d2
	move.w	ws_column(a5),ws_scratch(a5)    ; the column kept
input_file_values_edit:
	move.w	ws_scratch(a5),ws_column(a5)
	bsr.w	edit_line                       ; the line edited
	bne.w	command_escape                  ; escape
	lea	ws_line(a5),a0                  ; the line
	move.w	#$20,ws_token(a5)               ; the separator a space
	lea	ws_file_name(a5),a2             ; the name
	moveq	#32,d1                          ; 33 characters
input_file_values_name:
	bsr.w	next_token                      ; a character
	cmp.b	#$2c,d0                         ; ','?
	beq.s	input_file_values_start         ; yes: the name's end
	move.b	d0,(a2)+
	dbra	d1,input_file_values_name
	bra.s	input_file_values_bad           ; too long
input_file_values_start:
	clr.b	(a2)                            ; ended
	bsr.w	evaluate_next                   ; the start
	tst.b	ws_value_error(a5)              ; bad?
	bne.s	input_file_values_bad           ; yes
	move.l	d0,d4
	tst.b	ws_stepping(a5)                 ; a length too?
	beq.s	input_file_values_end           ; no
	cmpi.w	#$2c,ws_token(a5)               ; ','?
	bne.s	input_file_values_bad           ; no
	bsr.w	evaluate_next                   ; the length
	tst.b	ws_value_error(a5)              ; bad?
	bne.s	input_file_values_bad           ; yes
	move.l	d0,d5
input_file_values_end:
	tst.w	ws_token(a5)                    ; the end of the line?
	bne.s	input_file_values_bad           ; no
	lea	ws_file_name(a5),a0             ; the name
	moveq	#0,d0                           ; Z: all there
	rts
input_file_values_bad:
	bsr.w	flash_screen                    ; the error shown
	lea	ws_line_next(a5),a1
	suba.l	a1,a0
	move.l	a0,d2                           ; the cursor
	bra.w	input_file_values_edit          ; edited again

;------------------------------------------------------------------------------
; input_name_start_length: input_file_values with a length.
;------------------------------------------------------------------------------
input_name_start_length:	; from: write_sectors, read_sectors, write_file
	st	ws_stepping(a5)                 ; three values
	bsr.w	input_file_values
	rts

;------------------------------------------------------------------------------
; write_sectors (F5): "name,start,length": the memory from start written to drive A from logical sector 10,
; double sided, 10 sectors a track (the name is not used).
;------------------------------------------------------------------------------
write_sectors:	; from: key_table
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	lea	dma_write_prompt(pc),a4         ; "DMA Write - Filename,start,length > "
	bsr.w	input_name_start_length
	movea.l	a0,a4
	move.l	d4,$ea008                       ; the start
	divu.w	#$200,d5                        ; the sectors
	addq.w	#1,d5                           ; and a part
	move.w	d5,$ea00c
	moveq	#8,d0                           ; drive A, double sided, 10 sectors a track
	moveq	#10,d1                          ; sector 10
	move.w	$ea00c,d2                       ; the count
	move.l	#$8001,d3                       ; write
	movea.l	$ea008,a0                       ; the start
	bsr.w	floppy_io                       ; written
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	movem.l	(sp)+,d0-d7/a0-a6
	bsr.w	clear_message                   ; the message line cleared
	bra.w	command_loop

;------------------------------------------------------------------------------
; read_sectors (F4): "name,start,length": drive A from logical sector 10 read into memory from start.
;------------------------------------------------------------------------------
read_sectors:	; from: key_table
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	lea	dma_read_prompt(pc),a4          ; "DMA Read - Filename,start,length > "
	bsr.w	input_name_start_length
	movea.l	a0,a4
	move.l	d4,$ea008                       ; the start
	divu.w	#$200,d5                        ; the sectors
	addq.w	#1,d5                           ; and a part
	move.w	d5,$ea00c
	moveq	#8,d0                           ; drive A, double sided, 10 sectors a track
	moveq	#10,d1                          ; sector 10
	move.w	$ea00c,d2                       ; the count
	move.l	#$8000,d3                       ; read
	movea.l	$ea008,a0                       ; the start
	bsr.w	floppy_io                       ; read
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	movem.l	(sp)+,d0-d7/a0-a6
	bsr.w	clear_message                   ; the message line cleared
	bra.w	command_loop

;------------------------------------------------------------------------------
; write_file (F7): "name,start,length": the memory written as a file named name onto the disk in drive A,
; which must be 10 sectors a track and double sided (as *F formats it).  The FAT is read and unpacked to
; words, free clusters taken in order, the clusters written, the directory entry and the FAT written back.
; Its buffers are at $F0000-$F7FFF.
;------------------------------------------------------------------------------
write_file:	; from: key_table
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	lea	dma_write_prompt(pc),a4         ; "DMA Write - Filename,start,length > "
	lea	ws_file_length(a5),a0           ; the file's details
	move.w	#$a,d0                          ; 11 longs
write_file_clear:
	clr.l	(a0)+                           ; cleared
	dbra	d0,write_file_clear
	bsr.w	input_name_start_length         ; name, start, length
	move.l	(a0)+,ws_dos_name(a5)           ; the name, 12 bytes
	move.l	(a0)+,ws_dos_name_middle(a5)
	move.l	(a0)+,ws_dos_name_end(a5)
	move.l	d4,ws_file_start(a5)            ; the start
	move.l	d5,ws_file_length(a5)           ; the length
	divu.w	#$200,d5                        ; sectors
	swap	d5                              ; a part?
	cmp.w	#$0,d5
	beq.w	write_file_exact                ; no
	swap	d5
	addq.l	#1,d5                           ; one more
	bra.w	write_file_sectors
write_file_exact:
	swap	d5
write_file_sectors:
	move.w	d5,ws_file_sectors(a5)          ; the sectors
	lea	$f0000,a0                       ; the boot sector's buffer
	moveq	#8,d0                           ; drive A, double sided
	moveq	#0,d1                           ; sector 0
	moveq	#1,d2                           ; 1
	moveq	#0,d3                           ; read
	bsr.w	floppy_io                       ; read
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	move.w	$18(a0),d0                      ; sectors a track
	cmp.w	#$a00,d0                        ; 10?
	bne.w	disk_error                      ; no: "OOPS - Disk Error!!"
	move.w	$1a(a0),d0                      ; sides
	cmp.w	#$200,d0                        ; 2?
	bne.w	disk_error                      ; no: "OOPS - Disk Error!!"
	moveq	#1,d1                           ; the boot sector
	moveq	#0,d0
	move.b	$11(a0),d0                      ; directory entries
	lsr.l	#4,d0                           ; /16: the directory's sectors
	add.l	d0,d1                           ; + 1
	move.w	d0,ws_directory_sectors(a5)     ; kept
	moveq	#0,d0
	move.b	$17(a0),d0                      ; sectors a FAT
	lsl.l	#8,d0
	move.b	$16(a0),d0
	move.w	d0,ws_fat_sectors(a5)           ; kept
	move.b	$10(a0),d2                      ; FATs
	mulu.w	d2,d0                           ; the FATs' sectors
	add.l	d0,d1                           ; + them: the first data sector
	move.w	d1,ws_first_data_sector(a5)     ; kept
	move.b	$14(a0),d0                      ; the sectors
	lsl.l	#8,d0
	move.b	$13(a0),d0
	sub.l	d1,d0                           ; less those before the data
	moveq	#0,d1
	move.b	$d(a0),d1                       ; sectors a cluster
	move.w	d1,ws_cluster_sectors(a5)       ; kept
	divu.w	d1,d0                           ; the clusters
	addi.l	#$2,d0                          ; + 2
	move.w	d0,ws_fat_entries(a5)           ; the FAT's entries
	moveq	#0,d2
	move.w	ws_fat_sectors(a5),d2           ; the first FAT's sectors
	move.w	ws_fat_sectors(a5),ws_fat_copy_sector(a5) ; the second FAT's sector
	addi.w	#$1,ws_fat_copy_sector(a5)
	lea	$f0200,a0                       ; the FAT's buffer
	moveq	#8,d0                           ; drive A
	moveq	#1,d1                           ; sector 1
	moveq	#0,d3                           ; read
	bsr.w	floppy_io                       ; read
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	lea	$f0c00,a0                       ; the directory's buffer
	moveq	#8,d0                           ; drive A
	moveq	#0,d1
	move.w	ws_first_data_sector(a5),d1     ; the first data sector
	sub.w	ws_directory_sectors(a5),d1     ; less the directory: its first sector
	moveq	#0,d2
	move.w	ws_directory_sectors(a5),d2     ; its sectors
	moveq	#0,d3                           ; read
	bsr.w	floppy_io                       ; read
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	lea	$f0200,a0                       ; the FAT
	lea	$f2100,a2                       ; as words
	move.w	ws_fat_entries(a5),d7           ; the pairs
	subi.w	#$1,d7
write_file_unpack_fat:
	moveq	#0,d0
	move.b	1(a0),d0                        ; the first entry: the low byte
	andi.b	#$f,d0
	lsl.l	#8,d0
	move.b	(a0),d0
	move.w	d0,(a2)+
	moveq	#0,d0
	move.b	1(a0),d0                        ; the second entry
	andi.b	#$f0,d0
	lsr.l	#4,d0
	moveq	#0,d1
	move.b	2(a0),d1
	lsl.l	#4,d1
	or.l	d1,d0
	move.w	d0,(a2)+
	adda.l	#$3,a0                          ; the next three bytes
	dbra	d7,write_file_unpack_fat
	move.w	#$ffff,(a2)                     ; the end
	clr.w	ws_clusters(a5)                 ; no clusters yet
	lea	$f2104,a0                       ; from cluster 2
	lea	$f4000,a1                       ; the clusters taken
	moveq	#0,d0
	moveq	#2,d2                           ; cluster 2
write_file_find_cluster:
	move.w	(a0),d0                         ; its entry
	bne.w	write_file_next_cluster         ; in use
	move.l	d2,(a1)+                        ; free: its number
	move.l	a0,(a1)+                        ; and entry
	addi.w	#$1,ws_clusters(a5)             ; one more
	move.w	ws_clusters(a5),d1
	mulu.w	ws_cluster_sectors(a5),d1       ; their sectors
	cmp.w	ws_file_sectors(a5),d1          ; enough?
	bgt.w	write_file_found                ; yes
write_file_next_cluster:
	cmp.w	#$ffff,d0                       ; the end?
	beq.w	disk_full                       ; yes: "OOPS - No more space!!"
	addq.l	#1,d2
	addq.l	#2,a0
	bra.w	write_file_find_cluster
write_file_found:
	bsr.w	write_file_clusters             ; the clusters written and chained
	bsr.w	write_file_entry                ; the directory entry
	bsr.w	write_file_fat                  ; the FAT written
	movem.l	(sp)+,d0-d7/a0-a6
	bsr.w	clear_message                   ; the message line cleared
	bra.w	command_loop

;------------------------------------------------------------------------------
; write_file_clusters: each cluster taken written from the memory, its FAT entry set to the next taken, the last
; to $FFF.
;------------------------------------------------------------------------------
write_file_clusters:	; from: write_file
	lea	$f4000,a6                       ; the clusters taken
	moveq	#0,d6
	moveq	#0,d7
	move.w	ws_file_sectors(a5),d7          ; the sectors
	move.w	ws_cluster_sectors(a5),d6       ; sectors a cluster
	divu.w	d6,d7                           ; the clusters
	subq.l	#1,d7                           ; for dbra
	movea.l	ws_file_start(a5),a0            ; the memory
write_file_cluster:
	move.l	(a6)+,d0                        ; the cluster
	movea.l	(a6)+,a1                        ; its entry
	move.l	(a6),d1                         ; the next one
	move.w	d1,(a1)                         ; chained
	move.l	d0,d1
	subq.l	#2,d1                           ; less 2
	moveq	#0,d2
	move.w	ws_cluster_sectors(a5),d2       ; sectors a cluster
	mulu.w	d2,d1                           ; its sector
	add.w	ws_first_data_sector(a5),d1     ; + the first data sector
	moveq	#8,d0                           ; drive A
	moveq	#0,d2
	move.w	ws_cluster_sectors(a5),d2       ; sectors a cluster
	moveq	#1,d3                           ; write
	bsr.w	floppy_io                       ; written
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	move.l	#$200,d0
	mulu.w	d2,d0                           ; the cluster's bytes
	adda.l	d0,a0                           ; on
	dbra	d7,write_file_cluster           ; the next
	move.w	#$fff,(a1)                      ; the last: end of file
	rts

;------------------------------------------------------------------------------
; write_file_entry: a free directory entry, the name in capitals in 8.3 form, "OOPS - File already exists!!" if
; it is there, then the entry (time and date fixed, first cluster, length) and the directory written.
;------------------------------------------------------------------------------
write_file_entry:	; from: write_file
	move.l	#$ffffffff,$f2000               ; the end marker
	lea	$f0c20,a0                       ; the directory
	moveq	#0,d0
write_file_entry_free:
	move.b	(a0),d0
	cmp.b	#$0,d0                          ; never used?
	beq.w	write_file_entry_name           ; yes
	cmp.b	#$e5,d0                         ; deleted?
	beq.w	write_file_entry_name           ; yes
	cmp.b	#$ff,d0                         ; the end?
	beq.w	disk_error                      ; yes: "OOPS - Disk Error!!"
	adda.l	#$20,a0                         ; the next
	bra.w	write_file_entry_free
write_file_entry_name:
	move.l	a0,-(sp)                        ; the entry kept
	lea	$f2004,a0                       ; the 8.3 name
	lea	ws_dos_name(a5),a1              ; the name typed
	move.l	#$20202020,(a0)                 ; spaces
	move.l	#$20202020,4(a0)
	move.l	#$20202000,8(a0)
	move.b	(a1)+,d0                        ; the first character
	cmp.b	#$2e,d0                         ; '.'?
	beq.w	write_file_entry_extension      ; the extension
	cmp.b	#$20,d0                         ; a space?
	beq.w	write_file_entry_capitals       ; the end
	cmp.b	#$0,d0                          ; 0?
	beq.w	write_file_entry_capitals       ; the end
	move.b	d0,(a0)
	move.b	(a1)+,d0                        ; the second
	cmp.b	#$2e,d0
	beq.w	write_file_entry_extension
	cmp.b	#$20,d0
	beq.w	write_file_entry_capitals
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,1(a0)
	move.b	(a1)+,d0                        ; the third
	cmp.b	#$2e,d0
	beq.w	write_file_entry_extension
	cmp.b	#$20,d0
	beq.w	write_file_entry_capitals
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,2(a0)
	move.b	(a1)+,d0                        ; the fourth
	cmp.b	#$2e,d0
	beq.w	write_file_entry_extension
	cmp.b	#$20,d0
	beq.w	write_file_entry_capitals
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,3(a0)
	move.b	(a1)+,d0                        ; the fifth
	cmp.b	#$2e,d0
	beq.w	write_file_entry_extension
	cmp.b	#$20,d0
	beq.w	write_file_entry_capitals
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,4(a0)
	move.b	(a1)+,d0                        ; the sixth
	cmp.b	#$2e,d0
	beq.w	write_file_entry_extension
	cmp.b	#$20,d0
	beq.w	write_file_entry_capitals
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,5(a0)
	move.b	(a1)+,d0                        ; the seventh
	cmp.b	#$2e,d0
	beq.w	write_file_entry_extension
	cmp.b	#$20,d0
	beq.w	write_file_entry_capitals
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,6(a0)
	move.b	(a1)+,d0                        ; the eighth
	cmp.b	#$2e,d0
	beq.w	write_file_entry_extension
	cmp.b	#$20,d0
	beq.w	write_file_entry_capitals
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,7(a0)
	move.b	(a1)+,d0                        ; the '.'
write_file_entry_extension:
	move.b	(a1)+,d0                        ; the extension's first
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,8(a0)
	move.b	(a1)+,d0                        ; its second
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,9(a0)
	move.b	(a1)+,d0                        ; its third
	cmp.b	#$0,d0
	beq.w	write_file_entry_capitals
	move.b	d0,$a(a0)
write_file_entry_capitals:
	clr.b	$b(a0)                          ; ended
	move.w	#$a,d0                          ; 11 characters
write_file_entry_capital:
	move.b	(a0),d1
	cmp.b	#$61,d1                         ; a small letter?
	blt.w	write_file_entry_next
	cmp.b	#$7b,d1
	bgt.w	write_file_entry_next
	subi.b	#$20,d1                         ; in capitals
	move.b	d1,(a0)
write_file_entry_next:
	adda.l	#$1,a0
	dbra	d0,write_file_entry_capital
	move.l	#$ffffffff,$f2000               ; the end marker
	lea	$f0c20,a0                       ; the directory
	moveq	#0,d0
	lea	$f2004,a1                       ; the name
	move.l	(a1),d3
	move.l	4(a1),d4
	move.l	8(a1),d5
write_file_entry_compare:
	move.l	(a0),d0                         ; an entry
	move.l	4(a0),d1
	move.l	8(a0),d2
	cmp.l	d0,d3                           ; the same?
	bne.w	write_file_entry_compare_next
	cmp.l	d1,d4
	bne.w	write_file_entry_compare_next
	cmp.l	d2,d5
	bne.w	write_file_entry_compare_next
	bra.w	file_exists                     ; yes: "OOPS - File already exists!!"
write_file_entry_compare_next:
	cmpa.l	#$f2000,a0                      ; the end?
	bgt.w	write_file_entry_set            ; yes
	adda.l	#$20,a0                         ; the next
	bra.w	write_file_entry_compare
write_file_entry_set:
	movea.l	(sp)+,a0                        ; the free entry
	lea	$f2004,a1                       ; the name
	move.l	(a1),(a0)                       ; into it
	move.l	4(a1),4(a0)
	move.l	8(a1),8(a0)
	move.l	#$0,$f2004                      ; the name's place cleared
	move.l	#$0,$f2008
	move.l	#$0,$f200c
	move.l	#$3000960e,$16(a0)              ; its time and date
	lea	$f4000,a6                       ; the first cluster taken
	move.l	(a6),d0
	move.l	d0,d1
	lsr.l	#8,d0
	lsl.l	#8,d1
	or.l	d1,d0                           ; little-endian
	move.w	d0,$1a(a0)                      ; its first cluster
	lea	ws_file_length(a5),a1           ; the length
	moveq	#0,d0
	move.b	3(a1),d0                        ; little-endian
	lsl.l	#8,d0
	move.b	2(a1),d0
	lsl.l	#8,d0
	move.b	1(a1),d0
	lsl.l	#8,d0
	move.b	(a1),d0
	move.l	d0,$1c(a0)                      ; its length
	lea	$f0c00,a0                       ; the directory
	moveq	#8,d0                           ; drive A
	moveq	#0,d1
	move.w	ws_first_data_sector(a5),d1     ; the first data sector
	sub.w	ws_directory_sectors(a5),d1     ; less the directory: its first sector
	moveq	#0,d2
	move.w	ws_directory_sectors(a5),d2     ; its sectors
	moveq	#1,d3                           ; write
	bsr.w	floppy_io                       ; written
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	rts

;------------------------------------------------------------------------------
; write_file_fat: the FAT packed back to 12 bits and written as both FATs.
;------------------------------------------------------------------------------
write_file_fat:	; from: write_file
	lea	$f0200,a1                       ; the FAT
	lea	$f2100,a0                       ; the words
	move.w	ws_fat_entries(a5),d7           ; the pairs
	subi.w	#$1,d7
write_file_pack_fat:
	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	move.w	(a0)+,d0                        ; the first entry
	move.b	d0,d3
	lsr.l	#8,d0
	move.b	d0,d4
	move.w	(a0)+,d0                        ; the second
	move.l	d0,d1
	lsr.l	#4,d0
	move.b	d0,d5
	lsl.l	#4,d1
	andi.w	#$f0,d1
	or.w	d1,d4
	move.b	d3,(a1)+
	move.b	d4,(a1)+
	move.b	d5,(a1)+                        ; three bytes
	dbra	d7,write_file_pack_fat
	lea	$f0200,a0
	moveq	#8,d0                           ; drive A
	moveq	#1,d1                           ; sector 1
	moveq	#0,d2
	move.w	ws_fat_sectors(a5),d2           ; the FAT's sectors
	moveq	#1,d3                           ; write
	bsr.w	floppy_io                       ; the first FAT
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	lea	$f0200,a0
	moveq	#8,d0                           ; drive A
	move.w	ws_fat_copy_sector(a5),d1       ; the second FAT's sector
	moveq	#0,d2
	move.w	ws_fat_sectors(a5),d2           ; the FAT's sectors
	moveq	#1,d3                           ; write
	bsr.w	floppy_io                       ; the second FAT
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	rts
	movem.l	(sp)+,d0-d7/a0-a6               ; (not reached)
	bsr.w	clear_message
	bra.w	command_loop

;------------------------------------------------------------------------------
; format_disk (Alternate F): asks, formats drive A with 80 tracks, 10 sectors and 2 sides, then writes track
; 0 side 0 from disk_image (the boot sector, the FATs and the directory).
;------------------------------------------------------------------------------
format_disk:	; from: key_table
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	lea	format_question(pc),a0          ; "Do you really want to format [Y/N]"
	bsr.w	ask_yes_no
	moveq	#0,d1                           ; from sector 0
	move.l	#$640,d2                        ; 1600 sectors
	move.l	#$8002,d3                       ; format
	movea.l	#$ea010,a0                      ; the track buffer
	moveq	#8,d0                           ; drive A, double sided, 10 sectors a track
	bsr.w	floppy_io                       ; formatted
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	lea	disk_image,a0                   ; the disk's first sectors
	lea	$f0000,a1
	move.w	#$540,d0                        ; $541 longs
format_disk_copy:
	move.l	(a0)+,(a1)+                     ; copied
	dbra	d0,format_disk_copy
	lea	$f0000,a0
	moveq	#8,d0                           ; drive A
	moveq	#0,d1                           ; sector 0
	moveq	#10,d2                          ; 10 sectors
	moveq	#1,d3                           ; write
	bsr.w	floppy_io                       ; written
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	movem.l	(sp)+,d0-d7/a0-a6
	bsr.w	clear_message                   ; the message line cleared
	bra.w	command_loop

;------------------------------------------------------------------------------
; load_bootsector (F10): asks, reads drive A's boot sector to $EA010 and enters the monitor as if a trap #15
; there, with pc at the boot sector, to trace it.
;------------------------------------------------------------------------------
load_bootsector:	; from: key_table
	movem.l	d0-d7/a0-a6,-(sp)               ; saved
	lea	bootsector_question(pc),a0      ; "Do you want to read bootsector [Y/N]"
	bsr.w	ask_yes_no
	moveq	#0,d1                           ; sector 0
	move.l	#$1,d2                          ; 1
	move.l	#$8000,d3                       ; read
	movea.l	#$ea010,a0                      ; the buffer
	moveq	#0,d0                           ; drive A, single sided
	bsr.w	floppy_io                       ; read
	tst.l	d0                              ; an error?
	bne.w	disk_error                      ; "OOPS - Disk Error!!"
	movem.l	(sp)+,d0-d7/a0-a6
	bsr.w	clear_message                   ; the message line cleared
	move.l	#$ea010,-(sp)                   ; its pc
	move.w	sr,-(sp)                        ; its status register
	move.l	$bc,-(sp)                       ; trap #15
	rts                                     ; into the monitor
disk_error:                                     ; from: write_sectors, read_sectors, write_file, write_file_clusters,
                                                ;   write_file_entry, write_file_fat, 1 more
	lea	disk_error_text(pc),a0          ; "OOPS - Disk Error!!"
	bsr.w	print_message
	st	ws_message(a5)                  ; a message shown
	movem.l	(sp)+,d0-d7/a0-a6
	bra.w	monitor_restart
disk_full:	; from: write_file
	lea	disk_full_text(pc),a0           ; "OOPS - No more space!!"
	bsr.w	print_message
	st	ws_message(a5)                  ; a message shown
	movem.l	(sp)+,d0-d7/a0-a6
	bra.w	monitor_restart
file_exists:	; from: write_file_entry
	movea.l	(sp)+,a0
	lea	file_exists_text(pc),a0         ; "OOPS - File already exists!!"
	bsr.w	print_message
	st	ws_message(a5)                  ; a message shown
	movem.l	(sp)+,d0-d7/a0-a6
	bra.w	monitor_restart
disk_error_text:
	dc.b	'OOPS - Disk Error!!',0
disk_full_text:
	dc.b	'OOPS - No more space!!',0
	dc.b	$00
file_exists_text:
	dc.b	'OOPS - File already exists!!',0
	dc.b	$00
format_question:	; from: format_disk
	dc.b	'Do you really want to format [Y/N]',0
	dc.b	$00
bootsector_question:
	dc.b	'Do you want to read bootsector [Y/N]',0
	dc.b	$00

;------------------------------------------------------------------------------
; floppy_io: reads, writes or formats drive A or B through the FDC and DMA.  d0: bit 0 the drive, bit 3 set
; for double sided, the high word sectors a track (9-11, else 10); d1 the first logical sector, d2 the
; count, d3 $8000 read, $8001 write, $8002 format, a0 the buffer.  d0 = 0, or an error number.  Each
; drive's track is kept at $EA000.
;------------------------------------------------------------------------------
floppy_io:                                      ; from: write_sectors, read_sectors, write_file, write_file_clusters,
                                                ;   write_file_entry, write_file_fat, 2 more
	movem.l	d1-d4/a0-a1,-(sp)               ; saved
	link	a6,#-30                         ; the locals
	move.l	d0,d4
	andi.w	#$1,d0                          ; the drive
	move.w	d0,-$1c(a6)
	swap	d0                              ; sectors a track
	cmp.w	#$9,d0                          ; 9-11?
	blt.s	floppy_io_ten
	cmp.w	#$b,d0
	ble.s	floppy_io_params
floppy_io_ten:
	move.w	#$a,d0                          ; no: 10
floppy_io_params:
	move.w	d0,-$1e(a6)
	move.w	d1,-$16(a6)                     ; the first sector
	move.w	d2,-$12(a6)                     ; the count
	move.w	d3,-$8(a6)                      ; the command
	move.l	a0,-$c(a6)                      ; the buffer
	ror.l	#3,d4                           ; bit 3
	andi.w	#$1,d4
	eori.b	#$1,d4
	addq.b	#1,d4                           ; the track step: 1 double sided, 2 single
	move.w	d4,-$10(a6)
	clr.w	d4
	rol.l	#1,d4                           ; bit 4: the side
	move.w	d4,-$e(a6)
	moveq	#21,d0                          ; 21: too far
	add.w	d1,d2                           ; the last sector
	move.w	-$1e(a6),d3
	mulu.w	#$a0,d3                         ; 160 tracks' sectors
	cmp.w	d3,d2                           ; past them?
	bgt.w	floppy_io_done                  ; yes
	ext.l	d1
	divu.w	-$1e(a6),d1                     ; the track and sector
	cmpi.w	#$1,-$10(a6)                    ; double sided?
	beq.s	floppy_io_track                 ; yes
	add.w	d1,d1                           ; single: 2 tracks a side's step
floppy_io_track:
	move.w	d1,-$1a(a6)                     ; the logical track
	swap	d1
	addq.w	#1,d1                           ; from 1
	move.w	d1,-$18(a6)                     ; the sector
	bsr.w	floppy_select                   ; the drive selected, its track set
floppy_io_next_track:
	move.w	-$18(a6),d0                     ; the sector
	move.w	-$1e(a6),d1                     ; sectors a track
	addq.w	#1,d1
	sub.w	d0,d1                           ; left on the track
	cmp.w	-$12(a6),d1                     ; more than needed?
	ble.s	floppy_io_count                 ; no
	move.w	-$12(a6),d1                     ; those needed
floppy_io_count:
	move.w	d1,-$14(a6)
	bsr.w	floppy_track_io                 ; done
	bne.s	floppy_io_error                 ; an error
	move.w	-$12(a6),d0                     ; the count
	sub.w	-$14(a6),d0                     ; less those done
	beq.s	floppy_io_error                 ; all done
	move.w	d0,-$12(a6)                     ; the count left
	move.w	#$1,-$18(a6)                    ; from sector 1
	move.w	-$10(a6),d0
	add.w	d0,-$1a(a6)                     ; the next track
	cmpi.b	#$2,-$7(a6)                     ; format?
	beq.s	floppy_io_next_track            ; yes: the same buffer
	move.w	-$14(a6),d0
	lsl.l	#8,d0
	add.l	d0,d0                           ; * 512
	add.l	d0,-$c(a6)                      ; on in the buffer
	bra.s	floppy_io_next_track
floppy_io_error:
	move.l	d0,d1
	beq.s	floppy_io_done                  ; none
	andi.b	#$58,d0                         ; the status's error bits
	moveq	#28,d1                          ; 28: write protected
	cmp.b	#$40,d0
	beq.s	floppy_io_done
	moveq	#25,d1                          ; 25: CRC error
	cmp.b	#$8,d0
	beq.s	floppy_io_done
	moveq	#24,d1                          ; 24: record not found
	cmp.b	#$18,d0
	beq.s	floppy_io_done
	moveq	#21,d1                          ; 21
	cmp.b	#$10,d0                         ; lost data?
	beq.s	floppy_io_done
	moveq	#-1,d1                          ; -1: timeout
floppy_io_done:
	bsr.w	floppy_deselect                 ; the drive deselected
	unlk	a6
	move.l	d1,d0                           ; the error
	movem.l	(sp)+,d1-d4/a0-a1
	rts

;------------------------------------------------------------------------------
; floppy_track_io: the drive and side selected, the head on the track, then the track's sectors done, up to
; three tries (restoring after a record not found).
;------------------------------------------------------------------------------
floppy_track_io:	; from: floppy_io
	bsr.w	floppy_select_drive             ; selected
	move.w	#$2,d3                          ; 3 tries
	bra.s	floppy_track_seek
floppy_track_retry:
	cmp.b	#$10,d0                         ; record not found?
	bne.s	floppy_track_go                 ; no
	bsr.w	floppy_restore                  ; to track 0
floppy_track_seek:
	move.w	-$1a(a6),d0                     ; the logical track
	lsr.w	#1,d0                           ; the cylinder
	bsr.w	floppy_seek                     ; seek
floppy_track_go:
	movea.l	-$c(a6),a0                      ; the buffer
	move.w	-$18(a6),d1                     ; the sector
	move.w	-$14(a6),d2                     ; the count
	bsr.w	floppy_track_transfer           ; done
	tst.w	d0                              ; all right?
	beq.s	floppy_track_done               ; yes
	cmp.b	#$40,d0                         ; write protected?
	dbeq	d3,floppy_track_retry           ; no: again
	tst.w	d0
floppy_track_done:
	rts

;------------------------------------------------------------------------------
; floppy_track_transfer: the sectors d1 to d1+d2-1 of the track read, or written, or the track formatted.
;------------------------------------------------------------------------------
floppy_track_transfer:	; from: floppy_track_io
	tst.b	-$7(a6)                         ; read?
	beq.s	floppy_read                     ; yes
	bra.w	floppy_write                    ; write or format
floppy_read:
	bsr.w	floppy_set_dma                  ; the DMA address and sector
	move.w	#$90,$ffff8606.w                ; DMA mode / status, the DMA toggled to read
	move.w	#$190,$ffff8606.w               ; DMA mode / status
	move.w	#$90,$ffff8606.w                ; DMA mode / status
	moveq	#0,d0
	move.w	d2,d0                           ; the sector count
	bsr.w	fdc_write
	lsl.l	#8,d0                           ; * 512
	add.l	d0,d0
	movea.l	a0,a1
	adda.l	d0,a1                           ; the end
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the command register
	move.w	#$90,d0                         ; read multiple sectors
	bsr.w	fdc_write
	move.l	#$40000,d0                      ; the timeout
	clr.l	-$4(a6)
floppy_read_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, done (FDC interrupt)?
	beq.s	floppy_read_done                ; yes
	subq.l	#1,d0
	beq.s	floppy_read_timeout             ; timeout
	move.b	$ffff8609.w,-$3(a6)             ; DMA base high, the DMA address
	move.b	$ffff860b.w,-$2(a6)             ; DMA base mid
	move.b	$ffff860d.w,-$1(a6)             ; DMA base low
	cmpa.l	-$4(a6),a1                      ; all read?
	bgt.s	floppy_read_wait                ; no
	bsr.w	floppy_stop                     ; yes: stopped
floppy_read_done:
	move.w	#$90,$ffff8606.w                ; DMA mode / status, the DMA status
	move.w	$ffff8606.w,d0                  ; DMA mode / status
	btst	#$0,d0                          ; DMA error?
	beq.s	floppy_read_failed              ; yes
	bsr.w	floppy_status                   ; the FDC status
	andi.b	#$18,d0                         ; record not found, CRC error
	rts
floppy_read_timeout:
	bsr.w	floppy_stop                     ; stopped
floppy_read_failed:
	moveq	#-1,d0
	rts
floppy_write:
	bsr.w	floppy_set_dma                  ; the DMA address and sector
	move.w	#$190,$ffff8606.w               ; DMA mode / status, the DMA toggled to write
	move.w	#$90,$ffff8606.w                ; DMA mode / status
	move.w	#$190,$ffff8606.w               ; DMA mode / status
	moveq	#1,d0                           ; 1 sector
	cmpi.b	#$1,-$7(a6)                     ; write?
	beq.s	floppy_write_count              ; yes
	moveq	#31,d0                          ; format: 31 for the track
floppy_write_count:
	bsr.w	fdc_write
	move.w	#$180,$ffff8606.w               ; DMA mode / status, the command register, write
	move.w	#$a0,d0                         ; write sector
	cmpi.b	#$1,-$7(a6)                     ; write?
	beq.s	floppy_write_command            ; yes
	bsr.w	floppy_side                     ; the side
	move.w	d0,d1
	move.w	-$1a(a6),d0                     ; the logical track
	lsr.w	#1,d0                           ; the cylinder
	bsr.w	build_track                     ; the track built
	move.w	#$f0,d0                         ; write track
	moveq	#1,d2
floppy_write_command:
	bsr.w	fdc_write
	move.l	#$40000,d0                      ; the timeout
floppy_write_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, done (FDC interrupt)?
	beq.s	floppy_write_done               ; yes
	subq.l	#1,d0
	bne.s	floppy_write_wait               ; no: wait
	bsr.w	floppy_stop                     ; timeout: stopped
	moveq	#-1,d0
	rts
floppy_write_done:
	bsr.w	floppy_status_write             ; the FDC status
	andi.b	#$5c,d0                         ; write protect, record not found, CRC, lost data
	bne.s	floppy_write_end                ; an error
	lea	$200(a0),a0                     ; the next sector
	addq.b	#1,d1
	subq.b	#1,d2                           ; more?
	bne.s	floppy_write                    ; yes
floppy_write_end:
	rts

;------------------------------------------------------------------------------
; build_track: a format track at a0 for cylinder d0, side d1: 60 bytes of $4E, then for each sector 12 zeros,
; 3 $F5, the ID ($FE, track, side, sector, size 2, CRC), 22 $4E, 12 zeros, 3 $F5, $FB, the data ($6DB6DB...),
; CRC and 40 $4E; then 100 $4E.  The first sector of each track comes from track_first_sector.
;------------------------------------------------------------------------------
build_track:	; from: floppy_track_transfer
	movem.l	d0-d5/a0,-(sp)                  ; saved
	move.l	d0,d4                           ; the cylinder
	move.l	d1,d5                           ; the side
	mulu.w	#$14,d0
	bsr.w	track_first_sector              ; the first sector
	move.w	d0,d2
	move.b	#$4e,d0                         ; gap 1
	moveq	#60,d1                          ; 60
	bsr.w	fill_bytes
	move.w	-$1e(a6),d3                     ; sectors a track
build_track_sector:
	moveq	#0,d0
	moveq	#12,d1                          ; 12 zeros
	bsr.w	fill_bytes
	move.b	#$f5,d0
	moveq	#3,d1                           ; 3 $F5 (sync)
	bsr.w	fill_bytes
	move.b	#$fe,(a0)+                      ; ID mark
	move.b	d4,(a0)+                        ; the track
	move.b	d5,(a0)+                        ; the side
	cmp.b	-$1d(a6),d2                     ; past the last?
	ble.s	build_track_id                  ; no
	moveq	#1,d2                           ; back to 1
build_track_id:
	move.b	d2,(a0)+                        ; the sector
	move.b	#$2,(a0)+                       ; 512 bytes
	move.b	#$f7,(a0)+                      ; the CRC
	move.b	#$4e,d0                         ; gap 2
	moveq	#22,d1                          ; 22
	bsr.w	fill_bytes
	moveq	#0,d0                           ; 12 zeros
	moveq	#12,d1
	bsr.w	fill_bytes
	move.b	#$f5,d0                         ; 3 $F5 (sync)
	moveq	#3,d1
	bsr.w	fill_bytes
	move.b	#$fb,(a0)+                      ; data mark
	bsr.w	fill_sector_data                ; the data
	move.b	#$f7,(a0)+                      ; the CRC
	move.b	#$4e,d0                         ; gap 3
	moveq	#40,d1                          ; 40
	bsr.w	fill_bytes
	addq.b	#1,d2                           ; the next sector
	subq.w	#1,d3
	bne.s	build_track_sector
	moveq	#100,d1                         ; gap 4: 100 $4E
	bsr.w	fill_bytes
	movem.l	(sp)+,d0-d5/a0
	rts

;------------------------------------------------------------------------------
; fill_bytes: d1 bytes d0 at a0.
;------------------------------------------------------------------------------
fill_bytes:	; from: build_track
	move.b	d0,(a0)+
	subq.l	#1,d1
	bne.s	fill_bytes
	rts

;------------------------------------------------------------------------------
; fill_sector_data: 512 bytes of $6D,$B6,$DB at a0.
;------------------------------------------------------------------------------
fill_sector_data:	; from: build_track
	move.w	#$a9,d0                         ; 170 times
fill_sector_data_loop:
	move.b	#$6d,(a0)+
	move.b	#$b6,(a0)+
	move.b	#$db,(a0)+
	dbra	d0,fill_sector_data_loop
	move.b	#$6d,(a0)+                      ; and 2 more
	move.b	#$b6,(a0)+
	rts

;------------------------------------------------------------------------------
; track_first_sector: the first sector on cylinder d0 (d0 = cylinder * 20 on entry): the sectors skewed from
; one cylinder to the next.
;------------------------------------------------------------------------------
track_first_sector:	; from: build_track
	move.l	d1,-(sp)                        ; saved
	andi.l	#$ffff,d0
	divu.w	#$64,d0
	swap	d0                              ; the remainder
	andi.l	#$ffff,d0
	divu.w	#$14,d0                         ; / 20
	add.w	d0,d0
	subi.w	#$a,d0
	neg.w	d0
	move.l	d0,d1
	swap	d1
	add.w	d1,d0
	andi.l	#$ffff,d0
	divu.w	#$a,d0                          ; % 10
	swap	d0
	addq.b	#1,d0                           ; from 1
	andi.l	#$ffff,d0
	move.l	(sp)+,d1
	rts

;------------------------------------------------------------------------------
; floppy_set_dma: the DMA address a0, and the sector d1 into the FDC sector register.
;------------------------------------------------------------------------------
floppy_set_dma:	; from: floppy_track_transfer
	move.l	a0,d0
	move.b	d0,$ffff860d.w                  ; DMA base low, low
	lsr.l	#8,d0
	move.b	d0,$ffff860b.w                  ; DMA base mid, mid
	lsr.l	#8,d0
	move.b	d0,$ffff8609.w                  ; DMA base high, high
	move.w	#$84,$ffff8606.w                ; DMA mode / status, the sector register
	move.w	d1,d0
	bsr.w	fdc_write                       ; written
	rts

;------------------------------------------------------------------------------
; floppy_seek: the head to cylinder d0 (to track 0 for 0).  d0 = 0, or minus for a timeout.
;------------------------------------------------------------------------------
floppy_seek:	; from: floppy_track_io
	tst.w	d0                              ; track 0?
	beq.s	floppy_restore                  ; yes: restore
	move.w	#$86,$ffff8606.w                ; DMA mode / status, the data register
	bsr.w	fdc_write                       ; the cylinder
	move.w	#$10,d0                         ; seek
	bsr.w	floppy_command
	bmi.s	floppy_seek_done                ; timeout
	moveq	#0,d0
floppy_seek_done:
	rts

;------------------------------------------------------------------------------
; floppy_restore: the head to track 0.  d0 = 0, or the status if track 0 was not reached.
;------------------------------------------------------------------------------
floppy_restore:	; from: floppy_track_io, floppy_seek, floppy_select
	moveq	#0,d0                           ; restore
	bsr.w	floppy_command
	bmi.s	floppy_restore_done             ; timeout
	eori.b	#$4,d0
	btst	#$2,d0                          ; track 0?
	bne.s	floppy_restore_done             ; no
	moveq	#0,d0
floppy_restore_done:
	rts

;------------------------------------------------------------------------------
; floppy_select: the floppy locked, the drive and side selected, its track put in the track register
; (restored if not known).
;------------------------------------------------------------------------------
floppy_select:	; from: floppy_io
	move.w	$43e.w,-$6(a6)                  ; flock, flock kept
	st	$43e.w                          ; flock, floppy locked
	bsr.w	floppy_select_drive             ; selected
	move.w	-$1c(a6),d0                     ; the drive
	add.w	d0,d0
	move.w	#$82,$ffff8606.w                ; DMA mode / status, the track register
	lea	$ea000,a0                       ; the drives' tracks
	move.w	0(a0,d0.w),d0                   ; its track
	lsr.w	#1,d0                           ; the cylinder
	bsr.w	fdc_write                       ; written
	cmp.w	#$a0,d0                         ; 160 or more: not known?
	blt.s	floppy_select_done              ; no
	bsr.s	floppy_restore                  ; restore
floppy_select_done:
	rts

;------------------------------------------------------------------------------
; floppy_deselect: the drive's track kept, a wait for the motor, the drives deselected, flock back.
;------------------------------------------------------------------------------
floppy_deselect:	; from: floppy_io
	movem.l	d0-d1,-(sp)                     ; saved
	move.w	-$1c(a6),d0                     ; the drive
	add.w	d0,d0
	lea	$ea000,a0                       ; the drives' tracks
	move.w	-$1a(a6),d1                     ; the logical track
	move.w	d1,0(a0,d0.w)                   ; kept
	tst.w	-$8(a6)                         ; a command?
	bpl.s	floppy_deselect_drives          ; no
	move.l	#$c3500,d0                      ; the wait
	bsr.w	delay
floppy_deselect_drives:
	moveq	#7,d0                           ; no drive
	bsr.w	set_port_a
	move.w	-$6(a6),$43e.w                  ; flock, flock back
	movem.l	(sp)+,d0-d1
	rts

;------------------------------------------------------------------------------
; floppy_select_drive: the drive and side selected through the sound chip's port A.
;------------------------------------------------------------------------------
floppy_select_drive:	; from: floppy_track_io, floppy_select
	move.w	d0,-(sp)
	move.w	-$1c(a6),d0                     ; the drive
	andi.w	#$1,d0
	addq.b	#1,d0
	add.b	d0,d0                           ; its select bit
	move.w	d0,-(sp)
	bsr.w	floppy_side                     ; the side
	or.w	(sp)+,d0
	eori.b	#$7,d0                          ; active low
	andi.b	#$7,d0
	bsr.w	set_port_a                      ; set
	move.w	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; floppy_side: the side: bit 0 of the logical track when double sided, else the side given.
;------------------------------------------------------------------------------
floppy_side:	; from: floppy_track_transfer, floppy_select_drive
	move.w	-$10(a6),d0
	cmp.w	#$1,d0                          ; double sided?
	beq.s	floppy_side_double              ; yes
	move.w	-$e(a6),d0                      ; the side given
	bra.s	floppy_side_done
floppy_side_double:
	move.w	-$1a(a6),d0
	andi.w	#$1,d0                          ; bit 0
floppy_side_done:
	rts

;------------------------------------------------------------------------------
; set_port_a: the sound chip's port A bits 0-2 (side and drive selects) set to d0.
;------------------------------------------------------------------------------
set_port_a:	; from: floppy_deselect, floppy_select_drive
	move.w	sr,-(sp)
	ori.w	#$700,sr                        ; interrupts off
	move.b	#$e,$ffff8800.w                 ; PSG register select, port A
	move.b	$ffff8800.w,d1                  ; PSG register select
	andi.b	#$f8,d1
	or.b	d0,d1
	move.b	d1,$ffff8802.w                  ; PSG write data
	move.w	(sp)+,sr
	rts

;------------------------------------------------------------------------------
; floppy_command: a type I command d0 (step rate 3 added) and a wait for it.  d0 = the status, or minus.
;------------------------------------------------------------------------------
floppy_command:	; from: floppy_seek, floppy_restore
	cmp.b	#$80,d0                         ; type I?
	bcc.s	floppy_command_send             ; no
	ori.b	#$3,d0                          ; step rate 3
floppy_command_send:
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the command register
	bsr.w	fdc_write
	move.l	#$60000,d0                      ; the timeout
floppy_command_wait:
	btst	#$5,$fffffa01.w                 ; MFP GPIP, done (FDC interrupt)?
	beq.s	floppy_status                   ; yes: the status
	subq.l	#1,d0
	bne.s	floppy_command_wait             ; no: wait
	bsr.w	floppy_stop                     ; timeout: stopped
	moveq	#-1,d0
	rts

;------------------------------------------------------------------------------
; floppy_stop: Force Interrupt, then the status.
;------------------------------------------------------------------------------
floppy_stop:	; from: floppy_track_transfer, floppy_command
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the command register
	move.w	#$d0,d0                         ; Force Interrupt
	bsr.w	fdc_write
	moveq	#15,d0
	bsr.w	delay                           ; a wait
	bra.s	floppy_status

;------------------------------------------------------------------------------
; floppy_status_write: the FDC status, with the DMA in write.
;------------------------------------------------------------------------------
floppy_status_write:	; from: floppy_track_transfer
	move.w	#$180,$ffff8606.w               ; DMA mode / status
	bra.s	floppy_status_read

;------------------------------------------------------------------------------
; floppy_status: the FDC status into d0.
;------------------------------------------------------------------------------
floppy_status:	; from: floppy_track_transfer, floppy_command, floppy_stop
	move.w	#$80,$ffff8606.w                ; DMA mode / status, the status register
floppy_status_read:	; from: floppy_status_write
	bsr.w	fdc_wait
	move.w	$ffff8604.w,d0                  ; DMA sector count / FDC access, read
	andi.l	#$ff,d0
	bra.s	fdc_wait

;------------------------------------------------------------------------------
; fdc_write: d0 written to the FDC register selected, with a wait before and after.
;------------------------------------------------------------------------------
fdc_write:	; from: floppy_track_transfer, floppy_set_dma, floppy_seek, floppy_select, floppy_command, floppy_stop
	bsr.w	fdc_wait
	move.w	d0,$ffff8604.w                  ; DMA sector count / FDC access, written

;------------------------------------------------------------------------------
; fdc_wait: a short wait.
;------------------------------------------------------------------------------
fdc_wait:	; from: floppy_status, fdc_write
	move.w	sr,-(sp)
	move.w	d0,-(sp)
	moveq	#24,d0                          ; 24 loops
	bsr.w	delay
	move.w	(sp)+,d0
	move.w	(sp)+,sr
	rts

;------------------------------------------------------------------------------
; delay: d0 loops.
;------------------------------------------------------------------------------
delay:	; from: floppy_deselect, floppy_stop, fdc_wait
	subq.l	#1,d0
	bne.s	delay
	rts

;------------------------------------------------------------------------------
; breakpoint_here (Control B): a breakpoint at a disassembly window's base set, or cleared if there is one.
;------------------------------------------------------------------------------
breakpoint_here:	; from: key_table
	bsr.w	current_window                  ; the window
	bne.w	command_loop                    ; not a disassembly
	movea.l	(a0),a0                         ; its base

;------------------------------------------------------------------------------
; toggle_breakpoint: the breakpoint at a0 cleared if set, else set in a free slot if the memory takes it.
;------------------------------------------------------------------------------
toggle_breakpoint:	; from: breakpoint_at
	bsr.s	find_breakpoint                 ; set already?
	beq.s	toggle_breakpoint_clear         ; yes: cleared
	move.w	(a0),d0                         ; its word
	move.w	#$4afc,(a0)                     ; ILLEGAL
	cmpi.w	#$4afc,(a0)                     ; taken?
	bne.s	breakpoint_failed_rom           ; no: "Cannot set breakpoint!"
	move.w	d0,(a0)                         ; the word back
	move.l	a0,(a1)                         ; the slot
	lea	breakpoint_set_text(pc),a0      ; "Breakpoint SET"
	bra.s	breakpoint_message
toggle_breakpoint_clear:
	moveq	#-1,d0
	move.l	d0,-(a1)                        ; the slot free
	lea	breakpoint_cleared_text(pc),a0  ; "Breakpoint CLEARED"
breakpoint_message:	; from: find_breakpoint
	bsr.w	print_message                   ; shown
	lea	exception_ignore(pc),a0         ; faults: rte
	move.l	a0,ws_fault(a5)
	bsr.w	draw_windows                    ; drawn
	bra.w	command_loop
breakpoint_failed_rom:
	move.w	d0,(a0)                         ; the word back
	lea	breakpoint_failed_text(pc),a0   ; "Cannot set breakpoint!"
	bsr.w	print_message
	bra.w	command_loop

;------------------------------------------------------------------------------
; find_breakpoint: Z set and a1 past its slot if a0 is a breakpoint; else a1 = a free slot (Z clear), or
; "No more breakpoints left!" and back.
;------------------------------------------------------------------------------
find_breakpoint:	; from: toggle_breakpoint
	lea	command_fault(pc),a1            ; a fault: "Command aborted ..."
	move.l	a1,ws_fault(a5)
	lea	ws_breakpoints(a5),a1           ; the breakpoints
	lea	ws_breakpoint_words(a5),a2
	moveq	#3,d0                           ; 4
find_breakpoint_set:
	cmpa.l	(a1)+,a0                        ; this one?
	beq.s	find_breakpoint_done            ; yes
	addq.w	#1,a2                           ; (a2 not used)
	dbra	d0,find_breakpoint_set
	lea	ws_breakpoints(a5),a1           ; the breakpoints
	lea	ws_breakpoint_words(a5),a2
	moveq	#3,d0                           ; 4
find_breakpoint_free:
	tst.b	(a1)                            ; free?
	bmi.s	find_breakpoint_none            ; yes
	addq.w	#4,a1
	addq.w	#2,a2
	dbra	d0,find_breakpoint_free
	lea	no_breakpoints_text(pc),a0      ; "No more breakpoints left!"
	bra.s	breakpoint_message              ; shown, back
find_breakpoint_none:
	moveq	#1,d0                           ; Z clear
find_breakpoint_done:
	rts

;------------------------------------------------------------------------------
; breakpoint_at (Alternate B): "Set/Clear Breakpoint > ".
;------------------------------------------------------------------------------
breakpoint_at:	; from: key_table
	lea	breakpoint_prompt(pc),a4        ; "Set/Clear Breakpoint > "
	bsr.w	input_value                     ; the address
	bne.w	command_loop                    ; escape
	movea.l	d0,a0
	bra.w	toggle_breakpoint               ; set or cleared

;------------------------------------------------------------------------------
; get_key: a key from the keyboard ACIA, read directly: d0 = Alternate ($100), Control ($200) and the
; character from the key tables (F1-F10 $14-$1d, cursor keys $01-$04).  Shift and Caps Lock pick the
; shifted table; the mouse and joystick packets are skipped.
;------------------------------------------------------------------------------
get_key:	; from: command_loop, view_other_screen, help, zoom_window, get_key_cursor
	movem.l	d1/a0,-(sp)                     ; saved
get_key_byte:	; from: read_ikbd_data
	bsr.w	read_ikbd                       ; a byte
	cmp.b	#$f6,d0                         ; a packet's header?
	bcs.s	get_key_code                    ; no
	bsr.w	read_ikbd                       ; skipped
	bsr.w	read_ikbd
	bra.s	get_key_byte
get_key_code:
	cmp.b	#$1d,d0                         ; Control pressed?
	beq.w	get_key_control_on
	cmp.b	#$9d,d0                         ; Control released?
	beq.w	get_key_control_off
	cmp.b	#$38,d0                         ; Alternate pressed?
	beq.w	get_key_alternate_on
	cmp.b	#$b8,d0                         ; Alternate released?
	beq.w	get_key_alternate_off
	cmp.b	#$3a,d0                         ; Caps Lock?
	beq.w	get_key_caps_lock
	cmp.b	#$36,d0                         ; right Shift pressed?
	beq.w	get_key_shift_on
	cmp.b	#$2a,d0                         ; left Shift pressed?
	beq.w	get_key_shift_on
	cmp.b	#$b6,d0                         ; right Shift released?
	beq.w	get_key_shift_off
	cmp.b	#$aa,d0                         ; left Shift released?
	beq.w	get_key_shift_off
	btst	#$7,d0                          ; another key released?
	bne.s	get_key_byte                    ; yes: skipped
	andi.w	#$7f,d0
	lea	key_table_normal(pc),a0         ; the key table
	btst	#$3,ws_shift(a5)                ; Caps Lock?
	bne.s	get_key_shifted                 ; yes
	btst	#$2,ws_shift(a5)                ; Shift?
	beq.s	get_key_lookup                  ; no
get_key_shifted:
	lea	key_table_shifted(pc),a0        ; the shifted table
get_key_lookup:
	move.b	ws_shift(a5),d1                 ; Alternate and Control
	lsl.w	#8,d1
	andi.w	#$300,d1
	move.b	0(a0,d0.w),d1                   ; the character
	move.w	d1,d0
	cmp.w	#$7f,d0                         ; a character?
	bcs.s	get_key_done                    ; no
	bsr.w	to_capitals                     ; in capitals
get_key_done:
	movem.l	(sp)+,d1/a0
	bclr	#$6,$fffffa0f.w                 ; MFP ISRA, the keyboard's interrupt in service cleared
	rts

;------------------------------------------------------------------------------
; read_ikbd: the next byte from the keyboard ACIA.  A key held repeats it: after a wait of $C000 loops the
; first time, $1000 after.
;------------------------------------------------------------------------------
read_ikbd:	; from: get_key
	moveq	#0,d0
	move.w	ws_key_wait(a5),d1              ; the wait
read_ikbd_wait:
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the ACIA
	btst	#$7,d0                          ; a byte?
	bne.s	read_ikbd_byte                  ; yes
	dbra	d1,read_ikbd_wait
	move.w	#$1000,ws_key_wait(a5)          ; the repeat wait
	move.b	ws_key_held(a5),d0              ; a key held?
	beq.s	read_ikbd                       ; no: wait
	bra.s	read_ikbd_done                  ; yes: again
read_ikbd_byte:
	btst	#$0,d0                          ; received?
	bne.s	read_ikbd_data                  ; yes
	move.b	$fffffc02.w,d0                  ; keyboard ACIA data, an error: the byte dropped
	bra.s	read_ikbd

;------------------------------------------------------------------------------
; read_ikbd_data: the byte from the ACIA, kept as the key held (none for a release).
;------------------------------------------------------------------------------
read_ikbd_data:	; from: read_ikbd, poll_ikbd
	move.b	$fffffc02.w,d0                  ; keyboard ACIA data, the byte
	bclr	#$6,$fffffa11.w                 ; MFP ISRB, the ACIA's interrupt in service cleared
	move.b	d0,ws_key_held(a5)              ; the key held
	move.w	#$c000,ws_key_wait(a5)          ; the first wait
	btst	#$7,d0                          ; a release?
	beq.s	read_ikbd_done                  ; no
	clr.b	ws_key_held(a5)                 ; none held
read_ikbd_done:	; from: read_ikbd
	rts
get_key_caps_lock:	; from: get_key
	bchg	#$3,ws_shift(a5)                ; Caps Lock on or off
	bra.w	get_key_byte
get_key_control_on:	; from: get_key
	bset	#$1,ws_shift(a5)                ; Control
	bra.w	get_key_byte
get_key_control_off:	; from: get_key
	bclr	#$1,ws_shift(a5)
	bra.w	get_key_byte
get_key_alternate_on:	; from: get_key
	bset	#$0,ws_shift(a5)                ; Alternate
	bra.w	get_key_byte
get_key_alternate_off:	; from: get_key
	bclr	#$0,ws_shift(a5)
	bra.w	get_key_byte
get_key_shift_on:	; from: get_key
	bset	#$2,ws_shift(a5)                ; Shift
	bra.w	get_key_byte
get_key_shift_off:	; from: get_key
	bclr	#$2,ws_shift(a5)
	bra.w	get_key_byte

;------------------------------------------------------------------------------
; poll_ikbd: the next keyboard byte if there is one (Z clear), else Z set.
;------------------------------------------------------------------------------
poll_ikbd:	; from: find
	move.b	$fffffc00.w,d0                  ; keyboard ACIA control, the ACIA
	btst	#$7,d0                          ; a byte?
	beq.s	poll_ikbd_done                  ; no
	bsr.w	read_ikbd_data                  ; read
	tst.b	d0
poll_ikbd_done:
	rts

;------------------------------------------------------------------------------
; to_capitals: d0 in capitals if it is a small letter.
;------------------------------------------------------------------------------
to_capitals:	; from: command_loop, find, ask_yes_no, edit_memory, binary_load_save, get_key, 5 more
	cmp.b	#$61,d0                         ; below 'a'?
	bcs.s	to_capitals_done
	cmp.b	#$7a,d0                         ; above 'z'?
	bhi.s	to_capitals_done
	subi.b	#$20,d0
to_capitals_done:
	rts

;------------------------------------------------------------------------------
; input_value: the prompt a4, a line edited and evaluated.  d0 = the value and Z set; Z clear for escape.  A bad
; expression puts the cursor at the error to edit.
;------------------------------------------------------------------------------
input_value:	; from: set_window_base, evaluate, input_search_value, move_debugger, set_workspace, breakpoint_at
	moveq	#0,d2                           ; the cursor
	clr.b	ws_line(a5)                     ; the line empty
input_value_edit:
	movea.l	a4,a0                           ; the prompt
	bsr.w	print_message
	bsr.w	edit_line                       ; edited
	bne.s	input_value_escape              ; escape
	lea	ws_line(a5),a0                  ; the line
	bsr.w	evaluate_line                   ; evaluated
	beq.s	input_value_done                ; all right
	lea	ws_line_next(a5),a1
	suba.l	a1,a0
	move.l	a0,d2                           ; the cursor at the error
	bra.s	input_value_edit                ; again
input_value_done:
	bsr.w	clear_message                   ; the message line cleared
	ori.w	#$4,sr                          ; Z: the value
	rts
input_value_escape:
	bsr.w	clear_message
	andi.w	#$fffb,sr                       ; not Z
	rts

;------------------------------------------------------------------------------
; evaluate_line: the expression at a0, which must end the line.  d0 = its value, Z set; on an error the
; screen flashes, ws_value_error is set and Z clear.
;------------------------------------------------------------------------------
evaluate_line:	; from: set_register, set_label, input_value
	move.l	sp,ws_error_stack(a5)           ; the stack for an error
	sf	ws_errors_quiet(a5)             ; errors shown
	sf	ws_value_error(a5)              ; no error
	move.w	#$a,ws_token(a5)                ; a token to start
	bsr.w	next_token                      ; the first
	bsr.w	parse_sum                       ; the expression
	tst.w	ws_token(a5)                    ; the end of the line?
	bne.w	expression_error                ; no: an error
	rts

;------------------------------------------------------------------------------
; evaluate_next: the next expression at a0, up to the character that ends it (in ws_token), errors not shown.
;------------------------------------------------------------------------------
evaluate_next:	; from: input_three_values, input_file_values, draw_watch
	move.l	sp,ws_error_stack(a5)           ; the stack for an error
	sf	ws_value_error(a5)              ; no error
	st	ws_errors_quiet(a5)             ; errors not shown
	move.w	#$a,ws_token(a5)                ; a token to start
	bsr.w	next_token                      ; the first
	bsr.w	parse_sum                       ; the expression
	rts

;------------------------------------------------------------------------------
; parse_sum: terms with + and -.
;------------------------------------------------------------------------------
parse_sum:	; from: evaluate_line, evaluate_next, parse_factor
	move.l	d3,-(sp)
	bsr.w	parse_term                      ; the first term
	move.l	d0,d3
parse_sum_next:
	cmpi.w	#$2b,ws_token(a5)               ; '+'?
	beq.s	parse_sum_add
	cmpi.w	#$2d,ws_token(a5)               ; '-'?
	beq.s	parse_sum_subtract
	move.l	d3,d0
	move.l	(sp)+,d3
	rts
parse_sum_add:
	bsr.w	next_token
	bsr.w	parse_term                      ; the term
	add.l	d0,d3                           ; added
	bra.s	parse_sum_next
parse_sum_subtract:
	bsr.w	next_token
	bsr.w	parse_term                      ; the term
	sub.l	d0,d3                           ; subtracted
	bra.s	parse_sum_next

;------------------------------------------------------------------------------
; parse_term: logical terms with * and / (the quotient a word, and'ed with $7FFF; 0 for a division by 0).
;------------------------------------------------------------------------------
parse_term:	; from: parse_sum
	move.l	d3,-(sp)
	bsr.w	parse_logical                   ; the first
	move.l	d0,d3
parse_term_next:
	cmpi.w	#$2a,ws_token(a5)               ; '*'?
	beq.s	parse_term_multiply
	cmpi.w	#$2f,ws_token(a5)               ; '/'?
	beq.s	parse_term_divide
	move.l	d3,d0
	move.l	(sp)+,d3
	rts
parse_term_multiply:
	bsr.w	next_token
	bsr.w	parse_logical                   ; the next
	movem.l	d1-d2/d4,-(sp)                  ; saved
	moveq	#31,d4                          ; 32 bits
	moveq	#0,d2                           ; the product
parse_term_multiply_bit:
	lsl.l	#1,d2
	lsl.l	#1,d0                           ; the next bit
	bcc.s	parse_term_multiply_next        ; 0
	add.l	d3,d2                           ; 1: + the value
parse_term_multiply_next:
	dbra	d4,parse_term_multiply_bit
	move.l	d2,d3
	movem.l	(sp)+,d1-d2/d4
	bra.s	parse_term_next
	dc.w	$4afb                           ; not used
parse_term_divide:
	bsr.w	next_token
	bsr.w	parse_logical                   ; the next
	tst.w	d0                              ; by 0?
	beq.s	parse_term_divide_zero          ; yes: 0
	divu.w	d0,d3
	andi.l	#$7fff,d3                       ; the quotient
	bra.s	parse_term_next
parse_term_divide_zero:
	moveq	#0,d3
	bra.s	parse_term_next

;------------------------------------------------------------------------------
; parse_logical: factors with & (and), ! (or), ^ (eor), >> and <<.
;------------------------------------------------------------------------------
parse_logical:	; from: parse_term
	move.l	d3,-(sp)
	bsr.w	parse_factor                    ; the first
	move.l	d0,d3
parse_logical_next:
	cmpi.w	#$26,ws_token(a5)               ; '&'?
	beq.s	parse_logical_and
	cmpi.w	#$21,ws_token(a5)               ; '!'?
	beq.s	parse_logical_or
	cmpi.w	#$5e,ws_token(a5)               ; '^'?
	beq.s	parse_logical_eor
	cmpi.w	#$3e,ws_token(a5)               ; '>'?
	beq.s	parse_logical_right
	cmpi.w	#$3c,ws_token(a5)               ; '<'?
	beq.s	parse_logical_left
	move.l	d3,d0
	move.l	(sp)+,d3
	rts
parse_logical_and:
	bsr.w	next_token
	bsr.w	parse_factor                    ; the next
	and.l	d0,d3                           ; and
	bra.s	parse_logical_next
parse_logical_or:
	bsr.w	next_token
	bsr.w	parse_factor                    ; the next
	or.l	d0,d3                           ; or
	bra.s	parse_logical_next
parse_logical_eor:
	bsr.w	next_token
	bsr.w	parse_factor                    ; the next
	eor.l	d0,d3                           ; eor
	bra.s	parse_logical_next
parse_logical_right:
	bsr.w	next_token
	cmp.w	#$3e,d0                         ; '>' again?
	bne.w	expression_error                ; no: an error
	bsr.w	next_token
	bsr.w	parse_factor                    ; the next
	lsr.l	d0,d3                           ; shifted right
	bra.s	parse_logical_next
parse_logical_left:
	bsr.w	next_token
	cmp.w	#$3c,d0                         ; '<' again?
	bne.w	expression_error                ; no: an error
	bsr.w	next_token
	bsr.w	parse_factor                    ; the next
	lsl.l	d0,d3                           ; shifted left
	bra.w	parse_logical_next

;------------------------------------------------------------------------------
; parse_factor: (expression), [address][.B/.W/.L] (the memory there, long if not given), ~factor, $hex,
; %binary, a decimal number, or a register or label name (.B/.W/.L for a register).  A + or - here gives 0,
; so that -1 is 0-1.
;------------------------------------------------------------------------------
parse_factor:	; from: parse_logical
	cmpi.w	#$28,ws_token(a5)               ; '('?
	bne.s	parse_factor_memory             ; no
	bsr.w	next_token
	bsr.w	parse_sum                       ; the expression
	cmpi.w	#$29,ws_token(a5)               ; ')'?
	bne.w	expression_error                ; no: an error
	move.l	d0,-(sp)
	bsr.w	next_token
	move.l	(sp)+,d0
	rts
parse_factor_memory:
	cmpi.w	#$5b,ws_token(a5)               ; '['?
	bne.s	parse_factor_not                ; no
	bsr.w	next_token
	bsr.w	parse_sum                       ; the address
	cmpi.w	#$5d,ws_token(a5)               ; ']'?
	bne.w	expression_error                ; no: an error
	move.l	a1,-(sp)
	movea.l	d0,a1                           ; the address
	bsr.w	next_token
	moveq	#76,d1                          ; long if not given
	cmpi.w	#$2e,ws_token(a5)               ; '.'?
	bne.s	parse_factor_size               ; no
	bsr.w	next_token
	move.w	ws_token(a5),d0                 ; the size
	bsr.w	to_capitals                     ; in capitals
	move.w	d0,d1
	bsr.w	next_token
parse_factor_size:
	cmp.w	#$42,d1                         ; 'B'?
	beq.s	parse_factor_byte
	cmp.w	#$57,d1                         ; 'W'?
	beq.s	parse_factor_word
	cmp.w	#$4c,d1                         ; 'L'?
	beq.s	parse_factor_long
	bra.w	expression_error                ; none: an error
parse_factor_byte:
	move.b	(a1)+,d0                        ; the byte
	movea.l	(sp)+,a1
	rts
parse_factor_word:
	move.b	(a1)+,d0                        ; the word, by bytes
	lsl.w	#8,d0
	move.b	(a1)+,d0
	movea.l	(sp)+,a1
	rts
parse_factor_long:
	move.b	(a1)+,d0                        ; the long, by bytes
	lsl.w	#8,d0
	move.b	(a1)+,d0
	swap	d0
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	movea.l	(sp)+,a1
	rts
parse_factor_not:
	cmpi.w	#$7e,ws_token(a5)               ; '~'?
	bne.s	parse_factor_number             ; no
	bsr.w	next_token
	bsr.w	parse_factor                    ; the factor
	not.l	d0                              ; not
	rts
parse_factor_number:
	cmpi.w	#$24,ws_token(a5)               ; '$'?
	beq.w	parse_factor_hex                ; hex
	cmpi.w	#$25,ws_token(a5)               ; '%'?
	beq.w	parse_factor_binary             ; binary
	cmpi.w	#$2b,ws_token(a5)               ; '+'?
	beq.w	parse_factor_sign               ; 0
	cmpi.w	#$2d,ws_token(a5)               ; '-'?
	beq.w	parse_factor_sign               ; 0
	cmpi.w	#$30,ws_token(a5)               ; below '0'?
	bcs.w	parse_factor_name               ; a name
	cmpi.w	#$39,ws_token(a5)               ; above '9'?
	bhi.w	parse_factor_name               ; a name
	move.l	d3,-(sp)                        ; decimal
	moveq	#0,d3
	move.w	ws_token(a5),d3                 ; the first digit
	subi.w	#$30,d3
parse_factor_decimal:
	bsr.w	next_token
	move.w	ws_token(a5),d0
	subi.w	#$30,d0                         ; a digit?
	bcs.s	parse_factor_number_end         ; no: the end
	cmp.w	#$a,d0
	bcc.s	parse_factor_number_end
	add.l	d3,d3                           ; *2
	move.l	d3,-(sp)
	lsl.l	#2,d3                           ; *8
	add.l	(sp)+,d3                        ; *10
	add.l	d0,d3                           ; + the digit
	bra.s	parse_factor_decimal
parse_factor_number_end:
	move.l	d3,d0
	move.l	(sp)+,d3
	rts
parse_factor_sign:
	clr.l	d0                              ; 0
	rts
parse_factor_hex:
	bsr.w	hex_digit                       ; a hex digit
	bne.w	expression_error                ; none: an error
	move.l	d3,-(sp)
	moveq	#0,d3
	move.w	d0,d3
parse_factor_hex_digit:
	bsr.w	hex_digit                       ; the next
	bne.s	parse_factor_value              ; the end
	lsl.l	#4,d3
	add.l	d0,d3                           ; + the digit
	bra.s	parse_factor_hex_digit
parse_factor_value:
	move.l	d3,d0
	move.l	(sp)+,d3
	rts
parse_factor_binary:
	clr.l	d0
	bsr.w	next_token
	subi.w	#$30,d0                         ; '0' or '1'?
	bcs.w	expression_error                ; no: an error
	cmp.w	#$1,d0
	bhi.w	expression_error
	move.l	d3,-(sp)
	move.l	d0,d3
parse_factor_binary_digit:
	bsr.w	next_token
	subi.w	#$30,d0                         ; '0' or '1'?
	bcs.s	parse_factor_value              ; no: the end
	cmp.w	#$1,d0
	bhi.s	parse_factor_value
	lsl.l	#1,d3
	add.l	d0,d3                           ; + the digit
	bra.s	parse_factor_binary_digit

;------------------------------------------------------------------------------
; hex_digit: the next character as a hex digit in d0 (Z set), or Z clear.
;------------------------------------------------------------------------------
hex_digit:	; from: parse_factor
	moveq	#0,d0
	bsr.w	next_token                      ; the next
	bsr.w	to_capitals                     ; in capitals
	cmp.w	#$30,d0                         ; '0'-'9'?
	bcs.s	hex_digit_none
	cmp.w	#$39,d0
	bls.s	hex_digit_number
	cmp.w	#$41,d0                         ; 'A'-'F'?
	bcs.s	hex_digit_none
	cmp.w	#$46,d0
	bhi.s	hex_digit_none
	subq.w	#7,d0
hex_digit_number:
	subi.w	#$30,d0
	ori.w	#$4,sr                          ; Z
	rts
hex_digit_none:
	moveq	#1,d0                           ; not Z
	rts
parse_factor_name:	; from: parse_factor
	movem.l	d1-d3/a1-a3,-(sp)               ; saved
	bsr.w	read_name                       ; the name
	bsr.w	find_register                   ; a register?
	beq.s	parse_factor_register           ; yes
	bsr.w	find_label                      ; a label?
	bne.w	expression_error                ; no: an error
	move.l	8(a1),d0                        ; its value
	bra.s	parse_factor_done
parse_factor_register:
	moveq	#76,d2                          ; long if not given
	cmpi.w	#$2e,ws_token(a5)               ; '.'?
	bne.s	parse_factor_register_size      ; no
	bsr.w	next_token
	move.w	ws_token(a5),d0                 ; the size
	bsr.w	to_capitals                     ; in capitals
	move.w	d0,d2
	bsr.w	next_token
parse_factor_register_size:
	tst.w	d1                              ; a word register?
	beq.s	parse_factor_register_read      ; no
	subq.w	#2,a1                           ; its word
	cmp.w	#$4c,d2                         ; long?
	bne.s	parse_factor_register_read      ; no
	moveq	#87,d2                          ; a word then
parse_factor_register_read:
	move.b	(a1)+,d0                        ; the value, by bytes
	lsl.w	#8,d0
	move.b	(a1)+,d0
	swap	d0
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	cmp.w	#$4c,d2                         ; long?
	beq.s	parse_factor_done               ; yes
	andi.l	#$ffff,d0
	cmp.w	#$57,d2                         ; word?
	beq.s	parse_factor_done               ; yes
	andi.w	#$ff,d0
	cmp.w	#$42,d2                         ; byte?
	bne.w	expression_error                ; no: an error
parse_factor_done:
	movem.l	(sp)+,d1-d3/a1-a3
	rts

;------------------------------------------------------------------------------
; is_name_char: d1 = 1 if the character in ws_token can be in a name (letters, digits, '_').
;------------------------------------------------------------------------------
is_name_char:	; from: read_name
	move.w	ws_token(a5),d0
	bsr.w	to_capitals                     ; in capitals
	cmp.w	#$30,d0                         ; '0'-'9'?
	bcs.s	is_name_char_no
	cmp.w	#$39,d0
	bls.s	is_name_char_yes
	cmp.w	#$5f,d0                         ; '_'?
	beq.s	is_name_char_yes
	cmp.w	#$41,d0                         ; 'A'-'Z'?
	bcs.s	is_name_char_no
	cmp.w	#$5a,d0
	bls.s	is_name_char_yes
	cmp.w	#$61,d0                         ; 'a'-'z'?
	bcs.s	is_name_char_no
	cmp.w	#$7a,d0
	bhi.s	is_name_char_no
is_name_char_yes:
	moveq	#1,d1
	rts
is_name_char_no:
	moveq	#0,d1
	rts

;------------------------------------------------------------------------------
; read_name: a name of up to 8 characters into ws_name (an error if none).
;------------------------------------------------------------------------------
read_name:	; from: set_register, set_label, lock_window, hex_digit
	lea	ws_name(a5),a1
	moveq	#7,d2                           ; 8
	bsr.w	is_name_char                    ; a name character?
	beq.w	expression_error                ; no: an error
read_name_char:
	move.b	d0,(a1)+
	bsr.w	next_token                      ; the next
	bsr.w	is_name_char
	beq.s	read_name_end                   ; the end
	dbra	d2,read_name_char
read_name_end:
	clr.b	(a1)+                           ; ended
	rts

;------------------------------------------------------------------------------
; find_register: ws_name in register_names: a1 = the register in the workspace, d1 $8000 for a word register,
; Z set; else Z clear.
;------------------------------------------------------------------------------
find_register:	; from: set_register, set_label, lock_window, hex_digit
	lea	register_names(pc),a2           ; the names
	lea	register_offsets(pc),a1         ; their places
	moveq	#1,d2
find_register_next:
	tst.b	(a2)                            ; the end?
	beq.s	find_register_none              ; yes: not one
	moveq	#7,d1                           ; 8
	lea	ws_name(a5),a3                  ; the name
find_register_compare:
	tst.b	(a2)                            ; its end?
	beq.s	find_register_end               ; yes
	cmpm.b	(a3)+,(a2)+                     ; the same?
	bne.s	find_register_skip              ; no
	dbra	d1,find_register_compare
find_register_end:
	tst.b	(a3)                            ; the name's end too?
	bne.s	find_register_skip              ; no
	move.w	(a1),d1                         ; its place
	move.w	d1,d0
	andi.w	#$7fff,d0
	movea.l	a5,a1
	adda.w	d0,a1                           ; in the workspace
	andi.w	#$8000,d1                       ; the word flag
	moveq	#0,d0                           ; Z
	rts
find_register_skip:
	tst.b	(a2)+                           ; to the next name
	bne.s	find_register_skip
	addq.w	#2,a1
	addq.w	#1,d2
	bra.s	find_register_next
find_register_none:
	moveq	#1,d0
	rts

;------------------------------------------------------------------------------
; find_label: ws_name in the label table (12-byte entries: 8 characters, a value; 0 or minus ends it): a1 =
; the entry, Z set; else a1 = the table's end, Z clear.
;------------------------------------------------------------------------------
find_label:	; from: set_label, hex_digit
	move.l	ws_symtab(a5),d0                ; the label table
	andi.l	#$fffffe,d0                     ; even
	movea.l	d0,a2
	beq.w	find_label_none                 ; none
find_label_next:
	movea.l	a2,a1
	tst.b	(a2)                            ; the end?
	beq.s	find_label_none
	bmi.s	find_label_none
	lea	ws_name(a5),a3                  ; the name
	moveq	#7,d1                           ; 8
find_label_compare:
	move.b	(a2)+,d0                        ; the label's
	beq.s	find_label_end                  ; its end
	bsr.w	to_capitals                     ; in capitals
	cmp.b	(a3)+,d0                        ; the same?
	bne.s	find_label_skip                 ; no
	dbra	d1,find_label_compare
	bra.s	find_label_end
find_label_skip:
	lea	$c(a1),a2                       ; the next entry
	bra.s	find_label_next
find_label_end:
	tst.b	(a3)                            ; the name's end too?
	bne.s	find_label_skip                 ; no
	moveq	#0,d0                           ; Z
	rts
find_label_none:
	movea.l	a2,a1                           ; the table's end
	moveq	#1,d0                           ; not Z
	rts

;------------------------------------------------------------------------------
; find_label_value: the label with the value d0: a0 = its name, d2 = 0; d2 = 1 if none.
;------------------------------------------------------------------------------
find_label_value:	; from: copy_label_name, put_address
	move.l	a2,-(sp)                        ; saved
	move.l	d1,-(sp)
	movea.l	$38.w,a2                        ; the workspace
	move.l	$64(a2),d1                      ; the label table
	andi.l	#$fffffe,d1                     ; even
	beq.s	find_label_value_none           ; none
	movea.l	d1,a2
find_label_value_next:
	movea.l	a2,a0
	tst.b	(a2)                            ; the end?
	beq.s	find_label_value_none           ; yes
	lea	8(a2),a2
	cmp.l	(a2)+,d0                        ; its value?
	bne.s	find_label_value_next           ; no
	move.l	(sp)+,d1
	movea.l	(sp)+,a2
	moveq	#0,d2                           ; found
	rts
find_label_value_none:
	move.l	(sp)+,d1
	movea.l	(sp)+,a2
	moveq	#1,d2                           ; none
	rts

;------------------------------------------------------------------------------
; copy_label_name: the label with the value d0, if any, into the disassembly line's label place.
;------------------------------------------------------------------------------
copy_label_name:	; from: draw_disassembly_line
	movem.l	d0/d2/a0/a2,-(sp)               ; saved
	bsr.w	find_label_value                ; the label
	bne.s	copy_label_name_done            ; none
	lea	ws_line_label(a5),a2            ; the label's place
	moveq	#7,d0                           ; 8
copy_label_name_char:
	move.b	(a0)+,d2
	beq.s	copy_label_name_done            ; its end
	move.b	d2,(a2)+
	dbra	d0,copy_label_name_char
copy_label_name_done:
	movem.l	(sp)+,d0/d2/a0/a2
	rts

;------------------------------------------------------------------------------
; next_token: the next non-space character into ws_token and d0 (stays 0 at the end of the line).
;------------------------------------------------------------------------------
next_token:	; from: set_register, set_label, lock_window, input_file_values, evaluate_line, evaluate_next, 7 more
	tst.w	ws_token(a5)                    ; the end?
	beq.s	next_token_done                 ; yes
	moveq	#0,d0
	move.b	(a0)+,d0                        ; the next
	move.w	d0,ws_token(a5)
	cmp.w	#$20,d0                         ; a space?
	beq.s	next_token                      ; yes: skipped
next_token_done:
	rts

;------------------------------------------------------------------------------
; expression_error: back to the caller of evaluate_line or evaluate_next with ws_value_error set, Z clear, the
; screen flashed if errors are shown.
;------------------------------------------------------------------------------
expression_error:	; from: set_register, set_label, evaluate_line, parse_logical, parse_factor, hex_digit, 1 more
	movea.l	ws_error_stack(a5),sp
	st	ws_value_error(a5)              ; an error
	tst.b	ws_errors_quiet(a5)             ; errors shown?
	bne.s	expression_error_done           ; no
	bsr.w	flash_screen                    ; flashed
expression_error_done:
	clr.w	ws_token(a5)                    ; the end
	andi.w	#$fffb,sr                       ; not Z
	rts

;------------------------------------------------------------------------------
; flash_screen: the background inverted for a moment.
;------------------------------------------------------------------------------
flash_screen:	; from: input_three_values, set_register, set_label, edit_watch, lock_window, input_file_values, 1 more
	move.l	a0,-(sp)
	lea	$ffff8240.w,a0                  ; palette 0
	not.w	(a0)                            ; inverted
	move.w	#$3264,d1
flash_screen_wait:
	dbra	d1,flash_screen_wait
	not.w	(a0)                            ; back
	movea.l	(sp)+,a0
	rts

;------------------------------------------------------------------------------
; get_key_cursor: a key with the cursor shown.
;------------------------------------------------------------------------------
get_key_cursor:	; from: find, ask_yes_no, edit_memory, binary_load_save, edit_line
	bsr.w	toggle_cursor                   ; the cursor on
	bsr.w	get_key                         ; the key
	bra.w	toggle_cursor                   ; the cursor off

;------------------------------------------------------------------------------
; input_line: edit_line with the line empty.
;------------------------------------------------------------------------------
input_line:	; from: find, lock_window, load_executable
	clr.b	ws_line(a5)
	moveq	#0,d2                           ; the cursor

;------------------------------------------------------------------------------
; edit_line: the line at ws_line edited on the bottom row from the cursor's column, d2 the cursor in it:
; characters put in, Backspace, Delete, Control X (all out), left and right, Control left and right (start
; and end).  Return gives d0 = 0, escape or Control C 1.
;------------------------------------------------------------------------------
edit_line:	; from: input_three_values, set_register, set_label, edit_watch, input_file_values, input_value
	move.w	#$20,ws_token(a5)
	lea	ws_line(a5),a3                  ; the line
	movea.l	a3,a0
	moveq	#0,d3                           ; its length
	tst.w	d2                              ; a cursor given?
	bne.s	edit_line_length                ; yes
	move.w	d3,d2                           ; no: at the start
edit_line_length:
	tst.b	(a0)+
	beq.s	edit_line_column
	addq.w	#1,d3
	bra.s	edit_line_length
edit_line_column:
	move.w	ws_column(a5),ws_scratch(a5)    ; the column kept
edit_line_draw:
	lea	ws_line(a5),a0                  ; the line
	move.w	ws_scratch(a5),ws_column(a5)
	move.w	#$1c,ws_row(a5)                 ; the bottom row
	bsr.w	print_text                      ; printed
	move.w	ws_column(a5),ws_line_end(a5)   ; its end's column
	move.w	#$c7,d0                         ; a space (the cursor's block)
	bsr.w	print_char
	move.w	d2,d0                           ; the cursor
	add.w	ws_scratch(a5),d0
	move.w	d0,ws_column(a5)
	bsr.w	get_key_cursor                  ; a key
	cmp.b	#$1b,d0                         ; escape?
	beq.w	edit_line_escape
	cmp.w	#$243,d0                        ; ^C?
	beq.w	edit_line_escape
	cmp.w	#$d,d0                          ; Return?
	beq.s	edit_line_return
	cmp.w	#$8,d0                          ; Backspace?
	beq.s	edit_line_backspace
	cmp.w	#$7f,d0                         ; Delete?
	beq.w	edit_line_delete
	cmp.w	#$258,d0                        ; ^X?
	beq.w	edit_line_clear
	cmp.w	#$3,d0                          ; left?
	beq.w	edit_line_left
	cmp.w	#$4,d0                          ; right?
	beq.w	edit_line_right
	cmp.w	#$203,d0                        ; Control left?
	beq.w	edit_line_start
	cmp.w	#$204,d0                        ; Control right?
	beq.w	edit_line_end
	cmp.w	#$20,d0                         ; a character?
	bcs.w	edit_line_draw
	cmp.w	#$7f,d0
	bcc.w	edit_line_draw
	cmpi.w	#$4e,ws_line_end(a5)            ; the line full?
	bcc.w	edit_line_draw                  ; yes
	lea	0(a3,d3.w),a0                   ; the end
	lea	0(a3,d2.w),a1                   ; the cursor
edit_line_open:
	cmpa.l	a1,a0
	bcs.s	edit_line_insert
	move.b	(a0),1(a0)                      ; moved up
	subq.w	#1,a0
	bra.s	edit_line_open
edit_line_insert:
	move.b	d0,0(a3,d2.w)                   ; put in
	addq.w	#1,d2
	addq.w	#1,d3
	clr.b	0(a3,d3.w)                      ; ended
	bra.w	edit_line_draw
edit_line_return:
	clr.b	0(a3,d3.w)                      ; ended
	moveq	#0,d0                           ; 0
	rts
edit_line_escape:
	moveq	#1,d0                           ; 1
	rts
edit_line_backspace:
	tst.w	d2                              ; at the start?
	beq.w	edit_line_draw                  ; yes
	lea	0(a3,d2.w),a0
edit_line_close:
	tst.b	(a0)
	beq.s	edit_line_closed
	move.b	(a0)+,-$2(a0)                   ; moved down
	bra.s	edit_line_close
edit_line_closed:
	subq.w	#1,d2
	subq.w	#1,d3
	clr.b	0(a3,d3.w)                      ; ended
	bra.w	edit_line_draw
edit_line_delete:
	cmp.w	d2,d3                           ; at the end?
	beq.w	edit_line_draw                  ; yes
	addq.w	#1,d2                           ; the one after
	bra.s	edit_line_backspace
edit_line_clear:
	moveq	#0,d2
	moveq	#0,d3
	clr.b	(a3)                            ; empty
	move.w	ws_scratch(a5),ws_column(a5)
edit_line_clear_column:
	move.w	#$c7,d0                         ; spaces
	bsr.w	print_char
	cmpi.w	#$4e,ws_column(a5)              ; to the end of the row
	bcs.s	edit_line_clear_column
	bra.w	edit_line_draw
edit_line_left:
	tst.w	d2                              ; at the start?
	beq.w	edit_line_draw                  ; yes
	subq.w	#1,d2
	bra.w	edit_line_draw
edit_line_right:
	cmp.w	d2,d3                           ; at the end?
	bls.w	edit_line_draw                  ; yes
	addq.w	#1,d2
	bra.w	edit_line_draw
edit_line_end:
	move.w	d3,d2
	bra.w	edit_line_draw
edit_line_start:
	moveq	#0,d2
	bra.w	edit_line_draw

;------------------------------------------------------------------------------
; init_workspace: the workspace at a0 (a1 the label table, a2 the program's screen pointer): the vectors
; $8-$27 kept, the windows, breakpoints and watches set up, the 'SHIT' magic, then take_vectors.
;------------------------------------------------------------------------------
init_workspace:	; from: init_workspace_keep, reinit_workspace
	move.l	a0,$38.w                        ; the workspace
	movea.l	$38.w,a5
	move.l	a1,ws_symtab(a5)                ; the label table
	move.l	a2,ws_vidptr(a5)                ; the screen pointer
	lea	ws_vectors(a5),a0               ; the program's vectors
	movea.w	#$8,a1                          ; from $8
	moveq	#7,d0                           ; 8
init_workspace_vectors:
	move.l	(a1)+,(a0)+                     ; kept
	dbra	d0,init_workspace_vectors
	clr.b	ws_inverse(a5)                  ; no inverse
	lea	exception_ignore(pc),a0         ; faults: rte
	move.l	a0,ws_fault(a5)
	sf	ws_w4_open(a5)                  ; W4 closed
	sf	ws_w3_open(a5)                  ; W3 closed
	sf	ws_drawn(a5)                    ; the screen not drawn
	moveq	#-1,d0
	moveq	#4,d1                           ; 5
	lea	ws_temp_breakpoint(a5),a0       ; the temporary breakpoint and the four
init_workspace_breakpoints:
	move.l	d0,(a0)+                        ; free
	dbra	d1,init_workspace_breakpoints
	move.b	#$1,ws_window(a5)               ; W1 current
	move.b	#$12,ws_locks(a5)               ; W1 locked to PC
	clr.b	ws_lock_w3(a5)                  ; W2-W4 not locked
	clr.b	ws_lock_w2(a5)
	clr.b	ws_lock_w4(a5)
	clr.l	ws_w2(a5)                       ; the windows' bases
	clr.l	ws_w4(a5)
	clr.l	ws_w1(a5)
	clr.l	ws_w3(a5)
	clr.l	ws_w2_end(a5)
	clr.l	ws_w4_end(a5)
	clr.l	ws_w1_end(a5)                   ; and ends
	clr.l	ws_w3_end(a5)
	clr.w	ws_watch(a5)                    ; the first watch
	lea	ws_watches(a5),a0               ; the watches
	lea	first_watches(pc),a1            ; "BP0", "BP1", "BP2", "BP3"
init_workspace_watches:
	move.b	(a1)+,(a0)+                     ; copied
	cmpi.b	#$24,(a1)                       ; to the '$'
	bne.s	init_workspace_watches
	move.l	#$53484954,ws_magic(a5)         ; the magic

;------------------------------------------------------------------------------
; take_vectors: the exception vectors pointed at the monitor: $8-$27 first all to the spurious entry, then bus and
; address error, divide by zero (ignored), traps #3-#12 and #15, CHK, TRAPV, privilege and illegal.
;------------------------------------------------------------------------------
take_vectors:	; from: monitor_restart
	lea	exception_spurious(pc),a2
	movea.w	#$8,a1                          ; from $8
	moveq	#7,d0                           ; 8
take_vectors_default:
	move.l	a2,(a1)+
	dbra	d0,take_vectors_default
	lea	exception_bus_error(pc),a1      ; bus error
	move.l	a1,$8.w                         ; bus error vector
	lea	exception_address_error(pc),a1  ; address error
	move.l	a1,$c.w                         ; address error vector
	lea	exception_ignore(pc),a1         ; divide by zero: rte
	move.l	a1,$14.w
	lea	exception_trap_3(pc),a1         ; trap #3
	move.l	a1,$8c.w
	lea	exception_trap_5(pc),a1         ; trap #5
	move.l	a1,$94.w
	lea	exception_trap_6(pc),a1         ; trap #6
	move.l	a1,$98.w
	lea	exception_trap_7(pc),a1         ; trap #7
	move.l	a1,$9c.w
	lea	exception_trap_8(pc),a1         ; trap #8
	move.l	a1,$a0.w
	lea	exception_trap_9(pc),a1         ; trap #9
	move.l	a1,$a4.w
	lea	exception_trap_10(pc),a1        ; trap #10
	move.l	a1,$a8.w
	lea	exception_trap_11(pc),a1        ; trap #11
	move.l	a1,$ac.w
	lea	exception_trap_12(pc),a1        ; trap #12
	move.l	a1,$b0.w
	lea	exception_trap_15(pc),a1        ; trap #15
	move.l	a1,$bc.w
	lea	exception_chk(pc),a1            ; CHK
	move.l	a1,$18.w
	lea	exception_trapv(pc),a1          ; TRAPV
	move.l	a1,$1c.w
	lea	exception_privilege(pc),a1      ; privilege violation
	move.l	a1,$20.w
	lea	exception_illegal(pc),a1        ; illegal instruction
	move.l	a1,$10.w                        ; illegal instr vector
	clr.b	ws_shift(a5)                    ; no shift keys
	clr.b	ws_key_held(a5)                 ; no key held
	rts

;------------------------------------------------------------------------------
; set_screen: the screen at d0, set where the video counter is still (in the blank).
;------------------------------------------------------------------------------
set_screen:	; from: quit_monitor, show_program_screen, show_monitor_screen
	movem.l	d0-d1,-(sp)
set_screen_wait:
	move.b	$ffff8209,d1                    ; video count low, the video counter
	moveq	#100,d0
set_screen_delay:
	dbra	d0,set_screen_delay
	cmp.b	$ffff8209,d1                    ; video count low, moved?
	bne.s	set_screen_wait                 ; yes: again
	movem.l	(sp)+,d0-d1
	andi.l	#$ffffff,d0
	asr.w	#8,d0
	move.l	d0,$ffff8200.w                  ; high and mid
	rts

;------------------------------------------------------------------------------
; draw_screen: the windows locked to registers set from them, then the whole screen drawn.
;------------------------------------------------------------------------------
draw_screen:	; from: monitor_restart, help, draw_windows, enter_monitor_saved
	movea.l	$38.w,a5                        ; the workspace
	bsr.w	follow_registers                ; the locked windows

;------------------------------------------------------------------------------
; draw_frame: the monitor's screen shown and cleared, the frame and the titles, then the windows.
;------------------------------------------------------------------------------
draw_frame:	; from: set_workspace, zoom_window
	bsr.w	show_monitor_screen             ; shown
	bsr.w	clear_screen                    ; cleared
	clr.w	ws_column(a5)
	clr.w	ws_row(a5)
	lea	screen_rows(pc),a0              ; the normal rows
	move.l	a0,ws_rows(a5)
	lea	frame_text(pc),a0               ; the frame
	bsr.w	print_text
	bsr.w	draw_lower_frame                ; the lower windows' frame
	bsr.w	draw_titles                     ; the titles
	st	ws_drawn(a5)                    ; drawn

;------------------------------------------------------------------------------
; draw_windows: the disassembly windows, the registers, the watches and the memory windows (the whole screen if
; not drawn yet).
;------------------------------------------------------------------------------
draw_windows:	; from: set_window_base, fill_memory, find, set_label, edit_memory, binary_load_save, 2 more
	tst.b	ws_drawn(a5)                    ; drawn?
	beq.s	draw_screen                     ; no: all of it
	bsr.w	draw_disassembly                ; the disassembly
	bsr.w	draw_registers                  ; the registers
	bsr.w	draw_watches                    ; the watches
	bra.w	draw_memory                     ; the memory

;------------------------------------------------------------------------------
; redraw_windows: the locked windows set, then draw_windows.
;------------------------------------------------------------------------------
redraw_windows:                                 ; from: skip_instruction, set_register, edit_memory_write, lock_window,
                                                ;   load_executable, enter_monitor_saved
	bsr.w	follow_registers
	bra.s	draw_windows

;------------------------------------------------------------------------------
; clear_screen: the monitor's screen cleared, the cursor home, the first font.
;------------------------------------------------------------------------------
clear_screen:	; from: help, zoom_window, draw_frame
	lea	ws_screen(a5),a0                ; the screen
	moveq	#0,d1
	move.w	#$1f3f,d0                       ; 32000 bytes
clear_screen_long:
	move.l	d1,(a0)+                        ; cleared
	dbra	d0,clear_screen_long
	clr.w	ws_column(a5)
	clr.w	ws_row(a5)
	lea	font_one(pc),a0                 ; the first font
	move.l	a0,ws_font(a5)
	rts

;------------------------------------------------------------------------------
; draw_titles: the windows' titles, with their locks ("W1 DISASSEMBLY(PC)"), the current one in inverse.
;------------------------------------------------------------------------------
draw_titles:	; from: next_window, split_window, lock_window, draw_frame
	lea	window_titles(pc),a0            ; the titles
	lea	ws_locks(a5),a1                 ; the locks
	moveq	#2,d2                           ; W1, W2, the watches
	moveq	#0,d3
draw_titles_next:
	bsr.w	draw_title
	dbra	d2,draw_titles_next
	tst.b	ws_w3_open(a5)                  ; W3 open?
	beq.s	draw_titles_skip                ; no
	movem.l	a0-a1,-(sp)
	bsr.w	draw_title
	movem.l	(sp)+,a0-a1
draw_titles_skip:
	addq.w	#3,a0
	addq.w	#1,a1
draw_titles_skip_text:
	tst.b	(a0)+                           ; past W3's title
	bne.s	draw_titles_skip_text
	tst.b	ws_w4_open(a5)                  ; W4 open?
	beq.s	draw_titles_done                ; no
	bsr.w	draw_title
draw_titles_done:
	rts

;------------------------------------------------------------------------------
; draw_title: the title at a0 (its window number, column and row first) and its lock from a1.
;------------------------------------------------------------------------------
draw_title:	; from: draw_titles
	move.b	(a0)+,d3                        ; the window
	move.b	(a0)+,ws_row_low(a5)            ; the column
	move.b	(a0)+,ws_column_low(a5)         ; the row
	cmp.b	ws_window(a5),d3                ; the current one?
	bne.s	draw_title_text                 ; no
	bset	#$0,ws_inverse(a5)              ; inverse
draw_title_text:
	bsr.w	print_text                      ; printed
	tst.w	d3                              ; the watches?
	beq.s	draw_title_done                 ; yes: no lock
	move.l	a0,-(sp)
	moveq	#0,d0
	move.b	(a1)+,d0                        ; the lock
	beq.s	draw_title_no_lock              ; none
	subq.w	#1,d0
	bmi.s	draw_title_no_lock
	add.w	d0,d0
	lea	register_names_short(pc,d0.w),a0 ; its name
	bsr.w	print_space                     ; '('
	move.b	(a0)+,d0
	bsr.w	print_char
	move.b	(a0)+,d1
	move.b	d1,d0
	bsr.w	print_char
	cmp.b	#$53,d1                         ; 'S' (SR or SS)?
	bne.s	draw_title_lock_done            ; no
	move.b	#$50,d0                         ; 'P' (SP)
	bsr.w	print_char
draw_title_lock_done:
	movea.l	(sp)+,a0
draw_title_done:
	bclr	#$0,ws_inverse(a5)
	rts
draw_title_no_lock:
	bclr	#$0,ws_inverse(a5)
	lea	no_lock_text(pc),a0             ; "ggggg" (the frame)
	bsr.w	print_text
	bra.s	draw_title_lock_done

;------------------------------------------------------------------------------
; register_names_short: two characters for each register that a window can be locked to.
;------------------------------------------------------------------------------
register_names_short:	; from: draw_title
	dc.b	'D0D1D2D3D4D5D6D7A0A1A2A3A4A5A6A7SRPCSPUSSSW1W2W3W4'

;------------------------------------------------------------------------------
; draw_lower_frame: the frame of the lower windows (W3, W4, both or neither).
;------------------------------------------------------------------------------
draw_lower_frame:	; from: split_window, draw_frame
	lea	lower_frame_none(pc),a0         ; neither
	tst.b	ws_w3_open(a5)                  ; W3 open?
	beq.s	draw_lower_frame_w4             ; no
	lea	lower_frame_w3(pc),a0           ; W3
	tst.b	ws_w4_open(a5)                  ; W4 open?
	beq.s	draw_lower_frame_go             ; no
	lea	lower_frame_both(pc),a0         ; both
	bra.s	draw_lower_frame_go
draw_lower_frame_w4:
	tst.b	ws_w4_open(a5)                  ; W4 open?
	beq.s	draw_lower_frame_go             ; no
	lea	lower_frame_w4(pc),a0           ; W4
draw_lower_frame_go:
	clr.w	ws_column(a5)
	move.w	#$11,ws_row(a5)                 ; row 17
	bsr.w	print_text                      ; printed
	rts

;------------------------------------------------------------------------------
; follow_registers: each window locked to a register set to its value, when it is not shown already.
;------------------------------------------------------------------------------
follow_registers:	; from: draw_screen, redraw_windows
	lea	ws_w1(a5),a0                    ; the bases
	lea	register_offsets(pc),a1         ; the register places
	lea	ws_w1_end(a5),a3                ; the ends
	lea	ws_locks(a5),a4                 ; the locks
	moveq	#3,d1                           ; 4
follow_registers_next:
	moveq	#0,d0
	move.b	(a4)+,d0                        ; the lock
	beq.s	follow_registers_skip           ; none
	subq.w	#1,d0
	add.w	d0,d0
	move.w	0(a1,d0.w),d0                   ; its place
	move.l	0(a5,d0.w),d0                   ; its value
	cmp.l	(a0),d0                         ; below the base?
	bls.s	follow_registers_set            ; yes: moved
	move.l	(a0),d2
	cmp.l	(a3),d2                         ; the window past its end?
	bcc.s	follow_registers_set
	cmp.l	(a3),d0                         ; inside the window?
	bcs.s	follow_registers_skip           ; yes: not moved
follow_registers_set:
	move.l	d0,(a0)                         ; moved
follow_registers_skip:
	addq.w	#4,a0
	addq.w	#4,a3
	dbra	d1,follow_registers_next
	rts

;------------------------------------------------------------------------------
; draw_disassembly: W1 (11 or 5 lines from row 11) and W3 (4 from row 18) disassembled.
;------------------------------------------------------------------------------
draw_disassembly:	; from: cursor_right, cursor_left, cursor_down, cursor_up, page_down, edit_memory_write, 2 more
	move.w	#$b,d1                          ; row 11
	movea.l	ws_w1(a5),a1                    ; W1's base
	moveq	#5,d2                           ; 6 lines
	tst.b	ws_w3_open(a5)                  ; split?
	bne.s	draw_disassembly_split          ; yes
	addq.w	#6,d2                           ; 12 lines
	bsr.s	draw_disassembly_lines
	move.l	a1,ws_w1_end(a5)                ; its end
	rts
draw_disassembly_split:
	bsr.s	draw_disassembly_lines
	move.l	a1,ws_w1_end(a5)                ; its end
	movea.l	ws_w3(a5),a1                    ; W3's base
	move.w	#$12,d1                         ; row 18
	moveq	#4,d2                           ; 5 lines
	bsr.w	draw_disassembly_lines
	move.l	a1,ws_w3_end(a5)                ; its end
	rts

draw_disassembly_lines:	; from: draw_disassembly
	moveq	#20,d7                          ; 20 columns for the address

;------------------------------------------------------------------------------
; draw_disassembly_line: d2+1 lines from a1 on row d1 on: each disassembled with its label, the pc's line in
; inverse, a breakpoint's number in the margin.
;------------------------------------------------------------------------------
draw_disassembly_line:	; from: zoom_window
	move.l	a1,d3                           ; the address
	bsr.w	disassemble                     ; disassembled
	move.l	d3,d0
	bsr.w	copy_label_name                 ; its label
	lea	ws_line(a5),a0                  ; the line
	move.b	#$0,$36(a0)                     ; ended
	move.w	d1,ws_row(a5)                   ; the row
	move.w	#$1,ws_column(a5)               ; column 1
	cmp.l	ws_pc(a5),d3                    ; the pc?
	bne.s	draw_disassembly_breakpoint     ; no
	bset	#$0,ws_inverse(a5)              ; inverse
draw_disassembly_breakpoint:
	move.l	a2,-(sp)
	moveq	#48,d0                          ; '0'
	lea	ws_breakpoints(a5),a2           ; the breakpoints
	cmp.l	(a2)+,d3                        ; the first?
	beq.s	draw_disassembly_bp1
	cmp.l	(a2)+,d3                        ; the second?
	beq.s	draw_disassembly_bp2
	cmp.l	(a2)+,d3                        ; the third?
	beq.s	draw_disassembly_bp3
	cmp.l	(a2)+,d3                        ; the fourth?
	bne.s	draw_disassembly_print          ; no
	addq.w	#1,d0
draw_disassembly_bp3:
	addq.w	#1,d0
draw_disassembly_bp2:
	addq.w	#1,d0
draw_disassembly_bp1:
	move.b	d0,$13(a0)                      ; its number in the margin
draw_disassembly_print:
	movea.l	(sp)+,a2
	bsr.w	print_text                      ; printed
	bclr	#$0,ws_inverse(a5)
	addq.w	#1,d1                           ; the next row
	dbra	d2,draw_disassembly_line
	rts

;------------------------------------------------------------------------------
; draw_registers: D0-D7 (each with the word at its value), A0-A7, USP and SSP (each with 5 words at it), the
; instruction at pc, and SR with its flags and IPL.
;------------------------------------------------------------------------------
draw_registers:	; from: draw_windows
	lea	ws_d0(a5),a0                    ; the registers
	lea	register_places(pc),a3          ; their columns and rows
	moveq	#7,d1                           ; D0-D7
draw_registers_data:
	move.w	(a3)+,ws_column(a5)
	move.w	(a3)+,ws_row(a5)
	movea.l	(a0)+,a1                        ; the value
	move.l	a1,d0
	bsr.w	print_hex_long                  ; printed
	bsr.w	print_char_dot
	addi.w	#$1,ws_column(a5)
	move.b	(a1)+,d0                        ; the word at it
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word_tight            ; printed
	dbra	d1,draw_registers_data
	moveq	#8,d1                           ; A0-A6, USP, SSP
draw_registers_address:
	move.w	(a3)+,ws_column(a5)
	move.w	(a3)+,ws_row(a5)
	movea.l	(a0)+,a1                        ; the value
	move.l	a1,d0
	bsr.w	print_hex_long                  ; printed
	move.b	(a1)+,d0                        ; 5 words at it
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word
	addq.w	#1,d2
	dbra	d1,draw_registers_address
	movea.l	(a0)+,a1                        ; pc
	move.l	a0,-(sp)
	moveq	#10,d7                          ; 10 columns for the address
	bsr.w	disassemble                     ; disassembled
	move.w	#$5,ws_column(a5)               ; column 5
	move.w	#$9,ws_row(a5)                  ; row 9
	lea	ws_line(a5),a0                  ; the line
	cmpi.b	#$20,$23(a0)
	bne.s	draw_registers_pc
	move.b	#$c1,$23(a0)
draw_registers_pc:
	clr.b	$35(a0)                         ; ended
	bsr.w	print_text                      ; printed
	movea.l	(sp)+,a0
	move.w	#$2d,ws_column(a5)              ; column 45
	move.w	#$8,ws_row(a5)                  ; row 8
	move.w	(a0)+,d1                        ; SR
	move.w	d1,d0
	bsr.w	print_hex_word                  ; printed
	lea	sr_flags(pc),a2                 ; the flags
	moveq	#6,d3                           ; 7
draw_registers_flag:
	moveq	#0,d0
	move.b	(a2)+,d2                        ; its bit
	move.b	(a2)+,d0                        ; its letter
	btst	d2,d1                           ; set?
	bne.s	draw_registers_flag_print       ; yes
	moveq	#45,d0                          ; '-'
draw_registers_flag_print:
	bsr.w	print_char
	dbra	d3,draw_registers_flag
	move.w	#$40,ws_column(a5)              ; column 64
	lsr.w	#8,d1
	andi.w	#$7,d1                          ; the IPL
	moveq	#48,d0
	add.w	d1,d0
	bsr.w	print_char
	rts

;------------------------------------------------------------------------------
; sr_flags: each flag's bit and letter: T S X N Z V C.
;------------------------------------------------------------------------------
sr_flags:	; from: draw_registers
	dc.w	$0f54,$0d53,$0458,$034e,$025a,$0156,$0043

;------------------------------------------------------------------------------
; register_places: each register's column and row on the screen.
;------------------------------------------------------------------------------
register_places:	; from: draw_registers
	dc.w	$0005,$0001,$0019,$0001,$002d,$0001,$0040,$0001
	dc.w	$0005,$0002,$0019,$0002,$002d,$0002,$0040,$0002
	dc.w	$0005,$0004,$002d,$0004,$0005,$0005,$002d,$0005
	dc.w	$0005,$0006,$002d,$0006,$0005,$0007,$002d,$0007
	dc.w	$0005,$0008

;------------------------------------------------------------------------------
; draw_memory: W2 (12 or 6 lines from row 11) and W4 (5 from row 18): each line an address, a long and its
; four characters.
;------------------------------------------------------------------------------
draw_memory:	; from: cursor_right, cursor_left, cursor_down, cursor_up, page_down, page_up, 3 more
	movea.l	ws_w2(a5),a1                    ; W2's base
	moveq	#5,d1                           ; 6 lines
	moveq	#11,d2                          ; row 11
	tst.b	ws_w4_open(a5)                  ; split?
	bne.s	draw_memory_split               ; yes
	addq.w	#6,d1                           ; 12 lines
	bsr.s	draw_memory_line
	move.l	a1,ws_w2_end(a5)                ; its end
	rts
draw_memory_split:
	bsr.s	draw_memory_line
	move.l	a1,ws_w2_end(a5)                ; its end
	movea.l	ws_w4(a5),a1                    ; W4's base
	moveq	#18,d2                          ; row 18
	moveq	#4,d1                           ; 5 lines
	bsr.w	draw_memory_line
	move.l	a1,ws_w4_end(a5)                ; its end
	rts

draw_memory_line:	; from: draw_memory
	move.w	#$38,ws_column(a5)              ; column 56
	move.w	d2,ws_row(a5)                   ; the row
	move.l	a1,d0
	bsr.w	print_hex_long                  ; the address
	move.l	a1,-(sp)
	move.b	(a1)+,d0                        ; the long, by words
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word
	movea.l	(sp)+,a1
	move.b	(a1)+,d0                        ; its four characters
	bsr.w	print_char_dot
	move.b	(a1)+,d0
	bsr.w	print_char_dot
	move.b	(a1)+,d0
	bsr.w	print_char_dot
	move.b	(a1)+,d0
	bsr.w	print_char_dot
	addq.w	#1,d2                           ; the next row
	dbra	d1,draw_memory_line
	rts

;------------------------------------------------------------------------------
; draw_watches: four watches from the current one, on rows 24-27.
;------------------------------------------------------------------------------
draw_watches:	; from: cursor_down, cursor_up, edit_watch, delete_watch, draw_windows
	lea	ws_watches(a5),a0               ; the watches
	sf	ws_watch_check_only(a5)         ; shown, not checked
	adda.w	ws_watch(a5),a0                 ; the current one
	moveq	#3,d6                           ; 4
	moveq	#24,d5                          ; row 24
draw_watches_next:
	move.w	d5,ws_row(a5)
	move.w	#$1,ws_column(a5)               ; column 1
	movem.l	d3-d6,-(sp)
	bsr.w	draw_watch                      ; shown
	beq.s	draw_watches_skipped
draw_watches_skip:
	tst.b	(a0)+                           ; to the next
	bne.s	draw_watches_skip
draw_watches_skipped:
	movem.l	(sp)+,d3-d6
	addq.w	#1,d5                           ; the next row
	dbra	d6,draw_watches_next
	rts

;------------------------------------------------------------------------------
; draw_watch: the watch at a0, "address[,count][.B/.W/.L/.A/.S]": its text, '=', the address, ':' and the
; values (A: characters, S: a string in quotes), to the end of the row.  Only checked if ws_watch_check is set.
; ws_value_error is set (and Z clear) for a bad watch.
;------------------------------------------------------------------------------
draw_watch:	; from: edit_watch, draw_watches
	moveq	#0,d1
	tst.b	(a0)                            ; none?
	beq.w	draw_watch_clear                ; yes
	movea.l	a0,a3                           ; its text
	bsr.w	evaluate_next                   ; the address
	tst.b	ws_value_error(a5)              ; bad?
	bne.w	draw_watch_clear                ; yes
	move.l	d0,d3
	moveq	#1,d4                           ; 1
	moveq	#87,d5                          ; words if not given
	cmpi.w	#$2c,ws_token(a5)               ; ','?
	bne.s	draw_watch_size                 ; no
	bsr.w	evaluate_next                   ; the count
	tst.b	ws_value_error(a5)              ; bad?
	bne.w	draw_watch_clear                ; yes
	move.l	d0,d4
draw_watch_size:
	cmpi.w	#$2e,ws_token(a5)               ; '.'?
	bne.s	draw_watch_check                ; no
	bsr.w	next_token
	move.w	ws_token(a5),d0                 ; the size
	bsr.w	to_capitals                     ; in capitals
	move.w	d0,d5
	bsr.w	next_token
draw_watch_check:
	tst.w	ws_token(a5)                    ; the end of the line?
	sne	ws_value_error(a5)              ; no: bad
	bne.w	draw_watch_clear
	cmp.w	#$42,d5                         ; 'B'?
	beq.s	draw_watch_show
	cmp.w	#$57,d5                         ; 'W'?
	beq.s	draw_watch_show
	cmp.w	#$4c,d5                         ; 'L'?
	beq.s	draw_watch_show
	cmp.w	#$41,d5                         ; 'A'?
	beq.s	draw_watch_show
	cmp.w	#$53,d5                         ; 'S'?
	beq.s	draw_watch_show
	st	ws_value_error(a5)              ; none: bad
	bra.s	draw_watch_clear
draw_watch_show:
	tst.b	ws_watch_check_only(a5)         ; checking only?
	bne.s	draw_watch_done                 ; yes
	moveq	#14,d1                          ; 15 characters
draw_watch_text:
	tst.b	(a3)                            ; its end?
	beq.s	draw_watch_text_end             ; yes
	moveq	#0,d0
	move.b	(a3)+,d0                        ; printed
	bsr.w	print_char
	dbra	d1,draw_watch_text
draw_watch_text_end:
	tst.b	(a3)                            ; longer?
	beq.s	draw_watch_equals               ; no
	moveq	#62,d0                          ; '>' in inverse
	bset	#$0,ws_inverse(a5)
	bsr.w	print_char
	bclr	#$0,ws_inverse(a5)
draw_watch_equals:
	bsr.w	print_space                     ; a space
	moveq	#61,d0                          ; '='
	bsr.w	print_char
	bsr.w	print_space                     ; a space
	move.l	d3,d0                           ; the address
	bsr.w	print_hex_long                  ; printed
	movea.l	d3,a1
	subi.w	#$1,ws_column(a5)               ; back over its space
	moveq	#58,d0                          ; ':'
	bsr.w	print_char
	bsr.w	print_space                     ; a space
	cmp.b	#$42,d5                         ; bytes?
	beq.s	draw_watch_bytes
	cmp.b	#$57,d5                         ; words?
	beq.s	draw_watch_words
	cmp.b	#$4c,d5                         ; longs?
	beq.s	draw_watch_longs
	cmp.b	#$41,d5                         ; characters?
	beq.s	draw_watch_chars
	cmp.b	#$53,d5                         ; a string?
	beq.s	draw_watch_string
draw_watch_clear:
	cmpi.w	#$4f,ws_column(a5)              ; the end of the row?
	beq.s	draw_watch_done                 ; yes
	moveq	#32,d0                          ; spaces
	bsr.w	print_char
	bra.s	draw_watch_clear
draw_watch_done:
	tst.b	ws_value_error(a5)              ; Z: a good watch
	rts
draw_watch_bytes:
	bra.s	draw_watch_byte_next
draw_watch_byte:
	cmpi.w	#$4d,ws_column(a5)              ; room?
	bcc.s	draw_watch_clear                ; no
	move.b	(a1)+,d0
	bsr.w	print_hex_byte                  ; printed
draw_watch_byte_next:
	dbra	d4,draw_watch_byte
	bra.s	draw_watch_clear
draw_watch_words:
	bra.s	draw_watch_word_next
draw_watch_word:
	cmpi.w	#$4b,ws_column(a5)              ; room?
	bcc.s	draw_watch_clear                ; no
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_word                  ; printed
draw_watch_word_next:
	dbra	d4,draw_watch_word
	bra.s	draw_watch_clear
draw_watch_longs:
	bra.s	draw_watch_long_next
draw_watch_long:
	cmpi.w	#$47,ws_column(a5)              ; room?
	bcc.s	draw_watch_clear                ; no
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	swap	d0
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bsr.w	print_hex_long                  ; printed
draw_watch_long_next:
	dbra	d4,draw_watch_long
	bra.s	draw_watch_clear
draw_watch_chars:
	bra.s	draw_watch_char_next
draw_watch_char:
	cmpi.w	#$4f,ws_column(a5)              ; room?
	bcc.s	draw_watch_clear                ; no
	move.b	(a1)+,d0
	bsr.w	print_char_dot                  ; printed ('.' if not)
draw_watch_char_next:
	dbra	d4,draw_watch_char
	bra.s	draw_watch_clear
draw_watch_string:
	move.b	#$22,d0                         ; '"'
	bsr.w	print_char
	bra.s	draw_watch_string_next
draw_watch_string_char:
	cmpi.w	#$4e,ws_column(a5)              ; room?
	bcc.s	draw_watch_string_end           ; no
	move.b	(a1)+,d0
	cmp.w	#$20,d0                         ; a control character?
	bcs.s	draw_watch_string_end           ; yes: the end
	cmp.w	#$80,d0                         ; above $7F?
	bcc.s	draw_watch_string_end           ; yes: the end
	bsr.w	print_char                      ; printed
draw_watch_string_next:
	dbra	d4,draw_watch_string_char
draw_watch_string_end:
	move.b	#$22,d0                         ; '"'
	bsr.w	print_char
	bra.w	draw_watch_clear

;------------------------------------------------------------------------------
; disassemble: the instruction at a1 (made even) into ws_line: d7 columns of address (the line's start),
; then its mnemonic and operands; a1 = the next instruction.  ws_bad_instruction is set for one that cannot
; be; memory that cannot be read gives "MEMORY UNREADABLE!".  In here a5 is the operands' column.
;------------------------------------------------------------------------------
disassemble:                                    ; from: step_over, skip_instruction, cursor_down, zoom_window,
                                                ;   instruction_back, draw_disassembly_line, 1 more
	movem.l	d0-d7/a0/a2-a6,-(sp)            ; saved
	move.l	a1,d0
	andi.l	#$fffffe,d0                     ; even
	movea.l	d0,a1
	moveq	#53,d0                          ; 54
	lea	disassemble_unreadable(pc),a6   ; a fault: unreadable
	move.l	a6,ws_fault(a5)
	move.l	sp,ws_error_stack(a5)           ; the stack for it
	lea	ws_line(a5),a6                  ; the line
disassemble_clear:
	move.b	#$20,0(a6,d0.w)                 ; spaces
	dbra	d0,disassemble_clear
	moveq	#46,d5                          ; '.'
	moveq	#15,d4                          ; the A/D bit in an index word
	sf	ws_bad_instruction(a5)          ; not bad
	lea	ws_line(a5),a6
	move.l	a1,d0
	bclr	#$0,d0                          ; even
	movea.l	d0,a1
	bsr.w	put_line_address                ; the address
	lea	ws_line(a5),a6
	adda.w	d7,a6                           ; + its columns
	move.l	a6,ws_mnemonic(a5)              ; the mnemonic's place
	lea	8(a6),a5                        ; the operands' column
	move.b	(a1)+,d6                        ; the opcode
	lsl.w	#8,d6
	move.b	(a1)+,d6
	pea	disassemble_done(pc)            ; where the routines return
	lea	opcode_table(pc),a0             ; the opcodes
disassemble_find:
	movem.w	(a0)+,d0-d2                     ; mask, value, offset
	move.l	(a0)+,d3                        ; name
	tst.w	d0                              ; the end?
	beq.s	disassemble_unknown             ; yes: not known
	move.w	d6,d7
	and.w	d0,d7                           ; masked
	cmp.w	d1,d7                           ; this one?
	bne.s	disassemble_find                ; no
	lea	opcode_table(pc),a0
	adda.w	d2,a0                           ; its routine
	move.l	d3,(a6)+                        ; the name
	jmp	(a0)                            ; the operands
disassemble_done:
	movea.l	$38.w,a5                        ; the workspace
	lea	exception_ignore(pc),a0         ; faults: rte
	move.l	a0,ws_fault(a5)
	movea.l	ws_error_stack(a5),sp
	movem.l	(sp)+,d0-d7/a0/a2-a6
	rts
disassemble_unreadable:
	movea.l	$38.w,a5                        ; the workspace
	movea.l	ws_mnemonic(a5),a6              ; the mnemonic's place
	move.l	#$4d454d4f,(a6)+                ; "MEMORY UNREADABLE!"
	move.l	#$52592055,(a6)+
	move.l	#$4e524541,(a6)+
	move.l	#$4441424c,(a6)+
	move.l	#$45212020,(a6)+
	move.l	#$20202020,(a6)+
	move.l	#$20202020,(a6)+
	addq.w	#2,a1                           ; over the word
	bra.s	disassemble_done
disassemble_unknown:
	bsr.s	dis_bad                         ; "???"
	subq.w	#2,a1
	bra.w	dis_word_operand                ; the word as an operand

;------------------------------------------------------------------------------
; dis_bad: "???" and ws_bad_instruction set.
;------------------------------------------------------------------------------
dis_bad:	; from: disassemble, mode_seven_routines
	moveq	#63,d0                          ; '?'
	move.b	d0,(a6)+
	move.b	d0,(a6)+
	move.b	d0,(a6)+
	movea.l	$38.w,a0                        ; the workspace
	st	$68(a0)                         ; bad
	rts

;------------------------------------------------------------------------------
; dis_size: the size from bits 6-7 (.B, .W, .L) after the mnemonic, a6 to the operands.
;------------------------------------------------------------------------------
dis_size:	; from: dis_negx, dis_addx, dis_eor, dis_add, dis_addi, dis_addq
	bsr.s	dis_size_char
	move.b	d5,(a6)+                        ; '.'
	move.b	d7,(a6)+                        ; the size
	movea.l	a5,a6                           ; to the operands
	rts

;------------------------------------------------------------------------------
; dis_size_char: d7 = the size letter from bits 6-7 ('?' for 3, bad).
;------------------------------------------------------------------------------
dis_size_char:	; from: dis_size, dis_shift
	move.w	d6,d0
	lsr.w	#6,d0
	andi.w	#$3,d0
	move.b	size_letters(pc,d0.w),d7
	cmp.b	#$3f,d7                         ; '?'?
	bne.s	dis_size_char_done              ; no
	movea.l	$38.w,a0
	st	$68(a0)                         ; bad
dis_size_char_done:
	rts
size_letters:
	dc.w	$4257,$4c3f

;------------------------------------------------------------------------------
; dis_moveq: "MOVEQ.L #n,Dn".
;------------------------------------------------------------------------------
dis_moveq:	; from: opcode_table
	move.l	#$512e4c20,(a6)+                ; "Q.L "
	move.b	#$23,(a6)+                      ; '#'
	move.b	d6,d0                           ; the data
	ext.w	d0
	ext.l	d0
	bsr.w	put_hex
	move.b	#$2c,(a6)+                      ; ','
	bra.w	dis_dn_high                     ; Dn

;------------------------------------------------------------------------------
; dis_unlk: "UNLK An".
;------------------------------------------------------------------------------
dis_unlk:	; from: dis_link, opcode_table
	movea.l	a5,a6
dis_an_low:	; from: dis_move_usp, dis_exg_data
	bsr.s	ea_fields                       ; the register
	bra.s	dis_an                          ; An

;------------------------------------------------------------------------------
; ea_fields: d0 the mode (bits 3-5), d1 the register (bits 0-2).
;------------------------------------------------------------------------------
ea_fields:	; from: dis_unlk, dis_ea, dis_move_source, dis_dn_low
	move.w	d6,d0
	move.w	d6,d1
	lsr.w	#3,d0
	rts
move_size_letters:	; from: dis_move
	dc.w	$3f42,$4c57

;------------------------------------------------------------------------------
; dis_neg: NEG, NOT, CLR, TST: back over the name's space, then dis_negx.
;------------------------------------------------------------------------------
dis_neg:	; from: opcode_table
	subq.w	#1,a6

;------------------------------------------------------------------------------
; dis_negx: the size, then the effective address.
;------------------------------------------------------------------------------
dis_negx:	; from: dis_cmp, opcode_table
	bsr.s	dis_size

;------------------------------------------------------------------------------
; dis_ea_only: the effective address only (NBCD, SWAP, PEA, TAS, JSR, JMP).
;------------------------------------------------------------------------------
dis_ea_only:	; from: dis_shift, opcode_table
	movea.l	a5,a6

;------------------------------------------------------------------------------
; dis_ea: the effective address from bits 0-5.
;------------------------------------------------------------------------------
dis_ea:	; from: dis_eor, dis_adda, dis_add, dis_move_sr, dis_addi, dis_scc, 5 more
	bsr.s	ea_fields
	bra.s	dis_mode

;------------------------------------------------------------------------------
; dis_move: "MOVE.s ea,ea" (the size from bits 12-13).
;------------------------------------------------------------------------------
dis_move:	; from: opcode_table
	move.w	d6,d0
	rol.w	#4,d0
	andi.w	#$3,d0
	move.b	move_size_letters(pc,d0.w),d7   ; the size
	cmp.b	#$3f,d7                         ; '?'?
	bne.s	dis_move_size                   ; no
	movea.l	$38.w,a0
	st	$68(a0)                         ; bad
dis_move_size:
	move.b	d5,(a6)+                        ; '.'
	move.b	d7,(a6)+                        ; the size
	bsr.s	dis_move_source                 ; the source
	move.b	#$2c,(a6)+                      ; ','
	move.w	d6,d0                           ; the destination: mode bits 6-8, register 9-11
	lsr.w	#6,d0
	move.w	d0,d1
	lsr.w	#3,d1
	bra.s	dis_mode

dis_move_source:	; from: dis_move
	movea.l	a5,a6                           ; the operands
	bsr.w	ea_fields
dis_mode:	; from: dis_ea, dis_move
	andi.w	#$7,d0                          ; the mode
	andi.w	#$7,d1                          ; the register
	lea	ea_modes(pc),a0
dis_jump:	; from: dis_indirect
	add.w	d0,d0
	adda.w	0(a0,d0.w),a0                   ; its routine
	jmp	(a0)
ea_modes:
	dc.w	dis_dn-ea_modes
	dc.w	dis_an-ea_modes
	dc.w	dis_indirect-ea_modes
	dc.w	dis_postincrement-ea_modes
	dc.w	dis_predecrement-ea_modes
	dc.w	dis_displacement-ea_modes
	dc.w	dis_index-ea_modes
	dc.w	dis_mode_seven-ea_modes
dis_dn:	; from: dis_dn_high, dis_dn_low, dis_abcd, dis_movep
	move.b	#$44,(a6)+                      ; 'D'
dis_register:	; from: dis_an
	move.w	d1,d0
	andi.w	#$7,d0                          ; the number
	bra.w	put_digit

dis_an:	; from: dis_unlk, ea_modes, dis_indirect, dis_adda
	move.b	#$41,(a6)+                      ; 'A'
	bra.s	dis_register
dis_predecrement:	; from: ea_modes, dis_addx, dis_abcd
	move.b	#$2d,(a6)+                      ; '-'

dis_indirect:	; from: ea_modes
	move.b	#$28,(a6)+                      ; '('
	bsr.s	dis_an                          ; An
	move.b	#$29,(a6)+                      ; ')'
	rts
dis_postincrement:	; from: ea_modes, dis_cmpm
	bsr.s	dis_indirect                    ; (An)
	move.b	#$2b,(a6)+                      ; '+'
	rts
dis_displacement:	; from: ea_modes, dis_movep
	move.b	(a1)+,d0                        ; the displacement
	lsl.w	#8,d0
	move.b	(a1)+,d0
	ext.l	d0
	bsr.w	put_signed                      ; signed
	bra.s	dis_indirect                    ; (An)
dis_index:	; from: ea_modes
	move.b	(a1)+,d3                        ; the extension word
	lsl.w	#8,d3
	move.b	(a1)+,d3
	move.w	d3,d0
	cmp.w	#$ff,d0                         ; a displacement past a byte?
	bls.s	dis_index_displacement          ; no
	movea.l	$38.w,a0
	st	$68(a0)                         ; bad
dis_index_displacement:
	ext.w	d0
	ext.l	d0
	bsr.w	put_signed                      ; signed
	move.b	#$28,(a6)+                      ; '('
	bsr.w	dis_an                          ; An
	bra.w	dis_index_register              ; the index
dis_mode_seven:	; from: ea_modes
	lea	mode_seven_routines(pc),a0
	move.l	d1,d0                           ; by the register field
	bra.w	dis_jump
mode_seven_routines:
	dc.w	dis_absolute_word-mode_seven_routines
	dc.w	dis_absolute_long-mode_seven_routines
	dc.w	dis_pc_displacement-mode_seven_routines
	dc.w	dis_pc_index-mode_seven_routines
	dc.w	dis_immediate-mode_seven_routines
	dc.w	dis_bad-mode_seven_routines
	dc.w	dis_bad-mode_seven_routines
	dc.w	dis_bad-mode_seven_routines
dis_absolute_word:
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	ext.l	d0                              ; signed
	bsr.w	put_address                     ; its label or value
	move.b	d5,(a6)+                        ; '.'
	move.b	#$57,(a6)+                      ; 'W'
	rts
dis_absolute_long:
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	swap	d0
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	bra.w	put_address                     ; its label or value
dis_pc_displacement:
	movea.l	a1,a0                           ; the extension's address
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	adda.w	d0,a0                           ; the address
	move.l	a0,d0
	bsr.w	put_address                     ; its label or value
	bsr.s	dis_pc_text                     ; "(PC"
	move.b	#$29,(a6)+                      ; ')'
	rts

dis_pc_text:	; from: mode_seven_routines
	move.b	#$28,(a6)+                      ; '('
	move.b	#$50,(a6)+                      ; 'P'
	move.b	#$43,(a6)+                      ; 'C'
	rts
dis_pc_index:	; from: mode_seven_routines
	movea.l	a1,a0                           ; the extension's address
	move.b	(a1)+,d3                        ; the extension word
	lsl.w	#8,d3
	move.b	(a1)+,d3
	move.w	d3,d0
	cmp.w	#$ff,d0                         ; a displacement past a byte?
	bls.s	dis_pc_index_address            ; no
	movea.l	$38.w,a0
	st	$68(a0)                         ; bad
dis_pc_index_address:
	ext.w	d0
	ext.l	d0
	add.l	a0,d0                           ; the address
	bsr.w	put_address                     ; its label or value
	bsr.s	dis_pc_text                     ; "(PC"
dis_index_register:	; from: dis_indirect
	move.b	#$2c,(a6)+                      ; ','
	moveq	#68,d0                          ; 'D'
	btst	d4,d3                           ; an address register?
	beq.s	dis_index_register_letter       ; no
	moveq	#65,d0                          ; 'A'
dis_index_register_letter:
	move.b	d0,(a6)+
	move.w	d3,d0
	rol.w	#4,d0                           ; its number
	andi.w	#$7,d0
	bsr.w	put_digit
	move.b	d5,(a6)+                        ; '.'
	moveq	#87,d0                          ; 'W'
	btst	#$b,d3                          ; long?
	beq.s	dis_index_register_size         ; no
	moveq	#76,d0                          ; 'L'
dis_index_register_size:
	move.b	d0,(a6)+
	move.b	#$29,(a6)+                      ; ')'
	rts

;------------------------------------------------------------------------------
; dis_word_operand: a word immediate "#$n" (STOP, a word not known).
;------------------------------------------------------------------------------
dis_word_operand:	; from: disassemble, dis_andi, dis_bit, opcode_table
	moveq	#87,d7

;------------------------------------------------------------------------------
; dis_immediate: "#$n" of the size d7 (a byte's word must be under $100).
;------------------------------------------------------------------------------
dis_immediate:	; from: mode_seven_routines, dis_addi
	movea.l	a5,a6                           ; to the operands
	move.b	#$23,(a6)+                      ; '#'
	clr.l	d0
	move.b	(a1)+,d0                        ; a word
	lsl.w	#8,d0
	move.b	(a1)+,d0
	cmp.b	#$4c,d7                         ; long?
	bne.s	dis_immediate_byte              ; no
	swap	d0
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
dis_immediate_byte:
	cmp.b	#$42,d7                         ; byte?
	bne.s	dis_immediate_value             ; no
	cmp.w	#$ff,d0                         ; under $100?
	bls.s	dis_immediate_value             ; yes
	movea.l	$38.w,a0
	st	$68(a0)                         ; bad
dis_immediate_value:
	bra.w	put_hex                         ; in hex

;------------------------------------------------------------------------------
; dis_addx: ADDX, SUBX: "Dy,Dx" or "-(Ay),-(Ax)".
;------------------------------------------------------------------------------
dis_addx:	; from: opcode_table
	lea	dis_dn_high(pc),a4              ; data registers
	btst	#$3,d6                          ; -(An)?
	beq.s	dis_two_registers               ; no
	lea	dis_predecrement(pc),a4
dis_two_registers:	; from: dis_cmpm
	bsr.w	dis_size                        ; the size
	move.w	d6,d1                           ; the source register
	jsr	(a4)
	move.b	#$2c,(a6)+                      ; ','
	move.w	d6,d1                           ; the destination register
	rol.w	#7,d1
	jmp	(a4)

;------------------------------------------------------------------------------
; dis_cmpm: "CMPM (Ay)+,(Ax)+".
;------------------------------------------------------------------------------
dis_cmpm:	; from: opcode_table
	lea	dis_postincrement(pc),a4
	bra.s	dis_two_registers

;------------------------------------------------------------------------------
; dis_cmp: "CMP.s ea,Dn".
;------------------------------------------------------------------------------
dis_cmp:	; from: opcode_table
	subq.w	#1,a6                           ; back over the name's space
	bsr.w	dis_negx                        ; the size and ea
	move.b	#$2c,(a6)+                      ; ','

;------------------------------------------------------------------------------
; dis_dn_high: Dn from bits 9-11.
;------------------------------------------------------------------------------
dis_dn_high:	; from: dis_moveq, dis_addx, dis_eor, dis_add, dis_shift, dis_bit, 3 more
	move.w	d6,d1
	rol.w	#7,d1
	bra.w	dis_dn

;------------------------------------------------------------------------------
; dis_eor: "EOR.s Dn,ea".
;------------------------------------------------------------------------------
dis_eor:	; from: opcode_table
	subq.w	#1,a6
	bsr.w	dis_size                        ; the size
	bsr.s	dis_dn_high                     ; Dn
	move.b	#$2c,(a6)+                      ; ','
	bra.w	dis_ea                          ; ea

;------------------------------------------------------------------------------
; dis_adda: ADDA, SUBA, CMPA: "ea,An" (.W or .L from bit 8).
;------------------------------------------------------------------------------
dis_adda:	; from: opcode_table
	moveq	#87,d7                          ; 'W'
	btst	#$8,d6
	beq.s	dis_adda_size
	moveq	#76,d7                          ; 'L'
dis_adda_size:
	move.b	d5,(a6)+                        ; '.'
	move.b	d7,(a6)+
	movea.l	a5,a6
	bsr.w	dis_ea                          ; ea
	move.b	#$2c,(a6)+                      ; ','
dis_an_high:	; from: dis_lea, dis_exg_data
	move.w	d6,d1                           ; An from bits 9-11
	rol.w	#7,d1
	bra.w	dis_an

;------------------------------------------------------------------------------
; dis_or: OR (its name 2 letters): back over two spaces, then dis_add.
;------------------------------------------------------------------------------
dis_or:	; from: opcode_table
	subq.w	#1,a6

;------------------------------------------------------------------------------
; dis_add: ADD, SUB, AND (the name 3 letters, with a '.'): "ea,Dn" or "Dn,ea" (bit 8).
;------------------------------------------------------------------------------
dis_add:	; from: opcode_table
	subq.w	#1,a6
	bsr.w	dis_size                        ; the size
	lea	dis_dn_high(pc),a2              ; Dn
	lea	dis_ea(pc),a3                   ; ea
	btst	#$8,d6                          ; the direction
	bra.w	dis_operands_swap

;------------------------------------------------------------------------------
; dis_ori: ORI (3 letters), then dis_andi.
;------------------------------------------------------------------------------
dis_ori:	; from: opcode_table
	subq.w	#1,a6

;------------------------------------------------------------------------------
; dis_andi: ANDI, ORI, EORI: "#$n,ea", or "#$n,CCR" / "#$n,SR".
;------------------------------------------------------------------------------
dis_andi:	; from: opcode_table
	move.w	d6,d0
	andi.w	#$bf,d0
	cmp.w	#$3c,d0                         ; to CCR or SR?
	bne.s	dis_addi                        ; no
	bsr.w	dis_word_operand                ; the immediate
	move.l	#$43435220,-(sp)                ; "CCR"
	btst	#$6,d6                          ; to SR?
	beq.s	dis_ccr_sr                      ; no
	move.l	#$53522020,(sp)                 ; "SR"
dis_ccr_sr:	; from: dis_move_sr
	move.b	#$2c,(a6)+                      ; ','
	move.b	(sp),(a6)+                      ; "CCR" or "SR"
	move.b	1(sp),(a6)+
	move.b	2(sp),(a6)+
	addq.w	#4,sp
	rts

;------------------------------------------------------------------------------
; dis_move_sr: MOVE to CCR, to SR, from SR.
;------------------------------------------------------------------------------
dis_move_sr:	; from: opcode_table
	movea.l	a5,a6                           ; to the operands
	btst	#$a,d6                          ; from SR?
	beq.s	dis_move_sr_from                ; yes
	bsr.w	dis_ea                          ; ea
	move.l	#$43435220,-(sp)                ; "CCR"
	btst	#$9,d6                          ; to SR?
	beq.s	dis_move_sr_to                  ; no
	move.l	#$53522020,(sp)                 ; "SR"
dis_move_sr_to:
	bra.s	dis_ccr_sr
dis_move_sr_from:
	move.w	#$5352,(a6)+                    ; "SR"
	move.b	#$2c,(a6)+                      ; ','
	bra.w	dis_ea                          ; ea

;------------------------------------------------------------------------------
; dis_ext: "EXT.W Dn" / "EXT.L Dn".
;------------------------------------------------------------------------------
dis_ext:	; from: opcode_table
	subq.w	#1,a6
	bsr.s	dis_size_wl                     ; the size

dis_dn_low:	; from: dis_shift, dis_dbcc, dis_exg_data
	bsr.w	ea_fields                       ; Dn from bits 0-2
	bra.w	dis_dn

;------------------------------------------------------------------------------
; dis_size_wl: .W or .L from bit 6, a6 to the operands.
;------------------------------------------------------------------------------
dis_size_wl:	; from: dis_ext, dis_movem, dis_movep
	moveq	#87,d7                          ; 'W'
	btst	#$6,d6
	beq.s	dis_size_wl_put
	moveq	#76,d7                          ; 'L'
dis_size_wl_put:
	move.b	d5,(a6)+                        ; '.'
	move.b	d7,(a6)+
	movea.l	a5,a6                           ; to the operands
	rts

;------------------------------------------------------------------------------
; dis_addi: ADDI, SUBI, CMPI: "#$n,ea".
;------------------------------------------------------------------------------
dis_addi:	; from: dis_andi, opcode_table
	bsr.w	dis_size                        ; the size
	bsr.w	dis_immediate                   ; the immediate
dis_comma_ea:	; from: dis_addq
	move.b	#$2c,(a6)+                      ; ','
	bra.w	dis_ea                          ; ea

;------------------------------------------------------------------------------
; dis_addq: ADDQ, SUBQ: "#n,ea" (0 is 8).
;------------------------------------------------------------------------------
dis_addq:	; from: opcode_table
	bsr.w	dis_size                        ; the size
dis_quick:	; from: dis_shift
	movea.l	a5,a6                           ; to the operands
	move.b	#$23,(a6)+                      ; '#'
	move.w	d6,d0
	rol.w	#7,d0
	andi.l	#$7,d0                          ; the data
	bne.s	dis_quick_value                 ; 0?
	moveq	#8,d0                           ; 8
dis_quick_value:
	bsr.w	put_hex
	bra.s	dis_comma_ea

;------------------------------------------------------------------------------
; dis_trap: "TRAP #$n".
;------------------------------------------------------------------------------
dis_trap:	; from: opcode_table
	movea.l	a5,a6                           ; to the operands
	move.b	#$23,(a6)+                      ; '#'
	move.b	#$24,(a6)+                      ; '$'
	move.b	d6,d0                           ; the vector
	bra.w	put_digit

;------------------------------------------------------------------------------
; dis_shift: the shifts and rotates: ASx, LSx, ROXx, ROx, L or R, the size, then "#n,Dy", "Dx,Dy" or a
; memory shift's ea.
;------------------------------------------------------------------------------
dis_shift:	; from: opcode_table
	subq.w	#4,a6                           ; back over the name
	bsr.w	dis_size_char                   ; the size
	moveq	#2,d1                           ; register shift: bits 3-4
	cmp.b	#$3f,d7                         ; memory?
	bne.s	dis_shift_kind                  ; no
	moveq	#8,d1                           ; memory: bits 9-10
dis_shift_kind:
	move.w	d6,d0
	lsr.w	d1,d0
	andi.w	#$6,d0
	move.w	shift_names(pc,d0.w),(a6)+      ; "AS", "LS", "RO", "RO"
	cmp.b	#$4,d0                          ; ROX?
	bne.s	dis_shift_direction             ; no
	move.b	#$58,(a6)+                      ; 'X'
dis_shift_direction:
	moveq	#82,d0                          ; 'R'
	btst	#$8,d6                          ; left?
	beq.s	dis_shift_size                  ; no
	moveq	#76,d0                          ; 'L'
dis_shift_size:
	move.b	d0,(a6)+
	move.b	d5,(a6)+                        ; '.'
	cmp.b	#$3f,d7                         ; memory?
	beq.s	dis_shift_memory                ; yes
	move.b	d7,(a6)+                        ; the size
	btst	#$5,d6                          ; a register count?
	bne.s	dis_shift_register              ; yes
	bne.w	dis_dn_high                     ; (never)
	andi.w	#$e07,d6                        ; the count
	bra.w	dis_quick                       ; "#n,Dy"
dis_shift_memory:
	movea.l	$38.w,a0                        ; the workspace
	sf	$68(a0)                         ; not bad: '?' was the memory size
	move.b	#$57,(a6)+                      ; 'W'
	bra.w	dis_ea_only                     ; ea
dis_shift_register:
	movea.l	a5,a6                           ; to the operands
	bsr.w	dis_dn_high                     ; Dx
	move.b	#$2c,(a6)+                      ; ','
	bra.w	dis_dn_low                      ; Dy
shift_names:
	dc.b	'ASLSRORO'

;------------------------------------------------------------------------------
; dis_bcc: Bcc, BRA, BSR: the condition (T is RA, F is SR), .S for a short branch, and the target or its label.
;------------------------------------------------------------------------------
dis_bcc:	; from: opcode_table
	subq.w	#3,a6                           ; back over the name
	move.w	d6,d0
	lsr.w	#7,d0
	andi.w	#$1e,d0                         ; the condition
	cmp.w	#$4,d0                          ; T or F?
	bcc.s	dis_bcc_name                    ; no
	addi.w	#$20,d0                         ; RA or SR
dis_bcc_name:
	bsr.s	condition_letters
	move.l	a1,d0                           ; the next word's address
	move.b	d6,d1
	ext.w	d1                              ; the displacement
	beq.s	dis_bcc_word                    ; a word?
	move.b	d5,(a6)+                        ; '.'
	move.b	#$53,(a6)+                      ; 'S'
	bra.s	dis_bcc_target
dis_bcc_word:
	move.b	(a1)+,d1                        ; the word
	lsl.w	#8,d1
	move.b	(a1)+,d1
dis_bcc_target:
	movea.l	a5,a6                           ; to the operands
	add.w	d1,d0                           ; the target
	bra.w	put_address                     ; its label or value

;------------------------------------------------------------------------------
; dis_dbcc: "DBcc Dn,target".
;------------------------------------------------------------------------------
dis_dbcc:	; from: opcode_table
	subq.w	#2,a6                           ; back over "cc"
	bsr.s	condition                       ; the condition
	movea.l	a5,a6                           ; to the operands
	bsr.w	dis_dn_low                      ; Dn
	move.b	(a1),d0                         ; the displacement
	lsl.w	#8,d0
	move.b	1(a1),d0
	ext.l	d0
	add.l	a1,d0                           ; the target
	addq.w	#2,a1                           ; over it
	move.b	#$2c,(a6)+                      ; ','
	bra.w	put_address                     ; its label or value

;------------------------------------------------------------------------------
; condition: the condition's two letters from bits 8-11.
;------------------------------------------------------------------------------
condition:	; from: dis_dbcc, dis_scc
	move.w	d6,d0
	lsr.w	#7,d0
	andi.w	#$1e,d0

condition_letters:	; from: dis_bcc
	move.b	conditions(pc,d0.w),(a6)+
	move.b	conditions_second(pc,d0.w),(a6)+
	rts

;------------------------------------------------------------------------------
; conditions: T F HI LS CC CS NE EQ VC VS PL MI GE LT GT LE, then RA and SR for BRA and BSR.
;------------------------------------------------------------------------------
conditions:	; from: condition_letters
	dc.b	$54
conditions_second:	; from: condition_letters
	dc.b	' F HILSCCCSNEEQVCVSPLMIGELTGTLERASR'

;------------------------------------------------------------------------------
; dis_scc: "Scc ea".
;------------------------------------------------------------------------------
dis_scc:	; from: opcode_table
	subq.w	#3,a6                           ; back over "cc"
	bsr.s	condition                       ; the condition
	movea.l	a5,a6                           ; to the operands
	bra.w	dis_ea                          ; ea

;------------------------------------------------------------------------------
; dis_abcd: ABCD, SBCD: "Dy,Dx" or "-(Ay),-(Ax)".
;------------------------------------------------------------------------------
dis_abcd:	; from: opcode_table
	lea	dis_dn(pc),a4                   ; data registers
	btst	#$3,d6                          ; -(An)?
	beq.s	dis_bcd_registers               ; no
	lea	dis_predecrement(pc),a4
dis_bcd_registers:
	movea.l	a5,a6                           ; to the operands
	move.w	d6,d1                           ; the source register
	jsr	(a4)
	move.b	#$2c,(a6)+                      ; ','
	move.w	d6,d1                           ; the destination register
	rol.w	#7,d1
	jmp	(a4)

;------------------------------------------------------------------------------
; dis_movem: "MOVEM.s list,ea" or "MOVEM.s ea,list" (the list reversed for -(An)).
;------------------------------------------------------------------------------
dis_movem:	; from: opcode_table
	move.b	#$4d,(a6)+                      ; 'M'
	bsr.w	dis_size_wl                     ; the size
	move.b	(a1)+,d2                        ; the register mask
	lsl.w	#8,d2
	move.b	(a1)+,d2
	btst	#$a,d6                          ; to memory?
	beq.s	dis_movem_from                  ; no: from it
	bsr.w	dis_ea                          ; ea
	move.b	#$2c,(a6)+                      ; ','

;------------------------------------------------------------------------------
; register_list: the mask d2 as a register list: "D0-D3/A0".
;------------------------------------------------------------------------------
register_list:	; from: register_list_part
	moveq	#68,d0                          ; 'D'
	move.w	d2,-(sp)                        ; kept
	andi.w	#$ff,d2                         ; the low byte
	moveq	#0,d3                           ; none yet
	bsr.s	register_list_part              ; the data registers
	moveq	#65,d0                          ; 'A'
	move.w	(sp)+,d2
	lsr.w	#8,d2                           ; the address registers

;------------------------------------------------------------------------------
; register_list_part: the registers of the low byte of d2, d0 their letter, with '/' between and '-' for runs.
;------------------------------------------------------------------------------
register_list_part:	; from: register_list
	moveq	#47,d1                          ; '0' - 1
register_list_next:
	addq.w	#1,d1
	tst.w	d2                              ; any left?
	beq.s	register_list_done              ; no
	lsr.w	#1,d2                           ; the next
	bcc.s	register_list_next              ; not in it
	tas	d3                              ; the first?
	beq.s	register_list_register          ; yes
	move.b	#$2f,(a6)+                      ; '/'
register_list_register:
	move.b	d0,(a6)+
	move.b	d1,(a6)+
	btst	#$0,d2                          ; a run?
	beq.s	register_list_next              ; no
register_list_run:
	btst	#$0,d2
	beq.s	register_list_run_end
	addq.w	#1,d1
	lsr.w	#1,d2
	bcs.s	register_list_run
register_list_run_end:
	move.b	#$2d,(a6)+                      ; '-'
	move.b	d0,(a6)+
	move.b	d1,(a6)+
	bra.s	register_list_next
register_list_done:
	rts
dis_movem_from:	; from: dis_movem
	moveq	#15,d1                          ; 16 bits
	move.w	d2,d0
dis_movem_reverse:
	lsr.w	#1,d0                           ; reversed
	roxl.w	#1,d2
	dbra	d1,dis_movem_reverse
	bsr.s	register_list                   ; the list
	move.b	#$2c,(a6)+                      ; ','
	bra.w	dis_ea                          ; ea

;------------------------------------------------------------------------------
; dis_bit: BTST, BCHG, BCLR, BSET: "Dn,ea" or "#$n,ea".
;------------------------------------------------------------------------------
dis_bit:	; from: opcode_table
	movea.l	a5,a6                           ; to the operands
	move.w	d6,d0
	andi.w	#$f00,d0
	cmp.w	#$800,d0                        ; static?
	beq.s	dis_bit_static                  ; yes
	bsr.w	dis_dn_high                     ; Dn
	bra.s	dis_bit_ea
dis_bit_static:
	bsr.w	dis_word_operand                ; #$n
dis_bit_ea:
	move.b	#$2c,(a6)+                      ; ','
	bra.w	dis_ea                          ; ea

;------------------------------------------------------------------------------
; dis_mul: MULU, MULS, DIVU, DIVS: "ea,Dn".
;------------------------------------------------------------------------------
dis_mul:	; from: opcode_table
	movea.l	a5,a6                           ; to the operands
	bsr.w	dis_ea                          ; ea
	move.b	#$2c,(a6)+                      ; ','
	bra.w	dis_dn_high                     ; Dn

;------------------------------------------------------------------------------
; dis_reset: "RESET".
;------------------------------------------------------------------------------
dis_reset:	; from: opcode_table
	move.w	#$5420,(a6)+                    ; "T "
	bra.w	return

;------------------------------------------------------------------------------
; dis_trapv: "TRAPV".
;------------------------------------------------------------------------------
dis_trapv:	; from: opcode_table
	move.w	#$5620,(a6)+                    ; "V "
	bra.w	return

;------------------------------------------------------------------------------
; dis_illegal: "ILLEGAL".
;------------------------------------------------------------------------------
dis_illegal:	; from: opcode_table
	move.l	#$47414c20,(a6)+                ; "GAL "
	bra.w	return

;------------------------------------------------------------------------------
; dis_lea: "LEA ea,An".
;------------------------------------------------------------------------------
dis_lea:	; from: opcode_table
	lea	dis_an_high(pc),a2              ; An
	bra.s	dis_ea_register

;------------------------------------------------------------------------------
; dis_chk: "CHK ea,Dn".
;------------------------------------------------------------------------------
dis_chk:	; from: opcode_table
	lea	dis_dn_high(pc),a2              ; Dn
dis_ea_register:	; from: dis_lea
	movea.l	a5,a6                           ; to the operands
	bsr.w	dis_ea                          ; ea
	move.b	#$2c,(a6)+                      ; ','
	jmp	(a2)                            ; the register

;------------------------------------------------------------------------------
; dis_link: "LINK An,#n".
;------------------------------------------------------------------------------
dis_link:	; from: opcode_table
	bsr.w	dis_unlk                        ; An
	move.b	(a1)+,d0                        ; the displacement
	lsl.w	#8,d0
	move.b	(a1)+,d0
	ext.l	d0
	move.b	#$2c,(a6)+                      ; ','
	move.b	#$23,(a6)+                      ; '#'
	bra.w	put_hex

;------------------------------------------------------------------------------
; dis_movep: "MOVEP.s Dn,d(An)" or "MOVEP.s d(An),Dn".
;------------------------------------------------------------------------------
dis_movep:	; from: opcode_table
	move.b	#$50,(a6)+                      ; 'P'
	lea	dis_dn(pc),a2                   ; Dn
	lea	dis_displacement(pc),a3         ; d(An)
	bsr.w	dis_size_wl                     ; the size
	btst	#$7,d6                          ; to memory?
dis_operands_swap:	; from: dis_add, dis_move_usp
	bne.s	dis_operands_two                ; yes
	exg	a3,a2                           ; no: the other way
dis_operands_two:	; from: dis_exg_data
	jsr	(a2)                            ; the first
	move.b	#$2c,(a6)+                      ; ','
	jmp	(a3)                            ; the second

;------------------------------------------------------------------------------
; dis_move_usp: "MOVE An,USP" or "MOVE USP,An".
;------------------------------------------------------------------------------
dis_move_usp:	; from: opcode_table
	movea.l	a5,a6                           ; to the operands
	lea	dis_usp(pc),a2                  ; "USP"
	lea	dis_an_low(pc),a3               ; An
	btst	#$3,d6                          ; the direction
	bra.s	dis_operands_swap
dis_usp:
	move.b	#$55,(a6)+                      ; 'U'
	move.b	#$53,(a6)+                      ; 'S'
	move.b	#$50,(a6)+                      ; 'P'
	rts

;------------------------------------------------------------------------------
; dis_exg_data, dis_exg_address, dis_exg_mixed: "EXG Rx,Ry".
;------------------------------------------------------------------------------
dis_exg_data:	; from: opcode_table
	lea	dis_dn_high(pc),a2              ; Dx
	lea	dis_dn_low(pc),a3               ; Dy
	bra.s	dis_exg_go
dis_exg_address:	; from: opcode_table
	lea	dis_an_high(pc),a2              ; Ax
	bra.s	dis_exg_an
dis_exg_mixed:	; from: opcode_table
	lea	dis_dn_high(pc),a2              ; Dx
dis_exg_an:
	lea	dis_an_low(pc),a3               ; Ay
dis_exg_go:
	movea.l	a5,a6                           ; to the operands
	bra.s	dis_operands_two

;------------------------------------------------------------------------------
; put_address: the label with the value d0, or "$hex".
;------------------------------------------------------------------------------
put_address:	; from: mode_seven_routines, dis_pc_text, dis_bcc, dis_dbcc
	bsr.w	find_label_value                ; a label?
	bne.w	put_hex                         ; no: hex
	moveq	#7,d0                           ; 8 characters
put_address_char:
	move.b	(a0)+,d1
	beq.s	put_address_done                ; its end
	move.b	d1,(a6)+
	dbeq	d0,put_address_char
put_address_done:
	rts

;------------------------------------------------------------------------------
; put_digit: the hex digit d0 (and'ed with d4).
;------------------------------------------------------------------------------
put_digit:	; from: ea_modes, dis_pc_text, dis_trap
	move.l	d0,-(sp)
	and.w	d4,d0
	move.b	hex_digits(pc,d0.w),(a6)+
	move.l	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; put_line_address: the address d0 as 7 hex digits.
;------------------------------------------------------------------------------
put_line_address:	; from: disassemble
	movem.l	d0-d3,-(sp)
	moveq	#1,d2                           ; leading zeros too
	moveq	#6,d1
	bra.s	put_hex_digit
put_word_hex:
	movem.l	d0-d3,-(sp)                     ; (not called)
	moveq	#1,d2
	moveq	#2,d1
	swap	d0
	bra.s	put_hex_digit

;------------------------------------------------------------------------------
; put_signed: d0 as "$hex", with '-' for a negative.
;------------------------------------------------------------------------------
put_signed:	; from: dis_indirect
	tst.l	d0
	bpl.s	put_hex
	move.b	#$2d,(a6)+                      ; '-'
	neg.l	d0
	bra.s	put_hex
	move.b	#$2c,(a6)+                      ; (not reached: ',')

;------------------------------------------------------------------------------
; put_hex: "$" and d0 in hex without leading zeros (d4 the digit mask).
;------------------------------------------------------------------------------
put_hex:	; from: dis_moveq, dis_immediate, dis_addq, dis_link, put_address, put_signed
	movem.l	d0-d3,-(sp)
	move.b	#$24,(a6)+                      ; '$'
	moveq	#6,d1                           ; 8 digits
	moveq	#0,d2                           ; not yet
put_hex_digit:	; from: put_line_address
	rol.l	#4,d0                           ; the next
	move.l	d0,d3
	and.w	d4,d3
	bne.s	put_hex_put                     ; not 0
	tst.b	d2                              ; a digit already?
	beq.s	put_hex_next                    ; no: skipped
put_hex_put:
	move.b	hex_digits(pc,d3.w),(a6)+
	st	d2
put_hex_next:
	dbra	d1,put_hex_digit
	rol.l	#4,d0                           ; the last always
	and.w	d4,d0
	move.b	hex_digits(pc,d0.w),(a6)+
	movem.l	(sp)+,d0-d3
return:	; from: dis_reset, dis_trapv, dis_illegal, clear_message, opcode_table
	rts
hex_digits:	; from: put_digit
	dc.b	'0123456789ABCDEF'

;------------------------------------------------------------------------------
; print_message: the text at a0 on the message row (the bottom row), the old message cleared first.
;------------------------------------------------------------------------------
print_message:	; from: step_over, evaluate, input_three_values, search_next, find, input_search_value, 14 more
	tst.b	ws_message(a5)                  ; a message there?
	beq.s	print_message_text              ; no
	bsr.w	clear_message                   ; cleared
print_message_text:
	st	ws_message(a5)                  ; shown
	move.w	#$1c,ws_row(a5)                 ; the bottom row
	move.w	#$1,ws_column(a5)               ; column 1
	bra.w	print_text                      ; printed

;------------------------------------------------------------------------------
; clear_message: the message row cleared if a message is there.
;------------------------------------------------------------------------------
clear_message:	; from: command_loop, fill_memory, input_search_value, edit_watch, write_sectors, read_sectors, 6 more
	tst.b	ws_message(a5)                  ; a message there?
	beq.s	return                          ; no
	clr.b	ws_message(a5)
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	move.w	#$1c,ws_row(a5)                 ; the bottom row
	clr.w	ws_column(a5)
	lea	clear_row_text(pc),a0           ; spaces
	bsr.w	print_text
	movea.l	(sp)+,a0
	move.l	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; print_char_dot: the character d0, or '.' for a control character.
;------------------------------------------------------------------------------
print_char_dot:	; from: zoom_window, draw_registers, draw_memory_line, draw_watch
	andi.w	#$7f,d0
	cmp.w	#$20,d0                         ; a control character?
	bcc.w	print_char                      ; no
	moveq	#46,d0                          ; '.'
	bra.w	print_char

;------------------------------------------------------------------------------
; print_hex_byte: d0 as 2 hex digits and a space.
;------------------------------------------------------------------------------
print_hex_byte:	; from: draw_watch
	movem.l	d0-d3,-(sp)
	swap	d0
	lsl.w	#8,d0
	move.l	d0,d1
	moveq	#1,d2                           ; 2
	moveq	#0,d3
	bra.s	print_hex_digits

;------------------------------------------------------------------------------
; print_hex_word: d0 as 4 hex digits and a space.
;------------------------------------------------------------------------------
print_hex_word:	; from: zoom_window, draw_registers, draw_memory_line, draw_watch
	movem.l	d0-d3,-(sp)
	swap	d0
	move.l	d0,d1
	moveq	#3,d2                           ; 4
	moveq	#0,d3
	bra.s	print_hex_digits

;------------------------------------------------------------------------------
; print_hex_word_tight: d0 as 4 hex digits, no space.
;------------------------------------------------------------------------------
print_hex_word_tight:	; from: draw_registers
	movem.l	d0-d3,-(sp)
	swap	d0
	move.l	d0,d1
	moveq	#3,d2                           ; 4
	moveq	#0,d3
print_hex_word_tight_digit:
	rol.l	#4,d1
	move.w	d1,d0
	andi.w	#$f,d0
	move.b	hex_digits_print(pc,d0.w),d0
	bsr.w	print_char                      ; printed
	dbra	d2,print_hex_word_tight_digit
	movem.l	(sp)+,d0-d3
	rts

;------------------------------------------------------------------------------
; print_hex_long: d0 as 8 hex digits and a space (none at the last column).
;------------------------------------------------------------------------------
print_hex_long:	; from: evaluate, zoom_window, draw_registers, draw_memory_line, draw_watch, enter_monitor_saved
	movem.l	d0-d3,-(sp)
	move.l	d0,d1
	moveq	#7,d2                           ; 8
	moveq	#0,d3
print_hex_digits:	; from: print_hex_byte, print_hex_word
	rol.l	#4,d1                           ; the next
	move.w	d1,d0
	andi.w	#$f,d0
	move.b	hex_digits_print(pc,d0.w),d0
	bsr.w	print_char                      ; printed
	dbra	d2,print_hex_digits
	cmpi.w	#$4f,ws_column(a5)              ; the last column?
	bcc.s	print_hex_done                  ; yes
	bsr.w	print_space                     ; a space
print_hex_done:
	movem.l	(sp)+,d0-d3
	rts
hex_digits_print:	; from: print_hex_word_tight
	dc.b	'0123456789ABCDEF'

;------------------------------------------------------------------------------
; print_decimal: d0 in decimal, '-' first for a negative.
;------------------------------------------------------------------------------
print_decimal:	; from: evaluate
	move.l	d0,d3
	tst.l	d3                              ; negative?
	bpl.s	print_decimal_positive          ; no
	neg.l	d3
	moveq	#45,d0                          ; '-'
	bsr.w	print_char
print_decimal_positive:
	lea	powers_of_ten(pc),a2            ; the powers of 10
print_decimal_digit:
	move.l	(a2)+,d1                        ; the next
	beq.s	print_decimal_done              ; the end
	moveq	#47,d0                          ; '0' - 1
print_decimal_count:
	addq.w	#1,d0
	sub.l	d1,d3
	bpl.s	print_decimal_count
	add.l	d1,d3                           ; back
	bsr.w	print_char                      ; the digit
	bra.s	print_decimal_digit
print_decimal_done:
	rts
powers_of_ten:
	dc.w	$3b9a,$ca00,$05f5,$e100,$0098,$9680,$000f,$4240
	dc.w	$0001,$86a0,$0000,$2710,$0000,$03e8,$0000,$0064
	dc.w	$0000,$000a,$0000,$0001,$0000,$0000

;------------------------------------------------------------------------------
; print_text: the text at a0, 0 ending it.
;------------------------------------------------------------------------------
print_text:	; from: help, edit_line, draw_frame, draw_title, draw_lower_frame, draw_disassembly_line, 4 more
	moveq	#0,d0
	move.b	(a0)+,d0
	beq.w	print_text_done                 ; the end?
	bsr.w	print_char                      ; printed
	bra.w	print_text
print_text_done:
	rts

;------------------------------------------------------------------------------
; zoom_rows: each of the 30 zoom rows' offset in the screen (7 lines a row).
;------------------------------------------------------------------------------
zoom_rows:	; from: zoom_window
	dc.w	$0000,$0460,$08c0,$0d20,$1180,$15e0,$1a40,$1ea0
	dc.w	$2300,$2760,$2bc0,$3020,$3480,$38e0,$3d40,$41a0
	dc.w	$4600,$4a60,$4ec0,$5320,$5780,$5be0,$6040,$64a0
	dc.w	$6900,$6d60,$71c0,$7620,$7a80,$7ee0

;------------------------------------------------------------------------------
; column_offsets: each column's byte in a line (medium resolution: plane 0's bytes).
;------------------------------------------------------------------------------
column_offsets:	; from: screen_address
	dc.w	$0000,$0001,$0004,$0005,$0008,$0009,$000c,$000d
	dc.w	$0010,$0011,$0014,$0015,$0018,$0019,$001c,$001d
	dc.w	$0020,$0021,$0024,$0025,$0028,$0029,$002c,$002d
	dc.w	$0030,$0031,$0034,$0035,$0038,$0039,$003c,$003d
	dc.w	$0040,$0041,$0044,$0045,$0048,$0049,$004c,$004d
	dc.w	$0050,$0051,$0054,$0055,$0058,$0059,$005c,$005d
	dc.w	$0060,$0061,$0064,$0065,$0068,$0069,$006c,$006d
	dc.w	$0070,$0071,$0074,$0075,$0078,$0079,$007c,$007d
	dc.w	$0080,$0081,$0084,$0085,$0088,$0089,$008c,$008d
	dc.w	$0090,$0091,$0094,$0095,$0098,$0099,$009c,$009d
	dc.w	$00a0,$00a1,$00a4,$00a5,$00a8,$00a9,$00ac,$00ad
	dc.w	$00b0,$00b1,$00b4,$00b5,$00b8,$00b9,$00bc,$00bd
	dc.w	$00c0,$00c1,$00c4,$00c5,$00c8,$00c9,$00cc,$00cd
	dc.w	$00d0,$00d1,$00d4,$00d5,$00d8,$00d9,$00dc,$00dd
	dc.w	$00e0,$00e1,$00e4,$00e5,$00e8,$00e9,$00ec,$00ed
	dc.w	$00f0,$00f1,$00f4,$00f5,$00f8,$00f9,$00fc,$00fd
	dc.w	$0100,$0101,$0104,$0105,$0108,$0109,$010c,$010d
	dc.w	$0110,$0111,$0114,$0115,$0118,$0119,$011c,$011d
	dc.w	$0120,$0121,$0124,$0125,$0128,$0129,$012c,$012d
	dc.w	$0130,$0131,$0134,$0135,$0138,$0139,$013c,$013d
	dc.w	$0140,$0141,$0144,$0145,$0148,$0149,$014c,$014d
	dc.w	$0150,$0151,$0154,$0155,$0158,$0159,$015c,$015d
	dc.w	$0160,$0161,$0164,$0165

;------------------------------------------------------------------------------
; screen_rows: each row's offset in the screen, with 4 lines more between rows 3 and 4.
;------------------------------------------------------------------------------
screen_rows:	; from: draw_frame
	dc.w	$0000,$0460,$08c0,$0d20,$0fa0,$1400,$1860,$1cc0
	dc.w	$2120,$2580,$29e0,$2e40,$32a0,$3700,$3b60,$3fc0
	dc.w	$4420,$4880,$4ce0,$5140,$55a0,$5a00,$5e60,$62c0
	dc.w	$6720,$6b80,$6fe0,$7440,$78a0,$7d00,$8160

;------------------------------------------------------------------------------
; toggle_cursor: the cursor's block inverted at the column and row.
;------------------------------------------------------------------------------
toggle_cursor:	; from: get_key_cursor
	movem.l	d0/a2,-(sp)
	bsr.w	screen_address                  ; its place
	not.b	(a2)                            ; 7 lines inverted
	not.b	$a0(a2)
	not.b	$140(a2)
	not.b	$1e0(a2)
	not.b	$280(a2)
	not.b	$320(a2)
	not.b	$3c0(a2)
	movem.l	(sp)+,d0/a2
	rts

;------------------------------------------------------------------------------
; screen_address: a2 = the screen byte of the cursor's column and row.
;------------------------------------------------------------------------------
screen_address:	; from: toggle_cursor, print_space, print_char
	lea	ws_screen(a5),a2                ; the screen
	move.w	ws_row(a5),d0                   ; the row
	add.w	d0,d0
	movea.l	ws_rows(a5),a0                  ; the row table
	adda.w	0(a0,d0.w),a2
	move.w	ws_column(a5),d0                ; the column
	add.w	d0,d0
	lea	column_offsets(pc),a0
	adda.w	0(a0,d0.w),a2
	rts

;------------------------------------------------------------------------------
; print_space: a blank (inverse if on) at the cursor, then the cursor on.
;------------------------------------------------------------------------------
print_space:	; from: evaluate, draw_title, draw_watch, print_hex_long
	movem.l	d0/a0-a2,-(sp)
	bsr.w	screen_address                  ; its place
	btst	#$0,ws_inverse(a5)              ; inverse?
	sne	d0
	move.b	d0,(a2)                         ; 6 lines
	move.b	d0,$a0(a2)
	move.b	d0,$140(a2)
	move.b	d0,$1e0(a2)
	move.b	d0,$280(a2)
	move.b	d0,$320(a2)
	bra.s	print_char_next                 ; the cursor on

;------------------------------------------------------------------------------
; print_char: the character d0 at the cursor (7 lines of the font, inverse if on), the cursor on, a new line
; after column 79.  Control characters: 9 tab (the next tab stop), 10 new line, 11 the second font, 12 the
; first font, 14 inverse on or off.
;------------------------------------------------------------------------------
print_char:	; from: evaluate, edit_memory, edit_line, draw_title, draw_registers, draw_watch, 5 more
	movem.l	d0/a0-a2,-(sp)                  ; saved
	subi.w	#$20,d0                         ; a control character?
	bcs.w	print_control                   ; yes
	lsl.w	#3,d0                           ; 8 bytes a character
	movea.l	ws_font(a5),a1                  ; the font
	addq.w	#1,a1                           ; from its second line
	adda.w	d0,a1
	bsr.w	screen_address                  ; its place
	move.b	(a1)+,(a2)                      ; 7 lines
	move.b	(a1)+,$a0(a2)
	move.b	(a1)+,$140(a2)
	move.b	(a1)+,$1e0(a2)
	move.b	(a1)+,$280(a2)
	move.b	(a1)+,$320(a2)
	move.b	(a1)+,$3c0(a2)
	btst	#$0,ws_inverse(a5)              ; inverse?
	beq.s	print_char_next                 ; no
	not.b	(a2)                            ; inverted
	not.b	$a0(a2)
	not.b	$140(a2)
	not.b	$1e0(a2)
	not.b	$280(a2)
	not.b	$320(a2)
print_char_next:	; from: print_space
	move.w	ws_column(a5),d0                ; the column
	addq.w	#1,d0                           ; on
	cmp.w	#$50,d0                         ; past the end?
	bcc.s	print_new_line                  ; yes: a new line
	move.w	d0,ws_column(a5)
print_char_done:	; from: tab_stops
	movem.l	(sp)+,d0/a0-a2
	rts
print_control:
	addi.w	#$20,d0
	cmp.b	#$9,d0                          ; tab?
	beq.s	print_tab
	cmp.b	#$a,d0                          ; new line?
	beq.s	print_new_line
	cmp.b	#$b,d0                          ; the second font?
	beq.s	print_font_two
	cmp.b	#$c,d0                          ; the first font?
	beq.s	print_font_one
	cmp.b	#$e,d0                          ; inverse?
	beq.s	print_inverse
	bra.s	print_char_done
print_font_one:
	lea	font_one(pc),a1                 ; the first font
	move.l	a1,ws_font(a5)
	bra.s	print_char_done
print_font_two:
	lea	font_two(pc),a1                 ; the second font
	move.l	a1,ws_font(a5)
	bra.s	print_char_done
print_inverse:
	bchg	#$0,ws_inverse(a5)              ; inverse on or off
	bra.s	print_char_done
print_tab:
	move.w	ws_column(a5),d0                ; the column
	addq.w	#1,d0                           ; the next
	lea	tab_stops(pc),a1                ; the tab stops
	move.l	d1,-(sp)
print_tab_next:
	move.w	(a1)+,d1
	beq.s	print_tab_set                   ; the last: stay
	cmp.w	d1,d0                           ; past it?
	bhi.s	print_tab_next                  ; yes: the next
	move.w	d1,d0                           ; there
print_tab_set:
	move.l	(sp)+,d1
	move.w	d0,ws_column(a5)
	bra.s	print_char_done

;------------------------------------------------------------------------------
; tab_stops: 20, 36, 40, 55, 60, 79.
;------------------------------------------------------------------------------
tab_stops:	; from: print_char
	dc.w	$0014,$0024,$0028,$0037,$003c,$004f,$0000
print_new_line:	; from: print_char
	clr.w	ws_column(a5)                   ; column 0
	move.w	ws_row(a5),d0                   ; the row
	addq.w	#1,d0                           ; the next
	cmp.w	#$1e,d0                         ; past row 30?
	bls.s	print_new_line_set              ; no
	moveq	#0,d0                           ; back to 0
print_new_line_set:
	move.w	d0,ws_row(a5)
	bra.w	print_char_done

;------------------------------------------------------------------------------
; exception_spurious: any other vector from $8-$27 (spurious, and the rest): exception $1B.
;------------------------------------------------------------------------------
exception_spurious:	; from: take_vectors
	move.b	#$1b,$38.w                      ; exception $1B
	bra.w	enter_exception

;------------------------------------------------------------------------------
; exception_bus_error, exception_address_error: in the monitor, its fault routine (ws_fault) with the frame
; dropped; in the program, the exception (2 or 3) with the fault's address kept and pc back to the
; instruction (searched back for the opcode in the frame).
;------------------------------------------------------------------------------
exception_bus_error:	; from: start, take_vectors, exception_trap_15
	addq.w	#8,sp                           ; the long frame dropped
	move.l	a0,$30.w                        ; a0 kept
	movea.l	$38.w,a0                        ; the workspace
	tst.b	$270(a0)                        ; in the monitor?
	bne.s	exception_in_monitor            ; yes
	move.b	#$2,$38.w                       ; bus error
	bra.s	exception_fault
exception_address_error:	; from: start, take_vectors, exception_trap_15
	addq.w	#8,sp                           ; the long frame dropped
	move.l	a0,$30.w                        ; a0 kept
	movea.l	$38.w,a0                        ; the workspace
	tst.b	$270(a0)                        ; in the monitor?
	bne.s	exception_in_monitor            ; yes
	move.b	#$3,$38.w                       ; address error
exception_fault:
	move.l	d0,$34.w                        ; d0 kept
	move.l	-$6(sp),$90(a0)                 ; the address of the fault
	movea.l	2(sp),a0                        ; the pc of the frame
	move.w	-$2(sp),d0                      ; the opcode in the frame
exception_fault_find:
	subq.w	#2,a0
	cmp.w	(a0),d0                         ; the opcode?
	bne.s	exception_fault_find            ; no: a word back
	move.l	a0,2(sp)                        ; pc
	move.l	$34.w,d0
	bra.w	enter_monitor_saved
exception_in_monitor:
	move.l	$c(a0),-(sp)                    ; to its fault routine
	movea.l	$30.w,a0
	rts

;------------------------------------------------------------------------------
; exception_ignore: rte (divide by zero, and faults in the monitor by default).
;------------------------------------------------------------------------------
exception_ignore:	; from: start, command_loop, step_over, toggle_breakpoint, init_workspace, take_vectors, 2 more
	rte

;------------------------------------------------------------------------------
; command_fault: a fault in a command: "Command aborted due to BUS/ADDRESS error" and the command loop.
;------------------------------------------------------------------------------
command_fault:	; from: input_three_values, input_file_values, find_breakpoint
	lea	command_fault_text(pc),a0       ; "Command aborted due to BUS/ADDRESS error"
	bsr.w	print_message
	bra.w	command_loop

;------------------------------------------------------------------------------
; exception_illegal: a breakpoint (ILLEGAL) is exception 1, any other illegal instruction 4.
;------------------------------------------------------------------------------
exception_illegal:	; from: start, resume, take_vectors
	move.b	#$1,$38.w                       ; breakpoint
	move.l	a0,$30.w                        ; a0 kept
	movea.l	$38.w,a0
	movea.l	2(sp),a0                        ; pc
	cmpi.w	#$4afc,(a0)                     ; ILLEGAL?
	beq.w	enter_monitor_saved             ; yes
	move.b	#$4,$38.w                       ; illegal instruction
	bra.w	enter_monitor_saved

;------------------------------------------------------------------------------
; exception_chk, exception_trapv, exception_privilege, exception_trace and the traps: the exception's number
; into the workspace pointer's top byte, then into the monitor.
;------------------------------------------------------------------------------
exception_chk:	; from: start, take_vectors
	move.b	#$5,$38.w                       ; CHK
	bra.w	enter_exception
exception_trapv:	; from: start, take_vectors
	move.b	#$6,$38.w                       ; TRAPV
	bra.w	enter_exception
exception_privilege:	; from: start, take_vectors
	move.b	#$7,$38.w                       ; privilege violation
	bra.w	enter_exception
exception_trace:	; from: resume
	move.b	#$0,$38.w                       ; trace (a step)
	bra.w	enter_exception
exception_9:
	move.b	#$9,$38.w                       ; (not set)
	bra.w	enter_exception
exception_10:
	move.b	#$a,$38.w                       ; (not set)
	bra.w	enter_exception
exception_12:
	move.b	#$c,$38.w                       ; (not set)
	bra.w	enter_exception
exception_13:
	move.b	#$d,$38.w                       ; (not set)
	bra.w	enter_exception
exception_trap_3:	; from: start, take_vectors
	move.b	#$e,$38.w                       ; trap #3
	bra.w	enter_exception
exception_trap_4:	; from: start
	move.b	#$f,$38.w                       ; trap #4 (only at start-up)
	bra.w	enter_exception
exception_trap_5:	; from: start, take_vectors
	move.b	#$10,$38.w                      ; trap #5
	bra.w	enter_exception
exception_trap_6:	; from: start, take_vectors
	move.b	#$11,$38.w                      ; trap #6
	bra.w	enter_exception
exception_trap_7:	; from: start, take_vectors
	move.b	#$12,$38.w                      ; trap #7
	bra.w	enter_exception
exception_trap_8:	; from: start, take_vectors
	move.b	#$13,$38.w                      ; trap #8
	bra.w	enter_exception
exception_trap_9:	; from: start, take_vectors
	move.b	#$14,$38.w                      ; trap #9
	bra.w	enter_exception
exception_trap_10:	; from: start, take_vectors
	move.b	#$15,$38.w                      ; trap #10
	bra.w	enter_exception
exception_trap_11:	; from: start, take_vectors
	move.b	#$16,$38.w                      ; trap #11
	bra.w	enter_exception
exception_trap_12:	; from: start, take_vectors
	move.b	#$17,$38.w                      ; trap #12
	bra.w	enter_exception
exception_trap_13:
	move.b	#$18,$38.w                      ; trap #13 (not set)
	bra.w	enter_exception
exception_trap_14:
	move.b	#$19,$38.w                      ; trap #14 (not set)
	bra.w	enter_exception

;------------------------------------------------------------------------------
; exception_trap_15: the way into the monitor: bus and address errors taken again first.
;------------------------------------------------------------------------------
exception_trap_15:	; from: start, take_vectors
	move.l	a1,-(sp)
	lea	exception_bus_error(pc),a1      ; bus error
	move.l	a1,$8.w                         ; bus error vector
	lea	exception_address_error(pc),a1  ; address error
	move.l	a1,$c.w                         ; address error vector
	movea.l	(sp)+,a1
	move.b	#$1a,$38.w                      ; trap #15
	bra.w	enter_exception
enter_exception:	; from: exception_spurious, exception_chk
	move.l	a0,$30.w                        ; a0 kept
	movea.l	$38.w,a0                        ; the workspace

;------------------------------------------------------------------------------
; enter_monitor_saved: the program's registers, USP, SSP, SR and pc into the workspace, the workspace set up
; if its magic is not there, the breakpoints taken out, the screen drawn and the exception named, then the
; command loop.
;------------------------------------------------------------------------------
enter_monitor_saved:	; from: exception_bus_error, exception_illegal
	move.w	#$2700,sr                       ; interrupts off
	movea.l	$38.w,a0                        ; the workspace
	lea	$10(a0),a0                      ; the registers
	movem.l	d0-d7,(a0)                      ; d0-d7
	move.l	$30,$20(a0)                     ; a0
	movem.l	a1-a6,$24(a0)                   ; a1-a6
	move.l	usp,a1                          ; USP
	move.l	a1,$3c(a0)
	move.w	(sp)+,$48(a0)                   ; SR
	move.l	(sp)+,$44(a0)                   ; pc
	bclr	#$0,$47(a0)                     ; even
	move.l	sp,$40(a0)                      ; SSP
	movea.l	$38.w,a5                        ; the workspace
	lea	ws_message(a5),sp               ; the monitor's stack
	cmpi.l	#$53484954,ws_magic(a5)         ; 'SHIT': set up?
	beq.s	enter_monitor_breakpoints       ; yes
	bsr.w	reinit_workspace                ; no: set up
enter_monitor_breakpoints:
	st	ws_in_monitor(a5)               ; in the monitor
	lea	exception_ignore(pc),a1         ; faults: rte
	move.l	a1,ws_fault(a5)
	clr.b	$44(a0)                         ; pc's top byte cleared
	move.l	$44(a0),d2                      ; pc
	moveq	#-1,d3                          ; the slot free
	moveq	#3,d1                           ; 4
	tst.b	ws_stepping(a5)                 ; stepping?
	bne.s	enter_monitor_drawn             ; yes: no breakpoints set
	clr.b	ws_key_held(a5)                 ; no key held
	lea	ws_temp_breakpoint(a5),a1       ; the temporary breakpoint
	lea	ws_breakpoint_words(a5),a2      ; the saved words
	move.l	(a1)+,d0
	bmi.s	enter_monitor_breakpoint        ; none
	movea.l	d0,a3
	move.w	ws_temp_breakpoint_word(a5),(a3) ; its word back
	move.l	d3,ws_temp_breakpoint(a5)       ; cleared
enter_monitor_breakpoint:
	move.l	(a1)+,d0
	bmi.s	enter_monitor_breakpoint_next   ; none
	andi.l	#$ffffff,d0
	movea.l	d0,a3
	cmpa.l	d2,a3                           ; at pc?
	bne.s	enter_monitor_restore           ; no
	sf	ws_keep_program_screen(a5)      ; not always the program's screen
	move.l	d3,-$4(a1)                      ; (the slot made free here)
enter_monitor_restore:
	move.w	(a2),(a3)                       ; its word back
enter_monitor_breakpoint_next:
	addq.w	#2,a2
	dbra	d1,enter_monitor_breakpoint
enter_monitor_drawn:
	sf	ws_stepping(a5)                 ; not stepping
	tst.b	ws_drawn(a5)                    ; the screen drawn?
	bne.s	enter_monitor_name              ; yes
	bsr.w	draw_screen                     ; drawn
enter_monitor_name:
	moveq	#0,d1
	move.b	$38.w,d1                        ; the exception
	beq.s	enter_monitor_fault             ; trace: no name
	subq.w	#1,d1
	beq.s	enter_monitor_screen            ; a breakpoint?
	sf	ws_keep_program_screen(a5)      ; no: the program's screen not kept
enter_monitor_screen:
	tst.b	ws_keep_program_screen(a5)      ; always the program's?
	bne.s	enter_monitor_show_name         ; yes
	bsr.w	show_monitor_screen             ; the monitor's
enter_monitor_show_name:
	move.w	#$1c,ws_row(a5)                 ; row 28
	move.w	#$1,ws_column(a5)               ; column 1
	lea	exception_names(pc),a0          ; the exception names
	bra.s	enter_monitor_name_find
enter_monitor_name_skip:
	tst.b	(a0)+                           ; to the next name
	bne.s	enter_monitor_name_skip
	tst.b	(a0)
	bne.s	enter_monitor_name_find
	addq.w	#1,a0
	bra.s	enter_monitor_name_print
enter_monitor_name_find:
	dbra	d1,enter_monitor_name_skip
enter_monitor_name_print:
	move.l	a0,-(sp)
	bsr.w	print_text                      ; printed
	lea	exception_text(pc),a0           ; " exception"
	bsr.w	print_text
	movea.l	(sp)+,a0
enter_monitor_fault:
	move.b	$38.w,d0
	cmp.b	#$2,d0                          ; bus error?
	beq.s	enter_monitor_fault_address     ; yes
	cmp.b	#$3,d0                          ; address error?
	bne.s	enter_monitor_loop              ; no
enter_monitor_fault_address:
	lea	fault_address_text(pc),a0       ; " on accessing address $"
	bsr.w	print_text
	move.l	ws_scratch(a5),d0               ; the address
	bsr.w	print_hex_long                  ; printed
enter_monitor_loop:
	bsr.w	redraw_windows                  ; drawn
	st	ws_message(a5)                  ; a message shown
	sf	$38.w                           ; the exception cleared
	bra.w	command_loop                    ; the command loop

;------------------------------------------------------------------------------
; register_names: the names the expressions know, in the order of register_offsets: D0-D7, A0-A7, SR, PC, SP,
; USP, SSP, W1-W4 (the windows' bases), BP0-BP3, SYMTAB (the label table), VIDPTR (the program's screen
; pointer), BSS, DATA, TEXT.
;------------------------------------------------------------------------------
register_names:	; from: find_register
	dc.w	$4430,$0044,$3100,$4432,$0044,$3300,$4434,$0044
	dc.w	$3500,$4436,$0044,$3700,$4130,$0041,$3100,$4132
	dc.w	$0041,$3300,$4134,$0041,$3500,$4136,$0041,$3700
	dc.w	$5352,$0050,$4300,$5350
	dc.b	$00
	dc.b	'USP',0
	dc.b	'SSP',0
	dc.b	$57,$31,$00,$57,$32,$00,$57,$33,$00,$57,$34,$00
	dc.b	'BP0',0
	dc.b	'BP1',0
	dc.b	'BP2',0
	dc.b	'BP3',0
	dc.b	'SYMTAB',0
	dc.b	'VIDPTR',0
	dc.b	'BSS',0
	dc.b	'DATA',0
	dc.b	'TEXT',0
	dc.b	$00,$00,$00,$00,$00

;------------------------------------------------------------------------------
; register_offsets: each name's place in the workspace ($8000 for a word).
;------------------------------------------------------------------------------
register_offsets:	; from: find_register, follow_registers
	dc.w	$0010,$0014,$0018,$001c,$0020,$0024,$0028,$002c
	dc.w	$0030,$0034,$0038,$003c,$0040,$0044,$0048,$004c
	dc.w	$8058,$0054,$004c,$004c,$0050,$006e,$0072,$0076
	dc.w	$007a,$0098,$009c,$00a0,$00a4,$0064,$005a,$00c2
	dc.w	$00c6,$00ca

;------------------------------------------------------------------------------
; frame_text: the monitor's screen: the frame (the second font's line characters), the register names and the
; window titles' rows.
;------------------------------------------------------------------------------
frame_text:	; from: draw_frame
	dc.b	$0b
	dc.b	'dREGISTERSgggggggggghggggggggggggggggg SUB HUMANS IN TURKEY L.L.'
	dc.b	'S. CARTRIDGE ggeaD0:',9,'aD1:',9,9,'aD2:',9,9,'aD3:',9,'aaD4:',9,'aD5:'
	dc.b	9,9,'aD6:',9,9,'aD7:',9
	dc.b	'ajgggggggggggggggggggigggggggggggggggggggfgggggggggggggggggggigg'
	dc.b	'ggggggggggggggggkaA0:',9,9,9,'aA1:',9,9,9,'aaA2:',9,9,9,'aA3:',9,9,9
	dc.b	'aaA4:',9,9,9,'aA5:',9,9,9,'aaA6:',9,9,9,'aUSP',9,9,9,'aaSSP',9,9,9
	dc.b	'aSR:',9,'    IPL: ',9,'aaPC:',9,9,9,9,9,9
	dc.b	'ajW1 DISASSEMBLYgggggggggggggggggggggggggigggggggggggggghW2 MEMO'
	dc.b	'RYggggggggggggggka',9,9,9,9,'a',9,9,'aa',9,9,9,9,'a',9,9,'aa',9,9,9,9
	dc.b	'a',9,9,'aa',9,9,9,9,'a',9,9,'aa',9,9,9,9,'a',9,9,'aa',9,9,9,9,'a',9,9
	dc.b	'aa',9,9,9,9,'a',9,9,'aa',9,9,9,9,'a',9,9,'aa',9,9,9,9,'a',9,9,'aa',9,9
	dc.b	9,9,'a',9,9,'aa',9,9,9,9,'a',9,9,'aa',9,9,9,9,'a',9,9
	dc.b	'ajWATCH AREAggggggggggggggggggggggggggggggggggggggggggggiggggggg'
	dc.b	'ggggggggggggggggka',9,9,9,9,9,9,'aa',9,9,9,9,9,9,'aa',9,9,9,9,9,9,'aa'
	dc.b	9,9,9,9,9,9,'a'

;------------------------------------------------------------------------------
; clear_row_text: the message row cleared.
;------------------------------------------------------------------------------
clear_row_text:	; from: clear_message
	dc.b	$0b
	dc.b	'bggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg'
	dc.b	'gggggggggggggggc'
	dc.w	$0c00,$0c00
lower_frame_w3:	; from: draw_lower_frame
	dc.b	$0b
	dc.b	'jW3 DISASSEMBLYggggggggggggggggggggggggggggggggggggggggk'
	dc.b	$0c,$00
lower_frame_w4:	; from: draw_lower_frame
	dc.b	$0b
	dc.b	'a',9,9,9,9,'jW4 MEMORYggggggggggggggk'
	dc.w	$0c00
lower_frame_both:	; from: draw_lower_frame
	dc.b	$0b
	dc.b	'jW3 DISASSEMBLYggggggggggggggggggggggggggggggggggggggggfW4 MEMOR'
	dc.b	'Yggggggggggggggk'
	dc.b	$0c,$00
lower_frame_none:	; from: draw_lower_frame
	dc.b	$0b
	dc.b	'a',9,9,9,9,'a',9,9,'a'
	dc.b	$0c,$00,$00

;------------------------------------------------------------------------------
; opcode_table: each instruction's mask, value, routine (from opcode_table) and name, in the order they are
; tried; a 0 mask ends it.
;------------------------------------------------------------------------------
opcode_table:	; from: disassemble
	dc.w	$ff00,$0000,dis_ori-opcode_table
	dc.b	'ORI '
	dc.w	$ff00,$0200,dis_andi-opcode_table
	dc.b	'ANDI'
	dc.w	$ff00,$0400,dis_addi-opcode_table
	dc.b	'SUBI'
	dc.w	$ff00,$0600,dis_addi-opcode_table
	dc.b	'ADDI'
	dc.w	$ff00,$0a00,dis_andi-opcode_table
	dc.b	'EORI'
	dc.w	$ff00,$0c00,dis_addi-opcode_table
	dc.b	'CMPI'
	dc.w	$f138,$0108,dis_movep-opcode_table
	dc.b	'MOVE'
	dc.w	$f0c0,$0000,dis_bit-opcode_table
	dc.b	'BTST'
	dc.w	$f0c0,$0040,dis_bit-opcode_table
	dc.b	'BCHG'
	dc.w	$f0c0,$0080,dis_bit-opcode_table
	dc.b	'BCLR'
	dc.w	$f0c0,$00c0,dis_bit-opcode_table
	dc.b	'BSET'
	dc.w	$c000,$0000,dis_move-opcode_table
	dc.b	'MOVE'
	dc.w	$f9c0,$40c0,dis_move_sr-opcode_table
	dc.b	'MOVE'
	dc.w	$ff00,$4000,dis_negx-opcode_table
	dc.b	'NEGX'
	dc.w	$ff00,$4400,dis_neg-opcode_table
	dc.b	'NEG '
	dc.w	$ff00,$4600,dis_neg-opcode_table
	dc.b	'NOT '
	dc.w	$ffc0,$4800,dis_ea_only-opcode_table
	dc.b	'NBCD'
	dc.w	$ff00,$4200,dis_neg-opcode_table
	dc.b	'CLR '
	dc.w	$ffb8,$4880,dis_ext-opcode_table
	dc.b	'EXT '
	dc.w	$fff0,$4840,dis_ea_only-opcode_table
	dc.b	'SWAP'
	dc.w	$ffc0,$4840,dis_ea_only-opcode_table
	dc.b	'PEA '
	dc.w	$ffff,$4afc,dis_illegal-opcode_table
	dc.b	'ILLE'
	dc.w	$ffc0,$4ac0,dis_ea_only-opcode_table
	dc.b	'TAS '
	dc.w	$ff00,$4a00,dis_neg-opcode_table
	dc.b	'TST '
	dc.w	$fb80,$4880,dis_movem-opcode_table
	dc.b	'MOVE'
	dc.w	$fff0,$4e40,dis_trap-opcode_table
	dc.b	'TRAP'
	dc.w	$fff8,$4e50,dis_link-opcode_table
	dc.b	'LINK'
	dc.w	$fff8,$4e58,dis_unlk-opcode_table
	dc.b	'UNLK'
	dc.w	$fff0,$4e60,dis_move_usp-opcode_table
	dc.b	'MOVE'
	dc.w	$ffff,$4e70,dis_reset-opcode_table
	dc.b	'RESE'
	dc.w	$ffff,$4e71,return-opcode_table
	dc.b	'NOP '
	dc.w	$ffff,$4e72,dis_word_operand-opcode_table
	dc.b	'STOP'
	dc.w	$ffff,$4e73,return-opcode_table
	dc.b	'RTE '
	dc.w	$ffff,$4e76,dis_trapv-opcode_table
	dc.b	'TRAP'
	dc.w	$ffff,$4e75,return-opcode_table
	dc.b	'RTS '
	dc.w	$ffff,$4e77,return-opcode_table
	dc.b	'RTR '
	dc.w	$ffc0,$4e80,dis_ea_only-opcode_table
	dc.b	'JSR '
	dc.w	$ffc0,$4ec0,dis_ea_only-opcode_table
	dc.b	'JMP '
	dc.w	$f1c0,$4180,dis_chk-opcode_table
	dc.b	'CHK '
	dc.w	$f1c0,$41c0,dis_lea-opcode_table
	dc.b	'LEA '
	dc.w	$f0f8,$50c8,dis_dbcc-opcode_table
	dc.b	'DBcc'
	dc.w	$f0c0,$50c0,dis_scc-opcode_table
	dc.b	'Scc '
	dc.w	$f100,$5000,dis_addq-opcode_table
	dc.b	'ADDQ'
	dc.w	$f100,$5100,dis_addq-opcode_table
	dc.b	'SUBQ'
	dc.w	$f000,$6000,dis_bcc-opcode_table
	dc.b	'Bcc '
	dc.w	$f100,$7000,dis_moveq-opcode_table
	dc.b	'MOVE'
	dc.w	$f1f0,$8100,dis_abcd-opcode_table
	dc.b	'SBCD'
	dc.w	$f1c0,$80c0,dis_mul-opcode_table
	dc.b	'DIVU'
	dc.w	$f1c0,$81c0,dis_mul-opcode_table
	dc.b	'DIVS'
	dc.w	$f000,$8000,dis_or-opcode_table
	dc.b	'OR  '
	dc.w	$f0c0,$90c0,dis_adda-opcode_table
	dc.b	'SUBA'
	dc.w	$f130,$9100,dis_addx-opcode_table
	dc.b	'SUBX'
	dc.w	$f000,$9000,dis_add-opcode_table
	dc.b	'SUB.'
	dc.w	$f0c0,$b0c0,dis_adda-opcode_table
	dc.b	'CMPA'
	dc.w	$f138,$b108,dis_cmpm-opcode_table
	dc.b	'CMPM'
	dc.w	$f100,$b000,dis_cmp-opcode_table
	dc.b	'CMP '
	dc.w	$f100,$b100,dis_eor-opcode_table
	dc.b	'EOR '
	dc.w	$f1f0,$c100,dis_abcd-opcode_table
	dc.b	'ABCD'
	dc.w	$f1c0,$c0c0,dis_mul-opcode_table
	dc.b	'MULU'
	dc.w	$f1c0,$c1c0,dis_mul-opcode_table
	dc.b	'MULS'
	dc.w	$f1f8,$c140,dis_exg_data-opcode_table
	dc.b	'EXG '
	dc.w	$f1f8,$c148,dis_exg_address-opcode_table
	dc.b	'EXG '
	dc.w	$f1f8,$c188,dis_exg_mixed-opcode_table
	dc.b	'EXG '
	dc.w	$f000,$c000,dis_add-opcode_table
	dc.b	'AND '
	dc.w	$f0c0,$d0c0,dis_adda-opcode_table
	dc.b	'ADDA'
	dc.w	$f130,$d100,dis_addx-opcode_table
	dc.b	'ADDX'
	dc.w	$f000,$d000,dis_add-opcode_table
	dc.b	'ADD '
	dc.w	$f000,$e000,dis_shift-opcode_table
	dc.b	'    '
	dc.w	$0000

;------------------------------------------------------------------------------
; key_table_normal: the character of each scan code (F1-F10 $14-$1d, the cursor keys $01-$04, Delete $7F).
;------------------------------------------------------------------------------
key_table_normal:	; from: get_key
	dc.b	$00
	dc.b	27,'1234567890-='
	dc.b	$08
	dc.b	9,'qwertyuiop[]',13,0
	dc.b	'asdfghjkl;',$27,'`',0
	dc.b	'#zxcvbnm,./',0
	dc.b	$00,$00,$20,$00,$14,$15,$16,$17,$18,$19,$1a,$1b,$1c,$1d,$00,$00
	dc.b	$00,$01,$00,$2d,$03,$00,$04,$2b,$00,$02,$00,$00,$7f,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$5c,$00,$00
	dc.b	'()/*7894561230.',13

;------------------------------------------------------------------------------
; key_table_shifted: the same with Shift or Caps Lock (Shift F1-F5 give nothing).
;------------------------------------------------------------------------------
key_table_shifted:	; from: get_key
	dc.b	$00,$1b,$21,$22,$9c
	dc.b	'$%^&*()_+'
	dc.b	$08
	dc.b	9,'QWERTYUIOP{}',13,0
	dc.b	'ASDFGHJKL:@_',0
	dc.b	'~ZXCVBNM<>?',0
	dc.w	$0000,$2000,$0000,$0000,$0019,$1a1b,$1c1d,$0000
	dc.w	$0001,$002d,$0300,$042b,$0002,$0000,$7f00,$0000
	dc.w	$0000,$0000,$0000,$0000,$007c,$0000
	dc.b	'()/*7894561230.',13
command_fault_text:	; from: command_fault
	dc.b	'Command aborted due to BUS/ADDRESS error',0
edit_fault_text:	; from: edit_memory_write
	dc.b	'Edit aborted due to BUS/ADDRESS error',0
fault_address_text:	; from: enter_monitor_saved
	dc.b	' on accessing address $',0
temporary_breakpoint_text:	; from: step_over
	dc.b	'Cannot set temporary breakpoint!',0
breakpoint_failed_text:	; from: toggle_breakpoint
	dc.b	'Cannot set breakpoint!',0
breakpoint_set_text:	; from: toggle_breakpoint
	dc.b	'Breakpoint SET',0
breakpoint_cleared_text:	; from: toggle_breakpoint
	dc.b	'Breakpoint CLEARED',0
breakpoint_prompt:	; from: breakpoint_at
	dc.b	'Set/Clear Breakpoint > ',0
no_breakpoints_text:	; from: find_breakpoint
	dc.b	'No more breakpoints left!',0
workspace_prompt:	; from: set_workspace
	dc.b	'Set DEBUGGER workspace > ',0
relocate_prompt:	; from: move_debugger
	dc.b	'Relocate DEBUGGER to > ',0
window_base_prompt:	; from: set_window_base
	dc.b	'Modify window base > ',0
expression_prompt:	; from: evaluate
	dc.b	'Enter expression > ',0
lock_prompt:	; from: lock_window
	dc.b	'Lock window to register > ',0
reinitialise_question:	; from: initialise_workspace
	dc.b	'Are you sure you want to reinitialise the workspace [Y/N] ? ',0
download_question:	; from: go_download
	dc.b	'Are you sure you want to go to download [Y/N] ? ',0
quit_question:	; from: quit_monitor
	dc.b	'Are you sure you want to quit [Y/N] ? ',0
run_question:	; from: run_program
	dc.b	'Are you sure you want to run [Y/N] ? ',0
result_text:	; from: evaluate
	dc.b	'Result=$',0

;------------------------------------------------------------------------------
; first_watches: "BP0" to "BP3", ended by '$'.
;------------------------------------------------------------------------------
first_watches:	; from: init_workspace
	dc.b	'BP0',0
	dc.b	'BP1',0
	dc.b	'BP2',0
	dc.b	'BP3',0
	dc.w	$0024
register_prompt:	; from: set_register
	dc.b	'Enter Register=Value > ',0
label_prompt:	; from: set_label
	dc.b	'Enter Label=Value > ',0
edit_memory_text:	; from: edit_memory
	dc.b	'Enter hexadecimal and then RETURN to accept or ESCAPE to abort.',0
edit_watch_prompt:	; from: edit_watch
	dc.b	'Edit Watch > ',0
add_watch_prompt:	; from: add_watch
	dc.b	'Add Watch > ',0
search_question:	; from: find
	dc.b	'Search for Byte, Word, Long, Text ? ',0
byte_prompt:	; from: find
	dc.b	'Byte to find > ',0
word_prompt:	; from: find
	dc.b	'Word to find > ',0
long_prompt:	; from: find
	dc.b	'Longword to find > ',0
string_prompt:	; from: find
	dc.b	'String to find > ',0
case_question:	; from: find
	dc.b	'Search case sensitive [Y/N] ? ',0
searching_text:	; from: search_next, find, input_search_value
	dc.b	'Searching...',0
fill_prompt:	; from: fill_memory
	dc.b	'Fill start, end, with > ',0
copy_prompt:	; from: copy_memory
	dc.b	'Copy start, end, dest > ',0
watch_full_text:	; from: edit_watch
	dc.b	'The WATCH buffer is full, line deleted!',0
no_lock_text:	; from: draw_title
	dc.b	$0b,$67,$67,$67,$67,$0c,$00
binary_question:	; from: binary_load_save
	dc.b	'Binary Load/Save [L/S] ? ',0
binary_save_prompt:	; from: binary_load_save
	dc.b	'Binary Save File,start,length > ',0
binary_load_prompt:	; from: binary_load_save
	dc.b	'Binary Load File,start > ',0
executable_prompt:	; from: load_executable
	dc.b	'Load an Executable File > ',0
open_failed_text:	; from: binary_load_save
	dc.b	'Cannot open file',0
read_failed_text:	; from: binary_load_save
	dc.b	'Cannot read from file',0
write_failed_text:	; from: binary_load_save
	dc.b	'Cannot write to file',0
load_failed_text:	; from: binary_load_save
	dc.b	'Cannot load executable file',0
dma_read_prompt:	; from: read_sectors
	dc.b	'DMA Read - Filename,start,length > ',0
dma_write_prompt:	; from: write_sectors, write_file
	dc.b	'DMA Write - Filename,start,length > ',0

;------------------------------------------------------------------------------
; window_titles: each title's window, row and column, then its text.
;------------------------------------------------------------------------------
window_titles:	; from: draw_titles
	dc.b	$01,$0a,$01
	dc.b	'W1 DISASSEMBLY',0
	dc.b	$02
	dc.b	10,'8W2 MEMORY',0
	dc.w	$0017
	dc.b	$01
	dc.b	'WATCH AREA',0
	dc.w	$0311
	dc.b	$01
	dc.b	'W3 DISASSEMBLY',0
	dc.w	$0411
	dc.b	'8W4 MEMORY',0
exception_text:	; from: enter_monitor_saved
	dc.b	' exception',0

;------------------------------------------------------------------------------
; exception_names: the exceptions' names by number (1 Breakpoint, 2 Bus error ...), an empty name for none.
;------------------------------------------------------------------------------
exception_names:	; from: enter_monitor_saved
	dc.b	'Breakpoint',0
	dc.b	'Bus error',0
	dc.b	'Address error',0
	dc.b	'Illegal instruction',0
	dc.b	'CHK',0
	dc.b	'TRAPV',0
	dc.b	'Privilege',0
	dc.b	'Trace',0
	dc.b	'Line 1010',0
	dc.b	'Line 1111',0
	dc.b	'TRAP #0',0
	dc.b	'TRAP #1',0
	dc.b	'TRAP #2',0
	dc.b	'TRAP #3',0
	dc.b	'TRAP #4',0
	dc.b	'TRAP #5',0
	dc.b	'TRAP #6',0
	dc.b	'TRAP #7',0
	dc.b	'TRAP #8',0
	dc.b	'TRAP #9',0
	dc.b	'TRAP #10',0
	dc.b	'TRAP #11',0
	dc.b	'TRAP #12',0
	dc.b	'TRAP #13',0
	dc.b	'TRAP #14',0
	dc.b	'TRAP #15',0
	dc.b	'Unknown',0
	dc.b	$00

;------------------------------------------------------------------------------
; help_text: the help screen.  It is not quite the key table: F6 Load Bootsector is F10 here, F10 Start
; download and E Load executable are not in it, *M is Control M, and F7 (write_file) is not listed.
;------------------------------------------------------------------------------
help_text:	; from: help
	dc.b	10,10,10,10,'F1  Single Step',9,9,'F2  Breakpoint and run',10
	dc.b	'F3  Skip instruction',9,'F10 Start download',10,'F4  Read DMA sectors'
	dc.b	9,'F5  Write DMA sectors',10,'F6  Load Bootsector',9,9
	dc.b	'*F  Format Disk 80/10',10,'^B  Breakpoint here',9,9,'*B  Breakpoint at'
	dc.b	10,'^C  Quit monitor (ST)',9,'*D  Delete watch',10,'E   Load executable'
	dc.b	9,9,'*E  Edit memory/watch',10,'G   Find value',9,9
	dc.b	'*I  Initialise workspace',10,'^L  Set label value',9,9
	dc.b	'*L  Lock window to reg.',10,'M   Set window base',9,9
	dc.b	'*M  Move debugger',10,'N   Search next',9,9,'O   Evaluate expression'
	dc.b	10,'R   Run full speed',9,9,'*R  Set register',10,'*S  Split window',9,9
	dc.b	'V   View other screen',10,'*V  Always view other',9
	dc.b	'W   Fill memory with',10,'^W  Set workspace',9,9,'*W  Add watch',10
	dc.b	'Z   Zoom window',9,9,'TAB Next window',10,10,'^   Means control plus',9
	dc.b	'*   Means alt plus',10,10,'Press any key....',0
	dc.b	$00

;------------------------------------------------------------------------------
; font_one: 96 characters from Space, 8 bytes each (the first line not drawn).
;------------------------------------------------------------------------------
font_one:	; from: clear_screen, print_char
	dc.w	$0000,$0000,$0000,$0000,$0018,$1818,$1800,$1800
	dc.b	$00
	dc.b	'666',0
	dc.b	$00,$00,$00,$00,$36,$7f,$36,$36,$7f,$36,$00,$00,$0c,$3f,$6c,$3e
	dc.b	$1b,$7e,$18,$00,$63,$66,$0c,$18,$33,$63,$00,$00
	dc.b	'<f<gf;',0
	dc.w	$000c,$1800,$0000,$0000,$000c,$1818,$1818,$0c00
	dc.w	$0030,$1818,$1818,$3000,$0000,$361c,$7f1c,$3600
	dc.w	$0000,$1818,$7e18,$1800,$0000,$0000,$000c,$0c18
	dc.w	$0000,$003e,$0000,$0000,$0000,$0000,$0018,$1800
	dc.w	$0003,$060c,$1830,$6000
	dc.b	$00
	dc.b	'>go{s>',0
	dc.w	$0018,$3818,$1818,$3c00,$003e,$6303,$3e60,$7f00
	dc.w	$003e,$630e,$0363,$3e00,$000e,$1e36,$667f,$0600
	dc.w	$007f,$607e,$0363,$3e00
	dc.b	$00
	dc.b	'>`~cc>',0
	dc.w	$007f,$0306,$0c18,$1800
	dc.b	$00
	dc.b	'>c>cc>',0
	dc.w	$003e,$6363,$3f03,$3e00,$0000,$1818,$0018,$1800
	dc.w	$0000,$1818,$0018,$0810,$0000,$0c18,$3018,$0c00
	dc.w	$0000,$003e,$003e,$0000,$0000,$180c,$060c,$1800
	dc.w	$003e,$6306,$0c00,$0c00
	dc.b	$00
	dc.b	'>kko`>',0
	dc.w	$003e,$6363,$7f63,$6300
	dc.b	$00
	dc.b	'~c~cc~',0
	dc.b	$00
	dc.b	'>c``c>',0
	dc.b	$00
	dc.b	'|fccf|',0
	dc.w	$007f,$607c,$6060,$7f00,$007f
	dc.b	'`|```',0
	dc.b	$00
	dc.b	'>c`gc?',0
	dc.w	$0063,$637f
	dc.b	'ccc',0
	dc.w	$003c,$1818,$1818,$3c00,$0003,$0303,$0363,$3e00
	dc.b	$00
	dc.b	'cf||fc',0
	dc.w	$0060,$6060,$6060,$7f00,$0063,$777f
	dc.b	'kcc',0
	dc.b	$00
	dc.b	'cs{ogc',0
	dc.b	$00
	dc.b	'>cccc>',0
	dc.b	$00
	dc.b	'~cc~``',0
	dc.b	$00
	dc.b	'>ccof;',0
	dc.b	$00
	dc.b	'~cc~fc',0
	dc.w	$003e,$603e,$0363,$3e00,$007e,$1818,$1818,$1800
	dc.b	$00
	dc.b	'ccccc>',0
	dc.w	$0063,$6336,$361c,$0800,$0063,$636b,$7f77,$6300
	dc.w	$0063,$361c,$1c36,$6300,$0066,$6666,$3c18,$1800
	dc.w	$007f,$060c,$1830,$7f00
	dc.b	$00
	dc.b	'<0000<',0
	dc.w	$0060,$3018,$0c06,$0300,$003c,$0c0c,$0c0c,$3c00
	dc.w	$0008,$1c36,$0000,$0000,$0000,$0000,$0000,$3f00
	dc.w	$0018,$0c00,$0000,$0000,$0000,$3e03
	dc.b	'?c?',0
	dc.b	'``~ccc~',0
	dc.w	$0000
	dc.b	'>c`c>',0
	dc.w	$0303
	dc.b	'?ccc?',0
	dc.w	$0000
	dc.b	'>c~`>',0
	dc.w	$000e,$183e,$1818,$1800,$0000,$3f63,$633f
	dc.b	$03
	dc.b	'>``~cccc',0
	dc.w	$0c00,$1c0c,$0c0c,$1e00,$0600,$0e06,$0606,$663c
	dc.b	$00
	dc.b	'`flxlf',0
	dc.w	$0030,$3030,$3030,$1c00,$0000,$367f
	dc.b	'kcc',0
	dc.w	$0000
	dc.b	'~cccc',0
	dc.w	$0000
	dc.b	'>ccc>',0
	dc.w	$0000
	dc.b	'~ccc~`',0
	dc.b	$00,$3f,$63,$63,$63,$3f,$03,$00,$00
	dc.b	'~c```',0
	dc.w	$0000,$3e60,$3e03,$3e00,$0018,$3e18,$1818,$0e00
	dc.w	$0000
	dc.b	'cccc?',0
	dc.w	$0000,$6363,$6336,$1c00,$0000,$6363,$6b7f,$3600
	dc.w	$0000,$663c,$183c,$6600,$0000,$6363,$633f,$033e
	dc.w	$0000,$7f06,$1c30,$7f00,$000c,$1818,$3018,$180c
	dc.w	$0018,$1818,$1818,$1818,$0018,$0c0c,$060c,$0c18
	dc.b	$00
	dc.b	'1kF',0
	dc.b	$00,$00,$00,$18,$1c,$f6,$83,$83,$f6,$1c,$18

;------------------------------------------------------------------------------
; font_two: the second font: the frame's line characters.
;------------------------------------------------------------------------------
font_two:	; from: print_char
	dc.w	$0000,$0000,$0000,$0000,$0018,$1818,$1800,$1800
	dc.b	$00
	dc.b	'666',0
	dc.b	$00,$00,$00,$00,$36,$7f,$36,$36,$7f,$36,$00,$00,$0c,$3f,$6c,$3e
	dc.b	$1b,$7e,$18,$00,$63,$66,$0c,$18,$33,$63,$00,$00
	dc.b	'<f<gf;',0
	dc.w	$000c,$1800,$0000,$0000,$000c,$1818,$1818,$0c00
	dc.w	$0030,$1818,$1818,$3000,$0000,$361c,$7f1c,$3600
	dc.w	$0000,$1818,$7e18,$1800,$0000,$0000,$0008,$0810
	dc.w	$0000,$003e,$0000,$0000,$0000,$0000,$0018,$1800
	dc.w	$0003,$060c,$1830,$6000
	dc.b	$00
	dc.b	'>go{s>',0
	dc.w	$0018,$3818,$1818,$3c00,$003e,$6303,$3e60,$7f00
	dc.w	$003e,$630e,$0363,$3e00,$000e,$1e36,$667f,$0600
	dc.w	$007f,$607e,$0363,$3e00
	dc.b	$00
	dc.b	'>`~cc>',0
	dc.w	$007f,$0306,$0c18,$1800
	dc.b	$00
	dc.b	'>c>cc>',0
	dc.w	$003e,$6363,$3f03,$3e00,$0000,$1818,$0018,$1800
	dc.w	$0000,$1818,$0018,$0810,$0000,$0c18,$3018,$0c00
	dc.w	$0000,$003e,$003e,$0000,$0000,$180c,$060c,$1800
	dc.w	$003e,$6306,$0c00,$0c00
	dc.b	$00
	dc.b	'>kko`>',0
	dc.w	$003e,$6363,$7f63,$6300
	dc.b	$00
	dc.b	'~c~cc~',0
	dc.b	$00
	dc.b	'>c``c>',0
	dc.b	$00
	dc.b	'|fccf|',0
	dc.w	$007f,$607c,$6060,$7f00,$007f
	dc.b	'`|```',0
	dc.b	$00
	dc.b	'>c`gc?',0
	dc.w	$0063,$637f
	dc.b	'ccc',0
	dc.w	$003c,$1818,$1818,$3c00,$0003,$0303,$0363,$3e00
	dc.b	$00
	dc.b	'cf||fc',0
	dc.w	$0060,$6060,$6060,$7f00,$0063,$777f
	dc.b	'kcc',0
	dc.b	$00
	dc.b	'cs{ogc',0
	dc.b	$00
	dc.b	'>cccc>',0
	dc.b	$00
	dc.b	'~cc~``',0
	dc.b	$00
	dc.b	'>ccof;',0
	dc.b	$00
	dc.b	'~cc~fc',0
	dc.w	$003e,$603e,$0363,$3e00,$007e,$1818,$1818,$1800
	dc.b	$00
	dc.b	'ccccc>',0
	dc.w	$0063,$6336,$361c,$0800,$0063,$636b,$7f77,$6300
	dc.w	$0063,$361c,$1c36,$6300,$0066,$6666,$3c18,$1800
	dc.w	$007f,$060c,$1830,$7f00
	dc.b	$00
	dc.b	'<0000<',0
	dc.w	$0060,$3018,$0c06,$0300,$003c,$0c0c,$0c0c,$3c00
	dc.w	$0008,$1c36,$0000,$0000,$0000,$0000,$0000,$3f00
	dc.w	$0018,$0c00,$0000,$0000,$1818,$1818,$1818,$1818
	dc.w	$1818,$181f,$0000,$0000,$1818,$18f8,$0000,$0000
	dc.w	$0000,$001f,$1818,$1818,$0000,$00f8,$1818,$1818
	dc.w	$1818,$18ff,$1818,$1818,$0000,$00ff,$0000,$0000
	dc.w	$0000,$00ff,$1818,$1818,$1818,$18ff,$0000,$0000
	dc.w	$1818,$181f,$1818,$1818,$1818,$18f8,$1818,$1818
	dcb.b	160,0

;------------------------------------------------------------------------------
; font_end: where move_debugger's copy ends.
;------------------------------------------------------------------------------
font_end:	; from: move_debugger
	dcb.b	198,0

;------------------------------------------------------------------------------
; disk_image: what format_disk writes on track 0, side 0: the boot sector (The Medway Boys Protector III), the
; two FATs and the directory with the volume label "LLS_DISK.EGB", 10 sectors.
;------------------------------------------------------------------------------
disk_image:	; from: format_disk
	dc.w	$601c,$9049,$424d,$2020,$fe3f,$9d00,$0202,$0100
	dc.w	$0280,$0040,$06f9,$0300,$0a00,$0200,$0000,$4df9
	dc.w	$00ff,$8240,$3d7c,$0777,$001e,$41fa,$00c4,$6100
	dc.w	$00a8,$2079,$0000,$042e,$2248,$0c99,$1212
	dc.b	'4Vg',0
	dc.w	$0066,$91fc,$0000,$0200,$b1fc,$0000,$0000,$6ee6
	dc.w	$2038,$0426,$b0bc
	dc.b	'1AY&g',0
	dc.w	$0024,$3cbc,$0004,$41fa,$00ac,$6100
	dc.b	$00
	dc.b	'n"<',0
	dc.b	$05,$00,$00,$53,$81,$66,$fc,$3c,$bc,$07
	dc.b	'w=|',0
	dc.b	$00,$00,$1e,$4e,$75,$3c,$bc,$04,$00,$41,$fa,$00,$a8,$61,$00,$00
	dc.b	$4c,$61,$00,$00,$54,$0c,$00,$00,$3b,$67,$de,$0c,$00,$00,$3c,$66
	dc.b	$f0,$42,$b8,$04,$26,$42,$b8,$04,$2a,$60,$ce,$2a,$48,$3c,$bc,$04
	dc.b	$00,$41,$fa,$00,$dd,$61,$00,$00,$24,$61,$00,$00,$2c,$0c,$00,$00
	dc.b	$3b,$67,$b6,$0c,$00,$00,$3c,$66,$f0,$42,$b8,$04,$26,$42,$b8,$04
	dc.b	$2a,$42,$9d,$20,$79,$00,$00,$00,$04,$4e,$d0,$2f,$08,$3f,$3c,$00
	dc.b	$09,$4e,$41,$5c,$8f
	dc.b	'Nu?<',0
	dc.b	$07,$4e,$41,$54,$8f
	dc.b	'H@Nu',27,'Y %The Medway Boys Protector III',0
	dc.b	27,'Y*(You are FREE of viruses !',0
	dc.b	27,'Y&#The RESET VECTOR has been changed',27,'Y(+It MAY be a virus',27
	dc.b	'Y,,F1 Continue',27,'Y.,F2 Clear vector',0
	dc.b	27,'Y&%RESET RESIDENT prog in memory',27
	dc.b	'Y(#It is MORE than likely a VIRUS !!',27,'Y,-F1 Continue',27
	dc.b	'Y.-F2 Clear Virus',0
	dc.b	' (c) TS &'
	dc.w	$eeeb
disk_image_fat:
	dc.w	$f9ff,$ff00,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	1504,0
disk_image_fat_copy:
	dc.w	$f9ff,$ff00,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dcb.b	1504,0
disk_image_directory:
	dc.b	'LLS_DISKEGB'
	dc.b	$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$57,$0e,$86,$12,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dcb.b	1493,0
disk_image_end:
	dcb.b	229,0
	dcb.b	38683,$ff

	end
