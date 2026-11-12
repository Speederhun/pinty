import 'dart:typed_data';

import 'totp.dart' show base32Decode;

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// 32 bájt → 52 karakteres, négyes csoportokra bontott base32 kód (pl. `ABCD-EFGH-…`).
String formatRecoveryKey(Uint8List bytes) {
  var bits = 0;
  var value = 0;
  final out = StringBuffer();
  for (final b in bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
    value &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(value << (5 - bits)) & 31]);
  final s = out.toString();
  return [for (var i = 0; i < s.length; i += 4) s.substring(i, i + 4 > s.length ? s.length : i + 4)].join('-');
}

/// A kézzel beírt kód visszaalakítása (kisbetű, szóköz és kötőjel mindegy). Hibás kódnál FormatException.
Uint8List parseRecoveryKey(String input) {
  final bytes = base32Decode(input);
  if (bytes.length != 32) throw const FormatException('A visszaállító kulcs 52 karakteres.');
  return bytes;
}
