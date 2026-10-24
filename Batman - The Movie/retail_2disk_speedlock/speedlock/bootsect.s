; Batman The Movie (Ocean, 1989) - 2 disk retail release (the original), disk 1, SpeedLock protection
; Boot sector: track 0 sector 1, 512 bytes (bootsect.bin as on the disk).
;
; TOS reads the sector into its disk buffer and runs it because its words add up to
; $1234.  The code is PC relative; org 0 makes the addresses below offsets in the
; sector.  Bytes $68-$199 are encrypted on the disk and decrypted by the code at $54
; (each byte eored with the byte $2e before it); this source shows them decrypted,
; so it assembles to bootsect.dec, not to the sector on the disk.
;
; What it does: clears the exception vectors, decrypts itself, sets the screen to
; $78000, then drives the FDC directly to read track 1 sectors 5-7 to $1fd66 and
; jumps there (protect.s).  protect.s patches this code later and runs it again
; from read_loader to read sectors 8-10 to $1ff68 (layer3.s).

; addresses inside instructions
boot_stack	equ	$22c            ; boot_sector+$22c

	opt	o-
	org	$0
boot_sector:
	bra.s	boot_start              ; to the code, over the parameter block


; OEM area (six spaces), serial number and BIOS parameter block.
oem_area:
	dc.b	$20,$20,$20,$20,$20,$20
serial_number:
	dc.b	$01                     ; serial number
	dc.b	$00                     ; serial number
	dc.b	$00                     ; serial number
bpb:
	dc.b	$00                     ; bytes per sector, low byte (Intel order): 512
	dc.b	$02                     ; bytes per sector, high byte
	dc.b	2                       ; sectors per cluster
	dc.b	1                       ; reserved sectors, low byte
	dc.b	0                       ; reserved sectors, high byte
	dc.b	2                       ; FATs
	dc.b	$30                     ; root directory entries, low byte: 48
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
boot_filler:
	dcb.b	26,$4e                  ; filler
boot_spare:
	dc.w	$0000

;----------------------------------------------------------------------
; Boot code: own stack, interrupts off, clear the exception vectors and decrypt $68-$199.
;----------------------------------------------------------------------
boot_start:
	lea	boot_stack(pc),sp       ; own stack in the disk buffer, past the sector
	move.w	#$2700,sr               ; supervisor, interrupts off
	suba.l	a6,a6                   ; a6 = 0
	addq.l	#8,a6                   ; a6 = 8
	clr.l	(a6)+                   ; bus error vector = 0
	clr.l	(a6)+                   ; address error vector = 0
	clr.l	(a6)+                   ; illegal instruction vector = 0
	clr.l	$c(a6)                  ; privilege violation vector ($20) = 0
	clr.l	$10(a6)                 ; trace vector ($24) = 0
	lea	boot_start(pc),a0       ; key: the sector from boot_start, $2e bytes behind the data
	lea	decrypted_code(pc),a1   ; data: encrypted on the disk
	move.w	#$131,d0                ; $132 bytes, $68-$199
decrypt_loop:
	move.b	(a0)+,d1
	eor.b	d1,(a1)+                ; eor with a byte already decrypted
	dbra	d0,decrypt_loop

;----------------------------------------------------------------------
; Decrypted from here on: screen at $78000.
;----------------------------------------------------------------------
decrypted_code:
	clr.w	-(sp)                   ; resolution: low
	pea	$78000                  ; physical screen
	pea	$78000                  ; logical screen
	move.w	#$5,-(sp)               ; Setscreen
	trap	#14                     ; XBIOS 5 Setscreen($78000, $78000, 0)
	lea	$c(sp),sp

;----------------------------------------------------------------------
; Read track 1 sectors 5-7 to $1fd66 with the FDC, fill $14004 bytes after them with $ff and
; run them (protect.s).  protect.s patches the marked operands and runs this again to read
; sectors 8-10 to $1ff68 (layer3.s).
;----------------------------------------------------------------------
read_loader:
	lea	read_loader(pc),a0      ; a0 = read_loader
	move.l	a0,$20.w                ; privilege violation vector -> read_loader; protect.s finds this code through it
	lea	$28.l,a1                ; a1 = $28: delay count, and the base of the register addresses
	moveq	#1,d5                   ; d5 = 1: track 1, and the DMA address high byte
	lea	-$7a24(a1),a2           ; a2 = $ffff8604 FDC access
	move.w	d5,d4                   ; d4 = 1
	lea	$2(a2),a3               ; a3 = $ffff8606 DMA mode
	moveq	#20,d3                  ; d3 = $14: SEEK (verify, 6 ms)
	addi.w	#$d,d4                  ; d4 = 14
	move.w	#$80,d1                 ; d1 = $80: DMA mode for the FDC command register
	lea	$1fa(a3),a4             ; a4 = $ffff8800 PSG
	move.b	d4,(a4)                 ; select PSG register 14 (port A)
	move.w	d1,d2                   ; d2 = $80
	addq.w	#6,d2                   ; d2 = $86: DMA mode for the FDC data register
	move.b	(a4),d0                 ; port A
	andi.b	#$f8,d0
	addq.b	#5,d0                   ; drive A, side 0 (the select bits are active low)
	lea	$73fb(a3),a5            ; a5 = $fffffa01 MFP GPIP
	move.b	d0,$2(a4)               ; write PSG port A
	move.w	d2,(a3)                 ; DMA mode: FDC data register
	move.w	#$c8,d4                 ; d4 = $c8
	lea	$fd66,a0                ; a0 = $fd66, DMA address $1fd66 with d5; protect.s patches the operand to $ff68
	move.w	a1,d0                   ; delay
	subq.w	#2,d2                   ; d2 = $84: DMA mode for the FDC sector register
	dbra	d0,*
	move.w	d5,(a2)                 ; FDC data register = 1: the track to seek to
	move.w	a1,d0
	moveq	#0,d7                   ; d7 = 0
	dbra	d0,*
	move.w	d1,(a3)                 ; DMA mode: FDC command register
	move.w	a1,d0
	dbra	d0,*
	move.w	d3,(a2)                 ; SEEK to track 1
	addi.w	#$c,d3                  ; d3 = $20: GPIP bit 5, FDC interrupt (active low)
	lsl.w	d5,d4                   ; d4 = $190
	move.w	a1,d0
	dbra	d0,*
wait_seek:
	move.b	(a5),d0                 ; GPIP
	and.l	d3,d0
	bne.s	wait_seek               ; wait for the FDC interrupt
	move.w	d2,(a3)                 ; DMA mode: FDC sector register
	move.w	a1,d0
	move.b	d4,d7                   ; d7 = $90
	dbra	d0,*
	move.w	#$5,(a2)                ; first sector 5; protect.s patches the immediate to 8
	move.w	a1,d0
	dbra	d0,*
	move.w	a0,d6                   ; d6 = $fd66
	move.b	d6,-$1f3(a4)            ; DMA address low ($ffff860d)
	rol.w	#8,d6                   ; d6 = $66fd
	move.b	d6,$7(a2)               ; DMA address mid ($ffff860b)
	move.b	d5,$3(a3)               ; DMA address high ($ffff8609) = 1
	move.w	d4,(a3)                 ; DMA mode $190 then $90: toggling read/write clears the DMA
	move.w	d7,$2(a2)               ; DMA mode $90: sector count register
	move.w	#$3,(a2)                ; sector count 3 (protect.s writes 3 to the immediate again)
	addq.b	#6,d6                   ; d6 = DMA address mid/low after 3 sectors (protect.s rewrites the opcode byte unchanged)
	rol.w	#8,d6                   ; d6 = $0366
	move.w	d1,(a3)                 ; DMA mode: FDC command register
	move.w	a1,d0
	dbra	d0,*
	move.w	d7,(a2)                 ; READ MULTIPLE SECTORS ($90)
	move.w	a1,d0
	dbra	d0,*
	addi.w	#$40,d7                 ; d7 = $d0: FORCE INTERRUPT
wait_dma:
	move.b	(a5),d0                 ; GPIP
	and.l	d3,d0
	beq.s	reboot                  ; the FDC stopped before 3 sectors: reboot
	move.b	$5(a3),d0               ; DMA address mid
	lsl.w	#8,d0
	move.b	$7(a3),d0               ; DMA address low
	cmp.w	d0,d6
	bgt.s	wait_dma                ; until the DMA address reaches the end of the 3 sectors
	move.w	d1,(a3)                 ; DMA mode: FDC command register
	move.w	a1,d0
	dbra	d0,*
	move.w	d7,(a2)                 ; FORCE INTERRUPT: stop the multiple sector read
	move.w	a1,d0
	dbra	d0,*
	move.l	d5,d0                   ; d0 = 1
	swap	d0                      ; d0 = $10000
	adda.l	d0,a0                   ; a0 = $1fd66
	movea.l	a0,a6                   ; a6 = the code just read
	lea	$600(a6),a0             ; end of the 3 sectors (protect.s rewrites the displacement byte unchanged)
	move.w	#$5000,d0               ; $5001 longs
fill_loop:
	move.l	#$ffffffff,(a0)+        ; fill with $ff
	dbra	d0,fill_loop
	clr.w	$ff8240                 ; background black
	jmp	(a6)                    ; run protect.s at $1fd66; protect.s overwrites this with jmp $1fd66.l


;----------------------------------------------------------------------
; The read failed: jump through the reset vector.  After the patch by protect.s this is
; inside the new jmp instruction.
;----------------------------------------------------------------------
reboot:
	movea.l	$4.w,a0                 ; reset vector
	jmp	(a0)


; Padding up to the checksum word.
boot_padding:
	dcb.b	116,$00                 ; decrypted from the encrypted bytes up to $199, zeros after

; Checksum word: TOS runs the sector only if its words add up to $1234.
boot_checksum:
	dc.w	$7726                   ; makes the words of the sector on the disk add up to $1234

	end
