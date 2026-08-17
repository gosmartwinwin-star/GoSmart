import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:gosmart_mobile/domain/ride/ride_match_offer.dart';
import 'package:gosmart_mobile/services/ride_lifecycle_service.dart';
import 'package:gosmart_mobile/services/ride_match_offer_service.dart';

void main() {
  test(
    'discovery uses exact empty payload and parses only public dto',
    () async {
      final invoker = _Invoker()
        ..response = {
          'offers': [_offerMap()],
        };

      final offers = await RideMatchOfferService(
        invoker: invoker,
      ).getMyRideMatchOffers();

      expect(invoker.name, FirebaseFunctionsRegistry.getMyRideMatchOffers);
      expect(invoker.payload, isEmpty);
      expect(offers, hasLength(1));

      final offer = offers.single;

      expect(offer.rideId, 'ride_1');
      expect(offer.rideVersion, 1);
      expect(offer.pickup.addressLabel, 'Pickup');
      expect(offer.dropoff.addressLabel, 'Dropoff');
      expect(offer.expiresAt.isUtc, isTrue);
      expect(offer.expiresAt.millisecondsSinceEpoch, 1893456000000);
    },
  );

  test('identity or internal fields in public offer fail closed', () async {
    final unsafe = _offerMap()..['driverId'] = 'driver-secret';

    final invoker = _Invoker()
      ..response = {
        'offers': [unsafe],
      };

    await expectLater(
      RideMatchOfferService(invoker: invoker).getMyRideMatchOffers(),
      throwsA(
        isA<RideMatchOfferException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('malformed or oversized discovery response fails closed', () async {
    final malformed = _Invoker()
      ..response = {
        'offers': [
          _offerMap(),
          _offerMap('ride_2'),
          _offerMap('ride_3'),
          _offerMap('ride_4'),
        ],
      };

    await expectLater(
      RideMatchOfferService(invoker: malformed).getMyRideMatchOffers(),
      throwsA(
        isA<RideMatchOfferException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );

    final duplicate = _Invoker()
      ..response = {
        'offers': [_offerMap(), _offerMap()],
      };

    await expectLater(
      RideMatchOfferService(invoker: duplicate).getMyRideMatchOffers(),
      throwsA(
        isA<RideMatchOfferException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('accept uses exact authoritative offer version payload', () async {
    final offer = RideMatchOffer.fromMap(_offerMap());

    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'status': 'driverEnRoute',
        'version': 2,
      };

    await RideMatchOfferService(
      invoker: invoker,
    ).acceptRideMatchOffer(offer: offer, requestId: 'request_12345678');

    expect(invoker.name, FirebaseFunctionsRegistry.acceptRide);

    expect(invoker.payload, {
      'rideId': 'ride_1',
      'requestId': 'request_12345678',
      'expectedVersion': 1,
    });

    for (final forbidden in [
      'driverId',
      'passengerId',
      'returnRouteId',
      'offerId',
      'measurement',
      'policyVersion',
    ]) {
      expect(invoker.payload.containsKey(forbidden), isFalse);
    }
  });

  test('invalid accept request id is rejected before callable', () async {
    final invoker = _Invoker();

    await expectLater(
      RideMatchOfferService(invoker: invoker).acceptRideMatchOffer(
        offer: RideMatchOffer.fromMap(_offerMap()),
        requestId: 'short',
      ),
      throwsA(
        isA<RideMatchOfferException>()
            .having((error) => error.code, 'code', 'invalid-argument')
            .having((error) => error.reason, 'reason', 'invalid_request_id'),
      ),
    );

    expect(invoker.calls, 0);
  });

  test(
    'known backend reason is retained and unknown reason is hidden',
    () async {
      final known = _Invoker()
        ..error = const RideGatewayException(
          'failed-precondition',
          reason: 'subscription_required',
        );

      await expectLater(
        RideMatchOfferService(invoker: known).getMyRideMatchOffers(),
        throwsA(
          isA<RideMatchOfferException>()
              .having((error) => error.code, 'code', 'failed-precondition')
              .having(
                (error) => error.reason,
                'reason',
                'subscription_required',
              ),
        ),
      );

      final unknown = _Invoker()
        ..error = const RideGatewayException(
          'failed-precondition',
          reason: 'raw-secret-detail',
        );

      await expectLater(
        RideMatchOfferService(invoker: unknown).getMyRideMatchOffers(),
        throwsA(
          isA<RideMatchOfferException>().having(
            (error) => error.reason,
            'reason',
            isNull,
          ),
        ),
      );
    },
  );

  test('invalid location and unexpected nested fields fail closed', () {
    final invalidCoordinate = _offerMap();

    invalidCoordinate['pickup'] = {
      'latitude': 91,
      'longitude': 29,
      'addressLabel': 'Pickup',
    };

    expect(
      () => RideMatchOffer.fromMap(invalidCoordinate),
      throwsFormatException,
    );

    final nestedIdentity = _offerMap();

    nestedIdentity['pickup'] = {
      'latitude': 41.0,
      'longitude': 29.0,
      'addressLabel': 'Pickup',
      'passengerId': 'secret',
    };

    expect(() => RideMatchOffer.fromMap(nestedIdentity), throwsFormatException);
  });
}

Map<String, dynamic> _offerMap([String rideId = 'ride_1']) => {
  'rideId': rideId,
  'rideVersion': 1,
  'pickup': {
    'latitude': 41.0082,
    'longitude': 28.9784,
    'addressLabel': 'Pickup',
  },
  'dropoff': {
    'latitude': 41.0151,
    'longitude': 28.9795,
    'addressLabel': 'Dropoff',
  },
  'expiresAtMillis': 1893456000000,
};

class _Invoker implements RideCallableInvoker {
  Map<String, dynamic> response = {};
  RideGatewayException? error;
  String? name;
  Map<String, dynamic> payload = {};
  int calls = 0;

  @override
  Future<Map<String, dynamic>> call(
    String callable,
    Map<String, dynamic> data,
  ) async {
    calls++;
    name = callable;
    payload = Map<String, dynamic>.of(data);

    if (error case final failure?) {
      throw failure;
    }

    return response;
  }
}
