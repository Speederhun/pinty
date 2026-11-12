import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/en.dart';
import 'package:pinty/i18n.dart';

void main() {
  tearDown(() => setLang('en'));

  test('az angol az alapértelmezett, a magyar visszakapcsolható', () {
    setLang('en');
    expect(tr('Mégse'), 'Cancel');
    expect(trf('%1 jegyzet exportálva.', [3]), '3 notes exported.');
    setLang('hu');
    expect(tr('Mégse'), 'Mégse');
    expect(trf('%1 jegyzet exportálva.', [3]), '3 jegyzet exportálva.');
  });

  test('fordítatlan szöveg változatlan marad, a szerver hibaüzenetei fordulnak', () {
    setLang('en');
    expect(tr('Nincs ilyen szöveg'), 'Nincs ilyen szöveg');
    expect(tr('túl sok próbálkozás'), 'too many attempts');
  });

  test('minden fordításban ugyanazok a %n jelölők', () {
    final ph = RegExp(r'%\d');
    enStrings.forEach((hu, en) {
      expect(ph.allMatches(en).map((m) => m.group(0)).toList()..sort(),
          ph.allMatches(hu).map((m) => m.group(0)).toList()..sort(),
          reason: hu);
    });
  });
}
