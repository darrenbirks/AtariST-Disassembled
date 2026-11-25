Ultimate Virus Killer 2000 9.0 - GFA BASIC source
=================================================

Ultimate Virus Killer 2000, version 9.0, by Richard Karsmakers.  Released 12 April 2004 by C.R.I.M.E. Development
as shareware ("you can decide for yourself how much"), for the Atari ST, STE, TT, Mega ST, Mega STE, Stacy and
Falcon; http://www.uvk2000.com.  It was the last release of the Atari ST virus killer and boot sector restorer.  It
finds memory resident and link viruses and known resident programs, diagnoses boot sectors (viruses, anti-virus
boot sectors, immunized and known disks), and writes the original boot sector back to the disks it knows.

Decompiled by Darren Birks, 30 October 2026.


Credits
-------
Ultimate Virus Killer 2000      written by Richard Karsmakers (C.R.I.M.E. Development).  The program, its design,
                                its texts and its virus and boot sector database are all his work.
FlyDials                        the shareware library of dialog routines UVK draws its dialogs with, written by
                                Gregor Duchalski (module_address.S).
System Status memory check      written by H.W.A.M. de Beer, the author of SysInfo (ram_probe_routine.S).
Atomik 3.5 depacker             Atomik is by Altair (VMAX/MCS) (depack_routine.S).
GFA BASIC 3.6                   GFA Systemtechnik GmbH, whose compiler and runtime library UVK is built with.

This source is a reconstruction for study and preservation.  All rights in Ultimate Virus Killer remain with
Richard Karsmakers.


Files
-----
UVK.GFA         The GFA BASIC 3.6 source of the whole program, as the GFA BASIC editor saves it, with the INLINE
                data in place.
UVK.LST         The same source as text (the editor's Save,A format, Atari character set), for reading.
*.bin           The INLINE data, one file per INLINE line, named after its variable: the machine code modules the
                program CALLs, the numbered text tables and UVK's GEM resource file.  UVK.GFA holds the same bytes;
                a merged UVK.LST needs each one loaded into its INLINE line.
*.S             Devpac sources of the six machine code modules, each assembling to its .bin byte for byte:
                  depack_routine.S            the Atomik 3.5 depacker
                  find_disk_driver_routine.S  the search for a reset-resident program in memory
                  find_text_routine.S         the lookup of a text by number in UVK's text tables
                  module_address.S            the FlyDials GEM dialog module
                  pattern_match_routine.S     the 8-byte pattern compare
                  ram_probe_routine.S         the RAM size probe

Every variable, procedure, function and label is named for what it is, every procedure has a header saying what
it does, and the statements carry a comment (after !) with what they mean.  The DATA lines at the end are UVK's
signature tables; each table has a header giving its records field by field.


Building
--------
Compiled with the GFA BASIC 3.6TT compiler (GFA_BCOM) and linked with GL, UVK.GFA gives UVK's program byte for
byte, relocations included.  The released UVK_9_0.PRG is that program packed.

Link it with a copy of the 3.6TT GFA3BLIB in which the two Line-A calls of the mouse routines, $A00A (hide the
mouse) at library offset $6C82 and $A009 (show the mouse) at $6CB6, are each replaced with a nop ($4E71), as they
are in UVK's runtime.  The unpatched library gives the same program except for those two words.

Only UVK.GFA keeps the variable order the byte-for-byte build needs; UVK.LST merged into the editor gives a
working program that can differ from it.  The unused names in the source are there for the same reason: they keep
the compiler's choices the same as in UVK.

The module sources are plain Devpac syntax; local labels start with a dot.  Where Devpac would choose a different
encoding from the one in UVK (cmp, add and and with an immediate in the register form), the instruction is written
as dc.w with the instruction in the comment.
