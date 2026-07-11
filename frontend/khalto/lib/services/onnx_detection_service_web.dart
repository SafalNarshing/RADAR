import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../models/detection.dart';

class OnnxDetectionService {
  OnnxDetectionService._();

  static final OnnxDetectionService instance = OnnxDetectionService._();

  bool get isReady => false;

  Future<void> preload() async {}

  Future<List<Detection>> detectImageBytes(Uint8List encodedBytes) async {
    return const <Detection>[];
  }

  Future<List<Detection>> detectCameraImage(
    CameraImage image, {
    int sensorOrientationDegrees = 0,
  }) async {
    return const <Detection>[];
  }
}
