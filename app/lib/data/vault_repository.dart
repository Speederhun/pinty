import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../api/pinty_api.dart';
import '../crypto/vault_crypto.dart';
import '../models/vault_item.dart';
import 'local_store.dart';

class VaultException implements Exception {
  VaultException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SyncReport {
  SyncReport({this.pushed = 0, this.pulled = 0, this.conflicts = 0});
  int pushed;
  int pulled;
  int conflicts;
}

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// A széf teljes logikája: fiók létrehozás, feloldás, helyi (titkosított) tárolás és szinkron.
///
/// A mesterjelszó és a kulcsok csak memóriában élnek, zároláskor törlődnek.
/// A lemezre és a szerverre kizárólag titkosított blob kerül.
class VaultRepository {
  VaultRepository({
    required this.store,
    required this.apiFactory,
    KdfParams Function()? newKdf,
  }) : _newKdf = newKdf ?? _defaultKdf;

  final LocalStore store;
  final RemoteApi Function(String baseUrl) apiFactory;
  final KdfParams Function() _newKdf;

  static KdfParams _defaultKdf() => KdfParams(salt: _randomBytes(16));

  LocalState _state = LocalState();
  SecretKey? _vaultKey;
  MasterKeys? _keys;
  final Map<String, VaultItem> _items = {};

  /// Hány elemet nem sikerült visszafejteni az utolsó betöltéskor (sérült blob).
  int undecryptable = 0;

  bool get hasAccount => _state.meta != null;
  bool get isUnlocked => _vaultKey != null;
  LocalMeta? get meta => _state.meta;

  List<VaultItem> _ofKind(String kind) {
    final list = _items.values.where((i) => i.kind == kind).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// A jelszó-bejegyzések.
  List<VaultItem> get items => _ofKind(ItemKind.login);

  /// A jegyzetek.
  List<VaultItem> get notes => _ofKind(ItemKind.note);

  /// A jegyzetekhez csatolt fájlok.
  List<VaultItem> get files => _ofKind(ItemKind.file);

  /// A szerver blobonkénti korlátja 256 KiB (base64-ben), ezért a titkosítás előtti JSON ennyit
  /// bírhat el biztonságosan.
  static const maxItemBytes = 175000;

  Future<void> init() async {
    _state = await store.load();
  }

  SecretKey _requireKey() {
    final k = _vaultKey;
    if (k == null) throw VaultException('A széf zárolva van.');
    return k;
  }

  String _normEmail(String e) => e.trim().toLowerCase();

  String _normUrl(String u) {
    var s = u.trim();
    if (!s.contains('://')) s = 'https://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // ---------- fiók ----------

  /// Új fiók létrehozása a szerveren (az első eszközön).
  Future<void> register({
    required String serverUrl,
    required String email,
    required String password,
    String inviteCode = '',
  }) async {
    final url = _normUrl(serverUrl);
    final mail = _normEmail(email);
    final api = apiFactory(url);

    final kdf = _newKdf();
    final keys = await VaultCrypto.deriveMasterKeysAsync(password, kdf);
    final vaultKey = await VaultCrypto.newVaultKey();
    final wrapped = await VaultCrypto.wrapVaultKey(vaultKey, keys.encKey);

    await api.register(
      email: mail,
      authHash: keys.authHash,
      kdf: kdf,
      wrappedKey: wrapped,
      inviteCode: inviteCode.trim(),
    );

    _state = LocalState(meta: LocalMeta(serverUrl: url, email: mail, kdf: kdf, wrappedKey: wrapped));
    await store.save(_state);
    _keys = keys;
    _vaultKey = vaultKey;
    _items.clear();
  }

  /// Bejelentkezés meglévő fiókba (egy újabb eszközön), majd a széf letöltése.
  Future<void> connect({
    required String serverUrl,
    required String email,
    required String password,
  }) async {
    final url = _normUrl(serverUrl);
    final mail = _normEmail(email);
    final api = apiFactory(url);

    final kdf = await api.prelogin(mail);
    final keys = await VaultCrypto.deriveMasterKeysAsync(password, kdf);
    final res = await api.login(mail, keys.authHash);
    SecretKey vaultKey;
    try {
      vaultKey = await VaultCrypto.unwrapVaultKey(res.wrappedKey, keys.encKey);
    } catch (_) {
      throw VaultException('Hibás mesterjelszó.');
    } finally {
      try {
        await api.logout();
      } catch (_) {}
    }

    _state = LocalState(
      meta: LocalMeta(serverUrl: url, email: mail, kdf: res.kdf, wrappedKey: res.wrappedKey),
    );
    await store.save(_state);
    _keys = keys;
    _vaultKey = vaultKey;
    _items.clear();
    await sync();
  }

  /// Feloldás a mesterjelszóval (a helyi adatokból, hálózat nélkül is működik).
  Future<void> unlock(String password) async {
    final meta = _state.meta;
    if (meta == null) throw VaultException('Nincs beállított fiók.');
    final keys = await VaultCrypto.deriveMasterKeysAsync(password, meta.kdf);
    SecretKey vaultKey;
    try {
      vaultKey = await VaultCrypto.unwrapVaultKey(meta.wrappedKey, keys.encKey);
    } catch (_) {
      throw VaultException('Hibás mesterjelszó.');
    }
    _keys = keys;
    _vaultKey = vaultKey;
    await _decryptAll(vaultKey);
  }

  void lock() {
    _vaultKey = null;
    _keys = null;
    _items.clear();
  }

  /// Kijelentkezés: a helyi másolat törlése (a szerveren lévő adat megmarad).
  Future<void> signOut() async {
    lock();
    await store.wipe();
    _state = LocalState();
  }

  // ---------- elemek ----------

  Future<void> upsert(VaultItem item) async {
    final vk = _requireKey();
    if (utf8.encode(jsonEncode(item.toJson())).length > maxItemBytes) {
      throw VaultException('Túl nagy elem (legfeljebb kb. ${maxItemBytes ~/ 1000} KB lehet). Bontsd több részre.');
    }
    item.updatedAt = DateTime.now().toUtc();
    final blob = await VaultCrypto.encryptItem(item.toJson(), item.id, vk);
    final e = _state.entries[item.id];
    if (e == null) {
      _state.entries[item.id] = LocalEntry(blob: blob, dirty: true)..ver = 1;
    } else {
      e
        ..blob = blob
        ..deleted = false
        ..dirty = true
        ..ver += 1;
    }
    _items[item.id] = item;
    await store.save(_state);
  }

  Future<void> delete(String id) async {
    _requireKey();
    final e = _state.entries[id];
    if (e == null) return;
    e
      ..blob = null
      ..deleted = true
      ..dirty = true
      ..ver += 1;
    _items.remove(id);
    await store.save(_state);
  }

  Future<void> _decryptAll(SecretKey vk) async {
    final fresh = <String, VaultItem>{};
    var bad = 0;
    for (final entry in _state.entries.entries) {
      final en = entry.value;
      if (en.deleted || en.blob == null) continue;
      try {
        final json = await VaultCrypto.decryptItem(en.blob!, entry.key, vk);
        fresh[entry.key] = VaultItem.fromJson(json, rev: en.rev);
      } catch (_) {
        bad++;
      }
    }
    if (_vaultKey == null) return; // közben zároltak
    undecryptable = bad;
    _items
      ..clear()
      ..addAll(fresh);
  }

  // ---------- szinkron ----------

  /// Feltölti a helyi módosításokat, majd letölti a mások módosításait.
  ///
  /// Ütközésnél (két eszközön ugyanazt szerkesztették) a szerveren lévő változat marad,
  /// a helyi változat pedig "(ütköző példány)" néven külön elemként megmarad: semmi nem vész el.
  Future<SyncReport> sync() async {
    final vk = _requireKey();
    final keys = _keys!;
    final meta = _state.meta!;
    final api = apiFactory(meta.serverUrl);
    final report = SyncReport();

    await api.login(meta.email, keys.authHash);
    try {
      await _pushDirty(api, vk, report);
      if (_state.entries.values.any((e) => e.dirty)) {
        await _pushDirty(api, vk, report); // az ütközésből született másolatok
      }

      final res = await api.sync(_state.lastRev);
      for (final r in res.items) {
        final local = _state.entries[r.id];
        if (local != null && local.dirty) continue; // a következő feltöltésnél ütközésként kezeljük
        if (local != null && local.rev >= r.rev) continue; // már megvan
        _state.entries[r.id] = LocalEntry(
          blob: r.deleted ? null : r.blob,
          rev: r.rev,
          deleted: r.deleted,
        );
        report.pulled++;
      }
      _state.lastRev = res.rev;
    } finally {
      try {
        await store.save(_state);
      } catch (_) {}
      try {
        await api.logout();
      } catch (_) {}
    }
    if (_vaultKey != null) await _decryptAll(vk);
    return report;
  }

  Future<void> _pushDirty(RemoteApi api, SecretKey vk, SyncReport report) async {
    for (final id in _state.entries.keys.toList()) {
      final e = _state.entries[id];
      if (e == null || !e.dirty) continue;
      final ver = e.ver;
      try {
        if (e.deleted) {
          if (e.rev == 0) {
            _state.entries.remove(id); // sosem járt a szerveren, nincs mit törölni
            continue;
          }
          e.rev = await api.deleteItem(id, e.rev);
        } else {
          e.rev = await api.putItem(id, e.blob!, e.rev);
        }
        if (e.ver == ver) e.dirty = false; // ha közben újra szerkesztették, marad piszkos
        report.pushed++;
      } on ConflictException catch (c) {
        report.conflicts++;
        await _resolveConflict(id, e, c.current, vk);
      } on ApiException catch (a) {
        if (a.status == 404) {
          e.rev = 0; // a szerveren nincs meg: újként töltjük fel
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> _resolveConflict(String id, LocalEntry local, RemoteItem? cur, SecretKey vk) async {
    if (cur == null) {
      local.rev = 0;
      return;
    }
    if (cur.deleted) {
      if (local.deleted) {
        _state.entries[id] = LocalEntry(rev: cur.rev, deleted: true); // mindketten töröltük
      } else {
        local.rev = cur.rev; // a szerveren törölték, de mi módosítottuk: újraélesztjük
      }
      return;
    }
    if (local.deleted) {
      // mi töröltük, de közben módosították: a módosított változat marad
      _state.entries[id] = LocalEntry(blob: cur.blob, rev: cur.rev);
      return;
    }
    // mindkét oldalon módosították: a szerver változata marad, a miénk másolatként megmarad
    try {
      final mine = await VaultCrypto.decryptItem(local.blob!, id, vk);
      final copyId = const Uuid().v4();
      mine['id'] = copyId;
      mine['name'] = '${mine['name'] ?? ''} (ütköző példány)';
      mine['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      final blob = await VaultCrypto.encryptItem(mine, copyId, vk);
      _state.entries[copyId] = LocalEntry(blob: blob, dirty: true)..ver = 1;
    } catch (_) {
      // ha a sajátunkat sem tudjuk olvasni, nincs mit megőrizni
    }
    _state.entries[id] = LocalEntry(blob: cur.blob, rev: cur.rev);
  }
}
