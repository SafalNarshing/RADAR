import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/gov_feed_provider.dart';
import '../../../theme/gov_colors.dart';
import '../../../widgets/gov/gov_report_card.dart';
import '../../../widgets/radar_brand_title.dart';
import '../rewards/give_reward_sheet.dart';

class GovFeedScreen extends StatefulWidget {
  const GovFeedScreen({super.key});

  @override
  State<GovFeedScreen> createState() => _GovFeedScreenState();
}

class _GovFeedScreenState extends State<GovFeedScreen> {
  late final GovFeedProvider _provider;

  static const _filters = [
    (null, 'All'),
    ('reported', 'New'),
    ('verified', 'Verified'),
    ('in_progress', 'In Progress'),
    ('fixed', 'Fixed'),
    ('rejected', 'Rejected'),
  ];

  @override
  void initState() {
    super.initState();
    _provider = GovFeedProvider();
    _provider.load();
  }

  Future<void> _confirmDelete(int id, String? title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text(
          'This permanently removes "${title ?? 'this report'}" and its '
          'photos, comments, and upvotes. This cannot be undone.',
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
    if (confirmed == true) await _provider.deleteReport(id);
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
        ),
        body: Consumer<GovFeedProvider>(
          builder: (context, provider, _) {
            return Column(
              children: [
                _filterBar(provider),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: provider.load,
                    color: GovColors.primary,
                    child: provider.loading && provider.reports.isEmpty
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: GovColors.primary,
                            ),
                          )
                        : provider.reports.isEmpty
                        ? _emptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 24),
                            itemCount: provider.reports.length,
                            itemBuilder: (context, i) {
                              final report = provider.reports[i];
                              return GovReportCard(
                                pothole: report,
                                onStatusChange: (status) =>
                                    provider.updateStatus(report.id, status),
                                onGiveReward: () => showGiveRewardSheet(
                                  context,
                                  report: report,
                                ),
                                onDelete: () =>
                                    _confirmDelete(report.id, report.title),
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filterBar(GovFeedProvider provider) {
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
                    Icons.fact_check_outlined,
                    size: 56,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No reports in this view',
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
