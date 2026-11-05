/// Tema global de CauceStream.
///
/// Tipografias: Space Grotesk para titulos/etiquetas y Plus Jakarta
/// Sans para cuerpo (roles definidos en design.md). Las pantallas
/// usan `headlineLarge/...` para titulos y `bodyMedium` para texto
/// corrido, con overrides puntuales cuando la referencia lo pide.
library;

import 'package:flutter/material.dart';

import 'cauce_colors.dart';

abstract final class CauceTheme {
  static const String displayFont = 'SpaceGrotesk';
  static const String bodyFont = 'PlusJakartaSans';

  static ThemeData get light {
    const textTheme = TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 56,
        height: 1.14,
        fontWeight: FontWeight.w700,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 36,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 28,
        height: 1.28,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 40,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 28,
        height: 1.28,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 22,
        height: 1.36,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 18,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(fontFamily: bodyFont, fontSize: 18, height: 1.5),
      bodyMedium: TextStyle(fontFamily: bodyFont, fontSize: 16, height: 1.5),
      bodySmall: TextStyle(fontFamily: bodyFont, fontSize: 14, height: 1.42),
      labelLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: 16,
        height: 1.37,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        height: 1.42,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 12,
        height: 1.33,
        fontWeight: FontWeight.w500,
      ),
    );

    final colorScheme = ColorScheme.light(
      primary: CauceColors.creamPrimary,
      onPrimary: Colors.white,
      secondary: CauceColors.teal,
      onSecondary: Colors.white,
      surface: CauceColors.creamSurface,
      onSurface: CauceColors.creamOnSurface,
      error: CauceColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CauceColors.creamSurface,
      textTheme: textTheme,
      fontFamily: bodyFont,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: CauceColors.creamOnSurface,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CauceColors.creamLight,
        hintStyle: const TextStyle(color: Color(0xFF8E7166)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: CauceColors.brown.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CauceColors.orange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CauceColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CauceColors.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CauceColors.orange,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontFamily: bodyFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CauceColors.darkTeal,
        contentTextStyle: const TextStyle(
          fontFamily: bodyFont,
          color: CauceColors.cream,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
