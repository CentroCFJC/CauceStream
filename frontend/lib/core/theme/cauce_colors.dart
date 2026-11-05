/// Paleta de colores de CAUCE.
///
/// Fuente de verdad: docs/html_reference/design.md y los tokens
/// Tailwind de las referencias Stitch (dos variantes: calida "cream"
/// para pantallas apiladas y "peach" para las pestanas principales).
library;

import 'package:flutter/material.dart';

abstract final class CauceColors {
  // Marca (design.md)
  static const Color orange = Color(0xFFEA580C);
  static const Color orangeDark = Color(0xFFC2410C);
  static const Color brown = Color(0xFF6D432D);
  static const Color maroon = Color(0xFF600A0A);
  static const Color yellow = Color(0xFFF2C744);
  static const Color teal = Color(0xFF2B8190);
  static const Color cream = Color(0xFFFAF6DB);
  static const Color creamLight = Color(0xFFFFFDF4);
  static const Color darkTeal = Color(0xFF17404A);
  static const Color error = Color(0xFFBA1A1A);

  // Variante "cream" (login, perfil, nuevos registros, detalle de medio,
  // actividades): superficie #fefadf.
  static const Color creamSurface = Color(0xFFFEFADF);
  static const Color creamSurfaceContainer = Color(0xFFF3EFD4);
  static const Color creamSurfaceContainerLow = Color(0xFFF8F4D9);
  static const Color creamSurfaceContainerHigh = Color(0xFFEDE9CE);
  static const Color creamSurfaceContainerHighest = Color(0xFFE7E3C9);
  static const Color creamSecondary = Color(0xFF006876); // teal oscuro
  static const Color creamSecondaryFixed = Color(0xFFA1EFFF);
  static const Color creamOnSecondaryFixed = Color(0xFF001F25);
  static const Color creamPrimary = Color(0xFFA33900);
  static const Color creamPrimaryFixed = Color(0xFFFFDBCE);
  static const Color creamOnSurface = Color(0xFF1D1C0C);
  static const Color creamOnSurfaceVariant = Color(0xFF5A4138);
  static const Color creamTertiary = Color(0xFF7E513A);

  // Variante "peach" (inicio, dispositivos, biblioteca, detalle de
  // dispositivo): superficie #fff8f6 con contenedores rosados.
  static const Color peachSurface = Color(0xFFFFF8F6);
  static const Color peachSurfaceContainer = Color(0xFFFFE9E2);
  static const Color peachSurfaceContainerLow = Color(0xFFFFF1EC);
  static const Color peachSurfaceContainerHigh = Color(0xFFFEE2D9);
  static const Color peachSurfaceContainerHighest = Color(0xFFF8DDD4);
  static const Color peachSurfaceDim = Color(0xFFEFD4CB);
  static const Color peachSecondary = Color(0xFF81543C);
  static const Color peachSecondaryContainer = Color(0xFFFEC2A5);
  static const Color peachOnSecondaryContainer = Color(0xFF794D37);
  static const Color peachSecondaryFixedDim = Color(0xFFF5BA9D);
  static const Color peachPrimary = Color(0xFFA33900);
  static const Color peachPrimaryContainer = Color(0xFFCC4900);
  static const Color peachOnSurface = Color(0xFF261813);
  static const Color peachOnSurfaceVariant = Color(0xFF5A4138);
  static const Color peachErrorContainer = Color(0xFFFFDAD6);

  // Estados
  static const Color online = teal;
  static const Color alert = Color(0xFFF2C744);
  static const Color offline = maroon;
  static const Color success = Color(0xFF10B981);
}
