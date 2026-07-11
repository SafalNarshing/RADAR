import 'dart:math' as math;

import 'package:flutter/material.dart';

const _liveLocationBlue = Color(0xFF2979FF);

/// Google-Maps-style "my location" puck: a fixed blue dot with a soft halo,
/// plus a heading cone that rotates to point in the device's direction of
/// travel.
class LiveLocationMarker extends StatelessWidget {
  const LiveLocationMarker({super.key, required this.headingDegrees});

  final double headingDegrees;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _liveLocationBlue.withValues(alpha: 0.15),
          ),
        ),
        Transform.rotate(
          angle: headingDegrees * math.pi / 180,
          child: CustomPaint(
            size: const Size(46, 46),
            painter: _HeadingRayPainter(),
          ),
        ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _liveLocationBlue,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeadingRayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - radius * 0.32, center.dy - radius * 0.25)
      ..lineTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.32, center.dy - radius * 0.25)
      ..close();

    canvas.drawPath(path, Paint()..color = _liveLocationBlue.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(covariant _HeadingRayPainter oldDelegate) => false;
}
