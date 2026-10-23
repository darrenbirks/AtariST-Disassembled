; RSC.S  -  the resource of FCOPYPRO.PRG, included by FCOPYPRO.S in the data section
;
; Compiled in from an RSH file: the shared button strings, the TEDINFOs, the logo BITBLK,
; the 14 object trees, their strings, and the coordinates used in high resolution
; (high_res_coords).  run_fastcopy fixes the objects with rsrc_obfix on the first start.

str_empty:
	dc.b	$00
str_cancel:
	dc.b	'CANCEL',0
str_ok:
	dc.b	'OK',0
str_abort:
	dc.b	'ABORT',0
	dc.b	$00
; TEDINFOs: te_ptext, te_ptmplt, te_pvalid, then te_font, te_junk1, te_just, te_color,
; te_junk2, te_thickness, te_txtlen, te_tmplen
ted_00:
	dc.l	ted_00_text,str_empty,str_empty ; '¯ FastCopy PRO 1.2 ®    --    ½ 1986-94 by Martin Backschat / ICP / ACN'
	dc.w	3,6,2,$1180,0,0,64,1
ted_01:
	dc.l	ted_01_text,str_empty,str_empty ; '00000000001111111111222222222233333333334444444444555555555566666'
	dc.w	5,6,0,$1180,0,-1,66,1
ted_02:
	dc.l	ted_02_text,str_empty,str_empty ; '6666677777777778888888'
	dc.w	5,6,0,$1180,0,-1,23,1
ted_03:
	dc.l	ted_03_text,str_empty,str_empty ; '01234567890123456789012345678901234567890123456789012345678901234'
	dc.w	5,6,0,$1180,0,-1,66,1
ted_04:
	dc.l	ted_04_text,str_empty,str_empty ; '5678901234567890123456'
	dc.w	5,6,0,$1180,0,-1,23,1
ted_05:
	dc.l	ted_05_text,str_empty,str_empty ; '1234567'
	dc.w	3,0,2,$1100,0,-1,8,1
ted_06:
	dc.l	ted_06_text,str_empty,str_empty ; '1234567'
	dc.w	3,0,2,$1100,0,-1,8,1
ted_07:
	dc.l	ted_07_text,str_empty,str_empty ; '1234567'
	dc.w	3,0,2,$1100,0,-1,8,1
ted_08:
	dc.l	ted_08_text,str_empty,str_empty ; '1234567'
	dc.w	3,0,2,$1100,0,-1,8,1
ted_09:
	dc.l	ted_09_text,str_empty,str_empty ; '1234567'
	dc.w	3,0,2,$1100,0,-1,8,1
ted_10:
	dc.l	ted_10_text,ted_10_tmplt,ted_10_valid ; '09'
	dc.w	3,6,0,$1180,0,-1,3,3
ted_11:
	dc.l	ted_11_text,ted_11_tmplt,ted_11_valid ; '99'
	dc.w	3,6,0,$1180,0,-1,3,3
ted_12:
	dc.l	ted_12_text,ted_12_tmplt,ted_12_valid ; '79'
	dc.w	3,6,0,$1180,0,-1,3,3
ted_13:
	dc.l	ted_13_text,str_empty,str_empty ; 'DD'
	dc.w	3,0,2,$1100,0,-1,3,1
ted_14:
	dc.l	ted_14_text,str_empty,str_empty ; 'HD'
	dc.w	3,0,2,$1100,0,-1,3,1
ted_15:
	dc.l	ted_15_text,ted_15_tmplt,ted_15_valid ; ''
	dc.w	3,6,0,$1180,0,0,12,23
ted_16:
	dc.l	str_empty,str_empty,str_empty   ; ''
	dc.w	3,6,0,$1180,0,-1,4,1
ted_17:
	dc.l	str_empty,str_empty,str_empty   ; ''
	dc.w	3,6,0,$1180,0,-1,2,1
ted_18:
	dc.l	ted_18_text,str_empty,str_empty ; 'MS DOS'
	dc.w	3,4353,2,$1100,24,-1,7,1
ted_19:
	dc.l	ted_19_text,str_empty,str_empty ; 'TOS'
	dc.w	3,-1,2,$1100,64,-1,4,1
ted_20:
	dc.l	ted_20_text,str_empty,str_empty ; 'Optimized'
	dc.w	3,4352,2,$1100,24,-1,10,1
ted_21:
	dc.l	str_empty,str_empty,str_empty   ; ''
	dc.w	3,-4,2,$1172,16383,0,40,1
ted_22:
	dc.l	str_empty,str_empty,str_empty   ; ''
	dc.w	3,6,2,$1180,0,0,29,1
ted_23:
	dc.l	ted_23_text,str_empty,str_empty ; 'X:'
	dc.w	3,0,2,$1180,0,0,3,1
ted_24:
	dc.l	ted_24_text,str_empty,str_empty ; 'Data Storage'
	dc.w	3,0,2,$1180,0,0,13,1
ted_25:
	dc.l	ted_25_text,str_empty,str_empty ; 'Formatting'
	dc.w	3,0,2,$1180,0,0,11,1
ted_26:
	dc.l	ted_26_text,str_empty,str_empty ; 'User Interface'
	dc.w	3,0,2,$1180,0,0,15,1
ted_27:
	dc.l	ted_27_text,ted_27_tmplt,ted_27_valid ; '9999'
	dc.w	3,6,0,$1180,0,-1,5,11
ted_28:
	dc.l	ted_28_text,ted_28_tmplt,ted_28_valid ; '99'
	dc.w	3,6,0,$1180,0,-1,3,3
ted_29:
	dc.l	ted_29_text,str_empty,str_empty ; 'Error'
	dc.w	3,0,2,$1180,0,0,6,1
ted_30:
	dc.l	ted_30_text,str_empty,str_empty ; 'Accessory'
	dc.w	3,0,2,$1180,0,0,10,1
ted_31:
	dc.l	ted_31_text,str_empty,str_empty ; 'DD'
	dc.w	3,6,2,$1180,0,-1,3,1
ted_32:
	dc.l	ted_32_text,str_empty,str_empty ; 'HD 5¬'
	dc.w	3,6,2,$1180,0,-1,6,1
ted_33:
	dc.l	ted_33_text,str_empty,str_empty ; 'HD 3«'
	dc.w	3,6,2,$1180,0,-1,6,1
ted_34:
	dc.l	ted_34_text,str_empty,str_empty ; '2'
	dc.w	3,0,2,$1100,0,-1,2,1
ted_35:
	dc.l	ted_35_text,str_empty,str_empty ; '3'
	dc.w	3,0,2,$1100,0,-1,2,1
ted_36:
	dc.l	ted_36_text,str_empty,str_empty ; '6'
	dc.w	3,0,2,$1100,0,-1,2,1
ted_37:
	dc.l	ted_37_text,str_empty,str_empty ; '12'
	dc.w	3,0,2,$1100,0,-1,3,1
ted_38:
	dc.l	ted_38_text,str_empty,str_empty ; 'DD'
	dc.w	3,6,2,$1180,0,-1,3,1
ted_39:
	dc.l	ted_39_text,str_empty,str_empty ; 'HD 5¬'
	dc.w	3,6,2,$1180,0,-1,6,1
ted_40:
	dc.l	ted_40_text,str_empty,str_empty ; 'HD 3«'
	dc.w	3,6,2,$1180,0,-1,6,1
ted_41:
	dc.l	ted_41_text,str_empty,str_empty ; '2'
	dc.w	3,0,2,$1100,0,-1,2,1
ted_42:
	dc.l	ted_42_text,str_empty,str_empty ; '3'
	dc.w	3,0,2,$1100,0,-1,2,1
ted_43:
	dc.l	ted_43_text,str_empty,str_empty ; '6'
	dc.w	3,0,2,$1100,0,-1,2,1
ted_44:
	dc.l	ted_44_text,str_empty,str_empty ; '12'
	dc.w	3,0,2,$1100,0,-1,3,1
ted_45:
	dc.l	ted_45_text,str_empty,str_empty ; 'Drive A'
	dc.w	3,0,2,$1180,0,0,8,1
ted_46:
	dc.l	ted_46_text,str_empty,str_empty ; 'Drive B'
	dc.w	3,0,2,$1180,0,0,8,1
ted_47:
	dc.l	ted_47_text,str_empty,str_empty ; 'Automatic/Switch'
	dc.w	3,6,2,$1180,0,-1,17,1
ted_48:
	dc.l	ted_48_text,str_empty,str_empty ; 'Low'
	dc.w	3,6,2,$1180,0,-1,4,1
ted_49:
	dc.l	ted_49_text,str_empty,str_empty ; 'High'
	dc.w	3,6,2,$1180,0,-1,5,1
ted_50:
	dc.l	ted_50_text,str_empty,str_empty ; 'Low'
	dc.w	3,6,2,$1180,0,-1,4,1
ted_51:
	dc.l	ted_51_text,str_empty,str_empty ; 'High'
	dc.w	3,6,2,$1180,0,-1,5,1
ted_52:
	dc.l	ted_52_text,str_empty,str_empty ; 'High Density Detect'
	dc.w	3,0,2,$1180,0,0,20,1
ted_53:
	dc.l	ted_53_text,ted_53_tmplt,ted_53_valid ; '99999'
	dc.w	3,6,0,$1180,0,0,6,6
ted_54:
	dc.l	ted_54_text,str_empty,str_empty ; 'F1'
	dc.w	3,6,0,$1180,0,-1,3,1
ted_55:
	dc.l	ted_55_text,str_empty,str_empty ; 'F2'
	dc.w	3,6,0,$1180,0,-1,3,1
ted_56:
	dc.l	ted_56_text,str_empty,str_empty ; 'C->S'
	dc.w	3,6,0,$1180,0,-1,5,1
ted_57:
	dc.l	ted_57_text,str_empty,str_empty ; 'I->M'
	dc.w	3,6,0,$1180,0,-1,5,1
ted_58:
	dc.l	ted_58_text,ted_58_tmplt,ted_58_valid ; ''
	dc.w	3,6,0,$1180,0,-1,66,66
ted_59:
	dc.l	ted_59_text,ted_59_tmplt,ted_59_valid ; ''
	dc.w	3,6,0,$1180,0,-1,6,25
ted_60:
	dc.l	ted_60_text,ted_60_tmplt,ted_60_valid ; ''
	dc.w	3,6,0,$1180,0,-1,6,16
ted_61:
	dc.l	ted_61_text,ted_61_tmplt,ted_61_valid ; ''
	dc.w	3,6,0,$1180,0,-1,61,61
ted_62:
	dc.l	ted_62_text,ted_62_tmplt,ted_62_valid ; '_______'
	dc.w	3,6,0,$1180,0,-1,8,30
ted_63:
	dc.l	ted_63_text,ted_63_tmplt,ted_63_valid ; ''
	dc.w	3,6,0,$1180,0,-1,6,23
ted_64:
	dc.l	ted_64_text,ted_64_tmplt,ted_64_valid ; ''
	dc.w	3,6,0,$1180,0,-1,6,16
ted_65:
	dc.l	ted_65_text,ted_65_tmplt,ted_65_valid ; ''
	dc.w	3,6,0,$1180,0,-1,6,21
logo_image:
	dc.w	$3040,$0000,$0000,$1860,$0000,$0000
	dc.w	$0c7f,$ffff,$fe00,$0679,$0000,$4200
	dc.w	$036d,$0000,$5a00,$01ef,$0000,$5a00
	dc.w	$00eb,$0000,$4200,$0069,$8000,$4200
	dc.w	$0029,$c000,$4200,$0009,$6200,$4200
	dc.w	$0009,$3200,$4200,$0009,$1a00,$4200
	dc.w	$0009,$0e00,$4200,$0009,$3e00,$4200
	dc.w	$0009,$0000,$4200,$0009,$0000,$4200
	dc.w	$0008,$ffff,$8200,$0008,$0000,$0200
	dc.w	$0008,$0000,$0200,$0008,$1fff,$c200
	dc.w	$0008,$3ffe,$2200,$0008,$31fe,$2200
	dc.w	$0008,$31fe,$2200,$0008,$31fe,$2200
	dc.w	$0008,$31fe,$2200,$0008,$31fe,$2200
	dc.w	$0004,$3ffe,$2200,$0003,$ffff,$fe00

logo_bitblk:
	dc.l	logo_image                      ; bi_pdata
	dc.w	6,28,0,0,1                      ; bi_wb, bi_hl, bi_x, bi_y, bi_color
; OBJECTs: ob_next, ob_head, ob_tail, ob_type, ob_flags, ob_state, ob_spec,
; ob_x, ob_y, ob_width, ob_height (low byte characters, high byte pixels)

; tree 0: main dialog: functions, presets, options, drives, disk configuration
main_tree:
	dc.w	-1,1,75,G_BOX,0,0                                       ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$044d,$0217
	dc.w	2,-1,-1,G_BOXTEXT,TOUCHEXIT,SELECTED                    ; 1 '¯ FastCopy PRO 1.2 ®    --    ½ 1986-94 by Martin Backschat / ICP / ACN'
	dc.l	ted_00
	dc.w	$0003,$0000,$0149,$0201
	dc.w	3,-1,-1,G_BUTTON,0,0                                    ; 2 ''
	dc.l	str_empty
	dc.w	$0600,$0201,$004c,$0001
	dc.w	8,4,7,G_BOX,0,0                                         ; 3
	dc.l	$00ff1101
	dc.w	$0600,$0302,$004c,$0707
	dc.w	5,-1,-1,G_TEXT,0,0                                      ; 4 '00000000001111111111222222222233333333334444444444555555555566666'
	dc.l	ted_01
	dc.w	$0105,$0006,$0630,$0001
	dc.w	6,-1,-1,G_TEXT,0,0                                      ; 5 '6666677777777778888888'
	dc.l	ted_02
	dc.w	$0735,$0006,$0410,$0001
	dc.w	7,-1,-1,G_TEXT,0,0                                      ; 6 '01234567890123456789012345678901234567890123456789012345678901234'
	dc.l	ted_03
	dc.w	$0205,$0606,$0630,$0001
	dc.w	3,-1,-1,G_TEXT,0,0                                      ; 7 '5678901234567890123456'
	dc.l	ted_04
	dc.w	$0036,$0606,$0410,$0001
	dc.w	19,9,18,G_BOX,0,0                                       ; 8
	dc.l	$00ff1041
	dc.w	$0600,$030a,$004c,$0403
	dc.w	10,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0             ; 9 'Copy Disk'
	dc.l	main_09_text
	dc.w	$0001,$0300,$000e,$0001
	dc.w	11,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 10 'Scan Disk'
	dc.l	main_10_text
	dc.w	$0110,$0300,$000e,$0001
	dc.w	12,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 11 'Format Disk'
	dc.l	main_11_text
	dc.w	$011f,$0300,$000e,$0001
	dc.w	13,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 12 'Streamer'
	dc.l	main_12_text
	dc.w	$012e,$0300,$000e,$0001
	dc.w	14,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 13 'Directory'
	dc.l	main_13_text
	dc.w	$013d,$0300,$000e,$0001
	dc.w	15,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 14 'New Conf'
	dc.l	main_14_text
	dc.w	$0101,$0102,$000e,$0001
	dc.w	16,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 15 'Inspect Disk'
	dc.l	main_15_text
	dc.w	$0110,$0102,$000e,$0001
	dc.w	17,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 16 'Soft Format'
	dc.l	main_16_text
	dc.w	$011f,$0102,$000e,$0001
	dc.w	18,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 17 'Image Copy'
	dc.l	main_17_text
	dc.w	$012e,$0102,$000e,$0001
	dc.w	8,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 18 'Quit'
	dc.l	main_18_text
	dc.w	$013d,$0102,$000e,$0001
	dc.w	31,20,30,G_IBOX,0,0                                     ; 19
	dc.l	$00011100
	dc.w	$0641,$010e,$010b,$0009
	dc.w	21,-1,-1,G_STRING,0,0                                   ; 20 'Presets'
	dc.l	main_20_text
	dc.w	$0202,$0300,$0007,$0001
	dc.w	22,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 21 '>'
	dc.l	$3eff1100
	dc.w	$0301,$0002,$0001,$0001
	dc.w	23,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 22 '1234567'
	dc.l	ted_05
	dc.w	$0502,$0002,$0007,$0001
	dc.w	24,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 23 '>'
	dc.l	$3eff1100
	dc.w	$0301,$0303,$0001,$0001
	dc.w	25,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 24 '1234567'
	dc.l	ted_06
	dc.w	$0502,$0303,$0007,$0001
	dc.w	26,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 25 '>'
	dc.l	$3eff1100
	dc.w	$0301,$0604,$0001,$0001
	dc.w	27,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 26 '1234567'
	dc.l	ted_07
	dc.w	$0502,$0604,$0007,$0001
	dc.w	28,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 27 '>'
	dc.l	$3eff1100
	dc.w	$0301,$0106,$0001,$0001
	dc.w	29,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 28 '1234567'
	dc.l	ted_08
	dc.w	$0502,$0106,$0007,$0001
	dc.w	30,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 29 '>'
	dc.l	$3eff1100
	dc.w	$0301,$0407,$0001,$0001
	dc.w	19,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 30 '1234567'
	dc.l	ted_09
	dc.w	$0502,$0407,$0007,$0001
	dc.w	45,32,44,G_BOX,0,0                                      ; 31
	dc.l	$00ff1101
	dc.w	$0600,$020e,$0218,$0608
	dc.w	33,-1,-1,G_STRING,0,0                                   ; 32 'Verify Destination'
	dc.l	main_32_text
	dc.w	$0101,$0300,$0012,$0001
	dc.w	34,-1,-1,G_BOX,SELECTABLE,0                             ; 33
	dc.l	$00ff1100
	dc.w	$0714,$0300,$0002,$0001
	dc.w	35,-1,-1,G_STRING,0,0                                   ; 34 'Smart Formatting'
	dc.l	main_34_text
	dc.w	$0101,$0601,$0010,$0001
	dc.w	36,-1,-1,G_BOX,SELECTABLE,0                             ; 35
	dc.l	$00ff1100
	dc.w	$0714,$0601,$0002,$0001
	dc.w	37,-1,-1,G_STRING,0,0                                   ; 36 'Format Destination'
	dc.l	main_36_text
	dc.w	$0201,$0103,$0012,$0001
	dc.w	38,-1,-1,G_BOX,SELECTABLE,0                             ; 37
	dc.l	$00ff1100
	dc.w	$0714,$0103,$0002,$0001
	dc.w	39,-1,-1,G_BOX,SELECTABLE|EXIT,0                        ; 38
	dc.l	$00ff1100
	dc.w	$0714,$0404,$0002,$0001
	dc.w	40,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 39 'Read Disk Config.'
	dc.l	main_39_text
	dc.w	$0201,$0404,$0011,$0001
	dc.w	41,-1,-1,G_BOX,SELECTABLE,0                             ; 40
	dc.l	$00ff1100
	dc.w	$0714,$0705,$0002,$0001
	dc.w	42,-1,-1,G_STRING,0,0                                   ; 41 'Multiple Copy'
	dc.l	main_41_text
	dc.w	$0201,$0705,$000d,$0001
	dc.w	43,-1,-1,G_STRING,0,0                                   ; 42 'Get Sectors'
	dc.l	main_42_text
	dc.w	$0101,$0207,$000b,$0001
	dc.w	44,-1,-1,G_BUTTON,SELECTABLE|RBUTTON,0                  ; 43 'all'
	dc.l	main_43_text
	dc.w	$060d,$0207,$0004,$0001
	dc.w	31,-1,-1,G_BUTTON,SELECTABLE|RBUTTON,0                  ; 44 'used'
	dc.l	main_44_text
	dc.w	$0412,$0207,$0304,$0001
	dc.w	49,46,48,G_BOX,0,0                                      ; 45
	dc.l	$00ff1101
	dc.w	$0519,$020e,$0508,$0205
	dc.w	47,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 46 'Source'
	dc.l	main_46_text
	dc.w	$0201,$0300,$0006,$0001
	dc.w	48,-1,-1,G_BOXCHAR,SELECTABLE|EXIT|RBUTTON,0            ; 47 'A'
	dc.l	$41ff1100
	dc.w	$0601,$0102,$0005,$0001
	dc.w	45,-1,-1,G_BOXCHAR,SELECTABLE|EXIT|RBUTTON,0            ; 48 'B'
	dc.l	$42ff1100
	dc.w	$0601,$0603,$0005,$0001
	dc.w	53,50,52,G_BOX,0,0                                      ; 49
	dc.l	$00ff1101
	dc.w	$0222,$020e,$0508,$0205
	dc.w	51,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 50 'Dest.'
	dc.l	main_50_text
	dc.w	$0701,$0300,$0005,$0001
	dc.w	52,-1,-1,G_BOXCHAR,SELECTABLE|EXIT|RBUTTON,0            ; 51 'A'
	dc.l	$41ff1100
	dc.w	$0601,$0102,$0005,$0001
	dc.w	49,-1,-1,G_BOXCHAR,SELECTABLE|EXIT|RBUTTON,0            ; 52 'B'
	dc.l	$42ff1100
	dc.w	$0601,$0603,$0005,$0001
	dc.w	74,54,73,G_BOX,0,0                                      ; 53
	dc.l	$00ff1101
	dc.w	$032b,$020e,$0316,$0608
	dc.w	55,-1,-1,G_STRING,0,0                                   ; 54 'Disk Configuration'
	dc.l	main_54_text
	dc.w	$0202,$0200,$0012,$0001
	dc.w	56,-1,-1,G_STRING,0,0                                   ; 55 'Sides'
	dc.l	main_55_text
	dc.w	$0301,$0701,$0005,$0001
	dc.w	57,-1,-1,G_BOXCHAR,SELECTABLE|RBUTTON,0                 ; 56 '1'
	dc.l	$31ff1100
	dc.w	$020b,$0701,$0004,$0001
	dc.w	58,-1,-1,G_BOXCHAR,SELECTABLE|RBUTTON,0                 ; 57 '2'
	dc.l	$32ff1100
	dc.w	$0510,$0701,$0004,$0001
	dc.w	59,-1,-1,G_STRING,0,0                                   ; 58 'Sectors'
	dc.l	main_58_text
	dc.w	$0301,$0203,$0007,$0001
	dc.w	60,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 59 '-'
	dc.l	$2dff1100
	dc.w	$020b,$0203,$0003,$0001
	dc.w	61,-1,-1,G_FTEXT,EDITABLE,0                             ; 60 '09'
	dc.l	ted_10
	dc.w	$000f,$0203,$0002,$0001
	dc.w	62,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 61 '+'
	dc.l	$2bff1100
	dc.w	$0511,$0203,$0003,$0001
	dc.w	63,-1,-1,G_STRING,0,0                                   ; 62 'Start at'
	dc.l	main_62_text
	dc.w	$0301,$0504,$0008,$0001
	dc.w	64,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 63 '-'
	dc.l	$2dff1100
	dc.w	$020b,$0504,$0003,$0001
	dc.w	65,-1,-1,G_FTEXT,EDITABLE,0                             ; 64 '99'
	dc.l	ted_11
	dc.w	$000f,$0504,$0002,$0001
	dc.w	66,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 65 '+'
	dc.l	$2bff1100
	dc.w	$0511,$0504,$0003,$0001
	dc.w	67,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 66 '-'
	dc.l	$2dff1100
	dc.w	$020b,$0006,$0003,$0001
	dc.w	68,-1,-1,G_FTEXT,EDITABLE,0                             ; 67 '79'
	dc.l	ted_12
	dc.w	$000f,$0006,$0002,$0001
	dc.w	69,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 68 '+'
	dc.l	$2bff1101
	dc.w	$0511,$0006,$0003,$0001
	dc.w	70,-1,-1,G_STRING,0,0                                   ; 69 'End at'
	dc.l	main_69_text
	dc.w	$0401,$0006,$0006,$0001
	dc.w	73,71,72,G_IBOX,0,0                                     ; 70
	dc.l	$00001100
	dc.w	$010b,$0007,$040a,$0401
	dc.w	72,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 71 'DD'
	dc.l	ted_13
	dc.w	$0100,$0300,$0004,$0001
	dc.w	70,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 72 'HD'
	dc.l	ted_14
	dc.w	$0405,$0300,$0004,$0001
	dc.w	53,-1,-1,G_STRING,0,0                                   ; 73 'Density'
	dc.l	main_73_text
	dc.w	$0401,$0307,$0007,$0001
	dc.w	75,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 74 '>> More Options'
	dc.l	main_74_text
	dc.w	$0619,$0014,$0011,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 75 'Save Config.'
	dc.l	main_75_text
	dc.w	$0619,$0515,$0011,$0001

; tree 1: scrolling list box (drives, presets and file lists)
list_tree:
	dc.w	-1,1,20,G_BOX,0,0                                       ; 0
	dc.l	$00001100
	dc.w	$0000,$0000,$0748,$0507
	dc.w	2,-1,-1,G_BUTTON,0,0                                    ; 1 ''
	dc.l	str_empty
	dc.w	$0500,$0100,$033e,$0101
	dc.w	3,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 2 '\x07'
	dc.l	list_02_text
	dc.w	$0640,$0300,$0602,$0401
	dc.w	4,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 3 'X'
	dc.l	list_03_text
	dc.w	$0644,$0400,$0502,$0201
	dc.w	17,5,16,G_BOX,0,0                                       ; 4
	dc.l	$00001101
	dc.w	$0600,$0501,$003e,$0006
	dc.w	6,-1,-1,G_STRING,SELECTABLE|EXIT,0                      ; 5 ''
	dc.l	str_empty
	dc.w	$0000,$0000,$001d,$0001
	dc.w	7,-1,-1,G_STRING,SELECTABLE|EXIT,0                      ; 6 ''
	dc.l	str_empty
	dc.w	$0021,$0000,$001d,$0001
	dc.w	8,-1,-1,G_STRING,SELECTABLE|EXIT,0                      ; 7 ''
	dc.l	str_empty
	dc.w	$0000,$0001,$001d,$0001
	dc.w	9,-1,-1,G_STRING,SELECTABLE|EXIT,0                      ; 8 ''
	dc.l	str_empty
	dc.w	$0021,$0001,$001d,$0001
	dc.w	10,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 9 ''
	dc.l	str_empty
	dc.w	$0000,$0002,$001d,$0001
	dc.w	11,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 10 ''
	dc.l	str_empty
	dc.w	$0021,$0002,$001d,$0001
	dc.w	12,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 11 ''
	dc.l	str_empty
	dc.w	$0000,$0003,$001d,$0001
	dc.w	13,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 12 ''
	dc.l	str_empty
	dc.w	$0021,$0003,$001d,$0001
	dc.w	14,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 13 ''
	dc.l	str_empty
	dc.w	$0000,$0004,$001d,$0001
	dc.w	15,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 14 ''
	dc.l	str_empty
	dc.w	$0021,$0004,$001d,$0001
	dc.w	16,-1,-1,G_STRING,SELECTABLE|EXIT,0                     ; 15 ''
	dc.l	str_empty
	dc.w	$0000,$0005,$001d,$0001
	dc.w	4,-1,-1,G_STRING,SELECTABLE|EXIT,0                      ; 16 ''
	dc.l	str_empty
	dc.w	$0021,$0005,$001d,$0001
	dc.w	18,-1,-1,G_BUTTON,TOUCHEXIT,0                           ; 17 '\x01'
	dc.l	list_17_text
	dc.w	$0540,$0602,$0003,$0202
	dc.w	20,19,19,G_BOX,TOUCHEXIT,0                              ; 18
	dc.l	$00ff1141
	dc.w	$0444,$0602,$0103,$0504
	dc.w	18,-1,-1,G_BOX,TOUCHEXIT,0                              ; 19
	dc.l	$00ff1101
	dc.w	$0000,$0001,$0103,$0002
	dc.w	0,-1,-1,G_BUTTON,LASTOB|TOUCHEXIT,0                     ; 20 '\x02'
	dc.l	list_20_text
	dc.w	$0540,$0105,$0003,$0202

; tree 2: destination disk format dialog
format_tree:
	dc.w	-1,1,22,G_BOX,0,OUTLINED                                ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0626,$0512
	dc.w	2,-1,-1,G_STRING,0,0                                    ; 1 'X: Destination Disk'
	dc.l	format_01_text
	dc.w	$0509,$0600,$0013,$0001
	dc.w	3,-1,-1,G_FTEXT,EDITABLE,OUTLINED                       ; 2 'Disk Name: ___________'
	dc.l	ted_15
	dc.w	$0108,$0702,$0016,$0001
	dc.w	4,-1,-1,G_STRING,0,0                                    ; 3 ''
	dc.l	str_empty
	dc.w	$0007,$0704,$0217,$0001
	dc.w	6,5,5,G_BOX,0,0                                         ; 4
	dc.l	$00000080
	dc.w	$0007,$0006,$001a,$0001
	dc.w	4,-1,-1,G_STRING,0,0                                    ; 5 ''
	dc.l	str_empty
	dc.w	$0000,$0000,$0003,$0001
	dc.w	20,7,19,G_BOX,0,0                                       ; 6
	dc.l	$00ff1101
	dc.w	$0401,$0507,$0523,$0707
	dc.w	8,-1,-1,G_STRING,0,0                                    ; 7 'Directory Entries:'
	dc.l	format_07_text
	dc.w	$0102,$0600,$0012,$0001
	dc.w	9,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                     ; 8 char 2
	dc.l	$02ff1100
	dc.w	$0317,$0500,$0003,$0001
	dc.w	10,-1,-1,G_TEXT,0,0                                     ; 9 ''
	dc.l	ted_16
	dc.w	$071a,$0600,$0003,$0001
	dc.w	11,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 10 char 1
	dc.l	$01ff1100
	dc.w	$041e,$0500,$0003,$0001
	dc.w	12,-1,-1,G_TEXT,0,0                                     ; 11 ''
	dc.l	ted_17
	dc.w	$071b,$0202,$0001,$0001
	dc.w	13,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 12 char 2
	dc.l	$02ff1100
	dc.w	$0317,$0202,$0003,$0001
	dc.w	14,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 13 char 1
	dc.l	$01ff1100
	dc.w	$041e,$0202,$0003,$0001
	dc.w	15,-1,-1,G_STRING,0,0                                   ; 14 'Sectors per Cluster:'
	dc.l	format_14_text
	dc.w	$0002,$0202,$0014,$0001
	dc.w	16,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 15 'MS DOS'
	dc.l	ted_18
	dc.w	$0102,$0304,$0009,$0001
	dc.w	17,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 16 'TOS'
	dc.l	ted_19
	dc.w	$070c,$0304,$0009,$0001
	dc.w	18,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 17 'Optimized'
	dc.l	ted_20
	dc.w	$0417,$0304,$000a,$0001
	dc.w	19,-1,-1,G_BOX,SELECTABLE|EXIT,0                        ; 18
	dc.l	$00011100
	dc.w	$0102,$0206,$0002,$0001
	dc.w	6,-1,-1,G_STRING,0,0                                    ; 19 'Put Guardian on Boot-Sector'
	dc.l	format_19_text
	dc.w	$0305,$0206,$001b,$0001
	dc.w	21,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0             ; 20 'OK'
	dc.l	str_ok
	dc.w	$0701,$0510,$0009,$0001
	dc.w	22,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 21 'DATA DISK'
	dc.l	format_21_text
	dc.w	$010e,$0510,$000a,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 22 'CANCEL'
	dc.l	str_cancel
	dc.w	$001b,$0510,$000a,$0001

; tree 3: disk error box: RETRY, CONTINUE, BEST MATCH, NEW DISK, ABORT
error_tree:
	dc.w	-1,1,6,G_BOX,0,0                                        ; 0
	dc.l	$00021172
	dc.w	$0000,$0000,$0043,$0005
	dc.w	2,-1,-1,G_BOXTEXT,0,0                                   ; 1 ''
	dc.l	ted_21
	dc.w	$010d,$0700,$022a,$0001
	dc.w	3,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 2 'RETRY'
	dc.l	error_02_text
	dc.w	$0002,$0003,$000b,$0001
	dc.w	4,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 3 'CONTINUE'
	dc.l	error_03_text
	dc.w	$000f,$0003,$000b,$0001
	dc.w	5,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 4 'BEST MATCH'
	dc.l	error_04_text
	dc.w	$001c,$0003,$000b,$0001
	dc.w	6,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 5 'NEW DISK'
	dc.l	error_05_text
	dc.w	$0029,$0003,$000b,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 6 'ABORT'
	dc.l	str_abort
	dc.w	$0036,$0003,$000b,$0001

; tree 4: drive selection box with drive letter arrows
drive_tree:
	dc.w	-1,1,7,G_BOX,0,OUTLINED                                 ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0020,$0008
	dc.w	2,-1,-1,G_BOXTEXT,0,0                                   ; 1 ''
	dc.l	ted_22
	dc.w	$0002,$0001,$001c,$0001
	dc.w	3,-1,-1,G_BOXCHAR,TOUCHEXIT,0                           ; 2 char 4
	dc.l	$04ff1100
	dc.w	$000b,$0003,$0002,$0001
	dc.w	4,-1,-1,G_TEXT,0,0                                      ; 3 'X:'
	dc.l	ted_23
	dc.w	$000f,$0003,$0002,$0001
	dc.w	5,-1,-1,G_BOXCHAR,TOUCHEXIT,0                           ; 4 char 3
	dc.l	$03ff1100
	dc.w	$0013,$0003,$0002,$0001
	dc.w	6,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 5 'OK'
	dc.l	str_ok
	dc.w	$0501,$0605,$0008,$0001
	dc.w	7,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 6 'DIRECTORY'
	dc.l	drive_06_text
	dc.w	$000b,$0605,$000a,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 7 'ABORT'
	dc.l	str_abort
	dc.w	$0316,$0605,$0008,$0001

; tree 5: more options: data storage, formatting, user interface, drives A and B
options_tree:
	dc.w	-1,1,80,G_BOX,0,OUTLINED                                ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$054c,$0316
	dc.w	11,2,8,G_IBOX,0,0                                       ; 1
	dc.l	$00011100
	dc.w	$0701,$0001,$0327,$0707
	dc.w	3,-1,-1,G_BOX,SELECTABLE,0                              ; 2
	dc.l	$00011100
	dc.w	$0601,$0301,$0002,$0001
	dc.w	4,-1,-1,G_STRING,0,0                                    ; 3 'Compack Streamer Data'
	dc.l	options_03_text
	dc.w	$0404,$0301,$0015,$0001
	dc.w	5,-1,-1,G_BOX,SELECTABLE,0                              ; 4
	dc.l	$00011100
	dc.w	$0601,$0003,$0002,$0001
	dc.w	6,-1,-1,G_STRING,0,0                                    ; 5 'Optimize Partition when writing'
	dc.l	options_05_text
	dc.w	$0404,$0003,$001f,$0001
	dc.w	7,-1,-1,G_BOX,SELECTABLE|EXIT,0                         ; 6
	dc.l	$00011100
	dc.w	$0601,$0604,$0002,$0001
	dc.w	8,-1,-1,G_STRING,0,0                                    ; 7 'Use Harddisk as Extended Memory'
	dc.l	options_07_text
	dc.w	$0404,$0604,$001f,$0001
	dc.w	1,9,10,G_BOX,0,0                                        ; 8
	dc.l	$00000080
	dc.w	$0204,$0006,$0222,$0501
	dc.w	10,-1,-1,G_STRING,0,0                                   ; 9 'Current Partition is A:'
	dc.l	options_09_text
	dc.w	$0100,$0200,$0017,$0001
	dc.w	8,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 10 'Select'
	dc.l	options_10_text
	dc.w	$0718,$0200,$0108,$0001
	dc.w	16,12,15,G_IBOX,0,0                                     ; 11
	dc.l	$00011100
	dc.w	$0601,$0609,$0518,$0604
	dc.w	13,-1,-1,G_BOX,SELECTABLE,0                             ; 12
	dc.l	$00011100
	dc.w	$0501,$0301,$0002,$0001
	dc.w	14,-1,-1,G_STRING,0,0                                   ; 13 'Fast Format'
	dc.l	options_13_text
	dc.w	$0304,$0301,$000b,$0001
	dc.w	15,-1,-1,G_BOX,SELECTABLE,0                             ; 14
	dc.l	$00011100
	dc.w	$0501,$0003,$0002,$0001
	dc.w	11,-1,-1,G_STRING,0,0                                   ; 15 'Fast Access headers'
	dc.l	options_15_text
	dc.w	$0304,$0003,$0013,$0001
	dc.w	23,17,22,G_IBOX,0,0                                     ; 16
	dc.l	$00011100
	dc.w	$0601,$040f,$0717,$0106
	dc.w	18,-1,-1,G_BOX,SELECTABLE,0                             ; 17
	dc.l	$00011100
	dc.w	$0501,$0201,$0002,$0001
	dc.w	19,-1,-1,G_STRING,0,0                                   ; 18 'Show Request Boxes'
	dc.l	options_18_text
	dc.w	$0404,$0201,$0012,$0001
	dc.w	20,-1,-1,G_BOX,SELECTABLE|EXIT,0                        ; 19
	dc.l	$00011100
	dc.w	$0501,$0602,$0002,$0001
	dc.w	21,-1,-1,G_STRING,0,0                                   ; 20 'Use Sound'
	dc.l	options_20_text
	dc.w	$0504,$0602,$0009,$0001
	dc.w	22,-1,-1,G_BOX,SELECTABLE|EXIT,0                        ; 21
	dc.l	$00011100
	dc.w	$0501,$0204,$0002,$0001
	dc.w	16,-1,-1,G_STRING,0,0                                   ; 22 'Mouse Accelerator'
	dc.l	options_22_text
	dc.w	$0604,$0204,$0011,$0001
	dc.w	24,-1,-1,G_TEXT,0,0                                     ; 23 'Data Storage'
	dc.l	ted_24
	dc.w	$0303,$0500,$000c,$0001
	dc.w	25,-1,-1,G_TEXT,0,0                                     ; 24 'Formatting'
	dc.l	ted_25
	dc.w	$0403,$0309,$000a,$0001
	dc.w	26,-1,-1,G_TEXT,0,0                                     ; 25 'User Interface'
	dc.l	ted_26
	dc.w	$0103,$010f,$000e,$0001
	dc.w	29,27,28,G_IBOX,0,0                                     ; 26
	dc.l	$00011100
	dc.w	$031c,$0609,$070d,$0604
	dc.w	28,-1,-1,G_FTEXT,EDITABLE,0                             ; 27 '9999'
	dc.l	ted_27
	dc.w	$0102,$0003,$000a,$0001
	dc.w	26,-1,-1,G_STRING,0,0                                   ; 28 'Reserve'
	dc.l	options_28_text
	dc.w	$0203,$0201,$0007,$0001
	dc.w	34,30,33,G_IBOX,0,0                                     ; 29
	dc.l	$00011100
	dc.w	$071b,$040f,$0212,$0403
	dc.w	31,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 30 '-'
	dc.l	$2dff1100
	dc.w	$0701,$0601,$0002,$0001
	dc.w	32,-1,-1,G_FTEXT,EDITABLE,0                             ; 31 '99'
	dc.l	ted_28
	dc.w	$0404,$0601,$0002,$0001
	dc.w	33,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 32 '+'
	dc.l	$2bff1100
	dc.w	$0207,$0601,$0002,$0001
	dc.w	29,-1,-1,G_STRING,0,0                                   ; 33 'Retries'
	dc.l	options_33_text
	dc.w	$000a,$0601,$0007,$0001
	dc.w	35,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0             ; 34 'OK'
	dc.l	str_ok
	dc.w	$031c,$0214,$0008,$0001
	dc.w	36,-1,-1,G_TEXT,0,0                                     ; 35 'Error'
	dc.l	ted_29
	dc.w	$051d,$010f,$0005,$0001
	dc.w	37,-1,-1,G_TEXT,0,0                                     ; 36 'Accessory'
	dc.l	ted_30
	dc.w	$061d,$0309,$0009,$0001
	dc.w	38,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 37 'CANCEL'
	dc.l	str_cancel
	dc.w	$0026,$0214,$0008,$0001
	dc.w	54,39,53,G_IBOX,0,0                                     ; 38
	dc.l	$00011100
	dc.w	$022c,$0001,$021e,$0206
	dc.w	42,40,41,G_IBOX,0,0                                     ; 39
	dc.l	$00001100
	dc.w	$040b,$0700,$050b,$0401
	dc.w	41,-1,-1,G_BOXCHAR,SELECTABLE|RBUTTON,0                 ; 40 '1'
	dc.l	$31ff1100
	dc.w	$0200,$0200,$0005,$0001
	dc.w	39,-1,-1,G_BOXCHAR,SELECTABLE|RBUTTON,0                 ; 41 '2'
	dc.l	$32ff1100
	dc.w	$0006,$0200,$0005,$0001
	dc.w	43,-1,-1,G_STRING,0,0                                   ; 42 'Sides'
	dc.l	options_42_text
	dc.w	$0701,$0101,$0005,$0001
	dc.w	44,-1,-1,G_STRING,0,0                                   ; 43 'Density'
	dc.l	options_43_text
	dc.w	$0601,$0702,$0007,$0001
	dc.w	45,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 44 'DD'
	dc.l	ted_31
	dc.w	$060b,$0702,$0005,$0001
	dc.w	46,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 45 'HD 5¬'
	dc.l	ted_32
	dc.w	$0511,$0702,$0005,$0001
	dc.w	47,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 46 'HD 3«'
	dc.l	ted_33
	dc.w	$0317,$0702,$0005,$0001
	dc.w	53,48,52,G_BOX,0,0                                      ; 47
	dc.l	$00001101
	dc.w	$050b,$0204,$060d,$0601
	dc.w	49,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 48 '2'
	dc.l	ted_34
	dc.w	$0100,$0300,$0002,$0001
	dc.w	50,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 49 '3'
	dc.l	ted_35
	dc.w	$0702,$0300,$0002,$0001
	dc.w	51,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 50 '6'
	dc.l	ted_36
	dc.w	$0505,$0300,$0002,$0001
	dc.w	52,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 51 '12'
	dc.l	ted_37
	dc.w	$0308,$0300,$0002,$0001
	dc.w	47,-1,-1,G_STRING,0,0                                   ; 52 'ms'
	dc.l	options_52_text
	dc.w	$010b,$0300,$0002,$0001
	dc.w	38,-1,-1,G_STRING,0,0                                   ; 53 'Steprate'
	dc.l	options_53_text
	dc.w	$0601,$0504,$0008,$0001
	dc.w	70,55,69,G_IBOX,0,0                                     ; 54
	dc.l	$00011100
	dc.w	$022c,$0208,$021e,$0206
	dc.w	58,56,57,G_IBOX,0,0                                     ; 55
	dc.l	$00001100
	dc.w	$040b,$0700,$050b,$0401
	dc.w	57,-1,-1,G_BOXCHAR,SELECTABLE|RBUTTON,0                 ; 56 '1'
	dc.l	$31ff1100
	dc.w	$0200,$0200,$0005,$0001
	dc.w	55,-1,-1,G_BOXCHAR,SELECTABLE|RBUTTON,0                 ; 57 '2'
	dc.l	$32ff1100
	dc.w	$0006,$0200,$0005,$0001
	dc.w	59,-1,-1,G_STRING,0,0                                   ; 58 'Sides'
	dc.l	options_58_text
	dc.w	$0601,$0101,$0005,$0001
	dc.w	60,-1,-1,G_STRING,0,0                                   ; 59 'Density'
	dc.l	options_59_text
	dc.w	$0601,$0702,$0007,$0001
	dc.w	61,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 60 'DD'
	dc.l	ted_38
	dc.w	$060b,$0702,$0005,$0001
	dc.w	62,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 61 'HD 5¬'
	dc.l	ted_39
	dc.w	$0511,$0702,$0005,$0001
	dc.w	63,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 62 'HD 3«'
	dc.l	ted_40
	dc.w	$0317,$0702,$0005,$0001
	dc.w	69,64,68,G_BOX,0,0                                      ; 63
	dc.l	$00001101
	dc.w	$050b,$0204,$070d,$0501
	dc.w	65,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 64 '2'
	dc.l	ted_41
	dc.w	$0100,$0300,$0002,$0001
	dc.w	66,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 65 '3'
	dc.l	ted_42
	dc.w	$0702,$0300,$0002,$0001
	dc.w	67,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 66 '6'
	dc.l	ted_43
	dc.w	$0505,$0300,$0002,$0001
	dc.w	68,-1,-1,G_BOXTEXT,SELECTABLE|EXIT|RBUTTON,0            ; 67 '12'
	dc.l	ted_44
	dc.w	$0308,$0300,$0002,$0001
	dc.w	63,-1,-1,G_STRING,0,0                                   ; 68 'ms'
	dc.l	options_68_text
	dc.w	$010b,$0300,$0002,$0001
	dc.w	54,-1,-1,G_STRING,0,0                                   ; 69 'Steprate'
	dc.l	options_69_text
	dc.w	$0601,$0504,$0008,$0001
	dc.w	71,-1,-1,G_TEXT,0,0                                     ; 70 'Drive A'
	dc.l	ted_45
	dc.w	$032e,$0500,$0007,$0001
	dc.w	72,-1,-1,G_TEXT,0,0                                     ; 71 'Drive B'
	dc.l	ted_46
	dc.w	$032e,$0707,$0007,$0001
	dc.w	80,73,79,G_IBOX,0,0                                     ; 72
	dc.l	$00011100
	dc.w	$0330,$040f,$001a,$0106
	dc.w	74,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 73 'Automatic/Switch'
	dc.l	ted_47
	dc.w	$0701,$0301,$0016,$0001
	dc.w	75,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 74 'Low'
	dc.l	ted_48
	dc.w	$060c,$0702,$0005,$0001
	dc.w	76,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 75 'High'
	dc.l	ted_49
	dc.w	$0712,$0702,$0005,$0001
	dc.w	77,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 76 'Low'
	dc.l	ted_50
	dc.w	$060c,$0304,$0005,$0001
	dc.w	78,-1,-1,G_BOXTEXT,SELECTABLE|RBUTTON,0                 ; 77 'High'
	dc.l	ted_51
	dc.w	$0712,$0304,$0005,$0001
	dc.w	79,-1,-1,G_STRING,0,0                                   ; 78 'PSG Bit 6'
	dc.l	options_78_text
	dc.w	$0701,$0702,$0009,$0001
	dc.w	72,-1,-1,G_STRING,0,0                                   ; 79 'PSG Bit 7'
	dc.l	options_79_text
	dc.w	$0701,$0304,$0009,$0001
	dc.w	0,-1,-1,G_TEXT,LASTOB,0                                 ; 80 'High Density Detect'
	dc.l	ted_52
	dc.w	$0432,$010f,$0013,$0001

; tree 6: about box
about_tree:
	dc.w	-1,1,8,G_BOX,0,OUTLINED                                 ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0021,$0012
	dc.w	2,-1,-1,G_STRING,0,0                                    ; 1 'FastCopy PRO'
	dc.l	about_01_text
	dc.w	$010b,$0001,$000c,$0001
	dc.w	3,-1,-1,G_IMAGE,0,0                                     ; 2
	dc.l	logo_bitblk
	dc.w	$070d,$0302,$3000,$1c00
	dc.w	4,-1,-1,G_STRING,0,0                                    ; 3 'Version 1.2'
	dc.l	about_03_text
	dc.w	$010b,$0506,$0013,$0001
	dc.w	5,-1,-1,G_STRING,0,0                                    ; 4 'Concept, Design & Development'
	dc.l	about_04_text
	dc.w	$0002,$0009,$001d,$0001
	dc.w	6,-1,-1,G_STRING,0,0                                    ; 5 'Martin Backschat'
	dc.l	about_05_text
	dc.w	$0009,$000a,$0010,$0001
	dc.w	7,-1,-1,G_STRING,0,0                                    ; 6 '½ Copyright 1994 by'
	dc.l	about_06_text
	dc.w	$0007,$000c,$0013,$0001
	dc.w	8,-1,-1,G_STRING,0,0                                    ; 7 '    Martin Backschat'
	dc.l	about_07_text
	dc.w	$0205,$000d,$0017,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT|LASTOB,0       ; 8 'OK'
	dc.l	str_ok
	dc.w	$000d,$050f,$0008,$0001

; tree 7: disk inspector (sector editor)
inspect_tree:
	dc.w	-1,1,52,G_BOX,0,0                                       ; 0
	dc.l	$00011070
	dc.w	$0000,$0000,$044d,$0217
	dc.w	18,2,17,G_BOX,0,0                                       ; 1
	dc.l	$00ff1101
	dc.w	$0401,$0200,$0447,$0310
	dc.w	3,-1,-1,G_STRING,TOUCHEXIT,0                            ; 2 ''
	dc.l	str_empty
	dc.w	$0200,$0000,$0047,$0001
	dc.w	4,-1,-1,G_STRING,TOUCHEXIT,0                            ; 3 ''
	dc.l	str_empty
	dc.w	$0200,$0001,$0047,$0001
	dc.w	5,-1,-1,G_STRING,TOUCHEXIT,0                            ; 4 ''
	dc.l	str_empty
	dc.w	$0200,$0002,$0047,$0001
	dc.w	6,-1,-1,G_STRING,TOUCHEXIT,0                            ; 5 ''
	dc.l	str_empty
	dc.w	$0200,$0003,$0047,$0001
	dc.w	7,-1,-1,G_STRING,TOUCHEXIT,0                            ; 6 ''
	dc.l	str_empty
	dc.w	$0200,$0004,$0047,$0001
	dc.w	8,-1,-1,G_STRING,TOUCHEXIT,0                            ; 7 ''
	dc.l	str_empty
	dc.w	$0200,$0005,$0047,$0001
	dc.w	9,-1,-1,G_STRING,TOUCHEXIT,0                            ; 8 ''
	dc.l	str_empty
	dc.w	$0200,$0006,$0047,$0001
	dc.w	10,-1,-1,G_STRING,TOUCHEXIT,0                           ; 9 ''
	dc.l	str_empty
	dc.w	$0200,$0007,$0047,$0001
	dc.w	11,-1,-1,G_STRING,TOUCHEXIT,0                           ; 10 ''
	dc.l	str_empty
	dc.w	$0200,$0008,$0047,$0001
	dc.w	12,-1,-1,G_STRING,TOUCHEXIT,0                           ; 11 ''
	dc.l	str_empty
	dc.w	$0200,$0009,$0047,$0001
	dc.w	13,-1,-1,G_STRING,TOUCHEXIT,0                           ; 12 ''
	dc.l	str_empty
	dc.w	$0200,$000a,$0047,$0001
	dc.w	14,-1,-1,G_STRING,TOUCHEXIT,0                           ; 13 ''
	dc.l	str_empty
	dc.w	$0200,$000b,$0047,$0001
	dc.w	15,-1,-1,G_STRING,TOUCHEXIT,0                           ; 14 ''
	dc.l	str_empty
	dc.w	$0200,$000c,$0047,$0001
	dc.w	16,-1,-1,G_STRING,TOUCHEXIT,0                           ; 15 ''
	dc.l	str_empty
	dc.w	$0200,$000d,$0047,$0001
	dc.w	17,-1,-1,G_STRING,TOUCHEXIT,0                           ; 16 ''
	dc.l	str_empty
	dc.w	$0200,$000e,$0047,$0001
	dc.w	1,-1,-1,G_STRING,TOUCHEXIT,0                            ; 17 ''
	dc.l	str_empty
	dc.w	$0200,$000f,$0047,$0001
	dc.w	19,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 18 'D'
	dc.l	inspect_18_text
	dc.w	$0249,$0200,$0601,$0201
	dc.w	20,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 19 '\x07'
	dc.l	inspect_19_text
	dc.w	$0249,$0601,$0601,$0201
	dc.w	21,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 20 char 1
	dc.l	$01ff1100
	dc.w	$0149,$0203,$0002,$0501
	dc.w	23,22,22,G_BOX,TOUCHEXIT,0                              ; 21
	dc.l	$00ff1121
	dc.w	$0149,$0005,$0002,$0709
	dc.w	21,-1,-1,G_BOX,TOUCHEXIT,0                              ; 22
	dc.l	$00ff1101
	dc.w	$0000,$0202,$0002,$0404
	dc.w	24,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 23 char 2
	dc.l	$02ff1100
	dc.w	$0149,$000f,$0002,$0501
	dc.w	25,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 24 char 4
	dc.l	$04ff1100
	dc.w	$0401,$0610,$0003,$0001
	dc.w	27,26,26,G_BOX,TOUCHEXIT,0                              ; 25
	dc.l	$00ff1121
	dc.w	$0504,$0610,$0241,$0001
	dc.w	25,-1,-1,G_FTEXT,EDITABLE|TOUCHEXIT,0                   ; 26 '99999'
	dc.l	ted_53
	dc.w	$0013,$0000,$0005,$0001
	dc.w	28,-1,-1,G_BOXCHAR,TOUCHEXIT,0                          ; 27 char 3
	dc.l	$03ff1100
	dc.w	$0046,$0610,$0003,$0001
	dc.w	47,29,46,G_IBOX,0,OUTLINED                              ; 28
	dc.l	$00001100
	dc.w	$0601,$0112,$0746,$0502
	dc.w	31,30,30,G_BOX,0,0                                      ; 29
	dc.l	$00010080
	dc.w	$0001,$0000,$0621,$0001
	dc.w	29,-1,-1,G_STRING,0,0                                   ; 30 ''
	dc.l	str_empty
	dc.w	$0000,$0000,$0020,$0001
	dc.w	33,32,32,G_BOX,0,0                                      ; 31
	dc.l	$00010080
	dc.w	$0423,$0000,$000e,$0001
	dc.w	31,-1,-1,G_STRING,0,0                                   ; 32 ''
	dc.l	str_empty
	dc.w	$0000,$0000,$000c,$0001
	dc.w	35,34,34,G_BOX,0,0                                      ; 33
	dc.l	$00001080
	dc.w	$0532,$0000,$0113,$0101
	dc.w	33,-1,-1,G_STRING,0,0                                   ; 34 ''
	dc.l	str_empty
	dc.w	$0200,$0000,$0012,$0001
	dc.w	36,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 35 'B'
	dc.l	$42ff1100
	dc.w	$0201,$0401,$0002,$0001
	dc.w	37,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 36 'F1'
	dc.l	ted_54
	dc.w	$0104,$0401,$0002,$0001
	dc.w	38,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 37 'F2'
	dc.l	ted_55
	dc.w	$0007,$0401,$0002,$0001
	dc.w	39,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 38 'R'
	dc.l	$52ff1100
	dc.w	$0709,$0401,$0002,$0001
	dc.w	40,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 39 'D'
	dc.l	$44ff1100
	dc.w	$060c,$0401,$0002,$0001
	dc.w	41,-1,-1,G_BOXCHAR,SELECTABLE|EXIT,0                    ; 40 'E'
	dc.l	$45ff1100
	dc.w	$050f,$0401,$0002,$0001
	dc.w	42,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 41 'C->S'
	dc.l	ted_56
	dc.w	$0614,$0401,$0004,$0001
	dc.w	43,-1,-1,G_BOXTEXT,SELECTABLE|EXIT,0                    ; 42 'I->M'
	dc.l	ted_57
	dc.w	$001a,$0401,$0004,$0001
	dc.w	44,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 43 'Change'
	dc.l	inspect_43_text
	dc.w	$0521,$0401,$0008,$0001
	dc.w	45,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 44 'Search'
	dc.l	inspect_44_text
	dc.w	$062b,$0401,$0008,$0001
	dc.w	46,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 45 'Next'
	dc.l	inspect_45_text
	dc.w	$0035,$0401,$0005,$0001
	dc.w	28,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 46 'Write'
	dc.l	inspect_46_text
	dc.w	$023c,$0401,$0009,$0001
	dc.w	48,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 47 'Main Menu'
	dc.l	inspect_47_text
	dc.w	$0103,$0515,$000b,$0001
	dc.w	49,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 48 'Save'
	dc.l	inspect_48_text
	dc.w	$0110,$0515,$0008,$0001
	dc.w	50,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 49 'Load'
	dc.l	inspect_49_text
	dc.w	$001a,$0515,$0008,$0001
	dc.w	51,-1,-1,G_STRING,0,0                                   ; 50 'Boot-Sector:'
	dc.l	inspect_50_text
	dc.w	$0524,$0515,$000c,$0001
	dc.w	52,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                     ; 51 'Analyse'
	dc.l	inspect_51_text
	dc.w	$0631,$0515,$000a,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 52 'Protect'
	dc.l	inspect_52_text
	dc.w	$003d,$0515,$000a,$0001

; tree 8: enter values for a sector change
values_tree:
	dc.w	-1,1,4,G_BOX,0,0                                        ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$004b,$0005
	dc.w	2,-1,-1,G_STRING,0,0                                    ; 1 'Enter Values (e.g. 13,-34,$a6,"FCopy",12,0,,4) :'
	dc.l	values_01_text
	dc.w	$0002,$0001,$0030,$0001
	dc.w	3,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 2 'OK'
	dc.l	str_ok
	dc.w	$0036,$0001,$0008,$0001
	dc.w	4,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 3 'CANCEL'
	dc.l	str_cancel
	dc.w	$0040,$0001,$0008,$0001
	dc.w	0,-1,-1,G_FTEXT,EDITABLE|LASTOB,0                       ; 4 '_________________________________________________________________'
	dc.l	ted_58
	dc.w	$0004,$0003,$0041,$0001

; tree 9: search a pattern in a sector range
search_tree:
	dc.w	-1,1,9,G_BOX,0,0                                        ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$043f,$060a
	dc.w	2,-1,-1,G_FTEXT,EDITABLE,0                              ; 1 'Search from Sector _____'
	dc.l	ted_59
	dc.w	$0006,$0001,$0018,$0001
	dc.w	3,-1,-1,G_FTEXT,EDITABLE,0                              ; 2 'to Sector _____'
	dc.l	ted_60
	dc.w	$001f,$0001,$000f,$0001
	dc.w	4,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 3 'OK'
	dc.l	str_ok
	dc.w	$0035,$0001,$0008,$0001
	dc.w	5,-1,-1,G_BOX,SELECTABLE,0                              ; 4
	dc.l	$00011100
	dc.w	$0006,$0003,$0002,$0001
	dc.w	6,-1,-1,G_STRING,0,0                                    ; 5 'Ignore Case'
	dc.l	search_05_text
	dc.w	$0009,$0003,$000b,$0001
	dc.w	7,-1,-1,G_BUTTON,SELECTABLE|EXIT,0                      ; 6 'CANCEL'
	dc.l	str_cancel
	dc.w	$0035,$0003,$0008,$0001
	dc.w	8,-1,-1,G_STRING,0,0                                    ; 7 ''
	dc.l	str_empty
	dc.w	$0701,$0704,$000b,$0001
	dc.w	9,-1,-1,G_FTEXT,EDITABLE,0                              ; 8 '____________________________________________________________'
	dc.l	ted_61
	dc.w	$0601,$0206,$003c,$0001
	dc.w	0,10,11,G_BOX,0,0                                       ; 9
	dc.l	$00ff1101
	dc.w	$0211,$0308,$001d,$0001
	dc.w	11,-1,-1,G_STRING,0,0                                   ; 10 'Searching in Sector'
	dc.l	search_10_text
	dc.w	$0002,$0000,$0013,$0001
	dc.w	9,12,12,G_BOX,0,0                                       ; 11
	dc.l	$00010080
	dc.w	$0016,$0000,$0006,$0001
	dc.w	11,-1,-1,G_STRING,LASTOB,0                              ; 12 '99999'
	dc.l	search_12_text
	dc.w	$0000,$0000,$0005,$0001

; tree 10: message box with GOTO
goto_tree:
	dc.w	-1,1,3,G_BOX,0,0                                        ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0020,$0005
	dc.w	2,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 1 'OK'
	dc.l	str_ok
	dc.w	$0006,$0003,$0008,$0001
	dc.w	3,-1,-1,G_STRING,0,0                                    ; 2 ''
	dc.l	str_empty
	dc.w	$0002,$0001,$001c,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 3 'GOTO'
	dc.l	goto_03_text
	dc.w	$0012,$0003,$0008,$0001

; tree 11: enter the name of a preset
preset_tree:
	dc.w	-1,1,3,G_BOX,0,0                                        ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0039,$0003
	dc.w	2,-1,-1,G_FTEXT,EDITABLE,0                              ; 1 '_______'
	dc.l	ted_62
	dc.w	$0002,$0001,$001d,$0001
	dc.w	3,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 2 'OK'
	dc.l	str_ok
	dc.w	$0024,$0001,$0008,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 3 'CANCEL'
	dc.l	str_cancel
	dc.w	$002e,$0001,$0008,$0001

; tree 12: save a sector range to a file
save_tree:
	dc.w	-1,1,4,G_BOX,0,0                                        ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0044,$0003
	dc.w	2,-1,-1,G_FTEXT,EDITABLE,0                              ; 1 'Save from Sector _____'
	dc.l	ted_63
	dc.w	$0002,$0001,$0016,$0001
	dc.w	3,-1,-1,G_FTEXT,EDITABLE,0                              ; 2 'to Sector _____'
	dc.l	ted_64
	dc.w	$0019,$0001,$000f,$0001
	dc.w	4,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 3 'OK'
	dc.l	str_ok
	dc.w	$002f,$0001,$0008,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 4 'CANCEL'
	dc.l	str_cancel
	dc.w	$0039,$0001,$0008,$0001

; tree 13: load a file to a sector
load_tree:
	dc.w	-1,1,3,G_BOX,0,0                                        ; 0
	dc.l	$00021100
	dc.w	$0000,$0000,$0031,$0003
	dc.w	2,-1,-1,G_FTEXT,EDITABLE,0                              ; 1 'Load to Sector _____'
	dc.l	ted_65
	dc.w	$0202,$0001,$0014,$0001
	dc.w	3,-1,-1,G_BUTTON,SELECTABLE|DEFAULT|EXIT,0              ; 2 'OK'
	dc.l	str_ok
	dc.w	$011c,$0001,$0008,$0001
	dc.w	0,-1,-1,G_BUTTON,SELECTABLE|EXIT|LASTOB,0               ; 3 'CANCEL'
	dc.l	str_cancel
	dc.w	$0426,$0001,$0008,$0001
ted_01_text:
	dc.b	'000000000011111111112222222222333333333344444444445555555555'
	dc.b	'66666',0
ted_02_text:
	dc.b	'6666677777777778888888',0
ted_03_text:
	dc.b	'012345678901234567890123456789012345678901234567890123456789'
	dc.b	'01234',0
ted_04_text:
	dc.b	'5678901234567890123456',0
ted_05_text:
	dc.b	'1234567',0
ted_06_text:
	dc.b	'1234567',0
ted_07_text:
	dc.b	'1234567',0
ted_08_text:
	dc.b	'1234567',0
ted_09_text:
	dc.b	'1234567',0
ted_10_text:
	dc.b	'09',0
ted_10_tmplt:
	dc.b	'__',0
ted_10_valid:
	dc.b	'9',0
ted_11_text:
	dc.b	'99',0
ted_11_tmplt:
	dc.b	'__',0
ted_11_valid:
	dc.b	'9',0
ted_12_text:
	dc.b	'79',0
ted_12_tmplt:
	dc.b	'__',0
ted_12_valid:
	dc.b	'9',0
ted_13_text:
	dc.b	'DD',0
ted_14_text:
	dc.b	'HD',0
ted_15_text:
	dc.b	0
	dc.b	' 12345678901',0
ted_15_tmplt:
	dc.b	'Disk Name: ___________',0
ted_15_valid:
	dc.b	'F',0
ted_18_text:
	dc.b	'MS DOS',0
ted_19_text:
	dc.b	'TOS',0
ted_20_text:
	dc.b	'Optimized',0
ted_23_text:
	dc.b	'X:',0
ted_24_text:
	dc.b	'Data Storage',0
ted_25_text:
	dc.b	'Formatting',0
ted_26_text:
	dc.b	'User Interface',0
ted_27_text:
	dc.b	'9999',0
ted_27_tmplt:
	dc.b	'____ KByte',0
ted_27_valid:
	dc.b	'9',0
ted_28_text:
	dc.b	'99',0
ted_28_tmplt:
	dc.b	'__',0
ted_28_valid:
	dc.b	'9',0
ted_29_text:
	dc.b	'Error',0
ted_30_text:
	dc.b	'Accessory',0
ted_31_text:
	dc.b	'DD',0
ted_32_text:
	dc.b	'HD 5',$ac,0
ted_33_text:
	dc.b	'HD 3',$ab,0
ted_34_text:
	dc.b	'2',0
ted_35_text:
	dc.b	'3',0
ted_36_text:
	dc.b	'6',0
ted_37_text:
	dc.b	'12',0
ted_38_text:
	dc.b	'DD',0
ted_39_text:
	dc.b	'HD 5',$ac,0
ted_40_text:
	dc.b	'HD 3',$ab,0
ted_41_text:
	dc.b	'2',0
ted_42_text:
	dc.b	'3',0
ted_43_text:
	dc.b	'6',0
ted_44_text:
	dc.b	'12',0
ted_45_text:
	dc.b	'Drive A',0
ted_46_text:
	dc.b	'Drive B',0
ted_47_text:
	dc.b	'Automatic/Switch',0
ted_48_text:
	dc.b	'Low',0
ted_49_text:
	dc.b	'High',0
ted_50_text:
	dc.b	'Low',0
ted_51_text:
	dc.b	'High',0
ted_52_text:
	dc.b	'High Density Detect',0
ted_53_text:
	dc.b	'99999',0
ted_53_tmplt:
	dc.b	'_____',0
ted_53_valid:
	dc.b	'9',0
ted_54_text:
	dc.b	'F1',0
ted_55_text:
	dc.b	'F2',0
ted_56_text:
	dc.b	'C->S',0
ted_57_text:
	dc.b	'I->M',0
ted_58_text:
	dc.b	0
	dc.b	' 23456789012345678901234567890123456789012345678901234567890'
	dc.b	'12345',0
ted_58_tmplt:
	dc.b	'____________________________________________________________'
	dc.b	'_____',0
ted_58_valid:
	dc.b	'X',0
ted_59_text:
	dc.b	0
	dc.b	' 9999',0
ted_59_tmplt:
	dc.b	'Search from Sector _____',0
ted_59_valid:
	dc.b	'n',0
ted_60_text:
	dc.b	0
	dc.b	' 9999',0
ted_60_tmplt:
	dc.b	'to Sector _____',0
ted_60_valid:
	dc.b	'n',0
ted_61_text:
	dc.b	0
	dc.b	' 23456789012345678901234567890123456789012345678901234567890',0
ted_61_tmplt:
	dc.b	'____________________________________________________________',0
ted_61_valid:
	dc.b	'X',0
ted_62_text:
	dc.b	'_______',0
ted_62_tmplt:
	dc.b	'Enter Name of Preset: _______',0
ted_62_valid:
	dc.b	'X',0
ted_63_text:
	dc.b	0
	dc.b	'____',0
ted_63_tmplt:
	dc.b	'Save from Sector _____',0
ted_63_valid:
	dc.b	'n',0
ted_64_text:
	dc.b	0
	dc.b	'____',0
ted_64_tmplt:
	dc.b	'to Sector _____',0
ted_64_valid:
	dc.b	'n',0
ted_65_text:
	dc.b	0
	dc.b	'____',0
ted_65_tmplt:
	dc.b	'Load to Sector _____',0
ted_65_valid:
	dc.b	'n',0
main_09_text:
	dc.b	'Copy Disk',0
main_10_text:
	dc.b	'Scan Disk',0
main_11_text:
	dc.b	'Format Disk',0
main_12_text:
	dc.b	'Streamer',0
main_13_text:
	dc.b	'Directory',0
main_14_text:
	dc.b	'New Conf',0
main_15_text:
	dc.b	'Inspect Disk',0
main_16_text:
	dc.b	'Soft Format',0
main_17_text:
	dc.b	'Image Copy',0
main_18_text:
	dc.b	'Quit',0
main_20_text:
	dc.b	'Presets',0
main_32_text:
	dc.b	'Verify Destination',0
main_34_text:
	dc.b	'Smart Formatting',0
main_36_text:
	dc.b	'Format Destination',0
main_39_text:
	dc.b	'Read Disk Config.',0
main_41_text:
	dc.b	'Multiple Copy',0
main_42_text:
	dc.b	'Get Sectors',0
main_43_text:
	dc.b	'all',0
main_44_text:
	dc.b	'used',0
main_46_text:
	dc.b	'Source',0
main_50_text:
	dc.b	'Dest.',0
main_54_text:
	dc.b	'Disk Configuration',0
main_55_text:
	dc.b	'Sides',0
main_58_text:
	dc.b	'Sectors',0
main_62_text:
	dc.b	'Start at',0
main_69_text:
	dc.b	'End at',0
main_73_text:
	dc.b	'Density',0
main_74_text:
	dc.b	'>> More Options',0
main_75_text:
	dc.b	'Save Config.',0
list_02_text:
	dc.b	7,0
list_03_text:
	dc.b	'X',0
list_17_text:
	dc.b	1,0
list_20_text:
	dc.b	2,0
format_01_text:
	dc.b	'X: Destination Disk',0
format_07_text:
	dc.b	'Directory Entries:',0
format_14_text:
	dc.b	'Sectors per Cluster:',0
format_19_text:
	dc.b	'Put Guardian on Boot-Sector',0
format_21_text:
	dc.b	'DATA DISK',0
error_02_text:
	dc.b	'RETRY',0
error_03_text:
	dc.b	'CONTINUE',0
error_04_text:
	dc.b	'BEST MATCH',0
error_05_text:
	dc.b	'NEW DISK',0
drive_06_text:
	dc.b	'DIRECTORY',0
options_03_text:
	dc.b	'Compack Streamer Data',0
options_05_text:
	dc.b	'Optimize Partition when writing',0
options_07_text:
	dc.b	'Use Harddisk as Extended Memory',0
options_09_text:
	dc.b	'Current Partition is A:',0
options_10_text:
	dc.b	'Select',0
options_13_text:
	dc.b	'Fast Format',0
options_15_text:
	dc.b	'Fast Access headers',0
options_18_text:
	dc.b	'Show Request Boxes',0
options_20_text:
	dc.b	'Use Sound',0
options_22_text:
	dc.b	'Mouse Accelerator',0
options_28_text:
	dc.b	'Reserve',0
options_33_text:
	dc.b	'Retries',0
options_42_text:
	dc.b	'Sides',0
options_43_text:
	dc.b	'Density',0
options_52_text:
	dc.b	'ms',0
options_53_text:
	dc.b	'Steprate',0
options_58_text:
	dc.b	'Sides',0
options_59_text:
	dc.b	'Density',0
options_68_text:
	dc.b	'ms',0
options_69_text:
	dc.b	'Steprate',0
options_78_text:
	dc.b	'PSG Bit 6',0
options_79_text:
	dc.b	'PSG Bit 7',0
about_01_text:
	dc.b	'FastCopy PRO',0
inspect_18_text:
	dc.b	'D',0
inspect_19_text:
	dc.b	7,0
inspect_43_text:
	dc.b	'Change',0
inspect_44_text:
	dc.b	'Search',0
inspect_45_text:
	dc.b	'Next',0
inspect_46_text:
	dc.b	'Write',0
inspect_47_text:
	dc.b	'Main Menu',0
inspect_48_text:
	dc.b	'Save',0
inspect_49_text:
	dc.b	'Load',0
inspect_50_text:
	dc.b	'Boot-Sector:',0
inspect_51_text:
	dc.b	'Analyse',0
inspect_52_text:
	dc.b	'Protect',0
values_01_text:
	dc.b	'Enter Values (e.g. 13,-34,$a6,"FCopy",12,0,,4) :',0
search_05_text:
	dc.b	'Ignore Case',0
search_10_text:
	dc.b	'Searching in Sector',0
search_12_text:
	dc.b	'99999',0
goto_03_text:
	dc.b	'GOTO',0
high_res_coords:
	dc.w	$0000,$0000,$004e,$0917,$0302,$0800,$0149,$0401
	dc.w	$0600,$0f01,$034c,$0001,$0600,$0003,$034c,$0e07
	dc.w	$0205,$0406,$0630,$0001,$0036,$0406,$0410,$0001
	dc.w	$0205,$0b06,$0630,$0001,$0036,$0b06,$0410,$0001
	dc.w	$0600,$0f0a,$034c,$0903,$0001,$0500,$000e,$0801
	dc.w	$0110,$0500,$000e,$0801,$021f,$0500,$000e,$0801
	dc.w	$032e,$0500,$000e,$0801,$043d,$0500,$000e,$0801
	dc.w	$0001,$0402,$000e,$0001,$0110,$0402,$000e,$0001
	dc.w	$021f,$0402,$000e,$0001,$032e,$0402,$000e,$0001
	dc.w	$043d,$0402,$000e,$0001,$0042,$0b0e,$020b,$0908
	dc.w	$0202,$0600,$0007,$0001,$0401,$0f01,$0001,$0001
	dc.w	$0502,$0f01,$0007,$0001,$0401,$0403,$0001,$0001
	dc.w	$0502,$0403,$0007,$0001,$0401,$0904,$0001,$0001
	dc.w	$0502,$0904,$0007,$0001,$0401,$0e05,$0001,$0001
	dc.w	$0502,$0e05,$0007,$0001,$0401,$0307,$0001,$0001
	dc.w	$0502,$0307,$0007,$0001,$0600,$0c0e,$0318,$0708
	dc.w	$0101,$0400,$0012,$0001,$0714,$0400,$0002,$0001
	dc.w	$0101,$0a01,$0010,$0001,$0714,$0a01,$0002,$0001
	dc.w	$0101,$0003,$0012,$0001,$0714,$0003,$0002,$0001
	dc.w	$0714,$0604,$0002,$0001,$0201,$0704,$0011,$0001
	dc.w	$0714,$0c05,$0002,$0001,$0201,$0d05,$000d,$0001
	dc.w	$0101,$0207,$000b,$0001,$060d,$0207,$0004,$0001
	dc.w	$0412,$0207,$0304,$0001,$0519,$0c0e,$0508,$0405
	dc.w	$0301,$0600,$0006,$0001,$0601,$0102,$0005,$0001
	dc.w	$0601,$0803,$0005,$0001,$0322,$0c0e,$0508,$0405
	dc.w	$0701,$0600,$0005,$0001,$0601,$0102,$0005,$0001
	dc.w	$0601,$0803,$0005,$0001,$042b,$0c0e,$0416,$0708
	dc.w	$0302,$0500,$0012,$0001,$0301,$0e01,$0005,$0001
	dc.w	$020b,$0e01,$0004,$0001,$0510,$0e01,$0004,$0001
	dc.w	$0301,$0303,$0007,$0001,$020b,$0303,$0003,$0001
	dc.w	$000f,$0303,$0002,$0001,$0511,$0303,$0003,$0001
	dc.w	$0301,$0904,$0008,$0001,$020b,$0804,$0003,$0001
	dc.w	$000f,$0804,$0002,$0001,$0511,$0804,$0003,$0001
	dc.w	$020b,$0d05,$0003,$0001,$000f,$0d05,$0002,$0001
	dc.w	$0511,$0d05,$0003,$0001,$0301,$0e05,$0006,$0001
	dc.w	$010b,$0007,$030a,$0201,$0100,$0200,$0004,$0001
	dc.w	$0405,$0200,$0004,$0001,$0301,$0207,$0007,$0001
	dc.w	$0619,$0514,$0111,$0701,$0619,$0216,$0111,$0001
	dc.w	$0000,$0000,$0747,$0a07,$0500,$0400,$033e,$0001
	dc.w	$0640,$0300,$0602,$0601,$0344,$0400,$0402,$0401
	dc.w	$0001,$0901,$003e,$0006,$0000,$0000,$001d,$0001
	dc.w	$0021,$0000,$001d,$0001,$0000,$0001,$001d,$0001
	dc.w	$0021,$0001,$001d,$0001,$0000,$0002,$001d,$0001
	dc.w	$0021,$0002,$001d,$0001,$0000,$0003,$001d,$0001
	dc.w	$0021,$0003,$001d,$0001,$0000,$0004,$001d,$0001
	dc.w	$0021,$0004,$001d,$0001,$0000,$0005,$001d,$0001
	dc.w	$0021,$0005,$001d,$0001,$0540,$0f01,$0003,$0a02
	dc.w	$0244,$0f01,$0003,$0905,$0000,$0001,$0003,$0003
	dc.w	$0540,$0a04,$0003,$0e02,$0000,$0000,$0626,$0512
	dc.w	$060a,$0a00,$0013,$0001,$0209,$0e02,$0016,$0001
	dc.w	$0008,$0d04,$0017,$0001,$0008,$0006,$001a,$0001
	dc.w	$0000,$0000,$0001,$0001,$0401,$0d07,$0523,$0707
	dc.w	$0002,$0900,$0012,$0001,$0317,$0a00,$0003,$0001
	dc.w	$071a,$0a00,$0003,$0001,$041e,$0a00,$0003,$0001
	dc.w	$071b,$0f01,$0001,$0001,$0317,$0002,$0003,$0001
	dc.w	$041e,$0002,$0003,$0001,$0002,$0102,$0014,$0001
	dc.w	$0102,$0d03,$0009,$0001,$070c,$0d03,$0009,$0001
	dc.w	$0417,$0c03,$000a,$0001,$0102,$0d05,$0002,$0001
	dc.w	$0305,$0d05,$001b,$0001,$0701,$0810,$0009,$0001
	dc.w	$010e,$0810,$000a,$0001,$001b,$0810,$000a,$0001
	dc.w	$0000,$0000,$0542,$0505,$020c,$0e00,$022a,$0001
	dc.w	$0002,$0003,$000b,$0801,$000f,$0003,$000b,$0801
	dc.w	$001c,$0003,$000b,$0801,$0029,$0003,$000b,$0801
	dc.w	$0036,$0003,$000b,$0801,$0000,$0000,$0020,$0807
	dc.w	$0002,$0001,$001c,$0001,$000b,$0003,$0002,$0001
	dc.w	$000f,$0003,$0002,$0001,$0013,$0003,$0002,$0001
	dc.w	$0501,$0605,$0008,$0001,$000b,$0605,$000a,$0001
	dc.w	$0316,$0605,$0008,$0001,$0000,$0000,$004d,$0017
	dc.w	$0701,$0001,$0327,$0a07,$0601,$0301,$0002,$0001
	dc.w	$0404,$0301,$0015,$0001,$0601,$0902,$0002,$0001
	dc.w	$0404,$0902,$001f,$0001,$0601,$0604,$0002,$0001
	dc.w	$0404,$0604,$001f,$0001,$0204,$0805,$0222,$0501
	dc.w	$0100,$0200,$0017,$0001,$0119,$0400,$0108,$0001
	dc.w	$0701,$050a,$0518,$0604,$0501,$0301,$0002,$0001
	dc.w	$0304,$0301,$000b,$0001,$0501,$0a02,$0002,$0001
	dc.w	$0304,$0a02,$0013,$0001,$0701,$0510,$0717,$0c05
	dc.w	$0501,$0201,$0002,$0001,$0404,$0201,$0012,$0001
	dc.w	$0501,$0a02,$0002,$0001,$0504,$0a02,$0009,$0001
	dc.w	$0501,$0204,$0002,$0001,$0604,$0204,$0011,$0001
	dc.w	$0303,$0900,$000c,$0001,$0303,$0d09,$000a,$0001
	dc.w	$0203,$0d0f,$000e,$0001,$041c,$050a,$070d,$0604
	dc.w	$0701,$0a02,$000a,$0001,$0303,$0501,$0007,$0001
	dc.w	$001c,$0510,$0212,$0403,$0701,$0601,$0002,$0001
	dc.w	$0404,$0601,$0002,$0001,$0207,$0601,$0002,$0001
	dc.w	$000a,$0601,$0007,$0001,$041c,$0f14,$0008,$0001
	dc.w	$051d,$0d0f,$0005,$0001,$061d,$0e09,$0009,$0001
	dc.w	$0126,$0f14,$0008,$0001,$022c,$0001,$021e,$0106
	dc.w	$040b,$0501,$050b,$0401,$0200,$0200,$0005,$0001
	dc.w	$0006,$0200,$0005,$0001,$0701,$0701,$0005,$0001
	dc.w	$0601,$0e02,$0007,$0001,$060b,$0e02,$0005,$0001
	dc.w	$0511,$0e02,$0005,$0001,$0317,$0e02,$0005,$0001
	dc.w	$050b,$0204,$060d,$0601,$0100,$0300,$0002,$0001
	dc.w	$0702,$0300,$0002,$0001,$0505,$0300,$0002,$0001
	dc.w	$0308,$0300,$0002,$0001,$010b,$0300,$0002,$0001
	dc.w	$0601,$0504,$0008,$0001,$022c,$0908,$021e,$0206
	dc.w	$040b,$0501,$050b,$0401,$0200,$0200,$0005,$0001
	dc.w	$0006,$0200,$0005,$0001,$0601,$0701,$0005,$0001
	dc.w	$0601,$0e02,$0007,$0001,$060b,$0e02,$0005,$0001
	dc.w	$0511,$0e02,$0005,$0001,$0317,$0e02,$0005,$0001
	dc.w	$050b,$0204,$070d,$0501,$0100,$0300,$0002,$0001
	dc.w	$0702,$0300,$0002,$0001,$0505,$0300,$0002,$0001
	dc.w	$0308,$0300,$0002,$0001,$010b,$0300,$0002,$0001
	dc.w	$0601,$0504,$0008,$0001,$032e,$0800,$0007,$0001
	dc.w	$032e,$0108,$0007,$0001,$0330,$0510,$001a,$0c05
	dc.w	$0701,$0301,$0016,$0001,$060c,$0c02,$0005,$0001
	dc.w	$0712,$0c02,$0005,$0001,$060c,$0404,$0005,$0001
	dc.w	$0612,$0404,$0005,$0001,$0701,$0c02,$0009,$0001
	dc.w	$0701,$0404,$0009,$0001,$0332,$0d0f,$0013,$0001
	dc.w	$0000,$0000,$0021,$0012,$010b,$0001,$000c,$0001
	dc.w	$070d,$0403,$3000,$1c00,$010b,$0106,$0013,$0001
	dc.w	$0002,$0009,$001d,$0001,$0009,$000a,$0010,$0001
	dc.w	$0007,$000c,$0013,$0001,$0205,$000d,$0017,$0001
	dc.w	$020d,$0d0f,$0008,$0001,$0000,$0000,$014d,$0217
	dc.w	$0401,$0200,$0447,$0310,$0200,$0000,$0047,$0001
	dc.w	$0200,$0001,$0047,$0001,$0200,$0002,$0047,$0001
	dc.w	$0200,$0003,$0047,$0001,$0200,$0004,$0047,$0001
	dc.w	$0200,$0005,$0047,$0001,$0200,$0006,$0047,$0001
	dc.w	$0200,$0007,$0047,$0001,$0200,$0008,$0047,$0001
	dc.w	$0200,$0009,$0047,$0001,$0200,$000a,$0047,$0001
	dc.w	$0200,$000b,$0047,$0001,$0200,$000c,$0047,$0001
	dc.w	$0200,$000d,$0047,$0001,$0200,$000e,$0047,$0001
	dc.w	$0200,$000f,$0047,$0001,$0249,$0200,$0601,$0801
	dc.w	$0249,$0c01,$0601,$0801,$0149,$0603,$0002,$0901
	dc.w	$0149,$0005,$0002,$0c09,$0000,$0a01,$0002,$0c03
	dc.w	$0149,$0d0e,$0002,$0801,$0401,$0610,$0003,$0001
	dc.w	$0504,$0610,$0241,$0001,$0013,$0000,$0005,$0001
	dc.w	$0046,$0610,$0003,$0001,$0601,$0d11,$0746,$0d02
	dc.w	$0001,$0000,$0621,$0001,$0000,$0000,$0020,$0001
	dc.w	$0423,$0000,$000e,$0001,$0000,$0000,$000c,$0001
	dc.w	$0532,$0000,$0113,$0101,$0200,$0000,$0012,$0001
	dc.w	$0201,$0901,$0002,$0001,$0104,$0901,$0002,$0001
	dc.w	$0007,$0901,$0002,$0001,$0709,$0901,$0002,$0001
	dc.w	$060c,$0901,$0002,$0001,$050f,$0901,$0002,$0001
	dc.w	$0614,$0901,$0004,$0001,$0719,$0901,$0004,$0001
	dc.w	$0521,$0901,$0008,$0001,$062b,$0901,$0008,$0001
	dc.w	$0035,$0901,$0005,$0001,$023c,$0901,$0009,$0001
	dc.w	$0103,$0715,$000b,$0001,$0110,$0715,$0008,$0001
	dc.w	$011a,$0715,$0008,$0001,$0324,$0715,$000c,$0001
	dc.w	$0531,$0715,$000a,$0001,$023d,$0715,$000a,$0001
	dc.w	$0000,$0000,$004b,$0005,$0002,$0001,$0030,$0001
	dc.w	$0036,$0001,$0008,$0001,$0040,$0001,$0008,$0001
	dc.w	$0004,$0003,$0041,$0001,$0000,$0000,$053f,$0a0a
	dc.w	$0006,$0001,$0018,$0001,$001f,$0001,$000f,$0001
	dc.w	$0035,$0001,$0008,$0001,$0006,$0003,$0002,$0001
	dc.w	$0009,$0003,$000b,$0001,$0035,$0003,$0008,$0001
	dc.w	$0601,$0f04,$0001,$0001,$0601,$0706,$003c,$0001
	dc.w	$0111,$0908,$001d,$0001,$0002,$0000,$0013,$0001
	dc.w	$0016,$0000,$0006,$0001,$0000,$0000,$0005,$0001
	dc.w	$0000,$0000,$0020,$0005,$0006,$0003,$0008,$0001
	dc.w	$0002,$0001,$001c,$0001,$0012,$0003,$0008,$0001
	dc.w	$0000,$0000,$0039,$0003,$0002,$0001,$001d,$0001
	dc.w	$0024,$0001,$0008,$0001,$002e,$0001,$0008,$0001
	dc.w	$0000,$0000,$0044,$0003,$0002,$0001,$0016,$0001
	dc.w	$0019,$0001,$000f,$0001,$002f,$0001,$0008,$0001
	dc.w	$0039,$0001,$0008,$0001,$0000,$0000,$0031,$0003
	dc.w	$0002,$0001,$0014,$0001,$001d,$0001,$0008,$0001
	dc.w	$0027,$0001,$0008,$0001
