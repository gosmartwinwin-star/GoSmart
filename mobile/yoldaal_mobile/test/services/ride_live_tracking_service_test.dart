import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_live_tracking_gateway.dart';
import 'package:yoldaal_mobile/services/ride_live_tracking_service.dart';

void main() {
  test('tracking service sends rideId only and parses fresh response', () async {
    final auth = _AuthSession();
    final invoker = _Invoker(
      response: <String, Object?>{
        'latitude': 41.0082,
        'longitude': 28.9784,
        'updatedAtMillis': 1000,
        'etaSeconds': 180,
        'etaUpdatedAtMillis': 900,
      },
    );

    final service = RideLiveTrackingService(
      authSession: auth,
      invoker: invoker,
    );

    final result = await service.getTracking(
      rideId: 'ride_1',
    );

    expect(auth.calls, 1);
    expect(invoker.calls, 1);
    expect(
      invoker.lastPayload,
      <String, Object?>{'rideId': 'ride_1'},
    );
    expect(result.driverLocation?.latitude, 41.0082);
    expect(result.driverLocation?.longitude, 28.9784);
    expect(result.updatedAtMillis, 1000);
    expect(result.etaSeconds, 180);
    expect(result.etaUpdatedAtMillis, 900);
  });

  test('tracking service accepts server stale null location and ETA', () async {
    final service = RideLiveTrackingService(
      authSession: _AuthSession(),
      invoker: _Invoker(
        response: <String, Object?>{
          'latitude': null,
          'longitude': null,
          'updatedAtMillis': 1000,
          'etaSeconds': null,
          'etaUpdatedAtMillis': null,
        },
      ),
    );

    final result = await service.getTracking(
      rideId: 'ride_1',
    );

    expect(result.driverLocation, isNull);
    expect(result.updatedAtMillis, 1000);
    expect(result.etaSeconds, isNull);
    expect(result.etaUpdatedAtMillis, isNull);
  });

  test('tracking service accepts driverArrived location with null ETA', () async {
    final service = RideLiveTrackingService(
      authSession: _AuthSession(),
      invoker: _Invoker(
        response: <String, Object?>{
          'latitude': 41.0,
          'longitude': 29.0,
          'updatedAtMillis': 2000,
          'etaSeconds': null,
          'etaUpdatedAtMillis': null,
        },
      ),
    );

    final result = await service.getTracking(
      rideId: 'ride_1',
    );

    expect(result.driverLocation, isNotNull);
    expect(result.etaSeconds, isNull);
  });

  test('tracking service rejects extra authority fields', () async {
    final service = RideLiveTrackingService(
      authSession: _AuthSession(),
      invoker: _Invoker(
        response: <String, Object?>{
          'latitude': 41.0,
          'longitude': 29.0,
          'updatedAtMillis': 2000,
          'etaSeconds': 120,
          'etaUpdatedAtMillis': 1900,
          'driverId': 'client-visible-authority-must-not-exist',
        },
      ),
    );

    await expectLater(
      service.getTracking(rideId: 'ride_1'),
      throwsA(isA<FormatException>()),
    );
  });

  test('tracking service rejects one-sided coordinate response', () async {
    final service = RideLiveTrackingService(
      authSession: _AuthSession(),
      invoker: _Invoker(
        response: <String, Object?>{
          'latitude': 41.0,
          'longitude': null,
          'updatedAtMillis': 2000,
          'etaSeconds': null,
          'etaUpdatedAtMillis': null,
        },
      ),
    );

    await expectLater(
      service.getTracking(rideId: 'ride_1'),
      throwsA(isA<FormatException>()),
    );
  });

  test('tracking service fails before callable when unauthenticated', () async {
    final invoker = _Invoker(
      response: <String, Object?>{
        'latitude': null,
        'longitude': null,
        'updatedAtMillis': null,
        'etaSeconds': null,
        'etaUpdatedAtMillis': null,
      },
    );

    final service = RideLiveTrackingService(
      authSession: _AuthSession(
        error: const RideLiveTrackingException(
          code: 'unauthenticated',
        ),
      ),
      invoker: invoker,
    );

    await expectLater(
      service.getTracking(rideId: 'ride_1'),
      throwsA(
        isA<RideLiveTrackingException>().having(
          (error) => error.code,
          'code',
          'unauthenticated',
        ),
      ),
    );

    expect(invoker.calls, 0);
  });
}

class _AuthSession implements RideLiveTrackingAuthSession {
  _AuthSession({this.error});

  final Object? error;
  int calls = 0;

  @override
  Future<void> requireAuthenticatedUser() async {
    calls += 1;

    if (error case final error?) {
      throw error;
    }
  }
}

class _Invoker implements RideLiveTrackingCallableInvoker {
  _Invoker({required this.response});

  final Object? response;

  int calls = 0;
  Map<String, Object?>? lastPayload;

  @override
  Future<Object?> call(
    Map<String, Object?> payload,
  ) async {
    calls += 1;
    lastPayload = Map<String, Object?>.of(payload);
    return response;
  }
}
