import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/crypto/vault_crypto.dart';
import 'package:pinty/data/local_store.dart';
import 'package:pinty/data/vault_repository.dart';
import 'package:pinty/models/vault_item.dart';

import 'fake_server.dart';

KdfParams _fastKdf() => KdfParams(
      salt: Uint8List.fromList(List.generate(16, (i) => i + 1)),
      memoryKiB: 1024,
      iterations: 1,
      parallelism: 1,
    );

VaultRepository _device(FakeServer server, [MemoryLocalStore? store]) => VaultRepository(
      store: store ?? MemoryLocalStore(),
      apiFactory: (_) => server.client(),
      newKdf: _fastKdf,
    );

const _pw = 'nagyon-hosszu-mesterjelszo';

Future<VaultRepository> _registered(FakeServer server) async {
  final a = _device(server);
  await a.init();
  await a.register(serverUrl: 'https://vault.test', email: 'A@Example.com', password: _pw);
  return a;
}

Future<VaultRepository> _connected(FakeServer server) async {
  final b = _device(server);
  await b.init();
  await b.connect(serverUrl: 'https://vault.test/', email: 'a@example.com', password: _pw);
  return b;
}

void main() {
  test('szinkron után a szerveren csak titkosított adat van', () async {
    final server = FakeServer();
    final a = await _registered(server);
    await a.upsert(VaultItem(id: 'i1', name: 'GitHub', password: 'titkos-jelszo-123', notes: 'szupertitkos jegyzet'));
    await a.sync();

    expect(server.blobs, isNotEmpty);
    for (final b in server.blobs) {
      expect(b.contains('GitHub'), isFalse);
      expect(b.contains('titkos-jelszo-123'), isFalse);
      expect(b.contains('szupertitkos'), isFalse);
    }
  });

  test('második eszköz látja az elemeket, és a módosítások oda-vissza mennek', () async {
    final server = FakeServer();
    final a = await _registered(server);
    await a.upsert(VaultItem(id: 'i1', name: 'GitHub', username: 'u', password: 'p1', notes: 'jegyzet'));
    await a.sync();

    final b = await _connected(server);
    expect(b.items.map((e) => e.name), ['GitHub']);
    expect(b.items.first.notes, 'jegyzet');

    final item = b.items.first..password = 'p2';
    await b.upsert(item);
    await b.sync();
    await a.sync();
    expect(a.items.first.password, 'p2');
  });

  test('ütközésnél a szerver változata marad, a helyi másolatként megmarad', () async {
    final server = FakeServer();
    final a = await _registered(server);
    await a.upsert(VaultItem(id: 'i1', name: 'Eredeti'));
    await a.sync();
    final b = await _connected(server);

    // mindkét eszköz offline szerkeszti ugyanazt
    final ia = a.items.first..name = 'A-szerkesztés';
    await a.upsert(ia);
    final ib = b.items.first..name = 'B-szerkesztés';
    await b.upsert(ib);

    await a.sync(); // A ér oda először
    final report = await b.sync();
    expect(report.conflicts, 1);
    expect(b.items.map((e) => e.name).toSet(), {'A-szerkesztés', 'B-szerkesztés (ütköző példány)'});

    await a.sync();
    expect(a.items.map((e) => e.name).toSet(), {'A-szerkesztés', 'B-szerkesztés (ütköző példány)'});
  });

  test('a törlés eljut a másik eszközre', () async {
    final server = FakeServer();
    final a = await _registered(server);
    await a.upsert(VaultItem(id: 'i1', name: 'Törlendő'));
    await a.sync();
    final b = await _connected(server);
    expect(b.items, hasLength(1));

    await a.delete('i1');
    await a.sync();
    await b.sync();
    expect(b.items, isEmpty);
  });

  test('ha törölték, de közben módosítottam, a módosított marad', () async {
    final server = FakeServer();
    final a = await _registered(server);
    await a.upsert(VaultItem(id: 'i1', name: 'Közös'));
    await a.sync();
    final b = await _connected(server);

    await a.delete('i1');
    await a.sync();

    final ib = b.items.first..name = 'Módosított';
    await b.upsert(ib);
    await b.sync();
    expect(b.items.map((e) => e.name), ['Módosított']);

    await a.sync();
    expect(a.items.map((e) => e.name), ['Módosított']);
  });

  test('feloldás: helyes jelszóval megy, rossz jelszóval hibázik, zároláskor törli a memóriát', () async {
    final server = FakeServer();
    final store = MemoryLocalStore();
    final a = _device(server, store);
    await a.init();
    await a.register(serverUrl: 'https://vault.test', email: 'a@example.com', password: _pw);
    await a.upsert(VaultItem(id: 'i1', name: 'Titkos'));
    a.lock();
    expect(a.isUnlocked, isFalse);
    expect(a.items, isEmpty);

    // újraindítás: új repository ugyanazzal a tárolóval
    final again = _device(server, store);
    await again.init();
    expect(again.hasAccount, isTrue);
    await expectLater(again.unlock('rossz-jelszo'), throwsA(isA<VaultException>()));
    expect(again.isUnlocked, isFalse);
    await again.unlock(_pw);
    expect(again.items.map((e) => e.name), ['Titkos']);
  });

  test('a helyi tároló sem tartalmaz nyílt szöveget', () async {
    final server = FakeServer();
    final store = MemoryLocalStore();
    final a = _device(server, store);
    await a.init();
    await a.register(serverUrl: 'https://vault.test', email: 'a@example.com', password: _pw);
    await a.upsert(VaultItem(id: 'i1', name: 'NyiltSzovegNev', password: 'NyiltSzovegJelszo'));
    final raw = (await store.load()).toJson().toString();
    expect(raw.contains('NyiltSzoveg'), isFalse);
  });

  test('regisztrációs kulcs nélkül nem lehet fiókot létrehozni', () async {
    final server = FakeServer()..requiredInviteCode = 'kulcs';
    final a = _device(server);
    await a.init();
    await expectLater(
      a.register(serverUrl: 'https://vault.test', email: 'a@example.com', password: _pw),
      throwsA(isA<Exception>()),
    );
    await a.register(
      serverUrl: 'https://vault.test',
      email: 'a@example.com',
      password: _pw,
      inviteCode: 'kulcs',
    );
    expect(a.hasAccount, isTrue);
  });

  test('rossz mesterjelszóval nem lehet csatlakozni meglévő fiókhoz', () async {
    final server = FakeServer();
    await _registered(server);
    final b = _device(server);
    await b.init();
    await expectLater(
      b.connect(serverUrl: 'https://vault.test', email: 'a@example.com', password: 'rossz-jelszo-123'),
      throwsA(isA<Exception>()),
    );
    expect(b.hasAccount, isFalse);
  });
}
