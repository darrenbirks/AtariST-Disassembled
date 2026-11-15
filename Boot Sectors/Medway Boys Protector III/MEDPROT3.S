;-----------------------------------------------------------------------
; MEDPROT3.S - The Medway Boys Protector III boot sector.
; Devpac source of the boot sector, disassembled by Darren Birks, 14 November 2026.
;
; Taken from the L.L.S. cartridge (LLS.BIN, at $5400 of the cartridge),
; whose format command writes it, with this BPB, on the disks it formats
; (80 tracks, 10 sectors, 2 sides).  The sector is executable (word sum
; $1234) and is not encoded.
;
; What it does:
; 1. Sets colour 15 to white and shows its title.
; 2. Looks for a reset-resident program: the magic $12123456 at each
;    512-byte boundary from phystop down.  Found: "RESET RESIDENT prog in
;    memory / It is MORE than likely a VIRUS !!" on red, then F1 Continue
;    (the boot goes on) or F2 Clear Virus (resvalid, resvector and the
;    magic cleared, then a reset through the ROM's reset address).
; 3. Otherwise looks at resvalid: $31415926 there means a reset vector is
;    set.  "The RESET VECTOR has been changed / It MAY be a virus" on red,
;    then F1 Continue or F2 Clear vector (resvalid and resvector cleared),
;    and the boot goes on.
; 4. Nothing found: "You are FREE of viruses !" on blue for about 0.75
;    seconds, then a white background with black text, and the boot goes
;    on.
;
; Things that look wrong:
; - The search starts at phystop itself, past the end of memory.  With
;   4 Mb (phystop $400000) that read is a bus error.  (Protector IV starts
;   4 bytes lower instead, and so misses every boundary.)
;
; The bytes from $1f5 (" (c) TS &") are not used.
;
; Build: vasm -devpac -no-opt -Fbin (or Devpac with no optimising):
; exact encodings matter (the .l addresses, suba.l #$200,a0, cmpa.l #0,a0,
; the .w branches).
;-----------------------------------------------------------------------

	opt	o-

; boot sector header and BPB (little-endian words)

boot	bra.s	start			; $601c
	dc.b	$90,'IBM  '		; filler
	dc.b	$fe,$3f,$9d		; serial number
	dc.b	$00,$02			; 512 bytes a sector
	dc.b	$02			; 2 sectors a cluster
	dc.b	$01,$00			; 1 reserved sector
	dc.b	$02			; 2 FATs
	dc.b	$80,$00			; 128 directory entries
	dc.b	$40,$06			; 1600 sectors
	dc.b	$f9			; media byte
	dc.b	$03,$00			; 3 sectors a FAT
	dc.b	$0a,$00			; 10 sectors a track
	dc.b	$02,$00			; 2 sides
	dc.b	$00,$00			; no hidden sectors

; 1. the title, white text

start	lea	$ff8240,a6		; the palette
	move.w	#$777,30(a6)		; colour 15 white
	lea	title_text(pc),a0
	bsr.w	print

; 2. a reset-resident program: $12123456 at a 512-byte boundary

	movea.l	$42e.l,a0		; phystop
find_resident
	movea.l	a0,a1
	cmpi.l	#$12123456,(a1)+	; the reset-resident magic?
	beq.w	resident_found		; yes
	suba.l	#$200,a0		; the next boundary down
	cmpa.l	#0,a0			; down to 0?
	bgt.s	find_resident		; no

; 3. a reset vector set?

	move.l	$426.w,d0		; resvalid
	cmp.l	#$31415926,d0		; set?
	beq.w	reset_vector_set	; yes

; 4. nothing found

	move.w	#$004,(a6)		; blue
	lea	free_text(pc),a0	; "You are FREE of viruses !"
	bsr.w	print
	move.l	#$50000,d1		; about 0.75 seconds
wait	subq.l	#1,d1
	bne.s	wait
continue
	move.w	#$777,(a6)		; the background white
	move.w	#0,30(a6)		; colour 15 black
	rts				; the boot goes on

reset_vector_set
	move.w	#$400,(a6)		; red
	lea	reset_vector_text(pc),a0
	bsr.w	print
vector_key
	bsr.w	get_key
	cmpi.b	#$3b,d0			; F1?
	beq.s	continue		; yes
	cmpi.b	#$3c,d0			; F2?
	bne.s	vector_key		; no: another key
	clr.l	$426.w			; resvalid cleared
	clr.l	$42a.w			; resvector cleared
	bra.s	continue

resident_found
	movea.l	a0,a5			; the magic's place
	move.w	#$400,(a6)		; red
	lea	resident_text(pc),a0
	bsr.w	print
resident_key
	bsr.w	get_key
	cmpi.b	#$3b,d0			; F1?
	beq.s	continue		; yes
	cmpi.b	#$3c,d0			; F2?
	bne.s	resident_key		; no: another key
	clr.l	$426.w			; resvalid cleared
	clr.l	$42a.w			; resvector cleared
	clr.l	(a5)+			; the magic cleared
	movea.l	$4.l,a0			; the ROM's reset address
	jmp	(a0)			; reset

; print the text at a0 (Cconws)

print	move.l	a0,-(sp)
	move.w	#9,-(sp)		; Cconws
	trap	#1
	addq.l	#6,sp
	rts

; a key (Crawcin), its scan code in the low word

get_key	move.w	#7,-(sp)		; Crawcin
	trap	#1
	addq.l	#2,sp
	swap	d0			; the scan code
	rts

; the texts: ESC Y row column

title_text
	dc.b	27,'Y',32+0,32+5,'The Medway Boys Protector III',0
free_text
	dc.b	27,'Y',32+10,32+8,'You are FREE of viruses !',0
reset_vector_text
	dc.b	27,'Y',32+6,32+3,'The RESET VECTOR has been changed'
	dc.b	27,'Y',32+8,32+11,'It MAY be a virus'
	dc.b	27,'Y',32+12,32+12,'F1 Continue'
	dc.b	27,'Y',32+14,32+12,'F2 Clear vector',0
resident_text
	dc.b	27,'Y',32+6,32+5,'RESET RESIDENT prog in memory'
	dc.b	27,'Y',32+8,32+3,'It is MORE than likely a VIRUS !!'
	dc.b	27,'Y',32+12,32+13,'F1 Continue'
	dc.b	27,'Y',32+14,32+13,'F2 Clear Virus',0

; not used

	dc.b	' (c) TS &'

	dc.w	$eeeb			; makes the sector sum $1234
