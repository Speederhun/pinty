/// Egy széf-elem. A teljes objektum JSON-ja kerül titkosításra, a szerver
/// csak a titkosított blobot látja.
/// Az elem fajtája: jelszó-bejegyzés, jegyzet vagy csatolt fájl (kép).
class ItemKind {
  static const login = 'login';
  static const note = 'note';
  static const file = 'file';

  /// Üres (vagy bármilyen) mappa külön elemként: a `name` a teljes útvonal, a `scope` pedig
  /// `login` vagy `note`.
  static const folder = 'folder';
}

class VaultItem {
  VaultItem({
    required this.id,
    required this.name,
    this.kind = ItemKind.login,
    this.tags = const [],
    this.mime = '',
    this.data = '',
    this.scope = '',
    this.trashedAt,
    List<PasswordChange>? history,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '', // "Egyéb információ": szabad szöveg
    this.totpSecret = '',
    this.folder = '',
    this.favorite = false,
    DateTime? updatedAt,
    this.rev = 0,
  })  : updatedAt = updatedAt ?? DateTime.now().toUtc(),
        history = history ?? [];

  final String id;
  String name;

  /// [ItemKind]; a régi elemeknél hiányzik, ilyenkor `login`.
  String kind;

  /// Jegyzeteknél: a szövegből függetlenül felvett címkék (a #címkék a szövegből külön számítódnak).
  List<String> tags;

  /// Csatolt fájlnál: MIME típus és a tartalom base64-ben.
  String mime;
  String data;

  /// Mappa-elemnél: melyik részhez tartozik (`login` vagy `note`).
  String scope;

  /// Ha be van állítva, az elem a kukában van (30 nap után véglegesen törlődik).
  DateTime? trashedAt;

  /// A korábbi jelszavak (legújabb elöl).
  List<PasswordChange> history;

  bool get inTrash => trashedAt != null;

  static const maxHistory = 20;

  /// Új jelszó beállítása: ha változott, a régi bekerül az előzményekbe.
  void setPassword(String next) {
    if (next == password) return;
    if (password.isNotEmpty) {
      history.insert(0, PasswordChange(password, DateTime.now().toUtc()));
      if (history.length > maxHistory) history.removeRange(maxHistory, history.length);
    }
    password = next;
  }
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
        if (scope.isNotEmpty) 'scope': scope,
        if (trashedAt != null) 'trashedAt': trashedAt!.toIso8601String(),
        if (history.isNotEmpty) 'history': [for (final h in history) h.toJson()],
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
        scope: (j['scope'] as String?) ?? '',
        trashedAt: DateTime.tryParse((j['trashedAt'] as String?) ?? ''),
        history: [
          for (final h in (j['history'] as List?) ?? const [])
            if (h is Map<String, dynamic>) PasswordChange.fromJson(h)
        ],
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

/// Egy korábbi jelszó és a lecserélésének ideje.
class PasswordChange {
  PasswordChange(this.password, this.changedAt);
  final String password;
  final DateTime changedAt;

  Map<String, dynamic> toJson() => {'p': password, 'at': changedAt.toIso8601String()};

  factory PasswordChange.fromJson(Map<String, dynamic> j) => PasswordChange(
        (j['p'] as String?) ?? '',
        DateTime.tryParse((j['at'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}
