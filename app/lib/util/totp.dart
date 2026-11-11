import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Base32 (RFC 4648) dekódolás; szóközöket, kötőjeleket és kisbetűket megenged.
Uint8List base32Decode(String input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final s = input.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
  var bits = 0;
  var value = 0;
  final out = <int>[];
  for (final ch in s.split('')) {
    final idx = alphabet.indexOf(ch);
    if (idx < 0) throw FormatException('Érvénytelen base32 karakter: $ch');
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.add((value >> (bits - 8)) & 0xFF);
      bits -= 8;
      value &= (1 << bits) - 1;
    }
  }
  return Uint8List.fromList(out);
}

/// A titkos kulcsot adja vissza akkor is, ha egy teljes `otpauth://` hivatkozást másoltak be.
String extractTotpSecret(String raw) {
  final t = raw.trim();
  if (t.toLowerCase().startsWith('otpauth://')) {
    return Uri.tryParse(t)?.queryParameters['secret'] ?? '';
  }
  return t;
}

/// RFC 6238 szerinti TOTP (HMAC-SHA1), a Google Authenticator és társai formátuma.
String totpCode(String secret, {DateTime? at, int digits = 6, int period = 30}) {
  final key = base32Decode(extractTotpSecret(secret));
  if (key.isEmpty) throw const FormatException('Üres TOTP kulcs');
  final seconds = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
  final counter = seconds ~/ period;
  final msg = ByteData(8)..setUint64(0, counter);
  final mac = Hmac(sha1, key).convert(msg.buffer.asUint8List()).bytes;
  final off = mac.last & 0x0F;
  final bin = ((mac[off] & 0x7F) << 24) |
      (mac[off + 1] << 16) |
      (mac[off + 2] << 8) |
      mac[off + 3];
  var mod = 1;
  for (var i = 0; i < digits; i++) {
    mod *= 10;
  }
  return (bin % mod).toString().padLeft(digits, '0');
}

/// Hány másodpercig érvényes még az aktuális kód.
int totpRemaining({DateTime? at, int period = 30}) {
  final seconds = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
  return period - (seconds % period);
}
