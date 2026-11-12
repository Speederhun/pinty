import 'dart:convert';
import 'dart:math';

import '../models/vault_item.dart';
import '../i18n.dart';

/// Egy [[hivatkozás]] a jegyzet szövegében.
class WikiLink {
  const WikiLink({required this.target, this.heading = '', this.alias = '', this.embed = false});

  /// A célnév (cím vagy fájlnév), `#fejezet` és `|álnév` nélkül.
  final String target;
  final String heading;
  final String alias;

  /// `![[fájl]]` – beágyazott kép.
  final bool embed;

  String get label => alias.isNotEmpty ? alias : target;
}

final _fence = RegExp(r'^\s*(```|~~~)');
final _wiki = RegExp(r'(!?)\[\[([^\[\]\n]+?)\]\]');
final _tag = RegExp(r'(^|[\s(\[{,;])#([\p{L}\p{N}_][\p{L}\p{N}_\-/]*)', unicode: true);

/// A kódblokkon és a `kód` részleteken kívüli sorok-szövegrészek.
/// A [visit] minden nem-kód szövegrészt megkap, a többit változatlanul adja vissza.
String _mapOutsideCode(String text, String Function(String) visit) {
  final out = StringBuffer();
  var inFence = false;
  final lines = text.split('\n');
  for (var n = 0; n < lines.length; n++) {
    final line = lines[n];
    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      out.write(line);
    } else if (inFence) {
      out.write(line);
    } else {
      // soron belüli `kód` részek kihagyása
      final parts = line.split('`');
      final b = StringBuffer();
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) b.write('`');
        b.write(i.isEven ? visit(parts[i]) : parts[i]);
      }
      out.write(b);
    }
    if (n < lines.length - 1) out.write('\n');
  }
  return out.toString();
}

/// A szövegben lévő [[wikilink]]-ek és ![[beágyazások]].
List<WikiLink> extractLinks(String body) {
  final found = <WikiLink>[];
  _mapOutsideCode(body, (s) {
    for (final m in _wiki.allMatches(s)) {
      var inner = m.group(2)!;
      var alias = '';
      final bar = inner.indexOf('|');
      if (bar >= 0) {
        alias = inner.substring(bar + 1).trim();
        inner = inner.substring(0, bar);
      }
      var heading = '';
      final hash = inner.indexOf('#');
      if (hash >= 0) {
        heading = inner.substring(hash + 1).trim();
        inner = inner.substring(0, hash);
      }
      final target = inner.trim();
      if (target.isEmpty) continue;
      found.add(WikiLink(target: target, heading: heading, alias: alias, embed: m.group(1) == '!'));
    }
    return s;
  });
  return found;
}

/// A szövegben lévő #címkék (kisbetűsítve, `#` nélkül, egyedien, sorrendben).
/// A "# Cím" típusú fejléceket nem címkének veszi, a kódot kihagyja.
Set<String> extractTags(String body) {
  final tags = <String>{};
  _mapOutsideCode(body, (s) {
    for (final m in _tag.allMatches(s)) {
      final t = m.group(2)!.toLowerCase();
      if (RegExp(r'^\d+$').hasMatch(t)) continue; // "#1" nem címke
      tags.add(t);
    }
    return s;
  });
  return tags;
}

/// A weboldalon használt belső hivatkozások sémái a megjelenítéshez.
const noteScheme = 'pinty-note';
const tagScheme = 'pinty-tag';
const fileScheme = 'pinty-file';

/// A hivatkozás-célokat base64url-lel kódoljuk, hogy a markdown-feldolgozó ne írja át őket.
String encodeRef(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');

String decodeRef(String s) {
  try {
    return utf8.decode(base64Url.decode(base64Url.normalize(s)));
  } catch (_) {
    return s;
  }
}

/// A [[wikilink]]-ek, ![[képek]] és #címkék átírása szokásos markdown-hivatkozásokká
/// a megjelenítéshez. A kódot nem bántja.
String renderPrep(String body, NoteIndex index) {
  return _mapOutsideCode(body, (s) {
    var r = s.replaceAllMapped(_wiki, (m) {
      var inner = m.group(2)!;
      var alias = '';
      final bar = inner.indexOf('|');
      if (bar >= 0) {
        alias = inner.substring(bar + 1).trim();
        inner = inner.substring(0, bar);
      }
      final hash = inner.indexOf('#');
      final target = (hash >= 0 ? inner.substring(0, hash) : inner).trim();
      if (target.isEmpty) return m.group(0)!;
      if (m.group(1) == '!') {
        final f = index.fileByName(target);
        return f == null
            ? trf('*[hiányzó kép: %1]*', [_esc(target)])
            : '![${_esc(alias.isEmpty ? target : alias)}]($fileScheme:${f.id})';
      }
      final label = alias.isNotEmpty ? alias : (hash >= 0 ? inner.trim() : target);
      return '[${_esc(label)}]($noteScheme:${encodeRef(target)})';
    });
    r = r.replaceAllMapped(_tag, (m) => '${m.group(1)}[#${m.group(2)}]($tagScheme:${encodeRef(m.group(2)!.toLowerCase())})');
    return r;
  });
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('[', r'\[').replaceAll(']', r'\]');

/// A jegyzetek kapcsolatai: címfeloldás, visszahivatkozások, címkék, mappák.
class NoteIndex {
  NoteIndex(Iterable<VaultItem> notes, [Iterable<VaultItem> files = const [], Iterable<String> extraFolders = const []])
      : notes = List.unmodifiable(notes),
        files = List.unmodifiable(files),
        _extraFolders = List.unmodifiable(extraFolders) {
    for (final n in this.notes) {
      _byTitle.putIfAbsent(_key(n.name), () => n);
    }
    for (final f in this.files) {
      _fileByName.putIfAbsent(_key(f.name), () => f);
    }
    for (final n in this.notes) {
      final tags = <String>{...extractTags(n.notes), ...n.tags.map((t) => t.toLowerCase())};
      _tags[n.id] = tags;
      for (final t in tags) {
        _byTag.putIfAbsent(t, () => []).add(n);
      }
      final out = <String>{};
      for (final l in extractLinks(n.notes)) {
        if (l.embed) continue;
        final target = resolve(l.target);
        if (target != null && target.id != n.id) {
          out.add(target.id);
          (_backlinks[target.id] ??= <String>{}).add(n.id);
        }
      }
      _outgoing[n.id] = out;
    }
  }

  final List<VaultItem> notes;
  final List<VaultItem> files;
  final List<String> _extraFolders;
  final Map<String, VaultItem> _byTitle = {};
  final Map<String, VaultItem> _fileByName = {};
  final Map<String, Set<String>> _outgoing = {};
  final Map<String, Set<String>> _backlinks = {};
  final Map<String, Set<String>> _tags = {};
  final Map<String, List<VaultItem>> _byTag = {};

  static String _key(String s) => s.trim().toLowerCase();

  VaultItem? byId(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Cím szerinti feloldás (kis/nagybetűre érzéketlen); a mappa-előtag (`mappa/Cím`) is elfogadott.
  VaultItem? resolve(String target) {
    final k = _key(target);
    final direct = _byTitle[k];
    if (direct != null) return direct;
    final slash = k.lastIndexOf('/');
    if (slash >= 0) return _byTitle[k.substring(slash + 1).trim()];
    return null;
  }

  VaultItem? fileByName(String name) => _fileByName[_key(name)];

  List<VaultItem> outgoing(String id) =>
      [for (final i in (_outgoing[id] ?? const <String>{})) byId(i)].whereType<VaultItem>().toList();

  List<VaultItem> backlinks(String id) =>
      [for (final i in (_backlinks[id] ?? const <String>{})) byId(i)].whereType<VaultItem>().toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Olyan jegyzetek, amelyek kiírják a címet, de nem linkelik ([[…]] nélkül).
  List<VaultItem> unlinkedMentions(String id) {
    final me = byId(id);
    if (me == null || me.name.trim().length < 3) return const [];
    final needle = me.name.trim().toLowerCase();
    final linked = _backlinks[id] ?? const <String>{};
    return [
      for (final n in notes)
        if (n.id != id &&
            !linked.contains(n.id) &&
            _mapOutsideCode(n.notes, (s) => s.replaceAll(_wiki, '')).toLowerCase().contains(needle))
          n
    ];
  }

  Set<String> tagsOf(String id) => _tags[id] ?? const {};

  /// Címke → jegyzetek száma, betűrendben.
  Map<String, int> get tagCounts {
    final keys = _byTag.keys.toList()..sort();
    return {for (final k in keys) k: _byTag[k]!.length};
  }

  List<VaultItem> withTag(String tag) {
    final t = tag.toLowerCase();
    // egy szülő címke (pl. "munka") a gyerekeit is (pl. "munka/terv") tartalmazza
    return [
      for (final e in _byTag.entries)
        if (e.key == t || e.key.startsWith('$t/')) ...e.value
    ].toSet().toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// A mappák (egyediek, betűrendben); a beágyazottak `a/b` alakban.
  List<String> get folders {
    final set = <String>{};
    for (final n in [...notes, ..._extraFolders.map((p) => VaultItem(id: '', name: '', folder: p))]) {
      var f = n.folder.trim();
      while (f.isNotEmpty) {
        set.add(f);
        final i = f.lastIndexOf('/');
        f = i < 0 ? '' : f.substring(0, i);
      }
    }
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// A mappa közvetlen és beágyazott jegyzetei.
  List<VaultItem> inFolder(String folder) {
    final f = folder.trim();
    return [
      for (final n in notes)
        if (f.isEmpty || n.folder == f || n.folder.startsWith('$f/')) n
    ];
  }

  /// A gráf csúcsai és élei (egyszer számolt, irányítatlan párok).
  GraphData graph() {
    final edges = <(String, String)>{};
    _outgoing.forEach((from, tos) {
      for (final to in tos) {
        edges.add(from.compareTo(to) < 0 ? (from, to) : (to, from));
      }
    });
    return GraphData([for (final n in notes) n.id], edges.toList());
  }
}

class GraphData {
  GraphData(this.nodes, this.edges);
  final List<String> nodes;
  final List<(String, String)> edges;
}

/// Egyszerű erő-vezérelt (Fruchterman–Reingold) elrendezés [0,1]×[0,1] tartományban.
/// Determinisztikus: ugyanarra a bemenetre ugyanazt adja.
Map<String, Point<double>> layoutGraph(GraphData g, {int iterations = 200}) {
  final n = g.nodes.length;
  if (n == 0) return {};
  final rnd = Random(7);
  final x = List<double>.generate(n, (_) => rnd.nextDouble());
  final y = List<double>.generate(n, (_) => rnd.nextDouble());
  final idx = {for (var i = 0; i < n; i++) g.nodes[i]: i};
  final k = sqrt(1.0 / n) * 0.9;
  var temp = 0.1;
  for (var it = 0; it < iterations; it++) {
    final dx = List<double>.filled(n, 0);
    final dy = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var vx = x[i] - x[j];
        var vy = y[i] - y[j];
        var d = sqrt(vx * vx + vy * vy);
        if (d < 1e-4) {
          vx = rnd.nextDouble() - 0.5;
          vy = rnd.nextDouble() - 0.5;
          d = 1e-2;
        }
        final f = k * k / d;
        dx[i] += vx / d * f;
        dy[i] += vy / d * f;
        dx[j] -= vx / d * f;
        dy[j] -= vy / d * f;
      }
    }
    for (final (a, b) in g.edges) {
      final i = idx[a], j = idx[b];
      if (i == null || j == null) continue;
      final vx = x[i] - x[j];
      final vy = y[i] - y[j];
      final d = max(sqrt(vx * vx + vy * vy), 1e-4);
      final f = d * d / k;
      dx[i] -= vx / d * f;
      dy[i] -= vy / d * f;
      dx[j] += vx / d * f;
      dy[j] += vy / d * f;
    }
    for (var i = 0; i < n; i++) {
      // gyenge vonzás a középpont felé, hogy a különálló csoportok ne szóródjanak szét
      dx[i] += (0.5 - x[i]) * 0.5 * k;
      dy[i] += (0.5 - y[i]) * 0.5 * k;
      final d = max(sqrt(dx[i] * dx[i] + dy[i] * dy[i]), 1e-9);
      final s = min(d, temp) / d;
      x[i] += dx[i] * s;
      y[i] += dy[i] * s;
    }
    temp = max(0.002, temp * 0.97);
  }
  var minX = x.reduce(min), maxX = x.reduce(max), minY = y.reduce(min), maxY = y.reduce(max);
  final w = max(maxX - minX, 1e-6), h = max(maxY - minY, 1e-6);
  return {
    for (var i = 0; i < n; i++)
      g.nodes[i]: Point(n == 1 ? 0.5 : (x[i] - minX) / w, n == 1 ? 0.5 : (y[i] - minY) / h),
  };
}

/// Találat a keresésben.
class NoteHit {
  NoteHit(this.note, this.snippet, this.score);
  final VaultItem note;
  final String snippet;
  final int score;
}

/// Keresés. Szintaxis: szavak (mind szerepeljen), `"pontos kifejezés"`,
/// `tag:címke`, `folder:mappa`, `-szó` (kizárás).
List<NoteHit> searchNotes(NoteIndex index, String query) {
  final tokens = RegExp(r'"([^"]+)"|(\S+)').allMatches(query.trim()).map((m) => m.group(1) ?? m.group(2)!).toList();
  if (tokens.isEmpty) return [];
  final words = <String>[];
  final not = <String>[];
  final tags = <String>[];
  final folders = <String>[];
  for (final t in tokens) {
    final l = t.toLowerCase();
    if (l.startsWith('tag:') && l.length > 4) {
      tags.add(l.substring(4).replaceFirst('#', ''));
    } else if (l.startsWith('folder:') && l.length > 7) {
      folders.add(l.substring(7));
    } else if (l.startsWith('-') && l.length > 1) {
      not.add(l.substring(1));
    } else {
      words.add(l);
    }
  }
  final hits = <NoteHit>[];
  for (final n in index.notes) {
    final title = n.name.toLowerCase();
    final body = n.notes.toLowerCase();
    if (tags.any((t) => !index.tagsOf(n.id).any((x) => x == t || x.startsWith('$t/')))) continue;
    if (folders.any((f) => !n.folder.toLowerCase().contains(f))) continue;
    if (not.any((w) => title.contains(w) || body.contains(w))) continue;
    var score = 0;
    var ok = true;
    for (final w in words) {
      final inTitle = title.contains(w);
      final inBody = body.contains(w);
      if (!inTitle && !inBody) {
        ok = false;
        break;
      }
      score += (inTitle ? 10 : 0) + (inBody ? 1 : 0);
      if (title == w) score += 20;
    }
    if (!ok) continue;
    hits.add(NoteHit(n, words.isEmpty ? '' : _snippet(n.notes, words.first), score));
  }
  hits.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.note.name.toLowerCase().compareTo(b.note.name.toLowerCase());
  });
  return hits;
}

String _snippet(String body, String word) {
  final i = body.toLowerCase().indexOf(word);
  if (i < 0) return '';
  final start = max(0, i - 30);
  final end = min(body.length, i + word.length + 60);
  final s = body.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
  return '${start > 0 ? '…' : ''}$s${end < body.length ? '…' : ''}';
}

/// A fejlécek (outline): (szint, szöveg).
List<(int, String)> outline(String body) {
  final out = <(int, String)>[];
  var inFence = false;
  for (final line in body.split('\n')) {
    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final m = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$').firstMatch(line);
    if (m != null) out.add((m.group(1)!.length, m.group(2)!));
  }
  return out;
}

String two(int n) => n.toString().padLeft(2, '0');

String dateTitle(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// Sablon-helyőrzők: {{date}}, {{time}}, {{title}}.
String applyTemplate(String template, {required String title, DateTime? now}) {
  final t = now ?? DateTime.now();
  return template
      .replaceAll('{{date}}', dateTitle(t))
      .replaceAll('{{time}}', '${two(t.hour)}:${two(t.minute)}')
      .replaceAll('{{title}}', title);
}

/// Hivatkozás beszúrása/átnevezése: egy jegyzet átnevezésekor a rá mutató [[linkek]] frissítése.
String renameLinks(String body, String oldTitle, String newTitle) {
  final o = oldTitle.trim().toLowerCase();
  return _mapOutsideCode(body, (s) {
    return s.replaceAllMapped(_wiki, (m) {
      final inner = m.group(2)!;
      final bar = inner.indexOf('|');
      final namePart = bar >= 0 ? inner.substring(0, bar) : inner;
      final rest = bar >= 0 ? inner.substring(bar) : '';
      final hash = namePart.indexOf('#');
      final name = (hash >= 0 ? namePart.substring(0, hash) : namePart).trim();
      if (name.toLowerCase() != o) return m.group(0)!;
      final heading = hash >= 0 ? namePart.substring(hash) : '';
      return '${m.group(1)}[[$newTitle$heading$rest]]';
    });
  });
}
