import 'package:flutter/material.dart';

/// A négy beépített téma (az előképen látottak szerint).
enum PintyThemeId { light, dark, ocean, rose }

extension PintyThemeLabel on PintyThemeId {
  String get label => switch (this) {
        PintyThemeId.light => 'Világos',
        PintyThemeId.dark => 'Sötét',
        PintyThemeId.ocean => 'Óceán',
        PintyThemeId.rose => 'Rózsa',
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
