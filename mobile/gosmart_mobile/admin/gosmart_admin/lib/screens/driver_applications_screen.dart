import 'package:flutter/material.dart';
import '../application/ports.dart';
import '../controllers/driver_applications_controller.dart';
import '../core/formatting.dart';
import '../domain/driver_application.dart';
import 'driver_application_details_screen.dart';

final class DriverApplicationsScreen extends StatelessWidget {
  const DriverApplicationsScreen({
    required this.controller,
    required this.gateway,
    super.key,
  });
  final DriverApplicationsController controller;
  final DriverApplicationAdminReadGateway gateway;

  void _open(BuildContext context, String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          DriverApplicationDetailsScreen(applicationId: id, gateway: gateway),
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
              children: DriverApplicationReviewStatus.values
                  .map(
                    (status) => ChoiceChip(
                      label: Text(status.label),
                      selected: controller.selectedStatus == status,
                      onSelected: (_) => controller.changeStatus(status),
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
              if (constraints.maxWidth < 760) {
                return ListView.separated(
                  itemCount: controller.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) =>
                      _card(context, controller.items[index]),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Başvuru Tarihi')),
                      DataColumn(label: Text('Çalışma Şekli')),
                      DataColumn(label: Text('Araç')),
                      DataColumn(label: Text('Model Yılı')),
                      DataColumn(label: Text('Ruhsat Sahibi')),
                      DataColumn(label: Text('Durum')),
                      DataColumn(label: Text('İşlem')),
                    ],
                    rows: controller.items
                        .map(
                          (item) => DataRow(
                            cells: [
                              DataCell(Text(formatAdminDate(item.submittedAt))),
                              DataCell(Text(item.workType.label)),
                              DataCell(
                                Text(
                                  '${item.vehicleBrand} ${item.vehicleModel}',
                                ),
                              ),
                              DataCell(Text('${item.vehicleModelYear}')),
                              DataCell(Text(item.registrationOwnerType.label)),
                              DataCell(Text(item.status.label)),
                              DataCell(
                                OutlinedButton(
                                  onPressed: () =>
                                      _open(context, item.applicationId),
                                  child: const Text('İncele'),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              );
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
              Text(item.status.label),
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
