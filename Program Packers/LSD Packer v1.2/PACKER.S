; PACKER.TOS  -  The L.S.D. Packer v1.2
; Devpac source of the program, disassembled by Darren Birks, 11 November 2026.
; Text 3004 bytes, data 0 bytes, bss 0 bytes.
;
; This source rebuilds PACKER.TOS byte for byte, header, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o PACKER.TOS PACKER.S
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; "Welcome to the L.S.D. Packer v1.2.  Written by L.S.D., January 1989.  This version created on 18th January
; 1989."  A TOS program that asks its way through: the offset (how far ahead to look for strings, in hex,
; $1000 by default), whether the file is a program or data, how a packed program flashes while it depacks
; (the background, the text or not at all), whether its relocation is suppressed, then the source and
; destination files.  It packs in supervisor mode, flashing the background with the bits as it goes.
;
; A program is written as the stub (a PRG of its own, its text length set to cover the packed data too), the
; packed data and an empty relocation table; the stub depacks, relocates and starts the original.  A data
; file is written as the packed data and 'END!'.
;
; The menu's answers are patched into the stub: the flash instruction becomes a write to colour 15 or three
; nops, and with relocation suppressed two branches skip the relocation and the clearing of the BSS.
;
; Some things in it look unfinished:
;   - The packed data's checksum is worked out by the stub but never checked.
;   - In the offset, capital hex letters come out 4 too high, and 'a' is refused (parse_hex, hex_letter).
;   - The stub finds the relocation table after the text and data without counting a symbol table, and clears
;     from the BSS only up to the end of the depacked data.
;   - The counts of each code are gathered and loaded into d0-d5 at the end, but not used.
;
;=======================================================================
; LAYOUT
;=======================================================================
;   $0000-$0457  the dialogue and the file handling
;   $0458-$05f3  the cruncher
;   $05f4-$0891  the stub, with its PRG header, its depacker and its variables
;   $0892-$0bbb  the cruncher's tables and variables, the line buffers and the texts
;
;=======================================================================
; FILE FORMATS
;=======================================================================
; Packed data: longs of bits, written from the start up and read by the stub from the end down; the last two
; longs are the checksum (eor of the bit longs) and the unpacked length.  Codes, in the order they are read:
;   0 0 nnn         1 to 8 literals            1 00 o*9        a 3 byte string
;   0 1 o*8         a 2 byte string            1 01 o*10       a 4 byte string
;   1 11 n*8        9 to 264 literals          1 10 l*8 o*12   a string of 5 to 256 bytes
;
;=======================================================================


	section	text

;------------------------------------------------------------------------------
; The start-up: keep the program, then the dialogue: the offset, the kind of file, the flash and relocation
; options, the source file (loaded whole), the crunch in supervisor mode, then the destination file, written
; as a program (the stub, the packed data and an empty relocation table) or as data ('END!' after it).
;------------------------------------------------------------------------------
start:
	movea.l	sp,a5                           ; the basepage
	movea.l	4(a5),a5
	move.l	$c(a5),d0                       ; text length
	add.l	$14(a5),d0                      ; + data length
	add.l	$1c(a5),d0                      ; + BSS length
	addi.l	#$200,d0                        ; + 512
	move.l	d0,-(sp)                        ; to keep
	move.l	a5,-(sp)                        ; from the basepage
	move.w	#$0,-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	adda.l	#$c,sp
next_file:
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	move.l	d0,old_ssp                      ; the old stack, kept
	move.l	#$1000,offset                   ; the offset: $1000 unless another is given
	move.w	$fff8240,old_colour             ; palette 0, the background colour, kept
	movea.l	#text_welcome,a0                ; "Welcome to the L.S.D. Packer v1.2"...
	bsr.w	print                           ; printed
ask_offset:
	movea.l	#text_newline,a0                ; a new line
	bsr.w	print                           ; printed
	movea.l	#text_offset,a0                 ; "Enter offset (default is 1000):"
	bsr.w	print                           ; printed
	move.l	#offset_line,-(sp)              ; up to 4 characters
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	cmp.w	#$4,d0                          ; more than 4?
	bgt.s	ask_offset                      ; yes: again
	cmp.w	#$0,d0                          ; none?
	beq.w	ask_kind                        ; yes: $1000
	move.l	#$0,d1                          ; the count
	move.b	d0,d1
	move.l	#offset_text,d0                 ; the digits
	bsr.w	parse_hex                       ; in hex
	tst.l	d2                              ; a digit not hex?
	bmi.s	ask_offset                      ; yes: again
	move.l	d2,offset                       ; the offset
ask_kind:
	movea.l	#text_newline,a0                ; a new line
	bsr.w	print                           ; printed
	movea.l	#text_kind,a0                   ; "1) Crunch Executable..., 2) Crunch data file"
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; the key
	cmp.b	#$31,d0                         ; 1?
	beq.w	ask_flash                       ; yes: an executable
	cmp.b	#$32,d0                         ; 2?
	bne.s	ask_kind                        ; no: again
	move.b	#$1,data_flag                   ; data
	bra.w	ask_source                      ; no flash or relocation options
ask_flash:
	movea.l	#text_newline,a0                ; a new line
	bsr.w	print                           ; printed
	movea.l	#text_flash,a0                  ; "1) Flash background..., 2) Flash text..., 3) No flash"
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; the key
	cmp.b	#$31,d0                         ; 1: the background, as the stub has it
	beq.s	ask_relocation
	cmp.b	#$32,d0                         ; 2?
	beq.s	flash_text                      ; yes
	cmp.b	#$33,d0                         ; 3?
	bne.s	ask_flash                       ; no: again
	bra.s	no_flash
flash_text:
	move.w	#$ffff,stub_flash+2             ; move.w d0,$ffff825e: colour 15, the text
	move.w	#$825e,stub_flash+4
	bra.s	ask_relocation
no_flash:
	move.w	#$4e71,stub_flash               ; nop
	move.w	#$4e71,stub_flash+2             ; nop
	move.w	#$4e71,stub_flash+4             ; nop
ask_relocation:
	movea.l	#text_newline,a0                ; a new line
	bsr.w	print                           ; printed
	movea.l	#text_relocation,a0             ; "Supress relocation after decrunch (y/N):"
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; the key
	cmp.b	#$d,d0                          ; Return?
	beq.w	ask_source                      ; yes: no
	or.b	#$20,d0                         ; lower case
	cmp.b	#$6e,d0                         ; n?
	beq.s	ask_source                      ; yes
	cmp.b	#$79,d0                         ; y?
	bne.s	ask_relocation                  ; no: again
	move.w	#$6044,stub_relocate            ; bra.s: the stub skips the relocation
	move.w	#$600c,stub_clear_bss           ; bra.s: and the BSS clearing
ask_source:
	movea.l	#text_newline,a0                ; a new line
	bsr.w	print                           ; printed
	movea.l	#text_source,a0                 ; "Enter name of source file:"
	bsr.w	print                           ; printed
	move.l	#source_line,-(sp)              ; the line buffer
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	movea.l	#source_name,a1                 ; the name
	adda.w	d0,a1                           ; + its length
	move.b	#$0,(a1)                        ; ended
	movea.l	#text_newline,a0                ; a new line
	bsr.w	print                           ; printed
	move.l	#dta,-(sp)                      ; a DTA of our own
	move.w	#$1a,-(sp)
	trap	#1                              ; Fsetdta
	addq.l	#6,sp
	move.w	#$0,-(sp)                       ; normal files
	move.l	#source_name,-(sp)              ; the name
	move.w	#$4e,-(sp)
	trap	#1                              ; Fsfirst
	addq.l	#8,sp
	tst.l	d0                              ; found?
	bne.s	ask_source                      ; no: again
	move.l	dta_length,-(sp)                ; its length
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0                              ; got it?
	bmi.w	no_memory                       ; no
	move.l	d0,buffer                       ; the buffer: the source
	move.l	d0,output                       ; and where the packed data goes
	move.w	#$2,-(sp)                       ; read and write
	move.l	#source_name,-(sp)              ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.w	d0,handle                       ; the handle
	tst.l	d0                              ; opened?
	bmi.w	quit                            ; no: quit
	move.l	buffer,-(sp)                    ; into the buffer
	move.l	dta_length,-(sp)                ; the whole file
	move.w	handle,-(sp)                    ; the handle
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	adda.l	#$c,sp
	tst.l	d0                              ; read?
	bmi.w	quit                            ; no: quit
	bsr.w	close_file                      ; closed
	move.l	dta_length,d1                   ; the length
	add.l	buffer,d1                       ; + the buffer
	move.l	d1,source_end                   ; the source's end
	movea.l	#text_crunching,a0              ; "Wait a while - now crunching!"
	bsr.w	print                           ; printed
	bsr.w	crunch
	move.w	old_colour,$fff8240             ; palette 0, the background colour back
	move.l	old_ssp,-(sp)                   ; Super(old stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
ask_destination:
	movea.l	#text_destination,a0            ; "Enter name of destination file:"
	bsr.w	print                           ; printed
	move.l	#destination_line,-(sp)         ; the line buffer
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	cmp.b	#$0,d0                          ; nothing?
	beq.s	ask_destination                 ; yes: again
	movea.l	#destination_name,a1            ; the name
	adda.w	d0,a1                           ; + its length
	move.b	#$0,(a1)                        ; ended
	movea.l	#text_newline,a0                ; a new line
	jsr	print                           ; printed
	move.b	data_flag,d0                    ; data?
	cmp.b	#$1,d0
	beq.w	write_data                      ; yes
	movea.l	#$29e,a4                        ; the stub's length, with its header
	movea.l	a3,a5                           ; + the packed length
	adda.l	a4,a5
	suba.l	#$1c,a5                         ; less the header
	move.l	a5,stub_text_length             ; is the text length in the stub's header
	bsr.w	create_file                     ; Fcreate
	movea.l	#stub,a5                        ; the stub
	movea.l	#$29e,a6                        ; $29e bytes
	bsr.w	write_file                      ; written
	movea.l	buffer,a5                       ; the packed data
	movea.l	a3,a6                           ; its length
	bsr.w	write_file                      ; written
	movea.l	#empty_relocation,a5            ; a 0 long: no relocation
	movea.l	#$4,a6                          ; 4 bytes
	bsr.w	write_file                      ; written
	bsr.w	close_file                      ; closed
	bra.w	ask_again
write_data:
	bsr.w	create_file                     ; Fcreate
	movea.l	buffer,a5                       ; the packed data
	movea.l	a3,a6                           ; its length
	bsr.w	write_file                      ; written
	movea.l	#text_end_mark,a5               ; 'END!'
	movea.l	#$4,a6                          ; 4 bytes
	bsr.w	write_file                      ; written
	bsr.w	close_file                      ; closed
ask_again:
	movea.l	#text_newline,a0                ; a new line
	bsr.w	print                           ; printed
	movea.l	#text_again,a0                  ; "Crunch another file (Y/n):"
	bsr.w	print                           ; printed
	bsr.w	get_key                         ; the key
	or.b	#$20,d0                         ; lower case
	cmp.b	#$6e,d0                         ; n?
	beq.s	quit                            ; yes: quit
	move.l	buffer,-(sp)                    ; the buffer
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	tst.l	d0                              ; freed?
	bne.w	quit                            ; no: quit
	move.b	#$0,data_flag                   ; a program again
	bra.w	next_file                       ; the next file
no_memory:
	movea.l	#text_no_memory,a0              ; "Could not allocate enough memory"
	bsr.w	print                           ; printed
	bsr.w	wait_key                        ; wait for a key
quit:	; from: create_file, write_file, close_file
	clr.w	-(sp)
	trap	#1                              ; Pterm0

;------------------------------------------------------------------------------
; create_file: Fcreate the destination; quits on an error.
;------------------------------------------------------------------------------
create_file:	; from: start
	move.w	#$0,-(sp)                       ; normal file
	move.l	#destination_name,-(sp)         ; the destination
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	tst.l	d0                              ; created?
	bmi.s	quit                            ; no: quit
	move.w	d0,handle                       ; the handle
	rts

;------------------------------------------------------------------------------
; write_file: Fwrite a6 bytes from a5; quits on an error.
;------------------------------------------------------------------------------
write_file:	; from: start
	move.l	a5,-(sp)                        ; the data
	move.l	a6,-(sp)                        ; the length
	move.w	handle,-(sp)                    ; the handle
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	adda.l	#$c,sp
	tst.l	d0                              ; written?
	bmi.s	quit                            ; no: quit
	rts

;------------------------------------------------------------------------------
; close_file: Fclose; quits on an error.
;------------------------------------------------------------------------------
close_file:	; from: start
	move.w	handle,-(sp)                    ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	bmi.s	quit                            ; closed?
	rts

;------------------------------------------------------------------------------
; get_key: Cconin, d0 = the key.
;------------------------------------------------------------------------------
get_key:	; from: start
	move.w	#$1,-(sp)
	trap	#1                              ; Cconin
	addq.l	#2,sp
	rts

;------------------------------------------------------------------------------
; wait_key: Crawcin.
;------------------------------------------------------------------------------
wait_key:	; from: start
	move.w	#$7,-(sp)
	trap	#1                              ; Crawcin
	addq.l	#2,sp
	rts

;------------------------------------------------------------------------------
; print: Cconws the text at a0.
;------------------------------------------------------------------------------
print:	; from: start
	move.l	a0,-(sp)                        ; the text
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; parse_hex: d2 = the d1 hex digits at d0, read from the last; -1 when one is not a hex digit.
;------------------------------------------------------------------------------
parse_hex:	; from: start
	movea.l	d0,a1                           ; the digits
	adda.l	d1,a1                           ; past the last
	sub.b	#$1,d1                          ; one done first
	clr.l	d3
	clr.l	d4                              ; the last digit
	move.b	-(a1),d3
	cmp.b	#$30,d3                         ; below '0'?
	blt.s	parse_hex_bad                   ; yes: -1
	cmp.b	#$39,d3                         ; a decimal digit?
	ble.s	parse_hex_units                 ; yes
	bsr.w	hex_letter                      ; no: a letter
parse_hex_units:
	sub.l	#$30,d3                         ; its value
	move.l	d3,d2                           ; the units
	move.l	#$10,d4                         ; the next place: 16
parse_hex_loop:
	move.b	-(a1),d3                        ; the next digit back
	cmp.b	#$30,d3                         ; below '0'?
	blt.s	parse_hex_bad                   ; yes: -1
	cmp.b	#$39,d3                         ; a decimal digit?
	ble.s	parse_hex_digit                 ; yes
	bsr.w	hex_letter                      ; no: a letter
parse_hex_digit:
	sub.l	#$30,d3                         ; its value
	mulu.w	d4,d3                           ; * the place
	add.l	d3,d2                           ; added
	lsl.l	#4,d4                           ; the next place
	sub.b	#$1,d1                          ; one done
	clr.l	d3
	cmp.b	#$0,d1                          ; all done?
	bne.s	parse_hex_loop                  ; no
	rts
parse_hex_bad:	; from: hex_letter
	move.l	#$ffffffff,d2                   ; -1
	rts

;------------------------------------------------------------------------------
; hex_letter: d3 = a letter's value + '0' (A-F or a-f); anything else gives -1 from parse_hex.  Capitals
; come out 4 too high ('A' - 3 is '0' + 14), and 'a' itself is refused while anything above it passes.
;------------------------------------------------------------------------------
hex_letter:	; from: parse_hex
	cmp.b	#$46,d3                         ; upper case?
	ble.w	hex_upper                       ; yes
	cmp.b	#$61,d3                         ; above 'a'?
	bgt.s	hex_lower                       ; yes: lower case
	bra.s	parse_hex_bad                   ; no: -1
hex_upper:
	sub.b	#$3,d3                          ; less 3 (7 would make 'A' '0' + 10)
	rts
hex_lower:
	sub.b	#$27,d3                         ; 'a' - 39 = '0' + 10
	rts

;------------------------------------------------------------------------------
; crunch: pack the source (buffer_start to source_end) into the same buffer from its start up, the packed
; data trailing behind the source.  At each byte it takes the longest string found within the offset ahead,
; else a literal.  The codes are bits gathered into longs (d2, with a marker bit); after them come the
; longs' checksum (eor) and the unpacked length, which the stub reads first, from the end down.
; a3 = the packed length on return.
;------------------------------------------------------------------------------
crunch:	; from: start
	movea.l	buffer,a0                       ; the source
	movea.l	source_end,a1                   ; its end
	movea.l	output,a2                       ; where the packed data goes
	moveq	#1,d2                           ; the bit marker: no bits yet
	clr.w	d1                              ; no literals yet
	clr.l	d7                              ; the checksum
crunch_loop:
	bsr.w	crunch_find                     ; a string or a literal
	tst.b	d0                              ; a literal?
	beq.s	crunch_next                     ; no
	addq.w	#1,d1                           ; one more
	cmpi.w	#$108,d1                        ; 264, the most a run holds?
	bne.s	crunch_next                     ; no
	bsr.w	put_literal_count               ; yes: its count put
crunch_next:
	cmpa.l	a0,a1                           ; to the end?
	bgt.s	crunch_loop                     ; no: on
	bsr.w	put_literal_count               ; the last literals' count
	bsr.w	put_last_bits                   ; the last bits
	move.l	d7,(a2)+                        ; the checksum
	movea.l	buffer,a0                       ; the buffer
	movea.l	source_end,a1                   ; the source's end
	move.l	a1,d2
	sub.l	a0,d2                           ; less the buffer
	move.l	d2,(a2)+                        ; the unpacked length, last
	clr.l	d0
	clr.l	d1
	clr.l	d2
	clr.l	d3
	clr.l	d4
	clr.l	d5
	lea	kind_counts,a3                  ; the counts of each code
	movem.w	(a3)+,d0-d5                     ; into d0-d5 (not used)
	movea.l	a2,a3                           ; the end of the packed data
	suba.l	a0,a3                           ; less its start: the packed length
	lea	source_end,a4
	suba.l	a2,a4                           ; (not used)
	rts

;------------------------------------------------------------------------------
; crunch_find: put the longest string at a0 that is found again within the offset ahead (2 to 256 bytes,
; each length with its own furthest offset), or count a literal: d0 = 0 for a string, 1 for a literal.
;------------------------------------------------------------------------------
crunch_find:	; from: crunch
	movea.l	a0,a3                           ; how far to look
	adda.l	offset,a3
	cmpa.l	a1,a3                           ; past the end?
	ble.s	find_start                      ; no
	movea.l	a1,a3                           ; yes: the end
find_start:
	moveq	#1,d5                           ; the best so far: 1
	movea.l	a0,a5
	addq.w	#1,a5                           ; from the next byte
find_next:
	move.b	(a0),d3                         ; this byte
	move.b	1(a0),d4                        ; and the next
find_first:
	cmp.b	(a5)+,d3                        ; the first byte?
	bne.s	find_on                         ; no
	cmp.b	(a5),d4                         ; the second too?
	beq.s	find_compare_start              ; yes
find_on:
	cmpa.l	a5,a3                           ; up to the limit
	bgt.s	find_first
	bra.w	find_done                       ; none
find_compare_start:
	subq.w	#1,a5                           ; back to the first byte
	movea.l	a0,a4                           ; from here
find_compare:
	move.b	(a4)+,d3
	cmp.b	(a5)+,d3                        ; the same?
	bne.s	find_compared                   ; no
	cmpa.l	a5,a3                           ; up to the limit
	bgt.s	find_compare
find_compared:
	move.l	a4,d3                           ; the length
	sub.l	a0,d3
	subq.l	#1,d3
	cmp.l	d3,d5                           ; longer than the best?
	bge.s	find_more                       ; no
	move.l	a5,d4                           ; the offset:
	sub.l	a0,d4                           ; the distance
	sub.l	d3,d4                           ; less the length
	subq.w	#1,d4                           ; less one
	cmp.l	#$4,d3                          ; more than 4?
	ble.s	find_short                      ; no
	moveq	#6,d6                           ; kind 3, as a word index
	cmp.l	#$101,d3                        ; more than 256?
	blt.s	find_long                       ; no
	move.w	#$100,d3                        ; yes: 256
find_long:
	bra.s	find_kind
find_short:
	move.w	d3,d6                           ; 2, 3 or 4
	subq.w	#2,d6                           ; kinds 0, 1 and 2
	lsl.w	#1,d6                           ; as word indexes
find_kind:
	lea	code_table,a6                   ; the codes' table
	cmp.w	0(a6,d6.w),d4                   ; within the kind's furthest offset?
	bge.s	find_more                       ; no
	move.l	d3,d5                           ; the best: its length
	move.l	d4,match_offset                 ; its offset
	move.b	d6,match_kind                   ; its kind
find_more:
	cmpa.l	a5,a3                           ; up to the limit
	bgt.s	find_next
find_done:
	cmp.l	#$1,d5                          ; nothing found?
	beq.s	find_literal                    ; yes: a literal
	bsr.w	put_literal_count               ; the literals' count first
	move.b	match_kind,d6                   ; the kind
	move.l	match_offset,d3                 ; the offset
	move.w	8(a6,d6.w),d0                   ; the offset's bits
	bsr.w	put_bits                        ; put
	move.w	$10(a6,d6.w),d0                 ; the length's bits (kind 3 only)
	beq.s	find_put_code                   ; none
	move.l	d5,d3                           ; the length
	subq.w	#1,d3                           ; less one
	bsr.w	put_bits                        ; put
find_put_code:
	move.w	$18(a6,d6.w),d0                 ; the code's bits
	move.w	$20(a6,d6.w),d3                 ; the code
	bsr.w	put_bits                        ; put
	addi.w	#$1,$28(a6,d6.w)                ; counted
	adda.l	d5,a0                           ; past the string
	clr.b	d0                              ; 0: a string
	rts
find_literal:
	move.b	(a0)+,d3                        ; the byte
	moveq	#8,d0                           ; 8 bits
	bsr.w	put_bits                        ; put
	moveq	#1,d0                           ; 1: a literal
	rts

;------------------------------------------------------------------------------
; put_literal_count: the count of the literals just put (d1), with its code: 00 and 3 bits for 1 to 8,
; 111 and 8 bits for 9 to 264.
;------------------------------------------------------------------------------
put_literal_count:	; from: crunch, crunch_find
	tst.w	d1                              ; any?
	beq.s	put_literal_none                ; no
	move.w	d1,d3                           ; the count
	clr.w	d1                              ; none now
	cmp.w	#$9,d3                          ; 9 or more?
	bge.s	put_literal_long                ; yes
	addq.w	#1,short_runs                   ; counted
	subq.w	#1,d3                           ; 1 to 8 as 0 to 7
	moveq	#5,d0                           ; 5 bits: 00 and the count
	bra.w	put_bits
put_literal_none:
	rts
put_literal_long:
	addq.w	#1,long_runs                    ; counted
	subi.w	#$9,d3                          ; 9 to 264 as 0 to 255
	or.w	#$700,d3                        ; the code 111 above it
	moveq	#11,d0                          ; 11 bits
	bra.w	put_bits

;------------------------------------------------------------------------------
; put_bits: the low d0 bits of d3, lowest first, into d2; each full long is written.
;------------------------------------------------------------------------------
put_bits:	; from: crunch_find, put_literal_count
	subq.w	#1,d0                           ; less one
put_bits_loop:	; from: put_last_bits
	lsr.l	#1,d3                           ; the next bit
	roxl.l	#1,d2                           ; into the long
	bcs.s	put_long                        ; the marker out: full
	dbra	d0,put_bits_loop                ; for each bit
	rts

;------------------------------------------------------------------------------
; put_last_bits: write the long so far, as it is.
;------------------------------------------------------------------------------
put_last_bits:	; from: crunch
	clr.w	d0                              ; no more bits
put_long:	; from: put_bits
	move.l	d2,(a2)+                        ; written
	move.w	d2,$ff8240                      ; palette 0, palette 0, flashed
	eor.l	d2,d7                           ; the checksum
	moveq	#1,d2                           ; a new long: the marker
	dbra	d0,put_bits_loop                ; the rest of the bits
	rts

;------------------------------------------------------------------------------
; The stub put in front of a packed program: a PRG header whose text length is set to the stub's code and
; the packed data together, and the code below.  It clears the top of the screen and prints "PLEASE WAIT -
; DECOMPACTING.", depacks the program $300 bytes into its own text flashing the background (or the text, or
; not at all, as patched), relocates it (unless patched off), sets the basepage, and runs a mover from the
; screen that copies it down, clears from the BSS to the depacked data's end (unless patched off) and
; starts it.  The relocation table is found after the text and data, without the symbols.
;------------------------------------------------------------------------------
stub:	; from: start
	dc.w	$601a                           ; the stub's PRG header
stub_text_length:	; from: start
	dc.l	$00000282                       ; its text length, put in
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; the rest of the header
	dc.w	$0000,$0000,$ffff
stub_start:
	movea.l	4(sp),a5                        ; the basepage
	movea.l	$10(a5),a1                      ; the data segment: the packed data's end
	lea	stub_packed_end(pc),a2
	move.l	a1,(a2)                         ; kept
	movea.l	8(a5),a1                        ; the text segment
	lea	stub_text(pc),a2
	move.l	a1,(a2)                         ; kept: where the program will run
	adda.l	#$300,a1                        ; + $300
	lea	stub_output(pc),a2
	move.l	a1,(a2)                         ; is where it depacks to
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp
	lea	stub_screen(pc),a1
	move.l	d0,(a1)                         ; kept
	movea.l	d0,a2                           ; the screen
	move.w	#$17d,d1                        ; 1536 bytes
stub_clear:
	clr.l	(a2)+                           ; cleared
	dbra	d1,stub_clear
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp
	cmp.b	#$0,d0                          ; low?
	beq.w	stub_print                      ; yes
	lea	stub_column(pc),a1              ; no: column 25 instead of 6
	move.b	#$39,(a1)
stub_print:
	lea	stub_text_message(pc),a1        ; "PLEASE WAIT - DECOMPACTING."
	move.l	a1,-(sp)
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	lea	stub_ssp(pc),a6
	move.l	d0,(a6)                         ; the old stack, kept
	bsr.w	stub_depack                     ; depack
	move.w	stub_colour(pc),$fff8240        ; palette 0, palette 0, the colour back
	move.l	stub_ssp(pc),-(sp)              ; Super(old stack)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	movea.l	stub_text(pc),a5                ; the text segment
	suba.l	#$100,a5                        ; less $100: the basepage
	movea.l	stub_output(pc),a3              ; the depacked program's header
stub_relocate:	; from: start
	movea.l	2(a3),a0                        ; its text length (patched to a bra.s without relocation)
	adda.l	6(a3),a0                        ; + data length
	adda.l	#$1c,a0                         ; + the header
	adda.l	a3,a0                           ; a0 = its relocation table
	move.l	8(a5),d0                        ; the text segment: where it runs
	movea.l	stub_output(pc),a1              ; the depacked program
	adda.l	#$1c,a1                         ; its text
	tst.l	(a0)                            ; any relocation?
	beq.w	stub_relocated                  ; no
	adda.l	(a0)+,a1                        ; the first address
stub_relocate_long:
	add.l	d0,(a1)                         ; relocated
stub_relocate_next:
	clr.l	d1
	move.b	(a0)+,d1                        ; the next step
	tst.w	d1                              ; the end?
	beq.w	stub_relocated                  ; yes
	cmp.b	#$1,d1                          ; 1: 254 on?
	bne.w	stub_relocate_step              ; no
	adda.l	#$fe,a1                         ; yes
	bra.s	stub_relocate_next
stub_relocate_step:
	adda.l	d1,a1                           ; on to the next long
	bra.s	stub_relocate_long
stub_relocated:
	movea.l	stub_output(pc),a3              ; the header
	move.l	2(a3),$c(a5)                    ; text length
	move.l	6(a3),$14(a5)                   ; data length
	move.l	$a(a3),$1c(a5)                  ; BSS length
	move.l	8(a5),d0                        ; the text segment
	move.l	$c(a5),d1
	add.l	d0,d1
	move.l	d1,$10(a5)                      ; = the data segment
	move.l	$14(a5),d0
	add.l	d0,d1
	move.l	d1,$18(a5)                      ; = the BSS
	move.l	stub_screen(pc),d0              ; the screen
	add.l	#$7f00,d0                       ; + $7f00
	movea.l	d0,a2                           ; where the mover goes
	movea.l	d0,a5                           ; and runs
	move.l	#$30,d2                         ; 49 bytes
	lea	stub_mover(pc),a1               ; the mover
stub_copy_mover:
	move.b	(a1)+,(a2)+                     ; copied
	dbra	d2,stub_copy_mover
	movea.l	stub_output(pc),a1              ; the depacked program
	movea.l	a1,a4
	adda.l	#$1c,a1                         ; its text
	move.l	stub_length(pc),d2              ; the unpacked length
	divu.w	#$8,d2                          ; in 8 bytes
	addq.l	#1,d2                           ; and one more
	movea.l	stub_text(pc),a4                ; where it runs
	movea.l	a4,a3
	movea.l	stub_output_end(pc),a6          ; the depacked data's end
	jmp	(a5)                            ; run the mover
stub_mover:
	move.l	(a1)+,(a3)+                     ; copy the program down
	move.l	(a1)+,(a3)+
	dbra	d2,stub_mover
stub_clear_bss:	; from: start
	movea.l	4(sp),a1                        ; the basepage (patched to a bra.s that keeps the BSS)
	movea.l	$18(a1),a3                      ; its BSS
stub_clear_bss_loop:
	clr.l	(a3)+                           ; cleared
	cmpa.l	a6,a3                           ; up to the depacked data's end
	blt.s	stub_clear_bss_loop
stub_start_program:
	jmp	(a4)                            ; start the program

;------------------------------------------------------------------------------
; stub_depack: depack from the end of the packed data down.  The last long is the unpacked length, then the
; checksum (worked out but never checked), then the codes:
;  0 0 nnn         nnn + 1 literals (1 to 8)          1 01 o*10      a 4 byte string
;  0 1 o*8         a 2 byte string                    1 10 l*8 o*12  a string of l + 1 bytes
;  1 00 o*9        a 3 byte string                    1 11 n*8       n + 9 literals (9 to 264)
; a string's offset counts from the output position, which goes down.
;------------------------------------------------------------------------------
stub_depack:	; from: stub
	lea	stub_colour(pc),a2              ; the background colour
	move.w	$fff8240,(a2)                   ; palette 0, kept
	movea.l	stub_packed_end(pc),a0          ; the packed data's end
	movea.l	stub_output(pc),a1              ; the output's start
	movea.l	-(a0),a2                        ; the unpacked length
	lea	stub_length(pc),a3
	move.l	a2,(a3)                         ; kept
	adda.l	a1,a2                           ; + the start: the output's end
	lea	stub_output_end(pc),a3
	move.l	a2,(a3)                         ; kept
	move.l	-(a0),d5                        ; the checksum
	move.l	-(a0),d0                        ; the first long of bits
	eor.l	d0,d5
stub_flash:	; from: start
	move.w	d0,$fff8240                     ; palette 0, flash: patched to colour 15 (the text) or to nops
	lsr.l	#1,d0                           ; the next bit
	bne.s	stub_bit_got                    ; the long still has bits
	bsr.w	stub_next_long                  ; no: the next long
stub_bit_got:
	bcs.s	stub_code                       ; 1: a longer code
	moveq	#8,d1                           ; 0: 8 bit offset
	moveq	#1,d3                           ; 2 bytes
	lsr.l	#1,d0                           ; the next bit
	bne.s	stub_bit_2
	bsr.w	stub_next_long
stub_bit_2:
	bcs.s	stub_offset                     ; 1: a 2 byte string
	moveq	#3,d1                           ; 0: 3 bits of count
	clr.w	d4
stub_literals:
	bsr.w	stub_get_bits                   ; the count
	move.w	d2,d3                           ; + the base
	add.w	d4,d3
stub_literal:
	moveq	#7,d1                           ; 8 bits
stub_literal_bit:
	lsr.l	#1,d0                           ; the next bit
	bne.s	stub_literal_bit_got
	bsr.w	stub_next_long
stub_literal_bit_got:
	roxl.l	#1,d2                           ; into the byte
	dbra	d1,stub_literal_bit
	move.b	d2,-(a2)                        ; stored, downwards
	dbra	d3,stub_literal                 ; for each literal
	bra.w	stub_depack_next
stub_long_literals:
	moveq	#8,d1                           ; 8 bits of count
	moveq	#8,d4                           ; + 9
	bra.s	stub_literals
stub_code:
	moveq	#2,d1                           ; 2 bits
	bsr.w	stub_get_bits
	cmp.b	#$2,d2                          ; 0 or 1?
	blt.s	stub_short_string               ; yes
	cmp.b	#$3,d2                          ; 3?
	beq.s	stub_long_literals              ; yes: long literals
	moveq	#8,d1                           ; 2: 8 bits of length
	bsr.w	stub_get_bits
	move.w	d2,d3                           ; the length less one
	move.w	#$c,d1                          ; 12 bit offset
	bra.w	stub_offset
stub_short_string:
	move.w	#$9,d1                          ; 9 or 10 bit offset
	add.w	d2,d1
	addq.w	#2,d2                           ; 3 or 4 bytes
	move.w	d2,d3                           ; less one
stub_offset:
	bsr.w	stub_get_bits                   ; the offset
stub_copy:
	subq.w	#1,a2                           ; down one
	move.b	0(a2,d2.w),(a2)                 ; from the offset back
	dbra	d3,stub_copy                    ; for each byte
stub_depack_next:
	cmpa.l	a2,a1                           ; all depacked?
	blt.w	stub_flash                      ; no
	rts

;------------------------------------------------------------------------------
; stub_next_long: the next long of bits, with the marker in the x flag shifted in at the top.
;------------------------------------------------------------------------------
stub_next_long:	; from: stub_depack
	move.l	-(a0),d0                        ; the next long down
	eor.l	d0,d5                           ; the checksum
	move.w	#$10,ccr                        ; x set
	roxr.l	#1,d0                           ; the marker in, the first bit out
	rts

;------------------------------------------------------------------------------
; stub_get_bits: d2 = the next d1 bits.
;------------------------------------------------------------------------------
stub_get_bits:	; from: stub_depack
	subq.w	#1,d1                           ; less one
	clr.w	d2
stub_get_bits_loop:
	lsr.l	#1,d0                           ; the next bit
	bne.s	stub_get_bits_got               ; the long still has bits
	move.l	-(a0),d0                        ; no: the next long
	eor.l	d0,d5                           ; the checksum
	move.w	#$10,ccr                        ; x set
	roxr.l	#1,d0                           ; the marker in
stub_get_bits_got:
	roxl.l	#1,d2                           ; into d2
	dbra	d1,stub_get_bits_loop           ; for each bit
	rts
stub_ssp:	; from: stub
	dc.l	$00000000                       ; the stack Super returned
stub_packed_end:	; from: stub, stub_depack
	dc.l	$00000000                       ; the packed data's end
stub_output:	; from: stub, stub_depack
	dc.l	$00000000                       ; where it depacks to
stub_length:	; from: stub, stub_depack
	dc.l	$00000000                       ; the unpacked length
stub_text:	; from: stub
	dc.l	$00000000                       ; where the program runs
stub_colour:	; from: stub, stub_depack
	dc.w	$0000                           ; the background colour
stub_output_end:	; from: stub, stub_depack
	dc.l	$00000000                       ; the depacked data's end
stub_screen:	; from: stub
	dc.l	$00000000                       ; the screen
stub_text_message:	; from: stub
	dc.w	$1b59                           ; ESC Y: row 0, column 6
	dc.b	$20
stub_column:	; from: stub
	dc.b	'&PLEASE WAIT - DECOMPACTING.',0 ; , the column: & (6), or 9 (25) out of low resolution, then the text
	dc.w	$0000,$0000                     ; the stub's end
match_offset:	; from: crunch_find
	dc.l	$00000000                       ; the best string's offset
match_kind:	; from: crunch_find
	dc.w	$0000                           ; and kind, as a word index
code_table:	; from: crunch_find
	dc.w	$0100,$0200,$0400,$1000         ; for each kind (2, 3, 4, 5 to 256 bytes): the offsets it reaches
	dc.w	$0008,$0009,$000a,$000c         ; the offset's bits
	dc.w	$0000,$0000,$0000,$0008         ; the length's bits
	dc.w	$0002,$0003,$0003,$0003         ; the code's bits
	dc.w	$0001,$0004,$0005,$0006         ; the code
kind_counts:	; from: crunch
	dc.w	$0000,$0000,$0000,$0000         ; how many of each kind
short_runs:	; from: put_literal_count
	dc.w	$0000                           ; literal runs of 1 to 8
long_runs:	; from: put_literal_count
	dc.w	$0000                           ; literal runs of 9 or more
old_ssp:	; from: start
	dc.l	$00000000                       ; the stack Super returned
old_colour:	; from: start
	dc.w	$0000                           ; the background colour
empty_relocation:	; from: start
	dc.l	$00000000,$00000000             ; a 0 long: no relocation
buffer:	; from: start, crunch
	dc.l	$00000000                       ; the buffer: the source
output:	; from: start, crunch
	dc.l	$00000000                       ; where the packed data goes
source_end:	; from: start, crunch
	dc.l	$00000000
handle:	; from: start, create_file, write_file, close_file
	dc.w	$0000                           ; the file handle
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000 ; not used
offset:	; from: start, crunch_find
	dc.l	$00001000                       ; how far ahead to look for strings
data_flag:	; from: start
	dc.b	$00                             ; 1: crunch a data file
	dc.b	$00
dta:	; from: start
	dcb.b	26,0                            ; the DTA
dta_length:	; from: start
	dcb.b	18,0                            ; its file length
source_line:	; from: start
	dc.w	$3000                           ; Cconrs: 48 characters at most
source_name:	; from: start
	dcb.b	48,0
destination_line:	; from: start
	dc.w	$3000                           ; Cconrs: 48 characters at most
destination_name:	; from: start, create_file
	dcb.b	48,0
offset_line:	; from: start
	dc.w	$0500                           ; Cconrs: 5 characters at most
offset_text:	; from: start
	dc.w	$0000,$0000,$0000
text_newline:	; from: start
	dc.w	$0a0d
	dc.b	$00
text_source:	; from: start
	dc.b	10,13,'Enter name of source file:',0
text_destination:	; from: start
	dc.b	10,13,'Enter name of destination file:',0
text_offset:	; from: start
	dc.b	'Enter offset (default is 1000):',0
text_no_memory:	; from: start
	dc.b	'Could not allocate enough memory',10,13,0
text_crunching:	; from: start
	dc.b	10,13,'Wait a while - now crunching!',10,13,0
text_kind:	; from: start
	dc.b	10,13,'1) Crunch Executable .PRG, .TOS or .TTP file',10,13
	dc.b	'2) Crunch data file',10,13,'Choose:',0
text_flash:	; from: start
	dc.b	10,13,'1) Flash background screen when unpacking',10,13
	dc.b	'2) Flash text when unpacking (only in Low Res)',10,13,'3) No flash',10
	dc.b	13,'Choose:',0
text_relocation:	; from: start
	dc.b	10,13,'Supress relocation after decrunch (y/N):',0
text_welcome:	; from: start
	dc.b	27,'EWelcome to the L.S.D. Packer v1.2',10,13,10,13
	dc.b	'Written by L.S.D., January 1989.',10,13
	dc.b	'This version created on 18th January 1989',10,13,10,13,0
text_again:	; from: start
	dc.b	10,13,'Crunch another file (Y/n):',0
text_end_mark:	; from: start
	dc.b	'END!',0                        ; 'END!', after a data file

	section	bss
bss_end:

	end
