import 'package:flutter/material.dart';
import '../../models/pothole.dart';
import '../../services/supabase_service.dart';
import '../../theme/gov_colors.dart';
import 'status_picker.dart';

const _reportStatusOptions = [
  StatusOption('reported', 'Reported', Color(0xFF9E9E9E)),
  StatusOption('verified', 'Verified', Color(0xFF2196F3)),
  StatusOption('in_progress', 'In Progress', Color(0xFFFF9800)),
  StatusOption('fixed', 'Fixed', Color(0xFF4CAF50)),
  StatusOption('rejected', 'Rejected', Color(0xFFF44336)),
];

/// Report card for the police/government feed — swaps the citizen card's
/// upvote/comment actions for status-transition review actions.
class GovReportCard extends StatelessWidget {
  final Pothole pothole;
  final void Function(String newStatus) onStatusChange;
  final VoidCallback? onGiveReward;
  final VoidCallback? onDelete;

  const GovReportCard({
    super.key,
    required this.pothole,
    required this.onStatusChange,
    this.onGiveReward,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = pothole;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: GovColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GovColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.title ?? 'Untitled report',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: GovColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  p.timeAgo,
                  style: const TextStyle(
                    fontSize: 12,
                    color: GovColors.textSecondary,
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Reported by ${p.reporterName ?? 'Unknown'}',
              style: const TextStyle(
                fontSize: 12.5,
                color: GovColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (p.description != null && p.description!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                p.description!,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: GovColors.textSecondary,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _badge(
                  Pothole.severityLabel(p.severity),
                  Pothole.severityColor(p.severity),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => showStatusPicker(
                    context: context,
                    title: 'Update status',
                    current: p.status,
                    options: _reportStatusOptions,
                    onSelected: onStatusChange,
                  ),
                  child: _badge(
                    Pothole.statusLabel(p.status),
                    Pothole.statusColor(p.status),
                    trailingIcon: Icons.unfold_more,
                  ),
                ),
                if (p.status == 'fixed' && p.rewardGiven) ...[
                  const SizedBox(width: 8),
                  _badge('Rewarded', GovColors.success),
                ],
              ],
            ),
            if (p.primaryImagePath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  SupabaseService.getImageUrl(p.primaryImagePath!),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => Container(
                    height: 180,
                    color: GovColors.chipBg,
                    child: const Icon(
                      Icons.broken_image,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: GovColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    p.address ??
                        '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: GovColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (pothole.status == 'fixed' &&
                !pothole.rewardGiven &&
                onGiveReward != null) ...[
              const SizedBox(height: 14),
              _actionButton(
                'Give Reward',
                Icons.card_giftcard,
                GovColors.primary,
                onGiveReward!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color, {IconData? trailingIcon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, size: 13, color: color),
          ],
        ],
      ),
    );
  }
}
