"""Batman The Movie loading pictures to BMP and back.

Written by Darren Birks in October 2026.

usage: python picconv.py tobmp picture.pic picture.bmp [level]
       python picconv.py topic picture.bmp picture.pic [-2disk]

The pictures are 320 x 200, 16 colours (ST low resolution), in one of two formats:

  - The 1 disk reissue and the budget release (title.pic, level1.pic .. level5.pic,
    unpacked): Tiny pictures, as the loader's decode_picture reads them:

      byte     resolution (0 = low); 3-5 have 4 bytes of colour animation after it
      32 bytes the palette, 16 words
      word     the number of control bytes
      word     the number of data words
      control bytes, then data words

    A control byte n means: n < 0: the next -n data words as they are; 0: a word
    count follows, then a repeat of the next data word; 1: a word count follows, then
    that many data words; 2-127: the next data word n times.  The words go down the
    screen in columns: plane by plane, 16 pixels at a time, line 0 to 199.

  - The 2 disk release (level1.pic .. level5.pic): a marker word, the length ($7d00),
    then the screen words in order, where the marker, a word and a count byte stand
    for that word count times (a count of 0 is 256).  The palette is not in the file:
    the loader has one for each level (level1_palette .. level5_palette in loader.s),
    which tobmp takes from the level number given, or from the name levelN.pic.

Both kinds of file hold one word more than the 16000 of the screen.  The game's Tiny
decoder puts it at line 0, the last 16 pixels, plane 3 (tobmp does the same, and topic
writes that word there); the 2 disk loader stops before it (topic writes a 0).  With
that, topic gives back every picture of the game byte for byte, but for the reissue's
title.pic, whose last word is $5a5a where the budget release's is 0.

tobmp writes a 4 bit BMP with the picture's 16 colours.  topic reads a 4 or 8 bit BMP of
320 x 200 that uses colours 0-15 only, and writes a Tiny picture, or with -2disk the
2 disk release's format (its palette is not written; the loader's is used).
ST colours are 0-7 per channel: in the BMP, v becomes v * 36 + v // 2 (0, 36 .. 255),
and a BMP colour c becomes c * 7 // 255, rounded.
"""
import os, re, struct, sys

W, H = 320, 200
SCREEN_WORDS = W * H * 4 // 16          # 16000

# the 2 disk release's loader: the palettes of the level pictures
PALETTES_2DISK = {
    1: [0x000, 0x444, 0x222, 0x777, 0x023, 0x411, 0x333, 0x223, 0x555, 0x421, 0x212, 0x760, 0x532, 0x643, 0x754, 0x004],
    2: [0x000, 0x545, 0x536, 0x436, 0x314, 0x250, 0x240, 0x230, 0x000, 0x112, 0x223, 0x334, 0x445, 0x556, 0x667, 0x220],
    3: [0x000, 0x777, 0x604, 0x230, 0x120, 0x766, 0x544, 0x433, 0x433, 0x730, 0x721, 0x521, 0x400, 0x403, 0x313, 0x212],
    4: [0x000, 0x112, 0x223, 0x334, 0x445, 0x556, 0x667, 0x777, 0x333, 0x111, 0x222, 0x630, 0x751, 0x420, 0x101, 0x201],
    5: [0x000, 0x112, 0x333, 0x444, 0x555, 0x666, 0x340, 0x120, 0x303, 0x404, 0x525, 0x004, 0x225, 0x045, 0x771, 0x750],
}


def tiny_order():
    """Screen word index for each word of a Tiny picture, in the order they come."""
    order = []
    for plane in range(4):
        for group in range(20):
            for line in range(H):
                order.append(line * 80 + group * 4 + plane)
    return order


ORDER = tiny_order()
EXTRA = 19 * 4 + 3              # where the game's decoder puts a 16001st word


#----------------------------------------------------------------------
# Tiny (the reissue and the budget release)
#----------------------------------------------------------------------

def is_2disk(d):
    return len(d) >= 6 and struct.unpack_from('>I', d, 2)[0] == W * H // 2


def is_tiny(d):
    if len(d) < 37 or d[0] > 5 or is_2disk(d):
        return False
    o = 33 + (4 if d[0] >= 3 else 0)
    if len(d) < o + 4:
        return False
    n_ctrl, n_data = struct.unpack_from('>HH', d, o)
    return o + 4 + n_ctrl + 2 * n_data <= len(d)


def tiny_decode(d):
    """(palette, screen words)."""
    p = 1 + (4 if d[0] >= 3 else 0)
    palette = list(struct.unpack_from('>16H', d, p))
    p += 32
    n_ctrl, n_data = struct.unpack_from('>HH', d, p)
    p += 4
    ctrl, data = p, p + n_ctrl
    end = ctrl + n_ctrl

    def word():
        nonlocal data
        v = struct.unpack_from('>H', d, data)[0]
        data += 2
        return v

    out = []
    c = ctrl
    while c < end:
        n = d[c]
        c += 1
        if n >= 128:                            # -n words as they are
            out += [word() for _ in range(256 - n)]
        elif n == 0:                            # a long repeat
            k = struct.unpack_from('>H', d, c)[0]
            c += 2
            out += [word()] * k
        elif n == 1:                            # a long run of words
            k = struct.unpack_from('>H', d, c)[0]
            c += 2
            out += [word() for _ in range(k)]
        else:                                   # a short repeat
            out += [word()] * n
    screen = [0] * SCREEN_WORDS
    for i, v in enumerate(out[:SCREEN_WORDS]):
        screen[ORDER[i]] = v
    if len(out) > SCREEN_WORDS:                 # the game's decoder puts word 16001 at
        screen[EXTRA] = out[SCREEN_WORDS]       # line 0, last 16 pixels, plane 3
    return palette, screen


def tiny_encode(palette, screen, resolution=0):
    seq = [screen[i] for i in ORDER]
    ctrl, data = bytearray(), []
    i, n = 0, len(seq)
    lit = []

    def flush():
        while lit:
            k = len(lit)
            if k <= 128:
                ctrl.append(256 - k)
            else:
                ctrl.append(1)
                ctrl.extend(struct.pack('>H', k))
            data.extend(lit)
            lit.clear()

    while i < n:
        j = i
        while j < n and seq[j] == seq[i]:
            j += 1
        r = j - i
        if r >= 2:
            flush()
            if r <= 127:
                ctrl.append(r)
            else:
                ctrl.append(0)
                ctrl.extend(struct.pack('>H', r))
            data.append(seq[i])
            i = j
        else:
            lit.append(seq[i])
            i += 1
    flush()
    # Like the game's pictures, one word more: the game's decoder puts it back where it
    # came from, line 0, the last 16 pixels, plane 3.
    ctrl.append(255)
    data.append(screen[EXTRA])
    return (bytes([resolution]) + struct.pack('>16H', *palette) + struct.pack('>HH', len(ctrl), len(data))
            + bytes(ctrl) + struct.pack('>%dH' % len(data), *data))


#----------------------------------------------------------------------
# the 2 disk release's format
#----------------------------------------------------------------------

def rle_decode(d):
    marker, length = struct.unpack_from('>HI', d, 0)
    p, out = 6, []
    total = SCREEN_WORDS
    while len(out) < total and p + 2 <= len(d):
        v = struct.unpack_from('>H', d, p)[0]
        p += 2
        if v != marker:
            out.append(v)
            continue
        v = struct.unpack_from('>H', d, p)[0]
        k = d[p + 2] or 256
        p += 3
        out += [v] * k
    out = out[:total]
    return out + [0] * (total - len(out))


def rle_encode(screen, marker=None):
    if marker is None:                          # the lowest word the picture does not use
        counts = {}
        for v in screen:
            counts[v] = counts.get(v, 0) + 1
        marker = next(m for m in range(0x10000) if m not in counts)
    out = bytearray(struct.pack('>HI', marker, W * H // 2))
    # like the game's pictures, one word 0 more, which the loader does not write
    screen = list(screen) + [0]
    i, n = 0, len(screen)
    while i < n:
        j = i
        while j < n and j - i < 255 and screen[j] == screen[i]:
            j += 1
        r = j - i
        if r >= 3 or screen[i] == marker:
            out += struct.pack('>HHB', marker, screen[i], r)
            i = j
        else:
            out += struct.pack('>H', screen[i])
            i += 1
    return bytes(out)


#----------------------------------------------------------------------
# screen words <-> pixels, BMP
#----------------------------------------------------------------------

def to_pixels(screen):
    px = bytearray(W * H)
    for y in range(H):
        for g in range(20):
            p = [screen[y * 80 + g * 4 + k] for k in range(4)]
            for x in range(16):
                b = 15 - x
                px[y * W + g * 16 + x] = ((p[0] >> b) & 1) | (((p[1] >> b) & 1) << 1) | \
                    (((p[2] >> b) & 1) << 2) | (((p[3] >> b) & 1) << 3)
    return px


def from_pixels(px):
    screen = [0] * SCREEN_WORDS
    for y in range(H):
        for g in range(20):
            p = [0, 0, 0, 0]
            for x in range(16):
                c = px[y * W + g * 16 + x]
                for k in range(4):
                    p[k] = (p[k] << 1) | ((c >> k) & 1)
            for k in range(4):
                screen[y * 80 + g * 4 + k] = p[k]
    return screen


def st_to_rgb(v):
    return tuple(c * 36 + c // 2 for c in ((v >> 8) & 7, (v >> 4) & 7, v & 7))


def rgb_to_st(r, g, b):
    return sum(((c * 7 + 127) // 255) << s for c, s in ((r, 8), (g, 4), (b, 0)))


def write_bmp(path, palette, px):
    pal = b''.join(bytes((b, g, r, 0)) for r, g, b in (st_to_rgb(v) for v in palette))
    bits = bytearray()
    for y in range(H - 1, -1, -1):                  # bottom row first
        for x in range(0, W, 2):
            bits.append((px[y * W + x] << 4) | px[y * W + x + 1])
    off = 14 + 40 + len(pal)
    head = b'BM' + struct.pack('<IHHI', off + len(bits), 0, 0, off)
    info = struct.pack('<IiiHHIIiiII', 40, W, H, 1, 4, 0, len(bits), 2835, 2835, 16, 16)
    open(path, 'wb').write(head + info + pal + bits)


def read_bmp(path):
    d = open(path, 'rb').read()
    if d[:2] != b'BM':
        raise ValueError('not a BMP file')
    off = struct.unpack_from('<I', d, 10)[0]
    size, w, h, planes, bpp, comp = struct.unpack_from('<IiiHHI', d, 14)
    colours = struct.unpack_from('<I', d, 46)[0] or (1 << bpp)
    if comp != 0 or bpp not in (4, 8):
        raise ValueError('the BMP must be 4 or 8 bits a pixel, not compressed')
    if w != W or abs(h) != H:
        raise ValueError('the BMP must be 320 x 200')
    pal_at = 14 + size
    palette = []
    for k in range(16):
        if k < colours:
            b, g, r = d[pal_at + 4 * k:pal_at + 4 * k + 3]
            palette.append(rgb_to_st(r, g, b))
        else:
            palette.append(0)
    row = (W * bpp // 8 + 3) & ~3
    px = bytearray(W * H)
    for y in range(H):
        src = off + (y if h < 0 else H - 1 - y) * row
        for x in range(W):
            if bpp == 8:
                c = d[src + x]
            else:
                c = d[src + x // 2] >> (4 if x % 2 == 0 else 0) & 15
            if c > 15:
                raise ValueError('pixel %d,%d uses colour %d: only 0-15 can be used' % (x, y, c))
            px[y * W + x] = c
    return palette, px


def level_of(path, given):
    if given:
        return int(given)
    m = re.search(r'level(\d)', os.path.basename(path).lower())
    return int(m.group(1)) if m else None


def main():
    a = sys.argv[1:]
    if len(a) >= 3 and a[0] == 'tobmp':
        d = open(a[1], 'rb').read()
        if is_tiny(d):
            palette, screen = tiny_decode(d)
        elif not is_2disk(d):
            sys.exit('not a Batman picture')
        else:
            level = level_of(a[1], a[3] if len(a) > 3 else None)
            if level not in PALETTES_2DISK:
                sys.exit('a 2 disk release picture: give its level (1-5) for the palette')
            palette, screen = PALETTES_2DISK[level], rle_decode(d)
        write_bmp(a[2], palette, to_pixels(screen))
    elif len(a) >= 3 and a[0] == 'topic':
        palette, px = read_bmp(a[1])
        screen = from_pixels(px)
        if len(a) > 3 and a[3] == '-2disk':
            open(a[2], 'wb').write(rle_encode(screen))
        else:
            open(a[2], 'wb').write(tiny_encode(palette, screen))
    else:
        sys.exit(__doc__.split('\n\n')[2])


if __name__ == '__main__':
    main()
