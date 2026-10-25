; Batman The Movie (Ocean, 1989) - game loader (runs at $1000), all versions
; Module loader: loader.bin, loaded at $1000, in scenes loader.
; Size: RETAIL_2DISK 4026 bytes, RETAIL_1DISK 4020 bytes, BUDGET_1DISK 4020 bytes.
;
; Disassembled by Darren Birks in the evil month of October 2026.
;
; loadstub copies the loader to $1000 and enters it at loader_start.  The six entry
; vectors at $1000 (also reached through the jmp table at $200, jmp $1000 + 4n) are how
; the level modules leave a level: 0 the front end after a level (game over / well
; done), 1..5 level 1..5.  Each loader section loads the files of a scene, shows its
; picture and jumps to it.
;
; How each version reads its files:
;
; RETAIL_2DISK, the 2 disk retail release (the original): retail_2disk_speedlock\
; loader.bin from $46 on, track 0 sectors 2-9 of disk 1 after the SpeedLock decryption.
; Files are not packed.  Each starts at the beginning of a track ($1800 data bytes,
; escaped: $0f, x means ~x) and is read straight to its load address; every track ends
; in a checksum word that load_file checks.  The disk number is the first serial
; number byte of the disk's boot sector (1 or 2), found by Read Track on track 0; each
; section waits for its disk and shows INSERT OTHER DISC until it is in.  Pictures are
; run length packed and decoded by load_picture to $78000.  From $1c22 to the end the
; sectors hold leftover code of the tool that wrote the game tracks; the loader never
; runs it (see tool_start).
;
; RETAIL_1DISK, the 1 disk retail reissue: retail_1disk_speedlock\loader.bin (the stub
; at $21000 and this code).  Files run on from one track to the next, are read to
; "dest", unpacked with the FORM HUFF decoder to "load"; the checksum word is read but
; not checked.
;
; Game tracks of both retail versions: no sectors, written with Write Track.  Read back
; with Read Track a track is
;
;   gap ($ff ... f0)  c2 a1 a1  0f <track>  0f  <$1800 data bytes>  <checksum>  00  4e ...
;
; The sync is written as f5 f5 f5 and reads back as c2 a1 a1; the track number is the
; physical track, checked by the loader.  The data bytes are escaped, $0f, x meaning
; ~x, so $f5-$f7 (which Write Track turns into syncs or CRCs) and $0f never appear in
; the data.  With no sectors on them, a sector copier sees nothing on these tracks.
;
; BUDGET_1DISK, the 1 disk budget release (The Hit Squad): budget_1disk\loader.bin,
; the reissue's loader copied to $21000 by boot stage 3 (budget_1disk\boot) with four
; patches: load_file calls the sector loader that stage 3 puts at $6f950,
; unpack_file and drive_deselect return at once, show_picture takes the picture's
; address from d4.  The files are Pack-Ice packed and unpacked by the sector loader;
; the disk is 10 sectors a track with no protection, side 0 only.
;
; Load tables (load_table):
;
; RETAIL_2DISK: 16 bytes per file: track, length on disk, length to decrypt,
; destination; a picture's destination field holds its length again.  The files are
; in retail_2disk_speedlock\disk1 and disk2, except level24.bin and level4.gfx, the
; same as the reissue's, in retail_1disk_speedlock\unpacked.
;
; file  disk  tracks  length  decrypt  dest     name          contents
; ----  ----  ------  ------  -------  ------   ------------  --------
;  0     1     2- 3   $02000  $01e80   $75efc  panel.gfx     panel bitmap (resident)
;  1     1     4- 5   $01a00  $01880   $6b7fc  panel.bin     panel / score code (resident)
;  2     1     6- 7   $02700  $02580   $6d3e4  sound.prg     sound driver PRG (resident)
;  3     1     8- 9   $02600  $02400   $1fffc  frontend.bin  front end code
;  4     1    10-17   $0af00  $0a900   $3f236  frontend.gfx  front end pictures and big font
;  5     1    18-20   $04300  $04046   -       level1.pic    level 1 picture
;  6     1    21-24   $05600  $05280   $21fc   level1.bin    level 1 code
;  7     1    25-39   $15600  $14a80   $4fffc  level1.gfx    level 1 graphics ($50000 on, one file for the reissue's two)
;  8     1    40-45   $08400  $07f80   $73fc   level1.map    level 1 map
;  9     2     1- 3   $04300  $0403d   -       level2.pic    level 2 picture
; 10     2     4- 9   $08900  $08400   $21fc   level24.bin   level 2/4 code
; 11     2    10-13   $04c00  $04880   $bbfc   level24.gfx   level 2/4 graphics
; 12     2    14-36   $21400  $20280   $10434  level2.gfx    level 2 graphics
; 13     2    37-39   $03d00  $03a26   -       level3.pic    level 3 picture
; 14     2    40-49   $0dd00  $0d580   $1fffc  level3.bin    level 3
; 15     2    50-52   $03b00  $038cd   -       level4.pic    level 4 picture
; 16     2     4- 9   $08900  $08400   $21fc   level24.bin   level 2/4 code (as for level 2)
; 17     2    10-13   $04c00  $04880   $bbfc   level24.gfx   level 2/4 graphics (as for level 2)
; 18     2    53-79   $28600  $27080   $10434  level4.gfx    level 4 graphics
; 19     1    46-49   $04a00  $0474f   -       level5.pic    level 5 picture
; 20     1    50-53   $05700  $05400   $21fc   level5.bin    level 5 code
; 21     1    54-68   $15b00  $15000   $4fffc  level5.gfx    level 5 graphics ($50000 on, one file for the reissue's two)
; 22     1    69-74   $08500  $08000   $73fc   level5.map    level 5 map
;
; RETAIL_1DISK: 20 bytes per file.  "tracks" is where the packed file lies on the disk
; ($1800 data bytes per track) and "offset" where it starts in its first track;
; "dest" is where the packed file is read to and "load" where it is unpacked to.  The
; files are in retail_1disk_speedlock\packed (as on disk) and unpacked.
;
; file  tracks  offset  length  dest     load    name          contents
; ----  ------  ------  ------  ------   ------  ------------  --------
;  0     2- 5   $0000   $04a83  $3f23a   -       title.pic     title picture
;  1     5- 6   $0284   $017cc  $75efc   $75f00  panel.gfx     panel bitmap (resident)
;  2     6- 7   $0252   $01634  $6b7fc   $6b800  panel.bin     panel / score code (resident)
;  3     7- 8   $0088   $02299  $6d3e4   $6d3e4  sound.prg     sound driver PRG (resident)
;  4     8- 9   $0b22   $01cb6  $1fffc   $20000  frontend.bin  front end code
;  5     9-15   $0fe2   $08262  $3f236   $3f23a  frontend.gfx  front end pictures and big font
;  6    15-16   $0246   $01868  $78000   -       level1.pic    level 1 loading picture
;  7    16-19   $02b0   $04671  $021fc   $2200   level1.bin    level 1 code (platform engine)
;  8    19-23   $0122   $074a1  $4fffc   $50000  level1a.gfx   level 1 graphics
;  9    23-25   $15c4   $01d7a  $5fffc   $60000  level1b.gfx   level 1 graphics
; 10    25-27   $0340   $04128  $073fc   $7400   level1.map    level 1 map
; 11    27-29   $146a   $022df  $78000   -       level2.pic    level 2 loading picture
; 12    29-33   $074a   $0633a  $021fc   $2200   level24.bin   level 2/4 code (driving engine)
; 13    33-35   $0a86   $02ab0  $0bbfc   $bc00   level24.gfx   level 2/4 graphics
; 14    35-46   $0538   $103ad  $10434   $10438  level2.gfx    level 2 graphics
; 15    46-47   $00e6   $0299b  $78000   -       level3.pic    level 3 loading picture
; 16    47-51   $1282   $0613d  $1fffc   $20000  level3.bin    level 3 picture and code
; 17    51-53   $13c0   $025a7  $78000   -       level4.pic    level 4 loading picture
; 18    29-33   $074a   $0633a  $021fc   $2200   level24.bin   level 2/4 code (same file as 12)
; 19    33-35   $0a86   $02ab0  $0bbfc   $bc00   level24.gfx   level 2/4 graphics (same file as 13)
; 20    53-65   $0968   $122b7  $10434   $10438  level4.gfx    level 4 graphics
; 21    65-67   $0c20   $0281c  $78000   -       level5.pic    level 5 loading picture
; 22    67-70   $043e   $04a36  $021fc   $2200   level5.bin    level 5 code (platform engine)
; 23    70-74   $0676   $0690b  $4fffc   $50000  level5a.gfx   level 5 graphics
; 24    74-75   $0f82   $01d29  $5fffc   $60000  level5b.gfx   level 5 graphics
; 25    75-79   $14ac   $05e7e  $073fc   $7400   level5.map    level 5 map
;
; BUDGET_1DISK: the reissue's 20 byte entries; d1 is the first sector, counted on
; side 0 as track x 10 + sector - 1, d2 the number of sectors, both read as words (the
; high words are 0); d0 and d3 keep the reissue's values and are not used.  The files are
; in budget_1disk\packed and unpacked.
;
; file  sectors   track/sector  sectors  dest     name          (budget_1disk\packed)
; ----  -------   ------------  -------  ------   ------------
;  0     10- 46    1/1            37    $3f23a   title.pic
;  1     47- 55    4/8             9    $75efc   panel.gfx
;  2     56- 63    5/7             8    $6b7fc   panel.bin
;  3     64- 74    6/5            11    $6d3e4   sound.prg
;  4     75- 83    7/6             9    $1fffc   frontend.bin
;  5     84-137    8/5            54    $3f236   frontend.gfx
;  6    138-147   13/9            10    $78000   level1.pic
;  7    148-171   14/9            24    $021fc   level1.bin
;  8    172-218   17/3            47    $4fffc   level1a.gfx
;  9    219-231   21/10           13    $5fffc   level1b.gfx
; 10    232-251   23/3            20    $073fc   level1.map
; 11    252-267   25/3            16    $78000   level2.pic
; 12    268-299   26/9            32    $021fc   level24.bin
; 13    300-312   30/1            13    $0bbfc   level24.gfx
; 14    313-424   31/4           112    $10434   level2.gfx
; 15    425-441   42/6            17    $78000   level3.pic
; 16    442-473   44/3            32    $1fffc   level3.bin
; 17    474-489   47/5            16    $78000   level4.pic
; 18    490-521   49/1            32    $021fc   lev24_l4.bin
; 19    522-534   52/3            13    $0bbfc   lev24_l4.gfx
; 20    535-656   53/6           122    $10434   level4.gfx
; 21    657-674   65/8            18    $78000   level5.pic
; 22    675-699   67/6            25    $021fc   level5.bin
; 23    700-743   70/1            44    $4fffc   level5a.gfx
; 24    744-756   74/5            13    $5fffc   level5b.gfx
; 25    757-783   75/8            27    $073fc   level5.map
;
; Memory maps of the three versions.  Resident parts are in memory in every scene; a
; scene is what one loader section leaves in memory.  "free" = nothing known to use it.
;
; ----------------------------------------------------------------------
;
; Memory map of RETAIL_2DISK, the 2 disk retail release (the original), on a 512 K ST (levels 2 and 4 also with 1 MB).
;
;   resident (every scene)
;   000000-0007ff  exception vectors: $70 VBL, $100-$13c MFP (timer A $134), $200-$21b loader jmp table, $43e flock
;   001000-001fb9  loader (loader.s), zero padding from $1904, leftover code of the track writing tool from $1c22
;   06b800-06d07b  panel.bin (panel / score routines (resident))
;   06d400-06fd25  sound.prg (sound driver (resident PRG))
;   070000-077fff  screen 1 of the levels; loader track read buffer (disc number from $70020); $75f00 panel bitmap (panel.gfx) in its bottom 48 lines
;   075f00-077d7b  panel.gfx (panel bitmap (resident))
;   078000-07ffff  screen 2 of the levels; loader picture buffer (a picture is read to end at $7fd00 and decoded to $78000); $7df00 panel copy in its bottom 48 lines
;   Each file is read straight to its load address as long as its decrypt length in the
;   load table, which can run on past the data of the file.
;
;   front
;   010000-017fff  front end screen (stack top $10000, grows down)
;   018000-01ffff  picture decode buffer
;   020000-0223fb  frontend.bin (front end)
;   03f23a-049b35  frontend.gfx (front end pictures and big font)
;   free: $1fba-$ffff, $223fc-$3f239, $49b36-$6b7ff
;
;   level1
;   002200-00747b  level1.bin (level 1 code)
;   007400-00f37b  level1.map (level 1 map)
;   007400-007405  map header: tile count, row length ($cc), rows (42)
;   007406-00957d  map: a byte per 8 x 8 pixel tile
;   00957e-00977d  tile table, a word per tile (build_tile_order, tile_cache_free)
;   00977e-00987d  tile reference counts
;   00987e-00997d  cache slot of each tile
;   00997e-00c27d  tile graphics the cache is filled from
;   00c27e-02427d  tile graphics cache: 96 slots of $400 bytes, 8 shifted copies of a tile
;   02427e-025395  sprite headers (pack_sprites at level start)
;   02547e-047fff  packed sprites (pack_sprites at level start; draw_sprite adds their offsets to $23382)
;   048800-06afff  pre-shifted sprites (build_sprite_tables at level start), over level1.gfx
;   050000-064a7b  level1.gfx (level 1 graphics)
;   06d3e8          stack top, grows down below the sound driver
;   free: none
;   level1.map is loaded over the tail of level1.bin from $7400.
;
;   level2
;   002200-00a5fb  level24.bin (level 2/4 code)
;   00bc00-01047b  level24.gfx (level 2/4 graphics)
;   010438-0306b3  level2.gfx (level 2 graphics)
;   030690-03acdb  shifted sprite sets of gfx_list_common (unpack_gfx at level start)
;   03acdc-06af9f  shifted sprite sets of gfx_list_level2_512k (512K only)
;   070000          stack top, grows down
;   free: $a5fc-$bbff
;   with 1 MB (detect_1mb finds memory at $88888):
;   080000-0de79f  shifted sprite sets of gfx_list_level2_1mb
;   free: $a5fc-$bbff, $3acdc-$6b7ff, $de7a0-$fffff
;
;   level3
;   020000-02d57b  level3.bin (level 3)
;   063800-06b4ff  Batcave picture, unpacked at level start (stack top $63800, grows down)
;   free: $1fba-$1ffff, $2d57c-$637ff
;
;   level4
;   002200-00a5fb  level24.bin (level 2/4 code)
;   00bc00-01047b  level24.gfx (level 2/4 graphics)
;   010438-0374b3  level4.gfx (level 4 graphics)
;   037448-041a93  shifted sprite sets of gfx_list_common (unpack_gfx at level start)
;   041a94-06b769  shifted sprite sets of gfx_list_level4_512k (512K only)
;   070000          stack top, grows down
;   free: $a5fc-$bbff
;   with 1 MB (detect_1mb finds memory at $88888):
;   080000-0e9491  shifted sprite sets of gfx_list_level4_1mb
;   free: $a5fc-$bbff, $41a94-$6b7ff, $e9492-$fffff
;
;   level5
;   002200-0075fb  level5.bin (level 5 code)
;   007400-00f3fb  level5.map (level 5 map)
;   007400-007405  map header: tile count, row length ($5c), rows (204)
;   007406-00bd55  map: a byte per 8 x 8 pixel tile
;   00bd56-00bf55  tile table, a word per tile (build_tile_order, tile_cache_free)
;   00bf56-00c055  tile reference counts
;   00c056-00c155  cache slot of each tile
;   00c156-00f355  tile graphics the cache is filled from
;   00f356-021355  tile graphics cache: 72 slots of $400 bytes, 8 shifted copies of a tile
;   021356-022405  sprite headers (pack_sprites at level start)
;   022556-045497  packed sprites (pack_sprites at level start; draw_sprite adds their offsets to $23eaa)
;   046400-06933b  pre-shifted sprites (build_sprite_tables at level start), over level5.gfx
;   050000-064ffb  level5.gfx (level 5 graphics)
;   06d3e0          stack top, grows down below the sound driver
;   free: $6933c-$6b7ff
;   level5.map is loaded over the tail of level5.bin from $7400.
;
; ----------------------------------------------------------------------
;
; Memory map of RETAIL_1DISK, the 1 disk retail reissue, on a 512 K ST (levels 2 and 4 also with 1 MB).
;
;   resident (every scene)
;   000000-0007ff  exception vectors: $70 VBL, $100-$13c MFP (timer A $134), $200-$21b loader jmp table, $43e flock
;   001000-001fff  loader (loader.s), zero padding from $1d14
;   06b800-06d000  panel.bin (panel / score routines (resident))
;   06d400-06fd25  sound.prg (sound driver (resident PRG))
;   070000-077fff  screen 1 of the levels; loader track read buffer and picture copy; $75f00 panel bitmap (panel.gfx) in its bottom 48 lines
;   075f00-077d00  panel.gfx (panel bitmap (resident))
;   078000-07ffff  screen 2 of the levels; loader picture buffer; $7df00 panel copy in its bottom 48 lines
;
;   front
;   010000-017fff  front end screen (stack top $10000, grows down)
;   018000-01ffff  picture decode buffer
;   020000-022166  frontend.bin (front end)
;   03f23a-049aec  frontend.gfx (front end pictures and big font)
;   free: $2000-$ffff, $22167-$3f239, $49aed-$6b7ff
;
;   level1
;   002200-007074  level1.bin (level 1 code)
;   007400-00c27e  level1.map (level 1 map)
;   007400-007405  map header: tile count, row length ($cc), rows (42)
;   007406-00957d  map: a byte per 8 x 8 pixel tile
;   00957e-00977d  tile table, a word per tile (build_tile_order, tile_cache_free)
;   00977e-00987d  tile reference counts
;   00987e-00997d  cache slot of each tile
;   00997e-00c27d  tile graphics the cache is filled from
;   00c27e-02427d  tile graphics cache: 96 slots of $400 bytes, 8 shifted copies of a tile
;   02427e-025395  sprite headers (pack_sprites at level start)
;   02547e-047fff  packed sprites (pack_sprites at level start; draw_sprite adds their offsets to $23382)
;   048800-06afff  pre-shifted sprites (build_sprite_tables at level start), over level1a.gfx and level1b.gfx
;   050000-05ccfc  level1a.gfx (level 1 graphics)
;   060000-063ca4  level1b.gfx (level 1 graphics)
;   06d3e8          stack top, grows down below the sound driver
;   free: none
;
;   level2
;   002200-00a5fb  level24.bin (level 2/4 code)
;   00bc00-01047b  level24.gfx (level 2/4 graphics)
;   010438-0306b3  level2.gfx (level 2 graphics)
;   030690-03acdb  shifted sprite sets of gfx_list_common (unpack_gfx at level start)
;   03acdc-06af9f  shifted sprite sets of gfx_list_level2_512k (512K only)
;   070000          stack top, grows down
;   free: $a5fc-$bbff
;   with 1 MB (detect_1mb finds memory at $88888):
;   080000-0de79f  shifted sprite sets of gfx_list_level2_1mb
;   free: $a5fc-$bbff, $3acdc-$6b7ff, $de7a0-$fffff
;
;   level3
;   020000-02d56a  level3.bin (level 3)
;   063800-06b4ff  Batcave picture, unpacked at level start (stack top $63800, grows down)
;   free: $2000-$1ffff, $2d56b-$637ff
;
;   level4
;   002200-00a5fb  level24.bin (level 2/4 code)
;   00bc00-01047b  level24.gfx (level 2/4 graphics)
;   010438-0374b3  level4.gfx (level 4 graphics)
;   037448-041a93  shifted sprite sets of gfx_list_common (unpack_gfx at level start)
;   041a94-06b769  shifted sprite sets of gfx_list_level4_512k (512K only)
;   070000          stack top, grows down
;   free: $a5fc-$bbff
;   with 1 MB (detect_1mb finds memory at $88888):
;   080000-0e9491  shifted sprite sets of gfx_list_level4_1mb
;   free: $a5fc-$bbff, $41a94-$6b7ff, $e9492-$fffff
;
;   level5
;   002200-0075fb  level5.bin (level 5 code)
;   007400-00f356  level5.map (level 5 map)
;   007400-007405  map header: tile count, row length ($5c), rows (204)
;   007406-00bd55  map: a byte per 8 x 8 pixel tile
;   00bd56-00bf55  tile table, a word per tile (build_tile_order, tile_cache_free)
;   00bf56-00c055  tile reference counts
;   00c056-00c155  cache slot of each tile
;   00c156-00f355  tile graphics the cache is filled from
;   00f356-021355  tile graphics cache: 72 slots of $400 bytes, 8 shifted copies of a tile
;   021356-022405  sprite headers (pack_sprites at level start)
;   022556-0454c3  packed sprites (pack_sprites at level start; draw_sprite adds their offsets to $23eaa)
;   046400-069367  pre-shifted sprites (build_sprite_tables at level start), over level5a.gfx and level5b.gfx
;   050000-05cce4  level5a.gfx (level 5 graphics)
;   060000-063fb8  level5b.gfx (level 5 graphics)
;   06d3e8          stack top, grows down below the sound driver
;   free: $69368-$6b7ff
;   level5.map is loaded over the tail of level5.bin from $7400.
;
; ----------------------------------------------------------------------
;
; Memory map of BUDGET_1DISK, the 1 disk budget release, on a 512 K ST (levels 2 and 4 also with 1 MB).
;
;   resident (every scene)
;   000000-0007ff  exception vectors: $70 VBL, $100-$13c MFP (timer A $134), $200-$21b loader jmp table, $43e flock
;   000300-00031f  reset handler in unused vectors (stage3.s reset_trap): clears the system variables, cold boots
;   001000-001fff  loader (loader.s); from $18f1 it comes from past the end of stage 3, what the boot sector read
;   06b800-06d01f  panel.bin (panel / score routines (resident))
;   06d400-06fd25  sound.prg (sound driver (resident PRG))
;   06f950-06fe5f  sector loader and Pack-Ice depacker (stage3.s sector_load), called by load_file
;   06fe60-06fe9b  Pack-Ice tables
;   06fe9c-06ff13  Pack-Ice save buffer: the 120 bytes after a file while it is unpacked
;   06ff14-06ff1b  current track of each drive (track_table)
;   070000-077fff  screen 1 of the levels; loader picture copy; $75f00 panel bitmap (panel.gfx) in its bottom 48 lines
;   075f00-077d1f  panel.gfx (panel bitmap (resident))
;   078000-07ffff  screen 2 of the levels; loader picture buffer; $7df00 panel copy in its bottom 48 lines
;   A file is read to its load table destination and unpacked there; the depacker keeps
;   the 120 bytes after the unpacked file in its save buffer and puts them back.
;   The sector loader lies in the BSS of sound.prg ($6f926-$6fd25), the sample table
;   snd_sample_start reads; no tune or sound effect uses pattern command $8d, so nothing
;   fills it.  In levels 2 and 4 the stack grows down from $70000 towards it: more than
;   228 bytes reach the track table, more than 356 the Pack-Ice tables (not measured).
;   At boot only: the boot sector and stage 2 at $fe00-$127ff, the stage 2 depacker
;   at $60000-$60d07, stage 3 at $10000-$10ff6.
;
;   front
;   010000-017fff  front end screen (stack top $10000, grows down)
;   018000-01ffff  picture decode buffer
;   020000-022185  frontend.bin (front end)
;   03f23a-049b0b  frontend.gfx (front end pictures and big font)
;   free: $2000-$ffff, $22186-$3f239, $49b0c-$6b7ff
;
;   level1
;   002200-007093  level1.bin (level 1 code)
;   007400-00c29d  level1.map (level 1 map)
;   007400-007405  map header: tile count, row length ($cc), rows (42)
;   007406-00957d  map: a byte per 8 x 8 pixel tile
;   00957e-00977d  tile table, a word per tile (build_tile_order, tile_cache_free)
;   00977e-00987d  tile reference counts
;   00987e-00997d  cache slot of each tile
;   00997e-00c27d  tile graphics the cache is filled from
;   00c27e-02427d  tile graphics cache: 96 slots of $400 bytes, 8 shifted copies of a tile
;   02427e-025395  sprite headers (pack_sprites at level start)
;   02547e-047fff  packed sprites (pack_sprites at level start; draw_sprite adds their offsets to $23382)
;   048800-06afff  pre-shifted sprites (build_sprite_tables at level start), over level1a.gfx and level1b.gfx
;   050000-05cd1b  level1a.gfx (level 1 graphics)
;   060000-063cc3  level1b.gfx (level 1 graphics)
;   06d3e8          stack top, grows down below the sound driver
;   free: none
;
;   level2
;   002200-00a61d  level24.bin (level 2/4 code)
;   00bc00-01049a  level24.gfx (level 2/4 graphics)
;   010438-0306d2  level2.gfx (level 2 graphics)
;   030690-03acdb  shifted sprite sets of gfx_list_common (unpack_gfx at level start)
;   03acdc-06af9f  shifted sprite sets of gfx_list_level2_512k (512K only)
;   070000          stack top, grows down
;   free: $a61e-$bbff
;   The stack top $70000 is right above the sector loader.
;   with 1 MB (detect_1mb finds memory at $88888):
;   080000-0de79f  shifted sprite sets of gfx_list_level2_1mb
;   free: $a61e-$bbff, $3acdc-$6b7ff, $de7a0-$fffff
;
;   level3
;   020000-02d589  level3.bin (level 3)
;   063800-06b4ff  Batcave picture, unpacked at level start (stack top $63800, grows down)
;   free: $2000-$1ffff, $2d58a-$637ff
;
;   level4
;   002200-00a61d  level24.bin (level 2/4 code)
;   00bc00-01049a  level24.gfx (level 2/4 graphics)
;   010438-0374d2  level4.gfx (level 4 graphics)
;   037448-041a93  shifted sprite sets of gfx_list_common (unpack_gfx at level start)
;   041a94-06b769  shifted sprite sets of gfx_list_level4_512k (512K only)
;   070000          stack top, grows down
;   free: $a61e-$bbff
;   The stack top $70000 is right above the sector loader.
;   with 1 MB (detect_1mb finds memory at $88888):
;   080000-0e9491  shifted sprite sets of gfx_list_level4_1mb
;   free: $a61e-$bbff, $41a94-$6b7ff, $e9492-$fffff
;
;   level5
;   002200-00761a  level5.bin (level 5 code)
;   007400-00f375  level5.map (level 5 map)
;   007400-007405  map header: tile count, row length ($5c), rows (204)
;   007406-00bd55  map: a byte per 8 x 8 pixel tile
;   00bd56-00bf55  tile table, a word per tile (build_tile_order, tile_cache_free)
;   00bf56-00c055  tile reference counts
;   00c056-00c155  cache slot of each tile
;   00c156-00f355  tile graphics the cache is filled from
;   00f356-021355  tile graphics cache: 72 slots of $400 bytes, 8 shifted copies of a tile
;   021356-022405  sprite headers (pack_sprites at level start)
;   022556-0454c3  packed sprites (pack_sprites at level start; draw_sprite adds their offsets to $23eaa)
;   046400-069367  pre-shifted sprites (build_sprite_tables at level start), over level5a.gfx and level5b.gfx
;   050000-05cd03  level5a.gfx (level 5 graphics)
;   060000-063fd7  level5b.gfx (level 5 graphics)
;   06d3e8          stack top, grows down below the sound driver
;   free: $69368-$6b7ff
;   level5.map is loaded over the tail of level5.bin from $7400.
;
; Labels are named for what they do or hold; unused_ marks code that nothing
; calls.  A label still ending in its address (tab_ table, dat_ data) is one
; whose use is not known yet.  "; from:" lists the routines or modules that
; refer to a label (documentation only).

	include	"config.s"			; CONFIG: which version to assemble

	opt	o-
	org	$1000

loader_vectors:	; from: loadstub
	bra.w	after_level

vector_level1:
	bra.w	start_level1

vector_level2:
	bra.w	start_level2

vector_level3:
	bra.w	start_level3

vector_level4:
	bra.w	start_level4

vector_level5:
	bra.w	start_level5


;----------------------------------------------------------------------
; Boot entry: load the resident modules and the front end (frontend.bin/.gfx) and jump to $20000.
;----------------------------------------------------------------------
loader_start:	; from: loadstub
	lea	$10000,sp
	bsr.w	blank_screen
	movem.l	load_table(pc),d0-d4
	bsr.w	load_file
	ifne	CONFIG-RETAIL_2DISK
	bsr.w	show_picture
	movem.l	file_panel_gfx(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	endc
	movem.l	file_panel_bin(pc),d0-d4
	bsr.w	load_file
	ifne	CONFIG-RETAIL_2DISK
	bsr.w	unpack_file
	endc
	movem.l	file_sound_prg(pc),d0-d4
	bsr.w	load_file
	ifne	CONFIG-RETAIL_2DISK
	bsr.w	unpack_file
	endc
	movem.l	file_frontend_bin(pc),d0-d4
	bsr.w	load_file
	ifne	CONFIG-RETAIL_2DISK
	bsr.w	unpack_file
	endc
	movem.l	file_frontend_gfx(pc),d0-d4
	bsr.w	load_file
	ifne	CONFIG-RETAIL_2DISK
	bsr.w	unpack_file
	endc
	bsr.w	drive_deselect
	jmp	$20000


;----------------------------------------------------------------------
; Return from a level: reload the front end and jump to $20004.
;----------------------------------------------------------------------
after_level:	; from: loader_vectors
	bsr.w	blank_screen
	ifeq	CONFIG-RETAIL_2DISK
after_level_disc:
	bsr.w	read_disc_number
	cmpi.b	#$1,d0                          ; disc 1?
	beq.s	after_level_load
	bsr.w	insert_other_disc
	bra.s	after_level_disc

after_level_load:
	bsr.w	blank_screen
	endc
	movem.l	file_frontend_bin(pc),d0-d4
	bsr.w	load_file
	ifne	CONFIG-RETAIL_2DISK
	bsr.w	unpack_file
	endc
	movem.l	file_frontend_gfx(pc),d0-d4
	bsr.w	load_file
	ifne	CONFIG-RETAIL_2DISK
	bsr.w	unpack_file
	endc
	bsr.w	drive_deselect
	jmp	$20004


;----------------------------------------------------------------------
; Load level 1 (Axis Chemical Factory): level1.bin/.gfx/.map, jump $2200.
;----------------------------------------------------------------------
start_level1:	; from: loader_vectors
	bsr.w	blank_screen
	ifeq	CONFIG-RETAIL_2DISK
level1_disc:
	bsr.w	read_disc_number
	cmpi.b	#$1,d0                          ; disc 1?
	beq.s	level1_load
	bsr.w	insert_other_disc
	bra.s	level1_disc

level1_load:
	bsr.w	blank_screen
	movem.l	file_level1_pic(pc),d0-d3
	lea	level1_palette(pc),a6
	bsr.w	load_picture
	movem.l	file_level1_bin(pc),d0-d3
	bsr.w	load_file
	movem.l	file_level1_gfx(pc),d0-d3
	bsr.w	load_file
	movem.l	file_level1_map(pc),d0-d3
	bsr.w	load_file
	endc
	ifne	CONFIG-RETAIL_2DISK
	movem.l	file_level1_pic(pc),d0-d4
	bsr.w	load_file
	bsr.w	show_picture
	movem.l	file_level1_bin(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level1a_gfx(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level1b_gfx(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level1_map(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	endc
	bsr.w	drive_deselect
	jmp	$2200.w


;----------------------------------------------------------------------
; Load level 2 (Batmobile): level24.bin/.gfx, level2.gfx, jump $2200.
;----------------------------------------------------------------------
start_level2:	; from: loader_vectors
	bsr.w	blank_screen
	ifeq	CONFIG-RETAIL_2DISK
level2_disc:
	bsr.w	read_disc_number
	cmpi.b	#$2,d0                          ; disc 2?
	beq.s	level2_load
	bsr.w	insert_other_disc
	bra.s	level2_disc

level2_load:
	bsr.w	blank_screen
	movem.l	file_level2_pic(pc),d0-d3
	lea	level2_palette(pc),a6
	bsr.w	load_picture
	movem.l	file_level24_bin(pc),d0-d3
	bsr.w	load_file
	movem.l	file_level24_gfx(pc),d0-d3
	bsr.w	load_file
	movem.l	file_level2_gfx(pc),d0-d3
	bsr.w	load_file
	endc
	ifne	CONFIG-RETAIL_2DISK
	movem.l	file_level2_pic(pc),d0-d4
	bsr.w	load_file
	bsr.w	show_picture
	movem.l	file_level24_bin(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level24_gfx(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level2_gfx(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	endc
	bsr.w	drive_deselect
	jmp	$2200.w


;----------------------------------------------------------------------
; Load level 3 (Batcave): level3.bin, jump $28000.
;----------------------------------------------------------------------
start_level3:	; from: loader_vectors
	bsr.w	blank_screen
	ifeq	CONFIG-RETAIL_2DISK
level3_disc:
	bsr.w	read_disc_number
	cmpi.b	#$2,d0                          ; disc 2?
	beq.s	level3_load
	bsr.w	insert_other_disc
	bra.s	level3_disc

level3_load:
	bsr.w	blank_screen
	movem.l	file_level3_pic(pc),d0-d3
	lea	level3_palette(pc),a6
	bsr.w	load_picture
	movem.l	file_level3_bin(pc),d0-d3
	bsr.w	load_file
	endc
	ifne	CONFIG-RETAIL_2DISK
	movem.l	file_level3_pic(pc),d0-d4
	bsr.w	load_file
	bsr.w	show_picture
	movem.l	file_level3_bin(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	endc
	bsr.w	drive_deselect
	jmp	$28000


;----------------------------------------------------------------------
; Load level 4 (Batwing): level24.bin/.gfx, level4.gfx, jump $2202.
;----------------------------------------------------------------------
start_level4:	; from: loader_vectors
	bsr.w	blank_screen
	ifeq	CONFIG-RETAIL_2DISK
level4_disc:
	bsr.w	read_disc_number
	cmpi.b	#$2,d0                          ; disc 2?
	beq.s	level4_load
	bsr.w	insert_other_disc
	bra.s	level4_disc

level4_load:
	bsr.w	blank_screen
	movem.l	file_level4_pic(pc),d0-d3
	lea	level4_palette(pc),a6
	bsr.w	load_picture
	movem.l	file_level24_bin_l4(pc),d0-d3
	bsr.w	load_file
	movem.l	file_level24_gfx_l4(pc),d0-d3
	bsr.w	load_file
	movem.l	file_level4_gfx(pc),d0-d3
	bsr.w	load_file
	endc
	ifne	CONFIG-RETAIL_2DISK
	movem.l	file_level4_pic(pc),d0-d4
	bsr.w	load_file
	bsr.w	show_picture
	movem.l	file_level24_bin_l4(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level24_gfx_l4(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level4_gfx(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	endc
	bsr.w	drive_deselect
	jmp	$2202.w


;----------------------------------------------------------------------
; Load level 5 (Cathedral): level5.bin/.gfx/.map, jump $2200.
;----------------------------------------------------------------------
start_level5:	; from: loader_vectors
	bsr.w	blank_screen
	ifeq	CONFIG-RETAIL_2DISK
level5_disc:
	bsr.w	read_disc_number
	cmpi.b	#$1,d0                          ; disc 1?
	beq.s	level5_load
	bsr.w	insert_other_disc
	bra.s	level5_disc

level5_load:
	bsr.w	blank_screen
	movem.l	file_level5_pic(pc),d0-d3
	lea	level5_palette(pc),a6
	bsr.w	load_picture
	movem.l	file_level5_bin(pc),d0-d3
	bsr.w	load_file
	movem.l	file_level5_gfx(pc),d0-d3
	bsr.w	load_file
	movem.l	file_level5_map(pc),d0-d3
	bsr.w	load_file
	endc
	ifne	CONFIG-RETAIL_2DISK
	movem.l	file_level5_pic(pc),d0-d4
	bsr.w	load_file
	bsr.w	show_picture
	movem.l	file_level5_bin(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level5a_gfx(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level5b_gfx(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	movem.l	file_level5_map(pc),d0-d4
	bsr.w	load_file
	bsr.w	unpack_file
	endc
	bsr.w	drive_deselect
	jmp	$2200.w
	ifne	CONFIG-RETAIL_2DISK

	dc.w	$41f9,$0005,$0000
	endc

;----------------------------------------------------------------------
; Not called by anything: clears $8000 longs from $50000.
;----------------------------------------------------------------------
	ifeq	CONFIG-RETAIL_2DISK
; read to $7fd00 - length, moved up to end at $7fdfe, then decoded to $78000-$7fcff: a marker
; word, a long, then words; the marker followed by a word and a count byte repeats that word.
;----------------------------------------------------------------------
load_picture:	; from: start_level1, start_level2, start_level3, start_level4, start_level5
	move.l	#$78000,d4                      ; screen $78000
	move.b	#$7,$ff8201                     ; video base high
	move.b	#$80,$ff8203                    ; video base mid
	move.l	d2,-(sp)
	addi.l	#$7d00,d4                       ; $7fd00, the end of the screen
	sub.l	d3,d4                           ; - length: the picture is read there
	move.l	d4,d3
	move.l	d3,-(sp)
	pea	(a6)
	bsr.w	load_file
	movea.l	(sp)+,a6
	movea.l	(sp)+,a0
	move.l	(sp)+,d0
	lea	$7fdfe,a3                       ; the data is moved to end here
	lea	$0(a0,d0.w),a1
	subq.w	#1,d0
	btst	#$0,d0
	bne.s	move_picture_up
	addq.w	#1,a3
move_picture_up:
	move.b	-(a1),-(a3)
	dbra	d0,move_picture_up
	lea	$78000,a1
	lea	(a3),a0
	move.w	(a0)+,d7                        ; d7 = marker word
	move.l	(a0)+,d0                        ; skip a long
	lea	(a1),a3
	lea	$7fd00,a3                       ; end of the screen
decode_picture_loop:
	cmpa.l	a3,a1
	bcc.s	set_picture_palette
	move.b	(a0)+,(a1)
	move.b	(a0)+,$1(a1)
	move.w	(a1)+,d0
	cmp.w	d7,d0                           ; the marker?
	bne.s	decode_picture_loop
	subq.w	#2,a1
	move.b	(a0)+,(a1)
	move.b	(a0)+,$1(a1)
	move.w	(a1),d0
	moveq	#0,d1
	move.b	(a0)+,d1                        ; count
	subq.b	#1,d1
repeat_loop:
	move.w	d0,(a1)+
	cmpa.l	a3,a1
	bcc.s	set_picture_palette
	dbra	d1,repeat_loop
	bra.s	decode_picture_loop

set_picture_palette:
	lea	(a6),a0
	lea	$ff8240,a1                      ; palette 0
	move.w	#$7,d0
palette_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,palette_loop
	rts


;----------------------------------------------------------------------
; Show INSERT OTHER DISC: 208 words of plane 0 (insert_disc_gfx) from $7b260, line 80, colour 1 white.
;----------------------------------------------------------------------
insert_other_disc:	; from: after_level, start_level1, start_level2, start_level3, start_level4, start_level5
	lea	$7b260,a0                       ; line 80, word 12
	lea	insert_disc_gfx(pc),a1
	move.w	#$cf,d0                         ; 208 words
draw_message_loop:
	move.w	(a1)+,(a0)
	addq.w	#8,a0
	dbra	d0,draw_message_loop
	move.b	#$7,$ff8201                     ; video base high
	move.b	#$80,$ff8203                    ; video base mid
	bsr.s	wait_vbl
	move.w	#$777,$ff8242                   ; colour 1 white
	endc
	ifne	CONFIG-RETAIL_2DISK
unused_clear_50000:
	move.w	#$7fff,d0
clear_50000_loop:
	clr.l	(a0)+
	dbra	d0,clear_50000_loop
	endc
	rts


;----------------------------------------------------------------------
; Wait for the next frame (video counter mid byte passes $80).
;----------------------------------------------------------------------
wait_vbl:	; from: blank_screen
	move.b	$ff8207,d0                      ; video count mid
	cmpi.b	#$80,d0
	beq.s	wait_vbl
	move.b	#$80,d0
wait_count_past:
	cmp.b	$ff8207,d0                      ; video count mid
	bcs.s	wait_count_past
	rts


;----------------------------------------------------------------------
; Black palette, clear the $78000 screen and show it.
;----------------------------------------------------------------------
blank_screen:	; from: loader_start, after_level, start_level1, start_level2, start_level3, start_level4, ...
	movem.l	d0-d1/a0,-(sp)
	bsr.w	wait_vbl
	move.w	#$2700,sr
	lea	$ff8240,a0                      ; palette 0
	moveq	#15,d0
	moveq	#0,d1
clear_palette_loop:
	move.w	d1,(a0)+
	dbra	d0,clear_palette_loop
	lea	$78000,a0
	move.w	#$1f3f,d0
clear_screen_loop:
	move.l	d1,(a0)+
	dbra	d0,clear_screen_loop
	move.b	#$7,$ff8201                     ; video base high
	move.b	#$80,$ff8203                    ; video base mid
	movem.l	(sp)+,d0-d1/a0
	rts


;----------------------------------------------------------------------
; Unpack the picture file just loaded, decode it to $78000 and set its palette.
;----------------------------------------------------------------------
	ifne	CONFIG-RETAIL_2DISK
show_picture:	; from: loader_start, start_level1, start_level2, start_level3, start_level4, start_level5
	lea	file_vars(pc),a6
	lea	$ff8240,a0                      ; palette 0
	moveq	#7,d0
black_palette_loop:
	clr.l	(a0)+
	dbra	d0,black_palette_loop
	bsr.s	unpack_file
	ifeq	CONFIG-RETAIL_1DISK
	movea.l	$c(a6),a0
	endc
	ifeq	CONFIG-BUDGET_1DISK
	movea.l	d4,a0                           ; the picture is at d4, the load table destination
	nop
	endc
	cmpa.l	#$78000,a0
	bne.s	decode_to_screen
	lea	$70000,a1
	move.w	#$13ff,d0
move_picture_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,move_picture_loop
	lea	$70000,a0
decode_to_screen:
	lea	$78000,a1
	lea	picture_palette(pc),a2
	bsr.w	decode_picture
	lea	picture_palette(pc),a0
	lea	$ff8240,a1                      ; palette 0
	moveq	#7,d0
set_palette_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,set_palette_loop
	rts
	endc


	ifne	CONFIG-RETAIL_2DISK
;----------------------------------------------------------------------
; Unpack the file just loaded in place: copy its TREE chunk to huff_tree, move the packed
; CODE data to the end of the file area, then unpack_form writes the unpacked data from the start.
;----------------------------------------------------------------------
unpack_file:	; from: loader_start, after_level, start_level1, start_level2, start_level3, start_level4, ...
	ifeq	CONFIG-RETAIL_1DISK
	lea	file_vars(pc),a6
	endc
	ifeq	CONFIG-BUDGET_1DISK
	rts                                     ; the sector loader has unpacked the file already

	dc.w	$040e

;----------------------------------------------------------------------
; The reissue's unpack_file after its patched first instruction, not run any more.
;----------------------------------------------------------------------
unused_unpack_rest:
	endc
	movea.l	$c(a6),a0
	moveq	#-2,d3
	move.l	#$434f4445,d1
	bsr.w	find_chunk
	move.l	(a0)+,d0
	addq.l	#1,d0
	and.l	d3,d0
	adda.l	d0,a0
	addq.w	#8,a0
	move.w	#$ff,d0
	pea	(a0)
	lea	huff_tree(pc),a1
copy_tree_loop:
	move.l	(a0)+,(a1)+
	dbra	d0,copy_tree_loop
	movea.l	$c(a6),a0
	lea	(a0),a1
	move.l	#$53495a45,d1
	bsr.s	find_chunk
	addq.w	#4,a0
	move.l	(a0),d0
	addi.w	#$19,d0
	and.l	d3,d0
	adda.l	d0,a1
	movea.l	(sp)+,a0
	move.l	a0,d0
	addi.w	#$3,d0
	andi.l	#$fffffffc,d0
	movea.l	d0,a0
	movea.l	$c(a6),a2
move_code_up_loop:
	move.w	-(a0),-(a1)
	clr.w	(a0)
	cmpa.l	a0,a2
	bcs.s	move_code_up_loop
	lea	$4(a1),a0
	movea.l	$c(a6),a2
	bsr.s	unpack_form
	moveq	#30,d0
clear_header_loop:
	clr.b	(a2)+
	dbra	d0,clear_header_loop
	rts


find_chunk:	; from: unpack_file
	move.l	(a0)+,d0
	cmp.l	d1,d0
	bne.s	find_chunk
	rts


unpack_form:	; from: unpack_file
	bra.w	parse_form


;----------------------------------------------------------------------
; Decode a packed picture: a0 packed data, a1 screen, a2 palette out.  32 byte palette, then
; runs of literal word pairs or repeated words written down the screen in 2 byte columns.
;----------------------------------------------------------------------
decode_picture:	; from: show_picture
	movem.l	d0-d1/d7/a0-a3,-(sp)
	move.b	(a0)+,d0
	cmpi.b	#$3,d0
	bcs.s	copy_palette
	adda.l	#$4,a0
copy_palette:
	moveq	#31,d0
copy_palette_loop:
	move.b	(a0)+,(a2)+
	dbra	d0,copy_palette_loop
	move.b	(a0)+,d7
	asl.w	#8,d7
	move.b	(a0)+,d7
	addq.l	#2,a0
	lea	$0(a0,d7.w),a2
	subq.w	#1,d7
	bmi.s	decode_exit
	lea	$7d00(a1),a3
next_run:
	move.b	(a0)+,d0
	bmi.s	literal_short
	beq.s	repeat_long
	cmpi.b	#$1,d0
	bne.s	repeat_short
	move.b	(a0)+,d0
	asl.w	#8,d0
	move.b	(a0)+,d0
	subq.w	#2,d7
	bra.s	literal_run

literal_short:
	neg.b	d0
	ext.w	d0
literal_run:
	subq.w	#1,d0
literal_loop:
	move.b	(a2)+,(a1)+
	move.b	(a2)+,(a1)+
	bsr.s	next_picture_line
	dbra	d0,literal_loop
	bra.s	run_done

repeat_long:
	move.b	(a0)+,d0
	asl.w	#8,d0
	move.b	(a0)+,d0
	subq.w	#2,d7
	bra.s	repeat_run

repeat_short:
	ext.w	d0
repeat_run:
	subq.w	#1,d0
	move.b	(a2)+,d1
	asl.w	#8,d1
	move.b	(a2)+,d1
repeat_loop:
	move.w	d1,(a1)+
	bsr.s	next_picture_line
	dbra	d0,repeat_loop
run_done:
	dbra	d7,next_run
decode_exit:
	movem.l	(sp)+,d0-d1/d7/a0-a3
	rts


next_picture_line:	; from: decode_picture
	move.l	d0,-(sp)
	lea	$9e(a1),a1
	move.l	a1,d0
	sub.l	a3,d0
	bcs.s	next_line_exit
	suba.w	#$7cf8,a1
	cmpi.w	#$98,d0
	bcs.s	next_line_exit
	suba.w	#$9e,a1
next_line_exit:
	move.l	(sp)+,d0
	rts


;----------------------------------------------------------------------
; Walk a FORM HUFF file: SIZE (unpacked length), TREE and CODE chunks, then unhuff.
;----------------------------------------------------------------------
parse_form:	; from: unpack_form
	movem.l	d0/a0,-(sp)
	move.l	(a0)+,d0
	move.l	(a0)+,d1
	subq.l	#4,d0
	cmpi.l	#$48554646,d1
	beq.s	form_is_huff
	movem.l	(sp)+,d0/a0
	rts

form_is_huff:
	clr.l	-(sp)
	clr.l	-(sp)
	clr.l	-(sp)
	move.l	a6,-(sp)
	movea.l	sp,a6
next_chunk:
	tst.l	d0
	beq.s	chunks_done
	move.l	(a0)+,d1
	subq.l	#4,d0
	bsr.s	huff_chunk
	bra.s	next_chunk

chunks_done:
	tst.l	$4(a6)
	beq.s	parse_form_exit
	tst.l	$4(a6)
	beq.s	parse_form_exit
	tst.l	$8(a6)
	beq.s	parse_form_exit
	tst.l	$c(a6)
	beq.s	parse_form_exit
	movem.l	$4(a6),d0/a0-a1
	bsr.w	unhuff
parse_form_exit:
	movea.l	(sp)+,a6
	lea	$c(sp),sp
	movem.l	(sp)+,d0/a0
	rts


;----------------------------------------------------------------------
; One chunk of the FORM: SIZE, TREE and CODE are recorded in the frame at a6, others skipped.
;----------------------------------------------------------------------
huff_chunk:	; from: parse_form
	cmpi.l	#$53495a45,d1
	beq.s	size_chunk
	cmpi.l	#$434f4445,d1
	beq.s	code_chunk
	cmpi.l	#$54524545,d1
	beq.s	tree_chunk
	movem.l	d0/a0,-(sp)
	move.l	(a0)+,d0
	move.l	d0,d1
	btst	#$0,d1
	beq.s	skip_chunk_pad
	addq.l	#1,d1
skip_chunk_pad:
	addq.w	#4,d1
	add.l	d1,$4(sp)
	sub.l	d1,(sp)
	movem.l	(sp)+,d0/a0
	rts

size_chunk:
	movem.l	d0/a0,-(sp)
	move.l	(a0)+,d0
	move.l	d0,d1
	btst	#$0,d1
	beq.s	size_chunk_pad
	addq.l	#1,d1
size_chunk_pad:
	addq.w	#4,d1
	add.l	d1,$4(sp)
	sub.l	d1,(sp)
	move.l	(a0)+,$4(a6)
	movem.l	(sp)+,d0/a0
	rts

tree_chunk:
	movem.l	d0/a0,-(sp)
	move.l	(a0)+,d0
	move.l	d0,d1
	btst	#$0,d1
	beq.s	tree_chunk_pad
	addq.l	#1,d1
tree_chunk_pad:
	addq.w	#4,d1
	add.l	d1,$4(sp)
	sub.l	d1,(sp)
	lea	huff_tree(pc),a0
	move.l	a0,$c(a6)
	movem.l	(sp)+,d0/a0
	rts

code_chunk:
	movem.l	d0/a0,-(sp)
	move.l	(a0)+,d0
	move.l	d0,d1
	btst	#$0,d1
	beq.s	code_chunk_pad
	addq.l	#1,d1
code_chunk_pad:
	addq.w	#4,d1
	add.l	d1,$4(sp)
	sub.l	d1,(sp)
	move.l	a0,$8(a6)
	movem.l	(sp)+,d0/a0
	rts


;----------------------------------------------------------------------
; Huffman decode: d0 bytes from the bit stream at a0 through the tree at a1 to a2.
;----------------------------------------------------------------------
unhuff:	; from: parse_form
	movem.l	d0/a2,-(sp)
	moveq	#15,d1
	move.w	(a0)+,d2
next_symbol:
	movea.l	a1,a3
next_bit:
	add.w	d2,d2
	bcc.s	bits_left
	addq.w	#2,a3
bits_left:
	dbra	d1,walk_node
	moveq	#15,d1
	move.w	(a0)+,d2
walk_node:
	move.w	(a3),d3
	bmi.s	emit_byte
	adda.w	d3,a3
	bra.s	next_bit

emit_byte:
	move.b	d3,(a2)+
	subq.l	#1,d0
	bne.s	next_symbol
	movem.l	(sp)+,d0/a0
	rts

	dc.w	$4afc

;----------------------------------------------------------------------
; Load a file: d0 track, d1 offset, d2 length, d3 decrypt length, d4 destination
; (one load_table entry, fetched with movem.l).  Reads whole tracks with read_track, checks the
; track number, copies the bytes, unescapes $0f pairs and decrypts the first d3 bytes.
	endc
;----------------------------------------------------------------------
load_file:	; from: loader_start, after_level, start_level1, start_level2, start_level3, start_level4, ...
	ifeq	CONFIG-RETAIL_2DISK
	movem.l	d0-d7/a0-a7,-(sp)
	move.w	#$2700,sr
	lea	file_vars(pc),a6
	move.l	d3,$c(a6)                       ; destination
	move.w	d0,$2(a6)                       ; track
	move.l	d2,$4(a6)                       ; length to decrypt
	move.l	d1,$8(a6)                       ; length on disc
	endc
	ifeq	CONFIG-RETAIL_1DISK
	movem.l	d0-d7/a0-a7,-(sp)
	move.w	#$2700,sr
	lea	file_vars(pc),a6
	move.l	d4,$c(a6)
	move.w	d1,$10(a6)
	move.w	d0,$2(a6)
	move.l	d3,$4(a6)
	move.l	d2,$8(a6)
	endc
	ifeq	CONFIG-BUDGET_1DISK
	moveq	#0,d0                           ; d0 = 0: side 0, read
	jsr	$6f950                          ; sector loader and Pack-Ice depacker (budget_1disk\boot\stage3.s)
	rts

	dc.w	$01be

;----------------------------------------------------------------------
; The reissue's load_file after the patch, not run any more.
;----------------------------------------------------------------------
unused_load_rest:
	move.l	d4,$c(a6)
	move.w	d1,$10(a6)
	move.w	d0,$2(a6)
	move.l	d3,$4(a6)
	move.l	d2,$8(a6)
	endc
	bsr.w	fdc_select
	bsr.w	fdc_regs
	movea.l	$c(a6),a1
	lea	(a1),a5
	adda.l	$8(a6),a5
next_track:
	move.w	$2(a6),d5
	moveq	#14,d3
	moveq	#5,d1
	bsr.w	read_track
	lea	$70000,a0
find_sync:
	cmpi.b	#$a1,(a0)+
	bne.s	find_sync
skip_sync:
	cmpi.b	#$a1,(a0)+
	beq.s	skip_sync
	move.b	(a0)+,d0
	addq.w	#1,a0
	cmp.b	d5,d0
	bne.s	retry_load
	move.w	#$17ff,d0
	move.b	$1801(a0),d3
	lsl.w	#8,d3
	move.b	$1802(a0),d3
	ifne	CONFIG-RETAIL_2DISK
	adda.w	$10(a6),a0
	sub.w	$10(a6),d0
	endc
	moveq	#0,d2
	moveq	#0,d1
copy_byte_loop:
	move.b	(a0)+,d1
	add.w	d1,d2
	rol.w	#1,d2
	move.b	d1,(a1)+
	cmpa.l	a1,a5
	ifeq	CONFIG-RETAIL_2DISK
	beq.s	last_track_checksum
	dbra	d0,copy_byte_loop
	ori.w	#$4992,d2
	andi.w	#$7fbf,d2
	cmp.w	d3,d2
	bne.w	retry_load                      ; bad checksum: start again
	endc
	ifne	CONFIG-RETAIL_2DISK
	beq.s	unescape
	dbra	d0,copy_byte_loop
	clr.w	$10(a6)
	endc
	addq.w	#1,$2(a6)
	bra.s	next_track

	ifeq	CONFIG-RETAIL_2DISK
last_track_checksum:
	ori.w	#$4992,d2
	andi.w	#$7fbf,d2
	cmp.w	d3,d2
	bne.w	retry_load                      ; bad checksum: start again
	endc
	ifne	CONFIG-RETAIL_2DISK
unescape:
	endc
	moveq	#14,d3
	moveq	#5,d1
	movea.l	$c(a6),a1
	lea	(a1),a0
	lea	$1(a1),a2
	adda.l	$8(a6),a2
unescape_loop:
	move.b	(a0)+,d0
	clr.b	-$1(a0)
	cmpa.l	a0,a2
	beq.s	decrypt
	cmpi.b	#$f,d0
	bne.s	unescape_store
	move.b	(a0)+,d0
	clr.b	-$1(a0)
	cmpa.l	a0,a2
	beq.s	decrypt
	not.b	d0
unescape_store:
	move.b	d0,(a1)+
	bra.s	unescape_loop

retry_load:
	movem.l	(sp)+,d0-d7/a0-a7
	bra.w	load_file

decrypt:
	moveq	#1,d4
decrypt_pass:
	movea.l	$c(a6),a0
	lea	(a0),a1
	adda.l	$4(a6),a1
	moveq	#0,d3
	move.l	#$f4bd128c,d0
	move.l	#$5716923a,d1
decrypt_loop:
	move.l	(a0),d2
	eor.l	d0,d2
	swap	d2
	eor.l	d1,d2
	move.l	d2,(a0)+
	add.l	d1,d3
	add.l	d1,d0
	cmpa.l	a0,a1
	bcc.s	decrypt_loop
	dbra	d4,decrypt_pass
	move.w	#$2700,sr
	movem.l	(sp)+,d0-d7/a0-a7
	rts


;----------------------------------------------------------------------
; a4 = $ff8800 PSG, a2 = $ff8604 DMA data, a3 = $ff8606 DMA mode; d3 PSG port A, d4 delay count.
	ifeq	CONFIG-RETAIL_2DISK
; sector: the first serial number byte, 1 on disc 1, 2 on disc 2), -1 if there is none.
;----------------------------------------------------------------------
read_disc_number:	; from: after_level, start_level1, start_level2, start_level3, start_level4, start_level5
	movem.l	d1-d7/a0-a6,-(sp)
	bsr.w	fdc_regs
	bsr.w	fdc_select
	moveq	#0,d5
	bsr.w	read_track
	lea	$70020,a0                       ; from byte $20 of the track
	lea	$70100,a1                       ; to byte $100
find_data_mark:
	cmpa.l	a1,a0
	bcc.s	no_data_mark
	cmpi.b	#$a1,(a0)+
	bne.s	find_data_mark
skip_mark_sync:
	cmpa.l	a1,a0
	bcc.s	no_data_mark
	cmpi.b	#$a1,(a0)+
	beq.s	skip_mark_sync
	cmpi.b	#$fb,-$1(a0)                    ; $fb: data mark
	bne.s	find_data_mark
	move.b	$8(a0),d0                       ; first serial number byte of the boot sector
disc_number_exit:
	movem.l	(sp)+,d1-d7/a0-a6
	rts

no_data_mark:
	moveq	#-1,d0
	bra.s	disc_number_exit


;----------------------------------------------------------------------
; a4 = $ffff8800 PSG, a2 = $ffff8604 FDC access, a3 = $ffff8606 DMA mode; d3 PSG port A, d4 delay.
	endc
;----------------------------------------------------------------------
fdc_regs:	; from: load_file, drive_deselect, fdc_select
	suba.l	a4,a4
	lea	-$7800(a4),a4
	lea	-$1fc(a4),a2
	lea	$2(a2),a3
	moveq	#14,d3
	moveq	#40,d4
	moveq	#5,d1
	rts


;----------------------------------------------------------------------
; Wait for the FDC, deselect the drive through PSG port A, flock = -1, blank the screen.
;----------------------------------------------------------------------
drive_deselect:	; from: loader_start, after_level, start_level1, start_level2, start_level3, start_level4, ...
	ifne	CONFIG-BUDGET_1DISK
	bsr.s	fdc_regs
	endc
	ifeq	CONFIG-BUDGET_1DISK
	rts                                     ; the sector loader deselects the drive


;----------------------------------------------------------------------
; The reissue's drive_deselect after its patched first instruction, not run any more.
;----------------------------------------------------------------------
unused_deselect_rest:
	endc
	move.w	#$80,(a3)
wait_fdc_ready:
	move.w	d4,d2
deselect_delay:
	dbra	d2,deselect_delay
	move.w	(a2),d0
	btst	#$7,d0
	bne.s	wait_fdc_ready
	moveq	#7,d1
	move.b	d3,(a4)
	move.b	(a4),d0
	andi.b	#$f8,d0
	or.b	d1,d0
	move.b	d0,$2(a4)
	st	$43e                            ; flock
	ifeq	CONFIG-RETAIL_2DISK
	bra.w	blank_screen
	endc
	ifne	CONFIG-RETAIL_2DISK
	bsr.w	blank_screen
	rts
	endc


;----------------------------------------------------------------------
; Select drive A side 0 through PSG port A, flock = 0.
;----------------------------------------------------------------------
fdc_select:	; from: load_file
	bsr.w	fdc_regs
	moveq	#14,d3
	moveq	#40,d4
	move.b	d3,(a4)
	move.b	(a4),d0
	andi.b	#$f8,d0
	or.b	d1,d0
	move.b	d0,$2(a4)
	sf	$43e                            ; flock
	rts


;----------------------------------------------------------------------
; Seek to track d5 and Read Track ($e0) into $70000 through the DMA.
;----------------------------------------------------------------------
read_track:	; from: load_file
	move.w	#$86,(a3)
	move.l	d4,d0
mode_delay:
	dbra	d0,mode_delay
	move.w	d5,(a2)
	move.l	d4,d0
track_delay:
	dbra	d0,track_delay
	moveq	#19,d0
	bsr.w	fdc_command
	move.w	#$190,(a3)
	move.w	#$90,(a3)
	move.w	#$16,d0
	bsr.w	fdc_write_reg
	lea	$70000,a0
	move.l	a0,d0
	move.b	d0,$9(a2)
	lsr.w	#8,d0
	move.b	d0,$7(a2)
	swap	d0
	move.b	d0,$5(a2)
	move.w	#$e0,d0
	bra.s	fdc_command


;----------------------------------------------------------------------
; Not called by anything: a delay loop.
;----------------------------------------------------------------------
	ifeq	CONFIG-RETAIL_2DISK
unused_delay_command:
	endc
	ifne	CONFIG-RETAIL_2DISK
unused_delay:
	endc
	move.w	d4,d0
unused_delay_loop:
	dbra	d0,unused_delay_loop

fdc_command:	; from: read_track
	move.w	#$80,(a3)

fdc_write_reg:	; from: read_track
	move.w	d4,d2
reg_delay:
	dbra	d2,reg_delay
	move.w	d0,(a2)
wait_fdc_done:
	btst	d1,$7201(a4)
	bne.s	wait_fdc_done
	rts


	ifeq	CONFIG-RETAIL_2DISK
; Variables and tables.
loader_spare:
	dc.w	$0000,$0000

; Current file: +2 track, +4 length to decrypt, +8 length on disc, +$c destination.
file_vars:	; from: load_file
	dc.w	$0000                           ; spare
	dc.w	$0000                           ; track
	dc.l	$00000000                       ; length to decrypt
	dc.l	$00000000                       ; length on disc
	dc.l	$00000000                       ; destination

; Picture palettes, 16 colours each, set by load_picture.
level1_palette:	; from: start_level1
	dc.w	$0000,$0444,$0222,$0777,$0023,$0411,$0333,$0223
	dc.w	$0555,$0421,$0212,$0760,$0532,$0643,$0754,$0004
level2_palette:	; from: start_level2
	dc.w	$0000,$0545,$0536,$0436,$0314,$0250,$0240,$0230
	dc.w	$0000,$0112,$0223,$0334,$0445,$0556,$0667,$0220
level3_palette:	; from: start_level3
	dc.w	$0000,$0777,$0604,$0230,$0120,$0766,$0544,$0433
	dc.w	$0433,$0730,$0721,$0521,$0400,$0403,$0313,$0212
level4_palette:	; from: start_level4
	dc.w	$0000,$0112,$0223,$0334,$0445,$0556,$0667,$0777
	dc.w	$0333,$0111,$0222,$0630,$0751,$0420,$0101,$0201
level5_palette:	; from: start_level5
	dc.w	$0000,$0112,$0333,$0444,$0555,$0666,$0340,$0120
	dc.w	$0303,$0404,$0525,$0004,$0225,$0045,$0771,$0750

; Load table: 16 bytes per file, see the file list at the top.
load_table:	; from: loader_start
; file 0: panel.gfx, disc 1, tracks 2-3, panel bitmap (resident)
	dc.l	2                               ; start track
	dc.l	$2000                           ; length on disc
	dc.l	$1e80                           ; length to decrypt
	dc.l	$75efc                          ; destination
file_panel_bin:	; from: loader_start
; file 1: panel.bin, disc 1, tracks 4-5, panel / score code (resident)
	dc.l	4                               ; start track
	dc.l	$1a00                           ; length on disc
	dc.l	$1880                           ; length to decrypt
	dc.l	$6b7fc                          ; destination
file_sound_prg:	; from: loader_start
; file 2: sound.prg, disc 1, tracks 6-7, sound driver PRG (resident)
	dc.l	6                               ; start track
	dc.l	$2700                           ; length on disc
	dc.l	$2580                           ; length to decrypt
	dc.l	$6d3e4                          ; destination
file_frontend_bin:	; from: loader_start, after_level
; file 3: frontend.bin, disc 1, tracks 8-9, front end code
	dc.l	8                               ; start track
	dc.l	$2600                           ; length on disc
	dc.l	$2400                           ; length to decrypt
	dc.l	$1fffc                          ; destination
file_frontend_gfx:	; from: loader_start, after_level
; file 4: frontend.gfx, disc 1, tracks 10-17, front end pictures and big font
	dc.l	10                              ; start track
	dc.l	$af00                           ; length on disc
	dc.l	$a900                           ; length to decrypt
	dc.l	$3f236                          ; destination
file_level1_pic:	; from: start_level1
; file 5: level1.pic, disc 1, tracks 18-20, level 1 picture
	dc.l	18                              ; start track
	dc.l	$4300                           ; length on disc
	dc.l	$4046                           ; length to decrypt
	dc.l	$4300                           ; length again (read to $7fd00 - length)
file_level1_bin:	; from: start_level1
; file 6: level1.bin, disc 1, tracks 21-24, level 1 code
	dc.l	21                              ; start track
	dc.l	$5600                           ; length on disc
	dc.l	$5280                           ; length to decrypt
	dc.l	$21fc                           ; destination
file_level1_gfx:	; from: start_level1
; file 7: level1.gfx, disc 1, tracks 25-39, level 1 graphics ($50000 on, one file for the reissue's two)
	dc.l	25                              ; start track
	dc.l	$15600                          ; length on disc
	dc.l	$14a80                          ; length to decrypt
	dc.l	$4fffc                          ; destination
file_level1_map:	; from: start_level1
; file 8: level1.map, disc 1, tracks 40-45, level 1 map
	dc.l	40                              ; start track
	dc.l	$8400                           ; length on disc
	dc.l	$7f80                           ; length to decrypt
	dc.l	$73fc                           ; destination
file_level2_pic:	; from: start_level2
; file 9: level2.pic, disc 2, tracks 1-3, level 2 picture
	dc.l	1                               ; start track
	dc.l	$4300                           ; length on disc
	dc.l	$403d                           ; length to decrypt
	dc.l	$4300                           ; length again (read to $7fd00 - length)
file_level24_bin:	; from: start_level2
; file 10: level24.bin, disc 2, tracks 4-9, level 2/4 code
	dc.l	4                               ; start track
	dc.l	$8900                           ; length on disc
	dc.l	$8400                           ; length to decrypt
	dc.l	$21fc                           ; destination
file_level24_gfx:	; from: start_level2
; file 11: level24.gfx, disc 2, tracks 10-13, level 2/4 graphics
	dc.l	10                              ; start track
	dc.l	$4c00                           ; length on disc
	dc.l	$4880                           ; length to decrypt
	dc.l	$bbfc                           ; destination
file_level2_gfx:	; from: start_level2
; file 12: level2.gfx, disc 2, tracks 14-36, level 2 graphics
	dc.l	14                              ; start track
	dc.l	$21400                          ; length on disc
	dc.l	$20280                          ; length to decrypt
	dc.l	$10434                          ; destination
file_level3_pic:	; from: start_level3
; file 13: level3.pic, disc 2, tracks 37-39, level 3 picture
	dc.l	37                              ; start track
	dc.l	$3d00                           ; length on disc
	dc.l	$3a26                           ; length to decrypt
	dc.l	$3d00                           ; length again (read to $7fd00 - length)
file_level3_bin:	; from: start_level3
; file 14: level3.bin, disc 2, tracks 40-49, level 3
	dc.l	40                              ; start track
	dc.l	$dd00                           ; length on disc
	dc.l	$d580                           ; length to decrypt
	dc.l	$1fffc                          ; destination
file_level4_pic:	; from: start_level4
; file 15: level4.pic, disc 2, tracks 50-52, level 4 picture
	dc.l	50                              ; start track
	dc.l	$3b00                           ; length on disc
	dc.l	$38cd                           ; length to decrypt
	dc.l	$3b00                           ; length again (read to $7fd00 - length)
file_level24_bin_l4:	; from: start_level4
; file 16: level24.bin, disc 2, tracks 4-9, level 2/4 code (as for level 2)
	dc.l	4                               ; start track
	dc.l	$8900                           ; length on disc
	dc.l	$8400                           ; length to decrypt
	dc.l	$21fc                           ; destination
file_level24_gfx_l4:	; from: start_level4
; file 17: level24.gfx, disc 2, tracks 10-13, level 2/4 graphics (as for level 2)
	dc.l	10                              ; start track
	dc.l	$4c00                           ; length on disc
	dc.l	$4880                           ; length to decrypt
	dc.l	$bbfc                           ; destination
file_level4_gfx:	; from: start_level4
; file 18: level4.gfx, disc 2, tracks 53-79, level 4 graphics
	dc.l	53                              ; start track
	dc.l	$28600                          ; length on disc
	dc.l	$27080                          ; length to decrypt
	dc.l	$10434                          ; destination
file_level5_pic:	; from: start_level5
; file 19: level5.pic, disc 1, tracks 46-49, level 5 picture
	dc.l	46                              ; start track
	dc.l	$4a00                           ; length on disc
	dc.l	$474f                           ; length to decrypt
	dc.l	$4a00                           ; length again (read to $7fd00 - length)
file_level5_bin:	; from: start_level5
; file 20: level5.bin, disc 1, tracks 50-53, level 5 code
	dc.l	50                              ; start track
	dc.l	$5700                           ; length on disc
	dc.l	$5400                           ; length to decrypt
	dc.l	$21fc                           ; destination
file_level5_gfx:	; from: start_level5
; file 21: level5.gfx, disc 1, tracks 54-68, level 5 graphics ($50000 on, one file for the reissue's two)
	dc.l	54                              ; start track
	dc.l	$15b00                          ; length on disc
	dc.l	$15000                          ; length to decrypt
	dc.l	$4fffc                          ; destination
file_level5_map:	; from: start_level5
; file 22: level5.map, disc 1, tracks 69-74, level 5 map
	dc.l	69                              ; start track
	dc.l	$8500                           ; length on disc
	dc.l	$8000                           ; length to decrypt
	dc.l	$73fc                           ; destination

; INSERT OTHER DISC, 208 words of plane 0 drawn by insert_other_disc.
insert_disc_gfx:	; from: insert_other_disc
	incbin	"data/2disk_rt/lo_disc.bin"		; $1a0 bytes of data

; Zeros up to the leftover tool.
loader_padding:
	dcb.b	798,$00
	endc

	ifeq	CONFIG-RETAIL_1DISK
; Variables and tables.
loader_spare:
	dc.w	$0000,$0000

; Current file: +2 track, +4 length to decrypt, +8 length on disc, +$c destination,
; +$10 offset into the track.
file_vars:	; from: show_picture, unpack_file, load_file
	dc.w	$0000                           ; spare
	dc.w	$0000                           ; track
	dc.l	$00000000                       ; length to decrypt
	dc.l	$00000000                       ; length on disc
	dc.l	$00000000                       ; destination
	dc.w	$0000                           ; offset into the track

; Load table: 20 bytes per file, see the file list at the top.
load_table:	; from: loader_start
; file 0: title.pic, tracks 2-5, title picture
	dc.l	2                               ; start track
	dc.l	$0                              ; offset into the track
	dc.l	$4a83                           ; length on disc
	dc.l	$4826                           ; length to decrypt
	dc.l	$3f23a                          ; destination (picture)
file_panel_gfx:	; from: loader_start
; file 1: panel.gfx, tracks 5-6, panel bitmap (resident)
	dc.l	5                               ; start track
	dc.l	$284                            ; offset into the track
	dc.l	$17cc                           ; length on disc
	dc.l	$16fa                           ; length to decrypt
	dc.l	$75efc                          ; destination, unpacked to $75f00
file_panel_bin:	; from: loader_start
; file 2: panel.bin, tracks 6-7, panel / score code (resident)
	dc.l	6                               ; start track
	dc.l	$252                            ; offset into the track
	dc.l	$1634                           ; length on disc
	dc.l	$156c                           ; length to decrypt
	dc.l	$6b7fc                          ; destination, unpacked to $6b800
file_sound_prg:	; from: loader_start
; file 3: sound.prg, tracks 7-8, sound driver PRG (resident)
	dc.l	7                               ; start track
	dc.l	$88                             ; offset into the track
	dc.l	$2299                           ; length on disc
	dc.l	$2160                           ; length to decrypt
	dc.l	$6d3e4                          ; destination, unpacked to $6d3e4
file_frontend_bin:	; from: loader_start, after_level
; file 4: frontend.bin, tracks 8-9, front end code
	dc.l	8                               ; start track
	dc.l	$b22                            ; offset into the track
	dc.l	$1cb6                           ; length on disc
	dc.l	$1bc6                           ; length to decrypt
	dc.l	$1fffc                          ; destination, unpacked to $20000
file_frontend_gfx:	; from: loader_start, after_level
; file 5: frontend.gfx, tracks 9-15, front end pictures and big font
	dc.l	9                               ; start track
	dc.l	$fe2                            ; offset into the track
	dc.l	$8262                           ; length on disc
	dc.l	$7e34                           ; length to decrypt
	dc.l	$3f236                          ; destination, unpacked to $3f23a
file_level1_pic:	; from: start_level1
; file 6: level1.pic, tracks 15-16, level 1 loading picture
	dc.l	15                              ; start track
	dc.l	$246                            ; offset into the track
	dc.l	$1868                           ; length on disc
	dc.l	$1788                           ; length to decrypt
	dc.l	$78000                          ; destination (picture)
file_level1_bin:	; from: start_level1
; file 7: level1.bin, tracks 16-19, level 1 code (platform engine)
	dc.l	16                              ; start track
	dc.l	$2b0                            ; offset into the track
	dc.l	$4671                           ; length on disc
	dc.l	$4400                           ; length to decrypt
	dc.l	$21fc                           ; destination, unpacked to $2200
file_level1a_gfx:	; from: start_level1
; file 8: level1a.gfx, tracks 19-23, level 1 graphics
	dc.l	19                              ; start track
	dc.l	$122                            ; offset into the track
	dc.l	$74a1                           ; length on disc
	dc.l	$70de                           ; length to decrypt
	dc.l	$4fffc                          ; destination, unpacked to $50000
file_level1b_gfx:	; from: start_level1
; file 9: level1b.gfx, tracks 23-25, level 1 graphics
	dc.l	23                              ; start track
	dc.l	$15c4                           ; offset into the track
	dc.l	$1d7a                           ; length on disc
	dc.l	$1c70                           ; length to decrypt
	dc.l	$5fffc                          ; destination, unpacked to $60000
file_level1_map:	; from: start_level1
; file 10: level1.map, tracks 25-27, level 1 map
	dc.l	25                              ; start track
	dc.l	$340                            ; offset into the track
	dc.l	$4128                           ; length on disc
	dc.l	$3f0c                           ; length to decrypt
	dc.l	$73fc                           ; destination, unpacked to $7400
file_level2_pic:	; from: start_level2
; file 11: level2.pic, tracks 27-29, level 2 loading picture
	dc.l	27                              ; start track
	dc.l	$146a                           ; offset into the track
	dc.l	$22df                           ; length on disc
	dc.l	$21a4                           ; length to decrypt
	dc.l	$78000                          ; destination (picture)
file_level24_bin:	; from: start_level2
; file 12: level24.bin, tracks 29-33, level 2/4 code (driving engine)
	dc.l	29                              ; start track
	dc.l	$74a                            ; offset into the track
	dc.l	$633a                           ; length on disc
	dc.l	$6006                           ; length to decrypt
	dc.l	$21fc                           ; destination, unpacked to $2200
file_level24_gfx:	; from: start_level2
; file 13: level24.gfx, tracks 33-35, level 2/4 graphics
	dc.l	33                              ; start track
	dc.l	$a86                            ; offset into the track
	dc.l	$2ab0                           ; length on disc
	dc.l	$2926                           ; length to decrypt
	dc.l	$bbfc                           ; destination, unpacked to $bc00
file_level2_gfx:	; from: start_level2
; file 14: level2.gfx, tracks 35-46, level 2 graphics
	dc.l	35                              ; start track
	dc.l	$538                            ; offset into the track
	dc.l	$103ad                          ; length on disc
	dc.l	$fb74                           ; length to decrypt
	dc.l	$10434                          ; destination, unpacked to $10438
file_level3_pic:	; from: start_level3
; file 15: level3.pic, tracks 46-47, level 3 loading picture
	dc.l	46                              ; start track
	dc.l	$e6                             ; offset into the track
	dc.l	$299b                           ; length on disc
	dc.l	$2848                           ; length to decrypt
	dc.l	$78000                          ; destination (picture)
file_level3_bin:	; from: start_level3
; file 16: level3.bin, tracks 47-51, level 3 picture and code
	dc.l	47                              ; start track
	dc.l	$1282                           ; offset into the track
	dc.l	$613d                           ; length on disc
	dc.l	$5e4c                           ; length to decrypt
	dc.l	$1fffc                          ; destination, unpacked to $20000
file_level4_pic:	; from: start_level4
; file 17: level4.pic, tracks 51-53, level 4 loading picture
	dc.l	51                              ; start track
	dc.l	$13c0                           ; offset into the track
	dc.l	$25a7                           ; length on disc
	dc.l	$245c                           ; length to decrypt
	dc.l	$78000                          ; destination (picture)
file_level24_bin_l4:	; from: start_level4
; file 18: level24.bin, tracks 29-33, level 2/4 code (same file as 12)
	dc.l	29                              ; start track
	dc.l	$74a                            ; offset into the track
	dc.l	$633a                           ; length on disc
	dc.l	$6006                           ; length to decrypt
	dc.l	$21fc                           ; destination, unpacked to $2200
file_level24_gfx_l4:	; from: start_level4
; file 19: level24.gfx, tracks 33-35, level 2/4 graphics (same file as 13)
	dc.l	33                              ; start track
	dc.l	$a86                            ; offset into the track
	dc.l	$2ab0                           ; length on disc
	dc.l	$2926                           ; length to decrypt
	dc.l	$bbfc                           ; destination, unpacked to $bc00
file_level4_gfx:	; from: start_level4
; file 20: level4.gfx, tracks 53-65, level 4 graphics
	dc.l	53                              ; start track
	dc.l	$968                            ; offset into the track
	dc.l	$122b7                          ; length on disc
	dc.l	$119a6                          ; length to decrypt
	dc.l	$10434                          ; destination, unpacked to $10438
file_level5_pic:	; from: start_level5
; file 21: level5.pic, tracks 65-67, level 5 loading picture
	dc.l	65                              ; start track
	dc.l	$c20                            ; offset into the track
	dc.l	$281c                           ; length on disc
	dc.l	$26b4                           ; length to decrypt
	dc.l	$78000                          ; destination (picture)
file_level5_bin:	; from: start_level5
; file 22: level5.bin, tracks 67-70, level 5 code (platform engine)
	dc.l	67                              ; start track
	dc.l	$43e                            ; offset into the track
	dc.l	$4a36                           ; length on disc
	dc.l	$47c4                           ; length to decrypt
	dc.l	$21fc                           ; destination, unpacked to $2200
file_level5a_gfx:	; from: start_level5
; file 23: level5a.gfx, tracks 70-74, level 5 graphics
	dc.l	70                              ; start track
	dc.l	$676                            ; offset into the track
	dc.l	$690b                           ; length on disc
	dc.l	$6568                           ; length to decrypt
	dc.l	$4fffc                          ; destination, unpacked to $50000
file_level5b_gfx:	; from: start_level5
; file 24: level5b.gfx, tracks 74-75, level 5 graphics
	dc.l	74                              ; start track
	dc.l	$f82                            ; offset into the track
	dc.l	$1d29                           ; length on disc
	dc.l	$1c38                           ; length to decrypt
	dc.l	$5fffc                          ; destination, unpacked to $60000
file_level5_map:	; from: start_level5
; file 25: level5.map, tracks 75-79, level 5 map
	dc.l	75                              ; start track
	dc.l	$14ac                           ; offset into the track
	dc.l	$5e7e                           ; length on disc
	dc.l	$5b86                           ; length to decrypt
	dc.l	$73fc                           ; destination, unpacked to $7400

; Palette of the picture being shown.
picture_palette:	; from: show_picture
	dcb.b	36,$00

; Work area: the Huffman tree of the file being unpacked ($400 bytes copied from its TREE chunk).
huff_tree:	; from: unpack_file, huff_chunk
	dcb.b	1024,$ff

; Zero padding: with the $4c byte stub in front, the loader fills track 0 sectors 2-9 (4096 bytes).
sector_padding:
	dcb.b	672,$00
	endc

	ifeq	CONFIG-BUDGET_1DISK
; Variables and tables.
loader_spare:
	dc.w	$0000,$0000

; Current file: +2 track, +4 length to decrypt, +8 length on disc, +$c destination,
; +$10 offset into the track.
file_vars:	; from: show_picture
	dc.w	$0000                           ; spare
	dc.w	$0000                           ; track
	dc.l	$00000000                       ; length to decrypt
	dc.l	$00000000                       ; length on disc
	dc.l	$00000000                       ; destination
	dc.w	$0000                           ; offset into the track

; Load table: 20 bytes per file, see the file list at the top.
load_table:	; from: loader_start
; file 0: title.pic, sectors 10-46
	dc.l	2                               ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	10                              ; first sector: track 1 x 10 + sector 1 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	37                              ; sectors
	dc.l	$4826                           ; not used (the reissue's decrypt length)
	dc.l	$3f23a                          ; destination: read and unpacked here
file_panel_gfx:	; from: loader_start
; file 1: panel.gfx, sectors 47-55
	dc.l	5                               ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	47                              ; first sector: track 4 x 10 + sector 8 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	9                               ; sectors
	dc.l	$16fa                           ; not used (the reissue's decrypt length)
	dc.l	$75efc                          ; destination: read and unpacked here
file_panel_bin:	; from: loader_start
; file 2: panel.bin, sectors 56-63
	dc.l	6                               ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	56                              ; first sector: track 5 x 10 + sector 7 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	8                               ; sectors
	dc.l	$156c                           ; not used (the reissue's decrypt length)
	dc.l	$6b7fc                          ; destination: read and unpacked here
file_sound_prg:	; from: loader_start
; file 3: sound.prg, sectors 64-74
	dc.l	7                               ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	64                              ; first sector: track 6 x 10 + sector 5 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	11                              ; sectors
	dc.l	$2160                           ; not used (the reissue's decrypt length)
	dc.l	$6d3e4                          ; destination: read and unpacked here
file_frontend_bin:	; from: loader_start, after_level
; file 4: frontend.bin, sectors 75-83
	dc.l	8                               ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	75                              ; first sector: track 7 x 10 + sector 6 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	9                               ; sectors
	dc.l	$1bc6                           ; not used (the reissue's decrypt length)
	dc.l	$1fffc                          ; destination: read and unpacked here
file_frontend_gfx:	; from: loader_start, after_level
; file 5: frontend.gfx, sectors 84-137
	dc.l	9                               ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	84                              ; first sector: track 8 x 10 + sector 5 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	54                              ; sectors
	dc.l	$7e34                           ; not used (the reissue's decrypt length)
	dc.l	$3f236                          ; destination: read and unpacked here
file_level1_pic:	; from: start_level1
; file 6: level1.pic, sectors 138-147
	dc.l	15                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	138                             ; first sector: track 13 x 10 + sector 9 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	10                              ; sectors
	dc.l	$1788                           ; not used (the reissue's decrypt length)
	dc.l	$78000                          ; destination: read and unpacked here
file_level1_bin:	; from: start_level1
; file 7: level1.bin, sectors 148-171
	dc.l	16                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	148                             ; first sector: track 14 x 10 + sector 9 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	24                              ; sectors
	dc.l	$4400                           ; not used (the reissue's decrypt length)
	dc.l	$21fc                           ; destination: read and unpacked here
file_level1a_gfx:	; from: start_level1
; file 8: level1a.gfx, sectors 172-218
	dc.l	19                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	172                             ; first sector: track 17 x 10 + sector 3 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	47                              ; sectors
	dc.l	$70de                           ; not used (the reissue's decrypt length)
	dc.l	$4fffc                          ; destination: read and unpacked here
file_level1b_gfx:	; from: start_level1
; file 9: level1b.gfx, sectors 219-231
	dc.l	0                               ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	219                             ; first sector: track 21 x 10 + sector 10 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	13                              ; sectors
	dc.l	$1c70                           ; not used (the reissue's decrypt length)
	dc.l	$5fffc                          ; destination: read and unpacked here
file_level1_map:	; from: start_level1
; file 10: level1.map, sectors 232-251
	dc.l	25                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	232                             ; first sector: track 23 x 10 + sector 3 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	20                              ; sectors
	dc.l	$3f0c                           ; not used (the reissue's decrypt length)
	dc.l	$73fc                           ; destination: read and unpacked here
file_level2_pic:	; from: start_level2
; file 11: level2.pic, sectors 252-267
	dc.l	27                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	252                             ; first sector: track 25 x 10 + sector 3 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	16                              ; sectors
	dc.l	$21a4                           ; not used (the reissue's decrypt length)
	dc.l	$78000                          ; destination: read and unpacked here
file_level24_bin:	; from: start_level2
; file 12: level24.bin, sectors 268-299
	dc.l	29                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	268                             ; first sector: track 26 x 10 + sector 9 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	32                              ; sectors
	dc.l	$6006                           ; not used (the reissue's decrypt length)
	dc.l	$21fc                           ; destination: read and unpacked here
file_level24_gfx:	; from: start_level2
; file 13: level24.gfx, sectors 300-312
	dc.l	33                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	300                             ; first sector: track 30 x 10 + sector 1 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	13                              ; sectors
	dc.l	$2926                           ; not used (the reissue's decrypt length)
	dc.l	$bbfc                           ; destination: read and unpacked here
file_level2_gfx:	; from: start_level2
; file 14: level2.gfx, sectors 313-424
	dc.l	35                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	313                             ; first sector: track 31 x 10 + sector 4 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	112                             ; sectors
	dc.l	$fb74                           ; not used (the reissue's decrypt length)
	dc.l	$10434                          ; destination: read and unpacked here
file_level3_pic:	; from: start_level3
; file 15: level3.pic, sectors 425-441
	dc.l	46                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	425                             ; first sector: track 42 x 10 + sector 6 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	17                              ; sectors
	dc.l	$2848                           ; not used (the reissue's decrypt length)
	dc.l	$78000                          ; destination: read and unpacked here
file_level3_bin:	; from: start_level3
; file 16: level3.bin, sectors 442-473
	dc.l	47                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	442                             ; first sector: track 44 x 10 + sector 3 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	32                              ; sectors
	dc.l	$5e4c                           ; not used (the reissue's decrypt length)
	dc.l	$1fffc                          ; destination: read and unpacked here
file_level4_pic:	; from: start_level4
; file 17: level4.pic, sectors 474-489
	dc.l	51                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	474                             ; first sector: track 47 x 10 + sector 5 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	16                              ; sectors
	dc.l	$245c                           ; not used (the reissue's decrypt length)
	dc.l	$78000                          ; destination: read and unpacked here
file_level24_bin_l4:	; from: start_level4
; file 18: lev24_l4.bin, sectors 490-521
	dc.l	29                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	490                             ; first sector: track 49 x 10 + sector 1 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	32                              ; sectors
	dc.l	$6006                           ; not used (the reissue's decrypt length)
	dc.l	$21fc                           ; destination: read and unpacked here
file_level24_gfx_l4:	; from: start_level4
; file 19: lev24_l4.gfx, sectors 522-534
	dc.l	33                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	522                             ; first sector: track 52 x 10 + sector 3 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	13                              ; sectors
	dc.l	$2926                           ; not used (the reissue's decrypt length)
	dc.l	$bbfc                           ; destination: read and unpacked here
file_level4_gfx:	; from: start_level4
; file 20: level4.gfx, sectors 535-656
	dc.l	53                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	535                             ; first sector: track 53 x 10 + sector 6 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	122                             ; sectors
	dc.l	$119a6                          ; not used (the reissue's decrypt length)
	dc.l	$10434                          ; destination: read and unpacked here
file_level5_pic:	; from: start_level5
; file 21: level5.pic, sectors 657-674
	dc.l	65                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	657                             ; first sector: track 65 x 10 + sector 8 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	18                              ; sectors
	dc.l	$26b4                           ; not used (the reissue's decrypt length)
	dc.l	$78000                          ; destination: read and unpacked here
file_level5_bin:	; from: start_level5
; file 22: level5.bin, sectors 675-699
	dc.l	67                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	675                             ; first sector: track 67 x 10 + sector 6 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	25                              ; sectors
	dc.l	$47c4                           ; not used (the reissue's decrypt length)
	dc.l	$21fc                           ; destination: read and unpacked here
file_level5a_gfx:	; from: start_level5
; file 23: level5a.gfx, sectors 700-743
	dc.l	70                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	700                             ; first sector: track 70 x 10 + sector 1 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	44                              ; sectors
	dc.l	$6568                           ; not used (the reissue's decrypt length)
	dc.l	$4fffc                          ; destination: read and unpacked here
file_level5b_gfx:	; from: start_level5
; file 24: level5b.gfx, sectors 744-756
	dc.l	74                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	744                             ; first sector: track 74 x 10 + sector 5 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	13                              ; sectors
	dc.l	$1c38                           ; not used (the reissue's decrypt length)
	dc.l	$5fffc                          ; destination: read and unpacked here
file_level5_map:	; from: start_level5
; file 25: level5.map, sectors 757-783
	dc.l	75                              ; not used (the reissue's start track)
	dc.w	0                               ; not used: the sector loader reads d1.w
	dc.w	757                             ; first sector: track 75 x 10 + sector 8 - 1, side 0
	dc.w	0                               ; not used: the sector loader reads d2.w
	dc.w	27                              ; sectors
	dc.l	$5b86                           ; not used (the reissue's decrypt length)
	dc.l	$73fc                           ; destination: read and unpacked here

; Palette of the picture being shown.
picture_palette:	; from: show_picture
	dc.b	$00

; From here on the 4 KB stage 3 copies to $21000 runs past its own end: what the
; boot sector read is still there.
dat_018f1:
	dcb.b	35,$00

; Work area: the Huffman tree of the file being unpacked ($400 bytes copied from its TREE chunk).
huff_tree:	; from: unused_unpack_rest, huff_chunk
	dcb.b	486,$00
	dc.w	$4963,$6521,$0000,$4880,$0000,$5b2e,$1001,$0005
	dc.w	$2006,$03dc,$e6ac,$3007,$4007,$7007,$4301,$1102
	dc.w	$2203,$3304,$4405,$5506,$6607,$7709,$fa28,$781a
	dc.w	$00ff,$fc2c,$f008,$4a14,$1920,$e123,$d655,$f146
	dc.w	$e3d9,$b221,$7127,$3581,$fa1b,$00de,$d61a,$e706
	dc.w	$7710,$62cf,$18c3,$a2c5,$f812,$45a0,$9cce,$21c4
	dc.w	$62b3,$fa07,$ea09,$e804,$fc0b,$59e3,$3e04,$ed0d
	dc.w	$7dcb,$3e34,$f108,$8319,$c8e3,$f893,$b754,$f508
	dc.w	$fc04,$e8e1,$464d,$8c33,$ea56,$0d46,$5b30,$0a58
	dc.w	$6ad9,$327c,$4cab,$f80f,$4399,$8733,$25ea,$42c6
	dc.w	$8b48,$5664,$4686,$6d1c,$933b,$33c8,$b07e,$5855
	dc.w	$c455,$8874,$305b,$22b3,$42fd,$0909,$1262,$2971
	dc.w	$a30b,$350b,$a146,$9598,$76ac,$0b37,$2b14,$c702
	dc.w	$bb71,$88e2,$5e02,$bf72,$cca5,$7e58,$782c,$205b
	dc.w	$4284,$38eb,$07c1,$de88,$f302,$b93e,$66ad,$4c09
	dc.w	$fd0a,$fd07,$02de,$a1a5,$81c1,$a888,$384d,$0813
	dc.w	$c49e,$ab0c,$5906,$d99e,$03f5,$8ec8,$0f07,$0ed6
	dc.w	$2012,$0f25,$e29a,$ef33,$0789,$7ace,$4509,$3346
	dc.w	$85ab,$33b1,$58b6,$9b22,$15eb,$36b0,$77f0,$0f08
	dc.w	$7263,$f10b,$030b,$1585,$2ed1,$669e,$6b07,$f406
	dc.w	$f306,$21b2,$2fe5,$08b8,$4074,$01fc,$0516,$0404
	dc.w	$3e66,$5ca7,$03e8,$07eb,$acb0,$977a,$abf2,$c9c7
	dc.w	$59ab,$89d9,$05c4,$03e9,$1f3d,$f592,$e90d,$fad0
	dc.w	$4326,$f11e,$ed04,$d8eb,$14f4,$5a7e,$c1cb,$eef5
	dc.w	$0a50,$5a0c,$2b1a,$3409,$f072,$966e,$dcf4,$08ff
	dc.w	$1dcf,$03b1,$5fb6,$05db,$35fa,$25f6,$23d8,$8773
	dc.w	$3b20,$d7ad,$488a,$12ab,$9459,$25e0,$5661,$196d
	dc.w	$05df,$060d,$7596,$94c8,$199a,$84ff,$0a8a,$ce24
	dc.w	$c134,$bc40,$c5e5,$b44a,$905b,$f7ed,$0573,$b2ca
	dc.w	$260c,$f10a,$60a1,$3c2d,$0c90,$1ad3,$dff0,$2299
	dc.w	$f219,$67ee,$4ac6,$83cd,$32a6,$fd04,$d702,$031a
	dc.w	$d0eb,$052f,$3c5d,$0bc1,$145c,$02f3,$34b7,$330a
	dc.w	$a616,$132d,$e3ea,$b165,$a654,$43d6,$6008,$89a3
	dc.w	$7057,$0368,$e27a,$7535,$9e28,$d6f2,$400b,$420b
	dc.w	$f603,$cc3e,$eb08,$7d6a,$2c56,$1614,$9737,$129a
	dc.w	$3545,$8b81,$2c10,$d8ba,$f00c,$a292,$56d8,$b7e6
	dc.w	$a671,$605b,$d92a,$0599,$f503,$c6a4,$ae8c,$9102
	dc.w	$e902,$e1a0,$776d,$f504,$2c0e,$d9c3,$835b,$21ba
	dc.w	$86e7,$3815,$4d69,$b317,$f4d5,$6e2c,$10d9,$c434
	dc.w	$6421,$f505,$f808,$fb0f,$6233,$ece4,$05f1,$351a
	dc.w	$4aad,$b915,$038a,$bd65,$1812,$2582,$6407,$560a
	dc.w	$0b09,$fe49,$667c,$d6e7,$02d3,$11f5,$584f,$f961
	dc.w	$174c,$c1fe,$0244,$06a4,$628f,$6663,$00f5,$04dc
	dc.w	$8430,$29f5,$07b6,$62ed,$89ff,$16f8,$28eb,$2d2d
	dc.w	$1756,$b08b,$5808,$95ac,$cced,$072d,$30e4,$f109
	dc.w	$e246,$8292,$01ff,$1c19,$ba0b,$b2eb,$02e6,$05e9
	dc.w	$8fc8,$604b,$e729,$ac19,$8a10,$c505,$eb04,$f30b
	dc.w	$00bb,$0232,$f01d,$d902,$df05,$e29a,$fad0,$f740
	dc.w	$06f8,$b31d,$d003,$efee,$03f6,$04e5,$9247,$ace9
	dc.w	$f723,$459f,$f7ac,$c7fc,$1131,$2866,$2929,$6618
	dc.w	$8e08,$d200,$df1a,$ce24,$7cae,$fd6a,$0b08,$fafc
	dc.w	$2f0b,$5543,$c49a,$0833,$0c90,$59bf,$94a1,$0cf7
	dc.w	$71c1,$1401,$0935,$1fa1,$f2f4,$2a17,$c81b,$8920
	dc.w	$5613,$8eff,$0a19,$b9aa,$ac16,$2c53,$80fe,$0af3
	dc.w	$da1c,$c74a,$04f6,$1867,$3d8c,$44b3,$0ac6,$e126
	dc.w	$0290,$1518,$9000,$e3fa,$0e91,$223a,$9461,$d6cc
	dc.w	$f206,$58cd,$99ad,$0cfc,$424b,$2a37,$fc0d,$c2bb
	dc.w	$24da,$48d9,$912a,$0e35,$9888,$2cfa,$4964,$5983
	dc.w	$f489,$0422,$1448,$859d,$4109,$06cc,$26d6,$31b5
	dc.w	$8f98,$85c1,$ae33,$0707,$f804,$32cc,$88d5,$558f
	dc.w	$eabb,$664a,$cb1c,$2003,$31e2,$8050,$0220,$5de8
	dc.w	$2a62,$e5dc,$878e,$0610,$d2c4,$0a26,$0559,$2f6b
	dc.w	$1d76,$e104,$0303,$0312,$08f8,$0081,$35b8,$b1c1
	dc.w	$069a,$5ade,$00f1,$14d8,$b858,$fb45,$fe16,$82ec
	dc.w	$fff6,$9138,$9f19,$ee0c,$c0ab,$2c4b,$ea59,$ac09
	dc.w	$6ceb,$264a,$7d98,$01f5,$8729,$ad03,$408b,$0370
	dc.w	$2000,$2b58,$1216,$c6e1,$34d8,$ec38,$d642,$2c07
	dc.w	$f104,$f450,$d093,$3a05,$5acc,$1d1b,$f402,$f50b
	dc.w	$6b71,$96f2,$16fb,$4046,$b50a,$07f5,$1361,$b947
	dc.w	$fd0d,$73a3,$fe58,$3034,$907a,$ff87,$4f25,$0213
	dc.w	$dfac,$0633,$09fe,$1339,$29af,$0808,$4641,$42dc
	dc.w	$e60c,$9194,$2073,$6547,$064b,$c0cf,$ab3b,$6645
	dc.w	$7604,$0705,$8273,$3226,$4397,$9874,$1942,$a0e9
	dc.w	$03f5,$d984,$1589,$27fe,$2486,$350b,$290d,$0193
	dc.w	$480b,$0803,$5a42,$586e,$2f08,$798b,$84c2,$2bed
	dc.w	$6248,$490e,$836c,$8111,$23fa
	endc

	ifeq	CONFIG-RETAIL_2DISK
; Leftover of the tool that wrote the game tracks, never run by the loader: the end of its
; data, then its code.
tool_leftover:
	dc.w	$0000
tool_file_name:
	dc.b	'explode.tok',0

;----------------------------------------------------------------------
; The track writing tool.  It ran at another address: its PC relative variables are $1d986
; bytes below the absolute ones it also uses ($1fa64-$1fb26), and its PC relative and absolute
; targets lie outside this image.  It asks for a file and a start track, loads the file, has it
; prepared past the end of this image ($1ffa, output at $80000) and writes it a track at a time
; with Write Track ($f0): gap, three $f5 syncs, $0f track $0f, 6144 data bytes as they are, the
; checksum word load_file checks, gap.  The code runs on past the end of the sectors.
;----------------------------------------------------------------------
tool_start:
	move.w	sr,d0                           ; supervisor already?
	btst	#$d,d0
	bne.s	tool_next_file
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1                              ; Super
	addq.l	#6,sp
tool_next_file:
	move.w	#$2300,sr
	lea	$3ba0(pc),a0                    ; clear its BSS
	lea	$f7000,a1
tool_clear_loop:
	clr.l	(a0)+
	cmpa.l	a1,a0
	bcs.s	tool_clear_loop
	bsr.w	tool_load_file
	addi.l	#$ff,d1                         ; length rounded up to $100
	andi.l	#$ffff00,d1
	move.l	d1,$1fb1a
	lea	$214c(pc),a0
	bsr.w	tool_print
	move.l	$1fa6c,d7
	bsr.w	tool_print_hex
	lea	$217a(pc),a0
	bsr.w	tool_print
	move.l	$1fb1a,d7
	bsr.w	tool_print_hex
tool_ask_track:
	lea	$20f6(pc),a0
	bsr.w	tool_print
	bsr.w	tool_read_line
	lea	$20b6(pc),a0
	moveq	#0,d0
	move.b	-$1(a0),d0
	clr.b	$0(a0,d0.w)
	cmpi.b	#$3,d0
	bcc.s	tool_ask_track
	moveq	#0,d1
	moveq	#0,d0
	move.b	(a0)+,d0
	subi.b	#$30,d0
	tst.b	(a0)
	beq.s	tool_check_track
	mulu.w	#$a,d0
	move.b	(a0)+,d1
	subi.b	#$30,d1
	add.b	d1,d0
tool_check_track:
	cmpi.b	#$50,d0                         ; tracks 0-79
	bcc.w	tool_ask_track
	move.w	d0,$1fb1e
	lea	$210e(pc),a0
	bsr.w	tool_ask_key
	cmpi.b	#$eb,d0                         ; Esc ($1b - $30): another file
	beq.w	tool_next_file
	move.w	#$2700,sr
	lea	$80000,a0                       ; the prepared file
	bsr.w	tool_write_file
	move.w	#$2300,sr
	illegal                                 ; stop


;----------------------------------------------------------------------
; Print d7 as 6 hex digits with Cconout.
;----------------------------------------------------------------------
tool_print_hex:	; from: tool_start
	moveq	#0,d6
	moveq	#0,d5
	lea	tool_hex_digits(pc),a6
	moveq	#5,d4
	lsl.l	#8,d7
tool_hex_digit_loop:
	rol.l	#4,d7
	move.b	d7,d6
	andi.w	#$f,d6
	move.b	$0(a6,d6.w),d5
	move.w	d5,-(sp)
	move.w	#$2,-(sp)
	trap	#1                              ; Cconout
	addq.w	#4,sp
	dbra	d4,tool_hex_digit_loop
	rts

tool_hex_digits:	; from: tool_print_hex
	dc.b	'0123456789abcdef'

;----------------------------------------------------------------------
; Print the text at a0 and read a key with Cconin, as a digit.
;----------------------------------------------------------------------
tool_ask_key:	; from: tool_start
	bsr.w	tool_print
	move.w	#$1,-(sp)
	trap	#1                              ; Cconin
	addq.w	#2,sp
	subi.b	#$30,d0
	andi.w	#$ff,d0
	rts


;----------------------------------------------------------------------
; Print the text at a0 with Cconws.
;----------------------------------------------------------------------
tool_print:	; from: tool_start, tool_ask_key
	pea	(a0)
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.w	#6,sp
	rts


;----------------------------------------------------------------------
; Write the prepared file from a0 to consecutive tracks from the one asked for.
;----------------------------------------------------------------------
tool_write_file:	; from: tool_start
	move.l	$1fb1a,d0
	beq.w	tool_write_exit
	move.l	#$1800,d1
	move.l	d1,d3
	moveq	#-1,d2
tool_div_shift:
	add.l	d3,d3                           ; d2 = number of tracks ($1800 bytes each)
	cmp.l	d0,d3
	bls.s	tool_div_shift
tool_div_loop:
	lsr.l	#1,d3
	sub.l	d3,d0
	bcc.s	tool_div_bit
	add.l	d3,d0
tool_div_bit:
	roxl.l	#1,d2
	cmp.l	d1,d3
	bhi.s	tool_div_loop
	not.l	d2
	addq.w	#1,d2
	move.w	d2,$1fb20
	move.w	$1fb1e,d0
	move.w	d0,$1fb22
	bsr.w	tool_fdc_select
	bsr.w	tool_fdc_regs
	move.w	#$1,d0
	bsr.w	tool_fdc_command
tool_write_next_track:
	pea	(a0)
	lea	$21a0(pc),a6                    ; track image ($1fb26 where the tool ran)
	move.l	#$4e4e4e4e,d0                   ; gap
	moveq	#9,d1
tool_gap_loop:
	move.l	d0,(a6)+
	dbra	d1,tool_gap_loop
	moveq	#0,d0
	moveq	#2,d1
tool_zero_loop:
	move.l	d0,(a6)+
	dbra	d1,tool_zero_loop
	move.b	#$f5,d0                         ; three syncs
	moveq	#2,d1
tool_sync_loop:
	move.b	d0,(a6)+
	dbra	d1,tool_sync_loop
	move.w	$219c(pc),d0                    ; the track number ($1fb22 where the tool ran)
	move.b	#$f,(a6)+                       ; $0f track $0f
	move.b	d0,(a6)+
	move.b	#$f,(a6)+
	moveq	#0,d2
	moveq	#0,d0
	move.w	#$17ff,d1                       ; 6144 data bytes
tool_data_loop:
	move.b	(a0)+,d0
	add.w	d0,d2
	rol.w	#1,d2
	move.b	d0,(a6)+
	dbra	d1,tool_data_loop
	ori.w	#$4992,d2                       ; the checksum load_file checks
	andi.w	#$7fbf,d2
	clr.b	(a6)+
	ror.l	#8,d2
	move.b	d2,(a6)+
	rol.l	#8,d2
	move.b	d2,(a6)+
	clr.b	(a6)+
	move.w	#$100,d1                        ; gap to the end of the track
tool_gap_end_loop:
	move.b	#$4e,(a6)+
	dbra	d1,tool_gap_end_loop
	bsr.w	tool_fdc_regs
	move.w	$1fb22,d5
	bsr.w	tool_write_track
	movea.l	(sp)+,a0
	lea	$1800(a0),a0
	moveq	#1,d1
	add.w	d1,$1fb22
	sub.w	d1,$1fb20
	bne.w	tool_write_next_track
	bsr.w	tool_drive_deselect
tool_write_exit:
	rts


;----------------------------------------------------------------------
; a4 = $ffff8800 PSG, a2 = $ffff8604 FDC access, a3 = $ffff8606 DMA mode; d3 PSG port A, d4 delay.
;----------------------------------------------------------------------
tool_fdc_regs:	; from: tool_write_file, tool_drive_deselect, tool_fdc_select
	suba.l	a4,a4
	lea	-$7800(a4),a4
	lea	-$1fc(a4),a2
	lea	$2(a2),a3
	moveq	#14,d3
	moveq	#40,d4
	moveq	#5,d1
	rts


;----------------------------------------------------------------------
; Wait for the FDC, deselect the drive, flock = -1.
;----------------------------------------------------------------------
tool_drive_deselect:	; from: tool_write_file
	bsr.s	tool_fdc_regs
	move.w	#$80,(a3)
tool_wait_ready:
	move.w	d4,d2
tool_deselect_delay:
	dbra	d2,tool_deselect_delay
	move.w	(a2),d0
	btst	#$7,d0
	bne.s	tool_wait_ready
	moveq	#7,d1
	move.b	d3,(a4)
	move.b	(a4),d0
	andi.b	#$f8,d0
	or.b	d1,d0
	move.b	d0,$2(a4)
	st	$43e                            ; flock
	rts


;----------------------------------------------------------------------
; Select drive A side 0, flock = 0.
;----------------------------------------------------------------------
tool_fdc_select:	; from: tool_write_file
	bsr.w	tool_fdc_regs
	moveq	#14,d3
	moveq	#40,d4
	move.b	d3,(a4)
	move.b	(a4),d0
	andi.b	#$f8,d0
	or.b	d1,d0
	move.b	d0,$2(a4)
	sf	$43e                            ; flock
	rts


;----------------------------------------------------------------------
; Seek to track d5 and Write Track ($f0) from $1fb26.
;----------------------------------------------------------------------
tool_write_track:	; from: tool_write_file
	move.w	#$86,(a3)
	move.l	d4,d0
tool_mode_delay:
	dbra	d0,tool_mode_delay
	move.w	d5,(a2)
	move.l	d4,d0
tool_track_delay:
	dbra	d0,tool_track_delay
	moveq	#17,d0                          ; SEEK, no verify, 6 ms
	bsr.s	tool_fdc_command
	move.w	#$90,(a3)
	move.w	#$190,(a3)
	moveq	#14,d0
	bsr.w	tool_fdc_write_reg
	move.l	#$1fb26,d0                      ; track image
	move.b	d0,$9(a2)
	lsr.w	#8,d0
	move.b	d0,$7(a2)
	swap	d0
	move.b	d0,$5(a2)
	move.w	#$f0,d0                         ; WRITE TRACK
	move.w	#$180,(a3)
	bsr.w	tool_fdc_write_reg
	move.w	#$190,(a3)
	move.w	(a3),d7
	move.w	d7,$1fb24
	rts


tool_fdc_command:	; from: tool_write_file, tool_write_track
	move.w	#$80,(a3)

tool_fdc_write_reg:	; from: tool_write_track
	move.w	d4,d2
tool_reg_delay:
	dbra	d2,tool_reg_delay
	move.w	d0,(a2)
tool_wait_fdc:
	btst	d1,$7201(a4)
	bne.s	tool_wait_fdc
	rts


;----------------------------------------------------------------------
; Ask for the file name, open it, read it to $21526 and have it prepared to $80000 by $1ffa,
; past the end of this image; d1 = the prepared length.
;----------------------------------------------------------------------
tool_load_file:	; from: tool_start
	lea	$205a(pc),a0
	bsr.w	tool_print_line
	bsr.w	tool_read_line
	lea	$20b6(pc),a0
	moveq	#0,d0
	move.b	-$1(a0),d0
	clr.b	$0(a0,d0.w)
	bsr.w	tool_open_file
	lea	$21526,a4                       ; file buffer
	lea	(a4),a0
	bsr.w	tool_read_file
	movea.l	a4,a0
	bsr.w	$1ffa
	move.l	$20e6(pc),d0
	suba.l	#$80000,a1
	addq.w	#4,a1
	move.l	a1,d1
	rts


;----------------------------------------------------------------------
; Not called in what is left: the decrypt of load_file over a buffer, twice.
;----------------------------------------------------------------------
tool_crypt:
	moveq	#1,d4
	addi.l	#$10,$1fa66
tool_crypt_pass:
	movea.l	$20ee(pc),a0
	movea.l	$20f2(pc),a1
	moveq	#0,d3
	move.l	#$f4bd128c,d0
	move.l	#$5716923a,d1
tool_crypt_loop:
	move.l	(a0),d2
	eor.l	d0,d2
	swap	d2
	eor.l	d1,d2
	move.l	d2,(a0)+
	add.l	d1,d3
	add.l	d1,d0
	cmpa.l	a0,a1
	bcc.s	tool_crypt_loop
	dbra	d4,tool_crypt_pass
	rts


tool_print_line:	; from: tool_load_file
	pea	(a0)
	move.w	#$9,-(sp)
	trap	#1                              ; Cconws
	addq.l	#6,sp
	rts


tool_read_line:	; from: tool_start, tool_load_file
	pea	$20b4(pc)
	move.w	#$a,-(sp)
	trap	#1                              ; Cconrs
	addq.l	#6,sp
	rts


tool_open_file:	; from: tool_load_file
	clr.w	-(sp)
	pea	$20b6(pc)
	move.w	#$3d,-(sp)
	trap	#1                              ; Fopen
	addq.l	#8,sp
	move.w	d0,$1fa64
	rts


tool_read_file:	; from: tool_load_file
	move.l	a0,-(sp)
	pea	(a0)
	move.l	#$c0000,-(sp)
	dc.w	$3f39

	endc
	end
