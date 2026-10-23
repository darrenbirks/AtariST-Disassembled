; TCSTART.S  -  Turbo C 2.0 start-up code of FCOPYPRO.PRG, included by FCOPYPRO.S
;
; Tells program and accessory start apart, sets the stack and Mshrinks, then jumps to main.


;----------------------------------------------------------------------
; Turbo C start up.  a0 is the basepage when loaded as a desk accessory, 0 when run
; as a program (the basepage is then at 4(sp)); is_program records which.  The stack
; goes at the end of the program's memory and a program Mshrinks to text + data + bss.
;----------------------------------------------------------------------
start:
	bra.s	.program_or_accessory

	dc.w	$0000,$1000
	dc.b	'Turbo C 2.0 (c)88-90 Borland Int.',0
.program_or_accessory
	movea.l	a0,a3
	move.l	a3,d0
	bne.s	.accessory
	movea.l	$4(sp),a3
	moveq	#1,d0
	bra.s	.set_mode

.accessory
	clr.w	d0
.set_mode
	move.w	d0,is_program
	movea.l	$c(a3),a0
	adda.l	$14(a3),a0
	adda.l	$1c(a3),a0
	adda.w	#$100,a0
	move.l	a0,program_size
	move.l	a3,d0
	add.l	a0,d0
	dc.w	$c03c,$00fc                     ; and.b #$fc,d0
	movea.l	d0,sp
	dc.w	$90bc                           ; sub.l #$ffc,d0
	dc.l	$ffc
	move.l	d0,stack_limit
	tst.w	is_program
	beq.s	.main
	move.l	a0,-(sp)
	move.l	a3,-(sp)
	move.w	#$0,-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
.main
	jmp	main

