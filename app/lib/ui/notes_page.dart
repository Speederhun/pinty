import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models/vault_item.dart';
import '../theme/pinty_theme.dart';
import '../util/note_logic.dart';
import 'folder_manager.dart';
import 'graph_page.dart';
import 'home_page.dart' show ThemeMenu;

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// A "Jegyzetek" fül: Obsidian-szerű jegyzetek a titkosított széfben.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key, required this.state});
  final AppState state;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  String? _folder; // null = minden
  String? _tag;

  AppState get state => widget.state;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<VaultItem> _shown() {
    final idx = state.noteIndex;
    final q = _search.text.trim();
    var list = q.isNotEmpty ? searchNotes(idx, q).map((h) => h.note).toList() : idx.notes.toList();
    if (_folder != null) list = list.where((n) => n.folder == _folder || n.folder.startsWith('$_folder/')).toList();
    if (_tag != null) {
      final ids = idx.withTag(_tag!).map((n) => n.id).toSet();
      list = list.where((n) => ids.contains(n.id)).toList();
    }
    return list;
  }

  Future<void> _create({String title = '', String body = '', String? folder}) async {
    final n = await state.newNote(title: title, body: body, folder: folder ?? _folder ?? '');
    if (!mounted) return;
    _open(n.id);
  }

  void _open(String id) {
    state.selectNote(id);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: state,
          builder: (_, __) => Scaffold(
            body: state.selectedNote == null
                ? const Center(child: Text('A jegyzet törölve lett.'))
                : NoteEditor(
                    key: ValueKey(state.selectedNote!.id),
                    state: state,
                    note: state.selectedNote!,
                    onOpen: _open,
                    onTag: (t) => setState(() => _tag = t),
                    wide: false,
                  ),
          ),
        ),
      ));
    }
  }

  Future<void> _daily() async {
    final n = await state.openDaily();
    if (mounted) _open(n.id);
  }

  Future<void> _fromTemplate() async {
    final templates = state.noteIndex.notes.where((n) => n.folder == 'Sablonok').toList();
    if (templates.isEmpty) {
      _toast(context, 'Hozz létre jegyzeteket a „Sablonok” mappában (pl. {{date}}, {{title}} helyőrzőkkel).');
      return;
    }
    final tpl = await showDialog<VaultItem>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Új jegyzet sablonból'),
        children: [
          for (final t in templates) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, t), child: Text(t.name)),
        ],
      ),
    );
    if (tpl == null || !mounted) return;
    final title = dateTitle(DateTime.now());
    await _create(title: title, body: applyTemplate(tpl.notes, title: title), folder: '');
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['md', 'markdown', 'txt'],
      withData: true,
    );
    if (res == null) return;
    var ok = 0, skipped = 0;
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      try {
        final dot = f.name.lastIndexOf('.');
        final title = dot > 0 ? f.name.substring(0, dot) : f.name;
        await state.newNote(title: title, body: utf8.decode(bytes, allowMalformed: true), folder: _folder ?? '');
        ok++;
      } catch (_) {
        skipped++;
      }
    }
    if (mounted) _toast(context, '$ok jegyzet importálva${skipped > 0 ? ', $skipped kihagyva (túl nagy)' : ''}.');
  }

  Future<void> _folders() async {
    final picked = await showFolderManager(context, state, 'note');
    if (picked != null && mounted) setState(() => _folder = picked.isEmpty ? null : picked);
  }

  void _graph() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GraphPage(state: state, onOpen: _open),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = pintyPalettes[state.theme]!;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final list = _NoteList(
        state: state,
        notes: _shown(),
        search: _search,
        folder: _folder,
        tag: _tag,
        onSearch: () => setState(() {}),
        onFolder: (f) => setState(() => _folder = f),
        onTag: (t) => setState(() => _tag = t),
        onOpen: _open,
        onNew: () => _create(),
        onDaily: _daily,
        onTemplate: _fromTemplate,
        onImport: _import,
        onGraph: _graph,
        onFolders: _folders,
        wide: wide,
      );
      if (!wide) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Jegyzetek'),
            backgroundColor: p.bg,
            actions: [
              IconButton(tooltip: 'Gráf', onPressed: _graph, icon: const Icon(Icons.hub_outlined)),
              IconButton(tooltip: 'Napi jegyzet', onPressed: _daily, icon: const Icon(Icons.today_outlined)),
              IconButton(tooltip: 'Szinkronizálás', onPressed: state.sync, icon: const Icon(Icons.sync)),
              ThemeMenu(state: state),
              IconButton(tooltip: 'Zárolás', onPressed: state.lock, icon: const Icon(Icons.lock_outline)),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _create(),
            tooltip: 'Új jegyzet',
            child: const Icon(Icons.add),
          ),
          body: list,
        );
      }
      final note = state.selectedNote;
      return Scaffold(
        body: Row(children: [
          SizedBox(width: 320, child: list),
          VerticalDivider(width: 1, color: p.line),
          Expanded(
            child: note == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit_note, size: 56, color: p.muted),
                      const SizedBox(height: 12),
                      const Text('Válassz egy jegyzetet, vagy hozz létre újat.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                          onPressed: () => _create(), icon: const Icon(Icons.add), label: const Text('Új jegyzet')),
                    ]),
                  )
                : NoteEditor(
                    key: ValueKey(note.id),
                    state: state,
                    note: note,
                    onOpen: _open,
                    onTag: (t) => setState(() => _tag = t),
                    wide: true,
                  ),
          ),
        ]),
      );
    });
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({
    required this.state,
    required this.notes,
    required this.search,
    required this.folder,
    required this.tag,
    required this.onSearch,
    required this.onFolder,
    required this.onTag,
    required this.onOpen,
    required this.onNew,
    required this.onDaily,
    required this.onTemplate,
    required this.onImport,
    required this.onGraph,
    required this.onFolders,
    required this.wide,
  });

  final AppState state;
  final List<VaultItem> notes;
  final TextEditingController search;
  final String? folder, tag;
  final VoidCallback onSearch, onNew, onDaily, onTemplate, onImport, onGraph, onFolders;
  final void Function(String?) onFolder, onTag;
  final void Function(String) onOpen;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final idx = state.noteIndex;
    final tags = idx.tagCounts;
    final folders = idx.folders;
    return Column(children: [
      if (wide)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 0),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add), label: const Text('Új jegyzet')),
            ),
            IconButton(tooltip: 'Napi jegyzet', onPressed: onDaily, icon: const Icon(Icons.today_outlined)),
            PopupMenuButton<String>(
              tooltip: 'Továbbiak',
              onSelected: (v) {
                switch (v) {
                  case 'graph':
                    onGraph();
                  case 'template':
                    onTemplate();
                  case 'import':
                    onImport();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'graph', child: Text('Gráf nézet')),
                PopupMenuItem(value: 'template', child: Text('Új jegyzet sablonból')),
                PopupMenuItem(value: 'import', child: Text('Markdown importálása…')),
              ],
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          controller: search,
          onChanged: (_) => onSearch(),
          decoration: InputDecoration(
            hintText: 'Keresés… (tag:címke, folder:mappa, -kizár)',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Törlés',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      search.clear();
                      onSearch();
                    },
                  ),
          ),
        ),
      ),
      if (folders.isNotEmpty || tags.isNotEmpty)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  avatar: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Mappák…'),
                  onPressed: onFolders,
                ),
              ),
              if (folder != null || tag != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.clear, size: 16),
                    label: const Text('Szűrők törlése'),
                    onPressed: () {
                      onFolder(null);
                      onTag(null);
                    },
                  ),
                ),
              for (final f in folders)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: const Icon(Icons.folder_outlined, size: 16),
                    label: Text(f),
                    selected: folder == f,
                    onSelected: (v) => onFolder(v ? f : null),
                  ),
                ),
              for (final t in tags.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text('#${t.key} ${t.value}'),
                    selected: tag == t.key,
                    onSelected: (v) => onTag(v ? t.key : null),
                  ),
                ),
            ],
          ),
        ),
      Expanded(
        child: notes.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    idx.notes.isEmpty ? 'Még nincs jegyzet. Írj egyet!' : 'Nincs találat.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: notes.length,
                itemBuilder: (context, i) {
                  final n = notes[i];
                  return ListTile(
                    dense: true,
                    selected: wide && state.selectedNoteId == n.id,
                    title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [if (n.folder.isNotEmpty) n.folder, _preview(n.notes)].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onOpen(n.id),
                  );
                },
              ),
      ),
    ]);
  }

  static String _preview(String body) =>
      body.replaceAll(RegExp(r'[#>*_`\[\]-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

enum _Mode { edit, split, preview }

/// A szerkesztő: markdown, élő előnézet, [[ ]] automatikus kiegészítés, kép beillesztés,
/// automatikus mentés és oldalpanel (visszahivatkozások, vázlat).
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.state,
    required this.note,
    required this.onOpen,
    required this.onTag,
    required this.wide,
  });

  final AppState state;
  final VaultItem note;
  final void Function(String id) onOpen;
  final void Function(String? tag) onTag;
  final bool wide;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.note.name);
  late final TextEditingController _folder = TextEditingController(text: widget.note.folder);
  late final TextEditingController _body = TextEditingController(text: widget.note.notes);
  late final FocusNode _bodyFocus = FocusNode();
  late String _savedTitle = widget.note.name;
  _Mode _mode = _Mode.edit;
  Timer? _debounce;
  String _status = '';
  bool _dirty = false;
  List<VaultItem> _suggestions = const [];
  int _linkStart = -1;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _body.addListener(_onBodyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.wide && _mode == _Mode.edit && !_modeChosen) {
      _modeChosen = true;
      if (MediaQuery.sizeOf(context).width >= 1100) _mode = _Mode.split;
    }
  }

  bool _modeChosen = false;

  @override
  void dispose() {
    _debounce?.cancel();
    if (_dirty) unawaited(_save(silent: true));
    _title.dispose();
    _folder.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _touch() {
    _dirty = true;
    _status = 'Szerkesztés…';
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
    if (mounted) setState(() {});
  }

  Future<void> _save({bool silent = false}) async {
    _debounce?.cancel();
    final note = widget.note;
    final newTitle = _title.text.trim().isEmpty ? 'Névtelen jegyzet' : _title.text.trim();
    // Két jegyzetnek nem lehet ugyanaz a címe (a [[linkek]] cím alapján oldódnak fel).
    final clash = state.noteIndex.notes.any((n) => n.id != note.id && n.name.toLowerCase() == newTitle.toLowerCase());
    if (clash) {
      if (!silent && mounted) setState(() => _status = 'Ilyen című jegyzet már van – válassz másik címet.');
      return;
    }
    note
      ..name = newTitle
      ..folder = _folder.text.trim().replaceAll(RegExp(r'^/+|/+$'), '')
      ..notes = _body.text;
    final old = _savedTitle;
    try {
      await state.saveNote(note, oldTitle: old);
      _savedTitle = newTitle;
      _dirty = false;
      if (!silent && mounted) setState(() => _status = 'Mentve');
    } catch (e) {
      if (!silent && mounted) setState(() => _status = friendlyError(e));
    }
  }

  // ----- [[ automatikus kiegészítés -----

  void _onBodyChanged() {
    final sel = _body.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _clearSuggestions();
      return;
    }
    final before = _body.text.substring(0, sel.start);
    final open = before.lastIndexOf('[[');
    if (open < 0) return _clearSuggestions();
    final typed = before.substring(open + 2);
    if (typed.contains(']') || typed.contains('\n')) return _clearSuggestions();
    final q = typed.toLowerCase();
    final list = state.noteIndex.notes
        .where((n) => n.id != widget.note.id && n.name.toLowerCase().contains(q))
        .take(6)
        .toList();
    setState(() {
      _linkStart = open;
      _suggestions = list;
    });
  }

  void _clearSuggestions() {
    if (_suggestions.isEmpty && _linkStart == -1) return;
    setState(() {
      _suggestions = const [];
      _linkStart = -1;
    });
  }

  void _acceptSuggestion(VaultItem n) {
    final sel = _body.selection;
    final text = _body.text;
    final after = text.substring(sel.start);
    final hasClose = after.startsWith(']]');
    final insert = '${n.name}]]';
    final newText = text.replaceRange(_linkStart + 2, sel.start + (hasClose ? 2 : 0), insert);
    final caret = _linkStart + 2 + insert.length;
    _body.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: caret));
    _clearSuggestions();
    _touch();
    _bodyFocus.requestFocus();
  }

  // ----- formázó gombok -----

  void _wrap(String left, [String? right]) {
    final r = right ?? left;
    final sel = _body.selection;
    final t = _body.text;
    final s = sel.isValid ? sel.start : t.length;
    final e = sel.isValid ? sel.end : t.length;
    final chosen = t.substring(s, e);
    final nt = t.replaceRange(s, e, '$left$chosen$r');
    _body.value = TextEditingValue(
      text: nt,
      selection: chosen.isEmpty
          ? TextSelection.collapsed(offset: s + left.length)
          : TextSelection(baseOffset: s + left.length, extentOffset: s + left.length + chosen.length),
    );
    _touch();
    _bodyFocus.requestFocus();
  }

  void _linePrefix(String prefix) {
    final sel = _body.selection;
    final t = _body.text;
    final s = sel.isValid ? sel.start : t.length;
    final lineStart = t.lastIndexOf('\n', s > 0 ? s - 1 : 0) + 1;
    final from = s == 0 ? 0 : lineStart;
    _body.value = TextEditingValue(
      text: t.replaceRange(from, from, prefix),
      selection: TextSelection.collapsed(offset: s + prefix.length),
    );
    _touch();
    _bodyFocus.requestFocus();
  }

  Future<void> _insertImage() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = res?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    try {
      final item = await state.addImage(f.name, f.bytes!);
      _wrap('![[${item.name}]]', '');
    } catch (e) {
      if (mounted) _toast(context, friendlyError(e));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jegyzet a kukába'),
        content: Text('A(z) „${widget.note.name}” 30 napig a kukában marad, onnan visszaállítható.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kukába')),
        ],
      ),
    );
    if (ok != true) return;
    _debounce?.cancel();
    _dirty = false;
    await state.trashItem(widget.note);
    state.selectNote(null);
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  // ----- előnézet -----

  Future<void> _onLink(String href) async {
    if (href.startsWith('$noteScheme:')) {
      final target = decodeRef(href.substring(noteScheme.length + 1));
      final found = state.noteIndex.resolve(target);
      if (found != null) {
        await _save(silent: true);
        widget.onOpen(found.id);
      } else {
        final create = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('„$target” még nem létezik'),
            content: const Text('Létrehozod ezzel a címmel?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Létrehozás')),
            ],
          ),
        );
        if (create == true) {
          await _save(silent: true);
          final n = await state.newNote(title: target, folder: widget.note.folder);
          widget.onOpen(n.id);
        }
      }
    } else if (href.startsWith('$tagScheme:')) {
      widget.onTag(decodeRef(href.substring(tagScheme.length + 1)));
    } else {
      final uri = Uri.tryParse(href);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Widget _preview(PintyPalette p) {
    final idx = state.noteIndex;
    final md = renderPrep(_body.text, idx);
    return Markdown(
      data: md.isEmpty ? '*Üres jegyzet*' : md,
      selectable: true,
      padding: const EdgeInsets.all(20),
      onTapLink: (text, href, title) {
        if (href != null) unawaited(_onLink(href));
      },
      sizedImageBuilder: (config) {
        final uri = config.uri;
        final alt = config.alt;
        if (uri.scheme == fileScheme) {
          final f = idx.files.where((x) => x.id == uri.path).firstOrNull;
          if (f != null) {
            try {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Image.memory(base64Decode(f.data), fit: BoxFit.contain),
              );
            } catch (_) {}
          }
        }
        return Text('[kép: ${alt ?? ''}]');
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        a: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
        code: TextStyle(fontFamily: 'monospace', backgroundColor: p.chip, color: p.chipText),
        codeblockDecoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8)),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: p.accent, width: 3)),
        ),
      ),
    );
  }

  Widget _editor() {
    return Column(children: [
      Expanded(
        child: TextField(
          controller: _body,
          focusNode: _bodyFocus,
          onChanged: (_) => _touch(),
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontFamily: 'monospace', height: 1.45),
          decoration: const InputDecoration(
            hintText: 'Írj ide… Markdown, [[hivatkozás]], #címke',
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(20),
          ),
        ),
      ),
      if (_suggestions.isNotEmpty)
        Material(
          elevation: 4,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final n in _suggestions)
              ListTile(
                dense: true,
                leading: const Icon(Icons.link, size: 18),
                title: Text(n.name),
                onTap: () => _acceptSuggestion(n),
              ),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = pintyPalettes[state.theme]!;
    final canSplit = MediaQuery.sizeOf(context).width >= 1000;
    final mode = (_mode == _Mode.split && !canSplit) ? _Mode.edit : _mode;
    final panelInline = MediaQuery.sizeOf(context).width >= 1280;

    final body = switch (mode) {
      _Mode.edit => _editor(),
      _Mode.preview => _preview(p),
      _Mode.split => Row(children: [
          Expanded(child: _editor()),
          VerticalDivider(width: 1, color: p.line),
          Expanded(child: _preview(p)),
        ]),
    };

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(children: [
        if (!widget.wide)
          IconButton(
            tooltip: 'Vissza',
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _save(silent: true);
              if (context.mounted) Navigator.of(context).maybePop();
            },
          ),
        Expanded(
          child: TextField(
            controller: _title,
            onChanged: (_) => _touch(),
            style: Theme.of(context).textTheme.titleLarge,
            decoration: const InputDecoration(hintText: 'Cím', border: InputBorder.none),
          ),
        ),
        SegmentedButton<_Mode>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            const ButtonSegment(value: _Mode.edit, icon: Icon(Icons.edit_outlined), tooltip: 'Szerkesztés'),
            if (canSplit) const ButtonSegment(value: _Mode.split, icon: Icon(Icons.vertical_split_outlined), tooltip: 'Osztott'),
            const ButtonSegment(value: _Mode.preview, icon: Icon(Icons.visibility_outlined), tooltip: 'Előnézet'),
          ],
          selected: {mode},
          onSelectionChanged: (s) async {
            await _save(silent: true);
            setState(() => _mode = s.first);
          },
        ),
        if (!panelInline)
          IconButton(
            tooltip: 'Kapcsolatok és vázlat',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.7,
                child: _InfoPanel(state: state, note: widget.note, onOpen: (id) {
                  Navigator.pop(ctx);
                  widget.onOpen(id);
                }),
              ),
            ),
          ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'delete') await _delete();
            if (v == 'copy') {
              await Clipboard.setData(ClipboardData(text: _body.text));
              if (context.mounted) _toast(context, 'Markdown a vágólapra másolva.');
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'copy', child: Text('Másolás markdownként')),
            PopupMenuItem(value: 'delete', child: Text('Kukába')),
          ],
        ),
      ]),
    );

    final metaRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Icon(Icons.folder_outlined, size: 16, color: p.muted),
        const SizedBox(width: 6),
        SizedBox(
          width: 200,
          child: TextField(
            controller: _folder,
            onChanged: (_) => _touch(),
            style: Theme.of(context).textTheme.bodySmall,
            decoration: const InputDecoration(hintText: 'Mappa (pl. Munka/2026)', isDense: true, border: InputBorder.none),
          ),
        ),
        IconButton(
          tooltip: 'Mappa kiválasztása',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.drive_file_move_outline, size: 18),
          onPressed: () async {
            final picked = await pickFolder(context, state, 'note', _folder.text);
            if (picked != null) {
              _folder.text = picked;
              _touch();
            }
          },
        ),
        const Spacer(),
        Flexible(child: Text(_status, style: TextStyle(color: p.muted, fontSize: 12), overflow: TextOverflow.ellipsis)),
      ]),
    );

    final toolbar = mode == _Mode.preview
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              _Tool(Icons.title, 'Fejléc', () => _linePrefix('## ')),
              _Tool(Icons.format_bold, 'Félkövér', () => _wrap('**')),
              _Tool(Icons.format_italic, 'Dőlt', () => _wrap('*')),
              _Tool(Icons.code, 'Kód', () => _wrap('`')),
              _Tool(Icons.format_list_bulleted, 'Lista', () => _linePrefix('- ')),
              _Tool(Icons.check_box_outlined, 'Teendő', () => _linePrefix('- [ ] ')),
              _Tool(Icons.format_quote, 'Idézet', () => _linePrefix('> ')),
              _Tool(Icons.link, 'Jegyzet-hivatkozás', () => _wrap('[[', ']]')),
              _Tool(Icons.tag, 'Címke', () => _wrap('#', '')),
              _Tool(Icons.image_outlined, 'Kép beszúrása', _insertImage),
            ]),
          );

    final main = Column(children: [
      header,
      metaRow,
      toolbar,
      Divider(height: 1, color: p.line),
      Expanded(child: body),
    ]);

    if (!panelInline) return main;
    return Row(children: [
      Expanded(child: main),
      VerticalDivider(width: 1, color: p.line),
      SizedBox(width: 280, child: _InfoPanel(state: state, note: widget.note, onOpen: widget.onOpen)),
    ]);
  }
}

class _Tool extends StatelessWidget {
  const _Tool(this.icon, this.tip, this.onTap);
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: tip, visualDensity: VisualDensity.compact, onPressed: onTap, icon: Icon(icon, size: 20));
}

/// Oldalpanel: visszahivatkozások, kimenő linkek, nem linkelt említések, vázlat, címkék.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.state, required this.note, required this.onOpen});
  final AppState state;
  final VaultItem note;
  final void Function(String id) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final idx = state.noteIndex;
        final back = idx.backlinks(note.id);
        final out = idx.outgoing(note.id);
        final unlinked = idx.unlinkedMentions(note.id);
        final heads = outline(note.notes);
        final tags = idx.tagsOf(note.id).toList()..sort();
        Widget section(String title, List<Widget> children) => children.isEmpty
            ? const SizedBox.shrink()
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(title, style: Theme.of(context).textTheme.labelLarge),
                ),
                ...children,
              ]);
        Widget link(VaultItem n) => ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.description_outlined, size: 18),
              title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onOpen(n.id),
            );
        return ListView(children: [
          section('Visszahivatkozások (${back.length})', [for (final n in back) link(n)]),
          if (back.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Még egy jegyzet sem hivatkozik erre.')),
          section('Kimenő hivatkozások (${out.length})', [for (final n in out) link(n)]),
          section('Nem linkelt említések (${unlinked.length})', [for (final n in unlinked) link(n)]),
          section('Vázlat', [
            for (final (level, text) in heads)
              Padding(
                padding: EdgeInsets.fromLTRB(16.0 + (level - 1) * 12, 2, 16, 2),
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ]),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tags) Chip(label: Text('#$t'))]),
            ),
        ]);
      },
    );
  }
}
