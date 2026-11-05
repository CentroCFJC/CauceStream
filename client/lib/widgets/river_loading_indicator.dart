import 'dart:math' as math;
import 'package:flutter/material.dart';

class RiverLoadingIndicator extends StatefulWidget {
  final double width;
  final double height;

  const RiverLoadingIndicator({
    super.key,
    this.width = 300,
    this.height = 24,
  });

  @override
  State<RiverLoadingIndicator> createState() =>
      _RiverLoadingIndicatorState();
}

class _RiverLoadingIndicatorState extends State<RiverLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _RiverPainter(
              animation: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

class _RiverPainter extends CustomPainter {
  final double animation;

  _RiverPainter({
    required this.animation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height);

    final clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      radius,
    );

    canvas.clipRRect(clip);

    // Fondo oscuro para que la onda destaque
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0D1D34),
          Color(0xFF0A1628),
        ],
      ).createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      background,
    );

    _drawWave(
      canvas,
      size,
      amplitude: size.height * .28,
      frequency: 1.6,
      speed: 1,
      color: Colors.white.withValues(alpha: .35),
      yOffset: size.height * .35,
    );

    _drawWave(
      canvas,
      size,
      amplitude: size.height * .32,
      frequency: 1.2,
      speed: .65,
      color: const Color(0xFF42A5F5).withValues(alpha: .7),
      yOffset: size.height * .45,
    );

    _drawHighlights(canvas, size);
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double amplitude,
    required double frequency,
    required double speed,
    required Color color,
    required double yOffset,
  }) {
    final path = Path();

    path.moveTo(0, size.height);

    for (double x = 0; x <= size.width; x++) {
      final angle = (x / size.width) * frequency * 2 * math.pi;

      final y = yOffset +
          math.sin(
                angle - animation * speed * 2 * math.pi,
              ) *
              amplitude;

      path.lineTo(x, y);
    }

    path
      ..lineTo(size.width, size.height)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);
  }

  void _drawHighlights(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .25)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        1.2,
      );

    for (int i = 0; i < 5; i++) {
      final x = ((animation + i * .22) % 1) * size.width;

      canvas.drawLine(
        Offset(x - 10, size.height * .22),
        Offset(x + 10, size.height * .22),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RiverPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}