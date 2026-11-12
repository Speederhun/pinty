/// Egy széf-elem. A teljes objektum JSON-ja kerül titkosításra, a szerver
/// csak a titkosított blobot látja.
/// Az elem fajtája: jelszó-bejegyzés, jegyzet vagy csatolt fájl (kép).
class ItemKind {
  static const login = 'login';
  static const note = 'note';
  static const file = 'file';
}

class VaultItem {
  VaultItem({
    required this.id,
    required this.name,
    this.kind = ItemKind.login,
    this.tags = const [],
    this.mime = '',
    this.data = '',
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '', // "Egyéb információ": szabad szöveg
    this.totpSecret = '',
    this.folder = '',
    this.favorite = false,
    DateTime? updatedAt,
    this.rev = 0,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  String name;

  /// [ItemKind]; a régi elemeknél hiányzik, ilyenkor `login`.
  String kind;

  /// Jegyzeteknél: a szövegből függetlenül felvett címkék (a #címkék a szövegből külön számítódnak).
  List<String> tags;

  /// Csatolt fájlnál: MIME típus és a tartalom base64-ben.
  String mime;
  String data;
  String username;
  String password;
  String url;
  String notes;
  String totpSecret;
  String folder;
  bool favorite;
  DateTime updatedAt;

  /// A szerveren lévő utolsó ismert revízió (0 = még nem szinkronizált).
  /// Nem része a titkosított tartalomnak.
  int rev;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        if (tags.isNotEmpty) 'tags': tags,
        if (mime.isNotEmpty) 'mime': mime,
        if (data.isNotEmpty) 'data': data,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'totpSecret': totpSecret,
        'folder': folder,
        'favorite': favorite,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VaultItem.fromJson(Map<String, dynamic> j, {int rev = 0}) => VaultItem(
        id: j['id'] as String,
        kind: (j['kind'] as String?) ?? ItemKind.login,
        tags: ((j['tags'] as List?) ?? const []).whereType<String>().toList(),
        mime: (j['mime'] as String?) ?? '',
        data: (j['data'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        username: (j['username'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
        totpSecret: (j['totpSecret'] as String?) ?? '',
        folder: (j['folder'] as String?) ?? '',
        favorite: (j['favorite'] as bool?) ?? false,
        updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? ''),
        rev: rev,
      );
}
