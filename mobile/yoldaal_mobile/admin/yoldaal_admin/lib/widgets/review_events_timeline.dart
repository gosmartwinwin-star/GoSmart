import 'package:flutter/material.dart';
import '../controllers/driver_application_review_events_controller.dart';
import '../core/formatting.dart';

final class DriverApplicationReviewEventsTimeline extends StatelessWidget {
  const DriverApplicationReviewEventsTimeline({
    required this.controller,
    super.key,
  });
  final DriverApplicationReviewEventsController controller;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sürücü başvurusu inceleme geçmişi',
    container: true,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'İnceleme Geçmişi',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Divider(height: 24),
              if (controller.isLoading && controller.items.isEmpty)
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'İnceleme geçmişi yükleniyor',
                  ),
                )
              else if (controller.errorMessage != null &&
                  controller.items.isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('İnceleme geçmişi şu anda yüklenemedi.'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: controller.refresh,
                      child: const Text('Tekrar Dene'),
                    ),
                  ],
                )
              else if (controller.items.isEmpty)
                const Text('Bu başvuru için henüz inceleme geçmişi bulunmuyor.')
              else ...[
                ...controller.items.map(
                  (event) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.history, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.type.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(formatAdminDate(event.occurredAt)),
                              if (event.documentType != null)
                                Text(event.documentType!.label),
                              if (event.decision != null)
                                Text(event.decision!.label),
                              if (event.reason != null)
                                Text(event.reason!.label),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (controller.errorMessage != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('İnceleme geçmişi şu anda yüklenemedi.'),
                  ),
                if (controller.nextCursor != null)
                  OutlinedButton(
                    onPressed: controller.isLoadingMore
                        ? null
                        : controller.loadMore,
                    child: controller.isLoadingMore
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              semanticsLabel:
                                  'Daha fazla inceleme geçmişi yükleniyor',
                            ),
                          )
                        : const Text('Daha Fazla Göster'),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
