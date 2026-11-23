; MONST2.PRG  -  MonST 2.13, the debugger of HiSoft Devpac 2.25 ("MonST2.13 (C) HiSoft 1991")
; Devpac source of the program, disassembled by Darren Birks, 23 November 2026.
; Text 25218 bytes, data 0 bytes, bss 0 bytes.
;
; This source rebuilds MONST2.PRG byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o MONST2.PRG MONST2.S
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; MonST, the debugger.  It keeps its variables past its own end (Mshrink leaves $11da bytes after the
; program, a6 points at them; they are named by the equates below) and draws on a screen of its own, switching
; to the program's screen while the program runs.  It refuses a screen mode above ST high, warns on a 68010 or
; later, and reads MONST2.INF (its 8 settings bytes) at its first start; the same 8 bytes at settings can be
; patched into the file.
;
; The screen is a title line and up to five windows: 1 registers, 2 disassembly (locked to the PC), 3 memory,
; and windows 4 and 5 made by splitting 2 or 3 (Alt-S).  Tab or Alt and a digit picks the current window, the
; cursor keys scroll it, Alt-Z shows it full screen.  The window commands are Alt-A address, Alt-B breakpoint,
; Alt-E edit (memory in hex or characters, registers), Alt-F full height, Alt-L lock to a register, Alt-O
; evaluate, Alt-P print, Alt-R registers, Alt-S split, Alt-T type (window 4: disassembly, memory, source).
;
; The commands: A load a source file, B load a binary file, D directory, G search (bytes, words, longs, text,
; or an instruction's text), H history, I copy, L list the symbols, M window address, N find next, O evaluate,
; P disassemble to the printer or a file (with labels and data areas), Q and T read and write a port, R run
; (Go, Until a condition, Instructions, Slow, with Watch), S save binary, U run until an address, V view the
; program's screen, W fill; Control-A step over, -B toggle a breakpoint, -C quit, -D BDOS breakpoint, -E
; re-install the exceptions, -K kill the breakpoints, -L load a program, -O switch MonST's resolution, -P
; preferences, -R run, -S skip, -T interpret, -W/-Y/-Z single step; Help shows the program's areas and the
; breakpoints; Alternate-Undo resets.
;
; Breakpoints are ILLEGAL instructions: plain (stopping the nth time), counters, permanent, or conditional on
; an expression.  The expressions take registers, symbols, $ % @ \ numbers and 'text', {address}.size and the
; usual operators.  A program is loaded with Pexec 3 and run with Pexec 4, its symbols relocated and hashed;
; one assembled by GenST into memory (its parent's command line says AMPM) is run from there.  Alternate-Help
; with both Shift keys stops a running program, through the screen dump vector and the 200 Hz timer.
;
; Some things in it look unfinished:
;   - find_cookie and xbios are never called, and there are a few bytes of an older routine at $471d.
;   - The preferences are written with "pea $8.w" as Fwrite's length: 8 bytes, not the bus error vector.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$0577  start-up, the settings, the keyboard, the address checks
;   $0578-$1ec3  the command loop and the commands
;   $1ec4-$22c7  loading and running programs
;   $22c8-$2bd5  the windows' contents: memory, registers, disassembly, source code
;   $2bd6-$35ef  numbers, the expression evaluator and the symbols
;   $35f0-$41fb  file calls, the screen drivers, output, the line editor, window handling
;   $41fc-$4729  the messages and texts
;   $472a-$563f  the disassembler, with its opcode and mnemonic tables
;   $5640-$5d69  breakpoints, interpreting, history, prompts, the screens, the vectors
;   $5d6a-$6281  the exception handlers, running the program and the hooks
;
;=======================================================================

basepage	equ	$0                      ; MonST's basepage
reg_d	equ	$4                              ; the program's registers: d0-d7
reg_a	equ	$24                             ; a0-a6
reg_usp	equ	$40                             ; a7 in user mode
reg_ssp	equ	$44                             ; a7 in supervisor mode
reg_sr	equ	$48                             ; the status register, in the low word
reg_pc	equ	$4c                             ; the program counter (the ROM's reset address at the start)
prog_basepage	equ	$50                     ; the loaded program's basepage
prog_text	equ	$54                     ; the loaded program's text, from its basepage
prog_data	equ	$5c                     ; its data
prog_bss	equ	$64                     ; its BSS
prog_end	equ	$6c                     ; its end
font_headers	equ	$70                     ; the Line-A font headers
screen	equ	$74                             ; MonST's own screen, 256 byte aligned
prog_screen	equ	$78                     ; the program's screen address
prog_screen_now	equ	$7c                     ; its video base, read when MonST's screen goes on
colour_background	equ	$80             ; palette 0 at the start
colour_text	equ	$82                     ; the text colour at the start
prog_colour0	equ	$84                     ; the program's colours 0 and 1
prog_colour1	equ	$86
screen_mode	equ	$88                     ; the resolution at the start
prog_mode	equ	$89                     ; the program's screen mode
old_vectors	equ	$8a                     ; the vectors MonST took over
old_gemdos	equ	$e6                     ; the old GEMDOS handler
old_scr_dump	equ	$ea                     ; the old screen dump vector
old_timer	equ	$ee                     ; the old 200 Hz timer handler
phystop	equ	$f2                             ; the top of memory
title_height	equ	$f6                     ; the title line's height in pixels
current_window	equ	$f8                     ; the window the keys work on, 0 for none
caps_table	equ	$fc                     ; the keyboard's caps lock table
full_layout	equ	$100                    ; the full screen window's position and size
split_height	equ	$10a                    ; the lines a split window takes
input_width	equ	$10c                    ; the input field's width
layout_window_4	equ	$10e                    ; window 4's position and size
layout_window_5	equ	$116                    ; window 5's position and size
printer	equ	$11e                            ; nonzero: a printer is configured
output_on	equ	$120                    ; negative: the output goes to the printer or a file
relative_offsets	equ	$121            ; relative offsets
ignore_case	equ	$122                    ; ignore case in symbols
no_cartridge	equ	$123                    ; nonzero: leave the cartridge out of the memory checks
split_flags	equ	$124                    ; bit 0: window 4 open, bit 1: window 5 open
symbols	equ	$126                            ; the program's symbol table, 0 for none
operator_stack	equ	$12a                    ; the evaluator's operators: a count, then words
value_stack	equ	$13e                    ; the evaluator's values: a count, then longs
eval_error	equ	$166                    ; the evaluator's error number
eval_check_only	equ	$167                    ; nonzero: do not read memory
symbol_length	equ	$168                    ; the symbol length
prog_loaded	equ	$16a                    ; nonzero: a program is loaded
break_request	equ	$16b                    ; nonzero: Alternate-Help asked to stop the program
monst_running	equ	$16c                    ; nonzero: MonST (not the program) is running
message_shown	equ	$16d                    ; nonzero: the title window shows a message
screen_timer_on	equ	$16e                    ; the screen timer
follow_traps	equ	$16f                    ; follow traps
run_mode	equ	$170                    ; 0, or 1 slow, 2 until, 3 a count
watch	equ	$171                            ; watch while running slowly
screen_timer	equ	$172                    ; ticks before the program's screen goes on, -1 off
bdos_breakpoint	equ	$174                    ; the GEMDOS call to stop at, -1 none
input_column	equ	$176                    ; the input field's column
ea_count	equ	$178                    ; bit 0: an effective address worked out
ea_two	equ	$179                            ; nonzero: two effective addresses
ea_size	equ	$17a                            ; the operand size
ea_address	equ	$17c                    ; the instruction's effective address
ea_address2	equ	$180                    ; and the second one
source_start	equ	$184                    ; the source file's text
source_end	equ	$188                    ; and its end
source_from_editor	equ	$18c            ; the source window's file: from the editor (negative: ends with the
                                                ;   program)
xref_pass	equ	$18d                    ; the disassembly's label pass: 1 the first, -1 the second
xref_start	equ	$18e                    ; the label list
xref_end	equ	$192                    ; and its end, 0 for none
disasm_start	equ	$196                    ; the range to disassemble
disasm_end	equ	$19a
listing_file	equ	$19e                    ; the listing's file handle, 0 for the printer
output_pointer	equ	$1a0                    ; the output buffer's fill position
label_name	equ	$1a4                    ; a made-up label's name for the listing
run_count	equ	$1b0                    ; the instruction count for R I
breakpoints	equ	$1b4                    ; 8 breakpoints, $48 bytes each: address, word, type, count, condition
stepped_breakpoint	equ	$3f4            ; the breakpoint being stepped over
stepped_trace	equ	$3f8                    ; the trace bit before it
history	equ	$3fa                            ; 5 register snapshots
history_next	equ	$56c                    ; the next snapshot to fill
interpret_buffer	equ	$570            ; the instruction being interpreted, with nops and ILLEGAL
interpret_return	equ	$57c            ; where to go on after it
temp_break	equ	$580                    ; the temporary breakpoint after a TRAP
temp_break_word	equ	$584                    ; the word it replaced
temp_break_entry	equ	$586            ; the breakpoint to put back afterwards
old_ssp	equ	$58a                            ; the supervisor stack at the start
bios_caller	equ	$58e                    ; the return address round a BIOS call
old_savptr	equ	$592                    ; the BIOS save pointer
bios_save	equ	$5c6                    ; MonST's BIOS register save area
rom_start	equ	$5fa                    ; the first ROM range
rom_end	equ	$5fe
rom2_start	equ	$602                    ; the second ROM range (the cartridge, or the ROM when the cartridge is
                                                ;   lower)
rom2_end	equ	$606
symbol_hash	equ	$60a                    ; the symbols' hash table
symbol_hash_size	equ	$60e            ; its size
listing_mode	equ	$612                    ; nonzero: the disassembly is for a listing
screen_area	equ	$614                    ; the whole screen as an area to clear
window_title	equ	$634                    ; the title window
window_1	equ	$682                    ; window 1: registers
window_2	equ	$6d0                    ; window 2: disassembly
window_3	equ	$71e                    ; window 3: memory
window_4	equ	$76c                    ; window 4
window_5	equ	$7ba                    ; window 5
window_full	equ	$808                    ; the full screen window (zoom, help and the like)
window_prompt	equ	$856                    ; the prompt window
reg_m0	equ	$8a4                            ; the M0 and M1 registers; M2-M5 are windows 2-5's addresses
reg_m1	equ	$8a8
reg_m6	equ	$8ac                            ; M6-M9
line_buffer	equ	$8bc                    ; the disassembly line, and the program header when loading
arguments	equ	$90c                    ; the program's command line, a counted string
data_areas	equ	$948                    ; the listing's data areas, 10 bytes each (also a line buffer)
until_condition	equ	$986                    ; the R U condition
search_length	equ	$9c4                    ; the search pattern's length
search_ignore_case	equ	$9c5
search_align	equ	$9c6                    ; the search step: 1, 2 or 4
search_kind	equ	$9c7                    ; B, W, L, T or I
search_pattern	equ	$9c8                    ; the pattern
relative_registers	equ	$a40            ; bit n: show d(An) as a symbol
address_offset	equ	$a42                    ; added to branch targets
output_buffer	equ	$a46                    ; the listing's file buffer; also the upper case name
monst_stack	equ	$ef6                    ; MonST's stack
prog_stack	equ	$f46                    ; the program's stack at the start
monst_stack_top	equ	$10d6                   ; the stack MonST starts with

	section	text

;------------------------------------------------------------------------------
; The program starts here: over the settings and the name to main.
;------------------------------------------------------------------------------
start:	; from: timer_hook
	bra.s	main                            ; over the settings
settings_magic:
	dc.w	$4150                           ; 'AP': the settings below can be patched in the file

;------------------------------------------------------------------------------
; The settings, 8 bytes: patched into the file by the installer, or read from MONST2.INF at the first start.
;------------------------------------------------------------------------------
settings:	; from: show_cursor_here
	dc.b	$00                             ; 0: MONST2.INF not read yet
default_settings:
	dc.b	$00,$ff,$00,$00,$16,$ff,$00     ; follow traps, relative offsets, ignore case, the symbol length (a
                                                ;   word), screen timer, ignore cartridge
title:
	dc.b	'MONST2(C) HiSoft 1991',0       ; "MONST2(C) HiSoft 1991"
main:	; from: start
	movea.l	4(sp),a0                        ; the basepage
	movea.l	$18(a0),a6                      ; a6 = the variables, past the program (its BSS)
	lea	monst_stack_top(a6),sp          ; the stack in them
	movea.l	a0,a4                           ; a4 = the basepage
	lea	vars_address(pc),a1             ; the variables' address
	move.l	a6,(a1)                         ; kept for the exception handlers
	move.l	$c(a0),d0                       ; text length
	add.l	$14(a0),d0                      ; + data
	add.l	$1c(a0),d0                      ; + BSS
	addi.l	#$11da,d0                       ; + the variables
	move.l	d0,-(sp)                        ; Mshrink(0, basepage, length)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
	tst.l	d0                              ; all right?
	bne.w	quit_no_memory                  ; no: quit
	movea.l	a6,a0                           ; clear the variables
	move.w	#$2f5,d0                        ; $2f6 longs
clear_vars:
	clr.l	(a0)+
	dbra	d0,clear_vars
	move.l	a4,basepage(a6)                 ; the basepage
	st	ea_count(a6)
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#4,sp
	cmp.w	#$3,d0                          ; high resolution or lower?
	bcs.s	check_settings                  ; yes
	lea	text_unrecognised_screen_mode(pc),a3 ; "Unrecognised screen mode"
	bsr.w	print_wait                      ; print and wait for a key
	moveq	#10,d0                          ; exit code 10
	bra.w	quit                            ; quit
check_settings:
	lea	settings(pc),a0                 ; MONST2.INF read already?
	tst.b	(a0)
	bne.s	use_settings                    ; yes
	st	(a0)                            ; not again
	lea	name_monst_inf(pc),a0           ; "MONST2.INF"
	bsr.w	open_file                       ; open it
	bne.s	use_settings                    ; not there: the settings as they are
	moveq	#8,d4                           ; 8 bytes
	lea	settings(pc),a0                 ; into the settings
	bsr.w	read_file                       ; read
	bsr.w	close_file                      ; close
use_settings:
	lea	default_settings(pc),a0         ; the settings
	move.b	(a0)+,follow_traps(a6)          ; follow traps
	move.b	(a0)+,relative_offsets(a6)      ; relative offsets
	move.b	(a0)+,ignore_case(a6)           ; ignore case
	move.w	(a0)+,symbol_length(a6)         ; the symbol length
	move.b	(a0)+,screen_timer_on(a6)       ; screen timer
	move.b	(a0)+,no_cartridge(a6)          ; ignore cartridge
	move.l	#$7e00,d0                       ; $7e00 bytes for MonST's screen
	bsr.w	malloc                          ; Malloc
	bne.s	set_screen                      ; got it
quit_no_memory:
	move.w	#$ffd9,-(sp)                    ; Pterm(-39): not enough memory
	move.w	#$4c,-(sp)
	trap	#1                              ; Pterm

;------------------------------------------------------------------------------
; Print the string at a3 with Bconout to the console, then wait for a key.
;------------------------------------------------------------------------------
print_wait:	; from: settings
	move.b	(a3)+,d0                        ; a character
	beq.s	print_wait_key                  ; the end?
	move.w	d0,-(sp)                        ; Bconout(2, character)
	move.l	#$30002,-(sp)
	trap	#13                             ; Bconout
	addq.l	#6,sp
	bra.s	print_wait                      ; the next
print_wait_key:
	move.l	#$20002,-(sp)                   ; Bconin(2)
	trap	#13                             ; Bconin
	addq.l	#4,sp
	rts
set_screen:	; from: settings
	clr.b	d0                              ; to a 256 byte boundary
	addi.l	#$100,d0
	move.l	d0,screen(a6)                   ; MonST's screen
	clr.l	prog_screen_now(a6)
	pea	monst_stack(a6)                 ; Super(the variables' stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	move.l	d0,old_ssp(a6)                  ; the old supervisor stack
	tst.w	$59e.w                          ; _longframe, a 68010 or later?
	beq.s	check_printer                   ; no
	lea	text_needs_68000(pc),a3         ; "This version of MonST only works on a 68000 processor! ..."
	bsr.s	print_wait                      ; print and wait
check_printer:
	clr.w	printer(a6)                     ; no printer
	move.l	#$21ffff,-(sp)                  ; Setprt(-1)
	trap	#14                             ; Setprt
	addq.l	#4,sp
	btst	#$4,d0                          ; a printer configured?
	beq.s	read_system                     ; no
	addq.w	#1,printer(a6)                  ; yes
read_system:
	move.l	$4.w,reg_pc(a6)                 ; the reset address: the ROM's start
	moveq	#-1,d0                          ; Keytbl(-1, -1, -1)
	move.l	d0,-(sp)
	move.l	d0,-(sp)
	move.l	d0,-(sp)
	move.w	#$10,-(sp)
	trap	#14                             ; Keytbl
	lea	$e(sp),sp
	movea.l	d0,a0                           ; the key tables
	move.l	8(a0),caps_table(a6)            ; the caps lock table
	move.l	$42e.w,phystop(a6)              ; phystop, the top of memory
	move.b	$ffff8260.w,d0                  ; shift mode, the screen mode
	andi.w	#$3,d0
	move.b	d0,screen_mode(a6)              ; kept
	move.w	$ffff8240.w,colour_background(a6) ; palette 0, the background colour
	move.b	mode_colour_index(pc,d0.w),d0   ; the text colour's index for the mode
	lea	$ffff8240.w,a0                  ; palette 0, the palette
	move.w	0(a0,d0.w),colour_text(a6)      ; the text colour
	bra.s	check_environment               ; on
mode_colour_index:
	dc.w	$1e06,$0202,$1e02,$021e         ; byte offsets of the palette entry the text is drawn in, for low,
                                                ;   medium and high resolution
str_nocartridge:
	dc.b	'NOCARTRIDGE=',0                ; "NOCARTRIDGE=": an environment variable that leaves the cartridge out
                                                ;   of the memory checks
	dc.b	$00
check_environment:
	lea	str_nocartridge(pc),a1          ; "NOCARTRIDGE="
	movea.l	basepage(a6),a2                 ; the basepage
	bsr.w	find_environment                ; in the environment?
	seq	d1                              ; yes: d1 set
	or.b	no_cartridge(a6),d1             ; or the setting
	move.b	d1,no_cartridge(a6)
	bsr.w	rom_ranges                      ; the ROM and cartridge ranges
	bsr.w	install_vectors
	move.b	screen_mode(a6),d7              ; the screen mode
	bsr.w	init_screen
	move.w	#$4,input_column(a6)
	bsr.w	monst_screen
	bsr.w	clear_breakpoints
	bsr.w	clear_history
	move.b	screen_mode(a6),d7              ; the screen mode
	bsr.w	open_windows                    ; open the windows
	movea.l	basepage(a6),a0                 ; the basepage
	movea.l	$24(a0),a0                      ; its parent's basepage
	cmpi.l	#$414d504d,$80(a0)              ; 'AMPM' at its command line: started by the editor?
	beq.s	from_editor                     ; yes
	bsr.w	redraw_windows
	pea	command_loop(pc)                ; the command loop afterwards
	movea.l	basepage(a6),a0                 ; the basepage
	moveq	#0,d0
	lea	$80(a0),a0                      ; the command line
	move.b	(a0)+,d0                        ; its length
	beq.w	cmd_load_program                ; none: no program
	clr.b	0(a0,d0.w)                      ; ended
skip_spaces:
	cmpi.b	#$20,(a0)+                      ; past the spaces
	beq.s	skip_spaces
	subq.l	#1,a0                           ; back to the first character
	movea.l	a0,a3                           ; a3 = the program's name
	lea	arguments(a6),a4                ; the arguments, a counted string
	clr.w	(a4)                            ; none yet
	lea	1(a4),a2                        ; its text
find_arguments:
	move.b	(a0)+,d1                        ; a character
	beq.w	load_program                    ; the end: load the program
	cmp.b	#$20,d1                         ; a space?
	bne.s	find_arguments                  ; no
	clr.b	-$1(a0)                         ; the name ends here
copy_arguments:
	move.b	(a0)+,d1                        ; a character
	beq.w	load_program                    ; the end: load the program
	move.b	d1,(a2)+                        ; copied
	addq.b	#1,(a4)                         ; counted
	bra.s	copy_arguments                  ; the next
from_editor:
	movea.l	$84(a0),a4                      ; the program the editor assembled
	bra.w	run_from_editor                 ; run it

;------------------------------------------------------------------------------
; Work out the ROM's range from the reset address ($FC0000-$FF0000 for a 192 K TOS, else 512 K from its
; 64 K boundary) and the cartridge's ($FA0000-$FC0000) unless d1 is set; the lower range goes first.
;------------------------------------------------------------------------------
rom_ranges:	; from: print_wait, show_cursor_here
	move.l	$4.w,d0                         ; the reset address
	andi.l	#$fc0000,d0
	cmp.l	#$fc0000,d0                     ; the 192 K TOS?
	beq.s	rom_ranges_192k                 ; yes
	move.l	$4.w,d0                         ; the reset address
	andi.l	#$ff0000,d0                     ; its 64 K boundary
	move.l	d0,rom_start(a6)                ; the ROM's start
	addi.l	#$80000,d0                      ; + 512 K
	move.l	d0,rom_end(a6)                  ; its end
	bra.s	cartridge_range
rom_ranges_192k:
	move.l	#$fc0000,rom_start(a6)          ; the ROM's start
	move.l	#$ff0000,rom_end(a6)            ; its end
cartridge_range:
	tst.b	d1                              ; no cartridge?
	beq.s	cartridge_below
	clr.l	rom2_start(a6)                  ; no range
	clr.l	rom2_end(a6)
	bra.s	rom_ranges_done
cartridge_below:
	movea.l	#$fa0000,a0                     ; the cartridge's start
	movea.l	#$fc0000,a1                     ; and end
	cmpa.l	rom_start(a6),a0                ; below the ROM?
	blt.s	cartridge_first                 ; no
	movem.l	a0-a1,rom2_start(a6)            ; yes: the second range
	bra.s	rom_ranges_done
cartridge_first:
	move.l	rom_start(a6),rom2_start(a6)    ; the ROM second
	move.l	rom_end(a6),rom2_end(a6)
	movem.l	a0-a1,rom_start(a6)             ; the cartridge first
rom_ranges_done:
	rts
quit_monst:	; from: command_loop
	bsr.w	program_screen
	moveq	#-32,d0                         ; exit code -32
	tst.b	prog_loaded(a6)                 ; ?
	bne.s	quit
restore_and_quit:	; from: run_from_editor
	bsr.w	restore_vectors
	move.l	old_ssp(a6),-(sp)               ; Super(the old stack): back to user mode
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	moveq	#0,d0                           ; exit code 0
quit:	; from: settings
	sf	monst_running(a6)
	move.w	d0,-(sp)                        ; Pterm(d0)
	move.w	#$4c,-(sp)
	trap	#1                              ; Pterm

;------------------------------------------------------------------------------
; Never called: look for the cookie d3 in the cookie jar; Z set and d0 = its value when found.
;------------------------------------------------------------------------------
find_cookie:
	movea.l	$5a0.w,a3                       ; _p_cookies, the cookie jar
	move.l	a3,d0
	beq.s	find_cookie_none                ; none
find_cookie_loop:
	move.l	(a3)+,d0                        ; a cookie
	beq.s	find_cookie_none                ; the end
	cmp.l	d0,d3                           ; this one?
	beq.s	find_cookie_found               ; yes
	addq.l	#4,a3                           ; past its value
	bra.s	find_cookie_loop                ; the next
find_cookie_found:
	move.l	(a3)+,d0                        ; its value
	cmp.b	d0,d0                           ; Z set
	rts
find_cookie_none:
	moveq	#-1,d0                          ; Z clear

;------------------------------------------------------------------------------
; Look for the name at a1 among the environment strings of the basepage at a2; Z set when found.
;------------------------------------------------------------------------------
find_environment:	; from: print_wait
	movea.l	$2c(a2),a0                      ; the environment
	tst.b	(a0)
	bne.s	find_environment_next
	tst.b	1(a0)
	beq.s	find_environment_none
	addq.l	#1,a0
find_environment_next:
	tst.b	(a0)                            ; the end?
	beq.s	find_environment_none           ; yes: not there
	movem.l	a0-a1,-(sp)
find_environment_compare:
	move.b	(a1)+,d0                        ; a character of the name
	beq.s	find_environment_found          ; all of it: found
	cmp.b	(a0)+,d0                        ; the same?
	beq.s	find_environment_compare        ; yes: on
	bra.s	find_environment_skip           ; no
find_environment_found:
	movem.l	(sp)+,d0/a1
	moveq	#0,d0                           ; Z set
	rts
find_environment_skip:
	movem.l	(sp)+,a0-a1
find_environment_end:
	tst.b	(a0)+                           ; to the next string
	bne.s	find_environment_end
	bra.s	find_environment_next
find_environment_none:
	moveq	#-1,d0                          ; Z clear
	rts

;------------------------------------------------------------------------------
; Z set when both Shift keys are held.
;------------------------------------------------------------------------------
shift_keys_held:	; from: exc_trace_step
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	bsr.w	bios
	addq.l	#4,sp
	andi.b	#$3,d0                          ; the Shift keys
	cmp.b	#$3,d0                          ; both?
	rts

;------------------------------------------------------------------------------
; Wait for a key to be pressed, throwing away any already waiting.
;------------------------------------------------------------------------------
wait_key:	; from: flush_get_key, hex_column_offset
	movem.l	d0-d2/a0-a2,-(sp)               ; keep the registers
wait_key_loop:
	move.l	#$10002,-(sp)                   ; Bconstat(2)
	bsr.w	bios
	addq.l	#4,sp
	addq.b	#1,d0                           ; one waiting?
	bne.s	wait_key_done                   ; no: done
	move.l	#$20002,-(sp)                   ; yes: Bconin(2), thrown away
	bsr.w	bios
	addq.l	#4,sp
	bra.s	wait_key_loop
wait_key_done:
	movem.l	(sp)+,d0-d2/a0-a2               ; the registers back
	rts

;------------------------------------------------------------------------------
; Z set when Esc is waiting; any other key is read and thrown away.
;------------------------------------------------------------------------------
check_escape:	; from: search_bytes, search_instruction, flush_output_buffer
	movem.l	d0-d2/a0-a2,-(sp)               ; keep the registers
	move.w	#$2,-(sp)                       ; Bconstat(2)
	move.w	#$1,-(sp)
	bsr.w	bios
	addq.l	#4,sp
	addq.b	#1,d0                           ; a key?
	bne.s	check_escape_done               ; no
	move.l	#$20002,-(sp)                   ; Bconin(2)
	bsr.w	bios
	addq.l	#4,sp
	cmp.b	#$1b,d0                         ; Esc?
check_escape_done:
	movem.l	(sp)+,d0-d2/a0-a2               ; the registers back
	rts

;------------------------------------------------------------------------------
; Throw away the waiting keys, then get one.
;------------------------------------------------------------------------------
flush_get_key:	; from: window_evaluate, cmd_view, cmd_query_port, cmd_symbols, cmd_history, show_message
	bsr.s	wait_key                        ; throw away the waiting keys

;------------------------------------------------------------------------------
; Wait for a key: d1 = its code (an ASCII code, or the scan code in the high byte with the ASCII code of the
; caps table for Alt keys), d0 nonzero for an Alt key.  A cursor key held with others waiting is taken as one.
;------------------------------------------------------------------------------
get_key:	; from: command_loop, zoom_window, cmd_search, ask_yes_no, show_cursor_here, cmd_run_mode, 4 more
	movem.l	d0/d2/d6-d7/a0-a2,-(sp)         ; keep the registers
get_key_loop:
	move.l	#$20002,-(sp)                   ; Bconin(2)
	bsr.w	bios
	addq.l	#4,sp
	bsr.w	key_code                        ; made into d1
	cmp.w	#$4d00,d1                       ; cursor right?
	beq.s	get_key_cursor
	cmp.w	#$4b00,d1                       ; cursor left?
	beq.s	get_key_cursor
	cmp.w	#$5000,d1                       ; cursor down?
	beq.s	get_key_cursor
	cmp.w	#$4800,d1                       ; cursor up?
	beq.s	get_key_cursor
	cmp.w	#$5032,d1                       ; shift cursor down?
	beq.s	get_key_cursor
	cmp.w	#$4838,d1                       ; shift cursor up?
	bne.s	get_key_done                    ; no: done
get_key_cursor:
	move.w	d1,d7                           ; keep the key
	move.b	d0,d6
	move.l	#$10002,-(sp)                   ; Bconstat(2)
	bsr.w	bios
	addq.l	#4,sp
	addq.b	#1,d0                           ; another waiting?
	beq.s	get_key_loop                    ; yes: take that one
	move.b	d6,d0                           ; no: this one
	move.w	d7,d1
get_key_done:
	tst.b	d0                              ; the flags from d0
	movem.l	(sp)+,d0/d2/d6-d7/a0-a2         ; the registers back
	rts

;------------------------------------------------------------------------------
; Make Bconin's d0 into a key code in d1: the ASCII code if there is one, else the scan code in the high byte;
; Alt and a letter or a digit give the caps table's character and d0 = -1.
;------------------------------------------------------------------------------
key_code:	; from: get_key
	moveq	#0,d1
	move.b	d0,d1                           ; the ASCII code
	beq.s	key_code_scan                   ; none
	move.w	d1,-(sp)                        ; the scan code
	swap	d0
	move.b	d0,(sp)                         ; in the high byte
	move.w	(sp)+,d1                        ; d1 = scan and ASCII codes
key_code_plain:
	moveq	#0,d0                           ; d0 = 0
	rts
key_code_scan:
	swap	d0                              ; the scan code
	cmp.b	#$10,d0                         ; below Q?
	bcs.s	key_code_scan_only              ; yes: as it is
	cmp.b	#$33,d0                         ; M or above?
	bcc.s	key_code_alt_digit              ; yes
	andi.w	#$ff,d0
	movea.l	caps_table(a6),a0               ; the caps table
	move.b	0(a0,d0.w),d1                   ; its character
	moveq	#-1,d0                          ; an Alt key
	rts
key_code_scan_only:
	move.w	d1,-(sp)                        ; the scan code in the high byte
	move.b	d0,(sp)
	move.w	(sp)+,d1
	bra.s	key_code_plain
key_code_alt_digit:
	cmp.b	#$78,d0                         ; below Alt 1?
	bcs.s	key_code_scan_only              ; yes
	cmp.b	#$82,d0                         ; above Alt =?
	bcc.s	key_code_scan_only              ; yes
	move.b	d0,d1                           ; Alt 1-9, 0, -, =
	subi.b	#$47,d1                         ; made into '1'..'='
	moveq	#-1,d0                          ; an Alt key
	rts

;------------------------------------------------------------------------------
; Open the title window, from the layout at a4.
;------------------------------------------------------------------------------
open_title_window:	; from: open_windows
	lea	window_title(a6),a3             ; the title window
	movem.w	(a4)+,d0-d3                     ; its position and size
	lea	text_title(pc),a2               ; "MonST2.13 (C)..."
	move.b	#$0,$3e(a3)                     ; the registers
	clr.b	$46(a3)
	bra.w	open_window                     ; open it

;------------------------------------------------------------------------------
; Open window 1, the registers, from the layout at a4.
;------------------------------------------------------------------------------
open_window_1:	; from: open_windows
	lea	window_1(a6),a3                 ; window 1
	movem.w	(a4)+,d0-d3                     ; its position and size
	lea	text_registers(pc),a2           ; "Registers"
	move.b	#$2,$3e(a3)
	move.b	#$1,$46(a3)
	bsr.w	open_window                     ; open it
	bra.w	set_window_type                 ; draw it

;------------------------------------------------------------------------------
; Open window 2, a disassembly at the PC, from the layout at a4.
;------------------------------------------------------------------------------
open_window_2:	; from: open_windows
	moveq	#2,d4                           ; window 2
	lea	window_2(a6),a3
open_disassembly_window:	; from: window_split
	movem.w	(a4)+,d0-d3                     ; its position and size
	lea	text_disassembly(pc),a2         ; "Disassembly"
	move.b	#$3,$3e(a3)                     ; a disassembly
	move.b	d4,$46(a3)
	bsr.w	open_window                     ; open it
	move.l	reg_pc(a6),$42(a3)              ; at the PC
	bra.w	set_window_type                 ; draw it

;------------------------------------------------------------------------------
; Open window 3, a memory dump at 0, from the layout at a4.
;------------------------------------------------------------------------------
open_window_3:	; from: open_windows
	lea	window_3(a6),a3                 ; window 3
	moveq	#3,d4
open_memory_window:	; from: window_split
	movem.w	(a4)+,d0-d3                     ; its position and size
	lea	text_memory(pc),a2              ; "Memory"
	move.b	#$1,$3e(a3)                     ; a memory dump
	move.b	d4,$46(a3)
	clr.l	$42(a3)                         ; at 0
	bsr.w	open_window                     ; open it
	bra.w	set_window_type                 ; draw it

;------------------------------------------------------------------------------
; Open the full screen window, its title at a2, on a cleared screen.
;------------------------------------------------------------------------------
open_full_window:	; from: cmd_symbols, cmd_help, cmd_history
	move.l	a2,-(sp)
	lea	screen_area(a6),a3              ; the whole screen
	bsr.w	clear_window
	lea	window_full(a6),a3              ; the full screen window
	movem.w	full_layout(a6),d0-d4           ; its position and size
	sub.w	title_height(a6),d1
	movea.l	(sp)+,a2
	bsr.w	open_window                     ; open it
	st	d7
	st	d4
	bra.w	draw_frame                      ; draw it

;------------------------------------------------------------------------------
; Z set when a2 is an address that can be read without a bus error: in the RAM below 4 M, the ROM or the
; cartridge.  d0 = 0 then, -1 when not.
;------------------------------------------------------------------------------
check_address:                                  ; from: cmd_trace_rom, check_runnable, cmd_disassemble, memory_line,
                                                ;   memory_hex, next_instruction, 5 more
	move.l	a2,d0
	andi.l	#$ff000000,d0                   ; over 24 bits?
	bne.s	check_address_bad               ; yes: no
	cmpa.l	#$400000,a2                     ; below 4 M?
	bcs.s	check_address_good              ; yes
	cmpa.l	rom_start(a6),a2                ; below the first ROM range?
	bcs.s	check_address_bad               ; yes: no
	cmpa.l	rom_end(a6),a2                  ; inside it?
	bcs.s	check_address_good              ; yes
	cmpa.l	rom2_start(a6),a2               ; below the second?
	bcs.s	check_address_bad               ; yes: no
	cmpa.l	rom2_end(a6),a2                 ; inside it?
	bcs.s	check_address_good              ; yes
check_address_bad:
	moveq	#-1,d0                          ; no
	rts
check_address_good:
	moveq	#0,d0                           ; yes
	rts
	andi.b	#$fe,d0                         ; never reached

;------------------------------------------------------------------------------
; Z set when d0 is an address in RAM between 8 and phystop.
;------------------------------------------------------------------------------
check_ram:	; from: cmd_disassemble, hex_column_offset, set_breakpoint
	movem.l	d0,-(sp)
	andi.l	#$ff000000,d0                   ; over 24 bits?
	movem.l	(sp)+,d0
	bne.s	check_ram_bad                   ; yes: no
	cmp.l	#$8,d0                          ; below 8?
	bcs.s	check_ram_bad                   ; yes: no
	cmp.l	phystop(a6),d0                  ; below phystop?
	bcc.s	check_ram_bad                   ; no
	cmp.b	d0,d0                           ; yes: Z set
	rts
check_ram_bad:
	andi.b	#$0,ccr                         ; Z clear
	rts

;------------------------------------------------------------------------------
; Clear the title window if it shows a message.
;------------------------------------------------------------------------------
clear_title_window:	; from: command_loop
	tst.b	message_shown(a6)               ; a message?
	beq.s	clear_message_done              ; no

;------------------------------------------------------------------------------
; Clear the message in the title window and draw it again.
;------------------------------------------------------------------------------
clear_message:	; from: cmd_find_next, search_found
	movem.l	d1/a3,-(sp)
	lea	window_title(a6),a3             ; the title window
	bsr.w	clear_window                    ; draw it
	clr.l	$16(a3)
	sf	message_shown(a6)               ; no message
	movem.l	(sp)+,d1/a3
clear_message_done:	; from: clear_title_window
	rts

;------------------------------------------------------------------------------
; MonST's command loop: a key; Tab picks the next window, Control-C quits, Help shows the help, Alt keys are
; window commands, letters and control keys go through command_table, and the rest to the current window.
;------------------------------------------------------------------------------
command_loop:	; from: print_wait, zoom_window, cmd_help, undo_reset, relocate_symbols, stop_program
	bsr.w	get_key                         ; a key
	bmi.s	command_alt                     ; an Alt key
	bsr.s	clear_title_window              ; clear a message
command_key:
	cmp.b	#$9,d1                          ; Tab?
	beq.s	command_next_window             ; yes: the next window
	cmp.b	#$3,d1                          ; Control-C?
	beq.w	quit_monst                      ; yes: quit
	cmp.w	#$6200,d1                       ; Help?
	beq.w	cmd_help                        ; yes
	cmp.w	#$710e,d1                       ; Undo?
	beq.w	undo_reset                      ; yes
	move.b	d1,d0
	cmp.b	#$41,d0                         ; a letter?
	bcs.s	command_find                    ; no
	andi.b	#$df,d0                         ; upper case
command_find:
	lea	command_table(pc),a0            ; the command table
command_find_loop:
	move.w	(a0)+,d2                        ; a key
	beq.s	command_window_key              ; the end
	cmp.b	d0,d2                           ; this one?
	beq.s	command_run                     ; yes
	addq.w	#2,a0                           ; past its offset
	bra.s	command_find_loop               ; the next
command_run:
	adda.w	(a0),a0                         ; to the routine
	movea.l	current_window(a6),a3           ; the current window
	jsr	-$2(a0)                         ; run it
	bra.s	command_loop                    ; the next key
command_window_key:
	move.l	current_window(a6),d0           ; the current window
	beq.s	command_loop                    ; none
	movea.l	d0,a3
	bsr.w	window_keys                     ; its keys
	beq.s	command_loop                    ; taken
	bra.s	command_key                     ; a new key from it
command_next_window:
	bsr.w	next_window                     ; the next window
	bra.s	command_loop
command_alt:
	bsr.w	clear_title_window              ; clear a message
	move.l	current_window(a6),d0           ; the current window
	beq.s	command_loop                    ; none
	movea.l	d0,a3
	cmp.b	#$5a,d1                         ; Alt-Z?
	beq.s	zoom_window                     ; yes: zoom
	cmp.b	#$3a,d1                         ; Alt and a digit?
	bcs.s	command_select_window           ; yes: that window
	bsr.w	window_command                  ; a window command
	bra.w	command_loop
command_select_window:
	subi.b	#$30,d1                         ; the window's number
	bsr.w	select_window_number            ; make it current
	bra.w	command_loop

;------------------------------------------------------------------------------
; Alt-Z: show the current window full screen until Esc or Alt-Z again; its keys work meanwhile.
;------------------------------------------------------------------------------
zoom_window:	; from: command_loop
	move.l	a3,-(sp)                        ; the window
	lea	screen_area(a6),a3              ; the whole screen
	bsr.w	clear_window                    ; cleared
	lea	window_full(a6),a3              ; the full screen window
	movem.w	full_layout(a6),d0-d4           ; its layout
	movea.l	screen(a6),a0                   ; the screen
	bsr.w	open_window_area
	movea.l	(sp)+,a2                        ; the window
	lea	$20(a3),a0                      ; the full screen window's settings
	lea	$20(a2),a1                      ; from the window's
	moveq	#22,d0                          ; $2e bytes
zoom_copy:
	move.w	(a1)+,(a0)+
	dbra	d0,zoom_copy
	st	d7
	st	d4
	bsr.w	draw_frame                      ; its frame
	bsr.w	set_window_type                 ; its contents
	bsr.w	draw_window_contents            ; redraw
zoom_loop:
	bsr.w	get_key                         ; a key
	bmi.s	zoom_alt                        ; an Alt key
zoom_key:
	cmp.b	#$1b,d1                         ; Esc?
	beq.s	zoom_done                       ; yes: back
	bsr.s	window_keys                     ; the window's keys
	beq.s	zoom_loop                       ; taken
	bra.s	zoom_key
zoom_done:
	bsr.w	close_prompt                    ; back to the windows
	bra.w	command_loop
zoom_alt:
	cmp.b	#$5a,d1                         ; Alt-Z?
	beq.s	zoom_done                       ; yes: back
	bsr.w	window_command                  ; a window command
	bra.s	zoom_loop

;------------------------------------------------------------------------------
; The current window's own keys, through its handler table at $48(a3): cursor keys and Shift with them, and
; Space in the full screen window.  Z set (d1 = 0) when the key was taken; the handler's N flag asks for a
; redraw.
;------------------------------------------------------------------------------
window_keys:	; from: command_loop, zoom_window
	pea	window_keys_after(pc)           ; afterwards
	movea.l	$48(a3),a0                      ; the handlers
	cmp.w	#$4838,d1                       ; Shift cursor up?
	beq.s	window_key_page_up
	cmp.w	#$4800,d1                       ; cursor up?
	beq.s	window_key_up
	cmp.w	#$5000,d1                       ; cursor down?
	beq.s	window_key_down
	cmp.w	#$5032,d1                       ; Shift cursor down?
	beq.s	window_key_page_down
	cmp.w	#$4b00,d1                       ; cursor left?
	beq.s	window_key_left
	cmp.w	#$4d00,d1                       ; cursor right?
	beq.s	window_key_right
	tst.w	window_full+16(a6)              ; full screen?
	beq.s	window_keys_none                ; no
	cmp.b	#$20,d1                         ; Space?
	beq.s	window_key_page_down            ; yes: as Shift cursor down
window_keys_none:
	addq.l	#4,sp                           ; not taken
	moveq	#0,d1
	rts
window_key_page_down:
	jmp	6(a0)
window_key_page_up:
	jmp	4(a0)
window_key_up:
	jmp	8(a0)
window_key_down:
	jmp	$a(a0)
window_key_left:
	jmp	$c(a0)
window_key_right:
	jmp	$e(a0)
window_keys_after:
	bmi.s	window_keys_redraw              ; redraw?
	rts                                     ; no
window_keys_redraw:
	clr.l	$16(a3)
	movea.l	$48(a3),a0                      ; the handlers
	jsr	(a0)                            ; draw the window
	moveq	#0,d1                           ; taken
	rts

;------------------------------------------------------------------------------
; An Alt key command on the current window a3: A address, B breakpoint, E edit, F full height, L lock, O other
; display, P print, R registers, S split, T type.
;------------------------------------------------------------------------------
window_command:	; from: command_loop, zoom_window, cmd_help, hex_column_offset, cmd_history
	cmp.b	#$41,d1                         ; Alt-A?
	beq.s	window_address
	cmp.b	#$42,d1                         ; Alt-B?
	beq.w	window_breakpoint
	cmp.b	#$45,d1                         ; Alt-E?
	beq.w	window_edit
	cmp.b	#$46,d1                         ; Alt-F?
	beq.w	window_full_height
	cmp.b	#$4c,d1                         ; Alt-L?
	beq.w	window_lock
	cmp.b	#$4f,d1                         ; Alt-O?
	beq.w	window_evaluate
	cmp.b	#$50,d1                         ; Alt-P?
	beq.w	window_print
	cmp.b	#$52,d1                         ; Alt-R?
	beq.w	set_registers
	cmp.b	#$53,d1                         ; Alt-S?
	beq.w	window_split
	cmp.b	#$54,d1                         ; Alt-T?
	beq.w	window_type
window_command_done:	; from: window_address
	rts

;------------------------------------------------------------------------------
; Alt-A: a new start address for the window (a line number for a source window).
;------------------------------------------------------------------------------
window_address:	; from: window_command, command_table
	move.b	$3e(a3),d0                      ; its type
	cmp.b	#$2,d0                          ; registers?
	beq.s	window_command_done             ; yes: nothing to do
	cmp.b	#$4,d0                          ; source code?
	beq.s	window_goto_line                ; yes
	lea	text_window_start_address(pc),a0 ; "Window start address?"
	bsr.w	ask_address                     ; ask
	bne.s	window_command_done             ; cancelled
	move.l	d2,$42(a3)                      ; the window's address
	bra.w	draw_window_contents            ; redraw
window_goto_line:
	lea	text_goto_line(pc),a0           ; "Goto line?"
	bsr.w	ask_address                     ; ask
	bne.s	window_command_done             ; cancelled
	movea.l	source_start(a6),a0             ; the source
	movea.l	source_end(a6),a1               ; its end
	subq.l	#1,d2                           ; line 1?
	bmi.s	window_goto_end                 ; 0: the end
	beq.s	window_goto_line_set            ; yes: the start
	moveq	#13,d1                          ; Return
window_goto_line_loop:
	cmpa.l	a0,a1                           ; the end?
	beq.s	window_goto_end                 ; yes
	cmp.b	(a0)+,d1                        ; a line end?
	bne.s	window_goto_line_loop           ; no
	subq.l	#1,d2                           ; one line less
	bne.s	window_goto_line_loop
window_goto_line_set:
	move.l	a0,$42(a3)                      ; the window's address
	bra.w	draw_window_contents            ; redraw
window_goto_end:
	movea.l	source_end(a6),a2               ; the end
	move.l	#$ffff,d2
	add.w	$12(a3),d2                      ; back the window's height
window_goto_end_loop:
	bsr.w	source_line_back                ; a line back
	beq.s	window_goto_start               ; the start
	subq.w	#1,d2
	bne.s	window_goto_end_loop
	movea.l	a2,a0
	bra.s	window_goto_line_set
window_goto_start:
	movea.l	source_start(a6),a0             ; the start
	bra.s	window_goto_line_set

;------------------------------------------------------------------------------
; Alt-F: the window's height (registers: the windows below shrink to make room).
;------------------------------------------------------------------------------
window_full_height:	; from: window_command
	bsr.w	clear_window                    ; clear it
	bsr.w	other_font
	tst.w	window_full+16(a6)              ; full screen?
	bne.s	window_full_height_draw         ; yes
	cmpi.b	#$2,$3e(a3)                     ; the registers?
	beq.s	window_full_height_registers    ; yes
window_full_height_draw:
	bsr.w	set_window_type                 ; its frame
	bra.w	draw_window_contents            ; redraw
window_full_height_registers:
	bsr.w	clear_window_frame
	moveq	#10,d0                          ; 10 lines
	move.w	d0,$12(a3)
	mulu.w	$1a(a3),d0                      ; in pixels
	move.w	$14(a3),d5                      ; the old height
	move.w	d0,$14(a3)                      ; the new
	sub.w	d0,d5                           ; the difference
	bsr.w	draw_window
	lea	window_2(a6),a3                 ; window 2
	bsr.s	move_window                     ; moved
	tst.b	screen_mode(a6)                 ; high resolution?
	beq.s	window_full_height_done         ; no
	lea	window_3(a6),a3                 ; window 3
	bsr.s	move_window                     ; moved
window_full_height_done:
	lea	window_1(a6),a3                 ; window 1
	bsr.w	draw_window_contents            ; redraw
	bra.w	draw_window

;------------------------------------------------------------------------------
; Move the window a3 down by d5 lines of pixels, shrinking it, and redraw it.
;------------------------------------------------------------------------------
move_window:	; from: window_full_height
	bsr.w	clear_window_frame
	moveq	#80,d0                          ; 80 bytes a line
	cmpi.b	#$2,screen_mode(a6)             ; high resolution?
	beq.s	move_window_bytes               ; yes
	add.w	d0,d0                           ; 160
move_window_bytes:
	muls.w	d5,d0
	sub.l	d0,0(a3)                        ; its screen address
	add.w	d5,$14(a3)                      ; its top
	sub.w	d5,$1e(a3)                      ; its height
	move.w	$14(a3),d0                      ; in pixels
	ext.l	d0
	divu.w	$1a(a3),d0                      ; in lines
	move.w	d0,$12(a3)
	st	d4
	sf	d7
	bsr.w	draw_frame                      ; its frame
	bra.w	draw_window_contents            ; redraw

;------------------------------------------------------------------------------
; Alt-R in a register window (and Alt-E): assignments typed at the prompt, "register=expression", until an
; empty line.
;------------------------------------------------------------------------------
set_registers:	; from: window_command, window_edit
	move.l	a3,-(sp)
	moveq	#4,d3
	lea	text_register_value(pc),a0      ; the prompt
	bsr.w	open_prompt_text
set_registers_loop:
	bsr.w	edit_line                       ; a line
	bne.s	set_registers_cancel            ; cancelled
	tst.b	(a4)                            ; empty?
	beq.s	set_registers_cancel            ; yes: done
	movea.l	a4,a2
set_registers_find:
	move.b	(a2)+,d1                        ; a character
	beq.s	set_registers_loop              ; the end: again
	cmp.b	#$3d,d1                         ; =?
	bne.s	set_registers_find              ; no
	lea	arguments(a6),a1                ; the register's name
	move.l	a2,d2
	sub.l	a1,d2
	subq.w	#1,d2                           ; its length
	bsr.w	find_register                   ; find the register
	bne.s	set_registers_loop              ; no such one
	movem.l	a0/a4,-(sp)
	movea.l	a2,a4                           ; the expression
	bsr.w	evaluate_line                   ; work it out
	movem.l	(sp)+,a0/a4
	bne.s	set_registers_loop              ; bad
	move.l	d2,(a0)                         ; the new value
	move.l	a0,-(sp)
	bsr.w	close_prompt
	move.l	(sp)+,d2
	sub.l	a6,d2                           ; its offset
	bsr.w	move_locked_windows
	tst.w	window_full+16(a6)              ; full screen?
	bne.s	set_registers_done              ; yes
	bsr.w	redraw_windows                  ; redraw
set_registers_done:
	movea.l	(sp)+,a3
	rts
set_registers_cancel:
	bsr.w	close_prompt
	movea.l	(sp)+,a3
	rts
register_m:	; from: find_register
	move.b	1(a1),d0                        ; the digit
	subi.b	#$30,d0
	bcs.s	find_register_none
	cmp.b	#$a,d0
	bcc.s	find_register_none              ; 0-9?
	ext.w	d0
	add.w	d0,d0                           ; words
	lea	m_register_offsets(pc),a0       ; the M register table
	move.w	0(a0,d0.w),d0                   ; its offset
	lea	basepage(a6,d0.w),a0            ; its address
	bra.s	find_register_found

;------------------------------------------------------------------------------
; Find the register named at a1, d2 characters long: Dn, An, M0-M9, PC, SR, SP and SSP, END, BSS, DATA,
; TEXT.  a0 = its variable and Z set, or d0 = -1.
;------------------------------------------------------------------------------
find_register:	; from: set_registers, window_lock, read_token
	move.b	(a1),d0                         ; the first letter
	andi.b	#$df,d0                         ; upper case
	cmp.w	#$2,d2                          ; 2 characters?
	beq.s	find_register_2                 ; yes
	bcc.w	find_register_long              ; longer
find_register_none:	; from: set_registers
	moveq	#-1,d0                          ; not a register
	rts
find_register_2:
	lea	reg_a(a6),a0                    ; the address registers
	cmp.b	#$41,d0                         ; A?
	beq.s	find_register_number            ; yes
	lea	reg_d(a6),a0                    ; the data registers
	cmp.b	#$44,d0                         ; D?
	beq.s	find_register_number            ; yes
	cmp.b	#$53,d0                         ; S?
	beq.s	find_register_s                 ; yes
	cmp.b	#$4d,d0                         ; M?
	beq.s	register_m                      ; yes
	cmp.b	#$50,d0                         ; P?
	bne.s	find_register_none              ; no: not a register
	lea	reg_pc(a6),a0                   ; the PC
	cmpi.b	#$43,1(a1)                      ; PC?
	beq.s	find_register_found
	cmpi.b	#$63,1(a1)                      ; Pc?
	beq.s	find_register_found
	bra.s	find_register_none
find_register_s:
	move.b	1(a1),d0                        ; the second letter
	andi.b	#$df,d0                         ; upper case
	lea	reg_sr(a6),a0                   ; the SR
	cmp.b	#$52,d0                         ; SR?
	beq.s	find_register_found
	cmp.b	#$50,d0                         ; SP?
	bne.s	find_register_none              ; no
	lea	reg_usp(a6),a0                  ; the user stack
	btst	#$5,reg_sr+2(a6)                ; supervisor mode?
	beq.s	find_register_found             ; no
	lea	reg_ssp(a6),a0                  ; the supervisor stack
find_register_found:	; from: set_registers
	moveq	#0,d0                           ; found
	rts
find_register_number:
	move.b	1(a1),d0                        ; the digit
	subi.b	#$30,d0
	bcs.s	find_register_none
	cmp.b	#$8,d0                          ; 0-7?
	bcc.s	find_register_none              ; no
	andi.w	#$f,d0
	add.w	d0,d0                           ; longs
	add.w	d0,d0
	adda.w	d0,a0                           ; its address
	bra.s	find_register_found
find_register_long:
	lea	long_registers(pc),a0           ; the longer names
	moveq	#0,d0
find_register_long_loop:
	move.b	(a0)+,d0                        ; a name's length
	beq.w	find_register_none              ; the end: none
	cmp.w	d0,d2                           ; the same length?
	bne.s	find_register_skip              ; no
	move.l	d1,-(sp)
	movem.l	d0/a0-a1,-(sp)
find_register_compare:
	move.b	(a1)+,d1                        ; a character
	andi.b	#$df,d1                         ; upper case
	cmp.b	(a0)+,d1                        ; the same?
	bne.s	find_register_next              ; no
	subq.b	#1,d0                           ; all of it?
	bne.s	find_register_compare           ; no: on
	clr.w	-(sp)                           ; the offset
	move.b	(a0)+,(sp)
	move.b	(a0)+,1(sp)
	move.w	(sp)+,d0
	lea	basepage(a6,d0.w),a0            ; its address
	lea	$c(sp),sp
	move.l	(sp)+,d1
	moveq	#0,d0                           ; found
	rts
find_register_next:
	movem.l	(sp)+,d0/a0-a1
	move.l	(sp)+,d1
find_register_skip:
	lea	2(a0,d0.w),a0                   ; past the name and its offset
	bra.s	find_register_long_loop
long_registers:
	dc.b	$03                             ; the longer register names, each counted, with its offset in the
                                                ;   variables
	dc.b	'SSP',0
	dc.b	$44,$03
	dc.b	'END',0
	dc.b	$6c,$03
	dc.b	'BSS',0
	dc.b	$64,$04
	dc.b	'DATA',0
	dc.w	$5c04
	dc.b	'TEXT',0
	dc.b	$54,$00,$00
register_offsets:	; from: set_window_lock
	dc.w	$004c,$004a,$0044,$006c,$0064,$005c,$0054 ; the offsets of PC, SR, SSP, END, BSS, DATA and TEXT,
                                                ;   followed by their two-letter names
m_register_offsets:	; from: set_registers, draw_registers
	dc.w	$08a4,$08a8,$0712,$0760,$07ae,$07fc,$08ac,$08b0 ; the offsets of M0-M9: M2-M5 are the start addresses of
                                                ;   windows 2-5
	dc.w	$08b4,$08b8
register_names:
	dc.b	'PCSRSPE BS',0                  ; two-letter names, then "D", "T", "X" and M0-M9
	dc.b	'DTXM0M1M2M3M4M5M6M7M8M9'

;------------------------------------------------------------------------------
; Redraw the windows, or only the full screen window when it is open.
;------------------------------------------------------------------------------
redraw_after:	; from: window_breakpoint, hex_column_offset
	move.l	a3,-(sp)
	lea	window_full(a6),a3              ; the full screen window
	tst.w	$10(a3)                         ; open?
	bne.s	redraw_after_full               ; yes
	bsr.w	redraw_windows                  ; no: all the windows
	movea.l	(sp)+,a3
	rts
redraw_after_full:
	bsr.w	draw_window_contents            ; redraw it
	movea.l	(sp)+,a3
	rts

;------------------------------------------------------------------------------
; Alt-E: edit what the window shows: registers, memory, or source code switched between two display forms.
;------------------------------------------------------------------------------
window_edit:	; from: window_command
	move.b	$3e(a3),d0                      ; its type
	cmp.b	#$2,d0                          ; registers?
	beq.w	set_registers                   ; yes: set them
	cmp.b	#$1,d0                          ; memory?
	beq.w	edit_memory                     ; yes: edit it
	cmp.b	#$4,d0                          ; source code?
	beq.s	window_edit_source              ; yes
	rts
window_edit_source:
	eori.b	#$c,$3f(a3)                     ; the other display form
	bsr.w	clear_window                    ; clear it
	bra.w	draw_window_contents            ; redraw

;------------------------------------------------------------------------------
; Alt-B: "Breakpoint address<,param>": a plain breakpoint (,n stops the nth time), ,* permanent, ,= a
; counter, ,?expression conditional, ,- removes the one there.
;------------------------------------------------------------------------------
window_breakpoint:	; from: window_command
	move.l	a3,-(sp)
	moveq	#4,d3
	lea	text_breakpoint_address_param(pc),a0 ; "Breakpoint address<,param>"
	bsr.w	open_prompt_text                ; the prompt
window_breakpoint_line:
	bsr.w	edit_line                       ; a line
	bne.s	window_breakpoint_cancel        ; cancelled
	tst.b	(a4)                            ; empty?
	beq.s	window_breakpoint_cancel        ; yes: cancelled
	bsr.w	evaluate                        ; the address
	beq.s	window_breakpoint_address       ; good
window_breakpoint_bad:
	bsr.w	bell                            ; the bell
	lea	arguments(a6),a4                ; the line again
	bra.s	window_breakpoint_line
window_breakpoint_address:
	move.l	d2,d5                           ; d5 = the address
	moveq	#1,d2                           ; stop the first time
	tst.b	d1                              ; the end?
	beq.s	window_breakpoint_plain         ; yes
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	window_breakpoint_bad           ; no: bad
	move.b	(a4)+,d1                        ; what follows
	cmp.b	#$3f,d1                         ; ?: conditional
	beq.s	window_breakpoint_conditional
	cmp.b	#$2a,d1                         ; *: permanent
	beq.s	window_breakpoint_permanent
	cmp.b	#$3d,d1                         ; =: a counter
	beq.s	window_breakpoint_counter
	cmp.b	#$2d,d1                         ; -?
	bne.s	window_breakpoint_count         ; no
	tst.b	(a4)                            ; alone?
	beq.s	window_breakpoint_remove        ; yes: remove it
window_breakpoint_count:
	bsr.w	evaluate_d1                     ; the count
	bne.s	window_breakpoint_bad           ; bad
	tst.b	d1                              ; the end?
	bne.s	window_breakpoint_bad           ; no: bad
window_breakpoint_plain:
	move.l	d2,d6
	bsr.w	close_prompt                    ; the prompt off
	move.l	d6,d2
	moveq	#1,d3                           ; type 1: plain
window_breakpoint_set:
	movea.l	d5,a1                           ; the address
	bsr.w	set_breakpoint                  ; set it
	bne.s	window_breakpoint_done          ; failed
window_breakpoint_redraw:
	bsr.w	redraw_after                    ; redraw
window_breakpoint_done:
	movea.l	(sp)+,a3
	rts
window_breakpoint_cancel:
	bsr.w	close_prompt                    ; the prompt off
	movea.l	(sp)+,a3
	rts
window_breakpoint_conditional:
	bsr.w	check_expression                ; check the expression
	bne.s	window_breakpoint_bad           ; bad
	move.l	a4,-(sp)
	bsr.w	close_prompt                    ; the prompt off
	movea.l	(sp)+,a4                        ; the expression
	moveq	#4,d3                           ; type 4: conditional
	bra.s	window_breakpoint_set
window_breakpoint_permanent:
	tst.b	(a4)+                           ; the end?
	bne.s	window_breakpoint_bad           ; no: bad
	bsr.w	close_prompt                    ; the prompt off
	moveq	#3,d3                           ; type 3: permanent
	bra.s	window_breakpoint_set
window_breakpoint_counter:
	tst.b	(a4)+                           ; the end?
	bne.w	window_breakpoint_bad           ; no: bad
	bsr.w	close_prompt                    ; the prompt off
	moveq	#2,d3                           ; type 2: a counter
	moveq	#0,d2                           ; from 0
	bra.s	window_breakpoint_set
window_breakpoint_remove:
	bsr.w	close_prompt                    ; the prompt off
	movea.l	d5,a1                           ; the address
	bsr.w	find_breakpoint                 ; find its breakpoint
	bne.s	window_breakpoint_done          ; none
	bsr.w	remove_breakpoint               ; remove it
	bra.s	window_breakpoint_redraw        ; redraw

;------------------------------------------------------------------------------
; Alt-P: print the window.
;------------------------------------------------------------------------------
window_print:	; from: window_command
	bsr.w	printer_ready                   ; the printer ready?
	bne.s	window_print_on                 ; yes
	lea	text_printer_not_responding(pc),a0 ; "Printer not responding"
	bra.w	show_message                    ; show it
window_print_on:
	st	output_on(a6)                   ; output to the printer
	bsr.w	draw_window_contents            ; the window, printed
	sf	output_on(a6)                   ; output to the screen
	rts

;------------------------------------------------------------------------------
; Alt-L: "Register to lock": the window follows a register (none for an empty line); not for register or
; source windows.
;------------------------------------------------------------------------------
window_lock:	; from: window_command
	tst.w	window_full+16(a6)              ; full screen?
	bne.s	window_lock_done                ; yes: not here
	cmpi.b	#$2,$3e(a3)                     ; registers?
	beq.s	window_lock_done                ; yes: not here
	cmpi.b	#$4,$3e(a3)                     ; source code?
	beq.s	window_lock_done                ; yes: not here
	move.l	a3,-(sp)
	moveq	#4,d3
	lea	text_register_to_lock(pc),a0    ; "Register to lock"
	bsr.w	open_prompt_text                ; the prompt
window_lock_line:
	bsr.w	edit_line                       ; a line
	bne.s	window_lock_cancel              ; cancelled
	moveq	#0,d0                           ; no register
	tst.b	(a4)                            ; empty?
	beq.s	window_lock_set                 ; yes
	movea.l	a4,a0
window_lock_length:
	tst.b	(a0)+                           ; find its end
	bne.s	window_lock_length
	move.l	a0,d2
	sub.l	a4,d2                           ; its length
	movea.l	a4,a1                           ; the name
	subq.w	#1,d2
	bsr.w	find_register                   ; find the register
	bne.s	window_lock_line                ; no such one: again
	move.l	a0,d0                           ; its variable's address
	sub.l	a6,d0                           ; as an offset
window_lock_set:
	move.w	d0,-(sp)
	bsr.w	close_prompt                    ; the prompt off
	move.w	(sp)+,d0
	movea.l	(sp)+,a3                        ; the window
	st	d7
	move.w	d0,-(sp)
	bsr.w	set_window_lock                 ; the title shows the register
	move.w	(sp)+,d2
	beq.s	window_lock_done                ; none
	bsr.w	move_locked_windows             ; lock it
	tst.w	window_full+16(a6)              ; full screen?
	bne.s	window_lock_done                ; yes
	move.l	a3,-(sp)
	bsr.w	redraw_windows                  ; redraw the windows
	movea.l	(sp)+,a3
	bra.s	window_lock_done
window_lock_cancel:
	bsr.w	close_prompt                    ; the prompt off
	movea.l	(sp)+,a3
window_lock_done:
	rts

;------------------------------------------------------------------------------
; Alt-S: split a disassembly window (giving window 4) or a memory window (window 5), or join it again; not in
; low resolution.
;------------------------------------------------------------------------------
window_split:	; from: window_command
	tst.w	window_full+16(a6)              ; full screen?
	bne.w	window_split_done               ; yes: not here
	tst.b	screen_mode(a6)                 ; low resolution?
	beq.s	window_split_done               ; yes: not here
	move.b	$3e(a3),d0                      ; its type
	cmp.b	#$3,d0                          ; disassembly?
	beq.s	window_split_disassembly        ; yes
	cmpi.b	#$4,$46(a3)                     ; window 4?
	beq.s	window_split_disassembly        ; yes
	cmp.b	#$1,d0                          ; memory?
	bne.s	window_split_done               ; no: not here
	lea	layout_window_5(a6),a4          ; window 5's layout
	lea	window_5(a6),a5                 ; window 5
	bchg	#$1,split_flags(a6)             ; split already?
	bne.s	window_join                     ; yes: join
	moveq	#5,d4                           ; window 5
	lea	open_memory_window(pc),a2       ; opened as a memory window
	bra.s	window_split_open
window_split_disassembly:
	lea	layout_window_4(a6),a4          ; window 4's layout
	lea	window_4(a6),a5                 ; window 4
	bchg	#$0,split_flags(a6)             ; split already?
	bne.s	window_join                     ; yes: join
	lea	open_disassembly_window(pc),a2  ; opened as a disassembly window
	moveq	#4,d4                           ; window 4
window_split_open:	; from: cmd_load_source
	movem.l	d4/a2,-(sp)
	bsr.s	clear_window_frame              ; clear the window
	move.w	6(a4),d0                        ; the new window's height
	addq.w	#1,d0                           ; + its frame
	mulu.w	split_height(a6),d0             ; in pixels
	sub.w	d0,$14(a3)                      ; taken from this one
	move.w	$14(a3),d0
	ext.l	d0
	divu.w	$1a(a3),d0                      ; in lines
	move.w	d0,$12(a3)
	bsr.s	draw_window                     ; redraw it
	movem.l	(sp)+,d4/a2
	movea.l	a5,a3                           ; the new window
	jsr	(a2)                            ; open it
window_split_draw:
	bsr.w	select_window
	bsr.w	draw_window_contents            ; redraw
window_split_done:
	rts
window_join:
	cmpa.l	a5,a3                           ; the new window itself?
	bne.s	window_join_close               ; no
	lea	-$9c(a3),a3                     ; the one it was split from
window_join_close:
	exg	a5,a3
	bsr.s	clear_window_frame              ; clear the new window
	clr.w	$10(a3)                         ; closed
	exg	a5,a3
	bsr.s	clear_window_frame              ; clear this one
	move.w	6(a4),d0                        ; the new window's height
	addq.w	#1,d0                           ; + its frame
	mulu.w	split_height(a6),d0             ; in pixels
	add.w	d0,$14(a3)                      ; given back
	move.w	$14(a3),d0
	ext.l	d0
	divu.w	$1a(a3),d0                      ; in lines
	move.w	d0,$12(a3)
	bsr.s	draw_window                     ; redraw it
	bra.s	window_split_draw

;------------------------------------------------------------------------------
; Clear the window a3 and draw its frame.
;------------------------------------------------------------------------------
clear_window_frame:	; from: window_full_height, move_window, window_split
	bsr.w	clear_window                    ; clear it
	sf	d4
	sf	d7
	bra.w	draw_frame                      ; its frame

;------------------------------------------------------------------------------
; Draw the window a3's frame and title, then its contents.
;------------------------------------------------------------------------------
draw_window:	; from: window_full_height, window_split
	st	d4
	st	d7
	bsr.w	draw_frame                      ; the frame
	bra.w	draw_window_contents            ; the contents

;------------------------------------------------------------------------------
; Alt-O: "Enter expression": show its value in hex and decimal, and the symbol it is.
;------------------------------------------------------------------------------
window_evaluate:	; from: window_command, command_table
	move.l	a3,-(sp)
	moveq	#6,d3
	lea	text_enter_expression(pc),a0    ; "Enter expression"
	bsr.w	open_prompt_text                ; the prompt
window_evaluate_line:
	bsr.w	edit_line                       ; a line
	bne.s	window_evaluate_done            ; cancelled
	move.b	(a4)+,d1
	beq.s	window_evaluate_done            ; empty: cancelled
	bsr.w	evaluate_line_d1                ; work it out
	beq.s	window_evaluate_show            ; good
	lea	arguments(a6),a4                ; again
	bra.s	window_evaluate_line
window_evaluate_show:
	move.l	d2,d7                           ; the value
	bsr.w	new_line
	bsr.w	new_line
	moveq	#61,d1                          ; =
	bsr.w	print_char                      ; printed
	moveq	#36,d1                          ; $
	bsr.w	print_char                      ; printed
	move.l	d7,d2                           ; the value
	bsr.w	print_hex_long                  ; in hex
	moveq	#18,d1
	bsr.w	print_message
	move.l	d7,d1
	bsr.w	print_decimal                   ; in decimal
	move.l	d7,d0
	bsr.w	find_symbol                     ; a symbol for it?
	beq.s	window_evaluate_wait            ; no
	movea.l	d0,a4
	moveq	#18,d1
	bsr.w	print_message
	bsr.w	print_symbol                    ; and its name
window_evaluate_wait:
	move.w	$16(a3),d2
	moveq	#4,d3
	bsr.w	invert_char                     ; shown
	bsr.w	flush_get_key                   ; wait for a key
window_evaluate_done:
	bsr.w	close_prompt                    ; the prompt off
	movea.l	(sp)+,a3
	rts

;------------------------------------------------------------------------------
; Alt-T: change window 4 between disassembly, memory and source code.
;------------------------------------------------------------------------------
window_type:	; from: window_command
	cmpi.b	#$4,$46(a3)                     ; window 4?
	bne.s	window_type_done                ; no
	tst.w	window_full+16(a6)              ; full screen?
	bne.s	window_type_done                ; yes: not here
	move.b	$3e(a3),d0                      ; its type
	moveq	#1,d1                           ; disassembly next...
	cmp.b	#$3,d0                          ; memory?
	beq.s	window_type_set                 ; yes
	moveq	#3,d1                           ; memory next...
	cmp.b	#$4,d0                          ; source code?
	beq.s	window_type_set                 ; yes
	moveq	#3,d1                           ; memory
	tst.l	source_start(a6)                ; a source file?
	beq.s	window_type_set                 ; no
window_type_source:	; from: cmd_load_source
	moveq	#4,d1                           ; source code
	move.l	source_start(a6),$42(a3)        ; from its start
window_type_set:
	move.b	d1,$3e(a3)                      ; the new type
	clr.w	$4c(a3)
	bsr.w	set_window_type
	bsr.s	set_window_title                ; its title
	bsr.w	clear_window                    ; clear it
	bra.w	draw_window_contents            ; redraw
window_type_done:
	rts

;------------------------------------------------------------------------------
; Set the window a3's title from its type: " Memory ", " Disassembly " or " Source code ", and draw its frame.
;------------------------------------------------------------------------------
set_window_title:	; from: window_type, relocate_symbols
	sf	d4
	sf	d7
	bsr.w	draw_frame                      ; the frame
	lea	$20(a3),a0                      ; the title
	move.b	#$20,(a0)+                      ; a space first
	lea	text_memory(pc),a1              ; "Memory"
	move.b	$3e(a3),d0                      ; its type
	cmp.b	#$1,d0                          ; memory?
	beq.s	window_title_copy               ; yes
	lea	text_disassembly(pc),a1         ; "Disassembly"
	cmp.b	#$3,d0                          ; disassembly?
	beq.s	window_title_copy               ; yes
	lea	text_source_code(pc),a1         ; "Source code"
window_title_copy:
	move.b	(a1)+,(a0)+                     ; copy it
	bne.s	window_title_copy
	move.b	#$20,-$1(a0)                    ; a space after it
	clr.b	(a0)
	st	d4
	st	d7
	bra.w	draw_frame                      ; draw the frame

;------------------------------------------------------------------------------
; MonST's commands: a key and the offset of its routine from the entry; letters, then control keys.
;------------------------------------------------------------------------------
command_table:	; from: command_loop
	dc.w	'A'
	dc.w	cmd_load_source+2-*
	dc.w	'B'
	dc.w	cmd_load_binary+2-*
	dc.w	'D'
	dc.w	cmd_directory+2-*
	dc.w	'G'
	dc.w	cmd_search+2-*
	dc.w	'H'
	dc.w	cmd_history+2-*
	dc.w	'I'
	dc.w	cmd_copy+2-*
	dc.w	'L'
	dc.w	cmd_symbols+2-*
	dc.w	'M'
	dc.w	window_address+2-*
	dc.w	'N'
	dc.w	cmd_find_next+2-*
	dc.w	'O'
	dc.w	window_evaluate+2-*
	dc.w	'P'
	dc.w	cmd_disassemble+2-*
	dc.w	'Q'
	dc.w	cmd_query_port+2-*
	dc.w	'R'
	dc.w	cmd_run_mode+2-*
	dc.w	'S'
	dc.w	cmd_save_binary+2-*
	dc.w	'T'
	dc.w	cmd_write_port+2-*
	dc.w	'U'
	dc.w	cmd_run_until+2-*
	dc.w	'V'
	dc.w	cmd_view+2-*
	dc.w	'W'
	dc.w	cmd_fill+2-*
	dc.w	$1
	dc.w	cmd_step_over+2-*
	dc.w	$2
	dc.w	cmd_toggle_breakpoint+2-*
	dc.w	$4
	dc.w	cmd_bdos_breakpoint+2-*
	dc.w	$5
	dc.w	cmd_reinstall+2-*
	dc.w	$b
	dc.w	cmd_kill_breakpoints+2-*
	dc.w	$c
	dc.w	cmd_load_program+2-*
	dc.w	$f
	dc.w	cmd_resolution+2-*
	dc.w	$10
	dc.w	cmd_preferences+2-*
	dc.w	$12
	dc.w	cmd_run+2-*
	dc.w	$13
	dc.w	cmd_skip+2-*
	dc.w	$14
	dc.w	cmd_trace_rom+2-*
	dc.w	$17
	dc.w	cmd_step+2-*
	dc.w	$19
	dc.w	cmd_step+2-*
	dc.w	$1a
	dc.w	cmd_step+2-*
	dc.w	0

;------------------------------------------------------------------------------
; V: show the program's screen until a key.
;------------------------------------------------------------------------------
cmd_view:	; from: command_table
	bsr.w	program_screen                  ; the program's screen
	bsr.w	flush_get_key                   ; a key
	bra.w	monst_screen                    ; MonST's screen back

;------------------------------------------------------------------------------
; Control-B: set or clear a breakpoint at a disassembly window's start.
;------------------------------------------------------------------------------
cmd_toggle_breakpoint:	; from: command_table
	cmpi.b	#$3,$3e(a3)                     ; disassembly?
	bne.s	cmd_toggle_breakpoint_done      ; no
	movea.l	$42(a3),a1                      ; its address
	pea	redraw_windows(pc)              ; redraw afterwards
	bsr.w	find_breakpoint                 ; a breakpoint there?
	beq.w	remove_breakpoint               ; yes: remove it
	moveq	#1,d2                           ; no: a plain one
	moveq	#1,d3
	bra.w	set_breakpoint                  ; set it
cmd_toggle_breakpoint_done:
	rts

;------------------------------------------------------------------------------
; Control-T: interpret the instruction at the PC (for one in ROM, or a trap, run to its end).
;------------------------------------------------------------------------------
cmd_trace_rom:	; from: command_table
	bsr.s	check_runnable                  ; can it run?
	btst	#$0,reg_pc+3(a6)                ; an odd PC?
	bne.s	cmd_trace_rom_done              ; yes
	movea.l	reg_pc(a6),a2                   ; the PC
	bsr.w	check_address                   ; readable?
	bne.s	cmd_trace_rom_done              ; no
	bsr.w	program_state                   ; the program's state
	bra.w	interpret                       ; interpret it
cmd_trace_rom_done:
	rts

;------------------------------------------------------------------------------
; Control-K: "Kill all breakpoints Y/N?"
;------------------------------------------------------------------------------
cmd_kill_breakpoints:	; from: command_table
	lea	text_kill_all_breakpoints(pc),a0 ; "Kill all breakpoints"
	moveq	#89,d2                          ; Y
	bsr.w	ask_yes_no_message              ; ask
	bne.s	cmd_reinstall_done              ; no
	bsr.w	remove_breakpoints              ; all gone
	bra.w	redraw_windows                  ; redraw

;------------------------------------------------------------------------------
; Control-E: "Re-install exceptions Y/N?"
;------------------------------------------------------------------------------
cmd_reinstall:	; from: command_table
	lea	text_reinstall_exceptions(pc),a0 ; "Re-install exceptions"
	moveq	#89,d2                          ; Y
	bsr.w	ask_yes_no_message              ; ask
	beq.w	reinstall_vectors               ; yes
cmd_reinstall_done:	; from: cmd_kill_breakpoints
	rts

;------------------------------------------------------------------------------
; Return only if there is a program to run with an even, readable PC; else "Cannot run" and back to the
; caller's caller.
;------------------------------------------------------------------------------
check_runnable:	; from: cmd_trace_rom, cmd_run, cmd_step, cmd_step_over, cmd_skip, run_with_mode
	tst.l	reg_ssp(a6)                     ; a program?
	beq.s	cannot_run                      ; no
	btst	#$0,reg_pc+3(a6)                ; the PC odd?
	bne.s	cannot_run                      ; yes
	movea.l	reg_pc(a6),a2                   ; the PC
	bsr.w	check_address                   ; readable?
	bne.s	cannot_run                      ; no
	rts

;------------------------------------------------------------------------------
; Control-R: run the program at full speed.
;------------------------------------------------------------------------------
cmd_run:	; from: command_table, cmd_run_until, cmd_run_mode
	bsr.s	check_runnable                  ; can it run?
	move.w	(a2),d1
	bsr.w	program_state                   ; the program's state
	bclr	#$7,reg_sr+2(a6)                ; no trace
	bra.w	go                              ; go
cannot_run:	; from: check_runnable
	addq.l	#4,sp                           ; not to the caller
cannot_run_message:	; from: cmd_run_until
	lea	text_cannot_run(pc),a0          ; "Cannot run"
	bra.w	show_message                    ; show it

;------------------------------------------------------------------------------
; Control-Z, Control-Y, Control-W: single step one instruction.
;------------------------------------------------------------------------------
cmd_step:	; from: command_table
	bsr.s	check_runnable                  ; can it run?
	bset	#$7,reg_sr+2(a6)                ; trace on
	bsr.w	program_state                   ; the program's state
	movea.l	reg_pc(a6),a1                   ; the PC
	bsr.w	find_breakpoint                 ; a breakpoint there?
	bne.w	go_trace                        ; no: step
	cmpi.w	#$3,6(a0)                       ; permanent?
	bne.w	go_trace                        ; no: step
	bra.w	go                              ; yes: go

;------------------------------------------------------------------------------
; Control-A: run until the next instruction (over a subroutine or trap).
;------------------------------------------------------------------------------
cmd_step_over:	; from: command_table
	bsr.s	check_runnable                  ; can it run?
	bclr	#$7,reg_sr+2(a6)                ; no trace
	bsr.w	next_instruction                ; the next instruction
	movea.l	a2,a1
	moveq	#1,d3                           ; a plain breakpoint
	moveq	#1,d2
	bsr.w	set_breakpoint                  ; set it
	bne.s	cmd_step_over_done              ; failed
	bsr.w	program_state                   ; the program's state
	bra.w	go                              ; go
cmd_step_over_done:
	rts

;------------------------------------------------------------------------------
; Control-S: skip the instruction at the PC.
;------------------------------------------------------------------------------
cmd_skip:	; from: command_table
	bsr.s	check_runnable                  ; can it run?
	bsr.w	next_instruction                ; the next instruction
	move.l	a2,reg_pc(a6)                   ; the new PC
	moveq	#76,d2                          ; "PC"
	bsr.w	move_locked_windows
	bra.w	redraw_windows                  ; redraw

;------------------------------------------------------------------------------
; U: "Run until PC=": run with a breakpoint at an address.
;------------------------------------------------------------------------------
cmd_run_until:	; from: command_table
	tst.l	reg_ssp(a6)                     ; a program?
	beq.s	cannot_run_message              ; no: "Cannot run"
	moveq	#4,d3
	lea	text_run_until_pc(pc),a0        ; "Run until PC="
	bsr.w	open_prompt_text                ; the prompt
cmd_run_until_line:
	bsr.w	edit_line                       ; a line
	bne.s	cmd_run_until_cancel            ; cancelled
	move.b	(a4)+,d1
	beq.s	cmd_run_until_cancel            ; empty: cancelled
	bsr.w	evaluate_line_d1                ; the address
	beq.s	cmd_run_until_go                ; good
	lea	arguments(a6),a4                ; again
	bra.s	cmd_run_until_line
cmd_run_until_cancel:
	bra.w	close_prompt                    ; the prompt off
cmd_run_until_go:
	move.l	d2,-(sp)
	bsr.w	close_prompt                    ; the prompt off
	movea.l	(sp)+,a1                        ; the address
	moveq	#1,d2                           ; a plain breakpoint
	moveq	#1,d3
	bsr.w	set_breakpoint                  ; set it
	beq.w	cmd_run                         ; run
	rts

;------------------------------------------------------------------------------
; Q: "Query which port": read a byte (or ,W a word, ,L a long) at an address with the program's screen
; and show it.
;------------------------------------------------------------------------------
cmd_query_port:	; from: command_table
	moveq	#5,d3
	lea	text_query_which_port(pc),a0    ; "Query which port"
	bsr.w	open_prompt_text                ; the prompt
cmd_query_port_line:
	bsr.w	edit_line                       ; a line
	bne.s	cmd_query_port_cancel           ; cancelled
	tst.b	(a4)                            ; empty?
	beq.s	cmd_query_port_cancel           ; yes: cancelled
	bsr.w	evaluate                        ; the address
	beq.s	cmd_query_port_read             ; good
	bsr.w	bell                            ; the bell
	lea	arguments(a6),a4                ; again
	bra.s	cmd_query_port_line
cmd_query_port_cancel:
	bra.w	close_prompt                    ; the prompt off
cmd_query_port_read:
	movea.l	d2,a0                           ; the address
	bsr.w	program_screen                  ; the program's screen and state
	moveq	#0,d2
	tst.b	d1                              ; the end: a byte
	beq.s	cmd_query_port_byte
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_query_port_line             ; no: again
	move.b	(a4)+,d1                        ; the size
	cmp.b	#$57,d1                         ; W?
	beq.s	cmd_query_port_word
	cmp.b	#$4c,d1                         ; L?
	beq.s	cmd_query_port_long
cmd_query_port_byte:
	move.b	(a0),d2                         ; the byte
	bra.s	cmd_query_port_show
cmd_query_port_word:
	move.w	(a0),d2                         ; the word
	bra.s	cmd_query_port_show
cmd_query_port_long:
	move.l	(a0),d2                         ; the long
cmd_query_port_show:
	bsr.w	monst_screen                    ; MonST's screen back
	bsr.w	new_line
	bsr.w	print_hex_long                  ; in hex
	bsr.w	flush_get_key                   ; wait for a key
	bra.w	close_prompt                    ; the prompt off

;------------------------------------------------------------------------------
; T: "Port to write, value": write a byte (or ,W a word, ,L a long) at an address with the program's screen.
;------------------------------------------------------------------------------
cmd_write_port:	; from: command_table
	moveq	#4,d3
	lea	text_port_to_write_value(pc),a0 ; "Port to write, value"
	bsr.w	open_prompt_text                ; the prompt
cmd_write_port_line:
	bsr.w	edit_line                       ; a line
	bne.s	cmd_write_port_cancel           ; cancelled
	tst.b	(a4)                            ; empty?
	beq.s	cmd_write_port_cancel           ; yes: cancelled
	bsr.w	evaluate                        ; the address
	beq.s	cmd_write_port_value            ; good
cmd_write_port_bad:
	bsr.w	bell                            ; the bell
	lea	arguments(a6),a4                ; again
	bra.s	cmd_write_port_line
cmd_write_port_cancel:
	bra.w	close_prompt                    ; the prompt off
cmd_write_port_value:
	tst.b	d1                              ; the end?
	beq.s	cmd_write_port_bad              ; yes: bad
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_write_port_bad              ; no: bad
	move.l	d2,-(sp)
	bsr.w	evaluate                        ; the value
	movea.l	(sp)+,a0                        ; the address
	bne.s	cmd_write_port_bad              ; bad
	bsr.w	program_screen                  ; the program's screen and state
	tst.b	d1                              ; the end: a byte
	beq.s	cmd_write_port_byte
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_write_port_bad              ; no: bad
	move.b	(a4)+,d1                        ; the size
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$57,d1                         ; W?
	beq.s	cmd_write_port_word
	cmp.b	#$4c,d1                         ; L?
	beq.s	cmd_write_port_long
cmd_write_port_byte:
	move.b	d2,(a0)                         ; the byte
	bra.s	cmd_write_port_done
cmd_write_port_word:
	move.w	d2,(a0)                         ; the word
	bra.s	cmd_write_port_done
cmd_write_port_long:
	move.l	d2,(a0)                         ; the long
cmd_write_port_done:
	bsr.w	monst_screen                    ; MonST's screen back
	bsr.w	new_line
	bra.w	close_prompt                    ; the prompt off

;------------------------------------------------------------------------------
; G: "Search for B/W/L/T/I?": bytes, words or longs (a list, or one value with ,W or ,L making its size), text
; (case ignored if asked) or an instruction's text; then the search from the current window.
;------------------------------------------------------------------------------
cmd_search:	; from: command_table
	moveq	#5,d3
	bsr.w	open_prompt
	lea	text_search_for(pc),a0          ; "Search for B/W/L/T/I? "
	bsr.w	print_string                    ; the prompt
	movea.l	current_window(a6),a0           ; the current window
	moveq	#84,d1                          ; T
	cmpi.b	#$4,$3e(a0)                     ; source code?
	beq.s	cmd_search_set_kind             ; yes: text only
	moveq	#0,d3
	movem.w	$16(a3),d2-d3
	divu.w	$1a(a3),d3
	bsr.w	invert_char
cmd_search_kind:
	bsr.w	get_key                         ; a key
	bmi.s	cmd_search_kind
	cmp.b	#$1b,d1                         ; Esc?
	beq.w	cmd_search_cancel               ; yes
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$42,d1                         ; B?
	beq.s	cmd_search_set_kind
	cmp.b	#$57,d1                         ; W?
	beq.s	cmd_search_set_kind
	cmp.b	#$4c,d1                         ; L?
	beq.s	cmd_search_set_kind
	cmp.b	#$54,d1                         ; T?
	beq.s	cmd_search_set_kind
	cmp.b	#$49,d1                         ; I?
	bne.s	cmd_search_kind                 ; no: another key
cmd_search_set_kind:
	move.b	d1,search_kind(a6)              ; the kind
	bsr.w	print_char                      ; shown
	bsr.w	new_line
	lea	arguments(a6),a4
	clr.b	(a4)                            ; an empty line
	moveq	#0,d4
	moveq	#1,d6                           ; bytes
cmd_search_line:
	bsr.w	edit_line                       ; a line
	bne.w	cmd_search_cancel               ; cancelled
	bsr.w	new_line
	lea	search_kind(a6),a5              ; the kind
	move.b	(a5)+,d5
	cmp.b	#$49,d5                         ; an instruction?
	beq.s	cmd_search_text                 ; yes: as text
	cmp.b	#$54,d5                         ; text?
	beq.s	cmd_search_text                 ; yes
	clr.b	-$4(a5)
cmd_search_values:
	move.b	(a4)+,d1                        ; a character
	tst.b	(a4)                            ; the last?
	bne.s	cmd_search_value                ; no
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$4c,d1                         ; L: longs?
	beq.s	cmd_search_longs
	cmp.b	#$57,d1                         ; W: words?
	bne.s	cmd_search_value                ; no
	moveq	#2,d6                           ; words
	bra.s	cmd_search_values_done
cmd_search_longs:
	moveq	#4,d6                           ; longs
	bra.s	cmd_search_values_done
cmd_search_value:
	subq.w	#1,a4                           ; back to it
	bsr.w	evaluate                        ; the value
	bne.s	cmd_search_bad                  ; bad
	cmp.b	#$42,d5                         ; bytes?
	beq.s	cmd_search_byte
	cmp.b	#$57,d5                         ; words?
	beq.s	cmd_search_word
	move.l	d2,(a5)+                        ; a long
	bra.s	cmd_search_next_value
cmd_search_word:
	move.w	d2,(a5)+                        ; a word
	bra.s	cmd_search_next_value
cmd_search_byte:
	move.b	d2,(a5)+                        ; a byte
cmd_search_next_value:
	tst.b	d1                              ; the end?
	beq.s	cmd_search_values_done          ; yes
	cmp.b	#$2c,d1                         ; a comma?
	beq.s	cmd_search_values               ; yes: the next
cmd_search_bad:
	bsr.w	bell                            ; the bell
	lea	arguments(a6),a4
	bra.s	cmd_search_line                 ; again
cmd_search_values_done:
	lea	search_pattern(a6),a0           ; the pattern
	move.l	a5,d0
	sub.l	a0,d0                           ; its length
	bra.s	cmd_search_store
cmd_search_text:
	tst.b	search_ignore_case(a6)
	lea	text_ignore_case(pc),a0         ; "Ignore case Y/N? "
	bsr.w	ask_yes_no                      ; ask
	beq.s	cmd_search_copy_text            ; cancelled: as before
	spl	search_ignore_case(a6)
cmd_search_copy_text:
	movea.l	a4,a0
	tst.b	search_ignore_case(a6)          ; ignore case?
	beq.s	cmd_search_text_plain           ; no
cmd_search_text_upper:
	move.b	(a4)+,d1                        ; a character
	bsr.w	upper_case                      ; upper case
	move.b	d1,(a5)+
	bne.s	cmd_search_text_upper
	bra.s	cmd_search_text_length
cmd_search_text_plain:
	move.b	(a4)+,(a5)+
	bne.s	cmd_search_text_plain
cmd_search_text_length:
	move.l	a4,d0
	sub.l	a0,d0
	subq.l	#1,d0                           ; its length
	clr.b	arguments(a6)                   ; no arguments now
cmd_search_store:
	move.b	d0,search_length(a6)            ; the pattern's length
	move.b	d6,search_align(a6)             ; its step
	bsr.w	close_prompt                    ; the prompt off
	bra.s	cmd_find_next                   ; search
cmd_search_cancel:
	clr.w	search_length(a6)               ; no search
	bra.w	close_prompt                    ; the prompt off

;------------------------------------------------------------------------------
; N: find the next match of the last search from the current window's address.
;------------------------------------------------------------------------------
cmd_find_next:	; from: command_table, cmd_search
	lea	window_title(a6),a3             ; the title window
	moveq	#14,d1                          ; "Searching..."
	bsr.w	print_message                   ; shown
	movea.l	current_window(a6),a0           ; the current window
	movea.l	$42(a0),a2                      ; its address
	move.b	$3e(a0),d0                      ; its type
	cmp.b	#$2,d0                          ; registers?
	beq.s	cmd_find_next_done              ; yes: nothing
	lea	search_length(a6),a3            ; the pattern
	moveq	#0,d3
	move.b	(a3)+,d3                        ; its length
	beq.s	cmd_find_next_done              ; none
	addq.w	#1,a3
	moveq	#0,d6
	move.b	(a3)+,d6                        ; its step
	cmp.b	#$4,d0                          ; source code?
	beq.w	search_source                   ; yes
	bsr.s	search_step
	move.b	(a3)+,d0                        ; the kind
	cmp.b	#$49,d0                         ; an instruction?
	bne.s	search_bytes                    ; no
	bra.w	search_instruction              ; yes
cmd_find_next_done:
	bra.w	clear_message                   ; clear the message

search_advance:	; from: search_bytes
	addq.l	#1,a2                           ; the next address
	bra.s	search_check

;------------------------------------------------------------------------------
; Step the search address a2 by d6, keeping it in readable memory: past phystop it goes on in the ROM ranges
; and after them wraps to 0.  Z set when it jumped.
;------------------------------------------------------------------------------
search_step:	; from: cmd_find_next, search_bytes, search_instruction
	adda.l	d6,a2                           ; the step
search_check:	; from: search_advance
	cmpa.l	phystop(a6),a2                  ; in RAM?
	bcs.s	search_check_done               ; yes
	cmpa.l	rom_start(a6),a2                ; below the ROM?
	bcs.s	search_to_rom                   ; yes: to its start
	cmpa.l	rom_end(a6),a2                  ; inside it?
	bcc.s	search_check_rom2               ; no
	rts                                     ; yes
search_check_rom2:
	cmpa.l	rom2_start(a6),a2               ; below the second range?
	bcs.s	search_to_rom2                  ; yes: to its start
	cmpa.l	rom2_end(a6),a2                 ; inside it?
	bcc.s	search_wrap                     ; no: back to 0
search_check_done:
	rts
search_wrap:
	suba.l	a2,a2                           ; back to 0
	cmp.b	d1,d1                           ; Z set
	rts
search_to_rom:
	movea.l	rom_start(a6),a2                ; the ROM's start
	cmp.b	d1,d1                           ; Z set
	rts
search_to_rom2:
	movea.l	rom2_start(a6),a2               ; the second range's start
	cmp.b	d1,d1                           ; Z set
	rts

;------------------------------------------------------------------------------
; Search for the pattern at a3, d3 bytes long, from a2 on in steps of d6; Esc stops it every 64 K tries.
;------------------------------------------------------------------------------
search_bytes:	; from: cmd_find_next
	move.l	d6,d4
	neg.l	d4
	move.l	a2,d1
	and.l	d1,d4
	add.l	d6,d4                           ; a2 aligned to the step, past it
	movea.l	d4,a2
	move.b	(a3)+,d4                        ; the first byte
	subq.b	#1,d3                           ; the rest
	moveq	#0,d5                           ; the try count
	tst.b	search_ignore_case(a6)          ; ignore case?
	beq.s	search_bytes_loop               ; no
	bra.s	search_text_nocase              ; yes
search_bytes_escape:
	bsr.w	check_escape                    ; Esc?
	bne.s	search_bytes_loop               ; no: on
	movea.l	a2,a4                           ; yes: stop here
	bra.s	search_found
search_bytes_loop:
	addq.w	#1,d5                           ; 64 K tries?
	beq.s	search_bytes_escape             ; yes: Esc?
	bsr.s	search_step                     ; the next address
	cmp.b	(a2),d4                         ; the first byte?
	bne.s	search_bytes_loop               ; no
	movea.l	a2,a4                           ; a possible match
	tst.b	d3                              ; one byte only?
	beq.s	search_found                    ; yes: found
	movea.l	a3,a0                           ; the rest
	move.b	d3,d0
search_bytes_compare:
	bsr.s	search_advance                  ; the next byte
	beq.s	search_bytes_miss               ; jumped: no match
	move.b	(a2),d1
	cmp.b	(a0)+,d1                        ; the same?
	bne.s	search_bytes_miss               ; no
	subq.b	#1,d0
	bne.s	search_bytes_compare            ; all of them?
	bra.s	search_found                    ; yes: found
search_bytes_miss:
	movea.l	a4,a2                           ; from the possible match
	bra.s	search_bytes_loop               ; on
search_text_nocase:
	bra.s	search_text_loop
search_text_escape:
	bsr.w	check_escape                    ; Esc?
	bne.s	search_text_loop                ; no: on
	movea.l	a2,a4                           ; yes: stop here
	bra.s	search_found
search_text_loop:
	addq.w	#1,d5                           ; 64 K tries?
	beq.s	search_text_escape              ; yes: Esc?
	bsr.w	search_step                     ; the next address
	move.b	(a2),d1                         ; the byte
	bsr.w	upper_case                      ; upper case
	cmp.b	d1,d4                           ; the first?
	bne.s	search_text_loop                ; no
	movea.l	a2,a4                           ; a possible match
	tst.b	d3                              ; one only?
	beq.s	search_found                    ; yes: found
	movea.l	a3,a0                           ; the rest
	move.b	d3,d0
search_text_compare:
	bsr.w	search_advance                  ; the next byte
	beq.s	search_text_miss                ; jumped: no match
	move.b	(a2),d1
	bsr.w	upper_case                      ; upper case
	cmp.b	(a0)+,d1                        ; the same?
	bne.s	search_text_miss                ; no
	subq.b	#1,d0
	bne.s	search_text_compare             ; all of them?
	bra.s	search_found                    ; yes: found
search_text_miss:
	movea.l	a4,a2                           ; from the possible match
	bra.s	search_text_loop                ; on

;------------------------------------------------------------------------------
; Show the match at a4: in windows 2 and 3, or in windows 4 and 5 when the search started in one of them (a
; source window 4 keeps its place).
;------------------------------------------------------------------------------
search_found:	; from: search_bytes, search_source, search_instruction
	movea.l	current_window(a6),a0           ; the current window
	move.b	$46(a0),d0                      ; its number
	subq.b	#4,d0                           ; 4 or 5?
	bcc.s	search_found_lower              ; yes
	move.l	a4,window_2+66(a6)              ; window 2's address
	move.l	a4,window_3+66(a6)              ; window 3's address
	bra.s	search_found_show
search_found_lower:
	move.l	a4,window_5+66(a6)              ; window 5's address
	cmpi.b	#$4,window_4+62(a6)             ; window 4 source code?
	beq.s	search_found_show               ; yes
	move.l	a4,window_4+66(a6)              ; window 4's address
search_found_show:	; from: search_source
	bsr.w	clear_message                   ; clear "Searching..."
	bra.w	redraw_windows                  ; redraw
search_not_found:	; from: search_source
	bra.w	clear_message                   ; clear "Searching..."

;------------------------------------------------------------------------------
; Search a source window's file for the text from its current line on, line by line.
;------------------------------------------------------------------------------
search_source:	; from: cmd_find_next
	cmpi.b	#$54,(a3)+                      ; text?
	bne.s	search_not_found                ; no: nothing to find
search_source_line:
	bsr.w	source_next_line                ; the next line
	beq.s	search_not_found                ; the end: not found
	movea.l	a2,a0
	tst.b	search_ignore_case(a6)          ; ignore case?
	bne.s	search_source_nocase            ; yes
search_source_char:
	move.b	(a0)+,d1                        ; a character
	cmp.b	#$d,d1                          ; the line's end?
	beq.s	search_source_line              ; yes: the next line
	cmp.b	(a3),d1                         ; the first?
	bne.s	search_source_char              ; no
	movem.l	d3/a0/a3,-(sp)
	addq.l	#1,a3
search_source_compare:
	subq.w	#1,d3                           ; all of them?
	beq.s	search_source_found             ; yes: found
	cmpm.b	(a0)+,(a3)+                     ; the same?
	beq.s	search_source_compare           ; yes: on
	movem.l	(sp)+,d3/a0/a3
	bra.s	search_source_char              ; no: on
search_source_found:
	movem.l	(sp)+,d3/a0/a3
	movea.l	current_window(a6),a3           ; the current window
	move.l	a2,$42(a3)                      ; starts at the line
	bra.s	search_found_show               ; show it
search_source_nocase:
	move.b	(a0)+,d1                        ; a character
	cmp.b	#$d,d1                          ; the line's end?
	beq.s	search_source_line              ; yes: the next line
	bsr.w	upper_case                      ; upper case
	cmp.b	(a3),d1                         ; the first?
	bne.s	search_source_nocase            ; no
	movem.l	d3/a0/a3,-(sp)
	addq.l	#1,a3
search_source_compare_nocase:
	subq.w	#1,d3                           ; all of them?
	beq.s	search_source_found             ; yes: found
	move.b	(a0)+,d1
	bsr.w	upper_case                      ; upper case
	cmp.b	(a3)+,d1                        ; the same?
	beq.s	search_source_compare_nocase    ; yes: on
	movem.l	(sp)+,d3/a0/a3
	bra.s	search_source_nocase            ; no: on
search_instruction_stop:	; from: search_instruction
	movea.l	a2,a4                           ; stopped here
	bra.w	search_found                    ; show it

;------------------------------------------------------------------------------
; Search for an instruction whose disassembly contains the text: each word aligned address is disassembled and
; its text compared.
;------------------------------------------------------------------------------
search_instruction:	; from: cmd_find_next
	move.l	a2,d0
	btst	#$0,d0                          ; odd?
	beq.s	search_instruction_loop         ; no
	bsr.w	search_step                     ; to an even address
search_instruction_loop:
	movea.l	a2,a1
	lea	9(a2),a2                        ; 9 bytes on
	bsr.w	search_step                     ; kept in memory
	exg	a2,a1
	suba.l	a2,a1
	cmpa.l	#$a,a1                          ; did it jump?
	beq.s	search_instruction_try          ; no
	lea	9(a2),a2
	bsr.w	search_step
search_instruction_try:
	bsr.w	check_escape                    ; Esc?
	beq.s	search_instruction_stop         ; yes: stop
	movea.l	a2,a5                           ; the address
	move.l	a2,-(sp)
	sf	listing_mode(a6)                ; without the address
	move.l	d6,-(sp)
	bsr.w	disassemble                     ; disassemble it
	move.l	(sp)+,d6
	moveq	#0,d0
	move.b	search_length(a6),d0            ; the pattern's length
	subq.b	#1,d0
	lea	line_buffer(a6),a1              ; the disassembly's text
	lea	search_pattern(a6),a0           ; the pattern
	move.b	(a0)+,d2                        ; its first character
	tst.b	search_ignore_case(a6)          ; ignore case?
	bne.s	search_instruction_nocase       ; yes
search_instruction_char:
	move.b	(a1)+,d1                        ; a character
	cmp.b	d1,d2                           ; the first?
	beq.s	search_instruction_first        ; yes
	cmp.b	#$d,d1                          ; the end?
	bne.s	search_instruction_char         ; no: on
	bra.s	search_instruction_next         ; no match
search_instruction_first:
	tst.b	d0                              ; one character only?
	beq.s	search_instruction_found        ; yes: found
	movem.l	d0/a0-a1,-(sp)
	subq.w	#1,d0
search_instruction_compare:
	cmpm.b	(a0)+,(a1)+                     ; the rest
	dbne	d0,search_instruction_compare
search_instruction_compared:
	movem.l	(sp)+,d0/a0-a1
	beq.s	search_instruction_found        ; all the same: found
search_instruction_next:
	movea.l	(sp)+,a2                        ; the address
	bsr.w	search_step                     ; 2 bytes on
	bsr.w	search_step
	bra.s	search_instruction_loop         ; again
search_instruction_found:
	movea.l	(sp)+,a4
	bra.w	search_found                    ; show it
search_instruction_nocase:
	move.b	(a1)+,d1                        ; a character
	bsr.w	upper_case                      ; upper case
	cmp.b	d1,d2                           ; the first?
	beq.s	search_instruction_first_nocase ; yes
	cmp.b	#$d,d1                          ; the end?
	bne.s	search_instruction_nocase       ; no: on
	bra.s	search_instruction_next         ; no match
search_instruction_first_nocase:
	tst.b	d0                              ; one character only?
	beq.s	search_instruction_found        ; yes: found
	movem.l	d0/a0-a1,-(sp)
	subq.w	#1,d0
search_instruction_compare_nocase:
	move.b	(a1)+,d1                        ; a character
	bsr.w	upper_case                      ; upper case
	cmp.b	(a0)+,d1                        ; the same?
	dbne	d0,search_instruction_compare_nocase
	bra.s	search_instruction_compared

;------------------------------------------------------------------------------
; Control-O: switch MonST's display between low and medium resolution (not in high resolution).
;------------------------------------------------------------------------------
cmd_resolution:	; from: command_table
	move.b	screen_mode(a6),d7              ; the mode
	cmp.b	#$2,d7                          ; high?
	beq.s	cmd_resolution_done             ; yes: not here
	eori.b	#$1,d7                          ; the other one
	move.b	d7,screen_mode(a6)
	bsr.w	wait_vbl
	bsr.w	monst_screen_show
	bsr.w	init_screen
	bsr.w	open_windows                    ; the windows again
	bra.w	redraw_windows                  ; redraw
cmd_resolution_done:
	rts

;------------------------------------------------------------------------------
; Print the symbol entry's name at a4: its 8 characters, then up to 14 more for a long name.
;------------------------------------------------------------------------------
print_symbol:	; from: window_evaluate, cmd_symbols, listing_address
	moveq	#7,d3                           ; 8 characters
	movea.l	a4,a0
print_symbol_loop:
	move.b	(a0)+,d1                        ; a character
	beq.s	print_symbol_done               ; the end
	bsr.w	print_char                      ; printed
	dbra	d3,print_symbol_loop
	tst.b	9(a4)                           ; a long name?
	beq.s	print_symbol_done               ; no
	moveq	#13,d3                          ; 14 more
	lea	$e(a4),a0
print_symbol_long:
	move.b	(a0)+,d1                        ; a character
	beq.s	print_symbol_done               ; the end
	bsr.w	print_char                      ; printed
	dbra	d3,print_symbol_long
print_symbol_done:
	rts

;------------------------------------------------------------------------------
; L: list the program's symbols full screen, a page at a time (Esc stops).
;------------------------------------------------------------------------------
cmd_symbols:	; from: command_table
	tst.l	symbols(a6)                     ; any symbols?
	beq.w	cmd_symbols_none                ; no
	lea	text_symbols(pc),a2             ; "Symbols"
	bsr.w	open_full_window                ; full screen
	movea.l	symbols(a6),a4                  ; the symbol table
	moveq	#0,d6                           ; the line count
	lea	-$e(a4),a4                      ; before the first entry
cmd_symbols_loop:
	lea	$e(a4),a4                       ; the next entry, $e bytes
	move.b	(a4),d0
	beq.s	cmd_symbols_end                 ; the end
	addq.b	#1,d0                           ; $ff: a long name's second part
	beq.s	cmd_symbols_loop                ; yes: skip it
	move.l	$a(a4),d2                       ; its value
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_space                     ; a space
	bsr.s	print_symbol                    ; its name
	bsr.w	print_newline                   ; a new line
	tst.b	9(a4)                           ; a long name?
	beq.s	cmd_symbols_line                ; no
	lea	$e(a4),a4                       ; past its second part
cmd_symbols_line:
	addq.w	#1,d6                           ; a line more
	cmp.w	$12(a3),d6                      ; the window full?
	bne.s	cmd_symbols_loop                ; no
	bsr.w	flush_get_key                   ; wait for a key
	cmp.b	#$1b,d1                         ; Esc?
	beq.s	cmd_symbols_done                ; yes: stop
	moveq	#0,d6                           ; a new page
	bsr.w	clear_window                    ; cleared
	clr.l	$16(a3)                         ; from the top
	bra.s	cmd_symbols_loop
cmd_symbols_end:
	bsr.w	flush_get_key                   ; wait for a key
cmd_symbols_done:
	bsr.w	close_prompt                    ; the full screen off
cmd_symbols_none:	; from: cmd_load_source
	rts

;------------------------------------------------------------------------------
; A: "Source file to load": load an ASCII file and show it in window 4 (opened by splitting window 2 when
; it is not there); not in low resolution.
;------------------------------------------------------------------------------
cmd_load_source:	; from: command_table
	tst.l	source_start(a6)                ; a source file already?
	beq.s	cmd_load_source_ask             ; no
	tst.b	source_from_editor(a6)          ; from the editor?
	bgt.s	cmd_load_source_ask             ; yes: keep it
	movea.l	source_start(a6),a0
	bsr.w	mfree                           ; freed
	clr.l	source_start(a6)
cmd_load_source_ask:
	lea	text_source_file_to_load(pc),a0 ; "Source file to load"
	bsr.w	ask_load_file                   ; ask for it and load it
	bne.w	cmd_load_binary_done            ; failed
	move.l	a3,source_start(a6)             ; its start
	adda.l	d4,a3
	move.l	a3,source_end(a6)               ; its end
	move.b	prog_loaded(a6),source_from_editor(a6)
	tst.b	screen_mode(a6)                 ; low resolution?
	beq.s	cmd_symbols_none                ; yes: not shown
	bset	#$0,split_flags(a6)             ; window 4 open?
	beq.s	cmd_load_source_split           ; no
	lea	window_4(a6),a3                 ; window 4
	bsr.w	select_window
	bra.w	window_type_source              ; to the source
cmd_load_source_split:
	lea	window_2(a6),a3                 ; window 2
	bsr.w	select_window
	lea	layout_window_4(a6),a4          ; window 4's layout
	lea	window_4(a6),a5                 ; window 4
	lea	open_source_window(pc),a2       ; opened as a source window
	moveq	#4,d4                           ; window 4
	bra.w	window_split_open               ; split window 2
open_source_window:
	movem.w	(a4)+,d0-d3                     ; its position and size
	lea	text_source_code(pc),a2         ; "Source code"
	move.b	#$4,$3e(a3)                     ; source code
	move.b	d4,$46(a3)                      ; its number
	bsr.w	open_window                     ; open it
	move.l	source_start(a6),$42(a3)        ; at the start
	bra.w	set_window_type                 ; draw it

;------------------------------------------------------------------------------
; B: "Filename to load": load a file (",address" puts it there) and set M0 and M1 to its start and end.
;------------------------------------------------------------------------------
cmd_load_binary:	; from: command_table
	lea	text_filename_to_load(pc),a0    ; "Filename to load"
	moveq	#4,d3
	bsr.w	open_prompt_text                ; the prompt
	bsr.w	edit_line_start                 ; a name
cmd_load_binary_line:
	bne.w	close_prompt                    ; cancelled
	tst.b	(a4)                            ; empty?
	beq.w	close_prompt                    ; yes: cancelled
	lea	arguments(a6),a0                ; the name
	moveq	#0,d2                           ; no address
cmd_load_binary_comma:
	move.b	(a0)+,d1                        ; a character
	beq.s	cmd_load_binary_load            ; the end
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_load_binary_comma           ; no
	movea.l	a0,a4                           ; the address
	move.l	a0,-(sp)
	bsr.w	evaluate_line                   ; worked out
	movea.l	(sp)+,a0
	beq.s	cmd_load_binary_cut             ; good
	lea	arguments(a6),a4
	bsr.w	edit_line                       ; again
	bra.s	cmd_load_binary_line
cmd_load_binary_cut:
	clr.b	-(a0)                           ; the name ends at the comma
cmd_load_binary_load:
	bsr.s	load_file                       ; load it
	bne.s	cmd_load_binary_done            ; failed
	move.l	a3,reg_m0(a6)                   ; M0 = its start
	move.l	a3,window_2+66(a6)              ; window 2 shows it
	move.l	a3,window_3+66(a6)              ; and window 3
	adda.l	d4,a3
	subq.l	#1,a3
	move.l	a3,reg_m1(a6)                   ; M1 = its end
	bra.w	redraw_windows                  ; redraw
cmd_load_binary_done:	; from: cmd_load_source
	rts

;------------------------------------------------------------------------------
; Ask for a file name with the prompt at a0 and load it (see load_file).
;------------------------------------------------------------------------------
ask_load_file:	; from: cmd_load_source
	moveq	#4,d3
	bsr.w	open_prompt_text                ; the prompt
	bsr.w	edit_line_start                 ; a name
	bne.s	load_file_cancel                ; cancelled
	tst.b	(a4)                            ; empty?
	beq.s	load_file_cancel                ; yes: cancelled
	moveq	#0,d2                           ; anywhere in memory

;------------------------------------------------------------------------------
; Load the file named in arguments to d2 (0: a new block of its size): a3 = where, d4 = its length, Z set;
; else the TOS error is shown and d0 = -1.
;------------------------------------------------------------------------------
load_file:	; from: cmd_load_binary
	move.l	d2,-(sp)
	bsr.w	close_prompt                    ; the prompt off
	bsr.w	program_state                   ; the program's screen and state
	lea	arguments(a6),a0                ; the name
	bsr.w	open_file                       ; open it
	movea.l	(sp)+,a0                        ; the address
	bne.s	load_file_error                 ; failed
	move.l	a0,-(sp)
	bsr.w	file_length                     ; its length
	move.l	(sp)+,d0
	bne.s	load_file_read                  ; an address given?
	move.l	d4,d0                           ; the length
	bsr.w	malloc                          ; Malloc
	beq.s	load_file_no_memory             ; none: not enough memory
load_file_read:
	movea.l	d0,a3
	movea.l	d0,a0
	bsr.w	read_file                       ; read it
	bsr.w	close_file                      ; close
	bsr.w	monst_screen                    ; MonST's screen back
	moveq	#0,d0                           ; Z set
	rts
load_file_no_memory:
	moveq	#-39,d0                         ; -39: not enough memory
load_file_error:
	move.w	d0,-(sp)
	bsr.w	close_file                      ; close
	bsr.w	monst_screen                    ; MonST's screen back
	move.w	(sp)+,d0
	bsr.w	show_tos_error                  ; "TOS error: n"
	moveq	#-1,d0                          ; failed
	rts
load_file_cancel:	; from: ask_load_file
	bsr.w	close_prompt                    ; the prompt off
	moveq	#-1,d0                          ; cancelled
	rts

;------------------------------------------------------------------------------
; Control-P: "PREFERENCES": screen timer, follow traps, relative offsets, ignore case, ignore cartridge area,
; symbol length (8 to 22) and top of RAM, then "Save preferences Y/N?" writes them to MONST2.INF.
;------------------------------------------------------------------------------
cmd_preferences:	; from: command_table
	moveq	#13,d3
	lea	text_preferences(pc),a0         ; "PREFERENCES"
	bsr.w	open_prompt_text                ; the prompt
	lea	text_screen_timer(pc),a0        ; "Screen timer Y/N? "
	tst.b	screen_timer_on(a6)             ; the setting
	bsr.s	ask_yes_no                      ; ask
	beq.s	pref_traps                      ; cancelled: as it was
	spl	screen_timer_on(a6)             ; Y: on
pref_traps:
	lea	text_follow_traps(pc),a0        ; "Follow traps Y/N? "
	tst.b	follow_traps(a6)
	bsr.s	ask_yes_no                      ; ask
	beq.s	pref_relative
	spl	follow_traps(a6)
pref_relative:
	lea	text_relative_offsets(pc),a0    ; "Relative offsets Y/N? "
	tst.b	relative_offsets(a6)
	bsr.s	ask_yes_no                      ; ask
	beq.s	pref_case
	spl	relative_offsets(a6)
pref_case:
	lea	text_ignore_case(pc),a0         ; "Ignore case Y/N? "
	tst.b	ignore_case(a6)
	bsr.s	ask_yes_no                      ; ask
	beq.w	pref_cartridge
	spl	ignore_case(a6)
	bra.s	pref_cartridge

;------------------------------------------------------------------------------
; Print the question at a0 with its current answer (the flags from the setting: Y when set), the cursor on it,
; and wait for Y or N (Return keeps it, Esc stops the whole preferences).  Z clear when answered, N for N.
;------------------------------------------------------------------------------
ask_yes_no:	; from: cmd_search, cmd_preferences, show_cursor_here, cmd_run_mode
	sne	-(sp)                           ; the setting
	bsr.w	print_string                    ; the question
	moveq	#78,d1                          ; N
	tst.b	(sp)+                           ; set?
	beq.s	ask_yes_no_print                ; no
	moveq	#89,d1                          ; Y
ask_yes_no_print:
	bsr.w	print_char                      ; printed
	subq.w	#1,$16(a3)                      ; back on it
	bsr.s	show_cursor_here                ; the cursor there
ask_yes_no_key:
	bsr.w	get_key                         ; a key
	bmi.s	ask_yes_no_key
	cmp.b	#$1b,d1                         ; Esc?
	beq.s	ask_yes_no_escape               ; yes: stop
	cmp.b	#$d,d1                          ; Return?
	beq.s	ask_yes_no_return               ; yes: as it was
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$59,d1                         ; Y?
	beq.s	ask_yes_no_answer
	cmp.b	#$4e,d1                         ; N?
	bne.s	ask_yes_no_key                  ; no: another key
ask_yes_no_answer:
	move.w	d1,-(sp)
	bsr.w	print_char                      ; printed
	bsr.w	new_line                        ; a new line
	move.w	(sp)+,d1
	cmp.b	#$4f,d1                         ; N: minus; Z clear
	rts

;------------------------------------------------------------------------------
; Put the cursor at the current print position of window a3.
;------------------------------------------------------------------------------
show_cursor_here:	; from: ask_yes_no, cmd_run_mode
	moveq	#0,d3
	movem.w	$16(a3),d2-d3                   ; the position
	divu.w	$1a(a3),d3                      ; in lines
	bsr.w	invert_char
ask_yes_no_keep:
	moveq	#0,d1                           ; Z set: as it was
	rts
ask_yes_no_return:	; from: ask_yes_no
	bsr.s	show_cursor_here                ; the cursor
	bsr.w	new_line                        ; a new line
	bra.s	ask_yes_no_keep
ask_yes_no_escape:	; from: ask_yes_no
	addq.l	#4,sp                           ; not back to the question
	bra.w	close_prompt                    ; the prompt off
pref_cartridge:	; from: cmd_preferences
	lea	text_ignore_cartridge(pc),a0    ; "Ignore cartridge area Y/N? "
	tst.b	no_cartridge(a6)
	bsr.s	ask_yes_no                      ; ask
	beq.s	pref_symbol_length
	spl	no_cartridge(a6)
	move.b	no_cartridge(a6),d1
	bsr.w	rom_ranges                      ; the ROM ranges again
pref_symbol_length:
	lea	text_symbol_length(pc),a0       ; "Symbol length"
	bsr.w	print_string
	bsr.w	new_line                        ; a new line
	lea	arguments(a6),a4                ; the line, filled in
	move.b	#$5c,(a4)+                      ; \ for decimal
	moveq	#0,d1
	move.w	symbol_length(a6),d1            ; the symbol length
	lea	put_char_a4(pc),a2
	bsr.w	output_decimal                  ; in decimal
	clr.b	(a4)
	lea	arguments(a6),a4
	bsr.w	string_length
pref_symbol_length_line:
	lea	arguments(a6),a4
	bsr.w	edit_line                       ; edited
	bne.w	pref_done                       ; cancelled
	bsr.w	evaluate_line                   ; worked out
	bne.s	pref_symbol_length_line         ; bad
	cmp.l	#$8,d2                          ; below 8?
	bcs.s	pref_symbol_length_line         ; yes: again
	cmp.l	#$17,d2                         ; over 22?
	bcc.s	pref_symbol_length_line         ; yes: again
	move.w	d2,symbol_length(a6)            ; the symbol length
	bsr.w	new_line
	lea	text_top_of_ram(pc),a0          ; "Top of RAM"
	bsr.w	print_string
	bsr.w	new_line
	lea	arguments(a6),a4                ; the line, filled in
	move.l	phystop(a6),d1                  ; phystop
	bsr.w	put_address                     ; in hex
	clr.b	(a4)
	lea	arguments(a6),a4
	bsr.w	string_length
pref_top_line:
	bsr.w	edit_line                       ; edited
	bne.w	pref_done                       ; cancelled
	bsr.w	evaluate_line                   ; worked out
	beq.s	pref_top_set                    ; good
	lea	arguments(a6),a4
	bra.s	pref_top_line                   ; again
pref_top_set:
	move.l	d2,phystop(a6)                  ; the top of memory
	bsr.w	new_line
	lea	text_save_preferences(pc),a0    ; "Save preferences Y/N? "
	bsr.w	print_string
	bsr.w	show_cursor_here                ; the cursor
pref_save_key:
	bsr.w	get_key                         ; a key
	bmi.s	pref_save_key
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$59,d1                         ; Y?
	bne.s	pref_done                       ; no
	bsr.w	program_state                   ; the program's screen and state
	clr.w	-(sp)                           ; Fcreate("MONST2.INF", 0)
	pea	name_monst_inf(pc)
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	move.l	d0,d3
	bmi.s	pref_error                      ; failed
	lea	settings(pc),a0                 ; the settings
	st	(a0)+                           ; set: read
	move.b	follow_traps(a6),(a0)+          ; follow traps
	move.b	relative_offsets(a6),(a0)+      ; relative offsets
	move.b	ignore_case(a6),(a0)+           ; ignore case
	move.w	symbol_length(a6),(a0)+         ; symbol length
	move.b	screen_timer_on(a6),(a0)+       ; screen timer
	move.b	no_cartridge(a6),(a0)+          ; ignore cartridge
	pea	settings(pc)                    ; Fwrite(handle, 8, settings)
	pea	$8.w                            ; 8 bytes
	move.w	d0,-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	bsr.w	close_file                      ; close
	bsr.w	monst_screen                    ; MonST's screen back
pref_done:
	bra.w	close_prompt                    ; the prompt off
pref_error:
	bsr.w	close_prompt                    ; the prompt off
	bsr.w	show_tos_error                  ; "TOS error: n"
	bra.w	monst_screen                    ; MonST's screen back

;------------------------------------------------------------------------------
; Control-D: "BDOS Breakpoint": stop at a GEMDOS call number (none for an empty line).
;------------------------------------------------------------------------------
cmd_bdos_breakpoint:	; from: command_table
	moveq	#4,d3
	lea	text_bdos_breakpoint(pc),a0     ; "BDOS Breakpoint"
	bsr.w	open_prompt_text                ; the prompt
cmd_bdos_line:
	bsr.w	edit_line                       ; a line
	bne.s	cmd_bdos_done                   ; cancelled
	moveq	#-1,d2                          ; none
	move.b	(a4)+,d1
	beq.s	cmd_bdos_set                    ; empty
	bsr.w	evaluate_line_d1                ; the number
	beq.s	cmd_bdos_set                    ; good
	lea	arguments(a6),a4
	bra.s	cmd_bdos_line                   ; again
cmd_bdos_set:
	move.w	d2,bdos_breakpoint(a6)          ; the GEMDOS call to stop at
cmd_bdos_done:
	bra.w	close_prompt                    ; the prompt off

;------------------------------------------------------------------------------
; Read "start,end,value" into d5, d6 and d2; Z clear when cancelled.
;------------------------------------------------------------------------------
read_three_values:	; from: cmd_copy, cmd_fill
	bsr.w	edit_line                       ; a line
	bne.s	read_three_values_done          ; cancelled
	bsr.w	evaluate                        ; the first
	bne.s	read_three_values_bad           ; bad
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	read_three_values_bad           ; no: bad
	move.l	d2,d5
	bsr.w	evaluate                        ; the second
	bne.s	read_three_values_bad           ; bad
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	read_three_values_bad           ; no: bad
	move.l	d2,d6
	bsr.w	evaluate                        ; the third
	bne.s	read_three_values_bad           ; bad
	tst.b	d1                              ; the end?
	bne.s	read_three_values_bad           ; no: bad
read_three_values_done:
	rts
read_three_values_bad:
	bsr.w	bell                            ; the bell
	lea	arguments(a6),a4
	bra.s	read_three_values               ; again

;------------------------------------------------------------------------------
; I: "Copy start,end,to": copy memory, from the end down when the areas overlap upwards.
;------------------------------------------------------------------------------
cmd_copy:	; from: command_table
	moveq	#4,d3
	lea	text_copy_start_end_to(pc),a0   ; "Copy start,end,to"
	bsr.w	open_prompt_text                ; the prompt
cmd_copy_line:
	lea	arguments(a6),a4
	bsr.s	read_three_values               ; start, end and to
	bne.s	cmd_copy_done                   ; cancelled
	cmp.l	d5,d6                           ; end below start?
	blt.s	cmd_copy_line                   ; yes: again
	movea.l	d2,a2                           ; to
	movea.l	d6,a1                           ; end
	movea.l	d5,a0                           ; start
	sub.l	a0,d6                           ; the length less 1
	beq.s	cmd_copy_done                   ; nothing
	addq.l	#1,d6                           ; the length
	cmpa.l	a0,a2                           ; to above start?
	bcc.s	cmd_copy_down                   ; yes: from the end
cmd_copy_up:
	move.b	(a0)+,(a2)+                     ; a byte
	subq.l	#1,d6
	bne.s	cmd_copy_up
	bra.s	cmd_copy_done
cmd_copy_down:
	addq.l	#1,a1                           ; past the end
	lea	0(a2,d6.l),a2                   ; to's end
cmd_copy_down_loop:
	move.b	-(a1),-(a2)                     ; a byte
	subq.l	#1,d6
	bne.s	cmd_copy_down_loop
cmd_copy_done:	; from: cmd_fill
	bra.w	close_prompt                    ; the prompt off

;------------------------------------------------------------------------------
; W: "Fill start,end,with": fill memory with a byte.
;------------------------------------------------------------------------------
cmd_fill:	; from: command_table
	moveq	#4,d3
	lea	text_fill_start_end_with(pc),a0 ; "Fill start,end,with"
	bsr.w	open_prompt_text                ; the prompt
cmd_fill_line:
	lea	arguments(a6),a4
	bsr.w	read_three_values               ; start, end and the byte
	bne.s	cmd_copy_done                   ; cancelled
	sub.l	d5,d6                           ; the length less 1
	blt.s	cmd_fill_line                   ; negative: again
	movea.l	d5,a0                           ; start
cmd_fill_loop:
	move.b	d2,(a0)+                        ; a byte
	subq.l	#1,d6
	bcc.s	cmd_fill_loop                   ; to the end
	bra.s	cmd_copy_done

;------------------------------------------------------------------------------
; D: "Set current drive/directory": Dsetdrv for a drive letter and colon, then Dsetpath.
;------------------------------------------------------------------------------
cmd_directory:	; from: command_table
	moveq	#4,d3
	lea	text_set_drive_directory(pc),a0 ; "Set current drive/directory"
	bsr.w	open_prompt_text                ; the prompt
	bsr.w	edit_line_start                 ; a line
	bne.s	cmd_directory_done              ; cancelled
	movea.l	a4,a0
	tst.b	(a4)                            ; empty?
	beq.s	cmd_directory_done              ; yes
	cmpi.b	#$3a,1(a4)                      ; a drive?
	bne.s	cmd_directory_path              ; no
	move.b	(a4),d0                         ; the letter
	andi.b	#$df,d0                         ; upper case
	subi.b	#$41,d0                         ; A-Z
	bcs.s	cmd_directory_bad_drive         ; bad
	cmp.b	#$20,d0
	bcc.s	cmd_directory_bad_drive         ; bad
	move.w	d0,-(sp)                        ; Dsetdrv(drive)
	move.w	#$e,-(sp)
	trap	#1                              ; Dsetdrv
	addq.l	#4,sp
	lea	2(a4),a0                        ; past it
cmd_directory_path:
	move.l	a0,-(sp)                        ; Dsetpath(path)
	move.w	#$3b,-(sp)
	trap	#1                              ; Dsetpath
	addq.l	#6,sp
	tst.w	d0                              ; all right?
	bne.s	cmd_directory_error             ; no
cmd_directory_done:
	bra.w	close_prompt                    ; the prompt off
cmd_directory_bad_drive:
	moveq	#-46,d0                         ; -46: invalid drive
cmd_directory_error:
	move.w	d0,-(sp)
	bsr.w	close_prompt                    ; the prompt off
	move.w	(sp)+,d0
	bra.w	show_tos_error                  ; "TOS error: n"

;------------------------------------------------------------------------------
; S: "Save binary, filename" then "start address,end": save memory to a file.
;------------------------------------------------------------------------------
cmd_save_binary:	; from: command_table
	moveq	#7,d3
	lea	text_save_binary_filename(pc),a0 ; "Save binary, filename"
	bsr.w	open_prompt_text                ; the prompt
	bsr.w	edit_line                       ; a name
	bne.s	prompt_off                      ; cancelled
	tst.b	(a4)                            ; empty?
	beq.s	prompt_off                      ; yes: cancelled
	bsr.w	two_new_lines                   ; a new line
	lea	text_start_address_end(pc),a0   ; "start address,end"
	bsr.w	print_string
	bsr.w	new_line
	clr.b	data_areas(a6)                  ; an empty line
	moveq	#0,d4                           ; no length
	bra.s	cmd_save_line
cmd_save_bad:
	bsr.w	bell                            ; the bell
cmd_save_line:
	lea	data_areas(a6),a4
	bsr.w	edit_line                       ; a line
	bne.s	prompt_off                      ; cancelled
	bsr.w	evaluate                        ; the start
	bne.s	cmd_save_bad                    ; bad
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_save_bad                    ; no: bad
	move.l	d2,d5
	bsr.w	evaluate                        ; the end
	bne.s	cmd_save_bad                    ; bad
	tst.b	d1                              ; the end of the line?
	bne.s	cmd_save_bad                    ; no: bad
	move.l	d2,d4
	sub.l	d5,d4                           ; the length less 1
	blt.s	cmd_save_bad                    ; negative: bad
	addq.l	#1,d4                           ; the length
	bsr.w	program_state                   ; the program's screen and state
	lea	arguments(a6),a0                ; the name
	bsr.w	create_file                     ; create it
	bne.s	cmd_save_error                  ; failed
	movea.l	d5,a0                           ; the start
	bsr.w	write_file                      ; write it
	bne.s	cmd_save_error                  ; failed
	bsr.w	close_file                      ; close
	bsr.w	monst_screen                    ; MonST's screen back
	bra.s	prompt_off
cmd_save_error:
	bsr.w	monst_screen                    ; MonST's screen back
	move.w	d0,-(sp)
	bsr.s	prompt_off                      ; the prompt off
	move.w	(sp)+,d0
	bra.w	show_tos_error                  ; "TOS error: n"

;------------------------------------------------------------------------------
; Close the prompt.
;------------------------------------------------------------------------------
prompt_off:	; from: cmd_save_binary
	bra.w	close_prompt

;------------------------------------------------------------------------------
; R: "Run: Go,Until,Instruction,Slow": G at full speed, U until an expression is true, I for a number of
; instructions, S slowly; then "Watch Y/N?" for the slow ways.
;------------------------------------------------------------------------------
cmd_run_mode:	; from: command_table
	moveq	#7,d3
	bsr.w	open_prompt
	lea	text_run_mode(pc),a0            ; "Run: Go,Until,Instruction,Slow "
	bsr.w	print_string
	bsr.w	show_cursor_here                ; the cursor
cmd_run_mode_key:
	bsr.w	get_key                         ; a key
	cmp.b	#$1b,d1                         ; Esc?
	beq.w	prompt_off_2                    ; yes: cancelled
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$47,d1                         ; G?
	beq.s	cmd_run_mode_set
	cmp.b	#$55,d1                         ; U?
	beq.s	cmd_run_mode_set
	cmp.b	#$49,d1                         ; I?
	beq.s	cmd_run_mode_set
	cmp.b	#$53,d1                         ; S?
	bne.s	cmd_run_mode_key                ; no: another key
cmd_run_mode_set:
	move.w	d1,-(sp)
	bsr.w	print_char                      ; printed
	bsr.w	two_new_lines                   ; a new line
	move.w	(sp)+,d1
	cmp.b	#$47,d1                         ; G?
	beq.s	cmd_run_mode_go
	cmp.b	#$53,d1                         ; S?
	beq.s	cmd_run_mode_slow
	cmp.b	#$55,d1                         ; U?
	beq.s	cmd_run_mode_until
	lea	arguments(a6),a4                ; I: the count, filled in
	move.l	run_count(a6),d1                ; the last count
	beq.s	cmd_run_mode_count              ; none
	bsr.w	put_hex                         ; in hex
cmd_run_mode_count:
	clr.b	(a4)
	lea	arguments(a6),a4
	bsr.s	string_length
cmd_run_mode_count_line:
	lea	arguments(a6),a4
	bsr.w	edit_line                       ; edited
	bne.s	prompt_off_2                    ; cancelled
	bsr.w	evaluate_line                   ; worked out
	bne.s	cmd_run_mode_count_line         ; bad: again
	move.l	d2,run_count(a6)                ; the count
	moveq	#3,d7                           ; mode 3: a count
	bra.s	cmd_run_mode_watch
cmd_run_mode_until:
	lea	until_condition(a6),a4          ; the last condition
	bsr.s	string_length
cmd_run_mode_until_line:
	lea	until_condition(a6),a4
	bsr.w	edit_line                       ; edited
	bne.s	prompt_off_2                    ; cancelled
	bsr.w	check_expression                ; checked
	bne.s	cmd_run_mode_until_line         ; bad: again
	moveq	#2,d7                           ; mode 2: until
	bra.s	cmd_run_mode_watch
cmd_run_mode_go:
	bsr.s	prompt_off_2                    ; the prompt off
	bra.w	cmd_run                         ; run
cmd_run_mode_slow:
	moveq	#1,d7                           ; mode 1: slowly
cmd_run_mode_watch:
	bsr.w	two_new_lines                   ; a new line
	lea	text_watch(pc),a0               ; "Watch Y/N? "
	tst.b	watch(a6)                       ; the setting
	bsr.w	ask_yes_no                      ; ask
	beq.s	cmd_run_mode_go_slow            ; cancelled: as it was
	spl	watch(a6)
cmd_run_mode_go_slow:
	move.w	d7,-(sp)
	bsr.s	prompt_off_2                    ; the prompt off
	move.w	(sp)+,d3                        ; the mode
	bra.w	run_with_mode                   ; run that way

;------------------------------------------------------------------------------
; Close the prompt.
;------------------------------------------------------------------------------
prompt_off_2:	; from: cmd_run_mode
	bra.w	close_prompt

;------------------------------------------------------------------------------
; d4 = the length of the string at a4.
;------------------------------------------------------------------------------
string_length:	; from: show_cursor_here, cmd_run_mode
	move.l	a4,d4
string_length_loop:
	tst.b	(a4)+                           ; find its end
	bne.s	string_length_loop
	exg	d4,a4
	sub.l	a4,d4
	subq.w	#1,d4                           ; less the 0
	rts

;------------------------------------------------------------------------------
; Help: a full screen window showing the program's areas and the breakpoints; Alt keys work in it, any other
; key closes it.
;------------------------------------------------------------------------------
cmd_help:	; from: command_loop
	lea	text_help(pc),a2                ; "Help"
	bsr.w	open_full_window                ; full screen
	lea	draw_help(pc),a0                ; its contents
	move.l	a0,$48(a3)                      ; drawn by draw_help
	bsr.w	draw_window_contents            ; draw it
cmd_help_key:
	bsr.w	get_key                         ; a key
	bpl.s	cmd_help_done                   ; not Alt
	bsr.w	window_command                  ; a window command
	bra.s	cmd_help_key
cmd_help_done:
	bsr.w	close_prompt                    ; the full screen off
	bra.w	command_loop

;------------------------------------------------------------------------------
; The help window: "Text:", "Data:" and "BSS :" with their start and length, then "Current Breakpoints:"
; with each one's address, symbol, instruction and, for a conditional one, its condition.
;------------------------------------------------------------------------------
draw_help:	; from: cmd_help
	bsr.w	clear_window                    ; clear it
	moveq	#19,d4                          ; "Text: "
	lea	prog_text(a6),a2                ; the program's areas
draw_help_area:
	move.w	d4,d1
	bsr.w	print_message                   ; its name
	move.l	(a2)+,d2                        ; the start
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_space
	bsr.w	print_space
	move.l	(a2)+,d2                        ; the length
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_newline                   ; a new line
	addq.w	#1,d4                           ; the next
	cmp.w	#$16,d4                         ; three of them?
	bne.s	draw_help_area                  ; no
	moveq	#22,d1                          ; "Current Breakpoints:"
	bsr.w	print_message
	moveq	#7,d7                           ; 8 breakpoints
	lea	breakpoints(a6),a4              ; the breakpoint table
draw_help_breakpoint:
	move.w	6(a4),d1                        ; its type
	beq.s	draw_help_skip                  ; none
	move.l	(a4),d2                         ; its address
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_space                     ; a space
	moveq	#-1,d2                          ; no symbol
	tst.b	screen_mode(a6)                 ; low resolution?
	beq.s	draw_help_instruction           ; yes
	moveq	#22,d2                          ; a symbol column
	move.l	(a4),d0                         ; the address
	bsr.w	find_symbol                     ; a symbol for it?
	beq.s	draw_help_instruction           ; no
	bsr.w	print_symbol_name               ; printed
draw_help_instruction:
	addq.b	#1,d2
	bsr.w	print_spaces                    ; to the column
	movea.l	(a4),a2                         ; the address
	bsr.w	print_instruction               ; its instruction
	cmpi.w	#$4,6(a4)                       ; conditional?
	bne.s	draw_help_next                  ; no
	bsr.w	print_newline                   ; a new line
	moveq	#9,d2
	bsr.w	print_spaces                    ; to the column
	moveq	#63,d1                          ; ?
	bsr.w	print_char                      ; printed
	lea	$c(a4),a2                       ; the condition
draw_help_condition:
	move.b	(a2)+,d1                        ; a character
	beq.s	draw_help_next                  ; the end
	bsr.w	print_char                      ; printed
	bra.s	draw_help_condition
draw_help_next:
	bsr.w	print_newline                   ; a new line
	bsr.w	print_newline
draw_help_skip:
	lea	$48(a4),a4                      ; the next breakpoint
	dbra	d7,draw_help_breakpoint
	rts

;------------------------------------------------------------------------------
; P: "Disassemble start,end" to the printer or a file, with a "Cross-reference list" area for labels (start,end;
; the labels are made in a first pass), "Data start,end<,size>" areas shown as DC.B, DC.W or DC.L, and a
; "Filename" (none for the printer).
;------------------------------------------------------------------------------
cmd_disassemble:	; from: command_table
	lea	text_disassemble_start_end(pc),a0 ; "Disassemble start,end"
	st	listing_mode(a6)                ; labels on
	moveq	#10,d3
	bsr.w	open_prompt_text                ; the prompt
	clr.w	listing_file(a6)                ; to the printer
	bra.s	cmd_disassemble_range
cmd_disassemble_bad:
	bsr.w	bell                            ; the bell
cmd_disassemble_range:
	lea	arguments(a6),a4
	bsr.w	edit_line                       ; a line
	bne.w	cmd_disassemble_done            ; cancelled
	bsr.w	evaluate                        ; the start
	bne.s	cmd_disassemble_bad             ; bad
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_disassemble_bad             ; no: bad
	addq.l	#1,d2                           ; even
	andi.b	#$fe,d2
	move.l	d2,disasm_start(a6)             ; the start
	bsr.w	evaluate                        ; the end
	bne.s	cmd_disassemble_bad             ; bad
	cmp.l	disasm_start(a6),d2             ; above the start?
	ble.s	cmd_disassemble_bad             ; no: bad
	move.l	d2,disasm_end(a6)               ; the end
	movea.l	d2,a2
	bsr.w	check_address                   ; readable?
	bne.s	cmd_disassemble_bad             ; no: bad
	movea.l	disasm_start(a6),a2             ; the start
	bsr.w	check_address                   ; readable?
	bne.s	cmd_disassemble_bad             ; no: bad
	bsr.w	new_line
	moveq	#24,d1                          ; "Cross-reference list"
	bsr.w	print_message
	bsr.w	new_line
	clr.b	arguments(a6)                   ; an empty line
	moveq	#0,d4
	bra.s	cmd_disassemble_xref
cmd_disassemble_xref_bad:
	bsr.w	bell                            ; the bell
cmd_disassemble_xref:
	lea	arguments(a6),a4
	bsr.w	edit_line                       ; a line
	bne.w	cmd_disassemble_done            ; cancelled
	sf	xref_pass(a6)                   ; no cross-reference
	tst.b	(a4)                            ; empty?
	beq.s	cmd_disassemble_data            ; yes: none
	bsr.w	evaluate                        ; its start
	bne.s	cmd_disassemble_xref_bad        ; bad
	move.l	d2,xref_start(a6)
	clr.l	xref_end(a6)                    ; no end
	tst.b	d1                              ; the end of the line?
	beq.s	cmd_disassemble_xref_set        ; yes
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_disassemble_xref_bad        ; no: bad
	bsr.w	evaluate                        ; its end
	bne.s	cmd_disassemble_xref_bad        ; bad
	tst.b	d1                              ; the end of the line?
	bne.s	cmd_disassemble_xref_bad        ; no: bad
	cmp.l	xref_start(a6),d2               ; above the start?
	bcs.s	cmd_disassemble_xref_bad        ; no: bad
	move.l	d2,xref_end(a6)
cmd_disassemble_xref_set:
	move.l	xref_start(a6),d2               ; the start
	btst	#$0,d2                          ; odd?
	bne.s	cmd_disassemble_xref_bad        ; yes: bad
	move.l	d2,d0
	bsr.w	check_ram                       ; in RAM?
	bne.s	cmd_disassemble_xref_bad        ; no: bad
	addq.b	#1,xref_pass(a6)                ; the first pass on
	movea.l	d2,a0
	clr.l	(a0)                            ; an empty list
cmd_disassemble_data:
	bsr.w	new_line
	moveq	#23,d1                          ; "Data start,end<,size>"
	bsr.w	print_message
	bsr.w	new_line
	lea	data_areas(a6),a5               ; the data areas
cmd_disassemble_data_line:
	moveq	#0,d4
	clr.b	arguments(a6)                   ; an empty line
	bra.s	cmd_disassemble_data_read
cmd_disassemble_data_bad:
	bsr.w	bell                            ; the bell
cmd_disassemble_data_read:
	lea	arguments(a6),a4
	bsr.w	edit_line                       ; a line
	bne.w	cmd_disassemble_done            ; cancelled
	tst.b	(a4)                            ; empty?
	beq.s	cmd_disassemble_file            ; yes: no more
	bsr.w	evaluate                        ; the start
	bne.s	cmd_disassemble_data_bad        ; bad
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_disassemble_data_bad        ; no: bad
	move.l	d2,(a5)
	bsr.w	evaluate                        ; the end
	bne.s	cmd_disassemble_data_bad        ; bad
	cmp.l	(a5),d2                         ; above the start?
	ble.s	cmd_disassemble_data_bad        ; no: bad
	moveq	#0,d0                           ; bytes
	tst.b	d1                              ; the end of the line?
	beq.s	cmd_disassemble_data_add        ; yes
	cmp.b	#$2c,d1                         ; a comma?
	bne.s	cmd_disassemble_data_bad        ; no: bad
	move.b	(a4)+,d1                        ; the size
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$42,d1                         ; B?
	beq.s	cmd_disassemble_data_add
	moveq	#1,d0                           ; words
	cmp.b	#$57,d1                         ; W?
	beq.s	cmd_disassemble_data_add
	cmp.b	#$4c,d1                         ; L?
	bne.s	cmd_disassemble_data_bad        ; no: bad
	moveq	#2,d0                           ; longs
cmd_disassemble_data_add:
	move.l	(a5),d1                         ; the start
	addq.l	#1,d1
	andi.b	#$fe,d1                         ; even
	move.l	d1,(a5)+
	addq.l	#1,d2                           ; the end
	andi.b	#$fe,d2                         ; even
	move.l	d2,(a5)+
	move.w	d0,(a5)+                        ; the size
	move.w	#$4,$16(a3)
	bsr.w	clear_to_eol
	bra.s	cmd_disassemble_data_line       ; the next
cmd_disassemble_file:
	clr.l	(a5)                            ; the list's end
	bsr.w	new_line
	moveq	#25,d1                          ; "Filename"
	bsr.w	print_message
	bsr.w	new_line
	clr.b	arguments(a6)                   ; an empty line
	moveq	#0,d4
cmd_disassemble_file_line:
	lea	arguments(a6),a4
	bsr.w	edit_line                       ; a line
	bne.w	cmd_disassemble_done            ; cancelled
	tst.b	(a4)                            ; empty: the printer
	beq.s	cmd_disassemble_start           ; yes
	bsr.w	program_state                   ; the program's screen and state
	movea.l	a4,a0                           ; the name
	bsr.w	create_file                     ; create it
	beq.s	cmd_disassemble_file_open       ; all right
	bsr.w	monst_screen                    ; MonST's screen back
	bra.s	cmd_disassemble_file_line       ; again
cmd_disassemble_file_open:
	bsr.w	monst_screen                    ; MonST's screen back
	bsr.w	output_to_file
cmd_disassemble_start:
	movea.l	disasm_start(a6),a5             ; the start
	tst.b	xref_pass(a6)                   ; a first pass?
	beq.s	cmd_disassemble_output          ; no
cmd_disassemble_pass1:
	cmpa.l	disasm_end(a6),a5               ; the end?
	bgt.s	cmd_disassemble_pass2           ; yes
	bsr.w	find_data_area                  ; in a data area?
	bne.s	cmd_disassemble_pass1_code      ; no: an instruction
	move.b	9(a2),d0                        ; its size
	beq.s	cmd_disassemble_pass1_bytes     ; bytes
	subq.b	#1,d0
	beq.s	cmd_disassemble_pass1_words     ; words
cmd_disassemble_pass1_longs:
	move.l	(a5),d0                         ; a long: a label for it
	bsr.w	find_symbol
	addq.l	#4,a5
	cmpa.l	4(a2),a5                        ; to the area's end
	blt.s	cmd_disassemble_pass1_longs
	bra.s	cmd_disassemble_pass1
cmd_disassemble_pass1_words:
	addq.l	#2,a5
	cmpa.l	4(a2),a5                        ; to the area's end
	blt.s	cmd_disassemble_pass1_words
	bra.s	cmd_disassemble_pass1
cmd_disassemble_pass1_bytes:
	addq.l	#1,a5
	cmpa.l	4(a2),a5                        ; to the area's end
	blt.s	cmd_disassemble_pass1_bytes
	bra.s	cmd_disassemble_pass1
cmd_disassemble_pass1_code:
	bsr.w	disassemble                     ; disassembled for its labels
	bra.s	cmd_disassemble_pass1
cmd_disassemble_pass2:
	st	xref_pass(a6)                   ; the labels are made
	movea.l	disasm_start(a6),a5             ; from the start again
cmd_disassemble_output:
	tst.w	listing_file(a6)                ; to a file?
	bne.s	cmd_disassemble_print           ; yes
	bsr.w	printer_ready                   ; the printer ready?
	bne.s	cmd_disassemble_print           ; yes
	sf	output_on(a6)
	sf	xref_pass(a6)
	bsr.w	close_prompt                    ; the prompt off
	lea	text_printer_not_responding(pc),a0 ; "Printer not responding"
	bsr.w	show_message                    ; shown
	bra.s	cmd_disassemble_close
cmd_disassemble_print:
	st	output_on(a6)                   ; output on
	bsr.w	print_newline                   ; a new line
	bsr.s	disassemble_listing             ; the listing
cmd_disassemble_done:
	sf	output_on(a6)                   ; output off
	sf	xref_pass(a6)                   ; labels off
	bsr.w	close_prompt                    ; the prompt off
cmd_disassemble_close:
	tst.w	listing_file(a6)                ; a file?
	bne.w	close_output_file               ; yes: close it
	rts

;------------------------------------------------------------------------------
; Z set (and a2 = its entry) when a5 is in one of the data areas.
;------------------------------------------------------------------------------
find_data_area:	; from: cmd_disassemble, disassemble_listing
	lea	data_areas(a6),a2               ; the data areas
find_data_area_loop:
	move.l	(a2),d0                         ; its start
	beq.s	find_data_area_none             ; the end of the list
	cmpa.l	d0,a5                           ; below it?
	blt.s	find_data_area_next             ; yes
	cmpa.l	4(a2),a5                        ; past its end?
	bge.s	find_data_area_next             ; yes
	moveq	#0,d0                           ; in it
	rts
find_data_area_next:
	lea	$a(a2),a2                       ; the next, 10 bytes on
	bra.s	find_data_area_loop
find_data_area_none:
	moveq	#-1,d0                          ; not in one
	rts

;------------------------------------------------------------------------------
; The listing from a5 to the end: each line an instruction, or up to 8 bytes, 4 words or 2 longs of a data area
; as DC.B, DC.W or DC.L, stopping at a label.
;------------------------------------------------------------------------------
disassemble_listing:	; from: cmd_disassemble
	cmpa.l	disasm_end(a6),a5               ; the end?
	ble.s	disassemble_listing_line        ; no
disassemble_listing_done:
	rts
disassemble_listing_line:
	tst.b	output_on(a6)                   ; output on?
	bpl.s	disassemble_listing_done        ; no
	bsr.s	find_data_area                  ; in a data area?
	bne.w	disassemble_listing_code        ; no: an instruction
	move.l	a5,-(sp)
	lea	line_buffer(a6),a4              ; the line
	move.l	#$44432e42,(a4)+                ; "DC.B"
	subq.l	#1,a4                           ; over the B
	move.b	9(a2),d0                        ; the size
	beq.s	disassemble_listing_bytes       ; bytes
	subq.w	#1,d0
	beq.s	disassemble_listing_words       ; words
	move.b	#$4c,(a4)+                      ; L
	move.b	#$20,(a4)+
	moveq	#1,d4                           ; 2 longs
disassemble_listing_longs:
	move.l	(a5)+,d1                        ; a long
	bsr.w	put_address                     ; in hex
	move.b	#$2c,(a4)+                      ; a comma
	move.l	a5,d0
	bsr.w	find_symbol                     ; a label there?
	bne.s	disassemble_listing_data_end    ; yes: the line ends
	cmpa.l	4(a2),a5                        ; the area's end?
	dbge	d4,disassemble_listing_longs    ; no: on
	bra.s	disassemble_listing_data_end
disassemble_listing_words:
	move.b	#$57,(a4)+                      ; W
	move.b	#$20,(a4)+
	moveq	#3,d4                           ; 4 words
disassemble_listing_words_loop:
	move.w	(a5)+,d1                        ; a word
	bsr.w	put_word                        ; in hex
	move.b	#$2c,(a4)+                      ; a comma
	move.l	a5,d0
	bsr.w	find_symbol                     ; a label there?
	bne.s	disassemble_listing_data_end    ; yes: the line ends
	cmpa.l	4(a2),a5                        ; the area's end?
	dbge	d4,disassemble_listing_words_loop ; no: on
	bra.s	disassemble_listing_data_end
disassemble_listing_bytes:
	move.b	#$42,(a4)+                      ; B
	move.b	#$20,(a4)+
	moveq	#7,d4                           ; 8 bytes
disassemble_listing_bytes_loop:
	move.b	(a5)+,d1                        ; a byte
	bsr.w	put_byte                        ; in hex
	move.b	#$2c,(a4)+                      ; a comma
	move.l	a5,d0
	bsr.w	find_symbol                     ; a label there?
	bne.s	disassemble_listing_data_end    ; yes: the line ends
	cmpa.l	4(a2),a5                        ; the area's end?
	dbge	d4,disassemble_listing_bytes_loop ; no: on
disassemble_listing_data_end:
	move.b	#$d,-$1(a4)                     ; the last comma a Return
	movea.l	(sp)+,a4                        ; the line's address
	bra.s	disassemble_listing_print
disassemble_listing_code:
	movem.l	d3-d7/a5,-(sp)
	bsr.w	disassemble                     ; disassembled
	movem.l	(sp)+,d3-d7/a4                  ; a4 = its address
disassemble_listing_print:
	move.l	a5,d4                           ; the length
	sub.l	a4,d4
	bsr.s	listing_address                 ; the address, bytes and label
	lea	line_buffer(a6),a4              ; the line
	moveq	#-1,d2                          ; the column
disassemble_listing_char:
	addq.b	#1,d2
	move.b	(a4)+,d1                        ; a character
	cmp.b	#$d,d1                          ; the end?
	beq.s	disassemble_listing_eol         ; yes
	cmp.b	#$20,d1                         ; a space?
	bne.s	disassemble_listing_put         ; no
	moveq	#7,d0                           ; to column 8
	sub.b	d2,d0
	bcs.s	disassemble_listing_put         ; past it
	moveq	#9,d1                           ; a tab
	tst.w	listing_file(a6)                ; to a file?
	bne.s	disassemble_listing_tab         ; yes: the tab
	move.b	d0,d2
	bsr.w	print_spaces                    ; spaces to the column
	moveq	#32,d1                          ; the space
disassemble_listing_tab:
	moveq	#8,d2                           ; past column 8
disassemble_listing_put:
	bsr.w	print_char                      ; printed
	bra.s	disassemble_listing_char
disassemble_listing_eol:
	bsr.w	print_newline                   ; a new line
	bra.w	disassemble_listing             ; the next line

;------------------------------------------------------------------------------
; Start a listing line: to the printer the address and up to 10 of its d4 bytes in hex and a label column; to a
; file only the label and a tab.
;------------------------------------------------------------------------------
listing_address:	; from: disassemble_listing
	tst.w	listing_file(a6)                ; to a file?
	bne.s	listing_address_file            ; yes
	move.l	a4,d2                           ; the address
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_space                     ; a space
	moveq	#0,d3
listing_address_bytes:
	cmp.w	d4,d3                           ; all of them?
	bge.s	listing_address_pad             ; yes
	move.b	0(a4,d3.w),d2                   ; a byte
	bsr.w	print_hex_byte                  ; in hex
listing_address_next:
	addq.w	#1,d3
	cmp.w	#$a,d3                          ; 10 of them?
	bne.s	listing_address_bytes           ; no
	bra.s	listing_address_label
listing_address_pad:
	bsr.w	print_space                     ; two spaces
	bsr.w	print_space
	bra.s	listing_address_next
listing_address_label:
	bsr.w	print_space                     ; a space
	moveq	#12,d2                          ; the label column
	move.l	a4,d0                           ; the address
	bsr.w	find_symbol                     ; a symbol for it?
	beq.s	listing_address_column          ; no
	bsr.w	print_symbol_name               ; printed
listing_address_column:
	addq.b	#1,d2
	bra.w	print_spaces                    ; to the column
listing_address_file:
	move.l	a4,d0                           ; the address
	bsr.w	find_symbol                     ; a symbol for it?
	beq.s	listing_address_tab             ; no
	movea.l	d0,a4
	bsr.w	print_symbol                    ; printed
listing_address_tab:
	moveq	#9,d1                           ; a tab
	bra.w	print_char                      ; printed

;------------------------------------------------------------------------------
; Undo with Alternate held resets the machine through the reset vector.
;------------------------------------------------------------------------------
undo_reset:	; from: command_loop
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	bsr.w	bios
	addq.l	#4,sp
	btst	#$3,d0                          ; Alternate?
	beq.w	command_loop                    ; no
	ori.w	#$700,sr                        ; interrupts off
	movea.l	$0.w,sp                         ; the reset stack
	movea.l	$4.w,a0                         ; the reset address
	jmp	(a0)                            ; reset

;------------------------------------------------------------------------------
; Two new lines in the window a3.
;------------------------------------------------------------------------------
two_new_lines:	; from: cmd_save_binary, cmd_run_mode
	pea	new_line(pc)

;------------------------------------------------------------------------------
; A new line in the window a3: column 4, one character height down.
;------------------------------------------------------------------------------
new_line:                                       ; from: window_evaluate, cmd_query_port, cmd_write_port, cmd_search,
                                                ;   ask_yes_no, show_cursor_here, 5 more
	move.w	#$4,$16(a3)                     ; column 4
	move.w	$1a(a3),d0                      ; the character height
	add.w	d0,$18(a3)                      ; down
	rts

;------------------------------------------------------------------------------
; Control-L: "Executable file to load" and its "Command line", then load it (not when one is loaded).
;------------------------------------------------------------------------------
cmd_load_program:	; from: print_wait, command_table
	tst.b	prog_loaded(a6)                 ; a program loaded?
	bne.s	cmd_load_program_done           ; yes: not again
	moveq	#7,d3
	lea	text_executable_file_to_load(pc),a0 ; "Executable file to load"
	bsr.w	open_prompt_text                ; the prompt
	bsr.w	edit_line_start                 ; a name
	bne.s	cmd_load_program_cancel         ; cancelled
	tst.b	(a4)                            ; empty?
	beq.s	cmd_load_program_cancel         ; yes: cancelled
	bsr.s	new_line
	bsr.s	new_line
	lea	text_command_line(pc),a0        ; "Command line"
	bsr.w	print_string
	bsr.s	new_line
	lea	data_areas+1(a6),a4             ; its text
	clr.b	(a4)                            ; empty
	bsr.w	edit_line_start                 ; a line
	bne.s	cmd_load_program_cancel         ; cancelled
	movea.l	a4,a0
cmd_load_program_length:
	tst.b	(a0)+                           ; find its end
	bne.s	cmd_load_program_length
	move.l	a0,d0
	sub.l	a4,d0
	subq.l	#1,d0                           ; its length
	move.b	d0,-(a4)                        ; in front: a counted string
	bsr.w	close_prompt                    ; the prompt off
	lea	arguments(a6),a3                ; the name
	bra.s	load_program                    ; load it
cmd_load_program_cancel:
	bra.w	close_prompt                    ; the prompt off
cmd_load_program_done:
	rts

;------------------------------------------------------------------------------
; Load the program named at a3 with the command line a4: .PRG, .TTP and .TOS are tried when it is not found as
; it is.  Its symbols are read and relocated, a breakpoint set at its start, and it is run with Pexec 4; when
; it ends, "Program terminated".
;------------------------------------------------------------------------------
load_program:	; from: print_wait, cmd_load_program
	bsr.w	program_state                   ; the program's screen and state
	lea	program_extensions(pc),a5       ; the extensions to try
	bra.s	load_program_open               ; try the name as it is
load_program_extension:
	movea.l	a3,a0                           ; the name
	moveq	#46,d0                          ; .
load_program_find_dot:
	tst.b	(a0)                            ; the end?
	beq.s	load_program_add_dot            ; yes: add one
	cmp.b	(a0)+,d0                        ; the dot?
	bne.s	load_program_find_dot           ; no: on
	bra.s	load_program_set_extension      ; yes: the extension after it
load_program_add_dot:
	move.b	#$2e,(a0)+                      ; a dot
load_program_set_extension:
	move.b	(a5)+,(a0)+                     ; the extension
	move.b	(a5)+,(a0)+
	move.b	(a5)+,(a0)+
	clr.b	(a0)                            ; ended
load_program_open:
	movea.l	a3,a0                           ; the name
	bsr.w	open_file                       ; open it
	beq.s	load_program_header             ; found
	cmp.w	#$ffdf,d0                       ; -33: not found?
	bne.w	load_program_error              ; no: the error
	tst.b	(a5)                            ; more extensions?
	bne.s	load_program_extension          ; yes: the next
	bra.w	load_program_error              ; no: the error
program_extensions:
	dc.b	'PRGTTPTOS',0                   ; "PRG", "TTP", "TOS"
load_program_header:
	lea	line_buffer(a6),a0              ; the header
	moveq	#28,d4                          ; 28 bytes
	bsr.w	read_file                       ; read
	bne.s	load_program_error              ; failed
	move.l	symbols(a6),d0                  ; old symbols?
	beq.s	load_program_free               ; no
	movea.l	d0,a0
	bsr.w	mfree                           ; freed
	clr.l	symbols(a6)
load_program_free:
	move.l	symbol_hash(a6),d0
	beq.s	load_program_close
	movea.l	d0,a0
	bsr.w	mfree                           ; freed
	clr.l	symbol_hash(a6)
load_program_close:
	bsr.w	close_file                      ; close
	move.l	line_buffer+14(a6),d0           ; the symbol table's length
	beq.s	load_program_pexec              ; none
	addq.l	#2,d0                           ; + an end marker
	bsr.w	malloc                          ; Malloc
	move.l	d0,symbols(a6)                  ; the symbols' block
	beq.s	load_program_pexec              ; none
	move.l	line_buffer+14(a6),d0           ; its length
	bsr.w	alloc_symbol_hash
load_program_pexec:
	movea.l	basepage(a6),a0                 ; MonST's basepage
	move.l	$2c(a0),-(sp)                   ; Pexec(3, name, command line, MonST's environment): load only
	move.l	a4,-(sp)
	move.l	a3,-(sp)
	move.w	#$3,-(sp)
	move.w	#$4b,-(sp)
	trap	#1                              ; Pexec
	lea	$10(sp),sp
	tst.l	d0                              ; loaded?
	bpl.s	load_program_loaded             ; yes
	bra.s	load_program_error
	moveq	#-39,d0                         ; never reached
load_program_error:
	move.l	d0,d1
	bsr.w	monst_screen                    ; MonST's screen back
	move.l	d1,d0
	bra.w	show_tos_error                  ; "TOS error: n"
load_program_loaded:
	move.l	d0,prog_basepage(a6)            ; its basepage
	st	prog_loaded(a6)                 ; a program loaded
	movea.l	a3,a0                           ; the name
	bsr.w	open_file                       ; open it again
	bne.w	run_program                     ; failed: no symbols
	move.l	line_buffer+14(a6),d0           ; the symbol table's length
	beq.w	load_program_symbols_done       ; none
	divu.w	#$e,d0                          ; a whole number of 14 byte entries?
	swap	d0
	tst.w	d0
	bne.w	load_program_symbols_done       ; no: no symbols
	moveq	#28,d4                          ; the header
	add.l	line_buffer+2(a6),d4            ; + text
	add.l	line_buffer+6(a6),d4            ; + data
	bsr.w	seek_file                       ; to the symbols
	bne.w	load_program_symbols_done       ; failed
	movea.l	symbols(a6),a0                  ; the block
	move.l	a0,d0
	beq.w	load_program_symbols_done       ; none
	move.l	line_buffer+14(a6),d4           ; the length
	bsr.w	read_file                       ; read them
	bne.w	load_program_symbols_done       ; failed
	movea.l	symbols(a6),a0                  ; the symbols
	move.l	line_buffer+14(a6),d0
	divu.w	#$e,d0                          ; the entry count
	subq.w	#1,d0
	movea.l	prog_basepage(a6),a1            ; the basepage
	bsr.s	relocate_symbols                ; relocated
	bsr.w	fill_symbol_hash
	bra.s	load_program_symbols_done

;------------------------------------------------------------------------------
; Relocate the d0+1 symbol entries at a0 by the basepage a1 by their types: text, data and BSS symbols get the
; section's start added; others (and equates, registers, externals) are marked $ff to be left out.  The entry
; after a long name's (type $48) is its second part.  The list ends with a 0 word.
;------------------------------------------------------------------------------
relocate_symbols:	; from: load_program, run_from_editor
	move.b	8(a0),d1                        ; the type's high byte
	lsl.b	#1,d1                           ; defined?
	bcc.s	relocate_symbols_skip           ; no: left out
	lsl.b	#1,d1                           ; an equate?
	bcs.s	relocate_symbols_skip           ; yes: left out
	lsl.b	#2,d1                           ; a register or global?
	bcs.s	relocate_symbols_skip           ; yes: left out
	lsl.b	#1,d1
	move.l	$10(a1),d2                      ; the data's start
	lsl.b	#1,d1                           ; data?
	bcs.s	relocate_symbols_add            ; yes
	move.l	8(a1),d2                        ; the text's start
	lsl.b	#1,d1                           ; text?
	bcs.s	relocate_symbols_add            ; yes
	move.l	$18(a1),d2                      ; the BSS's start
	lsl.b	#1,d1                           ; BSS?
	bcc.s	relocate_symbols_skip           ; no: left out
relocate_symbols_add:
	add.l	d2,$a(a0)                       ; relocated
	clr.b	8(a0)                           ; the type now 0
	cmpi.b	#$48,9(a0)                      ; a long name?
	seq	9(a0)
	bne.s	relocate_symbols_next           ; no
	lea	$e(a0),a0                       ; past its second part
	subq.w	#1,d0
	bra.s	relocate_symbols_next
relocate_symbols_skip:
	st	(a0)                            ; left out
	clr.b	9(a0)
relocate_symbols_next:
	lea	$e(a0),a0                       ; the next entry
	dbra	d0,relocate_symbols
	clr.w	(a0)                            ; the end
	rts
load_program_symbols_done:	; from: load_program
	bsr.w	close_file                      ; close
run_program:	; from: load_program
	movea.l	prog_basepage(a6),a2            ; its basepage
	addq.l	#8,a2                           ; its text
	lea	prog_text(a6),a0                ; the program's areas
	move.l	(a2)+,(a0)+                     ; text
	move.l	(a2)+,(a0)+                     ; and length
	move.l	(a2)+,(a0)+                     ; data
	move.l	(a2)+,(a0)+                     ; and length
	move.l	(a2)+,(a0)+                     ; BSS
	move.l	(a2)+,(a0)+                     ; and length
	move.l	prog_bss(a6),d0                 ; the BSS
	add.l	prog_bss+4(a6),d0               ; + its length
	addi.l	#$7d00,d0                       ; + 32000
	move.l	d0,prog_end(a6)                 ; its end
	movea.l	prog_basepage(a6),a1            ; the basepage
	lea	$100(a1),a1                     ; its text
	move.l	a1,window_3+66(a6)              ; window 3 shows it
	moveq	#1,d3                           ; a plain breakpoint
	moveq	#1,d2
	bsr.w	set_breakpoint                  ; at the start
	lea	prog_stack(a6),sp               ; the stack for it
	clr.l	-(sp)                           ; Pexec(4, basepage): run it
	move.l	prog_basepage(a6),-(sp)
	clr.l	-(sp)
	move.w	#$4,-(sp)
	move.w	#$4b,-(sp)
	trap	#1                              ; Pexec
	lea	monst_stack(a6),sp              ; MonST's stack back
	move.l	d0,reg_d(a6)                    ; the exit code in d0
	sf	prog_loaded(a6)                 ; no program
	movea.l	prog_basepage(a6),a0
	move.l	$2c(a0),-(sp)                   ; its environment
	bsr.s	mfree                           ; freed
	movea.l	(sp)+,a0                        ; its basepage
	bsr.s	mfree                           ; freed
	clr.l	reg_ssp(a6)                     ; nothing to run
	bsr.w	monst_screen                    ; MonST's screen back
	lea	window_title(a6),a3             ; the title window
	bsr.w	clear_window                    ; cleared
	clr.l	$16(a3)
	lea	text_program_terminated(pc),a0  ; "Program terminated"
	bsr.w	print_string
	st	message_shown(a6)               ; a message
	tst.l	source_start(a6)                ; a source window?
	beq.s	run_program_done                ; no
	tst.b	source_from_editor(a6)          ; the editor's?
	bpl.s	run_program_done                ; yes: kept
	clr.l	source_start(a6)                ; no source now
	lea	window_4(a6),a3                 ; window 4
	tst.w	$10(a3)                         ; open?
	beq.s	run_program_done                ; no
	cmpi.b	#$4,$3e(a3)                     ; source code?
	bne.s	run_program_done                ; no
	move.b	#$3,$3e(a3)                     ; disassembly again
	bsr.w	select_window
	bsr.w	set_window_type
	bsr.w	set_window_title                ; its title
run_program_done:
	bra.w	command_loop                    ; the command loop

;------------------------------------------------------------------------------
; Mfree(a0).
;------------------------------------------------------------------------------
mfree:	; from: cmd_load_source, load_program, relocate_symbols
	move.l	a0,-(sp)
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; Run the program the editor assembled into memory, its PRG image at a4: a basepage from Pexec 5, the text and
; data copied in, the BSS cleared, relocated, a breakpoint at its start, its symbols used where they are, and
; Pexec 4 to run it.  MonST quits when it ends.
;------------------------------------------------------------------------------
run_from_editor:	; from: print_wait
	tst.w	(a4)                            ; an image?
	beq.w	run_from_editor_quit            ; no: quit
	lea	arguments(a6),a1                ; an empty command line
	clr.w	(a1)
	clr.l	-(sp)                           ; Pexec(5, 0, command line, 0): a basepage
	move.l	a1,-(sp)
	clr.l	-(sp)
	move.l	#$4b0005,-(sp)
	trap	#1                              ; Pexec
	lea	$10(sp),sp
	tst.l	d0
	bmi.w	run_from_editor_quit            ; failed: quit
	movea.l	d0,a3                           ; the basepage
	move.l	#$100,d1                        ; its $100 bytes
	add.l	2(a4),d1                        ; + text
	add.l	6(a4),d1                        ; + data
	add.l	$a(a4),d1                       ; + BSS
	add.l	(a3),d1                         ; + its address: the end needed
	cmp.l	4(a3),d1                        ; past the memory it has?
	bcc.w	run_from_editor_quit            ; yes: quit
	addi.l	#$100,d0                        ; the text
	lea	8(a3),a0                        ; the basepage's areas
	move.l	d0,(a0)+                        ; text start
	move.l	2(a4),(a0)                      ; and length
	add.l	(a0)+,d0
	move.l	d0,(a0)+                        ; data start
	move.l	6(a4),(a0)                      ; and length
	add.l	(a0)+,d0
	move.l	d0,(a0)+                        ; BSS start
	move.l	$a(a4),(a0)                     ; and length
	movea.l	8(a3),a0                        ; the text
	lea	$1c(a4),a1                      ; the image's text
	move.l	2(a4),d0                        ; text
	add.l	6(a4),d0                        ; + data
	lsr.l	#1,d0                           ; in words
	subq.l	#1,d0
	bcs.s	run_from_editor_bss             ; none
run_from_editor_copy:
	move.w	(a1)+,(a0)+                     ; copied
	dbra	d0,run_from_editor_copy
	subi.l	#$10000,d0                      ; 64 K words more
	bcc.s	run_from_editor_copy
run_from_editor_bss:
	move.l	$a(a4),d0                       ; the BSS
	lsr.l	#2,d0                           ; in longs
	subq.l	#1,d0
	bcs.s	run_from_editor_relocate        ; none
	moveq	#0,d1
run_from_editor_clear:
	move.l	d1,(a0)+                        ; cleared
	dbra	d0,run_from_editor_clear
	subi.l	#$10000,d0                      ; 64 K longs more
	bcc.s	run_from_editor_clear
run_from_editor_relocate:
	movea.l	8(a3),a0                        ; the text
	move.l	a0,d2                           ; the relocation base
	moveq	#0,d1
	adda.l	$e(a4),a1                       ; past the symbols: the relocation table
	move.l	(a1)+,d0                        ; the first offset
	beq.s	run_from_editor_start           ; none
run_from_editor_relocate_long:
	add.l	d2,0(a0,d0.l)                   ; relocate a long
run_from_editor_relocate_next:
	move.b	(a1)+,d1                        ; the next step
	beq.s	run_from_editor_start           ; the end
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.s	run_from_editor_relocate_step   ; no
	addi.l	#$fe,d0                         ; yes
	bra.s	run_from_editor_relocate_next
run_from_editor_relocate_step:
	add.l	d1,d0                           ; on
	bra.s	run_from_editor_relocate_long   ; relocate it
run_from_editor_start:
	movea.l	8(a3),a1                        ; the text
	move.l	a1,window_3+66(a6)              ; window 3 shows it
	moveq	#1,d2                           ; a plain breakpoint
	moveq	#1,d3
	bsr.w	set_breakpoint                  ; at the start
	lea	prog_stack(a6),sp               ; the stack for it
	st	prog_loaded(a6)                 ; a program loaded
	move.l	a3,prog_basepage(a6)            ; its basepage
	lea	8(a3),a1                        ; its areas
	lea	prog_text(a6),a0                ; the program's areas
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	move.l	prog_bss(a6),d0                 ; the BSS
	add.l	prog_bss+4(a6),d0               ; + its length
	addi.l	#$7d00,d0                       ; + 32000
	move.l	d0,prog_end(a6)                 ; its end
	tst.l	$e(a4)                          ; symbols?
	beq.s	run_from_editor_go              ; no
	lea	$1c(a4),a0                      ; the image's text
	adda.l	2(a4),a0                        ; + text
	adda.l	6(a4),a0                        ; + data: the symbols
	move.l	a0,symbols(a6)                  ; used where they are
	clr.l	symbol_hash(a6)
	tst.b	$12(a4)                         ; relocated already?
	bne.s	run_from_editor_go              ; yes
	st	$12(a4)                         ; not again
	move.l	$e(a4),d0                       ; their length
	subq.l	#2,d0                           ; less the end marker
	divu.w	#$e,d0                          ; entries
	subq.w	#1,d0
	movea.l	a3,a1                           ; the basepage
	bsr.w	relocate_symbols                ; relocated
run_from_editor_go:
	clr.l	-(sp)                           ; Pexec(4, 0, basepage, 0): run it
	move.l	a3,-(sp)
	clr.l	-(sp)
	move.l	#$4b0004,-(sp)
	trap	#1                              ; Pexec
	lea	$10(sp),sp
run_from_editor_quit:
	lea	monst_stack(a6),sp              ; MonST's stack
	bsr.w	program_screen                  ; the program's screen
	bra.w	restore_and_quit                ; quit

;------------------------------------------------------------------------------
; Draw the contents of all the open windows.
;------------------------------------------------------------------------------
redraw_windows:                                 ; from: print_wait, set_registers, redraw_after, window_lock,
                                                ;   cmd_toggle_breakpoint, cmd_kill_breakpoints, 6 more
	lea	window_title(a6),a3             ; the first
	moveq	#7,d2                           ; 8 of them
redraw_windows_loop:
	tst.w	$10(a3)                         ; open?
	beq.s	redraw_windows_next             ; no
	move.w	d2,-(sp)
	bsr.s	draw_window_contents            ; drawn
	move.w	(sp)+,d2
redraw_windows_next:
	adda.w	#$4e,a3                         ; the next
	dbra	d2,redraw_windows_loop
	rts

;------------------------------------------------------------------------------
; Draw all the open windows, frames and contents, the current one's frame highlighted.
;------------------------------------------------------------------------------
draw_all_windows:	; from: close_prompt
	lea	window_title(a6),a3             ; the first
	moveq	#7,d2                           ; 8 of them
draw_all_windows_loop:
	tst.w	$10(a3)                         ; open?
	beq.s	draw_all_windows_next           ; no
	move.w	d2,-(sp)
	cmpa.l	current_window(a6),a3           ; the current one?
	seq	d7                              ; d7 set for it
	st	d4
	bsr.w	draw_frame                      ; its frame
	bsr.s	draw_window_contents            ; its contents
	move.w	(sp)+,d2
draw_all_windows_next:
	adda.w	#$4e,a3                         ; the next
	dbra	d2,draw_all_windows_loop
	rts

;------------------------------------------------------------------------------
; Draw the window a3's contents through its handler table, the print position at the top.
;------------------------------------------------------------------------------
draw_window_contents:                           ; from: zoom_window, window_address, window_full_height, move_window,
                                                ;   redraw_after, window_edit, 8 more
	clr.l	$16(a3)                         ; the top
	movea.l	$48(a3),a0                      ; its handlers
	jmp	0(a0)                           ; draw

;------------------------------------------------------------------------------
; The title window's handler table: draw, then the keys; none does anything.
;------------------------------------------------------------------------------
title_handlers:	; from: open_window
	bra.w	handler_nothing                 ; draw
	bra.s	handler_nothing                 ; Shift cursor up
	bra.s	handler_nothing                 ; Shift cursor down
	bra.s	handler_nothing                 ; cursor up
	bra.s	handler_nothing                 ; cursor down
	bra.s	handler_nothing                 ; cursor left
	nop                                     ; cursor right
handler_nothing:
	moveq	#0,d1
	rts

;------------------------------------------------------------------------------
; A memory window: a line for each of its lines from its address.
;------------------------------------------------------------------------------
draw_memory:	; from: memory_handlers
	move.w	$12(a3),d7                      ; the lines
	movea.l	$42(a3),a2                      ; the address
draw_memory_loop:
	bsr.s	memory_line                     ; a line
	bsr.w	print_newline                   ; a new line
	subq.b	#1,d7
	bne.s	draw_memory_loop
	rts

;------------------------------------------------------------------------------
; A memory line at a2: the address, the bytes in hex and then as characters; unreadable memory is shown as
; stars and spaces.
;------------------------------------------------------------------------------
memory_line:	; from: draw_memory, memory_line_up, memory_line_down, hex_column_offset
	move.l	a2,d2                           ; the address
	bsr.w	print_hex_long                  ; in hex
	move.b	$3f(a3),d6                      ; the bytes a line
	bsr.s	memory_hex                      ; in hex
	moveq	#0,d6
	move.b	$3f(a3),d6
	bsr.w	check_address                   ; readable?
	suba.w	d6,a2                           ; back to the line's start
	bne.s	memory_line_unreadable          ; no
	bsr.w	check_address                   ; and its end?
	bne.s	memory_line_unreadable          ; no
	bsr.w	print_space                     ; a space
memory_line_chars:
	move.b	(a2)+,d1                        ; a byte
	bsr.w	print_byte_char                 ; as a character
	subq.b	#1,d6
	bne.s	memory_line_chars
	rts
memory_line_unreadable:
	move.b	$3f(a3),d2                      ; the width
	addq.b	#1,d2
	bsr.w	print_spaces                    ; spaces
	adda.w	d6,a2                           ; past the line
	rts

;------------------------------------------------------------------------------
; d6 bytes from a2 in hex, a space after each word; unreadable bytes are shown as stars.
;------------------------------------------------------------------------------
memory_hex:	; from: memory_line, draw_registers
	tst.b	d6                              ; none?
	beq.s	memory_hex_done
	bsr.w	print_space                     ; a space
memory_hex_loop:
	bsr.w	check_address                   ; readable?
	beq.s	memory_hex_byte                 ; yes
	addq.l	#1,a2
	bsr.w	print_stars                     ; "**"
	bra.s	memory_hex_space
memory_hex_byte:
	move.b	(a2)+,d2                        ; a byte
	bsr.w	print_hex_byte                  ; in hex
memory_hex_space:
	move.w	a2,d0
	btst	#$0,d0                          ; a word's end?
	bne.s	memory_hex_next                 ; no
	bsr.w	print_space                     ; a space
memory_hex_next:
	subq.b	#1,d6
	bne.s	memory_hex_loop
memory_hex_done:
	rts
memory_left:	; from: memory_handlers
	subq.l	#1,$42(a3)                      ; a byte back
	moveq	#-1,d0                          ; redraw
	rts
memory_right:	; from: memory_handlers
	addq.l	#1,$42(a3)                      ; a byte on
	moveq	#-1,d0                          ; redraw
	rts

;------------------------------------------------------------------------------
; A memory window's handler table: draw, page up, page down, a line up, a line down, a byte back, a byte on.
;------------------------------------------------------------------------------
memory_handlers:	; from: set_window_type
	bra.w	draw_memory                     ; draw
	bra.s	memory_page_up                  ; Shift cursor up
	bra.s	memory_page_down                ; Shift cursor down
	bra.s	memory_line_up                  ; cursor up
	bra.s	memory_line_down                ; cursor down
	bra.s	memory_left                     ; cursor left
	bra.s	memory_right                    ; cursor right
memory_page_up:
	moveq	#0,d0
	move.b	$3f(a3),d0                      ; the bytes a line
	neg.w	d0                              ; back
	bra.s	memory_page
memory_page_down:
	moveq	#0,d0
	move.b	$3f(a3),d0                      ; the bytes a line
memory_page:
	muls.w	$12(a3),d0                      ; a page of lines
	add.l	d0,$42(a3)                      ; moved
	moveq	#-1,d1                          ; redraw
	rts

;------------------------------------------------------------------------------
; Scroll the memory window down a line, the new top line drawn.
;------------------------------------------------------------------------------
memory_line_up:	; from: memory_handlers, hex_column_offset
	bsr.w	scroll_down_line                ; scrolled
	moveq	#0,d0
	move.b	$3f(a3),d0                      ; the bytes a line
	sub.l	d0,$42(a3)                      ; a line back
	movea.l	$42(a3),a2
	bsr.w	memory_line                     ; the new top line
	moveq	#0,d1                           ; no redraw
	rts

;------------------------------------------------------------------------------
; Scroll the memory window up a line, the new bottom line drawn.
;------------------------------------------------------------------------------
memory_line_down:	; from: memory_handlers, hex_column_offset
	bsr.w	scroll_up_line                  ; scrolled
	moveq	#0,d0
	move.b	$3f(a3),d0                      ; the bytes a line
	add.l	d0,$42(a3)                      ; a line on
	move.w	$12(a3),d1                      ; the lines
	subq.w	#1,d1
	mulu.w	d0,d1                           ; to the bottom line
	movea.l	$42(a3),a2
	adda.l	d1,a2
	bsr.w	memory_line                     ; drawn
	moveq	#0,d1                           ; no redraw
	rts

;------------------------------------------------------------------------------
; Alt-E in a memory window: edit it in hex (Tab switches to the characters), the cursor keys moving.
;------------------------------------------------------------------------------
edit_memory:	; from: window_edit
	movea.l	$42(a3),a4                      ; the address
	moveq	#0,d6
	moveq	#0,d7
	moveq	#0,d5                           ; in the hex
	moveq	#0,d4
	move.b	$3f(a3),d4                      ; the bytes a line
	mulu.w	#$5,d4                          ; 2.5 columns each
	lsr.w	#1,d4
	move.w	d4,d3
	bra.s	edit_memory_loop

;------------------------------------------------------------------------------
; Put the cursor at the edited byte: past the address, in the hex or the characters.
;------------------------------------------------------------------------------
edit_memory_cursor:	; from: hex_column_offset
	move.w	d3,-(sp)
	moveq	#9,d2                           ; past the address
	tst.b	d5                              ; the characters?
	beq.s	edit_memory_cursor_column       ; no
	add.w	d4,d2                           ; past the hex
	addq.w	#1,d2
edit_memory_cursor_column:
	add.w	d6,d2                           ; + the column
	move.w	d7,d3                           ; the line
	bsr.w	invert_char                     ; the cursor there
	move.w	(sp)+,d3
	rts
hex_column_offsets:	; from: hex_column_offset
	dc.w	$0000,$0101,$0102,$0203,$0303,$0404,$0505,$0506 ; the extra columns of each byte in a line: the spaces
                                                ;   between the words
	dc.w	$0607,$0707,$0808,$0909,$090a,$0a0b,$0b0b,$0c0c
	dc.w	$0d0d,$0d0e,$0e0f,$0f0f

;------------------------------------------------------------------------------
; d0 = the extra columns before byte d6 of a line.
;------------------------------------------------------------------------------
hex_column_offset:
	move.b	hex_column_offsets(pc,d6.w),d0
	ext.w	d0
	rts
edit_memory_tab:
	not.b	d5                              ; the other half
	bne.s	edit_memory_to_chars            ; to the characters
	mulu.w	#$5,d6                          ; back to the hex: 2.5 columns a byte
	btst	#$0,$45(a3)
	bne.s	edit_memory_hex_round
	lsr.w	#1,d6
edit_memory_hex_width:
	move.w	d4,d3                           ; the hex width
	bra.s	edit_memory_loop
edit_memory_hex_round:
	lsr.w	#1,d6
	bcc.s	edit_memory_hex_width
	addq.w	#1,d6
	bra.s	edit_memory_hex_width
edit_memory_to_chars:
	bsr.s	hex_column_offset               ; the byte's offset
	move.w	d0,d6
	moveq	#0,d3
	move.b	$3f(a3),d3                      ; the line's width: its bytes
edit_memory_loop:	; from: edit_memory, edit_memory_column
	bsr.s	edit_memory_cursor              ; the cursor on
	bsr.w	get_key                         ; a key
	bmi.w	edit_memory_alt                 ; an Alt key
	move.w	d1,-(sp)
	bsr.s	edit_memory_cursor              ; the cursor off
	move.w	(sp)+,d1
	cmp.b	#$1b,d1                         ; Esc?
	beq.w	redraw_after                    ; yes: done
	cmp.b	#$9,d1                          ; Tab?
	beq.s	edit_memory_tab                 ; yes: the other half
	cmp.w	#$4800,d1                       ; cursor up?
	beq.w	edit_memory_up
	cmp.w	#$5000,d1                       ; cursor down?
	beq.w	edit_memory_down
	cmp.w	#$4d00,d1                       ; cursor right?
	beq.w	edit_memory_right
	cmp.w	#$4b00,d1                       ; cursor left?
	beq.w	edit_memory_left
	cmp.b	#$8,d1                          ; Backspace?
	beq.w	edit_memory_left
	tst.b	d5                              ; the characters?
	bne.s	edit_memory_char                ; yes
	moveq	#48,d0                          ; a hex digit?
	cmp.b	d0,d1
	bcs.s	edit_memory_loop                ; no
	cmp.b	#$3a,d1                         ; 0-9?
	bcs.s	edit_memory_digit               ; yes
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$41,d1                         ; A-F?
	bcs.s	edit_memory_loop                ; no
	cmp.b	#$47,d1
	bcc.s	edit_memory_loop                ; no
	moveq	#55,d0
edit_memory_digit:
	sub.b	d0,d1                           ; its value
	move.b	d1,d2
	bsr.w	hex_column_offset               ; the byte's offset
	lea	0(a4,d0.w),a0                   ; its address
	move.l	a0,d0
	bsr.w	check_ram                       ; in RAM?
	bne.w	edit_memory_right               ; no: on
	bsr.w	edit_memory_column              ; the high or low digit?
	andi.b	#$1,d0
	bne.s	edit_memory_high                ; the high one
	andi.b	#$f0,(a0)                       ; the low digit
	or.b	d2,(a0)
	bra.s	edit_memory_redraw
edit_memory_high:
	andi.b	#$f,(a0)                        ; the high digit
	lsl.b	#4,d2
	or.b	d2,(a0)
	bra.s	edit_memory_redraw
edit_memory_char:
	tst.b	d1                              ; a character?
	beq.w	edit_memory_loop                ; no
	lea	0(a4,d6.w),a0                   ; its address
	move.l	a0,d0
	bsr.w	check_ram                       ; in RAM?
	bne.s	edit_memory_redraw              ; no
	move.b	d1,0(a4,d6.w)                   ; written
edit_memory_redraw:
	clr.w	$16(a3)                         ; the line again
	movem.l	d3-d7/a4,-(sp)
	mulu.w	$1a(a3),d7
	move.w	d7,$18(a3)
	movea.l	a4,a2
	bsr.w	memory_line                     ; redrawn
	movem.l	(sp)+,d3-d7/a4
	bra.s	edit_memory_right               ; the next column
edit_memory_alt:
	move.w	d1,-(sp)
	bsr.w	edit_memory_cursor              ; the cursor off
	move.w	(sp)+,d1
	cmp.b	#$45,d1                         ; Alt-E?
	beq.w	redraw_after                    ; yes: done
	move.w	d1,-(sp)
	bsr.w	redraw_after                    ; redraw
	move.w	(sp)+,d1
	bra.w	window_command                  ; the window command
edit_memory_up:	; from: edit_memory_column
	moveq	#0,d0
	move.b	$3f(a3),d0                      ; a line
	suba.l	d0,a4                           ; back
	subq.w	#1,d7                           ; the top line?
	bcc.w	edit_memory_next                ; no
	movem.l	d3-d7/a4,-(sp)
	bsr.w	memory_line_up                  ; scroll
	movem.l	(sp)+,d3-d7/a4
	moveq	#0,d7                           ; still the top
	bsr.w	wait_key
	bra.s	edit_memory_next
edit_memory_down:
	moveq	#0,d0
	move.b	$3f(a3),d0                      ; a line
	adda.l	d0,a4                           ; on
	addq.w	#1,d7
	cmp.w	$12(a3),d7                      ; the bottom line?
	bne.s	edit_memory_next                ; no
	subq.w	#1,d7                           ; still the bottom
	movem.l	d3-d7/a4,-(sp)
	bsr.w	memory_line_down                ; scroll
	movem.l	(sp)+,d3-d7/a4
	bsr.w	wait_key
	bra.s	edit_memory_next
edit_memory_right:
	addq.w	#1,d6                           ; a column on
	bsr.s	edit_memory_column              ; a space column?
	bne.s	edit_memory_right_wrap          ; no
	addq.w	#1,d6                           ; past it
edit_memory_right_wrap:
	cmp.w	d3,d6                           ; the line's end?
	bne.s	edit_memory_next                ; no
	moveq	#0,d6                           ; the next line's start
	bra.s	edit_memory_down

;------------------------------------------------------------------------------
; Z set when column d6 of the hex is a space between words (or the characters are edited, d0 nonzero then);
; d0 = 0 or 1 tells the low or high digit otherwise.
;------------------------------------------------------------------------------
edit_memory_column:	; from: hex_column_offset
	tst.b	d5                              ; the characters?
	bne.s	edit_memory_column_done         ; yes
	moveq	#0,d0
	move.w	d6,d0                           ; the column
	moveq	#1,d1
	btst	#$0,$45(a3)
	beq.s	edit_memory_column_mod
	moveq	#3,d1
edit_memory_column_mod:
	add.w	d1,d0
	divu.w	#$5,d0                          ; in 5 column groups
	swap	d0
	tst.w	d0
edit_memory_column_done:
	rts
edit_memory_left:	; from: hex_column_offset
	subq.w	#1,d6                           ; a column back
	bcs.s	edit_memory_left_wrap           ; the line's start
	bsr.s	edit_memory_column              ; a space?
	bne.s	edit_memory_next                ; no
	subq.w	#1,d6                           ; past it
	bcc.s	edit_memory_next
edit_memory_left_wrap:
	move.w	d3,d6                           ; the last column
	subq.w	#1,d6
	bsr.s	edit_memory_column              ; a space?
	bne.w	edit_memory_up                  ; no: up a line
	subq.w	#1,d6
	bra.w	edit_memory_up                  ; up a line
edit_memory_next:	; from: hex_column_offset
	bra.w	edit_memory_loop

;------------------------------------------------------------------------------
; A register window: D0-D7 with each value, its low byte as a character and the memory it points to, A0-A7
; the same; SR with its flags, A7' (the supervisor stack) and its memory, the PC and its instruction with the
; effective addresses it uses; and M0-M9 when the window is tall enough.
;------------------------------------------------------------------------------
draw_registers:	; from: register_handlers
	lea	reg_d(a6),a1                    ; the data registers
	moveq	#48,d7                          ; '0'
draw_registers_loop:
	moveq	#68,d1                          ; D
	bsr.w	print_char                      ; printed
	move.b	d7,d1                           ; the number
	bsr.w	print_char
	moveq	#58,d1                          ; :
	bsr.w	print_char
	movea.l	(a1)+,a2                        ; the value
	move.l	a2,d2
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_space                     ; a space
	move.b	-$1(a1),d1                      ; its low byte
	bsr.w	print_byte_char                 ; as a character
	move.b	$40(a3),d6                      ; the memory bytes to show
	bne.s	draw_registers_d_memory         ; some
	bsr.w	print_space                     ; none: a space
	bra.s	draw_registers_a
draw_registers_d_memory:
	bsr.w	memory_hex                      ; the memory at it
draw_registers_a:
	bsr.w	print_space                     ; a space
	moveq	#65,d1                          ; A
	bsr.w	print_char
	move.b	d7,d1                           ; the number
	bsr.w	print_char
	moveq	#58,d1                          ; :
	bsr.w	print_char
	movea.l	$1c(a1),a2                      ; the address register
	move.l	a2,d2
	bsr.w	print_hex_long                  ; in hex
	move.b	$3f(a3),d6                      ; the bytes a line
	bsr.w	memory_hex                      ; the memory at it
	bsr.w	print_newline                   ; a new line
	addq.b	#1,d7                           ; the next
	cmp.b	#$38,d7                         ; all 8?
	bne.s	draw_registers_loop             ; no
	moveq	#1,d1                           ; "SR:"
	bsr.w	print_message
	move.w	reg_sr+2(a6),d2                 ; the SR
	bsr.w	print_hex_word                  ; in hex
	bsr.w	print_space                     ; a space
	move.w	reg_sr+2(a6),d4
	bsr.w	print_flags                     ; its flags
	move.b	$40(a3),d2                      ; the column
	add.b	d2,d2
	add.b	d2,d2
	add.b	$40(a3),d2
	lsr.b	#1,d2
	bsr.w	print_spaces
	moveq	#2,d1                           ; "A7'"
	bsr.w	print_message
	move.l	reg_ssp(a6),d2                  ; the supervisor stack
	bsr.w	print_hex_long                  ; in hex
	movea.l	reg_ssp(a6),a2
	move.b	$3f(a3),d6                      ; the bytes a line
	bsr.w	memory_hex                      ; the memory at it
	bsr.w	print_newline                   ; a new line
	moveq	#0,d1                           ; "PC:"
	bsr.w	print_message
	move.l	reg_pc(a6),d2                   ; the PC
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_space                     ; a space
	movea.l	reg_pc(a6),a2
	sf	ea_count(a6)                    ; work out its effective addresses
	bsr.w	print_instruction               ; its instruction
	bset	#$0,ea_count(a6)                ; any effective address?
	beq.s	draw_registers_m                ; no
	moveq	#17,d1                          ; " ; "
	bsr.w	print_message
	move.l	ea_address(a6),d2               ; the first
	bsr.w	print_hex_long                  ; in hex
	movea.l	ea_address(a6),a2
	moveq	#0,d0
	move.b	ea_size(a6),d0                  ; the operand size
	move.b	operand_sizes(pc,d0.w),d6       ; its byte count
	bsr.w	memory_hex                      ; the memory there
	tst.b	ea_two(a6)                      ; a second?
	beq.s	draw_registers_m                ; no
	moveq	#3,d1                           ; the separator
	bsr.w	print_char                      ; printed
	move.l	ea_address2(a6),d2              ; the second
	bsr.w	print_hex_long                  ; in hex
	movea.l	ea_address2(a6),a2
	moveq	#0,d0
	move.b	ea_size(a6),d0                  ; the operand size
	move.b	operand_sizes(pc,d0.w),d6       ; its byte count
	bsr.w	memory_hex                      ; the memory there
draw_registers_m:
	st	ea_count(a6)
	bsr.w	clear_to_eol                    ; the rest of the line cleared
	bsr.w	print_newline                   ; a new line
	cmpi.w	#$b,$12(a3)                     ; 11 lines or more?
	bcs.s	draw_registers_done             ; no
	bra.s	draw_registers_m_list
operand_sizes:
	dc.w	$0102,$0408                     ; the bytes shown for a byte, word, long and 8 byte operand
draw_registers_m_list:
	bsr.w	print_newline                   ; a new line
	bsr.w	print_newline
	moveq	#0,d7                           ; M0 first
	lea	m_register_offsets(pc),a1       ; their offsets
draw_registers_m_loop:
	moveq	#77,d1                          ; M
	bsr.w	print_char
	moveq	#48,d1                          ; '0'
	add.b	d7,d1                           ; + the number
	bsr.w	print_char
	moveq	#58,d1                          ; :
	bsr.w	print_char
	move.w	(a1)+,d2                        ; its offset
	movea.l	basepage(a6,d2.w),a2            ; the address
	move.l	a2,d2
	bsr.w	print_hex_long                  ; in hex
	moveq	#12,d6                          ; 12 bytes
	bsr.w	memory_hex                      ; the memory there
	bsr.w	print_newline                   ; a new line
	addq.w	#1,d7                           ; the next
	cmp.w	#$a,d7                          ; all 10?
	bne.s	draw_registers_m_loop           ; no
draw_registers_done:
	rts

;------------------------------------------------------------------------------
; Print the flags of the SR d4: T, S or U, then X N Z V C, a space for each one clear.
;------------------------------------------------------------------------------
print_flags:	; from: draw_registers, draw_history
	lea	flag_letters(pc),a0             ; the letters
	btst	#$f,d4                          ; trace?
	bsr.s	print_flag                      ; T or a space
	moveq	#83,d1                          ; S
	btst	#$d,d4                          ; supervisor?
	bne.s	print_flags_mode                ; yes
	moveq	#85,d1                          ; U
print_flags_mode:
	bsr.w	print_char                      ; printed
	moveq	#4,d2                           ; 5 flags
print_flags_loop:
	btst	#$4,d4                          ; the next, X first
	bsr.s	print_flag                      ; its letter or a space
	add.b	d4,d4
	dbra	d2,print_flags_loop
	rts

;------------------------------------------------------------------------------
; Print the next letter at a0 if Z is clear, else a space.
;------------------------------------------------------------------------------
print_flag:	; from: print_flags
	beq.s	print_flag_space                ; clear?
	move.b	(a0)+,d1                        ; the letter
	bra.w	print_char                      ; printed
print_flag_space:
	addq.l	#1,a0                           ; past it
	bra.w	print_space                     ; a space
flag_letters:	; from: print_flags
	dc.b	'TXNZVC'                        ; "TXNZVC"

;------------------------------------------------------------------------------
; A register window's handler table: draw, and keys that do nothing.
;------------------------------------------------------------------------------
register_handlers:	; from: set_window_type
	bra.w	draw_registers                  ; draw
	bra.s	register_keys                   ; Shift cursor up
	bra.s	register_keys                   ; Shift cursor down
	bra.s	register_keys                   ; cursor up
	bra.s	register_keys                   ; cursor down
	bra.s	register_keys                   ; cursor left
	nop                                     ; cursor right
register_keys:
	moveq	#27,d1                          ; not taken
	rts

;------------------------------------------------------------------------------
; A disassembly window: for each line the address (or its symbol in the label column), a mark at the PC and
; the instruction.
;------------------------------------------------------------------------------
draw_disassembly:	; from: disassembly_handlers
	movea.l	$42(a3),a2                      ; the address
	move.w	$12(a3),d6                      ; the lines
draw_disassembly_loop:
	tst.b	$3f(a3)                         ; a label column?
	bne.s	draw_disassembly_label          ; yes
	moveq	#8,d2
	move.l	a2,d0
	bsr.w	find_symbol                     ; a symbol?
	bne.s	draw_disassembly_symbol         ; yes: it instead of the address
	move.l	a2,d2
	bsr.w	print_hex_long                  ; the address in hex
	moveq	#0,d2
	bra.s	draw_disassembly_column
draw_disassembly_label:
	move.l	a2,d2
	bsr.w	print_hex_long                  ; the address in hex
	bsr.w	print_space                     ; a space
	move.l	a2,d0
	move.b	$3f(a3),d2                      ; the column width
	bsr.w	find_symbol                     ; a symbol?
	beq.s	draw_disassembly_column         ; no
draw_disassembly_symbol:
	bsr.w	print_symbol_name               ; printed
draw_disassembly_column:
	bsr.w	print_spaces                    ; to the column
	moveq	#32,d1                          ; a space
	cmpa.l	reg_pc(a6),a2                   ; the PC?
	bne.s	draw_disassembly_mark           ; no
	moveq	#3,d1                           ; the PC mark
draw_disassembly_mark:
	bsr.w	print_char                      ; printed
	bsr.w	print_instruction               ; the instruction
	move.l	a2,-(sp)
	bsr.w	clear_to_eol                    ; the rest of the line cleared
	bsr.w	print_newline                   ; a new line
	movea.l	(sp)+,a2
	subq.b	#1,d6
	bne.s	draw_disassembly_loop
	rts
disassembly_left:	; from: disassembly_handlers
	bsr.s	disassembly_address             ; the address, even
	subq.l	#2,a2                           ; a word back
disassembly_set:
	move.l	a2,$42(a3)                      ; the window's address
	moveq	#-1,d0                          ; redraw
	rts
disassembly_right:	; from: disassembly_handlers
	bsr.s	disassembly_address             ; the address, even
	addq.l	#2,a2                           ; a word on
	bra.s	disassembly_set

;------------------------------------------------------------------------------
; A disassembly window's handler table: draw, page up, page down, an instruction back, an instruction on, a
; word back, a word on.
;------------------------------------------------------------------------------
disassembly_handlers:	; from: set_window_type
	bra.w	draw_disassembly                ; draw
	bra.s	disassembly_page_up             ; Shift cursor up
	bra.s	disassembly_page_down           ; Shift cursor down
	bra.s	disassembly_up                  ; cursor up
	bra.s	disassembly_down                ; cursor down
	bra.s	disassembly_left                ; cursor left
	bra.s	disassembly_right               ; cursor right
disassembly_page_up:
	move.w	$12(a3),d0                      ; the lines
	add.w	d0,d0                           ; two bytes each
	ext.l	d0
	sub.l	d0,$42(a3)                      ; back
	moveq	#-1,d0                          ; redraw
	rts
disassembly_page_down:
	move.l	$42(a3),d0                      ; the address
	addq.l	#1,d0                           ; even
	bclr	#$0,d0
	movea.l	d0,a2
	move.w	$12(a3),d6                      ; the lines
disassembly_page_down_loop:
	bsr.w	next_instruction                ; an instruction on
	subq.b	#1,d6
	bne.s	disassembly_page_down_loop
disassembly_set_a2:	; from: disassembly_address
	move.l	a2,$42(a3)                      ; the window's address
	moveq	#-1,d1                          ; redraw
	rts

;------------------------------------------------------------------------------
; a2 = the disassembly window's address, made even.
;------------------------------------------------------------------------------
disassembly_address:	; from: draw_disassembly
	move.l	$42(a3),d0
	addq.l	#1,d0
	bclr	#$0,d0
	movea.l	d0,a2
	rts
disassembly_down:	; from: disassembly_handlers
	bsr.s	disassembly_address             ; the address
	bsr.w	next_instruction                ; the next instruction
	bra.s	disassembly_set_a2
disassembly_up:	; from: disassembly_handlers
	bsr.s	disassembly_address             ; the address
	bsr.w	previous_instruction            ; the instruction before
	bra.s	disassembly_set_a2

;------------------------------------------------------------------------------
; Lock the window a3 to the register at offset d0 (0 for none) and put its name in the title: Dn, An, or
; PC, SR, SP and the like.
;------------------------------------------------------------------------------
set_window_lock:	; from: window_lock, open_windows
	movem.w	d0/d7,-(sp)
	sf	d4
	sf	d7
	bsr.w	draw_frame                      ; the frame
	movem.w	(sp)+,d0/d7
	lea	$20(a3),a0                      ; the title
set_window_lock_end:
	tst.b	(a0)+                           ; find its end
	bne.s	set_window_lock_end
	tst.w	$4c(a3)                         ; locked before?
	beq.s	set_window_lock_name            ; no
	subq.l	#3,a0                           ; back over the old name
set_window_lock_name:
	subq.l	#1,a0
	move.w	d0,$4c(a3)                      ; the register
	beq.s	set_window_lock_done            ; none
	cmp.w	#$4,d0                          ; below D0?
	bcs.s	set_window_lock_other           ; yes
	cmp.w	#$44,d0                         ; past A7?
	bcc.s	set_window_lock_other           ; yes
	subi.w	#$4,d0
	lsr.w	#2,d0                           ; the number
	moveq	#65,d1                          ; A
	subq.w	#8,d0                           ; 8 or more?
	bcc.s	set_window_lock_dn              ; yes
	moveq	#68,d1                          ; D
	addq.w	#8,d0
set_window_lock_dn:
	move.b	d1,(a0)+                        ; the letter
	addi.b	#$30,d0                         ; the digit
	move.b	d0,(a0)+
	move.b	#$20,(a0)+                      ; a space
	bra.s	set_window_lock_done
set_window_lock_other:
	lea	register_offsets(pc),a1         ; the offsets
set_window_lock_find:
	cmp.w	(a1)+,d0                        ; this one?
	bne.s	set_window_lock_find            ; no
	move.b	$20(a1),(a0)+                   ; its two letters
	move.b	$21(a1),(a0)+
	move.b	#$20,(a0)+                      ; a space
set_window_lock_done:
	clr.b	(a0)+                           ; the title's end
	st	d4
	bra.w	draw_frame                      ; the frame

;------------------------------------------------------------------------------
; Move the windows locked to the PC or to a data or address register to their new values.
;------------------------------------------------------------------------------
follow_registers:	; from: stop_program, exc_trace_step
	moveq	#76,d2                          ; the PC
	bsr.s	move_locked_windows
	moveq	#4,d2                           ; D0
follow_registers_loop:
	bsr.s	move_locked_windows
	addq.w	#4,d2                           ; the next
	cmp.w	#$48,d2                         ; past A7?
	bne.s	follow_registers_loop           ; no
	rts

;------------------------------------------------------------------------------
; Move every window locked to the variable at offset d2 to its value (and the windows locked to those windows'
; addresses in turn).  A disassembly window locked to the PC moves only when the PC is not already in its top
; lines.
;------------------------------------------------------------------------------
move_locked_windows:	; from: set_registers, window_lock, cmd_skip, follow_registers
	lea	window_title(a6),a0             ; the windows
	moveq	#7,d0                           ; 8 of them
move_locked_windows_loop:
	tst.w	$10(a0)                         ; open?
	beq.s	move_locked_windows_next        ; no
	move.w	$4c(a0),d1                      ; its lock
	cmp.w	d1,d2                           ; this variable?
	bne.s	move_locked_windows_next        ; no
	cmp.w	#$4c,d2                         ; the PC?
	bne.s	move_locked_windows_value       ; no
	cmpi.b	#$3,$3e(a0)                     ; a disassembly?
	beq.s	move_locked_windows_pc          ; yes: perhaps not
move_locked_windows_value:
	move.l	basepage(a6,d2.w),d1            ; the value
	cmp.l	$42(a0),d1                      ; already there?
	beq.s	move_locked_windows_next        ; yes
move_locked_windows_set:
	move.l	d1,$42(a0)                      ; the window's address
	movem.w	d0/d2,-(sp)
	move.l	a0,-(sp)
	lea	$42(a0),a0                      ; its address variable
	suba.l	a6,a0                           ; as an offset
	move.w	a0,d2
	bsr.s	move_locked_windows             ; the windows locked to it
	movea.l	(sp)+,a0
	movem.w	(sp)+,d0/d2
move_locked_windows_next:
	lea	$4e(a0),a0                      ; the next window
	dbra	d0,move_locked_windows_loop
	rts
move_locked_windows_pc:
	movem.l	d0/d2-d3/d6/a0-a2,-(sp)
	movea.l	reg_pc(a6),a1                   ; the PC
	move.l	$42(a0),d0                      ; the window's address
	addq.l	#1,d0                           ; even
	andi.b	#$fe,d0
	movea.l	d0,a2
	cmpa.l	a2,a1                           ; the PC before it?
	blt.s	move_locked_windows_move        ; yes: move it
	move.w	$12(a0),d6                      ; the lines
	subq.w	#3,d6                           ; less 3
	bcs.s	move_locked_windows_move        ; too few: move it
	move.l	a1,-(sp)
move_locked_windows_find_pc:
	bsr.w	next_instruction                ; the next instruction
	cmpa.l	(sp),a2                         ; the PC?
	beq.s	move_locked_windows_keep        ; yes: in view
	dbra	d6,move_locked_windows_find_pc
	movea.l	(sp)+,a1
move_locked_windows_move:
	move.l	a1,d1                           ; to the PC
	movem.l	(sp)+,d0/d2-d3/d6/a0-a2
	bra.s	move_locked_windows_set
move_locked_windows_keep:
	movea.l	(sp)+,a1
	movem.l	(sp)+,d0/d2-d3/d6/a0-a2
	bra.s	move_locked_windows_next

;------------------------------------------------------------------------------
; A source window: its lines from its address, the rest of the window cleared after the file's end.
;------------------------------------------------------------------------------
draw_source:	; from: source_handlers
	movea.l	$42(a3),a2                      ; the address
	move.w	$12(a3),d6                      ; the lines
	subq.w	#1,d6
draw_source_loop:
	bsr.w	source_print_line               ; a line
	dbeq	d6,draw_source_loop             ; until the end
	bne.s	draw_source_done                ; all shown
	tst.w	d6
	bmi.s	draw_source_done
draw_source_clear:
	bsr.w	clear_to_eol                    ; the rest of the line cleared
	bsr.w	print_newline                   ; a new line
	dbra	d6,draw_source_clear            ; for each line left
draw_source_done:
	rts

;------------------------------------------------------------------------------
; a2 back to the start of the line before; Z set when it is the file's start.
;------------------------------------------------------------------------------
source_line_back:	; from: window_address, source_handlers
	cmpa.l	source_start(a6),a2             ; the start?
	beq.s	source_line_back_start          ; yes: Z set
	cmpi.b	#$d,-(a2)                       ; back to a Return
	bne.s	source_line_back
source_line_back_loop:
	cmpa.l	source_start(a6),a2             ; the start?
	beq.s	source_line_back_done           ; yes
	cmpi.b	#$d,-(a2)                       ; back to the Return before
	bne.s	source_line_back_loop
	addq.l	#1,a2                           ; past it
source_line_back_done:
	moveq	#-1,d0                          ; Z clear
source_line_back_start:
	rts
source_nothing:	; from: source_handlers
	moveq	#0,d0                           ; no redraw
	rts

;------------------------------------------------------------------------------
; A source window's handler table: draw, page up, page down, a line up, a line down; left and right do
; nothing.
;------------------------------------------------------------------------------
source_handlers:	; from: set_window_type
	bra.w	draw_source                     ; draw
	bra.s	source_page_up                  ; Shift cursor up
	bra.s	source_page_down                ; Shift cursor down
	bra.s	source_line_up                  ; cursor up
	bra.s	source_line_down                ; cursor down
	bra.s	source_nothing                  ; cursor left
	bra.s	source_nothing                  ; cursor right
source_line_up:
	movea.l	$42(a3),a2                      ; the address
	bsr.s	source_line_back                ; a line back
	beq.s	source_line_up_done             ; the start: nothing
	move.l	a2,-(sp)
	bsr.w	scroll_down_line                ; scrolled
	bsr.w	clear_to_eol                    ; the line cleared
	movea.l	(sp)+,a2
	move.l	a2,$42(a3)                      ; the new address
	bsr.s	source_print_line               ; the new top line
source_line_up_done:
	moveq	#0,d0                           ; no redraw
	rts
source_page_up:
	movea.l	$42(a3),a2                      ; the address
	move.w	$12(a3),d2                      ; the lines
	subq.w	#1,d2
source_page_up_loop:
	bsr.s	source_line_back                ; a line back
	dbeq	d2,source_page_up_loop          ; to the start
	bra.s	source_set
source_page_down:
	movea.l	$42(a3),a2                      ; the address
	move.w	$12(a3),d2                      ; the lines
	subq.w	#1,d2
source_page_down_loop:
	bsr.s	source_next_line                ; a line on
	beq.s	source_line_down_done           ; the end: nothing
	dbra	d2,source_page_down_loop
source_set:
	move.l	a2,$42(a3)                      ; the window's address
	moveq	#-1,d0                          ; redraw
	rts
source_line_down:
	movea.l	$42(a3),a2                      ; the address
	move.w	$12(a3),d2                      ; the lines
	subq.w	#1,d2
source_line_down_loop:
	bsr.s	source_next_line                ; to the line after the bottom one
	beq.s	source_line_down_done           ; the end: nothing
	dbra	d2,source_line_down_loop
	move.l	a2,-(sp)
	bsr.w	scroll_up_line                  ; scrolled
	bsr.w	clear_to_eol                    ; the line cleared
	movea.l	(sp)+,a2
	bsr.s	source_print_line               ; the new bottom line
	movea.l	$42(a3),a2                      ; the address
	bsr.s	source_next_line                ; a line on
	move.l	a2,$42(a3)
source_line_down_done:
	moveq	#0,d0                           ; no redraw
	rts

;------------------------------------------------------------------------------
; a2 past the next Return; Z set at the file's end.
;------------------------------------------------------------------------------
source_next_line:	; from: search_source, source_handlers
	cmpa.l	source_end(a6),a2               ; the end?
	beq.s	source_print_done               ; yes
	cmpi.b	#$d,(a2)+                       ; a Return?
	bne.s	source_next_line                ; no
	moveq	#-1,d0                          ; Z clear
	rts

;------------------------------------------------------------------------------
; Print the source line at a2, line feeds left out and tabs to the next multiple of the window's tab width;
; Z set at the file's end.
;------------------------------------------------------------------------------
source_print_line:	; from: draw_source, source_handlers
	cmpa.l	source_end(a6),a2               ; the end?
	beq.s	source_print_done               ; yes
	move.b	(a2)+,d1                        ; a character
	cmp.b	#$a,d1                          ; a line feed?
	beq.s	source_print_line               ; yes: left out
	cmp.b	#$d,d1                          ; Return?
	beq.s	source_print_eol                ; yes: the line ends
	cmp.b	#$9,d1                          ; a tab?
	beq.s	source_print_tab                ; yes
	bsr.w	print_char                      ; printed
	bra.s	source_print_line
source_print_tab:
	move.w	$16(a3),d2                      ; the column
	moveq	#0,d1
	move.b	$3f(a3),d1                      ; the tab width
	subq.w	#1,d1
	not.w	d1
	and.w	d1,d2                           ; back to a tab stop
	add.b	$3f(a3),d2                      ; the next one
	sub.w	$16(a3),d2                      ; less the column
	bsr.w	print_spaces                    ; spaces to it
	bra.s	source_print_line
source_print_eol:
	move.l	a2,-(sp)
	bsr.w	clear_to_eol                    ; the rest of the line cleared
	movea.l	(sp)+,a2
	bsr.w	print_newline                   ; a new line
	moveq	#-1,d0                          ; Z clear
source_print_done:	; from: source_next_line
	rts

;------------------------------------------------------------------------------
; a2 past the instruction at a2 (2 bytes on when it cannot be read).
;------------------------------------------------------------------------------
next_instruction:	; from: cmd_step_over, cmd_skip, disassembly_handlers, disassembly_address, move_locked_windows
	bsr.w	check_address                   ; readable?
	bne.s	next_instruction_unreadable     ; no
	lea	$a(a2),a2
	bsr.w	check_address                   ; 10 bytes on too?
	lea	-$a(a2),a2
	bne.s	next_instruction_unreadable     ; no
	movem.l	d4-d7/a3-a5,-(sp)
	movea.l	a2,a5
	move.l	symbols(a6),-(sp)
	clr.l	symbols(a6)                     ; without symbols
	sf	listing_mode(a6)                ; without the address
	bsr.w	disassemble                     ; disassemble it: a5 past it
	move.l	(sp)+,symbols(a6)               ; the symbols back
	movea.l	a5,a2                           ; the next instruction
	movem.l	(sp)+,d4-d7/a3-a5
	rts
next_instruction_unreadable:
	addq.w	#2,a2                           ; a word on
	rts

;------------------------------------------------------------------------------
; Print the instruction at a2 (made even), a2 past it; a star when it cannot be read.
;------------------------------------------------------------------------------
print_instruction:	; from: draw_help, draw_registers, draw_disassembly, draw_history
	move.l	a2,d0
	addq.l	#1,d0                           ; even
	bclr	#$0,d0
	movea.l	d0,a2
	bsr.w	check_address                   ; readable?
	bne.s	print_instruction_unreadable    ; no
	lea	$a(a2),a2
	bsr.w	check_address                   ; 10 bytes on too?
	lea	-$a(a2),a2
	bne.s	print_instruction_unreadable    ; no
	movem.l	d4-d7/a3-a5,-(sp)
	movea.l	a2,a5
	sf	listing_mode(a6)                ; without the address
	bsr.w	disassemble                     ; disassemble it
	movea.l	a5,a2                           ; past it
	move.l	a4,d2                           ; the text's end
	sub.l	a6,d2
	subi.w	#$8be,d2                        ; its length less 1
	movem.l	(sp)+,d4-d7/a3-a5
	lea	line_buffer(a6),a0              ; the text
print_instruction_loop:
	move.b	(a0)+,d1                        ; a character
	bsr.w	print_char                      ; printed
	dbra	d2,print_instruction_loop
	rts
print_instruction_unreadable:
	moveq	#42,d1                          ; *
	bra.w	print_char                      ; printed

;------------------------------------------------------------------------------
; Print message number d1 from the message list.
;------------------------------------------------------------------------------
print_message:	; from: window_evaluate, cmd_find_next, draw_help, cmd_disassemble, draw_registers, draw_history, 1 more
	lea	messages(pc),a0                 ; the list
	tst.b	d1                              ; the first?
	beq.s	print_string                    ; yes
print_message_find:
	tst.b	(a0)+                           ; past a message
	bne.s	print_message_find
	subq.b	#1,d1
	bne.s	print_message_find

;------------------------------------------------------------------------------
; Print the string at a0.
;------------------------------------------------------------------------------
print_string:                                   ; from: cmd_search, ask_yes_no, show_cursor_here, cmd_save_binary,
                                                ;   cmd_run_mode, cmd_load_program, 6 more
	move.b	(a0)+,d1                        ; a character
	beq.s	print_string_done               ; the end
	bsr.w	print_char                      ; printed
	bra.s	print_string
print_string_done:
	rts

;------------------------------------------------------------------------------
; Print d2 spaces.
;------------------------------------------------------------------------------
print_spaces:                                   ; from: draw_help, disassemble_listing, listing_address, memory_line,
                                                ;   draw_registers, draw_disassembly, 3 more
	tst.b	d2
print_spaces_loop:
	beq.s	print_spaces_done               ; done
	bsr.s	print_space                     ; a space
	subq.b	#1,d2
	bra.s	print_spaces_loop
print_spaces_done:
	rts

;------------------------------------------------------------------------------
; Print a space.
;------------------------------------------------------------------------------
print_space:	; from: cmd_symbols, draw_help, listing_address, memory_line, memory_hex, draw_registers, 4 more
	moveq	#32,d1
	bra.w	print_char

;------------------------------------------------------------------------------
; Print "**" for an unreadable byte.
;------------------------------------------------------------------------------
print_stars:	; from: memory_hex
	moveq	#42,d1                          ; *
	bsr.w	print_char
	moveq	#42,d1                          ; *
	bra.w	print_char

;------------------------------------------------------------------------------
; Print a Return (a new line in the window).
;------------------------------------------------------------------------------
print_newline:                                  ; from: cmd_symbols, draw_help, cmd_disassemble, disassemble_listing,
                                                ;   draw_memory, draw_registers, 4 more
	moveq	#13,d1                          ; Return
	bra.w	print_char

;------------------------------------------------------------------------------
; Print d2 as 8 hex digits.
;------------------------------------------------------------------------------
print_hex_long:	; from: window_evaluate, cmd_query_port, cmd_symbols, draw_help, listing_address, memory_line, 3 more
	move.w	d2,-(sp)                        ; the low word
	swap	d2                              ; the high word first
	bsr.s	print_hex_word
	move.w	(sp)+,d2

;------------------------------------------------------------------------------
; Print d2's low word as 4 hex digits.
;------------------------------------------------------------------------------
print_hex_word:	; from: draw_registers, print_hex_long, draw_history
	move.w	d2,-(sp)
	lsr.w	#8,d2                           ; the high byte first
	bsr.s	print_hex_byte
	move.w	(sp)+,d2

;------------------------------------------------------------------------------
; Print d2's low byte as 2 hex digits.
;------------------------------------------------------------------------------
print_hex_byte:	; from: listing_address, memory_hex, print_hex_word
	move.w	d2,-(sp)
	lsr.b	#4,d2                           ; the high digit first
	bsr.s	print_hex_digit
	move.w	(sp)+,d2

;------------------------------------------------------------------------------
; Print d2's low 4 bits as a hex digit.
;------------------------------------------------------------------------------
print_hex_digit:	; from: print_hex_byte
	andi.w	#$f,d2
	move.b	hex_digits(pc,d2.w),d1          ; its character
	bra.w	print_char                      ; printed
hex_digits:
	dc.b	'0123456789ABCDEF'              ; "0123456789ABCDEF"

;------------------------------------------------------------------------------
; Print d1 in decimal.
;------------------------------------------------------------------------------
print_decimal:	; from: window_evaluate
	lea	print_char(pc),a2               ; through the character printer

;------------------------------------------------------------------------------
; Put d1 in decimal, without leading zeros, through the routine at a2 (d1 = each character).
;------------------------------------------------------------------------------
output_decimal:	; from: show_cursor_here, show_tos_error
	lea	powers_of_ten(pc),a0            ; the powers of ten
	moveq	#1,d2                           ; no digit yet
	moveq	#8,d0                           ; 9 of them, and the units
output_decimal_loop:
	moveq	#0,d3                           ; the digit
	cmp.l	(a0)+,d1                        ; below this power?
	bcs.s	output_decimal_zero             ; yes
	sub.l	-(a0),d1
output_decimal_count:
	addq.b	#1,d3                           ; one more
	sub.l	(a0),d1
	bcc.s	output_decimal_count
	add.l	(a0)+,d1                        ; back
	bra.s	output_decimal_digit
output_decimal_zero:
	tst.b	d2                              ; a digit before?
	bpl.s	output_decimal_next             ; no: a leading zero
output_decimal_digit:
	st	d2                              ; digits from now on
	addi.b	#$30,d3                         ; the character
	exg	d3,d1
	jsr	(a2)                            ; put
	exg	d3,d1
output_decimal_next:
	dbra	d0,output_decimal_loop          ; the next power
	addi.b	#$30,d1                         ; the units
	jmp	(a2)                            ; put
powers_of_ten:
	dc.w	$3b9a,$ca00,$05f5,$e100,$0098,$9680,$000f,$4240 ; 1000000000 down to 10
	dc.w	$0001,$86a0,$0000,$2710,$0000,$03e8,$0000,$0064
	dc.w	$0000,$000a

;------------------------------------------------------------------------------
; Check that the expression at a4 is good without reading memory (for a condition kept to work out later);
; Z set when it is, a4 kept.
;------------------------------------------------------------------------------
check_expression:	; from: window_breakpoint, cmd_run_mode
	move.l	a4,-(sp)
	st	eval_check_only(a6)             ; no memory reads
	bsr.w	evaluate                        ; work it out
	bne.s	check_expression_bad            ; bad
	tst.b	d1                              ; the end of the line?
	bne.s	check_expression_bad            ; no: bad
	sf	eval_check_only(a6)
	moveq	#0,d0                           ; good
	movea.l	(sp)+,a4
	rts
check_expression_bad:
	sf	eval_check_only(a6)
	moveq	#-1,d0                          ; bad
	movea.l	(sp)+,a4
	rts

;------------------------------------------------------------------------------
; Work out the expression at a4, which must end the line: d2 = its value, Z set; else the bell and d0 = -1.
;------------------------------------------------------------------------------
evaluate_line:	; from: set_registers, cmd_load_binary, show_cursor_here, cmd_run_mode
	bsr.s	evaluate
evaluate_line_check:	; from: evaluate_line_d1
	bne.s	evaluate_line_bad               ; bad
	tst.b	d1                              ; the end of the line?
	beq.s	evaluate_line_done              ; yes: good
evaluate_line_bad:
	bsr.w	bell                            ; the bell
	moveq	#-1,d0                          ; bad
evaluate_line_done:
	rts

;------------------------------------------------------------------------------
; As evaluate_line, its first character already in d1.
;------------------------------------------------------------------------------
evaluate_line_d1:	; from: window_evaluate, cmd_run_until, cmd_bdos_breakpoint
	bsr.s	evaluate_d1
	bra.s	evaluate_line_check

;------------------------------------------------------------------------------
; Work out the expression at a4: d2 = its value, d1 = the character that ended it, d0 = 0 when good, else the
; error number.
;------------------------------------------------------------------------------
evaluate:                                       ; from: window_breakpoint, cmd_query_port, cmd_write_port, cmd_search,
                                                ;   read_three_values, cmd_save_binary, 6 more
	move.b	(a4)+,d1                        ; the first character

evaluate_d1:	; from: window_breakpoint, evaluate_line_d1
	lea	operator_stack(a6),a0           ; the operator stack
	clr.w	(a0)                            ; empty
	lea	value_stack(a6),a0              ; the value stack
	clr.w	(a0)                            ; empty
	clr.b	eval_error(a6)                  ; no error
	movem.l	d4-d7,-(sp)
	bsr.w	evaluate_expression             ; work it out
	movem.l	(sp)+,d4-d7
	tst.w	operator_stack(a6)              ; operators left?
	bne.s	evaluate_bad                    ; yes: bad
	tst.w	value_stack(a6)                 ; values left?
	bne.s	evaluate_bad                    ; yes: bad
	move.b	eval_error(a6),d0               ; the error
	rts
evaluate_bad:	; from: evaluate_expression
	moveq	#1,d0                           ; bad
	rts
operator_chars:	; from: read_token
	dc.w	$132b,$142d,$062a,$072f,$0228,$0329,$157e,$0a3d ; pairs of a token and a character: + - * / ( ) ~ = & !
                                                ;   ^ { } and the number prefixes $ % @ ' " \
	dc.w	$1026,$e421,$125e,$047b,$057d,$fe24,$fa25,$f640
	dc.w	$f027,$f022,$f25c
	dc.b	$00                             ; the end
operator_priorities:	; from: evaluate_expression
	dc.b	$00,$00,$00,$00,$00,$00,$04,$04,$16,$16,$01,$01,$01,$01,$01,$01 ; each token's priority
	dc.b	$12,$12,$12,$02,$02,$1d,$1e

;------------------------------------------------------------------------------
; The binary and unary operators' routines, for tokens 6 to 22, relative to this table.
;------------------------------------------------------------------------------
operator_routines:	; from: evaluate_apply
	dc.w	op_multiply-operator_routines
	dc.w	op_divide-operator_routines
	dc.w	op_shift_left-operator_routines
	dc.w	op_shift_right-operator_routines
	dc.w	op_equal-operator_routines
	dc.w	op_not_equal-operator_routines
	dc.w	op_less-operator_routines
	dc.w	op_greater-operator_routines
	dc.w	op_less_equal-operator_routines
	dc.w	op_greater_equal-operator_routines
	dc.w	op_and-operator_routines
	dc.w	op_or-operator_routines
	dc.w	op_xor-operator_routines
	dc.w	op_add-operator_routines
	dc.w	op_subtract-operator_routines
	dc.w	op_not-operator_routines
	dc.w	op_negate-operator_routines

;------------------------------------------------------------------------------
; The evaluator: tokens are read with read_token; values go on the value stack ($13e) and operators on the
; operator stack ($12a), an operator working out those above it of the same or higher priority.  A {address}
; is the long (or .B, .W, .L) at the address.
;------------------------------------------------------------------------------
evaluate_expression:	; from: evaluate_d1
	lea	operator_stack(a6),a0           ; the operator stack
	move.w	(a0),d0
	addq.w	#2,(a0)+
	move.w	#$0,0(a0,d0.w)                  ; a 0 marker on it
	moveq	#1,d5                           ; a value expected
	bsr.w	read_token                      ; the first token
evaluate_token:
	cmp.b	#$2,d5                          ; two values in a row?
	bne.s	evaluate_token_kind             ; no
	cmp.b	#$6,d7                          ; an operator?
	bcs.w	evaluate_end                    ; no: the end
	cmp.b	#$17,d7
	bcc.w	evaluate_end
evaluate_token_kind:
	cmp.b	#$1,d7                          ; a value?
	bne.s	evaluate_token_other            ; no
evaluate_push_value:
	lea	value_stack(a6),a0              ; the value stack
	move.w	(a0),d0
	addq.w	#4,(a0)+
	move.l	d2,0(a0,d0.w)                   ; pushed
	bra.w	evaluate_next_token
evaluate_token_other:
	cmp.b	#$2,d7                          ; (?
	beq.s	evaluate_bracket                ; yes
	cmp.b	#$4,d7                          ; {?
	beq.w	evaluate_memory                 ; yes
	cmp.b	#$6,d7                          ; an operator?
	bcs.w	evaluate_finish                 ; no: the end
	cmp.b	#$17,d7
	bcc.w	evaluate_finish                 ; no: the end
	cmp.b	#$1,d5                          ; a value expected?
	bne.s	evaluate_operator               ; no: binary
	cmp.b	#$13,d7                         ; +: unary plus
	beq.s	evaluate_operator
	cmp.b	#$14,d7                         ; -: negate
	beq.s	evaluate_negate
	cmp.b	#$6,d7                          ; *: the PC
	beq.s	evaluate_pc
	cmp.b	#$15,d7                         ; ~: not
	bne.w	evaluate_bad                    ; no: bad
	bra.s	evaluate_operator
evaluate_pc:
	move.l	reg_pc(a6),d2                   ; * alone is the PC
	bra.s	evaluate_push_value
evaluate_negate:
	moveq	#22,d7                          ; negate
evaluate_operator:
	lea	operator_priorities(pc),a2      ; the priorities
	lea	operator_stack(a6),a0           ; the operator stack
	move.w	(a0),d0
	move.w	0(a0,d0.w),d6                   ; the top operator
	move.b	0(a2,d6.w),d6                   ; its priority
	cmp.b	0(a2,d7.w),d6                   ; below the new one?
	bge.s	evaluate_reduce                 ; no: work it out first
	addq.w	#2,(a0)+
	move.w	d7,0(a0,d0.w)                   ; the new one pushed
	bra.s	evaluate_expect_value
evaluate_reduce:
	bsr.w	evaluate_apply                  ; work out the top operator
	bra.s	evaluate_operator               ; and again
evaluate_expect_value:
	moveq	#0,d5                           ; a value expected
	bra.w	evaluate_next_token
evaluate_bracket:
	bsr.w	evaluate_expression             ; the bracketed expression
	lea	value_stack(a6),a0              ; its value pushed
	move.w	(a0),d0
	addq.w	#4,(a0)+
	move.l	d2,0(a0,d0.w)
	cmp.b	#$3,d7                          ; a ) after it?
	beq.s	evaluate_after_bracket          ; yes
evaluate_bad_bracket:
	move.b	#$2,eval_error(a6)              ; error 2: brackets
evaluate_after_bracket:
	moveq	#1,d5
	bra.w	evaluate_next_token
evaluate_memory:
	bsr.w	evaluate_expression             ; the address in it
	cmp.b	#$5,d7                          ; a } after it?
	bne.s	evaluate_bad_bracket            ; no: bad
	cmp.b	#$2e,d1                         ; a size?
	bne.s	evaluate_memory_long            ; no: a long
	move.b	(a4)+,d0                        ; the size
	move.b	(a4)+,d1
	andi.b	#$df,d0                         ; upper case
	cmp.b	#$42,d0                         ; B?
	beq.s	evaluate_memory_byte
	cmp.b	#$57,d0                         ; W?
	beq.s	evaluate_memory_word
	cmp.b	#$4c,d0                         ; L?
	beq.s	evaluate_memory_long
	move.b	#$7,eval_error(a6)              ; error 7: a bad size
	bra.s	evaluate_next_token
evaluate_memory_byte:
	movea.l	d2,a2                           ; the address
	bsr.w	check_address                   ; readable?
	bne.s	evaluate_memory_bad             ; no
	movea.l	d2,a0
	moveq	#0,d2
	move.b	(a0),d2                         ; the byte
	bra.s	evaluate_memory_push
evaluate_memory_word:
	btst	#$0,d2                          ; odd?
	bne.s	evaluate_memory_bad             ; yes: bad
	movea.l	d2,a2
	bsr.w	check_address                   ; readable?
	bne.s	evaluate_memory_bad             ; no
	moveq	#0,d2
	move.w	(a2),d2                         ; the word
	bra.s	evaluate_memory_push
evaluate_memory_long:
	btst	#$0,d2                          ; odd?
	bne.s	evaluate_memory_bad             ; yes: bad
	movea.l	d2,a2
	bsr.w	check_address                   ; readable?
	bne.s	evaluate_memory_bad             ; no
	addq.l	#3,a2                           ; its end
	bsr.w	check_address                   ; readable?
	bne.s	evaluate_memory_bad             ; no
	movea.l	d2,a0
	move.l	(a0),d2                         ; the long
evaluate_memory_push:
	lea	value_stack(a6),a0              ; the value stack
	move.w	(a0),d0
	addq.w	#4,(a0)+
	move.l	d2,0(a0,d0.w)                   ; pushed
	moveq	#1,d5
	bra.s	evaluate_next_token
evaluate_memory_bad:
	tst.b	eval_check_only(a6)             ; only checking?
	bne.s	evaluate_memory_push            ; yes: any value
	move.b	#$6,eval_error(a6)              ; error 6: no memory there
evaluate_next_token:
	addq.w	#1,d5
	bsr.w	read_token                      ; the next token
	bra.w	evaluate_token
evaluate_end:
	cmp.b	#$3,d7                          ; )?
	beq.s	evaluate_finish                 ; yes
	cmp.b	#$5,d7                          ; }?
	beq.s	evaluate_finish                 ; yes
	movea.l	a0,a4                           ; back to the character
	move.b	-$1(a4),d1
evaluate_finish:
	lea	operator_priorities(pc),a2      ; the priorities
evaluate_finish_loop:
	lea	operator_stack(a6),a0           ; the operator stack
	move.w	(a0),d0
	tst.w	0(a0,d0.w)                      ; the marker?
	beq.s	evaluate_finish_done            ; yes: done
	bsr.w	evaluate_apply                  ; work out the top operator
	bra.s	evaluate_finish_loop
evaluate_finish_done:
	subq.w	#2,operator_stack(a6)           ; the marker off
	lea	value_stack(a6),a0              ; the value stack
	subq.w	#4,(a0)
	move.w	(a0)+,d0
	move.l	0(a0,d0.w),d2                   ; d2 = the result
	rts
evaluate_underflow_pop:	; from: evaluate_apply
	move.w	(sp)+,d1
evaluate_underflow:	; from: evaluate_apply
	move.w	#$4,(a0)
	move.b	#$8,eval_error(a6)              ; error 8: a value missing
	rts

;------------------------------------------------------------------------------
; Work out the operator on top of the operator stack with the values on top of the value stack.
;------------------------------------------------------------------------------
evaluate_apply:	; from: evaluate_expression
	lea	value_stack(a6),a0              ; the value stack
	subq.w	#4,(a0)
	bcs.s	evaluate_underflow              ; empty: bad
	move.w	(a0)+,d0
	move.l	0(a0,d0.w),d2                   ; the right value
	move.w	d1,-(sp)
	lea	operator_stack(a6),a1           ; the operator stack
	subq.w	#2,(a1)
	move.w	(a1)+,d1
	move.w	0(a1,d1.w),d1                   ; the operator
	cmp.b	#$15,d1                         ; unary?
	bcc.s	evaluate_apply_run              ; yes
	subq.w	#4,-(a0)
	bcs.s	evaluate_underflow_pop          ; no left value: bad
	move.w	(a0)+,d0
	move.l	0(a0,d0.w),d0                   ; the left value
	exg	d0,d2
evaluate_apply_run:
	lea	operator_routines(pc),a1        ; the routines
	add.w	d1,d1                           ; words
	move.w	-$c(a1,d1.w),d1                 ; its offset
	jsr	0(a1,d1.w)                      ; worked out
	move.w	(sp)+,d1
	move.w	-(a0),d0
	addq.w	#4,(a0)+
	move.l	d2,0(a0,d0.w)                   ; the result pushed
	rts
op_add:	; from: operator_routines
	add.l	d0,d2
	rts
op_subtract:	; from: operator_routines
	sub.l	d0,d2
	rts
op_divide:	; from: operator_routines
	move.l	d7,-(sp)
	bsr.w	divide_32
	movem.l	(sp)+,d7
	beq.s	op_divide_done
	move.b	d0,eval_error(a6)               ; divide by 0
op_divide_done:
	rts
op_and:	; from: operator_routines
	and.l	d0,d2
	rts
op_or:	; from: operator_routines
	or.l	d0,d2
	rts
op_xor:	; from: operator_routines
	eor.l	d0,d2
	rts
op_shift_left:	; from: operator_routines
	lsl.l	d0,d2
	rts
op_shift_right:	; from: operator_routines
	lsr.l	d0,d2
	rts
op_equal:	; from: operator_routines
	cmp.l	d0,d2
	seq	d2
op_flag:
	ext.w	d2                              ; -1 or 0
	ext.l	d2
	rts
op_less:	; from: operator_routines
	cmp.l	d0,d2
	slt	d2
	bra.s	op_flag
op_greater:	; from: operator_routines
	cmp.l	d0,d2
	sgt	d2
	bra.s	op_flag
op_not_equal:	; from: operator_routines
	cmp.l	d0,d2
	sne	d2
	bra.s	op_flag
op_less_equal:	; from: operator_routines
	cmp.l	d0,d2
	sle	d2
	bra.s	op_flag
op_greater_equal:	; from: operator_routines
	cmp.l	d0,d2
	sge	d2
	bra.s	op_flag
op_not:	; from: operator_routines
	not.l	d2
	rts
op_negate:	; from: operator_routines
	neg.l	d2
	rts
op_multiply:	; from: operator_routines
	move.l	d2,d6                           ; the result's sign
	eor.l	d0,d6
	tst.l	d2
	bgt.s	op_multiply_signs
	neg.l	d2                              ; made positive
op_multiply_signs:
	tst.l	d0
	bgt.s	op_multiply_parts
	neg.l	d0                              ; made positive
op_multiply_parts:
	move.l	d2,d3
	swap	d3
	mulu.w	d0,d2                           ; low * low
	swap	d0
	tst.w	d3
	beq.s	op_multiply_low
	swap	d0
	bra.s	op_multiply_high
op_multiply_low:
	tst.w	d0
	beq.s	op_multiply_sign
	swap	d3
op_multiply_high:
	mulu.w	d3,d0                           ; high * low
	swap	d0
	add.l	d0,d2                           ; added
op_multiply_sign:
	tst.l	d6
	bpl.s	op_multiply_done
	neg.l	d2
op_multiply_done:
	rts

;------------------------------------------------------------------------------
; Divide d2 by d0, both 32 bits and signed: d2 = the quotient, d0 = the remainder, Z set; d0 = 3 (Z clear) to
; divide by 0.
;------------------------------------------------------------------------------
divide_32:	; from: evaluate_apply, symbol_hash_slot
	tst.l	d0                              ; by 0?
	beq.s	divide_32_by_zero               ; yes
	move.l	d2,d6
	eor.l	d0,d6                           ; the quotient's sign
	move.l	d6,-(sp)
	move.l	d2,-(sp)                        ; the remainder's
	tst.l	d0
	bpl.s	divide_32_signs
	neg.l	d0                              ; made positive
divide_32_signs:
	tst.l	d2
	bpl.s	divide_32_align
	neg.l	d2                              ; made positive
divide_32_align:
	moveq	#31,d6
	move.l	d0,d7
	moveq	#0,d0
divide_32_shift:
	add.l	d7,d7                           ; the divisor up to the top bit
	dbcs	d6,divide_32_shift
	roxr.l	#1,d7
	subi.w	#$1f,d6                         ; the bit count
	neg.w	d6
divide_32_loop:
	add.l	d0,d0                           ; a quotient bit
	cmp.l	d7,d2                           ; fits?
	bcs.s	divide_32_next                  ; no
	addq.l	#1,d0                           ; yes
	sub.l	d7,d2
divide_32_next:
	lsr.l	#1,d7
	dbra	d6,divide_32_loop               ; for each bit
	move.l	(sp)+,d6
	bpl.s	divide_32_sign
	neg.l	d2                              ; the remainder's sign
divide_32_sign:
	move.l	(sp)+,d6
	bpl.s	divide_32_done
	neg.l	d0                              ; the quotient's sign
divide_32_done:
	exg	d0,d2
	cmp.b	d0,d0                           ; Z set
	rts
divide_32_by_zero:
	moveq	#3,d0                           ; error 3
	rts

;------------------------------------------------------------------------------
; Z set when d1 can be in a name: a letter, a digit, _ or . (or above $7f).
;------------------------------------------------------------------------------
symbol_char:	; from: read_token
	tst.b	d1                              ; above $7f?
	bmi.s	symbol_char_yes                 ; yes
	cmp.b	#$2e,d1                         ; .?
	beq.s	symbol_char_yes                 ; yes
	cmp.b	#$30,d1                         ; below 0?
	bcs.s	symbol_char_no                  ; no
	cmp.b	#$3a,d1                         ; a digit?
	bcs.s	symbol_char_yes                 ; yes
	cmp.b	#$40,d1                         ; below @?
	bcs.s	symbol_char_no                  ; no
	cmp.b	#$5b,d1                         ; A-Z?
	bcs.s	symbol_char_yes                 ; yes
	cmp.b	#$5f,d1                         ; _?
	beq.s	symbol_char_yes                 ; yes
	cmp.b	#$61,d1                         ; below a?
	bcs.s	symbol_char_no                  ; no
	cmp.b	#$7b,d1                         ; a-z?
	bcs.s	symbol_char_yes                 ; yes
symbol_char_no:
	moveq	#-1,d0
	rts
symbol_char_yes:
	moveq	#0,d0
	rts

;------------------------------------------------------------------------------
; Read the token at d1/a4: d7 = its kind (1 a value in d2, else an operator), d1 the next character.  Names are
; registers or symbols; numbers are decimal, or $ hex, % binary, @ octal, \ decimal, or 'text'.
;------------------------------------------------------------------------------
read_token:	; from: evaluate_expression
	movem.l	d5-d6/a1-a2,-(sp)
	move.l	a4,-(sp)
	moveq	#0,d7
	lea	operator_chars(pc),a0           ; the operator characters
read_token_operator:
	move.b	(a0)+,d7                        ; a token
	beq.s	read_token_other                ; the end of the table
	cmp.b	(a0)+,d1                        ; this character?
	bne.s	read_token_operator             ; no
	tst.b	d7                              ; a number prefix?
	bmi.w	read_token_prefix               ; yes
	bra.w	read_token_next                 ; an operator
read_token_other:
	cmp.b	#$3c,d1                         ; <?
	beq.w	read_token_less
	cmp.b	#$3e,d1                         ; >?
	beq.s	read_token_greater
	moveq	#0,d2
	cmp.b	#$3a,d1                         ; a digit?
	bcc.s	read_token_name                 ; no
	cmp.b	#$30,d1
	bcc.s	read_token_decimal              ; yes: decimal
read_token_name:
	moveq	#1,d7                           ; a value
	bsr.s	symbol_char                     ; a name character?
	bne.s	read_token_bad                  ; no
	lea	-$1(a4),a1                      ; the name's start
	moveq	#0,d2                           ; its length
read_token_name_loop:
	addq.w	#1,d2
	move.b	(a4)+,d1
	bsr.w	symbol_char
	beq.s	read_token_name_loop
	bsr.w	find_register                   ; a register?
	bne.s	read_token_symbol               ; no
	move.l	(a0),d2                         ; its value
	bra.w	read_token_value
read_token_symbol:
	move.l	a1,-(sp)
	bsr.w	find_symbol_name                ; a symbol?
	movea.l	(sp)+,a1
	beq.w	read_token_value                ; yes
	movea.l	a1,a4                           ; no: as a hex number
	moveq	#0,d2
	bra.w	read_token_hex
read_token_bad:
	moveq	#23,d7                          ; token 23: bad
	bra.s	read_token_done
read_token_bang:
	move.b	(a4)+,d1                        ; =?
	cmp.b	#$3d,d1                         ; !=
	beq.s	read_token_not_equal
	moveq	#17,d7                          ; ! alone: token 17
	bra.s	read_token_done
read_token_less:
	moveq	#12,d7                          ; < : 12
	move.b	(a4)+,d1
	cmp.b	#$3c,d1                         ; <<?
	beq.s	read_token_shift
	cmp.b	#$3e,d1                         ; <>?
	beq.s	read_token_not_equal
	bra.s	read_token_or_equal
read_token_not_equal:
	moveq	#11,d7                          ; token 11
	bra.s	read_token_next
read_token_greater:
	moveq	#13,d7                          ; > : 13
	move.b	(a4)+,d1
	cmp.b	#$3e,d1                         ; >>?
	beq.s	read_token_shift
read_token_or_equal:
	cmp.b	#$3d,d1                         ; <= or >=?
	bne.s	read_token_done                 ; no
	addq.w	#2,d7
	bra.s	read_token_next
read_token_shift:
	subq.w	#4,d7                           ; << or >>
read_token_next:
	move.b	(a4)+,d1                        ; the next character
read_token_done:
	movea.l	(sp)+,a0
	movem.l	(sp)+,d5-d6/a1-a2
	rts
read_token_decimal:
	moveq	#0,d2
	subq.l	#1,a4                           ; back to the digit
	moveq	#1,d7                           ; a value
	bra.w	read_token_hex
read_token_backslash:
	move.b	(a4)+,d1                        ; a digit?
	cmp.b	#$30,d1
	bcs.w	read_token_error_4              ; no: bad
	cmp.b	#$3a,d1
	bcc.w	read_token_error_4              ; no: bad
read_token_decimal_loop:
	add.l	d2,d2                           ; * 10
	move.l	d2,d0
	add.l	d0,d0
	add.l	d0,d0
	add.l	d0,d2
	subi.b	#$30,d1                         ; + the digit
	andi.l	#$f,d1
	add.l	d1,d2
	move.b	(a4)+,d1                        ; the next
	cmp.b	#$3a,d1                         ; a digit?
	bcc.s	read_token_value                ; no
	cmp.b	#$30,d1
	bcc.s	read_token_decimal_loop         ; yes
read_token_value:
	moveq	#1,d7                           ; a value
	bra.s	read_token_done
read_token_prefix:
	neg.b	d7                              ; the prefix's number
	ext.w	d7
	moveq	#0,d2
	moveq	#1,d0
	exg	d0,d7
prefix_jump:
	jmp	prefix_jump+2(pc,d0.w)          ; to its routine
	bra.w	read_token_hex
	bra.w	read_token_binary
	bra.w	read_token_octal
	bra.s	read_token_backslash
	bra.w	read_token_string
	bra.w	read_token_less
	bra.w	read_token_greater
	bra.w	read_token_bang
read_token_string:
	moveq	#4,d0                           ; up to 4 characters
	move.b	d1,d3                           ; the quote
read_token_string_loop:
	move.b	(a4)+,d1                        ; a character
	cmp.b	#$d,d1                          ; the line's end?
	beq.w	read_token_error_4              ; yes: bad
	cmp.b	d3,d1                           ; the quote?
	bne.s	read_token_string_char          ; no
	move.b	(a4)+,d1
	cmp.b	d3,d1                           ; doubled?
	beq.s	read_token_string_char          ; yes: one quote
	bra.w	read_token_done                 ; no: the end
read_token_string_char:
	subq.b	#1,d0                           ; room?
	bcs.w	read_token_error_5              ; no: too big
	lsl.l	#8,d2
	move.b	d1,d2                           ; in
	bra.s	read_token_string_loop
read_token_binary:
	move.b	(a4)+,d1
	subi.b	#$30,d1                         ; 0 or 1?
	bcs.s	read_token_error_4              ; no: bad
	cmp.b	#$2,d1
	bcc.s	read_token_error_4
read_token_binary_loop:
	add.l	d2,d2
	bcs.s	read_token_error_5              ; too big
	or.b	d1,d2                           ; in
	move.b	(a4)+,d1                        ; the next
	subi.b	#$30,d1
	bcs.s	read_token_number_done
	cmp.b	#$2,d1
	bcs.s	read_token_binary_loop
	bra.s	read_token_number_done
read_token_octal:
	move.b	(a4),d0                         ; the next character
	subi.b	#$30,d0
	bcs.s	read_token_at                   ; not a digit: @ alone
	cmp.b	#$9,d0
	bcc.s	read_token_at
	move.b	d0,d1
	addq.l	#1,a4
read_token_octal_loop:
	lsl.l	#3,d2
	bcs.s	read_token_error_5              ; too big
	or.b	d1,d2                           ; in
	move.b	(a4)+,d1                        ; the next
	subi.b	#$30,d1
	bcs.s	read_token_number_done
	cmp.b	#$9,d1
	bcs.s	read_token_octal_loop
	bra.s	read_token_number_done
read_token_hex:
	lea	hex_digit_values(pc),a0         ; the hex digit values
	moveq	#0,d1
	move.b	(a4)+,d1                        ; a character
	bmi.s	read_token_error_4
	move.b	0(a0,d1.w),d1                   ; its value
	bmi.s	read_token_error_4              ; not a digit: bad
read_token_hex_loop:
	lsl.l	#4,d2
	or.b	d1,d2                           ; in
	move.b	(a4)+,d1                        ; the next
	bmi.s	read_token_number_done
	move.b	0(a0,d1.w),d1
	bpl.s	read_token_hex_loop
read_token_number_done:
	move.b	-$1(a4),d1                      ; the character after it
	bra.w	read_token_done
read_token_at:
	moveq	#64,d1                          ; @ as a name
	bra.w	read_token_name
read_token_error_4:
	moveq	#4,d0                           ; error 4: a bad number
read_token_error:
	tst.b	eval_error(a6)                  ; an error already?
	bne.s	read_token_number_done          ; yes
	move.b	d0,eval_error(a6)
	bra.s	read_token_number_done
read_token_error_5:
	moveq	#5,d0                           ; error 5: too big
	bra.s	read_token_error
hex_digit_values:
	dcb.w	24,$ffff                        ; each character's hex value, $ff for none
	dc.w	$0001,$0203,$0405,$0607,$0809,$ffff,$ffff,$ffff
	dc.w	$ff0a,$0b0c,$0d0e,$0fff,$ffff,$ffff,$ffff,$ffff
	dcb.w	8,$ffff
	dc.w	$ff0a,$0b0c,$0d0e,$0fff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff

;------------------------------------------------------------------------------
; Make a hash table for looking symbols up by value: half again as many slots as d0/14 symbols, odd, cleared.
;------------------------------------------------------------------------------
alloc_symbol_hash:	; from: load_program
	tst.l	symbols(a6)                     ; symbols?
	beq.s	alloc_symbol_hash_done          ; no
	divu.w	#$e,d0                          ; their count
	beq.s	alloc_symbol_hash_done          ; none
	moveq	#0,d4
	move.w	d0,d4
	move.l	d4,d0
	add.l	d0,d0
	add.l	d4,d0
	lsr.l	#1,d0                           ; * 1.5
	bset	#$0,d0                          ; odd
	addq.l	#2,d0                           ; + 2
	move.l	d0,symbol_hash_size(a6)         ; the slots
	add.l	d0,d0
	add.l	d0,d0                           ; 4 bytes each
	addq.l	#4,d0                           ; + 4
	move.l	d0,-(sp)
	bsr.w	malloc                          ; Malloc
	movem.l	(sp)+,d1
	move.l	d0,symbol_hash(a6)              ; the table
	beq.s	alloc_symbol_hash_done          ; none
	movea.l	d0,a0
	lsr.l	#2,d1                           ; in longs
alloc_symbol_hash_clear:
	clr.l	(a0)+                           ; cleared
	subq.l	#1,d1
	bne.s	alloc_symbol_hash_clear
alloc_symbol_hash_done:
	rts

;------------------------------------------------------------------------------
; Put every symbol into the hash table by its value.
;------------------------------------------------------------------------------
fill_symbol_hash:	; from: load_program
	movem.l	d6-d7,-(sp)
	tst.l	symbol_hash(a6)                 ; a table?
	beq.s	fill_symbol_hash_done           ; no
	movea.l	symbols(a6),a0                  ; the symbols
fill_symbol_hash_loop:
	tst.b	(a0)                            ; the end?
	beq.s	fill_symbol_hash_done           ; yes
	cmpi.b	#$ff,(a0)                       ; left out?
	beq.s	fill_symbol_hash_next           ; yes
	move.l	$a(a0),d0                       ; its value
	move.l	a0,-(sp)
	bsr.s	symbol_hash_slot                ; its slot
	movea.l	(sp)+,a0
	beq.s	fill_symbol_hash_next           ; taken by another of that value
	move.l	a0,(a1)                         ; in
fill_symbol_hash_next:
	lea	$e(a0),a0                       ; the next
	tst.b	-$5(a0)                         ; a long name?
	beq.s	fill_symbol_hash_loop           ; no
	lea	$e(a0),a0                       ; past its second part
	bra.s	fill_symbol_hash_loop
fill_symbol_hash_done:
	movem.l	(sp)+,d6-d7
	rts

;------------------------------------------------------------------------------
; Find the hash slot for the value d0: Z set and a1 = the symbol with it, else Z clear and a1 = an empty slot.
;------------------------------------------------------------------------------
symbol_hash_slot:	; from: fill_symbol_hash
	movea.l	symbol_hash(a6),a1              ; the table
	move.l	symbol_hash_size(a6),d2         ; its size
	move.l	d0,d6                           ; the value
	divu.w	d2,d6                           ; mod the size
	bvc.s	symbol_hash_index               ; fits in 16 bits
	movem.l	d0/d2,-(sp)
	exg	d2,d0
	bsr.w	divide_32                       ; a long division
	move.l	d0,d6
	swap	d6
	movem.l	(sp)+,d0/d2
symbol_hash_index:
	swap	d6                              ; the remainder
	ext.l	d6
	bpl.s	symbol_hash_offset
	neg.l	d6
symbol_hash_offset:
	add.l	d6,d6                           ; in longs
	add.l	d6,d6
	add.l	d2,d2                           ; the table's size in bytes
	add.l	d2,d2
symbol_hash_probe:
	move.l	0(a1,d6.l),d7                   ; a slot
	beq.s	symbol_hash_empty               ; empty: not there
	movea.l	d7,a0
	cmp.l	$a(a0),d0                       ; this value?
	beq.s	symbol_hash_found               ; yes
	addq.l	#4,d6                           ; the next slot
	cmp.l	d6,d2                           ; the end?
	bne.s	symbol_hash_probe               ; no
	moveq	#0,d6                           ; round to the start
	bra.s	symbol_hash_probe
symbol_hash_found:
	movea.l	a0,a1
	rts                                     ; Z set
symbol_hash_empty:
	lea	0(a1,d6.l),a1                   ; the empty slot
	moveq	#-1,d7                          ; Z clear
	rts
find_symbol_hash:	; from: find_symbol
	movem.l	d1-d2/d6-d7/a0-a1,-(sp)
	tst.l	d0
	bmi.s	find_symbol_hash_none
	bsr.s	symbol_hash_slot                ; in the table?
	beq.s	find_symbol_hash_found          ; yes
find_symbol_hash_none:
	moveq	#0,d0                           ; none
	bra.s	find_symbol_hash_done
find_symbol_hash_found:
	move.l	a1,d0                           ; the symbol
find_symbol_hash_done:
	movem.l	(sp)+,d1-d2/d6-d7/a0-a1
	rts

;------------------------------------------------------------------------------
; d0 = the symbol (its entry) for the address d0, or 0, Z set then: from the hash table, else by searching the
; symbols; in a disassembly with labels, the label list is used (and filled in on its first pass).
;------------------------------------------------------------------------------
find_symbol:                                    ; from: window_evaluate, draw_help, cmd_disassemble,
                                                ;   disassemble_listing, listing_address, draw_disassembly, 3 more
	tst.l	symbols(a6)                     ; symbols?
	beq.s	find_label                      ; no
	cmp.l	prog_text(a6),d0                ; below the text?
	bcs.s	find_label                      ; yes
	cmp.l	prog_end(a6),d0                 ; past the program?
	bcc.s	find_label                      ; yes
	tst.l	symbol_hash(a6)                 ; a hash table?
	bne.s	find_symbol_hash                ; yes
	movem.l	d1-d2/a0,-(sp)
	moveq	#0,d2
	moveq	#14,d1                          ; 14 bytes an entry
	movea.l	symbols(a6),a0
	suba.w	d1,a0
find_symbol_loop:
	adda.w	d1,a0                           ; the next
	tst.b	(a0)                            ; the end?
	beq.s	find_symbol_done                ; yes
	cmpi.b	#$ff,(a0)                       ; left out?
	beq.s	find_symbol_loop                ; yes
	cmp.l	$a(a0),d0                       ; this value?
	beq.s	find_symbol_check               ; yes
find_symbol_skip:
	tst.b	9(a0)                           ; a long name?
	beq.s	find_symbol_loop                ; no
	adda.w	d1,a0                           ; past its second part
	bra.s	find_symbol_loop
find_symbol_check:
	cmp.b	8(a0),d2                        ; a plain symbol?
	bne.s	find_symbol_skip                ; no
	move.l	a0,d0                           ; found
find_symbol_done:
	movem.l	(sp)+,d1-d2/a0
	rts
find_label:
	tst.b	xref_pass(a6)                   ; labels?
	bne.s	find_label_range                ; yes
	rts
find_label_range:
	cmp.l	disasm_start(a6),d0             ; in the disassembled range?
	bcs.s	find_label_none                 ; no
	cmp.l	disasm_end(a6),d0
	bcc.s	find_label_none                 ; no
	movem.l	d1/a0,-(sp)
	tst.b	xref_pass(a6)                   ; the first pass?
	bmi.s	find_label_lookup               ; no: look up
	movea.l	xref_start(a6),a0               ; the label list
find_label_add_loop:
	move.l	(a0)+,d1                        ; a label
	beq.s	find_label_add                  ; the end
	cmp.l	d0,d1                           ; this one?
	bne.s	find_label_add_loop             ; no
find_label_done:
	movem.l	(sp)+,d1/a0
find_label_none:
	moveq	#0,d0                           ; none
	rts
find_label_add:
	tst.l	xref_end(a6)                    ; a limit?
	beq.s	find_label_store                ; no
	cmpa.l	xref_end(a6),a0                 ; the list full?
	bge.s	find_label_done                 ; yes
find_label_store:
	move.l	d0,-$4(a0)                      ; added
	clr.l	(a0)                            ; the new end
	bra.s	find_label_done
find_label_lookup:
	movea.l	xref_start(a6),a0               ; the label list
find_label_lookup_loop:
	move.l	(a0)+,d1                        ; a label
	beq.s	find_label_done                 ; the end: none
	cmp.l	d1,d0                           ; this one?
	bne.s	find_label_lookup_loop          ; no
	lea	label_name(a6),a0               ; a made-up symbol
	clr.b	9(a0)                           ; a short name
	move.b	#$4c,(a0)+                      ; L
	exg	a4,a0
	move.l	d0,d1                           ; the address
	bsr.w	put_hex                         ; in hex: "L" and its address
	exg	a4,a0
	clr.b	(a0)                            ; ended
	lea	label_name(a6),a0
	move.l	a0,d0                           ; the symbol
	movem.l	(sp)+,d1/a0
	rts

;------------------------------------------------------------------------------
; Print the symbol entry d0's name (8 characters, and the rest of a long name), at most d2 characters, d2
; counted down.
;------------------------------------------------------------------------------
print_symbol_name:	; from: draw_help, listing_address, draw_disassembly, draw_history
	movea.l	d0,a0
	moveq	#7,d0                           ; 8 characters
print_symbol_name_loop:
	move.b	(a0)+,d1                        ; a character
	beq.s	print_symbol_name_done          ; the end
	bsr.w	print_char                      ; printed
	subq.b	#1,d2                           ; one less room
	dbeq	d0,print_symbol_name_loop
	beq.s	print_symbol_name_done          ; no room
	tst.b	1(a0)                           ; a long name?
	beq.s	print_symbol_name_done          ; no
	moveq	#13,d0
	addq.l	#6,a0                           ; its second part
	moveq	#7,d0                           ; 8 more
print_symbol_name_long:
	move.b	(a0)+,d1                        ; a character
	beq.s	print_symbol_name_done          ; the end
	bsr.w	print_char                      ; printed
	subq.b	#1,d2
	dbeq	d0,print_symbol_name_long
print_symbol_name_done:
	rts

;------------------------------------------------------------------------------
; Z set.
;------------------------------------------------------------------------------
always_found:	; from: ea_register_value
	cmp.b	d0,d0
	rts

;------------------------------------------------------------------------------
; Find the symbol named at a1, d2 characters (at most the symbol length): d2 = its value and d0 = 0, else
; d0 = -1.  The case is ignored when the preference says so.
;------------------------------------------------------------------------------
find_symbol_name:	; from: read_token
	move.l	d4,-(sp)
	tst.l	symbols(a6)                     ; symbols?
	beq.w	find_symbol_name_none           ; no
	clr.l	-(sp)                           ; 8 bytes on the stack for the name
	clr.l	-(sp)
	movea.l	sp,a0
	moveq	#0,d0
	move.b	d2,d0                           ; the length
	cmp.w	symbol_length(a6),d2            ; longer than the symbol length?
	ble.s	find_symbol_name_case           ; no
	move.w	symbol_length(a6),d2            ; cut to it
find_symbol_name_case:
	tst.b	ignore_case(a6)                 ; ignore case?
	bne.w	find_symbol_name_nocase         ; yes
	subq.b	#1,d0
	cmp.w	#$8,d2                          ; 8 or more?
	bcs.s	find_symbol_name_copy           ; no
	moveq	#7,d0                           ; the first 8
find_symbol_name_copy:
	move.b	(a1)+,(a0)+                     ; copied
	dbra	d0,find_symbol_name_copy
	move.l	(sp)+,d4                        ; d4, d3 = the first 8 characters
	move.l	(sp)+,d3
	movea.l	symbols(a6),a0                  ; the symbols
find_symbol_name_loop:
	move.b	(a0),d0
	beq.s	find_symbol_name_none           ; the end: none
	addq.b	#1,d0
	beq.s	find_symbol_name_next           ; left out
	cmp.l	(a0),d4                         ; the first 4 characters?
	bne.s	find_symbol_name_next           ; no
	cmp.l	4(a0),d3                        ; the next 4?
	bne.s	find_symbol_name_next           ; no
	tst.b	9(a0)                           ; a long name?
	bne.s	find_symbol_name_long           ; yes
	cmp.w	#$8,d2                          ; 8 or less?
	ble.s	find_symbol_name_found          ; yes: found
	bra.s	find_symbol_name_next           ; no
find_symbol_name_long:
	moveq	#8,d0                           ; the 9th character on
	move.w	d1,-(sp)
find_symbol_name_long_loop:
	move.b	6(a0,d0.w),d1                   ; the entry's
	cmp.b	-$8(a1,d0.w),d1                 ; the name's
	bne.s	find_symbol_name_differ         ; not the same
	addq.w	#1,d0
	cmp.w	d0,d2                           ; all of the name?
	bne.s	find_symbol_name_long_loop      ; no
	move.w	(sp)+,d1
	cmp.w	symbol_length(a6),d2            ; cut at the symbol length?
	beq.s	find_symbol_name_found          ; yes: found
	tst.b	6(a0,d0.w)                      ; the entry longer?
	bne.s	find_symbol_name_next           ; yes: not it
find_symbol_name_found:	; from: upper_case
	move.l	$a(a0),d2                       ; its value
	move.l	(sp)+,d4
	moveq	#0,d0                           ; found
	rts
find_symbol_name_differ:
	move.w	(sp)+,d1
find_symbol_name_next:
	lea	$e(a0),a0                       ; the next entry
	tst.b	-$5(a0)                         ; a long name?
	beq.s	find_symbol_name_loop           ; no
	lea	$e(a0),a0                       ; past its second part
	bra.s	find_symbol_name_loop
find_symbol_name_none:	; from: upper_case
	move.l	(sp)+,d4
	moveq	#-1,d0                          ; none
	rts
find_symbol_name_nocase:
	addq.l	#8,sp                           ; the stack back
	lea	output_buffer(a6),a0            ; the name in upper case
	move.w	d1,-(sp)
	move.w	d2,d0
	subq.w	#1,d0
find_symbol_name_upper:
	move.b	(a1)+,d1                        ; a character
	bsr.s	upper_case                      ; upper case
	move.b	d1,(a0)+
	dbra	d0,find_symbol_name_upper
	lea	output_buffer+22(a6),a1         ; the buffer's end
	suba.l	a0,a1
	move.w	a1,d0                           ; room left?
	beq.s	find_symbol_name_nocase_loop    ; no
	subq.w	#1,d0
find_symbol_name_pad:
	clr.b	(a0)+                           ; padded with 0
	dbra	d0,find_symbol_name_pad
	bra.s	find_symbol_name_nocase_loop

;------------------------------------------------------------------------------
; d1 in upper case if it is a-z.
;------------------------------------------------------------------------------
upper_case:	; from: cmd_search, search_bytes, search_source, search_instruction, find_symbol_name
	cmp.b	#$61,d1                         ; below a?
	bcs.s	upper_case_done                 ; yes
	cmp.b	#$7b,d1                         ; above z?
	bcc.s	upper_case_done                 ; yes
	andi.b	#$df,d1                         ; upper case
upper_case_done:
	rts
find_symbol_name_nocase_loop:	; from: find_symbol_name
	movea.l	symbols(a6),a0                  ; the symbols
	move.w	d2,d4
	cmp.w	#$8,d2                          ; up to 8 characters
	ble.s	find_symbol_name_nocase_first
	moveq	#8,d4
find_symbol_name_nocase_first:
	subq.w	#1,d4
	move.w	d2,d3
	subi.w	#$9,d3                          ; the characters past 8
find_symbol_name_nocase_entry:
	move.b	(a0),d0
	beq.s	find_symbol_name_nocase_none    ; the end: none
	addq.b	#1,d0
	beq.s	find_symbol_name_nocase_next    ; left out
	move.w	d4,d0
	move.l	a0,-(sp)
	lea	output_buffer(a6),a1            ; the name
find_symbol_name_nocase_compare:
	move.b	(a0)+,d1                        ; a character
	bsr.s	upper_case                      ; upper case
	cmp.b	(a1)+,d1                        ; the same?
	bne.s	find_symbol_name_nocase_differ  ; no
	dbra	d0,find_symbol_name_nocase_compare
	move.w	d3,d0                           ; longer than 8?
	bpl.s	find_symbol_name_nocase_long    ; yes
	tst.b	1(a0)                           ; the entry long?
	bne.s	find_symbol_name_nocase_differ  ; yes: not it
	tst.b	(a0)                            ; a 9th character?
	bne.s	find_symbol_name_nocase_differ  ; yes: not it
	bra.s	find_symbol_name_nocase_found   ; found
find_symbol_name_nocase_long:
	tst.b	1(a0)                           ; a long name?
	beq.s	find_symbol_name_nocase_differ  ; no: not it
	addq.l	#6,a0                           ; its second part
find_symbol_name_nocase_long_loop:
	move.b	(a0)+,d1                        ; a character
	bsr.s	upper_case                      ; upper case
	cmp.b	(a1)+,d1                        ; the same?
	bne.s	find_symbol_name_nocase_differ  ; no
	dbra	d0,find_symbol_name_nocase_long_loop
	cmp.w	symbol_length(a6),d2            ; cut at the symbol length?
	beq.s	find_symbol_name_nocase_found   ; yes: found
	tst.b	(a0)                            ; the entry longer?
	beq.s	find_symbol_name_nocase_found   ; no: found
find_symbol_name_nocase_differ:
	movea.l	(sp)+,a0
find_symbol_name_nocase_next:
	lea	$e(a0),a0                       ; the next entry
	tst.b	-$5(a0)                         ; a long name?
	beq.s	find_symbol_name_nocase_entry   ; no
	lea	$e(a0),a0                       ; past its second part
	bra.s	find_symbol_name_nocase_entry
find_symbol_name_nocase_found:
	movea.l	(sp)+,a0
	move.w	(sp)+,d1
	bra.w	find_symbol_name_found
find_symbol_name_nocase_none:
	move.w	(sp)+,d1
	bra.w	find_symbol_name_none

;------------------------------------------------------------------------------
; Fcreate the file named at a0: d3 = its handle, Z set; else d0 = the error.
;------------------------------------------------------------------------------
create_file:	; from: cmd_save_binary, cmd_disassemble
	clr.w	-(sp)                           ; Fcreate(a0, 0)
	move.l	a0,-(sp)
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	move.w	d0,d3                           ; the handle
	bmi.s	file_done                       ; failed
	moveq	#0,d0
	rts

;------------------------------------------------------------------------------
; Fopen the file named at a0 to read: d3 = its handle, Z set; else d0 = the error.
;------------------------------------------------------------------------------
open_file:	; from: settings, load_file, load_program
	clr.w	-(sp)                           ; Fopen(a0, 0)
	move.l	a0,-(sp)
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.w	d0,d3                           ; the handle
	bmi.s	file_done                       ; failed
	moveq	#0,d0
file_done:	; from: create_file
	rts

;------------------------------------------------------------------------------
; d4 = the length of the open file d3 (Fseek to its end and back).
;------------------------------------------------------------------------------
file_length:	; from: load_file
	move.w	#$2,-(sp)                       ; Fseek(0, d3, 2): to the end
	move.w	d3,-(sp)
	clr.l	-(sp)
	move.w	#$42,-(sp)
	trap	#1                              ; Fseek
	lea	$a(sp),sp
	move.l	d0,d4                           ; its length
	clr.w	-(sp)                           ; Fseek(0, d3, 0): back
	move.w	d3,-(sp)
	clr.l	-(sp)
	move.w	#$42,-(sp)
	trap	#1                              ; Fseek
	lea	$a(sp),sp
	rts

;------------------------------------------------------------------------------
; Fseek the file d3 to d4; Z set when it got there.
;------------------------------------------------------------------------------
seek_file:	; from: load_program
	move.w	#$0,-(sp)                       ; Fseek(d4, d3, 0)
	move.w	d3,-(sp)
	move.l	d4,-(sp)
	move.w	#$42,-(sp)
	trap	#1                              ; Fseek
	lea	$a(sp),sp
	cmp.l	d4,d0                           ; there?
	rts

;------------------------------------------------------------------------------
; Fread d4 bytes from the file d3 to a0; Z set when all were read.
;------------------------------------------------------------------------------
read_file:	; from: settings, load_file, load_program
	move.l	a0,-(sp)                        ; Fread(d3, d4, a0)
	move.l	d4,-(sp)
	move.w	d3,-(sp)
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	lea	$c(sp),sp
	cmp.l	d4,d0                           ; all of them?
	rts

;------------------------------------------------------------------------------
; Fwrite d4 bytes from a0 to the file d3; d0 = -50 (the disk full) when not all were written.
;------------------------------------------------------------------------------
write_file:	; from: cmd_save_binary
	move.l	a0,-(sp)                        ; Fwrite(d3, d4, a0)
	move.l	d4,-(sp)
	move.w	d3,-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	lea	$c(sp),sp
	cmp.l	d0,d4                           ; all of them?
	beq.s	write_file_done                 ; yes
	bsr.s	close_file                      ; close it
	moveq	#-50,d0                         ; -50
write_file_done:
	rts

;------------------------------------------------------------------------------
; Fclose the file d3.
;------------------------------------------------------------------------------
close_file:	; from: settings, load_file, show_cursor_here, cmd_save_binary, load_program, relocate_symbols, 2 more
	move.w	d3,-(sp)                        ; Fclose(d3)
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	rts

;------------------------------------------------------------------------------
; Malloc(d0): d0 = the block, Z set for none.
;------------------------------------------------------------------------------
malloc:	; from: settings, load_file, load_program, alloc_symbol_hash
	move.l	d0,-(sp)                        ; Malloc(d0)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; Set the window a3 on the screen a0: d0-d1 its column and line, d2-d3 its width and lines, d4 the screen
; mode (negative for the small font): its screen address, font, driver table and column offsets, then cleared.
;------------------------------------------------------------------------------
open_window_area:	; from: zoom_window, open_window, init_screen
	movem.w	d2-d3,$10(a3)                   ; its width and lines
	movem.w	d0-d1,$1c(a3)                   ; its column and line
	clr.l	$16(a3)                         ; the print position at the top
	moveq	#0,d0
	move.b	d4,d0                           ; the mode
	add.w	d0,d0
	add.w	d0,d0                           ; 4 bytes a branch
	movea.l	font_headers(a6),a1             ; the Line-A font headers
	tst.w	d4                              ; the small font?
	jsr	mode_setups(pc,d0.w)            ; the mode's set-up
	move.w	$12(a3),d0                      ; the lines
	mulu.w	$1a(a3),d0                      ; in pixels
	move.w	d0,$14(a3)                      ; its height
	bra.w	clear_window                    ; cleared
mode_setups:
	bra.w	setup_low                       ; low resolution
	bra.w	setup_medium                    ; medium resolution
	bra.w	setup_high                      ; high resolution
setup_low:
	bsr.w	setup_medium                    ; as medium
	lea	columns_low(pc),a0              ; the low resolution column offsets
	move.l	a0,$c(a3)
	rts
columns_low:
	dc.w	$0001,$0809,$1011,$1819         ; the byte offset of each character column in low resolution (4 planes)
	dc.b	' !()0189@AHIPQXY`ahipqxy'
	dc.w	$8081,$8889,$9091,$9899
columns_medium:	; from: setup_medium
	dc.w	$0001,$0405,$0809,$0c0d,$1011,$1415,$1819,$1c1d ; the byte offset of each character column in medium
                                                ;   resolution (2 planes)
	dc.b	' !$%(),-014589<=@ADEHILMPQTUXY\]`adehilmpqtuxy|}'
	dc.w	$8081,$8485,$8889,$8c8d,$9091,$9495,$9899,$9c9d

;------------------------------------------------------------------------------
; Low and medium resolution: 160 bytes a line, the 6x6 or the 8x8 font.
;------------------------------------------------------------------------------
setup_medium:	; from: open_window_area
	bpl.s	setup_medium_8                  ; the big font?
	movea.l	(a1),a1                         ; the 6x6 font
	moveq	#6,d0                           ; 6 lines a character
	bra.s	setup_medium_font
setup_medium_8:
	movea.l	4(a1),a1                        ; the 8x8 font
	moveq	#8,d0                           ; 8 lines a character
setup_medium_font:
	move.w	d0,$1a(a3)                      ; the character height
	move.l	$4c(a1),4(a3)                   ; the font data
	lea	drivers_colour(pc),a1           ; the driver table
	move.l	a1,8(a3)
	mulu.w	#$a0,d1                         ; 160 bytes a line
	adda.l	d1,a0
	move.l	a0,(a3)                         ; the window's screen address
	lea	columns_medium(pc),a0           ; the column offsets
	move.l	a0,$c(a3)
	rts

;------------------------------------------------------------------------------
; The colour drivers: a character, clear, a vertical line, a horizontal line, the other font, scroll and invert.
;------------------------------------------------------------------------------
drivers_colour:	; from: setup_medium
	bra.w	colour_char                     ; a character
	bra.w	colour_clear                    ; clear
	bra.w	colour_vertical                 ; a vertical line
	bra.w	colour_horizontal               ; a horizontal line
	bra.w	colour_font                     ; the other font
	bra.w	colour_scroll                   ; scroll
	bra.w	colour_invert_char              ; invert a character
colour_font:
	cmp.w	#$8,d0                          ; the 8x8 font now?
	beq.s	colour_font_small               ; yes
	moveq	#8,d0                           ; no: to it
	movea.l	4(a1),a1
	bra.s	colour_font_set
colour_font_small:
	moveq	#6,d0                           ; to the 6x6 font
	movea.l	(a1),a1
colour_font_set:
	move.l	$4c(a1),4(a3)                   ; the font data
	move.w	d0,$1a(a3)                      ; the character height
	moveq	#0,d1
	move.w	$14(a3),d1                      ; the height in pixels
	divu.w	d0,d1
	move.w	d1,$12(a3)                      ; the lines now
	rts
colour_clear:
	move.l	a2,-(sp)
	movea.l	$c(a3),a2                       ; the column offsets
	adda.w	$1c(a3),a2                      ; from the window's column
	moveq	#0,d1
colour_clear_line:
	movea.l	a2,a1
	move.w	$10(a3),d2                      ; the width
	subq.w	#1,d2
colour_clear_column:
	move.b	(a2)+,d1                        ; a column's byte
	sf	0(a0,d1.w)                      ; cleared
	dbra	d2,colour_clear_column
	movea.l	a1,a2
	lea	$a0(a0),a0                      ; the next pixel line
	dbra	d3,colour_clear_line            ; for each
	movea.l	(sp)+,a2
	rts
colour_vertical:
	movea.l	$c(a3),a1                       ; the column offsets
	add.w	$1c(a3),d1                      ; the column
	move.b	0(a1,d1.w),d1                   ; its byte
	adda.w	d1,a0
	mulu.w	#$a0,d2                         ; the line
	adda.l	d2,a0
	moveq	#16,d0                          ; the line's middle bit
	and.b	d4,d0
	move.w	#$a0,d1
colour_vertical_loop:
	move.b	d0,(a0)                         ; drawn
	adda.w	d1,a0
	dbra	d3,colour_vertical_loop         ; for each pixel line
	rts
colour_horizontal:
	muls.w	#$a0,d2                         ; the line
	adda.l	d2,a0
	movea.l	$c(a3),a1                       ; the column offsets
	subq.w	#1,d1                           ; from the column before
	add.w	$1c(a3),d1
	lea	0(a1,d1.w),a1
	moveq	#0,d1
	moveq	#31,d0                          ; the left end
	and.b	d4,d0
	move.b	(a1)+,d1
	move.b	d0,0(a0,d1.w)                   ; drawn
colour_horizontal_loop:
	move.b	(a1)+,d1
	move.b	d4,0(a0,d1.w)                   ; the middle bytes
	dbra	d3,colour_horizontal_loop
	moveq	#-16,d0                         ; the right end
	and.b	d4,d0
	move.b	(a1)+,d1
	move.b	d0,0(a0,d1.w)                   ; drawn
	rts

;------------------------------------------------------------------------------
; Draw character d1 at column d2, pixel line d3 of the window (d7 nonzero: inverted).
;------------------------------------------------------------------------------
colour_char:	; from: drivers_colour
	muls.w	#$a0,d3                         ; the line
	adda.l	d3,a0
	add.w	$1c(a3),d2                      ; the window's column
	movea.l	$c(a3),a2                       ; the column offsets
	moveq	#0,d0
	move.b	0(a2,d2.w),d0                   ; the column's byte
	adda.w	d0,a0
	move.w	$1a(a3),d2                      ; the character height
	subq.w	#1,d2
	cmp.w	#$5,d2                          ; the 6x6 font?
	beq.s	colour_char_small               ; yes
	adda.w	d1,a1                           ; the character's font bytes
	move.w	#$100,d0                        ; 256 bytes a font line
	move.w	#$a0,d1                         ; 160 a screen line
	tst.b	d7                              ; inverted?
	bne.s	colour_char_inverted            ; yes
colour_char_loop:
	move.b	(a1),(a0)                       ; a line of it
	adda.w	d0,a1
	adda.w	d1,a0
	dbra	d2,colour_char_loop             ; for each
	rts
colour_char_inverted:
	move.b	(a1),d7
	not.b	d7                              ; inverted
	move.b	d7,(a0)
	adda.w	d0,a1
	adda.w	d1,a0
	dbra	d2,colour_char_inverted
	rts

;------------------------------------------------------------------------------
; The 6x6 font: its characters are 6 bits wide and packed, so each line of one is taken out of two bytes.
;------------------------------------------------------------------------------
colour_char_small:	; from: colour_char
	movem.l	d4-d7/a0,-(sp)
	add.w	d1,d1
	move.w	d1,d0
	add.w	d0,d0
	add.w	d1,d0                           ; the character's bit offset: 6 a character
	move.w	d0,d1
	lsr.w	#3,d1                           ; its byte
	adda.w	d1,a1
	lsl.w	#3,d1
	sub.w	d1,d0                           ; the bit in it
	move.w	d0,d4
	moveq	#-4,d5                          ; the mask
	lsr.b	d4,d5
	moveq	#8,d6
	tst.b	d4
	sne	d7                              ; over two bytes?
	beq.s	colour_char_small_masks         ; no
	moveq	#-4,d7                          ; the second byte's mask
	sub.w	d4,d6
	lsl.b	d6,d7
colour_char_small_masks:
	move.w	$1a(a3),d2                      ; the height
	subq.w	#1,d2
	move.w	#$c0,d0                         ; 192 bytes a font line
	move.w	#$a0,d1                         ; 160 a screen line
colour_char_small_loop:
	move.b	(a1),d3                         ; the first byte's part
	and.b	d5,d3
	lsl.b	d4,d3
	move.b	d3,(a0)
	move.b	1(a1),d3                        ; the second's
	and.b	d7,d3
	lsr.b	d6,d3
	or.b	(a0),d3
	lsr.b	#1,d3                           ; centred
	move.b	d3,(a0)                         ; drawn
	adda.w	d0,a1
	adda.w	d1,a0
	dbra	d2,colour_char_small_loop       ; for each line
	movem.l	(sp)+,d4-d7/a0
	tst.b	d7                              ; inverted?
	beq.s	colour_char_done                ; no
colour_invert:
	move.w	$1a(a3),d0                      ; the height
colour_invert_loop:
	not.b	(a0)                            ; inverted
	adda.w	d1,a0
	subq.w	#1,d0
	bne.s	colour_invert_loop
colour_char_done:
	rts
colour_invert_char:	; from: drivers_colour
	move.w	#$a0,d1                         ; 160 bytes a line
	muls.w	d1,d3
	adda.l	d3,a0                           ; the line
	add.w	$1c(a3),d2                      ; the column
	movea.l	$c(a3),a1                       ; the column offsets
	moveq	#0,d0
	move.b	0(a1,d2.w),d0
	adda.w	d0,a0
	bra.s	colour_invert                   ; inverted

;------------------------------------------------------------------------------
; Scroll the window by a character line: up when d0 is negative, else down.
;------------------------------------------------------------------------------
colour_scroll:	; from: drivers_colour
	move.l	d4,-(sp)
	move.w	$12(a3),d3                      ; the lines
	subq.w	#1,d3
	mulu.w	$1a(a3),d3                      ; in pixels
	subq.w	#1,d3                           ; less one
	move.w	$10(a3),d2                      ; the width
	subq.w	#1,d2
	move.w	#$a0,d1
	mulu.w	$1a(a3),d1                      ; a character line in bytes
	movea.l	$c(a3),a2                       ; the column offsets
	adda.w	$1c(a3),a2
	tst.w	d0                              ; up?
	bpl.s	colour_scroll_down              ; no: down
colour_scroll_up:
	movea.l	(a3),a0                         ; the window
	moveq	#0,d4
	move.b	(a2)+,d4                        ; a column
	adda.w	d4,a0
	move.w	d3,d4
colour_scroll_up_loop:
	move.b	0(a0,d1.w),(a0)                 ; moved up
	lea	$a0(a0),a0
	dbra	d3,colour_scroll_up_loop
	move.w	d4,d3
	dbra	d2,colour_scroll_up             ; for each column
	move.l	(sp)+,d4
	rts
colour_scroll_down:
	move.w	$12(a3),d0                      ; the lines
	subq.w	#1,d0
	mulu.w	$1a(a3),d0
	subq.w	#1,d0
	mulu.w	#$a0,d0                         ; the bottom pixel line
colour_scroll_down_column:
	movea.l	(a3),a0                         ; the window
	moveq	#0,d4
	move.b	(a2)+,d4                        ; a column
	adda.w	d4,a0
	adda.w	d0,a0                           ; from the bottom
	move.w	d3,d4
colour_scroll_down_loop:
	move.b	(a0),0(a0,d1.w)                 ; moved down
	lea	-$a0(a0),a0
	dbra	d3,colour_scroll_down_loop
	move.w	d4,d3
	dbra	d2,colour_scroll_down_column    ; for each column
	move.l	(sp)+,d4
	rts
setup_high_8:	; from: setup_high
	movea.l	4(a1),a1                        ; the 8x8 font
	moveq	#8,d0                           ; 8 lines a character
	bra.s	setup_high_font

;------------------------------------------------------------------------------
; High resolution: 80 bytes a line, the 8x8 or the 8x16 font.
;------------------------------------------------------------------------------
setup_high:	; from: open_window_area
	bmi.s	setup_high_8                    ; the small font?
	movea.l	8(a1),a1                        ; the 8x16 font
	moveq	#16,d0                          ; 16 lines a character
setup_high_font:	; from: colour_scroll
	move.w	d0,$1a(a3)                      ; the character height
	move.l	$4c(a1),4(a3)                   ; the font data
	lea	drivers_mono(pc),a1             ; the driver table
	move.l	a1,8(a3)
	adda.w	$1c(a3),a0                      ; the window's column
	mulu.w	#$50,d1                         ; 80 bytes a line
	adda.l	d1,a0
	move.l	a0,(a3)                         ; the window's screen address
	rts

;------------------------------------------------------------------------------
; The high resolution drivers, in the same order.
;------------------------------------------------------------------------------
drivers_mono:	; from: setup_high
	bra.w	mono_char                       ; a character
	bra.w	mono_clear                      ; clear
	bra.w	mono_vertical                   ; a vertical line
	bra.w	mono_horizontal                 ; a horizontal line
	bra.w	mono_font                       ; the other font
	bra.w	mono_scroll                     ; scroll
	bra.w	mono_invert_char                ; invert a character
mono_font:
	cmp.w	#$8,d0                          ; the 8x16 font now?
	beq.s	mono_font_big                   ; no
	moveq	#8,d0                           ; to the 8x8 font
	movea.l	4(a1),a1
	lsl.w	$12(a3)                         ; twice the lines
	bra.s	mono_font_set
mono_font_big:
	moveq	#16,d0                          ; to the 8x16 font
	movea.l	8(a1),a1
	lsr.w	$12(a3)                         ; half the lines
mono_font_set:
	move.l	$4c(a1),4(a3)                   ; the font data
	move.w	d0,$1a(a3)                      ; the character height
	rts
mono_clear:
	move.w	$10(a3),d2                      ; the width
	subq.w	#1,d2
mono_clear_line:
	movea.l	a0,a1
	move.w	d2,d1
mono_clear_column:
	sf	(a0)+                           ; cleared
	dbra	d1,mono_clear_column
	lea	$50(a1),a0                      ; the next pixel line
	dbra	d3,mono_clear_line
	rts
mono_invert_char:
	muls.w	#$50,d3                         ; the line
	adda.l	d3,a0
	adda.w	d2,a0                           ; the column
	move.w	$1a(a3),d2                      ; the height
mono_invert_loop:
	not.b	(a0)                            ; inverted
	lea	$50(a0),a0
	subq.w	#1,d2
	bne.s	mono_invert_loop
	rts
mono_char:
	muls.w	#$50,d3                         ; the line
	adda.l	d3,a0
	adda.w	d2,a0                           ; the column
	adda.w	d1,a1                           ; the character's font bytes
	moveq	#80,d1                          ; 80 bytes a line
	move.w	$1a(a3),d2                      ; the height
	subq.w	#1,d2
	move.w	#$100,d0                        ; 256 bytes a font line
	tst.b	d7                              ; inverted?
	bne.s	mono_char_inverted              ; yes
mono_char_loop:
	move.b	(a1),(a0)                       ; a line of it
	adda.w	d0,a1
	adda.w	d1,a0
	dbra	d2,mono_char_loop
	rts
mono_char_inverted:
	move.b	(a1),d7
	not.b	d7                              ; inverted
	move.b	d7,(a0)
	adda.w	d0,a1
	adda.w	d1,a0
	dbra	d2,mono_char_inverted
	rts
mono_vertical:
	mulu.w	#$50,d2                         ; the line
	adda.l	d2,a0
	adda.w	d1,a0                           ; the column
	moveq	#16,d0                          ; the line's middle bit
	and.b	d4,d0
	move.w	#$50,d1
mono_vertical_loop:
	move.b	d0,(a0)                         ; drawn
	adda.w	d1,a0
	dbra	d3,mono_vertical_loop
	rts
mono_horizontal:
	muls.w	#$50,d2                         ; the line
	adda.l	d2,a0
	adda.w	d1,a0                           ; the column
	moveq	#31,d0                          ; the left end
	and.b	d4,d0
	move.b	d0,-$1(a0)
mono_horizontal_loop:
	move.b	d4,(a0)+                        ; the middle bytes
	dbra	d3,mono_horizontal_loop
	moveq	#-16,d0                         ; the right end
	and.b	d4,d0
	move.b	d0,(a0)
	rts
mono_scroll:
	move.w	$12(a3),d3                      ; the lines
	subq.w	#1,d3
	mulu.w	$1a(a3),d3                      ; in pixels
	subq.w	#1,d3                           ; less one
	move.w	$10(a3),d2                      ; the width
	subq.w	#1,d2
	moveq	#80,d1
	mulu.w	$1a(a3),d1                      ; a character line in bytes
	movea.l	(a3),a1                         ; the window
	tst.w	d0                              ; up?
	bpl.s	mono_scroll_down                ; no: down
mono_scroll_up:
	movea.l	a1,a2
	lea	0(a1,d1.w),a0                   ; from a line below
	move.w	d2,d0
mono_scroll_up_loop:
	move.b	(a0)+,(a1)+                     ; moved up
	dbra	d0,mono_scroll_up_loop
	lea	$50(a2),a1                      ; the next pixel line
	dbra	d3,mono_scroll_up
	rts
mono_scroll_down:
	move.w	$12(a3),d0                      ; the lines
	subq.w	#1,d0
	mulu.w	d1,d0
	lea	-$50(a1,d0.l),a0                ; the bottom
mono_scroll_down_line:
	movea.l	a0,a2
	lea	0(a0,d1.w),a1                   ; a line below
	move.w	d2,d0
mono_scroll_down_loop:
	move.b	(a0)+,(a1)+                     ; moved down
	dbra	d0,mono_scroll_down_loop
	lea	-$50(a2),a0                     ; the pixel line above
	dbra	d3,mono_scroll_down_line
	rts

;------------------------------------------------------------------------------
; Clear the window a3 through its driver.
;------------------------------------------------------------------------------
clear_window:                                   ; from: open_full_window, clear_message, zoom_window,
                                                ;   window_full_height, window_edit, clear_window_frame, 7 more
	movea.l	8(a3),a2                        ; the drivers
	move.w	$14(a3),d3                      ; the height
	subq.w	#1,d3
	movea.l	(a3),a0                         ; the window's screen
	jmp	4(a2)                           ; clear

;------------------------------------------------------------------------------
; Draw character d1 at column d2, pixel line d3 of the window a3 (d7: inverted).
;------------------------------------------------------------------------------
draw_char:	; from: print_char, edit_line, edit_line_cursor_off, draw_frame
	movea.l	8(a3),a2                        ; the drivers
	movea.l	(a3),a0                         ; the window's screen
	movea.l	4(a3),a1                        ; the font
	andi.w	#$ff,d1
	jmp	(a2)                            ; a character

;------------------------------------------------------------------------------
; Invert the character cell at column d2, line d3 of the window a3: the cursor.
;------------------------------------------------------------------------------
invert_char:	; from: window_evaluate, cmd_search, show_cursor_here, edit_memory_cursor
	movea.l	8(a3),a2                        ; the drivers
	movea.l	(a3),a0                         ; the window's screen
	mulu.w	$1a(a3),d3                      ; the line in pixels
	jmp	$18(a2)                         ; invert

;------------------------------------------------------------------------------
; A vertical line of d3 pixels at column d1, line d2 of the window a3 (a frame side).
;------------------------------------------------------------------------------
draw_vertical:	; from: draw_frame
	movea.l	(a3),a0                         ; the window's screen
	subq.w	#1,d3
	movea.l	8(a3),a2                        ; the drivers
	jmp	8(a2)

;------------------------------------------------------------------------------
; A horizontal line of d3 columns at column d1, pixel line d2 of the window a3 (d4: its pattern).
;------------------------------------------------------------------------------
draw_horizontal:	; from: clear_to_eol, draw_frame
	movea.l	(a3),a0                         ; the window's screen
	subq.w	#1,d3
	movea.l	8(a3),a2                        ; the drivers
	jmp	$c(a2)

;------------------------------------------------------------------------------
; Switch the window a3 to the other font.
;------------------------------------------------------------------------------
other_font:	; from: window_full_height
	clr.l	$16(a3)                         ; the print position at the top
	movea.l	font_headers(a6),a1             ; the Line-A font headers
	move.w	$1a(a3),d0                      ; the character height
	movea.l	8(a3),a2                        ; the drivers
	jmp	$10(a2)

;------------------------------------------------------------------------------
; Scroll the window a3 by a line (d0 negative: up).
;------------------------------------------------------------------------------
scroll_window:	; from: scroll_up_line, scroll_down_line
	movea.l	8(a3),a2                        ; the drivers
	jmp	$14(a2)

;------------------------------------------------------------------------------
; Scroll the window a3 up a line, the print position at the bottom line.
;------------------------------------------------------------------------------
scroll_up_line:	; from: memory_line_down, source_handlers
	moveq	#-1,d0                          ; up
	bsr.s	scroll_window
	move.w	$12(a3),d0                      ; the lines
	subq.w	#1,d0                           ; the bottom one
	mulu.w	$1a(a3),d0                      ; in pixels
	move.w	d0,$18(a3)
	clr.w	$16(a3)                         ; column 0
	rts

;------------------------------------------------------------------------------
; Scroll the window a3 down a line, the print position at the top.
;------------------------------------------------------------------------------
scroll_down_line:	; from: memory_line_up, source_handlers
	moveq	#0,d0                           ; down
	bsr.s	scroll_window
	clr.l	$16(a3)                         ; the top
clear_to_eol_done:	; from: clear_to_eol
	rts

;------------------------------------------------------------------------------
; Clear the rest of the window a3's line from the print position (not when printing).
;------------------------------------------------------------------------------
clear_to_eol:                                   ; from: cmd_disassemble, draw_registers, draw_disassembly, draw_source,
                                                ;   source_handlers, source_print_line, 1 more
	tst.b	output_on(a6)                   ; printing?
	bne.s	clear_to_eol_done               ; yes: nothing
	movem.l	d4-d5,-(sp)
	move.w	$1a(a3),d5                      ; the character height
	move.w	$18(a3),d2                      ; the pixel line
clear_to_eol_loop:
	move.w	$16(a3),d1                      ; the column
	addq.w	#1,d1
	move.w	$10(a3),d3                      ; the width
	sub.w	d1,d3                           ; columns left
	ble.s	clear_to_eol_end                ; none
	subq.w	#1,d3
	beq.s	clear_to_eol_end
	moveq	#0,d4                           ; a blank line
	move.w	d2,-(sp)
	bsr.s	draw_horizontal                 ; drawn
	move.w	(sp)+,d2
	addq.w	#1,d2                           ; the next pixel line
	subq.w	#1,d5
	bne.s	clear_to_eol_loop
clear_to_eol_end:
	movem.l	(sp)+,d4-d5
	rts

;------------------------------------------------------------------------------
; Z clear when the printer is ready (Bcostat).
;------------------------------------------------------------------------------
printer_ready:	; from: window_print, cmd_disassemble
	move.w	printer(a6),-(sp)               ; Bcostat(printer)
	move.w	#$8,-(sp)
	bsr.w	bios
	addq.l	#4,sp
	tst.w	d0
	rts

;------------------------------------------------------------------------------
; Send the output to the file d3 through the buffer.
;------------------------------------------------------------------------------
output_to_file:	; from: cmd_disassemble
	move.w	d3,listing_file(a6)             ; the handle
reset_output_buffer:	; from: flush_output_buffer
	lea	output_buffer(a6),a0            ; the buffer
	move.l	a0,output_pointer(a6)           ; empty
	rts
close_output_file:	; from: cmd_disassemble
	bsr.s	flush_output_buffer             ; the rest of the buffer
	move.w	listing_file(a6),d3             ; the handle
	bra.w	close_file                      ; closed
output_file_char:	; from: flush_output_buffer
	cmp.b	#$d,d1                          ; Return?
	bne.s	output_file_char_put            ; no
	bsr.s	buffer_char                     ; Return
	moveq	#10,d1                          ; and a line feed
output_file_char_put:
	bsr.s	buffer_char                     ; into the buffer
	bra.w	print_char_done

;------------------------------------------------------------------------------
; Put d1 into the output buffer, writing it out when full.
;------------------------------------------------------------------------------
buffer_char:	; from: output_to_file
	lea	$bd6(a6),a0                     ; the buffer's end
	movea.l	output_pointer(a6),a1           ; the position
	cmpa.l	a0,a1                           ; full?
	bne.s	buffer_char_put                 ; no
	move.w	d1,-(sp)
	bsr.s	flush_output_buffer             ; written out
	move.w	(sp)+,d1
	bra.s	buffer_char                     ; again
buffer_char_put:
	move.b	d1,(a1)+                        ; in
	move.l	a1,output_pointer(a6)
	rts

;------------------------------------------------------------------------------
; Write the output buffer to the file; a failure stops the output.
;------------------------------------------------------------------------------
flush_output_buffer:	; from: output_to_file, buffer_char
	move.l	output_pointer(a6),d0           ; the position
	lea	output_buffer(a6),a0            ; the buffer
	sub.l	a0,d0                           ; the bytes in it
	beq.s	flush_output_buffer_done        ; none
	pea	output_buffer(a6)               ; Fwrite(handle, length, buffer)
	move.l	d0,-(sp)
	move.w	listing_file(a6),-(sp)
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	cmp.l	4(sp),d0                        ; all written?
	lea	$c(sp),sp
	beq.s	flush_output_buffer_done        ; yes
	bclr	#$7,output_on(a6)               ; no: the output off
flush_output_buffer_done:
	bra.s	reset_output_buffer             ; empty again
output_char:	; from: print_byte_char, print_char
	tst.b	output_on(a6)                   ; output on?
	bpl.s	print_char_done                 ; no
	bsr.w	check_escape                    ; Esc?
	bne.s	output_char_on                  ; no
	bclr	#$7,output_on(a6)               ; yes: the output off
	bra.s	print_char_done
output_char_on:
	tst.w	listing_file(a6)                ; to a file?
	bne.s	output_file_char                ; yes
	andi.w	#$ff,d1
	move.w	d1,-(sp)                        ; Bconout(printer, d1)
	move.w	printer(a6),-(sp)
	move.w	#$3,-(sp)
	bsr.w	bios
	cmpi.w	#$d,4(sp)                       ; Return?
	addq.l	#6,sp
	bne.s	print_char_done                 ; no
	move.w	#$a,-(sp)                       ; and a line feed
	move.w	printer(a6),-(sp)
	move.w	#$3,-(sp)
	bsr.w	bios
	addq.l	#6,sp
print_char_done:	; from: output_to_file
	movem.l	(sp)+,d0-d3/d7/a0-a2            ; the registers back
	rts

;------------------------------------------------------------------------------
; Print the byte d1 as a character: to the printer or a file control characters become spaces.
;------------------------------------------------------------------------------
print_byte_char:	; from: memory_line, draw_registers
	movem.l	d0-d3/d7/a0-a2,-(sp)
	tst.b	output_on(a6)                   ; printing?
	beq.s	print_char_window               ; no: to the window
	move.w	d1,d0
	andi.b	#$7f,d0
	cmp.b	#$20,d0                         ; a control character?
	bcc.s	output_char                     ; no
	moveq	#32,d1                          ; a space
	bra.s	output_char
	addi.b	#$30,d1                         ; never reached

;------------------------------------------------------------------------------
; Print the character d1 at the window a3's print position (Return: a new line), or to the printer or file
; when the output is on.
;------------------------------------------------------------------------------
print_char:	; from: window_evaluate, cmd_search, print_symbol, ask_yes_no, cmd_run_mode, draw_help, 17 more
	movem.l	d0-d3/d7/a0-a2,-(sp)
	tst.b	output_on(a6)                   ; printing?
	bne.s	output_char                     ; yes
	cmp.b	#$d,d1                          ; Return?
	beq.s	print_char_newline              ; yes
print_char_window:	; from: print_byte_char
	move.w	$16(a3),d0                      ; the column
	cmp.w	$10(a3),d0                      ; at the right edge?
	beq.s	print_char_return               ; yes: not shown
	movem.w	$16(a3),d2-d3                   ; the position
	addq.w	#1,$16(a3)                      ; the next column
	moveq	#0,d7                           ; not inverted
	bsr.w	draw_char                       ; drawn
print_char_return:
	movem.l	(sp)+,d0-d3/d7/a0-a2            ; the registers back
	rts
print_char_newline:
	move.w	$1a(a3),d0                      ; the next line
	add.w	$18(a3),d0
	cmp.w	$14(a3),d0                      ; below the window?
	bcc.s	print_char_return               ; yes: stay
	move.w	d0,$18(a3)
	clr.w	$16(a3)                         ; column 0
	bra.s	print_char_return

;------------------------------------------------------------------------------
; Edit the line at a4 with the cursor at its start (see edit_line).
;------------------------------------------------------------------------------
edit_line_start:	; from: cmd_load_binary, ask_load_file, cmd_directory, cmd_load_program
	moveq	#0,d4                           ; the cursor at the start

;------------------------------------------------------------------------------
; Edit the line at a4 in the window a3 from column input_column, the cursor at d4: printable keys go in,
; Backspace and Delete take out, cursor left and right move, Clr Home clears it; Return (Z set) or Esc ends.
;------------------------------------------------------------------------------
edit_line:                                      ; from: set_registers, window_breakpoint, window_lock, window_evaluate,
                                                ;   cmd_run_until, cmd_query_port, 10 more
	movea.l	a4,a0
edit_line_length:
	tst.b	(a0)+                           ; find its end
	bne.s	edit_line_length
	move.l	a0,d5
	sub.l	a4,d5
	subq.w	#1,d5                           ; d5 = its length
	move.w	input_column(a6),$16(a3)        ; the input column
	bsr.w	edit_line_blank                 ; cleared
	bsr.w	edit_line_print                 ; the line shown
edit_line_cursor:
	move.w	$18(a3),d3                      ; the line
	move.w	input_column(a6),d2             ; the column
	add.w	d4,d2                           ; + the cursor
	st	d7                              ; inverted
	move.b	0(a4,d4.w),d1                   ; the character there
	bsr.w	draw_char                       ; the cursor drawn
edit_line_key:
	bsr.w	get_key                         ; a key
	bmi.s	edit_line_key                   ; not Alt keys
	cmp.b	#$d,d1                          ; Return?
	beq.w	edit_line_done                  ; yes
	cmp.b	#$1b,d1                         ; Esc?
	beq.w	edit_line_done                  ; yes
	cmp.b	#$8,d1                          ; Backspace?
	beq.w	edit_line_backspace
	cmp.b	#$7f,d1                         ; Delete?
	beq.w	edit_line_delete
	cmp.w	#$4700,d1                       ; Clr Home?
	beq.w	edit_line_clear
	cmp.w	#$4b00,d1                       ; cursor left?
	beq.s	edit_line_left
	cmp.w	#$4d00,d1                       ; cursor right?
	beq.s	edit_line_right
	tst.b	d1                              ; no character?
	beq.s	edit_line_key                   ; yes: ignored
	cmp.w	input_width(a6),d5              ; full?
	beq.s	edit_line_key                   ; yes: ignored
	move.w	d5,d0
	addq.w	#1,d5                           ; one longer
	sub.w	d4,d0                           ; characters after the cursor
	beq.s	edit_line_put                   ; none
	lea	-$1(a4,d5.w),a0                 ; the end
edit_line_insert:
	move.b	-(a0),1(a0)                     ; moved up
	subq.w	#1,d0
	bne.s	edit_line_insert
edit_line_put:
	bsr.w	edit_line_cursor_off            ; the cursor off
	move.b	d1,0(a4,d4.w)                   ; the character in
	addq.w	#1,d4                           ; past it
edit_line_end:
	clr.b	0(a4,d5.w)                      ; the end
edit_line_show:
	bsr.w	edit_line_print                 ; the line shown
	bra.s	edit_line_cursor
edit_line_left:
	tst.w	d4                              ; at the start?
	beq.s	edit_line_key                   ; yes: nothing
	bsr.s	edit_line_cursor_off            ; the cursor off
	subq.w	#1,d4                           ; back
	bra.s	edit_line_show
edit_line_right:
	cmp.w	d4,d5                           ; at the end?
	beq.s	edit_line_key                   ; yes: nothing
	bsr.s	edit_line_cursor_off            ; the cursor off
	addq.w	#1,d4                           ; on
	bra.s	edit_line_show
edit_line_backspace:
	tst.w	d4                              ; at the start?
	beq.w	edit_line_key                   ; yes: nothing
	bsr.s	edit_line_cursor_off            ; the cursor off
	move.w	d5,d0
	sub.w	d4,d0                           ; characters after the cursor
	beq.s	edit_line_backspace_done        ; none
	lea	0(a4,d4.w),a0
edit_line_backspace_loop:
	move.b	(a0)+,-$2(a0)                   ; moved down
	subq.w	#1,d0
	bne.s	edit_line_backspace_loop
edit_line_backspace_done:
	subq.w	#1,d4
	subq.w	#1,d5                           ; one shorter
	bra.s	edit_line_end
edit_line_delete:
	move.w	d5,d0
	sub.w	d4,d0                           ; characters after the cursor
	beq.w	edit_line_key                   ; none: nothing
	lea	1(a4,d4.w),a0
edit_line_delete_loop:
	move.b	(a0)+,-$2(a0)                   ; moved down
	subq.w	#1,d0
	bne.s	edit_line_delete_loop
	subq.w	#1,d5                           ; one shorter
	bra.s	edit_line_end
edit_line_done:
	bsr.s	edit_line_cursor_off            ; the cursor off
	cmp.b	#$d,d1                          ; Z set for Return
	rts
edit_line_clear:
	bsr.s	edit_line_blank                 ; cleared
	clr.b	(a4)                            ; an empty line
	moveq	#0,d4
	moveq	#0,d5
	bra.w	edit_line_cursor

;------------------------------------------------------------------------------
; Draw the character at the cursor plainly again.
;------------------------------------------------------------------------------
edit_line_cursor_off:	; from: edit_line
	move.w	d1,-(sp)
	move.w	input_column(a6),d2             ; the column
	add.w	d4,d2                           ; + the cursor
	move.w	$18(a3),d3                      ; the line
	sf	d7                              ; plain
	move.b	0(a4,d4.w),d1                   ; the character
	bsr.w	draw_char                       ; drawn
	move.w	(sp)+,d1
	rts

;------------------------------------------------------------------------------
; Print the line at a4 and a space after it, the print position kept.
;------------------------------------------------------------------------------
edit_line_print:	; from: edit_line
	move.w	$16(a3),-(sp)
	movea.l	a4,a0
	bsr.w	print_string                    ; printed
	moveq	#32,d1                          ; a space
	bsr.w	print_char
	move.w	(sp)+,$16(a3)
	rts

;------------------------------------------------------------------------------
; Clear the input field: as many spaces as the longest line, the print position kept.
;------------------------------------------------------------------------------
edit_line_blank:	; from: edit_line
	move.w	$16(a3),-(sp)
	move.w	input_width(a6),d2              ; the field's width
	bsr.w	print_spaces                    ; spaces
	move.w	(sp)+,$16(a3)
	rts

;------------------------------------------------------------------------------
; Open the window a3 at column d0, line d1 (below the title line), d2 wide, d3 lines, titled with the string at
; a2: the title handlers until its type sets its own, no lock, its frame drawn.
;------------------------------------------------------------------------------
open_window:                                    ; from: open_title_window, open_window_1, open_window_2, open_window_3,
                                                ;   open_full_window, cmd_load_source, 1 more
	move.l	a2,-(sp)
	movea.l	screen(a6),a0                   ; MonST's screen
	add.w	title_height(a6),d1             ; below the title line
	move.w	full_layout+8(a6),d4            ; the font
	bsr.w	open_window_area                ; placed
	movea.l	(sp)+,a2
	lea	$20(a3),a0                      ; the title
	moveq	#26,d0                          ; up to 27 characters
	move.b	#$20,(a0)+                      ; a space first
open_window_title:
	move.b	(a2)+,(a0)+                     ; copied
	dbeq	d0,open_window_title
	move.b	#$20,-$1(a0)                    ; a space after it
	clr.b	(a0)
	lea	title_handlers(pc),a0           ; the title handlers
	move.l	a0,$48(a3)
	clr.w	$4c(a3)                         ; no lock
	moveq	#0,d7                           ; not current
	st	d4                              ; the title shown

;------------------------------------------------------------------------------
; Draw the window a3's frame on the whole screen: the title line with its number (d4 set: the title text too,
; d7: highlighted), the sides, the top and the bottom.
;------------------------------------------------------------------------------
draw_frame:                                     ; from: open_full_window, zoom_window, move_window, clear_window_frame,
                                                ;   draw_window, set_window_title, 4 more
	move.l	a4,-(sp)
	movea.l	a3,a4                           ; the window
	lea	screen_area(a6),a3              ; the whole screen
	move.w	$1c(a4),d2                      ; the window's column
	move.w	$1e(a4),d3                      ; its top
	sub.w	title_height(a6),d3             ; the title line above it
	moveq	#32,d1                          ; a space
	tst.b	d4                              ; the title?
	beq.s	draw_frame_number               ; no
	tst.b	$46(a4)                         ; a number?
	beq.s	draw_frame_number               ; no
	moveq	#48,d1                          ; '0'
	add.b	$46(a4),d1                      ; + the number
draw_frame_number:
	movem.w	d2-d3,-(sp)
	bsr.w	draw_char                       ; drawn
	movem.w	(sp)+,d2-d3
	addq.w	#1,d2
	lea	$20(a4),a0                      ; the title
draw_frame_title:
	move.b	(a0)+,d1                        ; a character
	beq.s	draw_frame_sides                ; the end
	movem.l	d2-d3/d7/a0,-(sp)
	tst.b	d4                              ; the title?
	bne.s	draw_frame_title_char           ; yes
	moveq	#32,d1                          ; no: a space
draw_frame_title_char:
	bsr.w	draw_char                       ; drawn
	movem.l	(sp)+,d2-d3/d7/a0
	addq.w	#1,d2
	bra.s	draw_frame_title
draw_frame_sides:
	move.w	$1c(a4),d1                      ; the column left of it
	subq.w	#1,d1
	move.w	$1e(a4),d2                      ; its top
	move.w	$14(a4),d3                      ; its height
	movem.w	d2-d3,-(sp)
	bsr.w	draw_vertical                   ; the left side
	movem.w	(sp)+,d2-d3
	move.w	$1c(a4),d1                      ; the column right of it
	add.w	$10(a4),d1
	bsr.w	draw_vertical                   ; the right side
	movem.w	$1c(a4),d1-d2                   ; its top
	subq.w	#1,d2                           ; the line above it
	move.w	$10(a4),d3                      ; its width
	bsr.w	draw_horizontal                 ; the top
	move.w	$1c(a4),d1
	move.w	$14(a4),d2                      ; its height
	add.w	$1e(a4),d2                      ; below it
	move.w	$10(a4),d3                      ; its width
	bsr.w	draw_horizontal                 ; the bottom
	movea.l	a4,a3
	movea.l	(sp)+,a4
	rts

;------------------------------------------------------------------------------
; Set MonST's screen up for the mode d7: the Line-A font headers, the screen cleared, the whole screen as an
; area, every window closed, and the layout values for the mode.
;------------------------------------------------------------------------------
init_screen:	; from: print_wait, cmd_resolution
	dc.w	$a000                           ; Line-A $0, Line-A init: a1 = the font headers
	move.l	a1,font_headers(a6)             ; kept
	movea.l	screen(a6),a0                   ; MonST's screen
	move.w	#$f9f,d0                        ; 32000 bytes
init_screen_clear:
	clr.l	(a0)+                           ; cleared
	clr.l	(a0)+
	dbra	d0,init_screen_clear
	cmp.b	#$1,d7                          ; high?
	bgt.s	init_screen_high                ; yes
	beq.s	init_screen_medium              ; medium?
	move.w	#$28,d2                         ; low: 40 columns
	move.w	#$19,d3                         ; 25 lines
	moveq	#0,d4
	bra.s	init_screen_area
init_screen_medium:
	move.w	#$50,d2                         ; 80 columns
	move.w	#$19,d3                         ; 25 lines
	moveq	#1,d4
	bra.s	init_screen_area
init_screen_high:
	move.w	#$50,d2                         ; 80 columns
	move.w	#$32,d3                         ; 50 lines
	moveq	#2,d4
init_screen_area:
	moveq	#0,d0
	moveq	#0,d1
	lea	screen_area(a6),a3              ; the whole screen
	bset	#$f,d4                          ; the small font
	movea.l	screen(a6),a0
	bsr.w	open_window_area                ; placed
	move.w	$1a(a3),d0                      ; the character height
	addq.w	#1,d0                           ; + 1
	move.w	d0,title_height(a6)             ; the title line's height
	moveq	#7,d0                           ; 8 windows
	lea	window_title(a6),a0
init_screen_close:
	clr.w	$10(a0)                         ; closed
	lea	$4e(a0),a0
	dbra	d0,init_screen_close
	clr.l	current_window(a6)              ; no current window
	movem.w	layout_high(pc),d0-d6           ; the high resolution layout
	cmp.b	#$1,d7                          ; high?
	bgt.s	init_screen_layout              ; yes
	movem.w	layout_medium(pc),d0-d6         ; medium
	beq.s	init_screen_layout              ; medium?
	movem.w	layout_low(pc),d0-d6            ; low
init_screen_layout:
	movem.w	d0-d4,full_layout(a6)           ; the full screen window's position, size and font
	move.w	d5,split_height(a6)             ; the split window's height
	move.w	d6,input_width(a6)              ; the input field's width
	rts
layout_high:
	dc.w	$0001,$000a,$004e,$0018,$0002,$0010,$003b ; high resolution: the full screen window, the split height
                                                ;   and the input width
layout_medium:
	dc.w	$0001,$0007,$004e,$0018,$0001,$0008,$003b ; medium resolution
layout_low:
	dc.w	$0001,$0007,$0026,$0018,$0000,$0008,$001b ; low resolution
windows_high:	; from: open_windows
	dc.w	$0001,$0175,$004e,$0001,$0001,$0000,$004e,$000a ; high resolution: the title, windows 1, 2 and 3
                                                ;   (column, line, width, lines), then windows 4 and 5
	dc.w	$0001,$00ab,$0032,$000c,$0035,$00ab,$001a,$000c
	dc.w	$0001,$0106,$0032,$0006,$0035,$0106,$001a,$0006
windows_medium:	; from: open_windows
	dc.w	$0001,$00b8,$004e,$0001,$0001,$0000,$004e,$000a ; medium resolution
	dc.w	$0001,$0058,$0032,$000b,$0035,$0058,$001a,$000b
	dc.w	$0001,$0088,$0032,$0005,$0035,$0088,$001a,$0005
windows_low:	; from: open_windows
	dc.w	$0001,$00b8,$0026,$0001,$0001,$0000,$0026,$000a ; low resolution
	dc.w	$0001,$0058,$0026,$0007,$0001,$0098,$0026,$0003

;------------------------------------------------------------------------------
; Open the windows for the mode d7: the title, the registers, a disassembly at the PC (locked to it) and a
; memory window; window 2 is current.
;------------------------------------------------------------------------------
open_windows:	; from: print_wait, cmd_resolution
	clr.b	split_flags(a6)                 ; none split
	lea	windows_high(pc),a4             ; the high resolution layouts
	cmp.b	#$1,d7                          ; high?
	bgt.s	open_windows_open               ; yes
	lea	windows_medium(pc),a4           ; medium
	beq.s	open_windows_open               ; medium?
	lea	windows_low(pc),a4              ; low
open_windows_open:
	bsr.w	open_title_window               ; the title
	bsr.w	open_window_1                   ; window 1
	bsr.w	open_window_2                   ; window 2
	moveq	#76,d0                          ; the PC
	sf	d7
	bsr.w	set_window_lock                 ; locked to it
	bsr.w	open_window_3                   ; window 3
	movem.l	(a4)+,d0-d1                     ; window 4's layout
	movem.l	d0-d1,layout_window_4(a6)       ; kept
	movem.l	(a4)+,d0-d1                     ; window 5's layout
	movem.l	d0-d1,layout_window_5(a6)       ; kept
	lea	window_2(a6),a3                 ; window 2 current

;------------------------------------------------------------------------------
; Make the window a3 current: the old current window's frame drawn plainly, the new one's highlighted.
;------------------------------------------------------------------------------
select_window:	; from: window_split, cmd_load_source, relocate_symbols, next_window, select_window_number
	tst.l	current_window(a6)              ; one before?
	beq.s	select_window_new               ; no
	move.l	a3,-(sp)
	movea.l	current_window(a6),a3           ; the old one
	tst.w	$10(a3)                         ; open?
	beq.s	select_window_old_done          ; no
	sf	d7                              ; plain
	st	d4
	bsr.w	draw_frame                      ; its frame
select_window_old_done:
	movea.l	(sp)+,a3
select_window_new:
	move.l	a3,current_window(a6)           ; current
	st	d7                              ; highlighted
	st	d4
	bra.w	draw_frame                      ; its frame

;------------------------------------------------------------------------------
; Tab: make the next open window current (after window 5 window 1 again).
;------------------------------------------------------------------------------
next_window:	; from: command_loop
	move.w	#$856,d3                        ; past the last
	move.l	current_window(a6),d0           ; the current window
	beq.s	next_window_try                 ; none
	move.l	d0,d3
	sub.l	a6,d3                           ; as an offset
next_window_try:
	moveq	#6,d2                           ; 7 tries
next_window_loop:
	cmp.w	#$856,d3                        ; past the last?
	bne.s	next_window_step                ; no
	move.w	#$634,d3                        ; to the title, before window 1
next_window_step:
	addi.w	#$4e,d3                         ; the next window
	tst.w	reg_d+12(a6,d3.w)               ; open?
	bne.s	next_window_found               ; yes
	dbra	d2,next_window_loop
	rts
next_window_found:
	lea	basepage(a6,d3.w),a3            ; its address
	bra.s	select_window                   ; current

;------------------------------------------------------------------------------
; Make window number d1 current, when it is open.
;------------------------------------------------------------------------------
select_window_number:	; from: command_loop
	lea	window_1(a6),a3                 ; window 1
	moveq	#8,d2
select_window_number_loop:
	tst.w	$10(a3)                         ; open?
	beq.s	select_window_number_next       ; no
	cmp.b	$46(a3),d1                      ; its number?
	beq.s	select_window                   ; yes
select_window_number_next:
	lea	$4e(a3),a3                      ; the next
	dbra	d2,select_window_number_loop
	rts

;------------------------------------------------------------------------------
; Close the prompt window a3 and redraw: the full screen window when open, else all the windows.
;------------------------------------------------------------------------------
close_prompt:                                   ; from: zoom_window, set_registers, window_breakpoint, window_lock,
                                                ;   window_evaluate, cmd_run_until, 19 more
	movem.l	d4-d7,-(sp)
	pea	close_prompt_done(pc)           ; the registers back afterwards
	bsr.w	clear_window                    ; cleared
	sf	d7
	sf	d4
	bsr.w	draw_frame                      ; its frame cleared
	clr.w	$10(a3)                         ; closed
	lea	window_full(a6),a3              ; the full screen window
	tst.w	$10(a3)                         ; open?
	beq.w	draw_all_windows                ; no: all the windows
	st	d7
	st	d4
	bsr.w	draw_frame                      ; its frame
	bra.w	draw_window_contents            ; its contents
close_prompt_done:
	movem.l	(sp)+,d4-d7
	rts

;------------------------------------------------------------------------------
; Set the window a3's handlers and line width for its type: memory (bytes a line from the width, up to 16),
; registers (with memory bytes when 40 columns or wider), disassembly (a label column) or source code.
;------------------------------------------------------------------------------
set_window_type:                                ; from: open_window_1, open_window_2, open_window_3, zoom_window,
                                                ;   window_full_height, window_type, 2 more
	moveq	#0,d1
	move.w	$10(a3),d1                      ; its width
	moveq	#0,d0
	move.b	$3e(a3),d0                      ; its type
	add.w	d0,d0
	cmp.w	#$28,d1                         ; 40 columns?
	jmp	window_types(pc,d0.w)
window_types:
	rts                                     ; the title: nothing
	bra.s	set_window_memory               ; memory
	bra.s	set_window_registers            ; registers
	bra.s	set_window_disassembly          ; disassembly
	bra.s	set_window_source               ; source code
set_window_memory:
	subi.l	#$9,d1                          ; less the address
	divu.w	#$7,d1                          ; 7 columns a 2 bytes
	add.w	d1,d1                           ; bytes a line
	cmp.w	#$10,d1                         ; over 16?
	bcs.s	set_window_memory_width         ; no
	moveq	#16,d1                          ; 16
set_window_memory_width:
	move.b	d1,$3f(a3)
	lea	memory_handlers(pc),a0          ; the memory handlers
	move.l	a0,$48(a3)
	rts
set_window_registers:
	lea	register_handlers(pc),a0        ; the register handlers
	move.l	a0,$48(a3)
	moveq	#8,d2                           ; 8 bytes a data register
	moveq	#12,d3                          ; 12 an address register
	cmp.w	#$28,d1                         ; 40 columns or wider?
	bcc.s	set_window_registers_width      ; yes
	moveq	#0,d2                           ; no bytes
	moveq	#4,d3                           ; 4 bytes
set_window_registers_width:
	move.b	d2,$40(a3)
	move.b	d3,$3f(a3)
	rts
set_window_disassembly:
	subi.w	#$26,d1                         ; the width less 38
	bcc.s	set_window_disassembly_label
	moveq	#0,d1
set_window_disassembly_label:
	cmp.b	#$6,d1                          ; below 6?
	bcc.s	set_window_disassembly_max      ; no
	moveq	#0,d1                           ; no label column
set_window_disassembly_max:
	cmp.b	#$10,d1                         ; over 16?
	bcs.s	set_window_disassembly_set      ; no
	moveq	#16,d1                          ; 16
set_window_disassembly_set:
	move.b	d1,$3f(a3)                      ; the label column's width
	lea	disassembly_handlers(pc),a0     ; the disassembly handlers
	move.l	a0,$48(a3)
	rts
set_window_source:
	move.b	#$8,$3f(a3)                     ; tabs of 8
	lea	source_handlers(pc),a0          ; the source handlers
	move.l	a0,$48(a3)
	rts

;------------------------------------------------------------------------------
; The numbered messages print_message picks from, each ended by a 0: the register names, the exceptions, the
; help window's lines, the disassembly prompts and the window titles.
;------------------------------------------------------------------------------
messages:	; from: print_message
	dc.b	'PC:',0
	dc.b	'SR:',0
	dc.b	'A7',$27,0
	dc.b	'Divide by zero',0
	dc.b	'CHK exception',0
	dc.b	'TRAPV exception',0
	dc.b	'Privilege violation',0
	dc.b	'Trace',0
	dc.b	'Bad interrupt',0
	dc.b	'Invalid TRAP',0
	dc.b	'Illegal exception',0
	dc.b	'Breakpoint',0
	dc.b	$44,$3a,$00,$41,$3a,$00
	dc.b	'Searching...',0
	dc.b	'Address error',0
	dc.b	'Bus error',0
	dc.b	' ; ',0
	dc.w	$2c20
	dc.b	$00
	dc.b	'Text: ',0
	dc.b	'Data: ',0
	dc.b	'BSS : ',0
	dc.b	13,'Current Breakpoints:',13,13,0
	dc.b	'Data start,end<,size>',0
	dc.b	'Cross-reference list',0
	dc.b	'Filename',0
text_disassembly:	; from: open_window_2, set_window_title
	dc.b	'Disassembly',0
text_memory:	; from: open_window_3, set_window_title
	dc.b	'Memory',0
text_title:	; from: open_title_window
	dc.b	'MonST2.13 '
	dc.b	$bd
	dc.b	' HiSoft 1991',0
text_registers:	; from: open_window_1
	dc.b	'Registers',0
text_source_code:	; from: set_window_title, cmd_load_source
	dc.b	'Source code',0
text_esc_to_abort:	; from: open_prompt
	dc.b	'  ESC to abort   ',0
text_window_start_address:	; from: window_address
	dc.b	'Window start address?',0
text_goto_line:	; from: window_address
	dc.b	'Goto line?',0
text_return:	; from: show_message
	dc.b	'[Return]',0
text_space:	; from: open_message
	dc.b	$20,$00
text_filename_to_load:	; from: cmd_load_binary
	dc.b	'Filename to load',0
text_source_file_to_load:	; from: cmd_load_source
	dc.b	'Source file to load',0
text_executable_file_to_load:	; from: cmd_load_program
	dc.b	'Executable file to load',0
text_command_line:	; from: cmd_load_program
	dc.b	'Command line',0
text_program_terminated:	; from: relocate_symbols
	dc.b	'Program terminated',0
text_register_value:	; from: set_registers
	dc.b	'Register=value',0
text_tos_error:	; from: show_tos_error
	dc.b	'TOS error: '
tos_error_number:	; from: show_tos_error
	dc.b	'12345',0                       ; the error number is written here
text_cannot_run:	; from: cmd_run
	dc.b	'Cannot run',0
text_in_rom:	; from: set_breakpoint
	dc.b	'In ROM!',0
text_its_odd:	; from: set_breakpoint
	dc.b	'It',$27,'s odd!',0
text_cannot_write:	; from: set_breakpoint
	dc.b	'Cannot write!',0
text_too_many_breakpoints:	; from: set_breakpoint
	dc.b	'Too many breakpoints!',0
text_run_until_pc:	; from: cmd_run_until
	dc.b	'Run until PC=',0
text_kill_all_breakpoints:	; from: cmd_kill_breakpoints
	dc.b	'Kill all breakpoints',0
text_y_n:	; from: ask_yes_no_message
	dc.b	' Y/N?',0
text_breakpoint_address_param:	; from: window_breakpoint
	dc.b	'Breakpoint address<,param>',0
text_history:	; from: cmd_history
	dc.b	'History',0
text_search_for:	; from: cmd_search
	dc.b	'Search for B/W/L/T/I? ',0
text_printer_not_responding:	; from: window_print, cmd_disassemble
	dc.b	'Printer not responding',0
text_register_to_lock:	; from: window_lock
	dc.b	'Register to lock',0
text_enter_expression:	; from: window_evaluate
	dc.b	'Enter expression',0
text_symbols:	; from: cmd_symbols
	dc.b	'Symbols',0
text_preferences:	; from: cmd_preferences
	dc.b	'PREFERENCES',0
text_screen_timer:	; from: cmd_preferences
	dc.b	'Screen timer Y/N? ',0
text_follow_traps:	; from: cmd_preferences
	dc.b	'Follow traps Y/N? ',0
text_relative_offsets:	; from: cmd_preferences
	dc.b	'Relative offsets Y/N? ',0
text_ignore_case:	; from: cmd_search, cmd_preferences
	dc.b	'Ignore case Y/N? ',0
text_ignore_cartridge:	; from: show_cursor_here
	dc.b	'Ignore cartridge area Y/N? ',0
text_symbol_length:	; from: show_cursor_here
	dc.b	'Symbol length',0
text_top_of_ram:	; from: show_cursor_here
	dc.b	'Top of RAM',0
text_bdos_breakpoint:	; from: cmd_bdos_breakpoint
	dc.b	'BDOS Breakpoint',0
text_copy_start_end_to:	; from: cmd_copy
	dc.b	'Copy start,end,to',0
text_fill_start_end_with:	; from: cmd_fill
	dc.b	'Fill start,end,with',0
text_set_drive_directory:	; from: cmd_directory
	dc.b	'Set current drive/directory',0
text_save_binary_filename:	; from: cmd_save_binary
	dc.b	'Save binary, filename',0
text_start_address_end:	; from: cmd_save_binary
	dc.b	'start address,end',0
text_run_mode:	; from: cmd_run_mode
	dc.b	'Run: Go,Until,Instruction,Slow ',0
text_watch:	; from: cmd_run_mode
	dc.b	'Watch Y/N? ',0
text_help:	; from: cmd_help
	dc.b	'Help',0
text_disassemble_start_end:	; from: cmd_disassemble
	dc.b	'Disassemble start,end',0
text_reinstall_exceptions:	; from: cmd_reinstall
	dc.b	'Re-install exceptions',0
text_save_preferences:	; from: show_cursor_here
	dc.b	'Save preferences Y/N? ',0
text_needs_68000:	; from: print_wait
	dc.b	'This version of MonST only works on a 68000 processor!',13,10,'Don',$27
	dc.b	't try loading any programs...',0
text_unrecognised_screen_mode:	; from: settings
	dc.b	'Unrecognised screen mode',0
text_query_which_port:	; from: cmd_query_port
	dc.b	'Query which port',0
text_port_to_write_value:	; from: cmd_write_port
	dc.b	'Port to write, value',0
name_monst_inf:	; from: settings, show_cursor_here
	dc.b	'MONST2.INF',0
	dc.b	$00,$4a,$81,$6a,$34,$44,$81,$18,$fc,$00,$2d,$60,$2c ; not used: the end of an older number routine

;------------------------------------------------------------------------------
; Put the signed byte d1 at a4 in decimal (or $ hex from 10 on).
;------------------------------------------------------------------------------
put_signed_byte:	; from: op_moveq, index_address
	tst.b	d1                              ; negative?
	bpl.s	put_byte                        ; no
	move.b	#$2d,(a4)+                      ; -
	neg.b	d1

put_byte:	; from: disassemble_listing, put_signed_byte, op_immediate, op_bit_static, keep_address
	andi.l	#$ff,d1                         ; the byte
	bra.s	put_number

put_signed_word:	; from: op_movep, op_link, ea_register_value
	tst.w	d1                              ; negative?
	bpl.s	put_word                        ; no
	move.b	#$2d,(a4)+                      ; -
	neg.w	d1

put_word:	; from: disassemble_listing, put_signed_word, op_immediate, op_word, op_dc_w, keep_address
	andi.l	#$ffff,d1                       ; the word
	bra.s	put_number

;------------------------------------------------------------------------------
; Put the long d1 at a4: as a symbol if it is one, else as a number.
;------------------------------------------------------------------------------
put_address:	; from: show_cursor_here, disassemble_listing, op_immediate, op_dbcc, op_bcc, ea_other, 1 more
	move.l	d1,d0
	bsr.w	find_symbol                     ; a symbol?
	bne.s	put_symbol_name                 ; yes: its name

put_number:	; from: put_byte, put_word, op_illegal
	cmp.l	#$a,d1                          ; below 10?
	bcc.s	put_number_hex                  ; no: in hex
	addi.b	#$30,d1                         ; a digit
	move.b	d1,(a4)+
	rts
	move.l	d2,-(sp)                        ; never reached
	st	d2
	swap	d1
	moveq	#3,d0
	bra.s	put_hex_loop
put_number_hex:
	move.b	#$24,(a4)+                      ; $

;------------------------------------------------------------------------------
; Put d1 at a4 in hex without leading zeros.
;------------------------------------------------------------------------------
put_hex:	; from: cmd_run_mode, find_symbol
	move.l	d2,-(sp)
	moveq	#0,d2                           ; no digit yet
	moveq	#7,d0                           ; 8 digits
put_hex_loop:	; from: put_number
	rol.l	#4,d1                           ; the next
	move.w	d1,-(sp)
	andi.b	#$f,d1
	bne.s	put_hex_digit                   ; not 0
	tst.b	d2                              ; a digit before?
	beq.s	put_hex_next                    ; no: a leading zero
put_hex_digit:
	st	d2                              ; digits from now on
	cmp.b	#$9,d1                          ; 0-9?
	ble.s	put_hex_char                    ; yes
	addq.b	#7,d1                           ; A-F
put_hex_char:
	addi.b	#$30,d1
	move.b	d1,(a4)+
put_hex_next:
	move.w	(sp)+,d1
	dbra	d0,put_hex_loop
	move.l	(sp)+,d2
	rts

;------------------------------------------------------------------------------
; Put the name of the symbol entry d0 at a4.
;------------------------------------------------------------------------------
put_symbol_name:	; from: put_address, ea_register_value
	movem.l	d1/a0,-(sp)
	movea.l	d0,a0
	moveq	#7,d0                           ; 8 characters
put_symbol_name_loop:
	move.b	(a0)+,d1                        ; a character
	beq.s	put_symbol_name_done            ; the end
	move.b	d1,(a4)+
	dbra	d0,put_symbol_name_loop
	tst.b	1(a0)                           ; a long name?
	beq.s	put_symbol_name_done            ; no
	addq.l	#6,a0                           ; its second part
	moveq	#13,d0                          ; 14 more
put_symbol_name_long:
	move.b	(a0)+,d1                        ; a character
	beq.s	put_symbol_name_done            ; the end
	move.b	d1,(a4)+
	dbra	d0,put_symbol_name_long
put_symbol_name_done:
	movem.l	(sp)+,d1/a0
	rts

;------------------------------------------------------------------------------
; Put the condition d1 (0-15) at a4: T, F, HI, LS, CC, CS, NE, EQ, VC, VS, PL, MI, GE, LT, GT, LE, and a space.
;------------------------------------------------------------------------------
put_condition:	; from: op_dbcc, op_scc, op_bcc
	lea	condition_names(pc),a0          ; the condition names
	rol.l	#1,d1                           ; 2 characters each
	move.b	0(a0,d1.w),(a4)+                ; the first
	move.b	1(a0,d1.w),d0                   ; the second
	beq.s	put_condition_space             ; none
	move.b	d0,(a4)+
put_condition_space:
	ror.l	#1,d1
	move.b	#$20,(a4)+                      ; a space
	rts
condition_names:
	dc.w	$5400,$4600                     ; T, F, then the 14 two-letter conditions
	dc.b	'HILSCCCSNEEQVCVSPLMIGELTGTLE'

;------------------------------------------------------------------------------
; Put the size d5 (0-3) at a4: .B, .W, .L or .?, and a space.
;------------------------------------------------------------------------------
put_size:	; from: op_immediate, op_single, op_movem_to, op_movem_from, op_quick, op_bcd, 6 more
	lea	size_letters(pc),a0             ; the sizes
	ext.w	d5
	move.b	#$2e,(a4)+                      ; .
	move.b	0(a0,d5.w),(a4)+                ; the letter
	move.b	#$20,(a4)+                      ; a space
	rts
size_letters:
	dc.b	'BWL?D',0                       ; "BWL?D"

;------------------------------------------------------------------------------
; Put the bit operation d1 (0-3) at a4: TST, CHG, CLR or SET, and a space.
;------------------------------------------------------------------------------
put_bit_op:	; from: op_bit_dynamic, op_bit_static
	lea	bit_op_names(pc),a0             ; the names
	ext.w	d1
	rol.l	#2,d1                           ; 4 bytes each
	move.b	0(a0,d1.w),(a4)+
	move.b	1(a0,d1.w),(a4)+
	move.b	2(a0,d1.w),(a4)+
	move.b	#$20,(a4)+                      ; a space
	ror.l	#2,d1
	rts
bit_op_names:
	dc.b	'TST CHG CLR SET '              ; "TST CHG CLR SET "

put_register_number:	; from: op_movep, op_bit_dynamic, op_lea, op_exg, op_moveq, op_bcd, 8 more
	andi.b	#$7,d1                          ; 0-7

put_digit:	; from: op_quick, op_shift
	addi.b	#$30,d1                         ; a digit
	move.b	d1,(a4)+
	rts

;------------------------------------------------------------------------------
; Disassemble the instruction at a5 into the line at $8bc (ended by a Return), a5 past it.  The opcode is found
; by mask and value in opcode_table, its mnemonic and handler in mnemonic_table, and the handler puts the
; operands; the effective addresses used are kept for the register window.
;------------------------------------------------------------------------------
disassemble:                                    ; from: search_instruction, cmd_disassemble, disassemble_listing,
                                                ;   next_instruction, print_instruction, previous_instruction
	move.w	(a5)+,d7                        ; the opcode
	clr.b	ea_two(a6)                      ; no second effective address

disassemble_opcode:	; from: op_illegal
	lea	opcode_table(pc),a0             ; the masks and values
	clr.l	d0
disassemble_find:
	addq.l	#1,d0                           ; the entry number
	move.w	d7,d2
	and.w	(a0)+,d2                        ; masked
	cmp.w	(a0)+,d2                        ; this one?
	bne.s	disassemble_find                ; no
	moveq	#0,d1
	lea	mnemonic_table(pc),a0           ; the mnemonics
disassemble_mnemonic:
	move.b	(a0)+,d1                        ; its length
	subq.b	#1,d0                           ; this entry?
	beq.s	disassemble_put                 ; yes
	adda.l	d1,a0                           ; past it
	bra.s	disassemble_mnemonic
disassemble_put:
	move.b	(a0)+,d2                        ; the handler's number
	lea	line_buffer(a6),a4              ; the line
	subq.b	#2,d1                           ; the text's length
	bcs.s	disassemble_operands            ; none
disassemble_put_loop:
	move.b	(a0)+,(a4)+                     ; the mnemonic
	dbra	d1,disassemble_put_loop
disassemble_operands:
	move.b	d2,d6                           ; the handler
	bsr.s	put_operands                    ; the operands
	move.b	#$d,(a4)+                       ; a Return
	clr.l	d0
	rts

;------------------------------------------------------------------------------
; Jump to entry d0 of the table of offsets at a0.
;------------------------------------------------------------------------------
dispatch:	; from: put_operands, op_cmp_group, put_ea_mode, ea_other
	ext.w	d0
	add.w	d0,d0                           ; words
	move.w	0(a0,d0.w),d0                   ; its offset
	jmp	0(a0,d0.w)                      ; to it

;------------------------------------------------------------------------------
; Put the counted string at a0 at a4.
;------------------------------------------------------------------------------
put_counted:	; from: op_immediate, op_move_usp, op_bcd, op_cmpm, put_reg_9, keep_address
	clr.l	d0
	move.b	(a0)+,d0                        ; its length
	subq.b	#1,d0
put_counted_loop:
	move.b	(a0)+,(a4)+
	dbra	d0,put_counted_loop
	rts

;------------------------------------------------------------------------------
; Put the operands with handler d6, the size bits in d5.
;------------------------------------------------------------------------------
put_operands:	; from: disassemble_opcode
	lea	operand_handlers(pc),a0         ; the handlers
	move.b	d6,d0
	move.w	d7,d5
	andi.w	#$c0,d5                         ; the size bits
	lsr.w	#6,d5
	bsr.s	dispatch
op_none:	; from: operand_handlers
	rts                                     ; no operands
operand_handlers:
	dc.w	op_none-operand_handlers
	dc.w	op_nothing-operand_handlers
	dc.w	op_immediate-operand_handlers
	dc.w	op_movep-operand_handlers
	dc.w	op_bit_dynamic-operand_handlers
	dc.w	op_bit_static-operand_handlers
	dc.w	op_move-operand_handlers
	dc.w	op_word-operand_handlers
	dc.w	put_low_register-operand_handlers
	dc.w	op_link-operand_handlers
	dc.w	op_move_usp-operand_handlers
	dc.w	op_trap-operand_handlers
	dc.w	op_single-operand_handlers
	dc.w	op_move_ccr-operand_handlers
	dc.w	op_move_sr-operand_handlers
	dc.w	op_movem_to-operand_handlers
	dc.w	op_movem_from-operand_handlers
	dc.w	op_ea_dn-operand_handlers
	dc.w	op_lea-operand_handlers
	dc.w	op_dbcc-operand_handlers
	dc.w	op_scc-operand_handlers
	dc.w	op_quick-operand_handlers
	dc.w	op_exg-operand_handlers
	dc.w	op_bcc-operand_handlers
	dc.w	op_moveq-operand_handlers
	dc.w	op_bcd-operand_handlers
	dc.w	op_nothing-operand_handlers
	dc.w	op_nothing-operand_handlers
	dc.w	op_cmpm-operand_handlers
	dc.w	op_cmp_group-operand_handlers
	dc.w	op_add_sub-operand_handlers
	dc.w	op_or_and-operand_handlers
	dc.w	op_shift-operand_handlers
	dc.w	op_dc_w-operand_handlers
	dc.w	op_illegal-operand_handlers

;------------------------------------------------------------------------------
; ORI, ANDI, SUBI, ADDI, EORI, CMPI: #data, then the effective address (CCR or SR for mode $3C).
;------------------------------------------------------------------------------
op_immediate:	; from: operand_handlers
	bsr.w	put_size                        ; the size
	move.b	#$23,(a4)+                      ; #
	tst.b	d5                              ; a byte?
	bne.s	op_immediate_word               ; no
	move.w	(a5)+,d1                        ; the byte, in a word
	bsr.w	put_byte
	bra.s	op_immediate_ea
op_immediate_word:
	cmp.b	#$1,d5                          ; a word?
	beq.s	op_immediate_wordv              ; yes
	move.l	(a5)+,d1                        ; a long
	bsr.w	put_address
	bra.s	op_immediate_ea
op_immediate_wordv:
	move.w	(a5)+,d1
	bsr.w	put_word
op_immediate_ea:
	move.b	#$2c,(a4)+                      ; ,
	move.b	d7,d0
	andi.b	#$3f,d0
	cmp.b	#$3c,d0                         ; to the CCR or SR?
	bne.s	op_immediate_dest               ; no
	tst.b	d5                              ; a byte: CCR
	bne.s	put_sr
put_ccr:	; from: op_move_ccr
	lea	str_ccr(pc),a0                  ; "CCR"
	bra.w	put_counted
str_ccr:
	dc.w	$0343,$4352
put_sr:	; from: op_move_sr
	lea	str_sr(pc),a0                   ; "SR"
	bra.w	put_counted
str_sr:
	dc.w	$0253,$5200
op_immediate_dest:
	moveq	#61,d4                          ; the data alterable modes
	bra.w	put_ea                          ; the effective address

;------------------------------------------------------------------------------
; MOVEP: d(An) and Dn in the order of the direction bit.
;------------------------------------------------------------------------------
op_movep:	; from: operand_handlers
	moveq	#76,d0                          ; L
	btst	#$6,d7                          ; a long?
	bne.s	op_movep_size                   ; yes
	moveq	#87,d0                          ; W
op_movep_size:
	move.b	d0,(a4)+
	move.b	#$20,(a4)+                      ; a space
	move.b	d7,d2                           ; the address register
	move.w	d7,d3
	lsr.w	#8,d3                           ; the data register
	lsr.w	#1,d3
	lea	op_movep_memory(pc),a0          ; memory
	lea	op_movep_register(pc),a1        ; register
	btst	#$7,d7                          ; to memory?
	beq.s	op_movep_put                    ; no
	exg	a1,a0                           ; the other way round
op_movep_put:
	jsr	(a0)                            ; the first
	move.b	#$2c,(a4)+                      ; ,
	jmp	(a1)                            ; the second
op_movep_memory:
	move.w	(a5)+,d1                        ; the displacement
	bsr.w	put_signed_word
	move.b	#$28,(a4)+                      ; (
	move.b	#$41,(a4)+                      ; A
	move.b	d2,d1
	bsr.w	put_register_number             ; the register
	move.b	#$29,(a4)+                      ; )
	rts
op_movep_register:
	move.b	#$44,(a4)+                      ; D
	move.b	d3,d1
	bra.w	put_register_number             ; the register

;------------------------------------------------------------------------------
; BTST, BCHG, BCLR, BSET with the bit number in Dn.
;------------------------------------------------------------------------------
op_bit_dynamic:	; from: operand_handlers
	move.b	d5,d1                           ; the operation
	bsr.w	put_bit_op
	clr.b	d5
	move.b	#$44,(a4)+                      ; D
	move.w	d7,d1
	lsr.w	#8,d1
	lsr.w	#1,d1
	bsr.w	put_register_number             ; the register
	move.b	#$2c,(a4)+                      ; ,
	moveq	#61,d4                          ; the data alterable modes
	move.w	d7,d0
	andi.b	#$c0,d0                         ; BTST?
	bne.s	op_bit_ea                       ; no
	moveq	#-3,d4                          ; BTST: the data modes
op_bit_ea:	; from: op_bit_static
	bra.w	put_ea                          ; the effective address

;------------------------------------------------------------------------------
; The same with an immediate bit number.
;------------------------------------------------------------------------------
op_bit_static:	; from: operand_handlers
	move.b	d5,d1                           ; the operation
	bsr.w	put_bit_op
	clr.b	d5
	move.b	#$23,(a4)+                      ; #
	move.w	(a5)+,d1                        ; the bit number
	bsr.w	put_byte
	move.b	#$2c,(a4)+                      ; ,
	moveq	#61,d4                          ; the data alterable modes
	move.w	d7,d0
	andi.b	#$c0,d0                         ; BTST?
	bne.s	op_bit_ea                       ; no
	moveq	#125,d4                         ; BTST: no immediate
	bra.s	op_bit_ea

;------------------------------------------------------------------------------
; MOVE: the source, then the destination (its mode and register the other way round).
;------------------------------------------------------------------------------
op_move:	; from: operand_handlers
	move.w	d7,d5
	moveq	#12,d0
	lsr.w	d0,d5                           ; the size bits
	andi.w	#$3,d5
	move.b	move_sizes(pc,d5.w),d5          ; as B, W, L
	move.w	d7,-(sp)
	moveq	#-1,d4                          ; any source
	bsr.w	put_ea                          ; the source
	move.w	(sp)+,d7
	move.b	ea_count(a6),d0                 ; the source's effective address
	move.l	ea_address(a6),ea_address2(a6)
	sf	ea_count(a6)
	move.w	d0,-(sp)
	move.b	#$2c,(a4)+                      ; ,
	move.w	d7,d1                           ; the destination's register
	move.b	#$9,d0
	lsr.w	d0,d1
	andi.w	#$7,d1
	move.w	d7,d2                           ; its mode
	lsr.w	#6,d2
	andi.w	#$7,d2
	moveq	#63,d4                          ; the alterable modes
	bsr.w	put_ea_mode                     ; the destination
	move.w	(sp)+,d0
	tst.b	ea_count(a6)                    ; a destination address?
	beq.s	op_move_one                     ; no
	tst.b	d0                              ; a source address?
	beq.s	op_move_done                    ; no
	st	ea_two(a6)                      ; two of them
	movem.l	ea_address(a6),d0-d1            ; the source's first
	exg	d0,d1
	movem.l	d0-d1,ea_address(a6)
	rts
op_move_one:
	move.b	d0,ea_count(a6)
op_move_done:
	rts
move_sizes:
	dc.w	$0300,$0201                     ; the size codes for MOVE's size bits

;------------------------------------------------------------------------------
; STOP: #data.
;------------------------------------------------------------------------------
op_word:	; from: operand_handlers
	move.w	(a5)+,d1                        ; the word
	bra.w	put_word

;------------------------------------------------------------------------------
; Put the register number in d7's low 3 bits.
;------------------------------------------------------------------------------
put_low_register:	; from: operand_handlers, op_link, op_move_usp
	andi.b	#$7,d7
	addi.b	#$30,d7
	move.b	d7,(a4)+
	rts

;------------------------------------------------------------------------------
; LINK: An,#displacement.
;------------------------------------------------------------------------------
op_link:	; from: operand_handlers
	bsr.s	put_low_register                ; the register
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$23,(a4)+                      ; #
	move.w	(a5)+,d1                        ; the displacement
	bra.w	put_signed_word

;------------------------------------------------------------------------------
; MOVE An,USP.
;------------------------------------------------------------------------------
op_move_usp:	; from: operand_handlers
	bsr.s	put_low_register                ; the register
	lea	str_usp(pc),a0                  ; ",USP"
	bra.w	put_counted
str_usp:
	dc.w	$042c,$5553,$5020

;------------------------------------------------------------------------------
; TRAP: #0-15 in decimal.
;------------------------------------------------------------------------------
op_trap:	; from: operand_handlers
	andi.w	#$f,d7                          ; the vector
	cmp.b	#$a,d7                          ; 10 or more?
	bcs.s	op_trap_digit                   ; no
	move.b	#$31,(a4)+                      ; 1
	subi.b	#$a,d7
op_trap_digit:
	addi.b	#$30,d7
	move.b	d7,(a4)+
	rts

;------------------------------------------------------------------------------
; One effective address: NEGX, CLR, NEG, NOT, TST with a size, or NBCD, TAS, JSR, JMP, PEA, MOVE SR.
;------------------------------------------------------------------------------
op_single:	; from: operand_handlers
	move.b	-(a4),d0                        ; the last character
	cmp.b	#$2e,d0                         ; a dot already?
	beq.s	op_single_dot                   ; yes
	addq.l	#1,a4
	bsr.w	put_size                        ; the size
	bra.s	op_single_ea
op_single_dot:
	moveq	#2,d5
op_single_ea:
	move.b	line_buffer(a6),d0              ; the mnemonic's first letter
	moveq	#100,d4                         ; the control modes
	cmp.b	#$4a,d0                         ; JSR or JMP?
	beq.w	put_ea
	cmp.b	#$50,d0                         ; PEA?
	beq.w	put_ea
	moveq	#61,d4                          ; the data alterable modes
	bra.w	put_ea

;------------------------------------------------------------------------------
; MOVE to CCR.
;------------------------------------------------------------------------------
op_move_ccr:	; from: operand_handlers
	moveq	#1,d5                           ; a word
	moveq	#-3,d4                          ; the data modes
	bsr.w	put_ea                          ; the source
	move.b	#$2c,(a4)+                      ; ,
	bra.w	put_ccr                         ; CCR

;------------------------------------------------------------------------------
; MOVE to SR.
;------------------------------------------------------------------------------
op_move_sr:	; from: operand_handlers
	moveq	#1,d5                           ; a word
	moveq	#-3,d4                          ; the data modes
	bsr.w	put_ea                          ; the source
	move.b	#$2c,(a4)+                      ; ,
	bra.w	put_sr                          ; SR

;------------------------------------------------------------------------------
; MOVEM registers to memory: the list (reversed for -(An)), then the address.
;------------------------------------------------------------------------------
op_movem_to:	; from: operand_handlers
	move.b	d7,d5
	lsr.b	#6,d5                           ; the size bit
	andi.b	#$1,d5
	addq.b	#1,d5                           ; W or L
	bsr.w	put_size                        ; the size
	move.w	(a5)+,-(sp)                     ; the register mask
	moveq	#108,d4                         ; the control modes and -(An)
	bsr.w	put_ea                          ; the address
	move.b	#$3,ea_size(a6)
	move.w	(sp)+,d6                        ; the mask
	move.b	#$2c,(a4)+                      ; ,

movem_reverse:	; from: op_movem_from
	moveq	#15,d0                          ; 16 bits
movem_reverse_loop:
	roxl.w	#1,d6
	roxr.w	#1,d1                           ; reversed
	dbra	d0,movem_reverse_loop

;------------------------------------------------------------------------------
; Put the register mask d1 as a list: D registers, a /, A registers, runs as ranges.
;------------------------------------------------------------------------------
put_register_list:	; from: op_movem_from
	move.w	d1,d3                           ; the data registers
	ror.w	#8,d3
	move.b	#$44,d4                         ; D
	bsr.s	put_register_set
	tst.b	d3                              ; any?
	beq.s	put_register_list_a             ; no
	tst.b	d1                              ; any address registers?
	beq.s	put_register_list_a             ; no
	move.b	#$2f,(a4)+                      ; /
put_register_list_a:
	move.w	d1,d3                           ; the address registers
	move.b	#$41,d4                         ; A

;------------------------------------------------------------------------------
; Put the registers set in d3 (bit 7 the first), named with the letter d4.
;------------------------------------------------------------------------------
put_register_set:	; from: put_register_list
	tst.b	d3                              ; any?
	beq.s	put_register_set_done           ; no
	moveq	#7,d0                           ; 8 bits
put_register_set_loop:
	btst	d0,d3                           ; this one?
	beq.s	put_register_next               ; no
	move.b	d4,(a4)+                        ; the letter
	moveq	#55,d6
	sub.b	d0,d6                           ; its number
	move.b	d6,(a4)+
	tst.b	d0                              ; the last?
	beq.s	put_register_set_done           ; yes
	subq.b	#1,d0
	btst	d0,d3                           ; the next set too?
	beq.s	put_register_slash              ; no
	tst.b	d0                              ; the last?
	bne.s	put_register_range              ; no
put_register_range_end:
	move.b	#$2d,(a4)+                      ; -
	tst.b	listing_mode(a6)                ; the letter again?
	beq.s	put_register_range_7            ; no
	move.b	d4,(a4)+
put_register_range_7:
	move.b	#$37,(a4)+                      ; 7
put_register_set_done:
	rts
put_register_range:
	subq.b	#1,d0
	btst	d0,d3                           ; the next set?
	bne.s	put_register_range_more         ; yes: on
	move.b	#$2d,(a4)+                      ; -
	tst.b	listing_mode(a6)                ; the letter again?
	beq.s	put_register_range_last         ; no
	move.b	d4,(a4)+
put_register_range_last:
	moveq	#54,d6                          ; the range's end
	sub.b	d0,d6
	move.b	d6,(a4)+
	move.b	#$2f,(a4)+                      ; /
	bra.s	put_register_next
put_register_range_more:
	tst.b	d0                              ; the last?
	beq.s	put_register_range_end          ; yes
	bra.s	put_register_range
put_register_slash:
	move.b	#$2f,(a4)+                      ; /
put_register_next:
	subq.b	#1,d0
	bcc.s	put_register_set_loop
	subq.l	#1,a4                           ; back over the last /
	rts

;------------------------------------------------------------------------------
; MOVEM memory to registers.
;------------------------------------------------------------------------------
op_movem_from:	; from: operand_handlers
	move.b	d7,d5
	lsr.b	#6,d5                           ; the size bit
	andi.b	#$1,d5
	addq.b	#1,d5                           ; W or L
	bsr.w	put_size                        ; the size
	move.w	(a5)+,d6                        ; the register mask
	move.w	d7,d2
	andi.b	#$38,d2
	cmp.b	#$20,d2                         ; -(An)?
	bne.s	op_movem_from_reverse           ; no
	move.w	d6,d1
	bsr.w	put_register_list               ; the list as it is
op_movem_from_ea:
	move.b	#$2c,(a4)+                      ; ,
	moveq	#52,d4                          ; the control modes and (An)+
	bsr.w	put_ea
	move.b	#$3,ea_size(a6)
	rts
op_movem_from_reverse:
	bsr.w	movem_reverse                   ; reversed
	bra.s	op_movem_from_ea

;------------------------------------------------------------------------------
; CHK, DIVU, DIVS, MULU, MULS: the source, then Dn.
;------------------------------------------------------------------------------
op_ea_dn:	; from: operand_handlers
	moveq	#1,d5                           ; a word
	moveq	#-3,d4                          ; the data modes
	bsr.w	put_ea                          ; the source
	lsr.w	#1,d7
	lsr.w	#8,d7
	andi.b	#$7,d7                          ; the register
	addi.b	#$30,d7
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$44,(a4)+                      ; D
	move.b	d7,(a4)+
	rts

;------------------------------------------------------------------------------
; LEA: the address, then An.
;------------------------------------------------------------------------------
op_lea:	; from: operand_handlers
	moveq	#2,d5                           ; a long
	moveq	#100,d4                         ; the control modes
	bsr.w	put_ea                          ; the address
	move.b	#$9,d0
	move.w	d7,d1
	lsr.w	d0,d1
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$41,(a4)+                      ; A
	bra.w	put_register_number             ; the register

;------------------------------------------------------------------------------
; DBcc: the condition, Dn and the target.
;------------------------------------------------------------------------------
op_dbcc:	; from: operand_handlers
	move.w	d7,d1
	lsr.w	#8,d1
	andi.b	#$f,d1                          ; the condition
	bsr.w	put_condition
	move.b	#$44,(a4)+                      ; D
	andi.b	#$7,d7
	addi.b	#$30,d7
	move.b	d7,(a4)+
	move.b	#$2c,(a4)+                      ; ,
	move.l	a5,d1                           ; the target
	move.w	(a5)+,d2
	ext.l	d2
	add.l	d2,d1
	add.l	address_offset(a6),d1           ; + the address offset
	bra.w	put_address                     ; as a symbol or a number

;------------------------------------------------------------------------------
; Scc: the condition and the address.
;------------------------------------------------------------------------------
op_scc:	; from: operand_handlers
	move.w	d7,d1
	lsr.w	#8,d1
	andi.w	#$f,d1                          ; the condition
	bsr.w	put_condition
	clr.b	d5                              ; a byte
	moveq	#61,d4                          ; the data alterable modes
	bra.w	put_ea

;------------------------------------------------------------------------------
; ADDQ, SUBQ: #1-8, then the address.
;------------------------------------------------------------------------------
op_quick:	; from: operand_handlers
	bsr.w	put_size                        ; the size
	move.b	#$23,(a4)+                      ; #
	move.w	d7,d1
	lsr.w	#8,d1
	lsr.w	#1,d1
	andi.w	#$7,d1                          ; the data
	bne.s	op_quick_digit
	moveq	#8,d1                           ; 0 is 8
op_quick_digit:
	bsr.w	put_digit
	move.b	#$2c,(a4)+                      ; ,
	moveq	#63,d4                          ; the alterable modes
	bra.w	put_ea

;------------------------------------------------------------------------------
; EXG: Dn,Dn or An,An or Dn,An.
;------------------------------------------------------------------------------
op_exg:	; from: operand_handlers, op_add_sub
	move.w	d7,d0
	andi.w	#$f8,d0                         ; the mode
	move.b	d7,d2
	move.w	d7,d1
	lsr.w	#8,d1
	lsr.w	#1,d1
	cmp.b	#$40,d0                         ; data registers?
	beq.s	op_exg_data
	cmp.b	#$48,d0                         ; address registers?
	beq.s	op_exg_address
	cmp.b	#$88,d0                         ; one of each?
	beq.s	op_exg_mixed
	move.b	#$3f,(a4)+                      ; ??
	move.b	#$3f,(a4)+
	rts
op_exg_data:
	move.b	#$44,(a4)+                      ; D
	bsr.w	put_register_number
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$44,(a4)+                      ; D
op_exg_second:
	move.b	d2,d1
	bra.w	put_register_number
op_exg_address:
	move.b	#$41,(a4)+                      ; A
	bsr.w	put_register_number
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$41,(a4)+                      ; A
	bra.s	op_exg_second
op_exg_mixed:
	move.b	#$44,(a4)+                      ; D
	bsr.w	put_register_number
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$41,(a4)+                      ; A
	bra.s	op_exg_second

;------------------------------------------------------------------------------
; Bcc, BRA, BSR: the condition and the target (.S for a short branch).
;------------------------------------------------------------------------------
op_bcc:	; from: operand_handlers
	move.w	d7,d1
	lsr.w	#8,d1
	andi.b	#$f,d1                          ; the condition
	beq.s	op_bcc_bra                      ; BRA
	cmp.b	#$1,d1                          ; BSR?
	beq.s	op_bcc_bsr
	bsr.w	put_condition                   ; the condition
	bra.s	op_bcc_target
op_bcc_bra:
	subq.l	#1,a4
	move.l	#$42524120,(a4)+                ; "BRA "
	bra.s	op_bcc_target
op_bcc_bsr:
	subq.l	#1,a4
	move.l	#$42535220,(a4)+                ; "BSR "
op_bcc_target:
	move.b	d7,d1                           ; a short branch?
	beq.s	op_bcc_word                     ; no
	move.b	#$2e,-$1(a4)                    ; .
	move.b	#$53,(a4)+                      ; S
	move.b	#$20,(a4)+
	ext.w	d1
	ext.l	d1
op_bcc_put:
	add.l	a5,d1                           ; the target
	add.l	address_offset(a6),d1           ; + the address offset
	bra.w	put_address                     ; as a symbol or a number
op_bcc_word:
	move.w	(a5)+,d1                        ; the displacement
	ext.l	d1
	subq.l	#2,d1                           ; from the opcode's address
	bra.s	op_bcc_put

;------------------------------------------------------------------------------
; MOVEQ: #data,Dn.
;------------------------------------------------------------------------------
op_moveq:	; from: operand_handlers
	move.b	d7,d1                           ; the data
	bsr.w	put_signed_byte
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$44,(a4)+                      ; D
	move.w	d7,d1
	lsr.w	#8,d1
	lsr.w	#1,d1
	bra.w	put_register_number

;------------------------------------------------------------------------------
; SBCD, SUBX, ABCD, ADDX: Dn,Dn or -(An),-(An).
;------------------------------------------------------------------------------
op_bcd:	; from: operand_handlers
	moveq	#-1,d0
	cmpi.b	#$58,0(a4,d0.w)                 ; the last character an X?
	bne.s	op_bcd_operands                 ; no
	bsr.w	put_size                        ; the size
op_bcd_operands:
	move.b	d7,d1
	move.w	d7,d2
	lsr.w	#8,d2
	lsr.w	#1,d2
	btst	#$3,d7                          ; memory?
	beq.s	op_bcd_data                     ; no
	move.b	#$2d,(a4)+                      ; -
	move.b	#$28,(a4)+                      ; (
	move.b	#$41,(a4)+                      ; A
	bsr.w	put_register_number
	lea	str_predec(pc),a0               ; "),-(A"
	bsr.w	put_counted
	move.b	d2,d1
	bsr.w	put_register_number
	move.b	#$29,(a4)+                      ; )
	rts
op_bcd_data:
	move.b	#$44,(a4)+                      ; D
	bsr.w	put_register_number
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$44,(a4)+                      ; D
	move.b	d2,d1
	bra.w	put_register_number
str_predec:
	dc.w	$0529,$2c2d,$2841

;------------------------------------------------------------------------------
; CMPM: (An)+,(An)+.
;------------------------------------------------------------------------------
op_cmpm:	; from: operand_handlers
	bsr.w	put_size                        ; the size
	cmp.b	#$3,d5                          ; a word size 3?
	bne.s	op_cmpm_operands                ; no
	lea	line_buffer(a6),a4
	bra.s	op_cmp_group                    ; no: the CMP group
op_cmpm_operands:
	move.w	d7,d1
	move.b	#$28,(a4)+                      ; (
	move.b	#$41,(a4)+                      ; A
	bsr.w	put_register_number
	lea	str_postinc(pc),a0              ; ")+,(A"
	bsr.w	put_counted
	move.w	d7,d1
	lsr.w	#8,d1
	lsr.w	#1,d1
	bsr.w	put_register_number
	move.b	#$29,(a4)+                      ; )
	move.b	#$2b,(a4)+                      ; +
	rts
str_postinc:
	dc.w	$0529,$2b2c,$2841

;------------------------------------------------------------------------------
; CMP, CMPA and EOR, by the opmode.
;------------------------------------------------------------------------------
op_cmp_group:	; from: operand_handlers, op_cmpm
	lea	cmp_opmodes(pc),a0              ; the opmodes
	move.w	d7,d5
	lsr.w	#6,d5
	andi.b	#$7,d5
	move.b	d5,d0
	bra.w	dispatch
cmp_opmodes:
	dc.w	op_cmp-cmp_opmodes
	dc.w	op_cmp-cmp_opmodes
	dc.w	op_cmp-cmp_opmodes
	dc.w	op_cmpa-cmp_opmodes
	dc.w	op_eor-cmp_opmodes
	dc.w	op_eor-cmp_opmodes
	dc.w	op_eor-cmp_opmodes
	dc.w	op_cmpa-cmp_opmodes
op_cmpa:
	lsr.b	#2,d5
	andi.b	#$1,d5
	addq.b	#1,d5                           ; W or L
	move.l	#$434d5041,(a4)+                ; "CMPA"
	bsr.w	put_size                        ; the size
	moveq	#-1,d4                          ; any source
	bsr.w	put_ea
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$41,(a4)+                      ; A

;------------------------------------------------------------------------------
; Put the register number in d7's bits 9-11.
;------------------------------------------------------------------------------
put_reg_9:
	move.w	d7,d1
	lsr.w	#1,d1
	lsr.w	#8,d1
	bra.w	put_register_number
op_cmp:	; from: op_cmp_group
	lea	str_cmp(pc),a0                  ; "CMP"
	bsr.w	put_counted
	bsr.w	put_size                        ; the size
	moveq	#-1,d4                          ; any source
	bsr.w	put_ea
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$44,(a4)+                      ; D
	bra.s	put_reg_9
str_cmp:
	dc.w	$0343,$4d50
op_eor:	; from: op_cmp_group
	andi.b	#$3,d5
	lea	str_eor(pc),a0                  ; "EOR"
	bsr.w	put_counted
	bsr.w	put_size                        ; the size
	move.b	#$44,(a4)+                      ; D
	bsr.s	put_reg_9
	move.b	#$2c,(a4)+                      ; ,
	moveq	#61,d4                          ; the data alterable modes
	bra.w	put_ea
str_eor:
	dc.w	$0345,$4f52

;------------------------------------------------------------------------------
; OR, AND: to Dn or to memory, by the direction bit.
;------------------------------------------------------------------------------
op_or_and:	; from: operand_handlers
	bsr.w	put_size                        ; the size
	move.w	d7,d0
	andi.w	#$100,d0                        ; to memory?
	bne.s	op_to_memory                    ; yes
	moveq	#-3,d4                          ; the data modes
	bra.s	op_to_dn

;------------------------------------------------------------------------------
; ADD, SUB, ADDA, SUBA (and EXG, which shares its opcodes).
;------------------------------------------------------------------------------
op_add_sub:	; from: operand_handlers
	move.w	d7,d0
	andi.w	#$f1f8,d0
	cmp.w	#$c140,d0                       ; EXG Dn?
	beq.s	op_exg_named
	cmp.w	#$c148,d0                       ; EXG An?
	beq.s	op_exg_named
	cmp.w	#$c188,d0                       ; EXG Dn,An?
	bne.s	op_add_sub_size                 ; no
op_exg_named:
	lea	line_buffer(a6),a4
	move.l	#$45584720,(a4)+                ; "EXG "
	bra.w	op_exg
op_add_sub_size:
	cmp.b	#$3,d5                          ; ADDA or SUBA?
	beq.s	op_adda                         ; yes
	bsr.w	put_size                        ; the size
	move.w	d7,d0
	andi.w	#$100,d0
	bne.s	op_to_memory                    ; to memory?
	moveq	#-1,d4                          ; any source
op_to_dn:	; from: op_or_and
	bsr.w	put_ea                          ; the source
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$44,(a4)+                      ; D
	move.w	d7,d1
	lsr.w	#1,d1
	lsr.w	#8,d1
	bra.w	put_register_number
op_to_memory:	; from: op_or_and
	move.b	#$44,(a4)+                      ; D
	move.w	d7,d1
	lsr.w	#1,d1
	lsr.w	#8,d1
	bsr.w	put_register_number
	move.b	#$2c,(a4)+                      ; ,
	move.w	d7,d0
	move.w	#$3c,d4                         ; the memory alterable modes
	bra.w	put_ea
op_adda:
	move.w	d7,d5
	lsr.w	#8,d5
	andi.b	#$1,d5
	addq.b	#1,d5                           ; W or L
	bsr.w	put_size                        ; the size
	moveq	#-1,d4                          ; any source
	bsr.w	put_ea
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$41,(a4)+                      ; A
	move.w	d7,d1
	lsr.w	#1,d1
	lsr.w	#8,d1
	bra.w	put_register_number

;------------------------------------------------------------------------------
; ASx, LSx, ROXx, ROx: on a register (#count or Dn) or on memory.
;------------------------------------------------------------------------------
op_shift:	; from: operand_handlers
	move.w	d7,d1
	cmp.b	#$3,d5                          ; memory?
	beq.s	op_shift_memory                 ; yes
	lsr.b	#2,d1                           ; the type
	bsr.s	put_shift_name                  ; the name
	bsr.w	put_size                        ; the size
	move.w	d7,d1
	lsr.w	#8,d1
	lsr.w	#1,d1
	btst	#$5,d7                          ; a count in a register?
	bne.s	op_shift_register               ; yes
	move.b	#$23,(a4)+                      ; #
	andi.w	#$7,d1
	bne.s	op_shift_count                  ; 0 is 8
	moveq	#8,d1
op_shift_count:
	bsr.w	put_digit
	move.b	#$2c,(a4)+                      ; ,
	move.b	#$44,(a4)+                      ; D
	move.b	d7,d1
	bra.w	put_register_number
op_shift_register:
	move.b	#$44,(a4)+                      ; D
	andi.b	#$7,d1
	bra.s	op_shift_count
op_shift_memory:
	lsr.w	#8,d1                           ; the type
	bsr.s	put_shift_name                  ; the name
	move.b	#$20,(a4)+                      ; a space
	moveq	#2,d5                           ; a word
	moveq	#60,d4                          ; the memory alterable modes
	bra.w	put_ea

;------------------------------------------------------------------------------
; Put the shift's name for d1 (AS, LS, ROX, RO) and its direction (L or R from bit 8).
;------------------------------------------------------------------------------
put_shift_name:	; from: op_shift
	andi.w	#$6,d1
	lea	shift_names(pc,d1.w),a0         ; the names
	move.b	(a0)+,(a4)+
	move.b	(a0),(a4)+
	cmp.b	#$4,d1                          ; ROX?
	bne.s	put_shift_direction             ; no
	move.b	#$58,(a4)+                      ; X
put_shift_direction:
	moveq	#76,d1                          ; L
	moveq	#8,d0
	btst	d0,d7                           ; left?
	bne.s	put_shift_put                   ; yes
	moveq	#82,d1                          ; R
put_shift_put:
	move.b	d1,(a4)+
	rts
shift_names:
	dc.b	'ASLSRORO'

;------------------------------------------------------------------------------
; DC.W: the word itself.
;------------------------------------------------------------------------------
op_dc_w:	; from: operand_handlers
	move.w	d7,d1
	bra.w	put_word

;------------------------------------------------------------------------------
; ILLEGAL: a breakpoint is shown as the instruction it replaced and [n], [=n], [*] or [?condition].
;------------------------------------------------------------------------------
op_illegal:	; from: operand_handlers
	lea	-$2(a5),a1                      ; the opcode's address
	bsr.w	find_breakpoint                 ; a breakpoint there?
	beq.s	op_breakpoint                   ; yes
	rts                                     ; no: ILLEGAL
op_breakpoint:
	lea	line_buffer(a6),a4              ; the line again
	move.w	4(a0),d7                        ; the instruction it replaced
	move.l	a0,-(sp)
	bsr.w	disassemble_opcode              ; disassembled
	move.b	#$20,-$1(a4)                    ; the Return a space
	move.b	#$5b,(a4)+                      ; [
	movea.l	(sp)+,a0
	move.l	8(a0),d1                        ; its count
	move.w	6(a0),d0                        ; its type
	cmp.w	#$1,d0                          ; plain?
	beq.s	op_breakpoint_count             ; yes: n
	cmp.w	#$2,d0                          ; a counter?
	beq.s	op_breakpoint_counter           ; yes: =n
	cmp.w	#$3,d0                          ; permanent?
	beq.s	op_breakpoint_permanent         ; yes: *
	move.b	#$3f,(a4)+                      ; conditional: ?
	lea	$c(a0),a1                       ; its condition
	moveq	#7,d0                           ; 8 characters
op_breakpoint_condition:
	move.b	(a1)+,d1
	beq.s	op_breakpoint_end               ; the end
	move.b	d1,(a4)+
	dbra	d0,op_breakpoint_condition
	move.b	#$2e,(a4)+                      ; "..."
	move.b	#$2e,(a4)+
	bra.s	op_breakpoint_end
op_breakpoint_permanent:
	move.b	#$2a,(a4)+                      ; *
	bra.s	op_breakpoint_end
op_breakpoint_counter:
	move.b	#$3d,(a4)+                      ; =
op_breakpoint_count:
	bsr.w	put_number                      ; the count
op_breakpoint_end:
	move.b	#$5d,(a4)+                      ; ]
	rts
op_nothing:	; from: operand_handlers
	rts

;------------------------------------------------------------------------------
; Put the effective address of d7's low 6 bits (mode bits 3-5, register bits 0-2); d4 = the modes allowed, d5
; the size.  The address used is worked out from the registers for the register window.
;------------------------------------------------------------------------------
put_ea:	; from: op_immediate, op_bit_dynamic, op_move, op_single, op_move_ccr, op_move_sr, 10 more
	move.w	d7,d1                           ; the register
	andi.w	#$7,d1
	move.w	d7,d2                           ; the mode
	lsr.w	#3,d2
	andi.b	#$7,d2

put_ea_mode:	; from: op_move
	move.b	d2,d0                           ; the mode
	move.w	d1,d6                           ; the register
	lea	ea_modes(pc),a0                 ; the modes
	bra.w	dispatch
ea_modes:
	dc.w	ea_dn-ea_modes
	dc.w	ea_an-ea_modes
	dc.w	ea_indirect-ea_modes
	dc.w	ea_postinc-ea_modes
	dc.w	ea_predec-ea_modes
	dc.w	ea_displacement-ea_modes
	dc.w	ea_index-ea_modes
	dc.w	ea_other-ea_modes
ea_dn:
	btst	d2,d4                           ; allowed?
	beq.w	ea_bad                          ; no: ??
	move.b	d6,d1
	move.b	#$44,(a4)+                      ; D
	bra.w	put_register_number
ea_an:
	btst	d2,d4                           ; allowed?
	beq.w	ea_bad                          ; no
	tst.b	d5                              ; a byte?
	beq.w	ea_bad                          ; not with An

put_an:	; from: ea_register_value
	move.b	#$41,(a4)+                      ; A
	bra.w	put_register_number
ea_indirect:	; from: put_ea_mode
	btst	d2,d4                           ; allowed?
	beq.w	ea_bad                          ; no

ea_indirect_address:	; from: ea_register_value
	bset	#$0,ea_count(a6)                ; an address worked out already?
	bne.s	put_indirect                    ; yes
	bsr.s	ea_register_value               ; the register's value
	move.l	d0,ea_address(a6)               ; the address
	move.b	d5,ea_size(a6)                  ; the size
	bra.s	put_indirect

;------------------------------------------------------------------------------
; d0 = the value of address register d6 (A7 as the user or supervisor stack by the SR).
;------------------------------------------------------------------------------
ea_register_value:	; from: ea_indirect_address, index_address
	move.w	d6,d0
	add.w	d0,d0
	add.w	d0,d0                           ; longs
	cmp.w	#$1c,d0                         ; A7?
	bne.s	ea_register_value_get           ; no
	btst	#$5,reg_sr+2(a6)                ; supervisor mode?
	beq.s	ea_register_value_get           ; no
	moveq	#32,d0                          ; the supervisor stack
ea_register_value_get:
	move.l	reg_a(a6,d0.w),d0
	rts
put_indirect:	; from: ea_indirect_address
	move.b	#$28,(a4)+                      ; (
	bsr.s	put_an                          ; An
	move.b	#$29,(a4)+                      ; )
	rts
ea_postinc:	; from: put_ea_mode
	btst	d2,d4                           ; allowed?
	beq.w	ea_bad                          ; no
	bsr.s	ea_indirect_address             ; (An)
	move.b	#$2b,(a4)+                      ; +
	rts
ea_predec:	; from: put_ea_mode
	btst	d2,d4                           ; allowed?
	beq.w	ea_bad                          ; no
	move.b	#$2d,(a4)+                      ; -
	btst	#$0,ea_count(a6)                ; worked out already?
	bne.s	put_indirect                    ; yes
	bsr.s	ea_indirect_address
	andi.w	#$3,d5                          ; the size
	moveq	#0,d0
	move.b	predec_bytes(pc,d5.w),d0        ; its bytes
	sub.l	d0,ea_address(a6)               ; taken off
	rts
predec_bytes:
	dc.w	$0102,$0400
ea_displacement:	; from: put_ea_mode
	btst	d2,d4                           ; allowed?
	beq.w	ea_bad                          ; no
	move.w	(a5)+,d1                        ; the displacement
	ext.l	d1
	bset	#$0,ea_count(a6)                ; worked out already?
	bne.s	ea_displacement_show            ; yes
	bsr.s	ea_register_value               ; the register
	add.l	d1,d0                           ; + the displacement
	move.l	d0,ea_address(a6)               ; the address
	move.b	d5,ea_size(a6)                  ; the size
ea_displacement_show:
	tst.l	symbols(a6)                     ; symbols?
	beq.s	ea_displacement_number          ; no: a number
	btst	d6,relative_registers(a6)       ; this register relative?
	beq.s	ea_displacement_relative        ; no
	cmpa.l	prog_text(a6),a5                ; in the program's text?
	bcs.s	ea_displacement_number          ; no: a number
	cmpa.l	prog_data(a6),a5
	bcc.s	ea_displacement_number          ; no: a number
	move.w	d1,d0
	ext.l	d0
	move.l	d2,-(sp)
	move.b	d6,d2
	addq.b	#1,d2
	bsr.w	always_found
	movem.l	(sp)+,d2
	beq.s	ea_displacement_relative
	bsr.w	put_symbol_name                 ; as a symbol
	bra.s	ea_displacement_register
ea_displacement_relative:
	tst.b	relative_offsets(a6)            ; relative offsets?
	beq.s	ea_displacement_number          ; no: a number
	cmp.b	#$7,d6                          ; A7?
	beq.s	ea_displacement_number          ; yes: a number
	move.w	d1,d0                           ; the displacement
	ext.l	d0
	move.l	d2,-(sp)
	moveq	#0,d2
	move.b	d6,d2
	lsl.w	#2,d2                           ; longs
	add.l	reg_a(a6,d2.w),d0               ; + the register
	move.l	(sp)+,d2
	bsr.w	find_symbol                     ; a symbol there?
	beq.s	ea_displacement_number          ; no: a number
	bsr.w	put_symbol_name                 ; its name
	bra.s	ea_displacement_register
ea_displacement_number:
	bsr.w	put_signed_word                 ; the displacement
ea_displacement_register:
	move.b	d6,d1                           ; the register
	bra.w	put_indirect                    ; (An)

;------------------------------------------------------------------------------
; Work out base a0 + the index word d4's displacement and index register (.W or .L) for the register window.
;------------------------------------------------------------------------------
index_address:	; from: keep_address
	move.b	d4,d0                           ; the displacement
	ext.w	d0
	adda.w	d0,a0
	move.w	d4,d0                           ; the index register
	rol.w	#6,d0
	andi.w	#$3c,d0
	cmp.w	#$3c,d0                         ; A7?
	bne.s	index_address_register          ; no
	btst	#$5,reg_sr+2(a6)                ; supervisor mode?
	beq.s	index_address_register          ; no
	moveq	#64,d0                          ; the supervisor stack
index_address_register:
	move.l	reg_d(a6,d0.w),d0               ; its value
	btst	#$b,d4                          ; a long?
	bne.s	index_address_set               ; yes
	ext.l	d0                              ; a word
index_address_set:
	adda.l	d0,a0                           ; added
	move.l	a0,ea_address(a6)               ; the address
	move.b	d5,ea_size(a6)                  ; the size
	rts
ea_index:	; from: put_ea_mode
	btst	#$5,d4                          ; allowed?
	beq.w	ea_bad                          ; no
	move.w	(a5)+,d4                        ; the extension word
	bset	#$0,ea_count(a6)                ; worked out already?
	bne.s	ea_index_show                   ; yes
	bsr.w	ea_register_value               ; the base register
	movea.l	d0,a0
	bsr.s	index_address                   ; the address
ea_index_show:
	move.b	d4,d1                           ; the displacement
	bsr.w	put_signed_byte
	move.b	#$28,(a4)+                      ; (
	move.b	#$41,(a4)+                      ; A
	move.b	d6,d1
	bsr.w	put_register_number             ; the base register
	move.b	#$2c,(a4)+                      ; ,
	tst.w	d4                              ; an address register?
	bmi.s	ea_index_a                      ; yes
	move.b	#$44,(a4)+                      ; D
	bra.s	ea_index_register
ea_index_a:
	move.b	#$41,(a4)+                      ; A
ea_index_register:
	move.w	d4,d1
	moveq	#12,d0
	lsr.w	d0,d1
	bsr.w	put_register_number             ; the index register
	moveq	#87,d0                          ; W
	andi.w	#$800,d4                        ; a long?
	beq.s	ea_index_size                   ; no
	moveq	#76,d0                          ; L
ea_index_size:
	move.b	#$2e,(a4)+                      ; .
	move.b	d0,(a4)+
	move.b	#$29,(a4)+                      ; )
	rts

;------------------------------------------------------------------------------
; Mode 7: the register field picks absolute word, absolute long, d(PC), d(PC,Xn) or #data.
;------------------------------------------------------------------------------
ea_other:	; from: put_ea_mode
	lea	ea_other_modes(pc),a0
	move.b	d1,d0
	bra.w	dispatch
ea_other_modes:
	dc.w	ea_absolute_word-ea_other_modes
	dc.w	ea_absolute_long-ea_other_modes
	dc.w	ea_pc_displacement-ea_other_modes
	dc.w	ea_pc_index-ea_other_modes
	dc.w	ea_immediate-ea_other_modes
	dc.w	ea_none-ea_other_modes
	dc.w	ea_none-ea_other_modes
	dc.w	ea_none-ea_other_modes
ea_bad:	; from: put_ea_mode, put_an, ea_register_value, index_address, keep_address
	move.b	#$3f,(a4)+                      ; ??
	move.b	#$3f,(a4)+
	rts
ea_absolute_word:
	btst	#$5,d4                          ; allowed?
	beq.s	ea_bad                          ; no
	move.w	(a5)+,d1                        ; the address
	ext.l	d1
	bsr.s	keep_address                    ; for the register window
	bsr.w	put_address                     ; as a symbol or a number
	move.b	#$2e,(a4)+                      ; .
	move.b	#$57,(a4)+                      ; W
	rts

;------------------------------------------------------------------------------
; Keep d1 as the instruction's effective address unless one is kept already.
;------------------------------------------------------------------------------
keep_address:	; from: ea_other
	bset	#$0,ea_count(a6)                ; one already?
	bne.s	keep_address_done               ; yes
	move.l	d1,ea_address(a6)               ; the address
	move.b	d5,ea_size(a6)                  ; the size
keep_address_done:
	rts
ea_absolute_long:	; from: ea_other
	btst	#$5,d4                          ; allowed?
	beq.s	ea_bad                          ; no
	move.l	(a5)+,d1                        ; the address
	bsr.s	keep_address                    ; kept
	bra.w	put_address                     ; as a symbol or a number
ea_pc_displacement:	; from: ea_other
	btst	#$6,d4                          ; allowed?
	beq.s	ea_bad                          ; no
	move.w	(a5),d1                         ; the displacement
	ext.l	d1
	add.l	a5,d1                           ; + its address
	addq.l	#2,a5
	add.l	address_offset(a6),d1           ; + the address offset
	bsr.s	keep_address                    ; kept
	bsr.w	put_address                     ; as a symbol or a number
	lea	str_pc(pc),a0                   ; "(PC)"
	bra.w	put_counted
str_pc:
	dc.w	$0428,$5043,$2920
ea_pc_index:	; from: ea_other
	btst	#$6,d4                          ; allowed?
	beq.s	ea_bad                          ; no
	move.w	(a5),d6                         ; the extension word
	move.w	d6,d4
	move.b	d6,d1                           ; the displacement
	ext.w	d1
	ext.l	d1
	add.l	a5,d1                           ; + its address
	addq.l	#2,a5
	add.l	address_offset(a6),d1           ; + the address offset
	bsr.w	put_address                     ; as a symbol or a number
	lea	str_pc_index(pc),a0             ; "(PC,"
	bsr.w	put_counted
	tst.w	d6                              ; an address register?
	bmi.s	ea_pc_index_a                   ; yes
	move.b	#$44,(a4)+                      ; D
	bra.s	ea_pc_index_register
str_pc_index:
	dc.w	$0428,$5043,$2c20
ea_pc_index_a:
	move.b	#$41,(a4)+                      ; A
ea_pc_index_register:
	move.w	d6,d1
	moveq	#12,d0
	lsr.w	d0,d1
	bsr.w	put_register_number             ; the index register
	move.b	#$2e,(a4)+                      ; .
	andi.w	#$800,d6                        ; a long?
	beq.s	ea_pc_index_word                ; no
	move.b	#$4c,(a4)+                      ; L
	bra.s	ea_pc_index_end
ea_pc_index_word:
	move.b	#$57,(a4)+                      ; W
ea_pc_index_end:
	move.b	#$29,(a4)+                      ; )
	bset	#$0,ea_count(a6)                ; worked out already?
	beq.s	ea_pc_index_address             ; no
	rts
ea_pc_index_address:
	lea	-$2(a5),a0                      ; the extension word's address
	bra.w	index_address                   ; the address
ea_immediate:	; from: ea_other
	btst	#$7,d4                          ; allowed?
	beq.w	ea_bad                          ; no
	move.b	#$23,(a4)+                      ; #
	tst.b	d5                              ; a byte?
	bne.s	ea_immediate_word               ; no
	move.w	(a5)+,d1                        ; in a word
	bra.w	put_byte
ea_immediate_word:
	cmp.b	#$2,d5                          ; a long?
	bne.s	ea_immediate_wordv              ; no
	move.l	(a5)+,d1
	bra.w	put_address
ea_immediate_wordv:
	move.w	(a5)+,d1
	bra.w	put_word
ea_none:	; from: ea_other
	move.b	#$3f,(a4)+                      ; ?
	rts

;------------------------------------------------------------------------------
; The opcodes: a mask and a value for each, in the order of mnemonic_table.
;------------------------------------------------------------------------------
opcode_table:	; from: disassemble_opcode
	dc.w	$f138,$0108,$ff00,$0000,$ff00,$0200,$ff00,$0400
	dc.w	$ff00,$0600,$ff00,$0800,$ff00,$0a00,$ff00,$0c00
	dc.w	$f100,$0100,$f000,$1000,$f1c0,$2040,$f000,$2000
	dc.w	$f1c0,$3040,$f000,$3000,$ffff,$4afb,$ffff,$4afc
	dc.w	$ffff,$4e70,$ffff,$4e71,$ffff,$4e72,$ffff,$4e73
	dc.w	$ffff,$4e75,$ffff,$4e76,$ffff,$4e77,$fff8,$4840
	dc.w	$fff8,$4880,$fff8,$48c0,$fff8,$4e50,$fff8,$4e58
	dc.w	$fff8,$4e60,$fff8,$4e68,$fff0,$4e40,$ffc0,$40c0
	dc.w	$fff8,$4848,$ffc0,$44c0,$ffc0,$46c0,$ffc0,$4800
	dc.w	$ffc0,$4ac0,$ffc0,$4e80,$ffc0,$4ec0,$ff80,$4880
	dc.w	$ff80,$4c80,$ff40,$4840,$ff00,$4000,$ff00,$4200
	dc.w	$ff00,$4400,$ff00,$4600,$ff00,$4a00,$f1c0,$4180
	dc.w	$f1c0,$41c0,$f0f8,$50c8,$f0c0,$50c0,$f100,$5000
	dc.w	$f100,$5100,$f000,$6000,$f100,$7000,$f1f0,$8100
	dc.w	$f1c0,$80c0,$f1c0,$81c0,$f000,$8000,$f0c0,$90c0
	dc.w	$f130,$9100,$f000,$9000,$f138,$b108,$f000,$b000
	dc.w	$f1f0,$c100,$f1c0,$c0c0,$f1c0,$c1c0,$f130,$c100
	dc.w	$f000,$c000,$f0c0,$d0c0,$f130,$d100,$f000,$d000
	dc.w	$f000,$e000,$0000,$0000

;------------------------------------------------------------------------------
; Each opcode's mnemonic: a length byte, the operand handler's number and the text.
;------------------------------------------------------------------------------
mnemonic_table:	; from: disassemble_opcode
	dc.w	$0703,$4d4f,$5645,$502e,$0402,$4f52,$4905,$0241
	dc.w	$4e44,$4905,$0253,$5542,$4905,$0241,$4444,$4902
	dc.w	$0542,$0502,$454f,$5249,$0502,$434d,$5049,$0204
	dc.w	$4208
	dc.b	$06
	dc.b	'MOVE.B ',9
	dc.b	$06
	dc.b	'MOVEA.L '
	dc.w	$0806
	dc.b	'MOVE.L ',9
	dc.b	$06
	dc.b	'MOVEA.W '
	dc.b	$08,$06,$4d,$4f,$56,$45,$2e,$57,$20,$06,$21,$44,$43,$2e,$57,$20
	dc.b	$08
	dc.b	'"ILLEGAL'
	dc.w	$0600,$5245,$5345,$5404,$004e,$4f50,$0707,$5354
	dc.w	$4f50,$2023,$0400,$5254,$4504,$0052,$5453,$0600
	dc.w	$5452,$4150,$5604,$0052,$5452,$0708,$5357,$4150
	dc.w	$2044,$0808,$4558,$542e,$5720,$4408,$0845,$5854
	dc.w	$2e4c,$2044,$0709,$4c49,$4e4b,$2041,$0708
	dc.b	'UNLK A',9,10,'MOVE.L A',13
	dc.b	$08
	dc.b	'MOVE.L USP,A'
	dc.w	$070b,$5452,$4150,$2023,$0a0c
	dc.b	'MOVE SR,.'
	dc.b	$07,$08,$42,$4b,$50,$54,$20,$23,$08
	dc.b	13,'MOVE.B '
	dc.w	$080e,$4d4f,$5645,$2e57,$2007,$0c4e,$4243,$4420
	dc.w	$2e06,$0c54,$4153,$202e,$060c,$4a53,$5220,$2e06
	dc.w	$0c4a,$4d50,$202e,$0610,$4d4f,$5645,$4d06,$0f4d
	dc.w	$4f56,$454d,$060c,$5045,$4120,$2e05,$0c4e,$4547
	dc.w	$5804,$0c43,$4c52,$040c,$4e45,$4704,$0c4e,$4f54
	dc.w	$040c,$5453,$5405,$1143,$484b,$2005,$124c,$4541
	dc.w	$2003,$1344,$4202,$1453,$0515,$4144,$4451,$0515
	dc.w	$5355,$4251,$0217,$4208,$184d,$4f56,$4551,$2023
	dc.w	$0619,$5342,$4344,$2006,$1144,$4956,$5520,$0611
	dc.w	$4449,$5653,$2003,$1f4f,$5205,$1e53,$5542,$4105
	dc.w	$1953,$5542,$5804,$1e53,$5542,$051c,$434d,$504d
	dc.w	$011d,$0619,$4142,$4344,$2006,$114d,$554c,$5520
	dc.w	$0611,$4d55,$4c53,$2005,$1645,$5847,$2004,$1f41
	dc.w	$4e44,$051e,$4144,$4441,$0519,$4144,$4458,$041e
	dc.w	$4144,$4401,$2006,$2144,$432e,$5720

;------------------------------------------------------------------------------
; a2 back to the instruction before it: from 12 bytes back, the first start that disassembles cleanly (no ? or
; breakpoint marks) and ends at a2; else 2 bytes back.  Z set when found.
;------------------------------------------------------------------------------
previous_instruction:	; from: disassembly_address
	movem.l	d3-d7/a3-a5,-(sp)
	move.l	symbols(a6),-(sp)               ; without symbols
	clr.l	symbols(a6)
	move.l	a2,-(sp)                        ; the address
	moveq	#3,d4                           ; 4 tries
	lea	-$c(a2),a5                      ; 12 bytes back
	movea.l	a5,a2
	bsr.w	check_address                   ; readable?
	bne.s	previous_instruction_none       ; no
previous_instruction_try:
	addq.w	#2,a5                           ; 2 bytes on
	movem.l	d4/a5,-(sp)
	sf	listing_mode(a6)                ; without the address
	bsr.w	disassemble                     ; disassembled
	cmpa.l	8(sp),a5                        ; ends at the address?
	movem.l	(sp)+,d4/a5
	bne.s	previous_instruction_next       ; no
	lea	line_buffer(a6),a1              ; its text
previous_instruction_check:
	move.b	(a1)+,d1                        ; a character
	cmp.b	#$5b,d1                         ; a [?
	beq.s	previous_instruction_found      ; yes: good
	cmp.b	#$3f,d1                         ; a ??
	beq.s	previous_instruction_next       ; yes: bad
	cmp.b	#$d,d1                          ; the end?
	bne.s	previous_instruction_check      ; no
previous_instruction_found:
	addq.l	#4,sp
	moveq	#0,d0                           ; found
previous_instruction_done:
	move.l	(sp)+,symbols(a6)               ; the symbols back
	movea.l	a5,a2
	movem.l	(sp)+,d3-d7/a3-a5
	tst.b	d0                              ; the flags
	rts
previous_instruction_next:
	dbra	d4,previous_instruction_try     ; the next try
previous_instruction_none:
	movea.l	(sp)+,a5                        ; the address
	subq.w	#2,a5                           ; 2 bytes back
	moveq	#-1,d0                          ; not found
	bra.s	previous_instruction_done
interpret_trace:	; from: interpret
	move.l	a2,reg_pc(a6)                   ; the PC
	bset	#$7,reg_sr+2(a6)                ; trace on
	bra.w	resume                          ; go

;------------------------------------------------------------------------------
; Control-T: run the instruction at a2 in a buffer and stop after it: a trap or Line-A/F as it is, JSR and BSR
; (made into a JSR to the absolute address) to their end; any other instruction is traced.
;------------------------------------------------------------------------------
interpret:	; from: cmd_trace_rom, go
	lea	interpret_buffer(a6),a0         ; the buffer
	move.l	#$4e714e71,d0                   ; nops
	move.l	d0,(a0)
	move.l	d0,4(a0)
	move.w	d0,8(a0)
	move.w	#$4afc,$a(a0)                   ; and ILLEGAL to stop
	move.w	(a2),d0                         ; the instruction
	andi.w	#$fff0,d0
	cmp.w	#$4e40,d0                       ; a trap?
	beq.s	interpret_copy_word             ; yes
	andi.w	#$ffc0,d0
	cmp.w	#$4e80,d0                       ; JSR?
	beq.s	interpret_jsr                   ; yes
	andi.w	#$ff00,d0
	cmp.w	#$6100,d0                       ; BSR?
	beq.w	interpret_bsr                   ; yes
	andi.w	#$f000,d0
	cmp.w	#$a000,d0                       ; Line-A?
	beq.s	interpret_copy_word             ; yes
	cmp.w	#$f000,d0                       ; Line-F?
	bne.s	interpret_trace                 ; no: trace it
interpret_copy_word:
	move.w	(a2)+,(a0)                      ; the instruction copied
	bra.w	interpret_go
interpret_jsr:
	move.w	(a2)+,d0
	move.w	d0,(a0)                         ; copied
	move.b	d0,d1                           ; its mode
	andi.b	#$38,d1
	cmp.b	#$10,d1                         ; (An)?
	beq.w	interpret_go                    ; yes: as it is
	cmp.b	#$28,d1                         ; d(An)?
	beq.s	interpret_copy_extension        ; yes
	cmp.b	#$30,d1                         ; d(An,Xn)?
	beq.s	interpret_copy_extension        ; yes
	cmp.b	#$38,d1                         ; mode 7?
	bne.s	interpret_trace_it              ; no: traced
	move.b	d0,d1
	andi.b	#$7,d1                          ; the register field
	beq.s	interpret_copy_extension        ; absolute word
	cmp.b	#$4,d1
	bcc.s	interpret_trace_it              ; not PC relative: traced
	cmp.b	#$1,d1                          ; absolute long?
	bne.s	interpret_jsr_pc                ; no
	move.l	(a2)+,2(a0)                     ; the address copied
	bra.s	interpret_go
interpret_trace_it:
	bra.w	interpret_trace
interpret_copy_extension:
	move.w	(a2)+,2(a0)                     ; the extension copied
	bra.s	interpret_go
interpret_jsr_pc:
	cmp.b	#$2,d1                          ; d(PC)?
	bne.s	interpret_jsr_pc_index          ; no
	move.l	a2,d0
	move.w	(a2)+,d1                        ; the displacement
	ext.l	d1
	add.l	d1,d0                           ; the target
	bra.s	interpret_jsr_absolute
interpret_jsr_pc_index:
	move.w	(a2)+,d1                        ; the extension word
	move.b	d1,d0
	ext.w	d0                              ; the displacement
	ext.l	d0
	add.l	a2,d0
	subq.l	#2,d0
	move.w	d1,d2                           ; the index register
	rol.w	#6,d2
	andi.w	#$3c,d2
	move.l	reg_d(a6,d2.w),d2               ; its value
	btst	#$b,d1                          ; a long?
	bne.s	interpret_jsr_pc_index_add      ; yes
	ext.l	d2                              ; a word
interpret_jsr_pc_index_add:
	add.l	d2,d0                           ; the target
	bra.s	interpret_jsr_absolute
interpret_bsr:
	move.w	(a2)+,d0                        ; the displacement
	tst.b	d0                              ; a word one?
	beq.s	interpret_bsr_word              ; yes
	ext.w	d0
	ext.l	d0
	add.l	a2,d0                           ; the target
interpret_jsr_absolute:
	move.w	#$4eb9,(a0)                     ; JSR absolute
	move.l	d0,2(a0)                        ; to the target
	bra.s	interpret_go
interpret_bsr_word:
	move.w	(a2)+,d0                        ; the displacement
	ext.l	d0
	lea	-$2(a2,d0.w),a1                 ; the target
	move.l	a1,d0
	bra.s	interpret_jsr_absolute
interpret_go:
	move.l	a2,interpret_return(a6)         ; where to go on afterwards
	move.l	a0,-(sp)
	move.l	(sp)+,reg_pc(a6)                ; the PC: the buffer
	bclr	#$7,reg_sr+2(a6)                ; no trace
	bra.w	resume                          ; go

;------------------------------------------------------------------------------
; Clear the breakpoint table.
;------------------------------------------------------------------------------
clear_breakpoints:	; from: print_wait
	moveq	#7,d0                           ; 8 entries
	lea	breakpoints+6(a6),a0            ; their types
clear_breakpoints_loop:
	clr.w	(a0)                            ; none
	lea	$48(a0),a0
	dbra	d0,clear_breakpoints_loop
	rts

;------------------------------------------------------------------------------
; a0 = a free breakpoint entry (entries whose ILLEGAL was overwritten are freed); Z clear when all are taken.
;------------------------------------------------------------------------------
free_breakpoint:	; from: set_breakpoint
	moveq	#7,d0                           ; 8 entries
	lea	breakpoints(a6),a0              ; the table
free_breakpoint_loop:
	tst.w	6(a0)                           ; free?
	beq.s	free_breakpoint_done            ; yes
	movea.l	(a0),a1                         ; its address
	cmpi.w	#$4afc,(a1)                     ; the ILLEGAL still there?
	beq.s	free_breakpoint_next            ; yes: in use
	clr.w	6(a0)                           ; no: freed
	clr.l	(a0)
	bra.s	free_breakpoint_done
free_breakpoint_next:
	lea	$48(a0),a0                      ; the next
	dbra	d0,free_breakpoint_loop
	moveq	#-1,d0                          ; all taken
free_breakpoint_done:
	rts

;------------------------------------------------------------------------------
; Set a breakpoint of type d3 (1 plain, 2 counter, 3 permanent, 4 conditional with the expression at a4) at
; a1, with the count d2: the word there is kept and replaced by ILLEGAL.  "Too many breakpoints!", "It's odd!",
; "In ROM!" or "Cannot write!" when it cannot; Z set when set.
;------------------------------------------------------------------------------
set_breakpoint:                                 ; from: window_breakpoint, cmd_toggle_breakpoint, cmd_step_over,
                                                ;   cmd_run_until, relocate_symbols, run_from_editor
	move.l	a1,-(sp)
	bsr.w	find_breakpoint                 ; one there already?
	bne.s	set_breakpoint_entry            ; no
	bsr.w	remove_breakpoint               ; yes: removed
set_breakpoint_entry:
	bsr.s	free_breakpoint                 ; a free entry
	movea.l	(sp)+,a1
	lea	text_too_many_breakpoints(pc),a2 ; "Too many breakpoints!"
	bne.s	set_breakpoint_error            ; none
	move.l	a1,d0                           ; the address
	btst	#$0,d0                          ; odd?
	lea	text_its_odd(pc),a2             ; "It's odd!"
	bne.s	set_breakpoint_error            ; yes
	cmp.b	#$4,d3                          ; conditional?
	bne.s	set_breakpoint_ram              ; no
	move.l	a0,-(sp)
	lea	$c(a0),a0                       ; its condition
set_breakpoint_condition:
	move.b	(a4)+,(a0)+                     ; copied
	bne.s	set_breakpoint_condition
	movea.l	(sp)+,a0
	bra.s	set_breakpoint_write
set_breakpoint_ram:
	bsr.w	check_ram                       ; in RAM?
	lea	text_in_rom(pc),a2              ; "In ROM!"
	bne.s	set_breakpoint_error            ; no
set_breakpoint_write:
	move.w	(a1),4(a0)                      ; the word kept
	move.w	#$4afc,(a1)                     ; ILLEGAL
	cmpi.w	#$4afc,(a1)                     ; written?
	lea	text_cannot_write(pc),a2        ; "Cannot write!"
	bne.s	set_breakpoint_error            ; no
	move.l	a1,(a0)                         ; the address
	move.l	d2,8(a0)                        ; the count
	move.w	d3,6(a0)                        ; the type
	moveq	#0,d0                           ; set
	rts
set_breakpoint_error:
	movea.l	a2,a0                           ; the message
	bsr.w	show_message                    ; shown
	moveq	#-1,d0                          ; failed
	rts

;------------------------------------------------------------------------------
; a0 = the breakpoint at a1, Z set; else d0 = -1.
;------------------------------------------------------------------------------
find_breakpoint:                                ; from: window_breakpoint, cmd_toggle_breakpoint, cmd_step, op_illegal,
                                                ;   set_breakpoint, exc_breakpoint, 1 more
	moveq	#7,d0                           ; 8 entries
	lea	breakpoints(a6),a0              ; the table
find_breakpoint_loop:
	cmpa.l	(a0),a1                         ; this address?
	bne.s	find_breakpoint_next            ; no
	tst.w	6(a0)                           ; in use?
	beq.s	find_breakpoint_next            ; no
	moveq	#0,d0                           ; found
	rts
find_breakpoint_next:
	lea	$48(a0),a0                      ; the next
	dbra	d0,find_breakpoint_loop
	moveq	#-1,d0                          ; none
	rts

;------------------------------------------------------------------------------
; Remove every breakpoint.
;------------------------------------------------------------------------------
remove_breakpoints:	; from: cmd_kill_breakpoints
	moveq	#7,d1                           ; 8 entries
	lea	breakpoints(a6),a0              ; the table
remove_breakpoints_loop:
	bsr.s	remove_breakpoint               ; removed
	lea	$48(a0),a0                      ; the next
	dbra	d1,remove_breakpoints_loop
	rts

;------------------------------------------------------------------------------
; Remove the breakpoint a0: its word put back if its ILLEGAL is still there.
;------------------------------------------------------------------------------
remove_breakpoint:	; from: window_breakpoint, cmd_toggle_breakpoint, set_breakpoint, remove_breakpoints
	tst.w	6(a0)                           ; in use?
	beq.s	remove_breakpoint_done          ; no
	clr.w	6(a0)                           ; free
	movea.l	(a0),a1                         ; its address
	cmpi.w	#$4afc,(a1)                     ; the ILLEGAL there?
	bne.s	remove_breakpoint_done          ; no
	move.w	4(a0),(a1)                      ; the word back
remove_breakpoint_done:
	rts

;------------------------------------------------------------------------------
; Put the temporary ILLEGAL at a1, its word kept.
;------------------------------------------------------------------------------
set_temporary_break:	; from: resume
	move.l	a1,temp_break(a6)               ; the address
	move.w	(a1),temp_break_word(a6)        ; its word
	move.w	#$4afc,(a1)                     ; ILLEGAL
	rts

;------------------------------------------------------------------------------
; Clear the history: 5 register snapshots.
;------------------------------------------------------------------------------
clear_history:	; from: print_wait
	lea	history(a6),a0                  ; the list
	move.l	a0,history_next(a6)             ; the next one to fill
	moveq	#4,d0                           ; 5 entries
clear_history_loop:
	clr.l	$46(a0)                         ; empty
	lea	$4a(a0),a0                      ; the next, $4a bytes on
	dbra	d0,clear_history_loop
	rts

;------------------------------------------------------------------------------
; Save the registers into the next history entry (5 kept, round).
;------------------------------------------------------------------------------
save_history:	; from: exc_trace_step, exc_breakpoint
	movea.l	history_next(a6),a0             ; the next entry
	lea	reg_d(a6),a1                    ; the registers
	moveq	#15,d0                          ; D0-D7 and A0-A7
save_history_loop:
	move.l	(a1)+,(a0)+
	dbra	d0,save_history_loop
	move.l	reg_ssp(a6),(a0)+               ; the supervisor stack
	move.w	reg_sr+2(a6),(a0)+              ; the SR
	move.l	reg_pc(a6),(a0)+                ; the PC
	lea	history_next(a6),a1             ; past the last entry?
	cmpa.l	a0,a1
	bne.s	save_history_next               ; no
	lea	history(a6),a0                  ; yes: the first again
save_history_next:
	move.l	a0,history_next(a6)             ; the next one to fill
	rts

;------------------------------------------------------------------------------
; H: "History": the last 5 register snapshots full screen, oldest first; Alt keys work, any other key closes.
;------------------------------------------------------------------------------
cmd_history:	; from: command_table
	lea	text_history(pc),a2             ; "History"
	bsr.w	open_full_window                ; full screen
	move.b	#$10,$3f(a3)                    ; a 16 character label column
	bsr.s	draw_history                    ; drawn
	lea	draw_history(pc),a0             ; its contents
	move.l	a0,$48(a3)                      ; drawn by draw_history
cmd_history_key:
	bsr.w	flush_get_key                   ; a key
	bpl.w	close_prompt                    ; not Alt: close
	bsr.w	window_command                  ; a window command
	bra.s	cmd_history_key

;------------------------------------------------------------------------------
; The history window: a heading of register numbers, then for each snapshot "D:", "A:", "A7'", "SR:" with
; flags and "PC:" with its symbol and instruction.
;------------------------------------------------------------------------------
draw_history:	; from: cmd_history
	tst.l	history+70(a6)                  ; any?
	beq.w	draw_history_done               ; no
	moveq	#48,d4                          ; '0'
	moveq	#7,d5                           ; 8 columns
	moveq	#6,d2
	bra.s	draw_history_column
draw_history_heading:
	moveq	#8,d2
draw_history_column:
	bsr.w	print_spaces                    ; to the column
	move.b	d4,d1                           ; its number
	bsr.w	print_char
	addq.b	#1,d4
	dbra	d5,draw_history_heading
	bsr.w	print_newline
	lea	history(a6),a0                  ; the first entry
	movea.l	a0,a4                           ; from it
	lea	history_next(a6),a2             ; the list's end
	tst.l	$90(a0)                         ; all 5 used?
	beq.s	draw_history_entry              ; no: from the first
	tst.l	$da(a0)
	beq.s	draw_history_entry
	tst.l	$124(a0)
	beq.s	draw_history_entry
	tst.l	$16e(a0)
	beq.s	draw_history_entry
	movea.l	history_next(a6),a4             ; yes: from the oldest, the next to fill
draw_history_entry:
	moveq	#12,d1                          ; "D:"
	bsr.w	print_message
	moveq	#7,d3                           ; 8 registers
draw_history_d:
	bsr.w	print_space
	move.l	(a4)+,d2
	bsr.w	print_hex_long                  ; in hex
	dbra	d3,draw_history_d
	bsr.w	print_newline
	moveq	#13,d1                          ; "A:"
	bsr.w	print_message
	moveq	#7,d3                           ; 8 registers
draw_history_a:
	bsr.w	print_space
	move.l	(a4)+,d2
	bsr.w	print_hex_long                  ; in hex
	dbra	d3,draw_history_a
	bsr.w	print_newline
	moveq	#2,d1                           ; "A7'"
	bsr.w	print_message
	move.l	(a4)+,d2                        ; the supervisor stack
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_space
	moveq	#1,d1                           ; "SR:"
	bsr.w	print_message
	move.w	(a4),d2                         ; the SR
	bsr.w	print_hex_word                  ; in hex
	bsr.w	print_space
	move.w	(a4)+,d4
	bsr.w	print_flags                     ; its flags
	bsr.w	print_newline
	moveq	#0,d1                           ; "PC:"
	bsr.w	print_message
	move.l	(a4),d2                         ; the PC
	bsr.w	print_hex_long                  ; in hex
	bsr.w	print_space
	move.b	$3f(a3),d2                      ; the label column
	move.l	(a4),d0
	bsr.w	find_symbol                     ; a symbol?
	beq.s	draw_history_instruction        ; no
	bsr.w	print_symbol_name               ; its name
draw_history_instruction:
	addq.b	#1,d2
	bsr.w	print_spaces                    ; to the column
	move.l	a2,-(sp)
	movea.l	(a4)+,a2                        ; the PC
	bsr.w	print_instruction               ; its instruction
	bsr.w	clear_to_eol
	movea.l	(sp)+,a2
	bsr.w	print_newline
	cmpa.l	a4,a2                           ; the list's end?
	bne.s	draw_history_next               ; no
	lea	history(a6),a4                  ; round to the first
draw_history_next:
	cmpa.l	history_next(a6),a4             ; the newest done?
	beq.s	draw_history_done               ; yes
	tst.l	$46(a4)                         ; an entry there?
	bne.w	draw_history_entry              ; yes: shown
draw_history_done:
	rts

;------------------------------------------------------------------------------
; Ask with the prompt at a0 for an expression: d2 = its value and Z set; else d2 = -1 (Esc).
;------------------------------------------------------------------------------
ask_address:	; from: window_address
	move.l	a3,-(sp)
	move.l	a0,-(sp)
	moveq	#4,d3                           ; 4 lines
	bsr.s	open_prompt                     ; the prompt window
	movea.l	(sp)+,a0
	bsr.w	print_string                    ; the prompt
	move.w	#$4,$16(a3)                     ; column 4
	move.w	$1a(a3),d0
	add.w	d0,$18(a3)                      ; a new line
	lea	arguments(a6),a4                ; the line
	clr.b	(a4)                            ; empty
	moveq	#0,d4
ask_address_line:
	bsr.w	edit_line                       ; edited
	bne.s	ask_address_cancel              ; Esc
	bsr.w	evaluate                        ; worked out
	bne.s	ask_address_bad                 ; bad
	tst.b	d1                              ; the end of the line?
	beq.s	ask_address_good                ; yes: good
ask_address_bad:
	bsr.w	bell                            ; the bell
	lea	arguments(a6),a4
	bra.s	ask_address_line                ; again
ask_address_good:
	move.l	d2,-(sp)
	bsr.w	close_prompt                    ; the prompt off
	move.l	(sp)+,d2
	movea.l	(sp)+,a3
	moveq	#0,d0                           ; good
	rts
ask_address_cancel:
	bsr.w	close_prompt                    ; the prompt off
	movea.l	(sp)+,a3
	moveq	#-1,d2                          ; none
	rts

;------------------------------------------------------------------------------
; Open the prompt window titled "ESC to abort", d3 lines, wide enough for the input field.
;------------------------------------------------------------------------------
open_prompt:	; from: cmd_search, cmd_run_mode, ask_address, open_prompt_text
	moveq	#8,d2                           ; the margin
	add.w	input_width(a6),d2              ; + the input field
	lea	text_esc_to_abort(pc),a2        ; "  ESC to abort   "

;------------------------------------------------------------------------------
; Open the prompt window d2 wide and d3 lines, titled a2, centred in the full screen window's area.
;------------------------------------------------------------------------------
open_prompt_window:	; from: open_message
	movem.w	full_layout+4(a6),d0-d1/d4      ; the full screen area
	add.w	full_layout(a6),d0
	add.w	full_layout(a6),d0
	sub.w	d2,d0                           ; less the width
	lsr.w	#1,d0                           ; centred
	sub.w	d3,d1
	mulu.w	split_height(a6),d1
	lea	window_prompt(a6),a3            ; the prompt window
	clr.b	$46(a3)                         ; no number
	bsr.w	open_window                     ; opened
	move.w	#$4,$16(a3)                     ; column 4
	move.w	$1a(a3),$18(a3)                 ; the first line
	rts

;------------------------------------------------------------------------------
; Open the prompt window with the text at a0 and a new line, the line in arguments empty.
;------------------------------------------------------------------------------
open_prompt_text:                               ; from: set_registers, window_breakpoint, window_lock, window_evaluate,
                                                ;   cmd_run_until, cmd_query_port, 11 more
	move.l	a0,-(sp)
	bsr.s	open_prompt                     ; opened
	movea.l	(sp)+,a0
	bsr.w	print_string                    ; the text
	bsr.w	new_line                        ; a new line
	lea	arguments(a6),a4                ; the line
	clr.b	(a4)                            ; empty
	moveq	#0,d4                           ; the cursor at its start
	rts

;------------------------------------------------------------------------------
; Open a 5 line prompt window with the message at a0 and the text at a1 below it, both centred.
;------------------------------------------------------------------------------
open_message:	; from: show_message, ask_yes_no_message
	move.l	a1,-(sp)
	move.l	a0,-(sp)
	movem.w	full_layout+4(a6),d0-d1/d4      ; the full screen area
	moveq	#30,d2                          ; 30 wide
	moveq	#5,d3                           ; 5 lines
	lea	text_space(pc),a2               ; " "
	bsr.s	open_prompt_window              ; opened
	movea.l	(sp)+,a0                        ; the message
	bsr.s	print_centred                   ; centred
	move.w	split_height(a6),d0
	add.w	d0,d0                           ; two lines
	add.w	d0,$18(a3)                      ; down
	movea.l	(sp)+,a0                        ; the text

;------------------------------------------------------------------------------
; Print the string at a0 centred in a 30 column window.
;------------------------------------------------------------------------------
print_centred:	; from: open_message
	move.l	a0,-(sp)
	movea.l	a0,a1
print_centred_length:
	tst.b	(a0)+                           ; find its end
	bne.s	print_centred_length
	lea	$1e(a1),a1                      ; 30
	suba.l	a0,a1                           ; less its length
	move.w	a1,d0
	lsr.w	#1,d0                           ; half
	move.w	d0,$16(a3)                      ; the column
	movea.l	(sp)+,a0
	bra.w	print_string                    ; printed

;------------------------------------------------------------------------------
; Show the message at a0 with "[Return]" and wait for Return or Esc.
;------------------------------------------------------------------------------
show_message:	; from: window_print, cmd_run, cmd_disassemble, set_breakpoint, show_tos_error
	move.l	a3,-(sp)
	lea	text_return(pc),a1              ; "[Return]"
	bsr.s	open_message                    ; shown
show_message_key:
	bsr.w	flush_get_key                   ; a key
	bmi.s	show_message_key
	cmp.b	#$1b,d1                         ; Esc?
	beq.s	show_message_done               ; yes
	cmp.b	#$d,d1                          ; Return?
	bne.s	show_message_key                ; no
show_message_done:
	bsr.w	close_prompt                    ; closed
	movea.l	(sp)+,a3
	rts

;------------------------------------------------------------------------------
; "TOS error: n" for the error d0.
;------------------------------------------------------------------------------
show_tos_error:	; from: load_file, show_cursor_here, cmd_directory, cmd_save_binary, load_program
	move.l	a4,-(sp)
	lea	tos_error_number(pc),a4         ; the number's place
	neg.l	d0                              ; made positive
	moveq	#0,d1
	move.w	d0,d1
	lea	put_char_a4(pc),a2              ; put into the text
	bsr.w	output_decimal                  ; in decimal
	clr.b	(a4)+                           ; ended
	movea.l	(sp)+,a4
	lea	text_tos_error(pc),a0           ; "TOS error: "
	bra.s	show_message                    ; shown

;------------------------------------------------------------------------------
; Put d1 at a4.
;------------------------------------------------------------------------------
put_char_a4:	; from: show_cursor_here, show_tos_error
	move.b	d1,(a4)+
	rts

;------------------------------------------------------------------------------
; Show the message at a0 with " Y/N?" and wait for Y, N, Esc or the key d2: Z set for Y.
;------------------------------------------------------------------------------
ask_yes_no_message:	; from: cmd_kill_breakpoints, cmd_reinstall
	lea	text_y_n(pc),a1                 ; " Y/N?"
	move.w	d2,-(sp)                        ; the other key
	bsr.w	open_message                    ; shown
ask_yes_no_message_key:
	bsr.w	get_key                         ; a key
	bmi.s	ask_yes_no_message_key
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$59,d1                         ; Y?
	beq.s	ask_yes_no_message_done
	cmp.b	#$4e,d1                         ; N?
	beq.s	ask_yes_no_message_done
	cmp.b	#$1b,d1                         ; Esc?
	beq.s	ask_yes_no_message_done
	cmp.b	1(sp),d1                        ; the other key?
	bne.s	ask_yes_no_message_key          ; no
ask_yes_no_message_done:
	move.w	d1,(sp)
	bsr.w	close_prompt                    ; closed
	move.w	(sp)+,d1
	cmp.b	#$59,d1                         ; Y?
	rts
monst_screen_set:	; from: monst_screen
	move.b	$ffff8201.w,prog_screen_now+1(a6) ; video base high, the program's screen address
	move.b	$ffff8203.w,prog_screen_now+2(a6) ; video base mid
	move.l	prog_screen_now(a6),d0
	cmp.l	screen(a6),d0                   ; MonST's own?
	beq.s	monst_screen_done               ; yes
	move.l	d0,prog_screen(a6)              ; the program's screen
	move.w	$ffff8240.w,prog_colour0(a6)    ; palette 0, its colours
	move.w	$ffff8242.w,prog_colour1(a6)
	move.b	$ffff8260.w,prog_mode(a6)       ; shift mode, its mode

;------------------------------------------------------------------------------
; Show MonST's screen: its colours, mode and address.
;------------------------------------------------------------------------------
monst_screen_show:	; from: cmd_resolution
	move.w	colour_background(a6),$ffff8240.w ; palette 0, the colours
	move.w	colour_text(a6),$ffff8242.w
	move.b	screen_mode(a6),$ffff8260.w     ; shift mode, the mode
	move.b	screen+1(a6),$ffff8201.w        ; video base high, the address
	move.b	screen+2(a6),$ffff8203.w        ; video base mid
monst_screen_done:	; from: ask_yes_no_message
	rts

;------------------------------------------------------------------------------
; MonST's screen on (the program's kept), after a vertical blank if the mode changes.
;------------------------------------------------------------------------------
monst_screen:	; from: print_wait, cmd_view, cmd_query_port, cmd_write_port, load_file, show_cursor_here, 6 more
	move.w	#$ffff,screen_timer(a6)         ; no screen timer
	bsr.s	wait_vbl_if_mode
	bra.s	monst_screen_set

;------------------------------------------------------------------------------
; The program's screen on, after a vertical blank if the mode changes.
;------------------------------------------------------------------------------
program_screen:	; from: rom_ranges, cmd_view, cmd_query_port, cmd_write_port, run_from_editor, program_state
	move.w	#$ffff,screen_timer(a6)         ; no screen timer
	bsr.s	wait_vbl_if_mode

;------------------------------------------------------------------------------
; Show the program's screen: its mode, address and colours.
;------------------------------------------------------------------------------
program_screen_show:	; from: timer_hook
	move.b	prog_mode(a6),$ffff8260.w       ; shift mode, its mode
	move.b	prog_screen+1(a6),$ffff8201.w   ; video base high, its address
	move.b	prog_screen+2(a6),$ffff8203.w   ; video base mid
	move.w	prog_colour0(a6),$ffff8240.w    ; palette 0, its colours
	move.w	prog_colour1(a6),$ffff8242.w
	rts

;------------------------------------------------------------------------------
; Wait for a vertical blank.
;------------------------------------------------------------------------------
wait_vbl:	; from: cmd_resolution, wait_vbl_if_mode, bell
	move.l	$466.w,d0                       ; _frclock, the frame count
wait_vbl_loop:
	cmp.l	$466.w,d0                       ; _frclock, changed?
	beq.s	wait_vbl_loop                   ; no
	rts

;------------------------------------------------------------------------------
; Wait for a vertical blank when the program's mode is not MonST's.
;------------------------------------------------------------------------------
wait_vbl_if_mode:	; from: monst_screen, program_screen
	move.b	prog_mode(a6),d0                ; the program's mode
	andi.b	#$3,d0
	cmp.b	screen_mode(a6),d0              ; MonST's?
	bne.s	wait_vbl                        ; no: wait
	rts

;------------------------------------------------------------------------------
; Before running: the program's screen at once, or with the screen timer after 40 ticks (MonST's screen until
; then, so a short run does not flicker).
;------------------------------------------------------------------------------
program_state:	; from: cmd_trace_rom, cmd_run, cmd_step, cmd_step_over, load_file, show_cursor_here, 5 more
	tst.b	screen_timer_on(a6)             ; the screen timer?
	beq.s	program_screen                  ; no: the program's screen now
	move.w	#$28,screen_timer(a6)           ; 40 timer ticks
	rts

;------------------------------------------------------------------------------
; Flash the background for a bad input.
;------------------------------------------------------------------------------
bell:                                           ; from: window_breakpoint, cmd_query_port, cmd_write_port, cmd_search,
                                                ;   read_three_values, cmd_save_binary, 3 more
	bsr.s	wait_vbl
	not.w	$ffff8240.w                     ; palette 0, inverted
	bsr.s	wait_vbl
	not.w	$ffff8240.w                     ; palette 0, back
	rts

;------------------------------------------------------------------------------
; Call the BIOS with its own register save area, so that a call made while the program is stopped does not
; upset the program's.
;------------------------------------------------------------------------------
bios:	; from: shift_keys_held, wait_key, check_escape, get_key, undo_reset, printer_ready, 1 more
	move.l	(sp)+,bios_caller(a6)           ; the return address
	move.l	$4a2.w,old_savptr(a6)           ; savptr, the save pointer
	lea	bios_save(a6),a0                ; MonST's save area
	move.l	a0,$4a2.w                       ; savptr
	trap	#13                             ; BIOS, the call
bios_return:	; from: xbios
	move.l	old_savptr(a6),$4a2.w           ; savptr, the save pointer back
	move.l	bios_caller(a6),-(sp)
	rts

;------------------------------------------------------------------------------
; Never called: the same for the XBIOS.
;------------------------------------------------------------------------------
xbios:
	move.l	(sp)+,bios_caller(a6)
	move.l	$4a2.w,old_savptr(a6)           ; savptr
	lea	bios_save(a6),a0
	move.l	a0,$4a2.w                       ; savptr
	trap	#14                             ; XBIOS
	bra.s	bios_return

;------------------------------------------------------------------------------
; Install MonST's exception handlers (the old vectors kept), the 200 Hz timer hook, the screen dump hook
; (Alternate-Help with both Shift keys stops the program) and the GEMDOS hook for the BDOS breakpoint.
;------------------------------------------------------------------------------
install_vectors:	; from: print_wait
	lea	exception_vectors(pc),a0        ; the vectors
	lea	old_vectors(a6),a3              ; the old ones kept here
install_vectors_loop:
	move.w	(a0)+,d0                        ; a vector number
	beq.s	install_vectors_hooks           ; the end
	pea	2(a0)                           ; the next entry
	adda.w	(a0),a0                         ; the handler
	move.l	a0,-(sp)                        ; Setexc(vector, handler)
	move.w	d0,-(sp)
	move.w	#$5,-(sp)
	trap	#13                             ; Setexc
	addq.l	#8,sp
	move.l	d0,(a3)+                        ; the old one kept
	movea.l	(sp)+,a0
	bra.s	install_vectors_loop
install_vectors_hooks:
	sf	break_request(a6)               ; no break asked for
	st	monst_running(a6)               ; MonST running
	move.w	#$ffff,bdos_breakpoint(a6)      ; no BDOS breakpoint
	move.w	#$ffff,screen_timer(a6)         ; no screen timer
	move.w	sr,-(sp)
	ori.w	#$700,sr                        ; interrupts off
	pea	timer_hook(pc)                  ; Setexc($45, timer hook): the 200 Hz timer
	move.w	#$45,-(sp)
	move.w	#$5,-(sp)
	trap	#13                             ; Setexc
	addq.l	#8,sp
	move.l	d0,old_timer(a6)                ; the old one
	move.w	(sp)+,sr
	move.l	$502.w,old_scr_dump(a6)         ; scr_dump, the screen dump vector
	lea	scr_dump_hook(pc),a0            ; the screen dump hook
	move.l	a0,$502.w                       ; scr_dump
	pea	gemdos_hook(pc)                 ; Setexc($21, GEMDOS hook)
	move.w	#$21,-(sp)
	move.w	#$5,-(sp)
	trap	#13                             ; Setexc
	move.l	d0,old_gemdos(a6)               ; the old one
	addq.l	#8,sp
	rts

;------------------------------------------------------------------------------
; Control-E: set MonST's handlers again (the old vectors are not taken again).
;------------------------------------------------------------------------------
reinstall_vectors:	; from: cmd_reinstall
	lea	exception_vectors(pc),a3        ; the vectors
reinstall_vectors_loop:
	move.w	(a3)+,d0                        ; a vector number
	beq.s	reinstall_vectors_hooks         ; the end
	pea	2(a3)
	adda.w	(a3),a3                         ; the handler
	move.l	a3,-(sp)                        ; Setexc(vector, handler)
	move.w	d0,-(sp)
	move.w	#$5,-(sp)
	trap	#13                             ; Setexc
	addq.l	#8,sp
	movea.l	(sp)+,a3
	bra.s	reinstall_vectors_loop
reinstall_vectors_hooks:
	lea	scr_dump_hook(pc),a0            ; the screen dump hook
	move.l	a0,$502.w                       ; scr_dump
	pea	gemdos_hook(pc)                 ; Setexc($21, GEMDOS hook)
	move.w	#$21,-(sp)
	move.w	#$5,-(sp)
	trap	#13                             ; Setexc
	addq.l	#8,sp
	rts

;------------------------------------------------------------------------------
; Put the old vectors back.
;------------------------------------------------------------------------------
restore_vectors:	; from: rom_ranges
	lea	exception_vectors(pc),a0        ; the vectors
	lea	old_vectors(a6),a3              ; the old ones
restore_vectors_loop:
	move.w	(a0)+,d0                        ; a vector number
	beq.s	restore_vectors_hooks           ; the end
	pea	2(a0)
	move.l	(a3)+,-(sp)                     ; the old one
	move.w	d0,-(sp)                        ; Setexc(vector, old)
	move.w	#$5,-(sp)
	trap	#13                             ; Setexc
	addq.l	#8,sp
	movea.l	(sp)+,a0
	bra.s	restore_vectors_loop
restore_vectors_hooks:
	move.l	old_timer(a6),-(sp)             ; the old timer handler
	move.w	#$45,-(sp)
	move.w	#$5,-(sp)
	trap	#13                             ; Setexc
	addq.l	#8,sp
	move.l	old_scr_dump(a6),$502.w         ; scr_dump, the old screen dump vector
	move.l	old_gemdos(a6),-(sp)            ; the old GEMDOS handler
	move.w	#$21,-(sp)
	move.w	#$5,-(sp)
	trap	#13                             ; Setexc
	addq.l	#8,sp
	rts

;------------------------------------------------------------------------------
; The exceptions MonST handles: a vector number and the offset of its handler from the offset word; bus and
; address errors, illegal (breakpoints), divide, CHK, TRAPV, privilege, trace, the bad interrupts, the TRAPs
; not used by TOS, and etv_term.
;------------------------------------------------------------------------------
exception_vectors:	; from: install_vectors, reinstall_vectors, restore_vectors
	dc.w	$2
	dc.w	exc_bus_error-*
	dc.w	$3
	dc.w	exc_address_error-*
	dc.w	$4
	dc.w	exc_illegal-*
	dc.w	$5
	dc.w	exc_divide-*
	dc.w	$6
	dc.w	exc_chk-*
	dc.w	$7
	dc.w	exc_trapv-*
	dc.w	$8
	dc.w	exc_privilege-*
	dc.w	$9
	dc.w	exc_trace-*
	dc.w	$f
	dc.w	exc_bad_interrupt-*
	dc.w	$18
	dc.w	exc_bad_interrupt-*
	dc.w	$20
	dc.w	exc_bad_trap-*
	dc.w	$23
	dc.w	exc_bad_trap-*
	dc.w	$24
	dc.w	exc_bad_trap-*
	dc.w	$25
	dc.w	exc_bad_trap-*
	dc.w	$26
	dc.w	exc_bad_trap-*
	dc.w	$27
	dc.w	exc_bad_trap-*
	dc.w	$28
	dc.w	exc_bad_trap-*
	dc.w	$29
	dc.w	exc_bad_trap-*
	dc.w	$2a
	dc.w	exc_bad_trap-*
	dc.w	$2b
	dc.w	exc_bad_trap-*
	dc.w	$2c
	dc.w	exc_bad_trap-*
	dc.w	$2f
	dc.w	exc_bad_trap-*
	dc.w	$102
	dc.w	term_handler-*
	dc.w	0

;------------------------------------------------------------------------------
; The bus and address error handlers: the registers and the long frame saved, the PC moved back to the
; instruction (its opcode looked for in the 5 words before), then "Bus error" or "Address error".
;------------------------------------------------------------------------------
exc_bus_error:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#16,d0                          ; "Bus error"
	bra.s	exc_long_frame
exc_address_error:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#15,d0                          ; "Address error"
exc_long_frame:
	move.l	a6,-(sp)
	movea.l	vars_address(pc),a6             ; MonST's variables
	st	monst_running(a6)               ; MonST running
	movem.l	d1-d7/a0-a5,reg_d+4(a6)         ; the program's registers
	move.l	(sp)+,reg_a+24(a6)              ; a6
	move.l	(sp)+,reg_d(a6)                 ; d0
	addq.l	#6,sp                           ; past the access address and function code
	move.w	(sp)+,d3                        ; the instruction register
	move.w	(sp)+,reg_sr+2(a6)              ; the SR
	move.l	(sp)+,reg_pc(a6)                ; the PC
	move.l	sp,reg_ssp(a6)                  ; the supervisor stack
	lea	monst_stack(a6),sp              ; MonST's stack
	move.w	d0,-(sp)                        ; the message
	btst	#$0,reg_pc+3(a6)                ; the PC odd?
	bne.s	exc_long_frame_done             ; yes
	movea.l	reg_pc(a6),a2                   ; the PC
	lea	-$a(a2),a2                      ; 10 bytes back
	bsr.w	check_address                   ; readable?
	bne.s	exc_long_frame_done             ; no
	lea	$a(a2),a2
	bsr.w	check_address                   ; the PC readable?
	bne.s	exc_long_frame_done             ; no
	addq.l	#2,a2
	moveq	#4,d0                           ; 5 words
exc_find_opcode:
	cmp.w	-(a2),d3                        ; the opcode?
	dbeq	d0,exc_find_opcode
	bne.s	exc_long_frame_done             ; not found
	move.l	a2,reg_pc(a6)                   ; the PC at it
exc_long_frame_done:
	move.w	(sp)+,d0                        ; the message
	bra.w	exc_common

;------------------------------------------------------------------------------
; The other handlers: each its message number (10 for ILLEGAL, which is how breakpoints stop).
;------------------------------------------------------------------------------
exc_illegal:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#10,d0                          ; "Illegal exception"
	bra.s	exc_short_frame
exc_divide:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#3,d0                           ; "Divide by zero"
	bra.s	exc_short_frame
exc_chk:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#4,d0                           ; "CHK exception"
	bra.s	exc_short_frame
exc_trapv:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#5,d0                           ; "TRAPV exception"
	bra.s	exc_short_frame
exc_privilege:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#6,d0                           ; "Privilege violation"
	bra.s	exc_short_frame
exc_trace:	; from: exception_vectors, gemdos_hook
	move.l	d0,-(sp)
	moveq	#7,d0                           ; "Trace"
	bra.s	exc_short_frame
exc_bad_interrupt:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#8,d0                           ; "Bad interrupt"
	bra.s	exc_short_frame
exc_bad_trap:	; from: exception_vectors
	move.l	d0,-(sp)
	moveq	#9,d0                           ; "Invalid TRAP"
	subq.l	#2,6(sp)                        ; the PC back to the TRAP
exc_short_frame:
	move.l	a6,-(sp)
	movea.l	vars_address(pc),a6             ; MonST's variables
	st	monst_running(a6)               ; MonST running
	movem.l	d1-d7/a0-a5,reg_d+4(a6)         ; the program's registers
	move.l	(sp)+,reg_a+24(a6)              ; a6
	move.l	(sp)+,reg_d(a6)                 ; d0
	move.w	(sp)+,reg_sr+2(a6)              ; the SR
	move.l	(sp)+,reg_pc(a6)                ; the PC
	move.l	sp,reg_ssp(a6)                  ; the supervisor stack
	lea	monst_stack(a6),sp              ; MonST's stack
exc_common:	; from: exc_bus_error
	move.l	usp,a0                          ; the user stack
	move.l	a0,reg_usp(a6)
	move.l	current_window(a6),-(sp)        ; the current window kept
	move.w	d0,d4                           ; the message
	movea.l	reg_pc(a6),a1                   ; the PC
	cmp.b	#$a,d0                          ; ILLEGAL?
	beq.w	exc_breakpoint                  ; yes: a breakpoint perhaps
	cmp.b	#$7,d0                          ; trace?
	beq.s	exc_trace_step                  ; yes

;------------------------------------------------------------------------------
; The program stops: interrupts on, the windows redrawn and the message d4 in the title window.
;------------------------------------------------------------------------------
stop_program:	; from: exc_trace_step, exc_breakpoint
	andi.w	#$f8ff,sr                       ; interrupts on
	ori.w	#$200,sr
	clr.l	stepped_breakpoint(a6)          ; no breakpoint being stepped over
	clr.b	run_mode(a6)                    ; no run mode
	movea.l	reg_pc(a6),a1
	move.w	d4,-(sp)
	bsr.w	follow_registers                ; the windows locked to registers
	bsr.w	monst_screen                    ; MonST's screen
	bsr.w	redraw_windows                  ; redrawn
	lea	window_title(a6),a3             ; the title window
	bsr.w	clear_window                    ; cleared
	move.w	(sp)+,d1                        ; the message
	bsr.w	print_message                   ; printed
	st	message_shown(a6)
	move.l	(sp)+,current_window(a6)        ; the current window back
	bra.w	command_loop                    ; the command loop

;------------------------------------------------------------------------------
; A trace exception: the step is saved in the history; a breakpoint stepped over is put back; in a run mode
; (slow, until or a count) the program goes on unless it should stop.
;------------------------------------------------------------------------------
exc_trace_step:	; from: exc_illegal
	bsr.w	save_history                    ; the history
	tst.l	stepped_breakpoint(a6)
	bne.w	restore_stepped_breakpoint
run_mode_step:
	move.b	run_mode(a6),d0                 ; the run mode
	beq.s	stop_program                    ; none: stop
	lea	term_handler(pc),a0             ; the end of a terminate?
	cmpa.l	reg_pc(a6),a0
	beq.s	run_mode_terminated             ; yes
	movea.l	prog_screen(a6),a0              ; the program's screen
	eori.b	#$18,$140(a0)                   ; a mark flashed on it
	cmp.b	#$2,d0                          ; until?
	beq.s	run_mode_until                  ; yes
	cmp.b	#$3,d0                          ; a count?
	beq.w	run_mode_count                  ; yes
run_mode_watch:
	tst.b	watch(a6)                       ; watch?
	beq.s	run_mode_continue               ; no
	bsr.w	shift_keys_held                 ; both Shift keys?
	beq.s	run_mode_stop                   ; yes: stop
	movea.l	prog_screen(a6),a0
	eori.b	#$18,$140(a0)                   ; the mark back
	andi.w	#$f8ff,sr                       ; interrupts on
	ori.w	#$200,sr
	bsr.w	follow_registers                ; the windows
	bsr.w	monst_screen                    ; MonST's screen
	bsr.w	redraw_windows                  ; redrawn
	bsr.w	program_state                   ; and the program's again
run_mode_continue:
	movea.l	prog_screen(a6),a0
	eori.b	#$18,$140(a0)                   ; the mark
	tst.b	follow_traps(a6)                ; follow traps?
	beq.w	resume                          ; no: go
	move.b	reg_sr+2(a6),d0                 ; the interrupt mask
	andi.b	#$7,d0
	cmp.b	#$7,d0                          ; 7: in a handler
	beq.s	run_mode_untraced               ; yes: without tracing
	bset	#$7,reg_sr+2(a6)                ; trace on
	bra.w	resume                          ; go
run_mode_terminated:
	clr.b	run_mode(a6)                    ; no run mode
run_mode_untraced:
	bclr	#$7,reg_sr+2(a6)                ; no trace
	bra.w	resume                          ; go
run_mode_until:
	lea	until_condition(a6),a4          ; the condition
	bsr.w	evaluate                        ; worked out
	bne.s	run_mode_watch                  ; bad: on
	tst.b	d1
	bne.s	run_mode_watch
	tst.l	d2                              ; true?
	beq.s	run_mode_watch                  ; no: on
run_mode_stop:
	movea.l	prog_screen(a6),a0
	eori.b	#$18,$140(a0)                   ; the mark back
	moveq	#11,d4                          ; "Breakpoint"
	bra.w	stop_program                    ; stop
run_mode_count:
	subq.l	#1,run_count(a6)                ; one less
	bne.w	run_mode_watch                  ; not yet
	bra.s	run_mode_stop                   ; stop
restore_stepped_breakpoint:
	movea.l	stepped_breakpoint(a6),a0       ; the breakpoint stepped over
	clr.l	stepped_breakpoint(a6)
	movea.l	(a0),a1                         ; its address
	move.w	#$4afc,(a1)                     ; ILLEGAL again
	move.w	reg_sr+2(a6),d0                 ; the SR
	andi.w	#$7fff,d0
	or.w	stepped_trace(a6),d0            ; the trace bit as it was
	move.w	d0,reg_sr+2(a6)
	bpl.w	go_trace                        ; no trace: go
	tst.b	run_mode(a6)                    ; a run mode?
	beq.w	stop_program                    ; no: stop
	bra.w	run_mode_step

;------------------------------------------------------------------------------
; ILLEGAL: the end of an interpreted instruction, the temporary breakpoint after a TRAP, or a breakpoint: a
; plain one stops when its count runs out, a counter counts, a permanent one stops, a conditional one stops when
; its condition is true.  Any other ILLEGAL is "Illegal exception".
;------------------------------------------------------------------------------
exc_breakpoint:	; from: exc_illegal
	pea	interpret_buffer+10(a6)         ; the interpret buffer's ILLEGAL
	cmpa.l	(sp)+,a1                        ; there?
	beq.s	exc_interpret_done              ; yes
	cmpa.l	temp_break(a6),a1               ; the temporary breakpoint?
	beq.s	exc_temporary_break             ; yes
	st	temp_break+3(a6)                ; the temporary one off
	bsr.w	find_breakpoint                 ; a breakpoint here?
	bne.s	exc_breakpoint_illegal          ; no: illegal
	movem.l	a0-a1,-(sp)
	bsr.w	save_history                    ; the history
	movem.l	(sp)+,a0-a1
	move.w	6(a0),d0                        ; its type
	cmp.w	#$3,d0                          ; permanent?
	beq.s	exc_breakpoint_stop             ; yes: stop
	cmp.w	#$1,d0                          ; plain?
	beq.s	exc_breakpoint_plain
	cmp.w	#$2,d0                          ; a counter?
	beq.s	exc_breakpoint_counter
	lea	$c(a0),a4                       ; conditional: its condition
	movem.l	a0-a1,-(sp)
	bsr.w	evaluate                        ; worked out
	movem.l	(sp)+,a0-a1
	bne.s	go                              ; bad: on
	tst.b	d1
	bne.s	go
	tst.l	d2                              ; true?
	beq.s	go                              ; no: on
	bra.s	exc_breakpoint_remove
exc_breakpoint_counter:
	addq.l	#1,8(a0)                        ; counted
	bra.s	go                              ; on
exc_breakpoint_plain:
	subq.l	#1,8(a0)                        ; one less
	beq.s	exc_breakpoint_remove           ; run out: stop
	bra.s	go
exc_breakpoint_remove:
	move.w	4(a0),(a1)                      ; the word back
	clr.w	6(a0)                           ; gone
exc_breakpoint_stop:
	moveq	#11,d4                          ; "Breakpoint"
	bra.w	stop_program                    ; stop
exc_breakpoint_illegal:
	moveq	#10,d4                          ; "Illegal exception"
	bra.w	stop_program                    ; stop
exc_interpret_done:
	move.l	interpret_return(a6),reg_pc(a6) ; the PC after the instruction
	bsr.w	save_history                    ; the history
	moveq	#7,d4                           ; "Trace"
	bra.w	stop_program                    ; stop
exc_temporary_break:
	move.w	temp_break_word(a6),(a1)        ; the word back
	moveq	#-42,d0                         ; no temporary breakpoint
	move.l	d0,temp_break(a6)
	movea.l	temp_break_entry(a6),a0         ; the breakpoint before it
	movea.l	(a0),a1                         ; its address
	move.w	#$4afc,(a1)                     ; ILLEGAL again
	bsr.w	save_history                    ; the history

;------------------------------------------------------------------------------
; Go on with the program: a breakpoint at the PC is stepped over first (a TRAP with a temporary breakpoint
; after it); with tracing, a trap or Line-A is run whole or followed into, by the preference.
;------------------------------------------------------------------------------
go:	; from: cmd_run, cmd_step, cmd_step_over, exc_breakpoint
	btst	#$0,reg_pc+3(a6)                ; the PC odd?
	bne.s	go_trace                        ; yes
	movea.l	reg_pc(a6),a2                   ; the PC
	bsr.w	check_address                   ; readable?
	bne.s	go_trace                        ; no
	movea.l	a2,a1
	bsr.w	find_breakpoint                 ; a breakpoint at it?
	beq.w	go_over_breakpoint              ; yes
go_trace:	; from: cmd_step, exc_trace_step, resume
	tst.w	reg_sr+2(a6)                    ; tracing?
	bpl.s	resume                          ; no
	btst	#$0,reg_pc+3(a6)                ; the PC odd?
	bne.s	resume                          ; yes
	movea.l	reg_pc(a6),a2
	bsr.w	check_address                   ; readable?
	bne.s	resume                          ; no
	move.w	(a2),d0                         ; the instruction
	andi.w	#$fff0,d0
	tst.b	follow_traps(a6)                ; follow traps?
	beq.s	go_trace_whole                  ; no
	cmp.w	#$4e40,d0                       ; a TRAP: traced into
	beq.s	resume
	andi.w	#$f000,d0
	cmp.w	#$a000,d0                       ; Line-A?
	bne.s	resume                          ; no
	movea.l	reg_ssp(a6),a0                  ; into the Line-A handler: a frame
	move.l	a2,-(a0)                        ; the PC
	move.w	reg_sr+2(a6),-(a0)              ; the SR
	bset	#$5,reg_sr+2(a6)                ; supervisor mode
	move.l	$28.w,reg_pc(a6)                ; the Line-A handler
	move.l	a0,reg_ssp(a6)
	bra.s	resume
go_trace_whole:
	cmp.w	#$4e40,d0                       ; a TRAP?
	beq.w	interpret                       ; yes: run it whole
	andi.w	#$f000,d0
	cmp.w	#$a000,d0                       ; Line-A?
	beq.w	interpret                       ; yes: run it whole

;------------------------------------------------------------------------------
; Back into the program with its registers: an RTE to its PC and SR.
;------------------------------------------------------------------------------
resume:	; from: previous_instruction, interpret, exc_trace_step, go, run_with_mode
	sf	monst_running(a6)               ; the program running
	movea.l	reg_ssp(a6),sp                  ; its supervisor stack
	movea.l	reg_usp(a6),a0                  ; its user stack
	move.l	a0,usp
	move.l	reg_pc(a6),-(sp)                ; its PC
	move.w	reg_sr+2(a6),-(sp)              ; its SR
	movem.l	reg_d(a6),d0-d7/a0-a6           ; its registers
	rte
go_over_breakpoint:	; from: go
	move.w	4(a0),d0                        ; the word it replaced
	andi.w	#$fff0,d0
	cmp.w	#$4e40,d0                       ; a TRAP?
	beq.s	go_over_trap                    ; yes
	move.w	reg_sr+2(a6),d0                 ; the trace bit
	andi.w	#$8000,d0
	move.w	d0,stepped_trace(a6)            ; kept
	move.l	a0,stepped_breakpoint(a6)       ; the breakpoint to put back
	move.w	4(a0),(a1)                      ; the word back
	bset	#$7,reg_sr+2(a6)                ; one step traced
	bra.w	go_trace
go_over_trap:
	move.w	4(a0),(a1)+                     ; the word back, past it
	move.l	a0,temp_break_entry(a6)         ; the breakpoint
	bsr.w	set_temporary_break             ; a temporary one after the TRAP
	bclr	#$7,reg_sr+2(a6)                ; no trace
	bra.s	resume

;------------------------------------------------------------------------------
; etv_term: the trace bit off while a program ends.
;------------------------------------------------------------------------------
term_handler:	; from: exception_vectors, exc_trace_step
	andi.w	#$7fff,sr
	rts

;------------------------------------------------------------------------------
; The 200 Hz timer: a break asked for traces the program (unless MonST or the code before it is running), and
; the screen timer counts down to show the program's screen; then the old handler.
;------------------------------------------------------------------------------
timer_hook:	; from: install_vectors
	clr.l	-(sp)                           ; the old handler's place
	move.l	d0,-(sp)
	move.l	a6,-(sp)
	movea.l	vars_address(pc),a6             ; MonST's variables
	tst.b	break_request(a6)               ; a break asked for?
	beq.s	timer_hook_screen               ; no
	move.l	a0,-(sp)
	lea	bss_end(pc),a0                  ; MonST's end
	cmpa.l	$12(sp),a0                      ; the interrupted PC past it?
	bcs.s	timer_hook_break                ; yes: the program
	lea	start(pc),a0                    ; MonST's start
	cmpa.l	$12(sp),a0                      ; past it?
	bcs.s	timer_hook_break                ; yes: in MonST
	movea.l	(sp)+,a0
	sf	break_request(a6)               ; the break taken
	tst.b	run_mode(a6)                    ; a run mode?
	beq.s	timer_hook_screen               ; no
	clr.b	run_mode(a6)                    ; ended
	bra.s	timer_hook_screen
timer_hook_break:
	movea.l	(sp)+,a0
	sf	break_request(a6)               ; the break taken
	tst.b	run_mode(a6)                    ; a run mode?
	beq.s	timer_hook_trace                ; no
	clr.b	run_mode(a6)                    ; ended
	bra.s	timer_hook_screen
timer_hook_trace:
	ori.w	#$8000,$c(sp)                   ; trace the program
timer_hook_screen:
	move.w	screen_timer(a6),d0             ; the screen timer
	bmi.s	timer_hook_done                 ; off
	subq.w	#1,d0                           ; counted down
	bne.s	timer_hook_count                ; not yet
	bsr.w	program_screen_show             ; the program's screen
	moveq	#-1,d0                          ; off
timer_hook_count:
	move.w	d0,screen_timer(a6)
timer_hook_done:
	move.l	old_timer(a6),8(sp)             ; to the old handler
	movea.l	(sp)+,a6
	move.l	(sp)+,d0
	rts

;------------------------------------------------------------------------------
; Run in the mode d3 (1 slow, 2 until, 3 a count), tracing.
;------------------------------------------------------------------------------
run_with_mode:	; from: cmd_run_mode
	bsr.w	check_runnable                  ; can it run?
	bsr.w	program_state                   ; the program's state
	move.b	d3,run_mode(a6)                 ; the run mode
	bset	#$7,reg_sr+2(a6)                ; trace on
	bra.w	resume                          ; go

;------------------------------------------------------------------------------
; The screen dump vector (Alt-Help): with both Shift keys held, ask for a break; else the old screen dump.
;------------------------------------------------------------------------------
scr_dump_hook:	; from: install_vectors, reinstall_vectors
	movem.l	d0-d2/a1-a2,-(sp)
	movea.l	vars_address(pc),a0             ; MonST's variables
	move.l	#$bffff,-(sp)                   ; Kbshift(-1)
	move.l	$4a2.w,$5c6(a0)                 ; savptr, the save pointer kept
	lea	$5fa(a0),a0
	move.l	a0,$4a2.w                       ; savptr
	trap	#13                             ; BIOS
	addq.l	#4,sp
	movea.l	vars_address(pc),a0
	move.l	$5c6(a0),$4a2.w                 ; savptr, the save pointer back
	andi.b	#$3,d0                          ; both Shift keys?
	movem.l	(sp)+,d0-d2/a1-a2
	beq.s	scr_dump_hook_old               ; no
	st	$16b(a0)                        ; a break asked for
	rts
scr_dump_hook_old:
	movea.l	$ea(a0),a0                      ; the old screen dump
	jmp	(a0)

;------------------------------------------------------------------------------
; GEMDOS: with a BDOS breakpoint set, stop at a call with its number (the PC back on the TRAP), as a trace.
;------------------------------------------------------------------------------
gemdos_hook:	; from: install_vectors, reinstall_vectors
	clr.l	-(sp)                           ; the old handler's place
	movem.l	d0/a0,-(sp)
	movea.l	vars_address(pc),a0             ; MonST's variables
	move.w	$174(a0),d0                     ; the BDOS breakpoint
	bmi.s	gemdos_hook_old                 ; none
	tst.b	$16c(a0)                        ; from MonST?
	bne.s	gemdos_hook_old                 ; yes
	btst	#$5,$c(sp)                      ; from supervisor mode?
	bne.s	gemdos_hook_super               ; yes
	move.l	a0,-(sp)
	move.l	usp,a0                          ; the user stack
	cmp.w	(a0),d0                         ; the function number?
	movea.l	(sp)+,a0
	bne.s	gemdos_hook_old                 ; no
gemdos_hook_stop:
	subq.l	#2,$e(sp)                       ; the PC back on the TRAP
	movea.l	vars_address(pc),a0
	move.w	#$ffff,$174(a0)                 ; the BDOS breakpoint off
	clr.b	$170(a0)                        ; no run mode
	movem.l	(sp)+,d0/a0
	addq.l	#4,sp
	bra.w	exc_trace                       ; stop as a trace
gemdos_hook_super:
	cmp.w	$12(sp),d0                      ; the function number on the supervisor stack?
	beq.s	gemdos_hook_stop                ; yes
gemdos_hook_old:
	move.l	$e6(a0),8(sp)                   ; to the old handler
	movem.l	(sp)+,d0/a0
	rts
vars_address:	; from: settings, exc_bus_error, exc_illegal, timer_hook, scr_dump_hook
	dc.l	$00414d50                       ; the variables' address, set at the start for the handlers

	section	bss
bss_end:

	end
