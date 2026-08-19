import 'package:flutter/material.dart';

import '../../controllers/driver_plan_purchase_controller.dart';
import '../../domain/subscription/driver_pass_plan.dart';

class DriverPlanPurchasePanel extends StatefulWidget {
  const DriverPlanPurchasePanel({super.key, required this.controller});

  final DriverPlanPurchaseController controller;

  @override
  State<DriverPlanPurchasePanel> createState() =>
      _DriverPlanPurchasePanelState();
}

class _DriverPlanPurchasePanelState extends State<DriverPlanPurchasePanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadCatalog();
  }

  @override
  void didUpdateWidget(covariant DriverPlanPurchasePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      widget.controller.loadCatalog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final catalog = controller.catalog;
        final prepared = controller.prepared;

        return Card(
          key: const ValueKey('driver-plan-purchase-panel'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sürücü kontör planı',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Kullanılabilir planlar GoSmart sunucusundan alınır.',
                ),
                const SizedBox(height: 12),
                if (controller.catalogLoading && catalog == null)
                  const Center(
                    child: CircularProgressIndicator(
                      key: ValueKey('driver-plan-catalog-loading'),
                      strokeWidth: 2,
                    ),
                  )
                else if (catalog == null) ...[
                  Text(
                    controller.catalogErrorMessage ??
                        'Plan seçenekleri yüklenemedi.',
                    key: const ValueKey('driver-plan-catalog-error'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('driver-plan-catalog-retry'),
                    onPressed: controller.catalogLoading
                        ? null
                        : controller.loadCatalog,
                    child: const Text('Planları Tekrar Dene'),
                  ),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in catalog.plans)
                        ChoiceChip(
                          key: ValueKey('driver-plan-${entry.plan.name}'),
                          label: Text(entry.plan.displayName),
                          selected: controller.selectedPlan == entry.plan,
                          onSelected:
                              entry.enabled &&
                                  !controller.preparing &&
                                  prepared == null
                              ? (selected) {
                                  if (selected) {
                                    controller.selectPlan(entry.plan);
                                  }
                                }
                              : null,
                        ),
                    ],
                  ),
                  if (catalog.plans.any((entry) => !entry.enabled)) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Kullanılamayan planlar sunucu kataloğuna göre devre dışıdır.',
                      key: ValueKey('driver-plan-catalog-disabled-note'),
                    ),
                  ],
                  if (controller.errorMessage case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      key: const ValueKey('driver-plan-purchase-error'),
                    ),
                  ],
                  if (prepared != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${prepared.plan.displayName} plan talebi hazırlandı.',
                      key: const ValueKey('driver-plan-purchase-prepared'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ödeme veya paket aktivasyonu henüz tamamlanmadı.',
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('driver-plan-purchase-prepare'),
                    onPressed:
                        controller.preparing ||
                            prepared != null ||
                            controller.selectedPlan == null ||
                            !controller.isPlanEnabled(controller.selectedPlan!)
                        ? null
                        : controller.prepare,
                    child: controller.preparing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            prepared != null
                                ? 'Talep Hazırlandı'
                                : controller.errorMessage != null
                                ? 'Tekrar Dene'
                                : 'Talebi Hazırla',
                          ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
