import 'package:flutter/material.dart';
import '../i18n.dart';

/// A beépített témák.
enum PintyThemeId { light, dark, ocean, rose, sepia, solarized, lavender, sunset, midnight, forest, nord, dracula, amoled }

extension PintyThemeLabel on PintyThemeId {
  String get label => switch (this) {
        PintyThemeId.light => tr('Világos'),
        PintyThemeId.dark => tr('Sötét'),
        PintyThemeId.ocean => tr('Óceán'),
        PintyThemeId.rose => tr('Rózsa'),
        PintyThemeId.sepia => tr('Szépia'),
        PintyThemeId.solarized => 'Solarized',
        PintyThemeId.lavender => tr('Levendula'),
        PintyThemeId.sunset => tr('Naplemente'),
        PintyThemeId.midnight => tr('Éjkék'),
        PintyThemeId.forest => tr('Erdő'),
        PintyThemeId.nord => 'Nord',
        PintyThemeId.dracula => 'Dracula',
        PintyThemeId.amoled => tr('AMOLED fekete'),
      };
}

class PintyPalette {
  const PintyPalette({
    required this.bg,
    required this.card,
    required this.line,
    required this.text,
    required this.muted,
    required this.chip,
    required this.chipText,
    required this.side,
    required this.accent,
    required this.brightness,
  });

  final Color bg, card, line, text, muted, chip, chipText, side, accent;
  final Brightness brightness;
}

const pintyPalettes = <PintyThemeId, PintyPalette>{
  PintyThemeId.light: PintyPalette(
    bg: Color(0xFFF4F1EA), card: Color(0xFFFFFFFF), line: Color(0xFFE1DCD0),
    text: Color(0xFF17211F), muted: Color(0xFF5A6663), chip: Color(0xFFEEF3F1),
    chipText: Color(0xFF0A3F3A), side: Color(0xFF0E3A35), accent: Color(0xFF0F5C54),
    brightness: Brightness.light,
  ),
  PintyThemeId.dark: PintyPalette(
    bg: Color(0xFF111716), card: Color(0xFF1B2321), line: Color(0xFF2B3633),
    text: Color(0xFFE8EFED), muted: Color(0xFF9DB0AB), chip: Color(0xFF26332F),
    chipText: Color(0xFFBFE6DC), side: Color(0xFF0A0F0E), accent: Color(0xFF1F7F72),
    brightness: Brightness.dark,
  ),
  PintyThemeId.ocean: PintyPalette(
    bg: Color(0xFFEEF3F8), card: Color(0xFFFFFFFF), line: Color(0xFFD5E0EC),
    text: Color(0xFF14202E), muted: Color(0xFF51627A), chip: Color(0xFFE3ECF7),
    chipText: Color(0xFF123F73), side: Color(0xFF12315A), accent: Color(0xFF1E5FB3),
    brightness: Brightness.light,
  ),
  PintyThemeId.rose: PintyPalette(
    bg: Color(0xFFF8F0EF), card: Color(0xFFFFFFFF), line: Color(0xFFEBD9D6),
    text: Color(0xFF2A1B1B), muted: Color(0xFF735A58), chip: Color(0xFFF5E6E4),
    chipText: Color(0xFF6B1F2E), side: Color(0xFF4A1F2B), accent: Color(0xFFA3304A),
    brightness: Brightness.light,
  ),
  PintyThemeId.sepia: PintyPalette(
    bg: Color(0xFFF3EAD7), card: Color(0xFFFBF5E6), line: Color(0xFFE0D3B8),
    text: Color(0xFF3B2F1E), muted: Color(0xFF7A6A4F), chip: Color(0xFFEDE2C8),
    chipText: Color(0xFF5A3E12), side: Color(0xFF4A3A22), accent: Color(0xFF9A5B13),
    brightness: Brightness.light,
  ),
  PintyThemeId.solarized: PintyPalette(
    bg: Color(0xFFFDF6E3), card: Color(0xFFFFFBEF), line: Color(0xFFE6DDC3),
    text: Color(0xFF073642), muted: Color(0xFF657B83), chip: Color(0xFFEEE8D5),
    chipText: Color(0xFF073642), side: Color(0xFF073642), accent: Color(0xFF268BD2),
    brightness: Brightness.light,
  ),
  PintyThemeId.lavender: PintyPalette(
    bg: Color(0xFFF3F0FA), card: Color(0xFFFFFFFF), line: Color(0xFFE0D9F0),
    text: Color(0xFF21192F), muted: Color(0xFF6B6285), chip: Color(0xFFEAE4F7),
    chipText: Color(0xFF3F2A78), side: Color(0xFF2E2150), accent: Color(0xFF6B4FD1),
    brightness: Brightness.light,
  ),
  PintyThemeId.sunset: PintyPalette(
    bg: Color(0xFFFBF1EA), card: Color(0xFFFFFFFF), line: Color(0xFFF0DACB),
    text: Color(0xFF2B1A12), muted: Color(0xFF7C5E4C), chip: Color(0xFFF8E6DA),
    chipText: Color(0xFF7A2E0E), side: Color(0xFF5A2410), accent: Color(0xFFD2561E),
    brightness: Brightness.light,
  ),
  PintyThemeId.midnight: PintyPalette(
    bg: Color(0xFF0B1020), card: Color(0xFF141B30), line: Color(0xFF232C47),
    text: Color(0xFFE6EAF6), muted: Color(0xFF93A0C4), chip: Color(0xFF1C2542),
    chipText: Color(0xFFBFCBFF), side: Color(0xFF070B16), accent: Color(0xFF4F7CFF),
    brightness: Brightness.dark,
  ),
  PintyThemeId.forest: PintyPalette(
    bg: Color(0xFF0F1A14), card: Color(0xFF16251D), line: Color(0xFF24382C),
    text: Color(0xFFE4F0E8), muted: Color(0xFF92AE9C), chip: Color(0xFF1F3329),
    chipText: Color(0xFFBDE8CC), side: Color(0xFF09110C), accent: Color(0xFF3FA66B),
    brightness: Brightness.dark,
  ),
  PintyThemeId.nord: PintyPalette(
    bg: Color(0xFF2E3440), card: Color(0xFF3B4252), line: Color(0xFF4C566A),
    text: Color(0xFFECEFF4), muted: Color(0xFFA6B0C3), chip: Color(0xFF434C5E),
    chipText: Color(0xFF88C0D0), side: Color(0xFF242933), accent: Color(0xFF81A1C1),
    brightness: Brightness.dark,
  ),
  PintyThemeId.dracula: PintyPalette(
    bg: Color(0xFF282A36), card: Color(0xFF343746), line: Color(0xFF44475A),
    text: Color(0xFFF8F8F2), muted: Color(0xFFA0A4C0), chip: Color(0xFF3C3F52),
    chipText: Color(0xFFBD93F9), side: Color(0xFF1E1F29), accent: Color(0xFF9D6BF0),
    brightness: Brightness.dark,
  ),
  PintyThemeId.amoled: PintyPalette(
    bg: Color(0xFF000000), card: Color(0xFF0E0E0E), line: Color(0xFF222222),
    text: Color(0xFFEDEDED), muted: Color(0xFF9A9A9A), chip: Color(0xFF1A1A1A),
    chipText: Color(0xFFD0D0D0), side: Color(0xFF000000), accent: Color(0xFF2AA198),
    brightness: Brightness.dark,
  ),
};

ThemeData buildTheme(PintyThemeId id) {
  final p = pintyPalettes[id]!;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: p.brightness,
  ).copyWith(
    primary: p.accent,
    onPrimary: Colors.white,
    surface: p.card,
    onSurface: p.text,
    outline: p.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.line),
      ),
    ),
    dividerColor: p.line,
    textTheme: ThemeData(brightness: p.brightness)
        .textTheme
        .apply(bodyColor: p.text, displayColor: p.text),
  );
}
