import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../crypto/vault_crypto.dart';
import '../models/vault_item.dart';
import '../util/totp.dart' show extractTotpSecret;

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A titkosított mentés ("pinty-backup") formátuma: JSON-borító, benne az Argon2id paraméterek és egy
/// XChaCha20-Poly1305 blob. A kulcs a mentéskor megadott jelszóból származik, nem a mesterjelszóból.
class Backup {
  static const format = 'pinty-backup';

  /// Csak az "élő" elemeket menti (kuka nélkül): jelszavak, jegyzetek, mappák, csatolt képek.
  static Future<Uint8List> export(Iterable<VaultItem> items, String password, {KdfParams? kdf}) async {
    if (password.length < 8) throw BackupException('A mentés jelszava legalább 8 karakter legyen.');
    final params = kdf ?? KdfParams(salt: VaultCrypto.randomBytes(16));
    final key = await VaultCrypto.deriveBackupKeyAsync(password, params);
    final payload = jsonEncode({
      'items': [for (final i in items) if (!i.inTrash) i.toJson()],
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
    });
    final blob = await VaultCrypto.encryptBytes(utf8.encode(payload), key, aad: utf8.encode(format));
    return Uint8List.fromList(utf8.encode(jsonEncode({'format': format, 'v': 1, 'kdf': params.toJson(), 'blob': blob})));
  }

  static Future<List<VaultItem>> import(Uint8List bytes, String password) async {
    final Map<String, dynamic> env;
    try {
      env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('Ez nem Pinty-mentés.');
    }
    if (env['format'] != format) throw BackupException('Ez nem Pinty-mentés.');
    final KdfParams kdf;
    try {
      kdf = KdfParams.fromJson(env['kdf'] as Map<String, dynamic>);
    } catch (_) {
      throw BackupException('A mentés sérült.');
    }
    // védelem a rosszindulatú, irreálisan nagy paraméterek ellen
    if (kdf.memoryKiB > 1 << 20 || kdf.iterations > 20 || kdf.parallelism > 16) {
      throw BackupException('A mentés paraméterei érvénytelenek.');
    }
    final key = await VaultCrypto.deriveBackupKeyAsync(password, kdf);
    final List<int> plain;
    try {
      plain = await VaultCrypto.decryptBytes(env['blob'] as String, key, aad: utf8.encode(format));
    } catch (_) {
      throw BackupException('Hibás jelszó, vagy sérült mentés.');
    }
    final data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return [
      for (final j in (data['items'] as List? ?? const []))
        if (j is Map<String, dynamic> && j['id'] is String) VaultItem.fromJson(j)
    ];
  }
}

// ---------- CSV ----------

/// RFC 4180 szerinti CSV-olvasó (idézőjeles mezők, kettőzött idézőjel, sortörés a mezőben, BOM).
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var any = false;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (any || row.length > 1) rows.add(row);
    row = <String>[];
    any = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
      any = true;
    } else if (c == ',') {
      endCell();
      any = true;
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      cell.write(c);
      any = true;
    }
  }
  if (cell.isNotEmpty || any || row.isNotEmpty) endRow();
  return rows;
}

String csvEscape(String s) =>
    (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) ? '"${s.replaceAll('"', '""')}"' : s;

/// Titkosítatlan CSV-export (más programba költözéshez). Az oszlopok a Chrome/Bitwarden nevezéktanát követik.
String exportCsv(Iterable<VaultItem> items) {
  final b = StringBuffer('folder,favorite,name,url,username,password,totp,notes\n');
  for (final i in items) {
    if (i.kind != ItemKind.login || i.inTrash) continue;
    b.writeln([
      i.folder,
      i.favorite ? '1' : '',
      i.name,
      i.url,
      i.username,
      i.password,
      i.totpSecret,
      i.notes,
    ].map(csvEscape).join(','));
  }
  return b.toString();
}

class ImportResult {
  ImportResult(this.items, this.skipped);
  final List<VaultItem> items;
  final int skipped;
}

/// Chrome, Edge, Firefox, Bitwarden, 1Password, LastPass és hasonló CSV-k felismerése fejléc alapján.
ImportResult importCsv(String text) {
  final rows = parseCsv(text);
  if (rows.length < 2) throw BackupException('Üres vagy érvénytelen CSV.');
  final header = [for (final h in rows.first) h.trim().toLowerCase()];

  int col(List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final cName = col(['name', 'title', 'login_name']);
  final cUrl = col(['url', 'login_uri', 'website', 'web site', 'uri']);
  final cUser = col(['username', 'login_username', 'login', 'user', 'email']);
  final cPass = col(['password', 'login_password', 'pass']);
  final cNotes = col(['notes', 'note', 'extra', 'comments']);
  final cTotp = col(['login_totp', 'totp', 'otpauth', 'otp']);
  final cFolder = col(['folder', 'grouping', 'group']);
  final cFav = col(['favorite', 'fav']);
  final cType = col(['type']);
  if (cPass < 0 && cNotes < 0) throw BackupException('Nem ismerem fel a CSV oszlopait (nincs jelszó vagy jegyzet oszlop).');

  String at(List<String> r, int c) => c >= 0 && c < r.length ? r[c].trim() : '';

  final out = <VaultItem>[];
  var skipped = 0;
  for (final r in rows.skip(1)) {
    final type = at(r, cType).toLowerCase();
    final url = at(r, cUrl);
    var name = at(r, cName);
    if (name.isEmpty) name = Uri.tryParse(url.contains('://') ? url : 'https://$url')?.host ?? '';
    final pass = at(r, cPass);
    final notes = cNotes >= 0 && cNotes < r.length ? r[cNotes] : '';
    if (name.isEmpty && pass.isEmpty && notes.trim().isEmpty) {
      skipped++;
      continue;
    }
    // Bitwarden "securenote": jegyzetként érkezik
    final isNote = type == 'securenote' || type == 'note' || (pass.isEmpty && at(r, cUser).isEmpty && url.isEmpty);
    out.add(VaultItem(
      id: const Uuid().v4(),
      name: name.isEmpty ? 'Névtelen' : name,
      kind: isNote ? ItemKind.note : ItemKind.login,
      username: at(r, cUser),
      password: pass,
      url: url,
      notes: notes,
      totpSecret: extractTotpSecret(at(r, cTotp)),
      folder: at(r, cFolder),
      favorite: {'1', 'true', 'yes'}.contains(at(r, cFav).toLowerCase()),
    ));
  }
  return ImportResult(out, skipped);
}

/// Bitwarden JSON-export (titkosítatlan).
ImportResult importBitwardenJson(String text) {
  final Map<String, dynamic> root;
  try {
    root = jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    throw BackupException('Érvénytelen JSON.');
  }
  if (root['encrypted'] == true) throw BackupException('A titkosított Bitwarden-exportot nem tudom beolvasni. Exportálj titkosítatlan JSON-t.');
  final folders = {
    for (final f in (root['folders'] as List? ?? const []))
      if (f is Map<String, dynamic>) f['id']: (f['name'] as String?) ?? ''
  };
  final out = <VaultItem>[];
  var skipped = 0;
  for (final raw in (root['items'] as List? ?? const [])) {
    if (raw is! Map<String, dynamic>) {
      skipped++;
      continue;
    }
    final type = raw['type'];
    final folder = folders[raw['folderId']] ?? '';
    final name = (raw['name'] as String?) ?? 'Névtelen';
    final notes = (raw['notes'] as String?) ?? '';
    final fav = raw['favorite'] == true;
    if (type == 1) {
      final login = (raw['login'] as Map<String, dynamic>?) ?? const {};
      final uris = (login['uris'] as List?) ?? const [];
      final uri = uris.isNotEmpty && uris.first is Map ? ((uris.first as Map)['uri'] as String?) ?? '' : '';
      out.add(VaultItem(
        id: const Uuid().v4(),
        name: name,
        username: (login['username'] as String?) ?? '',
        password: (login['password'] as String?) ?? '',
        url: uri,
        notes: notes,
        totpSecret: extractTotpSecret((login['totp'] as String?) ?? ''),
        folder: folder,
        favorite: fav,
      ));
    } else if (type == 2) {
      out.add(VaultItem(id: const Uuid().v4(), name: name, kind: ItemKind.note, notes: notes, folder: folder));
    } else {
      skipped++; // kártya, személyazonosság: nincs megfelelője
    }
  }
  return ImportResult(out, skipped);
}
