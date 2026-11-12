import 'package:pinty/api/pinty_api.dart';
import 'package:pinty/crypto/vault_crypto.dart';

/// Memóriában élő hamis szerver, ugyanazokkal a szabályokkal, mint a valódi
/// (revíziók, ütközés 409-cel, sírkő), a szinkron-logika teszteléséhez.
class FakeServer {
  final _users = <String, _FakeUser>{};
  String? requiredInviteCode;

  /// A szerverre feltöltött összes titkosított blob (annak ellenőrzésére, hogy nincs bennük nyílt szöveg).
  final blobs = <String>[];

  RemoteApi client() => _FakeApi(this);
}

class _FakeUser {
  _FakeUser(this.authHash, this.kdf, this.wrapped);
  String authHash;
  KdfParams kdf;
  String wrapped;
  String? recoveryAuth;
  String? recoveryWrapped;
  int rev = 0;
  final items = <String, RemoteItem>{};
}

class _FakeApi implements RemoteApi {
  _FakeApi(this.server);
  final FakeServer server;
  String? _email;

  _FakeUser get _user {
    final u = _email == null ? null : server._users[_email];
    if (u == null) throw ApiException(401, 'bejelentkezés szükséges');
    return u;
  }

  @override
  Future<KdfParams> prelogin(String email) async {
    final u = server._users[email];
    if (u == null) throw ApiException(404, 'nincs ilyen felhasználó');
    return u.kdf;
  }

  @override
  Future<void> register({
    required String email,
    required String authHash,
    required KdfParams kdf,
    required String wrappedKey,
    String inviteCode = '',
  }) async {
    if (server.requiredInviteCode != null && inviteCode != server.requiredInviteCode) {
      throw ApiException(403, 'hibás regisztrációs kulcs');
    }
    if (server._users.containsKey(email)) throw ApiException(409, 'már regisztrálva van');
    server._users[email] = _FakeUser(authHash, kdf, wrappedKey);
  }

  @override
  Future<LoginResult> login(String email, String authHash) async {
    final u = server._users[email];
    if (u == null || u.authHash != authHash) throw ApiException(401, 'hibás e-mail vagy jelszó');
    _email = email;
    return LoginResult('token', u.wrapped, u.kdf);
  }

  @override
  Future<SyncResult> sync(int since) async {
    final u = _user;
    final items = u.items.values.where((i) => i.rev > since).toList()
      ..sort((a, b) => a.rev.compareTo(b.rev));
    return SyncResult(u.rev, items);
  }

  @override
  Future<int> putItem(String id, String blob, int baseRev) async {
    final u = _user;
    final cur = u.items[id];
    if (cur != null && cur.rev != baseRev) throw ConflictException(cur);
    if (cur == null && baseRev != 0) throw ApiException(404, 'az elem nem létezik');
    u.rev++;
    u.items[id] = RemoteItem(id, u.rev, false, blob);
    server.blobs.add(blob);
    return u.rev;
  }

  @override
  Future<int> deleteItem(String id, int baseRev) async {
    final u = _user;
    final cur = u.items[id];
    if (cur == null) throw ApiException(404, 'az elem nem létezik');
    if (cur.rev != baseRev) throw ConflictException(cur);
    u.rev++;
    u.items[id] = RemoteItem(id, u.rev, true, '');
    return u.rev;
  }

  @override
  Future<void> logout() async => _email = null;

  @override
  Future<void> changePassword({
    required String authHash,
    required String newAuthHash,
    required KdfParams newKdf,
    required String newWrappedKey,
  }) async {
    final u = _user;
    if (u.authHash != authHash) throw ApiException(401, 'hibás jelszó');
    u.authHash = newAuthHash;
    u.kdf = newKdf;
    u.wrapped = newWrappedKey;
  }

  @override
  Future<bool> recoveryEnabled() async => _user.recoveryAuth != null;

  @override
  Future<void> setRecovery(String recoveryAuth, String recoveryWrapped) async {
    final u = _user;
    u.recoveryAuth = recoveryAuth;
    u.recoveryWrapped = recoveryWrapped;
  }

  _FakeUser _byRecovery(String email, String proof) {
    final u = server._users[email];
    if (u == null || u.recoveryAuth == null || u.recoveryAuth != proof) {
      throw ApiException(401, 'hibás e-mail vagy visszaállító kulcs');
    }
    return u;
  }

  @override
  Future<String> recoverFetch(String email, String recoveryAuth) async =>
      _byRecovery(email, recoveryAuth).recoveryWrapped!;

  @override
  Future<void> recoverReset({
    required String email,
    required String recoveryAuth,
    required String newAuthHash,
    required KdfParams newKdf,
    required String newWrappedKey,
  }) async {
    final u = _byRecovery(email, recoveryAuth);
    u.authHash = newAuthHash;
    u.kdf = newKdf;
    u.wrapped = newWrappedKey;
  }
}
