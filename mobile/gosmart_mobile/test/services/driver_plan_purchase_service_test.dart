import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/services/driver_plan_purchase_service.dart';

void main() {
  test('canonical four plans use exact callable and minimal payload', () async {
    final caller = _Caller();
    final service = DriverPlanPurchaseService(caller: caller.call);

    for (final plan in DriverPassPlan.values) {
      caller.response = responseFor(plan);

      final result = await service.prepare(
        plan: plan,
        requestId: 'request-${plan.name}',
      );

      expect(caller.calls, hasLength(1));
      expect(caller.calls.single.name, 'prepareDriverPlanPurchase');
      expect(caller.calls.single.payload, {
        'planId': plan.name,
        'requestId': 'request-${plan.name}',
      });

      for (final forbidden in [
        'driverId',
        'amountMinor',
        'currency',
        'catalogVersion',
        'status',
        'passId',
        'paymentSettlementId',
      ]) {
        expect(caller.calls.single.payload.containsKey(forbidden), isFalse);
      }

      expect(result.plan, plan);
      expect(result.status, 'pending');

      caller.calls.clear();
    }
  });

  test('server snapshot is parsed without client price authority', () async {
    final caller = _Caller()
      ..response = responseFor(
        DriverPassPlan.monthly,
        amountMinor: 3456,
        currency: 'EUR',
        catalogVersion: 'catalog_v2',
      );

    final result = await DriverPlanPurchaseService(
      caller: caller.call,
    ).prepare(plan: DriverPassPlan.monthly, requestId: 'request-monthly');

    expect(result.purchaseOperationId, List<String>.filled(64, 'a').join());
    expect(result.catalogVersion, 'catalog_v2');
    expect(result.amountMinor, 3456);
    expect(result.currency, 'EUR');
  });

  test('malformed callable responses fail closed', () async {
    final invalidResponses = <Object?>[
      null,
      'broken',
      {...responseFor(DriverPassPlan.daily), 'status': 'settled'},
      {...responseFor(DriverPassPlan.daily), 'planId': 'unknown'},
      {...responseFor(DriverPassPlan.daily), 'amountMinor': -1},
      {...responseFor(DriverPassPlan.daily), 'currency': 'eur'},
      {...responseFor(DriverPassPlan.daily), 'purchaseOperationId': 'short'},
    ];

    for (final response in invalidResponses) {
      final caller = _Caller()..response = response;

      await expectLater(
        DriverPlanPurchaseService(
          caller: caller.call,
        ).prepare(plan: DriverPassPlan.daily, requestId: 'request'),
        throwsA(
          isA<DriverPlanPurchaseException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    }
  });

  test('response plan must match the requested plan', () async {
    final caller = _Caller()..response = responseFor(DriverPassPlan.weekly);

    await expectLater(
      DriverPlanPurchaseService(
        caller: caller.call,
      ).prepare(plan: DriverPassPlan.daily, requestId: 'request'),
      throwsA(
        isA<DriverPlanPurchaseException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('controlled Functions code and safe reason are preserved', () async {
    final caller = _Caller()
      ..error = _TestFunctionsException(
        code: 'failed-precondition',
        details: {'reason': 'driver_plan_disabled', 'raw': 'must-not-surface'},
        message: 'RAW_BACKEND_MESSAGE',
      );

    await expectLater(
      DriverPlanPurchaseService(
        caller: caller.call,
      ).prepare(plan: DriverPassPlan.daily, requestId: 'request'),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having((error) => error.reason, 'reason', 'driver_plan_disabled'),
      ),
    );
  });

  test('malformed Functions reason is discarded', () async {
    final caller = _Caller()
      ..error = _TestFunctionsException(
        code: 'internal',
        details: {'reason': 'RAW SECRET DETAIL'},
      );

    await expectLater(
      DriverPlanPurchaseService(
        caller: caller.call,
      ).prepare(plan: DriverPassPlan.daily, requestId: 'request'),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'internal')
            .having((error) => error.reason, 'reason', isNull),
      ),
    );
  });

  test('unexpected client failure becomes unavailable', () async {
    final caller = _Caller()..error = StateError('RAW_SOCKET_SECRET');

    await expectLater(
      DriverPlanPurchaseService(
        caller: caller.call,
      ).prepare(plan: DriverPassPlan.daily, requestId: 'request'),
      throwsA(
        isA<DriverPlanPurchaseException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });

  test('mobile production service does not expose settlement callable', () {
    final source = File(
      'lib/services/driver_plan_purchase_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('settleDriverPlanPurchase')));
  });
}

Map<String, Object?> responseFor(
  DriverPassPlan plan, {
  int amountMinor = 1234,
  String currency = 'EUR',
  String catalogVersion = 'catalog_v1',
}) {
  return {
    'purchaseOperationId': List<String>.filled(64, 'a').join(),
    'status': 'pending',
    'catalogVersion': catalogVersion,
    'planId': plan.name,
    'amountMinor': amountMinor,
    'currency': currency,
  };
}

class _Caller {
  Object? response;
  Object? error;

  final List<({String name, Map<String, Object?> payload})> calls = [];

  Future<Object?> call(String name, Map<String, Object?> payload) async {
    calls.add((name: name, payload: Map<String, Object?>.from(payload)));

    final failure = error;
    if (failure != null) {
      throw failure;
    }

    return response;
  }
}

class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException({
    required super.code,
    super.details,
    super.message = 'safe test failure',
  });
}
