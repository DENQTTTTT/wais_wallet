// Wais Wallet - design system: green palettes, light/dark themes, theme controller

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccentOption {
  const AccentOption(this.name, this.seed, this.glow);
  final String name;
  final Color seed; // main brand green
  final Color glow; // bright highlight used in gradients
}

/// The "Wais" greens. Default is index 0.
const accents = <AccentOption>[
  AccentOption('Wais Green', Color(0xFF00C27A), Color(0xFFB8F34A)),
  AccentOption('Pandan', Color(0xFF58B947), Color(0xFFE6F25A)),
  AccentOption('Jade', Color(0xFF12B5A0), Color(0xFF7CF5D2)),
  AccentOption('Forest', Color(0xFF1F7A4D), Color(0xFF9BE15D)),
];

class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  int _accent = 0;

  ThemeMode get mode => _mode;
  int get accentIndex => _accent;
  AccentOption get accent => accents[_accent];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = p.getString('theme_mode');
      _mode = ThemeMode.values.firstWhere(
        (e) => e.name == m,
        orElse: () => ThemeMode.system,
      );
      final a = p.getInt('accent') ?? 0;
      _accent = (a >= 0 && a < accents.length) ? a : 0;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    await _save();
  }

  Future<void> setAccent(int i) async {
    _accent = i;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme_mode', _mode.name);
      await p.setInt('accent', _accent);
    } catch (_) {}
  }
}

final themeController = ThemeController();

/// Applies the Plus Jakarta Sans font to every text style, one by one.
/// (Done per style because google_fonts' own TextTheme helper uses a
/// different TextTheme type than Flutter's in newer versions.)
TextTheme _withJakarta(TextTheme t) {
  TextStyle? f(TextStyle? s) =>
      s == null ? null : GoogleFonts.plusJakartaSans(textStyle: s);
  return t.copyWith(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

OutlineInputBorder _border(Color c, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: width),
    );

ThemeData buildTheme(AccentOption accent, Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? accent.seed : Color.lerp(accent.seed, Colors.black, 0.25)!,
    onPrimary: dark ? const Color(0xFF03150C) : Colors.white,
    secondary: dark ? accent.glow : Color.lerp(accent.glow, Colors.black, 0.12)!,
    onSecondary: const Color(0xFF0B1500),
    error: dark ? const Color(0xFFFF6B6B) : const Color(0xFFD83A3A),
    onError: dark ? const Color(0xFF2B0000) : Colors.white,
    surface: dark ? const Color(0xFF0D2119) : Colors.white,
    onSurface: dark ? const Color(0xFFE6F4EC) : const Color(0xFF0B2218),
  ).copyWith(
    onSurfaceVariant: dark ? const Color(0xFF9DB8AB) : const Color(0xFF4F6B5C),
    outline: dark ? const Color(0xFF3A5E50) : const Color(0xFF9CC7B0),
    outlineVariant: dark ? const Color(0xFF1F3D31) : const Color(0xFFCDE7D8),
    surfaceContainerHighest:
        dark ? const Color(0xFF133126) : const Color(0xFFE3F5EA),
    primaryContainer: dark
        ? Color.lerp(accent.seed, const Color(0xFF06120D), 0.72)!
        : Color.lerp(accent.seed, Colors.white, 0.8)!,
    onPrimaryContainer:
        dark ? const Color(0xFFBFF5DA) : const Color(0xFF053D27),
  );

  final baseText = ThemeData(brightness: brightness).textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  final textTheme = _withJakarta(baseText);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF06120D) : const Color(0xFFF2FBF6),
    textTheme: textTheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: _border(scheme.outlineVariant),
      enabledBorder: _border(scheme.outlineVariant),
      focusedBorder: _border(scheme.primary, width: 1.8),
      errorBorder: _border(scheme.error),
      focusedErrorBorder: _border(scheme.error, width: 1.8),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: scheme.outline),
        textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.primaryContainer,
      backgroundColor: scheme.surface,
      labelStyle: textTheme.labelLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}