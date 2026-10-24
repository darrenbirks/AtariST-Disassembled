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
| `disk1/`, `disk2/` | The game files of each disk, as loaded. They are not packed, so there is no `packed/` and `unpacked/` (pictures are run length packed, decoded by `load_picture` in loader.s). |
| `speedlock/` | The boot stages up to the game loader, as Devpac sources: `bootsect.s` (track 0 sector 1), `protect.s` (track 1 sectors 5-7, decryptor and timing check), `layer3.s` (track 1 sectors 8-10, third layer, loads and decrypts loader.bin). `.bin` = sectors as on the disk, `.dec` = decrypted, what each source assembles to. `pseudo_c.txt` = C pseudocode of all of it. |

### 1 disk retail reissue (SpeedLock)

Folder `retail_1disk_speedlock`. The reissue on 1 disk, after the 2 disk release, SpeedLock protected.

| Path | Contents |
|---|---|
| `loader.bin` | The decrypted game loader: the stub at `$21000` and the code that runs at `$1000` (loadstub.s, loader.s). |
| `packed/`, `unpacked/` | The 26 files as on the disk (FORM HUFF) and unpacked. The file table (tracks, lengths, load addresses, names) is at the top of loader.s. |
| `speedlock/` | As above, for this version. |

### 1 disk budget release (The Hit Squad)

Folder `budget_1disk`. No protection, a standard 10 x 512 byte sector disk of which only side 0 is used. The files are Pack-Ice 2.31 packed; most likely made from a cracked copy of the reissue (see below).

| Path | Contents |
|---|---|
| `loader.bin` | The 4 KB game loader stage 3 copies to `$21000`: the reissue's, with `load_file` calling the sector loader at `$6f950` (loadstub.s, loader.s). |
| `packed/`, `unpacked/` | The 26 files as on the disk and unpacked: the reissue's unpacked files, each with 31 bytes more (only the tails differ). |
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
- **acid_animate, levels 1 and 5:** the acid surface alternates map words `$6bc6`/`$6cc7` on the 2 disk release and `$6bc6`/`$6ac5` on the reissue (the map file is the same). The frame counter computed into d2 is overwritten in both.
- **Level 5 spawn_table:** the type 31 object (`vat_countdown`) at x 460 is at y 56 on the 2 disk release, y 64 on the reissue.

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

The data files are left as they are: `retail_1disk_speedlock/unpacked` and `budget_1disk/unpacked`, and for the 2 disk release `retail_2disk_speedlock/disk1` and `disk2`, with one level1.gfx / level5.gfx from `$50000` each.

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

Every routine, branch target and variable is named for what it does or holds, and `unused_` marks code that nothing calls. A few level 2/4 tables still carry their address (`tab_` table, `dat_` data) because their use is not known yet. `; from:` lists the routines or modules that refer to a label. Symbols of other modules in the same scene are equ'd at the top of each file.

Long runs of data are incbin'd from `data/` (8.3 names: two letter module code ld lo pn sn fe l1 l2 l3 l5, then what it holds, e.g. fe_font.bin, pn_ebar.bin, l3_items.bin; the label above each incbin line describes it). `data/` holds the blocks all versions have; `data/2disk_rt` holds those only the 2 disk release has, and `data/1disk_rt` and `data/1disk_bu` would hold those only the reissue or only the budget release has (there are none now).
