import 'dart:math';
import '../i18n.dart';

class PasswordOptions {
  const PasswordOptions({
    this.length = 20,
    this.lower = true,
    this.upper = true,
    this.digits = true,
    this.symbols = true,
  });

  final int length;
  final bool lower;
  final bool upper;
  final bool digits;
  final bool symbols;

  PasswordOptions copyWith({int? length, bool? lower, bool? upper, bool? digits, bool? symbols}) =>
      PasswordOptions(
        length: length ?? this.length,
        lower: lower ?? this.lower,
        upper: upper ?? this.upper,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
      );
}

const _lowerSet = 'abcdefghijklmnopqrstuvwxyz';
const _upperSet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _digitSet = '0123456789';
const _symbolSet = r'!@#$%^&*()-_=+[]{};:,.?';

/// Véletlen jelszó (alapból kriptográfiailag biztonságos véletlenből).
/// Minden bekapcsolt karaktercsoportból legalább egy karaktert tartalmaz.
String generatePassword(PasswordOptions o, {Random? random}) {
  final r = random ?? Random.secure();
  final sets = <String>[
    if (o.lower) _lowerSet,
    if (o.upper) _upperSet,
    if (o.digits) _digitSet,
    if (o.symbols) _symbolSet,
  ];
  if (sets.isEmpty) throw ArgumentError(tr('Legalább egy karaktercsoportot be kell kapcsolni.'));
  if (o.length < sets.length) throw ArgumentError(tr('Túl rövid jelszó a kiválasztott csoportokhoz.'));

  final all = sets.join();
  final chars = <String>[
    for (final s in sets) s[r.nextInt(s.length)],
  ];
  while (chars.length < o.length) {
    chars.add(all[r.nextInt(all.length)]);
  }
  for (var i = chars.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join();
}
