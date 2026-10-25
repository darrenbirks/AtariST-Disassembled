"""Pack-Ice packer: packs data files as the Atari ST packer Pack-Ice does.

Written by Darren Birks in October 2026.

usage: python icepack.py [-2.31] source target

Packs the file source into the file target in the Pack-Ice 2.40 format, which the
in-place depacker that comes with Pack-Ice 2.40 (ICE_UNP2.S) unpacks.  The output is
byte for byte what Pack-Ice 2.40 (ICE_2_4.PRG) writes for a data file with its
standard settings.

With -2.31 it packs in the older Pack-Ice 2.31 format ('Ice!'), byte for byte as
Pack-Ice 2.31 writes it.

Both formats
------------
A packed file is

    magic  <packed length: the whole file>  <unpacked length>  <data>

with magic 'ICE!' (2.40) or 'Ice!' (2.31).  The depacker reads the data from its end
backwards and writes the output from its end backwards.  The data is one stream of bits
and literal bytes, in the order the depacker reads them going down:

  - Bits come in bytes (2.40) or 32 bit longs (2.31).  The last one (first read) holds
    the first bits, followed by a 1 bit that marks where they end; every other one is
    full and read from its top bit down.  One is read when the depacker needs its first
    bit.
  - Literal bytes lie where the depacker reaches them, between the bytes or longs of
    bits, in the order they appear in the output.

The depacker repeats: a literal run (a 1 bit and its count, then the bytes), then a match
(unless the output is complete); or no literals (a 0 bit) and a match.  When the output
is complete it reads one more bit, which is 1 for a picture packed by planes; icepack
writes 0.

  literal count c:  1          10
                    2-4        11 xx            (xx = c - 2, not 3)
                    5-7        11 11 xx         (c - 5)
                    8-14       11 11 11 xxx     (c - 8, not 7)
                    15-269     11 11 11 111 x8  (c - 15, not 255)
                    270-33037  ... 11111111 x15 (c - 270)
  match length L:   2          0
                    3          10
                    4-5        110 x            (L - 4)
                    6-9        1110 xx          (L - 6)
                    10-1033    1111 x10         (L - 10)
  then the distance d, for 2.31:
                    L = 2      0 x6 (0-63) or 1 x9 (64-575)
                    L >= 3     10 x5 (0-31), 0 x8 (32-287) or 11 x12 (288-4383)
  or the offset d, for 2.40, one less than the field read as 2.31 reads it:
                    L = 2      0 x6 (-1-62) or 1 x9 (63-574)
                    L >= 3     10 x5 (-1-30), 0 x8 (31-286) or 11 x12 (287-4382)

A match copies L bytes from L + d bytes further up the output, so its source is output
already written, ending at least at the match itself; in 2.40 an offset of -1 instead
repeats the byte after the match L times.

The packing
-----------
Pack-Ice 2.40 parses the file from its start.  At each position q it looks at

  - the run: how many of the bytes after q are the same as the one at q, at most up to
    2 bytes before the end of the file or q + 1033;
  - the matches whose source starts after q (at s, the bytes both have in common, at
    most s - q of them) and ends before min(q + WINDOW, end of the file) - 1, nearest
    first; one replaces the match found so far only when it is longer.  A match longer
    than 1033 bytes is cut to 1033, its source moved up by as much, and one of 3 bytes
    or more must not have an offset over 4382.

The run wins when it is 2 bytes or more and at least as long as the match.  Otherwise
the match is taken, unless there is none or it is a 2 byte match with an offset over
574: then the byte at q is a literal.  The last 2 bytes are always literals.  Pack-Ice
writes its output in the buffer that holds the file, 2420 bytes before it; when the
output gets within 50 bytes of the part still to pack, the rest is stored as literals
(it checks after 2371 literals, then whenever that many literals have gone by as the gap
allowed).  This only happens to a file that does not pack.

Pack-Ice 2.31 parses the same way without runs: at each position it takes the longest
match whose source lies after it, the shortest distance of those, and a literal byte
when there is no match of 2 or more.  The source must end before the last byte of the
file and within WINDOW - 1 bytes of the match's start.  The stream ends with one 0 bit
more than the depacker reads.  These rules were worked out from files packed by
Pack-Ice 2.31, which -2.31 gives back byte for byte.
"""
import bisect, struct, sys

WINDOW = 0x1580     # the search window of Pack-Ice 2.40 (and of the 2.31 packing)
MAX_LENGTH = 1033
MAX_LITERALS = 33037


def key_positions(data):
    """2 bytes -> the positions they start at, in order."""
    where = {}
    for s in range(len(data) - 1):
        where.setdefault(data[s:s + 2], []).append(s)
    return where


#----------------------------------------------------------------------
# Pack-Ice 2.40
#----------------------------------------------------------------------

def pack_240(data):
    """The packed file, as ICE_2_4.PRG writes it."""
    n = len(data)
    out = bytearray(b'ICE!' + bytes(4) + struct.pack('>I', n))
    bits = [0, 7]           # the byte of bits being filled, and its free bits - 1

    def put(value, count):
        """The low count bits of value, the lowest first (the depacker reads them the
        other way round)."""
        byte, free = bits
        for i in range(count):
            byte = (byte >> 1) | (((value >> i) & 1) << 7)
            free -= 1
            if free < 0:
                out.append(byte)
                byte, free = 0, 7
        bits[:] = [byte, free]

    def put_literal_count(count):
        if count > MAX_LITERALS:
            raise ValueError('a literal run too long for Pack-Ice')
        for base, width, total in ((270, 15, 32), (15, 8, 17), (8, 3, 9), (5, 2, 6),
                                   (2, 2, 4), (1, 1, 2), (0, 1, 1)):
            if count >= base:
                put((-1 << width) | (count - base), total)
                return

    def put_offset(length, offset):
        code = offset + 1
        if length == 2:
            if code <= 0x3f:
                put(code, 7)
            else:
                put((code - 0x40) | 0x200, 10)
            return
        for base, width, total in ((0x120, 12, 14), (0x20, 9, 9), (0, 6, 7)):
            if code >= base:
                put((-1 << width) | (code - base), total)
                return

    def put_length(length):
        for base, width, prefix in ((10, 10, 4), (6, 3, 3), (4, 2, 2), (3, 1, 1), (2, 1, 0)):
            if length >= base:
                put((-1 << width) | (length - base), width + prefix)
                return

    where = key_positions(data)
    put(0, 1)               # not a picture: the last bit the depacker reads
    literals = 0
    guard = 0x942           # literals until the next look at the gap (a word)
    q = 0
    while True:
        # the run of the byte at q
        top = min(q + MAX_LENGTH, n)
        j = q + 1
        while j < top and data[j] == data[q]:
            j += 1
        run = j - q - 1 if j < top else top - q - 2
        # the longest match, nearest first
        limit = min(q + WINDOW, n)
        best_length, best_code = 1, 0
        positions = where.get(data[q:q + 2], ())
        i = bisect.bisect_right(positions, q)
        while i < len(positions) and best_length < MAX_LENGTH:
            s = positions[i]
            i += 1
            if s >= limit:
                break
            length = 0
            while data[q + length] == data[s + length] and q + length < s \
                    and s + length + 1 < limit:
                length += 1
            code = s - q - length + 1
            if length > MAX_LENGTH:
                code += length - MAX_LENGTH
                length = MAX_LENGTH
            if length <= best_length or (length > 2 and code > 0x111f):
                continue
            best_length, best_code = length, code
        if run > 1 and run >= best_length:
            best_length, best_code = run, 0
        if best_length == 1 or (best_length == 2 and best_code > 0x23f):
            out.append(data[q])
            q += 1
            literals += 1
            guard = (guard - 1) & 0xffff
            if guard & 0x8000:
                gap = 0x974 + q - len(out) - 50
                if gap < 0:
                    break
                guard = gap & 0xffff
        else:
            put_literal_count(literals)
            literals = 0
            put_offset(best_length, best_code - 1)
            put_length(best_length)
            q += best_length
        if n - q < 3:
            break
    out += data[q:]
    put_literal_count(literals + n - q)
    out.append(bits[0] | (1 << bits[1]))        # the end marker after the first bits
    struct.pack_into('>I', out, 4, len(out))
    return bytes(out)


#----------------------------------------------------------------------
# Pack-Ice 2.31
#----------------------------------------------------------------------

def parse_231(data):
    """The tokens from the start of the file: ('lit', count) and ('match', length, distance).

    At q a source s (s > q) allows a match of the bytes both have in common, at most
    s - q (the source starts after the match), end - s (the source ends before the last
    byte) and MAX_LENGTH; its distance is s - q - length.  The longest wins, the lowest
    source of equal ones; only sources that start with the same 2 bytes are looked at."""
    n = len(data)
    end = n - 1             # sources end before the last byte
    window = WINDOW - 1
    where = key_positions(data)
    tokens = []
    run = 0
    q = 0
    while q < n:
        best_length, best_source = 0, 0
        if end - q >= 4:
            positions = where.get(data[q:q + 2], ())
            i = bisect.bisect_left(positions, q + 2)
            while i < len(positions):
                s = positions[i]
                i += 1
                if s - q >= window:
                    break
                limit = min(s - q, end - s, MAX_LENGTH, q + window - s)
                if limit <= best_length:
                    continue
                length = 2
                while length < limit and data[q + length] == data[s + length]:
                    length += 1
                if length <= best_length:
                    continue
                distance = s - q - length
                if distance > (575 if length == 2 else 4383):
                    continue
                best_length, best_source = length, s
        if best_length:
            if run:
                tokens.append(('lit', run))
                run = 0
            tokens.append(('match', best_length, best_source - q - best_length))
            q += best_length
        else:
            run += 1
            q += 1
    if run:
        tokens.append(('lit', run))
    return tokens


def bits_of(value, count):
    return [(value >> (count - 1 - i)) & 1 for i in range(count)]


def literal_bits(count):
    if count == 1:
        return [1, 0]
    bits = [1, 1]
    for limit, width, base in ((3, 2, 2), (3, 2, 5), (7, 3, 8), (255, 8, 15), (32767, 15, 270)):
        field = count - base
        if field < limit or width == 15:
            return bits + bits_of(field, width)
        bits += bits_of(limit, width)
    raise ValueError(count)


def match_bits(length, distance):
    if length == 2:
        if distance < 64:
            return [0] + [0] + bits_of(distance, 6)
        return [0] + [1] + bits_of(distance - 64, 9)
    if length == 3:
        bits = [1, 0]
    elif length <= 5:
        bits = [1, 1, 0] + bits_of(length - 4, 1)
    elif length <= 9:
        bits = [1, 1, 1, 0] + bits_of(length - 6, 2)
    else:
        bits = [1, 1, 1, 1] + bits_of(length - 10, 10)
    if distance < 32:
        return bits + [1, 0] + bits_of(distance, 5)
    if distance < 288:
        return bits + [0] + bits_of(distance - 32, 8)
    return bits + [1, 1] + bits_of(distance - 288, 12)


def pack_231(data):
    """The packed file."""
    tokens = list(reversed(parse_231(data)))    # the order the depacker meets them
    # The depacker's reads: ('bits', [...]) and ('bytes', b'...'), in order.
    reads = []
    position = len(data)                        # where the depacker's output stands
    for k, token in enumerate(tokens):
        if token[0] == 'lit':
            count = token[1]
            if count > MAX_LITERALS:
                raise ValueError('a literal run too long for Pack-Ice')
            reads.append(('bits', literal_bits(count)))
            reads.append(('bytes', data[position - count:position]))
            position -= count
        else:
            if k == 0 or tokens[k - 1][0] != 'lit':
                reads.append(('bits', [0]))     # no literals before this match
            reads.append(('bits', match_bits(token[1], token[2])))
            position -= token[1]
    if tokens and tokens[-1][0] == 'match':
        reads.append(('bits', [0]))             # no literals: the output is complete
    reads.append(('bits', [0]))                 # not a picture; the depacker never reads it
    total = sum(len(r[1]) for r in reads if r[0] == 'bits')

    # The stream as the depacker reads it: the first long holds total % 32 bits, then
    # each long 32; a long's literal bytes are the ones read before the next long.
    room = total % 32
    longs = []                                  # [bits, literal byte strings]

    def new_long():
        longs.append([[], []])

    new_long()
    for kind, value in reads:
        if kind == 'bytes':
            longs[-1][1].append(value)
            continue
        for bit in value:
            if room == 0:
                new_long()
                room = 32
            longs[-1][0].append(bit)
            room -= 1
    # bytes from the end downwards: first long, then its literal bytes, then the next long...
    parts = []
    for index, (bits, literals) in enumerate(longs):
        if index == 0:
            word = 0
            for bit in bits:
                word = (word << 1) | bit
            word = ((word << 1) | 1) << (31 - len(bits))      # the end marker after them
        else:
            bits = bits + [0] * (32 - len(bits))
            word = 0
            for bit in bits:
                word = (word << 1) | bit
        parts.append(struct.pack('>I', word))
        for literal in literals:
            parts.append(bytes(literal))
    body = b''.join(reversed(parts))
    return b'Ice!' + struct.pack('>II', 12 + len(body), len(data)) + body


def main():
    args = sys.argv[1:]
    pack = pack_240
    if args and args[0] == '-2.31':
        pack = pack_231
        args = args[1:]
    if len(args) != 2:
        sys.exit('usage: python icepack.py [-2.31] source target')
    source, target = args
    data = open(source, 'rb').read()
    packed = pack(data)
    open(target, 'wb').write(packed)
    print('%s %d -> %d' % (source, len(data), len(packed)))


if __name__ == '__main__':
    main()
