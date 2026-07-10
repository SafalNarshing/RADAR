import 'package:flutter/material.dart';
import '../models/pothole.dart';
import '../services/supabase_service.dart';
import 'random_profile.dart';

class PotholeCard extends StatefulWidget {
  final Pothole pothole;
  final bool isUpvoted;
  final VoidCallback? onTap;

  const PotholeCard({
    super.key,
    required this.pothole,
    this.isUpvoted = false,
    this.onTap,
  });

  @override
  State<PotholeCard> createState() => _PotholeCardState();
}

class _PotholeCardState extends State<PotholeCard> {
  late bool _upvoted;
  late int _count;
  bool _voting = false;
  bool _following = false;

  @override
  void initState() {
    super.initState();
    _upvoted = widget.isUpvoted;
    _count = widget.pothole.upvotesCount;
  }

  Future<void> _toggleUpvote() async {
    if (_voting) return;
    setState(() {
      _voting = true;
      _upvoted = !_upvoted;
      _count += _upvoted ? 1 : -1;
    });

    try {
      await SupabaseService.toggleUpvote(widget.pothole.id);
    } catch (_) {
      // Revert on failure
      setState(() {
        _upvoted = !_upvoted;
        _count += _upvoted ? 1 : -1;
      });
    } finally {
      setState(() => _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pothole;
    final profile =
        RandomProfile.forSeed(p.reportedBy ?? p.id.toString());

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar, name, timestamps, follow button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: NetworkImage(profile.avatarUrl),
                  onBackgroundImageError: (exception, stackTrace) {},
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            p.timeAgo,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.postedAtLabel,
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _followButton(),
              ],
            ),
            const SizedBox(height: 12),

            // Caption
            if (p.title != null || p.description != null) ...[
              if (p.title != null)
                Text(
                  p.title!,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (p.title != null && p.description != null)
                const SizedBox(height: 4),
              if (p.description != null && p.description!.isNotEmpty)
                Text(
                  p.description!,
                  style: TextStyle(
                      color: Colors.grey.shade800, fontSize: 13, height: 1.35),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 10),
            ],

            // Severity / status chips
            Row(
              children: [
                _badge(
                  Pothole.severityLabel(p.severity),
                  Pothole.severityColor(p.severity),
                ),
                const SizedBox(width: 8),
                _badge(
                  Pothole.statusLabel(p.status),
                  Pothole.statusColor(p.status),
                ),
              ],
            ),

            // Image
            if (p.primaryImagePath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  SupabaseService.getImageUrl(p.primaryImagePath!),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => Container(
                    height: 200,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image,
                        size: 48, color: Colors.grey),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Footer: upvote button + location meta
            Row(
              children: [
                _upvoteButton(),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          p.address ??
                              '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _followButton() {
    return GestureDetector(
      onTap: () => setState(() => _following = !_following),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _following ? Colors.white : Colors.black87,
          borderRadius: BorderRadius.circular(20),
          border: _following
              ? Border.all(color: Colors.grey.shade300)
              : null,
        ),
        child: Text(
          _following ? 'following' : 'follow',
          style: TextStyle(
            color: _following ? Colors.grey.shade700 : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _upvoteButton() {
    return GestureDetector(
      onTap: _toggleUpvote,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _upvoted
              ? const Color(0xFFE53935).withValues(alpha: 0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _upvoted ? Icons.arrow_upward : Icons.arrow_upward_outlined,
              size: 16,
              color: _upvoted ? const Color(0xFFE53935) : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
            Text(
              '$_count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color:
                    _upvoted ? const Color(0xFFE53935) : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
