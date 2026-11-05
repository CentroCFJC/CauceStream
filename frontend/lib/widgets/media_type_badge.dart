/// Pastilla de tipo de medio (Imagen / Video / Enlace): la misma
/// visualizacion en la biblioteca de medios y en el detalle de
/// dispositivo (tarjeta de contenido asignado).

import 'package:flutter/material.dart';

import '../core/theme/cauce_colors.dart';
import '../core/theme/cauce_theme.dart';
import '../models/media.dart';

class MediaTypeBadge extends StatelessWidget {
  const MediaTypeBadge({
    super.key,
    required this.media,
    this.iconOnly = false,
  });

  final Media media;

  /// Solo icono (tarjetas de la biblioteca): el tipo se lee por la
  /// iconografia; la semántica conserva la etiqueta para lectores de
  /// pantalla.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(media.typeIcon, size: 13, color: CauceColors.yellow);
    if (iconOnly) {
      return Semantics(
        label: media.typeLabel,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: CauceColors.darkTeal.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: icon,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: CauceColors.darkTeal.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          Text(
            media.typeLabel.toUpperCase(),
            style: const TextStyle(
              fontFamily: CauceTheme.displayFont,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: CauceColors.cream,
            ),
          ),
        ],
      ),
    );
  }
}
