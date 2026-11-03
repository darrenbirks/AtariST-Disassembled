; GL.PRG  -  the GFA-BASIC linker of 3.02 D, 3.50 D, 3.51 D
;
; Devpac source of the linker, disassembled by Darren Birks, 3 November 2026.  Assembled, it gives GL.PRG byte
; for byte, relocations included:
;
;     vasmm68k_mot -devpac -m68000 -Ftos -o GL.PRG GL.S
;
; The linker joins the .O file the compiler wrote (G3OBJ) with the modules of the runtime library it needs
; (G3LIB, default GFA3BLIB, with its index GFA3BLIB.NDX) into the finished program (G3PRG, default TEST.PRG):
; it marks the modules the program's references need, following each module's own references, then copies the
; marked modules in index order behind the program's code and writes the relocation table.


	section	text

;------------------------------------------------------------------------------
; Program entry. Prints the title, then falls into scan_environment, which reads the options, links the program
; and terminates with the number of errors reported as the exit code.
;------------------------------------------------------------------------------
start:
	pea	title_message(pc)               ; the title
	move.w	#$9,-(sp)                       ; Cconws
	trap	#1                              ; Cconws
	addq.l	#6,sp                           ; drop the arguments
	bra.s	scan_environment                ; skip the title text
title_message:
	dc.b	13,'GFA-BASIC Linker 3.02 D',13,10,0
	dc.b	$00

;------------------------------------------------------------------------------
; Reads the options. Each environment string (basepage+$2c) has its first four characters packed into d0 and the
; next two into d1 (a marker bit in d0 says when four are in), then is compared with G3OBJ=, G3PRG=, G3LIB= and
; G3WAIT. For the first three a pointer to the value replaces the default (test.o, TEST.PRG, GFA3BLIB); G3WAIT=ON
; clears no_disk_prompt_flag (prompt for a disk before each file), G3WAIT=OFF sets it (the default).
; The library name and the object name go to their buffers, then the command tail (basepage+$80) is read:
;   -S         also write the symbol list into the program (other -x letters are ignored)
;   #          leave out the G3OBJ object file
;   +name      library name instead of G3LIB's
;   name       another object file, 'name.o', added to the list
; Then link_program, and Pterm with error_count.
;------------------------------------------------------------------------------
scan_environment:
	movea.l	start-$d4(pc),a0                ; a0 = basepage+$2c: the environment strings
.next_env_string:
	tst.b	(a0)                            ; an empty string ends the environment
	beq.w	.copy_names                     ; done: copy the names and read the command tail
	moveq	#0,d0                           ; d0 collects the name's first four characters
	moveq	#1,d1                           ; d1 = 1: a marker that moves up through d0
.pack_name_chars:
	rol.w	#8,d1                           ; previous character to d1's low byte
	asl.l	#8,d0                           ; shift d0 on; carry once the marker leaves bit 31
	bcs.s	.compare_env_name               ; marker out: d0 holds characters 1-4
	move.b	d1,d0                           ; add the previous character to d0
	move.b	(a0)+,d1                        ; d1 low byte = the next character
	bne.s	.pack_name_chars                ; until the string ends
	bra.s	.next_env_string                ; shorter than six characters: next string
.compare_env_name:
	move.b	d1,d0                           ; d0 = characters 1-4
	move.b	(a0)+,d1                        ; d1 = characters 5-6; a0 at character 7
	beq.s	.next_env_string                ; ends after six characters: next string
	cmpi.l	#$47334f42,d0                   ; 'G3OB'?
	bne.s	.check_g3prg                    ; no
	cmpi.w	#$4a3d,d1                       ; followed by 'J='?
	bne.s	.check_g3prg                    ; no
	move.l	a0,obj_name_pointer             ; G3OBJ=: the object file name
.check_g3prg:
	cmpi.l	#$47335052,d0                   ; 'G3PR'?
	bne.s	.check_g3lib                    ; no
	cmpi.w	#$473d,d1                       ; followed by 'G='?
	bne.s	.check_g3lib                    ; no
	move.l	a0,prg_name_pointer             ; G3PRG=: the program name
.check_g3lib:
	cmpi.l	#$47334c49,d0                   ; 'G3LI'?
	bne.s	.check_g3wait                   ; no
	cmpi.w	#$423d,d1                       ; followed by 'B='?
	bne.s	.check_g3wait                   ; no
	move.l	a0,lib_name_pointer             ; G3LIB=: the library name
.check_g3wait:
	cmpi.l	#$47335741,d0                   ; 'G3WA'?
	bne.s	.skip_env_string                ; no: skip this string
	cmpi.w	#$4954,d1                       ; followed by 'IT'?
	bne.s	.skip_env_string                ; no: skip this string
	lea	no_disk_prompt_flag(pc),a1      ; a1 = the disk prompt flag
	move.b	(a0)+,d2                        ; seventh character
	beq.s	.next_env_string                ; string ends: next string
	cmpi.b	#$3d,d2                         ; '='?
	bne.s	.skip_env_string                ; no: skip this string
	move.b	(a0)+,d2                        ; first character of the value
.next_if_zero:
	beq.s	.next_env_string                ; zero: next string
	andi.b	#$df,d2                         ; upper case
	cmpi.b	#$4f,d2                         ; 'O'?
	bne.s	.skip_env_string                ; no: skip this string
	move.b	(a0)+,d2                        ; second character
	beq.s	.next_if_zero                   ; string ends: next string
	andi.b	#$df,d2                         ; upper case
	cmpi.b	#$4e,d2                         ; 'N'?
	beq.s	.wait_on                        ; ON: prompt for disks
	cmpi.b	#$46,d2                         ; 'F'?
	bne.s	.skip_env_string                ; neither: flag unchanged
	st	(a1)                            ; OFF: no disk prompts
	bra.s	.skip_env_string                ; skip the rest of the string
.wait_on:
	sf	(a1)                            ; ON: prompt before each file
.skip_env_string:
	tst.b	(a0)+                           ; skip to the end of the string
	bne.s	.skip_env_string                ; until the zero
	bra.s	.next_if_zero                   ; Z still set from the zero: next string
.copy_names:
	clr.b	skip_first_object_flag          ; '#' not given
	clr.b	write_symbols_flag              ; -S not given
	lea	library_name(pc),a0             ; a0 = the library name buffer
	movea.l	lib_name_pointer(pc),a1         ; a1 = G3LIB's value or 'GFA3BLIB'
.copy_lib_name:
	move.b	(a1)+,(a0)+                     ; copy it
	bne.s	.copy_lib_name
	lea	object_name_list(pc),a2         ; a2 = the object name list
	movea.l	obj_name_pointer(pc),a1         ; a1 = G3OBJ's value or 'test.o'
.copy_obj_name:
	move.b	(a1)+,(a2)+                     ; copy it as the first name; a2 after its zero
	bne.s	.copy_obj_name
	lea	start-$80(pc),a0                ; a0 = basepage+$80: the command tail's length byte
	move.b	(a0),d0                         ; length
	beq.w	.arguments_done                 ; no command tail: start linking
	cmpi.b	#$60,d0                         ; length $60?
	bne.s	.commas_to_spaces               ; no: read the tail
	tst.b	1(a0)                           ; with an empty first character it counts as none (why unclear)
	beq.w	.arguments_done                 ; no arguments
.commas_to_spaces:
	move.b	(a0)+,d0                        ; next byte, starting with the length byte itself
	cmpi.b	#$2c,d0                         ; a comma?
	bne.s	.check_tail_end                 ; no
	moveq	#32,d0                          ; becomes a space
	move.b	d0,-(a0)                        ; stored back
.check_tail_end:
	cmpi.b	#$20,d0                         ; printable?
	bcc.s	.commas_to_spaces               ; until a control character (at once if length < 32)
	clr.b	-(a0)                           ; zero there, or over the length byte
	lea	start-$7f(pc),a0                ; a0 = the first character of the tail
.next_argument:
	move.b	(a0)+,d0                        ; next character
	beq.s	.arguments_done                 ; end of the tail: start linking
	cmpi.b	#$20,d0                         ; space?
	beq.s	.next_argument                  ; skip it
	cmpi.b	#$2d,d0                         ; '-'?
	bne.s	.check_hash                     ; no
	moveq	#-33,d0                         ; upper case mask
	and.b	(a0)+,d0                        ; option letter
	beq.s	.arguments_done                 ; '-' at the end: start linking
	cmpi.b	#$53,d0                         ; 'S'?
	bne.s	.check_word_end                 ; other letters are ignored
	st	write_symbols_flag              ; -S: write the symbol list into the program
.skip_option_word:
	move.b	(a0)+,d0                        ; skip the rest of the word
	beq.s	.arguments_done                 ; end of the tail: start linking
.check_word_end:
	cmpi.b	#$20,d0                         ; space ends the word
	bne.s	.skip_option_word               ; not yet
	bra.s	.next_argument                  ; next argument
.check_hash:
	cmpi.b	#$23,d0                         ; '#'?
	bne.s	.check_plus                     ; no
	st	skip_first_object_flag          ; '#': leave out the G3OBJ object file
	bra.s	.skip_option_word               ; skip the rest of the word
.check_plus:
	cmpi.b	#$2b,d0                         ; '+'?
	bne.s	.copy_obj_argument              ; no: an object file name
.skip_lib_spaces:
	move.b	(a0)+,d0                        ; skip spaces after the '+'
	beq.s	.arguments_done                 ; end of the tail: start linking
	cmpi.b	#$20,d0                         ; space?
	beq.s	.skip_lib_spaces                ; skip it
	lea	library_name(pc),a1             ; a1 = the library name buffer
.copy_lib_argument:
	move.b	d0,(a1)+                        ; copy the name over the G3LIB one
	move.b	(a0)+,d0                        ; next character
	beq.s	.end_lib_argument               ; end of the tail
	cmpi.b	#$20,d0                         ; space ends the name
	bne.s	.copy_lib_argument              ; not yet
.end_lib_argument:
	clr.b	(a1)                            ; terminate the library name
.back_to_separator:
	subq.l	#1,a0                           ; back to the separator, read again by .next_argument
	bra.s	.next_argument                  ; next argument
.copy_obj_argument:
	move.b	d0,(a2)+                        ; add the name to the object name list
	move.b	(a0)+,d0                        ; next character
	beq.s	.add_o_extension                ; end of the tail
	cmpi.b	#$20,d0                         ; space ends the name
	bne.s	.copy_obj_argument              ; not yet
.add_o_extension:
	move.b	#$2e,(a2)+                      ; append '.o' and a zero
	move.b	#$6f,(a2)+
	clr.b	(a2)+
	bra.s	.back_to_separator              ; next argument
.arguments_done:
	move.b	skip_first_object_flag(pc),d1   ; '#' given?
	beq.s	.start_link                     ; no: keep the list as it is
	lea	object_name_list(pc),a0         ; a0 = the object name list
	movea.l	a0,a1                           ; a1 = where the second name goes
.find_first_name_end:
	tst.b	(a0)+                           ; find the end of the first name
	bne.s	.find_first_name_end
	moveq	#99,d0                          ; 200 bytes
.drop_first_name:
	move.b	(a0)+,(a1)+                     ; move the rest of the list over the first name
	move.b	(a0)+,(a1)+
	dbra	d0,.drop_first_name             ; two bytes at a time
.start_link:
	bsr.w	link_program                    ; link the program
	move.w	error_count(pc),-(sp)           ; exit code = number of errors reported
	move.w	#$4c,-(sp)                      ; Pterm
	trap	#1                              ; Pterm
no_disk_prompt_flag:
	dc.w	$ffff                           ; nonzero: no disk prompts (G3WAIT=OFF, the default)

;------------------------------------------------------------------------------
; Prints the message at a0 and terminates with d0.w as the exit code.
;------------------------------------------------------------------------------
exit_with_message_code:
	move.w	d0,-(sp)                        ; exit code

;------------------------------------------------------------------------------
; Prints the message at a0 and terminates with the code already pushed on the stack.
;------------------------------------------------------------------------------
exit_with_message:
	bsr.s	print_string                    ; print the message
	move.w	#$4c,-(sp)                      ; Pterm
	trap	#1                              ; Pterm

;------------------------------------------------------------------------------
; Waits for a key (Cconin); d0 = the key.
;------------------------------------------------------------------------------
wait_for_key:
	move.w	#$1,-(sp)                       ; Cconin
	trap	#1                              ; Cconin
	addq.l	#2,sp                           ; drop the argument
	rts

;------------------------------------------------------------------------------
; Prints the zero-terminated string at a0 (Cconws).
;------------------------------------------------------------------------------
print_string:
	pea	(a0)                            ; string
	move.w	#$9,-(sp)                       ; Cconws
	trap	#1                              ; Cconws
	addq.l	#6,sp                           ; drop the arguments
	rts

;------------------------------------------------------------------------------
; Opens the file named at a0 for reading (Fopen mode 0).
; Exit: file_handle = the handle; on an error the linker prints 'Kann Datei <name> nicht oeffnen' and stops.
;------------------------------------------------------------------------------
open_file:
	moveq	#61,d0                          ; Fopen
	bra.s	open_or_create_file

;------------------------------------------------------------------------------
; Creates the file named at a0 (Fcreate, attributes 0). Exit as open_file.
;------------------------------------------------------------------------------
create_file:
	moveq	#60,d0                          ; Fcreate

;------------------------------------------------------------------------------
; Shared by open_file and create_file, d0 = GEMDOS function. Unless no_disk_prompt_flag is set it first asks for
; the disk ('Disk: <name> einlegen <RETURN>') and waits for a key. The linker keeps one file open at a time.
; Exit: d0 = file_handle = the handle; a GEMDOS error ends the program with the error as exit code.
;------------------------------------------------------------------------------
open_or_create_file:
	clr.w	-(sp)                           ; Fopen mode 0 / Fcreate attributes 0
	pea	(a0)                            ; file name
	move.w	d0,-(sp)                        ; GEMDOS function
	move.b	no_disk_prompt_flag(pc),d0      ; disk prompts off?
	bne.s	.call_gemdos                    ; yes: call at once
	lea	insert_disk_message(pc),a0      ; 'Disk: '
	bsr.s	print_string                    ; print it
	movea.l	2(sp),a0                        ; the file name
	bsr.s	print_string                    ; print it
	lea	insert_disk_return_message(pc),a0 ; ' einlegen <RETURN>' (insert, then Return)
	bsr.s	print_string                    ; print it
	bsr.s	wait_for_key                    ; wait for a key
	lea	newline_text(pc),a0             ; new line
	bsr.s	print_string                    ; print it
.call_gemdos:
	trap	#1                              ; GEMDOS, Fopen or Fcreate
	movea.l	2(sp),a0                        ; a0 = the file name again
	addq.l	#8,sp                           ; drop the arguments
	tst.l	d0                              ; handle, or a negative error
	bmi.s	.open_failed                    ; error: report it and stop
	move.w	d0,file_handle                  ; the open file's handle
	rts
.open_failed:
	move.w	d0,-(sp)                        ; the error becomes the exit code
	pea	(a0)                            ; keep the file name
	lea	cannot_open_message(pc),a0      ; 'Kann Datei ' (cannot ... file)
	bsr.s	print_string                    ; print it
	movea.l	(sp)+,a0                        ; the file name
	bsr.s	print_string                    ; print it
	lea	cannot_open_message_end(pc),a0  ; ' nicht oeffnen' (... open)
	bra.s	exit_with_message               ; print it and stop
cannot_open_message:
	dc.b	'Kann Datei ',0
cannot_open_message_end:
	dc.w	$206e,$6963,$6874,$2094         ; ' nicht ' and an o umlaut ($94 in the Atari set)
	dc.b	'ffnen',0
insert_disk_message:
	dc.b	'Disk: ',0
insert_disk_return_message:
	dc.b	' einlegen <RETURN>',0
newline_text:
	dc.w	$0d0a,$0000

;------------------------------------------------------------------------------
; Reads d0 bytes from file_handle to a0 (Fread); nothing when d0 is 0.
; Exit: d0 = bytes read. A GEMDOS error prints 'Lesefehler' and ends the program.
;------------------------------------------------------------------------------
read_file:
	pea	(a0)                            ; buffer
	move.l	d0,-(sp)                        ; byte count
	beq.s	.read_done                      ; zero: nothing to read
	move.w	file_handle(pc),-(sp)           ; handle
	move.w	#$3f,-(sp)                      ; Fread
	trap	#1                              ; Fread
	addq.l	#4,sp                           ; drop handle and function
.read_done:
	addq.l	#8,sp                           ; drop count and buffer
	tst.l	d0                              ; bytes read, or a negative error
	bmi.s	.read_failed                    ; error
	rts                                     ; d0 = bytes read
.read_failed:
	lea	read_error_message(pc),a0       ; 'Lesefehler' (read error)
	bra.w	exit_with_message_code          ; print it and stop with the error

;------------------------------------------------------------------------------
; Writes d0 bytes from a0 to file_handle (Fwrite); nothing when d0 is 0. A short write prints 'Diskette voll'
; and ends with code -1, a GEMDOS error prints 'Schreibfehler' and ends with the error.
;------------------------------------------------------------------------------
write_file:
	pea	(a0)                            ; buffer
	move.l	d0,-(sp)                        ; byte count
	beq.s	.write_done                     ; zero: nothing to write
	move.w	file_handle(pc),-(sp)           ; handle
	move.w	#$40,-(sp)                      ; Fwrite
	trap	#1                              ; Fwrite
	addq.l	#4,sp                           ; drop handle and function
	cmp.l	(sp),d0                         ; all bytes written?
	bne.s	.write_short                    ; no
.write_done:
	addq.l	#8,sp                           ; drop count and buffer
	rts
.write_short:
	tst.l	d0                              ; negative: a GEMDOS error
	bmi.s	.write_failed                   ; yes
	moveq	#-1,d0                          ; short write: exit code -1
	lea	disk_full_message(pc),a0        ; 'Diskette voll' (disk full)
	bra.w	exit_with_message_code          ; print it and stop
.write_failed:
	lea	write_error_message(pc),a0      ; 'Schreibfehler' (write error)
	bra.w	exit_with_message_code          ; print it and stop with the error

;------------------------------------------------------------------------------
; Seeks file_handle to offset d0 from the start of the file (Fseek mode 0).
;------------------------------------------------------------------------------
seek_file:
	clr.w	-(sp)                           ; mode 0: from the start
	move.w	file_handle(pc),-(sp)           ; handle
	move.l	d0,-(sp)                        ; offset
	move.w	#$42,-(sp)                      ; Fseek
	trap	#1                              ; Fseek
	adda.w	#$a,sp                          ; drop the arguments
	rts

;------------------------------------------------------------------------------
; Closes file_handle (Fclose).
;------------------------------------------------------------------------------
close_file:
	move.w	file_handle(pc),-(sp)           ; handle
	move.w	#$3e,-(sp)                      ; Fclose
	trap	#1                              ; Fclose
	addq.l	#4,sp                           ; drop the arguments
	rts

;------------------------------------------------------------------------------
; Reads the next 28 bytes of the file into object_header.
; Exit: d0-d5 = the header longs at +2..+$16: text, data, BSS and symbol table lengths, then the lengths of the
; text and the data relocation words.
;------------------------------------------------------------------------------
read_object_header:
	lea	object_header(pc),a0            ; header buffer
	moveq	#28,d0                          ; 28 bytes
	bsr.s	read_file                       ; read the header
	movem.l	object_header_lengths(pc),d0-d5 ; d0-d5 = header longs +2 to +$16
	rts

;------------------------------------------------------------------------------
; Loads the library index. Entry: a0 = the library name. Builds '<name>.NDX' (the name's own zero replaced) in free
; memory, opens it and reads the whole file to the same place, which is then kept: library_index = its address,
; library_index_length = its length (the space reserved is rounded up to even).
;------------------------------------------------------------------------------
load_library_index:
	movea.l	a0,a1                           ; a1 = the library name
	movea.l	heap_pointer(pc),a0             ; a0 = free memory
	movea.l	a0,a2                           ; a2 = where the name goes
.copy_index_name:
	move.b	(a1)+,(a2)+                     ; copy the library name
	bne.s	.copy_index_name
	move.b	#$2e,-$1(a2)                    ; its zero becomes '.'
	move.b	#$4e,(a2)+                      ; then 'NDX'
	move.b	#$44,(a2)+
	move.b	#$58,(a2)+
	clr.b	(a2)+                           ; and a zero
	bsr.w	open_file                       ; open <lib>.NDX
	movea.l	heap_pointer(pc),a0             ; a0 = free memory again
	move.l	a0,library_index                ; the index is loaded here
	moveq	#-1,d0                          ; d0 = $7fffffff:
	lsr.l	#1,d0                           ; read the whole file
	bsr.w	read_file                       ; into free memory, over the name
	move.l	d0,library_index_length         ; length of the index
	addq.l	#1,d0                           ; rounded up to even
	bclr	#$0,d0
	bsr.w	allocate_memory                 ; keep it
	bra.s	close_file                      ; close the index

;------------------------------------------------------------------------------
; Opens the object file named at a0, loads it into the module record at a6 and closes it.
;------------------------------------------------------------------------------
load_object_file:
	bsr.w	open_file                       ; open the object file
	bsr.s	read_object_module              ; load it into record a6
	bra.s	close_file                      ; close it

;------------------------------------------------------------------------------
; Loads one module from the current file position into the module record at a6. The header is read first; if
; it does not start with $601a the next 28 bytes are read as the header without a second check. When the header
; longs at $12 and $16 are both 0, the relocation words are taken to be as long as the text and the data.
; The rest of the module (text, data, symbol table, text relocation, data relocation, in that order) goes into
; new memory in one Fread.
; Module record, 48 bytes: +0 text, +4 data, +8 text relocation words, +$c data relocation words, +$10 symbol
; table (addresses); +$14 text, +$18 data, +$1c BSS, +$20 symbol table lengths; +$24, +$28, +$2c the module's
; text, data and BSS base in the program (set later by link_marked_modules).
;------------------------------------------------------------------------------
read_object_module:
	bsr.s	read_object_header              ; read the header
	cmpi.w	#$601a,object_header            ; $601a?
	beq.s	.header_read                    ; yes
	bsr.s	read_object_header              ; no: the next 28 bytes are the header
.header_read:
	move.l	d0,$14(a6)                      ; +$14: text length
	move.l	d1,$18(a6)                      ; +$18: data length
	move.l	d2,$1c(a6)                      ; +$1c: BSS length
	move.l	d3,$20(a6)                      ; +$20: symbol table length
	tst.l	d4                              ; text relocation length given?
	bne.s	.reloc_lengths_set
	tst.l	d5                              ; data relocation length given?
	bne.s	.reloc_lengths_set
	move.l	d0,d4                           ; neither: one relocation word per text word
	move.l	d1,d5                           ; and per data word
.reloc_lengths_set:
	move.l	d0,d7                           ; d7 = text length
	add.l	d1,d0                           ; d0 = text + data
	add.l	d4,d0                           ; + text relocation
	add.l	d5,d0                           ; + data relocation
	add.l	d3,d0                           ; + symbol table
	bsr.w	allocate_memory                 ; allocate it; a0 = its start
	move.l	a0,0(a6)                        ; +0: text
	adda.l	d7,a0                           ; data follows the text
	move.l	a0,4(a6)                        ; +4: data
	adda.l	d1,a0                           ; symbol table follows the data
	move.l	a0,$10(a6)                      ; +$10: symbol table
	adda.l	d3,a0                           ; text relocation words follow
	move.l	a0,8(a6)                        ; +8: text relocation words
	adda.l	d4,a0                           ; data relocation words follow
	move.l	a0,$c(a6)                       ; +$c: data relocation words
	adda.l	d5,a0                           ; end of the module
	move.l	a0,d0                           ; d0 = end
	movea.l	0(a6),a0                        ; a0 = text
	sub.l	a0,d0                           ; d0 = whole module length
	bsr.w	read_file                       ; read it
	rts

;------------------------------------------------------------------------------
; The link. Free memory starts at bss_end and is taken from there without any limit check.
; Loads every object file of object_name_list into module_records (a zeroed record ends the list), loads the
; library index, then collects in a list of 14-byte entries (8-byte name, type word, value) every global
; definition ($2000) and external reference ($0800) of the object files. A name defined twice gives ' +name' and an
; error, except names from '_0' to '_Z'. A reference already in the list is not added again, but a0 is then not
; moved past its type and value, so the walk through that module's symbols goes out of step (looks like a bug).
; NDX: header words 0 (not used), 1 = number of symbols, 2 = number of modules; then 20-byte module entries
; (a3), 12-byte symbol entries (a4) and the dependency bitmaps (a5), one row of (modules+7)/8 bytes per module.
; Every entry of the list that is not a definition is looked up in the NDX symbols. Its module is marked (bit 7
; of the module entry's first name byte) and its symbols are added as definitions (add_module_symbols); if it was
; marked already the reference is dropped from the list instead. A newly marked module's bitmap row marks the
; modules it needs, but their rows are not followed in turn, so the NDX rows must already hold every module
; needed indirectly. A name missing from the library gives ' ?name' and an error. Falls into link_marked_modules.
;------------------------------------------------------------------------------
link_program:
	move.l	#bss_end,heap_pointer           ; free memory starts behind the BSS
	lea	module_records(pc),a6           ; a6 = the first module record
	lea	object_name_list(pc),a5         ; a5 = the object name list
	clr.w	module_count                    ; no modules loaded yet
.load_next_object:
	movea.l	a5,a0                           ; a0 = the next name
	tst.b	(a5)+                           ; an empty name ends the list
	beq.s	.objects_loaded
.find_name_end:
	tst.b	(a5)+                           ; a5 to the following name
	bne.s	.find_name_end
	bsr.w	load_object_file                ; load the object file
	addq.w	#1,module_count                 ; count it
	lea	$30(a6),a6                      ; next record
	bra.s	.load_next_object               ; next name
.objects_loaded:
	moveq	#11,d0                          ; 12 longs
.clear_end_record:
	clr.l	(a6)+                           ; zeroed record ends the modules
	dbra	d0,.clear_end_record            ; until all 48 bytes are clear
	lea	library_name(pc),a0             ; a0 = the library name
	lea	module_records(pc),a6           ; a6 = the first module record
	bsr.w	load_library_index              ; load <lib>.NDX
	movea.l	heap_pointer(pc),a2             ; a2 = end of the symbol list
	move.l	a2,symbol_list_start            ; the list starts in free memory
.next_module_symbols:
	move.l	$10(a6),d0                      ; the module's symbol table
	beq.w	.mark_modules                   ; none: end record, all object files done
	movea.l	d0,a0                           ; a0 = its first symbol
	move.l	$20(a6),d2                      ; symbol table length
	divu.w	#$e,d2                          ; d2 = number of 14-byte symbols
	bra.s	.count_symbol                   ; into the loop
.next_symbol:
	addq.l	#8,a0                           ; a0 = the symbol's type word
	btst	#$3,(a0)                        ; $0800: external reference?
	bne.w	.add_external                   ; yes
	btst	#$5,(a0)                        ; $2000: global definition?
	bne.s	.add_global                     ; yes
.skip_symbol_value:
	addq.l	#6,a0                           ; skip type and value
.count_symbol:
	dbra	d2,.next_symbol                 ; next symbol
	lea	$30(a6),a6                      ; next module record
	bra.s	.next_module_symbols            ; next module
.add_global:
	movem.l	-$8(a0),d0-d1                   ; d0-d1 = the 8-character name
	movea.l	symbol_list_start(pc),a1        ; search the list from its start
	bra.s	.check_global_end               ; into the loop
.find_global:
	cmp.l	(a1)+,d0                        ; first name long matches?
	bne.s	.next_global_entry              ; no
	cmp.l	(a1),d1                         ; second name long matches?
	beq.s	.global_found                   ; yes: already in the list
.next_global_entry:
	adda.w	#$a,a1                          ; next entry
.check_global_end:
	cmpa.l	a2,a1                           ; end of the list?
	bcs.s	.find_global                    ; not yet
	move.l	d0,(a2)+                        ; not there: add the definition
	move.l	d1,(a2)+
	move.w	(a0)+,(a2)+                     ; type
	move.l	(a0)+,(a2)+                     ; value
	bra.s	.count_symbol                   ; next symbol
.global_found:
	addq.l	#4,a1                           ; a1 = the entry's type
	btst	#$5,(a1)                        ; already a definition?
	bne.s	.duplicate_global               ; yes: defined twice
	move.w	(a0)+,(a1)+                     ; no: the definition replaces the reference
	move.l	(a0)+,(a1)+                     ; its value
	bra.s	.count_symbol                   ; next symbol
.duplicate_global:
	movem.l	d0-d2/a0-a2,-(sp)               ; keep the registers
	lea	duplicate_symbol_message(pc),a0 ; ' +' message: defined twice
	movem.l	d0-d1,2(a0)                     ; put the name in it
	swap	d0                              ; d0.w = the first two characters
	cmpi.w	#$5f30,d0                       ; below '_0'?
	bcs.s	.print_duplicate                ; yes: an error
	cmpi.w	#$5f5a,d0                       ; up to '_Z'?
	bls.s	.duplicate_done                 ; yes: allowed twice, no message
.print_duplicate:
	pea	(a0)                            ; push the message
	moveq	#9,d1                           ; 10 characters
.pad_duplicate_name:
	move.b	(a0),d0                         ; character
	bne.s	.store_duplicate_char           ; not zero
	moveq	#32,d0                          ; zero prints as a space
.store_duplicate_char:
	move.b	d0,(a0)+                        ; store it
	dbra	d1,.pad_duplicate_name          ; next
	move.w	#$9,-(sp)                       ; Cconws
	trap	#1                              ; Cconws
	addq.l	#6,sp                           ; drop the arguments
	addq.w	#1,error_count                  ; count the error
.duplicate_done:
	movem.l	(sp)+,d0-d2/a0-a2               ; restore the registers
	bra.s	.skip_symbol_value              ; skip type and value
.add_external:
	movem.l	-$8(a0),d0-d1                   ; d0-d1 = the referenced name
	movea.l	symbol_list_start(pc),a1        ; search the list from its start
	bra.s	.check_external_end             ; into the loop
.find_external:
	cmp.l	(a1)+,d0                        ; first name long matches?
	bne.s	.next_external_entry            ; no
	cmp.l	(a1),d1                         ; second name long matches?
	beq.s	.external_known                 ; yes: already in the list
.next_external_entry:
	adda.w	#$a,a1                          ; next entry
.check_external_end:
	cmpa.l	a2,a1                           ; end of the list?
	bcs.s	.find_external                  ; not yet
	move.l	d0,(a2)+                        ; not there: add the reference
	move.l	d1,(a2)+
	move.w	(a0)+,(a2)+                     ; type
	move.l	(a0)+,(a2)+                     ; value
.external_known:
	bra.w	.count_symbol                   ; next symbol; when found, a0 is still at the type
.mark_modules:
	move.l	a2,heap_pointer                 ; the list is reserved
	movea.l	library_index,a1                ; a1 = the library index
	movem.w	(a1)+,d2-d4                     ; d2 = word 0 (unused), d3 = symbols, d4 = modules
	movea.l	a1,a3                           ; a3 = the 20-byte module entries
	move.l	d4,d2                           ; d2 = modules
	asl.l	#2,d2                           ; * 4
	add.l	d4,d2                           ; * 5
	asl.l	#2,d2                           ; * 20
	lea	0(a3,d2.l),a4                   ; a4 = the 12-byte symbol entries
	move.l	d3,d2                           ; d2 = symbols
	add.l	d2,d2                           ; * 2
	add.l	d3,d2                           ; * 3
	asl.l	#2,d2                           ; * 12
	lea	0(a4,d2.l),a5                   ; a5 = the dependency bitmaps
	movea.l	symbol_list_start(pc),a0        ; a0 = the start of the list
	bra.s	.check_reference_end            ; into the loop
.next_reference:
	addq.l	#8,a0                           ; a0 = the entry's type
	btst	#$3,(a0)                        ; external reference?
	bne.s	.look_up_reference              ; yes: look it up in the library
	btst	#$5,(a0)                        ; global definition?
	beq.s	.look_up_reference              ; no: look it up too
.skip_reference_value:
	addq.l	#6,a0                           ; skip type and value
.check_reference_end:
	cmpa.l	a2,a0                           ; end of the list? (it grows as modules are added)
	bcs.s	.next_reference                 ; not yet
	bra.w	link_marked_modules             ; all references done
.look_up_reference:
	movem.l	-$8(a0),d0-d1                   ; d0-d1 = the name
	lea	-$8(a4),a1                      ; a1 = the first NDX symbol less 8
.next_index_symbol:
	addq.l	#8,a1                           ; next 12-byte entry
	cmpa.l	a5,a1                           ; past the last one?
	bcc.s	.not_in_library                 ; yes: not in the library
	cmp.l	(a1)+,d0                        ; first name long matches?
	bne.s	.next_index_symbol              ; no
	cmp.l	(a1),d1                         ; second name long matches?
	bne.s	.next_index_symbol              ; no
	move.w	6(a1),d0                        ; the entry's module index
	ext.l	d0                              ; as a long
	move.l	d0,d1                           ; d1 = index
	asl.l	#2,d1                           ; * 4
	add.l	d0,d1                           ; * 5
	asl.l	#2,d1                           ; * 20
	lea	0(a3,d1.l),a1                   ; a1 = the module entry
	tas	(a1)                            ; mark it: bit 7 of its first name byte
	bpl.s	.module_newly_marked            ; it was not marked yet
	clr.l	-$8(a0)                         ; already marked: drop this entry from the list
	bra.s	.skip_reference_value           ; next entry
.module_newly_marked:
	bsr.s	add_module_symbols              ; add the module's symbols as definitions
	move.w	d4,d1                           ; d1 = modules
	move.w	d4,d2                           ; d2 = bits left in the row
	addq.w	#7,d1                           ; +7
	lsr.w	#3,d1                           ; d1 = bytes per bitmap row
	mulu.w	d0,d1                           ; times the module index
	lea	0(a5,d1.l),a1                   ; a1 = the module's dependency row
	moveq	#0,d0                           ; d0 = module index of the first bit
.next_bitmap_byte:
	move.b	(a1)+,d7                        ; next byte of the row
	beq.s	.empty_bitmap_byte              ; no bits set: eight modules on
	moveq	#7,d6                           ; 8 bits
.next_bitmap_bit:
	add.b	d7,d7                           ; next bit, most significant first
	bcc.s	.next_dependency                ; not needed
	move.l	d0,d1                           ; d1 = index
	asl.l	#2,d1                           ; * 4
	add.l	d0,d1                           ; * 5
	asl.l	#2,d1                           ; * 20
	tas	0(a3,d1.l)                      ; mark that module
	bmi.s	.next_dependency                ; already marked
	bsr.s	add_module_symbols              ; add its symbols
.next_dependency:
	addq.w	#1,d0                           ; next module index
	dbra	d6,.next_bitmap_bit             ; next bit
	bra.s	.count_bitmap_byte              ; next byte
.empty_bitmap_byte:
	addq.w	#8,d0                           ; eight modules on
.count_bitmap_byte:
	subq.w	#8,d2                           ; eight bits fewer
	bpl.s	.next_bitmap_byte               ; one byte too many when modules is a multiple of 8
	bra.s	.skip_reference_value           ; next entry
.not_in_library:
	move.l	d0,d2                           ; name for the message
	move.l	d1,d3
	bsr.w	report_undefined_symbol         ; ' ?name': undefined
	bra.w	.skip_reference_value           ; next entry

;------------------------------------------------------------------------------
; Adds every NDX symbol of module d0.w to the symbol list at a2 as a definition (type $2000, value 0). Entry:
; a4 = the NDX symbol entries, a5 = their end. The word at +8 and the module index at +10 are compared as one long
; with d0, so only entries with 0 at +8 count. Exit: a2 past the new entries; a1 kept.
;------------------------------------------------------------------------------
add_module_symbols:
	move.l	a1,-(sp)                        ; keep a1
	movea.l	a4,a1                           ; a1 = the NDX symbol entries
	ext.l	d0                              ; d0 = module index as a long
.scan_index_symbol:
	addq.l	#8,a1                           ; a1 = the entry's word at +8
	cmp.l	(a1)+,d0                        ; +8 and the module index as one long
	beq.s	.add_module_symbol              ; a symbol of this module
.check_index_end:
	cmpa.l	a5,a1                           ; past the last entry?
	bcs.s	.scan_index_symbol              ; not yet
	movea.l	(sp)+,a1                        ; restore a1
	rts
.add_module_symbol:
	move.l	-$c(a1),(a2)+                   ; add its name to the list
	move.l	-$8(a1),(a2)+
	move.w	#$2000,(a2)+                    ; type $2000: a definition
	clr.l	(a2)+                           ; value 0
	bra.s	.check_index_end                ; next entry

;------------------------------------------------------------------------------
; Rest of the link. Drops the list entries cleared by link_program, loads every marked library module, in index
; order, from its offset in the library into the records behind the object files', and sets each module's text
; base (all text first), data base (behind all text) and BSS base (behind all data); the totals go into
; program_header. Then builds a new symbol list of every global definition with its value turned into a program
; offset (bit 10 data, bit 9 text, bit 8 BSS add that base; values in the modules' symbol tables change too),
; looks up BaseA4 in it (d6, $80000000 when missing), relocates every module's text and then data while
; building the relocation table at a4, and writes the program: header, all text, all data, the symbol list when
; -S was given, then the relocation table and its zero byte.
;------------------------------------------------------------------------------
link_marked_modules:
	movea.l	symbol_list_start(pc),a0        ; a0 = read pointer in the list
	movea.l	a0,a1                           ; a1 = write pointer
	bra.s	.check_compact_end              ; into the loop
.copy_entry:
	move.l	(a0)+,(a1)+                     ; first name long; zero marks a dropped entry
	beq.s	.drop_entry                     ; dropped
	move.l	(a0)+,(a1)+                     ; second name long
	move.w	(a0)+,(a1)+                     ; type
	move.l	(a0)+,(a1)+                     ; value
.check_compact_end:
	cmpa.l	a2,a0                           ; end of the list?
	bcs.s	.copy_entry                     ; not yet
	bra.s	.compacted                      ; done
.drop_entry:
	subq.l	#4,a1                           ; take back the long copied
	adda.w	#$a,a0                          ; skip the rest of the entry
	bra.s	.check_compact_end              ; next entry
.compacted:
	move.l	a1,heap_pointer                 ; free memory after the shortened list
	move.w	d4,-(sp)                        ; count down the NDX modules
	lea	library_name(pc),a0             ; a0 = the library name
	lea	module_records(pc),a6           ; a6 = the first record
	move.w	module_count(pc),d0             ; module count so far
	mulu.w	#$30,d0                         ; * 48
	adda.l	d0,a6                           ; a6 = the record after the object files'
	bsr.w	open_file                       ; open the library
.next_library_module:
	subq.w	#1,(sp)                         ; next module entry
	bmi.s	.library_loaded                 ; all done
	tst.b	(a3)                            ; marked?
	bpl.s	.skip_library_module            ; no
	move.l	$10(a3),d0                      ; entry +$10: its offset in the library
	bsr.w	seek_file                       ; seek to it
	bsr.w	read_object_module              ; load it into the next record
	addq.w	#1,module_count                 ; count it
	lea	$30(a6),a6                      ; next record
.skip_library_module:
	adda.w	#$14,a3                         ; next 20-byte entry
	bra.s	.next_library_module            ; next module
.library_loaded:
	addq.l	#2,sp                           ; drop the counter
	bsr.w	close_file                      ; close the library
	moveq	#11,d0                          ; 12 longs
.clear_end_record:
	clr.l	(a6)+                           ; zeroed record ends the modules
	dbra	d0,.clear_end_record            ; until all 48 bytes are clear
	moveq	#0,d0                           ; d0 = program offset
	move.w	module_count(pc),d1             ; d1 = number of modules
	lea	module_records(pc),a6           ; a6 = the first record
	move.w	d1,d2                           ; count
	movea.l	a6,a2                           ; a2 = the record
	bra.s	.count_text_base                ; into the loop
.set_text_base:
	move.l	d0,$24(a2)                      ; +$24: the module's text base
	add.l	$14(a2),d0                      ; plus its text length
	lea	$30(a2),a2                      ; next record
.count_text_base:
	dbra	d2,.set_text_base               ; next module
	move.l	d0,d3                           ; d3 = end of all text
	move.w	d1,d2                           ; count
	movea.l	a6,a2                           ; a2 = the first record
	bra.s	.count_data_base                ; into the loop
.set_data_base:
	move.l	d0,$28(a2)                      ; +$28: its data base, behind all text
	add.l	$18(a2),d0                      ; plus its data length
	lea	$30(a2),a2                      ; next record
.count_data_base:
	dbra	d2,.set_data_base               ; next module
	move.l	d0,d4                           ; d4 = end of all data
	bra.s	.count_bss_base                 ; into the loop
.set_bss_base:
	move.l	d0,$2c(a6)                      ; +$2c: its BSS base, behind all data
	add.l	$1c(a6),d0                      ; plus its BSS length
	lea	$30(a6),a6                      ; next record
.count_bss_base:
	dbra	d1,.set_bss_base                ; next module
	move.l	d0,d5                           ; d5 = end of all BSS
	sub.l	d4,d5                           ; d5 = BSS length
	sub.l	d3,d4                           ; d4 = data length
	movem.l	d3-d5,program_header_lengths    ; program header: text, data, BSS lengths
	lea	module_records(pc),a6           ; a6 = the first record
	movea.l	heap_pointer(pc),a2             ; a2 = a new symbol list in free memory
	move.l	a2,symbol_list_start            ; its start
.next_module_symbols:
	move.l	$10(a6),d0                      ; the module's symbol table
	beq.s	.find_base_a4                   ; none: all modules done
	movea.l	d0,a0                           ; a0 = its first symbol
	move.l	$20(a6),d0                      ; symbol table length
	divu.w	#$e,d0                          ; d0 = number of 14-byte symbols
	bra.s	.count_symbol                   ; into the loop
.next_symbol:
	addq.l	#8,a0                           ; a0 = the type word
	btst	#$3,(a0)                        ; external reference?
	bne.s	.skip_symbol_value              ; yes: skip it
	btst	#$5,(a0)                        ; global definition?
	bne.s	.add_global                     ; yes: add it
.skip_symbol_value:
	addq.l	#6,a0                           ; skip type and value
.count_symbol:
	dbra	d0,.next_symbol                 ; next symbol
	lea	$30(a6),a6                      ; next module record
	bra.s	.next_module_symbols            ; next module
.add_global:
	move.l	-$8(a0),(a2)+                   ; copy the name
	move.l	-$4(a0),(a2)+
	move.w	(a0)+,d2                        ; type
	move.w	d2,(a2)+                        ; copy it
	asl.w	#6,d2                           ; carry = bit 10 ($0400): data
	bcs.s	.data_symbol                    ; data symbol
	add.w	d2,d2                           ; carry = bit 9 ($0200) text, N = bit 8 ($0100) BSS
	bcs.s	.text_symbol                    ; text symbol
	bmi.s	.bss_symbol                     ; BSS symbol
	bra.s	.copy_value                     ; otherwise the value stays
.bss_symbol:
	move.l	$2c(a6),d1                      ; the module's BSS base
	add.l	d1,(a0)                         ; added to the value in the module's table
.copy_value:
	move.l	(a0)+,(a2)+                     ; copy the value
	bra.s	.count_symbol                   ; next symbol
.data_symbol:
	move.l	$28(a6),d1                      ; the module's data base
	add.l	d1,(a0)                         ; added to the value in the module's table
	move.l	(a0)+,(a2)+                     ; copy the value
	bra.s	.count_symbol                   ; next symbol
.text_symbol:
	move.l	$24(a6),d1                      ; the module's text base
	add.l	d1,(a0)                         ; added to the value in the module's table
	move.l	(a0)+,(a2)+                     ; copy the value
	bra.s	.count_symbol                   ; next symbol
.find_base_a4:
	move.l	a2,heap_pointer                 ; the list is reserved
	movea.l	symbol_list_start(pc),a0        ; search it
	moveq	#1,d6                           ; d6 = $80000000 if BaseA4 is missing
	ror.l	#1,d6                           ; bit 0 rotated to bit 31
	move.l	#$42617365,d0                   ; 'Base'
	move.l	#$41340000,d1                   ; 'A4' and two zeros
.compare_first_long:
	cmp.l	(a0)+,d0                        ; first name long matches?
	beq.s	.compare_second_long            ; yes
.next_base_a4_entry:
	adda.w	#$a,a0                          ; next entry
	cmpa.l	a2,a0                           ; end of the list?
	bcs.s	.compare_first_long             ; not yet
	bra.s	.relocate_modules               ; not found
.compare_second_long:
	cmp.l	(a0),d1                         ; second name long matches?
	bne.s	.next_base_a4_entry             ; no
	move.l	6(a0),d6                        ; d6 = BaseA4's value
.relocate_modules:
	movea.l	heap_pointer(pc),a4             ; a4 = the relocation table, in free memory
	suba.l	a5,a5                           ; a5 = 0: no relocation recorded yet
	move.w	module_count(pc),-(sp)          ; count the modules
	lea	module_records(pc),a6           ; a6 = the first record
	bra.s	.count_text                     ; into the loop
.relocate_text:
	movea.l	$24(a6),a0                      ; a0 = the text's program offset
	movea.l	0(a6),a1                        ; a1 = the text
	movea.l	8(a6),a2                        ; a2 = its relocation words
	move.l	$14(a6),d0                      ; d0 = text length
	bsr.w	relocate_segment                ; relocate it
	lea	$30(a6),a6                      ; next record
.count_text:
	subq.w	#1,(sp)                         ; next module
	bpl.s	.relocate_text
	addq.l	#2,sp                           ; drop the counter
	move.w	module_count(pc),-(sp)          ; count the modules
	lea	module_records(pc),a6           ; a6 = the first record
	bra.s	.count_data                     ; into the loop
.relocate_data:
	movea.l	$28(a6),a0                      ; a0 = the data's program offset
	movea.l	4(a6),a1                        ; a1 = the data
	movea.l	$c(a6),a2                       ; a2 = its relocation words
	move.l	$18(a6),d0                      ; d0 = data length
	bsr.w	relocate_segment                ; relocate it
	lea	$30(a6),a6                      ; next record
.count_data:
	subq.w	#1,(sp)                         ; next module
	bpl.s	.relocate_data
	addq.l	#2,sp                           ; drop the counter
	movea.l	prg_name_pointer(pc),a0         ; a0 = the program name
	bsr.w	create_file                     ; create it
	lea	program_header(pc),a0           ; a0 = the program header
	move.b	write_symbols_flag(pc),d0       ; -S given?
	beq.s	.write_header                   ; no: symbol table length stays 0
	move.l	heap_pointer(pc),d0             ; end of the symbol list
	sub.l	symbol_list_start(pc),d0        ; minus its start
	move.l	d0,$e(a0)                       ; header +$e: symbol table length
.write_header:
	moveq	#28,d0                          ; 28 bytes
	bsr.w	write_file                      ; write the header
	move.w	module_count(pc),-(sp)          ; count the modules
	lea	module_records(pc),a6           ; a6 = the first record
	bra.s	.count_text_writes              ; into the loop
.write_text:
	movea.l	0(a6),a0                        ; the module's text
	move.l	$14(a6),d0                      ; its length
	bsr.w	write_file                      ; write it
	lea	$30(a6),a6                      ; next record
.count_text_writes:
	subq.w	#1,(sp)                         ; next module
	bpl.s	.write_text
	addq.l	#2,sp                           ; drop the counter
	move.w	module_count(pc),-(sp)          ; count the modules
	lea	module_records(pc),a6           ; a6 = the first record
	bra.s	.count_data_writes              ; into the loop
.write_data:
	movea.l	4(a6),a0                        ; the module's data
	move.l	$18(a6),d0                      ; its length
	bsr.w	write_file                      ; write it
	lea	$30(a6),a6                      ; next record
.count_data_writes:
	subq.w	#1,(sp)                         ; next module
	bpl.s	.write_data
	addq.l	#2,sp                           ; drop the counter
	move.b	write_symbols_flag(pc),d0       ; -S given?
	beq.s	.write_relocations              ; no
	movea.l	symbol_list_start(pc),a0        ; the symbol list
	move.l	heap_pointer(pc),d0             ; its end
	sub.l	a0,d0                           ; d0 = its length
	bsr.w	write_file                      ; write it
.write_relocations:
	clr.b	(a4)+                           ; a zero byte ends the relocation table
	move.l	a4,d0                           ; end of the table
	movea.l	heap_pointer(pc),a0             ; its start
	sub.l	a0,d0                           ; d0 = its length
	bsr.w	write_file                      ; write it
	bsr.w	close_file                      ; close the program
	rts

;------------------------------------------------------------------------------
; Part of relocate_segment: steps a0 on a word and takes the next relocation word.
;------------------------------------------------------------------------------
relocate_next_word:
	addq.l	#2,a0                           ; a0 = 2 past the offset of the next word
	move.w	(a2)+,d1                        ; its relocation word
	bne.s	relocate_by_type                ; not zero: handle it

;------------------------------------------------------------------------------
; Part of relocate_segment: a word with nothing to do; steps a1 on.
;------------------------------------------------------------------------------
relocate_plain_word:
	addq.l	#2,a1                           ; nothing to do: next word in memory

;------------------------------------------------------------------------------
; Relocates one segment. Entry: a0 = the segment's offset in the program, a1 = the segment in memory, a2 = its
; relocation words, one per word, d0 = its length, a6 = its module record, a4/a5 = relocation table pointer and
; the offset (+4) of the last relocated long, 0 for none, d6 = BaseA4. Inside, a0 is always 2 past the offset of
; the word a1 points at. Word types (low 3 bits): 0 bad, 1/2/3 add the data/text/BSS base to the word,
; index*8+4 add external symbol index's value to the word, 5 a long follows (the next word gives its type),
; index*8+6 PC-relative word to an external symbol, n*8+7 skip n words ($8007 = 4096).
; Exit: a4, a5 updated; d1-d5, d7, a3 changed.
;------------------------------------------------------------------------------
relocate_segment:
	subq.l	#2,d0                           ; one word fewer
	bpl.s	relocate_next_word              ; more: next word
	rts                                     ; segment done

;------------------------------------------------------------------------------
; Jumps to the handler of relocation word d1 by its low three bits.
;------------------------------------------------------------------------------
relocate_by_type:
	moveq	#7,d2                           ; d2 = relocation type, low three bits
	and.w	d1,d2
	add.w	d2,d2                           ; table index
	move.w	word_reloc_table(pc,d2.w),d2    ; offset of the handler
	jmp	word_reloc_table(pc,d2.w)       ; jump to it
word_reloc_table:
	dc.w	.bad_word_reloc-word_reloc_table
	dc.w	.data_word-word_reloc_table
	dc.w	.text_word-word_reloc_table
	dc.w	.bss_word-word_reloc_table
	dc.w	.external_word-word_reloc_table
	dc.w	.long_reloc-word_reloc_table
	dc.w	reloc_pc_relative_external-word_reloc_table
	dc.w	reloc_skip_words-word_reloc_table
.bad_word_reloc:
	illegal                                 ; type 0 must not occur
.data_word:
	move.w	(a1),d7                         ; the word
	ext.l	d7                              ; sign-extended
	add.l	$28(a6),d7                      ; plus the module's data base
	move.w	d7,(a1)+                        ; stored
	move.w	d7,d2                           ; range check with no effect:
	ext.l	d2
	cmp.l	d2,d7                           ; both branches continue
	beq.s	relocate_segment
	bra.s	relocate_segment
.text_word:
	move.w	(a1),d7                         ; the word
	ext.l	d7                              ; sign-extended
	add.l	$24(a6),d7                      ; plus the module's text base
	move.w	d7,(a1)+                        ; stored
	move.w	d7,d2                           ; range check with no effect:
	ext.l	d2
	cmp.l	d2,d7                           ; both branches continue
	beq.s	relocate_segment
	bra.s	relocate_segment
.bss_word:
	move.w	(a1),d7                         ; the word
	ext.l	d7                              ; sign-extended
	add.l	$2c(a6),d7                      ; plus the module's BSS base
	move.w	d7,(a1)+                        ; stored
	move.w	d7,d2                           ; range check with no effect:
	ext.l	d2
	cmp.l	d2,d7                           ; both branches continue
	beq.s	relocate_segment
	bra.s	relocate_segment
.external_word:
	lsr.w	#3,d1                           ; d1 = symbol index
	add.w	d1,d1                           ; * 2
	ext.l	d1                              ; as a long
	move.l	d1,d2                           ; keep * 2
	asl.l	#3,d1                           ; * 16
	sub.l	d2,d1                           ; * 14
	movea.l	$10(a6),a3                      ; a3 = the module's symbol table
	adda.l	d1,a3                           ; a3 = the symbol
	btst	#$3,8(a3)                       ; still a reference?
	bne.s	.resolve_external_word          ; yes: fetch the definition
	btst	#$5,8(a3)                       ; a definition?
	bne.s	.add_external_word              ; yes: its value is known
.resolve_external_word:
	bsr.w	resolve_symbol                  ; fetch it from the symbol list
.add_external_word:
	move.l	$a(a3),d1                       ; d1 = the symbol's value
	move.w	(a1),d2                         ; the word
	ext.l	d2                              ; sign-extended
	add.l	d2,d1                           ; added
	move.w	d1,(a1)+                        ; stored
	move.w	d1,d2
	ext.l	d2
	cmp.l	d1,d1                           ; compares d1 with itself, so never out of range
	beq.w	relocate_segment                ; always taken
	bra.w	report_out_of_range             ; not reached
.long_reloc:
	subq.l	#2,d0                           ; the long takes another word
	addq.l	#2,a0                           ; a0 past it
	move.w	(a2)+,d1                        ; the relocation word of the low word
	moveq	#7,d2                           ; its type
	and.w	d1,d2                           ; low three bits
	add.w	d2,d2                           ; table index
	move.w	long_reloc_table(pc,d2.w),d2    ; offset of the handler
	jmp	long_reloc_table(pc,d2.w)       ; jump to it
long_reloc_table:
	dc.w	reloc_long_absolute-long_reloc_table
	dc.w	reloc_long_data-long_reloc_table
	dc.w	reloc_long_text-long_reloc_table
	dc.w	reloc_long_bss-long_reloc_table
	dc.w	reloc_long_external-long_reloc_table
	dc.w	bad_long_reloc_five-long_reloc_table
	dc.w	bad_long_reloc_six-long_reloc_table
	dc.w	bad_long_reloc_seven-long_reloc_table

;------------------------------------------------------------------------------
; Relocation type 6: PC-relative word to external symbol d1>>3, as in bsr.w or bra.w. The displacement is the
; symbol's offset minus the word's offset plus the word already there. If that does not fit in 16 bits and the
; instruction is bsr.w or bra.w, it becomes jsr or jmp d16(a4) with a4 taken to be BaseA4+$8000; the symbol must
; then lie within 64K above BaseA4. Anything else gives ' >name' and an error.
;------------------------------------------------------------------------------
reloc_pc_relative_external:
	lsr.w	#3,d1                           ; d1 = symbol index
	add.w	d1,d1                           ; * 2
	ext.l	d1                              ; as a long
	move.l	d1,d2                           ; keep * 2
	asl.l	#3,d1                           ; * 16
	sub.l	d2,d1                           ; * 14
	movea.l	$10(a6),a3                      ; a3 = the module's symbol table
	adda.l	d1,a3                           ; a3 = the symbol
	btst	#$3,8(a3)                       ; still a reference?
	bne.s	.resolve_target                 ; yes: fetch the definition
	btst	#$5,8(a3)                       ; a definition?
	bne.s	.compute_displacement           ; yes: its value is known
.resolve_target:
	bsr.w	resolve_symbol                  ; fetch it from the symbol list
.compute_displacement:
	move.l	$a(a3),d1                       ; d1 = the target's program offset
	move.l	d1,d2                           ; kept in d2
	sub.l	a0,d1                           ; minus the word's offset + 2
	addq.l	#2,d1                           ; +2: displacement from the word itself
	move.w	(a1),d3                         ; the word already there
	ext.l	d3                              ; sign-extended
	add.l	d3,d1                           ; added
	move.w	d1,(a1)+                        ; store the displacement
	move.w	d1,d4                           ; sign-extended low word
	ext.l	d4
	cmp.l	d1,d4                           ; fits in 16 bits?
	beq.w	relocate_segment                ; yes: done
	cmpi.w	#$6100,-$4(a1)                  ; bsr.w before it?
	beq.s	.make_jsr                       ; yes: becomes jsr
	cmpi.w	#$6000,-$4(a1)                  ; bra.w before it?
	beq.s	.make_jmp                       ; yes: becomes jmp
	bra.w	report_out_of_range             ; anything else: ' >name', out of range
.make_jmp:
	move.w	#$4eec,d7                       ; jmp d16(a4)
	bra.s	.a4_displacement
.make_jsr:
	move.w	#$4eac,d7                       ; jsr d16(a4)
.a4_displacement:
	sub.l	d6,d2                           ; target minus BaseA4
	add.l	d3,d2                           ; plus the word already there
	move.l	d2,d3
	swap	d3                              ; high word
	tst.w	d3                              ; must be 0: within 64K above BaseA4
	bne.w	report_out_of_range             ; else out of range
	addi.w	#$8000,d2                       ; displacement from a4 = BaseA4+$8000
	move.w	d7,-$4(a1)                      ; rewrite the opcode
	move.w	d2,-$2(a1)                      ; and the displacement
	bra.w	relocate_segment                ; next word

;------------------------------------------------------------------------------
; Relocation type 7: n = d1>>3 words left as they are, this one included; n = 0 means just this word.
;------------------------------------------------------------------------------
reloc_skip_words:
	lsr.w	#3,d1                           ; d1 = number of words to leave
	beq.w	relocate_plain_word             ; zero: just this word
	ext.l	d1                              ; as a long
	add.w	d1,d1                           ; d1 = their length in bytes
	adda.w	d1,a1                           ; a1 past them
	adda.w	d1,a0                           ; a0 past them
	subq.l	#2,a0                           ; less the word already counted
	sub.l	d1,d0                           ; d0 likewise
	addq.l	#2,d0
	bra.w	relocate_segment                ; next word

;------------------------------------------------------------------------------
; Long relocation type 0: an absolute long, left as it is and not relocated.
;------------------------------------------------------------------------------
reloc_long_absolute:
	addq.l	#4,a1                           ; absolute long: skip it
	bra.w	relocate_segment                ; next word

;------------------------------------------------------------------------------
; Long relocation type 1: adds the module's data base to the long and records a relocation.
;------------------------------------------------------------------------------
reloc_long_data:
	move.l	$28(a6),d7                      ; the module's data base
	add.l	d7,(a1)+                        ; added to the long
	bra.s	emit_relocation                 ; record the relocation

;------------------------------------------------------------------------------
; Long relocation type 2: adds the module's text base to the long and records a relocation.
;------------------------------------------------------------------------------
reloc_long_text:
	move.l	$24(a6),d7                      ; the module's text base
	add.l	d7,(a1)+                        ; added to the long
	bra.s	emit_relocation                 ; record the relocation

;------------------------------------------------------------------------------
; Long relocation type 3: adds the module's BSS base to the long and records a relocation.
;------------------------------------------------------------------------------
reloc_long_bss:
	move.l	$2c(a6),d7                      ; the module's BSS base
	add.l	d7,(a1)+                        ; added to the long
	bra.s	emit_relocation                 ; record the relocation

;------------------------------------------------------------------------------
; Long relocation type 4 (index*8+4): adds external symbol d1>>3's value to the long; records a relocation unless
; the symbol is equated (type bit 14).
;------------------------------------------------------------------------------
reloc_long_external:
	lsr.w	#3,d1                           ; d1 = symbol index
	add.w	d1,d1                           ; * 2
	ext.l	d1                              ; as a long
	move.l	d1,d2                           ; keep * 2
	asl.l	#3,d1                           ; * 16
	sub.l	d2,d1                           ; * 14
	movea.l	$10(a6),a3                      ; a3 = the module's symbol table
	adda.l	d1,a3                           ; a3 = the symbol
	btst	#$3,8(a3)                       ; still a reference?
	bne.s	.resolve_external_long          ; yes: fetch the definition
	btst	#$5,8(a3)                       ; a definition?
	bne.s	.add_external_long              ; yes: its value is known
.resolve_external_long:
	bsr.s	resolve_symbol                  ; fetch it from the symbol list
.add_external_long:
	move.w	8(a3),d2                        ; d2 = the symbol's type
	move.l	$a(a3),d1                       ; d1 = its value
	add.l	d1,(a1)+                        ; added to the long
	add.w	d2,d2                           ; N = bit 14 ($4000): equated
	bmi.w	relocate_segment                ; equated: no relocation

;------------------------------------------------------------------------------
; Records the long that ends at offset a0 in the TOS relocation table at a4: the first as a long offset, then
; distances from the one before as bytes, 1 for every 254 bytes of a distance over 255 (an exact multiple of
; 254 ends with a 254 byte). Exit: a5 = a0; continues relocate_segment.
;------------------------------------------------------------------------------
emit_relocation:
	move.l	a5,d1                           ; offset (+4) of the previous relocation
	beq.s	.first_relocation               ; none: this is the first
	sub.l	a0,d1
	neg.l	d1                              ; d1 = distance from the previous one
	cmpi.l	#$ff,d1                         ; more than 255?
	bhi.s	.long_distance                  ; yes
.store_distance:
	move.b	d1,(a4)+                        ; distance byte
	movea.l	a0,a5                           ; remember this one
	bra.w	relocate_segment                ; next word
.long_distance:
	divu.w	#$fe,d1                         ; d1 = remainder : quotient of distance / 254
	cmpi.l	#$ffff,d1                       ; remainder 0?
	bhi.s	.emit_skips                     ; no
	addi.l	#$fdffff,d1                     ; then quotient-1 skips and a final 254
.emit_skips:
	bra.s	.count_skips                    ; into the loop
.emit_skip:
	move.b	#$1,(a4)+                       ; 1: skip 254 bytes
.count_skips:
	dbra	d1,.emit_skip                   ; one per 254
	swap	d1                              ; d1 = the remainder, the last byte
	bra.s	.store_distance                 ; store it
.first_relocation:
	move.l	a0,(a4)                         ; a0 is 4 past the long:
	subq.l	#4,(a4)+                        ; the first relocation as a long offset
	movea.l	a0,a5                           ; remember this one
	bra.w	relocate_segment                ; next word

;------------------------------------------------------------------------------
; Long relocation type 5 is not used: an illegal instruction.
;------------------------------------------------------------------------------
bad_long_reloc_five:
	illegal                                 ; long type 5 must not occur

;------------------------------------------------------------------------------
; Long relocation type 6 is not used: an illegal instruction.
;------------------------------------------------------------------------------
bad_long_reloc_six:
	illegal                                 ; long type 6 must not occur

;------------------------------------------------------------------------------
; Long relocation type 7 is not used: an illegal instruction (the rts after it is never reached).
;------------------------------------------------------------------------------
bad_long_reloc_seven:
	illegal                                 ; long type 7 must not occur
	rts                                     ; not reached

;------------------------------------------------------------------------------
; Fetches the definition of the module symbol at a3 from the symbol list (symbol_list_start to heap_pointer)
; and copies its type and value into the module's symbol table, so that later references use it directly.
; A missing name gives ' ?name' and an error; a name in the list that is not a definition gives the same
; message but is copied anyway. Exit: a1 kept; d2-d5, d7 changed.
;------------------------------------------------------------------------------
resolve_symbol:
	movem.l	(a3),d2-d3                      ; d2-d3 = the symbol's name
	move.l	a1,d5                           ; keep a1
	move.l	heap_pointer(pc),d4             ; end of the symbol list
	movea.l	symbol_list_start(pc),a1        ; a1 = its start
	moveq	#10,d7                          ; 10: the rest of an entry
.compare_first_long:
	cmp.l	(a1)+,d2                        ; first name long matches?
	beq.s	.compare_second_long            ; yes
	adda.l	d7,a1                           ; next entry
.check_list_end:
	cmpa.l	d4,a1                           ; end of the list?
	bcs.s	.compare_first_long             ; not yet
	bsr.s	report_undefined_symbol         ; not there: ' ?name'
	bra.s	.resolve_done                   ; done
.compare_second_long:
	cmp.l	(a1)+,d3                        ; second name long matches?
	beq.s	.symbol_found                   ; yes
	addq.l	#6,a1                           ; next entry
	bra.s	.check_list_end                 ; continue
.symbol_found:
	btst	#$5,(a1)                        ; a definition?
	bne.s	.copy_definition                ; yes
	bsr.s	report_undefined_symbol         ; no: ' ?name', but copied all the same
.copy_definition:
	move.w	(a1)+,8(a3)                     ; type into the module's symbol
	move.l	(a1),$a(a3)                     ; and value
.resolve_done:
	movea.l	d5,a1                           ; restore a1
	rts

;------------------------------------------------------------------------------
; Prints ' ?' and the 8-character name in d2-d3 (zero bytes as spaces) and counts an error. No line feed
; follows, so the messages run on one line. All registers kept.
;------------------------------------------------------------------------------
report_undefined_symbol:
	movem.l	d0-d2/a0-a2,-(sp)               ; keep the registers
	lea	undefined_symbol_message(pc),a0 ; ' ?' message: undefined
	movem.l	d2-d3,2(a0)                     ; put the name in it
	pea	(a0)                            ; push the message
	moveq	#9,d1                           ; 10 characters
.pad_name:
	move.b	(a0),d0                         ; character
	bne.s	.store_char                     ; not zero
	moveq	#32,d0                          ; zero prints as a space
.store_char:
	move.b	d0,(a0)+                        ; store it
	dbra	d1,.pad_name                    ; next
	move.w	#$9,-(sp)                       ; Cconws
	trap	#1                              ; Cconws
	addq.l	#6,sp                           ; drop the arguments
	addq.w	#1,error_count                  ; count the error
	movem.l	(sp)+,d0-d2/a0-a2               ; restore the registers
	rts
undefined_symbol_message:
	dc.b	' ?12345678',0                  ; ' ?name': undefined symbol
	dc.b	$00
duplicate_symbol_message:
	dc.b	' +12345678',0                  ; ' +name': symbol defined twice
	dc.b	$00
out_of_range_message:
	dc.b	' >12345678',0                  ; ' >name': PC-relative target out of range
	dc.b	$00

;------------------------------------------------------------------------------
; Prints ' >' and the name of symbol a3 (zero bytes as spaces), counts an error and continues
; relocate_segment.
;------------------------------------------------------------------------------
report_out_of_range:
	movem.l	d0-d2/a0-a2,-(sp)               ; keep the registers
	lea	out_of_range_message(pc),a0     ; ' >' message: out of range
	move.l	(a3),2(a0)                      ; the symbol's name, first long
	move.l	4(a3),6(a0)                     ; second long
	pea	(a0)                            ; push the message
	moveq	#9,d1                           ; 10 characters
.pad_name:
	move.b	(a0),d0                         ; character
	bne.s	.store_char                     ; not zero
	moveq	#32,d0                          ; zero prints as a space
.store_char:
	move.b	d0,(a0)+                        ; store it
	dbra	d1,.pad_name                    ; next
	move.w	#$9,-(sp)                       ; Cconws
	trap	#1                              ; Cconws
	addq.l	#6,sp                           ; drop the arguments
	addq.w	#1,error_count                  ; count the error
	movem.l	(sp)+,d0-d2/a0-a2               ; restore the registers
	bra.w	relocate_segment                ; continue relocating

;------------------------------------------------------------------------------
; Reserves d0 bytes of free memory. Exit: a0 = their start; heap_pointer moved on. There is no limit check.
;------------------------------------------------------------------------------
allocate_memory:
	movea.l	heap_pointer(pc),a0             ; a0 = free memory
	add.l	d0,heap_pointer                 ; reserve d0 bytes; no limit check
	rts
obj_name_pointer:
	dc.l	default_obj_name                ; G3OBJ's value, default 'test.o'
prg_name_pointer:
	dc.l	default_prg_name                ; G3PRG's value, default 'TEST.PRG'
lib_name_pointer:
	dc.l	default_lib_name                ; G3LIB's value, default 'GFA3BLIB'

; The default names, stored as text in the code section and therefore shown as instructions: 'TEST.PRG' at
; $ade, 'GFA3BLIB' at $ae7 (lib_name_pointer points one byte into $ae6), 'test.o' at $af0.
default_prg_name:
	dc.b	'TEST.PRG',0                    ; G3PRG's default
default_lib_name:
	dc.b	'GFA3BLIB',0                    ; G3LIB's default

;------------------------------------------------------------------------------
; The default object file name test.o, shown as code.
;------------------------------------------------------------------------------
default_obj_name:
	moveq	#101,d2                         ; G3OBJ's default
	dc.b	'st.o',0
	dc.b	$00

	section	data
read_error_message:
	dc.b	'Lesefehler',0                  ; read error
	dc.b	$00
disk_full_message:
	dc.b	'Diskette voll',0               ; disk full
write_error_message:
	dc.b	'Schreibfehler',0               ; write error
program_header:
	dc.w	$601a                           ; program header: magic $601a
program_header_lengths:
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; text, data, BSS, symbol lengths; rest 0
	dc.w	$0000,$0000,$0000,$0000,$0000

	section	bss
library_name:	ds.b	100                     ; library name (G3LIB, '+name' or GFA3BLIB)
object_name_list:	ds.b	200             ; object file names, each zero-ended; empty name ends
error_count:	ds.b	2                       ; errors reported, the exit code
heap_pointer:	ds.b	4                       ; start of free memory
module_count:	ds.b	2                       ; modules loaded
symbol_list_start:	ds.b	4               ; start of the symbol list
object_header:	ds.b	2                       ; object header: magic word
object_header_lengths:	ds.b	26              ; object header: lengths
skip_first_object_flag:	ds.b	1               ; '#': leave out the G3OBJ file
write_symbols_flag:	ds.b	1               ; -S: write the symbol list
file_handle:	ds.b	2                       ; handle of the one open file
module_records:	ds.b	57600                   ; 1200 module records of 48 bytes
library_index:	ds.b	4                       ; the NDX file in memory
library_index_length:	ds.b	4               ; its length
bss_end:

	end
