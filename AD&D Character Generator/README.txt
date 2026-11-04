Advanced Dungeons and Dragons Unofficial Character Generator - GFA BASIC source
================================================================================

DND_44.PRG, the "Advanced Dungeons and Dragons UNofficial Character Generator Program for the Atari ST" by
Christopher Allen Pelton (CompuServe 74706,1155, GEnie CAPELTON; public domain).  It creates AD&D characters:
rolls the abilities, takes the player through sex, race, class, alignment and social class, works out the derived
values (hit points, saving throws, thief skills, spells, age, money), lets the character buy equipment from the
store's price lists, and prints a character sheet.  Medium or high resolution.

DND_44.BAS      The GFA BASIC 2.0 source, as the GFA BASIC editor saves it.
DND_44.LST      The same source as text, for reading.

Every variable, procedure, function and label is named for what it is, every procedure has a header saying what
it does, and the statements carry a comment (after !) with what they mean.  The DATA lines at the end are the
program's tables (races, classes, saving throws, alignments, ability tables, spell lists and the twelve price
lists); each table has a header giving its records field by field.


Building
--------
Compiled with the GFA BASIC Compiler 2.02 US, with the options

    Stop    never
    Trapv   on
    Errors  as texts
    Bombs   on

DND_44.BAS gives DND_44.PRG byte for byte.  The 2.02 GB compiler gives the same program except for the version
text in the runtime's error alerts ("GFA BASIC Version 2.02 GB" in place of "... 2.02 US").

Use DND_44.BAS for the byte-for-byte build: it keeps the order of the names in each of the program's name lists,
which decides where every variable is stored and the bytes the compiler pads odd-length strings with.  DND_44.LST
is for reading.


Notes on the program
--------------------
Things the code does that look unintended, kept as they are:

  * The saving throw table is read one place out: the count before it (6) is used both for the category names and
    for the class groups, but only five names are there, so each saving throw is read one place early.
  * The class ON ... GOSUB has no procedure for the monk (its entry is 0), so set_up_monk is never called.
  * two_language_race_group% is never given a value, so its part of the extra languages test can never be true.
