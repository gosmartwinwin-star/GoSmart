import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/domain/ride/ride_match_offer.dart';

void main() {
  Map<String, dynamic> offer({Object? fare = _absent}) {
    final value = <String, dynamic>{
      'rideId': 'ride_1',
      'rideVersion': 3,
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
      'pickupDetourMeters': 100,
      'pickupDetourSeconds': 60,
      'dropoffDetourMeters': 200,
      'dropoffDetourSeconds': 120,
      'passengerTripDistanceMeters': 1000,
      'passengerTripDurationSeconds': 300,
      'expiresAtMillis': 1757000000000,
    };
    if (!identical(fare, _absent)) {
      value['fare'] = fare;
    }
    return value;
  }

  test('legacy driver offer remains readable before fare cutover', () {
    expect(RideMatchOffer.fromMap(offer()).fare, isNull);
  });

  test('priced driver offer parses YoldaAl-only fare', () {
    final parsed = RideMatchOffer.fromMap(
      offer(
        fare: {
          'currency': 'TRY',
          'yoldaalFareMinor': 27480,
        },
      ),
    );

    expect(parsed.fare, isNotNull);
    expect(parsed.fare!.currency, 'TRY');
    expect(parsed.fare!.yoldaalFareMinor, 27480);
  });

  test('present malformed driver offer fare fails closed', () {
    expect(
      () => RideMatchOffer.fromMap(offer(fare: null)),
      throwsFormatException,
    );
    expect(
      () => RideMatchOffer.fromMap(
        offer(
          fare: {
            'currency': 'TRY',
            'yoldaalFareMinor': 27480,
            'quoteId': 'a' * 64,
          },
        ),
      ),
      throwsFormatException,
    );
  });

  test('unexpected public offer fields still fail closed', () {
    final invalid = offer()..['referenceEstimatedFareMinor'] = 68700;
    expect(() => RideMatchOffer.fromMap(invalid), throwsFormatException);
  });
}

const _absent = Object();
