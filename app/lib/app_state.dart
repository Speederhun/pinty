import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models/vault_item.dart';
import 'theme/pinty_theme.dart';

/// Az app állapota. Ebben a verzióban a széf még csak memóriában él;
/// a titkosított helyi tárolás és a szinkron a következő lépés (lásd README).
class AppState extends ChangeNotifier {
  PintyThemeId theme = PintyThemeId.light;
  final List<VaultItem> items = [];
  String? selectedId;

  VaultItem? get selected {
    for (final i in items) {
      if (i.id == selectedId) return i;
    }
    return items.isEmpty ? null : items.first;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('theme');
    theme = PintyThemeId.values.firstWhere(
      (t) => t.name == name,
      orElse: () => PintyThemeId.light,
    );
    notifyListeners();
  }

  Future<void> setTheme(PintyThemeId id) async {
    theme = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', id.name);
  }

  void select(String id) {
    selectedId = id;
    notifyListeners();
  }

  VaultItem add({
    required String name,
    String username = '',
    String password = '',
    String url = '',
    String notes = '',
  }) {
    final item = VaultItem(
      id: const Uuid().v4(),
      name: name,
      username: username,
      password: password,
      url: url,
      notes: notes,
    );
    items.add(item);
    selectedId = item.id;
    notifyListeners();
    return item;
  }

  void update(VaultItem item) {
    item.updatedAt = DateTime.now().toUtc();
    notifyListeners();
  }

  void remove(String id) {
    items.removeWhere((i) => i.id == id);
    if (selectedId == id) selectedId = null;
    notifyListeners();
  }
}
