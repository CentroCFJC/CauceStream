/// Encabezados de aplicacion compartidos.
///
/// Dos variantes, tal como aparecen en las referencias de Stitch:
/// - [TabHeader]: logo + titulo de pestana + badge LAN + avatar.
/// - [StackHeader]: boton volver/cerrar + logo iso + titulo, para
///   pantallas apiladas (perfil, registros, detalles).
library;

import 'package:flutter/material.dart';

import '../core/theme/cauce_colors.dart';
import '../core/theme/cauce_theme.dart';
import 'identity_widgets.dart';

class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.title,
    this.subtitle = 'CAUCE_STREAM',
    this.onAvatarTap,
    this.backgroundColor = CauceColors.cream,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onAvatarTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    // Deja la franja de la barra de estado del telefono libre de
    // contenido (solo espacio vacio, con la banda del encabezado
    // extendida por debajo de ella).
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF261813).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Image.asset(
                  'assets/logo_iso.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: CauceTheme.displayFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: CauceColors.peachOnSurface,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 12,
                        color: CauceColors.peachOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const LanBadge(compact: true),
                const SizedBox(width: 12),
                _AvatarButton(onTap: onAvatarTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StackHeader extends StatelessWidget {
  const StackHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.closeInsteadOfBack = false,
    this.centered = false,
    this.showLanBadge = true,
    this.showLogo = true,
    this.titleFontSize = 22,
    this.onAvatarTap,
    this.backgroundColor = CauceColors.creamSurface,
  });

  final String title;
  final String? subtitle;

  /// Muestra una X (cerrar) en lugar de la flecha de volver.
  final bool closeInsteadOfBack;

  /// Centra el titulo (referencias "Nuevo..." con badge LAN centrado).
  final bool centered;
  final bool showLanBadge;

  /// Oculta el iso de Cauce (pantallas "Nuevo..." mas compactas).
  final bool showLogo;

  /// Tamano del titulo (las pantallas de registro lo reducen).
  final double titleFontSize;
  final VoidCallback? onAvatarTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final leading = IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: Icon(
        closeInsteadOfBack ? Icons.close : Icons.arrow_back,
        size: 24,
        color: CauceColors.creamOnSurface,
      ),
    );

    final titleBlock = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: CauceTheme.displayFont,
            fontSize: titleFontSize,
            fontWeight: FontWeight.w600,
            color: CauceColors.creamOnSurface,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: const TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 12,
              color: CauceColors.creamOnSurfaceVariant,
            ),
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: CauceColors.brown.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: 64,
          child: Padding(
            // Inset derecho identico al TabHeader (24): el badge y el
            // avatar quedan exactamente en la misma posicion al
            // navegar entre pestanas, detalles y registros.
            padding: const EdgeInsets.fromLTRB(12, 0, 24, 0),
            child: Row(
              children: [
                leading,
                // Aire extra entre volver/cerrar y el titulo: el icono
                // del boton queda pegado al borde y el titulo respira.
                const SizedBox(width: 8),
                if (!centered && showLogo) ...[
                  Image.asset(
                    'assets/logo_iso.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(child: titleBlock),
                if (centered && showLogo) ...[
                  Image.asset(
                    'assets/logo_iso.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                ],
                // Badge siempre anclado a la derecha, a la izquierda
                // del avatar: su posicion no depende del titulo.
                if (showLanBadge) ...[
                  const LanBadge(compact: true),
                  const SizedBox(width: 12),
                ],
                _AvatarButton(onTap: onAvatarTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: CauceColors.creamPrimary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person, size: 18, color: Colors.white),
      ),
    );
  }
}
