/// Egy széf-elem. A teljes objektum JSON-ja kerül titkosításra, a szerver
/// csak a titkosított blobot látja.
class VaultItem {
  VaultItem({
    required this.id,
    required this.name,
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
        'name': name,
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
