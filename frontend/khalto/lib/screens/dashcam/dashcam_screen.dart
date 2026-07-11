import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/detection.dart';
import '../../services/onnx_detection_service.dart';
import '../../widgets/bounding_box_overlay.dart';
import '../../widgets/camera_preview_box.dart';
import '../../widgets/status_pill.dart';

class DashCamScreen extends StatefulWidget {
  const DashCamScreen({super.key});

  @override
  State<DashCamScreen> createState() => _DashCamScreenState();
}

class _DashCamScreenState extends State<DashCamScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  bool _recording = false;
  String? _error;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  bool _streamingImages = false;
  bool _processingFrame = false;
  List<Detection> _detections = const [];
  Size _detectionFrameSize = Size.zero;

  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _modelReady = OnnxDetectionService.instance.isReady;
    // Camera setup and model loading happen concurrently — whichever
    // finishes last starts the frame stream (each checks the other's
    // readiness), so we're not serializing two independent multi-hundred-ms
    // startup costs.
    _setup();
    if (!_modelReady) {
      OnnxDetectionService.instance.preload().then((_) {
        if (!mounted) return;
        setState(() => _modelReady = true);
        _startDetectionStream();
      });
    }
  }

  Future<void> _setup() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Camera permission is required to use the dash cam.';
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
        ResolutionPreset.medium,
        enableAudio: false,
        // Pin the format explicitly rather than relying on the platform
        // default, so the frame conversion path (which only handles
        // yuv420/bgra8888) always gets what it expects.
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
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

  /// Live bounding-box detection only runs while previewing, not while
  /// actually recording — `CameraController.startImageStream` throws if a
  /// video recording is already in progress (the platform camera session
  /// can't do both at once), so boxes pause during a recording and resume
  /// once it stops.
  Future<void> _startDetectionStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_streamingImages || _recording || !_modelReady) return;
    try {
      await controller.startImageStream(_onFrame);
      if (mounted) setState(() => _streamingImages = true);
    } catch (e) {
      // Image streaming isn't supported on this device/platform — dash cam
      // recording still works, just without the live overlay.
      debugPrint('DashCamScreen: startImageStream failed: $e');
    }
  }

  Future<void> _stopDetectionStream() async {
    final controller = _controller;
    if (controller == null || !_streamingImages) return;
    _streamingImages = false;
    try {
      await controller.stopImageStream();
    } catch (_) {}
    if (mounted) setState(() => _detections = const []);
  }

  void _onFrame(CameraImage image) {
    if (_processingFrame) return; // throttle: drop frames while busy
    _processingFrame = true;
    final sensorOrientation = _controller?.description.sensorOrientation ?? 0;
    OnnxDetectionService.instance
        .detectCameraImage(image, sensorOrientationDegrees: sensorOrientation)
        .then((detections) {
          _processingFrame = false;
          if (!mounted) return;
          final rotated = sensorOrientation % 360 == 90 || sensorOrientation % 360 == 270;
          setState(() {
            _detections = detections;
            _detectionFrameSize = rotated
                ? Size(image.height.toDouble(), image.width.toDouble())
                : Size(image.width.toDouble(), image.height.toDouble());
          });
        })
        .catchError((Object e) {
          _processingFrame = false;
          debugPrint('DashCamScreen: frame detection failed: $e');
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _streamingImages = false;
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _setup();
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (_recording) {
      _elapsedTimer?.cancel();
      try {
        final file = await controller.stopVideoRecording();
        // Dash cam preview only for now — discard the clip instead of
        // saving it anywhere permanent.
        final f = File(file.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _recording = false;
        _elapsed = Duration.zero;
      });
      await _startDetectionStream();
    } else {
      await _stopDetectionStream();
      try {
        await controller.startVideoRecording();
        setState(() => _recording = true);
        _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start recording: $e')),
          );
        }
        await _startDetectionStream();
      }
    }
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _elapsedTimer?.cancel();
    if (_streamingImages) {
      _controller?.stopImageStream().catchError((_) {});
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
       backgroundColor: const Color(0xFFF7F9FB),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreviewBox(
          controller: controller,
          overlay: _detections.isEmpty
              ? null
              : BoundingBoxOverlay(
                  detections: _detections,
                  sourceSize: _detectionFrameSize,
                ),
        ),
        if (_recording)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: StatusPill(
                icon: Icons.fiber_manual_record,
                iconColor: Colors.redAccent,
                label: _formatElapsed(_elapsed),
              ),
            ),
          )
        else if (!_modelReady)
          const Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: StatusPill(
                icon: Icons.hourglass_top,
                iconColor: Colors.amberAccent,
                label: 'Loading detection model…',
                showSpinner: true,
              ),
            ),
          )
        else if (_streamingImages)
          const Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: StatusPill(
                icon: Icons.radar,
                iconColor: Colors.greenAccent,
                label: 'Scanning for damage',
              ),
            ),
          ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white70, width: 4),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _recording ? 28 : 56,
                    height: _recording ? 28 : 56,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius:
                          BorderRadius.circular(_recording ? 8 : 28),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
