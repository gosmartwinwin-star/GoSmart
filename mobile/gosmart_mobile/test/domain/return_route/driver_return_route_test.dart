import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_policy.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_policy.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);
  final origin = GeoCoordinate(latitude: 41.0, longitude: 29.0);
  final midpoint = GeoCoordinate(latitude: 41.1, longitude: 29.1);
  final destination = GeoCoordinate(latitude: 41.2, longitude: 29.2);
  const policy = DriverReturnRoutePolicy();

  DriverReturnRoute route({
    String id = 'route-1',
    String driverId = 'driver-1',
    DriverReturnRouteStatus status = DriverReturnRouteStatus.active,
    DateTime? createdAt,
    DateTime? activatedAt,
    DateTime? expiresAt,
    bool includeActivation = true,
    bool includeExpiration = true,
    bool includeDistance = true,
    bool includeDuration = true,
    List<GeoCoordinate>? routePoints,
    GeoCoordinate? routeOrigin,
    GeoCoordinate? routeDestination,
  }) {
    return DriverReturnRoute(
      id: id,
      driverId: driverId,
      origin: routeOrigin ?? origin,
      destination: routeDestination ?? destination,
      status: status,
      createdAt: createdAt ?? now.subtract(const Duration(hours: 2)),
      activatedAt: includeActivation
          ? activatedAt ?? now.subtract(const Duration(hours: 1))
          : null,
      expiresAt: includeExpiration
          ? expiresAt ?? now.add(const Duration(hours: 2))
          : null,
      routeDistanceMeters: includeDistance ? 12000 : null,
      routeDurationSeconds: includeDuration ? 1800 : null,
      routePoints: routePoints ?? [origin, midpoint, destination],
    );
  }

  group('GeoCoordinate', () {
    test('geçerli koordinat oluşturur', () {
      final coordinate = GeoCoordinate(latitude: 41.0, longitude: 29.0);

      expect(coordinate.latitude, 41.0);
      expect(coordinate.longitude, 29.0);
    });

    test('latitude 90 sınırını kabul eder', () {
      expect(GeoCoordinate(latitude: 90, longitude: 0).latitude, 90);
    });

    test('latitude -90 sınırını kabul eder', () {
      expect(GeoCoordinate(latitude: -90, longitude: 0).latitude, -90);
    });

    test('longitude 180 sınırını kabul eder', () {
      expect(GeoCoordinate(latitude: 0, longitude: 180).longitude, 180);
    });

    test('longitude -180 sınırını kabul eder', () {
      expect(GeoCoordinate(latitude: 0, longitude: -180).longitude, -180);
    });

    test('latitude 90 üzerinde olduğunda reddeder', () {
      expect(
        () => GeoCoordinate(latitude: 90.1, longitude: 0),
        throwsA(isA<RangeError>()),
      );
    });

    test('longitude 180 üzerinde olduğunda reddeder', () {
      expect(
        () => GeoCoordinate(latitude: 0, longitude: 180.1),
        throwsA(isA<RangeError>()),
      );
    });

    test('NaN değerini reddeder', () {
      expect(
        () => GeoCoordinate(latitude: double.nan, longitude: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('infinity değerini reddeder', () {
      expect(
        () => GeoCoordinate(latitude: 0, longitude: double.infinity),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('aynı koordinat değerlerini eşit kabul eder', () {
      final first = GeoCoordinate(latitude: 41, longitude: 29);
      final second = GeoCoordinate(latitude: 41, longitude: 29);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('DriverReturnRoute model', () {
    test('geçerli aktif dönüş rotası oluşturur', () {
      final result = route();

      expect(result.status, DriverReturnRouteStatus.active);
      expect(result.hasCalculatedRoute, isTrue);
    });

    test('boş id değerini reddeder', () {
      expect(() => route(id: ' '), throwsA(isA<ArgumentError>()));
    });

    test('boş driverId değerini reddeder', () {
      expect(() => route(driverId: ''), throwsA(isA<ArgumentError>()));
    });

    test('aynı origin ve destination değerini reddeder', () {
      expect(
        () => route(routeDestination: origin),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('sıfır routeDistanceMeters değerini reddeder', () {
      expect(
        () => DriverReturnRoute(
          id: 'route-1',
          driverId: 'driver-1',
          origin: origin,
          destination: destination,
          status: DriverReturnRouteStatus.draft,
          createdAt: now,
          routeDistanceMeters: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('negatif routeDistanceMeters değerini reddeder', () {
      expect(
        () => DriverReturnRoute(
          id: 'route-1',
          driverId: 'driver-1',
          origin: origin,
          destination: destination,
          status: DriverReturnRouteStatus.draft,
          createdAt: now,
          routeDistanceMeters: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('sıfır routeDurationSeconds değerini reddeder', () {
      expect(
        () => DriverReturnRoute(
          id: 'route-1',
          driverId: 'driver-1',
          origin: origin,
          destination: destination,
          status: DriverReturnRouteStatus.draft,
          createdAt: now,
          routeDurationSeconds: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('negatif routeDurationSeconds değerini reddeder', () {
      expect(
        () => DriverReturnRoute(
          id: 'route-1',
          driverId: 'driver-1',
          origin: origin,
          destination: destination,
          status: DriverReturnRouteStatus.draft,
          createdAt: now,
          routeDurationSeconds: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('tek route point değerini reddeder', () {
      expect(() => route(routePoints: [origin]), throwsA(isA<ArgumentError>()));
    });

    test('active statüde activatedAt eksikliğini reddeder', () {
      expect(
        () => route(includeActivation: false),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('active statüde expiresAt eksikliğini reddeder', () {
      expect(
        () => route(includeExpiration: false),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('active statüde mesafe eksikliğini reddeder', () {
      expect(
        () => route(includeDistance: false),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('active statüde süre eksikliğini reddeder', () {
      expect(
        () => route(includeDuration: false),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('active statüde rota noktası eksikliğini reddeder', () {
      expect(() => route(routePoints: const []), throwsA(isA<ArgumentError>()));
    });

    test('expiresAt activatedAt değerine eşitse reddeder', () {
      expect(
        () => route(activatedAt: now, expiresAt: now),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('expiresAt activatedAt değerinden önceyse reddeder', () {
      expect(
        () => route(
          activatedAt: now,
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('createdAt activatedAt değerinden sonraysa reddeder', () {
      expect(
        () => route(
          createdAt: now,
          activatedAt: now.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Aktiflik', () {
    test('tam activatedAt anında aktiftir', () {
      expect(route(activatedAt: now).isActiveAt(now), isTrue);
    });

    test('tam expiresAt anında aktif değildir', () {
      expect(route(expiresAt: now).isActiveAt(now), isFalse);
    });

    test('expiry sonrasında aktif değildir', () {
      expect(
        route(
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ).isActiveAt(now),
        isFalse,
      );
    });

    test('paused durumunda aktif değildir', () {
      expect(
        route(status: DriverReturnRouteStatus.paused).isActiveAt(now),
        isFalse,
      );
    });

    test('aktif rota için remainingAt pozitiftir', () {
      expect(route().remainingAt(now), const Duration(hours: 2));
    });

    test('aktif olmayan rota için remainingAt sıfırdır', () {
      expect(
        route(status: DriverReturnRouteStatus.paused).remainingAt(now),
        Duration.zero,
      );
    });

    test('hasCalculatedRoute hesaplanmış rotada true döner', () {
      expect(route().hasCalculatedRoute, isTrue);
    });

    test('hasCalculatedRoute taslak boş rotada false döner', () {
      final draft = route(
        status: DriverReturnRouteStatus.draft,
        includeDistance: false,
        includeDuration: false,
        routePoints: const [],
      );

      expect(draft.hasCalculatedRoute, isFalse);
    });
  });

  group('DriverReturnRoutePolicy', () {
    test('aktif abonelik ve geçerli rota ile publish izni verir', () {
      expect(
        policy.canPublish(route: route(), subscriptionActive: true, now: now),
        isTrue,
      );
    });

    test('abonelik yoksa publish izni vermez', () {
      expect(
        policy.canPublish(route: route(), subscriptionActive: false, now: now),
        isFalse,
      );
    });

    test('süresi dolmuş rotada publish izni vermez', () {
      expect(
        policy.canPublish(
          route: route(expiresAt: now),
          subscriptionActive: true,
          now: now,
        ),
        isFalse,
      );
    });

    test('hesaplanmamış taslak rotada publish izni vermez', () {
      final draft = route(
        status: DriverReturnRouteStatus.draft,
        includeDistance: false,
        includeDuration: false,
        routePoints: const [],
      );

      expect(
        policy.canPublish(route: draft, subscriptionActive: true, now: now),
        isFalse,
      );
    });

    test('geçerli rota ile match alabilir', () {
      expect(
        policy.canReceiveMatches(
          route: route(),
          subscriptionActive: true,
          now: now,
        ),
        isTrue,
      );
    });

    test('active rota pause edilebilir', () {
      expect(policy.canPause(route: route()), isTrue);
    });

    test('paused rota tekrar pause edilemez', () {
      expect(
        policy.canPause(route: route(status: DriverReturnRouteStatus.paused)),
        isFalse,
      );
    });

    test('paused rota aktif abonelikle resume edilebilir', () {
      expect(
        policy.canResume(
          route: route(status: DriverReturnRouteStatus.paused),
          subscriptionActive: true,
          now: now,
        ),
        isTrue,
      );
    });

    test('abonelik yoksa paused rota resume edilemez', () {
      expect(
        policy.canResume(
          route: route(status: DriverReturnRouteStatus.paused),
          subscriptionActive: false,
          now: now,
        ),
        isFalse,
      );
    });

    test('süresi bitmiş paused rota resume edilemez', () {
      expect(
        policy.canResume(
          route: route(status: DriverReturnRouteStatus.paused, expiresAt: now),
          subscriptionActive: true,
          now: now,
        ),
        isFalse,
      );
    });

    test('active rota complete edilebilir', () {
      expect(policy.canComplete(route: route()), isTrue);
    });

    test('paused rota complete edilebilir', () {
      expect(
        policy.canComplete(
          route: route(status: DriverReturnRouteStatus.paused),
        ),
        isTrue,
      );
    });

    test('completed rota tekrar complete edilemez', () {
      expect(
        policy.canComplete(
          route: route(status: DriverReturnRouteStatus.completed),
        ),
        isFalse,
      );
    });
  });

  group('Tek aktif rota', () {
    test('aynı sürücüde aktif rota varsa yeni rota aktive edilemez', () {
      expect(
        policy.canActivateNewRoute(
          existingRoutes: [route()],
          driverId: 'driver-1',
          now: now,
        ),
        isFalse,
      );
    });

    test('aynı sürücüde yalnızca expired rota varsa aktive edilebilir', () {
      expect(
        policy.canActivateNewRoute(
          existingRoutes: [route(status: DriverReturnRouteStatus.expired)],
          driverId: 'driver-1',
          now: now,
        ),
        isTrue,
      );
    });

    test('başka sürücünün aktif rotası sonucu etkilemez', () {
      expect(
        policy.canActivateNewRoute(
          existingRoutes: [route(driverId: 'driver-2')],
          driverId: 'driver-1',
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('Route points', () {
    test('routePointCount doğru sayıyı döndürür', () {
      expect(route().routePointCount, 3);
    });

    test('pointAt geçerli indexte doğru noktayı döndürür', () {
      expect(route().pointAt(1), midpoint);
    });

    test('pointAt negatif indexte RangeError üretir', () {
      expect(() => route().pointAt(-1), throwsA(isA<RangeError>()));
    });

    test('pointAt liste sınırı dışında RangeError üretir', () {
      expect(() => route().pointAt(3), throwsA(isA<RangeError>()));
    });

    test('kaynak liste sonradan değişse bile model listesi değişmez', () {
      final source = [origin, destination];
      final result = route(routePoints: source);
      source.add(midpoint);

      expect(result.routePointCount, 2);
    });

    test('modelin routePoints listesi değiştirilemez', () {
      expect(() => route().routePoints.add(midpoint), throwsUnsupportedError);
    });
  });

  test('subscription erişimi dönüş rotası policy sonucuna aktarılır', () {
    final pass = DriverAccessPass(
      id: 'pass-1',
      driverId: 'driver-1',
      plan: DriverPassPlan.daily,
      status: DriverPassStatus.active,
      purchasedAt: now.subtract(const Duration(hours: 2)),
      activatedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(hours: 1)),
    );
    final subscriptionActive = const DriverAccessPolicy().canPublishReturnRoute(
      pass: pass,
      now: now,
    );

    expect(
      policy.canPublish(
        route: route(),
        subscriptionActive: subscriptionActive,
        now: now,
      ),
      isTrue,
    );
  });

  test('durumlar Türkçe gösterim adlarını sağlar', () {
    expect(DriverReturnRouteStatus.draft.displayName, 'Taslak');
    expect(DriverReturnRouteStatus.active.displayName, 'Aktif');
    expect(DriverReturnRouteStatus.paused.displayName, 'Duraklatıldı');
    expect(DriverReturnRouteStatus.completed.displayName, 'Tamamlandı');
    expect(DriverReturnRouteStatus.expired.displayName, 'Süresi Doldu');
    expect(DriverReturnRouteStatus.cancelled.displayName, 'İptal Edildi');
  });
}
