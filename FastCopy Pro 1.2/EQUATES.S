; EQUATES.S  -  equates for FCOPYPRO.S, included at its start
;
; GEM object types, flags, states and field offsets for the resource, the DMA/FDC
; registers relative to $ffff8600 and the fields of fdc_state, the BPB copy, the
; Dfree buffer and the DTA.

; GEM object types, flags, states and field offsets used by the resource
G_BOX	equ	20
G_TEXT	equ	21
G_BOXTEXT	equ	22
G_IMAGE	equ	23
G_USERDEF	equ	24
G_IBOX	equ	25
G_BUTTON	equ	26
G_BOXCHAR	equ	27
G_STRING	equ	28
G_FTEXT	equ	29
G_FBOXTEXT	equ	30
G_ICON	equ	31
G_TITLE	equ	32

SELECTABLE	equ	$1
DEFAULT	equ	$2
EXIT	equ	$4
EDITABLE	equ	$8
RBUTTON	equ	$10
LASTOB	equ	$20
TOUCHEXIT	equ	$40
HIDETREE	equ	$80

SELECTED	equ	$1
CROSSED	equ	$2
CHECKED	equ	$4
DISABLED	equ	$8
OUTLINED	equ	$10
SHADOWED	equ	$20

ob_next	equ	0
ob_head	equ	2
ob_tail	equ	4
ob_type	equ	6
ob_flags	equ	8
ob_state	equ	10
ob_spec	equ	12
ob_x	equ	16
ob_y	equ	18
ob_width	equ	20
ob_height	equ	22

te_ptext	equ	0
te_ptmplt	equ	4
te_pvalid	equ	8
te_font	equ	12
te_just	equ	16
te_color	equ	18
te_thickness	equ	22
te_txtlen	equ	24
te_tmplen	equ	26
OBJECT_SIZE	equ	24

; DMA and FDC registers relative to $ffff8600
fdc_access	equ	$4
dma_mode	equ	$6
dma_high	equ	$9
dma_mid	equ	$b
dma_low	equ	$d
fdc_density	equ	$e

; floppy driver state (fdc_state)
fs_count	equ	$0
fs_id_offsets	equ	$2
fs_sector_order	equ	$30
fs_interleave	equ	$5e
fs_skew	equ	$60
fs_unit	equ	$62
fs_track	equ	$64
fs_head_track	equ	$66
fs_step_rate	equ	$68
fs_sides	equ	$6a
fs_sectors	equ	$6c
fs_side	equ	$6e
fs_drive	equ	$70
fs_track_a	equ	$72
fs_track_b	equ	$74
fs_density	equ	$76
fs_saved_ssp	equ	$78
fs_order_ptr	equ	$7c
fs_dma_stop	equ	$80
fs_extra_ids	equ	$84
fs_long_track	equ	$85
fs_split_sector	equ	$86
fs_split_offset	equ	$88
fs_saved_bytes	equ	$8a

; Dfree buffer (dfree_info) and DTA (dta)
b_free	equ	$0
b_total	equ	$4
b_secsiz	equ	$8
b_clsiz	equ	$c
d_attrib	equ	$15
d_time	equ	$16
d_date	equ	$18
d_length	equ	$1a
d_fname	equ	$1e

; BPB copy (bpb)
bpb_recsiz	equ	$0
bpb_clsiz	equ	$2
bpb_clsizb	equ	$4
bpb_rdlen	equ	$6
bpb_fsiz	equ	$8
bpb_fatrec	equ	$a
bpb_datrec	equ	$c
bpb_numcl	equ	$e
bpb_bflags	equ	$10
