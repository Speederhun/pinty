package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

type testEnv struct {
	t  *testing.T
	ts *httptest.Server
}

func newTestEnv(t *testing.T, allowReg bool) *testEnv {
	t.Helper()
	st, err := openStore(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatal(err)
	}
	s := newServer(st, bytes.Repeat([]byte{7}, 32), config{AllowRegistration: allowReg})
	s.authLim = newLimiter(1000, time.Minute)
	ts := httptest.NewServer(s.routes())
	t.Cleanup(func() { ts.Close(); st.Close() })
	return &testEnv{t: t, ts: ts}
}

func (e *testEnv) do(method, path, token string, body any) (int, map[string]any) {
	e.t.Helper()
	var rd *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	} else {
		rd = bytes.NewReader(nil)
	}
	req, _ := http.NewRequest(method, e.ts.URL+path, rd)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

func b64(n int, fill byte) string {
	return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{fill}, n))
}

func regBody(email string, hashFill byte) map[string]any {
	return map[string]any{
		"email": email, "auth_hash": b64(32, hashFill), "wrapped_key": "wrapped",
		"kdf": map[string]any{"salt": b64(16, 1), "memory_kib": 19456, "iterations": 2, "parallelism": 1},
	}
}

func login(e *testEnv, email string, fill byte) string {
	code, out := e.do("POST", "/api/v1/login", "", map[string]any{"email": email, "auth_hash": b64(32, fill)})
	if code != 200 {
		e.t.Fatalf("login: %d %v", code, out)
	}
	return out["token"].(string)
}

func TestFullFlow(t *testing.T) {
	e := newTestEnv(t, false)

	if code, _ := e.do("POST", "/api/v1/register", "", regBody("a@example.com", 9)); code != 201 {
		t.Fatalf("register: %d", code)
	}
	// második felhasználó: tiltva
	if code, _ := e.do("POST", "/api/v1/register", "", regBody("b@example.com", 9)); code != 403 {
		t.Fatalf("második regisztráció: %d, várt 403", code)
	}
	if code, _ := e.do("POST", "/api/v1/login", "", map[string]any{"email": "a@example.com", "auth_hash": b64(32, 1)}); code != 401 {
		t.Fatalf("rossz jelszó: %d, várt 401", code)
	}
	tok := login(e, "a@example.com", 9)

	if code, _ := e.do("GET", "/api/v1/sync", "", nil); code != 401 {
		t.Fatalf("token nélkül: %d, várt 401", code)
	}

	id := "11111111-2222-3333"
	code, out := e.do("PUT", "/api/v1/items/"+id, tok, map[string]any{"blob": "titkos1", "base_rev": 0})
	if code != 200 {
		t.Fatalf("put: %d %v", code, out)
	}
	rev1 := int64(out["rev"].(float64))

	// elavult base_rev -> ütközés
	code, out = e.do("PUT", "/api/v1/items/"+id, tok, map[string]any{"blob": "titkos2", "base_rev": 0})
	if code != 409 || out["current"] == nil {
		t.Fatalf("ütközés: %d %v", code, out)
	}

	code, out = e.do("PUT", "/api/v1/items/"+id, tok, map[string]any{"blob": "titkos2", "base_rev": rev1})
	if code != 200 {
		t.Fatalf("frissítés: %d %v", code, out)
	}
	rev2 := int64(out["rev"].(float64))

	code, out = e.do("GET", "/api/v1/sync?since=0", tok, nil)
	items := out["items"].([]any)
	if code != 200 || len(items) != 1 || items[0].(map[string]any)["blob"] != "titkos2" {
		t.Fatalf("sync: %d %v", code, out)
	}
	// inkrementális sync: nincs újdonság
	_, out = e.do("GET", "/api/v1/sync?since="+itoa(rev2), tok, nil)
	if len(out["items"].([]any)) != 0 {
		t.Fatalf("a since után nem várt elemet: %v", out)
	}

	// törlés sírkővel
	code, _ = e.do("DELETE", "/api/v1/items/"+id+"?base_rev="+itoa(rev2), tok, nil)
	if code != 200 {
		t.Fatalf("törlés: %d", code)
	}
	_, out = e.do("GET", "/api/v1/sync?since="+itoa(rev2), tok, nil)
	it := out["items"].([]any)[0].(map[string]any)
	if it["deleted"] != true || it["blob"] != "" {
		t.Fatalf("sírkő: %v", it)
	}

	// jelszócsere: a régi jelszó nem működik, az új igen, a többi token érvénytelen
	tok2 := login(e, "a@example.com", 9)
	code, _ = e.do("POST", "/api/v1/password", tok, map[string]any{
		"auth_hash": b64(32, 9), "new_auth_hash": b64(32, 5), "new_wrapped_key": "wrapped2",
		"new_kdf": map[string]any{"salt": b64(16, 2), "memory_kib": 19456, "iterations": 2, "parallelism": 1},
	})
	if code != 200 {
		t.Fatalf("jelszócsere: %d", code)
	}
	if code, _ := e.do("GET", "/api/v1/sync", tok2, nil); code != 401 {
		t.Fatalf("másik munkamenet él: %d", code)
	}
	if code, _ := e.do("GET", "/api/v1/sync", tok, nil); code != 200 {
		t.Fatalf("a jelenlegi munkamenetnek élnie kellene: %d", code)
	}
	if code, _ := e.do("POST", "/api/v1/login", "", map[string]any{"email": "a@example.com", "auth_hash": b64(32, 9)}); code != 401 {
		t.Fatalf("régi jelszó még működik: %d", code)
	}
	login(e, "a@example.com", 5)
}

func TestPreloginDoesNotLeakUsers(t *testing.T) {
	e := newTestEnv(t, true)
	_, a := e.do("GET", "/api/v1/prelogin?email=nincs@example.com", "", nil)
	_, b := e.do("GET", "/api/v1/prelogin?email=nincs@example.com", "", nil)
	if a["kdf"] == nil || a["kdf"].(map[string]any)["salt"] != b["kdf"].(map[string]any)["salt"] {
		t.Fatalf("ismeretlen e-mailre determinisztikus választ várunk: %v %v", a, b)
	}
}

func TestIsolationBetweenUsers(t *testing.T) {
	e := newTestEnv(t, true)
	e.do("POST", "/api/v1/register", "", regBody("a@example.com", 1))
	e.do("POST", "/api/v1/register", "", regBody("b@example.com", 2))
	ta, tb := login(e, "a@example.com", 1), login(e, "b@example.com", 2)
	e.do("PUT", "/api/v1/items/aaaaaaaa-bbbb", ta, map[string]any{"blob": "x", "base_rev": 0})
	_, out := e.do("GET", "/api/v1/sync", tb, nil)
	if len(out["items"].([]any)) != 0 {
		t.Fatalf("B látja A elemeit: %v", out)
	}
}

func itoa(n int64) string { return strconv.FormatInt(n, 10) }
