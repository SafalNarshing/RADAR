import 'package:flutter/material.dart';
import '../../models/pothole.dart';
import '../../services/supabase_service.dart';
import '../../screens/auth/auth_screen.dart';
import '../../screens/report/report_screen.dart';
import '../../widgets/pothole_card.dart';

/// ---------------------------------------------------------------------
/// RADAR design tokens, matching the tokens used in PotholeCard.
/// ---------------------------------------------------------------------
class _RadarColors {
  static const background = Color(0xFFF7F9FB),
      primary = Color(0xFF0F2B46),
      card = Colors.white,
      border = Color(0xFFEAEAEA),
      textPrimary = Color(0xFF111111),
      textSecondary = Color(0xFF6B7280);
  
}

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
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
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _RadarColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 1),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _RadarColors.border, width: 1),
            ),
          ),
          child: AppBar(
            titleSpacing: 0,
            centerTitle: false,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            foregroundColor: _RadarColors.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 16, right: 8),
                  child: _RadarLogo(),
                ),
                const Text(
                  'RADAR',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    fontSize: 18,
                    color: _RadarColors.textPrimary,
                  ),
                ),
              ],
            ),
            actions: [
              // Decorative notification affordance — no backend logic exists
              // for notifications, so this is presentational only.
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, size: 24),
                color: _RadarColors.textPrimary,
                onPressed: null,
                tooltip: 'Notifications',
              ),
              // Profile / more menu — wraps the original sign-out action so
              // that _signOut() is triggered exactly as before, just from a
              // menu instead of a bare icon button.
              PopupMenuButton<String>(
                icon: const Icon(Icons.account_circle_outlined, size: 26),
                color: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: _RadarColors.border),
                ),
                onSelected: (value) {
                  if (value == 'sign_out') _signOut();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'sign_out',
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: _RadarColors.textPrimary,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Sign out',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: _RadarColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadFeed(refresh: true),
        color: _RadarColors.primary,
        backgroundColor: Colors.white,
        child: _potholes.isEmpty && _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: _RadarColors.primary,
                  strokeWidth: 2.5,
                ),
              )
            : _potholes.isEmpty
            ? _emptyState()
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.only(top: 16, bottom: 96),
                itemCount: _potholes.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _potholes.length) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _RadarColors.primary,
                          strokeWidth: 2,
                        ),
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
          final added = await Navigator.of(
            context,
          ).push<bool>(MaterialPageRoute(builder: (_) => const ReportScreen()));
          if (added == true) _loadFeed(refresh: true);
        },
        backgroundColor: _RadarColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_road_rounded),
        label: const Text(
          'Report',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: _RadarColors.border),
                      ),
                      child: Icon(
                        Icons.add_road_rounded,
                        size: 44,
                        color: _RadarColors.primary.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No reports yet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _RadarColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Be the first to report a pothole',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _RadarColors.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small helper so a missing/broken asset never breaks the AppBar layout.
class _RadarLogo extends StatelessWidget {
  const _RadarLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/Radarlogo.png',
      height: 24,
      errorBuilder: (ctx, err, st) => const Icon(
        Icons.radar_rounded,
        size: 22,
        color: _RadarColors.primary,
      ),
    );
  }
}
