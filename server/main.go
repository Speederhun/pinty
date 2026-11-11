// Pinty szinkron-szerver.
//
// A szerver "zero-knowledge": csak titkosított blobokat tárol, a mesterjelszót
// és a széf kulcsát soha nem látja. Lásd: docs/SECURITY.md.
package main

import (
	"crypto/rand"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	if len(os.Args) > 1 {
		os.Exit(runCLI(os.Args[1:]))
	}

	addr := env("PINTY_ADDR", ":8080")
	dataDir := env("PINTY_DATA", "./data")
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		log.Fatalf("adatkönyvtár: %v", err)
	}

	st, err := openStore(filepath.Join(dataDir, "pinty.db"))
	if err != nil {
		log.Fatalf("adatbázis: %v", err)
	}
	defer st.Close()

	secret, err := loadOrCreateSecret(filepath.Join(dataDir, "server.key"))
	if err != nil {
		log.Fatalf("szerver kulcs: %v", err)
	}

	s := newServer(st, secret, config{
		AllowRegistration: strings.EqualFold(env("PINTY_ALLOW_REGISTRATION", "false"), "true"),
		TrustProxy:        strings.EqualFold(env("PINTY_TRUST_PROXY", "false"), "true"),
		SetupToken:        os.Getenv("PINTY_SETUP_TOKEN"),
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           s.routes(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	log.Printf("Pinty szerver indul: %s (adatok: %s)", addr, dataDir)
	log.Fatal(srv.ListenAndServe())
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// loadOrCreateSecret betölti (vagy létrehozza) a szerver titkát, amiből a
// nem létező felhasználókhoz tartozó hamis KDF-paraméterek származnak.
func loadOrCreateSecret(path string) ([]byte, error) {
	if b, err := os.ReadFile(path); err == nil && len(b) >= 32 {
		return b, nil
	}
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, b, 0o600); err != nil {
		return nil, err
	}
	return b, nil
}
