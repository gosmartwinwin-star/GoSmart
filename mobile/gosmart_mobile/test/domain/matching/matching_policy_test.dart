import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/matching/matching_policy.dart';

void main() {
  const policy = MatchingPolicy();

  RouteDeviationResult deviation({
    int pickupMeters = 2000,
    int pickupSeconds = 300,
    int dropoffMeters = 2000,
    int dropoffSeconds = 300,
    int pickupIndex = 10,
    int dropoffIndex = 20,
  }) {
    return RouteDeviationResult(
      pickupDetourMeters: pickupMeters,
      pickupDetourSeconds: pickupSeconds,
      dropoffDetourMeters: dropoffMeters,
      dropoffDetourSeconds: dropoffSeconds,
      pickupRouteIndex: pickupIndex,
      dropoffRouteIndex: dropoffIndex,
    );
  }

  group('MatchingPolicy', () {
    test('uygun sapmalar, aktif abonelik ve doğru yön eşleşir', () {
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: deviation(),
      );

      expect(result.isEligible, isTrue);
      expect(result.rejectionReasons, isEmpty);
    });

    test('3001 metre pickup sapmasını reddeder', () {
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: deviation(pickupMeters: 3001),
      );

      expect(result.isEligible, isFalse);
      expect(
        result.rejectionReasons,
        contains(MatchingPolicy.pickupDistanceExceededReason),
      );
    });

    test('601 saniye pickup sapmasını reddeder', () {
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: deviation(pickupSeconds: 601),
      );

      expect(result.isEligible, isFalse);
      expect(
        result.rejectionReasons,
        contains(MatchingPolicy.pickupDurationExceededReason),
      );
    });

    test('3001 metre dropoff sapmasını reddeder', () {
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: deviation(dropoffMeters: 3001),
      );

      expect(result.isEligible, isFalse);
      expect(
        result.rejectionReasons,
        contains(MatchingPolicy.dropoffDistanceExceededReason),
      );
    });

    test('601 saniye dropoff sapmasını reddeder', () {
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: deviation(dropoffSeconds: 601),
      );

      expect(result.isEligible, isFalse);
      expect(
        result.rejectionReasons,
        contains(MatchingPolicy.dropoffDurationExceededReason),
      );
    });

    test('toplam 5 km olsa da 4 km dropoff sapmasını reddeder', () {
      final routeDeviation = deviation(pickupMeters: 1000, dropoffMeters: 4000);
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: routeDeviation,
      );

      expect(routeDeviation.totalDetourMeters, 5000);
      expect(result.pickupEligible, isTrue);
      expect(result.dropoffEligible, isFalse);
      expect(result.isEligible, isFalse);
      expect(
        result.rejectionReasons,
        contains(MatchingPolicy.dropoffDistanceExceededReason),
      );
    });

    test('pickup ve dropoff için 3 km sınırını kabul eder', () {
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: deviation(pickupMeters: 3000, dropoffMeters: 3000),
      );

      expect(result.pickupEligible, isTrue);
      expect(result.dropoffEligible, isTrue);
      expect(result.isEligible, isTrue);
    });

    test('pickup index dropoff index sonrasındaysa yönü reddeder', () {
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: deviation(pickupIndex: 10, dropoffIndex: 5),
      );

      expect(result.directionCompatible, isFalse);
      expect(result.isEligible, isFalse);
      expect(
        result.rejectionReasons,
        contains(MatchingPolicy.incompatibleDirectionReason),
      );
    });

    test('aktif abonelik yoksa eşleşmeyi reddeder', () {
      final result = policy.evaluate(
        subscriptionActive: false,
        deviation: deviation(),
      );

      expect(result.isEligible, isFalse);
      expect(
        result.rejectionReasons,
        contains(MatchingPolicy.subscriptionRequiredReason),
      );
    });

    test('birden fazla ihlalin tüm nedenlerini döndürür', () {
      final result = policy.evaluate(
        subscriptionActive: false,
        deviation: deviation(
          pickupMeters: 3001,
          pickupSeconds: 601,
          dropoffMeters: 3001,
          dropoffSeconds: 601,
          pickupIndex: 10,
          dropoffIndex: 10,
        ),
      );

      expect(result.isEligible, isFalse);
      expect(
        result.rejectionReasons,
        unorderedEquals({
          MatchingPolicy.subscriptionRequiredReason,
          MatchingPolicy.pickupDistanceExceededReason,
          MatchingPolicy.pickupDurationExceededReason,
          MatchingPolicy.dropoffDistanceExceededReason,
          MatchingPolicy.dropoffDurationExceededReason,
          MatchingPolicy.incompatibleDirectionReason,
        }),
      );
    });

    test('eşit rota indexlerini uyumlu kabul etmez', () {
      final result = policy.evaluate(
        subscriptionActive: true,
        deviation: deviation(pickupIndex: 10, dropoffIndex: 10),
      );

      expect(result.directionCompatible, isFalse);
      expect(
        result.rejectionReasons,
        contains(MatchingPolicy.incompatibleDirectionReason),
      );
    });
  });

  group('RouteDeviationResult doğrulaması', () {
    test('negatif mesafe, süre ve rota indexlerini reddeder', () {
      expect(() => deviation(pickupMeters: -1), throwsA(isA<ArgumentError>()));
      expect(() => deviation(pickupSeconds: -1), throwsA(isA<ArgumentError>()));
      expect(() => deviation(dropoffMeters: -1), throwsA(isA<ArgumentError>()));
      expect(
        () => deviation(dropoffSeconds: -1),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => deviation(pickupIndex: -1), throwsA(isA<ArgumentError>()));
      expect(() => deviation(dropoffIndex: -1), throwsA(isA<ArgumentError>()));
    });
  });
}
