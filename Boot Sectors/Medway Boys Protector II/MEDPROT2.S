;-----------------------------------------------------------------------
; MEDPROT2.S - The Medway Boys Protector II boot sector.
; Devpac source of the boot sector, disassembled by Darren Birks, 13 November 2026.
;
; Taken from Cynix menu 3 (CYNIX_03.MSA).  The sector is executable
; (word sum $1234) and is not encoded.
;
; What it does:
; 1. Black background, colour 15 white, and its title.
; 2. Looks at the routine resvector points to for three viruses:
;    - $12123456 at resvector+$10: "Kobold #2", or "Automation V1" when
;      resvector+$b6 holds $5c8f60fe;
;    - $12123456 at resvector+$14: "Ghost".
;    Found: " virus in memory !" on red, and it stops there for good.
; 3. Otherwise looks at resvalid: $31415926 there means a reset vector is
;    set.  "The reset vector has been changed / It MAY be a virus" on
;    blue, then F1 to continue, or F2 to clear resvalid and resvector and
;    continue.
; 4. Nothing found: "You are FREE of viruses !" on green for about 0.75
;    seconds, then a white background with black text, and the boot goes
;    on.
;
; The virus checks read through resvector before resvalid is looked at:
; with no reset vector set they read $10 and $14 (the illegal instruction
; and divide by zero vectors), which never hold $12123456.
;
; The bytes from $1f5 (" (c) TS &") are not used.
;
; Build: vasm -devpac -no-opt -Fbin (or Devpac with no optimising):
; exact encodings matter (cmp.l #,d0, adda.l #$14,a2, the .w branches).
;-----------------------------------------------------------------------

	opt	o-

; boot sector header and BPB (little-endian words)

boot	bra.s	start			; $601c
	dc.b	$90,'IBM  '		; filler
	dc.b	$9a,$14,$5a		; serial number
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

; 1. the title, white on black

start	lea	$ff8240,a6		; the palette
	move.w	#0,(a6)			; the background black
	move.w	#$777,30(a6)		; colour 15 white
	lea	title_text(pc),a0
	bsr.w	print

; 2. the viruses, by the routine resvector points to

	movea.l	$42a.w,a0		; resvector
	movea.l	a0,a2
	lea	16(a0),a0
	move.l	(a0)+,d0		; resvector+$10
	cmp.l	#$12123456,d0		; Kobold #2 or Automation V1?
	beq.w	kobold_or_automation	; yes
	adda.l	#$14,a2
	move.l	(a2),d0			; resvector+$14
	cmp.l	#$12123456,d0		; Ghost?
	beq.w	ghost			; yes

; 3. a reset vector set?

	move.l	$426.w,d0		; resvalid
	cmp.l	#$31415926,d0		; set?
	beq.w	reset_vector_set	; yes

; 4. nothing found

	move.w	#$040,(a6)		; green
	lea	free_text(pc),a0	; "You are FREE of viruses !"
	bsr.w	print
	move.l	#$50000,d1		; about 0.75 seconds
wait	subq.l	#1,d1
	bne.s	wait
continue
	move.w	#$777,(a6)		; the background white
	move.w	#0,30(a6)		; colour 15 black
	rts				; the boot goes on

kobold_or_automation
	lea	162(a0),a0		; resvector+$b6
	move.l	(a0),d0
	cmp.l	#$5c8f60fe,d0		; Automation V1?
	beq.w	automation		; yes
	lea	kobold_text(pc),a0	; "Kobold #2"
	bsr.w	print
	bra.w	virus_found
automation
	lea	automation_text(pc),a0	; "Automation V1"
	bsr.w	print
	bra.w	virus_found
ghost	lea	ghost_text(pc),a0	; "Ghost"
	bsr.w	print
virus_found
	move.w	#$400,(a6)		; red
	lea	in_memory_text(pc),a0	; " virus in memory !"
	bsr.w	print
stop	bra.s	stop			; for good

reset_vector_set
	move.w	#$004,(a6)		; blue
	lea	reset_vector_text(pc),a0
	bsr.w	print
ask_key	bsr.w	get_key
	swap	d0			; the scan code
	cmpi.b	#$3b,d0			; F1?
	beq.s	continue		; yes
	cmpi.b	#$3c,d0			; F2?
	bne.s	ask_key			; no: again
	clr.l	$426.w			; resvalid cleared
	clr.l	$42a.w			; resvector cleared
	bra.s	continue

; print the text at a0 (Cconws)

print	move.l	a0,-(sp)
	move.w	#9,-(sp)		; Cconws
	trap	#1
	addq.l	#6,sp
	rts

; a key if there is one (Crawio), 0 if not

get_key	move.w	#$ff,-(sp)
	move.w	#6,-(sp)		; Crawio
	trap	#1
	addq.l	#4,sp
	rts

; the texts: ESC Y row column

title_text
	dc.b	27,'Y',32+0,32+6,'The Medway Boys Protector II',10,13,0
free_text
	dc.b	27,'Y',32+10,32+8,'You are FREE of viruses !',10,13,0
kobold_text
	dc.b	27,'Y',32+10,32+8,'Kobold #2',0
automation_text
	dc.b	27,'Y',32+10,32+4,'Automation V1',0
ghost_text
	dc.b	27,'Y',32+10,32+9,'Ghost',0
in_memory_text
	dc.b	' virus in memory !',0
reset_vector_text
	dc.b	27,'Y',32+6,32+3,'The reset vector has been changed'
	dc.b	27,'Y',32+8,32+10,'It MAY be a virus'
	dc.b	27,'Y',32+10,32+11,'F1 to continue.'
	dc.b	27,'Y',32+12,32+11,'F2 to clear vector.',10,13,0

; not used

	dc.b	' (c) TS &'

	dc.w	$5a6b			; makes the sector sum $1234
