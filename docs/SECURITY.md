# Biztonsági modell

Cél: a szerver (vagy aki megszerzi az adatbázisát) **semmit** ne tudjon meg a jelszavakról.
Saját kriptográfiai algoritmust nem írunk, csak bevált primitíveket használunk.

## Kulcsok

```
mesterjelszó ──Argon2id(só, memória, iteráció, párhuzamosság)──► stretched (32 B)
stretched ──HKDF-SHA256("pinty-enc-v1")──►  enc_key   (marad az eszközön)
stretched ──HKDF-SHA256("pinty-auth-v1")──► auth_key  (ebből lesz az auth_hash)

vault_key  = 32 véletlen bájt (egyszer generálva)
wrapped_key = XChaCha20-Poly1305(vault_key, kulcs = enc_key)   ← ezt tárolja a szerver
blob(elem)  = XChaCha20-Poly1305(elem JSON, kulcs = vault_key, AAD = "item:<id>")
```

- A szerver az `auth_hash`-t kapja, de abból a `enc_key` nem számolható vissza (külön HKDF-ág).
- A szerver az `auth_hash`-t még egyszer lenyomatolja (Argon2id, saját sóval), így az adatbázis kiszivárgása sem ad belépési adatot.
- A `vault_key` külön kulcs, ezért mesterjelszó-cserekor csak a `wrapped_key`-t kell újracsomagolni, a blobokat nem.
- Az AAD az elem azonosítója, így a szerver nem tud egy blobot másik azonosító alá átrakni.

## Blob formátum

`base64( 0x01 | nonce(24) | titkosított szöveg | MAC(16) )`

A verziószám lehetővé teszi az algoritmus későbbi cseréjét.

## Szerver oldali védelmek

- Bejelentkezési kísérletek korlátozása IP-nként (10/perc).
- Nem létező e-mailre is hasonló választ adunk a `prelogin`-ra, és a bejelentkezésnél is ugyanannyi munkát végzünk (felhasználó-felderítés és időzítés ellen).
- Munkamenet-tokenek véletlenek, a szerver csak a lenyomatukat tárolja; 30 nap után lejárnak.
- Jelszócsere után minden más munkamenet érvénytelen.
- Alapból csak az első felhasználó regisztrálhat.
- Kérésméret és elemméret korlát; szigorú JSON-dekódolás.

## Amit a modell **nem** véd

- A szerver látja a metaadatokat: az e-mail címedet, az elemek számát, méretét és módosítási idejét.
- Ha a mesterjelszó gyenge, az Argon2id csak lassítja a találgatást. Hosszú jelmondatot használj.
- Ha az eszközöd kompromittált (kártevő), a feloldott széf is az.

## Teendők a "valódi" használat előtt

- Külső biztonsági átvizsgálás a kriptó- és szinkronrétegen.
- Titkosított helyi tárolás a kliensen (kulcs az OS kulcstartóban), automatikus zárolás.
- Függőségek rendszeres frissítése.
