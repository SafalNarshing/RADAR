import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'full_image_viewer.dart';

/// Side-by-side "Reported" vs "Fixed" photos for a report — shown once it
/// has both an original image and a fixed_image_path, in the citizen and
/// government feed cards.
class BeforeAfterImages extends StatelessWidget {
  final String beforePath;
  final String afterPath;
  final String? fixedAtLabel;

  const BeforeAfterImages({
    super.key,
    required this.beforePath,
    required this.afterPath,
    this.fixedAtLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _viewFull(context, initialIndex: 0),
                child: _tile(beforePath, 'Reported', const Color(0xFFE53935)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => _viewFull(context, initialIndex: 1),
                child: _tile(afterPath, 'Fixed', const Color(0xFF4CAF50)),
              ),
            ),
          ],
        ),
        if (fixedAtLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            'Before & After · Fixed $fixedAtLabel',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  void _viewFull(BuildContext context, {required int initialIndex}) {
    showFullImageViewer(
      context,
      imageUrls: [
        SupabaseService.getImageUrl(beforePath),
        SupabaseService.getImageUrl(afterPath),
      ],
      labels: const ['Reported', 'Fixed'],
      initialIndex: initialIndex,
    );
  }

  Widget _tile(String path, String label, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Image.network(
            SupabaseService.getImageUrl(path),
            height: 140,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, st) => Container(
              height: 140,
              color: const Color(0xFFF6F7FB),
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
