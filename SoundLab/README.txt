Sound Lab 1.1 - GFA BASIC source
================================

SOUNDLAB.PRG, "Sound Lab 1.11, July 28, 1993" by Damien M. Jones, a shareware sample editor for the Atari ST and
STE.  It loads and saves AVR, SPL, SAM, SMP, SND and WAV samples, records from a cartridge sampler, plays through
the YM2149 or STE DMA sound, and edits blocks, loops, echo, fades, volume, rate conversion and stereo to mono.  It
runs in medium or high resolution, from the desktop or the AUTO folder, with its own dialogs, menus, file selector
and mouse driver.  It needs SOUNDLAB.COL (colour) or SOUNDLAB.MON (monochrome) beside it.

Decompiled by Darren Birks, 24 November 2026, with GFA Decompiler.

SOUNDLAB.PRG        The program as distributed (with the hand patch described below).
SOUNDLAB.GFA        The GFA BASIC 3.5 source, as the GFA BASIC editor saves it.
SOUNDLAB.LST        The same source as text, for reading.
SOUNDLAB.PAT        The hand patch: the two bytes of SOUNDLAB.PRG that no source line gives.
*.bin               The data of the 33 INLINE lines (machine code, fonts, mouse forms, icons, volume tables ...),
                    each named after its INLINE variable.  The .GFA holds them too; the .LST reads them from here.
SOUNDLAB.names      The names given to every procedure, function and variable.
SOUNDLAB.comments   The comments in the listing.

Every procedure, function and variable is named for what it is, every procedure has a header saying what it does,
its parameters and what it sets, and the steps of the code carry comments.  The INLINE machine-code routines are
described where they are set up (program_init) and where they are called.  Things in the original program that
look unintended (values never set, routines never called, a wrong timer value for 10971 Hz ...) are noted in the
comments and left as they are.


Building
--------
The program was compiled with the GFA BASIC Compiler 3.5E (English) and linked with its GFA3BLIB.

The original program, as Damien M. Jones compiled it:

    gfadec -compile SOUNDLAB.GFA SOUNDLAB.PRG -compiler "3.5E E"

The program as distributed (hacked), with the hand patch written over the compile:

    gfadec -compile SOUNDLAB.GFA SOUNDLAB.PRG -compiler "3.5E E" -patch SOUNDLAB.PAT

The first gives the unpatched original byte for byte; the second gives the distributed SOUNDLAB.PRG byte for
byte.  The two differ only in the two bytes at file offset $1776A.

Use SOUNDLAB.GFA for these builds: it keeps the order of the names in the program's name lists, which decides
where every variable is stored.  SOUNDLAB.LST compiles too, but its variables end up in a different order, so the
program is not byte for byte the same.

The named source can be made again from the program with

    gfadec SOUNDLAB.PRG -inline -names SOUNDLAB.names -comments SOUNDLAB.comments

and gfadec SOUNDLAB.PRG -restore -verify saves the unpatched original as SOUNDLAB.RES and checks that the
source compiles to it.


The hand patch
--------------
Sound Lab is shareware: while the main screen runs, its Shareware form (dialog 27, with the serial number) comes
up again and again, first as soon as the main screen is up, then after 5 minutes, each wait 10% shorter than the
last.  The test is in dialog_run:

    IF nag_deadline%<TIMER AND tour_active!=FALSE
      dialog_run(27,choice&)
      nag_interval%=nag_interval%*.900000000000002
      nag_deadline%=nag_interval%+TIMER
    ENDIF

(tour_active! is TRUE while the help tour plays itself, which the form must not interrupt.)

The compiler loads the boolean tour_active! as

    moveq   #0,d0
    tst.b   tour_active(a5)
    beq.s   *+4             ; $6702: FALSE, d0 stays 0
    moveq   #-1,d0          ; TRUE

In SOUNDLAB.PRG the beq.s has been overwritten with a second moveq #-1,d0 ($70FF), after compiling:

    moveq   #0,d0
    tst.b   tour_active(a5)
    moveq   #-1,d0          ; $70FF in place of the beq.s
    moveq   #-1,d0

so tour_active! always reads as TRUE in this test, tour_active!=FALSE is never true, and the Shareware form never
comes back.  No source line compiles to these instructions, so the source keeps the line as it was written and
SOUNDLAB.PAT holds the patch:

    $1776a: 70ff  ; hand patch: moveq.l #-1,d0 in place of beq.s $17752

($1776A is the offset in the file; $1774E, 28 bytes less, is the address in the program's code.)
