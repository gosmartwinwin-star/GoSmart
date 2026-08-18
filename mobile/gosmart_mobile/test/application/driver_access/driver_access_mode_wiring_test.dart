import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_context.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_context_service.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_mode_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_pass_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/application/matching/match_orchestration_rejection_codes.dart';
import 'package:gosmart_mobile/application/matching/return_route_match_orchestrator.dart';
import 'package:gosmart_mobile/application/matching/route_deviation_gateway.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/matching/matching_policy.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/return_route/route_anchor_result.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_mode.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 19, 30);
  final pickup = GeoCoordinate(latitude: 41.00, longitude: 29.00);
  final dropoff = GeoCoordinate(latitude: 41.02, longitude: 29.02);

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

  DriverReturnRoute expiredRoute() {
    return DriverReturnRoute(
      id: 'route-1',
      driverId: 'driver-1',
      origin: pickup,
      destination: dropoff,
      status: DriverReturnRouteStatus.active,
      createdAt: now.subtract(const Duration(hours: 2)),
      activatedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now,
      routeDistanceMeters: 10000,
      routeDurationSeconds: 1200,
      routePoints: [pickup, dropoff],
    );
  }

  Future<({DriverAccessContext context, _Modes modes, _Passes passes})>
  loadContext({
    DriverAccessMode mode = DriverAccessMode.paid,
    Object? modeError,
    DriverProfile? loadedProfile,
  }) async {
    final modes = _Modes(mode, error: modeError);
    final passes = _Passes();

    final context =
        await DriverAccessContextService(
          profileRepository: _Profiles(loadedProfile ?? profile()),
          passRepository: passes,
          modeRepository: modes,
        ).load(
          authenticatedUserId: 'user-1',
          requiredDriverId: 'driver-1',
          now: now,
        );

    return (context: context, modes: modes, passes: passes);
  }

  test(
    'context launchFree skips pass lookup and grants approved access',
    () async {
      final result = await loadContext(mode: DriverAccessMode.launchFree);

      expect(result.context.accessMode, DriverAccessMode.launchFree);
      expect(result.context.pass, isNull);
      expect(result.context.canUseDriverPlatform, isTrue);
      expect(result.context.eligibility.subscriptionActive, isTrue);
      expect(result.modes.calls, 1);
      expect(result.passes.calls, 0);
    },
  );

  test('context mode failure falls back to paid', () async {
    final result = await loadContext(
      mode: DriverAccessMode.launchFree,
      modeError: StateError('MODE_LOOKUP_FAILED'),
    );

    expect(result.context.accessMode, DriverAccessMode.paid);
    expect(result.context.canUseDriverPlatform, isFalse);
    expect(result.context.eligibility.rejectionReasons, [
      'subscription_required',
    ]);
    expect(result.modes.calls, 1);
    expect(result.passes.calls, 1);
  });

  test('orchestrator launchFree advances beyond subscription gate', () async {
    final gateway = _DeviationGateway();

    final result = await ReturnRouteMatchOrchestrator(deviationGateway: gateway)
        .evaluate(
          authenticatedUserId: 'user-1',
          driverProfile: profile(),
          pass: null,
          accessMode: DriverAccessMode.launchFree,
          returnRoute: expiredRoute(),
          pickup: pickup,
          dropoff: dropoff,
          now: now,
        );

    expect(result.subscriptionActive, isTrue);
    expect(result.rejectionReasons, [
      MatchOrchestrationRejectionCodes.returnRouteExpired,
    ]);
    expect(
      result.rejectionReasons,
      isNot(contains(MatchOrchestrationRejectionCodes.subscriptionRequired)),
    );
    expect(gateway.calls, 0);
  });

  test('orchestrator default remains paid', () async {
    final gateway = _DeviationGateway();

    final result = await ReturnRouteMatchOrchestrator(deviationGateway: gateway)
        .evaluate(
          authenticatedUserId: 'user-1',
          driverProfile: profile(),
          pass: null,
          returnRoute: expiredRoute(),
          pickup: pickup,
          dropoff: dropoff,
          now: now,
        );

    expect(result.subscriptionActive, isFalse);
    expect(result.rejectionReasons, [
      MatchOrchestrationRejectionCodes.subscriptionRequired,
    ]);
    expect(gateway.calls, 0);
  });

  test('orchestrator launchFree does not bypass suspension', () async {
    final gateway = _DeviationGateway();

    final result = await ReturnRouteMatchOrchestrator(deviationGateway: gateway)
        .evaluate(
          authenticatedUserId: 'user-1',
          driverProfile: profile(status: DriverProfileStatus.suspended),
          pass: null,
          accessMode: DriverAccessMode.launchFree,
          returnRoute: expiredRoute(),
          pickup: pickup,
          dropoff: dropoff,
          now: now,
        );

    expect(result.rejectionReasons, ['driver_suspended']);
    expect(gateway.calls, 0);
  });
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
  int calls = 0;

  @override
  Future<DriverAccessPass?> findLatestForDriver(String driverId) async {
    calls++;
    return null;
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

class _DeviationGateway implements RouteDeviationGateway {
  int calls = 0;

  @override
  Future<RouteDeviationResult> compute({
    required RouteAnchorResult anchors,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
  }) async {
    calls++;

    return RouteDeviationResult(
      pickupDetourMeters: 1000,
      pickupDetourSeconds: 200,
      dropoffDetourMeters: 1000,
      dropoffDetourSeconds: 200,
      pickupRouteIndex: anchors.pickupRouteIndex,
      dropoffRouteIndex: anchors.dropoffRouteIndex,
    );
  }
}
