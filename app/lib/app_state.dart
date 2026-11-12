import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api/pinty_api.dart';
import 'data/vault_repository.dart';
import 'models/vault_item.dart';
import 'theme/pinty_theme.dart';
import 'util/note_logic.dart';

enum Stage { loading, welcome, locked, unlocked }

String friendlyError(Object e) {
  if (e is VaultException) return e.message;
  if (e is ApiException) return e.message;
  if (e is SocketException || e is http.ClientException || e is TimeoutException) {
    return 'A szerver nem érhető el. Ellenőrizd a címet és a hálózatot.';
  }
  if (e is FormatException) return 'Érvénytelen szervercím vagy szerverválasz.';
  return 'Váratlan hiba: $e';
}

/// Az app állapota: melyik képernyő látszik, a téma, és a széf műveletei.
class AppState extends ChangeNotifier {
  AppState({required this.repo, this.autoLock = const Duration(minutes: 5)});

  final VaultRepository repo;

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
  NoteIndex get noteIndex => _noteIdx ??= NoteIndex(repo.notes, repo.files);

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
    var name = title.trim().isEmpty ? 'Névtelen jegyzet' : title.trim();
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
    final body = tpl != null ? applyTemplate(tpl.notes, title: title, now: day) : '# $title\n\n## Teendők\n- [ ] \n\n## Jegyzetek\n';
    return newNote(title: title, folder: 'Napi', body: body);
  }

  static const maxImageBytes = 3 * 1024 * 1024;

  /// Kép csatolása a széfhez (a jegyzetekben `![[név]]`-vel beágyazható). A neve egyedi lesz.
  Future<VaultItem> addImage(String name, Uint8List bytes) async {
    if (bytes.length > maxImageBytes) {
      throw VaultException('A kép legfeljebb ${maxImageBytes ~/ (1024 * 1024)} MB lehet.');
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
    if (mime.isEmpty) throw VaultException('Csak PNG, JPG, GIF vagy WebP kép csatolható.');
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

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('theme');
    theme = PintyThemeId.values.firstWhere(
      (t) => t.name == name,
      orElse: () => PintyThemeId.light,
    );
    await repo.init();
    stage = repo.hasAccount ? Stage.locked : Stage.welcome;
    notifyListeners();
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
    if (ok) _enterUnlocked();
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
    syncStatus = 'Szinkronizálás…';
    notifyListeners();
    try {
      final r = await repo.sync();
      syncStatus = r.conflicts > 0
          ? 'Szinkronizálva · ${r.conflicts} ütköző példány'
          : 'Szinkronizálva';
    } catch (e) {
      syncStatus = 'Nincs szinkron: ${friendlyError(e)}';
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
