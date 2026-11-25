; module_address.S  -  The FlyDials GEM dialog module
;
; Devpac source of the FlyDials GEM dialog module in Ultimate Virus Killer 2000 9.0 by Richard Karsmakers (C.R.I.M.E.
; Development, 2004), disassembled by Darren Birks, 30 October 2026. FlyDials, a shareware library of dialog routines,
; is by Gregor Duchalski.
;
; UVK.LST holds this code as the INLINE block module_address% (2834 bytes), and module_address.bin is those bytes.
; Assembled to a plain binary, this source gives module_address.bin byte for byte. The code is position independent.

; GEM helper module (machine code) used for dialogs.
; Header words: $00-$0e = offsets of the user-defined object draw routines (make_user_object picks one by number);
; $10 = offset of the raster copy routine (copy_raster_routine%), $12 = offset of the object text routine
; (object_text_routine%), $14 = offset of a third routine (unused_module_routine%).
; init_gem_workstation fills in: $16.l = AES parameter block address+24, $1a = VDI handle, $1c = character width,
; $1e = character height.
flydials_module:
	dc.w	$0024,$0148,$0232,$02ee,$034a,$03b4,$0576,$05a0 ; entry offsets 1-8
	dc.w	$0624,$0760,$07d6               ; entry offsets 1-8

; Long: address of the VDI parameter block (contrl, intin, ptsin, intout, ptsout pointers) the module uses for its VDI
; calls; set by the BASIC program.
flydials_vdi_pb:
	dc.w	$0002,$31ea

; Word: VDI workstation handle the module draws with; set by the BASIC program.
flydials_vdi_handle:
	dc.w	$0003

; Word: character cell width in pixels (from graf_handle); set by the BASIC program.
flydials_char_width:
	dc.w	$0008

; Word: character cell height in pixels (8 or 16 on the ST); set by the BASIC program.
flydials_char_height:
	dc.w	$0010

; Word: non-zero when the AES offers a 3D look (objc_sysvar background colour > 0); objects with 3D flags are then drawn
; in 3D.
flydials_3d_on:
	dc.w	$0000

; Word: 3D background colour from objc_sysvar (BACKGRCOL), used to fill 3D objects. The entry points 1-6 that follow
; have no labels of their own; see flydials_module for the list.
flydials_3d_colour:
	dc.w	$0000
	move.l	4(sp),d0                        ; entry 1, radio button: d0 = PARMBLK
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	fly_begin_object_draw           ; set up a6/a5/a4 and the clip rectangle
	moveq	#0,d0                           ; fill interior hollow
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
	bsr.w	fly_is_3d_object                ; 3D object?
	bne.s	.radio_draw_round               ; yes: draw it round with VDI
	move.w	flydials_char_height(pc),d0     ; character height
	dc.w	$b07c,$0008                     ; cmp.w	#$8,d0, cmp.w #8,d0
	beq.s	.radio_short                    ; 8: small images
	dc.w	$b07c,$0010                     ; cmp.w	#$10,d0, cmp.w #16,d0
	bne.s	.radio_draw_round               ; other heights: draw it round with VDI
	move.w	8(a6),d1                        ; pb_currstate
	btst	#$0,d1                          ; SELECTED?
	bne.s	.radio_on_tall
	lea	radio_off_image_tall(pc),a0     ; 16 lines, not selected
	bra.s	.radio_draw_image
.radio_on_tall:
	lea	radio_on_image_tall(pc),a0      ; 16 lines, selected
	bra.s	.radio_draw_image
.radio_short:
	move.w	8(a6),d1                        ; pb_currstate
	btst	#$0,d1                          ; SELECTED?
	bne.s	.radio_on_short
	lea	radio_off_image_short(pc),a0    ; 8 lines, not selected
	bra.s	.radio_draw_image
.radio_on_short:
	lea	radio_on_image_short(pc),a0     ; 8 lines, selected
.radio_draw_image:
	moveq	#1,d1                           ; mode 1: replace
	bsr.w	fly_draw_small_image            ; copy the 16-pixel image to pb_x-1, pb_y
	bra.w	.draw_label                     ; draw the label
.radio_draw_round:
	movem.w	$a(a6),d0-d1                    ; d0/d1 = pb_x, pb_y
	add.w	flydials_char_width(pc),d0      ; centre x = pb_x + character width
	move.w	$10(a6),d2                      ; pb_h
	asr.w	#1,d2                           ; /2
	move.w	d2,d3                           ; y radius = pb_h/2
	add.w	d2,d1                           ; centre y = pb_y + pb_h/2 - 1
	subq.w	#1,d1
	move.w	flydials_char_width(pc),d2      ; x radius = character width - 1
	subq.w	#1,d2
	move.w	flydials_char_height(pc),d4     ; d4 = character height
	dc.w	$b87c,$0008                     ; cmp.w	#$8,d4, cmp.w #8,d4
	beq.s	.radio_store_ellipse
	subq.w	#1,d3                           ; 16-line font: y radius one less
.radio_store_ellipse:
	movem.w	d0-d3,(a4)                      ; keep centre and radii in the work area
	moveq	#0,d4                           ; whole ellipse: 0 to 3600
	move.w	#$e10,d5
	bsr.w	fly_draw_elliptical_pie         ; v_ellpie: outline
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.radio_check_selected           ; no
	moveq	#1,d0                           ; fill solid
	bsr.w	fly_set_fill_interior           ; vsf_interior(1)
	move.w	flydials_3d_colour(pc),d0       ; in the 3D background colour
	bsr.w	fly_set_fill_colour             ; vsf_color
	movem.w	(a4),d0-d3                      ; the ellipse again
	bsr.w	fly_draw_elliptical_pie         ; v_ellpie: filled
	moveq	#1,d0                           ; black
	bsr.w	fly_set_line_colour             ; vsl_color(1)
	move.w	(a4),d0                         ; centre x
	move.w	#$320,d4                        ; arc 80-190 degrees: upper left
	move.w	#$76c,d5
	bsr.w	fly_draw_elliptical_arc         ; v_ellarc: dark edge
	moveq	#0,d0                           ; white
	bsr.w	fly_set_line_colour             ; vsl_color(0)
	move.w	(a4),d0                         ; centre x
	move.w	#$a28,d4                        ; arc 260-10 degrees: lower right
	move.w	#$64,d5
	bsr.w	fly_draw_elliptical_arc         ; v_ellarc: light edge
	moveq	#1,d0                           ; black again
	bsr.w	fly_set_line_colour             ; vsl_color(1)
	moveq	#3,d0                           ; XOR mode
	bsr.w	fly_set_writing_mode            ; vswr_mode(3)
.radio_check_selected:
	move.w	8(a6),d0                        ; pb_currstate
	dc.w	$c07c,$0001                     ; and.w	#$1,d0, and.w #1,d0: SELECTED?
	beq.w	.draw_label                     ; no: draw the label
	moveq	#1,d0                           ; fill solid
	bsr.w	fly_set_fill_interior           ; vsf_interior(1)
	moveq	#1,d0                           ; in black
	bsr.w	fly_set_fill_colour             ; vsf_color(1)
	movem.w	(a4),d0-d3                      ; centre and radii
	subq.w	#3,d2                           ; radii 3 smaller: the dot
	subq.w	#3,d3
	move.w	flydials_char_height(pc),d4     ; character height
	dc.w	$b87c,$0008                     ; cmp.w	#$8,d4, cmp.w #8,d4
	bne.s	.radio_draw_dot
	subq.w	#1,d2                           ; 8-line font: flatter dot
	addq.w	#1,d3
.radio_draw_dot:
	moveq	#0,d4                           ; whole ellipse
	move.w	#$e0f,d5
	bsr.w	fly_draw_elliptical_pie         ; v_ellpie: the dot
	moveq	#0,d0                           ; fill hollow again
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
	bra.w	.draw_label                     ; draw the label
	move.l	4(sp),d0                        ; entry 2, check box: d0 = PARMBLK
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	fly_begin_object_draw           ; set up a6/a5/a4 and the clip rectangle
	moveq	#0,d0                           ; fill interior hollow
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
	movem.w	$a(a6),d0-d3                    ; d0-d3 = pb_x, pb_y, pb_w, pb_h
	add.w	d1,d3                           ; y2 = pb_y + pb_h
	move.w	d0,d2                           ; x2 = pb_x + 2 character widths - 2
	add.w	flydials_char_width(pc),d2
	add.w	flydials_char_width(pc),d2
	subq.w	#2,d2
	subq.w	#2,d3                           ; y2 - 2
	movem.w	d0-d3,(a4)                      ; keep the box corners
	bsr.w	fly_draw_bar                    ; v_bar: box outline
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.check_box_checked
	move.w	#$0,-(sp)                       ; bottom/right white
	move.w	#$1,-(sp)                       ; top/left black: sunken
	bsr.w	fly_draw_3d_frame               ; 3D frame
	addq.l	#4,sp
.check_box_checked:
	move.w	8(a6),d0                        ; pb_currstate
	btst	#$2,d0                          ; CHECKED?
	beq.s	.check_box_selected             ; no
	moveq	#2,d0                           ; fill with the pattern
	bsr.w	fly_set_fill_interior           ; vsf_interior(2)
	moveq	#2,d0                           ; transparent
	bsr.w	fly_set_writing_mode            ; vswr_mode(2)
	moveq	#0,d0                           ; no outline
	bsr.w	fly_set_fill_perimeter          ; vsf_perimeter(0)
	movem.w	(a4),d0-d3                      ; box inside the frame
	subq.w	#1,d2
	subq.w	#1,d3
	bsr.w	fly_draw_bar                    ; v_bar: patterned box
	moveq	#1,d0                           ; outline on again
	bsr.w	fly_set_fill_perimeter          ; vsf_perimeter(1)
	moveq	#1,d0                           ; replace mode
	bsr.w	fly_set_writing_mode            ; vswr_mode(1)
	moveq	#0,d0                           ; fill hollow
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
	bra.s	.draw_label                     ; draw the label
.check_box_selected:
	btst	#$0,d0                          ; SELECTED?
	beq.s	.draw_label                     ; no: draw the label
	movem.w	(a4),d0-d3                      ; box corners
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.check_box_cross
	addq.w	#2,d0                           ; 3D: cross 2 pixels inside the frame
	addq.w	#2,d1
	subq.w	#2,d2
	subq.w	#2,d3
.check_box_cross:
	bsr.w	fly_draw_line                   ; v_pline: one diagonal
	move.w	d2,d6                           ; swap x1 and x2
	move.w	d0,d2
	move.w	d6,d0
	bsr.w	fly_draw_line                   ; v_pline: the other diagonal
.draw_label:
	move.w	6(a6),d0                        ; pb_prevstate
	cmp.w	8(a6),d0                        ; = pb_currstate: whole object drawn, not just a state change?
	bne.s	.label_done                     ; state change only: no label
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.label_position
	moveq	#2,d0                           ; transparent text
	bsr.w	fly_set_writing_mode            ; vswr_mode(2)
.label_position:
	movem.w	$a(a6),d0-d1                    ; pb_x, pb_y
	add.w	flydials_char_width(pc),d0      ; label x = pb_x + 3 character widths
	add.w	flydials_char_width(pc),d0
	add.w	flydials_char_width(pc),d0
	move.w	$10(a6),d2                      ; pb_h
	move.w	flydials_char_height(pc),d3     ; character height
	asr.w	#3,d3                           ; /8
	sub.w	d3,d2
	add.w	d2,d1                           ; label y = pb_y + pb_h - height/8 - 1
	subq.w	#1,d1
	move.l	$1a(a6),d2                      ; d2 = text (ub_parm)
	bsr.w	fly_draw_label_text             ; v_gtext with the shortcut underlined
.label_done:
	bra.w	fly_end_object_draw             ; restore and return the states
	move.l	4(sp),d0                        ; entry 3, group frame: d0 = PARMBLK
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	fly_begin_object_draw           ; set up a6/a5/a4 and the clip rectangle
	movem.w	$a(a6),d0-d3                    ; d0-d3 = pb_x, pb_y, pb_w, pb_h
	move.w	flydials_char_height(pc),d4     ; half a character height
	asr.w	#1,d4
	add.w	d4,d1                           ; frame starts half a line down
	sub.w	d4,d3                           ; and is that much shorter
	movem.w	d0-d3,(a4)                      ; keep x, y, w, h
	add.w	d0,d2                           ; x2 = x + w - 1
	add.w	d1,d3                           ; y2 = y + h - 1
	subq.w	#1,d2
	subq.w	#1,d3
	move.w	d0,d5                           ; d5 = x
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.group_frame_lines              ; no
	moveq	#1,d0                           ; fill solid
	bsr.w	fly_set_fill_interior           ; vsf_interior(1)
	move.w	flydials_3d_colour(pc),d0       ; in the 3D background colour
	bsr.w	fly_set_fill_colour             ; vsf_color
	move.w	d5,d0                           ; x
	bsr.w	fly_draw_bar                    ; v_bar: background
	moveq	#1,d0                           ; black
	bsr.w	fly_set_fill_colour             ; vsf_color(1)
	moveq	#0,d0                           ; hollow
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
.group_frame_lines:
	movem.w	(a4),d0-d3                      ; x, y, w, h
	move.w	d0,d4                           ; d4 = x + w
	move.w	d1,d5                           ; d5 = y + h
	add.w	d2,d4
	add.w	d3,d5
	move.w	d0,d2                           ; (x,y)-(x,y+h)-(x+w,y+h)
	move.w	d5,d3
	bsr.w	fly_draw_polyline               ; v_pline: left and bottom edge
	move.w	d4,d2                           ; (x,y)-(x+w,y)-(x+w,y+h)
	move.w	d1,d3
	bsr.w	fly_draw_polyline               ; v_pline: top and right edge
	movem.w	$a(a6),d0-d1                    ; pb_x, pb_y
	add.w	flydials_char_width(pc),d0      ; title x = pb_x + character width
	add.w	flydials_char_height(pc),d1     ; title y = pb_y + character height - 2
	subq.w	#2,d1
	move.l	$1a(a6),d2                      ; d2 = title text
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.group_title_text               ; no: text in replace mode over the line
	movem.w	d0-d1,(a4)                      ; keep the position
	moveq	#4,d0                           ; reverse transparent
	bsr.w	fly_set_writing_mode            ; vswr_mode(4)
	move.w	flydials_3d_colour(pc),d0       ; in the background colour
	bsr.w	fly_set_text_colour             ; vst_color: clears the line behind the title
	move.w	(a4),d0                         ; x
	bsr.w	fly_draw_label_text             ; v_gtext
	moveq	#1,d0                           ; black
	bsr.w	fly_set_text_colour             ; vst_color(1)
	moveq	#2,d0                           ; transparent
	bsr.w	fly_set_writing_mode            ; vswr_mode(2)
	movem.w	(a4),d0-d1                      ; position again
	move.l	$1a(a6),d2                      ; title text
.group_title_text:
	bsr.w	fly_draw_label_text             ; v_gtext: the title
	bra.w	fly_end_object_draw             ; restore and return the states
	dc.w	$4e75                           ; unused
	move.l	4(sp),d0                        ; entry 4, dialog title: d0 = PARMBLK
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	fly_begin_object_draw           ; set up a6/a5/a4 and the clip rectangle
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.title_text
	moveq	#2,d0                           ; transparent
	bsr.w	fly_set_writing_mode            ; vswr_mode(2)
.title_text:
	move.w	#$ffff,4(a4)                    ; no shortcut underline
	move.w	flydials_char_height(pc),d3     ; character height
	asr.w	#3,d3                           ; /8
	movem.w	$a(a6),d0-d1                    ; pb_x, pb_y
	add.w	$10(a6),d1                      ; y = pb_y + pb_h - height/8
	sub.w	d3,d1
	movea.l	$1a(a6),a0                      ; title text
	cmpi.b	#$20,(a0)                       ; starts with a space?
	bne.s	.title_draw
	addq.l	#1,a0                           ; skip it
.title_draw:
	move.l	a0,d2                           ; d2 = text
	bsr.w	fly_draw_label_text             ; v_gtext
	movem.w	$a(a6),d0-d2                    ; pb_x, pb_y, pb_w
	add.w	d0,d2                           ; x2 = pb_x + pb_w
	add.w	$10(a6),d1                      ; y = pb_y + pb_h + 1: just under the object
	addq.w	#1,d1
	move.w	d1,d3
	moveq	#2,d6
	bsr.w	fly_draw_line                   ; v_pline: the underline
	bra.w	fly_end_object_draw             ; restore and return the states
	move.l	4(sp),d0                        ; entry 5, drag corner: d0 = PARMBLK
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	fly_begin_object_draw           ; set up a6/a5/a4 and the clip rectangle
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.corner_flat                    ; no
	moveq	#1,d0                           ; fill solid
	bsr.w	fly_set_fill_interior           ; vsf_interior(1)
	move.w	flydials_3d_colour(pc),d0       ; in the 3D background colour
	bsr.w	fly_set_fill_colour             ; vsf_color
	bra.s	.corner_draw
.corner_flat:
	moveq	#0,d0                           ; fill hollow
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
.corner_draw:
	movem.w	$a(a6),d0-d3                    ; pb_x, pb_y, pb_w, pb_h
	add.w	d0,d2                           ; x2 = x + w
	add.w	d1,d3                           ; y2 = y + h
	subq.w	#3,d0                           ; corner triangle 3 pixels outside the object
	subq.w	#2,d1
	addq.w	#2,d2
	addq.w	#3,d3
	move.w	d2,d4                           ; (x-3,y-2)-(x-3,y2+3)-(x2+2,y2+3)
	move.w	d3,d5
	move.w	d0,d2
	bsr.w	fly_fill_triangle               ; v_fillarea: lower left half
	bsr.w	fly_draw_polyline               ; v_pline: its left and bottom edge
	move.w	d4,d2                           ; (x-3,y-2)-(x2+2,y2+3)
	move.w	d5,d3
	bsr.w	fly_draw_line                   ; v_pline: the fold
	movem.w	$a(a6),d0-d3                    ; pb_x, pb_y, pb_w, pb_h
	move.w	d0,d4                           ; (x,y)-(x,y+h)-(x+w,y+h)
	move.w	d1,d5
	add.w	d2,d4
	add.w	d3,d5
	move.w	d0,d2
	move.w	d5,d3
	bsr.w	fly_draw_polyline               ; v_pline: inner corner
	bra.w	fly_end_object_draw             ; restore and return the states
	move.l	4(sp),d0                        ; entry 6, button or string: d0 = PARMBLK
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	fly_begin_object_draw           ; set up a6/a5/a4 and the clip rectangle
	bsr.w	fly_get_drawn_object_flags      ; d6 = ob_flags, a1 = the object
	move.w	6(a1),d5                        ; original object type
	asr.w	#8,d5
	dc.w	$ba3c,$001c                     ; cmp.b	#$1c,d5, cmp.b #G_STRING,d5
	beq.s	.button_check_selected          ; string: no frame
	moveq	#0,d5                           ; frame width 1
	btst	#$1,d6                          ; DEFAULT?
	beq.s	.button_exit_border
	addq.w	#1,d5                           ; one pixel more
.button_exit_border:
	btst	#$2,d6                          ; EXIT?
	beq.s	.button_frame
	addq.w	#1,d5                           ; one pixel more
.button_frame:
	moveq	#0,d0                           ; fill hollow
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
	moveq	#1,d0                           ; black
	bsr.w	fly_set_fill_colour             ; vsf_color(1)
	movem.w	$a(a6),d0-d3                    ; pb_x, pb_y, pb_w, pb_h
	add.w	d0,d2                           ; x2 = x + w - 1
	add.w	d1,d3                           ; y2 = y + h - 1
	subq.w	#1,d2
	subq.w	#1,d3
.button_frame_loop:
	movem.w	d0-d3,(a4)                      ; keep the rectangle
	bsr.w	fly_draw_bar                    ; v_bar: one frame line
	addq.w	#1,d0                           ; one pixel further in
	addq.w	#1,d1
	subq.w	#1,d2
	subq.w	#1,d3
	dbra	d5,.button_frame_loop           ; for the frame width
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.button_check_selected
	move.w	#$1,-(sp)                       ; bottom/right black
	move.w	#$0,-(sp)                       ; top/left white: raised
	bsr.w	fly_draw_3d_frame               ; 3D frame
	addq.l	#4,sp
.button_check_selected:
	move.w	8(a6),d0                        ; pb_currstate
	btst	#$0,d0                          ; SELECTED?
	beq.s	.button_text_mode               ; no
	moveq	#3,d0                           ; XOR mode
	bsr.w	fly_set_writing_mode            ; vswr_mode(3)
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.button_invert_flat             ; no: invert the inside
	moveq	#0,d0                           ; white text
	bsr.w	fly_set_text_colour             ; vst_color(0)
	move.w	#$0,-(sp)                       ; bottom/right white
	move.w	#$1,-(sp)                       ; top/left black: pressed in
	bsr.w	fly_draw_3d_frame               ; 3D frame
	addq.l	#4,sp
	bra.s	.button_text_mode
.button_invert_flat:
	moveq	#0,d0                           ; no outline
	bsr.w	fly_set_fill_perimeter          ; vsf_perimeter(0)
	moveq	#1,d0                           ; fill solid
	bsr.w	fly_set_fill_interior           ; vsf_interior(1)
	movem.w	(a4),d0-d3                      ; inside the frame
	addq.w	#1,d0
	addq.w	#1,d1
	subq.w	#1,d2
	subq.w	#1,d3
	bsr.w	fly_draw_bar                    ; v_bar in XOR: inverted
	moveq	#1,d0                           ; outline on
	bsr.w	fly_set_fill_perimeter          ; vsf_perimeter(1)
	moveq	#0,d0                           ; hollow
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
.button_text_mode:
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.button_text
	moveq	#2,d0                           ; transparent text
	bsr.w	fly_set_writing_mode            ; vswr_mode(2)
.button_text:
	movea.l	$1a(a6),a1                      ; text
	bsr.s	fly_count_label_chars           ; d0 = characters to draw (without "[")
	mulu.w	flydials_char_width(pc),d0      ; text width in pixels
	moveq	#0,d2                           ; no offset for a string
	dc.w	$ba3c,$001c                     ; cmp.b	#$1c,d5, cmp.b #G_STRING,d5
	beq.s	.button_text_x
	move.w	$e(a6),d2                       ; button: centre the text
	sub.w	d0,d2
	asr.w	#1,d2
.button_text_x:
	move.w	$a(a6),d0                       ; x = pb_x + offset
	add.w	d2,d0
	move.w	$c(a6),d1                       ; pb_y
	move.w	$10(a6),d2                      ; pb_h
	asr.w	#1,d2                           ; /2
	add.w	d2,d1
	move.w	flydials_char_height(pc),d4     ; + character height/2
	asr.w	#1,d4
	add.w	d4,d1
	subq.w	#2,d1                           ; - 2: text baseline
	dc.w	$b87c,$0008                     ; cmp.w	#$8,d4, cmp.w #8,d4: 16-line font?
	bne.s	.button_text_shift
	subq.w	#1,d1                           ; yes: one higher
.button_text_shift:
	bsr.w	fly_is_3d_object                ; 3D object?
	beq.s	.button_draw_text
	move.w	8(a6),d2                        ; selected?
	btst	#$0,d2
	beq.s	.button_draw_text
	addq.w	#1,d0                           ; 3D and selected: text one pixel down and right
	addq.w	#1,d1
.button_draw_text:
	move.l	$1a(a6),d2                      ; d2 = text
	bsr.w	fly_draw_label_text             ; v_gtext with the shortcut underlined
	moveq	#1,d0                           ; black text again
	bsr.w	fly_set_text_colour             ; vst_color(1)
	bra.w	fly_end_object_draw             ; restore and return the states

;------------------------------------------------------------------------------
; Counts the characters of an object text that are drawn: all but the "[" shortcut marks.
; Entry: a1 = zero-terminated text. Exit: d0 = number of characters.
;------------------------------------------------------------------------------
fly_count_label_chars:
	moveq	#0,d0                           ; count = 0
.next_char:
	move.b	(a1)+,d1                        ; next character
	tst.b	d1
	beq.s	.done                           ; end of the text
	dc.w	$b23c,$005b                     ; cmp.b	#$5b,d1, cmp.b #"[",d1
	beq.s	.next_char                      ; shortcut mark: not counted
	addq.w	#1,d0                           ; count it
	bra.s	.next_char
.done:
	rts

;------------------------------------------------------------------------------
; Fills the rectangle in the work area (x1, y1, x2, y2 at a4) with the 3D background colour and draws its edges:
; left and top in one colour, bottom and right in another, so the object looks raised or pressed in.
; Entry: 4(sp) = colour of the left/top edge, 6(sp) = colour of the bottom/right edge (0 white, 1 black).
; Leaves black lines, black hollow fill.
; Two entries follow without labels: $203a4 (entry 7, draws a 16-pixel wide image from symbol_image_tall or
; symbol_image_short at the object position, transparent) and $203ce (entry 8, a double horizontal line through
; the middle of the object). Both take the PARMBLK at 4(sp) and return the states left for the AES in d0.
;------------------------------------------------------------------------------
fly_draw_3d_frame:
	moveq	#1,d0                           ; fill solid
	bsr.w	fly_set_fill_interior           ; vsf_interior(1)
	move.w	flydials_3d_colour(pc),d0       ; in the 3D background colour
	bsr.w	fly_set_fill_colour             ; vsf_color
	movem.w	(a4),d0-d3                      ; rectangle
	bsr.w	fly_draw_bar                    ; v_bar: background
	moveq	#1,d0                           ; replace mode
	bsr.w	fly_set_writing_mode            ; vswr_mode(1)
	move.w	4(sp),d0                        ; left/top colour
	bsr.w	fly_set_line_colour             ; vsl_color
	move.w	(a4),d0                         ; (x1,y2-1)-(x1,y1)-(x2-1,y1)
	move.w	6(a4),d1
	subq.w	#1,d1
	move.w	(a4),d2
	move.w	2(a4),d3
	move.w	4(a4),d4
	subq.w	#1,d4
	move.w	2(a4),d5
	bsr.w	fly_draw_polyline               ; v_pline: left and top edge
	move.w	6(sp),d0                        ; bottom/right colour
	bsr.w	fly_set_line_colour             ; vsl_color
	move.w	(a4),d0                         ; (x1+1,y2)-(x2,y2)-(x2,y1+1)
	addq.w	#1,d0
	move.w	6(a4),d1
	move.w	4(a4),d2
	move.w	6(a4),d3
	move.w	4(a4),d4
	move.w	2(a4),d5
	addq.w	#1,d5
	bsr.w	fly_draw_polyline               ; v_pline: bottom and right edge
	moveq	#1,d0                           ; black lines
	bsr.w	fly_set_line_colour             ; vsl_color(1)
	moveq	#1,d0                           ; black fill
	bsr.w	fly_set_fill_colour             ; vsf_color(1)
	moveq	#0,d0                           ; hollow
	bsr.w	fly_set_fill_interior           ; vsf_interior(0)
	rts
	move.l	4(sp),d0                        ; entry 7, small image: d0 = PARMBLK
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	fly_begin_object_draw           ; set up a6/a5/a4 and the clip rectangle
	lea	symbol_image_tall(pc),a0        ; 16-line image
	moveq	#16,d0                          ; 16 lines high
	move.w	flydials_char_height(pc),d1     ; character height
	dc.w	$b27c,$0010                     ; cmp.w	#$10,d1, cmp.w #16,d1
	bcc.s	.small_image                    ; 16 or more: the tall image
	lea	symbol_image_short(pc),a0       ; else the 8-line image
	moveq	#8,d0
.small_image:
	moveq	#2,d1                           ; mode 2: transparent
	bsr.s	fly_draw_small_image            ; copy it to pb_x-1, pb_y
	bra.w	fly_end_object_draw             ; restore and return the states
	move.l	4(sp),d0                        ; entry 8, separator line: d0 = PARMBLK
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	bsr.w	fly_begin_object_draw           ; set up a6/a5/a4 and the clip rectangle
	bsr.w	fly_clip_off                    ; clipping off
	movem.w	$a(a6),d0-d3                    ; pb_x, pb_y, pb_w, pb_h
	asr.w	#1,d3                           ; half the height
	add.w	d0,d2                           ; x2 = x + w
	add.w	d3,d1                           ; y = pb_y + pb_h/2 - 1
	subq.w	#1,d1
	move.w	d1,d3
	movem.w	d0-d3,(a4)                      ; keep the line
	bsr.w	fly_draw_line                   ; v_pline: upper line
	movem.w	(a4),d0-d3
	addq.w	#1,d1                           ; one line lower
	addq.w	#1,d3
	bsr.w	fly_draw_line                   ; v_pline: lower line
	bra.w	fly_end_object_draw             ; restore and return the states

;------------------------------------------------------------------------------
; Copies a one-plane image 16 pixels wide to the screen at pb_x-1, pb_y of the object being drawn, through
; fly_copy_raster.
; Entry: a0 = image data, d0 = height in lines, d1 = writing mode (1 replace, 2 transparent), a6 = PARMBLK.
;------------------------------------------------------------------------------
fly_draw_small_image:
	move.w	d1,-(sp)                        ; mode
	move.w	$c(a6),-(sp)                    ; destination y = pb_y
	move.w	$a(a6),d1                       ; destination x = pb_x - 1
	subq.w	#1,d1
	move.w	d1,-(sp)
	move.w	d0,-(sp)                        ; height
	move.w	#$10,-(sp)                      ; width 16
	move.w	#$0,-(sp)                       ; source y 0
	move.w	#$0,-(sp)                       ; source x 0
	move.w	#$0,-(sp)                       ; destination planes (screen)
	move.w	#$0,-(sp)                       ; destination format
	move.w	#$0,-(sp)                       ; destination height
	move.w	#$0,-(sp)                       ; destination width
	move.l	#$0,-(sp)                       ; destination address 0: the screen
	move.w	#$1,-(sp)                       ; source: one plane
	move.w	#$0,-(sp)                       ; source format: device specific
	move.w	d0,-(sp)                        ; source height
	move.w	#$10,-(sp)                      ; source width 16
	move.l	a0,-(sp)                        ; source address
	bsr.s	fly_copy_raster                 ; copy it
	adda.l	#$26,sp                         ; drop the parameters
	rts

;------------------------------------------------------------------------------
; Entry 9 of the module: copies a rectangle between two memory forms with vro_cpyfm, or with vrt_cpyfm when the
; number of planes differs (a one-plane image to the screen). Called with all parameters on the stack (38 bytes):
; 4(sp) source address, 8 width, 10 height, 12 format, 14 planes; 16(sp) destination address (0 = screen), 20 width,
; 22 height, 24 format, 26 planes; 28/30 source x/y, 32/34 width/height, 36/38 destination x/y, 40(sp) mode.
; Mode for vro_cpyfm: 1 gives replace (3), anything else XOR (6); for vrt_cpyfm it is the writing mode, colours 1 and 0.
; Keeps all registers but d0, and the handle in the VDI contrl array.
;------------------------------------------------------------------------------
fly_copy_raster:
	move.l	4(sp),d0                        ; d0 = first parameter (not used)
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	movea.l	flydials_vdi_pb(pc),a5          ; a5 = VDI parameter block
	lea	flydials_work_area(pc),a4       ; a4 = work area
	movea.l	(a5),a0                         ; a0 = contrl
	move.w	$c(a0),$a(a4)                   ; keep the current handle
	moveq	#121,d3                         ; vrt_cpyfm
	moveq	#3,d4                           ; with 3 intin words
	move.w	$60(sp),d5                      ; d5 = mode
	move.w	$46(sp),d0                      ; source planes
	cmp.w	$52(sp),d0                      ; = destination planes?
	bne.s	.fill_source_mfdb               ; no: vrt_cpyfm
	moveq	#109,d3                         ; vro_cpyfm
	moveq	#1,d4                           ; with 1 intin word
	dc.w	$ba7c,$0001                     ; cmp.w	#$1,d5, cmp.w #1,d5
	bne.s	.xor_mode
	moveq	#3,d5                           ; mode 1: S_ONLY (replace)
	bra.s	.fill_source_mfdb
.xor_mode:
	moveq	#6,d5                           ; else S_XOR_D
.fill_source_mfdb:
	lea	fly_source_mfdb(pc),a0          ; source MFDB
	move.l	$3c(sp),(a0)+                   ; address
	move.w	$40(sp),d0                      ; width
	move.w	d0,(a0)+
	move.w	$42(sp),(a0)+                   ; height
	dc.w	$d07c,$000f                     ; add.w	#$f,d0, width in words: (width+15)/16
	asr.w	#4,d0
	move.w	d0,(a0)+
	move.w	$44(sp),(a0)+                   ; format
	move.w	$46(sp),(a0)                    ; planes
	lea	fly_dest_mfdb(pc),a0            ; destination MFDB
	move.l	$48(sp),(a0)+                   ; address
	move.w	$4c(sp),d0                      ; width
	move.w	d0,(a0)+
	move.w	$4e(sp),(a0)+                   ; height
	dc.w	$d07c,$000f                     ; add.w	#$f,d0, width in words
	asr.w	#4,d0
	move.w	d0,(a0)+
	move.w	$50(sp),(a0)+                   ; format
	move.w	$52(sp),(a0)                    ; planes
	movea.l	flydials_vdi_pb(pc),a0          ; VDI parameter block
	movea.l	4(a0),a1                        ; a1 = intin
	move.w	d5,(a1)+                        ; intin[0] = mode
	move.w	#$1,(a1)+                       ; intin[1] = 1: set pixels colour
	move.w	#$0,(a1)                        ; intin[2] = 0: clear pixels colour
	movea.l	8(a0),a1                        ; a1 = ptsin
	move.w	$54(sp),(a1)+                   ; source x1
	move.w	$56(sp),(a1)+                   ; source y1
	move.w	$58(sp),d0                      ; width - 1
	subq.w	#1,d0
	move.w	$5a(sp),d1                      ; height - 1
	subq.w	#1,d1
	move.w	$54(sp),(a1)                    ; source x2
	add.w	d0,(a1)+
	move.w	$56(sp),(a1)                    ; source y2
	add.w	d1,(a1)+
	move.w	$5c(sp),(a1)+                   ; destination x1
	move.w	$5e(sp),(a1)+                   ; destination y1
	move.w	$5c(sp),(a1)                    ; destination x2
	add.w	d0,(a1)+
	move.w	$5e(sp),(a1)                    ; destination y2
	add.w	d1,(a1)+
	movea.l	(a0),a1                         ; a1 = contrl
	move.w	d3,(a1)                         ; contrl[0] = opcode
	move.w	#$4,2(a1)                       ; contrl[1] = 4 points
	move.w	#$0,4(a1)                       ; contrl[2] = 0
	move.w	d4,6(a1)                        ; contrl[3] = intin count
	move.w	#$0,8(a1)                       ; contrl[4] = 0
	move.w	#$0,$a(a1)                      ; contrl[5] = 0
	move.w	flydials_vdi_handle(pc),$c(a1)  ; contrl[6] = handle
	lea	fly_source_mfdb(pc),a2          ; contrl[7..8] = source MFDB
	move.l	a2,d0
	move.w	d0,$10(a1)
	swap	d0
	move.w	d0,$e(a1)
	lea	fly_dest_mfdb(pc),a2            ; contrl[9..10] = destination MFDB
	move.l	a2,d0
	move.w	d0,$14(a1)
	swap	d0
	move.w	d0,$12(a1)
	move.l	a0,d1                           ; d1 = VDI parameter block
	moveq	#115,d0                         ; VDI
	trap	#2                              ; AES/VDI
	movea.l	flydials_vdi_pb(pc),a5          ; restore the previous handle in contrl
	lea	flydials_work_area(pc),a4
	movea.l	(a5),a0
	move.w	$a(a4),$c(a0)
	movem.l	(sp)+,d1-d7/a0-a6               ; restore the registers
	rts

;------------------------------------------------------------------------------
; Finds the object being drawn: a1 = pb_tree + pb_obj * 24, d6 = its ob_flags.
; Entry: a6 = PARMBLK.
; Two entries follow without labels:
; $2058e, entry 10: 4(sp) = tree address, 8(sp) = object number; returns d0 = address of the object's text: the string
; of a G_BUTTON, G_STRING or G_TITLE, te_ptext of a text object, ib_ptext of an icon, or a one-character string made
; from the character of a G_BOX, G_IBOX or G_BOXCHAR (kept in the work area). A USERDEF object is looked at through
; its USERBLK as the original type.
; $20604, entry 11: 4(sp) = cookie id; returns d0 = the cookie value, or 0 when there is no such cookie or no cookie
; jar.
;------------------------------------------------------------------------------
fly_get_drawn_object_flags:
	movea.l	(a6),a1                         ; a1 = tree
	move.w	4(a6),d6                        ; object number
	mulu.w	#$18,d6                         ; * 24 bytes
	adda.l	d6,a1                           ; a1 = the object
	move.w	8(a1),d6                        ; d6 = ob_flags
	rts
	move.l	4(sp),d0                        ; entry 10, object text: d0 = tree
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	movea.l	d0,a0
	move.w	$40(sp),d1                      ; object number
	mulu.w	#$18,d1                         ; * 24 bytes
	adda.l	d1,a0                           ; a0 = the object
	move.w	6(a0),d0                        ; d0 = ob_type
	movea.l	$c(a0),a0                       ; a0 = ob_spec
	dc.w	$b03c,$0018                     ; cmp.b	#$18,d0, cmp.b #G_USERDEF,d0
	bne.s	.check_type
	movea.l	4(a0),a0                        ; a0 = ub_parm: the original ob_spec
	asr.w	#8,d0                           ; d0 = original type
.check_type:
	dc.w	$b03c,$0014                     ; cmp.b	#$14,d0, cmp.b #G_BOX,d0
	beq.s	.box_char
	dc.w	$b03c,$0019                     ; cmp.b	#$19,d0, cmp.b #G_IBOX,d0
	beq.s	.box_char
	dc.w	$b03c,$001b                     ; cmp.b	#$1b,d0, cmp.b #G_BOXCHAR,d0
	bne.s	.check_string_types
.box_char:
	move.l	a0,d0                           ; character = high byte of ob_spec
	asr.l	#8,d0
	asr.l	#8,d0
	asr.l	#8,d0
	lea	flydials_work_area(pc),a0       ; make it a one-character string
	move.b	d0,(a0)
	clr.b	1(a0)
	bra.s	.return_text
.check_string_types:
	dc.w	$b03c,$001a                     ; cmp.b	#$1a,d0, cmp.b #G_BUTTON,d0
	beq.s	.return_text                    ; the spec is the string
	dc.w	$b03c,$001c                     ; cmp.b	#$1c,d0, cmp.b #G_STRING,d0
	beq.s	.return_text
	dc.w	$b03c,$0020                     ; cmp.b	#$20,d0, cmp.b #G_TITLE,d0
	beq.s	.return_text
	dc.w	$b03c,$001f                     ; cmp.b	#$1f,d0, cmp.b #G_ICON,d0
	bne.s	.text_object
	movea.l	8(a0),a0                        ; ib_ptext
	bra.s	.return_text
.text_object:
	movea.l	(a0),a0                         ; te_ptext of the TEDINFO
.return_text:
	move.l	a0,d0                           ; d0 = text address
	movem.l	(sp)+,d1-d7/a0-a6               ; restore the registers
	rts
	move.l	4(sp),d0                        ; entry 11, cookie value: d0 = cookie id
	movem.l	d1-d7/a0-a6,-(sp)               ; keep the registers
	move.l	d0,d3                           ; d3 = id
	clr.l	-(sp)                           ; Super(0)
	move.w	#$20,-(sp)
	trap	#1                              ; Super, Super
	move.l	d0,2(sp)                        ; keep the old stack for the way back
	movea.l	$5a0,a0                         ; _p_cookies, a0 = cookie jar
	beq.s	.no_cookie                      ; none
.next_cookie:
	move.l	(a0)+,d1                        ; cookie id
	move.l	(a0)+,d0                        ; its value
	cmp.l	d3,d1                           ; the one wanted?
	beq.s	.return_cookie
	tst.l	d1                              ; end of the jar?
	bne.s	.next_cookie
.no_cookie:
	moveq	#0,d0                           ; not found: 0
.return_cookie:
	move.l	d0,d3                           ; d3 = result
	trap	#1                              ; GEMDOS, Super(old stack): back to user mode
	addq.l	#6,sp
	move.l	d3,d0                           ; d0 = cookie value
	movem.l	(sp)+,d1-d7/a0-a6               ; restore the registers
	rts

;------------------------------------------------------------------------------
; Tells whether the object being drawn gets the 3D look: the 3D look must be on and the object must have one of the
; AES 3D flags (FL3DIND $200, FL3DBAK $400).
; Entry: a6 = PARMBLK. Exit: Z clear for a 3D object; d6 = the flags tested, a1 = the object.
;------------------------------------------------------------------------------
fly_is_3d_object:
	move.w	flydials_3d_on(pc),d6           ; 3D look on?
	beq.s	.done                           ; no: Z set
	bsr.w	fly_get_drawn_object_flags      ; d6 = ob_flags
	dc.w	$cc7c,$0600                     ; and.w	#$600,d6, and.w #$600,d6: FL3DIND / FL3DBAK
.done:
	rts

;------------------------------------------------------------------------------
; vs_clip on: sets the clip rectangle.
; Entry: d0-d3 = x, y, w, h; a5 = VDI parameter block.
;------------------------------------------------------------------------------
fly_set_clip_rectangle:
	movea.l	4(a5),a1                        ; intin[0] = 1: clipping on
	move.w	#$1,(a1)
	add.w	d0,d2                           ; x2 = x + w - 1
	subq.w	#1,d2
	add.w	d1,d3                           ; y2 = y + h - 1
	subq.w	#1,d3
	movea.l	8(a5),a1                        ; ptsin = corners
	movem.w	d0-d3,(a1)
	move.l	#$81010002,d6                   ; vs_clip, 1 intin word, 2 points
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; vs_clip off.
; Entry: a5 = VDI parameter block.
;------------------------------------------------------------------------------
fly_clip_off:
	movea.l	4(a5),a1                        ; intin[0] = 0: clipping off
	clr.w	(a1)
	move.l	#$81010002,d6                   ; vs_clip
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; vsf_perimeter: outline filled areas or not. After it come the bytes of an unused v_ellipse call.
; Entry: d0 = 0 off, 1 on.
;------------------------------------------------------------------------------
fly_set_fill_perimeter:
	movea.l	4(a5),a1                        ; intin[0] = flag
	move.w	d0,(a1)
	move.l	#$68010000,d6                   ; vsf_perimeter
	bra.w	fly_vdi_call

; Not called: v_ellipse with the centre and the radii in d0-d3.
	movea.l	8(a5),a1                        ; ptsin
	movem.w	d0-d3,(a1)                      ; x, y, x radius, y radius
	move.l	#$0b000502,d6                   ; v_ellipse (opcode 11, function 5), 2 points in
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; v_ellarc.
; Entry: d0/d1 = centre, d2/d3 = x/y radius, d4/d5 = start and end angle in tenths of a degree.
;------------------------------------------------------------------------------
fly_draw_elliptical_arc:
	movea.l	8(a5),a1                        ; ptsin = centre and radii
	movem.w	d0-d3,(a1)
	movea.l	4(a5),a1                        ; intin = angles
	movem.w	d4-d5,(a1)
	move.l	#$b020602,d6                    ; GDP 6 v_ellarc
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; v_ellpie: a filled ellipse sector.
; Entry: d0/d1 = centre, d2/d3 = x/y radius, d4/d5 = start and end angle in tenths of a degree.
;------------------------------------------------------------------------------
fly_draw_elliptical_pie:
	movea.l	8(a5),a1                        ; ptsin = centre and radii
	movem.w	d0-d3,(a1)
	movea.l	4(a5),a1                        ; intin = angles
	movem.w	d4-d5,(a1)
	move.l	#$b020702,d6                    ; GDP 7 v_ellpie
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; vsf_interior.
; Entry: d0 = 0 hollow, 1 solid, 2 pattern.
;------------------------------------------------------------------------------
fly_set_fill_interior:
	movea.l	4(a5),a1                        ; intin[0] = style
	move.w	d0,(a1)
	move.l	#$17010000,d6                   ; vsf_interior
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; vsf_color.
; Entry: d0 = colour.
;------------------------------------------------------------------------------
fly_set_fill_colour:
	movea.l	4(a5),a1                        ; intin[0] = colour
	move.w	d0,(a1)
	move.l	#$19010000,d6                   ; vsf_color
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; vswr_mode.
; Entry: d0 = 1 replace, 2 transparent, 3 XOR, 4 reverse transparent.
;------------------------------------------------------------------------------
fly_set_writing_mode:
	movea.l	4(a5),a1                        ; intin[0] = mode
	move.w	d0,(a1)
	move.l	#$20010000,d6                   ; vswr_mode
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; v_bar: a filled rectangle (with outline when the perimeter is on).
; Entry: d0-d3 = x1, y1, x2, y2.
;------------------------------------------------------------------------------
fly_draw_bar:
	movea.l	8(a5),a1                        ; ptsin = corners
	movem.w	d0-d3,(a1)
	move.l	#$b000102,d6                    ; GDP 1 v_bar
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; v_pline with two points.
; Entry: d0-d3 = x1, y1, x2, y2.
;------------------------------------------------------------------------------
fly_draw_line:
	movea.l	8(a5),a1                        ; ptsin = 2 points
	movem.w	d0-d3,(a1)
	move.l	#$6000002,d6                    ; v_pline, 2 points
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; v_pline with three points.
; Entry: d0-d5 = x1, y1, x2, y2, x3, y3.
;------------------------------------------------------------------------------
fly_draw_polyline:
	movea.l	8(a5),a1                        ; ptsin = 3 points
	movem.w	d0-d5,(a1)
	move.l	#$6000003,d6                    ; v_pline, 3 points
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; vsl_color.
; Entry: d0 = colour.
;------------------------------------------------------------------------------
fly_set_line_colour:
	movea.l	4(a5),a1                        ; intin[0] = colour
	move.w	d0,(a1)
	move.l	#$11010000,d6                   ; vsl_color
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; vst_color.
; Entry: d0 = colour.
;------------------------------------------------------------------------------
fly_set_text_colour:
	movea.l	4(a5),a1                        ; intin[0] = colour
	move.w	d0,(a1)
	move.l	#$16010000,d6                   ; vst_color
	bra.w	fly_vdi_call

;------------------------------------------------------------------------------
; v_fillarea with three points.
; Entry: d0-d5 = x1, y1, x2, y2, x3, y3.
;------------------------------------------------------------------------------
fly_fill_triangle:
	movea.l	8(a5),a1                        ; ptsin = 3 points
	movem.w	d0-d5,(a1)
	move.l	#$9000003,d6                    ; v_fillarea, 3 points
	bra.s	fly_vdi_call

;------------------------------------------------------------------------------
; v_gtext for an object text: copies the text to intin leaving out the "[" marks, and when a "[" was found and
; underlining is allowed (4(a4) not negative), underlines the letter after it.
; Entry: d0/d1 = x/y of the text, d2 = address of the text, a4 = work area (+0 x of the shortcut letter, +2 y,
; +4 negative = no underline, +6 negative = no "[" found).
;------------------------------------------------------------------------------
fly_draw_label_text:
	movea.l	8(a5),a1                        ; ptsin = text position
	movem.w	d0-d1,(a1)
	movem.w	d0-d1,(a4)                      ; shortcut position starts at the text position
	movea.l	4(a5),a1                        ; a1 = intin
	movea.l	d2,a0                           ; a0 = text
	moveq	#0,d0
	moveq	#0,d1                           ; d1 = characters + 1
	moveq	#0,d2                           ; d2 = pixel offset of the next character
	move.w	#$ffff,6(a4)                    ; no "[" found yet
	clr.w	4(a4)                           ; underline allowed
.count_char:
	addq.w	#1,d1                           ; count the character
.next_char:
	move.b	(a0)+,d0                        ; next character
	dc.w	$b03c,$005b                     ; cmp.b	#$5b,d0, cmp.b #"[",d0
	bne.s	.store_char
	add.w	d2,(a4)                         ; shortcut x = text x + offset so far
	clr.w	6(a4)                           ; "[" found
	bra.s	.next_char                      ; not drawn itself
.store_char:
	add.w	flydials_char_width(pc),d2      ; next pixel offset
	move.w	d0,(a1)+                        ; into intin
	bne.s	.count_char                     ; up to the terminating 0
	move.l	#$8ff0001,d6                    ; v_gtext, intin count set here
	subq.w	#1,d1                           ; d1 = characters
	movea.l	(a5),a0
	move.w	d1,6(a0)                        ; contrl[3] = intin count
	tst.w	4(a4)                           ; underlining off?
	bmi.s	fly_vdi_call                    ; yes: just draw the text
	tst.w	6(a4)                           ; no "[" in the text?
	bmi.s	fly_vdi_call                    ; yes: just draw the text
	bsr.s	fly_vdi_call                    ; draw the text
	movem.w	(a4),d0-d1                      ; shortcut x, y
	move.w	flydials_char_height(pc),d2     ; character height
	asr.w	#3,d2                           ; /8
	add.w	d2,d1                           ; y = baseline + height/8
	move.w	d1,d3
	move.w	d0,d2                           ; x2 = x + character width - 1
	add.w	flydials_char_width(pc),d2
	subq.w	#1,d2
	bra.w	fly_draw_line                   ; v_pline: the underline

;------------------------------------------------------------------------------
; Makes a VDI call through the module's parameter block with the module's workstation handle.
; Entry: d6 = packed contrl values: bits 31-24 opcode, 23-16 intin count ($ff: leave contrl[3] as set),
; 15-8 sub-opcode (contrl[5]), 7-0 ptsin count; intin/ptsin already filled; a5 = VDI parameter block.
; Keeps all registers.
;------------------------------------------------------------------------------
fly_vdi_call:
	movem.l	d0-d7/a0-a6,-(sp)               ; keep all registers
	movea.l	(a5),a0                         ; a0 = contrl
	clr.w	4(a0)                           ; contrl[2] = 0
	clr.w	8(a0)                           ; contrl[4] = 0
	clr.w	2(a0)                           ; contrl[1] = ptsin count
	move.b	d6,3(a0)
	clr.w	$a(a0)                          ; contrl[5] = sub-opcode
	lsr.l	#8,d6
	move.b	d6,$b(a0)
	lsr.l	#8,d6                           ; intin count
	dc.w	$bc3c,$00ff                     ; cmp.b	#$ff,d6, cmp.b #$ff,d6: set by the caller?
	beq.s	.set_opcode
	clr.w	6(a0)                           ; contrl[3] = intin count
	move.b	d6,7(a0)
.set_opcode:
	clr.w	(a0)                            ; contrl[0] = opcode
	lsr.l	#8,d6
	move.b	d6,1(a0)
	move.w	flydials_vdi_handle(pc),$c(a0)  ; contrl[6] = handle
	move.l	a5,d1                           ; d1 = VDI parameter block
	move.w	#$73,d0                         ; VDI
	trap	#2                              ; AES/VDI
	movem.l	(sp)+,d0-d7/a0-a6               ; restore all registers
	rts

;------------------------------------------------------------------------------
; Start of every drawing entry: a6 = PARMBLK, a5 = VDI parameter block, a4 = work area; keeps the handle found in
; contrl[6] (restored on exit) and clips to the PARMBLK clip rectangle.
; Entry: d0 = PARMBLK address.
;------------------------------------------------------------------------------
fly_begin_object_draw:
	movea.l	d0,a6                           ; a6 = PARMBLK
	movea.l	flydials_vdi_pb(pc),a5          ; a5 = VDI parameter block
	lea	flydials_work_area(pc),a4       ; a4 = work area
	movea.l	(a5),a0                         ; a0 = contrl
	move.w	$c(a0),8(a4)                    ; keep the caller's handle
	movem.w	$12(a6),d0-d3                   ; pb_xc, pb_yc, pb_wc, pb_hc
	bsr.w	fly_set_clip_rectangle          ; clip to it
	rts

;------------------------------------------------------------------------------
; Common end of the drawing entries: replace mode, clipping off, the caller's handle back in contrl[6]; returns
; d0 = pb_currstate without SELECTED, CROSSED, CHECKED and OUTLINED, which the module drew itself, and restores the
; registers saved on entry.
;------------------------------------------------------------------------------
fly_end_object_draw:
	moveq	#1,d0                           ; replace mode
	bsr.w	fly_set_writing_mode            ; vswr_mode(1)
	bsr.w	fly_clip_off                    ; clipping off
	movea.l	(a5),a0                         ; a0 = contrl
	move.w	8(a4),$c(a0)                    ; caller's handle back
	move.w	8(a6),d0                        ; d0 = pb_currstate
	bclr	#$0,d0                          ; SELECTED drawn here
	bclr	#$1,d0                          ; CROSSED drawn here
	bclr	#$2,d0                          ; CHECKED drawn here
	bclr	#$4,d0                          ; OUTLINED drawn here
	movem.l	(sp)+,d1-d7/a0-a6               ; restore the registers saved on entry
	rts

; Work area of the module (a4): +0/+2 a rectangle or the shortcut letter position, +4 underline-off flag, +6 no-"["
; flag, +8 handle saved by fly_begin_object_draw, +$a handle saved by fly_copy_raster. Entry 10 also builds its
; one-character string here.
flydials_work_area:
	dc.w	$012c,$0138,$0000,$0000,$0002,$0002

; Image for entry 7 when the character height is 16 x 16 pixels, one plane, 32 bytes. In this file these bytes,
; and the start of radio_off_image_tall, hold left-over text instead of image data.
symbol_image_tall:
	dc.b	'     --UVK Recognition Statistic'

; Image for entry 7 when the character height is 8: 16 x 8 pixels, one plane.
symbol_image_short:
	dc.b	's--             '

; Radio button not selected, 16 x 16 pixels, one plane (its first three words are overwritten by the text above).
radio_off_image_tall:
	dc.b	'     ',0                       ; first words overwritten with spaces
	dc.w	$2002,$2002,$4001,$4001,$4001,$4001,$4001,$2002
	dc.w	$2002,$1004,$0c18,$03e0,$0000

; Radio button selected, 16 x 16 pixels, one plane.
radio_on_image_tall:
	dc.w	$03e0,$0c18,$11c4,$27f2,$2ffa,$4ff9,$5ffd,$5ffd
	dc.w	$5ffd,$4ff9,$2ffa,$27f2,$11c4,$0c18,$03e0,$0000

; Radio button not selected, 16 x 8 pixels, one plane.
radio_off_image_short:
	dc.w	$07c0,$0820,$1010,$1010,$1010,$1010,$0820,$07c0

; Radio button selected, 16 x 8 pixels, one plane.
radio_on_image_short:
	dc.w	$07c0,$0820,$17d0,$17d0,$17d0,$17d0,$0820,$07c0

; Source memory form definition block built by fly_copy_raster (address, width, height, width in words, format, planes,
; 3 reserved).
fly_source_mfdb:
	dc.w	$0021,$68ae,$022e,$0176,$0023,$0000,$0001,$0000
	dc.w	$0000,$0000

; Destination memory form definition block built by fly_copy_raster.
fly_dest_mfdb:
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0001,$0000
	dc.w	$0000,$0000
	dc.b	'TSN_SYLQ'                      ; end of the module
