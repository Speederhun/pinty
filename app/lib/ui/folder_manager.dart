import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';

/// Mappakezelő: fa nézet, új (üres) mappa, almappa, átnevezés/áthelyezés, törlés.
/// Mappára koppintva visszaadja annak útvonalát (üres szöveg = az összes). `scope`: `login` vagy `note`.
Future<String?> showFolderManager(BuildContext context, AppState state, String scope) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FolderManager(state: state, scope: scope),
  );
}

/// Mappaválasztó egy elem áthelyezéséhez. Visszaadja a választott útvonalat ('' = gyökér), vagy null-t, ha mégse.
Future<String?> pickFolder(BuildContext context, AppState state, String scope, String current) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final folders = state.foldersFor(scope);
      return SimpleDialog(
        title: Text(tr('Mappa kiválasztása')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Row(children: [
              Icon(current.isEmpty ? Icons.check : Icons.folder_off_outlined, size: 18),
              const SizedBox(width: 8),
              Text(tr('Nincs mappa')),
            ]),
          ),
          for (final f in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f),
              child: Padding(
                padding: EdgeInsets.only(left: 14.0 * '/'.allMatches(f).length),
                child: Row(children: [
                  Icon(f == current ? Icons.check : Icons.folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Flexible(child: Text(f.split('/').last)),
                ]),
              ),
            ),
          SimpleDialogOption(
            onPressed: () async {
              final name = await _askName(ctx, tr('Új mappa'), '');
              if (name == null || name.trim().isEmpty) return;
              final path = AppState.cleanPath(name);
              await state.createFolder(scope, path);
              if (ctx.mounted) Navigator.pop(ctx, path);
            },
            child: Row(children: [Icon(Icons.create_new_folder_outlined, size: 18), SizedBox(width: 8), Text(tr('Új mappa…'))]),
          ),
        ],
      );
    },
  );
}

/// Név bekérése (mappa létrehozásához / átnevezéséhez).
Future<String?> askFolderName(BuildContext context, String title, String initial, {String? hint}) =>
    _askName(context, title, initial, hint: hint);

Future<String?> _askName(BuildContext context, String title, String initial, {String? hint}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint ?? tr('pl. Munka/2026')),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Mégse'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Mentés'))),
      ],
    ),
  );
}

class _FolderManager extends StatelessWidget {
  const _FolderManager({required this.state, required this.scope});
  final AppState state;
  final String scope;

  int _count(String f) {
    final items = scope == 'note' ? state.noteIndex.notes : state.items;
    return items.where((i) => i.folder == f || i.folder.startsWith('$f/')).length;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final folders = state.foldersFor(scope);
        return AlertDialog(
          title: Text(tr('Mappák')),
          content: SizedBox(
            width: 420,
            child: folders.isEmpty
                ? Text(tr('Még nincs mappa. Hozz létre egyet!'))
                : ListView(shrinkWrap: true, children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.all_inbox_outlined, size: 20),
                      title: Text(tr('Az összes')),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                    for (final f in folders)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.only(left: 16.0 + 16.0 * '/'.allMatches(f).length, right: 4),
                        leading: const Icon(Icons.folder_outlined, size: 20),
                        title: Text(f.split('/').last),
                        subtitle: Text(trf('%1 elem', [_count(f)])),
                        onTap: () => Navigator.pop(context, f),
                        trailing: PopupMenuButton<String>(
                          tooltip: tr('Mappa műveletei'),
                          onSelected: (v) async {
                            switch (v) {
                              case 'sub':
                                final n = await _askName(context, trf('Új almappa a(z) „%1” alatt', [f]), '', hint: tr('Mappa neve'));
                                if (n != null && n.trim().isNotEmpty) await state.createFolder(scope, '$f/${AppState.cleanPath(n)}');
                              case 'rename':
                                final n = await _askName(context, tr('Mappa átnevezése / áthelyezése'), f);
                                if (n != null && n.trim().isNotEmpty) await state.renameFolder(scope, f, n);
                              case 'delete':
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(trf('„%1” törlése', [f])),
                                    content: Text(tr('A mappa megszűnik, a benne lévő elemek a szülő-mappába kerülnek. Semmi sem törlődik.')),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Mégse'))),
                                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Mappa törlése'))),
                                    ],
                                  ),
                                );
                                if (ok == true) await state.deleteFolder(scope, f);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'sub', child: Text(tr('Új almappa'))),
                            PopupMenuItem(value: 'rename', child: Text(tr('Átnevezés / áthelyezés'))),
                            PopupMenuItem(value: 'delete', child: Text(tr('Törlés'))),
                          ],
                        ),
                      ),
                  ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final n = await _askName(context, tr('Új mappa'), '');
                if (n != null && n.trim().isNotEmpty) await state.createFolder(scope, n);
              },
              child: Text(tr('Új mappa')),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bezár'))),
          ],
        );
      },
    );
  }
}
