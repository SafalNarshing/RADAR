import 'dart:math';
import 'package:image_picker/image_picker.dart';
import '../models/pothole.dart';

/// Result of running a captured/uploaded photo through a
/// [DamageDetectionService]. [type] is null when the service could not
/// classify the image at all.
class DetectionResult {
  final DamageType? type;
  final double confidence;

  const DetectionResult({this.type, required this.confidence});

  bool get isConfident =>
      type != null && confidence >= DamageDetectionService.confidenceThreshold;
}

/// Classifies a road-damage photo as pothole / crack / missing manhole.
///
/// There is no on-device or remote model wired into this app yet — see
/// [SimulatedDamageDetectionService]. Swap the instance used by
/// `ReportScreen` for a real implementation (e.g. one backed by a
/// `tflite_flutter` model or an HTTP classification endpoint) without
/// touching any UI code, since callers only depend on this interface.
abstract class DamageDetectionService {
  static const double confidenceThreshold = 0.75;

  Future<DetectionResult> detect(XFile image);
}

/// Placeholder detector: no real model exists in this codebase yet, so
/// this returns a plausible-looking random result after a short delay,
/// purely so the confirm/retake and manual-fallback UI flows have
/// something to react to. Replace with a real classifier later.
class SimulatedDamageDetectionService implements DamageDetectionService {
  final Random _random;

  SimulatedDamageDetectionService({Random? random})
      : _random = random ?? Random();

  @override
  Future<DetectionResult> detect(XFile image) async {
    await Future.delayed(const Duration(milliseconds: 900));

    // ~15% of the time, simulate an inconclusive result to exercise the
    // manual-fallback path.
    if (_random.nextDouble() < 0.15) {
      return DetectionResult(confidence: _random.nextDouble() * 0.4);
    }

    final type = DamageType.values[_random.nextInt(DamageType.values.length)];
    final confidence = 0.75 + _random.nextDouble() * 0.24;
    return DetectionResult(type: type, confidence: confidence);
  }
}
