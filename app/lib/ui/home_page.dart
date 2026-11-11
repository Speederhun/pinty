import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/vault_item.dart';
import '../theme/pinty_theme.dart';

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
                actions: [_ThemeMenu(state: state)],
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
    return Container(
      width: 232,
      color: palette.side,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pinty',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const Spacer(),
        const Text('TÉMA', style: TextStyle(color: Color(0xFF9FBDB7), fontSize: 11, letterSpacing: 1)),
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
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _edit(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Új elem'),
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

class _ItemList extends StatelessWidget {
  const _ItemList({required this.state, required this.wide});
  final AppState state;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return const Center(child: Text('Még nincs elem. Adj hozzá egyet!'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final it in state.items)
          Card(
            child: ListTile(
              selected: wide && state.selected?.id == it.id,
              leading: CircleAvatar(child: Text(it.name.isEmpty ? '?' : it.name[0].toUpperCase())),
              title: Text(it.name),
              subtitle: Text(it.username),
              onTap: () {
                state.select(it.id);
                if (!wide) {
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
    );
  }
}

class _Detail extends StatefulWidget {
  const _Detail({required this.state});
  final AppState state;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.state.selected;
    if (it == null) return const SizedBox.shrink();
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        Expanded(child: Text(it.name, style: Theme.of(context).textTheme.headlineMedium)),
        OutlinedButton(onPressed: () => _edit(context, widget.state, it), child: const Text('Szerkesztés')),
        IconButton(
          tooltip: 'Törlés',
          onPressed: () => widget.state.remove(it.id),
          icon: const Icon(Icons.delete_outline),
        ),
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
        ]),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Egyéb információ', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Text(it.notes.isEmpty ? 'Ide bármit írhatsz: jegyzetek, kódok, emlékeztetők…' : it.notes),
          ]),
        ),
      ),
    ]);
  }

  // A vágólapot 30 másodperc után töröljük, ha még ugyanaz van benne.
  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    Future<void>.delayed(const Duration(seconds: 30), () async {
      final cur = await Clipboard.getData(Clipboard.kTextPlain);
      if (cur?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
    });
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

Future<void> _edit(BuildContext context, AppState state, [VaultItem? existing]) async {
  final name = TextEditingController(text: existing?.name);
  final user = TextEditingController(text: existing?.username);
  final pass = TextEditingController(text: existing?.password);
  final url = TextEditingController(text: existing?.url);
  final notes = TextEditingController(text: existing?.notes);
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(existing == null ? 'Új elem' : 'Elem szerkesztése'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Név')),
            const SizedBox(height: 12),
            TextField(controller: user, decoration: const InputDecoration(labelText: 'Felhasználónév')),
            const SizedBox(height: 12),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Jelszó')),
            const SizedBox(height: 12),
            TextField(controller: url, decoration: const InputDecoration(labelText: 'Weboldal')),
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
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Mentés')),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return;
  if (existing == null) {
    state.add(
      name: name.text.trim(),
      username: user.text,
      password: pass.text,
      url: url.text,
      notes: notes.text,
    );
  } else {
    existing
      ..name = name.text.trim()
      ..username = user.text
      ..password = pass.text
      ..url = url.text
      ..notes = notes.text;
    state.update(existing);
  }
}
