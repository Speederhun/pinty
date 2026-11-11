# Pinty

Saját, végponttól végpontig titkosított jelszókezelő **Windowsra, Linuxra, macOS-re és Androidra**,
szinkronizációval az eszközök között.

- **Zero-knowledge**: a mesterjelszó és a titkosító kulcsok soha nem hagyják el az eszközt. A szerver csak titkosított blobokat lát.
- **Saját szerver**: egy kis Go szolgáltatás (SQLite), Dockerrel, automatikus HTTPS-sel (Caddy).
- **Egy kódbázis**: Flutter app, négy platformra.
- **Témák**: világos, sötét, óceán, rózsa.
- **Egyéb információ**: minden elemhez szabad szöveges mező.

## Felépítés

| Könyvtár | Tartalom |
|---|---|
| `server/` | Szinkron-szerver (Go + SQLite) |
| `app/` | Flutter kliens |
| `deploy/` | Docker Compose + Caddy a szerver üzemeltetéséhez |
| `docs/` | Biztonsági modell, API |

Részletek: [docs/SECURITY.md](docs/SECURITY.md), [docs/API.md](docs/API.md).

## A szerver üzembe helyezése

```bash
cd deploy
cp .env.example .env     # állítsd be a PINTY_DOMAIN-t
docker compose up -d --build
```

Szükséges: egy (al)domain, ami a szerver IP-jére mutat (pl. `vault.sajatdomain.hu`).
Ha a szerveren már fut másik reverse proxy, ne indítsd a Caddyt; add hozzá a `pinty:8080` célpontot a meglévő proxyhoz.

Az első felhasználó regisztrálhat; több fiókhoz ideiglenesen `PINTY_ALLOW_REGISTRATION=true`.

> A `server/go.sum` még nincs a repóban. Egy gépen, ahol van Go, futtasd egyszer:
> `cd server && go mod tidy && go test ./...`, majd commitold a `go.mod` és `go.sum` fájlokat.

## Állapot

Korai fázis. A szerver és a titkosító mag megvan, a kliens alap felülete működik memóriában.
**Ne tárolj még valódi jelszavakat**, amíg a titkosított helyi tárolás és a biztonsági átvizsgálás nem készült el.

## Útiterv

1. [x] Szerver, titkosító mag, témák, alap felület
2. [ ] Titkosított helyi tárolás, regisztráció/bejelentkezés képernyő
3. [ ] Szinkron (ütközéskezeléssel), jelszógenerátor
4. [ ] TOTP kódok, import/export (Bitwarden, KeePass, CSV)
5. [ ] Android: biometrikus feloldás, autofill
6. [ ] Böngészőbővítmény
