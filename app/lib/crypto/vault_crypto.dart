import 'dart:convert';
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
