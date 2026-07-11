import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom viewer for one or more images — opened when a
/// tapped thumbnail (shown cropped via BoxFit.cover) needs to be seen in
/// full, e.g. to see exactly where a pothole is in the frame.
Future<void> showFullImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  List<String>? labels,
  int initialIndex = 0,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) =>
          _FullImageViewer(
            imageUrls: imageUrls,
            labels: labels,
            initialIndex: initialIndex,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _FullImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final List<String>? labels;
  final int initialIndex;

  const _FullImageViewer({
    required this.imageUrls,
    this.labels,
    required this.initialIndex,
  });

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<_FullImageViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    widget.imageUrls[i],
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, st) => const Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
            if (labels != null && labels.length > _index)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      labels[_index],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
