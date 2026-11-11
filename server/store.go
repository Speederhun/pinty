package main

import (
	"database/sql"
	"errors"
	"time"

	_ "modernc.org/sqlite"
)

var (
	errExists   = errors.New("már létezik")
	errNotFound = errors.New("nem található")
	errConflict = errors.New("ütközés")
)

type kdfParams struct {
	Salt        string `json:"salt"` // base64
	MemoryKiB   int    `json:"memory_kib"`
	Iterations  int    `json:"iterations"`
	Parallelism int    `json:"parallelism"`
}

type user struct {
	ID         string
	Email      string
	KDF        kdfParams
	AuthStored string // a kliens auth_hash-ének szerveroldali Argon2id lenyomata
	WrappedKey string // a széfkulcs, a mesterkulccsal titkosítva (a szerver nem tudja kinyitni)
}

type item struct {
	ID        string `json:"id"`
	Rev       int64  `json:"rev"`
	Deleted   bool   `json:"deleted"`
	Blob      string `json:"blob"`
	UpdatedAt int64  `json:"updated_at"`
}

type store struct{ db *sql.DB }

const schema = `
CREATE TABLE IF NOT EXISTS users (
	id TEXT PRIMARY KEY,
	email TEXT NOT NULL UNIQUE,
	kdf_salt TEXT NOT NULL,
	kdf_memory INTEGER NOT NULL,
	kdf_iter INTEGER NOT NULL,
	kdf_par INTEGER NOT NULL,
	auth_stored TEXT NOT NULL,
	wrapped_key TEXT NOT NULL,
	rev INTEGER NOT NULL DEFAULT 0,
	created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
	token_hash TEXT PRIMARY KEY,
	user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS items (
	user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	id TEXT NOT NULL,
	rev INTEGER NOT NULL,
	blob TEXT NOT NULL,
	deleted INTEGER NOT NULL DEFAULT 0,
	updated_at INTEGER NOT NULL,
	PRIMARY KEY (user_id, id)
);
CREATE INDEX IF NOT EXISTS items_rev ON items (user_id, rev);
`

func openStore(path string) (*store, error) {
	dsn := "file:" + path + "?_txlock=immediate&_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(4)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	return &store{db: db}, nil
}

func (s *store) Close() error { return s.db.Close() }

func (s *store) countUsers() (int, error) {
	var n int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&n)
	return n, err
}

func (s *store) createUser(u user) error {
	_, err := s.db.Exec(`INSERT INTO users
		(id, email, kdf_salt, kdf_memory, kdf_iter, kdf_par, auth_stored, wrapped_key, created_at)
		VALUES (?,?,?,?,?,?,?,?,?)`,
		u.ID, u.Email, u.KDF.Salt, u.KDF.MemoryKiB, u.KDF.Iterations, u.KDF.Parallelism,
		u.AuthStored, u.WrappedKey, time.Now().Unix())
	if err != nil && isUnique(err) {
		return errExists
	}
	return err
}

func (s *store) userByEmail(email string) (*user, error) {
	var u user
	err := s.db.QueryRow(`SELECT id, email, kdf_salt, kdf_memory, kdf_iter, kdf_par, auth_stored, wrapped_key
		FROM users WHERE email = ?`, email).
		Scan(&u.ID, &u.Email, &u.KDF.Salt, &u.KDF.MemoryKiB, &u.KDF.Iterations, &u.KDF.Parallelism, &u.AuthStored, &u.WrappedKey)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errNotFound
	}
	return &u, err
}

func (s *store) userByID(id string) (*user, error) {
	var u user
	err := s.db.QueryRow(`SELECT id, email, kdf_salt, kdf_memory, kdf_iter, kdf_par, auth_stored, wrapped_key
		FROM users WHERE id = ?`, id).
		Scan(&u.ID, &u.Email, &u.KDF.Salt, &u.KDF.MemoryKiB, &u.KDF.Iterations, &u.KDF.Parallelism, &u.AuthStored, &u.WrappedKey)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errNotFound
	}
	return &u, err
}

func (s *store) createToken(userID, tokenHash string, exp time.Time) error {
	// a lejárt tokenek takarítása menet közben
	_, _ = s.db.Exec(`DELETE FROM tokens WHERE expires_at < ?`, time.Now().Unix())
	_, err := s.db.Exec(`INSERT INTO tokens (token_hash, user_id, expires_at) VALUES (?,?,?)`,
		tokenHash, userID, exp.Unix())
	return err
}

func (s *store) userIDByToken(tokenHash string) (string, error) {
	var id string
	err := s.db.QueryRow(`SELECT user_id FROM tokens WHERE token_hash = ? AND expires_at > ?`,
		tokenHash, time.Now().Unix()).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return "", errNotFound
	}
	return id, err
}

func (s *store) deleteToken(tokenHash string) error {
	_, err := s.db.Exec(`DELETE FROM tokens WHERE token_hash = ?`, tokenHash)
	return err
}

// updateCredentials a mesterjelszó cseréjekor lecseréli a hitelesítési adatokat,
// és minden más munkamenetet érvényteleníti.
func (s *store) updateCredentials(userID, authStored, wrappedKey string, kdf kdfParams, keepToken string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`UPDATE users SET auth_stored=?, wrapped_key=?, kdf_salt=?, kdf_memory=?, kdf_iter=?, kdf_par=? WHERE id=?`,
		authStored, wrappedKey, kdf.Salt, kdf.MemoryKiB, kdf.Iterations, kdf.Parallelism, userID); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM tokens WHERE user_id=? AND token_hash<>?`, userID, keepToken); err != nil {
		return err
	}
	return tx.Commit()
}

// syncSince visszaadja a since revízió után változott elemeket és a jelenlegi revíziót.
func (s *store) syncSince(userID string, since int64) ([]item, int64, error) {
	var rev int64
	if err := s.db.QueryRow(`SELECT rev FROM users WHERE id=?`, userID).Scan(&rev); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.Query(`SELECT id, rev, blob, deleted, updated_at FROM items
		WHERE user_id=? AND rev>? ORDER BY rev`, userID, since)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []item{}
	for rows.Next() {
		var it item
		var del int
		if err := rows.Scan(&it.ID, &it.Rev, &it.Blob, &del, &it.UpdatedAt); err != nil {
			return nil, 0, err
		}
		it.Deleted = del != 0
		out = append(out, it)
	}
	return out, rev, rows.Err()
}

// putItem optimista zárolással ír: baseRev egyezik a tárolt revízióval (új elemnél 0),
// különben errConflict és a szerveren lévő aktuális állapot.
func (s *store) putItem(userID, id, blob string, baseRev int64, deleted bool) (int64, *item, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return 0, nil, err
	}
	defer tx.Rollback()

	var cur item
	var del int
	err = tx.QueryRow(`SELECT id, rev, blob, deleted, updated_at FROM items WHERE user_id=? AND id=?`, userID, id).
		Scan(&cur.ID, &cur.Rev, &cur.Blob, &del, &cur.UpdatedAt)
	exists := err == nil
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return 0, nil, err
	}
	cur.Deleted = del != 0
	if exists && cur.Rev != baseRev {
		return 0, &cur, errConflict
	}
	if !exists && baseRev != 0 {
		return 0, nil, errNotFound
	}

	var newRev int64
	if err := tx.QueryRow(`UPDATE users SET rev = rev + 1 WHERE id=? RETURNING rev`, userID).Scan(&newRev); err != nil {
		return 0, nil, err
	}
	now := time.Now().Unix()
	d := 0
	if deleted {
		d = 1
		blob = "" // sírkő: a tartalmat töröljük
	}
	if _, err := tx.Exec(`INSERT INTO items (user_id, id, rev, blob, deleted, updated_at) VALUES (?,?,?,?,?,?)
		ON CONFLICT(user_id, id) DO UPDATE SET rev=excluded.rev, blob=excluded.blob, deleted=excluded.deleted, updated_at=excluded.updated_at`,
		userID, id, newRev, blob, d, now); err != nil {
		return 0, nil, err
	}
	return newRev, nil, tx.Commit()
}
