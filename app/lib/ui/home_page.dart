import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../models/vault_item.dart';
import '../theme/pinty_theme.dart';
import '../util/totp.dart';
import 'generator_dialog.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = pintyPalettes[state.theme]!;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      return Scaffold(
        appBar: wide
            ? null
            : AppBar(
                title: const Text('Pinty'),
                backgroundColor: p.bg,
                actions: [
                  IconButton(
                    tooltip: 'Szinkronizálás',
                    onPressed: state.sync,
                    icon: const Icon(Icons.sync),
                  ),
                  _ThemeMenu(state: state),
                  IconButton(
                    tooltip: 'Zárolás',
                    onPressed: state.lock,
                    icon: const Icon(Icons.lock_outline),
                  ),
                ],
              ),
        floatingActionButton: wide
            ? null
            : FloatingActionButton(
                onPressed: () => _edit(context, state),
                tooltip: 'Új elem',
                child: const Icon(Icons.add),
              ),
        body: Row(children: [
          if (wide) _Sidebar(state: state, palette: p),
          SizedBox(
            width: wide ? 340 : c.maxWidth,
            child: _ItemList(state: state, wide: wide),
          ),
          if (wide) Expanded(child: _Detail(state: state)),
        ]),
      );
    });
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state, required this.palette});
  final AppState state;
  final PintyPalette palette;

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFF9FBDB7);
    return Container(
      width: 232,
      color: palette.side,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pinty',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(state.email, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _edit(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Új elem'),
        ),
        const Spacer(),
        const Text('TÉMA', style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 8),
        Row(children: [
          for (final id in PintyThemeId.values)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Semantics(
                button: true,
                label: id.label,
                child: GestureDetector(
                  onTap: () => state.setTheme(id),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: id == PintyThemeId.dark
                          ? pintyPalettes[id]!.card
                          : pintyPalettes[id]!.accent,
                      border: Border.all(
                        width: 2,
                        color: state.theme == id ? const Color(0xFFF2B632) : Colors.white24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        Text(state.syncStatus ?? '', style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
          ),
          onPressed: state.sync,
          icon: const Icon(Icons.sync),
          label: const Text('Szinkronizálás'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
          ),
          onPressed: state.lock,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Zárolás most'),
        ),
      ]),
    );
  }
}

class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => PopupMenuButton<PintyThemeId>(
        icon: const Icon(Icons.palette_outlined),
        tooltip: 'Téma',
        onSelected: state.setTheme,
        itemBuilder: (_) => [
          for (final id in PintyThemeId.values) PopupMenuItem(value: id, child: Text(id.label)),
        ],
      );
}

class _ItemList extends StatefulWidget {
  const _ItemList({required this.state, required this.wide});
  final AppState state;
  final bool wide;

  @override
  State<_ItemList> createState() => _ItemListState();
}

class _ItemListState extends State<_ItemList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final q = _search.text.trim().toLowerCase();
    final shown = state.items.where((i) {
      if (q.isEmpty) return true;
      return i.name.toLowerCase().contains(q) ||
          i.username.toLowerCase().contains(q) ||
          i.url.toLowerCase().contains(q);
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Keresés…',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: shown.isEmpty
            ? Center(child: Text(state.items.isEmpty ? 'Még nincs elem. Adj hozzá egyet!' : 'Nincs találat.'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final it in shown)
                    Card(
                      child: ListTile(
                        selected: widget.wide && state.selected?.id == it.id,
                        leading: CircleAvatar(
                          child: Text(it.name.isEmpty ? '?' : it.name[0].toUpperCase()),
                        ),
                        title: Text(it.name),
                        subtitle: Text(it.username),
                        onTap: () {
                          state.select(it.id);
                          if (!widget.wide) {
                            Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(title: Text(it.name)),
                                body: ListenableBuilder(
                                  listenable: state,
                                  builder: (_, __) => _Detail(state: state),
                                ),
                              ),
                            ));
                          }
                        },
                      ),
                    ),
                ],
              ),
      ),
    ]);
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final it = state.selected;
    if (it == null) return const SizedBox.shrink();
    return _DetailBody(key: ValueKey(it.id), state: state, item: it);
  }
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({super.key, required this.state, required this.item});
  final AppState state;
  final VaultItem item;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  bool _show = false;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Törlés'),
        content: Text('Biztosan törlöd: ${widget.item.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Törlés')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.state.deleteItem(widget.item.id);
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        Expanded(child: Text(it.name, style: Theme.of(context).textTheme.headlineMedium)),
        OutlinedButton(
          onPressed: () => _edit(context, widget.state, it),
          child: const Text('Szerkesztés'),
        ),
        IconButton(tooltip: 'Törlés', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
      ]),
      const SizedBox(height: 16),
      Card(
        child: Column(children: [
          _Row(label: 'Felhasználónév', value: it.username, onCopy: () => _copy(it.username)),
          _Row(
            label: 'Jelszó',
            value: _show ? it.password : '••••••••••••',
            onCopy: () => _copy(it.password),
            extra: TextButton(
              onPressed: () => setState(() => _show = !_show),
              child: Text(_show ? 'Elrejtés' : 'Mutatás'),
            ),
          ),
          _Row(label: 'Weboldal', value: it.url),
          if (it.totpSecret.trim().isNotEmpty) _TotpTile(secret: it.totpSecret),
        ]),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Egyéb információ', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            SelectableText(
              it.notes.isEmpty ? 'Ide bármit írhatsz: jegyzetek, kódok, emlékeztetők…' : it.notes,
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _TotpTile extends StatefulWidget {
  const _TotpTile({required this.secret});
  final String secret;

  @override
  State<_TotpTile> createState() => _TotpTileState();
}

class _TotpTileState extends State<_TotpTile> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String code;
    try {
      code = totpCode(widget.secret);
    } on FormatException {
      return const ListTile(
        title: Text('Hitelesítő kód (TOTP)'),
        subtitle: Text('Érvénytelen titkos kulcs'),
      );
    }
    final remaining = totpRemaining();
    final pretty = '${code.substring(0, code.length ~/ 2)} ${code.substring(code.length ~/ 2)}';
    return ListTile(
      title: Text('Hitelesítő kód (TOTP)', style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(
        pretty,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Semantics(
            label: '$remaining másodperc van hátra',
            child: CircularProgressIndicator(value: remaining / 30, strokeWidth: 3),
          ),
        ),
        IconButton(tooltip: 'Másolás', onPressed: () => _copy(code), icon: const Icon(Icons.copy_outlined)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.onCopy, this.extra});
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(label, style: Theme.of(context).textTheme.labelMedium),
        subtitle: Text(value.isEmpty ? '–' : value, style: Theme.of(context).textTheme.bodyLarge),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (extra != null) extra!,
          if (onCopy != null)
            IconButton(tooltip: 'Másolás', onPressed: onCopy, icon: const Icon(Icons.copy_outlined)),
        ]),
      );
}

// A vágólapot 30 másodperc után töröljük, ha még ugyanaz van benne.
Future<void> _copy(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  Future<void>.delayed(const Duration(seconds: 30), () async {
    final cur = await Clipboard.getData(Clipboard.kTextPlain);
    if (cur?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
  });
}

Future<void> _edit(BuildContext context, AppState state, [VaultItem? existing]) async {
  final name = TextEditingController(text: existing?.name);
  final user = TextEditingController(text: existing?.username);
  final pass = TextEditingController(text: existing?.password);
  final url = TextEditingController(text: existing?.url);
  final totp = TextEditingController(text: existing?.totpSecret);
  final notes = TextEditingController(text: existing?.notes);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Új elem' : 'Elem szerkesztése'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Név')),
            const SizedBox(height: 12),
            TextField(controller: user, decoration: const InputDecoration(labelText: 'Felhasználónév')),
            const SizedBox(height: 12),
            TextField(
              controller: pass,
              decoration: InputDecoration(
                labelText: 'Jelszó',
                suffixIcon: IconButton(
                  tooltip: 'Jelszó generálása',
                  icon: const Icon(Icons.auto_fix_high),
                  onPressed: () async {
                    final generated = await showGeneratorDialog(ctx);
                    if (generated != null) pass.text = generated;
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: url, decoration: const InputDecoration(labelText: 'Weboldal')),
            const SizedBox(height: 12),
            TextField(
              controller: totp,
              decoration: const InputDecoration(
                labelText: 'TOTP titkos kulcs (opcionális)',
                helperText: 'Base32 kulcs vagy otpauth:// hivatkozás',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Egyéb információ', alignLabelWithHint: true),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mentés')),
      ],
    ),
  );

  final values = (
    name: name.text.trim(),
    user: user.text,
    pass: pass.text,
    url: url.text,
    totp: totp.text.trim(),
    notes: notes.text,
  );
  if (ok != true || values.name.isEmpty) return;

  final item = existing ?? VaultItem(id: const Uuid().v4(), name: values.name);
  item
    ..name = values.name
    ..username = values.user
    ..password = values.pass
    ..url = values.url
    ..totpSecret = values.totp
    ..notes = values.notes;
  await state.saveItem(item);
}
