import 'package:flutter/material.dart';
import '../models/pothole.dart';
import '../services/supabase_service.dart';
import '../models/comment.dart';
import 'random_profile.dart';

/// ---------------------------------------------------------------------
/// RADAR design tokens used throughout this card.
/// Kept local to this file so the redesign is drop-in and self-contained.
/// ---------------------------------------------------------------------
class _RadarColors {
  static const primary = Color(0xFF0F2B46);
  static const card = Colors.white;
  static const border = Color(0xFFEAEAEA);
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF6B7280);
  static const chipBg = Color(0xFFF6F7FB);
}

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
  List<Comment> _comments = [];

  @override
  void initState() {
    super.initState();
    _upvoted = widget.isUpvoted;
    _count = widget.pothole.upvotesCount;
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final list = await SupabaseService.getComments(widget.pothole.id);
      if (mounted) setState(() => _comments = list.reversed.toList());
    } catch (_) {}
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
    final profile = RandomProfile.forSeed(p.reportedBy ?? p.id.toString());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _RadarColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _RadarColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          splashColor: _RadarColors.primary.withValues(alpha: 0.05),
          highlightColor: _RadarColors.primary.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: avatar, name, timestamps, optional menu button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _RadarColors.chipBg,
                      backgroundImage: NetworkImage(profile.avatarUrl),
                      onBackgroundImageError: (exception, stackTrace) {},
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: _RadarColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                p.timeAgo,
                                style: const TextStyle(
                                  color: _RadarColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: _RadarColors.textSecondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  p.postedAtLabel,
                                  style: const TextStyle(
                                    color: _RadarColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Optional overflow menu (purely presentational; no
                    // backend behavior attached, preserving original scope).
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        splashRadius: 18,
                        icon: Icon(
                          Icons.more_horiz,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                        onPressed: null,
                      ),
                    ),
                    // Follow button retained for future use, hidden by default
                    // exactly as in the original implementation.
                    // _followButton(),
                  ],
                ),
                const SizedBox(height: 14),

                // Caption
                if (p.title != null || p.description != null) ...[
                  if (p.title != null)
                    Text(
                      p.title!,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _RadarColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (p.title != null && p.description != null)
                    const SizedBox(height: 6),
                  if (p.description != null && p.description!.isNotEmpty)
                    Text(
                      p.description!,
                      style: const TextStyle(
                        color: _RadarColors.textSecondary,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        Image.network(
                          SupabaseService.getImageUrl(p.primaryImagePath!),
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, st) => Container(
                            height: 220,
                            color: _RadarColors.chipBg,
                            child: const Icon(
                              Icons.broken_image,
                              size: 48,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _overlayBadge(
                            Pothole.severityLabel(p.severity),
                            Pothole.severityColor(p.severity),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Footer: upvote button, comment button + location meta
                Row(
                  children: [
                    _upvoteButton(),
                    const SizedBox(width: 8),
                    _commentButton(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              p.address ??
                                  '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: _RadarColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Inline comments shown under the action icons (visible
                // without tapping into the sheet).
                if (_comments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _RadarColors.chipBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_comments.length > 2)
                          GestureDetector(
                            onTap: _openCommentsSheet,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'View all ${_comments.length} comments',
                                style: TextStyle(
                                  color: _RadarColors.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ..._comments
                            .take(2)
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${c.userName ?? 'You'}  ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: _RadarColors.textPrimary,
                                        ),
                                      ),
                                      TextSpan(
                                        text: c.content,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: _RadarColors.textSecondary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
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
          color: _following ? Colors.white : _RadarColors.primary,
          borderRadius: BorderRadius.circular(20),
          border: _following
              ? Border.all(color: _RadarColors.border)
              : null,
        ),
        child: Text(
          _following ? 'following' : 'follow',
          style: TextStyle(
            color: _following ? _RadarColors.textSecondary : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _commentButton() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _openCommentsSheet,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _RadarColors.chipBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 16,
                color: Colors.grey.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                '${_comments.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCommentsSheet() async {
    final initial = await SupabaseService.getComments(widget.pothole.id);
    final TextEditingController ctrl = TextEditingController();
    List<Comment> sheetComments = initial.toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx2).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx2).size.height * 0.65,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      height: 4,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Text(
                            'Comments',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _RadarColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: _RadarColors.border),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        itemCount: sheetComments.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (c, i) {
                          final cm = sheetComments[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              cm.userName ?? 'You',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: _RadarColors.textPrimary,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                cm.content,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: _RadarColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            trailing: Text(
                              _relativeTime(cm.createdAt),
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 11.5,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ctrl,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Write a comment...',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                                filled: true,
                                fillColor: _RadarColors.chipBg,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: _RadarColors.primary,
                            borderRadius: BorderRadius.circular(24),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () async {
                                final text = ctrl.text.trim();
                                if (text.isEmpty) return;
                                await SupabaseService.addComment(
                                  widget.pothole.id,
                                  text,
                                );
                                // reload comments in sheet and in card
                                final updated =
                                    await SupabaseService.getComments(
                                  widget.pothole.id,
                                );
                                sheetComments = updated.toList();
                                if (mounted) {
                                  setState(
                                    () =>
                                        _comments = updated.reversed.toList(),
                                  );
                                }
                                setModalState(() {});
                                ctrl.clear();
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 13,
                                ),
                                child: Text(
                                  'Send',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }

  Widget _upvoteButton() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _toggleUpvote,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _upvoted
                ? const Color(0xFFE53935).withValues(alpha: 0.12)
                : _RadarColors.chipBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _upvoted
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_upward_rounded,
                size: 16,
                color:
                    _upvoted ? const Color(0xFFE53935) : Colors.grey.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                '$_count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _upvoted
                      ? const Color(0xFFE53935)
                      : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pill chip used for the severity/status row below the caption.
  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  /// Frosted-style badge used as an overlay on top of the pothole image.
  Widget _overlayBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}