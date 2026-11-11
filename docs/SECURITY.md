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

## Kliens oldali tárolás és zárolás

- A helyi másolat (`pinty_vault.json` az alkalmazás adatkönyvtárában) csak titkosított blobokat tartalmaz; nyílt szöveg a lemezre nem kerül.
- A mesterjelszó és a feloldott kulcsok kizárólag memóriában élnek, zároláskor törlődnek. Munkamenet-token sem kerül lemezre: minden szinkronhoz a mesterkulcsból származó `auth_hash`-sel új munkamenet nyílik, majd lezárul.
- A kulcsszármaztatás (Argon2id) külön izolátumban fut, hogy a felület ne fagyjon le.
- Automatikus zárolás 5 perc tétlenség után; Androidon az app háttérbe kerülésekor is. Zároláskor minden megnyitott oldal és párbeszédablak bezárul.
- A vágólapra másolt jelszó 30 másodperc múlva törlődik (ha még ugyanaz van benne).
- A helyi fájl írása ideiglenes fájlon és átnevezésen keresztül történik, így megszakadt írás sem rontja el a széfet.

## Szinkron és ütközések

Az elem helyi módosítása "piszkos" jelölést kap, és a következő szinkronnál kerül a szerverre az utoljára ismert revízióval (`base_rev`).
Ha közben máshol is módosították (409), a szerveren lévő változat marad, a helyi pedig "(ütköző példány)" néven új elemként megmarad.
Ha az egyik oldalon töröltek, a másikon módosítottak, a módosított változat marad. Szinkron közbeni szerkesztést a kliens nem írja felül.

## Szerver oldali védelmek

- Bejelentkezési kísérletek korlátozása IP-nként (10/perc).
- Nem létező e-mailre is hasonló választ adunk a `prelogin`-ra, és a bejelentkezésnél is ugyanannyi munkát végzünk (felhasználó-felderítés és időzítés ellen).
- Munkamenet-tokenek véletlenek, a szerver csak a lenyomatukat tárolja; 30 nap után lejárnak.
- Jelszócsere után minden más munkamenet érvénytelen.
- Alapból csak az első felhasználó regisztrálhat, (ha be van állítva a `PINTY_SETUP_TOKEN`, ahhoz az is kell); a további fiókokhoz az adott e-mailre kiállított, egyszer használható, lejáró meghívókód kell. A kódokból csak SHA-256 lenyomat kerül az adatbázisba (állandó idejű összehasonlítás).
- Kérésméret és elemméret korlát; szigorú JSON-dekódolás.

## Amit a modell **nem** véd

- A szerver látja a metaadatokat: az e-mail címedet, az elemek számát, méretét és módosítási idejét.
- Ha a mesterjelszó gyenge, az Argon2id csak lassítja a találgatást. Hosszú jelmondatot használj.
- Ha az eszközöd kompromittált (kártevő), a feloldott széf is az.

## Teendők a "valódi" használat előtt

- Külső biztonsági átvizsgálás a kriptó- és szinkronrétegen.
- Titkosított helyi tárolás a kliensen (kulcs az OS kulcstartóban), automatikus zárolás.
- Függőségek rendszeres frissítése.
- Mesterjelszó-csere az appból (a szerver oldala kész), és biztonsági mentés/export funkció.
