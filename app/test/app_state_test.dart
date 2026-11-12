import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/i18n.dart';
import 'package:pinty/app_state.dart';
import 'package:pinty/crypto/vault_crypto.dart';
import 'package:pinty/data/local_store.dart';
import 'package:pinty/data/vault_repository.dart';
import 'package:pinty/models/vault_item.dart';
import 'package:pinty/util/biometric.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

KdfParams _fastKdf() => KdfParams(
      salt: VaultCrypto.randomBytes(16),
      memoryKiB: 1024,
      iterations: 1,
      parallelism: 1,
    );

class _FakeUnlock implements UnlockHelper {
  Map<String, String>? stored;
  @override
  Future<bool> get available async => true;
  @override
  Future<bool> isEnabled(String account) async => stored != null;
  @override
  Future<bool> enable(String account, Map<String, String> secrets) async {
    stored = secrets;
    return true;
  }

  @override
  Future<Map<String, String>?> read(String account) async => stored;
  @override
  Future<void> disable(String account) async => stored = null;
}

const _pw = 'nagyon-hosszu-mesterjelszo';

Future<AppState> _app(FakeServer server, {UnlockHelper? unlock}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = VaultRepository(store: MemoryLocalStore(), apiFactory: (_) => server.client(), newKdf: _fastKdf);
  final s = AppState(repo: repo, unlockHelper: unlock ?? NoUnlock());
  await s.init();
  await s.register(serverUrl: 'https://vault.test', email: 'a@example.com', password: _pw, inviteCode: '');
  return s;
}

void main() {
  setLang('hu');
  test('mappák: létrehozás, átnevezés, áthelyezés, törlés (semmi sem vész el)', () async {
    final s = await _app(FakeServer());
    await s.newNote(title: 'Terv', folder: 'Munka/2026', body: 'x');
    await s.newNote(title: 'Egyéb', folder: 'Munka', body: 'y');
    await s.createFolder('note', 'Üres/Almappa');

    expect(s.foldersFor('note'), ['Munka', 'Munka/2026', 'Üres', 'Üres/Almappa']);
    expect(s.noteIndex.folders, contains('Üres/Almappa'));

    await s.renameFolder('note', 'Munka', 'Iroda');
    expect(s.noteIndex.notes.map((n) => n.folder).toSet(), {'Iroda', 'Iroda/2026'});

    await s.deleteFolder('note', 'Iroda');
    // az elemek a szülőbe (gyökérbe) kerültek, az almappa feljebb lépett
    expect(s.noteIndex.notes.map((n) => n.folder).toSet(), {'', '2026'});
    expect(s.noteIndex.notes.length, 2);
    expect(s.foldersFor('note'), ['2026', 'Üres', 'Üres/Almappa']);

    await s.deleteFolder('note', 'Üres');
    expect(s.foldersFor('note'), ['2026', 'Almappa']);

    // mappába áthelyezés
    await s.moveToFolder(s.noteIndex.notes.first, 'Új/Hely');
    expect(s.foldersFor('note'), contains('Új/Hely'));
  });

  test('kuka: visszaállítás, végleges törlés, 30 nap utáni takarítás', () async {
    final s = await _app(FakeServer());
    final a = VaultItem(id: 'a', name: 'A', password: 'p');
    final b = VaultItem(id: 'b', name: 'B', password: 'p');
    await s.saveItem(a);
    await s.saveItem(b);
    await s.trashItem(a);
    expect(s.items.map((i) => i.id), ['b']);
    expect(s.trashed.map((i) => i.id), ['a']);

    await s.restoreItem(a);
    expect(s.items.length, 2);

    await s.trashItem(a);
    a.trashedAt = DateTime.now().toUtc().subtract(const Duration(days: 31));
    await s.repo.upsert(a);
    expect(await s.repo.purgeTrash(), 1);
    expect(s.trashed, isEmpty);
    expect(s.items.map((i) => i.id), ['b']);
  });

  test('jelszó-előzmények', () {
    final i = VaultItem(id: 'x', name: 'X', password: 'régi');
    i.setPassword('új');
    i.setPassword('új'); // változatlan: nem kerül be
    i.setPassword('újabb');
    expect(i.history.map((h) => h.password), ['új', 'régi']);
    final back = VaultItem.fromJson(i.toJson());
    expect(back.history.length, 2);
    for (var n = 0; n < 30; n++) {
      i.setPassword('p$n');
    }
    expect(i.history.length, VaultItem.maxHistory);
  });

  test('mesterjelszó-csere: új jelszóval nyílik, régivel nem; a széf tartalma megmarad', () async {
    final server = FakeServer();
    final s = await _app(server);
    await s.saveItem(VaultItem(id: 'a', name: 'GitHub', password: 'titok'));
    await s.repo.sync();

    expect(await s.changeMasterPassword('rossz-regi-jelszo-xx', 'uj-nagyon-hosszu-jelszo'), isFalse);
    expect(await s.changeMasterPassword(_pw, 'uj-nagyon-hosszu-jelszo'), isTrue);

    s.lock();
    await s.unlock(_pw);
    expect(s.stage, Stage.locked);
    await s.unlock('uj-nagyon-hosszu-jelszo');
    expect(s.stage, Stage.unlocked);
    expect(s.items.single.password, 'titok');

    // egy másik eszköz is csak az új jelszóval lép be
    final other = VaultRepository(store: MemoryLocalStore(), apiFactory: (_) => server.client(), newKdf: _fastKdf);
    await other.init();
    await expectLater(other.connect(serverUrl: 'https://vault.test', email: 'a@example.com', password: _pw), throwsA(anything));
    await other.connect(serverUrl: 'https://vault.test', email: 'a@example.com', password: 'uj-nagyon-hosszu-jelszo');
    expect(other.items.single.name, 'GitHub');
  });

  test('visszaállító kulcs: elfelejtett jelszó után új jelszóval hozzáfér', () async {
    final server = FakeServer();
    final s = await _app(server);
    await s.saveItem(VaultItem(id: 'a', name: 'Bank', password: 'titok'));
    await s.repo.sync();
    expect(await s.recoveryEnabled(), isFalse);
    final key = await s.createRecoveryKey();
    expect(key, isNotNull);
    expect(await s.recoveryEnabled(), isTrue);

    // új eszköz, elfelejtett jelszó
    SharedPreferences.setMockInitialValues({});
    final repo = VaultRepository(store: MemoryLocalStore(), apiFactory: (_) => server.client(), newKdf: _fastKdf);
    final dev = AppState(repo: repo, unlockHelper: NoUnlock());
    await dev.init();
    await dev.recoverAccount(serverUrl: 'https://vault.test', email: 'a@example.com', recoveryKey: 'AAAA-BBBB', newPassword: 'masik-nagyon-hosszu-jelszo');
    expect(dev.error, isNotNull); // hibás kulcs
    await dev.recoverAccount(
      serverUrl: 'https://vault.test',
      email: 'a@example.com',
      recoveryKey: key!.toLowerCase(),
      newPassword: 'masik-nagyon-hosszu-jelszo',
    );
    expect(dev.stage, Stage.unlocked);
    expect(dev.items.single.name, 'Bank');

    // a régi jelszó már nem jó
    final old = VaultRepository(store: MemoryLocalStore(), apiFactory: (_) => server.client(), newKdf: _fastKdf);
    await old.init();
    await expectLater(old.connect(serverUrl: 'https://vault.test', email: 'a@example.com', password: _pw), throwsA(anything));
  });

  test('biometrikus feloldás: be-, kikapcsolás és feloldás tárolt adatokból', () async {
    final unlock = _FakeUnlock();
    final s = await _app(FakeServer(), unlock: unlock);
    await s.saveItem(VaultItem(id: 'a', name: 'A', password: 'p'));
    expect(await s.enableBiometric(), isTrue);
    expect(s.biometricEnabled, isTrue);

    s.lock();
    expect(s.stage, Stage.locked);
    await s.unlockBiometric();
    expect(s.stage, Stage.unlocked);
    expect(s.items.single.name, 'A');

    // jelszócsere után a tárolt adatok frissülnek, így a biometria tovább működik
    await s.changeMasterPassword(_pw, 'uj-nagyon-hosszu-jelszo');
    s.lock();
    await s.unlockBiometric();
    expect(s.stage, Stage.unlocked);

    await s.disableBiometric();
    expect(unlock.stored, isNull);
  });

  test('import: duplikátumok kihagyása, jegyzet-cím ütközés, képek', () async {
    final s = await _app(FakeServer());
    await s.saveItem(VaultItem(id: 'a', name: 'GitHub', username: 'u', password: 'p', url: 'https://github.com'));
    await s.newNote(title: 'Terv', body: 'régi');
    final (added, skipped) = await s.importItems([
      VaultItem(id: 'x1', name: 'GitHub', username: 'u', password: 'p', url: 'https://github.com'),
      VaultItem(id: 'x2', name: 'Új', password: 'q'),
      VaultItem(id: 'x3', name: 'Terv', kind: ItemKind.note, notes: 'másik tartalom'),
      VaultItem(id: 'x4', name: 'Terv', kind: ItemKind.note, notes: 'régi'),
    ]);
    expect(added, 2);
    expect(skipped, 2);
    expect(s.items.map((i) => i.name).toSet(), {'GitHub', 'Új'});
    expect(s.noteIndex.notes.map((n) => n.name).toSet(), {'Terv', 'Terv (importált)'});
  });

  test('kép csatolása: méret- és típusellenőrzés', () async {
    final s = await _app(FakeServer());
    final f = await s.addImage('kep.png', Uint8List.fromList([1, 2, 3]));
    expect(f.mime, 'image/png');
    final g = await s.addImage('kep.png', Uint8List.fromList([4]));
    expect(g.name, 'kep-2.png');
    await expectLater(s.addImage('x.exe', Uint8List(3)), throwsA(isA<VaultException>()));
    await expectLater(s.addImage('nagy.png', Uint8List(AppState.maxImageBytes + 1)), throwsA(isA<VaultException>()));
  });
}
