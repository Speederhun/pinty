import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/backup.dart';
import '../models/vault_item.dart';
import '../theme/pinty_theme.dart';
import '../util/security_audit.dart';

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<String?> _askPassword(BuildContext context, String title, String message, {bool confirm = false}) {
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(controller: a, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Jelszó')),
            if (confirm) ...[
              const SizedBox(height: 12),
              TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Jelszó újra')),
            ],
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mégse')),
          FilledButton(
            onPressed: () {
              if (a.text.length < 8) {
                setS(() => err = 'Legalább 8 karakter legyen.');
              } else if (confirm && a.text != b.text) {
                setS(() => err = 'A két jelszó nem egyezik.');
              } else {
                Navigator.pop(ctx, a.text);
              }
            },
            child: const Text('Tovább'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _saveBytes(String name, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(dialogTitle: 'Mentés', fileName: name, bytes: bytes);
  if (path == null) return false;
  if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
  return true;
}

/// Beállítások fül: biztonság, adatok, kuka, téma.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = pintyPalettes[state.theme]!;
    return Scaffold(
      appBar: AppBar(title: const Text('Beállítások'), backgroundColor: p.bg),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _section(context, 'Fiók', [
                    ListTile(title: const Text('E-mail'), subtitle: Text(state.email)),
                    ListTile(title: const Text('Szerver'), subtitle: Text(state.serverUrl)),
                    ListTile(title: const Text('Szinkron'), subtitle: Text(state.syncStatus ?? '–')),
                  ]),
                  _section(context, 'Biztonság', [
                    if (state.biometricAvailable)
                      SwitchListTile(
                        title: const Text('Biometrikus feloldás'),
                        subtitle: const Text('Ujjlenyomat, arc vagy eszköz-PIN a mesterjelszó helyett. A kulcsot az operációs rendszer tárolója őrzi.'),
                        value: state.biometricEnabled,
                        onChanged: (v) async {
                          if (v) {
                            final ok = await state.enableBiometric();
                            if (!ok && context.mounted && state.error != null) _toast(context, state.error!);
                          } else {
                            await state.disableBiometric();
                          }
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.password),
                      title: const Text('Mesterjelszó cseréje'),
                      onTap: () => _changePassword(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.key),
                      title: const Text('Visszaállító kulcs'),
                      subtitle: const Text('Ha elfelejted a mesterjelszót, ezzel még hozzáférsz a széfhez.'),
                      onTap: () => showRecoverySetup(context, state),
                    ),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Biztonsági ellenőrzés'),
                      subtitle: const Text('Gyenge, ismétlődő és régi jelszavak'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AuditPage(state: state))),
                    ),
                  ]),
                  _section(context, 'Adatok', [
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Kuka'),
                      subtitle: Text('${state.trashed.length} elem · 30 nap után véglegesen törlődik'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TrashPage(state: state))),
                    ),
                    ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: const Text('Titkosított mentés exportálása'),
                      subtitle: const Text('Minden jelszó, jegyzet és kép egy jelszóval védett fájlban.'),
                      onTap: () => _exportBackup(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.table_chart_outlined),
                      title: const Text('Jelszavak exportálása CSV-be'),
                      subtitle: const Text('Titkosítatlan! Csak más programba költözéshez.'),
                      onTap: () => _exportCsv(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: const Text('Importálás'),
                      subtitle: const Text('Pinty-mentés, Chrome/Firefox/Bitwarden/1Password CSV, Bitwarden JSON'),
                      onTap: () => _import(context),
                    ),
                  ]),
                  _section(context, 'Megjelenés', [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(spacing: 8, children: [
                        for (final id in PintyThemeId.values)
                          ChoiceChip(label: Text(id.label), selected: state.theme == id, onSelected: (_) => state.setTheme(id)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: state.lock, icon: const Icon(Icons.lock_outline), label: const Text('Zárolás most')),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          Card(margin: EdgeInsets.zero, child: Column(children: children)),
        ]),
      );

  Future<void> _changePassword(BuildContext context) async {
    final old = TextEditingController();
    final n1 = TextEditingController();
    final n2 = TextEditingController();
    String? err;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Mesterjelszó cseréje'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: old, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Jelenlegi mesterjelszó')),
              const SizedBox(height: 12),
              TextField(controller: n1, obscureText: true, decoration: const InputDecoration(labelText: 'Új mesterjelszó (legalább 12 karakter)')),
              const SizedBox(height: 12),
              TextField(controller: n2, obscureText: true, decoration: const InputDecoration(labelText: 'Új mesterjelszó újra')),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
              const SizedBox(height: 8),
              const Text('Más eszközökön újra be kell majd jelentkezned az új jelszóval.', style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
            FilledButton(
              onPressed: () async {
                if (n1.text.length < 12) {
                  setS(() => err = 'Az új mesterjelszó legyen legalább 12 karakter.');
                  return;
                }
                if (n1.text != n2.text) {
                  setS(() => err = 'A két új jelszó nem egyezik.');
                  return;
                }
                final ok = await state.changeMasterPassword(old.text, n1.text);
                if (ok) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setS(() => err = state.error);
                }
              },
              child: const Text('Csere'),
            ),
          ],
        ),
      ),
    );
    if (done == true && context.mounted) _toast(context, 'A mesterjelszó megváltozott.');
  }

  Future<void> _exportBackup(BuildContext context) async {
    final pw = await _askPassword(
      context,
      'Titkosított mentés',
      'Add meg a mentés jelszavát. Ez nem azonos a mesterjelszóval, és nélküle a mentés nem nyitható meg.',
      confirm: true,
    );
    if (pw == null) return;
    try {
      final bytes = await state.exportBackup(pw);
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final ok = await _saveBytes('pinty-mentes-$stamp.pintybackup', bytes);
      if (context.mounted && ok) _toast(context, 'A mentés elkészült.');
    } catch (e) {
      if (context.mounted) _toast(context, friendlyError(e));
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Titkosítatlan export'),
        content: const Text('A CSV fájlban a jelszavaid olvasható szövegként szerepelnek. Használat után töröld, és ne tárold felhőben.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exportálás')),
        ],
      ),
    );
    if (ok != true) return;
    final saved = await _saveBytes('pinty-jelszavak.csv', Uint8List.fromList(utf8.encode(state.exportCsvText())));
    if (context.mounted && saved) _toast(context, 'A CSV elkészült. Ne felejtsd el törölni használat után.');
  }

  Future<void> _import(BuildContext context) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pintybackup', 'json', 'csv'],
      withData: true,
    );
    final f = res?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    try {
      final List<VaultItem> items;
      var skipped = 0;
      final head = utf8.decode(f.bytes!, allowMalformed: true);
      if (head.contains('"format":"pinty-backup"') || head.contains('"format": "pinty-backup"')) {
        if (!context.mounted) return;
        final pw = await _askPassword(context, 'Mentés megnyitása', 'Add meg a mentés jelszavát.');
        if (pw == null) return;
        items = await Backup.import(f.bytes!, pw);
      } else if (f.name.toLowerCase().endsWith('.csv')) {
        final r = importCsv(head);
        items = r.items;
        skipped = r.skipped;
      } else {
        final r = importBitwardenJson(head);
        items = r.items;
        skipped = r.skipped;
      }
      final (added, dup) = await state.importItems(items);
      if (context.mounted) {
        _toast(context, '$added elem importálva${dup + skipped > 0 ? ', ${dup + skipped} kihagyva (már megvan vagy nem támogatott)' : ''}.');
      }
    } catch (e) {
      if (context.mounted) _toast(context, e is BackupException ? e.message : friendlyError(e));
    }
  }
}

/// A visszaállító kulcs létrehozása. A kulcsot csak most mutatjuk meg, sehol nincs eltárolva.
Future<void> showRecoverySetup(BuildContext context, AppState state) async {
  final enabled = await state.recoveryEnabled();
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Visszaállító kulcs'),
      content: Text(
        enabled
            ? 'Már van visszaállító kulcsod. Újat készíthetsz, de akkor a régi érvénytelen lesz.'
            : 'A mesterjelszót elfelejtve a széf nem nyitható meg, mert a szerver sem ismeri. A visszaállító kulcs ezt kerüli meg: '
                'írd fel papírra, és tárold biztonságos helyen (nem a telefonban vagy felhőben).',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Később')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(enabled ? 'Új kulcs készítése' : 'Kulcs készítése')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final key = await state.createRecoveryKey();
  if (!context.mounted) return;
  if (key == null) {
    _toast(context, state.error ?? 'Nem sikerült a kulcs létrehozása.');
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Írd fel ezt a kulcsot'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SelectableText(key, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, height: 1.6, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text('Ez az egyetlen alkalom, hogy látod. Aki ismeri, hozzáfér a széfedhez, ezért ne oszd meg senkivel.'),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: key));
            if (ctx.mounted) _toast(ctx, 'Vágólapra másolva. Ne felejtsd el törölni.');
          },
          child: const Text('Másolás'),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Felírtam')),
      ],
    ),
  );
}

class TrashPage extends StatelessWidget {
  const TrashPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final list = state.trashed;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Kuka'),
            actions: [
              if (list.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Kuka ürítése'),
                        content: const Text('Minden elem véglegesen törlődik, nem állítható vissza.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ürítés')),
                        ],
                      ),
                    );
                    if (ok == true) await state.emptyTrash();
                  },
                  child: const Text('Kuka ürítése'),
                ),
            ],
          ),
          body: list.isEmpty
              ? const Center(child: Text('A kuka üres.'))
              : ListView(children: [
                  for (final i in list)
                    ListTile(
                      leading: Icon(i.kind == ItemKind.note ? Icons.description_outlined : Icons.key_outlined),
                      title: Text(i.name),
                      subtitle: Text(
                        '${i.kind == ItemKind.note ? 'Jegyzet' : 'Jelszó'} · ${30 - DateTime.now().toUtc().difference(i.trashedAt!).inDays} nap múlva törlődik',
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(onPressed: () => state.restoreItem(i), child: const Text('Visszaállítás')),
                        IconButton(
                          tooltip: 'Végleges törlés',
                          icon: const Icon(Icons.delete_forever_outlined),
                          onPressed: () async {
                            await state.deleteForever(i.id);
                          },
                        ),
                      ]),
                    ),
                ]),
        );
      },
    );
  }
}

class AuditPage extends StatelessWidget {
  const AuditPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final r = auditLogins(state.items);
    final scoreColor = r.score >= 80 ? Colors.green : (r.score >= 50 ? Colors.orange : Colors.red);

    Widget group(String title, String hint, List<VaultItem> items, {String Function(VaultItem)? sub}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Card(
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text('$title (${items.length})'),
          subtitle: Text(hint),
          children: [
            for (final i in items)
              ListTile(
                dense: true,
                title: Text(i.name),
                subtitle: Text(sub?.call(i) ?? i.username),
                onTap: () {
                  state.select(i.id);
                  state.setTab(0);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Biztonsági ellenőrzés')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Text('${r.score}', style: Theme.of(context).textTheme.displayMedium?.copyWith(color: scoreColor, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(r.total == 0
                          ? 'Még nincs elmentett jelszó.'
                          : r.problems == 0
                              ? 'Minden jelszavad rendben van.'
                              : '${r.problems} elemet érdemes megnézni ${r.total} jelszóból.'),
                    ),
                  ]),
                ),
              ),
              group('Gyenge jelszavak', 'Rövidek, kitalálhatók vagy gyakoriak. Generálj helyette erőset.', r.weak,
                  sub: (i) => strengthOf(i.password).label),
              group('Ismétlődő jelszavak', 'Egy kiszivárgás több fiókodat is veszélybe sodorja.', [for (final g in r.reused) ...g],
                  sub: (i) => 'Ugyanazt használja ${r.reused.firstWhere((g) => g.contains(i)).length} elem'),
              group('Régi jelszavak', 'Több mint egy éve nem változtak.', r.old,
                  sub: (i) => 'Utoljára: ${i.updatedAt.toLocal().toString().substring(0, 10)}'),
              group('Jelszó nélküli elemek', 'Nincs jelszó megadva.', r.noPassword),
            ]),
          ),
        ),
      ]),
    );
  }
}
