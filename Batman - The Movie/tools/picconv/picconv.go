// Batman The Movie loading pictures to BMP and back.
//
// Written by Darren Birks in October 2026.
//
// usage: go run picconv.go tobmp picture.pic picture.bmp [level]
//        go run picconv.go topic picture.bmp picture.pic [-2disk]
//
// It does the same as picconv.py, step for step, and writes the same files; picconv.py
// describes the two picture formats in full.
package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const (
	width       = 320
	height      = 200
	screenWords = width * height * 4 / 16 // 16000
	extraWord   = 19*4 + 3                // where the game's decoder puts a 16001st word
)

// the 2 disk release's loader: the palettes of the level pictures
var palettes2disk = map[int][]uint16{
	1: {0x000, 0x444, 0x222, 0x777, 0x023, 0x411, 0x333, 0x223, 0x555, 0x421, 0x212, 0x760, 0x532, 0x643, 0x754, 0x004},
	2: {0x000, 0x545, 0x536, 0x436, 0x314, 0x250, 0x240, 0x230, 0x000, 0x112, 0x223, 0x334, 0x445, 0x556, 0x667, 0x220},
	3: {0x000, 0x777, 0x604, 0x230, 0x120, 0x766, 0x544, 0x433, 0x433, 0x730, 0x721, 0x521, 0x400, 0x403, 0x313, 0x212},
	4: {0x000, 0x112, 0x223, 0x334, 0x445, 0x556, 0x667, 0x777, 0x333, 0x111, 0x222, 0x630, 0x751, 0x420, 0x101, 0x201},
	5: {0x000, 0x112, 0x333, 0x444, 0x555, 0x666, 0x340, 0x120, 0x303, 0x404, 0x525, 0x004, 0x225, 0x045, 0x771, 0x750},
}

// order gives the screen word index of each word of a Tiny picture, in the order they come.
var order = func() []int {
	o := make([]int, 0, screenWords)
	for plane := 0; plane < 4; plane++ {
		for group := 0; group < 20; group++ {
			for line := 0; line < height; line++ {
				o = append(o, line*80+group*4+plane)
			}
		}
	}
	return o
}()

func be16(d []byte, o int) uint16 { return binary.BigEndian.Uint16(d[o:]) }

//----------------------------------------------------------------------
// Tiny (the reissue and the budget release)
//----------------------------------------------------------------------

func is2disk(d []byte) bool {
	return len(d) >= 6 && binary.BigEndian.Uint32(d[2:]) == width*height/2
}

func isTiny(d []byte) bool {
	if len(d) < 37 || d[0] > 5 || is2disk(d) {
		return false
	}
	o := 33
	if d[0] >= 3 {
		o += 4
	}
	if len(d) < o+4 {
		return false
	}
	return o+4+int(be16(d, o))+2*int(be16(d, o+2)) <= len(d)
}

func tinyDecode(d []byte) ([]uint16, []uint16) {
	p := 1
	if d[0] >= 3 {
		p += 4
	}
	palette := make([]uint16, 16)
	for k := range palette {
		palette[k] = be16(d, p+2*k)
	}
	p += 32
	nCtrl, nData := int(be16(d, p)), int(be16(d, p+2))
	_ = nData
	p += 4
	c, data, end := p, p+nCtrl, p+nCtrl
	word := func() uint16 { v := be16(d, data); data += 2; return v }
	var out []uint16
	for c < end {
		n := int(d[c])
		c++
		switch {
		case n >= 128: // -n words as they are
			for k := 0; k < 256-n; k++ {
				out = append(out, word())
			}
		case n == 0: // a long repeat
			k := int(be16(d, c))
			c += 2
			v := word()
			for ; k > 0; k-- {
				out = append(out, v)
			}
		case n == 1: // a long run of words
			k := int(be16(d, c))
			c += 2
			for ; k > 0; k-- {
				out = append(out, word())
			}
		default: // a short repeat
			v := word()
			for k := 0; k < n; k++ {
				out = append(out, v)
			}
		}
	}
	screen := make([]uint16, screenWords)
	for i, v := range out {
		if i >= screenWords {
			break
		}
		screen[order[i]] = v
	}
	if len(out) > screenWords { // the game's decoder puts word 16001 at line 0, last 16 pixels, plane 3
		screen[extraWord] = out[screenWords]
	}
	return palette, screen
}

func tinyEncode(palette, screen []uint16, resolution byte) []byte {
	seq := make([]uint16, screenWords)
	for i, s := range order {
		seq[i] = screen[s]
	}
	var ctrl []byte
	var data, lit []uint16
	flush := func() {
		for len(lit) > 0 {
			k := len(lit)
			if k <= 128 {
				ctrl = append(ctrl, byte(256-k))
			} else {
				ctrl = append(ctrl, 1, byte(k>>8), byte(k))
			}
			data = append(data, lit...)
			lit = lit[:0]
		}
	}
	for i := 0; i < len(seq); {
		j := i
		for j < len(seq) && seq[j] == seq[i] {
			j++
		}
		r := j - i
		if r >= 2 {
			flush()
			if r <= 127 {
				ctrl = append(ctrl, byte(r))
			} else {
				ctrl = append(ctrl, 0, byte(r>>8), byte(r))
			}
			data = append(data, seq[i])
			i = j
		} else {
			lit = append(lit, seq[i])
			i++
		}
	}
	flush()
	// Like the game's pictures, one word more: the game's decoder puts it back where it
	// came from, line 0, the last 16 pixels, plane 3.
	ctrl = append(ctrl, 255)
	data = append(data, screen[extraWord])
	out := []byte{resolution}
	for _, v := range palette {
		out = binary.BigEndian.AppendUint16(out, v)
	}
	out = binary.BigEndian.AppendUint16(out, uint16(len(ctrl)))
	out = binary.BigEndian.AppendUint16(out, uint16(len(data)))
	out = append(out, ctrl...)
	for _, v := range data {
		out = binary.BigEndian.AppendUint16(out, v)
	}
	return out
}

//----------------------------------------------------------------------
// the 2 disk release's format
//----------------------------------------------------------------------

func rleDecode(d []byte) []uint16 {
	marker := be16(d, 0)
	p := 6
	var out []uint16
	for len(out) < screenWords && p+2 <= len(d) {
		v := be16(d, p)
		p += 2
		if v != marker {
			out = append(out, v)
			continue
		}
		v = be16(d, p)
		k := int(d[p+2])
		if k == 0 {
			k = 256
		}
		p += 3
		for ; k > 0; k-- {
			out = append(out, v)
		}
	}
	if len(out) > screenWords {
		out = out[:screenWords]
	}
	for len(out) < screenWords {
		out = append(out, 0)
	}
	return out
}

func rleEncode(screen []uint16) []byte {
	used := make([]bool, 0x10000)
	for _, v := range screen {
		used[v] = true
	}
	marker := 0
	for used[marker] { // the lowest word the picture does not use, so it needs no escape
		marker++
	}
	out := binary.BigEndian.AppendUint16(nil, uint16(marker))
	out = binary.BigEndian.AppendUint32(out, width*height/2)
	// like the game's pictures, one word 0 more, which the loader does not write
	s := append(append([]uint16{}, screen...), 0)
	for i := 0; i < len(s); {
		j := i
		for j < len(s) && j-i < 255 && s[j] == s[i] {
			j++
		}
		r := j - i
		if r >= 3 || int(s[i]) == marker {
			out = binary.BigEndian.AppendUint16(out, uint16(marker))
			out = binary.BigEndian.AppendUint16(out, s[i])
			out = append(out, byte(r))
			i = j
		} else {
			out = binary.BigEndian.AppendUint16(out, s[i])
			i++
		}
	}
	return out
}

//----------------------------------------------------------------------
// screen words <-> pixels, BMP
//----------------------------------------------------------------------

func toPixels(screen []uint16) []byte {
	px := make([]byte, width*height)
	for y := 0; y < height; y++ {
		for g := 0; g < 20; g++ {
			var p [4]uint16
			for k := range p {
				p[k] = screen[y*80+g*4+k]
			}
			for x := 0; x < 16; x++ {
				b := uint(15 - x)
				px[y*width+g*16+x] = byte((p[0]>>b)&1 | ((p[1]>>b)&1)<<1 | ((p[2]>>b)&1)<<2 | ((p[3]>>b)&1)<<3)
			}
		}
	}
	return px
}

func fromPixels(px []byte) []uint16 {
	screen := make([]uint16, screenWords)
	for y := 0; y < height; y++ {
		for g := 0; g < 20; g++ {
			var p [4]uint16
			for x := 0; x < 16; x++ {
				c := px[y*width+g*16+x]
				for k := range p {
					p[k] = p[k]<<1 | uint16(c>>uint(k))&1
				}
			}
			for k := range p {
				screen[y*80+g*4+k] = p[k]
			}
		}
	}
	return screen
}

func stToRGB(v uint16) (byte, byte, byte) {
	f := func(c uint16) byte { return byte(c*36 + c/2) }
	return f((v >> 8) & 7), f((v >> 4) & 7), f(v & 7)
}

func rgbToST(r, g, b byte) uint16 {
	f := func(c byte) uint16 { return (uint16(c)*7 + 127) / 255 }
	return f(r)<<8 | f(g)<<4 | f(b)
}

func writeBMP(path string, palette []uint16, px []byte) error {
	var pal []byte
	for _, v := range palette {
		r, g, b := stToRGB(v)
		pal = append(pal, b, g, r, 0)
	}
	var bits []byte
	for y := height - 1; y >= 0; y-- { // bottom row first
		for x := 0; x < width; x += 2 {
			bits = append(bits, px[y*width+x]<<4|px[y*width+x+1])
		}
	}
	off := 14 + 40 + len(pal)
	le := binary.LittleEndian
	out := []byte("BM")
	out = le.AppendUint32(out, uint32(off+len(bits)))
	out = le.AppendUint32(out, 0)
	out = le.AppendUint32(out, uint32(off))
	out = le.AppendUint32(out, 40)
	out = le.AppendUint32(out, width)
	out = le.AppendUint32(out, height)
	out = le.AppendUint16(out, 1)
	out = le.AppendUint16(out, 4)
	out = le.AppendUint32(out, 0)
	out = le.AppendUint32(out, uint32(len(bits)))
	out = le.AppendUint32(out, 2835)
	out = le.AppendUint32(out, 2835)
	out = le.AppendUint32(out, 16)
	out = le.AppendUint32(out, 16)
	out = append(out, pal...)
	out = append(out, bits...)
	return os.WriteFile(path, out, 0o644)
}

func readBMP(path string) ([]uint16, []byte, error) {
	d, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	if len(d) < 54 || string(d[:2]) != "BM" {
		return nil, nil, errors.New("not a BMP file")
	}
	le := binary.LittleEndian
	off := int(le.Uint32(d[10:]))
	size := int(le.Uint32(d[14:]))
	w, h := int(int32(le.Uint32(d[18:]))), int(int32(le.Uint32(d[22:])))
	bpp, comp := int(le.Uint16(d[28:])), le.Uint32(d[30:])
	colours := int(le.Uint32(d[46:]))
	if colours == 0 {
		colours = 1 << uint(bpp)
	}
	if comp != 0 || (bpp != 4 && bpp != 8) {
		return nil, nil, errors.New("the BMP must be 4 or 8 bits a pixel, not compressed")
	}
	if w != width || (h != height && h != -height) {
		return nil, nil, errors.New("the BMP must be 320 x 200")
	}
	palette := make([]uint16, 16)
	for k := 0; k < 16 && k < colours; k++ {
		q := 14 + size + 4*k
		palette[k] = rgbToST(d[q+2], d[q+1], d[q])
	}
	row := (width*bpp/8 + 3) &^ 3
	px := make([]byte, width*height)
	for y := 0; y < height; y++ {
		src := off + (height-1-y)*row
		if h < 0 {
			src = off + y*row
		}
		for x := 0; x < width; x++ {
			var c byte
			if bpp == 8 {
				c = d[src+x]
			} else if x%2 == 0 {
				c = d[src+x/2] >> 4
			} else {
				c = d[src+x/2] & 15
			}
			if c > 15 {
				return nil, nil, fmt.Errorf("pixel %d,%d uses colour %d: only 0-15 can be used", x, y, c)
			}
			px[y*width+x] = c
		}
	}
	return palette, px, nil
}

func levelOf(path, given string) int {
	if given != "" {
		n, _ := strconv.Atoi(given)
		return n
	}
	m := regexp.MustCompile(`level(\d)`).FindStringSubmatch(strings.ToLower(filepath.Base(path)))
	if m == nil {
		return 0
	}
	n, _ := strconv.Atoi(m[1])
	return n
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

func main() {
	a := os.Args[1:]
	switch {
	case len(a) >= 3 && a[0] == "tobmp":
		d, err := os.ReadFile(a[1])
		if err != nil {
			fail(err)
		}
		var palette, screen []uint16
		switch {
		case isTiny(d):
			palette, screen = tinyDecode(d)
		case is2disk(d):
			given := ""
			if len(a) > 3 {
				given = a[3]
			}
			p, ok := palettes2disk[levelOf(a[1], given)]
			if !ok {
				fail(errors.New("a 2 disk release picture: give its level (1-5) for the palette"))
			}
			palette, screen = p, rleDecode(d)
		default:
			fail(errors.New("not a Batman picture"))
		}
		if err := writeBMP(a[2], palette, toPixels(screen)); err != nil {
			fail(err)
		}
	case len(a) >= 3 && a[0] == "topic":
		palette, px, err := readBMP(a[1])
		if err != nil {
			fail(err)
		}
		screen := fromPixels(px)
		var out []byte
		if len(a) > 3 && a[3] == "-2disk" {
			out = rleEncode(screen)
		} else {
			out = tinyEncode(palette, screen, 0)
		}
		if err := os.WriteFile(a[2], out, 0o644); err != nil {
			fail(err)
		}
	default:
		fmt.Fprintln(os.Stderr, "usage: go run picconv.go tobmp picture.pic picture.bmp [level]\n"+
			"       go run picconv.go topic picture.bmp picture.pic [-2disk]")
		os.Exit(2)
	}
}
