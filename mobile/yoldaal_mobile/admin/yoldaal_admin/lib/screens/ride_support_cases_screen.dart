import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/ride_support_cases_controller.dart';
import '../domain/ride_support_case.dart';

final class RideSupportCasesScreen extends StatelessWidget {
  const RideSupportCasesScreen({required this.controller, super.key});
  final RideSupportCasesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.isLoading && controller.items.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Yolculuk bildirimleri yükleniyor',
          ),
        );
      }

      if (controller.errorMessage != null && controller.items.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(controller.errorMessage!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: controller.refresh,
                child: const Text('Tekrar Yükle'),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Yolculuk Bildirimleri',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Yenile',
                  onPressed: controller.isLoading ? null : controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (controller.errorMessage != null) ...[
              Text(
                controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            if (controller.actionErrorMessage != null) ...[
              Text(
                controller.actionErrorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            if (controller.items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Henüz yolculuk bildirimi yok.'),
                ),
              )
            else
              ...controller.items.map(
                (item) => _SupportCaseCard(item: item, controller: controller),
              ),
            if (controller.nextCursor != null) ...[
              const SizedBox(height: 16),
              Center(
                child: OutlinedButton(
                  onPressed: controller.isLoadingMore
                      ? null
                      : controller.loadMore,
                  child: controller.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Daha Fazla Yükle'),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

final class _SupportCaseCard extends StatelessWidget {
  const _SupportCaseCard({required this.item, required this.controller});

  final RideSupportCaseSummary item;
  final RideSupportCasesController controller;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat(
      'dd.MM.yyyy HH:mm',
    ).format(item.createdAt.toLocal());
    final note = item.reporterNote?.trim();
    final actionLabel = item.status.actionLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.category.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(date),
                ],
              ),
              const SizedBox(height: 10),
              Text('Durum: ${item.status.label}'),
              Text('Bildiren: ${item.reporterRole.label}'),
              Text('Ride ID: ${item.rideId}'),
              Text('Case ID: ${item.caseId}'),
              const SizedBox(height: 10),
              Text(note == null || note.isEmpty ? 'Açıklama eklenmedi.' : note),
              if (actionLabel != null && controller.supportsTransitions) ...[
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: controller.isMutating
                      ? null
                      : () => controller.advanceStatus(item),
                  child: Text(actionLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
