# Pinty

Saját, végponttól végpontig titkosított jelszókezelő **Windowsra, Linuxra, macOS-re és Androidra**,
szinkronizációval az eszközök között.

- **Zero-knowledge**: a mesterjelszó és a titkosító kulcsok soha nem hagyják el az eszközt. A szerver csak titkosított blobokat lát.
- **Saját szerver**: egy kis Go szolgáltatás (SQLite), ~10 MB-os binárisként vagy Dockerben.
- **Egy kódbázis**: Flutter app, négy platformra.
- **Témák**: világos, sötét, óceán, rózsa.
- **Egyéb információ**: minden elemhez szabad szöveges mező.
- **Jelszógenerátor**, **TOTP** (hitelesítő kódok), **vágólap-törlés**, **automatikus zárolás** (5 perc tétlenség után; Androidon háttérbe kerüléskor is).
- **Offline működés**: a széf hálózat nélkül is feloldható és szerkeszthető, szinkron később.
- **Ütközéskezelés**: ha két eszközön ugyanazt szerkesztették, a szerveren lévő változat marad, a másik "(ütköző példány)" néven külön elemként megmarad. Semmi nem vész el.

## Felépítés

| Könyvtár | Tartalom |
|---|---|
| `server/` | Szinkron-szerver (Go + SQLite) |
| `app/` | Flutter kliens |
| `deploy/` | Docker Compose, nginx és systemd beállítások |
| `docs/` | Biztonsági modell, API |

Részletek: [docs/SECURITY.md](docs/SECURITY.md), [docs/API.md](docs/API.md).

## Letöltés

A GitHub Actions minden változtatás után megépíti a programokat. A **Releases** oldalon találod:

| Fájl | Platform |
|---|---|
| `pinty-windows-x64.zip` | Windows (kicsomagolás után `pinty.exe`) |
| `pinty-macos.zip` | macOS (első indításkor: jobb klikk › Megnyitás) |
| `pinty-linux-x64.tar.gz` | Linux |
| `pinty-android.apk` | Android (idegen forrásból telepítés engedélyezése kell) |
| `pinty-server-linux-amd64` | A szerver |

Az alkalmazások nincsenek kereskedelmi tanúsítvánnyal aláírva, ezért az operációs rendszer az első indításkor figyelmeztethet.

## A szerver üzembe helyezése

Szükséges: egy (al)domain, ami a szerver IP-jére mutat (pl. `vault.sajatdomain.hu`).

### Kész binárissal (ajánlott, kevés lemez/memória esetén is)

```bash
useradd --system --no-create-home --shell /usr/sbin/nologin pinty
mkdir -p /opt/pinty /etc/pinty
curl -L -o /opt/pinty/pinty-server https://github.com/Speederhun/pinty/releases/download/server-latest/pinty-server-linux-amd64
chmod 755 /opt/pinty/pinty-server

# regisztrációs kulcs: ezt kell megadni az appban az első fiók létrehozásakor
echo "PINTY_SETUP_TOKEN=$(openssl rand -hex 16)" > /etc/pinty/pinty.env
chmod 600 /etc/pinty/pinty.env && cat /etc/pinty/pinty.env

cp deploy/systemd/pinty.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now pinty
curl http://127.0.0.1:8081/healthz
```

Ezután egy reverse proxy (nginx: `deploy/nginx/pinty.conf`, majd `certbot --nginx -d vault.sajatdomain.hu`)
teszi elérhetővé HTTPS-en. Frissítés: töltsd le újra a binárist, majd `systemctl restart pinty`.

### Dockerrel

```bash
cd deploy
cp .env.example .env      # PINTY_DOMAIN és PINTY_SETUP_TOKEN beállítása
docker compose up -d --build                              # saját Caddy-vel (automatikus HTTPS)
docker compose -f docker-compose.nginx.yml up -d --build  # ha már van nginx a gépen
```

A Docker-build több száz MB lemezt és némi memóriát igényel, kis szerveren inkább a kész binárist használd.

### Beállítások (környezeti változók)

| Változó | Jelentés |
|---|---|
| `PINTY_ADDR` | Figyelési cím (alap: `:8080`) |
| `PINTY_DATA` | Adatkönyvtár (alap: `./data`) |
| `PINTY_SETUP_TOKEN` | Az ELSŐ fiók létrehozásához szükséges kulcs (opcionális) |
| `PINTY_ALLOW_REGISTRATION` | `true`: bárki regisztrálhat meghívó nélkül (nem ajánlott) |
| `PINTY_TRUST_PROXY` | `true`: a kliens címét az `X-Forwarded-For` fejlécből veszi (reverse proxy mögött) |

### Új felhasználó meghívása

Az első fiókot te hozod létre az appban. További felhasználók csak meghívókóddal regisztrálhatnak,
amit a szerveren állítasz ki az adott e-mail címre (egyszer használható, alapból 7 napig érvényes):

```bash
sudo -u pinty env PINTY_DATA=/var/lib/pinty /opt/pinty/pinty-server invite valaki@example.com
sudo -u pinty env PINTY_DATA=/var/lib/pinty /opt/pinty/pinty-server invites   # lista
sudo -u pinty env PINTY_DATA=/var/lib/pinty /opt/pinty/pinty-server revoke valaki@example.com
```

A meghívott az app „Új fiók” fülén megadja az e-mailjét, a kapott kódot és a saját mesterjelszavát.
Mindenkinek külön, teljesen elszigetelt széfje van.

## Állapot

Működő első verzió. **A kriptó- és szinkronréteg még nem esett át külső biztonsági átvizsgáláson**, ezért
fontos jelszavaidat csak saját felelősségre és biztonsági mentéssel tárold benne.

Még nincs: mesterjelszó-csere az appból (a szerver tudja), jelszótörténet, mappák/címkék és kedvencek a felületen,
import/export, biometrikus feloldás, autofill, böngészőbővítmény.

## Útiterv

1. [x] Szerver, titkosító mag, témák, alap felület
2. [x] Titkosított helyi tárolás, regisztráció/bejelentkezés, regisztrációs kulcs
3. [x] Szinkron ütközéskezeléssel, jelszógenerátor, TOTP
4. [ ] Mappák, címkék, kedvencek; import/export (Bitwarden, KeePass, CSV)
5. [ ] Mesterjelszó-csere, biometrikus feloldás, Android autofill
6. [ ] Böngészőbővítmény
