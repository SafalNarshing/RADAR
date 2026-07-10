import 'package:flutter/material.dart';
import '../widgets/pill_bottom_nav.dart';
import 'dashcam/dashcam_screen.dart';
import 'feed/feed_screen.dart';
import 'map/potholes_map_screen.dart';
import 'status/status_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _items = [
    NavItemData(Icons.home_rounded, 'Feed'),
    NavItemData(Icons.videocam_rounded, 'Dash Cam'),
    NavItemData(Icons.map_rounded, 'Map'),
    NavItemData(Icons.fact_check_rounded, 'Status'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The dash cam's camera preview is a native SurfaceView, which
      // composites above the Flutter UI regardless of IndexedStack's
      // offstage/visibility logic — so unlike the other tabs, it must only
      // be mounted while its tab is actually selected, not kept alive
      // underneath in the stack.
      body: IndexedStack(
        index: _index,
        children: [
          const FeedScreen(),
          _index == 1 ? const DashCamScreen() : const SizedBox.shrink(),
          const PotholesMapScreen(),
          const StatusScreen(),
        ],
      ),
      bottomNavigationBar: PillBottomNav(
        currentIndex: _index,
        items: _items,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
