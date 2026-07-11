import 'dart:ui';

import 'pothole.dart';

/// The 3 classes the road-damage ONNX model (assets/models/best2.onnx) was
/// trained on — matches the app's [DamageType] 1:1 (see `toDamageType`),
/// unlike the earlier 6-class model which needed collapsing/fallback logic.
enum RoadDamageClass {
  pothole,
  crack,
  missingManhole;

  /// Must match the model's class index order exactly (see the `names`
  /// metadata embedded in best2.onnx: {0: pothole, 1: crack, 2: manhole}).
  static RoadDamageClass fromIndex(int index) => RoadDamageClass.values[index];

  String get label {
    switch (this) {
      case RoadDamageClass.pothole:
        return 'Pothole';
      case RoadDamageClass.crack:
        return 'Crack';
      case RoadDamageClass.missingManhole:
        return 'Missing manhole';
    }
  }

  Color get color {
    switch (this) {
      case RoadDamageClass.pothole:
        return const Color(0xFFE53935);
      case RoadDamageClass.crack:
        return const Color(0xFFF57C00);
      case RoadDamageClass.missingManhole:
        return const Color(0xFF1E88E5);
    }
  }

  DamageType get toDamageType {
    switch (this) {
      case RoadDamageClass.pothole:
        return DamageType.pothole;
      case RoadDamageClass.crack:
        return DamageType.crack;
      case RoadDamageClass.missingManhole:
        return DamageType.missingManhole;
    }
  }
}

/// One detected object, with [box] in pixel coordinates of whatever source
/// image/frame it was detected in (callers must track that coordinate
/// space themselves — see [OnnxDetectionService]).
class Detection {
  const Detection({
    required this.box,
    required this.damageClass,
    required this.confidence,
  });

  final Rect box;
  final RoadDamageClass damageClass;
  final double confidence;
}
