import 'package:flutter/material.dart';
import '../../models/pothole.dart';
import '../../services/supabase_service.dart';
import '../../screens/auth/auth_screen.dart';
import '../../screens/report/report_screen.dart';
import '../../widgets/pothole_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final List<Pothole> _potholes = [];
  Set<int> _upvotedIds = {};
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >=
          _scrollCtrl.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFeed({bool refresh = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      if (refresh) {
        _page = 1;
        _hasMore = true;
        _potholes.clear();
      }

      final results = await SupabaseService.getFeed(page: _page);
      final ids = results.map((p) => p.id).toList();
      final upvoted = await SupabaseService.getUserUpvotes(ids);

      setState(() {
        _potholes.addAll(results);
        _upvotedIds = {..._upvotedIds, ...upvoted};
        _hasMore = results.length == 20;
        _page++;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading) return;
    await _loadFeed();
  }

  Future<void> _signOut() async {
    await SupabaseService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 20),
            SizedBox(width: 8),
            Text('RADAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadFeed(refresh: true),
        color: const Color(0xFFE53935),
        child: _potholes.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFE53935)))
            : _potholes.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.only(top: 8, bottom: 80),
                    itemCount: _potholes.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _potholes.length) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFE53935), strokeWidth: 2),
                          ),
                        );
                      }
                      final p = _potholes[i];
                      return PotholeCard(
                        pothole: p,
                        isUpvoted: _upvotedIds.contains(p.id),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const ReportScreen()),
          );
          if (added == true) _loadFeed(refresh: true);
        },
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_road),
        label: const Text('Report', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_road, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('No reports yet',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('Be the first to report a pothole',
              style: TextStyle(color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}
