import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/models/vault_item.dart';
import 'package:pinty/util/note_logic.dart';

VaultItem note(String id, String title, String body, {String folder = ''}) =>
    VaultItem(id: id, name: title, kind: ItemKind.note, notes: body, folder: folder);

void main() {
  test('wikilinkek kinyerése: álnév, fejezet, beágyazás, kód kihagyása', () {
    final l = extractLinks('Lásd [[Alfa]], [[Béta#Fej|álnév]] és ![[kep.png]].\n`[[kod]]`\n```\n[[blokk]]\n```');
    expect(l.map((e) => e.target), ['Alfa', 'Béta', 'kep.png']);
    expect(l[1].heading, 'Fej');
    expect(l[1].alias, 'álnév');
    expect(l[1].label, 'álnév');
    expect(l[2].embed, isTrue);
  });

  test('címkék: nem fejléc, nem szám, ékezetes és beágyazott', () {
    final t = extractTags('# Cím\nszöveg #Munka és #terv/2026 #ötlet, #1 `#kod`\n```\n#blokk\n```\nnincs#hash');
    expect(t, {'munka', 'terv/2026', 'ötlet'});
  });

  test('backlinkek, kimenő linkek, nagybetű-érzéketlen feloldás', () {
    final a = note('a', 'Alfa', 'Link: [[béta]] és [[Gamma|g]]');
    final b = note('b', 'Béta', 'Vissza: [[Alfa]]');
    final c = note('c', 'Gamma', 'üres');
    final idx = NoteIndex([a, b, c]);
    expect(idx.outgoing('a').map((n) => n.id).toSet(), {'b', 'c'});
    expect(idx.backlinks('a').map((n) => n.id), ['b']);
    expect(idx.backlinks('c').map((n) => n.id), ['a']);
    expect(idx.resolve('mappa/ALFA')?.id, 'a');
    expect(idx.resolve('nincs'), isNull);
  });

  test('nem linkelt említések', () {
    final a = note('a', 'Projekt', '');
    final b = note('b', 'X', 'a projekt jól halad');
    final c = note('c', 'Y', 'lásd [[Projekt]]');
    final idx = NoteIndex([a, b, c]);
    expect(idx.unlinkedMentions('a').map((n) => n.id), ['b']);
  });

  test('címke-összesítés és szülő címke', () {
    final idx = NoteIndex([
      note('a', 'A', '#munka/terv'),
      note('b', 'B', '#munka'),
      note('c', 'C', '#más'),
    ]);
    expect(idx.tagCounts, {'más': 1, 'munka': 1, 'munka/terv': 1});
    expect(idx.withTag('munka').map((n) => n.id), ['a', 'b']);
  });

  test('mappák és beágyazott mappák', () {
    final idx = NoteIndex([note('a', 'A', '', folder: 'Munka/2026'), note('b', 'B', '', folder: 'Otthon'), note('c', 'C', '')]);
    expect(idx.folders, ['Munka', 'Munka/2026', 'Otthon']);
    expect(idx.inFolder('Munka').map((n) => n.id), ['a']);
    expect(idx.inFolder('').length, 3);
  });

  test('keresés: szavak, tag:, folder:, kizárás, kifejezés', () {
    final idx = NoteIndex([
      note('a', 'Bevásárlás', 'tej kenyér #lista', folder: 'Otthon'),
      note('b', 'Munka terv', 'tej helyett kávé #munka'),
      note('c', 'Napló', 'semmi'),
    ]);
    expect(searchNotes(idx, 'tej').map((h) => h.note.id).toSet(), {'a', 'b'});
    expect(searchNotes(idx, 'tej tag:lista').map((h) => h.note.id), ['a']);
    expect(searchNotes(idx, 'tej -kávé').map((h) => h.note.id), ['a']);
    expect(searchNotes(idx, 'folder:otthon').map((h) => h.note.id), ['a']);
    expect(searchNotes(idx, 'tej folder:otthon').map((h) => h.note.id), ['a']);
    expect(searchNotes(idx, '"tej helyett"').map((h) => h.note.id), ['b']);
    expect(searchNotes(idx, 'terv').first.note.id, 'b'); // címtalálat
  });

  test('renderPrep: linkek, címkék, kép, kód érintetlen', () {
    final img = VaultItem(id: 'f1', name: 'kep.png', kind: ItemKind.file);
    final idx = NoteIndex([note('a', 'Alfa', '')], [img]);
    final out = renderPrep('[[Alfa|x]] #cimke ![[kep.png]] `[[Alfa]]`', idx);
    expect(out, contains('[x](pinty-note:${encodeRef('Alfa')})'));
    expect(out, contains('[#cimke](pinty-tag:${encodeRef('cimke')})'));
    expect(decodeRef(encodeRef('Ékezetes cím/1')), 'Ékezetes cím/1');
    expect(out, contains('![kep.png](pinty-file:f1)'));
    expect(out, contains('`[[Alfa]]`'));
  });

  test('fejléc-vázlat és sablon', () {
    expect(outline('# A\ntext\n## B\n```\n# nem\n```\n### C'), [(1, 'A'), (2, 'B'), (3, 'C')]);
    expect(applyTemplate('{{title}} {{date}} {{time}}', title: 'T', now: DateTime(2026, 11, 12, 9, 5)), 'T 2026-11-12 09:05');
    expect(dateTitle(DateTime(2026, 1, 2)), '2026-01-02');
  });

  test('átnevezéskor a linkek frissülnek', () {
    expect(renameLinks('[[Régi]] [[régi#F|x]] [[Más]] `[[Régi]]`', 'Régi', 'Új'), '[[Új]] [[Új#F|x]] [[Más]] `[[Régi]]`');
  });

  test('gráf-elrendezés: determinisztikus, [0,1] tartományban', () {
    final g = NoteIndex([
      note('a', 'A', '[[B]]'),
      note('b', 'B', '[[C]]'),
      note('c', 'C', ''),
      note('d', 'D', ''),
    ]).graph();
    expect(g.edges.length, 2);
    final p1 = layoutGraph(g);
    final p2 = layoutGraph(g);
    expect(p1.length, 4);
    for (final id in g.nodes) {
      expect(p1[id]!.x, p2[id]!.x);
      expect(p1[id]!.x, inInclusiveRange(0, 1));
      expect(p1[id]!.y, inInclusiveRange(0, 1));
    }
    expect(layoutGraph(GraphData([], [])), isEmpty);
  });

  test('régi (kind nélküli) elem jelszóként töltődik be', () {
    final it = VaultItem.fromJson({'id': 'x', 'name': 'n'});
    expect(it.kind, ItemKind.login);
    final n = VaultItem.fromJson(note('i', 'T', 'b').toJson());
    expect(n.kind, ItemKind.note);
  });
}
