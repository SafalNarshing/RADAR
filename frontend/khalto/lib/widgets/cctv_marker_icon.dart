import 'package:flutter/material.dart';

/// Camera-badge marker used for CCTV cameras on both the citizen and
/// government maps. Tap behavior differs per screen — this widget is purely
/// the visual.
class CctvMarkerIcon extends StatelessWidget {
  const CctvMarkerIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D29),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
