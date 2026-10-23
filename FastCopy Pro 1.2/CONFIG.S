; CONFIG.S  -  critical error handler and configuration of FCOPYPRO.PRG, included by FCOPYPRO.S
;
; critic_xbra..critic_handler: the etv_critic hook (XBRA FCOP), installed while FastCopy
; runs.  config: the 112 bytes save_config writes back into FCOPYPRO.PRG/.ACC, starting
; with the $2442 mark: the five presets, the drive A/B settings, the options and the
; selections of the main dialog.

critic_xbra:
	dc.b	'XBRAFCOP'
critic_old:
	dc.l	$00000000
critic_handler:
	rts

config:
	dc.w	$2442
presets:
; name, sides - 1, sectors, start track, end track, high density, unused
	dc.b	'Default',0
	dc.b	1,9,0,79,0,0
	dc.b	'Fat DD',0,0
	dc.b	1,11,0,82,0,0
	dc.b	'HD 5.25',0
	dc.b	1,15,0,79,1,0
	dc.b	'HD 3.5',0,0
	dc.b	1,18,0,79,1,0
	dc.b	'Fat HD',0,0
	dc.b	1,22,0,82,1,0
cfg_a_double_sided:
	dc.b	$01
cfg_a_density:
	dc.b	$02
cfg_b_double_sided:
	dc.b	$01
cfg_b_density:
	dc.b	$00
cfg_a_step_rate:
	dc.b	$02
cfg_b_step_rate:
	dc.b	$01
cfg_reserve_kb:
	dc.w	$0000
cfg_hd_detect:
	dc.b	$00
cfg_fast_access:
	dc.b	$01
cfg_compack:
	dc.b	$01
cfg_optimize_partition:
	dc.b	$01
cfg_request_boxes:
	dc.b	$01
cfg_mouse_accel:
	dc.b	$00
cfg_sound:
	dc.b	$01
cfg_retries:
	dc.b	$04
cfg_format_type:
	dc.b	$02
cfg_format_guardian:
	dc.b	$00
cfg_smart_format:
	dc.b	$01
cfg_ext_memory:
	dc.b	$00
cfg_ext_memory_drive:
	dc.b	$02
cfg_source_drive:
	dc.b	$00
cfg_dest_drive:
	dc.b	$00
cfg_format_dest:
	dc.b	$00
cfg_verify_dest:
	dc.b	$00
cfg_multiple_copy:
	dc.b	$00
cfg_fast_format:
	dc.b	$01
cfg_read_config:
	dc.b	$01
cfg_used_only:
	dc.w	$0100
cfg_sides:
	dc.w	$0001
cfg_sectors:
	dc.w	$0009
cfg_start_track:
	dc.w	$0000
cfg_end_track:
	dc.w	$004f
cfg_hd:
	dc.b	$00
cfg_disk_name:
	dc.b	$00
