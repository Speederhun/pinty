import 'dart:convert';
import 'dart:typed_data';

import '../i18n.dart';
import '../models/vault_item.dart';

/// Jegyzetek exportja titkosítatlan zip-be: minden jegyzet egy `.md` fájl a mappája szerint,
/// a képek az `attachments/` mappába kerülnek. Az Obsidian közvetlenül megnyitja.
Uint8List exportNotesZip(Iterable<VaultItem> notes, Iterable<VaultItem> files) {
  final used = <String>{};
  final entries = <(String, Uint8List)>[];

  String unique(String path) {
    var candidate = path;
    final dot = path.lastIndexOf('.');
    final stem = dot > 0 ? path.substring(0, dot) : path;
    final ext = dot > 0 ? path.substring(dot) : '';
    var n = 2;
    while (!used.add(candidate.toLowerCase())) {
      candidate = '$stem ($n)$ext';
      n++;
    }
    return candidate;
  }

  for (final n in notes) {
    if (n.inTrash) continue;
    final folder = n.folder.split('/').map(safeName).where((s) => s.isNotEmpty).join('/');
    final title = safeName(n.name);
    final path = unique('${folder.isEmpty ? '' : '$folder/'}${title.isEmpty ? tr('Névtelen') : title}.md');
    entries.add((path, Uint8List.fromList(utf8.encode(n.notes))));
  }
  for (final f in files) {
    if (f.inTrash) continue;
    try {
      entries.add((unique('attachments/${safeName(f.name)}'), base64Decode(f.data)));
    } catch (_) {}
  }
  return buildZip(entries);
}

/// Fájlnévbe nem illő karakterek cseréje.
String safeName(String s) {
  final r = s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return r == '.' || r == '..' ? '_' : r;
}

final List<int> _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Tömörítetlen ("store") zip, UTF-8 fájlnevekkel.
Uint8List buildZip(List<(String, Uint8List)> entries) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  const dosTime = 0;
  const dosDate = (2026 - 1980) << 9 | 1 << 5 | 1;

  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  for (final (name, data) in entries) {
    final nameBytes = utf8.encode(name);
    final crc = crc32(data);
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0x0800);
    u16(out, 0);
    u16(out, dosTime);
    u16(out, dosDate);
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, nameBytes.length);
    u16(out, 0);
    out.add(nameBytes);
    out.add(data);

    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, dosTime);
    u16(central, dosDate);
    u32(central, crc);
    u32(central, data.length);
    u32(central, data.length);
    u16(central, nameBytes.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(nameBytes);
  }
  final centralOffset = out.length;
  final centralBytes = central.toBytes();
  out.add(centralBytes);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, entries.length);
  u16(out, entries.length);
  u32(out, centralBytes.length);
  u32(out, centralOffset);
  u16(out, 0);
  return out.toBytes();
}
