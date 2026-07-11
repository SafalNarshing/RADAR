import 'package:flutter/material.dart';
import '../../widgets/pill_bottom_nav.dart';
import '../dashcam/dashcam_screen.dart';
import 'feed/gov_feed_screen.dart';
import 'home/gov_home_screen.dart';
import 'map/gov_map_screen.dart';
import 'rewards/gov_rewards_screen.dart';

class GovHomeShell extends StatefulWidget {
  const GovHomeShell({super.key});

  @override
  State<GovHomeShell> createState() => _GovHomeShellState();
}

class _GovHomeShellState extends State<GovHomeShell> {
  int _index = 0;

  static const _items = [
    NavItemData(Icons.dashboard_rounded, 'Home'),
    NavItemData(Icons.dynamic_feed_rounded, 'Feed'),
    NavItemData(Icons.videocam_rounded, 'Dash Cam'),
    NavItemData(Icons.map_rounded, 'Map'),
    NavItemData(Icons.card_giftcard_rounded, 'Rewards'),
  ];

  void _goToTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Dash Cam mounts a native camera SurfaceView that composites above
      // the Flutter UI regardless of IndexedStack visibility, so — as in
      // the citizen HomeShell — it's only built while its tab is active.
      body: IndexedStack(
        index: _index,
        children: [
          GovHomeScreen(onQuickAction: _goToTab),
          const GovFeedScreen(),
          _index == 2 ? const DashCamScreen() : const SizedBox.shrink(),
          const GovMapScreen(),
          const GovRewardsScreen(),
        ],
      ),
      bottomNavigationBar: PillBottomNav(
        currentIndex: _index,
        items: _items,
        onTap: _goToTab,
      ),
    );
  }
}
