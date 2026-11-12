import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../api/pinty_api.dart';
import '../crypto/vault_crypto.dart';
import '../models/vault_item.dart';
import '../util/recovery_code.dart';
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
  List<VaultItem> get items => _ofKind(ItemKind.login).where((i) => !i.inTrash).toList();

  /// A jegyzetek.
  List<VaultItem> get notes => _ofKind(ItemKind.note).where((i) => !i.inTrash).toList();

  /// Minden nem kukás elem (jelszavak, jegyzetek, képek, mappák) mentéshez.
  List<VaultItem> get liveItems => _items.values.where((i) => !i.inTrash).toList();

  /// A kukában lévő jelszavak és jegyzetek (legutóbb törölt elöl).
  List<VaultItem> get trash {
    final list = _items.values.where((i) => i.inTrash && i.kind != ItemKind.file && i.kind != ItemKind.folder).toList();
    list.sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));
    return list;
  }

  /// Az összes (kukás is) elem egy fajtából, belső műveletekhez (pl. mappa átnevezése).
  List<VaultItem> allOfKind(String kind) => _items.values.where((i) => i.kind == kind).toList();

  /// A létrehozott mappák (üresek is) az adott részhez (`login` vagy `note`).
  List<String> folderPaths(String scope) =>
      (_items.values.where((i) => i.kind == ItemKind.folder && i.scope == scope).map((i) => i.name).toList()..sort());

  Future<void> trashItem(VaultItem item) async {
    item.trashedAt = DateTime.now().toUtc();
    await upsert(item);
  }

  Future<void> restoreItem(VaultItem item) async {
    item.trashedAt = null;
    await upsert(item);
  }

  /// A 30 napnál régebben kukába tett elemek végleges törlése. Visszaadja, hányat törölt.
  Future<int> purgeTrash({Duration keep = const Duration(days: 30)}) async {
    final cutoff = DateTime.now().toUtc().subtract(keep);
    final old = [for (final i in trash) if (i.trashedAt!.isBefore(cutoff)) i.id];
    for (final id in old) {
      await delete(id);
    }
    return old.length;
  }

  /// A jegyzetekhez csatolt fájlok.
  List<VaultItem> get files => _ofKind(ItemKind.file);

  /// A szerver blobonkénti korlátja 8 MiB (base64-ben), ezért a titkosítás előtti JSON ennyit
  /// bírhat el biztonságosan.
  static const maxItemBytes = 5500000;

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

  // ---------- mesterjelszó, visszaállító kulcs, biometria ----------

  /// Mesterjelszó cseréje. A széfkulcs változatlan marad (így a tárolt elemeket nem kell újratitkosítani),
  /// csak a mesterkulcsból származó burkolat és a hitelesítés cserélődik. A szerver minden más
  /// munkamenetet érvénytelenít.
  Future<void> changeMasterPassword({required String oldPassword, required String newPassword}) async {
    final vk = _requireKey();
    final meta = _state.meta!;
    final oldKeys = await VaultCrypto.deriveMasterKeysAsync(oldPassword, meta.kdf);
    try {
      await VaultCrypto.unwrapVaultKey(meta.wrappedKey, oldKeys.encKey);
    } catch (_) {
      throw VaultException('A jelenlegi mesterjelszó hibás.');
    }
    final newKdf = _newKdf();
    final newKeys = await VaultCrypto.deriveMasterKeysAsync(newPassword, newKdf);
    final newWrapped = await VaultCrypto.wrapVaultKey(vk, newKeys.encKey);

    final api = apiFactory(meta.serverUrl);
    await api.login(meta.email, oldKeys.authHash);
    try {
      await api.changePassword(
        authHash: oldKeys.authHash,
        newAuthHash: newKeys.authHash,
        newKdf: newKdf,
        newWrappedKey: newWrapped,
      );
    } finally {
      try {
        await api.logout();
      } catch (_) {}
    }
    _state.meta = LocalMeta(serverUrl: meta.serverUrl, email: meta.email, kdf: newKdf, wrappedKey: newWrapped);
    await store.save(_state);
    _keys = newKeys;
  }

  /// Új visszaállító kulcs készítése és feltöltése (a régi érvénytelenné válik).
  /// A kulcs szöveges alakját csak ez a hívás adja vissza; sehol nincs eltárolva.
  Future<String> createRecoveryKey() async {
    final vk = _requireKey();
    final meta = _state.meta!;
    final raw = VaultCrypto.randomBytes(32);
    final (wrapKey, proof) = await VaultCrypto.deriveRecovery(raw);
    final wrapped = await VaultCrypto.wrapVaultKeyForRecovery(vk, wrapKey);
    final api = apiFactory(meta.serverUrl);
    await api.login(meta.email, _keys!.authHash);
    try {
      await api.setRecovery(proof, wrapped);
    } finally {
      try {
        await api.logout();
      } catch (_) {}
    }
    return formatRecoveryKey(raw);
  }

  Future<bool> recoveryEnabled() async {
    final meta = _state.meta!;
    final api = apiFactory(meta.serverUrl);
    await api.login(meta.email, _keys!.authHash);
    try {
      return await api.recoveryEnabled();
    } finally {
      try {
        await api.logout();
      } catch (_) {}
    }
  }

  /// Elfelejtett mesterjelszó: a visszaállító kulccsal új mesterjelszót állít be, majd bejelentkeztet.
  Future<void> recoverAccount({
    required String serverUrl,
    required String email,
    required String recoveryKey,
    required String newPassword,
  }) async {
    final url = _normUrl(serverUrl);
    final mail = _normEmail(email);
    final api = apiFactory(url);

    final Uint8List raw;
    try {
      raw = parseRecoveryKey(recoveryKey);
    } on FormatException catch (e) {
      throw VaultException(e.message);
    }
    final (wrapKey, proof) = await VaultCrypto.deriveRecovery(raw);
    final wrappedForRecovery = await api.recoverFetch(mail, proof);
    SecretKey vk;
    try {
      vk = await VaultCrypto.unwrapVaultKeyForRecovery(wrappedForRecovery, wrapKey);
    } catch (_) {
      throw VaultException('A visszaállító kulcs nem nyitja a széfet.');
    }
    final newKdf = _newKdf();
    final newKeys = await VaultCrypto.deriveMasterKeysAsync(newPassword, newKdf);
    final newWrapped = await VaultCrypto.wrapVaultKey(vk, newKeys.encKey);
    await api.recoverReset(
      email: mail,
      recoveryAuth: proof,
      newAuthHash: newKeys.authHash,
      newKdf: newKdf,
      newWrappedKey: newWrapped,
    );
    _state = LocalState(meta: LocalMeta(serverUrl: url, email: mail, kdf: newKdf, wrappedKey: newWrapped));
    await store.save(_state);
    _keys = newKeys;
    _vaultKey = vk;
    _items.clear();
    await sync();
  }

  /// A biometrikus feloldáshoz eltárolandó adatok (a mesterkulcs és a hitelesítő hash).
  /// Csak feloldott állapotban hívható; a hívó felelőssége, hogy biztonságos tárolóba tegye.
  Future<Map<String, String>> exportUnlockSecrets() async {
    _requireKey();
    final keys = _keys!;
    return {'enc': base64.encode(await keys.encKey.extractBytes()), 'auth': keys.authHash};
  }

  /// Feloldás a mesterjelszó nélkül, a [exportUnlockSecrets] által adott adatokból.
  Future<void> unlockWithSecrets(Map<String, String> secrets) async {
    final meta = _state.meta;
    if (meta == null) throw VaultException('Nincs beállított fiók.');
    final enc = SecretKey(base64.decode(secrets['enc'] ?? ''));
    SecretKey vaultKey;
    try {
      vaultKey = await VaultCrypto.unwrapVaultKey(meta.wrappedKey, enc);
    } catch (_) {
      throw VaultException('A mentett kulcs már nem érvényes. Oldd fel a mesterjelszóval.');
    }
    _keys = MasterKeys(enc, secrets['auth'] ?? '');
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
      throw VaultException('Túl nagy elem (legfeljebb kb. ${maxItemBytes ~/ 1000000} MB lehet). Bontsd több részre.');
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
