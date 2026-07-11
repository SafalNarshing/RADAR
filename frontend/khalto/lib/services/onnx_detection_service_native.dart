import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../models/detection.dart';

const _modelAssetPath = 'assets/models/best2.onnx';
const _inputSize = 640;
const _numClasses = 3;
const _confidenceThreshold = 0.35;
const _iouThreshold = 0.45;

/// Runs the road-damage YOLOv8 model (assets/models/best2.onnx) on either a
/// captured photo or a live camera frame.
///
/// A single [OrtSession] is shared for the app's lifetime, and every
/// inference call is serialized through [_inflight] — `onnxruntime`'s
/// `runAsync` reuses one broadcast stream per session with no per-call
/// correlation id, so two overlapping calls could read back each other's
/// result. Serializing here means callers (camera capture, dashcam frame
/// stream) don't each have to reason about that.
class OnnxDetectionService {
  OnnxDetectionService._();

  static final OnnxDetectionService instance = OnnxDetectionService._();

  OrtSession? _session;
  Future<void>? _loadFuture;
  Future<void> _inflight = Future.value();

  /// True once the model is loaded and ready to run inference.
  bool get isReady => _session != null;

  /// Starts loading the model immediately instead of waiting for the first
  /// [detectImageBytes]/[detectCameraImage] call, so a screen can show a
  /// "loading model" state up front and the first real detection isn't the
  /// one paying the (multi-second, ~100MB) load cost.
  Future<void> preload() => _ensureLoaded();

  Future<void> _ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    OrtEnv.instance.init();
    final assetData = await rootBundle.load(_modelAssetPath);
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

    // Best-effort hardware acceleration — these throw on platforms/devices
    // that don't support the given execution provider, so CPU (already the
    // implicit default) is the fallback.
    try {
      options.appendNnapiProvider(NnapiFlags.useFp16);
    } catch (_) {}
    try {
      options.appendCoreMLProvider(CoreMLFlags.useNone);
    } catch (_) {}

    _session = OrtSession.fromBuffer(
      assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      ),
      options,
    );
  }

  /// Detects damage in a captured photo (JPEG/PNG bytes). Boxes are returned
  /// in the pixel coordinates of the *original* (non-resized) image.
  Future<List<Detection>> detectImageBytes(Uint8List encodedBytes) {
    return _serialized(() async {
      final decoded = img.decodeImage(encodedBytes);
      if (decoded == null) return const <Detection>[];
      return _runOnImage(decoded);
    });
  }

  /// Detects damage in one live camera frame. [sensorOrientationDegrees]
  /// (from `CameraDescription.sensorOrientation`) is the clockwise rotation
  /// needed to make the raw sensor frame appear upright — Android delivers
  /// `CameraImage` stream frames in the sensor's native (usually landscape)
  /// orientation regardless of how the phone is held, unlike a captured
  /// still photo (which is auto-corrected via EXIF/baked rotation). Skipping
  /// this rotation feeds the model a sideways frame, which — for a model
  /// trained on upright photos — reliably prevents any confident detection,
  /// not just a coordinate misalignment.
  ///
  /// Boxes are returned in the pixel coordinates of the *rotated* (i.e.
  /// upright, display-matching) frame — [Size] of that rotated frame is
  /// `(image.height, image.width)` when the rotation is 90°/270°.
  Future<List<Detection>> detectCameraImage(
    CameraImage image, {
    int sensorOrientationDegrees = 0,
  }) {
    return _serialized(() async {
      var decoded = _cameraImageToImage(image);
      if (decoded == null) return const <Detection>[];
      final normalized = sensorOrientationDegrees % 360;
      if (normalized != 0) {
        decoded = img.copyRotate(decoded, angle: normalized);
      }
      return _runOnImage(decoded);
    });
  }

  Future<List<Detection>> _serialized(Future<List<Detection>> Function() run) {
    final result = _inflight.then((_) => run());
    _inflight = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<Detection>> _runOnImage(img.Image source) async {
    await _ensureLoaded();
    final session = _session;
    if (session == null) return const [];

    final letterboxed = _letterbox(source, _inputSize);
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      _imageToChwFloat(letterboxed.image),
      [1, 3, _inputSize, _inputSize],
    );
    final runOptions = OrtRunOptions();

    List<OrtValue?> outputs;
    try {
      outputs =
          await session.runAsync(runOptions, {'images': inputTensor}) ??
          const [];
    } finally {
      inputTensor.release();
      runOptions.release();
    }

    if (outputs.isEmpty || outputs.first == null) return const [];
    final output = outputs.first!;
    // output0: [1, 10, 8400] — 4 box channels + 6 class-score channels,
    // no separate objectness column (standard YOLOv8 export layout).
    final batch = output.value as List;
    for (final o in outputs) {
      o?.release();
    }

    final channels = batch[0] as List; // 10 x 8400
    return _decode(
      channels,
      letterboxed,
      source.width.toDouble(),
      source.height.toDouble(),
    );
  }

  List<Detection> _decode(
    List channels,
    _Letterbox letterboxed,
    double originalWidth,
    double originalHeight,
  ) {
    final numAnchors = (channels[0] as List).length;
    final candidates = <Detection>[];

    for (var i = 0; i < numAnchors; i++) {
      var bestScore = 0.0;
      var bestClass = -1;
      for (var c = 0; c < _numClasses; c++) {
        final score = (channels[4 + c][i] as num).toDouble();
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestClass == -1 || bestScore < _confidenceThreshold) continue;

      final cx = (channels[0][i] as num).toDouble();
      final cy = (channels[1][i] as num).toDouble();
      final w = (channels[2][i] as num).toDouble();
      final h = (channels[3][i] as num).toDouble();

      // Box is in 640x640 letterboxed space — invert the pad/scale to map
      // it back onto the original image's pixel coordinates.
      final x1 = ((cx - w / 2) - letterboxed.padX) / letterboxed.scale;
      final y1 = ((cy - h / 2) - letterboxed.padY) / letterboxed.scale;
      final x2 = ((cx + w / 2) - letterboxed.padX) / letterboxed.scale;
      final y2 = ((cy + h / 2) - letterboxed.padY) / letterboxed.scale;

      candidates.add(
        Detection(
          box: Rect.fromLTRB(
            x1.clamp(0, originalWidth),
            y1.clamp(0, originalHeight),
            x2.clamp(0, originalWidth),
            y2.clamp(0, originalHeight),
          ),
          damageClass: RoadDamageClass.fromIndex(bestClass),
          confidence: bestScore,
        ),
      );
    }

    return _nonMaxSuppression(candidates);
  }

  List<Detection> _nonMaxSuppression(List<Detection> boxes) {
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <Detection>[];
    for (final candidate in boxes) {
      final overlapsKept = kept.any(
        (k) =>
            k.damageClass == candidate.damageClass &&
            _iou(k.box, candidate.box) > _iouThreshold,
      );
      if (!overlapsKept) kept.add(candidate);
    }
    return kept;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    final interArea = (intersection.width <= 0 || intersection.height <= 0)
        ? 0.0
        : intersection.width * intersection.height;
    final unionArea = a.width * a.height + b.width * b.height - interArea;
    return unionArea <= 0 ? 0 : interArea / unionArea;
  }

  _Letterbox _letterbox(img.Image source, int target) {
    final scale = math.min(target / source.width, target / source.height);
    final newWidth = (source.width * scale).round();
    final newHeight = (source.height * scale).round();
    final resized = img.copyResize(
      source,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );

    final padX = (target - newWidth) ~/ 2;
    final padY = (target - newHeight) ~/ 2;
    final canvas = img.Image(width: target, height: target)
      ..clear(img.ColorRgb8(114, 114, 114));
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    return _Letterbox(
      image: canvas,
      scale: scale,
      padX: padX.toDouble(),
      padY: padY.toDouble(),
    );
  }

  Float32List _imageToChwFloat(img.Image image) {
    final planeSize = image.width * image.height;
    final data = Float32List(3 * planeSize);
    var i = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        data[i] = pixel.r / 255.0;
        data[planeSize + i] = pixel.g / 255.0;
        data[2 * planeSize + i] = pixel.b / 255.0;
        i++;
      }
    }
    return data;
  }

  img.Image? _cameraImageToImage(CameraImage image) {
    if (image.planes.isEmpty) return null;

    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        return _yuv420ToImage(image);
      }

      if (image.format.group == ImageFormatGroup.bgra8888) {
        final plane = image.planes.first;
        return img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: plane.bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
      }
    } catch (e) {
      debugPrint(
        'OnnxDetectionService: failed to convert camera frame '
        '${image.format.group}: $e',
      );
      return null;
    }

    debugPrint(
      'OnnxDetectionService: unsupported camera image format '
      '${image.format.group}',
    );
    return null;
  }

  img.Image _yuv420ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final planeY = image.planes[0];
    final planeU = image.planes[1];
    final planeV = image.planes[2];

    final out = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      final uvRow = y >> 1;
      for (var x = 0; x < width; x++) {
        final yValue = planeY.bytes[y * planeY.bytesPerRow + x];
        final uvCol = x >> 1;
        final uIndex =
            uvRow * planeU.bytesPerRow + uvCol * planeU.bytesPerPixel!;
        final vIndex =
            uvRow * planeV.bytesPerRow + uvCol * planeV.bytesPerPixel!;
        final uValue = planeU.bytes[uIndex];
        final vValue = planeV.bytes[vIndex];

        final yf = yValue.toDouble();
        final uf = uValue.toDouble() - 128.0;
        final vf = vValue.toDouble() - 128.0;

        final r = (yf + 1.402 * vf).round().clamp(0, 255);
        final g = (yf - 0.344136 * uf - 0.714136 * vf).round().clamp(0, 255);
        final b = (yf + 1.772 * uf).round().clamp(0, 255);

        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }
}

class _Letterbox {
  final img.Image image;
  final double scale;
  final double padX;
  final double padY;

  const _Letterbox({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}
