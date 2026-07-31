import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/matching/match_orchestration_rejection_codes.dart';
import 'package:gosmart_mobile/application/matching/return_route_match_orchestrator.dart';
import 'package:gosmart_mobile/application/matching/return_route_match_result.dart';
import 'package:gosmart_mobile/application/matching/route_deviation_gateway.dart';
import 'package:gosmart_mobile/domain/matching/matching_policy.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/return_route/route_anchor_locator.dart';
import 'package:gosmart_mobile/domain/return_route/route_anchor_result.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 12);
  final routePoints = [
    GeoCoordinate(latitude: 41.00, longitude: 29.00),
    GeoCoordinate(latitude: 41.01, longitude: 29.01),
    GeoCoordinate(latitude: 41.02, longitude: 29.02),
  ];
  final pickup = routePoints.first;
  final dropoff = routePoints.last;

  DriverAccessPass activePass({
    String driverId = 'driver-1',
    DriverPassStatus status = DriverPassStatus.active,
    DateTime? expiresAt,
  }) {
    return DriverAccessPass(
      id: 'pass-1',
      driverId: driverId,
      plan: DriverPassPlan.daily,
      status: status,
      purchasedAt: now.subtract(const Duration(hours: 2)),
      activatedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: expiresAt ?? now.add(const Duration(hours: 2)),
    );
  }

  DriverReturnRoute returnRoute({
    String driverId = 'driver-1',
    DriverReturnRouteStatus status = DriverReturnRouteStatus.active,
    bool calculated = true,
    DateTime? activatedAt,
    DateTime? expiresAt,
  }) {
    return DriverReturnRoute(
      id: 'route-1',
      driverId: driverId,
      origin: routePoints.first,
      destination: routePoints.last,
      status: status,
      createdAt: now.subtract(const Duration(hours: 2)),
      activatedAt: activatedAt ?? now.subtract(const Duration(hours: 1)),
      expiresAt: expiresAt ?? now.add(const Duration(hours: 2)),
      routeDistanceMeters: calculated ? 10000 : null,
      routeDurationSeconds: calculated ? 1200 : null,
      routePoints: calculated ? routePoints : const [],
    );
  }

  Future<ReturnRouteMatchResult> evaluate({
    DriverAccessPass? pass,
    DriverReturnRoute? route,
    GeoCoordinate? customerPickup,
    GeoCoordinate? customerDropoff,
    DateTime? evaluationTime,
    _FakeDeviationGateway? gateway,
    RouteAnchorLocator? locator,
  }) {
    final selectedGateway = gateway ?? _FakeDeviationGateway();
    return ReturnRouteMatchOrchestrator(
      deviationGateway: selectedGateway,
      anchorLocator: locator ?? const RouteAnchorLocator(),
    ).evaluate(
      pass: pass ?? activePass(),
      returnRoute: route ?? returnRoute(),
      pickup: customerPickup ?? pickup,
      dropoff: customerDropoff ?? dropoff,
      now: evaluationTime ?? now,
    );
  }

  group('Başarılı orkestrasyon', () {
    test('bütün kontroller geçtiğinde uygun sonuç üretir', () async {
      final result = await evaluate();

      expect(result.isEligible, isTrue);
      expect(result.measurementPerformed, isTrue);
    });

    test('geçerli ön kontrollerde gateway tam bir kez çağrılır', () async {
      final gateway = _FakeDeviationGateway();

      await evaluate(gateway: gateway);

      expect(gateway.callCount, 1);
    });

    test('gateway doğru pickup ve dropoff koordinatlarını alır', () async {
      final gateway = _FakeDeviationGateway();

      await evaluate(gateway: gateway);

      expect(gateway.pickup, pickup);
      expect(gateway.dropoff, dropoff);
    });

    test('gateway locator tarafından üretilen anchor nesnesini alır', () async {
      final fixedAnchors = _anchors(0, 2);
      final locator = _FixedAnchorLocator(fixedAnchors);
      final gateway = _FakeDeviationGateway();

      await evaluate(gateway: gateway, locator: locator);

      expect(identical(gateway.anchors, fixedAnchors), isTrue);
    });

    test('gateway sonucundaki anchor indeksleri korunur', () async {
      final result = await evaluate();

      expect(
        result.deviation?.pickupRouteIndex,
        result.anchors?.pickupRouteIndex,
      );
      expect(
        result.deviation?.dropoffRouteIndex,
        result.anchors?.dropoffRouteIndex,
      );
    });

    test(
      'başarılı gateway çağrısından sonra measurementPerformed true olur',
      () async {
        final result = await evaluate();

        expect(result.measurementPerformed, isTrue);
      },
    );
  });

  group('Ön kontrol retleri', () {
    test('null pass subscription_required üretir ve ölçüm yapmaz', () async {
      final gateway = _FakeDeviationGateway();
      final locator = _SpyAnchorLocator();

      final result =
          await ReturnRouteMatchOrchestrator(
            deviationGateway: gateway,
            anchorLocator: locator,
          ).evaluate(
            pass: null,
            returnRoute: returnRoute(),
            pickup: pickup,
            dropoff: dropoff,
            now: now,
          );

      expect(result.rejectionReasons, [
        MatchOrchestrationRejectionCodes.subscriptionRequired,
      ]);
      expect(result.subscriptionActive, isFalse);
      expect(result.measurementPerformed, isFalse);
      expect(gateway.callCount, 0);
      expect(locator.callCount, 0);
    });

    for (final status in [DriverPassStatus.pending, DriverPassStatus.expired]) {
      test('$status pass subscription_required üretir', () async {
        final gateway = _FakeDeviationGateway();
        final result = await evaluate(
          pass: activePass(status: status),
          gateway: gateway,
        );

        expect(
          result.rejectionReasons,
          contains(MatchOrchestrationRejectionCodes.subscriptionRequired),
        );
        expect(gateway.callCount, 0);
      });
    }

    test('süresi bitmiş pass subscription_required üretir', () async {
      final gateway = _FakeDeviationGateway();
      final result = await evaluate(
        pass: activePass(expiresAt: now),
        gateway: gateway,
      );

      expect(result.rejectionReasons, [
        MatchOrchestrationRejectionCodes.subscriptionRequired,
      ]);
      expect(gateway.callCount, 0);
    });

    test('farklı driverId driver_identity_mismatch üretir', () async {
      final gateway = _FakeDeviationGateway();
      final locator = _SpyAnchorLocator();
      final result = await evaluate(
        pass: activePass(driverId: 'driver-2'),
        gateway: gateway,
        locator: locator,
      );

      expect(result.rejectionReasons, [
        MatchOrchestrationRejectionCodes.driverIdentityMismatch,
      ]);
      expect(result.driverIdentityCompatible, isFalse);
      expect(gateway.callCount, 0);
      expect(locator.callCount, 0);
    });

    test('hesaplanmamış rota return_route_not_calculated üretir', () async {
      final gateway = _FakeDeviationGateway();
      final result = await evaluate(
        route: returnRoute(
          status: DriverReturnRouteStatus.draft,
          calculated: false,
        ),
        gateway: gateway,
      );

      expect(result.rejectionReasons, [
        MatchOrchestrationRejectionCodes.returnRouteNotCalculated,
      ]);
      expect(gateway.callCount, 0);
    });

    for (final status in [
      DriverReturnRouteStatus.paused,
      DriverReturnRouteStatus.completed,
    ]) {
      test('$status rota return_route_inactive üretir', () async {
        final gateway = _FakeDeviationGateway();
        final result = await evaluate(
          route: returnRoute(status: status),
          gateway: gateway,
        );

        expect(result.rejectionReasons, [
          MatchOrchestrationRejectionCodes.returnRouteInactive,
        ]);
        expect(gateway.callCount, 0);
      });
    }

    test('gelecekte aktive olacak rota return_route_inactive üretir', () async {
      final gateway = _FakeDeviationGateway();
      final result = await evaluate(
        route: returnRoute(
          activatedAt: now.add(const Duration(minutes: 1)),
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        gateway: gateway,
      );

      expect(result.rejectionReasons, [
        MatchOrchestrationRejectionCodes.returnRouteInactive,
      ]);
      expect(gateway.callCount, 0);
    });

    test('tam expiresAt anında return_route_expired üretir', () async {
      final gateway = _FakeDeviationGateway();
      final result = await evaluate(
        route: returnRoute(expiresAt: now),
        gateway: gateway,
      );

      expect(result.rejectionReasons, [
        MatchOrchestrationRejectionCodes.returnRouteExpired,
      ]);
      expect(gateway.callCount, 0);
    });

    test('expiresAt sonrasında return_route_expired üretir', () async {
      final gateway = _FakeDeviationGateway();
      final result = await evaluate(
        route: returnRoute(expiresAt: now.subtract(const Duration(seconds: 1))),
        gateway: gateway,
      );

      expect(result.rejectionReasons, [
        MatchOrchestrationRejectionCodes.returnRouteExpired,
      ]);
      expect(gateway.callCount, 0);
    });

    test(
      'ters anchor incompatible_direction üretir ve gateway çağırmaz',
      () async {
        final gateway = _FakeDeviationGateway();
        final result = await evaluate(
          customerPickup: dropoff,
          customerDropoff: pickup,
          gateway: gateway,
        );

        expect(result.rejectionReasons, [
          MatchingPolicy.incompatibleDirectionReason,
        ]);
        expect(result.anchors?.pickupRouteIndex, 2);
        expect(result.anchors?.dropoffRouteIndex, 0);
        expect(gateway.callCount, 0);
      },
    );

    test(
      'eşit anchor incompatible_direction üretir ve gateway çağırmaz',
      () async {
        final gateway = _FakeDeviationGateway();
        final result = await evaluate(
          customerPickup: routePoints[1],
          customerDropoff: routePoints[1],
          gateway: gateway,
        );

        expect(result.rejectionReasons, [
          MatchingPolicy.incompatibleDirectionReason,
        ]);
        expect(gateway.callCount, 0);
      },
    );

    test('ön kontrol reddinde measurementPerformed false olur', () async {
      final result =
          await ReturnRouteMatchOrchestrator(
            deviationGateway: _FakeDeviationGateway(),
          ).evaluate(
            pass: null,
            returnRoute: returnRoute(),
            pickup: pickup,
            dropoff: dropoff,
            now: now,
          );

      expect(result.measurementPerformed, isFalse);
      expect(result.deviation, isNull);
    });
  });

  group('MatchingPolicy değerlendirmesi', () {
    test('geometrik proximity değerleri sapma olarak kullanılmaz', () async {
      final fixedAnchors = _anchors(0, 2, proximity: 5000);
      final result = await evaluate(
        locator: _FixedAnchorLocator(fixedAnchors),
        gateway: _FakeDeviationGateway(
          pickupMeters: 1000,
          pickupSeconds: 200,
          dropoffMeters: 1000,
          dropoffSeconds: 200,
        ),
      );

      expect(result.isEligible, isTrue);
      expect(result.deviation?.pickupDetourMeters, 1000);
      expect(result.deviation?.dropoffDetourMeters, 1000);
    });

    test('pickup 3000 metre ve 600 saniyede uygundur', () async {
      final result = await evaluate(
        gateway: _FakeDeviationGateway(pickupMeters: 3000, pickupSeconds: 600),
      );

      expect(result.matchingEvaluation?.pickupEligible, isTrue);
      expect(result.isEligible, isTrue);
    });

    test('dropoff 3000 metre ve 600 saniyede uygundur', () async {
      final result = await evaluate(
        gateway: _FakeDeviationGateway(
          dropoffMeters: 3000,
          dropoffSeconds: 600,
        ),
      );

      expect(result.matchingEvaluation?.dropoffEligible, isTrue);
      expect(result.isEligible, isTrue);
    });

    final violations = <String, _FakeDeviationGateway>{
      MatchingPolicy.pickupDistanceExceededReason: _FakeDeviationGateway(
        pickupMeters: 3001,
      ),
      MatchingPolicy.pickupDurationExceededReason: _FakeDeviationGateway(
        pickupSeconds: 601,
      ),
      MatchingPolicy.dropoffDistanceExceededReason: _FakeDeviationGateway(
        dropoffMeters: 3001,
      ),
      MatchingPolicy.dropoffDurationExceededReason: _FakeDeviationGateway(
        dropoffSeconds: 601,
      ),
    };

    for (final entry in violations.entries) {
      test('${entry.key} nedeni korunur', () async {
        final result = await evaluate(gateway: entry.value);

        expect(result.rejectionReasons, contains(entry.key));
        expect(result.isEligible, isFalse);
      });
    }

    test('birden fazla sapma ihlalinin tüm nedenlerini korur', () async {
      final result = await evaluate(
        gateway: _FakeDeviationGateway(
          pickupMeters: 3001,
          pickupSeconds: 601,
          dropoffMeters: 3001,
          dropoffSeconds: 601,
        ),
      );

      expect(result.rejectionReasons, [
        MatchingPolicy.pickupDistanceExceededReason,
        MatchingPolicy.pickupDurationExceededReason,
        MatchingPolicy.dropoffDistanceExceededReason,
        MatchingPolicy.dropoffDurationExceededReason,
      ]);
      expect(
        result.rejectionReasons,
        result.matchingEvaluation?.rejectionReasons,
      );
    });
  });

  group('Sonuç ve altyapı güvenliği', () {
    test(
      'gateway exception iş kuralı sonucuna çevrilmeden aktarılır',
      () async {
        final exception = _GatewayTestException();

        await expectLater(
          evaluate(gateway: _FakeDeviationGateway(exception: exception)),
          throwsA(same(exception)),
        );
      },
    );

    test(
      'uyuşmayan gateway indeksleri altyapı sözleşme hatası üretir',
      () async {
        await expectLater(
          evaluate(gateway: _FakeDeviationGateway(indexOffset: 1)),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('rejectionReasons dışarıdan değiştirilemez', () async {
      final result = await evaluate(
        gateway: _FakeDeviationGateway(pickupMeters: 3001),
      );

      expect(
        () => result.rejectionReasons.add('another_reason'),
        throwsUnsupportedError,
      );
    });

    test('ret kodlarını tekrar etmeden deterministik sırada tutar', () {
      final result = ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: false,
        driverIdentityCompatible: false,
        returnRouteReady: false,
        rejectionReasons: const ['first', 'second', 'first', 'third'],
      );

      expect(result.rejectionReasons, ['first', 'second', 'third']);
    });

    test('verilen now değeri expiry sınırında doğrudan kullanılır', () async {
      final expiration = now.add(const Duration(minutes: 5));
      final route = returnRoute(expiresAt: expiration);
      final before = await evaluate(
        route: route,
        evaluationTime: expiration.subtract(const Duration(microseconds: 1)),
      );
      final atBoundary = await evaluate(
        route: route,
        evaluationTime: expiration,
      );

      expect(before.measurementPerformed, isTrue);
      expect(atBoundary.rejectionReasons, [
        MatchOrchestrationRejectionCodes.returnRouteExpired,
      ]);
    });
  });
}

RouteAnchorResult _anchors(
  int pickupIndex,
  int dropoffIndex, {
  double proximity = 0,
}) {
  return RouteAnchorResult(
    pickupRouteIndex: pickupIndex,
    dropoffRouteIndex: dropoffIndex,
    pickupAnchor: GeoCoordinate(latitude: 41, longitude: 29),
    dropoffAnchor: GeoCoordinate(latitude: 41.02, longitude: 29.02),
    pickupAnchorProximityMeters: proximity,
    dropoffAnchorProximityMeters: proximity,
  );
}

class _FakeDeviationGateway implements RouteDeviationGateway {
  final int pickupMeters;
  final int pickupSeconds;
  final int dropoffMeters;
  final int dropoffSeconds;
  final Object? exception;
  final int indexOffset;

  int callCount = 0;
  RouteAnchorResult? anchors;
  GeoCoordinate? pickup;
  GeoCoordinate? dropoff;

  _FakeDeviationGateway({
    this.pickupMeters = 1000,
    this.pickupSeconds = 200,
    this.dropoffMeters = 1000,
    this.dropoffSeconds = 200,
    this.exception,
    this.indexOffset = 0,
  });

  @override
  Future<RouteDeviationResult> compute({
    required RouteAnchorResult anchors,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
  }) async {
    callCount++;
    this.anchors = anchors;
    this.pickup = pickup;
    this.dropoff = dropoff;

    final failure = exception;
    if (failure != null) throw failure;

    return RouteDeviationResult(
      pickupDetourMeters: pickupMeters,
      pickupDetourSeconds: pickupSeconds,
      dropoffDetourMeters: dropoffMeters,
      dropoffDetourSeconds: dropoffSeconds,
      pickupRouteIndex: anchors.pickupRouteIndex + indexOffset,
      dropoffRouteIndex: anchors.dropoffRouteIndex + indexOffset,
    );
  }
}

class _FixedAnchorLocator extends RouteAnchorLocator {
  final RouteAnchorResult result;

  const _FixedAnchorLocator(this.result);

  @override
  RouteAnchorResult locate({
    required DriverReturnRoute route,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
  }) => result;
}

class _SpyAnchorLocator extends RouteAnchorLocator {
  int callCount = 0;

  @override
  RouteAnchorResult locate({
    required DriverReturnRoute route,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
  }) {
    callCount++;
    return super.locate(route: route, pickup: pickup, dropoff: dropoff);
  }
}

class _GatewayTestException implements Exception {}
