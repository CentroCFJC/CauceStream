/// Widgets de identidad compartidos: badge LAN, chips de estado.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/connectivity_controller.dart';
import '../core/config/api_config.dart';
import '../core/theme/cauce_colors.dart';
import '../core/theme/cauce_theme.dart';

/// Badge LAN de los encabezados: refleja si la app puede hablar con
/// el servidor Cauce (sondeo del endpoint de salud). Sin provider de
/// conectividad en el arbol (tests/preview) queda en estado neutro.
/// Compacto y sin IPs ni errores tecnicos en pantalla.
class LanBadge extends StatelessWidget {
  const LanBadge({
    super.key,
    this.compact = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final bool compact;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final status =
        context.watch<ConnectivityController?>()?.status ?? LanStatus.checking;
    final (dotColor, label, semantics) = switch (status) {
      LanStatus.active => (
        CauceColors.success,
        'Servidor\nActivo',
        'Servidor Cauce activo',
      ),
      LanStatus.inactive => (
        CauceColors.error,
        'Servidor\nInactivo',
        'Servidor Cauce inactivo',
      ),
      LanStatus.checking => (
        CauceColors.peachSecondary,
        'Comprobando',
        'Comprobando el servidor Cauce',
      ),
    };
    final style = TextStyle(
      fontFamily: CauceTheme.bodyFont,
      fontSize: compact ? 10 : 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      height: 1.2,
      color: foregroundColor ?? CauceColors.darkTeal,
    );
    // Ancho fijo: el badge nunca cambia de tamano al alternar entre
    // Comprobando y Servidor Activo/Inactivo, asi ni el badge ni el
    // avatar del encabezado se mueven de posicion. Se mide la palabra
    // mas ancha (Comprobando) con el escalado de texto vigente.
    final textScaler = MediaQuery.textScalerOf(context);
    var labelWidth = 0.0;
    for (final word in const [
      'Servidor',
      'Activo',
      'Inactivo',
      'Comprobando',
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
    }
    return Semantics(
      label: semantics,
      // Tooltip con la URL activa del servidor: si el badge dice
      // "Inactivo", aqui se confirma a que direccion se sondea.
      child: Tooltip(
        message: 'Servidor: ${ApiConfig.activeServerUrl}',
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: CauceColors.brown.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulsingDot(color: dotColor, size: 7),
              const SizedBox(width: 6),
              SizedBox(
                width: labelWidth,
                child: Text(label, textAlign: TextAlign.center, style: style),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Estados operativos de dispositivos/mostrados en tarjetas.
enum CauceStatus { online, alert, offline, active }

/// Chip de estado con punto de color, usado en las pantallas visuales.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, required this.label});

  final CauceStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      CauceStatus.online => (CauceColors.teal, Colors.white),
      CauceStatus.alert => (
        const Color(0xFF8A5A00),
        CauceColors.peachSurfaceContainerHighest,
      ),
      CauceStatus.offline => (
        CauceColors.maroon,
        CauceColors.peachErrorContainer,
      ),
      CauceStatus.active => (CauceColors.darkTeal, Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: fg, size: 7),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
