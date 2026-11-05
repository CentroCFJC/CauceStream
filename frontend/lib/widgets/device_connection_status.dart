/// Indicador de conectividad del dispositivo (detalle de dispositivo).
///
/// Ocupa la parte superior izquierda de la pantalla: la pastilla del
/// dispositivo (nombre arriba; icono del tipo y circulo de estado
/// abajo) y el conector del canal de comandos que la enlaza con la
/// pastilla LAN del encabezado, donde vive el estado del servidor (no
/// se duplica aqui).
///
/// El conector tiene dos flechas: la horizontal apunta a la pastilla
/// del dispositivo y la vertical apunta hacia arriba, anclada bajo la
/// pastilla del servidor del encabezado. En el codo va el circulo con
/// el estado del canal (check verde / X roja). El canal es el
/// WebSocket de playback: independiente del heartbeat, verde animado
/// con canal vivo y guiones rojos sin canal.
///
/// Los estados provienen de su fuente real, sin logica nueva:
/// conectividad y estado operativo por heartbeat ([Device.isOnline],
/// [Device.deviceState]); canal por [Device.wsConnected]).
///
/// Altura total fija: los cambios de color, icono o animacion no
/// alteran las dimensiones ni la posicion del componente.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/cauce_colors.dart';
import '../core/theme/cauce_theme.dart';
import '../models/device.dart';

/// Representacion visual de un estado. Centraliza la traduccion
/// estado real -> color + iconografia.
enum LinkVisual {
  /// Verde con check (✓).
  connected,

  /// Ambar con pausa: en linea pero en reposo (standby).
  standby,

  /// Rojo con X (✕).
  disconnected,
}

class DeviceConnectionStatus extends StatelessWidget {
  const DeviceConnectionStatus({
    super.key,
    required this.device,
    this.stale = false,
  });

  /// Dispositivo del inventario (sondeo): heartbeat + estado
  /// operativo + canal WebSocket.
  final Device device;

  /// Datos caducados (sondeo fallido): el componente se atenúa para no
  /// parecer estado actual. Nunca cambia su contenido.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final serverInset = serverBadgeCenterOffset(
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Opacity(
      opacity: stale ? 0.55 : 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // La pastilla nunca supera la mitad izquierda del ancho
          // disponible; el conector ocupa toda la mitad derecha y con
          // ella el anclaje bajo la pastilla del servidor. Con nombres
          // largos la pastilla se acorta (ellipsis).
          final pillMax = constraints.maxWidth / 2;
          return SizedBox(
            // Altura fija: ningun estado la modifica. La fija la
            // pastilla (nombre arriba, icono + estado abajo) con su
            // padding.
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: pillMax),
                  child: _devicePill(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ChannelConnector(
                    connected: device.wsConnected,
                    serverInset: serverInset,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Dispositivo: offline -> rojo; 'idle' (standby) -> ambar; en linea
  // (con o sin estado operativo) -> verde. El sondeo trae el estado
  // ya resuelto por el servidor a partir de los heartbeats.
  LinkVisual get _deviceVisual {
    if (!device.isOnline) return LinkVisual.disconnected;
    if (device.deviceState == 'idle') return LinkVisual.standby;
    return LinkVisual.connected;
  }

  /// Distancia desde el borde derecho del contenido hasta el centro de
  /// la pastilla LAN del encabezado, para anclar la flecha vertical
  /// debajo de ella (y no debajo del avatar). Reproduce la geometria
  /// del [StackHeader]: avatar (32) + separacion (12) hasta la pastilla
  /// y, dentro de la pastilla (LanBadge compacta): padding (20) + punto
  /// (7) + separacion (6) + etiqueta del ancho de su palabra mas
  /// ancha, medida con el escalado de texto vigente.
  static double serverBadgeCenterOffset({required TextScaler textScaler}) {
    final labelStyle = TextStyle(
      fontFamily: CauceTheme.bodyFont,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      height: 1.2,
    );
    var labelWidth = 0.0;
    for (final word in const ['Servidor', 'Activo', 'Inactivo', 'Comprobando']) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
    }
    const badgeEdge = 32.0 + 12.0;
    const badgeChrome = 20.0 + 7.0 + 6.0;
    return badgeEdge + (badgeChrome + labelWidth) / 2;
  }

  Widget _devicePill() {
    return Semantics(
      label: 'Dispositivo ${device.statusLabel}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: CauceColors.cream,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Arriba: el nombre del dispositivo.
              Flexible(
                child: Text(
                  device.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: CauceTheme.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CauceColors.darkTeal,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              // Abajo: el icono del tipo y el circulo de estado.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    device.typeIcon,
                    size: 28,
                    color: CauceColors.peachSecondary,
                  ),
                  const SizedBox(width: 6),
                  _StatusDot(visual: _deviceVisual),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circulo pequeno de estado con dimension fija (18x18): verde con
/// check, ambar con pausa o rojo con X.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.visual});

  final LinkVisual visual;

  @override
  Widget build(BuildContext context) {
    final (color, icon, iconColor) = switch (visual) {
      LinkVisual.connected => (CauceColors.success, Icons.check, Colors.white),
      // Ambar: icono oscuro para que la pausa sea legible.
      LinkVisual.standby => (
        CauceColors.alert,
        Icons.pause,
        CauceColors.darkTeal,
      ),
      LinkVisual.disconnected => (
        CauceColors.error,
        Icons.close,
        Colors.white,
      ),
    };
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 12, color: iconColor),
    );
  }
}

/// Conector del canal de comandos entre la pastilla del dispositivo y
/// la pastilla del servidor del encabezado: tramo horizontal que
/// arranca en la pastilla, codo bajo la pastilla del servidor y tramo
/// vertical que sube hacia ella. El circulo del canal va sobre el codo.
/// Con canal vivo: trazo verde con puntos que viajan por el recorrido;
/// sin canal: guiones rojos, sin animacion. El estado se entiende sin
/// la animacion.
class _ChannelConnector extends StatefulWidget {
  const _ChannelConnector({required this.connected, required this.serverInset});

  final bool connected;

  /// Distancia desde el borde derecho hasta el centro de la pastilla
  /// del servidor del encabezado: ancla el tramo vertical debajo de
  /// esa pastilla.
  final double serverInset;

  @override
  State<_ChannelConnector> createState() => _ChannelConnectorState();
}

class _ChannelConnectorState extends State<_ChannelConnector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.connected) _phase.repeat();
  }

  @override
  void didUpdateWidget(covariant _ChannelConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Solo anima con el canal vivo: nada de animacion permanente
    // cuando el estado ya se conoce.
    if (widget.connected == oldWidget.connected) return;
    if (widget.connected) {
      _phase.repeat();
    } else {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.connected
          ? 'Canal de comandos activo'
          : 'Canal de comandos inactivo',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _phase,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final midY = constraints.maxHeight / 2;
              // El codo cae bajo la pastilla del servidor; con poco
              // espacio (pantalla estrecha) se queda al borde derecho.
              final cornerX = math.min(
                width - 4,
                math.max(_ChannelPainter.margin + 12, width - widget.serverInset),
              );
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    foregroundPainter: _ChannelPainter(
                      connected: widget.connected,
                      phase: _phase.value,
                      cornerX: cornerX,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  // Circulo del canal sobre el codo del recorrido.
                  Positioned(
                    left: cornerX - 9,
                    top: midY - 9,
                    child: _StatusDot(
                      visual: widget.connected
                          ? LinkVisual.connected
                          : LinkVisual.disconnected,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Dibuja el recorrido del canal: flecha horizontal hacia la pastilla
/// del dispositivo, tramo horizontal, codo bajo la pastilla del
/// servidor, tramo vertical y flecha hacia arriba. Verde solido con
/// canal vivo; guiones rojos sin canal.
class _ChannelPainter extends CustomPainter {
  const _ChannelPainter({
    required this.connected,
    required this.phase,
    required this.cornerX,
  });

  /// Margen del arranque horizontal junto a la pastilla.
  static const double margin = 8;

  static const double _wing = 4.5;
  static const double _top = 8;

  final bool connected;

  /// Avance de los puntos viajeros (0..1), animado solo en verde.
  final double phase;

  /// Posicion horizontal del codo: centro de la pastilla del servidor.
  final double cornerX;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final startX = margin;
    final color = connected
        ? CauceColors.success
        : CauceColors.error.withValues(alpha: 0.75);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = connected ? StrokeCap.round : StrokeCap.butt;

    if (connected) {
      canvas.drawLine(Offset(startX, midY), Offset(cornerX, midY), stroke);
      canvas.drawLine(Offset(cornerX, midY), Offset(cornerX, _top), stroke);
    } else {
      // Guiones en el tramo horizontal y en el vertical.
      var x = startX;
      while (x < cornerX) {
        final end = math.min(x + 4, cornerX);
        canvas.drawLine(Offset(x, midY), Offset(end, midY), stroke);
        x += 8;
      }
      var y = midY;
      while (y > _top) {
        final end = math.max(y - 4, _top);
        canvas.drawLine(Offset(cornerX, y), Offset(cornerX, end), stroke);
        y -= 8;
      }
    }

    // Flechas: la horizontal apunta a la pastilla del dispositivo y
    // la vertical hacia arriba, a la pastilla del servidor.
    final arrow = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(2, midY), Offset(2 + _wing, midY - _wing), arrow);
    canvas.drawLine(Offset(2, midY), Offset(2 + _wing, midY + _wing), arrow);
    canvas.drawLine(
      Offset(cornerX, 2),
      Offset(cornerX - _wing, 2 + _wing),
      arrow,
    );
    canvas.drawLine(
      Offset(cornerX, 2),
      Offset(cornerX + _wing, 2 + _wing),
      arrow,
    );

    // Puntos viajeros discretos: recorren pastilla -> codo ->
    // servidor solo cuando el canal esta conectado.
    if (connected) {
      final dot = Paint()..color = color;
      final horizontalLen = cornerX - startX;
      final verticalLen = midY - _top;
      final total = horizontalLen + verticalLen;
      for (final base in const [0.0, 1.0 / 3, 2.0 / 3]) {
        final t = (base + phase) % 1.0;
        final d = t * total;
        if (d < horizontalLen) {
          canvas.drawCircle(Offset(startX + d, midY), 2, dot);
        } else {
          canvas.drawCircle(
            Offset(cornerX, midY - (d - horizontalLen)),
            2,
            dot,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChannelPainter oldDelegate) =>
      connected != oldDelegate.connected ||
      phase != oldDelegate.phase ||
      cornerX != oldDelegate.cornerX;
}
