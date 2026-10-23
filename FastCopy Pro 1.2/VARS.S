; VARS.S  -  the initialised data after the configuration, included by FCOPYPRO.S
;
; resource_fixed and the object list it is stored with, the message checksums, the
; directory, options and file selector texts and tables, and the other variables up to
; the end of the data section.

resource_fixed:
	dc.w	$0000,$0000,$0078,$0116,$011b,$0128,$012c,$0130
	dc.w	$0135,$ffff
keys_preset:
	dc.w	$0061,$0602
str_ret_ok_undo_cancel:
	dc.b	'<Ret.>   OK|<Undo>   CANCEL ',0
alert_drive_x_is_not_active_no:
	dc.b	'[1][Drive X: is not active!|No Extended Memory is used!][ OK'
	dc.b	' ]',0
message_sums:
	dc.w	$7a3e,$06e7,$975b,$0f88,$8fab
alert_cannot_access_xxxxxxxxxxxx:
	dc.b	'[1][Cannot access XXXXXXXXXXXX!  |Select the proper path and'
	dc.b	'|program file.][ OK ]',0
str_fcopypro_xxx:
	dc.b	'FCOPYPRO.XXX',0
str_next:
	dc.b	' NEXT ',0
str_ok_3:
	dc.b	' OK ',0
str_prev:
	dc.b	' PREV ',0
alert_cannot_install_the_mouse:
	dc.b	'[1][Cannot install|the Mouse Accelerator! ][ OK ]',0
alert_unable_to_open_window_please:
	dc.b	'[1][Unable to open Window!|Please remove one|and try again.]'
	dc.b	'[ ABORT ]',0
str_display_directory:
	dc.b	'Display Directory',0
alert_save_configuration_yes_no:
	dc.b	'[2][Save Configuration?  ][ YES | NO ]',0
str_prg:
	dc.b	'PRG',0
str_acc:
	dc.b	'ACC',0
str_save_configuration_into:
	dc.b	'Save Configuration into...',0
str_all_files:
	dc.w	$5c2a,$2e00
str_mch:
	dc.b	'_MCH',0
str_frb:
	dc.b	'_FRB',0
str_alert_0:
	dc.w	$5b30
str_alert_sep:
	dc.w	$5d5b
	dc.b	$00
str_bar:
	dc.b	$7c,$00,$00
str_x_x:
	dc.b	'X:\\X',0
underlines_options:
	dc.w	$0363,$0107,$6501,$056f,$010d,$660b,$0f68,$0b16
	dc.w	$6d10,$1262,$1014,$7510
	dc.b	'*s&+d&5p&:s6;d6Ep6',0
keys_options:
	dc.b	$00,$61,$25,$00,$2e,$02,$00,$12,$06,$00,$18,$04,$00,$21,$0c,$00
	dc.b	$23,$0e,$00,$1e,$12,$00,$30,$11,$00,$16,$13,$00,$32,$15,$00,$1f
	dc.b	$28,$01,$1f,$38,$00,$20,$2c,$01,$20,$3c,$00,$19,$30,$01,$19,$40
	dc.b	$00,$13,$49,$00,$0f,$0a,$00,$1b,$20,$00,$35,$1e,$02
str_configure_drive_a_b_s_sides_d:
	dc.b	'Configure Drive A,B:|<s> Sides|<d> Density|<p> Steprate in D'
	dc.b	'D mode|Use <Shift> for Drive B @  <Tab> Set Ext.Mem. Drive| '
	dc.b	'   <r> HD Detect|<+>,<-> Error Retries +1,-1 | <Undo> Cancel'
	dc.b	'@For the other settings use |the underlined char.',0
str_select_drive_for_ext_memory:
	dc.b	'Select Drive for Ext. Memory',0
	dc.b	$00
alert_cant_read_directory_please:
	dc.b	'[3][Can''t read directory!|Please check your disk!][ ABORT ]',0
alert_x_source_disk_dir_abort:
	dc.b	'[0][ X: Source Disk| ][ DIR | ABORT ]',0
keys_directory:
	dc.w	$0048,$1100,$5014,$0001,$0200,$6103
	dc.b	$02
str_scroll_up_scroll_down_esc_re:
	dc.b	'  </>  Scroll up|  <*>  Scroll down| <Esc> Re-Read|<Ret.> Qu'
	dc.b	'it',0
str_a:
	dc.b	'A:\*.*',0
str_bytes:
	dc.b	' Bytes (',0
str_free:
	dc.b	'%) free',0
fill_black:
	dc.w	$ffff
str_name:
	dc.b	'Name: ',0
str_dash:
	dc.b	$2d,$00
str_spaces:
	dc.b	'    ',0
str_used:
	dc.b	'%) used    ',0
str_parent:
	dc.b	'>>Parent<<',0
	dc.b	$00
