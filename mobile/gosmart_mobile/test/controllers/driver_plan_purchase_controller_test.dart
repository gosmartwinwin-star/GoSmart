import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_catalog_gateway.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_plan_purchase_controller.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';

void main() {
  test('catalog load exposes canonical server availability', () async {
    final gateway = _Gateway();
    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();

    expect(controller.catalogLoading, isFalse);
    expect(controller.catalogErrorMessage, isNull);
    expect(
      controller.catalog!.plans.map((entry) => entry.plan).toList(),
      DriverPassPlan.values,
    );
    expect(controller.isPlanEnabled(DriverPassPlan.daily), isTrue);
    expect(controller.isPlanEnabled(DriverPassPlan.weekly), isFalse);
  });

  test('concurrent catalog loads are suppressed', () async {
    final gateway = _Gateway();
    final completer = Completer<DriverPlanCatalogSnapshot>();
    gateway.catalogCompleter = completer;

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    final first = controller.loadCatalog();
    final second = controller.loadCatalog();

    expect(gateway.catalogCalls, 1);

    completer.complete(catalog());
    await Future.wait([first, second]);

    expect(controller.catalog, isNotNull);
  });

  test('catalog failure is safe and retryable', () async {
    final gateway = _Gateway()..catalogFailures = 1;

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.loadCatalog();

    expect(controller.catalog, isNull);
    expect(
      controller.catalogErrorMessage,
      'Plan seçenekleri yüklenemedi. Lütfen tekrar deneyin.',
    );

    await controller.loadCatalog();

    expect(gateway.catalogCalls, 2);
    expect(controller.catalog, isNotNull);
    expect(controller.catalogErrorMessage, isNull);
  });

  test('disabled plan cannot be selected while enabled plan can', () async {
    final gateway = _Gateway();

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.loadCatalog();

    controller.selectPlan(DriverPassPlan.weekly);
    expect(controller.selectedPlan, isNull);

    controller.selectPlan(DriverPassPlan.daily);
    expect(controller.selectedPlan, DriverPassPlan.daily);
  });

  test('catalog reload clears selection when plan becomes disabled', () async {
    final gateway = _Gateway();

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);

    gateway.catalogValue = catalog(version: 'catalog_v2', dailyEnabled: false);

    await controller.loadCatalog();

    expect(controller.selectedPlan, isNull);
    expect(controller.requestId, isNull);
    expect(controller.catalog!.catalogVersion, 'catalog_v2');
  });

  test('plan selection resets prepared state and request identity', () async {
    final gateway = _Gateway();

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();

    expect(controller.prepared, isNotNull);
    expect(controller.requestId, 'request-1');

    controller.selectPlan(DriverPassPlan.monthly);

    expect(controller.selectedPlan, DriverPassPlan.monthly);
    expect(controller.prepared, isNull);
    expect(controller.requestId, isNull);
  });

  test('failed retry reuses the same idempotency requestId', () async {
    final gateway = _Gateway()..prepareFailures = 1;
    var generated = 0;

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-${++generated}',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);

    await controller.prepare();
    await controller.prepare();

    expect(gateway.prepareRequestIds, ['request-1', 'request-1']);
    expect(controller.prepared, isNotNull);
  });

  test('selection cannot change while prepare is in flight', () async {
    final gateway = _Gateway();
    final completer = Completer<PreparedDriverPlanPurchase>();
    gateway.prepareCompleter = completer;

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);

    final future = controller.prepare();

    controller.selectPlan(DriverPassPlan.monthly);

    expect(controller.selectedPlan, DriverPassPlan.daily);
    expect(gateway.prepareCalls, 1);

    completer.complete(prepared(DriverPassPlan.daily));
    await future;
  });

  test('controlled auth errors become safe user messages', () async {
    final gateway = _Gateway()
      ..catalogError = const DriverPlanCatalogException(
        code: 'unauthenticated',
        reason: 'raw_secret_reason',
      );

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.loadCatalog();

    expect(
      controller.catalogErrorMessage,
      'Oturumunuzu kontrol edip tekrar deneyin.',
    );
    expect(
      controller.catalogErrorMessage,
      isNot(contains('raw_secret_reason')),
    );
  });

  test(
    'unknown purchase gateway errors receive generic safe message',
    () async {
      final gateway = _Gateway()..unexpectedPrepareFailure = true;

      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-1',
      );
      addTearDown(controller.dispose);

      await controller.loadCatalog();
      controller.selectPlan(DriverPassPlan.daily);
      await controller.prepare();

      expect(
        controller.errorMessage,
        'Plan talebi hazırlanamadı. Lütfen tekrar deneyin.',
      );
      expect(controller.errorMessage, isNot(contains('socket secret')));
    },
  );

  test(
    'dispose during async catalog completion does not notify after dispose',
    () async {
      final gateway = _Gateway();
      final completer = Completer<DriverPlanCatalogSnapshot>();
      gateway.catalogCompleter = completer;

      final controller = DriverPlanPurchaseController(gateway: gateway);

      final future = controller.loadCatalog();
      controller.dispose();

      completer.complete(catalog());

      await future;
    },
  );
}

DriverPlanCatalogSnapshot catalog({
  String version = 'catalog_v1',
  bool dailyEnabled = true,
}) {
  return DriverPlanCatalogSnapshot(
    catalogVersion: version,
    plans: [
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.daily,
        enabled: dailyEnabled,
        amountMinor: 0,
        currency: 'TRY',
      ),
      const DriverPlanCatalogEntry(
        plan: DriverPassPlan.weekly,
        enabled: false,
        amountMinor: 200,
        currency: 'TRY',
      ),
      const DriverPlanCatalogEntry(
        plan: DriverPassPlan.monthly,
        enabled: true,
        amountMinor: 300,
        currency: 'TRY',
      ),
      const DriverPlanCatalogEntry(
        plan: DriverPassPlan.quarterly,
        enabled: true,
        amountMinor: 400,
        currency: 'TRY',
      ),
    ],
  );
}

PreparedDriverPlanPurchase prepared(DriverPassPlan plan) {
  return PreparedDriverPlanPurchase(
    purchaseOperationId: List<String>.filled(64, 'a').join(),
    status: 'pending',
    catalogVersion: 'catalog_v1',
    plan: plan,
    amountMinor: 1234,
    currency: 'EUR',
  );
}

class _Gateway implements DriverPlanPurchaseGateway, DriverPlanCatalogGateway {
  DriverPlanCatalogSnapshot catalogValue = catalog();
  int catalogFailures = 0;
  DriverPlanCatalogException? catalogError;
  Completer<DriverPlanCatalogSnapshot>? catalogCompleter;
  int catalogCalls = 0;

  int prepareFailures = 0;
  bool unexpectedPrepareFailure = false;
  Completer<PreparedDriverPlanPurchase>? prepareCompleter;
  int prepareCalls = 0;
  final List<String> prepareRequestIds = [];

  @override
  Future<DriverPlanCatalogSnapshot> load() async {
    catalogCalls++;

    if (catalogError case final error?) {
      throw error;
    }

    if (catalogFailures > 0) {
      catalogFailures--;
      throw const DriverPlanCatalogException(code: 'unavailable');
    }

    if (catalogCompleter case final completer?) {
      return completer.future;
    }

    return catalogValue;
  }

  @override
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  }) async {
    prepareCalls++;
    prepareRequestIds.add(requestId);

    if (unexpectedPrepareFailure) {
      throw StateError('socket secret');
    }

    if (prepareFailures > 0) {
      prepareFailures--;
      throw const DriverPlanPurchaseException(code: 'unavailable');
    }

    if (prepareCompleter case final completer?) {
      return completer.future;
    }

    return prepared(plan);
  }
}
