import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/rewards_provider.dart';
import '../../../theme/gov_colors.dart';
import '../../../widgets/gov/reward_card.dart';
import 'give_reward_sheet.dart';

class GovRewardsScreen extends StatefulWidget {
  const GovRewardsScreen({super.key});

  @override
  State<GovRewardsScreen> createState() => _GovRewardsScreenState();
}

class _GovRewardsScreenState extends State<GovRewardsScreen> {
  late final RewardsProvider _provider;

  static const _filters = [
    (null, 'All'),
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('paid', 'Paid'),
    ('rejected', 'Rejected'),
  ];

  @override
  void initState() {
    super.initState();
    _provider = RewardsProvider();
    _provider.load();
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
          title: const Text(
            'Rewards',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
          ),
        ),
        body: Consumer<RewardsProvider>(
          builder: (context, provider, _) {
            return Column(
              children: [
                _filterBar(provider),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: provider.load,
                    color: GovColors.primary,
                    child: provider.loading && provider.rewards.isEmpty
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: GovColors.primary,
                            ),
                          )
                        : provider.rewards.isEmpty
                        ? _emptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 96),
                            itemCount: provider.rewards.length,
                            itemBuilder: (context, i) {
                              final reward = provider.rewards[i];
                              return RewardCard(
                                reward: reward,
                                onStatusChange: (status) =>
                                    provider.updateStatus(reward, status),
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showGiveRewardSheet(context, onDone: _provider.load),
          backgroundColor: GovColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.card_giftcard),
          label: const Text('Give Reward'),
        ),
      ),
    );
  }

  Widget _filterBar(RewardsProvider provider) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (value, label) = _filters[i];
          final selected = provider.filter == value;
          return GestureDetector(
            onTap: () => provider.setFilter(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? GovColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? GovColors.primary : GovColors.border,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : GovColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.card_giftcard_outlined,
                    size: 56,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No rewards yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
