import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/domain/ride/ride_fare.dart';

void main() {
  Map<String, dynamic> participant({
    Map<String, dynamic> overrides = const {},
  }) => {
    'quoteId': 'a' * 64,
    'currency': 'TRY',
    'yoldaalFareMinor': 27480,
    ...overrides,
  };

  Map<String, dynamic> driver({
    Map<String, dynamic> overrides = const {},
  }) => {
    'currency': 'TRY',
    'yoldaalFareMinor': 27480,
    ...overrides,
  };

  test('participant fare parses exact backend projection', () {
    final fare = RideParticipantFare.fromMap(participant());

    expect(fare.quoteId, 'a' * 64);
    expect(fare.currency, 'TRY');
    expect(fare.yoldaalFareMinor, 27480);
  });

  test('participant fare rejects missing extra and malformed identity', () {
    final missing = participant()..remove('currency');
    expect(
      () => RideParticipantFare.fromMap(missing),
      throwsFormatException,
    );
    expect(
      () => RideParticipantFare.fromMap(
        participant(overrides: {'savingMinor': 41220}),
      ),
      throwsFormatException,
    );
    expect(
      () => RideParticipantFare.fromMap(
        participant(overrides: {'quoteId': 'not-a-hash'}),
      ),
      throwsFormatException,
    );
  });

  test('participant fare freezes TRY and safe non-negative minor units', () {
    expect(
      () => RideParticipantFare.fromMap(
        participant(overrides: {'currency': 'USD'}),
      ),
      throwsFormatException,
    );
    expect(
      () => RideParticipantFare.fromMap(
        participant(overrides: {'yoldaalFareMinor': -1}),
      ),
      throwsFormatException,
    );
    expect(
      () => RideParticipantFare.fromMap(
        participant(overrides: {'yoldaalFareMinor': 1.5}),
      ),
      throwsFormatException,
    );
    expect(
      () => RideParticipantFare.fromMap(
        participant(
          overrides: {'yoldaalFareMinor': 9007199254740992},
        ),
      ),
      throwsFormatException,
    );
  });

  test('zero passenger fare remains structurally valid', () {
    final fare = RideParticipantFare.fromMap(
      participant(overrides: {'yoldaalFareMinor': 0}),
    );
    expect(fare.yoldaalFareMinor, 0);
  });

  test('driver fare exposes only currency and YoldaAl amount', () {
    final fare = DriverRideMatchOfferFare.fromMap(driver());

    expect(fare.currency, 'TRY');
    expect(fare.yoldaalFareMinor, 27480);

    expect(
      () => DriverRideMatchOfferFare.fromMap(
        driver(overrides: {'quoteId': 'a' * 64}),
      ),
      throwsFormatException,
    );
    expect(
      () => DriverRideMatchOfferFare.fromMap(
        driver(overrides: {'referenceEstimatedFareMinor': 68700}),
      ),
      throwsFormatException,
    );
  });

  test('driver fare rejects malformed currency and amount', () {
    expect(
      () => DriverRideMatchOfferFare.fromMap(
        driver(overrides: {'currency': 'USD'}),
      ),
      throwsFormatException,
    );
    expect(
      () => DriverRideMatchOfferFare.fromMap(
        driver(overrides: {'yoldaalFareMinor': -1}),
      ),
      throwsFormatException,
    );
    expect(
      () => DriverRideMatchOfferFare.fromMap(
        driver(overrides: {'yoldaalFareMinor': 1.5}),
      ),
      throwsFormatException,
    );
  });
}
