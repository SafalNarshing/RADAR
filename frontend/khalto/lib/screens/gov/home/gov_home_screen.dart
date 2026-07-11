import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/gov_dashboard_provider.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/gov_colors.dart';
import '../../../widgets/gov/quick_action_button.dart';
import '../../../widgets/gov/stat_card.dart';
import '../../../widgets/radar_brand_title.dart';
import '../../auth/auth_screen.dart';

/// Home tab of the Government/Police shell: dashboard stat cards + quick
/// actions. [onQuickAction] jumps to another tab index in [GovHomeShell].
class GovHomeScreen extends StatefulWidget {
  final void Function(int tabIndex) onQuickAction;

  const GovHomeScreen({super.key, required this.onQuickAction});

  @override
  State<GovHomeScreen> createState() => _GovHomeScreenState();
}

class _GovHomeScreenState extends State<GovHomeScreen> {
  late final GovDashboardProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GovDashboardProvider();
    _provider.load();
  }

  Future<void> _signOut() async {
    await SupabaseService.signOut();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        backgroundColor: GovColors.background,
        appBar: AppBar(
          titleSpacing: 16,
          centerTitle: false,
          backgroundColor: Colors.white,
          foregroundColor: GovColors.textPrimary,
          elevation: 0,
          title: const RadarBrandTitle(textColor: GovColors.textPrimary),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign out',
              onPressed: _signOut,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Consumer<GovDashboardProvider>(
          builder: (context, provider, _) {
            return RefreshIndicator(
              onRefresh: provider.load,
              color: GovColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (provider.loading && provider.stats == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: GovColors.primary,
                        ),
                      ),
                    )
                  else if (provider.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: Text(provider.error!)),
                    )
                  else
                    _statGrid(provider),
                  const SizedBox(height: 28),
                  const Text(
                    'Quick actions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GovColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _quickActions(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statGrid(GovDashboardProvider provider) {
    final stats = provider.stats!;
    final cards = [
      StatCard(
        label: 'Total Reports',
        value: '${stats.totalReports}',
        icon: Icons.assignment_outlined,
        accent: GovColors.primary,
      ),
      StatCard(
        label: 'Active Reports',
        value: '${stats.activeReports}',
        icon: Icons.pending_actions_outlined,
        accent: GovColors.warning,
      ),
      StatCard(
        label: 'Fixed This Month',
        value: '${stats.fixedThisMonth}',
        icon: Icons.task_alt_outlined,
        accent: GovColors.success,
      ),
      StatCard(
        label: 'Total Rewards Distributed',
        value: 'Rs. ${_formatAmount(stats.totalRewardsDistributed)}',
        icon: Icons.card_giftcard_outlined,
        accent: GovColors.accent,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: cards,
    );
  }

  Widget _quickActions() {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: [
        QuickActionButton(
          label: 'Review Reports',
          icon: Icons.rate_review_outlined,
          onTap: () => widget.onQuickAction(1),
        ),
        QuickActionButton(
          label: 'Dash Cam',
          icon: Icons.videocam_outlined,
          onTap: () => widget.onQuickAction(2),
        ),
        QuickActionButton(
          label: 'View Map',
          icon: Icons.map_outlined,
          onTap: () => widget.onQuickAction(3),
        ),
        QuickActionButton(
          label: 'Give Reward',
          icon: Icons.card_giftcard_outlined,
          onTap: () => widget.onQuickAction(4),
        ),
      ],
    );
  }

  String _formatAmount(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
