import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';

void main() {
  Map<String, dynamic> ride({Object? fare = _absent}) {
    final value = <String, dynamic>{
      'rideId': 'ride-1',
      'status': 'matching',
      'version': 1,
      'driverId': null,
      'pickup': {
        'latitude': 41.0,
        'longitude': 29.0,
        'addressLabel': 'Pickup',
      },
      'dropoff': {
        'latitude': 41.1,
        'longitude': 29.1,
        'addressLabel': 'Dropoff',
      },
      'route': {
        'distanceMeters': 1000,
        'durationSeconds': 300,
        'encodedPolyline': 'abc',
        'computedAtMillis': null,
      },
      'createdAtMillis': 1000,
      'updatedAtMillis': 2000,
      'acceptedAtMillis': null,
      'driverEnRouteAtMillis': null,
      'arrivedAtMillis': null,
      'startedAtMillis': null,
      'completedAtMillis': null,
      'cancelledAtMillis': null,
      'expiredAtMillis': null,
      'cancelledBy': null,
      'terminalReason': null,
    };
    if (!identical(fare, _absent)) {
      value['fare'] = fare;
    }
    return value;
  }

  test('legacy canonical ride remains readable before fare cutover', () {
    expect(CanonicalRide.fromMap(ride()).fare, isNull);
  });

  test('priced canonical ride parses exact participant fare', () {
    final parsed = CanonicalRide.fromMap(
      ride(
        fare: {
          'quoteId': 'a' * 64,
          'currency': 'TRY',
          'yoldaalFareMinor': 27480,
        },
      ),
    );

    expect(parsed.fare, isNotNull);
    expect(parsed.fare!.quoteId, 'a' * 64);
    expect(parsed.fare!.currency, 'TRY');
    expect(parsed.fare!.yoldaalFareMinor, 27480);
  });

  test('present malformed canonical ride fare fails closed', () {
    expect(
      () => CanonicalRide.fromMap(ride(fare: null)),
      throwsFormatException,
    );
    expect(
      () => CanonicalRide.fromMap(
        ride(
          fare: {
            'quoteId': 'a' * 64,
            'currency': 'TRY',
            'yoldaalFareMinor': 27480,
            'savingMinor': 41220,
          },
        ),
      ),
      throwsFormatException,
    );
  });
}

const _absent = Object();
