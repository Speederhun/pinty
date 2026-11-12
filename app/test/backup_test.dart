import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/crypto/vault_crypto.dart';
import 'package:pinty/data/backup.dart';
import 'package:pinty/models/vault_item.dart';
import 'package:pinty/util/recovery_code.dart';

KdfParams _fast() => KdfParams(
      salt: Uint8List.fromList(List.generate(16, (i) => i + 1)),
      memoryKiB: 1024,
      iterations: 1,
      parallelism: 1,
    );

void main() {
  test('titkosított mentés: oda-vissza, hibás jelszó, nincs nyílt szöveg', () async {
    final items = [
      VaultItem(id: 'a', name: 'GitHub', password: 'titkos-123', notes: 'szupertitkos'),
      VaultItem(id: 'b', name: 'Jegyzet', kind: ItemKind.note, notes: 'Lásd [[Másik]]', folder: 'Munka'),
      VaultItem(id: 'c', name: 'Kuka', trashedAt: DateTime.now().toUtc()),
    ];
    final bytes = await Backup.export(items, 'mentes-jelszo', kdf: _fast());
    final text = utf8.decode(bytes);
    expect(text.contains('titkos-123'), isFalse);
    expect(text.contains('GitHub'), isFalse);

    final back = await Backup.import(bytes, 'mentes-jelszo');
    expect(back.map((i) => i.id), ['a', 'b']);
    expect(back.first.password, 'titkos-123');
    expect(back.last.folder, 'Munka');

    expect(() => Backup.import(bytes, 'rossz-jelszo'), throwsA(isA<BackupException>()));
    expect(() => Backup.import(Uint8List.fromList(utf8.encode('{}')), 'x'), throwsA(isA<BackupException>()));
    expect(() => Backup.export(items, 'rovid'), throwsA(isA<BackupException>()));
  });

  test('CSV-olvasó: idézőjel, vessző, sortörés a mezőben, BOM, CRLF', () {
    final rows = parseCsv('﻿a,b,c\r\n1,"x, y","sor1\nsor2"\r\n"idéz ""jel""",,3\r\n');
    expect(rows, [
      ['a', 'b', 'c'],
      ['1', 'x, y', 'sor1\nsor2'],
      ['idéz "jel"', '', '3'],
    ]);
  });

  test('Chrome CSV import', () {
    final r = importCsv('name,url,username,password,note\n'
        'GitHub,https://github.com,me,pw1,jegyzet\n'
        ',https://example.org,u2,pw2,\n'
        ',,,,\n');
    expect(r.items.length, 2);
    expect(r.skipped, 1);
    expect(r.items[0].kind, ItemKind.login);
    expect(r.items[0].password, 'pw1');
    expect(r.items[1].name, 'example.org'); // név a gazdagépből
  });

  test('Bitwarden CSV import: mappa, kedvenc, TOTP, biztonságos jegyzet', () {
    final r = importCsv('folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n'
        'Munka,1,login,Szerver,,,0,https://s.example,root,pw,otpauth://totp/x?secret=JBSWY3DPEHPK3PXP\n'
        ',,note,Titok,csak szöveg,,0,,,,\n');
    expect(r.items.length, 2);
    final a = r.items[0];
    expect(a.folder, 'Munka');
    expect(a.favorite, isTrue);
    expect(a.totpSecret, 'JBSWY3DPEHPK3PXP');
    expect(r.items[1].kind, ItemKind.note);
  });

  test('ismeretlen CSV hibát ad', () {
    expect(() => importCsv('a,b\n1,2\n'), throwsA(isA<BackupException>()));
  });

  test('Bitwarden JSON import', () {
    final r = importBitwardenJson(jsonEncode({
      'folders': [
        {'id': 'f1', 'name': 'Otthon'}
      ],
      'items': [
        {
          'type': 1,
          'name': 'Wifi',
          'folderId': 'f1',
          'favorite': true,
          'login': {
            'username': 'u',
            'password': 'p',
            'uris': [
              {'uri': 'http://router'}
            ]
          }
        },
        {'type': 2, 'name': 'Jegyzet', 'notes': 'szöveg'},
        {'type': 3, 'name': 'Kártya'},
      ],
    }));
    expect(r.items.length, 2);
    expect(r.skipped, 1);
    expect(r.items[0].folder, 'Otthon');
    expect(r.items[0].url, 'http://router');
    expect(r.items[1].kind, ItemKind.note);
  });

  test('CSV-export és -import köre', () {
    final csv = exportCsv([
      VaultItem(id: '1', name: 'A, "B"', username: 'u', password: 'p,q', url: 'https://x', notes: 'a\nb', folder: 'F'),
    ]);
    final r = importCsv(csv);
    expect(r.items.single.name, 'A, "B"');
    expect(r.items.single.password, 'p,q');
    expect(r.items.single.notes, 'a\nb');
  });

  test('visszaállító kulcs kódolása', () {
    final raw = VaultCrypto.randomBytes(32);
    final text = formatRecoveryKey(raw);
    expect(text.length, 52 + 12); // 52 karakter + 12 kötőjel
    expect(parseRecoveryKey(text.toLowerCase().replaceAll('-', ' ')), raw);
    expect(() => parseRecoveryKey('ABCD-EFGH'), throwsFormatException);
  });
}
