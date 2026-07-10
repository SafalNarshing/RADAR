import 'package:flutter/material.dart';
import '../models/pothole.dart';

/// "AI Detection" confirmation dialog shown after a confident classification.
/// Returns true if the user tapped Confirm, false if they tapped Retake,
/// null if the dialog was otherwise dismissed.
Future<bool?> showDetectionConfirmDialog(
  BuildContext context, {
  required DamageType type,
  required double confidence,
}) {
  final color = Pothole.damageColor(type);
  final label = Pothole.damageLabel(type);
  final pct = (confidence * 100).toStringAsFixed(0);

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('AI Detection',
          style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Detected: $label',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Confidence: $pct%',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Retake Image'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: color, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Confirm Report'),
        ),
      ],
    ),
  );
}

/// Manual damage-type picker shown when detection is inconclusive. Returns
/// the chosen [DamageType], or null if dismissed without a selection.
Future<DamageType?> showManualDamageTypeDialog(BuildContext context) {
  DamageType? selected;

  return showDialog<DamageType>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "We couldn't confidently identify the road damage.",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please select the damage type:',
                style: TextStyle(fontSize: 13)),
            RadioGroup<DamageType>(
              groupValue: selected,
              onChanged: (v) => setDialogState(() => selected = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: DamageType.values
                    .map(
                      (type) => RadioListTile<DamageType>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: Pothole.damageColor(type),
                        title: Text(Pothole.damageLabel(type)),
                        value: type,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed:
                selected == null ? null : () => Navigator.of(ctx).pop(selected),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}
