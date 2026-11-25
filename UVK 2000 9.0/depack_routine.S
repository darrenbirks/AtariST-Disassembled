; depack_routine.S  -  The Atomik 3.5 depacker
;
; Devpac source of the Atomik 3.5 depacker in Ultimate Virus Killer 2000 9.0 by Richard Karsmakers (C.R.I.M.E.
; Development, 2004), disassembled by Darren Birks, 30 October 2026. Atomik is by Altair (VMAX/MCS).
;
; UVK.LST holds this code as the INLINE block depack_routine% (464 bytes), and depack_routine.bin is those bytes.
; Assembled to a plain binary, this source gives depack_routine.bin byte for byte. The code is position independent.

;------------------------------------------------------------------------------
; Atomik 3.5 ("ATM5") depacker, called with RCALL from the BASIC program.
; Entry: a0 (RCALL array element 8) = address of the packed data: "ATM5", long unpacked length, long packed length,
; packed bytes.
; The data is depacked in place: it is decoded backwards from the end of the packed bytes into memory $80 bytes above
; the final position, then moved down so the unpacked data starts where the "ATM5" header was.
; Data without the "ATM5" mark is left alone. All registers are kept; nothing is returned.
; Bits are read from the bit buffer d7 (a marker bit tells when it is empty), bytes from the packed data backwards via
; a6;
; output is written backwards via a5. Work area at a2: -$1c byte-table flag, -$1b picture-mode flag, -$1a picture byte,
; -$19..-$13 seven plane steps, -$12..-$3 sixteen frequent bytes.
;------------------------------------------------------------------------------
atomik_depack:
	movem.l	d0-d7/a0-a6,-(sp)               ; keep all registers
	cmpi.l	#$41544d35,(a0)+                ; packed data starts with "ATM5"?
	bne.w	atomik_return                   ; no: return with the data unchanged
	link	a2,#-28                         ; 28-byte work area under a2
	move.l	(a0)+,d0                        ; d0 = unpacked length
	lea	4(a0,d0.l),a5                   ; a5 = end of the unpacked data (data start + unpacked length)
	move.l	d0,-(sp)                        ; keep the unpacked length for the final move
	movea.l	a5,a4                           ; a4 = that end
	lea	$80(a4),a5                      ; write the output $80 bytes higher, so it cannot overrun the packed
                                                ;   bytes still to be read
	lea	-$c(a4),a4                      ; a4 = end of the final unpacked data ($c header bytes lower)
	move.l	(a0)+,d0                        ; d0 = packed length
	movea.l	a0,a6                           ; a6 = start of the packed bytes
	adda.l	d0,a6                           ; a6 = end of the packed bytes
	subq.w	#1,a6                           ; last byte is not part of the bit stream
	move.b	-(a6),d7                        ; first byte of the bit buffer
	bra.w	atomik_read_chunk_header        ; read the first chunk header

;------------------------------------------------------------------------------
; Atomik depacker: a 1 bit was read, so a match follows. Decodes its length from the bit stream: up to d3 zero bits
; ended by a 1 bit give a short length, otherwise a 4-, 8- or 14-bit field gives a longer one. Length 0 means a short
; token: a 2-byte match or a single byte taken from the frequent-byte table or as a small difference from the previous
; byte.
; Entry: d3 = zero-bit count limit of this chunk, d7 = bit buffer, a6 = packed data, a5 = output, a2 = work area.
;------------------------------------------------------------------------------
atomik_read_match_length:
	move.w	d3,d5                           ; d5 = most zero bits to count
.count_zero_bits:
	add.b	d7,d7                           ; next bit into carry
.test_bit:
	dbcs	d5,.count_zero_bits             ; count zero bits until a 1 bit or the limit
	beq.s	.refill_count                   ; bit buffer empty: refill and go on
	bcc.s	.long_length                    ; limit reached without a 1 bit: longer length field
	sub.w	d3,d5                           ; d5 = number of zero bits read
	neg.w	d5                              ; = the length
	bra.s	.have_length                    ; have the length
.long_length:
	moveq	#3,d6                           ; read 4 bits
	bsr.s	atomik_read_bits
	beq.s	.length_byte                    ; 0: try a byte field
	bra.s	.add_base_length                ; length = field + limit
.length_byte:
	moveq	#7,d6                           ; read 8 bits
	bsr.s	atomik_read_bits
	beq.s	.length_word                    ; 0: a 14-bit field
	addi.w	#$f,d5                          ; lengths above the 4-bit range start at 15
	bra.s	.add_base_length
.refill_count:
	move.b	-(a6),d7                        ; next byte of the packed data
	addx.b	d7,d7                           ; shift in the marker bit
	bra.s	.test_bit                       ; go on counting
.length_word:
	moveq	#13,d6                          ; read 14 bits
	bsr.s	atomik_read_bits
	addi.w	#$10e,d5                        ; lengths above the 8-bit range start at $10e
.add_base_length:
	add.w	d3,d5                           ; add the zero-bit limit
.have_length:
	lea	atomik_offset_tables(pc),a4     ; a4 = offset tables
	move.w	d5,d2                           ; d2 = length
	bne.s	atomik_match_offset_class       ; length > 0: normal match with a 3-bit offset class
	add.b	d7,d7                           ; length 0: next bit says which short token
	bne.s	.short_token_bit
	move.b	-(a6),d7                        ; refill the bit buffer
	addx.b	d7,d7
.short_token_bit:
	bcs.s	.single_byte                    ; 1: single byte
	moveq	#1,d6                           ; 0: 2-byte match with a 2-bit offset class
	bra.s	atomik_copy_match
.single_byte:
	moveq	#3,d6                           ; read a 4-bit value
	bsr.s	atomik_read_bits
	tst.b	-$1c(a2)                        ; chunk has a frequent-byte table?
	beq.s	.delta_byte                     ; no: difference from the previous byte
	move.b	-$12(a2,d5.w),-(a5)             ; yes: write the table byte
	bra.w	atomik_check_chunk_end          ; next token
.delta_byte:
	move.b	(a5),d0                         ; d0 = previous output byte
	btst	#$3,d5                          ; bit 3 set: the 4-bit difference is negative
	bne.s	.negative_delta
	bra.s	.store_delta_byte
.negative_delta:
	addi.b	#$f0,d5                         ; sign-extend the difference to a byte
.store_delta_byte:
	sub.b	d5,d0                           ; byte = previous byte - difference
	move.b	d0,-(a5)                        ; write it
	bra.w	atomik_check_chunk_end          ; next token

;------------------------------------------------------------------------------
; Atomik depacker: reads d6+1 bits from the bit buffer, most significant first.
; Entry: d6 = number of bits - 1, d7 = bit buffer, a6 = packed data (read backwards).
; Exit: d5 = the value, flags set from it (Z when 0).
;------------------------------------------------------------------------------
atomik_read_bits:
	clr.w	d5                              ; value = 0
.next_bit:
	add.b	d7,d7                           ; next bit into carry/X
	beq.s	.refill                         ; buffer empty: refill
.shift_in:
	addx.w	d5,d5                           ; shift the bit into the value
	dbra	d6,.next_bit                    ; for all d6+1 bits
	tst.w	d5                              ; Z when the value is 0
	rts
.refill:
	move.b	-(a6),d7                        ; next byte of the packed data
	addx.b	d7,d7                           ; shift in the marker bit
	bra.s	.shift_in

;------------------------------------------------------------------------------
; Atomik depacker: a match of length 1 or more takes its offset class from 3 bits.
; Entry: d2 = match length - 1 (bytes copied = d2 + 2), a4 = offset tables.
;------------------------------------------------------------------------------
atomik_match_offset_class:
	moveq	#2,d6                           ; read 3 bits for the offset class

;------------------------------------------------------------------------------
; Atomik depacker: reads the offset class (d6+1 bits) and the offset, then copies d2+2 bytes from that far above
; the output pointer. In picture mode the low 4 bits of the offset are coded separately, through the plane step table.
; Entry: d6 = class bits - 1, d2 = count - 2, a4 = offset tables (bases at $1b5f6, bit counts at $1b604), a5 = output.
;------------------------------------------------------------------------------
atomik_copy_match:
	bsr.s	atomik_read_bits                ; read the offset class
	move.w	d5,d4                           ; d4 = class
	move.b	$e(a4,d4.w),d6                  ; d6 = offset bits for the class
	ext.w	d6
	tst.b	-$1b(a2)                        ; picture mode on in this chunk?
	bne.s	.picture_offset                 ; yes
	addq.w	#4,d6                           ; no: 4 more offset bits
	bra.s	.plain_offset                   ; read the offset
.picture_offset:
	bsr.s	atomik_read_bits                ; read the high part of the offset
	move.w	d5,d1
	lsl.w	#4,d1                           ; shifted above the low nibble
	moveq	#2,d6                           ; read 3 bits for the low nibble
	bsr.s	atomik_read_bits
	dc.w	$ba3c,$0007                     ; cmp.b	#$7,d5, cmp.b #7,d5: 0-6 select a plane step
	blt.s	.use_plane_step
	moveq	#0,d6                           ; 7: one more bit
	bsr.s	atomik_read_bits
	beq.s	.use_picture_byte               ; 0: low nibble = picture byte
	moveq	#2,d6                           ; 1: read 3 bits
	bsr.s	atomik_read_bits
	add.w	d5,d5                           ; times 2
	or.w	d1,d5                           ; combine with the high part
	bra.s	.add_class_base
.use_picture_byte:
	or.b	-$1a(a2),d1                     ; low nibble = picture byte
	bra.s	.set_offset
.use_plane_step:
	or.b	-$19(a2,d5.w),d1                ; low nibble = plane step d5
.set_offset:
	move.w	d1,d5                           ; d5 = offset
	bra.s	.add_class_base
.plain_offset:
	bsr.s	atomik_read_bits                ; read the offset bits
.add_class_base:
	add.w	d4,d4                           ; class 0?
	beq.s	.copy_start                     ; yes: no base
	add.w	-$2(a4,d4.w),d5                 ; add the class base offset
.copy_start:
	lea	1(a5,d5.w),a4                   ; a4 = source of the copy (above the output)
	move.b	-(a4),-(a5)                     ; copy the first byte
.copy_loop:
	move.b	-(a4),-(a5)                     ; copy the rest, d2+1 bytes
	dbra	d2,.copy_loop
	bra.s	atomik_check_chunk_end          ; next token

;------------------------------------------------------------------------------
; Atomik depacker main loop: reads a bit; 1 means a match follows, 0 a literal byte, which is copied straight from
; the packed data to the output. Falls into the end-of-chunk check.
;------------------------------------------------------------------------------
atomik_next_token:
	add.b	d7,d7                           ; next bit
	bne.s	.test_token                     ; buffer empty?
	move.b	-(a6),d7                        ; refill
	addx.b	d7,d7
.test_token:
	bcs.s	atomik_decode_match             ; 1: match
	move.b	-(a6),-(a5)                     ; 0: copy a literal byte

;------------------------------------------------------------------------------
; Atomik depacker: checks whether the current chunk is complete (output pointer a5 reached a3) and whether all
; packed data is read (a6 back at the start a0); falls into the next chunk header otherwise.
;------------------------------------------------------------------------------
atomik_check_chunk_end:
	cmpa.l	a5,a3                           ; chunk output complete?
	bne.s	atomik_next_token               ; no: next token
	cmpa.l	a6,a0                           ; all packed data read?
	beq.s	atomik_finish                   ; yes: finish

;------------------------------------------------------------------------------
; Atomik depacker: reads the header of the next chunk from the packed data. A 1 bit switches picture mode on and is
; followed by the picture byte, from which the table of seven plane steps (odd values 1,3,5... skipping the picture
; byte)
; is built; a second 1 bit is followed by a table of 16 frequent bytes. Then come the zero-bit limit for match lengths
; (d3) and the word length of the chunk output; a3 is set to where the chunk ends.
;------------------------------------------------------------------------------
atomik_read_chunk_header:
	moveq	#0,d6                           ; read 1 bit: picture mode?
	bsr.w	atomik_read_bits
	beq.s	.no_picture_mode                ; no
	move.b	-(a6),d0                        ; picture byte
	lea	-$1a(a2),a1                     ; a1 = picture byte and plane steps
	move.b	d0,(a1)+                        ; store the picture byte
	moveq	#1,d1                           ; steps start at 1
	moveq	#6,d2                           ; 7 steps
.build_step_table:
	cmp.b	d0,d1                           ; step equal to the picture byte?
	bne.s	.store_step
	addq.w	#2,d1                           ; skip it
.store_step:
	move.b	d1,(a1)+                        ; store the step
	addq.w	#2,d1                           ; next odd value
	dbra	d2,.build_step_table
	st	-$1b(a2)                        ; picture mode on
	bra.s	.check_byte_table
.no_picture_mode:
	sf	-$1b(a2)                        ; picture mode off
.check_byte_table:
	moveq	#0,d6                           ; read 1 bit: frequent-byte table?
	bsr.w	atomik_read_bits
	beq.s	.no_byte_table                  ; no
	lea	-$12(a2),a1                     ; a1 = table of 16 bytes
	moveq	#15,d0                          ; 16 bytes
.read_byte_table:
	move.b	-(a6),(a1)+                     ; copy them from the packed data
	dbra	d0,.read_byte_table
	st	-$1c(a2)                        ; table present
	bra.s	.read_chunk_size
.no_byte_table:
	sf	-$1c(a2)                        ; no table
.read_chunk_size:
	clr.w	d3                              ; d3 = zero-bit limit for match lengths
	move.b	-(a6),d3
	move.b	-(a6),d0                        ; d0 = length of the chunk output, high byte
	lsl.w	#8,d0
	move.b	-(a6),d0                        ; low byte
	movea.l	a5,a3                           ; a3 = end of this chunk in the output
	suba.w	d0,a3
	bra.s	atomik_next_token               ; depack the chunk

;------------------------------------------------------------------------------
; Atomik depacker: branch to the match decoder (atomik_read_match_length).
;------------------------------------------------------------------------------
atomik_decode_match:
	bra.w	atomik_read_match_length        ; decode a match

;------------------------------------------------------------------------------
; Atomik depacker: all data depacked; moves the result down over the header and removes the work area.
;------------------------------------------------------------------------------
atomik_finish:
	move.l	(sp)+,d0                        ; d0 = unpacked length
	bsr.w	atomik_move_down                ; move the data down to the header address
	unlk	a2                              ; drop the work area

;------------------------------------------------------------------------------
; Atomik depacker exit: restores all registers and returns.
;------------------------------------------------------------------------------
atomik_return:
	movem.l	(sp)+,d0-d7/a0-a6               ; restore all registers
	rts

; Atomik depacker offset tables. Seven words: base offset of offset classes 1-7 ($20, $60, $160, $360, $760, $f60,
; $1f60);
; class 0 starts at 0. At $1b604 eight bytes: number of offset bits - 4 for classes 0-7 (0,1,3,4,5,6,7,8); without
; picture
; mode 4 is added, so class 0 has 5 bits (offsets 0-31), class 1 6 bits (32-95) and so on.
atomik_offset_tables:
	dc.w	$0020,$0060,$0160,$0360,$0760,$0f60,$1f60,$0001 ; class base offsets 1-7, then offset bits per class
	dc.w	$0304,$0506,$0708               ; class base offsets 1-7, then offset bits per class

;------------------------------------------------------------------------------
; Atomik depacker: moves the depacked data down to its final place, in 16-byte blocks.
; Entry: d0 = unpacked length, a5 = start of the depacked data, a6 = start of the packed bytes ($c above the header).
;------------------------------------------------------------------------------
atomik_move_down:
	lsr.l	#4,d0                           ; blocks of 16 bytes (minus one: rounded up)
	lea	-$c(a6),a6                      ; a6 = header start: destination
.copy_loop:
	move.l	(a5)+,(a6)+                     ; copy 16 bytes
	move.l	(a5)+,(a6)+
	move.l	(a5)+,(a6)+
	move.l	(a5)+,(a6)+
	dbra	d0,.copy_loop                   ; next block
	rts
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000 ; unused
