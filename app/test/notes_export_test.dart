import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/data/notes_export.dart';
import 'package:pinty/models/vault_item.dart';

void main() {
  test('crc32 ismert értékkel', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  });

  test('zip: fejlécek, fájlnevek, ütköző nevek, kuka kihagyva', () {
    final notes = [
      VaultItem(id: '1', name: 'Terv', kind: ItemKind.note, folder: 'Munka/2026', notes: 'Szia [[B]]'),
      VaultItem(id: '2', name: 'Terv', kind: ItemKind.note, folder: 'Munka/2026', notes: 'másik'),
      VaultItem(id: '3', name: 'a/b:c', kind: ItemKind.note, notes: 'x'),
      VaultItem(id: '4', name: 'Trashed', kind: ItemKind.note, notes: 'x', trashedAt: DateTime.now().toUtc()),
    ];
    final img = VaultItem(id: '5', name: 'kep.png', kind: ItemKind.file, mime: 'image/png', data: base64Encode([1, 2, 3]));
    final zip = exportNotesZip(notes, [img]);
    final text = latin1.decode(zip);
    expect(text.startsWith('PK\x03\x04'), isTrue);
    expect(text.contains('Munka/2026/Terv.md'), isTrue);
    expect(text.contains('Munka/2026/Terv (2).md'), isTrue);
    expect(text.contains('a_b_c.md'), isTrue);
    expect(text.contains('attachments/kep.png'), isTrue);
    expect(text.contains('Trashed'), isFalse);
    // záró rekord: 4 bejegyzés
    final eocd = zip.length - 22;
    expect(zip[eocd], 0x50);
    expect(zip[eocd + 10], 4);
  });
}
