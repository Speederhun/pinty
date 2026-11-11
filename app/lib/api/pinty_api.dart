import 'dart:convert';

import 'package:http/http.dart' as http;

import '../crypto/vault_crypto.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'ApiException($status): $message';
}

/// 409-es válasz: valaki közben módosította az elemet; [current] a szerveren lévő állapot.
class ConflictException extends ApiException {
  ConflictException(this.current) : super(409, 'ütközés');
  final RemoteItem? current;
}

class RemoteItem {
  RemoteItem(this.id, this.rev, this.deleted, this.blob);
  final String id;
  final int rev;
  final bool deleted;
  final String blob;

  factory RemoteItem.fromJson(Map<String, dynamic> j) => RemoteItem(
        j['id'] as String,
        j['rev'] as int,
        j['deleted'] as bool,
        j['blob'] as String,
      );
}

class LoginResult {
  LoginResult(this.token, this.wrappedKey, this.kdf);
  final String token;
  final String wrappedKey;
  final KdfParams kdf;
}

class SyncResult {
  SyncResult(this.rev, this.items);
  final int rev;
  final List<RemoteItem> items;
}

/// A szerver-kapcsolat felülete (a tesztekben hamis szerverrel cserélhető).
abstract class RemoteApi {
  Future<KdfParams> prelogin(String email);
  Future<void> register({
    required String email,
    required String authHash,
    required KdfParams kdf,
    required String wrappedKey,
    String setupToken = '',
  });
  Future<LoginResult> login(String email, String authHash);
  Future<SyncResult> sync(int since);
  Future<int> putItem(String id, String blob, int baseRev);
  Future<int> deleteItem(String id, int baseRev);
  Future<void> logout();
}

/// A Pinty szinkron-szerver kliense. Csak titkosított adat és auth hash megy ki.
class PintyApi implements RemoteApi {
  PintyApi(this.baseUrl, {http.Client? client}) : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  String? token;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse(baseUrl).replace(path: '/api/v1/$path', queryParameters: q);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _check(http.Response r) {
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode == 409) {
      final cur = body['current'];
      throw ConflictException(cur == null ? null : RemoteItem.fromJson(cur as Map<String, dynamic>));
    }
    if (r.statusCode >= 400) {
      throw ApiException(r.statusCode, (body['error'] as String?) ?? 'hiba');
    }
    return body;
  }

  @override
  Future<KdfParams> prelogin(String email) async {
    final r = await _http.get(_u('prelogin', {'email': email}), headers: _headers);
    return KdfParams.fromJson(_check(r)['kdf'] as Map<String, dynamic>);
  }

  @override
  Future<void> register({
    required String email,
    required String authHash,
    required KdfParams kdf,
    required String wrappedKey,
    String setupToken = '',
  }) async {
    final r = await _http.post(
      _u('register'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'auth_hash': authHash,
        'kdf': kdf.toJson(),
        'wrapped_key': wrappedKey,
        if (setupToken.isNotEmpty) 'setup_token': setupToken,
      }),
    );
    _check(r);
  }

  @override
  Future<LoginResult> login(String email, String authHash) async {
    final r = await _http.post(
      _u('login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'auth_hash': authHash}),
    );
    final b = _check(r);
    token = b['token'] as String;
    return LoginResult(
      token!,
      b['wrapped_key'] as String,
      KdfParams.fromJson(b['kdf'] as Map<String, dynamic>),
    );
  }

  @override
  Future<SyncResult> sync(int since) async {
    final r = await _http.get(_u('sync', {'since': '$since'}), headers: _headers);
    final b = _check(r);
    return SyncResult(
      b['rev'] as int,
      (b['items'] as List).map((e) => RemoteItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Visszaadja az elem új szerver-revízióját.
  @override
  Future<int> putItem(String id, String blob, int baseRev) async {
    final r = await _http.put(
      _u('items/$id'),
      headers: _headers,
      body: jsonEncode({'blob': blob, 'base_rev': baseRev}),
    );
    return _check(r)['rev'] as int;
  }

  @override
  Future<int> deleteItem(String id, int baseRev) async {
    final r = await _http.delete(_u('items/$id', {'base_rev': '$baseRev'}), headers: _headers);
    return _check(r)['rev'] as int;
  }

  @override
  Future<void> logout() async {
    await _http.post(_u('logout'), headers: _headers);
    token = null;
  }
}
