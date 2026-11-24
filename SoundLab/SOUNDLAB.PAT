; SOUNDLAB.PAT: the bytes of SOUNDLAB no source gives, written over a compile of SOUNDLAB.GFA
; gfadec -compile SOUNDLAB.GFA SOUNDLAB.PRG -compiler "3.5E E" -patch SOUNDLAB.PAT
; file offset: bytes  ; what they are
$1776a: 70ff  ; hand patch: moveq.l #-1,d0 in place of beq.s $17752
