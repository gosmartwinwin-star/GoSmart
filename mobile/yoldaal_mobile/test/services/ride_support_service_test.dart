import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_support_gateway.dart';
import 'package:yoldaal_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:yoldaal_mobile/services/ride_lifecycle_service.dart';
import 'package:yoldaal_mobile/services/ride_support_service.dart';

void main() {
  test('support callable sends exact frozen authoritative payload', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'caseId': 'case_123',
        'category': 'safety',
        'createdAtMillis': 456789,
      };

    final service = RideSupportService(invoker: invoker);

    final result = await service.createCase(
      rideId: 'ride_1',
      category: 'safety',
      requestId: 'support_request_1234567890',
    );

    expect(
      invoker.names,
      [FirebaseFunctionsRegistry.createRideSupportCase],
    );
    expect(
      invoker.payloads,
      [
        {
          'rideId': 'ride_1',
          'category': 'safety',
          'requestId': 'support_request_1234567890',
        },
      ],
    );

    expect(result.rideId, 'ride_1');
    expect(result.caseId, 'case_123');
    expect(result.category, 'safety');
    expect(
      result.createdAt,
      DateTime.fromMillisecondsSinceEpoch(
        456789,
        isUtc: true,
      ),
    );
  });

  test('every frozen support category is accepted locally', () async {
    for (final category in rideSupportCategories) {
      final invoker = _Invoker()
        ..response = {
          'rideId': 'ride_1',
          'caseId': 'case_$category',
          'category': category,
          'createdAtMillis': 1,
        };

      final service = RideSupportService(invoker: invoker);

      final result = await service.createCase(
        rideId: 'ride_1',
        category: category,
        requestId: 'support_request_1234567890',
      );

      expect(result.category, category);
      expect(invoker.payloads.single.keys.toList(), [
        'rideId',
        'category',
        'requestId',
      ]);
    }

    expect(
      rideSupportCategories,
      [
        'safety',
        'behavior',
        'fare',
        'route',
        'pickup',
        'no-show',
        'cancel',
        'vehicle',
        'technical',
        'lost-item',
      ],
    );
  });

  test('same logical retry keeps caller-owned requestId unchanged', () async {
    final invoker = _Invoker()
      ..failuresRemaining = 1
      ..response = {
        'rideId': 'ride_1',
        'caseId': 'case_retry',
        'category': 'route',
        'createdAtMillis': 999,
      };

    final service = RideSupportService(invoker: invoker);
    const stableRequestId = 'support_retry_1234567890';

    await expectLater(
      service.createCase(
        rideId: 'ride_1',
        category: 'route',
        requestId: stableRequestId,
      ),
      throwsA(
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );

    final result = await service.createCase(
      rideId: 'ride_1',
      category: 'route',
      requestId: stableRequestId,
    );

    expect(result.caseId, 'case_retry');
    expect(invoker.payloads, [
      {
        'rideId': 'ride_1',
        'category': 'route',
        'requestId': stableRequestId,
      },
      {
        'rideId': 'ride_1',
        'category': 'route',
        'requestId': stableRequestId,
      },
    ]);
  });

  test('local validation rejects invalid ride category and requestId', () async {
    final service = RideSupportService(invoker: _Invoker());

    expect(
      () => service.createCase(
        rideId: 'ride/invalid',
        category: 'route',
        requestId: 'support_request_1234567890',
      ),
      throwsArgumentError,
    );

    expect(
      () => service.createCase(
        rideId: 'ride_1',
        category: 'invented',
        requestId: 'support_request_1234567890',
      ),
      throwsArgumentError,
    );

    expect(
      () => service.createCase(
        rideId: 'ride_1',
        category: 'route',
        requestId: 'short',
      ),
      throwsArgumentError,
    );
  });

  test('gateway errors propagate unchanged', () async {
    final invoker = _Invoker()
      ..error = const RideGatewayException(
        'failed-precondition',
        reason: 'ride_support_requires_terminal_ride',
      );

    final service = RideSupportService(invoker: invoker);

    await expectLater(
      service.createCase(
        rideId: 'ride_1',
        category: 'fare',
        requestId: 'support_request_1234567890',
      ),
      throwsA(
        isA<RideGatewayException>()
            .having(
              (error) => error.code,
              'code',
              'failed-precondition',
            )
            .having(
              (error) => error.reason,
              'reason',
              'ride_support_requires_terminal_ride',
            ),
      ),
    );
  });

  test('active support uses separate callable with exact frozen payload', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'caseId': 'active_case_123',
        'category': 'route',
        'createdAtMillis': 789123,
      };

    final service = RideSupportService(invoker: invoker);

    final result = await service.createActiveCase(
      rideId: 'ride_1',
      category: 'route',
      requestId: 'active_support_request_1234567890',
    );

    expect(
      invoker.names,
      [FirebaseFunctionsRegistry.createActiveRideSupportCase],
    );
    expect(
      invoker.payloads,
      [
        {
          'rideId': 'ride_1',
          'category': 'route',
          'requestId': 'active_support_request_1234567890',
        },
      ],
    );
    expect(result.rideId, 'ride_1');
    expect(result.caseId, 'active_case_123');
    expect(result.category, 'route');
    expect(
      result.createdAt,
      DateTime.fromMillisecondsSinceEpoch(
        789123,
        isUtc: true,
      ),
    );
  });

  test('malformed or expanded support response fails closed', () async {
    for (final response in <Map<String, dynamic>>[
      {
        'rideId': 'other_ride',
        'caseId': 'case_1',
        'category': 'safety',
        'createdAtMillis': 1,
      },
      {
        'rideId': 'ride_1',
        'caseId': '',
        'category': 'safety',
        'createdAtMillis': 1,
      },
      {
        'rideId': 'ride_1',
        'caseId': 'case_1',
        'category': 'vehicle',
        'createdAtMillis': 1,
      },
      {
        'rideId': 'ride_1',
        'caseId': 'case_1',
        'category': 'safety',
        'createdAtMillis': -1,
      },
      {
        'rideId': 'ride_1',
        'caseId': 'case_1',
        'category': 'safety',
        'createdAtMillis': 1,
        'reporterId': 'must-not-leak',
      },
    ]) {
      final invoker = _Invoker()..response = response;
      final service = RideSupportService(invoker: invoker);

      await expectLater(
        service.createCase(
          rideId: 'ride_1',
          category: 'safety',
          requestId: 'support_request_1234567890',
        ),
        throwsA(
          isA<RideGatewayException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    }
  });
}

class _Invoker implements RideCallableInvoker {
  final names = <String>[];
  final payloads = <Map<String, dynamic>>[];

  Map<String, dynamic> response = const {};
  RideGatewayException? error;
  int failuresRemaining = 0;

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    names.add(name);
    payloads.add(Map<String, dynamic>.from(payload));

    if (error case final value?) {
      throw value;
    }

    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const RideGatewayException('unavailable');
    }

    return Map<String, dynamic>.from(response);
  }
}
