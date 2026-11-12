;-----------------------------------------------------------------------
; MEDBOOT.S - The Medway Boys anti-virus boot sector (menu disk 54).
; Devpac source of the Medway Boys boot sector, disassembled by Darren Birks, 11 November 2026.
;
; Taken from MED_054.ST (LGD CD, games\medway_boys\MED_054.ZIP). The
; sector is executable (word sum $1234). Bytes $4E to $1FF are stored on
; the disk XORed with $FF: the loop at decode undoes that in place. This
; source is the sector after decoding, so it assembles to the decoded
; 512 bytes; XOR bytes $4E-$1FF with $FF to get the sector as on disk.
; The loop runs $201 times, so it also flips the $51 bytes after the
; sector in the boot buffer.
;
; What it does:
; 1. Looks at the first $101 words of memory (the exception vectors) for
;    a word $0472, the address of hdv_bpb, taken as a virus's code.
; 2. Checks that hdv_bpb ($472) points into the ROM at $FCxxxx. On TOS
;    1.06, 1.62 and 2.0x the ROM is at $E00000, so an STE always fails.
; 3. Either fails: prints "A VIRUS IS LURKING IN MEMORY" and cycles
;    colour 0 forever.
; 4. Both pass: white screen, 11 line feeds, prints "MEDWAY BOYS-VIRUS
;    FREE" and fades the screen out, in and out again, waiting two VBLs
;    a step on its own VBL handler, then returns to TOS.
;
; Build: vasm -devpac -no-opt -Fbin (or Devpac with no optimising):
; exact encodings matter (move.w #0,$ffff8242, the .w branches).
;-----------------------------------------------------------------------

	opt	o-

; boot sector header and BPB (little-endian words)

boot	bra.s	decode			; $6038
	dc.b	0,0,0,0,0,0		; filler
	dc.b	$39,$da,$61		; serial number
	dc.b	$00,$02			; 512 bytes a sector
	dc.b	$02			; 2 sectors a cluster
	dc.b	$01,$00			; 1 reserved sector
	dc.b	$02			; 2 FATs
	dc.b	$70,$00			; 112 directory entries
	dc.b	$40,$06			; 1600 sectors
	dc.b	$f9			; media byte
	dc.b	$03,$00			; 3 sectors a FAT
	dc.b	$0a,$00			; 10 sectors a track
	dc.b	$02,$00			; 2 sides
	dc.b	$00,$00			; no hidden sectors
	dcb.b	$3a-30,0

; undo the XOR $FF on the rest of the sector

decode	lea	check(pc),a0
	move.w	#$200,d0
decode_byte
	move.b	(a0),d1
	eori.b	#$ff,d1
	move.b	d1,(a0)+
	dbra	d0,decode_byte

; 1. any word $0472 (hdv_bpb) in the first $101 words of memory?

check	move.w	#$100,d2
	movea.w	#0,a0
check_word
	movea.w	(a0)+,a1
	cmpa.w	#$472,a1
	beq.w	virus
	dbra	d2,check_word

; 2. hdv_bpb must point into the ROM at $FCxxxx

	move.w	$472.w,d2
	cmpi.w	#$fc,d2
	bne.w	virus
	nop

; no virus: black text on white, 11 line feeds, the message

	move.w	#$777,$ffff8240.l
	move.w	#0,$ffff8242.l
	moveq	#10,d7
line_feed
	move.w	#10,d0
	move.w	d0,-(sp)		; Crawcio(10)
	move.w	#6,-(sp)
	trap	#1
	addq.l	#4,sp
	dbra	d7,line_feed

	lea	s_free(pc),a0
	move.l	a0,-(sp)		; Cconws
	move.w	#9,-(sp)
	trap	#1
	addq.l	#6,sp

; fade out, in and out again, two VBLs a step on its own VBL handler

	lea	vbl(pc),a0
	move.l	$70.l,d7
	move.l	a0,$70.l

	moveq	#6,d1
fade_out
	addi.w	#$111,$ffff8242.l
	subi.w	#$111,$ffff8240.l
	bsr.w	wait_vbl
	bsr.w	wait_vbl
	dbra	d1,fade_out

	moveq	#6,d1
fade_in
	subi.w	#$111,$ffff8242.l
	addi.w	#$111,$ffff8240.l
	bsr.w	wait_vbl
	bsr.w	wait_vbl
	dbra	d1,fade_in

	moveq	#6,d1
fade_out_again
	addi.w	#$111,$ffff8242.l
	subi.w	#$111,$ffff8240.l
	bsr.w	wait_vbl
	bsr.w	wait_vbl
	dbra	d1,fade_out_again

	move.l	d7,$70.l
	rts				; back to TOS

; wait for the VBL handler to set d3 to -1

wait_vbl
	cmp.w	#$ffff,d3
	bne.s	wait_vbl
	moveq	#0,d3
	rts

vbl	move.w	#$ffff,d3
	rte

s_free	dc.b	27,'b',1,9,'MEDWAY BOYS-VIRUS FREE',0
	dc.b	0,0,0

; virus found: the message, then cycle colour 0 forever

virus	lea	s_virus(pc),a0
	move.l	a0,-(sp)		; Cconws
	move.w	#9,-(sp)
	trap	#1
	addq.l	#6,sp
virus_colour
	addi.w	#1,$ff8240.l
	bra.s	virus_colour

	dcb.b	$176-$15c,0

s_virus	dc.b	27,'E',10,13,10,13,10,13,10,13
	dc.b	'  A VIRUS IS LURKING IN MEMORY',10,13,10,13
	dc.b	'   SWITCH OFF AND START AGAIN',0

	dcb.b	$1db-$1c0,0
	dcb.b	$1fe-$1db,$ff
	dc.w	$d7e7			; makes the sector sum $1234 once encoded
