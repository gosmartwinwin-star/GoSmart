import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_pass_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/application/return_route/publish_return_route_gateway.dart';
import 'package:gosmart_mobile/application/return_route/published_return_route.dart';
import 'package:gosmart_mobile/controllers/driver_center_controller.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';
import 'package:gosmart_mobile/services/publish_return_route_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 1, 12);
  final origin = GeoCoordinate(latitude: 41, longitude: 29);
  final destination = GeoCoordinate(latitude: 41.1, longitude: 29.1);

  DriverProfile profile(DriverProfileStatus status) => DriverProfile(
    id: 'driver-1',
    authUserId: 'user-1',
    status: status,
    createdAt: now.subtract(const Duration(days: 2)),
    approvedAt: status == DriverProfileStatus.pendingReview
        ? null
        : now.subtract(const Duration(days: 1)),
    suspendedAt: status == DriverProfileStatus.suspended
        ? now.subtract(const Duration(hours: 1))
        : null,
  );
  DriverAccessPass pass({DateTime? expires}) => DriverAccessPass(
    id: 'pass-1',
    driverId: 'driver-1',
    plan: DriverPassPlan.daily,
    status: DriverPassStatus.active,
    purchasedAt: now.subtract(const Duration(hours: 2)),
    activatedAt: now.subtract(const Duration(hours: 1)),
    expiresAt: expires ?? now.add(const Duration(hours: 2)),
  );
  PublishedReturnRoute published() {
    final route = DriverReturnRoute(
      id: 'route-1',
      driverId: 'driver-1',
      origin: origin,
      destination: destination,
      status: DriverReturnRouteStatus.active,
      createdAt: now,
      activatedAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      routeDistanceMeters: 12000,
      routeDurationSeconds: 1800,
      routePoints: [origin, destination],
    );
    return PublishedReturnRoute(route: route, encodedPolyline: 'encoded');
  }

  DriverCenterController controller({
    String? userId = 'user-1',
    DriverProfile? loadedProfile,
    DriverAccessPass? loadedPass,
    Object? profileError,
    PublishReturnRouteGateway? publisher,
  }) => DriverCenterController(
    auth: _Auth(userId),
    profiles: _Profiles(loadedProfile, profileError),
    passes: _Passes(loadedPass),
    publisher: publisher ?? _Publisher(published()),
    location: _Location(origin),
    now: () => now,
  );

  test('oturum yoksa authentication required olur', () async {
    final value = controller(userId: null);
    await value.load();
    expect(value.rejectionReason, 'authentication_required');
  });
  test('profil yoksa driver profile required olur', () async {
    final value = controller();
    await value.load();
    expect(value.rejectionReason, 'driver_profile_required');
  });
  final statuses = {
    DriverProfileStatus.pendingReview: 'driver_approval_required',
    DriverProfileStatus.suspended: 'driver_suspended',
    DriverProfileStatus.rejected: 'driver_rejected',
    DriverProfileStatus.deactivated: 'driver_deactivated',
  };
  for (final entry in statuses.entries) {
    test('${entry.key} doğru state üretir', () async {
      final value = controller(
        loadedProfile: profile(entry.key),
        loadedPass: pass(),
      );
      await value.load();
      expect(value.rejectionReason, entry.value);
    });
  }
  test('approved profil fakat pass yoksa subscription required', () async {
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
    );
    await value.load();
    expect(value.rejectionReason, 'subscription_required');
  });
  test('süresi bitmiş pass subscription required', () async {
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(expires: now),
    );
    await value.load();
    expect(value.rejectionReason, 'subscription_required');
  });
  test('approved profil ve aktif pass ready olur ve konumu alır', () async {
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
    );
    await value.load();
    expect(value.status, DriverCenterStatus.ready);
    expect(value.origin, origin);
  });
  test('repository exception error state olur', () async {
    final value = controller(profileError: StateError('failure'));
    await value.load();
    expect(value.status, DriverCenterStatus.error);
  });
  test('origin veya destination yoksa publish çağrılmaz', () async {
    final publisher = _Publisher(published());
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      publisher: publisher,
    );
    await value.publish();
    expect(publisher.calls, 0);
    await value.load();
    await value.publish();
    expect(publisher.calls, 0);
  });
  test('başarılı publish backend zamanlarını değiştirmeden saklanır', () async {
    final expected = published();
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      publisher: _Publisher(expected),
    );
    await value.load();
    value.selectDestination(destination, 'Ev');
    value.selectValidity(900);
    await value.publish();
    expect(value.publishedRoute, same(expected));
    expect(value.publishedRoute?.activatedAt, now);
  });
  test('eşzamanlı ikinci publish çağrısı engellenir', () async {
    final publisher = _DeferredPublisher();
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      publisher: publisher,
    );
    await value.load();
    value.selectDestination(destination, 'Ev');
    final first = value.publish();
    await value.publish();
    expect(publisher.calls, 1);
    publisher.completer.complete(published());
    await first;
  });
  test('backend reason güvenli kullanıcı mesajına çevrilir', () async {
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      publisher: _ErrorPublisher(
        const PublishReturnRouteException(
          code: 'failed-precondition',
          reason: 'active_return_route_exists',
        ),
      ),
    );
    await value.load();
    value.selectDestination(destination, 'Ev');
    await value.publish();
    expect(value.errorMessage, 'Zaten aktif bir dönüş rotanız bulunuyor.');
  });
  test('dispose sonrasında async tamamlanması hata üretmez', () async {
    final publisher = _DeferredPublisher();
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      publisher: publisher,
    );
    await value.load();
    value.selectDestination(destination, 'Ev');
    final operation = value.publish();
    value.dispose();
    publisher.completer.complete(published());
    await operation;
  });
}

class _Auth implements DriverCenterAuthGateway {
  final String? value;
  _Auth(this.value);
  @override
  String? get authenticatedUserId => value;
}

class _Profiles implements DriverProfileRepository {
  final DriverProfile? value;
  final Object? error;
  _Profiles(this.value, this.error);
  @override
  Future<DriverProfile?> findByAuthenticatedUserId(String id) async {
    if (error != null) throw error!;
    return value;
  }
}

class _Passes implements DriverAccessPassRepository {
  final DriverAccessPass? value;
  _Passes(this.value);
  @override
  Future<DriverAccessPass?> findLatestForDriver(String id) async => value;
}

class _Location implements DriverLocationGateway {
  final GeoCoordinate value;
  _Location(this.value);
  @override
  Future<GeoCoordinate> currentLocation() async => value;
}

class _Publisher implements PublishReturnRouteGateway {
  final PublishedReturnRoute value;
  int calls = 0;
  _Publisher(this.value);
  @override
  Future<PublishedReturnRoute> publish({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required int validForSeconds,
  }) async {
    calls++;
    return value;
  }
}

class _DeferredPublisher implements PublishReturnRouteGateway {
  final completer = Completer<PublishedReturnRoute>();
  int calls = 0;
  @override
  Future<PublishedReturnRoute> publish({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required int validForSeconds,
  }) {
    calls++;
    return completer.future;
  }
}

class _ErrorPublisher implements PublishReturnRouteGateway {
  final Object error;
  _ErrorPublisher(this.error);
  @override
  Future<PublishedReturnRoute> publish({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required int validForSeconds,
  }) async => throw error;
}
