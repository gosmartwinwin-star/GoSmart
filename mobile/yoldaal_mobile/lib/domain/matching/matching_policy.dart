class RouteDeviationResult {
  final int pickupDetourMeters;
  final int pickupDetourSeconds;
  final int dropoffDetourMeters;
  final int dropoffDetourSeconds;
  final int pickupRouteIndex;
  final int dropoffRouteIndex;

  RouteDeviationResult({
    required int pickupDetourMeters,
    required int pickupDetourSeconds,
    required int dropoffDetourMeters,
    required int dropoffDetourSeconds,
    required int pickupRouteIndex,
    required int dropoffRouteIndex,
  }) : pickupDetourMeters = _requireNonNegative(
         pickupDetourMeters,
         'pickupDetourMeters',
       ),
       pickupDetourSeconds = _requireNonNegative(
         pickupDetourSeconds,
         'pickupDetourSeconds',
       ),
       dropoffDetourMeters = _requireNonNegative(
         dropoffDetourMeters,
         'dropoffDetourMeters',
       ),
       dropoffDetourSeconds = _requireNonNegative(
         dropoffDetourSeconds,
         'dropoffDetourSeconds',
       ),
       pickupRouteIndex = _requireNonNegative(
         pickupRouteIndex,
         'pickupRouteIndex',
       ),
       dropoffRouteIndex = _requireNonNegative(
         dropoffRouteIndex,
         'dropoffRouteIndex',
       );

  int get totalDetourMeters => pickupDetourMeters + dropoffDetourMeters;

  int get totalExtraDurationSeconds =>
      pickupDetourSeconds + dropoffDetourSeconds;

  bool get pickupEligible =>
      pickupDetourMeters <= MatchingPolicy.maximumPickupDetourMeters &&
      pickupDetourSeconds <= MatchingPolicy.maximumPickupDetourSeconds;

  bool get dropoffEligible =>
      dropoffDetourMeters <= MatchingPolicy.maximumDropoffDetourMeters &&
      dropoffDetourSeconds <= MatchingPolicy.maximumDropoffDetourSeconds;

  bool get directionCompatible => pickupRouteIndex < dropoffRouteIndex;

  static int _requireNonNegative(int value, String name) {
    if (value < 0) {
      throw ArgumentError.value(value, name, 'Negatif olamaz.');
    }

    return value;
  }
}

class MatchingEvaluationResult {
  final bool subscriptionActive;
  final bool pickupEligible;
  final bool dropoffEligible;
  final bool directionCompatible;
  final bool isEligible;
  final List<String> rejectionReasons;

  MatchingEvaluationResult({
    required this.subscriptionActive,
    required this.pickupEligible,
    required this.dropoffEligible,
    required this.directionCompatible,
    required this.isEligible,
    required List<String> rejectionReasons,
  }) : rejectionReasons = List.unmodifiable(rejectionReasons);
}

class MatchingPolicy {
  static const int maximumPickupDetourMeters = 3000;
  static const int maximumPickupDetourSeconds = 600;
  static const int maximumDropoffDetourMeters = 3000;
  static const int maximumDropoffDetourSeconds = 600;

  static const double driverProfitRate = 0.07;
  static const int customerPlatformFee = 0;
  static const bool subscriptionRequired = true;

  static const String subscriptionRequiredReason = 'subscription_required';
  static const String pickupDistanceExceededReason = 'pickup_distance_exceeded';
  static const String pickupDurationExceededReason = 'pickup_duration_exceeded';
  static const String dropoffDistanceExceededReason =
      'dropoff_distance_exceeded';
  static const String dropoffDurationExceededReason =
      'dropoff_duration_exceeded';
  static const String incompatibleDirectionReason = 'incompatible_direction';

  const MatchingPolicy();

  MatchingEvaluationResult evaluate({
    required bool subscriptionActive,
    required RouteDeviationResult deviation,
  }) {
    final rejectionReasons = <String>[];

    if (subscriptionRequired && !subscriptionActive) {
      rejectionReasons.add(subscriptionRequiredReason);
    }
    if (deviation.pickupDetourMeters > maximumPickupDetourMeters) {
      rejectionReasons.add(pickupDistanceExceededReason);
    }
    if (deviation.pickupDetourSeconds > maximumPickupDetourSeconds) {
      rejectionReasons.add(pickupDurationExceededReason);
    }
    if (deviation.dropoffDetourMeters > maximumDropoffDetourMeters) {
      rejectionReasons.add(dropoffDistanceExceededReason);
    }
    if (deviation.dropoffDetourSeconds > maximumDropoffDetourSeconds) {
      rejectionReasons.add(dropoffDurationExceededReason);
    }
    if (!deviation.directionCompatible) {
      rejectionReasons.add(incompatibleDirectionReason);
    }

    final isEligible =
        subscriptionActive &&
        deviation.pickupEligible &&
        deviation.dropoffEligible &&
        deviation.directionCompatible;

    return MatchingEvaluationResult(
      subscriptionActive: subscriptionActive,
      pickupEligible: deviation.pickupEligible,
      dropoffEligible: deviation.dropoffEligible,
      directionCompatible: deviation.directionCompatible,
      isEligible: isEligible,
      rejectionReasons: rejectionReasons,
    );
  }
}
