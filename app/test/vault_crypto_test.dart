import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/i18n.dart';
import 'package:pinty/crypto/vault_crypto.dart';

void main() {
  setLang('hu');
  // Gyors paraméterekkel, hogy a teszt ne tartson sokáig.
  final kdf = KdfParams(
    salt: Uint8List.fromList(List.generate(16, (i) => i)),
    memoryKiB: 1024,
    iterations: 1,
    parallelism: 1,
  );

  test('ugyanaz a jelszó ugyanazt a kulcsot adja, más jelszó mást', () async {
    final a = await VaultCrypto.deriveMasterKeys('titok', kdf);
    final b = await VaultCrypto.deriveMasterKeys('titok', kdf);
    final c = await VaultCrypto.deriveMasterKeys('mas-titok', kdf);
    expect(a.authHash, b.authHash);
    expect(a.authHash, isNot(c.authHash));
    expect(await a.encKey.extractBytes(), await b.encKey.extractBytes());
  });

  test('az auth hash nem egyezik a titkosító kulccsal', () async {
    final a = await VaultCrypto.deriveMasterKeys('titok', kdf);
    expect(a.authHash, isNot(String.fromCharCodes(await a.encKey.extractBytes())));
  });

  test('elem titkosítás oda-vissza, és az azonosítóhoz kötött', () async {
    final key = await VaultCrypto.newVaultKey();
    final blob = await VaultCrypto.encryptItem({'name': 'GitHub', 'notes': 'x'}, 'id-1', key);
    final back = await VaultCrypto.decryptItem(blob, 'id-1', key);
    expect(back['name'], 'GitHub');
    expect(() => VaultCrypto.decryptItem(blob, 'id-2', key), throwsA(anything));
  });

  test('széfkulcs becsomagolás oda-vissza, rossz kulccsal hibázik', () async {
    final master = await VaultCrypto.deriveMasterKeys('titok', kdf);
    final other = await VaultCrypto.deriveMasterKeys('rossz', kdf);
    final vk = await VaultCrypto.newVaultKey();
    final wrapped = await VaultCrypto.wrapVaultKey(vk, master.encKey);
    final back = await VaultCrypto.unwrapVaultKey(wrapped, master.encKey);
    expect(await back.extractBytes(), await vk.extractBytes());
    expect(() => VaultCrypto.unwrapVaultKey(wrapped, other.encKey), throwsA(anything));
  });
}
