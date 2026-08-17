import 'package:flutter/material.dart';

import '../../application/location/location_access_gateway.dart';

class LocationAccessBanner extends StatelessWidget {
  const LocationAccessBanner({
    super.key,
    required this.issue,
    required this.onAction,
  });

  final LocationAccessIssue issue;
  final VoidCallback onAction;

  static String messageFor(LocationAccessIssue issue) => switch (issue) {
    LocationAccessIssue.serviceDisabled =>
      'Konum servisi kapalı. Mevcut konumunuzu '
          'kullanabilmek için konumu açın.',
    LocationAccessIssue.permissionDenied =>
      'Konum izni verilmedi. Mevcut konumunuzu '
          'kullanmak için tekrar deneyebilirsiniz.',
    LocationAccessIssue.permissionDeniedForever =>
      'Konum izni uygulama ayarlarından kapatılmış. '
          'Konumu kullanmak için izni ayarlardan açın.',
    LocationAccessIssue.unavailable =>
      'Mevcut konum şu anda alınamadı. '
          'Lütfen tekrar deneyin.',
  };

  static String actionLabelFor(LocationAccessIssue issue) => switch (issue) {
    LocationAccessIssue.serviceDisabled => 'Konum Ayarları',
    LocationAccessIssue.permissionDenied => 'Tekrar Dene',
    LocationAccessIssue.permissionDeniedForever => 'Uygulama Ayarları',
    LocationAccessIssue.unavailable => 'Tekrar Dene',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(messageFor(issue))),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('location-access-action'),
              onPressed: onAction,
              child: Text(actionLabelFor(issue)),
            ),
          ],
        ),
      ),
    );
  }
}
