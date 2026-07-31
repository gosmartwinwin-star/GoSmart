import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/matching/matching_policy.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/return_route/geo_distance.dart';
import 'package:gosmart_mobile/domain/return_route/route_anchor_locator.dart';
import 'package:gosmart_mobile/domain/return_route/route_anchor_result.dart';

void main() {
  final now = DateTime.utc(2026, 8, 3, 12);
  const locator = RouteAnchorLocator();

  GeoCoordinate coordinate(double latitude, double longitude) {
    return GeoCoordinate(latitude: latitude, longitude: longitude);
  }

  DriverReturnRoute calculatedRoute(List<GeoCoordinate> points) {
    return DriverReturnRoute(
      id: 'route-1',
      driverId: 'driver-1',
      origin: points.first,
      destination: points.last,
      status: DriverReturnRouteStatus.active,
      createdAt: now.subtract(const Duration(hours: 2)),
      activatedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(hours: 2)),
      routeDistanceMeters: 10000,
      routeDurationSeconds: 1200,
      routePoints: points,
    );
  }

  final points = [
    coordinate(41.00, 29.00),
    coordinate(41.01, 29.01),
    coordinate(41.02, 29.02),
    coordinate(41.03, 29.03),
    coordinate(41.04, 29.04),
    coordinate(41.05, 29.05),
  ];

  group('GeoDistance', () {
    test('aynı koordinatlar için sıfır metre döndürür', () {
      expect(GeoDistance.betweenMeters(points.first, points.first), 0);
    });

    test('sonuç negatif değildir', () {
      expect(
        GeoDistance.betweenMeters(points.first, points.last),
        greaterThanOrEqualTo(0),
      );
    });

    test('bir derece latitude farkını makul aralıkta hesaplar', () {
      final distance = GeoDistance.betweenMeters(
        coordinate(0, 0),
        coordinate(1, 0),
      );

      expect(distance, inInclusiveRange(110000, 112000));
    });

    test('koordinat sırası ters çevrildiğinde simetriktir', () {
      final forward = GeoDistance.betweenMeters(points.first, points.last);
      final reverse = GeoDistance.betweenMeters(points.last, points.first);

      expect(reverse, closeTo(forward, 0.000001));
    });

    test('tarih değiştirme çizgisi yakınında sonlu sonuç üretir', () {
      final distance = GeoDistance.betweenMeters(
        coordinate(0, 179.9),
        coordinate(0, -179.9),
      );

      expect(distance.isFinite, isTrue);
      expect(distance, greaterThan(0));
    });
  });

  group('RouteAnchorLocator', () {
    test(
      'başlangıca yakın pickup ve sona yakın dropoff indekslerini bulur',
      () {
        final result = locator.locate(
          route: calculatedRoute(points),
          pickup: coordinate(41.0001, 29.0001),
          dropoff: coordinate(41.0499, 29.0499),
        );

        expect(result.pickupRouteIndex, 0);
        expect(result.dropoffRouteIndex, 5);
      },
    );

    test('doğru sıralı indekslerde directionCompatible true döner', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: points[1],
        dropoff: points[4],
      );

      expect(result.directionCompatible, isTrue);
    });

    test('ters sıralı indekslerde directionCompatible false döner', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: points[4],
        dropoff: points[1],
      );

      expect(result.pickupRouteIndex, 4);
      expect(result.dropoffRouteIndex, 1);
      expect(result.directionCompatible, isFalse);
    });

    test('aynı rota indeksinde directionCompatible false döner', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: points[2],
        dropoff: points[2],
      );

      expect(result.pickupRouteIndex, result.dropoffRouteIndex);
      expect(result.directionCompatible, isFalse);
    });

    test('eşit mesafede düşük indeksi seçer', () {
      final equidistantPoints = [coordinate(0, -1), coordinate(0, 1)];
      final result = locator.locate(
        route: calculatedRoute(equidistantPoints),
        pickup: coordinate(0, 0),
        dropoff: equidistantPoints.last,
      );

      expect(result.pickupRouteIndex, 0);
    });

    test('pickup anchor route point ile aynıdır', () {
      final route = calculatedRoute(points);
      final result = locator.locate(
        route: route,
        pickup: points[2],
        dropoff: points[5],
      );

      expect(result.pickupAnchor, route.pointAt(result.pickupRouteIndex));
    });

    test('dropoff anchor route point ile aynıdır', () {
      final route = calculatedRoute(points);
      final result = locator.locate(
        route: route,
        pickup: points.first,
        dropoff: points[3],
      );

      expect(result.dropoffAnchor, route.pointAt(result.dropoffRouteIndex));
    });

    test('yakınlık değerleri negatif değildir', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: coordinate(41.015, 29.015),
        dropoff: coordinate(41.035, 29.035),
      );

      expect(result.pickupAnchorProximityMeters, greaterThanOrEqualTo(0));
      expect(result.dropoffAnchorProximityMeters, greaterThanOrEqualTo(0));
    });

    test('toplam yakınlık iki bağımsız yakınlığın toplamıdır', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: coordinate(41.015, 29.015),
        dropoff: coordinate(41.035, 29.035),
      );

      expect(
        result.totalAnchorProximityMeters,
        result.pickupAnchorProximityMeters +
            result.dropoffAnchorProximityMeters,
      );
    });

    test('rota noktası üzerindeki pickup yakınlığı sıfırdır', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: points[2],
        dropoff: points[4],
      );

      expect(result.pickupAnchorProximityMeters, closeTo(0, 0.000001));
    });

    test('rota noktası üzerindeki dropoff yakınlığı sıfırdır', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: points[1],
        dropoff: points[4],
      );

      expect(result.dropoffAnchorProximityMeters, closeTo(0, 0.000001));
    });

    test('hesaplanmış rotası olmayan modelde StateError üretir', () {
      final draft = DriverReturnRoute(
        id: 'route-1',
        driverId: 'driver-1',
        origin: points.first,
        destination: points.last,
        status: DriverReturnRouteStatus.draft,
        createdAt: now,
      );

      expect(
        () => locator.locate(
          route: draft,
          pickup: points.first,
          dropoff: points.last,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('çok noktalı rotada doğru en yakın indeksleri bulur', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: coordinate(41.0399, 29.0401),
        dropoff: coordinate(41.0101, 29.0099),
      );

      expect(result.pickupRouteIndex, 4);
      expect(result.dropoffRouteIndex, 1);
    });

    test('routePoints listesini değiştirmez', () {
      final route = calculatedRoute(points);
      final before = List<GeoCoordinate>.from(route.routePoints);

      locator.locate(route: route, pickup: points[1], dropoff: points[4]);

      expect(route.routePoints, orderedEquals(before));
    });

    test('pickup ve dropoff anchorlarını bağımsız hesaplar', () {
      final result = locator.locate(
        route: calculatedRoute(points),
        pickup: points[4],
        dropoff: points[1],
      );

      expect(result.pickupRouteIndex, 4);
      expect(result.dropoffRouteIndex, 1);
    });
  });

  group('RouteAnchorResult doğrulaması', () {
    test('negatif indeksleri reddeder', () {
      expect(
        () => RouteAnchorResult(
          pickupRouteIndex: -1,
          dropoffRouteIndex: 1,
          pickupAnchor: points.first,
          dropoffAnchor: points.last,
          pickupAnchorProximityMeters: 0,
          dropoffAnchorProximityMeters: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('negatif veya sonlu olmayan yakınlıkları reddeder', () {
      expect(
        () => RouteAnchorResult(
          pickupRouteIndex: 0,
          dropoffRouteIndex: 1,
          pickupAnchor: points.first,
          dropoffAnchor: points.last,
          pickupAnchorProximityMeters: -1,
          dropoffAnchorProximityMeters: double.nan,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('MatchingPolicy veri uyumluluğu', () {
    test('doğru yönlü anchor indeksleri yön uyumlu sonuç üretir', () {
      final anchors = locator.locate(
        route: calculatedRoute(points),
        pickup: points[1],
        dropoff: points[4],
      );

      // Bu değerler anchor yakınlığından değil, doğrulanmış sürüş
      // ölçümlerini temsil eden bağımsız test girdilerinden gelir.
      final deviation = RouteDeviationResult(
        pickupDetourMeters: 1000,
        pickupDetourSeconds: 300,
        dropoffDetourMeters: 1000,
        dropoffDetourSeconds: 300,
        pickupRouteIndex: anchors.pickupRouteIndex,
        dropoffRouteIndex: anchors.dropoffRouteIndex,
      );
      final evaluation = const MatchingPolicy().evaluate(
        subscriptionActive: true,
        deviation: deviation,
      );

      expect(evaluation.directionCompatible, isTrue);
      expect(evaluation.isEligible, isTrue);
    });

    test('ters anchor indeksleri incompatible_direction üretir', () {
      final anchors = locator.locate(
        route: calculatedRoute(points),
        pickup: points[4],
        dropoff: points[1],
      );
      final deviation = RouteDeviationResult(
        pickupDetourMeters: 1000,
        pickupDetourSeconds: 300,
        dropoffDetourMeters: 1000,
        dropoffDetourSeconds: 300,
        pickupRouteIndex: anchors.pickupRouteIndex,
        dropoffRouteIndex: anchors.dropoffRouteIndex,
      );
      final evaluation = const MatchingPolicy().evaluate(
        subscriptionActive: true,
        deviation: deviation,
      );

      expect(
        evaluation.rejectionReasons,
        contains(MatchingPolicy.incompatibleDirectionReason),
      );
    });
  });
}
