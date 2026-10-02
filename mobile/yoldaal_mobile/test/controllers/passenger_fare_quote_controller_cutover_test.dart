import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/passenger_fare_quote_create_coordinator.dart';
import 'package:yoldaal_mobile/application/ride/passenger_fare_quote_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/controllers/passenger_ride_controller.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/domain/ride/passenger_fare_quote.dart';
import 'package:yoldaal_mobile/domain/ride/ride_fare.dart';

const _pickup = RideLocation(
  latitude: 41.0105,
  longitude: 28.9717,
  addressLabel: 'YoldaAl Merkez',
);
const _dropoff = RideLocation(
  latitude: 41.0256,
  longitude: 28.9744,
  addressLabel: 'Galata Kulesi',
);
const _quoteId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _quote = PassengerFareQuote(
  quoteId: _quoteId,
  pricingVersion: PassengerFareQuote.pricingVersionV1,
  currency: PassengerFareQuote.currencyTry,
  plannedDistanceMeters: 1800,
  plannedDurationSeconds: 420,
  referenceEstimatedFareMinor: 10000,
  yoldaalFareMinor: 4000,
  savingMinor: 6000,
  quotedAtMillis: 1,
);

void main() {
  test(
    'quote then create reuses one requestId and retains passenger quote',
    () async {
      final gateway = _Gateway();
      final calls = <String>[];
      final coordinator = PassengerFareQuoteCreateCoordinator(
        createQuote: ({
          required requestId,
          required pickup,
          required dropoff,
        }) async {
          calls.add('quote:$requestId');
          expect(pickup, same(_pickup));
          expect(dropoff, same(_dropoff));
          return _quote;
        },
        createRide: ({
          required requestId,
          required pickup,
          required dropoff,
        }) async {
          calls.add('ride:$requestId');
          return gateway.createRide(
            requestId: requestId,
            pickup: pickup,
            dropoff: dropoff,
          );
        },
      );
      final controller = PassengerRideController(
        gateway: gateway,
        repository: gateway,
        fareQuoteCreateCoordinator: coordinator,
        requestIdGenerator: () => 'shared_request_12345678',
      );
      addTearDown(controller.dispose);

      expect(
        await controller.create(pickup: _pickup, dropoff: _dropoff),
        isTrue,
      );
      expect(calls, <String>[
        'quote:shared_request_12345678',
        'ride:shared_request_12345678',
      ]);
      expect(gateway.createRequestIds, <String>['shared_request_12345678']);
      expect(controller.fareQuote, same(_quote));
      expect(controller.ride?.fare?.quoteId, _quoteId);
      expect(controller.ride?.fare?.yoldaalFareMinor, 4000);
    },
  );

  test('quote failure blocks create and retry retains the same requestId', () async {
    final gateway = _Gateway();
    final quoteRequestIds = <String>[];
    var failQuote = true;
    final coordinator = PassengerFareQuoteCreateCoordinator(
      createQuote: ({
        required requestId,
        required pickup,
        required dropoff,
      }) async {
        quoteRequestIds.add(requestId);
        if (failQuote) {
          throw const PassengerFareQuoteGatewayException('unavailable');
        }
        return _quote;
      },
      createRide: ({
        required requestId,
        required pickup,
        required dropoff,
      }) => gateway.createRide(
        requestId: requestId,
        pickup: pickup,
        dropoff: dropoff,
      ),
    );
    final controller = PassengerRideController(
      gateway: gateway,
      repository: gateway,
      fareQuoteCreateCoordinator: coordinator,
      requestIdGenerator: () => 'retry_request_12345678',
    );
    addTearDown(controller.dispose);

    expect(
      await controller.create(pickup: _pickup, dropoff: _dropoff),
      isFalse,
    );
    expect(gateway.createRequestIds, isEmpty);
    expect(controller.fareQuote, isNull);

    failQuote = false;

    expect(
      await controller.create(pickup: _pickup, dropoff: _dropoff),
      isTrue,
    );
    expect(quoteRequestIds, <String>[
      'retry_request_12345678',
      'retry_request_12345678',
    ]);
    expect(gateway.createRequestIds, <String>['retry_request_12345678']);
    expect(controller.fareQuote, same(_quote));
  });

  test(
    'home default controller construction wires quote service to shared ride gateway',
    () {
      final source = File(
        'lib/screens/home/home_screen.dart',
      ).readAsStringSync();

      expect(source, contains('final rideGateway = RideLifecycleService();'));
      expect(
        source,
        contains(
          'fareQuoteCreateCoordinator: PassengerFareQuoteCreateCoordinator(',
        ),
      );
      expect(
        source,
        contains('createQuote: PassengerFareQuoteService().createQuote,'),
      );
      expect(source, contains('createRide: rideGateway.createRide,'));
      expect(source, contains('await rideController.create('));
    },
  );
}

class _Gateway implements RideGateway, RideStreamRepository {
  final List<String> createRequestIds = <String>[];

  @override
  Future<CanonicalRide> createRide({
    required String requestId,
    required RideLocation pickup,
    required RideLocation dropoff,
  }) async {
    createRequestIds.add(requestId);
    return CanonicalRide(
      rideId: 'ride_1234',
      status: RideStatus.matching,
      version: 1,
      pickup: pickup,
      dropoff: dropoff,
      route: const RideRoute(
        distanceMeters: 1800,
        durationSeconds: 420,
        encodedPolyline: 'encoded',
      ),
      fare: const RideParticipantFare(
        quoteId: _quoteId,
        currency: 'TRY',
        yoldaalFareMinor: 4000,
      ),
    );
  }

  @override
  Future<CanonicalRide?> getMyActiveRide() async => null;

  @override
  Stream<CanonicalRide> watchRide(String rideId) =>
      const Stream<CanonicalRide>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected ride gateway call.');
}
