# Batman The Movie (Ocean, 1989) - Atari ST disassembly

Disassembled by Darren Birks in the evil month of October 2026.

The game is not one program: the boot sector copies a loader to `$1000` and the loader pulls the files it needs for each scene off the disk (sectorless tracks 2-81 in an escaped format, FORM HUFF packed). The top of [loader.s](loader.s) describes the track and file format. [retail_1disk_speedlock/speedlock/pseudo_c.txt](retail_1disk_speedlock/speedlock/pseudo_c.txt) describes the reissue's boot, protection and disk, and [retail_2disk_speedlock/speedlock/pseudo_c.txt](retail_2disk_speedlock/speedlock/pseudo_c.txt) those of the 2 disk release.

## Versions

Each version of the game has its own folder of extracted files.

### 2 disk retail release, the original (SpeedLock)

Folder `retail_2disk_speedlock`. The first release. Its SpeedLock stages (on disk 1) differ from the reissue's in one branch; its game loader is a different program.

| Path | Contents |
|---|---|
| `loader.bin` | The decrypted game loader (loadstub.s, loader.s). |
| `disk1/`, `disk2/` | The game files of each disk, as loaded. They are not packed, so there is no `packed/` and `unpacked/` (pictures are run length packed, decoded by `load_picture` in loader.s). Disk 2's level24.bin and level4.gfx are the same as the reissue's, so they are kept only in `retail_1disk_speedlock/unpacked`. |
| `speedlock/` | The boot stages up to the game loader, as Devpac sources: `bootsect.s` (track 0 sector 1), `protect.s` (track 1 sectors 5-7, decryptor and timing check), `layer3.s` (track 1 sectors 8-10, third layer, loads and decrypts loader.bin). `.bin` = sectors as on the disk, `.dec` = decrypted, what each source assembles to. `pseudo_c.txt` = C pseudocode of all of it. |

### 1 disk retail reissue (SpeedLock)

Folder `retail_1disk_speedlock`. The reissue on 1 disk, after the 2 disk release, SpeedLock protected.

| Path | Contents |
|---|---|
| `loader.bin` | The decrypted game loader: the stub at `$21000` and the code that runs at `$1000` (loadstub.s, loader.s). |
| `packed/`, `unpacked/` | The 24 files as on the disk (FORM HUFF) and unpacked. Level 4 loads level24.bin and level24.gfx again, so the load table has 26 entries. The file table (tracks, lengths, load addresses, names) is at the top of loader.s. |
| `speedlock/` | As above, for this version. |

### 1 disk budget release (The Hit Squad)

Folder `budget_1disk`. No protection, a standard 10 x 512 byte sector disk of which only side 0 is used. The files are Pack-Ice 2.31 packed; most likely made from a cracked copy of the reissue (see below).

| Path | Contents |
|---|---|
| `loader.bin` | The 4 KB game loader stage 3 copies to `$21000`: the reissue's, with `load_file` calling the sector loader at `$6f950` (loadstub.s, loader.s). |
| `packed/`, `unpacked/` | The 26 files as on the disk and unpacked: the reissue's unpacked files, each with 31 bytes more (only the tails differ), and level 4's own copies: lev24_l4.bin (level24.bin 3 bytes shorter) and lev24_l4.gfx (the same as level24.gfx). |
| `boot/` | The boot stages, as Devpac sources that assemble to the `.bin` files: `bootsect.s` (track 0 sector 1, reads tracks 0-1 to `$fe00`), `stage2.s` (track 0 sectors 2-8 at `$10000`: unpacks `stage3.ice`), `stage3.s` (unpacked stage 3: fade, sector loader and Pack-Ice depacker for `$6f950`, reset handler for `$300`, and the game loader, incbin `gameload.bin`). |

## Differences between the versions

| | RETAIL_2DISK | RETAIL_1DISK | BUDGET_1DISK |
|---|---|---|---|
| Released | first, the original | reissue | budget, Hit Squad |
| Disks | 2 | 1 | 1, side 0 only |
| Protection | SpeedLock | SpeedLock | none |
| Game tracks | escaped, each file at a track start | escaped, files run on track to track | 10 x 512 byte sectors |
| File packing | none (pictures run length packed) | FORM HUFF | Pack-Ice 2.31 |
| Track checks | checksum per track, disc number | checksum read, not checked | none |
| Level code | original | bugs fixed | the reissue's |

**Protection.** Both retail versions have the same SpeedLock boot sector and third layer. `protect.s` differs in one branch: the 2 disk release fails on the first `$fe` byte after Read Track that is not sector 1's ID. `speedlock/pseudo_c.txt` in each retail folder describes the stages in C.

**Loader.** The 2 disk loader reads unpacked files, each from the start of a track, checks the checksum word that ends every track, finds the disc number in the boot sector's serial number and shows INSERT OTHER DISC. Its sectors end in leftover code of the tool that wrote the game tracks, which nothing runs. The reissue's loader packs the files with FORM HUFF and lets them run on from track to track; it reads the checksum but does not check it. Track 0 sector 9 has a bad data CRC on both 2 disk discs and nothing checks it; on disc 1 it holds only leftover code of the track writing tool. The budget loader is the reissue's with four routines patched (see loader.s).

### What the reissue changed from the 2 disk release

Found by comparing the files in `retail_2disk_speedlock/disk1` and `disk2` with those in `retail_1disk_speedlock/unpacked`: code instruction by instruction, data word by word with the code address shifts taken out, graphics after running the reissue's own conversion. Addresses are where the code runs; labels are the reissue's. The code bugs are also commented in the RETAIL_2DISK blocks of level1.s and level5.s. Nothing here has been checked in play.

#### Bugs the reissue fixed

- **Level 5, respawn outside the cathedral.** In `checkpoint_starts` checkpoint 1 has `scroll_y` `$0044` on the 2 disk release, `$0448` on the reissue. The third word of each entry is `scroll_y` + the player's screen height (`$0608+$48`, `$0448+$28`, `$0268+$28`), which fits `$0448`. After a death past checkpoint 1 the 2 disk release restores the view 1028 lines too high in the map.
- **Levels 1 and 5, sheared 64 pixel sprites.** After the four 16 pixel columns of a line `blit_full_4` steps on with `lea 136(a2),a2`, so each line moves 168 bytes on a 160 byte screen and the sprite shears 8 bytes (one 16 pixel column) to the right per line. The reissue has `lea 128(a2),a2`.
- **Level 5, thugs walking right always show the same legs.** `goon_right_draw` saves the frame after adding `$40` and then tests it against `$0a` to choose the legs, which it is never below. The reissue saves the frame before the add.
- **Level 5, wrong crawler frames.** `crawler_right_draw` and `crawler_left_draw` take the frame from d4 as the movement code left it (the x position & 7 before the move, and not masked at all on the turn path). The reissue reads the x position from the enemy and masks it.
- **Level 1, stray pixels.** From `$53c50` on, 3050 blocks of the level 1 graphics have plane bits set under the transparent mask. The masked blitters AND the screen with the mask and then OR the planes in, so those bits show over the background. The reissue clears them.

#### Other changes

- **Graphics packing, levels 1 and 5.** The reissue keeps the tile and sprite graphics as 4 bits per pixel, with colour 15 for transparent, and turns them into the drawing format at level start: `level_start` calls `convert_level_gfx` twice (level 1: `$6019c` x `$741` and `$501f4` x `$1961` blocks; level 5: `$601b4` x `$801` and `$501e4` x `$1961`), which turns each 8 byte block into a mask word and 4 plane words. The 2 disk release stores them already in that form, as one level1.gfx / level5.gfx from `$50000`. Running the reissue's conversion on its files gives the 2 disk data except for the level 1 blocks above and 52 level 5 blocks (masks as well, around `$53a84`, `$5f000` and `$64000`: small changes to the pictures). `build_sprite_tables` moved from `level_begin` to `level_start`, after the conversion.
- **climb_column_animate (in levels 1 and 5, run by level 5's rope ladder):** the swinging rope ladder alternates map words `$6bc6`/`$6cc7` on the 2 disk release and `$6bc6`/`$6ac5` on the reissue (the map file is the same). The frame counter computed into d2 is overwritten in both.
- **Level 5 spawn_table:** the type 31 object (`boss_climb`, the Joker on the rope ladder) at x 460 is at y 56 on the 2 disk release, y 64 on the reissue.

#### Files that are the same

panel.gfx, sound.prg, frontend.bin, frontend.gfx, level1.map, level5.map, level24.bin and level4.gfx are byte for byte the same in both releases (the 2 disk files are longer only by the padding of their decrypt length).

#### Files that differ only in bytes nothing uses

| File | Difference |
|---|---|
| panel.bin | The code is the same. The 2 disk file has leftover bytes in two places: `time_digit_offsets` entries 12-15 (the digits passed are never that high) and the 65 bytes after the high score table, which hold fragments of panel code where the reissue has zeros. |
| level3.bin | One byte: the byte after the 32 byte `batcave_palette`, the last of the reissue's file (`$0f` on the 2 disk release, `$af` on the reissue). |
| level24.gfx | The last 4 bytes, which level2.gfx and level4.gfx are loaded over. |
| level2.gfx | The last 8 bytes, which the level setup overwrites when it builds its sprite sets from `$30690`. |
| level5.bin | Filler after the font that level5.map is loaded over (`$1a` bytes on the reissue, zeros on the 2 disk release). |

#### Found in both releases

- `checkpoint_3` can set checkpoint 3, but `checkpoint_starts` has entries for 0-2 only, so the fourth copy in `level_begin` copies `scroll_x` and the words after it onto themselves. Whether checkpoint 3 is placed in the level is not checked.
- level24.gfx, level2.gfx and level4.gfx run `$c00` bytes above the address in their own header (see Data files).

### The budget release

Its game files are the reissue's unpacked files, each with 31 bytes added at the end, so the levels play as the reissue does. We assume it was made from a cracked copy of the reissue rather than from Ocean's own masters, because:

- the SpeedLock protection is gone and the disk is a standard sector disk;
- the game loader is the reissue's, byte for byte, patched in place: `load_file` jumps to a new sector loader at `$6f950`, `unpack_file` and `drive_deselect` return at once, `show_picture` takes the picture where it was loaded, and the old code of these routines is still there after the patches (`unused_load_rest`, `unused_unpack_rest`, `unused_deselect_rest`);
- the files are packed with Pack-Ice 2.31, a packer from the crack and demo scene, in place of Ocean's FORM HUFF, and stage 3 of the boot is packed with it too.

No crack group name, intro or message was found on the disk.

## Sources

Each code file is disassembled into one Devpac source with its load address as `org`; pictures, graphics, maps and music stay as the binaries.

Every source holds all the versions. [config.s](config.s) says which one to assemble; set `CONFIG` in it to

| CONFIG | Version |
|---|---|
| `RETAIL_2DISK` | the 2 disk retail release (the original) |
| `RETAIL_1DISK` | the 1 disk retail reissue |
| `BUDGET_1DISK` | the 1 disk budget release |

Each source includes config.s. The lines all versions have are there once; the parts that differ are in blocks: `ifeq CONFIG-<version>` ... `endc` for one version, `ifne CONFIG-<version>` ... `endc` for all versions but one, and blocks inside blocks where two versions share code the third has not got. The boot stages are separate, in each version folder's `speedlock/` or `boot/`. [What the reissue changed](#what-the-reissue-changed-from-the-2-disk-release) lists what the 2 disk release's blocks change; the budget release's are the four routines of its loader.

### Rebuilding

Every source assembles, for every config, to the version's extracted file byte for byte (checked with vasm 1.8i in Devpac mode):

```
vasmm68k_mot -devpac -m68000 -Fbin -o level1.bin level1.s
```

vasm is in [tools/vasm](tools/vasm/README.txt), and the scripts in this folder use it:

| Script | Builds |
|---|---|
| [build.cmd](build.cmd) | the 2 MB file version (build-2mb.cmd): the quickest way to try an edited source or map, as nothing is packed |
| [build.cmd](build.cmd) `RETAIL_2DISK` | one release (`RETAIL_2DISK`, `RETAIL_1DISK` or `BUDGET_1DISK`) |
| [build-all.cmd](build-all.cmd) | all three releases |
| [build-2mb.cmd](build-2mb.cmd) | the 2 MB file version: `2mb-file-version/files`, loader.bin and batman.prg |
| [build-512.cmd](build-512.cmd) | the 512K file version: `512-file-version/files` packed with Pack-Ice 2.40 (`tools/icepack/icepack.py`, Python 3; about half a minute), loader.bin and batman.prg |
| [build-files.cmd](build-files.cmd) | used by both: the reissue's 24 game files, unpacked, in `build/file-version` |

Each release is built in `build/<release>/`: a copy of the sources and `data/`, a config.s that selects the release (the one here is left as it is), and `<source>.bin` for each of the nine sources, the file as the game loads it after its 4 byte load address (sound.bin is the text and data of sound.prg).

The file versions are made from the reissue's build: the code files get their 4 byte load address back (the `org` of their source), sound.bin becomes SOUND.PRG again (its 28 byte header, the code and an empty relocation table), loader.bin is loadstub.bin followed by loader.bin, and the pictures, graphics and maps come from `retail_1disk_speedlock/unpacked`. Built from the sources as they are, every file comes out as it is in the two folders. The floppy images (batman.st) are not rebuilt.

One instruction is written as `dc.w`: frontend.s `cmpi.b #$ff,d0`, whose original encoding has `$ffff` as its immediate word, which an assembler writes as `$00ff`.

### The sources

Assemble each with Devpac, `opt o-`, org = load address. What each assembles to is the file after its 4 byte load address, or the PRG's text and data for sound.prg.

| Source | Load | File | Contents |
|---|---|---|---|
| [config.s](config.s) | | | which version to assemble (`CONFIG`) |
| [loadstub.s](loadstub.s) | `$21000` | loader.bin | boot stub that copies the loader to `$1000` |
| [loader.s](loader.s) | `$1000` | loader.bin | loader: six entry vectors (front end after a level, levels 1-5), track reader, load table. RETAIL_1DISK with unhuff and the picture decoder; RETAIL_2DISK with a checksum per track, the disc check and INSERT OTHER DISC (the end of its sectors is leftover code of the tool that wrote the game tracks); BUDGET_1DISK is the reissue's loader with `load_file` calling the sector loader at `$6f950`, `unpack_file` and `drive_deselect` just returning, `show_picture` taking the picture where it was loaded, and its own load table (logical side 0 sectors) |
| [panel.s](panel.s) | `$6b800` | panel.bin | resident panel: timer, score, lives, energy (`panel_*`) |
| [sound.s](sound.s) | `$6d400` | sound.prg | resident sound driver (`snd_*`) |
| [frontend.s](frontend.s) | `$20000` | frontend.bin | title, credits script, high scores, cheat |
| [level1.s](level1.s) | `$2200` | level1.bin | level 1, Axis Chemical Factory (platform engine) |
| [level24.s](level24.s) | `$2200` | level24.bin | level 2 Batmobile and level 4 Batwing (driving engine, entry `$2200` / `$2202`) |
| [level3.s](level3.s) | `$20000` | level3.bin | level 3, Batcave puzzle (picture first, code at `$28000`) |
| [level5.s](level5.s) | `$2200` | level5.bin | level 5, Cathedral (level 1 engine, named as in level1.s) |

### Data files

The data files are left as they are: `retail_1disk_speedlock/unpacked` and `budget_1disk/unpacked`, and for the 2 disk release `retail_2disk_speedlock/disk1` and `disk2`, with one level1.gfx / level5.gfx from `$50000` each, and level4.gfx from the reissue's folder.

| File | Load | Contents |
|---|---|---|
| title.pic, level1.pic .. level5.pic | | packed pictures shown by the loader |
| panel.gfx | `$75f00` | panel bitmap |
| frontend.gfx | `$3f23a` | pictures, big font |
| level1a.gfx | `$50000` | level 1 graphics |
| level1b.gfx | `$60000` | level 1 graphics |
| level1.map | `$7400` | level 1 map |
| level24.gfx | `$bc00` | level 2/4 graphics |
| level2.gfx | `$10438` | level 2 graphics |
| level4.gfx | `$10438` | level 4 graphics |
| level5a.gfx | `$50000` | level 5 graphics |
| level5b.gfx | `$60000` | level 5 graphics |
| level5.map | `$7400` | level 5 map (loaded over the tail of level5.bin) |

level24.gfx, level2.gfx and level4.gfx start with a load address `$c00` lower than where the loaders put them; the addresses above are the real ones.

## Map files (level1.map, level5.map)

Levels 1 and 5 use the same platform engine and the same map format. A map file loads at `$7400` (level5.map over the end of level5.bin) and holds:

| Part | Level 1 | Level 5 | Contents |
|---|---|---|---|
| Header | `$7400`-`$7405` | `$7400`-`$7405` | 3 words: tile count, row length, rows |
| Map | `$7406`-`$957d` | `$7406`-`$bd55` | one byte per tile, row by row |
| Tile table | `$957e`-`$977d` | `$bd56`-`$bf55` | one word per tile (see below) |
| Work space | `$977e`-`$997d` | `$bf56`-`$c155` | reference counts and cache slots, set at level start; the file's bytes there are not used |
| Blocks | `$997e`-`$c27d` | `$c156`-`$f355` | the tile graphics, `$80` bytes a block |

The code reads only the tile count from the header; the row length and the number of rows are built into it.

| | Level 1 | Level 5 |
|---|---|---|
| Tiles | 253 | 255 |
| Map size | 204 x 42 tiles | 92 x 204 tiles |
| In pixels | 3264 x 672 | 1472 x 3264 |
| Blocks | 82 (81 used) | 100 (96 used) |

Tiles are 16 x 16 pixels; the code keeps positions in units of 2 pixels.

A **block** is 16 x 16 pixels in 4 bitplanes with no mask: 16 lines of 4 words (planes 0-3), `$80` bytes. The colours come from the level's palette, which the level code sets (and changes part way down the screen).

A **tile** is a pair of blocks. Its word in the tile table holds:

| Bits | Contents |
|---|---|
| 15-8 | the tile's own block |
| 7-0 | the block of the tile to its right |

When a tile enters the tile cache, the engine makes 8 copies of it, 2 pixels apart: its own block slid left, with the left edge of the right hand block filling in, so the map can scroll by 2 pixels with no work at draw time. Next to almost every tile in both maps the tile to its right has that block as its own (8510 of 8526 pairs on level 1, 18536 of 18564 on level 5).

At level start `build_tile_order` sorts the tile table by its words and renumbers every byte of the map to match (level 1's table is in that order already, level 5's is not). The tile types are tested against the new numbers:

| Type | Level 1 | Level 5 | What the code does |
|---|---|---|---|
| Wall | `$00`-`$27` | `$00`-`$17` | stops walking, bullets, batarangs and a fall's sideways move; no dropping through |
| Open space | `$28`-`$e1` | `$18`-`$c9` | nothing stops the player |
| Deadly floor | - | `$ca`-`$cc` | falling onto one counts as a fall of `$70`, which costs a life |
| Floor | `$e2`-`$f9` | `$cd`-`$f7` | stand and walk on it, land on it, drop through it; enemies turn at its end; the bat-rope hooks onto it |
| Ladder | `$fa`-`$fc` | `$f8`-`$fe` | climb; level 1's `$fa`-`$fb` and level 5's `$f8`-`$fa` are floor as well |

As the tiles are sorted by their own block, each type is a run of blocks:

| Type | Level 1 | Level 5 |
|---|---|---|
| Wall | 40 tiles, blocks 0-10 | 24 tiles, blocks 0-2 |
| Open space | 186 tiles, blocks 11-71 | 178 tiles, blocks 3-79 |
| Deadly floor | - | 3 tiles, block 80 |
| Floor | 24 tiles, blocks 72-77 | 43 tiles, blocks 81-95 |
| Ladder | 3 tiles, blocks 78-80 | 7 tiles, blocks 96-99 |

The type limits are fixed tile numbers in the code (`TILE_OPEN` and so on at the top of level1.s and level5.s), so an edited map has to keep the number of tiles of each type: tiles that exist can go anywhere, but a new pair of blocks can only replace an unused pair of the same type, or every tile after it moves across a limit. There are at most 256 tiles.

Not in the map file: the enemies and objects (`spawn_table`) and the restart points (`checkpoint_starts`) are in the level code. On level 5, `climb_column_animate` changes a few map words while the level plays to swing the rope ladder.

## Map editor

Folder `tools/map-editor`. [map-editor.html](tools/map-editor/map-editor.html) is a map editor for levels 1 and 5 that runs in a web browser: open it, then open (or drop on it) an unpacked level1.map or level5.map (`retail_1disk_speedlock/unpacked`), and for the objects the level's source, [level1.s](level1.s) or [level5.s](level5.s). Nothing is sent anywhere; **Save map** and **Save source** give the edited files back to save.

- The map is drawn with its own blocks, in the level's colours. The tile types can be shown over it, and so can a grid and the broken pairs (cells whose right hand block is not the one their tile expects; there are a few in the original maps too).
- The blocks are listed by type. Left click or drag paints the selected block; right click (or Alt and click) picks the block under the cursor. Blocks with no tile for the pair they would make at the cursor are dimmed.
- Painting a block sets the tiles of the cell and of its left neighbour to the pairs they now make. A pair with no tile can take over a tile that is no longer on the map, of the same type, as long as the game's sorted order of the tiles on the map stays the same; the tile numbers the code uses itself (0, 3, 9, `$4f`, `$51`-`$54`, `$5e`, `$6a`-`$6c`, `$c5`-`$c7`) are never taken. Otherwise the paint is refused with a message.
- The level's source gives the editor its settings: the map size (it must match the map), the tile type limits, the palette, the time limit, `SPAWN_OFFSET_X`, the object routines (`enemy_type_table`) and which object types the game draws (`type_sprite_table`). The places the code fixes (level 1's vat, level 5's ending view, lowest view and rope ladder) are drawn on the map, for reference; they are changed in the source.
- **Edit objects** shows the bad guys and other objects, each group's trigger point (the group appears when it comes into view) with lines to its objects, the single objects, and the start and restart positions with the view they start in. Drag them to move them (by map cells, Shift for 2 pixels), or type their numbers in. Click an empty spot, then **Add object** (into the selected group, or as a single object), **New group**, or **Delete** (also the Delete key); the arrow keys nudge. The list of types is the types the level already uses. Where the releases differ (two values on level 5), a **Release** list picks the release shown; every edit goes to all of them, a move keeping the difference and a typed number setting the same value, and saving writes the config blocks back. The table size is shown with what limits it: level 1 has about 870 bytes before the map, and level 5 must change `font_filler` in level5.s by the opposite amount. The game has room for 10 bad guys at a time.
- Undo and redo (Ctrl+Z, Ctrl+Y) for both, zoom, **Save map** and **Save source** (Ctrl+S). Only the map and the tile table change in the map file, and only `spawn_table`, `spawn_singles` and `checkpoint_starts` in the source; the rest is kept as it was.

To play an edited map or source, put the map in place of the unpacked file (`retail_1disk_speedlock/unpacked`) and the source in place of level1.s or level5.s, run [build.cmd](build.cmd), and run `2mb-file-version/batman.prg` (or [build-512.cmd](build-512.cmd) for the 512K version).

## Picture converter

Folder `tools/picconv`. Converts the loading pictures (title.pic, level1.pic .. level5.pic) to BMP and back, to edit them in any paint program.

| File | Contents |
|---|---|
| [picconv.py](tools/picconv/picconv.py) | Python 3: `python picconv.py tobmp picture.pic picture.bmp [level]`, `python picconv.py topic picture.bmp picture.pic [-2disk]`. |
| [picconv.go](tools/picconv/picconv.go) | The same in Go (1.21 or later): `go run picconv.go ...`. |

The pictures are 320 x 200 in 16 colours, in two formats:

| Release | Format |
|---|---|
| 1 disk reissue, budget | Tiny: resolution byte, palette, control bytes and data words, the words going down the screen in columns |
| 2 disk release | a marker word, the length, then the screen words where marker, word, count repeats a word; no palette in the file: the loader's for that level is used (give the level number, or keep the name levelN.pic) |

`topic` writes Tiny, or the 2 disk format with `-2disk`. The BMP must be 320 x 200 with 4 or 8 bits a pixel and use colours 0-15 only; its first 16 colours become the picture's palette (ST colours, 0-7 a channel). Converting a picture to BMP and back gives every picture of the game back byte for byte, but for the reissue's title.pic, whose last, unused word differs.

## Scenes

What is in memory together:

| Scene | Modules | Entry |
|---|---|---|
| front | panel.gfx panel.bin sound.prg + frontend.bin frontend.gfx | `$20000` / `$20004` |
| level1 | resident + level1.bin level1a.gfx level1b.gfx level1.map | `$2200` |
| level2 | resident + level24.bin level24.gfx level2.gfx | `$2200` |
| level3 | resident + level3.bin | `$28000` |
| level4 | resident + level24.bin level24.gfx level4.gfx | `$2202` |
| level5 | resident + level5.bin level5a.gfx level5b.gfx level5.map | `$2200` |

A level leaves through the jmp table at `$200` (jmp `$1000` + 4n): 0 the front end after a level (it shows game over / well done), 1..5 level 1..5.

## 512K and 1 MB

The game runs on a 512K ST. Only levels 2 and 4 look for more memory (`detect_1mb` in level24.s, all versions), and only to move the road sprites more smoothly from side to side.

- At level start the sprite sets are unpacked in nine sizes, most likely the sizes an object goes through as it comes nearer. Each size has eight horizontal positions 2 pixels apart; a position either gets its own pre-shifted copy of the graphics or uses the unshifted graphic.
- `detect_1mb` writes 256 values to `$88888` and reads each back; a mismatch or a bus error means 512K, and that path also sets colour 0 to white.
- On 512K the shift lists leave many positions without a copy, so the smaller sprites move in coarse steps. With 1 MB other lists give almost every position its own copy, and the second list is unpacked at `$80000`. Small and mid sized sprites gain the most: some have no copies on 512K and 3 to 6 with 1 MB.

| | 512K: shift_list_4, 5, 7, 8, 9 | 1 MB: shift_list_10, 11 |
|---|---|---|
| Plain sprites | 17 to 32 copies per set | 45 copies per set |
| Masked sprites | 14 to 23 copies per set | 51 copies per set |

Ranges, the same in every version (see the memory maps in loader.s):

| | Level 2 | Level 4 |
|---|---|---|
| First list | `$30690`-`$3acdb` | `$37448`-`$41a93` |
| 512K list | `$3acdc`-`$6af9f` | `$41a94`-`$6b769` |
| 1 MB list | `$80000`-`$de79f` | `$80000`-`$e9491` |

The 512K lists end just under the panel at `$6b800`. With 1 MB the 512K range stays free.

## Memory maps

The top of loader.s carries a scene by scene map of the 512 K for each version (modules, screens, buffers, stacks and what is free). The budget release keeps its sector loader and Pack-Ice depacker at `$6f950`-`$6ff1b`, in the sound driver's sample buffer, which no tune or sound effect uses, and its reset handler at `$300`.

## Reading the sources

Every routine, branch target and variable is named for what it does or holds, and `unused_` marks code that nothing calls. A few level 2/4 tables still carry their address (`tab_` table, `dat_` data) because their use is not known yet. `; from:` lists the routines or modules that refer to a label. Symbols of other modules in the same scene are equ'd at the top of each file. level1.s and level5.s also name their level's numbers there and use the names in the code:

- the map: `MAP_ROW_LENGTH` and `MAP_ROWS`, the tile types (`TILE_OPEN`, `TILE_FLOOR`, `TILE_LADDER`, and level 5's `TILE_DEADLY`), the floor ranges and `TILE_CACHE_SLOTS`;
- `LEVEL_TIME` (`$900` = 9:00 on level 1, `$1200` = 12:00 on level 5, in BCD) and `LEVEL_TUNE`, the level's music;
- `SPAWN_OFFSET_X`, what an object's x gets when it appears (`$50` on level 1, 8 on level 5);
- the places the code fixes: the vat at x `VAT_SPLASH_X` (`$5e0`, where Jack's splash is drawn) and y `VAT_DEPTH` (`$d4`, where his fall ends); `CLIMB_COLUMN_ROWS` (10 map rows from `map_climb_column`, column 58 of row 0: level 5's rope ladder); `ENDING_SCROLL_X` (level 5's ending pans the view until scroll_x gets to `$240`; 0 on level 1); `SCROLL_Y_LIMIT`, the lowest the view scrolls, worked out from `MAP_ROWS`;
- the addresses the code uses outside itself: the map file's parts (`MAP_START`, `map_tiles`, `TILE_TABLE`, `TILE_REFS` and `TILE_SLOTS` in its work space, `TILE_CACHE` after its `MAP_BLOCK_COUNT` blocks), the graphics files (`GFX_A`, `GFX_B` and their block graphics), the sprite tables (`SPRITE_HEADERS`, `SPRITE_PACKED`, `SPRITE_DATA`, `SPRITE_SHIFTED`), the screens (`SCREEN_FRONT`, `SCREEN_BACK`), `STACK_TOP`, and the loader's entries (`LOADER_FRONT_END`, and `NEXT_SCENE`, the one the level ends in: level 2 after level 1, the front end after level 5);
- the other numbers the two levels differ in: the map row strides (`MAP_ROW_LENGTH-18` and so on), the sprite counts (`SPRITE_HEADER_COUNT`, `SPRITE_COUNT`) and sprite bases (`JACK_SPRITE`, `SPLASH_SPRITE`, `CLIMB_SPRITE`, `LANDED_SPRITE`, `BULLET_SPRITE`).

The code of the two levels then differs only where the levels really do something else, such as level 5's goons checking the floor every 4 units when they walk left. Levels 1 and 5 run the same engine and each file holds all of its routines. Code that is Jack Napier's, run by level 1 only, has his names in both (`jack_start`, `jack_wait`, `vat_watch`, `vat_splash` ...); the boss climb code, run by level 5 for the Joker, is named for a boss in both (`boss_climb`, `boss_climb_watch`, `climb_column_animate`). A routine a level never runs says "Never run on level N" in its comment. The end texts are each level's own: `jack_dead_text` and `joker_lives_text` on level 1, `end_text` and `end_blank_text` on level 5. The objects (`spawn_table`, `spawn_singles`) and where the player starts (`checkpoint_starts`) are one group or object a line, with each object's routine named and a comment above them that describes the tables.

level24.s names what levels 2 and 4 start with (`LEVEL2_DISTANCE` 999 in 5:00, `LEVEL4_BALLOONS` 100 in 3:20, and the half way restarts) and the vehicles' speeds (`BATMOBILE_TOP_SPEED`, `BATWING_TOP_SPEED`, `BATWING_MIN_SPEED` and their steps); loader.s names the game track format (`TRACK_BYTES`, `TRACK_SYNC`, `ESCAPE_BYTE`, and the 2 disk release's `CHECKSUM_SET` and `CHECKSUM_MASK`), the decryption keys (`DECRYPT_KEY0`, `DECRYPT_KEY1`) and `PICTURE_SCREEN`, and writes the FORM HUFF chunk names as `'CODE'`, `'SIZE'`, `'TREE'` and `'HUFF'`.

Long runs of data are incbin'd from `data/` (8.3 names: two letter module code ld lo pn sn fe l1 l2 l3 l5, then what it holds, e.g. pn_ebar.bin, l3_items.bin; the label above each incbin line describes it). font.bin is the font every module has, one file for all of them. `data/` holds the blocks all versions have; `data/2disk_rt` holds those only the 2 disk release has, and `data/1disk_rt` and `data/1disk_bu` would hold those only the reissue or only the budget release has (there are none now).

## File version on a floppy (not an official release)

Folder `512-file-version`. **Ocean never released this.** I made it as an example of a file loader: the 1 disk retail reissue run from its files on a normal TOS floppy instead of its SpeedLock disk, on any ST with 512K or more. The game's code and files are the reissue's; only its loader is changed, in memory, when it starts.

| File | Contents |
|---|---|
| [batman.s](512-file-version/batman.s) | The program (Devpac source). |
| `batman.prg` | batman.s assembled. |
| `loader.bin` | The reissue's decrypted game loader, incbin'd by batman.s (loadstub.s and loader.s built). |
| `files/` | The reissue's 24 game files, packed with Pack-Ice 2.40 by `tools/icepack`. |
| `batman.st` | A 720K floppy image with batman.prg (in the root and in AUTO) and the files, as they were made from the original files. |

[build-512.cmd](build-512.cmd) in the top folder remakes loader.bin, `files/` and batman.prg from the sources; it does not remake batman.st.

**Why it needs its own reader:** the game overwrites TOS's memory, so GEMDOS cannot load files once the game runs. batman.prg finds the files while TOS still runs and gives the game a reader that uses the floppy controller itself.

### What batman.s does, in order

1. Shows its title: the screen fades to black with the text in white, it waits for a key, and the text fades out.
2. Reads the boot sector, FAT and root directory of drive A with BIOS Rwabs. It finds the 24 files and follows each one's clusters through the FAT, so it knows which sectors hold each file. A file does not have to be in one piece.
3. Copies the reissue's game loader and changes it in memory, all inside the 4 KB the loader keeps for the whole game (`$1000`-`$1fff`):
   - each load table entry points to its file's sectors and holds its destination, its length and a delay;
   - `load_file` becomes a jump to a new sector reader, which goes in the zero padding at the end of the loader (`$1d14`-`$1fb3`); the lists of sectors go over the rest of the old track reader (`$1514`-`$160d`);
   - the FORM HUFF unpacker makes way for the Pack-Ice 2.40 depacker, the one that comes with Pack-Ice (by Axe of Superior), over the Huffman tree work area (`$1914`-`$1d13`).
4. Starts the loader at `$21000`, as the SpeedLock boot does. From here on the game runs as from its own disk.

### Each time the game loads a file

The new reader:

- waits about 2.4 seconds when the file comes after a loading picture, so the picture can be seen as it was while the original disk loaded;
- reads the file's sectors with its own FDC and DMA code, a track side at a time, and the last sector through `$70000` so that nothing after the file is written;
- tries a read that fails again after a restore to track 0, as the old loader did.

The game then unpacks the file where it was loaded, and the 31 bytes after it are cleared, as the reissue's own unpacker does. The depacker keeps the 120 bytes after the file on the stack while it works, 196 bytes of stack in all.

### Limits

The files must be in the root directory of the disk in drive A; it does not work from a hard disk. Before the game starts it stops with a message (and goes back to the desktop after a key) if drive A has no TOS disk, the disk cannot be read, a file is missing, or the files are in too many pieces.

## 2 MB file version (not an official release)

Folder `2mb-file-version`. Like the file version on a floppy, **Ocean never released this**: I made it as a second example of a file loader, a simpler one. It runs the 1 disk retail reissue from its unpacked files on an ST with 2 MB or more, from any drive: a hard disk, an emulator's GEMDOS drive, or a floppy with room for the files.

| File | Contents |
|---|---|
| [batman.s](2mb-file-version/batman.s) | The program (Devpac source). |
| `batman.prg` | batman.s assembled. |
| `loader.bin` | The reissue's decrypted game loader, incbin'd by batman.s (loadstub.s and loader.s built). |
| `files/` | The reissue's 24 game files, unpacked: the code files built from the sources, the rest from `retail_1disk_speedlock/unpacked`. |
| `batman.st` | An 800K floppy image (80 tracks, 2 sides, 10 sectors a track) with batman.prg (in the root and in AUTO) and the files in FILES, as they were made from the original files. |

The files are not packed, so together they take 778754 bytes: more than a 720K floppy holds, but an 800K one (10 sectors a track) takes them with 5 KB to spare. On a hard disk or an emulator's GEMDOS drive, copy the folder (batman.prg with `files/` beside it) and run batman.prg from there. [build.cmd](build.cmd) (or [build-2mb.cmd](build-2mb.cmd)) remakes the files, loader.bin and batman.prg from the sources (not batman.st), which makes this the version to test edits with.

**Why it works:** the game never uses the second megabyte (`$100000` on). Levels 2 and 4 use `$80000`-`$e9491` when they find more than 512K, and a 2 MB ST keeps its screen at `$1f8000`. So all the files fit between, loaded with GEMDOS before the game starts.

### What batman.s does, in order

1. Shows its title: the screen fades to black with the text in white.
2. Takes the largest free block of memory from GEMDOS and checks that it covers `$100000`.
3. Loads the 24 files one after another from `$100000` on (Fopen, Fread, Fclose), a dot on the screen for each. They end at about `$1be202`.
4. Waits for a key and fades the text out.
5. Copies the reissue's game loader and changes it in memory:
   - each load table entry holds the file's address in the second megabyte, its destination, its length and a delay;
   - `load_file` becomes a copy: wait out the delay, then copy the file to its destination;
   - `unpack_file` only clears the 31 bytes after the file, as the reissue's own unpacker does, as the files are not packed.
6. Starts the loader at `$21000`, as the SpeedLock boot does.

The load table entry, as `load_file` gets it in d0-d4:

| Long | Holds |
|---|---|
| d0 | the file's address in the second megabyte (from `$100000`) |
| d1 | its destination |
| d2 | its length |
| d3 | the delay: about 2.4 seconds after a loading picture, else 0 |
| d4 | the entry's own destination, which the loader keeps using |

### Limits

It stops with a message (and goes back to the desktop after a key) if the ST has less than 2 MB, a file is missing or cannot be read.

## Pack-Ice packer

Folder `tools/icepack`. My own packer, written so that the files can be packed on a PC instead of running Pack-Ice under an emulator. It writes byte for byte what Pack-Ice 2.40 (ICE_2_4.PRG) writes for a data file with its standard settings, and with `-2.31` the older Pack-Ice 2.31 format of the budget release.

| File | Contents |
|---|---|
| [icepack.py](tools/icepack/icepack.py) | The packer in Python 3: `python icepack.py [-2.31] source target`. |
| [icepack.go](tools/icepack/icepack.go) | The same in Go (1.21 or later): `go run icepack.go [-2.31] source target`. |
| [python-pack.cmd](tools/icepack/python-pack.cmd), [go-pack.cmd](tools/icepack/go-pack.cmd) | Pack the reissue's 24 files (`retail_1disk_speedlock/unpacked`) into `512-file-version/files` with icepack.py or icepack.go. |

[build-512.cmd](build-512.cmd) in the top folder packs the files built from the sources instead.

With `-2.31`, given the budget release's unpacked files (`budget_1disk/unpacked`), it writes the budget release's packed files (`budget_1disk/packed`) back byte for byte. Those differ from the reissue's files only after the data: each has the 31 bytes its loader clears, and a few files end in other unused bytes.

Pack-Ice parses a file from its start: at each position the longest match whose source lies after it, within a 5504 byte window, the nearest of those, or else a literal byte; the depacker meets them in the opposite order, from the end of the file. Pack-Ice 2.40 adds runs of one byte and writes its bits a byte at a time instead of a long at a time, which packs the reissue's files 769 bytes smaller than 2.31. icepack.py describes both formats and the rules in full.
