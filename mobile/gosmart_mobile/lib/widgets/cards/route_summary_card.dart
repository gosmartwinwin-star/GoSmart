import 'dart:math' as math;

import 'package:flutter/material.dart';

class RouteSummaryCard extends StatelessWidget {
  final int distanceMeters;
  final int durationSeconds;

  const RouteSummaryCard({
    super.key,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  String _formatDistance(int meters) {
    if (meters < 1000) {
      return '$meters m';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(int seconds) {
    final totalMinutes = math.max(1, (seconds / 60).ceil());

    if (totalMinutes < 60) {
      return '$totalMinutes dk';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (minutes == 0) {
      return '$hours sa';
    }

    return '$hours sa $minutes dk';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                icon: Icons.route_rounded,
                label: 'Mesafe',
                value: _formatDistance(distanceMeters),
              ),
            ),
            const SizedBox(
              height: 46,
              child: VerticalDivider(width: 32, thickness: 1),
            ),
            Expanded(
              child: _SummaryItem(
                icon: Icons.schedule_rounded,
                label: 'Tahmini süre',
                value: _formatDuration(durationSeconds),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
