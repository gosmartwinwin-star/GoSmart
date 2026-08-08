import 'package:flutter/material.dart';
import '../application/ports.dart';
import '../controllers/admin_auth_controller.dart';
import '../controllers/driver_applications_controller.dart';
import '../core/formatting.dart';
import '../domain/driver_application.dart';
import 'driver_application_details_screen.dart';

final class DriverApplicationsScreen extends StatelessWidget {
  const DriverApplicationsScreen({
    required this.controller,
    required this.gateway,
    required this.reviews,
    required this.reviewEvents,
    required this.auth,
    super.key,
  });
  final DriverApplicationsController controller;
  final DriverApplicationAdminReadGateway gateway;
  final DriverApplicationAdminReviewGateway reviews;
  final DriverApplicationReviewEventsGateway reviewEvents;
  final AdminAuthController auth;

  void _open(BuildContext context, String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DriverApplicationDetailsScreen(
        applicationId: id,
        gateway: gateway,
        reviews: reviews,
        reviewEvents: reviewEvents,
        refreshList: controller.refresh,
        auth: auth,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Text(
                  'Sürücü Başvuruları',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                OutlinedButton.icon(
                  onPressed: controller.isLoading ? null : controller.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Yenile'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DriverApplicationReviewQueueState.values
                  .map(
                    (state) => ChoiceChip(
                      label: Text(state.label),
                      selected: controller.selectedReviewState == state,
                      onSelected: (_) => controller.changeReviewState(state),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            Expanded(child: _body(context)),
          ],
        ),
      );
    },
  );

  Widget _body(BuildContext context) {
    if (controller.isLoading && controller.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Başvurular yükleniyor',
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
              onPressed: controller.loadInitial,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }
    if (controller.items.isEmpty) {
      return const Center(child: Text('Bu durumda başvuru bulunmuyor.'));
    }
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 1050) {
                return ListView.separated(
                  itemCount: controller.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) =>
                      _card(context, controller.items[index]),
                );
              }
              return _desktopList(context);
            },
          ),
        ),
        if (controller.errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(controller.errorMessage!),
          ),
        if (controller.nextCursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: controller.isLoadingMore ? null : controller.loadMore,
              child: controller.isLoadingMore
                  ? const CircularProgressIndicator(
                      semanticsLabel: 'Daha fazla başvuru yükleniyor',
                    )
                  : const Text('Daha Fazla Yükle'),
            ),
          ),
      ],
    );
  }

  Widget _desktopList(BuildContext context) => Column(
    children: [
      const _ApplicationTableRow(
        isHeader: true,
        cells: [
          Text('Başvuru Tarihi'),
          Text('Çalışma Şekli'),
          Text('Araç'),
          Text('Model Yılı'),
          Text('Ruhsat Sahibi'),
          Text('Durum'),
          Text('İşlem'),
        ],
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.separated(
          itemCount: controller.items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final item = controller.items[index];
            return _ApplicationTableRow(
              cells: [
                Text(formatAdminDate(item.submittedAt)),
                Text(item.workType.label),
                Text('${item.vehicleBrand} ${item.vehicleModel}'),
                Text('${item.vehicleModelYear}'),
                Text(item.registrationOwnerType.label),
                Text(item.reviewState.label),
                OutlinedButton(
                  onPressed: () => _open(context, item.applicationId),
                  child: const Text('İncele'),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );

  Widget _card(BuildContext context, DriverApplicationReviewSummary item) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.vehicleBrand} ${item.vehicleModel}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(formatAdminDate(item.submittedAt)),
              Text(item.workType.label),
              Text(item.registrationOwnerType.label),
              Text(item.reviewState.label),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => _open(context, item.applicationId),
                  child: const Text('İncele'),
                ),
              ),
            ],
          ),
        ),
      );
}

final class _ApplicationTableRow extends StatelessWidget {
  const _ApplicationTableRow({required this.cells, this.isHeader = false});
  final List<Widget> cells;
  final bool isHeader;

  static const _flexes = [15, 12, 15, 8, 13, 17, 10];

  @override
  Widget build(BuildContext context) => Container(
    color: isHeader ? Theme.of(context).colorScheme.surfaceContainerLow : null,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(
        cells.length,
        (index) => Expanded(
          flex: _flexes[index],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: DefaultTextStyle.merge(
              style: isHeader
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: cells[index],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
