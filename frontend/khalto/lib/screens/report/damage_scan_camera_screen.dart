import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../../models/detection.dart';
import '../../models/pothole.dart';
import '../../services/onnx_detection_service.dart';
import '../../widgets/bounding_box_overlay.dart';
import '../../widgets/camera_preview_box.dart';
import '../../widgets/status_pill.dart';

const _navy = Color(0xFF0D1B3E);

/// Live camera → capture → on-device damage scan → confirm/retake.
///
/// Used by the report flow's "Camera" option instead of a plain
/// image_picker capture, so the user sees the model's bounding boxes drawn
/// on their photo before it's attached to the report. Pops with
/// `(image, damageType)` once accepted, or `null` if the user backs out.
/// [damageType] is null when nothing confident was detected — callers
/// should fall back to manual classification in that case.
class DamageScanCameraScreen extends StatefulWidget {
  const DamageScanCameraScreen({super.key});

  @override
  State<DamageScanCameraScreen> createState() => _DamageScanCameraScreenState();
}

class _DamageScanCameraScreenState extends State<DamageScanCameraScreen> {
  CameraController? _controller;
  bool _initializing = true;
  String? _error;
  bool _scanning = false;

  XFile? _capturedImage;
  Uint8List? _capturedBytes;
  Size? _capturedImageSize;
  List<Detection> _detections = const [];

  bool _modelReady = false;
  bool _modelStatusVisible = true;
  Timer? _modelStatusTimer;

  bool _streamingImages = false;
  bool _processingFrame = false;
  List<Detection> _liveDetections = const [];
  Size _liveFrameSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _setup();

    _modelReady = OnnxDetectionService.instance.isReady;
    if (_modelReady) {
      _modelStatusVisible = false;
    } else {
      OnnxDetectionService.instance.preload().then((_) {
        if (!mounted) return;
        setState(() => _modelReady = true);
        _modelStatusTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _modelStatusVisible = false);
        });
        _startDetectionStream();
      });
    }
  }

  @override
  void dispose() {
    _modelStatusTimer?.cancel();
    if (_streamingImages) {
      _controller?.stopImageStream().catchError((_) {});
    }
    _controller?.dispose();
    super.dispose();
  }

  /// Live preview scanning, same throttled-stream pattern as the dashcam
  /// screen — lets the user see bounding boxes while framing the shot,
  /// not just after tapping capture.
  Future<void> _startDetectionStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_streamingImages || !_modelReady) return;
    try {
      await controller.startImageStream(_onFrame);
      if (mounted) setState(() => _streamingImages = true);
    } catch (e) {
      debugPrint('DamageScanCameraScreen: startImageStream failed: $e');
    }
  }

  Future<void> _stopDetectionStream() async {
    final controller = _controller;
    if (controller == null || !_streamingImages) return;
    _streamingImages = false;
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  void _onFrame(CameraImage image) {
    if (_processingFrame) return;
    _processingFrame = true;
    final sensorOrientation = _controller?.description.sensorOrientation ?? 0;
    OnnxDetectionService.instance
        .detectCameraImage(image, sensorOrientationDegrees: sensorOrientation)
        .then((detections) {
          _processingFrame = false;
          if (!mounted) return;
          final rotated = sensorOrientation % 360 == 90 || sensorOrientation % 360 == 270;
          setState(() {
            _liveDetections = detections;
            _liveFrameSize = rotated
                ? Size(image.height.toDouble(), image.width.toDouble())
                : Size(image.width.toDouble(), image.height.toDouble());
          });
        })
        .catchError((Object e) {
          _processingFrame = false;
          debugPrint('DamageScanCameraScreen: frame detection failed: $e');
        });
  }

  Future<void> _setup() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Camera permission is required to scan for damage.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _error = 'No camera found on this device.';
        });
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      if (_modelReady) await _startDetectionStream();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Failed to start camera: $e';
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _scanning) {
      return;
    }

    setState(() => _scanning = true);
    try {
      // Stop the stream before capture — required on iOS, safe on Android.
      await _stopDetectionStream();
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      final detections =
          await OnnxDetectionService.instance.detectImageBytes(bytes);
      if (!mounted) return;
      setState(() {
        _capturedImage = file;
        _capturedBytes = bytes;
        _capturedImageSize = decoded != null
            ? Size(decoded.width.toDouble(), decoded.height.toDouble())
            : Size.zero;
        _detections = detections;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e')),
      );
    }
  }

  void _retake() {
    setState(() {
      _capturedImage = null;
      _capturedBytes = null;
      _capturedImageSize = null;
      _detections = const [];
    });
    _startDetectionStream();
  }

  void _usePhoto() {
    final image = _capturedImage;
    if (image == null) return;

    // Use the highest-confidence detection's type. Multiple detections of
    // different classes just means the top one wins — this only sets the
    // report's single damage-type field, not a list.
    DamageType? damageType;
    if (_detections.isNotEmpty) {
      final top = _detections.reduce(
        (a, b) => b.confidence > a.confidence ? b : a,
      );
      damageType = top.damageClass.toDamageType;
    }

    Navigator.of(context).pop((image, damageType));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_capturedImage != null) return _reviewView();

    if (_initializing) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return _errorView(_error!);
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreviewBox(
          controller: controller,
          overlay: _liveDetections.isEmpty
              ? null
              : BoundingBoxOverlay(
                  detections: _liveDetections,
                  sourceSize: _liveFrameSize,
                ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: !_modelReady
                ? const StatusPill(
                    icon: Icons.hourglass_top,
                    iconColor: Colors.amberAccent,
                    label: 'Loading detection model…',
                    showSpinner: true,
                  )
                : _modelStatusVisible
                ? const StatusPill(
                    icon: Icons.check_circle,
                    iconColor: Colors.greenAccent,
                    label: 'Model ready',
                  )
                : const Text(
                    'Point at the damage and capture',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
          ),
        ),
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _scanning ? null : _capture,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white70, width: 4),
                ),
                child: _scanning
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _navy,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewView() {
    final bytes = _capturedBytes!;
    final size = _capturedImageSize!;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: size.width == 0 ? 1 : size.width / size.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes, fit: BoxFit.cover),
                  BoundingBoxOverlay(detections: _detections, sourceSize: size),
                ],
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _detections.isEmpty
                    ? 'No damage detected in this photo — you can still use it, or retake.'
                    : '${_detections.length} damage spot(s) detected',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _retake,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Retake', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _usePhoto,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Use Photo', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
