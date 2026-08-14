import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_ride_controller.dart';
import 'package:gosmart_mobile/controllers/passenger_ride_controller.dart';
import 'package:gosmart_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/services/ride_lifecycle_service.dart';

void main() {
  const point = RideLocation(
    latitude: 41,
    longitude: 29,
    addressLabel: 'Adres',
  );
  test(
    'callable region europe-west1',
    () => expect(RideLifecycleService.region, 'europe-west1'),
  );
  test(
    'passenger create payload exact ve client/server kimlik alanlarından arınmış',
    () async {
      final invoker = FakeInvoker()..response = createResponse;
      await RideLifecycleService(
        invoker: invoker,
      ).createRide(requestId: 'request', pickup: point, dropoff: point);
      expect(invoker.name, 'createRideRequest');
      expect(invoker.payload, {
        'requestId': 'request',
        'pickup': {
          'latitude': 41.0,
          'longitude': 29.0,
          'addressLabel': 'Adres',
        },
        'dropoff': {
          'latitude': 41.0,
          'longitude': 29.0,
          'addressLabel': 'Adres',
        },
      });
      for (final forbidden in [
        'passengerId',
        'driverId',
        'actorType',
        'taxiId',
        'status',
        'version',
        'timestamp',
        'distanceMeters',
        'durationSeconds',
        'encodedPolyline',
      ]) {
        expect(invoker.payload.containsKey(forbidden), isFalse);
      }
    },
  );
  test('passenger recovery ve cancel exact payload', () async {
    final invoker = FakeInvoker()..response = {'activeRide': null};
    final service = RideLifecycleService(invoker: invoker);
    await service.getMyActiveRide();
    expect(invoker.name, 'getMyActiveRide');
    expect(invoker.payload, isEmpty);
    invoker.response = {};
    await service.cancel(
      rideId: 'ride',
      requestId: 'request',
      expectedVersion: 3,
      driver: false,
    );
    expect(invoker.name, 'cancelRide');
    expect(invoker.payload, {
      'rideId': 'ride',
      'requestId': 'request',
      'expectedVersion': 3,
      'reasonCode': 'passenger_cancelled',
    });
  });
  test('driver recovery ve bütün mutation payloadları exact', () async {
    final invoker = FakeInvoker()..response = {'activeRide': null};
    final service = RideLifecycleService(invoker: invoker);
    await service.getMyActiveDriverRide();
    expect(invoker.name, 'getMyActiveDriverRide');
    expect(invoker.payload, isEmpty);
    invoker.response = {};
    await service.markDriverArrived(
      rideId: 'ride',
      requestId: 'a',
      expectedVersion: 1,
    );
    expect(invoker.take(), [
      'markDriverArrived',
      {'rideId': 'ride', 'requestId': 'a', 'expectedVersion': 1},
    ]);
    await service.startRide(rideId: 'ride', requestId: 'b', expectedVersion: 2);
    expect(invoker.take(), [
      'startRide',
      {'rideId': 'ride', 'requestId': 'b', 'expectedVersion': 2},
    ]);
    await service.completeRide(
      rideId: 'ride',
      requestId: 'c',
      expectedVersion: 3,
    );
    expect(invoker.take(), [
      'completeRide',
      {'rideId': 'ride', 'requestId': 'c', 'expectedVersion': 3},
    ]);
    await service.cancel(
      rideId: 'ride',
      requestId: 'd',
      expectedVersion: 2,
      driver: true,
    );
    expect(invoker.take(), [
      'cancelRide',
      {
        'rideId': 'ride',
        'requestId': 'd',
        'expectedVersion': 2,
        'reasonCode': 'driver_cancelled',
      },
    ]);
    for (final call in invoker.calls) {
      for (final forbidden in ['driverId', 'passengerId', 'actorType']) {
        expect(call.$2.containsKey(forbidden), isFalse);
      }
    }
  });
  test(
    'exact fixture callable response canonical driver ride üretir',
    () async {
      final invoker = FakeInvoker()..response = fixtureRecoveryResponse;
      final recovered = await RideLifecycleService(
        invoker: invoker,
      ).getMyActiveDriverRide();

      expect(invoker.name, 'getMyActiveDriverRide');
      expect(recovered?.rideId, 'fixture_assigned_ride');
      expect(recovered?.driverId, 'fixture_driver_profile');
      expect(recovered?.status, RideStatus.driverEnRoute);
      expect(recovered?.version, 2);
    },
  );
  test('null active ride hata olmadan null döner', () async {
    final invoker = FakeInvoker()..response = {'activeRide': null};
    expect(
      await RideLifecycleService(invoker: invoker).getMyActiveDriverRide(),
      isNull,
    );
  });
  test('malformed active ride invalid response olarak reddedilir', () async {
    final invoker = FakeInvoker()..response = {'activeRide': 'broken'};
    await expectLater(
      RideLifecycleService(invoker: invoker).getMyActiveDriverRide(),
      throwsA(
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });
  test('gateway kontrollü error code/reason korur', () async {
    for (final code in [
      'unauthenticated',
      'permission-denied',
      'failed-precondition',
      'already-exists',
      'unavailable',
      'internal',
    ]) {
      final invoker = FakeInvoker()
        ..error = RideGatewayException(code, reason: 'raw-secret-detail');
      await expectLater(
        RideLifecycleService(invoker: invoker).getMyActiveRide(),
        throwsA(
          isA<RideGatewayException>().having((e) => e.code, 'code', code),
        ),
      );
    }
  });
  test('FirebaseFunctionsException code ve reason korunur', () async {
    final invoker = FirebaseRideCallableInvoker(
      routing: testRouting,
      caller: (_, _) => throw _TestFunctionsException(
        code: 'failed-precondition',
        details: {'reason': 'active_ride_pointer_inconsistent'},
      ),
    );
    await expectLater(
      invoker.call('getMyActiveDriverRide', const {}),
      throwsA(
        isA<RideGatewayException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.reason,
              'reason',
              'active_ride_pointer_inconsistent',
            ),
      ),
    );
  });
  test(
    'FirebaseFunctionsException debug message sanitize edilip 300 karakterle sinirlanir',
    () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
        }
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
      });

      final longTail = List<String>.filled(320, 'x').join();
      final invoker = FirebaseRideCallableInvoker(
        routing: testRouting,
        caller: (_, _) => throw _TestFunctionsException(
          code: 'unknown',
          message: '  first\n\tsecond   $longTail  ',
        ),
      );

      await expectLater(
        invoker.call('getMyActiveDriverRide', const {}),
        throwsA(
          isA<RideGatewayException>().having(
            (error) => error.code,
            'code',
            'unknown',
          ),
        ),
      );

      final failureLog = logs.singleWhere(
        (entry) => entry.startsWith(
          'Functions failure callable=getMyActiveDriverRide code=unknown',
        ),
      );
      const marker = ' message=';
      expect(failureLog, contains('reason=null message='));
      final safeMessage = failureLog.substring(
        failureLog.indexOf(marker) + marker.length,
      );

      expect(safeMessage.length, 300);
      expect(safeMessage, startsWith('first second '));
      expect(safeMessage, isNot(contains('\n')));
      expect(safeMessage, isNot(contains('\t')));
      expect(safeMessage.trim(), safeMessage);
      expect(RegExp(r'\s{2,}').hasMatch(safeMessage), isFalse);
    },
  );

  test(
    'beklenmeyen client hatası güvenli unavailable olarak map edilir',
    () async {
      final invoker = FirebaseRideCallableInvoker(
        routing: testRouting,
        caller: (_, _) => throw StateError('socket secret'),
      );
      await expectLater(
        invoker.call('getMyActiveDriverRide', const {}),
        throwsA(
          isA<RideGatewayException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
    },
  );
  test('user-facing error mapping raw backend detail sızdırmaz', () {
    for (final error in [
      const RideGatewayException('unauthenticated', reason: 'raw-secret'),
      const RideGatewayException('permission-denied', reason: 'raw-secret'),
      const RideGatewayException(
        'failed-precondition',
        reason: 'stale_ride_version',
      ),
      const RideGatewayException('already-exists', reason: 'raw-secret'),
      const RideGatewayException('unavailable', reason: 'raw-secret'),
      const RideGatewayException('internal', reason: 'raw-secret'),
    ]) {
      expect(
        PassengerRideController.messageFor(error),
        isNot(contains('raw-secret')),
      );
      expect(PassengerError.message(error), isNot(contains('raw-secret')));
    }
  });
}

const testRouting = FirebaseFunctionsRouting(
  projectId: 'demo-gosmart',
  region: 'europe-west1',
  emulatorHost: '10.0.2.2',
  emulatorPort: 5001,
);

class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException({
    required super.code,
    super.details,
    super.message = 'safe test failure',
  });
}

final createResponse = {
  'rideId': 'ride',
  'status': 'matching',
  'version': 1,
  'createdAtMillis': 1,
  'distanceMeters': 1,
  'durationSeconds': 1,
  'encodedPolyline': 'x',
};
final fixtureRecoveryResponse = <String, dynamic>{
  'activeRide': <String, dynamic>{
    'rideId': 'fixture_assigned_ride',
    'driverId': 'fixture_driver_profile',
    'status': 'driverEnRoute',
    'version': 2,
    'pickup': <String, dynamic>{
      'latitude': 41.0082,
      'longitude': 28.9784,
      'addressLabel': 'Fixture pickup',
    },
    'dropoff': <String, dynamic>{
      'latitude': 41.0151,
      'longitude': 28.9795,
      'addressLabel': 'Fixture dropoff',
    },
    'route': <String, dynamic>{
      'distanceMeters': 1400,
      'durationSeconds': 420,
      'encodedPolyline': 'fixture_polyline',
      'computedAtMillis': 1767225600000,
    },
    'createdAtMillis': 1767225600000,
    'updatedAtMillis': 1767225600000,
    'acceptedAtMillis': 1767225600000,
    'driverEnRouteAtMillis': 1767225600000,
    'arrivedAtMillis': null,
    'startedAtMillis': null,
    'completedAtMillis': null,
    'cancelledAtMillis': null,
    'expiredAtMillis': null,
    'cancelledBy': null,
    'terminalReason': null,
  },
};

class FakeInvoker implements RideCallableInvoker {
  Map<String, dynamic> response = {};
  RideGatewayException? error;
  String? name;
  Map<String, dynamic> payload = {};
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> call(
    String value,
    Map<String, dynamic> data,
  ) async {
    name = value;
    payload = Map.of(data);
    calls.add((value, Map.of(data)));
    if (error case final failure?) throw failure;
    return response;
  }

  List<Object> take() => [name!, payload];
}
