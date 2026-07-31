import '../../domain/matching/matching_policy.dart';
import '../../domain/return_route/driver_return_route.dart';
import '../../domain/return_route/driver_return_route_policy.dart';
import '../../domain/return_route/geo_coordinate.dart';
import '../../domain/return_route/route_anchor_locator.dart';
import '../../domain/subscription/driver_access_pass.dart';
import '../../domain/subscription/driver_access_policy.dart';
import 'match_orchestration_rejection_codes.dart';
import 'return_route_match_result.dart';
import 'route_deviation_gateway.dart';

class ReturnRouteMatchOrchestrator {
  final DriverAccessPolicy _accessPolicy;
  final DriverReturnRoutePolicy _returnRoutePolicy;
  final RouteAnchorLocator _anchorLocator;
  final RouteDeviationGateway _deviationGateway;
  final MatchingPolicy _matchingPolicy;

  ReturnRouteMatchOrchestrator({
    required RouteDeviationGateway deviationGateway,
    DriverAccessPolicy accessPolicy = const DriverAccessPolicy(),
    DriverReturnRoutePolicy returnRoutePolicy = const DriverReturnRoutePolicy(),
    RouteAnchorLocator anchorLocator = const RouteAnchorLocator(),
    MatchingPolicy matchingPolicy = const MatchingPolicy(),
  }) : _accessPolicy = accessPolicy,
       _returnRoutePolicy = returnRoutePolicy,
       _anchorLocator = anchorLocator,
       _deviationGateway = deviationGateway,
       _matchingPolicy = matchingPolicy;

  Future<ReturnRouteMatchResult> evaluate({
    required DriverAccessPass? pass,
    required DriverReturnRoute returnRoute,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
    required DateTime now,
  }) async {
    final subscriptionActive = _accessPolicy.canStartNewMatch(
      pass: pass,
      now: now,
    );
    if (!subscriptionActive) {
      return ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: false,
        driverIdentityCompatible: false,
        returnRouteReady: false,
        rejectionReasons: const [
          MatchOrchestrationRejectionCodes.subscriptionRequired,
        ],
      );
    }

    final driverIdentityCompatible = pass!.driverId == returnRoute.driverId;
    if (!driverIdentityCompatible) {
      return ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: true,
        driverIdentityCompatible: false,
        returnRouteReady: false,
        rejectionReasons: const [
          MatchOrchestrationRejectionCodes.driverIdentityMismatch,
        ],
      );
    }

    if (!returnRoute.hasCalculatedRoute) {
      return ReturnRouteMatchResult.rejectedBeforeMeasurement(
        subscriptionActive: true,
        driverIdentityCompatible: true,
        returnRouteReady: false,
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
      anchors: anchors,
      deviation: deviation,
      matchingEvaluation: matchingEvaluation,
    );
  }
}
