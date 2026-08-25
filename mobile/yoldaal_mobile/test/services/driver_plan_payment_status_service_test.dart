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
