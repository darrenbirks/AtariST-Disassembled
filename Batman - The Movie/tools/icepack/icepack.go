// Pack-Ice packer: packs data files as the Atari ST packer Pack-Ice does.
//
// Written by Darren Birks in October 2026.
//
// usage: go run icepack.go [-2.31] source target          (Go 1.21 or later)
//
// Packs the file source into the file target in the Pack-Ice 2.40 format, or with -2.31
// in the older Pack-Ice 2.31 format.  It does the same as icepack.py, step for step, and
// gives the same files: byte for byte what Pack-Ice 2.40 or 2.31 writes.  icepack.py
// describes the formats and the packing in full.
package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"sort"
)

const (
	window      = 0x1580 // the search window of Pack-Ice 2.40 (and of the 2.31 packing)
	maxLength   = 1033
	maxLiterals = 33037
)

// keyPositions gives, for each 2 bytes, the positions they start at, in order.
func keyPositions(data []byte) map[uint16][]int {
	where := map[uint16][]int{}
	for s := 0; s < len(data)-1; s++ {
		key := uint16(data[s])<<8 | uint16(data[s+1])
		where[key] = append(where[key], s)
	}
	return where
}

//----------------------------------------------------------------------
// Pack-Ice 2.40
//----------------------------------------------------------------------

// A writer of bits as Pack-Ice 2.40 writes them: into a byte from the top, the lowest bit
// of a value first, each full byte appended to the output.
type bitWriter struct {
	out  []byte
	bits byte // the byte being filled
	free int  // its free bits - 1
}

func (w *bitWriter) put(value, count int) {
	for i := 0; i < count; i++ {
		w.bits = w.bits>>1 | byte((value>>uint(i))&1)<<7
		w.free--
		if w.free < 0 {
			w.out = append(w.out, w.bits)
			w.bits, w.free = 0, 7
		}
	}
}

func (w *bitWriter) putLiteralCount(count int) error {
	if count > maxLiterals {
		return fmt.Errorf("a literal run too long for Pack-Ice")
	}
	sizes := []struct{ base, width, total int }{{270, 15, 32}, {15, 8, 17}, {8, 3, 9}, {5, 2, 6}, {2, 2, 4}, {1, 1, 2}, {0, 1, 1}}
	for _, s := range sizes {
		if count >= s.base {
			w.put(-1<<uint(s.width)|(count-s.base), s.total)
			break
		}
	}
	return nil
}

func (w *bitWriter) putOffset(length, offset int) {
	code := offset + 1
	if length == 2 {
		if code <= 0x3f {
			w.put(code, 7)
		} else {
			w.put((code-0x40)|0x200, 10)
		}
		return
	}
	sizes := []struct{ base, width, total int }{{0x120, 12, 14}, {0x20, 9, 9}, {0, 6, 7}}
	for _, s := range sizes {
		if code >= s.base {
			w.put(-1<<uint(s.width)|(code-s.base), s.total)
			return
		}
	}
}

func (w *bitWriter) putLength(length int) {
	sizes := []struct{ base, width, prefix int }{{10, 10, 4}, {6, 3, 3}, {4, 2, 2}, {3, 1, 1}, {2, 1, 0}}
	for _, s := range sizes {
		if length >= s.base {
			w.put(-1<<uint(s.width)|(length-s.base), s.width+s.prefix)
			return
		}
	}
}

// pack240 gives the packed file, as ICE_2_4.PRG writes it.
func pack240(data []byte) ([]byte, error) {
	n := len(data)
	w := &bitWriter{out: make([]byte, 12, 12+n), free: 7}
	copy(w.out, "ICE!")
	binary.BigEndian.PutUint32(w.out[8:], uint32(n))
	where := keyPositions(data)
	w.put(0, 1) // not a picture: the last bit the depacker reads
	literals := 0
	guard := uint16(0x942) // literals until the next look at the gap
	q := 0
	for {
		// the run of the byte at q
		top := min(q+maxLength, n)
		j := q + 1
		for j < top && data[j] == data[q] {
			j++
		}
		run := top - q - 2
		if j < top {
			run = j - q - 1
		}
		// the longest match, nearest first
		limit := min(q+window, n)
		bestLength, bestCode := 1, 0
		positions := where[uint16(data[q])<<8|uint16(data[q+1])]
		for i := sort.SearchInts(positions, q+1); i < len(positions) && bestLength < maxLength; i++ {
			s := positions[i]
			if s >= limit {
				break
			}
			length := 0
			for data[q+length] == data[s+length] && q+length < s && s+length+1 < limit {
				length++
			}
			code := s - q - length + 1
			if length > maxLength {
				code += length - maxLength
				length = maxLength
			}
			if length <= bestLength || (length > 2 && code > 0x111f) {
				continue
			}
			bestLength, bestCode = length, code
		}
		if run > 1 && run >= bestLength {
			bestLength, bestCode = run, 0
		}
		if bestLength == 1 || (bestLength == 2 && bestCode > 0x23f) {
			w.out = append(w.out, data[q])
			q++
			literals++
			guard--
			if guard&0x8000 != 0 {
				gap := 0x974 + q - len(w.out) - 50
				if gap < 0 {
					break
				}
				guard = uint16(gap)
			}
		} else {
			if err := w.putLiteralCount(literals); err != nil {
				return nil, err
			}
			literals = 0
			w.putOffset(bestLength, bestCode-1)
			w.putLength(bestLength)
			q += bestLength
		}
		if n-q < 3 {
			break
		}
	}
	w.out = append(w.out, data[q:]...)
	if err := w.putLiteralCount(literals + n - q); err != nil {
		return nil, err
	}
	w.out = append(w.out, w.bits|1<<uint(w.free)) // the end marker after the first bits
	binary.BigEndian.PutUint32(w.out[4:], uint32(len(w.out)))
	return w.out, nil
}

//----------------------------------------------------------------------
// Pack-Ice 2.31
//----------------------------------------------------------------------

// A token from the start of the file: a literal run (length = count, literal true) or a
// match of length bytes whose source is distance bytes after it.
type token struct {
	literal  bool
	length   int
	distance int
}

// parse231 finds the tokens from the start of the file: at each position the longest
// match whose source starts after it and ends before the last byte and within the
// window, the lowest source of equal ones, or else a literal byte.
func parse231(data []byte) []token {
	n := len(data)
	end := n - 1 // sources end before the last byte
	win := window - 1
	where := keyPositions(data)
	var tokens []token
	run := 0
	for q := 0; q < n; {
		bestLength, bestSource := 0, 0
		if end-q >= 4 {
			positions := where[uint16(data[q])<<8|uint16(data[q+1])]
			for i := sort.SearchInts(positions, q+2); i < len(positions); i++ {
				s := positions[i]
				if s-q >= win {
					break
				}
				limit := min(s-q, end-s, maxLength, q+win-s)
				if limit <= bestLength {
					continue
				}
				length := 2
				for length < limit && data[q+length] == data[s+length] {
					length++
				}
				if length <= bestLength {
					continue
				}
				distance := s - q - length
				if (length == 2 && distance > 575) || distance > 4383 {
					continue
				}
				bestLength, bestSource = length, s
			}
		}
		if bestLength > 0 {
			if run > 0 {
				tokens = append(tokens, token{literal: true, length: run})
				run = 0
			}
			tokens = append(tokens, token{length: bestLength, distance: bestSource - q - bestLength})
			q += bestLength
		} else {
			run++
			q++
		}
	}
	if run > 0 {
		tokens = append(tokens, token{literal: true, length: run})
	}
	return tokens
}

// bitsOf gives the count lowest bits of value, the highest first.
func bitsOf(value, count int) []byte {
	bits := make([]byte, count)
	for i := 0; i < count; i++ {
		bits[i] = byte(value>>(count-1-i)) & 1
	}
	return bits
}

func literalBits(count int) []byte {
	if count == 1 {
		return []byte{1, 0}
	}
	bits := []byte{1, 1}
	fields := []struct{ limit, width, base int }{{3, 2, 2}, {3, 2, 5}, {7, 3, 8}, {255, 8, 15}, {32767, 15, 270}}
	for _, f := range fields {
		field := count - f.base
		if field < f.limit || f.width == 15 {
			return append(bits, bitsOf(field, f.width)...)
		}
		bits = append(bits, bitsOf(f.limit, f.width)...)
	}
	panic("literal count")
}

func matchBits(length, distance int) []byte {
	var bits []byte
	switch {
	case length == 2:
		if distance < 64 {
			return append([]byte{0, 0}, bitsOf(distance, 6)...)
		}
		return append([]byte{0, 1}, bitsOf(distance-64, 9)...)
	case length == 3:
		bits = []byte{1, 0}
	case length <= 5:
		bits = append([]byte{1, 1, 0}, bitsOf(length-4, 1)...)
	case length <= 9:
		bits = append([]byte{1, 1, 1, 0}, bitsOf(length-6, 2)...)
	default:
		bits = append([]byte{1, 1, 1, 1}, bitsOf(length-10, 10)...)
	}
	switch {
	case distance < 32:
		return append(append(bits, 1, 0), bitsOf(distance, 5)...)
	case distance < 288:
		return append(append(bits, 0), bitsOf(distance-32, 8)...)
	default:
		return append(append(bits, 1, 1), bitsOf(distance-288, 12)...)
	}
}

// A read of the depacker: bits, or literal bytes.
type read struct {
	bits  []byte
	bytes []byte
}

// pack231 gives the packed file.
func pack231(data []byte) ([]byte, error) {
	forward := parse231(data)
	tokens := make([]token, len(forward)) // the order the depacker meets them
	for i, t := range forward {
		tokens[len(forward)-1-i] = t
	}
	var reads []read
	position := len(data) // where the depacker's output stands
	for k, t := range tokens {
		if t.literal {
			if t.length > maxLiterals {
				return nil, fmt.Errorf("a literal run too long for Pack-Ice")
			}
			reads = append(reads, read{bits: literalBits(t.length)})
			reads = append(reads, read{bytes: data[position-t.length : position]})
			position -= t.length
		} else {
			if k == 0 || !tokens[k-1].literal {
				reads = append(reads, read{bits: []byte{0}}) // no literals before this match
			}
			reads = append(reads, read{bits: matchBits(t.length, t.distance)})
			position -= t.length
		}
	}
	if len(tokens) > 0 && !tokens[len(tokens)-1].literal {
		reads = append(reads, read{bits: []byte{0}}) // no literals: the output is complete
	}
	reads = append(reads, read{bits: []byte{0}}) // not a picture; the depacker never reads it
	total := 0
	for _, r := range reads {
		total += len(r.bits)
	}

	// The first long holds total % 32 bits, then each long 32; a long's literal bytes
	// are the ones read before the next long.
	type long struct {
		bits     []byte
		literals [][]byte
	}
	longs := []*long{{}}
	room := total % 32
	for _, r := range reads {
		if r.bytes != nil {
			last := longs[len(longs)-1]
			last.literals = append(last.literals, r.bytes)
			continue
		}
		for _, bit := range r.bits {
			if room == 0 {
				longs = append(longs, &long{})
				room = 32
			}
			last := longs[len(longs)-1]
			last.bits = append(last.bits, bit)
			room--
		}
	}
	// From the end of the file downwards: the first long, its literal bytes, the next long...
	var parts [][]byte
	for index, l := range longs {
		var word uint32
		for _, bit := range l.bits {
			word = word<<1 | uint32(bit)
		}
		if index == 0 {
			word = (word<<1 | 1) << (31 - uint(len(l.bits))) // the end marker after them
		} else {
			word <<= 32 - uint(len(l.bits))
		}
		bytes4 := make([]byte, 4)
		binary.BigEndian.PutUint32(bytes4, word)
		parts = append(parts, bytes4)
		parts = append(parts, l.literals...)
	}
	var body []byte
	for i := len(parts) - 1; i >= 0; i-- {
		body = append(body, parts[i]...)
	}
	out := make([]byte, 12, 12+len(body))
	copy(out, "Ice!")
	binary.BigEndian.PutUint32(out[4:], uint32(12+len(body)))
	binary.BigEndian.PutUint32(out[8:], uint32(len(data)))
	return append(out, body...), nil
}

func main() {
	args := os.Args[1:]
	pack := pack240
	if len(args) > 0 && args[0] == "-2.31" {
		pack = pack231
		args = args[1:]
	}
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: go run icepack.go [-2.31] source target")
		os.Exit(2)
	}
	source, target := args[0], args[1]
	data, err := os.ReadFile(source)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	packed, err := pack(data)
	if err != nil {
		fmt.Fprintln(os.Stderr, source+":", err)
		os.Exit(1)
	}
	if err := os.WriteFile(target, packed, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("%s %d -> %d\n", source, len(data), len(packed))
}
