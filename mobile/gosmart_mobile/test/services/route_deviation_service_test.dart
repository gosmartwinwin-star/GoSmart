import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/matching/matching_policy.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/return_route/route_anchor_result.dart';
import 'package:gosmart_mobile/services/route_deviation_service.dart';

void main() {
  final pickupAnchor = GeoCoordinate(latitude: 41.0, longitude: 29.0);
  final pickup = GeoCoordinate(latitude: 41.001, longitude: 29.001);
  final dropoff = GeoCoordinate(latitude: 41.01, longitude: 29.01);
  final dropoffAnchor = GeoCoordinate(latitude: 41.011, longitude: 29.011);

  RouteAnchorResult anchors({int pickupIndex = 2, int dropoffIndex = 8}) {
    return RouteAnchorResult(
      pickupRouteIndex: pickupIndex,
      dropoffRouteIndex: dropoffIndex,
      pickupAnchor: pickupAnchor,
      dropoffAnchor: dropoffAnchor,
      pickupAnchorProximityMeters: 125.5,
      dropoffAnchorProximityMeters: 210.25,
    );
  }

  Map<String, Object?> validResponse({
    Object? pickupMeters = 1200,
    Object? pickupSeconds = 240,
    Object? dropoffMeters = 1800,
    Object? dropoffSeconds = 360,
  }) => {
    'pickupDetourMeters': pickupMeters,
    'pickupDetourSeconds': pickupSeconds,
    'dropoffDetourMeters': dropoffMeters,
    'dropoffDetourSeconds': dropoffSeconds,
  };

  Future<RouteDeviationResult> computeWith(
    Object? response, {
    RouteAnchorResult? routeAnchors,
    _FakeRouteDeviationInvoker? fake,
  }) {
    final invoker = fake ?? _FakeRouteDeviationInvoker(response);
    return RouteDeviationService(invoker: invoker).compute(
      anchors: routeAnchors ?? anchors(),
      pickup: pickup,
      dropoff: dropoff,
    );
  }

  group('RouteDeviationService response', () {
    test('geçerli yanıtı RouteDeviationResult modeline çevirir', () async {
      final result = await computeWith(validResponse());

      expect(result, isA<RouteDeviationResult>());
    });

    test('pickup ölçümlerini doğru aktarır', () async {
      final result = await computeWith(validResponse());

      expect(result.pickupDetourMeters, 1200);
      expect(result.pickupDetourSeconds, 240);
    });

    test('dropoff ölçümlerini doğru aktarır', () async {
      final result = await computeWith(validResponse());

      expect(result.dropoffDetourMeters, 1800);
      expect(result.dropoffDetourSeconds, 360);
    });

    test('anchor indekslerini aynen korur', () async {
      final result = await computeWith(
        validResponse(),
        routeAnchors: anchors(pickupIndex: 4, dropoffIndex: 11),
      );

      expect(result.pickupRouteIndex, 4);
      expect(result.dropoffRouteIndex, 11);
    });

    test('ters yönlü anchorları callable çağrısından önce reddeder', () async {
      final fake = _FakeRouteDeviationInvoker(validResponse());

      await expectLater(
        computeWith(
          validResponse(),
          routeAnchors: anchors(pickupIndex: 8, dropoffIndex: 2),
          fake: fake,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.callCount, 0);
    });

    test('eşit anchor indekslerini callable öncesinde reddeder', () async {
      final fake = _FakeRouteDeviationInvoker(validResponse());

      await expectLater(
        computeWith(
          validResponse(),
          routeAnchors: anchors(pickupIndex: 5, dropoffIndex: 5),
          fake: fake,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.callCount, 0);
    });

    for (final missingKey in [
      'pickupDetourMeters',
      'pickupDetourSeconds',
      'dropoffDetourMeters',
      'dropoffDetourSeconds',
    ]) {
      test('eksik $missingKey değerini reddeder', () async {
        final response = validResponse()..remove(missingKey);

        await expectLater(
          computeWith(response),
          throwsA(isA<RouteDeviationServiceException>()),
        );
      });
    }

    test('String ölçüm değerini reddeder', () async {
      await expectLater(
        computeWith(validResponse(pickupMeters: '1200')),
        throwsA(isA<RouteDeviationServiceException>()),
      );
    });

    test('tam sayı olmayan double değerini reddeder', () async {
      await expectLater(
        computeWith(validResponse(pickupMeters: 1200.5)),
        throwsA(isA<RouteDeviationServiceException>()),
      );
    });

    test('negatif ölçüm değerini reddeder', () async {
      await expectLater(
        computeWith(validResponse(dropoffSeconds: -1)),
        throwsA(isA<RouteDeviationServiceException>()),
      );
    });

    test('sıfır ölçüm değerlerini kabul eder', () async {
      final result = await computeWith(
        validResponse(
          pickupMeters: 0,
          pickupSeconds: 0,
          dropoffMeters: 0,
          dropoffSeconds: 0,
        ),
      );

      expect(result.totalDetourMeters, 0);
      expect(result.totalExtraDurationSeconds, 0);
    });
  });

  group('RouteDeviationService payload', () {
    test('dört koordinatı doğru yönlerde gönderir', () async {
      final fake = _FakeRouteDeviationInvoker(validResponse());

      await computeWith(validResponse(), fake: fake);

      expect(fake.payload?['pickupAnchor'], _coordinateMap(pickupAnchor));
      expect(fake.payload?['pickup'], _coordinateMap(pickup));
      expect(fake.payload?['dropoff'], _coordinateMap(dropoff));
      expect(fake.payload?['dropoffAnchor'], _coordinateMap(dropoffAnchor));
    });

    test('pickup ve dropoff indekslerini doğru gönderir', () async {
      final fake = _FakeRouteDeviationInvoker(validResponse());

      await computeWith(validResponse(), fake: fake);

      expect(fake.payload?['pickupRouteIndex'], 2);
      expect(fake.payload?['dropoffRouteIndex'], 8);
    });

    test('geometrik proximity değerlerini payload içine göndermez', () async {
      final fake = _FakeRouteDeviationInvoker(validResponse());

      await computeWith(validResponse(), fake: fake);

      expect(fake.payload?.containsKey('pickupAnchorProximityMeters'), isFalse);
      expect(
        fake.payload?.containsKey('dropoffAnchorProximityMeters'),
        isFalse,
      );
      expect(fake.payload?.length, 6);
    });
  });

  group('MatchingPolicy bağlantısı', () {
    test('3000 metre ve 600 saniye sınırlarında uygun sonuç üretir', () async {
      final deviation = await computeWith(
        validResponse(
          pickupMeters: 3000,
          pickupSeconds: 600,
          dropoffMeters: 3000,
          dropoffSeconds: 600,
        ),
      );
      final evaluation = const MatchingPolicy().evaluate(
        subscriptionActive: true,
        deviation: deviation,
      );

      expect(evaluation.isEligible, isTrue);
    });

    test('pickup 3001 metrede pickup_distance_exceeded üretir', () async {
      final deviation = await computeWith(validResponse(pickupMeters: 3001));
      final evaluation = const MatchingPolicy().evaluate(
        subscriptionActive: true,
        deviation: deviation,
      );

      expect(
        evaluation.rejectionReasons,
        contains(MatchingPolicy.pickupDistanceExceededReason),
      );
    });

    test('dropoff 601 saniyede dropoff_duration_exceeded üretir', () async {
      final deviation = await computeWith(validResponse(dropoffSeconds: 601));
      final evaluation = const MatchingPolicy().evaluate(
        subscriptionActive: true,
        deviation: deviation,
      );

      expect(
        evaluation.rejectionReasons,
        contains(MatchingPolicy.dropoffDurationExceededReason),
      );
    });
  });
}

Map<String, Object?> _coordinateMap(GeoCoordinate coordinate) => {
  'latitude': coordinate.latitude,
  'longitude': coordinate.longitude,
};

class _FakeRouteDeviationInvoker implements RouteDeviationCallableInvoker {
  final Object? response;
  int callCount = 0;
  Map<String, Object?>? payload;

  _FakeRouteDeviationInvoker(this.response);

  @override
  Future<Object?> invoke(Map<String, Object?> payload) async {
    callCount++;
    this.payload = payload;
    return response;
  }
}
