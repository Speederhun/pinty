package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/hex"
	"strings"
)

var b32 = base32.StdEncoding.WithPadding(base32.NoPadding)

// newInviteCode új, véletlen meghívókódot készít: a megjelenítendő (csoportosított) alakot
// és a tároláshoz használt lenyomatot adja vissza. A kód 160 bit entrópiájú.
func newInviteCode() (display, hash string, err error) {
	b := make([]byte, 20)
	if _, err = rand.Read(b); err != nil {
		return "", "", err
	}
	raw := b32.EncodeToString(b) // 32 karakter
	parts := make([]string, 0, 8)
	for i := 0; i < len(raw); i += 4 {
		parts = append(parts, raw[i:i+4])
	}
	return strings.Join(parts, "-"), hashInvite(raw), nil
}

// normInvite: nagybetű, kötőjelek és szóközök nélkül, hogy a beírás formája ne számítson.
func normInvite(s string) string {
	s = strings.ToUpper(s)
	return strings.Map(func(r rune) rune {
		if r == '-' || r == ' ' || r == '\t' || r == '\n' || r == '\r' {
			return -1
		}
		return r
	}, s)
}

func hashInvite(code string) string {
	h := sha256.Sum256([]byte(normInvite(code)))
	return hex.EncodeToString(h[:])
}
