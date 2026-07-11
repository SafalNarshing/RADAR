import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../../../models/cctv_camera.dart';
import '../../../models/detection.dart';
import '../../../models/pothole.dart';
import '../../../services/gov_service.dart';
import '../../../services/onnx_detection_service.dart';
import '../../../theme/gov_colors.dart';
import '../../../widgets/bounding_box_overlay.dart';

/// Returns true if the camera was deleted from within the dialog, so the
/// caller knows to refresh its marker list.
Future<bool?> showCctvFeedDialog(
  BuildContext context, {
  required CctvCamera camera,
  Pothole? pothole,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (_) => _CctvFeedDialog(camera: camera, pothole: pothole),
  );
}

class _CctvFeedDialog extends StatefulWidget {
  final CctvCamera camera;
  final Pothole? pothole;

  const _CctvFeedDialog({required this.camera, required this.pothole});

  @override
  State<_CctvFeedDialog> createState() => _CctvFeedDialogState();
}

class _CctvFeedDialogState extends State<_CctvFeedDialog> {
  final _frameKey = GlobalKey();
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _deleting = false;
  String? _error;

  Timer? _inferenceTimer;
  bool _analyzing = false;
  List<Detection> _detections = const [];
  Size _detectionFrameSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.camera.asset.assetPath);
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      await _controller.play();
      if (!mounted) return;
      setState(() => _ready = true);

      // Best-effort preload so the first inference pass isn't the one
      // paying the multi-second model-load cost.
      unawaited(OnnxDetectionService.instance.preload());

      _inferenceTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _runInference(),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Feed unavailable: $e');
    }
  }

  // "Real-time" here means periodically screenshotting the currently
  // rendered video frame (there's no cross-platform raw-frame API for
  // video_player) and running the same on-device model used elsewhere in
  // the app on that frame.
  Future<void> _runInference() async {
    if (_analyzing || !mounted) return;
    _analyzing = true;
    try {
      final boundary =
          _frameKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) return;

      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (byteData == null) return;

      final detections = await OnnxDetectionService.instance.detectImageBytes(
        byteData.buffer.asUint8List(),
      );
      if (mounted) {
        setState(() {
          _detections = detections;
          _detectionFrameSize = Size(
            boundary.size.width,
            boundary.size.height,
          );
        });
      }
    } catch (_) {
      // Best-effort — skip this cycle on failure rather than surfacing an
      // error over an otherwise-fine video feed.
    } finally {
      _analyzing = false;
    }
  }

  @override
  void dispose() {
    _inferenceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this camera?'),
        content: Text(
          'This removes "${widget.camera.name}" from the map. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await GovService.deleteCctvCamera(widget.camera.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = 'Failed to delete camera: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0B0F14),
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(
        children: [
          const _LiveDot(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.camera.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.pothole != null
                      ? '→ ${widget.pothole!.title ?? widget.pothole!.address ?? 'Linked report'}'
                      : 'No linked report',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _deleting ? null : _confirmDelete,
            tooltip: 'Delete camera',
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.redAccent,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: CircularProgressIndicator(color: GovColors.accent),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RepaintBoundary(
                key: _frameKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(_controller),
                    BoundingBoxOverlay(
                      detections: _detections,
                      sourceSize: _detectionFrameSize,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _detectionSummary(),
        ],
      ),
    );
  }

  Widget _detectionSummary() {
    final label = _detections.isEmpty
        ? 'Scanning for road damage...'
        : _detections
              .map(
                (d) =>
                    '${d.damageClass.label} ${(d.confidence * 100).round()}%',
              )
              .join(' · ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.auto_awesome, size: 13, color: GovColors.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
