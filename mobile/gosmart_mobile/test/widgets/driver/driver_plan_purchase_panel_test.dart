import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_plan_purchase_controller.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/widgets/driver/driver_plan_purchase_panel.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    DriverPlanPurchaseController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DriverPlanPurchasePanel(controller: controller)),
      ),
    );
  }

  testWidgets('canonical four plans are visible and selectable', (
    tester,
  ) async {
    final controller = DriverPlanPurchaseController(
      gateway: _Gateway(),
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await show(tester, controller);

    for (final label in ['Günlük', 'Haftalık', 'Aylık', '3 Aylık']) {
      expect(find.text(label), findsOneWidget);
    }

    final initialButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('driver-plan-purchase-prepare')),
    );
    expect(initialButton.onPressed, isNull);

    await tester.tap(find.text('Haftalık'));
    await tester.pump();

    expect(controller.selectedPlan, DriverPassPlan.weekly);

    final selected = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('driver-plan-weekly')),
    );
    expect(selected.selected, isTrue);
  });

  testWidgets('successful prepare is pending-only, not entitlement success', (
    tester,
  ) async {
    final controller = DriverPlanPurchaseController(
      gateway: _Gateway(),
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await show(tester, controller);

    await tester.tap(find.text('Günlük'));
    await tester.pump();
    await tester.tap(find.text('Talebi Hazırla'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driver-plan-purchase-prepared')),
      findsOneWidget,
    );
    expect(
      find.text('Ödeme veya paket aktivasyonu henüz tamamlanmadı.'),
      findsOneWidget,
    );
    expect(find.textContaining('Ödeme başarılı'), findsNothing);
    expect(find.textContaining('Paket aktif'), findsNothing);
  });

  testWidgets('in-flight prepare disables user mutation', (tester) async {
    final gateway = _Gateway()
      ..deferred = Completer<PreparedDriverPlanPurchase>();

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await show(tester, controller);

    await tester.tap(find.text('Aylık'));
    await tester.pump();
    await tester.tap(find.text('Talebi Hazırla'));
    await tester.pump();

    expect(controller.preparing, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('driver-plan-purchase-prepare')),
    );
    expect(button.onPressed, isNull);

    gateway.deferred!.complete(resultFor(DriverPassPlan.monthly));
    await tester.pumpAndSettle();

    expect(controller.prepared?.plan, DriverPassPlan.monthly);
  });

  testWidgets('safe failure can retry with the same operation identity', (
    tester,
  ) async {
    final gateway = _Gateway()..failuresRemaining = 1;

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'stable-request',
    );
    addTearDown(controller.dispose);

    await show(tester, controller);

    await tester.tap(find.text('3 Aylık'));
    await tester.pump();
    await tester.tap(find.text('Talebi Hazırla'));
    await tester.pumpAndSettle();

    expect(
      find.text('Plan talebi hazırlanamadı. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    expect(find.text('Tekrar Dene'), findsOneWidget);

    await tester.tap(find.text('Tekrar Dene'));
    await tester.pumpAndSettle();

    expect(gateway.calls, hasLength(2));
    expect(gateway.calls[0].requestId, 'stable-request');
    expect(gateway.calls[1].requestId, 'stable-request');
    expect(
      find.byKey(const ValueKey('driver-plan-purchase-prepared')),
      findsOneWidget,
    );
  });
}

PreparedDriverPlanPurchase resultFor(DriverPassPlan plan) {
  return PreparedDriverPlanPurchase(
    purchaseOperationId: List<String>.filled(64, 'a').join(),
    status: 'pending',
    catalogVersion: 'catalog_v1',
    plan: plan,
    amountMinor: 1234,
    currency: 'EUR',
  );
}

class _Gateway implements DriverPlanPurchaseGateway {
  final List<({DriverPassPlan plan, String requestId})> calls = [];

  int failuresRemaining = 0;
  Completer<PreparedDriverPlanPurchase>? deferred;

  @override
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  }) async {
    calls.add((plan: plan, requestId: requestId));

    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const DriverPlanPurchaseException(code: 'unavailable');
    }

    final pending = deferred;
    if (pending != null) {
      return pending.future;
    }

    return resultFor(plan);
  }
}
