import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/i18n.dart';
import 'package:pinty/util/password_generator.dart';
import 'package:pinty/util/totp.dart';

void main() {
  setLang('hu');
  group('TOTP (RFC 6238 tesztvektorok, SHA1)', () {
    const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'; // "12345678901234567890"

    DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

    test('8 jegyű kódok', () {
      expect(totpCode(secret, at: at(59), digits: 8), '94287082');
      expect(totpCode(secret, at: at(1111111109), digits: 8), '07081804');
      expect(totpCode(secret, at: at(20000000000), digits: 8), '65353130');
    });

    test('6 jegyű kód', () {
      expect(totpCode(secret, at: at(59)), '287082');
    });

    test('kisbetűs, szóközös kulcs és otpauth hivatkozás is jó', () {
      expect(totpCode('gezd gnbv gy3t qojq gezd gnbv gy3t qojq', at: at(59)), '287082');
      expect(totpCode('otpauth://totp/Teszt?secret=$secret&issuer=X', at: at(59)), '287082');
    });

    test('érvénytelen kulcs hibát dob', () {
      expect(() => totpCode('1!?', at: at(59)), throwsFormatException);
      expect(() => totpCode('', at: at(59)), throwsFormatException);
    });

    test('hátralévő idő', () {
      expect(totpRemaining(at: at(30)), 30);
      expect(totpRemaining(at: at(59)), 1);
    });
  });

  group('jelszógenerátor', () {
    test('a kért hosszúságú, és minden csoportból tartalmaz', () {
      final r = Random(42);
      for (var i = 0; i < 50; i++) {
        final p = generatePassword(const PasswordOptions(length: 12), random: r);
        expect(p.length, 12);
        expect(RegExp(r'[a-z]').hasMatch(p), isTrue);
        expect(RegExp(r'[A-Z]').hasMatch(p), isTrue);
        expect(RegExp(r'[0-9]').hasMatch(p), isTrue);
        expect(RegExp(r'[^a-zA-Z0-9]').hasMatch(p), isTrue);
      }
    });

    test('csak számok', () {
      final p = generatePassword(
        const PasswordOptions(length: 16, lower: false, upper: false, symbols: false),
      );
      expect(RegExp(r'^[0-9]{16}$').hasMatch(p), isTrue);
    });

    test('csoport nélkül hibát dob', () {
      expect(
        () => generatePassword(
          const PasswordOptions(lower: false, upper: false, digits: false, symbols: false),
        ),
        throwsArgumentError,
      );
    });

    test('két generálás különbözik', () {
      expect(generatePassword(const PasswordOptions()), isNot(generatePassword(const PasswordOptions())));
    });
  });
}
