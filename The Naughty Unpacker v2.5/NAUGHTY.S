; NAUGHTY.PRG  -  The Naughty Unpacker v2.5, ST NEWS version  (c) 1992 Marinos Yannikos, released 08.10.1992
; Devpac source of the program, disassembled by Darren Birks, 10th November 2026.
; Text 18382 bytes, data 1428 bytes, bss 39562 bytes.
;
; Disassembled from NAUGHTY.PRG as it was found: 20124 bytes, the program already unpacked.  The original
; was distributed packed, 13320 bytes long (the setup's SAVE checks for that length, see "the setup").
;
; This source rebuilds NAUGHTY.PRG byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o NAUGHTY.PRG NAUGHTY.S
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; A GEM program that turns a packed program file back into the plain program.  The main dialog has
; UNPACK, INFO and EXIT; clicking the title box opens the setup (show statistics, save and restore
; the screen).  UNPACK asks for a program, unpacks it, shows the packed and unpacked sizes, the
; compression ratio and the time taken when the setup says so, and asks for a name to save it under.
;
; Its info dialog names the packers it was tested with: Pack-Ice, Pack-Fire, LSD, Happy, Atomik, JAM,
; Pompey, Automation, the JEK packers, Thunder and BAPACK.  But it has no depack routine for any of
; them: it lets the packed program unpack itself and catches the result.
;
; It is written in Turbo C and linked with its library.  Only run_packed_program and
; catch_unpacked_program are assembly: they patch and run the packed program, and are entered from
; it.  Most of the text is the Turbo C library: printf, the 80-bit floating point
; package (which uses a 68881 through an SFP004 card when there is one), strings, and the GEMDOS,
; AES and VDI bindings.
;
;=======================================================================
; HOW IT UNPACKS
;=======================================================================
; load_and_unpack:
;  - reads the program header ($601a; a symbol table is refused) and makes sure the memory is there;
;  - makes a basepage with Pexec 5 and loads the text and data into it as TOS would, clearing the bss;
;  - a packed program is normally position-independent and has no relocation table.  If this one has
;    one, is_known_packer looks for the marks of packers whose depacker is relocated by TOS ('POPI'
;    at the end of the file, 'ATOM' at +$256, 'HART' at +$e, three code sequences); for anything else
;    it asks whether to go on, then relocates the program itself (relocate_loaded_program).
;
; run_packed_program, with the program loaded but not started:
;  1. Screen calls.  In the first $800 bytes every long $7fd00 (the screen of a 512K ST) and every
;     Physbase or Logbase call (move.w #2/#3,-(sp) / trap #14) is changed to give packer_screen
;     instead (screen_call_patch), so pictures and effects drawn while depacking go to a buffer.
;  2. The relocation loop.  Every depacker ends by relocating the unpacked program, so the same $800
;     bytes are searched for the start of that loop: move.l (an),dn or tst.l (an) followed by a short
;     beq (at most $30 on), or add.l d2,0(a1,d0.l).  The two words there are overwritten with
;     jmp catch_unpacked_program.
;  3. The program is started with Pexec 4.
;
; catch_unpacked_program, entered from the packed program in place of its relocation:
;  - the unpacked program is the program header ($601a) that one of the 15 saved registers points at,
;    in the packed program's memory below 4 MB, with text + data under 2 MB.  When several do, the
;    longest is taken.  A 'BRAS' program (bra.s *+$2c then 'BRAS') keeps no header: one is rebuilt in
;    front of its text from the basepage that a5 points at;
;  - the end of the unpacked program is found by walking its relocation table to its 0 byte;
;  - unpacked_header and unpacked_end are set and Pterm0 ends the packed program.  Pexec returns in
;    run_packed_program, which takes back its own registers.
; The unpacked program, header to the end of its relocation table, is written as it is.
;
;=======================================================================
; HOW TO READ THIS FILE
;=======================================================================
; - Every routine, branch target and variable has been named from its behaviour.  The resource's
;   strings are named after their dialog and their text (main_unpack_text, info_ted_title).
; - "; from: a, b" after a label lists the routines (or tables) that refer to it.  It is derived from
;   the original program and is documentation only; the assembler ignores it.  Labels referred to
;   only from inside their own routine carry no note.
; - Comments on trap calls give the GEMDOS, BIOS or XBIOS function.
; - Turbo C passes the first integer arguments in d0-d2 and the first pointers in a0-a1, the rest on
;   the stack, and returns in d0 or a0.  The C routines keep d3-d7 and a2-a6.
; - Some routines reach their variables through a base register: those operands are written as
;   label-base(an), e.g. alert_symbol_table-str_file(a3) with a3 = str_file.
; - Floating point library names: plain C names (log, fabs, ecvt) take their arguments on the stack;
;   ext_ names take pointers to 10-byte long doubles and use the 68881 when fpu_flags bit 7 is set;
;   soft_ names are the software paths; fp_ names are the package's shared parts.
;
;=======================================================================
; THE DIALOGS
;=======================================================================
; Four object trees are compiled into the text (tree_main, tree_info, tree_progress, tree_setup),
; with their TEDINFOs and strings; init_gem fixes all 51 objects with rsrc_obfix and centres the
; trees.  The exit objects the code tests:
;   tree_main      3 UNPACK, 4 INFO, 5 EXIT, 11 the title box (opens the setup)
;   tree_info      7 BACK
;   tree_progress  1 'File: ...', 2 the status ('reading...', 'checking...', 'unpacking...',
;                  'writing...'), 3 'Size: ... bytes' - their strings are rewritten by show_reading,
;                  show_checking, show_unpacking and show_writing
;   tree_setup     4 the save-screen check box, 6 the statistics check box, 7 BACK, 8 SAVE
;
;=======================================================================
; THE SETUP
;=======================================================================
; SAVE writes the ob_state low byte of the two check boxes into NAUGHTY.PRG at file offsets $1e
; (save screen) and $1f (statistics).  It refuses any file that is not 13320 bytes long: those two
; bytes are only meaningful in the packed original.  The start-up code copies the bytes at 8(sp) and
; 9(sp) into the check boxes; the packed original's depacker probably passes the two setup bytes
; there.  In this unpacked copy they are whatever is on the stack.
;
;=======================================================================
; MEMORY
;=======================================================================
; text   start-up, the resource, the unpacker ($0b68-$1983), the Turbo C library
; data   Turbo C and unpacker variables, the progress texts, the alerts, the library's variables
; bss    basepage pointers, the GEM variables, the file names and paths, screen_buffer,
;        file_header, the library's buffers and the AES and VDI arrays
; Variables used by run_packed_program and catch_unpacked_program while the packed program runs are
; kept in the text (best_length, caught_registers, saved_registers), so they are reached PC-relative.

G_BOX	equ	20                              ; AES object types
G_TEXT	equ	21
G_BOXTEXT	equ	22
G_IMAGE	equ	23
G_USERDEF	equ	24
G_IBOX	equ	25
G_BUTTON	equ	26
G_BOXCHAR	equ	27
G_STRING	equ	28
G_FTEXT	equ	29
G_FBOXTEXT	equ	30
G_ICON	equ	31
G_TITLE	equ	32
SELECTABLE	equ	$1                      ; object flags
DEFAULT	equ	$2
EXIT	equ	$4
EDITABLE	equ	$8
RBUTTON	equ	$10
LASTOB	equ	$20
TOUCHEXIT	equ	$40
HIDETREE	equ	$80
INDIRECT	equ	$100
SELECTED	equ	$1                      ; object states
CROSSED	equ	$2
CHECKED	equ	$4
DISABLED	equ	$8
OUTLINED	equ	$10
SHADOWED	equ	$20

	section	text

;------------------------------------------------------------------------------
; Turbo C start-up, changed for the setup: the two bytes the setup's SAVE writes into the program file
; (offsets $1e and $1f) are probably passed on the stack by the packed program's depacker, and are
; copied into the setup dialog's two check boxes.  Then the stack goes at the end of the program's
; memory, the program Mshrinks to text + data + bss and runs main.
;------------------------------------------------------------------------------
start:
	move.b	8(sp),tree_setup+155            ; show_statistics check box state
	move.b	9(sp),tree_setup+107            ; save_screen check box state
	move.w	#$1,is_program                  ; is_program
	movea.l	4(sp),a3                        ; the basepage
	move.l	a3,basepage                     ; kept in basepage
	movea.l	$c(a3),a0                       ; text +
	adda.l	$14(a3),a0                      ; data +
	adda.l	$1c(a3),a0                      ; bss +
	adda.w	#$100,a0                        ; basepage
	move.l	a0,program_size                 ; program_size: what the program needs
	move.l	a3,d0                           ; basepage + program_size:
	add.l	a0,d0                           ; the end of the program memory
	andi.b	#$fc,d0                         ; the stack at the end, word aligned
	movea.l	d0,sp                           ; the stack starts there
	subi.l	#$f00,d0                        ; the stack may go down 3840 bytes
	move.l	d0,stack_limit                  ; stack_limit
	move.l	a0,-(sp)                        ; new size
	move.l	a3,-(sp)                        ; block: the basepage
	move.w	#$0,-(sp)                       ; reserved
	move.w	#$4a,-(sp)                      ; Mshrink
	trap	#1                              ; Mshrink
	lea	$c(sp),sp                       ; drop the parameters
	bsr.w	main                            ; main

;------------------------------------------------------------------------------
; exit(d0 = status): calls the two exit routines if they are set, closes the files and ends the
; program with Pterm.
;------------------------------------------------------------------------------
exit:	; from: quit_with_error, select_file, init_gem, main
	move.w	d0,-(sp)                        ; keep the exit status
	move.l	exit_routine(pc),d0             ; exit_routine
	beq.s	exit_cleanup                    ; exit routine set?
	movea.l	d0,a0                           ; call it
	jsr	(a0)
exit_cleanup:
	move.l	cleanup_routine(pc),d0          ; cleanup_routine
	beq.s	exit_close_files                ; cleanup routine set?
	movea.l	d0,a0                           ; call it
	jsr	(a0)
exit_close_files:
	bsr.w	free_block_lists                ; close the files
	move.w	#$4c,-(sp)                      ; Pterm with the status on the stack
	trap	#1                              ; Pterm

;------------------------------------------------------------------------------
; The resource, compiled in: the main dialog, the info dialog, the progress box and the setup
; dialog, their TEDINFOs and strings.
;------------------------------------------------------------------------------
tree_main:	; from: init_gem
	dc.w	-1,1,13,G_BOX,0,0                       ; 0
	dc.l	$00fe1100
	dc.w	$0000,$0000,$0427,$0412
	dc.w	2,-1,-1,G_STRING,0,0                    ; 1: '(c)1992 by Marinos Yannikos'
	dc.l	main_author_text
	dc.w	$0406,$0405,$001b,$0001
	dc.w	3,-1,-1,G_STRING,0,0                    ; 2: '---------------------------------------'
	dc.l	main_rule_text
	dc.w	$0000,$0406,$0027,$0001
	dc.w	4,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0 ; 3: 'UNPACK'
	dc.l	main_unpack_text
	dc.w	$0002,$0008,$070a,$0103
	dc.w	5,-1,-1,G_BUTTON,SELECTABLE|EXIT,0      ; 4: 'INFO'
	dc.l	main_info_text
	dc.w	$000e,$0008,$070a,$0103
	dc.w	6,-1,-1,G_BUTTON,SELECTABLE|EXIT,0      ; 5: 'EXIT'
	dc.l	main_exit_text
	dc.w	$001a,$0008,$070a,$0103
	dc.w	7,-1,-1,G_TEXT,0,0                      ; 6: 'THIS PROGRAM MAY BE COPIED FREELY, AS LONG AS THE'
	dc.l	main_ted_this_program_may
	dc.w	$0001,$000c,$0624,$0600
	dc.w	8,-1,-1,G_TEXT,0,0                      ; 7: 'FILE NAUGHTY.DOC IS COPIED WITH IT AND BOTH FILES'
	dc.l	main_ted_file_naughty_doc
	dc.w	$0001,$000d,$0624,$0600
	dc.w	9,-1,-1,G_TEXT,0,0                      ; 8: 'REMAIN UNMODIFIED.'
	dc.l	main_ted_remain_unmodified
	dc.w	$0001,$000e,$040d,$0600
	dc.w	10,-1,-1,G_TEXT,0,0                     ; 9: 'THIS PROGRAM MAY NOT BE SOLD FOR PROFIT!'
	dc.l	main_ted_this_program_may_not
	dc.w	$0004,$000f,$001e,$0600
	dc.w	11,-1,-1,G_TEXT,0,0                     ; 10: 'COPYRIGHT (c) 1992. ALL RIGHTS RESERVED.'
	dc.l	main_ted_copyright_c_1992
	dc.w	$0004,$0010,$001e,$0600
	dc.w	12,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,SHADOWED ; 11: 'The Naughty Unpacker v2.5'
	dc.l	main_ted_title
	dc.w	$0005,$0001,$001e,$0002
	dc.w	13,-1,-1,G_TEXT,0,0                     ; 12: '>>> USE THIS PROGRAM AT YOUR OWN RISK! <<<'
	dc.l	main_ted_use_this_program
	dc.w	$0003,$0411,$041f,$0600
	dc.w	0,-1,-1,G_STRING,LASTOB,0               ; 13: '>>> ST NEWS VERSION <<<'
	dc.l	main_st_news_version_text
	dc.w	$0408,$0004,$0017,$0001
tree_info:	; from: init_gem
	dc.w	-1,1,23,G_BOX,0,0                       ; 0
	dc.l	$00fe1100
	dc.w	$0000,$0000,$0335,$0515
	dc.w	2,-1,-1,G_STRING,0,0                    ; 1: 'I'd like to thank the following people:'
	dc.l	info_thanks_text
	dc.w	$0007,$0010,$0027,$0001
	dc.w	3,-1,-1,G_STRING,0,0                    ; 2: 'W. Alan B. Evans  (for beta-testing)'
	dc.l	info_thanks_evans_text
	dc.w	$0002,$0012,$0031,$0001
	dc.w	4,-1,-1,G_STRING,0,0                    ; 3: 'Michael Darlison (for sending me lots'
	dc.l	info_thanks_darlison_text
	dc.w	$0002,$0013,$0025,$0001
	dc.w	5,-1,-1,G_BOX,0,0                       ; 4
	dc.l	$00ff1141
	dc.w	$0005,$0011,$022b,$0200
	dc.w	6,-1,-1,G_TEXT,0,0                      ; 5: 'RELEASED:'
	dc.l	info_ted_released
	dc.w	$002d,$0002,$0606,$0600
	dc.w	7,-1,-1,G_TEXT,0,0                      ; 6: '08.10.1992'
	dc.l	info_ted_date
	dc.w	$002c,$0003,$0407,$0600
	dc.w	8,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0 ; 7: 'BACK'
	dc.l	info_back_text
	dc.w	$0028,$0013,$070b,$0102
	dc.w	9,-1,-1,G_STRING,0,0                    ; 8: 'How to use this program:'
	dc.l	info_how_use_this_text
	dc.w	$000f,$0004,$0018,$0001
	dc.w	10,-1,-1,G_BOX,0,0                      ; 9
	dc.l	$00ff1141
	dc.w	$000c,$0005,$041c,$0200
	dc.w	11,-1,-1,G_STRING,0,0                   ; 10: 'This program can unpack most packed program files,'
	dc.l	info_this_program_can_text
	dc.w	$0002,$0006,$0032,$0001
	dc.w	12,-1,-1,G_STRING,0,0                   ; 11: 'but no data files! To unpack a program simply'
	dc.l	info_but_no_data_text
	dc.w	$0004,$0007,$002d,$0001
	dc.w	13,-1,-1,G_STRING,0,0                   ; 12: 'select it with the fileselector. Since most packers'
	dc.l	info_select_it_with_text
	dc.w	$0001,$0008,$0033,$0001
	dc.w	14,-1,-1,G_STRING,0,0                   ; 13: 'output PC-relative code, you will be warned if you'
	dc.l	info_output_pc_relative_text
	dc.w	$0001,$0009,$0032,$0001
	dc.w	15,-1,-1,G_STRING,0,0                   ; 14: 'select a program with relocation information.'
	dc.l	info_select_program_with_text
	dc.w	$0004,$000a,$002d,$0001
	dc.w	16,-1,-1,G_STRING,0,0                   ; 15: 'Supported packers:'
	dc.l	info_supported_packers_text
	dc.w	$0012,$000c,$0012,$0001
	dc.w	17,-1,-1,G_BOX,0,0                      ; 16
	dc.l	$00ff1141
	dc.w	$0011,$000d,$0313,$0200
	dc.w	18,-1,-1,G_TEXT,0,0                     ; 17: 'ALL PACK-ICE, PACK-FIRE, LSD, HAPPY, ATOMIK, JAM, POMPEY,
                                                ;   AUTOMATION,'
	dc.l	info_ted_all_pack_ice
	dc.w	$0001,$000e,$0633,$0600
	dc.w	19,-1,-1,G_TEXT,0,0                     ; 18: 'JEK PACKERS, THUNDER, BAPACK, AND EVERYTHING NICE AND
                                                ;   CLEAN!'
	dc.l	info_ted_jek_packers_thunder
	dc.w	$0001,$000f,$0033,$0600
	dc.w	20,-1,-1,G_TEXT,0,0                     ; 19: 'ZORK'
	dc.l	info_ted_zork
	dc.w	$0004,$0001,$0004,$0001
	dc.w	21,-1,-1,G_TEXT,0,0                     ; 20: 'OF'
	dc.l	info_ted_of
	dc.w	$0404,$0401,$0202,$0701
	dc.w	22,-1,-1,G_TEXT,0,0                     ; 21: 'S.O.T.E.'
	dc.l	info_ted_sote
	dc.w	$0003,$0003,$0006,$0600
	dc.w	23,-1,-1,G_BOXTEXT,0,SHADOWED           ; 22: 'The Naughty Unpacker v2.5'
	dc.l	info_ted_title
	dc.w	$000b,$0001,$001e,$0002
	dc.w	0,-1,-1,G_STRING,LASTOB,0               ; 23: 'of packers!)'
	dc.l	info_of_packers_text
	dc.w	$0002,$0014,$0025,$0001
tree_progress:	; from: init_gem
	dc.w	-1,1,3,G_BOX,0,0                        ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0617,$0705
	dc.w	2,-1,-1,G_STRING,0,0                    ; 1: 'File: 12345678901234'
	dc.l	progress_file_line_text
	dc.w	$0002,$0001,$0014,$0001
	dc.w	3,-1,-1,G_STRING,0,0                    ; 2: 'unpacking...'
	dc.l	progress_unpacking_text
	dc.w	$0006,$0004,$000c,$0001
	dc.w	0,-1,-1,G_STRING,LASTOB,0               ; 3: 'Size: 1234567 bytes'
	dc.l	progress_size_line_text
	dc.w	$0002,$0002,$0013,$0001
tree_setup:	; from: init_gem
	dc.w	-1,1,8,G_BOX,0,0                        ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0023,$000b
	dc.w	2,-1,-1,G_STRING,0,0                    ; 1: 'Setup Menu'
	dc.l	setup_title_text
	dc.w	$000c,$0001,$000a,$0001
	dc.w	3,-1,-1,G_BOX,0,0                       ; 2
	dc.l	$00ff1141
	dc.w	$000a,$0002,$000e,$0200
	dc.w	4,-1,-1,G_STRING,0,0                    ; 3: 'Show statistics'
	dc.l	setup_show_statistics_text
	dc.w	$0008,$0004,$0012,$0001
	dc.w	5,-1,-1,G_BOXCHAR,SELECTABLE,SELECTED   ; 4
	dc.l	$00ff1100
	dc.w	$0003,$0006,$0003,$0001
	dc.w	6,-1,-1,G_STRING,0,0                    ; 5: 'Save and restore screen'
	dc.l	setup_save_restore_screen_text
	dc.w	$0008,$0006,$0017,$0001
	dc.w	7,-1,-1,G_BOXCHAR,SELECTABLE,SELECTED   ; 6
	dc.l	$00ff1100
	dc.w	$0003,$0004,$0003,$0001
	dc.w	8,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0 ; 7: 'BACK'
	dc.l	setup_back_text
	dc.w	$0413,$0008,$000b,$0002
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0 ; 8: 'SAVE'
	dc.l	setup_save_text
	dc.w	$0404,$0008,$000a,$0002
main_ted_this_program_may:
	dc.l	main_this_program_may_text,main_this_program_may_tmplt,main_this_program_may_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0032,$0001
main_ted_file_naughty_doc:
	dc.l	main_file_naughty_doc_text,main_file_naughty_doc_tmplt,main_file_naughty_doc_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0032,$0001
main_ted_remain_unmodified:
	dc.l	main_remain_unmodified_text,main_remain_unmodified_tmplt,main_remain_unmodified_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0013,$0001
main_ted_this_program_may_not:
	dc.l	main_this_program_may_not_text,main_this_program_may_not_tmplt,main_this_program_may_not_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0029,$0001
main_ted_copyright_c_1992:
	dc.l	main_copyright_c_1992_text,main_copyright_c_1992_tmplt,main_copyright_c_1992_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0029,$0001
main_ted_title:
	dc.l	main_title_text,main_title_tmplt,main_title_valid
	dc.w	$0003,$0006,$0002,$1180,$0000,$0002,$001a,$0001
main_ted_use_this_program:
	dc.l	main_use_this_program_text,main_use_this_program_tmplt,main_use_this_program_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$002b,$0001
info_ted_released:
	dc.l	info_released_text,info_released_tmplt,info_released_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$000a,$0001
info_ted_date:
	dc.l	info_date_text,info_date_tmplt,info_date_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$000b,$0001
info_ted_all_pack_ice:
	dc.l	info_all_pack_ice_text,info_all_pack_ice_tmplt,info_all_pack_ice_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0046,$0001
info_ted_jek_packers_thunder:
	dc.l	info_jek_packers_thunder_text,info_jek_packers_thunder_tmplt,info_jek_packers_thunder_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$003d,$0001
info_ted_zork:
	dc.l	info_zork_text,info_zork_tmplt,info_zork_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0005,$0001
info_ted_of:
	dc.l	info_of_text,info_of_tmplt,info_of_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0003,$0001
info_ted_sote:
	dc.l	info_sote_text,info_sote_tmplt,info_sote_valid
	dc.w	$0005,$0006,$0000,$1180,$0000,$ffff,$0009,$0001
info_ted_title:
	dc.l	info_title_text,info_title_tmplt,info_title_valid
	dc.w	$0003,$0006,$0002,$1180,$0000,$0002,$001a,$0001
main_author_text:
	dc.b	'(c)1992 by Marinos Yannikos',0
main_rule_text:
	dc.b	'---------------------------------------',0
main_unpack_text:
	dc.b	'UNPACK',0
main_info_text:
	dc.b	'INFO',0
main_exit_text:
	dc.b	'EXIT',0
main_st_news_version_text:
	dc.b	'>>> ST NEWS VERSION <<<',0
info_thanks_text:
	dc.b	'I',$27,'d like to thank the following people:',0
info_thanks_evans_text:
	dc.b	'W. Alan B. Evans  (for beta-testing)',0
info_thanks_darlison_text:
	dc.b	'Michael Darlison (for sending me lots',0
info_back_text:
	dc.b	'BACK',0
info_how_use_this_text:
	dc.b	'How to use this program:',0
info_this_program_can_text:
	dc.b	'This program can unpack most packed program files,',0
info_but_no_data_text:
	dc.b	'but no data files! To unpack a program simply',0
info_select_it_with_text:
	dc.b	'select it with the fileselector. Since most packers',0
info_output_pc_relative_text:
	dc.b	'output PC-relative code, you will be warned if you',0
info_select_program_with_text:
	dc.b	'select a program with relocation information.',0
info_supported_packers_text:
	dc.b	'Supported packers:',0
info_of_packers_text:
	dc.b	'of packers!)',0
progress_file_line_text:
	dc.b	'File: 12345678901234',0
progress_unpacking_text:
	dc.b	'unpacking...',0
progress_size_line_text:
	dc.b	'Size: 1234567 bytes',0
setup_title_text:
	dc.b	'Setup Menu',0
setup_show_statistics_text:
	dc.b	'Show statistics',0
setup_save_restore_screen_text:
	dc.b	'Save and restore screen',0
setup_back_text:
	dc.b	'BACK',0
setup_save_text:
	dc.b	'SAVE',0
main_this_program_may_text:
	dc.b	'THIS PROGRAM MAY BE COPIED FREELY, AS LONG AS THE',0
main_this_program_may_tmplt:
	dc.b	$00
main_this_program_may_valid:
	dc.b	$00
main_file_naughty_doc_text:
	dc.b	'FILE NAUGHTY.DOC IS COPIED WITH IT AND BOTH FILES',0
main_file_naughty_doc_tmplt:
	dc.b	$00
main_file_naughty_doc_valid:
	dc.b	$00
main_remain_unmodified_text:
	dc.b	'REMAIN UNMODIFIED.',0
main_remain_unmodified_tmplt:
	dc.b	$00
main_remain_unmodified_valid:
	dc.b	$00
main_this_program_may_not_text:
	dc.b	'THIS PROGRAM MAY NOT BE SOLD FOR PROFIT!',0
main_this_program_may_not_tmplt:
	dc.b	$00
main_this_program_may_not_valid:
	dc.b	$00
main_copyright_c_1992_text:
	dc.b	'COPYRIGHT (c) 1992. ALL RIGHTS RESERVED.',0
main_copyright_c_1992_tmplt:
	dc.b	$00
main_copyright_c_1992_valid:
	dc.b	$00
main_title_text:
	dc.b	'The Naughty Unpacker v2.5',0
main_title_tmplt:
	dc.b	$00
main_title_valid:
	dc.b	$00
main_use_this_program_text:
	dc.b	'>>> USE THIS PROGRAM AT YOUR OWN RISK! <<<',0
main_use_this_program_tmplt:
	dc.b	$00
main_use_this_program_valid:
	dc.b	$00
info_released_text:
	dc.b	'RELEASED:',0
info_released_tmplt:
	dc.b	$00
info_released_valid:
	dc.b	$00
info_date_text:
	dc.b	'08.10.1992',0
info_date_tmplt:
	dc.b	$00
info_date_valid:
	dc.b	$00
info_all_pack_ice_text:
	dc.b	'ALL PACK-ICE, PACK-FIRE, LSD, HAPPY, ATOMIK, JAM, POMPEY, AUTOMA'
	dc.b	'TION,',0
info_all_pack_ice_tmplt:
	dc.b	$00
info_all_pack_ice_valid:
	dc.b	$00
info_jek_packers_thunder_text:
	dc.b	'JEK PACKERS, THUNDER, BAPACK, AND EVERYTHING NICE AND CLEAN!',0
info_jek_packers_thunder_tmplt:
	dc.b	$00
info_jek_packers_thunder_valid:
	dc.b	$00
info_zork_text:
	dc.b	'ZORK',0
info_zork_tmplt:
	dc.b	$00
info_zork_valid:
	dc.b	$00
info_of_text:
	dc.b	'OF',0
info_of_tmplt:
	dc.b	$00
info_of_valid:
	dc.b	$00
info_sote_text:
	dc.b	'S.O.T.E.',0
info_sote_tmplt:
	dc.b	$00
info_sote_valid:
	dc.b	$00
info_title_text:
	dc.b	'The Naughty Unpacker v2.5',0
info_title_tmplt:
	dc.b	$00
info_title_valid:
	dc.b	$00,$00,$11

;------------------------------------------------------------------------------
; Runs the loaded packed program so that it unpacks itself, and catches it as it is about to
; relocate the unpacked program.
;
; The first $800 bytes of its text are searched twice.  First the screen: every $7fd00 (the screen
; address of a 512K ST) and every Physbase or Logbase call is changed to give packer_screen instead,
; so the depacker's picture or effects go to a buffer.  Then the relocation loop the depacker runs
; on the unpacked program: a move.l (an),dn or tst.l (an) followed by a short beq, or the
; add.l d2,(a1) form $d5b10800.  That instruction is overwritten with jmp catch_unpacked_program and
; the program is started with Pexec 4.  Returns with unpacked_header and unpacked_end set, or both 0
; when nothing was found.
;------------------------------------------------------------------------------
run_packed_program:	; from: load_and_unpack
	movem.l	d0-d7/a0-sp,saved_registers     ; kept for after the packed program has run
	movea.l	loaded_text(pc),a0              ; the packed program's text
	clr.w	is_bras_program                 ; is_bras_program: bra.s *+$2c then 'BRAS'?
	cmpi.w	#$602a,(a0)                     ; bra.s *+$2c?
	bne.s	run_scan_start                  ; no
	cmpi.l	#$42524153,2(a0)                ; then 'BRAS'?
	seq	is_bras_program                 ; is_bras_program = $ff when it is
run_scan_start:
	movea.l	a0,a2                           ; a2 = the start, for the second search
	lea	$800(a0),a1                     ; a1 = the end of the search, $800 bytes in
patch_screen_calls:
	cmpa.l	a0,a1                           ; the end reached?
	beq.s	find_relocation_loop            ; yes: now the relocation loop
	cmpi.l	#$7fd00,(a0)                    ; the long $7fd00: the screen address of a 512K ST
	bne.s	patch_check_trap                ; no: look for a screen call
	move.l	packer_screen_ptr(pc),(a0)+     ; becomes packer_screen
	bra.s	patch_screen_calls              ; next word
patch_check_trap:
	cmpi.w	#$3f3c,(a0)+                    ; move.w #...,-(sp)
	bne.s	patch_screen_calls              ; not move.w #n,-(sp): next word
	cmpi.l	#$24e4e,(a0)                    ; #2 then trap #14: Physbase
	beq.s	patch_screen_call               ; Physbase: patch it
	cmpi.l	#$34e4e,(a0)                    ; #3 then trap #14: Logbase
	bne.s	patch_screen_calls              ; neither: next word
patch_screen_call:
	move.l	screen_call_patch(pc),-$2(a0)   ; move.l packer_screen_ptr,d0
	move.w	screen_call_patch+4(pc),2(a0)   ; ... and the nop after it
	cmpi.w	#$548f,4(a0)                    ; addq.l #2,sp
	beq.s	patch_stack_fix                 ; patch the parameter drop too
	cmpi.w	#$544f,4(a0)                    ; addq.w #2,sp
	bne.s	find_relocation_loop            ; anything else: leave it and stop looking
patch_stack_fix:
	move.w	trap_cleanup_patch(pc),4(a0)    ; becomes nop
find_relocation_loop:
	lea	$800(a0),a1                     ; a1 = the end of the search
	movea.l	a2,a0                           ; back to the start
find_relocation_next:
	cmpa.l	a0,a1                           ; the end reached?
	beq.w	nothing_found                   ; yes: nothing found
	move.w	(a0)+,d0                        ; next opcode
	move.w	d0,d1                           ; a copy for the tst.l test
	andi.w	#$f1f0,d0                       ; move.l (an),dn
	cmp.w	#$2010,d0                       ; move.l (an),dn?
	beq.s	find_relocation_beq             ; yes: check for the beq
	cmpi.l	#$d5b10800,(a0)                 ; or add.l d2,0(a1,d0.l)
	beq.s	patch_relocation_loop           ; yes: patch here
	andi.w	#$fff0,d1                       ; tst.l (an)
	cmp.w	#$4a90,d1                       ; tst.l (an)?
	bne.s	find_relocation_next            ; none of them: next word
find_relocation_beq:
	move.w	(a0)+,d1                        ; then beq.s
	move.w	d1,d2                           ; the next word ...
	lsr.w	#8,d2                           ; ... its high byte
	cmp.w	#$67,d2                         ; beq.s?
	bne.s	find_relocation_next            ; no: go on searching
	andi.w	#$ff,d1                         ; forward at most $30
	cmp.w	#$30,d1                         ; a short jump: the end of the relocation
	bgt.s	find_relocation_next            ; too far: not the loop
patch_relocation_loop:
	movem.l	d0-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	show_unpacking                  ; ' unpacking...'
	movem.l	(sp)+,d0-d7/a0-a6               ; and get them back
	move.w	#$4ef9,-$2(a0)                  ; jmp ...
	move.l	#catch_unpacked_program,(a0)    ; ... catch_unpacked_program
	clr.l	-(sp)                           ; no environment
	move.l	loaded_basepage(pc),-(sp)       ; the loaded basepage
	clr.l	-(sp)                           ; no command line
	move.w	#$4,-(sp)                       ; Pexec 4: just run it
	move.w	#$4b,-(sp)                      ; Pexec
	trap	#1                              ; Pexec
	lea	$10(sp),sp                      ; drop the parameters
	movem.l	saved_registers(pc),d0-d7/a0-sp ; back to the caller after the Pterm0
	rts                                     ; unpacked_header and unpacked_end are set

;------------------------------------------------------------------------------
; 4 bytes nothing uses.
;------------------------------------------------------------------------------
unused_long:
	dc.w	$0000,$0000

;------------------------------------------------------------------------------
; The packed program's registers when it reached its relocation loop.
;------------------------------------------------------------------------------
caught_registers:	; from: catch_unpacked_program
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; Where the patched program jumps instead of relocating.  The unpacked program is the program header
; ($601a) that one of the registers points at.  When several do, the one with the largest text +
; data (under 2 MB) is taken.  A 'BRAS' program keeps its header elsewhere: the header is rebuilt
; in front of the text from the basepage a5 points at.  Pterm0 then ends the packed program and
; returns to run_packed_program's Pexec.
;------------------------------------------------------------------------------
catch_unpacked_program:	; from: run_packed_program
	movem.l	d0-d7/a0-a6,caught_registers    ; the registers of the packed program
	clr.w	header_found                    ; none found yet
	lea	caught_registers(pc),a0         ; a0 = the registers to look through
	movea.l	loaded_text(pc),a6              ; a6 = the lowest address the unpacked program can be at
	tst.w	is_bras_program                 ; a BRAS program?
	beq.s	search_registers                ; no: search the registers
	move.l	$c(a5),-$1a(a3)                 ; BRAS: the header is rebuilt in front of the text from the basepage a5:
                                                ;   text length
	move.l	$14(a5),-$16(a3)                ; data length
	move.l	$1c(a5),-$12(a3)                ; bss length
	move.l	a3,d0                           ; a3 = the text
	add.l	$c(a5),d0                       ; + text length
	add.l	$14(a5),d0                      ; + data length = the end of the data
	cmp.l	a2,d0                           ; a2 = the relocation table: symbols between?
	beq.s	bras_header_magic               ; none
	sub.l	a2,d0                           ; the end of the data - a2 ...
	neg.l	d0                              ; ... negated: the symbol table length
	move.l	d0,-$e(a3)                      ; the symbol table length: what lies between the data and a2
bras_header_magic:
	move.w	#$601a,-$1c(a3)                 ; a program header
	tst.l	(a2)+                           ; the relocation table: the first long, then bytes to a 0
	beq.s	bras_header_done                ; no relocation: it ends there
bras_skip_relocation:
	tst.b	(a2)+                           ; skip the relocation bytes
	bne.s	bras_skip_relocation            ; up to the 0
bras_header_done:
	lea	-$1c(a3),a1                     ; a1 = the rebuilt header
	bra.w	unpacked_program_found          ; store it
search_registers:
	cmpa.l	#catch_unpacked_program,a0      ; all 15 registers looked at?
	beq.w	registers_searched              ; yes: take the best one
	move.l	(a0)+,d0                        ; next register
	btst	#$0,d0                          ; odd: not a header
	bne.s	search_registers                ; odd: next
	cmp.l	a6,d0                           ; below the program: not its unpacked copy
	blt.s	search_registers                ; too low: next
	cmp.l	#$400000,d0                     ; above 4 MB
	bge.s	search_registers                ; too high: next
	cmp.l	#$1000,d0                       ; below $1000 ...
	blt.s	search_registers                ; ... is the system: next
	movea.l	d0,a1                           ; a program header?
	cmpi.w	#$601a,(a1)
	bne.s	search_registers                ; no header: next
	moveq	#0,d2                           ; d2 = text + data
	add.l	2(a1),d2                        ; text +
	add.l	6(a1),d2                        ; data
	cmp.l	#$200000,d2                     ; no more than 2 MB
	bge.s	search_registers                ; too long: next
	tst.w	header_found                    ; the first one found?
	bne.s	search_compare_best             ; no: compare
	move.l	d2,best_length                  ; yes: take it
	move.l	a1,best_header                  ; and its header
	st	header_found                    ; one found
	bra.s	search_registers                ; next register
search_compare_best:
	cmp.l	best_length(pc),d2              ; longer than the best so far?
	ble.s	search_registers                ; not longer: next
	move.l	d2,best_length                  ; longer: take this one
	move.l	a1,best_header                  ; and its header
	bra.s	search_registers                ; next register
skip_relocation_table:
	lea	$1c(a1),a2                      ; past the header, text, data and symbols
	adda.l	2(a1),a2                        ; + text
	adda.l	6(a1),a2                        ; + data
	adda.l	$e(a1),a2                       ; + symbols: the relocation table
	tst.l	(a2)                            ; no relocation
	beq.s	unpacked_program_found          ; none: the program ends here
	addq.w	#4,a2                           ; the first long, then the bytes to the 0
skip_relocation_bytes:
	tst.b	(a2)+                           ; skip the step bytes
	bne.s	skip_relocation_bytes           ; up to the 0
unpacked_program_found:
	move.l	a2,unpacked_end                 ; the end of the unpacked program
	move.l	a1,unpacked_header              ; its header
	clr.w	-(sp)                           ; end the packed program
	trap	#1                              ; Pterm0
registers_searched:
	tst.w	header_found                    ; any header found?
	beq.s	nothing_found                   ; no
	movea.l	best_header(pc),a1              ; the longest
	bra.s	skip_relocation_table           ; find its end
nothing_found:	; from: run_packed_program
	clr.l	unpacked_end                    ; nothing: unpacked_end = 0
	clr.l	unpacked_header                 ; unpacked_header = 0
	rts                                     ; back to the caller

;------------------------------------------------------------------------------
; Variables of catch_unpacked_program, in the text so they are reached PC-relative.
;------------------------------------------------------------------------------
best_length:	; from: catch_unpacked_program
	dc.w	$0000,$0000
header_found:	; from: catch_unpacked_program
	dc.w	$0000
best_header:	; from: catch_unpacked_program
	dc.w	$0000,$0000
saved_registers:	; from: run_packed_program
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000

;------------------------------------------------------------------------------
; Relocates the loaded program (the packed one) at loaded_text, with its relocation table after the
; data, before it is run.
;------------------------------------------------------------------------------
relocate_loaded_program:	; from: load_and_unpack
	movem.l	d0-d1/a0-a1,-(sp)               ; keep the registers used
	moveq	#0,d1                           ; d1 = step byte, high bytes 0
	movea.l	loaded_basepage(pc),a0          ; the basepage:
	move.l	$c(a0),d0                       ; text +
	add.l	$14(a0),d0                      ; data: where the relocation table starts
	movea.l	loaded_text(pc),a1              ; a1 = the text
	movea.l	a1,a0                           ; a0 = the text too
	adda.l	d0,a1                           ; a1 = the relocation table
	move.l	a0,d0                           ; d0 = the text address to add
	adda.l	(a1)+,a0                        ; the first long to relocate
relocate_long:
	add.l	d0,(a0)                         ; relocate the long at a0
relocate_next_step:
	move.b	(a1)+,d1                        ; next step byte
	beq.s	relocate_done                   ; 0: done
	btst	#$0,d1                          ; odd?
	beq.s	relocate_step                   ; no: an even step
	lea	$fe(a0),a0                      ; 1: 254 bytes on, nothing to relocate
	bra.s	relocate_next_step              ; next step byte
relocate_step:
	adda.w	d1,a0                           ; move on that far
	bra.s	relocate_long                   ; and relocate there
relocate_done:
	movem.l	(sp)+,d0-d1/a0-a1               ; restore the registers
	rts

;------------------------------------------------------------------------------
; Returns in d0 the long at a0, which may be at an odd address; a0 moves on 4.
;------------------------------------------------------------------------------
get_unaligned_long:	; from: is_known_packer
	move.b	(a0)+,-(sp)                     ; byte 1 into the high byte of a word on the stack
	move.b	(a0)+,1(sp)                     ; byte 2 into its low byte
	move.b	(a0)+,-(sp)                     ; byte 3 into the high byte of the next word
	move.l	(sp)+,d0                        ; d0 = bytes 3,?,1,2
	swap	d0                              ; d0 = bytes 1,2,3,?
	move.b	(a0)+,d0                        ; byte 4
	rts

;------------------------------------------------------------------------------
; 10 bytes nothing uses.
;------------------------------------------------------------------------------
unused_bytes:
	dc.b	'ffo ssiqNu'

;------------------------------------------------------------------------------
; Whether the loaded program is from a packer known to relocate itself: returns d0 = 1 when one of
; the identifying marks is there ('POPI' at the end of the file, 'ATOM' at +$256, 'HART' at +$e,
; or one of three code sequences at the start), 0 otherwise.  Only asked when the program has a
; relocation table.
;------------------------------------------------------------------------------
is_known_packer:	; from: load_and_unpack
	move.l	a0,-(sp)                        ; keep a0
	move.l	a1,-(sp)                        ; and a1
	movea.l	loaded_text(pc),a1              ; a1 = the text
	lea	-$4(a1),a0                      ; the last long of the file
	adda.l	file_length,a0                  ; + the length read
	bsr.s	get_unaligned_long              ; d0 = the last long of the file
	cmp.l	#$504f5049,d0                   ; 'POPI'
	beq.s	known_packer_yes                ; yes
	cmpi.l	#$41544f4d,$256(a1)             ; 'ATOM'
	beq.s	known_packer_yes                ; yes
	cmpi.l	#$48415254,$e(a1)               ; 'HART'
	beq.s	known_packer_yes                ; yes
	cmpi.l	#$15124456,$76(a1)              ; a code sequence at +$76 ...
	bne.s	known_packer_check_loop         ; no
	cmpi.l	#$3c85b7ca,$7a(a1)              ; ... and +$7a
	beq.s	known_packer_yes                ; yes
known_packer_check_loop:
	cmpi.l	#$232051c9,$14(a1)              ; move.l -(a0),-(a1) / dbra d1 at +$14
	bne.s	known_packer_check_start        ; no
	cmpi.l	#$fffc51c8,$18(a1)              ; its two dbra
	bne.s	known_packer_check_start        ; no
	cmpi.w	#$fff8,$1c(a1)                  ; back 8
	beq.s	known_packer_yes                ; yes
known_packer_check_start:
	cmpi.l	#$6100009a,(a1)                 ; bsr.w ... / movea.l 4(sp),a5 / movea.l $18(a5),a4
	bne.s	known_packer_no                 ; no
	cmpi.l	#$2a6f0004,4(a1)                ; then movea.l 4(sp),a5
	bne.s	known_packer_no                 ; no
	cmpi.l	#$286d0018,8(a1)                ; then movea.l $18(a5),a4
	beq.s	known_packer_yes                ; yes
known_packer_no:
	movea.l	(sp)+,a1                        ; restore a1
	movea.l	(sp)+,a0                        ; and a0
	moveq	#0,d0                           ; not known
	rts
known_packer_yes:
	movea.l	(sp)+,a1                        ; restore a1
	movea.l	(sp)+,a0                        ; and a0
	moveq	#1,d0                           ; known
	rts

;------------------------------------------------------------------------------
; The 6 bytes put over move.w #2,-(sp) / trap #14 (Physbase) or #3 (Logbase): move.l
; packer_screen_ptr,d0, then nop over the addq/lea that drops the parameter.
;------------------------------------------------------------------------------
screen_call_patch:	; from: run_packed_program
	move.l	packer_screen_ptr,d0            ; over move.w #2,-(sp) / trap #14
trap_cleanup_patch:	; from: run_packed_program
	nop                                     ; over the addq that drops the parameter

;------------------------------------------------------------------------------
; Set when the loaded program starts bra.s *+$2c and 'BRAS'.
;------------------------------------------------------------------------------
is_bras_program:	; from: run_packed_program, catch_unpacked_program
	dc.w	$0000

;------------------------------------------------------------------------------
; form_dial(d0 = mode) for the tree at a0, with a box 2 pixels bigger on every side.
;------------------------------------------------------------------------------
form_dial_tree:	; from: open_progress, close_progress, main
	move.w	d3,-(sp)                        ; d3 = mode
	move.l	a2,-(sp)                        ; keep a2
	move.w	d0,d3                           ; d3 = the mode
	movea.l	a0,a2                           ; a2 = the tree
	moveq	#4,d1                           ; the big box: height + 4
	add.w	$16(a2),d1                      ; + ob_height
	move.w	d1,-(sp)                        ; pushed
	moveq	#4,d2                           ; width + 4
	add.w	$14(a2),d2                      ; + ob_width
	move.w	d2,-(sp)                        ; pushed
	moveq	#-2,d0                          ; y - 2
	add.w	$12(a2),d0                      ; + ob_y
	move.w	d0,-(sp)                        ; pushed
	moveq	#-2,d1                          ; x - 2
	add.w	$10(a2),d1                      ; + ob_x
	move.w	d1,-(sp)                        ; pushed
	moveq	#4,d2                           ; the little box the same: height + 4
	add.w	$16(a2),d2                      ; + ob_height
	move.w	d2,-(sp)                        ; pushed
	moveq	#4,d0                           ; width + 4
	add.w	$14(a2),d0                      ; + ob_width
	move.w	d0,-(sp)                        ; pushed
	moveq	#-2,d2                          ; y - 2
	add.w	$12(a2),d2                      ; + ob_y, in d2
	move.w	d3,d0                           ; the mode
	jsr	form_dial(pc)                   ; form_dial(mode, little box, big box)
	lea	$c(sp),sp                       ; drop the parameters
	movea.l	(sp)+,a2                        ; restore a2
	move.w	(sp)+,d3                        ; and d3
	rts

;------------------------------------------------------------------------------
; Puts up the progress box (form_dial FMD_START) unless it is already up.
;------------------------------------------------------------------------------
open_progress:	; from: draw_progress, show_reading, show_checking, show_unpacking, show_writing
	move.w	progress_open(pc),d0            ; up already?
	bne.s	open_progress_done              ; yes
	movea.l	tree_progress_ptr(pc),a0        ; the progress box
	clr.w	d0                              ; FMD_START
	jsr	form_dial_tree(pc)
	move.w	#$1,progress_open               ; it is up
open_progress_done:
	rts

;------------------------------------------------------------------------------
; Takes the progress box down (form_dial FMD_FINISH) if it is up.
;------------------------------------------------------------------------------
close_progress:	; from: unpack_and_save
	move.w	progress_open(pc),d0            ; up?
	beq.s	close_progress_done             ; no
	movea.l	tree_progress_ptr(pc),a0        ; the progress box
	moveq	#3,d0                           ; FMD_FINISH
	jsr	form_dial_tree(pc)
	clr.w	progress_open                   ; it is down
close_progress_done:
	rts

;------------------------------------------------------------------------------
; objc_draw(tree a0, from object d0, depth 8), clipped to a box 2 pixels bigger than the tree.
;------------------------------------------------------------------------------
draw_tree:	; from: draw_progress, main
	move.w	d3,-(sp)                        ; keep d3
	move.l	a2,-(sp)                        ; and a2
	movea.l	a0,a2                           ; a2 = the tree
	move.w	d0,d3                           ; d3 = the first object
	moveq	#4,d1                           ; clip height + 4
	add.w	$16(a2),d1                      ; + ob_height
	move.w	d1,-(sp)                        ; pushed
	moveq	#4,d2                           ; clip width + 4
	add.w	$14(a2),d2                      ; + ob_width
	move.w	d2,-(sp)                        ; pushed
	moveq	#-2,d0                          ; clip y - 2
	add.w	$12(a2),d0                      ; + ob_y
	move.w	d0,-(sp)                        ; pushed
	moveq	#-2,d2                          ; clip x - 2
	add.w	$10(a2),d2                      ; + ob_x, in d2
	move.w	d3,d0                           ; the first object
	moveq	#8,d1                           ; depth 8
	jsr	objc_draw(pc)
	addq.w	#6,sp                           ; drop the parameters
	movea.l	(sp)+,a2                        ; restore a2
	move.w	(sp)+,d3                        ; and d3
	rts

;------------------------------------------------------------------------------
; Puts up the progress box if needed and draws it.
;------------------------------------------------------------------------------
draw_progress:	; from: show_reading, show_checking, show_unpacking, show_writing
	jsr	open_progress(pc)               ; put the box up
	clr.w	d0                              ; from the root
	movea.l	tree_progress_ptr(pc),a0        ; the progress box
	jsr	draw_tree(pc)                   ; draw it
	rts

;------------------------------------------------------------------------------
; Progress box: 'File: <name>' and ' reading...'.
;------------------------------------------------------------------------------
show_reading:	; from: load_and_unpack
	move.l	a2,-(sp)                        ; keep a2
	jsr	open_progress(pc)               ; put the box up
	lea	progress_file_text(pc),a2       ; a2 = the pointers to its strings
	lea	str_file(pc),a1                 ; 'File: '
	movea.l	(a2),a0                         ; object 1's string
	jsr	strcpy(pc)                      ; 'File: '
	lea	load_name-progress_file_text(a2),a1 ; the name of the program
	movea.l	(a2),a0                         ; object 1's string
	jsr	strcat(pc)                      ; + the file name
	lea	str_reading(pc),a1
	movea.l	progress_status_text-progress_file_text(a2),a0 ; object 2's string
	jsr	strcpy(pc)                      ; ' reading...'
	lea	str_empty(pc),a1                ; ''
	movea.l	progress_size_text-progress_file_text(a2),a0 ; object 3's string
	jsr	strcpy(pc)                      ; no size yet
	jsr	draw_progress(pc)               ; draw it
	movea.l	(sp)+,a2                        ; restore a2
	rts

;------------------------------------------------------------------------------
; Progress box: 'checking...' and 'Size: <file length> bytes'.
;------------------------------------------------------------------------------
show_checking:	; from: load_and_unpack
	move.l	a2,-(sp)                        ; keep a2
	lea	-$32(sp),sp                     ; room for the number
	jsr	open_progress(pc)               ; put the box up
	lea	progress_size_text(pc),a2       ; a2 = the pointers to its strings
	lea	str_checking(pc),a1             ; 'checking...'
	movea.l	progress_status_text-progress_size_text(a2),a0 ; object 2's string
	jsr	strcpy(pc)                      ; copied
	moveq	#10,d1                          ; base 10
	lea	(sp),a0                         ; into the buffer
	moveq	#28,d0                          ; what was read after the header, + the header
	add.l	file_length-progress_size_text(a2),d0
	jsr	ultoa(pc)                       ; the number as text
	lea	str_size(pc),a1                 ; 'Size: '
	movea.l	(a2),a0                         ; object 3's string
	jsr	strcpy(pc)                      ; copied
	lea	(sp),a1                         ; + the number
	movea.l	(a2),a0                         ; object 3's string
	jsr	strcat(pc)                      ; appended
	lea	str_bytes(pc),a1                ; + ' bytes'
	movea.l	(a2),a0                         ; object 3's string
	jsr	strcat(pc)                      ; appended
	jsr	draw_progress(pc)               ; draw it
	lea	$32(sp),sp                      ; drop the buffer
	movea.l	(sp)+,a2                        ; restore a2
	rts

;------------------------------------------------------------------------------
; Progress box: 'unpacking...'.
;------------------------------------------------------------------------------
show_unpacking:	; from: run_packed_program
	jsr	open_progress(pc)               ; put the box up
	lea	str_unpacking(pc),a1            ; 'unpacking...'
	movea.l	progress_status_text(pc),a0     ; object 2's string
	jsr	strcpy(pc)                      ; copied
	jsr	draw_progress(pc)               ; draw it
	rts

;------------------------------------------------------------------------------
; Progress box: 'File: <new name>', ' writing...' and 'Size: <unpacked length> bytes'.
;------------------------------------------------------------------------------
show_writing:	; from: unpack_and_save
	move.l	a2,-(sp)                        ; keep a2
	move.l	a3,-(sp)                        ; and a3
	lea	-$32(sp),sp                     ; room for the number
	jsr	open_progress(pc)               ; put the box up
	lea	str_file(pc),a2                 ; a2 = the strings
	lea	progress_size_text(pc),a3       ; a3 = the pointers to the strings in the box
	movea.l	a2,a1                           ; 'File: '
	movea.l	progress_file_text-progress_size_text(a3),a0 ; object 1's string
	jsr	strcpy(pc)                      ; copied
	lea	save_name-progress_size_text(a3),a1 ; + the new name
	movea.l	progress_file_text-progress_size_text(a3),a0 ; object 1's string
	jsr	strcat(pc)                      ; appended
	lea	str_writing-str_file(a2),a1     ; ' writing...'
	movea.l	progress_status_text-progress_size_text(a3),a0 ; object 2's string
	jsr	strcpy(pc)                      ; copied
	moveq	#10,d1                          ; base 10
	lea	(sp),a0                         ; into the buffer
	move.l	save_length-progress_size_text(a3),d0 ; the unpacked length
	jsr	ultoa(pc)                       ; as text
	lea	str_size-str_file(a2),a1        ; 'Size: '
	movea.l	(a3),a0                         ; object 3's string
	jsr	strcpy(pc)                      ; copied
	lea	(sp),a1                         ; + the number
	movea.l	(a3),a0                         ; object 3's string
	jsr	strcat(pc)                      ; appended
	lea	str_bytes-str_file(a2),a1       ; + ' bytes'
	movea.l	(a3),a0                         ; object 3's string
	jsr	strcat(pc)                      ; appended
	jsr	draw_progress(pc)               ; draw it
	lea	$32(sp),sp                      ; drop the buffer
	movea.l	(sp)+,a3                        ; restore a3
	movea.l	(sp)+,a2                        ; and a2
	rts

;------------------------------------------------------------------------------
; Closes GEM and ends with exit(1).
;------------------------------------------------------------------------------
quit_with_error:	; from: load_and_unpack
	jsr	close_gem(pc)                   ; GEM off
	moveq	#1,d0                           ; status 1
	jsr	exit(pc)                        ; end the program
	rts

;------------------------------------------------------------------------------
; Loads the program in file_handle and unpacks it.  Returns d0 = 1 when unpacked_header and
; unpacked_end hold the unpacked program, 0 after an alert.
;
; The header must be a program's ($601a) with no symbol table.  A basepage is made with Pexec 5
; and the program read into it as TOS would load it; its relocation table is applied when it has
; one, after asking when the packer is not a known self-relocating one.  Then run_packed_program
; unpacks it, timed with the 200 Hz clock for the statistics.
;------------------------------------------------------------------------------
load_and_unpack:	; from: unpack_and_save
	movem.l	d3-d6/a2-a3/a5,-(sp)            ; keep the registers used
	lea	-$19a(sp),sp                    ; room for the statistics text and doubles
	lea	file_header,a2                  ; a2 = the header
	movea.l	a2,a0                           ; read into it
	moveq	#28,d1                          ; read the header
	move.w	file_handle(pc),d0              ; from the open file
	jsr	Fread(pc)
	lea	str_file(pc),a3                 ; a3 = the base of the strings
	cmpi.w	#$601a,(a2)                     ; a program?
	beq.s	load_check_symbols              ; yes
	lea	alert_not_executable-str_file(a3),a0 ; 'not executable!'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	bra.w	load_and_unpack_failed          ; give up
load_check_symbols:
	move.l	$e(a2),d0                       ; a symbol table?
	beq.s	load_check_memory               ; none
	lea	alert_symbol_table-str_file(a3),a0 ; 'contains a symbol table'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	bra.w	load_and_unpack_failed          ; give up
load_check_memory:
	move.l	#$10000,d0                      ; can 64K be had?
	jsr	Malloc(pc)                      ; Malloc
	move.l	a0,d3                           ; d3 = the block
	tst.l	d3                              ; had?
	bne.s	load_check_size                 ; yes
	lea	alert_no_memory-str_file(a3),a0 ; 'far too little memory'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	jsr	quit_with_error(pc)             ; and end the program
load_check_size:
	move.l	2(a2),d5                        ; text + data + bss + basepage
	add.l	6(a2),d5                        ; + data
	add.l	$a(a2),d5                       ; + bss
	addi.l	#$100,d5                        ; + the basepage
	moveq	#-1,d0                          ; Malloc(-1): the largest free block
	jsr	Malloc(pc)                      ; Malloc
	move.l	a0,d4                           ; d4 = the free memory
	cmp.l	d4,d5                           ; needed - free
	ble.s	load_make_basepage              ; enough memory?
	move.l	d4,-(sp)                        ; free, for the alert
	move.l	d5,-(sp)                        ; needed
	lea	alert_too_big-str_file(a3),a1   ; 'would require %ld bytes'
	lea	8(sp),a0                        ; the text buffer on the stack
	jsr	sprintf(pc)                     ; formatted
	addq.w	#8,sp                           ; drop the arguments
	movea.l	d3,a0                           ; the 64K test block ...
	jsr	Mfree(pc)                       ; ... freed
	lea	(sp),a0                         ; the text
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	bra.w	load_and_unpack_failed          ; give up
load_make_basepage:
	lea	loaded_basepage(pc),a5          ; a5 = loaded_basepage
	clr.l	-(sp)                           ; no environment
	lea	str_empty-str_file(a3),a1       ; empty command line
	suba.l	a0,a0                           ; no file name
	moveq	#5,d0                           ; Pexec 5: create a basepage
	jsr	Pexec(pc)                       ; Pexec
	addq.w	#4,sp                           ; drop the environment
	move.l	d0,(a5)                         ; loaded_basepage
	move.w	#$1,program_loaded              ; the basepage has to be freed
	movea.l	d3,a0                           ; free the 64K test block
	jsr	Mfree(pc)                       ; Mfree
	move.l	(a5),d0                         ; the basepage
	addi.l	#$100,d0                        ; + 256: the text
	movea.l	(a5),a0                         ; basepage
	move.l	d0,8(a0)                        ; p_tbase
	move.l	d0,loaded_text                  ; loaded_text
	add.l	2(a2),d0                        ; + text length: the data
	movea.l	(a5),a0                         ; basepage
	move.l	d0,$10(a0)                      ; p_dbase
	add.l	6(a2),d0                        ; + data length: the bss
	movea.l	(a5),a0                         ; basepage
	move.l	d0,$18(a0)                      ; p_bbase
	movea.l	(a5),a0                         ; basepage
	move.l	2(a2),$c(a0)                    ; p_tlen
	movea.l	(a5),a0                         ; basepage
	move.l	6(a2),$14(a0)                   ; p_dlen
	movea.l	(a5),a0                         ; basepage
	move.l	$a(a2),$1c(a0)                  ; p_blen
	movea.l	(a5),a0                         ; basepage
	lea	$80(a0),a0                      ; its command line
	movea.l	(a5),a1                         ; basepage
	move.l	a0,$20(a1)                      ; p_dta: at the command line
	jsr	show_reading(pc)                ; progress: 'reading...'
	subi.l	#$100,d5                        ; the length without the basepage
	moveq	#0,d4                           ; from byte 0
	bra.s	load_clear_test                 ; clear
load_clear_loop:
	movea.l	loaded_text(pc),a0              ; clear the program memory
	clr.b	0(a0,d4.l)                      ; one byte cleared
	addq.l	#1,d4                           ; next
load_clear_test:
	cmp.l	d4,d5                           ; all of it?
	bgt.s	load_clear_loop                 ; no
	movea.l	loaded_text(pc),a0              ; into the text
	move.l	#$7fffffff,d1                   ; as much as there is
	move.w	file_handle(pc),d0              ; from the open file
	jsr	Fread(pc)                       ; read the rest of the file
	move.l	d0,file_length                  ; file_length: the text, data, symbols and relocation
	move.w	file_handle(pc),d0              ; the file
	jsr	Fclose(pc)                      ; closed
	cmpi.w	#$ffff,$1a(a2)                  ; ph_absflag: no relocation?
	bne.s	load_get_relocation             ; has relocation
	moveq	#0,d5                           ; no relocation
	bra.s	load_check_relocation           ; go on
load_get_relocation:
	movea.l	(a5),a0                         ; the first long of the relocation table, after the data
	movea.l	$18(a0),a1                      ; the bss address: where the relocation table starts
	move.l	(a1),d5                         ; d5 = its first long, 0 for none
load_check_relocation:
	jsr	show_checking(pc)               ; progress: 'checking...'
	tst.l	d5                              ; relocation?
	ble.s	load_clear_bss                  ; none: no need
	jsr	is_known_packer(pc)             ; relocation: is it a packer that is meant to have it?
	tst.w	d0                              ; known?
	bne.s	load_relocate                   ; yes
	lea	alert_not_packed-str_file(a3),a0 ; 'wasn't packed with a known packer'
	moveq	#1,d0                           ; button 1: GO ON
	jsr	form_alert(pc)                  ; alert
	subq.w	#2,d0                           ; CANCEL
	beq.s	load_and_unpack_failed          ; cancelled
load_relocate:
	jsr	relocate_loaded_program(pc)     ; relocate the packed program
load_clear_bss:
	movea.l	(a5),a0                         ; basepage
	movea.l	$18(a0),a0                      ; p_bbase
	movea.l	(a5),a1                         ; basepage
	move.l	$1c(a1),d4                      ; p_blen
	bra.s	load_clear_bss_test             ; clear
load_clear_bss_loop:
	clr.b	(a0)+                           ; clear its bss
	subq.l	#1,d4                           ; one byte less
load_clear_bss_test:
	tst.l	d4                              ; all of it?
	bgt.s	load_clear_bss_loop             ; no
	jsr	clock(pc)                       ; the 200 Hz clock
	move.l	d0,d6                           ; d6 = the start time
	jsr	run_packed_program(pc)          ; unpack
	jsr	clock(pc)                       ; the time now
	sub.l	d6,d0                           ; - the start
	move.l	d0,d6                           ; d6 = the time it took, in 1/200 seconds
	move.l	unpacked_header(pc),d1          ; found?
	bne.s	load_and_unpack_done            ; yes
	lea	alert_cannot_unpack-str_file(a3),a0 ; 'Sorry, I couldn't unpack'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
load_and_unpack_failed:
	clr.w	d0                              ; d0 = 0: failed
	bra.w	load_and_unpack_return          ; return
load_and_unpack_done:
	move.w	show_statistics(pc),d0          ; statistics?
	beq.s	load_and_unpack_ok              ; no
	lea	$190(sp),a0                     ; the time in ticks as a double
	move.l	d6,d0                           ; d6, the ticks
	jsr	fp_from_long(pc)                ; as a long double
	lea	$190(sp),a0                     ; the ticks
	lea	ticks_per_second-str_file(a3),a1 ; 200.0
	jsr	ext_fdiv(pc)                    ; / 200: seconds
	lea	$19a(sp),a0                     ; past the seconds
	move.l	-(a0),-(sp)                     ; push the seconds (10 bytes)
	move.l	-(a0),-(sp)
	move.w	-(a0),-(sp)
	moveq	#37,d0                          ; '%'
	move.w	d0,-(sp)                        ; push '%'
	lea	$19c(sp),a0                     ; packed length
	move.l	file_length(pc),d0
	jsr	fp_from_long(pc)                ; as a long double
	lea	$19c(sp),a0                     ; the packed length
	lea	hundred_percent-str_file(a3),a1 ; 100.0
	jsr	ext_fmul(pc)                    ; * 100
	move.l	unpacked_end(pc),d0             ; the unpacked end
	sub.l	unpacked_header(pc),d0          ; - its start: the unpacked length
	lea	$19c(sp),a0                     ; the packed length * 100
	jsr	fdiv_long(pc)                   ; / unpacked length: the compression ratio
	lea	$1a6(sp),a0                     ; past the ratio
	move.l	-(a0),-(sp)                     ; push the ratio (10 bytes)
	move.l	-(a0),-(sp)
	move.w	-(a0),-(sp)
	movea.l	unpacked_end(pc),a0             ; the unpacked end
	suba.l	unpacked_header,a0              ; - its start
	move.l	a0,-(sp)                        ; push the unpacked length
	move.l	file_length(pc),-(sp)           ; push the packed length
	lea	alert_statistics-str_file(a3),a1 ; 'Packed size: %ld bytes ...'
	lea	$1e(sp),a0                      ; the text buffer
	jsr	sprintf(pc)                     ; formatted
	lea	$1e(sp),sp                      ; drop the arguments
	lea	(sp),a0                         ; the text
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
load_and_unpack_ok:
	moveq	#1,d0                           ; d0 = 1: unpacked
load_and_unpack_return:
	lea	$19a(sp),sp                     ; drop the buffers
	movem.l	(sp)+,d3-d6/a2-a3/a5            ; restore the registers
	rts

;------------------------------------------------------------------------------
; select_file(a0 = path, a1 = name, title on the stack, button on the stack): fsel_exinput when the
; AES has it, fsel_input otherwise.  Ends the program after an alert if the call fails.
;------------------------------------------------------------------------------
select_file:	; from: unpack_and_save, main
	movem.l	d3/a2-a4,-(sp)                  ; keep the registers used
	movea.l	a0,a4                           ; a4 = the path
	movea.l	a1,a3                           ; a3 = the name
	movea.l	$14(sp),a2                      ; a2 = the button result
	move.w	has_fsel_exinput(pc),d0         ; fsel_exinput?
	beq.s	select_file_old                 ; no: fsel_input
	move.l	$18(sp),-(sp)                   ; the title
	move.l	a2,-(sp)                        ; the button result
	jsr	fsel_exinput(pc)                ; with a title
	addq.w	#8,sp                           ; drop the arguments
	move.w	d0,d3                           ; d3 = 0 for an error
	bra.s	select_file_check               ; check
select_file_old:
	move.l	a2,-(sp)                        ; the button result
	movea.l	a3,a1                           ; the name
	movea.l	a4,a0                           ; the path
	jsr	fsel_input(pc)                  ; without a title (TOS before 1.4)
	addq.w	#4,sp                           ; drop the argument
	move.w	d0,d3                           ; d3 = 0 for an error
select_file_check:
	tst.w	d3                              ; an error?
	bne.s	select_file_done                ; no
	lea	alert_fsel_error(pc),a0         ; 'Error during fsel_input()!'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	jsr	close_gem(pc)                   ; GEM off
	moveq	#1,d0                           ; status 1
	jsr	exit(pc)                        ; end the program
select_file_done:
	movem.l	(sp)+,d3/a2-a4                  ; restore the registers
	rts

;------------------------------------------------------------------------------
; Reads the setup dialog's two check boxes into save_screen and show_statistics.
;------------------------------------------------------------------------------
read_setup:	; from: init_gem, main
	lea	tree_setup_ptr(pc),a0           ; show_statistics ...
	moveq	#1,d0                           ; bit 0: SELECTED
	movea.l	(a0),a1                         ; the setup tree
	and.w	$9a(a1),d0                      ; ... from object 6
	subq.w	#1,d0                           ; selected?
	bne.s	read_setup_stats_off            ; no
	moveq	#1,d1                           ; on
	bra.s	read_setup_screen               ; store it
read_setup_stats_off:
	clr.w	d1                              ; off
read_setup_screen:
	move.w	d1,show_statistics-tree_setup_ptr(a0) ; show_statistics
	moveq	#1,d0                           ; bit 0: SELECTED
	movea.l	(a0),a1                         ; the setup tree
	and.w	$6a(a1),d0                      ; object 4
	subq.w	#1,d0                           ; selected?
	bne.s	read_setup_screen_off           ; no
	moveq	#1,d2                           ; on
	bra.s	read_setup_store                ; store it
read_setup_screen_off:
	clr.w	d2                              ; off
read_setup_store:
	move.w	d2,save_screen-tree_setup_ptr(a0) ; save_screen
	rts

;------------------------------------------------------------------------------
; Returns in d0 the number of times d0 can be halved before it reaches 0: the planes for a colour count.
;------------------------------------------------------------------------------
bits_needed:	; from: init_gem
	clr.w	d1                              ; no halvings yet
	bra.s	bits_needed_halve               ; start halving
bits_needed_count:
	addq.w	#1,d1                           ; one more
bits_needed_halve:
	asr.w	#1,d0                           ; halve
	tst.w	d0                              ; still above 0?
	bgt.s	bits_needed_count               ; yes: count it
	move.w	d1,d0                           ; d0 = the count
	rts

;------------------------------------------------------------------------------
; Starts GEM: appl_init, the arrow mouse, checks the AES version for fsel_exinput (1.40 to
; 2.00, or 3.00 on), fixes the 51 objects with rsrc_obfix, centres the four dialogs, reads the
; setup, and works out screen_size from the width, height and colours a VDI workstation opened just
; for that reports.  Ends the program after an alert when appl_init fails.
;------------------------------------------------------------------------------
init_gem:	; from: main
	movem.l	d3/a2-a3,-(sp)                  ; keep the registers used
	lea	-$8a(sp),sp                     ; room for work_in and work_out
	lea	vdi_work_in(pc),a0              ; from vdi_work_in
	lea	(sp),a1                         ; to the stack
	moveq	#21,d0                          ; 22 bytes
init_gem_copy_work_in:
	move.b	(a0)+,(a1)+                     ; copy vdi_work_in
	dbra	d0,init_gem_copy_work_in        ; all of it
	lea	tree_progress_ptr(pc),a3        ; a3 = the GEM variables
	jsr	appl_init(pc)
	move.w	d0,ap_id-tree_progress_ptr(a3)  ; ap_id
	bge.s	init_gem_check_aes              ; all right
	lea	alert_appl_init(pc),a0          ; 'Can't appl_init()'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	jsr	appl_exit(pc)                   ; end the application
	moveq	#1,d0                           ; status 1
	jsr	exit(pc)                        ; end the program
init_gem_check_aes:
	suba.l	a0,a0                           ; no form
	clr.w	d0                              ; ARROW
	jsr	graf_mouse(pc)                  ; graf_mouse(ARROW)
	move.w	aes_global,d0                   ; global[0]: the AES version
	cmp.w	#$140,d0                        ; before 1.40?
	blt.s	init_gem_check_aes_3            ; yes: check for 3.00
	cmp.w	#$200,d0                        ; up to 2.00?
	ble.s	init_gem_exinput                ; yes: it has fsel_exinput
init_gem_check_aes_3:
	cmp.w	#$300,d0                        ; 3.00 or later?
	blt.s	init_gem_trees                  ; no: fsel_input only
init_gem_exinput:
	move.w	#$1,has_fsel_exinput            ; fsel_exinput can be used
init_gem_trees:
	lea	tree_main(pc),a2                ; a2 = the first tree
	move.l	a2,tree_main_ptr-tree_progress_ptr(a3) ; tree_main_ptr
	move.l	#tree_info,tree_info_ptr-tree_progress_ptr(a3) ; tree_info_ptr
	move.l	#tree_progress,(a3)             ; tree_progress_ptr
	move.l	#tree_setup,tree_setup_ptr-tree_progress_ptr(a3) ; tree_setup_ptr
	clr.w	d3                              ; from object 0
	bra.s	init_gem_obfix_test             ; fix
init_gem_obfix_loop:
	move.w	d3,d0                           ; rsrc_obfix every object
	movea.l	a2,a0                           ; counted from the first tree
	jsr	rsrc_obfix(pc)                  ; character to pixel coordinates
	addq.w	#1,d3                           ; next object
init_gem_obfix_test:
	cmp.w	#$33,d3                         ; all 51?
	blt.s	init_gem_obfix_loop             ; no
	movea.l	(a3),a0                         ; the progress box
	move.l	$24(a0),progress_file_text-tree_progress_ptr(a3) ; object 1's string: 'File: ...'
	movea.l	(a3),a0                         ; the progress box
	move.l	$3c(a0),progress_status_text-tree_progress_ptr(a3) ; object 2: 'unpacking...'
	movea.l	(a3),a0                         ; the progress box
	move.l	$54(a0),progress_size_text-tree_progress_ptr(a3) ; object 3: 'Size: ...'
	movea.l	tree_main_ptr-tree_progress_ptr(a3),a0 ; the main dialog
	pea	$16(a0)                         ; &ob_height
	pea	$14(a0)                         ; &ob_width
	pea	$12(a0)                         ; &ob_y
	movea.l	a0,a1                           ; the tree
	lea	$10(a1),a1                      ; &ob_x
	jsr	form_center(pc)                 ; centred
	lea	$c(sp),sp                       ; drop the arguments
	movea.l	tree_info_ptr-tree_progress_ptr(a3),a0 ; the info dialog
	pea	$16(a0)                         ; &ob_height
	pea	$14(a0)                         ; &ob_width
	pea	$12(a0)                         ; &ob_y
	movea.l	a0,a1                           ; the tree
	lea	$10(a1),a1                      ; &ob_x
	jsr	form_center(pc)                 ; centred
	lea	$c(sp),sp                       ; drop the arguments
	movea.l	(a3),a0                         ; the progress box
	pea	$16(a0)                         ; &ob_height
	pea	$14(a0)                         ; &ob_width
	pea	$12(a0)                         ; &ob_y
	movea.l	a0,a1                           ; the tree
	lea	$10(a1),a1                      ; &ob_x
	jsr	form_center(pc)                 ; centred
	lea	$c(sp),sp                       ; drop the arguments
	movea.l	tree_setup_ptr-tree_progress_ptr(a3),a0 ; the setup dialog
	pea	$16(a0)                         ; &ob_height
	pea	$14(a0)                         ; &ob_width
	pea	$12(a0)                         ; &ob_y
	movea.l	a0,a1                           ; the tree
	lea	$10(a1),a1                      ; &ob_x
	jsr	form_center(pc)                 ; centred
	lea	$c(sp),sp                       ; drop the arguments
	jsr	read_setup(pc)                  ; the check boxes
	pea	$18(sp)                         ; &handle
	lea	$1a(sp),a1                      ; work_out
	lea	4(sp),a0                        ; work_in
	jsr	v_opnvwk(pc)                    ; v_opnvwk, only to read the screen
	addq.w	#4,sp                           ; drop the argument
	moveq	#1,d0                           ; work_out[0] + 1: the width
	add.w	$18(sp),d0
	ext.l	d0
	moveq	#1,d1                           ; width * height
	add.w	$1a(sp),d1                      ; work_out[1] + 1: the height
	ext.l	d1
	jsr	lmul(pc)                        ; pixels
	move.l	d0,-(sp)                        ; kept
	move.w	$36(sp),d0                      ; colours
	jsr	bits_needed(pc)                 ; planes
	move.w	d0,d1                           ; as a long
	ext.l	d1
	move.l	(sp)+,d0                        ; the pixels
	jsr	lmul(pc)                        ; * planes
	asr.l	#3,d0                           ; / 8: bytes
	move.l	d0,screen_size-tree_progress_ptr(a3) ; screen_size
	move.w	$16(sp),d0                      ; the handle
	jsr	v_clsvwk(pc)                    ; v_clsvwk at once
	lea	$8a(sp),sp
	movem.l	(sp)+,d3/a2-a3
	rts

;------------------------------------------------------------------------------
; Sets load_path to the current drive and path with '\', save_path to the same, and setup_path to it with '*.PRG'.
;------------------------------------------------------------------------------
init_paths:	; from: main
	move.l	a2,-(sp)                        ; keep a2
	lea	load_path(pc),a2                ; a2 = load_path
	lea	dta-load_path(a2),a0            ; the DTA
	jsr	Fsetdta(pc)
	jsr	Dgetdrv(pc)
	addi.b	#$41,d0                         ; 'A' +
	move.b	d0,(a2)                         ; the drive letter
	move.b	#$3a,1(a2)                      ; ':'
	clr.w	d0                              ; the current drive
	lea	2(a2),a0                        ; after the colon
	jsr	Dgetpath(pc)
	lea	str_backslash(pc),a1
	movea.l	a2,a0                           ; load_path
	jsr	strcat(pc)                      ; + a backslash
	movea.l	a2,a1                           ; from load_path
	lea	save_path-load_path(a2),a0      ; to save_path
	jsr	strcpy(pc)                      ; save_path = load_path
	clr.b	load_name-load_path(a2)         ; no names yet
	clr.b	save_name-load_path(a2)
	movea.l	a2,a1                           ; from load_path
	lea	setup_path-load_path(a2),a0     ; to setup_path
	jsr	strcpy(pc)                      ; copied
	lea	str_prg_mask(pc),a1             ; '*.PRG'
	lea	setup_path-load_path(a2),a0     ; setup_path
	jsr	strcat(pc)                      ; appended
	movea.l	(sp)+,a2                        ; restore a2
	rts

;------------------------------------------------------------------------------
; Frees the resource and ends the application.
;------------------------------------------------------------------------------
close_gem:	; from: quit_with_error, select_file, main
	jsr	rsrc_free(pc)                   ; the resource
	jsr	appl_exit(pc)                   ; the application
	rts

;------------------------------------------------------------------------------
; UNPACK: asks for the program to unpack, loads and unpacks it (saving and restoring the screen when
; the setup says so), then asks for a name and writes the unpacked program.  A failed write deletes
; the file and asks again.
;------------------------------------------------------------------------------
unpack_and_save:	; from: main
	movem.l	d3/a2-a6,-(sp)                  ; keep the registers used
	lea	-$166(sp),sp                    ; room for the path and the alert text
	lea	$66(sp),a2                      ; a2 = the path for the file selector
	lea	file_handle(pc),a6              ; a6 = the file variables
	lea	load_path-file_handle(a6),a1    ; from load_path
	movea.l	a2,a0                           ; to the path
	jsr	strcpy(pc)                      ; copied
	lea	str_file(pc),a3                 ; a3 = the base of the strings
	lea	str_all_mask-str_file(a3),a1    ; + '*.*'
	movea.l	a2,a0                           ; the path
	jsr	strcat(pc)                      ; appended
	pea	str_choose_input-str_file(a3)   ; the title
	pea	4(sp)                           ; the button result
	lea	load_name-file_handle(a6),a1    ; the name
	movea.l	a2,a0                           ; the path
	jsr	select_file(pc)                 ; 'Choose a file to unpack:'
	addq.w	#8,sp                           ; drop the arguments
	move.w	(sp),d0                         ; the button
	beq.w	unpack_and_save_done            ; Cancel
	movea.l	a2,a0                           ; the path
	moveq	#92,d0                          ; a backslash
	jsr	strrchr(pc)                     ; the last backslash
	movea.l	a0,a5                           ; a5 = where it is
	move.l	a5,d0                           ; found?
	bne.s	unpack_keep_path                ; yes
	lea	-$1(a2),a5                      ; no: before the path
unpack_keep_path:
	clr.b	1(a5)                           ; keep the path only
	movea.l	a2,a1                           ; from the path
	lea	load_path-file_handle(a6),a0    ; to load_path
	jsr	strcpy(pc)                      ; copied
	lea	load_name-file_handle(a6),a1    ; + the name
	movea.l	a2,a0                           ; the path
	jsr	strcat(pc)                      ; appended: the full name
	clr.w	d0                              ; read
	movea.l	a2,a0                           ; the full name
	jsr	Fopen(pc)                       ; Fopen(read)
	move.w	d0,(a6)                         ; file_handle
	bge.s	unpack_check_save_screen        ; opened
	lea	alert_file_not_found-str_file(a3),a0 ; 'File not found!'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	bra.w	unpack_and_save_done            ; give up
unpack_check_save_screen:
	move.w	save_screen-file_handle(a6),d0  ; save the screen?
	beq.s	unpack_without_screen           ; no
	move.l	screen_size-file_handle(a6),d0  ; its size
	jsr	Malloc(pc)                      ; Malloc
	movea.l	a0,a4                           ; a4 = the copy
	move.l	a4,d0                           ; had?
	bne.s	unpack_save_screen              ; yes
	lea	alert_no_screen_memory-str_file(a3),a0 ; 'Insufficient memory for screen-saving!'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	bra.s	unpack_without_screen           ; unpack anyway
unpack_save_screen:
	jsr	Logbase(pc)                     ; Logbase
	movea.l	a0,a1                           ; from the screen
	movea.l	a4,a0                           ; to the copy
	move.l	screen_size-file_handle(a6),d0  ; the size
	jsr	memcpy(pc)                      ; copy the screen
	jsr	load_and_unpack(pc)             ; unpack
	move.w	d0,d3                           ; d3 = 1 if unpacked
	jsr	Logbase(pc)                     ; the screen
	movea.l	a4,a1                           ; from the copy
	move.l	screen_size-file_handle(a6),d0  ; the size
	jsr	memcpy(pc)                      ; restore it
	bra.s	unpack_unpacked                 ; go on
unpack_without_screen:
	jsr	load_and_unpack(pc)             ; unpack
	move.w	d0,d3                           ; d3 = 1 if unpacked
unpack_unpacked:
	jsr	close_progress(pc)              ; no progress box
	tst.w	d3                              ; unpacked?
	beq.w	free_loaded_program             ; nothing unpacked
	clr.b	1(a5)                           ; the path only again
	lea	load_name-file_handle(a6),a1    ; from load_name
	lea	save_name-file_handle(a6),a0    ; to save_name
	jsr	strcpy(pc)                      ; save_name = load_name
choose_save_name:
	lea	save_path-file_handle(a6),a1    ; from save_path
	movea.l	a2,a0                           ; to the path
	jsr	strcpy(pc)                      ; copied
	lea	str_all_mask-str_file(a3),a1    ; + '*.*'
	movea.l	a2,a0                           ; the path
	jsr	strcat(pc)                      ; appended
	pea	str_choose_output-str_file(a3)  ; the title
	pea	4(sp)                           ; the button result
	lea	save_name-file_handle(a6),a1    ; the name
	movea.l	a2,a0                           ; the path
	jsr	select_file(pc)                 ; 'Choose a name for the new file:'
	addq.w	#8,sp                           ; drop the arguments
	move.w	(sp),d0                         ; the button
	beq.w	free_loaded_program             ; Cancel
	movea.l	a2,a0                           ; the path
	moveq	#92,d0                          ; a backslash
	jsr	strrchr(pc)                     ; the last one
	movea.l	a0,a5                           ; a5 = where it is
	move.l	a5,d0                           ; found?
	bne.s	save_keep_path                  ; yes
	lea	-$1(a2),a5                      ; no: before the path
save_keep_path:
	clr.b	1(a5)                           ; the path only
	movea.l	a2,a1                           ; from the path
	lea	save_path-file_handle(a6),a0    ; to save_path
	jsr	strcpy(pc)                      ; copied
	lea	save_name-file_handle(a6),a1    ; + the name
	movea.l	a2,a0                           ; the path
	jsr	strcat(pc)                      ; appended: the full name
	clr.w	d0                              ; read
	movea.l	a2,a0                           ; the full name
	jsr	Fopen(pc)                       ; does it exist?
	move.w	d0,(a6)                         ; file_handle
	blt.s	save_create                     ; not there: create it
	jsr	Fclose(pc)                      ; close it again
	pea	(a2)                            ; the name
	lea	alert_overwrite-str_file(a3),a1 ; 'Overwrite existing file %s ?'
	lea	6(sp),a0                        ; the text buffer
	jsr	sprintf(pc)                     ; formatted
	addq.w	#4,sp                           ; drop the argument
	lea	2(sp),a0                        ; the text
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; 'Overwrite?'
	subq.w	#2,d0                           ; button 2?
	beq.w	choose_save_name                ; NO: choose again
save_create:
	clr.w	d0                              ; normal file
	movea.l	a2,a0                           ; the full name
	jsr	Fcreate(pc)                     ; Fcreate
	move.w	d0,(a6)                         ; file_handle
	tst.w	d0                              ; created?
	blt.s	save_create_failed              ; no: a write error
	move.l	unpacked_end-file_handle(a6),d1 ; the unpacked length
	sub.l	unpacked_header-file_handle(a6),d1 ; - unpacked_header
	move.l	d1,save_length-file_handle(a6)  ; save_length
	jsr	show_writing(pc)                ; progress: 'writing...'
	movea.l	unpacked_header-file_handle(a6),a0 ; from the unpacked header
	move.l	save_length-file_handle(a6),d1  ; save_length bytes
	move.w	(a6),d0                         ; to the file
	jsr	Fwrite(pc)                      ; Fwrite the unpacked program
	move.l	d0,d3                           ; d3 = bytes written
	bra.s	save_close                      ; close it
save_create_failed:
	move.l	save_length-file_handle(a6),d3  ; as if all were written
save_close:
	move.w	(a6),d0                         ; the file
	jsr	Fclose(pc)                      ; closed
	jsr	close_progress(pc)              ; the progress box down
	cmp.l	save_length-file_handle(a6),d3  ; all written?
	bge.s	free_loaded_program             ; yes: done
	movea.l	a2,a0                           ; the full name
	jsr	Fdelete(pc)                     ; Fdelete the part
	lea	alert_write_error-str_file(a3),a0 ; 'Write error!'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	bra.w	choose_save_name                ; choose again
free_loaded_program:
	move.w	program_loaded(pc),d0           ; memory to free?
	beq.s	unpack_and_save_done            ; no
	movea.l	loaded_basepage-file_handle(a6),a0 ; the basepage
	movea.l	$2c(a0),a0                      ; p_env
	jsr	Mfree(pc)                       ; Mfree the environment
	movea.l	loaded_basepage-file_handle(a6),a0 ; the basepage
	jsr	Mfree(pc)                       ; Mfree the basepage
	clr.w	program_loaded                  ; freed
unpack_and_save_done:
	lea	$166(sp),sp                     ; drop the buffers
	movem.l	(sp)+,d3/a2-a6                  ; restore the registers
	rts

;------------------------------------------------------------------------------
; The main dialog: UNPACK, INFO and EXIT, and the title box, which opens the setup dialog.  The
; setup's SAVE writes the two check boxes into NAUGHTY.PRG at file offsets $1e and $1f, which needs
; the original packed file, 13320 bytes long.
;------------------------------------------------------------------------------
main:	; from: start
	movem.l	d3-d4/a2-a6,-(sp)               ; keep the registers used
	lea	-$42(sp),sp                     ; room for a file name
	jsr	init_paths(pc)                  ; the paths
	jsr	init_gem(pc)                    ; GEM, the dialogs and the setup
	lea	str_file(pc),a2                 ; a2 = the base of the strings
	lea	2(sp),a3                        ; a3 = the name buffer
	lea	str_naughty_prg-str_file(a2),a1 ; 'NAUGHTY.PRG'
	movea.l	a3,a0                           ; the name buffer
	jsr	strcpy(pc)                      ; copied
	moveq	#3,d0                           ; BEG_MCTRL
	jsr	wind_update(pc)                 ; wind_update(BEG_MCTRL)
	moveq	#1,d0                           ; BEG_UPDATE
	jsr	wind_update(pc)                 ; wind_update(BEG_UPDATE)
	lea	setup_path(pc),a4               ; a4 = setup_path, the base of the GEM variables
	movea.l	tree_main_ptr-setup_path(a4),a0 ; the main dialog
	clr.w	d0                              ; FMD_START
	jsr	form_dial_tree(pc)              ; FMD_START
main_loop:
	lea	tree_setup_ptr-setup_path(a4),a5 ; a5 = &tree_setup_ptr
	clr.w	d0                              ; from the root
	movea.l	tree_main_ptr-setup_path(a4),a0 ; the main dialog
	jsr	draw_tree(pc)                   ; drawn
	clr.w	d0                              ; no edit field
	movea.l	tree_main_ptr-setup_path(a4),a0 ; the main dialog
	jsr	form_do(pc)                     ; form_do
	move.w	d0,d3                           ; d3 = the exit object
	andi.w	#$7fff,d3                       ; the object, without the double-click bit
	move.w	d3,d1                           ; the object
	ext.l	d1                              ; as a long
	move.l	d1,d0
	add.l	d0,d0                           ; * 2
	add.l	d1,d0                           ; * 3
	lsl.l	#3,d0                           ; * 24: its offset
	movea.l	tree_main_ptr-setup_path(a4),a0 ; the main dialog
	andi.w	#$fffe,$a(a0,d0.l)              ; deselect it
	movea.l	tree_main_ptr-setup_path(a4),a0 ; the main dialog
	move.w	d3,d0                           ; from the object
	jsr	draw_tree(pc)                   ; redrawn
	move.w	d3,d0                           ; the object
	subq.w	#3,d0                           ; - 3
	beq.w	main_unpack                     ; 3: UNPACK
	subq.w	#1,d0                           ; - 4
	beq.w	main_info                       ; 4: INFO
	subq.w	#1,d0                           ; - 5
	beq.w	main_exit                       ; 5: EXIT
	subq.w	#6,d0                           ; - 11
	beq.s	setup_dialog                    ; 11: the title box
	bra.s	main_loop                       ; anything else: again
setup_dialog:
	movea.l	(a5),a0                         ; the setup dialog
	clr.w	d0                              ; FMD_START
	jsr	form_dial_tree(pc)
	clr.w	d0                              ; from the root
	movea.l	(a5),a0                         ; the setup dialog
	jsr	draw_tree(pc)                   ; drawn
	clr.w	d0                              ; no edit field
	movea.l	(a5),a0                         ; the setup dialog
	jsr	form_do(pc)                     ; until BACK or SAVE
	move.w	d0,d3                           ; d3 = the exit object
	ext.l	d0                              ; as a long
	move.l	d0,d1
	add.l	d1,d1                           ; * 2
	add.l	d0,d1                           ; * 3
	lsl.l	#3,d1                           ; * 24
	movea.l	(a5),a0                         ; the setup dialog
	andi.w	#$fffe,$a(a0,d1.l)              ; deselect it
	movea.l	(a5),a0                         ; the setup dialog
	moveq	#3,d0                           ; FMD_FINISH
	jsr	form_dial_tree(pc)
	jsr	read_setup(pc)                  ; take the check boxes
	cmp.w	#$8,d3                          ; 8: SAVE
	bne.w	main_loop                       ; BACK: the main dialog again
save_setup:
	pea	str_locate_naughty-str_file(a2) ; the title
	pea	4(sp)                           ; the button result
	movea.l	a3,a1                           ; the name: 'NAUGHTY.PRG'
	movea.l	a4,a0                           ; the path
	jsr	select_file(pc)                 ; 'Please locate NAUGHTY.PRG:'
	addq.w	#8,sp                           ; drop the arguments
	move.w	(sp),d0                         ; the button
	beq.w	main_loop                       ; Cancel
	movea.l	a4,a0                           ; the path
	moveq	#92,d0                          ; a backslash
	jsr	strrchr(pc)                     ; the last one
	movea.l	a0,a6                           ; a6 = where it is
	addq.w	#1,a6                           ; after it
	clr.b	(a6)                            ; the path only
	movea.l	a3,a1                           ; + the name
	movea.l	a4,a0                           ; the path
	jsr	strcat(pc)                      ; appended: the full name
	moveq	#2,d0                           ; read/write
	movea.l	a4,a0                           ; the full name
	jsr	Fopen(pc)                       ; Fopen(read/write)
	move.l	d0,d4                           ; d4 = the handle
	clr.b	(a6)                            ; the path only again
	lea	str_prg_mask-str_file(a2),a1    ; + '*.PRG'
	movea.l	a4,a0                           ; the path
	jsr	strcat(pc)                      ; appended: the mask for next time
	tst.w	d4                              ; opened?
	bge.s	check_program_length            ; yes
	cmp.w	#$ffdf,d4                       ; file not found?
	bne.w	main_loop                       ; another error: give up
	lea	alert_naughty_not_found-str_file(a2),a0 ; 'File not found!'
	moveq	#2,d0                           ; button 2
	jsr	form_alert(pc)                  ; Retry|Cancel
	subq.w	#1,d0                           ; Retry?
	bne.s	close_program_file              ; Cancel
	bra.s	save_setup                      ; Retry
check_program_length:
	moveq	#2,d2                           ; from the end
	move.w	d4,d1                           ; the handle
	moveq	#0,d0                           ; offset 0
	jsr	Fseek(pc)                       ; Fseek to the end: the file length
	cmp.l	#$3408,d0                       ; the original, packed NAUGHTY.PRG?
	beq.s	save_setup_write                ; yes
	lea	alert_setup_needs_original-str_file(a2),a0 ; 'the program file NAUGHTY.PRG must be unmodified!'
	moveq	#1,d0                           ; button 1
	jsr	form_alert(pc)                  ; alert
	bra.s	close_program_file              ; close it
save_setup_write:
	clr.w	d2                              ; from the start
	move.w	d4,d1                           ; the handle
	move.l	#$1e,d0                         ; offset $1e
	jsr	Fseek(pc)                       ; Fseek($1e)
	movea.l	(a5),a0                         ; the setup dialog
	lea	$6b(a0),a0                      ; save_screen: object 4 ob_state
	moveq	#1,d1                           ; 1 byte
	move.w	d4,d0                           ; the handle
	jsr	Fwrite(pc)                      ; Fwrite 1 byte
	clr.w	d2                              ; from the start
	move.w	d4,d1                           ; the handle
	move.l	#$1f,d0                         ; offset $1f
	jsr	Fseek(pc)                       ; Fseek($1f)
	movea.l	(a5),a0                         ; the setup dialog
	lea	$9b(a0),a0                      ; show_statistics: object 6 ob_state
	moveq	#1,d1                           ; 1 byte
	move.w	d4,d0                           ; the handle
	jsr	Fwrite(pc)                      ; written
close_program_file:
	move.w	d4,d0                           ; the handle
	jsr	Fclose(pc)                      ; closed
	bra.w	main_loop                       ; back to the main dialog
main_unpack:
	jsr	unpack_and_save(pc)             ; choose, unpack and save
	bra.w	main_loop                       ; back to the main dialog
main_info:
	movea.l	tree_info_ptr-setup_path(a4),a0 ; the info dialog
	clr.w	d0                              ; FMD_START
	jsr	form_dial_tree(pc)
	clr.w	d0                              ; from the root
	movea.l	tree_info_ptr-setup_path(a4),a0 ; the info dialog
	jsr	draw_tree(pc)                   ; drawn
	clr.w	d0                              ; no edit field
	movea.l	tree_info_ptr-setup_path(a4),a0 ; the info dialog
	jsr	form_do(pc)                     ; until BACK
	move.w	d0,d3                           ; d3 = the exit object
	ext.l	d0                              ; as a long
	move.l	d0,d1
	add.l	d1,d1                           ; * 2
	add.l	d0,d1                           ; * 3
	lsl.l	#3,d1                           ; * 24
	movea.l	tree_info_ptr-setup_path(a4),a0 ; the info dialog
	andi.w	#$fffe,$a(a0,d1.l)              ; deselect it
	movea.l	tree_info_ptr-setup_path(a4),a0 ; the info dialog
	moveq	#3,d0                           ; FMD_FINISH
	jsr	form_dial_tree(pc)
	bra.w	main_loop                       ; back to the main dialog
main_exit:
	movea.l	tree_main_ptr-setup_path(a4),a0 ; the main dialog
	moveq	#3,d0                           ; FMD_FINISH
	jsr	form_dial_tree(pc)              ; FMD_FINISH
	moveq	#2,d0                           ; END_MCTRL
	jsr	wind_update(pc)                 ; wind_update(END_MCTRL)
	clr.w	d0                              ; END_UPDATE
	jsr	wind_update(pc)                 ; wind_update(END_UPDATE)
	jsr	close_gem(pc)                   ; GEM off
	clr.w	d0                              ; status 0
	jsr	exit(pc)                        ; end the program
	bra.w	main_loop                       ; never reached
	lea	$42(sp),sp                      ; never reached
	movem.l	(sp)+,d3-d4/a2-a6               ; never reached
	rts                                     ; never reached

;------------------------------------------------------------------------------
; printf formatting engine: walks the format string and sends text to an output function
; a0 = format string, a1 = argument list, 4(sp) = output function (a0 = text, d0.l = length)
; returns d0 = characters output, or -1 for a bad conversion; changes d0-d2/a0-a1
; literal text goes out in runs; each % takes flags, width (* or digits), precision (.* or .digits),
; l/L (long) or h (ignored), then the conversion character is dispatched through fmt_jump_table
; flags in d5: bit 0 space, 1 #, 2 +, 3 -, 4 0, 5 upper case, 15 long; d6 width, d2 precision
; a2 = format pointer, a3 = argument pointer, a4 = output function, d3 = count, d4 = %
;------------------------------------------------------------------------------
do_printf:	; from: sprintf
	movem.l	d3-d6/a2-a4,-(sp)
	subq.w	#6,sp                           ; locals: strtol end pointer, character buffer
	movea.l	a0,a2                           ; a2 = format
	movea.l	a1,a3                           ; a3 = arguments
	movea.l	$26(sp),a4                      ; a4 = output function
	clr.w	d3                              ; characters output = 0
	moveq	#37,d4                          ; d4 = '%'
do_printf_next_text:
	moveq	#-1,d0                          ; run length - 1
	movea.l	a2,a0                           ; a0 = start of the run
do_printf_count_text:
	addq.w	#1,d0                           ; run length + 1
	move.b	(a2)+,d5                        ; next character
	beq.w	fmt_done                        ; end of the format: output the run and finish
	cmp.b	d4,d5                           ; '%'?
	bne.s	do_printf_count_text            ; no: keep counting
	tst.w	d0                              ; any text before the %?
	beq.s	do_printf_flags                 ; no
	add.w	d0,d3                           ; add it to the count
	ext.l	d0                              ; length as a long
	jsr	(a4)                            ; output the run
do_printf_flags:
	clr.w	d5                              ; no flags yet
do_printf_flag_loop:
	move.b	(a2)+,d0                        ; next character
	beq.w	fmt_error                       ; end of the format inside a conversion: error
	clr.w	d1                              ; index from the character
	move.b	d0,d1                           ; character
	subi.b	#$20,d1                         ; minus ' '
	cmp.b	#$10,d1                         ; past '0'?
	bhi.s	do_printf_width                 ; yes: not a flag
	move.b	printf_flag_bits(pc,d1.w),d1    ; flag bit for the character, or -1
	bmi.s	do_printf_width                 ; not a flag
	or.b	d1,d5                           ; add the flag
	bra.s	do_printf_flag_loop             ; next character
printf_flag_bits:
	dc.w	$01ff,$ff02,$ffff,$ffff,$ffff,$ff04,$ff08,$ffff ; flag bits from ' ': space 1, # 2, + 4, - 8, 0 $10,
                                                ;   else -1
	dc.w	$1000                           ; '0': $10
do_printf_width:
	moveq	#-1,d6                          ; width: none
	cmp.b	#$2a,d0                         ; '*'?
	bne.s	do_printf_width_digits          ; no: digits?
	move.w	(a3)+,d6                        ; width from the arguments
	bra.s	do_printf_after_width           ; read the next character
do_printf_width_digits:
	move.b	d0,d1                           ; digit?
	subi.b	#$30,d1                         ; minus '0'
	cmp.b	#$9,d1                          ; above 9?
	bhi.s	do_printf_precision             ; not a digit: no width
	lea	-$1(a2),a0                      ; a0 = the number
	lea	(sp),a1                         ; a1 = &end pointer
	moveq	#10,d0                          ; base 10
	bsr.w	strtoul                         ; read the width
	movea.l	(sp),a2                         ; a2 = after the number
	cmp.l	#$7fff,d0                       ; above 32767?
	bhi.w	fmt_error                       ; yes: error
	move.w	d0,d6                           ; width
do_printf_after_width:
	move.b	(a2)+,d0                        ; next character
	beq.w	fmt_error                       ; end: error
do_printf_precision:
	moveq	#-1,d2                          ; precision: none
	cmp.b	#$2e,d0                         ; '.'?
	bne.s	do_printf_size                  ; no
	move.b	(a2)+,d0                        ; character after the point
	cmp.b	#$2a,d0                         ; '*'?
	bne.s	do_printf_precision_digits      ; no: digits
	move.w	(a3)+,d2                        ; precision from the arguments
	bra.s	do_printf_after_precision       ; read the next character
do_printf_precision_digits:
	subi.b	#$30,d0                         ; minus '0'
	cmp.b	#$9,d0                          ; above 9?
	bhi.s	do_printf_size                  ; no digits: no precision
	lea	-$1(a2),a0                      ; a0 = the number
	lea	(sp),a1                         ; a1 = &end pointer
	moveq	#10,d0                          ; base 10
	bsr.w	strtoul                         ; read the precision
	movea.l	(sp),a2                         ; a2 = after the number
	cmp.l	#$7fff,d0                       ; above 32767?
	bhi.w	fmt_error                       ; yes: error
	move.w	d0,d2                           ; precision
do_printf_after_precision:
	move.b	(a2)+,d0                        ; next character
	beq.w	fmt_error                       ; end: error
do_printf_size:
	move.b	d0,d1                           ; size character?
	andi.b	#$df,d1                         ; upper case
	cmp.b	#$4c,d1                         ; 'L' or 'l'?
	bne.s	do_printf_short                 ; no
	bset	#$f,d5                          ; long argument
do_printf_size_next:
	move.b	(a2)+,d0                        ; character after the size
	beq.w	fmt_error                       ; end: error
	bra.s	do_printf_conversion            ; to the conversion
do_printf_short:
	cmp.b	#$68,d0                         ; 'h'?
	beq.s	do_printf_size_next             ; yes: skip it
do_printf_conversion:
	cmp.b	d4,d0                           ; a second %?
	beq.w	fmt_percent                     ; yes: output a %
	moveq	#64,d1                          ; '@'
	sub.b	d1,d0                           ; character - '@'
	cmp.b	d1,d0                           ; below '@' or above DEL?
	bcc.w	fmt_error                       ; yes: error
	andi.w	#$3f,d0                         ; index 0..63
	add.w	d0,d0                           ; word index
	move.w	fmt_jump_table(pc,d0.w),d0      ; handler offset
	jmp	fmt_jump_table(pc,d0.w)         ; jump to the handler
fmt_jump_table:
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_e_upper-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_g_upper-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_hex_upper-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_char-fmt_jump_table
	dc.w	fmt_decimal-fmt_jump_table
	dc.w	fmt_e-fmt_jump_table
	dc.w	fmt_f-fmt_jump_table
	dc.w	fmt_g-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_decimal-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_count-fmt_jump_table
	dc.w	fmt_octal-fmt_jump_table
	dc.w	fmt_pointer-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_string-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_unsigned-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_hex-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
	dc.w	fmt_error-fmt_jump_table
fmt_count:
	movea.l	(a3)+,a0                        ; %n: int * from the arguments
	move.w	d3,(a0)                         ; store the count so far
	bra.w	do_printf_next_text             ; next
fmt_percent:
	lea	4(sp),a0                        ; buffer for one character
	move.b	d4,(a0)                         ; holds '%'
	bra.s	fmt_char_out                    ; output it as a character
fmt_char:
	move.w	(a3)+,d0                        ; %c: int argument
	lea	4(sp),a0                        ; buffer for one character
	move.b	d0,(a0)                         ; the character
fmt_char_out:
	move.b	d5,d0                           ; flags
	move.w	d6,d1                           ; width
	movea.l	a4,a1                           ; output function
	bsr.w	print_char                      ; output the character padded
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_string:
	movea.l	(a3)+,a0                        ; %s: string pointer
	move.b	d5,d0                           ; flags
	move.w	d6,d1                           ; width
	movea.l	a4,a1                           ; output function
	bsr.w	print_string                    ; output the string, precision in d2
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_unsigned:
	tst.w	d5                              ; %u: long?
	bpl.s	fmt_unsigned_word               ; no
	move.l	(a3)+,d0                        ; long argument
	bra.s	fmt_unsigned_out                ; output it
fmt_unsigned_word:
	moveq	#0,d0                           ; int argument
	move.w	(a3)+,d0                        ; zero extended
fmt_unsigned_out:
	move.w	d2,-(sp)                        ; precision on the stack
	move.b	d5,d1                           ; flags
	move.w	d6,d2                           ; width
	movea.l	a4,a0                           ; output function
	bsr.w	print_unsigned                  ; output unsigned decimal
	addq.w	#2,sp                           ; drop the precision
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_decimal:
	tst.w	d5                              ; %d %i: long?
	bpl.s	fmt_decimal_word                ; no
	move.l	(a3)+,d0                        ; long argument
	bra.s	fmt_decimal_out                 ; output it
fmt_decimal_word:
	move.w	(a3)+,d0                        ; int argument
	ext.l	d0                              ; sign extended
fmt_decimal_out:
	move.w	d2,-(sp)                        ; precision on the stack
	move.b	d5,d1                           ; flags
	move.w	d6,d2                           ; width
	movea.l	a4,a0                           ; output function
	bsr.w	print_signed                    ; output signed decimal
	addq.w	#2,sp                           ; drop the precision
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_hex_upper:
	bset	#$5,d5                          ; %X: upper case digits
fmt_hex:
	tst.w	d5                              ; %x: long?
	bpl.s	fmt_hex_word                    ; no
fmt_pointer:
	move.l	(a3)+,d0                        ; long argument (always for %p)
	bra.s	fmt_hex_out                     ; output it
fmt_hex_word:
	moveq	#0,d0                           ; int argument
	move.w	(a3)+,d0                        ; zero extended
fmt_hex_out:
	move.w	d2,-(sp)                        ; precision on the stack
	move.b	d5,d1                           ; flags
	move.w	d6,d2                           ; width
	movea.l	a4,a0                           ; output function
	bsr.w	print_hex                       ; output hex
	addq.w	#2,sp                           ; drop the precision
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_octal:
	tst.w	d5                              ; %o: long?
	bpl.s	fmt_octal_word                  ; no
	move.l	(a3)+,d0                        ; long argument
	bra.s	fmt_octal_out                   ; output it
fmt_octal_word:
	moveq	#0,d0                           ; int argument
	move.w	(a3)+,d0                        ; zero extended
fmt_octal_out:
	move.w	d2,-(sp)                        ; precision on the stack
	move.b	d5,d1                           ; flags
	move.w	d6,d2                           ; width
	movea.l	a4,a0                           ; output function
	bsr.w	print_octal                     ; output octal
	addq.w	#2,sp                           ; drop the precision
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_e_upper:
	bset	#$5,d5                          ; %E: upper case
fmt_e:
	lea	(a3),a0                         ; %e: a0 = long double argument
	adda.w	#$a,a3                          ; skip its 10 bytes
	move.b	d5,d0                           ; flags
	move.w	d6,d1                           ; width
	movea.l	a4,a1                           ; output function
	bsr.w	print_e_float                   ; output %e, precision in d2
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_f:
	lea	(a3),a0                         ; %f: a0 = long double argument
	adda.w	#$a,a3                          ; skip its 10 bytes
	move.b	d5,d0                           ; flags
	move.w	d6,d1                           ; width
	movea.l	a4,a1                           ; output function
	bsr.w	print_f_float                   ; output %f
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_g_upper:
	bset	#$5,d5                          ; %G: upper case
fmt_g:
	lea	(a3),a0                         ; %g: a0 = long double argument
	adda.w	#$a,a3                          ; skip its 10 bytes
	move.b	d5,d0                           ; flags
	move.w	d6,d1                           ; width
	movea.l	a4,a1                           ; output function
	bsr.w	print_g_float                   ; output %g
	add.w	d0,d3                           ; add to the count
	bra.w	do_printf_next_text             ; next
fmt_done:
	add.w	d0,d3                           ; add the last run to the count
	ext.l	d0                              ; length as a long
	jsr	(a4)                            ; output it
	move.w	d3,d0                           ; return the count
do_printf_return:
	addq.w	#6,sp                           ; drop the locals
	movem.l	(sp)+,d3-d6/a2-a4
	rts
fmt_error:
	moveq	#-1,d0                          ; bad conversion: -1
	bra.s	do_printf_return                ; return

;------------------------------------------------------------------------------
; %e conversion of a long double as d.ddddddE+xxxx (the exponent always has 4 digits)
; a0 = value, a1 = output function, d0 = flags, d1 = width, d2 = precision (-1: 6, at most 18)
; returns d0 = characters output; changes d0-d2/a0-a1
; precision + 1 digits come from ext_ecvt; the fields are filled in the frame and output by
; print_float_fields
; frame: (sp) flags, 2 space padding, 4 zero padding, 6 zeros after the point, 8 sign character,
; $a sign length, $c integer digits, $20 their count, $22 fraction digits, $36 their count,
; $38 exponent text, $40 its length, $42 negative flag, $44 decimal point from ecvt
;------------------------------------------------------------------------------
print_e_float:	; from: do_printf
	movem.l	d3-d7/a2-a3,-(sp)
	lea	-$62(sp),sp                     ; frame
	movea.l	a0,a2                           ; a2 = value
	movea.l	a1,a3                           ; a3 = output function
	move.w	d0,(sp)                         ; flags
	move.w	d1,d3                           ; d3 = width
	move.w	d2,d4                           ; d4 = precision
	bpl.s	print_e_cap_precision           ; given?
	moveq	#6,d4                           ; no: 6
	bra.s	print_e_digits                  ; on
print_e_cap_precision:
	moveq	#18,d0                          ; 18
	cmp.w	d0,d4                           ; above 18?
	bls.s	print_e_digits                  ; no
	move.w	d0,d4                           ; at most 18
print_e_digits:	; from: print_g_float
	move.w	#$0,6(sp)                       ; no zeros after the point
	move.w	(a2),d0                         ; exponent word
	bclr	#$f,d0                          ; without the sign
	cmp.w	#$7fff,d0                       ; $7fff?
	beq.w	print_inf_nan                   ; infinity or NaN
	movea.l	a2,a0                           ; a0 = value
	move.w	d4,d0                           ; precision
	addq.w	#1,d0                           ; + 1 digits
	lea	$44(sp),a1                      ; a1 = &decimal point
	pea	$42(sp)                         ; &negative
	bsr.w	ext_ecvt                        ; digits
	addq.w	#4,sp                           ; drop the pointer
	move.w	(sp),d0                         ; d0 = flags
	move.w	#$0,$a(sp)                      ; no sign yet
	tst.w	$42(sp)                         ; negative?
	beq.s	print_e_plus                    ; no
	move.b	#$2d,8(sp)                      ; '-'
	move.w	#$1,$a(sp)                      ; one sign character
	bra.s	print_e_mantissa                ; on
print_e_plus:
	btst	#$2,d0                          ; + flag?
	beq.s	print_e_space                   ; no
	move.b	#$2b,8(sp)                      ; '+'
	move.w	#$1,$a(sp)                      ; one sign character
	bra.s	print_e_mantissa                ; on
print_e_space:
	btst	#$0,d0                          ; space flag?
	beq.s	print_e_mantissa                ; no
	move.b	#$20,8(sp)                      ; ' '
	move.w	#$1,$a(sp)                      ; one sign character
print_e_mantissa:
	move.w	#$1,$20(sp)                     ; one digit before the point
	move.w	d4,$36(sp)                      ; precision digits after it
	move.w	d4,d1                           ; length = precision
	addq.w	#4,d1                           ; + 4
	addq.w	#4,d1                           ; + 4: digit, point and 6 exponent characters
	moveq	#48,d2                          ; '0'
	cmp.b	(a0),d2                         ; first digit '0'?
	beq.s	print_e_zero                    ; yes: zero
	tst.b	(a0)                            ; empty string?
	bne.s	print_e_first_digit             ; no: real digits
print_e_zero:
	move.b	d2,$c(sp)                       ; integer digit '0'
	addq.w	#1,$44(sp)                      ; exponent 0 (decimal point - 1)
	tst.w	d4                              ; precision 0?
	bne.s	print_e_zero_fraction           ; no: zero fraction
	btst	#$1,d0                          ; # flag?
	bne.s	print_e_padding                 ; yes: keep the point
	subq.w	#1,d1                           ; no point: one less
	bra.s	print_e_padding                 ; on
print_e_zero_fraction:
	lea	$22(sp),a1                      ; fraction buffer
	subq.w	#1,d4                           ; count - 1
print_e_zero_loop:
	move.b	d2,(a1)+                        ; '0'
	dbra	d4,print_e_zero_loop            ; for each fraction digit
	bra.s	print_e_padding                 ; on
print_e_first_digit:
	move.b	(a0)+,$c(sp)                    ; first digit before the point
	tst.w	d4                              ; precision 0?
	bne.s	print_e_fraction                ; no
	btst	#$1,d0                          ; # flag?
	bne.s	print_e_padding                 ; yes: keep the point
	subq.w	#1,d1                           ; no point: one less
	bra.s	print_e_padding                 ; on
print_e_fraction:
	lea	$22(sp),a1                      ; fraction buffer
	subq.w	#1,d4                           ; count - 1
	blt.s	print_e_padding                 ; none
print_e_fraction_loop:
	move.b	(a0)+,(a1)+                     ; copy the other digits
	dbra	d4,print_e_fraction_loop        ; for each fraction digit
print_e_padding:
	moveq	#0,d2                           ; d2 = 0
	add.w	$a(sp),d1                       ; length + sign
	sub.w	d1,d3                           ; padding = width - length
	bgt.s	print_e_pad_kind                ; some
	move.w	d2,2(sp)                        ; none: no spaces
	move.w	d2,4(sp)                        ; and no zeros
	bra.s	print_e_exponent                ; on
print_e_pad_kind:
	btst	#$3,d0                          ; left justified?
	bne.s	print_e_pad_spaces              ; yes: spaces
	btst	#$4,d0                          ; 0 flag?
	bne.s	print_e_pad_zeros               ; yes: zeros
print_e_pad_spaces:
	move.w	d3,2(sp)                        ; spaces
	move.w	d2,4(sp)                        ; no zeros
	bra.s	print_e_exponent                ; on
print_e_pad_zeros:
	move.w	d3,4(sp)                        ; zeros
	move.w	d2,2(sp)                        ; no spaces
print_e_exponent:
	lea	$38(sp),a1                      ; exponent text
	move.w	#$6,$40(sp)                     ; 6 characters: e, sign, 4 digits
	btst	#$5,d0                          ; upper case?
	beq.s	print_e_lower                   ; no
	move.b	#$45,(a1)+                      ; 'E'
	bra.s	print_e_exponent_sign           ; on
print_e_lower:
	move.b	#$65,(a1)+                      ; 'e'
print_e_exponent_sign:
	move.w	$44(sp),d0                      ; decimal point
	subq.w	#1,d0                           ; minus 1: exponent
	bpl.s	print_e_exponent_plus           ; not negative
	neg.w	d0                              ; magnitude
	move.b	#$2d,(a1)+                      ; '-'
	bra.s	print_e_exponent_digits         ; on
print_e_exponent_plus:
	move.b	#$2b,(a1)+                      ; '+'
print_e_exponent_digits:
	move.l	a1,-(sp)                        ; save the text pointer
	moveq	#10,d1                          ; base 10
	lea	$4a(sp),a0                      ; a0 = scratch buffer (frame $46)
	bsr.w	itoa                            ; itoa
	movea.l	(sp)+,a1                        ; text pointer
	lea	$46(sp),a0                      ; a0 = the digits
	moveq	#-1,d0                          ; count = -1
print_e_exponent_length:
	tst.b	(a0)+                           ; count up to the NUL
	dbeq	d0,print_e_exponent_length      ; until the NUL
	not.w	d0                              ; d0 = number of digits
	moveq	#4,d1                           ; 4
	sub.b	d0,d1                           ; zeros = 4 - digits
	beq.s	print_e_exponent_copy           ; none
	subq.w	#1,d1                           ; count - 1
	bmi.s	print_e_exponent_copy           ; more than 4 digits: none
	moveq	#48,d2                          ; '0'
print_e_exponent_zeros:
	move.b	d2,(a1)+                        ; leading zeros of the exponent
	dbra	d1,print_e_exponent_zeros       ; for each zero
print_e_exponent_copy:
	subq.w	#1,d0                           ; digits - 1
	bmi.s	print_e_done                    ; none
	lea	$46(sp),a0                      ; a0 = the digits
print_e_exponent_loop:
	move.b	(a0)+,(a1)+                     ; copy the exponent digits
	dbra	d0,print_e_exponent_loop        ; for each digit
print_e_done:
	bra.w	print_float_fields              ; output the fields

;------------------------------------------------------------------------------
; %f conversion of a long double; more than 19 significant digits prints "?"
; a0 = value, a1 = output function, d0 = flags, d1 = width, d2 = precision (-1: 6)
; returns d0 = characters output; changes d0-d2/a0-a1
; ext_ecvt with 19 digits gives the decimal point; the digits are then fetched again with exactly
; the number needed (decimal point + precision), so ext_ecvt does the rounding
; frame: (sp) flags, 2 space padding, 4 zero padding, 6 zeros after the point, 8 sign character,
; $a sign length, $c integer digits, $20 their count, $22 fraction digits, $36 their count,
; $38 exponent text, $40 its length, $42 negative flag, $44 decimal point from ecvt
;------------------------------------------------------------------------------
print_f_float:	; from: do_printf
	movem.l	d3-d7/a2-a3,-(sp)
	lea	-$62(sp),sp                     ; frame
	movea.l	a0,a2                           ; a2 = value
	movea.l	a1,a3                           ; a3 = output function
	move.w	#$0,$40(sp)                     ; no exponent field
	move.w	d0,d7                           ; d7 = flags
	move.w	d7,(sp)                         ; and in the frame
	move.w	d1,d3                           ; d3 = width
	move.w	d2,d4                           ; d4 = precision
	bpl.s	print_f_check                   ; given?
	moveq	#6,d4                           ; no: 6
print_f_check:
	move.w	(a2),d0                         ; exponent word
	bclr	#$f,d0                          ; without the sign
	cmp.w	#$7fff,d0                       ; $7fff?
	beq.w	print_inf_nan                   ; infinity or NaN
	movea.l	a2,a0                           ; a0 = value
	moveq	#19,d0                          ; 19 digits, for the decimal point
	lea	$44(sp),a1                      ; a1 = &decimal point
	pea	$42(sp)                         ; &negative
	bsr.w	ext_ecvt                        ; digits
	addq.w	#4,sp                           ; drop the pointer
print_f_digits:	; from: print_g_float
	move.w	#$0,$a(sp)                      ; no sign yet
	tst.w	$42(sp)                         ; negative?
	beq.s	print_f_plus                    ; no
	move.b	#$2d,8(sp)                      ; '-'
	move.w	#$1,$a(sp)                      ; one sign character
	bra.s	print_f_split                   ; on
print_f_plus:
	btst	#$2,d7                          ; + flag?
	beq.s	print_f_space                   ; no
	move.b	#$2b,8(sp)                      ; '+'
	move.w	#$1,$a(sp)                      ; one sign character
	bra.s	print_f_split                   ; on
print_f_space:
	btst	#$0,d7                          ; space flag?
	beq.s	print_f_split                   ; no
	move.b	#$20,8(sp)                      ; ' '
	move.w	#$1,$a(sp)                      ; one sign character
print_f_split:
	move.w	$44(sp),d5                      ; d5 = decimal point
	bge.w	print_f_large                   ; >= 0: integer digits
	neg.w	d5                              ; d5 = zeros after the point
	move.b	#$30,$c(sp)                     ; integer part "0"
	move.w	#$1,$20(sp)                     ; one digit
	moveq	#2,d6                           ; d6 = length of "0."
	tst.w	d4                              ; precision 0?
	bne.s	print_f_small_compare           ; no
	btst	#$1,d7                          ; # flag?
	bne.s	print_f_small_compare           ; yes: keep the point
	subq.w	#1,d6                           ; no point: "0"
print_f_small_compare:
	cmp.w	d4,d5                           ; zeros vs precision
	beq.s	print_f_equal_zeros             ; the same
	bcs.s	print_f_small_digits            ; fewer: some digits show
	move.w	d4,6(sp)                        ; more: precision zeros
	add.w	d4,d6                           ; length + zeros
	move.w	#$0,$36(sp)                     ; no fraction digits
	bra.w	print_f_padding                 ; output
print_f_equal_zeros:
	tst.w	d5                              ; no zeros at all?
	bne.s	print_f_round_last              ; no
	moveq	#0,d0                           ; nothing after the point
	move.w	d0,6(sp)                        ; no zeros
	move.w	d0,$36(sp)                      ; no fraction digits
	bra.w	print_f_padding                 ; output
print_f_round_last:
	movea.l	a2,a0                           ; a0 = value
	moveq	#19,d0                          ; 19 digits
	lea	$44(sp),a1                      ; a1 = &decimal point
	pea	$42(sp)                         ; &negative
	bsr.w	ext_ecvt                        ; digits
	addq.w	#4,sp                           ; drop the pointer
	cmpi.b	#$35,(a0)                       ; first digit at least '5'?
	bcc.s	print_f_round_up                ; yes: round up into the last place
	move.w	d5,6(sp)                        ; no: precision zeros
	add.w	d5,d6                           ; length + zeros
	move.w	#$0,$36(sp)                     ; no fraction digits
	bra.w	print_f_padding                 ; output
print_f_round_up:
	subq.w	#1,d5                           ; one zero less
	move.w	d5,6(sp)                        ; zeros after the point
	add.w	d5,d6                           ; length + zeros
	move.b	#$31,$22(sp)                    ; then a '1'
	moveq	#1,d0                           ; one fraction digit
	move.w	d0,$36(sp)                      ; fraction digit count 1
	add.w	d0,d6                           ; length + 1
	bra.w	print_f_padding                 ; output
print_f_small_digits:
	sub.w	d5,d4                           ; d4 = digits after the zeros
	cmp.w	#$13,d4                         ; more than 19?
	bhi.w	print_f_overflow                ; yes: "?"
	movea.l	a2,a0                           ; a0 = value
	move.w	d4,d0                           ; that many digits
	lea	$44(sp),a1                      ; a1 = &decimal point
	pea	$42(sp)                         ; &negative
	bsr.w	ext_ecvt                        ; digits
	addq.w	#4,sp                           ; drop the pointer
	move.b	#$30,0(a0,d4.w)                 ; '0' after the digits
	add.w	d5,d4                           ; back to the precision
	move.w	$44(sp),d5                      ; decimal point after rounding
	neg.w	d5                              ; zeros after the point
	sub.w	d5,d4                           ; digits = precision - zeros
	move.w	d4,$36(sp)                      ; fraction digit count
	add.w	d4,d6                           ; length + digits
	lea	$22(sp),a1                      ; fraction buffer
	subq.w	#1,d4                           ; count - 1
	blt.s	print_f_small_zeros             ; none
print_f_small_copy:
	move.b	(a0)+,(a1)+                     ; copy the digits
	dbra	d4,print_f_small_copy           ; for each digit
print_f_small_zeros:
	move.w	d5,6(sp)                        ; zeros after the point
	add.w	d5,d6                           ; length + zeros
	bra.w	print_f_padding                 ; output
print_f_large:
	move.w	#$0,6(sp)                       ; no zeros after the point
	move.w	d5,d0                           ; digits = decimal point
	add.w	d4,d0                           ; + precision
	cmp.w	#$13,d0                         ; more than 19?
	bhi.w	print_f_overflow                ; yes: "?"
	movea.l	a2,a0                           ; a0 = value
	lea	$44(sp),a1                      ; a1 = &decimal point
	pea	$42(sp)                         ; &negative
	bsr.w	ext_ecvt                        ; digits
	addq.w	#4,sp                           ; drop the pointer
	move.w	d5,d0                           ; digit count = decimal point
	add.w	d4,d0                           ; + precision
	move.b	#$30,0(a0,d0.w)                 ; '0' after the digits
	move.w	$44(sp),d5                      ; decimal point after rounding
	move.w	d5,d6                           ; length = integer digits
	addq.w	#1,d6                           ; + point
	add.w	d4,d6                           ; + precision
	tst.w	d4                              ; precision 0?
	bne.s	print_f_large_digits            ; no
	btst	#$1,d7                          ; # flag?
	bne.s	print_f_large_digits            ; yes: keep the point
	subq.w	#1,d6                           ; no point
print_f_large_digits:
	move.w	d4,$36(sp)                      ; fraction digit count
	moveq	#48,d2                          ; '0'
	tst.b	(a0)                            ; any digits?
	bne.s	print_f_integer                 ; yes
	move.b	d2,$c(sp)                       ; zero: integer digit '0'
	move.w	#$1,$20(sp)                     ; one digit
	addq.w	#1,$44(sp)                      ; decimal point + 1
	lea	$22(sp),a1                      ; fraction buffer
	subq.w	#1,d4                           ; count - 1
	bmi.s	print_f_padding                 ; none
print_f_zero_loop:
	move.b	d2,(a1)+                        ; '0'
	dbra	d4,print_f_zero_loop            ; for each fraction digit
	bra.s	print_f_padding                 ; on
print_f_integer:
	lea	$c(sp),a1                       ; integer buffer
	move.w	d5,$20(sp)                      ; integer digit count
	subq.w	#1,d5                           ; count - 1
	bpl.s	print_f_integer_loop            ; some
	move.b	#$30,(a1)+                      ; none: '0'
	move.w	#$1,$20(sp)                     ; one digit
	addq.w	#1,d6                           ; length + 1
	bra.s	print_f_fraction                ; on
print_f_integer_loop:
	move.b	(a0)+,(a1)+                     ; copy the integer digits
	dbra	d5,print_f_integer_loop         ; for each digit
print_f_fraction:
	lea	$22(sp),a1                      ; fraction buffer
	subq.w	#1,d4                           ; count - 1
	bmi.s	print_f_padding                 ; none
print_f_fraction_loop:
	move.b	(a0)+,(a1)+                     ; copy the fraction digits
	dbra	d4,print_f_fraction_loop        ; for each digit
print_f_padding:
	moveq	#0,d2                           ; d2 = 0
	add.w	$a(sp),d6                       ; length + sign
	sub.w	d6,d3                           ; padding = width - length
	bgt.s	print_f_pad_kind                ; some
	move.w	d2,2(sp)                        ; none: no spaces
	move.w	d2,4(sp)                        ; and no zeros
	bra.w	print_float_fields              ; output
print_f_pad_kind:
	btst	#$3,d7                          ; left justified?
	bne.s	print_f_pad_spaces              ; yes: spaces
	btst	#$4,d7                          ; 0 flag?
	bne.s	print_f_pad_zeros               ; yes: zeros
print_f_pad_spaces:
	move.w	d3,2(sp)                        ; spaces
	move.w	d2,4(sp)                        ; no zeros
	bra.w	print_float_fields              ; output
print_f_pad_zeros:
	move.w	d2,2(sp)                        ; no spaces
	move.w	d3,4(sp)                        ; zeros
	bra.w	print_float_fields              ; output
print_f_overflow:
	move.b	#$3f,$c(sp)                     ; "?"
	move.w	#$1,$20(sp)                     ; one character
	moveq	#0,d4                           ; 0
	move.w	d4,$a(sp)                       ; no sign
	move.w	d4,6(sp)                        ; no zeros after the point
	move.w	d4,$36(sp)                      ; no fraction digits
	moveq	#1,d6                           ; length 1
	bra.s	print_f_padding                 ; on to the padding

;------------------------------------------------------------------------------
; %g conversion of a long double: X = floor(log10 |value|); %e if X < -4 or X > precision,
; else %f; trailing zeros are dropped in both
; a0 = value, a1 = output function, d0 = flags, d1 = width, d2 = precision (-1: 6, at most 18)
; returns d0 = characters output; changes d0-d2/a0-a1
; it shares the frame of print_e_float and print_f_float and continues in their code
;------------------------------------------------------------------------------
print_g_float:	; from: do_printf
	movem.l	d3-d7/a2-a3,-(sp)
	lea	-$62(sp),sp                     ; frame as print_e_float
	movea.l	a0,a2                           ; a2 = value
	movea.l	a1,a3                           ; a3 = output function
	move.w	#$0,$40(sp)                     ; no exponent field
	move.w	d0,d7                           ; d7 = flags
	move.w	d7,(sp)                         ; and in the frame
	move.w	d1,d3                           ; d3 = width
	move.w	d2,d4                           ; d4 = precision
	bmi.s	print_g_default                 ; not given
	cmp.w	#$12,d4                         ; below 18?
	bmi.s	print_g_check                   ; yes
	moveq	#18,d4                          ; at most 18
	bra.s	print_g_check                   ; on
print_g_default:
	moveq	#6,d4                           ; 6
print_g_check:
	move.w	(a2),d0                         ; exponent word
	bclr	#$f,d0                          ; without the sign
	cmp.w	#$7fff,d0                       ; $7fff?
	beq.w	print_inf_nan                   ; infinity or NaN
	movea.l	a2,a0                           ; a0 = value
	lea	$4e(sp),a1                      ; a1 = |value| (frame $4e)
	bsr.w	ext_fabs                        ; fabs
	lea	$4e(sp),a0                      ; |value|
	tst.l	(a0)+                           ; any bits set?
	bne.s	print_g_nonzero                 ; yes
	tst.l	(a0)+                           ; low long
	bne.s	print_g_nonzero                 ; yes
	tst.w	(a0)                            ; exponent
	beq.s	print_g_zero                    ; zero
print_g_nonzero:
	lea	$4e(sp),a0                      ; a0 = |value|
	lea	$58(sp),a1                      ; a1 = log10 (frame $58)
	bsr.w	ext_log10                       ; log10 |value|
	lea	$58(sp),a0                      ; a0 = log10
	btst	#$7,(a0)                        ; negative?
	sne	d0                              ; d0 = -1 if so
	ext.w	d0                              ; 0 or -1
	move.w	d0,-(sp)                        ; the correction on the stack
	bsr.w	fp_to_long                      ; to a long, truncated toward zero
	add.w	(sp)+,d0                        ; X = floor(log10 |value|)
	movea.l	a2,a0                           ; a0 = value
	lea	$44(sp),a1                      ; a1 = &decimal point
	pea	$42(sp)                         ; &negative
	cmp.w	#$fffc,d0                       ; X < -4?
	bmi.s	print_g_exp                     ; yes: %e
	cmp.w	d0,d4                           ; precision < X?
	bmi.s	print_g_exp                     ; yes: %e
	add.w	d4,d0                           ; digits = X + precision
	addq.w	#1,d0                           ; + 1
	move.w	d0,d1                           ; excess
	subi.w	#$12,d1                         ; over 18?
	bmi.s	print_g_fixed                   ; no
	sub.w	d1,d4                           ; reduce the precision by the excess
print_g_fixed:
	bsr.w	ext_ecvt                        ; digits
	addq.w	#4,sp                           ; drop the pointer
	adda.w	$44(sp),a0                      ; past the integer digits
	adda.w	d4,a0                           ; past the fraction digits
print_g_strip_fixed:
	cmpi.b	#$30,-(a0)                      ; drop trailing '0's of the fraction
	dbne	d4,print_g_strip_fixed          ; counting the fraction digits down
	tst.w	d4                              ; any left?
	bpl.w	print_f_digits                  ; yes
	clr.w	d4                              ; none
	bra.w	print_f_digits                  ; %f with that precision
print_g_exp:
	move.w	d4,d0                           ; precision digits
	bsr.w	ext_ecvt                        ; digits
	addq.w	#4,sp                           ; drop the pointer
	adda.w	d4,a0                           ; end of the digits
print_g_strip_exp:
	cmpi.b	#$30,-(a0)                      ; drop trailing '0's
	dbne	d4,print_g_strip_exp            ; counting the fraction digits down
	subq.w	#1,d4                           ; fraction digits for %e
	bra.w	print_e_digits                  ; %e
print_g_zero:
	clr.w	d4                              ; zero: no fraction digits
	clr.w	$42(sp)                         ; not negative
	clr.w	$44(sp)                         ; decimal point 0
	bra.w	print_f_digits                  ; %f

;------------------------------------------------------------------------------
; output the fields built by the float conversions, in order: spaces (unless left justified), sign,
; zeros, integer digits, point, zeros, fraction digits, exponent, spaces (when left justified)
; a3 = output function, frame as in print_e_float; returns d0 = characters output
;------------------------------------------------------------------------------
print_float_fields:	; from: print_e_float, print_f_float, print_inf_nan
	move.w	(sp),d3                         ; d3 = flags
	moveq	#0,d4                           ; d4 = count
	move.w	2(sp),d0                        ; leading spaces?
	beq.s	print_fields_sign               ; none
	btst	#$3,d3                          ; left justified?
	bne.s	print_fields_sign               ; yes: they go at the end
	add.w	d0,d4                           ; count them
	movea.l	a3,a0                           ; a0 = output function
	bsr.w	print_spaces                    ; output d0 spaces
print_fields_sign:
	move.w	$a(sp),d0                       ; sign?
	beq.s	print_fields_zero_pad           ; none
	add.w	d0,d4                           ; count it
	lea	8(sp),a0                        ; a0 = sign character
	jsr	(a3)                            ; output
print_fields_zero_pad:
	move.w	4(sp),d0                        ; zeros?
	beq.s	print_fields_integer            ; none
	add.w	d0,d4                           ; count them
	movea.l	a3,a0                           ; a0 = output function
	bsr.w	print_zeros                     ; output d0 zeros
print_fields_integer:
	move.w	$20(sp),d0                      ; integer digits
	beq.s	print_fields_point_check        ; none
	add.w	d0,d4                           ; count them
	lea	$c(sp),a0                       ; a0 = the digits
	jsr	(a3)                            ; output
print_fields_point_check:
	tst.w	6(sp)                           ; zeros after the point?
	bne.s	print_fields_point              ; yes: point
	tst.w	$36(sp)                         ; fraction digits?
	bne.s	print_fields_point              ; yes: point
	btst	#$1,d3                          ; # flag?
	beq.s	print_fields_zeros              ; no: no point
print_fields_point:
	moveq	#1,d0                           ; one character
	add.w	d0,d4                           ; count it
	lea	$c(sp),a0                       ; the integer buffer is free now
	move.b	#$2e,(a0)                       ; '.'
	jsr	(a3)                            ; output
print_fields_zeros:
	move.w	6(sp),d0                        ; zeros after the point?
	beq.s	print_fields_fraction           ; none
	add.w	d0,d4                           ; count them
	movea.l	a3,a0                           ; a0 = output function
	bsr.w	print_zeros                     ; output d0 zeros
print_fields_fraction:
	move.w	$36(sp),d0                      ; fraction digits?
	beq.s	print_fields_exponent           ; none
	add.w	d0,d4                           ; count them
	lea	$22(sp),a0                      ; a0 = the digits
	jsr	(a3)                            ; output
print_fields_exponent:
	move.w	$40(sp),d0                      ; exponent?
	beq.s	print_fields_right_pad          ; none
	add.w	d0,d4                           ; count it
	lea	$38(sp),a0                      ; a0 = exponent text
	jsr	(a3)                            ; output
print_fields_right_pad:
	move.w	2(sp),d0                        ; spaces?
	beq.s	print_fields_return             ; none
	btst	#$3,d3                          ; left justified?
	beq.s	print_fields_return             ; no: already done
	add.w	d0,d4                           ; count them
	movea.l	a3,a0                           ; a0 = output function
	bsr.w	print_spaces                    ; output d0 spaces
print_fields_return:
	move.w	d4,d0                           ; return the count
	lea	$62(sp),sp                      ; drop the frame
	movem.l	(sp)+,d3-d7/a2-a3
	rts

;------------------------------------------------------------------------------
; infinity or NaN for the float conversions: "+Inf", "-Inf" or "Nan", padded with spaces
; a2 = value, d3 = width; continues in print_float_fields
;------------------------------------------------------------------------------
print_inf_nan:	; from: print_e_float, print_f_float, print_g_float
	move.w	#$8,d0                          ; mantissa bytes
	lsr.w	#1,d0                           ; words
	subq.w	#1,d0                           ; - 1 for dbra
	moveq	#2,d1                           ; from offset 2
print_inf_nan_test:
	tst.w	0(a2,d1.w)                      ; nonzero mantissa word?
	bne.s	print_nan_text                  ; yes: NaN
	addq.w	#2,d1                           ; next word
	dbra	d0,print_inf_nan_test           ; for each word
	move.b	#$2b,$c(sp)                     ; '+'
	btst	#$7,(a2)                        ; negative?
	beq.s	print_inf_text                  ; no
	move.b	#$2d,$c(sp)                     ; '-'
print_inf_text:
	move.b	#$49,$d(sp)                     ; 'I'
	move.b	#$6e,$e(sp)                     ; 'n'
	move.b	#$66,$f(sp)                     ; 'f'
	moveq	#4,d0                           ; 4 characters
	move.w	d0,$20(sp)                      ; integer field length
	sub.w	d0,d3                           ; spaces = width - 4
	bpl.s	print_inf_pad                   ; some
	moveq	#0,d3                           ; none
print_inf_pad:
	move.w	d3,2(sp)                        ; space padding
	bra.s	print_inf_nan_fields            ; on
print_nan_text:
	move.b	#$4e,$c(sp)                     ; 'N'
	move.b	#$61,$d(sp)                     ; 'a'
	move.b	#$6e,$e(sp)                     ; 'n'
	moveq	#3,d0                           ; 3 characters
	move.w	d0,$20(sp)                      ; integer field length
	sub.w	d0,d3                           ; spaces = width - 3
	bpl.s	print_nan_pad                   ; some
	moveq	#0,d3                           ; none
print_nan_pad:
	move.w	d3,2(sp)                        ; space padding
print_inf_nan_fields:
	bclr	#$1,1(sp)                       ; clear #: no point
	moveq	#0,d0                           ; 0
	move.w	d0,$a(sp)                       ; no sign
	move.w	d0,4(sp)                        ; no zeros
	move.w	d0,6(sp)                        ; no zeros after the point
	move.w	d0,$36(sp)                      ; no fraction
	move.w	d0,$40(sp)                      ; no exponent
	bra.w	print_float_fields              ; output

;------------------------------------------------------------------------------
; ecvt into a static buffer: digits of a long double
; a0 = value, d0 = number of digits, a1 = int *decimal point, 4(sp) = int *sign
; returns a0 = digit string (in ext_ecvt_buffer); changes d0-d2/a0-a1
;------------------------------------------------------------------------------
ext_ecvt:	; from: print_e_float, print_f_float, print_g_float
	moveq	#0,d1                           ; ecvt mode
	move.l	4(sp),-(sp)                     ; push the sign pointer
	move.l	a1,-(sp)                        ; push the decimal point pointer
	lea	ext_ecvt_buffer,a1              ; static digit buffer
	bsr.s	cvt_digits                      ; convert
	addq.w	#8,sp                           ; drop the pointers
	lea	ext_ecvt_buffer,a0              ; return the buffer
	rts

;------------------------------------------------------------------------------
; fcvt(value, ndigit, *decpt, *sign): value on the stack, d0 = digits after the point,
; a0 = int *decimal point, a1 = int *sign; returns a0 = digit string (in ecvt_buffer)
;------------------------------------------------------------------------------
fcvt:
	moveq	#1,d1                           ; fcvt mode
	bra.s	cvt_stack_value                 ; on

;------------------------------------------------------------------------------
; ecvt(value, ndigit, *decpt, *sign): as fcvt, d0 = total digits
;------------------------------------------------------------------------------
ecvt:
	moveq	#0,d1                           ; ecvt mode
cvt_stack_value:	; from: fcvt
	pea	(a1)                            ; push the sign pointer
	pea	(a0)                            ; push the decimal point pointer
	lea	ecvt_buffer,a1                  ; static digit buffer
	lea	$c(sp),a0                       ; a0 = value on the stack
	bsr.s	cvt_digits                      ; convert
	addq.w	#8,sp                           ; drop the pointers
	rts

;------------------------------------------------------------------------------
; convert a long double to a string of decimal digits, rounded
; a0 = value, a1 = buffer, d0 = digits, d1 = 0: total digits (ecvt), 1: digits after the point (fcvt)
; 4(sp) = int *decimal point, 8(sp) = int *sign (1 if negative)
; returns a0 = digit string (or "NaN"/"+INF"/"-INF" with d0 = 0), d0 = 1 for a number;
; changes d0-d2/a0-a1
; method: X = exponent * log10(2) estimates the decimal exponent; V = value / 10^X, then times 10
; until V >= 1; digits are the integer part of V, then of the fraction times 10, at most 20;
; a remainder >= 0.5 rounds the last digit up
;------------------------------------------------------------------------------
cvt_digits:	; from: ext_ecvt, ecvt
	movem.l	d3-d7/a6,-(sp)
	lea	(a1),a6                         ; a6 = buffer
	move.w	d1,d4                           ; d4 = mode
	move.w	d0,d6                           ; d6 = digits wanted
	ble.w	cvt_digits_return               ; none: return
	tst.w	(a0)                            ; negative?
	smi	d0                              ; d0 = $ff if so
	andi.w	#$1,d0                          ; 1 or 0
	movea.l	$20(sp),a1                      ; sign pointer
	move.w	d0,(a1)                         ; *sign
	bsr.w	fp_classify                     ; unpack: d0 exponent, d1:d2 mantissa
	bmi.s	cvt_digits_scale                ; finite, non-zero
	beq.s	cvt_digits_zero                 ; zero
	bvc.s	cvt_digits_nan                  ; V clear: NaN
	lea	str_plus_inf(pc),a6             ; "+INF"
	tst.w	d0                              ; negative?
	bpl.s	cvt_digits_special              ; no
	lea	str_minus_inf(pc),a6            ; "-INF"
	bra.s	cvt_digits_special              ; on
cvt_digits_nan:
	lea	str_nan(pc),a6                  ; "NaN"
cvt_digits_special:
	moveq	#0,d0                           ; d0 = 0: not a number
	bra.w	cvt_digits_return               ; return
cvt_digits_zero_loop:
	move.b	#$30,0(a6,d6.w)                 ; '0'
cvt_digits_zero:
	dbra	d6,cvt_digits_zero_loop         ; for each digit
	movea.l	$1c(sp),a0                      ; decimal point pointer
	clr.w	(a0)                            ; *decpt = 0
	bra.w	cvt_digits_ok                   ; return 1
cvt_digits_scale:
	lea	-$a(sp),sp                      ; room for a power of ten P
	andi.w	#$7fff,d0                       ; exponent without the sign
	move.l	d2,-(sp)                        ; V mantissa low
	move.l	d1,-(sp)                        ; V mantissa high
	move.w	d0,-(sp)                        ; V exponent: a copy of the value on the stack
	move.w	d0,d3                           ; d3 = exponent
	move.w	d0,d7                           ; d7 = exponent
	mulu.w	#$4d10,d7                       ; times log10(2) * 65536
	swap	d7                              ; / 65536
	subi.w	#$1343,d7                       ; X = estimated decimal exponent
	lea	$a(sp),a0                       ; a0 = P
	move.w	d7,d0                           ; X
	bpl.s	cvt_digits_divide               ; X >= 0
	neg.w	d0                              ; -X
	bsr.w	ext_pow10                       ; P = 10^-X
	lea	(sp),a0                         ; a0 = V
	lea	$a(sp),a1                       ; a1 = P
	bsr.w	soft_fmul                       ; V = V * 10^-X
	bra.s	cvt_digits_below_one            ; on
cvt_digits_divide:
	bsr.w	ext_pow10                       ; P = 10^X
	lea	(sp),a0                         ; a0 = V
	lea	$a(sp),a1                       ; a1 = P
	bsr.w	soft_fdiv                       ; V = V / 10^X
cvt_digits_below_one:
	cmpi.w	#$3ffe,(a0)                     ; V below 1.0?
	bhi.s	cvt_digits_point                ; no
	lea	fp_ten(pc),a1                   ; 10.0
	bsr.w	soft_fmul                       ; V * 10
	subq.w	#1,d7                           ; X - 1
	bra.s	cvt_digits_below_one            ; again
cvt_digits_point:
	lea	(sp),a0                         ; a0 = V
	move.w	(a0)+,d3                        ; d3 = exponent
	move.l	(a0)+,d1                        ; d1 = mantissa high
	move.l	(a0)+,d2                        ; d2 = mantissa low
	addq.w	#1,d7                           ; decimal point = X + 1
	tst.w	d4                              ; fcvt mode?
	ble.s	cvt_digits_limit                ; no
	add.w	d7,d6                           ; digits = digits after the point + decimal point
	bgt.s	cvt_digits_limit                ; at least one
	moveq	#1,d6                           ; 1
cvt_digits_limit:
	cmpi.w	#$14,d6                         ; at most 20
	ble.s	cvt_digits_start                ; yes
	moveq	#20,d6                          ; 20
cvt_digits_start:
	movea.l	$30(sp),a0                      ; decimal point pointer
	move.w	d7,(a0)                         ; *decpt
	lea	(a6),a1                         ; a1 = buffer
	subi.w	#$3fff,d3                       ; shift count = exponent - bias
	subq.w	#1,d6                           ; digit counter
	moveq	#0,d0                           ; integer part
cvt_digits_integer:
	add.l	d2,d2                           ; shift V left
	addx.l	d1,d1                           ; carry
	addx.w	d0,d0                           ; integer bits into d0
	dbra	d3,cvt_digits_integer           ; exponent + 1 bits
	bra.s	cvt_digits_store                ; store the first digit
cvt_digits_next:
	moveq	#0,d0                           ; next digit
	add.l	d2,d2                           ; fraction * 2 into d0:d1:d2
	addx.l	d1,d1                           ; carry
	addx.w	d0,d0                           ; carry
	move.l	d2,d5                           ; save fraction * 2
	move.l	d1,d4                           ; mantissa high
	move.w	d0,d3                           ; integer
	add.l	d2,d2                           ; * 4
	addx.l	d1,d1                           ; carry
	addx.w	d0,d0                           ; carry
	add.l	d2,d2                           ; * 8
	addx.l	d1,d1                           ; carry
	addx.w	d0,d0                           ; carry
	add.l	d5,d2                           ; * 8 + * 2 = * 10: the carry in d0 is the digit
	addx.l	d4,d1                           ; carry
	addx.w	d3,d0                           ; carry
cvt_digits_store:
	addi.b	#$30,d0                         ; to ASCII
	move.b	d0,(a1)+                        ; store
	dbra	d6,cvt_digits_next              ; for each digit
	clr.b	(a1)                            ; terminate
	tst.l	d1                              ; remainder at least 0.5?
	bpl.s	cvt_digits_done                 ; no: done
cvt_digits_round_up:
	addq.b	#1,-(a1)                        ; round up the last digit
	cmpi.b	#$3a,(a1)                       ; past '9'?
	bne.s	cvt_digits_done                 ; no
	cmpa.l	a1,a6                           ; at the first digit?
	beq.s	cvt_digits_carry_out            ; yes
	move.b	#$30,(a1)                       ; no: '0' and carry on
	bra.s	cvt_digits_round_up             ; into the previous digit
cvt_digits_carry_out:
	move.b	#$31,(a1)                       ; all 9s: "1000..."
	addq.w	#1,(a0)                         ; decimal point + 1
cvt_digits_done:
	lea	$14(sp),sp                      ; drop V and P
cvt_digits_ok:
	moveq	#1,d0                           ; d0 = 1: a number
cvt_digits_return:
	lea	(a6),a0                         ; return the buffer
	movem.l	(sp)+,d3-d7/a6
	rts

;------------------------------------------------------------------------------
; pow10: 10 to the power d0 into the long double at 4(sp)
;------------------------------------------------------------------------------
pow10:
	movea.l	4(sp),a0                        ; C entry: a0 = result pointer

;------------------------------------------------------------------------------
; a0 = result = 10^d0 as a long double (a negative power gives the reciprocal, |d0| at most 6144)
; 10^(n mod 8) from pow10_table, times 10^8, 10^16, ... for each bit of n / 8; changes d0-d2/a1
;------------------------------------------------------------------------------
ext_pow10:	; from: cvt_digits
	move.w	d0,-(sp)                        ; save the sign of the power
	bpl.s	ext_pow10_clamp                 ; positive
	neg.w	d0                              ; |n|
ext_pow10_clamp:
	cmpi.w	#$1800,d0                       ; at most 6144
	bls.s	ext_pow10_small                 ; yes
	move.w	#$1800,d0                       ; 6144
ext_pow10_small:
	move.w	d7,-(sp)                        ; save d7
	move.w	d0,d7                           ; d7 = n
	andi.w	#$7,d0                          ; n mod 8
	move.w	d0,d1                           ; times 10: table offset
	add.w	d1,d1                           ; * 2
	add.w	d1,d1                           ; * 4
	add.w	d0,d1                           ; * 5
	add.w	d1,d1                           ; * 10
	lea	pow10_table(pc,d1.w),a1         ; 10^(n mod 8)
	move.w	(a1)+,(a0)+                     ; copy it to the result
	move.l	(a1)+,(a0)+                     ; mantissa
	move.l	(a1)+,(a0)
	subq.w	#6,a0                           ; back to the start
	lsr.w	#3,d7                           ; n / 8
	beq.s	ext_pow10_done                  ; none: done
	lea	pow10_big_table(pc),a1          ; a1 = the 10^7 entry
ext_pow10_big_loop:
	lea	$a(a1),a1                       ; next power: 10^8, 10^16, ...
	lsr.w	#1,d7                           ; bit set?
	bcc.s	ext_pow10_big_loop              ; no
	bsr.w	ext_fmul                        ; result times that power
	tst.w	d7                              ; more bits?
	bne.s	ext_pow10_big_loop              ; yes
ext_pow10_done:
	move.w	(sp)+,d7                        ; restore d7
	tst.w	(sp)+                           ; negative power?
	bmi.w	soft_frecip                     ; yes: 1 / result
	rts

;------------------------------------------------------------------------------
; long doubles 10^0 .. 10^7, then 10^8, 10^16, 10^32 .. 10^4096
;------------------------------------------------------------------------------
pow10_table:	; from: ext_pow10
	dc.w	$3fff,$8000,$0000,$0000,$0000,$4002,$a000,$0000 ; 10^0, 10^1 start here
	dc.w	$0000,$0000,$4005,$c800,$0000,$0000,$0000,$4008 ; 10^2, 10^3 start here
	dc.w	$fa00,$0000,$0000,$0000,$400c,$9c40,$0000,$0000 ; 10^4 start here
	dc.w	$0000,$400f,$c350,$0000,$0000,$0000,$4012,$f424 ; 10^5, 10^6 start here
	dc.w	$0000,$0000,$0000
pow10_big_table:	; from: ext_pow10
	dc.w	$4016,$9896,$8000,$0000,$0000,$4019,$bebc,$2000 ; 10^7, the loop steps on from here to 10^8
	dc.w	$0000,$0000,$4034,$8e1b,$c9bf,$0400,$0000,$4069 ; 10^16, 10^32 start here
	dc.w	$9dc5,$ada8,$2b70,$b59e,$40d3,$c278,$1f49,$ffcf ; 10^64 start here
	dc.w	$a6d5,$41a8,$93ba,$47c9,$80e9,$8ce0,$4351,$aa7e ; 10^128, 10^256 start here
	dc.w	$ebfb,$9df9,$de8e,$46a3,$e319,$a0ae,$a60e,$91c7 ; 10^512 start here
	dc.w	$4d48,$c976,$7586,$8175,$0c17,$5a92,$9e8b,$3b5d ; 10^1024, 10^2048 start here
	dc.w	$c53d,$5de5,$7525,$c460,$5202,$8a20,$979b ; 10^4096 start here

;------------------------------------------------------------------------------
; function name passed to the math error handler
;------------------------------------------------------------------------------
log_name:	; from: soft_log2
	dc.b	'log',0

;------------------------------------------------------------------------------
; log2(1 + k/32) for k = 0..32, long doubles
;------------------------------------------------------------------------------
log2_table:	; from: log2p1_fraction
	dc.w	$0000,$0000,$0000,$0000,$0000,$3ffa,$b5d6,$9bac ; log2(1+0/32), log2(1+1/32) start here
	dc.w	$77ec,$398a,$3ffb,$b31f,$b7d6,$4898,$b3e6,$3ffc ; log2(1+2/32), log2(1+3/32) start here
	dc.w	$8462,$c466,$d3cf,$1cb1,$3ffc,$ae00,$d1cf,$deb4 ; log2(1+4/32) start here
	dc.w	$3cfd,$3ffc,$d67a,$f16d,$a764,$9f7f,$3ffc,$fde0 ; log2(1+5/32), log2(1+6/32) start here
	dc.w	$b5c8,$1340,$511d,$3ffd,$9220,$3d58,$7039,$cc12 ; log2(1+7/32) start here
	dc.w	$3ffd,$a4d3,$c25e,$68dc,$57f2,$3ffd,$b711,$0e6c ; log2(1+8/32), log2(1+9/32) start here
	dc.w	$e866,$f2bc,$3ffd,$c8dd,$d448,$f8b8,$45a6,$3ffd ; log2(1+10/32), log2(1+11/32) start here
	dc.w	$da3f,$5fb9,$c415,$0521,$3ffd,$eb3a,$9f01,$9750 ; log2(1+12/32) start here
	dc.w	$77f2,$3ffd,$fbd4,$2b46,$5836,$7671,$3ffe,$8608 ; log2(1+13/32), log2(1+14/32) start here
	dc.w	$2806,$b1d5,$32c4,$3ffe,$8df9,$88f4,$ae80,$6f1e ; log2(1+15/32) start here
	dc.w	$3ffe,$95c0,$1a39,$fbd6,$87a0,$3ffe,$9d5d,$9fd5 ; log2(1+16/32), log2(1+17/32) start here
	dc.w	$010b,$3666,$3ffe,$a4d3,$c25e,$68dc,$57f2,$3ffe ; log2(1+18/32), log2(1+19/32) start here
	dc.w	$ac24,$1134,$c4e9,$9e1c,$3ffe,$b350,$0472,$3c46 ; log2(1+20/32) start here
	dc.w	$5e69,$3ffe,$ba58,$feb2,$703a,$9e37,$3ffe,$c140 ; log2(1+21/32), log2(1+22/32) start here
	dc.w	$4ead,$f383,$96df,$3ffe,$c807,$30b0,$0016,$67f2 ; log2(1+23/32) start here
	dc.w	$3ffe,$ceae,$cfea,$8085,$9b33,$3ffe,$d538,$47ac ; log2(1+24/32), log2(1+25/32) start here
	dc.w	$00a6,$9be7,$3ffe,$dba4,$a47a,$a996,$d25a,$3ffe ; log2(1+26/32), log2(1+27/32) start here
	dc.w	$e1f4,$e517,$0d02,$a99b,$3ffe,$e829,$fb69,$3044 ; log2(1+28/32) start here
	dc.w	$b399,$3ffe,$ee44,$cd59,$ffab,$62f3,$3ffe,$f446 ; log2(1+29/32), log2(1+30/32) start here
	dc.w	$359b,$1353,$9551,$3ffe,$fa2f,$045e,$7832,$aa72 ; log2(1+31/32) start here
	dc.w	$3fff,$8000,$0000,$0000,$0000   ; log2(1+32/32) start here

;------------------------------------------------------------------------------
; series coefficients 2/ln2, 2/(3 ln2), 2/(5 ln2), 2/(7 ln2), read backwards
;------------------------------------------------------------------------------
log2_series:
	dc.w	$4000,$b8aa,$3b29,$5c17,$f0bc,$3ffe,$f638,$4ee1 ; 2/ln2, 2/(3 ln2) start here
	dc.w	$d025,$0cf5,$3ffe,$93bb,$6281,$1341,$3739,$3ffd ; 2/(5 ln2), 2/(7 ln2) start here
	dc.w	$d310,$d297,$c24c,$27df

;------------------------------------------------------------------------------
; log2(1+x) for 0 <= x < 1 by table and series
; a0 = x, a1 = result; changes d0-d2/a0-a1
; k = x * 32 rounded to the nearest, r = x - k/32 (|r| <= 1/64), s = r / (2(1 + k/32) + r);
; log2(1+x) = log2(1 + k/32) + s * (c1 + c3 s^2 + c5 s^4 + c7 s^6), c from log2_series
;------------------------------------------------------------------------------
log2p1_fraction:	; from: soft_log2, ext_log2p1
	bsr.w	fp_classify                     ; classify x
	bge.w	fp_store                        ; not finite non-zero: result = x
	movem.l	d3-d4/a5-a6,-(sp)
	moveq	#0,d3                           ; k = 0
	cmpi.w	#$3ff9,d0                       ; x < 2^-6?
	bcs.s	log2p1_series                   ; yes: k = 0
	beq.s	log2p1_reduce                   ; exactly 2^-6: no shift
log2p1_index_loop:
	subq.w	#1,d0                           ; one exponent less
	add.l	d2,d2                           ; shift the mantissa left
	roxl.l	#1,d1                           ; carry
	roxl.w	#1,d3                           ; top bit into k
	cmpi.w	#$3ff9,d0                       ; at 2^-6?
	bne.s	log2p1_index_loop               ; no
log2p1_reduce:
	tst.l	d1                              ; remainder r: top bit set?
	bpl.s	log2p1_small_rest               ; no: r < 1/64
	neg.l	d2                              ; 1/32 - r
	negx.l	d1                              ; high long
	bvs.s	log2p1_normalize                ; r = 1/64 exactly: keep it
	addq.w	#1,d3                           ; k + 1
	ori.w	#$8000,d0                       ; r = -(1/32 - r)
log2p1_small_rest:
	bne.s	log2p1_normalize                ; remainder nonzero
	tst.l	d2                              ; low long zero too?
	beq.s	log2p1_series                   ; zero
log2p1_normalize:
	bsr.w	fp_normalize                    ; normalise r
log2p1_series:
	add.w	d3,d3                           ; k * 2
	move.w	d3,d4                           ; 2k
	add.w	d4,d4                           ; k * 4
	add.w	d4,d4                           ; k * 8
	add.w	d4,d3                           ; k * 10: table offset
	move.l	d2,-(sp)                        ; r on the stack
	move.l	d1,-(sp)                        ; r mantissa high
	move.w	d0,-(sp)                        ; r exponent
	lea	(a1),a6                         ; a6 = result
	lea	(sp),a1                         ; a1 = r
	lea	-$a(sp),sp                      ; room for T
	move.w	#$4000,(sp)                     ; T exponent: 2
	addi.w	#$100,d4                        ; k * 8 + $100
	lsl.w	#7,d4                           ; * 128: mantissa top word $8000 + k * $400 = 1 + k/32
	bcc.s	log2p1_denominator              ; k < 32
	move.w	#$4001,(sp)                     ; k = 32: T = 4
	move.w	#$8000,d4                       ; mantissa top word $8000
log2p1_denominator:
	swap	d4                              ; top word up
	clr.w	d4                              ; low word zero
	move.l	d4,2(sp)                        ; T mantissa
	clr.l	6(sp)                           ; rest zero
	lea	(sp),a0                         ; a0 = T
	bsr.w	soft_fadd                       ; T = 2(1 + k/32) + r
	exg	a0,a1                           ; a0 = r, a1 = T
	bsr.w	soft_fdiv                       ; s = r / T
	bsr.w	soft_square                     ; T = s^2
	lea	log2p1_fraction(pc),a5          ; a5 = end of the coefficients
	lea	$a(a6),a0                       ; end of the result
	move.l	-(a5),-(a0)                     ; result = 2/(7 ln2)
	move.l	-(a5),-(a0)                     ; coefficient mantissa high
	move.w	-(a5),-(a0)                     ; coefficient exponent
	moveq	#2,d4                           ; 3 more coefficients
log2p1_horner:
	bsr.w	soft_fmul                       ; result * s^2
	lea	-$a(a5),a5                      ; previous coefficient
	exg	a1,a5                           ; a1 = coefficient
	bsr.w	soft_fadd                       ; result + coefficient
	exg	a1,a5                           ; a5 back
	dbra	d4,log2p1_horner                ; for each coefficient
	lea	$a(sp),a1                       ; a1 = s
	bsr.w	soft_fmul                       ; result * s
	lea	log2_table(pc),a1               ; log2(1 + k/32) table
	adda.w	d3,a1                           ; + k * 10
	bsr.w	soft_fadd                       ; result + log2(1 + k/32)
	lea	$14(sp),sp                      ; drop r and T
	movem.l	(sp)+,d3-d4/a5-a6
	rts

;------------------------------------------------------------------------------
; log2(x): 4(sp) = result pointer, 8(sp) = long double x
;------------------------------------------------------------------------------
log2:
	lea	8(sp),a0                        ; a0 = x
	movea.l	4(sp),a1                        ; a1 = result

;------------------------------------------------------------------------------
; log2(x): a0 = x, a1 = result; FLOG2 on the 68881 if fitted, else in software; changes d0-d2
; software: x = m * 2^e with 1 <= m < 2, log2(x) = e + log2p1_fraction(m - 1);
; x = 0 gives -infinity (range error), x < 0 or NaN gives NaN (domain error)
;------------------------------------------------------------------------------
ext_log2:	; from: ext_log2p1
	move.w	#$4816,d2                       ; FLOG2
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_unary                    ; yes

soft_log2:	; from: log, ext_log10
	bsr.w	fp_classify                     ; classify x
	bmi.s	soft_log2_sign                  ; finite non-zero
	bgt.s	soft_log2_domain                ; NaN
	bcs.s	soft_log2_domain                ; -infinity
	bne.w	fp_store                        ; +infinity: result +infinity
	pea	log_name(pc)                    ; zero: tag
	bsr.w	fp_range_minus_inf              ; -infinity, range error
	rts
soft_log2_sign:
	tst.w	d0                              ; negative?
	bpl.s	soft_log2_finite                ; no
soft_log2_domain:
	pea	log_name(pc)                    ; NaN, -infinity or negative: tag
	bsr.w	fp_domain_nan                   ; NaN, domain error
	rts
soft_log2_finite:
	lea	fpu_flags(pc),a0                ; mode word
	move.w	(a0),-(sp)                      ; save it
	clr.w	(a0)                            ; clear it for the calculation
	tst.l	d1                              ; normalised?
	bmi.s	soft_log2_split                 ; yes
soft_log2_normalize:
	subq.w	#1,d0                           ; normalise
	add.l	d2,d2                           ; shift the mantissa left
	addx.l	d1,d1                           ; carry
	bpl.s	soft_log2_normalize             ; until the integer bit is set
soft_log2_split:
	bclr	#$1f,d1                         ; integer bit off
	move.l	d2,-(sp)                        ; f = m - 1 on the stack
	move.l	d1,-(sp)                        ; f mantissa high
	move.w	#$3fff,-(sp)                    ; with the exponent of 1.0
	lea	(sp),a0                         ; a0 = f
	moveq	#0,d1                           ; e as a long double: exponent word
	subi.w	#$3fff,d0                       ; e = exponent - bias
	bmi.s	soft_log2_negative_exp          ; negative
	beq.s	soft_log2_add_exp               ; zero: 0.0
	move.w	#$400e,d1                       ; positive: 2^15 with e in the top word
	bra.s	soft_log2_add_exp               ; on
soft_log2_negative_exp:
	neg.w	d0                              ; |e|
	move.w	#$c00e,d1                       ; negative
soft_log2_add_exp:
	clr.l	-(sp)                           ; e on the stack
	clr.w	-(sp)
	move.w	d0,-(sp)                        ; e in the top mantissa word
	move.w	d1,-(sp)                        ; exponent word
	pea	(a1)                            ; save the result pointer
	bsr.w	log2p1_fraction                 ; result = log2(1 + f)
	movea.l	(sp)+,a0                        ; a0 = result
	lea	(sp),a1                         ; a1 = e
	bsr.w	soft_fadd                       ; result + e
	lea	$14(sp),sp                      ; drop f and e
	move.w	(sp)+,fpu_flags                 ; restore the mode word
	rts

;------------------------------------------------------------------------------
; log(x): 4(sp) = result pointer, 8(sp) = long double x; 68881 FLOGN or log2(x) * ln 2
; ext_log: a0 = x, a1 = result; changes d0-d2/a0
;------------------------------------------------------------------------------
log:
	lea	8(sp),a0                        ; a0 = x
	movea.l	4(sp),a1                        ; a1 = result
ext_log:
	move.w	#$4814,d2                       ; FLOGN
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_unary                    ; yes
	pea	(a1)                            ; save the result pointer
	bsr.w	soft_log2                       ; result = log2(x)
	movea.l	(sp)+,a0                        ; a0 = result
	lea	fpu_flags(pc),a1                ; mode word
	move.w	(a1),-(sp)                      ; save it
	clr.w	(a1)                            ; clear it
	lea	fp_ln2(pc),a1                   ; ln 2
	bsr.w	soft_fmul                       ; result * ln 2
	move.w	(sp)+,fpu_flags                 ; restore the mode word
	rts

;------------------------------------------------------------------------------
; log10(x): 4(sp) = result pointer, 8(sp) = long double x; 68881 FLOG10 or log2(x) * log10(2)
; ext_log10: a0 = x, a1 = result; changes d0-d2/a0
;------------------------------------------------------------------------------
log10:
	lea	8(sp),a0                        ; a0 = x
	movea.l	4(sp),a1                        ; a1 = result

ext_log10:	; from: print_g_float
	move.w	#$4815,d2                       ; FLOG10
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_unary                    ; yes
	pea	(a1)                            ; save the result pointer
	bsr.w	soft_log2                       ; result = log2(x)
	movea.l	(sp)+,a0                        ; a0 = result
	lea	fpu_flags(pc),a1                ; mode word
	move.w	(a1),-(sp)                      ; save it
	clr.w	(a1)                            ; clear it
	lea	fp_log10_2(pc),a1               ; log10(2)
	bsr.w	soft_fmul                       ; result * log10(2)
	move.w	(sp)+,fpu_flags                 ; restore the mode word
	rts

;------------------------------------------------------------------------------
; log1p(x) = ln(1+x): 4(sp) = result pointer, 8(sp) = long double x; 68881 FLOGNP1 or
; log2p1(x) * ln 2; ext_log1p: a0 = x, a1 = result; changes d0-d2/a0
;------------------------------------------------------------------------------
log1p:
	lea	8(sp),a0                        ; a0 = x
	movea.l	4(sp),a1                        ; a1 = result
ext_log1p:
	move.w	#$4806,d2                       ; FLOGNP1
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_unary                    ; yes
	pea	(a1)                            ; save the result pointer
	bsr.s	ext_log2p1                      ; result = log2(1 + x)
	movea.l	(sp)+,a0                        ; a0 = result
	lea	fpu_flags(pc),a1                ; mode word
	move.w	(a1),-(sp)                      ; save it
	clr.w	(a1)                            ; clear it
	lea	fp_ln2(pc),a1                   ; ln 2
	bsr.w	soft_fmul                       ; result * ln 2
	move.w	(sp)+,fpu_flags                 ; restore the mode word
	rts

;------------------------------------------------------------------------------
; log2p1(x) = log2(1+x): 4(sp) = result pointer, 8(sp) = long double x
;------------------------------------------------------------------------------
log2p1:
	lea	8(sp),a0                        ; a0 = x
	movea.l	4(sp),a1                        ; a1 = result

;------------------------------------------------------------------------------
; log2(1+x) in software: a0 = x, a1 = result; changes d0-d2/a0-a1
; 0 <= x < 1: log2p1_fraction directly; -0.5 < x < 0: -log2p1_fraction(-x/(1+x));
; otherwise log2(1 + x)
;------------------------------------------------------------------------------
ext_log2p1:	; from: log1p
	bsr.w	fp_classify                     ; classify x
	tst.w	d0                              ; negative?
	bmi.s	ext_log2p1_negative             ; yes
	cmpi.w	#$3fff,d0                       ; below 1.0?
	blt.w	log2p1_fraction                 ; yes: table and series
ext_log2p1_direct:
	lea	fpu_flags(pc),a0                ; mode word
	move.w	(a0),-(sp)                      ; save it
	clr.w	(a0)                            ; clear it
	move.l	d2,-(sp)                        ; copy of x on the stack
	move.l	d1,-(sp)                        ; copy mantissa high
	move.w	d0,-(sp)                        ; copy exponent
	lea	(sp),a0                         ; a0 = copy
	pea	(a1)                            ; save the result pointer
	bsr.w	soft_finc                       ; copy + 1
	movea.l	(sp)+,a1                        ; a1 = result
	bsr.w	ext_log2                        ; result = log2(x + 1)
	lea	$a(sp),sp                       ; drop the copy
	bra.s	ext_log2p1_done                 ; on
ext_log2p1_negative:
	cmpi.w	#$bffe,d0                       ; x <= -0.5?
	bge.s	ext_log2p1_direct               ; yes: log2(x + 1) directly
	lea	fpu_flags(pc),a0                ; mode word
	move.w	(a0),-(sp)                      ; save it
	clr.w	(a0)                            ; clear it
	move.l	d2,-(sp)                        ; copy of x
	move.l	d1,-(sp)                        ; copy mantissa high
	move.w	d0,-(sp)                        ; copy exponent
	lea	(sp),a0                         ; a0 = x
	move.l	d2,-(sp)                        ; second copy
	move.l	d1,-(sp)                        ; second copy mantissa high
	move.w	d0,-(sp)                        ; second copy exponent
	bchg	#$7,(sp)                        ; negated: -x
	pea	(a1)                            ; save the result pointer
	bsr.w	soft_finc                       ; x + 1
	lea	(a0),a1                         ; a1 = 1 + x
	lea	4(sp),a0                        ; a0 = -x
	bsr.w	soft_fdiv                       ; -x / (1 + x)
	movea.l	(sp),a1                         ; a1 = result
	bsr.w	log2p1_fraction                 ; log2(1 - x/(1+x)) = -log2(1 + x)
	movea.l	(sp)+,a1                        ; a1 = result
	bchg	#$7,(a1)                        ; negate
	lea	$14(sp),sp                      ; drop the copies
ext_log2p1_done:
	move.w	(sp)+,fpu_flags                 ; restore the mode word
	rts

;------------------------------------------------------------------------------
; fabs(x): 4(sp) = result pointer, 8(sp) = long double x
; ext_fabs: a0 = x, a1 = result; copies x with the sign cleared
;------------------------------------------------------------------------------
fabs:
	lea	8(sp),a0                        ; a0 = x
	movea.l	4(sp),a1                        ; a1 = result

ext_fabs:	; from: print_g_float
	move.w	(a0)+,(a1)+                     ; exponent word
	move.l	(a0)+,(a1)+                     ; mantissa
	move.l	(a0)+,(a1)+                     ; low long
	bclr	#$7,-$a(a1)                     ; clear the sign
	rts

;------------------------------------------------------------------------------
; square(x) = x*x: 4(sp) = result pointer, 8(sp) = long double x; FMUL on the 68881
;------------------------------------------------------------------------------
square:	; from: soft_square
	lea	8(sp),a0                        ; a0 = x
	movea.l	4(sp),a1                        ; a1 = result
	btst	#$7,fpu_flags                   ; 68881?
	beq.s	soft_square                     ; no: software
	move.w	#$4823,d2                       ; FMUL
	move.w	(a0),(a1)                       ; copy x to the result
	move.l	2(a0),2(a1)                     ; mantissa high
	move.l	6(a0),6(a1)                     ; mantissa low
	exg	a0,a1                           ; a0 = result, a1 = x
	bsr.w	fpu_op_ext                      ; result * x on the 68881
	exg	a0,a1                           ; registers back
	rts

;------------------------------------------------------------------------------
; x*x in software: a0 = x, a1 = result; changes d0-d2
; the mantissa words A3:A2:A1:A0 (d1, d2) are squared from 16-bit mulu products, cross terms
; doubled; the top 64 bits are kept and rounded half up from the next 16
;------------------------------------------------------------------------------
soft_square:	; from: log2p1_fraction, square
	movem.l	d3-d6,-(sp)
	movem.l	-$2(a0),d0-d2                   ; d0 = exponent, d1:d2 = mantissa
	andi.w	#$7fff,d0                       ; drop the sign
	cmpi.w	#$7fff,d0                       ; infinity or NaN?
	beq.w	soft_square_store               ; yes: copy
	tst.l	d1                              ; normalised?
	bmi.s	soft_square_product             ; yes
	bne.s	soft_square_normalize           ; denormal
	tst.l	d2                              ; low long zero too?
	beq.w	soft_square_store               ; zero: copy
soft_square_normalize:
	bsr.w	fp_normalize                    ; normalise
soft_square_product:
	add.w	d0,d0                           ; exponent * 2
	subi.w	#$3ffe,d0                       ; - bias
	moveq	#0,d6                           ; d6 = 0 for carries
	move.w	d2,d5                           ; A0 * A2
	mulu.w	d1,d5                           ; product
	move.w	d1,d4                           ; A2 * A2
	mulu.w	d1,d4                           ; product
	add.l	d5,d5                           ; A0 * A2 twice
	addx.l	d6,d4                           ; carry
	swap	d1                              ; d1.w = A3
	swap	d2                              ; d2.w = A1
	move.w	d2,d3                           ; A1 * A1
	mulu.w	d2,d3                           ; product
	add.l	d3,d5                           ; added
	addx.l	d6,d4                           ; carry
	move.w	d4,d5                           ; down 16 bits
	clr.w	d4                              ; d4 = top word
	swap	d4
	swap	d5                              ; d5 = d4 low : d5 high
	move.l	d2,d3                           ; A0 * A3
	swap	d3                              ; A0
	mulu.w	d1,d3                           ; times A3
	add.l	d3,d5                           ; added
	addx.l	d6,d4                           ; carry
	add.l	d3,d5                           ; and again
	addx.l	d6,d4                           ; carry
	move.l	d1,d3                           ; A1 * A2
	swap	d3                              ; A2
	mulu.w	d2,d3                           ; times A1
	add.l	d3,d5                           ; added
	addx.l	d6,d4                           ; carry
	add.l	d3,d5                           ; and again
	addx.l	d6,d4                           ; carry
	move.l	d1,d3                           ; A2 * A3
	swap	d3                              ; A2
	mulu.w	d1,d3                           ; times A3
	add.l	d3,d4                           ; added
	add.l	d3,d4                           ; and again
	addx.l	d6,d6                           ; carry
	move.w	d5,d3                           ; d3 = rounding word
	move.w	d4,d5                           ; down 16 bits
	move.w	d6,d4                           ; d5 = d4 low : d5 high
	swap	d4                              ; d4 = carries : d4 high
	swap	d5
	moveq	#0,d6                           ; carries
	mulu.w	d1,d2                           ; A1 * A3
	add.l	d2,d5                           ; added
	addx.l	d6,d4                           ; carry
	add.l	d5,d2                           ; and again
	addx.l	d6,d4                           ; carry
	mulu.w	d1,d1                           ; A3 * A3
	add.l	d4,d1                           ; top long
	bmi.s	soft_square_round               ; normalised
	add.w	d3,d3                           ; shift left one
	addx.l	d2,d2                           ; shift
	addx.l	d1,d1                           ; shift
	subq.w	#1,d0                           ; exponent - 1
soft_square_round:
	add.w	d3,d3                           ; top rounding bit
	addx.l	d6,d2                           ; round half up
	addx.l	d6,d1                           ; carry
	bne.s	soft_square_range               ; no carry out
	bset	#$1f,d1                         ; mantissa overflow: 1.0
	addq.w	#1,d0                           ; exponent + 1
soft_square_range:
	cmpi.w	#$7fff,d0                       ; exponent in range?
	bcs.s	soft_square_store               ; yes
	move.w	(a0),(a1)                       ; sign and exponent of x into the result
	exg	a0,a1                           ; a0 = result
	addq.w	#6,a0                           ; past the exponent and first long
	pea	square(pc)                      ; tag: square
	bsr.w	fp_out_of_range                 ; overflow or underflow result
	exg	a0,a1                           ; registers back
	bra.s	soft_square_return              ; done
soft_square_store:
	move.w	d0,(a1)+                        ; store the result
	move.l	d1,(a1)+                        ; mantissa high
	move.l	d2,(a1)                         ; mantissa low
	subq.w	#6,a1                           ; a1 = result
soft_square_return:
	movem.l	(sp)+,d3-d6
	rts

;------------------------------------------------------------------------------
; long double op double, one entry per operation (add, sub, mul, div, rem, cmp)
; a0 = long double operand and result, a1 = double; 68881 if fitted (d2 = command word),
; else the double is converted to a long double temporary and the software routine is called
;------------------------------------------------------------------------------
fadd_double:
	move.w	#$5422,d2                       ; FADD, double source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_double                   ; yes
	pea	soft_fadd(pc)                   ; software add
	bra.s	op_with_double                  ; convert and call
fsub_double:
	move.w	#$5428,d2                       ; FSUB, double source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_double                   ; yes
	pea	soft_fsub(pc)                   ; software subtract
	bra.s	op_with_double                  ; convert and call
fmul_double:
	move.w	#$5423,d2                       ; FMUL, double source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_double                   ; yes
	pea	soft_fmul(pc)                   ; software multiply
	bra.s	op_with_double                  ; convert and call
fdiv_double:
	move.w	#$5420,d2                       ; FDIV, double source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_double                   ; yes
	pea	soft_fdiv(pc)                   ; software divide
	bra.s	op_with_double                  ; convert and call
frem_double:
	move.w	#$5425,d2                       ; FREM, double source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_double                   ; yes
	pea	soft_frem(pc)                   ; software remainder
	bra.s	op_with_double                  ; convert and call
fcmp_double:
	pea	soft_fcmp(pc)                   ; software compare
op_with_double:
	pea	(a0)                            ; save a0
	lea	-$a(sp),sp                      ; temporary
	lea	(a1),a0                         ; a0 = double
	lea	(sp),a1                         ; a1 = temporary
	bsr.w	fp_from_double                  ; double to long double
	movea.l	$a(sp),a0                       ; a0 = first operand
	pea	op_with_double_done(pc)         ; return here
	move.l	$12(sp),-(sp)                   ; operation address
	rts                                     ; call it
op_with_double_done:
	lea	$12(sp),sp                      ; drop the temporary, a0 and the address
	rts

;------------------------------------------------------------------------------
; long double op float, one entry per operation (add, sub, mul, div, rem, cmp)
; a0 = long double operand and result, d0 = float; 68881 if fitted (d2 = command word)
;------------------------------------------------------------------------------
fadd_float:
	move.w	#$4422,d2                       ; FADD, single source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_fadd(pc)                   ; software add
	lea	fp_from_float(pc),a1            ; converter: float in d0
	bra.w	op_with_converted               ; convert and call
fsub_float:
	move.w	#$4428,d2                       ; FSUB, single source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_fsub(pc)                   ; software subtract
	lea	fp_from_float(pc),a1            ; converter: float in d0
	bra.w	op_with_converted               ; convert and call
fmul_float:
	move.w	#$4423,d2                       ; FMUL, single source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_fmul(pc)                   ; software multiply
	lea	fp_from_float(pc),a1            ; converter: float in d0
	bra.w	op_with_converted               ; convert and call
fdiv_float:
	move.w	#$4420,d2                       ; FDIV, single source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_fdiv(pc)                   ; software divide
	lea	fp_from_float(pc),a1            ; converter: float in d0
	bra.w	op_with_converted               ; convert and call
frem_float:
	move.w	#$4425,d2                       ; FREM, single source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_frem(pc)                   ; software remainder
	lea	fp_from_float(pc),a1            ; converter: float in d0
	bra.w	op_with_converted               ; convert and call
fcmp_float:
	pea	soft_fcmp(pc)                   ; software compare
	lea	fp_from_float(pc),a1            ; converter: float in d0
	bra.w	op_with_converted               ; convert and call

;------------------------------------------------------------------------------
; long double op int / long, an int entry (ext.l d0) before each long entry
; (add, sub, mul, div, rem, cmp); a0 = long double operand and result, d0 = integer
;------------------------------------------------------------------------------
fadd_int:
	ext.l	d0                              ; int to long
fadd_long:
	move.w	#$4022,d2                       ; FADD, long source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_fadd(pc)                   ; software add
	bra.s	op_with_long                    ; convert and call
fsub_int:
	ext.l	d0                              ; int to long
fsub_long:
	move.w	#$4028,d2                       ; FSUB, long source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_fsub(pc)                   ; software subtract
	bra.s	op_with_long                    ; convert and call
fmul_int:
	ext.l	d0                              ; int to long
fmul_long:
	move.w	#$4023,d2                       ; FMUL, long source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_fmul(pc)                   ; software multiply
	bra.s	op_with_long                    ; convert and call
fdiv_int:
	ext.l	d0                              ; int to long

fdiv_long:	; from: load_and_unpack
	move.w	#$4020,d2                       ; FDIV, long source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_fdiv(pc)                   ; software divide
	bra.s	op_with_long                    ; convert and call
frem_int:
	ext.l	d0                              ; int to long
frem_long:
	move.w	#$4025,d2                       ; FREM, long source
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_d0                       ; yes
	pea	soft_frem(pc)                   ; software remainder
	bra.s	op_with_long                    ; convert and call
fcmp_int:
	ext.l	d0                              ; int to long
fcmp_long:
	pea	soft_fcmp(pc)                   ; software compare
op_with_long:	; from: fadd_int
	lea	fp_from_long(pc),a1             ; converter: long in d0
op_with_converted:	; from: fadd_float
	pea	(a0)                            ; save a0
	lea	-$a(sp),sp                      ; temporary
	lea	(sp),a0                         ; a0 = temporary
	jsr	(a1)                            ; convert d0 into it
	lea	(sp),a1                         ; a1 = temporary
	movea.l	$a(sp),a0                       ; a0 = first operand
	pea	op_with_converted_done(pc)      ; return here
	move.l	$12(sp),-(sp)                   ; operation address
	rts                                     ; call it
op_with_converted_done:
	lea	$12(sp),sp                      ; drop the temporary, a0 and the address
	rts

;------------------------------------------------------------------------------
; condition codes for soft_fcmp, indexed by NZVC of the subtraction:
; $19 less (X N C), 0 greater, 4 equal
;------------------------------------------------------------------------------
fcmp_ccr_table:	; from: soft_fcmp
	dc.w	$0000,$1919,$0404,$0404,$1919,$0000 ; NZVC 0-1 greater, 2-3 less, 4-7 equal, 8-9 less, $a-$b greater

;------------------------------------------------------------------------------
; compare two long doubles: (a0) with (a1), result in the condition codes as for cmp
; (V set if either is NaN); changes d0-d2
; negative values are complemented so that the 80-bit patterns compare as signed integers
;------------------------------------------------------------------------------
soft_fcmp:	; from: fadd_double, fadd_float, fdiv_long
	movem.l	d3-d6,-(sp)
	pea	soft_fcmp_compare(pc)           ; return to the compare
	bra.w	fp_dispatch                     ; unpack, special cases return into the table below
soft_fcmp_unordered:
	moveq	#2,d0                           ; NaN: V set, unordered
	bra.s	soft_fcmp_return                ; return
	bra.s	soft_fcmp_unordered             ; NaN
	bra.s	soft_fcmp_unordered             ; NaN
	bra.s	soft_fcmp_unordered             ; NaN
	bra.s	soft_fcmp_compare               ; infinity and infinity: compare
	bra.s	soft_fcmp_compare               ; infinity and zero: compare
	bra.s	soft_fcmp_compare               ; infinity and number: compare
	bra.s	soft_fcmp_compare               ; zero and infinity: compare
	bra.s	soft_fcmp_subtract              ; both zero: equal whatever the signs
	nop                                     ; zero and number: compare
	nop                                     ; number and infinity: compare
	nop                                     ; number and zero: compare
soft_fcmp_compare:
	tst.w	d0                              ; first exponent negative (denormal)?
	bpl.s	soft_fcmp_sign_a                ; no
soft_fcmp_denormal_a:
	lsr.l	#1,d1                           ; shift back to exponent 0
	roxr.l	#1,d2                           ; shift
	addq.w	#1,d0                           ; exponent + 1
	bne.s	soft_fcmp_denormal_a            ; until exponent 0
soft_fcmp_sign_a:
	tst.l	d0                              ; negative?
	bpl.s	soft_fcmp_exp_b                 ; no
	not.l	d1                              ; complement, so that it orders as an integer
	not.l	d2
	not.w	d0                              ; exponent word too
soft_fcmp_exp_b:
	tst.w	d3                              ; second exponent negative?
	bpl.s	soft_fcmp_sign_b                ; no
soft_fcmp_denormal_b:
	lsr.l	#1,d4                           ; shift back to exponent 0
	roxr.l	#1,d5                           ; shift
	addq.w	#1,d3                           ; exponent + 1
	bne.s	soft_fcmp_denormal_b            ; until exponent 0
soft_fcmp_sign_b:
	tst.l	d3                              ; negative?
	bpl.s	soft_fcmp_subtract              ; no
	not.l	d4                              ; complement
	not.l	d5
	not.w	d3                              ; exponent word too
soft_fcmp_subtract:
	sub.l	d5,d2                           ; 96-bit first - second
	subx.l	d4,d1                           ; high long
	subx.w	d3,d0                           ; sign and exponent
	move.w	sr,d0                           ; flags
	andi.w	#$f,d0                          ; NZVC
	move.b	fcmp_ccr_table(pc,d0.w),d0      ; translate
soft_fcmp_return:
	move.w	d0,ccr                          ; as the result
	movem.l	(sp)+,d3-d6
	rts

;------------------------------------------------------------------------------
; function name passed to the math error handler
;------------------------------------------------------------------------------
add_name:	; from: soft_fadd
	dc.b	'add',0
	dc.w	$434c,$0ddc

;------------------------------------------------------------------------------
; long double add, subtract, increment and decrement; 68881 if fitted, else software
; a0 = operand and result, a1 = second operand (1.0 for inc/dec); changes d0-d2
; fp_dispatch unpacks both operands (d0/d1:d2 and d3/d4:d5, sign in the top word of d0/d3)
; and returns into the bra.s table before soft_fadd_main for zeros, infinities and NaNs
; method: the larger operand first, the smaller shifted right with guard and sticky bits in d3,
; mantissas added or subtracted, then rounded by the mode in fpu_mode: bit 7 clear = to nearest
; (ties to even), else bit 6 clear = toward zero, bit 5 set = toward +infinity, clear = toward
; -infinity
;------------------------------------------------------------------------------
ext_fsub:
	btst	#$7,fpu_flags                   ; 68881?
	beq.s	soft_fsub                       ; no: software
	move.w	#$4828,d2                       ; FSUB
	bra.w	fpu_op_ext                      ; on the 68881
soft_fdec:
	lea	fp_one(pc),a1                   ; a1 = 1.0
soft_fsub:	; from: fadd_double, fadd_float, fadd_int
	movem.l	d3-d6,-(sp)
	pea	soft_fadd_main(pc)              ; return to the add
	bra.w	fp_dispatch_neg                 ; unpack, second operand negated
ext_finc:
	lea	fp_one(pc),a1                   ; a1 = 1.0
ext_fadd:
	btst	#$7,fpu_flags                   ; 68881?
	beq.s	soft_fadd                       ; no
	move.w	#$4822,d2                       ; FADD
	bra.w	fpu_op_ext                      ; on the 68881

soft_finc:	; from: ext_log2p1
	lea	fp_one(pc),a1                   ; a1 = 1.0

soft_fadd:	; from: log2p1_fraction, soft_log2, fadd_double, fadd_float, fadd_int, ext_fsub
	movem.l	d3-d6,-(sp)
	pea	soft_fadd_main(pc)              ; return to the add
	bra.w	fp_dispatch                     ; unpack; special cases return into the table below
soft_fadd_zeros:
	eor.l	d3,d0                           ; signs differ?
	bmi.w	soft_fadd_zero_result           ; 0 + -0: zero by the rounding mode
soft_fadd_second:
	move.l	d3,d0                           ; result = second operand
	move.l	d4,d1                           ; its mantissa
	move.l	d5,d2
soft_fadd_first:
	tst.w	d0                              ; exponent negative (denormal)?
	bpl.w	soft_fadd_store                 ; no: store
	lsr.l	#1,d1                           ; shift back to exponent 0
	roxr.l	#1,d2                           ; shift
	addq.w	#1,d0                           ; exponent + 1
	bra.s	soft_fadd_first                 ; until exponent 0
soft_fadd_infinities:
	eor.l	d0,d3                           ; same signs?
	bpl.s	soft_fadd_first                 ; yes: the infinity
soft_fadd_invalid:
	pea	add_name(pc)                    ; tag
	bsr.w	fp_invalid                      ; NaN result, invalid operation
	bra.w	soft_fadd_return                ; return
	bra.s	soft_fadd_invalid               ; NaN: invalid
	bra.s	soft_fadd_invalid               ; NaN: invalid
	bra.s	soft_fadd_invalid               ; NaN: invalid
	bra.s	soft_fadd_infinities            ; inf + inf
	bra.s	soft_fadd_first                 ; inf + 0: inf
	bra.s	soft_fadd_first                 ; inf + x: inf
	bra.s	soft_fadd_second                ; 0 + inf: inf
	bra.s	soft_fadd_zeros                 ; 0 + 0
	bra.s	soft_fadd_second                ; 0 + x: x
	bra.s	soft_fadd_second                ; x + inf: inf
	bra.s	soft_fadd_first                 ; x + 0: x
soft_fadd_main:	; from: ext_fsub
	move.l	d0,d6                           ; top word: sign difference
	eor.l	d3,d6                           ; xor of the signs
	move.w	d0,d6                           ; low word: exponent difference
	sub.w	d3,d6                           ; minus the second exponent
	bgt.s	soft_fadd_align                 ; first larger
	neg.w	d6                              ; second larger or equal
	bne.s	soft_fadd_swap                  ; second larger: swap
	cmp.l	d4,d1                           ; equal exponents: compare mantissas
	bhi.s	soft_fadd_align                 ; first larger
	bne.s	soft_fadd_swap                  ; second larger
	cmp.l	d2,d5                           ; low longs
	bls.s	soft_fadd_align                 ; first larger or equal
soft_fadd_swap:
	move.l	d3,d0                           ; larger operand's sign and exponent
	exg	d1,d4                           ; swap the mantissas
	exg	d2,d5
soft_fadd_align:
	moveq	#0,d3                           ; guard and sticky bits
	cmpi.w	#$9,d6                          ; up to 9 bits?
	bls.s	soft_fadd_align_bits            ; shift bit by bit
	cmpi.w	#$41,d6                         ; over 65 bits?
	bls.s	soft_fadd_align_32              ; no
	moveq	#0,d5                           ; the smaller one is gone
	moveq	#0,d4
	moveq	#1,d3                           ; only a sticky bit
	bra.s	soft_fadd_add                   ; add
soft_fadd_align_32:
	cmpi.w	#$21,d6                         ; over 33 bits?
	bls.s	soft_fadd_align_16              ; no
	or.l	d5,d3                           ; low long into sticky
	move.l	d4,d5                           ; shift 32
	moveq	#0,d4
	subi.w	#$20,d6                         ; 32 bits done
soft_fadd_align_16:
	cmpi.w	#$11,d6                         ; over 17 bits?
	bls.s	soft_fadd_align_8               ; no
	or.w	d5,d3                           ; low word into sticky
	move.w	d4,d5                           ; shift 16
	clr.w	d4
	swap	d4
	swap	d5
	subi.w	#$10,d6                         ; 16 bits done
soft_fadd_align_8:
	cmpi.w	#$9,d6                          ; over 9 bits?
	bls.s	soft_fadd_sticky                ; no
	or.b	d5,d3                           ; low byte into sticky
	move.b	d4,d5                           ; shift 8
	ror.l	#8,d5
	lsr.l	#8,d4
	subq.w	#8,d6                           ; 8 bits done
soft_fadd_sticky:
	tst.l	d3                              ; any sticky bits?
	beq.s	soft_fadd_align_bits            ; no
	move.w	#$fff,d3                        ; keep them below the guard bits
soft_fadd_align_bits:
	subq.w	#1,d6                           ; bits left to shift
	bmi.s	soft_fadd_add                   ; none
soft_fadd_align_loop:
	lsr.l	#1,d4                           ; shift right through the guard word
	roxr.l	#1,d5
	roxr.w	#1,d3                           ; into the guard word
	dbra	d6,soft_fadd_align_loop         ; for each bit
soft_fadd_add:
	tst.l	d6                              ; signs differ?
	bmi.s	soft_fadd_subtract              ; yes: subtract
	add.l	d5,d2                           ; add the mantissas
	addx.l	d4,d1                           ; with carry
	bcc.s	soft_fadd_round                 ; no carry out
	roxr.l	#1,d1                           ; carry back in at the top
	roxr.l	#1,d2
	roxr.w	#1,d3                           ; guard word too
	addq.w	#1,d0                           ; exponent + 1
soft_fadd_round:
	btst	#$7,fpu_mode                    ; directed rounding?
	bne.s	soft_fadd_directed              ; yes
	cmpi.w	#$8000,d3                       ; guard more than half?
	bhi.s	soft_fadd_round_up              ; yes: up
	bne.w	soft_fadd_range                 ; less: done
	btst	#$0,d2                          ; exactly half: even?
	beq.w	soft_fadd_range                 ; yes: done
soft_fadd_round_up:
	addq.l	#1,d2                           ; one unit up
	bcc.w	soft_fadd_range                 ; no carry: done
	addq.l	#1,d1
	bcc.w	soft_fadd_range                 ; no carry: done
	bset	#$1f,d1                         ; mantissa overflow: 1.0
	addq.w	#1,d0                           ; exponent + 1
	bra.w	soft_fadd_range                 ; done
soft_fadd_directed:
	tst.w	d3                              ; exact?
	beq.w	soft_fadd_range                 ; yes: done
	btst	#$6,fpu_mode                    ; toward zero?
	beq.w	soft_fadd_range                 ; yes: truncate
	btst	#$5,fpu_mode                    ; toward +infinity?
	bne.s	soft_fadd_round_plus            ; yes
	tst.l	d0                              ; toward -infinity: up if negative
	bmi.s	soft_fadd_round_up              ; negative: up
	bra.w	soft_fadd_range                 ; positive: done
soft_fadd_round_plus:
	tst.l	d0                              ; toward +infinity: up if positive
	bmi.w	soft_fadd_range                 ; negative: done
	bra.s	soft_fadd_round_up              ; positive: up
soft_fadd_subtract:
	sub.l	d5,d2                           ; subtract the mantissas
	subx.l	d4,d1                           ; with borrow
	bmi.s	soft_fadd_sub_round             ; still normalised
	beq.w	soft_fadd_zero_result           ; zero
	subq.w	#1,d0                           ; exponent - 1
	add.l	d2,d2                           ; shift left one
	addx.l	d1,d1                           ; with carry
	add.w	d3,d3                           ; and the guard word
	bcc.s	soft_fadd_sub_round             ; no borrow
	subq.l	#1,d2                           ; borrow one unit
	bcc.s	soft_fadd_sub_round             ; no borrow
	subq.l	#1,d1                           ; borrow into the high long
soft_fadd_sub_round:
	btst	#$7,fpu_mode                    ; directed rounding?
	bne.s	soft_fadd_sub_directed          ; yes
	cmpi.w	#$8000,d3                       ; more than half to take off?
	bhi.s	soft_fadd_round_down            ; yes: down
	bne.s	soft_fadd_normalize             ; less: done
	btst	#$0,d2                          ; exactly half: odd?
	bne.s	soft_fadd_round_down            ; yes: down
	tst.l	d2                              ; even: down only for mantissa 1.000...
	bne.s	soft_fadd_normalize             ; no
	cmp.l	#$80000000,d1                   ; top long $80000000?
	bne.s	soft_fadd_normalize             ; no
soft_fadd_round_down:
	subq.l	#1,d2                           ; one unit down
	bcc.s	soft_fadd_normalize             ; no borrow
	subq.l	#1,d1                           ; borrow into the high long
	bmi.s	soft_fadd_range                 ; still normalised
	beq.s	soft_fadd_zero_result           ; zero
	moveq	#-1,d2                          ; below 1.0: all ones
	moveq	#-1,d1
	subq.w	#1,d0                           ; exponent - 1
	btst	#$e,d3                          ; more than a quarter unit to take off?
	beq.s	soft_fadd_range                 ; no
	moveq	#-2,d2                          ; yes: one more unit down
	bra.s	soft_fadd_range                 ; done
soft_fadd_sub_directed:
	tst.w	d3                              ; exact?
	beq.s	soft_fadd_normalize             ; yes: done
	btst	#$6,fpu_mode                    ; toward zero?
	beq.s	soft_fadd_round_down            ; yes: truncate (down)
	btst	#$5,fpu_mode                    ; toward +infinity?
	bne.s	soft_fadd_sub_plus              ; yes
	tst.l	d0                              ; toward -infinity: down if positive
	bmi.s	soft_fadd_normalize             ; negative: keep
	bra.s	soft_fadd_round_down            ; positive: down
soft_fadd_sub_plus:
	tst.l	d0                              ; toward +infinity: down if negative
	bmi.s	soft_fadd_round_down            ; negative: down
soft_fadd_normalize:
	tst.l	d1                              ; normalised?
	bmi.s	soft_fadd_range                 ; yes
soft_fadd_normalize_loop:
	subq.w	#1,d0                           ; shift left until normalised
	add.l	d2,d2                           ; shift
	addx.l	d1,d1                           ; carry
	bpl.s	soft_fadd_normalize_loop        ; until the integer bit is set
soft_fadd_range:
	cmpi.w	#$7fff,d0                       ; exponent in range?
	bcs.s	soft_fadd_store                 ; yes: store
	pea	add_name(pc)                    ; tag
	pea	soft_fadd_return(pc)            ; return here
	cmpi.w	#$c000,d0                       ; negative exponent?
	bhi.w	fp_underflow                    ; underflow
	bra.w	fp_overflow                     ; overflow
soft_fadd_zero_result:
	clr.l	(a0)                            ; result zero
	clr.l	-(a0)                           ; clear the rest
	clr.w	-(a0)                           ; and the exponent
	btst	#$7,fpu_mode                    ; directed rounding?
	beq.s	soft_fadd_return                ; no: +0
	btst	#$5,fpu_mode                    ; toward +infinity?
	bne.s	soft_fadd_return                ; yes: +0
	bchg	#$7,(a0)                        ; otherwise -0
	bra.s	soft_fadd_return                ; return
soft_fadd_store:
	add.l	d0,d0                           ; sign into bit 15
	roxr.w	#1,d0
	move.l	d2,(a0)                         ; store the mantissa
	move.l	d1,-(a0)                        ; mantissa high
	move.w	d0,-(a0)                        ; and the exponent
soft_fadd_return:
	movem.l	(sp)+,d3-d6
	rts

;------------------------------------------------------------------------------
; long double multiply: (a0) = (a0) * (a1); 68881 if fitted, else software; changes d0-d2
; the 64 x 64-bit mantissa product is built from 16-bit mulu products, A3..A0 the words of the
; first operand (d1:d2), B3..B0 of the second (d4:d5); columns by word position, the lowest
; products (A0B0, A0B1, A1B0) only through fp_mul_low_product when rounding needs them
;------------------------------------------------------------------------------
ext_fmul:	; from: load_and_unpack, ext_pow10, soft_fmul, fmul_round_nearest
	move.w	#$4823,d2                       ; FMUL
	btst	#$7,fpu_flags                   ; 68881?
	bne.w	fpu_op_ext                      ; yes

soft_fmul:	; from: cvt_digits, log2p1_fraction, log, ext_log10, log1p, fadd_double, 2 more
	movem.l	d3-d7,-(sp)
	pea	soft_fmul_main(pc)              ; return to the multiply
	bra.w	fp_dispatch                     ; unpack; special cases return into the table below
soft_fmul_zero:
	eor.l	d3,d0                           ; sign of the product
	andi.l	#$80000000,d0                   ; sign only
	clr.l	(a0)                            ; zero
	clr.w	-(a0)                           ; clear
	move.l	d0,-(a0)                        ; zero with the sign
	bra.w	fmul_done                       ; return
soft_fmul_invalid:
	pea	ext_fmul(pc)                    ; tag
	bsr.w	fp_invalid                      ; NaN result, invalid operation
	bra.w	fmul_done                       ; return
soft_fmul_infinity:
	eor.l	d3,d0                           ; sign of the product
	swap	d0                              ; sign into the low word
	or.w	d6,d0                           ; exponent $7fff
	clr.l	(a0)                            ; infinity
	clr.l	-(a0)                           ; mantissa zero
	move.w	d0,-(a0)                        ; sign and exponent
	bra.w	fmul_done                       ; return
	move.l	d7,d0                           ; not reached: overflow exit with the saved sign
	clr.w	d0                              ; sign only
	pea	ext_fmul(pc)                    ; tag
	bsr.w	fp_out_of_range                 ; overflow or underflow result
	bra.w	fmul_done                       ; return
	bra.s	soft_fmul_invalid               ; NaN: invalid
	bra.s	soft_fmul_invalid               ; NaN: invalid
	bra.s	soft_fmul_invalid               ; NaN: invalid
	bra.s	soft_fmul_infinity              ; inf * inf: inf
	bra.s	soft_fmul_invalid               ; inf * 0: invalid
	bra.s	soft_fmul_infinity              ; inf * x: inf
	bra.s	soft_fmul_invalid               ; 0 * inf: invalid
	bra.s	soft_fmul_zero                  ; 0 * 0: 0
	bra.s	soft_fmul_zero                  ; 0 * x: 0
	bra.s	soft_fmul_infinity              ; x * inf: inf
	bra.s	soft_fmul_zero                  ; x * 0: 0
soft_fmul_main:
	move.l	d0,d7                           ; top word: sign of the product
	eor.l	d3,d7                           ; xor of the signs
	move.w	d0,d7                           ; low word: exponent sum
	add.w	d3,d7                           ; plus the second exponent
	subi.w	#$3ffe,d7                       ; - bias
	move.l	d7,-(sp)                        ; save it
	moveq	#0,d0                           ; carries
	move.w	d2,d6                           ; A0 * B2: column 2
	mulu.w	d4,d6                           ; product
	move.w	d1,d3                           ; A2 * B2: column 4
	mulu.w	d4,d3                           ; product
	move.w	d1,d7                           ; A2 * B0: column 2
	mulu.w	d5,d7                           ; product
	add.l	d7,d6                           ; added
	addx.l	d0,d3                           ; carry
	swap	d1                              ; low words now A3, A1, B3, B1
	swap	d2
	swap	d4
	swap	d5
	move.w	d2,d7                           ; A1 * B1: column 2
	mulu.w	d5,d7                           ; product
	add.l	d7,d6                           ; added
	addx.l	d0,d3                           ; carry
	move.w	d6,-(sp)                        ; column 2 low word kept for rounding
	move.w	d3,d6                           ; down 16 bits
	clr.w	d3
	swap	d3                              ; d3 = top word
	swap	d6                              ; d6 = d3 low : d6 high
	move.l	d2,d7                           ; A0 * B3: column 3
	swap	d7                              ; A0
	mulu.w	d4,d7                           ; times B3
	add.l	d7,d6                           ; added
	addx.l	d0,d3                           ; carry
	move.l	d4,d7                           ; A1 * B2: column 3
	swap	d7                              ; B2
	mulu.w	d2,d7                           ; times A1
	add.l	d7,d6                           ; added
	addx.l	d0,d3                           ; carry
	move.l	d1,d7                           ; A2 * B1: column 3
	swap	d7                              ; A2
	mulu.w	d5,d7                           ; times B1
	add.l	d7,d6                           ; added
	addx.l	d0,d3                           ; carry
	move.l	d5,d7                           ; A3 * B0: column 3
	swap	d7                              ; B0
	mulu.w	d1,d7                           ; times A3
	add.l	d7,d6                           ; added
	addx.l	d0,d3                           ; carry
	move.l	d1,d7                           ; A2 * B3: column 5
	swap	d7                              ; A2
	mulu.w	d4,d7                           ; times B3
	add.l	d7,d3                           ; added
	move.l	d4,d7                           ; A3 * B2: column 5
	swap	d7                              ; B2
	mulu.w	d1,d7                           ; times A3
	add.l	d7,d3                           ; added
	addx.l	d0,d0                           ; carry
	move.w	d6,-(sp)                        ; column 3 low word kept for rounding
	move.w	d3,d6                           ; down 16 bits
	move.w	d0,d3                           ; carries
	swap	d3                              ; d3 = carries : d3 high
	swap	d6                              ; d6 = d3 low : d6 high
	moveq	#0,d0                           ; carries
	move.w	d2,d7                           ; A1 * B3: column 4
	mulu.w	d4,d7                           ; product
	add.l	d7,d6                           ; added
	addx.l	d0,d3                           ; carry
	move.w	d1,d7                           ; A3 * B1: column 4
	mulu.w	d5,d7                           ; product
	add.l	d7,d6                           ; added
	addx.l	d0,d3                           ; carry
	move.w	d1,d7                           ; A3 * B3: column 6
	mulu.w	d4,d7                           ; product
	add.l	d7,d3                           ; added
	move.l	(sp)+,d4                        ; d4 = the kept low words
	move.l	(sp)+,d1                        ; d1 = sign and exponent
	move.l	d4,d7                           ; d7 = rounding bits
	tst.l	d3                              ; product below 2?
	bmi.s	soft_fmul_round                 ; no
	add.l	d7,d7                           ; the rounding bits move up one
soft_fmul_round:
	btst	#$7,fpu_mode                    ; directed rounding?
	beq.w	fmul_round_nearest              ; no: nearest
	tst.l	d7                              ; rounding bits zero?
	beq.s	soft_fmul_low_bits              ; yes: the low products decide
	bpl.s	soft_fmul_directed              ; some, well below all ones
	cmpi.l	#$fffe0001,d7                   ; nearly all ones?
	bls.s	soft_fmul_directed              ; no
soft_fmul_low_bits:
	bsr.s	fmul_low_product                ; add the low products
	tst.l	d4                              ; still exact?
	bne.s	soft_fmul_directed              ; no
	tst.l	d7                              ; rounding bits too?
	beq.w	fmul_truncate                   ; yes: no rounding
soft_fmul_directed:
	btst	#$6,fpu_mode                    ; toward zero?
	beq.w	fmul_truncate                   ; yes: truncate
	btst	#$5,fpu_mode                    ; toward +infinity?
	bne.s	soft_fmul_round_plus            ; yes
	tst.l	d1                              ; toward -infinity: up if negative
	bmi.s	fmul_round_up                   ; negative: up
	bra.w	fmul_truncate                   ; positive: truncate
soft_fmul_round_plus:
	tst.l	d1                              ; toward +infinity: up if positive
	bmi.w	fmul_truncate                   ; negative: truncate
	bra.s	fmul_round_up                   ; positive: up

;------------------------------------------------------------------------------
; fmul_low_product: part of soft_fmul.  Adds the partial products of the low words, left out
; so far, into the 128-bit product d3:d6:d4:d7, then normalises it by one bit if bit 127 is
; clear.  Called only when the rounding cannot be decided without them.
; In: d1:d2 and d4:d5 the mantissas (words swapped as soft_fmul leaves them), d1 the exponent
; on entry.  Out: d3:d6:d4:d7 the product, d1 the exponent (- 1 if normalised), d0 = 0.
; Changes d0-d7.
;------------------------------------------------------------------------------
fmul_low_product:	; from: soft_fmul, fmul_round_nearest
	move.l	d1,-(sp)                        ; save the exponent
	move.l	d2,d1                           ; high word of the first low long
	swap	d1
	mulu.w	d5,d1                           ; times the low word of the second
	move.l	d5,d7                           ; high word of the second low long
	swap	d7
	mulu.w	d2,d7                           ; times the low word of the first
	moveq	#0,d0                           ; carry catcher
	add.l	d1,d7                           ; sum of the two cross products
	addx.w	d0,d0                           ; its carry
	swap	d0                              ; carry up to bit 16
	swap	d7                              ; high half of the sum into d0,
	move.w	d7,d0
	clr.w	d7                              ; low half to the top of d7
	swap	d2                              ; low words of both low longs
	swap	d5
	move.w	d2,d1
	mulu.w	d5,d1                           ; their product
	moveq	#0,d2                           ; zero for the carries
	add.l	d1,d7                           ; add into the 128-bit product
	addx.l	d0,d4                           ; d3:d6:d4:d7
	addx.l	d2,d6
	addx.l	d2,d3
	moveq	#0,d0                           ; d0 = 0 again
	move.l	(sp)+,d1                        ; restore the exponent
	tst.l	d3                              ; normalised?
	bmi.s	fmul_low_product_done           ; yes
	add.l	d7,d7                           ; no: shift the product left
	addx.l	d4,d4
	addx.l	d6,d6
	addx.l	d3,d3
	subq.w	#1,d1                           ; exponent - 1
fmul_low_product_done:
	rts

;------------------------------------------------------------------------------
; Rest of soft_fmul: rounds the 64-bit mantissa d3:d6 by the bits below it (d4:d7) in the
; mode in fpu_mode, checks the exponent d1 and stores the product at a0 - 6.
;------------------------------------------------------------------------------
fmul_round_nearest:	; from: soft_fmul
	cmpi.l	#$80000000,d7                   ; below the mantissa: above one half?
	bhi.s	fmul_round_up                   ; yes: round up
	cmpi.l	#$7ffe0001,d7                   ; clearly below one half?
	bls.s	fmul_truncate                   ; yes: no rounding
	bsr.s	fmul_low_product                ; near one half: add the low products
	cmpi.l	#$80000000,d4                   ; now above one half?
	bhi.s	fmul_round_up                   ; round up
	bne.s	fmul_truncate                   ; below: no rounding
	tst.l	d7                              ; exactly one half if nothing below
	bne.s	fmul_round_up                   ; more: round up
	btst	#$0,d6                          ; tie: mantissa even?
	beq.s	fmul_truncate                   ; yes: keep it
fmul_round_up:	; from: soft_fmul
	tst.l	d3                              ; normalised?
	bmi.s	fmul_add_one                    ; yes
	add.l	d4,d4                           ; no: shift left one bit
	addx.l	d6,d6
	addx.l	d3,d3
	subq.w	#1,d1                           ; exponent - 1
fmul_add_one:
	addq.l	#1,d6                           ; add one to the mantissa
	addx.l	d0,d3                           ; carry into the high long
	bne.s	fmul_check_exponent             ; no carry out: done
	bset	#$1f,d3                         ; carried out: mantissa 1.0
	addq.w	#1,d1                           ; exponent + 1
	bra.s	fmul_check_exponent
fmul_truncate:	; from: soft_fmul
	tst.l	d3                              ; normalised?
	bmi.s	fmul_check_exponent             ; yes
	add.l	d4,d4                           ; no: shift left one bit
	addx.l	d6,d6
	addx.l	d3,d3
	subq.w	#1,d1                           ; exponent - 1
fmul_check_exponent:
	cmpi.w	#$7fff,d1                       ; exponent in range (unsigned)?
	bcs.s	fmul_store                      ; yes: store
	move.l	d1,d0                           ; out of range: exponent
	move.l	d3,d1                           ; and mantissa for fp_out_of_range
	move.l	d6,d2
	pea	ext_fmul(pc)                    ; tag: ext_fmul
	bsr.w	fp_out_of_range                 ; overflow or underflow result
	bra.s	fmul_done
fmul_store:
	add.l	d1,d1                           ; sign bit 31 into X,
	roxr.w	#1,d1                           ; then into bit 15
	move.l	d6,(a0)                         ; store the low long,
	move.l	d3,-(a0)                        ; the high long
	move.w	d1,-(a0)                        ; and the exponent
fmul_done:	; from: soft_fmul
	movem.l	(sp)+,d3-d7
	rts

;------------------------------------------------------------------------------
; soft_frecip: (a0) = 1.0 / (a0), extended, in software.
; Its address is also the tag soft_fdiv passes to the exception routines.
; Changes d0-d2 and a1 (= the original a0).
;------------------------------------------------------------------------------
soft_frecip:	; from: ext_pow10, soft_fdiv
	lea	(a0),a1                         ; a1 = the divisor x
	lea	fp_two(pc),a0                   ; end of fp_one (fp_two - 10 bytes)
	move.l	-(a0),-(sp)                     ; push 1.0
	move.l	-(a0),-(sp)
	move.w	-(a0),-(sp)
	lea	(sp),a0                         ; a0 = the 1.0 copy
	bsr.s	soft_fdiv                       ; 1.0 / x
	lea	(a1),a0                         ; back to x
	move.w	(sp)+,(a0)+                     ; store the quotient over x
	move.l	(sp)+,(a0)+
	move.l	(sp)+,(a0)
	subq.w	#6,a0                           ; a0 = x again
	rts

;------------------------------------------------------------------------------
; ext_fdiv: (a0) = (a0) / (a1), both extended.  Uses the 68881 when one is present
; (bit 7 of fpu_flags), otherwise soft_fdiv.  Changes d0-d2.
;------------------------------------------------------------------------------
ext_fdiv:	; from: load_and_unpack
	move.w	#$4820,d2                       ; 68881 fdiv, extended source
	btst	#$7,fpu_flags                   ; 68881 present?
	bne.w	fpu_op_ext                      ; yes: divide on it

;------------------------------------------------------------------------------
; soft_fdiv: (a0) = (a0) / (a1) in software.  Zero, infinity and NaN operands go to the
; branches before fdiv_mantissas.  Otherwise the 64-bit mantissas are divided with divu,
; three 16-bit quotient digits with the full divisor, a fourth one with its high long, each
; digit estimated from the high words and corrected down; the remainder then rounds the
; quotient in the mode in fpu_mode.  Changes d0-d2.
;------------------------------------------------------------------------------
soft_fdiv:	; from: cvt_digits, log2p1_fraction, ext_log2p1, fadd_double, fadd_float, fdiv_long, 1 more
	movem.l	d3-d7/a2-a3,-(sp)
	pea	fdiv_mantissas(pc)              ; normal case: fdiv_mantissas
	bra.w	fp_dispatch                     ; load and classify the operands
fdiv_invalid:
	pea	soft_frecip(pc)                 ; tag: soft_frecip
	bsr.w	fp_invalid                      ; result NaN, exception 1
	bra.w	fdiv_done
fdiv_zero:
	eor.l	d3,d0                           ; sign of the result
	andi.l	#$80000000,d0                   ; keep only the sign bit
	clr.l	(a0)                            ; zero mantissa low long
	clr.w	-(a0)                           ; and high word
	move.l	d0,-(a0)                        ; sign, zero exponent and top word
	bra.w	fdiv_done
fdiv_by_zero:
	pea	soft_frecip(pc)                 ; tag: soft_frecip
	bsr.w	fp_div_by_zero                  ; result infinity, exception 2
	bra.w	fdiv_done
fdiv_infinity:
	eor.l	d3,d0                           ; sign of the result
	swap	d0                              ; into bit 15
	or.w	d6,d0                           ; exponent $7fff
	clr.l	(a0)                            ; zero mantissa
	clr.l	-(a0)
	move.w	d0,-(a0)                        ; store the infinity
	bra.w	fdiv_done
	bra.s	fdiv_invalid                    ; NaN operands
	bra.s	fdiv_invalid                    ; NaN operands
	bra.s	fdiv_invalid                    ; NaN operands
	bra.s	fdiv_invalid                    ; infinity / infinity
	bra.s	fdiv_infinity                   ; infinity / zero
	bra.s	fdiv_infinity                   ; infinity / finite
	bra.s	fdiv_zero                       ; zero / infinity
	bra.s	fdiv_invalid                    ; zero / zero
	bra.s	fdiv_zero                       ; zero / finite
	bra.s	fdiv_zero                       ; finite / infinity
	bra.s	fdiv_by_zero                    ; finite / zero
fdiv_mantissas:
	suba.l	a3,a3                           ; a3 = bit shifted out by the halving
	move.l	d0,d7                           ; sign of the result
	eor.l	d3,d7                           ; in the high word of d7
	move.w	d0,d7                           ; exponent difference
	sub.w	d3,d7
	addi.w	#$3ffe,d7                       ; plus the bias - 1
	cmp.l	d1,d4                           ; divisor mantissa above the dividend?
	bhi.s	fdiv_digits                     ; yes: quotient below 1
	bne.s	fdiv_halve                      ; dividend higher: halve
	cmp.l	d2,d5                           ; compare the low longs
	bhi.s	fdiv_digits                     ; divisor higher: no halving
fdiv_halve:
	addq.w	#1,d7                           ; exponent + 1
	lsr.l	#1,d1                           ; halve the dividend
	roxr.l	#1,d2
	bcc.s	fdiv_digits                     ; nothing shifted out
	movea.w	#$8000,a3                       ; keep the bit shifted out
fdiv_digits:
	move.l	d7,-(sp)                        ; save the sign and exponent
	moveq	#2,d6                           ; three 16-bit quotient digits
fdiv_digit_loop:
	movea.l	d6,a2                           ; loop counter
	move.l	d4,d6                           ; high word of the divisor
	swap	d6
	move.l	d1,d7                           ; remainder high long
	divu.w	d6,d7                           ; estimate the digit
	bvc.s	fdiv_digit_ok                   ; fits in 16 bits
	move.l	d4,d7                           ; too large: digit $ffff,
	clr.w	d7
	sub.l	d7,d1                           ; remainder - $ffff * divisor high word
	swap	d7
	add.l	d7,d1
	moveq	#-1,d7                          ; digit $ffff
	bra.s	fdiv_subtract
fdiv_digit_ok:
	move.l	d7,d1                           ; d1 = the divu remainder
	clr.w	d1
	swap	d1
fdiv_subtract:
	move.l	d5,d6                           ; divisor low long high word
	swap	d6
	mulu.w	d7,d6                           ; times the digit
	moveq	#0,d0                           ; carry catcher
	sub.l	d6,d2                           ; subtract from the remainder
	subx.l	d0,d1
	swap	d1                              ; shift the remainder d0:d1:d2
	swap	d2
	move.w	d1,d0                           ; left 16 bits
	move.w	d2,d1
	move.w	a3,d2                           ; bringing in the halved bit
	suba.l	a3,a3                           ; then zeros
	move.w	d4,d3                           ; divisor high long low word
	mulu.w	d7,d3                           ; times the digit
	move.w	d5,d6                           ; divisor low word
	mulu.w	d7,d6                           ; times the digit
	move.w	d7,-(sp)                        ; save the digit
	moveq	#0,d7
	sub.l	d6,d2                           ; subtract both products
	subx.l	d3,d1
	subx.w	d7,d0                           ; from the remainder
	bpl.s	fdiv_next_digit                 ; not negative: digit right
fdiv_correct:
	subq.w	#1,(sp)                         ; digit - 1
	add.l	d5,d2                           ; add the divisor back
	addx.l	d4,d1
	addx.w	d7,d0
	bcc.s	fdiv_correct                    ; until the remainder is positive
fdiv_next_digit:
	move.l	a2,d6                           ; loop counter
	dbra	d6,fdiv_digit_loop              ; next digit
	move.l	d4,d6                           ; fourth digit, for rounding
	swap	d6
	move.l	d1,d7                           ; remainder high long
	divu.w	d6,d7                           ; estimate the digit
	bvc.s	fdiv_last_digit_ok              ; fits in 16 bits
	move.l	d4,d7                           ; too large: digit $ffff,
	clr.w	d7
	sub.l	d7,d1                           ; remainder adjusted
	swap	d7
	add.l	d7,d1
	moveq	#-1,d7                          ; digit $ffff
	swap	d1                              ; remainder to the high word
	bra.s	fdiv_last_subtract
fdiv_last_digit_ok:
	move.l	d7,d1                           ; remainder in the high word
	clr.w	d1
fdiv_last_subtract:
	swap	d2                              ; shift the remainder 16 bits left
	move.w	d1,d0
	move.w	d2,d1
	clr.w	d2
	move.w	d4,d3                           ; divisor high long low word
	mulu.w	d7,d3                           ; times the digit
	moveq	#0,d6                           ; carry catcher
	sub.l	d3,d1                           ; subtract (low long of the divisor
	subx.w	d6,d0                           ; left for fdiv_remainder)
	bpl.s	fdiv_round                      ; not negative: digit right
fdiv_last_correct:
	subq.w	#1,d7                           ; digit - 1
	add.l	d4,d1                           ; add the divisor back
	addx.w	d6,d0
	bcc.s	fdiv_last_correct               ; until positive
fdiv_round:
	swap	d7                              ; d7 = digits 3 and 4
	move.w	(sp)+,d7
	swap	d7
	btst	#$7,fpu_mode                    ; rounding mode: nearest?
	bne.s	fdiv_round_directed             ; no: directed
	move.l	d4,d6                           ; half the divisor high long
	lsr.l	#1,d6
	sub.l	d1,d6                           ; minus the remainder
	bhi.w	fdiv_truncate                   ; clearly below one half: truncate
	swap	d6                              ; not below: how far above?
	addq.w	#1,d6
	bmi.w	fdiv_round_up                   ; clearly above: round up
fdiv_exact_remainder:
	pea	fdiv_round_exact(pc)            ; else decide on the exact remainder
	bra.s	fdiv_remainder                  ; get the exact remainder
fdiv_round_directed:
	cmpi.l	#$ffff,d1                       ; remainder may be zero?
	bls.s	fdiv_exact_remainder            ; yes: get it exactly
fdiv_round_direction:
	btst	#$6,fpu_mode                    ; toward zero?
	beq.s	fdiv_truncate                   ; yes: truncate
	btst	#$5,fpu_mode                    ; toward +infinity?
	bne.s	fdiv_round_plus                 ; yes
	tst.l	4(sp)                           ; toward -infinity: negative?
	bmi.s	fdiv_round_up                   ; yes: round up the magnitude
	bra.s	fdiv_truncate                   ; positive: truncate
fdiv_round_plus:
	tst.l	4(sp)                           ; toward +infinity: negative?
	bmi.s	fdiv_truncate                   ; yes: truncate
	bra.s	fdiv_round_up                   ; positive: round up
fdiv_remainder:
	move.l	d2,-(sp)                        ; save the remainder
	move.l	d1,-(sp)
	move.l	d5,d3                           ; divisor low long high word
	swap	d3
	mulu.w	d7,d3                           ; times the last digit
	move.w	d3,d0                           ; d3:d0 = the 48-bit product
	clr.w	d3
	swap	d3
	swap	d0
	clr.w	d0
	move.w	d5,d2                           ; divisor low word
	mulu.w	d7,d2                           ; times the last digit
	moveq	#0,d1
	add.l	d2,d0                           ; added in
	addx.l	d1,d3
	move.l	(sp)+,d1                        ; restore the remainder
	move.l	(sp)+,d2
	sub.l	d0,d2                           ; subtract the product
	subx.l	d3,d1
	bcc.s	fdiv_remainder_done             ; not negative: done
	subq.w	#1,d7                           ; digit - 1
	add.l	d5,d2                           ; add the divisor back
	addx.l	d4,d1
fdiv_remainder_done:
	rts
fdiv_round_exact:
	btst	#$7,fpu_mode                    ; round to nearest?
	bne.s	fdiv_remainder_test             ; no: directed, test the remainder
	lsr.l	#1,d4                           ; half the divisor
	roxr.l	#1,d5
	sub.l	d2,d5                           ; minus the remainder
	subx.l	d1,d4
	bmi.s	fdiv_round_up                   ; negative: above one half, round up
	bne.s	fdiv_truncate                   ; positive: below, truncate
	btst	#$0,d7                          ; tie: quotient even?
	beq.s	fdiv_truncate                   ; yes: truncate
	bra.s	fdiv_round_up                   ; odd: round up
fdiv_remainder_test:
	tst.l	d1                              ; any remainder?
	bne.s	fdiv_round_direction            ; yes: round by direction
	tst.l	d2                              ; low long
	beq.s	fdiv_truncate                   ; exact: truncate
	bra.s	fdiv_round_direction            ; round by direction
fdiv_round_up:
	move.l	(sp)+,d6                        ; digits 1 and 2
	swap	d6                              ; in order
	addq.l	#1,d7                           ; add one to the quotient
	bcc.s	fdiv_check_exponent             ; no carry
	addq.l	#1,d6                           ; carry into the high long
	bra.s	fdiv_check_exponent
fdiv_truncate:
	move.l	(sp)+,d6                        ; digits 1 and 2
	swap	d6                              ; in order
fdiv_check_exponent:
	move.l	(sp)+,d0                        ; sign and exponent
	cmpi.w	#$7ffe,d0                       ; exponent in range (unsigned)?
	bls.s	fdiv_store                      ; yes: store
	move.l	d6,d1                           ; mantissa for fp_out_of_range
	move.l	d7,d2
	pea	soft_frecip(pc)                 ; tag: soft_frecip
	bsr.w	fp_out_of_range                 ; overflow or underflow result
	bra.s	fdiv_done
fdiv_store:
	add.l	d0,d0                           ; sign bit 31 into X,
	roxr.w	#1,d0                           ; then into bit 15
	move.l	d7,(a0)                         ; store the low long,
	move.l	d6,-(a0)                        ; the high long
	move.w	d0,-(a0)                        ; and the exponent
fdiv_done:
	movem.l	(sp)+,d3-d7/a2-a3
	rts

;------------------------------------------------------------------------------
; ext_fmod: (a0) = fmod((a0), (a1)), extended: the remainder with the quotient truncated,
; with the sign of (a0).  Uses the 68881 when present, else falls into soft_fmod.
; Changes d0-d2.
;------------------------------------------------------------------------------
ext_fmod:	; from: soft_frem
	move.w	#$4821,d2                       ; 68881 fmod, extended source
	btst	#$7,fpu_flags                   ; 68881 present?
	bne.w	fpu_op_ext                      ; yes: on it

;------------------------------------------------------------------------------
; soft_fmod: fmod in software; d7 = 0 selects the truncated quotient.
;------------------------------------------------------------------------------
soft_fmod:
	movem.l	d3-d7,-(sp)
	moveq	#0,d7                           ; d7 = 0: truncated quotient
	pea	fmod_mantissas(pc)              ; normal case: fmod_mantissas
	bra.w	fp_dispatch                     ; load and classify the operands

;------------------------------------------------------------------------------
; ext_frem: (a0) = IEEE remainder of (a0) / (a1), the quotient rounded to nearest (even on
; a tie).  Uses the 68881 when present, otherwise soft_frem.  Changes d0-d2.
;------------------------------------------------------------------------------
ext_frem:
	move.w	#$4825,d2                       ; 68881 frem, extended source
	btst	#$7,fpu_flags                   ; 68881 present?
	bne.w	fpu_op_ext                      ; yes: on it

;------------------------------------------------------------------------------
; soft_frem: IEEE remainder in software; d7 = -1 selects the rounded quotient.
;------------------------------------------------------------------------------
soft_frem:	; from: fadd_double, fadd_float, fdiv_long
	movem.l	d3-d7,-(sp)
	moveq	#-1,d7                          ; d7 = -1: quotient rounded to nearest
	pea	fmod_mantissas(pc)              ; normal case: fmod_mantissas
	bra.w	fp_dispatch                     ; load and classify the operands
fmod_invalid:
	pea	ext_fmod(pc)                    ; tag: ext_fmod
	bsr.w	fp_invalid                      ; result NaN, exception 1
	bra.w	fmod_done
fmod_first:
	bra.w	fmod_denormalise                ; store the first operand
	bra.s	fmod_invalid                    ; NaN operands
	bra.s	fmod_invalid                    ; NaN operands
	bra.s	fmod_invalid                    ; NaN operands
	bra.s	fmod_invalid                    ; infinity mod infinity
	bra.s	fmod_invalid                    ; infinity mod zero
	bra.s	fmod_invalid                    ; infinity mod finite
	bra.s	fmod_first                      ; zero mod infinity
	bra.s	fmod_invalid                    ; zero mod zero
	bra.s	fmod_first                      ; zero mod finite
	bra.s	fmod_first                      ; finite mod infinity
	bra.s	fmod_invalid                    ; finite mod zero

;------------------------------------------------------------------------------
; fmod_mantissas: the remainder, for soft_fmod (d7 = 0) and soft_frem (d7 = -1).
; Shift-and-subtract over the exponent difference, reducing the remainder only when the
; shift carries out of 64 bits, then subtracting until it is below the divisor.  d6 flips
; with each subtraction, its sign giving the parity of the quotient for soft_frem.
; For soft_frem a remainder above half the divisor becomes divisor - remainder, sign
; flipped.  The result is normalised (or denormalised below the range) and stored.
;------------------------------------------------------------------------------
fmod_mantissas:	; from: soft_fmod, soft_frem
	moveq	#-1,d6                          ; d6 = quotient parity
	sub.w	d0,d3                           ; divisor exponent - dividend
	beq.s	fmod_final_subtract             ; equal: subtract directly
	blt.s	fmod_reduce                     ; dividend larger: reduce
	cmpi.w	#$1,d3                          ; divisor larger by exactly one?
	bne.s	fmod_normalise                  ; no: result = dividend
	tst.w	d7                              ; fmod?
	beq.s	fmod_normalise                  ; yes: result = dividend
	sub.l	d2,d5                           ; divisor mantissa - dividend
	subx.l	d1,d4
	bcc.s	fmod_normalise                  ; dividend at most half: keep it
	add.l	d5,d5                           ; twice the (negative) difference
	addx.l	d4,d4
	add.l	d5,d2                           ; dividend + 2 (divisor - dividend)
	addx.l	d4,d1
	bchg	#$1f,d0                         ; = divisor - dividend, sign flipped
	bra.s	fmod_normalise                  ; normalise and store
fmod_reduce:
	neg.w	d3                              ; exponent difference
	sub.w	d3,d0                           ; result exponent = the divisor's
	subq.w	#2,d3                           ; shifts before the last one
	bcs.s	fmod_last_shift                 ; none
fmod_reduce_loop:
	add.l	d2,d2                           ; remainder * 2
	addx.l	d1,d1
	bcc.s	fmod_reduce_next                ; below 2^64: no reduction
	sub.l	d5,d2                           ; carried out: subtract the divisor
	subx.l	d4,d1
	bcs.s	fmod_reduce_next                ; borrow cancels the carry: done
	sub.l	d5,d2                           ; still above: subtract again
	subx.l	d4,d1
fmod_reduce_next:
	dbra	d3,fmod_reduce_loop             ; next exponent step
fmod_last_shift:
	add.l	d2,d2                           ; last shift
	addx.l	d1,d1
	bcc.s	fmod_final_subtract             ; no carry: final subtraction
fmod_carry_subtract:
	neg.w	d6                              ; count the subtraction
	sub.l	d5,d2                           ; subtract the divisor
	subx.l	d4,d1
	bcc.s	fmod_carry_subtract             ; until it borrows
fmod_final_subtract:
	neg.w	d6                              ; count the subtraction
	sub.l	d5,d2                           ; subtract the divisor
	subx.l	d4,d1
	beq.s	fmod_zero                       ; exactly zero
	bcc.s	fmod_final_subtract             ; until it borrows
	add.l	d2,d5                           ; d4:d5 = remainder (add back)
	addx.l	d1,d4
	add.l	d5,d2                           ; d1:d2 = 2 remainder - divisor
	addx.l	d4,d1
	bne.s	fmod_compare_half               ; not exactly half
	tst.w	d6                              ; tie: quotient even?
	bpl.s	fmod_use_remainder              ; yes: keep the remainder
	bra.s	fmod_use_complement             ; odd: take the complement
fmod_zero:
	clr.w	d0                              ; zero result
	bra.s	fmod_store
fmod_compare_half:
	bcs.s	fmod_use_complement             ; above half: complement for frem
fmod_use_remainder:
	move.l	d5,d2                           ; result = remainder
	move.l	d4,d1
	bra.s	fmod_normalise                  ; normalise and store
fmod_use_complement:
	tst.w	d7                              ; fmod?
	beq.s	fmod_use_remainder              ; yes: plain remainder
	sub.l	d2,d5                           ; divisor - remainder
	subx.l	d1,d4
	move.l	d5,d2                           ; is the result
	move.l	d4,d1
	bchg	#$1f,d0                         ; with the sign flipped
fmod_normalise:
	tst.l	d1                              ; normalised?
	bmi.s	fmod_denormalise                ; yes
fmod_normalise_loop:
	subq.w	#1,d0                           ; exponent - 1
	add.l	d2,d2                           ; shift left
	addx.l	d1,d1
	bpl.s	fmod_normalise_loop             ; until bit 63 is set
fmod_denormalise:	; from: soft_frem
	tst.w	d0                              ; exponent below 0?
	bpl.s	fmod_store                      ; no: store
fmod_denormalise_loop:
	lsr.l	#1,d1                           ; shift right
	roxr.l	#1,d2
	addq.w	#1,d0                           ; exponent + 1
	bmi.s	fmod_denormalise_loop           ; until exponent 0: a denormal
fmod_store:
	add.l	d0,d0                           ; sign bit 31 into X,
	roxr.w	#1,d0                           ; then into bit 15
	move.l	d2,(a0)                         ; store the low long,
	move.l	d1,-(a0)                        ; the high long
	move.w	d0,-(a0)                        ; and the exponent
fmod_done:	; from: soft_frem
	movem.l	(sp)+,d3-d7
	rts
fpu_op_ext_abort:	; from: fpu_op_ext
	move.w	#$3,-$e(a2)                     ; control: abort, acknowledge exception
	movea.l	d1,a2                           ; restore a2, start again

;------------------------------------------------------------------------------
; fpu_op_ext: (a0) = (a0) <op> (a1) on the 68881 (SFP004 at $fffffa40), both extended.
; d2 = the 68881 command word for the operation with an extended source.
; Loads (a0) into fp0, runs the command with (a1), stores fp0 back to (a0).  Each
; handshake polls the response register; 128 polls in all.  If the result is not offered,
; the 68881 is reset with an abort and the operation starts again.
; Registers: $fa40 response, $fa42 control, $fa4a command, $fa50 operand.  Changes d0-d1.
;------------------------------------------------------------------------------
fpu_op_ext:	; from: square, ext_fsub, ext_fmul, ext_fdiv, ext_fmod, ext_frem
	moveq	#127,d0                         ; up to 128 polls in all
	move.l	a2,d1                           ; save a2
	lea	$fffffa50.w,a2                  ; a2 = the operand register
fpu_op_ext_wait_load_cmd:
	cmpi.w	#$802,-$10(a2)                  ; response: idle?
	dbeq	d0,fpu_op_ext_wait_load_cmd     ; wait
	move.w	#$4800,-$6(a2)                  ; command: fmove.x <ea>,fp0
fpu_op_ext_wait_load_data:
	cmpi.w	#$960c,-$10(a2)                 ; response: send 12 bytes?
	dbeq	d0,fpu_op_ext_wait_load_data    ; wait
	move.l	(a0),(a2)                       ; write the first operand
	move.l	2(a0),(a2)
	move.l	6(a0),(a2)
fpu_op_ext_wait_op_cmd:
	cmpi.w	#$802,-$10(a2)                  ; response: idle?
	dbeq	d0,fpu_op_ext_wait_op_cmd       ; wait
	move.w	d2,-$6(a2)                      ; command: the operation, <ea> to fp0
fpu_op_ext_wait_op_data:
	cmpi.w	#$960c,-$10(a2)                 ; response: send 12 bytes?
	dbeq	d0,fpu_op_ext_wait_op_data      ; wait
	move.l	(a1),(a2)                       ; write the second operand
	move.l	2(a1),(a2)
	move.l	6(a1),(a2)
fpu_op_ext_wait_store_cmd:
	cmpi.w	#$802,-$10(a2)                  ; response: idle?
	dbeq	d0,fpu_op_ext_wait_store_cmd    ; wait
	move.w	#$6800,-$6(a2)                  ; command: fmove.x fp0,<ea>
fpu_op_ext_wait_result:
	cmpi.w	#$b20c,-$10(a2)                 ; response: take 12 bytes?
	dbeq	d0,fpu_op_ext_wait_result       ; wait
	bne.s	fpu_op_ext_abort                ; not offered: abort and start again
	move.l	(a2),(a0)                       ; read the result into (a0)
	move.l	(a2),2(a0)
	move.l	(a2),6(a0)
	movea.l	d1,a2                           ; restore a2
	rts
fpu_op_double_abort:	; from: fpu_op_double
	move.w	#$3,-$e(a2)                     ; control: abort, acknowledge exception
	movea.l	d1,a2                           ; restore a2, start again

;------------------------------------------------------------------------------
; fpu_op_double: (a0) = (a0) <op> (a1) on the 68881, (a1) a double (8 bytes).
; d2 = the command word with a double source.  Same handshakes as fpu_op_ext.
; Changes d0-d1.
;------------------------------------------------------------------------------
fpu_op_double:	; from: fadd_double
	moveq	#127,d0                         ; up to 128 polls in all
	move.l	a2,d1                           ; save a2
	lea	$fffffa50.w,a2                  ; a2 = the operand register
fpu_op_double_wait_load_cmd:
	cmpi.w	#$802,-$10(a2)                  ; response: idle?
	dbeq	d0,fpu_op_double_wait_load_cmd  ; wait
	move.w	#$4800,-$6(a2)                  ; command: fmove.x <ea>,fp0
fpu_op_double_wait_load_data:
	cmpi.w	#$960c,-$10(a2)                 ; response: send 12 bytes?
	dbeq	d0,fpu_op_double_wait_load_data ; wait
	move.l	(a0),(a2)                       ; write the first operand
	move.l	2(a0),(a2)
	move.l	6(a0),(a2)
fpu_op_double_wait_op_cmd:
	cmpi.w	#$802,-$10(a2)                  ; response: idle?
	dbeq	d0,fpu_op_double_wait_op_cmd    ; wait
	move.w	d2,-$6(a2)                      ; command: the operation, double <ea>
fpu_op_double_wait_op_data:
	cmpi.w	#$9608,-$10(a2)                 ; response: send 8 bytes?
	dbeq	d0,fpu_op_double_wait_op_data   ; wait
	move.l	(a1),(a2)                       ; write the double
	move.l	4(a1),(a2)
fpu_op_double_wait_store_cmd:
	cmpi.w	#$802,-$10(a2)                  ; response: idle?
	dbeq	d0,fpu_op_double_wait_store_cmd ; wait
	move.w	#$6800,-$6(a2)                  ; command: fmove.x fp0,<ea>
fpu_op_double_wait_result:
	cmpi.w	#$b20c,-$10(a2)                 ; response: take 12 bytes?
	dbeq	d0,fpu_op_double_wait_result    ; wait
	bne.s	fpu_op_double_abort             ; not offered: abort and start again
	move.l	(a2),(a0)                       ; read the result into (a0)
	move.l	(a2),2(a0)
	move.l	(a2),6(a0)
	movea.l	d1,a2                           ; restore a2
	rts
fpu_op_d0_abort:	; from: fpu_op_d0
	move.w	#$3,-$e(a1)                     ; control: abort, acknowledge exception

;------------------------------------------------------------------------------
; fpu_op_d0: (a0) = (a0) <op> d0 on the 68881, d0 a long or a float as the command word
; in d2 says.  Same handshakes as fpu_op_ext.  Changes d1 and a1.
;------------------------------------------------------------------------------
fpu_op_d0:	; from: fadd_float, fadd_int, fdiv_long
	moveq	#127,d1                         ; up to 128 polls in all
	lea	$fffffa50.w,a1                  ; a1 = the operand register
fpu_op_d0_wait_load_cmd:
	cmpi.w	#$802,-$10(a1)                  ; response: idle?
	dbeq	d1,fpu_op_d0_wait_load_cmd      ; wait
	move.w	#$4800,-$6(a1)                  ; command: fmove.x <ea>,fp0
fpu_op_d0_wait_load_data:
	cmpi.w	#$960c,-$10(a1)                 ; response: send 12 bytes?
	dbeq	d1,fpu_op_d0_wait_load_data     ; wait
	move.l	(a0),(a1)                       ; write the first operand
	move.l	2(a0),(a1)
	move.l	6(a0),(a1)
fpu_op_d0_wait_op_cmd:
	cmpi.w	#$802,-$10(a1)                  ; response: idle?
	dbeq	d1,fpu_op_d0_wait_op_cmd        ; wait
	move.w	d2,-$6(a1)                      ; command: the operation, long/single
fpu_op_d0_wait_op_data:
	cmpi.w	#$9504,-$10(a1)                 ; response: send 4 bytes?
	dbeq	d1,fpu_op_d0_wait_op_data       ; wait
	move.l	d0,(a1)                         ; write d0
fpu_op_d0_wait_store_cmd:
	cmpi.w	#$802,-$10(a1)                  ; response: idle?
	dbeq	d1,fpu_op_d0_wait_store_cmd     ; wait
	move.w	#$6800,-$6(a1)                  ; command: fmove.x fp0,<ea>
fpu_op_d0_wait_result:
	cmpi.w	#$b20c,-$10(a1)                 ; response: take 12 bytes?
	dbeq	d1,fpu_op_d0_wait_result        ; wait
	bne.s	fpu_op_d0_abort                 ; not offered: abort and start again
	move.l	(a1),(a0)                       ; read the result into (a0)
	move.l	(a1),2(a0)
	move.l	(a1),6(a0)
	rts
fpu_op_unary_abort:	; from: fpu_op_unary
	move.w	#$3,-$e(a2)                     ; control: abort, acknowledge exception
	movea.l	d1,a2                           ; restore a2, start again

;------------------------------------------------------------------------------
; fpu_op_unary: (a1) = <op>((a0)) on the 68881, extended.  d2 = the command word, which
; loads (a0) and applies the operation in one step.  Changes d0-d1.
;------------------------------------------------------------------------------
fpu_op_unary:	; from: ext_log2, log, ext_log10, log1p
	moveq	#127,d0                         ; up to 128 polls in all
	move.l	a2,d1                           ; save a2
	lea	$fffffa50.w,a2                  ; a2 = the operand register
fpu_op_unary_wait_op_cmd:
	cmpi.w	#$802,-$10(a2)                  ; response: idle?
	dbeq	d0,fpu_op_unary_wait_op_cmd     ; wait
	move.w	d2,-$6(a2)                      ; command: the operation, (a0) to fp0
fpu_op_unary_wait_op_data:
	cmpi.w	#$960c,-$10(a2)                 ; response: send 12 bytes?
	dbeq	d0,fpu_op_unary_wait_op_data    ; wait
	move.l	(a0),(a2)                       ; write the operand
	move.l	2(a0),(a2)
	move.l	6(a0),(a2)
fpu_op_unary_wait_store_cmd:
	cmpi.w	#$802,-$10(a2)                  ; response: idle?
	dbeq	d0,fpu_op_unary_wait_store_cmd  ; wait
	move.w	#$6800,-$6(a2)                  ; command: fmove.x fp0,<ea>
fpu_op_unary_wait_result:
	cmpi.w	#$b20c,-$10(a2)                 ; response: take 12 bytes?
	dbeq	d0,fpu_op_unary_wait_result     ; wait
	bne.s	fpu_op_unary_abort              ; not offered: abort and start again
	move.l	(a2),(a1)                       ; read the result into (a1)
	move.l	(a2),2(a1)
	move.l	(a2),6(a1)
	movea.l	d1,a2                           ; restore a2
	rts

;------------------------------------------------------------------------------
; fp_classify: unpacks the extended at (a0) into d0 (sign and exponent), d1:d2 (mantissa).
; Returns N set for a finite non-zero value (a denormal normalised, then shifted back to
; exponent 0), Z for zero, V for an infinity (C set if negative), all clear for a NaN
; (made quiet: bit 30 of d1 set).  Changes d0-d2.
;------------------------------------------------------------------------------
fp_classify:	; from: cvt_digits, log2p1_fraction, soft_log2, ext_log2p1, fp_to_long
	move.l	6(a0),d2                        ; mantissa low long
	move.w	(a0),d0                         ; sign and exponent
	moveq	#1,d1                           ; exponent + 1,
	add.w	d0,d1
	add.w	d1,d1                           ; shifted out of the sign: zero
	beq.s	fp_classify_inf_nan             ; when the exponent is $7fff
	move.l	2(a0),d1                        ; mantissa high long
	bpl.s	fp_classify_check_zero          ; integer bit clear: not normal
	rts                                     ; normalised: N set
fp_classify_check_zero:
	bne.s	fp_classify_denormal            ; mantissa not zero: denormal
	tst.l	d2                              ; low long
	bne.s	fp_classify_denormal            ; not zero: denormal
	andi.w	#$8000,d0                       ; zero: keep the sign
	move.w	#$4,ccr                         ; Z
	rts
fp_classify_denormal:
	ext.l	d0                              ; sign in the high word
	andi.w	#$7fff,d0                       ; exponent alone
	bsr.w	fp_normalize                    ; normalise the mantissa
	tst.w	d0                              ; exponent still >= 0?
	bpl.s	fp_classify_finite              ; yes: finite
fp_classify_shift_back:
	lsr.l	#1,d1                           ; shift right again
	roxr.l	#1,d2
	addq.w	#1,d0                           ; up to exponent 0
	bne.s	fp_classify_shift_back
fp_classify_finite:
	add.l	d0,d0                           ; sign bit 31 into X,
	roxr.w	#1,d0                           ; then into bit 15
	move.w	#$8,ccr                         ; N: finite
	rts
fp_classify_inf_nan:
	move.l	2(a0),d1                        ; mantissa high long
	bne.s	fp_classify_nan                 ; not zero: NaN
	tst.l	d2                              ; low long
	bne.s	fp_classify_nan                 ; not zero: NaN
	tst.w	d0                              ; infinity: negative?
	bmi.s	fp_classify_minus_inf
	move.w	#$2,ccr                         ; V: +infinity
	rts
fp_classify_minus_inf:
	move.w	#$3,ccr                         ; V and C: -infinity
	rts
fp_classify_nan:
	bset	#$1e,d1                         ; make the NaN quiet
	move.w	#$0,ccr                         ; flags clear: NaN
	rts

;------------------------------------------------------------------------------
; fp_store: stores d0/d1:d2 as an extended at (a1).  Used to return an argument unchanged.
;------------------------------------------------------------------------------
fp_store:	; from: log2p1_fraction, soft_log2
	move.w	d0,(a1)+                        ; exponent
	move.l	d1,(a1)+                        ; mantissa high long
	move.l	d2,(a1)                         ; and low long
	subq.w	#6,a1                           ; a1 back to the start
	rts

;------------------------------------------------------------------------------
; fp_minus_inf: (a1) = -infinity.  Changes d1.
;------------------------------------------------------------------------------
fp_minus_inf:	; from: fp_range_minus_inf
	moveq	#0,d1                           ; mantissa zero
	move.w	#$ffff,(a1)+                    ; exponent with the sign set
	bra.s	fp_store_mantissa

;------------------------------------------------------------------------------
; fp_plus_inf: (a1) = +infinity.  Changes d1.
;------------------------------------------------------------------------------
fp_plus_inf:	; from: fp_range_plus_inf
	moveq	#0,d1                           ; mantissa zero
	bra.s	fp_store_max_exponent

;------------------------------------------------------------------------------
; fp_nan: (a1) = NaN (all mantissa bits set).  Changes d1.
;------------------------------------------------------------------------------
fp_nan:	; from: fp_domain_nan
	moveq	#-1,d1                          ; mantissa all ones
fp_store_max_exponent:	; from: fp_plus_inf
	move.w	#$7fff,(a1)+                    ; exponent $7fff
fp_store_mantissa:	; from: fp_minus_inf
	move.l	d1,(a1)+                        ; mantissa high long
	move.l	d1,(a1)                         ; and low long
	subq.w	#6,a1                           ; a1 back to the start
	rts

;------------------------------------------------------------------------------
; fp_range_minus_inf: (a1) = -infinity and raises exception 3 (range).
; The caller pushes a tag (its name string) before the call; it is removed on return.
; Changes d0-d1.
;------------------------------------------------------------------------------
fp_range_minus_inf:	; from: soft_log2
	bsr.s	fp_minus_inf                    ; -infinity
	moveq	#3,d0                           ; exception 3
	bra.s	fp_raise_tagged

;------------------------------------------------------------------------------
; fp_range_plus_inf: (a1) = +infinity and raises exception 3 (range).
;------------------------------------------------------------------------------
fp_range_plus_inf:
	bsr.s	fp_plus_inf                     ; +infinity
	moveq	#3,d0                           ; exception 3
	bra.s	fp_raise_tagged

;------------------------------------------------------------------------------
; fp_domain_nan: (a1) = NaN and raises exception 1 (domain / invalid).
;------------------------------------------------------------------------------
fp_domain_nan:	; from: soft_log2
	bsr.s	fp_nan                          ; NaN
	moveq	#1,d0                           ; exception 1
fp_raise_tagged:	; from: fp_range_minus_inf, fp_range_plus_inf
	pea	(a1)                            ; result pointer
	move.l	8(sp),-(sp)                     ; the caller's tag
	bsr.w	fp_raise                        ; raise the exception
	addq.l	#8,sp                           ; pop both
	move.l	(sp)+,(sp)                      ; drop the tag
	rts

;------------------------------------------------------------------------------
; fp_dispatch_neg: as fp_dispatch with the sign of the second operand flipped (subtract).
;------------------------------------------------------------------------------
fp_dispatch_neg:	; from: ext_fsub
	move.w	(a1),d3                         ; second operand exponent
	bchg	#$f,d3                          ; with the sign flipped
	bra.s	fp_dispatch_second

;------------------------------------------------------------------------------
; fp_dispatch: loads the operands of a binary operation.  (a1) goes to d3 (sign and
; exponent), d4:d5, (a0) to d0, d1:d2, a0 left at the operand + 6.  Denormals are
; normalised.  d6 = $7fff.  Entered with the address of the normal-case code on the stack;
; for zero, infinity and NaN operands it steps that address back into the branch table
; before it: second zero -2, second infinity -4, first zero -6, first infinity -12,
; NaN -18 (the second operand's step added to the first's).
;------------------------------------------------------------------------------
fp_dispatch:	; from: soft_fcmp, soft_fadd, soft_fmul, soft_fdiv, soft_fmod, soft_frem
	move.w	(a1),d3                         ; second operand exponent
fp_dispatch_second:	; from: fp_dispatch_neg
	move.l	6(a1),d5                        ; its mantissa low long
	move.w	#$7fff,d6                       ; exponent mask
	ext.l	d3                              ; sign into the high word
	and.w	d6,d3                           ; exponent alone
	cmp.w	d6,d3                           ; infinity or NaN?
	beq.s	fp_dispatch_second_inf_nan
	move.l	2(a1),d4                        ; mantissa high long
	bmi.s	fp_dispatch_first               ; normalised
	bne.s	fp_dispatch_normalise_second    ; not zero: denormal
	tst.l	d5                              ; low long
	bne.s	fp_dispatch_normalise_second    ; not zero: denormal
	subq.l	#2,(sp)                         ; second zero: step -2
	bra.s	fp_dispatch_first
fp_dispatch_normalise_second:
	subq.w	#1,d3                           ; exponent - 1
	add.l	d5,d5                           ; shift the mantissa left
	addx.l	d4,d4
	bpl.s	fp_dispatch_normalise_second    ; until bit 63 is set
fp_dispatch_first:
	move.w	(a0)+,d0                        ; first operand exponent
	move.l	(a0)+,d1                        ; mantissa high long
	move.l	(a0),d2                         ; and low long
	ext.l	d0                              ; sign into the high word
	and.w	d6,d0                           ; exponent alone
	cmp.w	d6,d0                           ; infinity or NaN?
	beq.s	fp_dispatch_first_inf_nan
	tst.l	d1                              ; integer bit set?
	bpl.s	fp_dispatch_check_first_zero    ; no: zero or denormal
	rts                                     ; normal: return to the case code
fp_dispatch_check_first_zero:
	bne.s	fp_normalize_loop               ; not zero: normalise and return
	tst.l	d2                              ; low long
	bne.s	fp_normalize_loop               ; not zero: normalise and return
	subq.l	#6,(sp)                         ; first zero: step -6
	rts
fp_dispatch_second_inf_nan:
	move.l	2(a1),d4                        ; mantissa high long
	bne.s	fp_dispatch_skip_first          ; not zero: NaN
	tst.l	d5                              ; low long
	bne.s	fp_dispatch_skip_first          ; not zero: NaN
	subq.l	#4,(sp)                         ; second infinity: step -4
	bra.s	fp_dispatch_first               ; now the first operand
fp_dispatch_first_inf_nan:
	tst.l	d1                              ; mantissa high long
	bne.s	fp_dispatch_nan                 ; not zero: NaN
	tst.l	d2                              ; low long
	bne.s	fp_dispatch_nan                 ; not zero: NaN
	subi.l	#$c,(sp)                        ; first infinity: step -12
	rts
fp_dispatch_skip_first:
	addq.w	#6,a0                           ; a0 past the first operand
fp_dispatch_nan:
	subi.l	#$12,(sp)                       ; NaN: step -18
	rts

;------------------------------------------------------------------------------
; fp_normalize: shifts d1:d2 left until bit 31 of d1 is set, decrementing d0 each time.
;------------------------------------------------------------------------------
fp_normalize:	; from: log2p1_fraction, soft_square, fp_classify
	tst.l	d1                              ; already normalised?
	bmi.s	fp_normalize_done
fp_normalize_loop:	; from: fp_dispatch
	subq.w	#1,d0                           ; exponent - 1
	add.l	d2,d2                           ; shift the mantissa left
	addx.l	d1,d1
	bpl.s	fp_normalize_loop               ; until bit 63 is set
fp_normalize_done:
	rts

;------------------------------------------------------------------------------
; fp_invalid: result NaN, raises exception 1 (invalid operation).
; Entered with the tag of the operation on the stack; a0 = operand + 6.
;------------------------------------------------------------------------------
fp_invalid:	; from: soft_fadd, soft_fmul, soft_fdiv, soft_frem
	move.w	#$7fff,d0                       ; exponent $7fff
	moveq	#-1,d1                          ; mantissa all ones: NaN
	moveq	#-1,d2
	moveq	#1,d3                           ; exception 1: invalid
	bra.w	fp_raise_result

;------------------------------------------------------------------------------
; fp_div_by_zero: result infinity with the sign of the operands (d0 eor d3), raises
; exception 2 (division by zero).  Tag on the stack, a0 = operand + 6.
;------------------------------------------------------------------------------
fp_div_by_zero:	; from: soft_fdiv
	eor.l	d3,d0                           ; sign of the result
	swap	d0                              ; into the low word
	or.w	d6,d0                           ; exponent $7fff
	moveq	#0,d1                           ; mantissa zero: infinity
	moveq	#0,d2
	moveq	#2,d3                           ; exception 2: division by zero
	bra.w	fp_raise_result

;------------------------------------------------------------------------------
; fp_out_of_range: the exponent in d0 is too large or below the denormal range; d1:d2 is
; the mantissa, the tag is on the stack, a0 = operand + 6.
; Overflow: infinity (exception 3), or the largest finite value when the rounding mode
; goes toward zero for this sign.  Underflow: denormalises the mantissa and rounds it;
; too small for that gives zero (exception 4), or the smallest denormal when rounding
; away from zero.  The result is stored at a0 - 6 and the tag is dropped.
; Rounding mode, bits 7-5 of fpu_mode: 0xx nearest, 100 toward zero, 110 toward
; -infinity, 111 toward +infinity.  Changes d0-d4.
;------------------------------------------------------------------------------
fp_out_of_range:	; from: soft_square, soft_fmul, fmul_round_nearest, soft_fdiv
	move.w	#$7fff,d6                       ; exponent mask
	move.w	-$6(a0),d3                      ; first operand exponent
	and.w	d6,d3
	beq.s	fp_underflow                    ; zero: underflow
	cmpi.w	#$7000,d3                       ; large first operand: overflow
	bgt.s	fp_overflow
	cmpi.w	#$b000,d0                       ; negative exponent ($b000 up)?
	bhi.s	fp_underflow                    ; yes: underflow
fp_overflow:	; from: soft_fadd
	swap	d0                              ; sign into the low word
	ori.w	#$7fff,d0                       ; exponent $7fff
	btst	#$7,fpu_mode                    ; round to nearest?
	beq.s	fp_overflow_infinity            ; yes: infinity
	btst	#$6,fpu_mode                    ; toward zero?
	beq.s	fp_overflow_largest             ; yes: the largest value
	move.w	fpu_flags(pc),d3                ; mode word: bit 5 of fpu_mode
	ror.w	#6,d3                           ; to bit 15
	eor.w	d0,d3                           ; toward the infinity of this sign?
	bmi.s	fp_overflow_infinity            ; yes: infinity
fp_overflow_largest:
	subq.w	#1,d0                           ; exponent $7ffe
	moveq	#-1,d1                          ; mantissa all ones: largest
	moveq	#-1,d2
	bra.w	fp_out_of_range_store           ; store, no exception
fp_overflow_infinity:
	moveq	#0,d1                           ; mantissa zero: infinity
	moveq	#0,d2
	moveq	#3,d3                           ; exception 3: overflow
	bra.w	fp_raise_result
fp_underflow:	; from: soft_fadd
	cmpi.w	#$ff80,d0                       ; within 128 bits of exponent 0?
	bgt.s	fp_denormalise                  ; yes: denormalise
	swap	d0                              ; sign into the low word
	andi.w	#$8000,d0                       ; keep only the sign
	moveq	#0,d1                           ; zero mantissa
	moveq	#0,d2
	moveq	#4,d3                           ; exception 4: underflow
	btst	#$7,fpu_mode                    ; round to nearest?
	beq.s	fp_raise_result                 ; yes: zero
	btst	#$6,fpu_mode                    ; toward zero?
	beq.s	fp_raise_result                 ; yes: zero
	move.w	fpu_flags(pc),d4                ; mode word: bit 5 of fpu_mode
	ror.w	#6,d4                           ; to bit 15
	eor.w	d0,d4                           ; away from zero for this sign?
	bpl.s	fp_raise_result                 ; no: zero
	moveq	#1,d2                           ; yes: the smallest denormal
	bra.s	fp_out_of_range_store           ; store, no exception
fp_denormalise:
	moveq	#0,d3                           ; bits shifted out: d3:d4
	moveq	#0,d4
fp_denormalise_loop:
	lsr.l	#1,d1                           ; shift the mantissa right
	roxr.l	#1,d2
	roxr.l	#1,d3                           ; into d3:d4
	roxr.l	#1,d4
	addq.w	#1,d0                           ; exponent + 1
	bne.s	fp_denormalise_loop             ; until exponent 0
	add.l	d0,d0                           ; sign bit 31 into X,
	roxr.w	#1,d0                           ; then into bit 15
	btst	#$7,fpu_mode                    ; round to nearest?
	bne.s	fp_denormalise_directed         ; no: directed
	bclr	#$1f,d3                         ; top bit shifted out: one half
	beq.s	fp_out_of_range_store           ; clear: truncate
	bra.s	fp_denormalise_round_up         ; set: round up if more below
fp_denormalise_directed:
	btst	#$6,fpu_mode                    ; toward zero?
	beq.s	fp_out_of_range_store           ; yes: truncate
	or.l	d4,d3                           ; all the bits shifted out
	btst	#$5,fpu_mode                    ; toward +infinity?
	beq.s	fp_denormalise_toward_minus     ; no: toward -infinity
	tst.w	d0                              ; negative?
	bmi.s	fp_out_of_range_store           ; yes: truncate
	bra.s	fp_denormalise_round_up         ; positive: round up if inexact
fp_denormalise_toward_minus:
	tst.w	d0                              ; positive?
	bpl.s	fp_out_of_range_store           ; yes: truncate
fp_denormalise_round_up:
	tst.l	d3                              ; any bits shifted out?
	beq.s	fp_out_of_range_store           ; no: exact
	addq.l	#1,d2                           ; add one to the mantissa
	bcc.s	fp_out_of_range_store           ; no carry
	addq.l	#1,d1                           ; carry into the high long
fp_out_of_range_store:
	move.l	d2,(a0)                         ; store the low long,
	move.l	d1,-(a0)                        ; the high long
	move.w	d0,-(a0)                        ; and the exponent
	move.l	(sp)+,(sp)                      ; drop the tag
	rts
	moveq	#5,d3                           ; exception 5, not referenced

;------------------------------------------------------------------------------
; fp_raise_result: stores the result d0/d1:d2 at a0 - 6, raises exception d3 through
; fp_raise with the tag on the stack, then returns with the tag removed.
;------------------------------------------------------------------------------
fp_raise_result:	; from: fp_invalid, fp_div_by_zero, fp_out_of_range
	subq.w	#6,a0                           ; a0 = the operand
	move.l	d2,-(sp)                        ; result on the stack
	move.l	d1,-(sp)
	move.w	d0,-(sp)
	pea	(sp)                            ; result pointer
	move.l	$12(sp),-(sp)                   ; the tag
	move.w	d3,d0                           ; exception code
	bsr.s	fp_raise                        ; raise it
	addq.w	#8,sp                           ; pop both
	move.w	(sp)+,(a0)+                     ; copy the result (the handler's
	move.l	(sp)+,(a0)+                     ; one, if any) to the operand
	move.l	(sp)+,(a0)
	subq.w	#6,a0                           ; a0 back to the start
	move.l	(sp)+,(sp)                      ; drop the tag
	rts

;------------------------------------------------------------------------------
; fp_raise: floating-point exception d0 (1 invalid, 2 division by zero, 3 overflow,
; 4 underflow, 5 probably inexact).  4(sp) = tag of the operation, 8(sp) = result.
; Sets the sticky flag, bit 5-d0 of fpu_mode.  If that exception is enabled (the same bit
; of fpu_flags) and fp_exception_handlers has a handler for it, calls the handler with
; a0 = record {code.w, tag.l, operand a0.x, operand a1.x, result.x} and fpu_flags/fpu_mode
; cleared; a non-zero d0 back copies the record's result to the result.  Otherwise
; errno = EDOM (33) for codes 1-2, ERANGE (34) above.  Keeps all registers but d0-d1.
;------------------------------------------------------------------------------
fp_raise:	; from: fp_domain_nan, fp_raise_result
	move.l	a1,-(sp)                        ; save the operand pointers
	move.l	a0,-(sp)
	movea.l	$10(sp),a0                      ; result pointer
	addq.w	#6,a0                           ; from its end
	move.l	(a0),-(sp)                      ; record: result
	move.l	-(a0),-(sp)
	move.w	-(a0),-(sp)
	movea.l	$a(sp),a0                       ; operand a0
	addq.w	#6,a0                           ; from its end
	addq.w	#6,a1                           ; operand a1 end
	move.l	(a1),-(sp)                      ; record: operand a1
	move.l	-(a1),-(sp)
	move.w	-(a1),-(sp)
	move.l	(a0),-(sp)                      ; record: operand a0
	move.l	-(a0),-(sp)
	move.w	-(a0),-(sp)
	move.l	$2a(sp),-(sp)                   ; record: tag of the operation
	move.w	d0,-(sp)                        ; record: exception code
	lea	fpu_mode(pc),a0                 ; sticky flags
	move.w	d0,d1                           ; bit 5 - code
	neg.w	d1
	addq.w	#5,d1
	bset	d1,(a0)                         ; set the sticky exception flag
	btst	d1,-(a0)                        ; enabled in fpu_flags?
	beq.s	fp_raise_no_handler             ; no: errno
	lea	fp_exception_handlers(pc),a1    ; handler table
	lsl.w	#2,d0                           ; code * 4
	move.l	-$4(a1,d0.w),d0                 ; handler for this code
	beq.s	fp_raise_no_handler             ; none: errno
	movea.l	d0,a1
	move.w	(a0),-(sp)                      ; save fpu_flags/fpu_mode
	clr.w	(a0)                            ; and clear them for the handler
	lea	2(sp),a0                        ; a0 = the record
	jsr	(a1)                            ; call the handler
	lea	fpu_flags(pc),a0
	move.w	(sp)+,(a0)                      ; restore fpu_flags/fpu_mode
	tst.w	d0                              ; handler gave a result?
	bne.s	fp_raise_copy_result            ; yes: copy it
fp_raise_no_handler:
	move.w	(sp),d0                         ; exception code
	cmpi.w	#$2,d0                          ; invalid or division by zero?
	bls.s	fp_raise_edom                   ; yes: EDOM
	move.w	#$22,errno                      ; errno = ERANGE
	bra.s	fp_raise_done
fp_raise_edom:
	move.w	#$21,errno                      ; errno = EDOM
	bra.s	fp_raise_done
fp_raise_copy_result:
	movea.l	$34(sp),a0                      ; result pointer
	lea	$1a(sp),a1                      ; the record's result
	move.w	(a1)+,(a0)+                     ; copied to it
	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
fp_raise_done:
	lea	$24(sp),sp                      ; drop the record
	movea.l	(sp)+,a0
	movea.l	(sp)+,a1
	rts

;------------------------------------------------------------------------------
; fp_from_double: converts the IEEE double at (a0) to an extended at (a1): shifts the
; fraction to the top, rebiases the exponent and sets the integer bit; normalises a
; denormal.  Changes d0-d2.
;------------------------------------------------------------------------------
fp_from_double:	; from: fadd_double
	move.l	(a0),d1                         ; high long: sign, exponent, fraction
	move.l	4(a0),d2                        ; low long of the fraction
	move.l	d1,d0                           ; sign and exponent
	swap	d0                              ; in the low word
	ext.l	d0                              ; sign into the high word
	rol.l	#8,d2                           ; shift the 64 bits left 8
	rol.l	#8,d1
	move.b	d2,d1                           ; top byte of the low long
	clr.b	d2                              ; moves to the high long
	add.l	d2,d2                           ; and 3 more: fraction
	roxl.l	#1,d1                           ; below the integer bit
	add.l	d2,d2
	roxl.l	#1,d1
	add.l	d2,d2
	roxl.l	#1,d1
	bclr	#$1f,d1                         ; clear the exponent bit left there
	andi.w	#$7ff0,d0                       ; exponent field
	cmpi.w	#$7ff0,d0                       ; infinity or NaN?
	bne.s	fp_from_double_finite           ; no: finite
	tst.l	d2                              ; fraction zero?
	bne.s	fp_from_double_nan
	tst.l	d1
	bne.s	fp_from_double_nan
	moveq	#0,d1                           ; infinity: mantissa zero
	bra.s	fp_from_double_special
fp_from_double_nan:
	moveq	#-1,d1                          ; NaN: mantissa all ones
fp_from_double_special:
	move.l	d1,d2                           ; low long the same
	st	d0                              ; exponent $7fff (sign in the high word)
	bra.s	fp_from_double_store
fp_from_double_finite:
	lsr.w	#4,d0                           ; biased exponent
	bne.s	fp_from_double_bias             ; not zero: normal
	tst.l	d1                              ; fraction zero: zero
	bne.s	fp_from_double_denormal
	tst.l	d2
	beq.s	fp_from_double_store
fp_from_double_denormal:
	subq.w	#1,d0                           ; denormal: exponent - 1
	add.l	d2,d2                           ; shift the fraction left
	addx.l	d1,d1
	bpl.s	fp_from_double_denormal         ; until bit 63 is set
	addq.w	#1,d0                           ; denormal exponent is 1
fp_from_double_bias:
	addi.w	#$3c00,d0                       ; rebias 1023 to 16383
	bset	#$1f,d1                         ; set the integer bit
fp_from_double_store:
	add.l	d0,d0                           ; sign bit 31 into X,
	roxr.w	#1,d0                           ; then into bit 15
	move.w	d0,(a1)+                        ; store the exponent,
	move.l	d1,(a1)+                        ; the high long
	move.l	d2,(a1)                         ; and the low long
	subq.w	#6,a1                           ; a1 back to the start
	rts

;------------------------------------------------------------------------------
; fp_from_float: converts the IEEE single in d0 to an extended at (a0), as
; fp_from_double.  Changes d0-d2.
;------------------------------------------------------------------------------
fp_from_float:	; from: fadd_float
	move.l	d0,d1                           ; fraction
	swap	d0                              ; sign and exponent
	move.w	d0,d2                           ; kept for the sign
	lsl.l	#8,d1                           ; fraction to the top
	bclr	#$1f,d1                         ; clear the exponent bit left there
	andi.w	#$7f80,d0                       ; exponent field
	cmpi.w	#$7f80,d0                       ; infinity or NaN?
	bne.s	fp_from_float_finite            ; no: finite
	move.w	#$7fff,d0                       ; exponent $7fff, fraction kept
	bra.s	fp_from_float_store
fp_from_float_finite:
	lsr.w	#7,d0                           ; biased exponent
	bne.s	fp_from_float_bias              ; not zero: normal
	tst.l	d1                              ; fraction zero: zero
	beq.s	fp_from_float_store
fp_from_float_denormal:
	subq.w	#1,d0                           ; denormal: exponent - 1
	add.l	d1,d1                           ; shift the fraction left
	bpl.s	fp_from_float_denormal          ; until bit 31 is set
	addq.w	#1,d0                           ; denormal exponent is 1
fp_from_float_bias:
	addi.w	#$3f80,d0                       ; rebias 127 to 16383
	bset	#$1f,d1                         ; set the integer bit
fp_from_float_store:
	add.w	d0,d0                           ; exponent up one bit
	add.w	d2,d2                           ; sign bit 15 into X
	roxr.w	#1,d0                           ; and into bit 15 of the exponent
	move.w	d0,(a0)+                        ; store the exponent,
	move.l	d1,(a0)+                        ; the high long
	clr.l	(a0)                            ; and a zero low long
	subq.w	#6,a0                           ; a0 back to the start
	rts

;------------------------------------------------------------------------------
; fp_to_long: returns the extended at (a0) as a long in d0, truncated toward zero.
; Too large, infinity or NaN give $7fffffff (or its negation); zero gives 0.
; Changes d0-d2.
;------------------------------------------------------------------------------
fp_to_long:	; from: print_g_float
	bsr.w	fp_classify                     ; unpack
	bne.s	fp_to_long_nonzero              ; not zero
	moveq	#0,d0                           ; zero gives 0
	rts
fp_to_long_nonzero:
	andi.w	#$7fff,d0                       ; exponent alone
	subi.w	#$401e,d0                       ; exponent - (bias + 31)
	bmi.s	fp_to_long_shift                ; below 2^31: shift
	move.l	#$7fffffff,d0                   ; too large: saturate
	bra.s	fp_to_long_sign
fp_to_long_shift:
	neg.w	d0                              ; shift = 31 - exponent
	cmpi.w	#$1f,d0                         ; more than 31?
	bls.s	fp_to_long_in_range             ; no: shift
	moveq	#0,d0                           ; below 1: 0
	rts
fp_to_long_in_range:
	lsr.l	d0,d1                           ; integer part
	move.l	d1,d0                           ; to d0
fp_to_long_sign:
	tst.w	(a0)                            ; negative?
	bpl.s	fp_to_long_done                 ; no
	neg.l	d0                              ; negate
fp_to_long_done:
	rts

;------------------------------------------------------------------------------
; fp_from_int: converts the int d0.w to an extended at (a0).
;------------------------------------------------------------------------------
fp_from_int:
	ext.l	d0                              ; int to long

;------------------------------------------------------------------------------
; fp_from_long: converts the long d0 to an extended at (a0): takes the magnitude and
; normalises it by 16, 8, 4, 2 and 1 bit steps.  Changes d0-d2.
;------------------------------------------------------------------------------
fp_from_long:	; from: load_and_unpack, fdiv_long
	move.l	d0,d2                           ; keep the sign
	bne.s	fp_from_long_nonzero            ; not zero
	clr.w	d1                              ; zero: exponent 0
	bra.s	fp_from_long_store              ; store zero
fp_from_long_nonzero:
	bpl.s	fp_from_long_positive           ; positive
	neg.l	d0                              ; magnitude
	bvc.s	fp_from_long_positive           ; not $80000000
	move.w	#$c01e,d1                       ; -2^31: exponent and sign
	move.l	#$80000000,d0                   ; mantissa $80000000
	bra.s	fp_from_long_store              ; store
fp_from_long_positive:
	move.w	#$401e,d1                       ; exponent for bit 31
	swap	d0                              ; words swapped: low word = top 16 bits
	tst.w	d0                              ; top 16 bits zero?
	bne.s	fp_from_long_by_8               ; no
	subi.w	#$10,d1                         ; yes: shift 16 bits
	swap	d0                              ; low word to the top
fp_from_long_by_8:
	cmpi.w	#$ff,d0                         ; top 8 bits zero?
	bhi.s	fp_from_long_by_4               ; no
	subq.w	#8,d1                           ; yes: shift 8 bits
	rol.l	#8,d0
fp_from_long_by_4:
	cmpi.w	#$fff,d0                        ; top 4 bits zero?
	bhi.s	fp_from_long_by_2               ; no
	subq.w	#4,d1                           ; yes: shift 4 bits
	rol.l	#4,d0
fp_from_long_by_2:
	cmpi.w	#$3fff,d0                       ; top 2 bits zero?
	bhi.s	fp_from_long_by_1               ; no
	subq.w	#2,d1                           ; yes: shift 2 bits
	rol.l	#2,d0
fp_from_long_by_1:
	tst.w	d0                              ; top bit set?
	bmi.s	fp_from_long_sign               ; yes
	subq.w	#1,d1                           ; no: shift 1 bit
	rol.l	#1,d0
fp_from_long_sign:
	swap	d0                              ; words back in order
	add.w	d1,d1                           ; exponent up one bit
	add.l	d2,d2                           ; sign bit 31 into X
	roxr.w	#1,d1                           ; and into bit 15
fp_from_long_store:
	move.w	d1,(a0)+                        ; store the exponent,
	move.l	d0,(a0)+                        ; the high long
	clr.l	(a0)                            ; and a zero low long
	subq.w	#6,a0                           ; a0 back to the start
	rts

;------------------------------------------------------------------------------
; Extended constants: e, log10(2), ln(2), pi, pi/2, pi/4, 1, 2 and 10.
;------------------------------------------------------------------------------
fp_e:
	dc.w	$4000,$adf8,$5458,$a2bb,$4a9b   ; e
fp_log10_2:	; from: ext_log10
	dc.w	$3ffd,$9a20,$9a84,$fbcf,$f799   ; log10(2)
fp_ln2:	; from: log, log1p
	dc.w	$3ffe,$b172,$17f7,$d1cf,$79ac   ; ln(2)
fp_pi:
	dc.w	$4000,$c90f,$daa2,$2168,$c235   ; pi
fp_half_pi:
	dc.w	$3fff,$c90f,$daa2,$2168,$c235   ; pi/2
fp_quarter_pi:
	dc.w	$3ffe,$c90f,$daa2,$2168,$c235   ; pi/4
fp_one:	; from: ext_fsub, soft_finc
	dc.w	$3fff,$8000,$0000,$0000,$0000   ; 1.0
fp_two:	; from: soft_frecip
	dc.w	$4000,$8000,$0000,$0000,$0000   ; 2.0
fp_ten:	; from: cvt_digits
	dc.w	$4002,$a000,$0000,$0000,$0000   ; 10.0

;------------------------------------------------------------------------------
; Texts printf uses for a NaN and the infinities.
;------------------------------------------------------------------------------
str_nan:	; from: cvt_digits
	dc.b	'NaN',0                         ; NaN
str_minus_inf:	; from: cvt_digits
	dc.b	'-INF',0                        ; negative infinity
str_plus_inf:	; from: cvt_digits
	dc.b	'+INF',0                        ; positive infinity

;------------------------------------------------------------------------------
; clock: returns the 200 Hz system timer _hz_200 in d0, read in supervisor mode with
; Supexec.  Changes d0-d2/a0-a1.
;------------------------------------------------------------------------------
clock:	; from: load_and_unpack
	move.l	a2,-(sp)                        ; save a2
	pea	read_hz_200(pc)                 ; routine to run
	move.w	#$26,-(sp)
	trap	#14                             ; Supexec
	addq.w	#6,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; read_hz_200: the Supexec routine, d0 = _hz_200.
;------------------------------------------------------------------------------
read_hz_200:	; from: clock
	move.l	$4ba.w,d0                       ; _hz_200, 200 Hz system timer
	rts

;------------------------------------------------------------------------------
; sprintf: formats a1 with the arguments on the stack into the buffer a0, through
; do_printf with sprintf_out as the output function, and terminates the string.
; Returns the count in d0.  Changes d0-d2/a0-a1.
;------------------------------------------------------------------------------
sprintf:	; from: load_and_unpack, unpack_and_save
	move.l	a6,-(sp)                        ; frame pointer for sprintf_out
	subq.w	#4,sp                           ; one long: the buffer pointer
	lea	(sp),a6
	move.l	a0,(a6)                         ; (a6) = buffer pointer
	movea.l	a1,a0                           ; format string
	lea	$c(sp),a1                       ; the arguments
	pea	sprintf_out(pc)                 ; output function
	bsr.w	do_printf                       ; format into the buffer
	addq.w	#4,sp                           ; drop the output function
	movea.l	(a6),a0                         ; buffer end
	clr.b	(a0)                            ; terminate the string
	addq.w	#4,sp                           ; drop the buffer pointer
	movea.l	(sp)+,a6
	rts

;------------------------------------------------------------------------------
; sprintf_out: copies d0 bytes from a0 to the buffer pointer kept at (a6) and advances it.
;------------------------------------------------------------------------------
sprintf_out:	; from: sprintf
	movea.l	(a6),a1                         ; buffer pointer
	subq.w	#1,d0                           ; count - 1
	bcs.s	sprintf_out_done                ; nothing to copy
sprintf_out_loop:
	move.b	(a0)+,(a1)+                     ; copy a byte
	dbra	d0,sprintf_out_loop             ; for the count
	move.l	a1,(a6)                         ; advance the buffer pointer
sprintf_out_done:
	rts

;------------------------------------------------------------------------------
; print_signed: printf %d.  d0 = value (long), d1 = flags, d2 = width, a0 = output
; function, 4(sp) = precision.  Flags: bit 0 space, 1 #, 2 +, 3 - (left justify),
; 4 0 (zero pad), 5 upper case.  Sets the sign prefix, then print_number.
; Returns the number of characters output in d0.  Changes d0-d2/a0-a1.
;------------------------------------------------------------------------------
print_signed:	; from: do_printf
	movem.l	d3-d4/a2,-(sp)                  ; save registers
	lea	-$18(sp),sp                     ; frame for print_number
	moveq	#10,d3                          ; radix 10
	tst.l	d0                              ; negative?
	bpl.s	print_signed_plus               ; no
	move.b	#$2d,6(sp)                      ; prefix '-'
	move.w	#$1,8(sp)                       ; one character
	neg.l	d0                              ; magnitude
	bra.w	print_number
print_signed_plus:
	btst	#$2,d1                          ; flag +?
	beq.s	print_signed_space              ; no
	move.b	#$2b,6(sp)                      ; prefix '+'
	move.w	#$1,8(sp)                       ; one character
	bra.w	print_number
print_signed_space:
	btst	#$0,d1                          ; flag space?
	beq.s	print_signed_no_prefix          ; no
	move.b	#$20,6(sp)                      ; prefix ' '
	move.w	#$1,8(sp)                       ; one character
	bra.s	print_number
print_signed_no_prefix:
	move.w	#$0,8(sp)                       ; no prefix
	bra.s	print_number

;------------------------------------------------------------------------------
; print_unsigned: printf %u, arguments as print_signed.
;------------------------------------------------------------------------------
print_unsigned:	; from: do_printf
	movem.l	d3-d4/a2,-(sp)                  ; save registers
	lea	-$18(sp),sp                     ; frame for print_number
	moveq	#10,d3                          ; radix 10
	move.w	#$0,8(sp)                       ; no prefix
	bra.s	print_number

;------------------------------------------------------------------------------
; print_hex: printf %x/%X, arguments as print_signed; # gives the 0x / 0X prefix.
;------------------------------------------------------------------------------
print_hex:	; from: do_printf
	movem.l	d3-d4/a2,-(sp)                  ; save registers
	lea	-$18(sp),sp                     ; frame for print_number
	moveq	#16,d3                          ; radix 16
	btst	#$1,d1                          ; flag #?
	bne.s	print_hex_prefix                ; yes: prefix
	move.w	#$0,8(sp)                       ; no prefix
	bra.s	print_number
print_hex_prefix:
	move.b	#$30,6(sp)                      ; '0'
	btst	#$5,d1                          ; upper case?
	bne.s	print_hex_prefix_upper          ; yes: 0X
	move.b	#$78,7(sp)                      ; 'x'
	move.w	#$2,8(sp)                       ; two characters
	bra.s	print_number
print_hex_prefix_upper:
	move.b	#$58,7(sp)                      ; 'X'
	move.w	#$2,8(sp)                       ; two characters
	bra.s	print_number

;------------------------------------------------------------------------------
; print_octal: printf %o, arguments as print_signed; # gives the 0 prefix.
;------------------------------------------------------------------------------
print_octal:	; from: do_printf
	movem.l	d3-d4/a2,-(sp)                  ; save registers
	lea	-$18(sp),sp                     ; frame for print_number
	moveq	#8,d3                           ; radix 8
	btst	#$1,d1                          ; flag #?
	bne.s	print_octal_prefix              ; yes: prefix
	move.w	#$0,8(sp)                       ; no prefix
	bra.s	print_number
print_octal_prefix:
	move.b	#$30,6(sp)                      ; '0'
	move.w	#$1,8(sp)                       ; one character

;------------------------------------------------------------------------------
; print_number: shared by the four.  Converts the value with ultoa, upper-cases it for
; flag 5, works out the zeros (precision, or flag 0 to the width) and the spaces, then
; print_number_fields outputs them.  Frame: (sp) flags, 2 spaces, 4 zeros, 6 prefix,
; 8 prefix length, $a digits, $16 digit count, d3 radix.
;------------------------------------------------------------------------------
print_number:	; from: print_signed, print_unsigned, print_hex, print_octal
	movea.l	a0,a2                           ; a2 = output function
	move.w	d1,(sp)                         ; save the flags
	exg	d3,d1                           ; d1 = radix, d3 = flags
	move.w	d2,d4                           ; d4 = width
	bpl.s	print_number_convert            ; given?
	moveq	#0,d4                           ; no: 0
print_number_convert:
	lea	$a(sp),a0                       ; digit buffer
	bsr.w	ultoa                           ; digits of the value
	lea	$a(sp),a0                       ; digit buffer
	moveq	#-1,d0                          ; count the digits
print_number_count:
	tst.b	(a0)+                           ; until the terminator
	dbeq	d0,print_number_count
	not.w	d0                              ; d0 = digit count
	move.w	d0,$16(sp)                      ; save it
	btst	#$5,d3                          ; upper case?
	beq.s	print_number_lengths            ; no
	lea	$a(sp),a0                       ; digit buffer
	move.w	d0,d1                           ; count
	subq.w	#1,d1                           ; - 1
	bmi.s	print_number_lengths            ; no digits
	moveq	#97,d2                          ; 'a'
print_number_upper_loop:
	cmp.b	(a0)+,d2                        ; below 'a'?
	dbls	d1,print_number_upper_loop      ; skip to the next letter
	bhi.s	print_number_lengths            ; no letters left
	andi.b	#$df,-$1(a0)                    ; make it upper case
	dbra	d1,print_number_upper_loop      ; next
print_number_lengths:
	move.w	8(sp),d1                        ; prefix length
	add.w	d0,d1                           ; + digits
	move.w	$28(sp),d2                      ; precision
	bpl.s	print_number_zero_count         ; given?
	moveq	#1,d2                           ; no: 1
print_number_zero_count:
	sub.w	d0,d2                           ; minus the digits
	bpl.s	print_number_width              ; zeros needed?
	moveq	#0,d2                           ; no: 0
print_number_width:
	add.w	d2,d1                           ; total length
	btst	#$4,d3                          ; flag 0?
	beq.s	print_number_spaces             ; no
	btst	#$3,d3                          ; and not left justified?
	bne.s	print_number_spaces             ; no
	move.w	d4,d0                           ; width
	sub.w	d1,d0                           ; - total
	ble.s	print_number_no_spaces          ; already wide enough
	add.w	d0,d1                           ; fill to the width
	add.w	d0,d2                           ; with zeros
print_number_spaces:
	sub.w	d1,d4                           ; spaces = width - total
	bge.s	print_number_save               ; not negative
print_number_no_spaces:
	moveq	#0,d4                           ; none
print_number_save:
	move.w	d2,4(sp)                        ; zeros
	move.w	d4,2(sp)                        ; spaces
	bra.s	print_number_fields             ; output the fields

;------------------------------------------------------------------------------
; print_char: printf %c.  a0 = buffer holding the character, d0 = flags, d1 = width,
; a1 = output function.  Returns the number of characters output in d0.
; Changes d0-d2/a0-a1.
;------------------------------------------------------------------------------
print_char:	; from: do_printf
	movem.l	d3-d4/a2-a3,-(sp)               ; save registers
	movea.l	a0,a2                           ; a2 = text
	movea.l	a1,a3                           ; a3 = output function
	clr.b	1(a0)                           ; terminate after the character
	moveq	#1,d3                           ; length 1
	bra.s	print_text

;------------------------------------------------------------------------------
; print_string: printf %s.  a0 = string, d0 = flags, d1 = width, d2 = precision (the
; most characters to print, negative for all), a1 = output function.  Pads with spaces on
; the left, or on the right for flag 3.  Returns the number of characters output in d0.
; Changes d0-d2/a0-a1.
;------------------------------------------------------------------------------
print_string:	; from: do_printf
	movem.l	d3-d4/a2-a3,-(sp)               ; save registers
	movea.l	a0,a2                           ; a2 = text
	movea.l	a1,a3                           ; a3 = output function
	moveq	#-1,d3                          ; count the length
print_string_length:
	tst.b	(a0)+                           ; until the terminator
	dbeq	d3,print_string_length
	not.w	d3                              ; d3 = length
print_text:	; from: print_char
	tst.w	d2                              ; precision given?
	bpl.s	print_text_limit                ; yes
	move.w	d3,d2                           ; no: the length
print_text_limit:
	cmp.w	d3,d2                           ; precision below the length?
	bhi.s	print_text_width                ; no
	move.w	d2,d3                           ; yes: print that many
print_text_width:
	moveq	#0,d4                           ; spaces = 0
	tst.w	d1                              ; width given?
	bmi.s	print_text_order                ; no
	cmp.w	d3,d1                           ; wider than the text?
	bls.s	print_text_order                ; no
	move.w	d1,d4                           ; spaces = width
	sub.w	d3,d4                           ; - length
print_text_order:
	btst	#$3,d0                          ; left justified?
	bne.s	print_text_left                 ; yes
	movea.l	a3,a0                           ; output function
	move.w	d4,d0                           ; spaces
	bsr.w	print_spaces                    ; first
	move.w	d3,d0                           ; length
	movea.l	a2,a0                           ; text
	jsr	(a3)                            ; then the text
	bra.s	print_text_done
print_text_left:
	move.w	d3,d0                           ; length
	movea.l	a2,a0                           ; text
	jsr	(a3)                            ; first
	move.w	d4,d0                           ; spaces
	movea.l	a3,a0                           ; output function
	bsr.s	print_spaces                    ; after it
print_text_done:
	move.w	d3,d0                           ; characters output
	add.w	d4,d0                           ; = length + spaces
	movem.l	(sp)+,d3-d4/a2-a3
	rts

;------------------------------------------------------------------------------
; print_number_fields: outputs leading spaces (unless left justified), the prefix, the
; zeros, the digits and trailing spaces (if left justified) through the output function
; in a2, from the print_number frame.  Returns the count in d0.
;------------------------------------------------------------------------------
print_number_fields:	; from: print_number
	move.w	(sp),d3                         ; flags
	moveq	#0,d4                           ; count = 0
	move.w	2(sp),d0                        ; spaces
	beq.s	print_number_prefix             ; none
	btst	#$3,d3                          ; left justified?
	bne.s	print_number_prefix             ; yes: they go after
	add.w	d0,d4                           ; count
	movea.l	a2,a0                           ; output function
	bsr.s	print_spaces                    ; leading spaces
print_number_prefix:
	move.w	8(sp),d0                        ; prefix length
	beq.s	print_number_zero_fill          ; none
	add.w	d0,d4                           ; count
	lea	6(sp),a0                        ; prefix
	jsr	(a2)                            ; output it
print_number_zero_fill:
	move.w	4(sp),d0                        ; zeros
	beq.s	print_number_digits             ; none
	add.w	d0,d4                           ; count
	movea.l	a2,a0                           ; output function
	bsr.s	print_zeros                     ; zeros
print_number_digits:
	move.w	$16(sp),d0                      ; digit count
	beq.s	print_number_trailing           ; none
	add.w	d0,d4                           ; count
	lea	$a(sp),a0                       ; digits
	jsr	(a2)                            ; output them
print_number_trailing:
	move.w	2(sp),d0                        ; spaces
	beq.s	print_number_done               ; none
	btst	#$3,d3                          ; left justified?
	beq.s	print_number_done               ; no: already output
	add.w	d0,d4                           ; count
	movea.l	a2,a0                           ; output function
	bsr.s	print_spaces                    ; trailing spaces
print_number_done:
	move.w	d4,d0                           ; characters output
	lea	$18(sp),sp                      ; drop the frame
	movem.l	(sp)+,d3-d4/a2
	rts

;------------------------------------------------------------------------------
; print_zeros: outputs d0 '0' characters through the output function a0.
;------------------------------------------------------------------------------
print_zeros:	; from: print_float_fields, print_number_fields
	movem.l	d3-d4/a2-a3,-(sp)               ; save registers
	lea	pad_zeros(pc),a2                ; pad with zeros
	bra.s	print_pad

;------------------------------------------------------------------------------
; print_spaces: outputs d0 spaces through the output function a0, 8 at a time.
; Changes d0-d2/a0-a1.
;------------------------------------------------------------------------------
print_spaces:	; from: print_float_fields, print_string, print_number_fields
	movem.l	d3-d4/a2-a3,-(sp)               ; save registers
	lea	pad_spaces(pc),a2               ; pad with spaces
print_pad:	; from: print_zeros
	movea.l	a0,a3                           ; a3 = output function
	move.w	d0,d3                           ; count
	beq.s	print_pad_done                  ; none
	move.w	d0,d4                           ; keep it
	lsr.w	#3,d3                           ; blocks of 8
	beq.s	print_pad_rest                  ; none
	subq.w	#1,d3                           ; dbra count
print_pad_block:
	movea.l	a2,a0                           ; pad text
	moveq	#8,d0                           ; 8 characters
	jsr	(a3)                            ; output them
	dbra	d3,print_pad_block              ; for each block
print_pad_rest:
	movea.l	a2,a0                           ; pad text
	move.w	d4,d0                           ; count
	andi.w	#$7,d0                          ; the rest, 0-7
	beq.s	print_pad_done                  ; none
	jsr	(a3)                            ; output them
print_pad_done:
	movem.l	(sp)+,d3-d4/a2-a3
	rts

;------------------------------------------------------------------------------
; Eight zeros and eight spaces for the padding.
;------------------------------------------------------------------------------
pad_zeros:	; from: print_zeros
	dc.b	'00000000'
pad_spaces:	; from: print_spaces
	dc.b	'        '

;------------------------------------------------------------------------------
; itoa: converts the int d0 to a string in radix d1 (2-36) at a0; a negative value gets
; a '-' only in radix 10.  Divides by the radix, digits from the right into a stack
; buffer, then copies them.  Returns a0.  A bad radix sets errno = EDOM and gives an
; empty string.  Changes d0-d2/a1.
;------------------------------------------------------------------------------
itoa:	; from: print_e_float
	move.l	d3,-(sp)                        ; save registers
	move.l	a0,-(sp)                        ; keep the buffer
	lea	-$12(sp),sp                     ; digit buffer on the stack
	move.w	d1,d2                           ; radix
	subq.w	#2,d2                           ; - 2
	cmp.w	#$22,d2                         ; radix 2-36?
	bhi.s	itoa_bad_radix                  ; no: error
	tst.w	d0                              ; negative?
	bpl.s	itoa_convert                    ; no
	cmp.b	#$a,d1                          ; radix 10?
	bne.s	itoa_convert                    ; no: unsigned
	neg.w	d0                              ; magnitude
	move.b	#$2d,(a0)+                      ; with a '-'
itoa_convert:
	lea	$12(sp),a1                      ; end of the digit buffer
	moveq	#-1,d2                          ; d2 = digit count - 1
	swap	d0                              ; clear the high word
	clr.w	d0
	swap	d0
itoa_divide:
	divu.w	d1,d0                           ; divide by the radix
	move.l	d0,d3                           ; remainder
	swap	d3                              ; to the low word
	move.b	itoa_digits(pc,d3.w),-(a1)      ; its digit, from the right
	addq.w	#1,d2                           ; count it
	swap	d0                              ; quotient,
	clr.w	d0                              ; high word cleared
	swap	d0
	bne.s	itoa_divide                     ; until zero
itoa_copy:
	move.b	(a1)+,(a0)+                     ; copy the digits
	dbra	d2,itoa_copy                    ; to the buffer
itoa_terminate:
	clr.b	(a0)+                           ; terminate
	lea	$12(sp),sp                      ; drop the digit buffer
	movea.l	(sp)+,a0                        ; return the buffer
	move.l	(sp)+,d3
	rts
itoa_bad_radix:
	move.w	#$21,errno                      ; errno = EDOM
	bra.s	itoa_terminate                  ; empty string

;------------------------------------------------------------------------------
; Digits for itoa.
;------------------------------------------------------------------------------
itoa_digits:	; from: itoa
	dc.b	'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'

;------------------------------------------------------------------------------
; strcat: appends the string a1 to a0.  Returns a0.  Changes d0/a1.
;------------------------------------------------------------------------------
strcat:	; from: show_reading, show_checking, show_writing, init_paths, unpack_and_save, main
	move.l	a0,d0                           ; keep the destination
strcat_find_end:
	tst.b	(a0)+                           ; find the end
	bne.s	strcat_find_end
	subq.w	#1,a0                           ; back onto the terminator
strcat_copy:
	move.b	(a1)+,(a0)+                     ; copy, terminator included
	bne.s	strcat_copy
	movea.l	d0,a0                           ; return the destination
	rts

;------------------------------------------------------------------------------
; strrchr: returns in a0 the last d0 in the string a0, or 0.
; For d0 = 0 returns the terminator.  Changes d1/a1.
;------------------------------------------------------------------------------
strrchr:	; from: unpack_and_save, main
	suba.l	a1,a1                           ; none found yet
strrchr_loop:
	move.b	(a0)+,d1                        ; next character
	beq.s	strrchr_end                     ; end of the string
	cmp.b	d0,d1                           ; the one searched for?
	bne.s	strrchr_loop                    ; no
	lea	-$1(a0),a1                      ; remember its position
	bra.s	strrchr_loop
strrchr_end:
	tst.b	d0                              ; searching for the terminator?
	beq.s	strrchr_terminator              ; yes
	movea.l	a1,a0                           ; last one found, or 0
	rts
strrchr_terminator:
	subq.w	#1,a0                           ; the terminator
	rts

;------------------------------------------------------------------------------
; strcpy: copies the string a1 to a0.  Returns a0.  Changes d0/a1.
;------------------------------------------------------------------------------
strcpy:	; from: show_reading, show_checking, show_unpacking, show_writing, init_paths, unpack_and_save, 1 more
	move.l	a0,d0                           ; keep the destination
strcpy_loop:
	move.b	(a1)+,(a0)+                     ; copy, terminator included
	bne.s	strcpy_loop
	movea.l	d0,a0                           ; return the destination
	rts

;------------------------------------------------------------------------------
; strtoul: converts the string a0 in base d0 (0 = by prefix: 0x hex, 0 octal, else
; decimal) to an unsigned long in d0, skipping leading white space; no sign is read.
; a1 = pointer for the end position, or 0.  Overflow gives -1 and errno = ERANGE, a bad
; base 0 and errno = EDOM.  Changes d0-d2.
;------------------------------------------------------------------------------
strtoul:	; from: do_printf
	movem.l	d3/a2-a3,-(sp)                  ; save registers
	movea.l	a0,a2                           ; a2 = string
	cmp.w	#$1,d0                          ; base 1?
	beq.w	strtoul_bad_base                ; error
	cmp.w	#$24,d0                         ; base above 36?
	bhi.w	strtoul_bad_base                ; error
	lea	ctype_table(pc),a3              ; character classes
	moveq	#0,d1                           ; character
	moveq	#0,d2                           ; value = 0
strtoul_skip_space:
	move.b	(a2)+,d1                        ; next character
	beq.w	strtoul_end                     ; end: value 0
	tst.b	0(a3,d1.w)                      ; white space?
	bmi.s	strtoul_skip_space              ; skip it
	subq.w	#1,a2                           ; back to it
	move.b	(a2)+,d1                        ; first character
	beq.s	strtoul_end                     ; end: value 0
	tst.w	d0                              ; base given?
	bne.s	strtoul_base_16                 ; yes
	moveq	#10,d0                          ; base 0: decimal
	cmp.b	#$30,d1                         ; unless it starts with '0'
	bne.s	strtoul_first_digit             ; no: decimal
	moveq	#8,d0                           ; leading 0: octal
	move.b	(a2)+,d1                        ; next character
	beq.s	strtoul_end                     ; end: value 0
	move.b	d1,d3                           ; upper case
	andi.b	#$df,d3
	cmp.b	#$58,d3                         ; 'X'?
	bne.s	strtoul_first_digit             ; no: octal
	moveq	#16,d0                          ; 0x: hex
	move.b	(a2)+,d1                        ; next character
	bne.s	strtoul_first_digit             ; digits follow
	bra.s	strtoul_end                     ; end: value 0
strtoul_base_16:
	cmp.w	#$10,d0                         ; base 16?
	bne.s	strtoul_first_digit             ; no
	cmp.b	#$30,d1                         ; leading '0'?
	bne.s	strtoul_first_digit             ; no
	move.b	(a2)+,d1                        ; next character
	beq.s	strtoul_end                     ; end: value 0
	move.b	d1,d3                           ; upper case
	andi.b	#$df,d3
	cmp.b	#$58,d3                         ; 'X'?
	bne.s	strtoul_first_digit             ; no: the 0 was a digit
	move.b	(a2)+,d1                        ; skip the 0x
	beq.s	strtoul_end                     ; end: value 0
strtoul_first_digit:
	lea	digit_table(pc),a3              ; digit values
	move.b	0(a3,d1.w),d1                   ; value of the character
	cmp.b	d0,d1                           ; a digit in this base?
	bcc.s	strtoul_end                     ; no: value 0
	move.b	d1,d2                           ; value = first digit
strtoul_next_digit:
	move.b	(a2)+,d1                        ; next character
	move.b	0(a3,d1.w),d1                   ; its value
	cmp.b	d0,d1                           ; a digit in this base?
	bcc.s	strtoul_end                     ; no: end
	move.l	d2,d3                           ; value high word
	swap	d3
	mulu.w	d0,d3                           ; times the base
	swap	d3                              ; product high word
	tst.w	d3                              ; not zero?
	bne.s	strtoul_overflow                ; yes: overflow
	mulu.w	d0,d2                           ; low word times the base
	add.l	d3,d2                           ; plus the high part
	add.l	d1,d2                           ; plus the digit
	bcc.s	strtoul_next_digit              ; next unless it carried
	bra.s	strtoul_overflow                ; carry: overflow
strtoul_end:
	move.l	d2,d0                           ; result
	move.l	a1,d3                           ; end pointer wanted?
	beq.s	strtoul_return                  ; no
	subq.w	#1,a2                           ; back to the first non-digit
	move.l	a2,(a1)                         ; store it
strtoul_return:
	movem.l	(sp)+,d3/a2-a3
	rts
strtoul_overflow:
	move.w	#$22,errno                      ; errno = ERANGE
	moveq	#-1,d0                          ; result -1
	bra.s	strtoul_no_number
strtoul_bad_base:
	move.w	#$21,errno                      ; errno = EDOM
	moveq	#0,d0                           ; result 0
strtoul_no_number:
	move.l	a1,d3                           ; end pointer wanted?
	beq.s	strtoul_return                  ; no
	move.l	a0,(a1)                         ; end pointer = the string
	bra.s	strtoul_return

;------------------------------------------------------------------------------
; ultoa: converts the unsigned long d0 to a string in radix d1 (2-36) at a0, dividing a
; long value in two divu steps.  Returns a0.  A bad radix sets errno = EDOM.
; Changes d0-d2/a1.
;------------------------------------------------------------------------------
ultoa:	; from: show_checking, show_writing, print_number
	move.l	d3,-(sp)                        ; save registers
	move.l	a0,-(sp)                        ; keep the buffer
	suba.w	#$22,sp                         ; digit buffer on the stack
	move.w	d1,d2                           ; radix
	subq.w	#2,d2                           ; - 2
	cmp.w	#$22,d2                         ; radix 2-36?
	bhi.s	ultoa_bad_radix                 ; no: error
	lea	$22(sp),a1                      ; end of the digit buffer
	moveq	#-1,d2                          ; d2 = digit count - 1
	move.l	d0,d3                           ; high word
	swap	d3
	tst.w	d3                              ; set?
	bne.s	ultoa_long                      ; yes: long division
ultoa_divide_word:
	divu.w	d1,d0                           ; divide by the radix
	move.l	d0,d3                           ; remainder
	swap	d3                              ; to the low word
	move.b	ultoa_digits(pc,d3.w),-(a1)     ; its digit, from the right
	addq.w	#1,d2                           ; count it
	swap	d0                              ; quotient,
	clr.w	d0                              ; high word cleared
	swap	d0
	bne.s	ultoa_divide_word               ; until zero
	bra.s	ultoa_copy                      ; copy the digits
ultoa_long:
	move.w	d4,-(sp)                        ; save d4
ultoa_divide_long:
	move.l	d0,d3                           ; value
	move.w	d0,d4                           ; low word
	clr.w	d3                              ; high word
	swap	d3                              ; alone
	divu.w	d1,d3                           ; high word / radix
	move.w	d3,d0                           ; quotient high word
	move.w	d4,d3                           ; remainder:low word
	divu.w	d1,d3                           ; / radix
	swap	d0                              ; quotient low word
	move.w	d3,d0                           ; into d0
	swap	d3                              ; remainder
	move.b	ultoa_digits(pc,d3.w),-(a1)     ; its digit, from the right
	addq.w	#1,d2                           ; count it
	tst.l	d0                              ; until the quotient is zero
	bne.s	ultoa_divide_long
	move.w	(sp)+,d4                        ; restore d4
ultoa_copy:
	move.b	(a1)+,(a0)+                     ; copy the digits
	dbra	d2,ultoa_copy                   ; to the buffer
ultoa_terminate:
	clr.b	(a0)+                           ; terminate
	adda.w	#$22,sp                         ; drop the digit buffer
	movea.l	(sp)+,a0                        ; return the buffer
	move.l	(sp)+,d3
	rts
ultoa_bad_radix:
	move.w	#$21,errno                      ; errno = EDOM
	bra.s	ultoa_terminate                 ; empty string

;------------------------------------------------------------------------------
; Digits for ultoa.
;------------------------------------------------------------------------------
ultoa_digits:	; from: ultoa
	dc.b	'0123456789abcdefghijklmnopqrstuvwxyz'

;------------------------------------------------------------------------------
; free_block_lists: Mfrees every block on block_list and other_block_list (each block
; links to the next by its first long).  Called on exit.  Changes d0-d2/a0-a1.
;------------------------------------------------------------------------------
free_block_lists:	; from: exit
	move.l	a3,-(sp)                        ; save a3
	movea.l	block_list(pc),a3               ; first block of block_list
free_block_list_loop:
	move.l	a3,d0                           ; any left?
	beq.s	free_other_block_list           ; no
	move.l	a3,-(sp)                        ; block to free
	movea.l	(a3),a3                         ; next block
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.w	#6,sp                           ; pop the arguments
	bra.s	free_block_list_loop
free_other_block_list:
	movea.l	other_block_list(pc),a3         ; first block of other_block_list
free_other_block_list_loop:
	move.l	a3,d0                           ; any left?
	beq.s	free_block_lists_done           ; no
	move.l	a3,-(sp)                        ; block to free
	movea.l	(a3),a3                         ; next block
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.w	#6,sp                           ; pop the arguments
	bra.s	free_other_block_list_loop
free_block_lists_done:
	movea.l	(sp)+,a3
	rts

;------------------------------------------------------------------------------
; memcpy: copies d0 bytes from a1 to a0; overlapping areas copy correctly (backwards when
; the destination is above).  When both are even or both odd it copies 512-byte blocks
; with movem (40 bytes each), then longs, then bytes; otherwise byte by byte.
; Returns a0.  Changes d0-d2/a1.
;------------------------------------------------------------------------------
memcpy:	; from: unpack_and_save
	tst.l	d0                              ; nothing to copy?
	beq.w	memcpy_return
	move.l	a0,-(sp)                        ; keep the destination
	cmpa.l	a0,a1                           ; destination below the source?
	bhi.w	memcpy_forward                  ; yes: copy forward
	beq.w	memcpy_done                     ; same place: nothing to do
	adda.l	d0,a1                           ; source end
	adda.l	d0,a0                           ; destination end
	move.w	a1,d1                           ; source address
	move.w	a0,d2                           ; destination address
	btst	#$0,d1                          ; source end odd?
	beq.s	memcpy_back_even                ; no
	btst	#$0,d2                          ; destination end odd too?
	bne.s	memcpy_back_align               ; yes: align
memcpy_back_bytes:
	move.b	-(a1),-(a0)                     ; copy a byte backwards
	subq.l	#1,d0                           ; count
	bne.s	memcpy_back_bytes               ; until done
	bra.w	memcpy_done
memcpy_back_even:
	btst	#$0,d2                          ; destination end odd?
	bne.s	memcpy_back_bytes               ; mixed: byte by byte
	bra.s	memcpy_back_blocks              ; both even
memcpy_back_align:
	move.b	-(a1),-(a0)                     ; one byte to make both even
	subq.l	#1,d0                           ; count
	beq.w	memcpy_done                     ; it was the only one
memcpy_back_blocks:
	move.l	d0,d1                           ; count
	lsr.l	#5,d1                           ; / 512:
	lsr.l	#4,d1                           ; blocks of 512 bytes
	beq.w	memcpy_back_longs               ; none
	movem.l	d2-d7/a3-a6,-(sp)               ; save the movem registers
memcpy_back_block_loop:
	movem.l	-$28(a1),d2-d7/a3-a6            ; 40 bytes at a time, 512 in all
	movem.l	d2-d7/a3-a6,-(a0)               ; down to the destination
	movem.l	-$50(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$78(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$a0(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$c8(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$f0(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$118(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$140(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$168(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$190(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$1b8(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$1e0(a1),d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,-(a0)
	movem.l	-$200(a1),d2-d7/a3-a4           ; last 32 bytes of the block
	movem.l	d2-d7/a3-a4,-(a0)
	suba.w	#$200,a1                        ; source down 512
	subq.l	#1,d1                           ; next block
	bne.w	memcpy_back_block_loop
	movem.l	(sp)+,d2-d7/a3-a6               ; restore the registers
memcpy_back_longs:
	move.w	d0,d1                           ; count
	andi.w	#$1ff,d0                        ; below 512
	lsr.w	#2,d0                           ; in longs
	beq.s	memcpy_back_tail                ; none
	subq.w	#1,d0                           ; dbra count
memcpy_back_long_loop:
	move.l	-(a1),-(a0)                     ; copy a long backwards
	dbra	d0,memcpy_back_long_loop        ; for each long
memcpy_back_tail:
	andi.w	#$3,d1                          ; bytes left, 0-3
	beq.w	memcpy_done                     ; none
	subq.w	#1,d1                           ; dbra count
memcpy_back_byte_loop:
	move.b	-(a1),-(a0)                     ; copy a byte backwards
	dbra	d1,memcpy_back_byte_loop        ; for each byte
	bra.w	memcpy_done
memcpy_forward:
	move.w	a1,d1                           ; source address
	move.w	a0,d2                           ; destination address
	btst	#$0,d1                          ; source odd?
	beq.s	memcpy_even                     ; no
	btst	#$0,d2                          ; destination odd too?
	bne.s	memcpy_align                    ; yes: align
memcpy_bytes:
	move.b	(a1)+,(a0)+                     ; copy a byte
	subq.l	#1,d0                           ; count
	bne.s	memcpy_bytes                    ; until done
	bra.w	memcpy_done
memcpy_even:
	btst	#$0,d2                          ; destination odd?
	bne.s	memcpy_bytes                    ; mixed: byte by byte
	bra.s	memcpy_blocks                   ; both even
memcpy_align:
	move.b	(a1)+,(a0)+                     ; one byte to make both even
	subq.l	#1,d0                           ; count
memcpy_blocks:
	move.l	d0,d1                           ; count
	lsr.l	#5,d1                           ; / 512:
	lsr.l	#4,d1                           ; blocks of 512 bytes
	beq.w	memcpy_longs                    ; none
	movem.l	d2-d7/a3-a6,-(sp)               ; save the movem registers
memcpy_block_loop:
	movem.l	(a1)+,d2-d7/a3-a6               ; 40 bytes at a time, 512 in all
	movem.l	d2-d7/a3-a6,(a0)                ; to the destination
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$28(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$50(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$78(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$a0(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$c8(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$f0(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$118(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$140(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$168(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$190(a0)
	movem.l	(a1)+,d2-d7/a3-a6
	movem.l	d2-d7/a3-a6,$1b8(a0)
	movem.l	(a1)+,d2-d7/a3-a4               ; last 32 bytes of the block
	movem.l	d2-d7/a3-a4,$1e0(a0)
	adda.w	#$200,a0                        ; destination up 512
	subq.l	#1,d1                           ; next block
	bne.w	memcpy_block_loop
	movem.l	(sp)+,d2-d7/a3-a6               ; restore the registers
memcpy_longs:
	move.w	d0,d1                           ; count
	andi.w	#$1ff,d0                        ; below 512
	lsr.w	#2,d0                           ; in longs
	beq.s	memcpy_tail                     ; none
	subq.w	#1,d0                           ; dbra count
memcpy_long_loop:
	move.l	(a1)+,(a0)+                     ; copy a long
	dbra	d0,memcpy_long_loop             ; for each long
memcpy_tail:
	andi.w	#$3,d1                          ; bytes left, 0-3
	beq.s	memcpy_done                     ; none
	subq.w	#1,d1                           ; dbra count
memcpy_byte_loop:
	move.b	(a1)+,(a0)+                     ; copy a byte
	dbra	d1,memcpy_byte_loop             ; for each byte
memcpy_done:
	movea.l	(sp)+,a0                        ; return the destination
memcpy_return:
	rts

;------------------------------------------------------------------------------
; ctype_table: class of each of the 256 characters: bit 7 white space, 6 control,
; 5 letter, 4 letter or digit, 3 upper case, 2 lower case, 1 hex digit, 0 punctuation.
;------------------------------------------------------------------------------
ctype_table:	; from: strtoul
	dc.b	'@@@@@@@@@'                     ; chars 0-8: control
	dc.b	$c0,$c0,$c0,$c0,$c0             ; 9-13 tab to cr: control, white space
	dc.b	'@@@@@@@@@@@@@@@@@@'            ; 14-31: control
	dc.w	$8001,$0101,$0101,$0101,$0101,$0101,$0101,$0101 ; 32 space, 33-47 punctuation
	dc.w	$1212,$1212,$1212,$1212,$1212,$0101,$0101,$0101 ; 48-57 digits, 58-63 punctuation
	dc.b	$00                             ; 64 @: none
	dc.b	'::::::88888888888888888888'    ; 65-90 A-Z, A-F also hex
	dc.b	$01,$01,$01,$01,$01,$01         ; 91-96 punctuation
	dc.b	'66666644444444444444444444'    ; 97-122 a-z, a-f also hex
	dc.b	$01,$01,$01,$01,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 123-126 punctuation, 127 control,
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 128-255: none
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	dc.b	$00,$00,$00,$00,$00

;------------------------------------------------------------------------------
; digit_table: value of each character as a digit (0-9, a-z and A-Z = 10-35), $ff for none.
;------------------------------------------------------------------------------
digit_table:	; from: strtoul
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff ; chars 0-47: no digit
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$0001,$0203,$0405,$0607,$0809,$ffff,$ffff,$ffff ; 0-9
	dc.w	$ff0a,$0b0c,$0d0e,$0f10,$1112,$1314,$1516,$1718 ; A-O = 10-24
	dc.w	$191a,$1b1c,$1d1e,$1f20,$2122,$23ff,$ffff,$ffff ; P-Z = 25-35
	dc.w	$ff0a,$0b0c,$0d0e,$0f10,$1112,$1314,$1516,$1718 ; a-o = 10-24
	dc.w	$191a,$1b1c,$1d1e,$1f20,$2122,$23ff,$ffff,$ffff ; p-z = 25-35
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff ; chars 128-255: no digit
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff
	dc.w	$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff,$ffff

;------------------------------------------------------------------------------
; lmul: d0 = d0 * d1, signed 32-bit result.  Multiplies the magnitudes with two mulu
; (one operand under 16 bits) or one (both), then sets the sign.  Changes d0-d2/a0.
;------------------------------------------------------------------------------
lmul:	; from: init_gem
	move.l	d0,d2                           ; sign of the first
	bpl.s	lmul_sign                       ; positive
	neg.l	d0                              ; magnitude
lmul_sign:
	eor.l	d1,d2                           ; sign of the product
	movea.l	d2,a0                           ; kept in a0
	tst.l	d1                              ; second negative?
	bpl.s	lmul_magnitudes                 ; no
	neg.l	d1                              ; magnitude
lmul_magnitudes:
	move.l	d0,d2                           ; first
	swap	d2                              ; high word
	tst.w	d2                              ; set?
	bne.s	lmul_first_long                 ; yes
	move.l	d1,d2                           ; second
	swap	d2                              ; high word
	tst.w	d2                              ; set?
	bne.s	lmul_second_long                ; yes
	mulu.w	d1,d0                           ; both 16-bit: one mulu
	move.l	a0,d2                           ; sign
	bpl.s	lmul_short_done                 ; positive
	neg.l	d0                              ; negate
lmul_short_done:
	rts
lmul_second_long:
	mulu.w	d0,d2                           ; second high word * first low
	swap	d2                              ; to the high word
	mulu.w	d1,d0                           ; low words
	add.l	d2,d0                           ; sum
	move.l	a0,d2                           ; sign
	bpl.s	lmul_second_done                ; positive
	neg.l	d0                              ; negate
lmul_second_done:
	rts
lmul_first_long:
	mulu.w	d1,d2                           ; first high word * second low
	swap	d2                              ; to the high word
	mulu.w	d1,d0                           ; low words
	add.l	d2,d0                           ; sum
	move.l	a0,d2                           ; sign
	bpl.s	lmul_first_done                 ; positive
	neg.l	d0                              ; negate
lmul_first_done:
	rts

;------------------------------------------------------------------------------
; GEMDOS and XBIOS bindings.  They save a2, which the traps may change, and return the
; trap result in d0.
; Fread: d0 = handle, d1 = count, a0 = buffer.
;------------------------------------------------------------------------------
Fread:	; from: load_and_unpack
	movem.l	d0-d1/a0/a2,-(sp)               ; push handle, count, buffer, a2
	move.w	#$3f,(sp)                       ; Fread over the high word of d0
	trap	#1                              ; GEMDOS
	lea	$c(sp),sp                       ; pop the arguments
	movea.l	(sp)+,a2                        ; restore a2
	rts

;------------------------------------------------------------------------------
; Fsetdta: a0 = DTA.
;------------------------------------------------------------------------------
Fsetdta:	; from: init_paths
	move.l	a2,-(sp)                        ; save a2
	move.l	a0,-(sp)                        ; DTA
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.w	#6,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Dgetdrv: returns the current drive in d0.
;------------------------------------------------------------------------------
Dgetdrv:	; from: init_paths
	move.l	a2,-(sp)                        ; save a2
	move.w	#$19,-(sp)
	trap	#1                              ; Dgetdrv
	addq.w	#2,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Fclose: d0 = handle.
;------------------------------------------------------------------------------
Fclose:	; from: load_and_unpack, unpack_and_save, main
	move.l	a2,-(sp)                        ; save a2
	move.w	d0,-(sp)                        ; handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.w	#4,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Malloc: d0 = size (-1 asks for the largest free block).  Returns the block in d0 and a0.
;------------------------------------------------------------------------------
Malloc:	; from: load_and_unpack, unpack_and_save
	move.l	a2,-(sp)                        ; save a2
	move.l	d0,-(sp)                        ; size
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.w	#6,sp                           ; pop the arguments
	movea.l	d0,a0                           ; block also in a0
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Fdelete: a0 = name.
;------------------------------------------------------------------------------
Fdelete:	; from: unpack_and_save
	move.l	a2,-(sp)                        ; save a2
	move.l	a0,-(sp)                        ; name
	move.w	#$41,-(sp)
	trap	#1                              ; Fdelete
	addq.w	#6,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Fwrite: d0 = handle, d1 = count, a0 = buffer.
;------------------------------------------------------------------------------
Fwrite:	; from: unpack_and_save, main
	movem.l	d0-d1/a0/a2,-(sp)               ; push handle, count, buffer, a2
	move.w	#$40,(sp)                       ; Fwrite over the high word of d0
	trap	#1                              ; GEMDOS
	lea	$c(sp),sp                       ; pop the arguments
	movea.l	(sp)+,a2                        ; restore a2
	rts

;------------------------------------------------------------------------------
; Dgetpath: a0 = buffer, d0 = drive (0 current).
;------------------------------------------------------------------------------
Dgetpath:	; from: init_paths
	move.l	a2,-(sp)                        ; save a2
	move.w	d0,-(sp)                        ; drive
	move.l	a0,-(sp)                        ; buffer
	move.w	#$47,-(sp)
	trap	#1                              ; Dgetpath
	addq.w	#8,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Fcreate: a0 = name, d0 = attributes.  Returns the handle in d0.
;------------------------------------------------------------------------------
Fcreate:	; from: unpack_and_save
	move.l	a2,-(sp)                        ; save a2
	move.w	d0,-(sp)                        ; attributes
	move.l	a0,-(sp)                        ; name
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.w	#8,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Fopen: a0 = name, d0 = mode.  Returns the handle in d0.
;------------------------------------------------------------------------------
Fopen:	; from: unpack_and_save, main
	move.l	a2,-(sp)                        ; save a2
	move.w	d0,-(sp)                        ; mode
	move.l	a0,-(sp)                        ; name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.w	#8,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Fseek: d0 = offset, d1 = handle, d2 = mode.
;------------------------------------------------------------------------------
Fseek:	; from: main
	move.l	a2,-(sp)                        ; save a2
	move.w	d2,-(sp)                        ; mode
	move.w	d1,-(sp)                        ; handle
	move.l	d0,-(sp)                        ; offset
	move.w	#$42,-(sp)
	trap	#1                              ; Fseek
	lea	$a(sp),sp                       ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Mfree: a0 = block.
;------------------------------------------------------------------------------
Mfree:	; from: load_and_unpack, unpack_and_save
	move.l	a2,-(sp)                        ; save a2
	move.l	a0,-(sp)                        ; block
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.w	#6,sp                           ; pop the arguments
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; Pexec: d0 = mode, a0 = file name, a1 = command line, 4(sp) = environment.
;------------------------------------------------------------------------------
Pexec:	; from: load_and_unpack
	move.l	a2,-(sp)                        ; save a2
	move.l	8(sp),-(sp)                     ; environment
	movem.l	d0/a0-a1,-(sp)                  ; mode, name, command line
	move.w	#$4b,(sp)                       ; Pexec over the high word of d0
	trap	#1                              ; GEMDOS
	lea	$10(sp),sp                      ; pop the arguments
	movea.l	(sp)+,a2                        ; restore a2
	rts

;------------------------------------------------------------------------------
; Logbase: returns the logical screen address in d0 and a0.
;------------------------------------------------------------------------------
Logbase:	; from: unpack_and_save
	move.l	a2,-(sp)                        ; save a2
	move.w	#$3,-(sp)
	trap	#14                             ; Logbase
	addq.w	#2,sp                           ; pop the arguments
	movea.l	d0,a0                           ; address also in a0
	movea.l	(sp)+,a2
	rts

;------------------------------------------------------------------------------
; VDI bindings.  They share contrl and intout with the AES, with their own intin, ptsin
; and ptsout.
; v_clsvwk: d0 = handle of the virtual workstation to close.
;------------------------------------------------------------------------------
v_clsvwk:	; from: init_gem
	lea	contrl,a0                       ; the VDI control array
	clr.w	2(a0)                           ; no ptsin
	clr.w	6(a0)                           ; no intin
	moveq	#101,d1                         ; opcode 101: v_clsvwk
	bra.s	vdi                             ; call the VDI

;------------------------------------------------------------------------------
; v_opnvwk: a0 = work_in (11 words), a1 = pointer to the handle (the physical handle in,
; the new one out), 4(sp) = work_out (57 words: intout then ptsout).
; Changes d0-d2/a0-a1.
;------------------------------------------------------------------------------
v_opnvwk:	; from: init_gem
	move.w	(a1),contrl+12                  ; contrl[6] = physical handle
	move.l	a1,-(sp)                        ; keep the handle pointer
	lea	contrl,a1                       ; the VDI control array
	move.w	#$64,(a1)                       ; opcode 100: v_opnvwk
	clr.w	2(a1)                           ; no ptsin
	move.w	#$b,6(a1)                       ; 11 intin
	lea	$be(a1),a1                      ; intin
	moveq	#10,d0                          ; 11 words
v_opnvwk_copy_work_in:
	move.w	(a0)+,(a1)+                     ; copy work_in
	dbra	d0,v_opnvwk_copy_work_in
	move.l	#vdi_pb,d1                      ; parameter block
	moveq	#115,d0                         ; VDI
	move.l	a2,-(sp)                        ; save a2
	trap	#2                              ; AES/VDI
	movea.l	(sp)+,a2                        ; restore a2
	movea.l	(sp)+,a0                        ; handle pointer
	move.w	contrl+12,(a0)                  ; new handle
	lea	intout,a0                       ; returned values
	movea.l	4(sp),a1                        ; work_out
	moveq	#44,d0                          ; 45 words
v_opnvwk_copy_intout:
	move.w	(a0)+,(a1)+                     ; copy intout
	dbra	d0,v_opnvwk_copy_intout
	lea	ptsout,a0                       ; returned points
	moveq	#11,d0                          ; 12 words
v_opnvwk_copy_ptsout:
	move.w	(a0)+,(a1)+                     ; copy ptsout after it
	dbra	d0,v_opnvwk_copy_ptsout
	rts

;------------------------------------------------------------------------------
; VDI parameter block: contrl, intin, ptsin, intout, ptsout.
;------------------------------------------------------------------------------
vdi_pb:	; from: v_opnvwk
	dc.l	contrl
	dc.l	intin
	dc.l	ptsin
	dc.l	intout
	dc.l	ptsout

;------------------------------------------------------------------------------
; vdi: VDI call with no parameters, through vdi_pb_copy.
; a0 = contrl, d0 = handle, d1 = opcode.  Returns intout[0] in d0.
;------------------------------------------------------------------------------
vdi:	; from: v_clsvwk
	move.l	a2,-(sp)                        ; save a2
	move.w	d0,$c(a0)                       ; contrl[6] = handle
	move.w	d1,(a0)                         ; contrl[0] = opcode
	move.l	#vdi_pb_copy,d1                 ; parameter block
	moveq	#115,d0                         ; VDI
	trap	#2                              ; AES/VDI
	lea	intout,a0                       ; results
	move.w	(a0)+,d0                        ; d0 = intout[0]
	movea.l	(sp)+,a2                        ; restore a2
	rts

;------------------------------------------------------------------------------
; AES bindings: the parameters go into intin / addrin, d0 is the function number for aes.
; They return intout[0] in d0 and change d0-d2/a0-a1.
; appl_init: returns the application id in d0.
;------------------------------------------------------------------------------
appl_init:	; from: init_gem
	moveq	#10,d0                          ; function 10
	bra.w	aes

;------------------------------------------------------------------------------
; appl_exit.
;------------------------------------------------------------------------------
appl_exit:	; from: init_gem, close_gem
	moveq	#19,d0                          ; function 19
	bra.w	aes

;------------------------------------------------------------------------------
; objc_draw: a0 = tree, d0 = start object, d1 = depth, d2 = clip x, 4/6/8(sp) = clip y,
; w, h.
;------------------------------------------------------------------------------
objc_draw:	; from: draw_tree
	move.l	a0,addrin                       ; addrin[0] = tree
	lea	intin,a0                        ; integer parameters
	move.w	d0,(a0)+                        ; start object
	move.w	d1,(a0)+                        ; depth
	move.w	d2,(a0)+                        ; clip x
	move.w	4(sp),(a0)+                     ; clip y
	move.w	6(sp),(a0)+                     ; clip w
	move.w	8(sp),(a0)+                     ; clip h
	moveq	#42,d0                          ; function 42
	bra.w	aes

;------------------------------------------------------------------------------
; form_do: a0 = tree, d0 = start edit object.  Returns the exit object in d0.
;------------------------------------------------------------------------------
form_do:	; from: main
	move.l	a0,addrin                       ; addrin[0] = tree
	move.w	d0,intin                        ; intin[0] = start object
	moveq	#50,d0                          ; function 50
	bra.w	aes

;------------------------------------------------------------------------------
; form_dial: d0 = flag, d1/d2 = little x/y, 4-$e(sp) = little w, h, big x, y, w, h.
;------------------------------------------------------------------------------
form_dial:	; from: form_dial_tree
	move.l	a0,addrin                       ; addrin[0] (not used by form_dial)
	lea	intin,a0                        ; integer parameters
	move.w	d0,(a0)+                        ; flag
	move.w	d1,(a0)+                        ; little x
	move.w	d2,(a0)+                        ; little y
	move.w	4(sp),(a0)+                     ; little w
	move.w	6(sp),(a0)+                     ; little h
	move.w	8(sp),(a0)+                     ; big x
	move.w	$a(sp),(a0)+                    ; big y
	move.w	$c(sp),(a0)+                    ; big w
	move.w	$e(sp),(a0)                     ; big h
	moveq	#51,d0                          ; function 51
	bra.w	aes

;------------------------------------------------------------------------------
; form_center: a0 = tree, a1 = &x, 4/8/$c(sp) = &y, &w, &h.
;------------------------------------------------------------------------------
form_center:	; from: init_gem
	move.l	a1,-(sp)                        ; keep &x
	move.l	a0,addrin                       ; addrin[0] = tree
	moveq	#54,d0                          ; function 54
	bsr.w	aes                             ; call the AES
	movea.l	(sp)+,a1                        ; &x
	move.w	(a0)+,(a1)                      ; x = intout[1]
	movea.l	4(sp),a1                        ; &y
	move.w	(a0)+,(a1)                      ; y = intout[2]
	movea.l	8(sp),a1                        ; &w
	move.w	(a0)+,(a1)                      ; w = intout[3]
	movea.l	$c(sp),a1                       ; &h
	move.w	(a0)+,(a1)                      ; h = intout[4]
	rts

;------------------------------------------------------------------------------
; form_alert: d0 = default button, a0 = alert string.  Returns the button in d0.
;------------------------------------------------------------------------------
form_alert:	; from: load_and_unpack, select_file, init_gem, unpack_and_save, main
	move.l	a0,addrin                       ; addrin[0] = alert string
	move.w	d0,intin                        ; intin[0] = default button
	moveq	#52,d0                          ; function 52
	bra.s	aes

;------------------------------------------------------------------------------
; rsrc_free.
;------------------------------------------------------------------------------
rsrc_free:	; from: close_gem
	moveq	#111,d0                         ; function 111
	bra.s	aes

;------------------------------------------------------------------------------
; rsrc_obfix: a0 = tree, d0 = object.
;------------------------------------------------------------------------------
rsrc_obfix:	; from: init_gem
	move.l	a0,addrin                       ; addrin[0] = tree
	move.w	d0,intin                        ; intin[0] = object
	moveq	#114,d0                         ; function 114
	bra.s	aes

;------------------------------------------------------------------------------
; graf_mouse: d0 = form number, a0 = user form.
;------------------------------------------------------------------------------
graf_mouse:	; from: init_gem
	move.l	a0,addrin                       ; addrin[0] = user form
	move.w	d0,intin                        ; intin[0] = form number
	moveq	#78,d0                          ; function 78
	bra.s	aes

;------------------------------------------------------------------------------
; wind_update: d0 = mode.
;------------------------------------------------------------------------------
wind_update:	; from: main
	move.w	d0,intin                        ; intin[0] = mode
	moveq	#107,d0                         ; function 107
	bra.s	aes

;------------------------------------------------------------------------------
; fsel_input: a0 = path, a1 = file name, 4(sp) = &button.
;------------------------------------------------------------------------------
fsel_input:	; from: select_file
	move.l	a0,addrin                       ; addrin[0] = path
	move.l	a1,addrin+4                     ; addrin[1] = file name
	moveq	#90,d0                          ; function 90
	bsr.s	aes                             ; call the AES
	movea.l	4(sp),a1                        ; &button
	move.w	(a0),(a1)                       ; button = intout[1]
	rts

;------------------------------------------------------------------------------
; fsel_exinput: a0 = path, a1 = file name, 4(sp) = &button, 8(sp) = title.
;------------------------------------------------------------------------------
fsel_exinput:	; from: select_file
	move.l	a0,addrin                       ; addrin[0] = path
	move.l	a1,addrin+4                     ; addrin[1] = file name
	move.l	8(sp),addrin+8                  ; addrin[2] = title
	moveq	#91,d0                          ; function 91
	bsr.s	aes                             ; call the AES
	movea.l	4(sp),a1                        ; &button
	move.w	(a0),(a1)                       ; button = intout[1]
	rts

;------------------------------------------------------------------------------
; aes: AES call; d0 is the function, its contrl counts come from aes_ctrl_table.
; Returns intout[0] in d0 and a0 = intout + 2.  Changes d0-d1/a0-a1.
;------------------------------------------------------------------------------
aes:	; from: appl_init, appl_exit, objc_draw, form_do, form_dial, form_center, 7 more
	move.l	a2,-(sp)                        ; save a2
	move.w	d0,contrl                       ; contrl[0] = function
	add.w	d0,d0                           ; * 4
	add.w	d0,d0
	lea	aes_ctrl_table-40(pc,d0.w),a0   ; its 4 counts (table from 10)
	lea	contrl+2,a1                     ; contrl[1]
	clr.w	d0                              ; byte to word
	move.b	(a0)+,d0                        ; contrl[1] = int_in count
	move.w	d0,(a1)+
	move.b	(a0)+,d0                        ; contrl[2] = int_out count
	move.w	d0,(a1)+
	move.b	(a0)+,d0                        ; contrl[3] = addr_in count
	move.w	d0,(a1)+
	move.b	(a0)+,d0                        ; contrl[4] = addr_out count
	move.w	d0,(a1)+
	move.w	#$c8,d0                         ; AES
	move.l	#aes_pb,d1                      ; parameter block
	trap	#2                              ; AES/VDI
	lea	intout,a0                       ; results
	move.w	(a0)+,d0                        ; d0 = intout[0]
	movea.l	(sp)+,a2                        ; restore a2
	rts

;------------------------------------------------------------------------------
; AES parameter block: contrl, global, intin, intout, addrin, addrout.
;------------------------------------------------------------------------------
aes_pb:	; from: aes
	dc.l	contrl
	dc.l	aes_global
	dc.l	intin
	dc.l	intout
	dc.l	addrin
	dc.l	addrout

;------------------------------------------------------------------------------
; contrl[1..4] of each AES function from 10: int_in, int_out, addr_in, addr_out.
; Each line holds four functions; - marks an unused entry.
;------------------------------------------------------------------------------
aes_ctrl_table:
	dc.b	$00,$01,$00,$00,$02,$01,$01,$00,$02,$01,$01,$00,$00,$01,$01,$00 ; 10: appl_init/read/write/find
	dc.b	$02,$01,$01,$00,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 14: appl_tplay/trecord/-/-
	dc.b	$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$03,$05,$00,$00 ; 18: -/appl_exit/evnt_keybd/button
	dc.b	$05,$05,$00,$00,$00,$01,$01,$00,$02,$01,$00,$00,$10,$07,$01,$00 ; 22: evnt_mouse/mesag/timer/multi
	dc.b	$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 26: evnt_dclick/-/-/-
	dc.b	$01,$01,$01,$00,$02,$01,$01,$00,$02,$01,$01,$00,$02,$01,$01,$00 ; 30: menu_bar/icheck/ienable/tnormal
	dc.b	$01,$01,$02,$00,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 34: menu_text/register/-/-
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$00,$01,$01,$01,$00 ; 38: -/-/objc_add/delete
	dc.b	$06,$01,$01,$00,$04,$01,$01,$00,$01,$03,$01,$00,$02,$01,$01,$00 ; 42: objc_draw/find/offset/order
	dc.b	$04,$02,$01,$00,$08,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 46: objc_edit/change/-/-
	dc.b	$01,$01,$01,$00,$09,$01,$01,$00,$01,$01,$01,$00,$01,$01,$00,$00 ; 50: form_do/dial/alert/error
	dc.b	$00,$05,$01,$00,$03,$03,$01,$00,$02,$02,$01,$00,$00,$00,$00,$00 ; 54: form_center/keybd/button/-
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 58-61: none
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 62-65: none
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 66-69: none
	dc.b	$04,$03,$00,$00,$08,$03,$00,$00,$06,$01,$00,$00,$08,$01,$00,$00 ; 70: graf_rubber/drag/move/growbox
	dc.b	$08,$01,$00,$00,$04,$01,$01,$00,$03,$01,$01,$00,$00,$05,$00,$00 ; 74: graf_shrink/watch/slidebox/handle
	dc.b	$01,$01,$01,$00,$00,$05,$00,$00,$00,$01,$01,$00,$00,$01,$01,$00 ; 78: graf_mouse/mkstate/scrp_read/write
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 82-85: none
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 86-89: none
	dc.b	$00,$02,$02,$00,$00,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 90: fsel_input/exinput/-/-
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 94-97: none
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$05,$01,$00,$00,$05,$01,$00,$00 ; 98: -/-/wind_create/open
	dc.b	$01,$01,$00,$00,$01,$01,$00,$00,$02,$05,$00,$00,$06,$01,$00,$00 ; 102: wind_close/delete/get/set
	dc.b	$02,$01,$00,$00,$01,$01,$00,$00,$06,$05,$00,$00,$00,$00,$00,$00 ; 106: wind_find/update/calc/-
	dc.b	$00,$01,$01,$00,$00,$01,$00,$00,$02,$01,$00,$01,$02,$01,$01,$00 ; 110: rsrc_load/free/gaddr/saddr
	dc.b	$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; 114: rsrc_obfix/-/-/-
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$03,$01,$02,$00 ; 118: -/-/shel_read/write
	dc.b	$01,$01,$01,$00,$01,$01,$01,$00,$00,$01,$01,$00,$00,$01,$03,$00 ; 122: shel_get/put/find/envrn

	section	data

;------------------------------------------------------------------------------
; Turbo C library: errno, $21 EDOM or $22 ERANGE.
;------------------------------------------------------------------------------
errno:	; from: fp_raise, itoa, strtoul, ultoa
	dc.w	$0000

;------------------------------------------------------------------------------
; Turbo C's exit routines, called by exit when set.
;------------------------------------------------------------------------------
exit_routine:	; from: exit
	dc.w	$0000,$0000
cleanup_routine:	; from: exit
	dc.w	$0000,$0000
progress_open:	; from: open_progress, close_progress
	dc.w	$0000
has_fsel_exinput:	; from: select_file, init_gem
	dc.w	$0000
program_loaded:	; from: load_and_unpack, unpack_and_save
	dc.w	$0000

;------------------------------------------------------------------------------
; What the patched Physbase and Logbase calls return.
;------------------------------------------------------------------------------
packer_screen_ptr:	; from: run_packed_program, screen_call_patch
	dc.l	packer_screen

;------------------------------------------------------------------------------
; v_opnvwk's work_in: 1 for everything, then raster coordinates (2).
;------------------------------------------------------------------------------
vdi_work_in:	; from: init_gem
	dc.w	$0001,$0001,$0001,$0001,$0001,$0001,$0001,$0001
	dc.w	$0001,$0001,$0002

;------------------------------------------------------------------------------
; Texts of the progress box.
;------------------------------------------------------------------------------
str_file:	; from: show_reading, show_writing, load_and_unpack, unpack_and_save, main
	dc.b	'File: '
str_empty:	; from: show_reading
	dc.b	$00
str_reading:	; from: show_reading
	dc.b	' reading...',0
str_checking:	; from: show_checking
	dc.b	'checking...',0
str_size:	; from: show_checking
	dc.b	'Size: ',0
str_bytes:	; from: show_checking
	dc.b	' bytes',0
str_unpacking:	; from: show_unpacking
	dc.b	'unpacking...',0
str_writing:
	dc.b	' writing...',0

;------------------------------------------------------------------------------
; Alerts and file selector titles.
;------------------------------------------------------------------------------
alert_not_executable:
	dc.b	'[3][ The file you selected is not | executable! ][  LAMER  ]',0
alert_symbol_table:
	dc.b	'[3][ The selected program contains a | symbol table, which is no'
	dc.b	't | typical for packed programs! ][FORGET IT]',0
alert_no_memory:
	dc.b	'[3][ You have far too little | memory available... ][  SORRY  ]',0
alert_too_big:
	dc.b	'[3][ Unpacking this program would | require %ld bytes of RAM, | '
	dc.b	'while you only have %ld | available... ][  SORRY  ]',0
alert_not_packed:
	dc.b	'[2][ This program file contains   | relocation info, but wasn',$27
	dc.b	't  | packed with a known packer.  | It',$27
	dc.b	's probably not packed! ][  GO ON  | CANCEL ]',0
alert_cannot_unpack:
	dc.b	'[1][ Sorry, I couldn',$27,'t unpack | this program... ][  GOSH  ]',0
alert_statistics:
	dc.b	'[1][   Packed size: %ld bytes | Unpacked size: %ld bytes |     C'
	dc.b	'R: %.2f%c |   Time: %.2f sec. ][  GOSH  ]',0
	dc.b	$00

;------------------------------------------------------------------------------
; Doubles for the statistics, in the 10-byte extended format: 200, the clock's ticks a second, and 100.
;------------------------------------------------------------------------------
ticks_per_second:
	dc.w	$4006,$c800,$0000,$0000,$0000
hundred_percent:
	dc.w	$4005,$c800,$0000,$0000,$0000
alert_fsel_error:	; from: select_file
	dc.b	'[3][ | Error during fsel_input()! ][  UH OH  ]',0
alert_appl_init:	; from: init_gem
	dc.b	'[3][ | Can',$27,'t appl_init() !!! ][  GULP  ]',0
str_backslash:	; from: init_paths
	dc.b	'\',0
str_prg_mask:	; from: init_paths
	dc.b	'*.PRG',0
str_all_mask:
	dc.b	'*.*',0
str_choose_input:
	dc.b	'Choose a file to unpack:',0
alert_file_not_found:
	dc.b	'[3][ | File not found! Try again. ][  HMMM  ]',0
alert_no_screen_memory:
	dc.b	'[3][ | Insufficient memory for | screen-saving! ][  UGH  ]',0
str_choose_output:
	dc.b	'Choose a name for the new file:',0
alert_overwrite:
	dc.b	'[3][ | Overwrite existing file | %s ? ][  YES  |  NO  ]',0
alert_write_error:
	dc.b	'[3][ | Write error! Choose another | path or cancel! ][  OK  ]',0
str_naughty_prg:
	dc.b	'NAUGHTY.PRG',0
str_locate_naughty:
	dc.b	'Please locate NAUGHTY.PRG:',0
alert_naughty_not_found:
	dc.b	'[3][ | File not found! ][Retry|Cancel]',0
alert_setup_needs_original:
	dc.b	'[3][ | In order to save the setup, | the program file NAUGHTY.PR'
	dc.b	'G | must be unmodified! | (13320 bytes long!) ][  AHA  ]',0

;------------------------------------------------------------------------------
; Turbo C library: the floating point exception handlers (5 longs, none set), the 68881 and exception
; enable flags (bit 7 of fpu_flags: a 68881 is there), the rounding mode and sticky exception flags,
; two lists of Malloc blocks that exit frees (nothing in this program fills them), and the VDI
; parameter block.
;------------------------------------------------------------------------------
fp_exception_handlers:	; from: fp_raise
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$0000
fpu_flags:	; from: ext_log2, soft_log2, log, ext_log10, log1p, ext_log2p1, 12 more
	dc.b	$00
fpu_mode:	; from: soft_fadd, soft_fmul, soft_fdiv, fp_out_of_range, fp_raise
	dc.b	$00,$00,$00
block_list:	; from: free_block_lists
	dc.w	$0000,$0000
other_block_list:	; from: free_block_lists
	dc.w	$0000,$0000
vdi_pb_copy:	; from: vdi
	dc.l	contrl
	dc.l	intin
	dc.l	ptsin
	dc.l	intout
	dc.l	ptsout

	section	bss

;------------------------------------------------------------------------------
; Turbo C start-up.
;------------------------------------------------------------------------------
basepage:	ds.b	4
is_program:	ds.b	2
stack_limit:	ds.b	4
program_size:	ds.b	28

;------------------------------------------------------------------------------
; GEM.
;------------------------------------------------------------------------------
ap_id:	ds.b	2
tree_main_ptr:	ds.b	4
tree_info_ptr:	ds.b	4
tree_progress_ptr:	ds.b	4
tree_setup_ptr:	ds.b	4
progress_file_text:	ds.b	4
progress_size_text:	ds.b	4
progress_status_text:	ds.b	4
save_screen:	ds.b	2
show_statistics:	ds.b	2

;------------------------------------------------------------------------------
; Files and paths.
;------------------------------------------------------------------------------
file_handle:	ds.b	2
screen_size:	ds.b	4
dta:	ds.b	44
loaded_basepage:	ds.b	4
loaded_text:	ds.b	4
file_length:	ds.b	4
save_length:	ds.b	4
unpacked_header:	ds.b	4
unpacked_end:	ds.b	4
load_path:	ds.b	256
save_path:	ds.b	256
setup_path:	ds.b	256
load_name:	ds.b	64
save_name:	ds.b	64

;------------------------------------------------------------------------------
; 32768 bytes, probably one array with packer_screen, which is 32000 bytes into it.
;------------------------------------------------------------------------------
screen_buffer:	ds.b	32000

;------------------------------------------------------------------------------
; Where the packed program's screen calls are pointed.
;------------------------------------------------------------------------------
packer_screen:	ds.b	768

;------------------------------------------------------------------------------
; The loaded program's header.
;------------------------------------------------------------------------------
file_header:	ds.b	28

;------------------------------------------------------------------------------
; The Turbo C library's buffers and the AES and VDI arrays.
;------------------------------------------------------------------------------
ext_ecvt_buffer:	ds.b	22
ecvt_buffer:	ds.b	22
contrl:	ds.b	30
aes_global:	ds.b	160
intin:	ds.b	256
intout:	ds.b	90
ptsout:	ds.b	256
addrin:	ds.b	512
addrout:	ds.b	24
ptsin:	ds.b	4352
bss_end:

	end
