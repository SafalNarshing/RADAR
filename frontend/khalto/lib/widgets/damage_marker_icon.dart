import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/pothole.dart';

/// Circular badge marker used on the map for a single damage report —
/// a warning-triangle glyph for potholes, a jagged crack glyph for cracks.
/// Colors follow [Pothole.damageColor] so the map and legend always match.
class DamageMarkerIcon extends StatelessWidget {
  final DamageType type;
  final double size;

  const DamageMarkerIcon({super.key, required this.type, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final color = Pothole.damageColor(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size * 0.06),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: _glyphFor(type, size)),
    );
  }

  Widget _glyphFor(DamageType type, double size) {
    switch (type) {
      case DamageType.crack:
        return CustomPaint(
          size: Size(size * 0.5, size * 0.5),
          painter: const _CrackPainter(),
        );
      case DamageType.missingManhole:
        return CustomPaint(
          size: Size(size * 0.52, size * 0.52),
          painter: const _ManholePainter(),
        );
      case DamageType.pothole:
        return Icon(
          Icons.warning_amber_rounded,
          color: Colors.white,
          size: size * 0.56,
        );
    }
  }
}

class _CrackPainter extends CustomPainter {
  const _CrackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.05, size.height * 0.95)
      ..lineTo(size.width * 0.45, size.height * 0.45)
      ..lineTo(size.width * 0.60, size.height * 0.65)
      ..lineTo(size.width * 0.78, size.height * 0.12)
      ..lineTo(size.width * 0.95, size.height * 0.5);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Overhead manhole-cover glyph: an outer rim, an inner ring, and spoke
/// lines — the universally recognized "drain/utility cover" symbol.
class _ManholePainter extends CustomPainter {
  const _ManholePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12;

    canvas.drawCircle(center, outerRadius - ringPaint.strokeWidth / 2, ringPaint);
    canvas.drawCircle(center, outerRadius * 0.5, ringPaint);

    final spokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round;

    for (final angleDeg in [0, 60, 120, 180, 240, 300]) {
      final angle = angleDeg * math.pi / 180;
      final inner = Offset(
        center.dx + outerRadius * 0.5 * math.cos(angle),
        center.dy + outerRadius * 0.5 * math.sin(angle),
      );
      final outer = Offset(
        center.dx + outerRadius * 0.88 * math.cos(angle),
        center.dy + outerRadius * 0.88 * math.sin(angle),
      );
      canvas.drawLine(inner, outer, spokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
