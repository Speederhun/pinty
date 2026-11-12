import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/models/vault_item.dart';
import 'package:pinty/util/security_audit.dart';

VaultItem login(String id, String pw, {DateTime? at}) => VaultItem(id: id, name: id, password: pw, updatedAt: at);

void main() {
  test('jelszó-erősség', () {
    expect(strengthOf('password'), Strength.veryWeak);
    expect(strengthOf('123456'), Strength.veryWeak);
    expect(strengthOf('aaaaaaaa').index, lessThanOrEqualTo(Strength.weak.index));
    expect(strengthOf('abc12345').index, lessThanOrEqualTo(Strength.weak.index));
    expect(strengthOf('k7#Qz!m9Lp2@vXw4').index, greaterThanOrEqualTo(Strength.good.index));
    expect(strengthOf('helyes-ló-elem-tűzfal-9').index, greaterThanOrEqualTo(Strength.good.index));
  });

  test('audit: gyenge, ismételt, régi', () {
    final now = DateTime.utc(2026, 11, 12);
    final r = auditLogins([
      login('a', 'password'),
      login('b', 'k7#Qz!m9Lp2@vXw4'),
      login('c', 'k7#Qz!m9Lp2@vXw4'),
      login('d', 'Zs9\$Tr8&Qm4!Lx7^', at: DateTime.utc(2024, 1, 1)),
      login('e', ''),
      VaultItem(id: 'n', name: 'jegyzet', kind: ItemKind.note),
      VaultItem(id: 'k', name: 'kuka', password: 'password', trashedAt: now),
    ], now: now);
    expect(r.weak.map((i) => i.id), ['a']);
    expect(r.reused.single.map((i) => i.id).toSet(), {'b', 'c'});
    expect(r.old.map((i) => i.id), ['d']);
    expect(r.noPassword.map((i) => i.id), ['e']);
    expect(r.total, 4);
    expect(r.score, lessThan(100));
    expect(auditLogins([]).score, 100);
  });
}
