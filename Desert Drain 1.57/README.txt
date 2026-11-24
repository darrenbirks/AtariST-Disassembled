Desert Drain 1.57 - GFA BASIC source
====================================

DS_DRAIN.PRG, "Desert Drain" 1.57 (09.94) by Volker Hemsen, a 680x0 disassembler for the Atari ST, STE and TT
with its own source editor.  It loads a program (whole or a part, with its DRI/GST symbols), a routine, an area of
RAM or ROM, a GEM resource file or a data file, disassembles 68000 to 68040 and FPU code into an editor window,
with labels, DATA areas in the TEXT, symbol names and the names of GEMDOS, BIOS, XBIOS, AES and VDI calls and
system variables, and saves the source as ASCII for an assembler.  It needs DS_DRAIN.RSC; DS_DRAIN.INF holds its
settings, DS_HILFE.TXT its help.

Decompiled by Darren Birks, 24 November 2026, with GFA Decompiler.

DS_DRAIN.PRG        The program as distributed (English).
DS_DRAIN.GFA        The GFA BASIC 3 source, as the GFA BASIC editor saves it, with its texts in German (see below).
DS_DRAIN.LST        The same source as text, for reading.
DS_DRAIN.PAT        The bytes of DS_DRAIN.PRG that no source line gives: the English translation, the patched
                    library and the program flags.
*.bin               The data of the INLINE lines (machine code: VDI text output, a bit field, USERDEF drawing,
                    the Line-A init; a 60-byte buffer), each named after its INLINE variable.
DS_DRAIN.names      The names given to every procedure, function, label and variable.
DS_DRAIN.comments   The comments in the listing.

Every procedure, function, label and variable is named for what it is, every procedure has a header saying what
it does, its parameters and what it sets, and the steps of the code carry comments: the resource's trees and
objects, the dialogs, the window handling, the loaders and file formats, the instruction decoder line by line and
the effective-address and operand texts.  Things in the original program that look unintended (values never set,
routines never called, a few wrong mnemonics and decodings) are noted in the comments and left as they are.


Building
--------
The program was compiled with a GFA BASIC Compiler 3.03 D whose code generator is 3.03 E's: its FUNCTIONs with
$F% extend a word result to a long before their rts, which the 3.03 D compiler gfadec has does not.  No copy of
that build has been found; gfadec's "3.03 D late synthetic" is 3.03 E's compiler with 3.03 D's linker and library,
and compiles the source to the same code.

The program as distributed, byte for byte:

    gfadec -compile DS_DRAIN.GFA DS_DRAIN.PRG -compiler "3.03 D late synthetic" -patch DS_DRAIN.PAT

The program as it was compiled, before its translation (German texts, German error texts, the library unpatched):

    gfadec -compile DS_DRAIN.GFA DS_DRAIN.PRG -compiler "3.03 D late synthetic"

Use DS_DRAIN.GFA for these builds: it keeps the order of the names in the program's name lists, which decides
where every variable is stored.  DS_DRAIN.LST compiles too, but its variables end up in a different order.


The translation
---------------
Desert Drain was written and compiled in German; the earlier versions (1.41, 1.46, 1.52 on the Atari Journal,
PD-ATS, Floppyshop and Poolware disks) are German throughout.  The English 1.57 is the German compile with its
texts translated in the program file afterwards: every English text sits in the room of its German one, padded
with spaces or NUL bytes to the same length ("Clear file   " for "Datei löschen", "[3][|Defective|RSC file!][ End ] "
for "[3][|Defekte|RSC-Datei! ][ Ende ]"), and the library's error texts are translated the same way ("Division by
zero   " for "Division durch Null").

The source therefore has the German texts, as the compiler had them.  The program shows how: the compiler keeps
every string constant once, and a string that is part of one already stored is taken from there.  The English
program stores "lea", "not" and "and" again although "Clear file" and other texts hold them, so they were not
there when it was compiled; and "or " and "am " in the mnemonic tables were "ori" and "rte", taken from the German
texts "[3][Der Editorinhalt|..." and another: the translation of those texts overwrote the mnemonics too, which
is why the English Desert Drain shows $4E73 as "am " and ori as "or ".

The German texts come from the same lines of Desert Drain 1.52 where it has them (40 texts).  Where 1.57 has a
text 1.52 does not, the German is written to the English text's length and to the strings the compiler takes from
it: "[3][Der Editorinhalt|wurde noch nicht|gespeichert!][Beenden|Zurück]" holds the "ori" the mnemonic table
takes at the same place.  The other texts no 1.52 line gives are left in English, which compiles the same.

DS_DRAIN.PAT then writes the English bytes over the German compile, each run with what it is:

    $1e72d: ...  ; translation: "Locate the r" for "Wo ist die R"
    $1efee: ...  ; error texts translated: "by zero   ..." for "durch Null..."

and the program's other changes:

  * the program flags (byte $19: fast load and TT-RAM bits), which the linker does not write;
  * the patched GFA3BLIB, made for graphics cards: INIT.O's Line-A init ($a000) made nop, INITAES.O's
    calls of Hidem and QShowm around every VDI and AES call made bra.s *+4, HIDEM.O's Hidem and Showm made rts
    throughout, and DEFXXX.O's clip to the Line-A screen size made bra.s *+4.

Decompiling DS_DRAIN.PRG again (gfadec DS_DRAIN.PRG -inline -names DS_DRAIN.names -comments DS_DRAIN.comments)
gives the named source with the English texts the program holds.
