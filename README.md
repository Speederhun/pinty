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
Ha a szerveren már fut nginx (a 80/443 port foglalt), ne a Caddyt használd, hanem:

```bash
cd deploy
docker compose -f docker-compose.nginx.yml up -d --build
# majd az nginx beállítása: deploy/nginx/pinty.conf
```

Az első felhasználó regisztrálhat; több fiókhoz ideiglenesen `PINTY_ALLOW_REGISTRATION=true`.

### Docker nélkül (kis lemezű szerverre)

A CI minden push után publikál egy kész binárist (`server-latest` release). Fordítás nélkül:

```bash
useradd --system --no-create-home --shell /usr/sbin/nologin pinty
mkdir -p /opt/pinty
curl -L -o /opt/pinty/pinty-server https://github.com/Speederhun/pinty/releases/download/server-latest/pinty-server-linux-amd64
chmod 755 /opt/pinty/pinty-server
cp deploy/systemd/pinty.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now pinty
curl http://127.0.0.1:8081/healthz
```

Frissítés: töltsd le újra a binárist, majd `systemctl restart pinty`.

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
