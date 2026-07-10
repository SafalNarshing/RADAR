import 'package:flutter/material.dart';
import '../models/pothole.dart';
import 'damage_marker_icon.dart';

/// Floating GIS-style legend explaining the pothole/crack marker colors.
/// Meant to sit in a corner of the map inside a [Stack] via [Positioned] —
/// it sizes to its content so it stays compact on any screen width.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Legend',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
              color: Colors.black.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 8),
          const _LegendRow(type: DamageType.pothole),
          const SizedBox(height: 6),
          const _LegendRow(type: DamageType.crack),
          const SizedBox(height: 6),
          const _LegendRow(type: DamageType.missingManhole),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final DamageType type;

  const _LegendRow({required this.type});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DamageMarkerIcon(type: type, size: 20),
        const SizedBox(width: 8),
        Text(
          Pothole.damageLabel(type),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
