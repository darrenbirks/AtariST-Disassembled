;-----------------------------------------------------------------------
; MEDPROT4.S - The Medway Boys Protector IV boot sector, "Improved By The BBC!".
; Devpac source of the boot sector, disassembled by Darren Birks, 13 November 2026.
;
; Taken from Superior menu 166 disk A (SUP_166A.MSA).  The sector is
; executable (word sum $1234) and is not encoded.
;
; What it does:
; 1. Sets colour 15 to white and shows its title.
; 2. Looks for a reset-resident program: the magic $12123456 at each
;    512-byte boundary from phystop down.  Found: "RESET RESIDENT prog in
;    memory / It is MORE than likely a VIRUS !!" on red.
; 3. Otherwise looks at resvalid: $31415926 there means a reset vector is
;    set.  "The RESET VECTOR has been changed / It MAY be a virus" on red.
; 4. Either way it offers F1 Continue (the boot goes on) or F2 Clear
;    (resvalid and resvector cleared, the reset-resident magic cleared,
;    then a reset through the ROM's reset address).
; 5. Nothing found: "You are FREE of viruses !" on purple for about 0.75
;    seconds, $263c0000 put at $140 (vector 80, not used by TOS), the
;    colours put back, and the boot goes on.
;
; Things that look wrong:
; - With 4 Mb (phystop $400000) the search starts at $3ffffc, so it looks
;   4 bytes below each 512-byte boundary and never finds a program.
; - F2 tests d0 (the scan code) where d7 was set for it, so it always
;   clears the long at a5 and resets.  After the reset vector message a5
;   is whatever TOS left in it, so a long somewhere is cleared.
; - read_key is never called, and has no rts.
; - The bytes from $1e7 ("Backschat", a new line, ESC q, a new line) are
;   not used: they are left from the FastCopy boot sector the disk had.
;
; Build: vasm -devpac -no-opt -Fbin (or Devpac with no optimising):
; exact encodings matter (cmp.w #0,d0, cmpa.l #0,a0, the .w branches).
;-----------------------------------------------------------------------

	opt	o-

; boot sector header and BPB (little-endian words)

boot	bra.s	start			; $601c
	dc.b	$90,'IBM  '		; filler
	dc.b	$96,$86,$0b		; serial number
	dc.b	$00,$02			; 512 bytes a sector
	dc.b	$02			; 2 sectors a cluster
	dc.b	$01,$00			; 1 reserved sector
	dc.b	$02			; 2 FATs
	dc.b	$30,$00			; 48 directory entries
	dc.b	$a0,$05			; 1440 sectors
	dc.b	$f9			; media byte
	dc.b	$03,$00			; 3 sectors a FAT
	dc.b	$09,$00			; 9 sectors a track
	dc.b	$02,$00			; 2 sides
	dc.b	$00,$00			; no hidden sectors

; 1. the title, white text

start	lea	$ffff8240.w,a6		; the palette
	move.w	#$777,30(a6)		; colour 15 white
	lea	title_text(pc),a0
	bsr.w	print

; 2. a reset-resident program: $12123456 at a 512-byte boundary

	movea.l	$42e.w,a0		; phystop
	cmpa.l	#$3ffffc,a0		; below 4 Mb?
	ble.s	find_resident		; yes: from phystop
	lea	-4(a0),a0		; no: from 4 bytes below it
find_resident
	movea.l	a0,a1
	cmpi.l	#$12123456,(a1)+	; the reset-resident magic?
	beq.s	resident_found		; yes
	lea	-512(a0),a0		; the next boundary down
	cmpa.l	#0,a0			; down to 0?
	bgt.s	find_resident		; no

; 3. a reset vector set?

	cmpi.l	#$31415926,$426.w	; resvalid
	beq.s	reset_vector_set	; yes

; 5. nothing found

	move.w	#$404,(a6)		; purple
	lea	free_text(pc),a0	; "You are FREE of viruses !"
	bsr.s	print
	move.l	#$50000,d0		; about 0.75 seconds
wait	subq.l	#1,d0
	bne.s	wait
	move.l	#$263c0000,$140.w	; into vector 80
continue
	move.w	#$777,(a6)		; the background white
	move.w	#0,30(a6)		; colour 15 black
	rts				; the boot goes on

reset_vector_set
	move.w	#$400,(a6)		; red
	lea	reset_vector_text(pc),a0
	bsr.s	print
	clr.w	d7			; no program to clear
	bra.s	ask

resident_found
	movea.l	a0,a5			; the magic's place
	move.w	#$400,(a6)		; red
	move.w	#1,d7			; a program to clear
	lea	resident_text(pc),a0
	bsr.s	print

; 4. F1 Continue or F2 Clear

ask	lea	keys_text(pc),a0	; "F1 Continue", "F2 Clear"
	bsr.s	print
ask_key	move.w	#7,-(sp)		; Crawcin
	trap	#1
	addq.l	#2,sp
	swap	d0			; the scan code
	cmpi.b	#$3b,d0			; F1?
	beq.s	continue		; yes
	cmpi.b	#$3c,d0			; F2?
	bne.s	ask_key			; no: another key
	clr.l	$426.w			; resvalid cleared
	clr.l	$42a.w			; resvector cleared
	cmp.w	#0,d0			; meant for d7: d0 is $3c here
	beq.s	continue		; (never)
	clr.l	(a5)+			; the magic cleared
	movea.l	$4.w,a0			; the ROM's reset address
	jmp	(a0)			; reset

; print the text at a0 (Cconws)

print	move.l	a0,-(sp)
	move.w	#9,-(sp)		; Cconws
	trap	#1
	addq.l	#6,sp
	rts

; a key (Crawcin), its scan code in the low word (not used, and with no rts)

read_key
	move.w	#7,-(sp)		; Crawcin
	trap	#1
	addq.l	#2,sp
	swap	d0

; the texts: ESC E clears the screen, ESC f hides the cursor, ESC Y row column

title_text
	dc.b	27,'E',27,'f'
	dc.b	27,'Y',32+0,32+5,'The Medway Boys Protector IV'
	dc.b	27,'Y',32+2,32+10,'Improved By The BBC!',0
free_text
	dc.b	27,'Y',32+10,32+8,'You are FREE of viruses !',0
reset_vector_text
	dc.b	27,'Y',32+6,32+3,'The RESET VECTOR has been changed'
	dc.b	27,'Y',32+8,32+11,'It MAY be a virus',0
resident_text
	dc.b	27,'Y',32+6,32+13,'RESET RESIDENT prog in memory'
	dc.b	27,'Y',32+8,32+11,'It is MORE than likely a VIRUS !!',0
keys_text
	dc.b	27,'Y',32+12,32+12,'F1 Continue'
	dc.b	27,'Y',32+14,32+12,'F2 Clear',0

; not used: left from the FastCopy boot sector

	dc.b	'Backschat     ',13,10,27,'q',13,10,0
	dc.b	$07,$00

	dc.w	$a167			; makes the sector sum $1234
