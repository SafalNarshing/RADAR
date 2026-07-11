import 'package:flutter/material.dart';

import '../models/detection.dart';

/// Draws detection boxes + labels over an image or camera preview.
///
/// [sourceSize] must be the pixel dimensions of whatever coordinate space
/// [detections]' boxes are defined in (e.g. the original photo, or the raw
/// camera frame) — this widget scales boxes from that space onto whatever
/// size it's actually laid out at, so it should be sized to exactly match
/// the image/preview it's stacked over.
class BoundingBoxOverlay extends StatelessWidget {
  const BoundingBoxOverlay({
    super.key,
    required this.detections,
    required this.sourceSize,
  });

  final List<Detection> detections;
  final Size sourceSize;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BoundingBoxPainter(detections: detections, sourceSize: sourceSize),
      ),
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  _BoundingBoxPainter({required this.detections, required this.sourceSize});

  final List<Detection> detections;
  final Size sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (sourceSize.width == 0 || sourceSize.height == 0) return;
    final scaleX = size.width / sourceSize.width;
    final scaleY = size.height / sourceSize.height;

    for (final detection in detections) {
      final rect = Rect.fromLTRB(
        detection.box.left * scaleX,
        detection.box.top * scaleY,
        detection.box.right * scaleX,
        detection.box.bottom * scaleY,
      );
      final color = detection.damageClass.color;

      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      final label =
          '${detection.damageClass.label} ${(detection.confidence * 100).round()}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelTop = (rect.top - textPainter.height - 4)
          .clamp(0, size.height - textPainter.height - 4)
          .toDouble();
      final labelBg = Rect.fromLTWH(
        rect.left,
        labelTop,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      canvas.drawRect(labelBg, Paint()..color = color);
      textPainter.paint(canvas, Offset(labelBg.left + 4, labelBg.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.sourceSize != sourceSize;
  }
}
