import '../../domain/driver/driver_eligibility_policy.dart';
import '../../domain/driver/driver_profile.dart';
import '../../domain/matching/matching_policy.dart';
import '../../domain/return_route/driver_return_route.dart';
import '../../domain/return_route/driver_return_route_policy.dart';
import '../../domain/return_route/geo_coordinate.dart';
import '../../domain/return_route/route_anchor_locator.dart';
import '../../domain/subscription/driver_access_mode.dart';
import '../../domain/subscription/driver_access_pass.dart';
import 'match_orchestration_rejection_codes.dart';
import 'return_route_match_result.dart';
import 'route_deviation_gateway.dart';

class ReturnRouteMatchOrchestrator {
  final DriverEligibilityPolicy _driverEligibilityPolicy;
  final DriverReturnRoutePolicy _returnRoutePolicy;
  final RouteAnchorLocator _anchorLocator;
  final RouteDeviationGateway _deviationGateway;
  final MatchingPolicy _matchingPolicy;

  ReturnRouteMatchOrchestrator({
    required RouteDeviationGateway deviationGateway,
    DriverEligibilityPolicy driverEligibilityPolicy =
        const DriverEligibilityPolicy(),
    DriverReturnRoutePolicy returnRoutePolicy = const DriverReturnRoutePolicy(),
    RouteAnchorLocator anchorLocator = const RouteAnchorLocator(),
    MatchingPolicy matchingPolicy = const MatchingPolicy(),
  }) : _driverEligibilityPolicy = driverEligibilityPolicy,
       _returnRoutePolicy = returnRoutePolicy,
       _anchorLocator = anchorLocator,
       _deviationGateway = deviationGateway,
       _matchingPolicy = matchingPolicy;

  Future<ReturnRouteMatchResult> evaluate({
    required String? authenticatedUserId,
    required DriverProfile? driverProfile,
    required DriverAccessPass? pass,
    DriverAccessMode accessMode = DriverAccessMode.paid,
    required DriverReturnRoute returnRoute,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
    required DateTime now,
  }) async {
    final driverEligibility = _driverEligibilityPolicy.evaluate(
      authenticatedUserId: authenticatedUserId,
      profile: driverProfile,
      pass: pass,
      accessMode: accessMode,
      requiredDriverId: returnRoute.driverId,
      now: now,
    );
    if (!driverEligibility.canUseDriverPlatform) {
      return ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: driverEligibility.subscriptionActive,
        driverIdentityCompatible: driverEligibility.identityCompatible,
        returnRouteReady: false,
        driverEligibility: driverEligibility,
        rejectionReasons: driverEligibility.rejectionReasons,
      );
    }

    if (!returnRoute.hasCalculatedRoute) {
      return ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: true,
        driverIdentityCompatible: true,
        returnRouteReady: false,
        driverEligibility: driverEligibility,
        rejectionReasons: const [
          MatchOrchestrationRejectionCodes.returnRouteNotCalculated,
        ],
      );
    }

    final expiresAt = returnRoute.expiresAt;
    if (expiresAt != null && !now.isBefore(expiresAt)) {
      return ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: true,
        driverIdentityCompatible: true,
        returnRouteReady: false,
        driverEligibility: driverEligibility,
        rejectionReasons: const [
          MatchOrchestrationRejectionCodes.returnRouteExpired,
        ],
      );
    }

    final canReceiveMatches = _returnRoutePolicy.canReceiveMatches(
      route: returnRoute,
      subscriptionActive: true,
      now: now,
    );
    if (!canReceiveMatches) {
      return ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: true,
        driverIdentityCompatible: true,
        returnRouteReady: false,
        driverEligibility: driverEligibility,
        rejectionReasons: const [
          MatchOrchestrationRejectionCodes.returnRouteInactive,
        ],
      );
    }

    final anchors = _anchorLocator.locate(
      route: returnRoute,
      pickup: pickup,
      dropoff: dropoff,
    );
    if (!anchors.directionCompatible) {
      return ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: true,
        driverIdentityCompatible: true,
        returnRouteReady: true,
        anchors: anchors,
        driverEligibility: driverEligibility,
        rejectionReasons: const [MatchingPolicy.incompatibleDirectionReason],
      );
    }

    final deviation = await _deviationGateway.compute(
      anchors: anchors,
      pickup: pickup,
      dropoff: dropoff,
    );
    if (deviation.pickupRouteIndex != anchors.pickupRouteIndex ||
        deviation.dropoffRouteIndex != anchors.dropoffRouteIndex) {
      throw StateError('Sürüş sapması rota indeksleri anchorlarla uyuşmuyor.');
    }

    final matchingEvaluation = _matchingPolicy.evaluate(
      subscriptionActive: true,
      deviation: deviation,
    );

    return ReturnRouteMatchResult.evaluated(
      driverEligibility: driverEligibility,
      anchors: anchors,
      deviation: deviation,
      matchingEvaluation: matchingEvaluation,
    );
  }
}
