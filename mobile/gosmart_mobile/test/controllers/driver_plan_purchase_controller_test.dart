import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_plan_purchase_controller.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';

void main() {
  test('plan selection resets prepared state and request identity', () async {
    var requestCounter = 0;
    final gateway = _Gateway();
    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-${++requestCounter}',
    );
    addTearDown(controller.dispose);

    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();

    expect(controller.prepared?.plan, DriverPassPlan.daily);
    expect(gateway.calls.single.requestId, 'request-1');

    controller.selectPlan(DriverPassPlan.weekly);

    expect(controller.selectedPlan, DriverPassPlan.weekly);
    expect(controller.prepared, isNull);
    expect(controller.errorMessage, isNull);

    await controller.prepare();

    expect(gateway.calls, hasLength(2));
    expect(gateway.calls.last.requestId, 'request-2');
  });

  test('failed retry reuses the same idempotency requestId', () async {
    var requestCounter = 0;
    final gateway = _Gateway()
      ..error = const DriverPlanPurchaseException(code: 'unavailable');

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-${++requestCounter}',
    );
    addTearDown(controller.dispose);

    controller.selectPlan(DriverPassPlan.monthly);
    await controller.prepare();

    expect(controller.errorMessage, isNotNull);
    expect(gateway.calls.single.requestId, 'request-1');

    gateway.error = null;
    await controller.prepare();

    expect(gateway.calls, hasLength(2));
    expect(gateway.calls[1].requestId, 'request-1');
    expect(requestCounter, 1);
    expect(controller.prepared?.plan, DriverPassPlan.monthly);
  });

  test('concurrent second prepare is suppressed', () async {
    final gateway = _Gateway()
      ..deferred = Completer<PreparedDriverPlanPurchase>();

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    controller.selectPlan(DriverPassPlan.daily);

    final first = controller.prepare();
    final second = controller.prepare();

    expect(controller.preparing, isTrue);
    expect(gateway.calls, hasLength(1));

    gateway.deferred!.complete(resultFor(DriverPassPlan.daily));

    await first;
    await second;

    expect(gateway.calls, hasLength(1));
    expect(controller.prepared, isNotNull);
  });

  test('selection cannot change while prepare is in flight', () async {
    final gateway = _Gateway()
      ..deferred = Completer<PreparedDriverPlanPurchase>();

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    controller.selectPlan(DriverPassPlan.daily);
    final operation = controller.prepare();

    controller.selectPlan(DriverPassPlan.quarterly);

    expect(controller.selectedPlan, DriverPassPlan.daily);

    gateway.deferred!.complete(resultFor(DriverPassPlan.daily));
    await operation;
  });

  test('controlled auth errors become safe user messages', () async {
    final gateway = _Gateway()
      ..error = const DriverPlanPurchaseException(
        code: 'unauthenticated',
        reason: 'raw_reason_not_displayed',
      );

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();

    expect(controller.errorMessage, 'Oturumunuzu kontrol edip tekrar deneyin.');
    expect(
      controller.errorMessage,
      isNot(contains('raw_reason_not_displayed')),
    );
  });

  test('unknown gateway errors receive generic safe message', () async {
    final gateway = _Gateway()..error = StateError('RAW_SECRET');

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    controller.selectPlan(DriverPassPlan.weekly);
    await controller.prepare();

    expect(
      controller.errorMessage,
      'Plan talebi hazırlanamadı. Lütfen tekrar deneyin.',
    );
  });

  test(
    'dispose during async completion does not notify after dispose',
    () async {
      final gateway = _Gateway()
        ..deferred = Completer<PreparedDriverPlanPurchase>();

      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-1',
      );

      controller.selectPlan(DriverPassPlan.daily);
      final operation = controller.prepare();

      controller.dispose();

      gateway.deferred!.complete(resultFor(DriverPassPlan.daily));

      await expectLater(operation, completes);
    },
  );
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

  Object? error;
  Completer<PreparedDriverPlanPurchase>? deferred;

  @override
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  }) async {
    calls.add((plan: plan, requestId: requestId));

    final failure = error;
    if (failure != null) {
      throw failure;
    }

    final pending = deferred;
    if (pending != null) {
      return pending.future;
    }

    return resultFor(plan);
  }
}
