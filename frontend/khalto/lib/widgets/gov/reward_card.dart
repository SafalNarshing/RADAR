import 'package:flutter/material.dart';
import '../../models/reward.dart';
import '../../theme/gov_colors.dart';
import 'status_picker.dart';

const _rewardStatusOptions = [
  StatusOption('pending', 'Pending', Color(0xFFFF9800)),
  StatusOption('approved', 'Approved', Color(0xFF2196F3)),
  StatusOption('paid', 'Paid', Color(0xFF4CAF50)),
  StatusOption('rejected', 'Rejected', Color(0xFFF44336)),
];

class RewardCard extends StatelessWidget {
  final Reward reward;
  final void Function(String newStatus) onStatusChange;

  const RewardCard({
    super.key,
    required this.reward,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final r = reward;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GovColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GovColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.citizenName ?? 'Citizen',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: GovColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                r.amountLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: GovColors.primary,
                ),
              ),
            ],
          ),
          if (r.potholeTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              'For: ${r.potholeTitle}',
              style: const TextStyle(
                fontSize: 12.5,
                color: GovColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (r.reason != null && r.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.reason!,
              style: const TextStyle(
                fontSize: 13,
                color: GovColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GestureDetector(
                onTap: () => showStatusPicker(
                  context: context,
                  title: 'Update reward status',
                  current: r.status,
                  options: _rewardStatusOptions,
                  onSelected: (status) => onStatusChange(status),
                ),
                child: _badge(
                  Reward.statusLabel(r.status),
                  Reward.statusColor(r.status),
                  trailingIcon: Icons.unfold_more,
                ),
              ),
              _badge(
                Reward.modeLabel(r.rewardMode),
                Reward.modeColor(r.rewardMode),
              ),
              _badge(Reward.typeLabel(r.rewardType), GovColors.textSecondary),
            ],
          ),
        ],
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
