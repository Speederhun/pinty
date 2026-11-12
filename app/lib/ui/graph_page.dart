import 'dart:isolate';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme/pinty_theme.dart';
import '../util/note_logic.dart';
import '../i18n.dart';

/// A jegyzetek kapcsolati gráfja. Koppintásra megnyitja a jegyzetet.
class GraphPage extends StatefulWidget {
  const GraphPage({super.key, required this.state, required this.onOpen});
  final AppState state;
  final void Function(String id) onOpen;

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  bool _local = false;
  Future<_Laid>? _future;
  String _sig = '';

  /// A jelenlegi nézethez tartozó elrendezés; csak akkor számolja újra, ha a gráf megváltozott.
  Future<_Laid> _layout() {
    final idx = widget.state.noteIndex;
    var g = idx.graph();
    final current = widget.state.selectedNoteId;
    if (_local && current != null) {
      final keep = <String>{current};
      for (final (a, b) in g.edges) {
        if (a == current) keep.add(b);
        if (b == current) keep.add(a);
      }
      g = GraphData([for (final n in g.nodes) if (keep.contains(n)) n], [
        for (final e in g.edges)
          if (keep.contains(e.$1) && keep.contains(e.$2)) e
      ]);
    }
    final sig = '${_local ? current : ''}|${g.nodes.join(',')}|${g.edges.join(',')}';
    if (_future == null || sig != _sig) {
      _sig = sig;
      _future = _compute(g);
    }
    return _future!;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final p = pintyPalettes[state.theme]!;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('Gráf')),
          backgroundColor: p.bg,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilterChip(
                label: Text(tr('Csak a környezet')),
                selected: _local,
                onSelected: state.selectedNoteId == null ? null : (v) => setState(() => _local = v),
              ),
            ),
          ],
        ),
        body: FutureBuilder<_Laid>(
          future: _layout(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final laid = snap.data!;
            if (laid.graph.nodes.isEmpty) return Center(child: Text(tr('Még nincs jegyzet.')));
            return _GraphView(
              laid: laid,
              state: state,
              palette: p,
              onOpen: (id) {
                widget.onOpen(id);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      ),
    );
  }
}

Future<_Laid> _compute(GraphData graph) async =>
    _Laid(graph, await Isolate.run(() => layoutGraph(graph)));

class _Laid {
  _Laid(this.graph, this.pos);
  final GraphData graph;
  final Map<String, Point<double>> pos;
}

class _GraphView extends StatelessWidget {
  const _GraphView({required this.laid, required this.state, required this.palette, required this.onOpen});
  final _Laid laid;
  final AppState state;
  final PintyPalette palette;
  final void Function(String id) onOpen;

  static const _w = 1400.0, _h = 1000.0, _pad = 80.0;

  Offset _at(String id) {
    final p = laid.pos[id]!;
    return Offset(_pad + p.x * (_w - 2 * _pad), _pad + p.y * (_h - 2 * _pad));
  }

  @override
  Widget build(BuildContext context) {
    final idx = state.noteIndex;
    final degree = <String, int>{};
    for (final (a, b) in laid.graph.edges) {
      degree[a] = (degree[a] ?? 0) + 1;
      degree[b] = (degree[b] ?? 0) + 1;
    }
    double radius(String id) => 6 + min(10, (degree[id] ?? 0).toDouble() * 1.5);
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(400),
      minScale: 0.3,
      maxScale: 4,
      child: GestureDetector(
        onTapUp: (d) {
          String? best;
          var bestD = double.infinity;
          for (final id in laid.graph.nodes) {
            final dist = (_at(id) - d.localPosition).distance;
            if (dist < bestD) {
              bestD = dist;
              best = id;
            }
          }
          if (best != null && bestD <= radius(best) + 14) onOpen(best);
        },
        child: CustomPaint(
          size: const Size(_w, _h),
          painter: _GraphPainter(
            laid: laid,
            at: _at,
            radius: radius,
            title: (id) => idx.byId(id)?.name ?? '',
            current: state.selectedNoteId,
            palette: palette,
          ),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.laid,
    required this.at,
    required this.radius,
    required this.title,
    required this.current,
    required this.palette,
  });

  final _Laid laid;
  final Offset Function(String) at;
  final double Function(String) radius;
  final String Function(String) title;
  final String? current;
  final PintyPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = Paint()
      ..color = palette.muted.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    for (final (a, b) in laid.graph.edges) {
      canvas.drawLine(at(a), at(b), edge);
    }
    for (final id in laid.graph.nodes) {
      final on = id == current;
      canvas.drawCircle(at(id), radius(id), Paint()..color = on ? const Color(0xFFF2B632) : palette.accent);
      final tp = TextPainter(
        text: TextSpan(text: title(id), style: TextStyle(color: palette.text, fontSize: 12)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 160);
      tp.paint(canvas, at(id) + Offset(-tp.width / 2, radius(id) + 3));
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
