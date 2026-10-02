import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/'
    'passenger_fare_quote_create_coordinator.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/domain/ride/passenger_fare_quote.dart';
import 'package:yoldaal_mobile/domain/ride/ride_fare.dart';

void main() {
  PassengerFareQuote quote({
    String quoteId = _quoteId,
    int yoldaalFareMinor = 27480,
  }) => PassengerFareQuote(
    quoteId: quoteId,
    pricingVersion: PassengerFareQuote.pricingVersionV1,
    currency: PassengerFareQuote.currencyTry,
    plannedDistanceMeters: 18200,
    plannedDurationSeconds: 2400,
    referenceEstimatedFareMinor: 68700,
    yoldaalFareMinor: yoldaalFareMinor,
    savingMinor: 68700 - yoldaalFareMinor,
    quotedAtMillis: 1757000000000,
  );

  CanonicalRide ride({
    RideParticipantFare? fare,
  }) => CanonicalRide(
    rideId: 'ride_1234',
    status: RideStatus.matching,
    version: 1,
    pickup: _pickup,
    dropoff: _dropoff,
    route: const RideRoute(
      distanceMeters: 18200,
      durationSeconds: 2400,
      encodedPolyline: 'encoded',
    ),
    fare: fare ??
        const RideParticipantFare(
          quoteId: _quoteId,
          currency: 'TRY',
          yoldaalFareMinor: 27480,
        ),
  );

  test(
    'quote completes before create with exact shared request data',
    () async {
      final calls = <String>[];

      final coordinator = PassengerFareQuoteCreateCoordinator(
        createQuote: ({
          required requestId,
          required pickup,
          required dropoff,
        }) async {
          calls.add('quote:$requestId');
          expect(identical(pickup, _pickup), isTrue);
          expect(identical(dropoff, _dropoff), isTrue);
          return quote();
        },
        createRide: ({
          required requestId,
          required pickup,
          required dropoff,
        }) async {
          calls.add('ride:$requestId');
          expect(identical(pickup, _pickup), isTrue);
          expect(identical(dropoff, _dropoff), isTrue);
          return ride();
        },
      );

      final result = await coordinator.create(
        requestId: 'shared_request_12345678',
        pickup: _pickup,
        dropoff: _dropoff,
      );

      expect(
        calls,
        [
          'quote:shared_request_12345678',
          'ride:shared_request_12345678',
        ],
      );
      expect(result.quote.quoteId, _quoteId);
      expect(result.ride.fare!.yoldaalFareMinor, 27480);
    },
  );

  test('quote failure prevents create ride call', () async {
    var createRideCalls = 0;
    final coordinator = PassengerFareQuoteCreateCoordinator(
      createQuote: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async {
        throw StateError('quote-failed');
      },
      createRide: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async {
        createRideCalls++;
        return ride();
      },
    );

    await expectLater(
      coordinator.create(
        requestId: 'shared_request_12345678',
        pickup: _pickup,
        dropoff: _dropoff,
      ),
      throwsStateError,
    );
    expect(createRideCalls, 0);
  });

  test('create failure is propagated without fallback fare', () async {
    final coordinator = PassengerFareQuoteCreateCoordinator(
      createQuote: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async => quote(),
      createRide: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async {
        throw StateError('create-failed');
      },
    );

    await expectLater(
      coordinator.create(
        requestId: 'shared_request_12345678',
        pickup: _pickup,
        dropoff: _dropoff,
      ),
      throwsStateError,
    );
  });

  test('missing bound ride fare fails closed after create', () async {
    final coordinator = PassengerFareQuoteCreateCoordinator(
      createQuote: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async => quote(),
      createRide: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async => const CanonicalRide(
        rideId: 'ride_1234',
        status: RideStatus.matching,
        version: 1,
        pickup: _pickup,
        dropoff: _dropoff,
        route: RideRoute(
          distanceMeters: 18200,
          durationSeconds: 2400,
          encodedPolyline: 'encoded',
        ),
      ),
    );

    await expectLater(
      coordinator.create(
        requestId: 'shared_request_12345678',
        pickup: _pickup,
        dropoff: _dropoff,
      ),
      throwsA(
        isA<PassengerFareQuoteCreateException>().having(
          (error) => error.reason,
          'reason',
          'fare-binding-mismatch',
        ),
      ),
    );
  });

  test('quote identity mismatch fails closed', () async {
    final coordinator = PassengerFareQuoteCreateCoordinator(
      createQuote: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async => quote(),
      createRide: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async => ride(
        fare: const RideParticipantFare(
          quoteId: _otherQuoteId,
          currency: 'TRY',
          yoldaalFareMinor: 27480,
        ),
      ),
    );

    await expectLater(
      coordinator.create(
        requestId: 'shared_request_12345678',
        pickup: _pickup,
        dropoff: _dropoff,
      ),
      throwsA(isA<PassengerFareQuoteCreateException>()),
    );
  });

  test('bound amount mismatch fails closed', () async {
    final coordinator = PassengerFareQuoteCreateCoordinator(
      createQuote: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async => quote(),
      createRide: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async => ride(
        fare: const RideParticipantFare(
          quoteId: _quoteId,
          currency: 'TRY',
          yoldaalFareMinor: 27481,
        ),
      ),
    );

    await expectLater(
      coordinator.create(
        requestId: 'shared_request_12345678',
        pickup: _pickup,
        dropoff: _dropoff,
      ),
      throwsA(isA<PassengerFareQuoteCreateException>()),
    );
  });
}

const _pickup = RideLocation(
  latitude: 39.92077,
  longitude: 32.85411,
  addressLabel: 'Pickup',
);
const _dropoff = RideLocation(
  latitude: 39.95,
  longitude: 32.88,
  addressLabel: 'Dropoff',
);
const _quoteId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherQuoteId =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
