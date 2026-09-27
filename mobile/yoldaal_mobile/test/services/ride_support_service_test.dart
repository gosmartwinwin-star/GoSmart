import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_support_gateway.dart';
import 'package:yoldaal_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:yoldaal_mobile/services/ride_lifecycle_service.dart';
import 'package:yoldaal_mobile/services/ride_support_service.dart';

void main() {
  test('legacy support payload remains exact and note-free', () async {
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

    expect(invoker.names, [FirebaseFunctionsRegistry.createRideSupportCase]);
    expect(invoker.payloads, [
      {
        'rideId': 'ride_1',
        'category': 'safety',
        'requestId': 'support_request_1234567890',
      },
    ]);
    expect(result.caseId, 'case_123');
  });

  test(
    'optional note is normalized and included only when non-empty',
    () async {
      final invoker = _Invoker()
        ..response = {
          'rideId': 'ride_1',
          'caseId': 'case_note',
          'category': 'technical',
          'createdAtMillis': 2,
        };

      final service = RideSupportService(invoker: invoker);

      await service.createCase(
        rideId: 'ride_1',
        category: 'technical',
        requestId: 'support_note_1234567890',
        note: '  Uygulama ekrani dondu.  ',
      );

      expect(invoker.payloads.single, {
        'rideId': 'ride_1',
        'category': 'technical',
        'requestId': 'support_note_1234567890',
        'note': 'Uygulama ekrani dondu.',
      });

      final blankInvoker = _Invoker()
        ..response = {
          'rideId': 'ride_1',
          'caseId': 'case_blank',
          'category': 'technical',
          'createdAtMillis': 3,
        };

      await RideSupportService(invoker: blankInvoker).createCase(
        rideId: 'ride_1',
        category: 'technical',
        requestId: 'support_blank_1234567890',
        note: '   ',
      );

      expect(blankInvoker.payloads.single.keys.toList(), [
        'rideId',
        'category',
        'requestId',
      ]);
    },
  );

  test('canonical categories stay compatible while UI exposes five', () {
    expect(rideSupportCategories, [
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
    ]);

    expect(rideSupportUiCategories, [
      'safety',
      'behavior',
      'route',
      'technical',
      'lost-item',
    ]);

    expect(rideSupportCategoryLabel('safety'), 'G\u00FCvenlik');
    expect(rideSupportCategoryLabel('lost-item'), 'Unutulan e\u015Fya');
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
        note: 'Ayni aciklama',
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
      note: 'Ayni aciklama',
    );

    expect(result.caseId, 'case_retry');
    expect(invoker.payloads, [
      {
        'rideId': 'ride_1',
        'category': 'route',
        'requestId': stableRequestId,
        'note': 'Ayni aciklama',
      },
      {
        'rideId': 'ride_1',
        'category': 'route',
        'requestId': stableRequestId,
        'note': 'Ayni aciklama',
      },
    ]);
  });

  test('local validation rejects invalid fields and oversized note', () async {
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

    expect(
      () => service.createCase(
        rideId: 'ride_1',
        category: 'route',
        requestId: 'support_request_1234567890',
        note: List.filled(rideSupportNoteMaxCodePoints + 1, 'a').join(),
      ),
      throwsArgumentError,
    );

    expect(
      () => normalizeRideSupportNote('bad\u0000note'),
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
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.reason,
              'reason',
              'ride_support_requires_terminal_ride',
            ),
      ),
    );
  });

  test('active support sends normalized optional note', () async {
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
      note: '  Kisa rota aciklamasi  ',
    );

    expect(invoker.names, [
      FirebaseFunctionsRegistry.createActiveRideSupportCase,
    ]);
    expect(invoker.payloads, [
      {
        'rideId': 'ride_1',
        'category': 'route',
        'requestId': 'active_support_request_1234567890',
        'note': 'Kisa rota aciklamasi',
      },
    ]);
    expect(result.caseId, 'active_case_123');
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
        'reporterNote': 'must-not-leak',
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
