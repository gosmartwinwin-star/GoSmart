import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/location/location_access_gateway.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_pass_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/application/return_route/publish_return_route_gateway.dart';
import 'package:gosmart_mobile/application/return_route/active_return_route_recovery_gateway.dart';
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
  PublishedReturnRoute published({
    String routeId = 'route-1',
    DateTime? expiresAt,
  }) {
    final route = DriverReturnRoute(
      id: routeId,
      driverId: 'driver-1',
      origin: origin,
      destination: destination,
      status: DriverReturnRouteStatus.active,
      createdAt: now,
      activatedAt: now,
      expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
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
    ActiveReturnRouteRecoveryGateway? recovery,
    Timer Function(Duration, void Function())? expiryTimerFactory,
    DateTime Function()? nowProvider,
    LocationAccessGateway? location,
  }) => DriverCenterController(
    auth: _Auth(userId),
    profiles: _Profiles(loadedProfile, profileError),
    passes: _Passes(loadedPass),
    publisher: publisher ?? _Publisher(published()),
    returnRouteRecovery: recovery,
    expiryTimerFactory:
        expiryTimerFactory ?? _ManualExpiryTimerFactory().create,
    location: location ?? _Location(origin),
    now: nowProvider ?? (() => now),
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
  test('service disabled typed location state', () async {
    final location = _IssueLocation(LocationAccessIssue.serviceDisabled);

    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      location: location,
    );

    await value.load();

    expect(value.status, DriverCenterStatus.ready);
    expect(value.origin, isNull);
    expect(value.locationIssue, LocationAccessIssue.serviceDisabled);
    expect(value.errorMessage, isNull);

    await value.handleLocationIssueAction();

    expect(location.locationSettingsCalls, 1);
    expect(location.appSettingsCalls, 0);
  });

  test('denied forever opens app settings', () async {
    final location = _IssueLocation(
      LocationAccessIssue.permissionDeniedForever,
    );

    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      location: location,
    );

    await value.load();
    await value.handleLocationIssueAction();

    expect(value.locationIssue, LocationAccessIssue.permissionDeniedForever);
    expect(location.appSettingsCalls, 1);
    expect(location.locationSettingsCalls, 0);
  });

  test('denied action retries location', () async {
    final location = _IssueLocation(LocationAccessIssue.permissionDenied);

    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      location: location,
    );

    await value.load();
    expect(location.currentCalls, 1);

    await value.handleLocationIssueAction();

    expect(location.currentCalls, 2);
  });

  test('raw location exception becomes unavailable', () async {
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      location: _ThrowingLocation(),
    );

    await value.load();

    expect(value.origin, isNull);
    expect(value.locationIssue, LocationAccessIssue.unavailable);
    expect(value.errorMessage, isNull);
  });
  test('ready load canonical active return route recovery yapar', () async {
    final expected = published();
    final recovery = _Recovery(expected);

    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      recovery: recovery,
    );

    await value.load();

    expect(value.status, DriverCenterStatus.ready);
    expect(value.publishedRoute, same(expected));
    expect(recovery.calls, 1);
  });

  test(
    'canonical route expiry tek seferlik timer ile stale state temizler',
    () async {
      final timerFactory = _ManualExpiryTimerFactory();
      var currentNow = now;
      final expected = published();
      final recovery = _Recovery(expected);

      final value = controller(
        loadedProfile: profile(DriverProfileStatus.approved),
        loadedPass: pass(),
        recovery: recovery,
        expiryTimerFactory: timerFactory.create,
        nowProvider: () => currentNow,
      );

      await value.load();

      expect(value.publishedRoute, same(expected));
      expect(timerFactory.created, 1);
      expect(timerFactory.lastDelay, const Duration(hours: 1));

      final timer = timerFactory.latest;
      expect(timer, isNotNull);
      expect(timer!.isActive, isTrue);

      currentNow = expected.expiresAt;
      timer.fire();

      expect(timer.isActive, isFalse);
      expect(value.publishedRoute, isNull);
      expect(recovery.calls, 1);
    },
  );

  test(
    'reload eski expiry timerini iptal eder ve yeni route timerini kurar',
    () async {
      final timerFactory = _ManualExpiryTimerFactory();
      var currentNow = now;
      final firstRoute = published(routeId: 'route-1');
      final secondRoute = published(
        routeId: 'route-2',
        expiresAt: now.add(const Duration(hours: 2)),
      );
      final recovery = _SequenceRecovery([firstRoute, secondRoute]);

      final value = controller(
        loadedProfile: profile(DriverProfileStatus.approved),
        loadedPass: pass(),
        recovery: recovery,
        expiryTimerFactory: timerFactory.create,
        nowProvider: () => currentNow,
      );

      await value.load();

      final firstTimer = timerFactory.latest;
      expect(firstTimer, isNotNull);
      expect(firstTimer!.isActive, isTrue);
      expect(value.publishedRoute?.routeId, 'route-1');

      await value.load();

      final secondTimer = timerFactory.latest;
      expect(recovery.calls, 2);
      expect(firstTimer.isActive, isFalse);
      expect(secondTimer, isNotNull);
      expect(identical(firstTimer, secondTimer), isFalse);
      expect(value.publishedRoute?.routeId, 'route-2');
      expect(timerFactory.lastDelay, const Duration(hours: 2));

      firstTimer.fire();
      expect(value.publishedRoute?.routeId, 'route-2');

      currentNow = secondRoute.expiresAt;
      secondTimer!.fire();
      expect(value.publishedRoute, isNull);
    },
  );

  test('dispose active route expiry timerini iptal eder', () async {
    final timerFactory = _ManualExpiryTimerFactory();

    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      recovery: _Recovery(published()),
      expiryTimerFactory: timerFactory.create,
    );

    await value.load();

    final timer = timerFactory.latest;
    expect(timer, isNotNull);
    expect(timer!.isActive, isTrue);

    value.dispose();

    expect(timer.isActive, isFalse);

    timer.fire();
  });
  test('canonical recovery null ise publish yüzeyi açık kalır', () async {
    final recovery = _Recovery(null);

    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      recovery: recovery,
    );

    await value.load();

    expect(value.status, DriverCenterStatus.ready);
    expect(value.publishedRoute, isNull);
    expect(value.errorMessage, isNull);
    expect(recovery.calls, 1);
  });

  test('recovery hatası fail closed error state üretir', () async {
    final recovery = _Recovery(null, error: StateError('RAW_RECOVERY_FAILURE'));

    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
      recovery: recovery,
    );

    await value.load();

    expect(value.status, DriverCenterStatus.error);
    expect(value.publishedRoute, isNull);
    expect(
      value.errorMessage,
      'Aktif dönüş rotası yüklenemedi. Lütfen tekrar deneyin.',
    );
    expect(value.origin, isNull);
    expect(recovery.calls, 1);
  });

  test('restricted sürücü için active route recovery çağrılmaz', () async {
    final recovery = _Recovery(published());

    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      recovery: recovery,
    );

    await value.load();

    expect(value.status, DriverCenterStatus.restricted);
    expect(value.rejectionReason, 'subscription_required');
    expect(recovery.calls, 0);
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

class _ManualExpiryTimerFactory {
  Duration? lastDelay;
  _ManualExpiryTimer? latest;
  int created = 0;

  Timer create(Duration delay, void Function() callback) {
    created++;
    lastDelay = delay;

    final timer = _ManualExpiryTimer(callback);
    latest = timer;

    return timer;
  }
}

class _ManualExpiryTimer implements Timer {
  _ManualExpiryTimer(this._callback);

  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) {
      return;
    }

    _active = false;
    _tick++;
    _callback();
  }

  @override
  void cancel() {
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

class _SequenceRecovery implements ActiveReturnRouteRecoveryGateway {
  _SequenceRecovery(this.values);

  final List<PublishedReturnRoute?> values;
  int calls = 0;

  @override
  Future<PublishedReturnRoute?> recover() async {
    if (calls >= values.length) {
      throw StateError('No recovery fixture remaining.');
    }

    final value = values[calls];
    calls++;

    return value;
  }
}

class _Recovery implements ActiveReturnRouteRecoveryGateway {
  _Recovery(this.value, {this.error});

  final PublishedReturnRoute? value;
  final Object? error;
  int calls = 0;

  @override
  Future<PublishedReturnRoute?> recover() async {
    calls++;

    final failure = error;

    if (failure != null) {
      throw failure;
    }

    return value;
  }
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

class _Location implements LocationAccessGateway {
  _Location(this.value);

  final GeoCoordinate value;

  @override
  Future<LocationAccessResult> currentLocation() async =>
      LocationAccessResult.granted(
        DeviceLocation(latitude: value.latitude, longitude: value.longitude),
      );

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _IssueLocation implements LocationAccessGateway {
  _IssueLocation(this.issue);

  final LocationAccessIssue issue;
  int currentCalls = 0;
  int appSettingsCalls = 0;
  int locationSettingsCalls = 0;

  @override
  Future<LocationAccessResult> currentLocation() async {
    currentCalls++;
    return LocationAccessResult.failed(issue);
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCalls++;
    return true;
  }
}

class _ThrowingLocation implements LocationAccessGateway {
  @override
  Future<LocationAccessResult> currentLocation() async {
    throw StateError('RAW_LOCATION_ERROR');
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
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
