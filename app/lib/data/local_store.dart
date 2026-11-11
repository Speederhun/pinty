import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../crypto/vault_crypto.dart';

/// Egy elem helyi állapota. A tartalom (blob) mindig titkosított, a lemezen sincs nyílt szöveg.
class LocalEntry {
  LocalEntry({this.blob, this.rev = 0, this.deleted = false, this.dirty = false});

  String? blob; // null: törölt elem (sírkő)
  int rev; // a szerveren lévő utolsó ismert revízió (0 = még nem volt fent)
  bool deleted;
  bool dirty; // helyi módosítás, ami még nincs a szerveren

  /// Csak memóriában: minden helyi változtatás növeli, hogy a szinkron közbeni
  /// szerkesztést ne töröljük el tévedésből a "tiszta" jelzéssel.
  int ver = 0;

  Map<String, dynamic> toJson() => {'blob': blob, 'rev': rev, 'deleted': deleted, 'dirty': dirty};

  factory LocalEntry.fromJson(Map<String, dynamic> j) => LocalEntry(
        blob: j['blob'] as String?,
        rev: (j['rev'] as int?) ?? 0,
        deleted: (j['deleted'] as bool?) ?? false,
        dirty: (j['dirty'] as bool?) ?? false,
      );
}

/// A fiók adatai az eszközön. Nem titkosak: a kulcsokat csak a mesterjelszó nyitja.
class LocalMeta {
  LocalMeta({
    required this.serverUrl,
    required this.email,
    required this.kdf,
    required this.wrappedKey,
  });

  final String serverUrl;
  final String email;
  final KdfParams kdf;
  final String wrappedKey;

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'email': email,
        'kdf': kdf.toJson(),
        'wrappedKey': wrappedKey,
      };

  factory LocalMeta.fromJson(Map<String, dynamic> j) => LocalMeta(
        serverUrl: j['serverUrl'] as String,
        email: j['email'] as String,
        kdf: KdfParams.fromJson(j['kdf'] as Map<String, dynamic>),
        wrappedKey: j['wrappedKey'] as String,
      );
}

class LocalState {
  LocalState({this.meta, this.lastRev = 0, Map<String, LocalEntry>? entries})
      : entries = entries ?? {};

  LocalMeta? meta;
  int lastRev;
  final Map<String, LocalEntry> entries;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'meta': meta?.toJson(),
        'lastRev': lastRev,
        'entries': {for (final e in entries.entries) e.key: e.value.toJson()},
      };

  factory LocalState.fromJson(Map<String, dynamic> j) => LocalState(
        meta: j['meta'] == null ? null : LocalMeta.fromJson(j['meta'] as Map<String, dynamic>),
        lastRev: (j['lastRev'] as int?) ?? 0,
        entries: {
          for (final e in ((j['entries'] as Map<String, dynamic>?) ?? {}).entries)
            e.key: LocalEntry.fromJson(e.value as Map<String, dynamic>),
        },
      );
}

abstract class LocalStore {
  Future<LocalState> load();
  Future<void> save(LocalState state);
  Future<void> wipe();
}

/// Tesztekhez.
class MemoryLocalStore implements LocalStore {
  String? _data;

  @override
  Future<LocalState> load() async =>
      _data == null ? LocalState() : LocalState.fromJson(jsonDecode(_data!) as Map<String, dynamic>);

  @override
  Future<void> save(LocalState state) async => _data = jsonEncode(state.toJson());

  @override
  Future<void> wipe() async => _data = null;
}

/// Fájlban tárol; írás közben ideiglenes fájlt használ, hogy áramszünet se rontsa el a széfet.
class FileLocalStore implements LocalStore {
  FileLocalStore(this.file);

  final File file;

  static Future<FileLocalStore> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return FileLocalStore(File('${dir.path}${Platform.pathSeparator}pinty_vault.json'));
  }

  @override
  Future<LocalState> load() async {
    if (!await file.exists()) return LocalState();
    return LocalState.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
  }

  @override
  Future<void> save(LocalState state) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> wipe() async {
    if (await file.exists()) await file.delete();
  }
}
