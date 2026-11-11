# API (v1)

Minden végpont JSON. A hitelesített végpontokhoz: `Authorization: Bearer <token>`.
Az `auth_hash`, `salt`, `blob`, `wrapped_key` mezők base64 szövegek.

| Metódus és útvonal | Leírás |
|---|---|
| `GET /healthz` | Életjel |
| `GET /api/v1/prelogin?email=` | KDF-paraméterek a kulcsszármaztatáshoz |
| `POST /api/v1/register` | `{email, auth_hash, kdf, wrapped_key, invite_code}`; az `invite_code` az adott e-mailre kiállított, egyszer használható, lejáró meghívókód. Kivétel az első fiók (ha nincs `PINTY_SETUP_TOKEN`, kód nélkül; ha van, azzal) |
| `POST /api/v1/login` | `{email, auth_hash}` → `{token, expires_at, wrapped_key, kdf}` |
| `POST /api/v1/logout` | Token érvénytelenítése |
| `POST /api/v1/password` | `{auth_hash, new_auth_hash, new_kdf, new_wrapped_key}` |
| `GET /api/v1/sync?since=N` | A `since` revízió óta változott elemek és a jelenlegi `rev` |
| `PUT /api/v1/items/{id}` | `{blob, base_rev}` → `{id, rev}`; ütközésnél `409` és a szerveren lévő `current` |
| `DELETE /api/v1/items/{id}?base_rev=N` | Törlés (sírkő), a tartalom törlődik |

## Szinkron

A szerver felhasználónként egy növekvő revíziószámot vezet. Minden írás új revíziót kap.
A kliens megjegyzi az utolsó `rev` értéket, és `since=<rev>`-vel csak az újdonságokat kéri le.
Íráskor a `base_rev` az elem utoljára ismert revíziója (újnál 0). Ha közben máshol módosították,
a szerver `409`-et ad, a kliens pedig összefésüli a két változatot, és a régit megőrzi az elem történetében.
