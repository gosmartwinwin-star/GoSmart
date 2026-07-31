import '../../domain/driver/driver_eligibility_rejection_codes.dart';

abstract final class MatchOrchestrationRejectionCodes {
  static const String subscriptionRequired =
      DriverEligibilityRejectionCodes.subscriptionRequired;
  static const String driverIdentityMismatch =
      DriverEligibilityRejectionCodes.driverIdentityMismatch;
  static const String returnRouteNotCalculated = 'return_route_not_calculated';
  static const String returnRouteInactive = 'return_route_inactive';
  static const String returnRouteExpired = 'return_route_expired';
}
