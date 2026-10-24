; Batman The Movie (Ocean, 1989) - 2 disk retail release (the original), disk 1, SpeedLock protection
; Track 1 sectors 8-10, read to $1ff68 by the patched boot sector code ($600 bytes,
; layer3.bin as on the disk).
;
; The loader stages of protect.s run again over $1ff68-$20267; the address error
; then lands at $1ff70 here.  This code wipes the first loader and runs a third
; decryption layer over $2003a-$204b1, keyed by its own loop code.  The layer then
; loads track 0 sectors 2-9 to $21000 with Floprd, decrypts them (loader.bin) and
; jumps to the game loader at $21000.
;
; Everything is shown after all decryption, so this source assembles to layer3.dec.
;
; Prefetch: eor.l d4,(a2)+ at $1fff6 toggles the next instruction, layer_store,
; from move.l d0,-4(a0) to move.l d0,$10(a0) in memory.  The 68000 has already
; prefetched it and runs it as -4(a0); the toggled long is also read back as key
; data, and the eor at $2001c toggles it back.

; addresses outside this source
mix_key	equ	$1fdf4                  ; protect.s: the first loader is wiped from here
game_loader	equ	$21000          ; the game loader, loader.bin decrypted
saved_registers	equ	$5ff80          ; d0-a7 of TOS (protect.s)
saved_vectors	equ	$60000          ; copy of $8-$7ff (protect.s)

	opt	o-
	org	$1ff68

; Decrypted by the protect.s stages up to $20267.
check_long:
	dc.l	$00000000               ; decrypts to 0 again: address_error comes to wipe_loader
	dc.l	$00000000               ; spare

;----------------------------------------------------------------------
; Second pass: wipe the first loader up to this loop, put the vectors back.
;----------------------------------------------------------------------
wipe_loader:
	lea	mix_key,a0              ; from mix_key ...
	lea	wipe_loop,a1            ; ... up to wipe_loop
	moveq	#0,d0
wipe_loop:
	move.l	d0,(a0)+
	cmpa.l	a0,a1
	bcc.s	wipe_loop
	move.w	#$2700,sr               ; interrupts off
	lea	$8.l,a0                 ; a0 = $8
	lea	saved_vectors,a1
restore_vectors_loop:
	move.w	(a1),(a0)+              ; put $8-$7ff back from saved_vectors
	clr.w	(a1)+
	cmpa.l	#$800,a0
	bne.s	restore_vectors_loop

;----------------------------------------------------------------------
; Third layer: $11e longs from layer_branch ($2003a-$204b1), keyed by the loop code.  The
; first long decrypted is the loop's own branch back (layer_branch).
;----------------------------------------------------------------------
third_layer:
	moveq	#0,d1                   ; d1 = key offset
	moveq	#-65,d3                 ; d3 = $ffffffbf
	moveq	#0,d4
	move.w	#$ffec,d4               ; d4 = $ffec: the toggle
	moveq	#7,d5                   ; d5 = 7
	moveq	#34,d6                  ; d6 = $22
	moveq	#0,d7
	move.w	#$11d,d7                ; $11e longs
	lea	layer_branch,a0         ; data from layer_branch
	lea	layer_loop(pc),a1       ; key: the loop code
	lea	layer_store(pc),a2      ; a2 = layer_store, the instruction it toggles
	lea	layer_loop(pc),a3       ; key
	lea	layer_key_add(pc),a4    ; key
	lea	layer_key_data(pc),a5   ; key
	lea	layer_key_eor(pc),a6    ; key
	lea	layer_key_byte(pc),sp   ; sp is a key pointer too
layer_loop:
	move.l	(a0)+,d0                ; d0 = next encrypted long
	move.l	$0(a1,d1.w),d2          ; key long from the loop code
layer_key_eor:
	eor.l	d2,d3
layer_key_add:
	add.l	d6,d2
	rol.l	d2,d3                   ; rol by d2 & 63
	add.w	$0(a3,d1.w),d3
	add.l	d3,d2
	ori.b	#$1,d2
	swap	d2
	ori.b	#$1,d2
layer_key_data:
	eor.l	d2,d0                   ; decrypt
	add.w	d3,d1                   ; next key offset
	eor.l	d4,(a2)+                ; toggles layer_store in memory to move.l d0,$10(a0)
layer_store:
	move.l	d0,-$4(a0)              ; prefetched before the toggle: stores the long at -4(a0)
	add.l	-$4(a2),d3              ; reads the toggled long
	and.l	d5,d2                   ; d2 = 0..7
layer_key_byte:
	add.b	$0(a4,d2.w),d3
	ori.b	#$10,d2
	add.b	-$2(a5,d2.w),d3
	sub.b	$8(a6,d2.w),d3          ; can read the toggled long
	add.b	$0(sp,d2.w),d3
	rol.l	d2,d2
	add.l	a2,d3
	add.l	d2,d6
	eor.l	d4,-(a2)                ; toggle layer_store back
	dbra	d7,layer_next           ; next long
	movea.l	layer_exit(pc),a0       ; done: a0 = load_game_loader
	jmp	(a0)

layer_next:
	andi.w	#$7e,d1                 ; key offset 0..$5e
	cmpi.w	#$60,d1
	bcs.s	layer_toggle
	subi.w	#$60,d1
layer_toggle:
	lea	$0(a1,d6.w),a2          ; a2 = layer_store again (d6 makes it so on this disk)
layer_branch:
	bra.s	layer_loop              ; the first long decrypted: the loop's branch back


;----------------------------------------------------------------------
; Decrypted by the third layer: load track 0 sectors 2-9 to $21000, decrypt them and run
; the game loader.
;----------------------------------------------------------------------
load_game_loader:
	or.b	d0,d0                   ; filler
	nop
	movem.l	saved_registers,d0-d7/a0-a7 ; TOS registers back
	move.w	#$2700,sr               ; interrupts off
	lea	$10000,sp               ; stack at $10000
	move.w	#$8,-(sp)               ; 8 sectors
	move.w	#$0,-(sp)               ; side 0
	move.w	#$0,-(sp)               ; track 0
	move.w	#$2,-(sp)               ; sector 2
	move.w	#$0,-(sp)               ; drive A
	move.l	#$0,-(sp)               ; filler
	pea	game_loader             ; buffer
	move.w	#$8,-(sp)               ; Floprd
	trap	#14                     ; XBIOS 8 Floprd(game_loader, 0, 0, 2, 0, 0, 8)
	adda.w	#$14,sp
	lea	game_loader,a0          ; decrypt the 4 KB in place
	move.w	#$3ff,d0                ; $400 longs
	move.l	#$76fcd913,d1           ; key 1
	move.l	#$671039df,d2           ; key 2
decrypt_loader_loop:
	move.l	(a0),d3
	eor.l	d1,d3                   ; eor key 1
	eor.l	d2,d3                   ; eor key 2
	eor.l	d2,d1                   ; key 1 eor key 2
	ror.l	d2,d2                   ; key 2 ror by itself
	rol.l	d1,d1                   ; key 1 rol by itself
	move.l	d3,(a0)+
	dbra	d0,decrypt_loader_loop
	jmp	game_loader             ; run the game loader


; Rest of the third layer area, decrypted to $ff.
layer_filler:
	dcb.b	1024,$ff
layer_exit:
	dc.l	load_game_loader        ; jump target of the third layer

; Rest of the sectors.
sector_filler:
	dcb.b	186,$ff                 ; not encrypted

	end
