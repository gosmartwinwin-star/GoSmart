import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_mode_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_pass_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/application/location/location_access_gateway.dart';
import 'package:gosmart_mobile/application/return_route/publish_return_route_gateway.dart';
import 'package:gosmart_mobile/application/return_route/published_return_route.dart';
import 'package:gosmart_mobile/controllers/driver_center_controller.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_mode.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 19);
  final origin = GeoCoordinate(latitude: 41.01, longitude: 28.97);

  DriverProfile profile({
    DriverProfileStatus status = DriverProfileStatus.approved,
  }) {
    return DriverProfile(
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
  }

  Future<({DriverCenterController controller, _Modes modes, _Passes passes})>
  load({
    DriverAccessMode mode = DriverAccessMode.paid,
    Object? modeError,
    DriverProfile? loadedProfile,
    DriverAccessPass? loadedPass,
  }) async {
    final modes = _Modes(mode, error: modeError);
    final passes = _Passes(loadedPass);

    final controller = DriverCenterController(
      auth: const _Auth('user-1'),
      profiles: _Profiles(loadedProfile ?? profile()),
      passes: passes,
      accessModes: modes,
      publisher: const _Publisher(),
      location: _Location(origin),
      now: () => now,
    );

    addTearDown(controller.dispose);

    await controller.load();

    return (controller: controller, modes: modes, passes: passes);
  }

  test('launchFree approved driver skips pass repository', () async {
    final result = await load(mode: DriverAccessMode.launchFree);

    expect(result.controller.status, DriverCenterStatus.ready);
    expect(result.controller.accessMode, DriverAccessMode.launchFree);
    expect(result.controller.rejectionReason, isNull);
    expect(result.modes.calls, 1);
    expect(result.passes.calls, 0);
  });

  test('paid approved driver without pass remains restricted', () async {
    final result = await load();

    expect(result.controller.status, DriverCenterStatus.restricted);
    expect(result.controller.accessMode, DriverAccessMode.paid);
    expect(result.controller.rejectionReason, 'subscription_required');
    expect(result.modes.calls, 1);
    expect(result.passes.calls, 1);
  });

  test('mode repository failure fails closed to paid', () async {
    final result = await load(
      mode: DriverAccessMode.launchFree,
      modeError: StateError('MODE_LOOKUP_FAILED'),
    );

    expect(result.controller.status, DriverCenterStatus.restricted);
    expect(result.controller.accessMode, DriverAccessMode.paid);
    expect(result.controller.rejectionReason, 'subscription_required');
    expect(result.modes.calls, 1);
    expect(result.passes.calls, 1);
  });

  test('launchFree does not bypass driver approval', () async {
    final result = await load(
      mode: DriverAccessMode.launchFree,
      loadedProfile: profile(status: DriverProfileStatus.suspended),
    );

    expect(result.controller.status, DriverCenterStatus.restricted);
    expect(result.controller.accessMode, DriverAccessMode.launchFree);
    expect(result.controller.rejectionReason, 'driver_suspended');
    expect(result.passes.calls, 0);
  });
}

class _Auth implements DriverCenterAuthGateway {
  const _Auth(this.value);

  final String? value;

  @override
  String? get authenticatedUserId => value;
}

class _Profiles implements DriverProfileRepository {
  const _Profiles(this.value);

  final DriverProfile? value;

  @override
  Future<DriverProfile?> findByAuthenticatedUserId(
    String authenticatedUserId,
  ) async {
    return value;
  }
}

class _Passes implements DriverAccessPassRepository {
  _Passes(this.value);

  final DriverAccessPass? value;
  int calls = 0;

  @override
  Future<DriverAccessPass?> findLatestForDriver(String driverId) async {
    calls++;
    return value;
  }
}

class _Modes implements DriverAccessModeRepository {
  _Modes(this.value, {this.error});

  final DriverAccessMode value;
  final Object? error;
  int calls = 0;

  @override
  Future<DriverAccessMode> load() async {
    calls++;

    final failure = error;
    if (failure != null) {
      throw failure;
    }

    return value;
  }
}

class _Location implements LocationAccessGateway {
  const _Location(this.value);

  final GeoCoordinate value;

  @override
  Future<LocationAccessResult> currentLocation() async {
    return LocationAccessResult.granted(
      DeviceLocation(latitude: value.latitude, longitude: value.longitude),
    );
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _Publisher implements PublishReturnRouteGateway {
  const _Publisher();

  @override
  Future<PublishedReturnRoute> publish({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required int validForSeconds,
  }) {
    throw UnimplementedError();
  }
}
