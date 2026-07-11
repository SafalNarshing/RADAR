import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Shows a [CameraController]'s preview in a fixed 3:4 (width:height) box —
/// the standard camera-app photo ratio — filling the available width.
///
/// Uses tight constraints (a [Stack] with [StackFit.expand]) so
/// [CameraPreview]'s own internal aspect-ratio/rotation handling is forced
/// to fill this exact box instead of adding its own letterboxing on top,
/// which is what previously produced an over-zoomed, wrongly-cropped
/// preview when this widget tried to independently compute a "cover fill"
/// scale on top of CameraPreview's internal sizing.
///
/// [overlay], if given, is layered on top of the preview inside the same
/// box, so it stays aligned with whatever's actually visible.
class CameraPreviewBox extends StatelessWidget {
  const CameraPreviewBox({super.key, required this.controller, this.overlay});

  final CameraController controller;
  final Widget? overlay;

  static const double _aspectRatio = 3 / 4;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [CameraPreview(controller), ?overlay],
        ),
      ),
    );
  }
}
