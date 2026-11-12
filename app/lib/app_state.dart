import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api/pinty_api.dart';
import 'data/vault_repository.dart';
import 'models/vault_item.dart';
import 'theme/pinty_theme.dart';
import 'data/backup.dart';
import 'util/biometric.dart';
import 'util/note_logic.dart';
import 'i18n.dart';

enum Stage { loading, welcome, locked, unlocked }

String friendlyError(Object e) {
  if (e is VaultException) return e.message;
  if (e is ApiException) return tr(e.message);
  if (e is SocketException || e is http.ClientException || e is TimeoutException) {
    return tr('A szerver nem érhető el. Ellenőrizd a címet és a hálózatot.');
  }
  if (e is FormatException) return tr('Érvénytelen szervercím vagy szerverválasz.');
  return trf('Váratlan hiba: %1', [e]);
}

/// Az app állapota: melyik képernyő látszik, a téma, és a széf műveletei.
class AppState extends ChangeNotifier {
  AppState({required this.repo, this.autoLock = const Duration(minutes: 5), UnlockHelper? unlockHelper})
      : unlockHelper = unlockHelper ?? BiometricUnlock();

  final VaultRepository repo;
  final UnlockHelper unlockHelper;
  bool biometricAvailable = false;
  bool biometricEnabled = false;

  /// Új fiók után true: a főképernyő felajánlja a visszaállító kulcs elkészítését.
  bool recoveryHint = false;

  /// Ennyi tétlenség után a széf magától zárolódik.
  final Duration autoLock;

  PintyThemeId theme = PintyThemeId.light;
  Stage stage = Stage.loading;
  bool busy = false;
  String? error;
  String? syncStatus;
  String? selectedId;
  String? selectedNoteId;
  int tab = 0; // 0 = jelszavak, 1 = jegyzetek

  Timer? _idle;
  Timer? _periodic;
  Timer? _debounce;
  bool _syncing = false;

  List<VaultItem> get items => repo.items;

  NoteIndex? _noteIdx;

  /// A jegyzetek kapcsolati térképe (visszahivatkozások, címkék, mappák); változáskor újraépül.
  NoteIndex get noteIndex => _noteIdx ??= NoteIndex(repo.notes, repo.files, repo.folderPaths('note'));

  @override
  void notifyListeners() {
    _noteIdx = null;
    super.notifyListeners();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  VaultItem? get selectedNote => selectedNoteId == null ? null : noteIndex.byId(selectedNoteId!);

  void selectNote(String? id) {
    selectedNoteId = id;
    notifyListeners();
  }

  /// Új, üres jegyzet (opcionálisan kezdőszöveggel); kijelöli.
  Future<VaultItem> newNote({String title = '', String folder = '', String body = ''}) async {
    final taken = {for (final n in repo.notes) n.name.toLowerCase()};
    var name = title.trim().isEmpty ? tr('Névtelen jegyzet') : title.trim();
    var candidate = name;
    for (var i = 2; taken.contains(candidate.toLowerCase()); i++) {
      candidate = '$name $i';
    }
    final note = VaultItem(id: const Uuid().v4(), name: candidate, kind: ItemKind.note, folder: folder, notes: body);
    await saveNote(note);
    return note;
  }

  /// Jegyzet mentése. Ha a cím megváltozott, a többi jegyzetben a rá mutató [[linkeket]] is átírja.
  Future<void> saveNote(VaultItem note, {String? oldTitle}) async {
    await repo.upsert(note);
    if (oldTitle != null && oldTitle.trim().isNotEmpty && oldTitle.trim().toLowerCase() != note.name.trim().toLowerCase()) {
      for (final other in repo.notes) {
        if (other.id == note.id) continue;
        final updated = renameLinks(other.notes, oldTitle, note.name);
        if (updated != other.notes) {
          other.notes = updated;
          await repo.upsert(other);
        }
      }
    }
    selectedNoteId = note.id;
    notifyListeners();
    _scheduleSync();
  }

  /// A mai napi jegyzet (létrehozza, ha még nincs). A "Sablonok/Napi" nevű jegyzet a sablonja.
  Future<VaultItem> openDaily([DateTime? now]) async {
    final day = now ?? DateTime.now();
    final title = dateTitle(day);
    final existing = noteIndex.resolve(title);
    if (existing != null) {
      selectNote(existing.id);
      return existing;
    }
    final tpl = noteIndex.notes.where((n) => n.folder == 'Sablonok' && n.name.toLowerCase() == 'napi').firstOrNull;
    final body = tpl != null ? applyTemplate(tpl.notes, title: title, now: day) : trf('# %1\n\n## Teendők\n- [ ] \n\n## Jegyzetek\n', [title]);
    return newNote(title: title, folder: 'Napi', body: body);
  }

  static const maxImageBytes = 3 * 1024 * 1024;

  /// Kép csatolása a széfhez (a jegyzetekben `![[név]]`-vel beágyazható). A neve egyedi lesz.
  Future<VaultItem> addImage(String name, Uint8List bytes) async {
    if (bytes.length > maxImageBytes) {
      throw VaultException(trf('A kép legfeljebb %1 MB lehet.', [maxImageBytes ~/ (1024 * 1024)]));
    }
    final lower = name.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.gif')
            ? 'image/gif'
            : lower.endsWith('.webp')
                ? 'image/webp'
                : (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
                    ? 'image/jpeg'
                    : '';
    if (mime.isEmpty) throw VaultException(tr('Csak PNG, JPG, GIF vagy WebP kép csatolható.'));
    var unique = name;
    for (var i = 2; noteIndex.fileByName(unique) != null; i++) {
      final dot = name.lastIndexOf('.');
      unique = '${name.substring(0, dot)}-$i${name.substring(dot)}';
    }
    final f = VaultItem(id: const Uuid().v4(), name: unique, kind: ItemKind.file, mime: mime, data: base64Encode(bytes));
    await repo.upsert(f);
    notifyListeners();
    _scheduleSync();
    return f;
  }
  String get email => repo.meta?.email ?? '';
  String get serverUrl => repo.meta?.serverUrl ?? '';

  VaultItem? get selected {
    final list = items;
    for (final i in list) {
      if (i.id == selectedId) return i;
    }
    return list.isEmpty ? null : list.first;
  }

  /// Az app nyelve: `en` (alap) vagy `hu`.
  String lang = 'en';

  Future<void> setLanguage(String code) async {
    lang = code == 'hu' ? 'hu' : 'en';
    setLang(lang);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', lang);
  }

  Future<void> init() async {
    languageRequest = setLanguage;
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('lang');
    if (savedLang != null) setLang(savedLang);
    lang = currentLang;
    final name = prefs.getString('theme');
    theme = PintyThemeId.values.firstWhere(
      (t) => t.name == name,
      orElse: () => PintyThemeId.light,
    );
    await repo.init();
    await _refreshBiometric();
    stage = repo.hasAccount ? Stage.locked : Stage.welcome;
    notifyListeners();
  }

  Future<void> _refreshBiometric() async {
    biometricAvailable = await unlockHelper.available;
    biometricEnabled = biometricAvailable && repo.hasAccount && await unlockHelper.isEnabled(email);
  }

  Future<void> setTheme(PintyThemeId id) async {
    theme = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', id.name);
  }

  // ---------- fiók és zárolás ----------

  Future<bool> _guard(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      error = friendlyError(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (error != null) {
      error = null;
      notifyListeners();
    }
  }

  Future<void> register({
    required String serverUrl,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    final ok = await _guard(() => repo.register(
          serverUrl: serverUrl,
          email: email,
          password: password,
          inviteCode: inviteCode,
        ));
    if (ok) {
      recoveryHint = true;
      _enterUnlocked();
    }
  }

  Future<void> connect({
    required String serverUrl,
    required String email,
    required String password,
  }) async {
    final ok = await _guard(() => repo.connect(serverUrl: serverUrl, email: email, password: password));
    if (ok) _enterUnlocked();
  }

  Future<void> unlock(String password) async {
    final ok = await _guard(() => repo.unlock(password));
    if (ok) _enterUnlocked();
  }

  /// Elfelejtett mesterjelszó: visszaállító kulccsal új jelszó beállítása.
  Future<void> recoverAccount({
    required String serverUrl,
    required String email,
    required String recoveryKey,
    required String newPassword,
  }) async {
    final ok = await _guard(() => repo.recoverAccount(
          serverUrl: serverUrl,
          email: email,
          recoveryKey: recoveryKey,
          newPassword: newPassword,
        ));
    if (ok) {
      await unlockHelper.disable(email);
      biometricEnabled = false;
      _enterUnlocked();
    }
  }

  Future<void> unlockBiometric() async {
    final ok = await _guard(() async {
      final secrets = await unlockHelper.read(email);
      if (secrets == null) throw VaultException(tr('A biometrikus azonosítás nem sikerült.'));
      try {
        await repo.unlockWithSecrets(secrets);
      } on VaultException {
        await unlockHelper.disable(email);
        biometricEnabled = false;
        rethrow;
      }
    });
    if (ok) _enterUnlocked();
  }

  Future<bool> enableBiometric() async {
    final ok = await _guard(() async {
      final done = await unlockHelper.enable(email, await repo.exportUnlockSecrets());
      if (!done) throw VaultException(tr('A biometrikus azonosítás nem sikerült.'));
      biometricEnabled = true;
    });
    return ok;
  }

  Future<void> disableBiometric() async {
    await unlockHelper.disable(email);
    biometricEnabled = false;
    notifyListeners();
  }

  /// Mesterjelszó cseréje; ha be van kapcsolva a biometrikus feloldás, annak adatai is frissülnek.
  Future<bool> changeMasterPassword(String oldPassword, String newPassword) async {
    return _guard(() async {
      await repo.changeMasterPassword(oldPassword: oldPassword, newPassword: newPassword);
      if (biometricEnabled) {
        await unlockHelper.disable(email);
        await unlockHelper.enable(email, await repo.exportUnlockSecrets());
      }
    });
  }

  /// Új visszaállító kulcs; null, ha nem sikerült (a hiba az [error] mezőben).
  Future<String?> createRecoveryKey() async {
    String? key;
    await _guard(() async => key = await repo.createRecoveryKey());
    return key;
  }

  Future<bool> recoveryEnabled() async {
    try {
      return await repo.recoveryEnabled();
    } catch (_) {
      return false;
    }
  }

  void _enterUnlocked() {
    stage = Stage.unlocked;
    selectedId = null;
    syncStatus = null;
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 1), (_) => sync());
    touch();
    notifyListeners();
    unawaited(sync());
  }

  /// Felhasználói tevékenység: újraindítja a tétlenségi időzítőt.
  void touch() {
    if (stage != Stage.unlocked) return;
    _idle?.cancel();
    _idle = Timer(autoLock, lock);
  }

  void lock() {
    _idle?.cancel();
    _periodic?.cancel();
    _debounce?.cancel();
    repo.lock();
    if (stage != Stage.loading) {
      stage = repo.hasAccount ? Stage.locked : Stage.welcome;
    }
    selectedId = null;
    selectedNoteId = null;
    tab = 0;
    error = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    lock();
    await repo.signOut();
    stage = Stage.welcome;
    syncStatus = null;
    notifyListeners();
  }

  // ---------- szinkron ----------

  Future<void> sync() async {
    if (stage != Stage.unlocked || _syncing) return;
    _syncing = true;
    syncStatus = tr('Szinkronizálás…');
    notifyListeners();
    try {
      final r = await repo.sync();
      await repo.purgeTrash();
      syncStatus = r.conflicts > 0
          ? trf('Szinkronizálva · %1 ütköző példány', [r.conflicts])
          : tr('Szinkronizálva');
    } catch (e) {
      syncStatus = e is ApiException && e.status == 401
          ? tr('Nincs szinkron: a mesterjelszót máshol megváltoztatták. Jelentkezz ki ezen az eszközön, és lépj be újra.')
          : trf('Nincs szinkron: %1', [friendlyError(e)]);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
  }

  // ---------- elemek ----------

  void select(String id) {
    selectedId = id;
    notifyListeners();
  }

  Future<void> saveItem(VaultItem item) async {
    await repo.upsert(item);
    selectedId = item.id;
    notifyListeners();
    _scheduleSync();
  }

  // ---------- kuka, mappák, import/export ----------

  List<VaultItem> get trashed => repo.trash;

  Future<void> trashItem(VaultItem item) async {
    await repo.trashItem(item);
    if (selectedId == item.id) selectedId = null;
    if (selectedNoteId == item.id) selectedNoteId = null;
    notifyListeners();
    _scheduleSync();
  }

  Future<void> restoreItem(VaultItem item) async {
    await repo.restoreItem(item);
    notifyListeners();
    _scheduleSync();
  }

  /// Egy elem végleges törlése (a kukából).
  Future<void> deleteForever(String id) async {
    await repo.delete(id);
    notifyListeners();
    _scheduleSync();
  }

  Future<void> emptyTrash() async {
    for (final i in repo.trash) {
      await repo.delete(i.id);
    }
    notifyListeners();
    _scheduleSync();
  }

  static String cleanPath(String p) =>
      p.replaceAll('\\', '/').split('/').map((s) => s.trim()).where((s) => s.isNotEmpty).join('/');

  static String parentPath(String p) {
    final i = p.lastIndexOf('/');
    return i < 0 ? '' : p.substring(0, i);
  }

  static String _remap(String p, String from, String to) {
    if (p == from) return to;
    if (p.startsWith('$from/')) {
      final rest = p.substring(from.length + 1);
      return to.isEmpty ? rest : '$to/$rest';
    }
    return p;
  }

  String _itemKindFor(String scope) => scope == 'note' ? ItemKind.note : ItemKind.login;

  /// Egy rész (jelszavak vagy jegyzetek) összes mappája: a létrehozottak, a bennük lévő elemek mappái
  /// és mindezek szülő-mappái.
  List<String> foldersFor(String scope) {
    final set = <String>{};
    void add(String path) {
      var f = path;
      while (f.isNotEmpty) {
        set.add(f);
        f = parentPath(f);
      }
    }

    repo.folderPaths(scope).forEach(add);
    for (final i in repo.allOfKind(_itemKindFor(scope))) {
      if (!i.inTrash) add(i.folder);
    }
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> createFolder(String scope, String path) async {
    final p = cleanPath(path);
    if (p.isEmpty || foldersFor(scope).contains(p)) return;
    await repo.upsert(VaultItem(id: const Uuid().v4(), name: p, kind: ItemKind.folder, scope: scope));
    notifyListeners();
    _scheduleSync();
  }

  /// Mappa átnevezése/áthelyezése: a benne és az alatta lévő elemek és mappák útvonala is követi.
  /// Ha a célmappa már létezik, a tartalmak összeolvadnak.
  Future<void> renameFolder(String scope, String from, String to) async {
    final f = cleanPath(from);
    final t = cleanPath(to);
    if (f.isEmpty || f == t || t == f || t.startsWith('$f/')) return;
    for (final i in repo.allOfKind(_itemKindFor(scope))) {
      final n = _remap(i.folder, f, t);
      if (n != i.folder) {
        i.folder = n;
        await repo.upsert(i);
      }
    }
    final seen = <String>{};
    for (final fi in repo.allOfKind(ItemKind.folder).where((x) => x.scope == scope)) {
      final n = _remap(fi.name, f, t);
      if (n.isEmpty || !seen.add(n)) {
        await repo.delete(fi.id);
      } else if (n != fi.name) {
        fi.name = n;
        await repo.upsert(fi);
      }
    }
    notifyListeners();
    _scheduleSync();
  }

  /// Mappa törlése: a tartalma (és az almappák) a szülő-mappába kerül, jegyzet nem vész el.
  Future<void> deleteFolder(String scope, String path) async {
    final p = cleanPath(path);
    if (p.isEmpty) return;
    await renameFolder(scope, p, parentPath(p));
    // az átnevezés után a törölt mappa maga is megszűnt (a folder-elemét a renameFolder törölte, ha üres lett a neve)
    for (final fi in repo.allOfKind(ItemKind.folder).where((x) => x.scope == scope && x.name == p).toList()) {
      await repo.delete(fi.id);
    }
    notifyListeners();
    _scheduleSync();
  }

  Future<void> moveToFolder(VaultItem item, String path) async {
    item.folder = cleanPath(path);
    await repo.upsert(item);
    notifyListeners();
    _scheduleSync();
  }

  Future<Uint8List> exportBackup(String password) => Backup.export(repo.liveItems, password);

  String exportCsvText() => exportCsv(repo.items);

  /// Beolvasott elemek hozzáadása: azonosak kihagyva, ütköző jegyzet-címek átnevezve.
  /// Visszaadja (hozzáadott, kihagyott) darabszámot.
  Future<(int, int)> importItems(Iterable<VaultItem> incoming) async {
    var added = 0, skipped = 0;
    final logins = repo.allOfKind(ItemKind.login);
    final noteTitles = {for (final n in repo.allOfKind(ItemKind.note)) n.name.toLowerCase(): n};
    final fileNames = {for (final f in repo.files) f.name.toLowerCase(): f};
    final folderKeys = {for (final f in repo.allOfKind(ItemKind.folder)) '${f.scope}:${f.name}'};
    for (final src in incoming) {
      switch (src.kind) {
        case ItemKind.login:
          final dup = logins.any((l) =>
              l.name == src.name && l.username == src.username && l.url == src.url && l.password == src.password);
          if (dup) {
            skipped++;
            continue;
          }
          final it = VaultItem.fromJson(src.toJson())..trashedAt = null;
          await repo.upsert(_withNewId(it));
          added++;
        case ItemKind.note:
          final existing = noteTitles[src.name.toLowerCase()];
          if (existing != null && existing.notes == src.notes) {
            skipped++;
            continue;
          }
          var title = src.name;
          for (var n = 2; noteTitles.containsKey(title.toLowerCase()); n++) {
            title = trf('%1 (importált%2)', [src.name, n > 2 ? ' $n' : '']);
          }
          final it = _withNewId(VaultItem.fromJson(src.toJson())..trashedAt = null)..name = title;
          await repo.upsert(it);
          noteTitles[title.toLowerCase()] = it;
          added++;
        case ItemKind.file:
          final existing = fileNames[src.name.toLowerCase()];
          if (existing != null && existing.data == src.data) {
            skipped++;
            continue;
          }
          var name = src.name;
          for (var n = 2; fileNames.containsKey(name.toLowerCase()); n++) {
            final dot = src.name.lastIndexOf('.');
            name = dot > 0 ? '${src.name.substring(0, dot)}-$n${src.name.substring(dot)}' : '${src.name}-$n';
          }
          final it = _withNewId(VaultItem.fromJson(src.toJson()))..name = name;
          await repo.upsert(it);
          fileNames[name.toLowerCase()] = it;
          added++;
        case ItemKind.folder:
          if (!folderKeys.add('${src.scope}:${src.name}')) {
            skipped++;
            continue;
          }
          await repo.upsert(_withNewId(VaultItem.fromJson(src.toJson())));
          added++;
      }
    }
    notifyListeners();
    _scheduleSync();
    return (added, skipped);
  }

  VaultItem _withNewId(VaultItem i) =>
      VaultItem.fromJson({...i.toJson(), 'id': const Uuid().v4()});

  Future<void> deleteItem(String id) async {
    await repo.delete(id);
    if (selectedId == id) selectedId = null;
    notifyListeners();
    _scheduleSync();
  }

  @override
  void dispose() {
    _idle?.cancel();
    _periodic?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
