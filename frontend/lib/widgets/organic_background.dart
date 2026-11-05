/// Fondo decorativo con las ondas organicas de CAUCE.
///
/// Usa los assets existentes en assets/decorations/ ("tercios bajos")
/// como marca de agua, tal como aparecen en las referencias de Stitch.
library;

import 'package:flutter/material.dart';

import '../core/theme/cauce_colors.dart';

class OrganicBackground extends StatelessWidget {
  const OrganicBackground({
    super.key,
    this.topRight = true,
    this.bottomLeft = true,
    this.baseColor,
  });

  /// Onda superior derecha.
  final bool topRight;

  /// Onda inferior izquierda.
  final bool bottomLeft;

  final Color? baseColor;

  @override
  Widget build(BuildContext context) {
    final color = baseColor ?? CauceColors.cream;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Container(color: color),
            if (topRight)
              Positioned(
                top: -48,
                right: -64,
                child: Opacity(
                  opacity: 0.18,
                  child: Transform.rotate(
                    angle: 0.2,
                    child: Image.asset(
                      'assets/decorations/tercios bajos -01.png',
                      width: 208,
                      height: 208,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            if (bottomLeft)
              Positioned(
                bottom: 40,
                left: -64,
                child: Opacity(
                  opacity: 0.14,
                  child: Transform.rotate(
                    angle: -0.8,
                    child: Image.asset(
                      'assets/decorations/tercios bajos CAUCE-07.png',
                      width: 240,
                      height: 240,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
