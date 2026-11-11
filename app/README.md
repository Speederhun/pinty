# Pinty app (Flutter)

Közös kódbázis Windowsra, Linuxra, macOS-re és Androidra.

## Első indítás

A platform-könyvtárakat (android/, windows/ stb.) a Flutter generálja, ezeket nem tároljuk kézzel:

```bash
cd app
flutter create --platforms=android,windows,linux,macos --project-name pinty .
flutter pub get
flutter test
flutter run -d linux   # vagy windows / macos / egy Android-eszköz
```

## Állapot

- Kész: témák (világos, sötét, óceán, rózsa), széf-elem modell "Egyéb információ" mezővel,
  titkosító mag (`lib/crypto`), szerver-kliens (`lib/api`), alap felület.
- Következő: titkosított helyi tárolás, bejelentkezés/regisztráció képernyő, szinkron,
  jelszógenerátor, TOTP, biometrikus feloldás, autofill.
