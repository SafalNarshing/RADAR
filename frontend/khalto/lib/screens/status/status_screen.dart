import 'package:flutter/material.dart';
import '../../models/pothole.dart';
import '../../services/supabase_service.dart';
import '../../widgets/pothole_card.dart';

const _navy = Color(0xFF0D1B3E);

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  List<Pothole> _reports = [];
  Set<int> _upvotedIds = {};
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
      if (!mounted) return;
      setState(() {
        _reports = results;
        _upvotedIds = upvoted;
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
    );
  }
}
