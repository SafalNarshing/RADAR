import 'package:flutter/material.dart';
import '../../models/pothole.dart';
import '../../models/tax_reward.dart';
import '../../services/supabase_service.dart';
import '../../widgets/pothole_card.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  List<Pothole> _reports = [];
  Set<int> _upvotedIds = {};
  List<TaxReward> _taxRewards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await SupabaseService.getMyReports();
      final ids = results.map((p) => p.id).toList();
      final upvoted = await SupabaseService.getUserUpvotes(ids);
      final taxRewards = await SupabaseService.getMyTaxRewards();
      if (!mounted) return;
      setState(() {
        _reports = results;
        _upvotedIds = upvoted;
        _taxRewards = taxRewards;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Image.asset(
                'assets/Radarlogo.png',
                height: 24,
                errorBuilder: (ctx, err, st) =>
                    const SizedBox(width: 24, height: 24),
              ),
            ),
            const Text(
              'RADAR',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            if (_taxRewards.isNotEmpty) _taxCreditBanner(),
            Expanded(
              child: _loading && _reports.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _reports.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.fact_check_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "You haven't reported anything yet",
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      itemCount: _reports.length,
                      itemBuilder: (context, i) {
                        final p = _reports[i];
                        return PotholeCard(
                          pothole: p,
                          isUpvoted: _upvotedIds.contains(p.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taxCreditBanner() {
    final totalPoints = _taxRewards.fold<int>(0, (sum, r) => sum + r.points);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Color(0xFF1E88E5),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tax Credit Points: $totalPoints',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF0D1B3E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You can claim this as a tax reduction next year',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
