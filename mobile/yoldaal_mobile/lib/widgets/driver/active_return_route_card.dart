import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/return_route/published_return_route.dart';

class ActiveReturnRouteCard extends StatelessWidget {
  final PublishedReturnRoute published;
  final String destinationLabel;

  const ActiveReturnRouteCard({
    super.key,
    required this.published,
    required this.destinationLabel,
  });

  static String formatDistance(int meters) => meters < 1000
      ? '$meters m'
      : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

  static String formatDuration(int seconds) {
    final minutes = math.max(1, (seconds / 60).ceil());
    if (minutes < 60) return '$minutes dk';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '$hours sa' : '$hours sa $remainder dk';
  }

  @override
  Widget build(BuildContext context) {
    final expires = published.expiresAt.toLocal();
    final remaining = expires.difference(DateTime.now());
    final remainingText = remaining.isNegative
        ? 'Süresi doldu'
        : formatDuration(remaining.inSeconds);
    final expiryText = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(expires),
      alwaysUse24HourFormat: true,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aktif Dönüş Rotası',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Durum: Aktif'),
            Text('Hedef: $destinationLabel'),
            Text('Mesafe: ${formatDistance(published.distanceMeters)}'),
            Text('Tahmini süre: ${formatDuration(published.durationSeconds)}'),
            Text('Geçerlilik bitişi: $expiryText'),
            Text('Kalan geçerlilik: $remainingText'),
          ],
        ),
      ),
    );
  }
}
