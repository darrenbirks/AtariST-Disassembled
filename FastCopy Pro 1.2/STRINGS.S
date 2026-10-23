; STRINGS.S  -  strings and tables of FCOPYPRO.PRG, included by FCOPYPRO.S
;
; The initialised data between the resource and the configuration, in program order:
; form_alert texts (alert_*), status and help texts (str_*), the form_do keyboard tables
; (keys_*: shift flag, scancode, object; 2 ends a table), the underline tables
; (underlines_*: object, letter, parent; 0 ends), fill patterns, step rate tables and a
; few flags.  X and XX in the texts are patched with drive letters and numbers.

alert_not_enough_memory_free_for:
	dc.b	'[3][Not enough memory free|for restructuring the|directories'
	dc.b	'!][ STOP ]',0
	dc.b	$00
alert_read_error_on_directory_entry:
	dc.b	'[1][Read Error on  |directory entry!][ CONT | ABORT ]',0
str_backslash:
	dc.w	$5c00
str_newline:
	dc.w	$0a0d
	dc.b	$00
alert_cannot_read_directory_stop:
	dc.b	'[3][Cannot read Directory! ][ STOP ]',0
alert_cannot_write_directory_stop:
	dc.b	'[3][Cannot write Directory! ][ STOP ]',0
alert_please_remove_write:
	dc.b	'[1][Please remove|WRITE-PROTECTION|on Disk in Drive X:][ OK '
	dc.b	'| ABORT ]',0
alert_put_boot_sector_guardian_on:
	dc.b	'[2][Put Boot-Sector Guardian|on selected Drive X: ?][ OK | C'
	dc.b	'ANCEL ]',0
alert_cannot_open_file_abort:
	dc.b	'[3][Cannot open file!  ][ ABORT ]',0
alert_cannot_write_file_abort:
	dc.b	'[3][Cannot write file!  ][ ABORT ]',0
str_the_boot_sector:
	dc.b	' The Boot-Sector| ',0
str_contains_no_virus_great:
	dc.b	'contains NO VIRUS!][ GREAT ]',0
str_is_not_executable_but_maybe:
	dc.b	'is NOT executable| but maybe contains| a sleeping VIRUS!][ O'
	dc.b	'K | CLEAR | PROTECT ]',0
str_is_executable_but_contains_no:
	dc.b	'is executable but|contains NO VIRUS!][ GREAT ]',0
str_is_executable_and_maybe:
	dc.b	'is executable and|MAYBE contains a VIRUS!][ OK | CLEAR | PRO'
	dc.b	'TECT ]',0
alert_drive_x:
	dc.b	'[1][ Drive X:|',0
str_read_error_on_sector:
	dc.b	' Read Error on Sector ',0
str_write_error_on_sector:
	dc.b	' Write Error on Sector ',0
str_ok_retry_quit:
	dc.b	' ][ OK | RETRY | QUIT ]',0
str_abort_retry:
	dc.b	' ][ ABORT | RETRY ]',0
keys_search:
	dc.b	$00,$3b,$04,$00,$61,$06,$02
str_f1_toggle_ignore_case_undo:
	dc.b	'  <F1> Toggle Ignore Case |<Undo> Cancel|Predefined sector m'
	dc.b	'acros:|c,b,f1,f2,r,d,e',0
keys_values:
	dc.b	$00,$61,$03,$02
str_undo_cancel:
	dc.b	'<Undo> Cancel ',0
keys_save:
	dc.w	$0061,$0402
keys_load:
	dc.w	$0061,$0302
str_undo_cancel_predefined_sector:
	dc.b	'<Undo> Cancel|Predefined sector macros:|c,b,f1,f2,r,d,e',0
keys_inspect:
	dc.w	$001e,$3300,$3023,$002e,$2b00,$2027,$0021,$2401
	dc.w	$2125,$0012,$2800,$2631,$0019,$3400,$1326,$001f
	dc.w	$2c01,$1f30,$0031,$2d00,$112e,$0101,$1200,$612f
	dc.w	$0001,$1300,$1c1a,$0072,$1a01,$4814,$0150,$1701
	dc.w	$4d1b,$014b,$1800,$3c2a,$003b,$2902
str_undo_return_to_main_menu_jump:
	dc.b	'<Undo> Return to Main menu|Jump to important locations: |<b>'
	dc.b	' Bootsec.   <r> Root Dir.|<f> FAT 1      <d> Data Area|<F> F'
	dc.b	'AT 2      <e> Last Sec.@<c> Change     <f> Find|<n> Find Nex'
	dc.b	't  <s> Search|<w> Write      <Esc> Re-Read|<l> Load sec.  <S'
	dc.b	'> Save sec. |<F1> C->S      <F2> I-M@<F3> Goto Directory Ent'
	dc.b	'ry|<Shift>-<Esc> Select Drive |Boot-Sector functions:|<a> An'
	dc.b	'alyse, Virus Check|<p> Protect with Guardian@Use Cursor keys'
	dc.b	' or the mouse|pointer to move the cursor.|<Shift>-<(>,<)> Pr'
	dc.b	'ev,Next Sec. |<Shift>-</>,<*> Prev,Next Page|<Ctrl>-<(>,<)> '
	dc.b	'Fast Move@<Home> moves cursor to the top |or the end of the '
	dc.b	'sector.',0
str_return_ok_g_goto:
	dc.b	'<Return> OK|     <g> Goto ',0
keys_goto:
	dc.b	$00,$22,$03,$02,$00
inspect_drive:
	dc.w	$0000
hex_digits:
	dc.b	'0123456789abcdef'
str_offset:
	dc.b	'Offset $',0
str_select_drive_to_inspect:
	dc.b	'Select Drive to Inspect',0
	dc.b	$00
virus_marker:
	dc.w	$1212,$3456
keys_none:
	dc.b	$02
keys_drive:
	dc.b	$00,$4b,$02,$00,$4d,$04,$00,$61,$07,$01,$20,$06,$02
str_a_p_select_drive_a_p_select:
	dc.b	'<a>..<p> Select Drive A-P |<(> Select prev. Drive|<)> Select'
	dc.b	' next Drive|<D> Display Directory|<Undo> Abort',0
	dc.b	$00
str_drive_x:
	dc.b	'Drive X, ',0
str_bps:
	dc.b	' BpS, ',0
str_sectors:
	dc.b	' Sectors',0
str_s:
	dc.b	'S ',0
str_tr:
	dc.b	' Tr ',0
str_sec:
	dc.b	' Sec ',0
str_system_area:
	dc.b	'System Area',0
str_cluster:
	dc.b	'Cluster ',0
alert_in_order_to_jump_to_a:
	dc.b	'[1][In order to jump to|a directory entry|put the cursor ont'
	dc.b	'o|the filename!][ OK ]',0
str_motorola_word:
	dc.b	'Motorola Word ',0
str_logical_sector:
	dc.b	'Logical Sector ',0
str_hex_open:
	dc.b	$20,$28,$24,$00
str_hex_close:
	dc.b	$29,$00
str_select_file_to_load_from:
	dc.b	'Select File to load from',0
str_all_names:
	dc.w	$2a00
str_select_file_to_save_to:
	dc.b	'Select File to save to',0
alert_pattern_found_ok_cont:
	dc.b	'[1][Pattern found!][ OK | CONT ]',0
alert_pattern_not_found_ok:
	dc.b	'[1][Pattern not found!][ OK ]',0
alert_analyse_protect_work_only:
	dc.b	'[1][Analyse/Protect work|only with boot-sectors|of diskettes'
	dc.b	'.][ OK ]',0
alert_write_sector_ok_cancel:
	dc.b	'[2][  Write Sector?][ OK | CANCEL ]',0
alert_sector_has_been_modified:
	dc.b	'[2][Sector has been modified!|Write it back?][ YES | NO ]',0
alert_no_drives_found_abort:
	dc.b	'[1][No Drives found!][ ABORT ]',0
alert_x_destination_disk_format:
	dc.b	'[0][X: Destination Disk  | ][ FORMAT | ABORT ]',0
alert_drive_x_is_one_sided_abort:
	dc.b	'[1][Drive X: is one-sided!  | ][ ABORT ]',0
alert_drive_x_doesnt_support_this:
	dc.b	'[1][Drive X: doesn''t support|this High Density mode!][ ABORT'
	dc.b	' ]',0
alert_drive_x_does_only_support_xx:
	dc.b	'[1][Drive X: does only|support XX Sectors|per Track!][ ABORT'
	dc.b	' ]',0
alert_cannot_access_system_sectors:
	dc.b	'[1][Cannot access|System sectors!][ ABORT ]',0
alert_cannot_write_diskname_ok:
	dc.b	'[1][Cannot write Diskname!| ][ OK ]',0
alert_not_enough_memory_free_ok:
	dc.b	'[1][Not enough memory free!  ][ OK ]',0
str_error_while:
	dc.b	'Error while ',0
str_track_of_drive_x:
	dc.b	' Track of Drive X:',0
str_formatting:
	dc.b	'FORMATTING',0
str_verifying:
	dc.b	'VERIFYING',0
str_scanning:
	dc.b	'SCANNING',0
str_reading:
	dc.b	'READING',0
str_writing:
	dc.b	'WRITING',0
alert_keep_old_disk_configuration:
	dc.b	'[2][Keep old Disk Configuration|or take new Settings?|Warnin'
	dc.b	'g: ''TAKE'' destroys|the Bad Sector List!][ KEEP | TAKE | CANC'
	dc.b	'EL ]',0
str_alert_1:
	dc.b	'[1][',0
str_sector_s_marked_as_bad_on:
	dc.b	' Sector(s) marked as|BAD on Disk in Drive X:][ OK ]',0
str_ok_2:
	dc.b	'OK             ',0
	dc.b	'DMA Error      ',0
	dc.b	'Time-Out       ',0
	dc.b	'Write-Protected',0
	dc.b	'Lost Data      ',0
	dc.b	'RNF/Seek Error ',0
	dc.b	'Bad Checksum   ',0
alert_cannot_write_the_fats_retry:
	dc.b	'[1][Cannot write the FATs!| ][ RETRY | ABORT ]',0
fill_dotted:
	dc.w	$aaaa,$ffff
fill_grey:
	dc.w	$5555,$aaaa
fill_solid:
	dc.w	$ffff,$ffff
dd_step_rates:
	dc.w	$0002,$0003,$0000,$0001
hd_step_rates:
	dc.w	$0000,$0000,$0000,$0001
keys_format:
	dc.w	$0048,$0a00,$5008,$0148,$0d01,$500c,$0132,$0f01
	dc.w	$1410,$0118,$1101,$1912,$0120,$1500,$6116
	dc.b	$02
str_d_data_disk_undo_cancel_p_put:
	dc.b	'<D> Data Disk  <Undo> Cancel|<P> Put Guardian...|Predefined '
	dc.b	'Config.:|<O> Optimized  <M> MS-DOS|<T> TOS@Edit Config.:|</>'
	dc.b	' Dir. Entries +16|<*> Dir. Entries -16|<Shift>-</> FAT Secto'
	dc.b	'rs +16|<Shift>-<*> FAT Sectors -16',0
underlines_format:
	dc.w	$1350,$0600
keys_error:
	dc.w	$0013,$0200,$2e03,$0030,$0400,$3105,$0061,$0602
str_c_continue_b_best_match_n:
	dc.b	'<c> Continue|<b> Best Match|<n> Retry with New Disk |<r> Do '
	dc.b	'a Retry|<Undo> Abort',0
str_formatting_2:
	dc.b	'Formatting',0
format_layouts:
	dc.w	$0202,$0700,$0203,$0700,$0107,$0e00,$0109,$0e00
format_layouts_hd:
	dc.w	$0205,$0700,$0206,$0e00,$0205,$0e00
alert_sector:
	dc.b	'[1][Sector ',0
str_is_damaged:
	dc.b	' is damaged|',0
str_and_free_mark_bad:
	dc.b	'and free!][ MARK BAD ]',0
str_but_used_noticed:
	dc.b	'but used!][ NOTICED ]',0
boot_sector_start:
	dc.w	$eb34,$9049,$424d,$2020
str_soft_formatting:
	dc.b	'Soft Formatting',0
str_bytes_available:
	dc.b	' Bytes available',0
str_star_dot_star:
	dc.b	$2a,$2e,$2a,$00
alert_the_floppy_head_has_reached:
	dc.b	'[3][The floppy head|has reached Track 0!  ][ ABORT ]',0
alert_the_floppy_head_has_not:
	dc.b	'[3][The floppy head has|NOT reached Track 0!  ][ ABORT ]',0
alert_write_error_on_track_format:
	dc.b	'[2][Write Error on Track!|Format it and try again?][ YES | N'
	dc.b	'O ]',0
str_side:
	dc.b	'Side',0
str_track:
	dc.b	'Track',0
str_status:
	dc.b	'Status:',0
alert_cannot_read_disk:
	dc.b	'[1][Cannot read|Disk-Configuration!][ ABORT ]',0
alert_interruption_abort_cont:
	dc.b	'[3][  Interruption!][ ABORT | CONT ]',0
alert_formatting_is_now_on_ok:
	dc.b	'[1][Formatting is now ON.][ OK ]',0
alert_formatting_is_now_off_ok:
	dc.b	'[1][  Formatting is now OFF.][ OK ]',0
alert_read_error_on_partition_x:
	dc.b	'[1][Read Error on Partition X:][ RETRY | CONT | ABORT ]',0
alert_write_error_on_partition_x:
	dc.b	'[1][Write Error on Partition X:][ RETRY | CONT | ABORT ]',0
str_reading_drive_x:
	dc.b	'Reading Drive X:',0
str_writing_drive_x:
	dc.b	'Writing Drive X:',0
str_calculating:
	dc.b	'Calculating',0
alert_x_source_disk:
	dc.b	'[0][  X: Source Disk #',0
alert_x_destination_disk:
	dc.b	'[0][  X: Destination Disk #',0
str_of_max_xx_disks_copy_abort:
	dc.b	'  |     of max. XX Disks| ][ COPY | ABORT ]',0
alert_the_data_of_partition_x_has:
	dc.b	'[0][  The data of Partition X:  |  has been compacked into| '
	dc.b	' XX% of its original size.][ GREAT! ]',0
str_part_x_12:
	dc.b	'PART_X  #12',0
alert_not_enough_memory_free_for_2:
	dc.b	'[1][Not enough memory free |for working with the|Streamer fu'
	dc.b	'nction!][ ABORT ]',0
alert_without_optimized_writing_the:
	dc.b	'[1][Without optimized Writing |the Destination Partition|is '
	dc.b	'too small!|Switch to the optimized|mode or abort?][ SWITCH |'
	dc.b	' ABORT ]',0
alert_destination_partition_is_too:
	dc.b	'[1][Destination Partition is |too small! Write back|as much '
	dc.b	'as possible?][ OK | ABORT ]',0
alert_the_disk_you_have_inserted:
	dc.b	'[1][The Disk you have inserted|already contains data of this'
	dc.b	'|Backup and should not be used|again! Insert another Disk,|c'
	dc.b	'ontinue or abort.][ OTHER | CONT | ABORT ]',0
str_select_destination_partition:
	dc.b	'Select Destination Partition',0
alert_read_from_partition_or_write:
	dc.b	'[2][Read from Partition|or write to Partition?][ READ | WRIT'
	dc.b	'E | CANCEL ]',0
str_select_source_partition:
	dc.b	'Select Source Partition',0
alert_source_and_destination:
	dc.b	'[3][Source and Destination|Partition have different|Sector s'
	dc.b	'izes!][ ABORT ]',0
alert_with_optimized_writing_fcopy:
	dc.b	'[2][With Optimized Writing|FCopy will only write|back the us'
	dc.b	'ed Sectors|of the Partition. Okay? ][ OK | ABORT ]',0
alert_destination_partition_is:
	dc.b	'[3][Destination Partition|is write-protected!][ STOP ]',0
str_updating_fat:
	dc.b	'Updating FAT...',0
str_updating_dirs:
	dc.b	'Updating Dirs...',0
	dc.b	$00
alert_x_source_disk_scan_abort:
	dc.b	'[0][ X: Source Disk| ][ SCAN | ABORT ]',0
str_alert_2:
	dc.b	'[2][',0
str_sectors_are_bad_mark_them_in:
	dc.b	' Sectors are bad.|Mark them in the FATs|or leave them untouc'
	dc.b	'hed? ][ MARK | LEAVE ]',0
str_previously_bad_marked_sectors:
	dc.b	'Previously bad-marked|sectors are now OK.|Update the FATs or'
	dc.b	' leave |them untouched?][ UPDATE | LEAVE ]',0
alert_x_source_disk_copy_abort:
	dc.b	'[0][ X: Source Disk| ][ COPY | ABORT ]',0
alert_x_destination_disk_copy_abort:
	dc.b	'[0][X: Destination Disk  | ][ COPY | ABORT ]',0
alert_x_source_disk_x_destination:
	dc.b	'[0][X: Source Disk|X: Destination Disk  | ][ COPY | ABORT ]',0
alert_x_destination_disk_2:
	dc.b	'[0][  X: Destination Disk #',0
str_copy_abort:
	dc.b	'   | ][ COPY | ABORT ]',0
str_copy_abort_last:
	dc.b	'| ][ COPY | ABORT | LAST ]',0
alert_output_a_report_of_the:
	dc.b	'[2][Output a report of the|damaged files to the|printer or t'
	dc.b	'o a file?|Please leave the scanned  |diskette in the drive!]'
	dc.b	'[ CANCEL | PRINTER | FILE ]',0
str_reading_2:
	dc.b	'Reading',0
str_writing_2:
	dc.b	'Writing',0
str_format_writing:
	dc.b	'Format. & Writing',0
str_a_fcopypro_tmp:
	dc.b	'A:\FCOPYPRO.TMP',0
alert_read_write_error_on_the:
	dc.b	'[1][READ/WRITE ERROR on the|Extended Memory (Drive X)!  ][ A'
	dc.b	'BORT ]',0
alert_read_write_error_on_the_disk:
	dc.b	'[1][READ/WRITE ERROR on|the Disk Image File! ][ ABORT ]',0
alert_the_disk_image_is_too_big_for:
	dc.b	'[1][The Disk Image is too big|for Drive X:!|Don''t use Extend'
	dc.b	'ed Memory but |proceed or abort function?][ PROCEED | ABORT '
	dc.b	']',0
	dc.b	$00
image_handle:
	dc.w	$ffff
alert_read_disk_image_and_write_it:
	dc.b	'[2][Read Disk Image and write|it to a file|or restore Disk I'
	dc.b	'mage from |a file and write it to|Destination Disk(s)?][ REA'
	dc.b	'D | RESTORE | ABORT ]',0
str_scanning_2:
	dc.b	'Scanning',0
str_output_scan_report_to:
	dc.b	'Output Scan Report to...',0
str_report_names:
	dc.w	$2a00
str_damaged_file_report_path:
	dc.b	'Damaged File Report',10,13
	dc.b	'Path & Filename                                   Damaged Se'
	dc.b	'ctors   File Size',10,13,10,13,0
str_files_damaged:
	dc.b	' Files damaged.'
	dc.w	$0c00
str_read_image:
	dc.b	'Read Image',0
str_restore_image:
	dc.b	'Restore Image',0
str_converting:
	dc.b	'Converting',0
str_copying:
	dc.b	'Copying',0
str_restore_image_from_file:
	dc.b	'Restore Image from File...',0
str_write_image_to_file:
	dc.b	'Write Image to File...',0
str_dim:
	dc.b	'DIM',0
alert_please_select_a_partition_ok:
	dc.b	'[1][Please select a Partition! ][ OK ]',0
str_dim_2:
	dc.b	'.DIM',0
alert_cannot_access_the_selected:
	dc.b	'[1][Cannot access the|selected file.|Please choose again!][ '
	dc.b	'OK | ABORT ]',0
alert_the_selected_file_does_not:
	dc.b	'[1][The selected file does|not contain a Disk Image. |Please'
	dc.b	' choose again!][ OK | ABORT ]',0
alert_do_you_want_to_use_the:
	dc.b	'[2][Do you want to use|the settings of the|Disk-Configuratio'
	dc.b	'n-Box?][ YES | NO ]',0
alert_file_already_exists_overwrite:
	dc.b	'[2][File already exists.|Overwrite it?][ YES | NO ]',0
alert_partition_has_not_enough:
	dc.b	'[3][Partition has not enough |space left for storing|the Dis'
	dc.b	'k Image!][ STOP ]',0
alert_destination_disk_is_too_small:
	dc.b	'[2][Destination Disk is too small!|Copy as much as possible?'
	dc.b	'][ COPY | ABORT ]',0
str_saving:
	dc.b	'Saving...',0
	dc.b	$00
str_fastcopy_pro:
	dc.b	'  FastCopy PRO',0
alert_somebody_overwrote_important:
	dc.b	'[3][Somebody overwrote important|messages in FastCopy PRO!|P'
	dc.b	'lease restore it to the|original code and try again!|][ OK ]',0
str_fastcopy_pro_1_2_by_martin:
	dc.b	'>> FastCopy PRO 1.2 << by Martin Backschat, Bergstra',$9e
	dc.b	'e 16, D-85120 Hepberg // (c) 1986-94 Martin Backschat',0
ted_00_text:
	dc.b	$af,' FastCopy PRO 1.2 ',$ae,'    --    ',$bd
	dc.b	' 1986-94 by Martin Backschat / ICP / ACN',0
about_03_text:
	dc.b	'Version 1.2',0
about_04_text:
	dc.b	'Concept, Design & Development',0
about_05_text:
	dc.b	'Martin Backschat',0
about_06_text:
	dc.b	$bd,' Copyright 1994 by',0
about_07_text:
	dc.b	'    Martin Backschat',0
alert_fastcopy_pro_does_not_support:
	dc.b	'[3][FastCopy PRO does not|support this resolution!][ QUIT ]',0
alert_fastcopy_pro_needs_at_least:
	dc.b	'[3][FastCopy PRO needs at|least about 40 KByte|of free memor'
	dc.b	'y!][ QUIT ]',0
underlines_main:
	dc.b	$20,$76,$1f,$24,$66,$1f,$27,$72,$1f,$29,$6d,$1f,$2a,$67,$1f
	dc.b	'7s5Id5"t'
	dc.w	$1f00
keys_main:
	dc.w	$003b,$0900,$3c0a,$003d,$0b00,$3e0c,$0061,$1200
	dc.w	$3f0d,$0040,$0e00,$410f,$0042,$1000,$4311,$0044
	dc.w	$1200,$1e2f,$0030,$3001,$1e33,$0130,$3400,$2125
	dc.w	$002f,$2100,$1326,$0113,$2700,$3228,$0018,$4a00
	dc.w	$394a,$0022,$2b00,$1f38,$0020,$4700,$1423,$0154
	dc.w	$1601,$5518,$0156,$1a01,$571c,$0158,$1e01,$0215
	dc.w	$0103,$1701,$0419,$0105,$1b01,$061d,$002e,$4b02
str_f1_copy_f6_new_conf_f2_scan:
	dc.b	'<F1> Copy     <F6> New Conf.|<F2> Scan     <F7> Inspect|<F3>'
	dc.b	' Format   <F8> Soft Fmt. |<F4> Streamer <F9> Image|<F5> Dir.'
	dc.b	'     <F10> Quit@<o>,<Space> More Options|        <c> Save Co'
	dc.b	'nfig.|<s> Sides     <d> Density|<a>,<b> Source Drive A or B '
	dc.b	'|<A>,<B> Dest. Drive A or B@<Shift><F1..5> Preset 1..5|<Shif'
	dc.b	't><1..5>  Set Preset 1..5 ',0
str_status_empty:
	dc.b	$00
str_kb:
	dc.b	'KB',0
str_select_option:
	dc.b	'Select Option!',0
alert_read_disk_configuration_from:
	dc.b	'[0][Read Disk Configuration  |from Drive X:| ][ READ | ABORT'
	dc.b	' ]',0
	dc.b	$00
fill_lines:
	dc.w	$0000,$ffff
window_open:
	dc.b	$00
no_hard_disk:
	dc.b	$00
alert_bell:
	dc.b	$01
mouse_accel_ok:
	dc.b	$01
