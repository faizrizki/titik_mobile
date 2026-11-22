import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Token warna dari desain titik (titik.css).
class TK {
  static const g = Color(0xFF17664F);
  static const gd = Color(0xFF0F5D45);
  static const g50 = Color(0xFFE9F3ED);
  static const bg = Color(0xFFF6F8F6);
  static const ink = Color(0xFF12241E);
  static const mut = Color(0xFF5B6962);
  static const line = Color(0xFFE1E7E3);
  static const warnBg = Color(0xFFFFF3DB);
  static const warn = Color(0xFF875709);
  static const badBg = Color(0xFFFCECE8);
  static const bad = Color(0xFFB3261E);
  static const neutralBg = Color(0xFFECEFED);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: TK.g, primary: TK.g),
    scaffoldBackgroundColor: TK.bg,
  );
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
      .apply(bodyColor: TK.ink, displayColor: TK.ink);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: TK.bg,
      foregroundColor: TK.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium
          ?.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: TK.ink),
    ),
    dividerTheme: const DividerThemeData(color: TK.line, space: 1, thickness: 1),
  );
}
