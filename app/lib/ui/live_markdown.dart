import 'package:flutter/material.dart';

import '../theme/pinty_theme.dart';

/// Obsidian-szerű "élő nézet": ugyanabban a mezőben szerkesztesz, ahol a markdown formázva látszik.
/// A jelölők (`**`, `#`, `[[`…) azokon a soron kívül elrejtődnek, ahol épp nem áll a kurzor.
/// A szöveg maga változatlan marad, csak a megjelenítés más.
class LiveMarkdownController extends TextEditingController {
  LiveMarkdownController({super.text});

  PintyPalette? palette;
  bool live = true;

  static final _fence = RegExp(r'^\s*(```|~~~)');
  static final _heading = RegExp(r'^(#{1,6})([ \t]+)');
  static final _quote = RegExp(r'^(\s*>+[ \t]?)');
  static final _task = RegExp(r'^(\s*[-*+][ \t]+)(\[[ xX]\])([ \t]+)');
  static final _bullet = RegExp(r'^(\s*(?:[-*+]|\d+[.)])[ \t]+)');
  static final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');

  static final _inline = RegExp(
    r'`([^`\n]+)`' // 1 kód
    r'|\*\*(.+?)\*\*' // 2 félkövér
    r'|~~(.+?)~~' // 3 áthúzott
    r'|(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)' // 4 dőlt
    r'|(!?)\[\[([^\[\]\n]+?)\]\]' // 5,6 wiki / kép
    r'|\[([^\]\n]+)\]\(([^)\n]+)\)' // 7,8 link
    r'|(^|[\s(\[{,;])#([\p{L}\p{N}_][\p{L}\p{N}_\-/]*)', // 9,10 címke
    unicode: true,
  );

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final p = palette;
    if (!live || p == null || text.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final base = style ?? const TextStyle();
    final sel = selection;
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    var offset = 0;
    var inFence = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final end = offset + line.length;
      final active = sel.isValid && sel.start <= end && sel.end >= offset;
      final hide = !active;
      if (_fence.hasMatch(line)) {
        inFence = !inFence;
        spans.add(TextSpan(text: line, style: _mono(base, p, marker: true)));
      } else if (inFence) {
        spans.add(TextSpan(text: line, style: _mono(base, p)));
      } else {
        spans.addAll(_line(line, base, p, hide));
      }
      if (i < lines.length - 1) spans.add(TextSpan(text: '\n', style: base));
      offset = end + 1;
    }
    return TextSpan(style: base, children: spans);
  }

  TextStyle _mono(TextStyle base, PintyPalette p, {bool marker = false}) => base.copyWith(
        fontFamily: 'monospace',
        fontSize: (base.fontSize ?? 16) * 0.9,
        color: marker ? p.muted : p.chipText,
        backgroundColor: p.chip,
      );

  TextStyle _marker(TextStyle base, PintyPalette p, bool hide) =>
      hide ? base.copyWith(fontSize: 0.1, color: Colors.transparent) : base.copyWith(color: p.muted);

  List<InlineSpan> _line(String line, TextStyle base, PintyPalette p, bool hide) {
    if (_rule.hasMatch(line)) return [TextSpan(text: line, style: base.copyWith(color: p.muted))];

    final h = _heading.firstMatch(line);
    if (h != null) {
      final level = h.group(1)!.length;
      const scale = [1.7, 1.45, 1.25, 1.1, 1.0, 0.95];
      final hs = base.copyWith(fontSize: (base.fontSize ?? 16) * scale[level - 1], fontWeight: FontWeight.w700);
      return [
        TextSpan(text: h.group(0), style: _marker(hs, p, hide)),
        ..._inlineSpans(line.substring(h.end), hs, p, hide),
      ];
    }

    final q = _quote.firstMatch(line);
    if (q != null) {
      final qs = base.copyWith(fontStyle: FontStyle.italic, color: p.muted);
      return [
        TextSpan(text: q.group(0), style: base.copyWith(color: p.accent, fontWeight: FontWeight.w700)),
        ..._inlineSpans(line.substring(q.end), qs, p, hide),
      ];
    }

    final t = _task.firstMatch(line);
    if (t != null) {
      final done = t.group(2)!.toLowerCase().contains('x');
      final rest = done ? base.copyWith(decoration: TextDecoration.lineThrough, color: p.muted) : base;
      return [
        TextSpan(text: t.group(1), style: base.copyWith(color: p.accent)),
        TextSpan(text: t.group(2), style: base.copyWith(color: p.accent, fontWeight: FontWeight.w700)),
        TextSpan(text: t.group(3), style: base),
        ..._inlineSpans(line.substring(t.end), rest, p, hide),
      ];
    }

    final b = _bullet.firstMatch(line);
    if (b != null) {
      return [
        TextSpan(text: b.group(0), style: base.copyWith(color: p.accent, fontWeight: FontWeight.w700)),
        ..._inlineSpans(line.substring(b.end), base, p, hide),
      ];
    }
    return _inlineSpans(line, base, p, hide);
  }

  List<InlineSpan> _inlineSpans(String s, TextStyle base, PintyPalette p, bool hide, [int depth = 0]) {
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > last) out.add(TextSpan(text: s.substring(last, m.start), style: base));
      final mk = _marker(base, p, hide);
      if (m.group(1) != null) {
        out
          ..add(TextSpan(text: '`', style: mk))
          ..add(TextSpan(
            text: m.group(1),
            style: base.copyWith(fontFamily: 'monospace', backgroundColor: p.chip, color: p.chipText),
          ))
          ..add(TextSpan(text: '`', style: mk));
      } else if (m.group(2) != null) {
        out
          ..add(TextSpan(text: '**', style: mk))
          ..addAll(depth < 2 ? _inlineSpans(m.group(2)!, base.copyWith(fontWeight: FontWeight.w700), p, hide, depth + 1) : [TextSpan(text: m.group(2), style: base)])
          ..add(TextSpan(text: '**', style: mk));
      } else if (m.group(3) != null) {
        out
          ..add(TextSpan(text: '~~', style: mk))
          ..add(TextSpan(text: m.group(3), style: base.copyWith(decoration: TextDecoration.lineThrough, color: p.muted)))
          ..add(TextSpan(text: '~~', style: mk));
      } else if (m.group(4) != null) {
        out
          ..add(TextSpan(text: '*', style: mk))
          ..addAll(depth < 2 ? _inlineSpans(m.group(4)!, base.copyWith(fontStyle: FontStyle.italic), p, hide, depth + 1) : [TextSpan(text: m.group(4), style: base)])
          ..add(TextSpan(text: '*', style: mk));
      } else if (m.group(6) != null) {
        final img = m.group(5) == '!';
        final inner = m.group(6)!;
        final bar = inner.indexOf('|');
        final target = bar >= 0 ? inner.substring(0, bar) : inner;
        final alias = bar >= 0 ? inner.substring(bar + 1) : null;
        final ls = base.copyWith(color: p.accent, decoration: img ? null : TextDecoration.underline, decorationColor: p.accent);
        out.add(TextSpan(text: img ? '![[' : '[[', style: mk));
        if (alias != null && hide) {
          // a hivatkozás-cél elrejtve, csak az alias látszik
          out
            ..add(TextSpan(text: '$target|', style: mk))
            ..add(TextSpan(text: alias, style: ls));
        } else {
          out.add(TextSpan(text: inner, style: ls));
        }
        out.add(TextSpan(text: ']]', style: mk));
      } else if (m.group(7) != null) {
        final ls = base.copyWith(color: p.accent, decoration: TextDecoration.underline, decorationColor: p.accent);
        out
          ..add(TextSpan(text: '[', style: mk))
          ..add(TextSpan(text: m.group(7), style: ls))
          ..add(TextSpan(text: '](${m.group(8)})', style: mk));
      } else if (m.group(10) != null) {
        out
          ..add(TextSpan(text: m.group(9), style: base))
          ..add(TextSpan(text: '#${m.group(10)}', style: base.copyWith(color: p.accent, fontWeight: FontWeight.w600)));
      }
      last = m.end;
    }
    if (last < s.length) out.add(TextSpan(text: s.substring(last), style: base));
    return out;
  }
}
