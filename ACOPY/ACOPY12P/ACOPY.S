; ACOPY.PRG  -  copy ST v1.2p  (Eurosystems 1988, written by Uwe Stahl)
; Disassembly in Devpac syntax.  Text 20030 bytes, data 1438 bytes, bss 20602 bytes.
;
; This is the original uncracked version with it's own protection still intact.
;
; Assembled with Devpac this source reproduces ACOPY.PRG byte for byte except that
; the original file lacks the $00 byte terminating its relocation table (it ends
; on the last relocation entry), so the Devpac output is one byte longer.
;
;=======================================================================
; WHAT IT IS
;=======================================================================
; A GEM disk copier for the Atari ST with two modes:
;
;  Normal ("Norm"): the source BPB is read with Getbpb, boot sector and FATs are
;   read with Rwabs, a usage map is built from the 12-bit FAT, and only the used
;   sectors are read (Read Sector) into a big Malloc'd buffer and written back
;   with Write Sector.  Sectors that consist of a single byte value are not
;   stored (one flag byte in the map instead).  The target can be formatted on
;   the fly (Write Track with a generated track image) and verified.
;
;  Protected ("Prot"): every track is read raw and rebuilt on the target with
;   Write Track, including the things the FDC normally hides: sync marks in
;   data, odd sector sizes, duplicate sector IDs, deleted data marks, bad CRCs,
;   long tracks, fuzzy (weak) bits and sectors written out of byte alignment.
;   How this works is described below under "track-write scripts" and "tricks".
;
;  The program is itself protected: a key disk check on track 80 and several
;   checks of its own copyright string (see "key disk and anti-tamper").
;
;=======================================================================
; HOW TO READ THIS FILE
;=======================================================================
; - Every routine and variable has been named from its behaviour.  Names of the
;   form dat_xxxx / loc_xxxx are the few places with no better name; xxxx is
;   the offset in the text segment of the original program.
; - "; from: a, b" after a label lists the routines (or data tables) that refer
;   to that label.  It is derived from the original binary and is documentation
;   only; Devpac ignores it.  Labels referenced only from inside their own
;   routine carry no note.
; - Comments on trap calls give the GEMDOS/BIOS/XBIOS function, comments on
;   bsr aes_call / vdi_call give the AES/VDI function, and writes to (a6) and
;   2(a6) are annotated with the FDC command or DMA mode they select.
; - Register conventions in the disk code: a4 -> disk_params (fields are the
;   dp_* equates below), a5 = PSG ($ff8800), a6 = FDC/DMA ($ff8604),
;   d7 = FDC status / error bits.  In the script code a0 = write position in
;   the track image, a2 = script pointer.
; - All FDC access goes through the DMA chip: 2(a6) selects the register
;   ($80 = command/status, $82 = track, $84 = sector, $86 = data, $90 = sector
;   count, +$100 = write direction) and (a6) reads or writes it.  Command
;   completion is polled on MFP GPIP bit 5 (low = FDC interrupt).  The DMA
;   address counter at $ff8609/b/d is read back to find out how far the FDC
;   has got through a track; that counter is the program's "position on the
;   track" in nearly all of the timing tricks.
;
;=======================================================================
; THE DIALOG (ACOPY.RSC)
;=======================================================================
; The object numbers below are the ones used in the code (form_do returns the
; exit object in d3, objc_change is called with the object in d3).  The names
; in the third column are used in the comments.
;
; Tree 0: main dialog (tree_main)
;    0 BOX  [SHADOWED]
;      1 BOXTEXT  TITLE        "  copy ST  (v 1.2p)  (c)  Eurosystems 1988 "  [SELECTABLE DEFAULT EXIT SHADOWED]
;      2 BOX  [SHADOWED]
;        3 BOXTEXT               "General parameters"  [SHADOWED]
;        4 STRING                "Source:"
;        5 BOX  [OUTLINED SHADOWED]
;          6 BOXCHAR  SRC_A        'A'  [SELECTABLE RBUTTON SELECTED]
;          7 BOXCHAR  SRC_B        'B'  [SELECTABLE RBUTTON]
;        8 STRING                "Target:"
;        9 BOX  [OUTLINED SHADOWED]
;         10 BOXCHAR  TGT_A        'A'  [SELECTABLE RBUTTON]
;         11 BOXCHAR  TGT_B        'B'  [SELECTABLE RBUTTON SELECTED]
;       12 STRING                "Verify:"
;       13 BOX  [OUTLINED SHADOWED]
;         14 BUTTON   VERIFY_YES   "Yes"  [SELECTABLE RBUTTON SELECTED]
;         15 BUTTON   VERIFY_NO    "No"  [SELECTABLE RBUTTON]
;       16 STRING                "Multiple:"
;       17 BOX  [OUTLINED SHADOWED]
;         18 BUTTON   MULTI_YES    "Yes"  [SELECTABLE RBUTTON]
;         19 BUTTON   MULTI_NO     "No"  [SELECTABLE RBUTTON SELECTED]
;       20 STRING                "Format:"
;       21 BOX  [OUTLINED SHADOWED]
;         22 BUTTON   FORMAT_YES   "Yes"  [SELECTABLE RBUTTON SELECTED]
;         23 BUTTON   FORMAT_NO    "No"  [SELECTABLE RBUTTON]
;       24 STRING                "Mode:"
;       25 BOX  [OUTLINED SHADOWED]
;         26 BUTTON   MODE_NORM    "Norm"  [SELECTABLE RBUTTON TOUCHEXIT SELECTED]
;         27 BUTTON   MODE_PROT    "Prot"  [SELECTABLE RBUTTON TOUCHEXIT]
;     28 BOX  [SHADOWED]
;       29 BOXTEXT               "Format parameters"  [SHADOWED]
;       30 STRING                "Sectors:"
;       31 BOX  [OUTLINED SHADOWED]
;         32 BOXCHAR  SECT_9       '9'  [SELECTABLE RBUTTON TOUCHEXIT SELECTED]
;         33 BUTTON   SECT_10      "10"  [SELECTABLE RBUTTON TOUCHEXIT]
;         34 BUTTON   SECT_11      "11"  [SELECTABLE RBUTTON TOUCHEXIT]
;       35 STRING                "Inter:"
;       36 BOX  [OUTLINED SHADOWED]
;         37 BOXCHAR  INTER_1      '1'  [SELECTABLE RBUTTON SELECTED]
;         38 BOXCHAR  INTER_6      '6'  [SELECTABLE RBUTTON]
;       39 BOX
;         40 BOXTEXT               "Format + Prot. parameters"  [SHADOWED]
;         41 STRING                "Sides:"
;         42 BOX  [OUTLINED SHADOWED]
;           43 BOXCHAR  SIDES_1      '1'  [SELECTABLE RBUTTON]
;           44 BOXCHAR  SIDES_2      '2'  [SELECTABLE RBUTTON SELECTED]
;         45 STRING                "Start:"
;         46 BOX  [OUTLINED SHADOWED]
;           47 BOXCHAR  START_DOWN   char 2 (arrow)  [TOUCHEXIT]
;           48 BOX
;             49 STRING   START_TEXT   "00"
;           50 BOXCHAR  START_UP     char 1 (arrow)  [TOUCHEXIT]
;         51 STRING                "End:"
;         52 BOX  [OUTLINED SHADOWED]
;           53 BOXCHAR  END_DOWN     char 2 (arrow)  [TOUCHEXIT]
;           54 BOX
;             55 STRING   END_TEXT     "81"
;           56 BOXCHAR  END_UP       char 1 (arrow)  [TOUCHEXIT]
;     57 BOXTEXT  INFO         "Info"  [SELECTABLE EXIT SHADOWED]
;     58 BOX  [OUTLINED SHADOWED]
;       59 STRING   WAITING_TEXT " Waiting "
;       60 STRING   DRIVE_TEXT   "Drive:    Side:    Track:   "
;     61 BOXTEXT  COPY         "Copy"  [SELECTABLE EXIT SHADOWED]
;     62 BOXTEXT  FORMAT       "Format"  [SELECTABLE EXIT SHADOWED]
;     63 BOXTEXT  EXIT         "Exit"  [SELECTABLE EXIT SHADOWED]
;
; Tree 1: about box (tree_about)
;    0 BOX  [SHADOWED]
;      1 BOX  [SHADOWED]
;        2 STRING                " copy ST was written in 1987"
;        3 STRING                "by Uwe Stahl"
;        4 STRING                "for EUROSYSTEMS Holland."
;        5 STRING                "Special thanks to Stefan Poltnigg / Austria"
;      6 BOXTEXT  ABOUT_OK     "OK"  [SELECTABLE DEFAULT EXIT SHADOWED]
;
; Tree 2: blank box (tree_blank)
;    0 BOX
;
; Tree 3: BIOS parameter block info (tree_bpb)
;    0 BOX  [SHADOWED]
;      1 BOX  [SHADOWED]
;        2 BOXTEXT               "BIOS parameter block"  [SHADOWED]
;        3 STRING                "Bytes pro record:      512"
;        4 STRING                "Records pro cluster:     2"
;        5 STRING                "Bytes pro cluster:    1024"
;        6 STRING                "Directory records:       7"
;        7 STRING                "FAT records:             5"
;        8 STRING                "FAT copy:                6"
;        9 STRING                "First data cluster:     18"
;       10 STRING                "Data clusters:         711"
;       11 STRING                "Number of sides:         2"
;       12 STRING                "Tracks pro side:        80"
;       13 STRING                "Sectors pro track:      10"
;       14 STRING                "Interleave:              1"
;     15 BOXTEXT  BPB_OK       "OK"  [SELECTABLE DEFAULT EXIT SHADOWED]
;
;=======================================================================
; PROTECTED MODE: HOW A TRACK GOES FROM SOURCE TO TARGET
;=======================================================================
; Read pass (copy_disk_protected, one track at a time, as many tracks as fit
; in the buffer):
;  1. fdc_read_track reads the raw track (including gaps, sync and marks) into
;     track_buf.  While it runs, read_track_find_index samples the DMA address
;     counter and watches for the index pulse, so the program learns where the
;     index is relative to the data and how long the track is (over-long and
;     unformatted tracks are flagged).
;  2. read_ids_timed issues Read Address again and again and records, for each
;     ID field, the FDC status and the time since the index (id_fields holds
;     the 6 ID bytes, sector_buf the status/time pairs).  drive_speed, measured
;     once per copy from the DMA count between two index pulses, converts time
;     into bytes.
;  3. scan_track_sectors walks the raw track matching the timed IDs to the
;     $a1 $a1 $fe marks it finds (find_next_id tolerates a window because the
;     timing is approximate), then looks for each data mark.  The result is
;     sector_list, 18 bytes per sector:
;        +0  flags: bit0 duplicate ID, bit1 data mark found, bit2 fuzzy bits,
;            bit3 read error, bit4 no data field, bit5 data mark not $fb,
;            bit7 sync bytes inside the ID; $ff = ID not matched in the buffer
;        +1  ordinal among duplicate IDs (or fuzzy position / 16)
;        +2  track, side, sector, size code       +6 CRC of the ID
;        +8  gap start   +$a ID offset   +$c data offset   +$e data length
;        +$10 ID mark byte   +$11 data mark byte
;  4. calc_sector_gaps works out the gap lengths, choose_gap_size picks the
;     gap to generate, mark_special_sectors flags IDs containing $f5..$f7 and
;     numbers duplicate IDs, and read_track_sectors reads the data of every
;     sector with Read Sector (duplicates with read_sector_timed, which starts
;     the read at a chosen time after the index so the right copy is hit).
;     Sectors that give a CRC error are read again and compared
;     (detect_fuzzy_sector): if two reads differ the sector has fuzzy bits.
;  5. The known schemes are detected (detect_scheme_*, rebuild_track79, the
;     Kaiser/STARTER/$0b09 signatures) and emit_track_script writes a
;     track-write script for the track into the copy buffer.
;
; Write pass (prot_write_pass): for each script write_track_from_script runs
; part 1 to build the track image, issues Write Track, optionally creates fuzzy
; bits, then runs part 2 which writes and verifies the awkward sectors
; individually.  Up to three attempts per track.
;
;=======================================================================
; TRACK-WRITE SCRIPTS
;=======================================================================
; A script is a small byte-code program, one per track, stored in the copy
; buffer in place of the track.  The program does not keep the raw track;
; it keeps a recipe for rebuilding it, which is why a whole disk of
; protected tracks fits in memory.
;
; Script header (at buffer_ptr):
;   +0 .w  length of part 1 (for raw scripts: number of longs - 1)
;   +2 .w  total length (raw scripts only)
;   +4 .w  total length, used by advance_script to step to the next script
;   +6 .l  handler: script_build_image (normal) or script_copy_raw_image
;          (the whole 6400-byte image stored as is)
;   +$a    part 1 items ... ending with opcode $2c
;          part 2 items ... ending with opcode $34
;
; Items: the first byte is the opcode, always a multiple of 4 because it is
; used directly as the index into opcode_table (30 entries).  The second byte
; of the opcode word usually is the first parameter.  script_dispatch loads the
; opcode byte at (a2) and jumps to the handler; the handler reads its own
; parameters from (a2)+, writes bytes to the image at (a0)+ and jumps back to
; script_dispatch.  The two end opcodes return to the caller with d0 = 0, an
; error returns d0 = -1 (or 1).
;
; Part 1 ("build") produces the track image in track_buf.  Part 2 ("verify")
; runs after Write Track and uses the FDC directly: it writes individual
; sectors with special timing and reads sectors back to check them.  Both
; parts are written by emit_track_script (part 2 is built at buffer+$2000 and
; appended afterwards, see emit_finish_script).
;
; Opcodes (parameters follow the opcode byte):
;   $00 sync+mark+fill    second byte = mark, .w length, .w first byte: writes
;                         byte, $f5 $f5, mark|$f0 then a data body as for $18
;   $04 fill words        .w value: d0+1 copies of the word (d0 from before)
;   $08 gap+literal       second byte <> 0: 16 x $4e first; .w n-1, n bytes
;   $0c special sectors   second byte = count*4: sectors whose ID holds sync
;                         bytes are written one by one with Write Sector,
;                         bit-shifted (see tricks); each is followed by a $40
;   $10 skip              one byte
;   $14 fill $e5          .w count
;   $18 data field        second byte = flags|mark low nibble: bit7 data
;                         follows (else zeros), bit6 no 2 trailing zeros,
;                         bit5 fill with one byte (.w), bit4 append $f7 (CRC);
;                         .w length; three $f5 then mark|$f0, then the data
;   $1c fix mark bytes    .w, .w: if a sync byte ended up in an ID, patch the
;                         last bytes; $ffff -> put $a1 8 bytes back
;   $20 ID field          second byte = mark, 4 ID bytes: three $f5, mark, ID,
;                         then the CRC code taken from the key disk ($f7)
;   $24 write+verify      (part 2) second byte = flags, .b track, .b sector,
;                         .w length, data: Write Sector (bit5 deleted mark, bit3 timed
;                         start, bit1 no read-back, bit2 read twice and expect
;                         differences = fuzzy), up to 5 attempts
;   $28 gap               second byte = count of $4e then 12 zeros; count 0:
;                         run list of (count,value) words, value $ff inverted
;   $2c end of part 1
;   $30 timed sector      (part 2) .b count, .b sector, .b track, .w length,
;                         data: Write Sector started a fixed delay after the
;                         index pulse, count times, two passes
;   $34 end of part 2
;   $38 long gap          .w count of $4e, then 12 zeros
;   $3c nop               as $10
;   $40 check special     (part 2) after a $0c sector: read the track back,
;                         note track/sector written, write the gap before the
;                         next ID with Write Track aborted at the right place
;   $44 ID $ff            ID with track $ff sector = special count, placed 60
;                         bytes back; used to park a special sector
;   $48 ID zero           ID 0/0/0/0 placed 44 bytes back
;   $4c verify sectors    (part 2) second byte = count-1, (sector,track) pairs:
;                         read each, any error fails the track
;   $50 ID $ff/1/3        .w offset: ID $ff 0 1 3 (1024-byte sector) at offset
;   $54 shifted sector    (part 2) .w length, data: the data is shifted one bit
;                         and written with Write Sector exactly when the DMA
;                         counter reaches a computed position, then the track
;                         is read back and compared
;   $58 fuzzy marker      marks the image position where fuzzy bits go
;                         (fuzzy_pos) and which sector to verify, then an ID
;   $5c long track prep   .l sector:track: prepare a track longer than one
;                         revolution ($4e then $d3 $93 $93 ... pattern)
;   $60 long track write  (part 2) write the long track in pieces aligned on
;                         the DMA counter, then write the sector and verify
;   $64 RLE data          run-length encoded bytes: (count,value) pairs, count
;                         0 = literal block (.w length, bytes), (0,0) = end
;   $68 ID current track  second byte = sector: ID with the current track and
;                         side and size code 2
;   $6c partial write     (part 2) Write Track aborted after $82 bytes: puts a
;                         write splice right after the first ID
;   $70 sync read         (part 2) Read Track until the bytes $14 $0b are seen
;                         in the first 65 bytes, re-writing the track between
;                         tries (synchronises the track start to the index)
;   $74 fuzzy params      .b gap, .b offset: as $58 with explicit values
;
;=======================================================================
; TRICKS USED TO REPRODUCE PROTECTIONS
;=======================================================================
; The WD1772 can only write what Write Track lets it: $f5 becomes an $a1 sync
; byte, $f6 a $c2 sync byte, $f7 writes a CRC, and $f8..$ff are reserved, so
; those values cannot appear as data.  Protections exploit exactly that.  What
; the program does about it:
;
; - Sync bytes inside sector data: copy_raw_sector and fix_sync_bytes turn
;   $a1 $a1 and $c2 $c2 $c2 runs back into $f5/$f6 so Write Track regenerates
;   them, and a data field is closed with $f7 so the CRC comes out right.  A
;   sector that still cannot be written this way is written separately with
;   Write Sector in part 2.
; - Sectors whose ID contains $f5..$f7 ("special"): opcode $0c writes them with
;   Write Sector after the track exists.  Because Write Sector lets the FDC add
;   its own marks, the data is first shifted one bit with roxr (shift_sector_
;   buf), i.e. the sector is written out of byte alignment; Write Sector is
;   started when the DMA counter shows the head is at the right place and is
;   ended by deselecting the drive through PSG port A (the FDC loses the
;   drive and stops writing).  Up to 18 attempts, adjusting write_delay from
;   the number of IDs still readable afterwards.
; - Fuzzy (weak) bits: write_fuzzy_bits re-issues Write Track, waits for the
;   DMA counter to reach fuzzy_pos and then toggles the drive-select line 128
;   times in a tight loop.  The interrupted write gate leaves bits that read
;   differently each time.  The sector is then read three times and must
;   differ in the first 16 bytes.
; - Precisely placed sectors (opcodes $24 bit 3, $30, $54, timed_write_sector):
;   Force Interrupt $d4 raises the FDC interrupt on the index pulse; the code
;   waits for it, then counts DMA address nibbles up to the wanted position,
;   delays (delay_count), starts Write Sector and ends it by deselecting the
;   drive.  op_30 does this a fixed number of times per revolution to create
;   the duplicate-ID sectors.
; - Tracks longer than a revolution: op_5c/op_60 write the image in pieces,
;   each Write Track being started with its DMA address adjusted so the data
;   lands where the previous piece ended (long_track_pos).
; - Duplicate sector IDs on the read side: read_sector_timed starts Read Sector
;   a computed delay after the index so the wanted copy of the ID is the first
;   one the FDC sees.  The timing (op_30 items) is measured with
;   emit_dup_sector_timing by counting how many Read Sector commands complete
;   after the index before a timeout (one per copy of the ID).
; - Deleted data marks ($f8), IDs with bad CRC (the stored CRC is written as
;   data by emit_id_with_crc instead of $f7), missing data fields, 128/256/
;   1024 byte sectors, sector numbers $ff, a 1024-byte sector hidden in the
;   gap (op_50), data that runs through the index (the last sector's data is
;   written over the start of the track).
; - Known schemes handled explicitly: the track 79 scheme with sectors 1..6,
;   $f5 and a checksum of the track (rebuild_track79 rewrites the whole track
;   from constants), the "Kaiser" signature, the $0b09 signature, the
;   $a1a1 $00fd signature (detect_a1a1_scheme) and tracks with exactly one
;   duplicated sector.  Gaps are generated, not copied, except for the parts
;   that carry odd bytes.
; - When the floppy is idle a VBL handler (vbl_deselect_drives) deselects both
;   drives so that nothing is written by accident while the select line is
;   being used as a write gate.
;
;=======================================================================
; PATCHES APPLIED TO THE COPIED DATA (the naughty part)
;=======================================================================
; Some checks cannot be satisfied by any copy, so the program recognises the
; checking code inside the sector data as it is read and rewrites it.  The
; copy then contains cracked code.  The patterns are stored as data (pat_*)
; and in the comparison routines:
;
; - patch_timing_loops: loops that measure the disk with the 200 Hz timer,
;   move.l $4ba.w,d3 / move.w d3,(a0)+ / dbra ... / rts (and the absolute-long
;   and d0 forms), become move.w #$3535,d0 or d3 plus nop, so the check sees
;   a constant.  Run over the whole buffer when an unformatted track was seen,
;   and over the data of track 3 (patch_track3).
; - patch_cmp_sequence: on track 79, when the sector data starts with
;   $f0f1f2f3 $f4f5f6f7, the loop cmp.l $54(a4),d1 / bne / cmp.l $a8(a4),d1 /
;   bne / cmp.l (a4)+,d1 / bne / dbra has both bne instructions replaced by nop.
; - patch_branches: a bne.s +$20 that follows pat_cmpi_fb or pat_move_a1 code
;   is turned into bne.s -$e (loops back instead of failing); the word before
;   a bne.s +$7e next to pat_cmpi_a1 / pat_bset becomes $98fa.
; - patch_fffb_check: when a sector on track 2 contains sync bytes, the
;   buffer is searched for move.b -5(a0),d0 followed by pat_cmp_loop and
;   either two bytes are patched or a nop is inserted.
; - patch_boot_scheme_a / _b: the boot sector (track 0 sector 1) is compared
;   at the offsets in boot_a_offsets / boot_b_offsets and, if the original
;   bytes are there, replaced with boot_a_replace / boot_b_replace.  Follow-up
;   patches then hit sector $f5 of track 2 (scheme A) or of track 1 and track
;   6 (scheme B, where a beq.s at offset $2c2 becomes bra.s).  For both schemes
;   bit 4 is cleared in the track/sector numbers of every ID (f_fix_id_bit4),
;   so the copy's IDs differ from the original's by design.
; - patch_track2_sector2: clr.w $ff8240 / jmp $10000 at offset $82 of track 2
;   sector 2 becomes subq.w #2,$11752.
; - patch_track6_sector10: sub.l d0,$10c8 inside move.b (a2),(a0) / sub.l /
;   move.w #$1f40,d0 / dbra on track 6 sector 10 is replaced by three nops.
;
;=======================================================================
; KEY DISK AND ANTI-TAMPER
;=======================================================================
; - read_key_track runs at start-up: it seeks to track 80 and reads the raw
;   track into track_buf.  check_key_disk (before the first format or
;   protected copy) must find "E" + "UROSYSTEMS" in the first 81 bytes of that
;   buffer and an $f7 byte within the following 4K, otherwise it hangs forever
;   with interrupts off.  load_crc_from_key_track takes the two bytes used as
;   the CRC code in generated ID and data fields from that track at offset
;   $1000 (normally $f7 $f7), so without the key disk the generated tracks
;   have no valid CRCs.
; - The copyright string at copyright is read through relocated negative
;   offsets (lea copyright+n-k,an then move.l k(an),key_x) into key_ems,
;   key_euro, key_copyright and key_syst.  The bytes are compared one at a
;   time deep inside the disk routines; a mismatch jumps into the middle of
;   another routine, restarts the program or executes the key bytes.
; - verify_rsc_checksums (called whenever the drive is restored before an
;   operation) requires key_numn -
;   key_numm = 1 and XOR checksums of five resource strings (the title and
;   the about box lines) equal to rsc_checksums, otherwise it hangs.
; - While regenerating its own key track (track 80 with a 1024-byte sector)
;   the program writes "Hi Cracker! Try your best!!" into it (cracker_msg).
;
; disk_params (bss disk_params, usually addressed through a4)
dp_recsiz	equ	$00	; bytes per sector
dp_clsiz	equ	$02	; sectors per cluster
dp_clsizb	equ	$04	; bytes per cluster
dp_rdlen	equ	$06	; root directory length in sectors
dp_fsiz	equ	$08	; FAT size in sectors
dp_fatrec	equ	$0a	; first sector of second FAT
dp_datrec	equ	$0c	; first data sector
dp_numcl	equ	$0e	; number of clusters
dp_sides	equ	$10	; sides (TOS private BPB field)
dp_tracks	equ	$12	; tracks per side
dp_spt	equ	$14	; sectors per track
dp_interleave	equ	$16
dp_drive	equ	$18	; current drive (byte in low half)
dp_side	equ	$1a	; current side
dp_track	equ	$20	; current track
dp_shown_side	equ	$22	; side shown in the dialog
dp_shown_track	equ	$24	; track shown in the dialog
dp_sector	equ	$26	; current sector within track
dp_sector_idx	equ	$28	; running sector index over the whole disk
dp_resume_idx	equ	$2a	; index where the next read pass starts
dp_track_idx	equ	$2c	; index of the first sector of the current track
dp_end_idx	equ	$2e	; last index of the current pass
dp_saved_idx	equ	$30
dp_map_ptr	equ	$32	; pointer into the sector usage map
dp_first_sector	equ	$36	; first sector id (skew) when formatting
dp_total_sectors	equ	$38
dp_first_mark	equ	$3a	; offset of the first address mark after the index
dp_first_sync	equ	$3c	; offset of the first sync after the index
dp_num_sectors	equ	$3e	; sectors found on the raw track
dp_unused_8c	equ	$8c
dp_unused_8e	equ	$8e
dp_unused_90	equ	$90
dp_cur_track	equ	$98	; track being written in protected mode
dp_track_retries	equ	$a8
dp_sector_retries	equ	$aa
dp_src_warned	equ	$ba	; write-protect warning for the source already shown

	section	text

start:	; from: op_0c_write_special_sectors, script_add_sector, op_24_write_verify
	bra.s	prg_init

key_numm:	; from: verify_rsc_checksums
	dc.b	'numm'

;----------------------------------------------------------------------
; Program entry: switch to supervisor mode, shrink memory to text+data+bss+256,
; install an extra VBL handler (vbl_deselect_drives) by copying the system VBL queue
; into vbl_queue, switch off key click, run main, then restore everything and exit.
;----------------------------------------------------------------------
prg_init:	; from: start
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	move.l	d0,saved_ssp
	movea.l	sp,a5                           ; a5 = basepage
	lea	bss_end,sp                      ; stack at the end of the BSS
	movea.l	$4(a5),a5                       ; a5 = basepage address
	move.l	$c(a5),d0                       ; text + data + bss + 256
	add.l	$14(a5),d0
	add.l	$1c(a5),d0
	addi.l	#$100,d0
	move.l	d0,-(sp)
	move.l	a5,-(sp)
	move.w	d0,-(sp)
	move.w	#$4a,-(sp)
	trap	#1                              ; Mshrink
	lea	$c(sp),sp
	moveq	#7,d0                           ; copy 8 longs from _autopath/_vbl_list
	lea	$4ca.w,a0                       ; _autopath
	lea	vbl_queue,a1
	movea.l	a1,a2
copy_vbl_queue:
	move.l	(a0)+,(a1)+
	dbra	d0,copy_vbl_queue
	move.l	a2,$456.w                       ; _vblqueue = vbl_queue
	move.b	#$9,$455.w                      ; nvbls = 9
	bclr	#$0,$484.w                      ; conterm: key click off
	bsr.s	main
	move.l	buffer_start,d0
	beq.s	prg_exit
	move.l	d0,-(sp)
	move.w	#$49,-(sp)
	trap	#1                              ; Mfree
	addq.l	#6,sp
prg_exit:
	bset	#$0,$484.w                      ; conterm: key click on
	move.b	#$8,$455.w                      ; nvbls = 8
	move.l	#$4ca,$456.w                    ; _vblqueue = $4ca
	move.l	saved_ssp,-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
	clr.l	-(sp)
	trap	#1                              ; Pterm0

;----------------------------------------------------------------------
; AES trap: d0 = 200, d1 = parameter block
;----------------------------------------------------------------------
aes_trap:	; from: aes_call
	move.l	#aes_pb,d1
	move.w	#$c8,d0
	trap	#2                              ; AES
	rts


;----------------------------------------------------------------------
; VDI trap: d0 = 115, d1 = parameter block
;----------------------------------------------------------------------
vdi_trap:	; from: vdi_call
	move.l	#vdi_pb,d1
	moveq	#115,d0
	trap	#2                              ; VDI
	rts


; Copyright string.  Also used as an anti-tamper key: several routines read
; "(c) ", "EURO", "SYST", "EMS " and "UROSYSTEMS" from here through relocated
; negative offsets (lea copyright+n-k,an / move.l k(an),key) and compare them.
copyright:
	dc.b	'(c) EUROSYSTEMS / Donkerslooto'

;----------------------------------------------------------------------
; Main program: open GEM, load ACOPY.RSC, read the key track, run the dialog loop.
;----------------------------------------------------------------------
main:	; from: prg_init
	move.w	#$4,-(sp)
	trap	#14                             ; Getrez
	addq.l	#2,sp
	addq.w	#1,d0                           ; resolution = Getrez + 1
	move.w	d0,resolution
	bsr.w	gem_init
	bsr.w	get_desktop_area
	cmpi.w	#$1,resolution                  ; low resolution?
	bne.s	main_get_drive
	subq.w	#1,char_h_adj                   ; low resolution: text one pixel smaller
	lea	alert_resolution,a0             ; alert: use medium or high
	bsr.w	alert
	beq.s	exit_gem                        ; Cancel: leave
main_get_drive:
	move.w	#$19,-(sp)
	trap	#1                              ; Dgetdrv
	addq.l	#2,sp
	cmpi.b	#$2,d0                          ; drive < 2?
	bcs.s	loc_011e
	clr.l	d0                              ; otherwise drive A
loc_011e:
	move.w	d0,cur_drive
	bsr.w	load_resource
	tst.w	intout                          ; rsrc_load ok?
	bne.s	main_load_trees
	lea	alert_no_rsc,a0
	bra.s	alert_and_exit

alert_system_error:
	lea	alert_sys_error,a0
alert_and_exit:
	bsr.w	alert
exit_gem:
	bra.w	gem_exit

main_load_trees:
	moveq	#3,d3                           ; trees 3..0 -> tree_bpb .. tree_main
	lea	char_w,a3
load_tree_loop:
	bsr.w	get_tree
	beq.s	alert_system_error
	move.l	a0,-(a3)
	dbra	d3,load_tree_loop
	moveq	#-1,d0                          ; Malloc(-1) = largest free block
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	cmpi.l	#$10000,d0                      ; at least 64K
	bcs.s	alert_system_error
	subi.l	#$100,d0                        ; allocate all but 256 bytes
	move.l	d0,d4
	move.l	d0,-(sp)
	move.w	#$48,-(sp)
	trap	#1                              ; Malloc
	addq.l	#6,sp
	tst.l	d0
	bmi.s	alert_system_error
	lea	buffer_start,a0
	move.l	d0,(a0)+                        ; buffer_start
	add.l	d4,d0
	subi.l	#$100,d0
	move.l	d0,(a0)+                        ; buffer_end = start + size - 256
	subi.l	#$3900,d0                       ; buffer_limit = end - $3900
	move.l	d0,(a0)
	bsr.w	mouse_arrow
	movea.l	tree_main,a3
	move.w	$4a6.w,d3                       ; _nflops: one drive only?
	cmpi.b	#$2,d3
	bcc.s	main_cache_strings
	lea	single_drive_states,a4          ; disable the drive B buttons
disable_drive_b_loop:
	clr.l	d0
	move.b	(a4)+,d0
	beq.s	main_cache_strings
	bsr.w	get_ob_state                    ; a0 -> ob_flags
	move.b	(a4)+,$3(a0)                    ; set ob_state low byte
	bra.s	disable_drive_b_loop

main_cache_strings:
	lea	rsc_strings,a1
	moveq	#1,d0                           ; cache ob_spec of TITLE
	bsr.w	get_ob_spec
	move.l	(a0),(a1)+
	movea.l	tree_about,a3
	moveq	#2,d2                           ; about box objects 2..5
cache_string_loop:
	move.l	d2,d0
	bsr.w	get_ob_spec
	move.l	d0,(a1)+
	addq.l	#1,d2
	cmpi.b	#$5,d2
	ble.s	cache_string_loop
	bsr.w	read_key_track                  ; key disk: read track 80
main_draw_dialog:	; from: main_loop
	movea.l	tree_main,a4
	bsr.w	redraw_main_dialog
	lea	text_objects,a4
	lea	obj_text_table,a5
cache_text_pos_loop:
	clr.l	d0
	move.b	(a4),d0
	beq.s	main_calc_text_pos
	bsr.w	get_ob_spec                     ; cache text address
	move.l	d0,(a5)+
	clr.l	d0
	move.b	(a4)+,d0
	bsr.w	object_screen_pos               ; and screen position
	move.l	d0,(a5)+
	bra.s	cache_text_pos_loop

main_calc_text_pos:
	lea	drive_xy,a0
	move.l	drive_label_xy,d0               ; x,y of "Drive: Side: Track:"
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)
	swap	d0
	addi.w	#$38,d0                         ; drive_xy.x += $38
	move.w	d0,-$8(a0)
	addi.w	#$48,d0                         ; side_xy.x += $48
	move.w	d0,-$4(a0)
	addi.w	#$50,d0                         ; track_xy.x += $50
	move.w	d0,(a0)

;----------------------------------------------------------------------
; Dialog event loop: form_do returns the exit object in d3.
;----------------------------------------------------------------------
main_loop:	; from: button_track_arrows
	bsr.w	do_dialog
	cmpi.b	#$1a,d3                         ; MODE_NORM?
	bne.s	button_mode_prot
	moveq	#23,d3                          ; FORMAT_NO
	moveq	#23,d0                          ; FORMAT_NO disabled?
	bsr.w	get_ob_state
	btst	#$3,d0                          ; DISABLED bit
	beq.s	loc_026c
	bsr.w	deselect_object                 ; deselect FORMAT_NO
	moveq	#22,d3                          ; FORMAT_YES
	bsr.w	select_object                   ; select FORMAT_YES
loc_026c:
	bra.s	main_loop

button_mode_prot:
	cmpi.b	#$1b,d3                         ; MODE_PROT?
	bne.s	button_sectors_9
	moveq	#43,d3                          ; SIDES_1
	bsr.w	select_object                   ; select SIDES_1
	moveq	#44,d3                          ; SIDES_2
	bsr.w	deselect_object                 ; deselect SIDES_2
	moveq	#23,d0                          ; FORMAT_NO
	bsr.w	get_ob_state
	btst	#$3,d0                          ; FORMAT_NO disabled?
	bne.s	loc_029e
	moveq	#22,d3                          ; FORMAT_YES
	bsr.w	select_object                   ; select FORMAT_YES
	moveq	#23,d3                          ; FORMAT_NO
	bsr.w	deselect_object
	moveq	#8,d1                           ; state 8 = DISABLED
	bsr.w	change_object_state             ; disable FORMAT_NO
loc_029e:
	bra.s	main_loop

button_sectors_9:
	cmpi.b	#$20,d3                         ; SECT_9?
	bne.s	button_sectors_10_11
set_interleave_1:
	moveq	#37,d3                          ; INTER_1
	bsr.w	select_object                   ; select INTER_1
	moveq	#38,d3                          ; INTER_6
	bsr.w	deselect_object                 ; deselect INTER_6
	bra.s	main_loop

button_sectors_10_11:
	cmpi.b	#$21,d3                         ; SECT_10?
	beq.s	set_interleave_1
	cmpi.b	#$22,d3                         ; SECT_11?
	bne.s	button_title
	moveq	#38,d3                          ; INTER_6
	bsr.w	select_object                   ; select INTER_6
	moveq	#37,d3                          ; INTER_1
	bsr.w	deselect_object                 ; deselect INTER_1
	bra.w	main_loop

button_title:
	cmpi.b	#$1,d3                          ; TITLE (about box)?
	bne.s	button_info
	movea.l	tree_about,a4
	bsr.w	show_about_dialog
	bsr.w	do_dialog
	bsr.w	unselect_button_nodraw
	bra.w	main_draw_dialog

button_info:
	cmpi.b	#$39,d3                         ; INFO?
	bne.s	button_format
	bsr.w	read_settings
	bne.w	unselect_and_loop               ; Cancel
	bsr.w	read_source_bpb
	beq.s	show_bpb_dialog
	lea	alert_cannot_normal,a0          ; alert: cannot copy this disk
	bsr.w	alert
	bra.s	unselect_and_loop

show_bpb_dialog:
	bsr.w	unselect_button_nodraw
	movea.l	tree_bpb,a3
	bsr.w	fill_bpb_dialog
	movea.l	a3,a4
	bsr.w	redraw_main_dialog
	bsr.w	do_dialog
	bsr.w	unselect_button_nodraw
	bra.w	main_draw_dialog

button_format:
	cmpi.b	#$3e,d3                         ; FORMAT?
	bne.s	button_copy
	bsr.w	read_settings
	bne.s	unselect_and_loop
	bsr.w	format_disk
	bra.s	unselect_and_loop

button_copy:
	cmpi.b	#$3d,d3                         ; COPY?
	bcs.s	button_track_arrows             ; below COPY: track arrows
	bne.w	gem_exit                        ; above COPY: EXIT
	bsr.w	read_settings
	bne.s	unselect_and_loop
	tst.b	prot_mode                       ; protected mode?
	beq.s	copy_normal_mode
	bsr.w	copy_disk_protected
	moveq	#61,d3                          ; unselect COPY afterwards
	bra.s	unselect_and_loop

copy_normal_mode:
	bsr.w	read_source_bpb
	beq.s	start_normal_copy
	lea	alert_cannot_normal,a0          ; alert: cannot copy this disk
	bsr.w	alert
	bra.s	unselect_and_loop

start_normal_copy:
	bsr.w	copy_disk_normal
unselect_and_loop:
	bsr.w	unselect_button
	bra.w	main_loop


;----------------------------------------------------------------------
; Start/end track arrow buttons (objects 47/50 and 53/56).
;----------------------------------------------------------------------
button_track_arrows:	; from: main_loop
	bsr.w	mouse_off
	clr.l	d2
	lea	start_track,a4
	lea	$1(a4),a5
	move.b	(a4),d2
	lea	obj_text_table,a1
	movea.l	(a1)+,a0                        ; a0 -> START_TEXT
	cmpi.b	#$35,d3                         ; END_DOWN or above?
	bcs.s	adjust_start_track
	addq.l	#4,a1
	movea.l	(a1)+,a0                        ; a0 -> END_TEXT
	move.b	(a5),d2
adjust_start_track:
	cmpi.b	#$35,d3                         ; '5', END_DOWN
	bcc.s	adjust_end_track
	cmpi.b	#$2f,d3                         ; START_DOWN?
	bne.s	loc_03b4
	tst.w	d2
	beq.s	loc_03c0
	subq.b	#1,d2
loc_03b4:
	cmpi.b	#$32,d3                         ; START_UP?
	bne.s	loc_03c0
	cmp.b	(a5),d2                         ; start < end?
	bcc.s	loc_03c0
	addq.b	#1,d2
loc_03c0:
	move.b	d2,(a4)
	bra.s	show_track_number

adjust_end_track:
	cmpi.b	#$35,d3                         ; END_DOWN?
	bne.s	loc_03d0
	cmp.b	(a4),d2                         ; end > start?
	beq.s	loc_03de
	subq.b	#1,d2
loc_03d0:
	cmpi.b	#$38,d3                         ; END_UP?
	bne.s	loc_03de
	cmpi.b	#$55,d2                         ; max 85
	bcc.s	loc_03de
	addq.b	#1,d2
loc_03de:
	move.b	d2,(a5)                         ; PSG register select
show_track_number:
	divu.w	#$a,d2                          ; two decimal digits
	ori.b	#$30,d2
	move.b	d2,(a0)
	swap	d2
	ori.b	#$30,d2
	move.b	d2,$1(a0)
	bsr.w	draw_text
	bsr.w	mouse_on
	moveq	#32,d1                          ; SHADOWED
	tst.b	(a4)                            ; start track 0?
	bne.s	disable_format_button
	cmpi.b	#$4f,(a5)                       ; end track >= 79?
	bcc.s	set_format_button_state
disable_format_button:
	moveq	#40,d1                          ; SHADOWED|DISABLED
set_format_button_state:
	moveq	#62,d3                          ; FORMAT button
	bsr.w	change_object_state
	bra.w	main_loop


show_about_dialog:	; from: main_loop
	bsr.w	unselect_button_nodraw

redraw_main_dialog:	; from: main, main_loop
	movea.l	tree_blank,a3
	bsr.s	center_and_draw
	movea.l	a4,a3

center_and_draw:	; from: redraw_main_dialog
	bsr.w	center_dialog
	bra.w	draw_tree


;----------------------------------------------------------------------
; GEM initialisation: appl_init, graf_handle, v_opnvwk
;----------------------------------------------------------------------
gem_init:	; from: main
	moveq	#10,d0                          ; appl_init
	move.l	#$100,d1
	bsr.w	aes_call                        ; AES appl_init
	moveq	#77,d0                          ; graf_handle
	move.l	#$500,d1
	bsr.w	aes_call                        ; AES graf_handle
	lea	intout,a0
	move.w	(a0)+,vdi_handle                ; intout[0] = VDI handle
	move.l	(a0),d0                         ; char cell w:h
	sub.w	resolution,d0                   ; h - resolution
	move.l	d0,char_w
	lea	intin,a0
	moveq	#9,d0
workin_loop:
	move.w	#$1,(a0)+                       ; work_in[0..9] = 1
	dbra	d0,workin_loop
	move.w	#$2,(a0)                        ; work_in[10] = 2
	move.w	#$64,d0                         ; v_opnvwk
	move.l	#$b0000,d1
	bsr.w	vdi_call                        ; VDI v_opnvwk
	move.w	contrl_handle,vdi_handle        ; contrl[6] = handle
	rts


;----------------------------------------------------------------------
; Leave GEM: rsrc_free, v_clsvwk, appl_exit
;----------------------------------------------------------------------
gem_exit:	; from: main, main_loop
	moveq	#111,d0                         ; rsrc_free
	move.l	#$100,d1
	bsr.w	aes_call                        ; AES rsrc_free
	moveq	#101,d0                         ; v_clsvwk
	clr.l	d1
	bsr.w	vdi_call                        ; VDI v_clsvwk
	moveq	#19,d0                          ; appl_exit
	clr.l	d1
	bra.w	aes_call                        ; AES appl_exit


;----------------------------------------------------------------------
; form_alert with string in a0; returns Z set if button 1 was chosen
;----------------------------------------------------------------------
alert:	; from: main, main_loop, read_settings, fdc_error_alert, copy_disk_protected, copy_disk_normal
	move.l	a0,addrin
	move.w	#$1,intin                       ; intin[0] = 1 (default button)
	moveq	#52,d0                          ; form_alert
	move.l	#$10101,d1
	bsr.w	aes_call                        ; AES form_alert
	move.w	intout,d0
	cmpi.b	#$1,d0                          ; button 1?
	rts


;----------------------------------------------------------------------
; wind_get(0, WF_WORKXYWH) -> desk_xy/desk_wh
;----------------------------------------------------------------------
get_desktop_area:	; from: main
	clr.w	intin                           ; intin[0] = 0 (desktop)
	move.w	#$4,intin_1                     ; intin[1] = WF_WORKXYWH
	moveq	#104,d0                         ; wind_get
	move.l	#$502,d1
	bsr.w	aes_call                        ; AES wind_get
	lea	intout_1,a0
	move.l	(a0)+,desk_xy
	move.l	(a0),desk_wh
	rts


mouse_on:	; from: read_source_bpb, copy_disk_normal, fdc_error_alert, copy_disk_protected, button_track_arrows
	move.w	#$101,d0                        ; M_ON
	bra.s	graf_mouse_call


mouse_off:	; from: read_source_bpb, format_disk, fdc_error_alert, copy_disk_protected, copy_disk_normal, button_track_arrows
	move.w	#$100,d0                        ; M_OFF
	bra.s	graf_mouse_call


mouse_arrow:	; from: main, read_source_bpb, advance_track
	moveq	#0,d0                           ; ARROW
	bra.s	graf_mouse_call


mouse_busy:	; from: read_source_bpb
	moveq	#2,d0                           ; BUSY_BEE
graf_mouse_call:	; from: mouse_arrow, mouse_on, mouse_off
	move.w	d0,intin
	moveq	#78,d0                          ; graf_mouse
	move.l	#$10101,d1
	bra.w	aes_call                        ; AES graf_mouse


get_mouse_button:	; from: check_abort
	moveq	#79,d0                          ; graf_mkstate
	move.l	#$500,d1
	bsr.w	aes_call                        ; AES graf_mkstate
	move.w	intout_3,d7                     ; d7 = button state
	rts


load_resource:	; from: main
	move.l	#rsc_name,addrin
	moveq	#110,d0                         ; rsrc_load
	move.l	#$10100,d1
	bra.w	aes_call                        ; AES rsrc_load


;----------------------------------------------------------------------
; rsrc_gaddr(R_TREE, d3) -> a0 = tree, Z set on failure
;----------------------------------------------------------------------
get_tree:	; from: main
	clr.w	intin                           ; intin[0] = R_TREE
	move.w	d3,intin_1                      ; intin[1] = tree index
	moveq	#112,d0                         ; rsrc_gaddr
	move.l	#$1000102,d1
	bsr.w	aes_call                        ; AES rsrc_gaddr
	movea.l	addrout,a0
	move.w	intout,d0                       ; Z set if failed
	rts


;----------------------------------------------------------------------
; objc_draw(tree a3, 0, depth 5, desktop clip)
;----------------------------------------------------------------------
draw_tree:	; from: center_and_draw
	moveq	#5,d0                           ; start object 0, depth 5
	bsr.w	set_intin_clip
	move.l	a3,addrin
	moveq	#42,d0                          ; objc_draw
	move.l	#$10106,d1
	bra.w	aes_call                        ; AES objc_draw


;----------------------------------------------------------------------
; objc_change on object d3: d1 = new state, d2 = redraw flag
;----------------------------------------------------------------------
deselect_object:	; from: main_loop
	moveq	#0,d1                           ; state 0 = normal
	bra.s	change_object_state


select_object:	; from: main_loop
	moveq	#1,d1                           ; state 1 = SELECTED

change_object_state:	; from: deselect_object, main_loop, button_track_arrows
	moveq	#1,d2                           ; redraw
	bra.s	objc_change_call


unselect_button:	; from: main_loop
	moveq	#1,d2
	bra.s	objc_change_shadowed


unselect_button_nodraw:	; from: main_loop, show_about_dialog
	clr.w	d2
objc_change_shadowed:	; from: unselect_button
	moveq	#32,d1                          ; state 32 = SHADOWED
objc_change_call:	; from: change_object_state
	move.w	d3,d0                           ; intin[0] = object, [1] = 0
	swap	d0
	clr.w	d0
	bsr.w	set_intin_clip
	move.l	a3,addrin
	move.w	d1,(a0)+                        ; intin[6] = new state
	move.w	d2,(a0)                         ; intin[7] = redraw
	moveq	#47,d0                          ; objc_change
	move.l	#$10108,d1
	bra.w	aes_call                        ; AES objc_change


center_dialog:	; from: center_and_draw
	move.l	a3,addrin
	moveq	#54,d0                          ; form_center
	move.l	#$10500,d1
	bsr.w	aes_call                        ; AES form_center
	move.l	intout_1,dlg_xy
	move.l	intout_2,dlg_wh
	rts


;----------------------------------------------------------------------
; form_do(tree a3) -> d3 = exit object without double-click bit
;----------------------------------------------------------------------
do_dialog:	; from: main_loop
	move.l	a3,addrin
	clr.w	intin
	moveq	#50,d0                          ; form_do
	move.l	#$10101,d1
	bsr.s	aes_call                        ; AES form_do
	move.w	intout,d3
	bclr	#$f,d3                          ; drop double-click bit
	rts


;----------------------------------------------------------------------
; objc_offset(tree a3, object d0) -> d0 = x:y (y adjusted by char_h_adj)
;----------------------------------------------------------------------
object_screen_pos:	; from: main
	move.l	a3,addrin
	move.w	d0,intin
	moveq	#44,d0                          ; objc_offset
	move.l	#$10301,d1
	bsr.s	aes_call                        ; AES objc_offset
	move.l	intout_1,d0                     ; x:y
	add.w	char_h_adj,d0
	rts


;----------------------------------------------------------------------
; v_gtext: a0 = C string, a1 -> x,y
;----------------------------------------------------------------------
draw_text:	; from: show_status_text, show_formatting, show_side, button_track_arrows
	move.l	(a1),ptsin                      ; ptsin = x,y
	lea	intin,a1
	clr.l	d1
text_to_intin_loop:
	addq.b	#1,d1                           ; intin[n] = char
	clr.b	(a1)+
	move.b	(a0)+,(a1)+
	bne.s	text_to_intin_loop
	subq.b	#1,d1
	swap	d1                              ; intin count
	bset	#$0,d1                          ; ptsin count 1
	moveq	#8,d0                           ; v_gtext

;----------------------------------------------------------------------
; VDI call: d0 = opcode, d1 = contrl[1..4] packed as bytes
;----------------------------------------------------------------------
vdi_call:	; from: gem_exit, gem_init
	bsr.s	set_control
	move.w	vdi_handle,contrl_handle        ; contrl[6] = handle
	bra.w	vdi_trap


;----------------------------------------------------------------------
; AES call: d0 = opcode, d1 = control[1..4] packed as bytes
;----------------------------------------------------------------------
aes_call:	; from: gem_exit, alert, object_screen_pos, unselect_button_nodraw, do_dialog, draw_tree, ...
	bsr.s	set_control
	bra.w	aes_trap


set_control:	; from: aes_call, vdi_call
	lea	control,a0
	moveq	#4,d2                           ; d1 bytes -> control[1..4]
set_control_loop:
	move.w	d0,(a0)+
	move.b	d1,d0
	lsr.l	#8,d1
	dbra	d2,set_control_loop
	rts


set_intin_clip:	; from: unselect_button_nodraw, draw_tree
	lea	intin,a0
	move.l	d0,(a0)+                        ; intin[0..1] = d0
	move.l	desk_xy,(a0)+                   ; intin[2..5] = clip rectangle
	move.l	desk_wh,(a0)+
	rts


;----------------------------------------------------------------------
; Read the radio buttons of the main dialog into the settings bytes
; (source_drive .. interleave_6), patch the drive letters into the alert texts
; and show the "Insert disk" alert that matches the pressed button (d3).
;----------------------------------------------------------------------
read_settings:	; from: main_loop
	lea	radio_objects,a1
	lea	source_drive,a2
	movea.l	a2,a4
read_radio_loop:
	clr.l	d0
	move.b	(a1)+,d0
	beq.s	patch_drive_letters
	bsr.s	get_ob_state
	andi.b	#$1,d0                          ; SELECTED bit
	move.b	d0,(a2)+
	bra.s	read_radio_loop

patch_drive_letters:
	move.b	(a4)+,d0                        ; source drive
	move.b	d0,d1
	addi.b	#$41,d0                         ; drive letter
	lea	alert_insert_source_drv,a1
	move.b	d0,(a1)                         ; alert_insert_source
	move.b	d0,$5b(a1)                      ; alert_insert_both
	move.b	d0,$fb(a1)                      ; alert_insert_disk
	move.b	(a4),d0                         ; target drive
	clr.w	d2
	cmp.b	d1,d0                           ; source == target?
	beq.s	pick_insert_alert
	moveq	#1,d2
pick_insert_alert:
	move.b	d2,same_drive
	addi.b	#$41,d0
	move.b	d0,$75(a1)                      ; alert_insert_both
	move.b	d0,$2e(a1)                      ; alert_insert_target
	move.b	d0,$a1(a1)                      ; alert_target_mode
	move.b	d0,$d1(a1)                      ; alert_format
	lea	alert_format,a0
	cmpi.b	#$3e,d3                         ; FORMAT?
	beq.s	show_insert_alert
	lea	$2a(a0),a0                      ; alert_insert_disk
	cmpi.b	#$39,d3                         ; INFO?
	beq.s	show_insert_alert
	lea	-$fe(a0),a0                     ; alert_insert_source
	tst.b	same_drive
	beq.s	show_insert_alert
	lea	$5c(a0),a0                      ; alert_insert_both
show_insert_alert:
	bra.w	alert


;----------------------------------------------------------------------
; Return a0 -> ob_spec of object d0 in tree a3, d0 = ob_spec
;----------------------------------------------------------------------
get_ob_spec:	; from: main, fill_bpb_dialog
	moveq	#12,d1                          ; offset of ob_spec
	bsr.s	get_object_field
	movea.l	d0,a0
	rts


;----------------------------------------------------------------------
; Return a0 -> ob_flags of object d0 in tree a3, d0 = ob_flags:ob_state
;----------------------------------------------------------------------
get_ob_state:	; from: main, main_loop, read_settings
	moveq	#8,d1                           ; offset of ob_flags

get_object_field:	; from: get_ob_spec
	movea.l	a3,a0
	mulu.w	#$18,d0                         ; object size 24
	add.l	d1,d0
	adda.l	d0,a0
	move.l	(a0),d0
	rts


;----------------------------------------------------------------------
; Getbpb(source drive) -> bpb_ptr
;----------------------------------------------------------------------
get_bpb:	; from: read_source_bpb
	clr.w	d0
	move.b	source_drive,d0
	move.w	d0,-(sp)
	move.w	#$7,-(sp)                       ; Getbpb
	trap	#13                             ; Getbpb
	addq.l	#4,sp
	move.l	d0,bpb_ptr
	rts


;----------------------------------------------------------------------
; Build a formatted track image in track_buf from the dialog settings:
; d4 = sectors per track, d5 = interleave.  The track is filled with $4e gap bytes,
; then for each sector: sync, ID address mark ($fe) + ID bytes + CRC ($f7),
; gap, sync, data address mark ($fb) + 512 data bytes + CRC.  The address of
; each ID field inside the image is recorded in sector_id_ptrs.
;----------------------------------------------------------------------
build_format_track:	; from: format_disk
	moveq	#11,d4
	tst.b	eleven_sectors
	bne.s	set_interleave
	moveq	#10,d4
	tst.b	ten_sectors
	bne.s	set_interleave
	moveq	#9,d4
set_interleave:
	move.w	d4,dp_spt(a4)
	moveq	#6,d5
	tst.b	interleave_6
	bne.s	build_track_image
	moveq	#1,d5

build_track_image:	; from: build_format_track, copy_disk_normal
	move.w	d5,dp_interleave(a4)
	bsr.w	check_key_disk
	bsr.w	load_crc_from_key_track
	lea	track_buf,a0
	movea.l	a0,a1
	move.l	#$4e4e4e4e,d0                   ; 'NNNN' gap bytes
	move.w	#$7bf,d1                        ; $7c0 longs = 7936 bytes
fill_gap_loop:
	move.l	d0,(a1)+
	dbra	d1,fill_gap_loop
	lea	sector_id_ptrs,a1
	addq.l	#4,a0
	cmpi.b	#$b,d4                          ; 11 sectors: no index gap
	bcc.s	build_sector_loop_outer
	lea	$38(a0),a0                      ; index gap 60 bytes
	cmpi.b	#$9,d4                          ; 9 sectors?
	bne.s	build_sector_loop_outer
	bsr.w	emit_sync
	move.b	#$fe,(a0)+                      ; extra ID field (sector 12) for 9 sectors
	move.l	a0,(a1)+
	clr.b	(a0)+
	clr.b	(a0)+
	move.b	#$c,(a0)+                       ; sector 12
	move.b	#$2,(a0)+                       ; size code 2 = 512
	move.b	#$f7,(a0)+                      ; CRC
	lea	$28(a0),a0
build_sector_loop_outer:
	moveq	#1,d7                           ; d7 = first sector of this pass
build_sector_loop_side:
	move.b	d7,d6
build_sector_loop:
	bsr.w	emit_sync
	move.b	#$fe,(a0)+                      ; ID address mark
	move.l	a0,(a1)+                        ; remember ID field address
	clr.b	(a0)+
	clr.b	(a0)+
	move.b	d6,(a0)+                        ; sector number
	move.b	#$2,(a0)+                       ; size code 2
	move.b	crc_code_1,(a0)+                ; CRC byte from key track ($f7)
	lea	$16(a0),a0                      ; gap 2
	bsr.w	emit_gap2_sync
	move.b	#$fb,(a0)+                      ; data address mark
	move.w	#$1ff,d1                        ; 512 zero bytes
	bsr.w	emit_fill
	move.b	#$f7,(a0)+                      ; CRC
	cmpi.b	#$b,d4                          ; 11 sectors: no gap 3
	beq.s	next_sector_id
	lea	$28(a0),a0
next_sector_id:
	add.b	d5,d6                           ; next sector = + interleave
	cmp.b	d4,d6
	ble.s	build_sector_loop
	addq.b	#1,d7
	cmp.b	d5,d7
	ble.s	build_sector_loop_side
	rts


;----------------------------------------------------------------------
; Fill track/side/sector numbers into the ID fields of the track image
; (sequential, interleaved or via skew_table_il6).
;----------------------------------------------------------------------
fill_sector_ids:	; from: format_disk, copy_disk_normal
	lea	sector_id_ptrs,a0
	move.w	dp_spt(a4),d0
	move.w	d0,d2
	cmpi.b	#$a,d0                          ; less than 10 sectors: sequential
	bcs.s	fill_ids_sequential
	subq.b	#1,d0
	cmpi.b	#$1,dp_interleave+1(a4)         ; interleave 1?
	beq.s	calc_skew
	cmpi.b	#$b,d2                          ; 11 sectors?
	bne.s	fill_ids_sequential
calc_skew:
	clr.l	d1                              ; skew = track mod spt
	move.w	dp_track(a4),d1
	divu.w	d2,d1
	swap	d1
	cmpi.b	#$6,dp_interleave+1(a4)         ; interleave 6?
	beq.s	fill_ids_interleave6
	tst.w	d1
	beq.s	store_skew
	lsl.w	#1,d1
	cmp.w	d2,d1
	bcs.s	skew_wrap
	sub.w	d2,d1
	beq.s	store_skew
skew_wrap:
	sub.w	d1,d2
	move.w	d2,d1
store_skew:
	addq.w	#1,d1                           ; first sector of track
	move.w	d1,dp_first_sector(a4)
fill_ids_interleaved:
	movea.l	(a0)+,a1                        ; fill ID: track, side, sector
	move.b	dp_track+1(a4),(a1)+
	move.b	dp_side+1(a4),(a1)+
	move.b	d1,(a1)
	addq.w	#1,d1
	cmp.w	dp_spt(a4),d1
	ble.s	fill_ids_next
	moveq	#1,d1
fill_ids_next:
	dbra	d0,fill_ids_interleaved
	rts

fill_ids_sequential:
	movea.l	(a0)+,a1                        ; fill ID: track, side
	move.b	dp_track+1(a4),(a1)+
	move.b	dp_side+1(a4),(a1)
	dbra	d0,fill_ids_sequential
	move.w	#$1,dp_first_sector(a4)
	rts

fill_ids_interleave6:
	tst.w	d1
	beq.s	fill_ids_table
	sub.w	d1,d2
	move.w	d2,d1
fill_ids_table:
	ext.l	d1
	lea	skew_table_il6,a2
	adda.l	d1,a2
	clr.l	d1
	move.b	(a2),d1
	move.w	d1,dp_first_sector(a4)
fill_ids_table_loop:
	movea.l	(a0)+,a1
	move.b	dp_track+1(a4),(a1)+
	move.b	dp_side+1(a4),(a1)+
	move.b	(a2)+,(a1)+
	tst.b	(a2)
	bne.s	fill_ids_table_next
	lea	-$b(a2),a2
fill_ids_table_next:
	dbra	d0,fill_ids_table_loop
	rts

skew_table_il6:	; from: fill_sector_ids
	dc.w	$0107,$0208,$0309,$040a,$050b,$0600

;----------------------------------------------------------------------
; Status display: print " Reading "/" Writing "/"Formating" and the drive letter
;----------------------------------------------------------------------
show_reading:	; from: copy_disk_protected, copy_disk_normal
	move.l	#txt_reading,d4
	bra.s	show_status                     ; show " Reading "


show_writing:	; from: copy_disk_protected, copy_disk_normal
	move.l	#txt_writing,d4
	bra.s	show_status                     ; show " Writing "


show_formatting:	; from: format_disk
	move.l	#txt_formating,d4
show_status:	; from: show_writing, show_reading
	bsr.w	show_status_text                ; show "Formating"
	lea	drive_xy,a1
	lea	txt_drive_letter,a0
	move.b	dp_drive+1(a4),d0               ; drive letter
	addi.b	#$41,d0
	move.b	d0,txt_drive_letter
	bsr.w	draw_text

;----------------------------------------------------------------------
; Abort the current operation if the right mouse button is pressed
;----------------------------------------------------------------------
check_abort:	; from: format_disk, copy_disk_protected, copy_disk_normal
	bsr.w	get_mouse_button
	btst	#$1,d7                          ; right button?
	beq.s	check_abort_ret
abort_operation:	; from: fdc_error_alert
	addq.l	#4,sp                           ; drop return address
	bra.w	finish_operation

check_abort_ret:
	rts


show_side:	; from: seek_and_show
	lea	side_xy,a1
	lea	txt_side_digit,a0
	bra.w	draw_text

show_track:	; from: seek_and_show
	lea	track_xy,a1
	lea	txt_track_digits,a0
	bra.w	draw_text


;----------------------------------------------------------------------
; Show the alert that matches the FDC error bits in d7 (bit 8 = DMA error,
; bit 9 = fatal read, bit 7 = source not write protected, 4 = record not
; found, 3 = CRC, 2 = lost data, 6 = write protected). Z = Retry, Cancel aborts.
;----------------------------------------------------------------------
fdc_error_alert:	; from: format_disk, copy_disk_protected, copy_disk_normal
	bsr.w	unlock_floppy
	bsr.s	show_waiting
	bsr.w	mouse_on
	lea	alert_timeout,a0                ; d7 = -1: timeout
	tst.l	d7
	bmi.s	fdc_error_show
	lea	$da(a0),a0                      ; alert_write
	btst	#$8,d7                          ; bit 8: DMA error
	bne.s	fdc_error_show
	lea	$36(a0),a0                      ; alert_fatal_read
	btst	#$9,d7                          ; bit 9: read track failed
	bne.s	fdc_error_show
	lea	-$1bc(a0),a0                    ; alert_write_protect
	btst	#$7,d7                          ; bit 7: source not write protected
	bne.s	fdc_error_show
	lea	$e2(a0),a0                      ; alert_rnf
	btst	#$4,d7                          ; bit 4: record not found
	bne.s	fdc_error_show
	lea	-$6c(a0),a0                     ; alert_lost_data
	btst	#$2,d7                          ; bit 2: lost data
	bne.s	fdc_error_show
	lea	$a2(a0),a0                      ; alert_remove_wprot
	btst	#$6,d7                          ; bit 6: write protected
	bne.s	fdc_error_show
	lea	-$d8(a0),a0                     ; alert_checksum
	btst	#$3,d7                          ; bit 3: CRC error
	bne.s	fdc_error_show
	lea	$110(a0),a0                     ; alert_verify
fdc_error_show:
	bsr.w	alert
	move.w	d0,d7
	bsr.w	mouse_off
	bsr.w	lock_floppy
	bsr.w	select_drive_side
	cmpi.b	#$2,d7                          ; Cancel?
	beq.w	abort_operation
	cmpi.b	#$1,d7                          ; Retry?
	rts


show_waiting:	; from: copy_disk_normal, fdc_error_alert, copy_disk_protected
	move.l	waiting_text,d4

show_status_text:	; from: show_formatting
	movea.l	d4,a0
	lea	waiting_xy,a1
	bra.w	draw_text


;----------------------------------------------------------------------
; Emit d1+1 zero bytes followed by three $f5 (write-track sync) bytes
;----------------------------------------------------------------------
emit_sync:	; from: build_track_image
	moveq	#2,d1                           ; 3 zero bytes
	cmpi.w	#$b,d4                          ; 11 sectors?
	beq.s	emit_zeros_then_sync

emit_gap2_sync:	; from: build_track_image
	moveq	#11,d1                          ; 12 zero bytes
emit_zeros_then_sync:	; from: emit_sync
	bsr.s	emit_fill
	moveq	#2,d1
	moveq	#-11,d0                         ; three $f5 sync bytes
	bra.s	emit_fill_loop


emit_fill:	; from: build_track_image, emit_gap2_sync
	clr.w	d0
emit_fill_loop:	; from: emit_gap2_sync
	move.b	d0,(a0)+
	dbra	d1,emit_fill_loop
	rts


;----------------------------------------------------------------------
; a5 = PSG, a6 = FDC/DMA registers, a4 = disk_params
;----------------------------------------------------------------------
load_base_regs:	; from: read_source_bpb, format_disk, copy_disk_protected, copy_disk_normal, read_key_track
	lea	$ff8800,a5                      ; PSG register select
	lea	$ff8604,a6                      ; DMA sector count / FDC access
	lea	disk_params,a4
	rts


;----------------------------------------------------------------------
; Step to the next side/track; returns d0 = 1 when past the last track
;----------------------------------------------------------------------
advance_track:	; from: format_disk, copy_disk_protected
	cmpi.b	#$1,dp_sides+1(a4)              ; single sided?
	beq.s	next_track_number
	eori.b	#$1,dp_side+1(a4)               ; toggle side
	bne.s	advance_track_more
next_track_number:
	move.w	dp_track(a4),d0
	addq.b	#1,d0
	move.w	d0,dp_track(a4)
check_last_track:	; from: calc_track_side_sector
	cmp.w	dp_tracks(a4),d0                ; past the last track?
	bcs.s	advance_track_more
	moveq	#1,d0
	rts

advance_track_more:
	clr.l	d0
	rts

fail_with_arrow:	; from: read_source_bpb
	bsr.w	mouse_arrow
	moveq	#1,d0
	rts


;----------------------------------------------------------------------
; FORMAT button: format the target disk track by track (write track + verify),
; then write a boot sector built with Protobt.
;----------------------------------------------------------------------
format_disk:	; from: main_loop
	bsr.w	mouse_off
	bsr.s	load_base_regs
	bsr.w	init_disk_params
	move.b	target_drive,dp_drive+1(a4)     ; drive = target
	bsr.w	build_format_track
	bsr.w	init_copy_buffer
	bsr.w	restore_drive
format_restart:
	bsr.w	show_formatting
format_track_begin:
	clr.w	dp_track_retries(a4)            ; clear retry count
format_track_retry:
	bsr.w	seek_and_show
	bsr.w	fill_sector_ids
	bsr.w	fdc_wait_status
	bsr.w	fdc_write_track
	bsr.w	check_abort
	bsr.w	fdc_wait_write_track
	bne.s	format_track_failed
	tst.b	verify_flag                     ; verify?
	beq.s	format_next_track
	move.w	dp_spt(a4),d5
	subq.w	#1,d5
	move.w	dp_first_sector(a4),d6          ; first sector id
	move.w	#$1,dp_saved_idx(a4)
format_verify_loop:
	clr.w	dp_sector_retries(a4)
	move.w	d6,d1
	move.w	d6,d4
	add.w	dp_interleave(a4),d6
	cmp.w	dp_spt(a4),d6
	ble.s	format_verify_sector
	moveq	#1,d6
	cmp.w	dp_interleave(a4),d6
	beq.s	format_verify_sector
	addq.b	#1,dp_saved_idx+1(a4)
	move.w	dp_saved_idx(a4),d6
format_verify_sector:
	move.l	#sector_list,d0                 ; read sector into sector_list buffer
	bsr.w	fdc_read_sector_cmd
	bsr.w	check_abort
	bsr.w	wait_dma_start                  ; DMA started?
	beq.s	format_verify_retry
	bsr.w	fdc_abort
	dbra	d5,format_verify_loop
	bra.s	format_next_track

format_verify_retry:
	bsr.w	fdc_abort
	move.w	d4,d1
	addq.w	#1,dp_sector_retries(a4)
	cmpi.b	#$5,dp_sector_retries+1(a4)     ; 5 attempts per sector
	bne.s	format_verify_sector
	moveq	#1,d7
format_track_failed:
	addq.w	#1,dp_track_retries(a4)
	cmpi.b	#$3,dp_track_retries+1(a4)      ; 3 attempts per track
	bcs.w	format_track_retry
	bsr.w	fdc_error_alert
	beq.w	format_restart                  ; Retry
	bsr.w	show_formatting
format_next_track:
	bsr.w	advance_track
	beq.w	format_track_begin
	clr.w	dp_side(a4)
	bsr.w	restore_drive
	clr.w	-(sp)                           ; execflag = 0
	moveq	#2,d0                           ; disktype 2 = 80 tracks single sided
	cmpi.b	#$1,dp_fsiz(a4)                 ; result unused
	cmpi.b	#$1,dp_sides+1(a4)              ; single sided?
	beq.s	format_write_boot
	moveq	#3,d0                           ; disktype 3 = 80 tracks double sided
format_write_boot:
	move.w	d0,-(sp)
	move.l	#$2000000,-(sp)                 ; serial > $1000000: random
	pea	sector_list
	move.w	#$12,-(sp)
	trap	#14                             ; Protobt
	lea	$e(sp),sp
	lea	sector_list,a0
	move.b	#$3,$16(a0)                     ; media descriptor low byte
	clr.l	d0
	move.w	dp_spt(a4),d0
	move.b	d0,$18(a0)                      ; sectors per track
	clr.l	d1
	move.w	dp_sides(a4),d1
	move.b	d1,$1a(a0)                      ; sides
	mulu.w	d1,d0
	move.w	dp_tracks(a4),d1
	mulu.w	d1,d0
	move.b	d0,$13(a0)                      ; total sectors
	lsr.w	#8,d0
	move.b	d0,$14(a0)
	moveq	#1,d1                           ; sector 1
	move.l	#sector_list,d0
	bsr.w	fdc_write_sector                ; write boot sector
	bsr.w	fdc_wait_result
	bra.w	finish_operation


;----------------------------------------------------------------------
; Initialise disk_params from the dialog: drive, tracks (end_track+1), sides
;----------------------------------------------------------------------
init_disk_params:	; from: format_disk, copy_disk_protected
	move.b	source_drive,dp_drive+1(a4)     ; drive = source
	clr.w	dp_side(a4)
	clr.w	d0
	move.b	end_track,d0                    ; tracks = end_track + 1
	addq.b	#1,d0
	move.w	d0,dp_tracks(a4)
	move.b	two_sides,d0                    ; sides = two_sides + 1
	addq.b	#1,d0
	move.w	d0,dp_sides(a4)
	rts


;----------------------------------------------------------------------
; Getbpb on the source drive, copy the BPB into disk_params, read boot sector
; and FATs into the buffer with Rwabs, read three sector IDs to find the
; interleave.  d0 = 0 on success.
;----------------------------------------------------------------------
read_source_bpb:	; from: main_loop, scan_track_sectors
	bsr.w	mouse_busy
	bsr.w	get_bpb
	tst.l	d0
	beq.w	fail_with_arrow
	bsr.w	load_base_regs
	movea.l	d0,a1
	lea	disk_params,a0
	moveq	#7,d1
copy_bpb_loop:
	move.w	(a1)+,(a0)+                     ; copy 8 BPB words
	dbra	d1,copy_bpb_loop
	movea.l	d0,a2
	move.w	(a2),d0
	cmpi.w	#$200,d0                        ; recsiz = 512?
	bne.w	fail_with_arrow
	clr.l	d0
	move.w	$14(a2),d0                      ; sides (TOS private field)
	cmpi.w	#$3,d0                          ; sides < 3
	bcc.w	fail_with_arrow
	move.w	d0,(a0)+
	move.w	$12(a2),d0                      ; tracks
	cmpi.w	#$57,d0                         ; tracks < 87
	bcc.w	fail_with_arrow
	move.w	d0,(a0)+
	move.w	$18(a2),d4                      ; sectors per track
	cmpi.w	#$c,d4                          ; sectors/track < 12
	bcc.w	fail_with_arrow
	move.w	d4,(a0)+
	clr.l	d0
	move.b	source_drive,d0
	move.w	d0,-(sp)
	move.w	$a(a2),-(sp)                    ; count = fatrec
	move.w	#$3,-(sp)                       ; start sector 3
	move.l	buffer_start,-(sp)
	move.w	#$2,-(sp)                       ; rwflag 2: read, no media change
	move.w	#$4,-(sp)                       ; Rwabs
	trap	#13                             ; Rwabs
	moveq	#14,d1
	adda.l	d1,sp
	tst.w	d0
	bne.w	fail_with_arrow
	bsr.w	mouse_arrow
	bsr.w	mouse_off
	bsr.w	lock_floppy
	bsr.w	read_ids_after_index            ; read 3 sector IDs
	bsr.w	unlock_floppy
	bsr.w	mouse_on
	tst.b	d7                              ; read ok?
	bne.w	fail_with_arrow
	lea	sector_list,a0
	lea	disk_params,a1
	moveq	#1,d1                           ; default interleave 1
	move.b	$2(a0),d0                       ; first ID: sector
	cmpi.b	#$1,d0                          ; sector 1?
	bne.s	store_interleave
	move.b	$8(a0),d2                       ; second ID: sector
	sub.b	d0,d2                           ; difference of sector numbers
	beq.s	store_interleave
	cmp.b	$15(a1),d2                      ; less than sectors per track?
	bcc.s	store_interleave
	move.b	d2,d1
store_interleave:
	move.w	d1,$16(a1)                      ; interleave
	clr.l	d0
	rts


;----------------------------------------------------------------------
; Fill the numbers of the BPB info dialog (tree 3, objects 3..14)
;----------------------------------------------------------------------
fill_bpb_dialog:	; from: main_loop
	moveq	#3,d4                           ; objects 3..14
	lea	disk_params,a4
	moveq	#11,d5
bpb_line_loop:
	move.l	d4,d0
	bsr.w	get_ob_spec
	lea	$1a(a0),a0                      ; end of the 4-digit field
	clr.l	d0
	move.w	(a4)+,d0
	moveq	#3,d1
bpb_digit_loop:
	divu.w	#$a,d0                          ; digits from the right
	swap	d0
	move.w	d0,d2
	clr.w	d0
	swap	d0
	ori.b	#$30,d2
	move.b	d2,-(a0)
	dbra	d1,bpb_digit_loop
	moveq	#2,d1
bpb_strip_zero_loop:
	cmpi.b	#$30,(a0)                       ; replace leading zeros by spaces
	bne.s	bpb_next_line
	bclr	#$4,(a0)
	tst.b	(a0)+
	dbra	d1,bpb_strip_zero_loop
bpb_next_line:
	addq.b	#1,d4
	dbra	d5,bpb_line_loop
	rts


;----------------------------------------------------------------------
; COPY in normal mode: build a sector usage map from the FAT, read all used
; sectors into memory, then write (and optionally verify) them to the target.
;----------------------------------------------------------------------
copy_disk_normal:	; from: main_loop
	bsr.w	mouse_off
	lea	disk_params,a0
	move.w	$e(a0),d2                       ; numcl
	move.w	$2(a0),d4                       ; clsiz - 1
	subq.w	#1,d4
	movea.l	buffer_start,a0
	lea	sector_list,a1                  ; sector usage map
	moveq	#2,d0                           ; first cluster 2
build_sector_map_loop:
	move.l	d0,d1                           ; 12-bit FAT entry for cluster d0
	lsr.w	#1,d1
	move.w	sr,d5                           ; remember odd/even
	add.w	d0,d1
	movea.l	a0,a2
	adda.l	d1,a2                           ; a2 -> FAT entry (buffer holds boot + FAT)
	move.b	$1(a2),d1
	lsl.w	#8,d1
	move.b	(a2),d1
	btst	#$0,d5
	beq.s	fat_entry_test
	lsr.w	#4,d1
fat_entry_test:
	clr.b	d5
	andi.w	#$fff,d1                        ; cluster used?
	beq.s	fat_entry_store
	addq.b	#1,d5
fat_entry_store:
	move.w	d4,d1
mark_cluster_loop:
	move.b	d5,(a1)+                        ; one map byte per sector of the cluster
	dbra	d1,mark_cluster_loop
	addq.w	#1,d0
	dbra	d2,build_sector_map_loop        ; next cluster
	bsr.w	load_base_regs
	clr.l	d4
	move.w	dp_spt(a4),d4
	clr.l	d5
	move.w	dp_interleave(a4),d5
	bsr.w	build_track_image
	clr.l	d0
	move.w	dp_sides(a4),d0
	mulu.w	dp_spt(a4),d0
	mulu.w	dp_tracks(a4),d0
	move.w	d0,dp_total_sectors(a4)         ; total sectors = sides*spt*tracks
	clr.w	dp_resume_idx(a4)
	clr.w	dp_sector_idx(a4)
	clr.w	dp_src_warned(a4)
read_pass:
	move.b	source_drive,dp_drive+1(a4)
	bsr.w	init_copy_buffer
	bsr.w	restore_check_wprot             ; source write protected?
	bne.s	read_pass_show
	tst.w	dp_src_warned(a4)
	bne.s	read_pass_show
	st	dp_src_warned(a4)               ; warn once
	bsr.w	fdc_error_alert                 ; alert_write_protect
read_pass_show:
	bsr.w	show_reading
read_sector_loop:
	bsr.w	calc_track_side_sector
	bsr.w	get_sector_map_entry
	beq.s	read_sector_next                ; unused sector: skip
	bsr.w	seek_and_show
	bsr.w	fdc_wait_status
	clr.w	dp_sector_retries(a4)
read_sector_retry:
	bsr.w	get_sector_buffer
	bsr.w	fdc_read_sector_cmd
	bsr.w	check_abort
	bsr.w	fdc_wait_result_rw
	beq.s	read_sector_done                ; ok
	tst.l	d7
	bmi.s	read_sector_count_retry         ; timeout: retry
	btst	#$4,d7                          ; record not found: alert
	bne.s	read_sector_error
read_sector_count_retry:
	addq.w	#1,dp_sector_retries(a4)
	cmpi.b	#$5,dp_sector_retries+1(a4)     ; 5 attempts
	bne.s	read_sector_retry
read_sector_error:
	bsr.w	fdc_error_alert
	beq.s	read_pass_show                  ; Retry
	bsr.w	show_reading
read_sector_done:
	bsr.w	compress_uniform_sector
read_sector_next:
	move.w	dp_sector(a4),d0
	cmp.w	dp_spt(a4),d0
	bne.s	read_check_buffer_full
	move.w	dp_sector_idx(a4),dp_end_idx(a4) ; last sector of track: remember index
read_check_buffer_full:
	move.l	buffer_ptr,d0
	addi.l	#$200,d0
	cmp.l	buffer_end,d0                   ; buffer full?
	bcc.s	read_pass_done
	addi.w	#$1,dp_sector_idx(a4)
	move.w	dp_sector_idx(a4),d0
	cmp.w	dp_total_sectors(a4),d0         ; all sectors read?
	bcs.w	read_sector_loop
read_pass_done:
	bsr.w	reset_track_and_restore
	tst.b	same_drive                      ; same drive: no alert
	bne.s	write_pass
	bsr.w	unlock_floppy
	bsr.w	show_waiting
	bsr.w	mouse_on
	lea	alert_insert_target,a0          ; alert_insert_target
	bsr.w	alert
	beq.s	write_pass_start                ; OK
	rts

write_pass_start:
	bsr.w	mouse_off
write_pass:
	bsr.w	init_copy_buffer
	move.w	dp_resume_idx(a4),dp_sector_idx(a4)
	move.b	target_drive,dp_drive+1(a4)
	bsr.w	restore_drive
write_track_begin:
	bsr.w	seek_and_show
	bsr.w	show_writing
	bsr.w	fdc_wait_status
write_sector_loop:
	bsr.w	calc_track_side_sector
	cmpi.b	#$1,dp_sector+1(a4)             ; first sector of the track?
	bne.s	write_sector
	move.l	buffer_ptr,buffer_ptr_saved
	move.w	dp_sector_idx(a4),dp_track_idx(a4)
	clr.w	dp_track_retries(a4)
format_target_track:
	tst.b	format_flag                     ; format target track first
	beq.s	write_sector
	bsr.w	seek_and_show
	move.l	buffer_ptr_saved,buffer_ptr
	move.w	dp_track_idx(a4),dp_sector_idx(a4)
	move.b	#$1,dp_sector+1(a4)             ; sector 1
	bsr.w	fill_sector_ids
	bsr.w	fdc_wait_status
	bsr.w	fdc_write_track
	bsr.w	check_abort
	bsr.w	fdc_wait_write_track
write_sector:
	bsr.w	get_sector_map_entry
	beq.s	write_sector_next
	bsr.w	seek_and_show
	bsr.w	fdc_wait_status
	clr.w	dp_sector_retries(a4)
write_sector_retry:
	bsr.w	prepare_sector_fill
	bsr.w	fdc_write_sector
	bsr.w	check_abort
	bsr.w	fdc_wait_result
	beq.s	write_sector_advance
	tst.l	d7                              ; timeout: retry
	bmi.s	write_sector_count_retry
	btst	#$6,d7                          ; write protected: alert
	bne.s	write_sector_error
	btst	#$4,d7                          ; record not found: format again
	bne.s	write_track_retry
write_sector_count_retry:
	addq.w	#1,dp_sector_retries(a4)
	cmpi.b	#$5,dp_sector_retries+1(a4)     ; 5 attempts
	bcs.s	write_sector_retry
write_track_retry:
	tst.b	format_flag
	beq.s	write_sector_error
	addq.w	#1,dp_track_retries(a4)
	cmpi.b	#$3,dp_track_retries+1(a4)      ; 3 attempts
	bcs.w	format_target_track
write_sector_error:
	bsr.w	fdc_error_alert
	beq.w	write_track_begin               ; Retry
	bsr.w	show_writing
write_sector_advance:
	movea.l	dp_map_ptr(a4),a0
	tst.b	(a0)                            ; uniform sector takes no buffer space
	bmi.s	write_sector_next
	addi.l	#$200,buffer_ptr
write_sector_next:
	tst.b	verify_flag                     ; verify?
	beq.w	write_next_sector
	move.w	dp_sector(a4),d0                ; last sector of the track?
	cmp.w	dp_spt(a4),d0
	bne.w	write_next_sector
	move.w	dp_sector_idx(a4),dp_saved_idx(a4)
	move.w	dp_track_idx(a4),dp_sector_idx(a4)
	moveq	#1,d5                           ; d5 = sector 1
	move.l	buffer_ptr_saved,sector_list_end
verify_sector_loop:
	tst.b	format_flag
	bne.s	verify_sector_start
	bsr.w	get_sector_map_entry
	beq.s	verify_sector_next
verify_sector_start:
	clr.w	dp_sector_retries(a4)
verify_sector_retry:
	move.w	d5,d1
	move.l	#verify_buf,d0                  ; read into verify_buf
	bsr.w	fdc_read_sector_cmd
	bsr.w	check_abort
	bsr.w	fdc_wait_result_rw
	tst.l	d7
	bmi.s	verify_sector_count_retry
	btst	#$4,d7                          ; record not found: failed
	bne.s	verify_failed
	tst.w	d7
	bne.s	verify_sector_count_retry
	bsr.w	get_sector_map_entry
	beq.s	verify_sector_next
	moveq	#127,d0                         ; 128 longs
	lea	verify_buf,a1
	tst.b	(a0)                            ; uniform sector?
	bmi.s	verify_uniform_sector
	movea.l	sector_list_end,a0
verify_compare_loop:
	cmpm.l	(a0)+,(a1)+                     ; compare with buffer
	dbne	d0,verify_compare_loop
	bne.s	verify_sector_count_retry
	move.l	a0,sector_list_end
	bra.s	verify_sector_next

verify_uniform_sector:
	move.b	$900(a0),d1                     ; uniform byte -> long
	move.w	d1,d2
	lsl.w	#8,d1
	move.b	d2,d1
	move.w	d1,d2
	swap	d1
	move.w	d2,d1
verify_uniform_loop:
	cmp.l	(a1)+,d1
	dbne	d0,verify_uniform_loop
	beq.s	verify_sector_next
verify_sector_count_retry:
	addq.w	#1,dp_sector_retries(a4)
	cmpi.b	#$3,dp_sector_retries+1(a4)     ; 3 attempts
	bcs.s	verify_sector_retry
	bra.s	verify_failed

verify_sector_next:
	addi.w	#$1,dp_sector_idx(a4)
	addq.b	#1,d5
	cmp.w	dp_spt(a4),d5
	ble.w	verify_sector_loop
	move.w	dp_saved_idx(a4),dp_sector_idx(a4)
	bra.s	write_next_sector

verify_failed:
	move.w	dp_track_idx(a4),dp_sector_idx(a4)
	tst.b	format_flag                     ; format on: format the track again
	beq.s	verify_error_alert
	addq.w	#1,dp_track_retries(a4)
	cmpi.b	#$3,dp_track_retries+1(a4)      ; 3 attempts
	bcs.w	format_target_track
verify_error_alert:
	moveq	#1,d7                           ; d7 = 1: verify error alert
	bsr.w	fdc_error_alert
	beq.w	write_track_begin               ; Retry
	bsr.w	show_writing
	move.w	dp_saved_idx(a4),dp_sector_idx(a4)
write_next_sector:
	addi.w	#$1,dp_sector_idx(a4)
	move.w	dp_sector_idx(a4),d0
	cmp.w	dp_end_idx(a4),d0
	ble.w	write_sector_loop
	bsr.w	reset_track_and_restore
	tst.b	multiple_flag                   ; multiple copies?
	beq.s	write_pass_more
	bsr.w	unlock_floppy
	bsr.w	show_waiting
	bsr.w	mouse_on
	lea	alert_target_mode,a0            ; alert_target_mode
	bsr.w	alert
	beq.w	write_pass_start                ; Write: write again
	move.b	d0,d7
	bsr.w	mouse_off
	cmpi.b	#$3,d7                          ; Read = continue reading
	beq.s	finish_mouse_on
write_pass_more:
	move.w	dp_sector_idx(a4),d0
	cmp.w	dp_total_sectors(a4),d0         ; all sectors done?
	bcc.s	finish_mouse_on
	tst.b	same_drive                      ; same drive: no alert
	bne.s	set_resume_index
	bsr.w	unlock_floppy
	bsr.w	show_waiting
	bsr.w	mouse_on
	lea	alert_insert_source,a0          ; alert_insert_source
	bsr.w	alert
	beq.s	resume_read_pass                ; OK
	rts

resume_read_pass:
	bsr.w	mouse_off
set_resume_index:
	move.w	dp_sector_idx(a4),dp_resume_idx(a4)
	bra.w	read_pass

finish_operation:	; from: format_disk, check_abort
	tst.w	dp_track(a4)                    ; track 0: no restore needed
	beq.s	finish_mouse_on
	bsr.w	reset_track_and_restore
finish_mouse_on:	; from: copy_disk_protected
	bsr.w	unlock_floppy
	bsr.w	show_waiting
	bra.w	mouse_on


;----------------------------------------------------------------------
; COPY in protected mode: read every track raw (Read Track + Read Address
; timing), analyse it, build a track-write script, then write the scripts to
; the target disk.
;----------------------------------------------------------------------
copy_disk_protected:	; from: main_loop
	bsr.w	mouse_off
	bsr.w	load_base_regs
	bsr.w	init_disk_params                ; drive = source
	clr.w	d0
	move.b	start_track,d0                  ; first track
	move.w	d0,dp_resume_idx(a4)
	clr.w	dp_track_idx(a4)
	bsr.w	check_key_disk
	bsr.w	load_crc_from_key_track
	clr.w	f_patch_fffb
	move.w	#$6a,write_delay                ; write_delay = 106
	clr.w	dp_unused_8c(a4)
	clr.w	dp_unused_90(a4)
	clr.w	dp_unused_8e(a4)
	clr.w	dp_src_warned(a4)
prot_read_pass:
	move.b	source_drive,dp_drive+1(a4)
	bsr.w	init_copy_buffer
	bsr.w	restore_check_wprot
	bne.s	prot_read_set_track
	tst.w	dp_src_warned(a4)               ; source write protected?
	bne.s	prot_read_set_track
	st	dp_src_warned(a4)
	bsr.w	fdc_error_alert                 ; alert_write_protect
prot_read_set_track:
	move.w	dp_resume_idx(a4),dp_track(a4)
	move.w	dp_track_idx(a4),dp_side(a4)
prot_read_show:
	bsr.w	show_reading
prot_read_track:
	bsr.w	seek_and_show
	bsr.w	fdc_wait_status
	move.w	dp_track(a4),d0
	move.w	d0,dp_cur_track(a4)
	clr.w	read_retries                    ; read_retries = 0
	cmp.b	start_track,d0                  ; start track: measure speed
	bne.s	prot_read_track_retry
	bsr.w	measure_drive_speed
prot_read_track_retry:
	addq.w	#1,read_retries
	cmpi.b	#$4,read_retries_1              ; 4 attempts
	beq.s	prot_build_script
	bsr.w	fdc_wait_status
	bsr.w	fdc_read_track
	bsr.w	check_abort
	bsr.w	wait_dma_change                 ; DMA running?
	bne.s	prot_analyse_track
	bsr.w	fdc_abort
	clr.l	d7                              ; bit 9 = read track failed
	move.w	#$200,d7
	bsr.w	fdc_error_alert
	beq.s	prot_read_show                  ; Retry
	bsr.w	show_reading
prot_analyse_track:
	bsr.w	init_id_list
	bsr.w	read_track_find_index
	beq.s	prot_no_sectors
	bsr.w	read_ids_timed
	beq.s	prot_no_sectors
	bsr.w	scan_track_sectors
	tst.w	f_id_ambiguous                  ; ID position ambiguous: read again
	bne.s	prot_read_track_retry
prot_build_script:
	tst.w	num_sectors                     ; no sectors found?
	beq.s	prot_no_sectors
	bsr.w	calc_sector_gaps
	bsr.w	check_abort
	bsr.w	detect_scheme_c
	clr.w	f_dup_scheme
prot_classify_loop:
	bsr.w	choose_gap_size
	bsr.w	read_track_sectors
	bsr.w	patch_cmp_sequence
	bsr.w	rebuild_track79
	beq.s	prot_no_sectors                 ; track 79 protection rebuilt
	bsr.w	detect_scheme_1b
	bsr.w	detect_scheme_dup
	beq.s	prot_classify_loop              ; duplicate sector split: classify again
prot_emit_script:
	bsr.w	emit_track_script
	bra.s	prot_read_next_track

prot_no_sectors:
	bsr.w	detect_a1a1_scheme
	beq.s	prot_emit_script                ; a1a1 scheme found
	bsr.w	patch_timing_loops
	bsr.w	emit_raw_track_script
prot_read_next_track:
	bsr.w	advance_track
	bne.s	prot_read_done                  ; last track?
	move.l	buffer_ptr,d0
	cmp.l	buffer_limit,d0                 ; buffer nearly full?
	bcs.w	prot_read_track
prot_read_done:
	bsr.w	patch_fffb_check
	bsr.w	reset_track_and_restore
	tst.b	same_drive                      ; same drive: no alert
	bne.s	prot_write_pass
	bsr.w	unlock_floppy
	bsr.w	show_waiting
	bsr.w	mouse_on
	lea	alert_insert_target,a0          ; alert_insert_target
	bsr.w	alert
	beq.s	prot_write_start                ; OK
	rts

prot_write_start:
	bsr.w	mouse_off
prot_write_pass:
	bsr.w	init_copy_buffer
	move.b	target_drive,dp_drive+1(a4)
	bsr.w	restore_drive
	move.w	dp_resume_idx(a4),dp_track(a4)
	move.w	dp_track_idx(a4),dp_side(a4)
prot_write_show:
	bsr.w	show_writing
prot_write_track:
	bsr.w	seek_and_show
	move.w	dp_track(a4),dp_cur_track(a4)
	bsr.w	fdc_wait_status
	bsr.w	write_track_from_script
	beq.s	prot_write_next                 ; ok
	bsr.w	fdc_error_alert
	beq.s	prot_write_show                 ; Retry
	bsr.w	show_writing
	bsr.w	advance_script                  ; Continue: skip this track
prot_write_next:
	bsr.w	check_abort
	bsr.w	advance_track
	bne.s	prot_write_done                 ; last track?
	move.l	buffer_ptr,d0
	cmp.l	buffer_limit,d0                 ; all scripts written?
	bcs.s	prot_write_track
prot_write_done:
	move.w	dp_track(a4),dp_end_idx(a4)
	bsr.w	reset_track_and_restore
	tst.b	multiple_flag                   ; multiple copies?
	beq.s	prot_more_tracks
	bsr.w	unlock_floppy
	bsr.w	show_waiting
	bsr.w	mouse_on
	lea	alert_target_mode,a0            ; alert_target_mode
	bsr.w	alert
	beq.w	prot_write_start                ; Write
	move.b	d0,d7
	bsr.w	mouse_off
	cmpi.b	#$3,d7                          ; Read
	beq.w	finish_mouse_on
prot_more_tracks:
	move.w	dp_end_idx(a4),d0
	cmp.w	dp_tracks(a4),d0                ; all tracks done?
	bcc.w	finish_mouse_on
	move.w	d0,dp_resume_idx(a4)
	move.w	dp_side(a4),dp_track_idx(a4)
	tst.b	same_drive                      ; same drive: no alert
	bne.s	prot_read_again
	bsr.w	unlock_floppy
	bsr.w	show_waiting
	bsr.w	mouse_on
	lea	alert_insert_source,a0          ; alert_insert_source
	bsr.w	alert
	beq.s	prot_resume_read                ; OK
	rts

prot_resume_read:
	bsr.w	mouse_off
prot_read_again:
	bra.w	prot_read_pass


;----------------------------------------------------------------------
; Measure the drive speed from the DMA count between index pulses -> drive_speed
;----------------------------------------------------------------------
measure_drive_speed:	; from: copy_disk_protected
	move.b	#$6f,drive_speed                ; default speed factor
	moveq	#2,d2                           ; 3 attempts
speed_measure_loop:
	bsr.w	fdc_read_track
	bsr.w	wait_dma_change
	beq.s	speed_measure_next
	move.w	#$3000,d0
speed_wait_index:
	btst	#$5,$fffa01                     ; wait for index pulse
	dbeq	d0,speed_wait_index
	beq.s	speed_measure_next
	bsr.w	dma_get_address
	subi.l	#track_buf_10,d0                ; bytes read until the index
	beq.s	speed_measure_next
	move.l	#$30000,d1                      ; speed = $30000 / bytes per revolution
	divu.w	d0,d1
	move.l	d1,d0
	swap	d0
	asl.b	#1,d0                           ; round
	cmp.b	d1,d0
	bcs.s	speed_range_check
	addq.b	#1,d1
speed_range_check:
	cmpi.b	#$60,d1                         ; plausible range $60..$7f
	bcs.s	speed_measure_next
	cmpi.b	#$80,d1
	bcc.s	speed_measure_next
	move.b	d1,drive_speed
	bra.w	fdc_abort

speed_measure_next:
	bsr.w	fdc_abort
	dbra	d2,speed_measure_loop
	rts


; Four bytes copied here from the copyright string (expected "EMS ")
key_ems:	; from: scan_track_sectors
	dc.b	$00
key_ems_1:	; from: scan_track_sectors
	dc.b	$00
key_ems_2:	; from: scan_track_sectors
	dc.b	$00,$00

;----------------------------------------------------------------------
; Scan the raw track in track_buf and build sector_list (18 bytes per entry):
;   +0  flags: bit0 duplicate ID, bit1 data mark present, bit2 fuzzy, bit3 read
;       error, bit4 no data field, bit5 data mark not $fb, bit7 contains sync
;       bytes; $ff = ID not found in buffer
;   +1  ordinal of duplicate IDs  +2 track,side,sector,size  +6 CRC
;   +8  gap start  +$a offset of ID  +$c offset of data  +$e data length
;   +$10 ID mark byte  +$11 data mark byte
;----------------------------------------------------------------------
scan_track_sectors:	; from: copy_disk_protected
	movem.l	a3-a6,-(sp)
	clr.w	f_id_ambiguous
	lea	copyright+$c-$681c,a0           ; a0 = copyright - $6754
	move.l	$681c(a0),key_ems               ; key_ems = "EMS "
	lea	track_buf,a0
	lea	sector_list,a3                  ; a3 = sector list
	lea	id_fields,a4                    ; a4 = ID fields
	lea	sector_buf,a5                   ; a5 = ID times
	clr.w	f_data_over_index
	clr.w	time_offset
	clr.w	gap_end
	clr.w	first_id_pos
	clr.w	f_ids_rotated
scan_next_id:
	bsr.w	find_next_id
	bmi.w	scan_finish                     ; no more IDs
	beq.s	scan_id_from_list               ; ID from the Read Address list
	move.w	d0,$a(a3)                       ; ID not in the list: copy bytes from the track
	movea.l	a3,a2
	addq.l	#2,a2
copy_id_bytes_loop:
	move.b	(a0)+,(a2)+                     ; copy d1+1 ID bytes
	dbra	d1,copy_id_bytes_loop
	move.w	#$ffff,(a3)                     ; flags = $ffff
	subq.l	#4,a5
	bra.s	scan_find_data

scan_id_from_list:
	move.w	d0,$a(a3)                       ; offset of ID in track
	move.w	d0,first_id_pos
	move.l	(a4)+,$2(a3)                    ; ID bytes and CRC from the list
	move.w	(a4)+,$6(a3)
	clr.w	(a3)
scan_find_data:
	movea.l	a0,a1
	cmpi.b	#$53,key_ems_2                  ; tamper check: "S"
	bne.w	read_source_bpb                 ; wrong: jump into read_source_bpb
	bsr.w	find_next_mark                  ; find the data address mark
	bne.w	scan_data_found
	cmpa.l	#sector_list,a3                 ; first entry?
	beq.s	scan_data_missing
	btst	#$4,-$12(a3)                    ; previous entry had no data field?
	bne.s	scan_no_data_field
scan_data_missing:
	cmpi.b	#$fc,last_mark                  ; last mark was an ID?
	bcs.s	scan_fake_data
	move.l	dma_pos,d0
	subi.l	#track_buf,d0
	sub.w	$a(a3),d0
	cmpi.w	#$32,d0                         ; ID within $32 bytes of the end?
	bcc.s	scan_no_data_field
scan_fake_data:
	moveq	#0,d0                           ; fake data field for a missing data mark
	move.w	$a(a3),d0
	addi.w	#$2c,d0
	move.w	d0,$c(a3)
	addq.w	#8,d0
	addi.l	#track_buf,d0
	move.l	d0,dma_pos
	move.b	#$fb,$11(a3)                    ; data mark $fb
	clr.l	d0
	move.b	$5(a3),d0
	bsr.w	sector_length
	move.w	d0,$e(a3)
	lea	$12(a3),a3
	st	f_data_over_index
	bra.w	scan_finish

scan_no_data_field:
	clr.l	$c(a3)
	bset	#$4,(a3)
	lea	$12(a3),a3
	bra.w	scan_finish

scan_data_found:
	addq.l	#2,a0                           ; skip the sync bytes
	subq.w	#2,d0
	move.w	d0,$c(a3)
	cmpi.b	#$fc,d1                         ; another ID mark?
	bcs.s	scan_check_data_mark
	movea.l	a1,a0
	clr.l	$c(a3)
	cmpa.l	#sector_list,a3
	beq.s	scan_mark_no_data
	move.w	$a(a3),d0
	sub.w	-$6(a3),d0                      ; distance to previous ID
	cmpi.w	#$4,d0                          ; adjacent IDs?
	bne.s	scan_mark_no_data
	bra.s	scan_next_entry

scan_mark_no_data:
	bset	#$4,(a3)
	bra.s	scan_gap_end

scan_check_data_mark:
	move.w	$c(a3),d0                       ; data mark more than $36 bytes after the ID?
	sub.w	$a(a3),d0
	cmpi.w	#$36,d0
	bcc.s	scan_mark_no_data
	movea.l	a0,a1
	move.b	d1,$11(a3)                      ; data mark byte
	cmpi.b	#$fb,d1                         ; normal data mark?
	beq.s	scan_data_length
	bset	#$5,(a3)                        ; bit 5: deleted/other data mark
scan_data_length:
	clr.l	d0
	move.b	$5(a3),d0
	bsr.w	sector_length                   ; data length from size code
	cmpi.b	#$4d,key_ems_1                  ; tamper check: "M"
	bne.w	read_track_sectors              ; wrong: jump into read_track_sectors
	move.w	d0,$e(a3)
scan_gap_end:
	move.w	$e(a3),d0                       ; end of data = data + length + 6
	beq.s	scan_store_gap_end
	add.w	$c(a3),d0
	addq.w	#6,d0
scan_store_gap_end:
	move.w	d0,gap_end
	lea	$12(a3),a3
scan_next_entry:
	cmpi.b	#$45,key_ems                    ; tamper check: "E"
	bne.w	calc_sector_gaps                ; wrong: jump into calc_sector_gaps
	addq.l	#4,a5                           ; end of ID list?
	cmpi.l	#$ffffffff,(a5)
	bne.w	scan_next_id
scan_finish:
	clr.w	(a3)                            ; terminating entry
	clr.l	$2(a3)
	move.l	a3,sector_list_end
	move.l	dma_pos,d0                      ; end of track = DMA position
	subi.l	#track_buf,d0
	move.w	d0,$8(a3)
	move.w	d0,$a(a3)
	move.w	d0,$c(a3)
	move.l	a3,d0
	lea	-$12(a3),a3
	move.l	a3,last_sector
	subi.l	#sector_list,d0                 ; number of entries
	divu.w	#$12,d0                         ; entry size 18
	move.w	d0,num_sectors
	cmpi.w	#$3,d0                          ; fewer than 3 sectors?
	bcc.s	scan_done
	tst.w	sector_list_c
	bne.s	scan_done
	subq.w	#1,d0
	beq.s	scan_check_fefe_track
	tst.w	sector_list_1e
	bne.s	scan_done
	cmpi.w	#$1810,sector_list_1c
	bcs.s	scan_done
scan_check_fefe_track:
	cmpi.l	#$fefefefe,sector_list_2        ; track of $fe bytes?
	bne.s	scan_no_sectors
	move.w	#$10,sector_list_a              ; ID offset 16
	lea	track_buf,a0
	clr.l	(a0)+
	clr.l	(a0)+
	clr.l	(a0)+
	clr.l	(a0)+
	bra.s	scan_done

scan_no_sectors:
	clr.w	num_sectors
scan_done:
	movem.l	(sp)+,a3-a6
	rts


;----------------------------------------------------------------------
; Compute the gap after each data field and flag over-long tracks
;----------------------------------------------------------------------
calc_sector_gaps:	; from: copy_disk_protected, scan_track_sectors
	lea	sector_list,a0
	lea	$12(a0),a1
	clr.w	$8(a0)
calc_gap_loop:
	move.w	$c(a0),d0                       ; end of this data field
	addq.w	#4,d0
	move.w	d0,d2
	add.w	$e(a0),d0
	move.w	$a(a1),d1                       ; next ID offset
	sub.w	d0,d1
	bcs.s	calc_gap_extend                 ; overlap: extend
	subq.w	#2,d1
	bcc.s	calc_gap_store
	clr.w	d1
calc_gap_extend:
	add.w	d1,$e(a0)
	ori.b	#$a,(a0)                        ; bits 1 and 3
calc_gap_store:
	add.w	$e(a0),d2
	btst	#$1,(a0)
	bne.s	calc_gap_next
	addq.w	#2,d2
calc_gap_next:
	move.w	d2,$8(a1)                       ; gap start of the next sector
	moveq	#18,d0                          ; entry size
	adda.l	d0,a0
	adda.l	d0,a1
	cmpa.l	sector_list_end,a1
	bcs.s	calc_gap_loop
	beq.s	calc_last_gap
	suba.l	d0,a0
	suba.l	d0,a1
calc_last_gap:
	clr.w	f_overlong_data
	clr.w	f_track_overflow
	clr.w	f_extra_id
	clr.w	f_sig_table_a
	move.w	$a(a1),$8(a1)
	move.b	$5(a0),d0                       ; size code of the last sector
	bsr.w	sector_length
	move.w	d0,d1
	move.w	$c(a0),d0                       ; no data field?
	beq.w	calc_gap_ret
	addq.w	#6,d0
	add.w	d1,d0
	move.l	d0,d2
	sub.w	$c(a1),d0                       ; data runs past the end of the track?
	bcs.w	calc_gap_extra_id
	st	f_overlong_data                 ; over-long data
	lea	sector_list,a2
	move.w	$a(a2),d1                       ; first ID offset + 16
	addq.w	#8,d1
	addq.w	#8,d1
	sub.w	d0,d1
	bcc.s	calc_gap_ten_sectors
	move.w	$c(a1),d2
	sub.w	$c(a0),d2
	subq.w	#4,d2
	cmpi.w	#$40,$a(a2)                     ; first ID after $40?
	bcs.s	calc_last_gap_limit
	add.w	$a(a2),d2
	subi.w	#$40,d2
calc_last_gap_limit:
	move.w	$c(a1),d1
	subi.w	#$1880,d1                       ; end beyond $1880?
	bcs.s	calc_last_gap_flags
	sub.w	d1,d2
	bcc.s	calc_last_gap_flags
	moveq	#16,d2
calc_last_gap_flags:
	cmpi.w	#$80,$a(a2)                     ; first ID after $80?
	bcs.s	calc_last_gap_min
	st	f_track_overflow
calc_last_gap_min:
	bclr	#$0,d2                          ; even, at least 16
	cmpi.w	#$10,d2
	bcc.s	calc_last_gap_long
	moveq	#16,d2
calc_last_gap_long:
	cmpi.w	#$44,num_sectors                ; 68+ sectors?
	bcs.s	calc_last_gap_store
	cmpi.w	#$24,d2
	bcs.s	calc_last_gap_store
	move.w	$c(a0),d0
	lea	track_buf,a1
	lea	$c(a1,d0.w),a1
	moveq	#-16,d0                         ; bytes $f0..$ff in a row?
calc_last_gap_scan:
	cmp.b	(a1)+,d0
	bne.s	calc_last_gap_store
	addq.b	#1,d0
	bne.s	calc_last_gap_scan
	moveq	#36,d2
calc_last_gap_store:
	move.w	d2,$e(a0)
	ori.b	#$a,(a0)
calc_gap_ret:	; from: orphan_rts
	rts

calc_gap_ten_sectors:
	cmpi.w	#$a,num_sectors                 ; 10 sectors: look for signature A
	bne.s	calc_gap_ret

;----------------------------------------------------------------------
; Look for the signature patterns in sig_table_a / sig_table_b
;----------------------------------------------------------------------
detect_signature_a:	; from: read_track_check_sig
	lea	track_buf_2,a0                  ; track_buf + 2
	move.b	(a0)+,d6
	bsr.w	count_byte_run                  ; run of the first byte
	cmpi.w	#$1f0,d0                        ; run $10..$1ef
	bge.s	sig_not_found
	cmpi.w	#$10,d0
	blt.s	sig_not_found
	subq.l	#1,a0
	lea	sig_table_a,a2                  ; 16 entries of 6 bytes
	move.b	(a0)+,d6
	moveq	#15,d1
sig_a_search_loop:
	move.b	(a2)+,d0                        ; first byte matches?
	cmp.b	d6,d0
	beq.s	sig_a_compare
	addq.l	#5,a2
	dbra	d1,sig_a_search_loop
sig_not_found:	; from: detect_signature_b
	moveq	#-1,d0
	rts

sig_a_compare:
	moveq	#4,d0                           ; compare the other 5 bytes
sig_a_compare_loop:
	cmpm.b	(a0)+,(a2)+
	dbne	d0,sig_a_compare_loop
	bne.s	sig_not_found
	st	f_sig_table_a
	clr.l	d0
	rts


detect_signature_b:	; from: read_track_check_sig
	move.b	(a0)+,d6
	bsr.w	count_byte_run                  ; run of the first byte
	cmpi.w	#$6,d0                          ; run 2..5
	bge.s	sig_not_found
	cmpi.w	#$1,d0
	ble.s	sig_not_found
	addq.l	#1,a0
	lea	sig_table_b,a2                  ; 16 entries of 5 bytes
	move.b	(a0)+,d6
	moveq	#15,d1
sig_b_search_loop:
	cmp.b	(a2)+,d6
	beq.s	sig_b_check_run
	addq.l	#4,a2
	dbra	d1,sig_b_search_loop
	bra.s	sig_not_found

sig_b_check_run:
	bsr.s	count_byte_run
	cmpi.w	#$c0,d0                         ; run $40..$bf
	bge.s	sig_not_found
	cmpi.w	#$40,d0
	blt.s	sig_not_found
	move.b	(a0)+,d6
	cmp.b	(a2)+,d6
	bne.s	sig_not_found
	move.b	(a0)+,d6
	cmp.b	(a2)+,d6
	bne.s	sig_not_found
	move.b	(a2)+,d6
	bsr.s	count_byte_run
	cmpi.w	#$48,d0                         ; run $39..$47
	bge.s	sig_not_found
	cmpi.w	#$38,d0
	ble.s	sig_not_found
	addq.l	#1,a0
	moveq	#9,d0                           ; 10 bytes
	cmpi.b	#$42,d6                         ; 11 bytes for these values
	beq.s	sig_b_extra_byte
	cmpi.b	#$72,d6                         ; 'r'
	beq.s	sig_b_extra_byte
	cmpi.b	#$9,d6
	beq.s	sig_b_extra_byte
	cmpi.b	#$84,d6
	beq.s	sig_b_extra_byte
	cmpi.b	#$39,d6                         ; '9'
	bne.s	sig_b_compare
sig_b_extra_byte:
	addq.w	#1,d0
sig_b_compare:
	move.b	(a2)+,d6
sig_b_compare_loop:
	cmp.b	(a0)+,d6
	dbne	d0,sig_b_compare_loop
	bne.w	sig_not_found
	addq.l	#1,a0
	cmpi.b	#$a1,(a0)+                      ; followed by $a1 $a1
	beq.s	sig_b_check_sync
	cmpi.b	#$a1,(a0)+
	bne.w	sig_not_found
sig_b_check_sync:
	cmpi.b	#$a1,(a0)
	bne.w	sig_not_found
	clr.l	d0
	rts


;----------------------------------------------------------------------
; Count the run of bytes equal to d6 at a0 -> d0
;----------------------------------------------------------------------
count_byte_run:	; from: detect_signature_b, detect_signature_a
	clr.l	d0
count_run_loop:
	cmp.b	(a0)+,d6
	beq.s	count_run_inc
	subq.l	#1,a0
	rts

count_run_inc:
	addq.w	#1,d0
	bra.s	count_run_loop

orphan_rts:
	rts                                     ; unreachable

calc_gap_check_overflow:
	cmpi.w	#$1890,d2                       ; end beyond $1890?
	bcs.s	calc_gap_ret2
	st	f_track_overflow
calc_gap_ret2:
	rts

calc_gap_extra_id:	; from: calc_sector_gaps
	lea	track_buf,a0
	adda.l	d2,a0
	bsr.w	find_next_mark                  ; another mark inside the gap?
	beq.s	calc_gap_check_overflow
	cmpi.b	#$fc,d1                         ; an ID mark?
	bcc.s	calc_gap_ret2
	subq.w	#2,d0
	move.w	d0,d4
	addi.w	#$106,d4                        ; ID + $106 before the next data field?
	cmp.w	$c(a1),d4
	bcc.w	calc_gap_ret
	move.w	d2,$8(a1)                       ; add it as an extra sector
	move.w	d0,$a(a1)
	st	f_extra_id
	clr.l	d0
	cmpi.b	#$fb,d1                         ; data mark $fb?
	beq.s	calc_gap_extra_store
	moveq	#32,d0                          ; flags: bit 5
calc_gap_extra_store:
	move.b	d0,(a1)
	move.w	#$100,$e(a1)                    ; length 256
	clr.l	$2(a1)
	rts


;----------------------------------------------------------------------
; Choose the inter-sector gap length for the track to write -> gap_size
;----------------------------------------------------------------------
choose_gap_size:	; from: copy_disk_protected
	moveq	#40,d1                          ; gap 40
	cmpi.w	#$b,num_sectors                 ; 11 sectors?
	bne.s	gap_size_check
	moveq	#1,d0
	lea	sector_list,a0
gap_size_scan_loop:
	cmpi.w	#$200,$e(a0)                    ; 512-byte sector?
	beq.s	gap_size_next
	cmpi.w	#$1f0,$e(a0)                    ; shorter than $1f0?
	bcs.s	gap_size_check
	subq.b	#1,d0                           ; allow one
	bne.s	gap_size_check
gap_size_next:
	lea	$12(a0),a0
	cmpa.l	last_sector,a0
	bne.s	gap_size_scan_loop
	moveq	#32,d1                          ; gap 32
	cmpi.w	#$160,$e(a0)                    ; last sector shorter than $160?
	bcs.s	gap_size_check
	moveq	#4,d1                           ; gap 4
	cmpi.w	#$200,$e(a0)                    ; last sector shorter than 512?
	bcc.s	gap_size_check
	move.w	#$200,$e(a0)                    ; make it 512
gap_size_check:
	cmpi.b	#$24,d1                         ; gap < 36?
	bcs.s	gap_size_store
	tst.w	f_data_over_index               ; data runs over the index?
	beq.s	gap_size_store
	move.b	sector_list,d0                  ; first sector has data?
	btst	#$4,d0
	bne.s	gap_size_store
	moveq	#36,d1                          ; gap 36
gap_size_store:
	move.w	d1,gap_size
gap_size_ret:	; from: read_track_sectors
	rts


;----------------------------------------------------------------------
; Read the data of every sector in sector_list into the copy buffer
;----------------------------------------------------------------------
read_track_sectors:	; from: copy_disk_protected, scan_track_sectors
	tst.w	f_fix_id_bit4                   ; ID bit 4 fixed?
	bne.s	read_all_sectors
	bsr.s	read_all_sectors                ; read all sectors
	tst.w	f_fix_id_bit4
	beq.s	gap_size_ret
	lea	sector_list,a0
clear_special_flag_loop:
	bclr	#$7,(a0)                        ; clear "special" flag
	lea	$12(a0),a0
	cmpa.l	sector_list_end,a0
	bne.s	clear_special_flag_loop

read_all_sectors:	; from: read_track_sectors
	clr.w	f_fuzzy_any
	clr.w	f_fuzzy_sector
	lea	sector_buf,a0                   ; a0 = sector buffer
	tst.w	f_extra_id                      ; extra ID found?
	beq.s	read_all_mark_special
	bsr.w	copy_track_tail
read_all_mark_special:
	bsr.w	mark_special_sectors            ; any special sectors?
	beq.s	read_all_setup
	bsr.w	read_special_sectors
read_all_setup:
	lea	sector_list,a1
	cmpi.w	#$6,num_sectors                 ; fewer than 6 sectors?
	bcs.s	read_all_start
	lea	$5a(a1),a1                      ; start with the 6th entry
	move.l	a0,d6
	movea.l	buffer_ptr,a0                   ; read into the copy buffer
read_all_start:
	move.l	a1,d5
read_all_loop:
	btst	#$4,(a1)                        ; no data field?
	bne.s	read_all_next
	btst	#$7,(a1)                        ; special?
	bne.s	read_all_next
	btst	#$0,(a1)                        ; duplicate ID?
	bne.s	read_all_duplicate
	bsr.w	read_sector_verify
	btst	#$3,(a1)                        ; read error?
	beq.s	read_all_next
	cmpa.l	last_sector,a1                  ; last sector?
	beq.s	read_all_fuzzy_check
	btst	#$1,(a1)                        ; data mark present?
	beq.s	read_all_fuzzy_check
	cmpi.w	#$4e,$e(a1)                     ; at least $4e bytes?
	bcs.s	read_all_next
read_all_fuzzy_check:
	bsr.w	detect_fuzzy_sector
	bra.s	read_all_next

read_all_duplicate:
	tst.w	f_dup_scheme                    ; duplicate scheme?
	bne.s	read_all_next
	bsr.w	read_sector_timed               ; timed read
	btst	#$4,(a1)                        ; no data?
	bne.s	read_all_mark_again
	btst	#$1,(a1)                        ; data mark present?
	beq.s	read_all_next
	move.w	$e(a1),d0                       ; advance buffer by data length
	lea	$0(a0,d0.w),a0
	btst	#$0,d0                          ; round up
	beq.s	read_all_next
	addq.l	#1,a0
	bra.s	read_all_next

read_all_mark_again:
	bsr.w	mark_special_sectors
read_all_next:
	lea	$12(a1),a1
	cmpa.l	d5,a1                           ; back at the start entry?
	beq.s	read_all_copy_buffer
	cmpa.l	sector_list_end,a1
	bne.s	read_all_loop
	lea	sector_list,a1                  ; wrap around to the first entry
	cmpa.l	d5,a1
	beq.s	read_all_done
	move.l	a0,d4
	movea.l	d6,a0
	bra.w	read_all_loop

read_all_copy_buffer:
	movea.l	buffer_ptr,a2                   ; copy the data read into the copy buffer
read_all_copy_loop:
	move.l	(a2)+,(a0)+
	cmpa.l	d4,a2
	bcs.s	read_all_copy_loop
read_all_done:
	bsr.w	fix_duplicate_counts
	rts


copy_track_tail:	; from: read_all_sectors
	movea.l	sector_list_end,a1              ; last entry = end of track
	clr.l	d0
	move.w	$a(a1),d0
	addq.w	#4,d0                           ; offset + 4
	lea	track_buf,a1
	adda.l	d0,a1
	move.w	#$ff,d0                         ; 256 bytes
copy_tail_loop:
	move.b	(a1)+,(a0)+
	dbra	d0,copy_tail_loop
	rts


detect_scheme_1b:	; from: copy_disk_protected
	clr.w	f_scheme_1b
	cmpi.w	#$80,num_sectors                ; at least 128 sectors?
	bcs.s	scheme_1b_ret
	lea	sector_list,a0
	movea.l	last_sector,a1
	lea	-$12(a1),a1
	moveq	#1,d0
scheme_1b_loop:
	cmpi.b	#$1b,(a0)                       ; flags $1b?
	bne.s	scheme_1b_ret
	cmp.b	$1(a0),d0                       ; ordinal sequential?
	bne.s	scheme_1b_ret
	addq.b	#1,d0
	lea	$12(a0),a0
	cmpa.l	a1,a0
	bne.s	scheme_1b_loop
	st	f_scheme_1b
scheme_1b_ret:
	rts


;----------------------------------------------------------------------
; Special handling for track 79 with a known protection signature: verify the
; checksum of the track and rebuild it from scratch in track_buf.
;----------------------------------------------------------------------
rebuild_track79:	; from: copy_disk_protected
	cmpi.b	#$4f,cur_track_b                ; track 79?
	bne.w	track79_ret
	cmpi.w	#$3,num_sectors                 ; 3 sectors?
	beq.w	track79_find_sig
	cmpi.w	#$9,num_sectors                 ; 9 sectors?
	bne.w	track79_ret
	lea	sector_list,a0
	moveq	#1,d0
	moveq	#8,d1
track79_check_loop:
	move.w	(a0),d2                         ; flags without bit 15
	bclr	#$f,d2
	tst.w	d2
	bne.w	track79_ret
	cmpi.w	#$4f00,$2(a0)                   ; track 79, side 0?
	bne.w	track79_ret
	cmp.b	$4(a0),d0                       ; sector 1..6, $f5..?
	bne.w	track79_ret
	cmpi.b	#$2,$5(a0)                      ; size code 2?
	bne.w	track79_ret
	addq.w	#1,d0
	cmpi.w	#$7,d0                          ; after sector 6 expect $f5
	bne.s	track79_check_next
	move.b	#$f5,d0
track79_check_next:
	lea	$12(a0),a0
	dbra	d1,track79_check_loop
	lea	sector_buf,a0
	move.l	#$f7f7f7f7,d0                   ; look for $f7f7f7f7 ...
	bsr.w	find_long_pattern
	move.l	#$f6f6f6f6,d0                   ; $f6f6f6f6
	bsr.w	find_long_pattern
	move.l	#$f5f5f5f5,d0                   ; $f5f5f5f5
	bsr.w	find_long_pattern
	move.l	#$e5e5e5e5,d0                   ; $e5e5e5e5 within $300 longs
	move.w	#$2ff,d1
	bsr.w	find_long_loop
track79_find_sig:
	lea	track_buf,a0                    ; search sig_track79 in the track
track79_sig_scan:
	addq.l	#1,a0
	cmpa.l	#track_buf_1000,a0              ; end of buffer
	beq.w	ret_one
	lea	sig_track79,a1
	moveq	#31,d7                          ; 32 bytes
	movea.l	a0,a2
track79_sig_compare:
	move.b	(a1)+,d0
	cmp.b	(a2)+,d0
	bne.s	track79_sig_scan
	dbra	d7,track79_sig_compare
	move.w	#$2e0,d0                        ; $2e1 longs
	moveq	#0,d1
track79_checksum_loop:
	moveq	#2,d2                           ; d4 = next long
track79_checksum_inner:
	move.b	(a0)+,d4
	asl.l	#8,d4
	dbra	d2,track79_checksum_inner
	move.b	(a0)+,d4
	add.l	d4,d1                           ; checksum: add and rotate
	rol.l	#1,d1
	dbra	d0,track79_checksum_loop
	cmpi.l	#$6a947ffe,d1                   ; checksum of the track
	bne.w	track79_ret
	lea	track_buf,a0
	movea.l	a0,a1
	move.w	#$63f,d0                        ; clear $1900 bytes
track79_clear_loop:
	clr.l	(a0)+
	dbra	d0,track79_clear_loop
	lea	$100(a1),a0                     ; ID at +$100: track 79, side 0, sector 4, size 2
	move.l	#$f5f5f5fe,(a0)+
	move.l	#$4f000402,(a0)+
	move.b	#$f7,(a0)+                      ; CRC
	lea	$200(a1),a0                     ; ID at +$200: track 79, side 0, sector 5, CRC $bcd9
	move.l	#$14a1a1fe,(a0)+
	move.l	#$4f000502,(a0)+
	move.w	#$bcd9,(a0)+
	move.w	#$4e4e,d0                       ; gap $4e
	moveq	#10,d1
track79_gap_loop:
	move.w	d0,(a0)+
	dbra	d1,track79_gap_loop
	clr.l	(a0)+                           ; data
	move.l	#$6221ecc0,(a0)+
	move.l	#$354a3fff,$b58(a0)             ; at +$b58
	lea	$bff(a0),a0                     ; at +$bff
	move.b	#$f5,(a0)+
	movea.l	a0,a1
	move.l	#$f5f5fe4f,(a0)+                ; ID: track 79 ...
	move.l	#$602f7,(a0)+                   ; side 0, sector 6, size 2, CRC
	moveq	#78,d0                          ; 21 x $4e
	moveq	#20,d1
track79_gap2_loop:
	move.b	d0,(a0)+
	dbra	d1,track79_gap2_loop
	move.b	#$f5,(a0)+
	move.b	#$1,(a0)+
	move.l	#$ffc0fa00,$5fc(a1)             ; at +$5fc
	clr.l	d0                              ; d0 = 0: ok
track79_ret:
	rts


find_long_pattern:	; from: rebuild_track79
	moveq	#127,d1                         ; search 128 longs

find_long_loop:	; from: rebuild_track79
	cmp.l	(a0)+,d0
	dbne	d1,find_long_loop
	bne.s	find_long_fail
	rts

find_long_fail:
	addq.l	#4,sp                           ; drop return address
ret_one:	; from: rebuild_track79
	moveq	#1,d0
	rts


; Expected start of the track 79 protection: sync, ID 79/0/5/2, CRC, gap
sig_track79:	; from: rebuild_track79
	dc.b	$14,$a1,$a1,$fe,$4f,$00,$05,$02,$bc,$d9
	dc.b	'NNNNNNNNNNNNNNNNNNNNNN'

detect_scheme_c:	; from: copy_disk_protected
	clr.w	f_scheme_c
	cmpi.b	#$4f,cur_track_b                ; track 79?
	bne.s	scheme_c_ret
	cmpi.w	#$c,num_sectors                 ; 12 sectors?
	bne.s	scheme_c_ret
	lea	sector_list,a0
	cmpi.b	#$1,$4(a0)                      ; first sector 1?
	bne.s	scheme_c_ret
	lea	$12(a0),a0
	cmpi.b	#$6,$4(a0)                      ; second sector 6?
	bne.s	scheme_c_ret
scheme_c_scan_loop:
	lea	$12(a0),a0
	cmpa.l	last_sector,a0
	beq.s	scheme_c_ret
	cmpi.b	#$9,$4(a0)                      ; find sector 9
	bne.s	scheme_c_scan_loop
	lea	-$12(a0),a0                     ; entry before it
	cmpi.b	#$a,(a0)                        ; flags $0a?
	bne.s	scheme_c_ret
	cmpi.b	#$43,$4(a0)                     ; sector >= 67?
	bcs.s	scheme_c_ret
	clr.l	d0
	move.b	$5(a0),d0
	bsr.w	sector_length                   ; data length from size code
	move.w	d0,$e(a0)
	st	f_scheme_c
scheme_c_tail_loop:
	lea	$12(a0),a0
	cmpa.l	last_sector,a0
	bne.s	scheme_c_tail_loop
	move.w	#$b0,$e(a0)                     ; last entry: length $b0
scheme_c_ret:
	rts


;----------------------------------------------------------------------
; Emit a track-write script for the "scheme C" protection
;----------------------------------------------------------------------
emit_script_scheme_c:	; from: emit_track_script
	lea	sector_list,a3
	move.w	#$6400,(a2)+                    ; opcode $64: RLE data
	move.l	#$84e0800,(a2)+                 ; 8 x $4e, 8 x $00
	bsr.w	emit_id_with_crc
	move.l	#$164e0c00,(a2)+                ; 22 x $4e, 12 x $00
	bsr.w	emit_mark_fb
	move.l	#$224e0c00,(a2)+                ; 34 x $4e, 12 x $00
	lea	$12(a3),a3
	bsr.w	emit_id_ff
	move.l	#$164e0c00,(a2)+
	bsr.w	emit_mark_f8
	move.l	#$d2e6d0e6,(a2)+                ; 210 x $e6, 208 x $e6
	move.l	#$23bc2,(a2)+                   ; literal 2 bytes $3b $c2
	move.w	#$5ce6,(a2)+                    ; 92 x $e6
	move.l	#$1f74e,(a2)+                   ; literal $f7, 78 x ... (end)
scheme_c_sector_loop:
	lea	$12(a3),a3
	move.l	#$24e0400,(a2)+                 ; 2 x $4e, 4 x $00
	btst	#$7,(a3)                        ; special sector?
	beq.s	scheme_c_normal_id
	clr.w	(a2)+                           ; literal: "D" + mark, $ff00ff00
	move.b	#$44,(a2)+                      ; 'D'
	move.b	$10(a3),(a2)+
	move.l	#$ff00ff00,(a2)+
	move.w	#$6400,(a2)+                    ; opcode $64
	bra.s	scheme_c_data

scheme_c_normal_id:
	bsr.w	emit_id_with_crc
scheme_c_data:
	move.l	#$164e0c00,(a2)+                ; 22 x $4e, 12 x $00
	bsr.w	emit_mark_fb
	move.l	#$80e680e6,(a2)+                ; 128 x $e6, 128 x $e6
	move.l	#$80e680e6,(a2)+
	move.l	#$1f700,(a2)+                   ; literal $f7, end
	cmpa.l	last_sector,a3
	bne.s	scheme_c_sector_loop
	clr.w	(a2)+                           ; end of RLE data
	tst.w	special_count                   ; special sectors?
	beq.s	scheme_c_verify_part
	bsr.w	emit_special_sector_script
scheme_c_verify_part:
	lea	sector_list,a3
	movea.l	a4,a6
	bsr.w	script_add_sector
	lea	$12(a3),a3
	bsr.w	script_add_sector
	movea.l	a6,a4
scheme_c_verify_loop:
	lea	$12(a3),a3
	btst	#$7,(a3)
	bne.s	scheme_c_verify_next
	bsr.w	script_add_sector
scheme_c_verify_next:
	cmpa.l	last_sector,a3
	bne.s	scheme_c_verify_loop
	rts


;----------------------------------------------------------------------
; Emit a track-write script for a track with one duplicated sector
;----------------------------------------------------------------------
emit_script_scheme_dup:	; from: emit_track_script
	lea	sector_list,a3
	moveq	#0,d0
	move.w	#$6400,(a2)+                    ; opcode $64: RLE data
scheme_dup_loop:
	move.l	#$224e0c00,(a2)+                ; 34 x $4e, 12 x $00
	bsr.w	emit_id_fe
	move.l	#$164e0c00,(a2)+                ; 22 x $4e, 12 x $00
	bsr.w	emit_mark_fb
	move.l	#$80e680e6,(a2)+                ; 128 x $e6, 128 x $e6
	cmpa.l	last_sector,a3
	beq.s	scheme_dup_data_end
	move.l	#$80e680e6,(a2)+
scheme_dup_data_end:
	move.l	#$1f700,(a2)+                   ; literal $f7, end
	addq.w	#1,d0
	cmpi.b	#$5,d0                          ; after 5 sectors: insert the last sector
	bne.s	scheme_dup_next
	movem.l	a3,-(sp)
	movea.l	last_sector,a3
	move.l	#$204e0c00,(a2)+                ; 32 x $4e, 12 x $00
	bsr.s	emit_id_fe
	move.l	#$164e0c00,(a2)+
	bsr.w	emit_mark_fb
	move.l	#$80e680e6,(a2)+
	move.l	#$1f700,(a2)+
	movem.l	(sp)+,a3
scheme_dup_next:
	lea	$12(a3),a3
	cmpa.l	sector_list_end,a3
	bne.s	scheme_dup_loop
	clr.w	(a2)+                           ; end of RLE data
	lea	sector_list,a3
scheme_dup_verify_loop:
	bsr.w	script_add_sector
	lea	$12(a3),a3
	cmpa.l	last_sector,a3
	bne.s	scheme_dup_verify_loop
	move.b	#$a,(a3)                        ; flags $0a, length $c0
	move.w	#$c0,$e(a3)
	bsr.w	script_add_sector
	movea.l	dma_pos,a5                      ; toggle bit 0 of the sector number
	eori.b	#$1,$4(a5)
	bsr.w	script_add_sector
	rts


;----------------------------------------------------------------------
; Script helpers: literal ID/data headers (count word followed by bytes)
;----------------------------------------------------------------------
emit_id_fe:	; from: emit_script_scheme_dup
	move.w	#$9,(a2)+                       ; 9 literal bytes: sync, $fe, ID, CRC
	move.l	#$f5f5f5fe,(a2)+
	move.l	$2(a3),(a2)+
	move.w	#$f700,(a2)+
	rts


emit_id_ff:	; from: emit_script_scheme_c
	move.w	#$9,(a2)+                       ; 9 literal bytes: sync, $ff, ID, CRC
	move.l	#$f5f5f5ff,(a2)+
	move.l	$2(a3),(a2)+
	move.w	#$f700,(a2)+
	rts


emit_id_with_crc:	; from: emit_script_scheme_c
	move.w	#$a,(a2)+                       ; 10 literal bytes: sync, $fe, ID, stored CRC
	move.l	#$f5f5f5fe,(a2)+
	move.l	$2(a3),(a2)+
	move.w	$6(a3),(a2)+
	rts


emit_mark_f8:	; from: emit_script_scheme_c
	move.w	#$4,(a2)+                       ; 4 literal bytes: sync, $f8 (deleted data mark)
	move.l	#$f5f5f5f8,(a2)+
	rts


emit_mark_fb:	; from: emit_script_scheme_c, emit_script_scheme_dup
	move.w	#$4,(a2)+                       ; 4 literal bytes: sync, $fb (data mark)
	move.l	#$f5f5f5fb,(a2)+
	rts


;----------------------------------------------------------------------
; Detect a track with exactly one duplicated sector ID
;----------------------------------------------------------------------
detect_scheme_dup:	; from: copy_disk_protected
	move.w	f_fuzzy_any,d0                  ; any fuzzy sectors?
	or.w	f_fuzzy_sector,d0
	beq.w	scheme_dup_ret_fail
	move.w	f_overlong_data,d0              ; none of these flags
	or.w	f_track_overflow,d0
	or.w	f_extra_id,d0
	or.w	f_sig_table_a,d0
	or.w	f_dup_scheme,d0
	bne.w	scheme_dup_ret_fail
	cmpi.w	#$b,num_sectors                 ; fewer than 11 sectors
	bcc.w	scheme_dup_ret_fail
	lea	sector_list,a0
	clr.w	d1
scheme_dup_scan_loop:
	cmpi.w	#$200,$e(a0)                    ; 512-byte sectors only
	bne.s	scheme_dup_ret_fail
	move.b	(a0),d2                         ; flags without bit 7
	bclr	#$7,d2
	tst.w	d2
	beq.s	scheme_dup_scan_next
	cmpi.b	#$c,d2                          ; flags $0c = fuzzy + read error
	bne.s	scheme_dup_ret_fail
	addq.w	#1,d1                           ; count them
	move.l	a0,d4
scheme_dup_scan_next:
	lea	$12(a0),a0
	cmpa.l	sector_list_end,a0
	bne.s	scheme_dup_scan_loop
	subq.w	#1,d1                           ; exactly one?
	bne.s	scheme_dup_ret_fail
	tst.w	f_fuzzy_any
	bne.s	scheme_dup_split
	cmpi.b	#$c,-$12(a0)                    ; last entry $0c?
	bne.s	scheme_dup_ret_fail
	st	f_dup_scheme_alt
	bra.s	scheme_dup_ret_fail

scheme_dup_split:
	st	f_dup_scheme
	move.l	a0,d1
	lea	$12(a0),a1                      ; make room for one more entry
	move.l	a0,last_sector
	move.l	a1,sector_list_end
	bsr.s	copy_entry                      ; copy the terminating entry up
	movea.l	d4,a0
	clr.b	(a0)                            ; clear flags of the fuzzy entry
	movea.l	d1,a1
	bsr.s	copy_entry                      ; duplicate it
	addq.w	#1,num_sectors
	moveq	#0,d0
	rts

scheme_dup_ret_fail:
	moveq	#1,d0
	rts


copy_entry:	; from: detect_scheme_dup
	moveq	#17,d0
copy_entry_loop:
	move.b	(a0)+,(a1)+
	dbra	d0,copy_entry_loop
	rts


;----------------------------------------------------------------------
; Build the track-write script for the current track into the copy buffer.
; Script layout at buffer_ptr: +0 length of part 1, +2/+4 total length,
; +6 handler (script_build_image or script_copy_raw_image), +$a script bytes.
; Each script item starts with an opcode byte (a multiple of 4, see
; opcode_table) followed by its parameters.  Part 2 (at +$2000 while building)
; is the verify script.
;----------------------------------------------------------------------
emit_track_script:	; from: copy_disk_protected
	movem.l	a3-a6,-(sp)
	movea.l	buffer_ptr,a2                   ; a2 = script part 1
	lea	$2000(a2),a4                    ; a4 = part 2 (verify)
	lea	$a(a2),a2                       ; script bytes start at +$a
	lea	sector_buf,a5
	move.w	num_sectors,d0                  ; no sectors?
	bne.s	emit_check_scheme_c
	tst.w	sig_a1a1_pos                    ; a1a1 signature found?
	beq.s	emit_check_scheme_c
	bsr.w	emit_script_a1a1                ; a1a1 scheme script
	bra.w	emit_finish_script

emit_check_scheme_c:
	tst.w	f_scheme_c                      ; scheme C?
	beq.s	emit_check_scheme_dup
	bsr.w	emit_script_scheme_c
	bra.w	emit_script_end

emit_check_scheme_dup:
	tst.w	f_dup_scheme_alt                ; single duplicate sector?
	beq.s	emit_check_extra_id
	bsr.w	emit_script_scheme_dup
	bra.w	emit_script_end

emit_check_extra_id:
	tst.w	f_extra_id                      ; extra ID found?
	beq.s	emit_check_special
	movea.l	sector_list_end,a3
	bsr.w	script_add_sector
emit_check_special:
	tst.w	special_count                   ; special sectors?
	beq.s	emit_leadin
	bsr.w	emit_special_sector_script
emit_leadin:
	bsr.w	detect_uniform_gap
	bsr.w	emit_leadin_gap
	tst.w	leadin_special_pos              ; lead-in handled?
	bne.s	emit_check_0b09
	bsr.w	emit_pregap_copy
emit_check_0b09:
	tst.w	f_scheme_0b09                   ; $0b09 scheme?
	beq.s	emit_sector_loop
	move.w	#$7000,(a4)+                    ; opcode $70: sync read track
emit_sector_loop:
	cmpi.b	#$ff,(a3)                       ; ID not from the list?
	beq.s	emit_sector_id
	btst	#$7,(a3)                        ; special sector?
	beq.s	emit_sector_normal
	move.b	#$44,(a2)+                      ; literal "D" + mark, $ff00ff00
	move.b	$10(a3),(a2)+
	move.l	#$ff00ff00,(a2)+
	bra.s	emit_sector_data

emit_sector_normal:
	btst	#$4,(a3)                        ; no data field?
	bne.s	emit_sector_id
	btst	#$0,(a3)                        ; duplicate ID?
	bne.s	emit_sector_id
	cmpa.l	last_sector,a3                  ; last sector?
	bne.s	emit_sector_verify
	tst.w	(a3)                            ; flags 0?
	bne.s	emit_sector_verify
	tst.w	f_sig_table_a                   ; signature A found?
	beq.s	emit_sector_verify
	bsr.w	patch_branches                  ; patch branches, emit long track
	bra.w	emit_script_end

emit_sector_verify:
	bsr.w	script_add_sector               ; verify part: add sector
emit_sector_id:
	bsr.w	emit_sector_header              ; ID item
	cmpi.b	#$ff,(a3)                       ; ID not from the list?
	beq.s	emit_sector_no_data
	btst	#$2,(a3)                        ; fuzzy?
	beq.s	emit_sector_no_data
	cmpi.b	#$2,$1(a3)                      ; ordinal < 2?
	bcc.s	emit_sector_no_data
	bsr.w	emit_data_check_opcode
emit_sector_no_data:
	btst	#$4,(a3)                        ; no data field?
	beq.s	emit_sector_data
	move.w	#$1c00,(a2)+                    ; opcode $1c: fix mark bytes
	move.w	$6(a3),(a2)+                    ; CRC, flags
	move.w	(a3),(a2)+
emit_sector_data:
	tst.w	$c(a3)                          ; no data offset?
	beq.w	emit_sector_gap
	cmpa.l	last_sector,a3                  ; last sector?
	bne.s	emit_data_header
	tst.w	f_data_over_index               ; data runs over the index?
	beq.s	emit_data_header
	btst	#$4,(a3)                        ; no data field?
	bne.w	emit_sector_gap
emit_data_header:
	bsr.w	emit_gap_after_id               ; gap 2
	move.b	#$18,(a2)+                      ; opcode $18: data field
	move.b	$11(a3),d0
	andi.b	#$f,d0                          ; data mark low nibble
	btst	#$1,(a3)                        ; data mark present?
	beq.s	emit_data_flags
	bset	#$6,d0                          ; bit 6: no trailing zeros
emit_data_flags:
	move.b	d0,(a2)+
	move.w	$e(a3),(a2)+                    ; length
	cmpi.b	#$ff,(a3)                       ; ID not from the list: raw data
	beq.w	emit_data_raw
	btst	#$7,(a3)                        ; special sector: no data
	bne.w	emit_sector_end
	btst	#$0,(a3)                        ; duplicate ID?
	beq.s	emit_data_kind
	bsr.w	emit_scheme_1b_data             ; scheme 1b marker
emit_data_done:
	bra.w	emit_sector_end

emit_data_kind:
	btst	#$4,(a3)                        ; no data field: raw
	bne.w	emit_data_raw
	btst	#$2,(a3)                        ; fuzzy?
	beq.s	emit_data_last_check
	cmpi.b	#$2,$1(a3)                      ; ordinal < 2: data from buffer
	bcs.s	emit_data_from_buffer
	bcc.s	emit_data_done
emit_data_last_check:
	cmpa.l	last_sector,a3                  ; last sector?
	bne.s	emit_data_special_check
	tst.w	f_track_overflow                ; track overflow: no data
	bne.s	emit_data_done
	btst	#$1,(a3)                        ; data mark present?
	bne.s	emit_data_special_check
	tst.w	f_overlong_data                 ; over-long data: no data
	bne.s	emit_data_done
emit_data_special_check:
	tst.w	special_count                   ; special sectors?
	beq.s	emit_data_sync_check
	btst	#$7,$12(a3)                     ; next sector special?
	bne.s	emit_data_done
emit_data_sync_check:
	tst.w	f_extra_id                      ; extra ID: no data
	bne.s	emit_data_done
	tst.w	f_sync_in_data                  ; sync bytes in data?
	beq.s	emit_data_from_buffer
	tst.w	f_uniform_gap                   ; uniform gap?
	beq.s	emit_data_short
	cmpa.l	#sector_list,a3                 ; first sector?
	bne.s	emit_data_short
	move.w	#$6c00,(a4)+                    ; opcode $6c: partial write track
	bra.s	emit_data_short_done

emit_data_short:
	bsr.w	check_f0f7_sector               ; $f0f1f2f3 sector?
	bne.s	emit_data_short_done
	move.w	#$24,-$2(a2)                    ; length $24
emit_data_short_done:
	bra.s	emit_data_done

emit_data_from_buffer:
	movea.l	script2_ptr,a4                  ; a4 = verify script, a5 = data
	movea.l	dma_pos,a5
	bset	#$7,-$3(a2)                     ; bit 7: data given
	btst	#$1,(a3)                        ; data mark present?
	bne.s	emit_data_length
	bset	#$4,-$3(a2)                     ; bit 4: CRC
	btst	#$3,(a3)                        ; read error?
	beq.s	emit_data_length
	bclr	#$4,-$3(a2)                     ; no CRC
	addq.w	#2,-$2(a2)                      ; length + 2
emit_data_length:
	clr.l	d0
	move.w	$e(a3),d0
	tst.b	f_data_not_uniform              ; uniform data?
	bne.s	emit_data_copy
	bset	#$5,-$3(a2)                     ; bit 5: fill byte
	move.w	f_data_not_uniform,(a2)+        ; fill byte
	adda.l	d0,a5                           ; skip the data
	btst	#$0,d0                          ; odd length: skip pad byte
	beq.w	emit_sector_end
	addq.l	#1,a5
	bra.w	emit_sector_end

emit_data_copy_loop:
	move.b	(a5)+,(a2)+                     ; copy the data bytes
emit_data_copy:
	dbra	d0,emit_data_copy_loop
	btst	#$0,$f(a3)                      ; odd length?
	beq.s	emit_data_tail
	move.b	#$10,(a2)+                      ; pad byte
	addq.l	#1,a5
emit_data_tail:
	btst	#$1,(a3)                        ; data mark present?
	bne.w	emit_sector_end
	btst	#$3,(a3)                        ; read error?
	beq.s	emit_sector_end
	move.b	#$e5,(a2)+                      ; $e5 $e5 after the data
	move.b	#$e5,(a2)+
	bra.s	emit_sector_end

emit_data_raw:
	bset	#$7,-$3(a2)                     ; bit 7: data given
	lea	track_buf,a1
	moveq	#4,d0                           ; data offset + 4
	add.w	$c(a3),d0
	adda.l	d0,a1
	move.w	$e(a3),d0                       ; length
	btst	#$1,(a3)                        ; data mark present?
	bne.s	emit_raw_select
	addq.w	#2,d0                           ; length + 2
	move.w	d0,-$2(a2)
	btst	#$4,(a3)                        ; no data field?
	beq.s	emit_raw_select
	tst.b	-$5(a1)                         ; byte before the mark
	bne.s	emit_raw_select
	cmpi.b	#$14,-$4(a1)                    ; $14 before the mark?
	beq.s	emit_raw_select
	clr.b	-$4(a2)                         ; patch length and mark
	clr.b	(a2)+
	move.b	-$4(a1),(a2)+
emit_raw_select:
	btst	#$4,(a3)                        ; no data field: copy from the track
	bne.s	emit_raw_copy
	movea.l	script2_ptr,a4                  ; else from the data buffer
	movea.l	dma_pos,a5
	bra.s	emit_buf_copy

emit_raw_copy_loop:
	move.b	(a1)+,(a2)+                     ; copy from the track buffer
emit_raw_copy:
	dbra	d0,emit_raw_copy_loop
	bra.s	emit_raw_odd

emit_buf_copy_loop:
	move.b	(a5)+,(a2)+                     ; copy from the data buffer
emit_buf_copy:
	dbra	d0,emit_buf_copy_loop
emit_raw_odd:
	btst	#$0,$f(a3)                      ; odd length?
	beq.s	emit_sector_end
	move.b	#$10,(a2)+                      ; pad byte
emit_sector_end:
	btst	#$1,(a3)                        ; data mark present?
	beq.w	emit_inter_gap
	lea	$12(a3),a3
	bra.w	emit_sector_next

emit_sector_gap:
	cmpa.l	last_sector,a3                  ; last sector?
	bne.s	emit_gap_from_track
	lea	$12(a3),a3
	bra.w	emit_sector_next

emit_gap_from_track:
	clr.l	d1
	move.w	$a(a3),d1                       ; this ID offset
	lea	$12(a3),a3
	move.w	$a(a3),d0                       ; next ID offset
	sub.w	d1,d0
	subi.w	#$a,d0                          ; gap length - 10
	bcs.w	emit_sector_next
	beq.w	emit_sector_next
	cmpi.w	#$22,d0                         ; gap $22?
	beq.s	emit_gap_22
	subq.w	#1,d0
	cmpi.w	#$22,d0
	beq.s	emit_gap_22
	move.w	#$800,(a2)+                     ; opcode $08: gap literal
	movea.l	a2,a1
	move.w	d0,(a2)+                        ; length
	addi.l	#track_buf_a,d1                 ; a0 -> gap in the track buffer
	movea.l	d1,a0
	move.w	d0,d1
	clr.l	d4
emit_gap_copy_loop:
	move.b	(a0)+,d2
	cmpi.b	#$c2,d2                         ; three $c2 -> $f6 (write-track C2 sync)
	bne.s	emit_gap_reset_c2
	lsl.l	#8,d4
	move.b	d2,d4
	cmpi.l	#$c2c2c2,d4
	bne.s	emit_gap_store
	moveq	#-10,d2
	move.b	d2,-$2(a2)
	move.b	d2,-$1(a2)
emit_gap_reset_c2:
	clr.l	d4
emit_gap_store:
	move.b	d2,(a2)+
	dbra	d0,emit_gap_copy_loop
	cmpi.b	#$f5,(a0)                       ; sync follows?
	bne.s	emit_gap_pad
	subq.l	#2,a2                           ; replace the last two bytes by $f7
	move.b	#$f7,(a2)+
	subq.w	#1,(a1)
	subq.w	#1,d1
emit_gap_pad:
	btst	#$0,d1                          ; odd length?
	bne.s	emit_sector_next
	move.b	#$10,(a2)+                      ; pad byte
	bra.s	emit_sector_next

emit_gap_22:
	move.w	#$2800,(a2)+                    ; opcode $28: gap
	move.l	#$15b10bff,(a2)+                ; run list: 21 x $b1, 11 x $ff, end
	clr.w	(a2)+
	bra.s	emit_sector_next

emit_inter_gap:
	lea	$12(a3),a3
	bsr.w	emit_inter_sector_gap
emit_sector_next:
	cmpa.l	sector_list_end,a3              ; all sectors done?
	bne.w	emit_sector_loop
	tst.w	f_extra_id                      ; extra ID?
	beq.s	emit_leadin_pos
	move.w	#$4800,(a2)+                    ; opcode $48: ID zero
emit_leadin_pos:
	move.w	leadin_special_pos,d0           ; lead-in special position?
	beq.s	emit_pregap_pos
	move.w	#$5000,(a2)+                    ; opcode $50: ID $ff sector 1
	move.w	d0,(a2)+
emit_pregap_pos:
	move.w	pregap_pos,d0                   ; pregap position?
	beq.s	emit_check_dup_ids
	move.w	#$5000,(a2)+                    ; opcode $50
	move.w	d0,(a2)+
emit_check_dup_ids:
	tst.w	f_dup_ids                       ; duplicate IDs?
	beq.s	emit_script_end
	bsr.w	emit_dup_sector_timing
emit_script_end:
	move.w	#$2c00,(a2)+                    ; opcode $2c: end of part 1
	tst.b	verify_flag                     ; verify?
	beq.s	emit_finish_script
	movea.l	a4,a5
	move.w	#$4cff,(a4)+                    ; opcode $4c: verify sectors, count
	lea	sector_list,a0
emit_verify_list_loop:
	move.w	(a0),d0
	bclr	#$f,d0                          ; flags without bit 15
	tst.w	d0                              ; flags 0 only
	bne.s	emit_verify_next
	addq.b	#1,$1(a5)                       ; count++
	move.b	$4(a0),d0                       ; sector, track
	move.b	$2(a0),d1
	tst.w	f_fix_id_bit4                   ; fix bit 4?
	beq.s	emit_verify_entry
	bclr	#$4,d0
	bclr	#$4,d1
emit_verify_entry:
	move.b	d0,(a4)+
	move.b	d1,(a4)+
emit_verify_next:
	lea	$12(a0),a0
	cmpa.l	sector_list_end,a0
	bne.s	emit_verify_list_loop
	tst.b	$1(a5)                          ; count >= 128?
	bpl.s	emit_finish_script
	movea.l	a5,a4                           ; drop the verify list
emit_finish_script:
	move.w	#$3400,(a4)+                    ; opcode $34: end of verify part
	move.w	cur_track,d1                    ; track register = cur_track
	bsr.w	fdc_set_track_reg
	move.l	a2,d0
	movea.l	buffer_ptr,a0
	sub.l	a0,d0
	move.w	d0,(a0)                         ; length of part 1
	move.l	a0,d0
	addi.l	#$2000,d0                       ; part 2 at +$2000
	movea.l	d0,a1
	sub.l	a4,d0                           ; length of part 2 in words
	neg.w	d0
	lsr.w	#1,d0
	subq.w	#1,d0
append_verify_loop:
	move.w	(a1)+,(a2)+                     ; append part 2 to part 1
	dbra	d0,append_verify_loop
	bsr.w	patch_track3
	move.l	a2,buffer_ptr
	move.l	a2,d0
	sub.l	a0,d0
	move.w	d0,$4(a0)                       ; total length
	move.l	#script_build_image,$6(a0)      ; handler
	movem.l	(sp)+,a3-a6
	rts


;----------------------------------------------------------------------
; Check for a short sector whose data starts with $f0f1f2f3 $f4f5f6f7
;----------------------------------------------------------------------
check_f0f7_sector:	; from: emit_track_script, emit_gap_after_id
	btst	#$4,(a3)                        ; no data field?
	bne.s	check_f0f7_fail
	cmpi.w	#$26,$e(a3)                     ; length $20..$25
	bcc.s	check_f0f7_fail
	cmpi.w	#$20,$e(a3)
	bcs.s	check_f0f7_fail
	movea.l	dma_pos,a0
	cmpi.l	#$f0f1f2f3,$8(a0)               ; $f0f1f2f3
	bne.s	check_f0f7_fail
	cmpi.l	#$f4f5f6f7,$c(a0)               ; $f4f5f6f7
	bne.s	check_f0f7_fail
	rts

check_f0f7_fail:
	moveq	#1,d0
	rts

sig_a1a1_pattern:	; from: detect_a1a1_scheme
	dc.b	$a1,$a1,$00,$fd,$f8,$fe,$fe,$f8,$fa,$f9,$c2,$f8,$75,$37,$f6,$00
sig_a1a1_replace:	; from: detect_a1a1_scheme
	dc.b	$a1,$a1,$af,$f7,$f7,$f4,$1f,$a0,$01,$88,$5f,$34,$20,$13,$bf,$a7
	dc.b	$43,$64,$31,$96,$4d,$29,$3c,$34,$1f,$00

;----------------------------------------------------------------------
; Look for the $a1a1 $00fd... signature in the track
;----------------------------------------------------------------------
detect_a1a1_scheme:	; from: copy_disk_protected
	clr.w	sig_a1a1_pos
	tst.w	f_patched_boot_a                ; boot scheme A patched?
	beq.s	a1a1_scan
	cmpi.b	#$1,cur_track_b                 ; track 1?
	bne.s	a1a1_not_found
	cmpi.w	#$2,num_sectors                 ; fewer than 2 sectors?
	bcc.s	a1a1_not_found
	bsr.w	fill_track_4e                   ; fill the track with $4e
	lea	track_buf_60,a0                 ; replace at track_buf+$60
	move.l	a0,d2
	lea	sig_a1a1_replace,a1
	moveq	#25,d0                          ; 26 bytes
a1a1_copy_loop:
	move.b	(a1)+,(a0)+
	dbra	d0,a1a1_copy_loop
	bra.s	a1a1_found

a1a1_scan:
	lea	track_buf,a0
	moveq	#127,d0                         ; search 128 positions
a1a1_scan_loop:
	move.l	a0,d2
	lea	sig_a1a1_pattern,a1
	moveq	#14,d1                          ; 15 bytes
a1a1_compare_loop:
	cmpm.b	(a0)+,(a1)+
	dbne	d1,a1a1_compare_loop
	beq.s	a1a1_found
	movea.l	d2,a0
	addq.l	#1,a0
	dbra	d0,a1a1_scan_loop
a1a1_not_found:
	moveq	#1,d0
	rts

a1a1_found:
	subi.l	#track_buf_m2,d2                ; offset + 2
	move.w	d2,sig_a1a1_pos
	clr.l	d2
	rts


emit_script_a1a1:	; from: emit_track_script
	move.l	#$50000042,(a2)+                ; opcode $50 $00 $00 $42
	lea	track_buf,a0
	move.w	sig_a1a1_pos,d0
	lea	$0(a0,d0.w),a0
	movea.l	a0,a1
	move.w	#$800,(a2)+                     ; opcode $08: gap literal
	move.w	#$fff,d0                        ; length $fff
	move.w	d0,(a2)+
	move.l	#$f5f5f500,d1                   ; sync $f5 $f5 $f5 + first byte
	move.b	(a0)+,d1
	move.l	d1,(a2)+
	subq.w	#4,d0
	addq.l	#1,a0
a1a1_data_loop:
	move.b	(a0)+,(a2)+
	dbra	d0,a1a1_data_loop
	move.w	#$2c00,(a2)+                    ; opcode $2c: end
	move.w	#$5400,(a4)+                    ; opcode $54: shifted sector write
	move.w	#$37f,d0                        ; $380 bytes
	move.w	d0,(a4)+
a1a1_verify_loop:
	move.b	(a1)+,(a4)+
	dbra	d0,a1a1_verify_loop
	rts


;----------------------------------------------------------------------
; Emit a raw-copy script: the whole track image is stored unchanged
;----------------------------------------------------------------------
emit_raw_track_script:	; from: copy_disk_protected
	movea.l	buffer_ptr,a2
	move.w	#$630,d0                        ; $630 longs
	move.w	d0,(a2)
	addq.l	#6,a2
	move.l	#script_copy_raw_image,(a2)+    ; handler
	lea	track_buf_1,a1                  ; from track_buf + 1
	lsl.w	#2,d0                           ; bytes = longs * 4
	subq.w	#1,d0
	move.l	a2,d7
	bsr.w	copy_raw_sector
	movea.l	d7,a0
	move.w	#$18bf,d0                       ; $18c0 bytes
	bsr.s	fix_sync_bytes
	move.l	a2,d0
	movea.l	buffer_ptr,a2
	move.l	d0,buffer_ptr
	sub.l	a2,d0
	move.w	d0,$2(a2)                       ; part 1 length
	move.w	d0,$4(a2)                       ; total length
	rts


emit_data_check_opcode:	; from: emit_track_script
	move.b	#$58,(a2)+                      ; "X"
	movea.l	dma_pos,a0
	move.b	(a0)+,d1                        ; first data byte
	moveq	#8,d0                           ; 9 bytes equal?
check_opcode_loop:
	move.b	(a0)+,d2
	cmp.b	d1,d2
	dbne	d0,check_opcode_loop
	bne.s	check_opcode_digits
	move.b	#$74,-$1(a2)                    ; "t" $04 "["
	move.b	#$4,(a2)+
	move.b	#$5b,(a2)+                      ; '['
	bra.s	emit_data_check_done

check_opcode_digits:
	movea.l	dma_pos,a0
	moveq	#5,d0                           ; 6 bytes in $30..$3f?
check_digits_loop:
	move.b	(a0)+,d2
	andi.b	#$f0,d2
	cmpi.b	#$30,d2                         ; '0'
	dbne	d0,check_digits_loop
	bne.s	emit_data_check_done
	cmpi.b	#$20,(a0)                       ; followed by space?
	bne.s	emit_data_check_done
	move.b	#$74,-$1(a2)                    ; "t" $07 "X"
	move.b	#$7,(a2)+
	move.b	#$58,(a2)+                      ; 'X'
emit_data_check_done:
	bra.s	emit_sector_id_bytes


;----------------------------------------------------------------------
; Replace $c2, $a1 and $14 bytes in the data by $f5 (write-track sync) when allowed
;----------------------------------------------------------------------
fix_sync_bytes:	; from: emit_leadin_or_gap, emit_raw_track_script
	tst.w	f_no_sync_fix                   ; sync fixing disabled?
	bne.s	fix_sync_ret
	move.b	(a0)+,d1
	cmpi.b	#$c2,d1                         ; $c2
	beq.s	fix_sync_store
	cmpi.b	#$a1,d1                         ; $a1
	beq.s	fix_sync_store
	cmpi.b	#$14,d1                         ; $14 not followed by $15
	bne.s	fix_sync_next
	cmpi.b	#$15,(a0)
	beq.s	fix_sync_next
fix_sync_store:
	move.b	#$f5,-$1(a0)                    ; -> $f5
fix_sync_next:
	dbra	d0,fix_sync_bytes
fix_sync_ret:
	rts


;----------------------------------------------------------------------
; Emit the ID part of a sector item ($68 = current track/side, $20 = full ID)
;----------------------------------------------------------------------
emit_sector_header:	; from: patch_branches, emit_track_script
	cmpi.b	#$fe,$10(a3)                    ; ID mark $fe?
	bne.s	emit_sector_header_full
	move.w	cur_track,d0                    ; track:side
	lsl.w	#8,d0
	move.b	cur_side_b,d0
	cmp.w	$2(a3),d0                       ; matches the current track/side?
	bne.s	emit_sector_header_full
	cmpi.b	#$2,$5(a3)                      ; size code 2?
	bne.s	emit_sector_header_full
	move.b	#$68,(a2)+                      ; opcode $68: ID current track
	move.b	$4(a3),(a2)+                    ; sector
	rts

emit_sector_header_full:
	move.b	#$20,(a2)+                      ; opcode $20: ID field
emit_sector_id_bytes:	; from: emit_data_check_opcode
	move.b	$10(a3),(a2)+                   ; mark byte
	move.l	$2(a3),d0                       ; ID bytes
	tst.w	f_fix_id_bit4
	beq.s	emit_sector_header_done
	andi.l	#$efefefef,d0                   ; clear bit 4 of each ID byte
emit_sector_header_done:
	move.l	d0,(a2)+
	rts


; 68000 code patterns searched for in the copied data (protection checks that are
; patched while copying):
;   pat_move_a1: move.b #$a1,d6 / move.w #2,d0 / bsr.w
;   pat_cmpi_fb: cmpi.b #$fb,(a0)+ / bne.s / clr.w d6 / move.b (a0)+,d6 / move.w d6,..
;   pat_cmp_loop: cmp.b (a6)+,d0 / bne.s / adda.w (a5)+,a0 / dbra d5 / moveq #1,d0 ...
;   pat_cmp_sequence: moveq #5,d5 / move.l (a3)+,d1 / cmp.l $54(a4),d1 / bne.s ...
;   pat_t6s10: move.b (a2),(a0) / sub.l d0,$10c8 / move.w #$1f40,d0 / dbra
;   pat_t2s2: clr.w $ff8240 / jmp $10000
pat_move_a1:	; from: patch_branches
	dc.w	$0000,$0025,$1c3c,$00a1,$303c,$0002,$6100,$0188
pat_cmpi_fb:	; from: patch_branches
	dc.w	$0c18,$00fb,$661a,$4246,$1c18,$33c6
pat_bset:	; from: patch_branches
	dc.w	$01e9,$52ef,$6b18,$00a1,$676f,$0c18,$00c6,$6600
pat_cmpi_a1:	; from: patch_branches
	dc.w	$0c18,$67a1,$6600,$0176,$4207,$45f9

compare_3_longs:	; from: patch_branches
	moveq	#2,d2                           ; 3 longs
	bra.s	compare_longs_loop


compare_4_longs:	; from: patch_branches
	moveq	#3,d2                           ; 4 longs
compare_longs_loop:	; from: compare_3_longs
	cmpm.l	(a1)+,(a2)+
	dbne	d2,compare_longs_loop
	rts


;----------------------------------------------------------------------
; On track 3 search the copied data for timing loops and patch them
;----------------------------------------------------------------------
patch_track3:	; from: emit_track_script
	cmpi.w	#$3,cur_track                   ; track 3?
	bne.s	patch_track3_ret
	movea.l	a2,a1
	movem.l	a0,-(sp)
	movea.l	buffer_ptr,a0                   ; from buffer start to script end
	bsr.w	patch_timing_scan
	movem.l	(sp)+,a0
patch_track3_ret:
	rts

pat_cmp_loop:	; from: patch_fffb_check
	dc.w	$b01e,$66ea,$d0dd,$51cd,$fff4,$7001,$4240,$601a
	dc.w	$4bfa,$001c,$4dfa,$0028

;----------------------------------------------------------------------
; Patch a protection check that uses move.b -5(a0),d0 (opcode $1028fffb)
;----------------------------------------------------------------------
patch_fffb_check:	; from: copy_disk_protected
	tst.w	f_patch_fffb
	beq.s	patch_fffb_ret
	movea.l	buffer_start,a0
	move.l	buffer_ptr,d2
	move.l	#$1028fffb,d1                   ; move.b -5(a0),d0
	subq.l	#2,a0
patch_fffb_scan:
	addq.l	#2,a0                           ; scan the copied data
	move.l	(a0),d0
	cmp.l	d0,d1
	beq.s	patch_fffb_match
	cmpa.l	d2,a0
	bcs.s	patch_fffb_scan
patch_fffb_ret:
	rts

patch_fffb_match:
	lea	pat_cmp_loop,a2                 ; pat_cmp_loop
	movea.l	a0,a1
	addq.l	#4,a1
	moveq	#4,d0
patch_fffb_compare:
	cmpm.w	(a1)+,(a2)+                     ; compare 5 words
	dbne	d0,patch_fffb_compare
	bne.s	patch_fffb_scan
	lea	-$e(a0),a1                      ; look $e back
	cmpm.l	(a1)+,(a2)+
	beq.s	patch_fffb_check_z
	cmpi.b	#$20,-$1(a1)                    ; or ends with $20
patch_fffb_retry:
	bne.s	patch_fffb_scan
patch_fffb_check_z:
	cmpi.b	#$7a,(a1)                       ; "z"?
	bne.s	patch_fffb_retry
	addq.l	#2,a1
	cmpm.l	(a1)+,(a2)+
	beq.s	patch_fffb_check_0
	cmpi.b	#$24,-$1(a1)                    ; or ends with "$"
	bne.s	patch_fffb_retry
patch_fffb_check_0:
	cmpm.l	(a1)+,(a2)+
	beq.s	patch_fffb_nop
	cmpi.b	#$30,-$1(a1)                    ; or ends with "0"
	bne.s	patch_fffb_retry
	move.b	#$18,-$b(a0)                    ; patch: $18 at -$b, $0d at -$f
	move.b	#$d,-$f(a0)
	bra.s	patch_fffb_done

patch_fffb_nop:
	move.w	#$4e71,$6(a0)                   ; nop at +6
patch_fffb_done:
	clr.w	f_patch_fffb
	rts


;----------------------------------------------------------------------
; Patch timing loops that read _hz_200 ($4ba): move.l $4ba.w,d3 / move.w d3,(a0)+
; / dbra / rts are replaced by move.w #$3535,d0 or d3 and nop
;----------------------------------------------------------------------
patch_timing_loops:	; from: copy_disk_protected
	tst.w	f_unformatted                   ; unformatted track seen?
	beq.s	patch_timing_ret
	movea.l	buffer_start,a0
	movea.l	buffer_ptr,a1

patch_timing_scan:	; from: patch_track3
	subq.l	#2,a0
	move.l	#$263804ba,d0                   ; move.l $4ba.w,d3
	move.l	#$30c351ca,d1                   ; move.w d3,(a0)+ / dbra
	move.l	#$fffc4e75,d2                   ; dbra tail / rts
	move.l	#$26390000,d7                   ; move.l $4ba,d3 (absolute long)
	move.w	#$4ba,d6                        ; $4ba
	move.l	#$20390000,d4                   ; move.l $4ba,d0
	move.l	#$30c051ca,d5                   ; move.w d0,(a0)+ / dbra
patch_timing_loop:
	addq.l	#2,a0                           ; scan word by word
	cmp.l	(a0),d0                         ; move.l $4ba.w,d3?
	beq.s	patch_timing_match
	cmp.l	(a0),d7                         ; move.l $4ba,d3?
	beq.s	patch_timing_alt
	cmp.l	(a0),d4                         ; move.l $4ba,d0?
	beq.s	patch_timing_alt
patch_timing_next:
	cmpa.l	a1,a0
	bcs.s	patch_timing_loop
patch_timing_ret:	; from: patch_timing_loops
	rts

patch_timing_match:
	cmp.l	$4(a0),d1                       ; followed by move.w d3,(a0)+ / dbra?
	bne.s	patch_timing_next
	cmp.l	$8(a0),d2                       ; and dbra tail / rts?
	bne.s	patch_timing_next
patch_timing_context:
	cmpi.w	#$2079,-$6(a0)                  ; movea.l abs.l,a0 before?
	beq.s	patch_timing_343c
	cmpi.w	#$206e,-$4(a0)                  ; movea.l (a6),a0 before?
	bne.s	patch_timing_next
	cmpi.w	#$243c,-$a(a0)                  ; move.l #,d2 before?
	bne.s	patch_timing_next
	beq.s	patch_timing_d3
patch_timing_343c:
	cmpi.w	#$343c,-$a(a0)                  ; move.w #,d2 before?
	bne.s	patch_timing_243c
	move.l	#$303c3535,(a0)                 ; replace by move.w #$3535,d0
	bra.s	patch_timing_nop

patch_timing_243c:
	cmpi.w	#$243c,-$c(a0)                  ; move.l #,d2 at -$c?
	bne.s	patch_timing_next
patch_timing_d3:
	move.l	#$363c3535,(a0)                 ; replace by move.w #$3535,d3
	cmp.w	$4(a0),d6                       ; followed by $4ba?
	bne.s	patch_timing_next
patch_timing_nop:
	move.w	#$4e71,$4(a0)                   ; nop
	bra.s	patch_timing_next

patch_timing_alt:
	cmp.w	$4(a0),d6                       ; absolute $4ba?
	bne.s	patch_timing_next
	cmp.l	$6(a0),d1                       ; move.w d3,(a0)+ / dbra?
	beq.s	patch_timing_alt2
	cmp.l	$6(a0),d5                       ; move.w d0,(a0)+ / dbra?
	bne.s	patch_timing_next
patch_timing_alt2:
	cmp.l	$a(a0),d2                       ; dbra tail / rts?
	bne.s	patch_timing_next
	bra.s	patch_timing_context

pat_cmp_sequence:	; from: patch_cmp_sequence
	dc.w	$7a05,$221b,$b2ac,$0054,$6610,$b2ac,$00a8,$660a
	dc.w	$b29c,$6606,$51cd,$ffec

;----------------------------------------------------------------------
; Patch the pat_cmp_sequence check on track 64+ with two nops
;----------------------------------------------------------------------
patch_cmp_sequence:	; from: copy_disk_protected
	cmpi.b	#$4f,cur_track_b                ; track 79?
	bne.s	patch_seq_ret
	cmpi.w	#$40,num_sectors                ; at least 64 sectors?
	bcs.s	patch_seq_ret
	cmpi.l	#$f0f1f2f3,sector_buf_8         ; sector data starts with $f0f1f2f3 $f4f5f6f7
	bne.s	patch_seq_ret
	cmpi.l	#$f4f5f6f7,sector_buf_c
	bne.s	patch_seq_ret
	movea.l	buffer_start,a0
	subq.l	#2,a0
patch_seq_scan:
	addq.l	#2,a0
	cmpa.l	buffer_ptr,a0
	bcc.s	patch_seq_ret
	moveq	#5,d0                           ; 6 longs
	lea	pat_cmp_sequence,a1
	movea.l	a0,a2
patch_seq_compare:
	cmpm.l	(a2)+,(a1)+
	dbne	d0,patch_seq_compare
	bne.s	patch_seq_scan
	move.w	#$4e71,$8(a0)                   ; nop the two bne.s
	move.w	#$4e71,$e(a0)
	bra.s	patch_seq_scan

patch_seq_ret:
	rts


;----------------------------------------------------------------------
; Patch bne.s $20 / bne.s $7e branches that follow the pat_* code patterns
;----------------------------------------------------------------------
patch_branches:	; from: emit_track_script
	movem.l	a2,-(sp)
	movea.l	buffer_start,a0
	move.w	#$6620,d0                       ; bne.s +$20
	move.w	#$667e,d1                       ; bne.s +$7e
patch_br_scan:
	cmp.w	(a0),d0
	beq.s	patch_br_6620
patch_br_scan2:
	cmp.w	(a0)+,d1
	beq.s	patch_br_667e
patch_br_next:
	cmpa.l	buffer_ptr,a0
	bcs.s	patch_br_scan
	bra.s	patch_br_emit

patch_br_6620:
	movea.l	a0,a1
	addq.l	#2,a1
	lea	pat_cmpi_fb,a2                  ; pat_cmpi_fb after it?
	bsr.w	compare_3_longs
	beq.s	patch_br_6620_apply
	lea	-$10(a0),a1
	lea	pat_move_a1,a2                  ; pat_move_a1 $10 before it?
	bsr.w	compare_4_longs
	bne.s	patch_br_scan2
patch_br_6620_apply:
	move.b	#$f2,$1(a0)                     ; bne.s +$20 -> bne.s -$e
	bra.s	patch_br_scan2

patch_br_667e:
	movea.l	a0,a1
	lea	pat_cmpi_a1,a2                  ; pat_cmpi_a1 at it?
	bsr.w	compare_3_longs
	beq.s	patch_br_667e_apply
	lea	-$12(a0),a1
	lea	pat_bset,a2                     ; pat_bset $12 before it?
	bsr.w	compare_4_longs
	bne.s	patch_br_next
patch_br_667e_apply:
	move.w	#$98fa,-$2(a0)                  ; word before bne.s $7e -> $98fa
	bra.s	patch_br_next

patch_br_emit:
	movem.l	(sp)+,a2
	move.w	#$5c00,(a2)+                    ; opcode $5c: long track prep
	clr.l	d0
	move.b	$4(a3),d0                       ; sector:track
	swap	d0
	move.b	$2(a3),d0
	move.l	d0,(a2)+
	bsr.w	emit_sector_header              ; ID item
	move.w	#$2800,(a2)+                    ; opcode $28: gap
	move.l	#$15b10bff,(a2)+                ; run list: 21 x $b1, 11 x $ff, end
	clr.w	(a2)+
	move.w	#$20fe,(a2)+                    ; opcode $20: ID $fe
	moveq	#3,d0                           ; $00 $00 $00 $03
	move.l	d0,(a2)+
	move.w	#$6000,(a4)+                    ; opcode $60: long track write
	rts


;----------------------------------------------------------------------
; Copy the lead-in gap before the first sector when it contains sync bytes
;----------------------------------------------------------------------
emit_pregap_copy:	; from: emit_track_script
	cmpi.w	#$9,num_sectors                 ; fewer than 9 sectors?
	bcs.w	pregap_ret
	lea	sector_list,a3
	tst.w	$c(a3)                          ; first sector has data?
	bne.w	pregap_ret
	clr.l	d0
	move.w	$a(a3),d0
	cmpi.w	#$50,d0                         ; first ID at $50..$ff?
	bcs.s	pregap_ret
	cmpi.w	#$100,d0
	bcc.s	pregap_ret
	move.w	$1c(a3),d1                      ; second ID offset
	sub.w	d0,d1
	bclr	#$0,d1
	cmpi.w	#$250,d1                        ; distance $250..$37f
	bcs.s	pregap_ret
	cmpi.w	#$380,d1
	bcc.s	pregap_ret
	lea	track_buf,a0
	subq.w	#3,d1                           ; length - 3
	move.w	d1,d4
	subi.w	#$17,d1                         ; scan length
	lea	track_buf,a0
	adda.l	d0,a0
	movea.l	a0,a1
	lea	$a(a0),a0                       ; start 10 bytes after the ID
pregap_scan_loop:
	move.b	(a0)+,d2
	cmpi.b	#$f5,d2                         ; sync byte $f5..$f7?
	bcs.s	pregap_scan_next
	cmpi.b	#$f8,d2
	bcc.s	pregap_scan_next
	bra.s	pregap_store

pregap_scan_next:
	dbra	d1,pregap_scan_loop
	bra.s	pregap_ret

pregap_store:
	move.w	#$5400,(a4)+                    ; opcode $54 (verify part): raw bytes
	move.w	d4,(a4)+
	addq.l	#3,a1                           ; skip 3 bytes
pregap_copy_loop:
	move.b	(a1)+,(a4)+
	dbra	d4,pregap_copy_loop
	move.w	$a(a3),d0                       ; first ID offset
	bclr	#$0,d0
	move.w	d0,pregap_pos
pregap_ret:
	rts


;----------------------------------------------------------------------
; Flag a track whose gap after the first ID is 24 identical bytes
;----------------------------------------------------------------------
detect_uniform_gap:	; from: emit_track_script
	clr.w	f_uniform_gap
	tst.w	f_fix_id_bit4                   ; ID bit 4 fixed?
	bne.s	uniform_gap_ret
	lea	sector_list,a0
	tst.w	(a0)                            ; first sector flags 0?
	bne.s	uniform_gap_ret
	move.w	$a(a0),d0
	lea	track_buf,a0
	lea	$a(a0,d0.w),a0                  ; bytes after the ID
	moveq	#23,d0                          ; 24 equal bytes?
	move.b	(a0)+,d1
uniform_gap_loop:
	cmp.b	(a0)+,d1
	dbne	d0,uniform_gap_loop
	bne.s	uniform_gap_ret
	st	f_uniform_gap
uniform_gap_ret:
	rts


;----------------------------------------------------------------------
; Emit the lead-in gap item (special position in leadin_special_pos)
;----------------------------------------------------------------------
emit_leadin_gap:	; from: emit_track_script
	lea	track_buf,a0
	movea.l	a0,a1
	lea	sector_list,a3
	move.l	a2,d7                           ; remember script position
	bsr.w	emit_leadin_or_gap
	clr.l	d0
	move.w	leadin_special_pos,d0           ; special position set?
	beq.s	leadin_ret
	cmpi.w	#$32,d0                         ; in $32..$ff?
	bcs.s	leadin_none
	cmpi.w	#$100,d0
	bcc.s	leadin_none
	move.w	$a(a3),d1                       ; distance to first ID
	sub.w	d0,d1
	cmpi.w	#$100,d1                        ; in $60..$ff?
	bcc.s	leadin_none
	cmpi.w	#$60,d1
	bcs.s	leadin_none
	movea.l	d0,a0
	adda.l	#track_buf_4,a0                 ; track_buf + 4 + position
	moveq	#62,d2                          ; 63 bytes
leadin_scan_loop:
	move.b	(a0)+,d1
	cmpi.b	#$f5,d1                         ; sync byte $f5..$f7?
	bcs.s	leadin_scan_next
	cmpi.b	#$f8,d1
	bcs.s	leadin_found
leadin_scan_next:
	dbra	d2,leadin_scan_loop
	bra.s	leadin_none

leadin_found:
	cmpi.w	#$42,d0                         ; position < $42?
	bcc.s	leadin_copy
	movea.l	d7,a0
	st	$1(a0)                          ; mark the gap item
	move.w	d0,d1                           ; position + 16
	addq.w	#8,d1
	addq.w	#8,d1
	move.w	d1,leadin_special_pos
leadin_copy:
	movea.l	d0,a0
	adda.l	#track_buf_3,a0                 ; track_buf + 3 + position
	move.w	$a(a3),d1
	sub.w	d0,d1                           ; length to the first ID
	bclr	#$0,d1
	subq.w	#3,d1
	move.w	#$5400,(a4)+                    ; opcode $54: raw bytes
	move.w	d1,(a4)+
leadin_copy_loop:
	move.b	(a0)+,(a4)+
	dbra	d1,leadin_copy_loop
	bra.s	leadin_ret

leadin_none:
	clr.w	leadin_special_pos
leadin_ret:
	rts


emit_scheme_1b_data:	; from: emit_track_script
	tst.w	f_scheme_1b                     ; scheme 1b?
	beq.s	scheme_1b_data_ret
	cmpi.b	#$1b,(a3)                       ; flags $1b?
	bne.s	scheme_1b_data_ret
	cmpi.w	#$b,-$2(a2)                     ; length 11?
	bne.s	scheme_1b_data_ret
	subq.w	#1,-$2(a2)                      ; length 10, bit 7
	bset	#$7,-$3(a2)
	move.w	#$e295,(a2)+                    ; $e295 and 8 zero bytes
	clr.l	(a2)+
	clr.l	(a2)+
scheme_1b_data_ret:
	rts

starter_gap:	; from: emit_gap_after_id
	dc.b	'NNNNNNNNNNNNN STARTER '
dat_29bc:
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

emit_gap_after_id:	; from: emit_track_script
	tst.w	f_fix_id_bit4                   ; ID bit 4 fixed?
	bne.w	gap_after_id_special
	bsr.w	check_f0f7_sector               ; $f0f1f2f3 sector?
	bne.s	gap_after_id_scan
	lea	starter_gap,a1                  ; STARTER gap text
	bra.s	gap_after_id_emit

gap_after_id_scan:
	move.w	$a(a3),d0                       ; gap after the ID in the track
	lea	track_buf,a0
	lea	$a(a0,d0.w),a0
	movea.l	a0,a1
	tst.w	f_uniform_gap                   ; uniform gap?
	beq.s	gap_after_id_count
	cmpa.l	#sector_list,a3                 ; first sector?
	beq.s	gap_after_id_emit
gap_after_id_count:
	addq.l	#1,a0                           ; count the byte changes in 26 bytes
	clr.w	d2
	moveq	#24,d0
	move.b	(a0)+,d1
gap_after_id_loop:
	cmp.b	(a0)+,d1
	dbne	d0,gap_after_id_loop
	beq.s	gap_after_id_check
	addq.w	#1,d2
	move.b	-$1(a0),d1
	bra.s	gap_after_id_loop

gap_after_id_check:
	tst.w	d2                              ; no changes?
	beq.s	gap_after_id_emit
	cmpi.w	#$5,d2                          ; fewer than 5?
	bcs.s	gap_after_id_special
gap_after_id_emit:
	move.w	#$800,(a2)+                     ; opcode $08: gap literal
	btst	#$4,(a3)                        ; no data field?
	beq.s	gap_after_id_34
	tst.w	f_scheme_1b                     ; scheme 1b?
	bne.s	gap_after_id_zeros
	move.w	$c(a3),d0                       ; gap length = data - ID - 11
	sub.w	$a(a3),d0
	subq.w	#8,d0
	subq.w	#2,d0
	subq.w	#1,d0
	move.w	d0,d1
	move.w	d0,(a2)+
	bra.s	gap_after_id_copy

gap_after_id_34:
	moveq	#33,d0                          ; 34 bytes
	move.w	d0,d1
	move.w	d0,(a2)+
gap_after_id_copy:
	move.b	(a1)+,(a2)+                     ; copy from the track
	dbra	d0,gap_after_id_copy
	btst	#$0,d1                          ; odd length?
	bne.s	gap_after_id_ret
	move.b	#$10,(a2)+                      ; pad byte
	bra.s	gap_after_id_ret

gap_after_id_special:
	bsr.w	emit_id_data_gap                ; generated gap
gap_after_id_ret:
	rts

gap_after_id_zeros:
	moveq	#11,d0                          ; 12 zero bytes
	move.w	d0,(a2)+
gap_zeros_loop:
	clr.b	(a2)+
	dbra	d0,gap_zeros_loop
	rts


emit_dup_sector_timing:	; from: emit_track_script
	lea	sector_list,a3
dup_timing_loop:
	cmpi.b	#$1,$1(a3)                      ; first of duplicates?
	bne.w	dup_timing_next
	clr.l	d1
	move.b	$2(a3),d1                       ; track
	bsr.w	fdc_set_track_reg
	movea.l	a4,a5
	move.w	#$3000,(a4)+                    ; opcode $30: timed sector write
	move.b	$4(a3),d1                       ; sector, track
	move.b	d1,(a4)+
	move.b	$2(a3),(a4)+
	clr.w	(a4)+                           ; count, filled in below
	move.l	a4,d0                           ; DMA address = after the item
	move.w	#$84,$2(a6)                     ; DMA mode: FDC sector register
	move.w	d1,(a6)                         ; sector register
	bsr.w	dma_set_address
	bsr.w	dma_read_mode
	tst.w	f_dup_scheme                    ; duplicate scheme?
	beq.s	dup_timing_measure
	move.w	#$80,(a6)                       ; two Read Sector
	bsr.w	fdc_wait_status
	move.w	#$80,(a6)                       ; FDC Read Sector
	bsr.w	fdc_wait_status
	addq.b	#2,$1(a5)                       ; count = 2
	bra.s	dup_timing_store

dup_timing_measure:
	move.w	#$d4,(a6)                       ; FDC Force Interrupt on index pulse
	moveq	#-1,d0                          ; wait for the index pulse
dup_wait_index:
	btst	#$5,$fffa01                     ; MFP GPIP, FDC/HDC interrupt (low = done)
	dbeq	d0,dup_wait_index
	move.w	#$80,(a6)                       ; FDC Read Sector
	move.w	#$ad00,d0                       ; timeout
dup_count_loop:
	btst	#$5,$fffa01                     ; wait until the sector was read
	dbeq	d0,dup_count_loop
	bne.s	dup_timing_store
	move.w	#$80,(a6)                       ; read again
	addq.b	#1,$1(a5)                       ; count++
	bra.s	dup_count_loop

dup_timing_store:
	move.w	#$d0,(a6)                       ; FDC Force Interrupt
	bsr.w	dma_get_address                 ; length of the data read
	movea.l	d0,a4
	sub.l	a5,d0
	move.w	d0,$4(a5)                       ; store the length
dup_timing_next:
	lea	$12(a3),a3
	cmpa.l	sector_list_end,a3
	bne.w	dup_timing_loop
	rts


;----------------------------------------------------------------------
; Sector length from the size code in d0 -> d0 (128/256/512/1024)
;----------------------------------------------------------------------
sector_length:	; from: detect_scheme_c, calc_sector_gaps, scan_track_sectors
	move.l	a0,-(sp)
	lea	sector_sizes,a0
	andi.w	#$3,d0                          ; size code 0..3
	lsl.w	#1,d0
	move.w	$0(a0,d0.w),d0
	movea.l	(sp)+,a0
sector_length_ret:	; from: emit_inter_sector_gap
	rts


;----------------------------------------------------------------------
; Emit the gap before the first ID field
;----------------------------------------------------------------------
emit_leadin_or_gap:	; from: emit_leadin_gap
	clr.w	leadin_special_pos
	clr.w	pregap_pos
	clr.w	f_scheme_0b09
	tst.w	f_fix_id_bit4                   ; ID bit 4 fixed?
	bne.s	leadin_default
	clr.l	d0
	moveq	#8,d0                           ; gap 8
	cmpi.w	#$5,gap_size                    ; gap size < 5?
	bcs.w	leadin_emit_gap
	moveq	#53,d0                          ; gap 53
	tst.w	f_uniform_gap                   ; uniform gap?
	bne.w	leadin_emit_gap
	move.w	$a(a3),d0                       ; first ID offset
	tst.w	f_ids_rotated                   ; IDs rotated?
	beq.s	leadin_check_size
	moveq	#4,d0                           ; gap 4
leadin_check_size:
	bclr	#$0,d0
	cmpi.b	#$ff,(a3)                       ; ID not from the list?
	beq.s	leadin_size_class
	btst	#$7,(a3)                        ; special?
	beq.s	leadin_size_class
	cmpi.w	#$48,d0                         ; at least $48?
	bcs.s	leadin_default
leadin_size_class:
	cmpi.w	#$f,d0                          ; less than 15?
	bcs.s	leadin_emit_gap
	cmpi.w	#$40,d0                         ; less than $40: copy raw
	bcs.s	leadin_copy_raw
	cmpi.w	#$60,d0                         ; $60 or more: copy raw
	bcc.s	leadin_copy_raw
	lea	track_buf,a0                    ; count byte changes before the ID
	adda.l	d0,a0
	subq.l	#1,a0
	clr.l	d1
	move.w	$a(a3),d2
	subq.w	#3,d2
	move.b	-(a0),d4
leadin_run_loop:
	cmp.b	-(a0),d4
	dbne	d2,leadin_run_loop
	beq.s	leadin_run_check
	addq.b	#1,d1
	move.b	(a0),d4
	tst.w	d2
	bpl.s	leadin_run_loop
leadin_run_check:
	cmpi.b	#$4,d1                          ; fewer than 4?
	bcc.s	leadin_copy_raw
leadin_default:
	moveq	#72,d0                          ; gap 72
	bra.s	leadin_emit_gap

leadin_copy_raw:
	subq.w	#1,d0
	move.w	#$800,(a2)+                     ; opcode $08: gap literal, d0 bytes
	move.w	d0,(a2)+
	movem.l	d0/a2,-(sp)
	bsr.w	copy_raw_sector                 ; copy raw (with scheme handling)
	movem.l	(sp)+,d0/a0
	bra.w	fix_sync_bytes

leadin_emit_gap:
	move.w	#$2800,(a2)+                    ; opcode $28: gap
	moveq	#60,d1                          ; max 60
	bra.w	gap_emit_count


;----------------------------------------------------------------------
; Emit the gap between an ID field and its data field
;----------------------------------------------------------------------
emit_id_data_gap:	; from: emit_gap_after_id
	move.w	#$2800,(a2)+                    ; opcode $28: gap
	clr.l	d1
	move.w	$a(a3),d1                       ; ID offset + 10
	addi.l	#track_buf,d1
	addq.l	#4,d1
	addq.l	#6,d1
	movea.l	d1,a1
	cmpi.b	#$f7,(a1)                       ; CRC byte there?
	bne.s	id_data_gap_normal
	move.w	#$8,(a2)+                       ; gap 8 then 0, then another gap
	clr.w	(a2)+
	move.w	#$2800,(a2)+
	move.w	$c(a3),d0                       ; data offset - 1
	subq.w	#1,d0
	bra.s	id_data_gap_emit

id_data_gap_normal:
	move.w	$c(a3),d0
id_data_gap_emit:
	sub.w	$a(a3),d0                       ; gap = data - ID - 10
	subi.w	#$a,d0
	moveq	#22,d1                          ; max 22
	bra.s	gap_emit_count


;----------------------------------------------------------------------
; Emit the gap between a data field and the next ID field
;----------------------------------------------------------------------
emit_inter_sector_gap:	; from: emit_track_script
	move.w	$a(a3),d0                       ; ID offset - gap start
	sub.w	$8(a3),d0
	beq.w	sector_length_ret               ; no gap
	move.w	#$2800,(a2)+                    ; opcode $28: gap
	cmpa.l	last_sector,a3                  ; last sector?
	beq.s	inter_gap_size
	btst	#$4,$12(a3)                     ; next sector: no data?
	bne.s	inter_gap_dup_check
	btst	#$2,$12(a3)                     ; next sector fuzzy?
	beq.s	inter_gap_dup_check
	cmpi.b	#$3,$13(a3)                     ; ordinal < 3?
	bcs.s	inter_gap_32
inter_gap_dup_check:
	btst	#$0,(a3)                        ; duplicate ID?
	beq.s	inter_gap_size
	btst	#$0,-$12(a3)                    ; previous also duplicate?
	beq.s	inter_gap_size
	cmpi.w	#$20,d0                         ; gap < $20?
	bcc.s	inter_gap_size
inter_gap_32:
	moveq	#32,d0                          ; gap 32
	move.w	d0,d1
	bra.s	gap_emit_count

inter_gap_size:
	move.w	gap_size,d1                     ; gap_size
	cmpi.w	#$5,d1                          ; 5 or more: use as is
	bcc.s	gap_emit_count
	move.w	d1,d0
	tst.w	f_sync_in_data                  ; sync bytes in data?
	beq.s	gap_emit_count
	moveq	#44,d1                          ; 44
	move.w	$c(a3),d2                       ; data - ID
	sub.w	$a(a3),d2
	cmp.w	d1,d2
	bcc.s	gap_emit_count
	sub.w	d2,d1
	add.w	d1,d0
	bra.s	gap_emit_long

gap_emit_count:	; from: emit_id_data_gap, emit_leadin_or_gap
	cmpi.w	#$e,d0                          ; count < 14: long form
	bcs.s	gap_emit_long
	subi.w	#$c,d0                          ; count - 12
	cmp.w	d1,d0                           ; limit to d1
	bcs.s	gap_emit_short
	move.w	d1,d0
gap_emit_short:
	subq.w	#1,d0
	move.b	d0,-$1(a2)                      ; store count - 1
	rts

gap_emit_long:
	subq.b	#1,d0                           ; count - 1, $ff, 0: run list
	move.b	d0,(a2)+
	move.b	#$ff,(a2)+
	clr.w	(a2)+
	rts


; Message written into the key track when it is rebuilt, stored backwards in
; longwords: "Hi Cracker! Try your best!!"
cracker_msg:	; from: copy_raw_sector
	dc.b	'st!!r be you Tryker!Crac'
dat_2ce0:
	dc.b	$a1,$48,$69,$20,$02,$03,$04,$a0

;----------------------------------------------------------------------
; Copy a raw sector into the script, handling known schemes: on track 80 with a
; large sector the Eurosystems key track is rebuilt, "Kaiser" and $0b09 signatures
; get their own layouts, otherwise the bytes are copied with sync marks fixed.
;----------------------------------------------------------------------
copy_raw_sector:	; from: emit_leadin_or_gap, emit_raw_track_script
	st	f_no_sync_fix                   ; no sync fixing by default
	cmpi.b	#$50,cur_track_b                ; track 80?
	bne.w	copy_raw_scan
	cmpi.w	#$3f0,d0                        ; sector length $3f0..$41f
	bcs.w	copy_raw_scan
	cmpi.w	#$420,d0
	bcc.w	copy_raw_scan
	cmpi.l	#$c2a1c2a1,track_buf_60         ; sync pattern at +$60?
	beq.s	key_track_rebuild
	cmpi.l	#$a1c2a1c2,track_buf_60
	bne.w	copy_raw_scan
key_track_rebuild:
	cmpi.l	#$a1a1a1a1,track_buf_2b0        ; sync at +$2b0?
	bne.s	copy_raw_scan
	movea.l	a2,a0
	move.w	#$407,-$2(a2)                   ; length $407
	moveq	#85,d0                          ; 35 x "U"
	moveq	#34,d1
	bsr.w	fill_bytes_loop
	clr.w	d0                              ; 13 x 0
	moveq	#12,d1
	bsr.w	fill_bytes_loop
	move.w	#$f001,(a0)+                    ; $f0 $01
	lea	copy_raw_sector,a1              ; copy cracker_msg backwards
key_track_msg_loop:
	move.l	-(a1),(a0)+
	cmpa.l	#cracker_msg,a1
	bne.s	key_track_msg_loop
	move.l	#$f6f5f6f5,d1                   ; 150 x $f6f5f6f5
	move.w	#$95,d0
key_track_fill_loop:
	move.l	d1,(a0)+
	dbra	d0,key_track_fill_loop
	move.w	#$b0b1,(a0)+                    ; $b0 $b1
	moveq	#-11,d0                         ; 301 x $f5
	move.w	#$12c,d1
	bsr.w	fill_bytes_loop
	moveq	#78,d0                          ; 31 x $4e
	moveq	#30,d1
	bsr.w	fill_bytes_loop
	clr.w	d0                              ; 21 x 0
	moveq	#20,d1
	bsr.w	fill_bytes_loop
	movea.l	a0,a2
	rts

sig_kaiser:	; from: copy_raw_sector
	dc.b	'Kaiser',0
dat_2d95:
	dc.b	$a1
kaiser_tail:	; from: copy_raw_sector
	dc.b	$20,$53,$20,$f5,$ff,$7d,$fb,$fa,$a5,$b0,$b4,$b9,$b2,$b9,$7a,$fb
	dc.b	$fd,$ff
copy_raw_scan:
	movem.l	d0/a1-a2,-(sp)
kaiser_scan_loop:
	movea.l	a1,a2
	lea	sig_kaiser,a0                   ; search "Kaiser"
	moveq	#5,d1
kaiser_compare_loop:
	cmpm.b	(a2)+,(a0)+
	dbne	d1,kaiser_compare_loop
	beq.s	kaiser_found
	addq.l	#1,a1
	dbra	d0,kaiser_scan_loop
	moveq	#1,d1                           ; not found
	bra.s	kaiser_result

kaiser_found:
	movem.l	(sp)+,d0/a1-a2
	movem.l	d0/a1-a2,-(sp)
	moveq	#-1,d1
kaiser_count_a1:
	addq.l	#1,d1                           ; count $a1 bytes
	cmpi.b	#$a1,(a1)+
	dbeq	d0,kaiser_count_a1
	bne.s	kaiser_result
	subq.l	#1,d0
	cmpi.w	#$5,d1                          ; at least 5
	bcc.s	kaiser_clamp
	moveq	#5,d1
kaiser_clamp:
	cmpi.w	#$2f,d1                         ; at most 47
	bcs.s	kaiser_skip_4e
	moveq	#47,d1
kaiser_skip_4e:
	subq.w	#1,d1
kaiser_skip_loop:
	cmpi.b	#$4e,(a1)+                      ; skip $4e bytes
	dbeq	d0,kaiser_skip_loop
	bne.s	kaiser_result
	moveq	#0,d2
kaiser_count_4e:
	addq.w	#1,d2                           ; count $4e bytes
	cmpi.b	#$4e,(a1)+                      ; 'N'
	dbne	d0,kaiser_count_4e
	beq.s	kaiser_fail
	moveq	#0,d0
	bra.s	kaiser_result

kaiser_fail:
	moveq	#1,d0
kaiser_result:
	movem.l	(sp)+,d0/a1-a2
	bne.s	copy_raw_0b09
	moveq	#40,d0                          ; length = 40 + a1 count + 4e count
	add.w	d1,d0
	add.w	d2,d0
	btst	#$0,d0                          ; make it even
	beq.s	kaiser_emit
	subq.w	#1,d0
	subq.w	#1,d1
kaiser_emit:
	subq.w	#1,d0
	subq.w	#1,d1
	move.w	d0,-$2(a2)                      ; store length
kaiser_gap_loop:
	move.b	#$4e,(a2)+                      ; gap of $4e
	dbra	d1,kaiser_gap_loop
	moveq	#9,d0
kaiser_sync_loop:
	move.b	#$f5,(a2)+                      ; 10 x $f5
	dbra	d0,kaiser_sync_loop
	subq.w	#1,d2
kaiser_gap2_loop:
	move.b	#$4e,(a2)+                      ; gap of $4e
	dbra	d2,kaiser_gap2_loop
	lea	kaiser_tail,a0                  ; kaiser_tail (18 bytes)
	moveq	#17,d0
kaiser_tail_loop:
	move.b	(a0)+,(a2)+
	dbra	d0,kaiser_tail_loop
	moveq	#11,d0                          ; 12 x 0
kaiser_zero_loop:
	clr.b	(a2)+
	dbra	d0,kaiser_zero_loop
	rts

sig_0b09:	; from: copy_raw_sector
	dc.b	$0b,$09,$07,$41,$e9,$8c,$f7,$00
tail_0b09:	; from: copy_raw_sector
	dc.b	$f5,$05,$84,$83,$a0,$f4,$c6,$7b,$84,$8e,$8e,$23,$02,$4c,$86,$fa
	dc.b	$00,$f9,$84,$aa,$81,$41,$0c,$77,$22,$34,$b3,$b4,$97,$20,$b9,$3a
	dc.b	$3b,$b7,$b9,$35,$a7,$00
copy_raw_0b09:
	cmpi.w	#$68,d0                         ; length $68..$8b?
	bcs.s	copy_raw_plain
	cmpi.w	#$8c,d0
	bcc.s	copy_raw_plain
	movem.l	d0/a1-a2,-(sp)
	moveq	#0,d2
scan_0b09_loop:
	movea.l	a1,a2
	lea	sig_0b09,a0                     ; search sig_0b09
	moveq	#6,d1
compare_0b09_loop:
	cmpm.b	(a2)+,(a0)+
	dbne	d1,compare_0b09_loop
	beq.s	result_0b09
	addq.l	#1,a1
	addq.w	#1,d2
	dbra	d0,scan_0b09_loop
	moveq	#1,d1
result_0b09:
	movem.l	(sp)+,d0/a1-a2
	bne.s	copy_raw_plain
	st	f_scheme_0b09                   ; scheme $0b09
	moveq	#107,d0                         ; length = 107 + offset
	add.w	d2,d0
	move.w	d0,-$2(a2)
	tst.w	d2                              ; zero bytes up to the signature
	beq.s	emit_0b09_tail
	move.w	d2,d0
	subq.w	#1,d0
zero_0b09_loop:
	clr.b	(a2)+
	dbra	d0,zero_0b09_loop
emit_0b09_tail:
	moveq	#36,d0                          ; tail_0b09 (37 bytes)
	lea	tail_0b09,a1
tail_0b09_loop:
	move.b	(a1)+,(a2)+
	dbra	d0,tail_0b09_loop
	moveq	#58,d0                          ; 59 x '''
quote_0b09_loop:
	move.b	#$27,(a2)+                      ; '''
	dbra	d0,quote_0b09_loop
	moveq	#11,d0                          ; 12 x 0
zero2_0b09_loop:
	clr.b	(a2)+
	dbra	d0,zero2_0b09_loop
	btst	#$0,d2                          ; odd offset?
	beq.s	ret_0b09
	move.b	#$10,(a2)+                      ; pad byte
ret_0b09:
	rts

copy_raw_plain:
	clr.w	f_no_sync_fix                   ; sync fixing on
	move.b	(a1)+,(a2)+                     ; copy 3 header bytes
	move.b	(a1)+,(a2)+
	move.b	(a1)+,(a2)+
	subq.w	#3,d0
	cmpi.w	#$30,d0                         ; short sector: plain copy
	bcs.s	raw_copy_loop
	movem.l	d0/a1,-(sp)
raw_find_c2_loop:
	move.b	(a1)+,d1
	cmpi.b	#$c2,d1                         ; three $c2 in a row?
	bne.s	raw_find_c2_next
	cmp.b	-$3(a1),d1
	bne.s	raw_find_c2_next
	cmp.b	-$2(a1),d1
	bne.s	raw_find_c2_next
	bra.s	raw_copy_c2

raw_find_c2_next:
	dbra	d0,raw_find_c2_loop
	movem.l	(sp)+,d0/a1
raw_copy_loop:
	move.b	(a1)+,d1
	tst.w	f_no_sync_fix                   ; sync fixing off?
	bne.s	raw_store_byte
	cmpi.b	#$a1,d1                         ; $a1?
	bne.s	raw_check_a1_run
	cmpi.b	#$a1,-$2(a1)                    ; previous also $a1?
	bne.s	raw_store_byte
	moveq	#-11,d1                         ; $f5
	move.b	d1,-$2(a2)                      ; $a1 $a1 -> $f5 $f5
	move.b	d1,-$1(a2)
	cmpi.b	#$a1,-$3(a1)                    ; third $a1?
	beq.s	raw_clear_leadin
	clr.b	-$3(a2)                         ; byte before -> 0
	move.l	a1,d2
	subi.l	#track_buf_3,d2                 ; offset - 3
	move.w	d2,leadin_special_pos           ; lead-in special position
	bra.s	raw_store_byte

raw_check_a1_run:
	cmpi.b	#$a1,-$3(a1)                    ; two $a1 before?
	bne.s	raw_store_byte
	cmpi.b	#$a1,-$2(a1)
	bne.s	raw_store_byte
	st	f_no_sync_fix                   ; stop fixing
	bra.s	raw_store_byte

raw_clear_leadin:
	clr.w	leadin_special_pos
raw_store_byte:
	move.b	d1,(a2)+
	dbra	d0,raw_copy_loop
	rts

raw_copy_c2:
	movem.l	(sp)+,d0/a1
	st	f_no_sync_fix
raw_c2_loop:
	move.b	(a1)+,d1
	cmpi.b	#$c2,d1                         ; $c2?
	bne.s	raw_c2_store
	cmp.b	-$2(a1),d1                      ; previous also $c2?
	bne.s	raw_c2_store
	move.b	#$f6,-$1(a2)                    ; $c2 $c2 -> $f6 $f6
	cmp.b	(a1),d1                         ; third $c2?
	beq.s	raw_c2_f6
	move.b	#$f6,-$2(a2)
raw_c2_f6:
	moveq	#-10,d1                         ; $f6
raw_c2_store:
	move.b	d1,(a2)+
	dbra	d0,raw_c2_loop
	rts

next_id_end_of_track:	; from: find_next_id
	cmpi.b	#$fc,last_mark                  ; last mark was an ID?
	bcc.s	next_id_none
	move.l	(a4),d0                         ; first ID field?
	cmp.l	id_fields,d0
	beq.s	next_id_none
	move.l	(a5),d0                         ; time of the next ID
	sub.w	time_offset,d0
	move.b	#$fe,$10(a3)                    ; ID mark $fe
	clr.l	d4
	rts

next_id_none:
	moveq	#-1,d1                          ; terminate the time list
	move.l	d1,(a5)
	rts


;----------------------------------------------------------------------
; Find the next ID field in the track buffer using the timing list -> d0 = offset
;----------------------------------------------------------------------
find_next_id:	; from: scan_track_sectors
	bsr.w	find_next_mark
	beq.s	next_id_end_of_track            ; no further mark
	cmpi.b	#$fc,d1                         ; ID mark ($fc..$ff)?
	bcs.s	find_next_id
	move.b	d1,$10(a3)                      ; d1 = mark byte
	move.l	(a5),d1                         ; expected time
	sub.w	time_offset,d1                  ; minus offset
	sub.w	d0,d1                           ; minus actual position
	move.w	d1,d2
	bpl.s	next_id_time_check
	neg.w	d1
next_id_time_check:
	cmpi.w	#$30,d1                         ; within $30 bytes?
	bcs.s	next_id_match
	tst.w	first_id_pos                    ; first ID known?
	bne.s	next_id_relative
	cmpi.w	#$800,first_mark_pos            ; first mark before $800?
	bcs.s	next_id_rotate
	cmpi.w	#$80,d1                         ; within $80?
	bcs.s	next_id_match
next_id_rotate:
	bsr.w	rotate_id_list                  ; rotate the ID list
	bne.s	find_next_id                    ; rotated: try again
	moveq	#0,d2
	bra.s	next_id_match

next_id_relative:
	move.w	d0,d4                           ; distance to the first ID
	sub.w	first_id_pos,d4
	cmpi.w	#$400,d4                        ; less than $400: gap check
	bcs.s	next_id_in_gap
	cmpi.w	#$60,d1                         ; within $60?
	bcs.s	next_id_match
	cmpi.w	#$800,d4                        ; less than $800: gap check
	bcs.s	next_id_in_gap
	cmpi.w	#$80,d1                         ; within $80?
	bcs.s	next_id_match
next_id_in_gap:
	tst.w	gap_end                         ; gap end known?
	beq.s	find_next_id
	move.w	d0,d4                           ; position - 4
	subq.w	#4,d4
	cmp.w	gap_end,d4                      ; before the gap end: skip
	bcs.s	find_next_id
	subq.w	#2,d0                           ; ID not in the list: d1 = 5 bytes to copy
	addq.l	#2,a0
	moveq	#5,d1
	rts

next_id_match:
	bsr.s	compare_id_bytes                ; ID bytes match the list?
	beq.s	next_id_accept
	tst.w	d2                              ; time difference negative?
	bmi.s	next_id_ambiguous
	movea.l	a0,a1                           ; look ahead for a better match
	move.w	d0,d4
next_id_lookahead:
	bsr.w	find_next_mark                  ; next mark
	beq.s	next_id_keep
	cmpi.b	#$fc,d1                         ; ID mark?
	bcs.s	next_id_lookahead
	move.l	(a5),d1                         ; time difference
	sub.w	time_offset,d1
	sub.w	d0,d1
	bpl.s	next_id_lookahead_time
	neg.w	d1
next_id_lookahead_time:
	cmpi.w	#$30,d1                         ; within $30?
	bcs.s	next_id_use_lookahead
	tst.w	first_id_pos                    ; first ID known?
	beq.s	next_id_keep
	sub.w	first_id_pos,d0                 ; distance to the first ID
	cmpi.w	#$400,d0                        ; less than $400?
	bcs.s	next_id_keep
	cmpi.w	#$60,d1                         ; within $60?
	bcc.s	next_id_keep
next_id_use_lookahead:
	movea.l	a1,a0                           ; use the look-ahead mark
	bra.w	find_next_id

next_id_keep:
	movea.l	a1,a0                           ; keep the first mark
	move.w	d4,d0
next_id_ambiguous:
	st	f_id_ambiguous                  ; position ambiguous
next_id_accept:
	add.w	d2,time_offset                  ; adjust the time offset
	addq.l	#8,a0                           ; skip the ID bytes
	clr.l	d1                              ; d1 = 0: from the list
	rts


compare_id_bytes:	; from: find_next_id, rotate_id_list
	movea.l	a0,a1                           ; a1 -> ID bytes in the track
	movea.l	a4,a2                           ; a2 -> ID bytes in the list
	subq.w	#2,d0
	addq.l	#2,a1
	move.l	a1,d3                           ; ID end
	addq.l	#4,d3
	cmp.l	dma_pos,d3                      ; beyond the DMA position?
	bcc.s	id_compare_fail
	moveq	#0,d3
id_wildcard_loop:
	move.b	$0(a4,d3.w),d4                  ; wildcard positions
	cmpi.b	#$29,d4                         ; ")"
	beq.s	id_compare_next
	andi.b	#$fe,d4                         ; "R"/"S"
	cmpi.b	#$52,d4                         ; 'R'
	beq.s	id_compare_next
	andi.b	#$fc,d4                         ; $a4..$a7
	cmpi.b	#$a4,d4
	beq.s	id_compare_next
	addq.w	#1,d3
	cmpi.b	#$4,d3                          ; compare 4 bytes
	bne.s	id_wildcard_loop
	bra.s	id_compare_next

id_compare_loop:
	cmpm.b	(a1)+,(a2)+                     ; compare d3+1 bytes
id_compare_next:
	dbne	d3,id_compare_loop
	rts

id_compare_fail:
	clr.l	d3
	rts


rotate_id_list:	; from: find_next_id
	cmpa.l	#sector_buf,a5                  ; first entry?
	bne.s	rotate_fail
	cmpi.w	#$8,d0                          ; position < 8?
	bcc.s	rotate_fail
	cmpi.l	#$ffffffff,$4(a5)               ; only one ID?
	beq.s	rotate_fail
rotate_find_end:
	addq.l	#4,a5                           ; find the end of the list
	addq.l	#6,a4
	cmpi.l	#$ffffffff,(a5)
	bne.s	rotate_find_end
	subq.l	#4,a5
	subq.l	#6,a4
	movem.l	d0-d7/a0-a6,-(sp)
	bsr.s	compare_id_bytes                ; last ID matches?
	movem.l	(sp)+,d0-d7/a0-a6
	bne.s	rotate_reset
	cmpi.w	#$1800,$2(a5)                   ; time >= $1800?
	bcs.s	rotate_reset
	move.l	(a5),-(sp)                      ; save the last entries
	move.l	(a4),-(sp)
	move.w	$4(a4),-(sp)
rotate_shift_loop:
	move.l	-(a5),$4(a5)                    ; shift the lists up by one
	move.l	-(a4),$6(a4)
	move.w	-(a4),$6(a4)
	cmpa.l	#sector_buf,a5
	bne.s	rotate_shift_loop
	move.w	(sp)+,$4(a4)                    ; put the last entries first
	move.l	(sp)+,(a4)
	move.l	(sp)+,(a5)
	st	f_ids_rotated                   ; rotated
	clr.l	d4                              ; d4 = 0: ok
	rts

rotate_reset:
	lea	sector_buf,a5
	lea	id_fields,a4
rotate_fail:
	moveq	#1,d4                           ; d4 = 1: failed
	rts


;----------------------------------------------------------------------
; Flag sectors that contain sync bytes ($f5-$f7) in their ID and number
; duplicated IDs
;----------------------------------------------------------------------
mark_special_sectors:	; from: read_all_sectors
	movem.l	d0-d7/a0-a1,-(sp)
	clr.w	d5                              ; special count
	lea	sector_list,a0
	move.l	a0,d1
special_entry_loop:
	movea.l	a0,a1
	addq.l	#2,a1
	moveq	#3,d0                           ; 4 ID bytes
special_byte_loop:
	cmpi.b	#$f8,(a1)+                      ; ID bytes $f5..$f7?
	bcc.s	special_byte_next
	cmpi.b	#$f5,-$1(a1)
	bcs.s	special_byte_next
	tst.w	f_fix_id_bit4                   ; ID bit 4 fixed?
	bne.s	special_byte_next
	bset	#$7,(a0)                        ; bit 7: special
	addq.w	#4,d5                           ; count * 4
	bra.s	special_entry_next

special_byte_next:
	dbra	d0,special_byte_loop
special_entry_next:
	lea	$12(a0),a0
	cmpa.l	sector_list_end,a0
	bne.s	special_entry_loop
	move.l	a0,d4
	movea.l	d1,a0
	clr.w	f_dup_ids
dup_id_outer:
	move.b	(a0),d0                         ; flags
	andi.b	#$11,d0                         ; duplicate or no data?
	bne.s	dup_id_outer_next
	moveq	#1,d0                           ; ordinal 1
	lea	$12(a0),a1
	move.b	$2(a0),d1                       ; track, sector
	move.b	$4(a0),d2
dup_id_inner:
	cmp.l	a1,d4                           ; end of list?
	beq.s	dup_id_outer_next
	btst	#$4,(a1)                        ; no data field?
	bne.s	dup_id_inner_next
	cmp.b	$2(a1),d1                       ; same track?
	bne.s	dup_id_inner_next
	cmp.b	$4(a1),d2                       ; same sector?
	bne.s	dup_id_inner_next
	st	f_dup_ids                       ; duplicate IDs
	move.b	#$1,$1(a0)                      ; ordinal of the first
	addq.w	#1,d0
	move.b	d0,$1(a1)                       ; ordinal of the duplicate
	bset	#$0,(a0)                        ; bit 0: duplicate
	bset	#$0,(a1)
dup_id_inner_next:
	lea	$12(a1),a1
	bra.s	dup_id_inner

dup_id_outer_next:
	lea	$12(a0),a0
	cmp.l	a0,d4
	bne.s	dup_id_outer
	move.w	d5,special_count
	movem.l	(sp)+,d0-d7/a0-a1
	rts


fix_duplicate_counts:	; from: read_all_sectors
	lea	sector_list,a0
fix_dup_loop:
	cmpi.w	#$ffff,(a0)                     ; ID not from the list?
	beq.s	fix_dup_next
	btst	#$0,(a0)                        ; duplicate?
	beq.s	fix_dup_next
	btst	#$1,(a0)                        ; data mark present?
	beq.s	fix_dup_next
	bclr	#$0,(a0)                        ; clear duplicate bit
	cmpi.b	#$1,$1(a0)                      ; ordinal 1?
	bne.s	fix_dup_clear
	move.b	$2(a0),d1                       ; track, sector
	move.b	$4(a0),d2
	lea	$12(a0),a1
fix_dup_inner:
	cmpa.l	sector_list_end,a1
	beq.s	fix_dup_clear
	cmp.b	$2(a1),d1                       ; same track?
	bne.s	fix_dup_inner_next
	cmp.b	$4(a1),d2                       ; same sector?
	bne.s	fix_dup_inner_next
	btst	#$4,(a1)                        ; no data field?
	bne.s	fix_dup_inner_next
	cmpi.b	#$2,$1(a1)                      ; ordinal >= 2?
	bcs.s	fix_dup_inner_next
	subq.b	#1,$1(a1)                       ; ordinal--
fix_dup_inner_next:
	lea	$12(a1),a1
	bra.s	fix_dup_inner

fix_dup_clear:
	clr.b	$1(a0)                          ; ordinal 0
fix_dup_next:
	lea	$12(a0),a0
	cmpa.l	sector_list_end,a0
	bne.s	fix_dup_loop
	rts


;----------------------------------------------------------------------
; Reset the copy buffer pointer and the displayed side/track
;----------------------------------------------------------------------
init_copy_buffer:	; from: format_disk, copy_disk_protected, copy_disk_normal
	move.l	buffer_start,buffer_ptr         ; buffer_ptr = buffer_start
	moveq	#-1,d0
	move.w	d0,$22(a4)                      ; shown side = -1
	move.w	d0,$24(a4)                      ; shown track = -1

;----------------------------------------------------------------------
; flock = 1, vblsem = 0 (keep the OS away from the floppy)
;----------------------------------------------------------------------
lock_floppy:	; from: read_source_bpb, fdc_error_alert, read_key_track
	move.b	#$1,$43f.w                      ; flock = 1
	clr.w	$452.w                          ; vblsem = 0
	rts


;----------------------------------------------------------------------
; flock = 0, vblsem = 1
;----------------------------------------------------------------------
unlock_floppy:	; from: read_source_bpb, copy_disk_normal, fdc_error_alert, copy_disk_protected, read_key_track
	clr.w	$43e.w                          ; flock = 0
	move.b	#$1,$453.w                      ; vblsem = 1
	clr.w	drives_deselected
	rts


prepare_sector_fill:	; from: copy_disk_normal
	movea.l	$32(a4),a0
	tst.b	(a0)                            ; uniform sector?
	bpl.s	get_sector_buffer
	lea	verify_buf,a1                   ; fill verify_buf with the byte
	move.b	$900(a0),d0                     ; fill byte
	move.w	d0,d1
	lsl.w	#8,d1
	move.b	d0,d1
	move.w	d1,d0
	swap	d1
	move.w	d0,d1
	move.l	a1,d0
	moveq	#127,d2                         ; DMA address = verify_buf
fill_sector_loop:
	move.l	d1,(a1)+
	dbra	d2,fill_sector_loop
	move.w	$26(a4),d1                      ; d1 = sector
	rts


get_sector_buffer:	; from: copy_disk_normal, prepare_sector_fill
	move.w	dp_sector(a4),d1                ; d1 = sector
	move.l	buffer_ptr,d0                   ; d0 = buffer address
	rts


;----------------------------------------------------------------------
; a0 -> sector map entry of the current sector; d0 = 1 when past the map
;----------------------------------------------------------------------
get_sector_map_entry:	; from: copy_disk_normal
	clr.l	d0
	move.w	dp_sector_idx(a4),d0
	sub.w	dp_datrec(a4),d0                ; index - first data sector
	bcc.s	map_entry_found
	clr.l	dp_map_ptr(a4)                  ; boot/FAT/root sectors: always used
	moveq	#1,d0
	rts

map_entry_found:
	lea	sector_list,a0                  ; map entry
	adda.l	d0,a0
	move.l	a0,dp_map_ptr(a4)
	tst.b	(a0)                            ; used?
	rts


;----------------------------------------------------------------------
; If the sector just read consists of one byte value, store that byte at
; map+$900 and flag the map entry (bit 7) so it takes no buffer space
;----------------------------------------------------------------------
compress_uniform_sector:	; from: copy_disk_normal
	movea.l	dp_map_ptr(a4),a0
	move.l	a0,d0
	beq.s	next_buffer_sector              ; no map entry?
	movea.l	buffer_ptr,a1
	move.l	(a1)+,d0                        ; first long
	swap	d0                              ; all 4 bytes equal?
	move.l	d0,d1
	cmp.l	d0,d1
	bne.s	next_buffer_sector
	lsr.w	#8,d1
	cmp.b	d0,d1
	bne.s	next_buffer_sector
	moveq	#126,d1                         ; 127 more longs
uniform_check_loop:
	cmp.l	(a1)+,d0
	dbne	d1,uniform_check_loop
	bne.s	next_buffer_sector
	bset	#$7,(a0)                        ; bit 7: uniform
	move.b	d0,$900(a0)                     ; fill byte at map + $900
	rts

next_buffer_sector:
	addi.l	#$200,buffer_ptr                ; advance buffer by 512
	rts


;----------------------------------------------------------------------
; Convert dp_sector_idx into sector/side/track
;----------------------------------------------------------------------
calc_track_side_sector:	; from: copy_disk_normal
	clr.l	d0
	move.w	dp_sector_idx(a4),d0
	divu.w	dp_spt(a4),d0                   ; index / spt
	swap	d0
	addq.w	#1,d0                           ; sector = remainder + 1
	move.w	d0,dp_sector(a4)
	swap	d0
	ext.l	d0
	divu.w	dp_sides(a4),d0                 ; / sides
	swap	d0
	move.w	d0,dp_side(a4)                  ; side = remainder
	swap	d0
	move.w	d0,dp_track(a4)                 ; track = quotient
	bra.w	check_last_track


;----------------------------------------------------------------------
; Write a track from its script: run the handler to build the image, Write
; Track, optionally create fuzzy bits, run the verify part; up to 3 attempts
;----------------------------------------------------------------------
write_track_from_script:	; from: copy_disk_protected
	movem.l	a4-a5,-(sp)
	clr.w	read_retries                    ; attempt counter
script_write_retry:
	move.w	read_retries,d0
	addq.w	#1,d0
	move.w	d0,read_retries
	cmpi.b	#$3,d0                          ; 3 attempts
	beq.s	script_write_failed
	bsr.w	fill_track_4e                   ; fill the image with $4e
	movea.l	buffer_ptr,a4                   ; script handler
	movea.l	$6(a4),a4
	clr.w	special_count
	clr.l	fuzzy_pos
	jsr	(a4)                            ; build the track image
	bsr.w	fdc_write_track                 ; Write Track
	bsr.w	fdc_wait_result
	btst	#$6,d7                          ; write protected?
	bne.s	script_write_ret
	tst.l	fuzzy_pos                       ; fuzzy bits wanted?
	beq.s	script_run_verify
	bsr.s	write_fuzzy_bits
	bne.s	script_write_failed             ; failed
script_run_verify:
	jsr	(a4)                            ; run the verify part
	bne.s	script_write_retry              ; verify failed: retry
	movem.l	(sp)+,a4-a5

advance_script:	; from: copy_disk_protected
	move.w	dp_track(a4),d1                 ; track register = track
	bsr.w	fdc_set_track_reg
	movea.l	buffer_ptr,a0
	clr.l	d0
	move.w	$4(a0),d0                       ; total length
	adda.l	d0,a0
	move.l	a0,buffer_ptr                   ; next script
	moveq	#0,d0                           ; d0 = 0: ok
	rts

script_write_failed:	; from: write_track_from_script
	clr.l	d7                              ; d7 = $100: DMA error
	move.w	#$100,d7
script_write_ret:	; from: write_track_from_script
	movem.l	(sp)+,a4-a5
	rts

fuzzy_write_fail:	; from: write_fuzzy_bits
	moveq	#-1,d0
	rts


;----------------------------------------------------------------------
; Create fuzzy (weak) bits: wait until the DMA address reaches fuzzy_pos,
; then rapidly toggle the drive select line while the FDC writes
;----------------------------------------------------------------------
write_fuzzy_bits:	; from: write_track_from_script
	move.b	#$6,fuzzy_retries               ; 6 attempts
fuzzy_retry_loop:
	subq.b	#1,fuzzy_retries
	beq.s	fuzzy_write_fail
	bsr.w	fdc_write_track                 ; Write Track again
	bsr.w	wait_dma_change                 ; DMA running?
	bne.s	fuzzy_wait_position
	bsr.w	fdc_abort
	bra.s	fuzzy_retry_loop

fuzzy_wait_position:
	move.w	sr,-(sp)
	ori.w	#$700,sr
	bsr.w	read_psg_port_a                 ; d5 = port A with drives deselected
	move.l	fuzzy_pos,d0                    ; target DMA address
	move.l	d0,d1
	lsr.w	#8,d1                           ; mid byte
	moveq	#-1,d2
	moveq	#2,d3
	moveq	#127,d6                         ; 128 toggles
	lea	$ff8802,a0                      ; PSG data register
	move.l	d5,d4                           ; d4 = port A with the drive selected
	swap	d4
fuzzy_wait_mid:
	cmp.b	$7(a6),d1                       ; wait for the DMA mid byte
	dbeq	d2,fuzzy_wait_mid
	bne.s	fuzzy_verify
fuzzy_wait_low:
	cmp.b	$9(a6),d0                       ; wait for the DMA low byte
	dbeq	d2,fuzzy_wait_low
	bne.s	fuzzy_verify
	nop
	nop
	nop
	nop
	nop
fuzzy_toggle_loop:
	move.b	d5,(a0)                         ; deselect
	nop
	nop
	move.b	d4,(a0)                         ; select
	dbra	d6,fuzzy_toggle_loop            ; toggle drive select 128 times
fuzzy_verify:
	move.w	(sp)+,sr
	bsr.w	fdc_abort                       ; stop the write
	tst.b	verify_flag                     ; verify?
	beq.s	fuzzy_write_ok
	move.l	fuzzy_sector,d1                 ; read the fuzzy sector
	move.l	#read_buf2,d0
	bsr.w	fdc_read_sector
	bsr.w	fdc_wait_status
	btst	#$4,d7                          ; record not found: retry
	bne.w	fuzzy_retry_loop
	moveq	#3,d2                           ; read it twice more
fuzzy_verify_loop:
	subq.w	#1,d2
	beq.w	fuzzy_retry_loop
	move.l	fuzzy_sector,d1
	move.l	#read_buf3,d0
	bsr.w	fdc_read_sector
	bsr.w	fdc_wait_status
	btst	#$4,d7                          ; record not found: read again
	bne.s	fuzzy_verify_loop
	lea	read_buf2,a0                    ; compare the first 16 bytes
	lea	$400(a0),a1
	moveq	#15,d0
fuzzy_compare_loop:
	cmpm.b	(a0)+,(a1)+
	dbne	d0,fuzzy_compare_loop
	beq.s	fuzzy_verify_loop               ; equal: not fuzzy, read again
fuzzy_write_ok:
	clr.l	d0                              ; d0 = 0: ok
	rts


;----------------------------------------------------------------------
; Fill track_buf (6400 bytes) with a long pattern
;----------------------------------------------------------------------
fill_track_f5e295:	; from: rtfi_timeout
	move.l	#$f5e29500,d0                   ; $f5 $e2 $95 $00
	bra.s	fill_track_buf


fill_track_dc:	; from: rtfi_timeout
	move.l	#$dcdcdcdc,d0                   ; $dc fill
	bra.s	fill_track_buf


fill_track_35:	; from: rtfi_timeout
	move.l	#$35353535,d0                   ; $35 fill
	bra.s	fill_track_buf


fill_track_4e:	; from: write_track_from_script, detect_a1a1_scheme
	move.l	#$4e4e4e4e,d0                   ; 'NNNN' gap fill
fill_track_buf:	; from: fill_track_dc, fill_track_35, fill_track_f5e295
	lea	track_buf,a0
	move.w	#$18f,d1                        ; 400 x 16 bytes
fill_track_loop:
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	dbra	d1,fill_track_loop
	rts


;----------------------------------------------------------------------
; Script handlers (address stored at script+6, called with jsr (a4))
;----------------------------------------------------------------------
script_build_image:	; from: emit_track_script
	lea	track_buf,a0                    ; image start
	movea.l	buffer_ptr,a2                   ; script bytes at +$a
	lea	$a(a2),a2
	bsr.w	fdc_wait_status
	bsr.s	script_dispatch                 ; build the image
	lea	script_run_second,a4            ; next call: verify part
	rts

script_copy_raw_image:	; from: emit_raw_track_script
	lea	track_buf,a0                    ; raw copy: d0+1 longs
	movea.l	buffer_ptr,a2
	move.w	(a2),d0                         ; number of longs
	lea	$a(a2),a2
raw_image_copy_loop:
	move.l	(a2)+,(a0)+
	dbra	d0,raw_image_copy_loop
	lea	script_finish,a4                ; next call: finish
	rts

script_run_second:	; from: script_build_image
	clr.w	special_count                   ; a2 = verify part
	movea.l	buffer_ptr,a2
	clr.l	d0
	move.w	(a2),d0                         ; part 1 length
	adda.l	d0,a2
	bsr.w	fdc_wait_status
	bsr.s	script_dispatch                 ; run the verify script
	rts

script_finish:	; from: script_copy_raw_image
	bsr.w	fdc_wait_status
	clr.l	d0                              ; d0 = 0: ok
	rts


;----------------------------------------------------------------------
; Script interpreter: read the opcode byte at (a2), jump through opcode_table
;----------------------------------------------------------------------
script_dispatch:	; from: script_run_second, script_build_image, op_20_id_field, op_70_sync_read_track, op_6c_partial_write_track, op_64_rle_data, ...
	move.w	d1,-(sp)
	lea	opcode_table,a4                 ; opcode_table
	clr.w	d1                              ; opcode byte
	move.b	(a2),d1
	movea.l	$0(a4,d1.w),a4
	move.w	(sp)+,d1
	jmp	(a4)


;----------------------------------------------------------------------
; Script opcodes.  a0 = write position in track_buf, a2 = script pointer.
; Each opcode returns to script_dispatch for the next item or rts with d0
; to end (0 = ok, -1 = error).
;----------------------------------------------------------------------
op_00_sync_mark_fill:	; from: opcode_table
	move.w	(a2)+,d1                        ; parameters: mark, length, first byte
	move.w	(a2)+,d0
	move.w	(a2)+,d2
	move.b	d2,(a0)+                        ; first byte
	move.b	#$f5,(a0)+                      ; two sync bytes
	move.b	#$f5,(a0)+
	move.b	d1,(a0)                         ; mark | $f0
	ori.b	#$f0,(a0)+
	tst.w	d0                              ; length 0?
	bra.s	data_field_body

op_04_fill_words:	; from: opcode_table
	move.w	(a2)+,d1                        ; skip opcode word, d1 = word
	move.w	(a2)+,d1
fill_words_loop:
	move.w	d1,(a0)+                        ; d0+1 words
	dbra	d0,fill_words_loop
	rts

op_08_gap_literal:	; from: opcode_table
	move.w	(a2)+,d1                        ; d1 = opcode:flag, d0 = length - 1
	move.w	(a2)+,d0
	tst.b	d1                              ; flag byte 0: no gap
	beq.s	gap_literal_copy
	moveq	#15,d1
gap_literal_4e_loop:
	move.b	#$4e,(a0)+                      ; 16 x $4e
	dbra	d1,gap_literal_4e_loop
gap_literal_copy:
	move.b	(a2)+,(a0)+                     ; copy d0+1 literal bytes
	dbra	d0,gap_literal_copy
	bra.s	script_dispatch

op_3c_nop_skip:	; from: opcode_table
	nop
op_10_skip:	; from: opcode_table
	addq.l	#1,a2
	bra.s	script_dispatch

op_14_fill_e5:	; from: opcode_table
	move.l	(a2)+,d0                        ; d0 = count
	subq.w	#1,d0
fill_e5_loop:
	move.b	#$e5,(a0)+                      ; $e5 fill
	dbra	d0,fill_e5_loop
	bra.s	script_dispatch

op_18_data_field:	; from: opcode_table
	bsr.w	emit_3_sync                     ; three $f5
	move.w	(a2)+,d1                        ; d1 = flags:mark
	move.b	d1,(a0)
	ori.b	#$f0,(a0)+                      ; mark | $f0
	move.w	(a2)+,d0                        ; d0 = length
data_field_body:	; from: op_00_sync_mark_fill
	beq.s	script_dispatch                 ; length 0?
	subq.w	#1,d0
	btst	#$7,d1                          ; bit 7: data given
	bne.s	data_field_kind
data_field_zero_loop:
	clr.b	(a0)+                           ; zero data
	dbra	d0,data_field_zero_loop
	btst	#$6,d1                          ; bit 6: no 2 trailing zeros
	bne.w	script_dispatch
	clr.b	(a0)+
	clr.b	(a0)+
	bra.w	script_dispatch

data_field_kind:
	btst	#$5,d1                          ; bit 5: fill byte
	beq.s	data_field_copy_loop
	move.w	(a2)+,d2
data_field_fill_loop:
	move.b	d2,(a0)+                        ; fill
	dbra	d0,data_field_fill_loop
data_field_crc:
	btst	#$4,d1                          ; bit 4: CRC
	beq.s	data_field_next
	move.b	#$f7,(a0)+                      ; CRC
data_field_next:
	bra.w	script_dispatch

data_field_copy_loop:
	move.b	(a2)+,(a0)+                     ; copy data from the script
	dbra	d0,data_field_copy_loop
	bra.s	data_field_crc

op_1c_fix_mark_bytes:	; from: opcode_table
	move.w	$2(a2),d0                       ; word 1 = two bytes
	bsr.s	is_mark_byte                    ; low byte a mark byte?
	bne.s	fix_mark_a1
	lsr.w	#8,d0
	bsr.s	is_mark_byte                    ; high byte a mark byte?
	bne.s	fix_mark_a1
	move.b	$2(a2),-$1(a0)                  ; replace the last byte and append one
	move.b	$3(a2),(a0)+
fix_mark_a1:
	move.w	$4(a2),d0                       ; word 2
	addq.l	#6,a2
	cmpi.w	#$ffff,d0                       ; $ffff?
	bne.s	fix_mark_next
	move.b	#$a1,-$8(a0)                    ; $a1 8 bytes back
fix_mark_next:
	bra.w	script_dispatch


is_mark_byte:	; from: op_1c_fix_mark_bytes
	cmpi.b	#$f5,d0
	bcs.s	not_mark_byte
	cmpi.b	#$f8,d0
	bcc.s	not_mark_byte
	rts

not_mark_byte:
	moveq	#0,d1
	rts

op_20_id_field:	; from: op_58_fuzzy_marker, op_44_id_sector_ff, opcode_table
	bsr.w	emit_3_sync                     ; three $f5
	move.w	(a2)+,d0                        ; mark byte
	move.b	d0,(a0)+
	moveq	#3,d0                           ; 4 ID bytes
id_field_copy_loop:
	move.b	(a2)+,(a0)+
	dbra	d0,id_field_copy_loop
id_field_crc:	; from: op_68_id_current_track
	move.b	crc_code,(a0)+                  ; CRC code from the key track
	bra.w	script_dispatch

op_68_id_current_track:	; from: opcode_table
	bsr.w	emit_3_sync                     ; three $f5
	move.b	#$fe,(a0)+                      ; ID mark
	move.b	cur_track_b,(a0)+               ; track
	move.b	cur_side_b,(a0)+                ; side
	move.w	(a2)+,d0                        ; sector from the script
	move.b	d0,(a0)+
	move.b	#$2,(a0)+                       ; size code 2
	bra.s	id_field_crc

op_2c_end:	; from: opcode_table
	addq.l	#2,a2                           ; d0 = 0: end
	clr.l	d0
	rts

op_28_gap:	; from: opcode_table
	move.w	(a2)+,d0                        ; d0 = opcode:count
	tst.b	d0                              ; count 0: run list follows
	bne.s	gap_emit_4e
	bsr.w	emit_run_list
gap_next:
	bra.w	script_dispatch

gap_emit_4e:
	clr.l	d1
	move.b	d0,d1                           ; count
	moveq	#78,d0                          ; $4e gap
	bsr.w	fill_bytes
	moveq	#11,d1                          ; 12 zero bytes
	clr.l	d0
	bsr.w	fill_bytes
	bra.s	gap_next


; Four bytes copied here from the copyright string (expected "EURO")
key_euro:	; from: op_24_write_verify
	dc.b	$00
key_euro_1:	; from: op_24_write_verify
	dc.b	$00
key_euro_2:	; from: op_24_write_verify
	dc.b	$00
key_euro_3:	; from: op_24_write_verify
	dc.b	$00

;----------------------------------------------------------------------
; Opcode $24: write the track and verify each listed sector (item: flags word,
; side/track, length, data), retried up to 5 times
;----------------------------------------------------------------------
op_24_write_verify:	; from: opcode_table
	lea	copyright+4-$1238,a5            ; a5 = copyright - $1178
	move.l	$1238(a5),key_euro              ; key_euro = "EURO"
	movea.l	a2,a5                           ; a5 -> item
	move.b	#$5,verify_retries              ; 5 attempts
wv_sector_loop:
	movea.l	a5,a2
	move.w	(a2)+,d6                        ; item flags
	clr.l	d1
	move.b	$1(a2),d1                       ; side:track
	swap	d1
	move.b	(a2),d1
	addq.l	#2,a2
	clr.l	d2
	move.w	(a2)+,d2                        ; length
	move.l	a2,d0                           ; DMA address = data
	move.l	d0,d4
	move.w	d2,d3
	adda.l	d2,a2                           ; next item
	clr.l	d2
	cmpi.b	#$55,key_euro_1                 ; tamper check: "U"
	bne.s	wv_retry
	btst	#$5,d6                          ; bit 5: deleted data mark
	beq.s	wv_check_key
	moveq	#1,d2                           ; command flag: deleted data
wv_check_key:
	cmpi.b	#$45,key_euro                   ; tamper check: "E"
	bne.w	script_dispatch                 ; wrong: treat as the next opcode
	btst	#$3,d6                          ; bit 3: timed write
	bne.s	wv_write_sector
	bsr.w	fdc_write_sector_flags          ; Write Sector
	bsr.w	fdc_wait_status
	btst	#$4,d7                          ; record not found?
	beq.s	wv_next
wv_retry:
	subq.b	#1,verify_retries               ; attempts--
	beq.s	wv_fail
	tst.w	special_count                   ; special sectors: no retry
	bne.s	wv_next
	bra.s	wv_sector_loop

wv_next:
	bra.w	script_dispatch

wv_fail:
	moveq	#-1,d0                          ; d0 = -1: failed
	rts

wv_write_sector:
	bsr.w	timed_write_sector
	cmpi.b	#$52,key_euro_2                 ; tamper check: "R"
	bne.s	wv_fail
	btst	#$1,d6                          ; bit 1: no verify
	bne.s	wv_done
	swap	d1                              ; d1 = sector:track
	move.l	#read_buf2,d0                   ; read back into read_buf2
	bsr.w	fdc_read_sector
	bsr.w	fdc_wait_status
	btst	#$3,d7                          ; CRC error expected?
	beq.s	wv_retry
	lea	$6(a5),a0                       ; compare with the script data
	move.w	$4(a5),d0
	subq.w	#1,d0
	lea	read_buf2,a1
	cmpi.b	#$4f,key_euro_3                 ; tamper check: "O"
	bne.w	start                           ; wrong: restart the program
wv_compare_loop:
	cmpm.b	(a0)+,(a1)+
	dbne	d0,wv_compare_loop
	bne.s	wv_retry
	btst	#$2,d6                          ; bit 2: read twice
	beq.s	wv_done
	moveq	#2,d2
wv_reread_loop:
	subq.w	#1,d2                           ; read again into read_buf3
	beq.s	wv_retry
	swap	d1
	move.l	#read_buf3,d0
	bsr.w	fdc_read_sector
	bsr.w	fdc_wait_status
	btst	#$4,d7                          ; record not found?
	bne.s	wv_reread_loop
	lea	read_buf2,a0                    ; compare 16 bytes at the data length
	clr.l	d0
	move.w	$4(a5),d0
	adda.l	d0,a0
	lea	$400(a0),a1
	moveq	#15,d0
wv_reread_compare:
	cmpm.b	(a0)+,(a1)+
	dbne	d0,wv_reread_compare
	beq.s	wv_reread_loop                  ; equal: not fuzzy enough, read again
wv_done:
	bra.w	script_dispatch


;----------------------------------------------------------------------
; Write a sector at a precise position: wait for the DMA counter to reach the
; target, delay, then start Write Sector and deselect the drive to end it
;----------------------------------------------------------------------
timed_write_sector:	; from: op_24_write_verify
	move.w	#$30,delay_count                ; delay $30

timed_write_sector_at:	; from: op_60_long_track_write
	bsr.w	fdc_write_sector_flags          ; Write Sector
	bsr.w	read_psg_port_a                 ; d5 = port A deselected
	lea	$ff860d,a1                      ; DMA base low
	lsr.w	#4,d3                           ; target nibbles
	beq.s	timed_write_end                 ; no wait?
	move.w	sr,-(sp)
	ori.w	#$700,sr
	bsr.w	wait_dma_change                 ; DMA moving?
	beq.s	timed_restore_sr
timed_wait_nibble:
	addi.b	#$10,d4                         ; next 16-byte step
	subq.b	#1,d3
	bcs.s	timed_wait_final
	cmp.b	(a1),d4                         ; reached?
	bne.s	timed_wait_nibble
timed_wait_nibble2:
	addi.b	#$10,d4                         ; wait for each step
	moveq	#-1,d0
timed_wait_low:
	cmp.b	(a1),d4
	dbeq	d0,timed_wait_low
	bne.s	timed_write_end
	subq.b	#1,d3
	bcc.s	timed_wait_nibble2
timed_wait_final:
	moveq	#-1,d0
	move.w	delay_count,d2                  ; delay
timed_wait_change:
	cmp.b	(a1),d4                         ; wait for the next change
	dbne	d0,timed_wait_change
timed_delay:
	dbra	d2,timed_delay                  ; delay loop
	move.b	d5,$ff8802                      ; deselect the drive (ends the write)
	btst	#$2,d6                          ; bit 2: toggle select
	bne.s	timed_toggle_select
timed_restore_sr:
	move.w	(sp)+,sr
timed_write_end:
	bsr.w	fdc_abort                       ; stop the FDC
	swap	d5                              ; reselect the drive
	move.b	d5,$ff8802                      ; PSG write data
	rts

timed_toggle_select:
	move.l	d5,d4                           ; d4 = selected
	swap	d4
	btst	#$1,d6                          ; bit 1?
	beq.s	timed_toggle_loop
	move.w	#$a0,d2                         ; $a0 toggles
timed_toggle_loop:
	move.b	d4,$ff8802                      ; select
	btst	#$5,$fffa01                     ; FDC done?
	beq.s	timed_toggle_done
	move.b	d5,$ff8802                      ; deselect
	dbra	d2,timed_toggle_loop
timed_toggle_done:
	move.b	d5,$ff8802                      ; deselect
	bra.s	timed_restore_sr

op_30_timed_sector_write:	; from: opcode_table
	move.w	sr,-(sp)                        ; IPL 1
	move.w	#$2100,sr
	move.b	#$2,d5                          ; 2 passes
tsw_pass_loop:
	move.b	$1(a2),d6                       ; count
	clr.l	d1                              ; track
	move.b	$3(a2),d1
	bsr.w	fdc_set_track_reg
	move.b	$2(a2),d1                       ; sector
	move.w	#$84,$2(a6)                     ; DMA mode: FDC sector register
	move.w	d1,(a6)
	move.w	#$80,$2(a6)                     ; DMA mode: FDC command/status
	move.l	a2,d0                           ; DMA address = data after the item
	addq.l	#6,d0
	bsr.w	dma_set_address
	bsr.w	dma_write_mode
	move.w	#$d4,(a6)                       ; Force Interrupt on index pulse
	moveq	#-1,d0
tsw_wait_index:
	btst	#$5,$fffa01                     ; wait for the index pulse
	dbeq	d0,tsw_wait_index
	move.w	#$b000,d0                       ; timeout
tsw_write_loop:
	move.w	#$a0,(a6)                       ; Write Sector
tsw_wait_done:
	btst	#$5,$fffa01                     ; wait until done
	dbeq	d0,tsw_wait_done
	bne.s	tsw_check                       ; timeout
	subq.b	#1,d6                           ; count--
	bne.s	tsw_write_loop
tsw_check:
	bsr.w	fdc_abort
	tst.w	d6                              ; all written?
	beq.s	tsw_done
	subq.b	#1,d5                           ; next pass
	bne.s	tsw_pass_loop
tsw_done:
	move.w	(sp)+,sr
	clr.l	d0
	move.w	$4(a2),d0                       ; item length
	adda.l	d0,a2
	bra.w	script_dispatch

op_34_end_verify:	; from: opcode_table
	addq.l	#2,a2                           ; d0 = 0: end
	clr.l	d0
	rts

op_38_gap_long:	; from: opcode_table
	move.l	(a2)+,d1                        ; d1 = count
	move.w	d1,d0
	bmi.s	gap_long_zeros                  ; negative: no gap
gap_long_4e_loop:
	move.b	#$4e,(a0)+                      ; $4e gap
	dbra	d0,gap_long_4e_loop
gap_long_zeros:
	moveq	#11,d1                          ; 12 zero bytes
gap_long_zero_loop:
	clr.b	(a0)+
	dbra	d1,gap_long_zero_loop
	bra.w	script_dispatch


; Four bytes copied here from the copyright string (expected "(c) ")
key_copyright:	; from: op_0c_write_special_sectors
	dc.b	$00
key_copyright_1:	; from: op_0c_write_special_sectors
	dc.b	$00
key_copyright_2:	; from: op_0c_write_special_sectors
	dc.b	$00
key_copyright_3:
	dc.b	$00

;----------------------------------------------------------------------
; Opcode $0c: write special sectors whose data is bit-shifted (roxr) so the
; bytes are out of sync, timed against the DMA counter
;----------------------------------------------------------------------
op_0c_write_special_sectors:	; from: opcode_table
	bsr.w	fdc_wait_status
	move.l	#special_ids,special_id_ptr     ; special_id_ptr = special_ids
	move.w	(a2)+,d0                        ; count * 4
	andi.w	#$ff,d0
	move.w	d0,special_count
wss_sector_loop:	; from: op_40_check_special_written
	move.l	a2,script2_ptr                  ; remember the script position
	move.b	#$12,write_retries              ; 18 attempts
	bsr.w	read_ids_short                  ; reference: number of IDs
	move.w	d0,id_count_ref
	move.b	#$3,f_sync_in_data              ; 3 attempts before changing the delay
wss_shift_loop_start:	; from: op_40_check_special_written
	lea	shift_sector_data,a1            ; shift the sector data one bit
	andi.b	#$ef,ccr                        ; X = 0
	moveq	#5,d0                           ; 6 bytes
wss_shift_loop:
	move.b	(a2)+,d1
	roxr.b	#1,d1
	move.b	d1,(a1)+
	dbra	d0,wss_shift_loop
	moveq	#32,d1
wss_shift_gap_loop:
	moveq	#78,d0                          ; 33 x shifted $4e
	roxr.b	#1,d0
	move.b	d0,(a1)+
	dbra	d1,wss_shift_gap_loop
	bsr.w	read_psg_port_a                 ; d5 = port A deselected
	lea	copyright-$1567,a0              ; a0 = copyright - $14ab
	move.l	$1567(a0),key_copyright         ; key_copyright = "(c) "
	clr.l	d1                              ; track register = $ff
	st	d1
	bsr.w	fdc_set_track_reg
	move.w	#$84,$2(a6)                     ; sector register
	move.w	special_count,(a6)              ; sector = special count
	move.l	#shift_sector_buf,d0            ; DMA from shift_sector_buf
	bsr.w	dma_set_address
	bsr.w	dma_write_mode
	clr.l	d1
	move.w	#$a0,(a6)                       ; Write Sector
	lea	$ff860d,a0                      ; DMA base low
	move.b	(a0),d1
	move.w	sr,-(sp)
	ori.w	#$700,sr
	cmpi.b	#$28,key_copyright              ; tamper check: "("
	bne.s	wss_wait_position
	moveq	#-1,d0                          ; timeout
	moveq	#3,d3                           ; wait for 4 changes
	move.w	write_delay,d2                  ; delay
wss_wait_position:
	cmp.b	(a0),d1                         ; wait for the DMA low byte to change
	dbne	d0,wss_wait_position
	bne.s	wss_deselect                    ; timeout
	dbra	d3,wss_wait_position
	move.w	(sp)+,sr
	bsr.w	fdc_abort
	cmpi.b	#$63,key_copyright_1            ; tamper check: "c"
	bne.w	start                           ; wrong: restart the program
	bra.w	wss_retry

wss_deselect:
	move.b	d5,$ff8802                      ; deselect the drive
	swap	d5
wss_delay_loop:
	dbra	d2,wss_delay_loop               ; delay
	clr.l	d2
	clr.l	d2
	move.b	d5,$ff8802                      ; reselect
	move.w	(sp)+,sr
	move.w	#$200,d2                        ; delay $200
wss_delay2_loop:
	dbra	d2,wss_delay2_loop
	bsr.w	fdc_abort
	cmpi.b	#$29,key_copyright_2            ; tamper check: ")"
	bne.w	key_copyright                   ; wrong: execute the key bytes
	clr.l	d7
	bra.w	script_dispatch

op_40_check_special_written:	; from: opcode_table
	addq.l	#2,a2
	btst	#$4,d7                          ; record not found?
	bne.s	wss_retry
	move.l	#sector_buf,d0
	bsr.w	dma_set_address                 ; read into sector_buf
	bsr.w	dma_read_mode
	move.w	#$80,(a6)                       ; Read Sector
	bsr.w	fdc_wait_status
	btst	#$4,d7                          ; record not found?
	bne.s	wss_retry
	movea.l	special_id_ptr,a5               ; remember track/sector written
	move.b	fdc_track_reg_3,(a5)+
	move.b	fdc_track_reg_1,(a5)+
	move.l	a5,special_id_ptr
	lea	id_fields,a0
	move.w	special_count,d0                ; ID field address for this count
	movea.l	$0(a0,d0.w),a0
	lea	-$50(a0),a0                     ; start 80 bytes before it
	moveq	#78,d0                          ; 68 x $4e
	moveq	#67,d1
	bsr.w	fill_bytes_loop
	moveq	#16,d0                          ; write until the ID + 16
	bsr.s	write_track_until
	subq.w	#4,special_count                ; next special sector
	bne.w	wss_sector_loop
	bsr.w	verify_special_sectors          ; verify all special sectors
	beq.w	script_dispatch
op_40_fail:
	moveq	#-1,d0
	rts

wss_retry:	; from: op_0c_write_special_sectors
	subq.b	#1,f_sync_in_data               ; attempts--
	bne.s	wss_retry_check
	bsr.w	read_ids_short                  ; count IDs now
	cmp.w	id_count_ref,d0                 ; more than before?
	bcc.s	wss_delay_dec
	addq.w	#1,write_delay                  ; longer delay
	bra.s	wss_reset_count

wss_delay_dec:
	subq.w	#1,write_delay                  ; shorter delay
	cmpi.w	#$66,write_delay                ; minimum $66
	bcc.s	wss_reset_count
	move.w	#$6a,write_delay                ; default $6a
wss_reset_count:
	move.b	#$3,f_sync_in_data              ; reset the counter
wss_retry_check:
	subq.b	#1,write_retries                ; attempts--
	beq.s	op_40_fail
	moveq	#80,d0                          ; write until the ID + 80
	bsr.s	write_track_until
	movea.l	script2_ptr,a2
	bra.w	wss_shift_loop_start


;----------------------------------------------------------------------
; Write Track and abort it once the DMA address passes id_fields+d0
;----------------------------------------------------------------------
write_track_until:	; from: op_54_shifted_sector_write, op_40_check_special_written
	move.w	special_count,d1                ; count * 4
	lea	id_fields,a5
	add.l	$0(a5,d1.w),d0                  ; d0 += ID field address
	move.l	d0,(a5)                         ; id_fields = stop address
	bsr.w	fdc_write_track                 ; Write Track
	moveq	#6,d1                           ; timeout
	swap	d1
wtu_wait_loop:
	btst	#$5,$fffa01                     ; FDC done?
	beq.s	wtu_stop
	bsr.w	dma_get_address                 ; DMA address
	cmp.l	id_fields,d0                    ; past the stop address?
	bcc.s	wtu_stop
	subq.l	#1,d1
	bne.s	wtu_wait_loop
wtu_stop:
	moveq	#5,d1                           ; short delay
wtu_delay_loop:
	dbra	d1,wtu_delay_loop
	bra.w	fdc_abort                       ; Force Interrupt


;----------------------------------------------------------------------
; Re-read the sectors listed in special_ids to verify them
;----------------------------------------------------------------------
verify_special_sectors:	; from: op_40_check_special_written, script_add_sector
	move.l	#sector_list_100,d0             ; read into sector_list + $100
	movea.l	special_id_ptr,a5
	cmpa.l	#special_ids,a5                 ; list empty?
	beq.s	verify_special_ret
	clr.l	d1
	move.b	-(a5),d1                        ; sector
	swap	d1
	move.b	-(a5),d1                        ; track
	move.l	a5,special_id_ptr
	bsr.w	fdc_read_sector                 ; read the sector
	bsr.w	fdc_wait_status
	btst	#$4,d7                          ; record not found: ok
	beq.s	verify_special_sectors
	btst	#$3,d7                          ; CRC error: ok
	beq.s	verify_special_sectors
verify_special_ret:
	rts

op_44_id_sector_ff:	; from: opcode_table
	lea	-$3c(a0),a0                     ; back 60 bytes
	move.b	(a0),d0                         ; CRC byte there?
	cmpi.b	#$f7,d0
	bne.s	id_ff_store
	moveq	#-27,d0                         ; $e5
	move.b	d0,(a0)+
id_ff_store:
	move.b	d0,(a0)+
	addq.w	#4,special_count                ; one more special sector
	bsr.w	emit_3_sync                     ; three $f5
	move.b	#$fe,(a0)+                      ; ID mark
	st	(a0)+                           ; track $ff
	clr.b	(a0)+                           ; side 0
	move.b	special_count_1,(a0)+           ; sector = special count
	clr.b	(a0)+                           ; size 0
	move.b	#$f7,(a0)+                      ; CRC
	moveq	#22,d1                          ; 23 x $4e
	moveq	#78,d0
	bsr.w	fill_bytes_loop
	moveq	#12,d1                          ; 13 x 0
	clr.l	d0
	bsr.w	fill_bytes_loop
	bsr.w	emit_3_sync                     ; three $f5
	move.b	#$fb,(a0)+                      ; data mark
	moveq	#16,d1                          ; 17 x 0
	clr.l	d0
	bsr.w	fill_bytes_loop
	lea	id_fields,a5
	move.w	special_count,d0                ; count * 4
	ext.l	d0
	adda.l	d0,a5
	move.l	a0,(a5)                         ; remember the position
	bra.w	op_20_id_field                  ; then a normal ID field

op_48_id_zero:	; from: opcode_table
	lea	-$2c(a0),a0                     ; back 44 bytes
	move.b	(a0),d0
	cmpi.b	#$f7,d0                         ; CRC byte there?
	bne.s	id_zero_store
	moveq	#-27,d0                         ; $e5
	move.b	d0,(a0)+
id_zero_store:
	move.b	d0,(a0)+
	bsr.w	emit_3_sync                     ; three $f5
	move.b	#$fe,(a0)+                      ; ID mark
	clr.b	(a0)+                           ; ID 0 0 0 0
	clr.b	(a0)+
	clr.b	(a0)+
	clr.b	(a0)+
	move.b	#$f7,(a0)+                      ; CRC
	moveq	#22,d1                          ; 23 x $4e
	moveq	#78,d0
	bsr.w	fill_bytes_loop
	moveq	#12,d1                          ; 13 x 0
	moveq	#0,d0
	bsr.w	fill_bytes_loop
	bsr.w	emit_3_sync                     ; three $f5
	move.b	#$fb,(a0)+                      ; data mark
	addq.l	#2,a2
	bra.w	script_dispatch

op_4c_verify_sectors:	; from: opcode_table
	move.w	(a2)+,d6                        ; count
	andi.w	#$ff,d6
	bsr.w	fdc_wait_status
verify_sectors_loop:
	clr.l	d1                              ; d1 = sector:track
	move.b	(a2)+,d1
	swap	d1
	move.b	(a2)+,d1
	move.l	#sector_buf,d0                  ; read into sector_buf
	bsr.w	fdc_read_sector
	bsr.w	fdc_wait_result_rw
	bne.s	verify_sectors_fail             ; error: fail
	dbra	d6,verify_sectors_loop
	bra.w	script_dispatch

verify_sectors_fail:
	moveq	#1,d0                           ; d0 = 1: failed
	rts

op_50_id_ff_sector1:	; from: opcode_table
	clr.l	d0
	addq.l	#2,a2
	move.w	(a2)+,d0                        ; offset in track
	addi.l	#track_buf,d0
	movea.l	d0,a0
	move.l	d0,id_fields                    ; remember the position
	lea	-$3f(a0),a0                     ; 63 bytes before it
	bsr.w	emit_3_sync                     ; three $f5
	move.b	#$fe,(a0)+                      ; ID mark
	move.b	#$ff,(a0)+                      ; ID $ff 0 1 3
	clr.b	(a0)+
	move.b	#$1,(a0)+
	move.b	#$3,(a0)+
	move.b	#$f7,(a0)+                      ; CRC
	moveq	#22,d1                          ; 23 x $4e
	moveq	#78,d0
	bsr.w	fill_bytes_loop
	moveq	#12,d1                          ; 13 x 0
	clr.l	d0
	bsr.w	fill_bytes_loop
	bsr.w	emit_3_sync                     ; three $f5
	move.b	#$fb,(a0)+                      ; data mark
	moveq	#16,d1                          ; 17 x 0
	clr.l	d0
	bsr.w	fill_bytes_loop
	bra.w	script_dispatch

shift_dma_target:	; from: op_54_shifted_sector_write
	dc.l	$00000000
shift_delay:	; from: op_54_shifted_sector_write
	dc.w	$0000
op_54_shifted_sector_write:	; from: opcode_table
	move.l	(a2)+,d0                        ; d0 = offset
	clr.l	d1
	move.w	d0,d1
	addi.w	#$1c,d1                         ; offset + $1c
	clr.l	d2
	move.w	d1,d2
	andi.w	#$fff0,d1                       ; rounded down to 16
	addi.l	#shift_buf2,d1                  ; DMA target: shift_buf2 + offset
	move.l	d1,shift_dma_target
	andi.w	#$f,d2                          ; offset & 15
	mulu.w	#$16,d2                         ; delay = (offset & 15) * 22 + 48
	addi.w	#$30,d2
	move.w	d2,shift_delay
	movea.l	a2,a4                           ; a4 -> data in the script
	bsr.w	fdc_wait_status
	lea	shift_buf2,a1                   ; 18 zero bytes
	clr.l	(a1)+
	clr.l	(a1)+
	clr.l	(a1)+
	clr.l	(a1)+
	clr.w	(a1)+
	andi.b	#$ef,ccr                        ; X = 0
ssw_shift_loop:
	move.b	(a2)+,d1                        ; shift the data one bit
	roxr.b	#1,d1
	move.b	d1,(a1)+
	dbra	d0,ssw_shift_loop
	move.b	#$12,write_retries              ; 18 attempts
	move.b	#$3,f_sync_in_data              ; 3 before changing the delay
ssw_write_loop:
	bsr.w	read_psg_port_a                 ; d5 = port A deselected
	move.w	#$ff,d1                         ; track register $ff
	bsr.w	fdc_set_track_reg
	move.w	#$84,$2(a6)                     ; sector register
	move.w	#$1,(a6)                        ; sector 1
	move.l	#shift_buf2,d0                  ; DMA from shift_buf2
	bsr.w	dma_set_address
	bsr.w	dma_write_mode
	clr.l	d1
	move.w	#$a0,(a6)                       ; Write Sector
	lea	$ff860d,a0                      ; DMA base low
	lea	$ff860b,a1                      ; DMA base mid
	move.l	shift_dma_target,d6             ; target address
	move.w	d6,d7                           ; d7 = mid byte
	lsr.w	#8,d7
	move.b	(a0),d1
	move.w	sr,-(sp)
	ori.w	#$700,sr
	moveq	#-1,d0                          ; timeout
	moveq	#3,d3                           ; wait for 4 changes
	move.w	write_delay,d2                  ; delay
ssw_wait_position:
	cmp.b	(a0),d1                         ; wait for the DMA low byte to change
	dbne	d0,ssw_wait_position
	bne.s	ssw_deselect                    ; timeout
	dbra	d3,ssw_wait_position
ssw_position_timeout:
	move.w	(sp)+,sr
	bra.s	ssw_retry

ssw_speed_up:
	subq.b	#1,f_sync_in_data               ; attempts before changing the delay
	bne.s	ssw_write_rest
	addq.w	#1,write_delay                  ; longer delay
	move.b	#$3,f_sync_in_data
ssw_write_rest:
	moveq	#80,d0                          ; write until the ID + 80
	bsr.w	write_track_until
	bra.s	ssw_retry

ssw_slow_down:
	subq.b	#1,f_sync_in_data               ; attempts before changing the delay
	bne.s	ssw_retry
	subq.w	#1,write_delay                  ; shorter delay
	move.b	#$3,f_sync_in_data
	cmpi.w	#$66,write_delay                ; minimum $66
	bcc.s	ssw_retry
	move.w	#$6a,write_delay                ; default $6a
ssw_retry:
	bsr.w	fdc_abort                       ; stop the FDC
	subq.b	#1,write_retries                ; attempts--
	bne.w	ssw_write_loop
	moveq	#-1,d0                          ; d0 = -1: failed
	rts

ssw_deselect:
	move.b	d5,$ff8802                      ; deselect the drive
	swap	d5
ssw_delay_loop:
	dbra	d2,ssw_delay_loop               ; delay
	clr.l	d2
	clr.l	d2
	move.b	d5,$ff8802                      ; reselect
	moveq	#-1,d0
ssw_wait_mid:
	cmp.b	(a1),d7                         ; wait for the DMA mid byte
	dbeq	d0,ssw_wait_mid
	bne.s	ssw_position_timeout
ssw_wait_low:
	cmp.b	(a0),d6                         ; wait for the DMA low byte
	dbeq	d0,ssw_wait_low
	bne.w	ssw_position_timeout
ssw_wait_low_change:
	cmp.b	(a0),d6                         ; wait for it to change
	dbne	d0,ssw_wait_low_change
	beq.w	ssw_position_timeout
	move.w	shift_delay,d0                  ; delay
ssw_delay2_loop:
	dbra	d0,ssw_delay2_loop
	bsr.w	fdc_abort                       ; stop the FDC
	move.w	(sp)+,sr
	move.l	#sector_buf,d0                  ; read into sector_buf
	bsr.w	dma_set_address
	bsr.w	dma_read_mode
	move.w	#$e0,(a6)                       ; Read Track
	moveq	#6,d7                           ; timeout
	swap	d7
ssw_read_wait:
	btst	#$5,$fffa01                     ; FDC done?
	beq.s	ssw_read_check
	bsr.w	dma_get_address                 ; DMA address
	cmpi.l	#sector_buf_200,d0              ; past sector_buf + $200?
	bcc.s	ssw_read_check
	subq.l	#1,d7
	bne.s	ssw_read_wait
	bra.w	ssw_retry

ssw_read_check:
	bsr.w	fdc_abort                       ; stop the FDC
	move.l	id_fields,d0                    ; position of the ID
	subi.l	#track_buf_8,d0
	addi.l	#sector_buf,d0
	movea.l	d0,a0
	moveq	#32,d0                          ; find $a1 $a1
ssw_find_sync_loop:
	cmpi.b	#$a1,(a0)+
	dbeq	d0,ssw_find_sync_loop
	bne.w	ssw_speed_up                    ; not found: longer delay
	cmpi.b	#$a1,(a0)+
	bne.w	ssw_speed_up
	moveq	#62,d0                          ; compare 63 bytes with the data
	movea.l	a4,a1
	cmpm.b	(a0)+,(a1)+                     ; first byte
	bne.w	ssw_speed_up
ssw_compare_loop:
	cmpm.b	(a0)+,(a1)+
	dbne	d0,ssw_compare_loop
	bne.w	ssw_slow_down                   ; mismatch: shorter delay
	movea.l	id_fields,a0                    ; position of the ID
	lea	-$3f(a0),a0                     ; 63 bytes before it
	moveq	#78,d0                          ; 63 x $4e
	moveq	#62,d1
	bsr.w	fill_bytes_loop
	clr.w	special_count
	moveq	#16,d0                          ; write until the ID + 16
	bsr.w	write_track_until
	bra.w	script_dispatch

op_58_fuzzy_marker:	; from: opcode_table
	moveq	#10,d1                          ; gap 10, offset 85
	moveq	#85,d2
fuzzy_marker_calc:	; from: op_74_fuzzy_marker_params
	lea	-$9(a0),a0                      ; back 9 bytes
	move.l	a0,d0                           ; offset in the image
	subi.l	#track_buf,d0
	subq.l	#1,d0
	moveq	#15,d4                          ; align to 16
	and.l	d4,d0
	cmp.b	d1,d0                           ; remainder >= gap?
	bcc.s	fuzzy_marker_back
	sub.l	d0,d1                           ; gap - remainder zero bytes
	bra.s	fuzzy_marker_zero

fuzzy_marker_zero_loop:
	clr.b	(a0)+
fuzzy_marker_zero:
	dbra	d1,fuzzy_marker_zero_loop
	bra.s	fuzzy_marker_store

fuzzy_marker_back:
	sub.l	d1,d0                           ; move back by remainder - gap
	suba.l	d0,a0
fuzzy_marker_store:
	move.l	a0,d0                           ; fuzzy_pos = position + offset
	add.l	d2,d0
	move.l	d0,fuzzy_pos
	clr.l	d0                              ; sector:track from the script
	move.b	$4(a2),d0
	swap	d0
	move.b	$2(a2),d0
	move.l	d0,fuzzy_sector
	bra.w	op_20_id_field                  ; then a normal ID field

op_5c_long_track_prep:	; from: opcode_table
	addq.l	#2,a2
	move.l	(a2)+,long_track_sector         ; sector:track
	move.l	a0,d0                           ; position + $122
	addi.l	#$122,d0
	move.l	d0,long_track_pos
	lea	track_buf,a1
	movea.l	a1,a4                           ; find $f5 $f5 $f5
	moveq	#-11,d0
ltp_find_f5_loop:
	cmp.b	(a1)+,d0
	bne.s	ltp_find_f5_loop
	cmp.b	(a1)+,d0
	bne.s	ltp_find_f5_loop
	cmp.b	(a1)+,d0
	bne.s	ltp_find_f5_loop
	subq.l	#3,a1                           ; back to the first $f5
	moveq	#11,d0                          ; 12 zero bytes before it
ltp_clear_loop:
	clr.b	-(a1)
	dbra	d0,ltp_clear_loop
	move.l	a1,d0                           ; offset of the zeros
	subi.l	#track_buf,d0
	subi.w	#$42,d0                         ; - $42
ltp_gap_loop:
	move.b	#$4e,(a4)+                      ; $4e fill
	dbra	d0,ltp_gap_loop
	move.b	#$d3,(a4)+                      ; $d3 then $93 ... up to the zeros
ltp_pattern_loop:
	move.b	#$93,(a4)+
	cmpa.l	a4,a1
	bne.s	ltp_pattern_loop
	bra.w	script_dispatch

op_60_long_track_write:	; from: opcode_table
	addq.l	#2,a2
	move.l	#track_buf,d2                   ; d2 = track_buf
ltw_align_loop:
	bsr.w	fdc_wait_status
	bsr.w	dma_get_address                 ; DMA address
	sub.l	long_track_pos,d0               ; minus the target position
	bclr	#$0,d0                          ; make it even
	move.l	d0,d1
	bpl.s	ltw_align_check
	neg.w	d0
ltw_align_check:
	cmpi.w	#$30,d0                         ; aligned within $30?
	bcs.s	ltw_build_image
	sub.l	d1,d2                           ; shift the DMA start
	move.l	d2,d0
	bsr.w	dma_set_address
	bsr.w	fdc_write_track_cmd             ; Write Track again
	bra.s	ltw_align_loop

ltw_build_image:
	lea	sector_buf,a0
	moveq	#-27,d0                         ; $e5
	move.w	#$1d3,d1                        ; 468 x $e5
	bsr.w	fill_bytes
	move.b	#$c4,(a0)+                      ; $c4 $0b
	move.b	#$b,(a0)+
	moveq	#15,d1                          ; 16 x 0
	clr.l	d0
	bsr.w	fill_bytes
	moveq	#15,d1                          ; 16 x $eb
	moveq	#-21,d0
	bsr.w	fill_bytes
	bsr.w	set_write_params_data           ; d0 = sector_buf, d3 = $1e0
	bsr.w	fdc_write_sector_flags          ; Write Sector
	bsr.w	wait_dma_change                 ; DMA started?
	bsr.w	fdc_abort                       ; stop the FDC
	clr.w	ltw_delay_sub
	clr.w	delay_count
ltw_retry_loop:
	addq.b	#1,delay_count_1                ; delay_count++
	cmpi.b	#$8,delay_count_1               ; every 8: reset
	bcs.s	ltw_retry_count
	clr.w	delay_count
ltw_retry_count:
	addq.b	#1,ltw_tries                    ; up to 30 tries
	cmpi.b	#$1e,ltw_tries
	bcc.s	ltw_fail
	bsr.w	set_write_params_data
	bsr.w	timed_write_sector_at           ; timed write
	bsr.s	read_track_check_sig            ; signature readable?
	bne.s	ltw_retry_loop
	lea	id_fields,a0                    ; 512 x $e5 in id_fields
	move.w	#$1ff,d1
	moveq	#-27,d0
	bsr.w	fill_bytes
ltw_verify_loop:
	bsr.w	set_write_params_id             ; write the ID part
	bsr.w	timed_write_sector_at
	bsr.w	set_write_params_data           ; then the data part
	move.l	long_track_sector,d1            ; read back the long sector
	bsr.w	fdc_read_sector
	bsr.w	fdc_wait_status
	lea	sector_buf,a0
	move.w	#$fe,d1                         ; 255 words
ltw_find_e5_loop:
	cmpi.w	#$e5e5,(a0)+                    ; find $e5e5
	dbne	d1,ltw_find_e5_loop
	bne.s	ltw_verify_retry                ; not found: retry
	bra.w	script_dispatch

ltw_verify_retry:
	addi.b	#$8,delay_count_1               ; delay + 8
	bpl.s	ltw_verify_loop                 ; up to 128
ltw_fail:
	moveq	#-1,d0                          ; d0 = -1: failed
	rts

ltw_delay_sub:	; from: op_60_long_track_write
	dc.b	$00
ltw_tries:	; from: op_60_long_track_write
	dc.b	$00

read_track_check_sig:	; from: op_60_long_track_write
	movem.l	a2,-(sp)
	bsr.w	fdc_read_track                  ; Read Track
rtc_wait_loop:
	bsr.w	wait_dma_change                 ; DMA running?
	beq.s	rtc_fail
	bsr.w	dma_get_address                 ; DMA address
	subi.l	#track_buf,d0
	cmpi.l	#$400,d0                        ; past $400?
	bcs.s	rtc_wait_loop
	bsr.w	fdc_abort                       ; stop the FDC
	bsr.w	detect_signature_a              ; signature A?
	bne.s	rtc_fail
	bsr.w	detect_signature_b              ; signature B?
	beq.s	rtc_ret
rtc_fail:
	bsr.w	fdc_abort                       ; stop the FDC
	moveq	#-1,d0                          ; d0 = -1: failed
rtc_ret:
	movem.l	(sp)+,a2
	rts


set_write_params_id:	; from: op_60_long_track_write
	move.l	#id_fields,d0                   ; DMA from id_fields
	move.w	#$60,d3                         ; Write Sector flags $60
	move.l	long_track_sector,d1            ; sector:track
	bra.s	set_write_params


set_write_params_data:	; from: op_60_long_track_write
	move.l	#sector_buf,d0                  ; DMA from sector_buf
	move.w	#$1e0,d3                        ; flags $1e0
	clr.l	d1                              ; sector 0
set_write_params:	; from: set_write_params_id
	clr.l	d2
	clr.l	d6
	move.l	d0,d4                           ; d4 = DMA address
	rts


;----------------------------------------------------------------------
; Opcode $64: run-length encoded track data: (count,value) byte pairs,
; count 0 = literal block (length word + bytes), (0,0) = end
;----------------------------------------------------------------------
op_64_rle_data:	; from: opcode_table
	addq.l	#1,a2                           ; skip opcode byte
rle_skip_pad:
	addq.l	#1,a2                           ; skip pad byte
rle_loop:
	clr.l	d0
	move.b	(a2),d0                         ; count
	beq.s	rle_literal                     ; count 0 = literal
	move.w	(a2)+,d1                        ; d1.b = value
	subq.w	#1,d0
rle_fill_loop:
	move.b	d1,(a0)+                        ; count x value
	dbra	d0,rle_fill_loop
	bra.s	rle_loop

rle_literal:
	move.w	(a2)+,d1                        ; literal length
	beq.w	script_dispatch                 ; length 0 = end
	move.w	d1,d2
	subq.w	#1,d1
rle_literal_loop:
	move.b	(a2)+,(a0)+                     ; copy literal bytes
	dbra	d1,rle_literal_loop
	btst	#$0,d2                          ; odd length: skip pad
	beq.s	rle_loop
	bne.s	rle_skip_pad
op_6c_partial_write_track:	; from: opcode_table
	addq.l	#2,a2                           ; skip opcode word
	clr.l	track_buf_60                    ; clear the sync at +$60
	move.l	#track_buf_2,d0                 ; DMA from track_buf + 2
	bsr.w	dma_set_address
	bsr.w	dma_write_mode
	move.w	#$f0,(a6)                       ; Write Track
	bsr.w	wait_dma_change                 ; DMA running?
	beq.s	pwt_abort
pwt_wait_loop:
	bsr.w	dma_get_address                 ; DMA address
	cmpi.l	#track_buf_82,d0                ; past track_buf + $82?
	bcs.s	pwt_wait_loop
	moveq	#3,d0                           ; short delay
pwt_delay_loop:
	dbra	d0,pwt_delay_loop
pwt_abort:
	bsr.w	fdc_abort                       ; stop the FDC
	move.l	#$f5f5f5fb,track_buf_60         ; restore sync + data mark at +$60
	bra.w	script_dispatch

op_70_sync_read_track:	; from: opcode_table
	addq.l	#2,a2                           ; skip opcode word
	bsr.w	fdc_wait_status
	moveq	#20,d5                          ; 21 tries
srt_read_loop:
	move.l	#sector_buf,d0                  ; read into sector_buf
	bsr.w	dma_set_address
	bsr.w	fdc_read_track_cmd              ; Read Track
	bsr.w	wait_dma_change                 ; DMA running?
	beq.s	srt_retry
srt_wait_loop:
	bsr.w	dma_get_address                 ; DMA address
	subi.l	#sector_buf,d0
	cmpi.w	#$80,d0                         ; $80 bytes read?
	bcs.s	srt_wait_loop
	bsr.w	fdc_abort                       ; stop the FDC
	moveq	#64,d0                          ; in the first 65 bytes
	lea	sector_buf,a0
srt_find_14_loop:
	cmpi.b	#$14,(a0)+                      ; find $14 $0b
	dbeq	d0,srt_find_14_loop
	bne.s	srt_retry
	cmpi.b	#$b,(a0)
	dbeq	d0,srt_find_14_loop
	beq.s	srt_done
srt_retry:
	bsr.w	fdc_abort                       ; stop the FDC
	bsr.w	fdc_write_track                 ; Write Track and try again
	bsr.w	fdc_wait_status
	dbra	d5,srt_read_loop
srt_done:
	bra.w	script_dispatch

op_74_fuzzy_marker_params:	; from: opcode_table
	moveq	#0,d1                           ; gap, offset from the script
	moveq	#0,d2
	move.b	$1(a2),d1
	move.b	$2(a2),d2
	addq.l	#2,a2
	bra.w	fuzzy_marker_calc


;----------------------------------------------------------------------
; Read PSG port A -> d5 = value | 7 (both drives deselected) in both words
;----------------------------------------------------------------------
read_psg_port_a:	; from: timed_write_sector_at, op_54_shifted_sector_write, op_0c_write_special_sectors, write_fuzzy_bits, script_add_sector
	move.b	#$e,$ff8800                     ; select PSG register 14
	move.b	$ff8800,d0                      ; read port A
	move.w	d0,d5
	swap	d5                              ; high word: as read
	move.w	d0,d5
	ori.b	#$7,d5                          ; low word: both drives deselected
	rts


fill_bytes:	; from: op_60_long_track_write, fill_bytes_loop, op_28_gap
	move.b	d0,(a0)+                        ; d1+1 bytes of d0

fill_bytes_loop:	; from: op_54_shifted_sector_write, op_50_id_ff_sector1, op_48_id_zero, op_44_id_sector_ff, op_40_check_special_written, copy_raw_sector
	dbra	d1,fill_bytes
	rts


;----------------------------------------------------------------------
; Emit three $f5 sync bytes (clearing a preceding $f5/$f6)
;----------------------------------------------------------------------
emit_3_sync:	; from: op_20_id_field, op_68_id_current_track, op_50_id_ff_sector1, op_48_id_zero, op_44_id_sector_ff, op_18_data_field
	moveq	#2,d0                           ; 3 bytes
	cmpi.b	#$f5,-$1(a0)                    ; previous byte $f5?
	beq.s	emit_3_sync_clear
	cmpi.b	#$f6,-$1(a0)                    ; or $f6?
	bne.s	emit_3_sync_loop
emit_3_sync_clear:
	clr.b	-$1(a0)                         ; clear it
emit_3_sync_loop:
	move.b	#$f5,(a0)+                      ; three $f5
	dbra	d0,emit_3_sync_loop
	rts

run_list_invert:	; from: emit_run_list
	eori.b	#$ff,d1                         ; invert the fill byte
run_list_fill_loop:
	move.b	d1,(a0)+                        ; count x byte
	dbra	d0,run_list_fill_loop

emit_run_list:	; from: op_28_gap
	clr.w	d0                              ; count
	move.b	(a2),d0                         ; count:value word
	move.w	(a2)+,d1
	bne.s	run_list_invert                 ; word 0 = end
	rts


restore_check_wprot:	; from: copy_disk_protected, copy_disk_normal
	bsr.s	restore_drive                   ; restore first
	clr.l	d7
	move.w	(a6),d7                         ; status bits
	andi.w	#$ff,d7
	bset	#$7,d7                          ; bit 7 always set
	btst	#$6,d7                          ; bit 6: write protect
	rts


restore_drive:	; from: format_disk, copy_disk_protected, restore_check_wprot, copy_disk_normal
	bsr.s	verify_rsc_checksums

select_and_restore:	; from: read_key_track
	bsr.w	select_drive_side

reset_track_and_restore:	; from: copy_disk_normal, copy_disk_protected
	clr.w	dp_track(a4)                    ; track 0
	clr.w	dp_cur_track(a4)                ; current track 0

set_steprate_restore:	; from: read_key_track
	bsr.w	fdc_restore                     ; Restore
	bra.w	fdc_wait_done


;----------------------------------------------------------------------
; Anti-tamper: key_numn - key_numm must be 1 and the XOR checksums of the five
; cached resource strings must match rsc_checksums, otherwise hang
;----------------------------------------------------------------------
verify_rsc_checksums:	; from: restore_drive
	move.w	sr,-(sp)                        ; disable interrupts
	ori.w	#$700,sr
	move.l	key_numn,d0                     ; key_numn - key_numm - 1 = 0?
	sub.l	key_numm,d0
	subq.l	#1,d0
	bne.s	rsc_checksum_hang               ; tampered: hang
	lea	rsc_strings,a0                  ; five cached strings
	lea	rsc_checksums,a2
	moveq	#4,d2
rsc_checksum_loop:
	movea.l	(a0)+,a1                        ; string address
	clr.l	d0
rsc_xor_loop:
	move.b	(a1)+,d1                        ; XOR checksum of the string
	eor.b	d1,d0
	tst.b	d1
	bne.s	rsc_xor_loop
	cmp.b	(a2)+,d0                        ; compare with the table
rsc_checksum_hang:
	nop                                     ; hang on mismatch
	bne.s	rsc_checksum_hang
	dbra	d2,rsc_checksum_loop
	move.w	(sp)+,sr
	rts


;----------------------------------------------------------------------
; Key disk check (once): the track read at start must contain "EUROSYSTEMS"
; followed within 256+ bytes by an $f7 byte, otherwise hang forever
;----------------------------------------------------------------------
check_key_disk:	; from: build_track_image, copy_disk_protected
	tst.w	key_checked                     ; already checked?
	bne.s	key_disk_ret
	addq.w	#1,key_checked
	move.w	sr,-(sp)                        ; disable interrupts
	ori.w	#$700,sr
	move.l	#track_buf,d2                   ; start of the key track
	moveq	#80,d0                          ; search in the first 81 bytes
key_scan_restart:
	movea.l	d2,a0
	lea	copyright+5-$1555,a1            ; a1 = copyright - $1494
	lea	$1555(a1),a1                    ; a1 = copyright + 5 ("UROSYSTEMS")
	moveq	#9,d1                           ; 10 bytes
key_find_e_loop:
	cmpi.b	#$45,(a0)+                      ; find "E"
	dbeq	d0,key_find_e_loop
	bne.s	key_disk_hang                   ; not found: hang
	move.l	a0,d2                           ; continue after it
key_compare_loop:
	cmpm.b	(a1)+,(a0)+                     ; compare "UROSYSTEMS"
	dbne	d1,key_compare_loop
	bne.s	key_scan_restart                ; mismatch: search on
	lea	$100(a0),a0                     ; skip 256 bytes
	move.w	#$1000,d0                       ; within 4K
key_find_f7_loop:
	cmpi.b	#$f7,(a0)+                      ; find an $f7 byte
	dbne	d0,key_find_f7_loop
key_disk_hang:
	bne.s	key_disk_hang                   ; hang if not found
	move.w	(sp)+,sr
key_disk_ret:
	rts


;----------------------------------------------------------------------
; Read the key track: seek to track 80 and Read Track into track_buf
;----------------------------------------------------------------------
read_key_track:	; from: main
	bsr.w	lock_floppy
	bsr.w	load_base_regs
	bsr.w	fdc_wait_status
	bsr.w	select_and_restore              ; select drive, Restore
	moveq	#80,d0                          ; track 80
	bsr.w	fdc_seek                        ; Seek
	bsr.w	fdc_wait_done
	bsr.w	fdc_read_track                  ; Read Track
	bsr.w	fdc_wait_status
	bsr.w	set_steprate_restore            ; Restore
	bsr.w	unlock_floppy
	rts


;----------------------------------------------------------------------
; During Read Track, sample the DMA address to find the index position and
; the first ID mark; flags unformatted and over-long tracks
;----------------------------------------------------------------------
read_track_find_index:	; from: copy_disk_protected
	clr.w	f_unformatted
	lea	track_buf,a0
	clr.w	$3a(a4)                         ; first mark position = 0
	clr.l	d7                              ; d7 = 0: no index seen yet
	move.l	#$10000,dma_timeout             ; timeout
	bsr.w	find_next_mark                  ; first sync
	beq.s	rtfi_check_length               ; none: check the length
	move.b	d1,last_mark                    ; remember the mark byte
	move.w	d0,$3c(a4)                      ; offset of the first sync
rtfi_skip_marks:
	cmpi.b	#$fc,d1                         ; ID mark?
	bcc.s	rtfi_first_mark
	bsr.w	find_next_mark                  ; next mark
	bne.s	rtfi_skip_marks
	bra.s	rtfi_check_length

rtfi_first_mark:
	move.w	d0,$3a(a4)                      ; offset of the first ID mark
rtfi_wait_end:
	bsr.w	sample_dma_address              ; follow the DMA address
	cmpi.l	#track_buf_1900,d0              ; past $1900?
	bcc.s	rtfi_timeout
	tst.w	d7                              ; index pulse seen?
	beq.s	rtfi_wait_end
	move.l	dma_pos,d0                      ; length of the track
	subi.l	#track_buf,d0
	cmpi.w	#$17f0,d0                       ; at least $17f0?
	bcs.s	rtfi_unformatted
	moveq	#1,d7                           ; d7 = 1: ok
	rts


rtfi_timeout:	; from: sample_dma_address, read_track_find_index
	bsr.w	fdc_abort                       ; stop the FDC
	move.w	#$d4,(a6)                       ; Force Interrupt on index pulse
	moveq	#-1,d7                          ; d7 = -1
	bsr.w	fdc_wait_irq                    ; wait for the index pulse
	moveq	#1,d7                           ; d7 = 1
	rts

rtfi_check_length:	; from: read_track_find_index
	move.l	dma_pos,d0                      ; length of the track
	subi.l	#track_buf,d0
	cmpi.w	#$17f0,d0                       ; shorter than $17f0?
	bcc.s	rtfi_long_track
rtfi_unformatted:	; from: read_track_find_index
	st	f_unformatted                   ; unformatted
	cmpi.b	#$2f,cur_track_b                ; track 47?
	bne.s	rtfi_fill_35
	bsr.w	fill_track_dc                   ; fill with $dc
	bra.s	rtfi_fill_sync

rtfi_fill_35:
	bsr.w	fill_track_35                   ; fill with $35
rtfi_fill_sync:
	move.l	#$a1a1a1a1,track_buf_1760       ; sync at +$1760
rtfi_ok:
	clr.l	d0                              ; d0 = 0: ok
	rts

rtfi_long_track:
	cmpi.w	#$1960,d0                       ; shorter than $1960?
	bcs.s	rtfi_ok
	bsr.w	fdc_abort                       ; stop the FDC
	bsr.w	fill_track_f5e295               ; fill with $f5 $e2 $95 $00
	bra.s	rtfi_ok

find_mark_fail:	; from: find_next_mark
	tst.w	d7                              ; index seen?
	beq.s	find_next_mark                  ; no: keep sampling
	clr.w	d0                              ; d0 = 0: no more marks
	rts


;----------------------------------------------------------------------
; Find the next $a1 $a1 + mark (>= $f8) from a0 up to offset d0 -> d0, d1 = mark
;----------------------------------------------------------------------
find_next_mark:	; from: orphan_rts, rtfi_timeout, scan_track_sectors, find_next_id, read_track_find_index
	bsr.s	sample_dma_address              ; DMA position
	subq.l	#3,d0                           ; minus 3
	sub.l	a0,d0                           ; bytes available from a0
	bcs.s	find_mark_fail                  ; none
find_mark_loop:
	subq.w	#1,d0
	bcs.s	find_mark_fail
find_mark_a1_loop:
	cmpi.b	#$a1,(a0)+                      ; find $a1
	dbeq	d0,find_mark_a1_loop
	bne.s	find_mark_fail
	cmpi.b	#$a1,(a0)                       ; second $a1?
	bne.s	find_mark_loop
	move.b	$1(a0),d1                       ; mark byte
	cmpi.b	#$f8,d1                         ; mark >= $f8?
	bcs.s	find_mark_loop
	move.l	a0,d0                           ; d0 = offset of the mark - 1
	subi.l	#track_buf,d0
	rts


;----------------------------------------------------------------------
; Once: take the CRC bytes used in ID/data fields from the key track (+$1000)
;----------------------------------------------------------------------
load_crc_from_key_track:	; from: build_track_image, copy_disk_protected
	lea	crc_loaded,a0                   ; first call?
	cmpi.b	#$1,(a0)
	bne.s	load_crc_ret
	addq.b	#1,(a0)
	move.w	track_buf_1000,crc_code         ; from key track + $1000
load_crc_ret:
	rts


;----------------------------------------------------------------------
; Sample the DMA address (two consistent reads) -> d0, dma_pos
;----------------------------------------------------------------------
sample_dma_address:	; from: find_next_mark, read_track_find_index
	tst.w	d7                              ; index seen?
	beq.s	sample_dma_timeout
	move.l	dma_pos,d0                      ; use the final position
	rts

sample_dma_timeout:
	subq.l	#1,dma_timeout                  ; timeout--
	beq.s	sample_dma_abort
	btst	#$5,$fffa01                     ; index pulse?
	bne.s	sample_dma_read
sample_dma_index:
	st	d7                              ; d7 = -1: index seen
sample_dma_read:
	move.b	$9(a6),d6                       ; DMA low byte
	bsr.w	dma_get_address                 ; DMA address
	cmp.b	d6,d0                           ; changed meanwhile?
	bne.s	sample_dma_address
	move.l	d0,dma_pos                      ; dma_pos
	rts

sample_dma_abort:
	bsr.w	rtfi_timeout                    ; stop the FDC
	bra.s	sample_dma_index


init_id_list:	; from: copy_disk_protected
	clr.w	dp_num_sectors(a4)              ; num_sectors = 0
	lea	sector_buf,a1                   ; a1 = ID time list
	clr.l	d2
	rts


;----------------------------------------------------------------------
; Read Address loop: store FDC status + time of each ID in sector_buf and
; the ID bytes (via DMA) in id_fields -> d0 = number of IDs
;----------------------------------------------------------------------
read_ids_short:	; from: op_0c_write_special_sectors, op_40_check_special_written
	moveq	#8,d6                           ; 8 IDs
	move.w	#$48,d2                         ; d2 = $48
	move.l	#sector_list,d0                 ; DMA to sector_list
	lea	sector_buf,a1
	bra.s	read_ids_start


read_ids_timed:	; from: copy_disk_protected
	bsr.w	fdc_abort                       ; stop the FDC
	move.w	dp_first_mark(a4),d2            ; d2 = first mark position
	move.w	d2,d6
	cmpi.w	#$200,d2                        ; limit to $200
	bcs.s	read_ids_min
	move.w	#$200,d2
	bra.s	read_ids_set_buffer

read_ids_min:
	cmpi.w	#$10,d2                         ; at least $10
	bcc.s	read_ids_set_buffer
	moveq	#16,d2
read_ids_set_buffer:
	move.l	#id_fields,d0                   ; DMA to id_fields
read_ids_start:	; from: read_ids_short
	mulu.w	#$7,d2                          ; timeout = 3.5 * d2 + $ad40
	lsr.w	#1,d2
	addi.w	#$ad40,d2
	clr.w	num_sectors                     ; num_sectors = 0
	bsr.w	dma_set_address
	bsr.w	dma_read_mode
	cmpi.w	#$10,d6                         ; short: wait for the index first
	bcc.s	read_ids_first
	move.w	#$d4,(a6)                       ; Force Interrupt on index pulse
	moveq	#-1,d7
read_ids_wait_index:
	btst	#$5,$fffa01                     ; wait for the index pulse
	dbeq	d7,read_ids_wait_index
read_ids_first:
	move.w	#$c0,(a6)                       ; Read Address
	clr.l	d6
	move.b	drive_speed,d6                  ; speed factor
	move.l	d2,d0                           ; timeout - 8
	subq.w	#8,d0
read_ids_loop:
	btst	#$5,$fffa01                     ; wait for the ID
	dbeq	d0,read_ids_loop
	bne.s	read_ids_end                    ; timeout
	move.w	(a6),(a1)+                      ; store the FDC status
	move.w	#$c0,(a6)                       ; Read Address again
	addq.w	#1,num_sectors                  ; num_sectors++
	move.l	d2,d1                           ; elapsed time
	sub.l	d0,d1
	lsl.l	#4,d1                           ; time = elapsed * 16 / speed
	divu.w	d6,d1
	move.w	d1,(a1)+                        ; store the time
	subq.w	#4,d0                           ; timeout - 4
	bcc.s	read_ids_loop
read_ids_end:
	moveq	#-1,d1                          ; end marker
	move.l	d1,(a1)
	cmpa.l	#sector_buf,a1                  ; nothing read?
	beq.s	read_ids_done
	moveq	#2,d1                           ; let 3 more Read Address finish
read_ids_drain_loop:
	btst	#$5,$fffa01                     ; MFP GPIP, FDC/HDC interrupt (low = done)
	dbeq	d0,read_ids_drain_loop
	move.w	#$c0,(a6)                       ; FDC Read Address
	moveq	#-1,d0
	dbra	d1,read_ids_drain_loop
read_ids_done:
	bsr.w	fdc_abort                       ; stop the FDC
	move.w	num_sectors,d0                  ; d0 = number of IDs
	rts


;----------------------------------------------------------------------
; Append the sectors flagged as special to the verify script
;----------------------------------------------------------------------
emit_special_sector_script:	; from: emit_script_scheme_c, emit_track_script
	move.b	#$c,(a4)+                       ; opcode $0c
	move.b	special_count_1,(a4)+           ; count * 4
	movea.l	sector_list_end,a3
special_script_loop:
	btst	#$7,(a3)                        ; special?
	beq.s	special_script_next
	move.l	$2(a3),(a4)+                    ; ID bytes and CRC
	move.w	$6(a3),(a4)+
	bsr.s	script_add_sector               ; add the sector
	move.w	#$4000,(a4)+                    ; opcode $40
special_script_next:
	lea	-$12(a3),a3                     ; previous entry
	cmpa.l	#sector_list,a3
	bcc.s	special_script_loop
	rts


; Four bytes copied here from the copyright string (expected "SYST")
key_syst:	; from: script_add_sector
	dc.b	$00
key_syst_1:	; from: script_add_sector
	dc.b	$00
key_syst_2:	; from: script_add_sector
	dc.b	$00
key_syst_3:	; from: script_add_sector
	dc.b	$00

;----------------------------------------------------------------------
; Append one sector of sector_list (a3) to the verify script (a4) and the
; data to the image buffer (a5).  Checks the "SYST" key bytes on the way.
;----------------------------------------------------------------------
script_add_sector:	; from: emit_script_scheme_c, emit_special_sector_script, emit_script_scheme_dup, emit_track_script
	move.l	a4,script2_ptr
	move.l	a5,dma_pos
	lea	copyright+8-$7128,a4            ; a4 = copyright - $7064
	move.l	$7128(a4),key_syst              ; key_syst = "SYST"
	movea.l	script2_ptr,a4
	clr.w	f_sync_in_data
	clr.w	f_data_not_uniform
	btst	#$4,(a3)                        ; no data field?
	bne.w	add_sector_ret
	cmpi.b	#$54,key_syst_3                 ; tamper check: "T"
	bne.w	verify_special_sectors          ; wrong: jump into verify_special_sectors
	move.b	#$24,(a4)+                      ; "$" = opcode $24
	move.b	(a3),(a4)+                      ; flags
	move.b	$2(a3),d0                       ; track
	move.b	$4(a3),d4                       ; sector
	tst.w	f_fix_id_bit4                   ; fix bit 4?
	beq.s	add_sector_id
	bclr	#$4,d0
	bclr	#$4,d4
add_sector_id:
	move.b	d0,(a4)+                        ; track
	move.b	d4,(a4)+                        ; sector
	clr.l	d0
	move.w	$e(a3),d0                       ; length
	move.w	d0,d4
	bclr	#$0,d0                          ; even length
	cmpi.b	#$53,key_syst                   ; tamper check: "S"
	bne.w	script_dispatch                 ; wrong: jump into script_dispatch
	btst	#$2,(a3)                        ; bit 2: fuzzy?
	beq.s	add_sector_data
	cmpi.b	#$59,key_syst_1                 ; tamper check: "Y"
	bne.w	read_psg_port_a                 ; wrong: jump into read_psg_port_a
	btst	#$7,(a3)                        ; special?
	bne.s	add_sector_fuzzy
	cmpi.b	#$2,$1(a3)                      ; ordinal < 2?
	bcs.s	add_sector_data
add_sector_fuzzy:
	clr.l	d1
	move.b	$1(a3),d1                       ; ordinal * 16 bytes
	lsl.w	#4,d1
	move.w	d1,(a4)+                        ; length
	move.l	a5,d2
	cmpi.b	#$53,key_syst_2                 ; tamper check: "S"
	bne.w	start                           ; wrong: restart the program
	bra.s	add_sector_fuzzy_copy

add_sector_fuzzy_loop:
	move.b	(a5)+,(a4)+                     ; copy the bytes
add_sector_fuzzy_copy:
	dbra	d1,add_sector_fuzzy_loop
	add.l	d0,d2                           ; skip the full length
	movea.l	d2,a5
	bra.s	add_sector_align

add_sector_data:
	move.w	d0,(a4)+                        ; length
	move.b	(a5),d2                         ; first byte
	move.b	d2,data_uniform_byte
	clr.w	d3                              ; d3 = 0: uniform
	bra.s	add_sector_data_next

add_sector_data_loop:
	move.b	(a5)+,d1
	cmp.b	d2,d1
	beq.s	add_sector_data_store           ; different byte
	st	d3
add_sector_data_store:
	move.b	d1,(a4)+
	cmpi.b	#$f5,d1                         ; sync byte $f5..$f7?
	bcs.s	add_sector_data_next
	cmpi.b	#$f8,d1
	bcc.s	add_sector_data_next
	st	f_sync_in_data                  ; sync byte in data
	cmpi.b	#$2,cur_track_b                 ; track 2?
	bne.s	add_sector_data_next
	st	f_patch_fffb                    ; patch the fffb check later
add_sector_data_next:
	dbra	d0,add_sector_data_loop
	move.b	d3,f_data_not_uniform           ; f_data_not_uniform
add_sector_align:
	btst	#$0,d4                          ; odd length?
	beq.s	add_sector_ret
	addq.l	#2,a5                           ; skip the pad
add_sector_ret:
	rts

f_data_not_uniform:	; from: script_add_sector, emit_track_script
	dc.b	$00
data_uniform_byte:	; from: script_add_sector
	dc.b	$00

;----------------------------------------------------------------------
; Read the sectors flagged as special again and check them for fuzzy bits
;----------------------------------------------------------------------
read_special_sectors:	; from: read_all_sectors
	movea.l	sector_list_end,a1              ; from the last entry backwards
read_special_loop:
	btst	#$7,(a1)                        ; special?
	beq.s	read_special_next
	bsr.s	read_sector_verify              ; read the sector
	btst	#$3,(a1)                        ; read error?
	beq.s	read_special_next
	btst	#$1,(a1)                        ; data mark present?
	beq.s	read_special_fuzzy
	cmpi.w	#$80,$e(a1)                     ; at least $80 bytes?
	bcs.s	read_special_next
read_special_fuzzy:
	bsr.w	detect_fuzzy_sector             ; check for fuzzy bits
read_special_next:
	lea	-$12(a1),a1
	cmpa.l	#sector_list,a1
	bcc.s	read_special_loop               ; first entry done?
	rts


;----------------------------------------------------------------------
; Read one sector into the buffer, flag errors, then apply known patches
;----------------------------------------------------------------------
read_sector_verify:	; from: read_all_sectors, read_special_sectors
	movea.l	a0,a2                           ; a2 = buffer
	clr.l	d1
	move.w	$e(a1),d1                       ; data length
	btst	#$0,d1                          ; odd?
	beq.s	read_sector_verify_even
	addq.w	#1,d1                           ; round up
read_sector_verify_even:
	move.l	a0,d0                           ; d0 = buffer address
	adda.l	d1,a0                           ; advance the buffer
	bsr.w	read_sector_entry               ; read the sector
	or.b	d7,(a1)                         ; merge the error bits
	btst	#$4,(a1)                        ; no data field?
	beq.s	read_sector_patch
	movea.l	a2,a0                           ; undo the advance
read_sector_verify_ret:
	rts

read_sector_patch:
	btst	#$3,d7                          ; CRC error?
	bne.s	read_sector_verify_ret
	bsr.w	patch_boot_scheme_b             ; boot scheme B
	bne.s	read_sector_verify_ret
	bsr.w	patch_boot_scheme_a             ; boot scheme A
	bne.s	read_sector_verify_ret
	bsr.s	patch_track6_sector10           ; track 6 sector 10
	bne.s	read_sector_verify_ret
	bsr.s	patch_track2_sector2            ; track 2 sector 2
	bra.s	read_sector_verify_ret


;----------------------------------------------------------------------
; Known protection patches applied to sector data (track 2 sector 2, track 6
; sector 10, boot sector variants compared at the offsets in boot_*_offsets)
;----------------------------------------------------------------------
patch_track2_sector2:	; from: read_sector_verify
	cmpi.b	#$2,cur_track_b                 ; track 2?
	bne.s	patch_t2s2_ret
	cmpi.b	#$2,d1                          ; sector 2?
	bne.s	patch_t2s2_ret
	movem.l	a1-a2,-(sp)
	lea	pat_t2s2,a1                     ; pat_t2s2 at +$82
	lea	$82(a2),a2
	moveq	#3,d0                           ; 4 longs
patch_t2s2_loop:
	cmpm.l	(a1)+,(a2)+
	dbne	d0,patch_t2s2_loop
	movem.l	(sp)+,a1-a2
	bne.s	patch_t2s2_ret
	move.l	#$55390001,$82(a2)              ; patch: move.w #1,$1752
	move.w	#$1752,$86(a2)
	rts

patch_t2s2_ret:
	moveq	#0,d0
	rts


patch_track6_sector10:	; from: read_sector_verify
	cmpi.b	#$6,cur_track_b                 ; track 6?
	bne.s	patch_t6s10_ret
	cmpi.b	#$a,d1                          ; sector 10?
	bne.s	patch_t6s10_ret
	movem.l	a1-a2,-(sp)
	lea	pat_t6s10,a1                    ; pat_t6s10 at +0
	moveq	#3,d0                           ; 4 longs
patch_t6s10_loop:
	cmpm.l	(a1)+,(a2)+
	dbne	d0,patch_t6s10_loop
	movem.l	(sp)+,a1-a2
	bne.s	patch_t6s10_ret
	move.l	#$4e714e71,d0                   ; nop nop nop at +2
	move.l	d0,$2(a2)
	move.w	d0,$6(a2)
	rts

patch_t6s10_ret:
	moveq	#0,d0
	rts


patch_boot_scheme_a:	; from: read_sector_verify
	movem.l	d1/a0-a1,-(sp)
	tst.w	cur_track                       ; track 0?
	bne.s	patch_boot_a_track2
	cmpi.b	#$1,d1                          ; sector 1?
	bne.s	patch_boot_a_ret
	lea	boot_a_offsets,a0
	lea	boot_a_match,a1
	bsr.w	compare_at_offsets              ; original bytes there?
	beq.s	patch_boot_a_apply
	lea	boot_a_offsets,a0
	lea	boot_a_replace,a1
	bsr.w	compare_at_offsets              ; already patched?
	beq.s	patch_boot_a_flag
	bne.s	patch_boot_a_ret
patch_boot_a_apply:
	lea	boot_a_offsets,a0
	lea	boot_a_replace,a1
	bsr.w	store_at_offsets                ; store the patch
	st	f_fix_id_bit4                   ; fix bit 4 of the IDs
patch_boot_a_flag:
	st	f_patched_boot_a
patch_boot_a_ret:
	movem.l	(sp)+,d1/a0-a1
	tst.w	f_patched_boot_a
	rts

patch_boot_a_track2:
	tst.w	f_patched_boot_a                ; scheme A found on track 0?
	beq.s	patch_boot_a_ret
	cmpi.b	#$2,cur_track_b                 ; track 2?
	bne.s	patch_boot_a_ret
	cmpi.b	#$f5,d1                         ; sector $f5?
	bne.s	patch_boot_a_ret
	lea	boot_a2_offsets,a0
	lea	boot_a2_match,a1
	bsr.w	compare_at_offsets              ; original bytes there?
	bne.s	patch_boot_a_ret
	lea	boot_a2_offsets,a0
	lea	boot_a2_replace,a1
	bsr.w	store_at_offsets                ; store the patch
	bra.s	patch_boot_a_ret


patch_boot_scheme_b:	; from: read_sector_verify
	movem.l	d1/a0-a1,-(sp)
	tst.w	cur_track                       ; track 0?
	bne.s	patch_boot_b_later
	cmpi.b	#$1,d1                          ; sector 1?
	bne.s	patch_boot_b_ret
	lea	boot_b_offsets,a0
	lea	boot_b_match,a1
	bsr.w	compare_at_offsets              ; original bytes there?
	bne.s	patch_boot_b_ret
	lea	boot_b_offsets,a0
	lea	boot_b_replace,a1
	bsr.w	store_at_offsets                ; store the patch
	st	f_fix_id_bit4                   ; fix bit 4 of the IDs
	st	f_patched_boot_b
patch_boot_b_ret:
	movem.l	(sp)+,d1/a0-a1
	tst.w	f_patched_boot_b
	rts

patch_boot_b_later:
	tst.w	f_patched_boot_b                ; scheme B found on track 0?
	beq.s	patch_boot_b_ret
	cmpi.b	#$1,cur_track_b                 ; track 1?
	bne.s	patch_boot_b_track6
	cmpi.b	#$f5,d1                         ; sector $f5?
	bne.s	patch_boot_b_ret
	lea	boot_b2_offsets,a0
	lea	boot_b2_match,a1
	bsr.s	compare_at_offsets              ; original bytes there?
	bne.s	patch_boot_b_ret
	lea	boot_b2_offsets,a0
	lea	boot_b2_replace,a1
	bsr.s	store_at_offsets                ; store the patch
	bra.s	patch_boot_b_ret

patch_boot_b_track6:
	cmpi.b	#$6,cur_track_b                 ; track 6?
	bne.s	patch_boot_b_ret
	cmpi.b	#$f5,d1                         ; sector $f5?
	bne.s	patch_boot_b_ret
	cmpi.b	#$67,$2c2(a2)                   ; beq.s at +$2c2?
	bne.s	patch_boot_b_ret
	move.b	#$60,$2c2(a2)                   ; -> bra.s
	bra.s	patch_boot_b_ret


;----------------------------------------------------------------------
; Compare the bytes at the offsets in (a0) with the values in (a1)
;----------------------------------------------------------------------
compare_at_offsets:	; from: patch_boot_scheme_a, patch_boot_scheme_b
	moveq	#0,d0                           ; count - 1
	move.w	(a0)+,d0
compare_offsets_loop:
	move.w	(a0)+,d1                        ; offset
	move.b	$0(a2,d1.w),d1                  ; byte in the sector
	cmp.b	(a1)+,d1                        ; expected?
	dbne	d0,compare_offsets_loop
	rts


;----------------------------------------------------------------------
; Store the bytes in (a1) at the offsets in (a0)
;----------------------------------------------------------------------
store_at_offsets:	; from: patch_boot_scheme_a, patch_boot_scheme_b
	moveq	#0,d0                           ; count - 1
	move.w	(a0)+,d0
store_offsets_loop:
	move.w	(a0)+,d1                        ; offset
	move.b	(a1)+,$0(a2,d1.w)               ; store
	dbra	d0,store_offsets_loop
	rts

boot_a_offsets:	; from: patch_boot_scheme_a
	dc.w	$0007,$00c9,$00e1,$00f5,$012b,$015d,$016f,$01fe
	dc.w	$01ff
boot_a_match:	; from: patch_boot_scheme_a
	dc.b	$f7,$f7,$f5,$b1,$fa,$c1,$5e,$72
boot_a_replace:	; from: patch_boot_scheme_a
	dc.b	$e7,$e7,$e5,$a1,$ea,$d1,$5e,$b2
boot_a2_offsets:	; from: patch_boot_scheme_a
	dc.w	$0006,$00e1,$00f9,$0115,$0129,$015f,$0191,$01a3
boot_a2_match:	; from: patch_boot_scheme_a
	dc.b	$55,$05,$cd,$a5,$bc,$94,$24
boot_a2_replace:	; from: patch_boot_scheme_a
	dc.b	$57,$07,$cf,$a7,$ba,$96,$22
boot_b_offsets:	; from: patch_boot_scheme_b
	dc.w	$0006,$00c3,$00d7,$010d,$013f,$0151,$01fe,$01ff
boot_b_match:	; from: patch_boot_scheme_b
	dc.b	$f7,$f5,$ab,$fa,$bb,$72,$90
boot_b_replace:	; from: patch_boot_scheme_b
	dc.b	$e7,$e5,$bb,$ea,$ab,$72,$c0
boot_b2_offsets:	; from: patch_boot_scheme_b
	dc.w	$0005,$00e5,$00fd,$0111,$0147,$0175,$0183
boot_b2_match:	; from: patch_boot_scheme_b
	dc.b	$59,$09,$61,$30,$98,$c8
boot_b2_replace:	; from: patch_boot_scheme_b
	dc.b	$5f,$0f,$67,$32,$9e,$ca
pat_t6s10:	; from: patch_track6_sector10
	dc.w	$1092,$91b9,$0000,$10c8,$303c,$1f40,$51c8,$fffe
pat_t2s2:	; from: patch_track2_sector2
	dc.w	$4279,$00ff,$8240,$4ef9,$0001,$0000,$4444,$2020

all_bytes_even:	; from: detect_fuzzy_sector
	movem.l	d0-d1/a0,-(sp)                  ; 160 bytes
	movea.l	a2,a0
	move.w	#$9f,d0
all_even_loop:
	move.b	(a0)+,d1
	bclr	#$0,d1                          ; bit 0 set?
	tst.b	d1
	dbne	d0,all_even_loop
	movem.l	(sp)+,d0-d1/a0
	rts


;----------------------------------------------------------------------
; Read the sector twice and compare: a difference marks a fuzzy sector
;----------------------------------------------------------------------
detect_fuzzy_sector:	; from: read_all_sectors, read_special_sectors
	movem.l	d4-d6,-(sp)                     ; read again
	move.l	a0,d0
	bsr.w	read_sector_entry               ; read the sector
	beq.s	fuzzy_read_failed               ; read ok: compare
	cmpi.b	#$8,d7                          ; CRC error only?
	bne.s	fuzzy_ret
	bsr.w	compare_sector_reads            ; compare the two reads
	beq.s	fuzzy_restore_a0                ; equal: not fuzzy
	movea.l	d0,a0
	move.w	d2,d4                           ; d4 = first difference
	bsr.s	read_sector_entry               ; read once more
	beq.s	fuzzy_read_failed
	bsr.w	compare_sector_reads            ; compare again
	cmp.w	d4,d2                           ; earliest difference
	bcs.s	fuzzy_classify
	move.w	d4,d2
fuzzy_classify:
	btst	#$1,(a1)                        ; data mark present?
	bne.s	fuzzy_check_length
	cmpi.w	#$b0,d2                         ; difference at $b0 or later?
	bcc.s	fuzzy_mark_sector
	bsr.s	all_bytes_even                  ; all bytes even?
	beq.s	fuzzy_set_flag
	cmpi.w	#$5053,(a2)                     ; "PS"?
	bne.s	fuzzy_mark_sector
fuzzy_set_flag:
	st	f_fuzzy_sector                  ; f_fuzzy_sector
	bra.s	fuzzy_mark_sector

fuzzy_check_length:
	cmpa.l	last_sector,a1                  ; last sector?
	beq.s	fuzzy_mark_sector
	move.w	$e(a1),d4                       ; length - difference
	sub.w	d2,d4
	bcs.s	fuzzy_restore_a0                ; difference past the end?
	cmpi.w	#$40,d4                         ; less than $40 left?
	bcs.s	fuzzy_restore_a0
fuzzy_mark_sector:
	bset	#$2,(a1)                        ; bit 2: fuzzy
	lsr.w	#4,d2                           ; difference / 16
	move.b	d2,$1(a1)                       ; as the ordinal
	btst	#$1,(a1)                        ; data mark present?
	beq.s	fuzzy_restore_a0
	btst	#$7,(a1)                        ; special?
	bne.s	fuzzy_restore_a0
	clr.b	$1(a1)                          ; ordinal 0
fuzzy_restore_a0:
	movea.l	d0,a0
fuzzy_ret:
	movem.l	(sp)+,d4-d6
	rts

fuzzy_read_failed:
	bclr	#$3,(a1)                        ; clear the error bit
	move.l	a0,d0
	move.l	a2,d2                           ; a2 = buffer
	move.w	$e(a1),d1                       ; length
	bra.s	fuzzy_copy

fuzzy_copy_loop:
	move.b	(a0)+,(a2)+                     ; copy the data read
fuzzy_copy:
	dbra	d1,fuzzy_copy_loop
	movea.l	d2,a2
	bra.s	fuzzy_restore_a0


read_sector_entry:	; from: detect_fuzzy_sector, read_sector_verify
	clr.l	d1                              ; sector:track
	move.b	$4(a1),d1
	swap	d1
	move.b	$2(a1),d1
	bsr.w	fdc_read_sector                 ; read the sector
	bsr.w	fdc_wait_status
	andi.w	#$38,d7                         ; bits 3-5: CRC, RNF, record type
	rts


;----------------------------------------------------------------------
; Compare two sector reads -> Z set if equal, d2 = first difference
;----------------------------------------------------------------------
compare_sector_reads:	; from: detect_fuzzy_sector
	move.l	a0,d0
	move.w	$e(a1),d1                       ; length
	cmpi.w	#$20,d1                         ; at least 32
	bcc.s	compare_reads_start
	moveq	#32,d1
compare_reads_start:
	subq.w	#1,d1
	clr.l	d2                              ; d2 = position
	movem.l	a2,-(sp)
compare_reads_loop:
	addq.w	#1,d2                           ; compare byte by byte
	cmpm.b	(a0)+,(a2)+
	dbne	d1,compare_reads_loop
	beq.s	compare_reads_ret               ; equal
	subq.l	#1,a0                           ; back to the difference
	subq.l	#1,a2
compare_reads_7bit:
	move.b	(a0)+,d5                        ; compare ignoring bit 7
	move.b	(a2)+,d6
	bclr	#$7,d5
	bclr	#$7,d6
	cmp.b	d5,d6
	dbne	d1,compare_reads_7bit
	bne.s	compare_reads_ret               ; still different
	move.b	#$1,f_weak_msb                  ; only bit 7 differs
compare_reads_ret:
	movem.l	(sp)+,a2
	rts


;----------------------------------------------------------------------
; Read a sector with a timed start (position derived from drive_speed)
;----------------------------------------------------------------------
read_sector_timed:	; from: read_all_sectors
	movem.l	d0-d7/a0-a1,-(sp)
	clr.l	d1
	clr.l	d2
	clr.l	d5
	move.b	$2(a1),d1                       ; track
	bsr.w	fdc_set_track_reg               ; track register
	clr.l	d0
	move.b	drive_speed,d0                  ; speed
	cmpi.b	#$1,$1(a1)                      ; first of duplicates?
	beq.s	timed_calc_delay
	move.l	a1,d4                           ; remember the entry
	move.b	$2(a1),d1                       ; track, sector
	move.b	$4(a1),d2
timed_find_prev_loop:
	lea	-$12(a1),a1                     ; find the previous entry with the same ID
	cmp.b	$2(a1),d1
	bne.s	timed_find_prev_loop
	cmp.b	$4(a1),d2
	bne.s	timed_find_prev_loop
	move.w	$c(a1),d5                       ; its data offset
	mulu.w	d0,d5                           ; d5 = offset * speed / 16
	lsr.l	#4,d5
	movea.l	d4,a1
timed_calc_delay:
	move.w	$c(a1),d2                       ; this data offset
	addi.w	#$200,d2                        ; + $200
	mulu.w	d0,d2                           ; d2 = (offset + $200) * speed / 16 - d5
	lsr.l	#4,d2
	sub.w	d5,d2
	move.w	#$84,$2(a6)                     ; sector register
	move.b	$4(a1),d0                       ; sector
	move.w	d0,(a6)
	move.l	a0,d0                           ; DMA address
	move.l	a0,dma_pos                      ; dma_pos
	bsr.w	dma_set_address
	bsr.w	dma_read_mode
	move.w	#$d4,(a6)                       ; Force Interrupt on index pulse
	moveq	#-1,d0                          ; timeout
timed_wait_index:
	btst	#$5,$fffa01                     ; wait for the index pulse
	dbeq	d0,timed_wait_index
timed_wait_delay:
	btst	#$5,$fffa01                     ; delay d5 loops
	dbra	d5,timed_wait_delay
	move.w	#$80,(a6)                       ; Read Sector
	bra.s	timed_watch_loop

timed_store_pos:
	move.w	d0,dma_pos_w                    ; remember the DMA position
timed_watch_loop:
	btst	#$5,$fffa01                     ; wait for the IRQ
	dbeq	d2,timed_watch_loop
	beq.s	timed_read_done                 ; done
	bsr.w	dma_get_address                 ; DMA address
	cmp.w	dma_pos_w,d0                    ; changed?
	bne.s	timed_store_pos
	bsr.w	fdc_abort                       ; timeout: stop the FDC
	moveq	#16,d0                          ; bit 4: not found
	bra.s	timed_set_flags

timed_read_done:
	move.w	(a6),d0                         ; FDC status
	andi.b	#$8,d0                          ; bit 3: CRC
timed_set_flags:
	or.b	d0,(a1)                         ; merge into the flags
	btst	#$4,(a1)                        ; no data field?
	bne.s	timed_read_ret
	btst	#$1,(a1)                        ; data mark present?
	beq.s	timed_read_ret
	move.w	$e(a1),d0                       ; length
	beq.s	timed_read_ret
	subq.w	#1,d0
timed_fix_marks_loop:
	move.b	(a0)+,d1                        ; sync bytes in the data -> $e5
	cmpi.b	#$f5,d1
	bcs.s	timed_fix_marks_next
	cmpi.b	#$f8,d1
	bcc.s	timed_fix_marks_next
	move.b	#$e5,-$1(a0)
timed_fix_marks_next:
	dbra	d0,timed_fix_marks_loop
timed_read_ret:
	movem.l	(sp)+,d0-d7/a0-a1
	rts


;----------------------------------------------------------------------
; FDC Restore with the system step rate
;----------------------------------------------------------------------
fdc_restore:	; from: set_steprate_restore
	move.w	#$80,$2(a6)                     ; command/status register
	bsr.w	fdc_wait_done
	move.w	$440.w,d0                       ; seekrate
	andi.w	#$3,d0                          ; step rate bits
	move.w	d0,(a6)                         ; Restore
	rts


;----------------------------------------------------------------------
; Select drive (dp_drive) and side (dp_side) through PSG port A
;----------------------------------------------------------------------
select_drive_side:	; from: select_and_restore, fdc_error_alert, seek_and_show
	moveq	#2,d0                           ; bit 1 = drive A off
	tst.b	dp_drive+1(a4)                  ; drive B?
	bne.s	select_side_bit
	moveq	#4,d0                           ; bit 2 = drive B off
select_side_bit:
	tst.b	dp_side+1(a4)                   ; side 1?
	bne.s	select_write_psg
	bset	#$0,d0                          ; bit 0 = side 0
select_write_psg:
	move.w	sr,-(sp)
	ori.w	#$700,sr
	move.b	#$e,(a5)                        ; PSG register 14 (port A)
	move.b	(a5),d1                         ; current value
	andi.b	#$f8,d1                         ; keep the other bits
	or.b	d0,d1
	move.b	d1,$2(a5)                       ; write port A
	move.w	(sp)+,sr
	rts


;----------------------------------------------------------------------
; Wait for Write Track to finish; with 9 sectors and no verify the command is
; aborted once most of the track is written
;----------------------------------------------------------------------
fdc_wait_write_track:	; from: format_disk, copy_disk_normal
	cmpi.b	#$a,dp_spt+1(a4)                ; 10+ sectors?
	bcc.s	fdc_wait_result
	tst.b	verify_flag                     ; verify on?
	bne.s	fdc_wait_result
	bsr.w	wait_dma_change                 ; DMA running?
	beq.s	fdc_wait_result
wait_wt_loop:
	subq.l	#1,d7                           ; timeout--
	beq.s	fdc_wait_result
	btst	#$5,$fffa01                     ; FDC done?
	beq.s	fdc_error_bits
	bsr.w	dma_get_address                 ; DMA address
	cmpi.l	#track_buf_17c0,d0              ; written up to +$17c0?
	bcs.s	wait_wt_loop
	bsr.s	fdc_abort                       ; stop the FDC
	bsr.s	fdc_error_bits                  ; error bits
	clr.l	d7                              ; d7 = 0: ok
	rts


fdc_wait_result_rw:	; from: op_4c_verify_sectors, copy_disk_normal
	bsr.s	fdc_wait_result                 ; lost data, CRC, RNF
	andi.w	#$1c,d7
	rts


;----------------------------------------------------------------------
; Wait for the FDC and return error bits in d7: -1 timeout, $100 DMA error,
; else status & $5c
;----------------------------------------------------------------------
fdc_wait_result:	; from: fdc_wait_result_rw, format_disk, fdc_wait_write_track, write_track_from_script, copy_disk_normal
	bsr.s	fdc_wait_done
	tst.l	d7                              ; timeout?
	beq.s	fdc_timeout

fdc_error_bits:	; from: fdc_wait_write_track
	move.w	#$90,$2(a6)                     ; sector count register
	move.w	$2(a6),d7                       ; DMA status
	btst	#$0,d7                          ; DMA error?
	beq.s	fdc_timeout
	move.w	#$80,$2(a6)                     ; command/status register
	move.w	(a6),d7                         ; FDC status
	andi.w	#$5c,d7                         ; WP, RNF, CRC, lost data
	rts

fdc_timeout:	; from: fdc_wait_result
	moveq	#-1,d7                          ; timeout
	rts


;----------------------------------------------------------------------
; Wait for the FDC to finish -> d7 = status
;----------------------------------------------------------------------
fdc_wait_status:	; from: script_finish, script_run_second, script_build_image, op_70_sync_read_track, op_60_long_track_write, op_54_shifted_sector_write, ...
	bsr.s	fdc_wait_done
	move.w	(a6),d7                         ; d7 = status
	rts


;----------------------------------------------------------------------
; Force Interrupt (immediate), then wait
;----------------------------------------------------------------------
fdc_abort:	; from: op_70_sync_read_track, op_6c_partial_write_track, op_60_long_track_write, timed_write_sector_at, read_track_check_sig, op_54_shifted_sector_write, ...
	move.w	#$d8,(a6)                       ; Force Interrupt immediate
	bsr.s	fdc_delay
	move.w	#$d0,(a6)                       ; clear Force Interrupt

;----------------------------------------------------------------------
; Wait until the FDC is not busy (timeout -> Force Interrupt)
;----------------------------------------------------------------------
fdc_wait_done:	; from: fdc_wait_status, fdc_wait_result, set_steprate_restore, fdc_restore, read_key_track
	bsr.s	fdc_delay
	moveq	#6,d7                           ; timeout $60000
	swap	d7
	move.w	(a6),d7                         ; FDC status
	btst	#$0,d7                          ; busy?
	beq.s	fdc_wait_ret

fdc_wait_irq:	; from: rtfi_timeout
	subq.l	#1,d7                           ; timeout--
	beq.s	fdc_clear_force
	btst	#$5,$fffa01                     ; FDC IRQ?
	bne.s	fdc_wait_irq
fdc_wait_ret:	; from: fdc_wait_done
	rts

fdc_clear_force:	; from: read_ids_after_index
	move.w	#$d0,(a6)                       ; Force Interrupt

fdc_delay:	; from: fdc_wait_done, fdc_abort
	move.l	d7,-(sp)
	moveq	#32,d7                          ; 33 loops
fdc_delay_loop:
	dbra	d7,fdc_delay_loop
	move.l	(sp)+,d7
	rts


;----------------------------------------------------------------------
; Select drive/side, seek to dp_track and update the side/track display
;----------------------------------------------------------------------
seek_and_show:	; from: format_disk, copy_disk_protected, copy_disk_normal
	move.w	dp_side(a4),d0
	cmp.w	dp_shown_side(a4),d0            ; side changed?
	beq.s	seek_check_track
	move.w	d0,dp_shown_side(a4)
	ori.b	#$30,d0                         ; digit
	move.b	d0,txt_side_digit
	bsr.w	select_drive_side               ; select drive and side
	bsr.w	show_side
seek_check_track:
	clr.l	d0
	move.w	dp_track(a4),d0
	cmp.w	dp_shown_track(a4),d0           ; track changed?
	beq.s	fdc_seek_ret
	move.w	d0,dp_shown_track(a4)
	bsr.s	fdc_seek                        ; Seek
	divu.w	#$a,d0                          ; two digits
	ori.b	#$30,d0
	move.b	d0,txt_track_digits
	swap	d0
	ori.b	#$30,d0
	move.b	d0,txt_track_digit_lo
	bra.w	show_track


;----------------------------------------------------------------------
; FDC Seek to track d0
;----------------------------------------------------------------------
fdc_seek:	; from: seek_and_show, read_key_track
	move.w	#$86,$2(a6)                     ; data register
	move.w	d0,(a6)                         ; target track
	move.w	#$80,$2(a6)                     ; command/status register
	move.w	$440.w,d7                       ; seekrate
	andi.w	#$3,d7
	bset	#$4,d7                          ; Seek command
	move.w	d7,(a6)
fdc_seek_ret:	; from: seek_and_show
	rts


;----------------------------------------------------------------------
; Load the FDC track register with d1 (cached in fdc_track_reg)
;----------------------------------------------------------------------
fdc_set_track_reg:	; from: fdc_read_sector, fdc_write_sector_flags, op_54_shifted_sector_write, op_0c_write_special_sectors, advance_script, emit_track_script, ...
	cmp.w	fdc_track_reg_w,d1              ; same track?
	beq.s	fdc_track_reg_done
	move.w	#$82,$2(a6)                     ; track register
	move.w	d1,(a6)
	move.w	#$86,$2(a6)                     ; data register
	move.w	d1,(a6)
	move.w	#$80,(a6)                       ; command/status register
fdc_track_reg_done:
	move.l	d1,fdc_track_reg
	rts


;----------------------------------------------------------------------
; Read Sector: d1 = sector:track, d0 = DMA address
;----------------------------------------------------------------------
fdc_read_sector:	; from: op_60_long_track_write, op_4c_verify_sectors, verify_special_sectors, write_fuzzy_bits, read_sector_entry, op_24_write_verify
	bsr.s	fdc_set_track_reg
	swap	d1                              ; d1.w = sector

fdc_read_sector_cmd:	; from: format_disk, copy_disk_normal
	bsr.w	fdc_set_sector_dma              ; sector register, DMA address
	bsr.w	dma_read_mode
	move.w	#$80,(a6)                       ; Read Sector
	rts


;----------------------------------------------------------------------
; Write Sector with command flags d2: d1 = sector:track, d0 = DMA address
;----------------------------------------------------------------------
fdc_write_sector_flags:	; from: op_60_long_track_write, timed_write_sector_at, op_24_write_verify
	bsr.s	fdc_set_track_reg
	swap	d1
	bsr.w	fdc_set_sector_dma
	bsr.w	dma_write_mode
	ori.b	#$a0,d2                         ; Write Sector + flags
	move.w	d2,(a6)
	rts


;----------------------------------------------------------------------
; Write Sector: d1 = sector, d0 = DMA address
;----------------------------------------------------------------------
fdc_write_sector:	; from: format_disk, copy_disk_normal
	bsr.s	fdc_set_sector_dma
	bsr.w	dma_write_mode
	move.w	#$a0,(a6)                       ; Write Sector
	rts


;----------------------------------------------------------------------
; Read Track into track_buf
;----------------------------------------------------------------------
fdc_read_track:	; from: read_track_check_sig, copy_disk_protected, measure_drive_speed, read_key_track
	bsr.s	dma_set_track_buf

fdc_read_track_cmd:	; from: op_70_sync_read_track
	bsr.w	dma_read_mode
	move.w	#$e0,(a6)                       ; Read Track
	rts


;----------------------------------------------------------------------
; Write Track from track_buf
;----------------------------------------------------------------------
fdc_write_track:	; from: op_70_sync_read_track, write_track_until, format_disk, write_track_from_script, write_fuzzy_bits, copy_disk_normal
	bsr.s	dma_set_track_buf

fdc_write_track_cmd:	; from: op_60_long_track_write
	bsr.s	dma_write_mode
	move.w	#$f0,(a6)                       ; Write Track
	rts


;----------------------------------------------------------------------
; Wait for the index pulse, then Read Address three times into sector_list
;----------------------------------------------------------------------
read_ids_after_index:	; from: read_source_bpb
	move.l	#sector_list,d0                 ; DMA to sector_list
	bsr.s	dma_set_address
	bsr.s	dma_read_mode
	moveq	#6,d7                           ; timeout
	swap	d7
	moveq	#2,d0                           ; 3 Read Address
	move.w	#$d4,(a6)                       ; Force Interrupt on index pulse
rai_wait_index:
	subq.l	#1,d7                           ; timeout--
	beq.w	fdc_clear_force
	btst	#$5,$fffa01                     ; wait for the index pulse
	bne.s	rai_wait_index
rai_read_address:
	move.w	#$c0,(a6)                       ; Read Address
rai_wait_id:
	subq.l	#1,d7                           ; timeout--
	beq.w	fdc_clear_force
	btst	#$5,$fffa01                     ; wait for the ID
	bne.s	rai_wait_id
	dbra	d0,rai_read_address
	clr.l	d7                              ; d7 = 0: ok
	rts


dma_set_track_buf:	; from: fdc_write_track, fdc_read_track
	move.l	#track_buf,d0
	bra.s	dma_set_address


fdc_set_sector_dma:	; from: fdc_read_sector_cmd, fdc_write_sector_flags, fdc_write_sector
	move.w	#$84,$2(a6)                     ; sector register
	move.w	d1,(a6)

;----------------------------------------------------------------------
; DMA helpers
;----------------------------------------------------------------------
dma_set_address:	; from: op_70_sync_read_track, dma_set_track_buf, op_6c_partial_write_track, op_60_long_track_write, op_54_shifted_sector_write, op_40_check_special_written, ...
	move.b	d0,$9(a6)                       ; DMA base low
	lsr.l	#8,d0
	move.b	d0,$7(a6)                       ; DMA base mid
	lsr.l	#8,d0
	move.b	d0,$5(a6)                       ; DMA base high
	rts


dma_write_mode:	; from: fdc_write_track_cmd, op_6c_partial_write_track, fdc_write_sector_flags, op_54_shifted_sector_write, op_0c_write_special_sectors, fdc_write_sector, ...
	move.w	#$90,$2(a6)                     ; toggle read/write
	move.w	#$190,$2(a6)                    ; sector count register, write
	move.w	#$d,(a6)                        ; sector count = 13
	move.w	#$180,$2(a6)                    ; command register, write
	rts


dma_read_mode:	; from: fdc_read_track_cmd, fdc_read_sector_cmd, op_54_shifted_sector_write, op_40_check_special_written, read_ids_timed, read_ids_after_index, ...
	move.w	#$190,$2(a6)                    ; toggle write/read
	move.w	#$90,$2(a6)                     ; sector count register, read
	move.w	#$d,(a6)                        ; sector count = 13
	move.w	#$80,$2(a6)                     ; command register, read
	rts


;----------------------------------------------------------------------
; DMA address -> d0
;----------------------------------------------------------------------
dma_get_address:	; from: op_70_sync_read_track, op_6c_partial_write_track, op_60_long_track_write, read_track_check_sig, op_54_shifted_sector_write, write_track_until, ...
	clr.l	d0
	move.b	$5(a6),d0                       ; DMA base high
	swap	d0
	move.b	$7(a6),d0                       ; DMA base mid
	lsl.w	#8,d0
	move.b	$9(a6),d0                       ; DMA base low
	rts


;----------------------------------------------------------------------
; Wait until the DMA address has moved away from sector_list
;----------------------------------------------------------------------
wait_dma_start:	; from: format_disk
	moveq	#4,d7                           ; timeout $40000
	swap	d7
	move.l	#sector_list,d1                 ; start address
wait_dma_start_loop:
	bsr.s	dma_get_address
	cmp.w	d1,d0                           ; moved away?
	bne.s	wait_dma_start_ret
	subq.l	#1,d7
	bne.s	wait_dma_start_loop
wait_dma_start_ret:
	rts


; Second half of the tamper key ("numm" + 1)
key_numn:	; from: verify_rsc_checksums
	dc.b	'numn'

;----------------------------------------------------------------------
; Wait until the DMA address low byte changes (Z set on timeout)
;----------------------------------------------------------------------
wait_dma_change:	; from: op_70_sync_read_track, op_6c_partial_write_track, op_60_long_track_write, timed_write_sector_at, read_track_check_sig, fdc_wait_write_track, ...
	moveq	#4,d7                           ; timeout $40000
	swap	d7
	move.b	$9(a6),d0                       ; DMA low byte
wait_dma_change_loop:
	cmp.b	$9(a6),d0                       ; changed?
	bne.s	wait_dma_change_ret
	subq.l	#1,d7
	bne.s	wait_dma_change_loop
wait_dma_change_ret:
	rts


;----------------------------------------------------------------------
; VBL handler: when the floppy is idle, deselect both drives via PSG port A
;----------------------------------------------------------------------
vbl_deselect_drives:	; from: vbl_queue_entry
	tst.w	$43e.w                          ; floppy locked?
	bne.s	vbl_ret
	tst.w	drives_deselected               ; already deselected?
	bne.s	vbl_ret
	move.w	#$80,$ff8606                    ; DMA mode: FDC command/status
	move.w	$ff8604,d0                      ; FDC status
	btst	#$7,d0                          ; motor on?
	bne.s	vbl_ret
	move.b	#$e,$ff8800                     ; PSG register 14 (port A)
	move.b	$ff8800,d0                      ; PSG register select
	ori.b	#$7,d0                          ; deselect both drives, side 0
	move.b	d0,$ff8802                      ; write port A
	move.w	d0,drives_deselected
vbl_ret:
	rts


	section	data


; Copy of the system VBL queue (8 entries) plus vbl_deselect_drives
vbl_queue:	; from: prg_init
	dc.l	$00000000,$00000000,$00000000,$00000000
	dc.l	$00000000,$00000000,$00000000,$00000000
vbl_queue_entry:
	dc.l	vbl_deselect_drives
drives_deselected:	; from: vbl_deselect_drives, unlock_floppy
	dc.w	$0001

; Resource file name and alert strings
rsc_name:	; from: load_resource
	dc.b	'ACOPY.RSC',0
alert_no_rsc:	; from: main
	dc.b	'[3][The RSC-file is missing!][ OK ]',0
alert_sys_error:	; from: main
	dc.b	'[3][System error|Reset computer!][ OK ]',0
alert_resolution:	; from: main
	dc.b	'[1][You should use|MEDIUM or HIGH resolution!][Cancel|Continue]'
	dc.b	0
alert_insert_source:	; from: copy_disk_protected, copy_disk_normal
	dc.b	'[1][Insert SOURCE| in drive '
alert_insert_source_drv:	; from: read_settings
	dc.b	'A!][ OK |Cancel]',0
dat_4f27:
	dc.b	$0e
alert_insert_target:	; from: copy_disk_protected, copy_disk_normal
	dc.b	'[1][Insert TARGET| in drive B!][ OK |Cancel]',0
dat_4f55:
	dc.b	$00
alert_insert_both:
	dc.b	'[1][Insert SOURCE in drive A!|Insert TARGET in drive B!][ OK |Cancel]'
	dc.b	0
alert_target_mode:	; from: copy_disk_protected, copy_disk_normal
	dc.b	'[1][Insert TARGET in drive B!][Write|Read|Cancel]',0
alert_format:	; from: read_settings
	dc.b	'[1][Format disk|in drive A!][ OK |Cancel]',0
alert_insert_disk:
	dc.b	'[1][Insert disk|in drive A!][ OK |Cancel]',0
alert_cannot_normal:	; from: main_loop
	dc.b	'[3][I cannot copy this disk|in normal mode!][ OK ]',0
dat_5055:
	dc.b	$6e
alert_write_protect:
	dc.b	'[1][You should use WRITE PROTECT|on SOURCE disk!][ OK |Cancel]'
	dc.b	0
dat_5095:
	dc.b	$20
alert_checksum:
	dc.b	'[1][    CHECKSUM Error!     ][Retry|Cancel|Continue]',0
dat_50cb:
	dc.b	$7c
alert_lost_data:
	dc.b	'[1][    LOST DATA Error!    ][Retry|Cancel|Continue]',0
dat_5101:
	dc.b	$5b
alert_timeout:	; from: fdc_error_alert
	dc.b	'[1][     TIMEOUT Error!     ][Retry|Cancel|Continue]',0
dat_5137:
	dc.b	$70
alert_rnf:
	dc.b	'[1][ RECORD NOT FOUND Error!][Retry|Cancel|Continue]',0
dat_516d:
	dc.b	$65
alert_remove_wprot:
	dc.b	'[1][Remove WRITE PROTECT|on TARGET disk!][ OK |Cancel]',0
dat_51a5:
	dc.b	$48
alert_verify:
	dc.b	'[1][      VERIFY Error!     ][Retry|Cancel|Continue]',0
dat_51db:
	dc.b	$4f
alert_write:
	dc.b	'[1][      WRITE Error!      ][Retry|Cancel|Continue]',0
dat_5211:
	dc.b	$54
alert_fatal_read:
	dc.b	'[1][Fatal READ Error!][Retry|Cancel]',0
dat_5237:
	dc.b	$69

; AES and VDI parameter blocks
aes_pb:	; from: aes_trap
	dc.l	control
	dc.l	global
	dc.l	intin
	dc.l	intout
	dc.l	addrin
	dc.l	addrout
vdi_pb:	; from: vdi_trap
	dc.l	control
	dc.l	intin
	dc.l	ptsin
	dc.l	intout
	dc.l	ptsout

; Object/state pairs applied when only one drive is present
single_drive_states:	; from: main
	dc.b	$07,$08,$0a,$01,$0b,$08,$00,$6e

; Objects whose text address and screen position are cached in obj_text_table
text_objects:	; from: main
	dc.b	$31,$37,$3b,$3c,$00,$5d

; Radio button objects read into the settings bytes
radio_objects:	; from: read_settings
	dc.b	$07,$0b,$0e,$12,$16,$2c,$1b,$21,$22,$26,$00,$65
txt_reading:	; from: show_reading
	dc.b	' Reading ',0
txt_writing:	; from: show_writing
	dc.b	' Writing ',0
txt_formating:	; from: show_formatting
	dc.b	'Formating',0
txt_drive_letter:	; from: show_formatting
	dc.b	$20,$00
txt_side_digit:	; from: seek_and_show, show_side
	dc.b	$20,$00
txt_track_digits:	; from: seek_and_show, show_side
	dc.b	$20
txt_track_digit_lo:	; from: seek_and_show
	dc.b	$20,$00,$43

; Start/end track as set with the arrow buttons
start_track:	; from: copy_disk_protected, button_track_arrows
	dc.b	$00
end_track:	; from: init_disk_params
	dc.b	$51

; XOR checksums of the five resource strings (see verify_rsc_checksums)
rsc_checksums:	; from: verify_rsc_checksums
	dc.b	$c7,$01,$1e,$42,$3c,$42

; Sector length by size code
sector_sizes:	; from: sector_length
	dc.w	$0080,$0100,$0200,$0400

; Script opcode table, indexed by opcode byte / 4
opcode_table:	; from: script_dispatch
	dc.l	op_00_sync_mark_fill            ; opcode $00
	dc.l	op_04_fill_words                ; opcode $04
	dc.l	op_08_gap_literal               ; opcode $08
	dc.l	op_0c_write_special_sectors     ; opcode $0c
	dc.l	op_10_skip                      ; opcode $10
	dc.l	op_14_fill_e5                   ; opcode $14
	dc.l	op_18_data_field                ; opcode $18
	dc.l	op_1c_fix_mark_bytes            ; opcode $1c
	dc.l	op_20_id_field                  ; opcode $20
	dc.l	op_24_write_verify              ; opcode $24
	dc.l	op_28_gap                       ; opcode $28
	dc.l	op_2c_end                       ; opcode $2c
	dc.l	op_30_timed_sector_write        ; opcode $30
	dc.l	op_34_end_verify                ; opcode $34
	dc.l	op_38_gap_long                  ; opcode $38
	dc.l	op_3c_nop_skip                  ; opcode $3c
	dc.l	op_40_check_special_written     ; opcode $40
	dc.l	op_44_id_sector_ff              ; opcode $44
	dc.l	op_48_id_zero                   ; opcode $48
	dc.l	op_4c_verify_sectors            ; opcode $4c
	dc.l	op_50_id_ff_sector1             ; opcode $50
	dc.l	op_54_shifted_sector_write      ; opcode $54
	dc.l	op_58_fuzzy_marker              ; opcode $58
	dc.l	op_5c_long_track_prep           ; opcode $5c
	dc.l	op_60_long_track_write          ; opcode $60
	dc.l	op_64_rle_data                  ; opcode $64
	dc.l	op_68_id_current_track          ; opcode $68
	dc.l	op_6c_partial_write_track       ; opcode $6c
	dc.l	op_70_sync_read_track           ; opcode $70
	dc.l	op_74_fuzzy_marker_params       ; opcode $74

; Signature tables used by detect_signature_a/b
sig_table_a:	; from: detect_signature_a
	dc.b	$01,$03,$3e,$0f,$ff,$ff,$02,$06,$7c,$1f,$ff,$ff,$04,$0c,$f8,$3f
	dc.b	$ff,$ff,$08,$19,$f0,$7f,$ff,$ff,$10,$33,$e0,$ff,$ff,$ff,$20,$67
	dc.b	$c1,$ff,$ff,$ff,$40,$cf,$83,$ff,$ff,$ff,$80,$81,$9f,$07,$ff,$ff
	dc.b	$5e,$5c,$40,$b0,$00,$00,$bc,$b8,$81,$60,$00,$00,$97,$10,$2c,$00
	dc.b	$00,$00,$2f,$2e,$20,$58,$00,$00,$e5,$c4,$0b,$00,$00,$00,$cb,$88
	dc.b	$16,$00,$00,$00,$79,$71,$02,$c0,$00,$00,$f2,$e2,$05,$80,$00,$00
sig_table_b:	; from: detect_signature_b
	dc.b	$24,$01,$09,$09,$ff,$48,$02,$12,$12,$ff,$09,$00,$42,$42,$ff,$12
	dc.b	$00,$84,$84,$ff,$42,$40,$10,$90,$ff,$84,$80,$21,$21,$ff,$90,$04
	dc.b	$24,$24,$ff,$21,$20,$08,$48,$ff,$c9,$da,$72,$72,$00,$93,$b4,$e4
	dc.b	$e4,$00,$27,$69,$c9,$c9,$00,$4e,$d3,$93,$93,$00,$9c,$9d,$a7,$27
	dc.b	$00,$39,$3b,$4e,$4e,$00,$72,$76,$9c,$9c,$00,$e4,$ed,$39,$39,$00

	section	bss


; Variables
bpb_ptr:	ds.b	4	; from: get_bpb
buffer_start:	ds.b	4	; from: prg_init, main, read_source_bpb, init_copy_buffer, patch_fffb_check, patch_branches, ...
buffer_end:	ds.b	4	; from: copy_disk_normal
buffer_limit:	ds.b	4	; from: copy_disk_protected
buffer_ptr:	ds.b	4	; from: script_run_second, script_copy_raw_image, script_build_image, init_copy_buffer, copy_disk_protected, advance_script, ...
buffer_ptr_saved:	ds.b	4	; from: copy_disk_normal
saved_ssp:	ds.b	4	; from: prg_init
resolution:	ds.b	2	; from: main, gem_init
key_checked:	ds.b	1	; from: check_key_disk
crc_loaded:	ds.b	1	; from: load_crc_from_key_track
crc_code:	ds.b	1	; from: op_20_id_field, load_crc_from_key_track
crc_code_1:	ds.b	1	; from: build_track_image
rsc_strings:	ds.b	20	; from: main, verify_rsc_checksums
source_drive:	ds.b	1	; from: read_source_bpb, get_bpb, read_settings, init_disk_params, copy_disk_protected, copy_disk_normal
target_drive:	ds.b	1	; from: format_disk, copy_disk_protected, copy_disk_normal
verify_flag:	ds.b	1	; from: format_disk, fdc_wait_write_track, write_fuzzy_bits, emit_track_script, copy_disk_normal
multiple_flag:	ds.b	1	; from: copy_disk_protected, copy_disk_normal
format_flag:	ds.b	1	; from: copy_disk_normal
two_sides:	ds.b	1	; from: init_disk_params
prot_mode:	ds.b	1	; from: main_loop
ten_sectors:	ds.b	1	; from: build_format_track
eleven_sectors:	ds.b	1	; from: build_format_track
interleave_6:	ds.b	1	; from: build_format_track
same_drive:	ds.b	2	; from: read_settings, copy_disk_protected, copy_disk_normal

; Disk parameter block (BPB + private fields, see dp_* equates)
disk_params:	ds.b	24	; from: fill_bpb_dialog, read_source_bpb, load_base_regs, copy_disk_normal
cur_drive:	ds.b	3	; from: main
cur_side_b:	ds.b	5	; from: op_68_id_current_track, emit_sector_header
cur_track:	ds.b	1	; from: emit_track_script, patch_track3, emit_sector_header, patch_boot_scheme_a, patch_boot_scheme_b
cur_track_b:	ds.b	25	; from: op_68_id_current_track, script_add_sector, copy_raw_sector, detect_a1a1_scheme, rebuild_track79, patch_cmp_sequence, ...
first_mark_pos:	ds.b	4	; from: find_next_id
num_sectors:	ds.b	3	; from: read_ids_timed, copy_disk_protected, emit_track_script, emit_pregap_copy, detect_scheme_dup, detect_scheme_1b, ...
last_mark:	ds.b	1	; from: scan_track_sectors, copy_raw_sector, read_track_find_index
dma_pos:	ds.b	2	; from: script_add_sector, emit_script_scheme_dup, check_f0f7_sector, emit_track_script, emit_data_check_opcode, read_sector_timed, ...
dma_pos_w:	ds.b	2	; from: read_sector_timed
fuzzy_pos:	ds.b	4	; from: op_58_fuzzy_marker, write_track_from_script, write_fuzzy_bits
fuzzy_sector:	ds.b	4	; from: op_58_fuzzy_marker, write_fuzzy_bits
long_track_sector:	ds.b	4	; from: op_60_long_track_write, set_write_params_id, op_5c_long_track_prep
long_track_pos:	ds.b	4	; from: op_60_long_track_write, op_5c_long_track_prep
time_offset:	ds.b	2	; from: scan_track_sectors, find_next_id, copy_raw_sector
gap_end:	ds.b	2	; from: scan_track_sectors, find_next_id
first_id_pos:	ds.b	2	; from: scan_track_sectors, find_next_id
sector_list_end:	ds.b	4	; from: emit_track_script, emit_special_sector_script, emit_script_scheme_dup, emit_dup_sector_timing, detect_scheme_dup, read_track_sectors, ...
last_sector:	ds.b	5	; from: emit_script_scheme_c, emit_script_scheme_dup, emit_track_script, emit_inter_sector_gap, detect_scheme_dup, detect_scheme_1b, ...
drive_speed:	ds.b	1	; from: read_ids_timed, read_sector_timed, measure_drive_speed
f_data_over_index:	ds.b	2	; from: emit_track_script, choose_gap_size, scan_track_sectors
f_overlong_data:	ds.b	2	; from: emit_track_script, detect_scheme_dup, calc_sector_gaps
f_track_overflow:	ds.b	2	; from: emit_track_script, detect_scheme_dup, calc_sector_gaps, orphan_rts
leadin_special_pos:	ds.b	2	; from: emit_track_script, emit_leadin_gap, emit_leadin_or_gap, copy_raw_sector
sig_a1a1_pos:	ds.b	2	; from: emit_track_script, emit_script_a1a1, detect_a1a1_scheme
pregap_pos:	ds.b	2	; from: emit_track_script, emit_pregap_copy, emit_leadin_or_gap
f_scheme_0b09:	ds.b	2	; from: emit_track_script, emit_leadin_or_gap, copy_raw_sector
f_no_sync_fix:	ds.b	2	; from: fix_sync_bytes, copy_raw_sector
f_extra_id:	ds.b	2	; from: emit_track_script, detect_scheme_dup, read_all_sectors, calc_sector_gaps, orphan_rts
f_sig_table_a:	ds.b	2	; from: detect_signature_a, emit_track_script, detect_scheme_dup, calc_sector_gaps
f_scheme_c:	ds.b	2	; from: emit_track_script, detect_scheme_c
f_fuzzy_any:	ds.b	1	; from: detect_scheme_dup, read_all_sectors
f_weak_msb:	ds.b	1	; from: compare_sector_reads
f_dup_scheme:	ds.b	2	; from: copy_disk_protected, emit_dup_sector_timing, detect_scheme_dup, read_all_sectors
f_fuzzy_sector:	ds.b	2	; from: detect_scheme_dup, read_all_sectors, detect_fuzzy_sector
f_dup_scheme_alt:	ds.b	2	; from: emit_track_script, detect_scheme_dup
f_uniform_gap:	ds.b	2	; from: emit_track_script, emit_gap_after_id, emit_leadin_or_gap, detect_uniform_gap
f_scheme_1b:	ds.b	2	; from: emit_scheme_1b_data, emit_gap_after_id, detect_scheme_1b
f_unformatted:	ds.b	2	; from: patch_timing_loops, read_track_find_index, rtfi_timeout
f_ids_rotated:	ds.b	2	; from: emit_leadin_or_gap, scan_track_sectors, rotate_id_list
f_patched_boot_b:	ds.b	2	; from: patch_boot_scheme_b
f_patched_boot_a:	ds.b	2	; from: detect_a1a1_scheme, patch_boot_scheme_a
f_fix_id_bit4:	ds.b	2	; from: emit_track_script, script_add_sector, emit_gap_after_id, emit_sector_header, emit_leadin_or_gap, detect_uniform_gap, ...
special_count:	ds.b	1	; from: script_run_second, op_54_shifted_sector_write, write_track_until, op_44_id_sector_ff, op_40_check_special_written, op_0c_write_special_sectors, ...
special_count_1:	ds.b	1	; from: op_44_id_sector_ff, emit_special_sector_script
f_dup_ids:	ds.b	2	; from: emit_track_script, mark_special_sectors
fdc_track_reg:	ds.b	1	; from: fdc_set_track_reg
fdc_track_reg_1:	ds.b	1	; from: op_40_check_special_written
fdc_track_reg_w:	ds.b	1	; from: fdc_set_track_reg
fdc_track_reg_3:	ds.b	1	; from: op_40_check_special_written
script2_ptr:	ds.b	4	; from: op_0c_write_special_sectors, op_40_check_special_written, script_add_sector, emit_track_script
special_id_ptr:	ds.b	4	; from: op_40_check_special_written, verify_special_sectors, op_0c_write_special_sectors
dma_timeout:	ds.b	4	; from: sample_dma_address, read_track_find_index
fuzzy_retries:	ds.b	3	; from: write_fuzzy_bits
verify_retries:	ds.b	1	; from: op_24_write_verify
f_sync_in_data:	ds.b	1	; from: op_54_shifted_sector_write, op_0c_write_special_sectors, op_40_check_special_written, script_add_sector, emit_inter_sector_gap, emit_track_script
write_retries:	ds.b	1	; from: op_54_shifted_sector_write, op_0c_write_special_sectors, op_40_check_special_written
f_patch_fffb:	ds.b	2	; from: copy_disk_protected, patch_fffb_check, script_add_sector
read_retries:	ds.b	1	; from: copy_disk_protected, write_track_from_script
read_retries_1:	ds.b	1	; from: copy_disk_protected
delay_count:	ds.b	1	; from: op_60_long_track_write, timed_write_sector_at, timed_write_sector
delay_count_1:	ds.b	1	; from: op_60_long_track_write
gap_size:	ds.b	2	; from: emit_inter_sector_gap, emit_leadin_or_gap, choose_gap_size
f_id_ambiguous:	ds.b	2	; from: copy_disk_protected, scan_track_sectors, find_next_id
write_delay:	ds.b	2	; from: op_54_shifted_sector_write, op_0c_write_special_sectors, op_40_check_special_written, copy_disk_protected
id_count_ref:	ds.b	4	; from: op_0c_write_special_sectors, op_40_check_special_written
obj_text_table:	ds.b	16	; from: main, button_track_arrows
waiting_text:	ds.b	4	; from: show_waiting
waiting_xy:	ds.b	4	; from: show_status_text
drive_text:	ds.b	4
drive_label_xy:	ds.b	4	; from: main
sector_id_ptrs:	ds.b	44	; from: fill_sector_ids, build_track_image
drive_xy:	ds.b	4	; from: main, show_formatting
side_xy:	ds.b	4	; from: show_side
track_xy:	ds.b	4	; from: show_side
vdi_handle:	ds.b	4	; from: vdi_call, gem_init
tree_main:	ds.b	4	; from: main
tree_about:	ds.b	4	; from: main, main_loop
tree_blank:	ds.b	4	; from: redraw_main_dialog
tree_bpb:	ds.b	4	; from: main_loop
char_w:	ds.b	2	; from: main, gem_init
char_h_adj:	ds.b	2	; from: main, object_screen_pos
desk_xy:	ds.b	4	; from: set_intin_clip, get_desktop_area
desk_wh:	ds.b	4	; from: set_intin_clip, get_desktop_area
dlg_xy:	ds.b	4	; from: center_dialog
dlg_wh:	ds.b	4	; from: center_dialog
control:	ds.b	12	; from: set_control, aes_pb, vdi_pb
contrl_handle:	ds.b	10	; from: vdi_call, gem_init
global:	ds.b	30	; from: aes_pb
intin:	ds.b	2	; from: alert, object_screen_pos, set_intin_clip, do_dialog, mouse_busy, draw_text, ...
intin_1:	ds.b	254	; from: get_tree, get_desktop_area
ptsin:	ds.b	512	; from: draw_text, vdi_pb
intout:	ds.b	2	; from: main, alert, do_dialog, get_tree, gem_init, aes_pb, ...
intout_1:	ds.b	2	; from: object_screen_pos, center_dialog, get_desktop_area
intout_2:	ds.b	2	; from: center_dialog
intout_3:	ds.b	250	; from: get_mouse_button
ptsout:	ds.b	24	; from: vdi_pb
addrin:	ds.b	256	; from: alert, object_screen_pos, unselect_button_nodraw, do_dialog, draw_tree, center_dialog, ...
addrout:	ds.b	254	; from: get_tree, aes_pb
track_buf_m2:	ds.b	2	; from: detect_a1a1_scheme

; Track image / raw track buffer
track_buf:	ds.b	1	; from: script_copy_raw_image, script_build_image, op_58_fuzzy_marker, dma_set_track_buf, op_60_long_track_write, read_track_check_sig, ...
track_buf_1:	ds.b	1	; from: emit_raw_track_script
track_buf_2:	ds.b	1	; from: op_6c_partial_write_track, detect_signature_a
track_buf_3:	ds.b	1	; from: emit_leadin_gap, copy_raw_sector
track_buf_4:	ds.b	4	; from: emit_leadin_gap
track_buf_8:	ds.b	2	; from: op_54_shifted_sector_write
track_buf_a:	ds.b	6	; from: emit_track_script
track_buf_10:	ds.b	80	; from: measure_drive_speed
track_buf_60:	ds.b	34	; from: op_6c_partial_write_track, copy_raw_sector, detect_a1a1_scheme
track_buf_82:	ds.b	558	; from: op_6c_partial_write_track
track_buf_2b0:	ds.b	3408	; from: copy_raw_sector
track_buf_1000:	ds.b	1888	; from: load_crc_from_key_track, rebuild_track79
track_buf_1760:	ds.b	96	; from: rtfi_timeout
track_buf_17c0:	ds.b	256	; from: fdc_wait_write_track
shift_sector_buf:	ds.b	19	; from: op_0c_write_special_sectors
shift_sector_data:	ds.b	45	; from: op_0c_write_special_sectors
track_buf_1900:	ds.b	256	; from: read_track_find_index
sector_buf:	ds.b	8	; from: op_70_sync_read_track, op_60_long_track_write, set_write_params_data, op_54_shifted_sector_write, op_4c_verify_sectors, op_40_check_special_written, ...
sector_buf_8:	ds.b	4	; from: patch_cmp_sequence
sector_buf_c:	ds.b	500	; from: patch_cmp_sequence
sector_buf_200:	ds.b	512	; from: op_54_shifted_sector_write
id_fields:	ds.b	256	; from: op_60_long_track_write, set_write_params_id, op_54_shifted_sector_write, write_track_until, op_50_id_ff_sector1, op_44_id_sector_ff, ...
shift_buf2:	ds.b	1280	; from: op_54_shifted_sector_write
verify_buf:	ds.b	512	; from: copy_disk_normal, prepare_sector_fill
special_ids:	ds.b	1024	; from: verify_special_sectors, op_0c_write_special_sectors
read_buf2:	ds.b	1024	; from: write_fuzzy_bits, op_24_write_verify
read_buf3:	ds.b	1024	; from: write_fuzzy_bits, op_24_write_verify

; Sector list (18-byte entries) / sector usage map in normal mode
sector_list:	ds.b	2	; from: read_ids_short, read_source_bpb, read_ids_after_index, format_disk, wait_dma_start, emit_track_script, ...
sector_list_2:	ds.b	8	; from: scan_track_sectors
sector_list_a:	ds.b	2	; from: scan_track_sectors
sector_list_c:	ds.b	16	; from: scan_track_sectors
sector_list_1c:	ds.b	2	; from: scan_track_sectors
sector_list_1e:	ds.b	226	; from: scan_track_sectors
sector_list_100:	ds.b	5552	; from: verify_special_sectors
bss_end:

	end
