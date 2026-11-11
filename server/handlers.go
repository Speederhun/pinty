package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/argon2"
)

const (
	maxBody      = 1 << 20   // 1 MiB / kérés
	maxBlob      = 256 << 10 // 256 KiB / elem
	tokenTTL     = 30 * 24 * time.Hour
	defaultMemKB = 65536 // 64 MiB
	defaultIter  = 3
	defaultPar   = 4
)

var (
	idRe    = regexp.MustCompile(`^[A-Za-z0-9-]{8,64}$`)
	emailRe = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)
)

type config struct {
	AllowRegistration bool
	TrustProxy        bool
}

type server struct {
	st      *store
	secret  []byte
	cfg     config
	authLim *limiter
}

func newServer(st *store, secret []byte, cfg config) *server {
	return &server{st: st, secret: secret, cfg: cfg, authLim: newLimiter(10, time.Minute)}
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, map[string]string{"status": "ok"}) })
	mux.HandleFunc("GET /api/v1/prelogin", s.handlePrelogin)
	mux.HandleFunc("POST /api/v1/register", s.handleRegister)
	mux.HandleFunc("POST /api/v1/login", s.handleLogin)
	mux.HandleFunc("POST /api/v1/logout", s.auth(s.handleLogout))
	mux.HandleFunc("POST /api/v1/password", s.auth(s.handleChangePassword))
	mux.HandleFunc("GET /api/v1/sync", s.auth(s.handleSync))
	mux.HandleFunc("PUT /api/v1/items/{id}", s.auth(s.handlePutItem))
	mux.HandleFunc("DELETE /api/v1/items/{id}", s.auth(s.handleDeleteItem))
	return secureHeaders(mux)
}

func secureHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Cache-Control", "no-store")
		h.Set("Referrer-Policy", "no-referrer")
		r.Body = http.MaxBytesReader(w, r.Body, maxBody)
		next.ServeHTTP(w, r)
	})
}

// ---------- segédek ----------

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		writeErr(w, http.StatusBadRequest, "érvénytelen kérés")
		return false
	}
	return true
}

func isUnique(err error) bool {
	return err != nil && strings.Contains(strings.ToLower(err.Error()), "unique")
}

func (s *server) clientIP(r *http.Request) string {
	if s.cfg.TrustProxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			return strings.TrimSpace(strings.Split(xff, ",")[0])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func normEmail(e string) string { return strings.ToLower(strings.TrimSpace(e)) }

func randToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func hashToken(t string) string {
	h := sha256.Sum256([]byte(t))
	return base64.RawURLEncoding.EncodeToString(h[:])
}

func validKDF(k kdfParams) bool {
	salt, err := base64.StdEncoding.DecodeString(k.Salt)
	return err == nil && len(salt) >= 16 && len(salt) <= 64 &&
		k.MemoryKiB >= 19456 && k.MemoryKiB <= 1<<20 &&
		k.Iterations >= 1 && k.Iterations <= 10 &&
		k.Parallelism >= 1 && k.Parallelism <= 16
}

func validAuthHash(h string) bool {
	b, err := base64.StdEncoding.DecodeString(h)
	return err == nil && len(b) >= 32 && len(b) <= 64
}

// A kliens auth_hash-e már egy erős KDF kimenete; a szerver ezt még egyszer
// lenyomatolja, hogy az adatbázis kiszivárgása se adjon belépési adatot.
func hashAuth(authHash string, salt []byte) string {
	h := argon2.IDKey([]byte(authHash), salt, 2, 19*1024, 1, 32)
	return base64.StdEncoding.EncodeToString(salt) + "$" + base64.StdEncoding.EncodeToString(h)
}

func verifyAuth(authHash, stored string) bool {
	parts := strings.SplitN(stored, "$", 2)
	if len(parts) != 2 {
		return false
	}
	salt, err := base64.StdEncoding.DecodeString(parts[0])
	if err != nil {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(hashAuth(authHash, salt)), []byte(stored)) == 1
}

// ---------- kezelők ----------

// prelogin: a kliensnek kell a KDF só és paraméterek a kulcs származtatásához.
// Ismeretlen e-mailre hamis, de determinisztikus választ adunk (nincs felhasználó-felderítés).
func (s *server) handlePrelogin(w http.ResponseWriter, r *http.Request) {
	if !s.authLim.allow("pre:" + s.clientIP(r)) {
		writeErr(w, http.StatusTooManyRequests, "túl sok próbálkozás")
		return
	}
	email := normEmail(r.URL.Query().Get("email"))
	if !emailRe.MatchString(email) {
		writeErr(w, http.StatusBadRequest, "érvénytelen e-mail")
		return
	}
	if u, err := s.st.userByEmail(email); err == nil {
		writeJSON(w, 200, map[string]any{"kdf": u.KDF})
		return
	}
	mac := hmac.New(sha256.New, s.secret)
	mac.Write([]byte("prelogin:" + email))
	salt := mac.Sum(nil)[:16]
	writeJSON(w, 200, map[string]any{"kdf": kdfParams{
		Salt: base64.StdEncoding.EncodeToString(salt), MemoryKiB: defaultMemKB, Iterations: defaultIter, Parallelism: defaultPar,
	}})
}

type registerReq struct {
	Email      string    `json:"email"`
	AuthHash   string    `json:"auth_hash"`
	KDF        kdfParams `json:"kdf"`
	WrappedKey string    `json:"wrapped_key"`
}

func (s *server) handleRegister(w http.ResponseWriter, r *http.Request) {
	if !s.authLim.allow("reg:" + s.clientIP(r)) {
		writeErr(w, http.StatusTooManyRequests, "túl sok próbálkozás")
		return
	}
	var req registerReq
	if !decode(w, r, &req) {
		return
	}
	req.Email = normEmail(req.Email)
	if !emailRe.MatchString(req.Email) || len(req.Email) > 254 || !validAuthHash(req.AuthHash) ||
		!validKDF(req.KDF) || req.WrappedKey == "" || len(req.WrappedKey) > 1024 {
		writeErr(w, http.StatusBadRequest, "érvénytelen adatok")
		return
	}
	n, err := s.st.countUsers()
	if err != nil {
		writeErr(w, 500, "szerverhiba")
		return
	}
	// Alapból csak az első felhasználó regisztrálhat; több fiókhoz kell a PINTY_ALLOW_REGISTRATION=true.
	if n > 0 && !s.cfg.AllowRegistration {
		writeErr(w, http.StatusForbidden, "a regisztráció le van tiltva")
		return
	}
	idb := make([]byte, 16)
	_, _ = rand.Read(idb)
	salt := make([]byte, 16)
	_, _ = rand.Read(salt)
	err = s.st.createUser(user{
		ID:         base64.RawURLEncoding.EncodeToString(idb),
		Email:      req.Email,
		KDF:        req.KDF,
		AuthStored: hashAuth(req.AuthHash, salt),
		WrappedKey: req.WrappedKey,
	})
	if errors.Is(err, errExists) {
		writeErr(w, http.StatusConflict, "ez az e-mail már regisztrálva van")
		return
	}
	if err != nil {
		writeErr(w, 500, "szerverhiba")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"status": "created"})
}

type loginReq struct {
	Email    string `json:"email"`
	AuthHash string `json:"auth_hash"`
}

// dummyStored: az ismeretlen felhasználóknál is ugyanannyi munkát végzünk (időzítés ellen).
var dummyStored = hashAuth("dummy", make([]byte, 16))

func (s *server) handleLogin(w http.ResponseWriter, r *http.Request) {
	ip := s.clientIP(r)
	if !s.authLim.allow("login:" + ip) {
		writeErr(w, http.StatusTooManyRequests, "túl sok próbálkozás")
		return
	}
	var req loginReq
	if !decode(w, r, &req) {
		return
	}
	req.Email = normEmail(req.Email)
	if !validAuthHash(req.AuthHash) {
		writeErr(w, http.StatusBadRequest, "érvénytelen adatok")
		return
	}
	u, err := s.st.userByEmail(req.Email)
	if err != nil {
		verifyAuth(req.AuthHash, dummyStored)
		writeErr(w, http.StatusUnauthorized, "hibás e-mail vagy jelszó")
		return
	}
	if !verifyAuth(req.AuthHash, u.AuthStored) {
		writeErr(w, http.StatusUnauthorized, "hibás e-mail vagy jelszó")
		return
	}
	tok, err := randToken()
	if err != nil {
		writeErr(w, 500, "szerverhiba")
		return
	}
	exp := time.Now().Add(tokenTTL)
	if err := s.st.createToken(u.ID, hashToken(tok), exp); err != nil {
		writeErr(w, 500, "szerverhiba")
		return
	}
	writeJSON(w, 200, map[string]any{
		"token": tok, "expires_at": exp.Unix(), "wrapped_key": u.WrappedKey, "kdf": u.KDF,
	})
}

// ---------- hitelesített kezelők ----------

type authedHandler func(w http.ResponseWriter, r *http.Request, userID, tokenHash string)

func (s *server) auth(next authedHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		h := r.Header.Get("Authorization")
		tok, ok := strings.CutPrefix(h, "Bearer ")
		if !ok || tok == "" {
			writeErr(w, http.StatusUnauthorized, "bejelentkezés szükséges")
			return
		}
		th := hashToken(tok)
		uid, err := s.st.userIDByToken(th)
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "bejelentkezés szükséges")
			return
		}
		next(w, r, uid, th)
	}
}

func (s *server) handleLogout(w http.ResponseWriter, r *http.Request, _ string, th string) {
	_ = s.st.deleteToken(th)
	writeJSON(w, 200, map[string]string{"status": "ok"})
}

type changePwReq struct {
	AuthHash      string    `json:"auth_hash"`
	NewAuthHash   string    `json:"new_auth_hash"`
	NewKDF        kdfParams `json:"new_kdf"`
	NewWrappedKey string    `json:"new_wrapped_key"`
}

func (s *server) handleChangePassword(w http.ResponseWriter, r *http.Request, uid, th string) {
	if !s.authLim.allow("pw:" + uid) {
		writeErr(w, http.StatusTooManyRequests, "túl sok próbálkozás")
		return
	}
	var req changePwReq
	if !decode(w, r, &req) {
		return
	}
	if !validAuthHash(req.AuthHash) || !validAuthHash(req.NewAuthHash) || !validKDF(req.NewKDF) ||
		req.NewWrappedKey == "" || len(req.NewWrappedKey) > 1024 {
		writeErr(w, http.StatusBadRequest, "érvénytelen adatok")
		return
	}
	u, err := s.st.userByID(uid)
	if err != nil || !verifyAuth(req.AuthHash, u.AuthStored) {
		writeErr(w, http.StatusUnauthorized, "hibás jelszó")
		return
	}
	salt := make([]byte, 16)
	_, _ = rand.Read(salt)
	if err := s.st.updateCredentials(uid, hashAuth(req.NewAuthHash, salt), req.NewWrappedKey, req.NewKDF, th); err != nil {
		writeErr(w, 500, "szerverhiba")
		return
	}
	writeJSON(w, 200, map[string]string{"status": "ok"})
}

func (s *server) handleSync(w http.ResponseWriter, r *http.Request, uid, _ string) {
	since := int64(0)
	if v := r.URL.Query().Get("since"); v != "" {
		n, err := strconv.ParseInt(v, 10, 64)
		if err != nil || n < 0 {
			writeErr(w, http.StatusBadRequest, "érvénytelen since")
			return
		}
		since = n
	}
	items, rev, err := s.st.syncSince(uid, since)
	if err != nil {
		writeErr(w, 500, "szerverhiba")
		return
	}
	writeJSON(w, 200, map[string]any{"rev": rev, "items": items})
}

type putItemReq struct {
	Blob    string `json:"blob"`
	BaseRev int64  `json:"base_rev"`
}

func (s *server) handlePutItem(w http.ResponseWriter, r *http.Request, uid, _ string) {
	id := r.PathValue("id")
	if !idRe.MatchString(id) {
		writeErr(w, http.StatusBadRequest, "érvénytelen azonosító")
		return
	}
	var req putItemReq
	if !decode(w, r, &req) {
		return
	}
	if req.Blob == "" || len(req.Blob) > maxBlob || req.BaseRev < 0 {
		writeErr(w, http.StatusBadRequest, "érvénytelen adatok")
		return
	}
	s.writeItem(w, uid, id, req.Blob, req.BaseRev, false)
}

func (s *server) handleDeleteItem(w http.ResponseWriter, r *http.Request, uid, _ string) {
	id := r.PathValue("id")
	if !idRe.MatchString(id) {
		writeErr(w, http.StatusBadRequest, "érvénytelen azonosító")
		return
	}
	base, err := strconv.ParseInt(r.URL.Query().Get("base_rev"), 10, 64)
	if err != nil || base <= 0 {
		writeErr(w, http.StatusBadRequest, "hiányzó base_rev")
		return
	}
	s.writeItem(w, uid, id, "", base, true)
}

func (s *server) writeItem(w http.ResponseWriter, uid, id, blob string, base int64, deleted bool) {
	rev, cur, err := s.st.putItem(uid, id, blob, base, deleted)
	switch {
	case errors.Is(err, errConflict):
		writeJSON(w, http.StatusConflict, map[string]any{"error": "ütközés", "current": cur})
	case errors.Is(err, errNotFound):
		writeErr(w, http.StatusNotFound, "az elem nem létezik")
	case err != nil:
		writeErr(w, 500, "szerverhiba")
	default:
		writeJSON(w, 200, map[string]any{"id": id, "rev": rev})
	}
}
