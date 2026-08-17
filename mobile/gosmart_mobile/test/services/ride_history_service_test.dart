import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/domain/ride/ride_history.dart';
import 'package:gosmart_mobile/services/ride_history_service.dart';
import 'package:gosmart_mobile/services/ride_lifecycle_service.dart';

void main() {
  test('passenger history exact payload ve response parse edilir', () async {
    final invoker = _Invoker()
      ..response = {
        'rides': [_rideMap(id: 'ride-1', status: 'completed')],
        'nextCursor': {'updatedAtMillis': 2000, 'rideId': 'ride-1'},
      };

    final page = await RideHistoryService(
      invoker: invoker,
    ).loadPage(scope: RideHistoryScope.passenger);

    expect(invoker.name, 'getMyRideHistory');

    expect(invoker.payload, {
      'scope': 'passenger',
      'pageSize': 20,
      'cursor': null,
    });

    expect(page.rides, hasLength(1));
    expect(page.rides.single.rideId, 'ride-1');
    expect(page.rides.single.status, RideStatus.completed);

    expect(page.nextCursor?.updatedAtMillis, 2000);

    expect(page.nextCursor?.rideId, 'ride-1');
  });

  test('driver cursor exact payload olarak gonderilir', () async {
    final invoker = _Invoker()
      ..response = {'rides': <Object?>[], 'nextCursor': null};

    await RideHistoryService(invoker: invoker).loadPage(
      scope: RideHistoryScope.driver,
      pageSize: 7,
      cursor: const RideHistoryCursor(
        updatedAtMillis: 1234,
        rideId: 'ride_abc',
      ),
    );

    expect(invoker.payload, {
      'scope': 'driver',
      'pageSize': 7,
      'cursor': {'updatedAtMillis': 1234, 'rideId': 'ride_abc'},
    });
  });

  test('non-terminal history response fail closed olur', () async {
    final invoker = _Invoker()
      ..response = {
        'rides': [_rideMap(id: 'active', status: 'inProgress')],
        'nextCursor': null,
      };

    await expectLater(
      RideHistoryService(
        invoker: invoker,
      ).loadPage(scope: RideHistoryScope.passenger),
      throwsA(
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('gateway code ve reason degistirilmeden korunur', () async {
    final invoker = _Invoker()
      ..error = const RideGatewayException(
        'failed-precondition',
        reason: 'duplicate_driver_profile',
      );

    await expectLater(
      RideHistoryService(
        invoker: invoker,
      ).loadPage(scope: RideHistoryScope.driver),
      throwsA(
        isA<RideGatewayException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.reason,
              'reason',
              'duplicate_driver_profile',
            ),
      ),
    );
  });

  test('page size client tarafinda da bounded', () async {
    final service = RideHistoryService(invoker: _Invoker());

    await expectLater(
      service.loadPage(scope: RideHistoryScope.passenger, pageSize: 21),
      throwsArgumentError,
    );
  });
}

class _Invoker implements RideCallableInvoker {
  String? name;
  Map<String, dynamic>? payload;

  Map<String, dynamic> response = {'rides': <Object?>[], 'nextCursor': null};

  RideGatewayException? error;

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    this.name = name;
    this.payload = payload;

    if (error case final value?) {
      throw value;
    }

    return response;
  }
}

Map<String, dynamic> _rideMap({required String id, required String status}) => {
  'rideId': id,
  'status': status,
  'version': status == 'completed' ? 5 : 4,
  'driverId': 'driver-1',
  'pickup': {'latitude': 41.0, 'longitude': 29.0, 'addressLabel': 'Pickup'},
  'dropoff': {'latitude': 41.1, 'longitude': 29.1, 'addressLabel': 'Dropoff'},
  'route': {
    'distanceMeters': 1500,
    'durationSeconds': 420,
    'encodedPolyline': 'encoded',
    'computedAtMillis': 1000,
  },
  'createdAtMillis': 1000,
  'updatedAtMillis': 2000,
  'acceptedAtMillis': 1100,
  'driverEnRouteAtMillis': 1200,
  'arrivedAtMillis': 1300,
  'startedAtMillis': 1400,
  'completedAtMillis': status == 'completed' ? 2000 : null,
  'cancelledAtMillis': null,
  'expiredAtMillis': null,
  'cancelledBy': null,
  'terminalReason': null,
};
