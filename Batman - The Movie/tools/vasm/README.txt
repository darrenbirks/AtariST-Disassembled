vasm
====

vasmm68k_mot.exe is vasm 1.8i for Windows, the 68000 version with Motorola syntax, by
Volker Barthelmann and Frank Wille.  It assembles the sources here byte for byte like
the original files; build.cmd and build-all.cmd in the top folder use it.

  vasmm68k_mot -devpac -m68000 -Fbin -quiet -o level1.bin level1.s

  -devpac    Devpac compatible: the sources are written for Devpac
  -m68000    68000 code only
  -Fbin      a plain binary, without a header: the file as the game loads it,
             after its 4 byte load address
  -quiet     no banner

vasm.pdf is vasm's manual (from http://www.ibaug.de/vasm/doc/vasm.pdf, April 2022,
a little newer than this vasm, so a few options in it may be missing here).  Its
"Legal" section has the licence: vasm may be passed on unchanged for
non-commercial use, and the files it makes may be used without restriction.
vasm's pages, with its source, are at http://www.compilers.de/vasm.html .
