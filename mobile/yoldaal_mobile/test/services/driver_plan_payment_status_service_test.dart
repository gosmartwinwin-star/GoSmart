import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:yoldaal_mobile/services/driver_plan_purchase_service.dart';

const operationId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('status uses exact callable and one-key request', () async {
    final caller = _Caller()..response = statusResponse('pending');

    final status = await DriverPlanPurchaseService(
      caller: caller.call,
    ).getPaymentStatus(purchaseOperationId: operationId);

    expect(caller.calls, hasLength(1));
    expect(
      caller.calls.single.name,
      DriverPlanPurchaseService.paymentStatusCallableName,
    );
    expect(caller.calls.single.payload, <String, Object?>{
      'purchaseOperationId': operationId,
    });
    expect(status.purchaseOperationId, operationId);
    expect(status.outcome, DriverPlanPaymentOutcome.pending);
  });

  for (final mapping in <String, DriverPlanPaymentOutcome>{
    'pending': DriverPlanPaymentOutcome.pending,
    'payment_failed': DriverPlanPaymentOutcome.paymentFailed,
    'payment_review': DriverPlanPaymentOutcome.paymentReview,
    'settled': DriverPlanPaymentOutcome.settled,
  }.entries) {
    test('status maps ${mapping.key} authoritatively', () async {
      final service = DriverPlanPurchaseService(
        caller: (_, _) async => statusResponse(mapping.key),
      );

      final result = await service.getPaymentStatus(
        purchaseOperationId: operationId,
      );

      expect(result.purchaseOperationId, operationId);
      expect(result.outcome, mapping.value);
    });
  }

  test(
    'status rejects malformed request operation id before callable',
    () async {
      final caller = _Caller()..response = statusResponse('pending');

      final service = DriverPlanPurchaseService(caller: caller.call);

      await expectLater(
        service.getPaymentStatus(purchaseOperationId: 'NOT_CANONICAL'),
        throwsA(
          isA<DriverPlanPurchaseException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );

      expect(caller.calls, isEmpty);
    },
  );

  test('status response operation id must match request', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => <String, Object?>{
        'purchaseOperationId':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'paymentOutcome': 'pending',
      },
    );

    await expectInvalidResponse(service);
  });

  test('status extra response key fails closed', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => <String, Object?>{
        ...statusResponse('pending'),
        'unexpected': true,
      },
    );

    await expectInvalidResponse(service);
  });

  test('status missing response key fails closed', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => <String, Object?>{
        'purchaseOperationId': operationId,
      },
    );

    await expectInvalidResponse(service);
  });

  for (final invalidOutcome in <Object?>['unknown', '', 1, null]) {
    test('status malformed outcome $invalidOutcome fails closed', () async {
      final service = DriverPlanPurchaseService(
        caller: (_, _) async => <String, Object?>{
          'purchaseOperationId': operationId,
          'paymentOutcome': invalidOutcome,
        },
      );

      await expectInvalidResponse(service);
    });
  }

  test('status malformed operation id fails closed', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => <String, Object?>{
        'purchaseOperationId': 'NOT_CANONICAL',
        'paymentOutcome': 'pending',
      },
    );

    await expectInvalidResponse(service);
  });

  for (final malformed in <Object?>[null, 'not-a-map', <Object?>[]]) {
    test('status malformed response shape fails closed', () async {
      final service = DriverPlanPurchaseService(
        caller: (_, _) async => malformed,
      );

      await expectInvalidResponse(service);
    });
  }

  test('status preserves safe Firebase code and reason', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => throw _TestFunctionsException(
        code: 'not-found',
        details: <String, Object?>{
          'reason': 'purchase_operation_not_found',
          'raw': 'must-not-surface',
        },
      ),
    );

    await expectLater(
      service.getPaymentStatus(purchaseOperationId: operationId),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'not-found')
            .having(
              (error) => error.reason,
              'reason',
              'purchase_operation_not_found',
            ),
      ),
    );
  });

  test('status sanitizes unknown Firebase code and raw reason', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => throw _TestFunctionsException(
        code: 'secret-provider-code',
        details: <String, Object?>{'reason': 'RAW SECRET DETAIL'},
      ),
    );

    await expectLater(
      service.getPaymentStatus(purchaseOperationId: operationId),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'unavailable')
            .having((error) => error.reason, 'reason', isNull),
      ),
    );
  });

  test('unexpected status client failure becomes unavailable', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => throw StateError('RAW_SOCKET_SECRET'),
    );

    await expectLater(
      service.getPaymentStatus(purchaseOperationId: operationId),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'unavailable')
            .having((error) => error.reason, 'reason', isNull),
      ),
    );
  });

  test('recovery uses exact callable and empty request', () async {
    final caller = _Caller()
      ..response = recoveryResponse(statusResponse('pending'));

    final status = await DriverPlanPurchaseService(
      caller: caller.call,
    ).getLatestPaymentStatus();

    expect(caller.calls, hasLength(1));
    expect(
      caller.calls.single.name,
      DriverPlanPurchaseService.paymentStatusRecoveryCallableName,
    );
    expect(caller.calls.single.payload, isEmpty);
    expect(status, isNotNull);
    expect(status!.purchaseOperationId, operationId);
    expect(status.outcome, DriverPlanPaymentOutcome.pending);
  });

  test('recovery accepts null payment status', () async {
    final caller = _Caller()..response = recoveryResponse(null);

    final result = await DriverPlanPurchaseService(
      caller: caller.call,
    ).getLatestPaymentStatus();

    expect(caller.calls, hasLength(1));
    expect(result, isNull);
  });

  test('recovery maps pending authoritatively', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => recoveryResponse(statusResponse('pending')),
    );

    final result = await service.getLatestPaymentStatus();

    expect(result?.purchaseOperationId, operationId);
    expect(result?.outcome, DriverPlanPaymentOutcome.pending);
  });

  test('recovery maps payment_review authoritatively', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async =>
          recoveryResponse(statusResponse('payment_review')),
    );

    final result = await service.getLatestPaymentStatus();

    expect(result?.purchaseOperationId, operationId);
    expect(result?.outcome, DriverPlanPaymentOutcome.paymentReview);
  });

  test('recovery maps payment_failed authoritatively', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async =>
          recoveryResponse(statusResponse('payment_failed')),
    );

    final result = await service.getLatestPaymentStatus();

    expect(result?.purchaseOperationId, operationId);
    expect(result?.outcome, DriverPlanPaymentOutcome.paymentFailed);
  });

  test('recovery maps settled authoritatively', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => recoveryResponse(statusResponse('settled')),
    );

    final result = await service.getLatestPaymentStatus();

    expect(result?.purchaseOperationId, operationId);
    expect(result?.outcome, DriverPlanPaymentOutcome.settled);
  });

  test('recovery outer response shape fails closed', () async {
    final missing = DriverPlanPurchaseService(
      caller: (_, _) async => <String, Object?>{},
    );

    await expectInvalidRecoveryResponse(missing);

    final extra = DriverPlanPurchaseService(
      caller: (_, _) async => <String, Object?>{
        'paymentStatus': statusResponse('pending'),
        'unexpected': true,
      },
    );

    await expectInvalidRecoveryResponse(extra);
  });

  test('recovery malformed operation id fails closed', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => recoveryResponse(<String, Object?>{
        'purchaseOperationId': 'NOT_CANONICAL',
        'paymentOutcome': 'pending',
      }),
    );

    await expectInvalidRecoveryResponse(service);
  });

  test('recovery malformed outcomes fail closed', () async {
    for (final outcome in <Object?>['unknown', '', 1, null]) {
      final service = DriverPlanPurchaseService(
        caller: (_, _) async => recoveryResponse(<String, Object?>{
          'purchaseOperationId': operationId,
          'paymentOutcome': outcome,
        }),
      );

      await expectInvalidRecoveryResponse(service);
    }
  });

  test('recovery Firebase errors are sanitized', () async {
    final safe = DriverPlanPurchaseService(
      caller: (_, _) async => throw _TestFunctionsException(
        code: 'not-found',
        details: <String, Object?>{
          'reason': 'purchase_operation_not_found',
          'raw': 'must-not-surface',
        },
      ),
    );

    await expectLater(
      safe.getLatestPaymentStatus(),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'not-found')
            .having(
              (error) => error.reason,
              'reason',
              'purchase_operation_not_found',
            ),
      ),
    );

    final unsafe = DriverPlanPurchaseService(
      caller: (_, _) async => throw _TestFunctionsException(
        code: 'secret-provider-code',
        details: <String, Object?>{'reason': 'RAW SECRET DETAIL'},
      ),
    );

    await expectLater(
      unsafe.getLatestPaymentStatus(),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'unavailable')
            .having((error) => error.reason, 'reason', isNull),
      ),
    );
  });

  test('unexpected recovery client failure becomes unavailable', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => throw StateError('RAW_RECOVERY_SECRET'),
    );

    await expectLater(
      service.getLatestPaymentStatus(),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'unavailable')
            .having((error) => error.reason, 'reason', isNull),
      ),
    );
  });

  test('production recovery client has read-only safe surface', () {
    final source = File(
      'lib/services/driver_plan_purchase_service.dart',
    ).readAsStringSync();

    final recoveryStart = source.indexOf(
      'Future<DriverPlanPaymentStatus?> getLatestPaymentStatus() async',
    );
    final statusParserStart = source.indexOf(
      'DriverPlanPaymentStatus _parsePaymentStatusResponse(',
    );

    expect(recoveryStart, greaterThanOrEqualTo(0));
    expect(statusParserStart, greaterThan(recoveryStart));

    final recoverySurface = source.substring(
      recoveryStart,
      statusParserStart,
    );

    expect(recoverySurface, isNot(contains('paymentPageUrl')));
    expect(recoverySurface, isNot(contains('conversationId')));
    expect(recoverySurface, isNot(contains('checkoutToken')));
    expect(recoverySurface, isNot(contains('provider')));
    expect(recoverySurface, isNot(contains('FirebaseFirestore')));
    expect(recoverySurface, isNot(contains('settleDriverPlanPurchase')));
    expect(
      recoverySurface,
      isNot(contains('driverPlanPaymentSettlements')),
    );
    expect(recoverySurface, isNot(contains('driverAccessPasses')));
  });

  test('production status client exposes no settlement or pass authority', () {
    final source = File(
      'lib/services/driver_plan_purchase_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('settleDriverPlanPurchase')));
    expect(source, isNot(contains('driverPlanPaymentSettlements')));
    expect(source, isNot(contains('driverAccessPasses')));
  });
}

Map<String, Object?> statusResponse(String outcome) => <String, Object?>{
  'purchaseOperationId': operationId,
  'paymentOutcome': outcome,
};

Map<String, Object?> recoveryResponse(Object? paymentStatus) =>
    <String, Object?>{'paymentStatus': paymentStatus};

Future<void> expectInvalidRecoveryResponse(
  DriverPlanPurchaseService service,
) async {
  await expectLater(
    service.getLatestPaymentStatus(),
    throwsA(
      isA<DriverPlanPurchaseException>().having(
        (error) => error.code,
        'code',
        'invalid-response',
      ),
    ),
  );
}

Future<void> expectInvalidResponse(DriverPlanPurchaseService service) async {
  await expectLater(
    service.getPaymentStatus(purchaseOperationId: operationId),
    throwsA(
      isA<DriverPlanPurchaseException>().having(
        (error) => error.code,
        'code',
        'invalid-response',
      ),
    ),
  );
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
  _TestFunctionsException({required super.code, super.details})
    : super(message: 'safe test failure');
}
