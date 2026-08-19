import 'package:flutter/material.dart';

import '../../controllers/driver_plan_purchase_controller.dart';
import '../../domain/subscription/driver_pass_plan.dart';

class DriverPlanPurchasePanel extends StatelessWidget {
  const DriverPlanPurchasePanel({super.key, required this.controller});

  final DriverPlanPurchaseController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final prepared = controller.prepared;

        return Card(
          key: const ValueKey('driver-plan-purchase-panel'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Kontör Planı Seç',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sunucu plan kataloğundaki kanonik seçeneklerden birini seçin.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final plan in DriverPassPlan.values)
                      ChoiceChip(
                        key: ValueKey('driver-plan-${plan.name}'),
                        label: Text(plan.displayName),
                        selected: controller.selectedPlan == plan,
                        onSelected: controller.preparing || prepared != null
                            ? null
                            : (selected) {
                                if (selected) {
                                  controller.selectPlan(plan);
                                }
                              },
                      ),
                  ],
                ),
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
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('driver-plan-purchase-prepare'),
                  onPressed: controller.canPrepare
                      ? () async {
                          await controller.prepare();
                        }
                      : null,
                  child: controller.preparing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
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
            ),
          ),
        );
      },
    );
  }
}
