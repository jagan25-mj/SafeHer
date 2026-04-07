import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SafeHerColors {
  static const background = Color(0xFFFFF8FB);
  static const foreground = Color(0xFF2D2342);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFFFF0F6);
  static const stroke = Color(0xFFF4D6E6);
  static const brand = Color(0xFFD66FB1);
  static const brandStrong = Color(0xFFBA4F96);
  static const accent = Color(0xFF6F5BB6);
  static const accentSoft = Color(0xFFE9DDFF);
  static const success = Color(0xFF31A37D);
  static const warning = Color(0xFFD07F2B);
}

class SafeHerGradients {
  static const pageBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFAFD), Color(0xFFF8EFFF), Color(0xFFFFF3F8)],
  );

  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SafeHerColors.brand, SafeHerColors.accent],
  );
}

ThemeData buildSafeHerTheme() {
  final baseText = GoogleFonts.nunitoTextTheme();

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: SafeHerColors.background,
    colorScheme: const ColorScheme.light(
      primary: SafeHerColors.brand,
      secondary: SafeHerColors.accent,
      surface: SafeHerColors.surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: SafeHerColors.foreground,
      error: SafeHerColors.warning,
      onError: Colors.white,
    ),
    textTheme: baseText.copyWith(
      headlineMedium: GoogleFonts.playfairDisplay(
        color: SafeHerColors.foreground,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        color: SafeHerColors.foreground,
        fontWeight: FontWeight.w800,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        color: SafeHerColors.foreground,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: SafeHerColors.foreground,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: SafeHerColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: SafeHerColors.stroke),
      ),
      shadowColor: const Color(0x1A5D3D82),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SafeHerColors.surface,
      hintStyle: baseText.bodyMedium?.copyWith(color: const Color(0xFF8D78A2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SafeHerColors.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SafeHerColors.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SafeHerColors.brand),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: SafeHerColors.foreground,
      contentTextStyle: baseText.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

BoxDecoration safeHerGlassDecoration() {
  return BoxDecoration(
    color: SafeHerColors.surface.withValues(alpha: 0.88),
    border: Border.all(color: SafeHerColors.stroke),
    borderRadius: BorderRadius.circular(18),
    boxShadow: const [
      BoxShadow(color: Color(0x1F5D3D82), blurRadius: 24, offset: Offset(0, 8)),
    ],
  );
}
