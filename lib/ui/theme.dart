import 'package:flutter/material.dart';

/// Colori del marchio Dom Studio.
class Brand {
  static const blue = Color(0xFF1D3A8A);
  static const orange = Color(0xFFF28C38);
  static const paper = Color(0xFFFFF8F0);
  static const ink = Color(0xFF14213D);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFFB4C5FF) : Brand.blue,
    onPrimary: dark ? Brand.ink : Colors.white,
    secondary: Brand.orange,
    onSecondary: Brand.ink,
    surface: dark ? const Color(0xFF12161F) : Brand.paper,
    onSurface: dark ? const Color(0xFFE8E6E1) : Brand.ink,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Sora',
    scaffoldBackgroundColor: scheme.surface,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Sora',
        fontWeight: FontWeight.w800,
        fontSize: 22,
        color: scheme.onSurface,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1B2130) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1B2130) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: scheme.primary,
      thumbColor: Brand.orange,
    ),
  );
}
