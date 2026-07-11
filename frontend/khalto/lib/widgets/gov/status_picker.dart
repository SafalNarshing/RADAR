import 'package:flutter/material.dart';
import '../../theme/gov_colors.dart';

class StatusOption {
  final String value;
  final String label;
  final Color color;

  const StatusOption(this.value, this.label, this.color);
}

/// Bottom sheet listing every status [current] could move to, with the
/// current one highlighted. Lets police jump to any status directly rather
/// than only stepping through a fixed forward sequence.
Future<void> showStatusPicker({
  required BuildContext context,
  required String title,
  required String current,
  required List<StatusOption> options,
  required ValueChanged<String> onSelected,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: GovColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...options.map((o) {
              final selected = o.value == current;
              return ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  if (!selected) onSelected(o.value);
                },
                tileColor: selected ? o.color.withValues(alpha: 0.08) : null,
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: o.color,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  o.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: GovColors.textPrimary,
                  ),
                ),
                trailing: selected
                    ? Icon(Icons.check_circle, color: o.color, size: 20)
                    : null,
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
