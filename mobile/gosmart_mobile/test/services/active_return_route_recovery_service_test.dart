import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_status.dart';
import 'package:gosmart_mobile/services/active_return_route_recovery_service.dart';

void main() {
  const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
  const createdAt = 1_800_000_000_000;
  const activatedAt = createdAt + 1_000;
  const expiresAt = activatedAt + 3_600_000;

  Map<String, Object?> route() => {
    'routeId': 'route-1',
    'driverId': 'driver-1',
    'status': 'active',
    'origin': {'latitude': 41.0, 'longitude': 29.0},
    'destination': {'latitude': 41.1, 'longitude': 29.1},
    'createdAtMillis': createdAt,
    'activatedAtMillis': activatedAt,
    'expiresAtMillis': expiresAt,
    'distanceMeters': 12000,
    'durationSeconds': 1800,
    'encodedPolyline': encoded,
  };

  test('recovery exact empty payload kullanır ve null kabul eder', () async {
    final invoker = _Invoker()..response = {'activeReturnRoute': null};

    final result = await ActiveReturnRouteRecoveryService(
      invoker: invoker,
    ).recover();

    expect(result, isNull);
    expect(invoker.calls, 1);
    expect(invoker.name, FirebaseFunctionsRegistry.getMyActiveReturnRoute);
    expect(invoker.payload, isEmpty);
  });

  test('canonical dto PublishedReturnRoute olarak map edilir', () async {
    final invoker = _Invoker()..response = {'activeReturnRoute': route()};

    final result = await ActiveReturnRouteRecoveryService(
      invoker: invoker,
    ).recover();

    expect(result, isNotNull);
    expect(result!.routeId, 'route-1');
    expect(result.driverId, 'driver-1');
    expect(result.route.status, DriverReturnRouteStatus.active);
    expect(result.route.createdAt.isUtc, isTrue);
    expect(result.activatedAt.isUtc, isTrue);
    expect(result.expiresAt.isUtc, isTrue);
    expect(result.route.createdAt.millisecondsSinceEpoch, createdAt);
    expect(result.activatedAt.millisecondsSinceEpoch, activatedAt);
    expect(result.expiresAt.millisecondsSinceEpoch, expiresAt);
    expect(result.distanceMeters, 12000);
    expect(result.durationSeconds, 1800);
    expect(result.encodedPolyline, encoded);
    expect(result.route.routePoints.length, 3);
  });

  test('extra root route veya coordinate alanı fail closed olur', () async {
    final extraRoot = _Invoker()
      ..response = {'activeReturnRoute': route(), 'internal': true};

    await expectLater(
      ActiveReturnRouteRecoveryService(invoker: extraRoot).recover(),
      throwsA(
        isA<ActiveReturnRouteRecoveryException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );

    final extraRoute = route()..['passengerId'] = 'secret';

    final routeInvoker = _Invoker()
      ..response = {'activeReturnRoute': extraRoute};

    await expectLater(
      ActiveReturnRouteRecoveryService(invoker: routeInvoker).recover(),
      throwsA(
        isA<ActiveReturnRouteRecoveryException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );

    final nestedRoute = route();

    nestedRoute['origin'] = {
      'latitude': 41.0,
      'longitude': 29.0,
      'authUserId': 'secret',
    };

    final nestedInvoker = _Invoker()
      ..response = {'activeReturnRoute': nestedRoute};

    await expectLater(
      ActiveReturnRouteRecoveryService(invoker: nestedInvoker).recover(),
      throwsA(
        isA<ActiveReturnRouteRecoveryException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('malformed route alanları ve polyline fail closed olur', () async {
    for (final mutation in <Map<String, Object?> Function()>[
      () => route()..['routeId'] = '',
      () => route()..['driverId'] = null,
      () => route()..['status'] = 'expired',
      () => route()..['activatedAtMillis'] = 10.0,
      () => route()..['expiresAtMillis'] = activatedAt,
      () => route()..['distanceMeters'] = 0,
      () => route()..['durationSeconds'] = -1,
      () => route()..['encodedPolyline'] = '',
    ]) {
      final invoker = _Invoker()..response = {'activeReturnRoute': mutation()};

      await expectLater(
        ActiveReturnRouteRecoveryService(invoker: invoker).recover(),
        throwsA(
          isA<ActiveReturnRouteRecoveryException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    }
  });

  test('known backend reason korunur unknown detail gizlenir', () async {
    final known = _Invoker()
      ..error = const ActiveReturnRouteRecoveryException(
        'failed-precondition',
        reason: 'active_return_route_inconsistent',
      );

    await expectLater(
      ActiveReturnRouteRecoveryService(invoker: known).recover(),
      throwsA(
        isA<ActiveReturnRouteRecoveryException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.reason,
              'reason',
              'active_return_route_inconsistent',
            ),
      ),
    );

    final unknown = _Invoker()
      ..error = const ActiveReturnRouteRecoveryException(
        'raw-backend-code',
        reason: 'RAW_SECRET_DETAIL',
      );

    await expectLater(
      ActiveReturnRouteRecoveryService(invoker: unknown).recover(),
      throwsA(
        isA<ActiveReturnRouteRecoveryException>()
            .having((error) => error.code, 'code', 'unknown')
            .having((error) => error.reason, 'reason', isNull),
      ),
    );
  });

  test('raw invocation failure unavailable olarak sanitize edilir', () async {
    final invoker = _Invoker()..error = StateError('RAW_NETWORK_FAILURE');

    await expectLater(
      ActiveReturnRouteRecoveryService(invoker: invoker).recover(),
      throwsA(
        isA<ActiveReturnRouteRecoveryException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });
}

class _Invoker implements ActiveReturnRouteCallableInvoker {
  Object? response;
  Object? error;
  String? name;
  Map<String, dynamic> payload = {};
  int calls = 0;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    calls++;
    name = callable;
    payload = Map<String, dynamic>.of(data);

    final failure = error;

    if (failure != null) {
      throw failure;
    }

    return response;
  }
}
