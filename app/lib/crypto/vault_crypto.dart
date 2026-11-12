import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Argon2id paraméterek. A szerver tárolja őket a felhasználónál, így később emelhetők.
class KdfParams {
  const KdfParams({
    required this.salt,
    this.memoryKiB = 65536,
    this.iterations = 3,
    this.parallelism = 4,
  });

  final Uint8List salt;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
        'salt': base64.encode(salt),
        'memory_kib': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
      };

  factory KdfParams.fromJson(Map<String, dynamic> j) => KdfParams(
        salt: base64.decode(j['salt'] as String),
        memoryKiB: j['memory_kib'] as int,
        iterations: j['iterations'] as int,
        parallelism: j['parallelism'] as int,
      );
}

/// A mesterjelszóból származtatott két kulcs: az egyik titkosít (soha nem hagyja el
/// az eszközt), a másik a szerver felé bizonyítja, hogy ismered a jelszót.
class MasterKeys {
  MasterKeys(this.encKey, this.authHash);
  final SecretKey encKey;
  final String authHash; // base64, ezt küldjük a szervernek
}

/// Titkosítási formátum: 0x01 | nonce(24) | ciphertext | mac(16), base64-ben.
/// Algoritmus: XChaCha20-Poly1305. Az AAD az elem azonosítója, így a szerver nem
/// tudja egy elem blobját egy másik azonosító alá "átrakni".
class VaultCrypto {
  static const _version = 0x01;
  static const _nonceLen = 24;
  static const _macLen = 16;

  static final _cipher = Xchacha20.poly1305Aead();

  /// Mesterjelszó → (titkosító kulcs, auth hash).
  static Future<MasterKeys> deriveMasterKeys(String password, KdfParams kdf) async {
    final argon = Argon2id(
      parallelism: kdf.parallelism,
      memory: kdf.memoryKiB,
      iterations: kdf.iterations,
      hashLength: 32,
    );
    final stretched = await argon.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: kdf.salt,
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final enc = await hkdf.deriveKey(
      secretKey: stretched,
      nonce: const <int>[],
      info: utf8.encode('pinty-enc-v1'),
    );
    final auth = await hkdf.deriveKey(
      secretKey: stretched,
      nonce: const <int>[],
      info: utf8.encode('pinty-auth-v1'),
    );
    return MasterKeys(enc, base64.encode(await auth.extractBytes()));
  }

  /// Ugyanaz, mint a [deriveMasterKeys], de külön izolátumban fut, így a lassú
  /// Argon2id nem fagyasztja le a felületet.
  static Future<MasterKeys> deriveMasterKeysAsync(String password, KdfParams kdf) async {
    final result = await Isolate.run(() async {
      final keys = await deriveMasterKeys(password, kdf);
      return (await keys.encKey.extractBytes(), keys.authHash);
    });
    return MasterKeys(SecretKey(result.$1), result.$2);
  }

  /// Biztonsági mentés kulcsa a mentés jelszavából (külön "info", így nem keverhető a fiók kulcsaival).
  static Future<SecretKey> deriveBackupKey(String password, KdfParams kdf) async {
    final argon = Argon2id(
      parallelism: kdf.parallelism,
      memory: kdf.memoryKiB,
      iterations: kdf.iterations,
      hashLength: 32,
    );
    final stretched = await argon.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: kdf.salt);
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32)
        .deriveKey(secretKey: stretched, nonce: const <int>[], info: utf8.encode('pinty-backup-v1'));
  }

  static Future<SecretKey> deriveBackupKeyAsync(String password, KdfParams kdf) async {
    final bytes = await Isolate.run(() async => (await deriveBackupKey(password, kdf)).extractBytes());
    return SecretKey(bytes);
  }

  /// A 256 bites visszaállító kulcsból két érték: a széfkulcs becsomagolásához használt kulcs, és a
  /// szervernek küldött bizonyíték (base64). A kettő egymásból nem számolható ki.
  static Future<(SecretKey, String)> deriveRecovery(List<int> recoveryKey) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final root = SecretKey(recoveryKey);
    final wrap = await hkdf.deriveKey(secretKey: root, nonce: const <int>[], info: utf8.encode('pinty-recovery-enc-v1'));
    final auth = await hkdf.deriveKey(secretKey: root, nonce: const <int>[], info: utf8.encode('pinty-recovery-auth-v1'));
    return (wrap, base64.encode(await auth.extractBytes()));
  }

  static Future<String> wrapVaultKeyForRecovery(SecretKey vaultKey, SecretKey wrapKey) async =>
      encryptBytes(await vaultKey.extractBytes(), wrapKey, aad: utf8.encode('vault-key-recovery'));

  static Future<SecretKey> unwrapVaultKeyForRecovery(String wrapped, SecretKey wrapKey) async =>
      SecretKey(await decryptBytes(wrapped, wrapKey, aad: utf8.encode('vault-key-recovery')));

  static Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// Új, véletlen széfkulcs.
  static Future<SecretKey> newVaultKey() => _cipher.newSecretKey();

  static Future<String> encryptBytes(
    List<int> plain,
    SecretKey key, {
    List<int> aad = const [],
  }) async {
    final box = await _cipher.encrypt(plain, secretKey: key, aad: aad);
    final out = BytesBuilder()
      ..addByte(_version)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return base64.encode(out.toBytes());
  }

  static Future<List<int>> decryptBytes(
    String blob,
    SecretKey key, {
    List<int> aad = const [],
  }) async {
    final data = base64.decode(blob);
    if (data.length < 1 + _nonceLen + _macLen || data[0] != _version) {
      throw const FormatException('ismeretlen vagy sérült blob');
    }
    final nonce = data.sublist(1, 1 + _nonceLen);
    final mac = Mac(data.sublist(data.length - _macLen));
    final cipherText = data.sublist(1 + _nonceLen, data.length - _macLen);
    return _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
      aad: aad,
    );
  }

  /// A széfkulcs becsomagolása a mesterkulccsal (ezt tárolja a szerver).
  static Future<String> wrapVaultKey(SecretKey vaultKey, SecretKey encKey) async =>
      encryptBytes(await vaultKey.extractBytes(), encKey, aad: utf8.encode('vault-key'));

  static Future<SecretKey> unwrapVaultKey(String wrapped, SecretKey encKey) async =>
      SecretKey(await decryptBytes(wrapped, encKey, aad: utf8.encode('vault-key')));

  static Future<String> encryptItem(Map<String, dynamic> json, String id, SecretKey vaultKey) =>
      encryptBytes(utf8.encode(jsonEncode(json)), vaultKey, aad: utf8.encode('item:$id'));

  static Future<Map<String, dynamic>> decryptItem(String blob, String id, SecretKey vaultKey) async {
    final bytes = await decryptBytes(blob, vaultKey, aad: utf8.encode('item:$id'));
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }
}
