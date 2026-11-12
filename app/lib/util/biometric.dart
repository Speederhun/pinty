import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../i18n.dart';

/// Feloldás ujjlenyomattal / Windows Hello-val / eszköz-PIN-nel. A mesterkulcsot az operációs rendszer
/// biztonságos tárolója (Android Keystore, Windows hitelesítő-tár) őrzi, és csak sikeres azonosítás után olvassuk ki.
abstract class UnlockHelper {
  Future<bool> get available;
  Future<bool> isEnabled(String account);

  /// Azonosítás után eltárolja az adatokat. `false`, ha az azonosítás nem sikerült.
  Future<bool> enable(String account, Map<String, String> secrets);

  /// Azonosítás után visszaadja az eltárolt adatokat (`null`, ha nem sikerült vagy nincs).
  Future<Map<String, String>?> read(String account);

  Future<void> disable(String account);
}

/// Ha nincs támogatás (pl. Linux, tesztek).
class NoUnlock implements UnlockHelper {
  @override
  Future<bool> get available async => false;
  @override
  Future<bool> isEnabled(String account) async => false;
  @override
  Future<bool> enable(String account, Map<String, String> secrets) async => false;
  @override
  Future<Map<String, String>?> read(String account) async => null;
  @override
  Future<void> disable(String account) async {}
}

class BiometricUnlock implements UnlockHelper {
  late final LocalAuthentication _auth = LocalAuthentication();
  late final FlutterSecureStorage _store = const FlutterSecureStorage();

  static String _key(String account) => 'pinty.unlock.${account.toLowerCase()}';

  // macOS-en a nem aláírt alkalmazás nem fér hozzá a kulcstartóhoz, Linuxon nincs biometria.
  bool get _platformOk => Platform.isAndroid || Platform.isWindows;

  @override
  Future<bool> get available async {
    if (!_platformOk) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isEnabled(String account) async {
    if (!_platformOk) return false;
    try {
      return await _store.containsKey(key: _key(account));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> enable(String account, Map<String, String> secrets) async {
    if (!await _authenticate(tr('Erősítsd meg a biometrikus feloldás bekapcsolását'))) return false;
    await _store.write(key: _key(account), value: jsonEncode(secrets));
    return true;
  }

  @override
  Future<Map<String, String>?> read(String account) async {
    if (!await _authenticate(tr('Pinty feloldása'))) return null;
    try {
      final raw = await _store.read(key: _key(account));
      if (raw == null) return null;
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> disable(String account) async {
    try {
      await _store.delete(key: _key(account));
    } catch (_) {}
  }
}
