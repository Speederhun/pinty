import 'dart:math';

import '../models/vault_item.dart';

enum Strength { veryWeak, weak, fair, good, strong }

extension StrengthLabel on Strength {
  String get label => switch (this) {
        Strength.veryWeak => 'Nagyon gyenge',
        Strength.weak => 'Gyenge',
        Strength.fair => 'Közepes',
        Strength.good => 'Jó',
        Strength.strong => 'Erős',
      };
}

const _common = {
  'password', 'jelszo', 'jelszó', '123456', '12345678', '123456789', 'qwerty', 'qwertz', 'abc123', 'letmein',
  'admin', 'welcome', 'iloveyou', 'monkey', 'dragon', 'football', 'master', 'login', 'passw0rd', 'p@ssw0rd',
  'asdfgh', 'asdfghjkl', 'minecraft', 'budapest', 'magyar', 'szia', 'titok', 'test', 'teszt', '111111', '000000',
};

/// Becsült entrópia bitekben: karakterkészlet × hossz, levonva az ismétlődések, sorozatok és gyakori jelszavak miatt.
double estimateEntropy(String pw) {
  if (pw.isEmpty) return 0;
  final lower = pw.toLowerCase();
  if (_common.contains(lower)) return 5;
  var pool = 0;
  if (RegExp(r'[a-záéíóöőúüű]').hasMatch(pw)) pool += 26;
  if (RegExp(r'[A-ZÁÉÍÓÖŐÚÜŰ]').hasMatch(pw)) pool += 26;
  if (RegExp(r'\d').hasMatch(pw)) pool += 10;
  if (RegExp(r'[^\p{L}\d]', unicode: true).hasMatch(pw)) pool += 33;
  if (pool == 0) pool = 10;
  // a különböző karakterek száma számít, az ismétlődés nem ad entrópiát
  final distinct = pw.split('').toSet().length;
  final effectiveLen = (distinct + (pw.length - distinct) * 0.25);
  var bits = effectiveLen * (log(pool) / ln2);
  // egymás melletti sorozatok (abc, 123) és billentyűzet-sorok
  final runs = RegExp(r'(?:012|123|234|345|456|567|678|789|abc|bcd|cde|def|qwe|wer|ert|asd|sdf|dfg|zxc|xcv)', caseSensitive: false)
      .allMatches(pw)
      .length;
  bits -= runs * 6;
  if (_common.any((c) => c.length >= 5 && lower.contains(c))) bits -= 15;
  return max(0, bits);
}

Strength strengthOf(String pw) {
  final b = estimateEntropy(pw);
  if (b < 28) return Strength.veryWeak;
  if (b < 40) return Strength.weak;
  if (b < 60) return Strength.fair;
  if (b < 80) return Strength.good;
  return Strength.strong;
}

class AuditReport {
  AuditReport({required this.weak, required this.reused, required this.old, required this.noPassword, required this.total});
  final List<VaultItem> weak;

  /// Azonos jelszót használó csoportok (legalább 2 elem).
  final List<List<VaultItem>> reused;
  final List<VaultItem> old;
  final List<VaultItem> noPassword;
  final int total;

  int get problems => weak.length + reused.fold<int>(0, (a, g) => a + g.length) + old.length;

  /// 0–100, minél több a gond, annál kisebb.
  int get score {
    if (total == 0) return 100;
    final bad = <String>{
      for (final i in weak) i.id,
      for (final g in reused) for (final i in g) i.id,
      for (final i in old) i.id,
    };
    return (100 - (bad.length * 100 / total)).round().clamp(0, 100);
  }
}

AuditReport auditLogins(Iterable<VaultItem> items, {DateTime? now, Duration maxAge = const Duration(days: 365)}) {
  final t = (now ?? DateTime.now()).toUtc();
  final logins = [for (final i in items) if (i.kind == ItemKind.login && !i.inTrash) i];
  final withPw = logins.where((i) => i.password.isNotEmpty).toList();
  final byPw = <String, List<VaultItem>>{};
  for (final i in withPw) {
    (byPw[i.password] ??= []).add(i);
  }
  return AuditReport(
    weak: [for (final i in withPw) if (strengthOf(i.password).index <= Strength.weak.index) i],
    reused: [for (final g in byPw.values) if (g.length > 1) g],
    old: [for (final i in withPw) if (t.difference(i.updatedAt) > maxAge) i],
    noPassword: [for (final i in logins) if (i.password.isEmpty) i],
    total: withPw.length,
  );
}
