; DATACOMP.TOS  -  a run-length packer for screen pictures
; Devpac source of the program, disassembled by Darren Birks, 11 November 2026.
; Text 1356 bytes, data 0 bytes, bss 122000 bytes, and a symbol table of 68 symbols.
;
; This source rebuilds DATACOMP.TOS byte for byte, header, symbol table, relocation table and all, with
;   vasmm68k_mot -devpac -m68000 -Ftos -o DATACOMP.TOS DATACOMP.S
;
; The original file keeps its author's symbols: 68 names of up to 8 capitals, all defined text symbols ($a200,
; the two buffers in the BSS too, by their offset from the text), sorted by name.  This source gives them as
; equates of offsets in the text, in reverse order (vasm writes its symbols last defined first), and every
; label of its own is local (starting with a full stop), so that nothing else goes into the table.  The
; original names are given in brackets in the comments.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; A TOS program found beside the L.S.D. Packer v1.2.  It asks Compress, Decompress or Quit:
;   Compress    loads a picture (up to $7f00 bytes: a 32000 byte screen and its palette), packs it with a
;               simple run-length code and saves it.
;   Decompress  loads a packed picture (up to 60000 bytes), unpacks it, shows it on the screen with its
;               palette, and saves it unpacked.
; Each load or save error has its message; Return goes back to the menu.
;
; Some things in it look unfinished:
;   - The message "Incorrect file format <not DPaint>" is never shown.
;   - load_file compares the bytes read with the bytes asked for and does nothing with it, so "Not enough
;     bytes loaded" is never shown either.
;   - The menu's text starts with a stray character 5.
;
;=======================================================================
; FILE FORMAT
;=======================================================================
; Packed picture: the unpacked length and the packed length (a long each), then runs: a count n from 0 to 127
; and n + 1 bytes as they are, or -n (n from 2 to 129, as a byte) and one byte to repeat n times.  The packed
; length counts the runs + 10, made even.
;
;=======================================================================


	opt	d+

	section	text

; The original program's symbol table, given as equates in reverse order so that it comes out the same.
WPERR	equ	*+$2f4
SVERT	equ	*+$368
SVERR	equ	*+$2f8
SVERM3	equ	*+$420
SVERM2	equ	*+$403
SVERM1	equ	*+$3e6
STRING	equ	*+$246
START	equ	*+$0
SCRNADRS	equ	*+$446
SAVEF	equ	*+$2a8
REP2	equ	*+$1d2
REP1	equ	*+$1bc
REP	equ	*+$1ba
PALST1	equ	*+$150
PALSET	equ	*+$150
OTFILE	equ	*+$f394
OFILEN	equ	*+$442
NOERR	equ	*+$96
NLFILE	equ	*+$34c
NEERR	equ	*+$354
LOADF	equ	*+$300
LDERT	equ	*+$358
LDERR	equ	*+$350
LDERM3	equ	*+$3c8
LDERM2	equ	*+$3b4
LDERM1	equ	*+$39e
INFILE	equ	*+$54c
IFILEN	equ	*+$43e
IFERM	equ	*+$378
GSADRS	equ	*+$252
FUNCB	equ	*+$471
FUNC	equ	*+$44a
FNOUT	equ	*+$4b6
FNOTB	equ	*+$4d0
FNINB	equ	*+$49e
FNIN	equ	*+$489
FLERR	equ	*+$a0
FLEREP	equ	*+$b0
FLER2	equ	*+$a6
FLER1	equ	*+$b4
DREP1	equ	*+$22e
DREP	equ	*+$228
DFNOUT	equ	*+$517
DFNOTB	equ	*+$533
DFNINB	equ	*+$4ff
DFNIN	equ	*+$4e8
DFERR	equ	*+$2fc
DECOM1	equ	*+$10a
DECOM	equ	*+$c4
DCOP	equ	*+$21c
DCMPRS	equ	*+$1fa
DCMPR	equ	*+$20c
DCMP2	equ	*+$23a
COP2	equ	*+$1ae
COP1	equ	*+$194
COP	equ	*+$190
CONIN	equ	*+$23c
CONBUF	equ	*+$262
CONB3	equ	*+$2a4
CONB2	equ	*+$27a
CONB1	equ	*+$270
COMPRS	equ	*+$15c
COM	equ	*+$2c
CMPR	equ	*+$178
CMP3	equ	*+$1f0
CMP2	equ	*+$1e0
CMP1	equ	*+$178
CDAEND	equ	*+$9a


;------------------------------------------------------------------------------
; start (START): Compress, Decompress or Quit.  Compress loads a picture (up to $7f00 bytes: a 32000 byte screen
; and its palette), run-length packs it and saves it; Decompress loads a packed picture (up to 60000
; bytes), unpacks it, shows it on the screen with its palette, and saves it unpacked.  Each error has its
; message, and Return goes back to the menu.
;------------------------------------------------------------------------------
.start:
	lea	.text_menu,a0                   ; "Compress/Decompress/Quit--(C/D/Q) >"
	bsr.w	.ask                            ; asked
	tst.b	d0                              ; anything?
	beq.w	.start                          ; no: again
	cmp.b	#$51,d1                         ; Q?
	beq.w	.quit                           ; yes: quit
	cmp.b	#$43,d1                         ; C?
	beq.w	.compress                       ; yes
	cmp.b	#$44,d1                         ; D?
	beq.w	.decompress                     ; yes
	bra.w	.start                          ; anything else: again
.compress:
	lea	.text_compress,a0               ; (COM) "File to compress >"
	bsr.w	.ask                            ; asked
	tst.b	d0                              ; anything?
	beq.w	.start                          ; no: the menu
	lea	.input_buffer,a1                ; into the input buffer
	lea	.compress_name,a0               ; the name
	move.l	#$7f00,d0                       ; $7f00 bytes at most
	bsr.w	.load_file                      ; loaded
	tst.b	d7                              ; an error?
	bne.w	.load_error                     ; yes
	bsr.w	.pack                           ; packed
	bsr.w	.get_screen                     ; the screen's address (not used here)
	lea	.text_compressed,a0             ; "Compressed filename >"
	bsr.w	.ask                            ; asked
	tst.b	d0                              ; anything?
	beq.w	.start                          ; no: the menu
	lea	.compressed_name,a0             ; the name
	lea	.output_buffer,a1               ; the packed data
	move.l	.output_length,d1               ; its length
	bsr.w	.save_file                      ; saved
	tst.b	d7                              ; an error?
	beq.w	.menu_again                     ; no
	lea	.save_errors,a0                 ; yes: the save errors
	bra.w	.show_error                     ; its message
.menu_again:
	bra.w	.start                          ; (NOERR) the menu
.quit:
	clr.w	-(sp)                           ; (CDAEND) Pterm0
	trap	#1                              ; Pterm0
	rts
.load_error:
	lea	.load_errors,a0                 ; (FLERR) the load errors
.show_error:
	clr.l	d6                              ; (FLER2) the error number
	move.b	d7,d6
	lsl.l	#2,d6                           ; * 4: longs
	adda.l	d6,a0                           ; its message
	movea.l	(a0),a0
	bsr.w	.print                          ; printed
.error_wait:
	bsr.w	.get_key                        ; (FLER1) a key
	cmp.b	#$d,d0                          ; Return?
	bne.w	.error_wait                     ; no: again
	bra.w	.start                          ; the menu
.decompress:
	lea	.text_decompress,a0             ; (DECOM) "File to decompress >"
	bsr.w	.ask                            ; asked
	tst.b	d0                              ; anything?
	beq.w	.start                          ; no: the menu
	lea	.output_buffer,a1               ; into the output buffer
	lea	.decompress_name,a0             ; the name
	move.l	#$ea60,d0                       ; 60000 bytes at most
	bsr.w	.load_file                      ; loaded
	tst.b	d7                              ; an error?
	bne.w	.load_error                     ; yes
	bsr.w	.get_screen                     ; the screen's address
	bsr.w	.unpack                         ; unpacked into the input buffer
	lea	.input_buffer,a0                ; the picture
	movea.l	.screen_address,a1              ; to the screen
	move.l	.output_buffer,d0               ; its unpacked length
.show_picture:
	move.b	(a0)+,(a1)+                     ; (DECOM1) copied
	subq.l	#1,d0
	bne.s	.show_picture
	lea	.input_palette,a4               ; its palette, after 32000 bytes
	bsr.w	.set_palette                    ; set
	lea	.text_decompressed,a0           ; "Decompressed filename >"
	bsr.w	.ask                            ; asked
	tst.b	d0                              ; anything?
	beq.w	.start                          ; no: the menu
	lea	.decompressed_name,a0           ; the name
	lea	.input_buffer,a1                ; the picture
	move.l	.output_buffer,d1               ; its unpacked length
	bsr.w	.save_file                      ; saved
	tst.b	d7                              ; an error?
	beq.w	.menu_again                     ; no: the menu
	lea	.save_errors,a0                 ; yes: the save errors
	bra.w	.show_error                     ; its message

;------------------------------------------------------------------------------
; set_palette (PALSET, PALST1): Setpalette(a4).
;------------------------------------------------------------------------------
.set_palette:	; from: .start
	move.l	a4,-(sp)                        ; the palette
	move.w	#$6,-(sp)
	trap	#14                             ; Setpalette
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; pack (COMPRS): run-length pack the input buffer into the output buffer: the unpacked length, the packed
; length, then runs: a count n from 0 to 127 and n + 1 bytes as they are, or -n (n from 2 to 129) and a
; byte to repeat n times.  The packed length (the runs, + 10, made even) goes into output_length.
;------------------------------------------------------------------------------
.pack:	; from: .start
	lea	.input_buffer,a0                ; the input
	lea	.output_buffer,a1               ; the output
	clr.l	d7                              ; the packed length so far
	move.l	.input_length,d4                ; the input length
	move.l	d4,(a1)+                        ; first in the output
	movea.l	a1,a3                           ; the packed length goes here
	addq.l	#4,a1
	subq.l	#1,a4                           ; (not used)
.pack_loop:
	tst.l	d4                              ; (CMP1, CMPR) all done?
	bmi.w	.pack_end                       ; yes
	tst.l	d4                              ; one byte left?
	beq.w	.pack_literals                  ; yes: as it is
	clr.l	d0
	move.b	(a0),d1                         ; this byte
	cmp.b	1(a0),d1                        ; the same as the next?
	beq.w	.pack_run                       ; yes: a run
.pack_literals:
	movea.l	a1,a2                           ; (COP) where the count goes
	addq.l	#1,a1
.pack_literal:
	move.b	(a0)+,(a1)+                     ; (COP1) copied
	subq.l	#1,d4                           ; one fewer
	bcs.w	.pack_literals_end              ; none left?
	addq.w	#1,d0                           ; counted
	tst.b	d0                              ; 128?
	bmi.w	.pack_literals_end              ; yes: enough
	move.b	(a0),d1                         ; the next byte
	cmp.b	1(a0),d1                        ; the same as the one after?
	bne.w	.pack_literal                   ; no: another literal
.pack_literals_end:
	subq.l	#1,d0                           ; (COP2) the count less one
	move.b	d0,(a2)                         ; stored
	add.l	d0,d7                           ; + the bytes
	addq.l	#2,d7                           ; + 2
	bra.w	.pack_loop
.pack_run:
	move.b	(a0)+,d1                        ; (REP) the byte
.pack_run_loop:
	addq.l	#1,a0                           ; (REP1) one more the same
	addq.l	#1,d0                           ; counted
	subq.l	#1,d4                           ; one fewer
	bcs.w	.pack_run_end                   ; none left?
	tst.b	d0
	bmi.w	.pack_run_end                   ; 128?
	cmp.b	(a0),d1                         ; the same again?
	beq.w	.pack_run_loop                  ; yes
.pack_run_end:
	subq.l	#1,d0                           ; (REP2)
	not.b	d0                              ; -(the run less one)
	move.b	d0,(a1)+                        ; stored
	move.b	d1,(a1)+                        ; the byte
	addq.l	#2,d7                           ; + 2
	bra.w	.pack_loop
.pack_end:
	addi.l	#$a,d7                          ; (CMP2) + 10
	btst	#$0,d7                          ; odd?
	beq.w	.pack_done                      ; no
	addq.l	#1,d7                           ; yes: even
.pack_done:
	move.l	d7,.output_length               ; (CMP3) the output's length
	move.l	d7,(a3)                         ; and in its header
	rts

;------------------------------------------------------------------------------
; unpack (DCMPRS): unpack the output buffer's runs into the input buffer.
;------------------------------------------------------------------------------
.unpack:	; from: .start
	lea	.output_buffer,a0               ; the packed data
	move.l	(a0)+,d4                        ; the unpacked length
	move.l	(a0)+,d5                        ; the packed length (not used)
	lea	.input_buffer,a1                ; the picture
	subq.l	#1,d4
.unpack_loop:
	tst.l	d4                              ; (DCMPR) all done?
	bmi.w	.unpack_done                    ; yes
	clr.l	d0
	move.b	(a0)+,d0                        ; the count
	tst.b	d0                              ; negative?
	bmi.w	.unpack_run                     ; yes: a run
.unpack_literal:
	move.b	(a0)+,(a1)+                     ; (DCOP) copied
	subq.l	#1,d4                           ; one fewer
	dbra	d0,.unpack_literal              ; count + 1 of them
	bra.w	.unpack_loop
.unpack_run:
	move.b	(a0)+,d1                        ; (DREP) the byte
	not.b	d0
	addq.w	#1,d0                           ; the run less one
.unpack_run_loop:
	move.b	d1,(a1)+                        ; (DREP1) stored
	subq.l	#1,d4                           ; one fewer
	dbra	d0,.unpack_run_loop
	bra.w	.unpack_loop
.unpack_done:
	rts                                     ; (DCMP2)

;------------------------------------------------------------------------------
; get_key (CONIN): Cnecin.
;------------------------------------------------------------------------------
.get_key:	; from: .start
	move.w	#$8,-(sp)
	trap	#1                              ; Cnecin
	addq.l	#2,sp
	rts

;------------------------------------------------------------------------------
; print (STRING): Cconws the text at a0.
;------------------------------------------------------------------------------
.print:	; from: .start
	move.l	a0,-(sp)                        ; the text
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	rts

;------------------------------------------------------------------------------
; get_screen (GSADRS): the screen's address into screen_address.
;------------------------------------------------------------------------------
.get_screen:	; from: .start
	move.w	#$2,-(sp)
	trap	#14                             ; Physbase
	addq.l	#2,sp
	move.l	d0,.screen_address              ; kept
	rts

;------------------------------------------------------------------------------
; ask (CONBUF): print the prompt at a0 and read a line into the Cconrs buffer after it.  d1 = its first
; character in capitals, d0 = its length, and the line is ended with a 0 for a file name.
;------------------------------------------------------------------------------
.ask:	; from: .start
	move.l	a0,-(sp)
	move.l	a0,-(sp)                        ; the prompt
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	movea.l	(sp)+,a0
.ask_find_end:
	tst.b	(a0)+                           ; (CONB1) past its end
	beq.w	.ask_read
	bra.w	.ask_find_end
.ask_read:
	move.l	a0,-(sp)                        ; (CONB2) the buffer after it
	move.l	a0,-(sp)
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	movea.l	(sp)+,a0
	clr.b	2(a0,d0.w)                      ; the line ended
	move.b	2(a0),d1                        ; its first character
	cmp.b	#$61,d1                         ; lower case?
	bcs.w	.ask_done
	cmp.b	#$7b,d1
	bcc.w	.ask_done
	andi.b	#$df,d1                         ; yes: in capitals
.ask_done:
	tst.b	d0                              ; (CONB3) anything?
	rts

;------------------------------------------------------------------------------
; save_file (SAVEF): save d1 bytes at a1 under the name at a0.  d7 = 0, or 1 when it cannot be created
; (write protected), 2 on a write error, 3 when the disk is full.
;------------------------------------------------------------------------------
.save_file:	; from: .start
	movea.l	a1,a4                           ; the data
	move.l	d1,d4                           ; its length
	move.w	#$0,-(sp)                       ; normal file
	move.l	a0,-(sp)
	move.w	#$3c,-(sp)
	trap	#1                              ; Fcreate
	addq.l	#8,sp
	tst.l	d0                              ; created?
	bmi.w	.save_protected                 ; no
	move.l	a4,-(sp)                        ; the data
	move.l	d4,-(sp)                        ; its length
	move.w	d0,-(sp)                        ; the handle
	move.w	d0,d6                           ; kept
	move.w	#$40,-(sp)
	trap	#1                              ; Fwrite
	adda.l	#$c,sp
	tst.l	d0                              ; written?
	bmi.w	.save_error                     ; no
	cmp.l	d4,d0                           ; all of it?
	bcs.w	.save_full                      ; no: the disk is full
	move.w	d6,-(sp)                        ; the handle
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.l	d0                              ; closed?
	bmi.w	.save_error                     ; no
	clr.l	d7                              ; 0
	rts
.save_protected:
	moveq	#1,d7                           ; (WPERR) 1
	rts
.save_error:
	moveq	#2,d7                           ; (SVERR) 2
	rts
.save_full:
	moveq	#3,d7                           ; (DFERR) 3
	rts

;------------------------------------------------------------------------------
; load_file (LOADF): load up to d0 bytes into a1 from the file named at a0; input_length = the bytes
; read.  d7 = 0, or 1 when it is not there, 2 on a read error.  The check for too few bytes is not made.
;------------------------------------------------------------------------------
.load_file:	; from: .start
	movea.l	a1,a4                           ; the buffer
	move.l	d0,d4                           ; the most
	move.w	#$0,-(sp)                       ; read only
	move.l	a0,-(sp)                        ; the name
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	tst.l	d0                              ; opened?
	bmi.w	.load_missing                   ; no
	move.w	d0,-(sp)                        ; the handle, for Fclose
	move.l	a4,-(sp)                        ; the buffer
	move.l	d4,-(sp)                        ; the most
	move.w	d0,-(sp)                        ; the handle
	move.w	#$3f,-(sp)
	trap	#1                              ; Fread
	adda.l	#$c,sp
	tst.l	d0                              ; read?
	bmi.w	.load_error_2                   ; no
	cmp.l	d0,d4                           ; fewer than asked? (nothing is done with it)
	move.l	d0,.input_length                ; the bytes read
	move.w	#$3e,-(sp)
	trap	#1                              ; Fclose
	addq.l	#4,sp
	tst.w	d0                              ; closed?
	bmi.w	.load_error_2                   ; no
	clr.l	d7                              ; 0
	rts
.load_missing:
	moveq	#1,d7                           ; (NLFILE) 1
	rts
.load_error_2:
	moveq	#2,d7                           ; (LDERR) 2
	rts
.load_short:
	moveq	#3,d7                           ; (NEERR) 3: never reached
	rts
.load_errors:	; from: .start
	dc.l	.text_not_present               ; (LDERT) the load errors' messages, for 1 to 3
	dc.l	.text_not_present
	dc.l	.text_load_error
	dc.l	.text_short
.save_errors:	; from: .start
	dc.l	.text_protected                 ; (SVERT) the save errors' messages, for 1 to 3
	dc.l	.text_protected
	dc.l	.text_save_error
	dc.l	.text_disk_full
.text_bad_format:
	dc.b	13,10,'Incorrect file format <not DPaint> ',0 ; (IFERM) not used
.text_not_present:
	dc.b	13,10,'File not present..!',0   ; (LDERM1)
.text_load_error:
	dc.b	13,10,'Load error .....!',0     ; (LDERM2)
.text_short:
	dc.b	13,10,'Not enough bytes loaded ..!',0 ; (LDERM3)
.text_protected:
	dc.b	13,10,'Disc write protected ....!',0 ; (SVERM1)
.text_save_error:
	dc.b	13,10,'Save file error .........!',0 ; (SVERM2)
.text_disk_full:
	dc.b	13,10,'Disk full error .........!',0 ; (SVERM3)
	dc.b	$00
.input_length:	; from: .pack
	dc.l	$00007f00                       ; (IFILEN) the bytes loaded
.output_length:	; from: .start, .pack
	dc.l	$00000000                       ; (OFILEN) the packed length
.screen_address:	; from: .start, .get_screen
	dc.l	$000f8000                       ; (SCRNADRS) the screen
.text_menu:	; from: .start
	dc.b	$05                             ; (FUNC) a stray character 5, then the prompt
	dc.b	13,10,'Compress/Decompress/Quit--(C/D/Q) >',0
.menu_line:
	dc.b	$14,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; (FUNCB) the Cconrs buffer: 20
                                                ;   characters
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00
.text_compress:	; from: .start
	dc.b	13,10,'File to compress >',0    ; (FNIN)
.compress_line:
	dc.w	$1400                           ; (FNINB) 20 characters
.compress_name:	; from: .start
	dcb.b	22,0
.text_compressed:	; from: .start
	dc.b	13,10,10,'Compressed filename  >',0 ; (FNOUT)
.compressed_line:
	dc.w	$1400                           ; (FNOTB) 20 characters
.compressed_name:	; from: .start
	dcb.b	22,0
.text_decompress:	; from: .start
	dc.b	13,10,'File to decompress >',0  ; (DFNIN)
.decompress_line:
	dc.b	$14,$00                         ; (DFNINB) 20 characters
.decompress_name:	; from: .start
	dcb.b	22,0
.text_decompressed:	; from: .start
	dc.b	13,10,10,'Decompressed filename  >',0 ; (DFNOUT)
.decompressed_line:
	dc.b	$14,$00                         ; (DFNOTB) 20 characters
.decompressed_name:	; from: .start
	dcb.b	23,0

	section	bss
.input_buffer:	ds.b	32000                   ; (INFILE) the picture: 32000 bytes of screen
.input_palette:	ds.b	29000                   ; then its palette
.output_buffer:	ds.b	61000                   ; (OTFILE) the packed data
.bss_end:

	end
