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
        data[i] = pixel.rNormalized.toDouble();
        data[planeSize + i] = pixel.gNormalized.toDouble();
        data[2 * planeSize + i] = pixel.bNormalized.toDouble();
        i++;
      }
    }
    return data;
  }

  img.Image? _cameraImageToImage(CameraImage image) {
    try {
      switch (image.format.group) {
        case ImageFormatGroup.bgra8888:
          final plane = image.planes[0];
          return img.Image.fromBytes(
            width: image.width,
            height: image.height,
            bytes: plane.bytes.buffer,
            bytesOffset: plane.bytes.offsetInBytes,
            order: img.ChannelOrder.bgra,
            rowStride: plane.bytesPerRow,
          );
        case ImageFormatGroup.yuv420:
        case ImageFormatGroup.nv21:
          return _yuv420ToImage(image);
        default:
          debugPrint(
            'OnnxDetectionService: unsupported camera image format '
            '${image.format.group} (${image.planes.length} planes) — '
            'skipping frame.',
          );
          return null;
      }
    } catch (e, st) {
      debugPrint(
        'OnnxDetectionService: failed to convert camera frame '
        '(format=${image.format.group}, planes=${image.planes.length}): $e\n$st',
      );
      return null;
    }
  }

  /// YUV420 → RGB conversion. Handles both layouts Android devices report
  /// under `ImageFormatGroup.yuv420`/`nv21`:
  ///  - 3 separate planes (Y, U, V), each with its own stride/pixel-stride
  ///    (the standard `YUV_420_888` case, and what requesting
  ///    [ImageFormatGroup.yuv420] should reliably produce).
  ///  - a single merged plane (Y followed by interleaved VU) — what
  ///    `camera_android_camerax` hands back when NV21 is requested/used.
  img.Image _yuv420ToImage(CameraImage image) {
    return image.planes.length >= 3
        ? _yuv420PlanarToImage(image)
        : _nv21SinglePlaneToImage(image);
  }

  img.Image _yuv420PlanarToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final out = img.Image(width: width, height: height);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < height; y++) {
      final yRow = y * yRowStride;
      final uvRow = (y >> 1) * uvRowStride;
      for (var x = 0; x < width; x++) {
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;
        final (r, g, b) = _yuvToRgb(
          yPlane.bytes[yRow + x],
          uPlane.bytes[uvIndex],
          vPlane.bytes[uvIndex],
        );
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  /// BT.601 video-range (16-235 luma / 16-240 chroma) → full-range RGB —
  /// the standard formula for Android camera YUV output. Using the simpler
  /// full-range formula (no -16 luma offset) produces washed-out colors
  /// that can measurably hurt a model's confidence.
  (int, int, int) _yuvToRgb(int yByte, int uByte, int vByte) {
    final yy = (yByte & 0xFF) - 16;
    final uu = (uByte & 0xFF) - 128;
    final vv = (vByte & 0xFF) - 128;
    final r = ((298 * yy + 409 * vv + 128) >> 8).clamp(0, 255);
    final g = ((298 * yy - 100 * uu - 208 * vv + 128) >> 8).clamp(0, 255);
    final b = ((298 * yy + 516 * uu + 128) >> 8).clamp(0, 255);
    return (r, g, b);
  }

  img.Image _nv21SinglePlaneToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final out = img.Image(width: width, height: height);

    final bytes = image.planes[0].bytes;
    final rowStride = image.planes[0].bytesPerRow;
    final ySize = rowStride * height;

    for (var y = 0; y < height; y++) {
      final yRow = y * rowStride;
      final uvRow = ySize + (y >> 1) * rowStride;
      for (var x = 0; x < width; x++) {
        // NV21 chroma order is V,U per pair, at the even x index.
        final uvIndex = uvRow + (x & ~1);
        final (r, g, b) = _yuvToRgb(
          bytes[yRow + x],
          bytes[uvIndex + 1],
          bytes[uvIndex],
        );
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }
}

class _Letterbox {
  const _Letterbox({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
  });

  final img.Image image;
  final double scale;
  final double padX;
  final double padY;
}
