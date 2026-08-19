import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_catalog_gateway.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_plan_purchase_controller.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/widgets/driver/driver_plan_purchase_panel.dart';

void main() {
  testWidgets('catalog loads before plan selection is enabled', (tester) async {
    final gateway = _Gateway();
    final completer = Completer<DriverPlanCatalogSnapshot>();
    gateway.catalogCompleter = completer;

    final controller = await _showPanel(tester, gateway);
    addTearDown(controller.dispose);

    expect(
      find.byKey(const ValueKey('driver-plan-catalog-loading')),
      findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNothing);

    completer.complete(catalog());
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(4));
  });

  testWidgets(
    'canonical four plans are visible and server-disabled plan is blocked',
    (tester) async {
      final gateway = _Gateway();
      final controller = await _showPanel(tester, gateway);
      addTearDown(controller.dispose);

      await tester.pumpAndSettle();

      expect(find.text('Günlük'), findsOneWidget);
      expect(find.text('Haftalık'), findsOneWidget);
      expect(find.text('Aylık'), findsOneWidget);
      expect(find.text('3 Aylık'), findsOneWidget);

      final weekly = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('driver-plan-weekly')),
      );

      expect(weekly.onSelected, isNull);

      await tester.tap(find.byKey(const ValueKey('driver-plan-daily')));
      await tester.pump();

      expect(controller.selectedPlan, DriverPassPlan.daily);
    },
  );

  testWidgets('catalog error is explicit and retryable', (tester) async {
    final gateway = _Gateway()..catalogFailures = 1;
    final controller = await _showPanel(tester, gateway);
    addTearDown(controller.dispose);

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driver-plan-catalog-error')),
      findsOneWidget,
    );
    expect(find.text('Planları Tekrar Dene'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('driver-plan-catalog-retry')));
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(4));
    expect(gateway.catalogCalls, 2);
  });

  testWidgets('raw amountMinor and currency are not rendered as price', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = await _showPanel(tester, gateway);
    addTearDown(controller.dispose);

    await tester.pumpAndSettle();

    expect(find.text('1234'), findsNothing);
    expect(find.text('TRY'), findsNothing);
    expect(find.textContaining('12.34'), findsNothing);
  });

  testWidgets('prepare failure remains retryable with existing purchase flow', (
    tester,
  ) async {
    final gateway = _Gateway()..prepareFailures = 1;
    final controller = await _showPanel(tester, gateway);
    addTearDown(controller.dispose);

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('driver-plan-daily')));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('driver-plan-purchase-prepare')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Plan talebi hazırlanamadı. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    expect(find.text('Tekrar Dene'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('driver-plan-purchase-prepare')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driver-plan-purchase-prepared')),
      findsOneWidget,
    );
  });

  testWidgets(
    'prepared state remains pending-only and never claims activation',
    (tester) async {
      final gateway = _Gateway();
      final controller = await _showPanel(tester, gateway);
      addTearDown(controller.dispose);

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('driver-plan-daily')));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('driver-plan-purchase-prepare')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Günlük plan talebi hazırlandı.'), findsOneWidget);
      expect(
        find.text('Ödeme veya paket aktivasyonu henüz tamamlanmadı.'),
        findsOneWidget,
      );
      expect(find.textContaining('aktif edildi'), findsNothing);
    },
  );
}

Future<DriverPlanPurchaseController> _showPanel(
  WidgetTester tester,
  _Gateway gateway,
) async {
  final controller = DriverPlanPurchaseController(
    gateway: gateway,
    requestIdFactory: () => 'request-1',
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DriverPlanPurchasePanel(controller: controller)),
    ),
  );

  return controller;
}

DriverPlanCatalogSnapshot catalog() {
  return const DriverPlanCatalogSnapshot(
    catalogVersion: 'catalog_v1',
    plans: [
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.daily,
        enabled: true,
        amountMinor: 1234,
        currency: 'TRY',
      ),
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.weekly,
        enabled: false,
        amountMinor: 2345,
        currency: 'TRY',
      ),
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.monthly,
        enabled: true,
        amountMinor: 3456,
        currency: 'TRY',
      ),
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.quarterly,
        enabled: true,
        amountMinor: 4567,
        currency: 'TRY',
      ),
    ],
  );
}

class _Gateway implements DriverPlanPurchaseGateway, DriverPlanCatalogGateway {
  int catalogCalls = 0;
  int catalogFailures = 0;
  int prepareFailures = 0;
  Completer<DriverPlanCatalogSnapshot>? catalogCompleter;

  @override
  Future<DriverPlanCatalogSnapshot> load() async {
    catalogCalls++;

    if (catalogFailures > 0) {
      catalogFailures--;
      throw const DriverPlanCatalogException(code: 'unavailable');
    }

    if (catalogCompleter case final completer?) {
      return completer.future;
    }

    return catalog();
  }

  @override
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  }) async {
    if (prepareFailures > 0) {
      prepareFailures--;
      throw const DriverPlanPurchaseException(code: 'unavailable');
    }

    return PreparedDriverPlanPurchase(
      purchaseOperationId: List<String>.filled(64, 'a').join(),
      status: 'pending',
      catalogVersion: 'catalog_v1',
      plan: plan,
      amountMinor: 1234,
      currency: 'TRY',
    );
  }
}
