import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api/pinty_api.dart';
import 'data/vault_repository.dart';
import 'models/vault_item.dart';
import 'theme/pinty_theme.dart';

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

  Timer? _idle;
  Timer? _periodic;
  Timer? _debounce;
  bool _syncing = false;

  List<VaultItem> get items => repo.items;
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
