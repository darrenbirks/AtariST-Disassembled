; Batman The Movie (Ocean, 1989) - 1 disk budget release (The Hit Squad)
; Boot sector: track 0 sector 1, 512 bytes (bootsect.bin).
;
; No protection and no encryption: this source assembles to bootsect.bin.  TOS runs
; the sector because its words add up to $1234; the code is PC relative and org 0
; gives the offsets in the sector.
;
; It sets the reset handler (resvalid / resvector, stage 3 puts the handler at $300),
; reads track 0 and track 1 of side 0 (20 sectors) to $fe00 with its own FDC code and
; jumps to $10000, track 0 sector 2 (stage2.s).  The parameter block says one side; the
; data is on side 0 only.

	opt	o-
	org	$0
boot_sector:
	bra.s	boot_start              ; to the code


; OEM area, serial number and BIOS parameter block.
oem_area:
	dc.b	$00,$00,$00,$00,$00,$00
serial_number:
	dc.b	$fb                     ; serial number
	dc.b	$97                     ; serial number
	dc.b	$3e                     ; serial number
bpb:
	dc.b	$00                     ; bytes per sector, low byte (Intel order): 512
	dc.b	$02                     ; bytes per sector, high byte
	dc.b	2                       ; sectors per cluster
	dc.b	1                       ; reserved sectors, low byte
	dc.b	0                       ; reserved sectors, high byte
	dc.b	2                       ; FATs
	dc.b	$70                     ; root directory entries, low byte: 112
	dc.b	$00                     ; root directory entries, high byte
	dc.b	$20                     ; sectors on the disk, low byte: 800 (80 tracks, 1 side)
	dc.b	$03                     ; sectors on the disk, high byte
	dc.b	$f8                     ; media descriptor
	dc.b	3                       ; sectors per FAT, low byte
	dc.b	0                       ; sectors per FAT, high byte
	dc.b	10                      ; sectors per track, low byte
	dc.b	0                       ; sectors per track, high byte
	dc.b	1                       ; sides, low byte
	dc.b	0                       ; sides, high byte
	dc.b	0                       ; hidden sectors, low byte
	dc.b	0                       ; hidden sectors, high byte

; Not used: the branch at the start jumps past it.
boot_spare:
	dc.w	$0000

;----------------------------------------------------------------------
; Boot code: stack, interrupts off, white screen, read tracks 0-1 of side 0 to $fe00 and
; run them.
;----------------------------------------------------------------------
boot_start:
	ori.b	#$0,d0                  ; two zero longs: ori.b #0,d0 does nothing
	ori.b	#$0,d0
	lea	$80000,sp               ; stack
	move.w	#$2700,sr               ; interrupts off
	lea	$ffff8240.w,a0          ; palette
	moveq	#15,d7
white_palette_loop:
	move.w	#$777,(a0)+             ; all 16 colours white
	dbra	d7,white_palette_loop
	lea	$fe00,a3                ; to $fe00: this sector, then $10000 for sector 2
	moveq	#0,d5                   ; track 0
	moveq	#1,d2                   ; two tracks
	bsr.s	read_tracks
	jmp	$10000                  ; run track 0 sector 2 (stage2.s)


;----------------------------------------------------------------------
; Read d2 + 1 tracks from track d5 to a3, side 0.  Sets the reset vector first.
;----------------------------------------------------------------------
read_tracks:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	#$31415926,$426.w       ; resvalid: the reset vector below is valid
	move.l	#$300,$42a.w            ; resvector: reset goes to $300 (stage 3 puts a handler there)
	movea.l	a3,a6
	lea	fdc_vars(pc),a5         ; the variables
read_tracks_loop:
	move.w	d5,d0
	bsr.s	read_track
	lea	$1400(a3),a3            ; next track: 10 sectors on
	addq.w	#1,d5
	dbra	d2,read_tracks_loop
	movem.l	(sp)+,d0-d7/a0-a6
	rts


;----------------------------------------------------------------------
; Seek to track d0, read its 10 sectors with one multiple sector read to a3.
;----------------------------------------------------------------------
read_track:
	bsr.s	seek
	move.l	#$1400,$14(a5)          ; one track
	move.l	a3,d0
	bsr.w	set_dma
	move.w	#$90,$ffff8606.w        ; DMA mode $90/$190/$90: clear the DMA, sector count register
	move.w	#$190,$ffff8606.w       ; DMA mode / status
	move.w	#$90,$ffff8606.w        ; DMA mode / status
	move.w	#$a,d0                  ; 10 sectors
	bsr.s	fdc_write
	move.w	#$84,$ffff8606.w        ; DMA mode: sector register
	move.w	#$1,d0                  ; from sector 1
	bsr.s	fdc_write
	move.w	#$94,d0                 ; READ MULTIPLE SECTORS, 15 ms settle
	move.w	#$80,$ffff8606.w        ; DMA mode: command register
	bsr.s	fdc_write
	bsr.s	wait_fdc
	rts


;----------------------------------------------------------------------
; Seek to track d0.
;----------------------------------------------------------------------
seek:
	move.w	d0,$0(a5)
	move.w	#$86,$ffff8606.w        ; DMA mode: data register
	bsr.s	fdc_write               ; the track
	move.w	#$80,$ffff8606.w        ; DMA mode: command register
	move.w	#$11,d0                 ; SEEK
	bsr.s	fdc_write
	bsr.s	wait_fdc
	rts


;----------------------------------------------------------------------
; DMA address = d0, and the end address for wait_fdc.
;----------------------------------------------------------------------
set_dma:
	move.l	d0,$8(a5)
	move.b	d0,$ffff860d.w          ; DMA base low
	lsr.l	#8,d0
	move.b	d0,$ffff860b.w          ; DMA base mid
	lsr.l	#8,d0
	move.b	d0,$ffff8609.w          ; DMA base high
	move.l	$8(a5),d0
	add.l	$14(a5),d0
	move.l	d0,$c(a5)
	move.w	#$1,$6(a5)
	rts


;----------------------------------------------------------------------
; Write d0 to the FDC register the DMA mode selects.
;----------------------------------------------------------------------
fdc_write:
	bsr.s	fdc_delay
	move.w	d0,$ffff8604.w          ; DMA sector count / FDC access
	bsr.s	fdc_delay
	rts

fdc_delay:
	move.w	d0,-(sp)
	move.w	#$20,d0
	dbra	d0,*
	move.w	(sp)+,d0
	rts


;----------------------------------------------------------------------
; Wait for the FDC interrupt, or until the DMA reaches the end (then stop the FDC), with
; a timeout.
;----------------------------------------------------------------------
wait_fdc:
	clr.w	$4(a5)                  ; no error
	move.l	#$180,d0                ; settle
	dbra	d0,*
	move.l	#$40000,d1              ; timeout
wait_fdc_loop:
	btst	#$5,$fffffa01.w         ; FDC interrupt?
	beq.s	fdc_done
	subq.l	#1,d1
	beq.s	fdc_timeout
	tst.w	$6(a5)                  ; DMA running?
	beq.s	wait_fdc_loop
	moveq	#0,d0
	move.b	$ffff8609.w,d0          ; DMA base high
	lsl.l	#8,d0
	move.b	$ffff860b.w,d0          ; DMA base mid
	lsl.l	#8,d0
	move.b	$ffff860d.w,d0          ; DMA base low
	cmp.l	$c(a5),d0               ; the DMA has reached the end
	blt.s	wait_fdc_loop
	bsr.s	force_interrupt         ; stop the FDC there
	clr.w	$6(a5)
	bra.s	fdc_done

fdc_timeout:
	move.w	$ffff8604.w,d0          ; timed out: status, error 1
	andi.w	#$ff,d0
	move.w	d0,$2(a5)
	bsr.s	force_interrupt
	move.w	#$1,$4(a5)
	clr.w	$6(a5)
	rts

fdc_done:
	move.w	$ffff8604.w,d0          ; DMA sector count / FDC access
	andi.w	#$ff,d0
	move.w	d0,$2(a5)
	clr.w	$6(a5)
	rts


;----------------------------------------------------------------------
; FORCE INTERRUPT: stop the FDC.
;----------------------------------------------------------------------
force_interrupt:
	move.w	#$80,$ffff8606.w        ; DMA mode / status
	move.w	#$d0,d0
	bsr.w	fdc_write
	move.w	#$100,d0
	dbra	d0,*
	rts


; Variables.
fdc_vars:
	dc.w	$0000                   ; track
	dc.w	$0000                   ; FDC status
	dc.w	$0000                   ; error: timeout
	dc.w	$0000                   ; DMA running
	dc.l	$00000000               ; DMA start
	dc.l	$00000000               ; DMA end
	dc.l	$00000000               ; not used
	dc.l	$00000000               ; bytes to read: one track

; Zeros up to the checksum word.
boot_padding:
	dcb.b	60,$00

; Checksum word.
boot_checksum:
	dc.w	$4c23                   ; makes the words of the sector add up to $1234

	end
